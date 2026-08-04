from pathlib import Path

# Bump own.cmd O30->O31 markers for L10 RMM + T11
p = Path(r"C:\Users\nobuddy\Desktop\Project\own.cmd")
t = p.read_text(encoding="utf-8")
for a, b in [
    ("O30", "O31"),
    ("20260802O30", "20260802O31"),
    ("20260802M20", "20260802M21"),
    ("20260802L9", "20260802L10"),
    ("20260802T10", "20260802T11"),
]:
    t = t.replace(a, b)
p.write_text(t, encoding="utf-8", newline="\n")

m = Path(r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd")
mt = m.read_text(encoding="utf-8")
mt = mt.replace("OWN_MON  BUILD 20260802M20", "OWN_MON  BUILD 20260802M21")
mt = mt.replace('set "MONVER=M20"', 'set "MONVER=M21"')
m.write_text(mt, encoding="utf-8", newline="\n")

print("bumped O31/M21 markers")
