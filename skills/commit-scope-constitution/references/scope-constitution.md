# Commit Scope Constitution

Last Updated: [DATE]

## Purpose

This constitution defines the approved scopes for atomic commits in this repository, ensuring consistency and clarity in commit history. It serves as the authoritative reference for:

- Valid scope names organized by commit type
- Scope definitions and boundaries
- Naming conventions and patterns
- Guidelines for choosing appropriate scopes

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

### `ai(skill)`

Scopes for agent skill definitions and implementations (files in `skills/` directory):

- `skill-creator`: Skill creation and templates
- `git-atomic-commit`: Git atomic commit skill
- `diataxis`: Diataxis documentation framework skill
- `instruction-creator`: Instruction creation skill
- `mermaid-creator`: Mermaid diagram generation skill
- `pdf`: PDF manipulation skill
- `vn-payroll`: Vietnam payroll calculation skill
- `[add-other-skills]`: [Description]

### `copilot(instruction)`

Scopes for repository-level Copilot instructions (`.instructions.md` files):

- `instruction`: General instruction updates
- `meta`: Meta-instructions about instructions
- `agent-eval`: Agent evaluation instructions
- `skill-eval`: Skill evaluation instructions
- `powershell`: PowerShell scripting instructions
- `[add-other-instructions]`: [Description]

### `copilot(custom-agent)`

Scopes for custom agent definitions (`*.agent.md` files):

- `agent`: General agent definition updates
- `meta`: Meta-agent for creating agents
- `ralph`: Ralph orchestration agent
- `git-committer`: Git commit agent
- `[add-other-agents]`: [Description]

### `copilot(prompt)`

Scopes for Copilot prompt files (`*.prompt.md`):

- `prompt`: General prompt updates
- `atomic-commit`: Atomic commit prompt
- `changelog`: Changelog generation prompt
- `ralph`: Ralph session prompt
- `[add-other-prompts]`: [Description]

### `copilot(memory)`

Scopes for knowledge graph memory systems (`memory.json`):

- `memory`: General memory updates
- `knowledge-graph`: Knowledge graph structure
- `[add-other-memory-scopes]`: [Description]

### `copilot(mcp)`

Scopes for MCP server configuration (`.vscode/mcp.json`):

- `mcp`: MCP server configuration
- `[add-other-mcp-scopes]`: [Description]

### `docs(issue)`

Scopes for issue documentation (`.docs/issues/*`):

- `issue`: General issue documentation
- `bug`: Bug reports and fixes
- `feature`: Feature requests and designs
- `rfc`: Request for comments
- `adr`: Architecture decision records
- `retrospective`: Retrospective documents
- `[add-other-issue-types]`: [Description]

### `docs(changelog)`

Scopes for changelog files (`.docs/changelogs/*`):

- `changelog`: General changelog updates
- `weekly`: Weekly changelog entries
- `monthly`: Monthly changelog summaries
- `[add-other-changelog-scopes]`: [Description]

### `devtool(script)`

Scopes for PowerShell/Bash/Python scripts (`scripts/`):

- `script`: General script updates
- `publish`: Publishing scripts
- `issues`: Issue management scripts
- `changelog`: Changelog generation scripts
- `workspace`: Workspace utility scripts
- `[add-other-script-scopes]`: [Description]

### `devtool(vscode)`

Scopes for VS Code configuration (`.vscode/*`):

- `vscode`: General VS Code settings
- `settings`: Workspace settings
- `tasks`: Task configurations
- `launch`: Debug configurations
- `[add-other-vscode-scopes]`: [Description]

### `codex`

Scopes for Codex-specific configuration and instructions (`.codex/*`):

- `config`: Codex configuration
- `instruction`: Codex instructions
- `[add-other-codex-scopes]`: [Description]

### `ai(instruction)`

Scopes for standard AI agent custom instructions (`AGENTS.md` files):

- `instruction`: General AI instruction updates
- `[add-other-ai-instruction-scopes]`: [Description]

### `feat`, `fix`, `refactor`, `test`, `chore`

For files without project-specific type mappings, use custom scopes based on the affected module/domain:

- `[module-name]`: Changes affecting a specific module
- `[domain-name]`: Changes affecting a specific domain
- `[feature-name]`: Changes affecting a specific feature

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
Type: ai(skill)
Scope: pdf ✅
Commit: ai(skill): add table extraction to PDF processing
```

**Bad Scope Selection:**
```
File: skills/pdf/SKILL.md
Type: ai(skill)
Scope: document ❌ (too generic)
Scope: pdf-skill-markdown-file ❌ (too specific)
Scope: PDF ❌ (wrong case)
```

## Amendment Process

### Proposing New Scopes

**When to Propose:**
- New module/domain added to codebase
- Existing scope is too broad and needs splitting
- Consistent pattern of commits without clear scope
- Change doesn't fit any existing scope

**How to Propose:**
1. Extract current scopes: `python3 skills/commit-scope-constitution/scripts/extract_scopes.py`
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
### `ai(skill)` - DEPRECATED SCOPES

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
- **commit-scope-constitution**: Defines valid scopes within each commit type (this skill)

Together they ensure commits follow: `correct_type(approved_scope): clear_message`
