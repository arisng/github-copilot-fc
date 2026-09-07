#Requires -Version 7.0
# Migrate OpenCode Go URLs in chatLanguageModels.json to use the session-header proxy.
# Replaces https://opencode.ai/zen/go/v1/... with https://opencode-go.local/v1/...
# Does NOT touch https://opencode.ai/zen/v1/... (non-Go OpenCode Zen endpoints).
# Creates a .bak-<timestamp> backup before modifying.

param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# Auto-detect chatLanguageModels.json if not specified
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $candidates = @(
        "$env:APPDATA\Code - Insiders\User\chatLanguageModels.json",
        "$env:APPDATA\Code\User\chatLanguageModels.json"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ConfigPath = $c; break }
    }
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        Write-Error "chatLanguageModels.json not found. Pass -ConfigPath explicitly."
        exit 1
    }
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "File not found: $ConfigPath"
    exit 1
}

Write-Host "Migrating OpenCode Go URLs in: $ConfigPath" -ForegroundColor Cyan

# Read the file
$content = Get-Content $ConfigPath -Raw

# Check if there are any OpenCode Go URLs to migrate
$goPattern = 'https://opencode\.ai/zen/go/v1/'
$matches = [regex]::Matches($content, $goPattern)
if ($matches.Count -eq 0) {
    Write-Host "  No OpenCode Go URLs found. Nothing to migrate." -ForegroundColor Gray
    exit 0
}

Write-Host "  Found $($matches.Count) OpenCode Go URL(s) to migrate." -ForegroundColor Yellow

# Create backup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "$ConfigPath.bak-$timestamp"
Copy-Item $ConfigPath $backupPath -Force
Write-Host "  Backup created: $backupPath" -ForegroundColor Gray

# Replace URLs — only zen/go/v1 paths (not zen/v1)
$newContent = $content -replace 'https://opencode\.ai/zen/go/v1/chat/completions', 'https://opencode-go.local/v1/chat/completions'
$newContent = $newContent -replace 'https://opencode\.ai/zen/go/v1/responses', 'https://opencode-go.local/v1/responses'
$newContent = $newContent -replace 'https://opencode\.ai/zen/go/v1/messages', 'https://opencode-go.local/v1/messages'

# Write back
Set-Content $ConfigPath $newContent -Encoding UTF8 -NoNewline

# Verify
$verify = Get-Content $ConfigPath -Raw
$remaining = [regex]::Matches($verify, $goPattern).Count
$migrated = $matches.Count - $remaining

Write-Host "  Migrated $migrated URL(s)." -ForegroundColor Green
if ($remaining -gt 0) {
    Write-Host "  WARNING: $remaining OpenCode Go URL(s) remain (unexpected pattern?)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Reload VS Code (Developer: Reload Window) for changes to take effect." -ForegroundColor Cyan
Write-Host "  Make sure the OpenCode Go proxy is running: .\scripts\start-opencode-proxy.ps1" -ForegroundColor Cyan
