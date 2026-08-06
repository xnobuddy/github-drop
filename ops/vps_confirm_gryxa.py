#!/usr/bin/env python3
from __future__ import annotations

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
    cmd = (
        r'echo ===LOG=== & '
        r'if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_RECOVER_LOG) & '
        r'echo ===SC=== & '
        r'sc query "ScreenConnect Client (36e506ff016b2151)" & '
        r'echo ===DIR=== & '
        r'if exist "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)\ScreenConnect.ClientService.exe" (echo DIR_OK) else (echo DIR_MISSING) & '
        r'echo STATUS_DONE'
    )
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/confirm_cmd.txt", "w") as f:
        f.write(cmd)
    py = r"""
import sqlite3, time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/confirm_cmd.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,'ADMINIS-0ET5284',cmd))
cid=int(cur.lastrowid)
con.commit()
print('queued', cid)
row=con.execute("SELECT state,siege,rmm,last_seen,last_beat,guard FROM hosts WHERE host='ADMINIS-0ET5284'").fetchone()
print('HOST', row)
print('digest_age_m', round((now-row[3])/60,1) if row and row[3] else None)
print('beat_age_m', round((now-row[4])/60,1) if row and row[4] else None)
con.close()
"""
    with sftp.file("/tmp/qconfirm.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qconfirm.py", timeout=30)
    print(o.read().decode(), e.read().decode())

    for i in range(20):
        time.sleep(15)
        poll = r"""
import sqlite3,os,time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
r=con.execute("SELECT cmd_id,rc,out FROM results WHERE host='ADMINIS-0ET5284' ORDER BY ts DESC LIMIT 1").fetchone()
print('LATEST', r[0] if r else None, r[1] if r else None)
if r and r[2] and 'STATUS_DONE' in r[2]:
    print(r[2])
    print('DONE')
row=con.execute("SELECT state,siege,rmm,last_seen FROM hosts WHERE host='ADMINIS-0ET5284'").fetchone()
print('state', row[0], 'siege', repr(row[1]))
print('rmm', row[2])
print('digest_age_m', round((now-row[3])/60,1) if row and row[3] else None)
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/pconfirm.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, e = ssh.exec_command("python3 /tmp/pconfirm.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        print(f"--- {i} ---")
        print(text)
        if "DONE" in text:
            break
    ssh.close()


if __name__ == "__main__":
    main()
