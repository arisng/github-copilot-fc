---
category: reference
source_session: 260302-001737
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-2 report (agent-variant-proposal update)"
  - "Iteration 3 task-5 report (directory structure and git mv)"
extracted_at: "2026-03-02T15:06:27+07:00"
promoted: true
promoted_at: "2026-03-02T15:17:25+07:00"
---

# Agent Variant Directory Convention

## Overview

Multi-runtime agent variants use a nested subdirectory convention under each agent group. Each runtime gets its own folder, with shared content elevated to the parent level.

## Directory Layout

```
agents/<agent-group>/
├── cli/                         # CLI runtime variants
│   ├── <agent-group>.agent.md
│   ├── <agent-group>-executor.agent.md
│   └── ...
├── vscode/                      # VS Code runtime variants
│   ├── <agent-group>.agent.md
│   ├── <agent-group>-executor.agent.md
│   └── ...
├── docs/                        # Shared documentation
├── specs/                       # Shared specifications
└── README.md                    # Shared README
```

## Key Decisions

- **VS Code agents live in `<agent-group>/vscode/`**: Moved via `git mv` from the agent group root to preserve git history. Each variant is a thin file (~28–30 lines) referencing a shared instruction.
- **CLI agents live in `<agent-group>/cli/`**: Created from scratch with CLI-specific tool namespaces and `infer` settings.
- **Shared content stays at parent level**: `README.md`, `docs/`, `specs/` remain at `agents/<agent-group>/` — they are not runtime-specific.
- **Non-variant agents are unaffected**: Agents without multi-runtime needs (e.g., `agents/planner.agent.md`) stay at `agents/` root.

## Advantages

1. **Encapsulation**: All variants for an agent group are co-located under one parent — no scattered `agents/cli/` at root level.
2. **Symmetry**: `vscode/` and `cli/` are structural siblings, making the design self-documenting.
3. **Discovery simplicity**: Glob patterns like `agents/*/vscode/*.agent.md` and `agents/*/cli/*.agent.md` reliably discover all variants by platform.

## Extensibility

Future runtimes (e.g., `cloud/`) are added as new subdirectories under the agent group:

```
agents/<agent-group>/<new-runtime>/
```

The checklist for adding a new runtime:
1. Create `agents/<agent-group>/<runtime>/` directory.
2. Create agent variant files with runtime-appropriate tool namespaces and settings.
3. Update publish scripts to discover from `agents/*/<runtime>/`.
4. Run `validate-agent-variants.ps1` to check deny-list compliance.
