from pathlib import Path

p = Path(__file__).with_name("wu7.cmd")
text = p.read_text(encoding="utf-8")
text = text.replace("\r\n", "\n").replace("\r", "\n")
for a, b in (
    ("\u2014", "-"),
    ("\u2013", "-"),
    ("\u2019", "'"),
    ("\u201c", '"'),
    ("\u201d", '"'),
):
    text = text.replace(a, b)
data = text.encode("ascii", errors="strict").replace(b"\n", b"\r\n")
p.write_bytes(data)
print("OK", p, "size", len(data), "crlf", data.count(b"\r\n"))
