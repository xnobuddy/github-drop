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
h = 'LAPTOP-G0T88MQP'
row = c.execute(
    'SELECT state,guard,siege,rmm,last_seen,last_beat,agent FROM hosts WHERE host=?', (h,)
).fetchone()
print('HOST', row)
if row:
    print('digest_age_m', round((now-row[4])/60,1) if row[4] else None)
    print('beat_age_m', round((now-row[5])/60,1) if row[5] else None)
for cid in (127, 126):
    r = c.execute('SELECT rc, substr(out,1,800), ts FROM results WHERE cmd_id=? AND host=?', (cid,h)).fetchone()
    print('CMD', cid, r[0] if r else 'NONE')
    if r:
        print(r[1])
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
    with sftp.file("/tmp/pg0t.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/pg0t.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
