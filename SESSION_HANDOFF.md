# Session handoff — 2026-08-05

Continue from here tomorrow. Repo `main` is pushed through `21c5b60` + C31 note.

## Live systems
- Sight: https://debian.seczio.com/sight (admin token = Desktop `admin_token.txt`)
- VPS: `winrtcs@144.172.107.56` key `~/.ssh/winrtcs_ed25519`
- Fleet DB: `/opt/winrtcs/fleet.db` — report service `winrtcs-report` on `:8077`
- Mirror: `/opt/winrtcs/repo/` (cron pull; also `winrtcs_gryxa_recover4.cmd` staged for installs)

## Shipped today
| Piece | Notes |
|---|---|
| Sight v5 | Sessions, heartbeat, jobs/retries, tags/@dogfood, policy enforce, SLA, audit, pastes, Gryxa columns/actions |
| Agent **0.0.8** | `/heartbeat` every tick + `maint.flag` |
| Guard **0.2.0** | maint skip, sidekick Hunt/Rmm |
| `winrtcs_sidekick.ps1` | Thin PS worker |
| Quick **Q5** / `winrtcs_q.cmd` | schtasks breakaway from Guest 10s job (C30) |
| Gryxa recover | `winrtcs_gryxa_recover.cmd` + VPS `recover4` + schtasks `GryxaRecover` (C29/C31) |
| Cases | **C29**, **C30**, **C31** in `CASES.md` |
| Rule | `.cursor/rules/gryxa-sight-install.mdc` (alwaysApply; may be gitignored locally) |

## Hosts touched today
- **ADMINIS-0ET5284** — Sight reinstall broke Gryxa (1060 + locked dir) → recover4 → back in Gryxa
- **LAPTOP-G0T88MQP** — Quick QUEUED but Agent missing until `wq_run.cmd --detached` → `WINRTCS_Q=OK` → landed
- **E32072484D** — looked healthy/`[gryxa]` but live **1060** → schtasks recover → **seen in Gryxa**
- **DESKTOP-JLB2B33** — online, already had Gryxa (+ unknown `89a1ede2@uvexr`)
- **MOE77** — offline (no beat; digest ~5h+ stale) when last checked

## Preferred Guest paste
```bat
curl.exe -L --ssl-no-revoke -o C:\Users\Public\wq.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_q.cmd && C:\Users\Public\wq.cmd
```

## Ops doctrine (do not regress)
1. Probe with `sc query` — never trust stale RMM/`healthy` alone.
2. Long work = schtasks SYSTEM breakaway or sync `start /wait msiexec` inside detached body.
3. No shared ProductCode `msiexec /x` with keepers present (C03).
4. Agent cmd channel ~60s; PowerShell `$` vars get stripped — use batch for probes.

## Tomorrow candidates
- Kick unknown SC on DESKTOP-JLB2B33 (`89a1ede2`)
- Bring MOE77 online (Guest Quick when available) / refresh guard 0.1.9 → 0.2.0
- Wire Sight Install buttons to schtasks recover path (not start/min only)
- Optional: agent verify `winrtcs.version.sig`
