#!/usr/bin/env python3
import json
import urllib.request
from pathlib import Path

ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text().strip()
req = urllib.request.Request(
    "https://debian.seczio.com/api/fleet",
    headers={"Authorization": "Bearer " + ADMIN, "User-Agent": "Mozilla/5.0 (WinRTCS-Console)"},
)
d = json.loads(urllib.request.urlopen(req, timeout=60).read().decode())
hosts = [
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
by = {h["host"]: h for h in d["hosts"]}
for h in hosts:
    x = by.get(h, {})
    print(
        f"{h}: {x.get('presence')} state={x.get('state')} "
        f"gryxa={x.get('has_gryxa')} beat={x.get('beat')}"
    )
print("counts", d.get("counts"))
