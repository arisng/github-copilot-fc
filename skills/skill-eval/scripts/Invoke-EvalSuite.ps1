<#
.SYNOPSIS
    Evaluates binary assertions from eval.json against output samples.

.DESCRIPTION
    Reads evals/eval.json from a skill directory and evaluates each assertion's
    passes_when expression against corresponding output sample files. Uses a
    whitelist-based expression dispatcher — Invoke-Expression is forbidden.

    Output samples are expected at OutputSamplesDir/<case-id>.md.

    Supports an -ExpressionSyntaxOnly switch for dry-run mode that validates
    expression parseability without requiring output files.

    This script is part of the generic empirical audit toolkit and works on any skill.

.PARAMETER SkillDir
    Path to the skill directory containing evals/eval.json.

.PARAMETER OutputSamplesDir
    Path to directory containing output sample files. Files must be named
    <case-id>.md matching the id field in eval.json. If omitted and
    -ExpressionSyntaxOnly is not set, the script exits with code 2.

.PARAMETER ExpressionSyntaxOnly
    When set, validates that every passes_when expression matches the supported
    grammar without requiring output files. Useful for checking eval.json quality.

.EXAMPLE
    pwsh -NoProfile -File Invoke-EvalSuite.ps1 -SkillDir skills/my-skill -OutputSamplesDir skills/my-skill/evals/samples

.EXAMPLE
    pwsh -NoProfile -File Invoke-EvalSuite.ps1 -SkillDir skills/my-skill -ExpressionSyntaxOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SkillDir,

    [Parameter()]
    [string]$OutputSamplesDir,

    [switch]$ExpressionSyntaxOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ── Resolve and validate skill directory ──

$resolvedPath = (Resolve-Path -Path $SkillDir -ErrorAction SilentlyContinue)
if (-not $resolvedPath -or -not (Test-Path -Path $resolvedPath -PathType Container)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'execution'
        error       = "Skill directory not found: $SkillDir"
        score       = 0
        pass_rate   = 0
        cases       = @()
    } | ConvertTo-Json -Depth 10)
    exit 2
}

$skillDirPath = $resolvedPath.Path
$evalJsonPath = Join-Path $skillDirPath 'evals' | Join-Path -ChildPath 'eval.json'

if (-not (Test-Path -Path $evalJsonPath -PathType Leaf)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'execution'
        error       = "evals/eval.json not found in: $skillDirPath"
        score       = 0
        pass_rate   = 0
        cases       = @()
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Parse eval.json ──

try {
    $evalData = Get-Content -Path $evalJsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-Output ([pscustomobject]@{
        audit_type  = 'execution'
        error       = "Failed to parse eval.json: $($_.Exception.Message)"
        score       = 0
        pass_rate   = 0
        cases       = @()
    } | ConvertTo-Json -Depth 10)
    exit 2
}

if (-not $evalData.cases -or @( $evalData.cases ).Count -eq 0) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'execution'
        error       = 'eval.json cases array is empty'
        score       = 0
        pass_rate   = 0
        cases       = @()
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Validate output samples directory ──

if (-not $ExpressionSyntaxOnly) {
    if (-not $OutputSamplesDir) {
        Write-Output ([pscustomobject]@{
            audit_type  = 'execution'
            error       = 'OutputSamplesDir is required when -ExpressionSyntaxOnly is not set'
            score       = 0
            pass_rate   = 0
            cases       = @()
        } | ConvertTo-Json -Depth 10)
        exit 2
    }

    $resolvedSamples = (Resolve-Path -Path $OutputSamplesDir -ErrorAction SilentlyContinue)
    if (-not $resolvedSamples -or -not (Test-Path -Path $resolvedSamples -PathType Container)) {
        Write-Output ([pscustomobject]@{
            audit_type  = 'execution'
            error       = "Output samples directory not found: $OutputSamplesDir"
            score       = 0
            pass_rate   = 0
            cases       = @()
        } | ConvertTo-Json -Depth 10)
        exit 2
    }
    $samplesDirPath = $resolvedSamples.Path
}

# ── Expression evaluator (whitelist-based, no Invoke-Expression) ──

function Test-NumericComparison {
    param(
        [string]$LeftValue,
        [string]$Operator,
        [string]$RightValue,
        [string]$OutputText
    )

    $metricValue = switch ($LeftValue) {
        'word_count' {
            @($OutputText -split '\s+' | Where-Object { $_.Length -gt 0 }).Count
        }
        'paragraph_count' {
            @($OutputText -split '\n\s*\n' | Where-Object { $_.Trim().Length -gt 0 }).Count
        }
        'heading_count' {
            @($OutputText -split "`n" | Where-Object { $_ -match '^#{1,6}\s' }).Count
        }
        'sentence_count' {
            # Approximate: split on .!? followed by whitespace
            @($OutputText -split '[.!?]+\s+' | Where-Object { $_.Trim().Length -gt 0 }).Count
        }
        default { return 'skip' }
    }

    $threshold = 0
    if (-not [double]::TryParse($RightValue, [ref]$threshold)) {
        return 'skip'
    }

    switch ($Operator) {
        '<'  { return ($metricValue -lt $threshold) }
        '>'  { return ($metricValue -gt $threshold) }
        '<=' { return ($metricValue -le $threshold) }
        '>=' { return ($metricValue -ge $threshold) }
        '==' { return ($metricValue -eq $threshold) }
        default { return 'skip' }
    }
}

function Test-SentenceConstraints {
    param(
        [string]$ConstraintType,
        [string]$Value,
        [string]$OutputText
    )

    switch ($ConstraintType) {
        'no_sentence_exceeds' {
            $maxWords = 0
            if (-not [int]::TryParse($Value, [ref]$maxWords)) { return 'skip' }
            $sentences = $OutputText -split '[.!?]+\s+' | Where-Object { $_.Trim().Length -gt 0 }
            foreach ($sentence in $sentences) {
                $wordCount = @($sentence -split '\s+' | Where-Object { $_.Length -gt 0 }).Count
                if ($wordCount -gt $maxWords) { return $false }
            }
            return $true
        }
        'paragraph_1_sentence_count' {
            $expected = 0
            if (-not [int]::TryParse($Value, [ref]$expected)) { return 'skip' }
            $paragraphs = $OutputText -split '\n\s*\n' | Where-Object { $_.Trim().Length -gt 0 }
            if ($paragraphs.Count -eq 0) { return $false }
            $firstParagraph = $paragraphs[0]
            $sentenceCount = @($firstParagraph -split '[.!?]+\s+' | Where-Object { $_.Trim().Length -gt 0 }).Count
            return ($sentenceCount -eq $expected)
        }
        default { return 'skip' }
    }
}

function Test-StringConstraint {
    param(
        [string]$FunctionName,
        [string]$Argument,
        [string]$OutputText
    )

    switch ($FunctionName) {
        'contains' {
            return $OutputText.ToLower().Contains($Argument.ToLower())
        }
        'not_contains' {
            return (-not $OutputText.ToLower().Contains($Argument.ToLower()))
        }
        'matches_regex' {
            try {
                return [regex]::IsMatch($OutputText, $Argument)
            }
            catch {
                return 'skip'
            }
        }
        'section_present' {
            $headingText = $Argument.TrimStart('#').TrimStart('=').Trim()
            $pattern = '(?m)^#{1,6}\s+' + [regex]::Escape($headingText) + '\s*$'
            return [regex]::IsMatch($OutputText, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        default { return 'skip' }
    }
}

function Test-HeadingOrder {
    param(
        [string[]]$Headings,
        [string]$OutputText
    )

    $foundOrder = @()
    foreach ($line in ($OutputText -split "`n")) {
        if ($line -match '^#{1,6}\s+(.+)$') {
            $foundOrder += $Matches[1].Trim()
        }
    }

    $lastIndex = -1
    foreach ($heading in $Headings) {
        $idx = -1
        for ($i = $lastIndex + 1; $i -lt $foundOrder.Count; $i++) {
            if ($foundOrder[$i] -ieq $heading) {
                $idx = $i
                break
            }
        }
        if ($idx -eq -1) { return $false }
        $lastIndex = $idx
    }
    return $true
}

function Invoke-AssertionEvaluator {
    param(
        [string]$Expression,
        [string]$OutputText
    )

    $expr = $Expression.Trim()

    # Pattern: metric <op> value  (e.g., word_count < 150)
    if ($expr -match '^(\w+)\s*(<|>|<=|>=|==)\s*(\d+)$') {
        return Test-NumericComparison -LeftValue $Matches[1] -Operator $Matches[2] -RightValue $Matches[3] -OutputText $OutputText
    }

    # Pattern: no_sentence_exceeds(N) or paragraph_1_sentence_count == N
    if ($expr -match '^(\w+)\s*(==|!=)\s*(\d+)$') {
        $metricName = $Matches[1]
        $op = $Matches[2]
        $threshold = [int]$Matches[3]

        $metricValue = switch ($metricName) {
            'word_count' { @($OutputText -split '\s+' | Where-Object { $_.Length -gt 0 }).Count }
            'paragraph_count' { @($OutputText -split '\n\s*\n' | Where-Object { $_.Trim().Length -gt 0 }).Count }
            'heading_count' { @($OutputText -split "`n" | Where-Object { $_ -match '^#{1,6}\s' }).Count }
            'sentence_count' { @($OutputText -split '[.!?]+\s+' | Where-Object { $_.Trim().Length -gt 0 }).Count }
            default { $null }
        }

        if ($null -ne $metricValue) {
            if ($op -eq '==') { return ($metricValue -eq $threshold) }
            else { return ($metricValue -ne $threshold) }
        }
    }

    # Pattern: no_sentence_exceeds(N)
    if ($expr -match '^no_sentence_exceeds\((\d+)\)$') {
        return Test-SentenceConstraints -ConstraintType 'no_sentence_exceeds' -Value $Matches[1] -OutputText $OutputText
    }

    # Pattern: paragraph_1_sentence_count == N
    if ($expr -match '^paragraph_1_sentence_count\s*==\s*(\d+)$') {
        return Test-SentenceConstraints -ConstraintType 'paragraph_1_sentence_count' -Value $Matches[1] -OutputText $OutputText
    }

    # Pattern: heading_order("H1","H2",...)
    if ($expr -match '^heading_order\((.+)\)$') {
        $argsStr = $Matches[1]
        $headings = [regex]::Matches($argsStr, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        return Test-HeadingOrder -Headings $headings -OutputText $OutputText
    }

    # Pattern: function("argument")
    if ($expr -match '^(\w+)\("(.+)"\)$') {
        return Test-StringConstraint -FunctionName $Matches[1] -Argument $Matches[2] -OutputText $OutputText
    }

    # Pattern: metric == true/false
    if ($expr -match '^(\w+)\s*==\s*(true|false)$') {
        $metricName = $Matches[1]
        $expected = [bool]::Parse($Matches[2])

        if ($metricName -eq 'json_valid') {
            try {
                $null = $OutputText | ConvertFrom-Json
                return $expected
            }
            catch {
                return (-not $expected)
            }
        }
    }

    # Unparseable
    return 'skip'
}

# ── Evaluate cases ──

$caseResults = [System.Collections.Generic.List[object]]::new()
$totalPassed = 0
$totalAssertions = 0
$totalSkipped = 0

foreach ($case in $evalData.cases) {
    $caseId = $case.id
    $assertionResults = [System.Collections.Generic.List[object]]::new()

    if ($ExpressionSyntaxOnly) {
        # Dry-run mode: validate expression parseability only
        foreach ($assertion in $case.assertions) {
            $totalAssertions++
            $expr = $assertion.passes_when

            # Quick check: does the expression match any known pattern?
            $isParseable = (
                $expr -match '^\w+\s*(<|>|<=|>=|==)\s*\d+$' -or
                $expr -match '^\w+\s*==\s*(true|false)$' -or
                $expr -match '^\w+\(\d+\)$' -or
                $expr -match '^\w+\s*==\s*\d+$' -or
                $expr -match '^\w+\(".*"\)$' -or
                $expr -match '^\w+\(.*\)$'
            )

            if ($isParseable) {
                $status = 'parseable'
                $totalPassed++
            }
            else {
                $status = 'skipped'
                $totalSkipped++
            }

            $assertionResults.Add([pscustomobject]@{
                id          = $assertion.id
                type        = $assertion.type
                expression  = $expr
                status      = $status
            })
        }
    }
    else {
        # Full evaluation mode: load output sample and evaluate
        $sampleFile = Join-Path $samplesDirPath "$caseId.md"

        if (-not (Test-Path -Path $sampleFile -PathType Leaf)) {
            $assertionResults.Add([pscustomobject]@{
                id      = '_sample_missing'
                status  = 'error'
                message = "Output sample not found: $sampleFile"
            })
        }
        else {
            $outputText = Get-Content -Path $sampleFile -Raw

            foreach ($assertion in $case.assertions) {
                $totalAssertions++
                $result = Invoke-AssertionEvaluator -Expression $assertion.passes_when -OutputText $outputText
                $resultStr = [string]$result

                if ($resultStr -eq 'skip') {
                    $status = 'skipped'
                    $totalSkipped++
                }
                elseif ($resultStr -eq 'True') {
                    $status = 'pass'
                    $totalPassed++
                }
                else {
                    $status = 'fail'
                }

                $assertionResults.Add([pscustomobject]@{
                    id         = $assertion.id
                    type       = $assertion.type
                    expression = $assertion.passes_when
                    status     = $status
                })
            }
        }
    }

    $casePassed = @($assertionResults | Where-Object { $_.status -eq 'pass' }).Count
    $caseTotal  = @($assertionResults | Where-Object { $_.status -ne 'error' }).Count

    $caseResults.Add([pscustomobject]@{
        id          = $caseId
        prompt      = $case.prompt
        assertions  = @($assertionResults)
        passed      = $casePassed
        total       = $caseTotal
    })
}

# ── Compute aggregate score ──

$effectiveTotal = $totalAssertions - $totalSkipped
$passRate = if ($effectiveTotal -gt 0) { [math]::Round($totalPassed / $effectiveTotal, 4) } else { 0 }

$report = [pscustomobject]@{
    audit_type      = 'execution'
    skill           = $evalData.skill
    objective       = $evalData.objective
    mode            = if ($ExpressionSyntaxOnly) { 'syntax_only' } else { 'full' }
    total_assertions = $totalAssertions
    passed          = $totalPassed
    skipped         = $totalSkipped
    effective_total = $effectiveTotal
    score           = "$totalPassed/$effectiveTotal"
    pass_rate       = $passRate
    cases           = @($caseResults)
}

Write-Output ($report | ConvertTo-Json -Depth 10)

if ($totalPassed -lt $effectiveTotal) {
    exit 1
}
exit 0
