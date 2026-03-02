<#
.SYNOPSIS
    Scans OpenSpec spec files for forbidden runtime-specific terminology.

.DESCRIPTION
    Lexical pass: greps all openspec/specs/*/spec.md files against the 5-category
    runtime blocklist from Q-REQ-004. Reports matches with file, line number, and
    matched term. Semantic leaks (natural language assumptions) are flagged as warnings.

.EXAMPLE
    pwsh -NoProfile -File scripts/openspec/validate-runtime-leaks.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SpecsRoot = (Join-Path $PSScriptRoot '..\..\openspec\specs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Blocklist data (5 categories + semantic patterns) from Q-REQ-004 / config.yaml
# ---------------------------------------------------------------------------
$Blocklist = @{
    'Editor/Runtime' = @(
        'VS Code', 'CLI', 'SDK', 'Coding Agent', 'Copilot', 'copilot-cli',
        'GitHub Copilot', '\beditor\b', '\bIDE\b'
    )
    'OS/Shell' = @(
        'Windows', 'Linux', 'macOS', 'WSL', 'PowerShell', 'pwsh', '\bbash\b',
        '\bcmd\b', 'Terminal'
    )
    'Tool Names' = @(
        '\bgit\b', 'git add', 'git apply', 'git diff', 'git commit',
        'run_in_terminal', 'semantic_search', 'read_file', 'edit_file',
        'editFiles', 'readFile', '\bgrep\b', '\bsearch\b', 'playwright',
        '\bnpm\b', '\bpip\b', 'python3', '\bnode\b'
    )
    'File Formats' = @(
        '\bYAML\b', '\.yaml\b', '\.md\b', '\.json\b', '\.jsonl\b',
        '\.ps1\b', '\.sh\b', '\bmarkdown\b', '\bJSON\b', '\bfrontmatter\b'
    )
    'Path/Filesystem' = @(
        'file path separator', 'absolute path', '\bdirectory\b', '\bfolder\b',
        '\bmkdir\b', '\bfilesystem\b', 'Test-Path', 'Get-Content'
    )
}

$SemanticPatterns = @(
    'reads the file', 'writes to disk', 'creates a directory',
    'drops a file in', 'file-per-task', 'directory-based mailbox'
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
function Get-SpecFiles {
    [CmdletBinding()]
    param([string]$Root)

    $resolved = Resolve-Path -Path $Root -ErrorAction Stop
    Get-ChildItem -Path $resolved -Filter 'spec.md' -Recurse -File
}

function Test-LineAgainstBlocklist {
    [CmdletBinding()]
    param(
        [string]$Line,
        [hashtable]$Categories
    )
    $hits = @()
    foreach ($category in $Categories.GetEnumerator()) {
        foreach ($term in $category.Value) {
            if ($Line -cmatch $term) {
                $hits += [PSCustomObject]@{
                    Category = $category.Key
                    Term     = $term
                }
            }
        }
    }
    return $hits
}

function Test-LineAgainstSemanticPatterns {
    [CmdletBinding()]
    param(
        [string]$Line,
        [string[]]$Patterns
    )
    $hits = @()
    foreach ($pattern in $Patterns) {
        if ($Line -match [regex]::Escape($pattern)) {
            $hits += $pattern
        }
    }
    return $hits
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-RuntimeLeakScan {
    [CmdletBinding()]
    param(
        [string]$SpecsRoot
    )

    $specFiles = Get-SpecFiles -Root $SpecsRoot
    if ($specFiles.Count -eq 0) {
        Write-Warning "No spec.md files found under '$SpecsRoot'."
        return 0
    }

    Write-Information "Scanning $($specFiles.Count) spec file(s) for runtime leaks..." -InformationAction Continue

    $totalViolations = 0
    $totalWarnings = 0

    foreach ($file in $specFiles) {
        $relativePath = $file.FullName.Replace((Resolve-Path (Join-Path $SpecsRoot '..')).Path, '').TrimStart('\', '/')
        $lines = Get-Content -Path $file.FullName -Encoding utf8
        $inFrontmatter = $false
        $frontmatterCount = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNum = $i + 1

            # Skip YAML frontmatter (between --- markers)
            if ($line -match '^---\s*$') {
                $frontmatterCount++
                if ($frontmatterCount -le 2) {
                    $inFrontmatter = ($frontmatterCount -eq 1)
                    continue
                }
            }
            if ($inFrontmatter) {
                if ($frontmatterCount -ge 2) { $inFrontmatter = $false }
                else { continue }
            }

            # Check blocklist
            $blocklistHits = Test-LineAgainstBlocklist -Line $line -Categories $Blocklist
            foreach ($hit in $blocklistHits) {
                Write-Information "  VIOLATION [$($hit.Category)] $relativePath`:$lineNum — matched '$($hit.Term)'" -InformationAction Continue
                Write-Information "    > $($line.Trim())" -InformationAction Continue
                $totalViolations++
            }

            # Check semantic patterns (warning level)
            $semanticHits = Test-LineAgainstSemanticPatterns -Line $line -Patterns $SemanticPatterns
            foreach ($hit in $semanticHits) {
                Write-Information "  WARNING [Semantic] $relativePath`:$lineNum — matched '$hit'" -InformationAction Continue
                Write-Information "    > $($line.Trim())" -InformationAction Continue
                $totalWarnings++
            }
        }
    }

    Write-Information '' -InformationAction Continue
    Write-Information "--- Runtime Leak Scan Summary ---" -InformationAction Continue
    Write-Information "Files scanned:       $($specFiles.Count)" -InformationAction Continue
    Write-Information "Blocklist violations: $totalViolations" -InformationAction Continue
    Write-Information "Semantic warnings:    $totalWarnings" -InformationAction Continue

    if ($totalViolations -eq 0 -and $totalWarnings -eq 0) {
        Write-Information "PASS: No runtime leaks detected." -InformationAction Continue
    }
    elseif ($totalViolations -eq 0) {
        Write-Information "PASS (with warnings): No blocklist violations, but $totalWarnings semantic pattern(s) found — manual review recommended." -InformationAction Continue
    }
    else {
        Write-Information "FAIL: $totalViolations blocklist violation(s) found." -InformationAction Continue
    }

    return $totalViolations
}

$exitCode = Invoke-RuntimeLeakScan -SpecsRoot $SpecsRoot
exit $exitCode
