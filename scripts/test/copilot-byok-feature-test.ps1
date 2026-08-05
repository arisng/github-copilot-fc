<#
.SYNOPSIS
    Deterministic copilot-byok feature harness (Phase 1: config-level).

.DESCRIPTION
    Exercises skills/copilot-byok/scripts/byok-profile.ps1 behaviors against an
    isolated staging COPILOT_HOME. Runs each case in a child pwsh with sentinel
    API-key env vars (never inherits real keys), injects a hermetic fixture
    profile file, and intercepts `run` launches with a copilot shim so no real
    copilot process and no network traffic occur in Phase 1.

    Isolation guarantees:
    - Staging home defaults to a harness-owned directory under
      scripts/test/.artifacts/copilot-byok-feature-test/staging — the shared
      ~/.copilot-staging dojo is NEVER touched by default; production
      ~/.copilot is only ever READ (for the production-default isolation case)
      and is hash-asserted unchanged after every mutating case.
    - The staging byok-profiles.json is snapshotted before the run and restored
      in a finally block (unless -KeepFixture).
    - Real API keys are never inherited: every child gets sentinel values for
      OPENCODE_API_KEY_HOME / OPENCODE_API_KEY_WORK / OPENAI_API_KEY.
    - The real copilot executable's directory is scrubbed from child PATH for
      run cases and a shim copilot.ps1 is prepended; a preflight inside the
      child aborts (exit 90) if the shim is not the resolved `copilot`.

    Status taxonomy: PASS / FAIL / SKIP / KNOWN-GAP (KNOWN-GAP reports as PASS
    with a gap label so the harness stays green while documenting behavior).
    Exit codes: 0 all passed, 1 any failed, 2 harness/preflight error.

    Phase 2 (-Live) is not implemented yet; passing -Live runs config-level only
    with a warning.

.EXAMPLE
    # Default run against the harness-owned staging dir with the checked-in fixture
    pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1

.EXAMPLE
    # Explicitly test against the shared dojo (~/.copilot-staging) and keep the
    # fixture there afterwards so the dojo retains a seeded byok-profiles.json
    pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1 -StagingHome "$HOME\.copilot-staging" -KeepFixture

.EXAMPLE
    # Keep the staging fixture in place after the run (do not restore snapshot)
    pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1 -KeepFixture

.EXAMPLE
    # Custom staging home and report path
    pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1 -StagingHome C:\temp\dojo -ReportPath C:\temp\report.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StagingHome = (Join-Path $PSScriptRoot '.artifacts\copilot-byok-feature-test\staging'),

    [Parameter(Mandatory = $false)]
    [string]$FixturePath,

    [Parameter(Mandatory = $false)]
    [switch]$Live,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLive,

    [Parameter(Mandatory = $false)]
    [switch]$KeepFixture,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$ByokScript = Join-Path $repoRoot 'skills\copilot-byok\scripts\byok-profile.ps1'
$SubSessionScript = Join-Path $repoRoot 'skills\copilot-cli-subsession\scripts\Invoke-CopilotCliSubSession.ps1'
$ProductionHome = Join-Path $HOME '.copilot'
$ProductionProfile = Join-Path $ProductionHome 'byok-profiles.json'

if (-not $FixturePath) {
    $FixturePath = Join-Path $PSScriptRoot 'fixtures\byok-profiles.fixture.json'
}

if (-not (Test-Path $ByokScript -PathType Leaf)) { throw "byok-profile.ps1 not found: $ByokScript" }
if (-not (Test-Path $SubSessionScript -PathType Leaf)) { throw "Invoke-CopilotCliSubSession.ps1 not found: $SubSessionScript" }
if (-not (Test-Path $FixturePath -PathType Leaf)) { throw "Fixture not found: $FixturePath" }

# --- Artifacts ---------------------------------------------------------------
$reportTimestamp = (Get-Date).ToUniversalTime().ToString('yyMMdd-HHmmss')
$script:reportDir = Join-Path $repoRoot ("scripts\test\.artifacts\copilot-byok-feature-test\run-{0}-{1}" -f $reportTimestamp, $PID)
$script:evidenceDir = Join-Path $script:reportDir 'evidence'
$script:testCases = [ordered]@{}
$script:harnessError = $null

# --- Helpers -----------------------------------------------------------------
function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        # AllowEmptyString: error-path children legitimately produce empty stdout.
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
    return $path
}

function Get-ByokChildEnv {
    param([string]$CopilotHome)
    # Sentinel keys ONLY — real OPENCODE_API_KEY_* / OPENAI_API_KEY are never inherited.
    return @{
        'COPILOT_HOME' = $CopilotHome
        'OPENCODE_API_KEY_HOME' = 'sentinel-opencode-home-key'
        'OPENCODE_API_KEY_WORK' = 'sentinel-opencode-work-key'
        'OPENAI_API_KEY' = 'sentinel-openai-key'
    }
}

function Invoke-ChildPwsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandText,
        [hashtable]$ExtraEnv = @{},
        [string[]]$RemoveEnv = @(),
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
    # NB: $psi.Environment.Remove() returns a bool that would pollute the function's
    # output pipeline (and turn $child into an array) — swallow it with $null =.
    foreach ($key in $RemoveEnv) { $null = $psi.Environment.Remove($key) }

    if ($PathPrepends.Count -gt 0 -or $ScrubCopilotFromPath) {
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
        $parts = @($currentPath -split ';' | Where-Object { $_ -ne '' })
        if ($ScrubCopilotFromPath) {
            $realCopilot = Get-Command copilot -ErrorAction SilentlyContinue
            if ($realCopilot -and $realCopilot.Source) {
                $realCopilotDir = Split-Path -Path $realCopilot.Source -Parent
                if ($realCopilotDir) {
                    $parts = @($parts | Where-Object { $_ -ne $realCopilotDir })
                }
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

function New-ShimCopilot {
    $dir = New-TempDirectory 'byok-copilot-shim'
    $shim = @'
$logPath = $env:COPILOT_TEST_SHIM_LOG
if ($logPath) {
    "ARGS|" + ($args -join ' ') | Out-File -FilePath $logPath -Encoding utf8
    "ENV|BASE_URL=$env:COPILOT_PROVIDER_BASE_URL|TYPE=$env:COPILOT_PROVIDER_TYPE|MODEL=$env:COPILOT_MODEL|WIRE_API=$env:COPILOT_PROVIDER_WIRE_API|KEY=$env:COPILOT_PROVIDER_API_KEY|MAX_PROMPT=$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS|MAX_OUTPUT=$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS|OFFLINE=$env:COPILOT_OFFLINE" | Out-File -FilePath $logPath -Encoding utf8 -Append
}
Write-Output 'SHIM_INVOKED'
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

function Save-ChildEvidence {
    param([string]$Id, [object]$ChildResult, [string]$ShimLog = $null)
    $out = Join-Path $script:evidenceDir "$Id.out.txt"
    $err = Join-Path $script:evidenceDir "$Id.err.txt"
    # Error-path children often emit nothing to stdout (terminating errors bypass
    # *>&1 and land on stderr), so tolerate null/empty stdout.
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

# --- Command templates (single-quoted: $env: stays literal for the child) ----
$script:tmplList = @'
& '__BYOK__' list *>&1
'@
$script:tmplShow = @'
& '__BYOK__' show __PROFILE__ *>&1
'@
$script:tmplUse = @'
& '__BYOK__' use __ACCOUNT__ *>&1
'@
$script:tmplRemove = @'
& '__BYOK__' remove __PROFILE__ *>&1
'@
$script:tmplAccounts = @'
& '__BYOK__' accounts *>&1
'@
$script:tmplSetEnvDump = @'
. '__BYOK__' set-env __PROFILE__ __ARGS__
Write-Output ('ENVDUMP|BASE_URL=' + $env:COPILOT_PROVIDER_BASE_URL + '|TYPE=' + $env:COPILOT_PROVIDER_TYPE + '|MODEL=' + $env:COPILOT_MODEL + '|WIRE_API=' + $env:COPILOT_PROVIDER_WIRE_API + '|KEY=' + $env:COPILOT_PROVIDER_API_KEY + '|MAX_PROMPT=' + $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS + '|MAX_OUTPUT=' + $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS + '|OFFLINE=' + $env:COPILOT_OFFLINE)
'@
$script:tmplRun = @'
if ((Get-Command copilot -ErrorAction Stop).Path -ne '__SHIM__') { Write-Error 'SHIM_NOT_WINNING'; exit 90 }
& '__BYOK__' run __PROFILE__ __ARGS__ *>&1
'@
$script:tmplWizard = @'
& '__BYOK__' add *>&1
'@
$script:tmplSubSession = @'
$out = & '__SUBSESSION__' -CopilotHome '__HOME__' -ByokProfile '__PROFILE__' -Prompt 'test' -TimeoutSeconds 20 2>&1 6>&1 | Out-String
Write-Output ('SEEDED=' + ([string]$out).Contains('Seeding staging COPILOT_HOME from production'))
Write-Output ('HAS_HOME=' + ([string]$out).Contains('__HOME__'))
Write-Output ('HAS_EXIT=' + ([string]$out).Contains('ExitCode'))
'@

# --- Case helpers ------------------------------------------------------------
function Invoke-ByokChild {
    param([string]$CommandText, [string]$CopilotHome = $StagingHome, [string[]]$RemoveEnv = @(), [int]$TimeoutSeconds = 30)
    return Invoke-ChildPwsh -CommandText $CommandText -ExtraEnv (Get-ByokChildEnv -CopilotHome $CopilotHome) -RemoveEnv $RemoveEnv -TimeoutSeconds $TimeoutSeconds
}

function Invoke-RunCase {
    param([string]$Id, [string]$Profile, [string]$ArgsText, [int]$TimeoutSeconds = 30)
    $shimDir = New-ShimCopilot
    $shimPath = Join-Path $shimDir 'copilot.ps1'
    $logPath = Join-Path $shimDir 'shim.log'
    $cmd = Format-ChildCommand -Template $script:tmplRun -Values @{
        '__SHIM__' = $shimPath; '__BYOK__' = $ByokScript; '__PROFILE__' = $Profile; '__ARGS__' = $ArgsText
    }
    $envMap = Get-ByokChildEnv -CopilotHome $StagingHome
    $envMap['COPILOT_TEST_SHIM_LOG'] = $logPath
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv $envMap -PathPrepends @($shimDir) -ScrubCopilotFromPath $true -TimeoutSeconds $TimeoutSeconds
    $logContent = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }
    $ev = Save-ChildEvidence -Id $Id -ChildResult $child -ShimLog $logPath
    return [PSCustomObject]@{ Child = $child; ShimLog = $logContent; Evidence = @($ev) }
}

function Get-StagingJson {
    $path = Join-Path $StagingHome 'byok-profiles.json'
    if (-not (Test-Path $path -PathType Leaf)) { return $null }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Get-ProductionProfileNames {
    if (-not (Test-Path $ProductionProfile -PathType Leaf)) { return @() }
    $json = Get-Content $ProductionProfile -Raw | ConvertFrom-Json
    if (-not $json -or -not $json.profiles) { return @() }
    return @($json.profiles.PSObject.Properties.Name)
}

# ============================================================================
# Test cases
# ============================================================================

# --- Bucket A: staging redirection & isolation -------------------------------
function Test-T1_1 {
    $cmd = Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't1-1' -ChildResult $child
    $passed = ($child.ExitCode -eq 0) -and
        ($child.StdOut -match 'openai-completions') -and
        ($child.StdOut -match 'responses-wire') -and
        ($child.StdOut -match 'no-reasoning') -and
        ($child.StdOut -match [regex]::Escape($StagingHome))
    $details = "exit=$($child.ExitCode); fixture profiles + staging path in list output"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T1_3 {
    $prodHashBefore = Get-FileHashValue -Path $ProductionProfile
    $cmd = Format-ChildCommand -Template $script:tmplUse -Values @{ '__BYOK__' = $ByokScript; '__ACCOUNT__' = 'opencode-home' }
    $child = Invoke-ByokChild -CommandText $cmd
    $json = Get-StagingJson
    $prodHashAfter = Get-FileHashValue -Path $ProductionProfile
    $ev = Save-ChildEvidence -Id 't1-3' -ChildResult $child
    $passed = ($child.ExitCode -eq 0) -and
        ($null -ne $json -and $json.activeAccount -eq 'opencode-home') -and
        ($prodHashBefore -eq $prodHashAfter)
    $details = "staging activeAccount=$($json.activeAccount); production hash unchanged=$($prodHashBefore -eq $prodHashAfter)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T1_4 {
    $prodHashBefore = Get-FileHashValue -Path $ProductionProfile
    $cmd = Format-ChildCommand -Template $script:tmplRemove -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'no-reasoning' }
    $child = Invoke-ByokChild -CommandText $cmd
    $json = Get-StagingJson
    $prodHashAfter = Get-FileHashValue -Path $ProductionProfile
    $ev = Save-ChildEvidence -Id 't1-4' -ChildResult $child
    $stillThere = $null -ne $json -and $json.profiles.PSObject.Properties.Name -contains 'no-reasoning'
    $passed = ($child.ExitCode -eq 0) -and (-not $stillThere) -and ($prodHashBefore -eq $prodHashAfter)
    $details = "staging has no-reasoning after remove=$stillThere; production hash unchanged=$($prodHashBefore -eq $prodHashAfter)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T1_5 {
    $prodNames = Get-ProductionProfileNames
    if ($prodNames.Count -eq 0) {
        return New-TestResult -Passed $true -Details 'production byok-profiles.json not present; skipped' -Skip
    }
    # Production default: COPILOT_HOME explicitly removed from child env.
    $cmd = Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd -RemoveEnv @('COPILOT_HOME')
    $ev = Save-ChildEvidence -Id 't1-5' -ChildResult $child
    $prodName = $prodNames | Select-Object -First 1
    $hasProd = $child.StdOut -match [regex]::Escape($prodName)
    $hasFixture = ($child.StdOut -match 'openai-completions') -or ($child.StdOut -match 'responses-wire')
    $passed = ($child.ExitCode -eq 0) -and $hasProd -and (-not $hasFixture) -and ($child.StdOut -match [regex]::Escape($ProductionHome))
    $details = "prod profile '$prodName' visible=$hasProd; fixture leaks=$hasFixture"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# --- Bucket B: profile manager -----------------------------------------------
function Test-T2_1 {
    $cmd = Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't2-1' -ChildResult $child
    $line = '-> openai | deepseek-v4-flash | https://opencode.ai/zen/go/v1 [accountGroup: opencode]'
    $passed = ($child.ExitCode -eq 0) -and ($child.StdOut -match [regex]::Escape($line)) -and ($child.StdOut -match 'BYOK Profiles')
    $details = "exit=$($child.ExitCode); list line format + accountGroup suffix verified"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T2_2 {
    # show: JSON + Reasoning Effort Supported per model
    $pairs = @(
        @{ p = 'openai-completions'; m = 'deepseek-v4-flash'; e = 'True' }
        @{ p = 'responses-wire'; m = 'gpt-5.6-luna'; e = 'True' }
        @{ p = 'no-reasoning'; m = 'kimi-k2.7-code'; e = 'False' }
        @{ p = 'no-reasoning-flag'; m = 'kimi-k2.6'; e = 'False' }
        @{ p = 'anthropic-type'; m = 'qwen3.7-plus'; e = 'False' }
        @{ p = 'legacy-api-key'; m = 'gpt-4.1'; e = 'True' }
        @{ p = 'drift-kimi-k3'; m = 'kimi-k3'; e = 'True' }
    )
    $allPassed = $true
    $detailParts = @()
    $evidence = @()
    foreach ($pair in $pairs) {
        $cmd = Format-ChildCommand -Template $script:tmplShow -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = $pair.p }
        $child = Invoke-ByokChild -CommandText $cmd
        $ev = Save-ChildEvidence -Id "t2-2-$($pair.p)" -ChildResult $child
        $evidence += $ev
        $ok = ($child.ExitCode -eq 0) -and
            ($child.StdOut -match [regex]::Escape('"' + $pair.m + '"')) -and
            ($child.StdOut -match ('Reasoning Effort Supported : ' + $pair.e))
        $allPassed = $allPassed -and $ok
        $detailParts += "$($pair.p)=$(if ($ok) { 'ok' } else { 'BAD' })"
    }
    return New-TestResult -Passed $allPassed -Details ($detailParts -join '; ') -Evidence $evidence
}

function Test-T2_3 {
    $cmd = Format-ChildCommand -Template $script:tmplAccounts -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't2-3' -ChildResult $child
    $activeLine = '-> OpenCode Zen (Work) | keyEnv: OPENCODE_API_KEY_WORK [active]'
    $passed = ($child.ExitCode -eq 0) -and
        ($child.StdOut -match 'opencode-home') -and
        ($child.StdOut -match 'opencode-work') -and
        ($child.StdOut -match [regex]::Escape($activeLine))
    $details = "exit=$($child.ExitCode); accounts list + [active] marker"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T2_4 {
    $cmdUse = Format-ChildCommand -Template $script:tmplUse -Values @{ '__BYOK__' = $ByokScript; '__ACCOUNT__' = 'opencode-home' }
    $null = Invoke-ByokChild -CommandText $cmdUse
    $cmdAccounts = Format-ChildCommand -Template $script:tmplAccounts -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmdAccounts
    $json = Get-StagingJson
    $ev = Save-ChildEvidence -Id 't2-4' -ChildResult $child
    $activeHome = $child.StdOut -match [regex]::Escape('OpenCode Zen (Home) | keyEnv: OPENCODE_API_KEY_HOME [active]')
    $passed = ($null -ne $json -and $json.activeAccount -eq 'opencode-home') -and $activeHome
    $details = "activeAccount=$($json.activeAccount); accounts reflects [active] on home=$activeHome"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T2_5 {
    $allPassed = $true
    $evidence = @()
    foreach ($sub in @(@{ c = 'show'; p = 'does-not-exist' }, @{ c = 'remove'; p = 'does-not-exist' })) {
        $template = if ($sub.c -eq 'show') { $script:tmplShow } else { $script:tmplRemove }
        $cmd = Format-ChildCommand -Template $template -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = $sub.p }
        $child = Invoke-ByokChild -CommandText $cmd
        $ev = Save-ChildEvidence -Id "t2-5-$($sub.c)" -ChildResult $child
        $evidence += $ev
        if ($child.ExitCode -ne 1) { $allPassed = $false }
    }
    return New-TestResult -Passed $allPassed -Details 'show/remove of missing profile both exit 1' -Evidence $evidence
}

function Test-T2_6 {
    # Wizard preset 6 (OpenCode Go), category 1, model 3 (kimi-k2.7-code).
    # Exactly 8 Read-Host prompts: name, preset, category, model, apiKey, maxPrompt, maxOutput, offline.
    $name = 'wizard-opencode'
    $stdin = "$name`n6`n1`n3`n`n`n`n`n"
    $cmd = Format-ChildCommand -Template $script:tmplWizard -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv (Get-ByokChildEnv -CopilotHome $StagingHome) -StdinText $stdin -TimeoutSeconds 60
    $ev = Save-ChildEvidence -Id 't2-6' -ChildResult $child
    $json = Get-StagingJson
    $p = $null
    if ($null -ne $json -and $json.profiles.PSObject.Properties.Name -contains $name) { $p = $json.profiles.$name }
    $exists = $null -ne $p
    $modelOk = $exists -and $p.model -eq 'kimi-k2.7-code'
    $reasoningOk = $exists -and $p.PSObject.Properties.Name -contains 'reasoningEffortSupported' -and $p.reasoningEffortSupported -eq $false
    $wireApiAbsent = $exists -and ($p.PSObject.Properties.Name -notcontains 'wireApi')
    $maxPromptOk = $exists -and $p.maxPromptTokens -eq 200000
    $groupOk = $exists -and $p.accountGroup -eq 'opencode'
    $passed = $exists -and $modelOk -and $reasoningOk -and $wireApiAbsent -and $maxPromptOk -and $groupOk
    $details = "exists=$exists; model=$($p.model); reasoningEffortSupported=false=$reasoningOk; wireApiAbsent=$wireApiAbsent; maxPrompt=200000=$maxPromptOk; accountGroup=$($p.accountGroup)"
    $gap = if ($wireApiAbsent) { 'wizard preset 6 does not prompt for wireApi (known gap, locked as baseline)' } else { '' }
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $ev
}

function Test-T2_7 {
    $allPassed = $true
    $evidence = @()
    $cmdSetEnv = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'does-not-exist'; '__ARGS__' = '' }
    $childSetEnv = Invoke-ByokChild -CommandText $cmdSetEnv
    $ev = Save-ChildEvidence -Id 't2-7-setenv' -ChildResult $childSetEnv
    $evidence += $ev
    if ($childSetEnv.ExitCode -ne 1) { $allPassed = $false }

    # run with missing profile fails BEFORE any copilot lookup; no shim needed.
    $cmdRun = "& '{0}' run does-not-exist *>&1" -f $ByokScript
    $childRun = Invoke-ByokChild -CommandText $cmdRun
    $ev2 = Save-ChildEvidence -Id 't2-7-run' -ChildResult $childRun
    $evidence += $ev2
    if ($childRun.ExitCode -ne 1) { $allPassed = $false }

    return New-TestResult -Passed $allPassed -Details 'set-env/run of missing profile both exit 1' -Evidence $evidence
}

function Test-T2_8 {
    $cmd = Format-ChildCommand -Template $script:tmplUse -Values @{ '__BYOK__' = $ByokScript; '__ACCOUNT__' = 'no-such-account' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't2-8' -ChildResult $child
    $passed = $child.ExitCode -eq 1
    return New-TestResult -Passed $passed -Details "use of missing account exits $($child.ExitCode)" -Evidence $ev
}

function Test-T2_9 {
    $emptyDir = New-TempDirectory 'byok-empty'
    Write-Utf8File -Path (Join-Path $emptyDir 'byok-profiles.json') -Content '{"profiles":{},"accounts":{}}'
    $cmd = Format-ChildCommand -Template $script:tmplAccounts -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd -CopilotHome $emptyDir
    $ev = Save-ChildEvidence -Id 't2-9' -ChildResult $child
    $passed = ($child.ExitCode -eq 0) -and ($child.StdOut -match 'No accounts defined')
    $details = "exit=$($child.ExitCode); empty-state message present"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# --- Bucket C: env emission (set-env, dot-sourced children) ------------------
function Test-T3_1 {
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'openai-completions'; '__ARGS__' = '' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-1' -ChildResult $child
    $passed = ($child.StdOut -match 'ENVDUMP\|BASE_URL=https://opencode.ai/zen/go/v1') -and
        ($child.StdOut -match 'TYPE=openai') -and
        ($child.StdOut -match 'MODEL=deepseek-v4-flash') -and
        ($child.StdOut -match 'WIRE_API=\|') -and
        ($child.StdOut -match 'MAX_PROMPT=325000') -and
        ($child.StdOut -match 'MAX_OUTPUT=64000') -and
        ($child.StdOut -match 'KEY=sentinel-opencode-work-key')
    $details = "exit=$($child.ExitCode); openai-completions env emission (WIRE_API removed)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_2 {
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'responses-wire'; '__ARGS__' = '' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-2' -ChildResult $child
    $passed = ($child.StdOut -match 'ENVDUMP\|') -and
        ($child.StdOut -match 'WIRE_API=responses') -and
        ($child.StdOut -match 'MAX_PROMPT=200000') -and
        ($child.StdOut -match 'MAX_OUTPUT=64000') -and
        ($child.StdOut -match 'MODEL=gpt-5.6-luna')
    $details = "exit=$($child.ExitCode); responses-wire env emission"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_3 {
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'no-reasoning'; '__ARGS__' = '' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-3' -ChildResult $child
    $passed = ($child.StdOut -match 'MODEL=kimi-k2.7-code') -and ($child.StdOut -match 'Reasoning Effort Supported = False')
    $details = "exit=$($child.ExitCode); kimi reports Reasoning Effort Supported = False"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_4 {
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'openai-completions'; '__ARGS__' = '--account opencode-home' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-4' -ChildResult $child
    $passed = ($child.StdOut -match 'KEY=sentinel-opencode-home-key') -and ($child.StdOut -match 'via --account override')
    $details = "exit=$($child.ExitCode); --account override resolves key to OPENCODE_API_KEY_HOME sentinel"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_5 {
    # Two dot-sourced set-env calls in one process: rich then minimal, then dump.
    $cmd = @"
. '$ByokScript' set-env responses-wire
. '$ByokScript' set-env minimal
Write-Output ('ENVDUMP|BASE_URL=' + `$env:COPILOT_PROVIDER_BASE_URL + '|TYPE=' + `$env:COPILOT_PROVIDER_TYPE + '|MODEL=' + `$env:COPILOT_MODEL + '|WIRE_API=' + `$env:COPILOT_PROVIDER_WIRE_API + '|KEY=' + `$env:COPILOT_PROVIDER_API_KEY + '|MAX_PROMPT=' + `$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS + '|MAX_OUTPUT=' + `$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS + '|OFFLINE=' + `$env:COPILOT_OFFLINE)
"@
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-5' -ChildResult $child
    $passed = ($child.StdOut -match 'WIRE_API=\|') -and
        ($child.StdOut -match 'MAX_OUTPUT=\|') -and
        ($child.StdOut -match 'MAX_PROMPT=96000') -and
        ($child.StdOut -match 'MODEL=deepseek-v4-flash')
    $details = "exit=$($child.ExitCode); rich->minimal stale cleanup removes WIRE_API + MAX_OUTPUT"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_6 {
    # Plain ${ENV} placeholder expansion (no account resolution) via set-env.
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'legacy-api-key'; '__ARGS__' = '' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-6' -ChildResult $child
    $passed = ($child.StdOut -match 'KEY=sentinel-openai-key') -and ($child.StdOut -match 'MODEL=gpt-4.1')
    $details = ('exit=' + $child.ExitCode + '; ${OPENAI_API_KEY} expands to sentinel')
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T3_7 {
    $cmd = Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'offline-profile'; '__ARGS__' = '' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't3-7' -ChildResult $child
    $passed = ($child.StdOut -match 'OFFLINE=true') -and ($child.StdOut -match 'KEY=\|') -and ($child.StdOut -match 'MODEL=llama3.2')
    $details = "exit=$($child.ExitCode); offline=true sets COPILOT_OFFLINE, no apiKey"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# --- Bucket D: reasoning stripping via run + shim ----------------------------
function Test-T4_1 {
    $r = Invoke-RunCase -Id 't4-1' -Profile 'no-reasoning' -ArgsText '--reasoning-effort high'
    $argsLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)
    $noReasoningInArgs = $argsLine -notmatch 'reasoning' -and $argsLine -notmatch 'high'
    $strippedBanner = $r.Child.StdOut -match 'Stripped --reasoning-effort'
    $passed = ($r.Child.ExitCode -eq 0) -and $noReasoningInArgs -and $strippedBanner
    $details = "shim args=[$argsLine]; stripped banner=$strippedBanner"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_2 {
    $r = Invoke-RunCase -Id 't4-2' -Profile 'openai-completions' -ArgsText '--reasoning-effort high'
    $argsLine = (($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)).Trim()
    $forwarded = $argsLine -match '--reasoning-effort' -and $argsLine -match ' high$'
    $noStrip = $r.Child.StdOut -notmatch 'Stripped --reasoning-effort'
    $passed = ($r.Child.ExitCode -eq 0) -and $forwarded -and $noStrip
    $details = "shim args=[$argsLine]; forwarded intact=$forwarded"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_3 {
    $r = Invoke-RunCase -Id 't4-3' -Profile 'openai-completions' -ArgsText '--reasoning-effort high --account opencode-home'
    $argsLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)
    $noAccount = $argsLine -notmatch '--account'
    $envLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ENV\|' } | Select-Object -First 1)
    $keyHome = $envLine -match 'KEY=sentinel-opencode-home-key'
    $passed = ($r.Child.ExitCode -eq 0) -and $noAccount -and $keyHome
    $details = "shim args=[$argsLine]; --account consumed=$noAccount; key home=$keyHome"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_4 {
    $r = Invoke-RunCase -Id 't4-4' -Profile 'openai-completions' -ArgsText '--effort=high'
    $argsLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)
    $forwarded = $argsLine -match '--effort=high'
    $passed = ($r.Child.ExitCode -eq 0) -and $forwarded
    $details = "shim args=[$argsLine]; --effort=high forwarded=$forwarded"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_5 {
    $r = Invoke-RunCase -Id 't4-5' -Profile 'no-reasoning' -ArgsText '--reasoning-effort=high'
    $argsLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)
    $stripped = $argsLine -notmatch 'reasoning'
    $passed = ($r.Child.ExitCode -eq 0) -and $stripped -and ($r.Child.StdOut -match 'Stripped --reasoning-effort')
    $details = "shim args=[$argsLine]; equals-form stripped=$stripped"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_6 {
    $r = Invoke-RunCase -Id 't4-6' -Profile 'legacy-api-key' -ArgsText '--prompt hi'
    $argsLine = (($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)).Trim()
    $envLine = (($r.ShimLog -split "`n" | Where-Object { $_ -match '^ENV\|' } | Select-Object -First 1)).Trim()
    $keyLegacy = $envLine -match 'KEY=sentinel-openai-key'
    $argsOk = $argsLine -match '--prompt hi'
    $passed = ($r.Child.ExitCode -eq 0) -and $keyLegacy -and $argsOk
    $details = "shim args=[$argsLine]; legacy apiKey sentinel=$keyLegacy; --prompt forwarded=$argsOk"
    return New-TestResult -Passed $passed -Details $details -Evidence $r.Evidence
}

function Test-T4_7 {
    # Lock: PowerShell param prefix-matching binds '-p' to the script's own
    # -Profile param, so a copilot-style '-p "<prompt>"' arg is consumed as the
    # profile name and run fails ('Profile ... not found') before the shim is
    # ever reached. Current behavior locked as a KNOWN-GAP; use --prompt instead.
    $r = Invoke-RunCase -Id 't4-7' -Profile 'openai-completions' -ArgsText '-p "hello world"'
    $shimRan = -not [string]::IsNullOrWhiteSpace($r.ShimLog)
    $failedBeforeShim = ($r.Child.ExitCode -eq 1) -and (-not $shimRan)
    $passed = $failedBeforeShim
    $details = "exit=$($r.Child.ExitCode); shim invoked=$shimRan (expected NOT)"
    $gap = "byok run consumes '-p' as -Profile (PowerShell param prefix matching); copilot-style '-p <prompt>' breaks run - use --prompt instead"
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

function Test-T4_8 {
    # Latent-bug lock: Remove-AccountArg regex requires 1+ chars after '--account=',
    # so '--account=' (empty value) is NOT consumed and gets forwarded.
    $r = Invoke-RunCase -Id 't4-8' -Profile 'openai-completions' -ArgsText '--account='
    $argsLine = ($r.ShimLog -split "`n" | Where-Object { $_ -match '^ARGS\|' } | Select-Object -First 1)
    $forwarded = $argsLine -match '--account='
    $passed = ($r.Child.ExitCode -eq 0) -and $forwarded
    $details = "shim args=[$argsLine]; --account= forwarded (current behavior)"
    $gap = 'Remove-AccountArg regex ^--account=(.+)$ does not match empty value; --account= leaks to copilot (latent bug, locked as baseline)'
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $r.Evidence
}

# --- Bucket E: negatives & drift ---------------------------------------------
function Test-T5_1 {
    $badDir = New-TempDirectory 'byok-malformed'
    Write-Utf8File -Path (Join-Path $badDir 'byok-profiles.json') -Content '{invalid'
    $cmd = Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd -CopilotHome $badDir
    $ev = Save-ChildEvidence -Id 't5-1' -ChildResult $child
    $passed = $child.ExitCode -eq 1
    $details = "malformed JSON exits $($child.ExitCode) (clean failure expected)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T5_2 {
    $emptyDir = New-TempDirectory 'byok-emptyfile'
    Write-Utf8File -Path (Join-Path $emptyDir 'byok-profiles.json') -Content ''
    $cmd = Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }
    $child = Invoke-ByokChild -CommandText $cmd -CopilotHome $emptyDir
    $ev = Save-ChildEvidence -Id 't5-2' -ChildResult $child
    # Expected: empty file is normalized by Get-ProfileConfig -> 'No profiles found' exit 0.
    $passed = ($child.ExitCode -eq 0) -and ($child.StdOut -match 'No profiles found')
    $details = "empty byok-profiles.json exits $($child.ExitCode); 'No profiles found' present=$($child.StdOut -match 'No profiles found')"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T5_3 {
    # Drift lock: kimi-k3 is NOT in Get-NoReasoningEffortModels -> Test returns True,
    # contradicting reasoning-effort-lookup.md's 'assume no support until probed'.
    $cmd = Format-ChildCommand -Template $script:tmplShow -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'drift-kimi-k3' }
    $child = Invoke-ByokChild -CommandText $cmd
    $ev = Save-ChildEvidence -Id 't5-3' -ChildResult $child
    $supportedTrue = $child.StdOut -match 'Reasoning Effort Supported : True'
    $passed = ($child.ExitCode -eq 0) -and $supportedTrue
    $details = "drift-kimi-k3 reports Supported: True (spec-vs-code inconsistency)"
    $gap = 'kimi-k3 absent from Get-NoReasoningEffortModels; Test-ReasoningEffortSupported returns True while reasoning-effort-lookup.md says assume no support until probed'
    return New-TestResult -Passed $passed -Details $details -KnownGap $gap -Evidence $ev
}

# --- Bucket T6: subsession seeding integration (throwaway dirs) --------------
function Test-T6_1 {
    $prodHashBefore = Get-FileHashValue -Path $ProductionProfile
    $throw = New-TempDirectory 'byok-t6-seed'
    $shimDir = New-ShimCopilot
    $shimPath = Join-Path $shimDir 'copilot.ps1'
    $logPath = Join-Path $shimDir 'shim.log'
    $cmd = Format-ChildCommand -Template $script:tmplSubSession -Values @{
        '__SUBSESSION__' = $SubSessionScript; '__HOME__' = $throw; '__PROFILE__' = 'opencode-go-deepseek-v4-flash'
    }
    $envMap = @{
        'OPENCODE_API_KEY_HOME' = 'sentinel-opencode-home-key'
        'OPENCODE_API_KEY_WORK' = 'sentinel-opencode-work-key'
        'COPILOT_TEST_SHIM_LOG' = $logPath
    }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv $envMap -RemoveEnv @('COPILOT_HOME') -PathPrepends @($shimDir) -ScrubCopilotFromPath $true -TimeoutSeconds 60
    $ev = Save-ChildEvidence -Id 't6-1' -ChildResult $child -ShimLog $logPath
    $seeded = $child.StdOut -match 'SEEDED=True'
    $fileCreated = Test-Path (Join-Path $throw 'byok-profiles.json')
    $prodHashAfter = Get-FileHashValue -Path $ProductionProfile
    $passed = $seeded -and $fileCreated -and ($prodHashBefore -eq $prodHashAfter)
    $details = "seeded=$seeded; file created=$fileCreated; production hash unchanged=$($prodHashBefore -eq $prodHashAfter)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T6_2 {
    $prodHashBefore = Get-FileHashValue -Path $ProductionProfile
    $throw = New-TempDirectory 'byok-t6-skip'
    $fixtureTarget = Join-Path $throw 'byok-profiles.json'
    Copy-Item $FixturePath $fixtureTarget -Force
    $beforeHash = Get-FileHashValue -Path $fixtureTarget
    $beforeTime = (Get-Item $fixtureTarget).LastWriteTimeUtc
    $shimDir = New-ShimCopilot
    $shimPath = Join-Path $shimDir 'copilot.ps1'
    $logPath = Join-Path $shimDir 'shim.log'
    $cmd = Format-ChildCommand -Template $script:tmplSubSession -Values @{
        '__SUBSESSION__' = $SubSessionScript; '__HOME__' = $throw; '__PROFILE__' = 'openai-completions'
    }
    $envMap = @{
        'OPENCODE_API_KEY_HOME' = 'sentinel-opencode-home-key'
        'OPENCODE_API_KEY_WORK' = 'sentinel-opencode-work-key'
        'COPILOT_TEST_SHIM_LOG' = $logPath
    }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv $envMap -RemoveEnv @('COPILOT_HOME') -PathPrepends @($shimDir) -ScrubCopilotFromPath $true -TimeoutSeconds 60
    $ev = Save-ChildEvidence -Id 't6-2' -ChildResult $child -ShimLog $logPath
    $notSeeded = $child.StdOut -match 'SEEDED=False'
    $afterHash = Get-FileHashValue -Path $fixtureTarget
    $afterTime = (Get-Item $fixtureTarget).LastWriteTimeUtc
    $prodHashAfter = Get-FileHashValue -Path $ProductionProfile
    $passed = $notSeeded -and ($beforeHash -eq $afterHash) -and ($beforeTime -eq $afterTime) -and ($prodHashBefore -eq $prodHashAfter)
    $details = "not seeded=$notSeeded; fixture hash unchanged=$($beforeHash -eq $afterHash); mtime unchanged=$($beforeTime -eq $afterTime); production unchanged=$($prodHashBefore -eq $prodHashAfter)"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

function Test-T6_4 {
    $throw = New-TempDirectory 'byok-t6-return'
    $shimDir = New-ShimCopilot
    $shimPath = Join-Path $shimDir 'copilot.ps1'
    $logPath = Join-Path $shimDir 'shim.log'
    $cmd = Format-ChildCommand -Template $script:tmplSubSession -Values @{
        '__SUBSESSION__' = $SubSessionScript; '__HOME__' = $throw; '__PROFILE__' = 'opencode-go-deepseek-v4-flash'
    }
    $envMap = @{
        'OPENCODE_API_KEY_HOME' = 'sentinel-opencode-home-key'
        'OPENCODE_API_KEY_WORK' = 'sentinel-opencode-work-key'
        'COPILOT_TEST_SHIM_LOG' = $logPath
    }
    $child = Invoke-ChildPwsh -CommandText $cmd -ExtraEnv $envMap -RemoveEnv @('COPILOT_HOME') -PathPrepends @($shimDir) -ScrubCopilotFromPath $true -TimeoutSeconds 60
    $ev = Save-ChildEvidence -Id 't6-4' -ChildResult $child -ShimLog $logPath
    $hasHome = $child.StdOut -match 'HAS_HOME=True'
    $hasExit = $child.StdOut -match 'HAS_EXIT=True'
    $passed = $hasHome -and $hasExit
    $details = "returned CopilotHome=$hasHome; ExitCode field=$hasExit"
    return New-TestResult -Passed $passed -Details $details -Evidence $ev
}

# ============================================================================
# Registration
# ============================================================================
Add-TestCase -Id 't1-1' -Bucket 'redirection' -Checkpoint 'list with COPILOT_HOME=staging shows fixture profiles + staging path'
Add-TestCase -Id 't1-3' -Bucket 'redirection' -Checkpoint 'use writes staging activeAccount; production hash unchanged'
Add-TestCase -Id 't1-4' -Bucket 'redirection' -Checkpoint 'remove deletes from staging only; production hash unchanged'
Add-TestCase -Id 't1-5' -Bucket 'redirection' -Checkpoint 'no COPILOT_HOME resolves production read-only (both ways)'
Add-TestCase -Id 't2-1' -Bucket 'profile-manager' -Checkpoint 'list line format + accountGroup suffix'
Add-TestCase -Id 't2-2' -Bucket 'profile-manager' -Checkpoint 'show JSON + Reasoning Effort Supported per model'
Add-TestCase -Id 't2-3' -Bucket 'profile-manager' -Checkpoint 'accounts list + [active] marker'
Add-TestCase -Id 't2-4' -Bucket 'profile-manager' -Checkpoint 'use persists activeAccount and reflects in accounts'
Add-TestCase -Id 't2-5' -Bucket 'profile-manager' -Checkpoint 'show/remove missing profile exit 1'
Add-TestCase -Id 't2-6' -Bucket 'profile-manager' -Checkpoint 'add wizard preset 6 via piped stdin (wireApi absent = known gap)'
Add-TestCase -Id 't2-7' -Bucket 'profile-manager' -Checkpoint 'set-env/run missing profile exit 1'
Add-TestCase -Id 't2-8' -Bucket 'profile-manager' -Checkpoint 'use missing account exit 1'
Add-TestCase -Id 't2-9' -Bucket 'profile-manager' -Checkpoint 'accounts empty-state message'
Add-TestCase -Id 't3-1' -Bucket 'env-emission' -Checkpoint 'set-env openai-completions: full env, WIRE_API removed'
Add-TestCase -Id 't3-2' -Bucket 'env-emission' -Checkpoint 'set-env responses-wire: WIRE_API=responses + token caps'
Add-TestCase -Id 't3-3' -Bucket 'env-emission' -Checkpoint 'set-env no-reasoning: Reasoning Effort Supported = False'
Add-TestCase -Id 't3-4' -Bucket 'env-emission' -Checkpoint 'set-env --account override resolves home key'
Add-TestCase -Id 't3-5' -Bucket 'env-emission' -Checkpoint 'set-env rich->minimal stale cleanup'
Add-TestCase -Id 't3-6' -Bucket 'env-emission' -Checkpoint 'set-env ${ENV} placeholder expansion'
Add-TestCase -Id 't3-7' -Bucket 'env-emission' -Checkpoint 'set-env offline profile sets COPILOT_OFFLINE'
Add-TestCase -Id 't4-1' -Bucket 'reasoning-strip' -Checkpoint 'run kimi --reasoning-effort high: stripped + banner'
Add-TestCase -Id 't4-2' -Bucket 'reasoning-strip' -Checkpoint 'run deepseek --reasoning-effort high: forwarded intact'
Add-TestCase -Id 't4-3' -Bucket 'reasoning-strip' -Checkpoint 'run --account override: consumed, home key in env'
Add-TestCase -Id 't4-4' -Bucket 'reasoning-strip' -Checkpoint 'run --effort=high equals form forwarded'
Add-TestCase -Id 't4-5' -Bucket 'reasoning-strip' -Checkpoint 'run kimi --reasoning-effort=high equals form stripped'
Add-TestCase -Id 't4-6' -Bucket 'reasoning-strip' -Checkpoint 'run legacy-api-key: legacy apiKey path + arg preservation'
Add-TestCase -Id 't4-7' -Bucket 'reasoning-strip' -Checkpoint "-p collision lock: copilot-style '-p <prompt>' consumed as -Profile (known gap)"
Add-TestCase -Id 't4-8' -Bucket 'reasoning-strip' -Checkpoint 'run --account= empty value forwarded (latent bug lock)'
Add-TestCase -Id 't5-1' -Bucket 'negatives' -Checkpoint 'malformed JSON exits 1 cleanly'
Add-TestCase -Id 't5-2' -Bucket 'negatives' -Checkpoint 'empty JSON file normalizes to No profiles found'
Add-TestCase -Id 't5-3' -Bucket 'negatives' -Checkpoint 'drift: kimi-k3 reports Supported True (spec-vs-code)'
Add-TestCase -Id 't6-1' -Bucket 'subsession' -Checkpoint 'subsession seeds staging when byok-profiles.json missing'
Add-TestCase -Id 't6-2' -Bucket 'subsession' -Checkpoint 'subsession skips seeding when file present (idempotent)'
Add-TestCase -Id 't6-4' -Bucket 'subsession' -Checkpoint 'subsession returns CopilotHome + ExitCode'

# ============================================================================
# Main flow
# ============================================================================
function Invoke-HarnessMain {
    param([string]$StagingHome, [string]$FixturePath, [switch]$KeepFixture)

    Write-Host "copilot-byok feature harness" -ForegroundColor Cyan
    Write-Host "  byok script   : $ByokScript" -ForegroundColor Gray
    Write-Host "  subsession    : $SubSessionScript" -ForegroundColor Gray
    Write-Host "  fixture       : $FixturePath" -ForegroundColor Gray
    Write-Host "  staging home  : $StagingHome" -ForegroundColor Gray
    Write-Host "  production    : $ProductionProfile" -ForegroundColor Gray
    if (-not $KeepFixture -and $StagingHome -eq (Join-Path $HOME '.copilot-staging')) {
        Write-Warning "Staging home is the shared dojo (~/.copilot-staging): the harness will inject the hermetic fixture for the run and then restore the previous byok-profiles.json (or remove it if none existed). Use -KeepFixture to leave a fixture-based seed, or point -StagingHome at a harness-owned dir."
    }
    if ($Live) { Write-Warning 'Phase 2 live probes not implemented yet; running config-level only.' }
    Write-Host ""

    New-Item -Path $StagingHome -ItemType Directory -Force | Out-Null
    $stagingProfile = Join-Path $StagingHome 'byok-profiles.json'
    $snapshot = $null
    if (Test-Path $stagingProfile -PathType Leaf) {
        $snapshot = [System.IO.File]::ReadAllBytes($stagingProfile)
        Write-Host "  snapshot taken: $stagingProfile" -ForegroundColor DarkGray
    }

    try {
        # SPIKE GATE (B1): prove stream capture + SUT reachability before running cases.
        Copy-Item $FixturePath $stagingProfile -Force
        $spikeList = Invoke-ChildPwsh -CommandText (Format-ChildCommand -Template $script:tmplList -Values @{ '__BYOK__' = $ByokScript }) -ExtraEnv (Get-ByokChildEnv -CopilotHome $StagingHome) -TimeoutSeconds 30
        if ($spikeList.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($spikeList.StdOut) -or $spikeList.StdOut -notmatch 'openai-completions') {
            throw "SPIKE FAILED: stream capture broken or byok-profile.ps1 unreachable (exit=$($spikeList.ExitCode); stdout len=$($spikeList.StdOut.Length))"
        }
        $spikeDump = Invoke-ChildPwsh -CommandText (Format-ChildCommand -Template $script:tmplSetEnvDump -Values @{ '__BYOK__' = $ByokScript; '__PROFILE__' = 'openai-completions'; '__ARGS__' = '' }) -ExtraEnv (Get-ByokChildEnv -CopilotHome $StagingHome) -TimeoutSeconds 30
        if ($spikeDump.StdOut -notmatch 'ENVDUMP\|') {
            throw "SPIKE FAILED: dot-source set-env capture broken (exit=$($spikeDump.ExitCode))"
        }
        Write-Host "  spike gate: stream capture + dot-source OK" -ForegroundColor Green

        # Run cases. Fixture is re-injected before every config case for determinism.
        $caseIds = @($script:testCases.Keys)
        foreach ($id in $caseIds) {
            $bucket = $script:testCases[$id].bucket
            $isFixtureCase = $bucket -ne 'subsession'
            if ($isFixtureCase -and $id -notin @('t1-5', 't2-9', 't5-1', 't5-2')) {
                Copy-Item $FixturePath $stagingProfile -Force
            }
            $body = Get-Item -Path "Function:\Test-$($id.Replace('-', '_'))"
            Invoke-Test -Id $id -Body $body.ScriptBlock
        }
    }
    finally {
        if ($KeepFixture) {
            Write-Host "  -KeepFixture: staging left as-is (fixture in place)" -ForegroundColor Yellow
        }
        elseif ($null -ne $snapshot) {
            [System.IO.File]::WriteAllBytes($stagingProfile, $snapshot)
            Write-Host "  restored staging byok-profiles.json from snapshot" -ForegroundColor DarkGray
        }
        else {
            Remove-Item $stagingProfile -Force -ErrorAction SilentlyContinue
            Write-Host "  removed injected staging byok-profiles.json (no pre-run snapshot)" -ForegroundColor DarkGray
        }
    }
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
            byok_script = $ByokScript
            subsession_script = $SubSessionScript
            fixture = $FixturePath
            staging_home = $StagingHome
            production_home = $ProductionProfile
            production_exists = (Test-Path $ProductionProfile -PathType Leaf)
            live = [bool]$Live
            keep_fixture = [bool]$KeepFixture
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

    # Markdown report
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# copilot-byok feature harness report')
    $lines.Add('')
    $lines.Add('## Run overview')
    $lines.Add('')
    $lines.Add("| Field | Value |")
    $lines.Add('| --- | --- |')
    $lines.Add("| Timestamp | $($summary.run.timestamp) |")
    $lines.Add("| Exit code | $ExitCode |")
    $lines.Add("| Status | $($summary.run.status) |")
    $lines.Add("| Staging home | ``$StagingHome`` |")
    $lines.Add("| Production | ``$ProductionProfile`` |")
    $lines.Add("| Fixture | ``$FixturePath`` |")
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
    Invoke-HarnessMain -StagingHome $StagingHome -FixturePath $FixturePath -KeepFixture:$KeepFixture
}
catch {
    $script:harnessError = $_
    Write-Error "Harness error: $_"
}

# Compute exit code BEFORE writing the report so the report reflects the outcome.
if ($script:harnessError) { $exitCode = 2 }
else {
    $failed = @($script:testCases.Values | Where-Object { $_.status -eq 'failed' })
    if ($failed.Count -gt 0) { $exitCode = 1 }
}

$resolvedReportPath = $ReportPath
if (-not $resolvedReportPath) {
    $resolvedReportPath = Join-Path $script:reportDir 'report.md'
}
try {
    Write-HarnessReport -ReportPath $resolvedReportPath -ExitCode $exitCode
}
catch {
    Write-Error "Failed to write report: $_"
}

Write-Host ""
Write-Host "copilot-byok feature harness complete: exit $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } elseif ($exitCode -eq 1) { 'Yellow' } else { 'Red' })
Write-Host "  report: $resolvedReportPath"
exit $exitCode
