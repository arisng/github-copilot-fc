---
category: reference
source_artifacts:
  - agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-planner.instructions.md
  - agents/ralph-v2/specs/normalization.spec.md
extracted_at: 2026-03-09T11:43:29+07:00
promoted: true
promoted_at: 2026-03-09T11:47:19+07:00
---

# Ralph iteration artifact reference normalization

## Purpose

This reference captures the durable normalization rule reinforced by the critique rerun: Ralph source instructions must keep iteration-scoped artifact references explicit so review sweeps can distinguish concrete workflow contracts from generic path templates.

## Normalization rule

- Use `iterations/<N>/...` when instruction text refers to concrete iteration artifacts.
- Use session-scoped paths only for truly session-level artifacts, such as `.ralph-sessions/<SESSION_ID>/session-review.md`.
- Bare artifact names like `plan.md`, `progress.md`, `tasks/`, `reports/`, and `questions/` are acceptable only when the text explicitly labels them as path-pattern or template examples.

## Review and rework implications

- Treat bare artifact references in source instruction rule text as a normalization defect during `ITERATION_REVIEW`.
- Fix the source instruction files directly before rerunning the iteration gate.
- Keep the rework narrowly scoped to the flagged references so the contract remains source-first and behaviorally unchanged.

## Stable examples

- `iterations/<N>/plan.md`
- `iterations/<N>/progress.md`
- `iterations/<N>/tasks/`
- `iterations/<N>/reports/`
- `iterations/<N>/questions/`
- `.ralph-sessions/<SESSION_ID>/session-review.md`

## Relationship to the finalized workflow contract

- This normalization rule complements the finalized Ralph workflow contract by preserving the boundary between iteration-scoped artifacts and session-scoped artifacts.
- Keeping those paths explicit makes the post-critique pipeline deterministic: EXTRACT can capture the reusable rule, then STAGE and PROMOTE can carry it forward before the targeted `ITERATION_REVIEW` rerun.

## Stable implementation points

- `agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md`
- `agents/ralph-v2/instructions/ralph-v2-planner.instructions.md`
- `agents/ralph-v2/specs/normalization.spec.md`