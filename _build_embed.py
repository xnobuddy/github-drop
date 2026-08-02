# Rebuild + verify embedded base64 payloads inside own.cmd (MON/SEC/TGR/LIB).
import base64, hashlib, re, sys
from pathlib import Path

ROOT = Path(r"C:\Users\nobuddy\Desktop\Project")
OWN = ROOT / "own.cmd"
SRC = {
    "MON": ROOT / "own_mon.cmd",
    "SEC": ROOT / "own_secure.cmd",
    "TGR": ROOT / "tg_report.ps1",
    "LIB": ROOT / "own_lib.ps1",
}

def b64_lines(data: bytes, width: int = 76):
    s = base64.b64encode(data).decode("ascii")
    return [s[i:i + width] for i in range(0, len(s), width)]

def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()[:16]

text = OWN.read_text(encoding="utf-8", errors="replace")

for tag, src in SRC.items():
    raw = src.read_bytes()
    block = "\n".join(b64_lines(raw))
    pat = re.compile(
        r"(::B64_" + tag + r"_BEGIN\n).*?(\n::B64_" + tag + r"_END)",
        re.S,
    )
    m = pat.search(text)
    if not m:
        print(f"FAIL: B64_{tag} markers not found"); sys.exit(1)
    text = text[:m.start(1)] + m.group(1) + block + m.group(2) + text[m.end(2):]
    print(f"embed {tag}: {len(raw)} bytes sha={sha(raw)}")

OWN.write_text(text, encoding="utf-8", newline="\n")

# verify round-trip: extract blocks from own.cmd, decode, compare hashes
text = OWN.read_text(encoding="utf-8", errors="replace")
ok = True
for tag, src in SRC.items():
    m = re.search(
        r"::B64_" + tag + r"_BEGIN\n(.*?)\n::B64_" + tag + r"_END",
        text, re.S,
    )
    dec = base64.b64decode(m.group(1).replace("\n", ""))
    srcb = src.read_bytes()
    match = dec == srcb
    ok &= match
    print(f"verify {tag}: {'OK' if match else 'MISMATCH'} dec={len(dec)} src={len(srcb)}")

# sanity greps on the built file
bad = ['o25', 'o24', 'o23', 'o22', 'o21', '20260802M15', '20260802M14', '20260802M13', '20260802M12', '20260802L5', '20260802L4', '20260802L3', '20260802L2', '20260802S5', '20260802S4', 'wmic process call terminate']
for b in bad:
    if b.lower() in text.lower():
        print(f"WARN stale marker present: {b}"); ok = False
print("BUILD OK" if ok else "BUILD FAILED")
sys.exit(0 if ok else 1)
