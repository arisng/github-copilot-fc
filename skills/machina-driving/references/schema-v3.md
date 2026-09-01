# Machina Schema Spec — v3.0.0 (driving)

The machine JSON contract understood by the `machina-driving` driver
(`scripts/machine-driver.py`). v3.0.0 is a **strict superset** of v2.0.0: every v2 machine
is a valid v3 machine. v2 machines remain valid; upgrades are opt-in via
`spec_version`.

## Versioning model

Three independent version concepts — never conflate:

| Concept | Source of truth | Format | Who sets it |
|---|---|---|---|
| Schema spec version | `SPEC_VERSIONS` in `machine-validator.py` | `x.y.z` | the shared engine |
| Machine version | machine's own `version` field | free-form string | machine author |
| Run report schema | `schema` field in report | `machina.report.v1` | the driver |

- `spec_version` must match a registry entry; absent ⇒ latest assumed. Pins the
  schema *contract*, not machine identity.
- Machine `version` is fully user-managed; never conflate with `spec_version`.

## v3.0.0 field reference

### Machine-level

| Field | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | ✅ | Stable machine identifier |
| `name` | string | recommended | Human-readable label |
| `version` | string | recommended | Machine's own version |
| `spec_version` | string | recommended | Target schema-spec version (`"3.0.0"`) |
| `initial` | string | ✅ (must resolve) | Default initial state key |
| `context` | object | optional | Initial extended state |
| `scenarios[]` | array | recommended | `{ id, label, initial?, context?, interface?, inputs? }` |
| `states` | object | ✅ (non-empty) | Keyed by state id |
| `tools` | object | optional | **v3** Named checker registry: `{ name: { cmd, expect_exit?, timeout_seconds?, output? } }` |
| `limits` | object | optional | **v3** `{ max_events?, max_steps?, timeout_seconds? }` |
| `coverage` | object | optional | Analysis metadata (unchanged from v2) |
| `cycle_prevention` | object | optional | `{ max_retry_limit, timeout_seconds, guards[] }` (unchanged from v2) |

### `tools` registry (v3)

```json
"tools": {
  "draft-file-exists": {
    "cmd": "python3 scripts/check_file.py",
    "expect_exit": 0,
    "timeout_seconds": 30
  },
  "link-check": {
    "cmd": ["python3", "scripts/check_links.py"],
    "expect_exit": 0,
    "output": { "broken": "review.broken_links" }
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `cmd` | string \| string[] | Command to run. First token resolved machine-relative if it contains a path separator. **Never inline code** — this is a reference to a script. |
| `expect_exit` | number | Expected exit code for the check to pass (default `0`) |
| `timeout_seconds` | number | Per-invocation timeout (default `30`) |
| `output` | object | **v3** Optional structured-output mapping: `{ <json_key>: <context_path> }`. If the tool prints a JSON object on stdout, matching keys are assigned into context. |

**Template rendering:** `cmd` tokens may contain `{ctx.path}` and
`{ctx.path|default}` templates, resolved from the run's context at invocation
time. This is how a checker learns *what* to verify (e.g. the draft file path).

### State-level (v3 additions)

| Field | Type | Meaning |
|---|---|---|
| `state.type` | `"atomic" \| "final" \| "phase"` | `phase` = nested machine delegation (v3) |
| `state.checks[]` | string[] | **v3** Tool references that must pass **before any outgoing transition fires** (gate all exits) |
| `state.invariants[]` | string[] | **v3** Tool references that must hold *while in* the state (reported by `status`, advisory in v1) |
| `state.entry` / `state.exit` | action[] | Unchanged from v2 |
| `state.on` | object | Event map (unchanged from v2) |

### Transition-level (v3 additions)

| Field | Type | Meaning |
|---|---|---|
| `transition.target` | string | ✅ must resolve |
| `transition.guard` | guard object | Unchanged from v2 (`{ type:"compare", key, op, value }`) |
| `transition.actions` | action[] | Unchanged from v2 |
| `transition.requires[]` | string[] | **v3** Tool references that must pass **in addition to** the state's `checks[]` before this specific event fires |
| `transition.ensures[]` | string[] | **v3** Tool references validated **after** the transition fires (post-condition). If any fails, the transition is recorded but flagged — see [driving-protocol.md](driving-protocol.md) |
| `transition.else_target` | string | **v3** Deterministic redirect when the guard fails (modeled failure path). Overrides the default stay+record |
| `transition.description` | string | Unchanged from v2 |

### Scenario-level (v3 addition)

```json
"scenarios": [{
  "id": "default",
  "label": "Default",
  "initial": "reviewing-draft",
  "interface": "API",
  "inputs": {
    "draft_path": { "required": true, "type": "string" }
  }
}]
```

| Field | Type | Meaning |
|---|---|---|
| `scenario.inputs` | object | **v3** Declared input contract: `{ <name>: { required?, type? } }`. `init` fails unless all required inputs are supplied via `--input k=v`. |

### `limits` (v3)

```json
"limits": { "max_events": 20, "max_steps": 10, "timeout_seconds": 1800 }
```

| Field | Type | Meaning |
|---|---|---|
| `max_events` | number | Hard cap on fired transitions; exceeding blocks further events |
| `max_steps` | number | Reserved for step-based budgets (v1: informational) |
| `timeout_seconds` | number | Reserved for wall-clock budgets (v1: informational) |

## Runtime semantics

- **Guard evaluation** (`eval_guard`): dotted-path context read; string `value`
  resolves against context keys first, then numeric coercion; unknown op → pass.
- **Actions** (`apply_actions`): `increment` (+1 on dotted path, default 0);
  `assign` (set path).
- **Firing order**: exit actions → transition actions → target entry actions.
- **Evidence order**: state `checks[]` then transition `requires[]`, each tool
  run in declaration order. All must pass for the transition to fire.
- **Terminal**: `type:"final"` or no outgoing transitions.
- **Phase state**: `type:"phase"` marks a state whose *work* is delegated to a
  nested machine. The driver does not auto-advance; the agent fires the
  completion event, and the driver permits it **iff** the child run ended in a
  success final (see [driving-protocol.md](driving-protocol.md)).
- **Blocked events**: stay in the current state; the ledger records a `blocked`
  entry; `fire` returns a first-class `blocked` JSON outcome (never an error
  exit). If the transition declares `else_target`, a guard failure redirects
  there instead.

## Conventions

- Event names `UPPER_SNAKE`; state keys `kebab-case`.
- Guard `value` may reference context keys by name.
- Tools are named references to scripts — **never inline code** (INV-2).
- Checker scripts are **read-only validators** in v1: they inspect files and
  processes and report exit code/stdout; they must not mutate the world.

## v2.0.0 (historical)

Subset of v3: no `tools`, `limits`, `checks[]`, `invariants[]`, `requires[]`,
`ensures[]`, `else_target`, `phase`, or scenario `inputs`. Preserved as a
faithful subset so v2 machines remain valid and exportable.

## v1.0.0 (historical)

Subset of v2: `id`, `name`, `version`, `initial`, `context`, `states` with
`state.type` and `state.on` where transitions are `{ EVENT: { target } }` only.