# GitHub Copilot Instructions for Copilot FC Workspace

This repository is a **Copilot FC Workspace** for developing and managing Custom Agents, Claude Skills, and Instructions.

## Project Structure & Architecture
- **Agents** (`agents/*.agent.md`): Custom AI personas for VS Code. **BY DESIGN**: Located in `agents/` (not `.github/`) to avoid duplication when VS Code scans synced user settings. Defined using YAML frontmatter and markdown instructions.
- **Skills** (`skills/`): Domain-specific capabilities. **BY DESIGN**: Located in `skills/` (not `.claude/skills/`) to avoid duplication when VS Code scans both workspace and user home locations. Managed via PowerShell scripts.
- **Instructions** (`instructions/`): Context-specific guidelines (e.g., `*.instructions.md`). **BY DESIGN**: Located in `instructions/` (not `.github/`) to avoid duplication when VS Code scans synced user settings.
- **Prompts** (`prompts/`): Reusable prompt templates. **BY DESIGN**: Located in `prompts/` (not `.github/`) to avoid duplication when VS Code scans synced user settings.
- **Scripts** (`scripts/`): PowerShell automation for workspace management.
- **Issues** (`.docs/issues/`): Project documentation and tracking.

## Development Workflows
- **Creating Agents**: Create `agents/<name>.agent.md`. Reference `agents/meta.agent.md` for schema and best practices.
- **Creating Instructions**: Use `agents/instruction-writer.agent.md` or reference `instructions/meta.instructions.md`.
- **Managing Skills**: Source: `skills/<skill-name>/` (managed via PowerShell scripts).
- **Publishing**: Use automated scripts to publish specific customizations to VS Code's synced user settings (e.g., `publish-agents.ps1 -Agents "agent-name"`, `publish-skills.ps1 -Method Copy -Skills "skill-name"`).
- **Meta-tools Note**: Meta-tools like `meta.agent.md` and `instruction-writer.agent.md` instruct users to save files in `.github/` locations (standard VS Code paths) since these tools are published for use in other projects.
- **Documentation**:
  - Create issues in `.docs/issues/`.
  - Reindex metadata: `scripts/extract-issue-metadata.ps1`.

## Conventions
- **Scripting**: Use **PowerShell** (`.ps1`) for all automation tasks.
- **Paths**: Use forward slashes `/` in markdown links, even on Windows.
- **Agent Definition**: Always include `name`, `description`, and `tools` in YAML frontmatter.
- **Skill Structure**: Each skill resides in its own subdirectory within `skills/`.

## Key Commands
- **Publish Agents**: `powershell -File scripts/publish-agents.ps1 -Agents "agent-name"`
- **Publish Skills**: `powershell -File scripts/publish-skills.ps1 -Method Copy -Skills "skill-name"`
- **Publish Instructions**: `powershell -File scripts/publish-instructions.ps1 -Instructions "instruction-name"`
- **Publish Prompts**: `powershell -File scripts/publish-prompts.ps1 -Prompts "prompt-name"`
- **Reindex Issues**: `powershell -File scripts/extract-issue-metadata.ps1`
