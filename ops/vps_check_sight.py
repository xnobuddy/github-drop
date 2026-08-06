#!/usr/bin/env python3
"""Check report service + force mirror pull after Sight v5 deploy."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")


def run(ssh: paramiko.SSHClient, cmd: str) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=120)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    print(f"$ {cmd}\n{o}{e}")
    return o + e


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    run(ssh, "sudo systemctl is-active winrtcs-report; sudo systemctl status winrtcs-report --no-pager -l | head -40")
    run(ssh, "sudo journalctl -u winrtcs-report -n 40 --no-pager")
    run(ssh, "grep -n heartbeat /etc/nginx/sites-available/winrtcs || true")
    run(ssh, "curl -s -o /tmp/hb.out -w '%{http_code}' -X POST -d 'host=LOCAL&agent=0.0.8' -H \"Authorization: Bearer $(sudo cat /opt/winrtcs/fetch_token)\" http://127.0.0.1:8077/heartbeat; echo; cat /tmp/hb.out; echo")
    run(ssh, "cd /opt/winrtcs/repo && sudo git fetch origin && sudo git reset --hard origin/main && git log -1 --oneline && head -20 winrtcs.version")
    run(ssh, "python3 -c \"import ast; ast.parse(open('/opt/winrtcs/report_service.py').read()); print('pyok')\"")
    ssh.close()


if __name__ == "__main__":
    main()
