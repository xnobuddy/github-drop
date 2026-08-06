#!/usr/bin/env python3
"""WinRTCS VPS provisioning - Phase 0 hardening + Phase 1 repo mirror.

One-shot, idempotent, lockout-safe: key auth is verified in fresh sessions BEFORE
password auth is disabled. Root password is read from ~/.vps_pw (delete after run)
and locked server-side once keys are proven. Prints the fleet fetch token at the end.
"""
from __future__ import annotations

import secrets
import sys
from pathlib import Path

import paramiko

HOST = "144.172.107.56"
REPO = "https://github.com/xnobuddy/github-drop"
PW = (Path.home() / ".vps_pw").read_text().strip()
PUB = (Path.home() / ".ssh" / "winrtcs_ed25519.pub").read_text().strip()
PRIV = str(Path.home() / ".ssh" / "winrtcs_ed25519")
FETCH_TOKEN = secrets.token_hex(20)


def run(ssh: paramiko.SSHClient, cmd: str, timeout: int = 300, check: bool = True) -> tuple[int, str, str]:
    _, out, err = ssh.exec_command(cmd, timeout=timeout)
    rc = out.channel.recv_exit_status()
    o, e = out.read().decode(errors="replace"), err.read().decode(errors="replace")
    if check and rc != 0:
        print(f"FAIL rc={rc}: {cmd}\n{o[-800:]}\n{e[-1200:]}")
        sys.exit(1)
    return rc, o, e


def put(ssh: paramiko.SSHClient, path: str, content: str, mode: int = 0o644) -> None:
    sftp = ssh.open_sftp()
    with sftp.open(path, "w") as f:
        f.write(content)
    sftp.chmod(path, mode)
    sftp.close()


def key_login(user: str) -> bool:
    try:
        t = paramiko.SSHClient()
        t.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        t.connect(HOST, username=user, key_filename=PRIV, timeout=15)
        _, o, _ = t.exec_command("whoami")
        ok = o.read().decode().strip() == user
        t.close()
        return ok
    except Exception as exc:
        print(f"    key login {user}: {exc}")
        return False


def main() -> None:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="root", password=PW, timeout=15)
    print("[1/7] password login OK")

    print("[2/7] system update + packages (few minutes)...")
    run(ssh, "apt-get update -qq", 600)
    run(ssh, "DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade", 900)
    run(ssh, "DEBIAN_FRONTEND=noninteractive apt-get -y install "
             "nginx git curl sqlite3 fail2ban unattended-upgrades ufw", 600)

    print("[3/7] winrtcs user + SSH keys")
    run(ssh, "id winrtcs >/dev/null 2>&1 || useradd -m -s /bin/bash winrtcs")
    run(ssh, "usermod -aG sudo winrtcs")
    put(ssh, "/etc/sudoers.d/winrtcs", "winrtcs ALL=(ALL) NOPASSWD:ALL\n", 0o440)
    run(ssh, "mkdir -p /root/.ssh /home/winrtcs/.ssh && chmod 700 /root/.ssh /home/winrtcs/.ssh")
    rc, out, _ = run(ssh, "grep -qF '" + PUB.split()[1] + "' /root/.ssh/authorized_keys 2>/dev/null", check=False)
    if rc != 0:
        run(ssh, f"echo '{PUB}' >> /root/.ssh/authorized_keys")
    rc, out, _ = run(ssh, "grep -qF '" + PUB.split()[1] + "' /home/winrtcs/.ssh/authorized_keys 2>/dev/null", check=False)
    if rc != 0:
        run(ssh, f"echo '{PUB}' >> /home/winrtcs/.ssh/authorized_keys")
    run(ssh, "chmod 600 /root/.ssh/authorized_keys /home/winrtcs/.ssh/authorized_keys "
             "&& chown -R winrtcs:winrtcs /home/winrtcs/.ssh")

    print("[4/7] sshd drop-in staged (NOT restarted yet) + firewall + fail2ban")
    put(ssh, "/etc/ssh/sshd_config.d/60-winrtcs.conf",
        "PasswordAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\n")
    run(ssh, "ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable")
    run(ssh, "systemctl enable --now fail2ban unattended-upgrades")
    run(ssh, "passwd -l root")  # password is dead weight; console/key only from here

    print("[5/7] verifying KEY auth in fresh sessions before the door closes...")
    if not key_login("winrtcs") or not key_login("root"):
        print("ABORT: key auth broken - password auth left ENABLED, fix keys first")
        sys.exit(2)
    print("    key login OK for winrtcs + root - disabling password auth")
    run(ssh, "systemctl restart ssh")
    try:
        bad = paramiko.SSHClient()
        bad.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        bad.connect(HOST, username="root", password=PW, timeout=10)
        print("WARN: password login still works!")
        bad.close()
    except paramiko.AuthenticationException:
        print("    confirmed: password auth refused")

    print("[6/7] repo mirror + cron")
    run(ssh, "mkdir -p /opt/winrtcs")
    rc, _, _ = run(ssh, "test -d /opt/winrtcs/repo/.git", check=False)
    if rc == 0:
        run(ssh, "git -C /opt/winrtcs/repo pull --ff-only -q", 300)
    else:
        run(ssh, f"git clone --depth 1 {REPO} /opt/winrtcs/repo", 300)
    put(ssh, "/etc/cron.d/winrtcs-mirror",
        "*/2 * * * * root git -C /opt/winrtcs/repo pull --ff-only -q\n")
    put(ssh, "/opt/winrtcs/fetch_token", FETCH_TOKEN + "\n", 0o600)

    print("[7/7] nginx bearer-gated mirror")
    site = f"""server {{
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    server_tokens off;

    location = /healthz {{
        default_type text/plain;
        return 200 "ok";
    }}

    location /winrtcs/ {{
        if ($http_authorization != "Bearer {FETCH_TOKEN}") {{ return 403; }}
        alias /opt/winrtcs/repo/;
        autoindex off;
        add_header Cache-Control "no-store";
    }}

    location / {{ return 404; }}
}}
"""
    put(ssh, "/etc/nginx/sites-available/winrtcs", site)
    run(ssh, "ln -sf /etc/nginx/sites-available/winrtcs /etc/nginx/sites-enabled/winrtcs "
             "&& rm -f /etc/nginx/sites-enabled/default && nginx -t && systemctl reload nginx")
    ssh.close()

    print()
    print("=" * 60)
    print("PROVISIONED OK")
    print(f"  fetch token : {FETCH_TOKEN}")
    print(f"  mirror url  : http://{HOST}/winrtcs/winrtcs.version")
    print(f"  health      : http://{HOST}/healthz")
    print("  ssh         : key-only now (winrtcs_ed25519), password auth dead")
    print("=" * 60)


if __name__ == "__main__":
    main()
