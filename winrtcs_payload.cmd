@echo off
rem WINRTCS_PAYLOAD 0.1.7 - force the guard gate this tick so guard 0.1.5's RMM radar
rem lights up fleet-wide immediately (first run = full RMM census per machine, batched
rem server-side into one alert - CASES.md C21).
setlocal
set "ZD=C:\ProgramData\WinRTCS"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
echo 9999>"%ZD%\guard.cnt"
echo 0>"%ZD%\extkill.cnt"
echo [%DATE% %TIME%] guard_0.1.5_forced host=%COMPUTERNAME%>>"%ZD%\payload.log"
endlocal & exit /b 0
