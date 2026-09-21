# Type & Scope Mapping Reference

Detailed tables for Tier 2 extended types, Tier 3 example mappings, and common mistakes.
Read this when assigning commit types and scopes to files (Workflow steps 2–3).

## Tier 2: Extended Types (Author Preferences)

> These extended types reflect the author's (`arisng`) personal conventions for AI/DevTool-heavy repositories. You are free to modify, remove, or add your own extended types to suit your workflow.

Extended types take precedence over universal types when the file matches a known pattern:

| Extended Type | Replaces | Domain | Typical File Patterns |
|---------------|----------|--------|-----------------------|
| `agent` | `feat`, `chore` | AI agent assets (skills, instructions) | `skills/*`, `**/AGENTS.md` |
| `copilot` | `feat`, `chore` | GitHub Copilot assets | `*.agent.md`, `*.prompt.md`, `instructions/*.md`, `.vscode/mcp.json`, `memory.json` |
| `devtool` | `chore`, `build` | Developer tooling & editor config | `scripts/*`, `.vscode/settings.json`, `.vscode/tasks.json` |
| `codex` | `chore` | OpenAI Codex assets | `.codex/*` |

**Rule:** When a file matches an extended type pattern, always use the extended type instead of the universal one. Fall back to universal types for everything else.

## Tier 3: Example Workspace Mappings

The mapping below is an **example** from the author's workspace. Each repository should define its own via the `git-commit-scope-constitution` skill. Your repository's `.github/git-scope-constitution.md` is the source of truth.

| File Path Pattern | Type (Tier 2) | Scope (Tier 3) | Rationale |
|-------------------|---------------|----------------|-----------|
| `.issues/*` | `docs` | `issue` | Issue documentation and tracking |
| `.docs/changelogs/*` | `docs` | `changelog` | Changelog files |
| `.github/git-scope-constitution.md` | `docs` | `constitution` | Scope constitution governance |
| `instructions/*.md` | `copilot` | `instruction` | Repository-level Copilot instructions |
| `skills/*` | `agent` | `skill` | Agent skill definitions and implementations |
| `scripts/*` | `devtool` | `script` | Automation scripts (PowerShell, Python, Bash) |
| `*.agent.md` | `copilot` | `custom-agent` | Custom agent definitions |
| `**/AGENTS.md` | `agent` | `instruction` | Standard AI agent custom instructions |
| `*.prompt.md` | `copilot` | `prompt` | Copilot prompt files |
| `memory.json` | `copilot` | `memory` | Knowledge graph memory systems |
| `.codex/*.json` | `codex` | `config` | Codex configuration files |
| `.codex/*.md` | `codex` | `instruction` | Codex instruction files |
| `.vscode/mcp.json` | `copilot` | `mcp` | MCP server configuration |
| `.vscode/settings.json` | `devtool` | `vscode` | VS Code workspace settings |
| `.vscode/tasks.json` | `devtool` | `vscode` | VS Code workspace task configurations |

## Common Mistakes to Avoid

- ❌ Conflating type and scope: `docs(issue)` is NOT a type. `docs` is the type, `issue` is the scope.
- ❌ `feat(instructions)` → ✅ `copilot(instruction)` — Use extended type `copilot` (Tier 2)
- ❌ `feat(skill)` → ✅ `agent(skill)` — Use extended type `agent` (Tier 2)
- ❌ `ai(skill)` → ✅ `agent(skill)` — `ai` type is deprecated; use `agent` for all AI model-facing behavior
- ❌ `ai(agent)` → ✅ `agent(instruction)` — deprecated `ai` type; the old `agent` scope maps to `instruction` under `agent`
- ❌ `chore(issue)` → ✅ `docs(issue)` — `docs` is the appropriate universal type
- ❌ `docs` (no scope) → ✅ `docs(issue)` or `docs(changelog)` — Always include a scope
- ❌ `agent(pdf)` → ✅ `agent(skill)` — Use category-level scope, put specific item in subject
- ❌ Mixing `copilot(mcp)` + `devtool(vscode)` in one commit → ✅ Separate commits
- ❌ Grouping files with different types → ✅ One type per commit

## Worked Example

```text
File: skills/pdf/SKILL.md
  → Type: agent            [Tier 2 extended type for AI agent assets]
  → Scope: skill           [Tier 3 category-level scope]
  → Result: agent(skill): add table extraction to pdf
```