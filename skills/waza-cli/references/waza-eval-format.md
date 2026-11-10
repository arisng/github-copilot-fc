# Waza Eval Format

Reference for `eval.yaml`, `trigger_tests.yaml`, and task YAML as of waza v0.40.1 (Nov 2026). Authoritative schemas: `schemas/eval.schema.json` and `schemas/task.schema.json` in the waza repo; workspace convention: `instructions/waza-eval.instructions.md` (single source of truth for task authoring).

## eval.yaml

```yaml
name: my-skill-eval            # schemaVersion is optional (legacy/current default: 1.4; scenario evals require exact "2.0")
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

Other supported top-level blocks (same schema): `hooks`, `inputs`, `range`, plus `mcp_mocks` (requires schemaVersion ≥1.1) and `command_mocks` (≥1.3, executor `copilot-sdk`). A `scenario: <nonblank string>` header (v0.39.0+) requires exact `schemaVersion: "2.0"`; omit the key for a legacy eval. **Task-level `mcp_mocks`** (v0.40.0) replace eval-level mocks by name — keys older versions ignored now take effect, and `before_run` hooks run before task loading, so review existing task files when upgrading.

Results schema (separate artifact): v0.39.1 writers emit **1.7**, v0.40.x emits **1.8**, main emits **1.9**; missing versions in legacy inputs default to **1.4**. `waza migrate <file>` reports/converts.

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

## Grader types (13)

Verified against `schemas/task.schema.json` at waza v0.40.1 — YAML `type:` identifiers are snake_case:

`code`, `text`, `file`, `diff`, `behavior`, `action_sequence`, `skill_invocation`, `tool_constraint`, `tool_calls`, `trigger`, `prompt`, `json_schema`, `program`.

Config enums / shapes (same schema):

- `code` → `language: python | javascript`
- `action_sequence` → `matching_mode: exact_match | in_order_match | any_order_match`
- `skill_invocation` → `mode: exact_match | in_order | any_order`
- `trigger` → `mode: positive | negative`
- `prompt` → `mode: independent | pairwise`, `reasoning_effort: low | medium | high | xhigh | max`; optional `evidence_context` (v0.39.0) selects a frozen judge-evidence bundle for fresh isolated judge sessions
- `tool_calls` (v0.40.0-era) → config needs one of `required_tools`, `forbidden_tools`, `min_calls`, `max_calls`, `expect` (`[{tool, args?}]`)
- `program` → receives grading context JSON (v0.40.0)

Do **not** use `regex` or `keyword` as `type:` values — they are not in the schema (use `text`, `code`, or `json_schema` instead). Graders can also be remote references (`graders[].ref`, resolved by `waza get` into a pinned `waza.lock`).

Mark a task `golden: true` to make `waza gate` fail the build if it regresses.

## Rubrics library

waza's repo ships ready-made LLM-judge rubrics under `examples/rubrics/`: intent_resolution, response_completeness, task_adherence, task_completion, tool_call_accuracy, tool_input_accuracy, tool_output_utilization, tool_selection. Paths move between releases — check the pinned version.

## Token budget override

waza's default SKILL.md token budget is 500 (hard limit reported by `waza check`; `waza tokens check` exits nonzero on strict-budget violation since v0.40.1). Configure per-repo in `.waza.yaml` using `tokens.limits.defaults` (glob → limit map; most specific pattern wins) and optional `tokens.limits.overrides` (exact-path suffix match). The legacy `.token-limits.json` file is deprecated — migrate to `.waza.yaml`. **Never use a bare `tokens.limits.max` key** — it is not in the schema; on waza 0.38.10 it hard-fails commands with `field max not found in type projectconfig.TokenLimitsConfig` (older releases ignored it silently):

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
