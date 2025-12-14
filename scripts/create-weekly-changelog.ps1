param(
    [string]$SinceDate = $null,
    [string]$UntilDate = $null,
    [string]$OutputStructure = "raw"
)

# Compute date range if not specified (for weekly)
if (-not $SinceDate -and -not $UntilDate) {
    $t = Get-Date
    $daysToMonday = (([int]$t.DayOfWeek - [int][System.DayOfWeek]::Monday) + 7) % 7
    $monday = $t.AddDays(-$daysToMonday).Date
    $sunday = $monday.AddDays(6)
}
else {
    $monday = [datetime]::Parse($SinceDate)
    $sunday = [datetime]::Parse($UntilDate)
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$calendar = $culture.Calendar
$week = $calendar.GetWeekOfYear($monday, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
$year = $monday.Year
$weekPadded = '{0:D2}' -f $week
$dirPath = Join-Path -Path (Get-Location) -ChildPath ".docs/changelogs"
if (-not (Test-Path -Path $dirPath)) { New-Item -ItemType Directory -Path $dirPath -Force | Out-Null }

# Build file path
$fileName = "w${weekPadded}_$($OutputStructure).md"
$filePath = Join-Path -Path $dirPath -ChildPath $fileName

# Build header
$startLabel = $monday.ToString("MMMM dd")
$endLabel = $sunday.ToString("dd")
$rangeLabel = "$startLabel-$endLabel, Week $week, $year"
if ($OutputStructure -eq "raw") {
    $header = "# Raw Changelog: $rangeLabel`n`n## Commits`n`n"
}
else {
    $header = "# Changelog: $rangeLabel`n`n### Added`n`n### Changed`n`n### Fixed`n`n"
}

# Get commits
$since = $monday.ToString("yyyy-MM-dd") + " 00:00:00"
$until = $sunday.ToString("yyyy-MM-dd") + " 23:59:59"

# Exclude commits that modify the changelog files themselves and those mentioning changelog in the commit message (case-insensitive)
if ($OutputStructure -eq "raw") {
    $format = "%an | %ad | %B"
}
else {
    $format = "%an | %ad | %s"
}
$gitArgs = @("log", "--since=$since", "--until=$until", "--pretty=format:$format", "--date=short", "--", ".", ":(exclude)_docs/changelogs")

$commits = & git @gitArgs 2>$null | Where-Object { $_ -notmatch "(?i)changelog" }

# Build content
if (-not $commits -or $commits.Count -eq 0) {
    $content = $header + "`nNo changes found for this period.`n"
}
else {
    $content = $header + ($commits -join "`n") + "`n"
}

# Write to file (overwrite)
Set-Content -Path $filePath -Value $content -Encoding UTF8

Write-Output "Created $filePath"
