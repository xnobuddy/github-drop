from pathlib import Path

lib = Path("own_lib.ps1").read_text(encoding="utf-8")
assert "Tag='Datto'" not in lib
assert "Is-DattoKeeper" in lib
assert "BUILD 20260802L10" in lib
assert "CentraStage" in lib  # only in keeper regex
assert lib.count("Tag=") >= 50

t = Path("tg_report.ps1").read_text(encoding="utf-8")
assert "keep-datto" in t
assert "BUILD 20260802T11" in t
assert "'Datto RMM'" not in t

o = Path("own.cmd").read_text(encoding="utf-8")
assert "OWN BUILD 20260802O31" in o
assert "20260802L10" in o
assert "20260802M21" in o

m = Path("own_mon.cmd").read_text(encoding="utf-8")
assert "MONVER=M21" in m

print("VERIFY OK")
print("RMM tags:", [line.split("Tag=")[1].split("'")[1] for line in lib.splitlines() if "Tag='" in line and "$rmm" not in line][:5], "...")
tags = [line.split("Tag=")[1].split("'")[1] for line in lib.splitlines() if "Tag='" in line and line.strip().startswith("@{")]
print("count", len(tags))
print("datto_in_tags", "Datto" in tags)
