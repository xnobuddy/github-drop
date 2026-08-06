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
    cmds = [
        "sudo grep -iE 'pierre|adolphe|PIERREADOLPHE' /var/log/nginx/access.log | tail -50",
        "sudo zgrep -iE 'pierre|adolphe' /var/log/nginx/access.log* 2>/dev/null | tail -50",
        "sudo sqlite3 /opt/winrtcs/report.db '.tables' 2>/dev/null; sudo ls -la /opt/winrtcs/report.db 2>/dev/null",
    ]
    for c in cmds:
        print(">>>", c)
        _, o, e = ssh.exec_command(c, timeout=60)
        print(o.read().decode("utf-8", "replace")[:4000])
        err = e.read().decode("utf-8", "replace")
        if err.strip():
            print("ERR", err[:800])

    py = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
print('=== online hosts without [gryxa] ===')
for h, st, ag, gu, lb, ls, rmm in c.execute(
    'SELECT host,state,agent,guard,last_beat,last_seen,rmm FROM hosts'
):
    if not lb or (now - float(lb)) > 5 * 60:
        continue
    r = rmm or ''
    if '[gryxa]' not in r:
        print(h, 'state=' + str(st), 'ag=' + str(ag), 'gu=' + str(gu),
              'beat_m=' + str(round((now - float(lb)) / 60, 1)),
              'seen_m=' + (str(round((now - float(ls)) / 60, 1)) if ls else '?'),
              'rmm=' + r[:120])
# also check report.db if sqlite
import subprocess
subprocess.run(['sudo', 'cp', '/opt/winrtcs/report.db', '/tmp/report_ro.db'], check=False)
try:
    r = sqlite3.connect('/tmp/report_ro.db')
    print('report tables', [x[0] for x in r.execute("SELECT name FROM sqlite_master WHERE type='table'")])
except Exception as e:
    print('report', e)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/pierre3.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/pierre3.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
