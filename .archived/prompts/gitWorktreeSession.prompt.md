---
name: gitWorktreeSession
description: Create a new git worktree session with workspace defaults (BaseBranch=develop)
argument-hint: Provide a slug describing the task (e.g., "fix-login-bug")
metadata:
  version: 1.0.0
  author: arisng
---
Use the git-worktree-generic skill to create a new worktree session with these defaults:
- BaseBranch: develop
- Mode: feature
- WorktreeRoot: .worktrees
Generate the branch name from the slug and date, create a detached worktree from develop, then create the branch inside it.
