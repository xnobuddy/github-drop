# Rebuild + verify embedded base64 payloads inside own.cmd (MON/SEC/TGR/LIB/NTF).
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
if (ROOT / "notify.cfg").is_file():
    SRC["NTF"] = ROOT / "notify.cfg"

def b64_lines(data: bytes, width: int = 76):
    s = base64.b64encode(data).decode("ascii")
    return [s[i : i + width] for i in range(0, len(s), width)]

def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()[:16]

text = OWN.read_text(encoding="utf-8", errors="replace")

for tag, src in SRC.items():
    raw = src.read_bytes()
    block = "\n".join(b64_lines(raw))
    pat = re.compile(
        r"::B64_" + tag + r"_BEGIN\r?\n(.*)\r?\n::B64_" + tag + r"_END",
        re.S,
    )
    m = pat.search(text)
    if not m:
        print(f"FAIL: B64_{tag} markers not found")
        sys.exit(1)
    start = m.start()
    end = m.end()
    replacement = f"::B64_{tag}_BEGIN\n{block}\n::B64_{tag}_END"
    text = text[:start] + replacement + text[end:]
    print(f"embed {tag}: {len(raw)} bytes sha={sha(raw)}")

OWN.write_text(text, encoding="utf-8", newline="\n")

text = OWN.read_text(encoding="utf-8", errors="replace")
ok = True
for tag, src in SRC.items():
    m = re.search(
        r"::B64_" + tag + r"_BEGIN\n(.*?)\n::B64_" + tag + r"_END",
        text,
        re.S,
    )
    dec = base64.b64decode(m.group(1).replace("\n", "").replace("\r", ""))
    srcb = src.read_bytes()
    match = dec == srcb
    ok &= match
    print(f"verify {tag}: {'OK' if match else 'MISMATCH'} dec={len(dec)} src={len(srcb)}")

if re.search(r"echo BOT_TOKEN=", text):
    print("WARN plaintext BOT_TOKEN echo still present")
    ok = False
print("BUILD OK" if ok else "BUILD FAILED")
sys.exit(0 if ok else 1)
