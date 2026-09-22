# Per-Date Merge Flow

For each date in the computed range:

1. Collect session data for the date — this only returns sessions matching the current repo and author
2. Compose entries for the current author from the filtered session data — if filtering leaves zero usable entries **and** `gitCommits` has no commits for this date → **skip this date** (fire `NO_ENTRIES` from `composing-entries`); never author an empty section
3. Cross-check with the current user's git commits to verify done status — **skip this step when `isRepo` is false**; if neither sessions nor commits yield any entry → **skip this date** (fire `NO_ENTRIES` from `cross-checking-git`)
4. Check if `.standup/standup-<yyyy>-<mm>-<dd>.md` already exists
5. If it does not exist → write the file fresh using `assets/templates/standup.md` as the format reference
6. If it does exist → read it, then dedup against the current user's entries (see [Dedup rules](#dedup-rules)):
   - Scan for `Author: @<current-user>` lines matching the current git user name
   - If the author's section already contains **every** composed entry → **skip this date** (fire `ALREADY_RECORDED`) — this user is already recorded
   - If some entries are new → append/merge only the new entries under this author's section (create the `## @<current-user>` section if absent)

## Dedup rules

Each entry is identified by a composite key: **(feature title, branch, author)**. Two entries are considered equal if all three match.

| Case | Action |
|------|--------|
| Entry exists for this author + feature + branch | **Skip** — already recorded |
| Entry exists with different author but same feature + branch | **Keep both** — different contributors, different perspective |
| Entry exists for this author but different feature/branch | **Add** — new work item |
| Author section exists but entries differ | **Merge** — update content, keep the existing |
