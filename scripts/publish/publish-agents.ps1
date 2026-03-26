<#
.SYNOPSIS
    Publishes custom agents to VS Code, VS Code Insiders, and personal .copilot folders.

.DESCRIPTION
    Copies agent files from the project's agents/ folder to the personal .copilot/agents
    folder for global availability across workspaces, devices, and GitHub Copilot CLI.
    This path is discovered by both GitHub Copilot CLI and VS Code (which also reads agents
    from ~/.copilot/agents/).

    All agents — regardless of whether they target 'cli' or 'vscode' — are published to
    ~/.copilot/agents/ only. The VS Code prompts directory (Code\User\prompts) is no longer
    used; VS Code discovers custom agents from ~/.copilot/agents/ in user scope.

    Supports runtime-aware publishing via the -Runtime parameter:
    - vscode: publishes VS Code variant agents (agents/*/vscode/) and root-level agents to VS Code prompts dirs
    - cli: publishes CLI variant agents (agents/*/cli/) to ~/.copilot/agents/
    - (default): publishes both runtimes

    Handles both array and comma-separated string input formats for agent names.
    Automatically detects and publishes to WSL if available.

.PARAMETER Agents
    Array or comma-separated string of agent names to publish (without .agent.md extension).
    If omitted, publishes all agents found.

    Accepted formats:
    - Array: -Agents @('git-committer','meta')
    - Comma-separated: -Agents 'git-committer,meta'
    - String array: -Agents 'git-committer','meta'

.PARAMETER Runtime
    Target runtime for publishing. Valid values: 'vscode', 'cli', 'all'. Default: 'all'.
    - vscode: discovers agents/*/vscode/*.agent.md + agents/*.agent.md (root non-variant agents)
    - cli: discovers agents/*/cli/*.agent.md
    - all: publishes both runtimes (default behavior)

.PARAMETER Force
    Overwrite existing agents without prompting for confirmation.

.PARAMETER SkipWSL
    Skip publishing to WSL (Windows-only mode).

.EXAMPLE
    # Publish all agents (both runtimes)
    ./publish-agents.ps1

.EXAMPLE
    # Publish VS Code agents only
    ./publish-agents.ps1 -Runtime vscode -Force

.EXAMPLE
    # Publish CLI agents only
    ./publish-agents.ps1 -Runtime cli -Force

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
    [ValidateSet("vscode", "cli", "all")]
    [string]$Runtime = "all",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

. "$PSScriptRoot/wsl-helpers.ps1"

function Get-AgentFiles {
    <#
    .SYNOPSIS
        Discovers agent files based on runtime selection.

    .PARAMETER ProjectAgentsPath
        Root agents/ directory in the workspace.

    .PARAMETER Runtime
        'vscode', 'cli', or 'all' (default) for both.

    .OUTPUTS
        Array of objects with FullName (source path) and DestinationName (flat filename).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectAgentsPath,

        [Parameter(Mandatory = $false)]
        [string]$Runtime
    )

    $results = @()

    $publishVSCode = ($Runtime -eq 'vscode') -or ($Runtime -eq 'all')
    $publishCLI = ($Runtime -eq 'cli') -or ($Runtime -eq 'all')

    if ($publishVSCode) {
        # VS Code variant agents: agents/*/vscode/*.agent.md
        # Exclude .archived directories and plugin-managed dirs
        $vscodeVariantDirs = Get-ChildItem -Path $ProjectAgentsPath -Directory | Where-Object { $_.Name -ne '.archived' } | ForEach-Object {
            $vscodeDir = Join-Path $_.FullName 'vscode'
            if (Test-Path $vscodeDir) {
                $markerFile = Join-Path $vscodeDir '.plugin-managed'
                if (Test-Path $markerFile) {
                    Write-Host "  SKIP (plugin-managed): $($_.Name)/vscode — use publish-plugins.ps1 instead" -ForegroundColor Yellow
                }
                else {
                    $vscodeDir
                }
            }
        }
        foreach ($dir in $vscodeVariantDirs) {
            Get-ChildItem -Path $dir -Filter '*.agent.md' | ForEach-Object {
                $results += [PSCustomObject]@{
                    FullName        = $_.FullName
                    DestinationName = $_.Name
                    Runtime         = 'vscode'
                }
            }
        }

        # Root-level non-variant agents: agents/*.agent.md (VS Code only)
        Get-ChildItem -Path $ProjectAgentsPath -Filter '*.agent.md' -File | ForEach-Object {
            $results += [PSCustomObject]@{
                FullName        = $_.FullName
                DestinationName = $_.Name
                Runtime         = 'vscode'
            }
        }
    }

    if ($publishCLI) {
        # CLI variant agents: agents/*/cli/*.agent.md
        # Exclude .archived directories and plugin-managed dirs
        $cliVariantDirs = Get-ChildItem -Path $ProjectAgentsPath -Directory | Where-Object { $_.Name -ne '.archived' } | ForEach-Object {
            $cliDir = Join-Path $_.FullName 'cli'
            if (Test-Path $cliDir) {
                $markerFile = Join-Path $cliDir '.plugin-managed'
                if (Test-Path $markerFile) {
                    Write-Host "  SKIP (plugin-managed): $($_.Name)/cli — use publish-plugins.ps1 instead" -ForegroundColor Yellow
                }
                else {
                    $cliDir
                }
            }
        }
        foreach ($dir in $cliVariantDirs) {
            Get-ChildItem -Path $dir -Filter '*.agent.md' | ForEach-Object {
                $results += [PSCustomObject]@{
                    FullName        = $_.FullName
                    DestinationName = $_.Name
                    Runtime         = 'cli'
                }
            }
        }
    }

    return $results
}

function Publish-AgentsToVSCode {

    $publishVSCode = ($Runtime -eq 'vscode') -or ($Runtime -eq 'all')
    $publishCLI = ($Runtime -eq 'cli') -or ($Runtime -eq 'all')

    $runtimeLabel = if ($Runtime -ne 'all') { $Runtime } else { 'all runtimes' }
    Write-Host "Publishing agents ($runtimeLabel)..." -ForegroundColor Cyan

    $projectAgentsPath = Join-Path $PSScriptRoot "..\..\agents"

    # All agents (both vscode and cli runtime) publish to ~/.copilot/agents/
    # VS Code discovers custom agents from this location in user scope.
    $copilotAgentsPaths = @(
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

    if ($publishVSCode) {
        foreach ($path in $copilotAgentsPaths) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "Created .copilot/agents directory: $path" -ForegroundColor Green
            }
        }
    }
    if ($publishCLI) {
        foreach ($path in $copilotAgentsPaths) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "Created .copilot/agents directory: $path" -ForegroundColor Green
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

    # Discover agent files based on runtime
    $discoveredAgents = @(Get-AgentFiles -ProjectAgentsPath $projectAgentsPath -Runtime $Runtime)

    # Apply agent name filter
    if ($agentList.Count -gt 0) {
        $discoveredAgents = @($discoveredAgents | Where-Object {
            $basename = $_.DestinationName -replace '\.agent\.md$'
            $agentList | Where-Object { $basename -like $_ } | Select-Object -First 1
        })

        if ($discoveredAgents.Count -eq 0) {
            Write-Host "Warning: No agents found matching: $($agentList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available agents:" -ForegroundColor Cyan
            $allAgents = @(Get-AgentFiles -ProjectAgentsPath $projectAgentsPath -Runtime $Runtime)
            $allAgents | ForEach-Object {
                $basename = $_.DestinationName -replace '\.agent\.md$'
                Write-Host "  - $basename ($($_.Runtime))" 
            }
            return
        }
    }

    if ($discoveredAgents.Count -eq 0) {
        Write-Host "No agent files found for runtime: $runtimeLabel" -ForegroundColor Yellow
        return
    }

    Write-Host "Discovered $($discoveredAgents.Count) agent file(s)..." -ForegroundColor Cyan

    $successCount = 0
    $failureCount = 0

    foreach ($agentEntry in $discoveredAgents) {
        $sourcePath = $agentEntry.FullName
        $destFileName = $agentEntry.DestinationName
        $agentRuntime = $agentEntry.Runtime

        # Determine destinations based on agent's runtime
        # Both vscode and cli runtime agents go to ~/.copilot/agents/
        $targetPaths = $copilotAgentsPaths

        foreach ($path in $targetPaths) {
            $destinationPath = Join-Path $path $destFileName
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $overwrite = Read-Host "Agent '$($destFileName -replace '\.agent\.md$')' already exists in .copilot/agents. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($destFileName -replace '\.agent\.md$') for .copilot/agents" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                Write-Host "Published: $($destFileName -replace '\.agent\.md$') [$agentRuntime] to .copilot/agents" -ForegroundColor Green
                $successCount++
            }
            catch {
                Write-Host "Failed to publish $($destFileName -replace '\.agent\.md$') to $path : $_" -ForegroundColor Red
                $failureCount++
            }
        }

        # Publish to WSL
        if ($wslAvailable) {
            # WSL: both vscode and cli runtime agents go to .copilot/agents
            $wslFolders = @(".copilot/agents")

            foreach ($wslFolder in $wslFolders) {
                $wslTargetPath = "$wslHome/$wslFolder/$destFileName"

                try {
                    $existsInWsl = Invoke-WSLCommand -Command "test -f '$wslTargetPath' && echo 'exists' || echo 'notfound'" -SuppressStderr

                    if ($existsInWsl -eq 'exists' -and -not $Force) {
                        Write-Host "Skipping $($destFileName -replace '\.agent\.md$') for WSL/$wslFolder (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                        continue
                    }

                    $copiedToWsl = Copy-ToWSL -Source $sourcePath -Destination $wslTargetPath

                    if ($copiedToWsl) {
                        Write-Host "Copied: $($destFileName -replace '\.agent\.md$') [$agentRuntime] to WSL/$wslFolder" -ForegroundColor Green
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
