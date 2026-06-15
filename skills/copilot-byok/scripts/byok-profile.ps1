<#
.SYNOPSIS
    Profile manager for GitHub Copilot CLI BYOK (Bring Your Own Key) LLM providers.

.DESCRIPTION
    Stores and switches between LLM provider configurations for Copilot CLI.
    Configurations are persisted in ~/.copilot/byok-profiles.json (or $COPILOT_HOME/byok-profiles.json).

    Supported provider types: openai (default), azure, anthropic.
    OpenCode Go is supported via preset in the interactive 'add' workflow.

.PARAMETER Command
    Action to perform: list, show, add, remove, run, set-env

.PARAMETER Profile
    Profile name to target.

.PARAMETER Arguments
    Additional arguments passed through to the copilot command when using 'run'.

.EXAMPLE
    .\byok-profile.ps1 list

    Lists all stored provider profiles.

.EXAMPLE
    .\byok-profile.ps1 run ollama

    Starts Copilot CLI using the 'ollama' profile for this session only.

.EXAMPLE
    . .\byok-profile.ps1 set-env openai

    Dot-source to apply the 'openai' profile environment variables to the current shell.

.EXAMPLE
    .\byok-profile.ps1 add

    Interactively creates a new provider profile.
#>
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('list', 'show', 'add', 'remove', 'run', 'set-env')]
    [string]$Command = 'list',

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Profile,

    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

# Resolve config directory respecting COPILOT_HOME
$configDir = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
$profilePath = Join-Path $configDir 'byok-profiles.json'

function ConvertTo-Hashtable {
    param([object]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.Hashtable]) { return $InputObject }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $collection = @()
        foreach ($item in $InputObject) {
            $collection += (ConvertTo-Hashtable -InputObject $item)
        }
        return $collection
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = (ConvertTo-Hashtable -InputObject $prop.Value)
        }
        return $hash
    }
    return $InputObject
}

function Get-ProfileConfig {
    if (-not (Test-Path $profilePath)) {
        return @{ profiles = @{} }
    }
    $raw = Get-Content $profilePath -Raw | ConvertFrom-Json
    $raw = ConvertTo-Hashtable -InputObject $raw
    if (-not $raw) { return @{ profiles = @{} } }
    if (-not $raw.profiles) { $raw.profiles = @{} }
    return $raw
}

function Save-ProfileConfig {
    param($Config)
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }
    $Config | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8
}

function Expand-EnvPlaceholder {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    return [regex]::Replace($Value, '\$\{([^}]+)\}', {
        param($m)
        $varName = $m.Groups[1].Value
        $envValue = [Environment]::GetEnvironmentVariable($varName)
        if ($null -eq $envValue) {
            Write-Warning "Environment variable '$varName' is not defined."
            return $m.Value
        }
        return $envValue
    })
}

function Set-ProviderEnvironment {
    param($Provider)
    $env:COPILOT_PROVIDER_BASE_URL = $Provider.baseUrl
    $env:COPILOT_MODEL = $Provider.model

    if ($Provider.type) {
        $env:COPILOT_PROVIDER_TYPE = $Provider.type
    }
    else {
        $env:COPILOT_PROVIDER_TYPE = 'openai'
    }

    if ($Provider.wireApi) {
        $env:COPILOT_PROVIDER_WIRE_API = $Provider.wireApi
    }
    else {
        Remove-Item Env:\COPILOT_PROVIDER_WIRE_API -ErrorAction SilentlyContinue
    }

    if ($Provider.apiKey) {
        $env:COPILOT_PROVIDER_API_KEY = Expand-EnvPlaceholder -Value $Provider.apiKey
    }
    else {
        Remove-Item Env:\COPILOT_PROVIDER_API_KEY -ErrorAction SilentlyContinue
    }

    if ($Provider.offline -eq $true) {
        $env:COPILOT_OFFLINE = 'true'
    }
    else {
        Remove-Item Env:\COPILOT_OFFLINE -ErrorAction SilentlyContinue
    }

    if ($Provider.maxPromptTokens) {
        $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = [string]$Provider.maxPromptTokens
    }
    else {
        Remove-Item Env:\COPILOT_PROVIDER_MAX_PROMPT_TOKENS -ErrorAction SilentlyContinue
    }

    if ($Provider.maxOutputTokens) {
        $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = [string]$Provider.maxOutputTokens
    }
    else {
        Remove-Item Env:\COPILOT_PROVIDER_MAX_OUTPUT_TOKENS -ErrorAction SilentlyContinue
    }
}

function Invoke-ProfileList {
    $config = Get-ProfileConfig
    $profiles = $config.profiles
    if ($profiles.Count -eq 0) {
        Write-Host "No profiles found. Use 'add' to create one." -ForegroundColor Yellow
        return
    }

    Write-Host "BYOK Profiles ($profilePath)" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan

    foreach ($name in ($profiles.Keys | Sort-Object)) {
        $p = $profiles[$name]
        $type = if ($p.type) { $p.type } else { 'openai' }
        $offline = if ($p.offline -eq $true) { ' [offline]' } else { '' }
        Write-Host "$name" -ForegroundColor Green -NoNewline
        Write-Host " -> $type | $($p.model) | $($p.baseUrl)$offline" -ForegroundColor Gray
    }
}

function Invoke-ProfileShow {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Profile name is required for 'show'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }
    $config.profiles[$Name] | ConvertTo-Json -Depth 10
}

function Invoke-ProfileRemove {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Profile name is required for 'remove'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }
    $config.profiles.Remove($Name)
    Save-ProfileConfig -Config $config
    Write-Host "Removed profile '$Name'." -ForegroundColor Green
}

function Invoke-ProfileAdd {
    $config = Get-ProfileConfig

    Write-Host "Create a new BYOK provider profile" -ForegroundColor Cyan
    $name = Read-Host "Profile name (e.g., ollama, azure-prod, kimi)"
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Error "Profile name cannot be empty."
        exit 1
    }
    if ($config.profiles.ContainsKey($name)) {
        $overwrite = Read-Host "Profile '$name' already exists. Overwrite? (y/N)"
        if ($overwrite -notin @('y', 'Y')) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Choose a preset (or select Custom to enter values manually):" -ForegroundColor Cyan
    Write-Host "  1) OpenAI"
    Write-Host "  2) Azure OpenAI"
    Write-Host "  3) Anthropic"
    Write-Host "  4) Ollama (local)"
    Write-Host "  5) Kimi AI / Moonshot"
    Write-Host "  6) OpenCode Go"
    Write-Host "  7) Custom"
    $preset = Read-Host "Preset number [7]"
    if ([string]::IsNullOrWhiteSpace($preset)) { $preset = '7' }

    $type = 'openai'
    $baseUrl = ''
    $model = ''
    $defaultApiKeyPrompt = ''
    $defaultMaxPromptTokens = $null
    $defaultMaxOutputTokens = $null

    switch ($preset) {
        '1' {
            $type = 'openai'
            $baseUrl = 'https://api.openai.com/v1'
            $model = 'gpt-4o'
            $defaultApiKeyPrompt = '${OPENAI_API_KEY}'
            $defaultMaxPromptTokens = 128000
        }
        '2' {
            $type = 'azure'
            $baseUrl = Read-Host "Azure base URL (e.g., https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT)"
            $model = Read-Host "Azure deployment name"
            $defaultApiKeyPrompt = '${AZURE_OPENAI_API_KEY}'
        }
        '3' {
            $type = 'anthropic'
            $baseUrl = 'https://api.anthropic.com'
            $model = 'claude-opus-4-5'
            $defaultApiKeyPrompt = '${ANTHROPIC_API_KEY}'
            $defaultMaxPromptTokens = 200000
        }
        '4' {
            $type = 'openai'
            $baseUrl = 'http://localhost:11434'
            $model = 'llama3.2'
            $defaultApiKeyPrompt = ''
            $defaultMaxPromptTokens = 32768
        }
        '5' {
            $type = 'openai'
            $defaultApiKeyPrompt = '${MOONSHOT_API_KEY}'
            $defaultMaxPromptTokens = 240000

            Write-Host "Select Kimi AI region:" -ForegroundColor Cyan
            Write-Host "  1) Global (api.moonshot.ai/v1) - recommended"
            Write-Host "  2) China (api.moonshot.cn/v1)"
            $region = Read-Host "Region [1]"
            if ([string]::IsNullOrWhiteSpace($region) -or $region -eq '1') {
                $baseUrl = 'https://api.moonshot.ai/v1'
            }
            else {
                $baseUrl = 'https://api.moonshot.cn/v1'
            }

            Write-Host "Select model:" -ForegroundColor Cyan
            Write-Host "  1) Kimi K2.7 Code (coding-optimized, thinking always on)"
            Write-Host "  2) Kimi K2.6 (latest flagship, multimodal)"
            Write-Host "  3) Kimi K2.5 (multimodal, lower cost)"
            $modelChoice = Read-Host "Model [2]"
            $model = switch ($modelChoice) {
                '1' { 'kimi-k2.7-code' }
                '2' { 'kimi-k2.6' }
                '3' { 'kimi-k2.5' }
                default { 'kimi-k2.6' }
            }
        }
        '6' {
            $type = 'openai'
            $baseUrl = 'https://opencode.ai/zen/go/v1'
            $defaultApiKeyPrompt = '${OPENCODE_API_KEY}'

            Write-Host "Select OpenCode Go model category:" -ForegroundColor Cyan
            Write-Host "  1) OpenAI-compatible (DeepSeek, GLM, Kimi, MiMo)"
            Write-Host "  2) Anthropic-compatible (MiniMax, Qwen)"
            $modelCategory = Read-Host "Category [1]"
            if ([string]::IsNullOrWhiteSpace($modelCategory) -or $modelCategory -eq '1') {
                $type = 'openai'
                Write-Host "Select model:" -ForegroundColor Cyan
                Write-Host "  1) DeepSeek V4 Flash (cheapest, recommended)"
                Write-Host "  2) DeepSeek V4 Pro"
                Write-Host "  3) Kimi K2.7 Code"
                Write-Host "  4) Kimi K2.6"
                Write-Host "  5) GLM-5.1"
                Write-Host "  6) GLM-5"
                Write-Host "  7) MiMo-V2.5"
                Write-Host "  8) MiMo-V2.5-Pro"
                $modelChoice = Read-Host "Model [1]"
                $model = switch ($modelChoice) {
                    '1' { 'deepseek-v4-flash' }
                    '2' { 'deepseek-v4-pro' }
                    '3' { 'kimi-k2.7-code' }
                    '4' { 'kimi-k2.6' }
                    '5' { 'glm-5.1' }
                    '6' { 'glm-5' }
                    '7' { 'mimo-v2.5' }
                    '8' { 'mimo-v2.5-pro' }
                    default { 'deepseek-v4-flash' }
                }
            }
            else {
                $type = 'anthropic'
                Write-Host "Select model:" -ForegroundColor Cyan
                Write-Host "  1) Qwen3.7 Plus (recommended)"
                Write-Host "  2) Qwen3.7 Max"
                Write-Host "  3) Qwen3.6 Plus"
                Write-Host "  4) MiniMax M3"
                Write-Host "  5) MiniMax M2.7"
                $modelChoice = Read-Host "Model [1]"
                $model = switch ($modelChoice) {
                    '1' { 'qwen3.7-plus' }
                    '2' { 'qwen3.7-max' }
                    '3' { 'qwen3.6-plus' }
                    '4' { 'minimax-m3' }
                    '5' { 'minimax-m2.7' }
                    default { 'qwen3.7-plus' }
                }
            }
            $defaultMaxPromptTokens = 200000
        }
        default {
            $type = Read-Host "Provider type (openai/azure/anthropic) [openai]"
            if ([string]::IsNullOrWhiteSpace($type)) { $type = 'openai' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        $baseUrl = Read-Host "Base URL (e.g., http://localhost:11434 or https://api.openai.com/v1)"
    }
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        Write-Error "Base URL is required."
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = Read-Host "Model identifier (e.g., llama3.2, gpt-4o, claude-opus-4-5)"
    }
    if ([string]::IsNullOrWhiteSpace($model)) {
        Write-Error "Model is required."
        exit 1
    }

    if ($defaultApiKeyPrompt) {
        $apiKey = Read-Host "API key [${defaultApiKeyPrompt}]"
        if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $defaultApiKeyPrompt }
    }
    else {
        $apiKey = Read-Host "API key (leave blank for none; use `${ENV_VAR}` syntax to reference an environment variable)"
    }

    if ($defaultMaxPromptTokens) {
        $maxPromptTokensInput = Read-Host "Max prompt tokens [$defaultMaxPromptTokens]"
        if ([string]::IsNullOrWhiteSpace($maxPromptTokensInput)) { $maxPromptTokensInput = $defaultMaxPromptTokens }
    }
    else {
        $maxPromptTokensInput = Read-Host "Max prompt tokens (optional, press Enter to skip)"
    }
    $maxPromptTokens = if ($maxPromptTokensInput) { [int]$maxPromptTokensInput } else { $null }

    $maxOutputTokensInput = Read-Host "Max output tokens (optional, press Enter to skip)"
    $maxOutputTokens = if ($maxOutputTokensInput) { [int]$maxOutputTokensInput } else { $null }

    $offlineInput = Read-Host "Offline mode? (y/N)"
    $offline = $offlineInput -in @('y', 'Y')

    $profileEntry = [ordered]@{
        type    = $type
        baseUrl = $baseUrl
        model   = $model
        apiKey  = if ($apiKey) { $apiKey } else { $null }
        offline = $offline
    }
    if ($maxPromptTokens) { $profileEntry.maxPromptTokens = $maxPromptTokens }
    if ($maxOutputTokens) { $profileEntry.maxOutputTokens = $maxOutputTokens }

    $config.profiles[$name] = $profileEntry

    Save-ProfileConfig -Config $config
    Write-Host "Saved profile '$name'." -ForegroundColor Green
}

function Invoke-ProfileRun {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Profile name is required for 'run'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }

    Set-ProviderEnvironment -Provider $config.profiles[$Name]

    # Show a brief summary
    $p = $config.profiles[$Name]
    Write-Host "Launching copilot with profile '$Name'" -ForegroundColor Cyan
    Write-Host "  Provider : $(if ($p.type) { $p.type } else { 'openai' })" -ForegroundColor Gray
    Write-Host "  Base URL : $($p.baseUrl)" -ForegroundColor Gray
    Write-Host "  Model    : $($p.model)" -ForegroundColor Gray
    if ($p.wireApi) { Write-Host "  Wire API : $($p.wireApi)" -ForegroundColor Gray }
    if ($p.maxPromptTokens) { Write-Host "  Max Prompt Tokens : $($p.maxPromptTokens)" -ForegroundColor Gray }
    if ($p.maxOutputTokens) { Write-Host "  Max Output Tokens : $($p.maxOutputTokens)" -ForegroundColor Gray }
    if ($p.offline -eq $true) { Write-Host "  Offline  : true" -ForegroundColor Gray }
    Write-Host ""

    $copilotCmd = Get-Command copilot -ErrorAction SilentlyContinue
    if (-not $copilotCmd) {
        Write-Error "'copilot' command not found in PATH. Is Copilot CLI installed?"
        exit 1
    }

    & copilot @Arguments
}

function Invoke-ProfileSetEnv {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Profile name is required for 'set-env'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }

    Set-ProviderEnvironment -Provider $config.profiles[$Name]

    $p = $config.profiles[$Name]
    Write-Host "Applied profile '$Name' to the current shell session." -ForegroundColor Green
    Write-Host "  COPILOT_PROVIDER_BASE_URL = $($env:COPILOT_PROVIDER_BASE_URL)" -ForegroundColor Gray
    Write-Host "  COPILOT_PROVIDER_TYPE     = $($env:COPILOT_PROVIDER_TYPE)" -ForegroundColor Gray
    Write-Host "  COPILOT_MODEL             = $($env:COPILOT_MODEL)" -ForegroundColor Gray
    if ($env:COPILOT_PROVIDER_WIRE_API) {
        Write-Host "  COPILOT_PROVIDER_WIRE_API = $($env:COPILOT_PROVIDER_WIRE_API)" -ForegroundColor Gray
    }
    if ($env:COPILOT_PROVIDER_API_KEY) {
        Write-Host "  COPILOT_PROVIDER_API_KEY  = ***" -ForegroundColor Gray
    }
    if ($env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS) {
        Write-Host "  COPILOT_PROVIDER_MAX_PROMPT_TOKENS  = $($env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS)" -ForegroundColor Gray
    }
    if ($env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS) {
        Write-Host "  COPILOT_PROVIDER_MAX_OUTPUT_TOKENS  = $($env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS)" -ForegroundColor Gray
    }
    if ($env:COPILOT_OFFLINE) {
        Write-Host "  COPILOT_OFFLINE           = $($env:COPILOT_OFFLINE)" -ForegroundColor Gray
    }
}

switch ($Command) {
    'list'    { Invoke-ProfileList }
    'show'    { Invoke-ProfileShow -Name $Profile }
    'add'     { Invoke-ProfileAdd }
    'remove'  { Invoke-ProfileRemove -Name $Profile }
    'run'     { Invoke-ProfileRun -Name $Profile }
    'set-env' { Invoke-ProfileSetEnv -Name $Profile }
    default   { Invoke-ProfileList }
}

