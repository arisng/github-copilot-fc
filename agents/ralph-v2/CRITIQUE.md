# Ralph v2 Workflow Critique (Revision 2)

**Date**: 2026-02-08  
**Status**: Post-Remediation Review

## Executive Summary

The Ralph v2 architecture has been significantly hardened based on the "Delegated State" pattern. The Orchestrator is now correctly positioned as a read-only router for shared execution state, with write authority delegated to specialized subagents. This eliminates the primary race conditions identified in the previous review.

**Status Overview:**
- ✅ **Critical Race Conditions**: Resolved via Delegated State Pattern
- ✅ **Task Lifecycle**: Improved task validation and `plan-init` handling
- ✅ **Session Governance**: Centralized holistic review in Ralph-Reviewer
- ⚠️ **Resiliency**: Error recovery and rollbacks are deferred (as per design constraints)

---

## 1. Resolved Issues

### ✅ Orchestrator Read-Only Access
The Orchestrator no longer writes to `progress.md` during execution or review loops.
- **Proof**: `EXECUTING_BATCH` and `REVIEWING_BATCH` states now wait for completion, trusting subagents (Executor/Reviewer) to update `progress.md`.
- **Benefit**: Eliminates "double-write" race conditions defined in the previous critique.

### ✅ Task Validation
The Orchestrator now explicitly validates task file existence (`tasks/<task-id>.md`) before invocation.
- **Benefit**: Prevents "blind execution" failures where the orchestrator would try to run a deleted or missing task.

### ✅ Session Review Segregation
A dedicated `SESSION_REVIEW` state has been added, invoking `Ralph-Reviewer-v2` in `SESSION_REVIEW` mode.
- **Benefit**: Ensures holistic consistency checks happen in a specialized agent, not implicitly in the Orchestrator's routing logic.

### ✅ Contract Redundancy Fix
`Ralph-Executor-v2` output contract has been cleaned up.
- **Change**: Removed redundant `parallel_execution_context` object.
- **Result**: Output is now flat and unambiguous (`files_modified` at the root).

---

## 2. Remaining Improvements (Actionable)

### 🟡 Medium: Cycle Limits for Planning
**Problem**: The `PLANNING` loop (`plan-brainstorm`, `plan-research`) theoretically allows infinite cycles if the Questioner keeps generating new questions.
- **Recommendation**: Add a `MAX_CYCLES` guardrail in the Orchestrator or Planner to force a transition to `TASK_BREAKDOWN` after N cycles.

### 🟡 Medium: Metadata.yaml Optimistic Locking
**Problem**: While `progress.md` is safe, `metadata.yaml` is still touched by both Planner (initialization) and Orchestrator (state tracking).
- **Recommendation**: As a future enhancement, implement a `version` field in `metadata.yaml` to detect if the Planner updated the file while the Orchestrator was processing.

### 🟡 Medium: Input Sanitization
**Problem**: `SESSION_ID` inputs are still used directly in file paths.
- **Recommendation**: Add path traversal checks (`../`) in the Orchestrator before resolving `.ralph-sessions/<SESSION_ID>/`.

---

## 3. Deferred capabilities (By Design)

The following areas are acknowledged gaps but are deferred for future enhancements:
- **Rollback Mechanism**: No transaction logging or state rollback on failure.
- **Advanced Concurrency**: No file-level locking or complex isolation checks (relying on user/planner discipline).
- **Subagent Resilience**: No retry logic for crashed subagents; system fails fast.
- **Feedback Validation**: `feedbacks.md` structure is treated as optional/flexible.

---

## 4. Final Verification

### Workflow Logic Check
1. **Init**: Planner creates artifacts + marks `plan-init` [x]. -> **OK**
2. **Planning**: Orchestrator routes based on `progress.md`. -> **OK**
3. **Execution**: Orchestrator checks file -> Invokes Executor -> Executor updates [P]. -> **OK**
4. **Review**: Orchestrator invokes Reviewer -> Reviewer updates [x]/[F]. -> **OK**
5. **Session Review**: Orchestrator invokes Reviewer (Session Mode). -> **OK**

### Conclusion
The architecture is now **Structurally Sound** for single-stream execution. The separation of concerns is strict:
- **Orchestrator**: Routing & Read-Only Monitoring
- **Planner**: Artifact Creation & Plan Mutable State
- **Executor**: Task Implementation & Progress Marking ([/], [P])
- **Reviewer**: Quality Gating & Progress Marking ([x], [F])

**Rating**: 9/10 (Within constraints)
The system is ready for implementation/usage of the v2 agents.
