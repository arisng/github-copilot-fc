# Feature Plan

Use this template when proposing a new feature, capability, or significant product improvement. Include goals, user stories, implementation approach, and risk assessment.

## Template

```markdown
---
date: YYYY-MM-DD
type: Feature Plan
severity: Critical | High | Medium | Low | N/A
status: Draft | Proposed | In Progress | Accepted
---

# [Feature Name]

## Goal
[What are we building and why? Value proposition.]

## Requirements
- [ ] User Story 1
- [ ] User Story 2

## Proposed Implementation
[High-level technical approach. Components involved.]

## Risks & Considerations
- [Potential blockers or edge cases]
```

## Field Descriptions

- **date**: ISO 8601 date when the feature plan was created or updated
- **type**: Always "Feature Plan" for this template
- **severity**: Importance level — Critical (core to roadmap), High (high priority), Medium (nice to have), Low (backlog), or N/A
- **status**: Draft (early concept), Proposed (ready for review), In Progress (under development), or Accepted (approved/shipped)

## Writing Tips

- **Goal**: Start with the "why" before the "what". Who benefits? What problem does it solve? Be concise but compelling.
- **Requirements**: Break down into user stories or acceptance criteria. Use checkboxes for tracking progress.
- **Implementation**: Outline the technical path — which components, APIs, databases, or dependencies are involved? Keep it high-level; detailed design goes in ADRs.
- **Risks**: Think about dependencies, integration points, performance implications, and edge cases.

## Example

```markdown
---
date: 2026-03-08
type: Feature Plan
severity: High
status: Accepted
---

# Real-time collaboration for document editing

## Goal
Enable multiple users to edit documents simultaneously with live cursor and change visibility, reducing coordination overhead and improving team productivity during collaborative writing.

## Requirements
- [ ] Users can see live cursor positions of collaborators
- [ ] Edits from other users appear in real-time (< 1 second latency)
- [ ] Conflict-free concurrent edits using CRDT or similar
- [ ] Connection loss handling with re-sync
- [ ] Audit log of all changes with author attribution

## Proposed Implementation
- Use Yjs (CRDT library) for conflict-free merging
- WebSocket server for real-time messaging (or use existing Socket.io setup)
- Extend document schema to track change metadata (user, timestamp)
- Frontend: integrate monaco-editor's collaborative extensions
- Backend: validate change operations and persist to database

## Risks & Considerations
- Performance at scale with many concurrent editors
- Network reliability and reconnection edge cases
- Browser compatibility (needs IE11 support? Confirm.)
- Audit log storage growth (consider archiving old changes)
```
