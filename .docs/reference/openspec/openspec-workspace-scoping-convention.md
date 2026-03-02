---
category: reference
source_session: 260302-142754
source_iteration: 1
source_artifacts:
  - "Iteration 1 task-16 report (directory reorganization)"
  - "Iteration 1 task-17 report (reference cascade update)"
  - "STEER signal for workspace-level scoping"
extracted_at: 2026-03-02T20:11:56+07:00
promoted: true
promoted_at: 2026-03-02T20:22:26+07:00
---

# OpenSpec Workspace Scoping Convention

The `openspec/` directory is a **workspace-level** container for all behavioral specifications in the repository. It is not scoped to any single workflow or project. Specs for specific workflows must be organized under named subdirectories.

## Directory Structure

```
openspec/
├── config.yaml              # Project-level OpenSpec configuration
├── changes/                  # Change proposals (deltas)
└── specs/
    └── ralph-v2-orchestration/   # ← Workflow-scoped subdirectory
        ├── session/spec.md
        ├── signals/spec.md
        ├── orchestration/spec.md
        ├── planning/spec.md
        ├── discovery/spec.md
        ├── execution/spec.md
        ├── review/spec.md
        └── knowledge/spec.md
```

## Rules

1. **Never place domain specs directly under `openspec/specs/`**. Domain specs must nest under a workflow-scoped subdirectory.
2. **Name the subdirectory after the workflow or system** it describes (e.g., `ralph-v2-orchestration/`, `ci-pipeline/`, `deploy-flow/`).
3. **`openspec/config.yaml`** remains at the workspace level and may reference multiple workflow subdirectories.
4. **Cross-workflow references** use the full path prefix: `ralph-v2-orchestration/session/SES-001`.

## Rationale

Placing domain specs directly under `openspec/specs/` (e.g., `openspec/specs/session/`) implicitly claims the entire OpenSpec namespace for a single workflow. When a second workflow's specs are added later, naming collisions are inevitable — two workflows could both define a "session" or "execution" domain. The subdirectory convention prevents this by scoping each workflow's domains under a unique namespace.

## Migration Pattern

When specs are already placed directly under `openspec/specs/`:

1. Create the target subdirectory: `openspec/specs/<workflow-name>/`
2. Move each domain directory using `git mv` to preserve history
3. Update all references in: `config.yaml`, `README.md`, `copilot-instructions.md`, validation scripts, and any instruction files
4. Verify `git status` shows `R` (rename) for all moved files — confirms history preservation

A reference cascade update across the workspace typically involves 5–10 files depending on how many documents reference the spec paths.
