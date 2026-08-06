#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text(encoding="utf-8").strip()
CMD_ID = int(sys.argv[1]) if len(sys.argv) > 1 else 640
HOST = sys.argv[2] if len(sys.argv) > 2 else "RRFD1-4-VS-SLOT"


def api(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode(errors="replace")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    for i in range(24):
        raw = api(f"/api/cmd/{CMD_ID}")
        try:
            j = json.loads(raw)
        except Exception:
            print(raw[:2000])
            time.sleep(5)
            continue
        results = j.get("results") or j.get("result") or []
        if isinstance(j, dict) and "out" in j:
            print(json.dumps(j, indent=2)[:8000])
            return 0
        hit = None
        for r in results:
            if str(r.get("host", "")).upper() == HOST.upper() or HOST.lower() in str(r).lower():
                hit = r
                break
        if hit:
            print(json.dumps(hit, indent=2, default=str)[:12000])
            # try fetch full out
            if "out" not in hit or not hit.get("out"):
                # some APIs nest
                print("keys", list(hit.keys()))
            return 0
        print(f"wait {i} results={len(results)} keys={list(j.keys())[:10]}")
        time.sleep(5)
    print("timeout")
    print(raw[:3000])
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
