#!/usr/bin/env python3
"""Pull full EVITA forensics via fixed cmd chaining + fleet detail."""
from __future__ import annotations

import time
from pathlib import Path

import paramiko

TARGET = "PC-EVITA-X6"
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_forensics_full.txt")

# Parentheses so & always runs after if/else (C15: Spanish OK for our markers)
PULL = (
    r'(if exist C:\Users\Public\evita_forensics.done (echo DONE_OK) else (echo DONE_MISSING))'
    r' & (if exist C:\Users\Public\evita_forensics.txt (echo FILE_OK & type C:\Users\Public\evita_forensics.txt) else (echo NO_FORENSICS_FILE))'
    r' & echo PULL_DONE'
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
        first = text.splitlines()[0] if text else ""
        print(f"[{cid} poll {i}] {first}")
        if text.startswith("FOUND") and needle in text:
            return text
    return last


def fleet_detail(ssh: paramiko.SSHClient) -> None:
    py = r"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
c.row_factory = sqlite3.Row
host = 'PC-EVITA-X6'
now = time.time()
print('NOW', now)
cols = [x[1] for x in c.execute('PRAGMA table_info(hosts)')]
print('HOST_COLS', cols)
row = c.execute('SELECT * FROM hosts WHERE host=?', (host,)).fetchone()
if row:
    d = dict(row)
    for k in ('last_seen','last_beat','last_rmm','ts'):
        if k in d and d[k]:
            try:
                d[k+'_ago_h'] = round((now - float(d[k]))/3600, 2)
            except Exception:
                pass
    print('HOST', json.dumps(d, default=str))
print('=== rmm_hist ===')
try:
    for r in c.execute('SELECT * FROM rmm_hist WHERE host=? ORDER BY rowid DESC LIMIT 8', (host,)):
        print(dict(r))
except Exception as e:
    print(e)
print('=== jobs ===')
try:
    for r in c.execute('SELECT id,kind,status,substr(detail,1,120),ts FROM jobs WHERE host=? ORDER BY id DESC LIMIT 8', (host,)):
        print(dict(r))
except Exception as e:
    # try other schema
    cols = c.execute('PRAGMA table_info(jobs)').fetchall()
    print('jobs cols', cols)
    for r in c.execute('SELECT * FROM jobs WHERE host=? ORDER BY rowid DESC LIMIT 8', (host,)):
        print(dict(r))
print('=== recent cmd results (install/gryxa) ===')
for r in c.execute('''
SELECT c.id, round((?-c.ts)/3600.0,2) as ago_h, substr(c.cmd,1,70) as cmd,
  r.rc, substr(replace(coalesce(r.out,''),char(10),' | '),1,200) as out
FROM cmds c LEFT JOIN results r ON r.cmd_id=c.id
WHERE c.target=? ORDER BY c.id DESC LIMIT 15
''', (now, host)):
    print(dict(r))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/fleet_detail.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/fleet_detail.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err:
        print("ERR", err)


def main() -> None:
    ssh = ssh_connect()
    print("=== fleet detail ===")
    fleet_detail(ssh)
    print("=== pull forensics ===")
    cid = queue(ssh, PULL)
    print("cid", cid)
    out = wait_result(ssh, cid, "PULL_DONE", rounds=20)
    print(out[:25000])
    OUT.write_text(out, encoding="utf-8")
    print("wrote", OUT, "bytes", OUT.stat().st_size)
    ssh.close()


if __name__ == "__main__":
    main()
