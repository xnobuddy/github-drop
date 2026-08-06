"""Shared paths for local ops scripts (Sight / VPS helpers)."""
from __future__ import annotations

from pathlib import Path

OPS = Path(__file__).resolve().parent
PROJECT = OPS.parent
SECRETS = OPS / "secrets"
LOGS = OPS / "logs"
DESKTOP = Path.home() / "Desktop"


def secret_file(name: str) -> Path:
    """Resolve a secret file from ops/secrets, then Desktop (legacy)."""
    for p in (SECRETS / name, DESKTOP / name, PROJECT / name):
        if p.is_file():
            return p
    raise FileNotFoundError(
        f"{name} not found under {SECRETS} or {DESKTOP}"
    )


def read_secret(name: str) -> str:
    return secret_file(name).read_text(encoding="utf-8").strip()


def sign_key() -> Path:
    for p in (
        SECRETS / "winrtcs_keys" / "sign_private.pem",
        DESKTOP / "winrtcs_keys" / "sign_private.pem",
        PROJECT / "keys" / "sign_private.pem",
    ):
        if p.is_file():
            return p
    raise FileNotFoundError("sign_private.pem not found")
