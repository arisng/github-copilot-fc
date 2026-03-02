<#
.SYNOPSIS
    Publishes custom agents to VS Code, VS Code Insiders, and personal .copilot folders.

.DESCRIPTION
    Copies agent files from the project's agents/ folder to VS Code's and VS Code Insiders'
    user prompts directories, and to personal .copilot/agents folder for global availability
    across all workspaces, devices, and GitHub Copilot CLI.

    Supports platform-aware publishing via the -Platform parameter:
    - vscode: publishes VS Code variant agents (agents/*/vscode/) and root-level agents to VS Code prompts dirs
    - cli: publishes CLI variant agents (agents/*/cli/) to ~/.copilot/agents/
    - (default): publishes both platforms

    Handles both array and comma-separated string input formats for agent names.
    Automatically detects and publishes to WSL if available.

.PARAMETER Agents
    Array or comma-separated string of agent names to publish (without .agent.md extension).
    If omitted, publishes all agents found.

    Accepted formats:
    - Array: -Agents @('git-committer','meta')
    - Comma-separated: -Agents 'git-committer,meta'
    - String array: -Agents 'git-committer','meta'

.PARAMETER Platform
    Target platform for publishing. Valid values: 'vscode', 'cli'.
    - vscode: discovers agents/*/vscode/*.agent.md + agents/*.agent.md (root non-variant agents)
    - cli: discovers agents/*/cli/*.agent.md
    - (omitted): publishes both platforms

.PARAMETER Force
    Overwrite existing agents without prompting for confirmation.

.PARAMETER SkipWSL
    Skip publishing to WSL (Windows-only mode).

.EXAMPLE
    # Publish all agents (both platforms)
    ./publish-agents.ps1

.EXAMPLE
    # Publish VS Code agents only
    ./publish-agents.ps1 -Platform vscode -Force

.EXAMPLE
    # Publish CLI agents only
    ./publish-agents.ps1 -Platform cli -Force

.EXAMPLE
    # Publish specific agents using array (recommended)
    ./publish-agents.ps1 -Agents @('ralph-v2', 'planner') -Force

.EXAMPLE
    # Publish specific agents using comma-separated string
    ./publish-agents.ps1 -Agents 'ralph-v2,planner' -Force
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Agents,

    [Parameter(Mandatory = $false)]
    [ValidateSet("vscode", "cli")]
    [string]$Platform,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

. "$PSScriptRoot/wsl-helpers.ps1"

function Get-AgentFiles {
    <#
    .SYNOPSIS
        Discovers agent files based on platform selection.

    .PARAMETER ProjectAgentsPath
        Root agents/ directory in the workspace.

    .PARAMETER Platform
        'vscode', 'cli', or empty string for both.

    .OUTPUTS
        Array of objects with FullName (source path) and DestinationName (flat filename).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectAgentsPath,

        [Parameter(Mandatory = $false)]
        [string]$Platform
    )

    $results = @()

    $publishVSCode = (-not $Platform) -or ($Platform -eq 'vscode')
    $publishCLI = (-not $Platform) -or ($Platform -eq 'cli')

    if ($publishVSCode) {
        # VS Code variant agents: agents/*/vscode/*.agent.md
        $vscodeVariantDirs = Get-ChildItem -Path $ProjectAgentsPath -Directory | ForEach-Object {
            $vscodeDir = Join-Path $_.FullName 'vscode'
            if (Test-Path $vscodeDir) { $vscodeDir }
        }
        foreach ($dir in $vscodeVariantDirs) {
            Get-ChildItem -Path $dir -Filter '*.agent.md' | ForEach-Object {
                $results += [PSCustomObject]@{
                    FullName        = $_.FullName
                    DestinationName = $_.Name
                    Platform        = 'vscode'
                }
            }
        }

        # Root-level non-variant agents: agents/*.agent.md (VS Code only)
        Get-ChildItem -Path $ProjectAgentsPath -Filter '*.agent.md' -File | ForEach-Object {
            $results += [PSCustomObject]@{
                FullName        = $_.FullName
                DestinationName = $_.Name
                Platform        = 'vscode'
            }
        }
    }

    if ($publishCLI) {
        # CLI variant agents: agents/*/cli/*.agent.md
        $cliVariantDirs = Get-ChildItem -Path $ProjectAgentsPath -Directory | ForEach-Object {
            $cliDir = Join-Path $_.FullName 'cli'
            if (Test-Path $cliDir) { $cliDir }
        }
        foreach ($dir in $cliVariantDirs) {
            Get-ChildItem -Path $dir -Filter '*.agent.md' | ForEach-Object {
                $results += [PSCustomObject]@{
                    FullName        = $_.FullName
                    DestinationName = $_.Name
                    Platform        = 'cli'
                }
            }
        }
    }

    return $results
}

function Publish-AgentsToVSCode {

    $publishVSCode = (-not $Platform) -or ($Platform -eq 'vscode')
    $publishCLI = (-not $Platform) -or ($Platform -eq 'cli')

    $platformLabel = if ($Platform) { $Platform } else { 'all platforms' }
    Write-Host "Publishing agents ($platformLabel)..." -ForegroundColor Cyan

    $projectAgentsPath = Join-Path $PSScriptRoot "..\..\agents"

    # VS Code destinations
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # CLI destinations
    $cliAgentsPaths = @(
        (Join-Path $env:USERPROFILE ".copilot\agents")
    )

    # WSL detection
    $wslAvailable = $false
    $wslHome = $null

    if (-not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
        else {
            Write-Host "WSL not available, skipping WSL publishing" -ForegroundColor Yellow
        }
    }

    # Ensure project agents directory exists
    if (-not (Test-Path $projectAgentsPath)) {
        throw "Project agents directory not found: $projectAgentsPath"
    }

    # Create destination directories
    if ($publishVSCode) {
        foreach ($path in $vscodePromptsPaths) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "Created VS Code prompts directory: $path" -ForegroundColor Green
            }
        }
    }
    if ($publishCLI) {
        foreach ($path in $cliAgentsPaths) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "Created CLI agents directory: $path" -ForegroundColor Green
            }
        }
    }

    # Normalize agent names: handle both comma-separated strings and arrays
    $agentList = @()
    if ($Agents) {
        foreach ($agent in $Agents) {
            $agentList += @($agent -split ',').Trim() | Where-Object { $_ -ne '' }
        }
        $agentList = $agentList | Select-Object -Unique
    }

    # Discover agent files based on platform
    $discoveredAgents = @(Get-AgentFiles -ProjectAgentsPath $projectAgentsPath -Platform $Platform)

    # Apply agent name filter
    if ($agentList.Count -gt 0) {
        $discoveredAgents = @($discoveredAgents | Where-Object {
            $basename = $_.DestinationName -replace '\.agent\.md$'
            $agentList | Where-Object { $basename -like $_ } | Select-Object -First 1
        })

        if ($discoveredAgents.Count -eq 0) {
            Write-Host "Warning: No agents found matching: $($agentList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available agents:" -ForegroundColor Cyan
            $allAgents = @(Get-AgentFiles -ProjectAgentsPath $projectAgentsPath -Platform $Platform)
            $allAgents | ForEach-Object {
                $basename = $_.DestinationName -replace '\.agent\.md$'
                Write-Host "  - $basename ($($_.Platform))" 
            }
            return
        }
    }

    if ($discoveredAgents.Count -eq 0) {
        Write-Host "No agent files found for platform: $platformLabel" -ForegroundColor Yellow
        return
    }

    Write-Host "Discovered $($discoveredAgents.Count) agent file(s)..." -ForegroundColor Cyan

    $successCount = 0
    $failureCount = 0

    foreach ($agentEntry in $discoveredAgents) {
        $sourcePath = $agentEntry.FullName
        $destFileName = $agentEntry.DestinationName
        $agentPlatform = $agentEntry.Platform

        # Determine destinations based on agent's platform
        $targetPaths = @()
        if ($agentPlatform -eq 'vscode') {
            $targetPaths = $vscodePromptsPaths
        }
        elseif ($agentPlatform -eq 'cli') {
            $targetPaths = $cliAgentsPaths
        }

        foreach ($path in $targetPaths) {
            $destinationPath = Join-Path $path $destFileName
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $location = if ($path -like "*Insiders*") { "VS Code Insiders" }
                            elseif ($path -like "*Code\User*") { "VS Code Stable" }
                            elseif ($path -like "*.copilot*") { ".copilot/agents" }
                            else { $path }

                $overwrite = Read-Host "Agent '$($destFileName -replace '\.agent\.md$')' already exists in $location. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($destFileName -replace '\.agent\.md$') for $location" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                $location = if ($path -like "*Insiders*") { "VS Code Insiders" }
                            elseif ($path -like "*Code\User*") { "VS Code Stable" }
                            elseif ($path -like "*.copilot*") { ".copilot/agents" }
                            else { $path }
                Write-Host "Published: $($destFileName -replace '\.agent\.md$') [$agentPlatform] to $location" -ForegroundColor Green
                $successCount++
            }
            catch {
                Write-Host "Failed to publish $($destFileName -replace '\.agent\.md$') to $path : $_" -ForegroundColor Red
                $failureCount++
            }
        }

        # Publish to WSL
        if ($wslAvailable) {
            # Determine WSL target folders based on agent platform
            $wslFolders = @()
            if ($agentPlatform -eq 'vscode') {
                # WSL VS Code prompts directories
                $wslFolders = @(
                    ".vscode-server/data/User/globalStorage/github.copilot/prompts",
                    ".vscode-server/data/User/globalStorage/github.copilot-insiders/prompts"
                )
            }
            elseif ($agentPlatform -eq 'cli') {
                $wslFolders = @(".copilot/agents")
            }

            foreach ($wslFolder in $wslFolders) {
                $wslTargetPath = "$wslHome/$wslFolder/$destFileName"
                $wslParentPath = "$wslHome/$wslFolder"

                try {
                    $existsInWsl = wsl bash -c "test -f '$wslTargetPath' && echo 'exists' || echo 'notfound'" 2>$null

                    if ($existsInWsl -eq 'exists' -and -not $Force) {
                        Write-Host "Skipping $($destFileName -replace '\.agent\.md$') for WSL/$wslFolder (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                        continue
                    }

                    wsl bash -c "mkdir -p '$wslParentPath'" 2>$null

                    if ($existsInWsl -eq 'exists') {
                        wsl bash -c "rm -f '$wslTargetPath'" 2>$null
                    }

                    $windowsSourcePath = Convert-ToWSLPath -WindowsPath $sourcePath
                    wsl bash -c "cp '$windowsSourcePath' '$wslTargetPath'"

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Copied: $($destFileName -replace '\.agent\.md$') [$agentPlatform] to WSL/$wslFolder" -ForegroundColor Green
                        $successCount++
                    }
                    else {
                        Write-Host "Failed to copy $($destFileName -replace '\.agent\.md$') to WSL/$wslFolder (cp exited with code $LASTEXITCODE)" -ForegroundColor Red
                        $failureCount++
                    }
                }
                catch {
                    Write-Host "Failed to publish $($destFileName -replace '\.agent\.md$') to WSL/$wslFolder : $_" -ForegroundColor Red
                    $failureCount++
                }
            }
        }
    }

    Write-Host "`nAgent publishing completed." -ForegroundColor Cyan
    Write-Host "Success: $successCount | Failed: $failureCount" -ForegroundColor Cyan
}

# Execute main function unconditionally to ensure wrapper calls succeed.
Publish-AgentsToVSCode
