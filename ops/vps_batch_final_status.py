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
c=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
want=[
 'LAPTOPBE','LAPTOP-1P6GP1UQ','EASYLAB0514-2','DESKTOP-JQKHHML','DESKTOP-GG4NNSJ',
 'DESKTOP-7M84CP8','DESKTOP-0Q4F5D9','CARPED-P16S','CARI','PIERREADOLPHE'
]
print(f'{"HOST":22} {"LINK":8} {"BEAT":7} {"SEEN":7} {"VER":12} GRYXA  STATE')
for t in want:
    r=c.execute('SELECT host,state,agent,guard,last_beat,last_seen,rmm FROM hosts WHERE host=? COLLATE NOCASE',(t,)).fetchone()
    if not r:
        print(f'{t:22} MISSING  -       -       -            no     (Guest Quick)')
        continue
    h,st,ag,gu,lb,ls,rmm=r
    beat=round((now-float(lb))/60,1) if lb else None
    seen=round((now-float(ls))/60,1) if ls else None
    online = beat is not None and beat < 5
    gryxa = '[gryxa]' in (rmm or '')
    link = 'ONLINE' if online else 'OFFLINE'
    ver = f'{ag}/{gu}'
    print(f'{h:22} {link:8} {str(beat)+"m":7} {str(seen)+"m":7} {ver:12} {"YES" if gryxa else "NO ":3}  {st}')
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/final.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/final.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
