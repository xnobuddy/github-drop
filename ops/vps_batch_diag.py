#!/usr/bin/env python3
"""Batch diagnose Gryxa on a host list."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TARGETS = [
    "LAPTOPBE",
    "LAPTOP-1P6GP1UQ",
    "EASYLAB0514-2",
    "DESKTOP-JQKHHML",
    "DESKTOP-GG4NNSJ",
    "DESKTOP-7M84CP8",
    "DESKTOP-0Q4F5D9",
    "CARPED-P16S",
    "CARI",
]


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    py = r"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c = sqlite3.connect('/tmp/fleet_ro.db')
c.row_factory = sqlite3.Row
now = time.time()
want = """ + json.dumps(TARGETS) + r"""
# exact + fuzzy
all_hosts = [r[0] for r in c.execute('SELECT host FROM hosts')]
print('=== LOOKUP ===')
for t in want:
    matches = [h for h in all_hosts if h.upper() == t.upper() or t.upper() in h.upper() or h.upper() in t.upper()]
    if not matches:
        # partial tokens
        toks = [x for x in t.upper().replace('-', ' ').split() if len(x) >= 3]
        matches = [h for h in all_hosts if any(tok in h.upper() for tok in toks)]
    print('TARGET', t, '->', matches or 'NOT_FOUND')
    for h in matches or []:
        r = dict(c.execute('SELECT * FROM hosts WHERE host=?', (h,)).fetchone())
        for k in ('last_seen', 'last_beat'):
            if r.get(k):
                try:
                    r[k + '_ago_min'] = round((now - float(r[k])) / 60, 1)
                except Exception:
                    pass
        print(' ', json.dumps({k: r.get(k) for k in (
            'host','state','agent','guard','streak','extkill','rmm','last_seen_ago_min','last_beat_ago_min','maint'
        )}, default=str))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/batch_diag.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/batch_diag.py", timeout=40)
    print(o.read().decode("utf-8", "replace"))
    err = e.read().decode("utf-8", "replace")
    if err:
        print("ERR", err)
    ssh.close()


if __name__ == "__main__":
    main()
