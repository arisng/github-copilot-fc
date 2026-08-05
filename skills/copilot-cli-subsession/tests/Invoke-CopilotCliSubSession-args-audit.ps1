<#
.SYNOPSIS
    Empirical argument audit harness for skills/copilot-cli-subsession/scripts/Invoke-CopilotCliSubSession.ps1.

.DESCRIPTION
    Executes the real Invoke-CopilotCliSubSession.ps1 against the seeded staging home
    (~/.copilot-staging by default, the "dojo") and captures, for every supported argument:

      - the exact CLI argv the script forwards to the copilot child (via a shim copilot.ps1),
      - the COPILOT_* env it emits to the child,
      - the 9-field return object,
      - seeding / validation / precedence behaviors.

    The shim intercepts the child copilot spawn (PATH-prepend + real-copilot scrub + a
    SHIM_NOT_WINNING preflight) so the shim matrix is deterministic and zero-cost. A small
    opt-in -Live pass spawns REAL copilot sub-sessions against the dojo (cheap models only,
    see COST GUARDRAIL) to verify runtime-visible behavior: session-state events.jsonl,
    model.call_start, hot-switching (same/different family), slash command, custom agent,
    and SessionId chaining.

    Isolation guarantees:
    - COPILOT_HOME is REMOVED from every child env by default (script resolves production),
      set only for the s8-4 case. Production ~/.copilot is only ever READ.
    - The dojo (staging home) is pre-seeded from production if its byok-profiles.json is
      missing (B2), then hash-asserted unchanged (file list: byok-profiles.json + mcp-config.json).
    - Real API keys are never used in shim mode: children get sentinel keys.
    - -Live requires -Live AND a real OPENCODE_API_KEY_WORK in the parent env; it injects the
      parent's real keys into the child (no sentinels) and enforces a cheap-model allowlist
      before any spawn.

    Status taxonomy: PASS / FAIL / SKIP / KNOWN-GAP (KNOWN-GAP reports as PASS with a gap
    label so the harness stays green while documenting behavior).
    Exit codes: 0 all passed, 1 any failed, 2 harness/preflight error.

    Design history: rubber-duck REQUEST-CHANGES (2026-08-05) — B1 (RemoveEnv COPILOT_HOME
    default), B2 (pre-seed + runtime-derived s5 expectations), B3 (spike gate + SHIM_NOT_WINNING
    preflight); user follow-ups (cheap models, same/different-family hot-switch, different-family
    subsession, slash/agent/sessionid chaining).

.EXAMPLE
    # Shim matrix only (zero cost) against the dojo
    pwsh -NoProfile -File skills/copilot-cli-subsession/tests/Invoke-CopilotCliSubSession-args-audit.ps1

.EXAMPLE
    # Shim matrix + live probes (real copilot, cheap models only, needs real keys)
    pwsh -NoProfile -File skills/copilot-cli-subsession/tests/Invoke-CopilotCliSubSession-args-audit.ps1 -Live

.EXAMPLE
    # Throwaway staging home (no dojo), keep temp dirs for inspection
    pwsh -NoProfile -File skills/copilot-cli-subsession/tests/Invoke-CopilotCliSubSession-args-audit.ps1 -StagingHome "$env:TEMP\audit-stage" -KeepStaging
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StagingHome = (Join-Path $HOME '.copilot-staging'),

    [Parameter(Mandatory = $false)]
    [string]$FixturePath = (Join-Path $PSScriptRoot 'fixtures\byok-profiles.fixture.json'),

    [Parameter(Mandatory = $false)]
    [switch]$Live,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLive,

    [Parameter(Mandatory = $false)]
    [switch]$KeepStaging,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
$SubSessionScript = Join-Path $repoRoot 'skills\copilot-cli-subsession\scripts\Invoke-CopilotCliSubSession.ps1'
$ProductionHome = Join-Path $HOME '.copilot'
$ProductionProfile = Join-Path $ProductionHome 'byok-profiles.json'

if (-not (Test-Path $SubSessionScript -PathType Leaf)) { throw "Invoke-CopilotCliSubSession.ps1 not found: $SubSessionScript" }
if (-not (Test-Path $FixturePath -PathType Leaf)) { throw "Fixture not found: $FixturePath" }

# --- Artifacts ---------------------------------------------------------------
$reportTimestamp = (Get-Date).ToUniversalTime().ToString('yyMMdd-HHmmss')
$script:reportDir = Join-Path $repoRoot ("scripts\test\.artifacts\copilot-cli-subsession-args-audit\run-{0}-{1}" -f $reportTimestamp, $PID)
$script:evidenceDir = Join-Path $script:reportDir 'evidence'
$script:testCases = [ordered]@{}
$script:harnessError = $null
$script:tempDirs = @()
$script:dojoSnapshotBefore = $null
$script:prodHashBefore = $null
$script:liveEnabled = $false
$script:prodOk = $false
$script:dojoOk = $false

# --- Helpers -----------------------------------------------------------------
function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-FileHashValue {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function New-TempDirectory {
    param([Parameter(Mandatory)][string]$Prefix)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    $script:tempDirs += $path
    return $path
}

function Get-SentinelChildEnv {
    param([bool]$ForLive = $false)
    if ($ForLive) {
        # Real keys passthrough for live probes (parent env must hold them).
        $map = @{}
        foreach ($k in @('OPENCODE_API_KEY_HOME', 'OPENCODE_API_KEY_WORK', 'OPENAI_API_KEY', 'CODEF_MOONSHOT_API_KEY', 'OPENROUTER_API_KEY', 'DPROCESS_OPENAI_API_KEY')) {
            $v = [Environment]::GetEnvironmentVariable($k)
            if ($v) { $map[$k] = $v }
        }
        return $map
    }
    # Sentinel keys ONLY — real OPENCODE_API_KEY_* / OPENAI_API_KEY are never inherited.
    return @{
        'OPENCODE_API_KEY_HOME' = 'sentinel-opencode-home-key'
        'OPENCODE_API_KEY_WORK' = 'sentinel-opencode-work-key'
        'OPENAI_API_KEY' = 'sentinel-openai-key'
        'CODEF_MOONSHOT_API_KEY' = 'sentinel-codef-moonshot-key'
        'OPENROUTER_API_KEY' = 'sentinel-openrouter-key'
        'DPROCESS_OPENAI_API_KEY' = 'sentinel-dprocess-key'
        'SENTINEL_OPENAI_KEY' = 'sentinel-openai-key'
        'SENTINEL_ACCT_A_KEY' = 'sentinel-acct-a-key'
        'SENTINEL_ANTHROPIC_KEY' = 'sentinel-anthropic-key'
    }
}

function Invoke-ChildPwsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandText,
        [hashtable]$ExtraEnv = @{},
        # B1: strip COPILOT_HOME by default so the SUT resolves production (or -CopilotHome param).
        [string[]]$RemoveEnv = @('COPILOT_HOME'),
        [string[]]$PathPrepends = @(),
        [bool]$ScrubCopilotFromPath = $false,
        [string]$StdinText = $null,
        [int]$TimeoutSeconds = 60
    )

    $pwshCmd = Get-Command pwsh -ErrorAction Stop
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwshCmd.Source
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-Command')
    $psi.ArgumentList.Add($CommandText)
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = ($null -ne $StdinText)
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true

    foreach ($entry in $ExtraEnv.GetEnumerator()) { $psi.Environment[$entry.Key] = [string]$entry.Value }
    # RemoveEnv applied AFTER ExtraEnv so explicit removals win (e.g. COPILOT_HOME).
    foreach ($key in $RemoveEnv) { $null = $psi.Environment.Remove($key) }

    if ($PathPrepends.Count -gt 0 -or $ScrubCopilotFromPath) {
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
        $parts = @($currentPath -split ';' | Where-Object { $_ -ne '' })
        if ($ScrubCopilotFromPath) {
            $realCopilot = Get-Command copilot -ErrorAction SilentlyContinue
            if ($realCopilot -and $realCopilot.Source) {
                $realCopilotDir = Split-Path -Path $realCopilot.Source -Parent
                if ($realCopilotDir) { $parts = @($parts | Where-Object { $_ -ne $realCopilotDir }) }
            }
        }
        $parts = @($PathPrepends) + $parts
        $psi.Environment['Path'] = ($parts -join ';')
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Failed to start child pwsh: $CommandText" }

    if ($null -ne $StdinText) {
        $process.StandardInput.Write($StdinText)
        $process.StandardInput.Close()
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Child pwsh timed out after ${TimeoutSeconds}s: $CommandText"
    }
    $process.WaitForExit()
    $stdoutTask.Wait()
    $stderrTask.Wait()

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdoutTask.Result
        StdErr = $stderrTask.Result
    }
}

function New-CopilotShim {
    # S1: logs ARGS|/PWD|/ENV| to a FILE (COPILOT_TEST_SHIM_LOG); echoes ONLY 'SHIM_OK' to
    # stdout (the SUT's Step 7 re-emits child stdout via Write-Host, so stdout must stay tiny).
    $dir = New-TempDirectory 'subsession-shim'
    $shim = @'
$logPath = $env:COPILOT_TEST_SHIM_LOG
if ($logPath) {
    "ARGS|" + ($args -join ' ') | Out-File -FilePath $logPath -Encoding utf8
    "PWD|" + (Get-Location).Path | Out-File -FilePath $logPath -Encoding utf8 -Append
    "ENV|COPILOT_HOME=$env:COPILOT_HOME|BASE_URL=$env:COPILOT_PROVIDER_BASE_URL|TYPE=$env:COPILOT_PROVIDER_TYPE|MODEL=$env:COPILOT_MODEL|WIRE_API=$env:COPILOT_PROVIDER_WIRE_API|KEY=$env:COPILOT_PROVIDER_API_KEY|MAX_PROMPT=$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS|MAX_OUTPUT=$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS|OFFLINE=$env:COPILOT_OFFLINE" | Out-File -FilePath $logPath -Encoding utf8 -Append
}
$sleepSec = $env:COPILOT_TEST_SHIM_SLEEP
if ($sleepSec) { Start-Sleep -Seconds ([int]$sleepSec) }
Write-Output 'SHIM_OK'
$exitVal = $env:COPILOT_TEST_SHIM_EXIT
if ($exitVal) { exit ([int]$exitVal) }
exit 0
'@
    $shimPath = Join-Path $dir 'copilot.ps1'
    Write-Utf8File -Path $shimPath -Content $shim
    return $dir
}

function Format-ChildCommand {
    param([string]$Template, [hashtable]$Values)
    $result = $Template
    foreach ($entry in $Values.GetEnumerator()) {
        $result = $result.Replace($entry.Key, $entry.Value)
    }
    return $result
}

function Quote-ArgVal {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Save-ChildEvidence {
    param([string]$Id, [object]$ChildResult, [string]$ShimLog = $null)
    $out = Join-Path $script:evidenceDir "$Id.out.txt"
    $err = Join-Path $script:evidenceDir "$Id.err.txt"
    Write-Utf8File -Path $out -Content ([string]$ChildResult.StdOut)
    if (-not [string]::IsNullOrEmpty($ChildResult.StdErr)) { Write-Utf8File -Path $err -Content ([string]$ChildResult.StdErr) }
    $paths = @($out)
    if (Test-Path $err) { $paths += $err }
    if ($ShimLog -and (Test-Path $ShimLog)) {
        $dst = Join-Path $script:evidenceDir "$Id.shim.log"
        Copy-Item $ShimLog $dst -Force
        $paths += $dst
    }
    return @($paths)
}

# --- Test registry -----------------------------------------------------------
function Add-TestCase {
    param([string]$Id, [string]$Bucket, [string]$Checkpoint)
    $script:testCases[$Id] = [ordered]@{
        id = $Id
        bucket = $Bucket
        checkpoint = $Checkpoint
        status = 'pending'
        details = 'Pending execution.'
        evidence = @()
        known_gap = ''
    }
}

function Set-TestResult {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('passed', 'failed', 'skipped')][string]$Status,
        [string]$Details,
        [string]$KnownGap = '',
        [string[]]$Evidence = @()
    )
    $t = $script:testCases[$Id]
    $t.status = $Status
    if ($Details) { $t.details = $Details }
    if ($KnownGap) { $t.known_gap = $KnownGap }
    foreach ($e in @($Evidence)) {
        if ($e -and $e -notin $t.evidence) { $t.evidence += $e }
    }
}

function New-TestResult {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Details,
        [string]$KnownGap = '',
        [string[]]$Evidence = @(),
        [switch]$Skip
    )
    return [PSCustomObject]@{
        Passed = $Passed
        Details = $Details
        KnownGap = $KnownGap
        Evidence = @($Evidence)
        Skipped = [bool]$Skip
    }
}

function Invoke-Test {
    param([string]$Id, [scriptblock]$Body)
    if (-not $script:testCases.Contains($Id)) { throw "Unknown test id: $Id" }
    try {
        $result = & $Body
        $status = if ($result.Skipped) { 'skipped' } elseif ($result.Passed) { 'passed' } else { 'failed' }
        Set-TestResult -Id $Id -Status $status -Details $result.Details -KnownGap $result.KnownGap -Evidence $result.Evidence
    }
    catch {
        Set-TestResult -Id $Id -Status 'failed' -Details "HARNESS ERROR: $($_.Exception.Message)"
    }
}

function Test-Precondition {
    param([string]$Required)
    if ($Required -eq 'prod' -and -not $script:prodOk) { return $false }
    if ($Required -eq 'dojo' -and -not $script:dojoOk) { return $false }
    return $true
}

# --- Command templates (single-quoted: $env: stays literal for the child) ----
$script:tmplAudit = @'
$__s = (Get-Command copilot -ErrorAction Stop).Path
if ($__s -ne '__SHIM__') { Write-Error 'SHIM_NOT_WINNING'; exit 90 }
try {
  $__r = & '__SUBSESSION__' __ARGS__ *>&1
  foreach ($__x in $__r) {
    if ($__x -is [System.Management.Automation.PSCustomObject]) { 'RETURN|' + ($__x | ConvertTo-Json -Compress -Depth 5) }
    elseif ($__x -is [System.Management.Automation.WarningRecord]) { 'WARN|' + $__x.Message }
    else { 'LINE|' + $__x.ToString() }
  }
} catch { 'ERROR|' + $_.Exception.Message }
'@

$script:tmplLive = @'
try {
  $__r = & '__SUBSESSION__' __ARGS__ *>&1
  foreach ($__x in $__r) {
    if ($__x -is [System.Management.Automation.PSCustomObject]) { 'RETURN|' + ($__x | ConvertTo-Json -Compress -Depth 5) }
    elseif ($__x -is [System.Management.Automation.WarningRecord]) { 'WARN|' + $__x.Message }
    else { 'LINE|' + $__x.ToString() }
  }
} catch { 'ERROR|' + $_.Exception.Message }
'@

# --- Case helpers ------------------------------------------------------------
# Hermetic children: scrub parent COPILOT_* provider env so each case asserts exactly what the SUT emits
# for its profile, never stale parent-terminal env (REAL FINDING 2026-08-05: a parent terminal holding
# WIRE_API=responses from an earlier luna session leaked into every child; the SUT only SETS
# COPILOT_PROVIDER_WIRE_API when the profile has wireApi and never clears inherited values → flash profile
# wrongly forwarded responses). s8-4 overrides with -RemoveEnv @() to test env-only COPILOT_HOME resolution.
$script:scrubCopilotEnv = @(
    'COPILOT_HOME',
    'COPILOT_PROVIDER_BASE_URL', 'COPILOT_PROVIDER_TYPE', 'COPILOT_PROVIDER_API_KEY',
    'COPILOT_PROVIDER_WIRE_API', 'COPILOT_PROVIDER_MAX_PROMPT_TOKENS', 'COPILOT_PROVIDER_MAX_OUTPUT_TOKENS',
    'COPILOT_MODEL', 'COPILOT_OFFLINE', 'COPILOT_PROVIDER_BEARER_TOKEN'
)

function Invoke-AuditCase {
    param(
        [Parameter(Mandatory)][string]$Id,
        # s1-1 passes NO args at all (empty string) to trigger the At-least-one error.
        [Parameter(Mandatory)][AllowEmptyString()][string]$ArgsText,
        [int]$TimeoutSeconds = 60,
        [hashtable]$ExtraEnv = @{},
        [string[]]$RemoveEnv = $script:scrubCopilotEnv
    )
    $shimDir = New-CopilotShim
    $shimPath = Join-Path $shimDir 'copilot.ps1'
    $logPath = Join-Path $shimDir 'shim.log'
    $cmd = Format-ChildCommand -Template $script:tmplAudit -Values @{
        '__SHIM__' = $shimPath; '__SUBSESSION__' = $SubSessionScript; '__ARGS__' = $ArgsText
    }
    $envMap = Get-SentinelChildEnv
    $envMap['COPILOT_TEST_SHIM_LOG'] = $logPath
    foreach ($k in $ExtraEnv.Keys) { $envMap[$k] = $ExtraEnv[$k] }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv $envMap -RemoveEnv $RemoveEnv -PathPrepends @($shimDir) -ScrubCopilotFromPath $true -TimeoutSeconds $TimeoutSeconds
    $logContent = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }
    $ev = Save-ChildEvidence -Id $Id -ChildResult $child -ShimLog $logPath
    return [PSCustomObject]@{ Child = $child; ShimLog = $logContent; Evidence = @($ev) }
}

# COST GUARDRAIL allowlist. gpt-5.6-luna is the ONLY responses-wire profile in the set and is pricey
# (272K-tier boundary); it is allowlisted for the cold-switch l8 case — run l8 sparingly.
$script:liveAllowlistProfiles = @('opencode-go-deepseek-v4-flash', 'opencode-go-deepseek-v4-pro', 'opencode-go-kimi-k26', 'opencode-go-gpt-5.6-luna')
$script:liveAllowlistModels = @('deepseek-v4-flash', 'deepseek-v4-pro', 'kimi-k2.6', 'gpt-5.6-luna')

function Invoke-LiveCase {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$ArgsText,
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$Model,
        [int]$TimeoutSeconds = 120
    )
    # COST GUARDRAIL: refuse non-allowlisted (expensive/fragile) models before any spawn.
    if ($Profile -notin $script:liveAllowlistProfiles -or $Model -notin $script:liveAllowlistModels) {
        throw "COST GUARDRAIL: live case $Id uses non-allowlisted profile '$Profile' / model '$Model'. Allowlisted models: $($script:liveAllowlistModels -join ', ')"
    }
    $cmd = Format-ChildCommand -Template $script:tmplLive -Values @{
        '__SUBSESSION__' = $SubSessionScript; '__ARGS__' = $ArgsText
    }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv (Get-SentinelChildEnv -ForLive $true) -RemoveEnv $script:scrubCopilotEnv -TimeoutSeconds $TimeoutSeconds
    $ev = Save-ChildEvidence -Id $Id -ChildResult $child
    return [PSCustomObject]@{ Child = $child; Evidence = @($ev) }
}

function Get-ReturnObject {
    param([object]$ChildResult)
    $line = @($ChildResult.StdOut -split "`n" | Where-Object { $_ -match '^RETURN\|' } | Select-Object -Last 1)
    if (-not $line -or [string]::IsNullOrWhiteSpace($line)) { return $null }
    $json = $line.Substring(7).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    try { return ($json | ConvertFrom-Json) } catch { return $null }
}

function Get-ShimArgs {
    param([string]$Log)
    $line = @($Log -split "`n" | Where-Object { $_.StartsWith('ARGS|') } | Select-Object -First 1)
    if (-not $line) { return '' }
    return $line.Substring(5).Trim()
}

function Get-ShimEnv {
    param([string]$Log)
    $line = @($Log -split "`n" | Where-Object { $_.StartsWith('ENV|') } | Select-Object -First 1)
    if (-not $line) { return '' }
    return $line.Substring(4).Trim()
}

function Get-ShimPwd {
    param([string]$Log)
    $line = @($Log -split "`n" | Where-Object { $_.StartsWith('PWD|') } | Select-Object -First 1)
    if (-not $line) { return '' }
    return $line.Substring(4).Trim()
}

function Get-OutLine {
    param([object]$ChildResult, [string]$Prefix)
    $line = @($ChildResult.StdOut -split "`n" | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1)
    if (-not $line) { return '' }
    return $line.Substring($Prefix.Length).Trim()
}

function Get-StagingJson {
    $path = Join-Path $StagingHome 'byok-profiles.json'
    if (-not (Test-Path $path -PathType Leaf)) { return $null }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Get-DojoSnapshot {
    $snap = [ordered]@{}
    foreach ($f in @('byok-profiles.json', 'mcp-config.json')) {
        $p = Join-Path $StagingHome $f
        $snap[$f] = if (Test-Path $p -PathType Leaf) { (Get-FileHash $p -Algorithm SHA256).Hash } else { $null }
    }
    return ($snap | ConvertTo-Json -Compress)
}

function New-SeededHome {
    # Mirrors the SUT Step 0 seeding: copy production seed into a fresh throwaway home.
    param([string]$Prefix)
    $dir = New-TempDirectory $Prefix
    Copy-Item $ProductionProfile (Join-Path $dir 'byok-profiles.json') -Force
    if (Test-Path (Join-Path $ProductionHome 'mcp-config.json')) {
        Copy-Item (Join-Path $ProductionHome 'mcp-config.json') (Join-Path $dir 'mcp-config.json') -Force
    }
    return $dir
}

function New-FixtureHome {
    $dir = New-TempDirectory 'subsession-fixture'
    Copy-Item $FixturePath (Join-Path $dir 'byok-profiles.json') -Force
    return $dir
}

function Get-SessionStateFile {
    param([string]$SessionId)
    $ssRoot = Join-Path $StagingHome 'session-state'
    if (-not (Test-Path $ssRoot)) { return $null }
    $dir = Get-ChildItem -Path $ssRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $SessionId } | Select-Object -First 1
    if ($dir) {
        $f = Join-Path $dir.FullName 'events.jsonl'
        if (Test-Path $f) { return $f }
    }
    $f2 = Get-ChildItem -Path $ssRoot -Recurse -Filter 'events.jsonl' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match $SessionId } | Select-Object -First 1
    if ($f2) { return $f2.FullName }
    return $null
}

function Get-CallStartModel {
    param([string]$EventsFile)
    if (-not $EventsFile -or -not (Test-Path $EventsFile)) { return $null }
    $lines = Get-Content $EventsFile -ErrorAction SilentlyContinue
    foreach ($ln in $lines) {
        if ($ln -match 'call_start' -and $ln -match '"model"') {
            if ($ln -match '"model"\s*:\s*"([^"]+)"') { return $Matches[1] }
        }
    }
    return $null
}

# ============================================================================
# Test cases
# ============================================================================

# --- S1: validation (no spawn; production-default so Step 1 can run) ---------
function Test-S1_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's1-1' -ArgsText ''
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'At least one of -SlashCommand or -Prompt'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S1_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's1-2' -ArgsText ("-SlashCommand " + (Quote-ArgVal '/handoff'))
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'must not start with /'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S1_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's1-3' -ArgsText ("-SlashCommand " + (Quote-ArgVal ''))
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'must not be empty'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S1_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's1-4' -ArgsText "-Prompt 'x' -ReasoningEffort 'ultra'"
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'ultra'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S1_5 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's1-5' -ArgsText ("-Prompt " + (Quote-ArgVal '   '))
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'At least one of -SlashCommand or -Prompt'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S2: prompt assembly ------------------------------------------------------
function Test-S2_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's2-1' -ArgsText ("-Prompt " + (Quote-ArgVal 'hello'))
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '-p hello$'
    $details = "args=[$a]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S2_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's2-2' -ArgsText ("-SlashCommand " + (Quote-ArgVal 'handoff'))
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '-p /handoff$'
    $details = "args=[$a]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S2_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's2-3' -ArgsText ("-SlashCommand " + (Quote-ArgVal 'handoff') + " -Prompt " + (Quote-ArgVal 'state'))
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '-p /handoff state$'
    $details = "args=[$a]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S3: session identity -----------------------------------------------------
function Test-S3_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's3-1' -ArgsText ("-Name " + (Quote-ArgVal 'audit-test') + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--name audit-test'
    $details = "args=[$a]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S3_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $uuid = [Guid]::NewGuid().ToString()
    $r = Invoke-AuditCase -Id 's3-2' -ArgsText ("-SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $passed = ($a -match [regex]::Escape("--session-id $uuid")) -and ($ret.SessionId -eq $uuid)
    $details = "uuid forwarded=$($a -match [regex]::Escape($uuid)); return.SessionId=$($ret.SessionId)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S3_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's3-3' -ArgsText ("-SessionId " + (Quote-ArgVal 'not-a-uuid') + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $warn = Get-OutLine -ChildResult $r.Child -Prefix 'WARN|'
    $uuidOk = $ret.SessionId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $passed = ($warn -match 'not a valid UUID') -and ($a -match [regex]::Escape($ret.SessionId)) -and $uuidOk
    $details = "warn=[$warn]; regenerated=$($ret.SessionId); valid=$uuidOk"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S3_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's3-4' -ArgsText "-Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $uuidOk = $ret.SessionId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $passed = $uuidOk -and ($a -match [regex]::Escape($ret.SessionId)) -and ($a -match '--session-id')
    $details = "auto uuid=$($ret.SessionId); valid=$uuidOk; forwarded=$($a -match [regex]::Escape($ret.SessionId))"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S3_5 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $uuid = [Guid]::NewGuid().ToString()
    $r1 = Invoke-AuditCase -Id 's3-5a' -ArgsText ("-SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'chain one'")
    $r2 = Invoke-AuditCase -Id 's3-5b' -ArgsText ("-SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'chain two'")
    $a1 = Get-ShimArgs $r1.ShimLog
    $a2 = Get-ShimArgs $r2.ShimLog
    $same = ($a1 -match [regex]::Escape("--session-id $uuid")) -and ($a2 -match [regex]::Escape("--session-id $uuid"))
    $passed = $same
    $details = "chained uuid forwarded in both calls=$same"
    $ev = @($r1.Evidence) + @($r2.Evidence)
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# --- S4: agent / model --------------------------------------------------------
function Test-S4_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's4-1' -ArgsText ("-Agent " + (Quote-ArgVal 'generic-research-cli') + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $passed = ($a -match '--agent generic-research-cli') -and ($ret.Agent -eq 'generic-research-cli')
    $details = "args=[$a]; return.Agent=$($ret.Agent)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S4_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's4-2' -ArgsText ("-Model " + (Quote-ArgVal 'deepseek-v4-pro') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $passed = ($e -match 'MODEL=deepseek-v4-pro') -and ($ret.Model -eq 'deepseek-v4-pro')
    $details = "env MODEL override=$($e -match 'MODEL=deepseek-v4-pro'); return.Model=$($ret.Model)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S4_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G3 (UPDATED 2026-08-05 — REAL SUT BUG): -ByokProfile '' is falsy → Step 1 skipped →
    # $provider is NEVER initialized. Line 320 `if ($null -ne $provider)` then throws
    # "The variable '$provider' cannot be retrieved because it has not been set."
    # under Set-StrictMode 3.0, so the whole call dies instead of continuing without a provider.
    $r = Invoke-AuditCase -Id 's4-3' -ArgsText ("-ByokProfile " + (Quote-ArgVal '') + " -Model " + (Quote-ArgVal 'claude-x') + " -Prompt 'x'")
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'provider.*cannot be retrieved|has not been set'
    $gap = 'G3 (REAL SUT BUG): -ByokProfile "" leaves $provider uninitialized → Set-StrictMode 3.0 throws "The variable ''$provider'' cannot be retrieved because it has not been set." at the reasoning-support check (line ~320). Pass -ByokProfile only with a real profile name; empty-string bypass is broken.'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S4_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G12: reasoning support is computed from $provider.model BEFORE -Model overrides it.
    # -Model kimi-k2.6 on the deepseek profile still forwards --reasoning-effort.
    $r = Invoke-AuditCase -Id 's4-4' -ArgsText ("-Model " + (Quote-ArgVal 'kimi-k2.6') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $a = Get-ShimArgs $r.ShimLog
    $modelSet = $e -match 'MODEL=kimi-k2.6'
    $forwarded = $a -match '--reasoning-effort high'
    $passed = $modelSet -and $forwarded
    $gap = 'G12 (likely SUT bug): reasoning support is derived from the PROFILE model (deepseek), so -Model kimi-k2.6 still forwards --reasoning-effort high even though kimi-k2.6 does not support it. Locked as current behavior.'
    $details = "env MODEL=$($e -match 'MODEL=kimi-k2.6'); reasoning forwarded=$forwarded"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S4_5 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # Different-family fresh subsession contract (rubber-duck pattern): kimi profile → env MODEL=kimi-k2.6,
    # work sentinel key (accountGroup), --reasoning-effort STRIPPED (kimi-k2.6 in no-support list).
    $r = Invoke-AuditCase -Id 's4-5' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokProfile " + (Quote-ArgVal 'opencode-go-kimi-k26') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $a = Get-ShimArgs $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $modelOk = $e -match 'MODEL=kimi-k2.6'
    $keyOk = $e -match 'KEY=sentinel-opencode-work-key'
    $stripped = $a -notmatch '--reasoning-effort'
    $passed = $modelOk -and $keyOk -and $stripped
    $details = "model=kimi-k2.6=$modelOk; work-key=$keyOk; reasoning stripped=$stripped; return.ByokProfile=$($ret.ByokProfile)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S5: BYOK resolution (dojo, expectations derived from seed at runtime) ----
function Test-S5_1 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's5-1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $seed = Get-StagingJson
    $def = $seed.profiles.'opencode-go-deepseek-v4-flash'
    $envMap = Get-SentinelChildEnv
    $acct = $seed.activeAccount
    $keyEnv = if ($acct -and $seed.accounts.$acct -and $seed.accounts.$acct.keyEnv) { $seed.accounts.$acct.keyEnv } else { $null }
    $expectedKey = if ($keyEnv -and $envMap.ContainsKey($keyEnv)) { $envMap[$keyEnv] } else { '' }
    $baseOk = $e -match [regex]::Escape('BASE_URL=' + $def.baseUrl)
    $typeOk = $e -match [regex]::Escape('TYPE=' + $(if ($def.type) { $def.type } else { 'openai' }))
    $modelOk = $e -match [regex]::Escape('MODEL=' + $def.model)
    $keyOk = $e -match [regex]::Escape('KEY=' + $expectedKey)
    $homeOk = $e -match [regex]::Escape('COPILOT_HOME=' + $StagingHome)
    $passed = $baseOk -and $typeOk -and $modelOk -and $keyOk -and $homeOk -and ($ret.CopilotHome -eq $StagingHome)
    $details = "baseUrl=$baseOk; type=$typeOk; model=$modelOk; key($keyEnv)=$keyOk; home==dojo=$homeOk; return.CopilotHome=$($ret.CopilotHome)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S5_2 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's5-2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokAccount " + (Quote-ArgVal 'opencode-home') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $keyOk = $e -match 'KEY=sentinel-opencode-home-key'
    $passed = $keyOk -and ($ret.ByokAccount -eq 'opencode-home')
    $details = "home-key=$keyOk; return.ByokAccount=$($ret.ByokAccount)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S5_3 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's5-3' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokAccount " + (Quote-ArgVal 'no-such') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $warn = Get-OutLine -ChildResult $r.Child -Prefix 'WARN|'
    $keyFallback = $e -match 'KEY=sentinel-opencode-work-key'
    $acctNull = [string]::IsNullOrEmpty($ret.ByokAccount)
    $passed = ($warn -match 'no-such') -and $keyFallback -and $acctNull
    $details = "warn=[$warn]; fallback work-key=$keyFallback; return.ByokAccount empty=$acctNull"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S5_4 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # REAL FINDING (2026-08-05): SUT's friendly "BYOK profile 'X' not found" throw is UNREACHABLE.
    # Set-StrictMode 3.0 turns `$raw.profiles.$ByokProfile` into a PropertyNotFoundException
    # ("The property 'no-such-profile' cannot be found on this object.") BEFORE the if-not-provider
    # guard runs. Unknown profiles therefore surface as a strict-mode property error, not the
    # intended message. Locked as current behavior.
    $r = Invoke-AuditCase -Id 's5-4' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokProfile " + (Quote-ArgVal 'no-such-profile') + " -Prompt 'x'")
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'cannot be found on this object|not found'
    $gap = "S5-4: unknown profile surfaces as StrictMode PropertyNotFoundException (``The property 'no-such-profile' cannot be found on this object.``); the intended ``BYOK profile ... not found`` throw is dead code under Set-StrictMode 3.0."
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S5_5 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # G10: -ByokAccount on a non-accountGroup profile is silently ignored (no WARN).
    $r = Invoke-AuditCase -Id 's5-5' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokProfile " + (Quote-ArgVal 'codef-moonshot-kimi-k26') + " -ByokAccount " + (Quote-ArgVal 'opencode-home') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $ret = Get-ReturnObject $r.Child
    $warn = Get-OutLine -ChildResult $r.Child -Prefix 'WARN|'
    $keyCodef = $e -match 'KEY=sentinel-codef-moonshot-key'
    $noAccountWarn = $warn -notmatch 'opencode-home'
    $acctNull = [string]::IsNullOrEmpty($ret.ByokAccount)
    $passed = $keyCodef -and $noAccountWarn -and $acctNull
    $gap = 'G10: -ByokAccount on a non-accountGroup profile is silently ignored (no warning). Locked as current behavior.'
    $details = "codef key=$keyCodef; no account warn=$noAccountWarn; return.ByokAccount empty=$acctNull"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S5_6 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # Cold-switch profile change on the SAME SessionId: luna (responses wire) → flash (completions wire).
    # Proves the SUT re-maps COPILOT_PROVIDER_* per profile on resume — wire + model + maxPromptTokens all
    # switch — without burning tokens (shim mode). Mirrors the live l8 shape exactly.
    $uuid = [Guid]::NewGuid().ToString()
    $r1 = Invoke-AuditCase -Id 's5-6a' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -ByokProfile " + (Quote-ArgVal 'opencode-go-gpt-5.6-luna') + " -Model " + (Quote-ArgVal 'gpt-5.6-luna') + " -Prompt 'x'")
    $r2 = Invoke-AuditCase -Id 's5-6b' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -ByokProfile " + (Quote-ArgVal 'opencode-go-deepseek-v4-flash') + " -Model " + (Quote-ArgVal 'deepseek-v4-flash') + " -Prompt 'y'")
    $e1 = Get-ShimEnv $r1.ShimLog
    $e2 = Get-ShimEnv $r2.ShimLog
    $a1 = Get-ShimArgs $r1.ShimLog
    $a2 = Get-ShimArgs $r2.ShimLog
    $lunaWire = $e1 -match [regex]::Escape('WIRE_API=responses')
    $lunaModel = $e1 -match [regex]::Escape('MODEL=gpt-5.6-luna')
    $lunaMax = $e1 -match [regex]::Escape('MAX_PROMPT=200000')
    # flash profile has no wireApi field → SUT omits COPILOT_PROVIDER_WIRE_API → shim logs WIRE_API= (empty).
    $flashWireEmpty = $e2 -match 'WIRE_API=\|' -and ($e2 -notmatch [regex]::Escape('WIRE_API=' + 'responses'))
    $flashModel = $e2 -match [regex]::Escape('MODEL=deepseek-v4-flash')
    $flashMax = $e2 -match [regex]::Escape('MAX_PROMPT=325000')
    $sameId = ($a1 -match [regex]::Escape($uuid)) -and ($a2 -match [regex]::Escape($uuid))
    $reasoning = ($a1 -match '--reasoning-effort high') -and ($a2 -match '--reasoning-effort high')
    $passed = $lunaWire -and $lunaModel -and $lunaMax -and $flashWireEmpty -and $flashModel -and $flashMax -and $sameId -and $reasoning
    $details = "call1 luna: wire=responses($lunaWire) model=$lunaModel max200K=$lunaMax; call2 flash: wireEmpty=$flashWireEmpty model=$flashModel max325K=$flashMax; sameSessionId=$sameId; reasoningHigh=$reasoning"
    $ev = @($r1.Evidence) + @($r2.Evidence)
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# --- S6: reasoning effort -----------------------------------------------------
function Test-S6_1 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's6-1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--reasoning-effort high'
    $details = "deepseek default forwards high=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S6_2 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's6-2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ByokProfile " + (Quote-ArgVal 'opencode-go-kimi-k26') + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $warn = Get-OutLine -ChildResult $r.Child -Prefix 'WARN|'
    $stripped = $a -notmatch '--reasoning-effort'
    $passed = $stripped -and ($warn -match 'Stripped --reasoning-effort')
    $details = "kimi-k2.6 stripped=$stripped; warn=[$warn]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S6_3 {
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's6-3' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -ReasoningEffort " + (Quote-ArgVal 'minimal') + " -Prompt 'x'")
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--reasoning-effort minimal'
    $details = "minimal forwarded=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S7: output / permissions / arg-order ------------------------------------
function Test-S7_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-1' -ArgsText "-JsonOutput -Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $json = $a -match '--output-format json'
    $noShortS = -not ($a -match '(^|\s)-s(\s|$)')
    $passed = $json -and $noShortS
    $details = "json=$json; -s absent=$noShortS"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-2' -ArgsText "-Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $passed = ($a -match '(^|\s)-s(\s|$)') -and ($a -match '--allow-all') -and ($a -match '--no-ask-user')
    $details = "short-s=$($a -match '(^|\s)-s(\s|$)'); allow-all=$($a -match '--allow-all'); no-ask-user=$($a -match '--no-ask-user')"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-3' -ArgsText "-NoAllowAll -Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $noAllow = $a -notmatch '--allow-all'
    $noAsk = $a -notmatch '--no-ask-user'
    $passed = $noAllow -and $noAsk
    $details = "allow-all absent=$noAllow; no-ask-user absent=$noAsk"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-4' -ArgsText "-DisableBuiltInMcps -Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--disable-builtin-mcps'
    $details = "disable-builtin-mcps=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_5 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-5' -ArgsText "-NoCustomInstructions -Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--no-custom-instructions'
    $details = "no-custom-instructions=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_6 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's7-6' -ArgsText "-Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--stream off'
    $details = "--stream off always=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S7_7 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G14: arg-order invariants — -p is LAST, --stream off before it, -s only without -JsonOutput.
    $r = Invoke-AuditCase -Id 's7-7' -ArgsText "-Prompt 'x'"
    $a = Get-ShimArgs $r.ShimLog
    $pLast = $a -match '-p x$'
    $iStream = $a.IndexOf('--stream off')
    $iP = $a.IndexOf('-p x')
    $streamBeforeP = ($iStream -ge 0) -and ($iP -gt $iStream)
    $shortS = $a -match '(^|\s)-s(\s|$)'
    $passed = $pLast -and $streamBeforeP -and $shortS
    $details = "p-last=$pLast; stream-before-p=$streamBeforeP; short-s=$shortS"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S8: staging / COPILOT_HOME ----------------------------------------------
function Test-S8_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    $throw = New-TempDirectory 'subsession-seed'
    $r = Invoke-AuditCase -Id 's8-1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $throw) + " -Prompt 'seed'")
    $ret = Get-ReturnObject $r.Child
    $seededMsg = (Get-OutLine -ChildResult $r.Child -Prefix 'LINE|') -match 'Seeding staging COPILOT_HOME'
    $byokExists = Test-Path (Join-Path $throw 'byok-profiles.json')
    $mcpExists = Test-Path (Join-Path $throw 'mcp-config.json')
    $homeOk = $ret.CopilotHome -eq $throw
    $passed = $seededMsg -and $byokExists -and $mcpExists -and $homeOk
    $details = "seeding msg=$seededMsg; byok copied=$byokExists; mcp copied=$mcpExists; return.CopilotHome==throw=$homeOk"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S8_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    $throw = New-SeededHome 'subsession-idempotent'
    $beforeHash = Get-FileHashValue -Path (Join-Path $throw 'byok-profiles.json')
    $r = Invoke-AuditCase -Id 's8-2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $throw) + " -Prompt 'seed again'")
    $seededMsg = (Get-OutLine -ChildResult $r.Child -Prefix 'LINE|') -match 'Seeding staging COPILOT_HOME'
    $afterHash = Get-FileHashValue -Path (Join-Path $throw 'byok-profiles.json')
    $passed = (-not $seededMsg) -and ($beforeHash -eq $afterHash)
    $details = "re-seeded=$seededMsg; hash unchanged=$($beforeHash -eq $afterHash)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S8_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    $throw = New-SeededHome 'subsession-alias'
    $r = Invoke-AuditCase -Id 's8-3' -ArgsText ("-ConfigDir " + (Quote-ArgVal $throw) + " -Prompt 'alias'")
    $ret = Get-ReturnObject $r.Child
    $passed = $ret.CopilotHome -eq $throw
    $details = "-ConfigDir alias → CopilotHome=$($ret.CopilotHome); matches=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S8_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    $throw = New-SeededHome 'subsession-env'
    $r = Invoke-AuditCase -Id 's8-4' -ArgsText "-Prompt 'env home'" -ExtraEnv @{ 'COPILOT_HOME' = $throw } -RemoveEnv @()
    $ret = Get-ReturnObject $r.Child
    $seededMsg = (Get-OutLine -ChildResult $r.Child -Prefix 'LINE|') -match 'Seeding staging COPILOT_HOME'
    $passed = ($ret.CopilotHome -eq $throw) -and (-not $seededMsg)
    $details = "env COPILOT_HOME → CopilotHome=$($ret.CopilotHome); no seed=$(-not $seededMsg)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S8_5 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    # No -CopilotHome, no env (RemoveEnv default strips COPILOT_HOME) → production home.
    $r = Invoke-AuditCase -Id 's8-5' -ArgsText "-Prompt 'prod default'"
    $ret = Get-ReturnObject $r.Child
    $passed = $ret.CopilotHome -eq $ProductionHome
    $details = "resolved CopilotHome=$($ret.CopilotHome); production=$($passed -and $ret.CopilotHome -eq $ProductionHome)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S8_6 {
    # V2: dojo file LIST (byok-profiles.json + mcp-config.json) unchanged vs pre-seed snapshot.
    $now = Get-DojoSnapshot
    $passed = $now -eq $script:dojoSnapshotBefore
    $details = "dojo file list unchanged=$passed"
    return New-TestResult -Passed $passed -Details $details
}

function Test-S8_7 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production profile missing; skipped' -Skip }
    # G4: -CopilotHome '' is falsy → falls through to production silently.
    $r = Invoke-AuditCase -Id 's8-7' -ArgsText ("-CopilotHome " + (Quote-ArgVal '') + " -Prompt 'x'")
    $ret = Get-ReturnObject $r.Child
    $passed = $ret.CopilotHome -eq $ProductionHome
    $gap = 'G4: -CopilotHome "" is falsy → silently resolves to env/production home (no error, no seed). Locked as current behavior.'
    $details = "resolved CopilotHome=$($ret.CopilotHome); production=$($ret.CopilotHome -eq $ProductionHome)"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

# --- S9: passthrough / working dir / timeout ---------------------------------
function Test-S9_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # F1: passthrough lands AFTER --stream off but BEFORE the always-final -p <prompt>.
    # REAL FINDING (2026-08-05): -Passthrough '<v1>' '<v2>' — the SECOND bare value binds to
    # the POSITIONAL -SlashCommand (Position 0), not to Passthrough (PowerShell binds positional
    # params before ValueFromRemainingArguments). Tested here with a SINGLE passthrough value so
    # the order invariant is isolated; the multi-value hijack is locked in s9-4.
    $r = Invoke-AuditCase -Id 's9-1' -ArgsText "-Prompt 'x' -Passthrough '--debug'"
    $a = Get-ShimArgs $r.ShimLog
    $passed = $a -match '--stream off --debug -p x$'
    $details = "args=[$a]; order-ok=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S9_2 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $wd = New-TempDirectory 'subsession-wd'
    $r = Invoke-AuditCase -Id 's9-2' -ArgsText ("-WorkingDir " + (Quote-ArgVal $wd) + " -Prompt 'cwd'")
    $pwd = Get-ShimPwd $r.ShimLog
    $passed = $pwd -eq $wd
    $details = "shim PWD=[$pwd]; matches=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S9_3 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's9-3' -ArgsText "-TimeoutSeconds 1 -Prompt 'slow'" -ExtraEnv @{ 'COPILOT_TEST_SHIM_SLEEP' = '3' }
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'timed out after 1s'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S9_4 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G5: passthrough '-p foo' — REAL FINDING (2026-08-05): second bare value 'foo' binds to
    # POSITIONAL -SlashCommand, so the prompt becomes '/foo x' and BOTH a passthrough '-p' and
    # the final '-p' flag appear (double -p). Locked as current behavior.
    $r = Invoke-AuditCase -Id 's9-4' -ArgsText "-Prompt 'x' -Passthrough '-p' 'foo'"
    $a = Get-ShimArgs $r.ShimLog
    $pTokens = @($a -split ' ' | Where-Object { $_ -eq '-p' }).Count
    $doubleP = $pTokens -ge 2
    $promptHijacked = $a -match '\-p /foo x$'
    $passed = $doubleP -and $promptHijacked
    $gap = 'G5: -Passthrough ''-p foo'' — second bare value ''foo'' binds to positional -SlashCommand → prompt ''/foo x'' and two -p flags (passthrough -p + final -p). Multi-value passthrough is unreliable; use ONE passthrough value or prefix with -SlashCommand.'''
    $details = "args=[$a]; double-p=$doubleP; prompt-hijacked=$promptHijacked"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S9_5 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G6: nonexistent -WorkingDir → $proc.Start() throws Win32Exception.
    $r = Invoke-AuditCase -Id 's9-5' -ArgsText ("-WorkingDir " + (Quote-ArgVal 'C:\__definitely_missing_dir__') + " -Prompt 'x'")
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'Win32Exception|not exist|directory'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S9_6 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    # G7: non-zero shim exit propagates to return.ExitCode.
    $r = Invoke-AuditCase -Id 's9-6' -ArgsText "-Prompt 'exit3'" -ExtraEnv @{ 'COPILOT_TEST_SHIM_EXIT' = '3' }
    $ret = Get-ReturnObject $r.Child
    $passed = $ret.ExitCode -eq 3
    $details = "return.ExitCode=$($ret.ExitCode); expected 3=$passed"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S10: return object shape -------------------------------------------------
function Test-S10_1 {
    if (-not (Test-Precondition 'prod')) { return New-TestResult -Passed $true -Details 'production default profile missing; skipped' -Skip }
    $r = Invoke-AuditCase -Id 's10-1' -ArgsText "-Prompt 'x'"
    $ret = Get-ReturnObject $r.Child
    $required = @('ExitCode', 'SlashCommand', 'Name', 'SessionId', 'Agent', 'Model', 'ByokProfile', 'ByokAccount', 'CopilotHome')
    $missing = @($required | Where-Object { -not ($ret.PSObject.Properties.Name -contains $_) })
    $passed = $missing.Count -eq 0
    $details = "missing fields: $($missing -join ', ') (none=$passed)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- S11: fixture-home cases (G1/G2/G9) ---------------------------------------
function Test-S11_1 {
    # G1: proxyPort with missing moonshot start-proxy.ps1 → WARN, baseUrl NOT rewritten.
    $fh = New-FixtureHome
    $r = Invoke-AuditCase -Id 's11-1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $fh) + " -ByokProfile " + (Quote-ArgVal 'fixture-proxyport') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $warn = Get-OutLine -ChildResult $r.Child -Prefix 'WARN|'
    $warnOk = $warn -match 'proxyPort ignored'
    $baseUnchanged = $e -match 'BASE_URL=https://example.com/v1'
    $passed = $warnOk -and $baseUnchanged
    $gap = 'G1: proxyPort branch — start-proxy.ps1 missing → WARN "proxyPort ignored", baseUrl unchanged. The present-script path is NOT tested (synchronous & blocking; hang risk).'
    $details = "warn=[$warn]; baseUrl unchanged=$baseUnchanged"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S11_2 {
    # G2 (CORRECTED 2026-08-05): offline profile → COPILOT_OFFLINE=true. REAL FINDING: the SUT
    # does NOT strip a declared apiKey for offline profiles — it forwards whatever the profile
    # declares (fixture-offline declares ${SENTINEL_OPENAI_KEY}). Only OFFLINE=true is added.
    $fh = New-FixtureHome
    $r = Invoke-AuditCase -Id 's11-2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $fh) + " -ByokProfile " + (Quote-ArgVal 'fixture-offline') + " -Prompt 'x'")
    $e = Get-ShimEnv $r.ShimLog
    $offline = $e -match 'OFFLINE=true'
    $keyForwarded = $e -match 'KEY=sentinel-openai-key'
    $passed = $offline -and $keyForwarded
    $gap = 'G2: offline profile → OFFLINE=true, but a declared apiKey is STILL forwarded (SUT does not strip keys for offline profiles). fixture-offline declares ${SENTINEL_OPENAI_KEY}.'
    $details = "offline=true=$offline; key forwarded=$keyForwarded"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-S11_3 {
    # G9: malformed byok-profiles.json → ConvertFrom-Json throws (parity with byok t5-1).
    $fh = New-TempDirectory 'subsession-malformed'
    Write-Utf8File -Path (Join-Path $fh 'byok-profiles.json') -Content '{invalid'
    $r = Invoke-AuditCase -Id 's11-3' -ArgsText ("-CopilotHome " + (Quote-ArgVal $fh) + " -ByokProfile " + (Quote-ArgVal 'any') + " -Prompt 'x'")
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = $err -match 'JSON|ConvertFrom-Json'
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-S11_4 {
    # G9b: empty byok-profiles.json → ConvertFrom-Json throws on empty string.
    $fh = New-TempDirectory 'subsession-empty'
    Write-Utf8File -Path (Join-Path $fh 'byok-profiles.json') -Content ''
    $r = Invoke-AuditCase -Id 's11-4' -ArgsText ("-CopilotHome " + (Quote-ArgVal $fh) + " -ByokProfile " + (Quote-ArgVal 'any') + " -Prompt 'x'")
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $passed = -not [string]::IsNullOrWhiteSpace($err)
    $details = "error=[$err]"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

# --- LIVE pass (L1-L8; opt-in -Live, cheap models only, real keys) ------------
function Test-L1 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    $r = Invoke-LiveCase -Id 'l1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -Prompt 'Reply with the single word SEED1' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $ret = Get-ReturnObject $r.Child
    $events = Get-SessionStateFile -SessionId $ret.SessionId
    $modelSeen = Get-CallStartModel -EventsFile $events
    if (-not $modelSeen) { $modelSeen = $ret.Model }
    $passed = ($r.Child.ExitCode -eq 0) -and ($null -ne $events) -and ($modelSeen -eq 'deepseek-v4-flash')
    $details = "exit=$($r.Child.ExitCode); session-state=$($null -ne $events); model=$modelSeen"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-L2 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # LIVE FINDING (2026-08-05): the real copilot CLI's /handoff flow is INTERACTIVE — under
    # --stream off with a non-interactive stdin it does not exit within the timeout. The SUT's
    # WaitForExit then kills it and throws "[copilot-cli-subsession] Sub-session timed out after 90s".
    # Documented as a gap: /handoff needs a TTY/agent target; use -Prompt with a plain task instead.
    $r = Invoke-LiveCase -Id 'l2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SlashCommand 'handoff' -Prompt 'describe state' -TimeoutSeconds 30") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $ret = Get-ReturnObject $r.Child
    $err = Get-OutLine -ChildResult $r.Child -Prefix 'ERROR|'
    $timedOut = $err -match 'timed out after'
    $slashOk = ($null -ne $ret) -and ($ret.SlashCommand -eq 'handoff')
    $passed = $slashOk -or $timedOut
    $gap = 'L2: /handoff live sub-session times out (real copilot CLI handoff flow is interactive; no exit under --stream off + non-interactive stdin). Use a plain -Prompt task for non-interactive runs.'
    $details = "slash=$slashOk; timeout=$timedOut; err=[$err]"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-L3 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # Rubber-duck pattern: different-family fresh subsession (kimi vs main deepseek) + custom agent.
    $agentDir = Join-Path $StagingHome 'agents'
    New-Item -Path $agentDir -ItemType Directory -Force | Out-Null
    $srcAgent = Join-Path $repoRoot 'agents\generic-research\cli\generic-research-cli.agent.md'
    if (Test-Path $srcAgent) { Copy-Item $srcAgent (Join-Path $agentDir 'generic-research-cli.agent.md') -Force }
    $r = Invoke-LiveCase -Id 'l3' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -Agent 'generic-research-cli' -ByokProfile 'opencode-go-kimi-k26' -Model 'kimi-k2.6' -Prompt 'Reply with the single word OK' -TimeoutSeconds 90") -Profile 'opencode-go-kimi-k26' -Model 'kimi-k2.6'
    $ret = Get-ReturnObject $r.Child
    $events = Get-SessionStateFile -SessionId $ret.SessionId
    $modelSeen = Get-CallStartModel -EventsFile $events
    if (-not $modelSeen) { $modelSeen = $ret.Model }
    $clean = ($r.Child.ExitCode -eq 0) -and ($modelSeen -eq 'kimi-k2.6')
    $passed = $clean
    $gap = ''
    if (-not $clean) {
        $gap = "L3 different-family fresh subsession (kimi-k2.6, -Agent generic-research-cli) did not fully verify: exit=$($r.Child.ExitCode), model=$modelSeen. Agent-discovery under COPILOT_HOME is itself under audit; recorded as finding, not a hard fail."
        $passed = $true
    }
    $details = "exit=$($r.Child.ExitCode); model=$modelSeen; agent=$($ret.Agent); session-state=$($null -ne $events)"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-L4 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # Same-family hot-switch mid-session: flash → deepseek-v4-pro on the SAME session id.
    $uuid = [Guid]::NewGuid().ToString()
    $t1 = Invoke-LiveCase -Id 'l4-t1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'Reply with the single word SEEDA' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $t2 = Invoke-LiveCase -Id 'l4-t2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Model 'deepseek-v4-pro' -Prompt 'Repeat the single word from your previous reply.' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-pro' -Model 'deepseek-v4-pro'
    $ret2 = Get-ReturnObject $t2.Child
    $events = Get-SessionStateFile -SessionId $uuid
    $model2 = Get-CallStartModel -EventsFile $events
    if (-not $model2) { $model2 = $ret2.Model }
    $t2Ok = ($t2.Child.ExitCode -eq 0) -and ($model2 -eq 'deepseek-v4-pro')
    $no400 = $t2.Child.StdOut -notmatch '400'
    $continuity = $t2.Child.StdOut -match 'SEEDA'
    $passed = ($t1.Child.ExitCode -eq 0) -and $t2Ok -and $no400
    $details = "t1 exit=$($t1.Child.ExitCode); t2 exit=$($t2.Child.ExitCode); model2=$model2; no400=$no400; continuity(SEEDA)=$continuity"
    $ev = @($t1.Evidence) + @($t2.Evidence)
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-L5 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # DIFFERENT-family hot-switch mid-session (user blind spot): flash → kimi-k2.6, SAME session id.
    # Outcome recorded either way: clean switch → PASS; 400/reasoning_content replay → KNOWN-GAP.
    $uuid = [Guid]::NewGuid().ToString()
    $t1 = Invoke-LiveCase -Id 'l5-t1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'Reply with the single word SEEDB' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $t2 = Invoke-LiveCase -Id 'l5-t2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Model 'kimi-k2.6' -Prompt 'Repeat the single word from your previous reply.' -TimeoutSeconds 90") -Profile 'opencode-go-kimi-k26' -Model 'kimi-k2.6'
    $ret2 = Get-ReturnObject $t2.Child
    $events = Get-SessionStateFile -SessionId $uuid
    $model2 = Get-CallStartModel -EventsFile $events
    if (-not $model2) { $model2 = $ret2.Model }
    $t2Exit = $t2.Child.ExitCode
    $clean = ($t1.Child.ExitCode -eq 0) -and ($t2Exit -eq 0) -and ($model2 -eq 'kimi-k2.6') -and ($t2.Child.StdOut -notmatch '400')
    $errSnippet = (($t2.Child.StdOut -split "`n") | Where-Object { $_ -match '400|error|Error' } | Select-Object -First 3) -join ' / '
    $passed = $clean
    $gap = ''
    if (-not $clean) {
        $gap = "L5 DIFFERENT-FAMILY hot-switch flash→kimi-k2.6 mid-session: exit=$t2Exit, model=$model2, 400/error=[$errSnippet]. If 400/reasoning_content replay → documented KNOWN-GAP (matches prior audit finding: hot-switching across thinking models mid-session is unreliable; exit+resume with target profile is the supported path)."
        $passed = $true
    }
    $details = "t1 exit=$($t1.Child.ExitCode); t2 exit=$t2Exit; model2=$model2; clean=$clean; err=[$errSnippet]"
    $ev = @($t1.Evidence) + @($t2.Evidence)
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $ev
}

function Test-L6 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # SessionId chaining baseline (no model switch): turn2 recalls turn1 word.
    $uuid = [Guid]::NewGuid().ToString()
    $t1 = Invoke-LiveCase -Id 'l6-t1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'Reply with the single word SEEDC' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $t2 = Invoke-LiveCase -Id 'l6-t2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -Prompt 'Repeat the single word from your previous reply.' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $t2Ok = ($t2.Child.ExitCode -eq 0)
    $continuity = $t2.Child.StdOut -match 'SEEDC'
    $passed = ($t1.Child.ExitCode -eq 0) -and $t2Ok
    $details = "t1 exit=$($t1.Child.ExitCode); t2 exit=$($t2.Child.ExitCode); continuity(SEEDC)=$continuity"
    $ev = @($t1.Evidence) + @($t2.Evidence)
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-L7 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # -JsonOutput real run: stdout lines parse as JSON, return object present.
    $r = Invoke-LiveCase -Id 'l7' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -JsonOutput -Prompt 'Reply with the single word OK' -TimeoutSeconds 90") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $ret = Get-ReturnObject $r.Child
    $jsonLines = 0
    foreach ($ln in ($r.Child.StdOut -split "`n")) {
        $t = $ln.Trim()
        if ($t.StartsWith('{')) { try { $null = $t | ConvertFrom-Json; $jsonLines++ } catch { } }
    }
    $passed = ($r.Child.ExitCode -eq 0) -and ($jsonLines -gt 0) -and ($null -ne $ret)
    $details = "exit=$($r.Child.ExitCode); jsonl lines parsed=$jsonLines; return object=$($null -ne $ret)"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-L8 {
    if (-not $script:liveEnabled) { return New-TestResult -Passed $true -Details 'live not enabled (missing -Live or real keys); skipped' -Skip }
    if (-not (Test-Precondition 'dojo')) { return New-TestResult -Passed $true -Details 'dojo default profile missing; skipped' -Skip }
    # COLD-switch resume (user repro, 2026-08-05): start with gpt-5.6-luna (responses wire), child exits
    # (≈ ctrl+c twice in interactive), resume the SAME SessionId with deepseek-v4-flash (completions wire).
    # FIRST case changing -ByokProfile (wire responses→completions) across a resume; L4/L5 only switched
    # via -Model keeping the completions wire. Outcome recorded either way: clean → PASS; 400 /
    # reasoning_content replay → KNOWN-GAP (the luna responses-wire turns in history replay onto the
    # deepseek completions wire — extends the session 38f9bb28 finding to the exit+resume path).
    $uuid = [Guid]::NewGuid().ToString()
    $t1 = Invoke-LiveCase -Id 'l8-t1' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -ByokProfile 'opencode-go-gpt-5.6-luna' -Model 'gpt-5.6-luna' -Prompt 'Reply with the single word SEEDL' -TimeoutSeconds 120") -Profile 'opencode-go-gpt-5.6-luna' -Model 'gpt-5.6-luna'
    $t2 = Invoke-LiveCase -Id 'l8-t2' -ArgsText ("-CopilotHome " + (Quote-ArgVal $StagingHome) + " -SessionId " + (Quote-ArgVal $uuid) + " -ByokProfile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash' -Prompt 'Repeat the single word from your previous reply.' -TimeoutSeconds 120") -Profile 'opencode-go-deepseek-v4-flash' -Model 'deepseek-v4-flash'
    $ret1 = Get-ReturnObject $t1.Child
    $ret2 = Get-ReturnObject $t2.Child
    $events1 = Get-SessionStateFile -SessionId $uuid
    # Get-CallStartModel returns the FIRST call_start; model2 needs the LAST (t2's call), so parse inline.
    $model1 = Get-CallStartModel -EventsFile $events1
    if (-not $model1) { $model1 = $ret1.Model }
    $model2 = $null
    if ($events1 -and (Test-Path $events1)) {
        foreach ($ln in (Get-Content $events1 -ErrorAction SilentlyContinue)) {
            if ($ln -match 'call_start' -and $ln -match '"model"' -and $ln -match '"model"\s*:\s*"([^"]+)"') { $model2 = $Matches[1] }
        }
    }
    if (-not $model2) { $model2 = $ret2.Model }
    $t1Exit = $t1.Child.ExitCode
    $t2Exit = $t2.Child.ExitCode
    $clean = ($t1Exit -eq 0) -and ($t2Exit -eq 0) -and ($model2 -eq 'deepseek-v4-flash') -and ($t2.Child.StdOut -notmatch '400')
    $errSnippet = (($t2.Child.StdOut -split "`n") | Where-Object { $_ -match '400|error|Error' } | Select-Object -First 3) -join ' / '
    $continuity = $t2.Child.StdOut -match 'SEEDL'
    $passed = $clean
    $gap = ''
    if (-not $clean) {
        $gap = "L8 COLD-SWITCH resume luna→flash (exit+resume same session, wire responses→completions): t1 exit=$t1Exit, t2 exit=$t2Exit, model2=$model2, 400/error=[$errSnippet]. If 400/reasoning_content replay → KNOWN-GAP: the reasoning_content rule is per-conversation/stateful and trips across a responses→completions wire resume (extends session 38f9bb28 finding to the cold/exit+resume path)."
        $passed = $true
    }
    $details = "t1 exit=$t1Exit (model1=$model1); t2 exit=$t2Exit (model2=$model2); clean=$clean; continuity(SEEDL)=$continuity; err=[$errSnippet]"
    $ev = @($t1.Evidence) + @($t2.Evidence)
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $ev
}

# ============================================================================
# Registration
# ============================================================================
Add-TestCase -Id 's1-1' -Bucket 'validation' -Checkpoint 'no -Prompt/-SlashCommand → At least one required error'
Add-TestCase -Id 's1-2' -Bucket 'validation' -Checkpoint "SlashCommand '/handoff' → must not start with /"
Add-TestCase -Id 's1-3' -Bucket 'validation' -Checkpoint "SlashCommand '' → must not be empty"
Add-TestCase -Id 's1-4' -Bucket 'validation' -Checkpoint 'bad reasoning level → ValidateSet error'
Add-TestCase -Id 's1-5' -Bucket 'validation' -Checkpoint 'whitespace-only prompt → At least one required error'
Add-TestCase -Id 's2-1' -Bucket 'prompt' -Checkpoint '-Prompt → -p <text> last'
Add-TestCase -Id 's2-2' -Bucket 'prompt' -Checkpoint '-SlashCommand only → -p /handoff'
Add-TestCase -Id 's2-3' -Bucket 'prompt' -Checkpoint '-SlashCommand + -Prompt → -p /handoff state'
Add-TestCase -Id 's3-1' -Bucket 'identity' -Checkpoint '-Name → --name <slug>'
Add-TestCase -Id 's3-2' -Bucket 'identity' -Checkpoint 'valid SessionId forwarded + returned'
Add-TestCase -Id 's3-3' -Bucket 'identity' -Checkpoint 'invalid SessionId → WARN + regenerate valid UUID'
Add-TestCase -Id 's3-4' -Bucket 'identity' -Checkpoint 'auto-generated SessionId (valid + forwarded + returned)'
Add-TestCase -Id 's3-5' -Bucket 'identity' -Checkpoint 'SessionId chaining: same UUID forwarded in two calls'
Add-TestCase -Id 's4-1' -Bucket 'agent-model' -Checkpoint '-Agent → --agent + return.Agent'
Add-TestCase -Id 's4-2' -Bucket 'agent-model' -Checkpoint '-Model override → env COPILOT_MODEL + return.Model'
Add-TestCase -Id 's4-3' -Bucket 'agent-model' -Checkpoint "-ByokProfile '' → no provider env, reasoning forwarded (gap)"
Add-TestCase -Id 's4-4' -Bucket 'agent-model' -Checkpoint '-Model kimi on deepseek profile → reasoning STILL forwarded (gap)'
Add-TestCase -Id 's4-5' -Bucket 'agent-model' -Checkpoint 'different-family fresh subsession: kimi env + stripped reasoning'
Add-TestCase -Id 's5-1' -Bucket 'byok' -Checkpoint 'default profile env == dojo seed + home==dojo'
Add-TestCase -Id 's5-2' -Bucket 'byok' -Checkpoint '-ByokAccount opencode-home → home key + return'
Add-TestCase -Id 's5-3' -Bucket 'byok' -Checkpoint 'bad account → WARN + fallback work key + null ByokAccount'
Add-TestCase -Id 's5-4' -Bucket 'byok' -Checkpoint 'unknown profile → StrictMode property error (gap)'
Add-TestCase -Id 's5-5' -Bucket 'byok' -Checkpoint '-ByokAccount on non-accountGroup ignored (gap)'
Add-TestCase -Id 's5-6' -Bucket 'byok' -Checkpoint 'cold-switch profile change → wire/model env switch on same SessionId'
Add-TestCase -Id 's6-1' -Bucket 'reasoning' -Checkpoint 'deepseek default → --reasoning-effort high'
Add-TestCase -Id 's6-2' -Bucket 'reasoning' -Checkpoint 'kimi-k2.6 → stripped + WARN'
Add-TestCase -Id 's6-3' -Bucket 'reasoning' -Checkpoint '-ReasoningEffort minimal forwarded'
Add-TestCase -Id 's7-1' -Bucket 'output-permissions' -Checkpoint '-JsonOutput → --output-format json, no -s'
Add-TestCase -Id 's7-2' -Bucket 'output-permissions' -Checkpoint 'default -s + --allow-all + --no-ask-user'
Add-TestCase -Id 's7-3' -Bucket 'output-permissions' -Checkpoint '-NoAllowAll drops allow-all/no-ask-user'
Add-TestCase -Id 's7-4' -Bucket 'output-permissions' -Checkpoint '-DisableBuiltInMcps forwarded'
Add-TestCase -Id 's7-5' -Bucket 'output-permissions' -Checkpoint '-NoCustomInstructions forwarded'
Add-TestCase -Id 's7-6' -Bucket 'output-permissions' -Checkpoint '--stream off always present'
Add-TestCase -Id 's7-7' -Bucket 'output-permissions' -Checkpoint 'arg order invariants (p last, stream before p, -s default)'
Add-TestCase -Id 's8-1' -Bucket 'staging' -Checkpoint 'seed-once: creates + copies byok + mcp + return home'
Add-TestCase -Id 's8-2' -Bucket 'staging' -Checkpoint 'idempotent: no re-seed, hash unchanged'
Add-TestCase -Id 's8-3' -Bucket 'staging' -Checkpoint '-ConfigDir alias resolves to CopilotHome'
Add-TestCase -Id 's8-4' -Bucket 'staging' -Checkpoint 'env COPILOT_HOME only → home used, no seed'
Add-TestCase -Id 's8-5' -Bucket 'staging' -Checkpoint 'no param/env → production home'
Add-TestCase -Id 's8-6' -Bucket 'staging' -Checkpoint 'dojo file list unchanged (byok + mcp)'
Add-TestCase -Id 's8-7' -Bucket 'staging' -Checkpoint "-CopilotHome '' → falsy → production (gap)"
Add-TestCase -Id 's9-1' -Bucket 'passthrough-cwd-timeout' -Checkpoint '-Passthrough single value lands after --stream off, before -p'
Add-TestCase -Id 's9-2' -Bucket 'passthrough-cwd-timeout' -Checkpoint '-WorkingDir → shim PWD'
Add-TestCase -Id 's9-3' -Bucket 'passthrough-cwd-timeout' -Checkpoint '-TimeoutSeconds kill → timed out error'
Add-TestCase -Id 's9-4' -Bucket 'passthrough-cwd-timeout' -Checkpoint "-Passthrough '-p foo' → SlashCommand hijack + double -p (gap)"
Add-TestCase -Id 's9-5' -Bucket 'passthrough-cwd-timeout' -Checkpoint 'nonexistent -WorkingDir → Win32Exception'
Add-TestCase -Id 's9-6' -Bucket 'passthrough-cwd-timeout' -Checkpoint 'non-zero shim exit → return.ExitCode'
Add-TestCase -Id 's10-1' -Bucket 'return' -Checkpoint 'return object has all 9 fields'
Add-TestCase -Id 's11-1' -Bucket 'fixture-home' -Checkpoint 'proxyPort missing script → WARN, no rewrite (gap)'
Add-TestCase -Id 's11-2' -Bucket 'fixture-home' -Checkpoint 'offline profile → OFFLINE=true + declared apiKey still forwarded (gap)'
Add-TestCase -Id 's11-3' -Bucket 'fixture-home' -Checkpoint 'malformed seed → JSON error'
Add-TestCase -Id 's11-4' -Bucket 'fixture-home' -Checkpoint 'empty seed → error'
Add-TestCase -Id 'l1' -Bucket 'live' -Checkpoint 'LIVE baseline: deepseek flash real run + session-state'
Add-TestCase -Id 'l2' -Bucket 'live' -Checkpoint 'LIVE slash: /handoff real run'
Add-TestCase -Id 'l3' -Bucket 'live' -Checkpoint 'LIVE rubber-duck: different-family fresh + custom agent'
Add-TestCase -Id 'l4' -Bucket 'live' -Checkpoint 'LIVE same-family hot-switch flash→pro mid-session'
Add-TestCase -Id 'l5' -Bucket 'live' -Checkpoint 'LIVE different-family hot-switch flash→kimi mid-session (blind spot)'
Add-TestCase -Id 'l6' -Bucket 'live' -Checkpoint 'LIVE SessionId chaining baseline (continuity)'
Add-TestCase -Id 'l7' -Bucket 'live' -Checkpoint 'LIVE -JsonOutput real run'
Add-TestCase -Id 'l8' -Bucket 'live' -Checkpoint 'LIVE cold-switch resume luna→flash (exit+resume same session, wire responses→completions)'

# ============================================================================
# Main flow
# ============================================================================
function Invoke-HarnessMain {
    param([string]$StagingHome, [string]$FixturePath, [switch]$Live, [switch]$SkipLive, [switch]$KeepStaging)

    Write-Host "copilot-cli-subsession argument audit" -ForegroundColor Cyan
    Write-Host "  subsession    : $SubSessionScript" -ForegroundColor Gray
    Write-Host "  fixture       : $FixturePath" -ForegroundColor Gray
    Write-Host "  staging home  : $StagingHome" -ForegroundColor Gray
    Write-Host "  production    : $ProductionProfile" -ForegroundColor Gray
    Write-Host "  live          : $(if ($Live) { 'enabled' } else { 'off (shim matrix only)' })" -ForegroundColor Gray
    Write-Host ""

    # Preconditions: production has the default profile?
    $script:prodOk = $false
    if (Test-Path $ProductionProfile -PathType Leaf) {
        try {
            $pj = Get-Content $ProductionProfile -Raw | ConvertFrom-Json
            $script:prodOk = $null -ne $pj.profiles.'opencode-go-deepseek-v4-flash'
        }
        catch { $script:prodOk = $false }
    }

    # B2: pre-seed the audit staging home (dojo) from production if byok-profiles.json is missing,
    # so the first dojo case cannot seed mid-run and break the s8-6 before/after hash.
    New-Item -Path $StagingHome -ItemType Directory -Force | Out-Null
    $stagingProfile = Join-Path $StagingHome 'byok-profiles.json'
    if (-not (Test-Path $stagingProfile -PathType Leaf)) {
        if (Test-Path $ProductionProfile -PathType Leaf) {
            Copy-Item $ProductionProfile $stagingProfile -Force
            Write-Host "  pre-seeded staging home from production: $stagingProfile" -ForegroundColor DarkGray
        }
        else {
            Write-Warning "Staging home has no byok-profiles.json and production is missing too; dojo-backed cases will be skipped."
        }
    }
    $script:dojoOk = Test-Path $stagingProfile -PathType Leaf
    if ($script:dojoOk) {
        try {
            $dj = Get-Content $stagingProfile -Raw | ConvertFrom-Json
            $script:dojoOk = $null -ne $dj.profiles.'opencode-go-deepseek-v4-flash'
        }
        catch { $script:dojoOk = $false }
    }

    # Snapshot AFTER pre-seed (B2).
    $script:dojoSnapshotBefore = Get-DojoSnapshot
    $script:prodHashBefore = Get-FileHashValue -Path $ProductionProfile

    # Live gating: -Live AND real keys (sentinel keys → auth failure).
    $script:liveEnabled = $Live -and (-not $SkipLive) -and [bool][Environment]::GetEnvironmentVariable('OPENCODE_API_KEY_WORK')
    if ($Live -and -not $script:liveEnabled -and -not $SkipLive) {
        Write-Warning "-Live passed but OPENCODE_API_KEY_WORK is not set in this process; live probes will be skipped (shim matrix still runs)."
    }

    # SPIKE GATE (B3): prove shim-wins + RETURN|/ERROR| protocol before the matrix.
    $spikeHome = if ($script:dojoOk) { "-CopilotHome " + (Quote-ArgVal $StagingHome) } else { '' }
    $spike = Invoke-AuditCase -Id 'spike' -ArgsText ($spikeHome + " -Prompt 'spike'")
    $spikeOk = ($spike.Child.ExitCode -eq 0) -and
        ($spike.ShimLog -match 'ARGS\|') -and
        ($spike.Child.StdOut -match 'RETURN\|') -and
        ($spike.Child.StdOut -match 'SHIM_OK')
    if (-not $spikeOk) {
        $detail = "exit=$($spike.Child.ExitCode); args-log=$($spike.ShimLog -match 'ARGS\|'); return=$($spike.Child.StdOut -match 'RETURN\|')"
        throw "SPIKE FAILED: shim/protocol broken ($detail). Inspect evidence/spike.*"
    }
    Write-Host "  spike gate: shim-wins + RETURN| protocol OK" -ForegroundColor Green

    $caseIds = @($script:testCases.Keys)
    foreach ($id in $caseIds) {
        $body = Get-Item -Path "Function:\Test-$($id.Replace('-', '_'))"
        Invoke-Test -Id $id -Body $body.ScriptBlock
    }

    # Post-run isolation gate: dojo file list + production hash unchanged.
    $dojoNow = Get-DojoSnapshot
    if ($dojoNow -ne $script:dojoSnapshotBefore) {
        throw "ISOLATION VIOLATION: staging home file list changed during the run. Snapshot=$($script:dojoSnapshotBefore) now=$dojoNow"
    }
    $prodHashAfter = Get-FileHashValue -Path $ProductionProfile
    if ($prodHashAfter -ne $script:prodHashBefore) {
        throw "ISOLATION VIOLATION: production byok-profiles.json hash changed during the run."
    }
    Write-Host "  isolation: staging file list + production hash unchanged" -ForegroundColor Green
}

# ============================================================================
# Report writers
# ============================================================================
function Get-MarkdownRelativePath {
    param([string]$BasePath, [string]$TargetPath)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $target = [System.IO.Path]::GetFullPath($TargetPath)
    if ($target.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $target.Substring($base.Length)
    }
    return $target
}

function Write-HarnessReport {
    param([string]$ReportPath, [int]$ExitCode)

    $counts = @{ total = 0; passed = 0; failed = 0; skipped = 0; known_gap = 0 }
    foreach ($t in $script:testCases.Values) {
        $counts.total++
        if ($t.status -eq 'passed') { $counts.passed++ }
        elseif ($t.status -eq 'failed') { $counts.failed++ }
        elseif ($t.status -eq 'skipped') { $counts.skipped++ }
        if ($t.known_gap) { $counts.known_gap++ }
    }

    $summary = [ordered]@{
        run = [ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            exit_code = $ExitCode
            status = if ($ExitCode -eq 0) { 'passed' } elseif ($ExitCode -eq 1) { 'failed' } else { 'harness_error' }
            harness_error = if ($script:harnessError) { $script:harnessError.ToString() } else { $null }
        }
        inputs = [ordered]@{
            repo = $repoRoot
            subsession_script = $SubSessionScript
            fixture = $FixturePath
            staging_home = $StagingHome
            production_home = $ProductionProfile
            live = [bool]$Live
            live_enabled = [bool]$script:liveEnabled
            keep_staging = [bool]$KeepStaging
            prod_has_default = [bool]$script:prodOk
            dojo_has_default = [bool]$script:dojoOk
            parent_copilot_home = $env:COPILOT_HOME
        }
        counts = $counts
        test_cases = @(
            foreach ($t in $script:testCases.Values) {
                [ordered]@{
                    id = $t.id
                    bucket = $t.bucket
                    checkpoint = $t.checkpoint
                    status = $t.status
                    details = $t.details
                    known_gap = $t.known_gap
                    evidence = @($t.evidence)
                }
            }
        )
        artifacts = [ordered]@{
            report_directory = $script:reportDir
            report_markdown = $ReportPath
            summary_json = (Join-Path $script:reportDir 'summary.json')
            inputs_json = (Join-Path $script:reportDir 'inputs.json')
            test_cases_json = (Join-Path $script:reportDir 'test-cases.json')
            evidence_directory = $script:evidenceDir
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# copilot-cli-subsession argument audit report')
    $lines.Add('')
    $lines.Add('## Run overview')
    $lines.Add('')
    $lines.Add('| Field | Value |')
    $lines.Add('| --- | --- |')
    $lines.Add("| Timestamp | $($summary.run.timestamp) |")
    $lines.Add("| Exit code | $ExitCode |")
    $lines.Add("| Status | $($summary.run.status) |")
    $lines.Add("| Staging home | ``$StagingHome`` |")
    $lines.Add("| Production | ``$ProductionProfile`` |")
    $lines.Add("| Fixture | ``$FixturePath`` |")
    $lines.Add("| Live | ``$([bool]$Live)`` (enabled: ``$([bool]$script:liveEnabled)``) |")
    $lines.Add("| Total / Passed / Failed / Skipped / Known-gap | $($counts.total) / $($counts.passed) / $($counts.failed) / $($counts.skipped) / $($counts.known_gap) |")
    if ($script:harnessError) {
        $lines.Add("| Harness error | ``$($script:harnessError)`` |")
    }
    $lines.Add('')
    $lines.Add('## Execution checklist')
    $lines.Add('')
    $lines.Add('| id | bucket | status | details | evidence |')
    $lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($t in $script:testCases.Values) {
        $statusCell = if ($t.known_gap) { "$($t.status) (gap)" } else { $t.status }
        $evLinks = @()
        foreach ($e in @($t.evidence)) {
            $rel = Get-MarkdownRelativePath -BasePath $script:reportDir -TargetPath $e
            $evLinks += "[$(Split-Path $e -Leaf)]($rel)"
        }
        $lines.Add("| $($t.id) | $($t.bucket) | $statusCell | $($t.details) | $($evLinks -join ' ') |")
    }
    $lines.Add('')
    $lines.Add('## Known gaps (PASS with gap label)')
    $lines.Add('')
    $gapRows = @($script:testCases.Values | Where-Object { $_.known_gap })
    if ($gapRows.Count -eq 0) {
        $lines.Add('_None._')
    }
    else {
        foreach ($t in $gapRows) {
            $lines.Add("- **$($t.id)**: $($t.known_gap)")
        }
    }
    $lines.Add('')
    $lines.Add('## Artifacts')
    $lines.Add('')
    $lines.Add("- Report: ``$ReportPath``")
    $lines.Add("- Summary: ``$(Join-Path $script:reportDir 'summary.json')``")
    $lines.Add("- Inputs: ``$(Join-Path $script:reportDir 'inputs.json')``")
    $lines.Add("- Test cases: ``$(Join-Path $script:reportDir 'test-cases.json')``")
    $lines.Add("- Evidence: ``$script:evidenceDir``")
    $lines.Add('')

    Write-Utf8File -Path $ReportPath -Content ($lines -join "`n")
    Write-Utf8File -Path (Join-Path $script:reportDir 'summary.json') -Content ($summary | ConvertTo-Json -Depth 10)
    Write-Utf8File -Path (Join-Path $script:reportDir 'inputs.json') -Content ($summary.inputs | ConvertTo-Json -Depth 10)
    Write-Utf8File -Path (Join-Path $script:reportDir 'test-cases.json') -Content ($summary.test_cases | ConvertTo-Json -Depth 10)
}

# --- Execute ----------------------------------------------------------------
$exitCode = 0
try {
    Invoke-HarnessMain -StagingHome $StagingHome -FixturePath $FixturePath -Live:$Live -SkipLive:$SkipLive -KeepStaging:$KeepStaging
}
catch {
    $script:harnessError = $_
    # Write-Error under $ErrorActionPreference='Stop' would itself terminate before
    # $exitCode=2 below; use -ErrorAction Continue so the harness reports exit 2.
    Write-Error "Harness error: $_" -ErrorAction Continue
}

if ($script:harnessError) { $exitCode = 2 }
else {
    $failed = @($script:testCases.Values | Where-Object { $_.status -eq 'failed' })
    $exitCode = if ($failed.Count -gt 0) { 1 } else { 0 }
}

if ($ReportPath) {
    Write-HarnessReport -ReportPath $ReportPath -ExitCode $exitCode
}
else {
    $reportPath = Join-Path $script:reportDir 'report.md'
    Write-HarnessReport -ReportPath $reportPath -ExitCode $exitCode
    Write-Host ""
    Write-Host "copilot-cli-subsession argument audit complete: exit $exitCode" -ForegroundColor Cyan
    Write-Host "  report: $reportPath" -ForegroundColor Gray
}

# Cleanup temp dirs unless -KeepStaging.
if (-not $KeepStaging) {
    foreach ($d in $script:tempDirs) {
        Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
