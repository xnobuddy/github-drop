#!/usr/bin/env python3
from __future__ import annotations

import sys
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
    script = r"""
import sqlite3, time, shutil, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
h='ADMINIS-0ET5284'
row=con.execute('SELECT state,rmm,last_seen,last_beat,guard FROM hosts WHERE host=?',(h,)).fetchone()
print('HOST', row)
if row and row[2]: print('digest_age_m', round((now-row[2])/60,1))
if row and row[3]: print('beat_age_m', round((now-row[3])/60,1))
for cid in (119, 117):
    r=con.execute('SELECT rc,ts,out FROM results WHERE cmd_id=? AND host=?',(cid,h)).fetchone()
    print('=== CMD', cid, (r[0] if r else 'NONE'), '===')
    if r:
        print('age_m', round((now-r[1])/60,1))
        print(r[2] or '(empty)')
con.close()
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/poll_check.py", "w") as f:
        f.write(script)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/poll_check.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
