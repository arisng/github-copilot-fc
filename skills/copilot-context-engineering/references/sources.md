# Authoritative Sources (verified 2026-10-11)

Claim-to-source mapping for the layout and mechanism statements in [SKILL.md](../SKILL.md). Re-verify after major Copilot releases or when a URL 404s (docs restructure; search `docs.github.com` or `code.visualstudio.com` for the page title). Where a source conflicts with SKILL.md, the source wins.

## Contents

- [Standard layout](#standard-layout)
- [Inheritance mechanisms](#inheritance-mechanisms)
- [Deprecations and migration signals](#deprecations-and-migration-signals)

## Standard layout

| Claim in SKILL.md | Source |
|---|---|
| Workspace custom agents live in `.github/agents` as `*.agent.md` files | [Custom agents in VS Code — Custom agent file locations](https://code.visualstudio.com/docs/agent-customization/custom-agents); VS Code also detects any `.md` file in `.github/agents` as an agent |
| Creating an agent on GitHub.com opens a template at `.github/agents/<name>.agent.md`; org/enterprise agents use a root `agents/` directory | [Creating custom agents for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents) |
| Skills live in `.github/skills/<name>/SKILL.md`; personal skills in `~/.copilot/skills` or `~/.agents/skills` | [Adding agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills) |
| Scoped instructions live in `.github/instructions/*.instructions.md` and attach via `applyTo` patterns (on-demand via `description`) | [Use custom instructions in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-instructions) |
| Root constitution: `.github/copilot-instructions.md`; `AGENTS.md` is the cross-agent shared project-instructions format | [Use custom instructions in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-instructions) |
| Alternative harness layouts exist (`.claude/agents`, `.claude/rules`, `.claude/skills`) | [Custom instructions in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-instructions) (file-location table); [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents) |
| Agent frontmatter: `description` is required, `name` optional (defaults to filename), plus `tools`, `model`, `target`, `user-invocable`, `disable-model-invocation` (`infer` retired) | [Custom agents configuration (GitHub reference)](https://docs.github.com/en/copilot/reference/custom-agents-configuration) |

## Inheritance mechanisms

| Claim in SKILL.md | Source |
|---|---|
| Agents reference other files (e.g., instructions) from the body with Markdown links or `#file:<path>`; relative paths resolve from the agent file; Unix-style `/` separators for portability | [Custom agents in VS Code — Body](https://code.visualstudio.com/docs/agent-customization/custom-agents) |
| Instructions inherit automatically for files matching their `applyTo` pattern — no per-consumer pointer needed | [Use custom instructions in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-instructions) |
| Skills are discovered by frontmatter `name` + `description` and loaded on demand; cross-file pointers are a prose convention, not a platform field | [About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills); [Use Agent Skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills) |
| Agent Markdown body limit is 30,000 characters (relevant when deciding what prose belongs in an agent vs. an owner file) | [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration) |

## Deprecations and migration signals

| Claim in SKILL.md | Source |
|---|---|
| Prompt files (`.github/prompts/*.prompt.md`) are deprecated for Agent Host sessions and are not loaded there; convert them to skills — prefer skills for workflows that must auto-trigger | [Use prompt files in VS Code](https://code.visualstudio.com/docs/agent-customization/prompt-files) |
| Agent `infer` frontmatter property is retired; use `disable-model-invocation` and `user-invocable` | [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration) |

## Primitive taxonomy and scope

| Claim in SKILL.md / references/primitives.md | Source |
|---|---|
| Official customization types: always-on + file-based instructions, agent skills, prompt files, custom agents, MCP servers, hooks, agent plugins — mapped to context / repeatable work / roles / capabilities / enforcement / packaging | [Understand agent customization (decision matrix)](https://code.visualstudio.com/docs/agents/concepts/customization) |
| Repository MCP configuration is entered in GitHub.com repo Settings → Copilot → MCP servers (JSON), not stored as a `.github` file; it can also be set per-agent via the `mcp-servers` frontmatter | [Configure MCP servers for your repository](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/configure-mcp-servers) |
| Hooks run commands at lifecycle points independent of the model (deterministic enforcement, not guidance prose) | [Understand agent customization](https://code.visualstudio.com/docs/agents/concepts/customization); [Hooks in VS Code](https://code.visualstudio.com/docs/agent-customization/hooks) |
