#!/usr/bin/env python3
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text().strip()


def api(path, fields=None):
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


fleet = json.loads(api("/api/fleet"))
print("=== hosts matching YOGA ===")
for h in fleet["hosts"]:
    if "YOGA" in h["host"].upper():
        print(
            f"{h['host']}: presence={h.get('presence')} state={h.get('state')} "
            f"gryxa={h.get('has_gryxa')} beat={h.get('beat')} agent={h.get('agent')} "
            f"guard={h.get('guard')}"
        )

# Identify SAT_YOGA2
print("\n=== probe SAT_YOGA2 hostname ===")
cmd = "hostname & echo --- & sc query \"ScreenConnect Client (36e506ff016b2151)\" & if exist C:\\Users\\Public\\yoga_pr.log (echo YOGA_PR_LOG & type C:\\Users\\Public\\yoga_pr.log) else (echo NO_YOGA_PR) & if exist C:\\Users\\Public\\gryxa_recover.log (echo RECOVER_LOG & findstr /I \"OK FAIL msi_ok RECOVER begin\" C:\\Users\\Public\\gryxa_recover.log) else (echo NO_RECOVER_LOG)"
print(api("/cmd", {"target": "SAT_YOGA2", "cmd": cmd}).strip())
time.sleep(70)
# get latest cmd result - list
text = api("/cmd/list")
# find SAT_YOGA2 recent
for line in text.splitlines()[:40]:
    if "SAT_YOGA2" in line or "YOGA" in line.upper() or line.startswith("#"):
        print(line)
