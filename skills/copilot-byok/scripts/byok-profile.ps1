<#
.SYNOPSIS
    Profile manager for GitHub Copilot CLI BYOK (Bring Your Own Key) LLM providers.

.DESCRIPTION
    Stores and switches between LLM provider configurations for Copilot CLI.
    Configurations are persisted in ~/.copilot/byok-profiles.json (or $COPILOT_HOME/byok-profiles.json).

    Supported provider types: openai (default), azure, anthropic.
    OpenCode Go is supported via preset in the interactive 'add' workflow.

.PARAMETER Command
    Action to perform: list, show, add, remove, run, set-env, accounts, use

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
    [ValidateSet('list', 'show', 'add', 'remove', 'run', 'set-env', 'accounts', 'use')]
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
    if (-not $raw) { return @{ profiles = @{}; accounts = @{} } }
    if (-not $raw.profiles) { $raw.profiles = @{} }
    if (-not $raw.accounts) { $raw.accounts = @{} }
    if (-not $raw.ContainsKey('activeAccount')) { $raw.activeAccount = $null }
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

# Models whose API does not expose controllable reasoning-effort levels. This is the
# single source of truth used by the wizard (add), run, set-env, and show. It mirrors
# references/reasoning-effort-lookup.md; keep both in sync.
function Get-NoReasoningEffortModels {
    return @(
        'kimi-k2.7-code', 'kimi-k2.6', 'kimi-k2.5',
        'glm-5.2', 'glm-5.1', 'glm-5',
        'mimo-v2.5', 'mimo-v2.5-pro', 'mimo-v2-pro', 'mimo-v2-omni',
        'qwen3.7-plus', 'qwen3.7-max', 'qwen3.6-plus', 'qwen3.5-plus',
        'minimax-m3', 'minimax-m2.7', 'minimax-m2.5'
    )
}

# Derive whether a model supports Copilot CLI --reasoning-effort.
# A stored profile flag (reasoningEffortSupported) takes precedence when present, but
# hand-added profiles may omit it, so fall back to the shared model list. This prevents
# forwarding --reasoning-effort to models that reject it.
function Test-ReasoningEffortSupported {
    param($Model, $Profile)
    if ($Profile -and $Profile.PSObject.Properties.Name -contains 'reasoningEffortSupported') {
        return [bool]$Profile.reasoningEffortSupported
    }
    if ($null -ne $Model -and $Model -in (Get-NoReasoningEffortModels)) {
        return $false
    }
    return $true
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

function Resolve-ProfileAccount {
    <#
    .SYNOPSIS
        Resolves which account (and which API-key env var) applies to a profile.
    .DESCRIPTION
        Only profiles with an 'accountGroup' field participate in account resolution.
        Resolution order: --account override > profile 'account' pin > config 'activeAccount'.
        Returns a hashtable with Name / KeyEnv / Source, or $null when the profile is
        not account-grouped. Emits a warning and returns $null when resolution fails,
        letting callers fall back to the profile's legacy 'apiKey' field.
    #>
    param(
        [hashtable]$Config,
        [hashtable]$Profile,
        [string]$AccountOverride
    )
    if (-not $Profile.accountGroup) { return $null }

    $accountName = $null
    $source = ''
    if ($AccountOverride) {
        $accountName = $AccountOverride
        $source = '--account override'
    }
    elseif ($Profile.account) {
        $accountName = $Profile.account
        $source = 'profile account pin'
    }
    elseif ($Config.activeAccount) {
        $accountName = $Config.activeAccount
        $source = 'activeAccount'
    }

    if (-not $accountName) {
        Write-Warning "Profile '$($Profile.model)' uses accountGroup '$($Profile.accountGroup)' but no account is selected. Run 'byok-profile.ps1 use <account>' or pass --account. Falling back to profile apiKey."
        return $null
    }
    if (-not $Config.accounts -or -not $Config.accounts.ContainsKey($accountName)) {
        Write-Warning "Account '$accountName' is not defined in the 'accounts' registry (via $source). Falling back to profile apiKey."
        return $null
    }
    $keyEnv = $Config.accounts[$accountName].keyEnv
    if (-not $keyEnv) {
        Write-Warning "Account '$accountName' has no 'keyEnv' set (via $source). Falling back to profile apiKey."
        return $null
    }
    return @{
        Name   = $accountName
        KeyEnv = $keyEnv
        Source = $source
    }
}

function Remove-AccountArg {
    <#
    .SYNOPSIS
        Extracts a --account <name> / --account=<name> override from CLI arguments.
    .DESCRIPTION
        Returns @{ Account = <name or $null>; Arguments = <remaining args> }.
        The account token is consumed here and never forwarded to copilot.
    #>
    param([string[]]$ArgList)
    $account = $null
    $newArgs = [System.Collections.Generic.List[string]]::new()
    $skipNext = $false
    foreach ($arg in $ArgList) {
        if ($skipNext) {
            $account = $arg
            $skipNext = $false
            continue
        }
        if ($arg -match '^--account=(.+)$') {
            $account = $Matches[1]
            continue
        }
        if ($arg -eq '--account') {
            $skipNext = $true
            continue
        }
        $newArgs.Add($arg)
    }
    if ($skipNext) {
        Write-Warning "'--account' was the last argument and has no value; ignoring it."
    }
    return @{ Account = $account; Arguments = $newArgs.ToArray() }
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
        $accountInfo = if ($p.accountGroup) { " [accountGroup: $($p.accountGroup)]" } else { '' }
        Write-Host "$name" -ForegroundColor Green -NoNewline
        Write-Host " -> $type | $($p.model) | $($p.baseUrl)$offline$accountInfo" -ForegroundColor Gray
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
    $p = $config.profiles[$Name]
    $p | ConvertTo-Json -Depth 10
    $reasoningSupported = Test-ReasoningEffortSupported -Model $p.model -Profile $p
    Write-Host ""
    Write-Host "  Reasoning Effort Supported : $reasoningSupported" -ForegroundColor Gray
    $resolved = Resolve-ProfileAccount -Config $config -Profile $p -AccountOverride $null
    if ($resolved) {
        Write-Host ""
        Write-Host "  Account : $($resolved.Name) ($($resolved.KeyEnv), via $($resolved.Source))" -ForegroundColor Green
    }
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

function Invoke-ProfileAccounts {
    $config = Get-ProfileConfig
    $accounts = $config.accounts
    if (-not $accounts -or $accounts.Count -eq 0) {
        Write-Host "No accounts defined. Add an 'accounts' section to $profilePath (see references/copilot-cli-providers.md)." -ForegroundColor Yellow
        return
    }

    Write-Host "BYOK Accounts ($profilePath)" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
    $active = $config.activeAccount

    foreach ($name in ($accounts.Keys | Sort-Object)) {
        $a = $accounts[$name]
        $marker = if ($name -eq $active) { ' [active]' } else { '' }
        $label = if ($a.label) { $a.label } else { '(no label)' }
        $keyEnv = if ($a.keyEnv) { $a.keyEnv } else { '(no keyEnv)' }
        Write-Host "$name" -ForegroundColor Green -NoNewline
        Write-Host " -> $label | keyEnv: $keyEnv$marker" -ForegroundColor Gray
    }

    if (-not $active) {
        Write-Host "" -ForegroundColor Gray
        Write-Host "No active account set. Use 'use <account>' to select one." -ForegroundColor Yellow
    }
}

function Invoke-ProfileUse {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Account name is required for 'use'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.accounts -or -not $config.accounts.ContainsKey($Name)) {
        Write-Error "Account '$Name' is not defined in the 'accounts' registry. See $profilePath"
        exit 1
    }
    $config.activeAccount = $Name
    Save-ProfileConfig -Config $config
    $a = $config.accounts[$Name]
    Write-Host "Active account set to '$Name'." -ForegroundColor Green
    if ($a.label) { Write-Host "  $($a.label)" -ForegroundColor Gray }
    if ($a.keyEnv) { Write-Host "  API key env: $($a.keyEnv)" -ForegroundColor Gray }
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
            $defaultApiKeyPrompt = '${OPENCODE_API_KEY_HOME}'

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
                Write-Host "  5) GLM-5.2"
                Write-Host "  6) GLM-5.1"
                Write-Host "  7) GLM-5"
                Write-Host "  8) MiMo-V2.5"
                Write-Host "  9) MiMo-V2.5-Pro"
                Write-Host "  10) Other (type model ID manually)"
                $modelChoice = Read-Host "Model [1]"
                $model = switch ($modelChoice) {
                    '1' { 'deepseek-v4-flash' }
                    '2' { 'deepseek-v4-pro' }
                    '3' { 'kimi-k2.7-code' }
                    '4' { 'kimi-k2.6' }
                    '5' { 'glm-5.2' }
                    '6' { 'glm-5.1' }
                    '7' { 'glm-5' }
                    '8' { 'mimo-v2.5' }
                    '9' { 'mimo-v2.5-pro' }
                    '10' { Read-Host "Enter model ID" }
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

    # Determine whether the model supports Copilot CLI --reasoning-effort
    $supportsReasoningEffort = Test-ReasoningEffortSupported -Model $model -Profile $null

    $profileEntry = [ordered]@{
        type    = $type
        baseUrl = $baseUrl
        model   = $model
        apiKey  = if ($apiKey) { $apiKey } else { $null }
        offline = $offline
    }
    if ($supportsReasoningEffort -eq $false) { $profileEntry.reasoningEffortSupported = $false }
    if ($maxPromptTokens) { $profileEntry.maxPromptTokens = $maxPromptTokens }
    if ($maxOutputTokens) { $profileEntry.maxOutputTokens = $maxOutputTokens }

    if ($supportsReasoningEffort -eq $false) {
        Write-Host "  Note: '$model' does not support --reasoning-effort. The profile has 'reasoningEffortSupported: false'." -ForegroundColor DarkYellow
    }

    if ($preset -eq '6') {
        $profileEntry.accountGroup = 'opencode'
        Write-Host "  Note: accountGroup 'opencode' set. Select the account with 'use <account>' or 'run <profile> --account <account>'." -ForegroundColor DarkYellow
    }

    $config.profiles[$name] = $profileEntry

    Save-ProfileConfig -Config $config
    Write-Host "Saved profile '$name'." -ForegroundColor Green
}

function Start-MoonshotProxy {
    <#
    .SYNOPSIS
        Auto-start the Moonshot top_p fix proxy if not already running.
    .DESCRIPTION
        Checks ports 3002 and 443. If neither is listening, starts start-proxy.ps1 elevated.
        Profiles needing the proxy set "proxyPort" in byok-profiles.json.
    #>
    $startScript = Join-Path $PSScriptRoot 'start-proxy.ps1'

    if (-not (Test-Path $startScript)) {
        Write-Error "Moonshot proxy script not found at $startScript"
        exit 1
    }

    $on3002 = (Get-NetTCPConnection -LocalPort 3002 -ErrorAction SilentlyContinue).State -eq 'Listen'
    $on443  = (Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue).State -eq 'Listen'

    if (-not $on3002 -and -not $on443) {
        Write-Host "  Starting Moonshot proxy..." -ForegroundColor Yellow
        Start-Process -FilePath powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -Verb RunAs
        Start-Sleep 5
        $on3002 = (Get-NetTCPConnection -LocalPort 3002 -ErrorAction SilentlyContinue).State -eq 'Listen'
        if (-not $on3002) {
            Write-Error "Proxy failed to start"
            exit 1
        }
        Write-Host "  Proxy running" -ForegroundColor Green
    }
    else {
        Write-Host "  Proxy already running" -ForegroundColor Gray
    }
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

    $p = $config.profiles[$Name]

    # Parse --account override (consumed here, never forwarded to copilot)
    $accountParse = Remove-AccountArg -ArgList $Arguments
    $Arguments = $accountParse.Arguments
    $accountOverride = $accountParse.Account

    # Resolve account -> API-key env var for account-grouped profiles
    $resolvedAccount = Resolve-ProfileAccount -Config $config -Profile $p -AccountOverride $accountOverride
    if ($resolvedAccount) {
        $p.apiKey = '${' + $resolvedAccount.KeyEnv + '}'
    }

    # Auto-start proxy if profile has proxyPort
    $proxyPort = $p.proxyPort
    if ($proxyPort) {
        Start-MoonshotProxy
        $originalBaseUrl = $p.baseUrl
        $p.baseUrl = "https://moonshot.local/v1"
        Write-Host "  (base URL proxied: $originalBaseUrl → https://moonshot.local)" -ForegroundColor DarkYellow
    }

    # Check for reasoning-effort compatibility (flag on profile OR shared model list)
    $hasReasoningArg = ($Arguments | Where-Object { $_ -match '^--(reasoning-effort|effort)(=|$)' }).Count -gt 0
    $reasoningSupported = Test-ReasoningEffortSupported -Model $p.model -Profile $p

    if ($hasReasoningArg -and $reasoningSupported -eq $false) {
        # Strip both the flag and its value argument
        $stripped = @()
        $newArgs = @()
        $skipNext = $false
        foreach ($arg in $Arguments) {
            if ($skipNext -and -not ($arg -match '^--')) {
                $stripped += $arg; $skipNext = $false; continue
            }
            $skipNext = $false
            if ($arg -match '^--(reasoning-effort|effort)(=|$)' ) {
                if ($arg -notmatch '=') { $skipNext = $true }
                $stripped += $arg; continue
            }
            $newArgs += $arg
        }
        $Arguments = $newArgs
        Write-Host ""
        Write-Host "  ⚠ Stripped --reasoning-effort argument(s) for model '$($p.model)'" -ForegroundColor Yellow
        Write-Host "    (the API does not expose controllable reasoning-effort levels)." -ForegroundColor Yellow
        Write-Host "    Removed: $($stripped -join ' ')" -ForegroundColor DarkYellow
        Write-Host ""
    }

    Set-ProviderEnvironment -Provider $p

    # Show a brief summary
    Write-Host "Launching copilot with profile '$Name'" -ForegroundColor Cyan
    Write-Host "  Provider : $(if ($p.type) { $p.type } else { 'openai' })" -ForegroundColor Gray
    Write-Host "  Base URL : $($p.baseUrl)" -ForegroundColor Gray
    Write-Host "  Model    : $($p.model)" -ForegroundColor Gray
    if ($resolvedAccount) {
        Write-Host "  Account  : $($resolvedAccount.Name) ($($resolvedAccount.KeyEnv), via $($resolvedAccount.Source))" -ForegroundColor Gray
    }
    if ($p.wireApi) { Write-Host "  Wire API : $($p.wireApi)" -ForegroundColor Gray }
    if ($p.maxPromptTokens) { Write-Host "  Max Prompt Tokens : $($p.maxPromptTokens)" -ForegroundColor Gray }
    if ($p.maxOutputTokens) { Write-Host "  Max Output Tokens : $($p.maxOutputTokens)" -ForegroundColor Gray }
    if ($p.offline -eq $true) { Write-Host "  Offline  : true" -ForegroundColor Gray }
    if ($proxyPort) { Write-Host "  Proxy    : https://moonshot.local (top_p override)" -ForegroundColor Green }
    if ($p.PSObject.Properties.Name -contains 'reasoningEffortSupported') {
        Write-Host "  Reasoning Effort : $($p.reasoningEffortSupported)" -ForegroundColor Gray
    }
    Write-Host ""

    $copilotCmd = Get-Command copilot -ErrorAction SilentlyContinue
    if (-not $copilotCmd) {
        Write-Error "'copilot' command not found in PATH. Is Copilot CLI installed?"
        exit 1
    }

    & copilot @Arguments
}

function Invoke-ProfileSetEnv {
    param([string]$Name, [string[]]$Arguments)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error "Profile name is required for 'set-env'."
        exit 1
    }
    $config = Get-ProfileConfig
    if (-not $config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }

    $p = $config.profiles[$Name]

    # Parse --account override (consumed here, not part of the env)
    $accountParse = Remove-AccountArg -ArgList $Arguments
    $accountOverride = $accountParse.Account

    # Resolve account -> API-key env var for account-grouped profiles
    $resolvedAccount = Resolve-ProfileAccount -Config $config -Profile $p -AccountOverride $accountOverride
    if ($resolvedAccount) {
        $p.apiKey = '${' + $resolvedAccount.KeyEnv + '}'
    }

    Set-ProviderEnvironment -Provider $p

    Write-Host "Applied profile '$Name' to the current shell session." -ForegroundColor Green
    Write-Host "  COPILOT_PROVIDER_BASE_URL = $($env:COPILOT_PROVIDER_BASE_URL)" -ForegroundColor Gray
    Write-Host "  COPILOT_PROVIDER_TYPE     = $($env:COPILOT_PROVIDER_TYPE)" -ForegroundColor Gray
    Write-Host "  COPILOT_MODEL             = $($env:COPILOT_MODEL)" -ForegroundColor Gray
    if ($resolvedAccount) {
        Write-Host "  COPILOT_PROVIDER_ACCOUNT = $($resolvedAccount.Name) ($($resolvedAccount.KeyEnv), via $($resolvedAccount.Source))" -ForegroundColor Gray
    }
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
    $reasoningSupported = Test-ReasoningEffortSupported -Model $p.model -Profile $p
    Write-Host "  Reasoning Effort Supported = $reasoningSupported" -ForegroundColor Gray
}

switch ($Command) {
    'list'     { Invoke-ProfileList }
    'show'     { Invoke-ProfileShow -Name $Profile }
    'add'      { Invoke-ProfileAdd }
    'remove'   { Invoke-ProfileRemove -Name $Profile }
    'run'      { Invoke-ProfileRun -Name $Profile }
    'set-env'  { Invoke-ProfileSetEnv -Name $Profile -Arguments $Arguments }
    'accounts' { Invoke-ProfileAccounts }
    'use'      { Invoke-ProfileUse -Name $Profile }
    default    { Invoke-ProfileList }
}

