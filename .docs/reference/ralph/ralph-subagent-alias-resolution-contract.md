---
category: reference
---

# Ralph-v2 subagent alias resolution contract

Reference for the stable alias layer used by the Ralph-v2 Orchestrator when it delegates work across runtime-specific and channel-specific subagent names.

## Purpose

This contract keeps orchestration stable even when the runtime surface changes:

- VS Code uses `agents:` frontmatter and `@AgentName` mentions.
- Copilot CLI delegates with `task("<runtime-visible name>", "...")`.
- Beta bundles rewrite runtime-visible agent names with `-beta`.

The Orchestrator therefore routes through stable lowercase aliases and resolves the alias to the correct runtime-visible name before delegation.

## Canonical aliases

| Alias | VS Code stable | VS Code beta | CLI stable | CLI beta |
| --- | --- | --- | --- | --- |
| `planner` | `Ralph-v2-Planner-VSCode` | `Ralph-v2-Planner-VSCode-beta` | `Ralph-v2-Planner-CLI` | `Ralph-v2-Planner-CLI-beta` |
| `questioner` | `Ralph-v2-Questioner-VSCode` | `Ralph-v2-Questioner-VSCode-beta` | `Ralph-v2-Questioner-CLI` | `Ralph-v2-Questioner-CLI-beta` |
| `executor` | `Ralph-v2-Executor-VSCode` | `Ralph-v2-Executor-VSCode-beta` | `Ralph-v2-Executor-CLI` | `Ralph-v2-Executor-CLI-beta` |
| `reviewer` | `Ralph-v2-Reviewer-VSCode` | `Ralph-v2-Reviewer-VSCode-beta` | `Ralph-v2-Reviewer-CLI` | `Ralph-v2-Reviewer-CLI-beta` |
| `librarian` | `Ralph-v2-Librarian-VSCode` | `Ralph-v2-Librarian-VSCode-beta` | `Ralph-v2-Librarian-CLI` | `Ralph-v2-Librarian-CLI-beta` |

## Resolution rules

1. Determine the runtime from the active wrapper surface.
2. Determine the channel from the active plugin or bundle identity, or from the visible bundled agent names.
3. Resolve the stable alias through the runtime/channel table before every delegation.
4. Treat the alias as unavailable when the resolved runtime-visible name is not exposed by the active wrapper or bundle inventory.

## Output-contract rule

Ralph subagents must return only canonical lowercase aliases in fields such as `next_agent`.

Examples:

- Valid: `planner`
- Valid: `reviewer`
- Invalid: `Ralph-v2-Reviewer-CLI`
- Invalid: `Ralph-v2-Planner-VSCode-beta`

The Orchestrator owns the final alias-to-runtime-visible-name translation.

## Why aliases exist

- They decouple workflow logic from bundle-specific naming.
- They prevent beta suffix rewrites from breaking orchestration.
- They let shared source instructions stay runtime-agnostic.

## What this contract does not do

- It does not let subagents infer runtime-visible names on their own.
- It does not replace the bundle-time beta rewrite rules for bundled agent `name:` values and VS Code `agents:` references.
- It does not change the Orchestrator router boundary; the Orchestrator still routes from declared contracts and persisted state, not from ad hoc workspace inspection.

## Related documents

- [Ralph Beta Agent Frontmatter Name Contract](ralph-beta-agent-frontmatter-name-contract.md)
- [Orchestrator Router Contract Boundary](orchestrator-router-contract-boundary.md)
- [Ralph-v2 agent frontmatter version contract](ralph-agent-frontmatter-version-contract.md)

