#!/bin/bash
# Google Workspace CLI - Quick Start Examples
# Copy-paste ready commands for common gws operations

# ============================================================================
# SETUP & VERIFICATION
# ============================================================================

# Verify gws is installed
gws --version

# Authenticate (one-time setup)
gws auth setup

# Check authentication status
gws auth status

# List available services
gws service list

# ============================================================================
# GMAIL EXAMPLES
# ============================================================================

# Search for unread emails
gws gmail search --query "is:unread" --limit 20 --output json

# Search for urgent emails from leadership
gws gmail search --query 'from:(boss@example.com OR ceo@example.com) subject:(urgent OR critical)' --limit 50 --output json

# Get full email content
gws gmail get --id "MESSAGE_ID" --format full --output json

# Send simple email
gws gmail send \
  --to "user@example.com" \
  --subject "Hello" \
  --body "This is a test email" \
  --output json

# Send email with attachment
gws gmail send \
  --to "user@example.com" \
  --subject "Report" \
  --body "Please find the report attached" \
  --attachments "report.pdf" "data.xlsx" \
  --output json

# Apply label to email
gws gmail modify \
  --id "MESSAGE_ID" \
  --add-label-ids "URGENT" \
  --remove-label-ids "INBOX" \
  --output json

# Create new label
gws gmail create-label --name "project-alpha" --color FF6D00 --output json

# List all labels
gws gmail list-labels --output json

# Get email thread
gws gmail get-thread --thread-id "THREAD_ID" --format full --output json

# ============================================================================
# DRIVE EXAMPLES
# ============================================================================

# List files
gws drive list --query "name contains 'Report' and trashed=false" --limit 50 --output json

# List files in specific folder
gws drive list --query "parents='FOLDER_ID'" --output json

# Create folder
gws drive create-folder --name "Q2 2026" --parent "root" --output json

# Upload file
gws drive upload --file "presentation.pptx" --parent "FOLDER_ID" --name "Q2 Strategy" --output json

# Share file with user
gws drive share \
  --file-id "FILE_ID" \
  --role "editor" \
  --emails "user@example.com" \
  --output json

# Share file with domain (team-wide)
gws drive share \
  --file-id "FILE_ID" \
  --role "viewer" \
  --type "domain" \
  --domain "example.com" \
  --output json

# Get file permissions
gws drive get-permissions --file-id "FILE_ID" --output json

# Update file permission
gws drive update-permission \
  --file-id "FILE_ID" \
  --permission-id "PERMISSION_ID" \
  --role "commenter" \
  --output json

# Delete file permission (revoke access)
gws drive delete-permission \
  --file-id "FILE_ID" \
  --permission-id "PERMISSION_ID" \
  --output json

# Move file to another folder
gws drive update --file-id "FILE_ID" --new-parent "NEW_PARENT_ID" --output json

# List file revisions (version history)
gws drive list-revisions --file-id "FILE_ID" --limit 10 --output json

# ============================================================================
# CALENDAR EXAMPLES
# ============================================================================

# List events for today
gws calendar list \
  --calendar-id "primary" \
  --time-min "2026-04-01T00:00:00Z" \
  --time-max "2026-04-02T00:00:00Z" \
  --output json

# List events for next 7 days
gws calendar list \
  --calendar-id "primary" \
  --time-min "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --time-max "$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 50 \
  --output json

# Create event
gws calendar create \
  --summary "Team Sync" \
  --description "Weekly synchronization" \
  --start "2026-04-15T10:00:00" \
  --end "2026-04-15T11:00:00" \
  --timezone "America/Los_Angeles" \
  --attendees "alice@example.com,bob@example.com" \
  --conference-type hangoutsMeet \
  --output json

# Create recurring event
gws calendar create \
  --summary "Weekly Standup" \
  --start "2026-04-14T09:00:00" \
  --end "2026-04-14T09:30:00" \
  --recurrence "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=12" \
  --attendees "team@example.com" \
  --output json

# Check free/busy for multiple people
gws calendar freebusy \
  --emails "alice@example.com,bob@example.com,charlie@example.com" \
  --time-min "2026-04-15T00:00:00Z" \
  --time-max "2026-04-22T23:59:59Z" \
  --output json

# Update event
gws calendar update \
  --event-id "EVENT_ID" \
  --summary "Team Sync (Rescheduled)" \
  --start "2026-04-15T10:30:00" \
  --end "2026-04-15T11:30:00" \
  --notify-attendees \
  --output json

# Delete event
gws calendar delete --event-id "EVENT_ID" --send-notifications --output json

# List calendars
gws calendar list-calendars --output json

# ============================================================================
# SHEETS EXAMPLES
# ============================================================================

# Create spreadsheet
gws sheets create --title "Q2 OKRs" --sheets "Engineering,Product,Sales" --output json

# Read data from spreadsheet
gws sheets get \
  --spreadsheet-id "SHEET_ID" \
  --range "Sheet1!A1:D100" \
  --output json

# Write data to spreadsheet
gws sheets update \
  --spreadsheet-id "SHEET_ID" \
  --range "Sheet1!A1" \
  --values '[["Name","Email","Status"],["Alice","alice@example.com","Active"]]' \
  --output json

# Append rows to spreadsheet
gws sheets append \
  --spreadsheet-id "SHEET_ID" \
  --range "Sheet1!A:D" \
  --values '[["Bob","bob@example.com","Active"]]' \
  --output json

# Clear sheet
gws sheets clear --spreadsheet-id "SHEET_ID" --range "Sheet1" --output json

# Add new sheet/tab
gws sheets add-sheet --spreadsheet-id "SHEET_ID" --title "New Tab" --output json

# Export as CSV
gws sheets export \
  --spreadsheet-id "SHEET_ID" \
  --range "Sheet1" \
  --format csv > output.csv

# ============================================================================
# DOCS EXAMPLES
# ============================================================================

# Create document
gws docs create --title "Meeting Notes" --output json

# Append text to document
gws docs append \
  --document-id "DOC_ID" \
  --text "# Introduction\n\nThis is a sample document." \
  --output json

# Insert table into document
gws docs insert-table \
  --document-id "DOC_ID" \
  --rows 5 \
  --columns 3 \
  --location 1 \
  --output json

# Insert image into document
gws docs insert-image \
  --document-id "DOC_ID" \
  --image-url "https://example.com/image.png" \
  --width 200 \
  --height 150 \
  --location 1 \
  --output json

# Replace text in document
gws docs update \
  --document-id "DOC_ID" \
  --request-type replaceText \
  --old-text "TODO" \
  --new-text "Done" \
  --output json

# Insert comment
gws docs insert-comment \
  --document-id "DOC_ID" \
  --text "Please review this section" \
  --anchor-text "Introduction" \
  --resolved false \
  --output json

# Get document content
gws docs get --document-id "DOC_ID" --output json

# ============================================================================
# CHAT EXAMPLES
# ============================================================================

# List spaces
gws chat list-spaces --limit 50 --output json

# List spaces with filter
gws chat list-spaces --filter "displayName:'engineering'" --output json

# Send message to space
gws chat send-message \
  --space "spaces/SPACE_ID" \
  --text "Team: The deployment is complete." \
  --output json

# Send message with formatting (card)
gws chat send-card \
  --space "spaces/SPACE_ID" \
  --card-json '{
    "sections": [
      {
        "widgets": [
          {
            "textParagraph": {
              "text": "<b>Deployment Status</b>\nAll services running"
            }
          }
        ]
      }
    ]
  }' \
  --output json

# Create new space
gws chat create-space --display-name "Project Alpha" --space-type ROOM --output json

# Add user to space
gws chat add-member \
  --space "spaces/SPACE_ID" \
  --member "users/alice@example.com" \
  --role MANAGER \
  --output json

# Remove user from space
gws chat remove-member \
  --space "spaces/SPACE_ID" \
  --member "users/alice@example.com" \
  --output json

# List messages in space
gws chat list-messages --space "spaces/SPACE_ID" --limit 100 --output json

# ============================================================================
# ADMIN EXAMPLES
# ============================================================================

# Create user
gws admin create-user \
  --first-name "Alice" \
  --last-name "Smith" \
  --email "alice@example.com" \
  --org-unit "/Engineering" \
  --password "TempPassword123!" \
  --output json

# Get user details
gws admin get-user --email "alice@example.com" --output json

# List users
gws admin list-users --limit 100 --output json

# List users in specific org unit
gws admin list-users \
  --query "orgUnitPath='/Engineering' and suspended=false" \
  --limit 100 \
  --output json

# Update user
gws admin update-user \
  --email "alice@example.com" \
  --first-name "Alicia" \
  --phone "555-0123" \
  --output json

# Suspend user (disable login)
gws admin suspend-user --email "alice@example.com" --output json

# Restore user (re-enable login)
gws admin restore-user --email "alice@example.com" --output json

# Create group
gws admin create-group \
  --name "engineering-team" \
  --email "engineering@example.com" \
  --description "All engineers" \
  --output json

# Add member to group
gws admin add-group-member \
  --group "engineering@example.com" \
  --member "alice@example.com" \
  --member-type USER \
  --output json

# List group members
gws admin list-group-members --group "engineering@example.com" --limit 500 --output json

# Remove member from group
gws admin remove-group-member \
  --group "engineering@example.com" \
  --member "alice@example.com" \
  --output json

# List organizational units
gws admin list-org-units --output json

# Create organizational unit
gws admin create-org-unit --name "Engineering" --parent "/" --output json

# Get admin report (licenses)
gws admin get-customer-report --report-type licenses --output json

# ============================================================================
# COMMON PATTERNS
# ============================================================================

# Search emails and export to CSV
gws gmail search --query "from:boss@example.com" --limit 100 --output json | \
  jq -r '.messages[] | [.id, .threadId] | @csv' > emails.csv

# List all files in folder and count
gws drive list --query "parents='FOLDER_ID'" --output json | \
  jq '.files | length'

# Find all shared files in domain
gws drive list --query "permission != 'restricted' and trashed=false" --limit 100 --output json

# Get all events for this week with attendees
gws calendar list \
  --calendar-id "primary" \
  --time-min "2026-04-14T00:00:00Z" \
  --time-max "2026-04-21T23:59:59Z" \
  --output json | \
  jq '.items[] | {summary: .summary, attendees: .attendees}'

# Archive emails older than 6 months
gws gmail search --query "before:2025-10-01" --output json | \
  jq -r '.messages[].id' | \
  xargs -I {} gws gmail modify --id {} --add-labels "Archive" --remove-labels "INBOX" --output json

# ============================================================================
# HELP & DEBUGGING
# ============================================================================

# Show version
gws --version

# Show all available commands
gws help

# Show help for specific command
gws gmail help
gws gmail search help

# Enable verbose/debug logging
gws --debug gmail search --query "..." --output json

# View authentication status
gws auth status

# Revoke current authentication
gws auth revoke

# Check API health
gws health check

# View recent logs
gws logs list --since "1 hour ago" --output json
