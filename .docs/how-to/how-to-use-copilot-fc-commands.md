# How to use Copilot FC commands

This guide shows you how to use terminal-first workspace commands to publish artifacts and maintain the workspace.

## When to use this guide

Use this guide when you need to publish content (agents, prompts, skills) or run maintenance tasks (reindex issues).

## Before you start

- Ensure you have the repository checked out and PowerShell available.
- Have the minimal repo permissions needed to run publish tasks.

## Steps

### Run a pre-defined command

1. From the repository root, run the command router. Example: list skills.

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 "workspace:list-skills"
```

1. To publish skills:

```powershell
pwsh -NoProfile -File scripts/publish/publish-skills.ps1
```

### Add a new command to the router

1. Add an entry to the `$commands` mapping in `scripts/workspace/run-command.ps1` with a descriptive key and executable command.
1. Document the new command in `.docs/how-to/` with expected arguments and example usage.

## Troubleshooting

- Problem: Scripts fail with execution policy errors. Solution: Ensure `-ExecutionPolicy Bypass` is present or adjust policy with admin privileges.
- Problem: A script expects environment variables. Solution: Check script header and export required variables before running.

## Related

- [Reference: Copilot FC Reference](../reference/copilot-fc-reference.md)
- [Explanation: About workspace commands](../explanation/about-copilot-fc.md)
