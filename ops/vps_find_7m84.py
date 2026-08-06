#!/usr/bin/env python3
"""Deep lookup for DESKTOP-7M84CP8."""
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
import sqlite3, os, time, json, re
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
c.row_factory = sqlite3.Row
now = time.time()
needle = '7M84CP8'
print('=== exact ===')
for r in c.execute("SELECT * FROM hosts WHERE host=? COLLATE NOCASE", ('DESKTOP-7M84CP8',)):
    print(dict(r))
print('=== contains 7M84 / CP8 / 7M84CP ===')
for r in c.execute('SELECT host,state,agent,guard,last_beat,last_seen,rmm FROM hosts'):
    h = r['host'].upper()
    if any(x in h for x in ('7M84', 'M84CP', '7M84CP8', '84CP8')):
        d = dict(r)
        if d.get('last_beat'):
            d['beat_ago_min'] = round((now - float(d['last_beat'])) / 60, 1)
        if d.get('last_seen'):
            d['seen_ago_min'] = round((now - float(d['last_seen'])) / 60, 1)
        print(json.dumps(d, default=str))
print('=== all DESKTOP-* with 7 or M84-like ===')
for r in c.execute("SELECT host, last_beat FROM hosts WHERE host LIKE 'DESKTOP-%' ORDER BY host"):
    h = r[0]
    if re.search(r'7M|M84|84CP|CP8', h, re.I):
        ago = round((now - float(r[1])) / 60, 1) if r[1] else None
        print(h, 'beat_ago', ago)
print('=== pending cmds for name ===')
for r in c.execute("SELECT id,target,round(?-ts,0),substr(cmd,1,50) FROM cmds WHERE target LIKE ? ORDER BY id DESC LIMIT 10", (now, '%7M84%')):
    print(r)
for r in c.execute("SELECT id,target,round(?-ts,0),substr(cmd,1,50) FROM cmds WHERE target LIKE ? ORDER BY id DESC LIMIT 10", (now, '%7M84CP8%')):
    print(r)
print('=== host count ===', c.execute('SELECT count(*) FROM hosts').fetchone()[0])
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/find_7m84.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/find_7m84.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))

    # nginx access log recent heartbeats
    cmds = [
        "sudo grep -i '7M84CP8\\|7m84cp8' /var/log/nginx/access.log | tail -30",
        "sudo grep -i '7M84' /var/log/nginx/access.log | tail -30",
        "sudo grep -oE 'host=[A-Za-z0-9_-]+' /var/log/nginx/access.log 2>/dev/null | sort | uniq -c | sort -rn | grep -i 7M | head",
        # maybe POST body not in access log - check report service if it logs hosts
        "sudo ls -lt /var/log/nginx/ | head -5",
    ]
    for c in cmds:
        print(">>>", c[:90])
        _, o, e = ssh.exec_command(c, timeout=60)
        out = o.read().decode("utf-8", "replace")
        err = e.read().decode("utf-8", "replace")
        print(out[:3000] if out.strip() else "(empty)")
        if err.strip():
            print("ERR", err[:400])
    ssh.close()


if __name__ == "__main__":
    main()
