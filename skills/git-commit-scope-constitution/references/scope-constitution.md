# Commit Scope Constitution

Last Updated: [DATE]

## Purpose

This constitution defines the **Tier 3 (Workspace-Specific)** scopes for atomic commits in this repository. It serves as the authoritative reference for:

- Valid scope names organized by commit type (Tier 1 universal + Tier 2 extended)
- Scope definitions and boundaries
- Naming conventions and patterns
- Guidelines for choosing appropriate scopes

> **Three-Tier Model:** Types come from Tier 1 (universal: `feat`, `fix`, `docs`...) and Tier 2 (author preferences: `agent`, `copilot`, `devtool`, `codex`). This constitution governs **Tier 3**: the repo-specific scopes paired with those types.

## Scope Naming Conventions

### Format Rules

- **Kebab-case**: Use hyphens to separate words (`user-profile`, not `userProfile` or `user_profile`)
- **Lowercase**: All scope names must be lowercase
- **Singular form**: Prefer singular (`skill`, not `skills`) unless naturally plural
- **No special characters**: Only lowercase letters, numbers, and hyphens
- **Concise**: Aim for 1-3 words maximum
- **Descriptive**: Name should clearly indicate the affected domain/module

### Naming Patterns

**Domain-Based Scopes:**
Use when the change affects a specific domain or bounded context:
- `auth`: Authentication and authorization
- `billing`: Payment and subscription logic
- `dashboard`: Dashboard UI and logic

**Module-Based Scopes:**
Use when the change affects a specific module or component:
- `api-client`: API client library
- `user-form`: User form component
- `email-service`: Email service module

**Feature-Based Scopes:**
Use when the change is feature-specific:
- `search`: Search functionality
- `notifications`: Notification system
- `export`: Export functionality

### Anti-Patterns

**Avoid These:**
- ❌ Generic names: `misc`, `other`, `utils`, `common`, `stuff`
- ❌ Action verbs: `adding`, `fixing`, `updating`
- ❌ File extensions: `ts`, `md`, `json`
- ❌ File paths: `src/components/UserForm`
- ❌ Overly specific: `button-click-handler-in-sidebar`
- ❌ Camel/Pascal case: `UserProfile`, `apiClient`
- ❌ Snake case: `user_profile`, `api_client`
- ❌ Spaces: `user profile`

## Approved Scopes by Commit Type

> **Key Distinction:** The *Type* (Tier 1/2) is the intent of the change; the *Scope* (Tier 3) is the repo-specific module/domain. Organize by **Type** first, then list valid **Scopes** under each.

### Type: `agent` (Extended)

AI agent instructions, skills, and configurations.

> **Scope Granularity Principle:** Scopes are artifact *categories*, not specific instances. Use `skill` not `pdf` or `diataxis`. The specific item name belongs in the commit subject.

| Scope          | Description                                 | File Patterns                             |
| -------------- | ------------------------------------------- | ----------------------------------------- |
| `skill`        | Agent skill definitions and implementations | `skills/*/SKILL.md`, `skills/*/scripts/*` |
| `instruction`  | Standard AI agent custom instructions       | `**/AGENTS.md`                            |
| `[add-others]` | [Description]                               | [Patterns]                                |

### Type: `copilot` (Extended)

GitHub Copilot specific assets (prompts, instructions, agents, mcp).

| Scope          | Description                           | File Patterns                    |
| -------------- | ------------------------------------- | -------------------------------- |
| `instruction`  | Repository-level Copilot instructions | `instructions/*.instructions.md` |
| `custom-agent` | Custom agent definitions              | `*.agent.md`                     |
| `prompt`       | Copilot prompt files                  | `*.prompt.md`                    |
| `memory`       | Knowledge graph memory systems        | `memory.json`                    |
| `mcp`          | MCP server configuration              | `.vscode/mcp.json`               |
| `[add-others]` | [Description]                         | [Patterns]                       |

### Type: `docs` (Universal)

Documentation changes.

| Scope          | Description                        | File Patterns                       |
| -------------- | ---------------------------------- | ----------------------------------- |
| `issue`        | Issue documentation and tracking   | `.issues/*`                    |
| `changelog`    | Changelog files                    | `.docs/changelogs/*`                |
| `constitution` | Scope constitution governance docs | `.github/git-scope-constitution.md` |
| `[add-others]` | [Description]                      | [Patterns]                          |

### Type: `devtool` (Extended)

Developer tools, scripts, and editor configurations.

| Scope          | Description                                   | File Patterns                                 |
| -------------- | --------------------------------------------- | --------------------------------------------- |
| `script`       | Automation scripts (PowerShell, Python, Bash) | `scripts/*`                                   |
| `vscode`       | VS Code workspace settings and tasks          | `.vscode/settings.json`, `.vscode/tasks.json` |
| `[add-others]` | [Description]                                 | [Patterns]                                    |

### Type: `codex` (Extended)

Codex-specific configuration and instructions.

| Scope          | Description         | File Patterns   |
| -------------- | ------------------- | --------------- |
| `config`       | Codex configuration | `.codex/*.json` |
| `instruction`  | Codex instructions  | `.codex/*.md`   |
| `[add-others]` | [Description]       | [Patterns]      |

### Universal Types: `feat`, `fix`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`, `style`, `revert`

For files without extended type mappings, use custom scopes based on the affected module/domain:

| Scope            | Description                          |
| ---------------- | ------------------------------------ |
| `[module-name]`  | Changes affecting a specific module  |
| `[domain-name]`  | Changes affecting a specific domain  |
| `[feature-name]` | Changes affecting a specific feature |

## Scope Selection Guidelines

### Decision Flow

1. **Identify commit type**: Use file path mapping to determine commit type (see `git-atomic-commit` skill)
2. **Consult approved scopes**: Look up approved scopes for that commit type in this constitution
3. **Choose most specific scope**: Select the most specific applicable scope
4. **Fallback to general scope**: If no specific scope fits, use the general scope for that type
5. **Propose new scope**: If no scope fits and change is significant, propose constitutional amendment

### Selection Criteria

**Choose a scope that:**
- ✅ Clearly identifies the affected component/domain
- ✅ Is specific enough to be meaningful
- ✅ Is general enough to be reusable
- ✅ Aligns with codebase module boundaries
- ✅ Matches existing scope naming patterns

**Avoid scopes that:**
- ❌ Are too broad (e.g., `code`, `app`, `project`)
- ❌ Are too narrow (e.g., specific file names or line numbers)
- ❌ Overlap significantly with existing scopes
- ❌ Violate naming conventions
- ❌ Are one-off and unlikely to be reused

### Examples

**Good Scope Selection:**
```
File: skills/pdf/SKILL.md
Type: agent
Scope: skill ✅
Commit: agent(skill): add table extraction to pdf
```

**Bad Scope Selection:**
```
File: skills/pdf/SKILL.md
Type: agent
Scope: pdf ❌ (instance-level — use category `skill`; put "pdf" in the subject)
Scope: agent-stuff ❌ (too vague, doesn't identify the artifact category)
Scope: SKILL ❌ (wrong case)
```

## Amendment Process

### Proposing New Scopes

**When to Propose:**
- New module/domain added to codebase
- Existing scope is too broad and needs splitting
- Consistent pattern of commits without clear scope
- Change doesn't fit any existing scope

**How to Propose:**
1. Extract current scopes: `python3 skills/git-commit-scope-constitution/scripts/extract_scopes.py`
2. Check if similar scope exists
3. Draft scope definition following naming conventions
4. Document rationale for new scope
5. Submit as constitutional amendment

### Amendment Format

```markdown
## Amendment History

### YYYY-MM-DD - Amendment #N

**Changes:**
- [List of changes to approved scopes]

**Rationale:**
[Why these changes were made]

**Migration Notes:**
[How to handle existing commits, if applicable]
```

### Approval Process

**For Individual Contributors:**
1. Propose amendment in pull request or issue
2. Discuss with team
3. Update constitution once approved
4. Commit amendment with `docs(constitution)` type

**For Weekly Refinements:**
1. Extract scopes from past week
2. Identify new scopes or anomalies
3. Update constitution if patterns warrant
4. Document in amendment history

## Scope Lifecycle

### States

1. **Proposed**: Scope suggested but not yet approved
2. **Active**: Scope approved and in use
3. **Deprecated**: Scope marked for removal (use alternative)
4. **Retired**: Scope removed from constitution (exists only in history)

### Lifecycle Management

**Deprecation Criteria:**
- Scope no longer relevant due to codebase changes
- Scope consolidation (merging similar scopes)
- Better scope naming identified

**Deprecation Process:**
1. Mark scope as deprecated in constitution
2. Specify replacement scope
3. Update documentation and examples
4. After grace period (e.g., 1 quarter), retire scope

**Example:**
```markdown
### Type: `ai` - DEPRECATED SCOPES

- ~~`skill-template`~~ → Use `skill-creator` (Deprecated 2026-01-15, Retire 2026-04-15)
```

## Amendment History

### [DATE] - Amendment #1

**Changes:**
- Initial constitution created
- Defined naming conventions
- Documented scopes from git history analysis

**Rationale:**
Establish baseline constitution for commit scope management.

**Migration Notes:**
None - initial version.

---

## Usage Notes

This constitution should be:
- **Version controlled**: Track changes in git
- **Regularly updated**: Weekly or monthly reviews
- **Referenced frequently**: Check before committing
- **Team-owned**: Amendments require consensus
- **Living document**: Evolves with codebase

## Related Skills

- **git-atomic-commit**: Enforces commit type mappings (file path → commit type)
- **git-commit-scope-constitution**: Defines valid scopes within each commit type (this skill)

Together they ensure commits follow: `correct_type(approved_scope): clear_message`
