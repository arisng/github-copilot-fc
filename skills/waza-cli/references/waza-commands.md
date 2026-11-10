# Waza Command Reference

Full command surface as of waza v0.40.1 (Nov 2026; verified against the released tag `v0.40.1` and the published CLI reference). Authoritative source: https://microsoft.github.io/waza/reference/cli/ — the docs site tracks `main`, so capabilities newer than your installed release carry their intro version (v0.39.0 / v0.40.0) below; main-only items are marked ⚠️.

## Core evaluation

| Command | Purpose |
|---------|---------|
| `waza check <skill-dir>` | Readiness report: spec compliance, token budget, link validity, advisory checks |
| `waza quality <skill-dir>` | LLM-as-judge score across clarity, completeness, trigger_precision, scope_coverage, anti_patterns (1-5 each). Requires Copilot auth. Flags: `--format table\|json`, `--model`, `--rubric` (reserved) |
| `waza run [eval.yaml \| skill-name \| agent-name]` | Behavioral eval with real agent execution (also discovers `.agent.md` custom agents) |
| `waza grade` | Run graders against stored results without re-executing |
| `waza compare` | Compare multiple results.json files (plus `compare-plan` / `compare-collect` / `compare-assurance-plan`, see Controlled comparisons) |
| `waza gate` | CI regression gate with stable exit codes |
| `waza coverage` | Eval coverage grid — which skills have evals (skills **and** `.agent.md` agents) |
| `waza spec verify` | Eval coverage against SKILL.md requirements |
| `waza adversarial` | Adversarial / fault-injection packs; every pack task is `golden: true`, unsafe outcome → exit 2 |
| `waza preflight <eval.yaml>` | (v0.39.0) Offline, agent-free eval inventory + prerequisite/grader-ref check. Exits: 1 invalid config, 2 usage error; unresolved prerequisites warn (exit 0) unless `--strict` → 1 |
| `waza assure <eval.yaml>` | (v0.39.0) Challenge native file/output graders against evaluator-only reference labels without running agents; exit 1 unless strict assessment passes. `waza assure calibrate` is separate and requires `--accept-paid-calls` (Unix-only `--output`) |
| `waza registry search\|add` | Discover / add shared eval registry artifacts (remote program graders need `--allow-exec`) |
| `waza get` | Resolve remote grader refs and update `waza.lock` (runs are strict: lock + cache required) |
| `waza migrate` | Check/migrate a schema artifact (eval input/reader default 1.4; results writer 1.7 in v0.39.1, 1.8 in v0.40.x, 1.9 on main) |

## Authoring and scaffolding

| Command | Purpose |
|---------|---------|
| `waza init [dir]` | Scaffold project (skills/, evals/, CI workflow); idempotent, never overwrites |
| `waza new skill\|eval\|task` | Create a skill, scaffold an eval suite from an existing SKILL.md, or generate tasks (`new task from-prompt` records a live prompt run) |
| `waza new eval <name> --scenario` | (v0.39.0) Scenario scaffold without a required skill; `--template repository\|cli\|mcp`. Requires exact eval schema `2.0`, disables ambient skills unless opted in, bypasses result caching |
| `waza suggest` | Suggest eval files for a skill; `--focus negative-triggers\|edge-fixtures\|…`, `--count N`, `--apply` (merge-safe, `--force` to overwrite) |
| `waza dev` | Interactive frontmatter compliance improvement; single target may be a skill name, directory, or `SKILL.md` file (v0.39.1 fix) |
| `waza migrate` | Migrate eval spec to the current schema version |

## Runner and interoperability (v0.40.0)

| Command | Purpose |
|---------|---------|
| `waza runner capabilities\|negotiate\|validate\|run` | Exact-work-unit runner protocol: inspect capabilities, negotiate (exit 5 incompatible / 6 invalid request), validate a captured request offline, run one text attempt (mock offline; Copilot/text needs explicit model + `allow_paid_execution: true`, tools/skills denied). Run exits: 0 ok, 1 failed checks, 2 infra, 3 cancel, 4 timeout, 5 incompatible, 6 invalid |
| `waza run --runner-compat` | Route one inline mock/text suite through runner 1.0 while keeping local result JSON/exits; unsupported mappings fail |
| `waza interop import\|export` | Convert one pinned AgentV `contains` assertion ↔ one native grader; whole-suite imports unsupported |

## Controlled comparisons (v0.39.0, opt-in)

`waza compare-plan` → `compare-collect` → `compare`/`gate --release-policy --collection-dir` implement source-bound release policies with paired collection and separate assurance contracts. Default collector is **offline mock**; `--collector native-copilot` is explicit, may incur usage, Linux/macOS only for durable collection. Never adopt historical results as fresh evidence; policy metadata alone is not enforcement.

## Key `waza run` flags

- `--baseline` — A/B: run with-skill vs without-skill and diff outcomes
- `--model` (repeatable) — override execution model; run multi-model comparison
- `--judge-model` — separate model for prompt/LLM graders
- `--trials N` — override `trials_per_task` for flakiness control
- `--reporter junit:path.xml` — JUnit output for CI (repeatable)
- `--strict` — with `--discover`, fail if any SKILL.md lacks eval.yaml
- `--snapshot <dir>` / `waza replay` — capture/replay for determinism (`replay` exit 0 match, 1 divergence, 2 load/parse error; `--mode live` is unsupported → 2)
- `--otel-exporter otlp\|stdout\|file` — OpenTelemetry tracing (payloads redacted by default)
- `--redact <policy.yaml>` — custom redaction for snapshot capture
- `--parallel --workers N` — concurrent task execution
- `--tags` / `--task` — glob filters to subset tasks
- `--suggest` / `--recommend` — heuristic improvement / multi-model recommendation reports
- `--interpret` — plain-language results interpretation
- `--skip-graders` — execute only; grade later with `waza grade`
- `--session-log` / `--transcript-dir` — NDJSON session events / per-task transcripts
- `--update-snapshots` — refresh `diff` grader snapshots from current output
- `--cache` / `--no-cache` — result caching (keyed by spec, tasks, model, fixtures)

## `waza gate` exit codes

| Code | Meaning |
|------|---------|
| 0 | Pass — all gates satisfied |
| 1 | Regression — pass rate dropped beyond `--max-regression-pct` or task-set policy tripped |
| 2 | Golden failure — a `golden: true` task failed |
| 3 | Configuration error |

Flags: `--baseline`, `--current`, `--max-regression-pct N`, `--golden-must-pass` (default true), `--on-new-tasks allow|warn|fail`, `--on-removed-tasks allow|warn|fail` (default warn), `--format human|json|markdown|github-actions`, plus opt-in `--release-policy`/`--collection-dir`/`--assurance-contract` controlled-policy mode (selected nonpass exits 1, separate from the legacy matrix).

## Other commands

`session` (session logs), `serve` (HTTP dashboard / JSON-RPC; `--lab` opens the experimental evidence dashboard at `/#/lab`, mutually exclusive with `--tcp`), `results` / `cache` (storage), `models`, `update` (self-update to the latest release), `completion`, `help`.

## Update path

Install or update with the release binary (`install.ps1` on Windows, `install.sh` on macOS/Linux) or `go install github.com/microsoft/waza@latest`; in-place: `waza update [--yes]`. The built-in background version check prints an update notice automatically.
