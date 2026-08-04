#!/usr/bin/env python3
"""Zerocool build: CRLF-normalize cmd payloads, hash agent+payload, write zerocool.version.

Bump PAYLOAD_VER whenever zerocool_payload.cmd changes (that is what makes the
fleet re-run it once). Bump ZC_VER on releases. Then: commit + push.
Repo .gitattributes stores *.cmd as binary, so hashed bytes == served bytes.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ZC_VER = "0.0.1"
PAYLOAD_VER = "0.0.1"

CMD_FILES = [
    "zerocool_agent.cmd",
    "zerocool_run.cmd",
    "zerocool_payload.cmd",
    "zerocool_bootstrap.cmd",
]


def crlf_bytes(p: Path) -> bytes:
    raw = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    data = raw.replace(b"\n", b"\r\n")
    p.write_bytes(data)
    return data


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> None:
    hashes = {name: sha(crlf_bytes(ROOT / name)) for name in CMD_FILES}
    text = (
        f"ZC_VER={ZC_VER}\n"
        f"AGENT_SHA256={hashes['zerocool_agent.cmd']}\n"
        f"PAYLOAD_VER={PAYLOAD_VER}\n"
        f"PAYLOAD_SHA256={hashes['zerocool_payload.cmd']}\n"
    )
    (ROOT / "zerocool.version").write_text(text, encoding="ascii", newline="\n")
    print(f"ZC_VER={ZC_VER} PAYLOAD_VER={PAYLOAD_VER}")
    print(f"AGENT_SHA256={hashes['zerocool_agent.cmd']}")
    print(f"PAYLOAD_SHA256={hashes['zerocool_payload.cmd']}")


if __name__ == "__main__":
    main()
