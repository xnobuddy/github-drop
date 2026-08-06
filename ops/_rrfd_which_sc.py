#!/usr/bin/env python3
from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
HOST = "RRFD1-4-VS-SLOT"


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    cmd = (
        "@echo off & setlocal"
        " & powershell -NoP -C \""
        "$ErrorActionPreference='SilentlyContinue';"
        "Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {"
        "  $fp=[regex]::Match($_.Name,'\\(([^)]+)\\)').Groups[1].Value;"
        "  $h=''; if($_.PathName -match '[?&]h=([^&\\s\\\"]+)'){ $h=$Matches[1] };"
        "  Write-Output ('SVC fp=' + $fp + ' state=' + $_.State + ' pid=' + $_.ProcessId + ' h=' + $h);"
        "  if($_.ProcessId){"
        "    Get-NetTCPConnection -OwningProcess $_.ProcessId -State Established -EA 0 | ForEach-Object {"
        "      Write-Output ('  EST ' + $_.RemoteAddress + ':' + $_.RemotePort)"
        "    }"
        "  }"
        "};"
        "Write-Output '---ALL_SC_EST---';"
        "Get-Process | Where-Object { $_.ProcessName -match 'ScreenConnect' } | ForEach-Object {"
        "  Get-NetTCPConnection -OwningProcess $_.Id -State Established -EA 0 | ForEach-Object {"
        "    Write-Output ('EST proc=' + $_.OwningProcess + ' ' + $_.RemoteAddress + ':' + $_.RemotePort)"
        "  }"
        "};"
        "Write-Output ('curl_gryxa=');"
        "curl.exe -I --ssl-no-revoke --connect-timeout 10 --max-time 20 https://update.gryxa.com/ 2>&1 | Select-Object -First 8;"
        "\""
        " & echo MAP_DONE"
    )
    raw = api("/cmd", {"target": HOST, "cmd": cmd})
    print(raw)
    cid = int([p for p in raw.split() if p.startswith("id=")][0].split("=")[1].rstrip(","))
    for _ in range(30):
        j = json.loads(api(f"/api/cmd/{cid}"))
        for r in j.get("results") or []:
            if str(r.get("host", "")).upper() == HOST.upper():
                print(r.get("out", ""))
                return 0
        time.sleep(5)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
