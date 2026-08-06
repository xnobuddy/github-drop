#!/usr/bin/env python3
from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
HOST = "RRFD1-4-VS-SLOT"


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    cmd = (
        "@echo off & setlocal EnableExtensions"
        " & echo HOST=%COMPUTERNAME%"
        " & echo ===GRYXA==="
        " & sc query \"ScreenConnect Client (36e506ff016b2151)\""
        " & echo ===RECOVER==="
        " & if exist C:\\Users\\Public\\gryxa_recover.log (type C:\\Users\\Public\\gryxa_recover.log) else echo NO_RECOVER"
        " & echo ===ANTI_TAIL==="
        " & if exist C:\\Users\\Public\\winrtcs_anti.log (powershell -NoP -C \"Get-Content C:\\Users\\Public\\winrtcs_anti.log -Tail 40\") else echo NO_ANTI"
        " & echo STATUS_DONE"
    )
    raw = api("/cmd", {"target": HOST, "cmd": cmd})
    print(raw)
    cid = 0
    for part in raw.split():
        if part.startswith("id="):
            cid = int(part.split("=", 1)[1].rstrip(","))
    deadline = time.time() + 120
    while time.time() < deadline:
        j = json.loads(api(f"/api/cmd/{cid}"))
        for r in j.get("results") or []:
            if str(r.get("host", "")).upper() == HOST.upper():
                print(r.get("out", "")[:9000])
                return 0
        time.sleep(5)
    print("timeout")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
