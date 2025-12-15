# GitHub Copilot Instructions for Copilot FC Workspace

**Note:** This `copilot-instructions.md` file is workspace-specific and provides context only for this Copilot FC Workspace. It is not intended for external publishing.

This repository is a **Copilot FC Workspace** for developing and managing Custom Agents, Claude Skills, and Instructions.

## Project Structure & Architecture
- **Agents** (`agents/*.agent.md`): Custom AI personas. **BY DESIGN**: Located in `agents/` (not `.github/`) to avoid duplication with synced user settings.
- **Skills** (`skills/`): Domain-specific capabilities. **BY DESIGN**: Located in `skills/` (not `.claude/skills/`) to avoid duplication with user home locations.
- **Instructions** (`instructions/`): Context-specific guidelines. **BY DESIGN**: Located in `instructions/` (not `.github/`) to avoid duplication.
- **Prompts** (`prompts/`): Reusable prompt templates. **BY DESIGN**: Located in `prompts/` (not `.github/`) to avoid duplication.
- **Scripts** (`scripts/`): Automation for workspace management (PowerShell) and testing/evaluation (Python).
- **Issues** (`.docs/issues/`): Project documentation and tracking.

## Development Workflows
- **Code Review**: Always review and get explicit approval for changes before committing. Do not auto-commit without user confirmation.
- **Creating Components**:
  - **Agents**: Create `agents/<name>.agent.md`. Reference `agents/meta.agent.md`.
  - **Instructions**: Use `agents/instruction-writer.agent.md` or reference `instructions/meta.instructions.md`.
  - **Skills**: Create in `skills/<skill-name>/`.
- **Publishing**: Use automated scripts to publish specific customizations to VS Code's synced user settings.
  - **Copy Method**: Recommended for reliability.
  - **Link Method**: For development (Windows only, requires admin).
- **Testing**:
  - Python scripts/skills: Use `scripts/run_tests.py`.
  - PowerShell scripts: Use Pester (e.g., `*.Tests.ps1`).
- **Agent Evaluation**: Use `scripts/agent_evaluator.py` for deterministic agent selection logic.

## Conventions
- **Scripting**:
  - **PowerShell** (`.ps1`): For workspace management and publishing tasks.
  - **Python** (`.py`): For complex logic, testing, and skill implementations.
- **Paths**: Use forward slashes `/` in markdown links, even on Windows.
- **Agent Definition**: Always include `name`, `description`, and `tools` in YAML frontmatter.
- **Skill Structure**: Each skill resides in its own subdirectory within `skills/`.

## Key Commands
- **Publish Agents**: `powershell -File scripts/publish-agents.ps1 -Agents "agent-name"`
- **Publish Skills (Copy)**: `powershell -File scripts/publish-skills.ps1 -Method Copy -Skills "skill-name"`
- **Publish Skills (Link)**: `powershell -File scripts/publish-skills.ps1 -Method Link -Skills "skill-name"`
- **Publish Instructions**: `powershell -File scripts/publish-instructions.ps1 -Instructions "instruction-name"`
- **Publish Prompts**: `powershell -File scripts/publish-prompts.ps1 -Prompts "prompt-name"`
- **Run Python Tests**: `python scripts/run_tests.py`
- **Run Agent Evaluator**: `python scripts/agent_evaluator.py "YOUR QUERY"`
- **Reindex Issues**: `powershell -File scripts/extract-issue-metadata.ps1`
