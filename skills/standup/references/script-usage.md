# Get-StandupData.ps1 Usage

Collect session data once per target date. Loop over each date in the computed range.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Days` | 1 | Relative: last N days of sessions |
| `-Date` | (empty) | Explicit calendar date in `yyyy-MM-dd` format (UTC+7) |
| `-UtcOffsetHours` | 7 | Timezone offset for date filtering |
| `-Author` | (auto-detect) | Override author (default: `git config user.name`) |
| `-Repository` | (auto-detect) | Override repo filter (default: `git remote get-url origin`) |
| `-SessionDbPath` | `~/.copilot/session-store.db` | Path to Copilot session database |

## Examples

```powershell
# Specific calendar date (UTC+7 timezone)
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Date "2026-07-06" | ConvertFrom-Json

# Last 24 hours (relative) — useful for a single-date run
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Days 1 | ConvertFrom-Json

# Override repository (when CWD is not the target repo)
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Days 1 -Repository "owner/repo" | ConvertFrom-Json
```

## Timezone

All date filtering defaults to **UTC+7 (Indochina Time)**. The `-Date` parameter treats the given date as midnight UTC+7. Override with `-UtcOffsetHours` (e.g. `-UtcOffsetHours 8` for UTC+8).

## Auto-detection

The script auto-detects the author from `git config user.name` and the current repo from `git remote get-url origin`. It only returns sessions matching that repo. Override with `-Author "Name"` or `-Repository "owner/repo"`.

**Date filtering is turn-timestamp based** — it finds sessions by when actual work happened (conversation turns), not when the session was created. This correctly catches multi-day sessions, resumed sessions, and overnight work.
