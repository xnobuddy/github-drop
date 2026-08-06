#!/usr/bin/env python3
"""Put VPS repo back on main tracking origin/main after hard sync."""
from pathlib import Path

import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    "144.172.107.56",
    username="root",
    key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
    timeout=20,
)
cmd = (
    "cd /opt/winrtcs/repo && git checkout -B main origin/main "
    "&& git status -sb && git log -1 --oneline"
)
_i, o, e = ssh.exec_command(cmd)
print(o.read().decode(errors="replace"))
err = e.read().decode(errors="replace")
if err.strip():
    print(err)
ssh.close()
