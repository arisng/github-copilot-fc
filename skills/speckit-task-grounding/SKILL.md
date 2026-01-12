---
name: speckit-task-grounding
description: Task grounding validation framework for ensuring development tasks are properly specified in planning artifacts before implementation. Use when validating feature specifications, checking task grounding against artifacts like spec.md, plan.md, data-model.md, api-contracts.md, research.md, and quickstart.md, or when performing parallel task validation for feature readiness assessment.
---

# SpecKit Task Grounding Validator

A framework for validating that development tasks are properly grounded in planning artifacts before implementation, enabling parallel task validation and reducing implementation risks.

## Integration with Speckit SDD

This skill integrates with the **Spec-Driven Development (SDD)** methodology implemented by Speckit:

- **SDD Workflow**: specify → plan → tasks
- **Artifact Scope**: Works within `specs/[branch-name]/` specification folders
- **Validation Timing**: Use after `/speckit.tasks` generates the task list
- **Quality Gate**: Ensures tasks are properly grounded before implementation begins

## Core Concept

**Parallel Task Validation**: Each task grounding check is independent, allowing multiple reviewers to validate tasks simultaneously (2-3 minutes per task).

## Quick Start

1. **Verify artifacts exist**: Check for spec.md, plan.md, tasks.md, and supporting artifacts
2. **Process each task in parallel**:
   - Extract task details from tasks.md
   - Search artifacts for evidence
   - Score grounding level (0-100%)
   - Assess risk and identify gaps
   - Document findings
3. **Generate report**: Use the complete report template for decision gates

## Grounding Score Calculator

| Score    | Meaning    | Evidence Required                    | Action           |
| -------- | ---------- | ------------------------------------ | ---------------- |
| **100%** | Explicit   | Direct quote with exact location     | ✅ Execute        |
| **90%**  | Detailed   | Code example or schema provided      | ✅ Execute        |
| **80%**  | Referenced | Clear spec with implementation notes | ✅ Execute        |
| **70%**  | Pattern    | Documented pattern to follow         | ⚠️ Verify pattern |
| **60%**  | Inferred   | Multiple weak references             | ⚠️ Clarify        |
| **50%**  | Assumed    | Single weak reference                | 🔴 High risk      |
| **<50%** | Missing    | No evidence found                    | 🔴 Block          |

## Decision Matrix

### Phase Thresholds
- **Phase 1 (Setup)**: ≥90% tasks at ≥80% grounding
- **Phase 2 (Foundation)**: ≥80% tasks at ≥70% grounding
- **Phase 3+ (Features)**: ≥70% tasks at ≥60% grounding

### Risk Levels
- **🟢 Low**: ≥90% grounding, no gaps
- **🟡 Medium**: 70-89% grounding, resolvable gaps
- **🔴 High**: <70% grounding, critical gaps

## Key Features

- **Parallel Processing**: Independent task validation enables team distribution
- **Evidence-Based Scoring**: Systematic 0-100% grounding assessment
- **Gap Analysis**: Identifies missing specifications with resolution steps
- **Decision Gates**: Clear approve/clarify/block recommendations
- **Report Templates**: Complete documentation framework

## Usage Workflow

For each task in tasks.md:
1. **Extract** task details and requirements
2. **Search** artifacts in order: spec.md → plan.md → research.md → data-model.md → contracts/ → quickstart.md
3. **Score** grounding level based on evidence strength
4. **Assess** risk and document gaps
5. **Aggregate** results for feature-level decision

## Parallel Processing Workflow

### Step 1: Assign Tasks to Reviewers
- **Reviewer A**: Tasks T001-T003 (Phase 1)
- **Reviewer B**: Tasks T004-T005 (Phase 2)
- **Reviewer C**: Tasks T006+ (Phase 3+)

### Step 2: Individual Validation
```powershell
# Reviewer A validates their assigned tasks
.\scripts\Validate-TaskGrounding.ps1 -FeaturePath "specs/my-feature" -TaskFilter "T001,T002,T003" -JsonOutput -OutputPath "reviewerA-assessment.json"

# Reviewer B validates their assigned tasks
.\scripts\Validate-TaskGrounding.ps1 -FeaturePath "specs/my-feature" -TaskFilter "T004,T005" -JsonOutput -OutputPath "reviewerB-assessment.json"
```

### Step 3: Aggregate Results
```powershell
# Combine all individual assessments into final report
.\scripts\Aggregate-TaskGrounding.ps1 -FeatureName "my-feature" -AssessmentFiles @("reviewerA-assessment.json", "reviewerB-assessment.json", "reviewerC-assessment.json")
```

**Benefits:**
- **Parallel Execution**: 2-3 minutes per reviewer instead of 15-25 minutes total
- **Independent Validation**: Each task assessed by one person, avoiding conflicts
- **Efficient Aggregation**: Automated combination maintains consistency
- **Scalable**: Works with 2 reviewers or 10 reviewers equally well

## References

- [Complete Framework](references/framework.md) - Full validation methodology and templates
- [Scoring Examples](references/examples.md) - Real-world validation cases
- [Report Template](references/report-template.md) - Complete documentation template
- [Automation Scripts](scripts/) - PowerShell validation and aggregation scripts

## Prerequisites

- `spec.md` - Feature specification with user stories and requirements (highest authority)
- `plan.md` - Implementation plan with technical decisions
- `research.md` - Technical research and context gathering
- `data-model.md` - Data models and entity definitions
- `contracts/` - Directory containing API contracts and interface specifications
- `quickstart.md` - Key validation scenarios and quickstart guide
- `tasks.md` - Executable task list derived from plan (input for validation)

## Common Use Cases

- **Feature Readiness**: Validate all tasks before implementation begins
- **Specification Review**: Ensure planning artifacts are complete
- **Risk Assessment**: Identify implementation uncertainties early
- **Team Coordination**: Parallel validation by multiple reviewers
- **Quality Gates**: Automated checking in CI/CD pipelines
- **SDD Compliance**: Validate Speckit-generated artifacts meet grounding standards

## Output

Generates `TASK_GROUNDING_ANALYSIS.md` with:
- Executive Summary table
- Task Grounding Matrix with status indicators
- Gap analysis with impact and resolution steps
- Action plan with phase-specific execution steps
- Risk assessment and mitigation strategies
- Decision gate recommendation

## Decision Rules

- **✅ APPROVE**: Meets phase thresholds, no critical gaps
- **⚠️ CLARIFY**: Resolvable gaps identified, needs verification
- **🔴 BLOCK**: Critical gaps or insufficient grounding

## Training Levels

- **Level 1 (30 min)**: Basic scoring and validation process
- **Level 2 (60 min)**: Complex cases and customization
- **Level 3 (2 hours)**: Administration and team training

## Version History

- **v3 (Current)**: Single-page parallel validation framework
- **v2 (Experimental)**: Four-file compressed structure
- **v1 (Experimental)**: Original 13-file comprehensive documentation