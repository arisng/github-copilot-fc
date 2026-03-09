---
domain: discovery
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-07T23:03:04+07:00
---

# Discovery Specification

## Purpose

This specification defines the behavioral contracts for the Discovery Role — the role responsible for question generation, evidence-based research, and feedback analysis. It establishes three discovery modes, the question category taxonomy, the Discovery Record structure, the research protocol with confidence levels and implication tracking, the feedback analysis workflow, and the cycle model with summary statistics. This specification depends on Session vocabulary (SES- prefix), Orchestration routing (ORCH- prefix), and the Signal protocol (SIG- prefix). User-facing guidance in this spec prefers iterating terminology for the feedback-driven loop, while the normative orchestration state name remains REPLANNING until a coordinated contract migration updates dependent artifacts.

## Discovery Modes

The Discovery Role operates in exactly three modes. Each mode is invoked by the Orchestration Role from a specific state (per the Orchestration Role Routing Table). The Discovery Role MUST accept exactly one mode per invocation (per SES-022).

| # | Mode | Invoked From | Purpose |
|---|---|---|---|
| 1 | **BRAINSTORM** | PLANNING (ORCH-005), ITERATION_CRITIQUE_REPLAN (ORCH-027 step 2) | Generate questions across a designated category to identify knowledge gaps |
| 2 | **RESEARCH** | PLANNING (ORCH-005), ITERATION_CRITIQUE_REPLAN (ORCH-027 step 3) | Answer unanswered questions with evidence-based findings, source citations, and confidence levels |
| 3 | **FEEDBACK_ANALYSIS** | REPLANNING (ORCH-013) | Analyze Feedback Collection artifacts to produce actionable questions that drive the iterating pipeline |

## Question Categories

The Discovery Role organizes questions into a fixed taxonomy. Each category targets a distinct knowledge domain.

| # | Category | ID Prefix | Knowledge Domain |
|---|---|---|---|
| 1 | **Technical** | Q-TECH | Architecture, tooling, dependencies, APIs, integration points |
| 2 | **Requirements** | Q-REQ | User needs, acceptance criteria, scope boundaries |
| 3 | **Constraints** | Q-CON | Time, resource, platform, and technical limitations |
| 4 | **Assumptions** | Q-ASM | Unstated beliefs, implicit dependencies, preconditions |
| 5 | **Risks** | Q-RSK | Failure modes, edge cases, external dependencies |
| 6 | **Feedback-Driven** | Q-FDB | Root causes, fixes, and prevention items extracted from Feedback Collection |
| 7 | **Critique** | Q-CRT | Knowledge gaps extracted from Iteration Review Report issues during ITERATION_CRITIQUE_REPLAN |

Categories 1–5 are standard categories used in BRAINSTORM mode during PLANNING. Category 6 is produced exclusively by FEEDBACK_ANALYSIS mode during iterating, while the normative orchestration state name remains REPLANNING. Category 7 is produced by BRAINSTORM mode when invoked with a critique source during ITERATION_CRITIQUE_REPLAN (per ORCH-027 step 2).

## Requirements

### Mode Enumeration

#### DISC-001: Recognized Discovery Mode Set
The Discovery Role MUST recognize exactly three modes: BRAINSTORM, RESEARCH, and FEEDBACK_ANALYSIS. Any request specifying a mode not in this set MUST be rejected.

### Question Category Taxonomy

#### DISC-002: Standard Category Set
The Discovery Role MUST recognize exactly five standard question categories: Technical, Requirements, Constraints, Assumptions, and Risks. These categories are used in BRAINSTORM and RESEARCH modes during the PLANNING state.

#### DISC-003: Extended Category Set
In addition to the five standard categories, the Discovery Role MUST recognize two extended categories:
- **Feedback-Driven** — produced exclusively by FEEDBACK_ANALYSIS mode.
- **Critique** — produced by BRAINSTORM mode when the invocation specifies a critique source.

#### DISC-004: Category Exclusivity
Each Discovery Record MUST belong to exactly one category. A single invocation of the Discovery Role MUST operate on exactly one category (per SES-022 single-mode constraint extended to single-category scope).

### Discovery Record Structure

#### DISC-005: Record Identity
Every question within a Discovery Record MUST carry a unique identifier following the pattern `Q-{CATEGORY_PREFIX}-{NUMBER}`, where `{CATEGORY_PREFIX}` is the ID prefix from the question category taxonomy and `{NUMBER}` is a three-digit zero-padded monotonically increasing integer within the category and iteration scope.

#### DISC-006: Record Metadata
Every Discovery Record MUST include the following metadata: the category, the iteration number, the cycle number, a creation timestamp, and an update timestamp. The update timestamp MUST be modified whenever the record is mutated.

#### DISC-007: Question Entry Structure
Every question entry within a Discovery Record MUST include the following fields:
1. **Identifier** — the unique question ID (per DISC-005).
2. **Question text** — a specific, concrete, answerable question. Vague or open-ended questions MUST NOT be accepted.
3. **Priority** — exactly one of: High, Medium, or Low.
4. **Status** — exactly one of: Unanswered, Answered, or Research Needed.
5. **Impact** — a statement describing how the answer affects planning decisions.

#### DISC-008: Answer Entry Structure
When a question transitions to Answered status, the Discovery Record MUST include an answer entry with the following fields:
1. **Question text** — the original question (for cross-reference).
2. **Answer text** — the evidence-based response.
3. **Source** — the provenance of the answer (a URL, file path, or "Deduced from context"). Every answer MUST cite at least one source.
4. **Confidence** — exactly one of: High, Medium, or Low.
5. **Implication** — a statement describing how the answer affects the Iteration Plan.

#### DISC-009: Feedback-Driven Question Extensions
Questions in the Feedback-Driven category (Q-FDB prefix) MUST include two additional fields beyond the standard question entry structure (per DISC-007):
1. **Source Issue** — the identifier of the issue in the Feedback Collection that prompted the question.
2. **Question Type** — exactly one of: Root Cause, Solution, Prevention, or Verification.

#### DISC-010: Critique Question Extensions
Questions in the Critique category (Q-CRT prefix) MUST include one additional field beyond the standard question entry structure (per DISC-007):
1. **Source Issue** — the identifier of the issue in the Iteration Review Report that prompted the question.

### BRAINSTORM Mode

#### DISC-011: BRAINSTORM Invocation Context
When invoked in BRAINSTORM mode, the Discovery Role MUST receive the following inputs: the session path, the iteration number, the cycle number, and the target category. If any required input is missing, the mode MUST return a blocked status.

#### DISC-012: Knowledge Gap Analysis
Before generating questions, the Discovery Role MUST analyze the Iteration Plan to identify knowledge gaps within the designated category:
- **Technical**: gaps in architecture, tooling, dependencies, and APIs.
- **Requirements**: gaps in user needs, acceptance criteria, and scope.
- **Constraints**: gaps in time, resource, and technical limitations.
- **Assumptions**: gaps in unstated beliefs and implicit dependencies.
- **Risks**: gaps in failure modes, edge cases, and external dependencies.

#### DISC-013: Critique Source Override
When the invocation specifies a critique source, the Discovery Role MUST replace the standard knowledge gap analysis (per DISC-012) with an issue-driven analysis: it MUST read the Iteration Review Report, extract all reported issues grouped by severity, and use the issue descriptions as the seed for question generation. The target category MUST be Critique (Q-CRT prefix), and the output MUST be written to a cycle-scoped Discovery Record.

#### DISC-014: Question Generation Volume
In BRAINSTORM mode, the Discovery Role MUST generate between 5 and 8 questions (inclusive) per invocation. Fewer than 5 questions indicates insufficient analysis; more than 8 questions indicates insufficient focus.

#### DISC-015: Cycle Limit Guard
Before executing BRAINSTORM logic, the Discovery Role MUST check the cycle number against the configured maximum planning cycle count (per ORCH-005). If the cycle number exceeds the maximum, the Discovery Role MUST skip question generation, append a cycle-skipped note to the Discovery Record, and return a completed status.

#### DISC-016: Cycle Isolation
The Discovery Role MUST NOT overwrite or modify questions from previous cycles. New cycle content MUST be appended to the Discovery Record under a new cycle section. Each cycle section is self-contained.

### RESEARCH Mode

#### DISC-017: RESEARCH Invocation Context
When invoked in RESEARCH mode, the Discovery Role MUST receive the following inputs: the session path, the iteration number, the cycle number, and the target category. The Discovery Role MUST load the Discovery Record for the specified category and iteration.

#### DISC-018: Unanswered Question Processing
For each question with status Unanswered in the Discovery Record, the Discovery Role MUST:
1. Conduct research using available capabilities (information retrieval, documentation lookup, workspace analysis).
2. Produce an answer entry conforming to DISC-008.
3. Update the question's status from Unanswered to Answered.

Questions with status Answered or Research Needed MUST be skipped during processing.

#### DISC-019: No Speculation Rule
The Discovery Role MUST NOT produce speculative answers. If research does not yield a confident answer, the question status MUST be set to Research Needed rather than Answered. An answer with Confidence level Low is permitted only when supported by at least one cited source.

#### DISC-020: Emergent Question Detection
If answers reveal new knowledge gaps not covered by existing questions, the Discovery Role MUST append new questions to the next cycle section of the Discovery Record. Emergent questions MUST follow the standard question entry structure (per DISC-007) and MUST document the emergence context — which answer triggered the new question.

#### DISC-021: Research Cycle Limit Guard
Before executing RESEARCH logic, the Discovery Role MUST check the cycle number against the configured maximum planning cycle count (per ORCH-005). If the cycle number exceeds the maximum, the Discovery Role MUST skip research, append a cycle-skipped note to the Discovery Record, and return a completed status.

### FEEDBACK_ANALYSIS Mode

#### DISC-022: FEEDBACK_ANALYSIS Invocation Context
When invoked in FEEDBACK_ANALYSIS mode, the Discovery Role MUST receive the following inputs: the session path and the iteration number. The Discovery Role MUST read all Feedback Collection artifacts (per SES-012) within the current Iteration Container.

#### DISC-023: Issue Categorization
The Discovery Role MUST categorize each issue from the Feedback Collection into exactly one of the following issue types:
- **Critical Issues** — blockers that prevent correct operation.
- **Quality Issues** — non-blocking defects affecting standards or usability.
- **New Requirements** — previously unscoped work items.
- **Positive Feedback** — confirmed successes (recorded but not questioned).

#### DISC-024: Issue-to-Question Mapping
For each non-positive issue, the Discovery Role MUST generate questions following the issue type mapping:

| Issue Type | Required Question Types |
|---|---|
| Critical Issues | Root Cause, Solution, Prevention, Verification |
| Quality Issues | Root Cause, Solution, Prevention |
| New Requirements | Scope assessment, Priority assessment, Minimal implementation approach |

Positive Feedback items MUST be recorded in the Discovery Record's source issue list but MUST NOT generate questions.

#### DISC-025: Feedback Coverage Requirement
Every Critical Issue in the Feedback Collection MUST generate at least 2 questions. This ensures that blockers receive sufficient analytical depth for effective replanning.

#### DISC-026: Source Issue Traceability
Every question generated by FEEDBACK_ANALYSIS mode MUST reference its source issue identifier (per DISC-009). The Discovery Record MUST include a source issue index section listing all issue identifiers and their brief descriptions.

### Cycle Model

#### DISC-027: Multi-Cycle Discovery
The Discovery Role MUST support multiple brainstorm-research cycles within a single planning phase. Each cycle MUST be identified by a monotonically increasing cycle number starting at 1 within the iteration scope.

#### DISC-028: Cycle Summary Statistics
At the end of each cycle (after BRAINSTORM or RESEARCH completes), the Discovery Record MUST include a cycle summary section with the following statistics:
1. **Questions Generated** — total count of questions in the cycle.
2. **Questions Answered** — count of questions with Answered status (RESEARCH mode only; zero after BRAINSTORM).
3. **Priority Distribution** — counts per priority level (High, Medium, Low).
4. **Confidence Distribution** — counts per confidence level (High, Medium, Low) for answered questions (RESEARCH mode only).
5. **Emergent Questions** — count of new questions that emerged during research (RESEARCH mode only; zero after BRAINSTORM).

#### DISC-029: Cycle Progression
The standard discovery cycle follows the sequence BRAINSTORM → RESEARCH within each cycle number. A new cycle (incrementing the cycle number) begins when the Orchestration Role re-invokes BRAINSTORM after a completed RESEARCH cycle. The Orchestration Role controls cycle progression; the Discovery Role MUST NOT self-invoke additional cycles.

### Signal Checkpoint Integration

#### DISC-030: Brainstorm Checkpoint
During BRAINSTORM mode, the Discovery Role MUST execute the Universal Polling Routine (per SIG-019) after the knowledge gap analysis and before question generation. Signal responses follow the standard behavioral semantics: STEER adjusts analysis context (per SIG-002), INFO injects context (per SIG-003), PAUSE halts and preserves state (per SIG-004), ABORT finalizes and returns blocked (per SIG-005).

#### DISC-031: Research Per-Question Checkpoint
During RESEARCH mode, the Discovery Role MUST execute the Universal Polling Routine (per SIG-019) before processing each unanswered question. This ensures that signals deposited during research are processed at question-level granularity.

#### DISC-032: Feedback Analysis Per-Issue Checkpoint
During FEEDBACK_ANALYSIS mode, the Discovery Role MUST execute the Universal Polling Routine (per SIG-019) before processing each issue from the Feedback Collection. This ensures that signals deposited during feedback analysis are processed at issue-level granularity.

### Broadcast Acknowledgment

#### DISC-033: Broadcast Signal Acknowledgment
When the Discovery Role encounters a broadcast signal (target ALL) during any polling checkpoint, it MUST create a Signal Acknowledgment Record (per SIG-011) specific to the signal and the Discovery Role. The Discovery Role MUST NOT remove the broadcast signal from the Signal Channel (Inbound).

### Artifact Ownership Integration

#### DISC-034: Discovery Role mutation authority
The Discovery Role has mutation authority over the following artifacts (per SES-012): Discovery Records and the Progress Tracker. The Discovery Role MUST NOT modify artifacts outside this set.

#### DISC-035: Progress Tracker Update Discipline
When the Discovery Role updates the Progress Tracker, it MUST follow the update discipline defined in SES-018: update at the start of work (marking in-progress) and at the end of work (marking the final status). The Discovery Role's Progress Tracker updates are limited to planning-phase entries for brainstorm, research, and feedback analysis — it MUST NOT modify execution-phase or review-phase status markers owned by other roles.

### Return Contract

#### DISC-036: Invocation Response Structure
Every Discovery Role invocation MUST return a structured response containing: the completion status, the mode that was executed, the iteration number, the cycle number, the category, the count of questions generated, the count of questions answered (zero for non-RESEARCH modes), the list of Discovery Records updated, critical findings (if any), the Progress Tracker entry updated, an optional next-role suggestion for the Messenger Protocol (per ORCH-016), and an optional forwarded message for the next role.

#### DISC-037: Planner Grounding Delegation Continuity
When the Discovery Role is invoked during PLANNING in response to a Planning Role grounding delegation, it MUST treat the planner-provided target category, cycle number, and question artifact path as the authoritative continuation context. BRAINSTORM MUST create or append that Discovery Record; RESEARCH MUST load that same Discovery Record; both modes MUST preserve the requested category and cycle in their artifacts and return payloads.

#### DISC-038: Planner Grounding Completion Payload
When BRAINSTORM or RESEARCH completes for a Planning Role grounding delegation, the Discovery Role MUST return a structured completion payload containing: `grounding_request_source` set to `Planner`, `question_artifact_path`, `progress_entry_updated`, `cycle_complete`, `research_needed`, `grounding_ready`, and `planner_resume_mode` set to `TASK_BREAKDOWN`. `grounding_ready` MUST be `true` only when the delegated Discovery Record has no remaining unanswered or research-needed items that block Planner from resuming task breakdown.

## Scenarios

### SC-DISC-001: BRAINSTORM — Standard Category Question Generation
**Validates**: DISC-001, DISC-002, DISC-004, DISC-005, DISC-006, DISC-007, DISC-011, DISC-012, DISC-014, DISC-016
```
GIVEN the system is in PLANNING and the Discovery Role is invoked in BRAINSTORM mode
AND the inputs specify iteration 1, cycle 1, and category Technical
WHEN the Discovery Role analyzes the Iteration Plan for technical knowledge gaps
THEN it generates between 5 and 8 questions with unique identifiers following the Q-TECH-NNN pattern
AND each question includes question text, priority, status set to Unanswered, and impact
AND the Discovery Record is created with metadata (category: Technical, iteration: 1, cycle: 1, timestamps)
AND the questions are written under a Cycle 1 section
AND a cycle summary is appended with question count and priority distribution
```

### SC-DISC-002: BRAINSTORM — Cycle Isolation Across Multiple Cycles
**Validates**: DISC-016, DISC-027
```
GIVEN the Discovery Record for category Requirements already contains Cycle 1 with 6 questions
AND the Orchestration Role re-invokes BRAINSTORM mode with cycle 2 for the same category
WHEN the Discovery Role generates new questions for Cycle 2
THEN the Cycle 1 section remains unmodified
AND a new Cycle 2 section is appended with its own questions
AND question identifiers continue from the last used number in the category
```

### SC-DISC-003: BRAINSTORM — Cycle Limit Exceeded
**Validates**: DISC-015
```
GIVEN the configured maximum planning cycle count is 2
AND the Orchestration Role invokes BRAINSTORM mode with cycle 3
WHEN the Discovery Role checks the cycle limit guard
THEN it skips question generation
AND appends a cycle-skipped note to the Discovery Record
AND returns a completed status without generating questions
```

### SC-DISC-004: BRAINSTORM — Critique Source Override
**Validates**: DISC-003, DISC-010, DISC-013
```
GIVEN the system is in ITERATION_CRITIQUE_REPLAN and the Iteration Review Report contains 2 critical and 1 major issue
AND the Orchestration Role invokes BRAINSTORM mode with a critique source and cycle 1
WHEN the Discovery Role reads the Iteration Review Report
THEN it uses the issue descriptions as knowledge-gap seeds instead of analyzing the Iteration Plan
AND generates questions in the Critique category with Q-CRT prefix
AND each question includes a Source Issue field referencing the originating issue identifier
AND the output is written to a cycle-scoped Discovery Record for the Critique category
```

### SC-DISC-005: RESEARCH — Evidence-Based Answer Synthesis
**Validates**: DISC-001, DISC-008, DISC-017, DISC-018
```
GIVEN a Discovery Record for category Technical, iteration 1, cycle 1 contains 6 questions with status Unanswered
AND the Discovery Role is invoked in RESEARCH mode for category Technical
WHEN the Discovery Role processes each unanswered question
THEN it produces an answer entry for each with answer text, at least one source citation, confidence level, and implication
AND updates each question's status from Unanswered to Answered
AND appends an Answers section under Cycle 1
```

### SC-DISC-006: RESEARCH — No Speculation Enforcement
**Validates**: DISC-019
```
GIVEN a Discovery Record contains a question that cannot be answered through available research
WHEN the Discovery Role attempts to research the question
THEN the question status is set to Research Needed
AND no answer entry is produced for that question
AND the Discovery Role does not fabricate a speculative answer
```

### SC-DISC-007: RESEARCH — Emergent Question Detection
**Validates**: DISC-020
```
GIVEN the Discovery Role is answering Q-TECH-003 during Cycle 1 research
AND the answer reveals a new knowledge gap about a dependency not covered by existing questions
WHEN the Discovery Role detects the emergent gap
THEN it appends a new question to the next cycle section (Cycle 2)
AND the new question follows the standard entry structure (per DISC-007)
AND the new question documents which answer triggered its creation
```

### SC-DISC-008: FEEDBACK_ANALYSIS — Issue Categorization and Question Generation
**Validates**: DISC-001, DISC-003, DISC-009, DISC-022, DISC-023, DISC-024, DISC-025, DISC-026
```
GIVEN the system is in REPLANNING and the Feedback Collection contains 2 critical issues and 1 quality issue
AND the Discovery Role is invoked in FEEDBACK_ANALYSIS mode
WHEN the Discovery Role categorizes the issues
THEN the 2 critical issues each generate at least 2 questions (Root Cause, Solution, Prevention, Verification types)
AND the quality issue generates questions (Root Cause, Solution, Prevention types)
AND every question includes a Source Issue field and a Question Type field
AND the Discovery Record includes a source issue index listing all 3 issue identifiers with descriptions
AND questions use the Q-FDB prefix
```

### SC-DISC-009: FEEDBACK_ANALYSIS — Positive Feedback Handling
**Validates**: DISC-023, DISC-024
```
GIVEN the Feedback Collection contains 1 critical issue and 1 positive feedback item
WHEN the Discovery Role processes the feedback
THEN the critical issue generates questions per the issue-to-question mapping
AND the positive feedback item is listed in the source issue index
AND no questions are generated for the positive feedback item
```

### SC-DISC-010: Cycle Summary Statistics
**Validates**: DISC-028
```
GIVEN the Discovery Role has completed RESEARCH mode for category Constraints, iteration 1, cycle 1
AND it answered 4 of 6 questions (2 remain as Research Needed)
WHEN the cycle summary is generated
THEN it includes: Questions Generated = 6, Questions Answered = 4
AND Priority Distribution lists the counts for each priority level
AND Confidence Distribution lists the counts for each confidence level among the 4 answered questions
AND Emergent Questions count reflects any questions appended to the next cycle
```

### SC-DISC-011: Signal Interruption — PAUSE During Research
**Validates**: DISC-031, DISC-033
```
GIVEN the Discovery Role is in RESEARCH mode processing question Q-TECH-003
AND a PAUSE signal exists in the Signal Channel (Inbound) targeting the Discovery Role
WHEN the Discovery Role executes the Universal Polling Routine before processing Q-TECH-003
THEN it completes any in-progress answer for the previous question (atomic operation boundary)
AND records current progress in the Progress Tracker with a pause indicator (per SIG-004)
AND returns a paused status to the Orchestration Role
AND if the signal targets ALL, creates a Signal Acknowledgment Record before pausing
```

### SC-DISC-012: Broadcast Signal Acknowledgment During Brainstorm
**Validates**: DISC-030, DISC-033
```
GIVEN the Discovery Role is in BRAINSTORM mode
AND a broadcast INFO signal (target ALL) exists in the Signal Channel (Inbound)
WHEN the Discovery Role executes the Universal Polling Routine at the brainstorm checkpoint
THEN it creates a Signal Acknowledgment Record for the signal and the Discovery Role
AND incorporates the INFO payload into its analysis context
AND does NOT remove the signal from the Signal Channel (Inbound)
```

### SC-DISC-013: RESEARCH — Cycle Limit Guard Skips Research
**Validates**: DISC-021
```
GIVEN the configured maximum planning cycle count is 2
AND the Orchestration Role invokes RESEARCH mode with cycle 3 for category Technical
WHEN the Discovery Role checks the research cycle limit guard
THEN it skips all research processing
AND appends a cycle-skipped note to the Discovery Record
AND returns a completed status without answering any questions
```

### SC-DISC-014: Cycle Progression — BRAINSTORM to RESEARCH Within and Across Cycles
**Validates**: DISC-029
```
GIVEN the Discovery Role has completed BRAINSTORM for category Requirements, iteration 1, cycle 1
AND the Orchestration Role then invokes RESEARCH for the same category and cycle 1
AND RESEARCH completes and returns
WHEN the Orchestration Role re-invokes BRAINSTORM with cycle 2 for the same category
THEN cycle 2 begins a new BRAINSTORM → RESEARCH sequence
AND the Discovery Role does NOT self-invoke additional cycles after completing its invoked mode
AND the cycle number is incremented only because the Orchestration Role issued a new invocation
```

### SC-DISC-015: FEEDBACK_ANALYSIS — Per-Issue Signal Checkpoint
**Validates**: DISC-032
```
GIVEN the Discovery Role is in FEEDBACK_ANALYSIS mode processing 3 issues from the Feedback Collection
AND a STEER signal is deposited into the Signal Channel (Inbound) targeting the Discovery Role after the first issue is processed
WHEN the Discovery Role executes the Universal Polling Routine before processing the second issue
THEN it detects and applies the STEER signal, adjusting the analysis context for subsequent issues (per SIG-002)
AND the first issue's questions remain unmodified
AND the remaining issues are processed under the adjusted context
```

### SC-DISC-016: Discovery Role mutation authority Enforcement
**Validates**: DISC-034
```
GIVEN the Discovery Role is invoked in BRAINSTORM mode
WHEN the Discovery Role completes question generation
THEN it modifies only Discovery Records and the Progress Tracker
AND it does NOT modify the Iteration Plan, Signal Channel, Feedback Collection, or any other artifact outside its mutation authority set
```

### SC-DISC-017: Progress Tracker Update Discipline
**Validates**: DISC-035
```
GIVEN the Discovery Role is invoked in RESEARCH mode for category Technical, iteration 1, cycle 1
WHEN execution begins
THEN the Discovery Role updates the Progress Tracker to mark the research task as in-progress (per SES-018)
AND when research processing completes
THEN the Discovery Role updates the Progress Tracker to mark the research task with its final status
AND it does NOT modify execution-phase or review-phase status markers owned by other roles
```

### SC-DISC-018: Invocation Response Structure Completeness
**Validates**: DISC-036
```
GIVEN the Discovery Role has completed BRAINSTORM mode for category Assumptions, iteration 1, cycle 1
AND it generated 6 questions with 0 answered
WHEN the invocation returns its structured response
THEN the response contains: completion status, mode (BRAINSTORM), iteration number (1), cycle number (1), category (Assumptions), questions generated count (6), questions answered count (0), list of Discovery Records updated, critical findings (if any), Progress Tracker entry updated, optional next-role suggestion, and optional forwarded message
```

### SC-DISC-019: PLANNING — Return Planner Grounding Completion Markers
**Validates**: DISC-037, DISC-038
```
GIVEN the Discovery Role is invoked during PLANNING from a Planner grounding delegation for category Technical and cycle 1
WHEN BRAINSTORM completes and writes the delegated Discovery Record
THEN the response preserves the requested category and cycle
AND includes `grounding_request_source` = `Planner`
AND includes the `question_artifact_path` for the delegated Discovery Record
AND includes the `progress_entry_updated` marker for the completed discovery step
AND sets `grounding_ready` to `false` until the delegated research work is complete
AND sets `planner_resume_mode` to `TASK_BREAKDOWN`
```
