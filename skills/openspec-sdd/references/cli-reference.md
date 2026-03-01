# CLI Reference

Full OpenSpec CLI commands and flags for GitHub Copilot integration.

## Table of Contents

- [init](#init)
- [update](#update)
- [list](#list)
- [show](#show)
- [status](#status)
- [instructions](#instructions)
- [validate](#validate)
- [archive](#archive)
- [config](#config)
- [schema](#schema)
- [completion](#completion)

## Agent Best Practices

When using the CLI programmatically (from an AI agent or script):

- **Always use `--json`** — structured output avoids parsing markdown tables
- **Always use `--no-color`** — prevents ANSI escape codes that confuse LLM parsing
- **Use `--no-interactive`** on commands that support it — avoids blocking prompts
- Recommended pattern: `openspec <command> --json --no-color`
- Example: `openspec validate --strict --json --no-color --no-interactive`

## init

Initialize OpenSpec in a project.

```bash
openspec init [path] [options]
```

| Flag | Description |
|---|---|
| `--tools <list>` | Configure AI tools: `github-copilot`, `all`, `none`, or comma-separated |
| `--force` | Auto-cleanup legacy files without prompting |
| `--profile <profile>` | Override global profile (`core` or custom) |

**For GitHub Copilot**: `openspec init --tools github-copilot`

Creates:
- `openspec/` directory tree (specs/, changes/, config.yaml)
- `.github/skills/openspec-*/SKILL.md` — Copilot skill files
- `.github/prompts/opsx-*.prompt.md` — Copilot slash commands

If `openspec/` exists, enters extend mode (adds tools without recreating base).

## update

Regenerate AI tool configuration files after CLI upgrade.

```bash
openspec update [path] [options]
```

| Flag | Description |
|---|---|
| `--force` | Force update even when files are up to date |

Run after: upgrading OpenSpec CLI, changing profile, or modifying delivery settings.

## list

List changes or specs.

```bash
openspec list [options]
```

| Flag | Description |
|---|---|
| `--specs` | List specs instead of changes |
| `--changes` | List changes (default) |
| `--sort <order>` | Sort by `recent` (default) or `name` |
| `--json` | Output as JSON |

## show

Display content of a specific change or spec.

```bash
openspec show <item> [options]
```

| Flag | Description |
|---|---|
| `--json` | Output as JSON for parsing |
| `--type <type>` | Disambiguate item kind: `change` or `spec` |
| `--no-interactive` | Disable interactive prompts |

**Change-specific flags:**

| Flag | Description |
|---|---|
| `--deltas-only` | Show only delta specs (JSON mode) |

**Spec-specific flags:**

| Flag | Description |
|---|---|
| `--requirements` | Requirements only, no scenarios |
| `--no-scenarios` | Exclude scenario content |
| `-r`, `--requirement <id>` | Show specific requirement by 1-based ID |

Example: `openspec show add-dark-mode`

## status

Display artifact completion status for a change.

```bash
openspec status --change "<name>" [options]
```

| Flag | Description |
|---|---|
| `--json` | Output as JSON |

Shows each artifact as complete, ready, or blocked with missing dependencies.
Use programmatically to determine next steps in workflow.

## instructions

Get enriched instructions for creating a specific artifact or applying tasks.

```bash
openspec instructions <artifact> [options]
```

| Flag | Description |
|---|---|
| `--json` | Output as JSON |
| `--change <id>` | Specify change name (required for non-interactive use) |
| `--schema <name>` | Override schema |

Outputs: artifact metadata, template content, dependency status, unlocked artifacts.
Primarily used by AI agents to understand what to create next.

## validate

Check changes and specs for structural issues.

```bash
openspec validate [change-or-spec-id] [options]
```

| Flag | Description |
|---|---|
| `--all` | Validate all changes and specs |
| `--changes` | Validate all changes |
| `--specs` | Validate all specs |
| `--json` | Output as JSON |
| `--strict` | Treat warnings as errors |
| `--type <type>` | Disambiguate: `change` or `spec` |
| `--concurrency <n>` | Parallel validations (default 6) |
| `--no-interactive` | Disable interactive prompts |

Checks: valid section markers, operation rules (RENAMED must have FROM:/TO:), spec structure.

## archive

Finalize a completed change.

```bash
openspec archive [change-name] [options]
```

| Flag / Arg | Description |
|---|---|
| `[change-name]` | Positional arg — change to archive (interactive selection if omitted) |
| `--skip-specs` | Skip spec update; use for doc/tooling-only changes |
| `--no-validate` | Skip validation |
| `--yes`, `-y` | Skip confirmation prompts |

Process:
1. Validates task completion (incomplete tasks → confirmation prompt)
2. Validates delta spec structure (errors block archive)
3. Merges delta specs: RENAMED → REMOVED → MODIFIED → ADDED
4. Moves change to `openspec/changes/archive/YYYY-MM-DD-<name>/`

## config

View and modify OpenSpec configuration.

```bash
openspec config <subcommand> [options]
```

| Subcommand | Description |
|---|---|
| `path` | Show config file location |
| `list` | Show all current settings |
| `get <key>` | Get a specific value |
| `set <key> <value>` | Set a value |
| `unset <key>` | Remove a key |
| `reset` | Reset to defaults |
| `edit` | Open in $EDITOR |
| `profile [preset]` | Set workflow profile interactively or via preset |

**Subcommand-specific flags:**

| Subcommand | Flag | Description |
|---|---|---|
| `set` | `--string` | Force string storage |
| `set` | `--allow-unknown` | Set non-schema keys |
| `reset` | `--all` | Required — reset all settings |
| `reset` | `-y`, `--yes` | Skip confirmation |
| `list` | `--json` | JSON output |

## schema

Manage workflow schemas. *(Experimental)*

```bash
openspec schema <subcommand> [options]
```

| Subcommand | Description |
|---|---|
| `init <name>` | Create new project-local schema |
| `fork <source> <name>` | Copy existing schema for customization |
| `validate <name>` | Validate schema structure and templates |
| `which [name]` | Show where a schema resolves from |

**Subcommand-specific flags:**

| Subcommand | Flag | Description |
|---|---|---|
| `init` | `--description <text>` | Schema description |
| `init` | `--artifacts <list>` | Comma-separated artifact list |
| `init` | `--default` | Set as project default schema |
| `init` | `--no-default` | Do not set as default |
| `init` | `--force` | Overwrite existing schema |
| `init` | `--json` | JSON output |
| `fork` | `--force` | Overwrite existing target |
| `fork` | `--json` | JSON output |
| `validate` | `--verbose` | Detailed validation output |
| `validate` | `--json` | JSON output |
| `which` | `--all` | Show all resolution sources |
| `which` | `--json` | JSON output |

## completion

Manage shell completions.

```bash
openspec completion <subcommand> [shell]
```

| Subcommand | Description |
|---|---|
| `generate [shell]` | Output completion script to stdout |
| `install [shell]` | Install completions to shell config |
| `uninstall [shell]` | Remove installed completions |

**Subcommand-specific flags:**

| Subcommand | Flag | Description |
|---|---|---|
| `install` | `--verbose` | Show installation details |
| `uninstall` | `-y`, `--yes` | Skip confirmation |

Supported shells: bash, zsh, fish, powershell.
