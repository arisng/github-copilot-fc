---
category: reference
source_artifacts:
  - agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md
  - agents/ralph-v2/instructions/ralph-v2-librarian.instructions.md
  - agents/ralph-v2/README.md
  - agents/ralph-v2/specs/live-signals.spec.md
extracted_at: 2026-03-09T00:43:27+07:00
promoted: true
promoted_at: 2026-03-09T00:49:10+07:00
---

# Durable provenance for commit and knowledge outputs

## Purpose

This reference defines the durable-provenance rules that keep Ralph commit history and reader-facing knowledge understandable after session artifacts are deleted or archived.

## Commit output rules

- Commit scope, subject, and summaries must be derived from stable repository areas or behavior changes.
- COMMIT outputs must not depend on `.ralph-sessions/`, `iterations/<N>/...`, `knowledge/`, temporary report or test paths, session IDs, iteration numbers, or other ephemeral provenance.
- Durable commit messages should describe the repository contract or behavior change, not session bookkeeping.

## Knowledge output rules

- Reader-facing staged or promoted knowledge must stay self-contained.
- Staged and promoted knowledge must not preserve `.ralph-sessions/...`, `iterations/<N>/...`, `knowledge/`, report or test paths, session IDs, or iteration numbers as durable provenance.
- When staging or promoting, provenance must be rewritten to stable repository files, contracts, or concepts.

## Operational consequences

- EXTRACT may retain iteration-scoped traceability in frontmatter because the artifact is still iteration-local.
- STAGE and PROMOTE are the rewrite boundaries for converting transient provenance into durable repository-facing references.
- Reviewer COMMIT guidance and Librarian STAGE, PROMOTE, and COMMIT guidance must stay aligned so git history and published knowledge follow the same durable-provenance standard.

## Stable implementation points

- The durable commit rule is defined in `agents/ralph-v2/instructions/ralph-v2-reviewer.instructions.md`.
- The durable knowledge provenance and rewrite requirements are defined in `agents/ralph-v2/instructions/ralph-v2-librarian.instructions.md`.
- Supporting workflow and signal wording was aligned in `agents/ralph-v2/README.md` and `agents/ralph-v2/specs/live-signals.spec.md`.
