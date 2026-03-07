---
name: copilot-plugin-creator
description: 'Create GitHub Copilot agent plugins for CLI, VS Code, or both. Use when scaffolding plugin.json, choosing runtime-specific component fields, wiring plugin components, handling CLI vs VS Code plugin differences, or preparing plugin bundles for local development and sharing.'
argument-hint: 'Plugin name, runtime (cli|vscode|both), components, and scaffold style'
metadata:
  version: 1.1.0
  author: arisng
---

# Copilot Plugin Creator

Use this skill when the user wants to create or scaffold a GitHub Copilot agent plugin.

## Outcomes

- Create a new plugin for CLI, VS Code, or both
- Reuse existing artifacts through correct relative paths when appropriate
- Proactively discover and select likely plugin components when users do not specify them
- Avoid mixing CLI-only assumptions into VS Code plugins
- Generate a minimal, pragmatic `README.md` for the plugin
- Leave the user with the smallest viable plugin scaffold for the requested runtime

## Required Inputs

Extract these from the user request. Ask only for missing items that block a correct scaffold.

- Plugin name in kebab-case
- Runtime target: `cli`, `vscode`, or `both`
- Short purpose/description
- Which artifacts to bundle: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers`
- Whether to reference existing artifacts or create plugin-local placeholders
- Intended use: local development, team sharing, or distributable bundle

## Reference Sources

This skill is self-contained. Use official runtime documentation only when you need to confirm current platform behavior, schema details, or installation mechanics.

- Copilot CLI plugin reference: https://docs.github.com/en/copilot/reference/cli-plugin-reference
- Copilot CLI plugin how-to: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating
- VS Code agent plugins: https://code.visualstudio.com/docs/copilot/customization/agent-plugins

## Workflow

1. Determine whether this is a CLI plugin, VS Code plugin, or both.
2. Run deep analysis on user intent and repository context to infer likely plugin components when explicit component lists are missing.
3. Build a candidate component map (`agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers`) and select only components supported by available artifacts.
4. Decide whether the plugin should reference existing artifacts or include plugin-local starter files.
5. Create the runtime-specific directory using the repository's established layout. If no layout exists yet, default to `plugins/cli/<name>/` and `plugins/vscode/<name>/`.
6. Write `plugin.json` with only the fields that belong to that runtime and request.
7. If reusing existing artifacts, calculate relative paths from the plugin directory to the real component locations.
8. If starter files are requested, create only the minimum folders/files needed for the declared component paths.
9. Create `README.md` in the plugin directory.
10. Summarize what was created, what components were inferred, any assumptions made, and the next validation step.

## Component Discovery Protocol

Use this protocol whenever component lists are incomplete or omitted:

1. Parse user intent for verbs and nouns that imply capability types (for example: orchestrate -> agents, automation -> hooks/commands, external integration -> mcpServers).
2. Inspect repository/customization context for existing artifacts that match the intent.
3. Produce a short inferred component plan with confidence labels (`high`, `medium`, `low`).
4. Auto-select `high` confidence components and proceed.
5. Ask concise follow-up questions only for `medium` or `low` confidence decisions that materially change plugin shape.

## CLI Plugin Rules

- Prefer `plugins/cli/<name>/plugin.json` unless the repository already uses a different plugin layout.
- Only use official CLI component fields: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers`.
- Do not add an `instructions` field to `plugin.json`.
- Prefer relative paths to existing artifacts for repository-internal plugins.
- If the plugin is meant to be packaged, keep the plugin self-contained or compatible with the repository's packaging flow.

## VS Code Plugin Rules

- Prefer `plugins/vscode/<name>/plugin.json` unless the repository already uses a different plugin layout.
- Validate plugin behavior against the current VS Code agent plugin documentation before assuming the CLI schema or install flow applies.
- Treat VS Code agent plugins as preview unless the official docs state otherwise.
- When useful in the final response, mention `chat.plugins.enabled`, `chat.plugins.paths`, and `chat.plugins.marketplaces` for local usage and discovery.

## Decision Points

### Existing artifacts vs placeholders

- Prefer existing artifacts when the user describes a plugin that bundles work already present in the repository.
- Create placeholders only when the user explicitly asks for a starter scaffold or the plugin would otherwise point to non-existent components.

### Single runtime vs both

- If the user requests both runtimes, create separate plugin directories for CLI and VS Code.
- Do not assume the two manifests can be identical.

## Completion Checks

- The plugin directory exists in the correct runtime folder.
- `plugin.json` contains a valid name and description.
- Component paths are relative to the plugin directory.
- No CLI-only field is copied into a VS Code manifest without runtime confirmation.
- Any created starter files match the manifest paths.
- A plugin `README.md` exists and is minimal/pragmatic.
- Any paths in `README.md` are relative to the published plugin root (for example `./agents/...`, `./skills/...`), never workspace-absolute.

## README Rules

When creating `README.md`, keep it short and practical:

- Purpose: 1-2 sentences
- Included components: bullet list with plugin-relative paths
- Usage: minimal install/enable commands relevant to runtime
- Validation: one quick check command or action

Avoid long design explanations, architecture history, or workspace-only path examples.

## Non-Goals

- Do not implement business logic for bundled artifacts unless explicitly requested.
- Do not invent marketplace metadata, publish pipelines, or custom schema fields not requested by the user.
- Do not copy large documentation blocks into `plugin.json` comments or extra markdown files.

## Response Pattern

When you finish:

- State which runtime target was created
- State whether the plugin reuses existing artifacts or includes placeholders
- State which components were inferred automatically vs explicitly provided by the user
- Note any runtime-specific differences you had to account for
- Give the next concrete validation command or VS Code setting to use