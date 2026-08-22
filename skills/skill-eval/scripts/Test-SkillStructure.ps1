<#
.SYNOPSIS
    Validates the structural integrity of a skill directory.

.DESCRIPTION
    Checks that a skill directory contains the required files and conformant schemas:
    - SKILL.md exists with valid YAML frontmatter (name, description fields)
    - description field is within 1024 characters
    - evals/eval.json exists and parses as valid JSON with correct schema
    - activation-matrix.md (if present) has valid column structure
    - No duplicate assertion IDs within cases
    - Assertion types are from the allowed set

    This script is part of the generic empirical audit toolkit and works on any skill.

.PARAMETER SkillDir
    Path to the skill directory to validate. Must contain SKILL.md.

.EXAMPLE
    pwsh -NoProfile -File Test-SkillStructure.ps1 -SkillDir skills/my-skill
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SkillDir
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ── Resolve and validate skill directory ──

$resolvedPath = (Resolve-Path -Path $SkillDir -ErrorAction SilentlyContinue)
if (-not $resolvedPath -or -not (Test-Path -Path $resolvedPath -PathType Container)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'structural'
        compliant   = $false
        errors      = @("Skill directory not found: $SkillDir")
        warnings    = @()
    } | ConvertTo-Json -Depth 10)
    exit 2
}

$skillDirPath = $resolvedPath.Path
$skillMdPath  = Join-Path $skillDirPath 'SKILL.md'

if (-not (Test-Path -Path $skillMdPath -PathType Leaf)) {
    Write-Output ([pscustomobject]@{
        audit_type  = 'structural'
        compliant   = $false
        errors      = @("SKILL.md not found in: $skillDirPath")
        warnings    = @()
    } | ConvertTo-Json -Depth 10)
    exit 1
}

$errors   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

# ── Validate SKILL.md frontmatter ──

$skillContent = Get-Content -Path $skillMdPath -Raw
$frontmatterMatch = [regex]::Match($skillContent, '^---\s*\r?\n(.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)

if (-not $frontmatterMatch.Success) {
    $errors.Add('SKILL.md has no YAML frontmatter (--- delimiters not found)')
}
else {
    $frontmatter = $frontmatterMatch.Groups[1].Value

    # Check for name field
    if ($frontmatter -notmatch '(?m)^name\s*:') {
        $errors.Add('SKILL.md frontmatter missing required field: name')
    }

    # Check for description field
    if ($frontmatter -notmatch '(?m)^description\s*:') {
        $errors.Add('SKILL.md frontmatter missing required field: description')
    }
    else {
        # Extract description value and check length
        $descMatch = [regex]::Match($frontmatter, '(?m)^description\s*:\s*(.+)$')
        if ($descMatch.Success) {
            $descValue = $descMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
            if ($descValue.Length -gt 1024) {
                $errors.Add("SKILL.md description field exceeds 1024 characters (actual: $($descValue.Length))")
            }
        }
    }
}

# ── Validate evals/eval.json ──

$evalJsonPath = Join-Path $skillDirPath 'evals' | Join-Path -ChildPath 'eval.json'

if (-not (Test-Path -Path $evalJsonPath -PathType Leaf)) {
    $warnings.Add('evals/eval.json not found (required for execution quality audit)')
}
else {
    try {
        $evalRaw = Get-Content -Path $evalJsonPath -Raw
        $evalData = $evalRaw | ConvertFrom-Json
    }
    catch {
        $errors.Add("evals/eval.json is not valid JSON: $($_.Exception.Message)")
        $evalData = $null
    }

    if ($null -ne $evalData) {
        # Check top-level keys
        if (-not ($evalData.PSObject.Properties.Name -contains 'cases')) {
            $errors.Add('eval.json missing required field: cases')
        }
        else {
            $cases = $evalData.cases
            if ($cases.Count -eq 0) {
                $errors.Add('eval.json cases array is empty (must have at least 1 case)')
            }

            $seenAssertionIds = @{}

            foreach ($case in $cases) {
                $caseId = if ($case.id) { $case.id } else { '<missing-id>' }

                if (-not ($case.PSObject.Properties.Name -contains 'id')) {
                    $errors.Add("Case missing required field: id")
                }
                if (-not ($case.PSObject.Properties.Name -contains 'prompt')) {
                    $errors.Add("Case '$caseId' missing required field: prompt")
                }
                if (-not ($case.PSObject.Properties.Name -contains 'expected_trigger')) {
                    $errors.Add("Case '$caseId' missing required field: expected_trigger")
                }
                if (-not ($case.PSObject.Properties.Name -contains 'assertions')) {
                    $errors.Add("Case '$caseId' missing required field: assertions")
                }
                else {
                    $allowedTypes = @('structural', 'formatting', 'readability', 'domain-bound', 'coverage', 'semantic')

                    foreach ($assertion in $case.assertions) {
                        $assertionId = if ($assertion.id) { $assertion.id } else { '<missing-id>' }

                        if (-not ($assertion.PSObject.Properties.Name -contains 'id')) {
                            $errors.Add("Assertion in case '$caseId' missing required field: id")
                        }
                        if (-not ($assertion.PSObject.Properties.Name -contains 'type')) {
                            $errors.Add("Assertion '$assertionId' in case '$caseId' missing required field: type")
                        }
                        elseif ($assertion.type -notin $allowedTypes) {
                            $errors.Add("Assertion '$assertionId' in case '$caseId' has invalid type '$($assertion.type)'. Allowed: $($allowedTypes -join ', ')")
                        }
                        if (-not ($assertion.PSObject.Properties.Name -contains 'description')) {
                            $errors.Add("Assertion '$assertionId' in case '$caseId' missing required field: description")
                        }
                        if (-not ($assertion.PSObject.Properties.Name -contains 'passes_when')) {
                            $errors.Add("Assertion '$assertionId' in case '$caseId' missing required field: passes_when")
                        }

                        # Check for duplicate assertion IDs within a case
                        $compositeKey = "$caseId::$assertionId"
                        if ($assertionId -ne '<missing-id>') {
                            if ($seenAssertionIds.ContainsKey($compositeKey)) {
                                $errors.Add("Duplicate assertion ID '$assertionId' in case '$caseId'")
                            }
                            else {
                                $seenAssertionIds[$compositeKey] = $true
                            }
                        }
                    }
                }
            }
        }
    }
}

# ── Validate activation-matrix.md (optional) ──

$activationMatrixPath = Join-Path $skillDirPath 'activation-matrix.md'

if (Test-Path -Path $activationMatrixPath -PathType Leaf) {
    $matrixContent = Get-Content -Path $activationMatrixPath -Raw

    # Check for required table columns
    $requiredColumns = @('ID', 'Prompt', 'Should Trigger', 'Actual Trigger')
    foreach ($col in $requiredColumns) {
        if ($matrixContent -notmatch "(?m)\|\s*$col\s*\|") {
            $warnings.Add("activation-matrix.md missing expected column: $col")
        }
    }
}

# ── Output report ──

$report = [pscustomobject]@{
    audit_type  = 'structural'
    compliant   = ($errors.Count -eq 0)
    skill_dir   = $skillDirPath
    errors      = @($errors)
    warnings    = @($warnings)
    checked     = [ordered]@{
        skill_md_frontmatter    = (Test-Path -Path $skillMdPath -PathType Leaf)
        eval_json_exists        = (Test-Path -Path $evalJsonPath -PathType Leaf)
        activation_matrix_exists = (Test-Path -Path $activationMatrixPath -PathType Leaf)
    }
}

Write-Output ($report | ConvertTo-Json -Depth 10)

if ($errors.Count -gt 0) {
    exit 1
}
exit 0
