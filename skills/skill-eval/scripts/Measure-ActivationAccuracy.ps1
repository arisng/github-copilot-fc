<#
.SYNOPSIS
    Measures activation accuracy from an activation matrix markdown file.

.DESCRIPTION
    Reads activation-matrix.md from a skill directory and computes activation
    accuracy metrics: true positives, false positives, true negatives, false
    negatives, accuracy, precision, recall, and false positive/negative rates.

    Pending rows (where Actual Trigger = "pending") are excluded from computation
    and reported separately.

    This script is a metrics computer — filling the Actual Trigger column is a
    manual step. This script does not test skill triggers against a runtime.

    This script is part of the generic empirical audit toolkit and works on any skill.

.PARAMETER SkillDir
    Path to the skill directory containing activation-matrix.md.

.PARAMETER Threshold
    Minimum accuracy percentage (0-100) to pass. Defaults to 80.

.EXAMPLE
    pwsh -NoProfile -File Measure-ActivationAccuracy.ps1 -SkillDir skills/my-skill

.EXAMPLE
    pwsh -NoProfile -File Measure-ActivationAccuracy.ps1 -SkillDir skills/my-skill -Threshold 90
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SkillDir,

    [Parameter()]
    [ValidateRange(0, 100)]
    [double]$Threshold = 80
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ── Resolve and validate skill directory ──

$resolvedPath = (Resolve-Path -Path $SkillDir -ErrorAction SilentlyContinue)
if (-not $resolvedPath -or -not (Test-Path -Path $resolvedPath -PathType Container)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'activation'
        error       = "Skill directory not found: $SkillDir"
        accuracy    = 0
        passed      = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

$skillDirPath      = $resolvedPath.Path
$activationMdPath  = Join-Path $skillDirPath 'activation-matrix.md'

if (-not (Test-Path -Path $activationMdPath -PathType Leaf)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'activation'
        error       = "activation-matrix.md not found in: $skillDirPath"
        accuracy    = 0
        passed      = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Parse markdown table ──

$lines = Get-Content -Path $activationMdPath

# Find the table header row (must contain | separators)
$tableStartIndex = -1
$headerLine = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^\|.*\|.*\|$' -and $line -match 'ID.*Prompt.*Should.*Trigger') {
        $tableStartIndex = $i
        $headerLine = $line
        break
    }
}

if ($tableStartIndex -eq -1) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'activation'
        error       = 'No valid activation matrix table found (missing header row with ID, Prompt, Should Trigger, Actual Trigger columns)'
        accuracy    = 0
        passed      = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# Skip separator row (|---|---|...)
$dataStartIndex = $tableStartIndex + 2

# Parse header columns
$headers = $headerLine -split '\|' | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }

$shouldTriggerCol = -1
$actualTriggerCol = -1
$idCol = -1
for ($i = 0; $i -lt $headers.Count; $i++) {
    switch -Regex ($headers[$i]) {
        '^ID$'            { $idCol = $i }
        '^Should Trigger$' { $shouldTriggerCol = $i }
        '^Actual Trigger$' { $actualTriggerCol = $i }
    }
}

if ($shouldTriggerCol -eq -1 -or $actualTriggerCol -eq -1) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'activation'
        error       = 'Table missing required columns: Should Trigger, Actual Trigger'
        accuracy    = 0
        passed      = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Extract rows ──

$dataRows = @()
for ($i = $dataStartIndex; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^\|.*\|$') {
        $cells = $line -split '\|' | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }
        if ($cells.Count -gt [math]::Max($shouldTriggerCol, $actualTriggerCol)) {
            $dataRows += [pscustomobject]@{
                id              = if ($idCol -ge 0 -and $idCol -lt $cells.Count) { $cells[$idCol] } else { "row-$($i - $tableStartIndex)" }
                should_trigger  = $cells[$shouldTriggerCol].ToLower()
                actual_trigger  = $cells[$actualTriggerCol].ToLower()
            }
        }
    }
}

if ($dataRows.Count -eq 0) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'activation'
        error       = 'No data rows found in activation matrix'
        accuracy    = 0
        passed      = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Compute metrics (exclude pending rows) ──

$totalRows     = $dataRows.Count
$pendingRows   = @($dataRows | Where-Object { $_.actual_trigger -eq 'pending' })
$evaluatedRows = @($dataRows | Where-Object { $_.actual_trigger -ne 'pending' })

$tp = 0; $fp = 0; $tn = 0; $fn = 0
foreach ($row in $evaluatedRows) {
    $shouldYes = ($row.should_trigger -eq 'yes')
    $actualYes = ($row.actual_trigger -eq 'yes')

    if ($shouldYes -and $actualYes)     { $tp++ }
    elseif ($shouldYes -and -not $actualYes) { $fn++ }
    elseif (-not $shouldYes -and $actualYes) { $fp++ }
    else { $tn++ }
}

$evaluatedCount = $evaluatedRows.Count
$accuracy   = if ($evaluatedCount -gt 0) { [math]::Round(($tp + $tn) / $evaluatedCount * 100, 2) } else { 0 }
$precision  = if (($tp + $fp) -gt 0) { [math]::Round($tp / ($tp + $fp) * 100, 2) } else { 0 }
$recall     = if (($tp + $fn) -gt 0) { [math]::Round($tp / ($tp + $fn) * 100, 2) } else { 0 }
$fpr         = if (($fp + $tn) -gt 0) { [math]::Round($fp / ($fp + $tn) * 100, 2) } else { 0 }
$fnr         = if (($fn + $tp) -gt 0) { [math]::Round($fn / ($fn + $tp) * 100, 2) } else { 0 }

# ── Check balance ──

$positiveCount = @($evaluatedRows | Where-Object { $_.should_trigger -eq 'yes' }).Count
$negativeCount = @($evaluatedRows | Where-Object { $_.should_trigger -eq 'no' }).Count
$warnings = @()

if ($positiveCount -lt 3 -or $negativeCount -lt 3) {
    $warnings += "Imbalanced matrix: $positiveCount positive prompts, $negativeCount negative prompts (recommended: >=3 each)"
}

# ── Output report ──

$report = [pscustomobject]@{
    audit_type          = 'activation'
    skill_dir           = $skillDirPath
    threshold           = $Threshold
    total_rows          = $totalRows
    evaluated_rows      = $evaluatedCount
    pending_count       = $pendingRows.Count
    positive_prompts    = $positiveCount
    negative_prompts    = $negativeCount
    true_positives      = $tp
    false_positives     = $fp
    true_negatives      = $tn
    false_negatives     = $fn
    accuracy            = $accuracy
    precision           = $precision
    recall              = $recall
    false_positive_rate = $fpr
    false_negative_rate = $fnr
    passed              = ($accuracy -ge $Threshold)
    warnings            = @($warnings)
}

Write-Output ($report | ConvertTo-Json -Depth 10)

if ($accuracy -lt $Threshold) {
    exit 1
}
exit 0
