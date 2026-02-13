# Copilot FC Workspace Command Reference

This reference documents terminal-first command entry points for the workspace.

## Primary command router

- Script: `scripts/workspace/run-command.ps1`
- Behavior: executes a built-in command map (no external manifest dependency).
- Usage:

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 list
pwsh -NoProfile -File scripts/workspace/run-command.ps1 "skills:publish"
```

## Supported command keys

- `agents:publish`
- `instructions:publish`
- `prompts:publish`
- `skills:publish`
- `toolsets:publish`
- `issues:reindex`
- `workspace:list-skills`
- `workspace:status`

## Direct script entry points

- `scripts/publish/publish-agents.ps1`
- `scripts/publish/publish-instructions.ps1`
- `scripts/publish/publish-prompts.ps1`
- `scripts/publish/publish-skills.ps1`
- `scripts/publish/publish-toolsets.ps1`
- `scripts/publish/publish-artifact.ps1`
- `scripts/issues/extract-issue-metadata.ps1`

## Notes

- VS Code tasks are wrappers over these scripts.
- Keep command behavior consistent between terminal and task execution.
