---
agent: 'agent'
tools: ['edit/createFile', 'edit/createDirectory', 'edit/editFiles', 'search', 'execute/getTerminalOutput', 'execute/runInTerminal', 'read/terminalLastCommand', 'read/terminalSelection', 'execute/createAndRunTask', 'execute/getTaskOutput', 'execute/runTask', 'git/*', 'microsoftdocs/mcp/*', 'sequentialthinking/*', 'time/*', 'search/usages', 'vscode/vscodeAPI', 'read/problems', 'search/changes', 'web/fetch', 'todo', 'agent']
description: 'Generate a changelog file for daily, weekly, or specific date updates, always overriding the existing file. Always use git commit history to gather changes.'
---

# Generate Changelog

Generate a changelog file from git commit history with configurable datetime range and output structure.

## Input Parameters

### 1. Datetime Range (default: weekly)
- **Weekly**: Current week (Monday–Sunday) with ISO week number
- **Daily**: Today (current date)
- **Specific Date**: User-specified date in YYYY-MM-DD format

### 2. Output Structure (default: raw)
- **Raw**: Unformatted git commits with full metadata (hash, author, date, full multi-line message) for ETL pipeline processing
- **Summary**: Categorized changelog grouped by Added/Changed/Fixed

## Requirements
- Prompt the user to select datetime range: `${input:datetimeRange:weekly,daily,specific}` (default: weekly)
- Prompt the user to select output structure: `${input:outputStructure:raw,summary}` (default: raw)
- If specific date is selected, prompt for the date: `${input:changelogDate:YYYY-MM-DD}`
- Always override the existing changelog file if it exists
- The changelog file must be saved in the `/_docs/changelogs` folder

## File Naming Convention
Format: `wNN[_yymmdd]_[raw|summary].md`

- `wNN`: ISO week number (always present)
- `_yymmdd`: Date suffix (only for daily or specific date modes)
- `_[raw|summary]`: Output structure

Examples:
- Weekly raw: `w47_raw.md` (week 47, 2025)
- Weekly summary: `w47_summary.md`
- Daily raw: `w47_251120_raw.md` (Nov 20, 2025, week 47)
- Daily summary: `w47_251120_summary.md`
- Specific date raw: `w42_251015_raw.md` (Oct 15, 2025, week 42)
- Specific date summary: `w42_251015_summary.md`

## Instructions
1. Prompt the user to select datetime range (default: weekly) and output structure (default: raw)
2. If specific date is selected, prompt for the date in YYYY-MM-DD format
3. Use the `scripts/create-weekly-changelog.ps1` PowerShell script to generate the changelog:
   - For **weekly** mode: `.\scripts\create-weekly-changelog.ps1 -OutputStructure [raw|summary]`
   - For **daily** mode: `.\scripts\create-weekly-changelog.ps1 -SinceDate YYYY-MM-DD -UntilDate YYYY-MM-DD -OutputStructure [raw|summary]`
   - For **specific date** mode: `.\scripts\create-weekly-changelog.ps1 -SinceDate YYYY-MM-DD -UntilDate YYYY-MM-DD -OutputStructure [raw|summary]`
4. The script automatically:
   - Calculates the ISO week number
   - Gathers git commit history for the period
   - Excludes changelog-related commits
   - Formats output according to structure (raw or summary)
   - Saves to `/_docs/changelogs` with proper naming convention
   - Overwrites existing file if present

## Output Format

### Raw Structure (Default)
```markdown
# Raw Changelog: [Date or Week Range], Week [NN], [Year]

## Commits

[Full git log output with format: author | date | message]
```

Example:
```markdown
# Raw Changelog: November 17–23, Week 47, 2025

## Commits

John Doe | 2025-11-20 | feat: add new activity controller

This commit introduces a new controller for managing activities.
- Added ActivityController with CRUD operations
- Integrated with existing service layer

Jane Smith | 2025-11-19 | fix: resolve session caching issue

Fixed a bug where session data was not properly cached.
Updated cache invalidation logic to handle edge cases.
```

### Summary Structure
```markdown
# Changelog: [Date or Week Range], Week [NN], [Year]

### Added
- [New features or functionality]

### Changed
- [Updates, modifications, enhancements, removals, deprecations]

### Fixed
- [Bug fixes and simple corrections]
```

## Guidance for Allocating Changes to Headings
- **Added**: Only for entirely new features or functionality.
- **Changed**: For updates or modifications to existing features, bug fixes, removals, deprecations, or any other change that is not a new feature (e.g., "update search methods to include advanced filtering options," removed features, or deprecated features should all be under Changed).
- **Fixed**: For bug fixes that are simple corrections and not broader changes.

Notices:
- If a change description includes words like "update," "modify," "enhance," "remove," or "deprecate" for existing features, allocate it to **Changed**. When in doubt, review the context or commit details to ensure correct classification.
- Ignore commit messages that is about adding new changelog entries or updating the changelog file itself, as these are not relevant to the actual changes in the codebase.

## Error Handling
- If datetime range is unclear, default to weekly
- If output structure is unclear, default to raw
- If no changes are found for the period, indicate this in the changelog file

## Additional Requirements
- Always use the `scripts/create-weekly-changelog.ps1` script to generate changelogs
- The script enforces all requirements: git commit history, ISO week numbers, proper naming, and changelog commit exclusion
- For summary output structure, you may need to post-process the generated file to categorize commits into Added/Changed/Fixed sections
- For raw output structure, the git log must include the full multi-line commit message body (ensure the script uses the appropriate git pretty format, e.g., %B instead of %s)