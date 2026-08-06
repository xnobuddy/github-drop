#!/usr/bin/env python3
"""Deploy report service v2 (RMM alerts + batching + map column), restart, self-test."""
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
SVC = (Path.home() / "Desktop" / "report_service.py").read_text()
TOKEN = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text().strip()

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, username="root", key_filename=PRIV, timeout=15)
sftp = ssh.open_sftp()
with sftp.open("/opt/winrtcs/report_service.py", "w") as f:
    f.write(SVC)
sftp.close()
for cmd in [
    "systemctl restart winrtcs-report && sleep 1 && systemctl is-active winrtcs-report",
    f"curl -s -X POST -H 'Authorization: Bearer {TOKEN}' --data-urlencode 'host=SELTEST' --data-urlencode 'state=healthy' --data-urlencode 'guard=0.1.5' --data-urlencode 'rmm=SC:36e506ff@ui.gryxa.com:443[gryxa];AnyDesk' --data-urlencode 'rmm_new=ScreenConnect FP=36e506ff016b2151 relay=ui.gryxa.com:443 mode=Access ver=25.2.1 [gryxa] state=Running || AnyDesk svc=AnyDesk state=Running ver=9.0.5 :: C:\\Program Files (x86)\\AnyDesk\\AnyDesk.exe' http://127.0.0.1:8077/report",
    f"curl -s -H 'Authorization: Bearer {TOKEN}' http://127.0.0.1:8077/map | head -4",
    "sqlite3 /opt/winrtcs/fleet.db \"DELETE FROM hosts WHERE host='SELTEST'\" && echo cleaned",
]:
    _, out, err = ssh.exec_command(cmd, timeout=60)
    print(out.read().decode(), err.read().decode())
ssh.close()
print("[+] report v2 deployed")
