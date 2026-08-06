#!/usr/bin/env python3
"""WinRTCS fleet console - queue commands for one host or ALL, list results.

Usage:
  python winrtcs_cmd.py DESKTOP-XXXX "hostname /b & ipconfig | findstr IPv4"
  python winrtcs_cmd.py ALL "systeminfo | findstr /C:\"Boot Time\""
  python winrtcs_cmd.py -list

Commands run as SYSTEM on the target, picked up within ~1 min (agent tick),
output returns to Telegram and /cmd/list. The admin token never leaves this
machine and the VPS.
"""
from __future__ import annotations

import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://debian.seczio.com"
ADMIN = ((Path(__file__).resolve().parent / "secrets" / "admin_token.txt")).read_text().strip()


def call(path: str, fields: dict | None = None) -> str:
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    req.add_header("Authorization", "Bearer " + ADMIN)
    req.add_header("User-Agent", "Mozilla/5.0 (WinRTCS-Console)")  # CF WAF blocks python-urllib
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode(errors="replace")


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    if args[0] == "-list":
        print(call("/cmd/list"))
        return
    if len(args) < 2:
        print("need: target command")
        return
    target, cmd = args[0], " ".join(args[1:])
    print(call("/cmd", {"target": target, "cmd": cmd}))
    print("picked up within ~1 min; result arrives on Telegram + -list")


if __name__ == "__main__":
    main()
