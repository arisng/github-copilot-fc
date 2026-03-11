---
name: git-atomic-commit
description: 'Analyze git changes, group into atomic commits, generate conventional commit messages with proper type(scope) format. Use when committing changes, grouping staged/unstaged files, or generating commit messages. Enforces universal commit types + repo-specific scopes from .github/git-scope-constitution.md.'
metadata: 
   version: 2.1.0
   author: arisng
---

# Git Atomic Commit

## Overview

This skill enables crafting clean, atomic git commits with conventional commit messages by analyzing all changes in the repository, intelligently grouping them into logical commits, and guiding the user through the process.

## ⚠️ Critical: Distinguish Commit Type vs. Commit Scope

Commit messages follow the pattern `type(scope): subject`. **Type** and **Scope** are governed by a three-tier hierarchy:

| Tier | What it governs | Defined by | Stability |
|------|----------------|------------|-----------|
| **1. Universal** | Standard Conventional Commits types | Industry convention | Fixed across all repos |
| **2. Author Preferences** | Extended types + default file-path mappings | Skill author (opinionated) | Portable across repos; users may override |
| **3. Workspace-Specific** | Scopes, additional types, file-path overrides | `.github/git-scope-constitution.md` per repo | Unique per repository |

**Commit Types** = Tier 1 + Tier 2. Types represent the *intent* of the change.
**Commit Scopes** = Tier 3. Scopes represent the *domain, module, or location* of the change, tightly coupled to the repository's context.

### Tier 1: Universal Commit Types

Standard Conventional Commits — these are immutable and apply everywhere:

| Type | Use Case |
|------|----------|
| `feat` | New features |
| `fix` | Bug fixes |
| `docs` | Documentation changes |
| `style` | Formatting, whitespace, missing semi colons |
| `refactor` | Code restructuring (no behavior change) |
| `perf` | Performance improvements |
| `test` | Adding or updating tests |
| `build` | Build system or external dependencies |
| `ci` | CI configuration files and scripts |
| `chore` | Maintenance that doesn't modify src or test files |
| `revert` | Reverts a previous commit |

### Tier 2: Author Preferences (Opinionated Extended Types)

> **Note for other users:** These extended types reflect the author's (`arisng`) personal conventions for AI/DevTool-heavy repositories. You are free to modify, remove, or add your own extended types to suit your workflow.

Extended types take precedence over universal types when the file matches a known pattern:

| Extended Type | Replaces | Domain | Typical File Patterns |
|---------------|----------|--------|-----------------------|
| `agent` | `feat`, `chore` | AI agent assets (skills, instructions) | `skills/*`, `**/AGENTS.md` |
| `copilot` | `feat`, `chore` | GitHub Copilot assets | `*.agent.md`, `*.prompt.md`, `instructions/*.md`, `.vscode/mcp.json`, `memory.json` |
| `devtool` | `chore`, `build` | Developer tooling & editor config | `scripts/*`, `.vscode/settings.json`, `.vscode/tasks.json` |
| `codex` | `chore` | OpenAI Codex assets | `.codex/*` |

**Rule:** When a file matches an extended type pattern, always use the extended type instead of the universal one. Fall back to universal types for everything else.

### Tier 3: Workspace-Specific (Scopes + Overrides)

Scopes are entirely repo-specific and governed by `.github/git-scope-constitution.md`. The file-path-to-scope mapping below is an **example** from the author's workspace. Each repository should define its own via the `git-commit-scope-constitution` skill.

**Scope Granularity Principle:** Scopes represent the **artifact category**, not a specific instance. When scanning `git log --oneline`, `type(category)` tells you *what kind of thing* changed; the commit subject tells you *which one*.

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

## File Assignment Rules

**MANDATORY STEP: Before any grouping or planning, assign a Commit Type and a Commit Scope to EACH changed file individually. Files with different types or unrelated scopes MUST be in separate commits — this is non-negotiable for atomicity.**

**Critical Rules:**
- **Different commit types = Different commits** — Even related files must be separated if they have different types.
- **Different scopes = Usually different commits** — Keep commits atomic by scope unless the change is a cross-cutting concern.
- **Extended type wins** — If a file matches a Tier 2 pattern, never use a Tier 1 universal type.
- **Check mapping first** — Assign types and scopes to individual files before considering relationships.

**Common Mistakes to Avoid:**

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

## Workflow

### 1. Analyze All Changes

- Retrieve all changed files (both staged and unstaged)
- If no changes exist, inform the user there's nothing to commit
- Read relevant file diffs to understand the nature of each change

### 2. Assign Commit Types and Scopes to Individual Files

**MANDATORY: For each changed file, determine its exact commit type AND scope using the mapping table above. Document this assignment - it drives the entire commit strategy.**

### 3. Validate Scope Selection

**MANDATORY: After types and scopes are assigned, validate scope choices.**

**Scope Validation Process:**
1. Check if repository has a scope constitution at `.github/git-scope-constitution.md`
2. If constitution exists, verify chosen scopes are approved for their commit type
3. If no constitution exists, use the `git-commit-scope-constitution` skill to:
   - Analyze repository structure (folders, modules, domains)
   - Extract historical scopes from git history
   - Propose appropriate scopes based on project structure
4. Ensure scope names follow conventions:
   - Kebab-case, lowercase, singular form
   - Domain/module/feature-based (not file-path-based)
   - Concise and descriptive (1-3 words)

**Scope Cross-Reference:**
- Commit type (Tier 1/2) determines WHAT kind of change
- Scope (Tier 3) specifies WHERE in the project
- Together they form: `type(scope): subject`

**Example:**
```text
File: skills/pdf/SKILL.md
  → Type: agent            [Tier 2 extended type for AI agent assets]
  → Scope: skill           [Tier 3 category-level scope]
  → Result: agent(skill): add table extraction to pdf
```

### 4. Pre-Commit Verification Checklist

**MANDATORY: Complete this checklist before presenting any commit plan:**

- [ ] **Type Mapping**: Every file path mapped to correct type (Tier 2 extended type when applicable, otherwise Tier 1 universal)
- [ ] **Scope Selection**: Every commit has an appropriate scope from the constitution (Tier 3)
- [ ] **No Generic Types**: No commits using Tier 1 types (`feat`, `fix`, `chore`) when a Tier 2 extended type applies
- [ ] **Atomic Grouping**: Changes grouped by logical feature/module boundaries
- [ ] **Dependency Order**: Commit order maintains buildable state
- [ ] **Scope Accuracy**: Commit scopes match actual module/feature names

**If any checklist item fails, revise the plan before proceeding.**

### 5. Group Changes into Logical Commits

**CRITICAL CONSTRAINT: Files with different commit types CANNOT be grouped together - they must be in separate commits.**

Group remaining related changes based on:
- **Same commit type**: Only group files that share the same required commit type
- **Feature scope**: Files related to the same feature/module (within same type)
- **Change type**: Separate refactors from features from fixes (within same type)
- **Domain boundaries**: Respect module/bounded context boundaries (within same type)
- **Dependencies**: Ensure commits can be applied sequentially without breaking the build

**If grouping would mix commit types, split into separate commits immediately.**

Create a todo list tracking each planned commit with their assigned types.

### 6. Validate Commit Plan

**MANDATORY VALIDATION: Review each planned commit to ensure:**
- All files in a commit share the same commit type
- No commit mixes different types
- Each commit represents one logical change within its type
- Commits can be applied in sequence without conflicts
- Scopes are valid per the constitution (if available)

**If validation fails, revise the grouping immediately.**

### 7. Generate Conventional Commit Messages

For each group, generate a commit message following **Conventional Commits** format:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**MANDATORY: Conventional Commit Syntax**
Every commit MUST follow this exact structure:
- `<type>(<scope>): <subject>`
- Never use multiple scopes like `<type>(<scope>)(<scope_2>)` or `<type>(<scope1,scope2>)`. Use ONE primary scope that best represents the change.
- **Secondary Areas**: If the change involves a second area (scope_2), mention it explicitly inside the `<subject>` part (e.g., `<type>(primary-scope): [scope2] actual message` or `<type>(primary-scope): fix scope2 bug`).

**Message Format Rules:**
- **Type**: Must be a Tier 1 universal type or Tier 2 extended type (see tables above).
- **Scope**: Must be a single, concise module or feature name (Tier 3).
- **Subject**: Imperative mood, lowercase, no period, ≤50 chars
- **Body**: Explain *what* and *why*, wrap at 72 chars

**Type Selection:** Refer to the Tier 1 and Tier 2 tables in the "Distinguish Commit Type vs. Commit Scope" section above.

**CRITICAL:** Use Tier 2 extended types (e.g., `agent`, `copilot`) instead of Tier 1 universal types (`feat`, `chore`) when the file matches an extended type pattern. Always pair the Type with a valid Scope from the repository's constitution.

**Scope Selection:**
- Prefer scopes from `.github/git-scope-constitution.md` if available
- Ensure scope aligns with repository structure (module, domain, feature)
- Follow kebab-case, lowercase naming conventions
- Use `git-commit-scope-constitution` skill if unclear

### 8. Commit Message Quality Standards

**KEY:** Provide sufficient detail for accurate changelog generation and knowledge graph tracking. Vague messages lead to misleading summaries.

**Quality Requirements:**
- **Deletions:** List specific items removed (files, features, agents, etc.)
- **Bulk changes:** Specify each major component affected
- **Refactors:** Detail what was restructured and why
- **Additions:** Describe new capabilities or features clearly

**Good Example (Specific):**
```text
copilot(custom-agent): remove unused agents - conductor, context7, implementation, microsoft-docs

Removes four specialized agents that were redundant.
Streamlines agent portfolio and reduces maintenance overhead.
```

**Bad Example (Vague):**
```text
refactor: update agent definitions
```

### 9. Execution & Review

**Interactive Mode (User-Guided):**
1. Present the complete commit plan with all details.
2. **Wait for explicit user approval** before proceeding.
3. Execute commits sequentially:
   - Stage only files for the current commit
   - Execute commit
   - Confirm success
4. Allow user to edit or reject commits.

**Autonomous Mode (Subagent):**
1. Analyze changes and generate the complete commit plan.
2. **Validate internally** against all constraints.
3. Execute all planned commits automatically without user prompts.
4. Return a comprehensive summary of all created commits.

**Safety:**
- Never discard or reset changes without consent.
- If validation fails, stop and report the issue.

### 10. Completion

After all commits are done, show a summary of all commits created.

## Constraints

- **Never commit without explicit user approval** (unless operating in authorized autonomous mode)
- **Never discard or reset user's changes**
- **MANDATORY: Use project-specific commit types - no exceptions**
- **MANDATORY: Complete pre-commit verification checklist**
- **MANDATORY: Different commit types require separate commits** - No exceptions for atomicity
- **MANDATORY: Use approved scopes from constitution** - Check `.github/git-scope-constitution.md` if available
- Keep commits atomic: one logical change per commit
- Ensure commit order maintains a buildable state
- Use English for all commit messages unless instructed otherwise

## Integration with git-commit-scope-constitution Skill

This skill works in tandem with the `git-commit-scope-constitution` skill to ensure complete commit message consistency:

**Division of Responsibility:**
- **git-atomic-commit** (this skill):
  - Maps file paths to commit types
  - Groups changes into atomic commits
  - Validates commit structure and ordering
  - Executes commits with user approval

- **git-commit-scope-constitution**:
  - Defines valid scopes for each commit type
  - Maintains scope naming conventions
  - Aligns scopes with repository structure
  - Provides scope selection guidelines

**Workflow Integration:**
```
Changed Files
    ↓
git-atomic-commit: Map files → Commit types
    ↓
git-commit-scope-constitution: Select scopes for each type
    ↓
git-atomic-commit: Generate commit messages
    ↓
Final Commits: type(scope): subject
```

**When to Use Each:**
- Use `git-atomic-commit` for every commit workflow
- Use `git-commit-scope-constitution` when:
  - Repository lacks `.github/git-scope-constitution.md`
  - Need to add new scopes
  - Weekly constitution refinement
  - Scope selection is unclear

**Constitution Location:** `.github/git-scope-constitution.md`
**Scopes Inventory:** `.github/git-scope-inventory.md`

## Commands Reference

```powershell
# View all changed files (staged + unstaged)
git status --short

# View diff for unstaged changes
git diff -- <filepath>

# View diff for staged changes
git diff --cached -- <filepath>

# Stage specific files
git add <filepath>

# Unstage specific files
git reset HEAD -- <filepath>

# Commit with message
git commit -m "<message>"

# Commit with multi-line message
git commit -m "<subject>" -m "<body>"
```

## Example Output

```text
📦 Commit Plan (3 commits)

1. agent(skill): add vscode-docs skill for researching VS Code docs
   Files: skills/vscode-docs/SKILL.md, skills/vscode-docs/assets/toc.md

2. copilot(instruction): update claude-skills orchestration guidelines
   Files: instructions/claude-skills.instructions.md

3. docs(issue): remove deprecated copilot-skills design decision issue
   Files: .issues/251210_copilot-skills.md

✅ Pre-commit verification: All file paths mapped to correct project-specific types
Ready to proceed with commit #1? (yes/no/edit)
```

## Error Handling

- If a commit fails, show the error and ask how to proceed
- If conflicts arise, guide the user to resolve them
- Always provide a way to abort and restore original staging state
- **If commit types are incorrect, stop and revise the entire plan**
- **If validation fails due to type mixing, immediately revise the grouping**
