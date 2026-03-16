---
title: "Cross-Agent Normalization Contract"
status: active
version: "2.13.0"
created_at: 2026-02-15T00:00:00+07:00
updated_at: 2026-03-09T10:44:58+07:00
---

# Cross-Agent Normalization Contract

This document defines the public consistency rules that keep Ralph-v2 summary surfaces aligned with the normative workflow contracts in `openspec/specs/ralph-v2-orchestration/`. Use it when updating the public README, wrapper hints, task-facing summaries, plugin manifests, publish messaging, or other derivative Ralph-facing documentation.

## Scope

- **Normative source of truth**: the OpenSpec orchestration, planning, review, session, and signals specifications.
- **Normalized summary surfaces**: `agents/ralph-v2/README.md`, wrapper agent hints, agent-local reference docs, source `plugin.json` manifests, and publish/build messaging.
- **Derived outputs**: generated bundles under `plugins/*/.build/` are build artifacts and MUST NOT be edited directly.

## Canonical Vocabulary

### Review and critique states

- The workflow uses exactly these post-implementation state names in public summary surfaces: `ITERATION_REVIEW`, `ITERATION_CRITIQUE_REPLAN`, `COMPLETE`, `REPLANNING`, and `SESSION_REVIEW`.
- `ITERATION_REVIEW` is the blocking, post-knowledge review gate for the current iteration.
- `SESSION_REVIEW` is the optional session-scoped retrospective after iteration work is already closed.
- `ITERATION_CRITIQUE_REPLAN` is the critique-loop state that converts iteration-review findings into follow-up planning work.

### Legacy wording prohibited

The following wording MUST NOT appear in normalized public summary surfaces:

- Assigning the session retrospective state name to the iteration gate.
- Describing `SESSION_REVIEW` as an iteration-scoped report.
- Using a session-scoped critique-replanning state name instead of iteration-scoped critique terminology.
- Referring to critique counters or payloads with session-review vocabulary when they are iteration-scoped.

## Artifact Boundaries

### Iteration scope

These remain the canonical iteration-scoped artifacts:

- `iterations/<N>/progress.md` for task status.
- `iterations/<N>/tasks/<id>.md` for task definitions.
- `iterations/<N>/metadata.yaml` for iteration timing and completion status.
- `iterations/<N>/reports/<id>-report*.md` for executor and reviewer attempt history.
- `iterations/<N>/plan.md` for the current plan.
- `iterations/<N>/questions/<category>.md` for grounded Q&A.
- `iterations/<N>/knowledge/{tutorials,how-to-guides,reference,explanation}/` for extracted knowledge.
- `iterations/<N>/review.md` for the `ITERATION_REVIEW` output.

### Session scope

These remain the canonical session-scoped artifacts:

- `metadata.yaml` for the session state machine.
- `signals/inputs/`, `signals/acks/`, and `signals/processed/` for the signal mailbox.
- `knowledge/` for staged session knowledge.
- `.ralph-sessions/<SESSION_ID>/session-review.md` for the `SESSION_REVIEW` retrospective.

### Denormalized summaries

If a summary can be regenerated from canonical sources, it is non-authoritative and MUST be labeled accordingly. Denormalized views MUST NOT redefine state names, artifact ownership, or completion semantics.

## Concurrency Summary Rules

Orchestration is the concurrency source of truth. Normalized public summaries MUST preserve these boundaries:

- Planner is sequential except for `TASK_CREATE`, which may run in parallel only after queued task inventory already exists.
- Questioner is sequential.
- Executor may run same-wave tasks in parallel only after dependency guards are satisfied.
- Reviewer may parallelize `TASK_REVIEW` across distinct pending tasks in the same wave; `COMMIT`, `ITERATION_REVIEW`, and `SESSION_REVIEW` remain sequential.
- Librarian remains sequential across `EXTRACT -> STAGE -> PROMOTE -> ITERATION_REVIEW`.

Public guidance MUST describe these boundaries as settled contract, not as provisional migration notes.

## Version Governance Rules

- The canonical Ralph workflow version is the shared `version` frontmatter carried by the source Ralph agent wrapper files.
- The source CLI and VS Code `plugin.json` `version` fields SHOULD mirror that canonical workflow version for source readability and fallback clarity.
- Ralph plugin bundle releases MAY declare `x-copilot-fc.bundleVersionOverride` in the source manifest to set the published plugin version independently from the workflow version.
- Build or publish automation MUST stamp bundled `plugin.json` manifests from `x-copilot-fc.bundleVersionOverride` when present, otherwise from the canonical workflow version before publication.
- Beta/stable channel handling MAY change bundle names, install names, registration paths, or bundled agent filenames, but MUST NOT change or suffix the canonical Ralph workflow version.

## Source-First Update Rule

- Contract changes land in source OpenSpec and source Ralph surfaces first.
- Generated bundle output under `plugins/*/.build/` is derived and MUST be refreshed by build/publish automation, not manual edits.
- Public summaries SHOULD point readers to the normative OpenSpec artifact when more detail is required instead of inventing local variants of the same rule.

## Public Surface Checklist

Use this checklist when touching README or other summary surfaces:

| Area | Expected normalized contract |
| --- | --- |
| State names | `ITERATION_REVIEW`, `ITERATION_CRITIQUE_REPLAN`, `SESSION_REVIEW` used with final semantics |
| Iteration review artifact | `iterations/<N>/review.md` |
| Session retrospective artifact | `.ralph-sessions/<SESSION_ID>/session-review.md` |
| Concurrency source of truth | Orchestration owns the matrix; summary surfaces mirror it without redefining it |
| Critique-loop terminology | Iteration-scoped wording only |
| Version governance | Wrapper frontmatter version is canonical; manifests mirror; bundles are stamped |
| Channel behavior | Channel identity is orthogonal to version numbers |
| Migration language | No temporary or retained-state wording in public summaries |
