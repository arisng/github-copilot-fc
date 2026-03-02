---
domain: planning
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T16:10:48+07:00
---

# Planning Specification

## Purpose

This specification defines the behavioral contracts for the Planning Role — the role responsible for session initialization, task breakdown, replanning, state repair, and critique-driven gap-filling. It establishes nine planning modes, the Task Definition Record structure, the multi-pass breakdown algorithm, grounding requirements, the Iteration Plan lifecycle, and wave optimization. This specification depends on Session vocabulary (SES- prefix), Orchestration routing (ORCH- prefix), and the Signal protocol (SIG- prefix).

## Planning Modes

The Planning Role operates in exactly nine modes. Each mode is invoked by the Orchestration Role from a specific state (per the Orchestration Role Routing Table). The Planning Role MUST accept exactly one mode per invocation (per SES-022).

| # | Mode | Invoked From | Purpose |
|---|---|---|---|
| 1 | **INITIALIZE** | INITIALIZING (ORCH-004) | Create the initial session structure: Session State Store, Iteration Container, Iteration State Store, Progress Tracker, Iteration Plan, and Signal Channel |
| 2 | **UPDATE** | REPLANNING (ORCH-013) | Integrate feedback and Discovery Record outputs into the Iteration Plan, appending replanning history |
| 3 | **TASK_BREAKDOWN** | PLANNING (ORCH-005) | Decompose the Iteration Plan into isolated Task Definition Records using the multi-pass breakdown algorithm |
| 4 | **REBREAKDOWN** | REPLANNING (ORCH-013) | Revise failed Task Definition Records based on feedback, reset their status, and create new records if required |
| 5 | **SPLIT_TASK** | Timeout Recovery (ORCH-020) | Decompose a single oversized Task Definition Record into smaller sub-records after repeated execution timeouts |
| 6 | **UPDATE_METADATA** | Any state | Update the Session State Store with status, timestamp, and iteration changes |
| 7 | **REPAIR_STATE** | Schema Validation failure (ORCH-023) | Reconstruct malformed or missing Progress Tracker and Session State Store artifacts |
| 8 | **CRITIQUE_TRIAGE** | SESSION_CRITIQUE_REPLAN (ORCH-027 step 1) | Analyze the Iteration Review Report and determine whether brainstorm or research cycles are needed before critique breakdown |
| 9 | **CRITIQUE_BREAKDOWN** | SESSION_CRITIQUE_REPLAN (ORCH-027 step 4) | Create gap-filling Task Definition Records from issues identified in the Iteration Review Report |

## Requirements

### Mode Enumeration

#### PLAN-001: Recognized Planning Mode Set
The Planning Role MUST recognize exactly nine modes: INITIALIZE, UPDATE, TASK_BREAKDOWN, REBREAKDOWN, SPLIT_TASK, UPDATE_METADATA, REPAIR_STATE, CRITIQUE_TRIAGE, and CRITIQUE_BREAKDOWN. Any request specifying a mode not in this set MUST be rejected.

### INITIALIZE Mode

#### PLAN-002: Session Structure Creation
When invoked in INITIALIZE mode, the Planning Role MUST create the following artifacts:
1. The Session State Store with the session identifier, creation timestamp, update timestamp, current status set to "in_progress", and iteration set to 1.
2. The Iteration Container for iteration 1.
3. The Iteration State Store for iteration 1 with the start timestamp and planning status set to incomplete.
4. The initial Iteration Plan for iteration 1 with all mandatory sections (per PLAN-030).
5. The Progress Tracker for iteration 1 with the planning-phase task entries.
6. The Active Session Pointer (per SES-004).
7. The Lifecycle Hook Gate (per SES-005), if applicable.

#### PLAN-003: Planning-Phase Task Entries
The INITIALIZE mode MUST register exactly four planning-phase tasks in the Progress Tracker: initialization, brainstorm, research, and task breakdown. All four MUST have initial status "not-started" (per SES-015). The initialization entry MUST be marked "completed" before the mode returns.

### UPDATE Mode

#### PLAN-004: Feedback-Driven Plan Revision
When invoked in UPDATE mode, the Planning Role MUST:
1. Read all Feedback Collection artifacts (per SES-012) within the current Iteration Container.
2. Read all Discovery Records (per SES-012) within the current Iteration Container.
3. Revise the Iteration Plan to incorporate feedback and discovery outputs.
4. Include a grounding section in the revised Iteration Plan that cites the specific Discovery Record identifiers and Feedback Collection identifiers driving each decision (per PLAN-029).

#### PLAN-005: Replanning History Append
In UPDATE mode, the Planning Role MUST append a replanning history section to the Iteration Plan. This section MUST include: a feedback summary (issue counts by severity), a changes section (items removed, added, and modified), and a rationale explaining how the changes address the feedback.

#### PLAN-006: Plan Self-Validation After Update
After revising the Iteration Plan in UPDATE mode, the Planning Role MUST verify that all mandatory sections (per PLAN-030) are present. If any section is missing, the Planning Role MUST add it with a placeholder before returning.

### TASK_BREAKDOWN Mode

#### PLAN-007: Multi-Pass Breakdown Invocation
When invoked in TASK_BREAKDOWN mode, the Planning Role MUST execute the three-pass breakdown algorithm (per PLAN-034 through PLAN-037) against the current Iteration Plan and available Discovery Records.

#### PLAN-008: Task Definition Record Creation
For each task identified by the breakdown algorithm, the Planning Role MUST create a Task Definition Record (per PLAN-022 through PLAN-026) within the current Iteration Container. Every record MUST satisfy the grounding requirements (per PLAN-027, PLAN-028).

#### PLAN-009: Progress Tracker Synchronization
After creating all Task Definition Records, the Planning Role MUST update the Progress Tracker to include every created record with status "not-started", grouped by wave assignment. The set of tasks in the Progress Tracker MUST equal the set of created Task Definition Records (per SES-019).

#### PLAN-010: Wave Table Update
After wave assignment (Pass 3 of the breakdown algorithm), the Planning Role MUST update the Iteration Plan's wave section with the final wave groupings and a rationale explaining why tasks are grouped together and what dependency relationships drive the grouping.

### REBREAKDOWN Mode

#### PLAN-011: Failed Task Revision
When invoked in REBREAKDOWN mode, the Planning Role MUST:
1. Identify all Task Definition Records with "failed" status in the Progress Tracker.
2. Read the associated Feedback Collection artifacts.
3. Revise the success criteria of each failed record based on feedback.
4. Update the record's iteration and timestamp fields.
5. Reset the status of each revised record from "failed" to "not-started" in the Progress Tracker (per SES-016).

#### PLAN-012: Supplementary Record Creation
If feedback requires work beyond revising existing records, the Planning Role MUST create new Task Definition Records within the current Iteration Container. Each new record MUST satisfy all structural (PLAN-022 through PLAN-026) and grounding (PLAN-027, PLAN-028) requirements.

### REBREAKDOWN vs. SPLIT_TASK Disambiguation

#### PLAN-013: Mode Selection Criteria
REBREAKDOWN and SPLIT_TASK MUST be invoked under mutually exclusive conditions:

| Aspect | REBREAKDOWN | SPLIT_TASK |
|---|---|---|
| Trigger | Feedback-driven replanning (ORCH-013) | Timeout Recovery Escalation only (ORCH-020) |
| Scope | Batch — all failed records in the iteration | Single record — one oversized record |
| Purpose | Revise success criteria based on human feedback | Decompose one timed-out record into smaller sub-records |
| Output | Updated existing records + optional new records | New sub-records; original marked "cancelled" |

### SPLIT_TASK Mode

#### PLAN-014: Single-Record Decomposition
When invoked in SPLIT_TASK mode, the Planning Role MUST:
1. Read the target Task Definition Record identified by the Orchestration Role.
2. Decompose it into 2–4 smaller Task Definition Records with narrower objectives.
3. Preserve dependency relationships: sub-records MUST inherit the original record's dependencies, and records that depended on the original MUST depend on the appropriate sub-records.
4. Mark the original record as "cancelled" in the Progress Tracker with a decomposition indicator.

### UPDATE_METADATA Mode

#### PLAN-015: Session State Store Mutation
When invoked in UPDATE_METADATA mode, the Planning Role MUST update the Session State Store with the provided status, timestamp, and iteration values. The Planning Role MUST perform an optimistic concurrency check: if the Session State Store version has changed since reading, the mode MUST return a blocked status.

### REPAIR_STATE Mode

#### PLAN-016: Artifact Reconstruction
When invoked in REPAIR_STATE mode (per ORCH-023), the Planning Role MUST:
1. Read all existing Task Definition Records within the current Iteration Container.
2. If the Progress Tracker is missing or structurally incomplete, reconstruct it from the Task Definition Records, preserving any existing status information.
3. If the Session State Store is missing or structurally incomplete, reconstruct it by inferring state from available artifacts.
4. After repair, the Orchestration Role exits the current turn — normal processing resumes on the next invocation (per ORCH-023).

### CRITIQUE_TRIAGE Mode

#### PLAN-017: Issue Analysis and Routing
When invoked in CRITIQUE_TRIAGE mode within SESSION_CRITIQUE_REPLAN (per ORCH-027), the Planning Role MUST:
1. Read the Iteration Review Report and extract all issues grouped by severity.
2. Group issues by theme or component to identify logical fix batches.
3. Determine whether brainstorm or research cycles are needed:
   - Brainstorm is needed when issues span multiple domains or require architectural decisions not grounded in existing Discovery Records.
   - Research is needed when issues require external knowledge or verification beyond existing workspace artifacts.
   - Both are set to not-needed when issues are well-scoped targeted fixes.
4. Register the critique planning tasks in the Progress Tracker: triage (completed), optional brainstorm, optional research, and breakdown.

#### PLAN-018: Triage Return Contract
The CRITIQUE_TRIAGE mode MUST return a structured response indicating: the current iteration, the critique cycle number, whether brainstorm is needed, whether research is needed, and a summary of issue groups. The Orchestration Role uses this response to route optional Discovery Role cycles (per ORCH-027 steps 2–3).

### CRITIQUE_BREAKDOWN Mode

#### PLAN-019: Gap-Filling Record Creation
When invoked in CRITIQUE_BREAKDOWN mode within SESSION_CRITIQUE_REPLAN (per ORCH-027 step 4), the Planning Role MUST:
1. Re-parse all issues from the Iteration Review Report.
2. If Discovery Records from the current critique cycle exist, read them for additional context.
3. Group issues into logical fix batches (typically 1–4 records per cycle).
4. Create a Task Definition Record for each fix batch within the current Iteration Container.

#### PLAN-020: Critique Record Grounding
Each Task Definition Record created in CRITIQUE_BREAKDOWN mode MUST include at least one reference to an issue from the Iteration Review Report and at least one additional reference (a Discovery Record identifier from the current critique cycle if available, otherwise a second issue reference).

#### PLAN-021: Critique Record Integration
After creating gap-filling records, the Planning Role MUST add them to the Progress Tracker under the implementation section with status "not-started". The Orchestration Role transitions to BATCHING (per ORCH-010) to execute these records alongside remaining iteration work.

### Task Definition Record Structure

#### PLAN-022: Record Identity
Every Task Definition Record MUST carry a unique identifier within its Iteration Container. The identifier MUST be deterministic and non-reusable within the iteration scope.

#### PLAN-023: Record Classification
Every Task Definition Record MUST be classified as exactly one of: **Sequential** (requires ordering guarantees relative to other records) or **Parallelizable** (safe to execute concurrently with other records in the same wave).

#### PLAN-024: Record Dependency Graph
Every Task Definition Record MUST declare its dependency set — the list of record identifiers that must reach terminal "completed" status (per SES-016) before the record's execution may begin. The dependency graph MUST be acyclic. The Orchestration Role enforces this at execution time (per ORCH-014).

#### PLAN-025: Record Success Criteria
Every Task Definition Record MUST include a set of verifiable success criteria. Each criterion MUST be a testable predicate that an independent Execution Role can evaluate. Success criteria MUST NOT reference internal Planning Role state or assume knowledge of the planning process.

#### PLAN-026: Record Immutability
Task Definition Records are immutable once created, with the following exceptions:
- REBREAKDOWN mode (PLAN-011) MAY update success criteria, iteration, and timestamp fields of failed records.
- No other mode or role MAY modify an existing Task Definition Record.

### Grounding Requirements

#### PLAN-027: Grounding Mandate
Every Task Definition Record created or updated by the Planning Role MUST include a grounding section. This is a MUST-level behavioral invariant — records without grounding sections MUST NOT be accepted by the system.

#### PLAN-028: Minimum Reference Threshold
The grounding section of every Task Definition Record MUST contain at least 2 unique references, including:
- At least 1 Discovery Record identifier (referencing brainstorm, research, or analysis outputs).
- The remaining reference(s) MAY be additional Discovery Record identifiers, Feedback Collection identifiers, or other traceable source identifiers.

This threshold is the minimum enforceable contract. Planning operations SHOULD exceed the minimum when source material supports it.

#### PLAN-029: Plan-Level Grounding
When the Planning Role updates the Iteration Plan (in UPDATE or TASK_BREAKDOWN mode), the Iteration Plan MUST include a grounding section that cites the Discovery Record identifiers and Feedback Collection identifiers driving the plan's decisions. This ensures traceability from plan-level strategy to source material.

### Iteration Plan Lifecycle

#### PLAN-030: Iteration Plan Structure
Every Iteration Plan MUST include the following mandatory sections:
1. **Goal** — concise statement of what the iteration aims to achieve.
2. **Success Criteria** — measurable criteria for iteration completion.
3. **Target Artifacts** — table of artifacts the iteration will produce or modify, with expected changes.
4. **Context** — background information, source materials, and constraints.
5. **Approach** — high-level strategy and key decisions.
6. **Waves** — wave assignments populated after TASK_BREAKDOWN (placeholder during INITIALIZE).
7. **Grounding** — source citations populated after brainstorm/research (placeholder during INITIALIZE if no Discovery Records exist yet).

#### PLAN-031: Iteration Plan Mutability
The Iteration Plan is mutable within its iteration. The Planning Role MAY update the Iteration Plan in INITIALIZE, UPDATE, and TASK_BREAKDOWN modes. The Iteration Plan MUST NOT be modified by any role other than the Planning Role (per SES-012).

#### PLAN-032: Replanning History Requirement
For iterations after the first (iteration ≥ 2), the Iteration Plan MUST include a replanning history section appended by UPDATE mode (per PLAN-005). The replanning history section is omitted in the first iteration.

#### PLAN-033: Plan Self-Validation
After every mutation of the Iteration Plan (in INITIALIZE, UPDATE, or TASK_BREAKDOWN mode), the Planning Role MUST verify that all mandatory sections defined in PLAN-030 are present. Missing sections MUST be added with placeholder content before the mode returns.

### Multi-Pass Breakdown Algorithm

#### PLAN-034: Three-Pass Structure
The TASK_BREAKDOWN mode MUST execute a three-pass algorithm over the Iteration Plan and Discovery Records:
1. **Pass 1 — Task Identification**: Identify all deliverables, work units, and integration points from the Iteration Plan and available Discovery Records.
2. **Pass 2 — Dependency Analysis**: Analyze inter-task dependencies using the four sub-analyses defined in PLAN-035.
3. **Pass 3 — Wave Assignment**: Group tasks into parallel-safe waves such that all dependencies for a wave are satisfied by prior waves.

#### PLAN-035: Dependency Analysis Sub-Analyses
Pass 2 of the breakdown algorithm MUST perform the following four analyses in order:

1. **Shared Resource Detection** — Identify tasks that modify the same artifacts or shared resources. Determine whether conflicting modifications require sequential ordering or whether non-overlapping sections permit parallel execution.
2. **Read-After-Write Detection** — Map producer-consumer relationships between tasks. A task that reads output produced by another task MUST depend on the producing task.
3. **Interface/Contract Detection** — Identify tasks that define contracts (APIs, data models, protocols) consumed by other tasks. Contract-defining tasks MUST precede contract-consuming tasks.
4. **Ordering Constraint Detection** — Identify logical ordering requirements not captured by the above analyses: prerequisite knowledge, sequential workflow steps, and cross-cutting concerns.

#### PLAN-036: Wave Assignment Rules
Pass 3 MUST produce wave groups satisfying:
1. Every task in wave $N$ MUST have all its dependencies satisfied by tasks in waves $1$ through $N-1$.
2. Tasks within the same wave MUST be safe for concurrent execution (no mutual dependencies).
3. The algorithm SHOULD minimize the total number of waves to maximize parallelism.

#### PLAN-037: Parallelism Preference
When the dependency analysis is ambiguous — a dependency relationship is possible but not strictly required for correctness — the Planning Role SHOULD prefer parallelism over sequential ordering. A dependency MUST only be declared when execution order is required for correctness.

### Signal Checkpoint Integration

#### PLAN-038: Mode Start Checkpoint
Before executing any mode-specific logic, the Planning Role MUST execute the Universal Polling Routine (per SIG-019). Signal responses follow the standard behavioral semantics: STEER adjusts mode context (per SIG-002), INFO injects context (per SIG-003), PAUSE halts and preserves state (per SIG-004), ABORT finalizes and returns blocked (per SIG-005).

#### PLAN-039: Breakdown Checkpoint
Before beginning the multi-pass breakdown algorithm in TASK_BREAKDOWN mode, the Planning Role MUST execute an additional polling checkpoint. This ensures signals deposited during the planning phase (between brainstorm/research completion and breakdown start) are processed before task creation begins.

### Artifact Ownership Integration

#### PLAN-040: Planning Role mutation authority
The Planning Role has mutation authority over the following artifacts (per SES-012): Session State Store (initialization only), Iteration State Store (initialization only), Iteration Plan, Task Definition Records, Progress Tracker, Active Session Pointer (initialization only), and Lifecycle Hook Gate (initialization only). The Planning Role MUST NOT modify artifacts outside this set.

#### PLAN-041: Progress Tracker Update Discipline
When the Planning Role updates the Progress Tracker, it MUST follow the update discipline defined in SES-018: update at the start of work (marking in-progress) and at the end of work (marking the final status). The Planning Role's Progress Tracker updates are limited to planning-phase entries and task definition entries — it MUST NOT modify execution-phase or review-phase status markers owned by other roles.

## Scenarios

### SC-PLAN-001: INITIALIZE — Session Structure Creation
**Validates**: PLAN-001, PLAN-002, PLAN-003, PLAN-030, PLAN-033
```
GIVEN no active session exists
WHEN the Planning Role is invoked in INITIALIZE mode
THEN it creates the Session State Store with status "in_progress" and iteration 1
AND creates the Iteration Container for iteration 1 with Iteration State Store
AND creates the Iteration Plan with all mandatory sections (Goal, Success Criteria, Target Artifacts, Context, Approach, Waves placeholder, Grounding placeholder)
AND creates the Progress Tracker with four planning-phase entries (initialization, brainstorm, research, breakdown)
AND marks the initialization entry as "completed" before returning
AND sets the Active Session Pointer to identify this session
```

### SC-PLAN-002: UPDATE — Feedback Integration with Grounding
**Validates**: PLAN-004, PLAN-005, PLAN-029
```
GIVEN the system is in REPLANNING and Feedback Collection artifacts exist in the current Iteration Container
AND Discovery Records from brainstorm and research exist
WHEN the Planning Role is invoked in UPDATE mode
THEN it reads all Feedback Collection artifacts and Discovery Records
AND revises the Iteration Plan incorporating feedback-driven changes
AND includes a grounding section citing Discovery Record identifiers and Feedback Collection identifiers
AND appends a replanning history section with feedback summary, changes (removed/added/modified), and rationale
```

### SC-PLAN-003: UPDATE — Plan Self-Validation
**Validates**: PLAN-006, PLAN-033
```
GIVEN the Planning Role has completed an Iteration Plan revision in UPDATE mode
AND the revised plan is missing the Target Artifacts section
WHEN the Planning Role performs self-validation
THEN it detects the missing mandatory section
AND adds the Target Artifacts section with placeholder content before returning
```

### SC-PLAN-004: TASK_BREAKDOWN — Full Three-Pass Algorithm
**Validates**: PLAN-007, PLAN-034, PLAN-035, PLAN-036
```
GIVEN the system is in PLANNING and an Iteration Plan with deliverables exists
WHEN the Planning Role is invoked in TASK_BREAKDOWN mode
THEN Pass 1 identifies all deliverables and work units from the Iteration Plan
AND Pass 2 analyzes dependencies via four sub-analyses (shared resource, read-after-write, interface/contract, ordering constraints)
AND Pass 3 groups tasks into waves where every task in wave N has dependencies satisfied by waves 1 through N-1
AND tasks within the same wave have no mutual dependencies
```

### SC-PLAN-005: TASK_BREAKDOWN — Record Creation and Grounding
**Validates**: PLAN-008, PLAN-022, PLAN-023, PLAN-024, PLAN-025, PLAN-027, PLAN-028
```
GIVEN the three-pass breakdown has identified 6 tasks across 3 waves
WHEN the Planning Role creates Task Definition Records
THEN each record has a unique identifier, a classification (Sequential or Parallelizable), a dependency set, and verifiable success criteria
AND each record includes a grounding section with at least 2 unique references including at least 1 Discovery Record identifier
AND no record has a cyclic dependency
```

### SC-PLAN-006: TASK_BREAKDOWN — Progress Tracker and Wave Table Sync
**Validates**: PLAN-009, PLAN-010
```
GIVEN the Planning Role has created 6 Task Definition Records across 3 waves
WHEN it updates the Progress Tracker and Iteration Plan
THEN the Progress Tracker lists all 6 records with status "not-started" grouped by wave
AND the Iteration Plan's wave section lists all 3 waves with task groupings and dependency rationale
AND the set of tasks in the Progress Tracker equals the set of created Task Definition Records (per SES-019)
```

### SC-PLAN-007: REBREAKDOWN — Failed Task Revision
**Validates**: PLAN-011
```
GIVEN the system is in REPLANNING and the Progress Tracker contains 2 records with "failed" status
AND Feedback Collection artifacts describe the issues with these records
WHEN the Planning Role is invoked in REBREAKDOWN mode
THEN it reads the failed records and the Feedback Collection
AND revises the success criteria of each failed record based on feedback
AND updates the iteration and timestamp fields of each revised record
AND resets both records from "failed" to "not-started" in the Progress Tracker (per SES-016)
```

### SC-PLAN-008: REBREAKDOWN — Supplementary Record Creation
**Validates**: PLAN-012, PLAN-028
```
GIVEN the Planning Role is in REBREAKDOWN mode
AND feedback requires new work beyond revising the 2 failed records
WHEN the Planning Role determines a new Task Definition Record is needed
THEN it creates the record within the current Iteration Container
AND the record includes a grounding section meeting the minimum reference threshold (≥2 refs, ≥1 Discovery Record identifier)
AND the record is added to the Progress Tracker with status "not-started"
```

### SC-PLAN-009: REBREAKDOWN vs. SPLIT_TASK Disambiguation
**Validates**: PLAN-013
```
GIVEN a task has failed due to human feedback in the Feedback Collection
WHEN the Orchestration Role determines the appropriate planning mode
THEN REBREAKDOWN is selected because the trigger is feedback-driven replanning (not timeout recovery)
AND GIVEN a different task has exhausted the Timeout Recovery Escalation chain (per ORCH-019)
WHEN the Orchestration Role determines the appropriate planning mode
THEN SPLIT_TASK is selected because the trigger is timeout recovery (per ORCH-020)
```

### SC-PLAN-010: SPLIT_TASK — Single-Record Decomposition
**Validates**: PLAN-014
```
GIVEN the Orchestration Role invokes the Planning Role in SPLIT_TASK mode for a specific Task Definition Record
WHEN the Planning Role decomposes the record
THEN it creates 2–4 smaller sub-records with narrower objectives
AND sub-records inherit the original record's dependencies
AND records that previously depended on the original now depend on the appropriate sub-records
AND the original record is marked "cancelled" in the Progress Tracker with a decomposition indicator
```

### SC-PLAN-011: UPDATE_METADATA — Optimistic Concurrency
**Validates**: PLAN-015
```
GIVEN the Planning Role is invoked in UPDATE_METADATA mode
AND the Session State Store has version 3
WHEN the Planning Role reads the store, prepares the update, and re-reads before writing
AND the version is still 3
THEN the update succeeds with the new status, timestamp, and iteration values
AND GIVEN the version has changed to 4 between read and write
THEN the mode returns a blocked status indicating a concurrency conflict
```

### SC-PLAN-012: REPAIR_STATE — Progress Tracker Reconstruction
**Validates**: PLAN-016
```
GIVEN the Orchestration Role detects a structurally incomplete Progress Tracker during schema validation (per ORCH-022)
AND invokes the Planning Role in REPAIR_STATE mode (per ORCH-023)
WHEN the Planning Role reads all existing Task Definition Records in the Iteration Container
THEN it reconstructs the Progress Tracker from the records, preserving any existing status information
AND after repair, the Orchestration Role exits the current turn
```

### SC-PLAN-013: CRITIQUE_TRIAGE — Issue Analysis
**Validates**: PLAN-017, PLAN-018
```
GIVEN the system is in SESSION_CRITIQUE_REPLAN (per ORCH-027)
AND the Iteration Review Report contains 3 critical issues spanning multiple domains
WHEN the Planning Role is invoked in CRITIQUE_TRIAGE mode
THEN it groups the issues by theme
AND determines that brainstorm is needed (issues span multiple domains)
AND determines that research is not needed (issues do not require external knowledge)
AND registers critique planning tasks in the Progress Tracker: triage (completed), brainstorm, and breakdown
AND returns the structured response with brainstorm_needed=true and research_needed=false
```

### SC-PLAN-014: CRITIQUE_TRIAGE — Well-Scoped Fixes Skip Optional Steps
**Validates**: PLAN-017
```
GIVEN the Iteration Review Report contains 2 minor issues that are well-scoped targeted fixes
WHEN the Planning Role is invoked in CRITIQUE_TRIAGE mode
THEN it determines both brainstorm and research are not needed
AND registers only triage (completed) and breakdown in the Progress Tracker
AND the Orchestration Role proceeds directly to CRITIQUE_BREAKDOWN (per ORCH-027)
```

### SC-PLAN-015: CRITIQUE_BREAKDOWN — Gap-Filling Record Creation
**Validates**: PLAN-019, PLAN-020, PLAN-021
```
GIVEN the system is in SESSION_CRITIQUE_REPLAN after triage and optional discovery cycles
AND 3 issues have been triaged into 2 logical fix batches
WHEN the Planning Role is invoked in CRITIQUE_BREAKDOWN mode
THEN it creates 2 Task Definition Records within the current Iteration Container
AND each record references at least 1 issue from the Iteration Review Report and 1 additional reference
AND both records are added to the Progress Tracker with status "not-started"
AND the Orchestration Role transitions to BATCHING (per ORCH-010) to execute them
```

### SC-PLAN-016: Grounding Violation — Record Rejected
**Validates**: PLAN-027, PLAN-028
```
GIVEN the Planning Role creates a Task Definition Record during TASK_BREAKDOWN
AND the record contains only 1 reference (below the minimum threshold of 2)
WHEN the grounding requirement is evaluated
THEN the record is rejected — it MUST NOT be accepted without meeting the threshold
AND the Planning Role MUST add at least 1 additional reference before the record is valid
```

### SC-PLAN-017: Grounding Violation — Missing Discovery Record Reference
**Validates**: PLAN-028
```
GIVEN a Task Definition Record's grounding section contains 2 Feedback Collection references but zero Discovery Record references
WHEN the grounding requirement is evaluated
THEN the record violates the minimum threshold (requires ≥1 Discovery Record identifier)
AND the Planning Role MUST add at least 1 Discovery Record reference before the record is valid
```

### SC-PLAN-018: Record Immutability Enforcement
**Validates**: PLAN-026
```
GIVEN a Task Definition Record was created in TASK_BREAKDOWN mode and has status "completed"
WHEN any role attempts to modify the record outside of REBREAKDOWN mode
THEN the modification is rejected — records are immutable once created
AND GIVEN the same record has "failed" status and the Planning Role is in REBREAKDOWN mode
THEN the modification succeeds for success criteria, iteration, and timestamp fields only
```

### SC-PLAN-019: Parallelism Preference in Dependency Analysis
**Validates**: PLAN-037
```
GIVEN two tasks that could potentially share a resource but do not have a strict ordering requirement
WHEN the Planning Role evaluates dependencies in Pass 2
THEN it classifies both tasks as Parallelizable and places them in the same wave
AND does not declare a dependency between them
```

### SC-PLAN-020: Wave Assignment Correctness
**Validates**: PLAN-036
```
GIVEN task A has no dependencies, task B depends on task A, and task C depends on task B
WHEN Pass 3 assigns waves
THEN task A is assigned to wave 1
AND task B is assigned to wave 2 (dependency on wave 1 satisfied)
AND task C is assigned to wave 3 (dependency on wave 2 satisfied)
AND no two tasks with a dependency relationship share the same wave
```

### SC-PLAN-021: Signal Checkpoint — Mode Start
**Validates**: PLAN-038
```
GIVEN the Planning Role is invoked in any mode
AND a STEER signal exists in the Signal Channel (Inbound) targeted to the Planning Role
WHEN the Planning Role executes the mode start checkpoint (per SIG-019)
THEN it processes the STEER signal before beginning any mode-specific logic
AND adjusts its mode context based on the signal payload (per SIG-002)
```

### SC-PLAN-022: Signal Checkpoint — Breakdown Pre-Check
**Validates**: PLAN-039
```
GIVEN the Planning Role is in TASK_BREAKDOWN mode
AND an INFO signal was deposited in the Signal Channel during the brainstorm/research phase
WHEN the Planning Role reaches the breakdown checkpoint before Pass 1
THEN it polls and processes the INFO signal (per SIG-003)
AND incorporates the context into the breakdown algorithm
```

### SC-PLAN-023: Replanning History in Iteration 2+
**Validates**: PLAN-032
```
GIVEN the system is in iteration 2 and the Planning Role is invoked in UPDATE mode
WHEN the Iteration Plan is revised
THEN the replanning history section is present in the Iteration Plan
AND it contains the feedback summary, changes (removed/added/modified), and rationale
AND GIVEN the system is in iteration 1 and INITIALIZE mode
THEN the replanning history section is omitted from the Iteration Plan
```

### SC-PLAN-024: mutation authority Enforcement
**Validates**: PLAN-040
```
GIVEN the Planning Role is executing in TASK_BREAKDOWN mode
WHEN it needs to create Task Definition Records and update the Iteration Plan
THEN both operations succeed (Planning Role has mutation authority per SES-012)
AND WHEN it attempts to modify a Task Report (owned by the Execution and Review Roles)
THEN the modification is rejected — the Planning Role has no mutation authority over Task Reports
```

### SC-PLAN-025: Progress Tracker Update Discipline
**Validates**: PLAN-041
```
GIVEN the Planning Role begins TASK_BREAKDOWN mode
WHEN it starts breakdown work
THEN it marks the breakdown planning entry as "in-progress" in the Progress Tracker (per SES-018)
AND upon completing all Task Definition Record creation
THEN it marks the breakdown planning entry as "completed"
AND does not modify any execution-phase or review-phase status markers
```

### SC-PLAN-026: Single-Mode Enforcement
**Validates**: PLAN-001 (via SES-022)
```
GIVEN the Planning Role receives a request containing both INITIALIZE and TASK_BREAKDOWN modes
WHEN the Planning Role evaluates the request
THEN it rejects the request
AND returns an error indicating that only one mode per invocation is permitted
```

### SC-PLAN-027: Iteration Plan Mutability Boundary
**Validates**: PLAN-031
```
GIVEN the Planning Role has created an Iteration Plan in INITIALIZE mode
WHEN the Discovery Role attempts to modify the Iteration Plan
THEN the modification is rejected — only the Planning Role has mutation authority
AND WHEN the Planning Role is invoked in UPDATE mode
THEN the Iteration Plan modification succeeds
```
