# Safety Protocol

> Pre-action verification, recovery procedures, and decision rules for git worktree operations.
> Load this file when investigating misdirected work, errors, or when safety checks fail.

---

## Table of Contents

- [Pre-Action Verification](#pre-action-verification)
- [Wrong-Worktree Recovery](#wrong-worktree-recovery)
- [Handling Detached HEAD State](#handling-detached-head-state)
- [Accidental Worktree Removal](#accidental-worktree-removal)
- [Recovery from Pushed Mistakes](#recovery-from-pushed-mistakes)

---

## Pre-Action Verification

Before every edit, build, test, or commit when worktrees exist:

### Three mandatory checks

```bash
# Check 1: Are you inside the worktree?
pwd
# Expected: /path/to/<repo>.worktrees/<branch-folder>
# DANGER: If it resolves under the primary repo's root, cd into the worktree immediately.

# Check 2: Is the branch correct?
git rev-parse --abbrev-ref HEAD
# Expected: feature/*, fix/*, hotfix/*, etc. (your task branch)
# DANGER: If it shows main/develop, you're about to commit to the integration branch.

# Check 3: Is the commit target correct?
git rev-parse --show-toplevel
# Expected: /path/to/<repo>.worktrees/<branch-folder>
# DANGER: If it shows the primary repo path, your commits land in the wrong repo root.
```

> If ANY check fails: **Stop.** Do not add, commit, push, or merge. The primary repo is **read-only** during a session.

---

## Wrong-Worktree Recovery

If edits or commits landed in the wrong location:

### Uncommitted changes in the wrong worktree

```bash
# 1. Stop. Do not push or merge.

# 2. Stash the misdirected changes
cd <wrong-location>
git stash -m "misplaced-changes-<date>"

# 3. cd to the correct worktree
cd <correct-worktree>

# 4. Apply the stash here
git stash pop

# 5. Resolve conflicts if any
# 6. Verify git status --short is clean and branch matches expectations

# 7. From the wrong location, drop the stash only after confirming correct application
cd <wrong-location>
git stash drop stash@{0}   # only if you popped and verified
```

### Committed changes in the wrong worktree (not pushed)

```bash
# 1. Note the commit hash
git log --oneline -1

# 2. Cherry-pick the commit to the correct worktree
cd <correct-worktree>
git cherry-pick <commit-hash>

# 3. Verify it applied cleanly
git log --oneline -1

# 4. Back in the wrong worktree, reset the commit
cd <wrong-location>
git reset HEAD~1 --soft   # keeps changes staged
# OR
git reset HEAD~1 --hard   # discards changes entirely
```

### Committed and pushed to the wrong branch

```bash
# 1. Stop. Do not force-push without confirmation.
# 2. Notify your team immediately.
# 3. Do not delete remote branches without explicit approval.
```

---

## Handling Detached HEAD State

If `git rev-parse --abbrev-ref HEAD` shows `HEAD` instead of a branch name:

```bash
# You're in detached HEAD state. Create a branch to save your work:
git checkout -b feature/250715-recovery-<slug>

# Now you have a proper branch. Continue normally.
```

Detached HEAD can happen if you forget the `git checkout -b <branch>` step after creating a detached worktree.

---

## Accidental Worktree Removal

If you removed a worktree with uncommitted work:

```bash
# Check the primary repo's git reflog for branch tips
git reflog --all | grep <branch-name>

# If the branch had commits, the commits still exist (only the working copy is gone)
git checkout <branch-name>
# This recreates the working copy with all committed changes intact

# Uncommitted changes are gone unless you had them in a stash
git stash list
```

**Prevention:** Lock worktrees you want to protect:

```bash
git worktree lock <path>
# Later:
git worktree unlock <path>
```

---

## Recovery from Pushed Mistakes

If you pushed a commit from the wrong worktree or branch:

1. **Do not force-push.** Forced pushes rewrite shared history and break other developers' clones.
2. Use `git revert <commit>` to create a new commit that undoes the mistake — this is safe for shared branches.
3. Notify your team about the revert.

If force-push is absolutely necessary (e.g., sensitive data in a commit):

1. Confirm with the team.
2. Coordinate a recovery window.
3. Use `git push --force-with-lease` (safer than `--force` — it checks that your remote-tracking branch still matches the remote).
