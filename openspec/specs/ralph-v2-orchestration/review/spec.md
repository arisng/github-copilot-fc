---
domain: review
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T16:31:00+07:00
---

# Review Specification

## Purpose

This specification defines the behavioral contracts for the Review Role — the role responsible for validating task implementations, producing iteration-wide assessments, persisting qualified changes, and handling execution failures. It establishes four review modes, three review dimensions, the verdict system, the workload inference protocol, the change persistence model, the session review lifecycle, and the cross-agent normalization checklist. This specification depends on Session vocabulary (SES- prefix), Orchestration routing (ORCH- prefix), the Signal protocol (SIG- prefix), and references Execution outputs (EXEC- prefix) and Planning structures (PLAN- prefix).

## Review Modes

The Review Role operates in exactly four modes. Each mode is invoked by the Orchestration Role from a specific state. The Review Role MUST accept exactly one mode per invocation (per SES-022).

| # | Mode | Invoked From | Purpose |
|---|---|---|---|
| 1 | **TASK_REVIEW** | REVIEWING_BATCH (ORCH-008) | Validate a single task implementation against its Task Definition Record and produce a verdict |
| 2 | **SESSION_REVIEW** | SESSION_REVIEW (ORCH-009) | Produce the Iteration Review Report — a holistic assessment of iteration outcomes with issue counts by severity |
| 3 | **COMMIT** | REVIEWING_BATCH (ORCH-031) | Persist qualified task changes atomically with sub-artifact-level selective staging and conventional labeling |
| 4 | **TIMEOUT_FAIL** | REVIEWING_BATCH (ORCH-019) | Mark a task as failed when the Execution Role timed out or crashed and no Task Report was produced |

## Review Dimensions

Every TASK_REVIEW evaluation applies exactly three dimensions. Each dimension produces a per-criterion assessment that feeds the final verdict.

| # | Dimension | Definition |
|---|---|---|
| 1 | **Correctness** | The implementation accurately satisfies the intent and logic of each success criterion — no behavioral errors, no misinterpretations |
| 2 | **Completeness** | Every success criterion in the Task Definition Record has been addressed — no missing deliverables, no partially implemented criteria |
| 3 | **Quality** | The implementation meets workload-appropriate standards — structural soundness, consistency with inherited patterns, absence of regressions |

## Requirements

### Mode Enumeration

#### REV-001: Recognized Review Mode Set
The Review Role MUST recognize exactly four modes: TASK_REVIEW, SESSION_REVIEW, COMMIT, and TIMEOUT_FAIL. Any request specifying a mode not in this set MUST be rejected.

#### REV-002: Single-Mode Invocation Constraint
The Review Role MUST accept exactly one mode and exactly one task per invocation (per SES-022). A request that specifies multiple modes or multiple tasks in a single invocation MUST be rejected.

### TASK_REVIEW Mode

#### REV-003: Single-Task Scope
In TASK_REVIEW mode, the Review Role MUST validate exactly one Task Definition Record per invocation. The task is identified by the Task Identifier and Iteration parameters provided by the Orchestration Role.

#### REV-004: Three-Dimension Evaluation
The Review Role MUST evaluate every success criterion in the Task Definition Record against all three review dimensions — Correctness, Completeness, and Quality. No dimension MAY be skipped.

#### REV-005: Correctness Dimension
For each success criterion, the Review Role MUST verify that the implementation accurately satisfies the criterion's intent. Evidence MUST be gathered by inspecting the artifacts referenced in or produced by the Task Report. Claims in Part 1 of the Task Report MUST be cross-referenced against actual artifact state — the Review Role MUST NOT accept claims without verification.

#### REV-006: Completeness Dimension
The Review Role MUST verify that every success criterion listed in the Task Definition Record has been addressed. A criterion that is not mentioned in the Task Report's success criteria table is automatically assessed as not met. Partial implementations of a criterion MUST be assessed as not met unless the criterion explicitly permits incremental delivery.

#### REV-007: Quality Dimension
The Review Role MUST assess whether the implementation meets workload-appropriate standards (per REV-019 workload inference). Quality assessment includes: structural soundness of produced artifacts, consistency with patterns inherited from predecessor Task Reports (per EXEC-009), and absence of regressions relative to prior iteration state.

### Verdict System

#### REV-008: Verdict Set
The Review Role MUST produce exactly one of three verdicts for each TASK_REVIEW invocation:
- **PASS** — all success criteria are met across all three dimensions.
- **FAIL** — one or more success criteria are not met in any dimension.
- **PASS_WITH_NOTES** — all success criteria are met, but minor issues were identified that do not block acceptance.

#### REV-009: PASS Verdict Preconditions
A PASS verdict MUST be issued only when every success criterion in the Task Definition Record is assessed as met across Correctness, Completeness, and Quality, and zero issues of any severity are identified.

#### REV-010: FAIL Verdict Obligation
A FAIL verdict MUST be issued when any success criterion is assessed as not met in any dimension. The Review Role MUST provide specific rework guidance for each unmet criterion — the guidance MUST identify which dimension failed and what corrective action is expected.

#### REV-011: PASS_WITH_NOTES Conditions
A PASS_WITH_NOTES verdict MUST be issued when all success criteria are met but the Review Role has identified minor issues (such as style inconsistencies, non-blocking suggestions, or improvement opportunities). The notes MUST be recorded in the Review Report but MUST NOT block acceptance.

#### REV-012: Progress Finalization — Qualified Path
When the verdict is PASS or PASS_WITH_NOTES, the Review Role MUST update the Progress Tracker to transition the task status from review-pending to completed (per SES-016). The update MUST include the attempt number, iteration, and a completion timestamp.

#### REV-013: Progress Finalization — Failed Path
When the verdict is FAIL, the Review Role MUST update the Progress Tracker to transition the task status from review-pending to failed (per SES-016). The update MUST include the attempt number, iteration, a failure timestamp, and the failure reason.

### Task Review Workflow

#### REV-014: Six-Step Task Review Workflow
The Review Role MUST execute the following six steps in order for every TASK_REVIEW invocation:
1. **Read Context** — load the Task Definition Record, the Task Report (Part 1), the Iteration Plan, and feedback context (if applicable).
2. **Infer Workload Type** — determine the workload category from task artifacts before selecting validation approach (per REV-019).
3. **Validate Success Criteria** — evaluate each criterion against the three review dimensions with evidence verification.
4. **Run Validation** — execute workload-appropriate validation actions (per REV-020).
5. **Create Review Report** — append Part 2 to the Task Report with the structured review findings.
6. **Update Progress** — finalize the task status in the Progress Tracker based on the verdict.

#### REV-015: Context Reading — Task Definition and Report
In the Read Context step, the Review Role MUST read the Task Definition Record to extract success criteria, target artifacts, and dependencies. The Review Role MUST then read Part 1 of the Task Report and cross-reference the Execution Role's self-assessment against actual artifact state.

#### REV-016: Context Reading — Feedback Resolution
When the Iteration is greater than 1, the Read Context step MUST additionally load the Feedback Collection artifacts within the current Iteration Container and identify issues relevant to the current task. The Review Role MUST verify that each relevant feedback issue has been addressed in the implementation.

#### REV-017: Feedback Resolution Validation
For each relevant feedback issue identified in the Feedback Collection, the Review Role MUST:
1. Map the issue to the current task's scope.
2. Verify the fix described in the Task Report's feedback context section.
3. Confirm that a regression safeguard exists to prevent reintroduction of the issue.

If any relevant feedback issue is not addressed, the Review Role MUST include it as a finding in the Review Report and consider it when computing the verdict.

#### REV-018: Review Report Structure
The Review Role MUST append Part 2 of the Task Report with the following mandatory sections:
1. **Review Summary** — a brief assessment overview.
2. **Success Criteria Validation** — a table mapping each criterion to a verdict (met/not met) with the evidence reviewed.
3. **Feedback Resolution Validation** (present only when iteration is greater than 1) — a table mapping each feedback issue to its resolution status.
4. **Quality Assessment** — overall quality observations.
5. **Issues Identified** — any issues found, with descriptions and severity.
6. **Validation Actions Performed** — summary of runtime and inspection actions taken.
7. **Recommendation** — the final verdict with reasoning.
8. **Feedback for Next Attempt** (present only when verdict is FAIL) — specific rework guidance.

#### REV-019: Runtime Validation Requirement
The Review Role MUST perform runtime validation for every task, even if not explicitly requested by the Task Definition Record. The Execution Role performs design-time validation only (per EXEC-025); the Review Role owns the runtime validation boundary.

### Workload Inference Protocol

#### REV-020: Workload Type Inference
Before selecting validation actions, the Review Role MUST infer the workload type from the task's target artifacts and Task Definition Record content. The inference MUST classify the task into exactly one of the following categories:

| Category | Detection Signals |
|---|---|
| **Documentation** | Target artifacts are exclusively markup or configuration guidance files; task objective describes content authoring |
| **Frontend / UI** | Target artifacts include user interface components, visual layouts, or interactive elements |
| **Backend / Service** | Target artifacts include server-side logic, data access, API endpoints, or runtime services |
| **Script / Automation** | Target artifacts reside in automation directories or the task focuses on tooling behavior |

The inferred workload type MUST be recorded in the Review Report.

#### REV-021: Workload-to-Validation Mapping
The Review Role MUST select validation actions appropriate to the inferred workload type:

| Workload Type | Validation Approach |
|---|---|
| **Documentation** | Validate structural accuracy, internal references, guidance consistency, and criterion coverage by inspection. Interactive runtime tools (browser automation, UI testing) MUST NOT be used for documentation workloads. |
| **Frontend / UI** | Use interactive runtime tools for visual and behavioral checks when applicable. Save validation artifacts in the task-scoped verification area within the Iteration Container. |
| **Backend / Service** | Run relevant automated checks, minimal runtime verifications (service startup, endpoint responses), or command-line validation without interactive runtime tools unless explicitly required. |
| **Script / Automation** | Execute scripts in a safe, scoped manner and capture output logs in the task-scoped verification area within the Iteration Container. |

#### REV-022: Documentation Workload Guardrail
When the inferred workload type is Documentation, the Review Role MUST NOT invoke interactive runtime tools (browser automation, UI testing frameworks). Validation MUST be limited to inspection-based checks: structural accuracy, reference validity, content completeness, and criterion satisfaction.

### SESSION_REVIEW Mode

#### REV-023: Session Review Scope
In SESSION_REVIEW mode, the Review Role MUST assess the entire iteration holistically — not individual tasks. The assessment compares all task outcomes against the Iteration Plan goals to identify gaps, unaddressed issues, and quality patterns across the iteration.

#### REV-024: Artifact Reading — Iteration-Wide
The Review Role MUST read the following artifacts before producing the Iteration Review Report:
1. The Iteration Plan for the current iteration.
2. All Task Reports (both Part 1 and Part 2) within the Iteration Container.
3. All Task Definition Records within the Iteration Container.
4. The Progress Tracker for the current iteration.
5. All Feedback Collection artifacts across iterations (for feedback loop effectiveness assessment).
6. The Iteration State Store for the current iteration.

#### REV-025: Goal Achievement Assessment
The Review Role MUST evaluate each success criterion listed in the Iteration Plan and classify it as one of: Achieved (fully satisfied with evidence), Partial (partially satisfied with documented gaps), or Not Achieved (not satisfied with impact assessment). The assessment MUST include the count of goals achieved out of the total.

#### REV-026: Issue Severity Classification
The Review Role MUST categorize all issues identified during the session review into exactly three severity levels:

| Severity | Definition |
|---|---|
| **Critical** | A defect or gap that prevents the iteration goal from being met — requires immediate remediation |
| **Major** | A significant quality or completeness issue that degrades the iteration outcome — should be remediated before session closure |
| **Minor** | A non-blocking observation (style, improvement opportunity, minor inconsistency) — may be deferred |

Each issue MUST carry a unique identity, a description, the originating task reference, and an impact statement.

#### REV-027: Iteration Review Report Structure
The Review Role MUST produce the Iteration Review Report (per SES-012 ownership) with the following mandatory sections:
1. **Metadata** — iteration number, review timestamp, overall verdict, session reference.
2. **Executive Summary** — overview of iteration results (2–3 sentences).
3. **Iteration Summary** — table of all tasks with verdict, persistence status, and key issues.
4. **Goal Achievement** — table mapping each Iteration Plan success criterion to its achievement status with evidence.
5. **Quality Assessment** — rated metrics for structural quality, cross-agent consistency, validation coverage, documentation completeness, and success criteria coverage.
6. **Issues Found** — categorized by severity (Critical, Major, Minor) with unique identities.
7. **Cross-Agent Consistency** — results of the Cross-Agent Normalization Checklist (per REV-038).
8. **Persistence Summary** — table of persisted changes per task with identifiers and labels.
9. **Knowledge Artifacts** — knowledge items staged or promoted during the iteration.
10. **Feedback Loop Effectiveness** — counts of feedback batches processed, issues resolved, issues remaining, and rework cycles.
11. **Recommendations** — actionable items for the next iteration or session closure.
12. **Next Actions** — decision (continue, replan, or complete) with rationale.

#### REV-028: Session Review Output
Upon completing the Iteration Review Report, the Review Role MUST return to the Orchestration Role: the assessment (Complete or Needs Rework), the issue counts by severity (critical, major, minor, total), and the path to the review document. The Orchestration Role uses these counts with the configured severity threshold (per ORCH-024) to determine whether to enter the critique self-loop (per ORCH-009). The Review Role MUST NOT encode routing decisions inside the Iteration Review Report.

#### REV-029: Assessment Derivation
The assessment value MUST be derived as follows:
- **Complete** — the Issues Found section contains zero issues across all severity levels.
- **Needs Rework** — at least one issue exists in any severity category.

#### REV-030: Critique Cycle Awareness
The SESSION_REVIEW invocation MAY include a critique cycle counter from the Orchestration Role. The Review Role MUST echo this counter in its output. The Review Role MUST NOT use the counter to influence its assessment — it reports issues objectively and lets the Orchestration Role apply threshold logic (per ORCH-024, ORCH-025, ORCH-026).

### COMMIT Mode

#### REV-031: Change Persistence Purpose
COMMIT mode SHOULD persist qualified task changes as atomic, labeled change records. This mode is a SHOULD-level capability — runtime environments that lack version control or equivalent persistence mechanisms satisfy this requirement by documenting the persistence gap.

> **Design note**: This requirement is SHOULD-level per system design. Environments with version control capabilities MUST implement the full persistence workflow described in REV-032 through REV-037. Environments without such capabilities MUST log that persistence was skipped and return a skipped status.

#### REV-032: Pre-flight Validation
Before persisting changes, the Review Role MUST validate:
1. A persistence mechanism is available in the runtime environment.
2. Uncommitted or unpersisted changes exist for the task's target artifacts.
3. The Task Report for the task exists and contains a list of modified artifacts in Part 1.

If validation fails at any step, the Review Role MUST return an appropriate status (failed if the mechanism is unavailable, skipped if no changes exist or the artifact list is empty).

#### REV-033: Change Analysis Per Artifact
For each artifact listed in the Task Report's modified artifacts list, the Review Role MUST analyze the pending changes and classify each change unit as one of:
- **Task-Relevant** — the change directly relates to modifications described in the Task Report.
- **Unrelated** — the change does not relate to any modification described in the Task Report.
- **Ambiguous** — the change's relevance to the task cannot be determined with certainty.

Each artifact MUST receive an overall classification: all-relevant (all change units are task-relevant), mixed (some task-relevant, some unrelated), ambiguous (contains ambiguous change units), or no-changes (no pending changes detected).

#### REV-034: Selective Persistence — Sub-Artifact-Level Granularity
The Review Role MUST support sub-artifact-level selective persistence:
- **All-relevant artifacts**: The entire artifact's changes MUST be staged for persistence.
- **Mixed artifacts**: Only task-relevant change units MUST be staged; unrelated change units MUST be excluded from persistence.
- **Ambiguous artifacts**: The entire artifact's changes MUST be staged (conservative approach — prefer over-inclusion to missing changes).
- **No-changes artifacts**: MUST be skipped.

Bulk persistence of the entire workspace (staging all changes indiscriminately) is explicitly prohibited.

#### REV-035: Persistence Verification
After staging, the Review Role MUST verify:
1. Only expected artifacts are staged — artifacts not in the Task Report's modified list MUST be unstaged.
2. The scope of staged changes aligns with the Task Report's summary of changes.
3. Staged changes are consistent with the task's scope — significant mismatches MUST be logged as warnings but MUST NOT abort persistence.

#### REV-036: Conventional Labeling
Each persisted change record MUST carry a structured label consisting of:
- **Type** — inferred from the nature of the changed artifacts (e.g., feature addition, documentation update, fix, refactoring).
- **Scope** — inferred from the task scope or artifact location.
- **Subject** — a concise imperative description of the change, derived from the Task Definition Record's title.

A single task MAY produce multiple change records if the modified artifacts span distinct types. Multiple records per task is correct behavior — the Review Role MUST NOT enforce a one-record-per-task constraint.

#### REV-037: Persistence Independence from Verdict
Persistence failure MUST NOT alter the task's review verdict. If persistence fails, the qualified verdict (PASS or PASS_WITH_NOTES) MUST be preserved in the Progress Tracker. The failure MUST be reported to the Orchestration Role for retry or deferral (per ORCH-031). The Orchestration Role MUST retry once; a second failure MUST be logged but MUST NOT change the qualified verdict.

### TIMEOUT_FAIL Mode

#### REV-038: Timeout-Fail Purpose
TIMEOUT_FAIL mode MUST handle the case where the Execution Role timed out, crashed, or otherwise failed to produce a Task Report. The Review Role MUST administratively mark the task as failed so the Orchestration Role can proceed.

#### REV-039: Report Existence Check
In TIMEOUT_FAIL mode, the Review Role MUST check whether any Task Report exists for the specified task in the current Iteration Container. If no report exists, the Review Role MUST create a minimal Task Report recording the timeout event.

#### REV-040: Minimal Report Structure
The minimal Task Report created during TIMEOUT_FAIL MUST contain:
- Part 1 noting that the Execution Role failed to complete (with the reason provided by the Orchestration Role).
- Part 2 with a FAIL verdict and the reason "Execution timeout or crash — no implementation report produced."

#### REV-041: Timeout Progress Marking
The Review Role MUST update the Progress Tracker to mark the task as failed (per SES-016) with: the failure timestamp, the reason provided by the Orchestration Role, and the attempt number.

### Cross-Agent Normalization Checklist

#### REV-042: Normalization Checklist Application
During SESSION_REVIEW mode, the Review Role MUST execute the Cross-Agent Normalization Checklist to detect consistency regressions across all role artifacts within the iteration scope. The checklist results MUST be recorded in the Cross-Agent Consistency section of the Iteration Review Report (per REV-027, section 7).

#### REV-043: Seven Consistency Checks
The Cross-Agent Normalization Checklist MUST include exactly seven checks:

| # | Check | Validation |
|---|---|---|
| (a) | **Version Consistency** | All role artifact metadata version fields MUST match the target release version |
| (b) | **No Bare Artifact References** | Zero bare Progress Tracker, Iteration Plan, Task Definition Record, Discovery Record, or Task Report references MUST appear outside of path pattern examples — every reference MUST use qualified paths |
| (c) | **Knowledge Organizational Structure** | The knowledge repository organizational structure MUST match the categories defined by the Knowledge Role specification |
| (d) | **Signal Checkpoint Formatting** | All signal checkpoint blocks MUST have intact formatting — no split tokens across lines |
| (e) | **Lifecycle Hook Path Accuracy** | Lifecycle hook descriptions MUST reference current artifact paths — no stale path references |
| (f) | **Priority Count Accuracy** | Summary counts in aggregate views MUST match actual enumerated lists |
| (g) | **Explicit Version Verification** | A definitive version consistency verification MUST be executed and uniformity confirmed |

Each check MUST be reported as Pass or Fail with supporting notes.

#### REV-044: Normalization Self-Test
Before executing the normalization checklist, the Review Role SHOULD verify that each check's validation approach produces expected results against the current state. If a check's approach produces unexpected results, the Review Role MUST note the discrepancy and proceed with the remaining checks.

### Signal Checkpoint Integration

#### REV-045: Pre-Review Signal Poll
Before the Read Context step in TASK_REVIEW mode, the Review Role MUST poll the Signal Channel for pending signals using the Universal Polling Routine (per SIG-019). The role MUST process ABORT signals (per SIG-005) by returning early, PAUSE signals (per SIG-004) by waiting, STEER signals (per SIG-002) by adjusting validation context, and INFO signals (per SIG-003) by incorporating into review context.

#### REV-046: Post-Verdict Signal Poll
After computing the verdict and before finalizing the Progress Tracker update, the Review Role MUST poll the Signal Channel again. Signal handling at this checkpoint:
- **ABORT** — proceed to reporting with partial results.
- **STEER** — re-evaluate whether the verdict should change; if changed, restart from the progress update step. A maximum of two STEER re-evaluations per review cycle MUST be enforced; after the second, the Review Role MUST escalate to the Orchestration Role.
- **PAUSE** — wait for resumption.
- **INFO** — log to context.

#### REV-047: Session Review Signal Poll
At the start of SESSION_REVIEW mode, the Review Role MUST poll the Signal Channel. ABORT signals MUST cause immediate exit. PAUSE signals MUST cause the role to wait. INFO signals MUST be injected into the review context. STEER signals MUST be logged and applied to the review evaluation.

### Capability Discovery

#### REV-048: Capability Loading
The Review Role SHOULD discover and load relevant capabilities at the start of task execution using the four-step reasoning process (per SES-020). The Review Role has known affinity for change persistence capabilities (used in COMMIT mode). If the capability registry is unavailable, the role SHOULD proceed in degraded mode (per SES-021).

### Invocation Contract

#### REV-049: TASK_REVIEW Input Contract
The Review Role in TASK_REVIEW mode MUST accept input consisting of: Session Reference, Task Identifier, path to the Task Report, Iteration, and optional Orchestrator Context. These parameters correspond to the invocation performed by the Orchestration Role in REVIEWING_BATCH state (per ORCH-008).

#### REV-050: TASK_REVIEW Output Contract
Upon completing TASK_REVIEW, the Review Role MUST return: status (completed), mode (TASK_REVIEW), verdict (PASS, FAIL, or PASS_WITH_NOTES), Task Identifier, Iteration, criteria results (total, met, not-met counts), feedback resolution (issues checked, resolved, not resolved — present only when iteration is greater than 1), path to the updated Task Report, rework guidance (present only when verdict is FAIL), and an optional next-role suggestion with a forwarded message (per ORCH-016).

#### REV-051: SESSION_REVIEW Input Contract
The Review Role in SESSION_REVIEW mode MUST accept input consisting of: Session Reference, mode identifier, Iteration, optional critique cycle counter, and optional Orchestrator Context.

#### REV-052: SESSION_REVIEW Output Contract
Upon completing SESSION_REVIEW, the Review Role MUST return: status (completed), mode (SESSION_REVIEW), critique cycle counter echo, assessment (Complete or Needs Rework), issue counts by severity (critical, major, minor, total), and path to the Iteration Review Report.

#### REV-053: COMMIT Input Contract
The Review Role in COMMIT mode MUST accept input consisting of: Session Reference, mode identifier, Task Identifier, path to the Task Report, Iteration, and optional Orchestrator Context.

#### REV-054: COMMIT Output Contract
Upon completing COMMIT mode, the Review Role MUST return: status (completed), mode (COMMIT), Task Identifier, Iteration, persistence status (success, failed, or skipped), persistence summary description, and a list of persisted change records (each with identifier, label, and modified artifacts).

#### REV-055: TIMEOUT_FAIL Input Contract
The Review Role in TIMEOUT_FAIL mode MUST accept input consisting of: Session Reference, mode identifier, Task Identifier, reason for the timeout or failure, Iteration, and optional Orchestrator Context.

#### REV-056: TIMEOUT_FAIL Output Contract
Upon completing TIMEOUT_FAIL mode, the Review Role MUST return: status (completed), mode (TIMEOUT_FAIL), Task Identifier, Iteration, verdict (FAIL), and the path to the created or updated Task Report.

#### REV-057: Postconditions
After any non-error invocation, the following MUST hold:
1. The Progress Tracker reflects the updated status of the reviewed task (TASK_REVIEW, TIMEOUT_FAIL) or remains unchanged (SESSION_REVIEW, COMMIT).
2. The Task Report contains Part 2 with the review verdict and findings (TASK_REVIEW, TIMEOUT_FAIL).
3. The Iteration Review Report exists at the session level (SESSION_REVIEW).
4. Validation artifacts, if any, are stored in the task-scoped verification area within the Iteration Container.

## Scenarios

### SC-REV-001: Happy-Path Task Review — PASS
**Validates**: REV-001, REV-003, REV-004, REV-005, REV-006, REV-007, REV-008, REV-009, REV-012, REV-014, REV-015, REV-018, REV-049, REV-050, REV-057
```
GIVEN the Orchestration Role is in REVIEWING_BATCH state
AND a Task Report exists with Part 1 populated by the Execution Role
AND the Task Definition Record lists three success criteria
WHEN the Review Role is invoked in TASK_REVIEW mode with valid Session Reference, Task Identifier, and Iteration
THEN the Review Role reads the Task Definition Record and Part 1 of the Task Report
AND infers the workload type from the task's target artifacts
AND evaluates each of the three success criteria against Correctness, Completeness, and Quality
AND cross-references the Execution Role's claims against actual artifact state
AND appends Part 2 to the Task Report with the structured review findings
AND all three criteria are assessed as met with zero issues identified
AND the verdict is PASS
AND the Progress Tracker is updated from review-pending to completed with a timestamp
AND the role returns completed status with criteria results showing 3/3 met
```

### SC-REV-002: Task Review — FAIL with Rework Guidance
**Validates**: REV-008, REV-010, REV-013, REV-018
```
GIVEN a Task Definition Record with four success criteria
AND the task's implementation satisfies three criteria but fails Correctness on the fourth
WHEN the Review Role completes TASK_REVIEW evaluation
THEN the verdict is FAIL
AND the Review Report's Issues Identified section describes the Correctness failure with specific evidence
AND the Feedback for Next Attempt section provides rework guidance identifying the failed dimension and corrective action
AND the Progress Tracker is updated from review-pending to failed with a failure timestamp and reason
```

### SC-REV-003: Task Review — PASS_WITH_NOTES
**Validates**: REV-008, REV-011, REV-012
```
GIVEN a Task Definition Record with two success criteria
AND the implementation meets both criteria across all three dimensions
AND the Review Role identifies a minor style inconsistency that does not block acceptance
WHEN the Review Role computes the verdict
THEN the verdict is PASS_WITH_NOTES
AND the Review Report records the minor issue in the Issues Identified section
AND the Progress Tracker is updated from review-pending to completed (not failed)
AND the role returns the minor issue as a note in the output
```

### SC-REV-004: Feedback Resolution — Iteration 2
**Validates**: REV-016, REV-017
```
GIVEN a task in Iteration 2
AND the Feedback Collection contains two issues relevant to the current task
AND the Task Report's Part 1 describes how both issues were addressed
WHEN the Review Role validates feedback resolution
THEN it maps each feedback issue to the task scope
AND verifies the described fixes against actual artifact state
AND confirms that regression safeguards exist for both issues
AND the Feedback Resolution Validation table in Part 2 shows both issues as resolved
```

### SC-REV-005: Feedback Issue Not Addressed
**Validates**: REV-017, REV-010
```
GIVEN a task in Iteration 2
AND the Feedback Collection contains one issue relevant to the current task
AND the Task Report does not mention this issue
WHEN the Review Role validates feedback resolution
THEN the unaddressed feedback issue is recorded as an unmet finding
AND the verdict considers this finding (contributing to a FAIL verdict if no other criteria compensate)
```

### SC-REV-006: Workload Inference — Documentation Guardrail
**Validates**: REV-020, REV-021, REV-022
```
GIVEN a Task Definition Record whose target artifacts are exclusively markup files
AND the task objective describes content authoring
WHEN the Review Role infers the workload type
THEN the inferred type is Documentation
AND the Review Role validates by inspection (structural accuracy, reference validity, content completeness)
AND interactive runtime tools are NOT invoked for this task
AND the inferred workload type is recorded in the Review Report
```

### SC-REV-007: Workload Inference — Frontend with Runtime Validation
**Validates**: REV-020, REV-021
```
GIVEN a Task Definition Record whose target artifacts include user interface components
WHEN the Review Role infers the workload type
THEN the inferred type is Frontend / UI
AND the Review Role uses interactive runtime tools for visual and behavioral checks
AND validation artifacts are saved in the task-scoped verification area within the Iteration Container
```

### SC-REV-008: Session Review — Complete with No Issues
**Validates**: REV-023, REV-024, REV-025, REV-027, REV-028, REV-029, REV-042, REV-051, REV-052
```
GIVEN all tasks in the iteration have PASS or PASS_WITH_NOTES verdicts
AND all Iteration Plan goals are assessed as Achieved
WHEN the Review Role executes SESSION_REVIEW
THEN it reads all Task Reports, Task Definition Records, and the Iteration Plan
AND produces the Iteration Review Report with all mandatory sections
AND the Issues Found section contains zero entries across all severity levels
AND the assessment is "Complete"
AND the role returns issue counts of zero for critical, major, and minor
AND the Cross-Agent Normalization Checklist results are recorded in the report
```

### SC-REV-009: Session Review — Issues Found Triggering Critique Loop
**Validates**: REV-026, REV-028, REV-029, REV-030
```
GIVEN two tasks received PASS verdicts but one Iteration Plan goal is only partially achieved
AND the Review Role identifies one major issue and two minor issues
WHEN the Review Role completes SESSION_REVIEW
THEN the Issues Found section lists the major issue under Major and the two minor issues under Minor
AND the assessment is "Needs Rework"
AND the role returns issue counts: critical=0, major=1, minor=2, total=3
AND the Orchestration Role receives these counts to evaluate against the severity threshold (per ORCH-024)
AND the Review Role does NOT encode routing decisions in the Iteration Review Report
```

### SC-REV-010: Session Review — Issue Severity Classification
**Validates**: REV-026
```
GIVEN the Review Role identifies three issues during session review
AND issue A prevents the iteration goal from being met
AND issue B significantly degrades the iteration outcome but does not prevent goal achievement
AND issue C is a non-blocking style observation
WHEN the Review Role classifies issue severities
THEN issue A is classified as Critical
AND issue B is classified as Major
AND issue C is classified as Minor
AND each issue carries a unique identity, description, originating task reference, and impact statement
```

### SC-REV-011: COMMIT — Full Selective Persistence
**Validates**: REV-031, REV-032, REV-033, REV-034, REV-035, REV-036, REV-053, REV-054
```
GIVEN a task that received a PASS verdict
AND the Task Report lists three modified artifacts
AND artifact A has all task-relevant changes
AND artifact B has a mix of task-relevant and unrelated changes
AND artifact C has no pending changes
WHEN the Review Role executes COMMIT mode
THEN pre-flight validation confirms a persistence mechanism is available and changes exist
AND artifact A is classified as all-relevant and fully staged
AND artifact B is classified as mixed — only task-relevant change units are staged and unrelated units are excluded
AND artifact C is classified as no-changes and skipped
AND verification confirms only expected artifacts are staged
AND a structured label is applied (type, scope, subject)
AND the role returns persistence status "success" with the change record details
```

### SC-REV-012: COMMIT — Sub-Artifact-Level Selective Persistence
**Validates**: REV-034
```
GIVEN a modified artifact containing four change units
AND two change units relate to modifications described in the Task Report
AND one change unit is unrelated to the task
AND one change unit is ambiguous
WHEN the Review Role performs selective persistence for this artifact
THEN the two task-relevant change units are staged
AND the unrelated change unit is excluded
AND the ambiguous change unit is staged (conservative approach)
AND the resulting staged state includes three of the four change units
```

### SC-REV-013: COMMIT — Persistence Not Available
**Validates**: REV-031, REV-032
```
GIVEN a runtime environment without a persistence mechanism
WHEN the Review Role executes COMMIT mode
THEN pre-flight validation detects the missing persistence mechanism
AND the role returns persistence status "skipped" with summary "Persistence mechanism not available"
AND the task's qualified verdict is NOT altered
```

### SC-REV-014: COMMIT — Persistence Failure Does Not Alter Verdict
**Validates**: REV-037
```
GIVEN a task with a PASS verdict
AND persistence staging completes but the persistence operation fails
WHEN the Review Role handles the failure
THEN the task's PASS verdict remains in the Progress Tracker (completed status preserved)
AND the role returns persistence status "failed" with the error description
AND the Orchestration Role receives the failure for retry (per ORCH-031)
```

### SC-REV-015: COMMIT — Multiple Change Records Per Task
**Validates**: REV-036
```
GIVEN a task that modified artifacts spanning two distinct types (e.g., a feature artifact and a documentation artifact)
WHEN the Review Role executes COMMIT mode
THEN two separate change records are produced — one for each type
AND each record carries its own structured label with the appropriate type
AND the Review Role does NOT enforce a one-record-per-task constraint
```

### SC-REV-016: TIMEOUT_FAIL — No Report Exists
**Validates**: REV-038, REV-039, REV-040, REV-041, REV-055, REV-056
```
GIVEN the Execution Role timed out and no Task Report exists for the task
WHEN the Review Role is invoked in TIMEOUT_FAIL mode with the timeout reason
THEN the Review Role confirms no Task Report exists in the Iteration Container
AND creates a minimal Task Report with Part 1 noting the execution failure and Part 2 with a FAIL verdict
AND updates the Progress Tracker to failed with the timestamp and reason
AND returns completed status with verdict FAIL and the report path
```

### SC-REV-017: TIMEOUT_FAIL — Partial Report Exists
**Validates**: REV-039
```
GIVEN the Execution Role produced a partial Task Report before timing out
WHEN the Review Role checks for existing reports
THEN it detects the existing partial report
AND appends Part 2 with a FAIL verdict and the timeout reason
AND updates the Progress Tracker to failed
```

### SC-REV-018: Signal — Pre-Review ABORT
**Validates**: REV-045
```
GIVEN a pending ABORT signal exists in the Signal Channel targeting the Review Role
WHEN the Review Role polls the Signal Channel before the Read Context step
THEN the Review Role processes the ABORT signal per the Universal Polling Routine (SIG-019)
AND returns early without producing a verdict
AND does not modify the Progress Tracker
```

### SC-REV-019: Signal — Post-Verdict STEER Re-evaluation
**Validates**: REV-046
```
GIVEN the Review Role has computed a PASS verdict
AND a STEER signal arrives during the post-verdict signal poll
WHEN the Review Role processes the STEER signal
THEN it re-evaluates whether the verdict should change in light of the STEER payload
AND if the verdict changes to FAIL, restarts from the progress update step
AND the maximum of two STEER re-evaluations per review cycle is enforced
```

### SC-REV-020: Signal — Post-Verdict STEER Loop Escalation
**Validates**: REV-046
```
GIVEN the Review Role has already performed two STEER re-evaluations in the current review cycle
AND a third STEER signal arrives during the post-verdict signal poll
WHEN the Review Role detects the re-evaluation limit is reached
THEN it escalates to the Orchestration Role with a loop marker
AND does not perform a third re-evaluation
```

### SC-REV-021: Multi-Mode Rejection
**Validates**: REV-001, REV-002
```
GIVEN the Orchestration Role invokes the Review Role
WHEN the invocation specifies both TASK_REVIEW and COMMIT modes
THEN the Review Role rejects the request
AND returns a blocked status with a single-mode violation reason
```

### SC-REV-022: Cross-Agent Normalization — Version Drift Detected
**Validates**: REV-042, REV-043
```
GIVEN the SESSION_REVIEW has reached the Cross-Agent Normalization Checklist
AND role artifact metadata shows two different version values across artifacts
WHEN the Review Role executes check (a) Version Consistency
THEN the check result is Fail
AND the notes identify the inconsistent version values and affected artifacts
AND the issue is recorded in the Issues Found section of the Iteration Review Report
```

### SC-REV-023: Cross-Agent Normalization — All Checks Pass
**Validates**: REV-042, REV-043, REV-044
```
GIVEN all role artifacts have consistent versions, qualified path references, correct organizational structure, intact formatting, accurate hook paths, matching counts, and verified version uniformity
WHEN the Review Role executes all seven normalization checks
THEN all checks report Pass
AND the Cross-Agent Consistency section records seven Pass results with supporting notes
```

### SC-REV-024: Capability Discovery — COMMIT Mode Degraded
**Validates**: REV-048
```
GIVEN the capability registry is unavailable
AND the Review Role is invoked in COMMIT mode
WHEN the Review Role attempts the four-step capability discovery process
THEN the Review Role proceeds in degraded mode (per SES-021)
AND uses a fallback persistence approach with manual conventional labeling
AND does not fail the invocation due to missing capabilities
```

### SC-REV-025: Runtime Validation Performed Without Explicit Request
**Validates**: REV-019
```
GIVEN a Task Definition Record that does not explicitly request runtime validation
AND the task's target artifacts include server-side logic
WHEN the Review Role executes TASK_REVIEW
THEN the Review Role performs runtime validation regardless of the absence of an explicit request
AND the Review Report's Validation Actions Performed section records the runtime checks executed
```

### SC-REV-026: Session Review Signal — ABORT at Start
**Validates**: REV-047
```
GIVEN a pending ABORT signal exists in the Signal Channel
WHEN the Review Role begins SESSION_REVIEW and polls the Signal Channel
THEN the Review Role processes the ABORT signal and exits immediately
AND no Iteration Review Report is produced
```
