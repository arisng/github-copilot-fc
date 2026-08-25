# Machina Machine Format Reference (for authors)

The machine JSON format understood by the Machina simulator app (served by the `machina-simulator` extension, schema documented under `copilot-extensions/machina-simulator/simulator/docs/schema-spec.md`). Target spec v2.0.0.

## Contents

1. [Versioning](#versioning)
2. [v2.0.0 field reference](#v200-field-reference-current)
3. [v1.0.0 (legacy — avoid for new machines)](#v100-legacy--avoid-for-new-machines)
4. [Runtime semantics an author must know](#runtime-semantics-an-author-must-know)
5. [Naming conventions](#naming-conventions)

## Versioning

| Field | Meaning | Author guidance |
|---|---|---|
| `version` | The machine's **own** version, free-form string, user-managed | Start at `"1.0.0"`; bump as you evolve the workflow |
| `spec_version` | Which schema-spec contract the machine targets | Always set explicitly to `"2.0.0"` on new machines |

These are independent — never encode the spec target inside `version`.

## v2.0.0 field reference (current)

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
