# GitHub Copilot FC

A dedicated workspace for developing, managing, and deploying GitHub Copilot customizations, including Custom Agents, Claude Skills, and Context Instructions.

## 🚀 Features

- **Custom Agents**: Specialized AI personas defined in `agents/*.agent.md` for specific tasks (e.g., Research, Documentation, Architecture).
- **Claude Skills**: Domain-specific capabilities and tools stored in `.claude/skills/` that extend Copilot's functionality.
- **Instructions**: Context-aware guidelines in `instructions/` to steer AI behavior for specific file types or folders.
- **Automation**: PowerShell scripts to manage the lifecycle of skills and agents.

## 📂 Project Structure

```text
.
├── agents/                 # Custom Agent definitions (.agent.md)
├── .claude/skills/         # Domain-specific skills (each in its own folder)
├── instructions/           # Context instructions (.instructions.md)
├── prompts/                # Reusable prompt templates
├── scripts/                # PowerShell automation scripts
├── .docs/issues/           # Project documentation and issue tracking
└── copilot-workspace.json  # Workspace configuration
```

## 🛠️ Getting Started

### Prerequisites

- **VS Code**
- **GitHub Copilot** & **GitHub Copilot Chat** extensions
- **PowerShell** (for automation scripts)

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

### Managing Skills

Skills are located in `.claude/skills/`. Use the provided scripts to manage them:

- **Publish Skills to Personal Library**:

  ```powershell
  # Copy mode (recommended for stability)
  ./scripts/publish-skills.ps1 -Method Copy
  
  # Link mode (for active development)
  ./scripts/publish-skills.ps1 -Method Link
  ```

- **Update Personal Skills**:

  ```powershell
  ./scripts/update-personal-skills.ps1
  ```

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
- Use **PowerShell** for all scripting tasks.
- Ensure all new agents include proper YAML frontmatter.
