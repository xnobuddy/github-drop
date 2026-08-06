#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"
STATUS = (
    r"powershell -NoProfile -NonInteractive -Command "
    r"\"$ErrorActionPreference='SilentlyContinue'; "
    r"Write-Output '===SVC==='; "
    r"Get-CimInstance Win32_Service | Where-Object { $_.Name -match '36e506ff' } | "
    r"ForEach-Object { $_.Name + ' | ' + $_.State }; "
    r"if(-not (Get-CimInstance Win32_Service | Where-Object { $_.Name -match '36e506ff' })){ 'SVC_MISSING' }; "
    r"Write-Output '===DIR==='; "
    r"$pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'); "
    r"$d=Join-Path $pf86 'ScreenConnect Client (36e506ff016b2151)'; "
    r"if(Test-Path -LiteralPath $d){'DIR_EXISTS'} else {'DIR_MISSING'}; "
    r"Write-Output '===LOG==='; "
    r"if(Test-Path 'C:\Users\Public\gryxa_recover.log'){ Get-Content 'C:\Users\Public\gryxa_recover.log' } else { 'NO_RECOVER_LOG' }; "
    r"Write-Output '===MSI_TAIL==='; "
    r"if(Test-Path 'C:\ProgramData\WinRTCS\msi_gryxa_install.log'){ Get-Content 'C:\ProgramData\WinRTCS\msi_gryxa_install.log' -Tail 25 } else { 'no msi log' }; "
    r"Write-Output 'STATUS_DONE'\""
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
    with sftp.file("/tmp/status_cmd.txt", "w") as f:
        f.write(STATUS)
    py = f"""
import sqlite3, time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cmd=open('/tmp/status_cmd.txt',encoding='utf-8').read().strip()
# show 120 first
r=con.execute('SELECT rc,substr(out,1,500) FROM results WHERE cmd_id=120 AND host=?',({TARGET!r},)).fetchone()
print('cmd120', r)
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},cmd))
print('status', cur.lastrowid)
con.commit(); con.close()
"""
    with sftp.file("/tmp/qstat.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qstat.py", timeout=30)
    print(o.read().decode(), e.read().decode())

    # wait for status result
    for i in range(24):
        time.sleep(15)
        _, o, e = ssh.exec_command(
            "sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db; "
            "sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null; "
            "sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null; "
            "python3 -c \""
            "import sqlite3; con=sqlite3.connect('/tmp/fleet_ro.db'); "
            "r=con.execute('SELECT cmd_id,rc,length(out),substr(out,1,3500) FROM results WHERE host=\\'ADMINIS-0ET5284\\' ORDER BY ts DESC LIMIT 1').fetchone(); "
            "print(r[0] if r else 'none', r[1] if r else '', r[2] if r else 0); "
            "print(r[3] if r else ''); "
            "h=con.execute('SELECT state,rmm,last_seen FROM hosts WHERE host=\\'ADMINIS-0ET5284\\'').fetchone(); print('HOST',h)"
            "\"",
            timeout=60,
        )
        text = o.read().decode("utf-8", "replace")
        print(f"--- poll {i} ---")
        print(text)
        if "STATUS_DONE" in text or "RECOVER=OK" in text or "RECOVER=FAIL" in text:
            break
        if "NO_RECOVER_LOG" in text and "STATUS_DONE" in text:
            break
    ssh.close()


if __name__ == "__main__":
    main()
