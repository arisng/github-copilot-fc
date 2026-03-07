---
category: reference
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-1 task definition"
  - "Iteration 9 task-1 report"
  - "Iteration 9 feedback-driven questions Q-FDB-002"
  - "Iteration 9 session review SC-5"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# Copilot CLI Agent: `infer` Frontmatter Key is Retired

## Status

The `infer` frontmatter key is **officially retired** as of March 2026. Using it in a Copilot CLI custom agent file (`.agent.md`) has no guaranteed effect and will be silently dropped once the CLI stops supporting it.

## Canonical Replacements

| Old key | Meaning | New key |
|---------|---------|---------|
| `infer: false` | Agent is NOT directly invocable by the user | `disable-model-invocation: true` |
| `infer: true` | Agent IS directly invocable by the user | `user-invocable: true` |

## Application Pattern

**Orchestrator agent** (not user-invocable; invoked by the system/workflow only):
```yaml
---
name: my-orchestrator
description: ...
disable-model-invocation: true
tools:
  - ...
---
```

**Subagent** (user-invocable; user can call it directly):
```yaml
---
name: my-subagent
description: ...
user-invocable: true
tools:
  - ...
---
```

## Migration Checklist

When updating existing CLI agent files:
1. Locate `infer:` in YAML frontmatter (typically line 3–5).
2. Replace `infer: false` → `disable-model-invocation: true`.
3. Replace `infer: true` → `user-invocable: true`.
4. Verify with: `Select-String "^infer:" agents/**/*.agent.md` → should return 0 matches.

## Source Reference

Official property names confirmed by the GitHub Copilot custom-agents-configuration reference page (March 2, 2026 version). Both `disable-model-invocation` and `user-invocable` appear in the official schema. `infer` is explicitly documented as "Retired. Use disable-model-invocation and user-invocable instead."
