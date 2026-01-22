function Invoke-CopilotWorkspaceCommand {
    <#
    .SYNOPSIS
        Execute commands from the Copilot FC workspace configuration.

    .DESCRIPTION
        Reads the workspace manifest (supports copilot-*.json; default is copilot-fc.json) and executes predefined commands for managing
        the Copilot FC workspace components.
    .PARAMETER Command
        The command to execute (use 'list' to see available commands).

    .EXAMPLE
        Invoke-CopilotWorkspaceCommand -Command skills:publish-copy

        Publishes skills using the copy method.

    .EXAMPLE
        Invoke-CopilotWorkspaceCommand -Command list

        Shows all available commands.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Command
    )

    # Determine configuration file: prefer COPILOT_WORKSPACE_FILE env var, then a single copilot-*.json file, otherwise default to 'copilot-fc.json'
    $repoRoot = Split-Path $PSScriptRoot -Parent

    if ($env:COPILOT_WORKSPACE_FILE) {
        $configFilename = $env:COPILOT_WORKSPACE_FILE
    }
    else {
        $matches = Get-ChildItem -Path $repoRoot -Filter 'copilot-*.json' -File -ErrorAction SilentlyContinue
        if ($matches -and $matches.Count -eq 1) {
            $configFilename = $matches[0].Name
        }
        elseif ($matches -and $matches.Count -gt 1) {
            Write-Error "Multiple copilot-*.json files found. Set the COPILOT_WORKSPACE_FILE environment variable to specify which one to use."
            return
        }
        else {
            $configFilename = 'copilot-fc.json'
        }
    }

    $configPath = Join-Path $repoRoot $configFilename

    if (-not (Test-Path $configPath)) {
        Write-Error "Configuration file not found: $configPath"
        return
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse configuration file: $_"
        return
    }

    # If no command specified or 'list', show available commands
    if (-not $Command -or $Command -eq 'list') {
        Write-Host "Copilot FC workspace commands" -ForegroundColor Cyan
        Write-Host "=================================" -ForegroundColor Cyan
        Write-Host ""

        $config.commands.PSObject.Properties | ForEach-Object {
            Write-Host "$($_.Name.PadRight(20)) : $($_.Value)" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "Usage: .\run-command.ps1 -Command <command-name>" -ForegroundColor Yellow
        return
    }

    # Execute the specified command
    if ($config.commands.PSObject.Properties.Name -contains $Command) {
        $commandLine = $config.commands.$Command
        Write-Host "Executing: $Command" -ForegroundColor Green
        Write-Host "Command: $commandLine" -ForegroundColor Gray
        Write-Host ""

        try {
            Invoke-Expression $commandLine
        }
        catch {
            Write-Error "Command execution failed: $_"
        }
    }
    else {
        Write-Error "Unknown command: $Command"
        Write-Host "Use 'list' to see available commands." -ForegroundColor Yellow
    }
}

# If script is run directly, execute the command
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    if ($args.Count -eq 0) {
        Invoke-CopilotWorkspaceCommand -Command 'list'
    }
    else {
        Invoke-CopilotWorkspaceCommand -Command $args[0]
    }
}