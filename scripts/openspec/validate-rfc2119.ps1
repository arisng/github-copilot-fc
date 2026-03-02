<#
.SYNOPSIS
    Audits OpenSpec spec files for RFC 2119 keyword presence and scenario coverage.

.DESCRIPTION
    Verifies that every requirement (identified by domain-prefixed ID) in each spec
    file contains at least one RFC 2119 keyword (MUST, SHALL, SHOULD, MAY, MUST NOT,
    SHALL NOT, SHOULD NOT) and has at least one associated GIVEN/WHEN/THEN scenario.

.EXAMPLE
    pwsh -NoProfile -File scripts/openspec/validate-rfc2119.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SpecsRoot = (Join-Path $PSScriptRoot '..\..\openspec\specs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$DomainPrefixes = @('SES', 'SIG', 'ORCH', 'PLAN', 'DISC', 'EXEC', 'REV', 'KNOW')
$IdPattern = '(' + ($DomainPrefixes -join '|') + ')-(\d{3})'
$Rfc2119Keywords = @('MUST NOT', 'SHALL NOT', 'SHOULD NOT', 'MUST', 'SHALL', 'SHOULD', 'MAY')
# Pattern matches RFC 2119 keywords as standalone uppercase words
$Rfc2119Pattern = '\b(' + (($Rfc2119Keywords | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
function Get-SpecFiles {
    [CmdletBinding()]
    param([string]$Root)

    $resolved = Resolve-Path -Path $Root -ErrorAction Stop
    Get-ChildItem -Path $resolved -Filter 'spec.md' -Recurse -File
}

function Get-RequirementBlocks {
    <#
    .SYNOPSIS
        Parses a spec file and extracts requirement blocks. Each block starts at a
        heading containing a requirement ID and extends until the next heading of
        same or higher level, or end of file.
    #>
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$Pattern
    )

    $lines = Get-Content -Path $FilePath -Encoding utf8
    $blocks = @()
    $currentBlock = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Detect heading lines
        if ($line -match '^(#{1,6})\s+(.+)$') {
            $headingLevel = $Matches[1].Length
            $headingText = $Matches[2]

            # Check if this heading contains a requirement ID
            $idMatch = [regex]::Match($headingText, $Pattern)
            if ($idMatch.Success) {
                # Save previous block
                if ($null -ne $currentBlock) {
                    $blocks += $currentBlock
                }
                $currentBlock = @{
                    Id           = $idMatch.Value
                    HeadingLevel = $headingLevel
                    StartLine    = $i + 1
                    Lines        = @($line)
                }
                continue
            }

            # If we hit a heading of same or higher level, close current block
            if ($null -ne $currentBlock -and $headingLevel -le $currentBlock.HeadingLevel) {
                $blocks += $currentBlock
                $currentBlock = $null
            }
        }

        # Accumulate lines into current block
        if ($null -ne $currentBlock) {
            $currentBlock.Lines += $line
        }
    }

    # Save last block
    if ($null -ne $currentBlock) {
        $blocks += $currentBlock
    }

    return $blocks
}

function Test-Rfc2119Presence {
    <#
    .SYNOPSIS
        Checks whether a requirement block contains at least one RFC 2119 keyword.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    foreach ($line in $Lines) {
        if ($line -cmatch $Pattern) {
            return $true
        }
    }
    return $false
}

function Test-ScenarioPresence {
    <#
    .SYNOPSIS
        Checks whether a requirement block contains at least one GIVEN/WHEN/THEN scenario.
    #>
    [CmdletBinding()]
    param([string[]]$Lines)

    $hasGiven = $false
    $hasWhen = $false
    $hasThen = $false

    foreach ($line in $Lines) {
        if ($line -match '\bGIVEN\b') { $hasGiven = $true }
        if ($line -match '\bWHEN\b') { $hasWhen = $true }
        if ($line -match '\bTHEN\b') { $hasThen = $true }
    }

    return ($hasGiven -and $hasWhen -and $hasThen)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-Rfc2119Audit {
    [CmdletBinding()]
    param(
        [string]$SpecsRoot
    )

    $specFiles = Get-SpecFiles -Root $SpecsRoot
    if ($specFiles.Count -eq 0) {
        Write-Warning "No spec.md files found under '$SpecsRoot'."
        return 0
    }

    Write-Information "Auditing $($specFiles.Count) spec file(s) for RFC 2119 compliance..." -InformationAction Continue

    $totalRequirements = 0
    $missingKeyword = 0
    $missingScenario = 0
    $specsRootResolved = (Resolve-Path (Join-Path $SpecsRoot '..')).Path

    foreach ($file in $specFiles) {
        $relativePath = $file.FullName.Replace($specsRootResolved, '').TrimStart('\', '/')
        $blocks = Get-RequirementBlocks -FilePath $file.FullName -Pattern $IdPattern

        foreach ($block in $blocks) {
            $totalRequirements++

            $hasKeyword = Test-Rfc2119Presence -Lines $block.Lines -Pattern $Rfc2119Pattern
            $hasScenario = Test-ScenarioPresence -Lines $block.Lines

            if (-not $hasKeyword) {
                Write-Information "  MISSING RFC 2119: $($block.Id) at $relativePath`:$($block.StartLine)" -InformationAction Continue
                $missingKeyword++
            }
            if (-not $hasScenario) {
                Write-Information "  MISSING SCENARIO: $($block.Id) at $relativePath`:$($block.StartLine)" -InformationAction Continue
                $missingScenario++
            }
        }
    }

    Write-Information '' -InformationAction Continue
    Write-Information "--- RFC 2119 Audit Summary ---" -InformationAction Continue
    Write-Information "Files scanned:            $($specFiles.Count)" -InformationAction Continue
    Write-Information "Total requirements found: $totalRequirements" -InformationAction Continue
    Write-Information "Missing RFC 2119 keyword: $missingKeyword" -InformationAction Continue
    Write-Information "Missing scenario:         $missingScenario" -InformationAction Continue

    $failures = $missingKeyword + $missingScenario
    if ($failures -eq 0) {
        if ($totalRequirements -eq 0) {
            Write-Information "PASS (trivial): No requirements found to audit." -InformationAction Continue
        }
        else {
            Write-Information "PASS: All $totalRequirements requirement(s) have RFC 2119 keywords and scenarios." -InformationAction Continue
        }
    }
    else {
        Write-Information "FAIL: $failures issue(s) found across $totalRequirements requirement(s)." -InformationAction Continue
    }

    return $failures
}

$exitCode = Invoke-Rfc2119Audit -SpecsRoot $SpecsRoot
exit $exitCode
