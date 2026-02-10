---
name: git-atomic-commit
description: Skill for analyzing git changes, grouping them into logical atomic commits, generating conventional commit messages, and guiding through the commit process. Use when committing changes with proper conventional commit format and maintaining atomic commits.
metadata: 
   version: 1.1.1
   author: arisng
---

# Git Atomic Commit

## Overview

This skill enables crafting clean, atomic git commits with conventional commit messages by analyzing all changes in the repository, intelligently grouping them into logical commits, and guiding the user through the process.

## ⚠️ Critical: Project-Specific Types Are Mandatory

**DO NOT default to general conventional commit types.** This project uses specialized commit types that must be applied based on file paths and change nature. Always use the project-specific mappings below - they override general conventional commit guidelines.

## File Path to Commit Type Mapping

**MANDATORY STEP: Before any grouping or planning, assign a commit type to EACH changed file individually using this mapping. Files with different commit types MUST be in separate commits - this is non-negotiable for atomicity.**

| File Path Pattern       | Required Commit Type    | Rationale                                    |
| ----------------------- | ----------------------- | -------------------------------------------- |
| `.docs/issues/*`        | `docs(issue)`           | Issue documentation and tracking             |
| `.docs/changelogs/*`    | `docs(changelog)`       | Changelog files                              |
| `instructions/*.md`     | `copilot(instruction)`  | Repository-level Copilot instructions        |
| `skills/*`              | `ai(skill)`             | Claude skill definitions and implementations |
| `scripts/*.ps1`         | `devtool(script)`       | PowerShell helper scripts                    |
| `*.agent.md`            | `copilot(custom-agent)` | Custom agent definitions                     |
| `**/AGENTS.md`          | `ai(instruction)`       | Standard AI agent custom instructions        |
| `*.prompt.md`           | `copilot(prompt)`       | Copilot prompt files                         |
| `memory.json`           | `copilot(memory)`       | Knowledge graph memory systems               |
| `.codex/*`              | `codex`                 | Codex-specific configuration and instructions|
| `.vscode/mcp.json`      | `copilot(mcp)`          | MCP server configuration for Copilot         |
| `.vscode/settings.json` | `devtool(vscode)`       | VS Code workspace settings                   |
| `.vscode/tasks.json`    | `devtool(vscode)`       | VS Code workspace task configurations        |

**Critical Rules:**
- **Different commit types = Different commits** - Even related files must be separated if they have different types
- **No exceptions** - Atomicity requires type separation
- **Check mapping first** - Assign types to individual files before considering relationships

**Common Mistakes to Avoid:**

- ❌ `feat(instructions)` → ✅ `copilot(instruction)`
- ❌ `feat(skill)` → ✅ `ai(skill)`  
- ❌ `chore(issue)` → ✅ `docs(issue)`
- ❌ `docs` (no scope) → ✅ `docs(issue)` or `docs(changelog)`
- ❌ `feat(codex)` → ✅ `codex`
- ❌ `copilot(agent-config)` → ✅ `ai(instruction)`
- ❌ `docs(agents)` → ✅ `ai(instruction)`
- ❌ Mixing `copilot(mcp)` + `devtool(vscode)` in one commit → ✅ Separate commits
- ❌ Grouping files with different types → ✅ One type per commit

## Workflow

### 1. Analyze All Changes

- Retrieve all changed files (both staged and unstaged)
- If no changes exist, inform the user there's nothing to commit
- Read relevant file diffs to understand the nature of each change

### 2. Assign Commit Types to Individual Files

**MANDATORY: For each changed file, determine its exact commit type using the mapping table above. Document this assignment - it drives the entire commit strategy.**

### 3. Select Appropriate Scopes

**MANDATORY: After commit types are assigned, select appropriate scopes for each commit.**

**Scope Selection Process:**
1. Check if repository has a scope constitution at `.github/scope-constitution.md`
2. If constitution exists, use it to select approved scopes for each commit type
3. If no constitution exists, use the `git-commit-scope-constitution` skill to:
   - Analyze repository structure (folders, modules, domains)
   - Extract historical scopes from git history
   - Propose appropriate scopes based on project structure
4. Ensure scope names follow conventions:
   - Kebab-case, lowercase, singular form
   - Domain/module/feature-based (not file-path-based)
   - Concise and descriptive (1-3 words)

**Scope Cross-Reference:**
- Commit type determines WHAT kind of change (via file path mapping)
- Scope specifies WHERE in the project (via repository structure)
- Together they form: `type(scope): subject`

**Example:**
```
File: skills/pdf/SKILL.md
  → Type: ai(skill)        [from file path mapping]
  → Scope: pdf             [from .github/scope-constitution.md]
  → Result: ai(skill): add table extraction
```

### 4. Pre-Commit Verification Checklist

**MANDATORY: Complete this checklist before presenting any commit plan:**

- [ ] **Type Mapping**: Every file path mapped to correct project-specific type using the table above
- [ ] **Scope Selection**: Every commit has an appropriate scope (check constitution if available)
- [ ] **No Generic Types**: No commits using `feat`, `fix`, `docs` without project-specific scope
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

**Message Format Rules:**
- **Subject**: Imperative mood, lowercase, no period, ≤50 chars
- **Body**: Explain *what* and *why*, wrap at 72 chars
- **Scope**: Module/feature name (required for project-specific types)

**Available Commit Types:**

| Type                    | Scope         | Use Case                                                       |
| ----------------------- | ------------- | -------------------------------------------------------------- |
| `docs(issue)`           | `issue`       | Issue documentation (`.docs/issues/*`)                         |
| `docs(changelog)`       | `changelog`   | Changelog files (`.docs/changelogs/*`)                         |
| `copilot(instruction)`  | `instruction` | `.instructions.md` files                                       |
| `ai(skill)`             | `skill`       | Claude skill implementations (`skills/*`)                      |
| `copilot(custom-agent)` | `agent`       | Custom agent definitions (`*.agent.md`)                        |
| `ai(instruction)`       | `instruction` | Standard AI agent custom instructions (`AGENTS.md`)            |
| `copilot(prompt)`       | `prompt`      | Prompt files (`*.prompt.md`)                                   |
| `copilot(memory)`       | `memory`      | Memory systems (`memory.json`)                                 |
| `copilot(mcp)`          | `mcp`         | MCP config (`.vscode/mcp.json`)                                |
| `codex`                 | custom        | Codex-specific configuration and instructions (`.codex/*`)     |
| `devtool(script)`       | `script`      | PowerShell or bash or python scripts (`*.ps1`, `*.sh`, `*.py`) |
| `devtool(vscode)`       | `vscode`      | VS Code config (`.vscode/settings.json`, `.vscode/tasks.json`) |
| `feat`                  | custom        | New features (if no project-specific type)                     |
| `fix`                   | custom        | Bug fixes (if no project-specific type)                        |
| `refactor`              | custom        | Code restructuring                                             |
| `test`                  | custom        | Test additions/changes                                         |
| `chore`                 | custom        | Build, tooling, dependencies                                   |

**CRITICAL:** Use project-specific types (e.g., `ai(skill)`) instead of generic types (`feat`, `fix`) when a mapping exists.

**Scope Selection:**
- Prefer scopes from `.github/scope-constitution.md` if available
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
- **MANDATORY: Use approved scopes from constitution** - Check `.github/scope-constitution.md` if available
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
  - Repository lacks `.github/scope-constitution.md`
  - Need to add new scopes
  - Weekly constitution refinement
  - Scope selection is unclear

**Constitution Location:** `.github/scope-constitution.md`
**Scopes Inventory:** `.github/scopes-inventory.md`

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

1. ai(skill): add vscode-docs skill for researching VS Code docs
   Files: skills/vscode-docs/SKILL.md, skills/vscode-docs/assets/toc.md

2. copilot(instruction): update orchestration guidelines for domain-specific skills
   Files: instructions/claude-skills.instructions.md

3. docs(issues): remove deprecated copilot-skills design decision issue
   Files: .docs/issues/251210_copilot-skills.md

✅ Pre-commit verification: All file paths mapped to correct project-specific types
Ready to proceed with commit #1? (yes/no/edit)
```

## Error Handling

- If a commit fails, show the error and ask how to proceed
- If conflicts arise, guide the user to resolve them
- Always provide a way to abort and restore original staging state
- **If commit types are incorrect, stop and revise the entire plan**
- **If validation fails due to type mixing, immediately revise the grouping**
