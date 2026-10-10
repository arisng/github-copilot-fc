# Metrics Definitions

Four goals, each mapped to a primary metric with a fixed trend direction.
All values are computed per episode (see attribution rules below) and compared
against `baseline.json` (and the previous run) in the report scorecard.

## Goal → metric mapping

| # | Goal | Primary metric | Trend |
|---|------|----------------|-------|
| 1 | Minimize LLM token usage | `tokens.total` (input + output + cache_read + cache_write + reasoning) | lower better |
| 2 | Minimize execution time | `time.active_ms` | lower better |
| 3 | Minimize semantic steps | `steps.semantic` | lower better |
| 4 | Maximize deterministic steps | `ratios.deterministic_ratio` = deterministic / total tool steps | higher better |

## Metric definitions

### Tokens
- Sourced from `session.usage_record` events inside the episode window.
- `tokens.total` sums all five token fields; each is also reported individually.
- Sub-agent usage (`initiator=sub-agent` or `agentId` present) is **included in totals**
  and broken out in `sub_agent_tokens` — sub-agent work is real cost.
- **Cost is informational only**: BYOK sessions report `cost=0`, so cost-based
  benchmarking is meaningless for them.

### Time
- `wall_clock_ms` — episode end − start (raw span).
- `ask_user_wait_ms` — sum of `ask_user` tool durations (human idle time).
- `active_ms` = `wall_clock_ms − ask_user_wait_ms` — the primary time metric;
  human wait must not penalize the workflow.
- `tool_ms` — sum of all tool execution durations.
- `llm_ms` — sum of `usage.duration` across LLM calls.
- `tool_ms + llm_ms` may exceed `active_ms` (parallel tool calls); that concurrency is
  a workflow property, not an error — both raw sums are reported.

### Steps
Counts of `tool.execution_start` events per taxonomy bucket
(see `classification.md`): semantic, deterministic, query_read, workflow_control,
uncertain, plus `total`.

### Efficiency ratios
- `deterministic_ratio` = deterministic / total tool steps.
- `decision_points` = semantic + query_read — how many model judgment/lookup points the
  workflow required; guards against "deterministic inflation" via grep-spam.
- `tokens_per_semantic_step` = tokens.total / semantic (None when semantic = 0).
- `active_ms_per_semantic_step` = active_ms / semantic (None when semantic = 0).

## Episode attribution rules

1. An episode = `[target skill.invoked timestamp → next skill.invoked of any skill | end of events]`.
2. Default episode = the **most recent** invocation; pass `--episode N` for earlier ones
   when a skill ran multiple times in one session.
3. **Self-exclusion**: the benchmark skill runs in the same session. Because the episode
   ends at the next `skill.invoked` (typically this skill's own invocation), the
   benchmark's own LLM calls and tools are automatically excluded. Do not benchmark
   across a boundary that includes the benchmark's own events.
4. `invokedAtTurn` is undefined in older sessions — never use turn indices; timestamp
   windows are the only reliable boundary mechanism (see `event-schema.md`).

## Baseline & durable artifacts

Per-report directory (repo-level target skill: `skills/<target>/benchmarks/`;
user-level: `benchmarks/<target>/` at repo root):

| File | Role |
|------|------|
| `YYYYMMDD-HHMMSS-episodeN-report.md` | Human-readable structured report (historical record) |
| `latest.json` | Machine-readable metrics of the most recent run |
| `baseline.json` | Chosen baseline; first run sets it implicitly, `-SetBaseline` overwrites |

Every report shows deltas vs `baseline.json` (goal direction applied: a negative token
delta is *improved*, a positive deterministic-ratio delta is *improved*).
Historical analysis = diff the dated reports / latest.json snapshots over time.
