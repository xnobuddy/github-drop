#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = sys.argv[1] if len(sys.argv) > 1 else "LAPTOP-G0T88MQP"

REMOTE = f"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
h = {TARGET!r}
row = c.execute(
    "SELECT host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,last_beat,agent,maint "
    "FROM hosts WHERE upper(host)=upper(?)",
    (h,),
).fetchone()
if not row:
    print('NOT_IN_FLEET', h)
    for r in c.execute(
        "SELECT host,last_beat,last_seen,state FROM hosts WHERE upper(host) LIKE upper(?) ORDER BY host",
        ('%' + h.replace('LAPTOP-','').replace('DESKTOP-','') + '%',),
    ):
        print('near', r)
else:
    keys = ['host','state','streak','extkill','guard','siege','suspects','rmm','last_seen','last_beat','agent','maint']
    d = dict(zip(keys, row))
    for k,v in d.items():
        if k in ('last_seen','last_beat') and v:
            print(f'{{k}}={{v}} age_m={{round((now-v)/60,1)}}')
        else:
            print(f'{{k}}={{v}}')
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
    with sftp.file("/tmp/hone.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/hone.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err.strip():
        print(err)
    ssh.close()


if __name__ == "__main__":
    main()
