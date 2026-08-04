from __future__ import annotations

from pathlib import Path

mon = Path(r"C:\Users\nobuddy\Desktop\Project\own_mon.cmd")
m = mon.read_text(encoding="utf-8")
assert "OWN_MON  BUILD 20260804M48" in m, "expected clean M48 base"
assert m.count(":GryxaAfter") == 3

m = m.replace("OWN_MON  BUILD 20260804M48", "OWN_MON  BUILD 20260804M49", 1)
m = m.replace('set "MONVER=M48"', 'set "MONVER=M49"', 1)
if "M49: FREEZE" not in m:
    m = m.replace(
        "rem  M48: HANDS-OFF all SC interrupt",
        "rem  M49: FREEZE - no auto Gryxa msiexec from mon; start-only; manual force only.\n"
        "rem  M48: HANDS-OFF all SC interrupt",
        1,
    )

# --- force flag: ack only ---
force_start = m.find('if "%FORCE_G%"=="1" (')
assert force_start > 0
force_end = m.find("  goto :GryxaAfter\n)", force_start)
assert force_end > force_start, "force end missing"
force_end = force_end + len("  goto :GryxaAfter\n)")
old_force = m[force_start:force_end]
assert "gryxa-ensure -Deep -Force" in old_force
new_force = (
    'if "%FORCE_G%"=="1" (\n'
    '  echo gryxa_force_push_L46_ack_no_install>>"%LOG%"\n'
    '  if exist "%WD%\\force_gryxa.new" copy /y "%WD%\\force_gryxa.new" "%WD%\\force_gryxa.done" >nul 2>&1\n'
    "  goto :GryxaAfter\n"
    ")"
)
m = m[:force_start] + new_force + m[force_end:]

# --- deep/missing block → start-only ---
deep_start = m.find("rem Deep or missing: gryxa-ensure only")
assert deep_start > 0
label = m.find("\n:GryxaAfter\n", deep_start)
assert label > deep_start, "label after deep"
# keep the newline before label; replace from deep_start through char before \n:GryxaAfter
deep_end = label + 1  # points at ':' of :GryxaAfter

replacement = (
    "rem M49 FREEZE: start-only; never msiexec/own_gryxa from mon\n"
    'if exist "%WD%\\gryxa_install.cmd" del /f /q "%WD%\\gryxa_install.cmd" >nul 2>&1\n'
    'if exist "%WD%\\gryxa_msi.lock" del /f /q "%WD%\\gryxa_msi.lock" >nul 2>&1\n'
    'if "%GRYXA_OK%"=="0" (\n'
    '  echo gryxa_mon_start_only>>"%LOG%"\n'
    '  sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1\n'
    '  sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1\n'
    "  timeout /t 5 /nobreak >nul\n"
    '  sc query "ScreenConnect Client (%GRYXA_FP%)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul\n'
    '  if not errorlevel 1 set "GRYXA_OK=1"\n'
    '  if "%GRYXA_OK%"=="0" (\n'
    "    for /f \"tokens=2 delims=()\" %%a in ('sc query state^= all ^| findstr /C:\"SERVICE_NAME: ScreenConnect Client\"') do (\n"
    '      set "_FP=%%a"\n'
    '      set "_FP=!_FP: =!"\n'
    '      if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (\n'
    '        sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul\n'
    "        if not errorlevel 1 (\n"
    '          set "GRYXA_OK=1"\n'
    '          set "GRYXA_FP=!_FP!"\n'
    "        )\n"
    "      )\n"
    "    )\n"
    "  )\n"
    ")\n"
    'if "%DO_DEEP%"=="1" echo done>"%GRYXA_DEEP%"\n'
    'echo gryxa_freeze_no_auto_install>>"%LOG%"\n'
    "\n"
)
assert "gryxa_freeze_no_auto_install" in replacement
m = m[:deep_start] + replacement + m[deep_end:]
assert "gryxa_freeze_no_auto_install" in m
assert ":GryxaAfter" in m

# --- EnsureGryxaMust start-only (label only — not "call :EnsureGryxaMust") ---
c = m.find("\n:EnsureGryxaMust\n")
d = m.find("\n:TgGryxa\n")
assert c > 0 and d > c, f"labels c={c} d={d}"
c += 1  # point at ':'
d += 1
helper = (
    ":EnsureGryxaMust\n"
    "rem M49 FREEZE: start-only - never spawn own_gryxa / msiexec\n"
    'set "GRYXA_OK=0"\n'
    'if exist "%WD%\\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "GRYXA_FP=%%L"\n'
    'set "GSVC=ScreenConnect Client (%GRYXA_FP%)"\n'
    'if exist "%WD%\\gryxa_install.cmd" del /f /q "%WD%\\gryxa_install.cmd" >nul 2>&1\n'
    'sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul\n'
    "if not errorlevel 1 (\n"
    '  set "GRYXA_OK=1"\n'
    '  echo gryxa_must_already_alive>>"%LOG%"\n'
    "  exit /b 0\n"
    ")\n"
    'sc query "%GSVC%" >nul 2>&1\n'
    "if not errorlevel 1 (\n"
    '  echo gryxa_must_start_only>>"%LOG%"\n'
    '  sc config "%GSVC%" start= auto >nul 2>&1\n'
    '  sc start "%GSVC%" >nul 2>&1\n'
    "  timeout /t 8 /nobreak >nul\n"
    '  sc query "%GSVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul\n'
    '  if not errorlevel 1 set "GRYXA_OK=1"\n'
    ")\n"
    'if "%GRYXA_OK%"=="1" (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down_no_install>>"%LOG%")\n'
    "exit /b 0\n"
    "\n"
)
m = m[:c] + helper + m[d:]

# Kill InstallMsi sevrz path calling EnsureGryxaMust is now start-only - OK.
# Soften InstallMsi itself? M48 already skips calling InstallMsi for sevrz when hands-off.
# Verify no gryxa-ensure left in mon.
left = [ln for ln in m.splitlines() if "gryxa-ensure" in ln]
print("remaining gryxa-ensure:", left)

assert "MONVER=M49" in m
assert "gryxa_freeze_no_auto_install" in m
assert "gryxa_force_push_L46_ack_no_install" in m
assert "Action gryxa-ensure" not in m
assert "gryxa_must_cmd_spawned" not in m
assert m.count(":GryxaAfter") >= 1
assert "\n:EnsureGryxaMust\n" in m or m.startswith(":EnsureGryxaMust\n")
assert "\n:TgGryxa\n" in m
assert "tick done:" in m
assert "rem ── [G2] Gryxa MUST-RUN" in m
assert len(m.splitlines()) > 600

mon.write_text(m, encoding="utf-8", newline="\n")
print("mon M49 freeze OK, lines", len(m.splitlines()))
