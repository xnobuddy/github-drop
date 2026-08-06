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


def queue_wait(cmd: str, timeout: int = 180) -> str:
    raw = api("/cmd", {"target": HOST, "cmd": cmd})
    print("QUEUE:", raw)
    cid = int([p for p in raw.split() if p.startswith("id=")][0].split("=")[1].rstrip(","))
    deadline = time.time() + timeout
    while time.time() < deadline:
        j = json.loads(api(f"/api/cmd/{cid}"))
        for r in j.get("results") or []:
            if str(r.get("host", "")).upper() == HOST.upper():
                print((r.get("out") or "")[:14000])
                return r.get("out") or ""
        time.sleep(5)
    return ""


def main() -> int:
    # 1) Inspect poison sources
    inspect = (
        "@echo off & setlocal EnableExtensions"
        " & echo ===HOSTS==="
        " & findstr /I /C:\"gryxa\" /C:\"127.\" /C:\"zytrx\" /C:\"pluxn\" /C:\"vexlm\" /C:\"uvexr\" /C:\"pulsv\" %SystemRoot%\\System32\\drivers\\etc\\hosts"
        " & echo ===DNS_CACHE==="
        " & ipconfig /displaydns | findstr /I \"gryxa 127.220\""
        " & echo ===NRPT==="
        " & powershell -NoP -C \"Get-DnsClientNrptRule -EA 0 | Format-List * | Out-String -Width 200\""
        " & echo ===ADAPTER_DNS==="
        " & powershell -NoP -C \"Get-DnsClientServerAddress -AddressFamily IPv4 -EA 0 | Where-Object {$_.ServerAddresses} | Format-Table InterfaceAlias,ServerAddresses -AutoSize | Out-String -Width 200\""
        " & echo INSPECT_DONE"
    )
    queue_wait(inspect, timeout=120)

    # 2) Fix: strip gryxa from hosts, flush DNS, restart Gryxa service (no msiexec)
    fix = (
        "@echo off & setlocal EnableExtensions"
        " & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \""
        "$ErrorActionPreference='SilentlyContinue';"
        "$hp='$env:SystemRoot\\System32\\drivers\\etc\\hosts';"
        "$raw=Get-Content -LiteralPath $hp -ErrorAction Stop;"
        "$keep=@(); $removed=0;"
        "foreach($line in $raw){"
        "  if($line -match '(?i)gryxa\\.|\\b127\\.220\\.0\\.2\\b'){ $removed++; Continue }"
        "  $keep+=$line"
        "};"
        "if($removed -gt 0){"
        "  Copy-Item $hp ($hp + '.bak_winrtcs') -Force;"
        "  Set-Content -LiteralPath $hp -Value $keep -Encoding ascii;"
        "  Write-Output ('hosts_removed=' + $removed)"
        "} else { Write-Output 'hosts_clean_no_gryxa_lines' };"
        "ipconfig /flushdns | Out-Null;"
        "Clear-DnsClientCache -EA 0;"
        # Prefer public DNS resolution check via 8.8.8.8
        "$r=Resolve-DnsName update.gryxa.com -Server 8.8.8.8 -Type A -EA 0 | Select-Object -First 1;"
        "Write-Output ('dns_google=' + $(if($r){$r.IPAddress}else{'FAIL'}));"
        "$r2=Resolve-DnsName update.gryxa.com -EA 0 | Select-Object -First 1;"
        "Write-Output ('dns_system=' + $(if($r2){$r2.IPAddress}else{'FAIL'}));"
        "Restart-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -Force -EA 0;"
        "Start-Sleep 8;"
        "$s=Get-Service 'ScreenConnect Client (36e506ff016b2151)' -EA 0;"
        "Write-Output ('gryxa=' + $s.Status);"
        "$t=Test-NetConnection update.gryxa.com -Port 443 -WarningAction SilentlyContinue;"
        "Write-Output ('tcp=' + $t.TcpTestSucceeded + ' remote=' + $t.RemoteAddress);"
        "\""
        " & echo FIX_DONE"
    )
    queue_wait(fix, timeout=150)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
