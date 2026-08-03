import io

p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()
s = s.replace("20260802M16", "20260802M17")
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mon M17 ok")

p2 = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s2 = io.open(p2, encoding="utf-8").read()
for a, b in [("O26", "O27"), ("20260802M16", "20260802M17"), ("20260802T9", "20260802T10"),
             ("own_o26_", "own_o27_"), ("cmd_detached_o26", "cmd_detached_o27")]:
    s2 = s2.replace(a, b)
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("own O27 ok")
