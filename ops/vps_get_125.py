#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    _, o, e = ssh.exec_command(
        "sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db && "
        "sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null; "
        "sudo chmod 644 /tmp/fleet_ro.db* 2>/dev/null; "
        "python3 -c \""
        "import sqlite3; c=sqlite3.connect('/tmp/fleet_ro.db');"
        "r=c.execute('select rc,out from results where cmd_id=125').fetchone();"
        "print('RC', r[0] if r else None); print(r[1] if r else 'none');"
        "r2=c.execute(\\\"select state,siege,rmm,guard from hosts where host='ADMINIS-0ET5284'\\\").fetchone();"
        "print('HOST', r2)"
        "\"",
        timeout=60,
    )
    print(o.read().decode("utf-8", "replace"))
    print(e.read().decode("utf-8", "replace"))
    ssh.close()


if __name__ == "__main__":
    main()
