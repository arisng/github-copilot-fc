---
category: reference
source_artifacts:
  - openspec/specs/ralph-v2-orchestration/orchestration/spec.md
  - agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md
  - agents/ralph-v2/README.md
  - agents/ralph-v2/specs/normalization.spec.md
extracted_at: 2026-03-09T12:34:25+07:00
promoted: true
promoted_at: 2026-03-09T12:34:25+07:00
---

# Ralph finalized workflow contract

## Purpose

This reference captures the durable Ralph-v2 workflow contract so later staging and promotion can preserve the stable behavior without carrying iteration-specific report context forward.

## Canonical workflow states

- `ITERATION_REVIEW` is the blocking, iteration-scoped post-knowledge gate.
- `SESSION_REVIEW` is a distinct end-of-session retrospective, not a renamed iteration review.
- `ITERATION_CRITIQUE_REPLAN` is the canonical critique-loop state.

## Concurrency and sequencing rules

- Orchestration is the source of truth for cross-role parallelism and sequencing.
- Planner parallelism is limited to `TASK_CREATE`; other planning modes remain sequential.
- Questioner runs sequentially.
- Executors may run in parallel only for same-wave tasks after dependency guards are satisfied.
- Reviewer task reviews may run in parallel across distinct pending tasks in the same wave, but `TASK_REVIEW -> COMMIT` remains sequential per task.
- Librarian knowledge work is sequential and follows `EXTRACT -> STAGE -> PROMOTE -> COMMIT -> ITERATION_REVIEW`.

## Review artifact boundaries

- Iteration review writes the iteration-scoped review artifact under `iterations/<N>/review.md`.
- Session review writes the session-scoped retrospective under `.ralph-sessions/<SESSION_ID>/session-review.md`.
- The iteration review checklist includes live-signal completion before the iteration can assess as complete.
- The session retrospective stays minimal: executive summary first, then ordered iteration drill-down.

## Source-first maintenance rule

- Canonical Ralph workflow changes land in source instructions, specs, and documentation first.
- Generated plugin bundle output under `plugins/*/.build/` is derivative and must not be edited directly.

## Stable implementation points

- `openspec/specs/ralph-v2-orchestration/orchestration/spec.md` defines the canonical state machine and ordered handoff rules.
- `agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md` defines the cross-role concurrency and sequencing contract.
- `agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md` defines the iteration-review checklist and session-review structure.
- `agents/ralph-v2/README.md` and `agents/ralph-v2/specs/normalization.spec.md` summarize and normalize the public-facing contract.
