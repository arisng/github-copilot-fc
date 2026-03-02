---
category: explanation
source_session: 260302-001737
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-4 report (shared instruction extraction)"
  - "Iteration 3 task-6 report (CLI variant creation)"
extracted_at: "2026-03-02T15:06:27+07:00"
promoted: true
promoted_at: "2026-03-02T15:17:25+07:00"
---

# Shared Instruction Pattern: Why It Exists and Its Trade-offs

## The Problem

Custom agents for AI coding assistants often contain substantial platform-agnostic content — personas, workflow rules, state machines, signals, contracts — that defines *what* the agent does. When supporting multiple runtimes (VS Code, CLI, Cloud), duplicating this content across variant files creates a maintenance burden and drift risk.

## The Solution: Shared Instructions

The shared instruction pattern separates agent files into two layers:

1. **Shared instruction file** (`instructions/<group>-<role>.instructions.md`): Contains all platform-agnostic body content. Uses `applyTo` frontmatter to declare when the runtime should load it.
2. **Thin agent variant** (`agents/<group>/<runtime>/<role>.agent.md`): Contains only runtime-specific frontmatter (tool namespaces, `infer` settings, MCP bindings) and a reference to the shared instruction.

This enables a single source of truth for agent logic with ~28–30 line variants per runtime.

## How the Reference Mechanism Works

The thinned agent uses a markdown blockquote:

```markdown
> **Shared instructions**: ../../../instructions/<group>-<role>.instructions.md
> You MUST read the shared instruction file above before proceeding.
```

This is a **convention-based reference**, not a formal import. Actual loading relies on the instruction file's `applyTo` pattern (e.g., `".ralph-sessions/**"`), which causes the runtime to list it as a context candidate when the agent operates in that scope.

## Trade-offs

### Advantages

- **Single source of truth**: One instruction file per role, not N copies per runtime. Updates propagate automatically.
- **Thin variants**: Each runtime variant is ~28–30 lines — easy to review, diff, and maintain.
- **Clean separation of concerns**: "What the agent does" (instructions) vs. "how it invokes tools" (agent variant).
- **Scalability**: Adding a new runtime requires only a new thin variant, not duplicating thousands of lines.

### Disadvantages

- **Broad `applyTo` injection**: All shared instructions with the same `applyTo` pattern are context candidates simultaneously. For a 6-agent system, all 6 instruction files may be listed when the LLM operates in the matching scope — regardless of which agent is active. The runtime's context budget management handles prioritization, and each instruction starts with clear role-specific headers to mitigate confusion.
- **Indirect loading**: The "You MUST read" directive is a soft convention. If the runtime doesn't load the file via `applyTo`, the agent operates without its core instructions. This is mitigated by the `applyTo` pattern being stable and tested.
- **Relative path fragility**: Moving agent files changes the relative path to shared instructions. The convention of using `../../../instructions/` from `agents/<group>/<runtime>/` is stable as long as the directory structure is maintained.

## When to Use This Pattern

- **Use it when**: An agent group has 2+ runtime variants sharing substantial (>100 lines) platform-agnostic content. The overhead of maintaining shared instructions pays off quickly.
- **Don't use it when**: An agent is single-runtime with no variant plans, or the body content is minimal (<50 lines). The indirection adds complexity without meaningful deduplication.
