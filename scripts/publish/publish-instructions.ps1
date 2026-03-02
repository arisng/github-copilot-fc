<#
.SYNOPSIS
    Publishes instructions to VS Code, VS Code Insiders, and copilot-cli targets.

.DESCRIPTION
    Copies instruction files from the project's instructions/ folder to VS Code's and
    VS Code Insiders' user prompts directories, and optionally publishes to copilot-cli
    targets using one of two modes:

    - **Concat** (default): Concatenates all .instructions.md files into a single
      ~/.copilot/copilot-instructions.md with separator comments showing source filenames.
    - **EnvVar**: Prints instructions for setting the COPILOT_CUSTOM_INSTRUCTIONS_DIRS
      environment variable pointing to the repo's instructions/ directory.

    Both modes include WSL targets via the shared wsl-helpers.ps1 utility (unless -SkipWSL
    is specified).

.PARAMETER Instructions
    Array of instruction names to publish. If empty, publishes all instructions.

.PARAMETER Force
    Overwrite existing instructions without prompting.

.PARAMETER Mode
    CLI publishing mode. 'Concat' (default) concatenates files into
    ~/.copilot/copilot-instructions.md. 'EnvVar' prints environment variable setup
    instructions without modifying the system.

.PARAMETER SkipWSL
    Skip publishing to WSL (Windows-only mode).

.EXAMPLE
    ./publish-instructions.ps1
    Publishes all instructions to VS Code targets and concatenates to ~/.copilot/copilot-instructions.md.

.EXAMPLE
    ./publish-instructions.ps1 -Mode EnvVar
    Publishes to VS Code targets and prints COPILOT_CUSTOM_INSTRUCTIONS_DIRS setup instructions.

.EXAMPLE
    ./publish-instructions.ps1 -Instructions "powershell","csharp-14" -Force -SkipWSL
    Publishes specific instructions to VS Code targets only, skipping WSL and CLI concat.
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Instructions,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Concat", "EnvVar")]
    [string]$Mode = "Concat",

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

# Dot-source shared WSL utility
. "$PSScriptRoot/wsl-helpers.ps1"

function Publish-Instructions {
    <#
    .SYNOPSIS
        Publishes instructions to VS Code, copilot-cli, and WSL targets.
    #>

    Write-Host "Publishing instructions..." -ForegroundColor Cyan

    $projectInstructionsPath = Join-Path $PSScriptRoot "..\..\instructions"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )
    $cliInstructionsDir = Join-Path $env:USERPROFILE ".copilot"
    $cliInstructionsFile = Join-Path $cliInstructionsDir "copilot-instructions.md"

    # WSL detection
    $wslAvailable = $false
    $wslHome = $null
    if (-not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
    }

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

    # --- Counters for summary ---
    $vscodeSuccess = 0
    $vscodeFail = 0
    $cliSuccess = 0
    $cliFail = 0
    $wslSuccess = 0
    $wslFail = 0

    # ======================================================================
    # PHASE 1: VS Code targets (unchanged behavior)
    # ======================================================================
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

    # ======================================================================
    # PHASE 2: copilot-cli targets
    # ======================================================================
    if ($Mode -eq "Concat") {
        # --- Concat mode: merge all instruction files into single copilot-instructions.md ---
        Write-Host "`nCLI Mode: Concat — Merging instructions into copilot-instructions.md" -ForegroundColor Cyan

        # Ensure ~/.copilot/ directory exists
        if (-not (Test-Path $cliInstructionsDir)) {
            New-Item -ItemType Directory -Path $cliInstructionsDir -Force | Out-Null
            Write-Host "Created CLI directory: $cliInstructionsDir" -ForegroundColor Green
        }

        # Build concatenated content with separator comments
        $concatContent = @()
        $concatContent += "# Copilot Custom Instructions"
        $concatContent += "# Auto-generated by publish-instructions.ps1 (Concat mode)"
        $concatContent += "# Source: instructions/ directory"
        $concatContent += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $concatContent += ""

        foreach ($instructionFile in $instructionFiles) {
            $concatContent += "# --- Source: $($instructionFile.Name) ---"
            $concatContent += ""
            $fileContent = Get-Content -Path $instructionFile.FullName -Raw
            # Strip YAML frontmatter if present (applyTo is lost in Concat mode — expected)
            $fileContent = $fileContent -replace '(?s)^---\r?\n.*?\r?\n---\r?\n', ''
            $concatContent += $fileContent.TrimEnd()
            $concatContent += ""
            $concatContent += "# --- End: $($instructionFile.Name) ---"
            $concatContent += ""
        }

        $concatText = $concatContent -join "`n"

        # Write to Windows CLI target
        $exists = Test-Path $cliInstructionsFile
        if ($exists -and -not $Force) {
            $overwrite = Read-Host "copilot-instructions.md already exists at $cliInstructionsDir. Overwrite? (y/N)"
            if ($overwrite -notmatch "^[Yy]") {
                Write-Host "Skipping CLI concat target (Windows)" -ForegroundColor Yellow
            }
            else {
                try {
                    Set-Content -Path $cliInstructionsFile -Value $concatText -Encoding utf8 -Force
                    Write-Host "Published: copilot-instructions.md to ~/.copilot/ (Windows)" -ForegroundColor Green
                    $cliSuccess++
                }
                catch {
                    Write-Error "Failed to write CLI instructions: $_"
                    $cliFail++
                }
            }
        }
        else {
            try {
                Set-Content -Path $cliInstructionsFile -Value $concatText -Encoding utf8 -Force
                Write-Host "Published: copilot-instructions.md to ~/.copilot/ (Windows)" -ForegroundColor Green
                $cliSuccess++
            }
            catch {
                Write-Error "Failed to write CLI instructions: $_"
                $cliFail++
            }
        }

        # Write to WSL CLI target
        if ($wslAvailable) {
            $wslConcatPath = "$wslHome/.copilot/copilot-instructions.md"
            $wslConcatDir = "$wslHome/.copilot"

            # Write concat content to a temp file, then copy to WSL
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $concatText -Encoding utf8 -Force
                $copied = Copy-ToWSL -Source $tempFile -Destination $wslConcatPath
                if ($copied) {
                    Write-Host "Published: copilot-instructions.md to ~/.copilot/ (WSL)" -ForegroundColor Green
                    $wslSuccess++
                }
                else {
                    $wslFail++
                }
            }
            catch {
                Write-Warning "Failed to publish copilot-instructions.md to WSL: $_"
                $wslFail++
            }
            finally {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    elseif ($Mode -eq "EnvVar") {
        # --- EnvVar mode: print instructions for environment variable setup ---
        Write-Host "`nCLI Mode: EnvVar — Environment variable setup instructions" -ForegroundColor Cyan
        $absInstructionsPath = (Resolve-Path $projectInstructionsPath).Path

        Write-Host ""
        Write-Host "To use copilot-cli with per-file instructions, set the following environment variable:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Windows (PowerShell — current session):" -ForegroundColor White
        Write-Host "    `$env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS = '$absInstructionsPath'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Windows (PowerShell — persistent via profile):" -ForegroundColor White
        Write-Host "    Add to `$PROFILE: `$env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS = '$absInstructionsPath'" -ForegroundColor Gray
        Write-Host ""

        if ($wslAvailable) {
            $wslInstructionsPath = Convert-ToWSLPath -Path $absInstructionsPath
            Write-Host "  WSL (bash — current session):" -ForegroundColor White
            Write-Host "    export COPILOT_CUSTOM_INSTRUCTIONS_DIRS='$wslInstructionsPath'" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  WSL (bash — persistent via ~/.bashrc):" -ForegroundColor White
            Write-Host "    echo `"export COPILOT_CUSTOM_INSTRUCTIONS_DIRS='$wslInstructionsPath'`" >> ~/.bashrc" -ForegroundColor Gray
            Write-Host ""
        }

        Write-Host "Note: EnvVar mode does NOT modify your environment. Copy the commands above manually." -ForegroundColor DarkGray
        $cliSuccess = 1  # Count informational output as success
    }

    # ======================================================================
    # PHASE 3: Summary
    # ======================================================================
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "Files processed:      $($instructionFiles.Count)" -ForegroundColor White
    Write-Host "VS Code targets:      $vscodeSuccess published, $vscodeFail failed" -ForegroundColor White
    Write-Host "CLI targets ($Mode):  $cliSuccess published, $cliFail failed" -ForegroundColor White
    if (-not $SkipWSL) {
        $wslStatus = if ($wslAvailable) { "$wslSuccess published, $wslFail failed" } else { "not available" }
        Write-Host "WSL targets:          $wslStatus" -ForegroundColor White
    }
    else {
        Write-Host "WSL targets:          skipped (-SkipWSL)" -ForegroundColor White
    }
    Write-Host "Instruction publishing completed." -ForegroundColor Cyan
}

# Execute main function unconditionally.
Publish-Instructions
