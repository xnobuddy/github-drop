#!/usr/bin/env python3
"""Push report service v3.1 (body cap + clean 404s), restart, quick sanity."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
SVC = (Path.home() / "Desktop" / "report_service.py").read_text(encoding="utf-8")
TOKEN = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text().strip()


def run(ssh: paramiko.SSHClient, cmd: str, timeout: int = 60) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=timeout)
    rc = out.channel.recv_exit_status()
    o = out.read().decode(errors="replace")
    if rc != 0:
        print(f"FAIL rc={rc}: {cmd}\n{o[-400:]}\n{err.read().decode(errors='replace')[-600:]}")
        sys.exit(1)
    return o


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="root", key_filename=PRIV, timeout=15)
    sftp = ssh.open_sftp()
    with sftp.open("/opt/winrtcs/report_service.py", "w") as f:
        f.write(SVC)
    sftp.close()
    print(run(ssh, "python3 -c \"import ast; ast.parse(open('/opt/winrtcs/report_service.py').read())\" && echo syntax_ok"))
    print(run(ssh, "systemctl restart winrtcs-report && sleep 1 && systemctl is-active winrtcs-report"))
    print(run(ssh, f"curl -s -H 'Authorization: Bearer {TOKEN}' http://127.0.0.1:8077/map | head -2"))
    print(run(ssh, f"curl -s -o /dev/null -w 'unknown-path=%{{http_code}}\\n' -H 'Authorization: Bearer {TOKEN}' http://127.0.0.1:8077/nope"))
    ssh.close()


if __name__ == "__main__":
    main()
