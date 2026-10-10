---
name: agentic-workflow-benchmark
description: Benchmark the efficiency of an agent skill's execution episode in a Copilot session against four goals - minimize LLM token usage, minimize execution time, minimize semantic (model-judgment) steps, and maximize deterministic (script/code-executed) steps - by parsing the session's local events.jsonl telemetry, then persist a structured report with baseline deltas as a durable artifact for historical analysis and self-improvement. Use AFTER a skill has finished executing in a session, to establish efficiency baselines, compare reruns against a baseline, or diagnose token/time/step hotspots in an agentic shipping workflow. Do NOT use for judging skill output quality (use skill-eval), for general session inspection, or when the session has no events.jsonl telemetry.
metadata:
  version: 0.1.0
---

# Agentic Workflow Benchmark

Benchmark one skill-execution episode from a Copilot session's local telemetry.
Goals, metric definitions, and classification rules live in `references/` — load them
only as needed.

## Workflow

1. **Identify target skill and session.** Determine the skill name that executed
   (repo-level in `skills/<name>/` or user-level/published). Locate the session dir:
   the current session (`$env:COPILOT_HOME` or `~/.copilot` + `session-state/<uuid>`),
   or scan `session-state/*/workspace.yaml` for `repository`/`git_root` matching the
   current repo (most recently modified first). Do NOT use the `sessions` SQLite
   catalog for discovery — it can be days stale.

2. **Pre-flight telemetry check.** Confirm `events.jsonl` exists in the session dir
   and contains a `skill.invoked` event with `data.name` equal to the target skill.
   If either is missing, stop and report the specific gap — never silently fall back
   to the stale SQLite catalog.

3. **Run the benchmark.**

   ```powershell
   pwsh -NoProfile -File skills/agentic-workflow-benchmark/scripts/Invoke-AgenticBenchmark.ps1 `
     -SkillName <target-skill> -SessionDir <session-dir>
   ```

   The orchestrator resolves the report location (target skill's `benchmarks/` folder
   when repo-level, `benchmarks/<skill>/` at repo root when user-level; override with
   `-OutDir`), runs `scripts/compute_metrics.py`, and writes:
   - `YYYYMMDD-HHMMSS-episodeN-report.md` — structured report
   - `latest.json` — machine-readable metrics
   - `baseline.json` — baseline (first run sets it; `-SetBaseline` overwrites)

   Options: `-Episode N` (earlier invocation of the skill), `-SetBaseline`,
   `-EventsPath` (direct file), `-OutDir`, `-RepoRoot`.

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
- Classification rules and the tool-name alias map: `references/classification.md`.
- Metric formulas and episode attribution (self-exclusion, timestamp windows):
  `references/metrics.md`. Event shapes: `references/event-schema.md`.

## Edge cases

- **Multiple invocations**: default is the most recent episode; use `-Episode N`.
- **Sub-agent (`task`) work**: included in totals and broken out in `sub_agent_tokens`.
- **Benchmark self-contamination**: excluded automatically — the episode ends at the
  next `skill.invoked` (the benchmark's own activation).
- **No/old telemetry**: pre-flight fails with a named gap; the engine still writes a
  `*-cannot-benchmark.md` stub (exit code 3) so the failure itself is a durable record.
