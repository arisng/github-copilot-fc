<#
.SYNOPSIS
    Compares two audit reports to verify improvement delta.

.DESCRIPTION
    Takes two JSON audit reports (before and after a rule change) and computes
    whether the change improved metrics without introducing regressions.

    Both reports must have the same audit_type field. The script validates this
    and exits with code 2 on mismatch.

    For execution reports: matches assertions by ID, computes normalized score
    delta on the intersection, reports added/removed/changed assertions.
    For activation reports: compares accuracy and false positive/negative rates.
    For structural reports: compares error counts.

    This script is part of the generic empirical audit toolkit and works on any skill.

.PARAMETER BeforeReport
    Path to the before-change JSON audit report file.

.PARAMETER AfterReport
    Path to the after-change JSON audit report file.

.EXAMPLE
    pwsh -NoProfile -File Compare-AuditDelta.ps1 -BeforeReport before.json -AfterReport after.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BeforeReport,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AfterReport
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ── Load and parse reports ──

function Load-Report {
    param([string]$Path, [string]$Label)

    $resolved = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)
    if (-not $resolved -or -not (Test-Path -Path $resolved.Path -PathType Leaf)) {
        Write-Output ([pscustomobject]@{
            error  = "$Label report not found: $Path"
            passed = $false
        } | ConvertTo-Json -Depth 10)
        exit 2
    }

    try {
        return Get-Content -Path $resolved.Path -Raw | ConvertFrom-Json
    }
    catch {
        Write-Output ([pscustomobject]@{
            error  = "Failed to parse $Label report: $($_.Exception.Message)"
            passed = $false
        } | ConvertTo-Json -Depth 10)
        exit 2
    }
}

$before = Load-Report -Path $BeforeReport -Label 'Before'
$after  = Load-Report -Path $AfterReport -Label 'After'

# ── Validate audit_type match ──

$beforeType = $before.audit_type
$afterType  = $after.audit_type

if (-not $beforeType -or -not $afterType) {
    Write-Output ([pscustomobject]@{
        error  = 'One or both reports missing audit_type field'
        passed = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

if ($beforeType -ne $afterType) {
    Write-Output ([pscustomobject]@{
        error  = "Audit type mismatch: before='$beforeType', after='$afterType'"
        passed = $false
    } | ConvertTo-Json -Depth 10)
    exit 2
}

# ── Compute delta based on audit type ──

$improved = $false
$regressions  = [System.Collections.Generic.List[string]]::new()
$improvements = [System.Collections.Generic.List[string]]::new()

switch ($beforeType) {
    'structural' {
        $beforeErrors = if ($before.errors) { $before.errors.Count } else { 0 }
        $afterErrors  = if ($after.errors) { $after.errors.Count } else { 0 }

        if ($afterErrors -lt $beforeErrors) {
            $improved = $true
            $improvements.Add("Error count reduced: $beforeErrors -> $afterErrors")
        }
        elseif ($afterErrors -gt $beforeErrors) {
            $regressions.Add("Error count increased: $beforeErrors -> $afterErrors")
        }

        $delta = [pscustomobject]@{
            audit_type      = 'structural'
            before_errors   = $beforeErrors
            after_errors    = $afterErrors
            delta           = ($afterErrors - $beforeErrors)
            improved        = $improved
            improvements    = @($improvements)
            regressions     = @($regressions)
        }
    }

    'execution' {
        $beforeRate = if ($before.pass_rate) { [double]$before.pass_rate } else { 0 }
        $afterRate  = if ($after.pass_rate) { [double]$after.pass_rate } else { 0 }

        # Build lookup tables by assertion ID
        $beforeMap = @{}
        $afterMap  = @{}

        foreach ($case in $before.cases) {
            foreach ($assertion in $case.assertions) {
                if ($assertion.id -and $assertion.id -ne '_sample_missing') {
                    $beforeMap[$assertion.id] = $assertion.status
                }
            }
        }

        foreach ($case in $after.cases) {
            foreach ($assertion in $case.assertions) {
                if ($assertion.id -and $assertion.id -ne '_sample_missing') {
                    $afterMap[$assertion.id] = $assertion.status
                }
            }
        }

        # Find intersection, additions, removals
        $beforeIds = @($beforeMap.Keys)
        $afterIds  = @($afterMap.Keys)
        $commonIds = @($beforeIds | Where-Object { $afterIds -contains $_ })
        $addedIds  = @($afterIds | Where-Object { $beforeIds -notcontains $_ })
        $removedIds = @($beforeIds | Where-Object { $afterIds -notcontains $_ })

        $regressedAssertions = [System.Collections.Generic.List[string]]::new()
        $improvedAssertions  = [System.Collections.Generic.List[string]]::new()

        foreach ($id in $commonIds) {
            $bStatus = $beforeMap[$id]
            $aStatus = $afterMap[$id]

            if ($bStatus -eq 'pass' -and $aStatus -eq 'fail') {
                $regressedAssertions.Add($id)
            }
            elseif ($bStatus -eq 'fail' -and $aStatus -eq 'pass') {
                $improvedAssertions.Add($id)
            }
        }

        # Compute normalized score on intersection
        $beforeIntersectionPassed = @($commonIds | Where-Object { $beforeMap[$_] -eq 'pass' }).Count
        $afterIntersectionPassed  = @($commonIds | Where-Object { $afterMap[$_] -eq 'pass' }).Count
        $intersectionCount = $commonIds.Count

        if ($regressedAssertions.Count -gt 0) {
            $regressions.Add("Regressed assertions: $($regressedAssertions -join ', ')")
        }
        if ($improvedAssertions.Count -gt 0) {
            $improvements.Add("Improved assertions: $($improvedAssertions -join ', ')")
        }
        if ($addedIds.Count -gt 0) {
            $improvements.Add("Added assertions: $($addedIds -join ', ')")
        }
        if ($removedIds.Count -gt 0) {
            $regressions.Add("Removed assertions: $($removedIds -join ', ')")
        }

        $improved = ($regressedAssertions.Count -eq 0 -and $afterIntersectionPassed -ge $beforeIntersectionPassed)

        $delta = [pscustomobject]@{
            audit_type                  = 'execution'
            before_pass_rate            = $beforeRate
            after_pass_rate             = $afterRate
            before_intersection_passed  = $beforeIntersectionPassed
            after_intersection_passed   = $afterIntersectionPassed
            intersection_count          = $intersectionCount
            added_assertions            = @($addedIds)
            removed_assertions          = @($removedIds)
            improved_assertions         = @($improvedAssertions)
            regressed_assertions        = @($regressedAssertions)
            improved                    = $improved
            improvements                = @($improvements)
            regressions                 = @($regressions)
        }
    }

    'activation' {
        $beforeAccuracy = if ($before.accuracy) { [double]$before.accuracy } else { 0 }
        $afterAccuracy  = if ($after.accuracy) { [double]$after.accuracy } else { 0 }

        $beforeFpr = if ($before.false_positive_rate) { [double]$before.false_positive_rate } else { 0 }
        $afterFpr  = if ($after.false_positive_rate) { [double]$after.false_positive_rate } else { 0 }

        $beforeFnr = if ($before.false_negative_rate) { [double]$before.false_negative_rate } else { 0 }
        $afterFnr  = if ($after.false_negative_rate) { [double]$after.false_negative_rate } else { 0 }

        if ($afterAccuracy -gt $beforeAccuracy) {
            $improved = $true
            $improvements.Add("Accuracy improved: $beforeAccuracy% -> $afterAccuracy%")
        }
        elseif ($afterAccuracy -lt $beforeAccuracy) {
            $regressions.Add("Accuracy regressed: $beforeAccuracy% -> $afterAccuracy%")
        }

        if ($afterFpr -gt $beforeFpr) {
            $regressions.Add("False positive rate increased: $beforeFpr% -> $afterFpr%")
        }
        elseif ($afterFpr -lt $beforeFpr) {
            $improvements.Add("False positive rate reduced: $beforeFpr% -> $afterFpr%")
        }

        if ($afterFnr -gt $beforeFnr) {
            $regressions.Add("False negative rate increased: $beforeFnr% -> $afterFnr%")
        }
        elseif ($afterFnr -lt $beforeFnr) {
            $improvements.Add("False negative rate reduced: $beforeFnr% -> $afterFnr%")
        }

        $improved = ($regressions.Count -eq 0 -and $afterAccuracy -ge $beforeAccuracy)

        $delta = [pscustomobject]@{
            audit_type              = 'activation'
            before_accuracy         = $beforeAccuracy
            after_accuracy          = $afterAccuracy
            accuracy_delta          = [math]::Round($afterAccuracy - $beforeAccuracy, 2)
            before_false_pos_rate   = $beforeFpr
            after_false_pos_rate    = $afterFpr
            before_false_neg_rate   = $beforeFnr
            after_false_neg_rate    = $afterFnr
            improved                = $improved
            improvements            = @($improvements)
            regressions             = @($regressions)
        }
    }

    default {
        Write-Output ([pscustomobject]@{
            error  = "Unknown audit_type: $beforeType"
            passed = $false
        } | ConvertTo-Json -Depth 10)
        exit 2
    }
}

# ── Output report ──

$report = [pscustomobject]@{
    delta       = $delta
    passed      = $improved
}

Write-Output ($report | ConvertTo-Json -Depth 10)

if (-not $improved) {
    exit 1
}
exit 0
