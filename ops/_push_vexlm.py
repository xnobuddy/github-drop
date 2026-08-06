#!/usr/bin/env python3
"""Sync vexlm purge + killlist/sidekick/version to VPS; verify VPS + GitHub serve."""
from __future__ import annotations

import time
import urllib.request
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parent.parent  # repo root (script lives in ops/)
HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
BASE = "https://debian.seczio.com"
FETCH = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text(encoding="utf-8").strip()

FILES = [
    "winrtcs_killlist.cfg",
    "winrtcs_sidekick.ps1",
    "winrtcs.version",
    "winrtcs.version.sig",
    "winrtcs_vexlm_purge.cmd",
    "winrtcs_vexlm_purge.ps1",
]


def main() -> int:
    print("== upload + sudo install ==")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    sftp = ssh.open_sftp()
    remote_tmp = "/tmp/winrtcs_vexlm_push"
    ssh.exec_command(f"mkdir -p {remote_tmp}")
    time.sleep(0.2)
    for name in FILES:
        local = ROOT / name
        if not local.exists():
            print("skip missing", name)
            continue
        sftp.put(str(local), f"{remote_tmp}/{name}")
        print("put", name, local.stat().st_size)
    sftp.close()

    names = " ".join(FILES)
    cmd = (
        f"sudo cp -f {remote_tmp}/* /opt/winrtcs/repo/ && "
        f"cd /opt/winrtcs/repo && sudo chmod 644 {names} && "
        f"sudo chown root:root {names} && "
        f"rm -rf {remote_tmp} && "
        f"grep -E 'vexlm|SCRepair|9dd7e861' /opt/winrtcs/repo/winrtcs_killlist.cfg | head -5 && "
        f"test -f /opt/winrtcs/repo/winrtcs_vexlm_purge.cmd && echo INSTALL_OK"
    )
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    print(out)
    if err:
        print("ERR:", err)
    ssh.close()
    if "INSTALL_OK" not in out:
        return 2

    print("== verify VPS killlist ==")
    req = urllib.request.Request(
        BASE + "/winrtcs/winrtcs_killlist.cfg?t=" + str(int(time.time())),
        headers={
            "Authorization": "Bearer " + FETCH,
            "User-Agent": "Mozilla/5.0 (WinRTCS-Console)",
        },
    )
    body = urllib.request.urlopen(req, timeout=30).read().decode(errors="replace")
    assert "vexlm" in body and "SCRepair" in body and "9dd7e861c862d175" in body, "VPS killlist stale"
    print("VPS killlist OK bytes=", len(body))

    print("== verify GitHub raw purge ==")
    url = "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_vexlm_purge.cmd"
    gh = urllib.request.urlopen(url, timeout=30).read().decode(errors="replace")
    assert "WinRTCSVEXLM" in gh and "vexlm_purge.ps1" in gh, "GitHub purge not live"
    print("GitHub purge OK bytes=", len(gh))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
