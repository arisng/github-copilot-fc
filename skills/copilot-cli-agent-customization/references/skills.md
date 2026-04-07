# [Agent Skills (SKILL.md)](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)

Portable folders of instructions, scripts, and resources that Copilot CLI can load on demand.

## Structure

```text
.github/skills/<skill-name>/
├── SKILL.md
├── scripts/
├── references/
└── assets/
```

## Locations

| Path | Scope |
|------|-------|
| `.github/skills/<name>/` | Repository |
| `~/.copilot/skills/<name>/` | Personal |

Within this workspace, source skills are authored under `skills/<name>/` and published to personal Copilot skill directories with the publish scripts.

## `SKILL.md` Format

```yaml
---
name: skill-name
description: "What the skill does and when to use it."
user-invocable: true
disable-model-invocation: false
---
```

## Body

Include:

- What the skill accomplishes
- Trigger phrases and when to use it
- A step-by-step procedure
- Links to references, scripts, or assets using relative paths

## Progressive Loading

1. `name` and `description` drive discovery
2. The `SKILL.md` body loads when the skill is relevant
3. `references/`, `scripts/`, and `assets/` load only when referenced

Keep `SKILL.md` concise and move detailed content into `references/`.

## CLI Management Surfaces

Inside Copilot CLI, skill management is exposed through commands such as:

- `/skills list`
- `/skills info`
- `/skills add`
- `/skills reload`
- `/skills remove`

Outside the interactive session, this workspace publishes skills with `scripts\publish\publish-skills.ps1`.

## When to Use

- Repeatable CLI workflows
- Multi-step tasks with supporting references or scripts
- Reusable operational knowledge that does not belong in always-on instructions

## Core Principles

1. **Write keyword-rich descriptions**
2. **Prefer one workflow per skill**
3. **Use relative links to resources**
4. **Keep runtime-neutral parts shareable, but keep runtime-specific guidance in runtime-specific skills**

## Anti-patterns

- **Vague descriptions**: The skill will not be discovered reliably
- **Monolithic `SKILL.md`**: Move detail into `references/`
- **Folder and `name` mismatch**: Keep them aligned
- **Using a skill for always-on policy**: That belongs in instructions
