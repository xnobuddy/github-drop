from pathlib import Path
import base64
import subprocess

root = Path(r"C:\Users\nobuddy\Desktop\Project\github-drop")
src = Path(r"C:\Users\nobuddy\Desktop\Project\Script.txt").read_bytes()
assert b"UNIFIED8" in src
assert b"Remove-ScreenConnectInstance" in src
b64 = base64.b64encode(src).decode("ascii")
(root / "updateA.b64").write_text("\n".join(b64[i : i + 76] for i in range(0, len(b64), 76)) + "\n", encoding="ascii")
print("updateA", len(src), (root / "updateA.b64").stat().st_size)
assert (root / "go.ps1").exists()
print("go.ps1", (root / "go.ps1").stat().st_size)
