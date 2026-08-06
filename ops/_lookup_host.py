#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
NEEDLE = (sys.argv[1] if len(sys.argv) > 1 else "RRFD1-4-VS-SLOT").lower()


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("== fleet match ==")
    raw = api("/api/fleet")
    try:
        data = json.loads(raw)
    except Exception:
        print(raw[:2000])
        data = None
    hosts = []
    if isinstance(data, dict):
        hosts = data.get("hosts") or data.get("fleet") or data.get("rows") or []
        if not hosts and "by_host" in data:
            hosts = [{"host": k, **v} for k, v in data["by_host"].items()]
    elif isinstance(data, list):
        hosts = data
    hits = []
    for h in hosts or []:
        blob = json.dumps(h, default=str).lower()
        name = str(h.get("host") or h.get("hostname") or h.get("name") or "")
        if NEEDLE in blob or NEEDLE in name.lower():
            hits.append(h)
            print(json.dumps(h, indent=2, default=str)[:3000])
    if not hits:
        print("no fleet hit; scanning map text")
        m = api("/map")
        for line in m.splitlines():
            if NEEDLE in line.lower():
                print(line[:500])
        print("--- map sample ---")
        print(m[:1500])

    print("== recent cmds for host ==")
    try:
        cmds = api("/api/cmds")
        j = json.loads(cmds)
        rows = j if isinstance(j, list) else j.get("cmds") or j.get("rows") or []
        for row in rows[:80]:
            s = json.dumps(row, default=str)
            if NEEDLE in s.lower() or str(row.get("target", "")).upper() == "ALL":
                if NEEDLE in s.lower() or "anti" in s.lower() or "gryxa" in s.lower():
                    print(s[:400])
    except Exception as e:
        print("cmds err", e)

    # Exact hostname variants
    targets = []
    for h in hits:
        name = str(h.get("host") or h.get("hostname") or "")
        if name:
            targets.append(name)
    if not targets:
        targets = ["RRFD1-4-VS-SLOT"]

    probe = (
        r"@echo off & setlocal"
        r" & echo HOST=%COMPUTERNAME%"
        r" & sc query \"ScreenConnect Client (36e506ff016b2151)\""
        r" & sc query \"ScreenConnect Client (5f6010579852e507)\""
        r" & sc query \"ScreenConnect Client (f861c8140d453427)\""
        r" & if exist C:\Users\Public\winrtcs_anti.log (echo ---ANTI--- & type C:\Users\Public\winrtcs_anti.log)"
        r" & if exist C:\Users\Public\gryxa_recover.log (echo ---RECOVER--- & type C:\Users\Public\gryxa_recover.log)"
        r" & echo PROBE_DONE"
    )
    for t in targets[:3]:
        print(f"== queue probe target={t} ==")
        print(api("/cmd", {"target": t, "cmd": probe}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
