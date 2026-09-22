# Cross-check with Git (Verification Only, Current User Only)

> **Skip this entire section when `isRepo` is false** — there is no git data to cross-check.

After grouping from session data, cross-reference with `gitCommits` to verify done status. Filter git commits to the current user's commits using `git log --author="$(git config user.name)"`. Other authors' commits are **not** used.

1. Verify done status (commits by the current user on this branch = done)
2. Check for additional work by the current user not captured in sessions — only add entries if the commits represent distinct work items with no corresponding session

**Never output raw commit hashes or a `## Git Commits` section.** Git data is evidence, not output.
