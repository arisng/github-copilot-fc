---
date: 2026-03-29
type: RFC
severity: High
status: Open for Comment
---

# RFC: Rebuild Ralph-v2 CLI on native Copilot session topology

## Summary
Rebuild the Ralph-v2 CLI variant from scratch so the Copilot CLI session becomes the only session container for a run. Instead of creating and maintaining a parallel `.ralph-sessions/` lifecycle, the CLI runtime should use the Copilot session UUID as its correlation key, store Ralph-v2 session-scoped artifacts under `~/.copilot/session-state/<uuid>/files/`, and inherit the native `/fleet` slash command as its orchestration entry point.

This proposal is intentionally scoped to the CLI runtime. VS Code and other runtimes can continue to use runtime-appropriate storage and orchestration patterns.

## Motivation
The current Ralph-v2 CLI shape duplicates infrastructure that Copilot CLI already provides:

- Session identity is tracked twice.
- Session artifacts are split across two containers.
- Resume and recovery semantics are harder to reason about.
- The fleet coordination substrate (session SQLite todos, `task()` dispatch) is duplicated rather than inherited.
- Debugging has to reconcile Ralph-v2 state with Copilot CLI state.

The session topology research completed in March 2026 established that Copilot CLI already provides the correct substrate for session persistence, auditability, resume, checkpointing, and historical lookup. Continuing to evolve the CLI variant around `.ralph-sessions/` would preserve the wrong abstraction boundary. A rebuild is preferable to incremental patching because the duplicate-session assumption affects the runtime's identity model, artifact layout, lifecycle, and tests.

## Detailed Design

### 1. Runtime identity model
- Use the active Copilot CLI session UUID as the primary run identifier.
- Discover the UUID from the active session context rather than generating a Ralph-specific session ID.
- Treat Ralph-v2 metadata as session-local data attached to that Copilot session, not as the root of a separate session model.

### 2. Artifact placement model
- Store Ralph-v2 session-scoped artifacts under the active session's `files/` directory.
- Reserve the Git working tree for user-facing outputs that are meant to be version-controlled.
- Do not create new `.ralph-sessions/<id>/` directories for CLI runs.

Suggested layout inside `files/`:

```text
~/.copilot/session-state/<uuid>/files/
├── metadata.yaml
├── plan.md
├── progress.md           ← running log: scores, last change, what improved/worsened, next intent
├── scores.jsonl          ← machine-readable per-iteration eval scores (deterministic + LLM-judge)
├── iterations/
│   └── <n>/
│       ├── tasks/
│       ├── reviews/
│       ├── reports/
│       ├── knowledge/
│       └── eval.json     ← structured scores for this iteration (overall + llm-judge)
└── logs/
```

The exact sub-layout can be refined during implementation, but the boundary should remain stable: per-run orchestration state belongs in the active Copilot session workspace.

`progress.md` should record, for each iteration: the current best scores, what changed, what the eval said got better or worse, and what Ralph plans to try next. This makes the session resumable and auditable without reconstructing history from raw logs.

### 3. Lifecycle model
- Remove Ralph-v2 CLI assumptions that it owns session creation, session shutdown, or separate resume semantics.
- Express Ralph-v2 progress through artifacts and events inside the existing Copilot session lifecycle.
- On resume, rediscover Ralph-v2 state from the active Copilot session workspace rather than from a parallel Ralph session folder.

### 4. Fleet Command Inheritance

The `/fleet` slash command in Copilot CLI is not a runtime mode — it is a **prompt injection** into the current session turn. Running `/fleet` sends the fleet system prompt to whatever agent is currently active, promoting it to orchestrator role and handing it the SQL-todos coordination schema. Ralph-v2 is already fleet made explicit: its orchestrator embeds the same parallel-dispatch and iteration pattern as the fleet system prompt, but uses structured markdown task files and `progress.md` instead of SQL todo rows.

The rebuilt CLI variant MUST inherit this native entry point rather than invent a competing one:

- **`/fleet` as the canonical trigger**: When the user invokes `/fleet <task>` while the ralph-v2 orchestrator agent is active, the orchestrator receives the fleet system prompt on top of its own instructions. It has the judgment to translate the fleet coordination schema into structured Ralph-v2 task files, giving the user the richer, review-gated Ralph-v2 workflow through the familiar command they already know.
- **`autopilot_fleet` as the plan-then-execute path**: When `exit_plan_mode` emits `autopilot_fleet`, fleet starts automatically with no user prompt. The rebuild should support this path: the planner agent produces `plan.md`, the user approves (or the orchestrator auto-proceeds), and `autopilot_fleet` triggers parallel dispatch of the iteration's task agents without requiring a manual `/fleet` invocation.
- **Session SQLite todos as the coordination bus**: Fleet writes pending/done/blocked rows via the session SQLite database; Ralph-v2 wraps each of those rows with a richer `iterations/<N>/tasks/<task-id>.md` artifact. In the rebuilt design these two layers are complementary — the SQL row is the lightweight live-status signal, the markdown file is the durable specification and result artifact. Ralph's orchestrator must read the SQL state and keep it consistent with the markdown artifacts.
- **`task()` dispatch is the only subagent mechanism**: Both fleet and ralph-v2 dispatch subagents via the `task()` call. The rebuilt CLI runtime must use `task()` exclusively and must not implement any parallel-execution mechanism outside it. This guarantees that Ralph-v2's subagent dispatch is visible to fleet's coordination machinery and to Copilot CLI's session analytics.
- **No duplicate orchestration prompt**: The ralph-v2 orchestrator already encodes the fleet coordination loop. The rebuilt runtime must guard against injecting the generic fleet system prompt on top of ralph-v2 orchestrator instructions when the orchestrator is already active — doing so would produce conflicting dispatch behavior. The orchestrator's `disable-model-invocation: true` frontmatter enforces this boundary at the dispatch layer.

### 5. Migration and compatibility
- New CLI runs should stop writing fresh state into `.ralph-sessions/`.
- Existing `.ralph-sessions/` data may remain readable during a transition period, but it should be treated as legacy input, not the write target.
- Tests, diagnostics, and documentation should be updated to validate the native Copilot session layout.
- Rebuild the CLI runtime around the new storage contract instead of wrapping the current design with compatibility shims as the primary architecture.

### 6. Eval-Driven Iteration Model

The rebuild is also an opportunity to address a structural weakness in the current Ralph-v2 loop: no machine-readable progress signal. Hard tasks drift because the agent cannot tell whether an iteration improved the outcome. Adopting an **eval-driven improvement loop** as a first-class harness primitive fixes this.

#### 6.1 Define success before the loop starts

Before a Ralph run executes any iteration, it must establish:

- **Deterministic checks**: scripted assertions that can be scored mechanically — build passes, test coverage, constraint violations, schema validity, referenced files exist.
- **LLM-as-judge checks**: rubric-based scores for qualities a script cannot encode — plan coherence, review thoroughness, knowledge document usefulness, output readability.

Each check category produces a numeric score. Both must meet their target threshold before the run is considered complete. The eval composition should be declared in `metadata.yaml` so it is visible to both the orchestrator and any diagnostics tooling.

#### 6.2 Explicit stopping rules

Unbounded "keep improving" loops are a primary source of runaway sessions and wasted context. Replace open-ended iteration with explicit targets:

- **Overall threshold** (deterministic aggregate): e.g., ≥ 90%.
- **LLM-judge threshold**: e.g., ≥ 85% average across rubric dimensions.
- Ralph MUST continue until **both** thresholds are met, not just one.
- If either threshold cannot be met after a configurable maximum iteration count, Ralph escalates to the user with the bottleneck identified in `progress.md` rather than silently looping.

#### 6.3 One-change-per-iteration discipline

Each iteration must:

1. Run the eval on the **current state** — not an assumed baseline.
2. Identify the **single largest failure mode** from the scores and from artifact inspection.
3. Make **one focused change** that addresses that bottleneck.
4. Re-run the eval.
5. Log the delta scores and whether the change helped.
6. Continue or stop based on thresholds.

If multiple things need fixing, queue them — don't batch. Batching makes it impossible to attribute improvements or regressions to a specific change, and degrades the agent's ability to learn mid-session.

#### 6.4 Running log as the session record

`progress.md` is the handoff document. Each iteration entry must record:

- Current best scores (overall + LLM-judge, per dimension).
- What changed in this iteration.
- What the eval said improved or worsened.
- What Ralph intends to do next.

Long-running Ralph sessions become reliable and resumable when `progress.md` is the only state a new Copilot session needs to reconstruct context — instead of replaying the entire event log.

#### 6.5 Artifact inspection, not just log scanning

Score numbers alone are insufficient for complex orchestration tasks. Ralph's orchestrator agent should be able to inspect its own output artifacts directly after each iteration — examine the actual `plan.md`, a reviewer's report, or a generated knowledge document — and compare against the prior best or against the eval rubric. This grounds the next change in observable reality rather than inferred metrics.

This is consistent with the harness engineering principle: **application legibility**. For an agentic pipeline, the "application" being observed is the pipeline's own artifacts.

### 7. Validation strategy
- Validate that Ralph-v2 session artifacts land under the active Copilot session `files/` path, not under `.ralph-sessions/`.
- Validate resume behavior against a reused Copilot session UUID.
- Validate that reviewer, planner, executor, and librarian handoffs work through the shared session workspace.
- Validate that `/fleet <task>` with the ralph-v2 orchestrator active produces structured task files in `iterations/<N>/tasks/` rather than bare SQL todos.
- Validate that SQL todo rows and markdown task files remain consistent after each orchestrator iteration.
- Validate that the `autopilot_fleet` trigger path (plan → approve → execute) produces a complete iteration cycle without manual `/fleet` invocation.
- Validate that `scores.jsonl` is written after each iteration and contains both deterministic and LLM-judge score fields.
- Validate that Ralph halts iteration and produces a bottleneck explanation in `progress.md` when the maximum iteration count is reached without hitting thresholds.
- Validate that `progress.md` contains a machine-readable delta per iteration (scores before, scores after, change description).

## Alternatives Considered
- **Keep `.ralph-sessions/` as the primary CLI state store**: Rejected because it preserves dual sources of truth for identity, artifacts, and lifecycle.
- **Mirror data between `.ralph-sessions/` and the Copilot session workspace**: Rejected because synchronization logic would add failure modes without fixing the architectural duplication.
- **Partially migrate artifacts but keep Ralph-owned session lifecycle**: Rejected because it still leaves Copilot CLI and Ralph-v2 competing to define the same run.
- **Incrementally patch the existing CLI implementation in place**: Rejected as the primary strategy because the current design centers on the wrong session boundary; a clean rebuild reduces hidden coupling and migration debt.

## Unresolved Questions
- [ ] What is the most reliable runtime mechanism for discovering the active Copilot session UUID inside the CLI agent flow?
- [ ] Which current Ralph-v2 artifacts should remain session-scoped versus become durable repository artifacts?
- [ ] How much read-only compatibility with legacy `.ralph-sessions/` data is actually needed for tests and diagnostics?
- [ ] Should the rebuilt CLI runtime preserve the current Ralph iteration directory semantics exactly, or simplify them while moving into `files/`?
- [ ] What is the minimum acceptable migration path for the existing reviewer workflows during the transition from `.ralph-sessions/` to the native Copilot session layout?
- [ ] What is the canonical eval composition for a standard Ralph run? Who owns the LLM-as-judge scoring script — the harness, the skill, or Ralph's orchestrator agent?
- [ ] What numeric thresholds (overall and LLM-judge) should gate Ralph iteration completion, and should they be configurable per task type?
- [ ] How should Ralph's orchestrator surface a "bottleneck explanation" in `progress.md` when it cannot reach the eval threshold within the maximum iteration count?
- [ ] Should `scores.jsonl` be structured for direct consumption by Copilot CLI session analytics, or is it a Ralph-private artifact?
- [ ] At what iteration granularity should artifacts be snapshotted for direct inspection — per iteration, per phase, or on-demand by the orchestrator?
- [ ] When `/fleet <task>` is invoked with the ralph-v2 orchestrator active, how should the orchestrator determine whether to start a new iteration cycle or resume an existing one from `progress.md`?
- [ ] Should the SQL todo rows be the primary task-dispatch signal and markdown task files the durable record, or the other way around?

## References
- Research task: [Reverse engineer Copilot CLI session topology and orchestration layer](../.issues/260320_research-copilot-cli-session-topology-and-orchestration-layer.md)
- Explanation: [Copilot CLI Session Topology and Orchestration Layer](../.docs/explanation/copilot/cli/copilot-cli-session-topology.md)
- Harness design pattern: [OpenAI — Harness Engineering](https://openai.com/index/harness-engineering/) | [Martin Fowler — Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html)
- Eval-driven loop pattern: [OpenAI Codex — Iterate on difficult problems](https://developers.openai.com/codex/use-cases/iterate-on-difficult-problems)
- Fleet internals: [Fleet Mode as Prompt Injection in Copilot CLI](../.docs/explanation/copilot/cli/fleet-mode-as-prompt-injection.md)