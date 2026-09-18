---
name: waza-cli
description: Drive the waza CLI (microsoft/waza) to evaluate agent skills with real LLM execution, model comparison, and CI regression gating. Use when checking a skill for submission readiness, running behavioral eval suites with LLM graders, comparing models A/B, gating skill regressions in CI, or measuring skill quality with an LLM judge. Do not use for fast static structure audits with zero LLM cost (use skill-eval).
metadata:
  version: 0.1.0
---

# Waza CLI Evaluation

Run [waza](https://github.com/microsoft/waza) commands against a skill dir. Install: `go install github.com/microsoft/waza@latest`.

USE FOR: check my skill, run my evals, compare models, gate CI regressions, score skill quality. DO NOT USE FOR: first-draft authoring (use skill-creator); offline static audits (use skill-eval).

## Choose the command

| Goal | Command |
|------|---------|
| Readiness, compliance, token budget | `waza check <skill-dir>` |
| LLM-judge quality (5 dimensions) | `waza quality <skill-dir>` |
| Behavioral eval, real execution | `waza run <eval.yaml>` |
| Model A/B comparison | `waza run --baseline` |
| CI regression gate | `waza gate` |
| Determinism check | `waza snapshot` + `waza replay` |

## Quick recipes

```bash
waza check skills/<name>           # offline, no LLM cost
waza tokens suggest skills/<name>

waza run skills/<name>/eval.yaml   # needs Copilot auth
waza run --baseline skills/<name>/eval.yaml

waza gate --baseline baseline.json --current results.json
```

If `waza check` flags the 500-token budget on a large skill, raise `tokens.limits.max` in `.waza.yaml` — see [eval format reference](references/waza-eval-format.md#token-budget-override).

## Decision rule

Run `skill-eval` first for zero-cost structural checks. Escalate to `waza` for real model execution, model comparison, or CI regression gating. Complementary, not replacements.

Read references when needed:
- [Eval format and graders](references/waza-eval-format.md) — authoring eval.yaml, task YAML, trigger tests
- [Full command surface](references/waza-commands.md) — flags/subcommands not covered above
- [CI integration](references/waza-ci.md) — wiring `waza gate`/`waza run` into GitHub Actions
