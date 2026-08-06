# WINRTCS EVITA purge v2b - force-delete orphan WMI bindings
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\evita_purge2.txt'
$log = New-Object System.Collections.Generic.List[string]
function L([string]$s) { [void]$log.Add($s) }

L ("=== PURGE2 BEGIN " + (Get-Date -Format o) + " ===")
$ns = 'root\subscription'
$pat = 'SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|WucacheWatchdog|ETLParser|NetTraceParser|wucache|etlcache'

for ($round = 1; $round -le 6; $round++) {
    L ("--- round $round ---")
    $n = 0
    $binds = @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding)
    foreach ($b in $binds) {
        $blob = [string]$b.Filter + ' ' + [string]$b.Consumer
        if ($blob -match $pat) {
            try {
                $b.Delete()
                L ("DEL_BIND " + $blob)
                $n++
            } catch {
                L ("FAIL_BIND " + $_.Exception.Message)
            }
        }
    }
    foreach ($cls in @('CommandLineEventConsumer', '__EventFilter', '__IntervalTimerInstruction')) {
        $items = @(Get-WmiObject -Namespace $ns -Class $cls)
        foreach ($it in $items) {
            $blob = ''
            try { $blob = [string]$it.Name } catch {}
            try { if (-not $blob) { $blob = [string]$it.TimerId } } catch {}
            try { $blob = $blob + ' ' + [string]$it.Query } catch {}
            try { $blob = $blob + ' ' + [string]$it.CommandLineTemplate } catch {}
            if ($blob -match $pat) {
                try {
                    $it.Delete()
                    L ("DEL_$cls " + $blob)
                    $n++
                } catch {
                    L ("FAIL_$cls " + $_.Exception.Message)
                }
            }
        }
    }
    L ("deleted=$n")
    if ($n -eq 0) { break }
    Start-Sleep -Seconds 1
}

$fp = 'C:\Program Files (x86)\ScreenConnect Client (9dd7e861c862d175)'
if (Test-Path -LiteralPath $fp) {
    cmd /c "takeown /f `"$fp`" /r /d y >nul 2>&1"
    cmd /c "icacls `"$fp`" /grant *S-1-5-32-544:F /t /c >nul 2>&1"
    cmd /c "rmdir /s /q `"$fp`""
    if (Test-Path -LiteralPath $fp) { L 'PHANTOM_STILL_THERE' } else { L 'PHANTOM_GONE' }
} else {
    L 'PHANTOM_ALREADY_GONE'
}

foreach ($p in @(
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
        'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache'
    )) {
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Recurse -Force
        L ("PATH_KILL " + $p)
    } else {
        L ("PATH_GONE " + $p)
    }
}

L '=== FINAL BINDINGS ==='
foreach ($b in @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding)) {
    L ("BIND " + [string]$b.Filter + " -> " + [string]$b.Consumer)
}
L '=== FINAL FILTERS ==='
foreach ($f in @(Get-WmiObject -Namespace $ns -Class __EventFilter)) {
    L ("FILT " + $f.Name)
}
L '=== FINAL CONSUMERS ==='
foreach ($c in @(Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer)) {
    L ("CONS " + $c.Name)
}

$g = Get-Service -Name 'ScreenConnect Client (36e506ff016b2151)'
if ($g) { L ("GRYXA " + $g.Status) } else { L 'GRYXA MISSING' }

L '=== SC DIRS ==='
Get-ChildItem -LiteralPath ${env:ProgramFiles(x86)} -Directory -Filter 'ScreenConnect Client (*)' | ForEach-Object {
    L ("DIR " + $_.Name)
}

L '=== PURGE2 END ==='
$log | Set-Content -Path $out -Encoding ASCII
Set-Content -Path 'C:\Users\Public\evita_purge2.done' -Value 'PURGE2_DONE' -Encoding ASCII
