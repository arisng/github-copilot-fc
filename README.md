# Copilot FC

Copilot FC is a workspace-first factory for authoring and publishing Copilot customization artifacts.

Use this repository to create, validate, and distribute:

- Plugins (`plugins/<plugin-name>/`)
- Custom Agents (`agents/*.agent.md`)
- Agent Hooks (`hooks/<name>/<name>.json`)
- Custom Instructions (`instructions/*.instructions.md`)
- Skills (`skills/<skill-name>/SKILL.md`)
- Tools inventory (`tools/`)

The repository is operationally script-driven: VS Code tasks are convenience wrappers around `scripts/`.

## Core Principles

- Workspace-first authoring: build artifacts in this repo, then publish to personal locations.
- Script-first operations: `scripts/` is the source of truth for automation behavior.
- Clear boundaries: treat `.archived/` content as deprecated and not a template source.
- Cross-shell usage: commands are designed to run from Windows PowerShell and Linux/WSL (`pwsh`).

## Repository Layout

- `plugins/`: plugin definitions and assets for local development; publish to personal plugin folders.
- `agents/`: active agent definitions plus `agents/ralph-v2/` system docs.
- `hooks/`: agent hook configurations organized as per-hook directories with manifests and companion scripts; publish manifests to `.github/hooks/`.
- `instructions/`: reusable instruction files; `instructions/.archived/` for superseded items.
- `prompt-engineering/`: system message data models, reverse-engineering notes, and samples.
- `skills/`: skill factory source; publish from here to personal skill folders.
- `tools/`: cross-runtime tools inventory, tool docs, and VS Code toolsets under `tools/vscode/toolsets/`.
- `copilot-sdk/`: architecture and planning documents for Copilot SDK and Ralph v2 implementation.
- `scripts/`: automation entry points:
  - `scripts/publish/`: publish agents, hooks, instructions, skills, toolsets.
  - `scripts/issues/`: issue metadata extraction and indexing.
  - `scripts/workspace/`: workspace command router.
  - `scripts/changelog/`: weekly changelog generation.
- `.docs/`: workspace documentation index and Diataxis-style content.
- `.issues/`: issue documents used as planning/change inputs.
- `.ralph-sessions/`: Ralph session artifacts and iteration state.
  - Session folders use `<YYMMDD>-<hhmmss>` format.
  - Session-level instruction files may exist as `.ralph-sessions/<session-id>.instructions.md`.

Archived locations that should not be used as authoring templates:

- `agents/.archived/`
- `instructions/.archived/`
- `skills/playwright-cli-archived/`
- `.archived/prompts/` (retired — GitHub Copilot deprecated prompt files)

## Quickstart

1. Edit or add artifacts in `plugins/`, `agents/`, `hooks/`, `instructions/`, `skills/`, or `tools/`.
2. Validate changes locally: `pwsh -NoProfile -File scripts/workspace/run-command.ps1 workspace:check`.
3. Publish with scripts under `scripts/publish/`.

## Terminal-First Commands

Run from repository root:

```powershell
# Show available workspace commands
pwsh -NoProfile -File scripts/workspace/run-command.ps1 list

# Execute a named workspace command
pwsh -NoProfile -File scripts/workspace/run-command.ps1 skills:publish

# Reindex issue metadata (.issues)
pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1

# Publish one artifact via router
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name diataxis

# Publish all skills (preferred: Skills CLI)
npx skills <options>
# Publish all skills (legacy workspace copy)
pwsh -NoProfile -File scripts/publish/publish-skills.ps1
```

Current command map is implemented directly in `scripts/workspace/run-command.ps1` and includes:

- `agents:publish`
- `hooks:publish`
- `instructions:publish`
- `skills:publish`
- `toolsets:publish`
- `issues:reindex`
- `tests:skills-pytest`
- `workspace:check`
- `workspace:list-skills`
- `workspace:status`

## Local CI (quality enforcement)

Quality gates run locally from repo scripts — this repo intentionally uses no cloud CI workflows:

```powershell
# Run all checks: TOC freshness, waza (advisory), skill pytest, markdown lint
pwsh -NoProfile -File scripts/workspace/workspace-check.ps1
# or via the dispatcher:
pwsh -NoProfile -File scripts/workspace/run-command.ps1 workspace:check
```

Activate the versioned git hooks once per clone:

```powershell
git config core.hooksPath scripts/hooks
```

- `scripts/hooks/pre-push` runs `workspace-check` before every push; gate failures block the push.
- `scripts/hooks/post-commit` publishes any skill changed by the commit to personal folders.

## Publishing Model

Publish scripts are the canonical distribution path (skills/plugins have preferred CLI alternatives):

- `scripts/publish/publish-agents.ps1` (supports `-CopilotHome` staging override)
- `scripts/publish/publish-hooks.ps1` (supports `-CopilotHome` staging override)
- `scripts/publish/publish-instructions.ps1` (supports `-CopilotHome` staging override)
- `scripts/publish/publish-toolsets.ps1`
- `scripts/publish/publish-artifact.ps1` (type-based router)
- ~~`scripts/publish/publish-skills.ps1`~~ **deprecated** — prefer `npx skills <options>` (Skills CLI)
- ~~`scripts/publish/publish-plugins.ps1`~~ **deprecated** — prefer `copilot plugins <options>` (native CLI; `build-plugins.ps1` for bundle-only)

Publish destination behavior:

- Agents, instructions, and VS Code toolsets are copied to VS Code user prompts paths:
  - `%APPDATA%/Code/User/prompts`
  - `%APPDATA%/Code - Insiders/User/prompts`
- Hooks are copied to workspace `.github/hooks/` for VS Code agent hook discovery.
- Skills are copied to personal skill folders:
  - `%USERPROFILE%/.claude/skills`
  - `%USERPROFILE%/.codex/skills`
  - `%USERPROFILE%/.copilot/skills`
  - WSL equivalents are **NOT** published by default (2026-08): WSL mirroring is opt-in via the `-IncludeWSL` switch and is discouraged for regular use.

Wildcard patterns are supported by helpers for name selection. Quote patterns to avoid shell expansion.

```powershell
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

## Artifact Scope

- Agents, hooks, instructions, toolsets: Copilot-focused artifacts.
- Skills: cross-platform reusable assets (Copilot, Codex, Claude workflows).

## VS Code Tasks

Workspace tasks are wrappers for script entry points. The same behavior should remain available via terminal commands:

- `Workspace Commands`
- `Publish Skills`
- `Publish Artifact`
- `Reindex Issues`

## Naming and Authoring Conventions

- Agent file naming: `agents/<name>.agent.md`
- Hook file naming: `hooks/<name>/<name>.json`
- Instruction naming: `instructions/<name>.instructions.md`
- Skill folder requirement: `skills/<name>/SKILL.md`
- Tools inventory root: `tools/`
- VS Code toolset naming: `tools/vscode/toolsets/<name>.toolsets.jsonc`
- Use forward slashes in markdown links.

## Related References

- Workspace authoring rules: `.github/copilot-instructions.md`
- Git scope governance: `.github/git-scope-constitution.md`, `.github/git-scope-inventory.md`
- Skills-specific guidance: `skills/README.md`
- Tools inventory: `tools/inventory.yaml`
- Ralph v2 system docs: `agents/ralph-v2/README.md`

## Troubleshooting

- PowerShell execution policy blocks scripts:
  - Run PowerShell with proper policy or trusted shell context.
- Publish output not reflected:
  - Re-run publish script and verify personal target folders.
- Issue index not generated:
  - Ensure `.issues` exists and contains markdown issue files.
- Python tooling scripts fail:
  - Most Python utilities are skill-local under `skills/<skill-name>/scripts/`.
  - Install Python 3 and invoke those utilities as `python3`.
