#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"
# No PowerShell $ vars — batch-safe for agent cmd channel.
CMD = r"""
echo ===LOG===
if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_RECOVER_LOG)
echo ===SC===
sc query "ScreenConnect Client (36e506ff016b2151)"
echo ===DIR===
if exist "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)\ScreenConnect.ClientService.exe" (echo DIR_OK) else (echo DIR_MISSING)
echo ===SCRIPT===
if exist C:\Users\Public\gryxa_recover.cmd (echo SCRIPT_OK) else (echo SCRIPT_MISSING)
echo STATUS_DONE
""".strip().replace("\n", " & ")


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
    with sftp.file("/tmp/st_simple.txt", "w") as f:
        f.write(CMD)
    py = f"""
import sqlite3,time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/st_simple.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},cmd))
print('queued',int(cur.lastrowid))
con.commit(); con.close()
"""
    with sftp.file("/tmp/qst.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qst.py", timeout=30)
    print(o.read().decode(), e.read().decode())
    cid = None
    for i in range(20):
        time.sleep(12)
        poll = r"""
import sqlite3,time,os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null')
con=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
h='ADMINIS-0ET5284'
r=con.execute('SELECT cmd_id,rc,out,ts FROM results WHERE host=? ORDER BY ts DESC LIMIT 1',(h,)).fetchone()
print('LATEST', r[0] if r else None, r[1] if r else None)
if r: print(r[2] or '')
row=con.execute('SELECT state,rmm,last_seen,last_beat FROM hosts WHERE host=?',(h,)).fetchone()
print('HOST_STATE', row[0] if row else None)
print('RMM', row[1] if row else None)
if row and row[2]: print('digest_age_m', round((now-row[2])/60,1))
if row and row[3]: print('beat_age_m', round((now-row[3])/60,1))
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/pollst.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, e = ssh.exec_command("python3 /tmp/pollst.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        print(f"--- poll {i} ---")
        print(text)
        if "STATUS_DONE" in text:
            break
    ssh.close()


if __name__ == "__main__":
    main()
