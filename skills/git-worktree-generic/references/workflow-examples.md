# Workflow Examples

> Detailed step-by-step walkthroughs for git worktree operations.
> Load this file when you need full command sequences with concrete examples.

---

## Table of Contents

- [Create a Session Worktree](#create-a-session-worktree)
- [Keep Up to Date (Rebase)](#keep-up-to-date-rebase)
- [Integrate a Branch Back](#integrate-a-branch-back)
- [Resolve Conflicts During Rebase](#resolve-conflicts-during-rebase)
- [Work with Multiple Worktrees Sequentially](#work-with-multiple-worktrees-sequentially)
- [Hotfix While Mid-Feature](#hotfix-while-mid-feature)

---

## Create a Session Worktree

```bash
# From the primary repo root
git fetch origin
git merge --ff-only origin/main

# Create the worktree in detached state (works even if current branch is dirty)
git worktree add --detach ../<repo>.worktrees/feature-250715-login-redesign origin/main

# Enter the worktree and create the task branch
cd ../<repo>.worktrees/feature-250715-login-redesign
git checkout -b feature/250715-login-redesign

# Verify location and branch
pwd
git rev-parse --abbrev-ref HEAD
git rev-parse --show-toplevel
```

---

## Keep Up to Date (Rebase)

```bash
# From inside the worktree
git fetch origin
git rebase origin/main
```

If the rebase succeeds without conflicts, you're done. If conflicts occur, see [Resolve Conflicts During Rebase](#resolve-conflicts-during-rebase).

---

## Integrate a Branch Back

```bash
# Step 1: Update the primary repo's integration branch
cd <primary-repo>
git checkout main
git fetch origin
git merge --ff-only origin/main

# Step 2: Rebase the worktree branch onto latest integration
cd ../<repo>.worktrees/feature-250715-login-redesign
git rebase origin/main

# Step 3: If rebase succeeds, merge from the primary repo
cd <primary-repo>
git merge --no-ff feature/250715-login-redesign -m "Integrate feature/250715-login-redesign into main"

# Step 4: Push
git push origin main

# Step 5: Clean up
git worktree remove ../<repo>.worktrees/feature-250715-login-redesign
git worktree prune
git branch -d feature/250715-login-redesign
```

---

## Resolve Conflicts During Rebase

```bash
# Inside the worktree after `git rebase origin/main` reports conflicts

# 1. See which files are conflicted
git status

# 2. Open each conflicted file, resolve the markers (<<<<<<, ======, >>>>>>)
#    Edit the file to keep the correct combination

# 3. Stage the resolved files
git add <resolved-file>

# 4. Continue the rebase
git rebase --continue

# 5. If you get stuck or want to abort:
git rebase --abort   # returns to the state before rebase started
```

**Conflict avoidance tips:**

- **Integrate frequently** — short-lived branches (<1 day) rarely conflict
- **Parallelize only unrelated modules** — if two worktrees touch the same files, integrate sequentially
- **Communicate** with teammates when sharing hotspots

---

## Work with Multiple Worktrees Sequentially

When working on features A and B in parallel:

```bash
# Session 1: Feature A
git worktree add --detach ../<repo>.worktrees/feature-250715-feature-a origin/main
cd ../<repo>.worktrees/feature-250715-feature-a
git checkout -b feature/250715-feature-a
# ... work, commit ...
cd <primary-repo>

# Session 2: Feature B (while Feature A still open)
git worktree add --detach ../<repo>.worktrees/feature-250715-feature-b origin/main
cd ../<repo>.worktrees/feature-250715-feature-b
git checkout -b feature/250715-feature-b
# ... work, commit ...
cd <primary-repo>

# Later: Integrate A first, then rebase B on top
# (Integrate A using the standard workflow)
# Then rebase B:
cd ../<repo>.worktrees/feature-250715-feature-b
git fetch origin
git rebase main
```

---

## Hotfix While Mid-Feature

```bash
# Current state: deep into feature/250715-login-redesign, not ready to commit

# 1. Create a hotfix worktree from main
git worktree add --detach ../<repo>.worktrees/hotfix-login-timeout origin/main
cd ../<repo>.worktrees/hotfix-login-timeout
git checkout -b hotfix/login-timeout

# 2. Fix, commit, merge back to main
git add . && git commit -m "fix(auth): increase login timeout"
cd <primary-repo>
git merge --no-ff hotfix/login-timeout
git push origin main

# 3. Clean up hotfix worktree
git worktree remove ../<repo>.worktrees/hotfix-login-timeout
git worktree prune
git branch -d hotfix/login-timeout

# 4. Return to feature work — no stashing needed
cd ../<repo>.worktrees/feature-250715-login-redesign
# Everything is exactly as you left it
```
