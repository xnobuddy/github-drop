# Probe why Gryxa stuck-registered hosts never come back. Read-only.
$o = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\stuck.txt'
"=== STUCK $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $o
'--- SC services ---' | Out-File $o -Append
Get-CimInstance Win32_Service -Filter "Name like 'ScreenConnect Client%'" |
    ForEach-Object { "$($_.Name) | $($_.State) | pid $($_.ProcessId)" } | Out-File $o -Append
'--- Gryxa ARP registration ---' | Out-File $o -Append
foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem $r -EA SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).DisplayName -match '9908198e' } |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath
            "$r | $($_.PSChildName) | $($p.DisplayName) | ver=$($p.DisplayVersion) | uninstall=$($p.UninstallString)"
        } | Out-File $o -Append
}
'--- Gryxa dir present? ---' | Out-File $o -Append
$d = 'C:\Program Files (x86)\ScreenConnect Client (9908198e668e4750)'
"exists=$(Test-Path $d)" | Out-File $o -Append
if (Test-Path $d) {
    Get-ChildItem $d -EA SilentlyContinue | Select-Object -First 10 |
        ForEach-Object { $_.Name } | Out-File $o -Append
}
'--- cached gryxa MSI ---' | Out-File $o -Append
$m = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\pkg_gryxa.msi'
"exists=$(Test-Path $m) size=$((Get-Item $m -EA SilentlyContinue).Length)" | Out-File $o -Append
'--- rate-limit flags ---' | Out-File $o -Append
foreach ($f in @('gryxa_reinstall.flag', 'gryxa_deep.flag')) {
    $p = "C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\$f"
    if (Test-Path $p) { "$f age_min=$([int]((Get-Date) - (Get-Item $p).LastWriteTime).TotalMinutes)" | Out-File $o -Append }
    else { "$f absent" | Out-File $o -Append }
}
'--- gryxa_ensure.log tail ---' | Out-File $o -Append
Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa_ensure.log' -EA SilentlyContinue |
    Select-Object -Last 50 | Out-File $o -Append
'--- msi_gryxa_ensure.log tail ---' | Out-File $o -Append
Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\msi_gryxa_ensure.log' -EA SilentlyContinue |
    Select-Object -Last 40 | Out-File $o -Append
'--- gryxa.cfg ---' | Out-File $o -Append
if (Test-Path 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa.cfg') {
    Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa.cfg' | Out-File $o -Append
}
Get-Content $o
