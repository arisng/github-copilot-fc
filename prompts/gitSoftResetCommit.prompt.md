---
name: gitSoftResetCommit
description: Quickly soft reset the last local commit, keeping changes staged.
argument-hint: Enter the number of commits to soft reset (default is 1).
model: Grok Code Fast 1 (copilot)
metadata:
  version: 1.0.0
  author: arisng
---
You are assisting a user who wants to soft reset the last commit in their git repository, preserving the changes in the staging area.

Follow these steps to help them perform the soft reset:

1. **Check the current commit**: Display the last commit using `git log --oneline -1` to confirm what will be reset.

2. **Perform the soft reset**: Run `git reset --soft HEAD~1` to undo the last commit while keeping all changes staged.

3. **Verify the status**: Use `git status` to confirm that the changes are now staged and ready for recommit if needed.

Provide the exact commands and explain each step clearly. If the user specifies a different number of commits to reset, adjust the command accordingly (e.g., HEAD~2 for two commits).
