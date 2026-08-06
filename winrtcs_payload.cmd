@echo off
rem WINRTCS_PAYLOAD 0.1.9 - SoftHide kick: force guard once so 0.2.2 ARP+ProgramFiles hide
rem lands fleet-wide without waiting for the 3h stagger. C26 absent-fast-path unchanged.
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
>"%ZD%\guard.cnt" echo 9999
>"%ZD%\gryxa_boost.cnt" echo 15
echo [%DATE% %TIME%] c26_gryxa_force_gate host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
