#!/usr/bin/env python3
"""Upload EVITA forensics PS1, launch via schtasks, wait, pull output."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "PC-EVITA-X6"
LOCAL = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_evita_forensics.ps1")
OUT_LOCAL = Path(r"C:\Users\nobuddy\Desktop\evita_forensics_out.txt")

LAUNCH = (
    r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
    r'-H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5" '
    r'--connect-timeout 15 --max-time 60 '
    r'-o C:\Users\Public\evita_forensics.ps1 '
    r'https://debian.seczio.com/winrtcs/winrtcs_evita_forensics.ps1 '
    r' & del /f /q C:\Users\Public\evita_forensics.txt C:\Users\Public\evita_forensics.done '
    r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\EvitaForensics" '
    r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\evita_forensics.ps1" '
    r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
    r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\EvitaForensics" '
    r' & echo FORENSICS_QUEUED'
)

PULL = (
    r'if exist C:\Users\Public\evita_forensics.done (echo DONE_OK) else (echo DONE_MISSING) & '
    r'if exist C:\Users\Public\evita_forensics.txt (type C:\Users\Public\evita_forensics.txt) else (echo NO_FORENSICS_FILE) & '
    r'echo PULL_DONE'
)


def ssh_connect() -> paramiko.SSHClient:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    return ssh


def queue_cmd(ssh: paramiko.SSHClient, body: str, label: str) -> int:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/evita_cmd_body.txt", "w") as f:
        f.write(body)
    py = f"""
import sqlite3, time
con=sqlite3.connect('/opt/winrtcs/fleet.db')
cmd=open('/tmp/evita_cmd_body.txt',encoding='utf-8').read().strip()
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),{TARGET!r},cmd[:4000]))
cid=int(cur.lastrowid)
con.commit(); con.close()
print(cid)
"""
    with sftp.file("/tmp/q1.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/q1.py", timeout=30)
    cid = int(o.read().decode().strip().splitlines()[-1])
    print(label, cid)
    return cid


def wait_result(ssh: paramiko.SSHClient, cid: int, needle: str, rounds: int = 24) -> str:
    for i in range(rounds):
        time.sleep(15)
        poll = f"""
import sqlite3,os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
r=c.execute('SELECT rc,out FROM results WHERE cmd_id=? AND host=?',({cid},{TARGET!r})).fetchone()
print('FOUND' if r else 'WAIT')
if r:
    print('RC', r[0])
    print(r[1] or '')
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/wres.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, e = ssh.exec_command("python3 /tmp/wres.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        print(f"[{label_wait(cid)} poll {i}] {text[:200].splitlines()[0] if text else ''}")
        if text.startswith("FOUND") and needle in text:
            return text
    return text


def label_wait(cid: int) -> str:
    return str(cid)


def main() -> None:
    ssh = ssh_connect()
    sftp = ssh.open_sftp()
    sftp.put(str(LOCAL), "/tmp/winrtcs_evita_forensics.ps1")
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_evita_forensics.ps1 /opt/winrtcs/repo/winrtcs_evita_forensics.ps1 && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_evita_forensics.ps1 && echo OK",
        timeout=30,
    )
    print(o.read().decode(), e.read().decode())

    launch_id = queue_cmd(ssh, LAUNCH, "launch")
    launch_out = wait_result(ssh, launch_id, "FORENSICS_QUEUED", rounds=20)
    print(launch_out[:1500])

    print("waiting 100s for forensics script...")
    time.sleep(100)

    pull_id = queue_cmd(ssh, PULL, "pull")
    pull_out = wait_result(ssh, pull_id, "PULL_DONE", rounds=20)
    print(pull_out[:20000])
    OUT_LOCAL.write_text(pull_out, encoding="utf-8")
    print("wrote", OUT_LOCAL, "bytes", OUT_LOCAL.stat().st_size)
    ssh.close()


if __name__ == "__main__":
    main()
