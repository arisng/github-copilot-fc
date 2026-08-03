<#
.SYNOPSIS
    Detect drift between this skill's documented Copilot CLI surface and the
    installed GitHub Copilot CLI.

.DESCRIPTION
    Captures `copilot --version`, `copilot --help`, and `copilot help environment`,
    then compares them against the flags, environment variables, and
    reasoning-effort levels that the copilot-cli-subsession skill (and its
    copilot-byok / copilot-sdk-dotnet siblings) document.

    Exits non-zero when drift is found so the script can be used as a
    pre-publish gate. New flags found in the installed CLI are reported as
    informational "new capabilities" (they never fail the gate).

    The expected surface is maintained in:
    - references/copilot-sdk-parity-matrix.md  (cross-surface map, verified 1.0.77)
    - references/copilot-cli-programmatic-cheatsheet.md (flag reference)

.PARAMETER CliCommand
    Path to the copilot CLI. Default: the first `copilot` found on PATH.

.PARAMETER ReportPath
    Optional path to write a markdown copy of the report to.

.EXAMPLE
    .\scripts\Test-CopilotCliParity.ps1

.EXAMPLE
    .\scripts\Test-CopilotCliParity.ps1 -ReportPath .\parity-report.md

.OUTPUTS
    Exit codes: 0 = no drift, 1 = drift found (missing documented flag/env/level),
    2 = infrastructure failure (copilot CLI not found or help could not be captured).
#>
[CmdletBinding()]
param(
    [string]$CliCommand,
    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# --- Locate the copilot CLI ---
if (-not $CliCommand) {
    $found = Get-Command copilot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $CliCommand = $found.Source }
}
if (-not $CliCommand) {
    Write-Error "copilot CLI not found on PATH. Pass -CliCommand with the path to the copilot CLI."
    exit 2
}
if (-not (Test-Path $CliCommand)) {
    Write-Error "copilot CLI not found at '$CliCommand'."
    exit 2
}

# --- Expected surface (keep in sync with references/copilot-sdk-parity-matrix.md) ---
$ExpectedFlags = @(
    # Forwarded by Invoke-CopilotCliSubSession.ps1
    'session-id', 'name', 'agent', 'model', 'reasoning-effort', 'effort',
    'allow-all', 'no-ask-user', 'disable-builtin-mcps', 'no-custom-instructions',
    'stream', 'output-format', 'prompt', 'silent', 'resume',
    # Documented in the parity matrix / cheatsheet
    'add-dir', 'available-tools', 'excluded-tools', 'log-dir', 'log-level',
    'allow-tool', 'deny-tool', 'allow-url', 'deny-url',
    'disable-mcp-server', 'additional-mcp-config', 'attachment'
)

$ExpectedEnvVars = @(
    'COPILOT_MODEL', 'COPILOT_HOME', 'COPILOT_OFFLINE', 'COPILOT_ALLOW_ALL',
    'COPILOT_PROVIDER_BASE_URL', 'COPILOT_PROVIDER_TYPE', 'COPILOT_PROVIDER_API_KEY',
    'COPILOT_PROVIDER_WIRE_API', 'COPILOT_PROVIDER_MAX_PROMPT_TOKENS',
    'COPILOT_PROVIDER_MAX_OUTPUT_TOKENS'
)

$ExpectedReasoningLevels = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')

# Flags the skill deliberately does not document; excluded from new-capability noise.
$IgnoredNewFlags = @(
    'acp', 'banner', 'mouse', 'no-mouse', 'no-color', 'screen-reader',
    'bash-env', 'no-bash-env', 'no-auto-update',
    'no-remote', 'no-remote-export', 'remote-export', 'remote',
    'experimental', 'no-experimental', 'plugin-dir', 'plan', 'continue',
    'interactive', 'help', 'version', 'plain-diff', 'disallow-temp-dir',
    'max-autopilot-continues', 'yolo', 'max-ai-credits', 'extension-sdk-path',
    'enable-reasoning-summaries', 'enable-all-github-mcp-tools',
    'add-github-mcp-tool', 'add-github-mcp-toolset', 'allow-all-mcp-server-instructions',
    'allow-all-paths', 'allow-all-tools', 'allow-all-urls'
)

# --- Helpers ---
function Get-CliText {
    param([string[]]$Arguments)
    $text = & $CliCommand @Arguments 2>&1 | Out-String
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "No output from '$CliCommand $($Arguments -join ' ')'. Is the CLI installed correctly?"
    }
    return $text
}

function Get-FlagsFromHelp {
    param([string]$HelpText)
    $optionsMatch = [regex]::Match($HelpText, '(?s)\bOptions:\s*(.*?)\r?\n\s*Commands:')
    if (-not $optionsMatch.Success) { $optionsMatch = [regex]::Match($HelpText, '(?s)\bOptions:\s*(.*)') }
    $block = $optionsMatch.Groups[1].Value
    $flags = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($block, '--([a-z0-9-]+)')) {
        [void]$flags.Add($m.Groups[1].Value)
    }
    return $flags
}

function Get-ReasoningLevelsFromHelp {
    param([string]$HelpText)
    # The choices list is wrapped across continuation lines, so scan a fixed
    # window after the --reasoning-effort entry instead of matching one line.
    $idx = $HelpText.IndexOf('--reasoning-effort')
    if ($idx -lt 0) { return @() }
    $tail = $HelpText.Substring($idx, [Math]::Min(300, $HelpText.Length - $idx))
    $choicesMatch = [regex]::Match($tail, 'choices:\s*([^)]+)')
    if (-not $choicesMatch.Success) { return @() }
    $levels = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($choicesMatch.Groups[1].Value, '"([^"]+)"')) {
        $levels.Add($m.Groups[1].Value)
    }
    return $levels
}

function Get-EnvVarsFromEnvironmentHelp {
    param([string]$EnvText)
    $vars = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($EnvText, '\b(COPILOT_[A-Z][A-Z0-9_]+)\b')) {
        [void]$vars.Add($m.Groups[1].Value)
    }
    return $vars
}

# --- Capture the installed CLI surface ---
$versionText = Get-CliText -Arguments @('--version')
$versionMatch = [regex]::Match($versionText, '(\d+\.\d+\.\d+)')
$cliVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }

$help = Get-CliText -Arguments @('--help')
$envHelp = Get-CliText -Arguments @('help', 'environment')

$actualFlags = Get-FlagsFromHelp -HelpText $help
$actualLevels = Get-ReasoningLevelsFromHelp -HelpText $help
$actualEnv = Get-EnvVarsFromEnvironmentHelp -EnvText $envHelp

# --- Compare against the expected surface ---
$missingFlags = @($ExpectedFlags | Where-Object { -not $actualFlags.Contains($_) } | Sort-Object)
$newFlags = @($actualFlags | Where-Object { $_ -notin $ExpectedFlags -and $_ -notin $IgnoredNewFlags } | Sort-Object)
$missingEnv = @($ExpectedEnvVars | Where-Object { -not $actualEnv.Contains($_) } | Sort-Object)
$missingLevels = @($ExpectedReasoningLevels | Where-Object { $_ -notin $actualLevels } | Sort-Object)
$newLevels = @($actualLevels | Where-Object { $_ -notin $ExpectedReasoningLevels } | Sort-Object)

$findings = [System.Collections.Generic.List[string]]::new()
foreach ($f in $missingFlags) { $findings.Add("MISSING FLAG   --$f  (documented by the skill, not in installed CLI help)") }
foreach ($v in $missingEnv) { $findings.Add("MISSING ENV    $v  (documented by the skill, not in 'copilot help environment')") }
foreach ($l in $missingLevels) { $findings.Add("MISSING LEVEL  $l  (expected reasoning-effort level, not offered by installed CLI)") }

# --- Report ---
$result = if ($findings.Count -gt 0) { 'DRIFT FOUND' } else { 'OK' }
$console = @"
Copilot CLI parity check
  CLI version       : $cliVersion
  Expected flags    : $($ExpectedFlags.Count)
  Flags found       : $($actualFlags.Count)
  Expected env vars : $($ExpectedEnvVars.Count)
  Env vars found    : $($actualEnv.Count)
  Reasoning levels  : $($actualLevels -join ', ')
  Result            : $result
"@

if ($findings.Count -gt 0) {
    $console += "`n`nFindings ($($findings.Count)):"
    foreach ($finding in $findings) { $console += "`n  - $finding" }
}
if ($newFlags.Count -gt 0) {
    $console += "`n`nNew capabilities in installed CLI (not yet documented by the skill):"
    foreach ($f in $newFlags) { $console += "`n  - --$f" }
}
if ($newLevels.Count -gt 0) {
    $console += "`n`nNew reasoning-effort levels offered by installed CLI: $($newLevels -join ', ')"
}

Write-Host $console

if ($ReportPath) {
    $md = @"
# Copilot CLI parity check ($(Get-Date -Format 'yyyy-MM-dd'))

- **CLI version**: $cliVersion
- **Result**: $result

## Findings ($($findings.Count))
$($findings | ForEach-Object { "- $_" } | Out-String)

## New capabilities in installed CLI
$($newFlags | ForEach-Object { "- \`--$_" } | Out-String)

## Reasoning-effort levels
- Expected: $($ExpectedReasoningLevels -join ', ')
- Installed CLI: $($actualLevels -join ', ')
"@
    $ReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
    Set-Content -Path $ReportPath -Value $md -Encoding utf8
    Write-Host "`nReport written to $ReportPath"
}

if ($findings.Count -gt 0) { exit 1 }
exit 0
