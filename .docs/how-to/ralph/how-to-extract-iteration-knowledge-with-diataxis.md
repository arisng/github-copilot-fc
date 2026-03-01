# How to extract iteration knowledge with Diátaxis

Use this workflow at the end of each Ralph-v2 iteration to capture reusable knowledge into the workspace wiki through a staging-first pipeline with human review gating.

## Prerequisites

- Session artifacts exist under `.ralph-sessions/<session-id>/`.
- Wiki root `.docs/` exists (auto-created by Librarian if missing).
- The Librarian agent (`Ralph-v2-Librarian`) is listed in the orchestrator's `agents` frontmatter.
- The Librarian is invoked in two modes during this workflow:
  - **MODE: STAGE** — steps 1–6 (extract and stage knowledge).
  - **MODE: PROMOTE** — steps 9–10 (promote approved knowledge to wiki).

## Steps

### Stage (Librarian — MODE: STAGE)

1. **Collect evidence** — Read iteration artifacts:
   - `.ralph-sessions/<session-id>/tasks/`
   - `.ralph-sessions/<session-id>/reports/`
   - `.ralph-sessions/<session-id>/plan.md`

2. **Filter for reusable knowledge** — Extract reusable knowledge only:
   - Include: stable processes, contracts, conventions, workflows, and decision rationale.
   - Exclude: transient logs, one-off errors, temporary experiments, and session-specific data.

3. **Classify** — Assign each item to exactly one Diátaxis category:
   - **Tutorial**: guided learning path for first-time execution.
   - **How-to**: goal-driven operational procedure.
   - **Reference**: factual lookup (schemas, commands, contracts).
   - **Explanation**: rationale and conceptual model.

4. **Stage** — Write each item to the iteration staging directory with YAML frontmatter:
   - `iterations/<N>/knowledge/tutorials/`
   - `iterations/<N>/knowledge/how-to/`
   - `iterations/<N>/knowledge/reference/`
   - `iterations/<N>/knowledge/explanation/`

   Each staged file includes frontmatter with traceability metadata:
   ```yaml
   ---
   category: how-to          # Diátaxis category
   source_session: 260213-154139
   source_iteration: 3
   source_artifacts:
     - reports/task-10-report.md
   staged_at: 2026-02-14T16:44:00+07:00
   ---
   ```

5. **Add traceability** — Ensure every staged page references the source artifacts it was derived from.

6. **Generate staging manifest** — Create or update `iterations/<N>/knowledge/index.md` listing all staged items with their categories and source references.

### Review (Human)

7. **Review staged content** — Human inspects the staged files in `iterations/<N>/knowledge/`:
   - Read items in each category directory.
   - Edit content for accuracy, clarity, or completeness.
   - Delete items that should not be promoted.

8. **Auto-promote (default) or opt-out** — Promotion proceeds automatically unless the human opts out:
   - **Default**: All remaining staged items are promoted to `.docs/` without requiring a signal.
   - **Opt-out**: To skip promotion, the human sends an `INFO` signal with `target: Librarian` and a message starting with `SKIP_PROMOTION:` — staged content is preserved in `iterations/<N>/knowledge/` for future manual promotion.

### Promote (Librarian — MODE: PROMOTE)

9. **Promote staged content** — Unless opt-out was signaled, copy all remaining items from `iterations/<N>/knowledge/{category}/` to `.docs/{category}/`:
   - `.docs/tutorials/`
   - `.docs/how-to/`
   - `.docs/reference/`
   - `.docs/explanation/`

   If a target file in `.docs/` was modified after the staged file's `staged_at` timestamp, log a conflict warning (best-effort detection; full merge deferred).

10. **Update wiki index** — Update `.docs/index.md` to reflect any files added or moved during promotion.

## Output rules

- Each staged knowledge item maps to exactly one Diátaxis category.
- Promoted items may merge with or update existing entries in `.docs/`.
- On opt-out (`INFO` + `SKIP_PROMOTION:`), no files are written to `.docs/`; staged content persists in `iterations/<N>/knowledge/` for reference.