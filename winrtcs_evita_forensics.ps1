# WINRTCS EVITA forensics — dump killers + SC inventory for C12/C10/C16 triage
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\evita_forensics.txt'
$lines = New-Object System.Collections.Generic.List[string]
function L([string]$s) { $script:lines.Add($s) | Out-Null }

L ("=== BEGIN " + (Get-Date -Format o) + " host=" + $env:COMPUTERNAME + " ===")

L '=== WINRTCS FLAGS ==='
$zd = 'C:\ProgramData\WinRTCS'
foreach ($f in @(
        'extkill.cnt', 'fight.cnt', 'streak.cnt', 'guard.cnt', 'guard.ver', 'agent.sigstate',
        'gryxa_boost.cnt', 'maint.flag', 'killer.flag', 'rmm.top', 'rmm.new', 'siege.flag'
    )) {
    $p = Join-Path $zd $f
    if (Test-Path $p) {
        $t = (Get-Content $p -Raw -ErrorAction SilentlyContinue)
        if ($null -eq $t) { $t = '' }
        $t = ($t -replace '\s+', ' ').Trim()
        if ($t.Length -gt 300) { $t = $t.Substring(0, 300) + '...' }
        L ("FLAG " + $f + "=" + $t)
    } else {
        L ("FLAG " + $f + "=MISSING")
    }
}

L '=== SCREENCONNECT SERVICES ==='
Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'ScreenConnect' } | ForEach-Object {
    L ("SVC name=" + $_.Name + " state=" + $_.State + " start=" + $_.StartMode)
    L ("  path=" + $_.PathName)
}

L '=== SCREENCONNECT DIRS ==='
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $root) { continue }
    Get-ChildItem $root -Directory -Filter 'ScreenConnect Client (*)' -ErrorAction SilentlyContinue | ForEach-Object {
        L ("DIR " + $_.FullName)
    }
}

L '=== WMI CONSUMERS ==='
Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue | ForEach-Object {
    $cl = ''
    try { $cl = [string]$_.CommandLineTemplate } catch {}
    L ("WMI_CONSUMER name=" + $_.Name + " type=" + $_.CimClass.CimClassName)
    if ($cl) { L ("  cmd=" + ($cl -replace '\s+', ' ').Substring(0, [Math]::Min(240, ($cl -replace '\s+', ' ').Length))) }
}
L '=== WMI FILTERS ==='
Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction SilentlyContinue | ForEach-Object {
    L ("WMI_FILTER name=" + $_.Name + " query=" + (($_.Query -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($_.Query -replace '\s+', ' ').Length))))
}
L '=== WMI BINDINGS ==='
Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue | ForEach-Object {
    L ("WMI_BIND filter=" + $_.Filter + " consumer=" + $_.Consumer)
}

L '=== RUN KEYS ==='
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
        if ($prop.Value -is [string]) {
            L ("RUN " + $rk + " |" + $prop.Name + "=" + $prop.Value)
        }
    }
}

L '=== SUSPECT TASKS (content match) ==='
$pat = 'gryxa|wucache|etlcache|ETLParser|NetTraceParser|own_mon|own_lib|own_gryxa|zerocool|36e506ff|SystemHealth|Diagnosis\\\\ETL|NetTrace'
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        if (($tn -match $pat) -or ($acts -match $pat)) {
            if ($tn -match 'WinRTCS') { continue }
            L ("TASK " + $tn)
            L ("  act=" + (($acts -replace '\s+', ' ').Substring(0, [Math]::Min(220, ($acts -replace '\s+', ' ').Length))))
        }
    }
}

L '=== GHOST FILES ==='
foreach ($f in @(
        'C:\ProgramData\Microsoft\Diagnosis\ETLParser.ps1',
        'C:\ProgramData\Microsoft\NetTrace\NetTraceParser.ps1',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\wucache.vbs',
        'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache',
        'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
        'C:\ProgramData\Microsoft\NetTrace'
    )) {
    if (Test-Path $f) { L ("EXISTS " + $f) } else { L ("GONE " + $f) }
}

L '=== GUARD.LOG TAIL ==='
$gl = Join-Path $zd 'guard.log'
if (Test-Path $gl) {
    Get-Content $gl -Tail 80 | ForEach-Object { L $_ }
} else { L 'guard.log MISSING' }

L '=== MSI LOG TAIL ==='
$ml = Join-Path $zd 'msi_gryxa_install.log'
if (Test-Path $ml) {
    Get-Content $ml -Tail 40 | ForEach-Object { L $_ }
} else { L 'msi log MISSING' }

L '=== AGENT.LOG TAIL ==='
$al = Join-Path $zd 'agent.log'
if (Test-Path $al) {
    Get-Content $al -Tail 40 | ForEach-Object { L $_ }
} else { L 'agent.log MISSING' }

L '=== PROCESSES matching ghost/SC ==='
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and (
        $_.CommandLine -match 'ETLParser|NetTraceParser|wucache|etlcache|ScreenConnect|36e506ff'
    )
} | Select-Object -First 40 | ForEach-Object {
    L ("PROC pid=" + $_.ProcessId + " name=" + $_.Name + " cmd=" + (($_.CommandLine -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($_.CommandLine -replace '\s+', ' ').Length))))
}

L '=== END ==='
$lines | Set-Content -Path $out -Encoding ASCII
'FORENSICS_WRITTEN' | Set-Content -Path 'C:\Users\Public\evita_forensics.done' -Encoding ASCII
