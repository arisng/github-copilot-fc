# Ralph v2 Workflow Critique (Revision 4)

**Date**: 2026-02-10  
**Status**: Post-Remediation Review (Guardrail Closure)

## Executive Summary

Ralph v2 is structurally sound for single-stream execution and has resolved the prior critical race conditions through the Delegated State pattern. The remaining risks are no longer architectural correctness issues, but operational and governance gaps: lifecycle guardrails, state consistency, and resiliency controls. These are tractable with light-weight guardrails and validation, without altering the core architecture.

**Status Overview:**
- ✅ **Critical Race Conditions**: Resolved via Delegated State Pattern
- ✅ **Task Lifecycle**: Explicit task existence validation is in place
- ✅ **Session Governance**: Dedicated Session Review state confirmed
- ✅ **Operational Guardrails**: Cycle limits, state validation, input hardening added
- ✅ **Resiliency**: Timeout recovery policy, retry backoff, and task splitting added
- ✅ **Orchestrator Purity**: Router-only behavior enforced with explicit rules

---

## 1. Strengths (Confirmed)

### ✅ Read-Only Orchestrator

The Orchestrator functions as a router and state observer only, preventing double-write contention.

### ✅ Single Source of Truth (SSOT)

`progress.md` is the sole progress state; tasks are isolated in `tasks/<id>.md` files.

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

### 🟢 Low: Dependency Enforcement

**Risk**: Pre-check exists; remaining risk is inconsistent task metadata.

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

## 4. Deferred Capabilities (By Design)

These are acceptable gaps given the current scope, but should be explicit in docs:
- **Rollback Mechanism**: No transaction rollback or revert of partial writes.
- **Advanced Concurrency**: No file locking or transactional isolation across subagents.
- **Deep Observability**: No structured event log for agent decisions and state transitions.

---

## 5. Validation Checklist (Operational)

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

## Conclusion

Ralph v2 is ready for sustained use under its current architectural constraints. The next step is not structural change, but operational guardrails that prevent drift, enforce consistency, and improve recovery ergonomics. With those additions, the system would reach production-grade reliability for single-stream execution.

---

## 6. Appendix: Normalization Deep Dive

This appendix clarifies how to normalize shared state at iteration scope while allowing denormalized session views for humans.

### 6.1 Summary

- **Normalize iteration scope**: keep SSOT artifacts minimal and canonical per iteration.
- **Denormalize session scope**: allow read-only summaries for human consumption.
- **Enforce boundaries**: SSOT files are authoritative; derived views are disposable.

### 6.2 Detailed Design

See [agents/ralph-v2/appendixes/normalization-deep-dive.md](agents/ralph-v2/appendixes/normalization-deep-dive.md) for the full guidance, boundary rules, and consistency checks.

---

## 7. Appendix: Hooks Integration Summary

This appendix summarizes how GitHub Copilot Hooks can increase determinism in the Ralph v2 workflow.

### 7.1 Targeted Hook Types

- **Session start**: Initialize or validate session structure; record session header for audit.
- **User prompt submitted**: Log prompt for deterministic replay and governance.
- **Pre-tool use**: Enforce guardrails (allowlists, schema checks, single-mode rules).
- **Post-tool use**: Log tool outcomes for metrics and failure detection.
- **Error occurred**: Centralize error telemetry (timeouts, crashes, tool failures).

### 7.2 Determinism Gains

- **State correctness**: Block invalid writes to SSOT files.
- **Replayability**: Stable logs of prompts and tool executions.
- **Scope safety**: Enforce single-mode and single-task invariants.
- **Recovery fidelity**: Measure and enforce timeout recovery behavior.

### 7.3 Detailed Design

See [agents/ralph-v2/appendixes/hooks-integrations.md](agents/ralph-v2/appendixes/hooks-integrations.md) for proposed hook policies, scripts, and governance notes.
