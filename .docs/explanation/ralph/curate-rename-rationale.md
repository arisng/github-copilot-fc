---
category: explanation
source_session: 260227-144634
source_iteration: 1
source_artifacts:
  - iterations/1/plan.md
  - iterations/1/reports/task-2-report.md
  - iterations/1/tasks/task-2.md
staged_at: 2026-02-27T16:07:02+07:00
approved: true
approved_at: 2026-02-27T16:09:38+07:00
---

# Why KNOWLEDGE_APPROVAL Was Renamed to CURATE

## Context

In Ralph v2.8.0, the Librarian subagent had three modes: `STAGE`, `PROMOTE`, and `KNOWLEDGE_APPROVAL`. The third mode broke the single-word naming convention established by the first two.

## The Signal Collision Problem

The initial candidate for the rename was `APPROVE` — intuitive and consistent with the approval gate concept. However, research during planning (Q-REQ-001, Q-RISK-002) revealed a **naming collision**:

- The Librarian's CURATE (formerly KNOWLEDGE_APPROVAL) workflow polls for **APPROVE** and **SKIP** signal types in `signals/inputs/`.
- If the mode were named `APPROVE`, the keyword would appear in two distinct semantic roles:
  1. As a **mode name** (the mode the Librarian runs in)
  2. As a **signal type** (the human-issued approval signal the mode polls for)
- This dual usage would make grep-based verification unreliable and documentation ambiguous ("Did you mean the APPROVE mode or the APPROVE signal?").

## Why CURATE

`CURATE` was selected because:

1. **No collision**: The word "curate" does not appear in any signal type, field value, or task name.
2. **Semantic fit**: The Librarian's role is knowledge curation — staging, reviewing, and promoting wiki content.
3. **Single-word**: Aligns with `STAGE` and `PROMOTE` convention.
4. **Distinct from action**: Unlike `APPROVE` (which describes what the human does), `CURATE` describes what the Librarian does in this mode — orchestrating the full approval gate lifecycle.

## Takeaway

When renaming modes or states in multi-agent systems, always check for **semantic collision** with signal types, field values, task names, and other controlled vocabularies. A name that is intuitive in isolation may create ambiguity when it overlaps with an existing keyword in a different role.
