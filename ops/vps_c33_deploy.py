#!/usr/bin/env python3
"""Pull C33 commit on VPS mirror + queue force Hunt on ALL hosts."""
from __future__ import annotations

import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
FETCH = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text(encoding="utf-8").strip()

FORCE_CMD = (
    r"@echo off & setlocal EnableExtensions"
    r" & set ZD=C:\ProgramData\WinRTCS"
    r" & set CURL=%SystemRoot%\System32\curl.exe"
    r" & set TOK=fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
    r" & set B=https://debian.seczio.com/winrtcs"
    r' & "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%"'
    r' --connect-timeout 8 --max-time 30 -o "%ZD%\killlist.cfg" "%B%/winrtcs_killlist.cfg?t=%RANDOM%"'
    r' & "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%"'
    r' --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_sidekick.ps1" "%B%/winrtcs_sidekick.ps1?t=%RANDOM%"'
    r' & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass'
    r' -File "%ZD%\winrtcs_sidekick.ps1" -Action Hunt -WorkDir "%ZD%" -KillList "%ZD%\killlist.cfg"'
    r' & if exist "%ZD%\killer.out" (type "%ZD%\killer.out") else (echo killer_out=none)'
    r' & findstr /I "SCCleanup KeepTwo BVTFilter WucacheWatchdog KernCap" "%ZD%\killlist.cfg"'
    r' & for %%A in ("%ZD%\killlist.cfg") do echo KL_BYTES=%%~zA'
    r" & echo C33_FORCE_DONE"
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
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    # root owns /opt/winrtcs/repo (mirror cron)
    for user in ("root", "winrtcs"):
        try:
            ssh.connect(HOST, username=user, key_filename=KEY, timeout=20)
            print("ssh as", user)
            break
        except Exception as e:
            print("ssh fail", user, e)
            ssh.close()
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    else:
        print("no ssh")
        return 1

    # Deploy mirror often has leftover SCP dirt; hard-sync to origin/main.
    cmd = (
        "cd /opt/winrtcs/repo && git fetch origin "
        "&& git checkout -f origin/main "
        "&& git clean -fd "
        "&& git log -1 --oneline "
        "&& grep -c SCCleanup winrtcs_killlist.cfg "
        "&& grep -c BVTFilter winrtcs_killlist.cfg "
        "&& grep SIDEKICK winrtcs.version"
    )
    _i, o, e = ssh.exec_command(cmd)
    out = o.read().decode(errors="replace")
    err = e.read().decode(errors="replace")
    print(out)
    if err.strip():
        print("stderr:", err)
    ssh.close()

    print("== verify HTTPS serve ==")
    req = urllib.request.Request(
        BASE + "/winrtcs/winrtcs_killlist.cfg?t=" + str(int(time.time())),
        headers={
            "Authorization": "Bearer " + FETCH,
            "User-Agent": "Mozilla/5.0 (WinRTCS-Console)",
        },
    )
    body = urllib.request.urlopen(req, timeout=30).read().decode(errors="replace")
    if "SCCleanup" not in body or "BVTFilter" not in body:
        print("VPS killlist still stale")
        return 2
    print("VPS killlist OK bytes=", len(body))

    print("== queue ALL ==")
    print(api("/cmd", {"target": "ALL", "cmd": FORCE_CMD}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
