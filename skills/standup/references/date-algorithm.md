# Date Range Auto-Detection

Determine which dates need standup files before collecting data. The algorithm has two phases: a **backward catch-up scan** (existing files missing this author) and a **forward range** (new dates not yet on disk).

Get the current git user name from `git config user.name` — this is the author whose entries we need. If not in a git repo, use `$env:USERNAME`.

## Phase 1: Backward catch-up scan

Scan **all** existing `.standup/` files matching `standup-YYYY-MM-DD.md`. For each file before today:
- Read it and check whether it contains `Author: @<current-user>` (matching the current git user name).
- If **no** entries found for this author → add that date to the `missing_dates` set.
- Files that do contain entries for this author are skipped.

This catches gaps where earlier dates have standup files but the current user never contributed to them.

## Phase 2: Compute forward range

Determine `latest_generated_date`: the most recent date from matching filenames (ignoring future-dated files). Generate standup files for **every date** from `latest_generated_date` (inclusive) through **yesterday** (relative to current date). Never generate a file for today — today's work is not complete.

- **No existing `.standup/` directory or no files** — Default `latest_generated_date` to 6 calendar days before yesterday (i.e., generate the last 7 completed days). Do not warn or ask; it is the expected first-run case.
- **Gap in coverage** — Include every date in the range even if some intermediate dates are missing from disk.

## Phase 3: Merge target dates

Take the union of `missing_dates` and the forward range. This is the full set of dates to process. Deduplicate and sort chronologically.

## Edge cases

- **Future-dated file** — If a file exists with a date after today, ignore it for `latest_generated_date`. Fall back to the most recent valid file before today.
- **Nothing to generate** — If both the forward range and `missing_dates` are empty, report "Standup is current — nothing to generate." and stop.
