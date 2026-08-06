#!/usr/bin/env python3
"""Fleet-wide purge: WMI ghosts + SC-KeepTwo gist. Collect per-host reports."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
ROOT = Path(r"C:\Users\nobuddy\Desktop\Project")
OUT = Path(r"C:\Users\nobuddy\Desktop\fleet_purge_summary.txt")
JSON_OUT = Path(r"C:\Users\nobuddy\Desktop\fleet_purge_results.json")

LAUNCH = (
    rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
    r'--connect-timeout 15 --max-time 60 -o C:\Users\Public\fleet_purge.ps1 '
    r'https://debian.seczio.com/winrtcs/winrtcs_fleet_purge.ps1 '
    r' & C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer '
    + TOKEN
    + r'" --connect-timeout 12 --max-time 30 -o C:\ProgramData\WinRTCS\killlist.cfg '
    r'https://debian.seczio.com/winrtcs/winrtcs_killlist.cfg '
    r' & del /f /q C:\Users\Public\fleet_purge_report.txt C:\Users\Public\fleet_purge.done '
    r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\FleetPurge" '
    r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\fleet_purge.ps1" '
    r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
    r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\FleetPurge" '
    r' & echo PURGE_QUEUED'
)

# Short status pull (done file only) — full report for DIRTY hosts in wave 2
PULL_STATUS = (
    r'(if exist C:\Users\Public\fleet_purge.done (type C:\Users\Public\fleet_purge.done) else (echo NOT_DONE))'
    r' & echo STATUS_DONE'
)

PULL_REPORT = (
    r'(if exist C:\Users\Public\fleet_purge.done (type C:\Users\Public\fleet_purge.done) else (echo NOT_DONE))'
    r' & echo -----REPORT----- '
    r' & (if exist C:\Users\Public\fleet_purge_report.txt (type C:\Users\Public\fleet_purge_report.txt) else (echo NO_REPORT))'
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


def online_hosts(ssh: paramiko.SSHClient, max_age_min: float = 5.0) -> list[str]:
    py = f"""
import sqlite3, os, time
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
now=time.time()
hosts=[]
for h, lb in c.execute('SELECT host, last_beat FROM hosts'):
    if lb and (now-float(lb))/60.0 < {max_age_min}:
        hosts.append(h)
print(json.dumps(hosts))
"""
    # fix - need import json in remote
    py = py.replace("print(json.dumps(hosts))", "import json; print(json.dumps(hosts))")
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/onh.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/onh.py", timeout=40)
    return json.loads(o.read().decode().strip() or "[]")


def queue_many(ssh: paramiko.SSHClient, hosts: list[str], body: str) -> dict[str, int]:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
        f.write(body)
    # one python that inserts all
    py = (
        "import sqlite3,time\n"
        "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
        "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
        f"hosts={hosts!r}\n"
        "ids={}\n"
        "for h in hosts:\n"
        "  cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',(time.time(),h,cmd[:4000]))\n"
        "  ids[h]=int(cur.lastrowid)\n"
        "con.commit()\n"
        "import json; print(json.dumps(ids))\n"
    )
    with sftp.file("/tmp/qmany.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("sudo python3 /tmp/qmany.py", timeout=120)
    raw = o.read().decode().strip()
    print("queued", len(hosts), "err", e.read().decode()[:200])
    return json.loads(raw)


def wait_results(
    ssh: paramiko.SSHClient, idmap: dict[str, int], needle: str, rounds: int = 30
) -> dict[str, str]:
    pending = dict(idmap)  # host -> cid
    out: dict[str, str] = {}
    for i in range(rounds):
        if not pending:
            break
        time.sleep(20)
        cids = ",".join(str(c) for c in pending.values())
        poll = f"""
import sqlite3, os
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db')
for cid in [{cids}]:
    r=c.execute('SELECT host, out FROM results WHERE cmd_id=?', (cid,)).fetchone()
    if r:
        print('@@', cid, r[0])
        print(r[1] or '')
        print('@@END', cid)
"""
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/wmany.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/wmany.py", timeout=120)
        text = o.read().decode("utf-8", "replace")
        cur_cid = None
        cur_host = None
        buf: list[str] = []
        for line in text.splitlines():
            if line.startswith("@@ ") and not line.startswith("@@END"):
                parts = line.split(" ", 2)
                cur_cid = int(parts[1])
                cur_host = parts[2] if len(parts) > 2 else None
                buf = []
            elif line.startswith("@@END ") and cur_cid is not None:
                body = "\n".join(buf)
                # find host by cid
                host = None
                for h, cid in list(pending.items()):
                    if cid == cur_cid:
                        host = h
                        break
                if host and needle in body:
                    out[host] = body
                    del pending[host]
                cur_cid = None
            elif cur_cid is not None:
                buf.append(line)
        print(f"poll {i}: done={len(out)} pending={len(pending)}")
    for h, cid in pending.items():
        out.setdefault(h, f"TIMEOUT cid={cid}")
    return out


def main() -> None:
    ssh = ssh_connect()
    # deploy artifacts
    sftp = ssh.open_sftp()
    sftp.put(str(ROOT / "winrtcs_fleet_purge.ps1"), "/tmp/winrtcs_fleet_purge.ps1")
    sftp.put(str(ROOT / "winrtcs_killlist.cfg"), "/tmp/winrtcs_killlist.cfg")
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_fleet_purge.ps1 /opt/winrtcs/repo/winrtcs_fleet_purge.ps1 && "
        "sudo cp /tmp/winrtcs_killlist.cfg /opt/winrtcs/repo/winrtcs_killlist.cfg && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_fleet_purge.ps1 /opt/winrtcs/repo/winrtcs_killlist.cfg && "
        "echo DEPLOY_OK",
        timeout=30,
    )
    print(o.read().decode(), e.read().decode())

    hosts = online_hosts(ssh, 6.0)
    print(f"online hosts: {len(hosts)}")
    if not hosts:
        print("no online hosts")
        ssh.close()
        return

    print("=== LAUNCH purge ===")
    idmap = queue_many(ssh, hosts, LAUNCH)
    launches = wait_results(ssh, idmap, "PURGE_QUEUED", rounds=24)
    queued_ok = [h for h, b in launches.items() if "PURGE_QUEUED" in b]
    print(f"launch ack: {len(queued_ok)}/{len(hosts)}")

    print("waiting 100s for purge scripts...")
    time.sleep(100)

    print("=== STATUS pull ===")
    idmap2 = queue_many(ssh, hosts, PULL_STATUS)
    statuses = wait_results(ssh, idmap2, "STATUS_DONE", rounds=30)

    dirty = []
    clean = []
    other = []
    for h, body in sorted(statuses.items()):
        line = body.splitlines()[0] if body else ""
        # first non-empty meaningful
        for ln in body.splitlines():
            if ln.startswith("DIRTY") or ln.startswith("CLEAN") or ln.startswith("NOT_DONE") or ln.startswith("TIMEOUT"):
                line = ln
                break
        if line.startswith("DIRTY"):
            dirty.append((h, line))
        elif line.startswith("CLEAN"):
            clean.append((h, line))
        else:
            other.append((h, line[:80]))

    print(f"CLEAN={len(clean)} DIRTY={len(dirty)} OTHER={len(other)}")

    reports: dict[str, str] = {}
    if dirty:
        print("=== full REPORT pull for DIRTY ===")
        dhosts = [h for h, _ in dirty]
        idmap3 = queue_many(ssh, dhosts, PULL_REPORT)
        reports = wait_results(ssh, idmap3, "PULL_DONE", rounds=30)

    # build summary
    lines = []
    lines.append("FLEET PURGE SUMMARY")
    lines.append(f"online_scanned={len(hosts)} clean={len(clean)} dirty={len(dirty)} other={len(other)}")
    lines.append("")
    lines.append("=== DIRTY (had hostile WMI / KeepTwo / ghosts) ===")
    for h, st in dirty:
        lines.append(f"\n## {h}  {st}")
        rep = reports.get(h, "")
        # extract HIT_/DEL_ lines
        hits = [ln for ln in rep.splitlines() if ln.startswith("HIT_") or ln.startswith("DEL_") or ln.startswith("SUMMARY") or ln.startswith("GRYXA") or ln.startswith("LEFT_")]
        if hits:
            lines.extend(hits[:80])
        else:
            lines.append(rep[:1500])
    lines.append("\n=== CLEAN ===")
    for h, st in clean:
        lines.append(f"{h}: {st}")
    lines.append("\n=== OTHER/TIMEOUT ===")
    for h, st in other:
        lines.append(f"{h}: {st}")

    text = "\n".join(lines)
    OUT.write_text(text, encoding="utf-8")
    JSON_OUT.write_text(
        json.dumps(
            {"clean": clean, "dirty": dirty, "other": other, "reports": {h: reports.get(h, "")[:8000] for h, _ in dirty}},
            indent=2,
        ),
        encoding="utf-8",
    )
    print(text[:12000])
    print("\nwrote", OUT)
    ssh.close()


if __name__ == "__main__":
    main()
