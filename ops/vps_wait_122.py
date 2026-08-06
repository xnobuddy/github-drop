#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    poll = r"""
import sqlite3, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
r=con.execute("SELECT rc,out FROM results WHERE cmd_id=122 AND host='ADMINIS-0ET5284'").fetchone()
print('FOUND' if r else 'WAIT')
if r:
    print('RC', r[0])
    print(r[1] or '')
row=con.execute("SELECT state,rmm,last_seen,last_beat FROM hosts WHERE host='ADMINIS-0ET5284'").fetchone()
import time
now=time.time()
print('HOST', row[0], 'digest_age', round((now-row[2])/60,1) if row and row[2] else None, 'beat_age', round((now-row[3])/60,1) if row and row[3] else None)
print('RMM', row[1] if row else None)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/w122.py", "w") as f:
        f.write(poll)
    sftp.close()
    for i in range(30):
        _, o, e = ssh.exec_command("python3 /tmp/w122.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        print(f"--- {i} ---")
        print(text)
        if text.startswith("FOUND"):
            break
        time.sleep(15)
    ssh.close()


if __name__ == "__main__":
    main()
