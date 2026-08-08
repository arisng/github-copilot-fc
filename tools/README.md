# Tools Inventory

This folder is the single source of truth for cross-runtime tool authoring in this workspace.

## Purpose

- Keep one machine-readable inventory of important tool concepts across runtimes.
- Keep runtime-specific toolsets close to the inventory that explains them.
- Keep the workspace focused on the runtime artifacts that are still actively maintained.

## Structure

- `inventory.yaml`: cross-runtime SSOT for important tool entries, aliases, defaults, and maintenance guidance. The YAML schema is documented in the file header and enforced by the `copilot-cli-tools-inventory-refresh` skill (`.github/skills/copilot-cli-tools-inventory-refresh/`).
- `vscode/toolsets/`: actual VS Code `.toolsets.jsonc` files and the publish source for `scripts/publish/publish-toolsets.ps1`.

## Authoring Rules

- Update `inventory.yaml` first when introducing or changing an important tool concept.
- Keep `tools/vscode/toolsets/` in sync when a VS Code runtime artifact changes.
- Keep runtime caveats in the runtime `README.md` files rather than overloading the inventory.
- For CLI and GitHub.com authoring, use `inventory.yaml` plus runtime-specific agent/docs updates rather than separate workspace toolset folders.

## Maintaining the Inventory

To refresh the inventory against the latest GitHub Copilot CLI, invoke the `copilot-cli-tools-inventory-refresh` skill. It grounds the inventory in both the official CLI command reference and the local `copilot` binary (version, `--help`, `plugins list`), validates the YAML schema, and emits a drift report so entries stay current without blind auto-rewrites.

## Migration Note

The old root `toolsets/` folder has been replaced by `tools/vscode/toolsets/`. Legacy `tools/cli/`, `tools/github-copilot/`, and `tools/templates/` folders were removed after consolidation because they were no longer used by build or publish flows. In 2026-08, the inventory itself was converted from `inventory.md` to `inventory.yaml` for machine readability.
