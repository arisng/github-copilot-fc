# Tools Inventory

## Purpose

This file is the primary cross-runtime inventory for important tools and tool namespaces used when authoring Copilot custom agents and related tool access in this workspace.

## How to use this inventory

- Treat this file as the **single source of truth** for tool concepts, aliases, defaults, and runtime caveats.
- Start here before editing agent `tools:` allowlists, runtime docs, or VS Code toolset files.
- Keep concrete VS Code artifacts in sync under `tools/vscode/toolsets/`.
- For copilot-cli and GitHub.com authoring, document the runtime spelling here and then apply it directly in agent frontmatter, flags, or runtime-specific docs.

## Maintenance workflow

When adding or changing a tool entry:

1. Update this file first.
2. Update any affected VS Code `.toolsets.jsonc` files under `tools/vscode/toolsets/`.
3. Update runtime docs if the supported spelling or behavior changed.
4. Validate with targeted searches, for example:
   - `rg "tools[\\\\/](cli|github-copilot|templates)" .`
   - `rg "tools/inventory.md|tools/vscode/toolsets" .`

## Source of truth boundaries

- **This file owns:** cross-runtime tool concepts, aliases, defaults, and caveats.
- **`tools/vscode/toolsets/` owns:** the concrete VS Code `.toolsets.jsonc` artifacts used by `scripts/publish/publish-toolsets.ps1`.
- **CLI / GitHub.com runtimes do not have workspace toolset folders anymore:** represent those runtimes here and in the relevant agent/docs instead of duplicating inventory-only YAML files.

## Inventory

Each entry lists:

- **Category**
- **Description**
- **Official alias**
- **CLI**
- **VS Code**
- **GitHub Copilot**
- **Default when unspecified**
- **Notes**
- **Sources**

### Core built-ins

#### `execute`

- **Category:** `core-built-in`
- **Description:** Shell command execution.
- **Official alias:** `execute`, `shell`
- **CLI:** `bash`
- **VS Code:** `execute/runInTerminal`, `execute/getTerminalOutput`
- **GitHub Copilot:** `execute`
- **Default when unspecified:** enabled if available
- **Notes:** Runtime naming differs; execution approval may still apply. See `workspace-terminal-family` below for the fuller VS Code terminal/test helper surface used in this workspace.
- **Sources:** `official custom-agent docs`, `.docs/reference/copilot/copilot-cli-customization-matrix.md`, `tools/vscode/toolsets/workspace-terminal.toolsets.jsonc`

#### `read`

- **Category:** `core-built-in`
- **Description:** File reading and inspection.
- **Official alias:** `read`
- **CLI:** `view`
- **VS Code:** `read/readFile`, `read/problems`, `read/terminalLastCommand`, `read/terminalSelection`
- **GitHub Copilot:** `read`
- **Default when unspecified:** enabled if available
- **Notes:** VS Code splits read-like behavior across multiple tools.
- **Sources:** `official custom-agent docs`, `tools/vscode/toolsets/workspace-read.toolsets.jsonc`

#### `edit`

- **Category:** `core-built-in`
- **Description:** File and directory modification.
- **Official alias:** `edit`
- **CLI:** `edit`
- **VS Code:** `edit/createDirectory`, `edit/createFile`, `edit/editFiles`
- **GitHub Copilot:** `edit`
- **Default when unspecified:** enabled if available
- **Notes:** In CLI, author-facing files typically use `edit`, not `create`.
- **Sources:** `official custom-agent docs`, `tools/vscode/toolsets/workspace-edit.toolsets.jsonc`

#### `search`

- **Category:** `core-built-in`
- **Description:** Repository and code search.
- **Official alias:** `search`
- **CLI:** `search`
- **VS Code:** `search/codebase`, `search/changes`
- **GitHub Copilot:** `search`
- **Default when unspecified:** enabled if available
- **Notes:** Keep search-only toolsets separate from read/edit when you want tighter agent scope.
- **Sources:** `official custom-agent docs`, `tools/vscode/toolsets/workspace-search.toolsets.jsonc`

#### `agent`

- **Category:** `core-built-in`
- **Description:** Delegation to another custom agent or subagent.
- **Official alias:** `agent`, `Task`
- **CLI:** `task`
- **VS Code:** `agent`
- **GitHub Copilot:** `agent`
- **Default when unspecified:** enabled if available
- **Notes:** CLI wrappers commonly use `task` as the runtime spelling.
- **Sources:** `official custom-agent docs`, `agents/ralph-v2/cli/ralph-v2-orchestrator-CLI.agent.md`

### Limited-applicability tool concepts

#### `web`

- **Category:** `limited-applicability`
- **Description:** Web fetch and search concept.
- **Official alias:** `web`
- **CLI:** workspace MCPs such as `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`
- **VS Code:** `web`, `fetch_content`, `brave_summarizer`, `brave_web_search`
- **GitHub Copilot:** `web`
- **Default when unspecified:** runtime-dependent
- **Notes:** Official docs list `web`, but it is not currently applicable for coding agents in the same way as core built-ins.
- **Sources:** `official custom-agent docs`, `tools/vscode/toolsets/web.toolsets.jsonc`

#### `todo`

- **Category:** `limited-applicability`
- **Description:** Structured task-list tool concept.
- **Official alias:** `todo`
- **CLI:** runtime-dependent
- **VS Code:** `todo`
- **GitHub Copilot:** `todo`
- **Default when unspecified:** runtime-dependent
- **Notes:** Useful as a concept in inventories; support differs by runtime.
- **Sources:** `official custom-agent docs`

### Built-in MCP namespaces

#### `github-namespace`

- **Category:** `builtin-mcp`
- **Description:** GitHub MCP namespace for repository operations.
- **Official alias:** `github/*`
- **CLI:** `github/*`
- **VS Code:** GitHub extension / MCP tools such as `search_repositories`
- **GitHub Copilot:** `github/*`
- **Default when unspecified:** enabled if available
- **Notes:** Treat namespace-level access separately from core built-ins.
- **Sources:** `official custom-agent docs`, `tools/vscode/toolsets/github-research.toolsets.jsonc`

#### `playwright-namespace`

- **Category:** `builtin-mcp`
- **Description:** Browser automation MCP namespace.
- **Official alias:** `playwright/*`
- **CLI:** `playwright/*`
- **VS Code:** runtime-dependent
- **GitHub Copilot:** `playwright/*`
- **Default when unspecified:** enabled if available
- **Notes:** Built-in namespace, but not currently used in this workspace's VS Code toolsets.
- **Sources:** `official custom-agent docs`

### Custom MCP and workspace helper tools

#### `microsoftdocs-namespace`

- **Category:** `custom-mcp`
- **Description:** Microsoft Learn documentation access.
- **Official alias:** `microsoftdocs/*`
- **CLI:** `microsoftdocs/*`
- **VS Code:** `microsoftdocs/mcp`
- **GitHub Copilot:** `microsoftdocs/*`
- **Default when unspecified:** enabled if configured
- **Notes:** Requires MCP availability in the target runtime/environment.
- **Sources:** `tools/vscode/toolsets/devlibs.toolsets.jsonc`, `agents/ralph-v2/cli/ralph-v2-questioner-CLI.agent.md`

#### `deepwiki-namespace`

- **Category:** `custom-mcp`
- **Description:** DeepWiki repository documentation access.
- **Official alias:** `deepwiki/*`
- **CLI:** `deepwiki/*`
- **VS Code:** `deepwiki`, `ask_question`
- **GitHub Copilot:** `deepwiki/*`
- **Default when unspecified:** enabled if configured
- **Notes:** Treat DeepWiki as a research namespace rather than a core built-in.
- **Sources:** `tools/vscode/toolsets/github-research.toolsets.jsonc`, `agents/ralph-v2/cli/ralph-v2-questioner-CLI.agent.md`

#### `context7-docs`

- **Category:** `custom-mcp`
- **Description:** Library documentation retrieval.
- **Official alias:** runtime-specific
- **CLI:** `mcp_docker/get-library-docs`, `mcp_docker/resolve-library-id`
- **VS Code:** `get-library-docs`, `resolve-library-id`
- **GitHub Copilot:** runtime-dependent
- **Default when unspecified:** enabled if configured
- **Notes:** This workspace currently uses Context7-style docs access in runtime-specific forms.
- **Sources:** `tools/vscode/toolsets/devlibs.toolsets.jsonc`

#### `brave-web-search`

- **Category:** `custom-mcp`
- **Description:** Brave web search and summarization.
- **Official alias:** runtime-specific
- **CLI:** `mcp_docker/brave_web_search`, `mcp_docker/brave_summarizer`
- **VS Code:** `brave_web_search`, `brave_summarizer`
- **GitHub Copilot:** runtime-dependent
- **Default when unspecified:** enabled if configured
- **Notes:** Useful for research-oriented toolsets; not a core built-in.
- **Sources:** `tools/vscode/toolsets/web.toolsets.jsonc`

#### `fetch-content`

- **Category:** `custom-mcp`
- **Description:** Direct page-content fetch.
- **Official alias:** runtime-specific
- **CLI:** `mcp_docker/fetch_content`
- **VS Code:** `fetch_content`
- **GitHub Copilot:** runtime-dependent
- **Default when unspecified:** enabled if configured
- **Notes:** Keep separate from general web search in toolset design.
- **Sources:** `tools/vscode/toolsets/web.toolsets.jsonc`

#### `sequentialthinking`

- **Category:** `utility`
- **Description:** Sequential reasoning helper.
- **Official alias:** runtime-specific
- **CLI:** `mcp_docker/sequentialthinking`
- **VS Code:** `sequentialthinking`
- **GitHub Copilot:** runtime-dependent
- **Default when unspecified:** enabled if configured
- **Notes:** Workspace utility often used in planner/research toolsets.
- **Sources:** `tools/vscode/toolsets/utils.toolsets.jsonc`

### Runtime-only families

#### `workspace-terminal-family`

- **Category:** `runtime-only`
- **Description:** VS Code terminal and test helper family used by the workspace terminal toolset.
- **Official alias:** runtime-specific
- **CLI:** `bash` (closest equivalent)
- **VS Code:** `runInTerminal`, `getTerminalOutput`, `awaitTerminal`, `killTerminal`, `runTests`, `testFailure`
- **GitHub Copilot:** `execute` (closest equivalent)
- **Default when unspecified:** runtime-dependent
- **Notes:** This is the concrete VS Code execution surface that sits underneath the cross-runtime `execute` concept.
- **Sources:** `tools/vscode/toolsets/workspace-terminal.toolsets.jsonc`

#### `vscode-memory`

- **Category:** `runtime-only`
- **Description:** VS Code memory helper.
- **Official alias:** runtime-specific
- **CLI:** `-`
- **VS Code:** `vscode/memory`
- **GitHub Copilot:** `-`
- **Default when unspecified:** n/a
- **Notes:** VS Code-only concept; no direct CLI equivalent.
- **Sources:** `tools/vscode/toolsets/utils.toolsets.jsonc`

#### `filesystem-readonly-family`

- **Category:** `runtime-only`
- **Description:** VS Code filesystem-readonly tool family.
- **Official alias:** runtime-specific
- **CLI:** `view`, `search` (closest)
- **VS Code:** `directory_tree`, `list_allowed_directories`, `list_directory_with_sizes`, `list_directory`, `search_files`, `read_multiple_files`, `get_file_info`, `read_text_file`
- **GitHub Copilot:** `read`, `search` (closest)
- **Default when unspecified:** runtime-dependent
- **Notes:** Represents a VS Code-only grouping of fine-grained filesystem tools.
- **Sources:** `tools/vscode/toolsets/filesystem-read.toolsets.jsonc`

#### `github-gist-family`

- **Category:** `runtime-only`
- **Description:** Gist management tool family.
- **Official alias:** runtime-specific
- **CLI:** `-`
- **VS Code:** `create_gist`, `get_gist`, `list_gists`, `update_gist`
- **GitHub Copilot:** runtime-dependent
- **Default when unspecified:** runtime-dependent
- **Notes:** Current workspace has a VS Code toolset for Gist operations; other runtimes may not have equivalent built-ins.
- **Sources:** `tools/vscode/toolsets/github-gist.toolsets.jsonc`

## Notes

- Use this file as the reviewable inventory and runtime mapping sheet.
- Use runtime `README.md` files to explain how each runtime interprets these entries.
