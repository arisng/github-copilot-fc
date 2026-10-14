---
name: agentic-workflow-benchmark
description: Benchmark the efficiency of an agent skill's execution episode in a Copilot session against four goals - minimize LLM token usage, minimize execution time, minimize semantic (model-judgment) steps, and maximize deterministic (script/code-executed) steps - by parsing the session's local events.jsonl telemetry, then persist a structured report with baseline deltas as a durable artifact for historical analysis and self-improvement. Use AFTER a skill has finished executing in a session, to establish efficiency baselines, compare reruns against a baseline, or diagnose token/time/step hotspots in any agentic workflow executed by an AI agent - software delivery, research, operations, content production, or any other skill-driven run. Do NOT use for judging skill output quality (use skill-eval), for general session inspection, or when the session has no events.jsonl telemetry.
metadata:
  version: 0.2.3
---

# Agentic Workflow Benchmark

Benchmark one skill-execution episode from a Copilot session's local telemetry.
Goals, metric definitions, and classification rules live in `references/` — load them
only as needed.

> **Terminology**: an **episode** is one execution run of the target skill — a
> time-window *slice* of the session's `events.jsonl` transcript, from the skill's
> invocation to the next external skill invocation (or session end). One session
> can contain many episodes. `--mode session` measures the whole transcript
> instead (everything before this benchmark's own activation).

## Workflow

1. **Identify target skill and session.** Determine the skill name that executed
   (repo-level in `skills/<name>/` or `.github/skills/<name>/`, or user-level/published). Locate the session dir:
   the current session (`$env:COPILOT_HOME` or `~/.copilot` + `session-state/<uuid>`),
   or scan `session-state/*/workspace.yaml` for `repository`/`git_root` matching the
   current repo (most recently modified first). Do NOT use the `sessions` SQLite
   catalog for discovery — it can be days stale.

2. **Pre-flight telemetry check.** Confirm `events.jsonl` exists in the session dir
   and contains a `skill.invoked` **event type** whose `data.name` equals the target
   skill. Filter on the event `type` field exactly — a substring match on
   `skill.invoked` also catches `skill.invoked_ref` events, whose `data.name` is an
   empty string; those are noise, not evidence of a missing skill. If either check
   is missing, stop and report the specific gap — never silently fall back to the
   stale SQLite catalog.

3. **Run the benchmark.**

   ```powershell
   pwsh -NoProfile -File skills/agentic-workflow-benchmark/scripts/Invoke-AgenticBenchmark.ps1 `
     -SkillName <target-skill> -SessionDir <session-dir>
   ```

   The orchestrator resolves the report location (target skill's `benchmarks/` folder
   when repo-level — `skills/<skill>/` or `.github/skills/<skill>/` —, `benchmarks/<skill>/` at repo root when user-level; override with
   `-OutDir`), runs `scripts/compute_metrics.py`, and writes:
   - `YYYYMMDD-HHMMSS-episodeN-report.md` — structured report
   - `latest.json` — machine-readable metrics
   - `baseline.json` — baseline (first run sets it; `-SetBaseline` overwrites)

   Options: `-Episode N` (earlier invocation of the skill), `-Mode episode|session`,
   `-SetBaseline`, `-EventsPath` (direct file), `-OutDir`, `-RepoRoot`.

   **Modes**: `-Mode episode` (default) measures one execution run of the skill.
   `-Mode session` measures everything before the benchmark's own activation —
   the whole-workflow number that survives ambiguous attribution; per-episode
   detail appears as a secondary breakdown table. Session mode writes
   `baseline.session.json` / `latest.session.json` (modes never cross-compare).

4. **Present results.** Show the four-goal scorecard and deltas vs baseline. When a
   metric regressed, name one concrete improvement: raise the deterministic ratio by
   scripting a repeated ad-hoc shell command; cut tokens by trimming context loaded
   per step; cut semantic steps by batching edits.

## Reading the output

- Tokens are primary; cost is informational only (BYOK sessions report 0).
- Active time excludes `ask_user` waits — human idle never penalizes the workflow.
- A high `uncertain` count (usually ad-hoc `powershell` one-liners) is a signal, not
  noise: each one is a candidate for promotion to a repo script.
- `query_read` steps count as decision points — grep/view spam is visible, not free.
- **Degenerate-episode guard**: an episode with ≤ 2 tool steps (or a < 2 min window
  while the session holds far more work) is flagged in the report's Caveats and
  refuses to write `baseline.json` — a skill-load measurement must never silently
  become the baseline. Pass `-SetBaseline` to force, or use `-Mode session`.
- **Skill-chain & subagent attribution**: loads of driver/helper skills named by the
  target's `SKILL.md` (or its `machina:` contract) and skill loads inside subagent
  windows do not terminate the episode — they appear in the report's Boundaries
  table with their own sub-window totals.
- Classification rules and the tool-name alias map: `references/classification.md`.
- Metric formulas and episode attribution (self-exclusion, timestamp windows):
  `references/metrics.md`. Event shapes: `references/event-schema.md`.

## Edge cases

- **Multiple invocations**: default is the most recent episode; use `-Episode N`.
- **Meta/driver skills belong to their owner**: when a driver skill (e.g.
  `machina-driving`) is chain-merged into a declaring orchestrator's episode, its
  cost is already owned by that orchestrator's scorecard (shown as a boundary row).
  Do NOT establish a standalone baseline for a shared driver — it would double-count
  and mix callers (several orchestrators can declare the same driver). Benchmark a
  driver directly only when the session drove the workflow with no orchestrator
  involved (e.g. a direct human-conductor run).
- **Sub-agent (`task`) work**: included in totals and broken out in `sub_agent_tokens`.
- **Benchmark self-contamination**: excluded automatically — the episode ends at the
  benchmark's own activation (hard stop, even across skill chains).
- **No/old telemetry**: pre-flight fails with a named gap; the engine still writes a
  `*-cannot-benchmark.md` stub (exit code 3) so the failure itself is a durable record.
