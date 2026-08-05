#!/usr/bin/env python3
"""Deploy Sight console + report_service v5 to the VPS and reload nginx."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
ROOT = Path(__file__).resolve().parent
REMOTE = "/opt/winrtcs"

NGINX = r"""
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    http2 on;
    server_name _;
    server_tokens off;

    ssl_certificate     /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;

    location = /healthz {
        default_type text/plain;
        return 200 "ok";
    }

    location = /report { proxy_pass http://127.0.0.1:8077/report; }
    location = /map    { proxy_pass http://127.0.0.1:8077/map; }
    location = /heartbeat { proxy_pass http://127.0.0.1:8077/heartbeat; }
    location = /hostcfg { proxy_pass http://127.0.0.1:8077/hostcfg; }
    location /cmd      { proxy_pass http://127.0.0.1:8077; }

    location /api/ {
        proxy_pass http://127.0.0.1:8077/api/;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Content-Type $content_type;
        proxy_set_header Cookie $http_cookie;
        proxy_pass_header Set-Cookie;
    }

    location /sight {
        proxy_pass http://127.0.0.1:8077/sight;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Cookie $http_cookie;
        proxy_pass_header Set-Cookie;
    }

    location /winrtcs/ {
        if ($http_authorization != "Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5") { return 403; }
        alias /opt/winrtcs/repo/;
        autoindex off;
        add_header Cache-Control "no-store";
    }

    location / { return 404; }
}
"""


def run(ssh: paramiko.SSHClient, cmd: str) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=120)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    print(f"$ {cmd}\n{o}{e}")
    return o + e


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="winrtcs", key_filename=KEY, timeout=20)
    sftp = ssh.open_sftp()

    run(ssh, f"sudo mkdir -p {REMOTE}/static")
    # upload via temp then sudo move (winrtcs may not write /opt)
    tmp = "/tmp/sight_deploy"
    run(ssh, f"rm -rf {tmp} && mkdir -p {tmp}/static")

    files = [
        (ROOT / "report_service.py", f"{tmp}/report_service.py"),
        (ROOT / "jobs_catalog.py", f"{tmp}/jobs_catalog.py"),
        (ROOT / "static" / "index.html", f"{tmp}/static/index.html"),
    ]
    for local, remote in files:
        print("put", local.name, "->", remote)
        sftp.put(str(local), remote)

    # nginx config
    with sftp.file(f"{tmp}/nginx_winrtcs.conf", "w") as f:
        f.write(NGINX)

    run(
        ssh,
        f"sudo cp {tmp}/report_service.py {REMOTE}/report_service.py && "
        f"sudo cp {tmp}/jobs_catalog.py {REMOTE}/jobs_catalog.py && "
        f"sudo mkdir -p {REMOTE}/static && "
        f"sudo cp {tmp}/static/index.html {REMOTE}/static/index.html && "
        f"sudo cp {tmp}/nginx_winrtcs.conf /etc/nginx/sites-available/winrtcs && "
        f"sudo nginx -t && sudo systemctl reload nginx && "
        f"sudo systemctl restart winrtcs-report && "
        f"sudo systemctl is-active winrtcs-report",
    )
    sftp.close()
    ssh.close()
    print("\nSIGHT: https://debian.seczio.com/sight")
    print("Login with Desktop/admin_token.txt")


if __name__ == "__main__":
    main()
