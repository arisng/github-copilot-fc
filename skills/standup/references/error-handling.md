# Error Handling

The state machine includes error transitions for I/O failures at critical points:
- `DATA_COLLECTION_FAILED` (collecting-data → error)
- `GIT_CHECK_FAILED` (cross-checking-git → error)
- `DEDUP_CHECK_FAILED` (checking-dedup → error)
- `WRITE_FAILED` (writing-fresh → error)
- `APPEND_FAILED` (appending-author → error)

When an error occurs, the machine transitions to the `error` state (non-final). The driving agent will see **zero enabled events** (STUCK) and should call `abort --reason "..."` to terminate the run with `result: ABORTED`.

**Retry behavior:** Re-running the skill after an error is safe. The date auto-detection algorithm scans existing `.standup/` files and skips dates that already have entries for the current author (via the dedup check). This means:
- Dates that completed successfully before the error are preserved on disk.
- Only the failed date (and subsequent dates) will be reprocessed.
- No duplicate entries are created.
