@echo off
rem WINRTCS_PAYLOAD 0.0.2 - uninstall Gryxa (ScreenConnect FP 36e506ff016b2151) fleet-wide.
rem Keepers 5f6010579852e507 / f861c8140d453427 are never touched: service ops target the exact
rem gryxa FP only, and the MSI ProductCode is the gryxa-shared one (proven separate from keepers).
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "SVC=ScreenConnect Client (36e506ff016b2151)"
set "PCODE={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
set "LOG=%ZD%\payload.log"

sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] gryxa_absent_skip host=%COMPUTERNAME%>>"%LOG%"
  endlocal & exit /b 0
)

echo [%DATE% %TIME%] gryxa_uninstall_begin host=%COMPUTERNAME%>>"%LOG%"
sc stop "%SVC%" >nul 2>&1
timeout /t 3 /nobreak >nul 2>&1
sc delete "%SVC%" >nul 2>&1

msiexec /x %PCODE% /qn /norestart /l*v "%ZD%\msi_gryxa_uninstall.log" >nul 2>&1
echo [%DATE% %TIME%] msiexec_exit=!errorlevel!>>"%LOG%"

sc query "ScreenConnect Client (5f6010579852e507)" >nul 2>&1
set "K1=!errorlevel!"
sc query "ScreenConnect Client (f861c8140d453427)" >nul 2>&1
set "K2=!errorlevel!"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] gryxa_gone keeper1=!K1! keeper2=!K2!>>"%LOG%"
) else (
  echo [%DATE% %TIME%] gryxa_still_present keeper1=!K1! keeper2=!K2!>>"%LOG%"
)
endlocal & exit /b 0
