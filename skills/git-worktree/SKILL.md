---
name: git-worktree
description: Manage git worktrees in this repository for parallel implementation, sequential integration, release-branch preparation, and session cleanup. Use when creating a detached worktree first and only then creating its task branch inside that worktree, aligning task branches with shipping policy (`develop` for beta integration, `release/*` or `hotfix/*` for stable lanes), rebasing session branches into `develop`, or removing merged worktrees after validation.
---

# Git Worktree

Use one task branch per worktree and one integration branch in the primary repo.

## Defaults

- Keep the repo root on `develop` for normal feature integration.
- Create agent branches from `develop` as `feature/YYMMDD-slug` or `openspec/YYMMDD-slug`.
- Derive the worktree folder from the branch name by replacing `/` with `-` and placing it under `.worktrees/`.
- Treat branch and worktree names as a deterministic pair, not as identical strings.
- Create the worktree first from the chosen base ref in detached state, then create the branch inside that new worktree.
- Prefer no suffix; add a short suffix only when two concurrent sessions would otherwise collide on the same slug.
- Delete a worktree after its branch is merged and `develop` passes validation.
- Reserve `release/*`, `hotfix/*`, and `main` for stable shipping lanes; do not use them as disposable agent branches.
- Bootstrap one FSH stack per worktree session, but configure every session to target the same warm shared MSSQL container on the machine.

## Decision Rules

- Parallelize only when branches are unlikely to touch the same files.
- If two tasks touch the same hotspot, keep one task per branch but integrate sequentially and rebase the remaining branches after each merge.
- Keep the primary repo as the integration surface; keep agent worktrees disposable.
- Use worktree-first creation so a new agent session can start from a clean detached checkout even when the current branch is dirty.
- Start one FSH stack per worktree session for runtime checks.
- Keep MSSQL shared: point each session's FSH stack to the same warm MSSQL container endpoint so agents do not create separate SQL containers.

## Workflow

1. Create a session with `scripts/New-GitWorktreeSession.ps1`.
2. Run the assigned agent only inside that worktree.
3. Start a separate FSH stack inside each task worktree session.
4. Configure each session stack to use the same warm shared MSSQL container.
5. Integrate from the primary repo with `scripts/Integrate-GitWorktreeBranch.ps1`.
6. Rebase remaining session branches onto the updated base before the next merge.
7. Remove merged sessions with `scripts/Remove-GitWorktreeSession.ps1 -DeleteBranch`.

## Naming Matrix

| Use case | Base branch | Branch name | Worktree path |
| --- | --- | --- | --- |
| Parallel task | `develop` | `feature/260503-session-audit` | `.worktrees/feature-260503-session-audit` |
| OpenSpec task | `develop` | `openspec/260503-fix-zoom-status` | `.worktrees/openspec-260503-fix-zoom-status` |
| Release hardening | `main` or the chosen release base | `release/2605-stable` | `.worktrees/release-2605-stable` |
| Hotfix | `main` | `hotfix/login-timeout` | `.worktrees/hotfix-login-timeout` |

## Scripts

- `scripts/New-GitWorktreeSession.ps1`: create a detached worktree from the base ref, then create the branch inside that worktree, and optionally run restore/build.
- `scripts/Integrate-GitWorktreeBranch.ps1`: update the base branch, rebase the session branch, and integrate it in the planned order.
- `scripts/Remove-GitWorktreeSession.ps1`: remove the linked worktree and, when requested, delete the merged branch.

## Guardrails

- Do not check out the same branch in more than one worktree.
- Do not merge task branches into each other; merge them into `develop` in planned order.
- Do not create the task branch in the current dirty repo first; always create the worktree first and branch inside it.
- Do not delete a worktree that still holds the only copy of uncommitted work unless you intentionally pass `-Force`.
- Keep stable shipping worktrees long-lived only when the release or hotfix is still active.