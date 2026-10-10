#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pure, I/O-free helpers for the triage skill.

.DESCRIPTION
    Dot-sourced by triage-signals.ps1 and by tests/triage-signals.Tests.ps1 so the
    parsing and signal-derivation logic has exactly one definition. Nothing here
    touches the network or GitHub.

    Kept free of `$script:` state on purpose: dot-sourcing from two different
    callers makes script-scoped variables ambiguous.
#>

function Get-FormSection {
    <#
    Value of a rendered issue-form field: the lines under its "### Heading" marker.

    Written without `break`/`continue` on purpose: Pester 6 aborts a whole run when a
    loop-control statement escapes from a function called inside a test block
    (https://github.com/pester/Pester/issues/2669).
    #>
    param([string]$Body, [string]$Heading)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }

    $sections = @{}
    $current = $null
    foreach ($line in ($Body -split '\r?\n')) {
        $isHeading = ($line -match '^###\s+(.+?)\s*$')
        if ($isHeading) {
            $current = $Matches[1]
            if (-not $sections.ContainsKey($current)) { $sections[$current] = @() }
        }
        elseif ($current) {
            $sections[$current] += $line
        }
    }

    if ($sections.ContainsKey($Heading)) {
        $text = (($sections[$Heading]) -join "`n").Trim()
        if ($text) { return $text }
    }
    return $null
}

function Get-ProposedPriority {
    param(
        [string]$Body,
        [string]$Heading = 'Priority',
        [string[]]$Codes = @('P0', 'P1', 'P2', 'P3')
    )
    $section = Get-FormSection -Body $Body -Heading $Heading
    if (-not $section) { return $null }
    # Match any configured priority code as a whole token, longest-first so a shorter
    # code can never match inside a longer one (e.g. "P1" inside "P10").
    $alt = (@($Codes | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|')
    if (-not $alt) { return $null }
    if ($section -match "(?<!\w)($alt)(?!\w)") { return $Matches[1] }
    return $null
}

function Get-ProposedArea {
    param([string]$Body, [string]$Heading = 'Area')
    $section = Get-FormSection -Body $Body -Heading $Heading
    if (-not $section) { return $null }
    $areas = @($section -split '[,\r\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($areas.Count -gt 0) { return $areas }
    return $null
}

function Get-AgeDays {
    <# Whole days elapsed, floored, computed in UTC. Returns $null for garbage input. #>
    param([string]$CreatedAt, [datetime]$Reference = [datetime]::UtcNow)
    if ([string]::IsNullOrWhiteSpace($CreatedAt)) { return $null }
    try { $created = ([datetimeoffset]$CreatedAt).UtcDateTime }
    catch { return $null }
    return [int][Math]::Floor(($Reference - $created).TotalDays)
}

function Get-DueInfo {
    param(
        [string]$Body,
        [datetime]$Reference = [datetime]::UtcNow,
        [string]$Pattern = '\*\*Due:\*\*\s*(\d{4}-\d{2}-\d{2})'
    )
    if ([string]::IsNullOrWhiteSpace($Body) -or [string]::IsNullOrWhiteSpace($Pattern)) { return $null }
    try { $m = [regex]::Match($Body, $Pattern) }
    catch { return $null }
    if (-not $m.Success -or $m.Groups.Count -lt 2) { return $null }
    $raw = $m.Groups[1].Value
    # Prefer the canonical yyyy-MM-dd; fall back to a culture-invariant parse so a repo
    # using a different date format in its due marker still resolves.
    $due = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($raw, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$due)) {
        if (-not [datetime]::TryParse($raw, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$due)) { return $null }
    }
    $days = [int]($Reference.Date - $due.Date).TotalDays
    return [pscustomobject]@{
        due          = $raw
        days_overdue = if ($days -gt 0) { $days } else { 0 }
        is_overdue   = ($days -gt 0)
    }
}

function Get-IssueRefs {
    <# Every `#N` mention, whatever its context. #>
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @() }
    $refs = @([regex]::Matches($Body, '(?<![`\w])#(\d+)\b') | ForEach-Object { [int]$_.Groups[1].Value })
    return @($refs | Select-Object -Unique)
}

function Get-DependencyRefs {
    <#
    Only references in an actual dependency context ("Depends on #N" / "Blocked by #N").
    Deliberately narrower than Get-IssueRefs: a "Map: #27" or "Related: #19" mention is
    context, not a blocker, and must not drive the blocked-label invariant.
    #>
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @() }
    $refs = @()
    foreach ($m in [regex]::Matches($Body, '(?i)(?:depends\s+on|blocked\s+by)\W{0,10}(#\d+(?:[\s,]+#\d+)*)')) {
        $refs += @([regex]::Matches($m.Groups[1].Value, '#(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
    }
    return @($refs | Select-Object -Unique)
}

function Get-RoadmapRefs {
    param([string]$Body, [string]$Pattern = '\b(R\d+[a-z]?)\b')
    if ([string]::IsNullOrWhiteSpace($Body) -or [string]::IsNullOrWhiteSpace($Pattern)) { return @() }
    try { $matches = [regex]::Matches($Body, $Pattern) }
    catch { return @() }
    $refs = @($matches | ForEach-Object {
        if ($_.Groups.Count -gt 1) { $_.Groups[1].Value } else { $_.Groups[0].Value }
    })
    return @($refs | Select-Object -Unique)
}

function Get-GoalRefs {
    param([string]$Body, [string]$Pattern = '\b(G[1-5])\b')
    if ([string]::IsNullOrWhiteSpace($Body) -or [string]::IsNullOrWhiteSpace($Pattern)) { return @() }
    try { $matches = [regex]::Matches($Body, $Pattern) }
    catch { return @() }
    $refs = @($matches | ForEach-Object {
        if ($_.Groups.Count -gt 1) { $_.Groups[1].Value } else { $_.Groups[0].Value }
    })
    return @($refs | Select-Object -Unique)
}

function Test-RegexPattern {
    <#
    True when $Pattern compiles AND contains at least one capture group (the due/
    roadmap/goal extractors read Groups[1]). A null/empty pattern is "valid but
    disabled" and returns $true so callers can treat it uniformly.
    #>
    param([string]$Pattern)
    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $true }
    try {
        $rx = [regex]::new($Pattern)
        return ($rx.GetGroupNumbers().Count -gt 1)
    }
    catch { return $false }
}

function Get-SignificantTokens {
    <# Title tokens worth comparing for duplicate detection. #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $stop = @(
        'implementation', 'implement', 'task', 'bug', 'feature', 'plan', 'map',
        'wayfinder', 'with', 'from', 'that', 'this', 'into', 'when', 'then',
        'fix', 'add', 'update', 'make', 'using', 'based', 'core', 'v1'
    )
    $tokens = @($Text.ToLower() -split '[^a-z0-9]+' |
        Where-Object { $_.Length -ge 4 -and $stop -notcontains $_ })
    return @($tokens | Select-Object -Unique)
}

function Get-DedupCandidates {
    <# Pairs of open issues sharing >= 2 significant title tokens. #>
    param($Issues)
    $open = @($Issues | Where-Object { $_.state -eq 'OPEN' })
    $tokenMap = @{}
    foreach ($i in $open) { $tokenMap[[int]$i.number] = Get-SignificantTokens $i.title }

    $candidates = @()
    for ($a = 0; $a -lt $open.Count; $a++) {
        for ($b = $a + 1; $b -lt $open.Count; $b++) {
            $shared = @($tokenMap[[int]$open[$a].number] |
                Where-Object { $tokenMap[[int]$open[$b].number] -contains $_ })
            if ($shared.Count -ge 2) {
                $candidates += [pscustomobject]@{
                    a            = [int]$open[$a].number
                    b            = [int]$open[$b].number
                    shared_terms = $shared
                }
            }
        }
    }
    return $candidates
}

# ─── taxonomy: the per-repo label model ──────────────────────────────────────
#
# The triage skill reasons about abstract concepts (an untriaged marker, a blocked
# marker, an ordered priority axis, area/type tag families). Each GitHub repo maps
# those concepts onto its OWN label names. Get-DefaultTaxonomy is the built-in
# baseline (FinOps); a per-repo JSON config overlays it via Merge-Taxonomy; and
# Resolve-Taxonomy validates the result against the repo's real labels so a config
# that references a missing label is reported rather than silently ignored.

function Get-DefaultTaxonomy {
    <#
    The built-in baseline taxonomy. Every repo starts here so the skill works with
    zero configuration; a config file only needs to specify what differs.
    #>
    return [pscustomobject]@{
        needs_triage          = 'needs-triage'
        blocked               = 'blocked'
        owner_decision        = 'owner-decision'
        priority_prefix       = 'priority:'
        priority_levels       = @(
            [pscustomobject]@{ code = 'P0'; label = 'priority:P0'; meaning = 'Emergency - drop everything' }
            [pscustomobject]@{ code = 'P1'; label = 'priority:P1'; meaning = 'This cycle - blocks a goal or roadmap item' }
            [pscustomobject]@{ code = 'P2'; label = 'priority:P2'; meaning = 'Scheduled - important, not blocking' }
            [pscustomobject]@{ code = 'P3'; label = 'priority:P3'; meaning = 'Backlog - nice to have' }
        )
        area_prefix           = 'area:'
        type_prefix           = 'type:'
        form_priority_heading = 'Priority'
        form_area_heading     = 'Area'
        roadmap_pattern       = '\b(R\d+[a-z]?)\b'
        goal_pattern          = '\b(G[1-5])\b'
        due_pattern           = '\*\*Due:\*\*\s*(\d{4}-\d{2}-\d{2})'
        # Which priority codes count as "top priority" for the stale-item check,
        # and the lowest tier for the accumulation check. Overridable per repo.
        stale_priority_codes  = @('P1')
        stale_age_days        = 30
    }
}

function Merge-Taxonomy {
    <#
    Overlay a config object (from JSON) onto a base taxonomy.

    Unknown keys are skipped with a warning (a typo must not abort the run).
    `priority_levels` and `stale_priority_codes` are non-nullable: an empty overlay
    keeps the base values. `stale_age_days` must be a positive integer; anything else
    keeps the base value.
    #>
    param($Base, $Overlay)
    if ($null -eq $Overlay) { return $Base }
    $t = $Base.PSObject.Copy()
    $known = @($Base.PSObject.Properties.Name)
    foreach ($prop in $Overlay.PSObject.Properties) {
        if ($prop.Name -eq 'repo') { continue }
        if ($known -notcontains $prop.Name) {
            Write-Warning "Ignoring unknown triage config key '$($prop.Name)'."
            continue
        }
        $v = $prop.Value
        # An explicit null or empty string DISABLES a concept (e.g. a repo with no
        # owner-decision label). Absent keys never reach this loop, so defaults for
        # anything the config omits are preserved.
        if ($prop.Name -eq 'priority_levels') {
            $levels = @($v | Where-Object { $_.code -and $_.label })
            if ($levels.Count -gt 0) { $t.priority_levels = $levels }
            continue
        }
        if ($prop.Name -eq 'stale_priority_codes') {
            $codes = @($v | Where-Object { $_ })
            if ($codes.Count -gt 0) { $t.stale_priority_codes = $codes }
            continue
        }
        if ($prop.Name -eq 'stale_age_days') {
            $days = 0
            if ($v -and [int]::TryParse("$v", [ref]$days) -and $days -gt 0) { $t.stale_age_days = $days }
            continue
        }
        $t.$($prop.Name) = $v
    }
    return $t
}

function Resolve-Taxonomy {
    <#
    Build the effective taxonomy for a repo.

    - Starts from Get-DefaultTaxonomy.
    - Overlays $Config (a pscustomobject parsed from JSON) when present.
    - Validates the roadmap/goal/due patterns: an invalid pattern (or one without a
      capture group) warns and falls back to the default (or $null when the config
      explicitly disabled it).
    - When the caller passes -ExistingLabels, records any configured label that does
      not exist in the repo under `missing_labels`. Pass $null to skip the check
      entirely; pass @() when the check ran and the repo has no labels.

    Returns a taxonomy object augmented with: source, priority_codes, missing_labels.
    #>
    param(
        $Config,
        [string[]]$ExistingLabels
    )
    $base = Get-DefaultTaxonomy
    $source = 'defaults'
    $t = $base.PSObject.Copy()
    if ($Config) {
        $t = Merge-Taxonomy -Base $base -Overlay $Config
        $source = 'config'
    }

    foreach ($k in 'roadmap_pattern', 'goal_pattern', 'due_pattern') {
        if (-not (Test-RegexPattern $t.$k)) {
            $fallback = $base.$k
            Write-Warning "Invalid triage config pattern '$k' ('$($t.$k)'); falling back to default."
            $t.$k = $fallback
        }
    }

    $missing = @()
    if ($PSBoundParameters.ContainsKey('ExistingLabels')) {
        $configured = @()
        foreach ($k in 'needs_triage', 'blocked', 'owner_decision') {
            if ($t.$k) { $configured += $t.$k }
        }
        foreach ($lvl in $t.priority_levels) { $configured += $lvl.label }
        $missing = @($configured | Where-Object { $ExistingLabels -notcontains $_ } | Select-Object -Unique)
    }

    $t | Add-Member -NotePropertyName 'source'          -NotePropertyValue $source -Force
    $t | Add-Member -NotePropertyName 'priority_codes'  -NotePropertyValue @($t.priority_levels | ForEach-Object { $_.code }) -Force
    $t | Add-Member -NotePropertyName 'missing_labels'  -NotePropertyValue @($missing) -Force
    return $t
}

function Get-TriageConfigCandidates {
    <# Ordered repo-local config candidates for a checkout root. #>
    param([string]$RepoRoot)
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { return @() }
    return @(
        (Join-Path $RepoRoot 'triage.json'),
        (Join-Path $RepoRoot '.triage.json'),
        (Join-Path $RepoRoot '.github' 'triage.json')
    )
}

function Resolve-TriageConfigPath {
    <#
    Config discovery order:
      1. explicit -Config (authoritative; a missing file is an error)
      2. repo-local config in the checkout root ($RepoRoot): triage.json,
         .triage.json, or .github/triage.json — at user level this makes the
         TARGET repo's config win over whatever ships with the skill
      3. skill-co-located triage.json ($SkillRoot = the skill directory)
      4. none -> built-in defaults

    Returns the path to use, or $null when no config exists. Does not read or
    parse the file; callers do that (and warn on parse failure).
    #>
    param([string]$Explicit, [string]$RepoRoot, [string]$SkillRoot)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Triage config not found: $Explicit" }
        return $Explicit
    }
    foreach ($candidate in (Get-TriageConfigCandidates $RepoRoot)) {
        if (Test-Path $candidate) { return $candidate }
    }
    if ($SkillRoot) {
        $co = Join-Path $SkillRoot 'triage.json'
        if (Test-Path $co) { return $co }
    }
    return $null
}

function Get-OwnerNameFromRemoteUrl {
    <# owner/name from an https or ssh GitHub remote URL; $null when unparseable. #>
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $u = $Url.Trim() -replace '\.git$', ''
    $path = $null
    if ($u -match '^[^/]*@[^/]+:(.+)$') { $path = $Matches[1] }         # git@github.com:owner/name
    elseif ($u -match '^[a-z][a-z0-9+.-]*://[^/]+/(.+)$') { $path = $Matches[1] }  # https://github.com/owner/name
    if (-not $path) { return $null }
    $parts = @($path -split '/' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $null }
    return '{0}/{1}' -f $parts[-2], $parts[-1]
}

function Get-TriageOriginRemoteUrl {
    <# origin URL of the current checkout, or $null outside a git repo. Local read only. #>
    try {
        $url = git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $url) { return "$url".Trim() }
    }
    catch { }
    return $null
}

function Resolve-TriageRepo {
    <#
    Target repo resolution: explicit -Repo > config "repo" > origin remote of the
    local checkout > error. There is no built-in default repo: at user level a
    silent arisng/fin-ops fallback would query the wrong repo from any directory.
    #>
    param([string]$Repo, $Config, [string]$RemoteUrl)
    if ($Repo) { return $Repo }
    if ($Config -and $Config.repo) { return $Config.repo }
    $fromRemote = Get-OwnerNameFromRemoteUrl $RemoteUrl
    if ($fromRemote) { return $fromRemote }
    throw 'Could not determine the target repository: pass -Repo <owner/name>, add a "repo" field to the triage config, or run from a git checkout with an origin remote.'
}

function Get-PriorityLevel {
    <# The highest-priority level present in an issue's labels, or $null. #>
    param([string[]]$Labels, $Taxonomy)
    if (-not $Labels -or -not $Taxonomy -or -not $Taxonomy.priority_levels) { return $null }
    $set = @($Labels)
    foreach ($lvl in $Taxonomy.priority_levels) {
        if ($set -contains $lvl.label) { return $lvl }
    }
    return $null
}

function Get-PriorityCode {
    <# The priority code (e.g. 'P1') for an issue's labels, or $null. #>
    param([string[]]$Labels, $Taxonomy)
    $lvl = Get-PriorityLevel -Labels $Labels -Taxonomy $Taxonomy
    if ($lvl) { return $lvl.code }
    return $null
}

function Test-HasLabel {
    <# True when $Name is present in $Labels. A null/empty $Name is never present. #>
    param([string[]]$Labels, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return (@($Labels) -contains $Name)
}

function Get-LabelsByPrefix {
    <# All labels beginning with $Prefix (e.g. 'area:'). Empty prefix -> nothing. #>
    param([string[]]$Labels, [string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return @() }
    return @($Labels | Where-Object { $_ -like "$Prefix*" })
}

function Get-StalePriorityIssues {
    <#
    Open issues at a stale_priority_codes tier older than stale_age_days. A non-positive
    stale_age_days disables the check (returns nothing).
    #>
    param($OpenIssues, $Taxonomy, [datetime]$Reference = [datetime]::UtcNow)
    $days = 0
    if (-not ([int]::TryParse("$($Taxonomy.stale_age_days)", [ref]$days)) -or $days -le 0) { return @() }
    $staleLabels = @($Taxonomy.priority_levels |
        Where-Object { $Taxonomy.stale_priority_codes -contains $_.code } |
        ForEach-Object { $_.label })
    if ($staleLabels.Count -eq 0) { return @() }
    return @($OpenIssues | Where-Object {
        $ln = @($_.labels | ForEach-Object { $_.name })
        (@($staleLabels | Where-Object { $ln -contains $_ }).Count -gt 0) -and
        ((Get-AgeDays -CreatedAt $_.createdAt -Reference $Reference) -ge $days)
    } | ForEach-Object {
        [pscustomobject]@{
            number   = [int]$_.number
            title    = $_.title
            age_days = Get-AgeDays -CreatedAt $_.createdAt -Reference $Reference
        }
    })
}

function Get-LowPriorityIssues {
    <# Numbers of open issues at the lowest tier of the priority axis. #>
    param($OpenIssues, $Taxonomy)
    if (-not $Taxonomy.priority_levels -or @($Taxonomy.priority_levels).Count -eq 0) { return @() }
    $lowestLabel = @($Taxonomy.priority_levels)[-1].label
    return @($OpenIssues | Where-Object {
        (@($_.labels | ForEach-Object { $_.name }) -contains $lowestLabel)
    } | ForEach-Object { [int]$_.number })
}
