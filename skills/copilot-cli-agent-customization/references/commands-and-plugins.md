# [Commands and Plugins](https://docs.github.com/en/copilot/reference/cli-plugin-reference)

Terminal-first reusable workflows in Copilot CLI are usually delivered through plugin `commands`, plugin bundles, or skills. Do **not** use `.prompt.md` prompt files for CLI.

## Core File Layout

| File or Folder | Location | Purpose |
|----------------|----------|---------|
| `plugin.json` | `plugins/cli/<name>/` | Declares plugin components such as commands, skills, agents, and hooks |
| `commands/*.md` | `plugins/cli/<name>/commands/` | Lightweight reusable command files |
| `skills/<name>/` | `plugins/cli/<name>/skills/` or workspace `skills/` | Richer workflows with bundled references, scripts, and assets |

## When to Use

| Primitive | Best Fit |
|-----------|----------|
| Command file | Single focused terminal shortcut or reusable one-step workflow |
| Plugin bundle | Share a command pack, skill set, or related CLI customizations across machines or teams |
| Skill | Multi-step workflow with bundled references, scripts, or reusable operational context |

If the request sounds like "make me a slash-command style shortcut for CLI," start here.

## Minimal Plugin Example

```json
{
  "name": "my-cli-workflows",
  "version": "0.1.0",
  "commands": "commands/",
  "skills": "skills/"
}
```

## Official Plugin Fields

These are the official component fields supported by the workspace and the CLI plugin reference:

- `agents`
- `skills`
- `commands`
- `hooks`
- `mcpServers`
- `lspServers`

`instructions` is **not** a plugin field. If an agent needs extra instructions inside a plugin, this workspace handles that through build-time embedding.

## Publish and Install Pattern

For workspace-managed plugins:

1. Build or publish the plugin bundle
2. Install the local bundle with `copilot plugin install <local bundle path>`
3. Reinstall after local edits because plugin installs are cached

If you only change a standalone skill under `skills/`, publish it with the skill publish script instead of wrapping it in a plugin unless you also need commands or other bundled components.

## Prompt File Boundary

`.prompt.md` is an IDE customization surface, not a Copilot CLI one. If the user asks for a prompt-like CLI shortcut:

1. Use a command file when the workflow is lightweight
2. Use a skill when the workflow needs more structure
3. Use a custom agent when the workflow needs a persona or tool restrictions

## Core Principles

1. **Commands for shortcuts, skills for capability**: Do not collapse them into one concept
2. **Bundle when you need distribution**: Plugins are the shareable packaging layer
3. **Keep `plugin.json` official-field only**: Unsupported fields fail silently or are ignored
4. **Treat reinstall as part of the workflow**: Local plugin edits are not live-linked

## Anti-patterns

- **Trying to register `.prompt.md` in CLI**: Prompt files are IDE-only
- **Using instructions as command definitions**: Instructions guide behavior; they do not create reusable command entries
- **Forgetting plugin reinstall**: Old bundle contents stay installed
- **Overusing plugins for one local instruction file**: Use the smallest primitive that fits
