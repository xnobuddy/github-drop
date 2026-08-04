from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"C:\Users\nobuddy\Desktop\Project")

# ─── own_lib.ps1 ───
lib = ROOT / "own_lib.ps1"
t = lib.read_text(encoding="utf-8")
t = re.sub(r"# OWN_LIB  BUILD 20260804L\d+", "# OWN_LIB  BUILD 20260804L46", t, count=1)
if "L46: FREEZE" not in t:
    t = t.replace(
        "# L45: HANDS-OFF all ScreenConnect except Gryxa install-if-absent.\n",
        "# L46: FREEZE - never auto msiexec from mon/boot; start-only. Manual force only.\n"
        "# L45: HANDS-OFF all ScreenConnect except Gryxa install-if-absent.\n",
        1,
    )

old_fr = """function Find-RunningGryxaFp {
    $cfg = Get-GryxaFp
    if ($cfg -and (Test-ScRunning $cfg) -and (Test-IsGryxaFp $cfg)) { return $cfg }
    if ($script:GryxaExpectedFp -and (Test-ScRunning $script:GryxaExpectedFp)) { return $script:GryxaExpectedFp.ToLower() }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\\(([0-9a-f]{16})\\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            if (Test-IsGryxaFp $fp) { return $fp }
        }
    }
    return $null
}"""

new_fr = """function Find-RunningGryxaFp {
    # L46: ANY non-sevrz Running/Pending SC is live - never install over it.
    $cfg = Get-GryxaFp
    if ($cfg -and (Test-ScRunning $cfg) -and ($cfg -notin $script:SevrzKeep)) { return $cfg.ToLower() }
    if ($script:GryxaExpectedFp -and (Test-ScRunning $script:GryxaExpectedFp)) { return $script:GryxaExpectedFp.ToLower() }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\\(([0-9a-f]{16})\\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            return $fp
        }
    }
    return $null
}"""

if old_fr not in t:
    raise SystemExit("Find-RunningGryxaFp not found")
t = t.replace(old_fr, new_fr, 1)

start = t.find("function Invoke-GryxaEnsure {")
end = t.find("function Invoke-Exterminate {")
if start < 0 or end < 0:
    raise SystemExit("ensure markers missing")

new_ensure = """function Invoke-GryxaEnsure {
    # L46 FREEZE: never msiexec from mon/boot/force-flag. Start-only. Manual own_gryxa_force for install.
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $log = Join-Path $WorkDir 'gryxa_ensure.log'
    function GLog([string]$m) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction SilentlyContinue }

    foreach ($stale in @('gryxa_install.cmd', 'gryxa_msi.lock', 'own_gryxa.lock')) {
        $p = Join-Path $WorkDir $stale
        if (Test-Path -LiteralPath $p) {
            GLog "l46_abort_stale $stale"
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }

    $fp = Get-GryxaFp
    $exp = $script:GryxaExpectedFp
    if (-not $exp) { $exp = $fp }

    $running = Find-RunningGryxaFp
    if ($running) {
        Set-GryxaFp $running
        GLog "l46_live_ok fp=$running force=$Force deep=$Deep"
        if ($Deep) {
            $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
            $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
            return "HEALTHY|$running|running=1|deep=1|relay=$tcpR|ui=$tcpU|freeze=1"
        }
        return "HEALTHY|$running|running=1|freeze=1"
    }

    foreach ($tryFp in @($exp, $fp) | Where-Object { $_ } | Select-Object -Unique) {
        if (-not (Test-ScServiceExists $tryFp)) { continue }
        $name = "ScreenConnect Client ($tryFp)"
        GLog "l46_start_only fp=$tryFp"
        & sc.exe config $name start= auto 2>&1 | Out-Null
        & sc.exe start $name 2>&1 | Out-Null
        Start-Sleep -Seconds 5
        if (Test-ScRunning $tryFp) {
            Set-GryxaFp $tryFp
            return "HEALTHY|$tryFp|started=1|freeze=1"
        }
    }

    GLog "l46_absent_no_auto_install target=$exp"
    return "UNHEALTHY|$exp|absent-freeze-no-install"
}

"""
t = t[:start] + new_ensure + t[end:]

# boot: sc start only
if "gryxa-ensure -Deep -Force -NoWait" in t:
    t = t.replace(
        "('start /min \"\" powershell -NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Action gryxa-ensure -Deep -Force -NoWait -WorkDir \"{1}\" -Build BOOT' -f $libInBoot, $WorkDir),",
        "'rem L46 FREEZE boot sc start only',\n"
        "        'sc start \"ScreenConnect Client (36e506ff016b2151)\" >nul 2>&1',",
        1,
    )

lib.write_text(t, encoding="utf-8", newline="\n")
print("lib ok", "L46" in t[:200], "absent-freeze-no-install" in t)

# ─── own_mon.cmd ───
mon = ROOT / "own_mon.cmd"
m = mon.read_text(encoding="utf-8")
m = m.replace("OWN_MON  BUILD 20260804M48", "OWN_MON  BUILD 20260804M49", 1)
m = m.replace('set "MONVER=M48"', 'set "MONVER=M49"', 1)
if "M49: FREEZE" not in m:
    m = m.replace(
        "rem  M48: HANDS-OFF all SC interrupt",
        "rem  M49: FREEZE - no auto Gryxa msiexec from mon; start-only; manual force only.\n"
        "rem  M48: HANDS-OFF all SC interrupt",
        1,
    )

old_f = (
    'if "%FORCE_G%"=="1" (\n'
    '  echo gryxa_force_push>>"%LOG%"\n'
    '  if exist "%WD%\\own_lib.ps1" (\n'
    '    set "GRES="\n'
    '    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action gryxa-ensure -Deep -Force -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"\n'
    '    echo gryxa_force_result=!GRES!>>"%LOG%"\n'
    '    copy /y "%WD%\\force_gryxa.new" "%WD%\\force_gryxa.done" >nul 2>&1\n'
    '  )\n'
    '  goto :GryxaAfter\n'
    ')'
)
new_f = (
    'if "%FORCE_G%"=="1" (\n'
    '  echo gryxa_force_push_L46_ack_no_install>>"%LOG%"\n'
    '  if exist "%WD%\\force_gryxa.new" copy /y "%WD%\\force_gryxa.new" "%WD%\\force_gryxa.done" >nul 2>&1\n'
    '  goto :GryxaAfter\n'
    ')'
)
if old_f not in m:
    raise SystemExit("force block missing")
m = m.replace(old_f, new_f, 1)

old_g = (
    'rem Deep or missing: gryxa-ensure only (lib locks msiexec if Running)\n'
    'if exist "%WD%\\own_lib.ps1" (\n'
    '  set "GRES="\n'
    '  if "%DO_DEEP%"=="1" (\n'
    '    echo gryxa_deep_begin>>"%LOG%"\n'
    '    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action gryxa-ensure -Deep -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"\n'
    '  ) else (\n'
    '    for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\\own_lib.ps1" -Action gryxa-ensure -NoWait -WorkDir "%WD%" -Build %MONVER%`) do set "GRES=%%R"\n'
    '  )\n'
    '  echo gryxa_ensure_result=!GRES!>>"%LOG%"\n'
    '  rem M41: only mark OK on true HEALTHY|...running/started/svc-recreated — never INFLIGHT/spawned\n'
    '  echo !GRES!| findstr /I /B /C:"HEALTHY|" | findstr /I "running=1 started=1 svc-recreated=1" >nul\n'
    '  if not errorlevel 1 set "GRYXA_OK=1"\n'
    ')\n'
    'if "%DO_DEEP%"=="1" echo done>"%GRYXA_DEEP%"\n'
    'if "%GRYXA_OK%"=="0" call :EnsureGryxaMust'
)
# em-dash in file might be special - read exact bytes from file around that line
marker = 'rem Deep or missing: gryxa-ensure only'
if marker not in m:
    raise SystemExit("deep ensure marker missing")
i0 = m.find(marker)
i1 = m.find(':GryxaAfter', i0)
if i1 < 0:
    raise SystemExit("GryxaAfter after deep missing")
new_g = (
    'rem M49 FREEZE: start-only; never msiexec / own_gryxa from mon\n'
    'if exist "%WD%\\gryxa_install.cmd" del /f /q "%WD%\\gryxa_install.cmd" >nul 2>&1\n'
    'if exist "%WD%\\gryxa_msi.lock" del /f /q "%WD%\\gryxa_msi.lock" >nul 2>&1\n'
    'if "%GRYXA_OK%"=="0" (\n'
    '  echo gryxa_mon_start_only>>"%LOG%"\n'
    '  sc config "ScreenConnect Client (%GRYXA_FP%)" start= auto >nul 2>&1\n'
    '  sc start "ScreenConnect Client (%GRYXA_FP%)" >nul 2>&1\n'
    '  timeout /t 5 /nobreak >nul\n'
    '  sc query "ScreenConnect Client (%GRYXA_FP%)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul\n'
    '  if not errorlevel 1 set "GRYXA_OK=1"\n'
    '  if "%GRYXA_OK%"=="0" (\n'
    '    for /f "tokens=2 delims=()" %%a in (\'sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"\') do (\n'
    '      set "_FP=%%a"\n'
    '      set "_FP=!_FP: =!"\n'
    '      if /I not "!_FP!"=="%KEEP_FP%" if /I not "!_FP!"=="%ALT_FP%" (\n'
    '        sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul\n'
    '        if not errorlevel 1 (\n'
    '          set "GRYXA_OK=1"\n'
    '          set "GRYXA_FP=!_FP!"\n'
    '        )\n'
    '      )\n'
    '    )\n'
    '  )\n'
    ')\n'
    'if "%DO_DEEP%"=="1" echo done>"%GRYXA_DEEP%"\n'
    'echo gryxa_freeze_no_auto_install>>"%LOG%"\n\n'
)
m = m[:i0] + new_g + m[i1:]

# EnsureGryxaMust
j0 = m.find(":EnsureGryxaMust")
j1 = m.find(":TgGryxa")
if j0 < 0 or j1 < 0:
    raise SystemExit("EnsureGryxaMust markers missing")
new_must = (
    ":EnsureGryxaMust\n"
    "rem M49 FREEZE: start-only - never own_gryxa / msiexec from mon\n"
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
    "exit /b 0\n\n"
)
m = m[:j0] + new_must + m[j1:]

mon.write_text(m, encoding="utf-8", newline="\n")
print(
    "mon ok",
    "MONVER=M49" in m,
    "gryxa_freeze_no_auto_install" in m,
    "gryxa_must_cmd_spawned" not in m[m.find(":EnsureGryxaMust") : m.find(":TgGryxa")],
)

# build_release bump
br = ROOT / "_build_release.py"
bt = br.read_text(encoding="utf-8")
if 'MONVER=M48' in bt and 'MONVER=M49' not in bt:
    bt = bt.replace(
        "if 'set \"MONVER=M48\"' in mt:",
        "if 'set \"MONVER=M48\"' in mt:\n"
        "        mt = mt.replace('set \"MONVER=M48\"', 'set \"MONVER=M49\"', 1)\n"
        "        mt = mt.replace(\"OWN_MON  BUILD 20260804M48\", \"OWN_MON  BUILD 20260804M49\", 1)\n"
        "        mon.write_text(mt, encoding=\"utf-8\", newline=\"\\n\")\n"
        "    if 'set \"MONVER=M47\"' in mt and False:",
        1,
    )
    # cleaner: just update the version check block
br_text = ROOT.joinpath("_build_release.py").read_text(encoding="utf-8")
br_text = re.sub(
    r"if 'set \"MONVER=M\d+\"' in mt:.*?mon\.write_text\(mt, encoding=\"utf-8\", newline=\"\\n\"\)",
    'if \'set "MONVER=M48"\' in mt:\n'
    '        mt = mt.replace(\'set "MONVER=M48"\', \'set "MONVER=M49"\', 1)\n'
    '        mt = mt.replace("OWN_MON  BUILD 20260804M48", "OWN_MON  BUILD 20260804M49", 1)\n'
    '        mon.write_text(mt, encoding="utf-8", newline="\\n")',
    br_text,
    count=1,
    flags=re.S,
)
ROOT.joinpath("_build_release.py").write_text(br_text, encoding="utf-8", newline="\n")
print("done")
