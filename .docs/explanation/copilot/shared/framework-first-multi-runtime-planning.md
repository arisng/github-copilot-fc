---
category: explanation
source_session: 260302-001737
source_iteration: 2
source_artifacts:
  - "Iteration 2 plan"
  - "Iteration 2 review"
  - "Iteration 2 task-3 report (runtime-support framework)"
extracted_at: 2026-03-02T12:35:33+07:00
promoted: true
promoted_at: 2026-03-02T12:41:22+07:00
---

# Framework-First Approach to Multi-Runtime Infrastructure

When extending a single-runtime workspace to support multiple target runtimes, the natural instinct is to jump straight to implementation — modify scripts, create variant files, and handle each gap individually. A more effective approach is to establish a reference framework document first and use it to drive all subsequent implementation decisions.

## The Problem with Implementation-First

Without a shared framework, each publish script redesign or artifact variant decision is made in isolation. This leads to:

- **Inconsistent terminology** — different scripts use different names for the same concepts (e.g., "target" vs. "destination" vs. "runtime")
- **Gap blindness** — implementation focuses on the most visible gaps while less obvious ones accumulate
- **Ad-hoc prioritization** — no systematic way to decide which artifact types to automate first
- **Repeated analysis** — each script author must independently research which runtimes support which artifacts

## The Framework-First Approach

Before writing any implementation code, create a structured reference document that maps every artifact type across every target runtime. The document should capture:

1. **Support matrix** — artifact types (rows) × runtimes (columns) with a three-state verdict per cell: Automated (supported + implemented), Manual (supported + not yet implemented), or N/A (runtime doesn't support this artifact type). The three states are critical — they distinguish "we can't do this" from "we haven't done this yet."

2. **Destination paths** — for each supported cell, the exact filesystem path where the artifact is published. Having these paths in one place prevents scripts from guessing or hardcoding inconsistent paths.

3. **Delivery mechanisms** — how each artifact reaches its destination (direct copy, concatenation, environment variable, repo-scoped only). Delivery mechanism determines the implementation pattern, so documenting it upfront prevents architectural surprises mid-implementation.

4. **Shareability assessment** — whether each artifact type can be shared across runtimes as-is, or requires per-runtime variants. This uses a three-level criterion: File Format compatibility (same file extension?), Semantic compatibility (same frontmatter schema?), and Behavioral compatibility (same runtime behavior?). Only artifacts passing all three levels are truly shareable.

5. **Gap analysis** — prioritized list of Manual cells that should be upgraded to Automated, with rationale for the priority ordering. This becomes the implementation roadmap.

## Why This Works

The framework document serves multiple roles:

- **Shared vocabulary** — all subsequent tasks use consistent terminology (verdicts, shareability tiers, delivery mechanisms), reducing ambiguity in task definitions and review criteria.
- **Implementation roadmap** — the gap analysis directly produces the task list. Priority 1 gaps become the current iteration's work; lower priorities feed the backlog.
- **Quality gate** — reviewers can cross-verify implementation claims against the framework's verdicts and paths, catching inconsistencies early.
- **Forward planning** — extensibility notes (e.g., "how to add a future Cloud runtime column") prevent implementations from baking in assumptions that block future expansion.

## Phasing Pattern

When adopting framework-first for multi-runtime work:

1. **Phase 1 — Framework + Infrastructure**: Create the reference framework document alongside shared utilities (e.g., a cross-platform helper module). These are independent and can be done in parallel.
2. **Phase 2 — Implementation**: Use the framework's gap analysis to drive script redesigns and new tooling. The framework provides target paths, delivery mechanisms, and priority ordering.
3. **Phase 3 — Architecture + Documentation**: Establish forward-looking patterns (variant models, directory conventions) and update existing documentation to reflect the new multi-runtime vocabulary.

This phasing prevents the common antipattern of building infrastructure without a clear model of what it serves, or documenting after the fact when details are already hazy.
