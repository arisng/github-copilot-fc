# About Copilot FC workspace commands

This explanation discusses *why* the workspace uses a script-based command router and key design decisions.

## Background

The workspace centralizes conventions and common operations through scripts so contributors and coding agents can run the same workflows from terminal environments.

## Core concept

`scripts/workspace/run-command.ps1` is intentionally lightweight: a built-in command surface rather than an external configuration dependency. It provides runnable commands for common tasks.

## Design tradeoffs

- Using PowerShell scripts is pragmatic for Windows-first contributors and still works in Linux/WSL when `pwsh` is available.
- Keeping commands as explicit script entries gives transparency and reduces hidden coupling to editor-specific configuration files.

## Comparison to alternatives

- Versus per-project Makefiles or editor-only task runners: the current approach keeps command entry points in repository scripts and avoids editor lock-in.

## Further reading

- **Learn it**: [.docs/tutorials/getting-started-with-copilot-fc.md](../tutorials/getting-started-with-copilot-fc.md)
- **Use it**: [.docs/how-to/how-to-use-copilot-fc-commands.md](../how-to/how-to-use-copilot-fc-commands.md)
- **Details**: [.docs/reference/copilot-fc-reference.md](../reference/copilot-fc-reference.md)
