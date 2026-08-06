#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REMOTE = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
print('=== LIKE G0T88 / G0T ===')
for row in c.execute(
    "SELECT host,state,guard,agent,last_seen,last_beat,rmm FROM hosts "
    "WHERE upper(host) LIKE '%G0T%' OR upper(host) LIKE '%88MQP%' ORDER BY host"
):
    h,st,g,ag,ls,lb,rmm = row
    print(h, 'state', st, 'guard', g, 'agent', ag)
    print('  digest_age_m', round((now-ls)/60,1) if ls else None, 'beat_age_m', round((now-lb)/60,1) if lb else None)
    print('  rmm', rmm)
print('=== newest digests (15) ===')
for row in c.execute(
    "SELECT host,state,last_seen,last_beat,agent FROM hosts ORDER BY COALESCE(last_beat,last_seen) DESC LIMIT 15"
):
    h,st,ls,lb,ag = row
    ref = lb or ls
    print(h, 'age_m', round((now-ref)/60,1) if ref else None, 'beat' if lb else 'digest', st, 'agent', ag)
"""


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/recent.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/recent.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
