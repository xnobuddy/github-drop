@echo off
rem WINRTCS_PAYLOAD 0.1.8 - C26 fleet kick: force the guard gate once so hosts that already
rem have WinRTCS but never got Gryxa (or lost it) run guard immediately after this payload,
rem without waiting for the 1-3h stagger. Agent 0.0.7 then keeps the absent-fast-path alive.
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
>"%ZD%\guard.cnt" echo 9999
>"%ZD%\gryxa_boost.cnt" echo 15
echo [%DATE% %TIME%] c26_gryxa_force_gate host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
