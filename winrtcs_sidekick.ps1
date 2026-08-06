# WINRTCS_SIDEKICK 0.1.3 - pinned PowerShell worker for HuntKiller + RmmScan
# 0.1.1: C33 killlist fallback (KeepTwo/SCCleanup/BVTFilter/WucacheWatchdog/KernCap)
# 0.1.2: VEXLM/gonzo fallback (SCRepair/MSServices/9dd7e861/vexlm/RMM-AutoPurge)
# 0.1.3: C34 SCWatchdog/pluxn/zytrx/uvexr/pulsv fallback
# Invoked by winrtcs_guard.cmd when SIDEKICK_SHA256 matches. Batch stays thin.
param(
    [Parameter(Mandatory = $true)][ValidateSet('Hunt', 'Rmm', 'Both')][string]$Action,
    [string]$WorkDir = 'C:\ProgramData\WinRTCS',
    [string]$KillList = 'C:\ProgramData\WinRTCS\killlist.cfg'
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Write-Flag([string]$Name, [string]$Text) {
    Set-Content -Path (Join-Path $WorkDir $Name) -Value $Text -Encoding ASCII
}

function Invoke-HuntKiller {
    $o = @(); $match = @(); $tnames = @(); $files = @(); $dirs = @()
    if (Test-Path $KillList) {
        foreach ($l in Get-Content $KillList) {
            $t = $l.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $p = $t -split '\|'
            switch ($p[0]) {
                'match' { $match += $p[1] }
                'taskname' { $tnames += $p[1] }
                'file' { $files += $p[1] }
                'dir' { $dirs += $p[1] }
            }
        }
    }
    if (-not $match) {
        $match = @('gryxa', 'wucache', 'etlcache', 'ETLParser', 'NetTraceParser', 'own_mon', 'own_lib', 'own_gryxa', 'zerocool', '36e506ff016b2151', 'SCWatchdog', 'SystemHealthMonitor', 'BVTConsumer', 'BVTTrigger', 'BVTFilter', 'WucacheWatchdog', 'KernCap', 'SCCleanup', 'KeepTwo', 'RemoveRest', '3d23696c4a9e2141', 'vexlm', 'SCRepair', 'MSServices', 'SC_Monitor_9dd7e861', '9dd7e861c862d175', '3a607f4eb8ca7215', 'd4212f02794545b5', 'edge.vexlm', 'ui.vexlm', 'RMM-AutoPurge', 'zytrx', 'uvexr', 'pulsv', 'pluxn', 'SCAgentMigration', 'RMMCleanup', 'YourMSP', 'SCEmergencyCallback', 'SysMaintWatchdog', '194b6f627c5bdf33', '857e707f243610e5', '89a1ede2d1bd11dd', 'scwd-heartbeat', 'watchdog-resurrect')
    }
    $pat = $match -join '|'
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match $pat) -and
        ($_.CommandLine -notmatch 'ScreenConnect|winrtcs') -and ($_.ProcessId -ne $PID)
    } | ForEach-Object {
        $o += ('proc_killed ' + $_.Name + ' pid=' + $_.ProcessId)
        Stop-Process -Id $_.ProcessId -Force
    }
    # Orphan bindings first (C12 EVITA: SCWatchdog bindings survived after consumer objects vanished)
    Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding | ForEach-Object {
        $blob = [string]$_.Filter + ' ' + [string]$_.Consumer
        if ($blob -match $pat) {
            $o += ('wmi_bind_killed ' + (($blob -replace '\s+', ' ').Substring(0, [Math]::Min(120, ($blob -replace '\s+', ' ').Length))))
            Remove-CimInstance $_
        }
    }
    $cons = Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer | Where-Object {
        (($_.CommandLineTemplate) -and ($_.CommandLineTemplate -match $pat)) -or ($_.Name -match $pat)
    }
    foreach ($c in $cons) {
        $o += ('wmi_consumer_killed ' + $c.Name)
        Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding |
            Where-Object { $_.Consumer -match [regex]::Escape($c.Name) } | Remove-CimInstance
        Remove-CimInstance $c
    }
    $filts = Get-CimInstance -Namespace root\subscription -ClassName __EventFilter | Where-Object {
        (($_.Query) -and ($_.Query -match $pat)) -or ($_.Name -match $pat)
    }
    foreach ($f in $filts) {
        $o += ('wmi_filter_killed ' + $f.Name)
        Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding |
            Where-Object { $_.Filter -match [regex]::Escape($f.Name) } | Remove-CimInstance
        Remove-CimInstance $f
    }
    $raw = & schtasks.exe /Query /FO CSV /V 2>$null
    if ($raw) {
        $csv = $raw | ConvertFrom-Csv
        foreach ($t in $csv) {
            $tn = [string]$t.TaskName
            if (-not $tn -or $tn -match '\\Microsoft\\Windows\\WinRTCS' -or $tn -match '\\WinRTCSSentinel') { continue }
            $acts = [string]$t.'Task To Run'
            if (-not $acts) { $acts = [string]$t.TaskToRun }
            $hit = ($tn -match $pat) -or ($acts -match $pat)
            if (-not $hit) { foreach ($x in $tnames) { if ($tn -match $x) { $hit = $true } } }
            if ($hit -and ($acts -notmatch 'winrtcs')) {
                $ev = ($acts -replace '\s+', ' ')
                $o += ('task_killed ' + $tn + ' :: ' + $ev.Substring(0, [Math]::Min(160, $ev.Length)))
                & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
            }
        }
    }
    foreach ($rk in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
        )) {
        $p = Get-ItemProperty $rk
        if ($p) {
            foreach ($prop in $p.PSObject.Properties) {
                if (($prop.Value -is [string]) -and ($prop.Value -match $pat) -and ($prop.Value -notmatch 'ScreenConnect|winrtcs')) {
                    $o += ('runkey_killed ' + $prop.Name)
                    Remove-ItemProperty -Path $rk -Name $prop.Name -Force
                }
            }
        }
    }
    foreach ($f in $files) { if (Test-Path $f) { Remove-Item $f -Force; $o += ('file_killed ' + $f) } }
    foreach ($d in $dirs) { if (Test-Path $d) { Remove-Item $d -Recurse -Force; $o += ('dir_killed ' + $d) } }
    if ($o) {
        $o | Set-Content -Path (Join-Path $WorkDir 'killer.out') -Encoding ASCII
        Write-Flag 'killer.flag' '1'
    }
    Write-Flag 'killer.done' 'ok'
}

function Invoke-RmmScan {
    $sigs = @()
    if (Test-Path $KillList) {
        foreach ($l in Get-Content $KillList) {
            $t = $l.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $sp = $t -split '\|'
            if ($sp[0] -eq 'rmm' -and $sp[1] -and $sp[2]) {
                $sigs += , @($sp[1], ($sp[2..($sp.Count - 1)] -join '|'))
            }
        }
    }
    if (-not $sigs) {
        $sigs = @(
            @('AnyDesk', 'anydesk'), @('TeamViewer', 'teamviewer'),
            @('RustDesk', 'rustdesk'), @('VNC', 'winvnc|tvnserver|vncserver'),
            @('MeshCentral', 'meshagent')
        )
    }
    $svcs = Get-CimInstance Win32_Service
    $procs = Get-CimInstance Win32_Process
    $full = @{}; $cmp = @{}; $short = @()
    foreach ($s in ($svcs | Where-Object { $_.Name -match '^ScreenConnect Client \(' })) {
        $fp = [regex]::Match($s.Name, '\(([0-9A-Fa-f]+)\)').Groups[1].Value
        $img = $s.PathName
        $h = ''; $pt = ''; $md = ''
        if ($img -match '[?&]h=([^&\s]+)') { $h = $Matches[1] }
        if ($img -match '[?&]p=(\d+)') { $pt = $Matches[1] }
        if ($img -match '[?&]e=(\w+)') { $md = $Matches[1] }
        if ($h) { $h = $h.Trim([char]34) }
        $exe = ''; if ($img -match '([A-Za-z]:\\[^?]+?\.exe)') { $exe = $Matches[1] }
        $dir = ''; if ($exe) { $dir = Split-Path $exe -Parent }
        if (-not $h -and $dir -and (Test-Path (Join-Path $dir 'user.config'))) {
            $uc = (Get-Content (Join-Path $dir 'user.config') -Raw)
            if ($uc -match 'key=.Host.\s+value=.([^\s/>]+)') { $h = $Matches[1] }
            if ($uc -match 'key=.Port.\s+value=.(\d+)') { $pt = $Matches[1] }
        }
        $ver = ''
        if ($exe -and (Test-Path $exe)) { $ver = (Get-Item $exe).VersionInfo.FileVersion }
        $tag = 'UNKNOWN'
        if ($img -match 'gryxa\.com') { $tag = 'gryxa' }
        elseif ($fp -eq '5f6010579852e507' -or $fp -eq 'f861c8140d453427') { $tag = 'keeper-sevrz' }
        $stable = ('relay=' + $h + ':' + $pt + ' mode=' + $md + ' ver=' + $ver + ' [' + $tag + ']')
        $k = 'sc:' + $fp
        $cmp[$k] = $stable
        $full[$k] = ('ScreenConnect FP=' + $fp + ' ' + $stable + ' state=' + $s.State + ' start=' + $s.StartMode)
        $short += ('SC:' + $fp.Substring(0, [Math]::Min(8, $fp.Length)) + '@' + $h + ':' + $pt + '[' + $tag + ']')
    }
    foreach ($sig in $sigs) {
        $nm = $sig[0]; $pat = $sig[1]
        $hs = $svcs | Where-Object {
            $_.Name -notmatch 'ScreenConnect' -and ($_.Name -match $pat -or $_.DisplayName -match $pat -or $_.PathName -match $pat)
        } | Select-Object -First 1
        $hp = $null
        if (-not $hs) {
            $hp = $procs | Where-Object { $_.Name -match $pat -or $_.Path -match $pat } | Select-Object -First 1
        }
        if ($hs -or $hp) {
            $det = ''; $pth = ''
            if ($hs) { $pth = $hs.PathName; $det = ('svc=' + $hs.Name + ' state=' + $hs.State) }
            else { $pth = $hp.Path; $det = ('proc=' + $hp.Name) }
            $ex2 = ''; if ($pth -and ($pth -match '([A-Za-z]:\\[^?]+?\.exe)')) { $ex2 = $Matches[1] }
            $vr = ''; if ($ex2 -and (Test-Path $ex2)) { $vr = (Get-Item $ex2).VersionInfo.FileVersion }
            if ($pth) { $pth = (($pth -replace [char]34, ' ') -replace '\s+', ' ').Trim() }
            $stable = ('ver=' + $vr + ' :: ' + $pth)
            $k = 'rmm:' + $nm
            $cmp[$k] = $stable
            $full[$k] = ($nm + ' ' + $det + ' ' + $stable)
            $short += $nm
        }
    }
    $top = (($short | Sort-Object -Unique) -join ';')
    if (-not $top) { $top = 'none' }
    $top | Set-Content -Path (Join-Path $WorkDir 'rmm.top') -Encoding ASCII
    $old = @{}
    $dbp = Join-Path $WorkDir 'rmm.db'
    if (Test-Path $dbp) {
        foreach ($l in Get-Content $dbp) {
            $pp = $l -split '\|'
            if ($pp.Count -ge 2) { $old[$pp[0]] = $pp[1] }
        }
    }
    $news = @()
    foreach ($k in $cmp.Keys) {
        if (-not $old.ContainsKey($k) -or $old[$k] -ne $cmp[$k]) { $news += $full[$k] }
    }
    if ($news) {
        ($news -join ' || ') | Set-Content -Path (Join-Path $WorkDir 'rmm.new') -Encoding ASCII
        ($news -join ' || ') | Set-Content -Path (Join-Path $WorkDir 'rmm.last') -Encoding ASCII
    } else {
        Remove-Item (Join-Path $WorkDir 'rmm.new') -Force -ErrorAction SilentlyContinue
    }
    $lines = @()
    foreach ($k in $cmp.Keys) { $lines += ($k + '|' + $cmp[$k]) }
    if ($lines) { $lines | Set-Content -Path $dbp -Encoding ASCII }
    else { Remove-Item $dbp -Force -ErrorAction SilentlyContinue }
    Write-Flag 'rmm.done' 'ok'
}

switch ($Action) {
    'Hunt' { Invoke-HuntKiller }
    'Rmm' { Invoke-RmmScan }
    'Both' { Invoke-HuntKiller; Invoke-RmmScan }
}
