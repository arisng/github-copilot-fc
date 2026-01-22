# About `copilot-fc.json`

This explanation discusses *why* the workspace manifest exists and key design decisions. By default the project uses `copilot-fc.json`, but any file matching `copilot-*.json` is supported and `COPILOT_WORKSPACE_FILE` can override the chosen file.

## Background
A workspace manifest centralizes conventions, commands, and editor recommendations so contributors have a single source of truth. It evolved to make publishing and maintenance reproducible across machines and CI.

## Core concept
`copilot-fc.json` is intentionally lightweight: a mapping and command surface rather than a full platform. It documents what the repository exposes and provides runnable commands for common tasks.

## Design tradeoffs
- Using PowerShell scripts is pragmatic for Windows-first contributors and simplifies automation, but it reduces portability for non-Windows environments. Consider providing cross-platform wrappers if needed.
- Keeping `commands` as ad-hoc shell commands gives flexibility, but a typed command schema and JSON Schema validation would make CI checks stronger.

## Comparison to alternatives
- Versus per-project Makefiles or task runners: this manifest is a declarative map of commands and directories and integrates directly with VS Code recommendations, giving a better onboarding experience for VS Code users.

## Further reading
- **Learn it**: [.docs/tutorials/getting-started-with-copilot-fc.md](../tutorials/getting-started-with-copilot-fc.md)
- **Use it**: [.docs/how-to/how-to-use-copilot-fc-commands.md](../how-to/how-to-use-copilot-fc-commands.md)
- **Details**: [.docs/reference/copilot-fc-reference.md](../reference/copilot-fc-reference.md)