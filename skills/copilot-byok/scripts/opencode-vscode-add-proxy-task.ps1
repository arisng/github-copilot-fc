#Requires -Version 7.0
# Add the OpenCode Go proxy background task to .vscode/tasks.json.
# Creates tasks.json if it doesn't exist. Skips if the task already exists.
# Run from the workspace root (where .vscode/ lives).

param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

# Auto-detect workspace root from current directory
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Get-Location
}

$vscodeDir = Join-Path $WorkspaceRoot '.vscode'
$tasksPath = Join-Path $vscodeDir 'tasks.json'

# Resolve the proxy script path (installed skill location)
$proxyScript = Join-Path $HOME '.agents' 'skills' 'copilot-byok' 'scripts' 'start-opencode-proxy.ps1'
if (-not (Test-Path $proxyScript)) {
    # Fallback: try the authoring location
    $proxyScript = Join-Path $HOME 'Workplace' 'Agents' 'github-copilot-fc' 'skills' 'copilot-byok' 'scripts' 'start-opencode-proxy.ps1'
}
if (-not (Test-Path $proxyScript)) {
    Write-Error "start-opencode-proxy.ps1 not found. Is the copilot-byok skill installed?"
    exit 1
}

Write-Host "Adding OpenCode Go proxy task to: $tasksPath" -ForegroundColor Cyan

# Ensure .vscode directory exists
if (-not (Test-Path $vscodeDir)) {
    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
}

$taskLabel = 'OpenCode Go Proxy'

if (Test-Path $tasksPath) {
    # Read existing tasks.json
    $content = Get-Content $tasksPath -Raw
    $tasks = $content | ConvertFrom-Json

    # Check if the task already exists
    if ($tasks.tasks) {
        foreach ($t in $tasks.tasks) {
            if ($t.label -eq $taskLabel) {
                Write-Host "  Task '$taskLabel' already exists. Skipping." -ForegroundColor Gray
                exit 0
            }
        }
    }

    # Add the new task
    $newTask = [ordered]@{
        label = $taskLabel
        type = 'shell'
        command = "pwsh -NoProfile -File `"$proxyScript`""
        runOptions = [ordered]@{ runOn = 'folderOpen' }
        isBackground = $true
        problemMatcher = @()
    }

    if (-not $tasks.tasks) {
        $tasks | Add-Member -NotePropertyName 'tasks' -NotePropertyValue @($newTask) -Force
    } else {
        $tasks.tasks = @($tasks.tasks) + @($newTask)
    }

    # Backup and write
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $tasksPath "$tasksPath.bak-$timestamp" -Force
    $tasks | ConvertTo-Json -Depth 10 | Set-Content $tasksPath -Encoding UTF8

    Write-Host "  Added task '$taskLabel' to existing tasks.json" -ForegroundColor Green
    Write-Host "  Backup: $tasksPath.bak-$timestamp" -ForegroundColor Gray
} else {
    # Create new tasks.json
    $tasksObj = [ordered]@{
        version = '2.0.0'
        tasks = @(
            [ordered]@{
                label = $taskLabel
                type = 'shell'
                command = "pwsh -NoProfile -File `"$proxyScript`""
                runOptions = [ordered]@{ runOn = 'folderOpen' }
                isBackground = $true
                problemMatcher = @()
            }
        )
    }

    $tasksObj | ConvertTo-Json -Depth 10 | Set-Content $tasksPath -Encoding UTF8
    Write-Host "  Created tasks.json with task '$taskLabel'" -ForegroundColor Green
}

Write-Host ""
Write-Host "  The proxy will auto-start when you open this workspace in VS Code." -ForegroundColor Cyan
Write-Host "  You can also run it manually: Terminal → Run Task → '$taskLabel'" -ForegroundColor Cyan
