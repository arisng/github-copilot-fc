# Normalization Deep Dive

This appendix defines how to normalize shared state at iteration scope while allowing denormalized session views for human consumption.

## Principles

- **SSOT first**: Each canonical fact lives in exactly one place.
- **Derived views are disposable**: Summaries must be regenerable and never authoritative.
- **Iteration scope favors normalization**: Keep iteration artifacts minimal and canonical.
- **Session scope allows denormalization**: Aggregate for readability, but never write back.

## Normalized vs Denormalized Boundaries

**Normalize (iteration scope, authoritative):**
- `progress.md` (status markers for tasks)
- `tasks/<id>.md` (task definition, dependencies, criteria)
- `iterations/<N>/metadata.yaml` (timing, iteration-level status)
- `reports/<id>-report*.md` (attempt history; append-only)

**Denormalize (session scope, non-authoritative):**
- Session dashboards or summaries (rollups across iterations)
- Human-friendly overviews (e.g., completion tables)
- Any generated index or snapshot that duplicates task state

**Boundary rule:** If an artifact can be regenerated from normalized sources, it must be labeled non-authoritative.

## Iteration Scope Enforcement

**Goal:** maximize normalization inside iteration containers.

- Keep all mutable state for iteration N inside `iterations/<N>/` plus SSOT files.
- Avoid copying task statuses into multiple places.
- Only one place may track task status: `progress.md`.

**Anti-patterns:**
- Duplicating task status in `tasks/<id>.md` and `progress.md`.
- Maintaining multiple summary files with conflicting counts.
- Editing denormalized summaries to fix canonical data.

## Session Scope Denormalization

**Goal:** allow human-friendly views without affecting correctness.

Recommended denormalized artifacts:
- `session.summary.md` (read-only, regenerated)
- `iterations/<N>/state.index.md` (read-only rollup)

**Labeling requirement:**
- Add a header: "Non-authoritative. Regenerate from SSOT." on all denormalized views.

## Proposed Normalization Map

| Fact | SSOT Location | Allowed Denormalized Views |
| --- | --- | --- |
| Task status | `progress.md` | session summary tables |
| Task definition | `tasks/<id>.md` | aggregated task list |
| Iteration timing | `iterations/<N>/metadata.yaml` | iteration rollup tables |
| Attempt outcomes | `reports/<id>-report*.md` | session QA summary |

## Consistency Checks

Add lightweight checks before transitions:
- `progress.md` task list equals set of `tasks/*.md`
- No task status appears outside `progress.md`
- Iteration metadata exists for current iteration

## Workflow Alignment

**Iteration mindset (normalize):**
- Keep the minimum canonical state per iteration.
- Prefer appending to reports over editing past attempts.

**Session mindset (denormalize):**
- Provide aggregated views for humans.
- Never allow session summaries to influence state transitions.
