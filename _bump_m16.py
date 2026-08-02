import io

p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()
for a, b in [("BUILD 20260802M15", "BUILD 20260802M16"), ('set "MONVER=M15"', 'set "MONVER=M16"')]:
    assert a in s, "MISSING: " + a
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mon M16 ok")

p2 = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s2 = io.open(p2, encoding="utf-8").read()
for a, b in [("O24", "O25"), ("20260802M15", "20260802M16"), ("20260802L4", "20260802L5"),
             ("own_o24_", "own_o25_"), ("cmd_detached_o24", "cmd_detached_o25")]:
    s2 = s2.replace(a, b)
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("own O25 ok")
