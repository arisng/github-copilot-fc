---
domain: orchestration
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T15:42:16+07:00
---

# Orchestration Specification

## Purpose

This specification defines the state machine backbone that drives all role invocations. It establishes the system's ten states, their transition rules with behavioral guards, the role routing model, and four cross-cutting protocols: Messenger Protocol, Timeout Recovery Escalation, Schema Validation on Resume, and Critique Self-Loop. All other domain specifications receive their invocation patterns from the routing table defined here. This specification depends on Session vocabulary (SES- prefix) and the Signal protocol (SIG- prefix).

## State Machine Definition

The system defines exactly ten states. Each state represents a distinct phase of the session lifecycle. The Orchestration Role maintains the current state in the Session State Store (per SES-012).

| # | State | Purpose |
|---|---|---|
| 1 | **INITIALIZING** | Session structure creation — the Planning Role produces the initial Iteration Container, Progress Tracker, Session State Store, and Signal Channel |
| 2 | **PLANNING** | Planning task execution — the Discovery Role performs brainstorm and research; the Planning Role performs task breakdown |
| 3 | **BATCHING** | Wave selection — the Orchestration Role constructs waves from Task Definition Records and identifies the next incomplete wave |
| 4 | **EXECUTING_BATCH** | Task execution — the Execution Role implements each task in the current wave |
| 5 | **REVIEWING_BATCH** | Batch validation — the Review Role validates each completed task and executes atomic commits for qualified work |
| 6 | **SESSION_REVIEW** | Post-knowledge iteration assessment — the Review Role evaluates the final iteration state, including knowledge-pipeline evidence, and returns issue counts |
| 7 | **SESSION_CRITIQUE_REPLAN** | Critique replanning — the Planning Role triages issues and the Discovery Role optionally brainstorms and researches; the Planning Role produces gap-filling tasks |
| 8 | **KNOWLEDGE_EXTRACTION** | Knowledge pipeline — the Knowledge Role extracts, stages, and promotes reusable knowledge before final session review |
| 9 | **COMPLETE** | Final state — all tasks are finished or awaiting feedback; broadcast signals are finalized |
| 10 | **REPLANNING** | Feedback-driven replanning — the Planning Role triages feedback intent and routes to either full replanning or fast-path knowledge promotion |

## Transition Table

Every transition follows the form: **FROM** state **→ TO** state **WHEN** a behavioral guard is satisfied.

| # | From | To | Guard (behavioral predicate) |
|---|---|---|---|
| T1 | INITIALIZING | PLANNING | The Planning Role has completed initialization and the session structure exists |
| T2 | PLANNING | BATCHING | All planning tasks in the Progress Tracker are complete |
| T3 | BATCHING | EXECUTING_BATCH | At least one wave contains tasks that are not complete and not cancelled |
| T4 | BATCHING | KNOWLEDGE_EXTRACTION | No wave contains tasks that are not complete and not cancelled |
| T5 | EXECUTING_BATCH | REVIEWING_BATCH | All tasks in the current wave have completed execution or failed |
| T6 | REVIEWING_BATCH | BATCHING | All review-pending tasks in the current wave have received verdicts |
| T7 | KNOWLEDGE_EXTRACTION | SESSION_REVIEW | The knowledge pipeline has finished (all three stages complete, or the pipeline was skipped) |
| T8 | SESSION_REVIEW | SESSION_CRITIQUE_REPLAN | The active issue count is above zero AND the critique cycle counter has not reached the configured maximum |
| T9 | SESSION_CRITIQUE_REPLAN | BATCHING | All critique planning tasks for the current cycle are complete |
| T10 | SESSION_REVIEW | COMPLETE | The active issue count is zero, OR the critique cycle counter has reached the configured maximum |
| T11 | COMPLETE | REPLANNING | Post-iteration feedback is detected in the next Iteration Container's Feedback Collection |
| T12 | REPLANNING | BATCHING | The full replanning pipeline has completed (feedback analysis, plan update, and task rebreakdown are all done) |
| T13 | REPLANNING | COMPLETE | The knowledge-promotion fast-path has completed |

## Role Routing Table

Each state invokes zero or more roles. The Orchestration Role defines which role to invoke and with what mode; the invoked role defines its own execution contract.

| State | Role(s) Invoked | Invocation Purpose |
|---|---|---|
| INITIALIZING | Planning Role | Create session structure (Iteration Container, Progress Tracker, Session State Store, Signal Channel) |
| PLANNING | Discovery Role, Planning Role | Discovery: brainstorm and research cycles. Planning: task breakdown |
| BATCHING | *(none — routing only)* | Orchestration Role computes waves and selects the next incomplete wave |
| EXECUTING_BATCH | Execution Role | Implement each task in the current wave; one invocation per task |
| REVIEWING_BATCH | Review Role | Validate each review-pending task; for qualified tasks, invoke commit mode as a sub-step |
| SESSION_REVIEW | Review Role | Produce the post-knowledge Iteration Review Report with issue counts by severity |
| SESSION_CRITIQUE_REPLAN | Planning Role, Discovery Role | Planning: critique triage and critique breakdown. Discovery: optional brainstorm and research |
| KNOWLEDGE_EXTRACTION | Knowledge Role | Three-stage pipeline: extract, stage, promote before SESSION_REVIEW |
| COMPLETE | *(none — terminal)* | Finalize remaining broadcast signals and exit |
| REPLANNING | Planning Role, Discovery Role | Planning: metadata update, plan update, task rebreakdown. Discovery: feedback analysis and research |

## Requirements

### State Machine Core

#### ORCH-001: State Enumeration
The system MUST define exactly ten states: INITIALIZING, PLANNING, BATCHING, EXECUTING_BATCH, REVIEWING_BATCH, SESSION_REVIEW, SESSION_CRITIQUE_REPLAN, KNOWLEDGE_EXTRACTION, COMPLETE, and REPLANNING.

#### ORCH-002: Single Active State
The system MUST maintain exactly one current state in the Session State Store (per SES-012) at any time. Every state transition MUST atomically update the current state before any role invocation for the new state begins.

#### ORCH-003: Transition Exclusivity
State transitions MUST occur only through the transitions defined in the Transition Table. Any state pair not listed in the table is a forbidden transition. The Orchestration Role MUST NOT skip intermediate states.

### Transition Guards

#### ORCH-004: Initialization Completion Guard (T1)
The transition from INITIALIZING to PLANNING MUST occur only when the Planning Role has successfully created the Iteration Container, the Progress Tracker, the Session State Store, the Iteration State Store, and the Signal Channel. If initialization fails, the Orchestration Role MUST apply the Timeout Recovery Escalation (per ORCH-019).

#### ORCH-005: Planning Completion Guard (T2)
The transition from PLANNING to BATCHING MUST occur only when every planning task recorded in the Progress Tracker has reached a terminal status. The Orchestration Role MUST enforce a configurable maximum planning cycle count; if the cycle count is exceeded, remaining Discovery Role cycles MUST be skipped and the Planning Role's task breakdown MUST be invoked directly.

#### ORCH-006: Wave Selection Guards (T3, T4)
When the Orchestration Role evaluates Task Definition Records in BATCHING:
- If at least one wave contains tasks whose Progress Tracker status is neither complete nor cancelled, the system MUST transition to EXECUTING_BATCH (T3).
- If no such wave exists, the system MUST transition to KNOWLEDGE_EXTRACTION (T4).

#### ORCH-007: Execution Completion Guard (T5)
The transition from EXECUTING_BATCH to REVIEWING_BATCH MUST occur only when every task in the current wave has been processed by the Execution Role — each task is either review-pending or failed in the Progress Tracker.

#### ORCH-008: Review Completion Guard (T6)
The transition from REVIEWING_BATCH to BATCHING MUST occur only when every review-pending task in the current wave has received a review verdict (qualified or failed). For each qualified task, the Review Role's commit sub-step MUST have been attempted before the transition occurs.

#### ORCH-009: Session Review Decision Guard (T8, T10)
After the Review Role returns the Iteration Review Report, the Orchestration Role MUST compute the active issue count by applying the configured severity threshold:
- Threshold "any": all reported issues are active.
- Threshold "major": only critical and major issues are active.
- Threshold "critical": only critical issues are active.

If the active issue count is zero OR the critique cycle counter equals or exceeds the configured maximum, the system MUST transition to COMPLETE (T10). Otherwise, it MUST transition to SESSION_CRITIQUE_REPLAN (T8).

#### ORCH-010: Critique Completion Guard (T9)
The transition from SESSION_CRITIQUE_REPLAN to BATCHING MUST occur only when all critique planning tasks for the current critique cycle are complete in the Progress Tracker. Gap-filling tasks produced by critique breakdown are added to the current iteration's implementation scope.

#### ORCH-011: Knowledge Pipeline Completion Guard (T7)
The transition from KNOWLEDGE_EXTRACTION to SESSION_REVIEW MUST occur when:
- The Knowledge Role is not available (conditional skip), OR
- The extraction stage returns zero items, OR
- All three pipeline stages (extract, stage, promote) have completed.

#### ORCH-012: Feedback Detection Guard (T11)
The transition from COMPLETE to REPLANNING MUST occur only when the Orchestration Role detects unprocessed Feedback Collection artifacts in the next Iteration Container. The Orchestration Role MUST record the previous state before transitioning.

#### ORCH-013: Replanning Route Guards (T12, T13)
After the Planning Role triages feedback intent, it returns a replanning route:
- **Full replanning** (T12): the pipeline includes feedback analysis, plan update, and task rebreakdown. The transition to BATCHING MUST occur only when all replanning tasks are complete.
- **Knowledge promotion fast-path** (T13): the Knowledge Role executes promotion directly. The transition to COMPLETE MUST occur when promotion finishes.

### Dependency Pre-Check

#### ORCH-014: Task Dependency Enforcement
Before invoking the Execution Role for any task in EXECUTING_BATCH, the Orchestration Role MUST verify that all tasks listed in the Task Definition Record's dependency set have reached terminal complete status in the Progress Tracker. Tasks with unsatisfied dependencies MUST be skipped within the current wave.

#### ORCH-015: Task Definition Existence Check
Before invoking the Execution Role, the Orchestration Role MUST verify that the Task Definition Record exists. If the record is missing, the task MUST be marked as failed in the Progress Tracker with a missing-definition reason.

### Messenger Protocol

#### ORCH-016: One-Hop Message Forwarding
When a role invocation completes and returns a forwarded message with a next-role suggestion, the Orchestration Role MUST buffer the message for delivery to the next invoked role. The message MUST be passed as orchestration context in the next invocation's input.

#### ORCH-017: State Machine Precedence
The state machine MUST always take precedence over a role's next-role suggestion. If the state machine dictates a different next role than suggested, the Orchestration Role MUST still forward the buffered message to whichever role the state machine selects.

#### ORCH-018: Buffer Lifecycle
The message buffer MUST be cleared immediately after forwarding to the next role. Messages are one-hop only — the Orchestration Role MUST NOT accumulate messages across multiple invocations. Each invocation starts with at most one forwarded message from the immediately preceding invocation.

### Timeout Recovery Escalation

#### ORCH-019: Four-Step Escalation Chain
When a role invocation times out or returns an error, the Orchestration Role MUST apply the following escalation chain in order:
1. **Retry** — re-invoke the same role with identical input.
2. **Short wait + retry** — wait a short interval, then re-invoke.
3. **Long wait + retry** — wait a longer interval, then re-invoke.
4. **Final wait + retry** — wait once more, then re-invoke.

If the invocation still fails after step 4, the Orchestration Role MUST proceed to task splitting (per ORCH-020) or user escalation (per ORCH-021).

#### ORCH-020: Task Splitting Fallback
If the escalation chain is exhausted and the failing invocation is associated with a specific task, the Orchestration Role MUST invoke the Planning Role in task-splitting mode to decompose the task into smaller units. The Orchestration Role MUST then execute the resulting sub-tasks. If sub-tasks also exhaust the escalation chain, the policy reapplies recursively.

#### ORCH-021: Unidentified Task Escalation
If the escalation chain is exhausted and the failing invocation is NOT associated with a specific task (e.g., a planning or session-level invocation), the Orchestration Role MUST exit the session with a blocked status and request human scope reduction.

### Schema Validation on Resume

#### ORCH-022: Resume Validation Gate
On every session resume (re-entering an existing session), the Orchestration Role MUST validate the schemas of both the Session State Store and the Progress Tracker before proceeding with any state machine logic. Validation MUST check structural completeness — the presence of required sections and fields — not content correctness.

#### ORCH-023: Repair Mode Invocation
If schema validation fails for either the Session State Store or the Progress Tracker, the Orchestration Role MUST invoke the Planning Role in repair-state mode. After repair completes, the Orchestration Role MUST exit the current turn — normal state machine processing resumes on the next invocation.

### Critique Self-Loop

#### ORCH-024: Severity Threshold Configuration
The critique self-loop MUST use a configurable severity threshold loaded from session-level configuration. Valid threshold values are "any" (all issues trigger critique), "major" (only critical and major issues trigger critique), and "critical" (only critical issues trigger critique). The default MUST be "any".

#### ORCH-025: Critique Cycle Counter
The Orchestration Role MUST maintain a critique cycle counter in the Session State Store. The counter MUST be incremented each time the system enters SESSION_CRITIQUE_REPLAN and MUST be reset to zero at the start of each new iteration.

#### ORCH-026: Critique Cycle Cap
The critique self-loop MUST respect a configurable maximum cycle count loaded from session-level configuration. A null value means unlimited cycles. When the counter reaches the maximum, the system MUST advance to COMPLETE regardless of remaining active issues and MUST log a warning indicating the cap was reached.

#### ORCH-027: Critique Planning Task Sequence
Within SESSION_CRITIQUE_REPLAN, the Orchestration Role MUST route critique planning tasks in the following order:
1. **Critique triage** — Planning Role evaluates the Iteration Review Report and determines which issues require action.
2. **Critique brainstorm** (optional) — Discovery Role brainstorms if triage indicates brainstorming is needed.
3. **Critique research** (optional) — Discovery Role researches if triage indicates research is needed.
4. **Critique breakdown** — Planning Role produces gap-filling tasks for the current iteration.

Steps 2 and 3 are present only when the triage explicitly requests them.

### Signal Checkpoint Integration

#### ORCH-028: State Boundary Polling
The Orchestration Role MUST execute the Universal Polling Routine (per SIG-019) at every state transition boundary — immediately after entering a new state and before invoking any role. This ensures that signals deposited during inter-state gaps are processed before new work begins.

#### ORCH-029: Signal-Driven State Interruption
When the polling routine encounters a PAUSE signal (per SIG-004), the Orchestration Role MUST suspend state machine processing and preserve the current state for later resumption. When the polling routine encounters an ABORT signal (per SIG-005), the Orchestration Role MUST execute the abort finalization checklist and transition to a terminal blocked status.

#### ORCH-030: Session-End Signal Finalization
When the system enters COMPLETE, the Orchestration Role MUST finalize all remaining broadcast signals in the Signal Channel (Inbound) per the session-end finalization contract (per SIG-018). Signals with full quorum acknowledgment MUST be archived normally. Signals with partial acknowledgment MUST be archived with a partial delivery indicator.

### Commit Sub-Step

#### ORCH-031: Review-Then-Commit Sequence
Within REVIEWING_BATCH, for each task that receives a qualified verdict, the Orchestration Role MUST invoke the Review Role's commit mode as an immediate follow-up. Commit mode is a sub-step within REVIEWING_BATCH — it MUST NOT be modeled as a separate state. If the commit attempt fails, the Orchestration Role MUST retry once. A second commit failure MUST be logged but MUST NOT alter the qualified verdict.

### Conditional Knowledge Activation

#### ORCH-032: Knowledge Role Availability Check
Before entering the knowledge pipeline in KNOWLEDGE_EXTRACTION, the Orchestration Role MUST check whether the Knowledge Role is available. If the Knowledge Role is not available, the system MUST skip the entire pipeline and transition to SESSION_REVIEW so final review still covers the skipped knowledge stage.

#### ORCH-033: Knowledge Pipeline Sequence
When the Knowledge Role is available, the Orchestration Role MUST invoke it in exactly three sequential stages: extract (iteration artifacts to Knowledge Extraction Area), stage (Knowledge Extraction Area to Knowledge Staging Area), and promote (Knowledge Staging Area to Knowledge Repository). If the extract stage returns zero items, the remaining stages MUST be skipped and SESSION_REVIEW MUST still run on the post-pipeline state.

### Orchestration Role Boundaries

#### ORCH-034: Write Restriction
The Orchestration Role MUST NOT modify any artifact other than the Session State Store. All other artifact mutations MUST be delegated to the appropriate role as defined in the ownership model (per SES-012). Routing decisions MAY read contract-level session artifacts needed for state-machine operation, but MUST NOT expand into workspace subject-matter inspection.

#### ORCH-035: No Self-Execution
The Orchestration Role MUST NOT perform work belonging to any other role. It MUST NOT analyze workspace content, infer session subject matter from repository files, implement tasks, review code, extract knowledge, or generate plans. Its sole function is state machine evaluation, role routing, and protocol enforcement. Invocation choices MUST be derived only from contract-level inputs such as state, progress status, declared task records, prior role outputs, feedback metadata, and signal artifacts.

## Scenarios

### SC-ORCH-001: Happy Path — Initialization Through Completion
**Validates**: ORCH-001, ORCH-002, ORCH-003, ORCH-004, ORCH-005, ORCH-006, ORCH-007, ORCH-008, ORCH-009 (T10), ORCH-011
```
GIVEN a new session with no existing Session State Store
WHEN the Orchestration Role starts the session
THEN the state is set to INITIALIZING and the Planning Role is invoked
AND upon initialization completion the state transitions to PLANNING (T1)
AND upon all planning tasks completing the state transitions to BATCHING (T2)
AND the Orchestration Role identifies a wave with incomplete tasks and transitions to EXECUTING_BATCH (T3)
AND upon all wave tasks completing execution the state transitions to REVIEWING_BATCH (T5)
AND upon all verdicts being issued the state transitions to BATCHING (T6)
AND when no incomplete waves remain the state transitions to KNOWLEDGE_EXTRACTION (T4)
AND the knowledge pipeline completes and the state transitions to SESSION_REVIEW (T7)
AND the active issue count is zero so the state transitions to COMPLETE (T10)
AND the system maintains exactly one state throughout the entire sequence
```

### SC-ORCH-002: Replanning Loop — Feedback Triggers New Iteration
**Validates**: ORCH-012, ORCH-013 (T12)
```
GIVEN the system is in COMPLETE with all tasks finished
AND the human deposits Feedback Collection artifacts in the next Iteration Container
WHEN the Orchestration Role resumes the session
THEN it detects unprocessed feedback and records the previous state
AND transitions to REPLANNING (T11)
AND the Planning Role triages feedback and returns a full-replanning route
AND the replanning pipeline completes (feedback analysis, plan update, task rebreakdown)
AND the state transitions to BATCHING (T12)
```

### SC-ORCH-003: Knowledge Promotion Fast-Path
**Validates**: ORCH-013 (T13)
```
GIVEN the system is in REPLANNING after feedback from KNOWLEDGE_EXTRACTION
AND the Planning Role determines the feedback endorses staged knowledge
WHEN the Planning Role returns a knowledge-promotion route
THEN the Orchestration Role invokes the Knowledge Role in promote mode
AND the state transitions to COMPLETE (T13) without entering BATCHING
```

### SC-ORCH-004: Critique Self-Loop — Issues Found and Resolved
**Validates**: ORCH-009 (T8), ORCH-010, ORCH-025, ORCH-027
```
GIVEN the system is in SESSION_REVIEW
AND the Review Role returns an Iteration Review Report with three major issues
AND the severity threshold is "any" and the critique cycle counter is 0
WHEN the Orchestration Role computes the active issue count as 3
THEN it increments the critique cycle counter to 1
AND transitions to SESSION_CRITIQUE_REPLAN (T8)
AND routes critique planning tasks in order: triage, optional brainstorm, optional research, breakdown
AND upon all critique planning tasks completing, transitions to BATCHING (T9)
AND the gap-filling tasks are executed and reviewed
AND when SESSION_REVIEW is re-entered with zero active issues, the state transitions to COMPLETE (T10)
```

### SC-ORCH-005: Critique Cycle Cap Reached
**Validates**: ORCH-026, ORCH-009 (T10 via cap)
```
GIVEN the system is in SESSION_REVIEW
AND the critique cycle counter equals the configured maximum critique cycles
AND the active issue count is above zero
WHEN the Orchestration Role evaluates the critique loop decision
THEN it logs a warning that the critique cycle cap was reached
AND transitions to COMPLETE (T10) with unresolved issues
AND the critique cycle counter is reset to zero
```

### SC-ORCH-006: Severity Threshold Filters Issues
**Validates**: ORCH-024
```
GIVEN the system is in SESSION_REVIEW
AND the Review Role reports 2 minor issues and 0 major or critical issues
AND the severity threshold is "major"
WHEN the Orchestration Role computes the active issue count
THEN the active issue count is zero (minor issues are excluded)
AND the system transitions to COMPLETE without entering the critique loop
```

### SC-ORCH-007: Signal Interruption — PAUSE During Execution
**Validates**: ORCH-028, ORCH-029
```
GIVEN the system has just transitioned to EXECUTING_BATCH
WHEN the Orchestration Role executes the Universal Polling Routine (per SIG-019) at the state boundary
AND a PAUSE signal is present in the Signal Channel (Inbound)
THEN the Orchestration Role suspends state machine processing
AND preserves the current state as EXECUTING_BATCH in the Session State Store
AND does not invoke the Execution Role until resumption is initiated
```

### SC-ORCH-008: Signal Interruption — ABORT Terminates Session
**Validates**: ORCH-029
```
GIVEN the system is in any active state
WHEN the Orchestration Role encounters an ABORT signal during polling
THEN it executes the abort finalization checklist (per SIG-005)
AND marks all in-progress tasks as failed in the Progress Tracker
AND records the termination in the Session State Store
AND does not proceed with any further state transitions
```

### SC-ORCH-009: Messenger Protocol — One-Hop Forwarding
**Validates**: ORCH-016, ORCH-018
```
GIVEN the Discovery Role completes a brainstorm invocation
AND its response includes a forwarded message with context for the next role
WHEN the Orchestration Role captures the message
THEN it buffers the message
AND passes it as orchestration context to the next invoked role (the Discovery Role for research, per the state machine)
AND clears the buffer immediately after forwarding
```

### SC-ORCH-010: Messenger Protocol — State Machine Overrides Suggestion
**Validates**: ORCH-017
```
GIVEN the Discovery Role completes its work and suggests the Planning Role as the next role
BUT the state machine dictates that another Discovery Role cycle must run first
WHEN the Orchestration Role evaluates the next transition
THEN it ignores the next-role suggestion
AND invokes the Discovery Role for the next cycle
AND forwards the buffered message to the Discovery Role instead of the Planning Role
```

### SC-ORCH-011: Timeout Recovery — Full Escalation to Task Split
**Validates**: ORCH-019, ORCH-020
```
GIVEN the Execution Role times out on a task
WHEN the Orchestration Role applies the escalation chain
THEN it retries the same invocation (step 1)
AND if that fails, waits a short interval and retries (step 2)
AND if that fails, waits a longer interval and retries (step 3)
AND if that fails, waits once more and retries (step 4)
AND if that still fails, invokes the Planning Role in task-splitting mode
AND executes the resulting sub-tasks in place of the original task
```

### SC-ORCH-012: Timeout Recovery — No Task ID Escalation
**Validates**: ORCH-021
```
GIVEN a planning-phase invocation times out
AND the failing invocation is not associated with any specific task
WHEN the escalation chain is exhausted after all four steps
THEN the Orchestration Role exits the session with a blocked status
AND requests the human to reduce the request scope
```

### SC-ORCH-013: Schema Validation — Successful Resume
**Validates**: ORCH-022
```
GIVEN an existing session with a valid Session State Store and Progress Tracker
WHEN the Orchestration Role resumes the session
THEN it validates both schemas and confirms structural completeness
AND proceeds with normal state machine processing from the stored current state
```

### SC-ORCH-014: Schema Validation — Repair Required
**Validates**: ORCH-022, ORCH-023
```
GIVEN an existing session where the Progress Tracker is missing a required section
WHEN the Orchestration Role resumes the session and validates schemas
THEN validation fails
AND the Orchestration Role invokes the Planning Role in repair-state mode
AND after repair completes, the Orchestration Role exits the current turn
AND normal state machine processing resumes on the next invocation
```

### SC-ORCH-015: Dependency Pre-Check Blocks Execution
**Validates**: ORCH-014
```
GIVEN a task in the current wave depends on another task
AND the dependency task has not reached terminal complete status in the Progress Tracker
WHEN the Orchestration Role evaluates the task for execution
THEN it skips the task within this wave
AND does not invoke the Execution Role for the skipped task
```

### SC-ORCH-016: Missing Task Definition
**Validates**: ORCH-015
```
GIVEN a task is listed in the Progress Tracker for the current wave
BUT its Task Definition Record does not exist
WHEN the Orchestration Role prepares to invoke the Execution Role
THEN it marks the task as failed in the Progress Tracker with reason "Task definition missing"
AND does not invoke the Execution Role for that task
```

### SC-ORCH-017: Review-Then-Commit — Commit Failure Isolation
**Validates**: ORCH-031
```
GIVEN a task receives a qualified verdict from the Review Role
WHEN the Orchestration Role invokes commit mode and it fails
THEN the Orchestration Role retries commit mode once
AND if the retry also fails, it logs the failure
AND the qualified verdict is preserved — the task remains complete in the Progress Tracker
```

### SC-ORCH-018: Knowledge Role Unavailable — Pipeline Skipped
**Validates**: ORCH-032
```
GIVEN the system transitions to KNOWLEDGE_EXTRACTION
AND the Knowledge Role is not available in the current session
WHEN the Orchestration Role checks Knowledge Role availability
THEN it skips the entire knowledge pipeline
AND transitions to SESSION_REVIEW (T7)
```

### SC-ORCH-019: Knowledge Pipeline — Zero Extraction Short-Circuit
**Validates**: ORCH-033
```
GIVEN the Knowledge Role is available
AND the extract stage processes iteration artifacts but finds zero reusable items
WHEN the extract stage returns a zero-item result
THEN the Orchestration Role skips the stage and promote stages
AND transitions to SESSION_REVIEW (T7)
```

### SC-ORCH-020: Session-End Signal Finalization
**Validates**: ORCH-030
```
GIVEN the system enters COMPLETE
AND a broadcast signal remains in the Signal Channel (Inbound) with partial acknowledgments
WHEN the Orchestration Role executes session-end finalization (per SIG-018)
THEN it archives the signal with a partial delivery indicator
AND records the list of roles that did not acknowledge
```

### SC-ORCH-021: Write Restriction Enforcement
**Validates**: ORCH-034
```
GIVEN the Orchestration Role needs to update task status after a role invocation completes
WHEN it determines the Progress Tracker must be updated
THEN the update is performed by the invoked role (per SES-012), not by the Orchestration Role
AND the Orchestration Role only updates the Session State Store for state transitions
```

### SC-ORCH-022: Forbidden Transition Rejected
**Validates**: ORCH-003
```
GIVEN the system is in EXECUTING_BATCH
WHEN a condition arises that would suggest transitioning directly to SESSION_REVIEW
THEN the Orchestration Role rejects the transition because EXECUTING_BATCH → SESSION_REVIEW is not in the Transition Table
AND instead follows the required path through REVIEWING_BATCH and BATCHING
```

### SC-ORCH-023: Critique Optional Steps Skipped
**Validates**: ORCH-027
```
GIVEN the system is in SESSION_CRITIQUE_REPLAN
AND the critique triage determines that neither brainstorming nor research is needed
WHEN the Orchestration Role routes critique planning tasks
THEN it skips the brainstorm and research steps
AND proceeds directly from critique triage to critique breakdown
AND upon breakdown completion transitions to BATCHING (T9)
```

### SC-ORCH-024: No Self-Execution Enforcement
**Validates**: ORCH-035
```
GIVEN the Orchestration Role receives a user request that includes session-specific subject matter
WHEN it evaluates the next invocation
THEN it derives that routing decision from contract-level inputs only
AND it does not read or analyze workspace files to infer what the session is about
AND it immediately invokes the appropriate role with the raw user input or buffered role context required by the state machine
```
