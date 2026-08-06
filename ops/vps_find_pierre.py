#!/usr/bin/env python3
from __future__ import annotations

import json
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
    py = r"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
c.row_factory = sqlite3.Row
now = time.time()
print('=== hosts match PIERRE/ADOL ===')
for r in c.execute(
    "SELECT * FROM hosts WHERE host LIKE ? COLLATE NOCASE OR host LIKE ? COLLATE NOCASE",
    ('%PIERRE%', '%ADOL%'),
):
    d = dict(r)
    for k in ('last_seen', 'last_beat'):
        if d.get(k):
            try:
                d[k + '_ago_min'] = round((now - float(d[k])) / 60, 1)
            except Exception:
                pass
    print(json.dumps(d, default=str))
print('=== recent cmds ===')
for r in c.execute(
    '''SELECT c.id, c.target, round((?-c.ts)/60,1) as ago_min, substr(c.cmd,1,70) as cmd,
              r.rc, substr(replace(coalesce(r.out,''),char(10),' | '),1,160) as out
       FROM cmds c LEFT JOIN results r ON r.cmd_id=c.id
       WHERE c.target LIKE ? COLLATE NOCASE OR c.target LIKE ? COLLATE NOCASE
       ORDER BY c.id DESC LIMIT 10''',
    (now, '%PIERRE%', '%ADOL%'),
):
    print(dict(r))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/find_pierre.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/find_pierre.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err:
        print("ERR", err)
    ssh.close()


if __name__ == "__main__":
    main()
