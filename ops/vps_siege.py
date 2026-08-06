#!/usr/bin/env python3
"""Check which components the siege hosts are missing."""
from pathlib import Path

import paramiko

PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("144.172.107.56", username="root", key_filename=PRIV, timeout=15)
_, out, err = ssh.exec_command(
    "sqlite3 /opt/winrtcs/fleet.db \"SELECT host, siege, suspects, last_seen FROM hosts WHERE siege != ''\"", timeout=30
)
print(out.read().decode() or "(no siege rows)", err.read().decode())
ssh.close()
