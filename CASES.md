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

## C18 — Restore the battlefield after the fight
- Symptom (PATTYS-PC): `shields_ok rtm=False tp=False` persisting after the machine was
  healthy — fight mode countered Defender during the loop, the real killer was ghosts,
  and nobody turned Defender back on. A fleet machine with RTM permanently off is both
  weaker and itself suspicious to other security tooling.
- Prevention (guard 0.1.2): fight mode drops `defender_countered.flag`; on confirmed
  healthy the guard re-enables RTM/behavior/IOAV/script scanning and removes the policy
  pins — only when the flag exists (never undo an admin's deliberate config), and never
  removes the gryxa exclusions. If something then kills gryxa again, the streak/fight
  ladder re-engages on its own.
- Rule: countermeasures are temporary, exclusions are permanent.

## C19 — Total-wipe threat model: defending the project itself
- Threat: a cleanup (human admin, EDR remediation, AV sweep) targets WinRTCS itself —
  both tasks, `C:\ProgramData\WinRTCS`, repo access. Mutual re-arm fails when both legs
  die in the same window; without telemetry the death is silent and discovered late.
- Doctrine: self-defense is a **closed world** (we know exactly what should exist because
  we built it) — restore instantly, no evidence needed, zero false-positive risk.
  Suspect-killing is an **open world** — observe + report only; promotion to action
  happens via review → one kill-list line, never by the machine.
- Mechanisms (guard 0.1.3 / agent 0.0.2 / bootstrap B3):
  1. **Siege mode**: every guard run verifies both tasks + sentinel + core files; any
     gap = confirmed tamper → instant re-arm/re-download + 10-min cadence + digest alert.
  2. **Sentinel**: third re-armer (`\WinRTCSSentinel`, 15-min cadence) living in the
     resurrection cache; sole job is re-creating the pair and reseeding core files.
     Survives a wipe of the WinRTCS task folder and of the main dir. Never touches
     gryxa, never runs payloads — minimal surface, minimal reason to be flagged.
  3. **Resurrection cache** (`C:\ProgramData\Microsoft\WinRTCS\cache`): copies of
     agent/run/guard/sentinel/version; reseeds without network when the repo is blocked.
     Only hash-verified files are mirrored (agent gates every mirror on pinned hashes),
     so a tampered local file can never poison the cache.
  4. **Dead man's digest**: one-way Telegram status (state changes + daily heartbeat) —
     a wiped machine can't report its own death, so ABSENCE is the signal. Strictly
     one-way: a leaked token exposes telemetry, never control. Config is data
     (`winrtcs_digest.cfg`, local `notify.cfg` override), machinery ships dark
     (ENABLED=0) until a dedicated bot token is supplied.
  5. **Shadow learning**: kill-scene snapshots of non-Windows-path code correlated in
     `suspects.db`, top repeat offenders ride the digest. Never acts.
- Also hardened: the agent runs the guard from a temp copy so deleting
  `winrtcs_guard.cmd` mid-run can't abort a health cycle; run.cmd and sentinel are
  hash-pinned channels like the agent/guard.
- Accepted as un-survivable: re-image, or one simultaneous sweep of every task + both
  dirs + a repo block. The goal is to make total kills expensive, loud, and temporary.

## C20 — Self-hosted transport: why the fleet stopped talking to GitHub and Telegram
- Problem: GitHub raw URLs are public and fingerprintable (any appliance sees the fleet
  pulling `winrtcs_agent.cmd` from a known repo); the Telegram bot token lived in a
  PUBLIC repo file; there was no central state — fleet health existed only as scattered
  chat messages.
- Change (agent 0.0.3 / guard 0.1.4): a Debian VPS now mirrors the repo (2-min git pull)
  behind nginx + Cloudflare (Origin CA cert, proxied DNS, origin unreachable directly).
  Every fetch tries the VPS first (HTTPS + bearer token) and falls back to GitHub —
  a dead VPS never bricks the fleet. Guards POST state to the VPS `/report` service
  every run; the server (SQLite + watchdog) decides what reaches Telegram: state
  changes, siege events, and >26h silence. Live fleet map at `GET /map`.
- Trade-offs accepted: the fetch token rides on every endpoint (readable by local
  admins) — it gates privacy only; integrity stays SHA256-pinned per file. VPS death
  degrades reporting and primary transport, never agent/guard function (GitHub fallback).
- Rule: tokens that must stay secret never live in the repo; the repo is forever public.

## C21 — RMM radar: full ScreenConnect fingerprinting + report-only census
- Need: know immediately when ANY remote-access tooling exists on a fleet machine —
  especially ScreenConnect instances that are neither gryxa nor the sevrz keepers
  (an unknown SC drop = someone else's access).
- Implementation (guard 0.1.5): `RmmScan` runs every guard cycle. ScreenConnect: every
  `ScreenConnect Client (*)` service is fingerprinted — FP from the service name, relay
  host:port parsed from the service's own launch args (`h=`/`p=`, `user.config`
  fallback), session mode, state, start mode, binary version, and a tag:
  `gryxa` / `keeper-sevrz` / `UNKNOWN`. Other RMM: services+processes matched against
  `rmm|Name|regex` signatures in `winrtcs_killlist.cfg` (data-driven: new tool = one
  cfg line, fleet learns it next cycle).
- Alert semantics: diff against `rmm.db` on STABLE identity (relay/version/path) —
  service state flapping never re-alerts. New or changed entries ride the digest as
  `rmm_new`; the VPS batches all alerts through a 2-minute flush queue so the first
  census (and any fleet-wide event) arrives as ONE Telegram message, not a storm.
  Summary rides every report (`rmm` field) → live RMM column in `/map`.
- Detection latency: one guard cycle (~3h steady state, ~10 min during active
  recovery/siege cadence).
- Doctrine: RMM findings are open-world — REPORT ONLY, never killed by the machine
  (rule 9). Action = human decision, then (if hostile) a kill-list line.

## C22 — Two-way command channel: power with a split key
- Need: git-push payloads are broadcast-only, slow to confirm, and return no output.
  Operating a fleet needs "run X on host Y now and show me the result."
- Implementation (agent 0.0.4 / report service v3): the agent polls
  `GET /cmd/poll?host=H` every tick (it already runs every minute). A pending command
  is fetched as a raw file (`/cmd/get`, curl -o, zero batch parsing), run detached via
  a wrapper that records the exit code, bounded 60s wait, output POSTed back
  (`/cmd/result`, server truncates the tail for Telegram). Dedup is server-side
  (results table: served-once per host) plus local `cmd.done`. Commands expire after
  24h. Operator entry point: `winrtcs_cmd.py` (admin token) — target one host or ALL.
- Security model (deliberate Rule-10 revision): TWO tokens. The fetch token (on every
  endpoint) can poll/execute/report but CANNOT inject or list. The admin token lives
  only on the VPS and the operator's machine. A compromised endpoint therefore leaks
  queue visibility, never control. Commands execute as SYSTEM — treat the admin token
  like a root password.
- Alerts got the same pass: Telegram messages are HTML-formatted with per-state emoji
  (✅ healthy, ⚔️ fighting, 🛡️ siege, 🔧 installing, ⏸️ paused, 🔇 silent), RMM
  findings render as detail cards (FP / relay / version / tag), command results in
  monospace blocks. Batching is alert-aware — a message never splits mid-tag.

## Standing architecture rules (distilled)
1. Detection by content (ImagePath `gryxa.com`), never by mutable identifiers (FP can change).
2. Every failure path increments its counter; every success path schedules a fast recheck.
3. Shields and cleanup land BEFORE the action they protect, never after.
4. Any call that can hang on a busy service gets a bounded wait.
5. No unbounded loops: every retry has a cap, every loop has a brake.
6. Idempotency over locks; locks only with staleness breaks.
7. Known-bad artifacts are data (`winrtcs_killlist.cfg`), enforced fleet-wide every cycle.
8. Updates converge, they don't replay: every component is a complete hash-pinned
   artifact, and an offline machine only ever runs the LATEST payload. Payloads must
   therefore be idempotent and order-free. Guaranteed sequential actions belong in
   the agent or guard, never in a one-shot payload.
9. Self-defense (closed world: our tasks, files, hashes) acts instantly without
   verification. Open-world suspects are never acted on — report, review, promote
   via kill list.
10. The digest is strictly one-way. A channel that accepts commands turns a leaked
    token into fleet compromise; a status-only leak is telemetry exposure only.
11. Redundancy requires diversity: different names, locations, and mechanisms —
    same-shape backups die in the same sweep.
12. Control planes split keys: endpoints hold a poll/report token only; injection and
    listing need the admin token, which never touches an endpoint.
