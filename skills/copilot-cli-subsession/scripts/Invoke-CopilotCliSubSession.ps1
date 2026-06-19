<#
.SYNOPSIS
    Spawn a new isolated Copilot CLI sub-session with explicit session, agent, model,
    and BYOK provider control.

.DESCRIPTION
    A main session (Copilot CLI or VS Code) can call this script to start a fresh
    Copilot CLI subprocess. The script supports custom session IDs for resume/chaining,
    custom agent selection, model pinning, and BYOK profile application from
    ~/.copilot/byok-profiles.json.

.PARAMETER Prompt
    The task prompt to send to the sub-session. Supports multi-line strings
    (here-strings, backtick-n, or literal newlines).

.PARAMETER Name
    Human-readable session name passed to --name. Use short kebab-case slugs
    so agents can reference sessions by name. Distinct from SessionId (UUID).

.PARAMETER SessionId
    Custom session UUID passed to --session-id. Reuse the same UUID to chain
    follow-up messages in the same sub-session.

.PARAMETER Agent
    Custom agent name. Qualify plugin agents as plugin-name/agent-name.

.PARAMETER Model
    Model override for --model. Also sets $env:COPILOT_MODEL.

.PARAMETER ByokProfile
    Name of a BYOK profile stored in ~/.copilot/byok-profiles.json.
    Default: 'opencode-go-deepseek-v4-flash'.

.PARAMETER ConfigDir
    Isolated Copilot CLI config directory for --config-dir.

.PARAMETER WorkingDir
    Working directory for the sub-process (default: current location).

.PARAMETER ReasoningEffort
    Reasoning level: none | low | medium | high | xhigh | max.  Default: 'high'.

.PARAMETER JsonOutput
    Emit JSONL output instead of plain text.

.PARAMETER AllowAll
    Grant full permissions and disable interactive prompts.

.PARAMETER DisableBuiltInMcps
    Disable built-in MCP servers (by default the sub-session inherits the main
    session's MCP configuration).

.PARAMETER NoCustomInstructions
    Skip project custom instructions (by default the sub-session inherits the
    main session's custom instructions).

.PARAMETER TimeoutSeconds
    Sub-process timeout before forced termination (default: 600).

.PARAMETER Passthrough
    Additional arguments forwarded directly to the copilot CLI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$Agent,

    [Parameter(Mandatory = $false)]
    [string]$Model,

    [Parameter(Mandatory = $false)]
    [string]$ByokProfile = 'opencode-go-deepseek-v4-flash',

    [Parameter(Mandatory = $false)]
    [string]$ConfigDir,

    [Parameter(Mandatory = $false)]
    [string]$WorkingDir = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet('none', 'low', 'medium', 'high', 'xhigh', 'max')]
    [string]$ReasoningEffort = 'high',

    [switch]$JsonOutput,
    [switch]$AllowAll,
    [switch]$DisableBuiltInMcps,
    [switch]$NoCustomInstructions,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 600,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Passthrough
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-ProviderProp {
    param($Provider, [string]$Name)
    if ($null -eq $Provider) { return $null }
    if ($Provider.PSObject.Properties.Name -contains $Name) {
        return $Provider.$Name
    }
    return $null
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

# --- Step 1: Resolve BYOK profile ---
if ($ByokProfile) {
    $configDir = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
    $profilePath = Join-Path $configDir 'byok-profiles.json'

    if (-not (Test-Path $profilePath)) {
        throw "BYOK profile file not found: $profilePath"
    }

    $raw = Get-Content $profilePath -Raw | ConvertFrom-Json
    $provider = $raw.profiles.$ByokProfile

    if (-not $provider) {
        throw "BYOK profile '$ByokProfile' not found in $profilePath"
    }

    $env:COPILOT_PROVIDER_BASE_URL = $provider.baseUrl
    $env:COPILOT_PROVIDER_TYPE = if (Get-ProviderProp $provider 'type') { $provider.type } else { 'openai' }
    $env:COPILOT_MODEL = $provider.model

    $apiKey = Get-ProviderProp $provider 'apiKey'
    if ($apiKey) {
        $env:COPILOT_PROVIDER_API_KEY = Expand-EnvPlaceholder -Value $apiKey
    }

    $wireApi = Get-ProviderProp $provider 'wireApi'
    if ($wireApi) {
        $env:COPILOT_PROVIDER_WIRE_API = $wireApi
    }

    $maxPrompt = Get-ProviderProp $provider 'maxPromptTokens'
    if ($maxPrompt) {
        $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = [string]$maxPrompt
    }

    $maxOutput = Get-ProviderProp $provider 'maxOutputTokens'
    if ($maxOutput) {
        $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = [string]$maxOutput
    }

    $offline = Get-ProviderProp $provider 'offline'
    if ($offline -eq $true) {
        $env:COPILOT_OFFLINE = 'true'
    }

    $proxyPort = Get-ProviderProp $provider 'proxyPort'
    if ($proxyPort) {
        $proxyScript = Join-Path $configDir 'moonshot-proxy' 'start-proxy.ps1'
        if (Test-Path $proxyScript) {
            & $proxyScript
            $env:COPILOT_PROVIDER_BASE_URL = 'https://moonshot.local/v1'
        }
        else {
            Write-Warning "Moonshot proxy script not found at $proxyScript; proxyPort ignored."
        }
    }
}

# --- Step 2: Model override precedence ---
if ($Model) {
    $env:COPILOT_MODEL = $Model
}

# --- Step 3: Build CLI argument list ---
$cliArgs = [System.Collections.ArrayList]@()

if ($ConfigDir) {
    [void]$cliArgs.Add('--config-dir')
    [void]$cliArgs.Add($ConfigDir)
}

if ($Name) {
    [void]$cliArgs.Add('--name')
    [void]$cliArgs.Add($Name)
}

if ($SessionId) {
    # --session-id starts a new session with an explicit UUID (preferred).
    # Resume via --resume is attempted only if --session-id does not exist in this CLI version.
    # Detect by checking copilot help: newer versions support --session-id for new sessions.
    [void]$cliArgs.Add('--session-id')
    [void]$cliArgs.Add($SessionId)
}

if ($Agent) {
    [void]$cliArgs.Add('--agent')
    [void]$cliArgs.Add($Agent)
}

if ($ReasoningEffort) {
    [void]$cliArgs.Add('--reasoning-effort')
    [void]$cliArgs.Add($ReasoningEffort)
}

if ($JsonOutput) {
    [void]$cliArgs.Add('--output-format')
    [void]$cliArgs.Add('json')
}
else {
    [void]$cliArgs.Add('-s')
}

if ($AllowAll) {
    [void]$cliArgs.Add('--allow-all')
    [void]$cliArgs.Add('--no-ask-user')
}

if ($DisableBuiltInMcps) {
    [void]$cliArgs.Add('--disable-builtin-mcps')
}

if ($NoCustomInstructions) {
    [void]$cliArgs.Add('--no-custom-instructions')
}

# Stream off for programmatic capture; passthrough can override if needed.
[void]$cliArgs.Add('--stream')
[void]$cliArgs.Add('off')

if ($Passthrough) {
    foreach ($arg in $Passthrough) {
        [void]$cliArgs.Add($arg)
    }
}

# Prompt must be last.
[void]$cliArgs.Add('-p')
[void]$cliArgs.Add($Prompt)

# --- Step 4: Resolve copilot command and runtime ---
$copilotCmd = Get-Command copilot -ErrorAction SilentlyContinue
if (-not $copilotCmd) {
    throw "'copilot' command not found in PATH."
}
$copilotPath = $copilotCmd.Source

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    throw "'pwsh' (PowerShell 7+) not found in PATH."
}

# --- Step 5: Ensure COPILOT_HOME is set ---
# Copilot CLI auto-adds --config-dir internally when COPILOT_HOME is unset,
# triggering a deprecation warning. Set it to the standard location.
if (-not $env:COPILOT_HOME) {
    $env:COPILOT_HOME = Join-Path $HOME '.copilot'
}

# --- Step 6: Spawn subprocess via pwsh ---
Write-Host "[copilot-cli-subsession] Spawning sub-session..." -ForegroundColor Cyan
Write-Host "[copilot-cli-subsession] Name: $Name | Agent: $Agent | Model: $env:COPILOT_MODEL | Session: $SessionId" -ForegroundColor Gray

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $pwshCmd.Source
$psi.ArgumentList.Add('-NoProfile')
$psi.ArgumentList.Add('-File')
$psi.ArgumentList.Add($copilotPath)
foreach ($arg in $cliArgs) {
    $psi.ArgumentList.Add($arg)
}
$psi.WorkingDirectory = $WorkingDir
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$proc.Start() | Out-Null

$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    $proc.Kill()
    throw "[copilot-cli-subsession] Sub-session timed out after ${TimeoutSeconds}s"
}

$proc.WaitForExit()
$stdout = $stdoutTask.Result.TrimEnd()
$stderr = $stderrTask.Result.TrimEnd()

if ($stdout) { Write-Host $stdout }
if ($stderr) { Write-Warning $stderr }

# --- Step 7: Return structured result ---
return [PSCustomObject]@{
    ExitCode      = $proc.ExitCode
    StdOut        = $stdout
    StdErr        = $stderr
    Name          = $Name
    SessionId     = $SessionId
    Agent         = $Agent
    Model         = $env:COPILOT_MODEL
    ByokProfile   = $ByokProfile
}
