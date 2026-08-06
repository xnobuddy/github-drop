#!/usr/bin/env python3
"""Deploy the WinRTCS report service to the VPS: service file, TG config (server-side
only - this is where the bot token moves to, out of the repo), systemd unit, nginx
proxy locations for /report and /map."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
SVC = (Path.home() / "Desktop" / "report_service.py").read_text()
TOKEN = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text().strip()
TG_JSON = '{\n  "token": "8908569128:AAGIuyqWonhK4fvq2hWW5Eh9gM4W5Dvr-MM",\n  "chat_id": "7547462070"\n}\n'

UNIT = """[Unit]
Description=WinRTCS report service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/winrtcs/report_service.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""

SITE = """server {{
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}}

server {{
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    http2 on;
    server_name _;
    server_tokens off;

    ssl_certificate     /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;

    location = /healthz {{
        default_type text/plain;
        return 200 "ok";
    }}

    location = /report {{ proxy_pass http://127.0.0.1:8077/report; }}
    location = /map    {{ proxy_pass http://127.0.0.1:8077/map; }}

    location /winrtcs/ {{
        if ($http_authorization != "Bearer {TOKEN}") {{ return 403; }}
        alias /opt/winrtcs/repo/;
        autoindex off;
        add_header Cache-Control "no-store";
    }}

    location / {{ return 404; }}
}}
""".format(TOKEN=TOKEN)


def run(ssh: paramiko.SSHClient, cmd: str, timeout: int = 120) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=timeout)
    rc = out.channel.recv_exit_status()
    o, e = out.read().decode(errors="replace"), err.read().decode(errors="replace")
    if rc != 0:
        print(f"FAIL rc={rc}: {cmd}\n{o[-500:]}\n{e[-800:]}")
        sys.exit(1)
    return o


def put(ssh: paramiko.SSHClient, path: str, content: str, mode: int = 0o644) -> None:
    sftp = ssh.open_sftp()
    with sftp.open(path, "w") as f:
        f.write(content)
    sftp.chmod(path, mode)
    sftp.close()


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="root", key_filename=PRIV, timeout=15)
    print("[+] key login OK")

    put(ssh, "/opt/winrtcs/report_service.py", SVC)
    put(ssh, "/opt/winrtcs/tg.json", TG_JSON, 0o600)
    put(ssh, "/etc/systemd/system/winrtcs-report.service", UNIT)
    put(ssh, "/etc/nginx/sites-available/winrtcs", SITE)
    run(ssh, "systemctl daemon-reload && systemctl enable --now winrtcs-report && nginx -t && systemctl reload nginx")
    print(run(ssh, "systemctl is-active winrtcs-report"))
    print(run(ssh, f"curl -s -X POST -H 'Authorization: Bearer {TOKEN}' -d 'host=SELTEST&state=healthy&guard=0.1.3' http://127.0.0.1:8077/report"))
    print(run(ssh, f"curl -s -H 'Authorization: Bearer {TOKEN}' http://127.0.0.1:8077/map"))
    print(run(ssh, f"curl -sk -X POST -H 'Authorization: Bearer {TOKEN}' -d 'host=SELTEST2&state=paused&guard=0.1.3' -o /dev/null -w 'https-report=%{{http_code}}\\n' https://127.0.0.1/report"))
    print(run(ssh, "curl -sk -X POST -o /dev/null -w 'https-report-no-token=%{http_code}\\n' https://127.0.0.1/report"))
    print(run(ssh, f"curl -sk -H 'Authorization: Bearer {TOKEN}' https://127.0.0.1/map"))
    ssh.close()
    print("[+] report service live")


if __name__ == "__main__":
    main()
