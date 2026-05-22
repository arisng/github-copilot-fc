---
name: git-session-atomic-commits
description: "Session-scoped git commit orchestrator that commits only current-session changes and leaves unrelated dirty worktree edits untouched. Inherits git-atomic-commit for atomic grouping and commit message execution, and git-commit-scope-constitution for scope governance and validation. Use when asked to commit this session only or isolate commits from mixed worktree state."
argument-hint: "Optional session scope hint: feature, issue, files, or short intent"
---

# Git Atomic Commits for Current Session

## Inherited Skills

Load and delegate to these; do not re-implement their rules here:
- **git-atomic-commit** — atomic partitioning, staging, commit execution, type/scope format
- **git-commit-scope-constitution** — scope inventory and validation

## Workflow

1. Resolve scope: use argument text → infer from conversation + git status → ask if still ambiguous.
2. Run `git status` and `git diff`. Map each changed file/hunk to session scope or mark as unrelated.
3. If a file could belong to multiple atomic units, pause and ask before proceeding.
4. Delegate scoped changes to **git-atomic-commit** for partitioning and commit execution.
5. Validate all scopes via **git-commit-scope-constitution**.
6. Report results (see Output below).

## Safety Rules

- Never stage or commit unrelated files or hunks.
- Never amend existing commits unless explicitly requested.
- Prefer non-destructive git commands.
- Stop and report if session boundaries cannot be established confidently.

## Output

Return in order:
1. Session scope identified.
2. Commits created (type/scope/message).
3. Files included per commit.
4. Unrelated changes intentionally left untouched.
5. Any ambiguities and how they were resolved.
