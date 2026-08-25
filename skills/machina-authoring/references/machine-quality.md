# Machine Quality Reference (author's guide to compliance scoring)

What the Machina compliance checker demands, from the author's side. 17 checks, weights summing
to exactly 100; score = earned/total ×100, capped at 100. Grades: **90+ Excellent · 80–89
Good · 70–79 Fair · <70 Needs work**.

## Contents

1. [Check-by-check author guidance](#check-by-check-author-guidance)
2. [Auto vs review gaps](#auto-vs-review-gaps)
3. [Pre-flight checklist](#pre-flight-checklist)

## Check-by-check author guidance

### Identity & metadata (15 pts)

| Check | Wt | How to pass |
|---|---|---|
| `id-present` | 5 | Stable kebab-case `id`. **Blocking** — machine won't score without it |
| `name-present` | 5 | Human-readable `name` |
| `version-present` | 5 | Set `"version": "1.0.0"` yourself |
| `spec-version` | 0 | Declare `"spec_version": "2.0.0"` — informational today, but future-proof |

### Structure & integrity (25 pts) — all blocking, all hand-fixable only

| Check | Wt | How to pass |
|---|---|---|
| `states-present` | 10 | Non-empty `states` object |
| `initial-resolves` | 10 | `initial` names an existing state key |
| `targets-resolve` | 5 | Every transition `target` names an existing state key |

These fail validation before simulation — fix them first when a machine misbehaves.

### State quality (20 pts)

| Check | Wt | How to pass |
|---|---|---|
| `state-descriptions` | 8 | A real `description` on every state. Autofill writes placeholders (`generated:true`) — replace them with genuine text |
| `finals-typed` | 6 | Every terminal state gets `"type": "final"`, not just zero outgoing edges |
| `actions-used` | 6 | Use declarative actions where the workflow mutates context. Review-only: the scorer will not invent transitions/actions for you |

### Conventions (10 pts)

| Check | Wt | How to pass |
|---|---|---|
| `event-naming` | 5 | All events `UPPER_SNAKE` |
| `state-naming` | 5 | All state keys `kebab-case` |

Renames are destructive and never auto-applied — fix naming while authoring, not after.

### Topology & reachability (20 pts)

| Check | Wt | How to pass |
|---|---|---|
| `all-reachable` | 8 | Every state reachable from `initial` via BFS — delete or wire up orphans |
| `terminal-reachable` | 6 | At least one final state is reachable — every workflow needs an end |
| `entry-points` | 6 | ≥1 declared in `scenarios[]` with explicit `initial` |

### Safety (5 pts)

`cycle-guards` (wt 5): any loop-capable path must be guarded by a compare against a genuine
`retry`/`attempt` context counter. The scorer only recognizes this exact pattern; it will not
invent counters for you.

```json
"context": { "attempts": 0 }
// looping transition:
{ "target": "pending",
  "guard": { "type": "compare", "key": "attempts", "op": "lt", "value": 3 },
  "actions": [{ "type": "increment", "key": "attempts" }] }
```

Optionally add a `cycle_prevention` block documenting limits (`max_retry_limit`,
`timeout_seconds`, guards with `else_target` at a final state).

### Coverage metadata (5 pts)

`coverage-present` (wt 5): normally filled by Machina's "Generate missing" — don't hand-author;
run autofill after your structure is final.

## Auto vs review gaps

After running Compliance:

- **`auto`** gaps are deterministically fillable via the "Generate missing" diff-preview:
  missing `spec_version`/`version`, derived scenarios, computed coverage, cycle guards (only if a
  retry counter exists), placeholder descriptions, implicit finals.
- **`review`** gaps always need you: missing `id`, missing/renamed transitions, convention
  renames, unreachable states, `name`, `actions-used`.

Strategy: author so that *review* gaps never appear; use *auto* fill as a convenience, not a plan.

## Pre-flight checklist

- [ ] `id`, `name`, `version`, `spec_version: "2.0.0"` present
- [ ] `initial` resolves; all transition targets resolve
- [ ] Every state has a real description
- [ ] Terminals explicitly `"type": "final"`
- [ ] Events UPPER_SNAKE, states kebab-case
- [ ] No orphan states; ≥1 reachable final
- [ ] `scenarios[]` declares entry points
- [ ] Loops guarded by retry/attempt counters
- [ ] Compliance run → ≥90, remaining findings understood
