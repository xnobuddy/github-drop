from pathlib import Path

# lib L30
p = Path("own_lib.ps1")
t = p.read_text(encoding="utf-8", errors="replace")
t = t.replace("OWN_LIB  BUILD 20260802L29", "OWN_LIB  BUILD 20260802L30")
t = t.replace(
    "# L29: Get-GryxaMsi falls back to TEMP install when .wucache cache-write is ACL-locked (was msi-unavailable).",
    "# L30: Repair-SCService NEVER msiexec /fa or /i (shared UpgradeCodes killed Gryxa sibling). Service-level heal only.",
)
p.write_text(t, encoding="utf-8", newline="\n")
seg = t.split("function Repair-SCService")[1]
seg = seg[: seg.index("\nfunction ")] if "\nfunction " in seg else seg
print("L30", "20260802L30" in t, "| /fa removed from Repair:", "/fa " not in seg, "| braces", t.count("{") - t.count("}"))

# mon M36
p = Path("own_mon.cmd")
t = p.read_text(encoding="utf-8", errors="replace")
t = t.replace('set "MONVER=M35"', 'set "MONVER=M36"')
p.write_text(t, encoding="utf-8", newline="\r\n")
print("M36", "MONVER=M36" in t, "| gryxa.com relay checks", t.count("gryxa.com"))

# own.txt O50
p = Path("own.txt")
t = p.read_text(encoding="utf-8", errors="replace")
t = t.replace("OWN BUILD 20260802O49", "OWN BUILD 20260802O50")
p.write_text(t, encoding="utf-8", newline="\r\n")
print("O50", "20260802O50" in t, "| GPRESENT", "GPRESENT" in t, "| parens", t.count("(") - t.count(")"))

# sync own.cmd to own.txt
Path("own.cmd").write_bytes(Path("own.txt").read_bytes())
print("synced", Path("own.cmd").read_bytes() == Path("own.txt").read_bytes())
