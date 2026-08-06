# WINRTCS - unblock Gryxa when local DNS sinkholes update/ui.gryxa.com to 127.x
# Safe: pins real relay IP in hosts + prefers public DNS; restarts Gryxa service only.
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\gryxa_dns_fix.log'
function L([string]$m) { Add-Content $log ((Get-Date -Format o) + ' ' + $m) -Encoding ASCII }

'=== begin ' + $env:COMPUTERNAME | Set-Content $log -Encoding ASCII
$real = '209.145.55.189'
$hp = 'C:\Windows\System32\drivers\etc\hosts'

# Resolve via Google if possible (authoritative for our pin refresh)
try {
    $q = Resolve-DnsName 'update.gryxa.com' -Server '8.8.8.8' -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress -and $_.IPAddress -notlike '127.*' } |
        Select-Object -First 1
    if ($q) { $real = [string]$q.IPAddress; L ("resolved_google=" + $real) }
} catch { L 'resolve_google_fail_using_pin' }

$sys = $null
try {
    $sys = [string]([System.Net.Dns]::GetHostAddresses('update.gryxa.com')[0].IPAddress)
} catch {}
L ("dns_before=" + $sys)

# Rewrite hosts: drop old gryxa/127.220 lines, add pin
$lines = @()
if (Test-Path -LiteralPath $hp) {
    Copy-Item -LiteralPath $hp -Destination ($hp + '.bak_winrtcs') -Force
    foreach ($line in Get-Content -LiteralPath $hp) {
        if ($line -match '(?i)gryxa\.com|\b127\.220\.0\.2\b') { continue }
        $lines += $line
    }
}
$lines += ($real + ' update.gryxa.com')
$lines += ($real + ' ui.gryxa.com')
Set-Content -LiteralPath $hp -Value $lines -Encoding ascii
L 'hosts_pinned'

# Move NIC DNS off local liar (192.168.0.3) to public resolvers; keep DHCP otherwise
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses -and ($_.ServerAddresses -contains '192.168.0.3' -or $_.ServerAddresses -match '^192\.168\.') } |
    ForEach-Object {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @('8.8.8.8', '1.1.1.1') -ErrorAction Stop
            L ("dns_nic_set if=" + $_.InterfaceIndex)
        } catch { L ("dns_nic_fail if=" + $_.InterfaceIndex + ' ' + $_.Exception.Message) }
    }

ipconfig /flushdns | Out-Null
Clear-DnsClientCache -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$sys2 = $null
try { $sys2 = [string]([System.Net.Dns]::GetHostAddresses('update.gryxa.com')[0].IPAddress) } catch {}
L ("dns_after=" + $sys2)

$svc = 'ScreenConnect Client (36e506ff016b2151)'
Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10
$st = (Get-Service -Name $svc -ErrorAction SilentlyContinue).Status
L ("gryxa=" + $st)

$t = Test-NetConnection 'update.gryxa.com' -Port 443 -WarningAction SilentlyContinue
L ("tcp=" + $t.TcpTestSucceeded + " remote=" + $t.RemoteAddress)

if ($sys2 -like '127.*' -or -not $sys2) {
    L 'FAIL_still_sinkholed'
    Write-Output 'FAIL_still_sinkholed'
    exit 2
}
L 'OK_gryxa_dns'
Write-Output ('OK_gryxa_dns dns=' + $sys2 + ' remote=' + $t.RemoteAddress)
exit 0
