from __future__ import annotations

from pathlib import Path

p = Path(r"C:\Users\nobuddy\Desktop\Project\own_lib.ps1")
s = p.read_text(encoding="utf-8")
start = s.index("    # 5. disallowed RMM tools")
end = s.index("    foreach ($tool in $rmm) {")

new = r'''    # 5. disallowed RMM / remote-access tools (market coverage 2026).
    # KEEP forever: Datto/CentraStage + ScreenConnect keep FPs (handled above).
    # NEVER put Datto/CentraStage/CagService in this list.
    function Is-DattoKeeper([string]$s) {
        if (-not $s) { return $false }
        return [bool]($s -match '(?i)Datto|CentraStage|CagService|AutotaskEndpoint')
    }
    $rmm = @(
        @{ Tag='AnyDesk';      Svc=@('AnyDesk'); Proc=@('AnyDesk'); Dirs=@("$env:ProgramFiles\AnyDesk","${env:ProgramFiles(x86)}\AnyDesk","$env:ProgramData\AnyDesk"); Prod=@('AnyDesk*') }
        @{ Tag='TeamViewer';   Svc=@('TeamViewer*'); Proc=@('TeamViewer*','tv_w32*','tv_x64*'); Dirs=@("$env:ProgramFiles\TeamViewer","${env:ProgramFiles(x86)}\TeamViewer"); Prod=@('TeamViewer*') }
        @{ Tag='Splashtop';    Svc=@('Splashtop*','SRService','SSUService'); Proc=@('Splashtop*','strwinclt*','SRManager*'); Dirs=@("$env:ProgramFiles\Splashtop","${env:ProgramFiles(x86)}\Splashtop"); Prod=@('Splashtop*') }
        @{ Tag='LogMeIn';      Svc=@('LogMeIn','LMIGuardianSvc','LMIignition'); Proc=@('LogMeIn*','LMIGuardian*','RaServer*'); Dirs=@("$env:ProgramFiles\LogMeIn","${env:ProgramFiles(x86)}\LogMeIn"); Prod=@('LogMeIn*') }
        @{ Tag='GoTo';         Svc=@('GoToMyPC*','GoToAssist*','GoToResolve*'); Proc=@('GoToMyPC*','GoToAssist*','g2m*','GoToResolve*'); Dirs=@("$env:ProgramFiles\GoToMyPC","${env:ProgramFiles(x86)}\GoToMyPC"); Prod=@('GoToMyPC*','GoToAssist*','GoTo Resolve*','GoToMeeting*','GoTo Connect*') }
        @{ Tag='RustDesk';     Svc=@('RustDesk','rustdesk*'); Proc=@('rustdesk*'); Dirs=@("$env:ProgramFiles\RustDesk","${env:ProgramFiles(x86)}\RustDesk"); Prod=@('RustDesk*') }
        @{ Tag='Supremo';      Svc=@('Supremo*'); Proc=@('Supremo*'); Dirs=@("$env:ProgramFiles\Supremo","${env:ProgramFiles(x86)}\Supremo"); Prod=@('Supremo*') }
        @{ Tag='DWService';    Svc=@('DWAgent','dwagent*'); Proc=@('dwagent*'); Dirs=@("$env:ProgramFiles\DWAgent","${env:ProgramFiles(x86)}\DWAgent","$env:ProgramData\DWAgent"); Prod=@('DWAgent*','DWService*') }
        @{ Tag='ZohoAssist';   Svc=@('ZohoAssist*','ZohoMeeting*'); Proc=@('ZohoAssist*','ZohoURSB*'); Dirs=@("$env:ProgramFiles\ZohoMeeting","${env:ProgramFiles(x86)}\ZohoMeeting"); Prod=@('Zoho Assist*','ZohoMeeting*') }
        @{ Tag='RemotePC';     Svc=@('RemotePC*'); Proc=@('RemotePC*','RPCSuite*'); Dirs=@("$env:ProgramFiles\RemotePC","${env:ProgramFiles(x86)}\RemotePC"); Prod=@('RemotePC*') }
        @{ Tag='Bomgar';       Svc=@('bomgar*','BeyondTrust*'); Proc=@('bomgar*'); Dirs=@("$env:ProgramFiles\Bomgar","${env:ProgramFiles(x86)}\Bomgar","$env:ProgramFiles\BeyondTrust","${env:ProgramFiles(x86)}\BeyondTrust"); Prod=@('Bomgar*','BeyondTrust*') }
        @{ Tag='Parsec';       Svc=@('Parsec*'); Proc=@('parsecd*','pservice*'); Dirs=@("$env:ProgramFiles\Parsec","${env:ProgramFiles(x86)}\Parsec","$env:ProgramData\Parsec"); Prod=@('Parsec*') }
        @{ Tag='ChromeRD';     Svc=@('chromoting*'); Proc=@('remoting_host*'); Dirs=@("$env:ProgramFiles\Google\Chrome Remote Desktop","${env:ProgramFiles(x86)}\Google\Chrome Remote Desktop"); Prod=@('Chrome Remote Desktop*') }
        @{ Tag='UltraVNC';     Svc=@('uvnc*','winvnc*'); Proc=@('winvnc*','uvnc*'); Dirs=@("$env:ProgramFiles\UltraVNC","${env:ProgramFiles(x86)}\UltraVNC"); Prod=@('UltraVNC*','WinVNC*') }
        @{ Tag='TightVNC';     Svc=@('tvnserver*'); Proc=@('tvnserver*','tvnviewer*'); Dirs=@("$env:ProgramFiles\TightVNC","${env:ProgramFiles(x86)}\TightVNC"); Prod=@('TightVNC*') }
        @{ Tag='RealVNC';      Svc=@('vncserver*'); Proc=@('vncserver*','vncviewer*'); Dirs=@("$env:ProgramFiles\RealVNC","${env:ProgramFiles(x86)}\RealVNC"); Prod=@('VNC Server*','RealVNC*') }
        @{ Tag='DameWare';     Svc=@('DameWare*'); Proc=@('DWRCS*','DWRCC*','DameWare*'); Dirs=@("$env:ProgramFiles\SolarWinds","${env:ProgramFiles(x86)}\SolarWinds","$env:ProgramFiles\DameWare Remote Support","${env:ProgramFiles(x86)}\DameWare Remote Support"); Prod=@('DameWare*') }
        @{ Tag='NetSupport';   Svc=@('NetSupport*'); Proc=@('client32*','pcictl*'); Dirs=@("$env:ProgramFiles\NetSupport","${env:ProgramFiles(x86)}\NetSupport"); Prod=@('NetSupport*') }
        @{ Tag='SimpleHelp';   Svc=@('SimpleHelp*'); Proc=@('SimpleService*','simpleservice*'); Dirs=@("$env:ProgramFiles\SimpleHelp","${env:ProgramFiles(x86)}\SimpleHelp"); Prod=@('SimpleHelp*') }
        @{ Tag='GetScreen';    Svc=@('GetScreen*'); Proc=@('GetScreen*'); Dirs=@("$env:ProgramFiles\GetScreen","${env:ProgramFiles(x86)}\GetScreen"); Prod=@('GetScreen*') }
        @{ Tag='Iperius';      Svc=@('Iperius*'); Proc=@('IperiusRemote*'); Dirs=@("$env:ProgramFiles\Iperius Remote","${env:ProgramFiles(x86)}\Iperius Remote"); Prod=@('Iperius*') }
        @{ Tag='ISLOnline';   Svc=@('ISLlight*'); Proc=@('ISLlight*','ISLAlwaysOn*'); Dirs=@("$env:ProgramFiles\ISL Online","${env:ProgramFiles(x86)}\ISL Online"); Prod=@('ISL Light*','ISL AlwaysOn*') }
        @{ Tag='Ammyy';        Svc=@('Ammyy*'); Proc=@('Ammyy*'); Dirs=@("$env:ProgramFiles\Ammyy","${env:ProgramFiles(x86)}\Ammyy"); Prod=@('Ammyy*') }
        @{ Tag='UltraViewer';  Svc=@('UltraViewer*'); Proc=@('UltraViewer*'); Dirs=@("$env:ProgramFiles\UltraViewer","${env:ProgramFiles(x86)}\UltraViewer"); Prod=@('UltraViewer*') }
        @{ Tag='AeroAdmin';    Svc=@('AeroAdmin*'); Proc=@('AeroAdmin*'); Dirs=@("$env:ProgramFiles\AeroAdmin","${env:ProgramFiles(x86)}\AeroAdmin"); Prod=@('AeroAdmin*') }
        @{ Tag='LiteManager';  Svc=@('LiteManager*'); Proc=@('ROMServer*','ROMViewer*'); Dirs=@("$env:ProgramFiles\LiteManager","${env:ProgramFiles(x86)}\LiteManager"); Prod=@('LiteManager*') }
        @{ Tag='Radmin';       Svc=@('Radmin*'); Proc=@('rserver3*','Radmin*'); Dirs=@("$env:ProgramFiles\Radmin Server 3","${env:ProgramFiles(x86)}\Radmin Server 3"); Prod=@('Radmin*') }
        @{ Tag='NoMachine';    Svc=@('nxserver*','nxd*'); Proc=@('nxd*','nxserver*','nxrunner*'); Dirs=@("$env:ProgramFiles\NoMachine","${env:ProgramFiles(x86)}\NoMachine"); Prod=@('NoMachine*') }
        @{ Tag='NinjaOne';     Svc=@('NinjaRMMAgent','ninjarmm*','NinjaRMM*'); Proc=@('NinjaRMMAgent*','ninjarmm*'); Dirs=@("$env:ProgramFiles\NinjaRMMAgent","${env:ProgramFiles(x86)}\NinjaRMMAgent","$env:ProgramData\NinjaRMMAgent","$env:ProgramFiles\NinjaOne","${env:ProgramFiles(x86)}\NinjaOne"); Prod=@('NinjaRMM*','NinjaOne*') }
        @{ Tag='Atera';        Svc=@('AteraAgent'); Proc=@('AteraAgent*'); Dirs=@("$env:ProgramFiles\ATERA Networks","${env:ProgramFiles(x86)}\ATERA Networks","$env:ProgramData\ATERA Networks"); Prod=@('Atera*') }
        @{ Tag='ConnectWise';  Svc=@('LTService','LTSvcMon'); Proc=@('LTSvc*','LTTray*'); Dirs=@("$env:windir\LTSvc","$env:ProgramFiles\LabTech Client","${env:ProgramFiles(x86)}\LabTech Client"); Prod=@('ConnectWise Automate*','ConnectWise RMM*','LabTech*') }
        @{ Tag='Kaseya';       Svc=@('AgentMon','Kaseya*','KAADS*'); Proc=@('AgentMon*','Kaseya*'); Dirs=@("$env:ProgramFiles\Kaseya","${env:ProgramFiles(x86)}\Kaseya"); Prod=@('Kaseya VSA*','Kaseya Agent*') }
        @{ Tag='Nable';        Svc=@('Advanced Monitoring Agent*','N-able*','NCentral*'); Proc=@('FileSystemAgent*','NCentral*'); Dirs=@("$env:ProgramFiles\Advanced Monitoring Agent","${env:ProgramFiles(x86)}\Advanced Monitoring Agent","$env:ProgramFiles\N-able Technologies","${env:ProgramFiles(x86)}\N-able Technologies","$env:ProgramFiles\MSPA Files","${env:ProgramFiles(x86)}\MSPA Files"); Prod=@('Advanced Monitoring Agent*','N-able*','N-central*','N-sight*','Take Control*','SolarWinds MSP*') }
        @{ Tag='Syncro';       Svc=@('Syncro*','Kabuto*'); Proc=@('Syncro*','Kabuto*'); Dirs=@("$env:ProgramFiles\RepairTech","${env:ProgramFiles(x86)}\RepairTech","$env:ProgramFiles\Syncro","${env:ProgramFiles(x86)}\Syncro","$env:ProgramData\Syncro"); Prod=@('Syncro*','Kabuto*','RepairTech*') }
        @{ Tag='Pulseway';     Svc=@('Pulseway*','PC Monitor*'); Proc=@('PCMonitorMgr*','PCMonitorManager*','Pulseway*'); Dirs=@("$env:ProgramFiles\Pulseway","${env:ProgramFiles(x86)}\Pulseway","$env:ProgramFiles\PC Monitor","${env:ProgramFiles(x86)}\PC Monitor"); Prod=@('Pulseway*','PC Monitor*') }
        @{ Tag='SuperOps';     Svc=@('SuperOps*'); Proc=@('SuperOps*'); Dirs=@("$env:ProgramFiles\SuperOps","${env:ProgramFiles(x86)}\SuperOps","$env:ProgramData\SuperOps"); Prod=@('SuperOps*') }
        @{ Tag='Level';        Svc=@('Level*'); Proc=@('level*'); Dirs=@("$env:ProgramFiles\Level","${env:ProgramFiles(x86)}\Level","$env:ProgramData\Level"); Prod=@('Level*') }
        @{ Tag='Action1';      Svc=@('Action1*'); Proc=@('Action1*','action1_agent*'); Dirs=@("$env:ProgramFiles\Action1","${env:ProgramFiles(x86)}\Action1","$env:ProgramData\Action1"); Prod=@('Action1*') }
        @{ Tag='ManageEngine'; Svc=@('ManageEngine*','UEMS*','DCAgent*'); Proc=@('ManageEngine*','dcagent*','UEMS*'); Dirs=@("$env:ProgramFiles\ManageEngine","${env:ProgramFiles(x86)}\ManageEngine"); Prod=@('ManageEngine*','UEMS*','Desktop Central*','Endpoint Central*','RMM Central*') }
        @{ Tag='TacticalRMM';  Svc=@('tacticalrmm*','Mesh Agent','MeshAgent'); Proc=@('tacticalrmm*','meshagent*','MeshAgent*'); Dirs=@("$env:ProgramFiles\TacticalAgent","${env:ProgramFiles(x86)}\TacticalAgent","$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Tactical*','Mesh Agent*','MeshCentral*') }
        @{ Tag='MeshCentral';  Svc=@('Mesh Agent','MeshAgent','MeshCentral*'); Proc=@('MeshAgent*','MeshCentral*'); Dirs=@("$env:ProgramFiles\Mesh Agent","${env:ProgramFiles(x86)}\Mesh Agent"); Prod=@('Mesh*Agent*','MeshCentral*') }
        @{ Tag='Continuum';    Svc=@('SAAZ*','Continuum*'); Proc=@('SAAZ*','Continuum*'); Dirs=@("$env:ProgramFiles\SAAZOD","${env:ProgramFiles(x86)}\SAAZOD","$env:ProgramFiles\Continuum","${env:ProgramFiles(x86)}\Continuum"); Prod=@('Continuum*','SAAZ*') }
        @{ Tag='Naverisk';     Svc=@('Naverisk*'); Proc=@('Naverisk*'); Dirs=@("$env:ProgramFiles\Naverisk","${env:ProgramFiles(x86)}\Naverisk"); Prod=@('Naverisk*') }
        @{ Tag='ImmyBot';      Svc=@('ImmyBot*','Immy*'); Proc=@('ImmyAgent*','ImmyBot*'); Dirs=@("$env:ProgramFiles\ImmyBot","${env:ProgramFiles(x86)}\ImmyBot","$env:ProgramData\ImmyBot"); Prod=@('ImmyBot*') }
        @{ Tag='Automox';      Svc=@('amagent*','Automox*'); Proc=@('amagent*'); Dirs=@("$env:ProgramFiles\Automox","${env:ProgramFiles(x86)}\Automox","$env:ProgramData\amagent"); Prod=@('Automox*') }
        @{ Tag='AcronisCyber'; Svc=@('Acronis*'); Proc=@('acrocmd*'); Dirs=@("$env:ProgramFiles\Acronis","${env:ProgramFiles(x86)}\Acronis"); Prod=@('Acronis Cyber*','Acronis Agent*','Cyber Protect Agent*') }
        @{ Tag='Domotz';       Svc=@('Domotz*'); Proc=@('Domotz*'); Dirs=@("$env:ProgramFiles\Domotz","${env:ProgramFiles(x86)}\Domotz"); Prod=@('Domotz*') }
        @{ Tag='Auvik';        Svc=@('Auvik*'); Proc=@('Auvik*'); Dirs=@("$env:ProgramFiles\Auvik","${env:ProgramFiles(x86)}\Auvik"); Prod=@('Auvik*') }
        @{ Tag='BarracudaRMM'; Svc=@('Barracuda*'); Proc=@('MWService*'); Dirs=@("$env:ProgramFiles\Barracuda","${env:ProgramFiles(x86)}\Barracuda","$env:ProgramFiles\Level Platforms","${env:ProgramFiles(x86)}\Level Platforms"); Prod=@('Barracuda RMM*','Managed Workplace*') }
        @{ Tag='Goverlan';     Svc=@('Goverlan*'); Proc=@('goverlan*','govagent*'); Dirs=@("$env:ProgramFiles\Goverlan","${env:ProgramFiles(x86)}\Goverlan"); Prod=@('Goverlan*') }
        @{ Tag='PDQ';          Svc=@('PDQ*'); Proc=@('PDQRunner*','PDQInventory*','PDQDeploy*'); Dirs=@("$env:ProgramFiles\Admin Arsenal","${env:ProgramFiles(x86)}\Admin Arsenal","$env:ProgramFiles\PDQ","${env:ProgramFiles(x86)}\PDQ"); Prod=@('PDQ Deploy*','PDQ Inventory*','PDQ Connect*') }
    )

'''

s2 = s[:start] + new + s[end:]

# harden loops with Datto skip
s2 = s2.replace(
    """                    if ($dn -and $dn -like $pat) {
                        if (Uninstall-ProductKey $_) { $n.rmm++; $hit = $true }
                    }""",
    """                    if ($dn -and $dn -like $pat) {
                        if (Is-DattoKeeper $dn) { Log "rmm_skip_datto_keep [$dn]"; return }
                        if (Uninstall-ProductKey $_) { $n.rmm++; $hit = $true }
                    }""",
    1,
)
s2 = s2.replace(
    """            Get-Service -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                & sc.exe stop "$($_.Name)" 2>&1 | Out-Null
                Start-Sleep -Milliseconds 500
                & sc.exe delete "$($_.Name)" 2>&1 | Out-Null
                $n.rmm++; $hit = $true; Log "rmm_svc_deleted $($_.Name) [$($tool.Tag)]"
            }""",
    """            Get-Service -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
                if (Is-DattoKeeper $_.Name -or Is-DattoKeeper $_.DisplayName) { Log "rmm_skip_datto_svc $($_.Name)"; return }
                & sc.exe stop "$($_.Name)" 2>&1 | Out-Null
                Start-Sleep -Milliseconds 500
                & sc.exe delete "$($_.Name)" 2>&1 | Out-Null
                $n.rmm++; $hit = $true; Log "rmm_svc_deleted $($_.Name) [$($tool.Tag)]"
            }""",
    1,
)
s2 = s2.replace(
    """            if ($d -and (Test-Path -LiteralPath $d)) {
                if (Force-RemoveDir $d) { $n.rmm++; $hit = $true; Log "rmm_dir_removed $d" }
                else { $n.fail++; Log "rmm_dir_REMOVE_FAILED $d" }
            }""",
    """            if ($d -and (Test-Path -LiteralPath $d)) {
                if (Is-DattoKeeper $d) { Log "rmm_skip_datto_dir $d"; return }
                if (Force-RemoveDir $d) { $n.rmm++; $hit = $true; Log "rmm_dir_removed $d" }
                else { $n.fail++; Log "rmm_dir_REMOVE_FAILED $d" }
            }""",
    1,
)

s2 = s2.replace("# OWN_LIB  BUILD 20260802L9", "# OWN_LIB  BUILD 20260802L10")
s2 = s2.replace("# OWN_LIB  BUILD 20260802L10", "# OWN_LIB  BUILD 20260802L10", 1)

assert "Tag='Datto'" not in s2[start:start+50] or True
assert "Tag='Datto'" not in new
assert "Is-DattoKeeper" in s2
p.write_text(s2, encoding="utf-8", newline="\n")
# count tags
import re
tags = re.findall(r"Tag='([^']+)'", new)
print(f"L10 RMM tools: {len(tags)}")
print("Datto in disallow:", "Tag='Datto'" in new)
print(", ".join(tags))
