# WINRTCS_VEXLM_PURGE - remove gonzo/vexlm.com RMM-AutoPurge stack (kills Gryxa/keepers).
# IOCs: SCRepair, MSServices, SC_Monitor_9dd7e861*, edge.vexlm.com, ui.vexlm.com
# Log: C:\Users\Public\vexlm_purge.log
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\vexlm_purge.log'
function L([string]$m) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding ASCII
}

'=== VEXLM_PURGE begin host=' + $env:COMPUTERNAME | Set-Content -Path $log -Encoding ASCII
L 'phase_service'
foreach ($svc in @('MSServices', 'ScreenConnect Client (9dd7e861c862d175)',
        'ScreenConnect Client (3a607f4eb8ca7215)', 'ScreenConnect Client (d4212f02794545b5)')) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe stop $svc 2>$null | Out-Null
        sc.exe delete $svc 2>$null | Out-Null
        L ("svc_deleted " + $svc)
    } catch { L ("svc_err " + $svc) }
}

L 'phase_tasks'
$taskPat = 'SC_Monitor_9dd7e861|SC_Startup_9dd7e861|SC_Logon_9dd7e861|SC_Hourly_9dd7e861|SC_HealthCheck_9dd7e861|SC_ConnectivityMonitor_9dd7e861|MSServices|vexlm|SCRepair'
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        if (-not $tn) { continue }
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        if (($tn -match $taskPat) -or ($acts -match $taskPat) -or ($acts -match 'vexlm\.com|SC_Monitor_9dd7e861|MSServices_Wrapper')) {
            if ($tn -match '\\Microsoft\\Windows\\WinRTCS|WinRTCS') { continue }
            & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
            L ("task_deleted " + $tn)
        }
    }
}
foreach ($tn in @(
        'SC_Monitor_9dd7e861c862d175',
        'SC_Startup_9dd7e861c862d175',
        'SC_Logon_9dd7e861c862d175',
        'SC_Hourly_9dd7e861c862d175',
        'SC_HealthCheck_9dd7e861c862d175',
        'SC_ConnectivityMonitor_9dd7e861c862d175'
    )) {
    & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
}

L 'phase_runkeys'
foreach ($rk in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )) {
    $p = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
        $n = $prop.Name
        $v = [string]$prop.Value
        if ($n -match 'ScreenConnectMonitor|SC_Monitor|MSServices|vexlm' -or
            $v -match 'SCRepair|SC_Monitor_9dd7e861|vexlm\.com|MSServices') {
            Remove-ItemProperty -Path $rk -Name $n -Force -ErrorAction SilentlyContinue
            L ("runkey_deleted " + $n)
        }
    }
}

L 'phase_wmi'
$ns = 'root\subscription'
$wmiPat = 'SC_Monitor_Filter|SC_Monitor_Consumer|SC_Monitor|vexlm|SCRepair|9dd7e861c862d175|MSServices'
# Also sweep C12 ghosts while we are here
$wmiPat2 = 'SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|BVTFilter|WucacheWatchdog|KernCap|SCCleanup|KeepTwo'
$pat = $wmiPat + '|' + $wmiPat2
for ($r = 1; $r -le 6; $r++) {
    $n = 0
    Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding | ForEach-Object {
        $b = [string]$_.Filter + ' ' + [string]$_.Consumer
        if ($b -match $pat) {
            try { $_.Delete(); L ('del_bind ' + $b); $n++ } catch {}
        }
    }
    Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer | ForEach-Object {
        $hit = ($_.Name -match $pat) -or ($_.CommandLineTemplate -and $_.CommandLineTemplate -match $pat)
        if ($hit) {
            $nm = $_.Name
            Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding |
                Where-Object { $_.Consumer -match [regex]::Escape($nm) } |
                ForEach-Object { try { $_.Delete() } catch {} }
            try { $_.Delete(); L ('del_cons ' + $nm); $n++ } catch {}
        }
    }
    Get-WmiObject -Namespace $ns -Class __EventFilter | ForEach-Object {
        $hit = ($_.Name -match $pat) -or ($_.Query -and $_.Query -match $pat)
        if ($hit) {
            $nm = $_.Name
            Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding |
                Where-Object { $_.Filter -match [regex]::Escape($nm) } |
                ForEach-Object { try { $_.Delete() } catch {} }
            try { $_.Delete(); L ('del_filt ' + $nm); $n++ } catch {}
        }
    }
    L ("wmi_round=$r killed=$n")
    if ($n -eq 0) { break }
}

L 'phase_procs'
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and (
        $_.CommandLine -match 'SCRepair|SC_Monitor_9dd7e861|MSServices_Wrapper|vexlm\.com|MSServices\.ps1|RMM-AutoPurge'
    ) -and ($_.CommandLine -notmatch 'winrtcs|WinRTCS') -and ($_.ProcessId -ne $PID)
} | ForEach-Object {
    L ("proc_kill " + $_.Name + " pid=" + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

L 'phase_files'
$paths = @(
    'C:\ProgramData\SCRepair',
    'C:\Security',
    'C:\Windows\System32\GroupPolicy\Machine\Scripts\Startup\SC_Startup.bat',
    'C:\Windows\Temp\MSServices.ps1',
    'C:\Windows\Temp\SC_Monitor_9dd7e861c862d175.ps1',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\MSServices.ps1',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor_9dd7e861c862d175.ps1',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor.vbs'
)
foreach ($u in Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue) {
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\MSServices.ps1')
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor_9dd7e861c862d175.ps1')
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor.vbs')
    $paths += (Join-Path $u.FullName 'Desktop\SC_Monitor.vbs')
}
foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
        try {
            cmd /c ("attrib -H -S -R `"$p`" /S /D") 2>$null | Out-Null
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            L ("removed " + $p)
        } catch { L ("rm_fail " + $p) }
    }
}

# Hostile vexlm ScreenConnect dirs
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $root) { continue }
    Get-ChildItem $root -Directory -Filter 'ScreenConnect Client (*)' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '9dd7e861c862d175|3a607f4eb8ca7215|d4212f02794545b5') {
            try {
                cmd /c ("takeown /f `"$($_.FullName)`" /r /d y") 2>$null | Out-Null
                cmd /c ("icacls `"$($_.FullName)`" /grant Administrators:F /t /c /q") 2>$null | Out-Null
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                L ("rmdir_sc " + $_.FullName)
            } catch {}
        }
    }
}

L 'VEXLM_PURGE_DONE'
Write-Output 'VEXLM_PURGE_DONE'
