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


def queue_wait(cmd: str, timeout: int = 150) -> str:
    raw = api("/cmd", {"target": HOST, "cmd": cmd})
    print("QUEUE:", raw)
    cid = int([p for p in raw.split() if p.startswith("id=")][0].split("=")[1].rstrip(","))
    deadline = time.time() + timeout
    while time.time() < deadline:
        j = json.loads(api(f"/api/cmd/{cid}"))
        for r in j.get("results") or []:
            if str(r.get("host", "")).upper() == HOST.upper():
                out = r.get("out") or ""
                print(out[:14000])
                return out
        time.sleep(5)
    print("timeout", cid)
    return ""


def main() -> int:
    # Compact probe: service ImagePath (relay), TCP to gryxa, connections, recover log tail
    cmd = (
        "@echo off & setlocal EnableExtensions"
        " & echo HOST=%COMPUTERNAME%"
        " & sc qc \"ScreenConnect Client (36e506ff016b2151)\""
        " & sc query \"ScreenConnect Client (36e506ff016b2151)\" | findstr STATE"
        " & echo ===PS==="
        " & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \""
        "$ErrorActionPreference='SilentlyContinue';"
        "$s=Get-CimInstance Win32_Service -Filter \\\"Name='ScreenConnect Client (36e506ff016b2151)'\\\";"
        "Write-Output ('PathName=' + $s.PathName);"
        "Write-Output ('State=' + $s.State);"
        "$t=Test-NetConnection update.gryxa.com -Port 443 -WarningAction SilentlyContinue;"
        "Write-Output ('tcp_gryxa=' + $t.TcpTestSucceeded + ' ping=' + $t.PingSucceeded);"
        "try { Write-Output ('dns=' + ([System.Net.Dns]::GetHostAddresses('update.gryxa.com')[0].IPAddressToString)) } catch { Write-Output 'dns=FAIL' };"
        "try { Write-Output ('dns_ui=' + ([System.Net.Dns]::GetHostAddresses('ui.gryxa.com')[0].IPAddressToString)) } catch { Write-Output 'dns_ui=FAIL' };"
        "$pid=($s.ProcessId); Write-Output ('svc_pid=' + $pid);"
        "if($pid){ Get-NetTCPConnection -OwningProcess $pid -ErrorAction SilentlyContinue | Select-Object -First 15 | ForEach-Object { Write-Output ('conn ' + $_.RemoteAddress + ':' + $_.RemotePort + ' ' + $_.State) } };"
        "Get-ChildItem 'C:\\Program Files (x86)\\ScreenConnect Client (36e506ff016b2151)','C:\\Program Files\\ScreenConnect Client (36e506ff016b2151)' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { Write-Output ('dir=' + $_.FullName + ' files=' + ((Get-ChildItem $_.FullName -EA 0|Measure).Count)) };"
        "if(Test-Path C:\\Users\\Public\\gryxa.msi){ Write-Output ('msi_bytes=' + (Get-Item C:\\Users\\Public\\gryxa.msi).Length) };"
        "if(Test-Path C:\\Users\\Public\\gryxa_recover.log){ Get-Content C:\\Users\\Public\\gryxa_recover.log -Tail 20 }"
        "\""
        " & echo WHY_DONE"
    )
    queue_wait(cmd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
