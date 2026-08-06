# Probe ScreenConnect relay connectivity (esp. Gryxa)
$ErrorActionPreference = 'SilentlyContinue'
Write-Output ("host=" + $env:COMPUTERNAME)
Write-Output ("hosts_dns=" + [System.Net.Dns]::GetHostEntry('update.gryxa.com').AddressList[0].IPAddressToString)
Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
    $fp = [regex]::Match($_.Name, '\(([^)]+)\)').Groups[1].Value
    $h = ''
    if ($_.PathName -match '[?&]h=([^&\s\"]+)') { $h = $Matches[1] }
    Write-Output ("SVC fp=$fp state=$($_.State) pid=$($_.ProcessId) h=$h")
    if ($_.ProcessId) {
        Get-NetTCPConnection -OwningProcess $_.ProcessId -State Established -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Output ("  EST $($_.RemoteAddress):$($_.RemotePort)")
        }
    }
}
Write-Output '---curl_ui---'
& curl.exe -I -L --ssl-no-revoke --connect-timeout 10 --max-time 25 'https://ui.gryxa.com/' 2>&1 | Select-Object -First 12
Write-Output '---curl_update---'
& curl.exe -I -L --ssl-no-revoke --connect-timeout 10 --max-time 25 'https://update.gryxa.com/' 2>&1 | Select-Object -First 12
Write-Output 'PROBE_DONE'
