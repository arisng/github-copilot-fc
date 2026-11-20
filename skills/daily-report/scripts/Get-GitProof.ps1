<#
.SYNOPSIS
  Git proof collector for the daily-report skill.
.DESCRIPTION
  Digs the requester's git history for one calendar day and emits
  structured JSON that the report uses as proof for its claims:
  per-commit files, line counts, branch containment, pushed-or-local state,
  plus git status for uncommitted work. Host checkpoint commits are
  excluded. Commit hashes are grounding only — the report never prints them.
  This skill owns every script it runs: no dependency on other skills.
  Auto-detected author and repository, single-day bounds, structured JSON out.
.EXAMPLE
  .\Get-GitProof.ps1 -Date '2026-11-10'
.EXAMPLE
  .\Get-GitProof.ps1 -Start '2026-11-10 13:00' -End '2026-11-10 18:00'
#>
param(
    [string]$Date = "",

    [string]$Start = "",

    [string]$End = "",

    [string]$Author = "",

    [string]$RepoRoot = ""
)

$ErrorActionPreference = 'Stop'

# Day-scope guardrail: grounding covers exactly one calendar day.
$fmt = [string[]]@('yyyy-MM-dd', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss')
$parsedDay = [DateTime]::MinValue
$parsedStart = [DateTime]::MinValue
$parsedEnd = [DateTime]::MinValue

if ($Date -and ($Start -or $End)) {
    Write-Error 'day scope: give either -Date or a same-day -Start/-End pair, not both.'
    exit 1
}
if ($Date) {
    if (-not [DateTime]::TryParseExact($Date, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDay)) {
        Write-Error "Invalid -Date '$Date'. Use 'yyyy-MM-dd'."
        exit 1
    }
    $parsedStart = $parsedDay
    $parsedEnd = $parsedDay.AddDays(1)
    $Start = $parsedStart.ToString('yyyy-MM-dd HH:mm')
    $End = $parsedStart.ToString('yyyy-MM-dd 23:59')
}
elseif ($Start -and $End) {
    $startOk = [DateTime]::TryParseExact($Start, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedStart)
    $endOk = [DateTime]::TryParseExact($End, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedEnd)
    if (-not $startOk -or -not $endOk) {
        Write-Error "Invalid -Start/-End. Use 'yyyy-MM-dd HH:mm' (local time, git parses it as-is)."
        exit 1
    }
    if ($parsedEnd -le $parsedStart) {
        Write-Error '-End must be after -Start.'
        exit 1
    }
    if ($parsedStart.Date -ne $parsedEnd.Date -and $parsedEnd -ne $parsedStart.Date.AddDays(1)) {
        Write-Error "day scope: -Start and -End must resolve to one calendar day; got '$($parsedStart.ToString('yyyy-MM-dd'))'..'$($parsedEnd.ToString('yyyy-MM-dd'))'. Multi-day coverage runs the per-day path once per day."
        exit 1
    }
}
else {
    Write-Error "day scope: pass -Date 'yyyy-MM-dd' or a same-day -Start/-End pair."
    exit 1
}

if (-not $RepoRoot) {
    $RepoRoot = (& git rev-parse --show-toplevel 2>$null)
}
if (-not $RepoRoot) {
    Write-Error 'Not inside a git repository and no -RepoRoot given.'
    exit 1
}

Push-Location $RepoRoot
try {
    # Attribution boundary: the requester's identity from Step 0.
    if (-not $Author) { $Author = (& git config user.email 2>$null) }
    if (-not $Author) { $Author = (& git config user.name 2>$null) }
    if (-not $Author) {
        Write-Error 'No author resolved. Pass -Author or set git config user.email.'
        exit 1
    }

    # One pass: author-filtered, window-bounded, all refs, no merge noise.
    # --numstat gives per-file line counts for every claim in the report.
    $raw = & git log --all --author="$Author" --since="$Start" --until="$End" `
        --no-merges --format='@@COMMIT@@|%H|%h|%ci|%s' --numstat 2>$null

    $commits = @()
    $noiseExcluded = 0
    $current = $null
    foreach ($line in @($raw)) {
        if ($line -like '@@COMMIT@@|*') {
            if ($current) { $commits += $current }
            $parts = $line -split '\|', 5
            $subject = if ($parts.Count -ge 5) { $parts[4] } else { '' }
            if ($subject -like 'Agent host session *') {
                # Host per-turn checkpoint commits: not the requester's work.
                $noiseExcluded++
                $current = $null
            }
            else {
                $current = [ordered]@{
                    hash         = $parts[1]
                    short        = $parts[2]
                    date         = $parts[3]
                    subject      = $subject
                    files        = @()
                    filesAdded   = 0
                    filesDeleted = 0
                    branches     = @()
                    pushed       = $false
                }
            }
        }
        elseif ($null -ne $current -and $line -match "`t") {
            $fields = $line -split "`t"
            if ($fields.Count -ge 3) {
                $add = $fields[0]; $del = $fields[1]
                $path = if ($fields.Count -gt 3) { ($fields[2..($fields.Count - 1)] -join ' => ') } else { $fields[2] }
                $current.files += [ordered]@{ add = $add; del = $del; path = $path }
                if ($add -match '^\d+$') { $current.filesAdded += [int]$add }
                if ($del -match '^\d+$') { $current.filesDeleted += [int]$del }
            }
        }
    }
    if ($current) { $commits += $current }

    # Branch containment and pushed state per commit (bounded: one window).
    # %(refname:short) renders remote-tracking branches as "origin/<branch>".
    foreach ($c in $commits) {
        $containing = @(& git branch -a --contains $c.hash --format='%(refname:short)' 2>$null)
        $c.pushed = [bool]($containing | Where-Object { $_ -like 'origin/*' } | Select-Object -First 1)
        $c.branches = @($containing | Where-Object { $_ -notlike 'origin/*' -and $_ -notmatch ' -> ' })
    }

    $status = @(git status --short 2>$null)

    # Working-tree activity: files created or modified inside the window that
    # carry no commit yet — new artifacts are invisible to git log.
    $workingTree = @()
    foreach ($row in $status) {
        if ($row.Length -lt 4) { continue }
        $path = $row.Substring(3)
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        $path = $path.Trim('"')
        $full = Join-Path $RepoRoot $path
        $candidates = @()
        if (Test-Path $full -PathType Container) {
            $candidates = @(Get-ChildItem $full -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 100)
        }
        elseif (Test-Path $full -PathType Leaf) {
            $candidates = @(Get-Item $full)
        }
        foreach ($it in $candidates) {
            if ($it.LastWriteTime -ge $parsedStart -and $it.LastWriteTime -lt $parsedEnd) {
                $rel = $it.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
                $workingTree += [ordered]@{ path = $rel; modified = $it.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
            }
        }
    }

    $recentBranches = @(git branch --sort=-committerdate --format='%(refname:short)' 2>$null | Select-Object -First 10)

    [ordered]@{
        generatedAt    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        windowStart    = $Start
        windowEnd      = $End
        author         = $Author
        repoRoot       = "$RepoRoot"
        commitCount    = $commits.Count
        noiseExcluded  = $noiseExcluded
        commits        = $commits
        status         = $status
        workingTree    = $workingTree
        workingTreeCount = $workingTree.Count
        recentBranches = $recentBranches
    } | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
