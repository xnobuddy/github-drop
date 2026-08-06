#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"
CMD = (
    r"echo ===RECOVER_LOG=== & "
    r"if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else echo NO_RECOVER_LOG & "
    r"echo ===SC=== & sc query \"ScreenConnect Client (36e506ff016b2151)\" & "
    r"echo ===DIR=== & dir \"C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)\" & "
    r"echo ===MSI_TAIL=== & powershell -NoP -NonI -C \"if(Test-Path 'C:\ProgramData\WinRTCS\msi_gryxa_install.log'){"
    r"Get-Content 'C:\ProgramData\WinRTCS\msi_gryxa_install.log' -Tail 40} else {'no msi log'}\" & "
    r"echo CHECK_DONE"
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
    with sftp.file("/tmp/check_body.txt", "w") as f:
        f.write(CMD)
    py = f"""
import sqlite3, time
cmd=open('/tmp/check_body.txt',encoding='utf-8').read().strip()
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(now,{TARGET!r},cmd))
print('queued', cur.lastrowid)
con.commit(); con.close()
"""
    with sftp.file("/tmp/qcheck.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qcheck.py", timeout=30)
    print(o.read().decode(), e.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
