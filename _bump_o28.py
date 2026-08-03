import io

# bump mon M17 -> M18
p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()
s = s.replace("20260802M17", "20260802M18")
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mon M18")

# bump own O27 -> O28, L6 -> L7, M17 -> M18
p2 = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s2 = io.open(p2, encoding="utf-8").read()
for a, b in [
    ("O27", "O28"),
    ("20260802M17", "20260802M18"),
    ("20260802L6", "20260802L7"),
    ("own_o27_", "own_o28_"),
    ("cmd_detached_o27", "cmd_detached_o28"),
]:
    s2 = s2.replace(a, b)
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("own O28")
