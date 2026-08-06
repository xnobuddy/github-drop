#!/usr/bin/env python3
"""Install Cloudflare Origin CA cert on the WinRTCS VPS, flip nginx to HTTPS-only.
Key auth only (password auth is dead). Origin cert = Cloudflare-trusted, so the site
serves correctly to the fleet only via the proxied hostname - direct-to-origin TLS
fails validation, which is a feature (origin hides behind CF)."""
from __future__ import annotations

import sys
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
CRT = (Path.home() / "Desktop" / "origin.crt").read_text()
KEY = (Path.home() / "Desktop" / "origin.key").read_text()
TOKEN = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text().strip()


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

    run(ssh, "mkdir -p /etc/nginx/ssl")
    put(ssh, "/etc/nginx/ssl/origin.crt", CRT if CRT.endswith("\n") else CRT + "\n")
    put(ssh, "/etc/nginx/ssl/origin.key", KEY if KEY.endswith("\n") else KEY + "\n", 0o600)

    site = f"""server {{
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

    location /winrtcs/ {{
        if ($http_authorization != "Bearer {TOKEN}") {{ return 403; }}
        alias /opt/winrtcs/repo/;
        autoindex off;
        add_header Cache-Control "no-store";
    }}

    location / {{ return 404; }}
}}
"""
    put(ssh, "/etc/nginx/sites-available/winrtcs", site)
    print(run(ssh, "nginx -t && systemctl reload nginx"))
    print(run(ssh, "curl -sk -o /dev/null -w 'local-https-no-token=%{http_code}\\n' https://127.0.0.1/winrtcs/winrtcs.version"))
    print(run(ssh, f"curl -sk -H 'Authorization: Bearer {TOKEN}' -o /dev/null -w 'local-https-token=%{http_code}\\n' https://127.0.0.1/winrtcs/winrtcs.version"))
    ssh.close()
    print("[+] TLS live on origin (Cloudflare Origin CA - only validates via the proxied hostname)")


if __name__ == "__main__":
    main()
