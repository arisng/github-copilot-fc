# [Workspace Instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/add-custom-instructions)

Guidelines that automatically apply to Copilot CLI sessions from repository files, compatibility files, or your home-level CLI config.

## File Types and Loading Model

| File | Location | Purpose |
|------|----------|---------|
| `copilot-instructions.md` | `.github/` | Repository-wide defaults for Copilot CLI |
| `AGENTS.md` | Repo root, cwd, or compatible instruction roots | Open-standard instructions, often used for shared agent behavior |
| `CLAUDE.md`, `GEMINI.md` | Repo root | Compatibility instruction files that Copilot CLI can also load |
| `copilot-instructions.md` | `~/.copilot/` | Personal defaults for all local CLI sessions |

Copilot CLI can load **both** `.github/copilot-instructions.md` and `AGENTS.md` together. Do not assume "choose one" unless you are intentionally simplifying a workspace policy.

`COPILOT_CUSTOM_INSTRUCTIONS_DIRS` can add more instruction roots when you need local or shared directories outside the repository.

## Template

Only include material that should apply broadly:

```markdown
# Project Guidelines

## Code Style
{Language and formatting preferences with links to examples}

## Architecture
{Major components, boundaries, and non-obvious design rules}

## Build and Test
{Install, build, and test commands the CLI can run}

## Conventions
{Patterns that differ from common defaults}
```

For large repos, link to detailed docs instead of copying them into the instruction file.

## When to Use

- Repository-wide coding and testing standards
- Shared team rules that should always be present
- Personal CLI defaults that are useful across many repositories

## Core Principles

1. **Keep it additive**: Separate repository policy from personal defaults
2. **Keep it short**: Every line should change behavior
3. **Link, do not duplicate**: Point at deeper docs instead of copying them
4. **Keep repo and home scopes distinct**: Repository files for team policy, `~/.copilot/` for personal defaults

## Anti-patterns

- **Teaching "choose one" as a CLI rule**: Copilot CLI can load multiple instruction files together
- **Putting repo-specific rules in home-level instructions**: This creates cross-repo leakage
- **Copying whole READMEs**: Link to docs instead
- **Using workspace instructions for one-off workflows**: Use a skill, command, or custom agent instead
