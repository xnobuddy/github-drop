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
rows = c.execute(
    "SELECT host,state,guard,rmm,last_seen,last_beat,agent FROM hosts "
    "WHERE upper(host) LIKE '%MOE%' OR upper(host) LIKE '%JLB2B33%' "
    "OR host='DESKTOP-JLB2B33' OR host='MOE77' ORDER BY host"
).fetchall()
if not rows:
    print('NO_MATCH')
    # show recent heartbeats for context
    for row in c.execute(
        "SELECT host,last_beat,state FROM hosts ORDER BY last_beat DESC LIMIT 15"
    ):
        h, lb, st = row
        age = round((now - lb) / 60, 1) if lb else None
        print('recent', h, 'beat_age_m', age, st)
else:
    for h, st, g, rmm, ls, lb, ag in rows:
        print('HOST', h)
        print('  state', st, 'guard', g, 'agent', ag)
        print('  rmm', rmm)
        print('  digest_age_m', round((now - ls) / 60, 1) if ls else None)
        print('  beat_age_m', round((now - lb) / 60, 1) if lb else None)
print('total', c.execute('select count(*) from hosts').fetchone()[0])
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
    with sftp.file("/tmp/hcheck.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/hcheck.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err.strip():
        print(err)
    ssh.close()


if __name__ == "__main__":
    main()
