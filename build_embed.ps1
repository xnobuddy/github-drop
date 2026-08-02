#Requires -Version 5.1
# BUILD_EMBED - regenerates own.cmd embedded base64 blocks + syncs own.txt
# Run after editing own_mon.cmd / own_secure.cmd / tg_report.ps1 / own_lib.ps1.
[CmdletBinding()]
param([string]$Root = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$ownPath = Join-Path $Root 'own.cmd'
$own = Get-Content -LiteralPath $ownPath -Raw

function Get-EmbedBlock([string]$file) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
    $chunks = [regex]::Matches($b64, '.{1,76}') | ForEach-Object { '::' + $_.Value }
    return ($chunks -join "`r`n")
}

$pairs = @(
    @{ Tag = 'B64_MON'; File = 'own_mon.cmd' },
    @{ Tag = 'B64_SEC'; File = 'own_secure.cmd' },
    @{ Tag = 'B64_TGR'; File = 'tg_report.ps1' },
    @{ Tag = 'B64_LIB'; File = 'own_lib.ps1' }
)

foreach ($p in $pairs) {
    $block = Get-EmbedBlock (Join-Path $Root $p.File)
    $pattern = "(?s)(::$($p.Tag)_BEGIN\r?\n).*?(\r?\n::$($p.Tag)_END)"
    $own = [regex]::Replace($own, $pattern, {
            param($m)
            $m.Groups[1].Value + $block + $m.Groups[2].Value
        })
    Write-Host ("embedded {0} <- {1} ({2} bytes b64)" -f $p.Tag, $p.File, $block.Length)
}

Set-Content -LiteralPath $ownPath -Value $own -NoNewline
Copy-Item -LiteralPath $ownPath -Destination (Join-Path $Root 'own.txt') -Force
Write-Host ("own.cmd = {0:N0} bytes | own.txt synced" -f (Get-Item $ownPath).Length)
