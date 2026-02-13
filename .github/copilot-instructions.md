# GitHub Copilot Instructions for Copilot FC Workspace

Use this file for in-repo authoring of Copilot artifacts (not external publishing docs).

## Big picture
- This repo is a customization factory: `agents/`, `instructions/`, `prompts/`, `skills/`, `toolsets/`, plus publish/automation scripts in `scripts/`.
- Authoring is workspace-first by design (see `README.md` and `skills/README.md`): artifacts are created here, then copied to personal folders via publish scripts.
- `archived/` content is deprecated/superseded; do not use archived files as references/templates for new work.

## Architecture and boundaries
- Follow the Agent -> Instruction -> Skill split used across the repo (example: `agents/meta-v2.agent.md`, `instructions/meta.instructions.md`, `skills/*/SKILL.md`).
- Custom Agent files (`*.agent.md`) define persona/orchestration and tool access; keep required frontmatter (`name`, `description`, `tools`).
- Custom Instruction files (`*.instructions.md`) define policy/workflows and should use `description` + `applyTo` frontmatter.
- Agent Skills are folder-based and must include `SKILL.md`; scripts local to a skill belong under that skill’s own `scripts/` folder.

## File and naming conventions
- Custom Agents: `agents/<name>.agent.md`
- Custom Instructions: `instructions/<name>.instructions.md`
- Custom Prompts: `prompts/*.prompt.md`
- Custom Toolsets: `toolsets/*.toolsets.jsonc`
- Use forward slashes in markdown links, even on Windows paths.

## Critical workflows
- Treat scripts as primary workflow entry points; VS Code tasks are optional wrappers over the same scripts.
- Publish scripts are source of truth for distribution: `scripts/publish/publish-*.ps1` and router `scripts/publish/publish-artifact.ps1`.
- Workspace command dispatcher is `scripts/workspace/run-command.ps1`, with built-in command mapping (no external manifest required).
- Issue indexing flow is `scripts/issues/extract-issue-metadata.ps1` (supports YAML frontmatter and legacy metadata).

## Terminal-first execution (editor agnostic)
- Windows PowerShell: `pwsh -NoProfile -File scripts/workspace/run-command.ps1 list`
- Bash/WSL: `pwsh -NoProfile -File scripts/workspace/run-command.ps1 list`
- Publish one artifact: `pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type skill -Name diataxis`
- Publish all skills: `pwsh -NoProfile -File scripts/publish/publish-skills.ps1`
- Reindex issues: `pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1`
- If using VS Code tasks, keep behavior consistent with the command above; do not add task-only logic.

## Tooling and execution norms
- Use PowerShell for workspace/publishing automation; use Python for logic/testing utilities.
- Run Python as `python3` (not `python`).
- For `scripts/**/*.ps1`, keep function-based PowerShell style with approved verbs and robust error handling (see `instructions/powershell.instructions.md`).
- Keep automation callable from both Windows and Linux/WSL terminals; avoid assumptions tied to VS Code APIs.

## High-value examples
- Current agent template reference: `agents/meta-v2.agent.md`.
- Planning/orchestration patterns: `agents/planner.agent.md` and `agents/ralph-v2/README.md`.
- Instruction authoring reference: `instructions/meta.instructions.md`.
- Cross-platform skill publishing behavior (Windows + optional WSL): `scripts/publish/publish-skills.ps1`.
