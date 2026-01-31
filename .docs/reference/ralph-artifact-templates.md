# Ralph Session Artifact Templates

This document contains the canonical templates for all Ralph session artifacts. These templates are the single source of truth referenced by Ralph-Planner and other subagents.

---

## 1. Plan Template (`plan.md`)

```markdown
# Plan: [Title]

## Goal & Success Criteria
[Specific objective and what 'done' looks like]

## Target Files/Artifacts
[List specific files, documents, or artifacts referenced in user input or identified as primary targets for this session]

## Context & Analysis
[Context, problem breakdown, research findings, and constraints]

## Proposed Design/Changes/Approach
[Detailed breakdown of changes, deliverables, or approach - may include: file changes, logic updates, new components, research deliverables, documentation structure, analysis framework, etc.]

## Verification & Testing
[Specific steps to validate the work, which may include:
- Code: unit tests, integration tests, browser automation tests (use `playwright-cli` skill for web interaction validation)
- Research: source validation, completeness checks, cross-reference verification
- Documentation: readability review, technical accuracy, structure validation
- Analysis: methodology review, data validation, conclusion verification]

## Risks & Assumptions (Optional)
[Potential side-effects, edge cases, and assumptions made]
```

---

## 2. Q&A Discovery Template (`plan.questions.md`)

```markdown
# Q&A Discovery: [Session Title]

## Overview
- **Session ID**: [SESSION_ID]
- **Created**: [Timestamp]
- **Last Updated**: [Timestamp]
- **Q&A Cycles Completed**: [Number]
- **Status**: Active | Converged | Complete

## Q&A Cycles

### Cycle 1
**Initiated**: [Timestamp]
**Objective**: Initial context exploration and assumption validation

#### Generated Questions
1. **[High Priority]** [Question]
    - **Category**: Technical | Requirements | Constraints | Assumptions | Risks
    - **Priority**: High | Medium | Low
    - **Status**: Unanswered | Research Needed | Answered
    - **Impact**: [How this affects plan/tasks]
    - **Answer**: [To be filled]
    - **Source**: [Research source or rationale]
    - **Confidence**: [High/Medium/Low if answered]

2. **[Medium Priority]** [Question]
    - **Category**: [Category]
    - **Priority**: [Priority]
    - **Status**: [Status]
    - **Impact**: [Impact]
    - **Answer**: [To be filled]
    - **Source**: [Source]
    - **Confidence**: [Confidence]

#### Cycle Summary
- **Questions Generated**: [Number]
- **Questions Answered**: [Number]
- **New Questions Emerged**: [Number]
- **Key Insights**: [Summary of important findings]

### Cycle 2
[Repeat structure if new questions emerged]

## Key Insights for Plan.md
### Critical Findings
- [Key answers that inform the plan]

### Validated Assumptions
- [Assumptions that were confirmed]

### Invalidated Assumptions
- [Assumptions that were disproven and need replanning]

### Remaining Unknowns & Risks
- [Questions that couldn't be answered, representing risks]

### Recommendations for Plan Updates
- [Specific suggestions for updating plan.md sections]
```

---

## 3. Tasks Template (`tasks.md`)

```markdown
# Task List

## Planning Tasks
- qa-brainstorm: Generate comprehensive questions to uncover hidden assumptions and knowledge gaps
    - **Type**: Sequential
    - **Files**: [plan.questions.md]
    - **Objective**: Produce categorized list of critical questions impacting plan quality
    - **Success Criteria**: 
        - Generate 10+ questions across technical, requirements, constraints categories
        - Each question includes priority assessment and potential impact
        - Questions address both explicit and implicit aspects of the session goal

- qa-research: Answer prioritized questions with evidence-based research
    - **Type**: Sequential (depends on qa-brainstorm)
    - **Files**: [plan.questions.md]
    - **Objective**: Provide well-researched answers to critical questions
    - **Success Criteria**:
        - Answer all High priority questions with credible sources
        - Document Medium priority questions with best available information
        - Identify which Low priority questions can be deferred
        - All answers include source references and confidence levels

## Implementation Tasks
- task-1: [Clear, actionable description]
    - **Type**: Sequential | Parallelizable
    - **Files**: [path/to/file1, path/to/file2] OR [Artifacts/Deliverables: report.md, analysis.md]
    - **Objective**: [Clear objective statement]
    - **Success Criteria**: [Specific, measurable, testable outcomes that define "done"]

- task-2: [Clear, actionable description]
    - **Type**: Sequential | Parallelizable
    - **Files**: [path/to/file3] OR [Deliverables: documentation/guide.md]
    - **Objective**: [Clear objective statement]
    - **Success Criteria**: [Specific, measurable, testable outcomes that define "done"]
```

### Success Criteria Quality Standards

**Good Success Criteria (Coding):**
- ✅ "Unit tests pass with 80%+ coverage for new functions"
- ✅ "Browser automation successfully completes login flow without errors (validated with playwright-cli)"
- ✅ "API endpoint returns 200 status with expected JSON schema"

**Good Success Criteria (Research):**
- ✅ "Report documents 5+ credible sources with URLs and key findings"
- ✅ "Comparison table includes 3+ alternatives with pros/cons for each"
- ✅ "Research findings answer all 4 questions listed in plan.md"

**Good Success Criteria (Documentation):**
- ✅ "Guide includes step-by-step instructions with screenshots for each step"
- ✅ "API reference documents all 10 endpoints with parameters and examples"
- ✅ "README has installation, usage, and troubleshooting sections"

**Good Success Criteria (Analysis):**
- ✅ "Analysis identifies 3+ root causes with supporting evidence"
- ✅ "Performance report includes baseline vs optimized metrics"
- ✅ "Security audit lists vulnerabilities with severity ratings and mitigation steps"

**Bad Success Criteria:**
- ❌ "Code looks good" (not measurable)
- ❌ "Implement the feature" (not an outcome)
- ❌ "Do your best" (not verifiable)
- ❌ "Write some docs" (not specific)

---

## 4. Progress Template (`progress.md`)

```markdown
# Progress Tracking

## Planning Progress
- [x] qa-brainstorm (Completed)
- [x] qa-research (Completed)

## Implementation Progress
- [x] task-1 (Completed)
- [P] task-2 (Review Pending)
- [/] task-3 (In Progress)
- [ ] task-4 (Not Started)
```

### Progress Markers
| Marker | Meaning |
|--------|---------|
| `[ ]` | Not Started |
| `[/]` | In Progress |
| `[P]` | Review Pending |
| `[x]` | Completed |

---

## 5. Task Report Template (`tasks.<TASK_ID>-report.md`)

For first attempt: `tasks.<TASK_ID>-report.md`
For rework iterations: `tasks.<TASK_ID>-report-r<N>.md` (N = 2, 3, 4...)

```markdown
# Task Report: <TASK_ID> [Rework #N]

---
## PART 1: IMPLEMENTATION REPORT
*(Created by Ralph-Executor)*

### Rework Context (if applicable)
[Only for rework iterations: Summary of previous attempt's failure and what changed in approach]
- **Previous Report**: tasks.<TASK_ID>-report[-r<N-1>].md
- **Reason for Rework**: [Why the previous attempt failed]
- **New Approach**: [What's different this time]

### Objective Recap
[Restate the objective from tasks.md]

### Success Criteria Status
[Explicitly address each success criterion and whether it was met]
- ✅ Criterion 1: [Met/Not Met - Evidence]
- ✅ Criterion 2: [Met/Not Met - Evidence]

### Summary of Changes
[Describe files edited and logic implemented]

### Verification Results
[List tests run and their results]

### Discovered Tasks
[List any new tasks or requirements identified for the orchestrator to review]

---
## PART 2: REVIEW REPORT
*(Appended by Ralph-Reviewer)*

### Review Summary
[Brief 2-3 sentence summary of findings]

### Success Criteria Validation
[For each criterion from tasks.md, document validation results]
- ✅ **Criterion 1**: [Met/Not Met]
  - **Evidence Reviewed**: [What you checked]
  - **Finding**: [Your assessment]
- ❌ **Criterion 2**: [Met/Not Met]
  - **Evidence Reviewed**: [What you checked]
  - **Finding**: [Your assessment]

### Quality Assessment
[Overall assessment of work quality, completeness, and adherence to objective]

### Issues Identified (if any)
[List specific problems, gaps, or deficiencies found]
- Issue 1: [Description]
- Issue 2: [Description]

### Validation Actions Performed
[List concrete validation steps taken]
- Ran tests: [results]
- Inspected files: [findings]
- Verified data: [findings]

### Recommendation
**Status**: Qualified | Failed
**Reasoning**: [Explain why this status is appropriate]

### Feedback for Next Iteration (if Failed)
[If failed, provide specific guidance for rework]
```

---

## 6. Session Instructions Template (`<SESSION_ID>.instructions.md`)

```markdown
---
description: Custom instructions for Ralph session <SESSION_ID>
applyTo: .ralph-sessions/<SESSION_ID>/**
---

# Session: <SESSION_ID>

## Context
[Brief description of the session goal]

## Target Files
- [List of primary files being modified]

## Coding Conventions
[Session-specific coding standards if any]

## Important Constraints
[Any constraints or requirements specific to this session]
```

---

## Browser Automation Reference

For web feature validation and interaction testing, use the `playwright-cli` skill:

```bash
playwright-cli open https://example.com
playwright-cli click e15
playwright-cli type "test input"
playwright-cli press Enter
```

See [playwright-cli skill](../../skills/playwright-cli/SKILL.md) for capability distinction between CLI-based and script-based approaches.
