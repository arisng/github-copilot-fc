# Getting started with Copilot FC

This tutorial shows you how to get the workspace running locally and discover terminal-first automation commands.

## When to use this tutorial

Use this when onboarding to the Copilot FC workspace or when you want a quick tour of how scripts power automation.

## Prerequisites

- Git and PowerShell available on Windows (or a compatible shell on other OS).
- `pwsh` available on PATH.

## Steps

1. Clone the repository and enter the folder.

```powershell
git clone https://github.com/arisng/copilot-workspace.git
Set-Location copilot-workspace
```

1. List available workspace commands:

```powershell
# from repo root
pwsh -NoProfile -File scripts/workspace/run-command.ps1 list
```

1. Run a sample command, for example to list skills:

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 "workspace:list-skills"
```

1. Run a publishing command (Skills CLI preferred; `publish-skills.ps1` is deprecated):

```bash
npx skills add <owner>/<repo> --all
```

## Next steps

- Read the [How-to guide](../../../../../how-to/copilot/shared/how-to-use-copilot-fc-commands.md) for common workflows.
- See the [Reference](../../../../../reference/copilot/shared/copilot-fc-reference.md) for command catalog and execution behavior.
