# Google Workspace CLI - Service API Reference

Quick reference for commonly-used gws commands organized by service.

## Gmail API

| Operation | Command | Notes |
|-----------|---------|-------|
| Search emails | `gws gmail search --query "..."` | Supports advanced search syntax |
| Get email | `gws gmail get --id MSG_ID --format full` | Formats: metadata, minimal, full |
| Send email | `gws gmail send --to EMAIL --subject SUBJ --body TEXT` | Supports attachments, CC, BCC |
| Reply to email | `gws gmail send --to EMAIL --in-reply-to MSG_ID` | Preserves thread |
| List labels | `gws gmail list-labels` | Built-in: INBOX, DRAFT, SENT, TRASH |
| Create label | `gws gmail create-label --name NAME --color COLOR` | Colors: hex format (FF6D00) |
| Modify email | `gws gmail modify --id ID --add-label-ids LABEL --remove-label-ids LABEL` | Batch operation |
| Delete email | `gws gmail delete --id ID` | Permanently deletes |
| Get thread | `gws gmail get-thread --thread-id THREAD_ID --format full` | Returns all messages in thread |
| Batch modify | `gws gmail batch-modify --ids ID1,ID2,ID3 --add-labels LABEL` | Modify up to 100 at once |

**Common Search Queries**:
- Unread: `is:unread`
- From sender: `from:boss@example.com`
- Subject: `subject:urgent`
- Date range: `before:2026-04-01 after:2026-03-01`
- Has attachment: `has:attachment`
- Label: `label:important`
- Combine: `from:boss@example.com subject:urgent is:unread`

---

## Drive API

| Operation | Command | Notes |
|-----------|---------|-------|
| List files | `gws drive list --query "name contains 'Report'"` | Supports MIME type filters |
| Create folder | `gws drive create-folder --name NAME --parent PARENT_ID` | Parent: "root" or folder ID |
| Upload file | `gws drive upload --file PATH --parent PARENT_ID` | Auto-detects MIME type |
| Download file | `gws drive download --file-id FILE_ID --output PATH` | Downloads to local file |
| Share file | `gws drive share --file-id ID --role ROLE --emails EMAIL` | Roles: viewer, commenter, editor, owner |
| Get permissions | `gws drive get-permissions --file-id FILE_ID` | Lists all shared users |
| Update permission | `gws drive update-permission --file-id ID --permission-id PERM_ID --role ROLE` | Modify existing permission |
| Delete permission | `gws drive delete-permission --file-id ID --permission-id PERM_ID` | Revoke access |
| Move file | `gws drive update --file-id ID --new-parent PARENT_ID` | Moves to new folder |
| Rename file | `gws drive update --file-id ID --name NEW_NAME` | Changes display name |
| Get file info | `gws drive get --file-id ID` | Returns metadata |
| List revisions | `gws drive list-revisions --file-id ID` | Version history |
| Export as PDF | `gws drive export --file-id ID --mime-type application/pdf` | Converts format |

**Common MIME Types**:
- Google Docs: `application/vnd.google-apps.document`
- Google Sheets: `application/vnd.google-apps.spreadsheet`
- Google Slides: `application/vnd.google-apps.presentation`
- Folder: `application/vnd.google-apps.folder`
- PDF: `application/pdf`
- Any: omit for all types

**Share Roles**:
- `owner` — Can share and modify
- `editor` — Can modify but not share
- `commenter` — Can comment only
- `viewer` — Read-only access

---

## Calendar API

| Operation | Command | Notes |
|-----------|---------|-------|
| List events | `gws calendar list --calendar-id primary --time-min START --time-max END` | ISO 8601 timestamps |
| Create event | `gws calendar create --summary TEXT --start TIME --end TIME` | Supports recurrence |
| Update event | `gws calendar update --event-id ID --summary TEXT` | Partial updates allowed |
| Delete event | `gws calendar delete --event-id ID` | Removes for all attendees |
| Get free/busy | `gws calendar freebusy --emails EMAIL1,EMAIL2 --time-min START --time-max END` | Check availability |
| List calendars | `gws calendar list-calendars` | Shows all calendars user can access |
| Create calendar | `gws calendar create-calendar --summary NAME` | New calendar |
| Delete calendar | `gws calendar delete-calendar --calendar-id ID` | Permanently deletes |

**Recurrence Patterns** (RFC 5545):
- `FREQ=DAILY;COUNT=10` — Repeat daily for 10 times
- `FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=12` — MWF for 12 weeks
- `FREQ=MONTHLY;BYMONTHDAY=15` — Monthly on 15th
- `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` — Yearly on Dec 25

**Conference Types**:
- `hangoutsMeet` — Google Meet
- `addOn` — Third-party conference

---

## Sheets API

| Operation | Command | Notes |
|-----------|---------|-------|
| Create spreadsheet | `gws sheets create --title NAME --sheets SHEET1,SHEET2` | Creates with initial sheets |
| Get data | `gws sheets get --spreadsheet-id ID --range "Sheet1!A1:D100"` | Returns cell values |
| Update data | `gws sheets update --spreadsheet-id ID --range "Sheet1!A1" --values DATA` | Sets values in range |
| Append data | `gws sheets append --spreadsheet-id ID --range "Sheet1!A:D" --values DATA` | Adds new rows |
| Clear data | `gws sheets clear --spreadsheet-id ID --range "Sheet1"` | Clears cells |
| Add sheet | `gws sheets add-sheet --spreadsheet-id ID --title NAME` | New tab/sheet |
| Delete sheet | `gws sheets delete-sheet --spreadsheet-id ID --sheet-id ID` | Removes sheet |
| Batch update | `gws sheets batch-update --spreadsheet-id ID --requests JSON` | Complex operations |
| Export | `gws sheets export --spreadsheet-id ID --range "Sheet1" --format csv` | CSV, JSON, etc. |

**Cell Ranges**:
- `Sheet1!A1` — Single cell
- `Sheet1!A1:D10` — Rectangle
- `Sheet1!A:D` — Columns A-D
- `'My Sheet'!A1:A100` — Quoted sheet names with spaces
- `Sheet1!A1:B2,Sheet2!C1:D2` — Multiple ranges

**Data Format** (for update/append):
```json
[
  ["Name", "Email", "Status"],
  ["Alice", "alice@example.com", "Active"],
  ["Bob", "bob@example.com", "Inactive"]
]
```

---

## Docs API

| Operation | Command | Notes |
|-----------|---------|-------|
| Create document | `gws docs create --title NAME` | Empty doc by default |
| Get document | `gws docs get --document-id ID` | Full content |
| Append text | `gws docs append --document-id ID --text TEXT` | Adds to end |
| Insert table | `gws docs insert-table --document-id ID --rows 5 --columns 3` | At location 1 |
| Insert image | `gws docs insert-image --document-id ID --image-url URL` | From web |
| Update text | `gws docs update --document-id ID --old-text OLD --new-text NEW` | Find/replace |
| Insert page break | `gws docs insert-page-break --document-id ID` | New page |
| Insert comment | `gws docs insert-comment --document-id ID --text COMMENT` | Adds comment |
| Resolve comment | `gws docs resolve-comment --document-id ID --comment-id ID` | Marks as done |

**Markdown Support**:
- `# Heading 1`, `## Heading 2`, etc.
- `**bold**`, `*italic*`, `~~strikethrough~~`
- `- List item`
- `> Quote`
- `[Link](https://...)`

---

## Chat API

| Operation | Command | Notes |
|-----------|---------|-------|
| List spaces | `gws chat list-spaces` | All accessible spaces |
| Create space | `gws chat create-space --display-name NAME --space-type ROOM` | New collaboration space |
| Send message | `gws chat send-message --space SPACE_ID --text TEXT` | Plain text |
| Send card | `gws chat send-card --space SPACE_ID --card-json JSON` | Rich formatting |
| List messages | `gws chat list-messages --space SPACE_ID` | Message history |
| Delete message | `gws chat delete-message --space SPACE_ID --message-id ID` | Removes message |
| Update message | `gws chat update-message --space SPACE_ID --message-id ID --text TEXT` | Edit message |
| Add member | `gws chat add-member --space SPACE_ID --member EMAIL --role ROLE` | Add user to space |
| Remove member | `gws chat remove-member --space SPACE_ID --member EMAIL` | Remove user |
| List members | `gws chat list-members --space SPACE_ID` | All space members |

**Space Types**:
- `ROOM` — Persistent space for team collaboration
- `DM` — Direct message (1-on-1)
- `GROUP_DM` — Group direct message

**Member Roles**:
- `ROLE_MANAGER` — Can manage space
- `ROLE_MEMBER` — Regular member
- `ROLE_READER` — Read-only access

---

## Admin SDK

| Operation | Command | Notes |
|-----------|---------|-------|
| Create user | `gws admin create-user --first-name FIRST --last-name LAST --email EMAIL` | Must be unique |
| Get user | `gws admin get-user --email EMAIL` | User details |
| List users | `gws admin list-users --query "suspended=false"` | With optional filter |
| Update user | `gws admin update-user --email EMAIL --first-name FIRST` | Partial updates |
| Delete user | `gws admin delete-user --email EMAIL` | Removes account |
| Suspend user | `gws admin suspend-user --email EMAIL` | Disables login |
| Restore user | `gws admin restore-user --email EMAIL` | Re-enable login |
| Create group | `gws admin create-group --email EMAIL --name NAME` | Group email |
| Add group member | `gws admin add-group-member --group GROUP --member MEMBER` | Add to group |
| Remove group member | `gws admin remove-group-member --group GROUP --member MEMBER` | Remove from group |
| List group members | `gws admin list-group-members --group GROUP` | All members |
| Create org unit | `gws admin create-org-unit --name NAME --parent PATH` | Organization tree |
| List org units | `gws admin list-org-units` | All OUs |
| Update org unit | `gws admin update-org-unit --org-unit-path PATH --name NAME` | Rename OU |

**User Queries** (for filtering):
- `suspended=false` — Active users
- `orgUnitPath='/Engineering'` — Users in OU
- `changePasswordAtNextLogin=true` — Must change password
- Combine with `AND`: `suspended=false AND orgUnitPath='/Engineering'`

---

## Output Formats

All commands support these output options:

```powershell
# JSON (default, suitable for scripting)
gws gmail search --query "..." --output json

# CSV (for spreadsheets)
gws gmail search --query "..." --output csv > results.csv

# YAML (human-readable)
gws gmail search --query "..." --output yaml

# Table (CLI-friendly)
gws gmail search --query "..." --output table
```

---

## Common Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--output FORMAT` | Output format | `--output json` |
| `--limit N` | Max results | `--limit 100` |
| `--page-size N` | Results per page | `--page-size 50` |
| `--dry-run` | Preview without executing | `--dry-run` |
| `--silent` | No output to stdout | `--silent` |
| `--timeout SEC` | Request timeout | `--timeout 120` |
| `--retry N` | Max retries | `--retry 3` |
| `--fields FIELDS` | Specific fields only | `--fields "id,name"` |

---

## Error Messages & Solutions

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `401 Unauthorized` | Token expired | `gws auth login --refresh` |
| `403 Forbidden` | Insufficient permissions | Check OAuth scopes: `gws auth status` |
| `404 Not Found` | Resource doesn't exist | Verify ID format and spelling |
| `429 Too Many Requests` | Rate limited | Add delay: `--page-delay 1000` |
| `500 Internal Server Error` | Google service error | Retry: `--retry 3` |
| `Invalid file ID` | Wrong format | Check file ID (alphanumeric, ~30 chars) |
| `Query parse error` | Bad Gmail query | Verify search syntax |

---

## Pagination

For large result sets:

```powershell
# Automatic pagination with page size
gws gmail search --query "..." --limit 1000 --page-size 100 --output json

# Paginate manually
$page1 = gws gmail search --query "..." --limit 100 --page-token "" --output json
$page2 = gws gmail search --query "..." --limit 100 --page-token $page1.nextPageToken --output json
```

---

## Tips & Tricks

1. **Save results to variable for reuse**:
   ```powershell
   $results = gws gmail search --query "..." --output json | ConvertFrom-Json
   foreach ($item in $results.messages) { ... }
   ```

2. **Filter results with ConvertFrom-Json and Where-Object**:
   ```powershell
   gws gmail search --query "..." --output json | ConvertFrom-Json | `
     Select-Object -ExpandProperty messages | `
     Where-Object { $_.id -like "*abc*" }
   ```

3. **Export to CSV for analysis**:
   ```powershell
   gws drive list --query "..." --output json | ConvertFrom-Json | `
     Select-Object -ExpandProperty files | `
     Export-Csv "files.csv" -NoTypeInformation
   ```

4. **Chain operations**:
   ```powershell
   # Create doc → Share → Send announcement
   $doc = gws docs create --title "Report" --output json | ConvertFrom-Json
   gws drive share --file-id $doc.documentId --role editor --emails "team@example.com" --output json | Out-Null
   gws chat send-message --space "spaces/ABC123" --text "New report: https://docs.google.com/document/d/$($doc.documentId)/edit" --output json
   ```
