#!/usr/bin/env python3
"""Deep dump of PC-EVITA-X6 from fleet.db."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HOST = "PC-EVITA-X6"

REMOTE = r"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
h = 'PC-EVITA-X6'
print('=== HOST ROW ===')
cols = [d[0] for d in c.execute('PRAGMA table_info(hosts)').fetchall()]
# pragma returns cid,name,...
colnames = [r[1] for r in c.execute('PRAGMA table_info(hosts)').fetchall()]
row = c.execute('SELECT * FROM hosts WHERE host=?', (h,)).fetchone()
if not row:
    print('NOT FOUND')
else:
    d = dict(zip(colnames, row))
    for k,v in d.items():
        if k in ('last_seen','last_beat','last_alert') and v:
            print(f'{k}={v} age_m={round((now-float(v))/60,1)}')
        else:
            print(f'{k}={v}')

print('=== RECENT CMDS (host or ALL) ===')
for cid,ts,tgt,cmd in c.execute(
    'SELECT id,ts,target,substr(cmd,1,200) FROM cmds WHERE target=? OR target="ALL" ORDER BY id DESC LIMIT 40',
    (h,),
):
    print(f'#{cid} age_m={round((now-ts)/60,1)} tgt={tgt} {cmd!r}')

print('=== RESULTS ===')
for cid,ts,rc,out in c.execute(
    'SELECT cmd_id,ts,rc,out FROM results WHERE host=? ORDER BY ts DESC LIMIT 20',
    (h,),
):
    print(f'--- #{cid} rc={rc} age_m={round((now-ts)/60,1)} ---')
    print((out or '')[:3000])

print('=== JOBS ===')
for j in c.execute(
    'SELECT id,name,target,status,attempts,cmd_id,note,updated FROM jobs WHERE target=? OR target="ALL" ORDER BY id DESC LIMIT 25',
    (h,),
):
    print(j)

print('=== AUDIT (evita) ===')
for a in c.execute(
    "SELECT id,ts,actor,action,substr(detail,1,160) FROM audit WHERE detail LIKE '%EVITA%' OR detail LIKE '%evita%' ORDER BY id DESC LIMIT 20"
):
    print(a)

print('=== POLICY ===')
for p in c.execute('SELECT id,kind,pattern,action,scope,note FROM policy ORDER BY id DESC LIMIT 30'):
    print(p)

print('=== RMM HIST ===')
for r in c.execute(
    'SELECT id,ts,host,substr(rmm,1,200) FROM rmm_hist WHERE host=? ORDER BY id DESC LIMIT 15',
    (h,),
):
    print(r[0], 'age_m', round((now-r[1])/60,1), r[3])
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
    with sftp.file("/tmp/evita_deep.py", "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/evita_deep.py", timeout=90)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err.strip():
        print("STDERR", err)
    ssh.close()


if __name__ == "__main__":
    main()
