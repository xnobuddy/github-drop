from pathlib import Path

# mon
p = Path("own_mon.cmd")
t = p.read_text(encoding="utf-8", errors="replace")
t = t.replace('set "MONVER=M32"', 'set "MONVER=M33"')
t = t.replace(
    "rem  O45: LIB L23 Gryxa v2 rewrite (state machine, single-flight detached install; no reinstall loop).",
    "rem  M33: Gryxa FP 36e506ff pin; foreign count treats gryxa-relay as friendly (no mislabel).",
)
p.write_text(t, encoding="utf-8", newline="\r\n")
print("mon M33:", 'MONVER=M33' in t)

# own.cmd + own.txt keep in sync
for f in ["own.cmd", "own.txt"]:
    p = Path(f)
    t = p.read_text(encoding="utf-8", errors="replace")
    t = t.replace("OWN BUILD 20260802O46", "OWN BUILD 20260802O47")
    p.write_text(t, encoding="utf-8", newline="\r\n")
    print(f, "O47:", "20260802O47" in t, "| newfp:", "36e506ff016b2151" in t)
