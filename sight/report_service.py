#!/usr/bin/env python3
"""WinRTCS report service v4 + Sight console.

v3 endpoints unchanged (fleet agents). New:
  GET  /sight          — operator dashboard (HTML)
  GET  /api/fleet     — JSON fleet truth (admin)
  GET  /api/jobs      — job catalog (admin)
  POST /api/jobs      — queue named job (admin)
  POST /api/cmd       — raw command (admin)  [same as /cmd]
  GET  /api/cmds      — command + result history (admin)
  GET  /api/cmd/<id>  — one command + full outputs (admin)
  GET  /api/policy    — RMM/SC policy list (admin)
  POST /api/policy    — add/update policy (admin)
  DELETE /api/policy  — remove policy (admin)
  POST /api/rmm/kick  — queue kick for tool/fp on host|ALL (admin)
"""
from __future__ import annotations

import html
import json
import re
import sqlite3
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE = Path("/opt/winrtcs")
STATIC = BASE / "static"
DB = str(BASE / "fleet.db")
TOKEN = (BASE / "fetch_token").read_text().strip()
ADMIN = (BASE / "admin_token").read_text().strip()
TG = json.loads((BASE / "tg.json").read_text())

# Import job catalog from same directory (deployed beside this file).
sys.path.insert(0, str(BASE))
from jobs_catalog import JOBS, catalog_public, render_job  # noqa: E402

SILENCE_SECS = 26 * 3600
ONLINE_SECS = 4 * 3600  # guard digests ~every 3h
SILENCE_RESEND = 20 * 3600
CMD_MAX_AGE = 24 * 3600
FLUSH_SECS = 120
TG_CHUNK = 3900

_queue: list[str] = []
_lock = threading.Lock()


def db() -> sqlite3.Connection:
    c = sqlite3.connect(DB)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute(
        """CREATE TABLE IF NOT EXISTS hosts(
        host TEXT PRIMARY KEY, state TEXT, streak INTEGER, extkill INTEGER,
        guard TEXT, siege TEXT, suspects TEXT, rmm TEXT, last_seen REAL,
        last_alert REAL DEFAULT 0)"""
    )
    try:
        c.execute("ALTER TABLE hosts ADD COLUMN rmm TEXT")
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
        params TEXT, cmd_id INTEGER, note TEXT)"""
    )
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
    mode = re.search(r"mode=(\S+)", seg)
    ver = re.search(r"ver=(\S*)", seg)
    tag = re.search(r"\[(\S+?)\]", seg)
    state = re.search(r"state=(\S+)", seg)
    start = re.search(r"start=(\S+)", seg)
    tagv = tag.group(1) if tag else "UNKNOWN"
    icon = {"gryxa": "🛰", "keeper-sevrz": "🔒"}.get(tagv, "⚠️")
    taglabel = {"gryxa": "gryxa (ours)", "keeper-sevrz": "keeper · sevrz"}.get(
        tagv, "❓ UNKNOWN"
    )
    return "\n".join(
        [
            f"{icon} <b>ScreenConnect</b> · {taglabel}",
            f"   🔑 FP: <code>{esc(fp.group(1) if fp else '?')}</code>",
            f"   🌐 Relay: <code>{esc(relay.group(1) if relay else '?')}</code>",
            f"   ⚙️ {esc(state.group(1) if state else '?')} · "
            f"{esc(start.group(1) if start else '?')} · "
            f"v{esc(ver.group(1) if ver and ver.group(1) else '?')} · "
            f"{esc(mode.group(1) if mode else '?')}",
        ]
    )


def _fmt_generic_segment(seg: str) -> str:
    name = seg.split(" ", 1)[0]
    svc = re.search(r"svc=(\S+)", seg)
    proc = re.search(r"proc=(\S+)", seg)
    state = re.search(r"state=(\S+)", seg)
    ver = re.search(r"ver=(\S*)", seg)
    path = re.search(r":: (.+)$", seg)
    how = (
        f"svc <code>{esc(svc.group(1))}</code>"
        if svc
        else (f"proc <code>{esc(proc.group(1))}</code>" if proc else "")
    )
    lines = [
        f"📡 <b>{esc(name)}</b>",
        f"   ⚙️ {how} · {esc(state.group(1) if state else '?')} · "
        f"v{esc(ver.group(1) if ver and ver.group(1) else '?')}",
    ]
    if path:
        lines.append(f"   📁 <code>{esc(path.group(1))}</code>")
    return "\n".join(lines)


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
        f"<pre>{esc(out)}</pre>\n"
        f"🕐 {utcnow()}"
    )


def classify_presence(last_seen: float, now: float) -> str:
    age = now - (last_seen or 0)
    if age <= ONLINE_SECS:
        return "online"
    if age <= SILENCE_SECS:
        return "stale"
    return "silent"


def parse_rmm(rmm: str) -> list[dict]:
    """Split compact rmm.top style field into structured entries."""
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


def queue_cmd(target: str, cmd: str, job_name: str = "", params: dict | None = None) -> int:
    con = db()
    cur = con.execute(
        "INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)",
        (time.time(), target[:64], cmd[:4000]),
    )
    cid = int(cur.lastrowid)
    if job_name:
        con.execute(
            "INSERT INTO jobs(ts,name,target,params,cmd_id,note) VALUES(?,?,?,?,?,?)",
            (
                time.time(),
                job_name[:64],
                target[:64],
                json.dumps(params or {}),
                cid,
                "",
            ),
        )
    con.commit()
    con.close()
    return cid


def fleet_payload() -> dict:
    con = db()
    rows = con.execute(
        "SELECT host,state,streak,extkill,guard,siege,suspects,rmm,last_seen FROM hosts ORDER BY host"
    ).fetchall()
    # last failed / last cmd per host
    last_res = con.execute(
        """SELECT r.host, r.cmd_id, r.rc, r.ts, c.cmd FROM results r
           JOIN cmds c ON c.id=r.cmd_id
           ORDER BY r.ts DESC"""
    ).fetchall()
    con.close()
    last_by_host: dict[str, dict] = {}
    for host, cid, rc, ts, cmd in last_res:
        if host not in last_by_host:
            last_by_host[host] = {
                "cmd_id": cid,
                "rc": rc,
                "ts": ts,
                "cmd": (cmd or "")[:120],
                "failed": rc.strip() not in ("RC=0", "0") and "timeout" not in (rc or "").lower(),
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
    }
    for h, state, streak, extkill, guard, siege, suspects, rmm, ts in rows:
        counts["total"] += 1
        presence = classify_presence(ts or 0, now)
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
        entries = parse_rmm(rmm or "")
        nonkeeper = [
            e
            for e in entries
            if e["tag"] not in ("gryxa", "keeper-sevrz") and e["raw"] not in ("none",)
        ]
        if nonkeeper:
            counts["nonkeeper_rmm"] += 1
        ago = int((now - (ts or 0)) / 60)
        seen = (
            f"{ago}m ago"
            if ago < 90
            else (f"{ago/60:.1f}h ago" if ago < 2880 else f"{ago/1440:.1f}d ago")
        )
        hosts.append(
            {
                "host": h,
                "state": state,
                "streak": streak,
                "extkill": extkill,
                "guard": guard,
                "siege": siege or "",
                "suspects": suspects or "",
                "rmm": rmm or "",
                "rmm_entries": entries,
                "nonkeeper": nonkeeper,
                "last_seen": ts,
                "seen": seen,
                "presence": presence,
                "last_cmd": last_by_host.get(h),
            }
        )
    return {"generated": now, "counts": counts, "hosts": hosts, "jobs": catalog_public()}


class H(BaseHTTPRequestHandler):
    def _auth(self, admin: bool = False) -> bool:
        want = "Bearer " + (ADMIN if admin else TOKEN)
        if self.headers.get("Authorization") != want:
            self.send_response(403)
            self.end_headers()
            return False
        return True

    def _text(self, body: str, code: int = 200, ctype: str = "text/plain; charset=utf-8") -> None:
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data if isinstance(data, bytes) else data.encode())

    def _json(self, obj: object, code: int = 200) -> None:
        self._text(json.dumps(obj), code, "application/json; charset=utf-8")

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
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    # ------------------------------------------------------------ post
    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/report":
            return self._post_report() if self._auth() else None
        if path == "/cmd" or path == "/api/cmd":
            return self._post_cmd() if self._auth(admin=True) else None
        if path == "/cmd/result":
            return self._post_result() if self._auth() else None
        if path == "/api/jobs":
            return self._post_job() if self._auth(admin=True) else None
        if path == "/api/policy":
            return self._post_policy() if self._auth(admin=True) else None
        if path == "/api/rmm/kick":
            return self._post_rmm_kick() if self._auth(admin=True) else None
        self._text("not found", 404)

    def do_DELETE(self) -> None:
        path, _, qs = self.path.partition("?")
        if path == "/api/policy":
            return self._del_policy(urllib.parse.parse_qs(qs)) if self._auth(admin=True) else None
        self._text("not found", 404)

    def _post_report(self) -> None:
        f = self._fields()
        host = f.get("host", "?")[:64]
        state = f.get("state", "?")[:64]
        rmm = f.get("rmm", "")[:500]
        rmm_new = f.get("rmm_new", "").strip()
        now = time.time()
        con = db()
        row = con.execute("SELECT state FROM hosts WHERE host=?", (host,)).fetchone()
        old = row[0] if row else None
        con.execute(
            """INSERT INTO hosts(host,state,streak,extkill,guard,siege,suspects,rmm,last_seen)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(host) DO UPDATE SET state=excluded.state, streak=excluded.streak,
            extkill=excluded.extkill, guard=excluded.guard, siege=excluded.siege,
            suspects=excluded.suspects, rmm=excluded.rmm, last_seen=excluded.last_seen""",
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
            ),
        )
        con.commit()
        con.close()
        if old is None:
            alert(fmt_new_host(host, state, f.get("guard", "?")))
        elif old != state:
            alert(fmt_state(host, old, state, f))
        if rmm_new:
            alert(fmt_rmm(host, rmm_new[:2500]))
        self._text("ok")

    def _post_cmd(self) -> None:
        f = self._fields()
        target = str(f.get("target", "")).strip()[:64]
        cmd = str(f.get("cmd", "")).strip()[:4000]
        if not target or not cmd:
            return self._json({"error": "need target + cmd"}, 400)
        cid = queue_cmd(target, cmd)
        audit("admin", "raw_cmd", f"id={cid} target={target}")
        if self.path.startswith("/api/"):
            return self._json({"queued": cid, "target": target})
        self._text(f"queued id={cid} target={target}")

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
        con = db()
        con.execute(
            "INSERT OR REPLACE INTO results(cmd_id,host,ts,rc,out) VALUES(?,?,?,?,?)",
            (cid, host, time.time(), rc, out),
        )
        con.commit()
        con.close()
        alert(fmt_cmd_result(host, cid, rc, out))
        self._text("ok")

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
        if not name or not target:
            return self._json({"error": "need name + target"}, 400)
        if name not in JOBS:
            return self._json({"error": f"unknown job {name}", "jobs": list(JOBS)}, 400)
        try:
            body = render_job(name, params if isinstance(params, dict) else {})
        except (ValueError, KeyError) as exc:
            return self._json({"error": str(exc)}, 400)
        cid = queue_cmd(target, body, job_name=name, params=params if isinstance(params, dict) else {})
        audit("admin", "job", f"{name} -> {target} cmd={cid}")
        alert(
            f"🛠 <b>JOB QUEUED</b>\n━━━━━━━━━━━━━━━━\n"
            f"📦 <code>{esc(name)}</code> → <code>{esc(target)}</code>\n"
            f"🆔 cmd #{cid}\n🕐 {utcnow()}"
        )
        self._json({"queued": cid, "job": name, "target": target})

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
        if not pid:
            return self._json({"error": "id required"}, 400)
        con = db()
        con.execute("DELETE FROM policy WHERE id=?", (pid,))
        con.commit()
        con.close()
        audit("admin", "policy_del", f"id={pid}")
        self._json({"ok": True})

    def _post_rmm_kick(self) -> None:
        f = self._fields()
        target = str(f.get("target", "")).strip()[:64]
        fp = str(f.get("fp", "")).strip().lower()
        mode = str(f.get("mode", "unknown-sc")).strip()
        if not target:
            return self._json({"error": "need target"}, 400)
        if mode == "fp" or fp:
            try:
                body = render_job("kick-sc-fp", {"fp": fp})
                name = "kick-sc-fp"
            except ValueError as exc:
                return self._json({"error": str(exc)}, 400)
        else:
            body = render_job("kick-unknown-sc")
            name = "kick-unknown-sc"
        cid = queue_cmd(target, body, job_name=name, params={"fp": fp})
        audit("admin", "rmm_kick", f"{name} -> {target} cmd={cid}")
        self._json({"queued": cid, "job": name, "target": target})

    # ------------------------------------------------------------ get
    def do_GET(self) -> None:
        path, _, qs = self.path.partition("?")
        q = urllib.parse.parse_qs(qs)
        if path in ("/sight", "/sight/", "/sight/index.html"):
            return self._sight()
        if path.startswith("/sight/static/"):
            return self._static(path[len("/sight/static/") :])
        if path == "/api/fleet":
            return self._json(fleet_payload()) if self._auth(admin=True) else None
        if path == "/api/jobs":
            return self._json({"jobs": catalog_public()}) if self._auth(admin=True) else None
        if path == "/api/cmds" or path == "/cmd/list":
            if not self._auth(admin=True):
                return None
            return self._api_cmds() if path.startswith("/api/") else self._get_cmdlist()
        if path.startswith("/api/cmd/"):
            if not self._auth(admin=True):
                return None
            try:
                cid = int(path.rsplit("/", 1)[-1])
            except ValueError:
                return self._json({"error": "bad id"}, 400)
            return self._api_cmd_detail(cid)
        if path == "/api/policy":
            return self._api_policy() if self._auth(admin=True) else None
        if path == "/api/audit":
            return self._api_audit() if self._auth(admin=True) else None
        if path == "/map":
            return self._get_map() if self._auth() else None
        if path == "/cmd/poll":
            return self._get_poll(q) if self._auth() else None
        if path == "/cmd/get":
            return self._get_cmd(q) if self._auth() else None
        self._text("not found", 404)

    def _sight(self) -> None:
        p = STATIC / "index.html"
        if not p.is_file():
            return self._text("sight UI missing — deploy static/index.html", 500)
        self._text(p.read_text(encoding="utf-8"), 200, "text/html; charset=utf-8")

    def _static(self, rel: str) -> None:
        rel = rel.replace("..", "").lstrip("/")
        p = STATIC / rel
        if not p.is_file():
            return self._text("missing", 404)
        ctype = "application/octet-stream"
        if rel.endswith(".css"):
            ctype = "text/css; charset=utf-8"
        elif rel.endswith(".js"):
            ctype = "application/javascript; charset=utf-8"
        elif rel.endswith(".svg"):
            ctype = "image/svg+xml"
        self._text(p.read_bytes(), 200, ctype)

    def _api_cmds(self) -> None:
        con = db()
        cmds = con.execute(
            "SELECT id, ts, target, cmd FROM cmds ORDER BY id DESC LIMIT 40"
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
        out = []
        for cid, ts, target, cmd in cmds:
            out.append(
                {
                    "id": cid,
                    "ts": ts,
                    "target": target,
                    "cmd": cmd[:200],
                    "job": jobs.get(cid),
                    "results": sorted(byid.get(cid, []), key=lambda x: x["host"]),
                }
            )
        self._json({"cmds": out})

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
            "SELECT name, params FROM jobs WHERE cmd_id=?", (cid,)
        ).fetchone()
        con.close()
        self._json(
            {
                "id": row[0],
                "ts": row[1],
                "target": row[2],
                "cmd": row[3],
                "job": {"name": job[0], "params": job[1]} if job else None,
                "results": [
                    {"host": h, "ts": t, "rc": rc, "out": o} for h, t, rc, o in res
                ],
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
            "SELECT id,ts,actor,action,detail FROM audit ORDER BY id DESC LIMIT 100"
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

    def _get_map(self) -> None:
        con = db()
        rows = con.execute(
            "SELECT host,state,guard,rmm,last_seen FROM hosts ORDER BY host"
        ).fetchall()
        con.close()
        now = time.time()
        lines = ["%-24s %-18s %-7s %-9s %s" % ("HOST", "STATE", "GUARD", "LAST SEEN", "RMM")]
        for h, s, g, rmm, ts in rows:
            ago = int((now - ts) / 60)
            seen = (
                ("%dm ago" % ago)
                if ago < 90
                else ("%.1fh ago" % (ago / 60))
                if ago < 2880
                else ("%.1fd ago" % (ago / 1440))
            )
            if now - ts > SILENCE_SECS:
                s += " [SILENT]"
            lines.append("%-24s %-18s %-7s %-9s %s" % (h, s, g, seen, (rmm or "-")[:80]))
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
        time.sleep(3600)
        try:
            con = db()
            rows = con.execute(
                "SELECT host,state,last_seen,last_alert FROM hosts"
            ).fetchall()
            now = time.time()
            for h, s, ts, la in rows:
                if now - ts > SILENCE_SECS and now - la > SILENCE_RESEND:
                    alert(fmt_silent(h, s, (now - ts) / 3600))
                    con.execute(
                        "UPDATE hosts SET last_alert=? WHERE host=?", (now, h)
                    )
            con.commit()
            con.close()
        except Exception:
            pass


if __name__ == "__main__":
    threading.Thread(target=silence_watchdog, daemon=True).start()
    threading.Thread(target=alert_flusher, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8077), H).serve_forever()
