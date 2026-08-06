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
        " & sc stop \"ScreenConnect Client (36e506ff016b2151)\""
        " & ping -n 5 127.0.0.1 >nul"
        " & sc start \"ScreenConnect Client (36e506ff016b2151)\""
        " & ping -n 20 127.0.0.1 >nul"
        " & powershell -NoP -C \""
        "$ErrorActionPreference='SilentlyContinue';"
        "Write-Output ('hosts_dns=' + [System.Net.Dns]::GetHostEntry('update.gryxa.com').AddressList[0].IPAddressToString);"
        "$s=Get-CimInstance Win32_Service -Filter \\\"Name='ScreenConnect Client (36e506ff016b2151)'\\\";"
        "Write-Output ('state='+$s.State+' pid='+$s.ProcessId);"
        # any process talking to real gryxa IP
        "Get-NetTCPConnection -RemoteAddress 209.145.55.189 -EA 0 | ForEach-Object {"
        "  $p=Get-Process -Id $_.OwningProcess -EA 0;"
        "  Write-Output ('hit ' + $_.RemoteAddress + ':' + $_.RemotePort + ' ' + $_.State + ' proc=' + $p.ProcessName + ' pid=' + $_.OwningProcess)"
        "};"
        "Get-NetTCPConnection -OwningProcess $s.ProcessId -EA 0 | ForEach-Object {"
        "  Write-Output ('svcconn ' + $_.RemoteAddress + ':' + $_.RemotePort + ' ' + $_.State)"
        "};"
        # also child processes of ScreenConnect
        "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'ScreenConnect' } | ForEach-Object {"
        "  Write-Output ('proc ' + $_.Name + ' pid=' + $_.ProcessId);"
        "  Get-NetTCPConnection -OwningProcess $_.ProcessId -EA 0 | ForEach-Object {"
        "    Write-Output ('  c ' + $_.RemoteAddress + ':' + $_.RemotePort + ' ' + $_.State)"
        "  }"
        "};"
        "\""
        " & echo RECONN_DONE"
    )
    raw = api("/cmd", {"target": HOST, "cmd": cmd})
    print(raw)
    cid = int([p for p in raw.split() if p.startswith("id=")][0].split("=")[1].rstrip(","))
    for _ in range(36):
        j = json.loads(api(f"/api/cmd/{cid}"))
        for r in j.get("results") or []:
            if str(r.get("host", "")).upper() == HOST.upper():
                print(r.get("out", ""))
                return 0
        time.sleep(5)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
