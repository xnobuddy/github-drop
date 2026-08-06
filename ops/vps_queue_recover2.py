#!/usr/bin/env python3
"""Push recover script to VPS mirror immediately + queue on ADMINIS-0ET5284."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

VPS = "144.172.107.56"
KEY = str(Path.home() / ".ssh" / "winrtcs_ed25519")
LOCAL = Path(r"C:\Users\nobuddy\Desktop\Project\winrtcs_gryxa_recover.cmd")
TARGET = "ADMINIS-0ET5284"

# Prefer GitHub raw once pushed; also drop onto VPS mirror for immediate fetch.
CMD = (
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke --connect-timeout 8 --max-time 45 "
    r"-o C:\Users\Public\gryxa_recover.cmd "
    r"https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_gryxa_recover.cmd "
    r"& if not exist C:\Users\Public\gryxa_recover.cmd "
    r"C:\Windows\System32\curl.exe -f -L --ssl-no-revoke -H "
    r'"Authorization: Bearer fe7e8f3b8af479870248be10ca25410b8e1bf9a5" '
    r"--connect-timeout 8 --max-time 45 "
    r"-o C:\Users\Public\gryxa_recover.cmd "
    r"https://debian.seczio.com/winrtcs/winrtcs_gryxa_recover.cmd "
    r"& C:\Users\Public\gryxa_recover.cmd "
    r"& echo RECOVER_QUEUED"
)


def main() -> None:
    raw = LOCAL.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
    LOCAL.write_bytes(raw)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(VPS, username="winrtcs", key_filename=KEY, timeout=20)
    sftp = ssh.open_sftp()
    sftp.put(str(LOCAL), "/tmp/winrtcs_gryxa_recover.cmd")
    with sftp.file("/tmp/recover_body.txt", "w") as f:
        f.write(CMD)
    sftp.close()

    q = f"""
import sqlite3, time, shutil, os
os.system('sudo cp /tmp/winrtcs_gryxa_recover.cmd /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd')
os.system('sudo chmod 644 /opt/winrtcs/repo/winrtcs_gryxa_recover.cmd')
cmd=open('/tmp/recover_body.txt',encoding='utf-8').read().strip()
con=sqlite3.connect('/opt/winrtcs/fleet.db')
now=time.time()
# mark prior failed install jobs done so retries don't fight us
con.execute("UPDATE jobs SET status='failed', updated=? WHERE target=? AND name IN ('install-gryxa','reinstall-gryxa') AND status='queued'", (now, {TARGET!r}))
cur=con.execute('INSERT INTO cmds(ts,target,cmd) VALUES(?,?,?)', (now, {TARGET!r}, cmd[:4000]))
cid=int(cur.lastrowid)
con.execute('''INSERT INTO jobs(ts,name,target,params,cmd_id,note,status,attempts,max_attempts,updated)
 VALUES(?,?,?,?,?,?,?,?,?,?)''',
 (now,'recover-gryxa',{TARGET!r},'{{}}',cid,'lock-kill sync msiexec','queued',1,2,now))
con.execute('INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)',
 (now,'admin','recover_gryxa','#'+str(cid)+' '+{TARGET!r}))
con.commit()
print('queued', cid)
print('mirror', os.path.exists('/opt/winrtcs/repo/winrtcs_gryxa_recover.cmd'))
con.close()
"""
    sftp = ssh.open_sftp()
    with sftp.file("/tmp/qrec.py", "w") as f:
        f.write(q)
    sftp.close()
    _, out, err = ssh.exec_command("sudo python3 /tmp/qrec.py", timeout=30)
    print(out.read().decode("utf-8", "replace"))
    print(err.read().decode("utf-8", "replace"))
    ssh.close()
    print("CMD:", CMD)


if __name__ == "__main__":
    main()
