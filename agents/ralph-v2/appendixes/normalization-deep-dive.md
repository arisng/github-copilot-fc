# Normalization Deep Dive

> **Status**: Implemented in v2.2.0 (2026-02-15)

This appendix defines how shared state is normalized at iteration scope. The normalization described here was proposed in the v2.1.0 timeframe and fully implemented in v2.2.0.

## Principles

- **SSOT first**: Each canonical fact lives in exactly one place.
- **Derived views are disposable**: Summaries must be regenerable and never authoritative.
- **Iteration scope favors normalization**: Keep iteration artifacts minimal and canonical.
- **Session scope allows denormalization**: Aggregate for readability, but never write back.

## Normalized vs Denormalized Boundaries

**Normalize (iteration scope, authoritative):**
- `iterations/<N>/progress.md` (status markers for tasks)
- `iterations/<N>/tasks/<id>.md` (task definition, dependencies, criteria)
- `iterations/<N>/metadata.yaml` (timing, iteration-level status)
- `iterations/<N>/reports/<id>-report*.md` (attempt history; append-only)
- `iterations/<N>/plan.md` (current plan with Replanning History)
- `iterations/<N>/questions/<category>.md` (Q&A by category)
- `iterations/<N>/knowledge/{tutorials,how-to,reference,explanation}/` (Diátaxis-categorized knowledge)

**Session scope (authoritative, non-iteration):**
- `metadata.yaml` (session-level state machine SSOT — Orchestrator-owned)
- `signals/inputs/` and `signals/processed/` (session-level signal mailbox)

**Denormalize (session scope, non-authoritative):**
- Session dashboards or summaries (rollups across iterations)
- Human-friendly overviews (e.g., completion tables)
- Any generated index or snapshot that duplicates task state

**Boundary rule:** If an artifact can be regenerated from normalized sources, it must be labeled non-authoritative.

## Iteration Scope Enforcement

**Goal:** maximize normalization inside iteration containers.

- Keep all mutable state for iteration N inside `iterations/<N>/`.
- Session-level `metadata.yaml` is the ONLY mutable artifact outside iteration containers.
- `signals/` stays at session level because humans can send signals at any time regardless of iteration.
- Avoid copying task statuses into multiple places.
- Only one place may track task status: `iterations/<N>/progress.md`.

**Anti-patterns:**
- Duplicating task status in `iterations/<N>/tasks/<id>.md` and `iterations/<N>/progress.md`.
- Maintaining multiple summary files with conflicting counts.
- Editing denormalized summaries to fix canonical data.
- Storing `plan.md`, `tasks/`, `progress.md`, or `reports/` at session root (pre-v2.2.0 pattern).

**Removed artifacts (v2.2.0):**
- `plan.iteration-N.md` — replaced by inline Replanning History in `iterations/<N>/plan.md`
- `delta.md` and `replanning/` directory — rationale captured in Replanning History section

## Session Scope Denormalization

**Goal:** allow human-friendly views without affecting correctness.

Recommended denormalized artifacts:
- `session.summary.md` (read-only, regenerated)
- `iterations/<N>/state.index.md` (read-only rollup)

**Labeling requirement:**
- Add a header: "Non-authoritative. Regenerate from SSOT." on all denormalized views.

## Normalization Map (Implemented)

| Fact | SSOT Location | Allowed Denormalized Views |
| --- | --- | --- |
| Task status | `iterations/<N>/progress.md` | session summary tables |
| Task definition | `iterations/<N>/tasks/<id>.md` | aggregated task list |
| Iteration timing | `iterations/<N>/metadata.yaml` | iteration rollup tables |
| Attempt outcomes | `iterations/<N>/reports/<id>-report*.md` | session QA summary |
| Current plan | `iterations/<N>/plan.md` | — |
| Q&A categories | `iterations/<N>/questions/<category>.md` | — |
| Session state | `metadata.yaml` (session root) | — |
| Signal mailbox | `signals/inputs/` (session root) | — |
| Knowledge (Diátaxis) | `iterations/<N>/knowledge/{tutorials,how-to,reference,explanation}/` | — |

## Consistency Checks

Add lightweight checks before transitions:
- `iterations/<N>/progress.md` task list equals set of `iterations/<N>/tasks/*.md`
- No task status appears outside `iterations/<N>/progress.md`
- Iteration metadata exists at `iterations/<N>/metadata.yaml` for current iteration
- `metadata.yaml` at session root reflects current state machine position
- No mutable artifacts (plan, tasks, progress, reports, questions) exist at session root
- Knowledge carry-forward markers are valid (no `carried_from_iteration` > current iteration)

## Workflow Alignment

**Iteration mindset (normalize):**
- Keep the minimum canonical state per iteration.
- Prefer appending to reports over editing past attempts.
- Each iteration is self-contained: `plan.md`, `tasks/`, `progress.md`, `reports/`, `questions/`, `knowledge/`.

**Session mindset (denormalize):**
- Provide aggregated views for humans.
- Never allow session summaries to influence state transitions.
- Session `metadata.yaml` is the sole cross-iteration mutable artifact (state machine SSOT).
