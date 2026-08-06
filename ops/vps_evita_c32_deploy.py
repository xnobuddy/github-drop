#!/usr/bin/env python3
"""Deploy C32 fix to VPS, force EVITA agent update + guard, verify healthy."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "PC-EVITA-X6"
ROOT = Path(r"C:\Users\nobuddy\Desktop\Project")
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
FILES = [
    "winrtcs.version",
    "winrtcs.version.sig",
    "winrtcs_agent.cmd",
    "winrtcs_guard.cmd",
    "winrtcs_sidekick.ps1",
    "winrtcs_killlist.cfg",
]


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


def wait_result(ssh: paramiko.SSHClient, cid: int, needle: str, rounds: int = 30) -> str:
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
    for name in FILES:
        sftp.put(str(ROOT / name), f"/tmp/{name}")
    sftp.close()
    cps = " && ".join(f"sudo cp /tmp/{n} /opt/winrtcs/repo/{n}" for n in FILES)
    _, o, e = ssh.exec_command(
        cps + " && sudo chmod 644 /opt/winrtcs/repo/winrtcs.* /opt/winrtcs/repo/winrtcs_*.* "
        "2>/dev/null; grep -E 'GUARD_VER|AGENT_SHA|SIDEKICK' /opt/winrtcs/repo/winrtcs.version; "
        "echo DEPLOY_OK",
        timeout=40,
    )
    print(o.read().decode(), e.read().decode())

    # Force download agent+guard+version and run agent once + force guard
    # Stage a cmd via schtasks so msiexec/guard can run long
    body = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
        r'--connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs.version.remote '
        r'https://debian.seczio.com/winrtcs/winrtcs.version '
        r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
        + TOKEN
        + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
        r'https://debian.seczio.com/winrtcs/winrtcs_agent.cmd '
        r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
        + TOKEN
        + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
        r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
        r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
        + TOKEN
        + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\killlist.cfg '
        r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
        r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
        + TOKEN
        + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_sidekick.ps1 '
        r'https://debian.seczio.com/winrtcs/winrtcs_sidekick.ps1 '
        r' & findstr GUARD_VER C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
        r' & findstr AGENT_VER C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
        r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
        r' & del /f /q C:\ProgramData\WinRTCS\extkill.cnt C:\ProgramData\WinRTCS\fight.cnt '
        r'C:\ProgramData\WinRTCS\gryxa_boost.cnt C:\ProgramData\WinRTCS\killer.flag '
        r' & >C:\ProgramData\WinRTCS\streak.cnt echo 0 '
        r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\ForceGuardC32" '
        r'/TR "cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd" '
        r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
        r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\ForceGuardC32" '
        r' & echo C32_DEPLOYED'
    )
    cid = queue(ssh, body)
    print("deploy cmd", cid)
    print(wait_result(ssh, cid, "C32_DEPLOYED", rounds=20)[:2500])

    print("waiting 3 min for forced guard...")
    time.sleep(180)

    verify = (
        r'findstr /C:"GVER=0.2.1" C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
        r' & findstr /C:"AGENT_VER=0.0.9" C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
        r' & sc query "ScreenConnect Client (36e506ff016b2151)" '
        r' & echo -----GUARD_TAIL----- '
        r' & powershell -NoProfile -Command '
        r'"Get-Content -LiteralPath ''C:\ProgramData\WinRTCS\guard.log'' -Tail 30" '
        r' & echo VERIFY_DONE'
    )
    cid2 = queue(ssh, verify)
    print("verify", cid2)
    out = wait_result(ssh, cid2, "VERIFY_DONE", rounds=20)
    print(out[:12000])
    Path(r"C:\Users\nobuddy\Desktop\evita_c32_verify.txt").write_text(out, encoding="utf-8")

    snap = r"""
import sqlite3,os,time,json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db'); c.row_factory=sqlite3.Row
now=time.time()
r=dict(c.execute("SELECT * FROM hosts WHERE host='PC-EVITA-X6'").fetchone())
for k in ('last_seen','last_beat'):
    if r.get(k): r[k+'_ago_min']=round((now-float(r[k]))/60,1)
print(json.dumps(r, default=str))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/snap.py", "w") as f:
        f.write(snap)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/snap.py", timeout=30)
    print("HOST", o.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
