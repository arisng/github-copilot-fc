# [File-Specific Instructions (.instructions.md)](https://docs.github.com/en/copilot/how-tos/copilot-cli/add-custom-instructions)

Guidelines loaded on demand for Copilot CLI based on task relevance, file patterns, and agent targeting.

## Locations

| Path | Scope |
|------|-------|
| `.github/instructions/*.instructions.md` | Repository |
| `<dir from COPILOT_CUSTOM_INSTRUCTIONS_DIRS>/*.instructions.md` | Additional local or shared instruction roots |

There is no special built-in `~/.copilot/instructions/` discovery rule. Use `.github/instructions/` for repository files and `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` when you need more instruction roots.

## Frontmatter

```yaml
---
description: "Use when refactoring CLI plugins, skills, or command packs. Covers packaging and publish checks."
name: "Optional instruction name"
applyTo: "plugins/cli/**/*.json"
excludeAgent: ["code-review"]
---
```

## Discovery Modes

| Mode | Trigger | Use Case |
|------|---------|----------|
| **On-demand** (`description`) | Agent detects task relevance | Task-based guidance such as migrations, packaging, or refactors |
| **Explicit** (`applyTo`) | Files matching the glob are being created or edited | Language or folder rules |
| **Scoped exclusion** (`excludeAgent`) | Prevents loading for named agents | Keep the wrong instruction away from `code-review`, `coding-agent`, or other agents |

## Template

```markdown
---
description: "Use when editing CLI hook files, hook scripts, or hook validation logic. Covers event names and safety checks."
---
# CLI Hook Guidelines

- Use lowercase CLI event names such as `preToolUse`
- Keep hook scripts fast and auditable
- Prefer repository hooks for shared policy
```

## `applyTo` Notes

Use focused globs:

```yaml
applyTo: "plugins/cli/**/*.json"
applyTo: ["skills/**/*.md", "plugins/cli/**/commands/*.md"]
applyTo: "**/*.ps1"
```

Avoid `applyTo: "**"` unless the instruction truly belongs everywhere.

## `excludeAgent` Notes

`excludeAgent` is useful when an instruction should not load for a specific agent:

```yaml
excludeAgent: ["code-review", "copilot-cli-agent-customization"]
```

Only exclude real agent names that exist in your runtime.

## Core Principles

1. **Keyword-rich descriptions**: Include trigger phrases for on-demand discovery
2. **One concern per file**: Separate packaging, testing, and style guidance
3. **Use `excludeAgent` intentionally**: Prevent noisy instructions from loading in the wrong workflow
4. **Prefer explicit globs over global attachment**: Narrow scope keeps the CLI context lean

## Anti-patterns

- **Assuming profile-style instruction folders are automatic**: Use repository roots or `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`
- **Broad `applyTo` without broad content**: This wastes context
- **Missing `description`**: On-demand discovery becomes weaker
- **Using instructions as command registration**: Commands and skills are the reusable workflow surfaces
