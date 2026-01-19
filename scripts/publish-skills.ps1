param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Copy', 'Link', 'Sync')]
    [string]$Method,

    [Parameter(Mandatory = $false)]
    [string[]]$Skills,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-SkillsToPersonal {
    <#
    .SYNOPSIS
        Publishes skills from the project factory to personal skills folders.

    .DESCRIPTION
        Copies or links skills from the project's skills/ folder to the user's personal
        skills folders (.claude, .codex, .copilot) for reuse across all projects.

    .PARAMETER Method
        The publishing method: 'Copy', 'Link', or 'Sync'

    .PARAMETER Skills
        Array of skill names to publish. If empty, publishes all skills.

    .PARAMETER Force
        Overwrite existing skills without prompting.

    .EXAMPLE
        Publish-SkillsToPersonal -Method Copy

        Copies all skills from project to personal folders.

    .EXAMPLE
        Publish-SkillsToPersonal -Method Link -Skills "git-atomic-commit", "issue-writer"

        Creates symbolic links for specific skills in all personal folders.
    #>

    Write-Host "Script started with Method: $Method" -ForegroundColor Cyan

    $projectSkillsPath = Join-Path $PSScriptRoot "..\skills"
    $personalSkillsPaths = @(
        (Join-Path $env:USERPROFILE ".claude\skills"),
        (Join-Path $env:USERPROFILE ".codex\skills"),
        (Join-Path $env:USERPROFILE ".copilot\skills")
    )

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

    Write-Host "Publishing $($skillDirs.Count) skill(s) using method: $Method" -ForegroundColor Cyan

    foreach ($skillDir in $skillDirs) {
        $sourcePath = $skillDir.FullName

        foreach ($path in $personalSkillsPaths) {
            $destinationPath = Join-Path $path $skillDir.Name
            $folder = Split-Path (Split-Path $path -Parent) -Leaf

            # Check if skill already exists
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $overwrite = Read-Host "Skill '$($skillDir.Name)' already exists in $folder. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($skillDir.Name) for $folder" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                switch ($Method) {
                    'Copy' {
                        if ($exists) { Remove-Item -Path $destinationPath -Recurse -Force }
                        Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
                        Write-Host "Copied: $($skillDir.Name) to $folder" -ForegroundColor Green
                    }
                    'Link' {
                        if ($exists) { Remove-Item -Path $destinationPath -Force }
                        # Create symbolic link (requires admin privileges on Windows)
                        $target = $sourcePath
                        $link = $destinationPath
                        New-Item -ItemType SymbolicLink -Path $link -Target $target -Force | Out-Null
                        Write-Host "Linked: $($skillDir.Name) to $folder" -ForegroundColor Green
                    }
                    'Sync' {
                        # Use robocopy for incremental sync
                        $robocopyArgs = @(
                            "`"$sourcePath`"",
                            "`"$destinationPath`"",
                            "/MIR",  # Mirror directory tree
                            "/NJH",  # No job header
                            "/NJS"   # No job summary
                        )
                        $result = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                        if ($result.ExitCode -le 3) { # Robocopy exit codes: 0-3 are success
                            Write-Host "Synced: $($skillDir.Name) to $folder" -ForegroundColor Green
                        } else {
                            Write-Warning "Sync failed for $($skillDir.Name) in $folder (Exit code: $($result.ExitCode))"
                        }
                    }
                }
            }
            catch {
                Write-Error "Failed to publish $($skillDir.Name) to $folder : $_"
            }
        }
    }

    Write-Host "Skill publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-skills.ps1") {
    Publish-SkillsToPersonal
}