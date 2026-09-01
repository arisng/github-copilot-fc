<#
.SYNOPSIS
    Smoke tests for the skill-description-guard hook script.

.DESCRIPTION
    Feeds mock postToolUse payloads and asserts correct output:
    - Warning (additionalContext) for >1024 char descriptions
    - Empty {} for <=1024 char descriptions
    - Empty {} for non-SKILL.md files
    - Empty {} for non-write tools
    - Both VS Code and CLI payload formats
#>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\skill-description-guard.ps1'

$pass = 0
$fail = 0

function Assert-Output {
    param(
        [string]$TestName,
        [string]$PayloadJson,
        [bool]$ExpectWarning
    )

    # Write payload to temp file and use Get-Content pipe to avoid $input conflicts
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmpFile, $PayloadJson)
        $result = Get-Content -Raw -Path $tmpFile | pwsh -NoProfile -File $scriptPath 2>$null
    }
    finally {
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    }

    $hasWarning = $result -notmatch '^\s*\{\s*\}\s*$'

    if ($ExpectWarning -and $hasWarning) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:pass++
    }
    elseif (-not $ExpectWarning -and -not $hasWarning) {
        Write-Host " PASS: $TestName" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        Write-Host "    Expected warning: $ExpectWarning, Got: $hasWarning" -ForegroundColor Red
        Write-Host "    Output: $result" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`n=== skill-description-guard smoke tests ===" -ForegroundColor Cyan

# --- VS Code format tests ---

Write-Host "`nVS Code format (snake_case):" -ForegroundColor Yellow

# Test 1: SKILL.md with long description (>1024 chars) via write_file
$longDesc = ('A' * 1100)
$payload1 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "---`nname: my-skill`ndescription: >-`n  $longDesc`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "write_file + SKILL.md >1024 chars => warning" -PayloadJson $payload1 -ExpectWarning $true

# Test 2: SKILL.md with short description (≤1024 chars) via write_file
$shortDesc = ('B' * 500)
$payload2 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "---`nname: my-skill`ndescription: $shortDesc`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "write_file + SKILL.md <=1024 chars => no warning" -PayloadJson $payload2 -ExpectWarning $false

# Test 3: Non-SKILL.md file via write_file
$payload3 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/README.md'
        file_text = "---`ntitle: Readme`n---`n# Hello`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "write_file + README.md => no warning" -PayloadJson $payload3 -ExpectWarning $false

# Test 4: SKILL.md via replace_string_in_file (new_str exceeds limit)
$longNewStr = ('C' * 1200)
$payload4 = @{
    tool_name = 'replace_string_in_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        new_str = "---`nname: my-skill`ndescription: >-`n  $longNewStr`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "replace_string_in_file + SKILL.md >1024 chars => warning" -PayloadJson $payload4 -ExpectWarning $true

# Test 5: Non-write tool → no warning
$payload5 = @{
    tool_name = 'read_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
    }
} | ConvertTo-Json -Depth 5
Assert-Output "read_file + SKILL.md => no warning" -PayloadJson $payload5 -ExpectWarning $false

# --- CLI format tests ---

Write-Host "`nCLI format (camelCase):" -ForegroundColor Yellow

# Test 6: CLI create + SKILL.md >1024 chars
$payload6 = @{
    toolName = 'create'
    toolArgs = (@{
        file_path = 'skills/my-skill/SKILL.md'
        text = "---`nname: my-skill`ndescription: >-`n  $longDesc`n---`n# Body`n"
    } | ConvertTo-Json -Depth 5)
} | ConvertTo-Json -Depth 5
Assert-Output "CLI create + SKILL.md >1024 chars => warning" -PayloadJson $payload6 -ExpectWarning $true

# Test 7: CLI edit + SKILL.md ≤1024 chars → no warning
$payload7 = @{
    toolName = 'edit'
    toolArgs = (@{
        file_path = 'skills/my-skill/SKILL.md'
        newText = "---`nname: my-skill`ndescription: $shortDesc`n---`n# Body`n"
    } | ConvertTo-Json -Depth 5)
} | ConvertTo-Json -Depth 5
Assert-Output "CLI edit + SKILL.md <=1024 chars => no warning" -PayloadJson $payload7 -ExpectWarning $false
# --- Boundary tests ---

Write-Host "`nBoundary tests:" -ForegroundColor Yellow

# Test 8: Description exactly at 1024 chars => no warning
$exactDesc = ('D' * 1024)
$payload8 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "---`nname: my-skill`ndescription: $exactDesc`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "Description exactly 1024 chars => no warning" -PayloadJson $payload8 -ExpectWarning $false

# Test 9: Description at 1025 chars => warning
$overDesc = ('E' * 1025)
$payload9 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "---`nname: my-skill`ndescription: $overDesc`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "Description 1025 chars => warning" -PayloadJson $payload9 -ExpectWarning $true

# --- Edge-case tests ---

Write-Host "`nEdge-case tests:" -ForegroundColor Yellow

# Test 10: Double-quoted description
$quotedDesc = ('F' * 1100)
$payload10 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "---`nname: my-skill`ndescription: `"$quotedDesc`"`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "Double-quoted description >1024 => warning" -PayloadJson $payload10 -ExpectWarning $true

# Test 11: Partial-edit (replace_string_in_file with only new_str, no --- delimiters)
$partialNewStr = "description: >-`n  $longDesc"
$payload11 = @{
    tool_name = 'replace_string_in_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        new_str = $partialNewStr
    }
} | ConvertTo-Json -Depth 5
Assert-Output "Partial-edit new_str >1024 => warning" -PayloadJson $payload11 -ExpectWarning $true

# Test 12: No frontmatter at all => no warning
$payload12 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills/my-skill/SKILL.md'
        file_text = "# Just a heading`nNo frontmatter here.`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "No frontmatter => no warning" -PayloadJson $payload12 -ExpectWarning $false

# Test 13: Malformed JSON on stdin => no crash, no warning
$payload13 = "this is not json {{{"
$tmpFile13 = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tmpFile13, $payload13)
    $result13 = Get-Content -Raw -Path $tmpFile13 | pwsh -NoProfile -File $scriptPath 2>$null
    $hasWarning13 = $result13 -notmatch '^\s*\{\s*\}\s*$'
    if (-not $hasWarning13) {
        Write-Host "  PASS: Malformed JSON => no warning" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: Malformed JSON => should not warn" -ForegroundColor Red
        Write-Host "    Output: $result13" -ForegroundColor Red
        $script:fail++
    }
}
finally {
    Remove-Item -Path $tmpFile13 -Force -ErrorAction SilentlyContinue
}

# Test 14: Windows-style backslash path
$payload14 = @{
    tool_name = 'write_file'
    tool_input = @{
        file_path = 'skills\my-skill\SKILL.md'
        file_text = "---`nname: my-skill`ndescription: $longDesc`n---`n# Body`n"
    }
} | ConvertTo-Json -Depth 5
Assert-Output "Backslash path + SKILL.md >1024 => warning" -PayloadJson $payload14 -ExpectWarning $true
# --- Summary ---

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
