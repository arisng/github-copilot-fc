<#
.SYNOPSIS
    Validates that all cross-domain requirement ID references in OpenSpec specs
    point to existing requirement IDs.

.DESCRIPTION
    Extracts all requirement ID definitions (SES-NNN, SIG-NNN, ORCH-NNN, etc.)
    from spec files, then scans for cross-domain references to these IDs and
    reports any dangling references (IDs that are referenced but never defined).

.EXAMPLE
    pwsh -NoProfile -File scripts/openspec/validate-cross-refs.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SpecsRoot = (Join-Path $PSScriptRoot '..\..\openspec\specs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Domain prefixes from config.yaml cross-reference convention
# ---------------------------------------------------------------------------
$DomainPrefixes = @('SES', 'SIG', 'ORCH', 'PLAN', 'DISC', 'EXEC', 'REV', 'KNOW')
$IdPattern = '(' + ($DomainPrefixes -join '|') + ')-(\d{3})'

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
function Get-SpecFiles {
    [CmdletBinding()]
    param([string]$Root)

    $resolved = Resolve-Path -Path $Root -ErrorAction Stop
    Get-ChildItem -Path $resolved -Filter 'spec.md' -Recurse -File
}

function Get-DefinedIds {
    <#
    .SYNOPSIS
        Extracts all requirement IDs that are defined (appear as headings or
        at the start of requirement blocks) across all spec files.
    #>
    [CmdletBinding()]
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Pattern
    )

    $defined = @{}
    foreach ($file in $Files) {
        $domain = $file.Directory.Name
        $lines = Get-Content -Path $file.FullName -Encoding utf8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $matches = [regex]::Matches($lines[$i], $Pattern)
            foreach ($m in $matches) {
                $id = $m.Value
                $prefix = $m.Groups[1].Value
                # An ID is "defined" when it appears in its own domain spec
                $expectedDomain = switch ($prefix) {
                    'SES'  { 'session' }
                    'SIG'  { 'signals' }
                    'ORCH' { 'orchestration' }
                    'PLAN' { 'planning' }
                    'DISC' { 'discovery' }
                    'EXEC' { 'execution' }
                    'REV'  { 'review' }
                    'KNOW' { 'knowledge' }
                }
                if ($domain -eq $expectedDomain) {
                    $defined[$id] = @{
                        File = $file.FullName
                        Line = $i + 1
                    }
                }
            }
        }
    }
    return $defined
}

function Get-AllReferences {
    <#
    .SYNOPSIS
        Extracts all requirement ID references across all spec files,
        including both same-domain and cross-domain references.
    #>
    [CmdletBinding()]
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Pattern
    )

    $refs = @()
    foreach ($file in $Files) {
        $lines = Get-Content -Path $file.FullName -Encoding utf8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $matches = [regex]::Matches($lines[$i], $Pattern)
            foreach ($m in $matches) {
                $refs += [PSCustomObject]@{
                    Id       = $m.Value
                    File     = $file.FullName
                    Line     = $i + 1
                    LineText = $lines[$i].Trim()
                }
            }
        }
    }
    return $refs
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-CrossRefValidation {
    [CmdletBinding()]
    param(
        [string]$SpecsRoot
    )

    $specFiles = Get-SpecFiles -Root $SpecsRoot
    if ($specFiles.Count -eq 0) {
        Write-Warning "No spec.md files found under '$SpecsRoot'."
        return 0
    }

    Write-Information "Scanning $($specFiles.Count) spec file(s) for cross-reference integrity..." -InformationAction Continue

    # Phase 1: Collect all defined IDs
    $definedIds = Get-DefinedIds -Files $specFiles -Pattern $IdPattern
    Write-Information "Defined requirement IDs: $($definedIds.Count)" -InformationAction Continue

    if ($definedIds.Count -eq 0) {
        Write-Information "No requirement IDs found in specs. Skipping reference validation." -InformationAction Continue
        return 0
    }

    # Phase 2: Collect all references
    $allRefs = Get-AllReferences -Files $specFiles -Pattern $IdPattern

    # Phase 3: Find dangling references (referenced but not defined)
    $danglingCount = 0
    $specsRootResolved = (Resolve-Path (Join-Path $SpecsRoot '..')).Path

    foreach ($ref in $allRefs) {
        if (-not $definedIds.ContainsKey($ref.Id)) {
            $relativePath = $ref.File.Replace($specsRootResolved, '').TrimStart('\', '/')
            Write-Information "  DANGLING REF: $($ref.Id) at $relativePath`:$($ref.Line)" -InformationAction Continue
            Write-Information "    > $($ref.LineText)" -InformationAction Continue
            $danglingCount++
        }
    }

    Write-Information '' -InformationAction Continue
    Write-Information "--- Cross-Reference Validation Summary ---" -InformationAction Continue
    Write-Information "Files scanned:       $($specFiles.Count)" -InformationAction Continue
    Write-Information "Defined IDs:         $($definedIds.Count)" -InformationAction Continue
    Write-Information "Total references:    $($allRefs.Count)" -InformationAction Continue
    Write-Information "Dangling references: $danglingCount" -InformationAction Continue

    if ($danglingCount -eq 0) {
        Write-Information "PASS: All cross-references resolve to defined requirement IDs." -InformationAction Continue
    }
    else {
        Write-Information "FAIL: $danglingCount dangling reference(s) found." -InformationAction Continue
    }

    return $danglingCount
}

$exitCode = Invoke-CrossRefValidation -SpecsRoot $SpecsRoot
exit $exitCode
