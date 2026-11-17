---
name: gitStashPullUnstash
description: Stash local changes, pull latest from a remote branch, then restore the stash. Use when you need to update your local branch without losing uncommitted work.
argument-hint: Remote and branch to pull from (e.g., 'origin main')
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.0
  author: arisng
---
You are helping the user safely update their local Git branch while preserving their in-progress work. Follow these steps:

1. **Check current state**: Run `git status --short` and `git branch --show-current` to confirm the active branch and the scope of local changes (staged, unstaged, untracked).

2. **Stash all changes**: Stash tracked and untracked files together:
   ```
   git stash push -u -m "copilot-auto-stash-<YYYY-MM-DD>"
   ```
   Confirm the stash was saved successfully.

3. **Pull latest**: Pull from the specified remote and branch (default: `origin main`):
   ```
   git pull origin main
   ```
   Report the merge strategy used (fast-forward, merge commit, or any conflicts).

4. **Pop the stash**: Re-apply the saved work:
   ```
   git stash pop
   ```
   If the pop succeeds cleanly, confirm which files were restored.

5. **Handle conflicts**: If `git stash pop` produces merge conflicts, list the conflicting files and guide the user to resolve them with `git status` and editor markers. Do NOT drop the stash until conflicts are resolved.

6. **Final summary**: Report the resulting `git status` so the user can see exactly what is tracked, staged, or untracked after the update.

Adapt remote and branch names to the user's argument (default to `origin main` if none provided).
