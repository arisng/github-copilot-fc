# Waza Eval Format

Reference for `eval.yaml`, `trigger_tests.yaml`, and task YAML as of waza v0.38.10 (Oct 2026). Authoritative schemas: `schemas/eval.schema.json` and `schemas/task.schema.json` in the waza repo; workspace convention: `instructions/waza-eval.instructions.md` (single source of truth for task authoring).

## eval.yaml

```yaml
name: my-skill-eval            # schemaVersion is optional (defaults to current: 1.4)
description: Behavioral evaluation for my skill.
skill: my-skill
version: "1.0"
config:
  trials_per_task: 3        # higher = less flaky, more cost
  timeout_seconds: 300
  parallel: false
  executor: copilot-sdk     # or mock for offline dry-runs
  model: claude-sonnet-4.6
  skill_directories:        # separated skills/ + evals/ layout (this workspace)
    - ../../skills/my-skill
metrics:
  - name: task_completion
    weight: 0.4
    threshold: 0.8
    description: Overall completion quality target.
  - name: trigger_accuracy
    weight: 0.3
    threshold: 0.9
  - name: behavior_quality
    weight: 0.3
    threshold: 0.7
tasks:
  - "tasks/*.yaml"          # or tasks_from: <path/glob>
graders:                    # optional global graders apply to all tasks
  - name: output-shape      # each grader: name + type + config (see grader types)
    type: text
    config: {}
```

Other supported top-level blocks (same schema): `hooks`, `inputs`, `range`, plus `mcp_mocks` (requires schemaVersion ≥1.1) and `command_mocks` (≥1.3, executor `copilot-sdk`).

## trigger_tests.yaml

```yaml
should_trigger_prompts:
  - prompt: "Explain recursion in Python"
    reason: Core use case
    confidence: high
should_not_trigger_prompts:
  - prompt: "Fix this compile error"
    reason: Unrelated to skill scope
    confidence: high
```

## Task YAML

Task authoring (required fields `id`, `name`, `description`, `tags`, `inputs`, `expected`) and grader config shapes are codified in `instructions/waza-eval.instructions.md` — the workspace single source of truth — and validated against `schemas/task.schema.json`.

Example shape (see the instruction file for the full schema):

```yaml
id: explain-recursion
name: Explain recursion
description: Skill explains recursion with a code example.
tags: [behavioral]
inputs:
  prompt: "Explain recursion in Python"
  context: ""
  files: []
expected:
  should_trigger: true
```

## Grader types (12)

Verified against `schemas/task.schema.json` at waza v0.38.10 — YAML `type:` identifiers are snake_case:

`code`, `text`, `file`, `diff`, `behavior`, `action_sequence`, `skill_invocation`, `tool_constraint`, `trigger`, `prompt`, `json_schema`, `program`.

Config enums (same schema):

- `code` → `language: python | javascript`
- `action_sequence` → `matching_mode: exact_match | in_order_match | any_order_match`
- `skill_invocation` → `mode: exact_match | in_order | any_order`
- `trigger` → `mode: positive | negative`
- `prompt` → `mode: independent | pairwise`, `reasoning_effort: low | medium | high | xhigh | max`

Do **not** use `regex` or `keyword` as `type:` values — they are not in the schema (use `text`, `code`, or `json_schema` instead). Graders can also be remote references (`graders[].ref`, resolved by `waza get` into a pinned `waza.lock`).

Mark a task `golden: true` to make `waza gate` fail the build if it regresses.

## Rubrics library

waza's repo ships ready-made LLM-judge rubrics under `examples/rubrics/`: intent_resolution, response_completeness, task_adherence, task_completion, tool_call_accuracy, tool_input_accuracy, tool_output_utilization, tool_selection. Paths move between releases — check the pinned version.

## Token budget override

waza's default SKILL.md token budget is 500 (hard limit reported by `waza check`). Configure per-repo in `.waza.yaml` using `tokens.limits.defaults` (glob → limit map; most specific pattern wins) and optional `tokens.limits.overrides` (exact-path suffix match). **Never use a bare `tokens.limits.max` key** — it is not in the schema; on waza 0.38.10 it hard-fails commands with `field max not found in type projectconfig.TokenLimitsConfig` (older releases ignored it silently):

```yaml
tokens:
  warningThreshold: 2500   # soft warning threshold (optional)
  fallbackLimit: 1000      # limit for files matching no pattern (optional)
  limits:
    defaults:
      "SKILL.md": 4000
      "references/**/*.md": 1000
      "*.md": 2000
    overrides:
      "README.md": 3000
```
