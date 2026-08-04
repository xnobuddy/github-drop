@echo off
rem WINRTCS_PAYLOAD 0.0.1 - first beacon: proves the repo->machine push channel end to end.
rem This is the file you edit + bump PAYLOAD_VER in winrtcs_build.py to push any command fleet-wide.
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo [%DATE% %TIME%] winrtcs 0.0.1 online host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
