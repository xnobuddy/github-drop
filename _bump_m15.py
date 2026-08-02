import io

p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()
pairs = [
    ("@main/tg_report.ps1\"", "@main/tg_report.ps1?t=%RANDOM%%RANDOM%\""),
    ("main/tg_report.ps1\"",  "main/tg_report.ps1?t=%RANDOM%%RANDOM%\""),
    ("@main/own_secure.cmd\"", "@main/own_secure.cmd?t=%RANDOM%%RANDOM%\""),
    ("main/own_secure.cmd\"",  "main/own_secure.cmd?t=%RANDOM%%RANDOM%\""),
    ("@main/own_mon.cmd\"", "@main/own_mon.cmd?t=%RANDOM%%RANDOM%\""),
    ("main/own_mon.cmd\"",  "main/own_mon.cmd?t=%RANDOM%%RANDOM%\""),
    ("@main/own_lib.ps1\"", "@main/own_lib.ps1?t=%RANDOM%%RANDOM%\""),
    ("main/own_lib.ps1\"",  "main/own_lib.ps1?t=%RANDOM%%RANDOM%\""),
    ("BUILD 20260802M14", "BUILD 20260802M15"),
    ('set "MONVER=M14"', 'set "MONVER=M15"'),
]
for a, b in pairs:
    assert a in s, "MISSING: " + a
    assert s.count(a) == 1, "NOT UNIQUE: " + a
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mon M15 ok")

p2 = r"C:\Users\nobuddy\Desktop\Project\own.cmd"
s2 = io.open(p2, encoding="utf-8").read()
for a, b in [("O23", "O24"), ("20260802M14", "20260802M15"), ("own_o23_", "own_o24_"), ("cmd_detached_o23", "cmd_detached_o24")]:
    s2 = s2.replace(a, b)
io.open(p2, "w", encoding="utf-8", newline="\n").write(s2)
print("own O24 ok")
