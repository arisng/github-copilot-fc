<#
.SYNOPSIS
    Validates issue-to-theme relations, (re)generates the tree file, or dumps the
    store as machine rows (-Inventory).

.DESCRIPTION
    A theme (type: theme) is a prioritized workstream. Every active non-theme issue
    must relate to exactly one theme - directly via `theme: NNNN`, or indirectly via
    a `parent:` chain that ends at a theme (or at an issue carrying a theme).

    Checks:
      1. Frontmatter: required fields, id matches filename, status/priority/type
         enums, numeric order.
      2. Theme relations: resolvable, no cycles, theme refs point at type: theme,
         every theme has at least one active child.
      3. -Check also fails when the tree file is missing or stale.

    Store resolution (repo-agnostic): .github/issue-tracker.json, read relative to
    the current directory, supplies tracker / issuesDir / treeFile / archiveDir;
    falls back to .issues, .issues/tree.md and .issues/archived when the manifest
    is absent, and refuses to run when the manifest declares a non-local-markdown
    tracker (issue-tracking skill, step 0).

    Modes (all validate first; errors print as THEME lines and exit 1):
      default     regenerate the tree file (exits before writing when invalid)
      -Check      validate only + tree freshness (repo issue lint, pre-commit gate)
      -Inventory  print one pipe row per issue, then the next free id:
                    id|type|status|priority|theme|parent|order|file|title
                    NEXT_ID|NNNN   (max id across active + archived, plus one,
                    skipping ids reserved by issue-new-id leases)
    tree grammar (blank and comment lines are not data; title is always the
    last field and may contain '|'):
                  SUMMARY|themes=N|issues=N|P0=N|P1=N|P2=N|P3=N|blocked=N
                  NEXT|id|theme|priority|status|title   (absent when nothing actionable)
                  ## THEME|id|priority|status|title
                  - id|theme|parent|priority|status|title  (indent = nesting, 3 spaces
                    per level; parent "-" = theme root)

    Run from the repo root. The script ships inside the issue-tracking skill folder
    (next to its SKILL.md), so invoke it by its own path - installed at:
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 - the issue store is
    resolved relative to the current directory, never relative to this file.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Check
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Inventory
#>
param(
    [switch]$Check,
    [switch]$Inventory
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-id-lib.ps1')

# --- Store resolution: manifest first, .issues fallback (repo-agnostic) ------
$issuesDir = '.issues'
$treePath = Join-Path -Path $issuesDir -ChildPath 'tree.md'
$archiveDir = Join-Path -Path $issuesDir -ChildPath 'archived'
$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($manifest.PSObject.Properties.Name)
    if ($names -contains 'tracker' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker) -and
        $manifest.tracker -ne 'local-markdown') {
        "issue-tree: tracker '$($manifest.tracker)' is not local-markdown - this script only handles the local file store (issue-tracking skill, step 0)"
        exit 1
    }
    if ($names -contains 'issuesDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.issuesDir)) {
        $issuesDir = [string]$manifest.issuesDir
    }
    if ($names -contains 'treeFile' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeFile)) {
        $treePath = [string]$manifest.treeFile
    }
    else {
        $treePath = Join-Path -Path $issuesDir -ChildPath 'tree.md'
    }
    if ($names -contains 'archiveDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.archiveDir)) {
        $archiveDir = [string]$manifest.archiveDir
    }
    else {
        $archiveDir = Join-Path -Path $issuesDir -ChildPath 'archived'
    }
}
$issuesLabel = $issuesDir -replace '\\', '/'
$treeLabel = $treePath -replace '\\', '/'
if (-not (Test-Path -LiteralPath $issuesDir)) {
    "issue-tree: issue store '$issuesLabel' not found - create it, or point .github/issue-tracker.json issuesDir at it"
    exit 1
}

$validStatus = @('open', 'in-progress', 'blocked', 'done', 'dropped')
$validPriority = @('P0', 'P1', 'P2', 'P3')
$validType = @('theme', 'epic', 'task', 'bug', 'chore')

$fail = $false

function Get-PriorityRank {
    param([string]$Priority)
    switch ($Priority) {
        'P0' { return 0 }
        'P1' { return 1 }
        'P2' { return 2 }
        'P3' { return 3 }
        default { return 9 }
    }
}

function Get-ChildLines {
    # Nested sub-issues of one parent inside a theme, depth-first, sorted input.
    param(
        [string]$ParentId,
        $ThemeChildren,
        [int]$Depth,
        $Seen
    )
    $result = @()
    foreach ($child in $ThemeChildren) {
        if ($child.Parent -ne $ParentId) { continue }
        if ($Seen.ContainsKey($child.Id)) { continue }
        $Seen[$child.Id] = $true
        $indent = '   ' * $Depth
        $result += "$indent- $($child.Id)|$($child.ResolvedTheme)|$($child.Parent)|$($child.Priority)|$($child.Status)|$($child.Title)"
        $result += Get-ChildLines -ParentId $child.Id -ThemeChildren $ThemeChildren -Depth ($Depth + 1) -Seen $Seen
    }
    return $result
}

function Read-Frontmatter {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') { return $null }
    $fm = @{}
    $closed = $false
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        if ($line.Trim() -eq '---') { $closed = $true; break }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            # Strip inline comments the way the README format example shows them
            # (never for title: - a title may legitimately contain ' #').
            if ($key -ne 'title' -and $value -match ' #') {
                $value = ($value -split ' #', 2)[0].Trim()
            }
            if ($value.Length -ge 2 -and
                ($value[0] -eq '"' -or $value[0] -eq "'") -and
                $value[$value.Length - 1] -eq $value[0]) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $fm[$key] = $value
        }
    }
    if (-not $closed) { return $null }
    return $fm
}

# --- 1. Load and validate frontmatter ---------------------------------------
$records = @()
$byId = @{}

$files = Get-ChildItem -LiteralPath $issuesDir -File -Filter '*.md' |
    Where-Object { $_.Name -match '^\d{4}-' } |
    Sort-Object Name

foreach ($file in $files) {
    $fileId = $file.Name.Substring(0, 4)
    $fm = Read-Frontmatter -Path $file.FullName
    if ($null -eq $fm) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): missing or malformed YAML frontmatter"
        continue
    }
    foreach ($required in @('id', 'title', 'status', 'priority', 'type', 'created')) {
        if (-not $fm.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($fm[$required])) {
            $fail = $true
            "THEME   $issuesLabel/$($file.Name): missing required frontmatter field '$required'"
        }
    }
    if ($fm.ContainsKey('id') -and $fm['id'] -ne $fileId) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): id '$($fm['id'])' does not match the filename"
    }
    if ($fm.ContainsKey('status') -and $validStatus -notcontains $fm['status']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid status '$($fm['status'])'"
    }
    if ($fm.ContainsKey('priority') -and $validPriority -notcontains $fm['priority']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid priority '$($fm['priority'])'"
    }
    if ($fm.ContainsKey('type') -and $validType -notcontains $fm['type']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid type '$($fm['type'])' (expected theme|epic|task|bug|chore)"
    }
    $order = 999
    if ($fm.ContainsKey('order') -and -not [string]::IsNullOrWhiteSpace($fm['order'])) {
        $parsedOrder = 0
        if ([int]::TryParse($fm['order'], [ref]$parsedOrder)) {
            $order = $parsedOrder
        }
        else {
            $fail = $true
            "THEME   $issuesLabel/$($file.Name): order '$($fm['order'])' is not an integer"
        }
    }
    if ($byId.ContainsKey($fileId)) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): duplicate issue id $fileId"
        continue
    }
    $record = [pscustomobject]@{
        File          = $file.Name
        Id            = $fileId
        Title         = $(if ($fm.ContainsKey('title')) { $fm['title'] } else { '' })
        Status        = $(if ($fm.ContainsKey('status')) { $fm['status'] } else { '' })
        Priority      = $(if ($fm.ContainsKey('priority')) { $fm['priority'] } else { '' })
        Type          = $(if ($fm.ContainsKey('type')) { $fm['type'] } else { '' })
        Theme         = $(if ($fm.ContainsKey('theme')) { $fm['theme'] } else { '' })
        Parent        = $(if ($fm.ContainsKey('parent')) { $fm['parent'] } else { '' })
        Order         = $order
        ResolvedTheme = ''
    }
    $byId[$fileId] = $record
    $records += $record
}

# --- 2. Parent chains: exist, no cycles --------------------------------------
foreach ($record in $records) {
    if ([string]::IsNullOrWhiteSpace($record.Parent)) { continue }
    $visited = @{}
    $visited[$record.Id] = $true
    $cursor = $record
    while (-not [string]::IsNullOrWhiteSpace($cursor.Parent)) {
        if ($visited.ContainsKey($cursor.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): parent chain cycles at '$($cursor.Parent)'"
            break
        }
        if (-not $byId.ContainsKey($cursor.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): parent '$($cursor.Parent)' does not exist"
            break
        }
        $visited[$cursor.Parent] = $true
        $cursor = $byId[$cursor.Parent]
    }
}

# --- 3. Theme relations ------------------------------------------------------
foreach ($record in $records) {
    if ($record.Type -eq 'theme') {
        if (-not [string]::IsNullOrWhiteSpace($record.Theme)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): a theme must not declare 'theme:'"
        }
        if (-not [string]::IsNullOrWhiteSpace($record.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): a theme must not declare 'parent:'"
        }
        continue
    }
    if (-not [string]::IsNullOrWhiteSpace($record.Theme)) {
        if (-not $byId.ContainsKey($record.Theme)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): theme '$($record.Theme)' does not exist"
        }
        elseif ($byId[$record.Theme].Type -ne 'theme') {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): theme '$($record.Theme)' is not a theme issue"
        }
        else {
            $record.ResolvedTheme = $record.Theme
        }
        continue
    }
    if ([string]::IsNullOrWhiteSpace($record.Parent)) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): not related to a theme - add 'theme: <id>' (or a parent chain ending at a theme)"
        continue
    }
    # Indirect relation: walk the parent chain until a theme (or a themed issue).
    $seen = @{}
    $seen[$record.Id] = $true
    $cursor = $record
    $resolved = $null
    $chainError = $null
    while (-not [string]::IsNullOrWhiteSpace($cursor.Parent)) {
        if ($seen.ContainsKey($cursor.Parent)) {
            $chainError = "parent chain cycles at '$($cursor.Parent)'"
            break
        }
        if (-not $byId.ContainsKey($cursor.Parent)) {
            $chainError = "parent '$($cursor.Parent)' does not exist"
            break
        }
        $seen[$cursor.Parent] = $true
        $cursor = $byId[$cursor.Parent]
        if ($cursor.Type -eq 'theme') {
            $resolved = $cursor.Id
            break
        }
        if (-not [string]::IsNullOrWhiteSpace($cursor.Theme)) {
            if (-not $byId.ContainsKey($cursor.Theme) -or $byId[$cursor.Theme].Type -ne 'theme') {
                $chainError = "parent '$($cursor.Id)' references invalid theme '$($cursor.Theme)'"
            }
            else {
                $resolved = $cursor.Theme
            }
            break
        }
    }
    if ($chainError) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): $chainError"
    }
    elseif ($null -eq $resolved) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): parent chain '$($record.Parent)' does not reach a theme"
    }
    else {
        $record.ResolvedTheme = $resolved
    }
}

# Every theme must carry active work, otherwise it is clutter to archive.
foreach ($record in $records) {
    if ($record.Type -ne 'theme') { continue }
    $hasChild = $false
    foreach ($other in $records) {
        if ($other.Type -ne 'theme' -and $other.ResolvedTheme -eq $record.Id) {
            $hasChild = $true
            break
        }
    }
    if (-not $hasChild) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): theme has no active child issues"
    }
}

if ($fail) {
    "issue-tree: FAILED - fix the THEME errors above, then re-run"
    exit 1
}

if ($Check -and $Inventory) {
    "issue-tree: pass either -Check or -Inventory, not both"
    exit 1
}

# --- 4. Inventory: the store as machine rows ---------------------------------
if ($Inventory) {
    'id|type|status|priority|theme|parent|order|file|title'
    foreach ($record in $records) {
        $themeField = '-'
        if (-not [string]::IsNullOrWhiteSpace($record.ResolvedTheme)) {
            $themeField = $record.ResolvedTheme
        }
        $parentField = '-'
        if (-not [string]::IsNullOrWhiteSpace($record.Parent)) {
            $parentField = $record.Parent
        }
        "$($record.Id)|$($record.Type)|$($record.Status)|$($record.Priority)|$themeField|$parentField|$($record.Order)|$($record.File)|$($record.Title)"
    }
    $maxId = 0
    foreach ($record in $records) {
        $parsedId = 0
        if ([int]::TryParse($record.Id, [ref]$parsedId) -and $parsedId -gt $maxId) {
            $maxId = $parsedId
        }
    }
    $archivedDir = $archiveDir
    if (Test-Path -LiteralPath $archivedDir) {
        foreach ($archived in (Get-ChildItem -LiteralPath $archivedDir -File -Filter '*.md')) {
            if ($archived.Name -match '^(\d{4})-') {
                $parsedId = [int]$Matches[1]
                if ($parsedId -gt $maxId) { $maxId = $parsedId }
            }
        }
    }
    # NEXT_ID must agree with the allocator (issue-new-id.ps1): skip ids that
    # are only reserved (outstanding lease in the shared git-common-dir store).
    $nextCandidate = $maxId + 1
    $reservedLeases = Get-IssueIdLeases -LeaseDir (Get-IssueIdLeaseDir)
    while ($nextCandidate -le 9999 -and
        $reservedLeases.Active.ContainsKey(('{0:D4}' -f $nextCandidate))) {
        $nextCandidate++
    }
    $nextId = '{0:D4}' -f $nextCandidate
    ''
    "NEXT_ID|$nextId"
    exit 0
}

# --- 5. Render the tree ------------------------------------------------------
$themes = @($records |
    Where-Object { $_.Type -eq 'theme' } |
    Sort-Object @{ Expression = { Get-PriorityRank $_.Priority } }, @{ Expression = { $_.Id } })
$children = @($records | Where-Object { $_.Type -ne 'theme' })
$sortedChildren = @($children |
    Sort-Object @{ Expression = { Get-PriorityRank $_.Priority } },
                 @{ Expression = { $_.Order } },
                 @{ Expression = { $_.Id } })

$pCounts = @{}
foreach ($priority in $validPriority) { $pCounts[$priority] = 0 }
$blocked = 0
foreach ($child in $children) {
    if ($pCounts.ContainsKey($child.Priority)) { $pCounts[$child.Priority]++ }
    if ($child.Status -eq 'blocked') { $blocked++ }
}
$lines = @()
$lines += '# Issue tree'
$lines += ''
$lines += '<!-- Generated by issue-tree.ps1 (issue-tracking skill) - do not edit by hand. -->'
$lines += '<!-- Regenerate: pwsh <skill-folder>/scripts/issue-tree.ps1 | Validate: the same script with -Check -->'
$lines += '<!-- Human view: .issues/tree.html - render: pwsh <skill-folder>/scripts/render-issue-tree.ps1 -->'
$lines += '<!-- Machine grammar (blank and comment lines are not data): -->'
$lines += '<!--   SUMMARY|themes=N|issues=N|P0=N|P1=N|P2=N|P3=N|blocked=N -->'
$lines += '<!--   NEXT|id|theme|priority|status|title          (absent when nothing actionable) -->'
$lines += '<!--   ## THEME|id|priority|status|title -->'
$lines += '<!--   - id|theme|parent|priority|status|title      (indent = nesting, 3 spaces per -->'
$lines += '<!--     level, parent "-" = theme root; title is last and may contain "|") -->'
$lines += ''
$lines += "SUMMARY|themes=$($themes.Count)|issues=$($children.Count)|P0=$($pCounts['P0'])|P1=$($pCounts['P1'])|P2=$($pCounts['P2'])|P3=$($pCounts['P3'])|blocked=$blocked"
$lines += ''

# "What to do next": first actionable child in theme order.
$next = $null
foreach ($theme in $themes) {
    foreach ($child in @($sortedChildren | Where-Object { $_.ResolvedTheme -eq $theme.Id })) {
        if ($child.Status -eq 'open' -or $child.Status -eq 'in-progress') {
            $next = $child
            break
        }
    }
    if ($null -ne $next) { break }
}
if ($null -ne $next) {
    $lines += "NEXT|$($next.Id)|$($next.ResolvedTheme)|$($next.Priority)|$($next.Status)|$($next.Title)"
    $lines += ''
}

foreach ($theme in $themes) {
    $lines += "## THEME|$($theme.Id)|$($theme.Priority)|$($theme.Status)|$($theme.Title)"
    $lines += ''
    $themeChildren = @($sortedChildren | Where-Object { $_.ResolvedTheme -eq $theme.Id })
    $memberIds = @{}
    foreach ($member in $themeChildren) { $memberIds[$member.Id] = $true }
    $roots = @($themeChildren | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Parent) -or -not $memberIds.ContainsKey($_.Parent)
    })
    $seen = @{}
    foreach ($root in $roots) {
        $seen[$root.Id] = $true
        $rootParent = '-'
        if (-not [string]::IsNullOrWhiteSpace($root.Parent)) { $rootParent = $root.Parent }
        $lines += "- $($root.Id)|$($root.ResolvedTheme)|$rootParent|$($root.Priority)|$($root.Status)|$($root.Title)"
        $lines += Get-ChildLines -ParentId $root.Id -ThemeChildren $themeChildren -Depth 1 -Seen $seen
    }
    $lines += ''
}

$generated = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
$absTree = Join-Path -Path (Get-Location).Path -ChildPath $treePath

if ($Check) {
    if (-not (Test-Path -LiteralPath $absTree)) {
        "TREE    $treeLabel is missing - run: pwsh $PSCommandPath"
        exit 1
    }
    $existing = [System.IO.File]::ReadAllText($absTree, [System.Text.Encoding]::UTF8)
    $normExisting = ($existing -replace "`r`n", "`n").TrimEnd("`n")
    $normGenerated = ($generated -replace "`r`n", "`n").TrimEnd("`n")
    if ($normExisting -ne $normGenerated) {
        "TREE    $treeLabel is stale - run: pwsh $PSCommandPath"
        exit 1
    }
    "issue-tree: OK ($($themes.Count) themes, $($children.Count) issues, tree.md fresh)"
    exit 0
}

[System.IO.File]::WriteAllText($absTree, $generated, [System.Text.UTF8Encoding]::new($false))
"issue-tree: OK ($($themes.Count) themes, $($children.Count) issues, wrote $treeLabel)"
exit 0
