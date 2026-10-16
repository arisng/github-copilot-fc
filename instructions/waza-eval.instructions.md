---
name: waza-eval
description: 'Waza evaluation harness conventions: file placement, eval.yaml schema, and task authoring for skill quality gates.'
applyTo:
  - '**/eval.yaml'
  - '**/evals/**/*.yaml'
  - '**/skills/**/SKILL.md'
---

# Waza Eval Conventions

This instruction codifies the workspace convention for placing and authoring waza evaluation artifacts. It is the single source of truth — do not duplicate this prose elsewhere.

## File placement (separated convention)

Skills and evals live in **separate top-level directories**:

```
skills/<name>/SKILL.md          ← skill definition (source of truth for behavior)
evals/<name>/eval.yaml          ← eval harness (config, tasks, graders)
evals/<name>/tasks/*.yaml       ← individual task definitions
evals/<name>/trigger_tests.yaml ← positive/negative trigger prompts
```

Evals reference their skill via `skill_directories` in `eval.yaml`:

```yaml
config:
  skill_directories:
    - ../../skills/<name>
```

**Why separated?** The workspace is a multi-skill customization factory. Separating evals from skills keeps authoring folders lean, avoids polluting publishable skill artifacts with test fixtures, and aligns with waza's `waza new skill` scaffold output.

## eval.yaml minimum fields

```yaml
name: <skill-name>-eval
description: Brief description of what this eval covers.
skill: <skill-name>
version: "1.0"
config:
  trials_per_task: 1
  timeout_seconds: 300
  executor: copilot-sdk
  model: <model-id>
  skill_directories:
    - ../../skills/<skill-name>
metrics:
  - name: task_completion
    threshold: 0.8
    weight: 1
tasks:
  - tasks/*.yaml
```

## Task YAML schema (verified against waza v0.38.10)

Required fields: `id`, `name`, `description`, `tags`, `inputs.prompt`, `expected.should_trigger`.

Grader types (valid): `code`, `prompt`, `text`, `file`, `json_schema`, `program`, `behavior`, `action_sequence`, `skill_invocation`, `trigger`, `diff`, `tool_constraint`.

Each grader requires `name` and `config`. Do not use `keyword` or `regex` types — they are not in the schema (verified at v0.38.10; `schemas/task.schema.json` in the waza repo is authoritative).

## Token budget

Default SKILL.md limit is 500 tokens. Override per-repo in `.waza.yaml` with `limits.defaults` (glob map) or `limits.overrides` (exact path suffix):

```yaml
tokens:
  limits:
    defaults:
      "SKILL.md": 4000
    overrides:
      "README.md": 3000
```

Never use `tokens.limits.max` — it is not a schema key and hard-fails every command with `field max not found in type projectconfig.TokenLimitsConfig`.

## References

- [waza eval format](../skills/waza-cli/references/waza-eval-format.md) — eval.yaml shape, 12 grader types, token budgets
- [waza commands](../skills/waza-cli/references/waza-commands.md) — CLI flags and subcommands
- [waza CI patterns](../skills/waza-cli/references/waza-ci.md) — gating patterns (workspace CI wiring deferred)
