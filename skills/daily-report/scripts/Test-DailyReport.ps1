<#
.SYNOPSIS
  Read-only report and glossary validator for the daily-report skill.
.DESCRIPTION
  Checks one rendered report and the runner's glossary against the pinned
  formats and the script-enforced guardrails: path and naming, frontmatter
  schema (created/updated with runtime UTC offsets, no covers), timeless
  body, section structure and caps, refs format, one-page budget,
  session-transcript exports (every session the report mentions must have
  its sessions/<slug>.html beside the report), report-to-canonical glossary
  consistency, and — with -EvidenceJson — empty-source honesty. Exits
  non-zero with a specific message per violation. Writes nothing.
.EXAMPLE
  .\Test-DailyReport.ps1 -RepoRoot .. -GitUser TranKhnhDuy -Date 2026-11-10
#>
param(
    [string]$ReportPath = "",
    [string]$RepoRoot = "",
    [string]$GitUser = "",
    [string]$Date = "",
    [string]$GlossaryPath = "",
    [string]$EvidenceJson = ""
)

$ErrorActionPreference = 'Stop'
$failures = @()
function Fail([string]$Message) { $script:failures += $Message }

# ---- path and naming guardrail ----
$parsedDay = [DateTime]::MinValue
if ($Date -and -not [DateTime]::TryParseExact($Date, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDay)) {
    Write-Error "Invalid -Date '$Date'."
    exit 1
}
if (-not $ReportPath) {
    if (-not $RepoRoot -or -not $GitUser -or -not $Date) { Write-Error 'pass -ReportPath or -RepoRoot/-GitUser/-Date.'; exit 1 }
    $ReportPath = Join-Path $RepoRoot "reports/daily/$GitUser/$($parsedDay.ToString('yyMMdd')).md"
}
$folderName = Split-Path (Split-Path $ReportPath -Parent) -Leaf
$fileName = Split-Path $ReportPath -Leaf
if ($fileName -notmatch '^\d{6}\.md$') { Fail "naming: report file must be yymmdd.md, got '$fileName'" }
if (-not $GitUser) { $GitUser = $folderName }
if ($folderName -ne $GitUser) { Fail "path: report must live under reports/daily/$GitUser/, got folder '$folderName'" }
$root = Split-Path (Split-Path (Split-Path $ReportPath -Parent) -Parent) -Parent
if ($GitUser -and $fileName -match '^(\d{2})(\d{2})(\d{2})\.md$' -and $Date) {
    if ($parsedDay.ToString('yyMMdd') -ne ($matches[1] + $matches[2] + $matches[3])) {
        Fail "naming: '$fileName' does not match report date $Date"
    }
}

if (-not (Test-Path $ReportPath)) { Write-Error "report not found: $ReportPath"; exit 1 }
$content = [IO.File]::ReadAllText($ReportPath)
$lines = $content -split "\r?\n"

# ---- frontmatter schema guardrail ----
$fmEnd = -1
if ($lines.Count -gt 2 -and $lines[0] -eq '---') {
    for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $fmEnd = $i; break } }
}
if ($fmEnd -lt 0) { Fail 'frontmatter: missing or unterminated block' }
else {
    $created = $null; $updated = $null; $badKeys = @()
    for ($i = 1; $i -lt $fmEnd; $i++) {
        $l = $lines[$i]
        if ($l -match '^created:\s*(.+?)\s*$') { $created = $matches[1] }
        elseif ($l -match '^updated:\s*(.+?)\s*$') { $updated = $matches[1] }
        elseif ($l.Trim() -ne '') { $badKeys += $l }
    }
    if ($badKeys.Count -gt 0) { Fail "frontmatter: unexpected key(s) '$($badKeys -join ', ')' (only created/updated allowed)" }
    $stampPattern = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2} [+-]\d{2}:\d{2}$'
    if (-not $created -or $created -notmatch $stampPattern) { Fail "frontmatter: created must look like 'yyyy-MM-dd HH:mm +07:00' with a runtime offset, got '$created'" }
    if (-not $updated -or $updated -notmatch $stampPattern) { Fail "frontmatter: updated must look like 'yyyy-MM-dd HH:mm +07:00' with a runtime offset, got '$updated'" }
}

# ---- timeless body guardrail (frontmatter excepted) ----
$bodyStart = if ($fmEnd -ge 0) { $fmEnd + 1 } else { 0 }
$bodyLines = @($lines[$bodyStart..($lines.Count - 1)])
$body = $bodyLines -join "`n"
if ($body -match '(?m)^-?\s*>?\s*Updated at:') { Fail 'timeless body: an Updated at line survived (time lives in frontmatter only)' }
if ($body -match '(?m)Covers:') { Fail 'timeless body: a Covers line survived (the window stays out of the report)' }
$clockHits = [regex]::Matches($body, '\b\d{1,2}:\d{2}\b')
if ($clockHits.Count -gt 0) { Fail "timeless body: clock time '$($clockHits[0].Value)' found in body" }
$dateHits = [regex]::Matches($body, '\b20\d{2}-\d{2}-\d{2}\b')
if ($dateHits.Count -gt 0) { Fail "timeless body: date '$($dateHits[0].Value)' found in body" }

# ---- structure and caps ----
$order = @('## 🏆 Completed Today', '## 👀 Under Review', '## 🚀 Active Work', '## ⚠️ Blockers & Risks', '## 📋 Next Up', '## Glossary')
$seenIdx = -1
foreach ($h in $order) {
    $idx = [array]::IndexOf($lines, $h)
    if ($idx -lt 0) { Fail "structure: missing section '$h'" }
    elseif ($idx -lt $seenIdx) { Fail "structure: section '$h' out of order" }
    else { $seenIdx = $idx }
}
$itemCount = @($bodyLines | Where-Object { $_ -match '^### ' }).Count
if ($itemCount -gt 4) { Fail "caps: $itemCount Completed items (max 4)" }
foreach ($m in [regex]::Matches($body, '(?ms)^### .+?(?=^### |^## |\z)')) {
    $itemLines = @($m.Value -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    if ($itemLines.Count -gt 4) { Fail "caps: item '$($itemLines[0])' has $($itemLines.Count) lines (max 4)" }
}

# ---- refs format guardrail ----
$refLines = @($bodyLines | Where-Object { $_ -match '^- \*\*Refs:\*\*' })
foreach ($r in $refLines) {
    $ptrs = @($r -split ' · ')
    if ($ptrs.Count -lt 2 -or $ptrs.Count -gt 4) { Fail "refs: expected 2-4 pointers, got $($ptrs.Count) in '$r'" }
    if ($r -match '\bturn \d') { Fail "refs: turn number in '$r'" }
    if ($r -match '(?i)\bwindow \d') { Fail "refs: window tag in '$r'" }
    if ($r -match 'commit\s+`[0-9a-f]{7,}`') { Fail "refs: commit hash in '$r'" }
    if ($r -match '`[0-9a-f]{40}`') { Fail "refs: full commit hash in '$r'" }
}

    # ---- session transcript exports (enforced) ----
    # Every session the body mentions must have its export beside the report;
    # Export-SessionTranscripts.ps1 -ListOnly is the single mention parser.
    $exportScript = Join-Path $PSScriptRoot 'Export-SessionTranscripts.ps1'
    if (-not (Test-Path -LiteralPath $exportScript)) { Fail "sessions: missing $exportScript" }
    else {
        $mentioned = @()
        $listed = $false
        try { $mentioned = @(& $exportScript -ReportPath $ReportPath -ListOnly); $listed = $true }
        catch { Fail "sessions: cannot list mentioned sessions for '$ReportPath' — $($_.Exception.Message)" }
        if ($listed -and $LASTEXITCODE -ne 0) { Fail "sessions: session listing failed for '$ReportPath' (exit $LASTEXITCODE)" }
        if ($listed) {
            $sessionsDir = Join-Path (Split-Path $ReportPath -Parent) 'sessions'
            foreach ($sid in $mentioned) {
                if ($sid -and -not (Test-Path -LiteralPath (Join-Path $sessionsDir "$sid.html"))) {
                    Fail "sessions: no exported transcript for session $sid — run scripts/Export-SessionTranscripts.ps1 -ReportPath '$ReportPath'"
                }
            }
        }
    }

# ---- budget (frontmatter + body) ----
# A budget failure must localize the cut: words per section, heaviest first.
function Get-SectionWords([string]$Text) {
    $chunks = @([regex]::Split($Text, '(?m)(?=^## )'))
    $rows = @()
    for ($i = 0; $i -lt $chunks.Count; $i++) {
        $first = ($chunks[$i] -split "`n")[0]
        $name = if ($i -eq 0) { 'frontmatter+title' } else { ($first -replace '^##\s+', '').Trim() }
        $w = @(($chunks[$i] -split '\s+') | Where-Object { $_ }).Count
        if ($w -gt 0) { $rows += [pscustomobject]@{ n = $name; w = $w } }
    }
    (($rows | Sort-Object w -Descending | ForEach-Object { "$($_.n)=$($_.w)" }) -join ', ')
}
$totalLines = $lines.Count
if ($totalLines -gt 56) { Fail "budget: $totalLines lines (max 56) — words by section: $(Get-SectionWords $content)" }
$totalWords = @(($content -split '\s+') | Where-Object { $_ }).Count
if ($totalWords -gt 600) { Fail "budget: $totalWords words (max 600) — words by section: $(Get-SectionWords $content)" }

# ---- glossary: schema + report-to-canonical consistency ----
if (-not $GlossaryPath) { $GlossaryPath = Join-Path (Split-Path $ReportPath -Parent) 'glossary.md' }
$mergeScript = Join-Path $PSScriptRoot 'Merge-Glossary.ps1'
$canonical = @{}
if (Test-Path $GlossaryPath) {
    $v = & $mergeScript -GlossaryPath $GlossaryPath -Validate 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "glossary: schema validation failed — $v" }
    else {
        $gl = [IO.File]::ReadAllText($GlossaryPath)
        foreach ($row in ($gl -split "\r?\n")) {
            if ($row -match '^\|' -and $row -notmatch '^\|[\s:|-]+\|$' -and $row -ne '| Term | Meaning |') {
                $parts = @($row -split '(?<!\\)\|')
                if ($parts.Count -ge 2) {
                    $parts = $parts[1..($parts.Count - 1)]
                    if ($parts.Count -ge 1 -and $parts[$parts.Count - 1].Trim() -eq '') { $parts = $parts[0..($parts.Count - 2)] }
                    if ($parts.Count -eq 2) {
                        $canonical[($parts[0] -replace '\\\|', '|').Trim().ToLowerInvariant()] = ($parts[1] -replace '\\\|', '|').Trim()
                    }
                }
            }
        }
    }
}
else { Fail "glossary: missing $GlossaryPath" }

$glSection = [regex]::Match($body, '(?ms)^## Glossary\s*$\n(.*?)(?=\n## |\z)')
if ($glSection.Success) {
    $glLines = @($glSection.Groups[1].Value -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $headerIdx = [array]::IndexOf($glLines, '| Term | Status | Meaning |')
    if ($headerIdx -lt 0) { Fail 'glossary: report needs the exact | Term | Status | Meaning | header' }
    $glRows = @($glLines | Where-Object { $_ -match '^\| .+ \| (NEW|known) \|' })
    if ($glRows.Count -gt 8) { Fail "glossary: $($glRows.Count) rows (max 8)" }
    $statusFirst = $true; $seenKnown = $false
    foreach ($row in $glRows) {
        $parts = @($row -split '(?<!\\)\|')[1..3]
        $term = ($parts[0] -replace '\\\|', '|').Trim()
        $status = $parts[1].Trim()
        $meaning = ($parts[2] -replace '\\\|', '|').Trim()
        if ($status -eq 'known') { $seenKnown = $true }
        elseif ($status -eq 'NEW' -and $seenKnown) { Fail 'glossary: NEW rows must come before known rows' }
        if ($status -notin @('NEW', 'known')) { Fail "glossary: status '$status' is not NEW/known" }
        if ($status -eq 'known') {
            $key = $term.ToLowerInvariant()
            if (-not $canonical.ContainsKey($key)) { Fail "glossary: known term '$term' is absent from canonical" }
            elseif ($canonical[$key] -cne $meaning) { Fail "glossary: known term '$term' meaning differs from canonical verbatim" }
        }
    }
}
else { Fail 'glossary: report has no Glossary section' }

# ---- empty-source honesty (with -EvidenceJson) ----
if ($EvidenceJson -and (Test-Path $EvidenceJson)) {
    $ev = Get-Content $EvidenceJson -Raw | ConvertFrom-Json
    $commits = if ($ev.commits) { @($ev.commits).Count } else { 0 }
    $sessions = if ($ev.sessions) { @($ev.sessions).Count } elseif ($ev.sessionCount) { [int]$ev.sessionCount } else { 0 }
    $working = if ($ev.workingTree) { @($ev.workingTree).Count } else { 0 }
    if ($commits -eq 0 -and $sessions -eq 0 -and $working -eq 0) {
        if ($body -notmatch '(?i)gap|no evidence|no session|no commit') {
            Fail 'empty-source honesty: grounding returned zero rows and the report states no gap'
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output "PASS: $ReportPath"
exit 0
