@echo off
rem WINRTCS_PAYLOAD 0.1.6 - force the guard gate this tick + reset the external-kill pause
rem + retire the direct-Telegram digest (guard 0.1.4 reports to the VPS; the bot token is
rem server-side only now - CASES.md C20).
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
echo 0>"%ZD%\extkill.cnt"
del /f /q "%ZD%\digest.state" "%ZD%\digest.hb" "%ZD%\notify.cfg" "%ZD%\digest.cfg" >nul 2>&1
echo [%DATE% %TIME%] guard_0.1.4_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
