#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TARGET = "ADMINIS-0ET5284"


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    _, out, err = ssh.exec_command(
        "sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db && "
        "sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null; "
        "sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null; "
        "python3 - <<'PY'\n"
        "import sqlite3,time\n"
        "con=sqlite3.connect('/tmp/fleet_ro.db')\n"
        f"h={TARGET!r}\n"
        "now=time.time()\n"
        "row=con.execute('SELECT state,rmm,last_seen,last_beat,guard,agent FROM hosts WHERE host=?',(h,)).fetchone()\n"
        "print('HOST',row)\n"
        "if row and row[2]: print('digest_age_m',round((now-row[2])/60,1))\n"
        "if row and row[3]: print('beat_age_m',round((now-row[3])/60,1))\n"
        "for cid in (117,30,28,26):\n"
        "  r=con.execute('SELECT rc,ts,substr(out,1,2000) FROM results WHERE cmd_id=? AND host=?',(cid,h)).fetchone()\n"
        "  print('RESULT',cid, r[0] if r else 'NONE', 'age', round((now-r[1])/60,1) if r else '-')\n"
        "  if r: print(r[2] or '(empty)'); print('---')\n"
        "j=con.execute(\"SELECT id,name,status,cmd_id FROM jobs WHERE target=? ORDER BY id DESC LIMIT 8\",(h,)).fetchall()\n"
        "print('JOBS',j)\n"
        "PY",
        timeout=60,
    )
    print(out.read().decode("utf-8", "replace"))
    print(err.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
