# Agent Customization Primitives — Inventory and Skill Scope

Companion to [SKILL.md](../SKILL.md). Grounded in the official VS Code "Understand agent customization" taxonomy and GitHub Copilot docs, verified 2026-10-11. Claim-to-source mapping: [sources.md](sources.md).

## Official taxonomy

Per the VS Code docs, agent customization covers: providing **context** (instructions), defining **repeatable work** (agent skills, prompt files), configuring a **role** (custom agents), adding **capabilities** (MCP servers), **enforcing actions** (hooks), and **packaging** (agent plugins). The decision matrix maps needs to the smallest fitting primitive.

## In scope — prose-bearing context primitives

This skill governs ownership and inheritance of the **guidance text** in these five primitives:

| Primitive | Repo location | Role | Key mechanics |
|---|---|---|---|
| Root constitution (always-on instructions) | `.github/copilot-instructions.md` or `AGENTS.md` | Universal rules + authority model | Attached to every request; read first; valid owner when no scoped file exists |
| File-based instructions | `.github/instructions/*.instructions.md` | Policy scoped by `applyTo` pattern (on-demand via `description`) | Auto-attach when the pattern matches |
| Agent skills | `.github/skills/<name>/SKILL.md` | Task playbooks loaded on demand | `name` + `description` drive discovery |
| Custom agents | `.github/agents/*.agent.md` | Roles: instructions + tools + model | Body max 30,000 chars; reference other files via Markdown link or `#file:<path>` |
| Prompt files | `.github/prompts/*.prompt.md` | User-invoked slash commands | Deprecated for Agent Host sessions — prefer skills |

## Out of scope — executable/config primitives

Other workflows own these; this skill only applies its prose discipline to any *documentation* of their rules, never to the config itself:

| Primitive | Why out of scope | Where it lives |
|---|---|---|
| Hooks | Deterministic lifecycle commands, not guidance text | Harness-specific config (VS Code hooks settings; agent-scoped hooks are Preview) |
| MCP servers | Tool connectivity config; repo-level config is entered in GitHub.com repo **Settings → Copilot → MCP servers** (not a `.github` file); also settable via agent frontmatter `mcp-servers` | GitHub.com settings / agent frontmatter / VS Code settings |
| Tool sets and tool lists | Capability selection (`tools` frontmatter), not prose | Agent frontmatter, VS Code toolset files |
| Agent plugins | Packaging/distribution of the primitives above — a publish-time concern, not an ownership question | `plugin.json` bundles installed via marketplaces |
