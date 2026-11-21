---
date: 2025-12-11
type: Task
severity: N/A
status: Completed
---

# GitHub Copilot Workspace - Automation Solutions

> **Superseded (2026-11-21).** The unified command dispatcher and the
> publish scripts described in this record are **not present in this tree**;
> nothing below is runnable as written. Current entry points:
> `task lint` / `task check` (wrappers over `scripts/workspace/workspace-check.ps1`),
> `task skills:catalog`, `task issues:index`, and
> `npx skills add arisng/github-copilot-fc` for distribution.
> The consistency gate now fails any shipped-claim issue doc that cites a
> missing repo path, so this trap cannot ship again.

## Summary

This record documents the automation system that was scoped for managing
GitHub Copilot customizations: skills, agents, instructions, and prompts. The
described solutions were delivered and later removed; the document is kept
for its decision history only.

## What was described at the time

### 1. PowerShell scripts

- `publish-skills.ps1` — publishing with Copy/Link/Sync methods (not in this tree)
- `update-personal-skills.ps1` — update management for installed skills (not in this tree)
- `run-command.ps1` — a unified command dispatcher for all workspace operations (never retained)

### 2. Workspace configuration system

A centralized command mapping lived behind the dispatcher. Its equivalent
today is the Taskfile: `task lint`, `task check`, `task test`,
`task issues:index`, `task skills:catalog`.

### 3. VS Code integration

Six Command Palette tasks for publishing and status checks (historical).

### 4. Git integration

A post-commit publishing hook (historical). Current hooks live in
`.githooks/` — `pre-commit` runs the quick gate, `pre-push` the full gate.

### 5. Documentation

`skills/README.md` remains the distribution guide; issue tracking now lives
in `.issues/`.

## Current usage

```powershell
# Quick gate (pre-commit) and full gate (pre-push)
task lint
task check
```

Distribution and updates:

```powershell
npx skills add arisng/github-copilot-fc
npx skills update
```

## Method comparison (historical)

- Copy: cross-platform, no auto-update, best for production.
- Link: Windows-only, auto-update, best for development.
- Sync: Windows-only, auto-update, best for large collections.

## Why it still matters

- The workspace automation described here was folded into the Taskfile and
  the workspace gate that now runs on every commit.
- The document is a worked example of the check added on 2026-11-21:
  a "Completed" issue doc advertising commands that no longer exist reads as
  live instruction to an agent, and cost one failed command run before the
  citation rule caught it.
