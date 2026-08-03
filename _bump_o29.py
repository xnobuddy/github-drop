import io

# mon header + any leftover M18
p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()
s = s.replace("20260802M18", "20260802M19")
s = s.replace("20260802M17", "20260802M19")
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mon M19")

p2 = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s2 = io.open(p2, encoding="utf-8").read()
for a, b in [
    ("O28", "O29"),
    ("20260802M18", "20260802M19"),
    ("20260802L7", "20260802L8"),
    ("own_o28_", "own_o29_"),
    ("cmd_detached_o28", "cmd_detached_o29"),
]:
    s2 = s2.replace(a, b)
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("own O29")
