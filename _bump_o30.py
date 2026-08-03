from pathlib import Path

p = Path(r"C:\Users\nobuddy\Desktop\Project\own.cmd")
t = p.read_text(encoding="utf-8")
if "::B64_NTF_BEGIN" not in t:
    t = t.rstrip() + "\n\n::B64_NTF_BEGIN\n::B64_NTF_END\n"
    print("NTF markers added")
for a, b in [
    ("O29", "O30"),
    ("20260802M19", "20260802M20"),
    ("20260802L8", "20260802L9"),
    ("own_o29_", "own_o30_"),
    ("cmd_detached_o29", "cmd_detached_o30"),
]:
    t = t.replace(a, b)
# ensure extract notify line exists
if 'call :Extract B64_NTF' not in t:
    t = t.replace(
        'call :Extract B64_LIB "%WD%\\own_lib.ps1"\necho embed_extract_done',
        'call :Extract B64_LIB "%WD%\\own_lib.ps1"\n'
        'if not exist "%WD%\\notify.cfg" call :Extract B64_NTF "%WD%\\notify.cfg"\n'
        'echo embed_extract_done',
    )
p.write_text(t, encoding="utf-8", newline="\n")
print("own O30 ready")
