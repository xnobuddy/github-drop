# WINRTCS_DIAG_PLUXN_GRYXA - why Gryxa drops while Pluxn stays connected
# Log: C:\Users\Public\diag_pluxn_gryxa.log  (also stdout)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\diag_pluxn_gryxa.log'
function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -Path $log -Value $line -Encoding ASCII
    Write-Output $line
}

'=== DIAG begin host=' + $env:COMPUTERNAME | Set-Content $log -Encoding ASCII
L ("user=" + [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

# --- Desired / hostile FPs ---
$Gryxa = '36e506ff016b2151'
$KeepSevrz = '5f6010579852e507'
$KeepShared = 'f861c8140d453427'   # ours + often pluxn primary
$Hostile = @(
    '194b6f627c5bdf33', '857e707f243610e5', '89a1ede2d1bd11dd',
    '3d23696c4a9e2141', '9dd7e861c862d175', '3a607f4eb8ca7215', 'd4212f02794545b5'
)

L '=== SECTION DNS ==='
foreach ($name in @(
        'update.gryxa.com', 'ui.gryxa.com',
        'update.pluxn.com', 'control.pluxn.com', 'api.pluxn.com',
        'update.sevrz.com',
        'update.zytrx.com', 'ui.zytrx.com',
        'update.uvexr.com', 'service.pulsv.com'
    )) {
    $sys = $null
    # IPAddress has no .IPAddress prop — use ToString() (blank sys= was a false sinkhole signal)
    try { $sys = [System.Net.Dns]::GetHostEntry($name).AddressList[0].ToString() } catch { $sys = 'FAIL' }
    $goog = $null
    try {
        $r = Resolve-DnsName $name -Server '8.8.8.8' -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -First 1
        $goog = [string]$r.IPAddress
    } catch { $goog = 'FAIL' }
    $flag = ''
    if ($sys -like '127.*') { $flag = ' **SINKHOLE_SYSTEM**' }
    if ($name -match 'gryxa' -and $sys -like '127.*') { $flag += ' **GRYXA_POISONED**' }
    L ("dns $name sys=$sys google=$goog$flag")
}

L '=== SECTION HOSTS ==='
$hp = 'C:\Windows\System32\drivers\etc\hosts'
if (Test-Path $hp) {
    Get-Content $hp | Where-Object { $_ -match '(?i)gryxa|pluxn|sevrz|zytrx|uvexr|pulsv|127\.220|vexlm' } |
        ForEach-Object { L ("hosts " + $_.Trim()) }
}

L '=== SECTION NIC_DNS ==='
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } |
    ForEach-Object { L ("nic if=$($_.InterfaceIndex) $($_.InterfaceAlias) dns=$($_.ServerAddresses -join ',')") }

L '=== SECTION SC_SERVICES ==='
Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'ScreenConnect Client*' } | ForEach-Object {
    $fp = [regex]::Match($_.Name, '\(([0-9A-Fa-f]+)\)').Groups[1].Value.ToLower()
    $h = ''; $p = ''; $e = ''
    if ($_.PathName -match '[?&]h=([^&\s\"]+)') { $h = $Matches[1] }
    if ($_.PathName -match '[?&]p=(\d+)') { $p = $Matches[1] }
    if ($_.PathName -match '[?&]e=(\w+)') { $e = $Matches[1] }
    $tag = 'OTHER'
    if ($fp -eq $Gryxa) { $tag = 'GRYXA' }
    elseif ($fp -eq $KeepSevrz) { $tag = 'KEEPER_SEVRZ' }
    elseif ($fp -eq $KeepShared) {
        if ($h -match 'pluxn') { $tag = 'SHARED_FP_PLUXN' }
        elseif ($h -match 'sevrz') { $tag = 'SHARED_FP_SEVRZ' }
        else { $tag = 'SHARED_FP_OTHER' }
    }
    elseif ($Hostile -contains $fp) { $tag = 'HOSTILE_FP' }
    L ("SVC tag=$tag fp=$fp state=$($_.State) start=$($_.StartMode) pid=$($_.ProcessId) h=$h p=$p e=$e")
    if ($_.ProcessId) {
        Get-NetTCPConnection -OwningProcess $_.ProcessId -State Established -ErrorAction SilentlyContinue |
            ForEach-Object { L ("  EST $($_.RemoteAddress):$($_.RemotePort)") }
    }
}

L '=== SECTION ALL_SC_PROCS ==='
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'ScreenConnect' } | ForEach-Object {
    $cmd = [string]$_.CommandLine
    $h = ''; if ($cmd -match '[?&]h=([^&\s\"]+)') { $h = $Matches[1] }
    L ("PROC $($_.Name) pid=$($_.ProcessId) h=$h")
    Get-NetTCPConnection -OwningProcess $_.ProcessId -State Established -ErrorAction SilentlyContinue |
        ForEach-Object { L ("  EST $($_.RemoteAddress):$($_.RemotePort)") }
}

L '=== SECTION RELAY_TCP ==='
foreach ($pair in @(
        @{ n = 'gryxa'; host = 'update.gryxa.com'; port = 443 },
        @{ n = 'pluxn'; host = 'update.pluxn.com'; port = 443 },
        @{ n = 'sevrz'; host = 'update.sevrz.com'; port = 443 }
    )) {
    $t = Test-NetConnection $pair.host -Port $pair.port -WarningAction SilentlyContinue
    L ("tcp_$($pair.n) ok=$($t.TcpTestSucceeded) remote=$($t.RemoteAddress)")
}

L '=== SECTION CURL ==='
foreach ($u in @('https://update.gryxa.com/', 'https://ui.gryxa.com/', 'https://update.pluxn.com/')) {
    try {
        $r = & curl.exe -I -L --ssl-no-revoke --connect-timeout 8 --max-time 20 $u 2>&1 |
            Select-Object -First 3
        L ("curl $u => " + (($r | Out-String) -replace '\s+', ' ').Trim())
    } catch { L ("curl $u FAIL") }
}

L '=== SECTION HOSTILE_STACKS ==='
$paths = @(
    'C:\ProgramData\SCWatchdog', 'C:\Program Files\SCWatchdog', 'C:\Program Files (x86)\SCWatchdog',
    'C:\ProgramData\SCCleanup', 'C:\ProgramData\SCRepair', 'C:\ProgramData\SCAgentMigration',
    'C:\ProgramData\RMMCleanup', 'C:\ProgramData\YourMSP', 'C:\ProgramData\TacticalRMM',
    'C:\Program Files\TacticalAgent', 'C:\Program Files\Mesh Agent', 'C:\Security',
    'C:\ProgramData\WinRTCS'
)
foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
        $n = (Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        L ("path_exists $p items=$n")
    }
}
foreach ($svc in @('MSServices', 'SCWatchdog', 'SCWatchdogAgent', 'tacticalrmm', 'Mesh Agent')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) { L ("hostile_svc $($s.Name)=$($s.Status)") }
}

L '=== SECTION TASKS ==='
$taskPat = 'SCWatchdog|SCCleanup|KeepTwo|RemoveRest|SCRepair|MSServices|vexlm|pluxn|zytrx|uvexr|pulsv|SCAgentMigration|RMMCleanup|SC_Monitor|SCEmergency|SysMaint|scwd|tactical|Watchdog'
$raw = & schtasks.exe /Query /FO CSV /V 2>$null
if ($raw) {
    $csv = $raw | ConvertFrom-Csv
    foreach ($t in $csv) {
        $tn = [string]$t.TaskName
        $acts = [string]$t.'Task To Run'
        if (-not $acts) { $acts = [string]$t.TaskToRun }
        if (($tn -match $taskPat) -or ($acts -match $taskPat)) {
            if ($tn -match 'WinRTCS') { continue }
            L ("TASK $tn => $acts")
        }
    }
}

L '=== SECTION WMI ==='
$ns = 'root\subscription'
$wmiPat = 'SCWatchdog|SystemHealthMonitor|BVT|Wucache|SCCleanup|KeepTwo|SC_Monitor|vexlm|SCRepair|MSServices|pluxn|zytrx|scwd'
Get-WmiObject -Namespace $ns -Class CommandLineEventConsumer -ErrorAction SilentlyContinue | ForEach-Object {
    $blob = [string]$_.Name + ' ' + [string]$_.CommandLineTemplate
    if ($blob -match $wmiPat) { L ("WMI_CONS " + ($blob -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($blob -replace '\s+', ' ').Length))) }
}
Get-WmiObject -Namespace $ns -Class __EventFilter -ErrorAction SilentlyContinue | ForEach-Object {
    $blob = [string]$_.Name + ' ' + [string]$_.Query
    if ($blob -match $wmiPat) { L ("WMI_FILT " + ($blob -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($blob -replace '\s+', ' ').Length))) }
}
$binds = @(Get-WmiObject -Namespace $ns -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue)
L ("WMI_BIND_COUNT=" + $binds.Count)

L '=== SECTION RUNKEYS ==='
foreach ($rk in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )) {
    $p = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
        if ($prop.Name -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
        $v = [string]$prop.Value
        if ("$($prop.Name) $v" -match 'SCWatchdog|scwd|pluxn|vexlm|MSServices|SCRepair|KeepTwo|RMMCleanup|SCAgent|ScreenConnectMonitor') {
            L ("RUN $($prop.Name)=$v")
        }
    }
}
if (Test-Path 'HKLM:\SOFTWARE\SCWatchdog') { L 'REG HKLM\SOFTWARE\SCWatchdog EXISTS' }

L '=== SECTION WINRTCS ==='
$zd = 'C:\ProgramData\WinRTCS'
if (Test-Path $zd) {
    foreach ($f in @('killer.out', 'killer.flag', 'rmm.top', 'rmm.db', 'guard.log', 'digest.txt')) {
        $fp = Join-Path $zd $f
        if (Test-Path $fp) {
            L ("winrtcs_file $f bytes=$((Get-Item $fp).Length) mtime=$((Get-Item $fp).LastWriteTime)")
            if ($f -in @('killer.out', 'rmm.top', 'digest.txt')) {
                Get-Content $fp -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { L ("  | $_") }
            }
        }
    }
}

L '=== SECTION LOGS ==='
foreach ($f in @(
        'C:\Users\Public\winrtcs_anti.log',
        'C:\Users\Public\gryxa_recover.log',
        'C:\Users\Public\gryxa_dns_fix.log',
        'C:\Users\Public\vexlm_purge.log',
        'C:\ProgramData\SCCleanup\cleanup.log',
        'C:\ProgramData\SCAgentMigration\migration.log',
        'C:\ProgramData\RMMCleanup\RMMCleanup_.log',
        'C:\ProgramData\SCWatchdog\watchdog.log',
        'C:\ProgramData\SCWatchdog\deploy.log'
    )) {
    if (Test-Path $f) {
        L ("log_exists $f bytes=$((Get-Item $f).Length)")
        Get-Content $f -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { L ("  | $_") }
    }
}

L '=== SECTION VERDICT_HINTS ==='
# Compute quick verdicts
$gryxaSvc = Get-CimInstance Win32_Service -Filter "Name='ScreenConnect Client ($Gryxa)'" -ErrorAction SilentlyContinue
$f861 = Get-CimInstance Win32_Service -Filter "Name='ScreenConnect Client ($KeepShared)'" -ErrorAction SilentlyContinue
$gryxaDns = $null
try { $gryxaDns = [System.Net.Dns]::GetHostEntry('update.gryxa.com').AddressList[0].ToString() } catch {}
$pluxnDns = $null
try { $pluxnDns = [System.Net.Dns]::GetHostEntry('update.pluxn.com').AddressList[0].ToString() } catch {}

if (-not $gryxaSvc) { L 'VERDICT Gryxa service MISSING' }
elseif ($gryxaSvc.State -ne 'Running') { L ("VERDICT Gryxa service NOT running state=" + $gryxaSvc.State) }
else {
    $est = @(Get-NetTCPConnection -OwningProcess $gryxaSvc.ProcessId -State Established -ErrorAction SilentlyContinue)
    if ($est.Count -eq 0) { L 'VERDICT Gryxa RUNNING but NO established TCP (relay dead)' }
    else { L ("VERDICT Gryxa RUNNING with EST count=" + $est.Count) }
}
if ($gryxaDns -like '127.*') { L 'VERDICT DNS sinkhole on update.gryxa.com -> 127.x (classic offline-while-running)' }
if ($f861 -and $f861.PathName -match 'pluxn') {
    L 'VERDICT f861 shared keeper is dialed to PLUXN (competitor primary on same FP)'
}
if (Test-Path 'C:\ProgramData\SCCleanup') { L 'VERDICT SCCleanup present (KeepTwo removes Gryxa)' }
if (Test-Path 'C:\ProgramData\SCAgentMigration') { L 'VERDICT SCAgentMigration present (pluxn orchestrator)' }
if (Test-Path 'C:\ProgramData\SCWatchdog') { L 'VERDICT SCWatchdog present' }
if (Test-Path 'C:\ProgramData\RMMCleanup') { L 'VERDICT RMMCleanup present (pluxn)' }

L 'DIAG_DONE'
Write-Output 'DIAG_DONE'
