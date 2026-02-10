# Ralph v2 Workflow Critique (Revision 3)

**Date**: 2026-02-10  
**Status**: Post-Remediation Review (Delta Focus)

## Executive Summary

Ralph v2 is structurally sound for single-stream execution and has resolved the prior critical race conditions through the Delegated State pattern. The remaining risks are no longer architectural correctness issues, but operational and governance gaps: lifecycle guardrails, state consistency, and resiliency controls. These are tractable with light-weight guardrails and validation, without altering the core architecture.

**Status Overview:**
- ✅ **Critical Race Conditions**: Resolved via Delegated State Pattern
- ✅ **Task Lifecycle**: Explicit task existence validation is in place
- ✅ **Session Governance**: Dedicated Session Review state confirmed
- ⚠️ **Operational Guardrails**: Missing cycle limits, state validation, and input hardening
- ⚠️ **Resiliency**: No retries/rollback, limited observability
- ⚠️ **Orchestrator Purity**: Observed fallback to self-execution on subagent timeouts

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

### 🔴 High: State Machine Drift

**Risk**: Orchestrator decisions depend on `progress.md` and metadata fields without schema validation.
Incorrect or partial edits can cause invalid transitions (e.g., REPLANNING with no feedback batch).

### 🟠 High: Path Injection via Session ID

**Risk**: `SESSION_ID` is used to build file paths without sanitization, enabling traversal or invalid paths.

### 🟡 Medium: Planning Cycle Exhaustion

**Risk**: `plan-brainstorm` and `plan-research` can loop indefinitely if new questions keep emerging.

### 🟡 Medium: Metadata Ownership Conflicts

**Risk**: `metadata.yaml` can still be modified by multiple agents without optimistic locking or a revision check.

### 🟡 Medium: Partial Failure Handling

**Risk**: A subagent crash can leave `progress.md` in `[/]` with no timeout, forcing manual recovery.

### 🟡 Medium: Orchestrator Role Drift

**Risk**: On subagent timeout, the Orchestrator may attempt to complete the task itself, violating the router-only contract and mixing responsibilities.

### 🟡 Medium: Multi-Mode Subagent Invocation

**Risk**: A single subagent invocation may be asked to execute multiple modes (e.g., Planner `UPDATE` + `REBREAKDOWN`), increasing context overload and blending responsibilities.

### 🟡 Medium: Dependency Enforcement

**Risk**: Task dependency rules (`depends_on`) are not enforced by a hard pre-check before execution.

---

## 3. Recommendations (Actionable)

### Guardrails and Validation

1. **Add a state schema validator** for `progress.md` and `metadata.yaml` before transitions.
2. **Introduce `MAX_CYCLES`** for planning loops; after N cycles, force `TASK_BREAKDOWN` with a warning note.
3. **Sanitize `SESSION_ID`** by restricting to `^[0-9]{6}-[0-9]{6}$` and rejecting path separators.

### Resiliency and Recovery

4. **Add a timeout rule** for `[/]` tasks (e.g., mark as `[F]` after TTL or prompt for recovery).
5. **Add a retry slot** for failed subagent calls (single retry with backoff, then fail fast).
6. **On timeout or error, re-spawn the same subagent** with the same single-mode request; never route the Orchestrator to execute the task.

### Consistency and Governance

7. **Optimistic locking for `metadata.yaml`** using a `version` field incremented on each write.
8. **Enforce one mode per subagent invocation**; chain modes via separate subagent calls.
9. **Dependency pre-check**: block execution of a task if any `depends_on` tasks are not `[x]`.

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
5. **Timeout recovery** converts stale `[/]` to `[F]` with a reason note.
6. **Subagent retry** spawns the same role with the same single-mode request.
7. **Single-mode enforcement** prevents `UPDATE` + `REBREAKDOWN` in one Planner call.

---

## Conclusion

Ralph v2 is ready for sustained use under its current architectural constraints. The next step is not structural change, but operational guardrails that prevent drift, enforce consistency, and improve recovery ergonomics. With those additions, the system would reach production-grade reliability for single-stream execution.
