# VS Code Toolsets

This folder contains the actual VS Code `.toolsets.jsonc` files used by this workspace.

## Notes

- `tools/vscode/toolsets/` is the publish source for `scripts/publish/publish-toolsets.ps1`.
- These files use VS Code tool names exactly as required by the runtime.
- Not every VS Code toolset has a direct CLI or GitHub.com equivalent.

## Relationship to the Inventory

- `tools/inventory.md` explains the important tool concepts across runtimes.
- The `.toolsets.jsonc` files in `toolsets/` are the concrete VS Code runtime artifacts.
