from pathlib import Path

root = Path(__file__).resolve().parent
src = (root / "wu8.cmd").read_text(encoding="utf-8")
src = src.replace("\r\n", "\n").replace("\r", "\n")
for a, b in (("\u2014", "-"), ("\u2013", "-"), ("\u2019", "'"), ("\u201c", '"'), ("\u201d", '"')):
    src = src.replace(a, b)
data = src.encode("ascii").replace(b"\n", b"\r\n")
for name in ("wu8.cmd", "wu7.cmd"):
    (root / name).write_bytes(data)
    print(name, len(data), "WU8B" in src)
