#!/usr/bin/env python3
"""Debug the VPS mirror cron: show cron entry, attempt manual pull, show status."""
from pathlib import Path

import paramiko

PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("144.172.107.56", username="root", key_filename=PRIV, timeout=15)
for cmd in [
    "cat /etc/cron.d/winrtcs-mirror",
    "systemctl status cron --no-pager | head -5",
    "cd /opt/winrtcs/repo && git pull --ff-only 2>&1; git log --oneline -1",
    "grep CRON /var/log/syslog 2>/dev/null | tail -5 || journalctl -u cron --no-pager -n 10 2>&1 | tail -10",
]:
    _, out, err = ssh.exec_command(cmd, timeout=60)
    print(f"--- {cmd[:60]}\n{out.read().decode()}{err.read().decode()}")
ssh.close()
