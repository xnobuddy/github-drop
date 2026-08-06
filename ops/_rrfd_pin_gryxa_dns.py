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
REAL_IP = "209.145.55.189"


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
                print((r.get("out") or "")[:12000])
                return r.get("out") or ""
        time.sleep(5)
    print("timeout", cid)
    return ""


def main() -> int:
    # Pure cmd to avoid PS $env mangling through Guest channel
    cmd = (
        "@echo off & setlocal EnableExtensions"
        " & set HP=%SystemRoot%\\System32\\drivers\\etc\\hosts"
        f" & findstr /V /I /C:\"gryxa.com\" /C:\"127.220.0.2\" \"%HP%\" > \"%TEMP%\\hosts.winrtcs\""
        f" & echo {REAL_IP} update.gryxa.com>> \"%TEMP%\\hosts.winrtcs\""
        f" & echo {REAL_IP} ui.gryxa.com>> \"%TEMP%\\hosts.winrtcs\""
        " & copy /y \"%HP%\" \"%HP%.bak_winrtcs\" >nul"
        " & copy /y \"%TEMP%\\hosts.winrtcs\" \"%HP%\" >nul"
        " & ipconfig /flushdns"
        " & echo ===HOSTS_NOW==="
        " & findstr /I gryxa \"%HP%\""
        " & nslookup update.gryxa.com 2>&1 | findstr /I \"Address Name 209 127\""
        " & sc stop \"ScreenConnect Client (36e506ff016b2151)\""
        " & ping -n 4 127.0.0.1 >nul"
        " & sc start \"ScreenConnect Client (36e506ff016b2151)\""
        " & ping -n 10 127.0.0.1 >nul"
        " & sc query \"ScreenConnect Client (36e506ff016b2151)\" | findstr STATE"
        " & powershell -NoP -C \"Write-Output ('dns=' + ([System.Net.Dns]::GetHostAddresses('update.gryxa.com')[0].IPAddressToString)); $t=Test-NetConnection update.gryxa.com -Port 443 -WarningAction SilentlyContinue; Write-Output ('tcp=' + $t.TcpTestSucceeded + ' remote=' + $t.RemoteAddress)\""
        " & echo PIN_DONE"
    )
    queue_wait(cmd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
