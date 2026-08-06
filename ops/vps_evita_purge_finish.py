#!/usr/bin/env python3
"""Finish EVITA purge: wait, pull output, push killlist, probe Gryxa."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TARGET = "PC-EVITA-X6"
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_purge_out.txt")


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

    # Check if launch 144 already completed
    check = (
        "import sqlite3,os\n"
        "os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')\n"
        "os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')\n"
        "os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')\n"
        "c=sqlite3.connect('/tmp/fleet_ro.db')\n"
        "r=c.execute('SELECT rc,substr(out,1,500) FROM results WHERE cmd_id=144').fetchone()\n"
        "print(r)\n"
        "r2=c.execute(\"SELECT id,substr(cmd,1,40) FROM cmds WHERE target='PC-EVITA-X6' ORDER BY id DESC LIMIT 5\").fetchall()\n"
        "print(r2)\n"
    )
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/chk.py", "w") as f:
        f.write(check)
    sftp.close()
    _, o, _ = ssh.exec_command("python3 /tmp/chk.py", timeout=30)
    print("chk", o.read().decode("utf-8", "replace"))

    # If purge.done missing, re-launch
    rel = (
        r'(if exist C:\Users\Public\evita_purge.done (echo ALREADY_DONE) else (echo NEED_RUN))'
        r' & echo CHECK_DONE'
    )
    cid = queue(ssh, rel)
    print("check done flag", cid)
    st = wait_result(ssh, cid, "CHECK_DONE", rounds=16)
    print(st[:800])

    if "NEED_RUN" in st or "ALREADY_DONE" not in st:
        launch = (
            rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
            rf'-H "Authorization: Bearer {TOKEN}" '
            r'--connect-timeout 15 --max-time 60 '
            r'-o C:\Users\Public\evita_purge.ps1 '
            r'https://debian.seczio.com/winrtcs/winrtcs_evita_purge.ps1 '
            r' & del /f /q C:\Users\Public\evita_purge.txt C:\Users\Public\evita_purge.done '
            r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\EvitaPurge" '
            r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\evita_purge.ps1" '
            r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
            r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\EvitaPurge" '
            r' & echo PURGE_QUEUED'
        )
        cid2 = queue(ssh, launch)
        print("relaunch", cid2)
        print(wait_result(ssh, cid2, "PURGE_QUEUED", rounds=20)[:1200])
        print("wait 100s...")
        time.sleep(100)
    else:
        print("purge already done, pulling...")

    pull = (
        r'(if exist C:\Users\Public\evita_purge.done (echo DONE_OK) else (echo DONE_MISSING))'
        r' & (if exist C:\Users\Public\evita_purge.txt (echo FILE_OK & type C:\Users\Public\evita_purge.txt) else (echo NO_PURGE_FILE))'
        r' & echo PULL_DONE'
    )
    cid3 = queue(ssh, pull)
    print("pull", cid3)
    out = wait_result(ssh, cid3, "PULL_DONE", rounds=20)
    print(out[:20000])
    OUT.write_text(out, encoding="utf-8")

    kl = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
        rf'-H "Authorization: Bearer {TOKEN}" '
        r'--connect-timeout 15 --max-time 60 '
        r'-o C:\ProgramData\WinRTCS\killlist.cfg '
        r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
        r' & echo KILLLIST_RC=%ERRORLEVEL% & findstr /i SCWatchdog C:\ProgramData\WinRTCS\killlist.cfg & echo KL_DONE'
    )
    cid4 = queue(ssh, kl)
    print("kl", cid4)
    print(wait_result(ssh, cid4, "KL_DONE", rounds=20)[:2500])

    probe = (
        r'sc query "ScreenConnect Client (36e506ff016b2151)" & '
        r'sc query "ScreenConnect Client (5f6010579852e507)" & '
        r'echo PROBE_DONE'
    )
    cid5 = queue(ssh, probe)
    print("probe", cid5)
    print(wait_result(ssh, cid5, "PROBE_DONE", rounds=20)[:3000])
    ssh.close()


if __name__ == "__main__":
    main()
