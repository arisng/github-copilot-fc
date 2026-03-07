---
domain: knowledge
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T16:37:13+07:00
---

# Knowledge Specification

## Purpose

This specification defines the behavioral contracts for the Knowledge Role — the role responsible for extracting reusable knowledge from iteration artifacts, staging it to session scope, promoting it to the workspace-level Knowledge Repository, and persisting promoted changes atomically. It establishes the four-stage knowledge pipeline, the Diátaxis classification model, the deterministic merge algorithm, three preflight gates, scope progression semantics, the skip-promotion convention, cancellation propagation, and knowledge artifact metadata. This specification depends on Session vocabulary (SES- prefix), Orchestration routing (ORCH- prefix), and the Signal protocol (SIG- prefix).

## Knowledge Pipeline

The Knowledge Role operates a four-stage pipeline. Each stage transforms knowledge between scope tiers. The Orchestration Role auto-sequences the first three stages in the KNOWLEDGE_EXTRACTION state (per ORCH-011).

| # | Stage | Scope Transition | Purpose |
|---|---|---|---|
| 1 | **EXTRACT** | Iteration → Knowledge Extraction Area | Scan iteration artifacts and identify reusable knowledge items |
| 2 | **STAGE** | Knowledge Extraction Area → Knowledge Staging Area | Merge iteration-scoped knowledge into session-scoped staging with conflict resolution |
| 3 | **PROMOTE** | Knowledge Staging Area → Knowledge Repository | Merge session-scoped knowledge into the workspace-level persistent knowledge base |
| 4 | **COMMIT** | Knowledge Repository → Version Control | Atomically persist all promoted changes |

## Diátaxis Classification Model

All knowledge artifacts MUST be classified using the Diátaxis 2×2 matrix. This taxonomy is the domain-level categorization model — it defines how knowledge is organized across all three scope tiers.

|              | **Practical**     | **Theoretical** |
|---|---|---|
| **Learning** | **Tutorials**     | **Explanation** |
| **Working**  | **How-to Guides** | **Reference**   |

| # | Category | Definition |
|---|---|---|
| 1 | **Tutorials** | Guided learning paths — teach by doing |
| 2 | **How-to Guides** | Goal-driven procedures — help accomplish a specific objective |
| 3 | **Reference** | Factual and technical lookup — state the facts |
| 4 | **Explanation** | Rationale and conceptual understanding — explain why |

## Scope Progression Model

Knowledge progresses through three scope tiers. Each tier has a distinct owner and lifecycle.

| # | Scope Tier | Abstract Artifact | Owner | Lifecycle |
|---|---|---|---|---|
| 1 | **Iteration-scoped** | Knowledge Extraction Area (per SES-012) | Knowledge Role | Created during EXTRACT; read-only after iteration completes (per SES-011) |
| 2 | **Session-scoped** | Knowledge Staging Area (per SES-010, SES-012) | Knowledge Role | Accumulates across iterations; survives iteration boundaries |
| 3 | **Workspace-scoped** | Knowledge Repository (per SES-012) | Knowledge Role | Persists beyond sessions; the promotion target |

## Requirements

### Mode Enumeration

#### KNOW-001: Recognized Knowledge Mode Set
The Knowledge Role MUST recognize exactly four modes: EXTRACT, STAGE, PROMOTE, and COMMIT. Any request specifying a mode not in this set MUST be rejected.

#### KNOW-002: Single-Mode Invocation Constraint
The Knowledge Role MUST accept exactly one mode per invocation (per SES-022). A request that specifies multiple modes in a single invocation MUST be rejected.

#### KNOW-003: Required Parameter Set
Every invocation of the Knowledge Role MUST include: Session Reference, Iteration, and Mode. The Knowledge Role MUST return a blocked status if any required parameter is missing.

#### KNOW-004: Optional Parameter Set
The Knowledge Role MAY accept the following optional parameters:
- **Orchestrator Context** — a one-hop message forwarded via the Messenger Protocol (per ORCH-016).
- **Source Iterations** — a list of iteration identifiers to stage from (STAGE mode only; defaults to the current iteration).
- **Cherry Pick** — a list of specific artifact references to stage (STAGE mode only; stages only the listed items).

### Diátaxis Classification

#### KNOW-005: Mandatory Four-Category Classification
Every knowledge artifact produced by the Knowledge Role MUST be classified into exactly one of the four Diátaxis categories: tutorials, how-to guides, reference, or explanation. A knowledge artifact MUST NOT be assigned to zero categories or to more than one category.

#### KNOW-006: Classification Consistency Across Tiers
When a knowledge artifact is staged from the Knowledge Extraction Area to the Knowledge Staging Area, and when it is promoted from the Knowledge Staging Area to the Knowledge Repository, the artifact MUST retain its original Diátaxis classification. The category MUST NOT change during scope transitions.

#### KNOW-007: Diátaxis Organizational Structure
Each scope tier (Knowledge Extraction Area, Knowledge Staging Area, Knowledge Repository) MUST maintain a four-category organizational structure corresponding to the Diátaxis taxonomy: one section each for tutorials, how-to guides, reference, and explanation.

#### KNOW-008: Sub-Category Classification (Extension Point)
Within each Diátaxis category, knowledge artifacts MAY be further organized into domain-based sub-categories. Sub-categorization is an optional enhancement — the Knowledge Role MAY apply it during PROMOTE when a sufficient density of related artifacts exists within a single category.

#### KNOW-009: Sub-Category Density Threshold
When sub-category classification is applied (per KNOW-008), the Knowledge Role MUST apply a minimum density threshold: a sub-category MUST contain at least three artifacts (including the current promotion batch) sharing the same domain before the sub-category is created. Artifacts below this threshold MUST remain at the category root.

#### KNOW-010: Sub-Category Reuse Priority
Before creating a new sub-category, the Knowledge Role MUST check for an existing sub-category in the Knowledge Repository that matches the domain of the artifact being promoted. If a match exists, the artifact MUST be placed into the existing sub-category rather than remaining at the category root.

### Knowledge Artifact Metadata

#### KNOW-011: Source Tracing Metadata
Every knowledge artifact produced during EXTRACT MUST carry metadata that traces it back to its source. The metadata MUST include:
- The Diátaxis category assignment.
- The session identifier of the originating session.
- The iteration identifier from which the artifact was extracted.
- A list of source artifact references identifying the iteration artifacts from which the knowledge was derived.
- An extraction timestamp.

#### KNOW-012: Pipeline State Metadata
Every knowledge artifact MUST carry metadata fields that track its progression through the pipeline:
- A staged indicator (whether the artifact has been merged into the Knowledge Staging Area) and a staging timestamp.
- A promoted indicator (whether the artifact has been merged into the Knowledge Repository) and a promotion timestamp.

Both indicators MUST default to their negative state upon extraction. Each indicator MUST be updated to its positive state only by the respective pipeline stage (STAGE sets the staged indicator; PROMOTE sets the promoted indicator).

#### KNOW-013: Self-Contained Body Content
The body content of every knowledge artifact MUST be authored as a standalone document. The body MUST NOT contain references to session-relative paths, session identifiers, or iteration numbers. Descriptive context MUST be used instead of concrete session references. Source traceability MUST be maintained exclusively through the metadata fields (per KNOW-011).

### Preflight Gate Protocol

#### KNOW-014: Gate-Before-Operation Principle
Before the Knowledge Role performs any read or write operation in a given pipeline stage, it MUST first execute the preflight gate associated with that stage. If the preflight gate fails validation, the Knowledge Role MUST NOT proceed with the stage and MUST return a blocked status.

#### KNOW-015: Gate 0 — Extraction Structure Preflight
Before any EXTRACT operation, the Knowledge Role MUST verify that the Knowledge Extraction Area exists within the current Iteration Container. If the structure does not exist, the Knowledge Role MUST auto-create the full Diátaxis organizational structure (per KNOW-007) within the Knowledge Extraction Area, including a manifest that tracks extracted items. Validation MUST confirm the structure exists after creation. If validation fails, the role MUST return a blocked status.

#### KNOW-016: Gate 1 — Staging Structure Preflight
Before any STAGE operation, the Knowledge Role MUST verify that the Knowledge Staging Area exists at section scope. If the structure does not exist, the Knowledge Role MUST auto-create the full Diátaxis organizational structure (per KNOW-007) within the Knowledge Staging Area, including a persistent manifest that tracks staged and promoted items across iterations. Validation MUST confirm the structure exists after creation. If validation fails, the role MUST return a blocked status.

#### KNOW-017: Gate 2 — Repository Structure Preflight
Before any PROMOTE operation, the Knowledge Role MUST verify that the Knowledge Repository exists at workspace scope. If the structure does not exist, the Knowledge Role MUST auto-create the full Diátaxis organizational structure (per KNOW-007) within the Knowledge Repository, including a navigation index. Validation MUST confirm the structure exists after creation. If validation fails, the role MUST return a blocked status.

#### KNOW-018: Preflight Idempotency
All three preflight gates MUST be idempotent. Running a gate when the target structure already exists MUST be a no-op — the gate MUST NOT modify, overwrite, or duplicate existing structures.

### EXTRACT Stage

#### KNOW-019: Evidence Collection Scope
In EXTRACT mode, the Knowledge Role MUST scan the following iteration artifacts within the current Iteration Container: Task Definition Records, Task Reports, the Iteration Plan, the Progress Tracker, and the Iteration State Store. The EXTRACT stage MUST NOT depend on an Iteration Review Report because SESSION_REVIEW occurs after the knowledge pipeline in the default iteration flow. The role MUST NOT read or write artifacts outside the current Iteration Container and the Knowledge Extraction Area.

#### KNOW-020: Reusability Filter
The Knowledge Role MUST filter collected evidence to retain only reusable knowledge: stable guidance, contracts, workflows, architectural decisions, and conventions. Transient or iteration-specific artifacts (debug logs, temporary test outputs, status-tracking artifacts) MUST be discarded.

#### KNOW-021: Write Scope — EXTRACT
In EXTRACT mode, the Knowledge Role MUST persist only to the Knowledge Extraction Area within the current Iteration Container. The role MUST NOT modify the Knowledge Staging Area or the Knowledge Repository during EXTRACT.

#### KNOW-022: Manifest Update — EXTRACT
After persisting extracted artifacts, the Knowledge Role MUST update the Knowledge Extraction Area manifest with an entry for each extracted item, including: the artifact reference, the Diátaxis category, the extraction timestamp, and the source artifact references.

#### KNOW-023: Empty Extraction — Cancellation Cascade
If the EXTRACT stage produces zero knowledge items, the Knowledge Role MUST:
1. Mark the extraction progress entry as cancelled with a note indicating empty extraction.
2. Mark the staging progress entry as cancelled.
3. Mark the promotion progress entry as cancelled.
4. Return a summary indicating zero items extracted.

This cancellation cascade prevents downstream stages from executing on empty input.

#### KNOW-024: EXTRACT Idempotency
Re-running EXTRACT on the same iteration MUST overwrite previously extracted artifacts in the Knowledge Extraction Area. The extraction timestamp MUST be updated. Existing artifacts in the Knowledge Staging Area MUST NOT be affected unless STAGE is re-run.

### STAGE Stage

#### KNOW-025: Source Iteration Resolution
In STAGE mode, the Knowledge Role MUST resolve the source iterations: use the Source Iterations parameter if provided, otherwise default to the current iteration only. Each source iteration's Knowledge Extraction Area MUST be processed sequentially.

#### KNOW-026: Cherry-Pick Filtering
When the Cherry Pick parameter is provided, the Knowledge Role MUST stage only the specified artifact references from the source iteration's Knowledge Extraction Area. All other artifacts MUST be skipped.

#### KNOW-027: Promoted Artifact Immutability
When scanning the Knowledge Staging Area, the Knowledge Role MUST skip any artifact whose promoted indicator is set to its positive state (per KNOW-012). Promoted artifacts are finalized and MUST NOT be overwritten during staging.

#### KNOW-028: Write Scope — STAGE
In STAGE mode, the Knowledge Role MUST persist only to the Knowledge Staging Area. The role MUST NOT modify the Knowledge Extraction Area or the Knowledge Repository during STAGE.

#### KNOW-029: Source Metadata Update — STAGE
For each artifact successfully staged, the Knowledge Role MUST update the source artifact's metadata in the Knowledge Extraction Area: set the staged indicator to its positive state and record the staging timestamp (per KNOW-012).

#### KNOW-030: Manifest Update — STAGE
After staging, the Knowledge Role MUST update the Knowledge Staging Area persistent manifest to reflect newly staged items, including their staging timestamps and iteration of origin.

### PROMOTE Stage

#### KNOW-031: Skip-Promotion Signal Convention
Before beginning promotion, the Knowledge Role MUST poll the Signal Channel (Inbound) (per SIG-019) for an INFO signal (per SIG-003) with a target matching the Knowledge Role and a payload carrying a recognized skip-promotion prefix (per SIG-006). If such a signal is found:
1. The signal MUST be consumed and archived (per SIG-015).
2. The promotion progress entry MUST be marked as cancelled.
3. The Knowledge Role MUST return an outcome indicating promotion was skipped.
4. Staged knowledge in the Knowledge Staging Area MUST be preserved for future manual promotion.

#### KNOW-032: Unpromoted Item Selection
In PROMOTE mode, the Knowledge Role MUST select only artifacts from the Knowledge Staging Area whose promoted indicator is in its negative state (per KNOW-012). If zero unpromoted items exist, the Knowledge Role MUST mark the promotion progress entry as cancelled with a note and return a skipped outcome.

#### KNOW-033: Write Scope — PROMOTE
In PROMOTE mode, the Knowledge Role MUST persist to the Knowledge Repository (for promoted content) and update the Knowledge Staging Area (to record promotion metadata per KNOW-012). The role MUST NOT modify the Knowledge Extraction Area during PROMOTE.

#### KNOW-034: Content Transformation on Promotion
When artifacts are promoted to the Knowledge Repository, the Knowledge Role MUST apply the following transformations:
1. Source artifact references in metadata MUST be replaced with descriptive labels (removing session-relative path references).
2. Pipeline-internal metadata fields (staged indicator, staging timestamp) MUST be removed from the promoted artifact.
3. Body content MUST be scanned for ephemeral session references (session-relative paths, session identifiers). Any found MUST be replaced with descriptive text.

#### KNOW-035: Promotion Metadata Update
For each artifact successfully promoted, the Knowledge Role MUST update the source artifact's metadata in the Knowledge Staging Area: set the promoted indicator to its positive state and record the promotion timestamp (per KNOW-012).

#### KNOW-036: Navigation Index Update
After promotion, the Knowledge Role MUST update the Knowledge Repository navigation index to reflect newly promoted content and any new sub-category structures created during sub-category resolution (per KNOW-008).

### Merge Algorithm

#### KNOW-037: Shared Merge Algorithm
Both the STAGE and PROMOTE stages MUST use the same merge algorithm when transferring knowledge artifacts between scope tiers. The merge operates per-artifact within each Diátaxis category.

#### KNOW-038: New Artifact — Direct Copy
When an artifact has no matching counterpart in the target tier (by artifact identity within the same Diátaxis category), the artifact MUST be copied directly to the target.

#### KNOW-039: Same Identity, Source Newer — Overwrite
When an artifact matches an existing artifact in the target tier by identity, and the source artifact's timestamp is newer than the target artifact's timestamp, the source MUST overwrite the target.

#### KNOW-040: Same Identity, Target Newer — Skip
When an artifact matches an existing artifact in the target tier by identity, and the target artifact's timestamp is newer than the source artifact's timestamp, the source artifact MUST be skipped. The target MUST remain unchanged.

#### KNOW-041: Content Overlap — Append Unique Sections
When two artifacts have different identities but reside in the same Diátaxis category, and structural heading comparison (per KNOW-042) detects greater than 50% overlap, the Knowledge Role MUST append only the unique sections from the source artifact to the target artifact.

#### KNOW-042: Structural Heading Overlap Detection
To detect content overlap, the Knowledge Role MUST compare second-level and third-level structural headings between the source artifact and every artifact in the same Diátaxis category within the target tier:
- Extract all second-level and third-level headings from both the source and target artifacts.
- If more than 50% of the source artifact's headings already exist in any single target artifact, content overlap is detected.
- If a shared heading contains different body content between source and target, a contradiction is detected.

This is a structural heuristic, not a semantic comparison. The threshold is deliberately set above 50% to minimize false positives, which would cause content loss. False negatives (missed overlap) result in near-duplicate content that can be resolved manually.

#### KNOW-043: Contradictory Content — Newer Wins
When a contradiction is detected (same heading, different content), the newer artifact's version of the contradicted section MUST replace the older version entirely. The prior version MUST be noted in the merge log.

#### KNOW-044: Merge Logging
Every merge operation MUST produce a log entry recording: the artifact identity, the merge case applied (new, overwrite, skip, append, contradiction), and any conflict details. This log MUST be included in the stage's return summary to the Orchestration Role.

### COMMIT Stage

#### KNOW-045: Orchestrator-Initiated Invocation
The COMMIT stage MUST only be invoked by the Orchestration Role after a successful PROMOTE stage. COMMIT MUST NOT be self-initiated by the Knowledge Role.

#### KNOW-046: Commit Scope Determination
In COMMIT mode, the Knowledge Role MUST identify all promoted artifacts in the Knowledge Repository that have uncommitted changes. The commit scope MUST be limited to: artifacts whose identity matches a promoted item in the Knowledge Staging Area manifest, plus the Knowledge Repository navigation index if it has uncommitted changes.

#### KNOW-047: Selective Staging
The Knowledge Role MUST stage only the artifacts identified in the commit scope (per KNOW-046) for version control. The role MUST NOT stage all changes indiscriminately. If unexpected artifacts are found in the staging area, they MUST be removed from the commit scope.

#### KNOW-048: Atomic Commit Execution
The Knowledge Role SHOULD use a capability for atomic, conventionally-labeled commits (per SES-020) if available. If the capability is unavailable, the Knowledge Role MUST fall back to a single commit with a descriptive label. The commit MUST include only the scoped artifacts.

#### KNOW-049: Commit Failure Independence
A failure during COMMIT MUST NOT retroactively affect the PROMOTE outcome. Artifacts already marked as promoted in the Knowledge Staging Area manifest MUST retain their promoted status. The failure MUST be reported to the Orchestration Role for retry or deferral.

### Knowledge Progress Tracking

#### KNOW-050: Three Progress Entries
The Knowledge Role MUST maintain three progress entries in the Progress Tracker (per SES-018) for the knowledge pipeline:
1. An extraction progress entry (for EXTRACT mode).
2. A staging progress entry (for STAGE mode).
3. A promotion progress entry (for PROMOTE mode).

#### KNOW-051: Progress Initialization Idempotency
The Knowledge Role MUST initialize the three progress entries before any pipeline stage begins. Initialization MUST be idempotent — if the entries already exist, the role MUST NOT duplicate or overwrite them.

#### KNOW-052: Cancellation Semantics
When a pipeline stage is bypassed (empty extraction per KNOW-023, skip-promotion signal per KNOW-031, or zero unpromoted items per KNOW-032), the corresponding progress entry and all downstream progress entries MUST be marked as cancelled with a descriptive note.

### Signal Integration

#### KNOW-053: Signal Polling at Stage Boundaries
The Knowledge Role MUST poll the Signal Channel (Inbound) (per SIG-019, SIG-021) at the following checkpoints:
1. Before beginning any pipeline stage (initialization checkpoint).
2. After evidence collection in EXTRACT mode (post-collection checkpoint).
3. After reading staged content in PROMOTE mode (post-collection checkpoint).

#### KNOW-054: Signal Response Behavior
At each polling checkpoint, the Knowledge Role MUST respond to signals according to the Signal protocol:
- **ABORT** (per SIG-005): Return a blocked status immediately.
- **PAUSE** (per SIG-004): Halt at the current safe boundary and preserve state.
- **STEER** (per SIG-002): Adjust the scope or criteria of the current pipeline stage.
- **INFO** (per SIG-003): Append the payload to the active context and continue.

#### KNOW-055: Broadcast Acknowledgment
When the Knowledge Role encounters a broadcast signal (target ALL), it MUST create a Signal Acknowledgment Record (per SIG-011) and MUST NOT remove the signal from the Signal Channel (Inbound).

### Cross-Iteration Staging

#### KNOW-056: Multi-Iteration Source Processing
When the Source Iterations parameter specifies multiple iterations, the Knowledge Role MUST process each iteration's Knowledge Extraction Area sequentially, applying the merge algorithm (per KNOW-037 through KNOW-044) against the accumulating Knowledge Staging Area. Earlier iterations are processed before later iterations.

### Pipeline Orchestration Integration

#### KNOW-057: KNOWLEDGE_EXTRACTION State Routing
The Orchestration Role MUST invoke the Knowledge Role in the KNOWLEDGE_EXTRACTION state before SESSION_REVIEW (per ORCH-011). The default invocation sequence MUST be EXTRACT → STAGE → PROMOTE. The Orchestration Role MUST auto-sequence all three stages unless the pipeline is interrupted by a signal or cancellation cascade.

#### KNOW-058: Pipeline Completion Guard
The transition from KNOWLEDGE_EXTRACTION to SESSION_REVIEW (per ORCH-011) MUST occur when:
- The Knowledge Role is unavailable (conditional skip), OR
- The EXTRACT stage returns zero items (cancellation cascade per KNOW-023), OR
- All three stages (EXTRACT, STAGE, PROMOTE) have completed.

#### KNOW-059: Replanning Fast-Path Promotion
The Knowledge Role MAY be invoked in PROMOTE mode directly from the REPLANNING state (per ORCH-013) for knowledge-promotion fast-path, bypassing EXTRACT and STAGE. In this case, the Knowledge Role promotes already-staged artifacts from the Knowledge Staging Area.

## Scenarios

### SC-KNOW-001: Mode Validation — Recognized Mode
**Validates**: KNOW-001
```
GIVEN the Knowledge Role receives a request with mode EXTRACT
WHEN the role validates the mode
THEN the role accepts the mode and proceeds with the EXTRACT pipeline stage
```

### SC-KNOW-002: Mode Validation — Unrecognized Mode
**Validates**: KNOW-001
```
GIVEN the Knowledge Role receives a request with mode CURATE
WHEN the role validates the mode
THEN the role rejects the request
AND returns an error indicating the mode is not in the recognized set
```

### SC-KNOW-003: Single-Mode Enforcement
**Validates**: KNOW-002
```
GIVEN the Knowledge Role receives a request specifying both EXTRACT and STAGE modes
WHEN the role evaluates the request
THEN the role rejects the request
AND returns an error indicating only one mode per invocation is permitted
```

### SC-KNOW-004: Missing Required Parameter
**Validates**: KNOW-003
```
GIVEN the Knowledge Role receives a request with mode EXTRACT but no Iteration parameter
WHEN the role validates the parameters
THEN the role returns a blocked status indicating the missing required parameter
```

### SC-KNOW-005: Diátaxis Classification — Single Category Assignment
**Validates**: KNOW-005
```
GIVEN a knowledge artifact is identified during EXTRACT
WHEN the Knowledge Role classifies the artifact
THEN the artifact is assigned to exactly one Diátaxis category
AND the artifact is not assigned to zero or more than one category
```

### SC-KNOW-006: Classification Preserved Across Tiers
**Validates**: KNOW-006
```
GIVEN a knowledge artifact classified as "reference" exists in the Knowledge Extraction Area
WHEN the artifact is staged to the Knowledge Staging Area
AND later promoted to the Knowledge Repository
THEN the artifact retains its "reference" classification at each tier
```

### SC-KNOW-007: Organizational Structure at Each Tier
**Validates**: KNOW-007
```
GIVEN the Knowledge Extraction Area is being initialized for an iteration
WHEN the preflight gate creates the structure
THEN the structure includes four category sections: tutorials, how-to guides, reference, and explanation
```

### SC-KNOW-008: Sub-Category Creation — Sufficient Density
**Validates**: KNOW-008, KNOW-009
```
GIVEN the Knowledge Repository reference category contains 2 existing artifacts with domain "api"
AND the current promotion batch includes 1 artifact also with domain "api"
WHEN the Knowledge Role applies sub-category classification during PROMOTE
THEN a sub-category for domain "api" is created within the reference category
AND all 3 artifacts (2 existing + 1 new) are placed into the sub-category
```

### SC-KNOW-009: Sub-Category Creation — Insufficient Density
**Validates**: KNOW-009
```
GIVEN the Knowledge Repository reference category contains 0 existing artifacts with domain "api"
AND the current promotion batch includes 1 artifact with domain "api"
WHEN the Knowledge Role applies sub-category classification during PROMOTE
THEN no sub-category is created
AND the artifact remains at the reference category root
```

### SC-KNOW-010: Sub-Category Reuse
**Validates**: KNOW-010
```
GIVEN the Knowledge Repository already has a sub-category "api" within the reference category
AND a new artifact with domain "api" is being promoted
WHEN the Knowledge Role evaluates sub-category placement
THEN the artifact is placed into the existing "api" sub-category
AND no new sub-category is created
```

### SC-KNOW-011: Source Tracing Metadata Completeness
**Validates**: KNOW-011
```
GIVEN a knowledge artifact is extracted during EXTRACT
WHEN the Knowledge Role writes the artifact to the Knowledge Extraction Area
THEN the artifact's metadata includes the Diátaxis category, session identifier, iteration identifier, source artifact references, and extraction timestamp
```

### SC-KNOW-012: Pipeline State Metadata Lifecycle
**Validates**: KNOW-012
```
GIVEN a knowledge artifact is extracted with staged and promoted indicators in their negative states
WHEN the artifact is staged to the Knowledge Staging Area
THEN the staged indicator is set to its positive state and the staging timestamp is recorded
AND the promoted indicator remains in its negative state
AND WHEN the artifact is later promoted to the Knowledge Repository
THEN the promoted indicator is set to its positive state and the promotion timestamp is recorded
```

### SC-KNOW-013: Self-Contained Body Content
**Validates**: KNOW-013
```
GIVEN a knowledge artifact is being written during EXTRACT
AND the source evidence refers to a specific iteration task
WHEN the Knowledge Role authors the body content
THEN the body uses descriptive context (e.g., "during the rename cascade task")
AND does not contain session-relative paths, session identifiers, or iteration numbers
AND source traceability is maintained exclusively through metadata fields
```

### SC-KNOW-014: Preflight Gate — Extraction Structure Auto-Create
**Validates**: KNOW-014, KNOW-015
```
GIVEN no Knowledge Extraction Area exists within the current Iteration Container
WHEN the Knowledge Role begins EXTRACT mode
THEN the preflight gate auto-creates the full Diátaxis organizational structure in the Knowledge Extraction Area
AND creates a manifest for tracking extracted items
AND validates the structure exists after creation
AND proceeds with the EXTRACT stage
```

### SC-KNOW-015: Preflight Gate — Staging Structure Auto-Create
**Validates**: KNOW-014, KNOW-016
```
GIVEN no Knowledge Staging Area exists at session scope
WHEN the Knowledge Role begins STAGE mode
THEN the preflight gate auto-creates the full Diátaxis organizational structure in the Knowledge Staging Area
AND creates a persistent manifest for tracking staged and promoted items
AND validates the structure exists after creation
AND proceeds with the STAGE stage
```

### SC-KNOW-016: Preflight Gate — Repository Structure Auto-Create
**Validates**: KNOW-014, KNOW-017
```
GIVEN no Knowledge Repository exists at workspace scope
WHEN the Knowledge Role begins PROMOTE mode
THEN the preflight gate auto-creates the full Diátaxis organizational structure in the Knowledge Repository
AND creates a navigation index
AND validates the structure exists after creation
AND proceeds with the PROMOTE stage
```

### SC-KNOW-017: Preflight Gate — Validation Failure Blocks Stage
**Validates**: KNOW-014
```
GIVEN the Knowledge Role executes the staging preflight gate
AND the auto-creation step completes
WHEN post-creation validation fails (structure does not exist)
THEN the Knowledge Role returns a blocked status
AND does not proceed with the STAGE stage
```

### SC-KNOW-018: Preflight Gate — Idempotency
**Validates**: KNOW-018
```
GIVEN the Knowledge Extraction Area already exists with a valid Diátaxis structure
WHEN the Knowledge Role re-runs the extraction preflight gate
THEN the existing structure is not modified, overwritten, or duplicated
AND the gate passes validation
```

### SC-KNOW-019: EXTRACT — Evidence Collection and Filtering
**Validates**: KNOW-019, KNOW-020
```
GIVEN the current Iteration Container contains Task Definition Records, Task Reports, an Iteration Plan, and temporary test outputs
WHEN the Knowledge Role executes EXTRACT
THEN the role scans all Task Definition Records, Task Reports, and the Iteration Plan
AND filters out temporary test outputs as transient
AND retains only reusable knowledge items
```

### SC-KNOW-020: EXTRACT — Write Scope Enforcement
**Validates**: KNOW-021
```
GIVEN the Knowledge Role is executing in EXTRACT mode
WHEN the role writes extracted artifacts
THEN all writes go to the Knowledge Extraction Area within the current Iteration Container
AND no writes go to the Knowledge Staging Area or the Knowledge Repository
```

### SC-KNOW-021: EXTRACT — Empty Extraction Cancellation Cascade
**Validates**: KNOW-023, KNOW-052
```
GIVEN the Knowledge Role executes EXTRACT on an iteration
AND the reusability filter produces zero items
WHEN the Knowledge Role finalizes the EXTRACT stage
THEN the extraction progress entry is marked as cancelled with note "empty extraction"
AND the staging progress entry is marked as cancelled
AND the promotion progress entry is marked as cancelled
AND the return summary indicates zero items extracted
```

### SC-KNOW-022: EXTRACT — Idempotent Re-Run
**Validates**: KNOW-024
```
GIVEN the Knowledge Role previously extracted 3 artifacts in iteration 2
WHEN the Knowledge Role re-runs EXTRACT on iteration 2
THEN the Knowledge Extraction Area is overwritten with the new extraction results
AND extraction timestamps are updated
AND the Knowledge Staging Area is not affected
```

### SC-KNOW-023: STAGE — Default Source Resolution
**Validates**: KNOW-025
```
GIVEN the Knowledge Role is invoked in STAGE mode for iteration 3
AND no Source Iterations parameter is provided
WHEN the role resolves source iterations
THEN the role defaults to staging from iteration 3 only
```

### SC-KNOW-024: STAGE — Cherry-Pick Filtering
**Validates**: KNOW-026
```
GIVEN the Knowledge Extraction Area for iteration 2 contains 5 artifacts
AND the Cherry Pick parameter specifies 2 artifact references
WHEN the Knowledge Role executes STAGE
THEN only the 2 specified artifacts are staged
AND the remaining 3 artifacts are skipped
```

### SC-KNOW-025: STAGE — Promoted Artifact Skipped
**Validates**: KNOW-027
```
GIVEN the Knowledge Staging Area contains an artifact with its promoted indicator in the positive state
AND a newer version of the same artifact exists in the Knowledge Extraction Area
WHEN the Knowledge Role executes STAGE
THEN the promoted artifact in the Knowledge Staging Area is not overwritten
AND the source artifact is skipped
```

### SC-KNOW-026: STAGE — Write Scope Enforcement
**Validates**: KNOW-028
```
GIVEN the Knowledge Role is executing in STAGE mode
WHEN the role writes staged artifacts
THEN all writes go to the Knowledge Staging Area
AND no writes go to the Knowledge Extraction Area or the Knowledge Repository
```

### SC-KNOW-027: PROMOTE — Skip-Promotion Signal Opt-Out
**Validates**: KNOW-031
```
GIVEN the Knowledge Role begins PROMOTE mode
AND an INFO signal exists in the Signal Channel (Inbound) targeting the Knowledge Role with a skip-promotion payload prefix
WHEN the Knowledge Role polls for signals before promotion
THEN the signal is consumed and archived
AND the promotion progress entry is marked as cancelled
AND the Knowledge Role returns an outcome indicating promotion was skipped
AND staged artifacts in the Knowledge Staging Area are preserved
```

### SC-KNOW-028: PROMOTE — No Unpromoted Items
**Validates**: KNOW-032
```
GIVEN the Knowledge Role begins PROMOTE mode
AND all artifacts in the Knowledge Staging Area have their promoted indicator in a positive state
WHEN the Knowledge Role selects unpromoted items
THEN zero items are selected
AND the promotion progress entry is marked as cancelled with note "no staged items to promote"
AND the Knowledge Role returns a skipped outcome
```

### SC-KNOW-029: Content Transformation on Promotion
**Validates**: KNOW-034
```
GIVEN a staged artifact in the Knowledge Staging Area contains session-relative path references in metadata and ephemeral session references in body content
WHEN the Knowledge Role promotes the artifact to the Knowledge Repository
THEN metadata source references are replaced with descriptive labels
AND pipeline-internal metadata fields are removed from the promoted artifact
AND ephemeral session references in body content are replaced with descriptive text
```

### SC-KNOW-030: Merge — New Artifact
**Validates**: KNOW-037, KNOW-038
```
GIVEN the target tier contains no artifact matching the source artifact's identity in the same Diátaxis category
WHEN the merge algorithm processes the source artifact
THEN the artifact is copied directly to the target tier
AND the merge log records "added"
```

### SC-KNOW-031: Merge — Same Identity, Source Newer
**Validates**: KNOW-037, KNOW-039
```
GIVEN the target tier contains an artifact with the same identity as the source
AND the source artifact's timestamp is newer than the target's timestamp
WHEN the merge algorithm processes the source artifact
THEN the source overwrites the target
AND the merge log records "auto-resolved: newer source replaces older target"
```

### SC-KNOW-032: Merge — Same Identity, Target Newer
**Validates**: KNOW-037, KNOW-040
```
GIVEN the target tier contains an artifact with the same identity as the source
AND the target artifact's timestamp is newer than the source's timestamp
WHEN the merge algorithm processes the source artifact
THEN the source artifact is skipped
AND the target remains unchanged
AND the merge log records "skipped: target version is newer"
```

### SC-KNOW-033: Merge — Content Overlap Detected
**Validates**: KNOW-037, KNOW-041, KNOW-042
```
GIVEN two artifacts with different identities exist in the same Diátaxis category
AND more than 50% of the source artifact's second-level and third-level headings match headings in the target artifact
WHEN the merge algorithm processes the source artifact
THEN only the unique sections from the source are appended to the target
AND the merge log records the number of unique sections appended
```

### SC-KNOW-034: Merge — Content Overlap Below Threshold
**Validates**: KNOW-042
```
GIVEN two artifacts with different identities exist in the same Diátaxis category
AND exactly 50% of the source artifact's headings match headings in the target artifact
WHEN the merge algorithm evaluates overlap
THEN content overlap is NOT detected (the threshold requires more than 50%)
AND the source artifact is treated as a new artifact
```

### SC-KNOW-035: Merge — Contradiction Resolution
**Validates**: KNOW-043
```
GIVEN two artifacts share a structural heading
AND the body content under that heading differs between source and target
AND the source artifact is newer than the target
WHEN the merge algorithm detects the contradiction
THEN the source version of the contradicted section replaces the target version entirely
AND the prior target version is noted in the merge log
```

### SC-KNOW-036: COMMIT — Scope Limited to Promoted Artifacts
**Validates**: KNOW-045, KNOW-046
```
GIVEN the PROMOTE stage has completed successfully
AND the Knowledge Repository contains 3 newly promoted artifacts and one previously committed artifact
WHEN the Orchestration Role invokes the Knowledge Role in COMMIT mode
THEN the commit scope includes only the 3 newly promoted artifacts and the navigation index (if changed)
AND the previously committed artifact is excluded from the commit scope
```

### SC-KNOW-037: COMMIT — Selective Staging
**Validates**: KNOW-047
```
GIVEN the commit scope contains 3 promoted artifacts
AND the workspace also has unrelated uncommitted changes outside the Knowledge Repository
WHEN the Knowledge Role stages artifacts for commit
THEN only the 3 promoted artifacts (and the navigation index if changed) are staged
AND unrelated changes are not included in the commit
```

### SC-KNOW-038: COMMIT — Failure Independence
**Validates**: KNOW-049
```
GIVEN the PROMOTE stage completed successfully and marked 3 artifacts as promoted
WHEN the COMMIT stage fails due to a version control error
THEN the 3 artifacts retain their promoted status in the Knowledge Staging Area manifest
AND the failure is reported to the Orchestration Role for retry
AND no promoted metadata is reverted
```

### SC-KNOW-039: Progress — Three Entries Per Iteration
**Validates**: KNOW-050, KNOW-051
```
GIVEN the Knowledge Role begins the EXTRACT stage for iteration 2
AND no knowledge progress entries exist in the Progress Tracker
WHEN the Knowledge Role initializes progress
THEN three entries are created: extraction, staging, and promotion
AND all three have initial status "not-started"
AND WHEN the Knowledge Role re-initializes progress (e.g., during a standalone PROMOTE invocation)
THEN the existing entries are not duplicated or overwritten
```

### SC-KNOW-040: Signal — ABORT Before EXTRACT
**Validates**: KNOW-053, KNOW-054
```
GIVEN an ABORT signal exists in the Signal Channel (Inbound)
AND the Knowledge Role is about to begin EXTRACT mode
WHEN the Knowledge Role polls at the initialization checkpoint
THEN the Knowledge Role returns a blocked status immediately
AND does not perform any extraction
```

### SC-KNOW-041: Signal — STEER After Evidence Collection
**Validates**: KNOW-053, KNOW-054
```
GIVEN the Knowledge Role has collected evidence during EXTRACT
AND a STEER signal exists in the Signal Channel (Inbound) adjusting the extraction scope
WHEN the Knowledge Role polls at the post-collection checkpoint
THEN the Knowledge Role re-filters the collected evidence based on the STEER payload
AND continues extraction with the adjusted scope
```

### SC-KNOW-042: Broadcast Signal Acknowledgment
**Validates**: KNOW-055
```
GIVEN a broadcast signal (target ALL) exists in the Signal Channel (Inbound)
WHEN the Knowledge Role polls and finds the signal
THEN the Knowledge Role creates a Signal Acknowledgment Record for itself
AND does not remove the signal from the Signal Channel (Inbound)
```

### SC-KNOW-043: Cross-Iteration Staging — Sequential Processing
**Validates**: KNOW-056
```
GIVEN the Source Iterations parameter specifies iterations [1, 2, 3]
WHEN the Knowledge Role executes STAGE
THEN iteration 1's Knowledge Extraction Area is processed first against the Knowledge Staging Area
AND iteration 2's area is processed second against the accumulated staging state
AND iteration 3's area is processed third
AND the merge algorithm is applied at each step
```

### SC-KNOW-044: Pipeline Completion — Cancellation Path
**Validates**: KNOW-057, KNOW-058
```
GIVEN the Orchestration Role is in the KNOWLEDGE_EXTRACTION state
AND the Knowledge Role's EXTRACT stage returns zero items
WHEN the Orchestration Role evaluates the pipeline completion guard
THEN the Orchestration Role transitions to SESSION_REVIEW (per ORCH-011)
AND does not invoke STAGE or PROMOTE
```

### SC-KNOW-045: Pipeline Completion — Full Path
**Validates**: KNOW-057, KNOW-058
```
GIVEN the Orchestration Role is in the KNOWLEDGE_EXTRACTION state
AND the Knowledge Role completes EXTRACT with 3 items, STAGE with 3 items staged, and PROMOTE with 3 items promoted
WHEN the Orchestration Role evaluates the pipeline completion guard
THEN the Orchestration Role transitions to SESSION_REVIEW
```

### SC-KNOW-046: Replanning Fast-Path Promotion
**Validates**: KNOW-059
```
GIVEN the Orchestration Role is in the REPLANNING state
AND the Planning Role has triaged feedback intent as knowledge-promotion fast-path
WHEN the Orchestration Role invokes the Knowledge Role in PROMOTE mode directly
THEN the Knowledge Role promotes already-staged artifacts from the Knowledge Staging Area
AND does not require a prior EXTRACT or STAGE invocation in this iteration
```

### SC-KNOW-047: Merge Logging Completeness
**Validates**: KNOW-044
```
GIVEN the Knowledge Role completes a STAGE operation that involves 1 new artifact, 1 overwrite, 1 skip, and 1 content overlap merge
WHEN the staging summary is returned to the Orchestration Role
THEN the merge log contains 4 entries — one per artifact — each recording the artifact identity, the merge case applied, and any conflict details
```

### SC-KNOW-048: Navigation Index Updated After Promotion
**Validates**: KNOW-036
```
GIVEN the Knowledge Role promotes 2 artifacts to the Knowledge Repository
AND one artifact triggers the creation of a new sub-category
WHEN the PROMOTE stage completes
THEN the Knowledge Repository navigation index is updated to include the newly promoted content
AND the new sub-category is reflected in the navigation index
```

### SC-KNOW-049: Optional Parameters — Cherry Pick and Source Iterations
**Validates**: KNOW-004
```
GIVEN the Knowledge Role is invoked in STAGE mode
AND the request includes both Source Iterations [1, 2] and Cherry Pick with 2 artifact references
WHEN the Knowledge Role processes the parameters
THEN it resolves source iterations as [1, 2] instead of the default
AND filters each iteration's artifacts to only the cherry-picked references
```

### SC-KNOW-050: Manifest Update After Extraction
**Validates**: KNOW-022
```
GIVEN the Knowledge Role extracts 3 artifacts during EXTRACT
WHEN the role updates the Knowledge Extraction Area manifest
THEN the manifest contains 3 entries — one per artifact
AND each entry includes the artifact reference, Diátaxis category, extraction timestamp, and source artifact references
```

### SC-KNOW-051: Source Metadata Updated After Staging
**Validates**: KNOW-029
```
GIVEN the Knowledge Role successfully stages an artifact from the Knowledge Extraction Area to the Knowledge Staging Area
WHEN the staging completes for that artifact
THEN the source artifact's metadata in the Knowledge Extraction Area is updated: staged indicator set to positive, staging timestamp recorded
```

### SC-KNOW-052: Staging Manifest Updated
**Validates**: KNOW-030
```
GIVEN the Knowledge Role stages 2 new artifacts and merges 1 existing artifact during STAGE
WHEN the staging operation completes
THEN the Knowledge Staging Area persistent manifest reflects all 3 items with their staging timestamps and origin iteration identifiers
```

### SC-KNOW-053: PROMOTE Write Scope Enforcement
**Validates**: KNOW-033
```
GIVEN the Knowledge Role is executing in PROMOTE mode
WHEN the role persists promoted artifacts
THEN persisted content in the Knowledge Repository contains promoted content
AND updates to the Knowledge Staging Area are limited to promotion metadata
AND no updates go to the Knowledge Extraction Area
```

### SC-KNOW-054: Promotion Metadata Updated in Staging Area
**Validates**: KNOW-035
```
GIVEN the Knowledge Role successfully promotes an artifact to the Knowledge Repository
WHEN the promotion completes for that artifact
THEN the source artifact in the Knowledge Staging Area has its promoted indicator set to positive
AND the promotion timestamp is recorded
```

### SC-KNOW-055: Atomic Commit — Capability Available
**Validates**: KNOW-048
```
GIVEN the Knowledge Role is invoked in COMMIT mode
AND the atomic commit capability is available (per SES-020)
WHEN the Knowledge Role commits promoted artifacts
THEN the capability is used for conventionally-labeled, atomic commit execution
AND only the scoped artifacts (per KNOW-046) are included
```

### SC-KNOW-056: Atomic Commit — Capability Unavailable Fallback
**Validates**: KNOW-048
```
GIVEN the Knowledge Role is invoked in COMMIT mode
AND the atomic commit capability is unavailable
WHEN the Knowledge Role commits promoted artifacts
THEN a single commit with a descriptive label is created as fallback
AND only the scoped artifacts (per KNOW-046) are included
```
