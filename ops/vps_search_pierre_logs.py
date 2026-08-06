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
    # nginx / report logs for hostname
    cmds = [
        "sudo grep -i pierre /var/log/nginx/*.log /opt/winrtcs/logs/* 2>/dev/null | tail -40",
        "sudo grep -i adolphe /var/log/nginx/*.log /opt/winrtcs/logs/* 2>/dev/null | tail -40",
        "sudo journalctl -u winrtcs-report --no-pager -n 200 2>/dev/null | grep -iE 'pierre|adol' | tail -20",
        "ls /opt/winrtcs/ 2>/dev/null; ls /var/log/nginx/ 2>/dev/null | head",
    ]
    for c in cmds:
        print(">>>", c[:80])
        _, o, e = ssh.exec_command(c, timeout=30)
        print(o.read().decode("utf-8", "replace")[:3000])
        err = e.read().decode("utf-8", "replace")
        if err:
            print("ERR", err[:500])
    # tags / audit
    py = r"""
import sqlite3, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
print('tags', c.execute('SELECT name FROM sqlite_master').fetchall())
try:
  for r in c.execute('SELECT * FROM tags'): print('TAG', dict(zip([x[0] for x in c.execute('PRAGMA table_info(tags)')], r)) if False else r)
except Exception as e: print(e)
try:
  for r in c.execute(\"SELECT * FROM host_tags\"): print('HT', r)
except Exception as e: print('ht', e)
try:
  for r in c.execute(\"SELECT * FROM audit ORDER BY rowid DESC LIMIT 30\"):
    s=str(r).lower()
    if 'pierre' in s or 'adol' in s: print('AUDIT', r)
except Exception as e: print('audit', e)
# hosts missing gryxa with fresh beat
import time
now=time.time()
print('=== online no gryxa ===')
for h,st,ag,lb,rmm in c.execute('SELECT host,state,agent,last_beat,rmm FROM hosts'):
  if not lb or (now-float(lb))>5*60: continue
  r=(rmm or '')
  if '[gryxa]' not in r:
    print(h, st, ag, round((now-float(lb))/60,1), r[:100])
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/search_pierre2.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/search_pierre2.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
