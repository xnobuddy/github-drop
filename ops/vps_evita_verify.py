#!/usr/bin/env python3
"""Wait for guard cycle(s), then verify EVITA is stable."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "PC-EVITA-X6"
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_verify_out.txt")

# Compact verify script — no $ in a way that gets stripped if we use -File
# We'll stage via curl a small ps1
VERIFY_PS1 = r'''
$ErrorActionPreference='SilentlyContinue'
$o='C:\Users\Public\evita_verify.txt'
$L=@()
$L+="=== VERIFY $(Get-Date -Format o) ==="
$ns='root\subscription'
$L+='=== BINDINGS ==='
Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | ForEach-Object { $L+="BIND $($_.Filter) -> $($_.Consumer)" }
$L+='=== FILTERS ==='
Get-WmiObject -Namespace $ns -Class __EventFilter | ForEach-Object { $L+="FILT $($_.Name)" }
$L+='=== CONSUMERS ==='
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer | ForEach-Object { $L+="CONS $($_.Name)" }
$L+='=== GHOST PATHS ==='
foreach($p in @('C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache','C:\ProgramData\Microsoft\Diagnosis\State\.etlcache','C:\ProgramData\Microsoft\Diagnosis\ETLParser.ps1')){
  if(Test-Path -LiteralPath $p){$L+="EXISTS $p"} else {$L+="GONE $p"}
}
$g=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)'
$L+="GRYXA $($g.Status)"
$L+='=== GUARD FLAGS ==='
$zd='C:\ProgramData\WinRTCS'
foreach($f in @('extkill.cnt','fight.cnt','streak.cnt','killer.flag','guard.ver')){
  $p=Join-Path $zd $f
  if(Test-Path $p){ $L+="FLAG $f=$((Get-Content $p -Raw) -replace '\s+',' ').Trim()" } else { $L+="FLAG $f=MISSING" }
}
$L+='=== GUARD.LOG TAIL ==='
Get-Content (Join-Path $zd 'guard.log') -Tail 40 | ForEach-Object { $L+=$_ }
$L+='=== VERIFY END ==='
$L | Set-Content $o -Encoding ASCII
'OK'|Set-Content 'C:\Users\Public\evita_verify.done' -Encoding ASCII
'''


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
    # Write verify ps1 to repo
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/winrtcs_evita_verify.ps1", "w") as f:
        f.write(VERIFY_PS1.replace("\r\n", "\n"))
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_evita_verify.ps1 /opt/winrtcs/repo/winrtcs_evita_verify.ps1 && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_evita_verify.ps1 && echo OK",
        timeout=20,
    )
    print(o.read().decode(), e.read().decode())

    print("Waiting 17 minutes for at least one full guard cycle...")
    time.sleep(17 * 60)

    token = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
    launch = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {token}" '
        r'--connect-timeout 15 --max-time 60 -o C:\Users\Public\evita_verify.ps1 '
        r'https://debian.seczio.com/winrtcs/winrtcs_evita_verify.ps1 '
        r' & del /f /q C:\Users\Public\evita_verify.txt C:\Users\Public\evita_verify.done '
        r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\EvitaVerify" '
        r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\evita_verify.ps1" '
        r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
        r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\EvitaVerify" '
        r' & echo VERIFY_QUEUED'
    )
    cid = queue(ssh, launch)
    print("launch", cid)
    print(wait_result(ssh, cid, "VERIFY_QUEUED")[:800])
    time.sleep(60)
    pull = (
        r'(if exist C:\Users\Public\evita_verify.done (echo DONE_OK) else (echo DONE_MISSING))'
        r' & (if exist C:\Users\Public\evita_verify.txt (echo FILE_OK & type C:\Users\Public\evita_verify.txt) else (echo NOFILE))'
        r' & sc query "ScreenConnect Client (36e506ff016b2151)" '
        r' & echo PULL_DONE'
    )
    cid2 = queue(ssh, pull)
    print("pull", cid2)
    out = wait_result(ssh, cid2, "PULL_DONE")
    print(out[:20000])
    OUT.write_text(out, encoding="utf-8")

    # fleet host row
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
