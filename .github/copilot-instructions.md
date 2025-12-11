# GitHub Copilot Instructions for Copilot FC Workspace

This repository is a **Copilot FC Workspace** for developing and managing Custom Agents, Claude Skills, and Instructions.

## Project Structure & Architecture
- **Agents** (`agents/*.agent.md`): Custom AI personas for VS Code. Defined using YAML frontmatter and markdown instructions.
- **Skills** (`.claude/skills/`): Domain-specific capabilities. Managed via PowerShell scripts.
- **Instructions** (`instructions/`): Context-specific guidelines (e.g., `*.instructions.md`).
- **Scripts** (`scripts/`): PowerShell automation for workspace management.
- **Issues** (`.docs/issues/`): Project documentation and tracking.

## Development Workflows
- **Creating Agents**: Create `agents/<name>.agent.md`. Reference `agents/meta.agent.md` for schema and best practices.
- **Managing Skills**:
  - Source: `.claude/skills/<skill-name>/`
  - Publish: Use `scripts/publish-skills.ps1` (Methods: Copy, Link).
  - Update: Use `scripts/update-personal-skills.ps1`.
- **Documentation**:
  - Create issues in `.docs/issues/`.
  - Reindex metadata: `scripts/extract-issue-metadata.ps1`.

## Conventions
- **Scripting**: Use **PowerShell** (`.ps1`) for all automation tasks.
- **Paths**: Use forward slashes `/` in markdown links, even on Windows.
- **Agent Definition**: Always include `name`, `description`, and `tools` in YAML frontmatter.
- **Skill Structure**: Each skill resides in its own subdirectory within `.claude/skills/`.

## Key Commands
- **Publish Skills**: `powershell -File scripts/publish-skills.ps1 -Method Copy`
- **Reindex Issues**: `powershell -File scripts/extract-issue-metadata.ps1`
