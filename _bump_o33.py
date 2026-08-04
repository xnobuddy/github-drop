from pathlib import Path

p = Path("own.cmd")
t = p.read_text(encoding="utf-8")
# normalize newlines for edit
t = t.replace("\r\n", "\n").replace("\r", "\n")
for a, b in [
    ("O32", "O33"),
    ("20260802O32", "20260802O33"),
    ("20260802M22", "20260802M23"),
    ("20260802L11", "20260802L12"),
    ("20260802T12", "20260802T13"),
    ("IDENTVER=6", "IDENTVER=7"),
]:
    t = t.replace(a, b)

old = """if not defined TASK_A set \"TASK_A=\\Microsoft\\Windows\\Diagnosis\\EvtCacheSync\"
if not defined TASK_B set \"TASK_B=\\Microsoft\\Windows\\PLA\\ServerHealth\"
if not defined TASK_C set \"TASK_C=\\Microsoft\\Windows\\WDI\\ResolutionHostProxy\"
if not defined TASK_D set \"TASK_D=\\Microsoft\\Windows\\Tcpip\\IpConflictResolver\""""
new = """if not defined TASK_A set \"TASK_A=\\WerQueueSync\"
if not defined TASK_B set \"TASK_B=\\PlaServerHealth\"
if not defined TASK_C set \"TASK_C=\\WdiHostProxy\"
if not defined TASK_D set \"TASK_D=\\TcpIpConflictRes\""""
if old not in t:
    raise SystemExit("defaults not found")
t = t.replace(old, new)
t = t.replace(
    "REM O33/L11: IDENTVER=7 unique names; tasks-ensure verifies Task To Run owns mon",
    "REM O33/L12: IDENTVER=7 ROOT-level task names (nested Microsoft\\Windows Create = Access Denied)",
)
# fix if previous replace made O33/L11 from O32/L11
t = t.replace(
    "REM O33/L11: IDENTVER=7 unique names; tasks-ensure verifies Task To Run owns mon\n"
    "REM (existence-only Query previously false-OKed Windows Diagnosis\\Scheduled).",
    "REM O33/L12: IDENTVER=7 ROOT-level names — nested Microsoft\\Windows\\* Create = Access Denied.",
)
t = t.replace(
    "REM OWN BUILD 20260802O33 - CRLF + unique detach runner + IDENTVER=7 task ownership",
    "REM OWN BUILD 20260802O33 - IDENTVER=7 root tasks + CRLF + Datto keep",
)
p.write_text(t, encoding="utf-8", newline="\n")
print("own.cmd text ready")
