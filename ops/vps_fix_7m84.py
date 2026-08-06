#!/usr/bin/env python3
"""Fix Gryxa on DESKTOP-7M84CP8 now that it is online."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HOST = "DESKTOP-7M84CP8"
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
GFP = "36e506ff016b2151"

PROBE = (
    f'sc query "ScreenConnect Client ({GFP})" & '
    r'echo --- & '
    r'reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ('
    + GFP
    + r')" /v ImagePath & '
    r'echo PROBE_DONE'
)

FIX = (
    f'sc start "ScreenConnect Client ({GFP})" & '
    rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
    r'--connect-timeout 12 --max-time 60 -o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 12 --max-time 45 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 12 --max-time 45 -o C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_agent.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 12 --max-time 30 -o C:\ProgramData\WinRTCS\killlist.cfg '
    r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
    r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd '
    r' & del /f /q C:\ProgramData\WinRTCS\guard.lock C:\ProgramData\WinRTCS\extkill.cnt '
    r' & >C:\ProgramData\WinRTCS\streak.cnt echo 0 '
    r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
    r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r'/TR "cmd.exe /c C:\Users\Public\gryxa_recover4.cmd --detached" '
    r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
    r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r' & echo FIX_QUEUED'
)

VERIFY = (
    f'sc query "ScreenConnect Client ({GFP})" & '
    r'echo -----LOG----- & '
    r'(if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_LOG)) & '
    r'findstr /C:"GVER=0.2.1" C:\ProgramData\WinRTCS\winrtcs_guard.cmd & '
    r'echo VERIFY_DONE'
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


def queue(ssh: paramiko.SSHClient, body: str) -> int:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
        f.write(body)
    with sftp.file("/tmp/q.py", "w") as f:
        f.write(
            "import sqlite3,time\n"
            "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
            "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
            "cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',"
            f"(time.time(),{HOST!r},cmd[:4000]))\n"
            "print(cur.lastrowid); con.commit()\n"
        )
    sftp.close()
    _, o, _ = ssh.exec_command("sudo python3 /tmp/q.py", timeout=30)
    return int(o.read().decode().strip().splitlines()[-1])


def wait(ssh: paramiko.SSHClient, cid: int, needle: str, rounds: int = 24) -> str:
    last = ""
    for i in range(rounds):
        time.sleep(15)
        poll = (
            "import sqlite3,os\n"
            "os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')\n"
            "os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')\n"
            "os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')\n"
            "c=sqlite3.connect('/tmp/fleet_ro.db')\n"
            f"r=c.execute('SELECT rc,out FROM results WHERE cmd_id=? AND host=?',({cid},{HOST!r})).fetchone()\n"
            "print('FOUND' if r else 'WAIT')\n"
            "if r:\n print('RC', r[0])\n print(r[1] or '')\n"
        )
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/w.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/w.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        last = text
        print(f"[{cid} {i}] {(text.splitlines() or [''])[0]}")
        if text.startswith("FOUND") and needle in text:
            return text
    return last


def snap(ssh: paramiko.SSHClient) -> None:
    py = f"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db'); c.row_factory=sqlite3.Row
now=time.time()
r=dict(c.execute('SELECT * FROM hosts WHERE host=?',({HOST!r},)).fetchone())
for k in ('last_seen','last_beat'):
    if r.get(k): r[k+'_ago_min']=round((now-float(r[k]))/60,1)
print(json.dumps({{k:r.get(k) for k in ('host','state','agent','guard','rmm','last_seen_ago_min','last_beat_ago_min','streak','extkill')}}, default=str))
# last cmds
for x in c.execute('''SELECT c.id, substr(c.cmd,1,50), r.rc, substr(replace(coalesce(r.out,''),char(10),'|'),1,180)
 FROM cmds c LEFT JOIN results r ON r.cmd_id=c.id WHERE c.target=? ORDER BY c.id DESC LIMIT 5''', ({HOST!r},)):
    print('CMD', x)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/snap7.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/snap7.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))


def main() -> None:
    ssh = ssh_connect()
    print("=== before ===")
    snap(ssh)

    # Check if cmd 208 already ran recover
    print("=== probe ===")
    cid = queue(ssh, PROBE)
    print("probe", cid)
    probe = wait(ssh, cid, "PROBE_DONE")
    print(probe[:2500])
    Path(r"C:\Users\nobuddy\Desktop\7m84_probe.txt").write_text(probe, encoding="utf-8")

    running = "RUNNING" in probe and "1060" not in probe[:600]
    if running:
        print("already RUNNING — force guard only")
        light = (
            rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
            r'--connect-timeout 12 --max-time 45 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
            r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
            r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd '
            r' & del /f /q C:\ProgramData\WinRTCS\guard.lock '
            r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
            r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\ForceGuard" '
            r'/TR "cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd" '
            r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
            r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\ForceGuard" '
            r' & echo FIX_QUEUED'
        )
        cid2 = queue(ssh, light)
    else:
        print("not running — full recover")
        cid2 = queue(ssh, FIX)
    print("fix", cid2)
    print(wait(ssh, cid2, "FIX_QUEUED")[:2000])

    print("waiting 3.5 min...")
    time.sleep(210)

    cid3 = queue(ssh, VERIFY)
    print("verify", cid3)
    ver = wait(ssh, cid3, "VERIFY_DONE")
    print(ver[:4000])
    Path(r"C:\Users\nobuddy\Desktop\7m84_verify.txt").write_text(ver, encoding="utf-8")

    print("=== after ===")
    snap(ssh)
    ssh.close()


if __name__ == "__main__":
    main()
