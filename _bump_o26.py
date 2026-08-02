import io

p = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s = io.open(p, encoding="utf-8").read()
for a, b in [("O25", "O26"), ("20260802L5", "20260802L6"), ("20260802T8", "20260802T9"),
             ("own_o25_", "own_o26_"), ("cmd_detached_o25", "cmd_detached_o26"),
             ("order=msi_then_primary_then_nuke_foreign", "order=exterminate_then_repair_then_install")]:
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("own O26 ok")

p2 = r"C:\Users\nobuddy\Desktop\Project\_build_embed.py"
s2 = io.open(p2, encoding="utf-8").read()
s2 = s2.replace("'o22', 'o21'", "'o25', 'o24', 'o23', 'o22', 'o21'")
s2 = s2.replace("'20260802L3', '20260802L2'", "'20260802L5', '20260802L4', '20260802L3', '20260802L2'")
s2 = s2.replace("'20260802M13', '20260802M12'", "'20260802M15', '20260802M14', '20260802M13', '20260802M12'")
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("build badlist ok")
