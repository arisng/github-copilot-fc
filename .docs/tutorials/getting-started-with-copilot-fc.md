# Getting started with Copilot FC

This tutorial shows you how to get the workspace running locally and where to find the `copilot-fc.json` manifest.

## When to use this tutorial
Use this when onboarding to the Copilot FC workspace or when you want a quick tour of how the manifest powers scripts and VS Code settings.

## Prerequisites
- Git and PowerShell available on Windows (or a compatible shell on other OS).
- VS Code installed with the recommended extensions.

## Steps
1. Clone the repository and open it in VS Code.

```powershell
git clone https://github.com/arisng/copilot-workspace.git
code copilot-workspace
```

2. Open `copilot-fc.json` to see the manifest (top-level config for the workspace). You can also set the `COPILOT_WORKSPACE_FILE` environment variable to point to a different `copilot-*.json` manifest.

3. Check available workspace commands from the `commands` section:

```powershell
# from repo root
powershell -ExecutionPolicy Bypass -File scripts/run-command.ps1 list
```

4. Run a sample command, for example to list skills:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-command.ps1 "workspace:list-skills"
```

5. Explore tasks in VS Code (Task Runner) to run `Publish Skills` or `Reindex Issues`.

## Next steps
- Read the [How-to guide](../how-to/how-to-use-copilot-fc-commands.md) for common workflows.
- See the [Reference](../reference/copilot-fc-reference.md) for a field-by-field schema. Note: the default filename is `copilot-fc.json` and you can override it via `COPILOT_WORKSPACE_FILE`.