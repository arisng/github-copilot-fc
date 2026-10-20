# Tools Inventory

This folder is the single source of truth for cross-runtime tool authoring in this workspace.

## Purpose

- Keep one machine-readable inventory of important tool concepts across runtimes.
- Keep runtime-specific toolsets close to the inventory that explains them.
- Keep the workspace focused on the runtime artifacts that are still actively maintained.

## Runtime Dimensions

| Key | Runtime |
|---|---|
| `cli` | GitHub Copilot CLI |
| `vscode` | VS Code extension host (editor window) |
| `github_copilot` | GitHub.com Copilot / cloud agent |
| `agent_host` | VS Code Agent Host — the process behind the Agents window and the Copilot SDK harness. Optional: when omitted an entry inherits the `cli` spellings, because the Agent Host's Copilot harness runs the Copilot SDK runtime and therefore speaks the Copilot CLI tool vocabulary. Set it explicitly only when the Agent Host differs (`[]` marks a VS Code-extension-host-only tool). |

See `.docs/reference/copilot/vscode/copilot-vscode-agent-host-tools.md` for the Agent Host model.

## Category Taxonomy

Each category answers one question. Use it to find the entry you need.

| Category | Question |
|---|---|
| `core-built-in` | Which tool concepts exist across runtimes? (`execute`, `read`, `edit`, `search`, `agent`) |
| `limited-applicability` | Which tool concepts exist in only some runtimes? (`web`, `todo`) |
| `builtin-mcp` | Which MCP namespaces does the product ship with, with no extra setup? |
| `custom-mcp` | Which MCP tool sets require the user to configure the server? |
| `cli-surface` | What does the Copilot CLI ship with beyond the shared concepts? |
| `vscode-surface` | What does the VS Code extension host ship with beyond the shared concepts? |
| `agent-host` | What does the VS Code Agent Host expose (Agents window, Copilot SDK harness)? |

Entry ids carry a runtime prefix (`cli-`, `vscode-`, `agent-host-`) when the entry describes one runtime's surface; concept and MCP entries are unprefixed.

A runtime's concrete tool inventory belongs in that runtime's `*-surface` category, and an MCP tool set belongs in `custom-mcp`. There is deliberately no catch-all bucket for "tools that exist in one runtime only".

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
