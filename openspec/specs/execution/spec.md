---
domain: execution
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T16:24:32+07:00
---

# Execution Specification

This specification defines the behavioral contracts for the Execution Role — the role responsible for implementing exactly one Task Definition Record per invocation. It establishes the single-task execution model, the execution parameter set, the five-step execution workflow, the progress status lifecycle, the dependency inheritance protocol, the rework protocol, the two-part Task Report structure, and design-time validation scope. This specification depends on Session vocabulary (SES- prefix), Orchestration routing (ORCH- prefix), and the Signal protocol (SIG- prefix).

## Execution Parameters

Every invocation of the Execution Role receives a fixed parameter set from the Orchestration Role. These parameters fully identify the work unit and its position within the session lifecycle.

| # | Parameter | Purpose |
|---|---|---|
| 1 | **Session Reference** | Identifies the target session containing the Iteration Container |
| 2 | **Task Identifier** | Identifies the specific Task Definition Record to implement |
| 3 | **Attempt Number** | Ordinal of the current attempt (1 for first execution, 2+ for rework) |
| 4 | **Iteration** | Identifies the Iteration Container holding the Task Definition Record |
| 5 | **Orchestrator Context** | Optional one-hop message forwarded from a preceding role via the Messenger Protocol (per ORCH-016) |

## Requirements

### Single-Task Execution Model

#### EXEC-001: One Task Per Invocation
The Execution Role MUST accept exactly one Task Definition Record per invocation (per SES-022). The role MUST reject any request that specifies multiple tasks in a single invocation.

#### EXEC-002: Task Definition Record as Input
The Execution Role MUST read the Task Definition Record identified by the Task Identifier and Iteration parameters. The record provides the objective, success criteria, target artifacts, and dependency set that govern implementation.

#### EXEC-003: Execution Parameter Completeness
Every invocation of the Execution Role MUST include all four mandatory parameters: Session Reference, Task Identifier, Attempt Number, and Iteration. The Orchestrator Context parameter is optional. If any mandatory parameter is missing, the Execution Role MUST return a blocked status.

### Execution Workflow

#### EXEC-004: Five-Step Execution Workflow
The Execution Role MUST execute the following five steps in order for every invocation:
1. **Read Context** — load the Task Definition Record, inherited dependency context, feedback context (if applicable), and any previous attempt context.
2. **Mark Work-in-Progress** — update the Progress Tracker to reflect that execution has begun.
3. **Implement** — perform the work specified by the Task Definition Record.
4. **Verify** — validate the implementation against each success criterion.
5. **Report** — persist the Task Report and update the Progress Tracker with the final status.

#### EXEC-005: Context Reading — Task Definition
In the Read Context step, the Execution Role MUST extract the following from the Task Definition Record: title, target artifacts, objective, success criteria, and dependency set (per PLAN-022 through PLAN-026 structural requirements).

#### EXEC-006: Context Reading — Orchestrator Context
If the Orchestrator Context parameter is present, the Execution Role MUST incorporate the forwarded message into its working context before beginning implementation. This message originates from the Messenger Protocol (per ORCH-016, ORCH-017).

#### EXEC-007: Capability Discovery Before Implementation
The Execution Role SHOULD discover and load relevant capabilities before beginning the Implement step using the four-step reasoning process (per SES-020). If the capability registry is unavailable, the role SHOULD proceed in degraded mode (per SES-021).

### Dependency Inheritance Protocol

#### EXEC-008: Mandatory Predecessor Report Reading
When the Task Definition Record contains a non-empty dependency set, the Execution Role MUST read the Task Report of every predecessor task before beginning the Implement step. This is a MUST-level requirement — skipping predecessor context is a protocol violation.

#### EXEC-009: Pattern Inheritance
From each predecessor Task Report, the Execution Role MUST extract and apply: conventions adopted, interface patterns established, architectural decisions made, and any constraints discovered. These inherited patterns MUST inform the current implementation.

#### EXEC-010: Dependency Satisfaction Precondition
The Execution Role MUST NOT begin the Implement step if any predecessor task in the dependency set has not reached terminal complete status in the Progress Tracker. If a predecessor is incomplete, the Execution Role MUST return a blocked status with the unsatisfied dependency as the blocker (per ORCH-014).

### Progress Status Lifecycle

#### EXEC-011: Work-in-Progress Marking
At the start of the Mark Work-in-Progress step, the Execution Role MUST update the Progress Tracker to transition the task status from not-started to in-progress (per SES-016). The update MUST include the attempt number, iteration, and a start timestamp.

#### EXEC-012: Review-Pending Marking
When the Execution Role completes implementation and all success criteria are assessed as met, the Progress Tracker MUST be updated to transition the task status from in-progress to review-pending (per SES-016).

#### EXEC-013: Blocked Status on Failure
If the Execution Role encounters an unresolvable issue during implementation, the Progress Tracker MUST remain at in-progress and the role MUST return a blocked status with the specific blockers documented.

#### EXEC-014: Honest Assessment Obligation
The Execution Role MUST NOT mark a task as review-pending if any success criterion is assessed as not met. The status MUST accurately reflect the implementation outcome. Overstating completion is a protocol violation.

### Rework Protocol

#### EXEC-015: Previous Attempt Report Reading
When the Attempt Number is greater than 1, the Execution Role MUST read the Task Report from the immediately preceding attempt before beginning the Implement step. The report includes both Part 1 (implementation decisions) and Part 2 (review verdict and feedback).

#### EXEC-016: Feedback Context Reading
When the Iteration is greater than 1, the Execution Role MUST read the Feedback Collection artifacts within the current Iteration Container and identify issues relevant to the current task.

#### EXEC-017: Rework Lessons Application
During a rework attempt, the Execution Role MUST document in the Task Report: which previous attempt was reviewed, what feedback was addressed, and how the current approach differs from the prior attempt. Implementation MUST apply the lessons learned from the review verdict.

#### EXEC-018: Report Preservation
The Execution Role MUST NOT overwrite or modify Task Reports from previous attempts. Each attempt produces its own distinct Task Report (per SES-011 cross-iteration immutability extended to cross-attempt immutability within an iteration).

### Task Report Structure

#### EXEC-019: Two-Part Report Model
The Task Report MUST consist of exactly two parts:
- **Part 1: Implementation Report** — authored by the Execution Role during the Report step.
- **Part 2: Review Report** — reserved for the Review Role. The Execution Role MUST NOT write to Part 2.

#### EXEC-020: Part 1 Mandatory Sections
Part 1 of the Task Report MUST include at minimum:
1. **Objective Recap** — the objective extracted from the Task Definition Record.
2. **Success Criteria Status** — a table mapping each success criterion to a met/not-met assessment with evidence.
3. **Summary of Changes** — the artifacts modified and the nature of each modification.
4. **Verification Results** — the outcome of each verification check performed.
5. **Blockers** — any unresolved issues, or an explicit "none" declaration.

#### EXEC-021: Rework Context Section
When the Attempt Number is greater than 1, Part 1 MUST additionally include a Rework Context section documenting: the previous attempt report reference, the feedback addressed, and the changes in approach.

#### EXEC-022: Feedback Context Section
When the Iteration is greater than 1 and relevant Feedback Collection artifacts exist, Part 1 MUST additionally include a Feedback Context section documenting how feedback influenced the implementation.

#### EXEC-023: Discovered Tasks Section
Part 1 SHOULD include a Discovered Tasks section listing any new requirements identified during execution that fall outside the current Task Definition Record's scope. These items are informational for the Orchestration Role.

#### EXEC-024: Report Metadata
Every Task Report MUST include metadata recording: the Task Identifier, Iteration, Attempt Number, and creation timestamp.

### Design-Time Validation Scope

#### EXEC-025: Verification Responsibility Boundary
The Execution Role MUST perform design-time validation only: structural correctness, consistency checks, constraint satisfaction, and any automated checks that do not require runtime execution of the implemented artifacts. The Execution Role MUST NOT perform runtime validation — runtime checks are the exclusive responsibility of the Review Role.

#### EXEC-026: Per-Criterion Verification
In the Verify step, the Execution Role MUST evaluate each success criterion individually. For each criterion, the Execution Role MUST record: whether the criterion is met or not met, and the evidence supporting the assessment.

#### EXEC-027: Verification Artifact Storage
Ephemeral artifacts produced during verification (logs, intermediate outputs, generated files) MUST be stored in a verification area scoped to the current task within the Iteration Container. Verification results MUST be consolidated into the Task Report — the verification area is not authoritative.

### Signal Checkpoint Integration

#### EXEC-028: Pre-Execution Signal Poll
Before the Read Context step, the Execution Role MUST poll the Signal Channel for pending signals using the Universal Polling Routine (per SIG-019). The role MUST process ABORT signals (per SIG-005) by returning a blocked status, PAUSE signals (per SIG-004) by waiting, STEER signals by updating context, and INFO signals by logging.

#### EXEC-029: Post-WIP Signal Poll
After the Mark Work-in-Progress step, the Execution Role MUST poll the Signal Channel again. ABORT signals MUST result in a blocked status. PAUSE signals MUST cause the role to wait. STEER and INFO signals MUST be logged and incorporated into context.

#### EXEC-030: Mid-Execution Signal Handling
During the Implement step, if a STEER signal is received, the Execution Role MUST evaluate the signal against the current implementation state using three criteria:
1. **Work Invalidated** — the signal contradicts already-implemented work. The Execution Role MUST restart the Implement step with updated context.
2. **Additive / Non-conflicting** — the signal adds constraints without invalidating current work. The Execution Role MUST adjust in-place and continue.
3. **Scope Change** — the signal fundamentally redefines the task objective. The Execution Role MUST return a blocked status and escalate to the Orchestration Role for task redefinition.

### Invocation Contract

#### EXEC-031: Input Contract
The Execution Role MUST accept input consisting of: Session Reference, Task Identifier, Attempt Number, Iteration, and optional Orchestrator Context. These parameters correspond to the invocation performed by the Orchestration Role in EXECUTING_BATCH state (per ORCH-007).

#### EXEC-032: Output Contract
Upon completion, the Execution Role MUST return: a status (completed, failed, or blocked), the Task Identifier, Iteration, Attempt Number, the path reference to the created Task Report, a success-criteria-met indicator, a criteria breakdown (total, met, not-met counts), the list of modified artifacts, any feedback issues addressed, discovered tasks, blockers, and an optional next-role suggestion with a forwarded message (per ORCH-016).

#### EXEC-033: Postconditions
After any non-error invocation, the following MUST hold:
1. A Task Report exists for this attempt.
2. The Progress Tracker reflects the final status of this task.
3. Verification artifacts, if any, are stored in the task-scoped verification area.

## Scenarios

### SC-EXEC-001: Happy-Path Single-Task Execution
**Validates**: EXEC-001, EXEC-002, EXEC-004, EXEC-005, EXEC-011, EXEC-012, EXEC-019, EXEC-020, EXEC-024, EXEC-031, EXEC-032, EXEC-033
```
GIVEN the Orchestration Role is in EXECUTING_BATCH state
AND a Task Definition Record exists for the specified Task Identifier
AND the task has no dependencies
WHEN the Execution Role is invoked with valid Session Reference, Task Identifier, Attempt Number 1, and Iteration 1
THEN the Execution Role reads the Task Definition Record
AND updates the Progress Tracker from not-started to in-progress
AND implements the work specified by the Task Definition Record
AND verifies each success criterion individually
AND creates a Task Report with Part 1 populated and Part 2 reserved
AND updates the Progress Tracker from in-progress to review-pending
AND returns a completed status with the success-criteria-met indicator set to true
```

### SC-EXEC-002: Multi-Task Rejection
**Validates**: EXEC-001
```
GIVEN the Orchestration Role invokes the Execution Role
WHEN the invocation specifies two or more Task Identifiers
THEN the Execution Role rejects the request
AND returns a blocked status with a single-task violation blocker
```

### SC-EXEC-003: Missing Parameter Detection
**Validates**: EXEC-003
```
GIVEN an invocation of the Execution Role
WHEN the Task Identifier parameter is missing
THEN the Execution Role returns a blocked status
AND the blocker identifies the missing mandatory parameter
```

### SC-EXEC-004: Dependency Inheritance — Patterns Applied
**Validates**: EXEC-008, EXEC-009, EXEC-010
```
GIVEN a Task Definition Record with a non-empty dependency set listing task A
AND task A has a completed Task Report documenting an interface convention
WHEN the Execution Role reads context for the current task
THEN the Execution Role reads task A's Task Report
AND extracts the interface convention
AND applies the convention during implementation of the current task
```

### SC-EXEC-005: Dependency Unsatisfied — Blocked
**Validates**: EXEC-010
```
GIVEN a Task Definition Record with a dependency on task B
AND task B has status in-progress in the Progress Tracker
WHEN the Execution Role checks dependency satisfaction
THEN the Execution Role returns a blocked status
AND the blocker identifies task B as the unsatisfied dependency
```

### SC-EXEC-006: Rework — Second Attempt
**Validates**: EXEC-015, EXEC-017, EXEC-018, EXEC-021
```
GIVEN a task that failed review on Attempt 1
AND a Task Report for Attempt 1 exists with review feedback in Part 2
WHEN the Execution Role is invoked with Attempt Number 2
THEN the Execution Role reads the Attempt 1 Task Report
AND documents in the new Task Report: the previous attempt reference, feedback addressed, and changes in approach
AND creates a separate Task Report for Attempt 2 without modifying the Attempt 1 report
```

### SC-EXEC-007: Feedback Context — Iteration 2
**Validates**: EXEC-016, EXEC-022
```
GIVEN a task in Iteration 2
AND the Feedback Collection contains issues relevant to the current task
WHEN the Execution Role reads context
THEN the Execution Role reads the Feedback Collection artifacts
AND includes a Feedback Context section in Part 1 of the Task Report
```

### SC-EXEC-008: Honest Assessment — Criteria Not Met
**Validates**: EXEC-014, EXEC-013, EXEC-026
```
GIVEN the Execution Role has completed implementation
AND one success criterion is assessed as not met
WHEN the Verify step evaluates all criteria
THEN the Progress Tracker remains at in-progress (not advanced to review-pending)
AND the Task Report documents the unmet criterion with evidence
AND the role returns with success-criteria-met set to false
```

### SC-EXEC-009: Design-Time vs. Runtime Validation Boundary
**Validates**: EXEC-025
```
GIVEN the Execution Role is in the Verify step
WHEN a success criterion requires runtime execution of the implemented artifact to validate
THEN the Execution Role records the criterion as "pending runtime validation"
AND does NOT attempt to execute the artifact at runtime
AND defers the runtime check to the Review Role
```

### SC-EXEC-010: Report Structure — Part 2 Reserved
**Validates**: EXEC-019
```
GIVEN the Execution Role is in the Report step
WHEN it creates the Task Report
THEN Part 1 (Implementation Report) is fully populated
AND Part 2 (Review Report) exists as a reserved section with no content
AND the Execution Role does not write to Part 2
```

### SC-EXEC-011: Pre-Execution ABORT Signal
**Validates**: EXEC-028
```
GIVEN a pending ABORT signal exists in the Signal Channel targeting the Execution Role
WHEN the Execution Role polls the Signal Channel before the Read Context step
THEN the Execution Role processes the ABORT signal per the Universal Polling Routine (SIG-019)
AND returns a blocked status with an abort blocker
AND does not begin reading the Task Definition Record
```

### SC-EXEC-012: Mid-Execution STEER — Work Invalidated
**Validates**: EXEC-030
```
GIVEN the Execution Role is in the Implement step and has modified artifacts
WHEN a STEER signal is received that contradicts the already-implemented changes
THEN the Execution Role restarts the Implement step with the updated context from the STEER signal
AND notes in the Task Report that implementation was restarted due to the STEER signal
```

### SC-EXEC-013: Mid-Execution STEER — Additive Constraint
**Validates**: EXEC-030
```
GIVEN the Execution Role is in the Implement step
WHEN a STEER signal is received that adds a constraint without invalidating current work
THEN the Execution Role incorporates the constraint and continues implementation from the current position
AND does not restart the Implement step
```

### SC-EXEC-014: Mid-Execution STEER — Scope Change
**Validates**: EXEC-030
```
GIVEN the Execution Role is in the Implement step
WHEN a STEER signal is received that fundamentally redefines the task objective
THEN the Execution Role returns a blocked status
AND the blocker identifies the scope change
AND the Orchestration Role receives the escalation for task redefinition
```

### SC-EXEC-015: Orchestrator Context Forwarding
**Validates**: EXEC-006, EXEC-031
```
GIVEN the preceding role returned a forwarded message via the Messenger Protocol
AND the Orchestration Role buffers the message
WHEN the Execution Role is invoked with the Orchestrator Context parameter containing the message
THEN the Execution Role incorporates the message into its working context
AND uses the forwarded context to inform implementation decisions
```

### SC-EXEC-016: Capability Discovery — Degraded Mode
**Validates**: EXEC-007
```
GIVEN the capability registry is unavailable
WHEN the Execution Role attempts the four-step capability discovery process
THEN the Execution Role proceeds in degraded mode
AND does not fail the invocation due to missing capabilities
```

### SC-EXEC-017: Verification Artifact Storage
**Validates**: EXEC-023, EXEC-027
```
GIVEN the Execution Role identifies a new requirement during implementation that is outside the current Task Definition Record's scope
AND the role produces ephemeral verification artifacts during the Verify step
WHEN verification completes
THEN the discovered requirement is listed in the Discovered Tasks section of the Task Report
AND the ephemeral artifacts are stored in the task-scoped verification area
AND the verification results are consolidated into the Task Report
AND the verification area is not treated as authoritative
```

### SC-EXEC-018: Post-WIP PAUSE Signal
**Validates**: EXEC-029
```
GIVEN the Execution Role has updated the Progress Tracker to in-progress
WHEN a PAUSE signal is detected during the post-WIP signal poll
THEN the Execution Role waits until the PAUSE condition is resolved
AND resumes the Implement step after the pause is lifted
```
