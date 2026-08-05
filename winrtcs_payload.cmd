@echo off
rem WINRTCS_PAYLOAD 0.1.7 - force the guard gate this tick so the current guard lights up
rem fleet-wide immediately. (Content fix only, no version bump: extkill reset now uses the
rem fd-trap-immune prefix form - C23. Payloads are one-shot; already-ran hosts keep 0.1.7.)
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
>"%ZD%\extkill.cnt" echo 0
echo [%DATE% %TIME%] guard_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
