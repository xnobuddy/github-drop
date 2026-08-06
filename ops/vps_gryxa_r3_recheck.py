#!/usr/bin/env python3
"""Recheck offline R3 targets via Sight + live probe."""
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

HOSTS = [
    "CUONGCHECKERS",
    "KYLEESPC",
    "BRAINDEVICE",
    "PEREZ",
    "MIKESCOMPUTER",
    "IDGITPOE1959",
    "DESKTOP-L12E0G2",
    "DESKTOP-L66QG8O",
    "MRG-DELL",
    "SECRETARYPC",
    "DESKTOP-3UFSG6P",
]

PROBE = (
    "powershell -NoProfile -NonInteractive -Command "
    "\"$ErrorActionPreference='SilentlyContinue'; "
    "$s=Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -EA SilentlyContinue; "
    "if($s){Write-Output ('GRYXA='+$s.Status)} else {Write-Output 'GRYXA=MISSING'}; "
    "Write-Output 'DONE'\""
)


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    fleet = json.loads(api("/api/fleet"))
    by = {h["host"]: h for h in fleet["hosts"]}
    print("=== SIGHT ===")
    for h in HOSTS:
        x = by.get(h)
        if not x:
            print(f"{h}: not_in_fleet")
            continue
        print(
            f"{h}: presence={x.get('presence')} state={x.get('state')} "
            f"has_gryxa={x.get('has_gryxa')} beat={x.get('beat')}"
        )

    ids = []
    for h in HOSTS:
        text = api("/cmd", {"target": h, "cmd": PROBE})
        m = re.search(r"id=(\d+)", text)
        print("queued", text.strip())
        if m:
            ids.append((h, int(m.group(1))))
    print("wait 95s")
    time.sleep(95)
    print("=== LIVE ===")
    for h, cid in ids:
        d = json.loads(api(f"/api/cmd/{cid}"))
        res = d.get("results") or []
        if not res:
            print(f"{h}: no_response")
        else:
            print(f"{h}: {(res[0].get('out') or '').replace(chr(10), ' | ')[:140]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
