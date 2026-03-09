---
domain: session
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-09T10:30:30+07:00
---

# Session Specification

## Purpose

This specification defines the foundational behavioral contracts for the multi-agent orchestration system. It establishes the abstract vocabulary, session identity model, iteration model, artifact ownership, progress tracking protocol, capability discovery protocol, and single-mode enforcement rule. All other domain specifications reference the vocabulary and ownership table defined here.

## Abstract Vocabulary Table

The following table maps implementation-specific terms to abstract behavioral terms used across all specifications. All domain specifications MUST use only the abstract terms defined in this table when referring to system artifacts.

| # | Abstract Term | Definition |
|---|---|---|
| 1 | **Session State Store** | Authoritative record of the session state machine position and session-level metadata |
| 2 | **Iteration State Store** | Timing and lifecycle metadata for a single self-contained iteration |
| 3 | **Progress Tracker** | Single source of truth for task and planning completion status within an iteration |
| 4 | **Task Definition Record** | Immutable, identity-bearing definition of a single task with dependencies and success criteria |
| 5 | **Iteration Plan** | Mutable planning artifact describing the strategy and approach for the current iteration |
| 6 | **Task Report** | Append-only record of implementation outcomes and review verdicts for a task |
| 7 | **Discovery Record** | Per-category record of questions, research findings, and analysis outputs |
| 8 | **Signal Channel (Inbound)** | Delivery channel for incoming intervention messages from external actors |
| 9 | **Signal Archive** | Storage for consumed and finalized signals after processing |
| 10 | **Knowledge Staging Area** | Session-scoped repository for merged, categorized knowledge artifacts |
| 11 | **Knowledge Extraction Area** | Iteration-scoped repository for knowledge extracted from iteration artifacts |
| 12 | **Knowledge Repository** | Workspace-level persistent knowledge base (promotion target) |
| 13 | **Iteration Review Report** | Holistic assessment of iteration outcomes produced during session review |
| 14 | **Feedback Collection** | Structured human feedback artifacts associated with an iteration |
| 15 | **Active Session Pointer** | Marker identifying the currently active session for external consumers |
| 16 | **Lifecycle Hook Gate** | Marker enabling lifecycle hook processing for the session |
| 17 | **Iteration Container** | Self-contained scope boundary holding all mutable artifacts for a single iteration |
| 18 | **Signal Acknowledgment Record** | Per-recipient acknowledgment for broadcast signals |

## Requirements

### Session Identity Model

#### SES-001: Session Identifier Format
Every session MUST have a unique identifier derived from its creation timestamp.

#### SES-002: Session Timestamps
Every session MUST record a creation timestamp and an update timestamp. The update timestamp MUST be modified whenever the Session State Store is mutated.

#### SES-003: Session Status Lifecycle
A session MUST maintain a status with exactly one of the following values at any time: `in_progress`, `completed`, or `awaiting_feedback`. Transitions MUST follow: `in_progress` → `completed` (all work finished), `in_progress` → `awaiting_feedback` (feedback requested), `awaiting_feedback` → `in_progress` (feedback received and replanning started).

#### SES-004: Active Session Pointer
Only one session MAY be active at a time. When a session is active, the Active Session Pointer MUST identify it. When a session completes, the pointer MUST be cleared.

#### SES-005: Lifecycle Hook Gate
A session MAY enable lifecycle hook processing via the Lifecycle Hook Gate. When the gate is present and the Active Session Pointer identifies a session, external lifecycle hooks MUST be permitted to finalize session state.

### Iteration Model

#### SES-006: Iteration Containment
Each iteration MUST be self-contained — all mutable iteration artifacts (Iteration Plan, Task Definition Records, Progress Tracker, Task Reports, Discovery Records, Knowledge Extraction Area, Feedback Collection) MUST reside within the Iteration Container for that iteration.

#### SES-007: Iteration Identity
Each iteration MUST have a monotonically increasing numeric identifier within its session, starting at 1.

#### SES-008: Iteration Timing
Each iteration MUST record a start timestamp in its Iteration State Store. The completion timestamp MUST be recorded when all iteration work is finished.

#### SES-009: Iteration Planning Status
Each Iteration State Store MUST track whether planning is complete and the number of defined tasks. The planning completion timestamp MUST be recorded when the planning phase finishes.

#### SES-010: Session-Level Artifacts
The Session State Store, signal-related artifacts (Signal Channel, Signal Archive, Signal Acknowledgment Records), and Knowledge Staging Area MUST reside at the session level, outside any Iteration Container.

#### SES-011: Cross-Iteration Immutability
Artifacts within a completed Iteration Container MUST NOT be modified by subsequent iterations. Subsequent iterations MUST create new artifacts within their own Iteration Container.

### Artifact Ownership Table

#### SES-012: Normative Ownership Model
The system MUST enforce the following ownership model. Only the designated owner role(s) with mutation authority MAY mutate each artifact. All other roles have read-only access unless explicitly listed.

| Abstract Artifact | mutation authority | Notes |
|---|---|---|
| Session State Store | Planning Role (init), Orchestration Role (transitions) | State machine SSOT |
| Iteration State Store | Planning Role (init), Review Role (timing updates) | Timing SSOT |
| Iteration Plan | Planning Role | Mutable per iteration |
| Task Definition Records | Planning Role | One record per task |
| Progress Tracker | Planning Role, Discovery Role, Execution Role, Review Role, Knowledge Role | SSOT for status |
| Task Reports | Execution Role, Review Role | Append-only per attempt |
| Discovery Records | Discovery Role | Per-category |
| Signal Channel (Inbound) | External Actors | Human-initiated |
| Signal Archive | Orchestration Role | Finalized signals |
| Signal Acknowledgment Records | All Roles (per-recipient) | Broadcast acks |
| Knowledge Extraction Area | Knowledge Role | Iteration-scoped |
| Knowledge Staging Area | Knowledge Role | Session-scoped |
| Knowledge Repository | Knowledge Role | Workspace-scoped |
| Iteration Review Report | Review Role | Per-iteration |
| Feedback Collection | External Actors | Structured feedback |
| Active Session Pointer | Planning Role (init), Orchestration Role (clear) | Session-level |
| Lifecycle Hook Gate | Planning Role (init) | Session-level |

#### SES-013: SSOT Principle
Each canonical fact MUST live in exactly one authoritative location. Derived views (summaries, rollups, dashboards) MUST be labeled non-authoritative and MUST be regenerable from the authoritative source.

#### SES-014: No Duplicate Status Tracking
Task status MUST be tracked exclusively in the Progress Tracker. No other artifact (including Task Definition Records or Task Reports) MAY carry authoritative status information.

### Progress Tracking Protocol

#### SES-015: Status Marker Set
The Progress Tracker MUST use exactly the following status markers: not-started, in-progress, review-pending, completed, failed, cancelled. Each task entry MUST have exactly one status marker at any time.

#### SES-016: Status Transition Rules
Status transitions MUST follow these rules:
- not-started → in-progress (when execution begins)
- in-progress → review-pending (when execution completes and awaits review)
- review-pending → completed (when review qualifies the work)
- review-pending → failed (when review rejects the work)
- not-started → cancelled (when a task is skipped)
- failed → not-started (when replanning resets a failed task)

#### SES-017: Progress Tracker Structure
The Progress Tracker MUST include: a legend defining the status markers, a planning progress section listing planning-phase tasks, and an implementation progress section listing execution-phase tasks grouped by wave.

#### SES-018: Update Discipline
Every role that updates the Progress Tracker MUST do so at the start of work (marking in-progress) and at the end of work (marking the final status). The Orchestration Role MUST NOT update the Progress Tracker — it has read-only access.

#### SES-019: Progress-Task Consistency
The set of tasks listed in the Progress Tracker MUST equal the set of Task Definition Records within the same Iteration Container. No task MAY exist in one but not the other.

### Capability Discovery Protocol

#### SES-020: Runtime Capability Loading
Every role SHOULD discover and load relevant capabilities at the start of task execution using a four-step reasoning process:
1. Check the role's own instructions for declared capability affinities
2. Check the current task context for explicitly referenced capabilities
3. Scan the available capability registry and match descriptions against current requirements
4. Load only capabilities directly relevant to the current task (typically 1–3)

#### SES-021: Degraded Mode
If the capability registry is unavailable, the role SHOULD proceed in degraded mode (skipping capability loading) rather than failing.

### Single-Mode Enforcement

#### SES-022: Single-Mode Invocation Constraint
Every role MUST accept exactly one mode of operation or one task per invocation. A role MUST reject any request that asks for multiple modes or multiple tasks in a single invocation.

### Normalization Principles

#### SES-023: Iteration-Scope Normalization
Within an Iteration Container, all mutable artifacts MUST be stored in their canonical, normalized form. Anti-patterns include: duplicating task status across multiple artifacts, maintaining conflicting summary counts, or editing derived views to fix canonical data.

#### SES-024: Session-Scope Denormalization
At the session level, non-authoritative aggregate views (rollups, summaries, completion tables) MAY be produced for human readability. These views MUST NOT influence state transitions or routing decisions.

#### SES-025: Boundary Rule
If an artifact can be regenerated from normalized sources, it MUST be labeled non-authoritative. Non-authoritative artifacts MUST carry a visible indicator that they are regenerable and not canonical.

#### SES-026: PLANNING Delegation Observability
During PLANNING, Planner-to-Questioner grounding delegation MUST be observable through iteration artifacts alone. The Progress Tracker MUST show the active discovery step through `plan-brainstorm` or `plan-research`, `plan-breakdown` MUST remain incomplete until grounding is ready, and the corresponding Discovery Record under `iterations/<N>/questions/` MUST identify the category and cycle that unblock Planner.

#### SES-027: Orchestration Read Boundary for Planning Delegation
When routing the PLANNING loop, the Orchestration Role MUST rely on the Progress Tracker and Discovery Record artifacts to determine whether discovery should continue or Planner should resume. It MUST NOT inspect unrelated workspace content to infer grounding status.

### Ralph Workflow Version Governance

#### SES-028: Canonical Ralph Workflow Version Source
For the `ralph-v2` plugin family, the canonical workflow version MUST be the shared `version` frontmatter value carried by the source Ralph agent wrapper files referenced by the source CLI and VS Code plugin manifests. The canonical workflow version is a workflow contract value, not a channel-specific publish value.

#### SES-029: Ralph Plugin Manifest Correlation
The source CLI and VS Code `plugin.json` manifests for `ralph-v2` MUST mirror the canonical Ralph workflow version for source readability. The bundled `plugin.json` emitted during build or publish MUST be stamped to the canonical Ralph workflow version before publication so the published plugin manifest and the Ralph workflow contract stay numerically aligned.

#### SES-030: Ralph Version Drift Handling
If a source `ralph-v2` plugin manifest version drifts from the canonical Ralph workflow version, build or publish automation MUST detect the drift before bundle publication, MUST stamp the bundled manifest to the canonical workflow version, and SHOULD surface the mismatch to the operator.

#### SES-031: Channel Orthogonality for Ralph Versioning
Beta and stable channel handling for `ralph-v2` MUST remain orthogonal to version governance. Channel-specific behavior MAY rewrite bundle names, install names, file names, or registration paths, but it MUST NOT change, derive, or suffix the canonical Ralph workflow version.

## Scenarios

### SC-SES-001: Session Creation
**Validates**: SES-001, SES-002, SES-003, SES-004, SES-006, SES-007, SES-008
```
GIVEN no active session exists
WHEN a new session is initialized
THEN a unique session identifier is created from the current timestamp
AND the Session State Store is created with status "in_progress"
AND the Active Session Pointer identifies this session
AND Iteration Container 1 is created with all required sub-structures
AND the Iteration State Store for iteration 1 records the start timestamp
```

### SC-SES-002: Session Status Lifecycle — Completion
**Validates**: SES-003
```
GIVEN a session with status "in_progress"
AND all tasks in the current iteration are completed or cancelled
WHEN the session review passes with no actionable issues
THEN the session status transitions to "completed"
AND the Active Session Pointer is cleared
```

### SC-SES-003: Session Status Lifecycle — Feedback Loop
**Validates**: SES-003
```
GIVEN a session with status "in_progress"
AND the current iteration has failed tasks
WHEN the iteration review identifies issues requiring human input
THEN the session status transitions to "awaiting_feedback"
AND WHEN human feedback is provided
THEN the session status transitions back to "in_progress"
AND a new Iteration Container is created for replanning
```

### SC-SES-004: Iteration Self-Containment
**Validates**: SES-006, SES-010, SES-011
```
GIVEN a session with completed iteration 1
WHEN iteration 2 is created for replanning
THEN iteration 2 has its own Iteration Plan, Task Definition Records, and Progress Tracker
AND iteration 1 artifacts are not modified
AND session-level artifacts (Session State Store, Signal Channel, Knowledge Staging Area) remain at session scope
```

### SC-SES-005: Artifact Ownership Enforcement
**Validates**: SES-012
```
GIVEN the Orchestration Role is active
WHEN it attempts to modify the Progress Tracker
THEN the modification is rejected (Orchestration Role has read-only access to Progress Tracker)
AND WHEN the Execution Role updates the Progress Tracker to mark a task in-progress
THEN the modification succeeds (Execution Role has mutation authority)
```

### SC-SES-006: SSOT Violation Detection
**Validates**: SES-013, SES-014
```
GIVEN a task with status "completed" in the Progress Tracker
WHEN a derived summary shows a conflicting status for the same task
THEN the Progress Tracker status is authoritative
AND the derived summary MUST be regenerated from the Progress Tracker
```

### SC-SES-007: Progress Tracker Update Discipline
**Validates**: SES-015, SES-016, SES-018
```
GIVEN a task with status "not-started" in the Progress Tracker
WHEN the Execution Role begins work on the task
THEN the Execution Role updates the status to "in-progress"
AND WHEN execution completes and the task is ready for review
THEN the Execution Role updates the status to "review-pending"
AND WHEN the Review Role qualifies the task
THEN the Review Role updates the status to "completed"
```

### SC-SES-008: Progress-Task Consistency Check
**Validates**: SES-019
```
GIVEN an Iteration Container with 5 Task Definition Records
WHEN the Progress Tracker lists only 4 tasks
THEN a consistency violation is detected
AND the system MUST reconcile the Progress Tracker with the Task Definition Records before proceeding
```

### SC-SES-008b: Progress Tracker Structure Validation
**Validates**: SES-017
```
GIVEN a newly created Progress Tracker for an iteration
WHEN the tracker is inspected
THEN it contains a legend section defining all six status markers
AND a planning progress section listing planning-phase tasks
AND an implementation progress section with tasks grouped by wave
```

### SC-SES-009: Capability Discovery — Happy Path
**Validates**: SES-020
```
GIVEN a role beginning task execution
AND a capability registry is available with matching capabilities
WHEN the role executes the 4-step capability discovery process
THEN it loads only the directly relevant capabilities (1-3)
AND proceeds with augmented task execution
```

### SC-SES-010: Capability Discovery — Degraded Mode
**Validates**: SES-021
```
GIVEN a role beginning task execution
AND the capability registry is unavailable
WHEN the role attempts capability discovery
THEN it logs a warning
AND proceeds in degraded mode without loaded capabilities
AND task execution is not blocked
```

### SC-SES-011: Single-Mode Enforcement
**Validates**: SES-022
```
GIVEN a role receives a request containing two modes of operation
WHEN the role evaluates the request
THEN the role rejects the request
AND returns an error indicating that only one mode per invocation is permitted
```

### SC-SES-012: Normalization — No Duplicate Status
**Validates**: SES-023, SES-014
```
GIVEN a task exists in both the Progress Tracker and a Task Definition Record
WHEN an observer queries task status
THEN only the Progress Tracker value is authoritative
AND the Task Definition Record does not carry status information
```

### SC-SES-013: Denormalization Boundary
**Validates**: SES-024, SES-025
```
GIVEN a session-level summary artifact exists
WHEN the summary shows "3 of 5 tasks completed"
AND the Progress Tracker shows "4 of 5 tasks completed"
THEN the summary is non-authoritative and must be regenerated
AND no routing decision may rely on the summary value
```

### SC-SES-014: Lifecycle Hook Finalization
**Validates**: SES-005
```
GIVEN a session with the Lifecycle Hook Gate enabled
AND the Active Session Pointer identifies the session
WHEN an external lifecycle hook fires
THEN the hook is permitted to finalize the Session State Store
AND WHEN the Lifecycle Hook Gate is absent
THEN external hooks MUST NOT modify session state
```

### SC-SES-015: Iteration Completion Timing
**Validates**: SES-008
```
GIVEN an iteration with all tasks completed or cancelled
WHEN the iteration is finalized
THEN the Iteration State Store records the completion timestamp
```

### SC-SES-016: Iteration Planning Status Tracking
**Validates**: SES-009
```
GIVEN an iteration that has just started
AND no tasks have been defined yet
WHEN the Planning Role completes task breakdown with 5 Task Definition Records
THEN the Iteration State Store records planning as complete
AND the Iteration State Store records 5 as the number of defined tasks
AND the planning completion timestamp is recorded
```

### SC-SES-017: PLANNING Delegation Is Observable From Session Artifacts
**Validates**: SES-026, SES-027
```
GIVEN the Planning Role delegated Technical grounding during PLANNING
AND `iterations/<N>/questions/technical.md` exists for the delegated cycle
WHEN the Orchestration Role evaluates whether to continue discovery or resume Planner
THEN it reads the Progress Tracker and the delegated Discovery Record only
AND it does NOT inspect unrelated workspace files to infer grounding status
AND the delegated cycle remains observable because `plan-breakdown` is still incomplete until grounding is ready
```

### SC-SES-018: Ralph Bundle Version Is Stamped From The Workflow Contract
**Validates**: SES-028, SES-029, SES-030
```
GIVEN the source `ralph-v2` agent wrapper files all declare workflow version "2.13.0"
AND a source `ralph-v2` plugin manifest is stale or missing that version
WHEN build or publish automation prepares a bundle for publication
THEN it derives the canonical Ralph workflow version from the source agent wrapper frontmatter
AND it stamps the bundled `plugin.json` version to "2.13.0" before publication
AND it surfaces the source-manifest drift to the operator
```

### SC-SES-019: Ralph Channel Naming Does Not Affect Version Stamping
**Validates**: SES-028, SES-031
```
GIVEN the canonical Ralph workflow version is "2.13.0"
WHEN the same `ralph-v2` source is bundled for both stable and beta channels
THEN the stable and beta bundles both retain plugin manifest version "2.13.0"
AND only channel-specific naming surfaces change, such as bundle names, install names, and agent file names
```
