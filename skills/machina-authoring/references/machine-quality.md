# Machine Quality Reference (author's guide to compliance scoring)

What the Machina compliance scorer demands, from the author's side. **24 checks, 22 of them
weighted** — `spec-version` and `tools-exist` are weight-0 informational checks, and the whole `tools`
family is `since 3.0.0`, so a v1/v2 target is graded on 17 checks totalling exactly 100 while
v3.0.0 totals **134**. Score = earned/total ×100, capped at 100. Grades: **90+ Excellent · 80–89
Good · 70–79 Fair · <70 Needs work**.

Rows marked **(v3)** do not apply below `spec_version: "3.0.0"`. Every check is a *finding*, not a
"gap": only the auto-fillable ones appear in the `gaps` command's patch list (see the end of this
file).

## Contents

1. [Check-by-check author guidance](#check-by-check-author-guidance)
2. [Auto vs review findings](#auto-vs-review-findings)
3. [Pre-flight checklist](#pre-flight-checklist)

## Check-by-check author guidance

### Identity & metadata (15 pts)

| Check | Wt | How to pass |
|---|---|---|
| `id-present` | 5 | Stable kebab-case `id`. **Blocking** — machine won't score without it |
| `name-present` | 5 | Human-readable `name` |
| `version-present` | 5 | Set `"version": "1.0.0"` yourself |
| `spec-version` | 0 | Declare `"spec_version": "3.0.0"` yourself. Informational (weight 0 — nothing punishes an omission), but the target you declare decides whether the v3 `tools` checks apply |

### Structure & integrity (25 pts) — all blocking, all hand-fixable only

| Check | Wt | How to pass |
|---|---|---|
| `states-present` | 10 | Non-empty `states` object |
| `initial-resolves` | 10 | `initial` names an existing state key |
| `targets-resolve` | 5 | Every transition `target` names an existing state key |

These fail validation before simulation — fix them first when a machine misbehaves.

### State quality (20 pts · 23 at v3.0.0)

| Check | Wt | How to pass |
|---|---|---|
| `state-descriptions` | 8 | A real `description` on every state. Autofill writes placeholders (`generated:true`) — replace them with genuine text |
| `finals-typed` | 6 | Every terminal state gets `"type": "final"`, not just zero outgoing edges |
| `actions-used` | 6 | Use declarative actions where the workflow mutates context. Review-only: the scorer will not invent transitions/actions for you |
| `phase-states` **(v3)** | 3 | A state typed `"type": "phase"` needs a `description` like any other |

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

### Safety (5 pts · 8 at v3.0.0)

`cycle-guards` (wt 5): any loop-capable path must be guarded by a compare against a genuine
`retry`/`attempt` context counter. The scorer only recognizes this exact pattern; it will not
invent counters for you.

`limits-valid` **(v3)** (wt 3): `limits.max_events`, `max_steps` and `timeout_seconds` must be positive
numbers when present. The simulator enforces them and halts with a diagnostic when one is exceeded.

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

### Tools & execution (25 pts at v3.0.0)

The only family where a machine can score full marks while nothing can independently fail. All four
checks are `since 3.0.0`.

| Check | Wt | How to pass |
|---|---|---|
| `tools-registry` | 5 | A `tools` map of `{name: {cmd, expect_exit?, timeout_seconds?, output?}}`. Absent is fine; **declared but empty is not** |
| `tools-refs` | 5 | Every `checks[]`/`requires[]`/`ensures[]` entry names a registered tool. Zero references passes vacuously — `checkers-used` is the check that cares |
| `checkers-used` | 15 | At least one checker referenced from a state `checks[]` or a transition `requires[]`, with a path-bearing `cmd`, `expect_exit: 0`, and — when the machine file is scored from disk — a script that resolves machine-relative. References from `ensures[]` or `invariants[]` do not count: nothing executes them |
| `tools-exist` | 0 | Informational: per tool, whether a path-bearing `cmd` resolves. Skips pathless commands, and reports without changing the score |

**The whole point of this band is evidence, so author it deliberately rather than to satisfy the
check.** A checker that cannot fail is not evidence: `expect_exit: 1` on a script that always exits 1,
or `cmd: "python3 -c pass"`, would score here and verify nothing. Derive each checker from an
observable fact of the workflow, then prove it fails on a known-bad case —
[checker-scripts.md](checker-scripts.md) has the method and the script contract.

### Scenarios (3 pts at v3.0.0)

`scenario-inputs` **(v3)** (wt 3): each `scenarios[].inputs` entry is an object declaring `required`
(bool) or `type` (string), which is how a machine states its input contract before a run starts.

## Auto vs review findings

After running Compliance:

- **`auto`** findings are deterministically fillable via the "Generate missing" diff-preview: missing
  `spec_version`/`version`, derived scenarios, computed coverage, cycle guards (only if a retry
  counter exists), placeholder descriptions, implicit finals.
- **`review`** findings always need you: missing `id`, missing/renamed transitions, convention
  renames, unreachable states, `name`, `actions-used`, malformed registries, and every
  evidence-related finding (`tools-refs`, `checkers-used`).

Only the `auto` ones appear in the CLI's `gaps` list — `gaps` is a patch list, not a report. Review
findings must be read from `score` output, and `apply` never re-scores, so re-run `score --text` after
patching.

Strategy: author so that *review* findings never appear; use *auto* fill as a convenience, not a plan.

## Pre-flight checklist

- [ ] `id`, `name`, `version`, `spec_version: "3.0.0"` present (the declared target decides whether the v3 checks apply)
- [ ] `initial` resolves; all transition targets resolve
- [ ] Every state has a real description
- [ ] Terminals explicitly `"type": "final"`
- [ ] Events UPPER_SNAKE, states kebab-case
- [ ] No orphan states; ≥1 reachable final
- [ ] `scenarios[]` declares entry points
- [ ] Loops guarded by retry/attempt counters
- [ ] A usable checker: script beside the machine, registered in `tools[]`, referenced from `checks[]` or `requires[]`, invoked by path, `expect_exit: 0`
- [ ] Every `tools[].cmd` path resolves next to the machine (nothing scores this — `tools-exist` is weight 0)
- [ ] Each checker proven to fail on a known-bad case
- [ ] Compliance run → ≥90, remaining findings understood (read them in `score` output, not `gaps`)
