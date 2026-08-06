#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    cmd = (
        "TOK=$(sudo cat /opt/winrtcs/fetch_token); "
        "curl -s -w '\\nHTTP:%{http_code}\\n' -X POST "
        "-d 'host=LOCALHB&agent=0.0.8&guard=0.2.0' "
        "-H \"Authorization: Bearer $TOK\" "
        "http://127.0.0.1:8077/heartbeat; "
        "echo ---; head -15 /opt/winrtcs/repo/winrtcs.version; "
        "echo ---; cd /opt/winrtcs/repo && sudo git -c safe.directory=/opt/winrtcs/repo log -1 --oneline"
    )
    _, out, err = ssh.exec_command(cmd, timeout=60)
    print(out.read().decode("utf-8", "replace"))
    print(err.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
