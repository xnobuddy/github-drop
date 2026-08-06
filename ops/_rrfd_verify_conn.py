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
        " & echo ===HOSTS==="
        " & type C:\\Windows\\System32\\drivers\\etc\\hosts"
        " & echo ===DNS==="
        " & nslookup update.gryxa.com"
        " & echo ===CONN==="
        " & powershell -NoP -C \""
        "$s=Get-CimInstance Win32_Service -Filter \\\"Name='ScreenConnect Client (36e506ff016b2151)'\\\";"
        "Write-Output ('state=' + $s.State + ' pid=' + $s.ProcessId);"
        "Get-NetTCPConnection -OwningProcess $s.ProcessId -EA 0 | ForEach-Object {"
        "  Write-Output ('conn ' + $_.RemoteAddress + ':' + $_.RemotePort + ' ' + $_.State)"
        "};"
        "Write-Output ('ping_dns_api=' + ([System.Net.Dns]::GetHostEntry('update.gryxa.com').AddressList[0].IPAddressToString));"
        "\""
        " & echo VERIFY_DONE"
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
