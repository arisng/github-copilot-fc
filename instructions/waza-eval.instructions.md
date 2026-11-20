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

```text
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

## Eval design rules (quality bar)

Authoring rules adopted from the dotnet/skills evaluation quality bar (research synthesis 2026-11-19):

1. **Baseline-delta, not vibes.** Judge each skill as a *delta against the same model with no skill* (arms: baseline / skilled / plugin). A skill passes only when skilled beats baseline; raw quality scores alone prove nothing.
2. **Statistical floor for preference claims.** Use ≥5 distinct stimuli per comparison with an exact one-sided sign test at p≤0.05. Dormancy/routing contracts are exempt from the floor but still need trigger tests.
3. **Golden acceptance + mutation rejection.** Every task's grader must accept a known-good output *and* reject a plausible mutated one — a grader that passes everything is not a grader.
4. **Triage failures in order before editing content:** fixture → spec-load → reliability → power → design → content → routing → cost. Editing skill content first masks upstream causes.
5. **Conformance.** All `evals/*/eval.yaml` are spot-checked against these rules when they change; `evals/standup` (9 tasks) is the reference shape.

## Structural validation (in the gate)

- `waza preflight <eval.yaml>` runs inside `workspace-check.ps1` for every eval: offline, agent-free inventory + prereq/grader-ref checks against waza's **embedded authoritative schema** (`schemas/eval.schema.json` lives in the waza repo — never fork a local copy).
- Workspace-only rules live in `scripts/workspace/validate-manifests.py` (declared metric weights must be *positive numbers* — waza treats weights as relative, so there is no sum-1 contract; `tasks` globs must resolve): things preflight does not cover for *this* repo.
- **Gate classification:** schema/configuration preflight errors FAIL (a corrupt `eval.yaml` must break the gate). `resource.file` errors WARN as *fixture-class debt*: this repo mixes two path conventions — `machina-authoring` tasks resolve bare filenames under waza's default `eval/<name>/fixtures` base, while `machina-driving`/`machina-simulator` declare repo-root-relative paths (`skills/...`) that only resolve with `--context-dir .`. Triage that debt per rule 4 below (fixture class first); do not silently rewrite paths to one convention without checking how the executor materializes workspaces at run time.
- This is structural validation only. **`waza gate` / `waza run` CI execution stays deferred** (2026-10-16 policy).

## CI evaluation lane (design note, wiring deferred)

When execution gating is lifted, adopt the manual-but-bound pattern: a pending commit status on PRs, triggered by a maintainer comment `/evaluate <sha>` bound to a *reviewed* commit; results post as a PR comment plus artifacts; failures include a paste-in "investigate this with your agent" prompt. Never an automatic PR blocker, and never evaluating an unreviewed head.

## References

- [waza eval format](../skills/waza-cli/references/waza-eval-format.md) — eval.yaml shape, 12 grader types, token budgets
- [waza commands](../skills/waza-cli/references/waza-commands.md) — CLI flags and subcommands
- [waza CI patterns](../skills/waza-cli/references/waza-ci.md) — gating patterns (workspace CI wiring deferred)
