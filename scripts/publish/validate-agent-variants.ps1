<#
.SYNOPSIS
    Validates agent variant files for tool namespace cross-contamination.

.DESCRIPTION
    Performs deny-list namespace validation on VS Code and CLI agent variants to
    catch tool cross-contamination between platforms. This is an advisory script
    that warns but does not block publishing.

    Four validation checks:
    1. VS Code deny-list for CLI variants (CLI files must not contain VS Code-only tool namespaces)
    2. CLI deny-list for VS Code variants (VS Code files must not contain CLI-only tool names)
    3. Body content scan for platform-specific tool references
    4. Shared instruction reference check (both variants should reference the same shared instruction)

.PARAMETER AgentsPath
    Path to agents/ directory. Defaults to agents/ relative to the script's workspace root.

.EXAMPLE
    ./validate-agent-variants.ps1

.EXAMPLE
    ./validate-agent-variants.ps1 -AgentsPath "C:\my\workspace\agents"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$AgentsPath
)

function Get-AgentFrontmatter {
    <#
    .SYNOPSIS
        Extracts YAML frontmatter tools array from an agent file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $content = Get-Content -Path $FilePath -Raw
    $tools = @()

    # Extract frontmatter between --- markers
    if ($content -match '(?s)^---\r?\n(.*?)\r?\n---') {
        $frontmatter = $Matches[1]

        # Extract tools list (simple YAML array parsing)
        if ($frontmatter -match '(?s)tools:\s*\r?\n((?:\s+-\s+.*\r?\n?)*)') {
            $toolsBlock = $Matches[1]
            $tools = @($toolsBlock -split '\r?\n' | ForEach-Object {
                if ($_ -match '^\s+-\s+(.+)$') { $Matches[1].Trim() }
            } | Where-Object { $_ })
        }
        # Also handle inline array: tools: [bash, view, edit]
        elseif ($frontmatter -match 'tools:\s*\[([^\]]+)\]') {
            $tools = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    return $tools
}

function Get-AgentBody {
    <#
    .SYNOPSIS
        Extracts body content (after frontmatter) from an agent file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $content = Get-Content -Path $FilePath -Raw
    if ($content -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
        return $Matches[1]
    }
    return $content
}

# VS Code-only tool namespaces (deny-list for CLI variants)
$vscodeDenyList = @(
    'execute/runInTerminal',
    'execute/getTerminalOutput',
    'execute/awaitTerminal',
    'execute/killTerminal',
    'execute/testFailure',
    'execute/runTests',
    'read/readFile',
    'read/problems',
    'read/terminalSelection',
    'read/terminalLastCommand',
    'edit/editFiles',
    'edit/createFile',
    'edit/createDirectory',
    'search',
    'agent',
    'vscode/memory',
    'web'
)

# CLI-only tool names (deny-list for VS Code variants)
$cliDenyList = @(
    'bash',
    'view',
    'create',
    'task',
    'glob',
    'grep',
    'cat',
    'ls',
    'sed'
)
# Note: 'edit' is ambiguous (VS Code has edit/* namespace, CLI has bare 'edit')
# Only flag bare 'edit' in VS Code if no namespace prefix

# Body content patterns for cross-contamination warnings
$vscodeBodyPatterns = @(
    'execute/runInTerminal',
    'read/readFile',
    'edit/editFiles',
    'edit/createFile',
    '@Ralph-v2-',
    'vscode/memory'
)

$cliBodyPatterns = @(
    '\btask\(',
    '\bbash\(',
    '\bview\(',
    '\bcreate\('
)

# Resolve agents path
if (-not $AgentsPath) {
    $AgentsPath = Join-Path $PSScriptRoot "..\..\agents"
}

if (-not (Test-Path $AgentsPath)) {
    Write-Host "ERROR: Agents directory not found: $AgentsPath" -ForegroundColor Red
    exit 1
}

$errorCount = 0
$warnCount = 0

# Discover all agent groups with variants
$agentGroups = Get-ChildItem -Path $AgentsPath -Directory | Where-Object {
    (Test-Path (Join-Path $_.FullName 'vscode')) -or (Test-Path (Join-Path $_.FullName 'cli'))
}

Write-Host "Validating agent variants..." -ForegroundColor Cyan
Write-Host "Found $($agentGroups.Count) agent group(s) with variants" -ForegroundColor DarkGray

foreach ($group in $agentGroups) {
    $groupName = $group.Name
    $vscodeDir = Join-Path $group.FullName 'vscode'
    $cliDir = Join-Path $group.FullName 'cli'

    Write-Host "`n--- $groupName ---" -ForegroundColor White

    # Check 1: VS Code deny-list for CLI variants
    if (Test-Path $cliDir) {
        $cliFiles = Get-ChildItem -Path $cliDir -Filter '*.agent.md'
        foreach ($file in $cliFiles) {
            $tools = Get-AgentFrontmatter -FilePath $file.FullName
            foreach ($tool in $tools) {
                if ($vscodeDenyList -contains $tool) {
                    Write-Host "[ERROR] $($file.Name): tools: contains VS Code-only tool '$tool'" -ForegroundColor Red
                    $errorCount++
                }
            }
        }
    }

    # Check 2: CLI deny-list for VS Code variants
    if (Test-Path $vscodeDir) {
        $vscodeFiles = Get-ChildItem -Path $vscodeDir -Filter '*.agent.md'
        foreach ($file in $vscodeFiles) {
            $tools = Get-AgentFrontmatter -FilePath $file.FullName
            foreach ($tool in $tools) {
                # For bare 'edit', only flag if it's not a namespace prefix (edit/*)
                if ($tool -eq 'edit') {
                    Write-Host "[ERROR] $($file.Name): tools: contains CLI-only bare tool 'edit' (VS Code uses edit/* namespace)" -ForegroundColor Red
                    $errorCount++
                }
                elseif ($cliDenyList -contains $tool) {
                    Write-Host "[ERROR] $($file.Name): tools: contains CLI-only tool '$tool'" -ForegroundColor Red
                    $errorCount++
                }
            }
        }
    }

    # Check 3: Body content scan
    if (Test-Path $cliDir) {
        $cliFiles = Get-ChildItem -Path $cliDir -Filter '*.agent.md'
        foreach ($file in $cliFiles) {
            $body = Get-AgentBody -FilePath $file.FullName
            foreach ($pattern in $vscodeBodyPatterns) {
                if ($body -match [regex]::Escape($pattern)) {
                    Write-Host "[WARN] $($file.Name): body contains VS Code reference '$pattern'" -ForegroundColor Yellow
                    $warnCount++
                }
            }
        }
    }

    if (Test-Path $vscodeDir) {
        $vscodeFiles = Get-ChildItem -Path $vscodeDir -Filter '*.agent.md'
        foreach ($file in $vscodeFiles) {
            $body = Get-AgentBody -FilePath $file.FullName
            foreach ($pattern in $cliBodyPatterns) {
                if ($body -match $pattern) {
                    Write-Host "[WARN] $($file.Name): body contains CLI reference matching '$pattern'" -ForegroundColor Yellow
                    $warnCount++
                }
            }
        }
    }

    # Check 4: Shared instruction reference check
    if ((Test-Path $vscodeDir) -and (Test-Path $cliDir)) {
        $vscodeFiles = Get-ChildItem -Path $vscodeDir -Filter '*.agent.md'
        $cliFiles = Get-ChildItem -Path $cliDir -Filter '*.agent.md'

        foreach ($vscodeFile in $vscodeFiles) {
            $cliFile = $cliFiles | Where-Object { $_.Name -eq $vscodeFile.Name }
            if (-not $cliFile) {
                Write-Host "[WARN] $($vscodeFile.Name): VS Code variant exists but no CLI variant found" -ForegroundColor Yellow
                $warnCount++
                continue
            }

            # Extract instruction references from body
            $vscodeBody = Get-AgentBody -FilePath $vscodeFile.FullName
            $cliBody = Get-AgentBody -FilePath $cliFile.FullName

            $vscodeRefs = @([regex]::Matches($vscodeBody, 'instructions/[^\s\)]+\.instructions\.md') | ForEach-Object { $_.Value })
            $cliRefs = @([regex]::Matches($cliBody, 'instructions/[^\s\)]+\.instructions\.md') | ForEach-Object { $_.Value })

            if ($vscodeRefs.Count -gt 0 -and $cliRefs.Count -gt 0) {
                $vscopeSet = $vscodeRefs | Sort-Object -Unique
                $cliSet = $cliRefs | Sort-Object -Unique
                $diff = Compare-Object $vscopeSet $cliSet
                if ($diff) {
                    Write-Host "[WARN] $($vscodeFile.Name): instruction references differ between VS Code and CLI variants" -ForegroundColor Yellow
                    $warnCount++
                }
            }
        }

        # Check for CLI agents without VS Code counterpart
        foreach ($cliFile in $cliFiles) {
            $vscodeFile = $vscodeFiles | Where-Object { $_.Name -eq $cliFile.Name }
            if (-not $vscodeFile) {
                Write-Host "[WARN] $($cliFile.Name): CLI variant exists but no VS Code variant found" -ForegroundColor Yellow
                $warnCount++
            }
        }
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Errors: $errorCount | Warnings: $warnCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Green' })

if ($errorCount -gt 0) {
    Write-Host "Tool namespace cross-contamination detected. Review and fix errors above." -ForegroundColor Red
    exit 1
}
elseif ($warnCount -gt 0) {
    Write-Host "No critical errors. Warnings are advisory — review if relevant." -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host "All checks passed." -ForegroundColor Green
    exit 0
}
