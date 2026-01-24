# Copilot FC

A workspace for building and publishing GitHub Copilot customizations: Custom Agents, Custom Instructions, Prompts, Agent Skills, and Toolsets.

## 🚀 Quickstart

1. Create or edit a customization in `agents/`, `instructions/`, `prompts/`, `skills/`, or `toolsets/`.
2. Test locally in this workspace.
3. Publish with the appropriate script in `scripts/`.

## 📦 What’s Inside

- **Custom Agents**: `agents/*.agent.md`
- **Custom Instructions**: `instructions/*.instructions.md`
- **Prompts**: `prompts/`
- **Agent Skills**: `skills/<skill-name>/`
- **Toolsets**: `toolsets/*.toolsets.jsonc`
- **Documentation**: `.docs/` (Diátaxis-structured)
- **Publishing**: `scripts/publish/`

## 📚 Documentation

Documentation is organized using the [Diátaxis framework](https://diataxis.fr/) in `.docs/`:

- **Tutorials**: Learning-oriented guides for beginners
- **How-to Guides**: Goal-oriented instructions for specific tasks
- **Reference**: Technical descriptions of features and APIs
- **Explanation**: Background and conceptual information

Start with [.docs/index.md](.docs/index.md) for the documentation index.

## Scope by Artifact

- **Custom Agents**: Copilot only.
- **Custom Instructions**: Copilot only.
- **Prompts**: Copilot only.
- **Skills**: Shared across multi-agent platforms (Copilot, Codex, Claude).
- **Toolsets**: Copilot only. Chat toolsets for grouping related tools.

## 🧭 Why These Folders

Customizations live in workspace root folders (not `.github/` scan paths) to avoid duplicates when VS Code also scans synced user settings.

## 🛠️ Publishing

- Agents: `scripts/publish/publish-agents.ps1`
- Instructions: `scripts/publish/publish-instructions.ps1`
- Prompts: `scripts/publish/publish-prompts.ps1`
- Skills: `scripts/publish/publish-skills.ps1`
- Toolsets: `scripts/publish/publish-toolsets.ps1`

## 🧯 Troubleshooting

- **PowerShell blocked**: Set execution policy or run as admin.
- **Python missing**: Install Python 3 and ensure it’s on PATH.
- **Changes not syncing**: Re-run publish script and confirm VS Code sync is enabled.

## ⚙️ Configuration

Workspace configuration is defined in `copilot-fc.json` (or via `COPILOT_WORKSPACE_FILE`).

## 🤝 Contributing

- Follow conventions in `.github/copilot-instructions.md`.
- Use **PowerShell** for publishing tasks and **Python** for complex logic/tools.
