#!/usr/bin/env python3
import json
import sys
import urllib.request
from pathlib import Path

ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text().strip()
names = [
    "CRAIGLT02",
    "Duck",
    "RipTide1",
    "DESKTOP-JJP5B6C",
    "BILLL1951",
    "DESKTOP-NDTB9PF",
    "tomsLaptop",
    "DESKTOP-FASC59A",
    "DESKTOP-43T0RER",
    "DESKTOP-BDTMU13",
    "John59",
    "King-PC",
    "HALCONESBAPS",
    "DESKTOP-9RGIPHF",
]
if len(sys.argv) > 1:
    names = sys.argv[1:]

req = urllib.request.Request(
    "https://debian.seczio.com/api/fleet",
    headers={"Authorization": "Bearer " + ADMIN, "User-Agent": "Mozilla/5.0 (WinRTCS-Console)"},
)
d = json.loads(urllib.request.urlopen(req, timeout=60).read().decode())
by = {h["host"].upper(): h for h in d.get("hosts") or []}

yes, no = [], []
for n in names:
    h = by.get(n.upper())
    if h:
        yes.append(h)
        print(
            f"YES  {h['host']}: presence={h.get('presence')} state={h.get('state')} "
            f"gryxa={h.get('has_gryxa')} beat={h.get('beat')}"
        )
    else:
        no.append(n)
        # close: case/partial
        close = [
            x["host"]
            for x in d["hosts"]
            if n.upper() in x["host"].upper() or x["host"].upper() in n.upper()
        ]
        extra = f"  (close: {', '.join(close[:5])})" if close else ""
        print(f"NO   {n}{extra}")

print()
print(f"in_fleet={len(yes)} missing={len(no)}")
if no:
    print("missing:", ", ".join(no))
