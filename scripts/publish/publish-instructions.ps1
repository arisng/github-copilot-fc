<#
.SYNOPSIS
    Publishes instructions to VS Code prompts directories (Windows + WSL).
.DESCRIPTION
    Copies .instructions.md files to VS Code Stable and Insiders user prompts
    directories on Windows. Optionally publishes to WSL VS Code prompts via
    wsl-helpers.ps1 (unless -SkipWSL is specified).
.PARAMETER Instructions
    Instruction names to publish (supports wildcards). Publishes all if omitted.
.PARAMETER Force
    Overwrite existing instructions without prompting.
.PARAMETER SkipWSL
    Skip publishing to WSL VS Code targets.
.EXAMPLE
    ./publish-instructions.ps1 -Instructions "powershell","csharp-14" -Force
#>
param(
    [string[]]$Instructions,
    [switch]$Force,
    [switch]$SkipWSL
)

# Dot-source shared WSL utility
. "$PSScriptRoot/wsl-helpers.ps1"

# CLI instructions publishing is intentionally excluded (ISS-002).
# Concatenating all .instructions.md files into a single copilot-instructions.md
# overloads the CLI context window. VS Code's per-file applyTo pattern is superior.

function Publish-Instructions {
    Write-Host "Publishing instructions..." -ForegroundColor Cyan

    $projectInstructionsPath = Join-Path $PSScriptRoot "..\..\instructions"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # WSL VS Code prompts paths (relative to WSL home directory)
    $wslVscodePromptsPaths = @(
        ".config/Code/User/prompts",
        ".config/Code - Insiders/User/prompts"
    )

    # WSL detection
    $wslAvailable = $false
    $wslHome = $null
    if (-not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
    }

    if (-not (Test-Path $projectInstructionsPath)) {
        throw "Project instructions directory not found: $projectInstructionsPath"
    }

    foreach ($path in $vscodePromptsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    # Get and filter instruction files
    $instructionFiles = Get-ChildItem -Path $projectInstructionsPath -Filter "*.instructions.md"
    if ($Instructions) {
        $instrList = @()
        foreach ($item in $Instructions) {
            $instrList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        $instructionFiles = $instructionFiles | Where-Object {
            $base = $_.Name -replace '\.instructions\.md$',''
            $instrList | Where-Object { $base -like $_ } | Select-Object -First 1
        }
        if ($instructionFiles.Count -eq 0) {
            Write-Host "Warning: No instructions found matching: $($instrList -join ', ')" -ForegroundColor Yellow
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
    $vscodeSuccess = 0; $vscodeFail = 0
    $wslSuccess = 0; $wslFail = 0

    # --- VS Code Windows targets ---
    foreach ($instructionFile in $instructionFiles) {
        $sourcePath = $instructionFile.FullName
        foreach ($path in $vscodePromptsPaths) {
            $destinationPath = Join-Path $path $instructionFile.Name
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
                $vscodeSuccess++
            }
            catch {
                Write-Error "Failed to publish $($instructionFile.BaseName) to $path : $_"
                $vscodeFail++
            }
        }
    }

    # --- WSL VS Code targets ---
    if ($wslAvailable) {
        foreach ($instructionFile in $instructionFiles) {
            foreach ($wslPromptsPath in $wslVscodePromptsPaths) {
                $wslTarget = "$wslHome/$wslPromptsPath/$($instructionFile.Name)"
                $copied = Copy-ToWSL -Source $instructionFile.FullName -Destination $wslTarget
                if ($copied) {
                    $edition = if ($wslPromptsPath -like "*Insiders*") { "Insiders" } else { "Stable" }
                    Write-Host "Published: $($instructionFile.BaseName) to WSL VS Code $edition" -ForegroundColor Green
                    $wslSuccess++
                }
                else {
                    $wslFail++
                }
            }
        }
    }

    # --- Summary ---
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "Files processed:      $($instructionFiles.Count)" -ForegroundColor White
    Write-Host "VS Code targets:      $vscodeSuccess published, $vscodeFail failed" -ForegroundColor White
    if (-not $SkipWSL) {
        $wslStatus = if ($wslAvailable) { "$wslSuccess published, $wslFail failed" } else { "not available" }
        Write-Host "WSL VS Code targets:  $wslStatus" -ForegroundColor White
    }
    else {
        Write-Host "WSL VS Code targets:  skipped (-SkipWSL)" -ForegroundColor White
    }
    Write-Host "Instruction publishing completed." -ForegroundColor Cyan
}

# Execute main function unconditionally.
Publish-Instructions
