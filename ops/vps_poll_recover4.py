#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def run_py(ssh, code: str) -> str:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/p4.py", "w") as f:
        f.write(code)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/p4.py", timeout=60)
    return o.read().decode("utf-8", "replace") + e.read().decode("utf-8", "replace")


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )

    # wait for 123 result
    for i in range(20):
        text = run_py(
            ssh,
            r"""
import sqlite3,os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
r=con.execute("SELECT rc,out FROM results WHERE cmd_id=123 AND host='ADMINIS-0ET5284'").fetchone()
print('FOUND' if r else 'WAIT')
if r: print(r[0]); print(r[1])
""",
        )
        print(f"123 poll {i}:", text[:500])
        if text.startswith("FOUND"):
            break
        time.sleep(15)

    # wait for recover work (~2.5 min more)
    print("waiting for msiexec window...")
    time.sleep(150)

    # queue status
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
    with sftp.file("/tmp/st4.txt", "w") as f:
        f.write(cmd)
    sftp.close()
    text = run_py(
        ssh,
        r"""
import sqlite3,time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
cmd=open('/tmp/st4.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),'ADMINIS-0ET5284',cmd))
print('status_cmd', int(cur.lastrowid))
con.commit(); con.close()
""",
    )
    print(text)
    try:
        status_id = int(text.strip().split()[-1])
    except Exception:
        status_id = 0

    for i in range(25):
        time.sleep(12)
        text = run_py(
            ssh,
            f"""
import sqlite3,os,time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
r=con.execute("SELECT rc,out FROM results WHERE cmd_id={status_id} AND host='ADMINIS-0ET5284'").fetchone()
print('FOUND' if r else 'WAIT')
if r:
    print('RC', r[0])
    print(r[1] or '')
row=con.execute("SELECT state,rmm,last_seen,last_beat FROM hosts WHERE host='ADMINIS-0ET5284'").fetchone()
print('HOST', row[0] if row else None)
print('RMM', row[1] if row else None)
if row and row[2]: print('digest_age_m', round((now-row[2])/60,1))
""",
        )
        print(f"status poll {i}:")
        print(text)
        if text.startswith("FOUND"):
            break
    ssh.close()


if __name__ == "__main__":
    main()
