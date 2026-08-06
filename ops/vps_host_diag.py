#!/usr/bin/env python3
"""Diagnose one host from fleet.db + recent cmd results."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
TARGET = "ADMINIS-0ET5284"


def run(ssh: paramiko.SSHClient, cmd: str) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=90)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    print(o)
    if e.strip():
        print("STDERR:", e)
    return o


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    # copy under winrtcs home so we can read without WAL write issues
    run(
        ssh,
        "sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db && "
        "sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null; "
        "sudo cp -f /opt/winrtcs/fleet.db-shm /tmp/fleet_ro.db-shm 2>/dev/null; "
        "sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-* 2>/dev/null; true",
    )
    script = r'''
import sqlite3, time
con=sqlite3.connect('/tmp/fleet_ro.db')
h=%r
now=time.time()
row=con.execute('SELECT host,state,streak,extkill,guard,siege,suspects,rmm,last_seen,last_beat,agent,maint FROM hosts WHERE host=?',(h,)).fetchone()
print('=== HOST ===')
if not row:
    print('NOT FOUND')
else:
    keys=['host','state','streak','extkill','guard','siege','suspects','rmm','last_seen','last_beat','agent','maint']
    d=dict(zip(keys,row))
    for k,v in d.items():
        if k in ('last_seen','last_beat') and v:
            print(f'{k}={v} age_m={(now-v)/60:.1f}')
        else:
            print(f'{k}={v}')
print('=== RECENT CMDS ===')
cmds=con.execute('SELECT id,ts,target,substr(cmd,1,220) FROM cmds WHERE target=? OR target="ALL" ORDER BY id DESC LIMIT 30',(h,)).fetchall()
for cid,ts,tgt,cmd in cmds:
    print(f'#{cid} tgt={tgt} age_m={(now-ts)/60:.1f} cmd={cmd!r}')
print('=== RESULTS ===')
res=con.execute('SELECT cmd_id,ts,rc,out FROM results WHERE host=? ORDER BY ts DESC LIMIT 12',(h,)).fetchall()
for cid,ts,rc,out in res:
    print(f'--- #{cid} rc={rc} age_m={(now-ts)/60:.1f} ---')
    print((out or '(empty)')[:4000])
print('=== JOBS ===')
for j in con.execute('SELECT id,name,target,status,attempts,cmd_id,updated FROM jobs WHERE target=? OR target="ALL" ORDER BY id DESC LIMIT 20',(h,)):
    print(j)
con.close()
''' % TARGET
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/host_diag.py", "w") as f:
        f.write(script)
    sftp.close()
    run(ssh, "python3 /tmp/host_diag.py")
    ssh.close()


if __name__ == "__main__":
    main()
