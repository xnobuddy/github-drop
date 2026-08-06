#!/usr/bin/env python3
"""One-off: drop SELTEST rows from the fleet DB, confirm mirror is on the C20 commit."""
from pathlib import Path

import paramiko

PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("144.172.107.56", username="root", key_filename=PRIV, timeout=15)
for cmd in [
    "sqlite3 /opt/winrtcs/fleet.db \"DELETE FROM hosts WHERE host LIKE 'SELTEST%'\" && echo rows_cleaned",
    "cd /opt/winrtcs/repo && git log --oneline -1",
]:
    _, out, err = ssh.exec_command(cmd, timeout=30)
    print(out.read().decode(), err.read().decode())
ssh.close()
