<#
.SYNOPSIS
    Publishes custom agents to VS Code and VS Code Insiders user prompts directories.

.DESCRIPTION
    Copies agent files from the project's agents/ folder to VS Code's and VS Code Insiders'
    user prompts directories for global availability across all workspaces and devices.

    Handles both array and comma-separated string input formats for agent names.

.PARAMETER Agents
    Array or comma-separated string of agent names to publish (without .agent.md extension).
    If omitted, publishes all agents found.

    Accepted formats:
    - Array: -Agents @('git-committer','meta')
    - Comma-separated: -Agents 'git-committer,meta'
    - String array: -Agents 'git-committer','meta'

.PARAMETER Force
    Overwrite existing agents without prompting for confirmation.

.EXAMPLE
    # Publish all agents
    ./publish-agents.ps1

.EXAMPLE
    # Publish specific agents using array (recommended)
    ./publish-agents.ps1 -Agents @('git-committer', 'meta') -Force

.EXAMPLE
    # Publish specific agents using comma-separated string
    ./publish-agents.ps1 -Agents 'git-committer,meta' -Force
.EXAMPLE
    # Publish a single agent with prompts for overwrite
    ./publish-agents.ps1 -Agents 'meta'
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Agents,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-AgentsToVSCode {

    Write-Host "Publishing agents to VS Code..." -ForegroundColor Cyan

    $projectAgentsPath = Join-Path $PSScriptRoot "..\..\agents"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # Ensure project agents directory exists
    if (-not (Test-Path $projectAgentsPath)) {
        throw "Project agents directory not found: $projectAgentsPath"
    }

    # Create VS Code prompts directories if they don't exist
    foreach ($path in $vscodePromptsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created VS Code prompts directory: $path" -ForegroundColor Green
        }
    }

    # Normalize agent names: handle both comma-separated strings and arrays
    $agentList = @()
    if ($Agents) {
        foreach ($agent in $Agents) {
            # Split comma-separated values and trim whitespace
            $agentList += @($agent -split ',').Trim() | Where-Object { $_ -ne '' }
        }
        # Remove duplicates
        $agentList = $agentList | Select-Object -Unique
    }

    # Get agent files to publish
    $agentFiles = Get-ChildItem -Path $projectAgentsPath -Filter "*.agent.md"

    if ($agentList.Count -gt 0) {
        $agentFiles = $agentFiles | Where-Object { 
            ($_.Name -replace '\.agent\.md$') -in $agentList 
        }
        
        if ($agentFiles.Count -eq 0) {
            Write-Host "Warning: No agents found matching: $($agentList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available agents:" -ForegroundColor Cyan
            Get-ChildItem -Path $projectAgentsPath -Filter "*.agent.md" | 
                ForEach-Object { Write-Host "  - $($_.Name -replace '\.agent\.md$')" }
            return
        }
    } elseif ($agentFiles.Count -eq 0) {
        Write-Host "No agent files found in: $projectAgentsPath" -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($agentFiles.Count) agent file(s)..." -ForegroundColor Cyan

    $successCount = 0
    $failureCount = 0

    foreach ($agentFile in $agentFiles) {
        $sourcePath = $agentFile.FullName

        foreach ($path in $vscodePromptsPaths) {
            $destinationPath = Join-Path $path $agentFile.Name

            # Check if agent already exists
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                $overwrite = Read-Host "Agent '$($agentFile.BaseName)' already exists in VS Code $edition. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($agentFile.BaseName) for VS Code $edition" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                Write-Host "Published: $($agentFile.BaseName) to VS Code $edition" -ForegroundColor Green
                $successCount++
            }
            catch {
                Write-Host "Failed to publish $($agentFile.BaseName) to $path : $_" -ForegroundColor Red
                $failureCount++
            }
        }
    }

    Write-Host "`nAgent publishing completed." -ForegroundColor Cyan
    Write-Host "Success: $successCount | Failed: $failureCount" -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-agents.ps1") {
    Publish-AgentsToVSCode
}