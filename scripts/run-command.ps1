function Invoke-CopilotWorkspaceCommand {
    <#
    .SYNOPSIS
        Execute commands from the Github Copilot FC workspace configuration.

    .DESCRIPTION
        Reads copilot-workspace.json and executes predefined commands for managing
        the GitHub Copilot FC workspace components.

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

    $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "copilot-workspace.json"

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
        Write-Host "GitHub Copilot FC workspace commands" -ForegroundColor Cyan
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