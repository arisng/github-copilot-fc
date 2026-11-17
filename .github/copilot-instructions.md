# GitHub Copilot Instructions for Copilot FC Workspace

Use this file for in-repo authoring of Copilot artifacts (not external publishing docs).

## Big picture

- This workspace is a **customization factory**: `agents/`, `hooks/`, `instructions/`, `skills/`, `tools/`, `plugins/`, plus publish/automation scripts in `scripts/`.
- Authoring is workspace-first by design (see `README.md` and `skills/README.md`): artifacts are created here, then published to personal folders (`~/.copilot/`, `~/.codex/`, `%APPDATA%/Code*/User/prompts`) via publish scripts.
- `.docs/` is the workspace wiki, organized using the **Diátaxis framework** (tutorials, how-to, reference, explanation), with domain sub-folders (copilot, ralph, blazor-agui). Must use skills `diataxis` and `diataxis-categorizer` for maintenaning this wiki.
- `.archived/` content is deprecated/superseded; do not use archived files as references/templates for new work.

## Architecture and boundaries

### Agent Customization Primitives

- **Agents** (`*.agent.md`) define persona, tool access, and orchestration; `description` is the only required frontmatter field; include `name` and `tools` as needed.
- **Instructions** (`*.instructions.md`) define policy/workflows using `description` + `applyTo` frontmatter; they prescribe which skills to invoke.
- **Skills** are folder-based (`skills/<name>/SKILL.md`), with optional `scripts/`, `references/`, and `assets/` subdirectories; `name` and `description` in SKILL.md frontmatter drive discovery. Keep SKILL.md lean — offload detailed docs to `references/`.
- **Agent Hook files** (`*.json`): lifecycle hooks authored in `hooks/`, published to `.github/hooks/`. Support cross-runtime scripts (`.ps1` for Windows, `.sh` for Bash/WSL).
- **Tools inventory** (`tools/`): cross-runtime tool inventory plus the active VS Code `tools/vscode/toolsets/` folder. CLI and GitHub.com tool mappings are documented in `tools/inventory.yaml` and applied in runtime-specific agent/docs authoring rather than separate workspace toolset folders.
- **Plugins** (`plugins/<runtime>/<name>/plugin.json`): self-contained CLI bundles of agents + skills + hooks; installed via `copilot plugin install`. Only 6 official component fields: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers` — the `instructions` field does NOT exist in plugin.json.

### Runtime variants (VS Code vs CLI)

- Agent files have runtime-specific variants: `agents/<name>/vscode/*.agent.md` and `agents/<name>/cli/*.agent.md`.
- VS Code agents use `@SubAgentName` mention syntax; CLI agents use `task("AgentName-CLI", "...")`.
- CLI agents embed instructions at build time via `<!-- EMBED: filename.instructions.md -->` markers (resolved by `build-plugins.ps1`; legacy `publish-plugins.ps1` also resolved them).
- CLI agent markdown body limit: **30,000 characters** (YAML frontmatter excluded). Monitor large instruction files.
- `.plugin-managed` marker in a directory prevents `publish-agents.ps1` and `publish-skills.ps1` from syncing that artifact (plugin system owns it).
- CLI frontmatter uses `disable-model-invocation: true` (not the retired `infer: false`).

## File and naming conventions

- Custom Agents: `agents/<name>.agent.md` (standalone) or `agents/<name>/<runtime>/<name>-<runtime>.agent.md` (variants)
- Agent Hooks: `hooks/<name>/<name>.json`
- Custom Instructions: `instructions/<name>.instructions.md`
- Agent-specific private instructions: `agents/<name>/instructions/*.instructions.md` (tightly coupled to that agent workflow)
- Tools inventory root: `tools/`
- VS Code Toolsets: `tools/vscode/toolsets/*.toolsets.jsonc`
- Plugins: `plugins/<runtime>/<name>/plugin.json` (runtime = `cli` or `vscode`)
- Skills: `skills/<name>/SKILL.md` with optional `scripts/`, `references/`, `assets/`
- Skill evals: `evals/<name>/eval.yaml` with `tasks/` and `trigger_tests.yaml` (→ see `instructions/waza-eval.instructions.md`)
- Skill telemetry: `telemetry/<name>/` (real-session efficiency audit artifacts; legacy name `benchmarks/`)
- Use forward slashes in markdown links, even on Windows paths.
- Kebab-case for directory and file names.

## Skill evaluation and telemetry

- **waza is the default skill-evaluation tool** — drive it through the `skills/waza-cli` skill. Start with the zero-cost, offline commands (`waza check`, `waza tokens check`, `waza coverage`); escalate to `waza quality`, `waza run`, or `waza gate` only when real model execution is needed (BYOK profile gate applies).
- **CI gating is intentionally deferred (2026-10-16).** Do not wire `waza gate`/`waza run` into workflows yet; extend eval coverage on demand under `evals/<name>/` (see `instructions/waza-eval.instructions.md`).
- **Real-session efficiency telemetry is a separate concern** — the `skills/copilot-session-telemetry` skill (formerly `agentic-workflow-benchmark`) audits what a finished run actually burned (tokens/time/scripted-vs-ad-hoc steps) and writes a dated report. It is not an evaluation tool; its findings hand off to waza for eval refinement and regression gating.
- **Vocabulary:** "benchmark" = waza's authored evals; "telemetry" = the telemetry skill's artifacts (`telemetry/` folders).

## Critical workflows

### Publishing

- Publish scripts are source of truth for distribution: `scripts/publish/publish-*.ps1` and router `scripts/publish/publish-artifact.ps1`.
- Artifact flow: workspace source → specialized publish helper → personal folder (`~/.copilot/`, `%APPDATA%/Code*/`) → optional WSL mirror (via `scripts/publish/wsl-helpers.ps1`).
- **NEVER publish skills to WSL by default (2026-08).** `publish-skills.ps1` publishes to Windows personal folders only; WSL mirroring is opt-in via the explicit `-IncludeWSL` switch. Do not pass `-IncludeWSL` for routine skill publishing — the Windows personal folders (`~/.agents/skills`, `~/.copilot/skills`) are the canonical targets. The deprecated `-SkipWSL` flag is a no-op retained for backward compatibility only.
- Plugin publishing builds runtime-scoped bundles under `plugins/<runtime>/.build/<name>/`, embeds instructions via marker resolution, validates 30K body limit, then publishes by runtime: CLI bundles are installed from the resulting local bundle with `copilot plugin install <local_plugin_path>` (treat `_direct/...` only as an observed cache location), while VS Code bundles are registered in `chat.plugins.paths`. `publish-plugins.ps1` is deprecated — prefer `copilot plugins <options>` (and `build-plugins.ps1` for bundle-only).
- Hooks are authored in `hooks/` and published to `.github/hooks/` via `scripts/publish/publish-hooks.ps1`.

### Local CI

- Run `pwsh -NoProfile -File scripts/workspace/run-command.ps1 workspace:check` in-session after changing skills, instructions, scripts, or wiki pages — it aggregates TOC freshness, `waza check`, skill pytest, and markdown lint. The pre-push hook runs the same script before every push (activate once per clone: `git config core.hooksPath scripts/hooks`).

### Wiki lookup

- Start at `.docs/index.md` before reading individual wiki pages.
- Choose the Diátaxis category by intent: `tutorials` to learn, `how-to` to accomplish, `reference` to look up, `explanation` to understand.
- Narrow into a domain folder when present (`copilot`, `ralph`, `blazor-agui`, `codex`).
- Prefer targeted reads of likely files over broad directory scans.
- Treat `.archived/` as non-authoritative unless explicitly asked to inspect deprecated material.

### Other workflows

- Treat scripts as primary workflow entry points; VS Code tasks are optional wrappers over the same scripts.
- Workspace command dispatcher is `scripts/workspace/run-command.ps1`, with built-in command mapping (no external manifest required). Key commands: `agents:publish`, `skills:publish`, `hooks:publish`, `instructions:publish`, `toolsets:publish`, `issues:reindex`, `workspace:check`. The dispatcher forwards `-CopilotHome <dir>` to `agents:publish`, `hooks:publish`, and `instructions:publish` for staging (dojo) publishing.
- Issue indexing: `scripts/issues/extract-issue-metadata.ps1` reads `{.docs,_docs}/issues/*.md`, supports YAML frontmatter and legacy metadata formats, writes `index.md`.
- Changelog generation: `scripts/changelog/create-weekly-changelog.ps1` — auto-generates from git history, supports raw/conventional formats.

## Terminal-first execution (editor agnostic)

- List workspace commands (any shell): `pwsh -NoProfile -File scripts/workspace/run-command.ps1 list`
- Publish one artifact: `pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name diataxis`
- Stage artifacts into a test Copilot home (dojo): `pwsh -NoProfile -File scripts/workspace/run-command.ps1 -Command agents:publish -CopilotHome C:\temp\copilot-staging` (also `hooks:publish`, `instructions:publish`; or call the publish scripts directly with `-CopilotHome <dir>`)
- Publish all skills: `npx skills <options>` (preferred; `publish-skills.ps1` is deprecated — workspace-to-personal copy only, legacy)
- Publish plugin: `copilot plugins <options>` (preferred; `publish-plugins.ps1` is deprecated — bundle/install flow only, legacy; use `build-plugins.ps1` if you only need the local bundle)
- If using VS Code tasks, keep behavior consistent with the commands above; do not add task-only logic.

## Tooling and execution norms

- Use PowerShell for workspace/publishing automation; use Python for logic/testing utilities.
- Run Python as `python3` (not `python`).
- For `scripts/**/*.ps1`, keep function-based PowerShell style with approved verbs and robust error handling (see `instructions/powershell.instructions.md`).
- Keep automation callable from both Windows and Linux/WSL terminals; avoid assumptions tied to VS Code APIs.
- Research long web docs in one shot: download once to a temp file (`curl`/`Invoke-WebRequest`) and grep locally — `web_fetch` truncates around 20 KB, so paged re-fetches multiply calls. Prefer narrow globs; the glob tool ignores `.gitignore`, so broad patterns return `node_modules`/artifact noise.

## Common pitfalls

- **Legacy Windows PowerShell vs pwsh**: Never use the `powershell` command (Windows PowerShell 5.1) to run workspace scripts. The scripts rely on modern PowerShell 7+ features (like `&&` and `||` pipeline chain operators). Always invoke scripts using `pwsh`.
- **Regex backreference corruption**: PowerShell's `-replace` operator interprets `$0`, `$&`, `$+` as regex tokens. Use `[Regex]::Replace($input, $pattern, { param($m) $literal })` with a script block evaluator for dynamic replacements.
- **VS Code prompts directory collision**: instructions and toolsets both publish to `%APPDATA%/Code*/User/prompts` — naming must avoid conflicts.
- **CLI instructions not concatenated**: `publish-instructions.ps1` intentionally excludes CLI instruction concatenation due to context overload risk.
- **Wildcard quoting**: Callers must quote glob patterns at CLI (`publish-agents.ps1 -Agents "*ralph*"`) to prevent PowerShell expansion.
- **Plugin re-install required**: `copilot plugin install` caches files — local changes require re-install.

## High-value examples

- Single-agent (Standalone agent) template: `agents/planner.agent.md`.
- Multi-agent orchestration pattern: `agents/ralph-v2/README.md` (6 agents, state machine, session structure).
- Runtime variant agents: `agents/ralph-v2/vscode/` and `agents/ralph-v2/cli/`.
- Instruction authoring reference: `create-instructions.prompt.md` in the VS Code extension assets — glob `%USERPROFILE%\.vscode-insiders\extensions\github.copilot-chat-*\assets\prompts\` for the newest version (the path embeds the extension version and changes with every update).
- Skill authoring reference: `create-skill.prompt.md` in the same extension assets folder (version-agnostic lookup as above).
- Cross-runtime skill publishing: `npx skills <options>` (preferred; legacy: `scripts/publish/publish-skills.ps1`).
- Plugin bundling with instruction embedding: `scripts/publish/publish-plugins.ps1` (legacy, deprecated — prefer `copilot plugins <options>`; `build-plugins.ps1` for bundle-only).
