---
category: how-to
source_session: 260302-001737
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-4 report (shared instruction extraction)"
extracted_at: "2026-03-02T15:06:27+07:00"
promoted: true
promoted_at: "2026-03-02T15:17:25+07:00"
---

# How to Extract Shared Instructions from Agent Files

## Goal

Extract platform-agnostic body content from agent files into shared `.instructions.md` files, enabling multiple runtime variants to reference the same core logic without duplication.

## Prerequisites

- Agent files with substantial body content (orchestration rules, workflows, contracts) that is not platform-specific.
- A target `instructions/` directory for shared instruction files.

## Steps

### 1. Identify Platform-Agnostic Content

Review each agent file and classify content into:
- **Platform-agnostic** (shared): Persona, artifacts, rules, workflows, signals, contracts — anything that defines *what* the agent does, not *how* it invokes tools.
- **Platform-specific** (stays in agent): YAML frontmatter (`tools:`, `agents:`, `infer:`), tool namespace references (`execute/runInTerminal`, `bash`), delegation syntax (`@AgentName`, `task()`), MCP server bindings.

### 2. Create Shared Instruction Files

For each agent, create `instructions/<agent-group>-<role>.instructions.md` with:

```yaml
---
description: <One-line description of the role>
applyTo: "<glob pattern matching work directories>"
---
```

Copy the platform-agnostic body content verbatim. Ensure zero VS Code-specific or CLI-specific tool references remain in the body.

### 3. Thin the Agent Files

Replace the original agent body with a reference stub:

```markdown
[original YAML frontmatter — unchanged]
---

# <Role> (<Runtime>)

> **Shared instructions**: <relative-path>/instructions/<agent-group>-<role>.instructions.md
> You MUST read the shared instruction file above before proceeding.

## <Runtime> Platform Notes
- Tool references: [runtime-specific tool names]
- [Role-specific runtime capabilities]
```

Each thinned agent should be ~28–30 lines.

### 4. Validate

- **Platform-neutrality grep**: Search shared instructions for runtime-specific patterns. Zero matches expected.
- **`@AgentName` check**: No VS Code `@AgentName` delegation syntax in shared instructions.
- **Path resolution**: Verify relative paths from agent files to instruction files resolve correctly.
- **Line count match**: Total body lines in shared instructions should match total body lines removed from agents.
- **Runtime test**: Confirm the host runtime still loads the shared instruction via the `applyTo` pattern.

## Key Design Notes

- The `applyTo` field in shared instructions uses the same glob pattern as the agents, ensuring the runtime lists the instruction as a context candidate when working in that scope.
- Shared instruction extraction MUST precede CLI variant creation — CLI variants depend on having shared instructions to reference.
- The reference mechanism uses a markdown blockquote with "You MUST read" directive, not a formal import — the runtime's `applyTo` handles actual loading.
