<#
.SYNOPSIS
    Validates that SKILL.md description fields do not exceed 1024 characters.

.DESCRIPTION
    PostToolUse hook that fires after file write/edit operations. Parses the
    hook payload (VS Code snake_case or CLI camelCase format), checks whether
    the target file is a SKILL.md, extracts the YAML frontmatter description,
    and emits additionalContext guidance when the limit is exceeded.

    Exit code 0 always — this is a non-blocking warning hook.
#>

$ErrorActionPreference = 'Stop'
$MAX_DESCRIPTION_LENGTH = 1024

# --- Helpers ---

function Get-JsonInput {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        # Malformed JSON — silently pass (non-blocking hook)
        return $null
    }
}

function Get-ToolInput {
    param([psobject]$Event)
    # VS Code: tool_input (object), CLI: toolArgs (JSON string)
    $inputObj = $null
    $prop = $Event.PSObject.Properties['tool_input']
    if ($null -ne $prop -and $null -ne $prop.Value) {
        $inputObj = $prop.Value
    }
    else {
        $prop = $Event.PSObject.Properties['toolArgs']
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $val = $prop.Value
            if ($val -is [string]) {
                $inputObj = ($val | ConvertFrom-Json)
            }
            else {
                $inputObj = $val
            }
        }
    }
    return $inputObj
}

function Get-FilePath {
    param([psobject]$InputObj)
    foreach ($name in @('file_path', 'filePath', 'path')) {
        $prop = $InputObj.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            return $prop.Value
        }
    }
    return $null
}

function Get-FileContent {
    param([psobject]$InputObj)
    # Full-file writes: file_text, fileText, content, text
    foreach ($name in @('file_text', 'fileText', 'content', 'text')) {
        $prop = $InputObj.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [string]) {
            return $prop.Value
        }
    }
    # String replacements: new_str, newText (only the new text portion)
    foreach ($name in @('new_str', 'newText', 'new_string')) {
        $prop = $InputObj.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [string]) {
            return $prop.Value
        }
    }
    return $null
}

function Extract-Frontmatter {
    param([string]$Content)
    $lines = $Content -split "`n"
    $start = -1
    $end = -1
    $foundFirst = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -eq '---') {
            if (-not $foundFirst) {
                $start = $i + 1
                $foundFirst = $true
            }
            else {
                $end = $i
                break
            }
        }
    }

    if ($start -ge 0 -and $end -gt $start) {
        return ($lines[$start..($end - 1)] -join "`n")
    }
    return $null
}

function Extract-Description {
    param([string]$Frontmatter)
    if ([string]::IsNullOrWhiteSpace($Frontmatter)) { return $null }

    $lines = $Frontmatter -split "`n"
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^\s*description\s*:\s*>-') {
            # Folded block scalar — collect indented continuation lines
            $parts = @()
            $i++
            while ($i -lt $lines.Count) {
                $next = $lines[$i]
                if ($next -match '^\s+\S' -or $next -match '^\s*$') {
                    $parts += $next.TrimStart()
                    $i++
                }
                else { break }
            }
            return ($parts -join ' ').Trim()
        }
        elseif ($line -match '^\s*description\s*:\s*"(.*)"\s*$') {
            return $Matches[1]
        }
        elseif ($line -match "^\s*description\s*:\s*'(.*)'\s*$") {
            return $Matches[1]
        }
        elseif ($line -match '^\s*description\s*:\s*(.+)\s*$') {
            return $Matches[1].Trim()
        }
        $i++
    }
    return $null
}

# --- Main ---

$event = Get-JsonInput
if ($null -eq $event) { Write-Output '{}'; exit 0 }

# Determine tool name (VS Code: tool_name, CLI: toolName)
$toolName = $null
foreach ($name in @('tool_name', 'toolName')) {
    $prop = $event.PSObject.Properties[$name]
    if ($null -ne $prop -and $null -ne $prop.Value) {
        $toolName = $prop.Value
        break
    }
}

# Write tools across runtimes
$writeTools = @('write_file', 'replace_string_in_file', 'multi_replace_string_in_file', 'create', 'edit')
if ($toolName -notin $writeTools) {
    Write-Output '{}'
    exit 0
}

$inputObj = Get-ToolInput -Event $event
if ($null -eq $inputObj) { Write-Output '{}'; exit 0 }

$filePath = Get-FilePath -InputObj $inputObj
if ([string]::IsNullOrWhiteSpace($filePath)) { Write-Output '{}'; exit 0 }

# Only fire for SKILL.md files
if (-not $filePath.EndsWith('SKILL.md', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Output '{}'
    exit 0
}

$content = Get-FileContent -InputObj $inputObj
if ([string]::IsNullOrWhiteSpace($content)) { Write-Output '{}'; exit 0 }

# Try full frontmatter extraction first (full-file writes)
$frontmatter = Extract-Frontmatter -Content $content
$description = Extract-Description -Frontmatter $frontmatter

# If no frontmatter found, try partial-edit extraction (replacement fragments
# that don't contain --- delimiters but still contain a description line)
if ([string]::IsNullOrWhiteSpace($description)) {
    $description = Extract-Description -Frontmatter $content
}

if ([string]::IsNullOrWhiteSpace($description)) { Write-Output '{}'; exit 0 }

$length = $description.Length
if ($length -gt $MAX_DESCRIPTION_LENGTH) {
    $msg = "SKILL.md description is $length characters (limit: $MAX_DESCRIPTION_LENGTH). Please trim the description field to no more than $MAX_DESCRIPTION_LENGTH characters."
    $output = @{ additionalContext = $msg } | ConvertTo-Json -Compress
    Write-Output $output
}
else {
    Write-Output '{}'
}

exit 0
