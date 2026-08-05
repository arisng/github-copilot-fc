<#
.SYNOPSIS
    Adds the "work" OpenCode Go account as separate provider entries in VS Code
    Insiders chatLanguageModels.json, renaming the existing entries to "(Home, ...)".
.DESCRIPTION
    VS Code stores BYOK API keys in secret storage, so the work key must first be
    registered through the UI:
      1. VS Code Insiders -> Command Palette -> "Chat: Manage Language Models"
      2. "Add Models" -> "Custom Endpoint"
      3. Name: OpenCode Go (Work, OpenAI) | API key: <work key> | API Type: Chat Completions
      4. This writes a new provider entry whose apiKey is "${input:chat.lm.secret.XXXX}".
    Then run this script. It renames the two existing "OpenCode Go (OpenAI|Anthropic)"
    providers to "(Home, ...)" and clones them into "(Work, ...)" entries, reusing the
    secret reference from the provider you just added (or from -WorkSecretRef).
.PARAMETER WorkSecretRef
    Optional. The secret reference to use for the Work providers, e.g.
    "${input:chat.lm.secret.abc123}". If omitted, the script looks for an existing
    provider named "OpenCode Go (Work, OpenAI)" (as created by the UI step) and
    reuses its secret.
.PARAMETER LmFile
    Optional. Path to chatLanguageModels.json. Defaults to the VS Code Insiders file.
.EXAMPLE
    .\opencode-vscode-add-work-account.ps1
.EXAMPLE
    .\opencode-vscode-add-work-account.ps1 -WorkSecretRef '${input:chat.lm.secret.abc123}'
#>
param(
    [string]$WorkSecretRef,
    [string]$LmFile = "$env:APPDATA\Code - Insiders\User\chatLanguageModels.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LmFile)) {
    Write-Error "chatLanguageModels.json not found at $LmFile"
    exit 1
}

# Back up
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $LmFile "$LmFile.bak-$ts" -Force
Write-Host "Backup: $LmFile.bak-$ts" -ForegroundColor Green

$lm = Get-Content $LmFile -Raw | ConvertFrom-Json
if ($lm -isnot [array]) { $lm = @($lm) }

function Get-Provider {
    param([string]$Name)
    return $lm | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

# 1) Rename existing OpenCode providers to (Home, ...)
$renameMap = @{
    'OpenCode Go (OpenAI)'      = 'OpenCode Go (Home, OpenAI)'
    'OpenCode Go (Anthropic)'   = 'OpenCode Go (Home, Anthropic)'
}
foreach ($k in $renameMap.Keys) {
    $p = Get-Provider -Name $k
    if ($p) { $p.name = $renameMap[$k]; Write-Host "Renamed '$k' -> '$($renameMap[$k])'" -ForegroundColor Gray }
    else { Write-Warning "'$k' not found; skipping rename (already done?)" }
}

# 2) Determine the work secret reference
if (-not $WorkSecretRef) {
    $uiEntry = Get-Provider -Name 'OpenCode Go (Work, OpenAI)'
    if ($uiEntry -and $uiEntry.apiKey) {
        $WorkSecretRef = $uiEntry.apiKey
        Write-Host "Using secret ref from UI-added provider: $WorkSecretRef" -ForegroundColor Gray
    }
    else {
        Write-Error "Could not find a 'OpenCode Go (Work, OpenAI)' provider (from the UI step) and -WorkSecretRef was not provided."
        exit 1
    }
}

# 3) Clone Home providers into Work providers (replace any pre-existing Work entries)
foreach ($suffix in @('OpenAI', 'Anthropic')) {
    $src = Get-Provider -Name "OpenCode Go (Home, $suffix)"
    if (-not $src) { Write-Warning "OpenCode Go (Home, $suffix) not found; skipping Work clone."; continue }
    $existing = Get-Provider -Name "OpenCode Go (Work, $suffix)"
    if ($existing) {
        $lm = @($lm | Where-Object { $_ -ne $existing })
        Write-Host "Replaced existing 'OpenCode Go (Work, $suffix)'" -ForegroundColor Yellow
    }
    $clone = $src | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $clone.name = "OpenCode Go (Work, $suffix)"
    $clone.apiKey = $WorkSecretRef
    $lm = @($lm) + $clone
    Write-Host "Added 'OpenCode Go (Work, $suffix)'" -ForegroundColor Green
}

# 4) Save
$lm | ConvertTo-Json -Depth 12 | Set-Content $LmFile -Encoding UTF8
Write-Host ""
Write-Host "Saved $LmFile" -ForegroundColor Cyan
Write-Host "Next: reload the VS Code window (Developer: Reload Window). Both Home and Work"
Write-Host "OpenCode Go providers will appear in the chat model picker." -ForegroundColor Cyan
