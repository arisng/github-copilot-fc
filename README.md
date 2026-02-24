# Copilot FC

Copilot FC is a workspace-first factory for authoring and publishing Copilot customization artifacts.

Use this repository to create, validate, and distribute:

- Custom Agents (`agents/*.agent.md`)
- Agent Hooks (`hooks/*.hooks.json`)
- Custom Instructions (`instructions/*.instructions.md`)
- Prompt files (`prompts/*.prompt.md`)
- Skills (`skills/<skill-name>/SKILL.md`)
- Toolsets (`toolsets/*.toolsets.jsonc`)

The repository is operationally script-driven: VS Code tasks are convenience wrappers around `scripts/`.

## Core Principles

- Workspace-first authoring: build artifacts in this repo, then publish to personal locations.
- Script-first operations: `scripts/` is the source of truth for automation behavior.
- Clear boundaries: treat `archived/` content as deprecated and not a template source.
- Cross-shell usage: commands are designed to run from Windows PowerShell and Linux/WSL (`pwsh`).

## Repository Layout

- `agents/`: active agent definitions plus `agents/ralph-v2/` system docs.
- `hooks/`: agent hook configurations (lifecycle hooks); publish to `.github/hooks/`.
- `instructions/`: reusable instruction files; `instructions/archived/` for superseded items.
- `prompts/`: reusable prompt files for workflow automation.
- `prompt-engineering/`: system message data models, reverse-engineering notes, and samples.
- `skills/`: skill factory source; publish from here to personal skill folders.
- `toolsets/`: chat toolset definitions and index.
- `copilot-sdk/`: architecture and planning documents for Copilot SDK and Ralph v2 implementation.
- `scripts/`: automation entry points:
	- `scripts/publish/`: publish agents, hooks, instructions, prompts, skills, toolsets.
	- `scripts/issues/`: issue metadata extraction and indexing.
	- `scripts/workspace/`: workspace command router.
	- `scripts/changelog/`: weekly changelog generation.
- `.docs/`: workspace documentation index and Diataxis-style content.
- `.issues/`: issue documents used as planning/change inputs.
- `.ralph-sessions/`: Ralph session artifacts and iteration state.
	- Session folders use `<YYMMDD>-<hhmmss>` format.
	- Session-level instruction files may exist as `.ralph-sessions/<session-id>.instructions.md`.

Archived locations that should not be used as authoring templates:

- `agents/archived/`
- `instructions/archived/`
- `skills/playwright-cli-archived/`

## Quickstart

1. Edit or add artifacts in `agents/`, `hooks/`, `instructions/`, `prompts/`, `skills/`, or `toolsets/`.
2. Validate changes locally in the workspace.
3. Publish with scripts under `scripts/publish/`.

## Terminal-First Commands

Run from repository root:

```powershell
# Show available workspace commands
pwsh -NoProfile -File scripts/workspace/run-command.ps1 list

# Execute a named workspace command
pwsh -NoProfile -File scripts/workspace/run-command.ps1 skills:publish

# Reindex issue metadata (.docs/issues or _docs/issues)
pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1

# Publish one artifact via router
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name diataxis

# Publish all skills
pwsh -NoProfile -File scripts/publish/publish-skills.ps1
```

Current command map is implemented directly in `scripts/workspace/run-command.ps1` and includes:

- `agents:publish`
- `hooks:publish`
- `instructions:publish`
- `prompts:publish`
- `skills:publish`
- `toolsets:publish`
- `issues:reindex`
- `workspace:list-skills`
- `workspace:status`

## Publishing Model

Publish scripts are the canonical distribution path:

- `scripts/publish/publish-agents.ps1`
- `scripts/publish/publish-hooks.ps1`
- `scripts/publish/publish-instructions.ps1`
- `scripts/publish/publish-prompts.ps1`
- `scripts/publish/publish-skills.ps1`
- `scripts/publish/publish-toolsets.ps1`
- `scripts/publish/publish-artifact.ps1` (type-based router)

Publish destination behavior:

- Agents, instructions, prompts, and toolsets are copied to VS Code user prompts paths:
	- `%APPDATA%/Code/User/prompts`
	- `%APPDATA%/Code - Insiders/User/prompts`
- Hooks are copied to workspace `.github/hooks/` for VS Code agent hook discovery.
- Skills are copied to personal skill folders:
	- `%USERPROFILE%/.claude/skills`
	- `%USERPROFILE%/.codex/skills`
	- `%USERPROFILE%/.copilot/skills`
	- Optional WSL equivalents (unless `-SkipWSL`)

Wildcard patterns are supported by helpers for name selection. Quote patterns to avoid shell expansion.

```powershell
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type prompt -Name "git*"
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name "playwright*" -Force
```

## Documentation Structure

Documentation root: `.docs/index.md`.

Primary documentation sections in `.docs/`:

- `tutorials/`
- `how-to/`
- `reference/`
- `explanation/`
- `research/`

## Prompt Locations

- `prompts/`: primary authoring location for prompt files.
- `.github/prompts/`: additional prompt assets used by repository workflows.
- When the same prompt exists in both places, treat `prompts/` as source for publish scripts.

## Artifact Scope

- Agents, hooks, instructions, prompts, toolsets: Copilot-focused artifacts.
- Skills: cross-platform reusable assets (Copilot, Codex, Claude workflows).

## VS Code Tasks

Workspace tasks are wrappers for script entry points. The same behavior should remain available via terminal commands:

- `Workspace Commands`
- `Publish Skills`
- `Publish Artifact`
- `Reindex Issues`

## Naming and Authoring Conventions

- Agent file naming: `agents/<name>.agent.md`
- Hook file naming: `hooks/<name>.hooks.json`
- Instruction naming: `instructions/<name>.instructions.md`
- Prompt naming: `prompts/<name>.prompt.md`
- Skill folder requirement: `skills/<name>/SKILL.md`
- Toolset naming: `toolsets/<name>.toolsets.jsonc`
- Use forward slashes in markdown links.

## Related References

- Workspace authoring rules: `.github/copilot-instructions.md`
- Git scope governance: `.github/git-scope-constitution.md`, `.github/git-scope-inventory.md`
- Skills-specific guidance: `skills/README.md`
- Toolset registry: `toolsets/index.md`
- Ralph v2 system docs: `agents/ralph-v2/README.md`

## Troubleshooting

- PowerShell execution policy blocks scripts:
	- Run PowerShell with proper policy or trusted shell context.
- Publish output not reflected:
	- Re-run publish script and verify personal target folders.
- Issue index not generated:
	- Ensure `.docs/issues` or `_docs/issues` exists and contains markdown issue files.
- Python tooling scripts fail:
	- Most Python utilities are skill-local under `skills/<skill-name>/scripts/`.
	- Install Python 3 and invoke those utilities as `python3`.
