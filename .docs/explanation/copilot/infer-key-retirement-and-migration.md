---
category: explanation
source_session: 260302-001737
source_iteration: 4
source_artifacts:
  - "Iteration 4 feedback-driven questions"
  - "Iteration 4 task-1"
  - "Iteration 4 task-1 report"
extracted_at: 2026-03-02T16:12:52+07:00
promoted: true
promoted_at: 2026-03-02T16:21:15+07:00
---

# The `infer` Key Retirement: Rationale and Migration

## Background

Early versions of the GitHub Copilot CLI custom agents specification included an `infer` frontmatter property that controlled how the CLI's multi-agent model handled delegation. Before the property was retired, two patterns emerged:

- `infer: false` on the "entry" agent (orchestrator) — intended to prevent the model from auto-selecting it as a sub-delegation target
- `infer: true` on subagents — intended to mark them as available for model-driven auto-delegation

Both patterns were based on pre-GA documentation and have been superseded.

---

## Why `infer` Was Retired

The `infer` property was a single boolean trying to express two orthogonal access-control axes simultaneously:

1. **Can the model automatically select this agent?** (automatic invocation)
2. **Can users explicitly invoke this agent?** (user invocation)

A single boolean cannot cleanly express all four combinations of these two axes. The GA specification replaced `infer` with two explicit properties:

| Property | Controls |
|----------|----------|
| `disable-model-invocation` | Whether the model can automatically select this agent |
| `user-invocable` | Whether users can manually invoke this agent via `/agent` or `--agent=` |

---

## Behavioral Model

```
                    user-invocable: true    user-invocable: false
                    (default)
disable-model-
invocation: false   ┌─────────────────────┬────────────────────────┐
(default)           │ Normal subagent:     │ Internal-only agent:   │
                    │ model can auto-pick, │ model can auto-pick,   │
                    │ user can invoke      │ user CANNOT invoke     │
                    ├─────────────────────┼────────────────────────┤
disable-model-
invocation: true    │ Entry/Orchestrator:  │ Programmatic-only:     │
                    │ model CANNOT auto-   │ neither model nor user │
                    │ pick, user CAN       │ can invoke directly    │
                    │ invoke manually      │                        │
                    └─────────────────────┴────────────────────────┘
```

The most important cell is **bottom-left**: this is the pattern for orchestrator/entry agents. The user explicitly starts the workflow via `copilot --agent=my-orchestrator`; the model cannot accidentally route to it during subagent resolution.

---

## Pre-GA → GA Migration Mapping

| Pre-GA frontmatter | GA frontmatter | Notes |
|--------------------|---------------|-------|
| `infer: false` | `disable-model-invocation: true` | Orchestrators only |
| `infer: true` | *(omit key entirely)* | Subagents — default behavior is `disable-model-invocation: false` |
| *(no `infer`)* | *(no change needed)* | Already correct for subagents |

**`infer: true` → omit entirely** (not `disable-model-invocation: false`)  
The explicit `false` value is redundant since `false` is the default. Clean files omit the key when using the default.

---

## Common Mistake: Conflating `disable-model-invocation` with `user-invocable`

These two properties control different invocation axes and are easy to confuse:

| Property | What it blocks | Who is blocked |
|----------|---------------|----------------|
| `disable-model-invocation: true` | Automatic model selection | The model |
| `user-invocable: false` | Manual user invocation | The user |

**Wrong pattern (orchestrators):**
```yaml
user-invocable: false  # ❌ This prevents users from starting the agent manually
```

**Correct pattern (orchestrators):**
```yaml
disable-model-invocation: true  # ✅ Prevents model auto-routing; user can still invoke
```

Use `user-invocable: false` only for agents that should never be invoked directly by any user — typically internal pipeline steps that only make sense when called programmatically via another agent.
