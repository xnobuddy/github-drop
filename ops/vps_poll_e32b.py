#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROBE = (
    r'echo ===SC=== & sc query "ScreenConnect Client (36e506ff016b2151)" & '
    r'echo ===DIR=== & '
    r'if exist "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)\ScreenConnect.ClientService.exe" '
    r'(echo DIR_OK) else (echo DIR_MISSING) & '
    r'echo ===LOG=== & '
    r'if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_RECOVER_LOG) & '
    r'echo PROBE_DONE'
)


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
    with sftp.file("/tmp/probe2.txt", "w") as f:
        f.write(PROBE)
    py = r"""
import sqlite3, time, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
now = time.time()
h = 'E32072484D'
row = c.execute('SELECT state,guard,siege,rmm,last_seen,last_beat FROM hosts WHERE host=?',(h,)).fetchone()
print('HOST', row)
if row:
    print('digest_age_m', round((now-row[4])/60,1) if row[4] else None)
    print('beat_age_m', round((now-row[5])/60,1) if row[5] else None)
for cid in (132, 131, 130):
    r = c.execute('SELECT rc, substr(out,1,600) FROM results WHERE cmd_id=? AND host=?',(cid,h)).fetchone()
    print('CMD', cid, r[0] if r else 'NONE')
    if r: print(r[1])
# queue fresh probe
con = sqlite3.connect('/opt/winrtcs/fleet.db')
cmd = open('/tmp/probe2.txt',encoding='utf-8').read().strip()
cur = con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),h,cmd))
print('probe2', int(cur.lastrowid))
con.commit(); con.close()
"""
    with sftp.file("/tmp/pe32b.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/pe32b.py", timeout=60)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))

    # wait for probe2
    for i in range(16):
        time.sleep(12)
        poll = r"""
import sqlite3,os,time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
h='E32072484D'
r=c.execute("SELECT cmd_id,rc,out FROM results WHERE host=? ORDER BY ts DESC LIMIT 1",(h,)).fetchone()
print('LATEST', r[0] if r else None, r[1] if r else None)
if r and r[2] and 'PROBE_DONE' in r[2]:
    print(r[2])
    print('DONE')
row=c.execute('SELECT state,rmm,last_seen FROM hosts WHERE host=?',(h,)).fetchone()
print('state', row[0] if row else None)
print('rmm', row[1] if row else None)
print('digest_age_m', round((now-row[2])/60,1) if row and row[2] else None)
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/pe32c.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, e = ssh.exec_command("python3 /tmp/pe32c.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        print(f"--- {i} ---")
        print(text)
        if "DONE" in text:
            break
    ssh.close()


if __name__ == "__main__":
    main()
