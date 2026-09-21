param(
    [int]$Days = 1,
    [string]$Date = "",
    [int]$UtcOffsetHours = 7,
    [string]$Author = "",
    [string]$SessionDbPath = "$env:USERPROFILE\.copilot\session-store.db",
    [string]$RepoRoot = (Get-Location).Path
)

# Detect whether CWD is inside a git repository
$IsRepo = $false
$remoteUrl = ""
$RepoFilter = ""

$gitDir = & git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -eq 0 -and $gitDir) {
    $IsRepo = $true

    # Auto-detect author from git if not provided
    if (-not $Author) {
        $Author = & git config user.name 2>$null
    }

    # Auto-detect repository from git remote
    $remoteUrl = & git remote get-url origin 2>$null
    if ($remoteUrl) {
        if ($remoteUrl -match '(?:github\.com[/:])([^/]+)/([^/]+?)(?:\.git)?$') {
            $RepoFilter = "$($matches[1])/$($matches[2])"
        }
    }
}

# Fallback author when not in a repo or git config unavailable
if (-not $Author) { $Author = $env:USERNAME }

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SessionDbPath)) {
    Write-Error "Session store not found at: $SessionDbPath"
    exit 1
}

# Determine date filter — either relative (-Days) or explicit (-Date)
# Default timezone is UTC+7; override with -UtcOffsetHours
if ($Date) {
    # Explicit calendar date in UTC+7 (e.g. "2026-07-06")
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($Date, "yyyy-MM-dd", [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        Write-Error "Invalid date format. Use yyyy-MM-dd (e.g. 2026-07-06)"
        exit 1
    }
    # Treat date as midnight UTC+7 → UTC range
    $utcStart = $parsed.AddHours(-$UtcOffsetHours)
    $utcEnd = $utcStart.AddDays(1)
    $dateFilter = $utcStart.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $dateFilterEnd = $utcEnd.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $filterLabel = $Date
} else {
    # Relative: compute today's UTC+7 midnight, then go back N days
    $nowUtc = (Get-Date).ToUniversalTime()
    $nowInTargetZone = $nowUtc.AddHours($UtcOffsetHours)
    $todayMidnightTargetZone = $nowInTargetZone.Date
    $utcStart = $todayMidnightTargetZone.AddHours(-$UtcOffsetHours).AddDays(-$Days)
    $dateFilter = $utcStart.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $dateFilterEnd = ""
    $filterLabel = "last $Days day(s)"
}

$repoClause = if ($RepoFilter) { "AND s.repository = '$RepoFilter'" } else { "" }
$timeClause = if ($dateFilterEnd) {
    "AND t.timestamp >= '$dateFilter' AND t.timestamp < '$dateFilterEnd'"
} else {
    "AND t.timestamp >= '$dateFilter'"
}

$sessionsQuery = @"
SELECT DISTINCT
    s.id,
    COALESCE(s.branch, '') AS branch,
    COALESCE(s.summary, '') AS summary,
    COALESCE(s.repository, '') AS repository,
    s.created_at,
    s.updated_at
FROM sessions s
INNER JOIN turns t ON s.id = t.session_id
WHERE 1=1
$repoClause
$timeClause
ORDER BY s.created_at DESC
"@

$sessions = sqlite3.exe -json $SessionDbPath $sessionsQuery 2>$null | ConvertFrom-Json

if (-not $sessions -or $sessions.Count -eq 0) {
    Write-Host "No sessions found in the last $Days day(s)."
    exit 0
}

$sessionIds = ($sessions | ForEach-Object { "'$($_.id)'" }) -join ","

# 2. Query first turn (user_message) per session for work description
$firstTurnsQuery = @"
SELECT t.session_id, t.turn_index, t.user_message, t.timestamp
FROM turns t
WHERE t.session_id IN ($sessionIds)
  AND t.turn_index = 0
ORDER BY t.session_id
"@
$firstTurns = sqlite3.exe -json $SessionDbPath $firstTurnsQuery 2>$null | ConvertFrom-Json

# 3. Query last turn (user_message + assistant_response) per session for status
$lastTurnsQuery = @"
SELECT t1.session_id, t1.turn_index, t1.user_message, t1.assistant_response, t1.timestamp
FROM turns t1
INNER JOIN (
    SELECT session_id, MAX(turn_index) AS max_turn
    FROM turns
    WHERE session_id IN ($sessionIds)
    GROUP BY session_id
) t2 ON t1.session_id = t2.session_id AND t1.turn_index = t2.max_turn
ORDER BY t1.session_id
"@
$lastTurns = sqlite3.exe -json $SessionDbPath $lastTurnsQuery 2>$null | ConvertFrom-Json

# 4. Query session files (modified/created files)
$filesQuery = @"
SELECT session_id, file_path, tool_name, turn_index
FROM session_files
WHERE session_id IN ($sessionIds)
ORDER BY session_id, turn_index
"@
$sessionFiles = sqlite3.exe -json $SessionDbPath $filesQuery 2>$null | ConvertFrom-Json

# 5. Query session refs (PRs, issues, commits)
$refsQuery = @"
SELECT session_id, ref_type, ref_value, created_at
FROM session_refs
WHERE session_id IN ($sessionIds)
ORDER BY session_id, ref_type
"@
$sessionRefs = sqlite3.exe -json $SessionDbPath $refsQuery 2>$null | ConvertFrom-Json

# 6. Get recent git commits (only when in a git repo)
$gitLog = @()
$gitBranches = @()

if ($IsRepo) {
    $gitSince = if ($Date) {
        $parsed.ToString("yyyy-MM-dd")
    } else {
        $utcStart.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $gitLog = & git log --all --oneline --since="$gitSince" --format="%h %s" 2>$null
    $gitBranches = & git branch --sort=-committerdate 2>$null | ForEach-Object { $_.Trim() }
}

# Assemble output as structured JSON
$result = @{
    generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    dateFilter = $dateFilter
    dateFilterEnd = $dateFilterEnd
    filterLabel = $filterLabel
    days = $Days
    repoRoot = $RepoRoot
    isRepo = $IsRepo
    repoFilter = $RepoFilter
    remoteUrl = $remoteUrl
    author = $Author
    sessions = @()
    gitCommits = if ($gitLog) { $gitLog } else { @() }
    gitBranches = if ($gitBranches) { $gitBranches } else { @() }
}

$sessionMap = @{}
foreach ($s in $sessions) {
    $sessionMap[$s.id] = @{
        id = $s.id
        branch = $s.branch
        summary = $s.summary
        repository = $s.repository
        createdAt = $s.created_at
        updatedAt = $s.updated_at
        firstMessage = ""
        lastMessage = ""
        lastResponse = ""
        files = @()
        refs = @()
    }
}

foreach ($t in $firstTurns) {
    if ($sessionMap.ContainsKey($t.session_id)) {
        $sessionMap[$t.session_id].firstMessage = $t.user_message
    }
}

foreach ($t in $lastTurns) {
    if ($sessionMap.ContainsKey($t.session_id)) {
        $sessionMap[$t.session_id].lastMessage = $t.user_message
        $sessionMap[$t.session_id].lastResponse = $t.assistant_response
    }
}

foreach ($f in $sessionFiles) {
    if ($sessionMap.ContainsKey($f.session_id)) {
        $sessionMap[$f.session_id].files += @{
            path = $f.file_path
            tool = $f.tool_name
            turn = $f.turn_index
        }
    }
}

foreach ($r in $sessionRefs) {
    if ($sessionMap.ContainsKey($r.session_id)) {
        $sessionMap[$r.session_id].refs += @{
            type = $r.ref_type
            value = $r.ref_value
            createdAt = $r.created_at
        }
    }
}

$result.sessions = $sessionMap.Values | Sort-Object -Property updatedAt -Descending

# Output as JSON
$result | ConvertTo-Json -Depth 10
