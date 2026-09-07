# Machina Machine Format Reference (for authors)

The machine JSON format understood by the Machina simulator app (served by the `machina-simulator` extension, schema documented under `copilot-extensions/machina-simulator/simulator/docs/schema-spec.md`). Target spec v3.0.0.

## Contents

1. [Versioning](#versioning)
2. [v3.0.0 field reference](#v300-field-reference-current)
3. [v3.0.0 features in depth](#v300-features-in-depth)
4. [v2.0.0 field reference](#v200-field-reference)
5. [v1.0.0 (legacy — avoid for new machines)](#v100-legacy--avoid-for-new-machines)
6. [Runtime semantics an author must know](#runtime-semantics-an-author-must-know)
7. [Naming conventions](#naming-conventions)

## Versioning

| Field | Meaning | Author guidance |
|---|---|---|
| `version` | The machine's **own** version, free-form string, user-managed | Start at `"1.0.0"`; bump as you evolve the workflow |
| `spec_version` | Which schema-spec contract the machine targets | Always set explicitly to `"3.0.0"` on new machines |

These are independent — never encode the spec target inside `version`.

### Spec version history

| Spec Version | Features |
|---|---|
| v1.0.0 | Basic states, events, transitions |
| v2.0.0 | Guards, actions, scenarios, coverage, cycle_prevention |
| v3.0.0 | Tools, checks[], requires[], ensures[], phase, inputs, limits |

## v3.0.0 field reference (current)

Inherits all v2.0.0 fields, plus:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `tools` | object | optional | Named checker registry: `{ name: { cmd, expect_exit?, timeout_seconds?, output? } }` |
| `state.checks[]` | string[] | optional | Tool references that must pass before any outgoing transition fires |
| `state.invariants[]` | string[] | optional | Tool references that must hold while in the state |
| `transition.requires[]` | string[] | optional | Tool references that must pass in addition to state `checks[]` |
| `transition.ensures[]` | string[] | optional | Tool references validated after the transition fires (post-condition) |
| `transition.else_target` | string | optional | Deterministic redirect when guard fails |
| `transition.description` | string | optional | Human-readable transition description |
| `state.type` | `"phase"` | optional | Nested machine delegation |
| `scenario.inputs` | object | optional | Declared input contract: `{ name: { required?, type? } }` |
| `limits` | object | optional | `{ max_events?, max_steps?, timeout_seconds? }` |

## v3.0.0 features in depth

### Tools registry

Top-level `tools` maps checker names to executable commands.

```json
"tools": {
  "file-exists": {
    "cmd": "python3 scripts/check_file.py {ctx.draft_path}",
    "expect_exit": 0,
    "timeout_seconds": 30
  },
  "validate-output": {
    "cmd": ["python3", "scripts/validate_output.py", "{ctx.output_path}"],
    "expect_exit": 0,
    "output": { "errors": "review.errors" }
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `cmd` | string \| string[] | Command to run. First token with path separator resolved machine-relative. Supports `{ctx.key}` interpolation. |
| `expect_exit` | number | Expected exit code (default `0`) |
| `timeout_seconds` | number | Per-invocation timeout (default `30`) |
| `output` | object | Structured-output mapping: `{ json_key: context_path }` — parses JSON stdout and writes values into context |

### State checks

```json
"drafting": {
  "checks": ["file-exists"],
  "on": { ... }
}
```

State `checks[]` gate **all** exits from that state. Every outgoing transition is blocked until all listed tools pass. If any check fails, the transition does not fire and the machine stays in the current state.

### State invariants

```json
"running": {
  "invariants": ["process-alive"],
  "on": { ... }
}
```

State `invariants[]` are continuously validated while the machine remains in the state. Unlike `checks[]` (which gate exits), invariants assert conditions that must hold at all times — violation is flagged without preventing transitions.

### Transition requires

```json
"DRAFT_COMPLETE": {
  "target": "reviewing",
  "requires": ["validate-output"],
  "ensures": ["output-ready"]
}
```

Transition `requires[]` add edge-specific evidence on top of state `checks[]`. A transition can only fire if both the state checks and the transition requires pass.

### Transition ensures

Transition `ensures[]` are post-conditions validated **after** the transition fires. If any ensure fails, the transition is recorded but flagged — the machine does not roll back, but downstream consumers can observe the flag.

### Phase states

```json
"phase-state": {
  "type": "phase",
  "description": "Delegates to child machine"
}
```

Phase states delegate work to nested machines. When the machine enters a phase state, control transfers to a child machine until it reaches a final state, then control returns to the parent.

### Scenario inputs

```json
"scenarios": [{
  "id": "default",
  "inputs": {
    "draft_path": { "required": true, "type": "string" }
  },
  "initial": "drafting",
  "context": { "draft_path": null }
}]
```

Scenario `inputs` declare required parameters for `init`. This makes the machine's input contract explicit and allows validation before execution begins.

### Limits

```json
"limits": {
  "max_events": 20,
  "max_steps": 10,
  "timeout_seconds": 1800
}
```

Top-level `limits` cap execution to prevent runaway machines. The simulator enforces these and halts with a diagnostic when exceeded.

## v2.0.0 field reference

| Field | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | ✅ (validated) | Stable machine identifier |
| `name` | string | recommended | Human-readable label |
| `version` | string | recommended | Machine's own version |
| `spec_version` | string | recommended | Target schema-spec version (`"2.0.0"`) |
| `initial` | string | ✅ (must resolve) | Default initial state key |
| `context` | object | optional | Initial extended state (default conditions) |
| `scenarios[]` | array | recommended | `{ id, label, initial?, context?, interface? }`, `interface ∈ "UI" \| "API"` |
| `states` | object | ✅ (non-empty) | Keyed by state id: `{ type?, description?, entry?, exit?, on? }` |
| `state.type` | `"atomic" \| "final"` | — | Terminal states are `"final"` |
| `state.description` | string | recommended | Human description of the state |
| `state.entry` / `state.exit` | action[] | optional | Actions fired on entering/leaving the state |
| `state.on` | object | — | Event map: `{ EVENT: { target, guard?, actions?, description? } }` |
| transition.target | string | ✅ (must resolve) | Destination state key |
| transition.guard | guard object | optional | `{ type:"compare", key, op, value }`, `op ∈ eq·neq·lt·lte·gt·gte` |
| transition.actions | action[] | optional | `{ type:"assign", key, value }` or `{ type:"increment", key }` |
| `coverage` | object | optional | Analysis metadata — normally produced by Machina's autofill, not hand-authored |
| `cycle_prevention` | object | optional | `{ max_retry_limit, timeout_seconds, guards[] { event, guard, else_target } }` |

## v1.0.0 (legacy — avoid for new machines)

Subset only: no `scenarios`, no guards/actions (transitions are `{ EVENT: { target } }` only),
no `coverage`/`cycle_prevention`. Only relevant when editing old files.

## Runtime semantics an author must know

- Guards evaluate against `context` via dotted paths; a string guard `value` is first resolved as
  a context-key name, then numeric-coerced. Unknown ops pass silently.
- Firing order per transition: exit actions → transition actions → entry actions.
- A state with **no outgoing transitions** behaves as terminal even without `"type": "final"` —
  but explicit finals score better and read better.
- Blocked guards stop the event ("Guard blocked") — they do not error; design retry flows around
  this.
- Scenario playback follows a path while history matches its prefix; well-chosen scenarios make
  guided playback deterministic.

## Naming conventions

Event names `UPPER_SNAKE` (`PAYMENT_CONFIRMED`). State keys `kebab-case`
(`awaiting-payment`). Both are scored checks (`event-naming`, `state-naming`) — violations land
as `review` gaps requiring manual renames, so get them right up front.
