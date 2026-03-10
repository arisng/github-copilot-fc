---
category: reference
---

# OpenSpec Custom Profile Command Routing

## Core vs Custom Profile

OpenSpec supports two profiles:
- **Core profile** (default): 4 commands — `/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive`
- **Custom profile**: adds 7 commands — `/opsx:new`, `/opsx:continue`, `/opsx:ff`, `/opsx:verify`, `/opsx:sync`, `/opsx:bulk-archive`, `/opsx:onboard`

## Skill/Prompt Generation Pattern

When the custom profile is enabled via `openspec config profile` → `openspec update`, each custom command generates:
- Skill file: `.github/skills/openspec-<command>/SKILL.md`
- Prompt file: `.github/prompts/opsx-<command>.prompt.md`

The same skill-first routing pattern applies: check for the generated skill file first, fall back to CLI execution if the skill is unavailable.

## Routing Notes

- Core commands always have hand-authored skill files in `.github/skills/openspec-*/`
- Custom commands have **generated** skill files — they exist only when the custom profile is active
- An AI agent encountering a custom profile command in a workspace with only core profile active will not find a matching skill file; it should fall back to CLI or inform the user the custom profile is not enabled
- The instruction file (`instructions/openspec-protocol.instructions.md`) handles `/opsx:*` generically in routing rules 5-6, covering both core and custom commands

## Current Workspace State

This workspace uses the **core profile** (4 commands). Custom profile skill/prompt files do not exist in `.github/skills/` or `.github/prompts/` beyond the 4 core entries.
