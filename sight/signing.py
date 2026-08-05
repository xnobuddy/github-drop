"""RSA-SHA256 signatures for winrtcs.version (existing winrtcs_keys PEM).

Note: keys on disk are RSA, not ed25519. We sign with RSA-PKCS1v15-SHA256 and can
add an ed25519 key later without changing the .sig file format (alg= field).
"""
from __future__ import annotations

import base64
from pathlib import Path

try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
except ImportError:  # pragma: no cover
    hashes = None  # type: ignore


def sign_bytes(data: bytes, priv_pem: Path) -> str:
    if hashes is None:
        raise RuntimeError("cryptography package required for signing")
    key = serialization.load_pem_private_key(priv_pem.read_bytes(), password=None)
    sig = key.sign(data, padding.PKCS1v15(), hashes.SHA256())
    return "alg=rsa-sha256\nsig=" + base64.b64encode(sig).decode("ascii") + "\n"


def verify_bytes(data: bytes, sig_text: str, pub_pem: Path | None = None, mod_exp: Path | None = None) -> bool:
    if hashes is None:
        return False
    sig_b64 = ""
    for line in sig_text.splitlines():
        if line.startswith("sig="):
            sig_b64 = line[4:].strip()
    if not sig_b64:
        return False
    sig = base64.b64decode(sig_b64)
    if pub_pem and pub_pem.is_file():
        key = serialization.load_pem_public_key(pub_pem.read_bytes())
    else:
        return False
    try:
        key.verify(sig, data, padding.PKCS1v15(), hashes.SHA256())
        return True
    except Exception:
        return False
