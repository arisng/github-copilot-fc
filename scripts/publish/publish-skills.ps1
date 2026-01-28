param(
    [Parameter(Mandatory = $false)]
    [string[]]$Skills,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

function Publish-SkillsToPersonal {
    <#
    .SYNOPSIS
        Publishes skills from the workspace to personal skills folders.

    .DESCRIPTION
        Copies skills from the workspace skills/ folder to the user's personal
        skills folders (.claude, .codex, .copilot) for reuse across all projects.
        Automatically detects and publishes to WSL if available.

    .PARAMETER Skills
        Array of skill names to publish. If empty, publishes all skills.

    .PARAMETER Force
        Overwrite existing skills.

    .PARAMETER SkipWSL
        Skip publishing to WSL (Windows-only mode).

    .EXAMPLE
        Publish-SkillsToPersonal

        Copies all skills from the workspace to personal folders (Windows and WSL if available).

    .EXAMPLE
        Publish-SkillsToPersonal -Skills diataxis,beads

        Publishes only the 'diataxis' and 'beads' skills.

    .EXAMPLE
        Publish-SkillsToPersonal -Force

        Overwrites existing skills in both Windows and WSL.

    .EXAMPLE
        Publish-SkillsToPersonal -SkipWSL

        Publishes skills to Windows only, skipping WSL.
    #>

    Write-Host "Publishing skills to personal folders" -ForegroundColor Cyan

    $projectSkillsPath = Join-Path $PSScriptRoot "..\..\skills"
    $personalSkillsPaths = @(
        (Join-Path $env:USERPROFILE ".claude\skills"),
        (Join-Path $env:USERPROFILE ".codex\skills"),
        (Join-Path $env:USERPROFILE ".copilot\skills")
    )

    # WSL target paths (relative to WSL home directory)
    $wslSkillFolders = @(".claude/skills", ".codex/skills", ".copilot/skills")
    $wslAvailable = $false
    $wslHome = $null

    if (-not $SkipWSL) {
        try {
            $wslHome = wsl bash -c 'echo $HOME' 2>$null
            if ($wslHome -and $LASTEXITCODE -eq 0) {
                $wslAvailable = $true
                Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "WSL not available, skipping WSL publishing" -ForegroundColor Yellow
        }
    }

    # Ensure project skills directory exists
    if (-not (Test-Path $projectSkillsPath)) {
        throw "Project skills directory not found: $projectSkillsPath"
    }

    # Create personal skills directories if they don't exist
    foreach ($path in $personalSkillsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created personal skills directory: $path" -ForegroundColor Green
        }
    }

    # Get skills to publish
    $skillDirs = Get-ChildItem -Path $projectSkillsPath -Directory
    if ($Skills) {
        $skillDirs = $skillDirs | Where-Object { $_.Name -in $Skills }
    }

    if ($skillDirs.Count -eq 0) {
        Write-Host "No skills found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($skillDirs.Count) skill(s)" -ForegroundColor Cyan

    foreach ($skillDir in $skillDirs) {
        $sourcePath = $skillDir.FullName

        # Publish to Windows personal folders
        foreach ($path in $personalSkillsPaths) {
            $destinationPath = Join-Path $path $skillDir.Name
            $folder = Split-Path (Split-Path $path -Parent) -Leaf

            # Check if skill already exists
            $exists = Test-Path $destinationPath

            try {
                if ($exists -and -not $Force) {
                    Write-Host "Skipping $($skillDir.Name) for $folder (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                    continue
                }

                if ($exists) { Remove-Item -Path $destinationPath -Recurse -Force }
                Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
                Write-Host "Copied: $($skillDir.Name) to $folder" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to publish $($skillDir.Name) to $folder : $_"
            }
        }

        # Publish to WSL
        if ($wslAvailable) {
            foreach ($wslFolder in $wslSkillFolders) {
                $wslTargetPath = "$wslHome/$wslFolder/$($skillDir.Name)"
                $wslParentPath = "$wslHome/$wslFolder"
                $agent = Split-Path $wslFolder -Parent  # .claude, .codex, or .copilot

                try {
                    # Check if skill exists in WSL
                    $existsInWsl = wsl bash -c "test -d '$wslTargetPath' && echo 'exists' || echo 'notfound'" 2>$null

                    if ($existsInWsl -eq 'exists' -and -not $Force) {
                        Write-Host "Skipping $($skillDir.Name) for WSL/$agent (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                        continue
                    }

                    # Create parent directory if needed
                    wsl bash -c "mkdir -p '$wslParentPath'" 2>$null

                    # Remove existing skill if present
                    if ($existsInWsl -eq 'exists') {
                        wsl bash -c "rm -rf '$wslTargetPath'" 2>$null
                    }

                    # Copy skill to WSL using wsl command with Windows path converted to WSL path
                    $windowsSourcePath = [regex]::Replace(($sourcePath -replace '\\', '/'), '^([A-Za-z]):', { param($m) "/mnt/" + $m.Groups[1].Value.ToLower() })
                    wsl bash -c "cp -r '$windowsSourcePath' '$wslTargetPath'"

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Copied: $($skillDir.Name) to WSL/$agent" -ForegroundColor Green
                    } else {
                        Write-Error "Failed to copy $($skillDir.Name) to WSL/$agent (cp exited with code $LASTEXITCODE)"
                    }
                }
                catch {
                    Write-Error "Failed to publish $($skillDir.Name) to WSL/$agent : $_"
                }
            }
        }
    }

    Write-Host "Skill publishing completed." -ForegroundColor Cyan
    if ($wslAvailable) {
        Write-Host "Published to both Windows and WSL." -ForegroundColor Cyan
    }
    else {
        Write-Host "Published to Windows only (WSL not detected)." -ForegroundColor Cyan
    }
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-skills.ps1") {
    Publish-SkillsToPersonal
}