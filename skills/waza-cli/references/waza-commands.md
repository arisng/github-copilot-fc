# Waza Command Reference

Full command surface as of waza v0.38.10 (Oct 2026; verified against the installed binary). Authoritative source: https://microsoft.github.io/waza/reference/cli/ — the docs site tracks `main` and documents unreleased commands, which are marked ⚠️ below.

## Core evaluation

| Command | Purpose |
|---------|---------|
| `waza check <skill-dir>` | Readiness report: spec compliance, token budget, link validity, advisory checks |
| `waza quality <skill-dir>` | LLM-as-judge score across clarity, completeness, trigger_precision, scope_coverage, anti_patterns (1-5 each). Requires Copilot auth. Flags: `--format table\|json`, `--model` |
| `waza run [eval.yaml \| skill-name]` | Behavioral eval with real agent execution |
| `waza grade` | Run graders against stored results without re-executing |
| `waza compare` | Compare multiple results.json files |
| `waza gate` | CI regression gate with stable exit codes |
| `waza coverage` | Eval coverage grid — which skills have evals |
| `waza spec verify` | Eval coverage against SKILL.md requirements |
| `waza adversarial` | Offline adversarial / fault-injection packs |
| `waza registry search\|add` | Discover / add shared eval registry artifacts |
| `waza get` | Resolve remote grader refs and update `waza.lock` |
| `waza migrate` | Migrate a schema artifact to the current version |
| ⚠️ `waza preflight <eval.yaml>` | Offline, agent-free eval inspection — *docs/main only, not in 0.38.10* |

## Authoring and scaffolding

| Command | Purpose |
|---------|---------|
| `waza init [dir]` | Scaffold project (skills/, evals/, CI workflow); idempotent, never overwrites |
| `waza new skill\|eval\|task` | Create a skill, scaffold an eval suite from an existing SKILL.md, or generate tasks |
| `waza suggest` | Suggest eval files for a skill (experimental) |
| `waza dev` | Interactive frontmatter compliance improvement |
| `waza migrate` | Migrate eval spec to current schema version |
| ⚠️ `waza new eval <name> --scenario` | Scenario scaffold with `--template repository\|cli\|mcp` — *docs/main only, not in 0.38.10* |

## Key `waza run` flags

- `--baseline` — A/B: run with-skill vs without-skill and diff outcomes
- `--model` (repeatable) — override execution model; run multi-model comparison
- `--judge-model` — separate model for prompt/LLM graders
- `--trials N` — override `trials_per_task` for flakiness control
- `--reporter junit:path.xml` — JUnit output for CI (repeatable)
- `--strict` — with `--discover`, fail if any SKILL.md lacks eval.yaml
- `--snapshot <dir>` / `waza replay` — capture/replay for determinism
- `--otel-exporter otlp\|stdout\|file` — OpenTelemetry tracing (payloads redacted by default)
- `--redact <policy.yaml>` — custom redaction for snapshot capture
- `--parallel --workers N` — concurrent task execution
- `--tags` / `--task` — glob filters to subset tasks
- `--suggest` — heuristic improvement suggestions from outcomes
- `--interpret` — plain-language results interpretation

## `waza gate` exit codes

| Code | Meaning |
|------|---------|
| 0 | Pass — all gates satisfied |
| 1 | Regression — pass rate dropped beyond `--max-regression-pct` or task-set policy tripped |
| 2 | Golden failure — a `golden: true` task failed |
| 3 | Configuration error |

Flags: `--baseline`, `--current`, `--max-regression-pct N`, `--format github-actions`.

## Other commands

`session` (session logs), `serve` (HTTP dashboard / JSON-RPC), `results` / `cache` (storage), `models`, `update` (self-update to the latest release), `completion`, `help`.

## Update path

Install or update with the release binary (`install.ps1` on Windows, `install.sh` on macOS/Linux) or `go install github.com/microsoft/waza@latest`; in-place: `waza update [--yes]`. The built-in background version check prints an update notice automatically.
