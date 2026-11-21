<#
.SYNOPSIS
  Single-day Copilot session evidence for the daily-report skill.
.DESCRIPTION
  Queries the Copilot session store for one calendar day, scoped to the
  repository of the current checkout, and emits structured JSON: sessions
  with first and last messages, files, and refs. Optionally merges
  cloud-store rows exported to JSON via -CloudJson; merged rows are refused
  unless they match the same day and repository. This skill owns every
  script it runs — nothing here depends on another skill's scripts.
.EXAMPLE
  .\Get-SessionEvidence.ps1 -Date '2026-11-10'
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Date,

    [string]$Start = "",

    [string]$End = "",

    [string]$RepoRoot = "",

    [string]$SessionDbPath = "$env:USERPROFILE\.copilot\session-store.db",

    [string]$CloudJson = "",

    [int]$UtcOffsetHours = [int][DateTimeOffset]::Now.Offset.TotalHours
)

$ErrorActionPreference = 'Stop'

# Day-scope guardrail: exactly one calendar day.
$parsedDay = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact($Date, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDay)) {
    Write-Error "Invalid -Date '$Date'. Use 'yyyy-MM-dd'."
    exit 1
}
$parsedStart = $parsedDay
$parsedEnd = $parsedDay.AddDays(1)
if ($Start -or $End) {
    $fmt = [string[]]@('yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss')
    $s = [DateTime]::MinValue; $e = [DateTime]::MinValue
    $sOk = $Start -and [DateTime]::TryParseExact($Start, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$s)
    $eOk = $End -and [DateTime]::TryParseExact($End, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$e)
    if (-not $sOk -or -not $eOk) {
        Write-Error "Invalid -Start/-End. Use 'yyyy-MM-dd HH:mm'."
        exit 1
    }
    if ($s.Date -ne $parsedDay -or ($e.Date -ne $parsedDay -and $e -ne $parsedDay.AddDays(1))) {
        Write-Error "day scope: -Start/-End must stay inside $Date."
        exit 1
    }
    $parsedStart = $s; $parsedEnd = $e
}

if (-not $RepoRoot) {
    $RepoRoot = (& git rev-parse --show-toplevel 2>$null)
}
if (-not $RepoRoot) {
    Write-Error 'repo scope: not inside a git repository and no -RepoRoot given.'
    exit 1
}

# Repo-scope guardrail: session evidence must match the current repository.
# The store keys GitHub checkouts as owner/name and Azure DevOps checkouts as
# org/project/repo; any other remote shape refuses rather than query unfiltered.
$remoteUrl = (& git -C $RepoRoot remote get-url origin 2>$null)
$repoFilter = ''
if ($remoteUrl -and $remoteUrl -match '(?:github\.com[/:])([^/]+)/([^/]+?)(?:\.git)?$') {
    $repoFilter = "$($matches[1])/$($matches[2])"
}
elseif ($remoteUrl -and $remoteUrl -match '(?:dev\.azure\.com[/:])v3/([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$') {
    $repoFilter = "$($matches[1])/$($matches[2])/$($matches[3])"
}
elseif ($remoteUrl -and $remoteUrl -match '(?:dev\.azure\.com[/:])([^/]+)/([^/]+)/_git/([^/]+?)(?:\.git)?$') {
    $repoFilter = "$($matches[1])/$($matches[2])/$($matches[3])"
}
if (-not $repoFilter) {
    Write-Error "repo scope: cannot resolve owner/name (GitHub) or org/project/repo (Azure DevOps) from remote '$remoteUrl'. Refusing an unfiltered query."
    exit 1
}

if (-not (Test-Path $SessionDbPath)) {
    Write-Error "Session store not found at: $SessionDbPath — state this grounding gap in the report."
    exit 1
}

# Membership rules — keep in sync with Get-SessionCoverage.ps1: a session
# grounds here by repository key OR by cwd under this checkout, so a store row
# whose repository key drifted (or was never recorded) is still caught.
# Escape char '@': with '\', Windows path backslashes would be consumed as
# escapes and match nothing.
$repoPathNorm = ($RepoRoot -replace '/', '\').TrimEnd('\').ToLowerInvariant()
$repoPathLike = ($repoPathNorm -replace '([%_@])', '@$1') + '\'

# Local store timestamps are UTC; convert the local-day bounds at runtime.
$utcStart = $parsedStart.AddHours(-$UtcOffsetHours)
$utcEnd = $parsedEnd.AddHours(-$UtcOffsetHours)
$utcStartStr = $utcStart.ToString('yyyy-MM-ddTHH:mm:ss')
$utcEndStr = $utcEnd.ToString('yyyy-MM-ddTHH:mm:ss')

$sessionsQuery = @"
SELECT DISTINCT s.id,
       COALESCE(s.branch, '') AS branch,
       COALESCE(s.summary, '') AS summary,
       COALESCE(s.repository, '') AS repository,
       s.created_at, s.updated_at
FROM sessions s
INNER JOIN turns t ON t.session_id = s.id
WHERE (s.repository = '$repoFilter'
       OR lower(replace(COALESCE(s.cwd, ''), '/', '\')) = '$repoPathNorm'
       OR lower(replace(COALESCE(s.cwd, ''), '/', '\')) LIKE '$repoPathLike%' ESCAPE '@')
  AND t.timestamp >= '$utcStartStr' AND t.timestamp < '$utcEndStr'
ORDER BY s.updated_at DESC
"@

# sqlite3 -json pretty-prints multi-row results across lines; join before
# parsing or ConvertFrom-Json chokes on the row separators.
function Invoke-SqliteJson([string]$Query) {
    # Bare `sqlite3`: resolves sqlite3.exe via PATHEXT on Windows and the
    # CLI on Linux/macOS (CI runners ship the plain name only).
    $raw = ((sqlite3 -json $SessionDbPath $Query 2>$null) -join "`n").Trim()
    if (-not $raw) { return @() }
    return @($raw | ConvertFrom-Json)
}

function Shorten([string]$Text, [int]$Max) {
    if (-not $Text) { return '' }
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -le $Max) { return $t }
    return $t.Substring(0, $Max) + '…'
}

$sessions = @(Invoke-SqliteJson $sessionsQuery)

$sessionList = @()
foreach ($s in $sessions) {
    $id = $s.id
    $first = Invoke-SqliteJson "SELECT user_message FROM turns WHERE session_id = '$id' ORDER BY turn_index LIMIT 1"
    $last = Invoke-SqliteJson "SELECT user_message, assistant_response FROM turns WHERE session_id = '$id' ORDER BY turn_index DESC LIMIT 1"
    $files = @(Invoke-SqliteJson "SELECT file_path, tool_name, turn_index FROM session_files WHERE session_id = '$id' ORDER BY turn_index")
    $refs = @(Invoke-SqliteJson "SELECT ref_type, ref_value FROM session_refs WHERE session_id = '$id'")
    $winRows = Invoke-SqliteJson "SELECT turn_index, timestamp, user_message, assistant_response FROM turns WHERE session_id = '$id' AND timestamp >= '$utcStartStr' AND timestamp < '$utcEndStr' ORDER BY turn_index"
    $windowTurns = @()
    foreach ($w in $winRows) {
        $windowTurns += [ordered]@{
            turn      = $w.turn_index
            ts        = $w.timestamp
            user      = (Shorten $w.user_message 180)
            assistant = (Shorten $w.assistant_response 320)
        }
    }
    $sessionList += [ordered]@{
        id            = $id
        branch        = $s.branch
        summary       = $s.summary
        repository    = $s.repository
        createdAt     = $s.created_at
        updatedAt     = $s.updated_at
        firstMessage  = if ($first) { $first.user_message } else { '' }
        lastMessage   = if ($last) { $last.user_message } else { '' }
        lastResponse  = if ($last) { $last.assistant_response } else { '' }
        files         = $files
        refs          = $refs
        windowTurns   = $windowTurns
    }
}

# Optional cloud-store merge: rows must match the same repo and day bounds.
$cloudMerged = 0
if ($CloudJson) {
    if (-not (Test-Path $CloudJson)) {
        Write-Error "CloudJson '$CloudJson' not found."
        exit 1
    }
    $cloud = @(Get-Content $CloudJson -Raw | ConvertFrom-Json)
    foreach ($c in $cloud) {
        if ($c.repository -ne $repoFilter) {
            Write-Error "repo scope: cloud row for '$($c.repository)' is outside '$repoFilter'. Refusing."
            exit 1
        }
        $ts = [DateTime]::MinValue
        if (-not [DateTime]::TryParse("$($c.updatedAt)", [ref]$ts) -or $ts -lt $utcStart -or $ts -ge $utcEnd) {
            Write-Error "day scope: cloud row '$($c.id)' falls outside $Date. Refusing."
            exit 1
        }
        if (-not ($sessionList | Where-Object { $_.id -eq $c.id })) {
            $sessionList += $c
            $cloudMerged++
        }
    }
}

[ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    day         = $Date
    utcStart    = $utcStartStr
    utcEnd      = $utcEndStr
    utcOffset   = "$UtcOffsetHours"
    repository  = $repoFilter
    sessionCount = $sessionList.Count
    cloudMerged = $cloudMerged
    sessions    = $sessionList
} | ConvertTo-Json -Depth 8
