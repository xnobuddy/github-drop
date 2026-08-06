#!/usr/bin/env python3
"""WinRTCS TRUST keygen (C24): one-time offline RSA-2048 keypair.

PRIVATE KEY NEVER leaves this machine and is NEVER committed to the repo.
- private:  Desktop\\winrtcs_keys\\sign_private.pem  (back it up offline; losing it
            means updates can never be signed again - fleet freezes safely, no brick)
- public:   modulus/exponent get embedded into the agent (not secret)
"""
from __future__ import annotations

import base64
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

KEYDIR = (Path(__file__).resolve().parent / "secrets" / "winrtcs_keys")
PRIV = KEYDIR / "sign_private.pem"
PUB = KEYDIR / "sign_public.txt"


def main() -> None:
    if PRIV.exists():
        print(f"REFUSING to overwrite existing key: {PRIV}")
        print("Delete it by hand only if you are rotating on purpose.")
        sys.exit(2)
    KEYDIR.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    )
    PRIV.write_bytes(pem)
    nums = key.public_key().public_numbers()
    mod = base64.b64encode(nums.n.to_bytes(256, "big")).decode()
    exp = base64.b64encode(nums.e.to_bytes(3, "big")).decode()
    PUB.write_text(f"MOD={mod}\nEXP={exp}\n", encoding="ascii")
    try:
        import ctypes
        ctypes.windll.kernel32.SetFileAttributesW(str(PRIV), 2)  # hidden
    except Exception:
        pass
    print(f"private: {PRIV}")
    print(f"public:  {PUB}")
    print(f"\nMOD={mod}\nEXP={exp}")


if __name__ == "__main__":
    main()
