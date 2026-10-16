# Metrics Definitions

Four goals, each mapped to a primary metric with a fixed trend direction.
All values are computed per episode (see attribution rules below) and rendered into
the dated report's scorecard (values only — no baseline tracking).

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
  comparison is meaningless for them.

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

1. **Mechanical window**: an episode starts at the target `skill.invoked` timestamp.
2. **Chain/subagent-aware end** (v0.2+): the episode ends at the first subsequent
   `skill.invoked` that is *external and unchained*:
   - **Skill-chain merge**: a following invoke is absorbed (not a boundary) when the
     target's `SKILL.md` declares a `machina:` block and the follower is
     `machina-driving` (declarative contract), or when the follower is invoked within
     120 s of the previous chain event and some chain member's SKILL.md names it
     (fallback heuristic). Chain texts come from the invoke event's `content` field
     plus the on-disk SKILL.md (for frontmatter) when readable.
   - **Subagent-internal loads**: a `skill.invoked` inside a
     `subagent.started → subagent.completed` window is the subagent's own skill
     load; it does not end the orchestrator's episode.
   - **Hard stops**: this audit's own activation (`SELF_SKILLS`) and any
     re-invocation of the target skill always terminate the episode, regardless of
     chain or subagent state.
   - Absorbed loads appear in `episode.boundaries[]` (`{skill, timestamp, subagent,
     tokens, tool_steps}`) with their own sub-window totals — a merged load is
     reported, never silently hidden.
   - **Ownership rule**: a chain-merged meta/driver skill's cost belongs to the
     *owner orchestrator's* scorecard, not to an audit of the driver itself.
     Drivers are shared across orchestrators, so a standalone driver audit would
     aggregate unrelated callers and double-count work already owned by each
     orchestrator's episode. Audit a driver directly only when it ran with no
     declaring orchestrator in the session.
   - Older sessions without `subagent.*` events degrade to pure chain logic.
3. Default episode = the **most recent** invocation; pass `--episode N` for earlier ones
   when a skill ran multiple times in one session.
4. **Self-exclusion**: this audit skill runs in the same session. Because the episode
   ends at the audit's own activation (hard stop), the audit's own LLM calls and
   tools are always excluded — including when a skill chain would otherwise absorb it.
5. `invokedAtTurn` is undefined in older sessions — never use turn indices; timestamp
   windows are the only reliable boundary mechanism (see `event-schema.md`).

## Session-aggregate mode (`--mode session`)

Measures **everything before this audit's own activation** — the whole-workflow
number that survives ambiguous attribution. Use it when the target is an orchestrator
skill, or whenever the per-episode table looks suspiciously small relative to the
session's total activity.

- Window: `[first event → most recent audit activation]` (offline re-runs against
  an events file where the audit never ran fall back to end-of-events).
- The four-goal scorecard reports the aggregate; the per-episode mechanical table is a
  secondary `episode_breakdown[]` (skill, window, tokens, tool steps).
- Modes are **report-separated**: session mode writes `…-session-report.md`; episode
  mode writes `…-episodeN-report.md`. The two modes answer different questions and must
  never cross-compare.

## Degenerate-episode guard

An episode is **degenerate** when it has ≤ 2 tool steps, or a window < 2 min while the
session holds > 50 tool steps outside it — i.e. it measures a skill *load*, not a
workflow. Degenerate episodes:

- carry a prominent Caveats entry at the top of the report,
- set `degenerate.is_degenerate`, `degenerate.reasons`, and
  `other_skill_invokes` (other skills invoked in the session) in the metrics payload
  (stdout JSON).

## Durable artifacts

Artifact directory — "telemetry" (repo-level target skill: `skills/<target>/telemetry/` or
`.github/skills/<target>/telemetry/`; user-level: `telemetry/<target>/` at repo root). An
existing legacy `benchmarks/` folder is reused (with a warning) until renamed.

**The dated report is the only persisted artifact:**

| File | Role |
|------|------|
| `YYYYMMDD-HHMMSS-episodeN-report.md` | Human-readable report carrying the full metric tables (historical record); session mode writes `…-session-report.md` |

`baseline.json` / `latest.json` are **no longer written** (retired 2026-10-16): each report
carries the complete numbers, so cross-run comparison is a report-to-report diff, and
regression gating belongs to waza evals (see the `waza-cli` skill). The engine also echoes
the full metrics object as JSON on stdout for scripted consumption — nothing extra is
persisted.
