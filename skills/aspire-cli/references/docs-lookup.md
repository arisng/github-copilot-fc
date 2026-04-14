# Aspire docs lookup workflows (13.2)

Sources:
- https://devblogs.microsoft.com/aspire/aspire-docs-in-your-terminal/
- https://aspire.dev/get-started/ai-coding-agents/
- https://aspire.dev/reference/cli/commands/aspire-docs/
- https://aspire.dev/reference/cli/commands/aspire-docs-list/
- https://aspire.dev/reference/cli/commands/aspire-docs-search/
- https://aspire.dev/reference/cli/commands/aspire-docs-get/
- https://aspire.dev/whats-new/aspire-13-2/

## Why this belongs in the default workflow

- Aspire 13.2 treats `aspire docs` as a first-class CLI surface for official `aspire.dev` guidance.
- The same docs are exposed to humans, skills, automation, and Aspire MCP tooling, so the agent should look up current guidance instead of guessing from memory.
- Use docs lookup before editing unfamiliar integrations, custom commands, or AppHost APIs.

## CLI docs workflow

1. Use `aspire docs list` when the page or slug is not obvious yet.
2. Use `aspire docs search "<topic>"` to get ranked results and slugs. Add `--limit` when you want a smaller result set.
3. Use `aspire docs get <slug>` to read the full page. Add `--section "<heading>"` when one section is enough.
4. Use `--format Json` and `--non-interactive` when another tool or agent needs structured output without prompts.

## When to look up docs before editing

- Before `aspire add <name-or-id>` for an unfamiliar integration
- Before custom dashboard or resource commands such as `WithCommand`
- Before editing unfamiliar C# or TypeScript AppHost APIs
- Before updating prompts, skills, or automation that explain Aspire behavior

## CLI and MCP docs parity

| Need | CLI | MCP |
| --- | --- | --- |
| Browse available docs pages | `aspire docs list` | `list_docs` |
| Search the docs set | `aspire docs search <topic>` | `search_docs` |
| Read a selected page | `aspire docs get <slug>` | `get_doc` |

- Prefer CLI docs commands when you just need a terminal lookup.
- Prefer MCP docs tools when Aspire MCP is already connected and keeping the workflow inside the current agent session is simpler.

## Example flows

1. Add an integration safely:
   - `aspire docs search postgres`
   - `aspire docs get <slug>`
   - `aspire add <name-or-id>`
2. Find a custom command pattern:
   - `aspire docs search "custom resource commands"`
   - `aspire docs get custom-resource-commands`
