# Tools Inventory

This folder is the single source of truth for cross-runtime tool authoring in this workspace.

## Purpose

- Keep one human-readable inventory of important tool concepts across runtimes.
- Keep runtime-specific toolsets close to the inventory that explains them.
- Keep the workspace focused on the runtime artifacts that are still actively maintained.

## Structure

- `inventory.md`: cross-runtime SSOT for important tool entries, aliases, defaults, and maintenance guidance.
- `vscode/toolsets/`: actual VS Code `.toolsets.jsonc` files and the publish source for `scripts/publish/publish-toolsets.ps1`.

## Authoring Rules

- Update `inventory.md` first when introducing or changing an important tool concept.
- Keep `tools/vscode/toolsets/` in sync when a VS Code runtime artifact changes.
- Keep runtime caveats in the runtime `README.md` files rather than overloading the inventory.
- For CLI and GitHub.com authoring, use `inventory.md` plus runtime-specific agent/docs updates rather than separate workspace toolset folders.

## Migration Note

The old root `toolsets/` folder has been replaced by `tools/vscode/toolsets/`. Legacy `tools/cli/`, `tools/github-copilot/`, and `tools/templates/` folders were removed after consolidation because they were no longer used by build or publish flows.
