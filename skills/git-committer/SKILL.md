---
name: git-committer
description: Skill for analyzing git changes, grouping them into logical atomic commits, generating conventional commit messages, and guiding through the commit process. Use when committing changes with proper conventional commit format and maintaining atomic commits.
---

# Git Committer

## Overview

This skill enables crafting clean, atomic git commits with conventional commit messages by analyzing all changes in the repository, intelligently grouping them into logical commits, and guiding the user through the process.

## Workflow

### 1. Analyze All Changes

- Retrieve all changed files (both staged and unstaged)
- If no changes exist, inform the user there's nothing to commit
- Read relevant file diffs to understand the nature of each change

### 2. Group Changes into Logical Commits

Group related changes based on:

- **Feature scope**: Files related to the same feature/module
- **Change type**: Separate refactors from features from fixes
- **Domain boundaries**: Respect module/bounded context boundaries
- **Dependencies**: Ensure commits can be applied sequentially without breaking the build

Create a todo list tracking each planned commit.

### 3. Generate Conventional Commit Messages

For each group, generate a commit message following **Conventional Commits** format:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

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

**Project-Specific Types:**

- `docs(changelog)`: Changes to changelog files
- `devtool(script)`: Changes to PowerShell or helper scripts (e.g., `scripts/*.ps1`)
- `copilot(custom-agent)`: Modifications to custom agent definitions (files ending with `.agent.md`)
- `copilot(prompt)`: Updates to specialized prompts for GitHub Copilot (files ending with `.prompt.md`)
- `copilot(memory)`: Updates to the knowledge graph or memory systems (e.g., `memory.json`)
- `copilot(instruction)`: Changes to `.instructions.md` files or `copilot-instructions.md` (repository-level instructions)

**Rules:**

- Subject: imperative mood, lowercase, no period, max 50 chars
- Body: explain *what* and *why*, wrap at 72 chars
- Scope: module/feature name (optional but recommended)

### 4. Interactive Review & Commit Loop

For each planned commit:

1. Present the commit message and list of files to be included
2. **Wait for user approval** before proceeding
3. On approval: stage only the files for this commit, execute the commit
4. On rejection: ask for feedback and regenerate the message
5. Mark the commit as completed and move to the next

### 5. Completion

After all commits are done, show a summary of all commits created.

## Constraints

- **Never commit without explicit user approval**
- **Never discard or reset user's changes**
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

1. feat(quiz): add question bank entity and repository
   Files: src/Core/Domain/Quiz/QuestionBank.cs, src/Infrastructure/Persistence/QuizRepository.cs

2. test(quiz): add unit tests for question bank
   Files: tests/Core.Tests/Quiz/QuestionBankTests.cs

3. docs(quiz): update API documentation for quiz module
   Files: docs/api/quiz.md

Ready to proceed with commit #1? (yes/no/edit)
```

## Error Handling

- If a commit fails, show the error and ask how to proceed
- If conflicts arise, guide the user to resolve them
- Always provide a way to abort and restore original staging state
