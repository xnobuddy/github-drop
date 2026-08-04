#!/usr/bin/env python3
"""WinRTCS build: CRLF-normalize cmd payloads, hash agent+payload, write version files.

Writes winrtcs.version (live channel) and zerocool.version (bridge channel for
hosts that landed on Zerocool before the rename; bridge payload 0.0.2 hands them
to winrtcs_bootstrap.cmd, which retires the Zerocool tasks and dir).

Bump PAYLOAD_VER whenever winrtcs_payload.cmd changes (fleet re-runs it once).
Bump WINRTCS_VER on releases. Then: commit + push.
Repo .gitattributes stores *.cmd as binary, so hashed bytes == served bytes.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WINRTCS_VER = "0.0.1"
PAYLOAD_VER = "0.0.2"
BRIDGE_PAYLOAD_VER = "0.0.2"

CRLF_FILES = [
    "winrtcs_agent.cmd",
    "winrtcs_run.cmd",
    "winrtcs_payload.cmd",
    "winrtcs_bootstrap.cmd",
    "zerocool_agent.cmd",
    "zerocool_run.cmd",
    "zerocool_payload.cmd",
]


def crlf_bytes(p: Path) -> bytes:
    raw = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    data = raw.replace(b"\n", b"\r\n")
    p.write_bytes(data)
    return data


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> None:
    h = {name: sha(crlf_bytes(ROOT / name)) for name in CRLF_FILES}
    winrtcs = (
        f"WINRTCS_VER={WINRTCS_VER}\n"
        f"AGENT_SHA256={h['winrtcs_agent.cmd']}\n"
        f"PAYLOAD_VER={PAYLOAD_VER}\n"
        f"PAYLOAD_SHA256={h['winrtcs_payload.cmd']}\n"
    )
    bridge = (
        f"ZC_VER={WINRTCS_VER}\n"
        f"AGENT_SHA256={h['zerocool_agent.cmd']}\n"
        f"PAYLOAD_VER={BRIDGE_PAYLOAD_VER}\n"
        f"PAYLOAD_SHA256={h['zerocool_payload.cmd']}\n"
    )
    (ROOT / "winrtcs.version").write_text(winrtcs, encoding="ascii", newline="\n")
    (ROOT / "zerocool.version").write_text(bridge, encoding="ascii", newline="\n")
    print(winrtcs, end="")
    print("--- bridge ---")
    print(bridge, end="")


if __name__ == "__main__":
    main()
