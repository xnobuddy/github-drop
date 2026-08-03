# Live watch: SC services + processes + msiexec every 5s for ~10 min
for ($i = 0; $i -lt 120; $i++) {
    $sv = (Get-CimInstance Win32_Service -Filter "Name like 'ScreenConnect Client%'" |
        ForEach-Object { $_.Name.Split('(')[1].TrimEnd(')') + ':' + $_.State }) -join ' '
    $pr = (Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" |
        ForEach-Object { $_.ProcessId }) -join ','
    $mi = (Get-CimInstance Win32_Process -Filter "Name='msiexec.exe'" |
        ForEach-Object { "$($_.ProcessId):$($_.CommandLine)" }) -join ' | '
    $mon = (Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
        Where-Object { $_.CommandLine -match 'own_mon|etl_mon' } |
        ForEach-Object { $_.ProcessId }) -join ','
    Write-Output ("{0} | svc {1} | SCpid {2} | msiexec {3} | mon {4}" -f
        (Get-Date -Format 'HH:mm:ss'), $sv, $pr, $mi, $mon)
    Start-Sleep -Seconds 5
}
