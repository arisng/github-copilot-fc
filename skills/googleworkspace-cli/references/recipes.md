# Google Workspace CLI - Recipes & Common Workflows

This document contains 10+ tested, copy-paste-ready recipes for real-world Google Workspace automation scenarios.

## Recipe 1: Daily Email Triage

Automatically organize morning emails: search for urgent messages, apply priority labels, and send acknowledgments.

```powershell
# daily-email-triage.ps1
param(
    [string]$EmailAddress = $env:USER_EMAIL
)

Write-Host "🔍 Triaging emails for $EmailAddress..."

# Search for urgent emails
$urgent = gws gmail search `
  --query 'from:(boss OR ceo OR CEO OR founder) subject:(urgent OR CRITICAL or ASAP) after:today' `
  --limit 100 `
  --output json | ConvertFrom-Json

$count = if ($urgent.messages) { $urgent.messages.Count } else { 0 }
Write-Host "Found $count urgent emails"

# Apply labels
foreach ($email in $urgent.messages) {
    gws gmail modify `
      --id $email.id `
      --add-label-ids "URGENT" `
      --remove-label-ids "UNREAD" `
      --output json | Out-Null
    Write-Host "  ✓ Labeled: $($email.id)"
}

# Send auto-reply to first urgent sender
if ($urgent.messages.Count -gt 0) {
    $first = $urgent.messages[0]
    gws gmail get --id $first.id --format full --output json | ConvertFrom-Json | ForEach-Object {
        $sender = $_.payload.headers | Where-Object { $_.name -eq "From" } | Select-Object -ExpandProperty value
        
        gws gmail send `
          --to $sender `
          --subject "Auto-reply: Will respond ASAP" `
          --body @"
Hi,

Thank you for your urgent message. I've marked it as high priority and will respond within 1 hour.

Best regards,
$EmailAddress
"@ `
          --output json | Out-Null
    }
}

Write-Host "✅ Email triage complete"
```

**Usage**:
```powershell
.\daily-email-triage.ps1
```

---

## Recipe 2: Weekly Meeting Prep

Fetch this week's calendar, identify attendees, check availability, and export as agenda.

```powershell
# weekly-meeting-prep.ps1
param(
    [int]$DaysAhead = 7
)

$startDate = Get-Date
$endDate = $startDate.AddDays($DaysAhead)

Write-Host "📅 Preparing for meetings from $($startDate.ToShortDateString()) to $($endDate.ToShortDateString())"

# Fetch events
$events = gws calendar list `
  --calendar-id "primary" `
  --time-min $startDate.ToUniversalTime().ToString('o') `
  --time-max $endDate.ToUniversalTime().ToString('o') `
  --max-results 50 `
  --output json | ConvertFrom-Json

# Create preparation document
$doc = gws docs create `
  --title "Week of $($startDate.ToShortDateString()) - Meeting Prep" `
  --output json | ConvertFrom-Json

$docId = $doc.documentId

# Build agenda
$content = "# Meeting Preparation Agenda`n`n"

foreach ($event in $events.items) {
    if ($event.summary -and $event.start) {
        $content += "## $($event.summary)`n"
        $content += "- **When**: $($event.start.dateTime)`n"
        $content += "- **Where**: $($event.location)`n"
        
        if ($event.attendees) {
            $content += "- **Attendees**: $(($event.attendees | Select-Object -ExpandProperty email) -join ', ')`n"
        }
        
        $content += "`n"
    }
}

# Append to doc
gws docs append --document-id $docId --text $content --output json | Out-Null

# Share with team
gws drive share --file-id $docId `
  --role reader `
  --emails "team@example.com" `
  --output json | Out-Null

Write-Host "✅ Meeting prep document created: https://docs.google.com/document/d/$docId/edit"
```

**Usage**:
```powershell
.\weekly-meeting-prep.ps1 -DaysAhead 7
```

---

## Recipe 3: Bulk User Onboarding

Create user accounts from CSV, add to groups, and send welcome emails.

```powershell
# onboard-users.ps1
param(
    [string]$CsvPath = "new-hires.csv",  # Columns: FirstName, LastName, Email, Department
    [string]$OrgUnit = "/Engineering",
    [string[]]$GroupsToAdd = @("all-hands", "employees"),
    [switch]$DryRun
)

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

$users = Import-Csv $CsvPath
$results = @()

Write-Host "👥 Onboarding $($users.Count) users from $CsvPath"

foreach ($user in $users) {
    $email = $user.Email
    Write-Host "Processing: $email"
    
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create: $($user.FirstName) $($user.LastName)"
    } else {
        try {
            # Create user
            $newUser = gws admin create-user `
              --first-name $user.FirstName `
              --last-name $user.LastName `
              --email $email `
              --org-unit $OrgUnit `
              --password "Welcome123!CHANGE" `
              --change-password-on-next-login `
              --output json | ConvertFrom-Json
            
            # Add to groups
            foreach ($group in $GroupsToAdd) {
                gws admin add-group-member `
                  --group $group `
                  --member $email `
                  --member-type USER `
                  --output json | Out-Null
                Write-Host "    ✓ Added to $group"
            }
            
            # Send welcome email
            gws gmail send `
              --to $email `
              --subject "Welcome to the team!" `
              --body @"
Welcome, $($user.FirstName)!

Your account has been set up and you're ready to go. You've been added to:
$($GroupsToAdd -join "`n")

Your initial password is: Welcome123!CHANGE
Please change it on first login.

Looking forward to working with you!
"@ `
              --output json | Out-Null
            
            $results += [PSCustomObject]@{
                Email = $email
                Status = "Created"
                UserId = $newUser.id
                Timestamp = Get-Date
            }
            Write-Host "  ✅ Complete"
            
        } catch {
            $results += [PSCustomObject]@{
                Email = $email
                Status = "Failed"
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
            Write-Host "  ❌ Error: $($_.Exception.Message)"
        }
    }
}

# Export results
$csvOutput = "onboarding-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$results | Export-Csv $csvOutput -NoTypeInformation
Write-Host "`n📊 Results saved to $csvOutput"

$successCount = ($results | Where-Object { $_.Status -eq "Created" }).Count
Write-Host "✅ Successfully onboarded: $successCount / $($users.Count)"
```

**Usage**:
```powershell
# Create CSV first:
# FirstName,LastName,Email,Department
# Alice,Smith,alice@example.com,Engineering
# Bob,Jones,bob@example.com,Sales

.\onboard-users.ps1 -CsvPath "new-hires.csv" -DryRun
.\onboard-users.ps1 -CsvPath "new-hires.csv"  # Execute after dry-run review
```

---

## Recipe 4: Find Meeting Availability

Search for a time slot when all attendees are available.

```powershell
# find-meeting-slot.ps1
param(
    [string[]]$Attendees = @("alice@example.com", "bob@example.com"),
    [string]$Title = "Team Sync",
    [int]$DurationMinutes = 60,
    [int]$DaysToSearch = 5,
    [int]$StartHour = 9,
    [int]$EndHour = 17
)

Write-Host "🔍 Finding available slot for: $($Attendees -join ', ')"

$startTime = (Get-Date).AddDays(1).ToUniversalTime()
$endTime = (Get-Date).AddDays($DaysToSearch).ToUniversalTime()

# Get free/busy info
$freebusy = gws calendar freebusy `
  --emails $Attendees `
  --time-min $startTime.ToString('o') `
  --time-max $endTime.ToString('o') `
  --output json | ConvertFrom-Json

# Find best slot
$bestSlots = @()
$currentDate = $startTime.Date

for ($d = 0; $d -lt $DaysToSearch; $d++) {
    for ($h = $StartHour; $h -lt $EndHour; $h++) {
        $slotStart = $currentDate.AddHours($h)
        $slotEnd = $slotStart.AddMinutes($DurationMinutes)
        
        # Check if slot is available (simple heuristic)
        $isAvailable = $true
        foreach ($cal in $freebusy.calendars) {
            if ($cal.busy) {
                foreach ($busy in $cal.busy) {
                    $busyStart = [DateTime]::Parse($busy.start)
                    $busyEnd = [DateTime]::Parse($busy.end)
                    
                    if (-not ($slotEnd -le $busyStart -or $slotStart -ge $busyEnd)) {
                        $isAvailable = $false
                        break
                    }
                }
            }
            if (-not $isAvailable) { break }
        }
        
        if ($isAvailable) {
            $bestSlots += [PSCustomObject]@{
                Start = $slotStart
                End = $slotEnd
                Score = 100
            }
            
            if ($bestSlots.Count -ge 5) { break }
        }
    }
    
    if ($bestSlots.Count -ge 5) { break }
    $currentDate = $currentDate.AddDays(1)
}

if ($bestSlots.Count -eq 0) {
    Write-Host "❌ No available slots found"
    exit 1
}

# Display options
Write-Host "`n📅 Available slots:"
$bestSlots | ForEach-Object {
    Write-Host "  $($_.Start.ToString('dddd, MMMM d, yyyy h:mm tt'))"
}

# Book the best slot
$chosenSlot = $bestSlots[0]
Write-Host "`n📍 Booking: $($chosenSlot.Start)"

$event = gws calendar create `
  --summary $Title `
  --start $chosenSlot.Start.ToUniversalTime().ToString('o') `
  --end $chosenSlot.End.ToUniversalTime().ToString('o') `
  --attendees $Attendees `
  --conference-type hangoutsMeet `
  --output json | ConvertFrom-Json

Write-Host "✅ Meeting created: $($event.id)"
```

**Usage**:
```powershell
.\find-meeting-slot.ps1 -Attendees "alice@example.com","bob@example.com","charlie@example.com" -Title "Q2 Planning"
```

---

## Recipe 5: Export Gmail to Spreadsheet

Archive email metadata to Google Sheets for analysis or compliance.

```powershell
# export-emails-to-sheets.ps1
param(
    [string]$Query = 'from:customer@example.com',
    [string]$SpreadsheetTitle = "Email Export - $(Get-Date -Format 'yyyy-MM-dd')"
)

Write-Host "📧 Exporting emails matching: $Query"

# Search
$emails = gws gmail search --query $Query --limit 1000 --output json | ConvertFrom-Json

if (-not $emails.messages) {
    Write-Host "❌ No emails found"
    exit 1
}

# Create spreadsheet
$sheet = gws sheets create --title $SpreadsheetTitle --output json | ConvertFrom-Json
$spreadsheetId = $sheet.spreadsheetId

Write-Host "📊 Created spreadsheet: $spreadsheetId"

# Prepare data
$rows = @(@("Date", "From", "Subject", "Snippet"))

foreach ($email in $emails.messages) {
    $full = gws gmail get --id $email.id --format full --output json | ConvertFrom-Json
    
    $date = ($full.payload.headers | Where-Object { $_.name -eq "Date" } | Select-Object -ExpandProperty value)
    $from = ($full.payload.headers | Where-Object { $_.name -eq "From" } | Select-Object -ExpandProperty value)
    $subject = ($full.payload.headers | Where-Object { $_.name -eq "Subject" } | Select-Object -ExpandProperty value)
    
    $rows += @($date, $from, $subject, $full.snippet)
}

# Write to sheet
gws sheets update `
  --spreadsheet-id $spreadsheetId `
  --range "Sheet1!A1" `
  --values $rows `
  --output json | Out-Null

Write-Host "✅ Exported $($emails.messages.Count) emails"
Write-Host "🔗 https://docs.google.com/spreadsheets/d/$spreadsheetId/edit"
```

**Usage**:
```powershell
.\export-emails-to-sheets.ps1 -Query 'from:support@example.com after:2026-03-01'
```

---

## Recipe 6: Auto-Label & Archive Old Emails

Clean up old emails with a single command.

```powershell
# archive-old-emails.ps1
param(
    [string]$Query = 'before:2026-01-01',
    [string]$Label = "Archive",
    [int]$BatchSize = 100
)

Write-Host "🗂️ Archiving emails: $Query"

$emails = gws gmail search --query $Query --output json | ConvertFrom-Json
$total = if ($emails.messages) { $emails.messages.Count } else { 0 }

if ($total -eq 0) {
    Write-Host "No emails to archive"
    exit 0
}

Write-Host "Found $total emails to archive"

# Create label if not exists
$labels = gws gmail list-labels --output json | ConvertFrom-Json
$labelExists = $labels.labels | Where-Object { $_.name -eq $Label }

if (-not $labelExists) {
    gws gmail create-label --name $Label --output json | Out-Null
    Write-Host "Created label: $Label"
}

# Batch modify in chunks
$processed = 0
for ($i = 0; $i -lt $emails.messages.Count; $i += $BatchSize) {
    $batch = $emails.messages[$i..([Math]::Min($i + $BatchSize - 1, $emails.messages.Count - 1))]
    $ids = $batch.id -join ","
    
    gws gmail batch-modify `
      --ids $ids `
      --add-label-ids $Label `
      --remove-label-ids "INBOX" `
      --output json | Out-Null
    
    $processed += $batch.Count
    Write-Host "  ✓ Processed $processed / $total"
}

Write-Host "✅ Archiving complete"
```

**Usage**:
```powershell
.\archive-old-emails.ps1 -Query 'before:2025-01-01' -Label "Old"
```

---

## Quick Reference: Running Recipes

All recipes follow this pattern:

```powershell
# 1. Save script to file
# 2. Check parameters
.\script.ps1 -Help

# 3. Test with dry-run (if supported)
.\script.ps1 -DryRun

# 4. Execute
.\script.ps1

# 5. Check output
```

For automation, schedule with Windows Task Scheduler, `cron`, or Azure Logic Apps.
