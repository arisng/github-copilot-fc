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

# sqlite3 -json emits pretty-printed multi-line JSON; piping it line-by-line
# into ConvertFrom-Json fails ("Additional text encountered..."), so buffer
# the raw output to a single string first. Empty results normalize to $null.
function Convert-SqliteJson {
    param([object]$raw)
    $text = if ($null -eq $raw) { "" } else { ($raw | Out-String).Trim() }
    if (-not $text) { return $null }
    ConvertFrom-Json -InputObject $text
}

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

$sessions = Convert-SqliteJson (sqlite3.exe -json $SessionDbPath $sessionsQuery 2>$null)

$hasSessions = $sessions -and $sessions.Count -gt 0

if (-not $hasSessions -and -not $IsRepo) {
    Write-Host "No sessions found in the last $Days day(s)."
    exit 0
}

if (-not $hasSessions) {
    # Repo present: still emit git/issue context so cross-check can source
    # commit-only work items and issue refs without session data.
    # stderr keeps stdout a clean single JSON object for redirect/pipeline consumers.
    [Console]::Error.WriteLine("No sessions found for this date; emitting git-only context for cross-check.")
}

$sessionIds = if ($hasSessions) {
    ($sessions | ForEach-Object { "'$($_.id)'" }) -join ","
} else {
    # Matches no rows; keeps the session queries valid SQL without branching
    "''"
}

# 2. Query first turn (user_message) per session for work description
$firstTurnsQuery = @"
SELECT t.session_id, t.turn_index, t.user_message, t.timestamp
FROM turns t
WHERE t.session_id IN ($sessionIds)
  AND t.turn_index = 0
ORDER BY t.session_id
"@
$firstTurns = Convert-SqliteJson (sqlite3.exe -json $SessionDbPath $firstTurnsQuery 2>$null)

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
$lastTurns = Convert-SqliteJson (sqlite3.exe -json $SessionDbPath $lastTurnsQuery 2>$null)

# 4. Query session files (modified/created files)
$filesQuery = @"
SELECT session_id, file_path, tool_name, turn_index
FROM session_files
WHERE session_id IN ($sessionIds)
ORDER BY session_id, turn_index
"@
$sessionFiles = Convert-SqliteJson (sqlite3.exe -json $SessionDbPath $filesQuery 2>$null)

# 5. Query session refs (PRs, issues, commits)
$refsQuery = @"
SELECT session_id, ref_type, ref_value, created_at
FROM session_refs
WHERE session_id IN ($sessionIds)
ORDER BY session_id, ref_type
"@
$sessionRefs = Convert-SqliteJson (sqlite3.exe -json $SessionDbPath $refsQuery 2>$null)

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

# 6b. Extract issue references from git commit subjects/bodies (source: git history).
# Uses one extra local git log pass with US/RS record separators; deduped by issue number.
$gitIssueRefs = @()
$candidateNumbers = @{}
$seenGitNumbers = @{}

if ($IsRepo) {
    $rawLog = (& git log --all --since="$gitSince" --format="%h%x1f%s%x1f%b%x1e" 2>$null) -join "`n"
    foreach ($record in [regex]::Split($rawLog, "\x1e")) {
        if (-not $record.Trim()) { continue }
        $parts = $record -split "\x1f"
        if ($parts.Count -lt 2) { continue }
        $sha = $parts[0].Trim()
        $subject = $parts[1].Trim()
        $body = if ($parts.Count -ge 3) { $parts[2] } else { "" }
        foreach ($m in [regex]::Matches("$subject`n$body", '(?<![\w/])#(\d+)\b')) {
            $num = $m.Groups[1].Value
            $candidateNumbers[$num] = $true
            if (-not $seenGitNumbers.ContainsKey($num)) {
                $seenGitNumbers[$num] = $true
                $gitIssueRefs += @{ number = [int]$num; sha = $sha; subject = $subject }
            }
        }
    }
}

# Session refs also seed issue candidates (source: Copilot session database)
foreach ($r in @($sessionRefs)) {
    if (-not $r) { continue }
    $val = "$($r.ref_value)"
    $num = $null
    if ($val -match '/issues/(\d+)') {
        $num = $matches[1]
    } elseif ("$($r.ref_type)" -match 'issue' -and $val -match '#?(\d+)$') {
        $num = $matches[1]
    }
    if ($num) { $candidateNumbers[$num] = $true }
}

$candidateList = @($candidateNumbers.Keys | ForEach-Object { [int]$_ } | Sort-Object)

# 6c. Resolve candidate issue details via gh CLI (source: gh CLI).
# Bounded and fail-soft: at most 10 calls, stops after 3 consecutive failures
# (auth/network down); PR numbers simply fail `gh issue view` and are skipped.
$issueDetails = @()
$ghCalls = 0
$maxGhCalls = 10
$consecutiveFailures = 0
$ghAvailable = [bool](Get-Command gh -ErrorAction SilentlyContinue)

if ($ghAvailable -and $IsRepo -and $candidateList.Count -gt 0) {
    foreach ($n in ($candidateList | Select-Object -First $maxGhCalls)) {
        $ghCalls++
        $ghOut = & gh issue view $n --json number,title,state,url 2>$null
        if ($LASTEXITCODE -eq 0 -and $ghOut) {
            $consecutiveFailures = 0
            try { $issueDetails += (Out-String -InputObject $ghOut | ConvertFrom-Json) } catch { }
        } else {
            $consecutiveFailures++
            if ($consecutiveFailures -ge 3) { break }
        }
    }
}

# Assemble output as structured JSON
# NOTE: if/else emitting an empty array unrolls to $null through the pipeline;
# normalize each collection afterwards so consumers always see [] not null.
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
    gitIssueRefs = if ($gitIssueRefs) { $gitIssueRefs } else { @() }
    issueCandidates = if ($candidateList) { $candidateList } else { @() }
    issueDetails = if ($issueDetails) { $issueDetails } else { @() }
    ghCalls = $ghCalls
}
foreach ($key in @('gitCommits', 'gitBranches', 'gitIssueRefs', 'issueCandidates', 'issueDetails', 'sessions')) {
    if ($null -eq $result[$key]) { $result[$key] = @() }
}

$sessionMap = @{}
foreach ($s in @($sessions)) {
    if (-not $s.id) { continue }
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

foreach ($t in @($firstTurns)) {
    if ($t -and $sessionMap.ContainsKey($t.session_id)) {
        $sessionMap[$t.session_id].firstMessage = $t.user_message
    }
}

foreach ($t in @($lastTurns)) {
    if ($t -and $sessionMap.ContainsKey($t.session_id)) {
        $sessionMap[$t.session_id].lastMessage = $t.user_message
        $sessionMap[$t.session_id].lastResponse = $t.assistant_response
    }
}

foreach ($f in @($sessionFiles)) {
    if ($f -and $sessionMap.ContainsKey($f.session_id)) {
        $sessionMap[$f.session_id].files += @{
            path = $f.file_path
            tool = $f.tool_name
            turn = $f.turn_index
        }
    }
}

foreach ($r in @($sessionRefs)) {
    if ($r -and $sessionMap.ContainsKey($r.session_id)) {
        $sessionMap[$r.session_id].refs += @{
            type = $r.ref_type
            value = $r.ref_value
            createdAt = $r.created_at
        }
    }
}

$sessionsOut = if ($hasSessions) {
    @($sessionMap.Values | Sort-Object -Property updatedAt -Descending)
} else {
    @()
}
if ($null -eq $sessionsOut) { $sessionsOut = @() }
$result.sessions = $sessionsOut

# Output as JSON
$result | ConvertTo-Json -Depth 10
