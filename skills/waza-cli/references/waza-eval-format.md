# Waza Eval Format

Reference for `eval.yaml`, `trigger_tests.yaml`, and task YAML as of waza v0.38.7. Authoritative source: https://deepwiki.com/microsoft/waza/3.2-eval.yaml-and-task.yaml-evaluation-spec-schemas and https://github.com/microsoft/waza/tree/main/examples/code-explainer.

## eval.yaml

```yaml
schemaVersion: "1.0"
name: my-skill-eval
description: Behavioral evaluation for my skill.
skill: my-skill
version: "1.0"
config:
  trials_per_task: 3        # higher = less flaky, more cost
  timeout_seconds: 300
  parallel: false
  executor: copilot-sdk     # or mock for offline dry-runs
  model: claude-sonnet-4.6
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
graders:                    # global graders apply to all tasks
  - type: regex
    pattern: "..."
tasks: "tasks/*.yaml"       # or tasks_from: path/glob
```

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

```yaml
name: explain-recursion
description: Skill explains recursion with a code example.
inputs:
  prompt: "Explain recursion in Python"
  context: ""
  files: []
expected:
  output_contains:
    - "base case"
  outcomes: []              # assertions on agent behavior
  behavior: []              # tool-call / action expectations
graders:                    # task-specific graders override/extend global
  - type: keyword
    keywords: ["recursion", "base case"]
    weight: 1.0
```

## Grader types (11)

`code`, `regex`, `keyword`, `file`, `diff`, `json-schema`, `prompt` (LLM-as-judge), `behavior`, `action-sequence`, `skill-invocation`, `program`.

Mark a task `golden: true` to make `waza gate` fail the build if it regresses.

## Rubrics library

Ready-made LLM-judge rubrics ship in the repo under `examples/rubrics/`: intent_resolution, response_completeness, task_adherence, task_completion, tool_call_accuracy, tool_input_accuracy, tool_output_utilization, tool_selection.

## Token budget override

waza's default SKILL.md token budget is 500 (hard limit reported by `waza check`). Configure per-repo in `.waza.yaml`:

```yaml
tokens:
  limits:
    max: 1500
```
