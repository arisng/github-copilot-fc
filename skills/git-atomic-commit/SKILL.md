---
name: git-atomic-commit
description: 'Analyze git changes, group into atomic commits, generate conventional commit messages with proper type(scope) format. Use when committing changes, grouping staged/unstaged files, or generating commit messages. Enforces universal commit types + repo-specific scopes from .github/git-scope-constitution.md, plain-English messages, and the repository''s established CONTEXT.md vocabulary. Honors caller-constrained file scopes (e.g. from git-session-atomic-commits): commits only the provided files, never stages out-of-scope worktree changes, and verifies the staged set before every commit.'
metadata: 
   version: 2.3.0
   author: arisng
---

# Git Atomic Commit

## Overview

Craft clean, atomic git commits with conventional commit messages: analyze changes, group them into logical commits, and guide execution. Honors a caller-constrained file scope when provided; otherwise analyzes the full worktree.

## Type vs. Scope (Three-Tier Model)

Messages follow `type(scope): subject`. **Type** = intent of the change; **Scope** = domain/module/location of the change.

| Tier | What it governs | Defined by | Stability |
|------|----------------|------------|-----------|
| **1. Universal** | Standard Conventional Commits types | Industry convention | Fixed across all repos |
| **2. Author Preferences** | Extended types + default file-path mappings | Skill author (opinionated) | Portable; users may override |
| **3. Workspace-Specific** | Scopes, additional types, file-path overrides | `.github/git-scope-constitution.md` per repo | Unique per repository |

### Tier 1: Universal Types (immutable)

| Type | Use Case |
|------|----------|
| `feat` | New features |
| `fix` | Bug fixes |
| `docs` | Documentation changes |
| `style` | Formatting, whitespace, missing semicolons |
| `refactor` | Code restructuring (no behavior change) |
| `perf` | Performance improvements |
| `test` | Adding or updating tests |
| `build` | Build system or external dependencies |
| `ci` | CI configuration files and scripts |
| `chore` | Maintenance that doesn't modify src or test files |
| `revert` | Reverts a previous commit |

### Tier 2: Extended Types (author preferences, win over Tier 1)

`agent` (skills, `**/AGENTS.md`), `copilot` (`*.agent.md`, `*.prompt.md`, `instructions/*.md`, `.vscode/mcp.json`, `memory.json`), `devtool` (`scripts/*`, `.vscode/settings.json`, `.vscode/tasks.json`), `codex` (`.codex/*`).

**Rule:** if a file matches an extended type pattern, always use the extended type. Full table: [references/type-scope-mapping.md](references/type-scope-mapping.md).

### Tier 3: Workspace-Specific Scopes

Repo-specific, governed by `.github/git-scope-constitution.md`. **Scope granularity:** scopes are the *artifact category*, not a specific instance — `type(category)` tells what kind of thing changed; the subject tells *which one*. Example mappings: [references/type-scope-mapping.md](references/type-scope-mapping.md).

## File Assignment Rules

**MANDATORY: Before any grouping, assign a Commit Type AND Scope to EACH changed file individually. Files with different types must be in separate commits.**

- Different commit types = different commits (non-negotiable)
- Different scopes = usually different commits (unless cross-cutting)
- Extended type wins over universal type
- Assign per file before considering relationships

Common mistakes (conflating type/scope, deprecated `ai`, missing scope, type mixing) and the full catalog: [references/type-scope-mapping.md](references/type-scope-mapping.md).

## Workflow

### 0. Honor Caller-Constrained Scope

If a caller (e.g. `git-session-atomic-commits`) passes a constrained file list, that list is the **complete scope** of this run:

- Analyze, group, stage, and commit **only** the provided files.
- Every other worktree change is **out of scope**: do not read its diff, stage it, commit it, or suggest it.
- If the caller states an ignore list, never touch any path on it.
- If staging would include any out-of-scope path, stop and report.

When no constrained list is provided, analyze the full worktree.

### 1. Analyze Changes

- Retrieve all changed files (staged + unstaged); restrict to the constrained list when a scope is active.
- If no changes exist, report there's nothing to commit.
- Read relevant diffs to understand each change.

### 2. Assign Types and Scopes Per File

**MANDATORY:** Determine each file's exact type and scope using the tables above. Document the assignment — it drives the entire plan.

### 3. Validate Scopes

1. If `.github/git-scope-constitution.md` exists, verify every chosen scope is approved for its type.
2. If not, use the `git-commit-scope-constitution` skill to propose scopes.
3. Scope names: kebab-case, lowercase, singular, 1-3 words, domain/module-based.

### 4. Pre-Commit Verification Checklist (MANDATORY)

- [ ] Every file mapped to the correct type (Tier 2 when applicable)
- [ ] Every commit has an approved scope from the constitution
- [ ] No Tier 1 type used when a Tier 2 extended type applies
- [ ] Atomic grouping by feature/module boundaries
- [ ] Commit order maintains a buildable state
- [ ] Scopes match actual module/feature names

If any item fails, revise the plan before proceeding.

### 5. Group into Logical Commits

**CRITICAL: Files with different commit types CANNOT be grouped together.**

Group by: same type → feature scope → change kind (refactor vs feat vs fix) → domain boundaries → dependency order. If grouping would mix types, split immediately. Track planned commits in a todo list.

### 6. Validate Plan

Each planned commit must: share one type, represent one logical change, apply in sequence without conflicts, use valid scopes. If validation fails, revise immediately.

### 7. Generate Commit Messages

Format: `<type>(<scope>): <subject>` — exactly ONE scope; mention secondary areas in the subject.

- **Type**: Tier 1 or Tier 2 (extended wins)
- **Scope**: single, concise, from the constitution
- **Subject**: imperative, lowercase, no period, ≤50 chars
- **Body**: what and why, wrap at 72 chars

Quality standards (plain English, repository vocabulary, durable references) and worked examples: [references/message-quality.md](references/message-quality.md).

### 8. Execute with Verification Gates (MANDATORY)

**Interactive mode:** present the full plan, wait for explicit approval, then commit sequentially.
**Autonomous mode:** validate internally, then execute all planned commits.

Before EACH `git commit`:
- [ ] **Staged set matches this commit's plan exactly**: `git diff --cached --name-only` equals the planned file list — no more, no fewer.
- [ ] **No out-of-scope files staged**: with a constrained scope active, every staged path is on the allowed list.
- [ ] **Mixed-hunk files handled per-hunk**: if a file contains both in-scope and out-of-scope changes, stage only the in-scope hunks with `git add -p`; never `git add` the whole file.
- [ ] **No broad staging**: never `git add .`, `git add -A`, `git add <dir>`, or `git commit -a`/`-am`.
- [ ] **Untracked files handled explicitly**: enumerate them; never sweep them in implicitly.

After EACH commit:
- [ ] **Post-commit check**: `git show --stat --oneline HEAD` contains exactly the intended files; `git status --short` shows no unintended leftovers staged.

If any gate fails: unstage offending paths (`git restore --staged <path>`), re-verify, then proceed. If a commit fails mid-sequence, stop and report — do not continue with remaining commits until the user decides.

### 9. Completion

Show a summary of all commits created.

## Constraints

- Never commit without explicit user approval (unless authorized autonomous mode)
- Never discard or reset user's changes
- **Never stage or commit out-of-scope files when a caller-constrained scope is active**
- Never use broad staging (`git add .` / `-A` / `<dir>`, `git commit -a`); stage mixed-hunk files per-hunk with `git add -p`
- MANDATORY: project-specific commit types; pre-commit checklist; one type per commit; approved scopes; plain-English messages; repository vocabulary; durable references only
- Keep commits atomic; commit order maintains a buildable state
- Repository terminology rules (e.g. `.github/instructions/`, audit scripts) are authoritative

## Integration with git-commit-scope-constitution

- **git-atomic-commit**: maps files → types, groups atomic commits, validates structure/order, executes with approval
- **git-commit-scope-constitution**: defines valid scopes per type, naming conventions, structural alignment

Flow: Changed Files → map types → select scopes → generate messages → commit. Constitution: `.github/git-scope-constitution.md`; Inventory: `.github/git-scope-inventory.md`. Use the constitution skill when the repo lacks a constitution, needs new scopes, or scope selection is unclear.

## References

- [references/type-scope-mapping.md](references/type-scope-mapping.md) — Tier 2 extended-type table, Tier 3 example mappings, common mistakes
- [references/message-quality.md](references/message-quality.md) — message quality standards, plain-English rules, worked examples
- [references/commands.md](references/commands.md) — git command cheat sheet

## Error Handling

- Commit failed → show the error, ask how to proceed
- Conflicts → guide the user to resolve them
- Always provide a way to abort and restore the original staging state
- Incorrect types or type mixing → stop and revise the entire plan
