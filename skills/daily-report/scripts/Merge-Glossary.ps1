<#
.SYNOPSIS
  Canonical glossary mechanics for the daily-report skill.
.DESCRIPTION
  Owns every mechanical invariant of reports/daily/<git user>/glossary.md:
  parse, validate, case-insensitive matching, normalization, deterministic
  sorting, escaping, atomic write, and a JSON receipt. The agent owns the
  semantics (which term is new, which meaning is better); this script owns
  the file. Fail-closed: a schema violation aborts with a line-numbered
  error and the file is never touched, never recreated.
  Pinned format (schema 1): frontmatter owner + schema, one '# Glossary'
  H1, one two-column table '| Term | Meaning |', single-line cells, '\|'
  escaped pipes, meanings at most 25 words, case-insensitive unique keys.
.EXAMPLE
  .\Merge-Glossary.ps1 -RepoRoot .. -GitUser TranKhnhDuy -TermsJson '[{"term":"git proof","meaning":"Author-filtered window commits as proof rows.","op":"insert"}]'
.EXAMPLE
  .\Merge-Glossary.ps1 -GlossaryPath ..\reports\daily\TranKhnhDuy\glossary.md -Validate
#>
param(
    [string]$GlossaryPath = "",
    [string]$RepoRoot = "",
    [string]$GitUser = "",
    [string]$Owner = "",
    [string]$TermsJson = "[]",
    [switch]$Validate
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message, [int]$Line = 0) {
    $prefix = if ($Line -gt 0) { "glossary schema (line $Line): " } else { 'glossary: ' }
    Write-Error "$prefix$Message"
    exit 1
}

function ConvertTo-Cell([string]$Text) {
    return ($Text -replace '\r?\n', ' ' -replace '\|', '\|')
}

function ConvertFrom-Cell([string]$Text) {
    return ($Text -replace '\\\|', '|')
}

function Get-GlossaryRows([string]$Content, [string]$ExpectedOwner) {
    $lines = $Content -split "\r?\n"
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') { Fail 'missing frontmatter block' 1 }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $end = $i; break } }
    if ($end -lt 0) { Fail 'frontmatter is not terminated' }
    $owner = $null; $schema = $null
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ($line -match '^owner:\s*(\S+)\s*$') { if ($null -ne $owner) { Fail 'duplicate owner key' ($i + 1) }; $owner = $matches[1] }
        elseif ($line -match '^schema:\s*(\d+)\s*$') { if ($null -ne $schema) { Fail 'duplicate schema key' ($i + 1) }; $schema = [int]$matches[1] }
        elseif ($line.Trim() -ne '') { Fail "unknown frontmatter key '$line'" ($i + 1) }
    }
    if ($null -eq $owner) { Fail 'frontmatter is missing owner' }
    if ($null -eq $schema) { Fail 'frontmatter is missing schema' }
    if ($schema -ne 1) { Fail "unknown schema '$schema' (expected 1)" }
    if ($ExpectedOwner -and $owner -ne $ExpectedOwner) {
        Fail "ownership: frontmatter owner '$owner' does not match folder name '$ExpectedOwner'"
    }

    $h1 = 0; $headerLine = 0; $rows = @()
    for ($i = $end + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq '') { continue }
        if ($line -match '^#\s') {
            $h1++
            if ($line.Trim() -ne '# Glossary') { Fail "unexpected heading '$line' (expected '# Glossary')" ($i + 1) }
            continue
        }
        if ($line -match '^\|') {
            if ($line -match '^\|[\s:|-]+\|$') { continue }  # separator row
            if ($line -eq '| Term | Meaning |') { $headerLine++; continue }
            $parts = @()
            foreach ($c in @($line -split '(?<!\\)\|')) { $parts += $c }
            if ($parts.Count -ge 2 -and $parts[0].Trim() -eq '') { $parts = $parts[1..($parts.Count - 1)] }
            if ($parts.Count -ge 1 -and $parts[$parts.Count - 1].Trim() -eq '') { $parts = $parts[0..($parts.Count - 2)] }
            if ($parts.Count -ne 2) { Fail 'row must have exactly 2 columns' ($i + 1) }
            $term = (ConvertFrom-Cell $parts[0]).Trim()
            $meaning = (ConvertFrom-Cell $parts[1]).Trim()
            if ($term -eq '') { Fail 'empty term' ($i + 1) }
            if ($term.Length -gt 100) { Fail "term exceeds 100 characters ($($term.Length))" ($i + 1) }
            if ($meaning -eq '') { Fail 'empty meaning' ($i + 1) }
            if (@($meaning -split '\s+' | Where-Object { $_ }).Count -gt 25) { Fail 'meaning exceeds 25 words' ($i + 1) }
            $rows += [ordered]@{ term = $term; meaning = $meaning; line = ($i + 1) }
            continue
        }
        Fail "unexpected content '$line'" ($i + 1)
    }
    if ($h1 -ne 1) { Fail "expected exactly one '# Glossary' heading, found $h1" }
    if ($headerLine -ne 1) { Fail "expected exactly one '| Term | Meaning |' header, found $headerLine" }

    $seen = @{}
    foreach ($r in $rows) {
        $key = $r.term.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { Fail "duplicate key '$($r.term)' (first seen line $($seen[$key]))" $r.line }
        $seen[$key] = $r.line
    }
    return $rows
}

function New-GlossaryContent([string]$OwnerName, $Rows) {
    $lines = @(
        '---',
        "owner: $OwnerName",
        'schema: 1',
        '---',
        '',
        '# Glossary',
        '',
        '| Term | Meaning |',
        '| --- | --- |'
    )
    foreach ($r in $Rows) {
        $lines += "| $(ConvertTo-Cell $r.term) | $(ConvertTo-Cell $r.meaning) |"
    }
    # LF endings keep the file byte-stable across machines and platforms.
    return (($lines -join "`n") + "`n")
}

# ---- resolve path and owner (ownership guardrail) ----
if (-not $GlossaryPath) {
    if (-not $RepoRoot -or -not $GitUser) { Fail 'pass -GlossaryPath or both -RepoRoot and -GitUser' }
    $GlossaryPath = Join-Path $RepoRoot "reports/daily/$GitUser/glossary.md"
}
$folderName = Split-Path (Split-Path $GlossaryPath -Parent) -Leaf
if (-not $folderName) { Fail "cannot derive user folder from '$GlossaryPath'" }
if ($Owner -and $Owner -ne $folderName) {
    Fail "ownership: -Owner '$Owner' does not match folder name '$folderName'"
}
$expectedOwner = $folderName

$exists = Test-Path $GlossaryPath
$existingContent = ''
$existingRows = @()
if ($exists) {
    $existingContent = [IO.File]::ReadAllText($GlossaryPath)
    $existingRows = @(Get-GlossaryRows $existingContent $expectedOwner)
}

if ($Validate) {
    [ordered]@{ valid = $true; path = "$GlossaryPath"; owner = $expectedOwner; total = $existingRows.Count } | ConvertTo-Json -Compress
    exit 0
}

# ---- apply ops (semantics decided by the agent; mechanics here) ----
$store = @()
foreach ($r in $existingRows) { $store += [ordered]@{ term = $r.term; meaning = $r.meaning } }

$added = 0; $refreshed = 0; $kept = 0
$terms = @()
try { $terms = @($TermsJson | ConvertFrom-Json) } catch { Fail "TermsJson is not valid JSON: $($_.Exception.Message)" }

foreach ($t in $terms) {
    $term = "$($t.term)".Trim()
    $meaning = "$($t.meaning)".Trim() -replace '\r?\n', ' '
    $op = "$($t.op)".ToLowerInvariant()
    if ($term -eq '') { Fail 'term in TermsJson is empty' }
    if ($term.Length -gt 100) { Fail "term '$term' exceeds 100 characters" }
    if ($meaning -eq '') { Fail "meaning for '$term' is empty" }
    if (@($meaning -split '\s+' | Where-Object { $_ }).Count -gt 25) { Fail "meaning for '$term' exceeds 25 words" }
    if ($op -notin @('insert', 'refresh', 'keep')) { Fail "unknown op '$op' for '$term'" }

    $idx = -1
    for ($i = 0; $i -lt $store.Count; $i++) { if ($store[$i].term.ToLowerInvariant() -eq $term.ToLowerInvariant()) { $idx = $i; break } }

    if ($op -eq 'insert') {
        if ($idx -ge 0) { Fail "insert on existing key '$term'" }
        $store += [ordered]@{ term = $term; meaning = $meaning }
        $added++
    }
    elseif ($op -eq 'refresh') {
        if ($idx -ge 0) {
            if ($store[$idx].meaning -cne $meaning) { $store[$idx].meaning = $meaning; $refreshed++ }
            else { $kept++ }
        }
        else {
            $store += [ordered]@{ term = $term; meaning = $meaning }
            $added++
        }
    }
    else { # keep
        if ($idx -ge 0) { $kept++ }
        else { $store += [ordered]@{ term = $term; meaning = $meaning }; $added++ }
    }
}

# ---- deterministic order: case-insensitive ordinal by term ----
$sorted = @($store | Sort-Object -Property @{ Expression = { $_.term.ToLowerInvariant() } }, @{ Expression = { $_.term } })

$newContent = New-GlossaryContent $expectedOwner $sorted
$changed = $true
if ($exists -and $existingContent -eq $newContent) { $changed = $false }

if ($changed) {
    $dir = Split-Path $GlossaryPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = "$GlossaryPath.tmp-$PID"
    [IO.File]::WriteAllText($tmp, $newContent)
    Move-Item -Force $tmp $GlossaryPath
}

[ordered]@{
    added    = $added
    refreshed = $refreshed
    kept     = $kept
    total    = $sorted.Count
    changed  = $changed
} | ConvertTo-Json -Compress
