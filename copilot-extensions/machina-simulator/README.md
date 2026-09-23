# machina-simulator (Copilot CLI extension)

Active Copilot CLI surface for the Machina simulator ecosystem: validate and
compliance-score state-machine definitions, fill deterministic gaps, look up the
spec, and visually inspect state machines — all from the terminal.

This extension is the canonical home of the Machina **simulator** implementation
and its maintenance docs (see [`simulator/`](simulator/)). For **authoring**
state machine definitions, use the [`machina-authoring`](../../skills/machina-authoring/SKILL.md)
skill — the tools here implement the same deterministic 17-check / weight-100
compliance model that skill's bundled `machine-validator.py` uses, so in-session results
match what authors see when they score a definition.

## What it provides

| Surface | Name | Purpose |
|---|---|---|
| Tool | `machina_validate` | Score a state machine 0–100 against its target spec version; returns grade, per-category breakdown, blocking findings, and per-check findings with remediation. |
| Tool | `machina_autofill` | Deterministic "Generate missing" patches (spec_version → version → scenarios → coverage → cycle-guards → descriptions → finals-typed); returns the patched definition and before/after scores. Never mutates the input. |
| Tool | `machina_spec` | Look up any registry spec version as JSON Schema (draft 2020-12) or Markdown. |
| Canvas | `machine-simulator` | Side-panel that runs the full simulator app: graph, playback, scenarios, coverage, cycle guards, compliance, schema editor — and **run replay** of a recorded Machina ledger, plus a **Runs** inventory tab that auto-discovers persisted run history. |
| Slash command | `/machina-simulator` | Open the `machine-simulator` canvas. Optional argument: a machine JSON string to preload. |

## Opening the canvas from the terminal

`/machina-simulator` (no leading slash in code; invoked as a slash command) opens
the `machine-simulator` canvas via the `open_canvas` tool. You can also pass a
machine JSON string to preload it:

```
/machina-simulator
/machina-simulator { "id": "pm-release-notes", ... }
```

The command is wired like `session-md-reader`'s `/session-md-viewer` — the handler
sends a prompt that tells the agent to call `open_canvas` with the canvas id; the
actual render happens in the agent runtime.

## Canonical docs (simulator maintenance)

The Machina simulator app (`simulator/app.html`) and its maintenance
docs live under [`simulator/`](simulator/) and are the **canonical** reference for
this extension:

| Path | Covers |
|---|---|
| [`simulator/app.html`](simulator/app.html) | The simulator app (served by the extension at `/`; a single source of truth for the interactive UI) |
| [`simulator/docs/maintenance.md`](simulator/docs/maintenance.md) | Editing rules, invariants, pitfalls, engine-parity notes |
| [`simulator/docs/architecture.md`](simulator/docs/architecture.md) | App shell, engine/playback, graph, inspector, file I/O |
| [`simulator/docs/schema-spec.md`](simulator/docs/schema-spec.md) | Machine JSON shape, guard/action semantics, SPEC_REGISTRY |
| [`simulator/docs/compliance-scoring.md`](simulator/docs/compliance-scoring.md) | 17-check registry, scoring math, grades, autofill pipeline |
| [`simulator/samples/machina-order.json`](simulator/samples/machina-order.json) | Reference state machine definition (also used by the test suite) |

`machine-simulator.mjs` at the extension root is a dependency-free port of the
compliance/scoring/autofill engine. It is served to the app at `/machine-simulator.mjs` and
imported by the app's module script, so both the tools and the simulator share a
single engine implementation. Keep it in sync with `simulator/docs/maintenance.md`
whenever the scoring or autofill model changes.

## How the simulator is served

The extension runs a loopback HTTP server (bound to `127.0.0.1`) that serves:

| Route | Content |
|---|---|
| `/` | `simulator/app.html` — the full interactive simulator |
| `/machine-simulator.mjs` | `machine-simulator.mjs` — the shared compliance/scoring/autofill engine |
| `/events` | SSE stream carrying `machina` events (`{type:'load'}` with a state machine, or `{type:'command'}` for playback) |
| `/state` | JSON snapshot of the loaded state machine + compliance summary for an instance; also exposes `runHistory` (auto-discovered run inventory) and `replay` (verdict, integrity, terminal) |
| `/runs` | JSON run-history inventory: `{ ok, runs: [{ root, family, runid, machine, machineName, records, readError, terminal, verdict, integrityOk, finalState, blockedCount, machineMatch, childRuns, report, startedAt }] }` from the shared discovery convention |
| `/open-run` | `?instance=<id>&runRef=<family>/<runid>` — resolve a persisted run server-side, enter replay mode, and broadcast the replay `load` event to the app |

The canvas `open` handler returns the app URL; the `machina_load` action live-loads
a state machine into the app over SSE, and the `machina_command` action drives playback
(play/pause/step/back/reset/scenarios/compliance/jump; in replay mode
`replayStep`/`replayBack`/`replayReset`/`replayJump`). The `machina_replay` action
loads a recorded run ledger and enters replay mode with an integrity verdict.

## Run replay & conductor watch

`machina_replay` replays a recorded Machina run from a persisted ledger — the exact
event sequence + evidence + child_run + context_after as it happened, verified against
the SHA-256 chain:

| Aspect | Behavior |
|---|---|
| Input | `machine` (definition) + `ledger` (array of `{prev_hash, payload, hash}` records: `init`/`transition`/`blocked`/`redirect`/`abort`) |
| Integrity | Recomputes the Python-canonical hash chain; when `machineJson` (raw machine.json text) is passed, also verifies the pinned `machine_sha256` (sha256 of the parsed machine in Python-canonical form, lexeme-preserving). Verdict `verifiable` / `tampered` with `indexOfFirstFailure`, `expectedHash`, `actualHash`; `machineHashOk` is `true` / `false` / `null` (null = not verified because raw text wasn't provided). |
| Terminality | `terminal: complete` / `stuck` (blocked-final) / `aborted` / `incomplete` — non-terminal runs are surfaced, not silently "complete" |
| Evidence | Blocked records carry `reason` + `evidence[]` + `note`; transition records carry `child_run` (nested-badge renders the delegation). The app's log timeline renders these inline: evidence chips (✓/✗ tool), the agent's `note` («…»), and a ⚑ **spec-disagreement** line when `guardMismatch` fires |
| Diff | `diffReeval` re-evaluates guards against the context-before; `guardMismatch` flags when what happened disagrees with what the machine says should have happened |
| Trust | The app renders a **✓ verified** (green) or **TAMPERED at record N** (red) badge; when raw machine text is provided, machine-hash verification is folded in (`machineHashOk` false → HASH MISMATCH). |
| Report | When the run dir has a `report.json` (`machina.report.v1`, written by `machine-driver.py report`), discovery parses it into every run's inventory and `/open-run`. The app shows a colored **result chip** (SUCCESS / STUCK / ABORTED / IN_PROGRESS) in the audit banner and a **Report** button that opens a full report modal: result, run KPI grid (events / redirects / blocked / evidence ✓✗, started time), path, **Agent timeline**, context snapshot, nested runs (**drill-down**), parent runs (**drill-up**), `ledger_final_hash`, and a raw JSON view with **Copy JSON**. A **tampered** ledger is never presented as clean SUCCESS — the result chip becomes "⚠ SUCCESS (UNVERIFIED)", the banner shows the TAMPERED verdict, and the modal opens with a red warning banner. |
| Timestamps | Every run row carries `startedAt` (the `init` record's `timestamp`); rendered in the run list, the audit banner, and the report modal's Run KPI grid. |
| Drill navigation | **Canvas-level:** a PHASE state node in the graph carries a clickable **↳ child** badge when the ledger records the child run it delegated to — clicking opens that child machine/run in the stage (drill-down). When the replayed run is itself a child, its **terminal node** carries a sticky **↑ parent** badge that reopens the parent run (drill-up) — mirroring the drill-down UX node badge. The run list child chips, the report modal's "Nested runs", and the audit banner's "↑ parent" link provide the same navigation outside the graph. |

### Run-history discovery (`runRef`)

Instead of passing `machine` + `ledger` by hand, you can reference a **persisted run**
by its discovery path. Both the canvas `open` handler and `scripts/replay-all.mjs`
share one discovery convention (`scripts/discovery.mjs`):

1. **Roots** — explicit roots > `MACHINA_RUN_ROOTS` env (`;`/`,`-separated) >
   every `~/.copilot/session-state/<uuid>/{machina-runs,machina-persist,machina-i2}` that exists.
2. **Run** = any directory containing `ledger.jsonl` (+ optional `machine.json` sibling,
   and optional `report.json` terminal report, which is parsed into `run.report`).
3. **Ref formats** — `"<family>/<runid>"` or a bare `"<runid>"` (bare may be ambiguous
   across families → error).
4. **Machine** — sibling `machine.json` if present; otherwise replay falls back to the
   init record's `machine_id` identity (`machineMatch`).

E.g. open the canvas already replaying a persisted run:

```json
{ "runRef": "i5-releasenotes/6c9dfff19bf2" }
```

`machina-runs` is the canonical write location (written by `machina-driving`:
`<session-workspace>/machina-runs/<run-id>/`); `machina-persist` and `machina-i2` are
**legacy read-only** roots from earlier naming rounds, scanned for replay compatibility
but never write targets.

### Auto-discovery & the Runs tab

Opening the canvas with **no input** auto-discovers the persisted run history and
exposes it without a `runRef`:

- `open()` always runs `discoverRunHistory()` and stores the adjudication-summary
  inventory in `/state` → `runHistory` (`[{ family, runid, machine, records,
  readError, terminal, verdict, integrityOk, finalState, blockedCount, machineMatch,
  childRuns }]`). An empty open shows the discovered count in the status line
  (e.g. "Empty — load a machine or pick a run (21 discovered)").
- The app's **Runs** tab (`/runs` + `/open-run`) groups runs by family with a
  family-level aggregate, and each run row carries an **outcome chip**
  (✓ complete / ⚠ stuck / ■ aborted / … incomplete / ✗ tampered), the final state,
  record count, **started timestamp**, and child-run references (clickable
  drill-down; a tampered run's chip is always ✗ tampered even if it reached a
  final state).
- Clicking a run calls `/open-run` and the SSE `load` event replays that run from
  its ledger in the stage — **opening at the final record** (with an audit banner:
  outcome, integrity verdict, final state, blocked count, path) so the conductor
  lands on the *result* and steps backwards to inspect. Transport buttons and
  arrow keys are replay-aware in replay mode (`replayStep`/`replayBack`/`replayReset`).

### Conducting from the browser

The app URL returned by `open` is a loopback URL with an `instance` id:
`http://127.0.0.1:<port>?instance=<id>`. SSE is **per-instance and shared** — two
browsers opened on the same URL receive the same `machina` event stream. That makes
the conductor-watch workflow deliberate:

> **Open <url> in any browser to watch** — the agent drives the simulator live;
> you see every load/command the agent fires, on the same timeline. For a recorded
> run, the conductor replays the ledger and steers the agent at the next live run.

The conductor->agent steering protocol (for recorded runs): the conductor opens the
same URL, watches the replayed history, and tells the agent which gate/decision to
fix before the next live run. The re-eval diff in `machina_replay` output is what
powers that instruction — "record N says X, but the machine says the guard should
have gone to Y".

For runs that are still *executing* (not just replayed), the **Live** tab watches
them progress without a reload — see [Live watching](#live-watching) below
(`GET /live` + `GET /live-events`).

## Live watching

The **Live** left-panel tab (alongside Schema/Runs) lists every run the watcher
marks live (`row.live === true`). Round 2 detection rules **explicitly supersede**
Round 1's "lifecycle membership, **never clock-migrated**" claim — LIVE
membership now means **all** of:

- **No terminal report** — no `report.json` whose `result` is anything other than
  `IN_PROGRESS`, **and no `abort` record**;
- **R1 — disposition / grace** — the run's disposition is not yet terminal, **or**
  it is replay-terminal but within the **30-minute grace window** since
  `lastActivity` (the window in which the `report` command is expected to land);
- **R2 — staleness cap** — for mid-state (non-final) candidates, `lastActivity`
  is younger than **24 hours**; at the cap the row is no longer live.

An `IN_PROGRESS` report is **not terminal evidence** and **does not
short-circuit liveness** — such runs fall through to the same clock rules as
reportless runs:

- **Machine-gated final state** — live through the 30-min grace, then `live:
  false` with `terminal` via precedence (report mapping first, else the replay
  terminal verbatim — the real-world 8.6-day-old `f87fb459bce7` `IN_PROGRESS`
  exemplar → `"complete"`). Same exit as P1: if it was live when grace expired,
  `live-final` (toast + row leaves); born past grace → silent.
- **Mid-state** — live while under the 24h cap, then the stale class
  (`live: false`, `terminal: null`, silent).

**Fresh `IN_PROGRESS` runs remain LIVE exactly as before** — that is the normal
mid-run state: recent `lastActivity` sits inside both windows (grace for a
replay-final disposition, the 24h cap for mid-state). Ledger growth after a
terminal report makes the run live again (`reportStale`), and that re-live
flows through the same clocks too — fresh `lastActivity` keeps it live, while
quiet ≥24h in mid-state goes stale.

The four pattern classes the rules cover:

| Pattern | Behavior |
|---|---|
| **P1 — reportless-final** | Replay shows a machine-gated final state but the `report` command never ran: live through the 30-min grace, then the row **leaves the Live tab** with `live: false` and `terminal` from the report mapping first, else the replay terminal verbatim (e2ae-class → `"complete"`). If the run was live in the watcher's view when grace expires, that **is** a `live-final` (toast + row leaves — an observable exit for a real completion); rows already past grace when first seen are born terminal and were classified **silently, no toast**. |
| **P2 — reportless-abandoned** | The agent died mid-state with no report/abort: **drops out of the Live tab silently at the 24h cap** (a staleness drop is not a terminal disposition — **no toast**) and **stays visible in RUNS**, where the stale row keeps `terminal: null`. |
| **P3 — abort-record** | `abort` record → `terminal: "aborted"` — already correct. |
| **P4 — has report** | Non-`IN_PROGRESS` `report.json` → mapped terminal — already correct. |

The **heartbeat text** (`in <state> for Xm · no event for Xm`) and the **quiet
tint** (>60s idle) remain **cosmetic only** — they never affect membership; the
30-min grace window and the 24h staleness cap are what move it.

The inventory is fed by `scripts/live-watcher.mjs`: a stat-poll (~5s over the
discovered run roots — size/mtime only, re-parsing just the grown `ledger.jsonl`
files). The watcher runs **only in the primary** — session-hosted or standalone,
identical code path — and browsers always talk to whoever owns port 7750.

| Element | Behavior |
|---|---|
| LIVE badge | Pulsing ● **LIVE** while live; quiet tint + heartbeat text are display-only cosmetics. |
| Advisory chip | **⚠ no exits** — *syntactic* and machine-gated (computed only when a sibling `machine.json` exists): the current state is non-final with **zero outgoing transitions**. Display-only; deliberately avoids the protocol's "STUCK" vocabulary — the driver's report stays authoritative (semantic zero-*enabled* events would need the Python evidence checkers the simulator can't run). |
| Terminal chip | On **`live-final`** (the `machina-live` event carrying a report/abort disposition): **toast + the row leaves the Live tab** — the run's final outcome is then viewed in **RUNS**. The clock-driven P1/P2 departures above are silent. |
| Machine-less rows | Still listed but **click-disabled** — `/open-run` 404s them: replay skipped, no advisory, `terminal: null`. |
| Child runs | **Indented** under their parent via `childRuns`. |

A row carries exactly: `root`, `family`, `runid`, `runRef`, `machineId`,
`machineName`, `session`, `currentState`, `records`, `lastActivity`, `advisory`,
`childRuns`, `machineMissing`, `terminal`, `live` — the Round-1 14 fields plus
**`live: boolean`**, which the UI reads directly instead of inferring liveness
from `terminal == null`. Stale (P2) rows keep `terminal: null`.

**Watch-only (INV-1):** the tab never drives or fires anything — driving stays the
agent's job; the replay playback controls only steer the visualization. Clicking a
row loads it into the shared stage via `/open-run` and switches the stage into
**follow mode**:

- The stage shows a **Following ● / Paused ⏸** toggle — ON when the run was opened
  from the Live tab.
- While Following, each live delta for the watched `runRef` triggers a
  **debounced (~500ms) re-fetch of `/open-run`** — a full, idempotent replay reload
  (there is no incremental append to make).
- A manual step-back **auto-pauses** (user intent wins — no yank-forward); flipping
  the toggle back on **jumps to the latest record**.
- On the run's final event (`machina-live` → `live-final`): **toast**, and the
  stage auto-loads the final replay **only if it is watching that run**; either
  way the row **leaves the Live tab** — its final stays viewable in **RUNS**.
- Viewers are concurrent and read-only: any number of browser tabs may watch the
  same run — no locks; each tab loads/follows only what it clicks.

The Live tab is a **global feed**: the RUNS tab's `sessionWorkspace` picker keeps
its tri-state contract scoped to **`/runs` only** and does not affect the Live tab.

### Endpoints

| Route | Contract |
|---|---|
| `GET /live` | **Live rows only** (initial render + the poll fallback): `{ ok: true, rows: [...] }` — each entry the row shape above with `live: true`. Accepts **no scope parameters**: the Live tab is a global feed (the RUNS workspace picker does not affect it). |
| `GET /live-events` | **Instance-agnostic** SSE — one module-level stream shared by every connected tab: `:ok` prime on connect, client removed on close (mirrors `/events`), write-guarded pushes, **15s heartbeat comment**. Updates arrive as the **`machina-live`** event carrying delta rows and final events. **Client contract:** plain `EventSource`; only after repeated hard errors (or a CLOSED stream) does the client **close the EventSource first, then poll `GET /live` every 5s** — never both at once — and it **resumes the stream on recovery**. |

## Standalone pre-start (manual conductor)

Bind the fixed simulator port without starting a Copilot session:

```bash
node scripts/start-standalone.mjs   # or: npm start
```

The server claims `127.0.0.1:7750` and serves the full UI plus `/action/*`
endpoints. Copilot sessions started later detect the port in use, **skip
auto-start**, and attach as secondaries: their agents' `open_canvas` and
canvas actions delegate to this process over HTTP, and every browser tab
(`?instance=<id>`) shares the one server. Running the launcher twice is safe —
the second run exits with "already running" (exit 0).

The listener binds **IPv4 loopback only** (`127.0.0.1`, plain HTTP): open
`http://127.0.0.1:7750/` — not `https://`, and not `http://[::1]:7750/`
(IPv6 loopback is refused; if your client resolves `localhost` to `::1`
first, use the `127.0.0.1` form). If the URL is refused outright, nothing is
listening yet — check with the command in
[Stopping an instance](#stopping-an-instance) and start one.

## Stopping an instance

There are three kinds of running instance — how you stop one depends on which
it is. Find the listener first:

```powershell
Get-NetTCPConnection -LocalPort 7750 -State Listen | Select-Object -ExpandProperty OwningProcess
```

| Instance | How it runs | How to stop |
|---|---|---|
| **Standalone** | `node scripts/start-standalone.mjs` / `npm start` (a foreground node process) | `Ctrl+C` in its terminal, or `Stop-Process -Id <PID>` for the PID above |
| **Session primary** | the Copilot session's extension process that won the port election | **End that Copilot session** — the extension process is part of the session and exits with it. Killing the PID directly works but yanks the extension from a live session |
| **Session secondary** | a session's extension process that found the port busy (no server of its own) | Nothing to stop — it holds no port and dies with its session |

After stopping the primary, nothing needs manual restart:

- Remaining session secondaries **re-elect on their next canvas action**
  (`tryBecomePrimary`) — one binds `127.0.0.1:7750` again.
- The next `start-standalone.mjs` or session start binds it fresh; the
  launcher exits politely with "already running" if something else got there
  first.
- Open browser tabs recover on their own: the instance SSE auto-reconnects
  and `/live-events` falls back to 5s `/live` polling until the stream is
  back — no tab restart needed.

## Install

Extensions are experimental. Run `copilot --experimental` (or use
`/experimental on` in a session), then place this folder under one of:

* User scope — `~/.copilot/extensions/machina-simulator/extension.mjs`
* Project scope — `.github/extensions/machina-simulator/extension.mjs`

Reload with `/clear` (fresh session) or "Reload my extensions" (Load & Augment).
Verify with `/extensions manage`.

## Usage examples (agent-facing)

* "Validate `state-machine.json` with machina_validate."
* "Run machina_autofill on the machine in `sample.json` and show what changed."
* "Give me the machina_spec for v1.0.0 as JSON Schema."
* "Open the machine-simulator canvas for this state machine."

## Development

**Versioning — one source of truth:** bump `package.json` `"version"` only.
The banner version shown in the UI is injected from it at serve time
(`__PKG_VERSION__` replacement in `extension.mjs`), so `package.json` and the
visible version can never drift. Add a dated entry to the `app version`
changelog comment in `simulator/app.html` per release, using the same
`package.json` version string.

```powershell
# Run the full suite (engine + handler contracts + canvas/HTTP integration)
npm test
```

The suite is clone-safe: `test/sdk-stub-loader.mjs` maps the CLI SDK specifier
to a committed test stub so `extension.mjs` (including its HTTP server and
canvas wiring) runs outside the CLI runtime. No `node_modules` required. The
suite loads `simulator/samples/machina-order.json` as its reference state machine.

## Notes

* Uses `session.log()` never `console.log()` — stdout is reserved for JSON-RPC.
* The compliance engine matches the documented model used by the `machina-authoring`
  skill's bundled `machine-validator.py`: `pass(false)` reports a failing check, and checks
  apply when `since ≤ target spec version` (all 17 checks at v2.0.0, total weight 100).