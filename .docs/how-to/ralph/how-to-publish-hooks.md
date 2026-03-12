---
category: how-to
---

# How to Publish Hooks

This guide shows you how to publish hook configurations from the authoring `hooks/` directory to their deployment locations using `publish-hooks.ps1`.

## When to Use This Guide

Use this when you have authored or modified hook files in `hooks/` and need to deploy them so VS Code discovers them at runtime. Covers both repo-scoped (default) and user-level (opt-in) publishing.

## Prerequisites

- PowerShell 7+ (`pwsh`) available on your system.
- Hook manifests exist under `hooks/<name>/` (for example, `hooks/ralph-tool-logger/ralph-tool-logger.hooks.json`).
- Familiarity with the deployment model — see [Workspace-Level Hook Deployment Model](../../reference/ralph/workspace-level-hook-deployment-model.md) for why workspace-level is the default.

## Steps

### 1. Publish to Workspace (Default)

Run the publish script with no extra flags to copy hook manifests discovered under `hooks/<name>/` to `.github/hooks/`:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1
```

This is the recommended default. `.github/hooks/` is an auto-discovered VS Code hook search path — no settings changes are needed.

### 2. Publish Specific Hooks

To publish only named hooks (without the `.hooks.json` extension):

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Hooks "ralph-tool-logger"
```

Multiple hooks can be specified as a comma-separated string:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Hooks "ralph-tool-logger,security-policy"
```

### 3. Overwrite Existing Hooks

By default, existing hooks at the destination are skipped. Use `-Force` to overwrite:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Force
```

### 4. Publish as User-Level Hooks (Opt-In)

To publish a hook as a user-level hook in `~/.copilot/hooks/` (and WSL mirror if available), select the user-level scope:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Scope user-level
```

This performs four user-level actions:

1. Copies hook manifests to `~/.copilot/hooks/` on Windows.
2. Mirrors to `~/.copilot/hooks/` inside WSL (if WSL is detected).
3. Copies referenced hook scripts into the published user-level hook tree, preserving hook-relative subpaths such as `ralph-tool-logger/scripts/`.
4. Rewrites script paths in the published hook JSON from workspace-relative paths to full user-level paths, then updates `chat.hookFilesLocations` in VS Code settings to include both `.github/hooks` and `~/.copilot/hooks/`.

> **Important**: User-level hooks fire in *every* workspace - only use `-Scope user-level` when you intentionally want cross-workspace hook activation. The `chat.hookFilesLocations` VS Code setting is required for user-level path discovery since `~/.copilot/hooks/` is not a default search path.

> **Compatibility note**: `-UserLevel` still works as a legacy alias, but new automation should prefer `-Scope user-level`.

### 5. Validate the Published Hook

After publishing, confirm the hook file exists at the target:

```powershell
# Workspace-level check
Test-Path ".github\hooks\ralph-tool-logger.hooks.json"

# User-level check (only if -Scope user-level was used)
Test-Path "$env:USERPROFILE\.copilot\hooks\ralph-tool-logger.hooks.json"

# User-level script check
Test-Path "$env:USERPROFILE\.copilot\hooks\ralph-tool-logger\scripts\ralph-tool-logger.ps1"
```

Verify VS Code discovers the hooks by opening the Command Palette and running **Developer: Show Running Extensions** — hook-related activity appears in the Copilot output channel.

## Troubleshooting

**Problem: Published hook is not firing**
Workspace-level hooks must be in `.github/hooks/` — verify the file was copied there, not just `hooks/`. The `hooks/` directory is the authoring source; it is not a discovery path.

**Problem: User-level hook not discovered**
Ensure `chat.hookFilesLocations` in your VS Code `settings.json` includes `~/.copilot/hooks/`. The publish script sets this automatically in user-level mode, but manual edits may have removed it.

**Problem: Hook script path not resolving**
Repo-scoped hooks can keep workspace-relative paths (for example, `hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh`). In user-level mode the publish script copies referenced scripts into `~/.copilot/hooks/ralph-tool-logger/scripts/` and rewrites the published hook JSON to use full user-level paths. If a user-level hook still has a relative script path, republish it with `-Force -Scope user-level`.

## See Also

- [Workspace-Level Hook Deployment Model](../../reference/ralph/workspace-level-hook-deployment-model.md) — deployment architecture and rationale
