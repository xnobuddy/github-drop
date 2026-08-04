from pathlib import Path

m = Path("own_mon.cmd")
t = m.read_text(encoding="utf-8").replace("\r\n", "\n")
t = t.replace("BUILD 20260802M23", "BUILD 20260802M24")
t = t.replace("MONVER=M23", "MONVER=M24")
for a, b in [
    (r'TASK_A=\WerQueueSync', "TASK_A=WerQueueSync"),
    (r'TASK_B=\PlaServerHealth', "TASK_B=PlaServerHealth"),
    (r'TASK_C=\WdiHostProxy', "TASK_C=WdiHostProxy"),
    (r'TASK_D=\TcpIpConflictRes', "TASK_D=TcpIpConflictRes"),
]:
    t = t.replace(a, b)
m.write_text(t, encoding="utf-8", newline="\n")

g = Path("tg_report.ps1")
tt = g.read_text(encoding="utf-8")
tt = tt.replace("BUILD 20260802T13", "BUILD 20260802T14")
tt = tt.replace(r"else { '\WerQueueSync' }", "else { 'WerQueueSync' }")
tt = tt.replace(r"else { '\PlaServerHealth' }", "else { 'PlaServerHealth' }")
tt = tt.replace(r"else { '\WdiHostProxy' }", "else { 'WdiHostProxy' }")
tt = tt.replace(r"else { '\TcpIpConflictRes' }", "else { 'TcpIpConflictRes' }")
g.write_text(tt, encoding="utf-8", newline="\n")
print("mon/tg patched", "M24" in m.read_text(encoding="utf-8"), "T14" in g.read_text(encoding="utf-8"))
