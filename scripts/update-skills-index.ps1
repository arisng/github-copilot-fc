# Update Skills Index

<#
.SYNOPSIS
    Scans the skills folder for SKILL.md files, parses YAML frontmatter, and updates the Skills Index in skills.instructions.md.

.DESCRIPTION
    This script scans subfolders in the skills directory, looks for SKILL.md or skill.md files (case insensitive),
    parses the YAML frontmatter to extract name and description, and updates the <skills-index> section in
    the skills.instructions.md file.

.PARAMETER SkillsPath
    Path to the skills folder. Defaults to '..\skills' relative to the script location.

.PARAMETER InstructionsPath
    Path to the skills.instructions.md file. Defaults to '..\.github\instructions\skills.instructions.md'.

.EXAMPLE
    .\update-skills-index.ps1

    Scans the default skills folder and updates the instructions file.

.EXAMPLE
    .\update-skills-index.ps1 -SkillsPath "C:\path\to\skills" -InstructionsPath "C:\path\to\instructions.md"

    Uses custom paths.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SkillsPath = (Join-Path $PSScriptRoot "..\skills"),

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InstructionsPath = (Join-Path $PSScriptRoot "..\instructions\skills.instructions.md")
)

function Parse-YamlFrontmatter {
    <#
    .SYNOPSIS
        Parses YAML frontmatter from a markdown file.

    .PARAMETER FilePath
        Path to the markdown file.

    .OUTPUTS
        Hashtable with Name and Description, or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    try {
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        Write-Verbose "Reading file: $FilePath"

        # Match YAML frontmatter between --- lines
        if ($content -match '(?s)---\s*(.+?)\s*---') {
            $yamlBlock = $matches[1]
            Write-Verbose "Found YAML frontmatter in $FilePath"

            $metadata = @{}

            # Extract name
            if ($yamlBlock -match 'name:\s*(.+)') {
                $metadata.Name = $matches[1].Trim()
            }

            # Extract description
            if ($yamlBlock -match 'description:\s*(.+)') {
                $metadata.Description = $matches[1].Trim()
            }

            if ($metadata.Name -and $metadata.Description) {
                Write-Verbose "Extracted metadata: Name='$($metadata.Name)', Description='$($metadata.Description)'"
                return $metadata
            } else {
                Write-Warning "Incomplete metadata in $FilePath (missing name or description)"
            }
        } else {
            Write-Warning "No YAML frontmatter found in $FilePath"
        }
    } catch {
        Write-Error "Failed to parse $FilePath`: $_"
    }

    return $null
}

function Get-SkillsMetadata {
    <#
    .SYNOPSIS
        Scans skills folder and extracts metadata from SKILL.md files.

    .PARAMETER SkillsPath
        Path to the skills folder.

    .OUTPUTS
        Array of hashtables with Name and Description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SkillsPath
    )

    $skills = @()

    try {
        $folders = Get-ChildItem -Path $SkillsPath -Directory -ErrorAction Stop
        Write-Verbose "Found $($folders.Count) subfolders in $SkillsPath"

        foreach ($folder in $folders) {
            Write-Verbose "Processing folder: $($folder.Name)"

            # Find SKILL.md or skill.md (case insensitive)
            $skillMdFiles = Get-ChildItem -Path $folder.FullName -Filter "*skill*.md"
            if ($skillMdFiles) {
                $skillMd = $skillMdFiles | Select-Object -First 1
                Write-Verbose "Found SKILL.md file: $($skillMd.FullName)"

                $metadata = Parse-YamlFrontmatter -FilePath $skillMd.FullName
                if ($metadata) {
                    $skills += $metadata
                }
            } else {
                Write-Warning "No SKILL.md file found in $($folder.Name)"
            }
        }
    } catch {
        Write-Error "Failed to scan skills folder: $_"
        throw
    }

    Write-Verbose "Extracted metadata for $($skills.Count) skills"
    return $skills
}

function Update-SkillsIndex {
    <#
    .SYNOPSIS
        Updates the Skills Index section in the instructions file.

    .PARAMETER InstructionsPath
        Path to the skills.instructions.md file.

    .PARAMETER Skills
        Array of skill metadata hashtables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstructionsPath,

        [Parameter(Mandatory)]
        [array]$Skills
    )

    try {
        $content = Get-Content $InstructionsPath -Raw -ErrorAction Stop
        Write-Verbose "Reading instructions file: $InstructionsPath"

        # Build new index content
        $indexContent = "<skills-index>`n"
        foreach ($skill in $Skills) {
            $indexContent += "- name: $($skill.Name)`n"
            $indexContent += "  description: $($skill.Description)`n"
        }
        $indexContent += "</skills-index>"

        # Replace the existing <skills-index> section
        $pattern = '(?s)<skills-index>.*?</skills-index>'
        if ($content -match $pattern) {
            $newContent = $content -replace $pattern, $indexContent
            $newContent | Out-File -FilePath $InstructionsPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "Successfully updated Skills Index in $InstructionsPath with $($Skills.Count) skills" -ForegroundColor Green
        } else {
            Write-Error "Could not find <skills-index> section in $InstructionsPath"
        }
    } catch {
        Write-Error "Failed to update instructions file: $_"
        throw
    }
}

# Main execution
try {
    Write-Host "Starting Skills Index update..." -ForegroundColor Cyan

    $skills = Get-SkillsMetadata -SkillsPath $SkillsPath
    Write-Host "Found $($skills.Count) skills"

    Update-SkillsIndex -InstructionsPath $InstructionsPath -Skills $skills

    Write-Host "Skills Index update completed successfully." -ForegroundColor Green
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
}