# Extract Issue Metadata and Generate Report Table

# Determine the issues folder: check _docs first, then .docs
if (Test-Path "_docs/issues") {
    $issuesPath = "_docs/issues"
} else {
    $issuesPath = ".docs/issues"
}

# Get all .md files in the issues folder
$files = Get-ChildItem -Path $issuesPath -Filter "*.md" | Where-Object { $_.Name -ne "index.md" }

# Initialize an array to hold the report data
$report = @()

function Parse-YamlFrontmatter {
    param([string]$Content)

    $metadata = @{
        Date = ""
        Type = ""
        Severity = ""
        Status = ""
    }

    # Check if content starts with YAML frontmatter (use single-line mode for dot matching)
    if ($Content -match '(?s)^\s*---\s*[\r\n]+(.+?)[\r\n]+---') {
        $yamlBlock = $matches[1]

        # Parse YAML fields
        if ($yamlBlock -match 'date:\s*([^\r\n]+)') {
            $metadata.Date = $matches[1].Trim()
        }

        if ($yamlBlock -match 'type:\s*([^\r\n]+)') {
            $metadata.Type = $matches[1].Trim()
        }

        if ($yamlBlock -match 'severity:\s*([^\r\n]+)') {
            $metadata.Severity = $matches[1].Trim()
        }

        if ($yamlBlock -match 'status:\s*([^\r\n]+)') {
            $metadata.Status = $matches[1].Trim()
        }

        return $metadata
    }

    return $null
}

function Parse-LegacyMetadata {
    param([string]$Content)

    $metadata = @{
        Date = ""
        Type = ""
        Severity = ""
        Status = ""
    }

    # Extract the header (metadata) part before first heading or ---
    $header = $Content -split '---' | Select-Object -First 1

    # Extract metadata using regex (flexible to handle variations)
    if ($header -match '\*\*Date:\*\*\s*([^\r\n]+)') {
        $metadata.Date = $matches[1].Trim()
    }

    if ($header -match '\*\*(?:Issue\s+)?Type:\*\*\s*([^\r\n]+)') {
        $metadata.Type = $matches[1].Trim()
    }

    if ($header -match '\*\*Severity:\*\*\s*([^\r\n]+)') {
        $metadata.Severity = $matches[1].Trim()
    }

    if ($header -match '\*\*Status:\*\*\s*([^\r\n]+)') {
        $metadata.Status = $matches[1].Trim()
    }

    return $metadata
}

# Process each file
foreach ($file in $files) {
    # Read the file content
    $content = Get-Content $file.FullName -Raw

    # Try parsing YAML frontmatter first
    $metadata = Parse-YamlFrontmatter -Content $content

    # Fallback to legacy format if no YAML found
    if ($null -eq $metadata) {
        $metadata = Parse-LegacyMetadata -Content $content
        $format = "Legacy"
    }
    else {
        $format = "YAML"
    }

    # Warn if required fields are missing
    $warnings = @()
    if (-not $metadata.Date) { $warnings += "Missing Date" }
    if (-not $metadata.Type) { $warnings += "Missing Type" }
    if (-not $metadata.Status) { $warnings += "Missing Status" }

    if ($warnings.Count -gt 0) {
        Write-Host "[WARN] $($file.Name): $($warnings -join ', ')" -ForegroundColor Yellow
    }

    # Add to report array
    $report += [PSCustomObject]@{
        File       = $file.Name
        Date       = $metadata.Date
        Type       = $metadata.Type
        Severity   = $metadata.Severity
        Status     = $metadata.Status
        Format     = $format
    }
}

# Generate summary statistics
$totalFiles = $report.Count
$yamlCount = ($report | Where-Object { $_.Format -eq "YAML" }).Count
$legacyCount = ($report | Where-Object { $_.Format -eq "Legacy" }).Count
$missingDate = ($report | Where-Object { -not $_.Date }).Count
$missingType = ($report | Where-Object { -not $_.Type }).Count
$missingStatus = ($report | Where-Object { -not $_.Status }).Count

Write-Host "`n==================================="
Write-Host "Issue Metadata Extraction Summary"
Write-Host "==================================="
Write-Host "Total files: $totalFiles"
Write-Host "YAML frontmatter: $yamlCount" -ForegroundColor Green
Write-Host "Legacy format: $legacyCount" -ForegroundColor $(if ($legacyCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "`nMissing required fields:"
Write-Host "  Date: $missingDate" -ForegroundColor $(if ($missingDate -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Type: $missingType" -ForegroundColor $(if ($missingType -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Status: $missingStatus" -ForegroundColor $(if ($missingStatus -gt 0) { "Yellow" } else { "Green" })

# Generate Markdown table with updated columns
$outputLines = @()
$outputLines += "# Issue Metadata Index"
$outputLines += ""
$outputLines += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$outputLines += ""
$outputLines += "**Statistics:**"
$outputLines += "- Total Issues: $totalFiles"
$outputLines += "- YAML Format: $yamlCount"
$outputLines += "- Legacy Format: $legacyCount"
$outputLines += ""
$outputLines += "| File | Date | Type | Status | Severity | Format |"
$outputLines += "|------|------|------|--------|----------|--------|"

foreach ($item in $report | Sort-Object Date -Descending) {
    $outputLines += "| $($item.File) | $($item.Date) | $($item.Type) | $($item.Status) | $($item.Severity) | $($item.Format) |"
}

# Output to a markdown file in the issues folder
$outputPath = "$issuesPath/index.md"
$outputLines | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "`nReport generated at $outputPath" -ForegroundColor Cyan