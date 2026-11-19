<#
.SYNOPSIS
    Renders the generated issue tree (.issues/tree.md) into a self-contained,
    deterministic static HTML page - the skill's primary human-facing surface.

.DESCRIPTION
    Reads the tree file (path from .github/issue-tracker.json, default
    .issues/tree.md), parses it per its machine grammar, embeds the result as
    JSON into assets/tree-template.html (inline CSS + JS, no external deps,
    opens over file://) and writes it next to the tree file as .html.

    Determinism: same tree file + same template -> byte-identical HTML
    (no timestamps; stable key order; platform line endings only).

    Modes:
      default   write the HTML file
      -Check    fail (exit 1) when the HTML file is missing or stale
                (repo issue lint, pre-commit gate)
    -Out overrides the output path (default: tree file with .html extension).

    Interactive features live in the template: search (/), status/priority
    filter chips, expand/collapse, click-to-copy ids, NEXT callout, hash
    deep links (#0001) with highlight, light/dark via prefers-color-scheme.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1 -Check
#>
param(
    [switch]$Check,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
$treePath = '.issues/tree.md'
$tracker = $null
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($manifest.PSObject.Properties.Name)
    if ($names -contains 'tracker' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker)) {
        $tracker = [string]$manifest.tracker
        if ($tracker -ne 'local-markdown') {
            "render-tree: tracker '$tracker' is not local-markdown - HTML rendering only handles the local file store"
            exit 1
        }
    }
    if ($names -contains 'treeFile' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeFile)) {
        $treePath = [string]$manifest.treeFile
    }
}
$treeLabel = $treePath -replace '\\', '/'

$templatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\tree-template.html'
if (-not (Test-Path -LiteralPath $templatePath)) {
    "render-tree: template not found at $templatePath (skill assets must ship with the script)"
    exit 1
}
if (-not (Test-Path -LiteralPath $treePath)) {
    "render-tree: tree file '$treeLabel' not found - run the issue-tree script first"
    exit 1
}

# --- Parse tree.md per its machine grammar ------------------------------------
$summaryList = New-Object System.Collections.Generic.List[string]   # "k":v fragments in file order
$summaryCount = @{}
$nextNode = $null
$themes = New-Object System.Collections.Generic.List[object]
$allIds = @{}
$rowTotal = 0
$currentTheme = $null
$stack = New-Object System.Collections.Stack
$fail = $null

function ConvertTo-JsString {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    $escaped = $escaped.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
    return '"' + $escaped + '"'
}

function New-RowNode {
    param([string]$Id, [string]$Theme, [string]$Parent, [string]$Priority, [string]$Status, [string]$Title)
    return [pscustomobject]@{
        Id       = $Id
        Theme    = $Theme
        Parent   = $Parent
        Priority = $Priority
        Status   = $Status
        Title    = $Title
        Children = New-Object System.Collections.Generic.List[object]
    }
}

foreach ($line in [System.IO.File]::ReadAllLines((Join-Path (Get-Location).Path $treePath))) {
    if ($fail) { break }
    if ($line -match '^SUMMARY\|') {
        foreach ($seg in (($line -split '\|') | Select-Object -Skip 1)) {
            if ($seg -match '^([^=]+)=(\d+)$') {
                $summaryList.Add(('"{0}":{1}' -f $Matches[1], $Matches[2]))
                $summaryCount[$Matches[1]] = [int]$Matches[2]
            }
            else {
                $fail = "malformed SUMMARY segment '$seg'"
            }
        }
        continue
    }
    if ($line -match '^NEXT\|') {
        $f = $line -split '\|', 6
        if ($f.Count -lt 6) { $fail = 'malformed NEXT line'; continue }
        $nextNode = @{ Id = $f[1]; Theme = $f[2]; Priority = $f[3]; Status = $f[4]; Title = $f[5] }
        continue
    }
    if ($line -match '^## THEME\|') {
        $f = $line -split '\|', 5
        if ($f.Count -lt 5) { $fail = 'malformed THEME line'; continue }
        $currentTheme = [pscustomobject]@{
            Id       = $f[1]
            Priority = $f[2]
            Status   = $f[3]
            Title    = $f[4]
            Children = New-Object System.Collections.Generic.List[object]
        }
        $themes.Add($currentTheme)
        $stack.Clear()
        $stack.Push(@{ Node = $currentTheme; Depth = -1 })
        continue
    }
    if ($line -match '^( *)- \|') { $fail = 'malformed row line'; continue }
    if ($line -match '^( *)- ') {
        $indent = $Matches[1].Length
        if ($indent % 3 -ne 0) { $fail = "row indent $indent is not a multiple of 3"; continue }
        $depth = [int]($indent / 3)
        $f = ($line -replace '^( *)- ', '') -split '\|', 6
        if ($f.Count -lt 6) { $fail = "malformed row '$line'"; continue }
        if ($null -eq $currentTheme) { $fail = "row '$($f[0])' appears before any THEME section"; continue }
        if ($f[1] -ne $currentTheme.Id) { $fail = "row '$($f[0])' theme '$($f[1])' != section '$($currentTheme.Id)'"; continue }
        $node = New-RowNode -Id $f[0] -Theme $f[1] -Parent $f[2] -Priority $f[3] -Status $f[4] -Title $f[5]
        while ($stack.Count -gt 0 -and $stack.Peek().Depth -ge $depth) { [void]$stack.Pop() }
        if ($stack.Count -eq 0) {
            $fail = "row '$($f[0])' at depth $depth has no visible parent"
            continue
        }
        [void]$stack.Peek().Node.Children.Add($node)
        $stack.Push(@{ Node = $node; Depth = $depth })
        $allIds[$node.Id] = $true
        $rowTotal++
        continue
    }
    # everything else (heading, blanks, comments, grammar docs) is not data
}

if ($fail) {
    "render-tree: $fail - regenerate the tree first"
    exit 1
}
if ($summaryList.Count -eq 0) {
    "render-tree: no SUMMARY line in '$treeLabel' - is this really a tree file?"
    exit 1
}
if ($themes.Count -eq 0) {
    "render-tree: no THEME sections in '$treeLabel' - regenerate the tree first"
    exit 1
}
if ($summaryCount.ContainsKey('themes') -and $summaryCount['themes'] -ne $themes.Count) {
    "render-tree: SUMMARY themes=$($summaryCount['themes']) but parsed $($themes.Count) sections"
    exit 1
}
if ($summaryCount.ContainsKey('issues') -and $summaryCount['issues'] -ne $rowTotal) {
    "render-tree: SUMMARY issues=$($summaryCount['issues']) but parsed $rowTotal rows"
    exit 1
}
if ($null -ne $nextNode -and -not $allIds.ContainsKey($nextNode.Id)) {
    "render-tree: NEXT id '$($nextNode.Id)' does not exist in the tree"
    exit 1
}

# --- Serialize to JSON (stable order, script-safe escaping) --------------------
function ConvertTo-RowJson {
    param($Row)
    $childJson = (($Row.Children | ForEach-Object { ConvertTo-RowJson -Row $_ }) -join ',')
    return ('{{"id":{0},"theme":{1},"parent":{2},"priority":{3},"status":{4},"title":{5},"children":[{6}]}}' -f
        (ConvertTo-JsString $Row.Id), (ConvertTo-JsString $Row.Theme), (ConvertTo-JsString $Row.Parent),
        (ConvertTo-JsString $Row.Priority), (ConvertTo-JsString $Row.Status), (ConvertTo-JsString $Row.Title),
        $childJson)
}
function ConvertTo-ThemeJson {
    param($Theme)
    $childJson = (($Theme.Children | ForEach-Object { ConvertTo-RowJson -Row $_ }) -join ',')
    return ('{{"id":{0},"priority":{1},"status":{2},"title":{3},"children":[{4}]}}' -f
        (ConvertTo-JsString $Theme.Id), (ConvertTo-JsString $Theme.Priority),
        (ConvertTo-JsString $Theme.Status), (ConvertTo-JsString $Theme.Title), $childJson)
}

$themeJson = (($themes | ForEach-Object { ConvertTo-ThemeJson -Theme $_ }) -join ',')
$summaryJson = '{' + ($summaryList -join ',') + '}'
$nextJson = 'null'
if ($null -ne $nextNode) {
    $nextJson = ('{{"id":{0},"theme":{1},"priority":{2},"status":{3},"title":{4}}}' -f
        (ConvertTo-JsString $nextNode.Id), (ConvertTo-JsString $nextNode.Theme),
        (ConvertTo-JsString $nextNode.Priority), (ConvertTo-JsString $nextNode.Status),
        (ConvertTo-JsString $nextNode.Title))
}
$dataJson = '{{"source":{0},"summary":{1},"next":{2},"themes":[{3}]}}' -f
    (ConvertTo-JsString $treeLabel), $summaryJson, $nextJson, $themeJson

# --- Hydrate the template -------------------------------------------------------
$template = [System.IO.File]::ReadAllText($templatePath)
$placeholderCount = [regex]::Matches($template, '__ISSUE_TREE_DATA__').Count
if ($placeholderCount -ne 1) {
    "render-tree: expected exactly 1 __ISSUE_TREE_DATA__ placeholder in the template, found $placeholderCount"
    exit 1
}
$htmlLf = ($template.Replace('__ISSUE_TREE_DATA__', $dataJson) -replace "`r`n", "`n")
$html = $htmlLf.Replace("`n", [Environment]::NewLine)

if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = $treePath -replace '\.[^.]+$', '.html'
}
$OutLabel = $Out -replace '\\', '/'

if ($Check) {
    if (-not (Test-Path -LiteralPath $Out)) {
        "TREE-HTML  $OutLabel is missing - run: pwsh $PSCommandPath"
        exit 1
    }
    $existing = ([System.IO.File]::ReadAllText((Join-Path (Get-Location).Path $Out)) -replace "`r`n", "`n")
    if ($existing -ne $htmlLf) {
        "TREE-HTML  $OutLabel is stale - run: pwsh $PSCommandPath"
        exit 1
    }
    "render-tree: OK ($($themes.Count) themes, $rowTotal issues, $OutLabel fresh)"
    exit 0
}

$fullOut = Join-Path -Path (Get-Location).Path -ChildPath $Out
$outDir = Split-Path -Parent $fullOut
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($fullOut, $html, [System.Text.UTF8Encoding]::new($false))
"render-tree: OK ($($themes.Count) themes, $rowTotal issues, wrote $OutLabel)"
exit 0
