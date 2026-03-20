---
category: reference
---

# Workspace-Level Hook Deployment Model

## Summary

VS Code Copilot hooks should be deployed to `.github/hooks/` (repo-scoped, historically called workspace-level) rather than `~/.copilot/hooks/` (user-level). Repo-scoped deployment is a default VS Code search path, while user-level is not - user-level requires explicit `chat.hookFilesLocations` settings customization and is best reserved for intentionally shared cross-workspace hooks.

## Why Workspace-Level Is Default

1. **Blast-radius scoping**: Workspace-level hooks fire only in the workspace that contains them. User-level hooks fire in every workspace, which is rarely desired for project-specific tooling.
2. **Script path resolution**: Hook `command` fields resolve relative to the workspace root. A user-level `hooks.json` cannot reliably find scripts located in a specific workspace unless the published copy rewrites those script paths to user-level full paths.
3. **Default discovery**: `.github/hooks/` is a default VS Code hook search path. `~/.copilot/hooks/` is **not** a default path and requires adding it to `chat.hookFilesLocations` in VS Code settings.

## Deployment Layout

```text
<workspace>/
├── .github/hooks/                           # Workspace-level (default, auto-discovered)
│   └── ralph-tool-logger.hooks.json
├── hooks/                                   # Authoring source (not directly discovered)
│   └── ralph-tool-logger/
│       ├── ralph-tool-logger.hooks.json
│       └── scripts/
│           ├── ralph-tool-logger.ps1
│           └── ralph-tool-logger.sh
```

## Publish Script Contract

`scripts/publish/publish-hooks.ps1` supports two modes:

| Mode | Command | Target | Discovery |
|------|---------|--------|-----------|
| Repo-scoped (default) | `publish-hooks.ps1` | `.github/hooks/` | Automatic |
| User-level (opt-in) | `publish-hooks.ps1 -Scope user-level` | `~/.copilot/hooks/` + WSL | Requires `chat.hookFilesLocations` |

The `-Scope user-level` mode performs four user-level operations: Windows `~/.copilot/hooks/` publish, WSL mirror, referenced script copy (for example into `~/.copilot/hooks/ralph-tool-logger/scripts/`), and published command-path rewrite to full user-level paths. `-UserLevel` remains as a legacy alias for compatibility.

## Key Constraint

Hook manifest `command` values use workspace-relative paths (for example, `hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh`). These paths only resolve correctly when the manifest is discovered from the workspace that contains the scripts. The publish script therefore keeps repo-scoped manifests unchanged, but rewrites user-level published copies to full paths under `~/.copilot/hooks/`.

## Related references

- [Copilot Hook Discovery and Publishing Model](../copilot/shared/copilot-hook-discovery-and-publishing-model.md)
- [How to Publish Hooks](../../how-to/ralph/how-to-publish-hooks.md)
