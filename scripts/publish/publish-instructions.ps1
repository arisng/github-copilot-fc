param(
    [Parameter(Mandatory = $false)]
    [string[]]$Instructions,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-InstructionsToVSCode {
    <#
    .SYNOPSIS
        Publishes instructions from the project factory to VS Code and VS Code Insiders user prompts directories.

    .DESCRIPTION
        Copies instruction files from the project's instructions/ folder to VS Code's and VS Code Insiders'
        user prompts directories for global availability across all workspaces and devices.

    .PARAMETER Instructions
        Array of instruction names to publish. If empty, publishes all instructions.

    .PARAMETER Force
        Overwrite existing instructions without prompting.

    .EXAMPLE
        Publish-InstructionsToVSCode

        Copies all instructions from project to VS Code user prompts.

    .EXAMPLE
        Publish-InstructionsToVSCode -Instructions "powershell", "claude-skills"

        Copies specific instructions.
    #>

    Write-Host "Publishing instructions to VS Code..." -ForegroundColor Cyan

    $projectInstructionsPath = Join-Path $PSScriptRoot "..\..\instructions"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # Ensure project instructions directory exists
    if (-not (Test-Path $projectInstructionsPath)) {
        throw "Project instructions directory not found: $projectInstructionsPath"
    }

    # Create VS Code prompts directories if they don't exist
    foreach ($path in $vscodePromptsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created VS Code prompts directory: $path" -ForegroundColor Green
        }
    }

    # Get instruction files to publish
    $instructionFiles = Get-ChildItem -Path $projectInstructionsPath -Filter "*.instructions.md"
    if ($Instructions) {
        # convert comma-separated strings to array if necessary
        $instrList = @()
        foreach ($item in $Instructions) {
            $instrList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        # perform wildcard matching against base names
        $instructionFiles = $instructionFiles | Where-Object {
            $base = $_.Name -replace '\.instructions\.md$',''
            $instrList | Where-Object { $base -like $_ } | Select-Object -First 1
        }
        if ($instructionFiles.Count -eq 0) {
            Write-Host "Warning: No instructions found matching: $($instrList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available instructions:" -ForegroundColor Cyan
            Get-ChildItem -Path $projectInstructionsPath -Filter "*.instructions.md" | 
                ForEach-Object { Write-Host "  - $($_.Name -replace '\.instructions\.md$')" }
            return
        }
    }

    if ($instructionFiles.Count -eq 0) {
        Write-Host "No instruction files found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($instructionFiles.Count) instruction file(s)..." -ForegroundColor Cyan

    foreach ($instructionFile in $instructionFiles) {
        $sourcePath = $instructionFile.FullName

        foreach ($path in $vscodePromptsPaths) {
            $destinationPath = Join-Path $path $instructionFile.Name

            # Check if instruction already exists
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                $overwrite = Read-Host "Instruction '$($instructionFile.BaseName)' already exists in VS Code $edition. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($instructionFile.BaseName) for VS Code $edition" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                Write-Host "Published: $($instructionFile.BaseName) to VS Code $edition" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to publish $($instructionFile.BaseName) to $path : $_"
            }
        }
    }

    Write-Host "Instruction publishing completed." -ForegroundColor Cyan
}

# Execute main function unconditionally.  The previous guard used
# $MyInvocation.InvocationName which becomes '&' when the script is invoked
# via the call operator; as a result the helper never executed during wrapper
# invocations.
Publish-InstructionsToVSCode
