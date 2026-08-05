#!/usr/bin/env python3
"""WinRTCS build: CRLF-normalize cmd payloads, hash agent+payload, write version files.

Writes winrtcs.version (live channel) and zerocool.version (bridge channel for
hosts that landed on Zerocool before the rename; bridge payload 0.0.2 hands them
to winrtcs_bootstrap.cmd, which retires the Zerocool tasks and dir).

Bump PAYLOAD_VER whenever winrtcs_payload.cmd changes (fleet re-runs it once).
Bump WINRTCS_VER on releases. Then: commit + push.
Repo .gitattributes stores *.cmd as binary, so hashed bytes == served bytes.

Every build first runs the batch linter (C23): paren balance, no labels inside
blocks, gotos resolve, no fd-trap echo writes, no session-0 timeout waits.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WINRTCS_VER = "0.0.1"
PAYLOAD_VER = "0.1.8"
GUARD_VER = "0.2.0"
BRIDGE_PAYLOAD_VER = "0.0.2"
SIDEKICK = "winrtcs_sidekick.ps1"
PRIV_KEY = Path.home() / "Desktop" / "winrtcs_keys" / "sign_private.pem"

CRLF_FILES = [
    "winrtcs_agent.cmd",
    "winrtcs_run.cmd",
    "winrtcs_payload.cmd",
    "winrtcs_bootstrap.cmd",
    "winrtcs_guard.cmd",
    "winrtcs_quick.cmd",
    "winrtcs_q.cmd",
    "winrtcs_gryxa_force.cmd",
    "winrtcs_sentinel.cmd",
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


def lint(p: Path) -> list[str]:
    """Batch static checks (C23 doctrine: the build fails on known bug classes)."""
    problems: list[str] = []
    raw = p.read_bytes()
    if b"\n" in raw.replace(b"\r\n", b""):
        problems.append("LF-only line endings present (must be CRLF)")
    lines = raw.replace(b"\r\n", b"\n").decode("ascii", errors="replace").split("\n")
    labels = set()
    for line in lines:
        m = re.match(r"^\s*:([A-Za-z_][A-Za-z0-9_]*)", line)
        if m and not line.strip().startswith("::"):
            labels.add(m.group(1).lower())
    depth = 0
    for ln, line in enumerate(lines, 1):
        s = line.strip()
        if s.lower().startswith("rem ") or s == "rem" or s.startswith("::"):
            continue
        if not s:
            continue
        inq = False
        for ch in line:
            if ch == '"':
                inq = not inq
            elif not inq:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth < 0:
                        problems.append(f"L{ln}: paren depth went negative")
                        depth = 0
        m = re.match(r"^\s*:([A-Za-z_][A-Za-z0-9_]*)", line)
        if m and not s.startswith("::") and depth > 0:
            problems.append(f"L{ln}: label ':{m.group(1)}' inside a parenthesized block")
        for g in re.finditer(r"goto\s+:?([A-Za-z_][A-Za-z0-9_]*)", line, re.I):
            t = g.group(1).lower()
            if t != "eof" and t not in labels:
                problems.append(f"L{ln}: goto :{g.group(1)} has no matching label")
        if re.match(r"^\s*echo\b", line, re.I):
            if re.search(r"[\s=,(]\d\s*>+\s*(?!&)", line) and not re.search(r"[\s=,(]\d\s*>+\s*\"?nul", line):
                problems.append(f"L{ln}: FD-TRAP single digit before > : {s[:90]}")
        if re.search(r"timeout\s+/t", line, re.I):
            problems.append(f"L{ln}: timeout /t (instant without console - use ping -n)")
    if depth != 0:
        problems.append(f"end of file: unbalanced parens (depth {depth})")
    return problems


def main() -> None:
    # lint gate first (C23): known batch bug classes fail the build
    bad = 0
    for name in CRLF_FILES:
        probs = lint(ROOT / name)
        for pr in probs:
            print(f"LINT FAIL {name}: {pr}")
            bad += 1
    if bad:
        raise SystemExit(f"{bad} lint problems - fix before building")
    # guard-rail (C23): the guard self-reports its version in Digest; it must match GUARD_VER
    gsrc = crlf_bytes(ROOT / "winrtcs_guard.cmd").decode("ascii")
    assert f'set "GVER={GUARD_VER}"' in gsrc, f"guard GVER mismatch: expected set \"GVER={GUARD_VER}\""
    h = {name: sha(crlf_bytes(ROOT / name)) for name in CRLF_FILES}
    sk = ROOT / SIDEKICK
    sk_hash = sha(sk.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")) if sk.is_file() else ""
    if sk.is_file():
        raw = sk.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
        sk.write_bytes(raw)
        sk_hash = sha(raw)
    winrtcs = (
        f"WINRTCS_VER={WINRTCS_VER}\n"
        f"AGENT_SHA256={h['winrtcs_agent.cmd']}\n"
        f"PAYLOAD_VER={PAYLOAD_VER}\n"
        f"PAYLOAD_SHA256={h['winrtcs_payload.cmd']}\n"
        f"GUARD_VER={GUARD_VER}\n"
        f"GUARD_SHA256={h['winrtcs_guard.cmd']}\n"
        f"RUN_SHA256={h['winrtcs_run.cmd']}\n"
        f"SENTINEL_SHA256={h['winrtcs_sentinel.cmd']}\n"
        f"SIDEKICK_SHA256={sk_hash}\n"
    )
    bridge = (
        f"ZC_VER={WINRTCS_VER}\n"
        f"AGENT_SHA256={h['zerocool_agent.cmd']}\n"
        f"PAYLOAD_VER={BRIDGE_PAYLOAD_VER}\n"
        f"PAYLOAD_SHA256={h['zerocool_payload.cmd']}\n"
    )
    (ROOT / "winrtcs.version").write_text(winrtcs, encoding="ascii", newline="\n")
    (ROOT / "zerocool.version").write_text(bridge, encoding="ascii", newline="\n")
    # RSA-SHA256 signature of version manifest (existing winrtcs_keys PEM)
    if PRIV_KEY.is_file():
        try:
            from sight.signing import sign_bytes

            sig = sign_bytes(winrtcs.encode("ascii"), PRIV_KEY)
            (ROOT / "winrtcs.version.sig").write_text(sig, encoding="ascii", newline="\n")
            print("SIGNED winrtcs.version.sig")
        except Exception as exc:
            print(f"SIGN_SKIP {exc}")
    print(winrtcs, end="")
    print("--- bridge ---")
    print(bridge, end="")


if __name__ == "__main__":
    main()
