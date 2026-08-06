#!/usr/bin/env python3
"""Build, verify, force-sync C33 killlist update to VPS, queue Hunt on ALL online hosts."""
from __future__ import annotations

import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parent.parent  # repo root (script lives in ops/)
HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
FETCH = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text(encoding="utf-8").strip()

FILES = [
    "winrtcs_killlist.cfg",
    "winrtcs_sidekick.ps1",
    "winrtcs.version",
    "winrtcs.version.sig",
    "winrtcs_fleet_purge.ps1",
    "CASES.md",
]

# Force immediate killlist + Hunt (does not wait for next guard cycle).
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
    print("== build ==")
    r = subprocess.run([sys.executable, str(ROOT / "winrtcs_build.py")], cwd=ROOT)
    if r.returncode != 0:
        print("build failed", r.returncode)
        return r.returncode

    ver = (ROOT / "winrtcs.version").read_text(encoding="utf-8")
    print(ver)
    kl = (ROOT / "winrtcs_killlist.cfg").read_text(encoding="utf-8")
    for needle in (
        "SCCleanup",
        "KeepTwo",
        "BVTFilter",
        "WucacheWatchdog",
        "KernCap",
        "4d789b4bfb0e00cd84c1f83a4ca5317e",
    ):
        assert needle in kl, f"missing {needle} in killlist"

    print("== scp to VPS repo ==")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    sftp = ssh.open_sftp()
    remote = "/opt/winrtcs/repo"
    for name in FILES:
        local = ROOT / name
        if not local.exists():
            print("skip missing", name)
            continue
        dest = f"{remote}/{name}"
        sftp.put(str(local), dest)
        print("put", name, local.stat().st_size)
    sftp.close()
    # Ensure nginx can serve; touch so mtime updates
    ssh.exec_command(f"chmod 644 {remote}/winrtcs_killlist.cfg {remote}/winrtcs_sidekick.ps1")
    ssh.close()

    print("== verify VPS serves killlist ==")
    req = urllib.request.Request(
        BASE + "/winrtcs/winrtcs_killlist.cfg?t=" + str(int(time.time())),
        headers={
            "Authorization": "Bearer " + FETCH,
            "User-Agent": "Mozilla/5.0 (WinRTCS-Console)",
        },
    )
    body = urllib.request.urlopen(req, timeout=30).read().decode(errors="replace")
    assert "SCCleanup" in body and "BVTFilter" in body, "VPS killlist stale"
    print("VPS killlist OK bytes=", len(body))

    print("== queue ALL force Hunt ==")
    print(api("/cmd", {"target": "ALL", "cmd": FORCE_CMD}))
    print("queued; hosts pick up within ~1 min")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
