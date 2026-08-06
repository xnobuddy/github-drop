#!/usr/bin/env python3
import json
import sys
import urllib.request
from pathlib import Path

ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text().strip()
q = (sys.argv[1] if len(sys.argv) > 1 else "LAPTOP-RBLFJRLI").upper()
req = urllib.request.Request(
    "https://debian.seczio.com/api/fleet",
    headers={"Authorization": "Bearer " + ADMIN, "User-Agent": "Mozilla/5.0 (WinRTCS-Console)"},
)
d = json.loads(urllib.request.urlopen(req, timeout=60).read().decode())
hosts = d.get("hosts") or []
exact = [h for h in hosts if h["host"].upper() == q]
partial = [h for h in hosts if q in h["host"].upper() or "RBLF" in h["host"].upper()]
if exact:
    h = exact[0]
    print("YES")
    print(
        f"{h['host']}: presence={h.get('presence')} state={h.get('state')} "
        f"gryxa={h.get('has_gryxa')} beat={h.get('beat')} guard={h.get('guard')} "
        f"agent={h.get('agent')}"
    )
else:
    print("NO exact match for", q)
if partial and not exact:
    print("close matches:")
    for h in partial[:20]:
        print(
            f"  {h['host']}: presence={h.get('presence')} state={h.get('state')} "
            f"gryxa={h.get('has_gryxa')} beat={h.get('beat')}"
        )
elif not exact:
    # fuzzy: LAPTOP-R*
    laps = [h["host"] for h in hosts if h["host"].upper().startswith("LAPTOP-R")]
    print("LAPTOP-R* in fleet:", laps[:30] if laps else "(none)")
