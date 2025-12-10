function Copy-SkillsInstructions {
    [CmdletBinding()]
    param()

    $sourcePath = Join-Path $PSScriptRoot "..\instructions\skills.instructions.md"
    $destinationDir = Join-Path $env:APPDATA "Code\User\prompts"
    $destinationPath = Join-Path $destinationDir "skills.instructions.md"

    try {
        # Ensure source file exists
        if (-not (Test-Path $sourcePath)) {
            throw "Source file not found: $sourcePath"
        }

        # Create destination directory if it doesn't exist
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            Write-Verbose "Created directory: $destinationDir"
        }

        # Copy the file
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
        Write-Verbose "Copied file from $sourcePath to $destinationPath"
    }
    catch {
        Write-Error "Failed to copy skills instructions: $_"
        throw
    }
}

# Execute the function
Copy-SkillsInstructions