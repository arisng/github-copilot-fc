# Git Commands Reference

Cheat sheet for inspecting, staging, and committing changes.

```powershell
# View all changed files (staged + unstaged)
git status --short

# View diff for unstaged changes
git diff -- <filepath>

# View diff for staged changes
git diff --cached -- <filepath>

# Stage specific files (never broad staging: . , -A, <dir>)
git add <filepath>

# Stage only in-scope hunks of a mixed-hunk file
git add -p <filepath>

# Unstage specific files
git restore --staged <filepath>      # modern
git reset HEAD -- <filepath>         # legacy

# Verify exactly what is staged before committing
git diff --cached --name-only

# Verify exactly what a commit contains
git show --stat --oneline HEAD

# Commit with message
git commit -m "<subject>" -m "<body>"
```