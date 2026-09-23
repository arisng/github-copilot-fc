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

.PARAMETER Interactive
    Opt-in wizard flag (alias -i). All pickers are ACCOUNT-FIRST: choose the
    scoping account (or skip), then only profiles whose 'scope' matches are
    listed; enabled:false profiles are hidden where unusable and marked
    [disabled] where they can be re-enabled or removed. Consulted ONLY when
    the target name is omitted (or for list/accounts, which map to the wizard
    entry point); never auto-triggered - a missing name without this flag
    still exits non-zero. On 'run' with an explicit profile name, the
    canonical --interactive token is re-forwarded to copilot (copilot defines
    -i/--interactive) so existing pass-through invocations keep working.

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

.EXAMPLE
    .\byok-profile.ps1 -i

    Bare -i wizard entry: pick a scoping account, then a profile belonging to
    it, then an action (Run / Show / Set-env / Enable-Disable).
#>
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('list', 'show', 'add', 'remove', 'run', 'set-env', 'accounts', 'use')]
    [string]$Command = 'list',

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Profile,

    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,

    # Opt-in wizard flag (cli-wizard-pattern). Consulted ONLY when no name is
    # given; never auto-triggered. With an explicit name on 'run', the canonical
    # --interactive token is re-forwarded to copilot (which defines
    # -i/--interactive <prompt>) so pass-through behavior is preserved.
    [Parameter(Mandatory = $false)]
    [Alias('i')]
    [switch]$Interactive
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

function Migrate-OpenCodeGoProfiles {
    <#
    .SYNOPSIS
        Auto-migrate OpenCode Go profiles to use the session-header proxy.
    .DESCRIPTION
        Detects profiles with baseUrl pointing to opencode.ai/zen/go/v1 that lack
        the opencodeSessionHeader flag. Adds the flag and rewrites baseUrl to
        opencode-go.local/v1 so the proxy can inject the required header.
    #>
    param($Config)
    $migrated = @()
    foreach ($name in @($Config.profiles.Keys)) {
        $p = $Config.profiles[$name]
        if ($p.baseUrl -match 'https://opencode\.ai/zen/go/v1' -and $p.opencodeSessionHeader -ne $true) {
            $p.opencodeSessionHeader = $true
            $p.baseUrl = "https://opencode-go.local/v1"
            $migrated += $name
        }
    }
    if ($migrated.Count -gt 0) {
        Save-ProfileConfig -Config $Config
        Write-Host "  Migrated $($migrated.Count) OpenCode Go profile(s) to use session-header proxy:" -ForegroundColor Yellow
        foreach ($name in $migrated) {
            Write-Host "    - $name" -ForegroundColor Yellow
        }
        Write-Host "    (baseUrl rewritten to https://opencode-go.local/v1, opencodeSessionHeader: true added)" -ForegroundColor DarkYellow
        Write-Host "    Run .\scripts\setup-opencode-proxy-dns.ps1 once (admin) to set up DNS + cert." -ForegroundColor DarkYellow
        Write-Host ""
    }
    return $Config
}

function Migrate-AccountNames {
    <#
    .SYNOPSIS
        One-time rename of account registry keys to the uniform
        <scope>-<variant> convention (account key starts with its scope).
    .DESCRIPTION
        Rewrites accounts keys, activeAccount, normalizes the four labels
        during the rename, and defensively rewrites any profile 'account' pin.
        Prints a notice; a second read is a no-op.
    #>
    param($Config)
    $renameMap = @{
        'opencode-home' = 'opencode-go-home'
        'opencode-work' = 'opencode-go-work'
        'opencode-zen'  = 'opencode-zen-home'
        'commandcode'   = 'commandcode-goat'
    }
    $labelMap = @{
        'opencode-go-home'  = 'OpenCode Go (Home)'
        'opencode-go-work'  = 'OpenCode Go (Work)'
        'opencode-zen-home' = 'OpenCode Zen (Home)'
        'commandcode-goat'  = 'Command Code GOAT'
    }
    $renamed = @()
    if ($Config.accounts) {
        foreach ($old in @($Config.accounts.Keys)) {
            if (-not $renameMap.ContainsKey($old)) { continue }
            $new = $renameMap[$old]
            if (-not $Config.accounts.ContainsKey($new)) {
                $Config.accounts[$new] = $Config.accounts[$old]
                if ($labelMap.ContainsKey($new)) { $Config.accounts[$new].label = $labelMap[$new] }
            }
            $Config.accounts.Remove($old)
            $renamed += "$old -> $new"
        }
    }
    if ($Config.activeAccount -and $renameMap.ContainsKey($Config.activeAccount)) {
        $Config.activeAccount = $renameMap[$Config.activeAccount]
    }
    if ($Config.profiles) {
        foreach ($name in @($Config.profiles.Keys)) {
            $p = $Config.profiles[$name]
            if ($p.account -and $renameMap.ContainsKey($p.account)) {
                $p.account = $renameMap[$p.account]
                $renamed += "profile '$name' account pin -> $($p.account)"
            }
        }
    }
    if ($renamed.Count -gt 0) {
        Save-ProfileConfig -Config $Config
        Write-Host "  Renamed BYOK account(s):" -ForegroundColor Yellow
        foreach ($r in $renamed) { Write-Host "    - $r" -ForegroundColor Yellow }
        Write-Host "    (old keys are invalid; update scripts using them)" -ForegroundColor DarkYellow
        Write-Host ""
    }
    return $Config
}

function Get-ScopeForAccount {
    param([System.Collections.IDictionary]$Account)
    if ($Account.scope) { return $Account.scope }
    $ke = "$($Account.keyEnv)"
    if ($ke -match '^COMMANDCODE_') { return 'commandcode' }
    if ($ke -match '^OPENCODE_ZEN_') { return 'opencode-zen' }
    if ($ke -match '^OPENCODE_API_KEY_') { return 'opencode-go' }
    if ($ke -match '^DPROCESS_') { return 'dprocess' }
    if ($ke -match '^(.+)_API_KEY$') { return ($Matches[1] -replace '_', '-').ToLower() }
    return $null
}

function Get-ScopeForProfile {
    param([System.Collections.IDictionary]$Profile)
    if ($Profile.scope) { return $Profile.scope }
    $b = "$($Profile.baseUrl)"
    if ($b -match 'commandcode\.ai') { return 'commandcode' }
    if ($b -match 'opencode-go\.local') { return 'opencode-go' }
    if ($b -match 'opencode\.ai/zen') { return 'opencode-zen' }
    if ($b -match 'openrouter\.ai') { return 'openrouter' }
    if ("$($Profile.apiKey)" -match '^\$\{(.+?)\}') {
        $ke = $Matches[1]
        if ($ke -match '^COMMANDCODE_') { return 'commandcode' }
        if ($ke -match '^OPENCODE_ZEN_') { return 'opencode-zen' }
        if ($ke -match '^OPENCODE_API_KEY_') { return 'opencode-go' }
        if ($ke -match '^DPROCESS_') { return 'dprocess' }
        if ($ke -match '^(.+)_API_KEY$') { return ($Matches[1] -replace '_', '-').ToLower() }
    }
    return $null
}

function Migrate-WizardScope {
    <#
    .SYNOPSIS
        One-time backfill of the optional 'scope' field on accounts and
        profiles (drives account-first wizard filtering).
    .DESCRIPTION
        Writes only fields that are missing; a second read is a no-op.
        Profiles/accounts whose scope cannot be inferred stay without one and
        are reachable only via the wizard's skip-scoping escape.
    #>
    param($Config)
    $changed = $false
    if ($Config.accounts) {
        foreach ($n in @($Config.accounts.Keys)) {
            $a = $Config.accounts[$n]
            if (-not $a.scope) {
                $s = Get-ScopeForAccount -Account $a
                if ($s) { $a.scope = $s; $changed = $true }
            }
        }
    }
    if ($Config.profiles) {
        foreach ($n in @($Config.profiles.Keys)) {
            $p = $Config.profiles[$n]
            if (-not $p.scope) {
                $s = Get-ScopeForProfile -Profile $p
                if ($s) { $p.scope = $s; $changed = $true }
            }
        }
    }
    if ($changed) {
        Save-ProfileConfig -Config $Config
        Write-Host "  Backfilled missing 'scope' field(s) for the account-first wizard." -ForegroundColor DarkYellow
        Write-Host ""
    }
    return $Config
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

    # Auto-migrate on first access (order matters: proxy rewrite, then account
    # rename, then scope backfill against the final keys).
    $raw = Migrate-OpenCodeGoProfiles -Config $raw
    $raw = Migrate-AccountNames -Config $raw
    $raw = Migrate-WizardScope -Config $raw

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

# --- cli-wizard-pattern helpers ---------------------------------------------
# Guided-input primitives shared by the pickers (-i) and the 'add' interview.
# Rules (skills/cli-wizard-pattern): numbered menus over free text, validation
# re-prompt loops, q quits cleanly (caller returns, never a non-zero exit),
# empty option sets fail with guidance before a menu is ever drawn.

function Read-MenuChoice {
    <#
    .SYNOPSIS
        Numbered selection menu with validation loop, marked default, and quit token.
    .OUTPUTS
        The chosen option's Value (or the bare string for plain-string options).
        Returns $null when the user quits (q/Q) — callers treat $null as a clean
        cancel with no side effects. Blank input returns -Default when provided
        and re-prompts otherwise.
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [object[]]$Options,   # hashtables @{Label;Value} or plain strings
        [object]$Default,
        [switch]$AllowQuit
    )
    $opts = @($Options)
    if ($opts.Count -eq 0) {
        # Defensive: callers must pre-check emptiness so this stays unreachable.
        Write-Error "No options available for '$Prompt'."
        return $null
    }
    $hasDefault = $PSBoundParameters.ContainsKey('Default')
    for (;;) {
        for ($idx = 0; $idx -lt $opts.Count; $idx++) {
            $o = $opts[$idx]
            $label = if ($o -is [hashtable] -and $o.ContainsKey('Label')) { [string]$o.Label } else { [string]$o }
            Write-Host ("  {0}) {1}" -f ($idx + 1), $label)
        }
        $suffix = if ($hasDefault -and $null -ne $Default -and "$Default" -ne '') { " [$Default]" } else { '' }
        $quitHint = if ($AllowQuit) { ' (q to quit)' } else { '' }
        $raw = Read-Host ("{0}{1}{2}" -f $Prompt, $suffix, $quitHint)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            if ($hasDefault) { return $Default }
            continue
        }
        if ($AllowQuit -and $raw -in @('q', 'Q')) { return $null }
        $num = 0
        if ([int]::TryParse($raw, [ref]$num) -and $num -ge 1 -and $num -le $opts.Count) {
            $choice = $opts[$num - 1]
            if ($choice -is [hashtable] -and $choice.ContainsKey('Value')) { return $choice.Value }
            return $choice
        }
        Write-Host ("  Invalid selection '{0}'. Enter a number 1-{1}." -f $raw, $opts.Count) -ForegroundColor Yellow
    }
}

function Read-YesNo {
    <#
    .SYNOPSIS
        Numbered 1) Yes / 2) No prompt with a marked default and re-prompt loop.
        y/n are also accepted for muscle memory. Never trusts a single read.
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [bool]$Default = $false
    )
    for (;;) {
        Write-Host '  1) Yes   2) No'
        $hint = if ($Default) { ' [1]' } else { ' [2]' }
        $raw = Read-Host ("{0}{1}" -f $Prompt, $hint)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        switch ($raw) {
            '1' { return $true }
            '2' { return $false }
            { $_ -in @('y', 'Y', 'yes', 'YES') } { return $true }
            { $_ -in @('n', 'N', 'no', 'NO') } { return $false }
        }
        Write-Host '  Enter 1 or 2 (y/n also accepted).' -ForegroundColor Yellow
    }
}

function Read-RequiredText {
    <#
    .SYNOPSIS
        Non-empty text prompt with a re-prompt loop for values that cannot be
        enumerated (profile name, base URL, model ID). Blank input accepts
        -Default when one is documented; otherwise it re-prompts.
        With -AllowQuit, 'q' returns $null — callers must treat that as a
        clean cancel (callers can distinguish: valid values are never $null).
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Default,
        [switch]$AllowQuit
    )
    $hasDefault = -not [string]::IsNullOrWhiteSpace($Default)
    for (;;) {
        $suffix = if ($hasDefault) { " [$Default]" } else { '' }
        $quitHint = if ($AllowQuit) { ' (q to quit)' } else { '' }
        $raw = Read-Host ("{0}{1}{2}" -f $Prompt, $suffix, $quitHint)
        if ($AllowQuit -and -not [string]::IsNullOrWhiteSpace($raw) -and $raw -in @('q', 'Q')) { return $null }
        if (-not [string]::IsNullOrWhiteSpace($raw)) { return $raw }
        if ($hasDefault) { return $Default }
        Write-Host '  A value is required.' -ForegroundColor Yellow
    }
}

function Read-OptionalInt {
    <#
    .SYNOPSIS
        Positive-integer prompt with a try/parse re-prompt loop (never a raw
        [int] cast crash). Returns @{ Quit; Value }: Quit=$true when the user
        pressed q (with -AllowQuit), else Value = the integer or $null (skip
        when blank and no -Default is given). The object return keeps "blank =
        skip" distinguishable from "q = cancel".
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        $Default,
        [switch]$AllowQuit
    )
    $hasDefault = $null -ne $Default
    for (;;) {
        $suffix = if ($hasDefault) { " [$Default]" } else { '' }
        $quitHint = if ($AllowQuit) { ' (q to quit)' } else { '' }
        $raw = Read-Host ("{0}{1}{2}" -f $Prompt, $suffix, $quitHint)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            if ($hasDefault) { return @{ Quit = $false; Value = [int]$Default } }
            return @{ Quit = $false; Value = $null }
        }
        if ($AllowQuit -and $raw -in @('q', 'Q')) { return @{ Quit = $true; Value = $null } }
        $num = 0
        if ([int]::TryParse($raw, [ref]$num) -and $num -gt 0) { return @{ Quit = $false; Value = $num } }
        Write-Host '  Enter a positive whole number.' -ForegroundColor Yellow
    }
}

function Show-ConfirmationSummary {
    <#
    .SYNOPSIS
        Prints a key/value summary of every resolved value and gates on yes/no.
        API keys must be passed as env-var placeholders only — never raw secrets.
        Returns $true only on explicit confirmation; declining is a clean cancel.
    #>
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary]$Rows
    )
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    foreach ($key in $Rows.Keys) {
        Write-Host ("  {0,-24}: {1}" -f $key, $Rows[$key]) -ForegroundColor Gray
    }
    Write-Host ''
    return (Read-YesNo -Prompt 'Proceed?' -Default $false)
}

# Models whose API does not expose controllable reasoning-effort levels. This is the
# single source of truth used by the wizard (add), run, set-env, and show. It mirrors
# references/shared/reasoning-effort-lookup.md; keep both in sync.
function Get-NoReasoningEffortModels {
    return @(
        'kimi-k2.7-code', 'kimi-k2.6', 'kimi-k2.5',
        'glm-5.2', 'glm-5.1', 'glm-5',
        'mimo-v2.5', 'mimo-v2.5-pro', 'mimo-v2-pro', 'mimo-v2-omni',
        # MiMo V2.6: Xiaomi API exposes only a binary thinking toggle (mimo.mi.com docs).
        # Bare form (OpenCode Go) + provider/model form (Command Code) — match is exact.
        'mimo-v2.6-flash', 'xiaomi/mimo-v2.6-flash',
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
    # Scope guard: an account only serves a profile when both scopes agree
    # (e.g. an OpenCode Go account must never key an OpenCode Zen profile).
    $acctScope = $Config.accounts[$accountName].scope
    $profScope = $Profile.scope
    if ($acctScope -and $profScope -and "$acctScope" -ne "$profScope") {
        Write-Warning "Account '$accountName' has scope '$acctScope' but profile scope is '$profScope' (via $source). Falling back to profile apiKey."
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
        $disabled = if ($p.enabled -eq $false) { ' [disabled]' } else { '' }
        $accountInfo = if ($p.accountGroup) { " [accountGroup: $($p.accountGroup)]" } else { '' }
        Write-Host "$name" -ForegroundColor Green -NoNewline
        Write-Host " -> $type | $($p.model) | $($p.baseUrl)$offline$accountInfo$disabled" -ForegroundColor Gray
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
        Write-Host "No accounts defined. Add an 'accounts' section to $profilePath (see references/shared/copilot-cli-accounts.md)." -ForegroundColor Yellow
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

function Get-ScopedProfileNames {
    <#
    .SYNOPSIS
        Profile names visible to the wizard: scope-filtered, enabled-only
        (unless -IncludeDisabled), sorted. Profiles without a scope are only
        reachable when no scope filter is active (the skip-scoping escape).
    #>
    param(
        [Parameter(Mandatory)] [hashtable]$Config,
        [string]$Scope,
        [switch]$IncludeDisabled
    )
    $out = @(foreach ($n in @($Config.profiles.Keys)) {
        $p = $Config.profiles[$n]
        if (-not $IncludeDisabled -and $p.enabled -eq $false) { continue }
        if ($Scope) {
            $ps = if ($p.scope) { "$($p.scope)" } else { '' }
            if ($ps -ne $Scope) { continue }
        }
        $n
    })
    return @($out | Sort-Object)
}

function Invoke-InteractiveSelect {
    <#
    .SYNOPSIS
        Opt-in (-i) wizard: account-first target resolution when no name was given.
    .DESCRIPTION
        Step 1: pick the scoping account (or skip); an explicit --account skips
        the menu and provides the scope instead. Step 2: pick from the profiles
        belonging to that account (profile.scope == account.scope), applying
        enabled-visibility per command (-IncludeDisabled for list/accounts/
        remove so disabled profiles stay reachable for re-enable/delete).
        An empty scope result prints guidance and re-loops to the account menu;
        q at any menu returns Cancelled=$true with no side effects.
        Returns @{ Profile; Account; Cancelled }.
    #>
    param(
        [Parameter(Mandatory)] [string]$CommandName,
        [Parameter(Mandatory)] [hashtable]$Config,
        [string[]]$ArgumentList = @(),
        [switch]$IncludeDisabled
    )

    # 'use' targets accounts (no scoping step; labels carry scope tags).
    if ($CommandName -eq 'use') {
        $acctNames = @($Config.accounts.Keys | Sort-Object)
        if ($acctNames.Count -eq 0) {
            Write-Error "No accounts defined in $profilePath. Add an 'accounts' section first (see references/shared/copilot-cli-accounts.md)."
            exit 1
        }
        $options = @(foreach ($n in $acctNames) {
            $a = $Config.accounts[$n]
            $label = if ($a.label) { $a.label } else { '(no label)' }
            $scopeTag = if ($a.scope) { " [scope: $($a.scope)]" } else { '' }
            $marker = if ($n -eq $Config.activeAccount) { '  [active]' } else { '' }
            @{ Label = "$n | $label$scopeTag$marker"; Value = $n }
        })
        $picked = Read-MenuChoice -Prompt 'Select account' -Options $options -AllowQuit
        if ($null -eq $picked) { return @{ Profile = $null; Account = $null; Cancelled = $true } }
        return @{ Profile = $null; Account = $picked; Cancelled = $false }
    }

    if (-not $Config.profiles -or $Config.profiles.Count -eq 0) {
        Write-Error "No profiles defined in $profilePath. Run 'byok-profile.ps1 add' to create one."
        exit 1
    }

    # ---- Step 0: resolve the scoping account ----
    $explicit = Remove-AccountArg -ArgList $ArgumentList
    $scopeAccount = $null   # account name feeding --account for grouped profiles
    $scopeValue = $null     # scope filter ($null = all profiles)
    $acctNames = @()
    if ($Config.accounts) { $acctNames = @($Config.accounts.Keys | Sort-Object) }

    $names = @()
    if ($explicit.Account) {
        # Explicit --account wins: no account menu; it provides the scope.
        if ($Config.accounts -and $Config.accounts.ContainsKey($explicit.Account)) {
            $scopeAccount = $explicit.Account
            $scopeValue = $Config.accounts[$explicit.Account].scope
        }
        $names = Get-ScopedProfileNames -Config $Config -Scope $scopeValue -IncludeDisabled:$IncludeDisabled
        if ($names.Count -eq 0) {
            $what = if ($scopeValue) { "profiles with scope '$scopeValue' (from --account $scopeAccount)" } else { 'visible profiles' }
            Write-Error "No $what in $profilePath."
            exit 1
        }
    }
    elseif ($acctNames.Count -gt 0) {
        $acctOptions = @(foreach ($n in $acctNames) {
            $a = $Config.accounts[$n]
            $label = if ($a.label) { $a.label } else { '(no label)' }
            $scopeTag = if ($a.scope) { " [scope: $($a.scope)]" } else { ' [no scope]' }
            $marker = if ($n -eq $Config.activeAccount) { '  [active]' } else { '' }
            @{ Label = "$n  |  $label$scopeTag$marker"; Value = $n }
        })
        $acctOptions += @{ Label = '(all profiles - skip scoping)'; Value = '' }
        for (;;) {
            $acctPick = Read-MenuChoice -Prompt 'Select account (scope filter)' -Options $acctOptions -Default '' -AllowQuit
            if ($null -eq $acctPick) { return @{ Profile = $null; Account = $null; Cancelled = $true } }
            if ("$acctPick" -eq '') {
                $scopeAccount = $null
                $scopeValue = $null
            }
            else {
                $scopeAccount = "$acctPick"
                $scopeValue = $Config.accounts["$acctPick"].scope
            }
            $names = Get-ScopedProfileNames -Config $Config -Scope $scopeValue -IncludeDisabled:$IncludeDisabled
            if ($names.Count -gt 0) { break }
            $what = if ($scopeValue) { "profiles with scope '$scopeValue'" } else { 'visible profiles' }
            Write-Host "  No $what. Pick another account or skip scoping." -ForegroundColor Yellow
        }
    }
    else {
        # No accounts registry at all: flat list.
        $names = Get-ScopedProfileNames -Config $Config -Scope $null -IncludeDisabled:$IncludeDisabled
        if ($names.Count -eq 0) {
            $why = if (-not $IncludeDisabled) { 'enabled ' } else { '' }
            Write-Error "No $why`profiles defined in $profilePath. Run 'byok-profile.ps1 add' to create one."
            exit 1
        }
    }

    # ---- Step 2: profile menu over the scoped/visible names ----
    $options = @(foreach ($n in $names) {
        $p = $Config.profiles[$n]
        $type = if ($p.type) { $p.type } else { 'openai' }
        $group = if ($p.accountGroup) { "  [accountGroup: $($p.accountGroup)]" } else { '' }
        $dis = if ($p.enabled -eq $false) { '  [disabled]' } else { '' }
        @{ Label = "$n  ($type | $($p.model))$group$dis"; Value = $n }
    })
    $picked = Read-MenuChoice -Prompt 'Select profile' -Options $options -AllowQuit
    if ($null -eq $picked) { return @{ Profile = $null; Account = $null; Cancelled = $true } }

    # Chosen scope account flows into run/set-env as --account (grouped only;
    # non-grouped profiles already carry the matching keyEnv placeholder).
    # Explicit --account keeps precedence: it stays in $Arguments untouched.
    $account = $null
    if ($CommandName -in @('run', 'set-env') -and -not $explicit.Account -and $scopeAccount) {
        $isGrouped = [bool]$Config.profiles[$picked].accountGroup
        if ($isGrouped) { $account = $scopeAccount }
    }

    return @{ Profile = $picked; Account = $account; Cancelled = $false }
}

function Invoke-ProfileToggleEnabled {
    <#
    .SYNOPSIS
        Confirmed on/off toggle for a profile's 'enabled' flag (kept in JSON).
    .DESCRIPTION
        Prints a confirmation summary first (confirm before mutating); a
        declined confirmation is a clean cancel ($false, nothing written).
        Absent flag = enabled; both directions write an explicit boolean.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Config
    )
    if (-not $Config.profiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' not found."
        exit 1
    }
    $p = $Config.profiles[$Name]
    $currently = -not ($p.enabled -eq $false)
    $newState = -not $currently
    $rows = [ordered]@{
        'Profile'       = $Name
        'Model'         = "$($p.model)"
        'Current state' = $(if ($currently) { 'enabled' } else { 'disabled' })
        'New state'     = $(if ($newState) { 'enabled' } else { 'disabled' })
    }
    if (-not (Show-ConfirmationSummary -Title "$(if ($newState) { 'Enable' } else { 'Disable' }) profile '$Name'?" -Rows $rows)) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return $false
    }
    $p.enabled = $newState
    Save-ProfileConfig -Config $Config
    Write-Host "Profile '$Name' is now $(if ($newState) { 'enabled' } else { 'disabled' })." -ForegroundColor Green
    return $true
}

function Invoke-ProfileAdd {
    $config = Get-ProfileConfig

    Write-Host "Create a new BYOK provider profile" -ForegroundColor Cyan
    $name = Read-RequiredText -Prompt "Profile name (e.g., ollama, azure-prod, kimi)" -AllowQuit
    if ($null -eq $name) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    if ($config.profiles.ContainsKey($name)) {
        if (-not (Read-YesNo -Prompt "Profile '$name' already exists. Overwrite?" -Default $false)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Choose a preset (or select Custom to enter values manually):" -ForegroundColor Cyan
    $preset = Read-MenuChoice -Prompt "Preset" -Default '8' -AllowQuit -Options @(
        @{ Label = 'OpenAI'; Value = '1' }
        @{ Label = 'Azure OpenAI'; Value = '2' }
        @{ Label = 'Anthropic'; Value = '3' }
        @{ Label = 'Ollama (local)'; Value = '4' }
        @{ Label = 'Kimi AI / Moonshot'; Value = '5' }
        @{ Label = 'OpenCode Go'; Value = '6' }
        @{ Label = 'Command Code'; Value = '7' }
        @{ Label = 'Custom'; Value = '8' }
    )
    if ($null -eq $preset) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

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
            $baseUrl = Read-RequiredText -Prompt "Azure base URL (e.g., https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT)" -AllowQuit
            if ($null -eq $baseUrl) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            $model = Read-RequiredText -Prompt "Azure deployment name" -AllowQuit
            if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
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

            $region = Read-MenuChoice -Prompt "Region" -Default '1' -AllowQuit -Options @(
                @{ Label = 'Global (api.moonshot.ai/v1) - recommended'; Value = '1' }
                @{ Label = 'China (api.moonshot.cn/v1)'; Value = '2' }
            )
            if ($null -eq $region) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            if ($region -eq '2') {
                $baseUrl = 'https://api.moonshot.cn/v1'
            }
            else {
                $baseUrl = 'https://api.moonshot.ai/v1'
            }

            $model = Read-MenuChoice -Prompt "Model" -Default 'kimi-k2.6' -AllowQuit -Options @(
                @{ Label = 'Kimi K2.7 Code (coding-optimized, thinking always on)'; Value = 'kimi-k2.7-code' }
                @{ Label = 'Kimi K2.6 (latest flagship, multimodal)'; Value = 'kimi-k2.6' }
                @{ Label = 'Kimi K2.5 (multimodal, lower cost)'; Value = 'kimi-k2.5' }
            )
            if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
        }
        '6' {
            $type = 'openai'
            $baseUrl = 'https://opencode.ai/zen/go/v1'
            $defaultApiKeyPrompt = '${OPENCODE_API_KEY_HOME}'

            Write-Host "Select OpenCode Go model category:" -ForegroundColor Cyan
            $modelCategory = Read-MenuChoice -Prompt "Category" -Default '1' -AllowQuit -Options @(
                @{ Label = 'OpenAI-compatible (DeepSeek, GLM, Kimi, MiMo)'; Value = '1' }
                @{ Label = 'Anthropic-compatible (MiniMax, Qwen)'; Value = '2' }
            )
            if ($null -eq $modelCategory) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            if ($modelCategory -eq '1') {
                $type = 'openai'
                $model = Read-MenuChoice -Prompt "Model" -Default 'deepseek-v4-flash' -AllowQuit -Options @(
                    @{ Label = 'DeepSeek V4 Flash (cheapest, recommended)'; Value = 'deepseek-v4-flash' }
                    @{ Label = 'DeepSeek V4 Pro'; Value = 'deepseek-v4-pro' }
                    @{ Label = 'Kimi K2.7 Code'; Value = 'kimi-k2.7-code' }
                    @{ Label = 'Kimi K2.6'; Value = 'kimi-k2.6' }
                    @{ Label = 'GLM-5.2'; Value = 'glm-5.2' }
                    @{ Label = 'GLM-5.1'; Value = 'glm-5.1' }
                    @{ Label = 'GLM-5'; Value = 'glm-5' }
                    @{ Label = 'MiMo-V2.5'; Value = 'mimo-v2.5' }
                    @{ Label = 'MiMo-V2.5-Pro'; Value = 'mimo-v2.5-pro' }
                    @{ Label = 'Other (type model ID manually)'; Value = '__other__' }
                )
                if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
                if ($model -eq '__other__') {
                    $model = Read-RequiredText -Prompt "Enter model ID" -AllowQuit
                    if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
                }
            }
            else {
                $type = 'anthropic'
                $model = Read-MenuChoice -Prompt "Model" -Default 'qwen3.7-plus' -AllowQuit -Options @(
                    @{ Label = 'Qwen3.7 Plus (recommended)'; Value = 'qwen3.7-plus' }
                    @{ Label = 'Qwen3.7 Max'; Value = 'qwen3.7-max' }
                    @{ Label = 'Qwen3.6 Plus'; Value = 'qwen3.6-plus' }
                    @{ Label = 'MiniMax M3'; Value = 'minimax-m3' }
                    @{ Label = 'MiniMax M2.7'; Value = 'minimax-m2.7' }
                )
                if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            }
            $defaultMaxPromptTokens = 200000
        }
        '7' {
            $type = 'openai'
            $baseUrl = 'https://api.commandcode.ai/provider/v1'
            $defaultApiKeyPrompt = '${COMMANDCODE_API_KEY}'
            $defaultMaxPromptTokens = 1000000
            $defaultMaxOutputTokens = 32768

            Write-Host "Select Command Code model:" -ForegroundColor Cyan
            $model = Read-MenuChoice -Prompt "Model" -Default 'deepseek/deepseek-v4-flash' -AllowQuit -Options @(
                @{ Label = 'DeepSeek V4 Flash (cheapest paid, recommended)'; Value = 'deepseek/deepseek-v4-flash' }
                @{ Label = 'DeepSeek V4.1 Flash'; Value = 'deepseek/deepseek-v4.1-flash' }
                @{ Label = 'DeepSeek V4 Pro'; Value = 'deepseek/deepseek-v4-pro' }
                @{ Label = 'GPT-5.6 Luna'; Value = 'gpt-5.6-luna' }
                @{ Label = 'MiMo V2.6 Flash (grounded: 872K prompt / 128K output)'; Value = 'xiaomi/mimo-v2.6-flash' }
                @{ Label = 'MiMo V2.5'; Value = 'xiaomi/mimo-v2.5' }
                @{ Label = 'MiMo V2.5 Pro'; Value = 'xiaomi/mimo-v2.5-pro' }
                @{ Label = 'Muse Spark 1.3 Contributor'; Value = 'meta/muse-spark-1.3-contributor' }
                @{ Label = 'Ling 3.0 Flash Sante (free)'; Value = 'inclusionai/ling-3.0-flash-sante:free' }
                @{ Label = 'Laguna S 2.1 (free)'; Value = 'poolside/laguna-s-2.1-free' }
                @{ Label = 'LongCat 2.0 (free)'; Value = 'meituan/longcat-2.0:free' }
                @{ Label = 'Other (type model ID manually)'; Value = '__other__' }
            )
            if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            if ($model -eq '__other__') {
                $model = Read-RequiredText -Prompt "Enter model ID (provider/model-name format)" -AllowQuit
                if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
            }
            # Grounded by Xiaomi MiMo docs (mimo.mi.com): 1M context, 128K max output.
            if ($model -eq 'xiaomi/mimo-v2.6-flash') {
                $defaultMaxPromptTokens = 872000
                $defaultMaxOutputTokens = 128000
            }
        }
        default {
            $type = Read-MenuChoice -Prompt "Provider type" -Default 'openai' -AllowQuit -Options @(
                @{ Label = 'openai (OpenAI-compatible default)'; Value = 'openai' }
                @{ Label = 'azure (Azure OpenAI)'; Value = 'azure' }
                @{ Label = 'anthropic'; Value = 'anthropic' }
            )
            if ($null -eq $type) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
        }
    }

    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        $baseUrl = Read-RequiredText -Prompt "Base URL (e.g., http://localhost:11434 or https://api.openai.com/v1)" -AllowQuit
        if ($null -eq $baseUrl) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    }

    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = Read-RequiredText -Prompt "Model identifier (e.g., llama3.2, gpt-4o, claude-opus-4-5)" -AllowQuit
        if ($null -eq $model) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    }

    if ($defaultApiKeyPrompt) {
        $apiKey = Read-Host "API key [${defaultApiKeyPrompt}]"
        if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $defaultApiKeyPrompt }
    }
    else {
        $apiKey = Read-Host "API key (leave blank for none; use `${ENV_VAR}` syntax to reference an environment variable)"
    }

    $maxPromptRes = Read-OptionalInt -Prompt "Max prompt tokens (blank to skip)" -Default $defaultMaxPromptTokens -AllowQuit
    if ($maxPromptRes.Quit) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    $maxOutputRes = Read-OptionalInt -Prompt "Max output tokens (blank to skip)" -Default $defaultMaxOutputTokens -AllowQuit
    if ($maxOutputRes.Quit) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    $maxPromptTokens = $maxPromptRes.Value
    $maxOutputTokens = $maxOutputRes.Value
    $offline = Read-YesNo -Prompt "Offline mode?" -Default $false

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

    # Stamp the wizard scope at creation time (same inference as migration).
    $entryScope = Get-ScopeForProfile -Profile $profileEntry
    if ($entryScope) { $profileEntry.scope = $entryScope }

    if ($supportsReasoningEffort -eq $false) {
        Write-Host "  Note: '$model' does not support --reasoning-effort. The profile has 'reasoningEffortSupported: false'." -ForegroundColor DarkYellow
    }

    if ($preset -eq '6') {
        $profileEntry.accountGroup = 'opencode'
        Write-Host "  Note: accountGroup 'opencode' set. Select the account with 'use <account>' or 'run <profile> --account <account>'." -ForegroundColor DarkYellow
    }

    # Final confirmation gate (cli-wizard-pattern: confirm before mutating).
    $apiKeyDisplay = if (-not $apiKey) { '(none)' }
                     elseif ($apiKey -match '^\$\{.+\}$') { $apiKey }
                     else { '(set - hidden)' }
    $summaryRows = [ordered]@{
        'Profile name'       = $name
        'Provider type'      = $type
        'Base URL'           = $baseUrl
        'Model'              = $model
        'API key'            = $apiKeyDisplay
        'Max prompt tokens'  = if ($maxPromptTokens) { "$maxPromptTokens" } else { '(not set)' }
        'Max output tokens'  = if ($maxOutputTokens) { "$maxOutputTokens" } else { '(not set)' }
        'Offline'            = "$offline"
        'Reasoning effort'   = if ($supportsReasoningEffort) { 'supported' } else { 'not supported (reasoningEffortSupported: false)' }
        'Account group'      = if ($preset -eq '6') { 'opencode' } else { '(none)' }
    }
    if (-not (Show-ConfirmationSummary -Title "Create profile '$name'?" -Rows $summaryRows)) {
        Write-Host "Cancelled. Nothing was saved." -ForegroundColor Yellow
        return
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
        Start-Process -FilePath pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -Verb RunAs
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

function Start-OpenCodeGoProxy {
    <#
    .SYNOPSIS
        Auto-start the OpenCode Go session-header proxy if not already running.
    .DESCRIPTION
        Checks ports 3001 and 443. If neither is listening, starts start-opencode-proxy.ps1 elevated.
        Profiles with "opencodeSessionHeader": true need this proxy.
    #>
    $startScript = Join-Path $PSScriptRoot 'start-opencode-proxy.ps1'

    if (-not (Test-Path $startScript)) {
        Write-Error "OpenCode Go proxy script not found at $startScript"
        exit 1
    }

    $on3001 = (Get-NetTCPConnection -LocalPort 3001 -ErrorAction SilentlyContinue).State -eq 'Listen'
    $on443  = (Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue).State -eq 'Listen'

    if (-not $on3001 -and -not $on443) {
        Write-Host "  Starting OpenCode Go proxy..." -ForegroundColor Yellow
        Start-Process -FilePath pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -Verb RunAs
        Start-Sleep 5
        $on3001 = (Get-NetTCPConnection -LocalPort 3001 -ErrorAction SilentlyContinue).State -eq 'Listen'
        if (-not $on3001) {
            Write-Error "OpenCode Go proxy failed to start"
            exit 1
        }
        Write-Host "  OpenCode Go proxy running" -ForegroundColor Green
    }
    else {
        Write-Host "  OpenCode Go proxy already running" -ForegroundColor Gray
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
    if ($p.enabled -eq $false) {
        Write-Error "Profile '$Name' is disabled. Re-enable it via 'byok-profile.ps1 -i' (Enable-Disable action) or set enabled: true in $profilePath."
        exit 1
    }

    # Parse --account override (consumed here, never forwarded to copilot)
    $accountParse = Remove-AccountArg -ArgList $Arguments
    $Arguments = $accountParse.Arguments
    $accountOverride = $accountParse.Account

    # Resolve account -> API-key env var for account-grouped profiles
    $resolvedAccount = Resolve-ProfileAccount -Config $config -Profile $p -AccountOverride $accountOverride
    if ($resolvedAccount) {
        $p.apiKey = '${' + $resolvedAccount.KeyEnv + '}'
    }

    # Auto-start OpenCode Go proxy if profile needs session header injection
    if ($p.opencodeSessionHeader -eq $true) {
        Start-OpenCodeGoProxy
        $originalBaseUrl = $p.baseUrl
        $p.baseUrl = "https://opencode-go.local/v1"
        Write-Host "  (base URL proxied: $originalBaseUrl → https://opencode-go.local/v1 [x-opencode-session injected])" -ForegroundColor DarkYellow
    }

    # Auto-start proxy if profile has proxyPort (Moonshot top_p fix)
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
    if ($p.opencodeSessionHeader -eq $true) { Write-Host "  Proxy    : https://opencode-go.local (x-opencode-session injected)" -ForegroundColor Green }
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
    if ($p.enabled -eq $false) {
        Write-Error "Profile '$Name' is disabled. Re-enable it via 'byok-profile.ps1 -i' (Enable-Disable action) or set enabled: true in $profilePath."
        exit 1
    }

    # Parse --account override (consumed here, not part of the env)
    $accountParse = Remove-AccountArg -ArgList $Arguments
    $accountOverride = $accountParse.Account

    # Resolve account -> API-key env var for account-grouped profiles
    $resolvedAccount = Resolve-ProfileAccount -Config $config -Profile $p -AccountOverride $accountOverride
    if ($resolvedAccount) {
        $p.apiKey = '${' + $resolvedAccount.KeyEnv + '}'
    }

    # Auto-start OpenCode Go proxy if profile needs session header injection
    if ($p.opencodeSessionHeader -eq $true) {
        Start-OpenCodeGoProxy
        $p.baseUrl = "https://opencode-go.local/v1"
    }

    # Auto-start proxy if profile has proxyPort (Moonshot top_p fix)
    if ($p.proxyPort) {
        Start-MoonshotProxy
        $p.baseUrl = "https://moonshot.local/v1"
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

# --- Opt-in wizard dispatch (cli-wizard-pattern) -----------------------------
# Rule 1: never auto-detected. Without -Interactive, a missing name fails fast
# exactly as before. With -Interactive, gather via pickers, then fall through to
# the unchanged non-interactive functions (one execution path).
# C1 collision guard: with an explicit name, -Interactive/-i/--interactive is
# treated as pass-through intent on 'run' — copilot defines -i/--interactive
# <prompt>, so the canonical token is re-forwarded (flag-first order restored).
if ($Interactive -and -not [string]::IsNullOrWhiteSpace($Profile)) {
    if ($Command -eq 'run') {
        $fwd = @(); if ($Arguments) { $fwd = @($Arguments) }
        $guardConfig = Get-ProfileConfig
        if ($guardConfig.profiles.ContainsKey($Profile)) {
            # Explicit profile + pass-through flag: forward the canonical token
            # (copilot defines -i/--interactive <prompt>) in flag-first order.
            $Arguments = @('--interactive') + $fwd
            Write-Host "  (-Interactive with an explicit profile: forwarding '--interactive' to copilot)" -ForegroundColor DarkYellow
            $Interactive = $false
        }
        else {
            # The name is NOT a known profile: PowerShell bound the orphaned
            # VALUE of --interactive (e.g. `run --interactive "do X"` with no
            # profile). Restore flag+value to the pass-through args and let the
            # wizard pick the profile.
            $Arguments = @('--interactive', $Profile) + $fwd
            Write-Host "  ('$Profile' restored as the --interactive value; opening the profile picker)" -ForegroundColor DarkYellow
            $Profile = ''
        }
    }
    else {
        # show/remove/set-env/use: an explicit name wins; the flag is cleared.
        $Interactive = $false
    }
}
if ($Interactive) {
    if ($Command -in @('show', 'remove', 'run', 'set-env', 'use', 'list', 'accounts')) {
        $wizConfig = Get-ProfileConfig
        # Disabled profiles stay reachable only where the action makes sense:
        # list/accounts (Enable-Disable) and remove (delete). run/set-env/show
        # hide them; their functions refuse explicit names anyway.
        $includeDisabled = $Command -in @('list', 'accounts', 'remove')
        $selection = Invoke-InteractiveSelect -CommandName $Command -Config $wizConfig -ArgumentList $Arguments -IncludeDisabled:$includeDisabled
        if ($selection.Cancelled) {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
        if ($Command -eq 'use') {
            $Profile = $selection.Account
        }
        else {
            $Profile = $selection.Profile
            if ($selection.Account) {
                $Arguments = @($Arguments) + @('--account', $selection.Account)
            }
        }

        if ($Command -in @('list', 'accounts')) {
            # Bare `-i` entry point: account -> scoped profile -> action menu.
            $action = Read-MenuChoice -Prompt 'Action' -AllowQuit -Options @(
                @{ Label = 'Run - launch Copilot with this profile'; Value = 'run' }
                @{ Label = 'Show - print profile JSON'; Value = 'show' }
                @{ Label = 'Set-env - apply profile to the current shell'; Value = 'set-env' }
                @{ Label = 'Enable-Disable - toggle profile enabled state'; Value = 'toggle' }
            )
            if ($null -eq $action) {
                Write-Host 'Cancelled.' -ForegroundColor Yellow
                return
            }
            switch ($action) {
                'run'     { Invoke-ProfileRun -Name $Profile }
                'show'    { Invoke-ProfileShow -Name $Profile }
                'set-env' { Invoke-ProfileSetEnv -Name $Profile -Arguments $Arguments }
                'toggle'  { Invoke-ProfileToggleEnabled -Name $Profile -Config $wizConfig | Out-Null }
            }
            return
        }

        if ($Command -eq 'remove') {
            # Wizard-path confirmation (confirm before mutating). Direct
            # `remove <name>` keeps its historical no-prompt behavior.
            $rp = $wizConfig.profiles[$Profile]
            $removeRows = [ordered]@{
                'Profile to remove' = $Profile
                'Provider type'     = if ($rp.type) { $rp.type } else { 'openai' }
                'Model'             = "$($rp.model)"
                'Base URL'          = "$($rp.baseUrl)"
            }
            if (-not (Show-ConfirmationSummary -Title "Remove profile '$Profile'?" -Rows $removeRows)) {
                Write-Host 'Cancelled. Nothing was removed.' -ForegroundColor Yellow
                return
            }
        }
        $Interactive = $false
        Write-Host ''
    }
    else {
        # add ignores the flag (add already is interactive).
        $Interactive = $false
    }
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

