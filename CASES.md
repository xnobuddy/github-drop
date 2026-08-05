# WinRTCS Case Studies

Every fleet incident, its root cause, and the preventive mechanism now in place.
Referenced by `winrtcs_killlist.cfg` entries and guard header comments. New incidents
get a new case number; if the fix introduces a new artifact pattern, it also goes
into the kill list so the fleet preempts it instead of reacting to it.

## C01 — ScreenConnect Guest shell kills long commands at 10s
- Symptom: bootstrap died mid-run with "Killed after 10000 milliseconds".
- Root cause: Guest session terminates the foreground process tree.
- Prevention: self-detach prologue pattern — scripts copy themselves to a temp path,
  relaunch detached with `--detached`, and exit instantly. All long-running entry
  points (bootstrap) use it.

## C02 — cmd.exe parsing failures from pasted loops and LF line endings
- Symptom: "X was unexpected at this time", mangled `%VAR%` in Guest pastes.
- Root cause: interactive cmd expands `%V` differently; LF-only batch files misparse.
- Prevention: `winrtcs_build.py` CRLF-normalizes every `.cmd` before hashing
  (`.gitattributes` keeps blobs byte-stable); one-liners avoid `for` loops; fleet
  logic ships as downloaded files, never interactive pastes.

## C03 — Shared MSI ProductCode collateral damage
- Symptom: uninstalling gryxa also removed the sevrz keepers (shared
  ProductCode `{9D7CC418-A356-9693-DCC5-41EC44D03B31}`).
- Root cause: ProductCode-scoped `msiexec /x` hits every client from that MSI line.
- Prevention: FP-agnostic detection (ImagePath contains `gryxa.com`), keepers never
  touched; ProductCode actions only inside gryxa-scoped preconditioning.

## C04 — msiexec 1603 on reinstall (phantom registration)
- Symptom: install fails 1603 after a prior uninstall (ADMINIS-0ET5284).
- Root cause: orphaned Installer registry keys block re-registration.
- Prevention: guard preconditioning — kill service, `/x` shared ProductCode, purge the
  5 phantom Installer keys, sweep orphan dirs, one install retry. (Proven in the
  legacy `gryxa_clean_install.cmd` L34 era, carried forward.)

## C05 — Defender exclusions that never landed
- Symptom: gryxa eaten minutes after install despite "exclusions" (EVITA, first waves).
- Root cause: `ExclusionPath` does not expand wildcards; enumeration only covered
  directories that existed at exclusion time; plain-key reg edits are ignored under
  Tamper Protection.
- Prevention: literal gryxa paths pinned via the **Policies** channel (GP channel is
  TP-safe) + bounded async `Add-MpPreference`, always BEFORE install; post-install
  re-shield of the real ImagePath dir.

## C06 — Guard hung 12+ minutes on a busy Defender service
- Symptom: guard stall after `guard_begin` (ADMINIS-0ET5284).
- Root cause: synchronous `Add-MpPreference` blocks when WinDefend is busy.
- Prevention: shields run async with a 60s flag-poll cap; the health ladder never
  blocks on Defender. Any cmdlet that can touch a busy service must be bounded.

## C07 — Self-inflicted payload deadlock
- Root cause: a `mkdir` lock around payloads would survive a mid-payload reboot and
  block all future payloads forever.
- Prevention: no payload locks. Task Scheduler single-instance policy + idempotent
  scripts instead. The guard's overlap lock carries a 15-min staleness break.

## C08 — Fight mode never engaged (streak accounting bug)
- Symptom: endless reinstall loop, `streak=0` forever (EVITA, guard 0.0.3).
- Root cause: `FAIL_svc_not_running` never incremented `fight.cnt`.
- Prevention: EVERY failure path bumps the streak; verified by reading guard.log, not
  by assuming. Lesson: escalation logic is only as good as its accounting.

## C09 — Post-verify kills invisible for 3 hours
- Symptom: client verified, killed 2 minutes later, guard asleep until the next 3h gate.
- Prevention: `guard.cnt=170` (~10 min recheck) after ANY install/recovery; only a
  confirmed-healthy recheck returns to the 3h cadence.

## C10 — Reinstall loop = console duplicate flood
- Symptom: ~96 duplicate entries for one host in the gryxa console.
- Root cause: every `msiexec /i` mints a new ScreenConnect device GUID.
- Prevention: `extkill` brake — 3 consecutive exit-0-but-dead installs pause installs
  (hourly health checks only); payloads reset the brake when a fix ships. Console
  hygiene rule: only ever delete OFFLINE entries — deleting a connected Access session
  sends the client an uninstall command.

## C11 — The gryxa wars (330MLRACE / fleet)
- Symptom: "something is killing gryxa" — service deleted minutes after install.
- Root cause (two layers): outdated M68/L32 build still running old gryxa watcher
  tasks on an un-updatable host; and anything matching the gryxa FP by name.
- Prevention: fleet campaign mechanism for forced migrations; never let fleet builds
  drift (1-min agent tick); kill list entry `36e506ff016b2151` treats FP-targeting
  artifacts as definitionally hostile.

## C12 — EVITA ghost: legacy camo persistence survives the bootstrap
- Symptom (PC-EVITA-X6): service entry deleted within seconds of the 7045
  registration event, zero SCM/MsiInstaller evidence, product registration intact.
- Root cause: pre-WinRTCS persistence the bootstrap's name-based wipe never touched:
  `SystemHealthMonitor` WMI timer → `Diagnosis\ETLParser.ps1`, Run keys
  `DiagnosticsService`/`WindowsDiagnostics` → ETLParser/NetTraceParser, `BVTConsumer`
  → `.wucache\wucache.vbs`, mangled task literally named `%V`.
- Root lesson: **WMI permanent subscriptions live in the WMI repository, Run values in
  the registry — wiping task names and two directories does not remove them.**
- Prevention: HuntKiller runs every guard cycle — processes, WMI consumers/filters/
  bindings, tasks, Run/RunOnce values, files, dirs — driven by `winrtcs_killlist.cfg`
  (data, not code). New artifact = one cfg line; the fleet preempts it.
- Addendum (DESKTOP-T275Q3J, guard 0.0.9): same ghost family ran under different camo
  names — `\Microsoft\SystemDiagnostics\*Analysis` and `\Microsoft\Windows\Diagnosis\*`
  tasks whose actions pointed at the same scripts. Name lists never catch up; content
  patterns do.

## C17 — Guard overlap-lock race
- Symptom (DESKTOP-T275Q3J): duplicate `guard_begin` lines 0.1s apart when the Agent
  and Guard tasks fired on the same minute.
- Root cause: file-exists lock check is not atomic — both processes checked before
  either created the file.
- Prevention (guard 0.1.1): atomic `mkdir` lock (NTFS directory creation is atomic),
  stale locks (>15 min) broken by timestamp; HuntKiller logs matched task actions as
  evidence with every kill.

## C13 — Fleet drift and the rebrand migrations
- Symptom: hosts stuck on old builds never receive fixes (the "never came" class).
- Prevention: campaign hook + bridge payloads (zerocool → winrtcs), hash-pinned
  self-update, 1-minute agent cadence, quick installer for EDR-blocked hosts.

## C14 — "Access is denied" as SYSTEM is not ACLs
- Symptom: SYSTEM shell denied writing/executing `C:\Windows\Temp\wb.cmd`.
- Root cause: active script control (AV/EDR kernel block), not permissions.
- Prevention: `winrtcs_quick.cmd` — minimal low-profile installer (no Defender/service/
  registry tamper strings) that only drops the agent and registers tasks; the agent
  does everything else once alive.

## C15 — Never parse localized command output
- Symptom risk: EVITA is a Spanish-locale Windows; tools like `systeminfo` localize.
- Prevention: only parse language-invariant output (`sc` field tokens, registry, WMI);
  log analysis keys off our own English markers.

## C16 — Multiple gryxa-lineage clients on one host = duplicates without a reinstall loop
- Symptom (DESKTOP-7OE852J): "duplicates" in the console while the guard reports healthy
  and zero reinstalls all day.
- Root cause: a second ScreenConnect client with a different fingerprint
  (`e2ed8513aacaeeec` next to `36e506ff016b2151`) — installed from a different MSI
  generation; if its ImagePath points at gryxa.com the host holds two live connections.
- Also validated here: Policies-channel exclusions hold with Tamper Protection ON
  (`tp=True`), and HideARP removed gryxa from the ARP list as designed.
- Prevention: one-gryxa-per-machine invariant (guard 0.1.0) — DetectAll+ Dedup keeps the
  RUNNING gryxa.com service, stop/deletes extras with their dirs + ARP entries, never
  touches the shared ProductCode, keepers can't match.
- Console hygiene unchanged: delete offline entries only.

## Standing architecture rules (distilled)
1. Detection by content (ImagePath `gryxa.com`), never by mutable identifiers (FP can change).
2. Every failure path increments its counter; every success path schedules a fast recheck.
3. Shields and cleanup land BEFORE the action they protect, never after.
4. Any call that can hang on a busy service gets a bounded wait.
5. No unbounded loops: every retry has a cap, every loop has a brake.
6. Idempotency over locks; locks only with staleness breaks.
7. Known-bad artifacts are data (`winrtcs_killlist.cfg`), enforced fleet-wide every cycle.
