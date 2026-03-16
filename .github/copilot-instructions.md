# GitHub Copilot Instructions for Copilot FC Workspace

Use this file for in-repo authoring of Copilot artifacts (not external publishing docs).

## Big picture
- This workspace is a **customization factory**: `agents/`, `hooks/`, `instructions/`, `prompts/`, `skills/`, `tools/`, `plugins/`, plus publish/automation scripts in `scripts/`.
- Authoring is workspace-first by design (see `README.md` and `skills/README.md`): artifacts are created here, then published to personal folders (`~/.copilot/`, `~/.codex/`, `%APPDATA%/Code*/User/prompts`) via publish scripts.
- `.docs/` is the workspace wiki, organized using the **Diátaxis framework** (tutorials, how-to, reference, explanation), with domain sub-folders (copilot, openspec, ralph, blazor-agui). Must use skills `diataxis` and `diataxis-categorizer` for maintenaning this wiki.
- `.archived/` content is deprecated/superseded; do not use archived files as references/templates for new work.

## Architecture and boundaries

### Agent Customization Primitives
- **Agents** (`*.agent.md`) define persona, tool access, and orchestration; `description` is the only required frontmatter field; include `name` and `tools` as needed.
- **Instructions** (`*.instructions.md`) define policy/workflows using `description` + `applyTo` frontmatter; they prescribe which skills to invoke.
- **Skills** are folder-based (`skills/<name>/SKILL.md`), with optional `scripts/`, `references/`, and `assets/` subdirectories; `name` and `description` in SKILL.md frontmatter drive discovery. Keep SKILL.md lean — offload detailed docs to `references/`.
- **Agent Hook files** (`*.hooks.json`): lifecycle hooks authored in `hooks/`, published to `.github/hooks/`. Support cross-runtime scripts (`.ps1` for Windows, `.sh` for Bash/WSL).
- **Tools inventory** (`tools/`): cross-runtime tool inventory plus the active VS Code `tools/vscode/toolsets/` folder. CLI and GitHub.com tool mappings are documented in `tools/inventory.md` and applied in runtime-specific agent/docs authoring rather than separate workspace toolset folders.
- **Prompts** (`*.prompt.md`): user-facing workflow shortcuts (git, changelog, Ralph orchestration, plugin creation).
- **Plugins** (`plugins/<runtime>/<name>/plugin.json`): self-contained CLI bundles of agents + skills + hooks; installed via `copilot plugin install`. Only 6 official component fields: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers` — the `instructions` field does NOT exist in plugin.json.
- **OpenSpec Specs** follow the SDD convention in `openspec/specs/ralph-v2-orchestration/<domain>/spec.md`. Specs are runtime-agnostic (shared across VS Code, CLI, and Cloud), unlike agent files which are runtime-specific. 8 domains: session, signals, orchestration, planning, discovery, execution, review, knowledge.

### Runtime variants (VS Code vs CLI)
- Agent files have runtime-specific variants: `agents/<name>/vscode/*.agent.md` and `agents/<name>/cli/*.agent.md`.
- VS Code agents use `@SubAgentName` mention syntax; CLI agents use `task("AgentName-CLI", "...")`.
- CLI agents embed instructions at build time via `<!-- EMBED: filename.instructions.md -->` markers (resolved by `publish-plugins.ps1`).
- CLI agent markdown body limit: **30,000 characters** (YAML frontmatter excluded). Monitor large instruction files.
- `.plugin-managed` marker in a directory prevents `publish-agents.ps1` and `publish-skills.ps1` from syncing that artifact (plugin system owns it).
- CLI frontmatter uses `disable-model-invocation: true` (not the retired `infer: false`).

## File and naming conventions
- Custom Agents: `agents/<name>.agent.md` (standalone) or `agents/<name>/<runtime>/<name>-<runtime>.agent.md` (variants)
- Agent Hooks: `hooks/<name>/<name>.hooks.json`
- Custom Instructions: `instructions/<name>.instructions.md`
- Agent-specific private instructions: `agents/<name>/instructions/*.instructions.md` (tightly coupled to that agent workflow)
- Custom Prompts: `prompts/*.prompt.md`
- Tools inventory root: `tools/`
- VS Code Toolsets: `tools/vscode/toolsets/*.toolsets.jsonc`
- Plugins: `plugins/<runtime>/<name>/plugin.json` (runtime = `cli` or `vscode`)
- OpenSpec Specs: `openspec/specs/ralph-v2-orchestration/<domain>/spec.md`
- Skills: `skills/<name>/SKILL.md` with optional `scripts/`, `references/`, `assets/`
- Use forward slashes in markdown links, even on Windows paths.
- Kebab-case for directory and file names.

## Critical workflows

### Publishing
- Publish scripts are source of truth for distribution: `scripts/publish/publish-*.ps1` and router `scripts/publish/publish-artifact.ps1`.
- Artifact flow: workspace source → specialized publish helper → personal folder (`~/.copilot/`, `%APPDATA%/Code*/`) → optional WSL mirror (via `scripts/publish/wsl-helpers.ps1`).
- Plugin publishing builds runtime-scoped bundles under `plugins/<runtime>/.build/<name>/`, embeds instructions via marker resolution, validates 30K body limit, then publishes by runtime: CLI bundles are installed from the resulting local bundle with `copilot plugin install <local_plugin_path>` (treat `_direct/...` only as an observed cache location), while VS Code bundles are registered in `chat.plugins.paths`.
- Hooks are authored in `hooks/` and published to `.github/hooks/` via `scripts/publish/publish-hooks.ps1`.

### Other workflows
- Treat scripts as primary workflow entry points; VS Code tasks are optional wrappers over the same scripts.
- Workspace command dispatcher is `scripts/workspace/run-command.ps1`, with built-in command mapping (no external manifest required). Key commands: `agents:publish`, `skills:publish`, `hooks:publish`, `instructions:publish`, `prompts:publish`, `toolsets:publish`, `issues:reindex`.
- Issue indexing: `scripts/issues/extract-issue-metadata.ps1` reads `{.docs,_docs}/issues/*.md`, supports YAML frontmatter and legacy metadata formats, writes `index.md`.
- OpenSpec validation: `scripts/openspec/validate-cross-refs.ps1` (dangling requirement IDs), `validate-rfc2119.ps1` (keyword + scenario coverage), `validate-runtime-leaks.ps1` (forbidden runtime-specific terms in specs).
- Changelog generation: `scripts/changelog/create-weekly-changelog.ps1` — auto-generates from git history, supports raw/conventional formats.

## Terminal-first execution (editor agnostic)
- Windows PowerShell: `pwsh -NoProfile -File scripts/workspace/run-command.ps1 list`
- Bash/WSL: `pwsh -NoProfile -File scripts/workspace/run-command.ps1 list`
- Publish one artifact: `pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name diataxis`
- Publish all skills: `pwsh -NoProfile -File scripts/publish/publish-skills.ps1`
- Publish plugin: `pwsh -NoProfile -File scripts/publish/publish-plugins.ps1`
- Reindex issues: `pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1`
- Validate specs: `pwsh -NoProfile -File scripts/openspec/validate-cross-refs.ps1`
- If using VS Code tasks, keep behavior consistent with the commands above; do not add task-only logic.

## Tooling and execution norms
- Use PowerShell for workspace/publishing automation; use Python for logic/testing utilities.
- Run Python as `python3` (not `python`).
- For `scripts/**/*.ps1`, keep function-based PowerShell style with approved verbs and robust error handling (see `instructions/powershell.instructions.md`).
- Keep automation callable from both Windows and Linux/WSL terminals; avoid assumptions tied to VS Code APIs.

## Common pitfalls
- **Regex backreference corruption**: PowerShell's `-replace` operator interprets `$0`, `$&`, `$+` as regex tokens. Use `[Regex]::Replace($input, $pattern, { param($m) $literal })` with a script block evaluator for dynamic replacements.
- **VS Code prompts directory collision**: instructions and toolsets both publish to `%APPDATA%/Code*/User/prompts` — naming must avoid conflicts.
- **CLI instructions not concatenated**: `publish-instructions.ps1` intentionally excludes CLI instruction concatenation due to context overload risk.
- **Wildcard quoting**: Callers must quote glob patterns at CLI (`publish-agents.ps1 -Agents "*ralph*"`) to prevent PowerShell expansion.
- **Plugin re-install required**: `copilot plugin install` caches files — local changes require re-install.

## High-value examples
- Single-agent (Standalone agent) template: `agents/planner.agent.md`.
- Multi-agent orchestration pattern: `agents/ralph-v2/README.md` (6 agents, state machine, session structure).
- Runtime variant agents: `agents/ralph-v2/vscode/` and `agents/ralph-v2/cli/`.
- Instruction authoring reference: `create-instructions.prompt.md` (C:\Users\ADMIN\.vscode-insiders\extensions\github.copilot-chat-0.39.2026030507\assets\prompts\create-instructions.prompt.md - this prompt is from VS Code's extension and version-specific, version might be changed overtime).
- Skill authoring reference: `create-skill.prompt.md` (C:\Users\ADMIN\.vscode-insiders\extensions\github.copilot-chat-0.39.2026030507\assets\prompts\create-skill.prompt.md - this prompt is from VS Code's extension and version-specific, version might be changed overtime).
- Prompt authoring reference: `create-prompt.prompt.md` (C:\Users\ADMIN\.vscode-insiders\extensions\github.copilot-chat-0.39.2026030507\assets\prompts\create-prompt.prompt.md - this prompt is from VS Code's extension and version-specific, version might be changed overtime).
- Cross-runtime skill publishing: `scripts/publish/publish-skills.ps1`.
- Plugin bundling with instruction embedding: `scripts/publish/publish-plugins.ps1`.
- OpenSpec behavioral specification: `openspec/specs/ralph-v2-orchestration/orchestration/spec.md`.
