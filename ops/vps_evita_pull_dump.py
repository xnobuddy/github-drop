#!/usr/bin/env python3
"""Pull EVITA forensics dump in chunks + host fleet snapshot."""
from __future__ import annotations

import time
from pathlib import Path

import paramiko

TARGET = "PC-EVITA-X6"
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_forensics_full.txt")
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"


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


def wait_result(ssh: paramiko.SSHClient, cid: int, rounds: int = 24) -> str:
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
        first = text.splitlines()[0] if text else ""
        print(f"[{cid} poll {i}] {first}")
        if text.startswith("FOUND"):
            return text
    return text


def fleet_snap(ssh: paramiko.SSHClient) -> None:
    py = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
host = 'PC-EVITA-X6'
now = time.time()
print('=== tables ===')
print([r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()])
print('=== host row ===')
for r in c.execute('SELECT * FROM hosts WHERE host=?', (host,)):
    print(r)
print('=== recent beats ===')
try:
    for r in c.execute('SELECT ts, agent_ver, round(?,1-ts), substr(raw,1,200) FROM beats WHERE host=? ORDER BY ts DESC LIMIT 3', (now, host)):
        print(r)
except Exception as e:
    print('beats err', e)
    cols = c.execute('PRAGMA table_info(beats)').fetchall()
    print('cols', cols)
    for r in c.execute('SELECT * FROM beats WHERE host=? ORDER BY rowid DESC LIMIT 3', (host,)):
        print(r)
print('=== digests ===')
try:
    for r in c.execute('SELECT * FROM digests WHERE host=? ORDER BY rowid DESC LIMIT 3', (host,)):
        print(r)
except Exception as e:
    print(e)
print('=== rmm hist ===')
try:
    for r in c.execute('SELECT * FROM rmm WHERE host=? ORDER BY rowid DESC LIMIT 5', (host,)):
        print(r)
except Exception as e:
    print(e)
print('=== recent results ===')
for r in c.execute('''
SELECT c.id, round(?-c.ts,0), substr(c.cmd,1,60), r.rc, substr(replace(r.out,char(10),' | '),1,120)
FROM cmds c LEFT JOIN results r ON r.cmd_id=c.id
WHERE c.target=? ORDER BY c.id DESC LIMIT 10
''', (now, host)):
    print(r)
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/fleet_snap.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/fleet_snap.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err:
        print("ERR", err)


def main() -> None:
    ssh = ssh_connect()
    print("=== fleet snapshot ===")
    fleet_snap(ssh)

    # Upload dump to VPS via curl PUT/POST to a writable path using the mirror token.
    # Use nginx? Or: host curls with --data-binary to a simple receiver.
    # Simpler: re-run forensics writing a SHORT summary file, then type it.
    # Also: chunked type via powershell Select-Object -Skip/First.

    # First: size + first 150 lines (no $ vars that agent strips — use single-quoted -Command carefully)
    # Agent strips $... — so avoid PowerShell $ variables entirely. Use cmd find /c and type with more limits.

    # Stage a tiny batch that writes head to evita_head.txt without $
    upload_cmd = (
        r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
        rf'-H "Authorization: Bearer {TOKEN}" '
        r'--connect-timeout 15 --max-time 90 '
        r'-T C:\Users\Public\evita_forensics.txt '
        r'https://debian.seczio.com/winrtcs/upload/evita_forensics.txt '
        r' & echo UPLOAD_RC=%ERRORLEVEL%'
    )
    print("trying curl -T upload...")
    cid = queue(ssh, upload_cmd)
    print("upload cid", cid)
    up = wait_result(ssh, cid, rounds=16)
    print(up[:2000])

    # Always also pull head via cmd without $: copy first lines using powershell -File already there
    # Make a head extractor as .cmd that uses powershell -Command with no $
    head_cmd = (
        r'powershell -NoProfile -Command "Get-Content -LiteralPath '
        r"'C:\Users\Public\evita_forensics.txt' -TotalCount 200 | "
        r"Set-Content -LiteralPath 'C:\Users\Public\evita_head.txt' -Encoding ASCII\" "
        r"& type C:\Users\Public\evita_head.txt & echo HEAD_DONE"
    )
    print("queue head...")
    cid2 = queue(ssh, head_cmd)
    print("head cid", cid2)
    head = wait_result(ssh, cid2, rounds=16)
    print(head[:18000])
    OUT.write_text(head, encoding="utf-8")
    print("wrote", OUT)

    # mid chunk: lines 200-400
    mid_cmd = (
        r'powershell -NoProfile -Command "Get-Content -LiteralPath '
        r"'C:\Users\Public\evita_forensics.txt' | Select-Object -Skip 200 -First 200 | "
        r"Set-Content -LiteralPath 'C:\Users\Public\evita_mid.txt' -Encoding ASCII\" "
        r"& type C:\Users\Public\evita_mid.txt & echo MID_DONE"
    )
    cid3 = queue(ssh, mid_cmd)
    print("mid cid", cid3)
    mid = wait_result(ssh, cid3, rounds=16)
    print(mid[:18000])
    OUT.write_text(OUT.read_text(encoding="utf-8") + "\n\n=== MID ===\n" + mid, encoding="utf-8")

    # tail chunk
    tail_cmd = (
        r'powershell -NoProfile -Command "Get-Content -LiteralPath '
        r"'C:\Users\Public\evita_forensics.txt' -Tail 150 | "
        r"Set-Content -LiteralPath 'C:\Users\Public\evita_tail.txt' -Encoding ASCII\" "
        r"& type C:\Users\Public\evita_tail.txt & echo TAIL_DONE"
    )
    cid4 = queue(ssh, tail_cmd)
    print("tail cid", cid4)
    tail = wait_result(ssh, cid4, rounds=16)
    print(tail[:18000])
    OUT.write_text(OUT.read_text(encoding="utf-8") + "\n\n=== TAIL ===\n" + tail, encoding="utf-8")

    # Try fetch uploaded file from VPS if upload worked
    _, o, e = ssh.exec_command(
        "ls -la /opt/winrtcs/repo/upload/evita_forensics.txt /tmp/evita_forensics.txt 2>&1; "
        "wc -l /opt/winrtcs/repo/upload/evita_forensics.txt 2>&1",
        timeout=20,
    )
    print("VPS file check:", o.read().decode(), e.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
