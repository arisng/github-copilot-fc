function Invoke-CopilotWorkspaceCommand {
    <#
    .SYNOPSIS
        Execute commands from the Copilot FC workspace configuration.

    .DESCRIPTION
        Executes predefined terminal-first commands for managing
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

    $repoRoot = Split-Path $PSScriptRoot -Parent

    $commands = [ordered]@{
        'agents:publish'       = 'pwsh -NoProfile -File scripts/publish/publish-agents.ps1'
        'instructions:publish' = 'pwsh -NoProfile -File scripts/publish/publish-instructions.ps1'
        'prompts:publish'      = 'pwsh -NoProfile -File scripts/publish/publish-prompts.ps1'
        'skills:publish'       = 'pwsh -NoProfile -File scripts/publish/publish-skills.ps1'
        'toolsets:publish'     = 'pwsh -NoProfile -File scripts/publish/publish-toolsets.ps1'
        'issues:reindex'       = 'pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1'
        'workspace:list-skills' = 'Get-ChildItem -Path skills -Directory | Select-Object Name'
        'workspace:status'      = "Write-Host 'Copilot FC Workspace Status'; Get-ChildItem -Path skills -Directory | Measure-Object | Select-Object -ExpandProperty Count; Write-Host ' skills available'"
    }

    # If no command specified or 'list', show available commands
    if (-not $Command -or $Command -eq 'list') {
        Write-Host "Copilot FC workspace commands" -ForegroundColor Cyan
        Write-Host "=================================" -ForegroundColor Cyan
        Write-Host ""

        $commands.Keys | ForEach-Object {
            Write-Host "$($_.PadRight(20)) : $($commands[$_])" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "Usage: .\run-command.ps1 -Command <command-name>" -ForegroundColor Yellow
        return
    }

    # Execute the specified command
    if ($commands.Contains($Command)) {
        $commandLine = $commands[$Command]
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

# If script is run directly (not dot-sourced), execute the command
if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -eq 0) {
        Invoke-CopilotWorkspaceCommand -Command 'list'
    }
    else {
        Invoke-CopilotWorkspaceCommand -Command $args[0]
    }
}