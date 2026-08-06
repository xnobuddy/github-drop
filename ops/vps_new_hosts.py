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
print('=== first_seen proxy: hosts with beat in last 15m and digest in last 15m ===')
n = 0
for row in c.execute(
    "SELECT host,state,guard,agent,rmm,last_seen,last_beat FROM hosts "
    "WHERE (last_beat IS NOT NULL AND last_beat > ?) OR (last_seen > ?) "
    "ORDER BY COALESCE(last_beat, last_seen) DESC",
    (now - 900, now - 900),
):
    h,st,g,ag,rmm,ls,lb = row
    # only print if likely new: no prior - hard. just print laptop*
    if 'LAPTOP' in h.upper() or 'G0T' in h.upper():
        print(h, 'state', st, 'guard', g, 'agent', ag)
        print('  digest_age_m', round((now-ls)/60,1) if ls else None, 'beat_age_m', round((now-lb)/60,1) if lb else None)
        print('  rmm', (rmm or '')[:120])
        n += 1
print('laptop matches in 15m window:', n)
print('=== all hosts matching LAPTOP newly beating ===')
for row in c.execute(
    "SELECT host,agent,last_beat,last_seen,state,rmm FROM hosts WHERE upper(host) LIKE 'LAPTOP%' AND last_beat > ? ORDER BY last_beat DESC LIMIT 30",
    (now - 1800,),
):
    h,ag,lb,ls,st,rmm = row
    print(h, 'beat_age', round((now-lb)/60,1), 'agent', ag, 'state', st)
    print(' ', (rmm or '')[:100])
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
    with sftp.file("/tmp/newh.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/newh.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
