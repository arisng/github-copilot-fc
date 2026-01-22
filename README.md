# Copilot FC

A workspace for building and publishing GitHub Copilot customizations: Custom Agents, Custom Instructions, Prompts, and Agent Skills.

## 🚀 Quickstart

1. Create or edit a customization in `agents/`, `instructions/`, `prompts/`, or `skills/`.
2. Test locally in this workspace.
3. Publish with the appropriate script in `scripts/`.

## 📦 What’s Inside

- **Custom Agents**: `agents/*.agent.md`
- **Custom Instructions**: `instructions/*.instructions.md`
- **Copilot Prompts**: `prompts/copilot/`
- **Codex Prompts**: `prompts/codex/`
- **Agent Skills**: `skills/<skill-name>/`
- **Publishing**: `scripts/publish/`

## 🎯 Scope by Artifact

- **Custom Agents**: Copilot only.
- **Custom Instructions**: Copilot only.
- **Prompts**:
  - **Copilot**: Author prompts in `prompts/copilot/` (files end with `.prompt.md`).
  - **Codex**: Author prompts in `prompts/codex/` (Codex custom prompt files).
- **Skills**: Shared across multi-agent platforms (Copilot, Codex, Claude).

## 🧭 Why These Folders

Customizations live in workspace root folders (not `.github/` scan paths) to avoid duplicates when VS Code also scans synced user settings.

## 🛠️ Publish (Common)

- Agents: `scripts/publish/publish-agents.ps1`
- Instructions: `scripts/publish/publish-instructions.ps1`
- Prompts: `scripts/publish/publish-prompts.ps1`
- Skills: `scripts/publish/publish-skills.ps1`

## 🧯 Troubleshooting

- **PowerShell blocked**: Set execution policy or run as admin.
- **Python missing**: Install Python 3 and ensure it’s on PATH.
- **Changes not syncing**: Re-run publish script and confirm VS Code sync is enabled.

## ⚙️ Configuration

Workspace configuration is defined in `copilot-fc.json` (or via `COPILOT_WORKSPACE_FILE`).

## 🤝 Contributing

- Follow conventions in `.github/copilot-instructions.md`.
- Use **PowerShell** for publishing tasks and **Python** for complex logic/tools.
