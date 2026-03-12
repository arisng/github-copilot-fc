# Commit Scope Constitution

Last Updated: 2026-02-24

## Purpose

This constitution defines the approved scopes for atomic commits in the `github-copilot-fc` repository, ensuring consistency and clarity in commit history. It aligns with the repository's artifact-centric structure and automation-first architecture.

## Repository Context

This repository is a **customization factory** for GitHub Copilot customizations:

| Directory             | Domain                | Primary Artifact Type              |
| --------------------- | --------------------- | ---------------------------------- |
| `agents/`             | AI Agents             | `.agent.md` files                  |
| `instructions/`       | Copilot Instructions  | `.instructions.md` files           |
| `prompts/`            | Prompt Templates      | `.prompt.md` files                 |
| `skills/`             | Skill Libraries       | `SKILL.md` + supporting scripts    |
| `scripts/`            | Automation            | `.ps1`, `.py` scripts              |
| `toolsets/`           | Tool Configurations   | `.toolsets.jsonc` files            |
| `plugins/`            | Copilot CLI Plugins   | `plugin.json` + local components   |
| `copilot-sdk/`        | SDK Documentation     | `.md` docs                         |
| `prompt-engineering/` | PE Research           | `.md`, `.json` docs                |
| `.github/`            | Repository Governance | Constitution, inventory, workflows |

## Scope Naming Conventions

1. **Format**: Use `kebab-case` (lowercase, hyphen-separated words)
2. **Number**: Use **singular** form — `skill` not `skills`, `toolset` not `toolsets`, `issue` not `issues`
3. **Specificity**: Choose the most specific scope that accurately identifies the changed area
4. **Single Scope Only**: Each commit uses exactly **one** scope
5. **No Path Syntax**: Never use `/` in scope names — use `skill` not `copilot/skill`, `script` not `devtool/script`

## Approved Scopes by Commit Type

### `copilot`

Changes to GitHub Copilot customization artifact files — the most-used commit type in this repo.

- `custom-agent`: Copilot custom agent definition files (`agents/**/*.agent.md`)
- `instruction`: Copilot custom instruction files (`instructions/**/*.instructions.md`)
- `mcp`: MCP server configuration for Copilot CLI (`.github/mcp*.json`, `mcp-config.json`)
- `memory`: Copilot memory files (`.copilot/memories/`)
- `plugin`: Copilot plugin definition and assets (`plugins/**/plugin.json`)
- `prompt`: Copilot prompt files (`prompts/**/*.prompt.md`)
- `toolset`: Copilot toolset configuration files (`toolsets/**/*.toolsets.jsonc`)
- `hook`: Copilot hook lifecycle configurations (`hooks/`)

### `agent`

Tier 2 extended type replacing the deprecated `ai` type. Use for changes to AI agent assets and AI model-facing behavior — skill instructions, agent intelligence, or model configuration.
Use `agent` when the scope is beyond Copilot artifact files; Skill is now standard customization across Coding Agents and not specific to Copilot; use `copilot` when the scope is a Copilot specific customization artifact.

- `codex`: AI codex knowledge base or index entries
- `instruction`: AI behavioral changes to agent definition files (instructions, persona, reasoning) *(was `ai(agent)`)*
- `prompt-engineering`: Prompt engineering research and analysis (`prompt-engineering/`)
- `skill`: AI instruction content within skills folders (`skills/**`)

### `ai`

> **Deprecated type.** Use `agent` instead. All `ai(*)` commits should migrate to `agent(*)`. See Amendment #3 and the selection guide below.

Historical scopes (do not use in new commits):

- ~~`agent`~~ → `agent(instruction)`
- ~~`codex`~~ → `agent(codex)`
- ~~`mcp`~~ → `agent(mcp)`
- ~~`prompt`~~ → `agent(prompt)`
- ~~`prompt-engineering`~~ → `agent(prompt-engineering)`
- ~~`skill`~~ → `agent(skill)`

### `docs`

Documentation-only changes (non-code, non-artifact).

- `agent`: Documentation about agent design, decisions, or capabilities (e.g., README.md, CRITIQUE.md in `agents/`)
- `changelog`: Changelog files and release notes
- `constitution`: Commit scope constitution or governance docs (`.github/scope-*.md`)
- `copilot-cli`: GitHub Copilot CLI documentation
- `issue`: Issue documents (`.issues/`)
- `readme`: Root or directory-level README files
- `reference`: Reference materials, API docs, or specification files
- `plugin`: Documentation for Copilot CLI plugins (e.g., README.md in `plugins/`)
- `research`: Research notes and analysis documents
- `script`: Documentation for scripts or automation
- `workspace`: Workspace-level documentation

### `devtool`

Changes to developer tooling, automation scripts, and editor integrations.

- `git`: Git hooks, configuration, aliases, or workflow tooling
- `script`: Automation and utility scripts (`scripts/`)
- `vscode`: VS Code extensions, tasks, settings, or launch configurations

### `chore`

Maintenance tasks, configuration updates, and housekeeping that don't affect functionality.

- `build`: Build system or dependency configuration updates
- `config`: General project or tool configuration files
- `vscode`: VS Code workspace settings (`.vscode/` directory)
- `workspace`: Workspace-level setup, folder restructuring, or root config files

### `feat`

New features or capabilities added to the workspace.

- `agent`: New agent capability or entirely new agent file
- `copilot-sdk`: GitHub Copilot SDK features (`copilot-sdk/`)
- `instruction`: New instruction capability
- `plugin`: New Copilot CLI plugin
- `prompt`: New prompt template
- `script`: New automation script
- `skill`: New skill or major skill capability
- `toolset`: New toolset definition

### `refactor`

Artifact or code restructuring without behavior change.

- `agent`: Reorganizing or restructuring agent files
- `instruction`: Restructuring instruction files
- `prompt`: Restructuring prompt files
- `plugin`: Restructuring plugin files or directory structure
- `skill`: Restructuring skill files (single skill or cross-skill reorganization)
- `toolset`: Restructuring toolset files
- `script`: Restructuring script files

### `build`

Build system, CI/CD pipeline, or dependency changes.

- *(Scopes rare in this repo — use `chore(build)` for build config changes unless targeting CI specifically)*
- `ci`: CI/CD pipeline configuration changes

### `style`

Style or formatting changes only (whitespace, formatting — no logic changes).

- *(Scopes optional; if needed use the artifact area: `agent`, `instruction`, `prompt`, `skill`)*

### `vscode`

> **Deprecated type.** Use `chore(vscode)` for VS Code settings or `devtool(vscode)` for tooling instead.

- `workspace`: VS Code workspace configuration *(legacy — use `chore(vscode)` or `devtool(vscode)`)*

## `agent` vs `copilot` — Selection Guide

These two commit types often apply to the same files. Use this guide to choose:

| Scenario                                 | Type      | Example                                                          |
| ---------------------------------------- | --------- | ---------------------------------------------------------------- |
| Adding a new `.agent.md` file            | `copilot` | `copilot(custom-agent): add nexus orchestrator agent`            |
| Updating agent persona/tools list        | `copilot` | `copilot(custom-agent): add memory tool to planner`              |
| Improving agent's reasoning instructions | `agent`   | `agent(instruction): strengthen replanning logic in orchestrator`|
| Creating a new `SKILL.md` file           | `copilot` | `copilot(skill): add beads issue tracker skill`                  |
| Updating skill's AI instruction content  | `agent`   | `agent(skill): refine scope constitution extraction workflow`    |
| Adding new `.prompt.md` file             | `copilot` | `copilot(prompt): add gitAtomicCommit prompt`                    |
| Researching prompt patterns              | `agent`   | `agent(prompt-engineering): analyze chain-of-thought patterns`   |

**Rule of thumb**: `copilot` = *managing the artifact file*; `agent` = *improving the intelligence inside the artifact*.

## Scope Selection Guidelines

1. **Match the artifact directory first**: File in `skills/` → `skill`, file in `plugins/` → `plugin`, file in `agents/` → `custom-agent` or `agent`, file in `prompts/` → `prompt`, file in `toolsets/` → `toolset`.

2. **Choose commit type by intent**:
   - `copilot` → GitHub Copilot customization artifact lifecycle (most common type)
   - `agent` → AI model-facing behavior or intelligence changes *(replaces deprecated `ai`)*
   - `feat` → New capability being added for the first time
   - `refactor` → Restructuring without behavior change
   - `docs` → Documentation-only changes
   - `chore` → Maintenance and housekeeping
   - `devtool` → Developer workflow automation

3. **feat with copilot scopes**: When adding an entirely new artifact (skill, agent, prompt), use `feat` for the initial commit establishing the capability, then use `copilot` or `agent` for subsequent iterations.

4. **No path syntax**: Use simple scope names — never `copilot/skill`, `devtool/script`, or similar path-style scopes.

5. **Singular always**: `skill` not `skills`, `toolset` not `toolsets`, `issue` not `issues`.

6. **If no scope fits**: Consult the Amendment Process before inventing a new scope.

## Deprecated Scopes

These scopes and types appeared in historical commits but **must not be used in new commits**:

**Deprecated Types:**

| Deprecated Type | Replacement | Notes |
| --------------- | ----------- | ----- |
| `ai`            | `agent`     | All `ai(scope)` commits migrate to `agent(scope)`; `ai(agent)` specifically → `agent(instruction)` |
| `vscode`        | `chore(vscode)` or `devtool(vscode)` | See `vscode` section above |

**Deprecated Scopes:**

These scopes appeared in historical commits but **must not be used in new commits**:

| Deprecated Scope       | Replacement                     | Commit Type Context |
| ---------------------- | ------------------------------- | ------------------- |
| `copilot/custom-agent` | `agent` (for `feat`/`refactor`) | `feat`, `refactor`  |
| `copilot/instruction`  | `instruction`                   | `feat`, `refactor`  |
| `copilot/prompt`       | `prompt`                        | `feat`, `refactor`  |
| `copilot/skill`        | `skill`                         | `feat`, `refactor`  |
| `devtool/script`       | `script`                        | `feat`              |
| `custom-agents`        | `custom-agent`                  | `copilot`           |
| `toolsets`             | `toolset`                       | `copilot`           |
| `issues`               | `issue`                         | `docs`              |
| `git-commit-scope`     | `constitution`                  | `docs`              |

## Amendment Process

To propose a new scope or modify an existing one:

1. **Identify the gap**: Which architectural area or module lacks a scope?
2. **Check for overlap**: Does any existing approved scope cover the same area?
3. **Follow conventions**: Ensure the proposed name is kebab-case, singular, and has no path syntax
4. **Update constitution**: Add the scope to the appropriate commit type section with a definition
5. **Re-run inventory**: Run `python skills/git-commit-scope-constitution/scripts/extract_scopes.py --format markdown --output .github/git-scope-inventory.md` to refresh the inventory
6. **Document amendment**: Add an entry to the Amendment History below

## Amendment History

### 2026-02-24 — Amendment #1 (Initial Constitution)

**Changes:**
- Created initial constitution from full git history analysis (51 unique scopes across 10 commit types)
- Established approved scope sets for: `copilot`, `ai`, `docs`, `devtool`, `chore`, `feat`, `refactor`, `build`, `style`, `vscode`
- Deprecated 9 path-style and plural scopes (see Deprecated Scopes table)
- Renamed `git-commit-scope` → `constitution` under `docs` type
- Marked `vscode` commit type as legacy in favor of `chore(vscode)` / `devtool(vscode)`
- Clarified `ai` vs `copilot` type selection with decision table

**Rationale:**
Initial constitution creation based on analysis of all git history combined with repository structure inspection. The `copilot(custom-agent)` pattern dominates the commit history and is the primary workflow type in this repo.

**Migration Notes:**
- Existing commits with deprecated scopes are preserved as-is (no history rewriting)
- For new commits, consult the `agent` vs `copilot` selection guide above
- The `feat` type should use simple single-word scopes, not path-style scopes

### 2026-02-24 — Amendment #2 (Inventory Refresh)

**Changes:**
- Regenerated scope inventory → 52 unique scopes (up from 51 at initial creation)
- Confirmed `docs(constitution)` is now active in git history (first usage: the initial constitution commit itself)
- Restored deprecated annotations to inventory after regeneration (extraction script strips annotations; they are maintained manually)
- Validated scope coverage against all 10 commit types and full repository structure — no gaps or amendments required

**Rationale:**
First post-creation review, same day as initial creation. The initial constitution accurately reflects all active development patterns across the full git history. No structural or scope amendments are needed at this time.

**Migration Notes:**
No changes to approved scopes. All existing commit patterns remain valid.

### 2026-02-24 — Amendment #3 (Deprecate `ai` type, introduce `agent`)

**Changes:**
- Deprecated `ai` commit type entirely; use `agent` for all AI model-facing behavior commits going forward
- Added `### \`agent\`` section with 6 approved scopes: `codex`, `instruction`, `mcp`, `prompt`, `prompt-engineering`, `skill`
- Scope `ai(agent)` migrates to `agent(instruction)` (avoids the `agent(agent)` identity redundancy)
- All other `ai` scopes carry over to `agent` unchanged
- Updated `ai` vs `copilot` Selection Guide → `agent` vs `copilot` Selection Guide (all examples updated)
- Updated Scope Selection Guidelines point #2 and #3 to reference `agent` instead of `ai`
- Added a **Deprecated Types** table above the Deprecated Scopes table

**Rationale:**
The `ai` type was removed from the author's commit conventions in favor of the more precise `agent` extended type. `agent` already exists in Tier 2 of the `git-atomic-commit` skill to cover AI agent assets (`skills/*`, `**/AGENTS.md`). Consolidating under `agent` eliminates the ambiguity between `ai` and `agent` types and aligns the constitution with the skill's actual Tier 2 mapping.

**Migration Notes:**
- All new commits previously using `ai(skill)` → use `agent(skill)`
- All new commits previously using `ai(agent)` → use `agent(instruction)`
- All other `ai(scope)` → use `agent(scope)` verbatim
- Existing `ai(*)` commits in history are preserved as-is
