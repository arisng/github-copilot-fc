param(
    [Parameter(Mandatory = $false)]
    [string[]]$Agents,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-AgentsToVSCode {
    <#
    .SYNOPSIS
        Publishes agents from the project factory to VS Code user prompts directory.

    .DESCRIPTION
        Copies agent files from the project's agents/ folder to VS Code's user prompts
        directory for global availability across all workspaces and devices.

    .PARAMETER Agents
        Array of agent names to publish. If empty, publishes all agents.

    .PARAMETER Force
        Overwrite existing agents without prompting.

    .EXAMPLE
        Publish-AgentsToVSCode

        Copies all agents from project to VS Code user prompts.

    .EXAMPLE
        Publish-AgentsToVSCode -Agents "meta", "instruction-writer"

        Copies specific agents.
    #>

    Write-Host "Publishing agents to VS Code..." -ForegroundColor Cyan

    $projectAgentsPath = Join-Path $PSScriptRoot "..\agents"
    $vscodePromptsPath = Join-Path $env:APPDATA "Code\User\prompts"

    # Ensure project agents directory exists
    if (-not (Test-Path $projectAgentsPath)) {
        throw "Project agents directory not found: $projectAgentsPath"
    }

    # Create VS Code prompts directory if it doesn't exist
    if (-not (Test-Path $vscodePromptsPath)) {
        New-Item -ItemType Directory -Path $vscodePromptsPath -Force | Out-Null
        Write-Host "Created VS Code prompts directory: $vscodePromptsPath" -ForegroundColor Green
    }

    # Get agent files to publish
    $agentFiles = Get-ChildItem -Path $projectAgentsPath -Filter "*.agent.md"
    if ($Agents) {
        $agentFiles = $agentFiles | Where-Object { ($_.Name -replace '\.agent\.md$') -in $Agents }
    }

    if ($agentFiles.Count -eq 0) {
        Write-Host "No agent files found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($agentFiles.Count) agent file(s)..." -ForegroundColor Cyan

    foreach ($agentFile in $agentFiles) {
        $sourcePath = $agentFile.FullName
        $destinationPath = Join-Path $vscodePromptsPath $agentFile.Name

        # Check if agent already exists
        $exists = Test-Path $destinationPath

        if ($exists -and -not $Force) {
            $overwrite = Read-Host "Agent '$($agentFile.BaseName)' already exists. Overwrite? (y/N)"
            if ($overwrite -notmatch "^[Yy]") {
                Write-Host "Skipping $($agentFile.BaseName)" -ForegroundColor Yellow
                continue
            }
        }

        try {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            Write-Host "Published: $($agentFile.BaseName)" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to publish $($agentFile.BaseName): $_"
        }
    }

    Write-Host "Agent publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-agents.ps1") {
    Publish-AgentsToVSCode
}