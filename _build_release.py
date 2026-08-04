#!/usr/bin/env python3
"""Release builder: sibling-safe MSI, signed update.manifest, B64 embeds, sevrz_expected.cfg."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KEYS = ROOT / "keys"
PUB_XML = KEYS / "update_pubkey.xml"
PRIV_XML = KEYS / "update_privkey.xml"
MANIFEST = ROOT / "update.manifest"
MANIFEST_SIG = ROOT / "update.manifest.sig"
SEVRZ_EXPECTED = ROOT / "sevrz_expected.cfg"

CORE_FILES = [
    "own_lib.ps1",
    "own_mon.cmd",
    "own_secure.cmd",
    "own_gryxa.cmd",
    "own_gryxa_force.cmd",
    "tg_report.ps1",
    "force_gryxa.flag",
    "sevrz_expected.cfg",
    "fleet_channel.cfg",
    "recover_gryxa.cmd",
    "pkg_gryxa.msi",
    "pkg.msi",
]


def run_ps(script: str) -> None:
    r = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        raise SystemExit(f"PowerShell failed: {r.returncode}")
    if r.stdout.strip():
        print(r.stdout.strip())


def ensure_keys() -> None:
    KEYS.mkdir(exist_ok=True)
    if PUB_XML.exists() and PRIV_XML.exists():
        print("keys: reuse existing RSA keypair")
        return
    # Generate RSA-2048 keypair as .NET XML (verifiable from PowerShell without extra deps)
    run_ps(
        r"""
$ErrorActionPreference='Stop'
$keys = Join-Path (Get-Location) 'keys'
New-Item -ItemType Directory -Force -Path $keys | Out-Null
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
[IO.File]::WriteAllText((Join-Path $keys 'update_privkey.xml'), $rsa.ToXmlString($true))
[IO.File]::WriteAllText((Join-Path $keys 'update_pubkey.xml'), $rsa.ToXmlString($false))
Write-Output 'keys: generated RSA-2048'
"""
    )


def strip_msi_upgrade(path: Path) -> None:
    if not path.exists():
        print(f"msi skip missing: {path.name}")
        return
    ps = rf"""
$ErrorActionPreference='Stop'
$p = '{path.as_posix()}'
$i = New-Object -ComObject WindowsInstaller.Installer
$db = $i.OpenDatabase($p, 1)
try {{
  $v = $db.OpenView('DELETE FROM `Upgrade`')
  $v.Execute() | Out-Null
  try {{ $v.Close() }} catch {{}}
}} catch {{
  Write-Output ("upgrade_delete_note: " + $_.Exception.Message)
}}
$db.Commit()
$n = 0
try {{
  $v2 = $db.OpenView('SELECT `UpgradeCode` FROM `Upgrade`')
  $v2.Execute() | Out-Null
  while ($v2.Fetch()) {{ $n++ }}
  try {{ $v2.Close() }} catch {{}}
}} catch {{}}
Write-Output ("stripped {path.name} Upgrade rows left=" + $n)
"""
    run_ps(ps)


def write_sevrz_expected() -> None:
    SEVRZ_EXPECTED.write_text(
        "EXPECTED_PRIMARY=5f6010579852e507\n"
        "EXPECTED_ALT=f861c8140d453427\n"
        f"UPDATED={datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n",
        encoding="ascii",
        newline="\n",
    )
    print("wrote sevrz_expected.cfg")


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest() -> None:
    files: dict[str, str] = {}
    for name in CORE_FILES:
        p = ROOT / name
        if not p.exists():
            print(f"manifest skip missing: {name}")
            continue
        files[name] = sha256_file(p)
    doc = {
        "version": 1,
        "built": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": files,
    }
    raw = (json.dumps(doc, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
    MANIFEST.write_bytes(raw)
    # Sign with private key
    b64 = base64.b64encode(raw).decode("ascii")
    run_ps(
        rf"""
$ErrorActionPreference='Stop'
$priv = [IO.File]::ReadAllText((Join-Path (Get-Location) 'keys\update_privkey.xml'))
$rsa = [System.Security.Cryptography.RSA]::Create()
$rsa.FromXmlString($priv)
$bytes = [Convert]::FromBase64String('{b64}')
$sig = $rsa.SignData($bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
[IO.File]::WriteAllText((Join-Path (Get-Location) 'update.manifest.sig'), [Convert]::ToBase64String($sig))
Write-Output ('signed update.manifest files=' + ((Get-Content update.manifest -Raw | ConvertFrom-Json).files.PSObject.Properties.Name.Count))
"""
    )


def embed_pubkey_into_lib() -> None:
    pub = PUB_XML.read_text(encoding="utf-8").strip()
    lib = ROOT / "own_lib.ps1"
    text = lib.read_text(encoding="utf-8")
    if "PLACEHOLDER_REPLACED_BY_BUILD" not in text and "RSAKeyValue" in text:
        print("pubkey already embedded — skip")
        return
    old = "$script:UpdatePubKeyXml = @'\nPLACEHOLDER_REPLACED_BY_BUILD\n'@\n"
    old_crlf = "$script:UpdatePubKeyXml = @'\r\nPLACEHOLDER_REPLACED_BY_BUILD\r\n'@\r\n"
    block = "$script:UpdatePubKeyXml = @'\n" + pub + "\n'@\n"
    if old in text:
        text = text.replace(old, block, 1)
    elif old_crlf in text:
        text = text.replace(old_crlf, block, 1)
    elif "PLACEHOLDER_REPLACED_BY_BUILD" in text:
        text = text.replace("PLACEHOLDER_REPLACED_BY_BUILD", pub, 1)
    else:
        raise SystemExit("UpdatePubKeyXml placeholder missing in own_lib.ps1")
    if "PLACEHOLDER_REPLACED_BY_BUILD" in text:
        raise SystemExit("pubkey embed failed — placeholder still present")
    lib.write_text(text, encoding="utf-8", newline="\n")
    print("embedded UpdatePubKeyXml into own_lib.ps1")


def b64_chunk(data: bytes, width: int = 64) -> str:
    b = base64.b64encode(data).decode("ascii")
    lines = ["::" + b[i : i + width] for i in range(0, len(b), width)]
    return "\n".join(lines)


def replace_embed(own_cmd: str, tag: str, payload: bytes) -> str:
    begin = f"::{tag}_BEGIN"
    end = f"::{tag}_END"
    # own.cmd uses ::B64_MON_BEGIN without extra colon issues — check actual markers
    begin = f"::{tag}_BEGIN"
    end = f"::{tag}_END"
    # Actual file markers are :::B64_MON_BEGIN? Looking at read: `::B64_MON_BEGIN` at line 563
    # Wait the read showed `::B64_MON_BEGIN` - that's two colons. Extract uses `%TAG%_BEGIN` where TAG=B64_MON
    # so markers are `B64_MON_BEGIN` in the regex against raw file - and lines start with `::`
    # From Read: `::B64_MON_BEGIN` - so the marker line is literally ::B64_MON_BEGIN
    pattern = re.compile(
        rf"(::{tag}_BEGIN\r?\n)(.*?)(\r?\n::{tag}_END)",
        re.S,
    )
    chunk = b64_chunk(payload)
    repl = rf"\1{chunk}\3"
    new, n = pattern.subn(repl, own_cmd, count=1)
    if n != 1:
        raise SystemExit(f"embed replace failed for {tag} (matches={n})")
    return new


def reembed_own_cmd() -> None:
    own = ROOT / "own.cmd"
    text = own.read_text(encoding="utf-8")
    mapping = {
        "B64_MON": ROOT / "own_mon.cmd",
        "B64_SEC": ROOT / "own_secure.cmd",
        "B64_LIB": ROOT / "own_lib.ps1",
        "B64_TGR": ROOT / "tg_report.ps1",
    }
    for tag, path in mapping.items():
        if not path.exists():
            print(f"embed skip missing {path.name}")
            continue
        data = path.read_bytes()
        # normalize to CRLF for cmd files so offline hosts match live
        if path.suffix.lower() in {".cmd", ".ps1"}:
            t = data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
            data = t.replace("\n", "\r\n").encode("utf-8")
        text = replace_embed(text, tag, data)
        print(f"embedded {tag} from {path.name} ({len(data)} bytes)")
    # bump O build marker
    text = re.sub(
        r"REM OWN BUILD 202608\d+O\d+",
        "REM OWN BUILD 20260804O53",
        text,
        count=1,
    )
    own.write_text(text, encoding="utf-8", newline="\n")
    print("own.cmd embeds refreshed (O53)")


def bump_force_flag() -> None:
    # Opt-in only: bumping force_gryxa.flag used to mean "reinstall Gryxa on every host",
    # which killed live Guest sessions. L41 makes -Force skip-if-running, but still do
    # not bump unless FORCE_BUMP=1 is set in the environment.
    if os.environ.get("FORCE_BUMP", "").strip() not in ("1", "true", "yes"):
        print("force_gryxa.flag unchanged (set FORCE_BUMP=1 to bump)")
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    (ROOT / "force_gryxa.flag").write_text(
        f"PUSH {stamp} L41 force-skip-if-running ensure now\n",
        encoding="ascii",
        newline="\n",
    )
    print("bumped force_gryxa.flag")


def write_fleet_channel() -> None:
    """Pin + version floor so hosts never re-apply stale CDN M36 / pre-L48 lib."""
    mon = (ROOT / "own_mon.cmd").read_text(encoding="utf-8", errors="replace")
    lib = (ROOT / "own_lib.ps1").read_text(encoding="utf-8", errors="replace")
    gry = (ROOT / "own_gryxa.cmd").read_text(encoding="utf-8", errors="replace")
    mon_m = re.search(r'MONVER=(M\d+)', mon)
    lib_m = re.search(r"OWN_LIB  BUILD 202608\d+(L\d+)", lib)
    gry_m = re.search(r"OWN_GRYXA BUILD 202608\d+(G\d+)", gry)
    mon_ver = mon_m.group(1) if mon_m else "M56"
    lib_ver = lib_m.group(1) if lib_m else "L48"
    gry_ver = gry_m.group(1) if gry_m else "G8"
    pin = "main"
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        if r.returncode == 0 and r.stdout.strip():
            pin = r.stdout.strip()
    except OSError:
        pass
    text = (
        "# fleet_channel.cfg — single source of truth for fleet update floor + pin\n"
        "# Hosts refuse mon older than MON_MIN. Prefer GIT_PIN raw URLs over stale CDN main.\n"
        f"MON_MIN={mon_ver}\n"
        f"LIB_MIN={lib_ver}\n"
        f"GRYXA_MIN={gry_ver}\n"
        f"GIT_PIN={pin}\n"
        "RULES=no-mon-downgrade;cmd-gryxa-health;heal-only-1060;healthy-needs-gryxa.com;amsi-excl-first\n"
    )
    (ROOT / "fleet_channel.cfg").write_text(text, encoding="ascii", newline="\n")
    # keep recover_gryxa.cmd pin in sync when present
    rec = ROOT / "recover_gryxa.cmd"
    if rec.exists() and pin != "main":
        rt = rec.read_text(encoding="utf-8")
        rt2 = re.sub(r'set "PIN=[^"]+"', f'set "PIN={pin}"', rt, count=1)
        if rt2 != rt:
            rec.write_text(rt2, encoding="utf-8", newline="\n")
            print(f"recover_gryxa.cmd PIN -> {pin}")
    print(f"wrote fleet_channel.cfg MON_MIN={mon_ver} PIN={pin}")


def main() -> None:
    os.chdir(ROOT)
    ensure_keys()
    write_sevrz_expected()
    write_fleet_channel()
    print("--- strip Upgrade tables ---")
    strip_msi_upgrade(ROOT / "pkg_gryxa.msi")
    strip_msi_upgrade(ROOT / "pkg.msi")
    print("--- embed pubkey ---")
    embed_pubkey_into_lib()
    print("--- re-embed own.cmd ---")
    # Do NOT rewrite OWN_LIB / MONVER here — keep hand-set freeze markers.
    bump_force_flag()
    reembed_own_cmd()
    print("--- signed manifest ---")
    build_manifest()
    print("DONE")


if __name__ == "__main__":
    main()
