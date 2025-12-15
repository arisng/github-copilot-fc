---
name: git-committer
description: Skill for analyzing git changes, grouping them into logical atomic commits, generating conventional commit messages, and guiding through the commit process. Use when committing changes with proper conventional commit format and maintaining atomic commits.
---

# Git Committer

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
| `skills/*`              | `copilot(skill)`        | Claude skill definitions and implementations |
| `scripts/*.ps1`         | `devtool(script)`       | PowerShell helper scripts                    |
| `*.agent.md`            | `copilot(custom-agent)` | Custom agent definitions                     |
| `*.prompt.md`           | `copilot(prompt)`       | Copilot prompt files                         |
| `memory.json`           | `copilot(memory)`       | Knowledge graph memory systems               |
| `.vscode/mcp.json`      | `copilot(mcp)`          | MCP server configuration for Copilot         |
| `.vscode/settings.json` | `devtool(vscode)`       | VS Code workspace settings                   |
| `.vscode/tasks.json`    | `devtool(vscode)`       | VS Code workspace task configurations        |

**Critical Rules:**
- **Different commit types = Different commits** - Even related files must be separated if they have different types
- **No exceptions** - Atomicity requires type separation
- **Check mapping first** - Assign types to individual files before considering relationships

**Common Mistakes to Avoid:**

- ❌ `feat(instructions)` → ✅ `copilot(instruction)`
- ❌ `feat(skill)` → ✅ `copilot(skill)`  
- ❌ `chore(issue)` → ✅ `docs(issue)`
- ❌ `docs` (no scope) → ✅ `docs(issue)` or `docs(changelog)`
- ❌ Mixing `copilot(mcp)` + `devtool(vscode)` in one commit → ✅ Separate commits
- ❌ Grouping files with different types → ✅ One type per commit

## Workflow

### 1. Analyze All Changes

- Retrieve all changed files (both staged and unstaged)
- If no changes exist, inform the user there's nothing to commit
- Read relevant file diffs to understand the nature of each change

### 2. Assign Commit Types to Individual Files

**MANDATORY: For each changed file, determine its exact commit type using the mapping table above. Document this assignment - it drives the entire commit strategy.**

### 3. Pre-Commit Verification Checklist

**MANDATORY: Complete this checklist before presenting any commit plan:**

- [ ] **Type Mapping**: Every file path mapped to correct project-specific type using the table above
- [ ] **No Generic Types**: No commits using `feat`, `fix`, `docs` without project-specific scope
- [ ] **Atomic Grouping**: Changes grouped by logical feature/module boundaries
- [ ] **Dependency Order**: Commit order maintains buildable state
- [ ] **Scope Accuracy**: Commit scopes match actual module/feature names

**If any checklist item fails, revise the plan before proceeding.**

### 4. Group Changes into Logical Commits

**CRITICAL CONSTRAINT: Files with different commit types CANNOT be grouped together - they must be in separate commits.**

Group remaining related changes based on:
- **Same commit type**: Only group files that share the same required commit type
- **Feature scope**: Files related to the same feature/module (within same type)
- **Change type**: Separate refactors from features from fixes (within same type)
- **Domain boundaries**: Respect module/bounded context boundaries (within same type)
- **Dependencies**: Ensure commits can be applied sequentially without breaking the build

**If grouping would mix commit types, split into separate commits immediately.**

Create a todo list tracking each planned commit with their assigned types.

### 5. Validate Commit Plan

**MANDATORY VALIDATION: Review each planned commit to ensure:**
- All files in a commit share the same commit type
- No commit mixes different types
- Each commit represents one logical change within its type
- Commits can be applied in sequence without conflicts

**If validation fails, revise the grouping immediately.**

### 6. Generate Conventional Commit Messages

For each group, generate a commit message following **Conventional Commits** format:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Generic Types (use only when no project-specific type applies):**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, whitespace (no code change)
- `refactor`: Code change that neither fixes nor adds
- `perf`: Performance improvement
- `test`: Adding/updating tests
- `chore`: Build, CI, tooling, dependencies
- `build`: Build system or external dependencies
- `ci`: CI configuration

**Project-Specific Types (MANDATORY - use these instead of general types):**

- `docs(issue)`: Changes to issues documentation (e.g., `.docs/issues/` files)
- `docs(changelog)`: Changes to changelog files (e.g., `.docs/changelogs/` files)
- `devtool(script)`: Changes to PowerShell or helper scripts (e.g., `scripts/*.ps1`)
- `copilot(custom-agent)`: Modifications to custom agent definitions (files ending with `.agent.md`)
- `copilot(prompt)`: Updates to specialized prompts for GitHub Copilot (files ending with `.prompt.md`)
- `copilot(memory)`: Updates to the knowledge graph or memory systems (e.g., `memory.json`)
- `copilot(instruction)`: Changes to `.instructions.md` files or `copilot-instructions.md` (repository-level instructions)
- `copilot(skill)`: Changes to Claude Skill definitions, implementations, and packaging (e.g., files under `skills/` directory)
- `copilot(mcp)`: Changes to MCP configuration files (e.g., `mcp.json`)

- Subject: imperative mood, lowercase, no period, max 50 chars
- Body: explain *what* and *why*, wrap at 72 chars
- Scope: module/feature name (optional but recommended)

### 7. Interactive Review & Commit Loop

For each planned commit:

1. Present the commit message and list of files to be included
2. **Wait for user approval** before proceeding
3. On approval: stage only the files for this commit, execute the commit
4. On rejection: ask for feedback and regenerate the message
5. Mark the commit as completed and move to the next

### 8. Completion

After all commits are done, show a summary of all commits created.

## Constraints

- **Never commit without explicit user approval**
- **Never discard or reset user's changes**
- **MANDATORY: Use project-specific commit types - no exceptions**
- **MANDATORY: Complete pre-commit verification checklist**
- **MANDATORY: Different commit types require separate commits** - No exceptions for atomicity
- Keep commits atomic: one logical change per commit
- Ensure commit order maintains a buildable state
- Use English for all commit messages unless instructed otherwise

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

1. copilot(skill): add vscode-docs skill for researching VS Code docs
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
