# Grounding Sources for the Tools Inventory

The `copilot-cli-tools-inventory-refresh` skill verifies `tools/inventory.yaml` against two independent grounding sources: **official documentation** and **local CLI introspection**. Always consult both.

## 1. Official Documentation

| Source | URL | What to extract |
|--------|-----|-----------------|
| GitHub Copilot CLI command reference | <https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference> | Command-line commands, flags, and the **Tool availability values** section (concrete built-in tool names accepted by `--available-tools` / `--excluded-tools`) |
| Custom agents configuration | <https://docs.github.com/en/copilot/reference/custom-agents-configuration> | Agent `tools:` frontmatter aliases and MCP namespace conventions |
| Customization cheat sheet | <https://docs.github.com/en/copilot/reference/customization-cheat-sheet> | Cross-cutting alias/spelling quick reference |
| CLI plugin reference | <https://docs.github.com/en/copilot/reference/cli-plugin-reference> | Plugin-bundled tool/MCP surface |
| Overview of customizing Copilot CLI | <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/quickstart-for-customizing> | High-level customization surface |

Fetch via `web_fetch`. Note the command-reference page is long — use `start_index` pagination to reach the "Tool availability values" section.

## 2. Local CLI Introspection

Run these commands and capture output:

```powershell
copilot version          # -> cli_version metadata
copilot --help           # flags including --available-tools / --excluded-tools / --allow-tool / --deny-tool
copilot plugins list     # discovered MCP servers, skills, plugins, LSPs
```

Optionally, inside an interactive session: `/env` lists loaded instructions, MCP servers, skills, agents, hooks, plugins, LSPs, and extensions — useful for cross-checking discovered namespaces.

## 3. Workspace Corpus (`.docs/reference/copilot/cli/`)

These workspace reference pages are cross-checked during a refresh:

| File | Role |
|------|------|
| `.docs/reference/copilot/cli/cli-agent-valid-tool-aliases.md` | **Canonical CLI-frontmatter alias set** (`bash`, `view`, `edit`, `search`, `mcp_SERVERNAME_TOOLNAME`). Distinct from the inventory's conceptual `official_alias`. |
| `.docs/reference/copilot/cli/copilot-cli-customization-matrix.md` | Runtime-by-runtime tool namespace remapping and tool restriction mechanisms |
| `.docs/reference/copilot/cli/copilot-cli-help.md` | **Historical `--help` snapshot.** Predates v1.0.77 (still lists `--config-dir`, `--disable-parallel-tools-execution`). Regenerating it is OUT of scope for this skill; the drift report may flag it as stale. |
| `.docs/reference/copilot/shared/copilot-cli-programmatic-cheatsheet.md` | Programmatic invocation flags (`-p`, `--agent`, `--model`, env vars) |
| `tools/vscode/toolsets/*.toolsets.jsonc` | Concrete VS Code runtime spellings that must stay in sync with the inventory |

## 4. Known Deliberate Nuances (do not "fix" these away)

- **Alias vs concrete built-in split**: `official_alias` in the YAML is the *conceptual* cross-runtime alias (e.g. `execute`, `read`, `agent`), which differs from the CLI-frontmatter alias set (`bash`, `view`, `edit`, `search`) documented in `cli-agent-valid-tool-aliases.md`. Preserve both.
- **`create`**: valid as a concrete CLI built-in (`copilot-cli-file-write-family`), NOT valid as an agent `tools:` alias.
- **`runtime-dependent` / `(closest)` / `runtime-specific`** encodings: see the "Value Encoding Rules" in `SKILL.md`.
- **Curation over adoption**: the inventory lists *important* tools, not the entire live tool surface. The drift report proposes additions; the author decides.
