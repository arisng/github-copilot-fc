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
| Canvas | `machina-viewer` | Side-panel that runs the full simulator app: graph, playback, scenarios, coverage, cycle guards, compliance, schema editor — and **run replay** of a recorded Machina ledger. |

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
| `/state` | JSON snapshot of the loaded state machine + compliance summary for an instance |

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
| Integrity | Recomputes the Python-canonical hash chain and `machine_sha256`; verdict `verifiable` / `tampered` with `indexOfFirstFailure`, `expectedHash`, `actualHash` |
| Terminality | `terminal: complete` / `stuck` (blocked-final) / `aborted` / `incomplete` — non-terminal runs are surfaced, not silently "complete" |
| Evidence | Blocked records carry `reason` + `evidence[]` + `note`; transition records carry `child_run` (nested-badge renders the delegation) |
| Diff | `diffReeval` re-evaluates guards against the context-before; `guardMismatch` flags when what happened disagrees with what the machine says should have happened |
| Trust | The app renders a **✓ verified** (green) or **TAMPERED at record N** (red) badge |

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
* "Open the machina-viewer canvas for this state machine."

## Development

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