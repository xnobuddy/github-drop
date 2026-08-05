@echo off
rem WINRTCS_PAYLOAD 0.1.5 - force the guard gate this tick + reset the external-kill pause
rem + clean slate for shadow learning (guard 0.1.3 rollout: siege mode, resurrection cache,
rem sentinel third re-armer, one-way fleet digest - CASES.md C19).
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
echo 0>"%ZD%\extkill.cnt"
del /f /q "%ZD%\suspects.db" "%ZD%\suspects.top" "%ZD%\digest.state" >nul 2>&1
echo [%DATE% %TIME%] guard_0.1.3_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
