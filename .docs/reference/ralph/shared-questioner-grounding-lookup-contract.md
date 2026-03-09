---
category: reference
source_artifacts:
  - agents/ralph-v2/instructions/ralph-v2-planner.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-executor.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-librarian.instructions.md
extracted_at: 2026-03-09T00:43:27+07:00
promoted: true
promoted_at: 2026-03-09T00:49:10+07:00
---

# Shared Questioner grounding lookup contract

## Purpose

This reference defines the finalized cross-role contract for consuming Questioner grounding so Planner, Executor, Reviewer, and Librarian all resolve the same artifact and freshness boundary.

## Resolution order

1. If `question_artifact_path` is present in delegated context or a prior Ralph payload, read that file first and treat it as the authoritative handoff artifact.
2. Otherwise, if the needed category is known, read the canonical category artifact at `iterations/<ITERATION>/questions/<category>.md`.
3. Only when one artifact is insufficient for the current mode, read additional canonical category artifacts under `iterations/<ITERATION>/questions/`.

Do not choose a preferred artifact from glob order, file timestamps, partial Q-ID overlap, or other role-local heuristics.

## Freshness rules

An artifact is fresh for the current answered cycle only when both conditions hold:

- Frontmatter `cycle` matches the latest `## Answers (Cycle <C>)` section in that same file.
- The questions relevant to the current handoff are marked `Status: Answered` inside that same answers cycle.

If either condition fails, treat grounding as stale or incomplete. Do not mix answers across cycles or silently fall back to a different artifact.

## Role obligations

- Planner, Executor, Reviewer, and Librarian must all use the same lookup order and freshness test.
- When grounding is stale or incomplete, the current role must return or delegate for refreshed Questioner grounding instead of rediscovering context locally.
- Downstream handoffs must preserve the resolved `question_artifact_path` so every role consumes the same grounding source.

## Stable implementation points

- The shared contract block is defined verbatim in `agents/ralph-v2/instructions/ralph-v2-planner.instructions.md`, `agents/ralph-v2/instructions/ralph-v2-executor.instructions.md`, `agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md`, and `agents/ralph-v2/instructions/ralph-v2-librarian.instructions.md`.
- Planner workflow steps that need Questioner grounding must route through this contract instead of using wildcard rediscovery.
