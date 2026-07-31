from pathlib import Path
import base64

root = Path(__file__).resolve().parent
proj = root.parent
src = (proj / "Script.txt").read_bytes()
assert b"UNIFIED6" in src
assert b"ps_abort_not_elevated" in src
b64 = base64.b64encode(src).decode("ascii")
wrapped = "\n".join(b64[i : i + 76] for i in range(0, len(b64), 76))
(root / "updateA.b64").write_text(wrapped + "\n", encoding="ascii")
print("updateA", len(src), (root / "updateA.b64").stat().st_size)

text = (root / "wu8.cmd").read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
for a, b in (("\u2014", "-"), ("\u2013", "-"), ("\u2019", "'"), ("\u201c", '"'), ("\u201d", '"')):
    text = text.replace(a, b)
data = text.encode("ascii").replace(b"\n", b"\r\n")
for name in ("wu8.cmd", "wu7.cmd"):
    (root / name).write_bytes(data)
print("wu8", len(data), b"WU8C" in data, b"UNIFIED6" in data)
