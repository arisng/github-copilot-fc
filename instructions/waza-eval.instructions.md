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

## Task YAML schema (waza v0.38.7)

Required fields: `id`, `name`, `description`, `tags`, `inputs.prompt`, `expected.should_trigger`.

Grader types (valid): `code`, `prompt`, `text`, `file`, `json_schema`, `program`, `behavior`, `action_sequence`, `skill_invocation`, `trigger`, `diff`, `tool_constraint`.

Each grader requires `name` and `config`. Do not use `keyword` or `regex` types — they are not in the v0.38.7 schema.

## Token budget

Default SKILL.md limit is 500 tokens. Override per-repo in `.waza.yaml`:

```yaml
tokens:
  limits:
    max: 4000
```

## References

- [waza eval format](../.archived/waza-eval-format.md) — full grader catalog and task schema
- [waza commands](../.archived/waza-commands.md) — CLI flags and subcommands
