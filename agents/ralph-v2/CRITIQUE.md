# Ralph v2 Workflow Critique (Revision 5)

**Date**: 2026-02-16  
**Status**: v2.3.0 Design Decisions Review

## Executive Summary

Ralph v2 is structurally sound for single-stream execution and has resolved the prior critical race conditions through the Delegated State pattern. The remaining risks are no longer architectural correctness issues, but operational and governance gaps: lifecycle guardrails, state consistency, and resiliency controls. These are tractable with light-weight guardrails and validation, without altering the core architecture.

**v2.3.0** addresses four feedback areas — Skills Enforcement, COMMIT Mode, Knowledge Session-Scope, and Task Dependency Reasoning — with design decisions that prioritize backward-compatible patterns, reasoning-based flexibility, and conservative enhancements. All changes apply to new sessions only.

**Status Overview:**
- ✅ **Critical Race Conditions**: Resolved via Delegated State Pattern
- ✅ **Task Lifecycle**: Explicit task existence validation is in place
- ✅ **Session Governance**: Dedicated Session Review state confirmed
- ✅ **Operational Guardrails**: Cycle limits, state validation, input hardening added
- ✅ **Resiliency**: Timeout recovery policy, retry backoff, and task splitting added
- ✅ **Orchestrator Purity**: Router-only behavior enforced for content, but State Ownership granted for `metadata.yaml`
- ✅ **Skills Enforcement**: Reasoning-based discovery replaces numeric cap (v2.3.0)
- ✅ **COMMIT Mode**: Separate mode for git atomic commits within REVIEWING_BATCH (v2.3.0)
- ✅ **Knowledge Session-Scope**: Session-scope knowledge with frontmatter-based approval (v2.3.0)
- ✅ **Task Dependency Reasoning**: Enhanced multi-pass dependency analysis in Planner (v2.3.0)

---

## 1. Strengths (Confirmed)

### ✅ Orchestrator-Owned State

The Orchestrator directly updates `metadata.yaml` on state transitions, ensuring atomicity and eliminating sync drift.

### ✅ Single Source of Truth (SSOT)

`progress.md` is the sole progress SSOT; `metadata.yaml` is the sole state SSOT.

### ✅ Structured Feedback Loops

The v2 feedbacks directory layout and REPLANNING state enforce explicit feedback handling.

---

## 2. Remaining Risks (Prioritized)

### 🟡 Medium: State Machine Drift

**Risk**: Schema validation now exists, but malformed manual edits can still cause drift until repair runs.

### 🟡 Medium: Path Injection via Session ID

**Risk**: Basic validation exists, but enforcement relies on orchestrator checks only.

### 🟢 Low: Planning Cycle Exhaustion

**Risk**: Guardrail is in place, but cycles can still be set too high for large sessions.

### 🟢 Low: Metadata Ownership Conflicts

**Risk**: Optimistic locking exists, but requires consistent usage by all writers.

### 🟡 Medium: Partial Failure Handling

**Risk**: Timeout recovery exists, but repeated failures still depend on task splitting effectiveness.

### 🟢 Low: Orchestrator Role Drift

**Risk**: Explicit rules prohibit this, but regressions remain possible without tests.

### 🟢 Low: Multi-Mode Subagent Invocation

**Risk**: Enforcement is documented, but relies on orchestrator compliance.

**Note (v2.3.0)**: COMMIT mode added to Reviewer as a separate invocation within REVIEWING_BATCH, reinforcing the single-mode-per-invocation pattern. Orchestrator compliance remains the enforcement mechanism.

### ✅ Resolved: Dependency Enforcement

**Risk**: Pre-check exists; remaining risk is inconsistent task metadata.

**Resolution (v2.3.0)**: Enhanced with multi-pass dependency reasoning in Planner's TASK_BREAKDOWN mode. Pass 2 now includes explicit sub-steps for shared resource analysis, read-after-write detection, interface/contract dependencies, and ordering constraints. Waves are documented with rationale in plan.md. This is a proactive hardening — no known failures existed; the enhancement is conservative and future-proofs for more complex projects (ref: Q-ASM-006).

---

## 3. Recommendations (Actionable)

### Guardrails and Validation

1. **Add regression tests** for orchestrator routing, single-mode enforcement, and schema validation.
2. **Tighten SESSION_ID validation** to strict regex and enforce in every entry point.
3. **Add a lightweight lint** for `tasks/<id>.md` metadata completeness.

### Resiliency and Recovery

4. **Measure timeout recovery effectiveness** (rate of recovery vs. split). Adjust split thresholds if needed.
5. **Add optional capped exponential backoff** for heavy tasks that repeatedly timeout.

### Consistency and Governance

6. **Add a short governance checklist** for any manual edits to session files.
7. **Document runtime validation expectations** as reviewer-owned, mandatory behavior.

### State Normalization Strategy

8. **Define normalization boundaries**:
	- **Iteration scope (normalize)**: Treat iteration artifacts as SSOT, avoid duplication across iteration files.
	- **Session scope (denormalize)**: Allow aggregated views for reporting and human consumption only.
9. **Add a normalization guide**:
	- Enumerate SSOT files (e.g., `progress.md`, `tasks/<id>.md`, `iterations/<N>/metadata.yaml`).
	- Define derived artifacts (e.g., dashboards, summaries) as read-only, regenerate anytime.
10. **Introduce a lightweight state index**:
	- A generated `iterations/<N>/state.index.json` (or markdown) that summarizes normalized fields without becoming SSOT.
	- Clearly mark as denormalized and non-authoritative.

---

## 4. v2.3.0 Design Decisions

This section documents the key design decisions made in v2.3.0 across four feedback areas, including the rationale behind each choice and alternatives considered.

### 4.1 COMMIT Mode — Sub-step in REVIEWING_BATCH (Not a New State)

**Decision**: COMMIT is implemented as a separate Reviewer mode invocation within the existing REVIEWING_BATCH state, not as a new top-level state in the state machine.

**Rationale**:
- Adding a new top-level state would change the state machine diagram, all state transition validation logic in the Orchestrator, and potentially the Planner's progress schema (ref: Q-ASM-005).
- COMMIT is logically a follow-up to a qualified review verdict — it belongs to the review phase, not a distinct lifecycle phase.
- The Orchestrator invokes Reviewer TASK_REVIEW for each task, then for `[x]` tasks, invokes Reviewer COMMIT mode — all within the same REVIEWING_BATCH state.
- `metadata.yaml` state remains `REVIEWING_BATCH` throughout; no new state transition needed.

**Alternative Considered**: A top-level `COMMITTING` state between REVIEWING_BATCH and SESSION_REVIEW. Rejected because it would require state machine changes with cascading updates across Orchestrator, Planner, and Reviewer.

### 4.2 Knowledge — Frontmatter-Based Approval (Not Directory-Based)

**Decision**: Approved and staged knowledge coexist in the same Diátaxis directory structure (`knowledge/{tutorials,how-to,reference,explanation}/`), differentiated by frontmatter fields (`approved: true/false`, `approved_at`), not by separate directories.

**Rationale**:
- The existing Librarian already places carried-forward and fresh knowledge in the same directories, using frontmatter markers (`carried_from_iteration`) — frontmatter-based differentiation is a natural extension (ref: Q-ASM-003).
- A separate `knowledge/staged/` vs `knowledge/approved/` split would duplicate the Diátaxis structure and complicate promotion workflows.
- `knowledge/index.md` manifest can display both approval statuses for human review.
- Session-scope knowledge persists across iterations: approved knowledge carries forward without re-approval; new knowledge goes through the existing APPROVE signal flow.

**Alternative Considered**: Directory-based separation (`knowledge/staged/` and `knowledge/approved/`). Rejected because it duplicates the Diátaxis taxonomy and makes promotion a file-move operation rather than a metadata update.

### 4.3 Skills — Reasoning-Based Discovery (Not Rule-Based or Manifest-Based)

**Decision**: The `max 3-5 skills per invocation` numeric cap is removed and replaced with a 4-step reasoning process: (1) check agent instructions for skill affinities, (2) check task description for explicitly mentioned skills, (3) scan skills directory and match by description, (4) prioritize skills mentioned in agent instructions or task descriptions.

**Rationale**:
- A numeric cap is arbitrary and context-insensitive — some tasks need zero skills, others need several (ref: Q-CON-002).
- Pre-listing skills in session instructions creates duplication: the Planner discovers skills at planning time, but subagents must re-discover at runtime anyway. Removing pre-listing eliminates this redundancy (ref: Q-ASM-002).
- Agent-specific skill affinities in agent instructions (e.g., Reviewer's `git-atomic-commit`, Librarian's `diataxis`) survive the removal and serve as strong discovery hints.
- The reasoning process naturally self-limits — cognitive dilution from irrelevant skills guides agents to load only 1-3 relevant skills per invocation without a hard cap.

**Alternative Considered**: A manifest file mapping tasks to skills (rule-based). Rejected because it requires upfront knowledge of task-skill mappings and cannot adapt to runtime discoveries. Also considered keeping the numeric cap but increasing it — rejected because any fixed number is arbitrary.

### 4.4 Task Dependencies — Pass 2 Expansion (Not New Passes)

**Decision**: Enhanced dependency reasoning is implemented by expanding Pass 2 of the existing 3-pass TASK_BREAKDOWN with explicit sub-steps, not by adding new passes (Pass 4, Pass 5, etc.).

**Rationale**:
- The current 3-pass approach is adequate; no documented failures exist. The enhancement is proactive hardening for future complexity (ref: Q-ASM-006, source feedback: "not because the current breakdown is not good enough").
- Adding new passes would increase planning latency and complexity without addressing a real failure mode.
- Pass 2 sub-steps (shared resource analysis, read-after-write detection, interface/contract dependencies, ordering constraints) add structured reasoning within the existing framework.
- Waves are now documented in plan.md with rationale for grouping and inter-wave dependencies.

**Alternative Considered**: Adding Pass 4 (cross-validation) and Pass 5 (wave optimization). Rejected as over-engineering for a proactive enhancement with no known failures. The expanded Pass 2 achieves the same reasoning depth with less structural change.

---

## 5. v2.3.0 Known Limitations and Trade-offs

### 5.1 Skills: Reasoning-Based Discovery Edge Cases

**Limitation**: Reasoning-based discovery may load fewer skills than optimal in edge cases where a skill's relevance is not obvious from its name or description alone.

**Trade-off**: Accepted. The alternative (loading all skills) risks context window dilution. Agent-specific affinities in agent instructions serve as a safety net for critical skills (e.g., Reviewer always finds `git-atomic-commit` through its own instructions).

**Mitigation**: Task descriptions from the Orchestrator can explicitly mention required skills, which the reasoning process prioritizes.

### 5.2 COMMIT: Partial Staging Is Best-Effort

**Limitation**: Partial file staging (staging only task-relevant hunks of a file with other unrelated changes) relies on `git diff` analysis and `git apply --cached` for hunk-level staging. This is best-effort — if hunk extraction fails, the conservative fallback stages the entire file.

**Trade-off**: Accepted. Conservative fallback to whole-file staging ensures commits always succeed, at the cost of potentially including unrelated changes in the commit. Commit failure does NOT revert the review verdict.

**Mitigation**: COMMIT mode validates prerequisites (git repo, uncommitted changes) before attempting staging. Retry-once logic in the Orchestrator handles transient failures.

### 5.3 Knowledge: No Concurrent Access Protection

**Limitation**: Session-scope knowledge has no file locking or transactional isolation for concurrent access. Multiple agents could theoretically read/write knowledge files simultaneously.

**Trade-off**: Accepted. The sequential iteration model means only one Librarian invocation runs at a time within a given state (KNOWLEDGE_EXTRACTION). Concurrent access is not a realistic scenario under the current architecture.

**Mitigation**: If multi-agent parallelism is added in the future, file locking or optimistic concurrency (version fields in frontmatter) should be introduced.

### 5.4 Dependencies: Proactive Hardening Without Failure Evidence

**Limitation**: The enhanced dependency reasoning is a proactive improvement without documented evidence of past failures. The additional sub-steps in Pass 2 add reasoning overhead without a measurable baseline improvement.

**Trade-off**: Accepted. The overhead is minimal (sub-steps within an existing pass, not new passes). Future complex projects will benefit from the structured reasoning even if current projects don't expose gaps.

---

## 6. Deferred Capabilities (By Design)

These are acceptable gaps given the current scope, but should be explicit in docs:
- **Rollback Mechanism**: No transaction rollback or revert of partial writes.
- **Advanced Concurrency**: No file locking or transactional isolation across subagents.
- **Deep Observability**: No structured event log for agent decisions and state transitions.
- **Line-Level Staging** (v2.3.0): COMMIT mode stages at hunk level via `git apply --cached`. True line-level staging (individual lines within a hunk) is not supported; conservative fallback to whole-file staging if hunk extraction fails.
- **Concurrent Knowledge Access** (v2.3.0): No file locking for session-scope knowledge. Acceptable under the sequential iteration model. Requires revisiting if multi-agent parallelism is introduced.
- **Skill Manifest/Registry** (v2.3.0): No centralized mapping of tasks to skills. Discovery is reasoning-based and runtime-only. A manifest could improve determinism but at the cost of maintenance overhead.

---

## 7. Validation Checklist (Operational)

Use this before rolling out changes to v2 agents:

1. **State validation** passes for a clean session and a REPLANNING session.
2. **Session ID sanitization** rejects invalid inputs (`../`, spaces, extra dots).
3. **Planning cycle limit** triggers and reports the forced transition.
4. **Dependency pre-check** blocks dependent tasks when prerequisites are not `[x]`.
5. **Timeout recovery** performs 30/60/60 sleeps before task split.
6. **Task split path** creates smaller tasks and cancels the oversized one.
7. **Runtime validation** is performed by Reviewer for every task.
8. **Single-mode enforcement** prevents `UPDATE` + `REBREAKDOWN` in one Planner call.

---

## 8. Conclusion

Ralph v2 is ready for sustained use under its current architectural constraints. The v2.3.0 enhancements address skills enforcement, commit workflow, knowledge management, and dependency reasoning without altering the core architecture. Design decisions prioritize reasoning-based flexibility over rigid rules, conservative enhancements over structural overhauls, and backward-incompatible clarity (new sessions only) over migration complexity. The next step is operational validation of the new capabilities and measurement of their impact on session quality.

---

## 9. Appendix: Normalization Deep Dive

This appendix clarifies how to normalize shared state at iteration scope while allowing denormalized session views for humans.

### 9.1 Summary

- **Normalize iteration scope**: keep SSOT artifacts minimal and canonical per iteration.
- **Denormalize session scope**: allow read-only summaries for human consumption.
- **Enforce boundaries**: SSOT files are authoritative; derived views are disposable.

### 9.2 Detailed Design

See [agents/ralph-v2/appendixes/normalization-deep-dive.md](agents/ralph-v2/appendixes/normalization-deep-dive.md) for the full guidance, boundary rules, and consistency checks.

---

## 10. Appendix: Hooks Integration Summary

This appendix summarizes how GitHub Copilot Hooks can increase determinism in the Ralph v2 workflow.

### 10.1 Targeted Hook Types

- **Session start**: Initialize or validate session structure; record session header for audit.
- **User prompt submitted**: Log prompt for deterministic replay and governance.
- **Pre-tool use**: Enforce guardrails (allowlists, schema checks, single-mode rules).
- **Post-tool use**: Log tool outcomes for metrics and failure detection.
- **Error occurred**: Centralize error telemetry (timeouts, crashes, tool failures).

### 10.2 Determinism Gains

- **State correctness**: Block invalid writes to SSOT files.
- **Replayability**: Stable logs of prompts and tool executions.
- **Scope safety**: Enforce single-mode and single-task invariants.
- **Recovery fidelity**: Measure and enforce timeout recovery behavior.

### 10.3 Detailed Design

See [agents/ralph-v2/appendixes/hooks-integrations.md](agents/ralph-v2/appendixes/hooks-integrations.md) for proposed hook policies, scripts, and governance notes.
