#!/usr/bin/env python3
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "PC-EVITA-X6"
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
LOCAL = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_evita_purge2.ps1")
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_purge2_out.txt")


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


def queue(ssh: paramiko.SSHClient, body: str) -> int:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/evita_cmd_body.txt", "w") as f:
        f.write(body)
    with sftp.file("/tmp/q_evita.py", "w") as f:
        f.write(
            "import sqlite3,time\n"
            "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
            "cmd=open('/tmp/evita_cmd_body.txt',encoding='utf-8').read().strip()\n"
            "cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',"
            f"(time.time(),{TARGET!r},cmd[:4000]))\n"
            "print(cur.lastrowid); con.commit()\n"
        )
    sftp.close()
    _, o, _ = ssh.exec_command("sudo python3 /tmp/q_evita.py", timeout=30)
    return int(o.read().decode().strip().splitlines()[-1])


def wait_result(ssh: paramiko.SSHClient, cid: int, needle: str, rounds: int = 24) -> str:
    last = ""
    for i in range(rounds):
        time.sleep(15)
        poll = (
            "import sqlite3,os\n"
            "os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')\n"
            "os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')\n"
            "os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')\n"
            "c=sqlite3.connect('/tmp/fleet_ro.db')\n"
            f"r=c.execute('SELECT rc,out FROM results WHERE cmd_id=? AND host=?',"
            f"({cid},{TARGET!r})).fetchone()\n"
            "print('FOUND' if r else 'WAIT')\n"
            "if r:\n"
            "    print('RC', r[0])\n"
            "    print(r[1] or '')\n"
        )
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/wres.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/wres.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        last = text
        print(f"[{cid} poll {i}] {(text.splitlines() or [''])[0]}")
        if text.startswith("FOUND") and needle in text:
            return text
    return last


def main() -> None:
    ssh = ssh_connect()
    sftp = ssh.open_sftp()
    sftp.put(str(LOCAL), "/tmp/winrtcs_evita_purge2.ps1")
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_evita_purge2.ps1 /opt/winrtcs/repo/winrtcs_evita_purge2.ps1 && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_evita_purge2.ps1 && echo OK",
        timeout=20,
    )
    print(o.read().decode(), e.read().decode())

    launch = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
        rf'-H "Authorization: Bearer {TOKEN}" --connect-timeout 15 --max-time 60 '
        r'-o C:\Users\Public\evita_purge2.ps1 '
        r'https://debian.seczio.com/winrtcs/winrtcs_evita_purge2.ps1 '
        r' & del /f /q C:\Users\Public\evita_purge2.txt C:\Users\Public\evita_purge2.done '
        r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\EvitaPurge2" '
        r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\evita_purge2.ps1" '
        r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
        r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\EvitaPurge2" '
        r' & echo PURGE2_QUEUED'
    )
    cid = queue(ssh, launch)
    print("launch", cid)
    print(wait_result(ssh, cid, "PURGE2_QUEUED")[:1000])
    time.sleep(90)
    pull = (
        r'(if exist C:\Users\Public\evita_purge2.done (echo DONE_OK) else (echo DONE_MISSING))'
        r' & (if exist C:\Users\Public\evita_purge2.txt (echo FILE_OK & type C:\Users\Public\evita_purge2.txt) else (echo NOFILE))'
        r' & echo PULL_DONE'
    )
    cid2 = queue(ssh, pull)
    print("pull", cid2)
    out = wait_result(ssh, cid2, "PULL_DONE")
    print(out[:15000])
    OUT.write_text(out, encoding="utf-8")
    ssh.close()


if __name__ == "__main__":
    main()
