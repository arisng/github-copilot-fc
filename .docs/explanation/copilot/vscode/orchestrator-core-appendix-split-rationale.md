---
category: explanation
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-5 task definition"
  - "Iteration 9 task-5 report"
  - "Iteration 9 plan FDB-020 SC-3"
  - "Iteration 9 session review SC-3"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# Orchestrator Core/Appendix Split Rationale

## Problem

The Copilot CLI enforces a **30,000-character maximum on the Markdown body** of a custom agent file (YAML frontmatter is excluded from this count). The Ralph-v2 Orchestrator instruction body approaches this limit, making it infeasible to embed the entire instruction set in a single CLI-compatible agent file.

## Solution: Core + Appendix Split

The Orchestrator instructions are split into two files:

| File | Purpose | CLI compatible? |
|------|---------|----------------|
| `agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md` | Core orchestrator instructions — fits the CLI body limit | ✅ Yes (VS Code + CLI) |
| `agents/ralph-v2/instructions/ralph-v2-orchestrator-appendix.instructions.md` | Overflow content too large for CLI | ❌ No (VS Code only) |

## Size Context

- **Core body**: ~27,967 characters (97.5% of the 30K limit)
- **Total with appendix**: ~46,400 characters (would exceed CLI limit by ~55%)
- **CLI plugin**: The appendix is excluded from the `.build/` bundle because the CLI cannot load it

## Scope of the Appendix

The appendix carries:
- Extended state machine reference tables
- Detailed protocol edge-case documentation
- Content that reference-type readers need but execution-time agents do not

## Configuration

Both files use `applyTo: ".ralph-sessions/**"` to scope to Ralph session files. The appendix is a VS Code-only supplement — it is never embedded into CLI plugin bundles.

## Why Not Trim the Core?

The orchestrator instructions are dense by design: they encode a full state machine, signal protocol, and multi-agent coordination logic. Trimming the core would require removing semantically critical content. The appendix pattern preserves full VS Code fidelity while allowing a working (if reduced) CLI variant.
