# Artifact Templates

Detailed templates for each artifact in an OpenSpec change folder.

## Table of Contents

- [proposal.md](#proposalmd)
- [Delta Specs](#delta-specs)
- [design.md](#designmd)
- [tasks.md](#tasksmd)
- [.openspec.yaml](#openspecyaml)

## proposal.md

The "why" and "what" — captures motivation, changes, and which capabilities are affected. The **Capabilities** section is the critical contract: each new capability becomes a `specs/<name>/spec.md` file; each modified capability requires a delta spec.

```markdown
# Proposal: <Change Name>

## Why
1-2 sentences on the problem this change solves.

## What Changes
- Change description (mark **BREAKING** if it breaks existing behavior)
- Another change
- **BREAKING**: Change that breaks existing API/contracts

## Capabilities

### New Capabilities
Each entry becomes `specs/<kebab-case-name>/spec.md`:
- **<capability-name>** — Description of the new capability

### Modified Capabilities
Existing specs with requirement changes (need delta spec):
- **<existing-capability>** — What changes in this capability

## Impact
Affected code paths, APIs, dependencies, and downstream consumers.
```

## Delta Specs

Delta specs live in `openspec/changes/<name>/specs/<domain>/spec.md`.
They describe modifications to existing specifications using semantic markers.

```markdown
# Delta for <Domain>

## ADDED Requirements

### Requirement: <New Requirement Name>
The system MUST <behavior statement>.

#### Scenario: <Scenario Name>
- **GIVEN** <precondition>
- **WHEN** <action>
- **THEN** <expected outcome>
- **AND** <additional outcome>

## MODIFIED Requirements

### Requirement: <Existing Requirement Name>
The system SHALL <updated behavior statement>.
(Previously: <old behavior summary>)

#### Scenario: <Updated Scenario Name>
- **GIVEN** <precondition>
- **WHEN** <action>
- **THEN** <updated expected outcome>

## REMOVED Requirements

### Requirement: <Deprecated Requirement Name>
(Deprecated: <reason for removal>. Migration: <migration path or "None">.)

## RENAMED Requirements

### Requirement: <New Requirement Name>
- **FROM:** Old Requirement Name
- **TO:** New Requirement Name
```

### Delta Rules

- **ADDED**: Include complete requirement with all scenarios
- **MODIFIED**: Include full updated requirement block (from `### Requirement:` through all scenarios)
- **REMOVED**: Only normalized header text needed, plus reason and optional migration
- **RENAMED**: Must include `FROM:` and `TO:` mapping
- **Merge order**: RENAMED → REMOVED → MODIFIED → ADDED (ensures MODIFIED can reference renamed requirements)

## design.md

The "how" — technical approach, architecture decisions, file change manifest.

```markdown
# Design: <Change Name>

## Technical Approach
Detailed implementation strategy.
How the proposed changes will be realized in code.

## Architecture Decisions

### Decision: <Decision Name>
Explanation of the architectural choice.

**Rationale:**
- Reason 1
- Reason 2

**Alternatives considered:**
- Alternative A — rejected because...

### Decision: <Another Decision>
...

## Data Flow
[ASCII diagrams or descriptions of data/control flow]

## File Changes
- `path/to/file.ts` — new: <purpose>
- `path/to/other.ts` — modified: <what changes>
- `path/to/old.ts` — deleted: <reason>
```

## tasks.md

Implementation checklist with phased grouping and checkbox tracking.

```markdown
# Tasks

## 1. <Phase Name>
- [ ] 1.1 First task description
- [ ] 1.2 Second task description
- [ ] 1.3 Third task description

## 2. <Phase Name>
- [ ] 2.1 Task description
- [x] 2.2 Completed task description
- [ ] 2.3 Task description

## 3. Verification
- [ ] 3.1 Run tests
- [ ] 3.2 Manual verification of scenarios
```

### Task Rules

- Group tasks by phase with numbered headings
- Each task gets a numbered checkbox item
- Tasks should be independently verifiable
- Mark `- [x]` immediately upon completion during `/opsx:apply`
- Tasks can be added, reordered, or revised mid-implementation

## .openspec.yaml

Change metadata file (auto-generated):

```yaml
schema: spec-driven
created: 2026-03-01
```
