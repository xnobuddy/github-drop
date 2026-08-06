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
    py = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
print('=== all hosts (ago_min last_beat / last_seen) ===')
rows = c.execute('SELECT host,state,agent,guard,last_beat,last_seen,rmm,streak,extkill FROM hosts ORDER BY last_beat DESC').fetchall()
for h,st,ag,gu,lb,ls,rmm,sk,ek in rows:
    lb_ago = round((now-float(lb))/60,1) if lb else None
    ls_ago = round((now-float(ls))/60,1) if ls else None
    online = (lb_ago is not None and lb_ago < 5)
    print(f'{h:30} beat={lb_ago}m seen={ls_ago}m state={st} ag={ag} gu={gu} online={online} rmm={(rmm or "")[:80]}')
print('total', len(rows))
print('=== fuzzy ===')
for r in c.execute("SELECT host FROM hosts"):
    h=r[0].upper()
    if 'PIE' in h or 'ADOL' in h or 'PH' in h and 'PIER' in h:
        print('FUZZY', r[0])
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/list_hosts.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/list_hosts.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
