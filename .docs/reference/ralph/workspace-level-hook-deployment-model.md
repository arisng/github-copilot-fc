---
category: reference
---

# Workspace-Level Hook Deployment Model

## Summary

VS Code Copilot hooks should be deployed to `.github/hooks/` (workspace-level) rather than `~/.copilot/hooks/` (user-level). Workspace-level deployment is a default VS Code search path, while user-level is not — user-level requires explicit `chat.hookFilesLocations` settings customization.

## Why Workspace-Level Is Default

1. **Blast-radius scoping**: Workspace-level hooks fire only in the workspace that contains them. User-level hooks fire in every workspace, which is rarely desired for project-specific tooling.
2. **Script path resolution**: Hook `command` fields resolve relative to the workspace root. A user-level `hooks.json` cannot reliably find scripts located in a specific workspace.
3. **Default discovery**: `.github/hooks/` is a default VS Code hook search path. `~/.copilot/hooks/` is **not** a default path and requires adding it to `chat.hookFilesLocations` in VS Code settings.

## Deployment Layout

```
<workspace>/
├── .github/hooks/                  # Workspace-level (default, auto-discovered)
│   └── ralph-tool-logger.hooks.json
├── hooks/                          # Authoring source (not directly discovered)
│   ├── ralph-tool-logger.hooks.json
│   └── scripts/
│       ├── ralph-tool-logger.ps1
│       └── ralph-tool-logger.sh
```

## Publish Script Contract

`scripts/publish/publish-hooks.ps1` supports two modes:

| Mode | Command | Target | Discovery |
|------|---------|--------|-----------|
| Workspace-only (default) | `publish-hooks.ps1` | `.github/hooks/` | Automatic |
| User-level (opt-in) | `publish-hooks.ps1 -UserLevel` | `.github/hooks/` + `~/.copilot/hooks/` + WSL | Requires `chat.hookFilesLocations` |

The `-UserLevel` switch gates all user-level operations: Windows `~/.copilot/hooks/` copy, WSL mirror, and VS Code settings update.

## Key Constraint

Hook manifest `command` values use workspace-relative paths (e.g., `hooks/scripts/ralph-tool-logger.sh`). These paths only resolve correctly when the manifest is discovered from the workspace that contains the scripts.
