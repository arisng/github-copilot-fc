# machina-simulator (Copilot CLI extension)

Active Copilot CLI surface for the Machina simulator ecosystem: validate and
compliance-score state-machine definitions, fill deterministic gaps, look up the
spec, and visually inspect state machines — all from the terminal.

This extension is the canonical home of the Machina **simulator** implementation
and its maintenance docs (see [`simulator/`](simulator/)). For **authoring**
state machine definitions, use the [`machina-authoring`](../../skills/machina-authoring/SKILL.md)
skill — the tools here implement the same deterministic 17-check / weight-100
compliance model that skill's bundled `machina.py` uses, so in-session results
match what authors see when they score a definition.

## What it provides

| Surface | Name | Purpose |
|---|---|---|
| Tool | `machina_validate` | Score a state machine 0–100 against its target spec version; returns grade, per-category breakdown, blocking findings, and per-check findings with remediation. |
| Tool | `machina_autofill` | Deterministic "Generate missing" patches (spec_version → version → scenarios → coverage → cycle-guards → descriptions → finals-typed); returns the patched definition and before/after scores. Never mutates the input. |
| Tool | `machina_spec` | Look up any registry spec version as JSON Schema (draft 2020-12) or Markdown. |
| Canvas | `machina-viewer` | Side-panel that runs the full simulator app: graph, playback, scenarios, coverage, cycle guards, compliance, and schema editor. |

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

`engine.mjs` at the extension root is a dependency-free port of the
compliance/scoring/autofill engine. It is served to the app at `/engine.mjs` and
imported by the app's module script, so both the tools and the simulator share a
single engine implementation. Keep it in sync with `simulator/docs/maintenance.md`
whenever the scoring or autofill model changes.

## How the simulator is served

The extension runs a loopback HTTP server (bound to `127.0.0.1`) that serves:

| Route | Content |
|---|---|
| `/` | `simulator/app.html` — the full interactive simulator |
| `/engine.mjs` | `engine.mjs` — the shared compliance/scoring/autofill engine |
| `/events` | SSE stream carrying `machina` events (`{type:'load'}` with a state machine, or `{type:'command'}` for playback) |
| `/state` | JSON snapshot of the loaded state machine + compliance summary for an instance |

The canvas `open` handler returns the app URL; the `machina_load` action live-loads
a state machine into the app over SSE, and the `machina_command` action drives playback
(play/pause/step/back/reset/scenarios/compliance/jump).

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
  skill's bundled `machina.py`: `pass(false)` reports a failing check, and checks
  apply when `since ≤ target spec version` (all 17 checks at v2.0.0, total weight 100).