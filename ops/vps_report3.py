#!/usr/bin/env python3
"""Deploy report service v3 (command channel + pretty alerts): admin token, nginx /cmd
route, service restart, full round-trip self-test."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
SVC = (Path.home() / "Desktop" / "report_service.py").read_text(encoding="utf-8")
TOKEN = ((Path(__file__).resolve().parent / "secrets" / "fetch_token.txt")).read_text().strip()

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
    location /cmd      {{ proxy_pass http://127.0.0.1:8077; }}

    location /winrtcs/ {{
        if ($http_authorization != "Bearer {TOKEN}") {{ return 403; }}
        alias /opt/winrtcs/repo/;
        autoindex off;
        add_header Cache-Control "no-store";
    }}

    location / {{ return 404; }}
}}
""".format(TOKEN=TOKEN)


def run(ssh: paramiko.SSHClient, cmd: str, timeout: int = 120, ok_rc: tuple = (0,)) -> str:
    _, out, err = ssh.exec_command(cmd, timeout=timeout)
    rc = out.channel.recv_exit_status()
    o, e = out.read().decode(errors="replace"), err.read().decode(errors="replace")
    if rc not in ok_rc:
        print(f"FAIL rc={rc}: {cmd}\n{o[-500:]}\n{e[-800:]}")
        sys.exit(1)
    return o


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="root", key_filename=PRIV, timeout=15)
    print("[+] key login OK")

    print(run(ssh, "[ -s /opt/winrtcs/admin_token ] || (python3 -c \"import secrets;print(secrets.token_hex(20))\" > /opt/winrtcs/admin_token); chmod 600 /opt/winrtcs/admin_token; echo token_ready"))
    sftp = ssh.open_sftp()
    with sftp.open("/opt/winrtcs/report_service.py", "w") as f:
        f.write(SVC)
    with sftp.open("/etc/nginx/sites-available/winrtcs", "w") as f:
        f.write(SITE)
    sftp.close()
    print(run(ssh, "nginx -t && systemctl reload nginx && systemctl restart winrtcs-report && sleep 1 && systemctl is-active winrtcs-report"))
    atok = run(ssh, "cat /opt/winrtcs/admin_token").strip()
    print(f"[+] admin token: {atok}")

    # round-trip self-test: queue a cmd as admin, poll as a fake host, fetch body, post result
    print(run(ssh, f"curl -s -X POST -H 'Authorization: Bearer {atok}' --data-urlencode 'target=SELTEST' --data-urlencode 'cmd=hostname && whoami' http://127.0.0.1:8077/cmd"))
    cid = run(ssh, f"curl -s -H 'Authorization: Bearer {TOKEN}' 'http://127.0.0.1:8077/cmd/poll?host=SELTEST'").strip()
    print(f"[+] poll returned: {cid}")
    print(run(ssh, f"curl -s -H 'Authorization: Bearer {TOKEN}' 'http://127.0.0.1:8077/cmd/get?id={cid}&host=SELTEST'"))
    print(run(ssh, f"curl -s -X POST -H 'Authorization: Bearer {TOKEN}' --data-urlencode 'id={cid}' --data-urlencode 'host=SELTEST' --data-urlencode 'rc=RC=0' --data-urlencode 'out=SELTEST-PC\\nnt authority\\system' http://127.0.0.1:8077/cmd/result"))
    time.sleep(1)
    print(run(ssh, f"curl -s -H 'Authorization: Bearer {atok}' http://127.0.0.1:8077/cmd/list"))
    # fetch token must NOT be able to inject or list
    print(run(ssh, f"curl -s -o /dev/null -w 'inject-with-fetch-token=%{{http_code}}\\n' -X POST -H 'Authorization: Bearer {TOKEN}' --data-urlencode 'target=ALL' --data-urlencode 'cmd=bad' http://127.0.0.1:8077/cmd"))
    print(run(ssh, f"curl -s -o /dev/null -w 'list-with-fetch-token=%{{http_code}}\\n' -H 'Authorization: Bearer {TOKEN}' http://127.0.0.1:8077/cmd/list"))
    ssh.close()
    ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).write_text(atok + "\n")
    print("[+] admin token saved to Desktop\\admin_token.txt")


if __name__ == "__main__":
    main()
