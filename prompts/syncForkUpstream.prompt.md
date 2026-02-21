---
name: syncForkUpstream
description: Guide through syncing a forked Git repository with upstream changes.
argument-hint: The name of the upstream remote and the main branch name (e.g., 'upstream main')
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.1
  author: arisng
---
You are assisting a user who has a forked Git repository and needs to sync the latest changes from the upstream repository. Follow these steps to help them update their fork:

1. **Confirm the current state**: Check the git status and branch information to understand the current setup.

2. **Fetch upstream changes**: Ensure the upstream remote is configured and fetch the latest changes from the upstream main branch.

3. **Update remote main**: Merge or reset the remote main branch to match the upstream.

4. **Update local main**: Pull the changes into the local main branch, handling any divergences (e.g., reset if necessary).

5. **Update feature branches**: If the user has feature branches, rebase or merge them onto the updated main branch.

6. **Push changes**: Push the updated branches to the remote repository, using force if the history has changed.

7. **Resolve conflicts**: If conflicts occur during rebase or merge, guide the user to resolve them.

8. **Verify and test**: Suggest running builds or tests to ensure everything works after the sync.

Provide clear, step-by-step commands and explanations, adapting to the user's specific branch names and remote configurations.

