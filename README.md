# Copilot FC

**FC** (inspired by "football club") embodies the collaborative spirit of a professional team where specialized AI components work together harmoniously toward shared coding victories. Just as football players pass, defend, and score as a cohesive unit, Copilot FC orchestrates AI assistants, skills, and tools as a unified team—fostering the team-sport mentality where every component contributes to collective development excellence.

A dedicated workspace for developing, versioning, and publishing GitHub Copilot customizations, including Custom Agents, Context Instructions, Prompts, and Claude Skills.

## 🚀 Features

- **Custom Agents**: Specialized AI personas defined in `agents/*.agent.md` for specific tasks (e.g., Research, Documentation, Architecture).
- **Instructions**: Context-aware guidelines in `instructions/` to steer AI behavior for specific file types or folders.
- **Claude Skills**: Domain-specific capabilities and tools stored in `skills/` that extend Copilot's functionality.
- **Agent Evaluation**: Deterministic framework for evaluating and activating the right agents for the job.
- **Automation**: PowerShell and Python scripts to manage the lifecycle of skills, agents, and evaluations.

## 📂 Project Structure

```text
.
├── agents/                 # Custom Agent definitions (.agent.md) - BY DESIGN: Located here instead of .github/ to avoid duplication when VS Code scans synced user settings
├── skills/                 # Domain-specific skills (each in its own folder) - BY DESIGN: Located here instead of .claude/skills/ to avoid duplication when VS Code scans both workspace and user home locations
├── instructions/           # Context instructions (.instructions.md) - BY DESIGN: Located here instead of .github/ to avoid duplication when VS Code scans synced user settings
├── prompts/                # Reusable prompt templates - BY DESIGN: Located here instead of .github/ to avoid duplication when VS Code scans synced user settings
├── scripts/                # PowerShell and Python automation scripts
├── .docs/issues/           # Project documentation and issue tracking
└── copilot-workspace.json  # Workspace configuration
```

## 🏗️ Architecture Decisions

### Component Locations: Workspace Root vs VS Code Scan Paths

**By Design**: All GitHub Copilot customizations are intentionally located in workspace root directories (not in VS Code's standard scan locations) to prevent duplication.

**The Problem**: VS Code scans for customizations in both:
- **Synced user settings locations** (published versions)
- **Workspace scan paths** (like `.github/`, `.claude/skills/`)

Since this workspace is for authoring, versioning, and publishing customizations to VS Code's synced user settings, having them in both places causes duplication.

#### GitHub Copilot Customizations (Agents, Instructions, Prompts)

- **VS Code scans**: `.github/` (workspace) + VS Code User Settings (synced)
- **Our locations**: `agents/`, `instructions/`, `prompts/` (not `.github/`)

#### Claude Skills

- **VS Code scans**: `.claude/skills/` (workspace) + `~/.claude/skills/` (user home)
- **Our location**: `skills/` (not `.claude/skills/`)

**Workflow**:
1. **Author** customizations in workspace root directories (not scanned by VS Code)
2. **Publish** to VS Code's synced user settings or personal locations (globally available)
3. **Use** across all workspaces and devices without duplication

**Authoring Workflow**:
1. **Create/Edit** customizations in their respective directories (`agents/`, `instructions/`, `prompts/`, `skills/`)
2. **Test Locally** in this workspace (customizations are available here)
3. **Publish** using the appropriate script when ready for global use
4. **Sync** happens automatically across your VS Code installations

## 🛠️ Getting Started

### Prerequisites

- **VS Code**
- **GitHub Copilot** & **GitHub Copilot Chat** extensions
- **PowerShell** (for automation scripts)
- **Python 3.x** (for agent evaluation and advanced tools)

### Installation

1. Clone this repository.
2. Open the folder in VS Code.
3. Ensure the recommended extensions are installed.

## 📖 Usage

### Working with Agents

Agents are defined in the `agents/` directory. To create a new agent:

1. Create a new file `agents/<agent-name>.agent.md`.
2. Use the `Meta-Agent` or reference `agents/meta.agent.md` for the required schema.
3. Define the agent's `name`, `description`, and `tools` in the YAML frontmatter.

### Agent Evaluation

The workspace includes a deterministic evaluation framework to ensure the right agents are activated for each task.

- **Forced Evaluation**: The `instructions/agent-forced-eval.instructions.md` file (when published) instructs Copilot to evaluate available subagents before responding.
- **Tool-Based Evaluation**: For deterministic results, use the Python-based evaluator:

  ```powershell
  python scripts/agent_evaluator.py "Your query here"
  ```

### Authoring Customizations

All GitHub Copilot customizations are managed through automated publishing scripts:

#### Agents

```powershell
# Publish all agents to VS Code
.\scripts\publish-agents.ps1

# Publish specific agents
.\scripts\publish-agents.ps1 -Agents "meta", "instruction-writer"
```

#### Instructions

```powershell
# Publish all instructions to VS Code
.\scripts\publish-instructions.ps1

# Publish specific instructions
.\scripts\publish-instructions.ps1 -Instructions "powershell", "claude-skills"
```

#### Prompts

```powershell
# Publish all prompts to VS Code
.\scripts\publish-prompts.ps1

# Publish specific prompts
.\scripts\publish-prompts.ps1 -Prompts "changelog", "conventional-commit"
```

#### Claude Skills

```powershell
# Copy method (recommended)
.\scripts\publish-skills.ps1 -Method Copy

# Link method (for development)
.\scripts\publish-skills.ps1 -Method Link -Skills "git-atomic-commit", "issue-writer"

# Check for updates
.\scripts\update-personal-skills.ps1 -CheckOnly

# Apply updates
.\scripts\update-personal-skills.ps1
```

All published customizations are stored in VS Code's user data directory (`~/AppData/Roaming/Code/User/prompts/`) and synced across your devices.

### Documentation

Project issues and documentation are stored in `.docs/issues/`.

- To reindex issue metadata:

  ```powershell
  ./scripts/extract-issue-metadata.ps1
  ```

## ⚙️ Configuration

The workspace is configured via `copilot-workspace.json`. This file defines the directory structure, available commands, and VS Code settings.

## 🤝 Contributing

- Follow the conventions defined in `.github/copilot-instructions.md`.
- Use **PowerShell** for automation tasks and **Python** for complex logic/tools.
- Ensure all new agents include proper YAML frontmatter.
