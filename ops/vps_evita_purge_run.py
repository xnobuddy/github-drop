#!/usr/bin/env python3
"""Deploy EVITA purge + updated killlist; run purge via schtasks; pull result; verify."""
from __future__ import annotations

import hashlib
import time
from pathlib import Path

import paramiko

TARGET = "PC-EVITA-X6"
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
ROOT = Path(r"C:\Users\nobuddy\Desktop\Project")
OUT = Path(r"C:\Users\nobuddy\Desktop\evita_purge_out.txt")


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


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
    purge = ROOT / "winrtcs_evita_purge.ps1"
    killlist = ROOT / "winrtcs_killlist.cfg"
    sidekick = ROOT / "winrtcs_sidekick.ps1"
    print("purge sha", sha256(purge))
    print("killlist sha", sha256(killlist))
    print("sidekick sha", sha256(sidekick))

    ssh = ssh_connect()
    sftp = ssh.open_sftp()
    sftp.put(str(purge), "/tmp/winrtcs_evita_purge.ps1")
    sftp.put(str(killlist), "/tmp/winrtcs_killlist.cfg")
    sftp.put(str(sidekick), "/tmp/winrtcs_sidekick.ps1")
    sftp.close()

    # Deploy to repo mirror. Sidekick needs version pin update — check winrtcs.version
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_evita_purge.ps1 /opt/winrtcs/repo/winrtcs_evita_purge.ps1 && "
        "sudo cp /tmp/winrtcs_killlist.cfg /opt/winrtcs/repo/winrtcs_killlist.cfg && "
        "sudo cp /tmp/winrtcs_sidekick.ps1 /opt/winrtcs/repo/winrtcs_sidekick.ps1 && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_evita_purge.ps1 "
        "/opt/winrtcs/repo/winrtcs_killlist.cfg /opt/winrtcs/repo/winrtcs_sidekick.ps1 && "
        "echo DEPLOY_OK && "
        "sha256sum /opt/winrtcs/repo/winrtcs_killlist.cfg /opt/winrtcs/repo/winrtcs_sidekick.ps1 "
        "/opt/winrtcs/repo/winrtcs_evita_purge.ps1",
        timeout=30,
    )
    print(o.read().decode(), e.read().decode())

    # Update SIDEKICK_SHA256 in winrtcs.version if present
    sk_hash = sha256(sidekick)
    upd = f"""
from pathlib import Path
p = Path('/opt/winrtcs/repo/winrtcs.version')
t = p.read_text()
lines = []
found = False
for line in t.splitlines():
    if line.startswith('SIDEKICK_SHA256='):
        lines.append('SIDEKICK_SHA256={sk_hash}')
        found = True
    else:
        lines.append(line)
if not found:
    lines.append(f'SIDEKICK_SHA256={sk_hash}')
text = '\\n'.join(lines) + '\\n'
Path('/tmp/winrtcs.version.new').write_text(text)
print('updated', found)
print([l for l in lines if 'SIDEKICK' in l or 'KILLLIST' in l or 'GUARD' in l][:20])
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/upd_ver.py", "w") as f:
        f.write(upd)
    sftp.close()
    _, o, e = ssh.exec_command(
        "python3 /tmp/upd_ver.py && sudo cp /tmp/winrtcs.version.new /opt/winrtcs/repo/winrtcs.version && "
        "grep SIDEKICK /opt/winrtcs/repo/winrtcs.version",
        timeout=30,
    )
    print(o.read().decode(), e.read().decode())

    # Re-sign version if signing script exists
    _, o, e = ssh.exec_command(
        "ls /opt/winrtcs/repo/winrtcs.version.sig /opt/winrtcs/signing.py /home/winrtcs/signing.py 2>&1; "
        "which openssl; ls /opt/winrtcs/*.pem /opt/winrtcs/keys/* 2>&1 | head",
        timeout=20,
    )
    print("sign probe:", o.read().decode(), e.read().decode())

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
    cid = queue(ssh, launch)
    print("launch", cid)
    print(wait_result(ssh, cid, "PURGE_QUEUED", rounds=20)[:1500])

    print("waiting 90s for purge...")
    time.sleep(90)

    pull = (
        r'(if exist C:\Users\Public\evita_purge.done (echo DONE_OK) else (echo DONE_MISSING))'
        r' & (if exist C:\Users\Public\evita_purge.txt (echo FILE_OK & type C:\Users\Public\evita_purge.txt) else (echo NO_PURGE_FILE))'
        r' & echo PULL_DONE'
    )
    cid2 = queue(ssh, pull)
    print("pull", cid2)
    out = wait_result(ssh, cid2, "PULL_DONE", rounds=20)
    print(out[:20000])
    OUT.write_text(out, encoding="utf-8")
    print("wrote", OUT)

    # Force refresh killlist on host next guard — also push killlist now
    kl = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke '
        rf'-H "Authorization: Bearer {TOKEN}" '
        r'--connect-timeout 15 --max-time 60 '
        r'-o C:\ProgramData\WinRTCS\killlist.cfg '
        r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
        r' & echo KILLLIST_RC=%ERRORLEVEL% & findstr /i SCWatchdog C:\ProgramData\WinRTCS\killlist.cfg'
    )
    cid3 = queue(ssh, kl)
    print("killlist push", cid3)
    print(wait_result(ssh, cid3, "SCWatchdog", rounds=20)[:2000])

    # Live Gryxa probe
    probe = (
        r'sc query "ScreenConnect Client (36e506ff016b2151)" & '
        r'sc query "ScreenConnect Client (5f6010579852e507)" & '
        r'echo PROBE_DONE'
    )
    cid4 = queue(ssh, probe)
    print("probe", cid4)
    print(wait_result(ssh, cid4, "PROBE_DONE", rounds=20)[:3000])
    ssh.close()


if __name__ == "__main__":
    main()
