@echo off
rem WINRTCS_PAYLOAD 0.0.6 - force the guard gate to fire this same tick (guard 0.0.4 rollout).
rem The guard block (runs right after this payload) sees the high counter, downloads the
rem hash-pinned winrtcs_guard.cmd if needed, and executes the full health ladder + install.
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
echo [%DATE% %TIME%] gryxa_install_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
