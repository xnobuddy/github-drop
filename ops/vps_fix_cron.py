#!/usr/bin/env python3
"""Fix: install cron (missing on the minimal Debian 13 image) so the mirror sync runs."""
from pathlib import Path

import paramiko

PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("144.172.107.56", username="root", key_filename=PRIV, timeout=15)
for cmd in [
    "apt-get install -y cron 2>&1 | tail -2",
    "systemctl enable --now cron && systemctl is-active cron",
]:
    _, out, err = ssh.exec_command(cmd, timeout=180)
    print(out.read().decode(), err.read().decode())
ssh.close()
