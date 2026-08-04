from __future__ import annotations
from pathlib import Path

m = Path(r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd").read_text(encoding="utf-8")
start = m.find('if "%FORCE_G%"=="1"')
print("start", start)
print(repr(m[start : start + 480]))
print("--- needle check ---")
# Exact from file
end = m.find("goto :GryxaAfter", start)
end = m.find(")", end) + 1
block = m[start:end]
print("extracted block:")
print(block)
print("---")
a = m.find("rem Deep or missing: gryxa-ensure only")
b = m.find("\n:GryxaAfter\n", a)
print("a", a, "b", b)
print("EnsureGryxaMust in deep", "call :EnsureGryxaMust" in m[a:b])
