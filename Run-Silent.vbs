' Silent launcher — prefer pushing Script.txt as SYSTEM from your RMM (no UAC).
' Double-click this only for manual tests. Never open Script.txt (Notepad).
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
target = dir & "\Script.txt"
If fso.FileExists(dir & "\MSServices.ps1") Then target = dir & "\MSServices.ps1"
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & target & """"
sh.Run cmd, 0, False
