<#
.SYNOPSIS
    Deterministic Ralph-v2 CLI smoke and publish-gate harness.

.DESCRIPTION
    Builds the Ralph-v2 CLI plugin bundle with the existing workspace build helper,
    installs that bundle into an isolated Copilot CLI config directory, verifies
    plugin discovery and installed cache state, and optionally runs one
    non-interactive agent invocation with pinned Copilot CLI settings.

    The harness uses the supported local install flow:
      copilot plugin install <local_plugin_path>

    Any on-disk cache layout discovered after installation is treated as an
    observed implementation detail and is detected dynamically rather than being
    assumed ahead of time.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('stable', 'beta')]
    [string]$Channel = 'beta',

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        'claude-sonnet-4.6',
        'claude-sonnet-4.5',
        'claude-haiku-4.5',
        'claude-opus-4.6',
        'claude-opus-4.6-fast',
        'claude-opus-4.5',
        'claude-sonnet-4',
        'gemini-3-pro-preview',
        'gpt-5.4',
        'gpt-5.3-codex',
        'gpt-5.2-codex',
        'gpt-5.2',
        'gpt-5.1-codex-max',
        'gpt-5.1-codex',
        'gpt-5.1',
        'gpt-5.1-codex-mini',
        'gpt-5-mini',
        'gpt-4.1'
    )]
    [string]$Model = 'gpt-5.2',

    [Parameter(Mandatory = $false)]
    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'low',

    [Parameter(Mandatory = $false)]
    [string]$ConfigDir,

    [Parameter(Mandatory = $false)]
    [string]$LogDir,

    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$SmokeOutputRelativePath = 'README.md',

    [Parameter(Mandatory = $false)]
    [int]$PromptTimeoutSeconds = 900,

    [Parameter(Mandatory = $false)]
    [string]$PromptText = '',

    [Parameter(Mandatory = $false)]
    [switch]$SkipAgentInvocation,

    [Parameter(Mandatory = $false)]
    [switch]$KeepConfigDir,

    [Parameter(Mandatory = $false)]
    [switch]$KeepLogDir,

    [Parameter(Mandatory = $false)]
    [switch]$KeepWorkingDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Import-BuildPluginFunctions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath -PathType Leaf)) {
        throw "Build helper script not found: $ScriptPath"
    }

    $buildModule = New-Module -Name "copilot-build-plugins-smoke-$PID" -ScriptBlock {
        param([string]$InnerScriptPath)

        . $InnerScriptPath
        Export-ModuleMember -Function *
    } -ArgumentList $ScriptPath

    Import-Module $buildModule -Force -DisableNameChecking | Out-Null
}

function Resolve-CommandExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandName
    )

    $command = Get-Command $CommandName -ErrorAction Stop

    if ($command.CommandType -eq 'Application') {
        return [PSCustomObject]@{
            FilePath = $command.Source
            PrefixArguments = @()
        }
    }

    if ($command.CommandType -in @('ExternalScript', 'Script')) {
        $powerShellHost = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if ($null -eq $powerShellHost) {
            $powerShellHost = Get-Command 'powershell' -ErrorAction SilentlyContinue
        }

        if ($null -eq $powerShellHost) {
            throw "Unable to resolve a PowerShell host executable for command '$CommandName'."
        }

        return [PSCustomObject]@{
            FilePath = $powerShellHost.Source
            PrefixArguments = @('-NoProfile', '-File', $command.Source)
        }
    }

    throw "Unsupported command type for '$CommandName': $($command.CommandType)"
}

function New-TemporaryDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prefix
    )

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    return $path
}

function ConvertTo-DisplayCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $parts = @($FilePath)
    foreach ($argument in $Arguments) {
        if ($argument -match '\s|"') {
            $escaped = $argument.Replace('"', '\"')
            $parts += '"{0}"' -f $escaped
            continue
        }

        $parts += $argument
    }

    return ($parts -join ' ')
}

function Invoke-ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [int]$TimeoutSeconds = 120,
        [int]$TimeoutGraceSeconds = 0
    )

    $commandLine = ConvertTo-DisplayCommandLine -FilePath $FilePath -Arguments $Arguments

    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = $FilePath
    $processStartInfo.WorkingDirectory = $WorkingDirectory
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.RedirectStandardError = $true
    $processStartInfo.CreateNoWindow = $true

    foreach ($argument in $Arguments) {
        [void]$processStartInfo.ArgumentList.Add($argument)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processStartInfo

    if (-not $process.Start()) {
        throw "Failed to start command: $commandLine"
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $gracePeriodUsed = $false
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        if (($TimeoutGraceSeconds -gt 0) -and $process.WaitForExit($TimeoutGraceSeconds * 1000)) {
            $gracePeriodUsed = $true
        }
        else {
            try {
                $process.Kill()
            }
            catch {
            }

            $timeoutDescription = if ($TimeoutGraceSeconds -gt 0) {
                "{0} second(s) plus {1} second(s) grace" -f $TimeoutSeconds, $TimeoutGraceSeconds
            }
            else {
                "$TimeoutSeconds second(s)"
            }

            throw "Command timed out after ${timeoutDescription}: $commandLine"
        }
    }

    if ($gracePeriodUsed) {
        try {
            $process.WaitForExit()
        }
        catch {
        }
    }

    $process.WaitForExit()
    $stdoutTask.Wait()
    $stderrTask.Wait()

    return [PSCustomObject]@{
        CommandLine = $commandLine
        ExitCode = $process.ExitCode
        StdOut = $stdoutTask.Result.TrimEnd()
        StdErr = $stderrTask.Result.TrimEnd()
        RequestedTimeoutSeconds = $TimeoutSeconds
        TimeoutGraceSeconds = $TimeoutGraceSeconds
        GracePeriodUsed = $gracePeriodUsed
    }
}

function New-SmokeSessionId {
    [CmdletBinding()]
    param()

    return (Get-Date).ToUniversalTime().ToString('yyMMdd-HHmmss')
}

function Get-DefaultSmokePromptText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$SmokeOutputRelativePath
    )

    return @"
SESSION_PATH: .ralph-sessions/$SessionId/

USER_REQUEST: Run one minimal Ralph-v2 smoke session in this disposable workspace using the existing session path above. Create exactly one tiny documentation task whose only product-file change is in ${SmokeOutputRelativePath}: append a single bullet immediately after `- Seed bullet.` with exact text `- Ralph-v2 smoke session completed.`. Ralph workflow artifacts such as progress, task, question, report, metadata, and explicit knowledge-skip markers are expected and must not count as extra product-file changes. Keep the task success criteria verifiable by direct workspace inspection and normal Ralph artifacts only; do not require git diff output, shell-generated proof files, or any reviewer evidence that depends on tools outside the normal Ralph role workflow. Keep all other scope minimal, use the normal Ralph planning/questioner/executor/reviewer/librarian flow, and stop once iteration 1 reaches COMPLETE. Always route the knowledge step through the Ralph librarian before completion; if nothing reusable exists, have the librarian explicitly record the skip/cancel decision in the iteration artifacts instead of expanding scope. Final response format (only these lines, and only after iteration 1 reaches COMPLETE):
SESSION_PATH: <path>
FINAL_STATE: <state>
"@.Trim()
}

function Initialize-SmokeWorkspaceFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$SessionId
    )

    New-Item -Path $WorkingDirectory -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $WorkingDirectory '.docs') -ItemType Directory -Force | Out-Null
    $sessionRoot = Join-Path $WorkingDirectory '.ralph-sessions'
    New-Item -Path $sessionRoot -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $WorkingDirectory 'knowledge') -ItemType Directory -Force | Out-Null
    $sessionPath = Join-Path $sessionRoot $SessionId

    foreach ($path in @(
            $sessionPath,
            (Join-Path $sessionPath 'signals'),
            (Join-Path $sessionPath 'signals\inputs'),
            (Join-Path $sessionPath 'signals\acks'),
            (Join-Path $sessionPath 'signals\processed'),
            (Join-Path $WorkingDirectory 'iterations'),
            (Join-Path $WorkingDirectory 'iterations\1'),
            (Join-Path $WorkingDirectory 'iterations\1\tasks'),
            (Join-Path $WorkingDirectory 'iterations\1\questions'),
            (Join-Path $WorkingDirectory 'iterations\1\reports'),
            (Join-Path $WorkingDirectory 'iterations\1\tests'),
            (Join-Path $WorkingDirectory 'iterations\1\feedbacks'),
            (Join-Path $WorkingDirectory 'iterations\1\knowledge')
        )) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }

    $readmePath = Join-Path $WorkingDirectory 'README.md'
    if (-not (Test-Path $readmePath -PathType Leaf)) {
        Write-Utf8File -Path $readmePath -Content "# Smoke Seed`n`n- Seed bullet."
    }

    $docsReadmePath = Join-Path $WorkingDirectory '.docs\README.md'
    if (-not (Test-Path $docsReadmePath -PathType Leaf)) {
        Write-Utf8File -Path $docsReadmePath -Content "# Smoke Fixture Docs`n`nThis folder exists so the Ralph smoke harness can validate knowledge promotion in an isolated workspace."
    }

    $gitignorePath = Join-Path $WorkingDirectory '.gitignore'
    if (-not (Test-Path $gitignorePath -PathType Leaf)) {
        Write-Utf8File -Path $gitignorePath -Content ".ralph-sessions/`n"
    }

    $gitCommand = Resolve-CommandExecution -CommandName 'git'
    $gitDir = Join-Path $WorkingDirectory '.git'
    if (-not (Test-Path $gitDir -PathType Container)) {
        $null = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('init', '--initial-branch=main')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
    }

    $null = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('config', 'user.name', 'Ralph Smoke Harness')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
    $null = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('config', 'user.email', 'ralph-smoke@example.invalid')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
    $null = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('add', '.')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30

    $statusResult = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('status', '--short')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
    if (-not [string]::IsNullOrWhiteSpace($statusResult.StdOut)) {
        $null = Invoke-ExternalCommand -FilePath $gitCommand.FilePath -Arguments ($gitCommand.PrefixArguments + @('commit', '-m', 'chore: initialize smoke fixture')) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
    }
}

function Get-JsonFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    Assert-True -Condition (Test-Path $Path -PathType Leaf) -Message "Expected JSON file was not found: $Path"
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-CopilotConfigRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigRoot
    )

    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add([System.IO.Path]::GetFullPath($ConfigRoot))

    $homeRoot = if (-not [string]::IsNullOrWhiteSpace($HOME)) {
        Join-Path $HOME '.copilot'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        Join-Path $env:USERPROFILE '.copilot'
    }
    else {
        $null
    }

    if (-not [string]::IsNullOrWhiteSpace($homeRoot)) {
        $resolvedHomeRoot = [System.IO.Path]::GetFullPath($homeRoot)
        if ($resolvedHomeRoot -notin $roots) {
            $roots.Add($resolvedHomeRoot)
        }
    }

    return @($roots)
}

function Get-InstalledPluginManifestCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ConfigRoots,
        [Parameter(Mandatory)][string]$ExpectedPluginName
    )

    $candidates = @()
    foreach ($configRoot in $ConfigRoots) {
        $installedPluginsRoot = Join-Path $configRoot 'installed-plugins'
        if (-not (Test-Path $installedPluginsRoot -PathType Container)) {
            continue
        }

        $manifestPaths = Get-ChildItem -Path $installedPluginsRoot -Filter 'plugin.json' -File -Recurse -ErrorAction SilentlyContinue
        foreach ($manifestPath in $manifestPaths) {
            try {
                $manifest = Get-JsonFileContent -Path $manifestPath.FullName
            }
            catch {
                continue
            }

            if ($manifest.name -ne $ExpectedPluginName) {
                continue
            }

            $relativePath = [System.IO.Path]::GetRelativePath($installedPluginsRoot, $manifestPath.Directory.FullName)
            $cacheKind = if ($relativePath -match '^(?i)_direct(?:\\|$)') { '_direct' } else { 'detected' }

            $candidates += [PSCustomObject]@{
                ConfigRoot = $configRoot
                Path = $manifestPath.Directory.FullName
                RelativePath = $relativePath
                CacheKind = $cacheKind
                Manifest = $manifest
            }
        }
    }

    return $candidates
}

function Get-PreferredInstalledPluginManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Candidates,
        [Parameter(Mandatory)][string]$ExpectedVersion
    )

    $matchingVersion = @($Candidates | Where-Object { $_.Manifest.version -eq $ExpectedVersion })
    if (@($matchingVersion).Count -eq 0) {
        return $null
    }

    $preferredDirect = @($matchingVersion | Where-Object { $_.CacheKind -eq '_direct' } | Select-Object -First 1)
    if (@($preferredDirect).Count -gt 0) {
        return $preferredDirect[0]
    }

    return $matchingVersion | Select-Object -First 1
}

function Get-BundledAgentNameMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][string]$PluginName
    )

    $agentDir = Join-Path $BuildDir 'agents'
    Assert-True -Condition (Test-Path $agentDir -PathType Container) -Message "Built bundle is missing agents directory: $agentDir"

    $rolePatterns = [ordered]@{
        orchestrator = '*orchestrator*.agent.md'
        planner = '*planner*.agent.md'
        questioner = '*questioner*.agent.md'
        executor = '*executor*.agent.md'
        reviewer = '*reviewer*.agent.md'
        librarian = '*librarian*.agent.md'
    }
    $agentMap = [ordered]@{}

    foreach ($role in $rolePatterns.GetEnumerator()) {
        $agentFile = Get-ChildItem -Path $agentDir -Filter $role.Value -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
        Assert-True -Condition ($null -ne $agentFile) -Message "Built bundle is missing the Ralph $($role.Key) agent."

        $agentName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($agentFile.Name))
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($agentName)) -Message "Built $($role.Key) agent filename could not be resolved: $($agentFile.FullName)"
        $agentMap[$role.Key] = ('{0}/{1}' -f $PluginName, $agentName)
    }

    return [PSCustomObject]$agentMap
}

function Get-OrchestratorAgentNameFromBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][string]$PluginName
    )

    return (Get-BundledAgentNameMap -BuildDir $BuildDir -PluginName $PluginName).orchestrator
}

function New-SmokeTestCases {
    [CmdletBinding()]
    param()

    return [ordered]@{
        'copilot-version' = [ordered]@{
            id = 'copilot-version'
            bucket = 'overall'
            checkpoint = 'Resolve the Copilot CLI command and verify copilot --version succeeds'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'build-cli-bundle' = [ordered]@{
            id = 'build-cli-bundle'
            bucket = 'build'
            checkpoint = 'Build the Ralph CLI plugin bundle and validate the bundled manifest contract'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'install-cli-plugin' = [ordered]@{
            id = 'install-cli-plugin'
            bucket = 'install'
            checkpoint = 'Install the built Ralph plugin into the isolated Copilot config directory'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'verify-plugin-discovery' = [ordered]@{
            id = 'verify-plugin-discovery'
            bucket = 'install'
            checkpoint = 'Verify plugin discovery via copilot plugin list and installed manifest detection'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'orchestrator-invocation' = [ordered]@{
            id = 'orchestrator-invocation'
            bucket = 'orchestration'
            checkpoint = 'Invoke the Ralph orchestrator with a real session-driven smoke scenario'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'orchestrator-session-state' = [ordered]@{
            id = 'orchestrator-session-state'
            bucket = 'orchestration'
            checkpoint = 'Verify Ralph session metadata reached a reviewable terminal state and session artifacts were produced'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'planner-artifacts' = [ordered]@{
            id = 'planner-artifacts'
            bucket = 'planner'
            checkpoint = 'Verify planner-owned artifacts were created for the smoke session'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'questioner-artifacts' = [ordered]@{
            id = 'questioner-artifacts'
            bucket = 'questioner'
            checkpoint = 'Verify questioner-owned planning artifacts were created for the smoke session'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'executor-artifacts' = [ordered]@{
            id = 'executor-artifacts'
            bucket = 'executor'
            checkpoint = 'Verify executor-created workspace and report artifacts exist for the smoke scenario'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'reviewer-artifacts' = [ordered]@{
            id = 'reviewer-artifacts'
            bucket = 'reviewer'
            checkpoint = 'Verify reviewer verdict and iteration-review artifacts exist for the smoke session'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'librarian-artifacts' = [ordered]@{
            id = 'librarian-artifacts'
            bucket = 'librarian'
            checkpoint = 'Verify librarian knowledge-pipeline artifacts were created or explicitly recorded'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'cleanup' = [ordered]@{
            id = 'cleanup'
            bucket = 'cleanup'
            checkpoint = 'Clean up the installed plugin and transient directories as configured'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
        'overall' = [ordered]@{
            id = 'overall'
            bucket = 'overall'
            checkpoint = 'Overall smoke run completed and review artifacts were written for this execution'
            status = 'pending'
            details = 'Pending execution.'
            evidence = @()
        }
    }
}

function Set-TestCaseStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('pending', 'passed', 'skipped', 'failed', 'not_run')][string]$Status,
        [string]$Details
    )

    Assert-True -Condition ($script:testCases.Contains($Id)) -Message "Unknown smoke test case id: $Id"
    $testCase = $script:testCases[$Id]
    $testCase.status = $Status

    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        $testCase.details = $Details
    }
}

function Add-TestCaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string[]]$EvidencePaths
    )

    Assert-True -Condition ($script:testCases.Contains($Id)) -Message "Unknown smoke test case id: $Id"
    $testCase = $script:testCases[$Id]
    $evidence = New-Object System.Collections.Generic.List[string]

    foreach ($path in @($testCase.evidence + $EvidencePaths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if ($path -notin $evidence) {
            $evidence.Add($path)
        }
    }

    $testCase.evidence = @($evidence)
}

function Complete-PendingTestCases {
    [CmdletBinding()]
    param()

    foreach ($testCase in $script:testCases.Values) {
        if ($testCase.status -eq 'pending') {
            $testCase.status = 'not_run'
            $testCase.details = 'Not executed because the smoke harness exited before reaching this checkpoint.'
        }
    }
}

function Get-TestCaseList {
    [CmdletBinding()]
    param()

    return @(
        foreach ($testCase in $script:testCases.Values) {
            [PSCustomObject]@{
                id = $testCase.id
                bucket = $testCase.bucket
                checkpoint = $testCase.checkpoint
                status = $testCase.status
                details = $testCase.details
                evidence = @($testCase.evidence)
            }
        }
    )
}

function Get-TestCaseCounts {
    [CmdletBinding()]
    param()

    $countMap = [ordered]@{
        total = 0
        passed = 0
        skipped = 0
        failed = 0
        not_run = 0
        pending = 0
    }

    foreach ($testCase in $script:testCases.Values) {
        if ($testCase.id -eq 'overall') {
            continue
        }

        $countMap.total++
        if ($countMap.Contains($testCase.status)) {
            $countMap[$testCase.status]++
        }
    }

    return [PSCustomObject]$countMap
}

function Write-Utf8File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][AllowNull()][string]$Content
    )

    $parentPath = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $text = if ($null -eq $Content) { '' } else { $Content }
    [System.IO.File]::WriteAllText($Path, $text, $encoding)
}

function Write-JsonArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject,
        [int]$Depth = 12
    )

    Write-Utf8File -Path $Path -Content ($InputObject | ConvertTo-Json -Depth $Depth)
}

function Get-MarkdownRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath).Replace('\', '/')
}

function ConvertTo-MarkdownCell {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        return '-'
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '-'
    }

    return $text.Replace('|', '\|').Replace("`r`n", '<br/>').Replace("`n", '<br/>').Replace("`r", '<br/>')
}

function Get-TestCaseStatusIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status
    )

    switch ($Status) {
        'passed' { return '✅' }
        'skipped' { return '⏭️' }
        'failed' { return '❌' }
        'not_run' { return '⚪' }
        default { return '⏳' }
    }
}

function New-EvidenceArtifactRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Path,
        [string]$Kind = 'file',
        [bool]$Truncated = $false,
        [Nullable[int]]$OriginalLength = $null,
        [Nullable[int]]$StoredLength = $null,
        [string]$Notes,
        [string]$CommandLine
    )

    return [PSCustomObject]@{
        category = $Category
        description = $Description
        path = $Path
        kind = $Kind
        truncated = $Truncated
        original_length = $OriginalLength
        stored_length = $StoredLength
        notes = $Notes
        command = $CommandLine
    }
}

function Add-EvidenceArtifact {
    [CmdletBinding()]
    param(
        [System.Collections.Generic.List[object]]$Artifacts,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Description,
        [string]$Path,
        [string]$Kind = 'file',
        [bool]$Truncated = $false,
        [Nullable[int]]$OriginalLength = $null,
        [Nullable[int]]$StoredLength = $null,
        [string]$Notes,
        [string]$CommandLine
    )

    Assert-True -Condition ($null -ne $Artifacts) -Message 'Evidence artifact collection was not initialized.'

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $Artifacts.Add((New-EvidenceArtifactRecord -Category $Category -Description $Description -Path $Path -Kind $Kind -Truncated $Truncated -OriginalLength $OriginalLength -StoredLength $StoredLength -Notes $Notes -CommandLine $CommandLine))
}

function Get-TextArtifactSnapshot {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Content,
        [int]$MaxLength = 24000
    )

    $text = if ($null -eq $Content) { '' } else { $Content }
    $originalLength = $text.Length

    if ($originalLength -le $MaxLength) {
        return [PSCustomObject]@{
            Content = $text
            Truncated = $false
            OriginalLength = $originalLength
            StoredLength = $originalLength
            Notes = "Stored verbatim ($originalLength characters)."
        }
    }

    $marker = [Environment]::NewLine + "[TRUNCATED for review: original length $originalLength characters; head and tail preserved]" + [Environment]::NewLine
    $availableLength = [Math]::Max(0, $MaxLength - $marker.Length)
    $headLength = [Math]::Floor($availableLength / 2)
    $tailLength = $availableLength - $headLength
    $truncatedContent = $text.Substring(0, $headLength) + $marker + $text.Substring($originalLength - $tailLength)

    return [PSCustomObject]@{
        Content = $truncatedContent
        Truncated = $true
        OriginalLength = $originalLength
        StoredLength = $truncatedContent.Length
        Notes = "Truncated for reviewability (original $originalLength characters; stored $($truncatedContent.Length) characters)."
    }
}

function Write-TextEvidenceArtifact {
    [CmdletBinding()]
    param(
        [System.Collections.Generic.List[object]]$Artifacts,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$Content,
        [int]$MaxLength = 24000,
        [string]$CommandLine
    )

    $snapshot = Get-TextArtifactSnapshot -Content $Content -MaxLength $MaxLength
    Write-Utf8File -Path $Path -Content $snapshot.Content
    Add-EvidenceArtifact -Artifacts $Artifacts -Category $Category -Description $Description -Path $Path -Kind 'text' -Truncated $snapshot.Truncated -OriginalLength $snapshot.OriginalLength -StoredLength $snapshot.StoredLength -Notes $snapshot.Notes -CommandLine $CommandLine
    return $Path
}

function Get-EvidenceArtifactNoteText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Artifact
    )

    $notes = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Artifact.notes)) {
        $notes.Add($Artifact.notes)
    }

    if (-not [string]::IsNullOrWhiteSpace($Artifact.command)) {
        $notes.Add('Command captured in summary/commands artifact.')
    }

    if ((Get-CollectionCount -Value $notes) -eq 0) {
        return '-'
    }

    return ($notes -join ' ')
}

function Get-FileTextIfExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        return $null
    }

    return Get-Content -Path $Path -Raw
}

function Copy-PathToEvidenceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$SnapshotRoot,
        [Parameter(Mandatory)][string]$RelativeDestination
    )

    if (-not (Test-Path $SourcePath)) {
        return $null
    }

    $destinationPath = Join-Path $SnapshotRoot $RelativeDestination
    $destinationParent = Split-Path -Path $destinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationParent)) {
        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $destinationPath) {
        Remove-Item -Path $destinationPath -Recurse -Force
    }

    Copy-Item -Path $SourcePath -Destination $destinationPath -Recurse -Force
    return $destinationPath
}

function Test-ProgressFileContainsPattern {
    [CmdletBinding()]
    param(
        [string]$ProgressContent,
        [Parameter(Mandatory)][string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($ProgressContent)) {
        return $false
    }

    return $ProgressContent -match $Pattern
}

function Get-WorkspaceSnapshotPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$WorkspaceSnapshotRoot
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or
        [string]::IsNullOrWhiteSpace($WorkspaceRoot) -or
        [string]::IsNullOrWhiteSpace($WorkspaceSnapshotRoot)) {
        return $null
    }

    $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    $resolvedWorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    $resolvedSnapshotRoot = [System.IO.Path]::GetFullPath($WorkspaceSnapshotRoot)
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedWorkspaceRoot, $resolvedSourcePath)
    if ($relativePath.StartsWith('..')) {
        return $null
    }

    return Join-Path $resolvedSnapshotRoot $relativePath
}

function Join-DetailSentences {
    [CmdletBinding()]
    param(
        [string[]]$Parts
    )

    return ((@($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ') -replace '\s+', ' ').Trim()
}

function Get-LogEvidenceMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot) -or -not (Test-Path $LogRoot -PathType Container)) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    $regex = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($logFile in @(Get-ChildItem -Path $LogRoot -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $lineNumber = 0
        foreach ($line in Get-Content -Path $logFile.FullName -ErrorAction SilentlyContinue) {
            $lineNumber++
            if ($regex.IsMatch($line)) {
                $results.Add([PSCustomObject]@{
                        path = $logFile.FullName
                        line_number = $lineNumber
                        text = $line.Trim()
                    })
            }
        }
    }

    return @($results.ToArray())
}

function Get-RalphSubagentProvenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][object]$BundledAgentNames
    )

    $roles = @(
        [PSCustomObject]@{ id = 'planner-artifacts'; label = 'Planner'; agent_name = [string]$BundledAgentNames.planner },
        [PSCustomObject]@{ id = 'questioner-artifacts'; label = 'Questioner'; agent_name = [string]$BundledAgentNames.questioner },
        [PSCustomObject]@{ id = 'executor-artifacts'; label = 'Executor'; agent_name = [string]$BundledAgentNames.executor },
        [PSCustomObject]@{ id = 'reviewer-artifacts'; label = 'Reviewer'; agent_name = [string]$BundledAgentNames.reviewer },
        [PSCustomObject]@{ id = 'librarian-artifacts'; label = 'Librarian'; agent_name = [string]$BundledAgentNames.librarian }
    )
    $provenance = New-Object System.Collections.Generic.List[object]

    foreach ($role in $roles) {
        $escapedAgentName = [regex]::Escape($role.agent_name)
        $taskToolMatches = @(Get-LogEvidenceMatches -LogRoot $LogRoot -Pattern ("Task tool invoked with agent_type:\s*{0}(?:\s|,|$)" -f $escapedAgentName))
        $customAgentMatches = @(Get-LogEvidenceMatches -LogRoot $LogRoot -Pattern ("Custom agent ""{0}""" -f $escapedAgentName))
        $allMatches = @($taskToolMatches) + @($customAgentMatches)
        $sessionReferenceMatches = if ([string]::IsNullOrWhiteSpace($SessionId)) {
            @()
        }
        else {
            @($allMatches | Where-Object { $_.text -match [regex]::Escape($SessionId) })
        }
        $matchedFiles = @(
            foreach ($match in $allMatches) {
                $match.path
            }
        ) | Select-Object -Unique
        $sampleMatches = @(
            foreach ($match in @($allMatches | Select-Object -First 8)) {
                [ordered]@{
                    path = $match.path
                    line_number = $match.line_number
                    text = $match.text
                }
            }
        )
        $observed = (@($taskToolMatches).Count -ge 1) -or (@($customAgentMatches).Count -ge 1)

        $provenance.Add([PSCustomObject]@{
                id = $role.id
                label = $role.label
                agent_name = $role.agent_name
                observed = [bool]$observed
                task_tool_invocation_count = @($taskToolMatches).Count
                custom_agent_invocation_count = @($customAgentMatches).Count
                session_reference_count = @($sessionReferenceMatches).Count
                matched_files = @($matchedFiles)
                sample_matches = @($sampleMatches)
                evidence_paths = @()
                notes = $(if ($observed) {
                        Join-DetailSentences -Parts @(
                            "Observed custom agent '$($role.agent_name)' in Copilot CLI logs ($(@($taskToolMatches).Count) task-tool line(s), $(@($customAgentMatches).Count) custom-agent line(s)).",
                            $(if (@($sessionReferenceMatches).Count -ge 1) { "$(@($sessionReferenceMatches).Count) matched line(s) referenced session '$SessionId'." } else { "Matched lines did not echo session '$SessionId', so the proof relies on the current run's isolated log directory." })
                        )
                    }
                    else {
                        "No Copilot CLI log evidence was captured for custom agent '$($role.agent_name)'."
                    })
            })
    }

    return @($provenance.ToArray())
}

function Get-CollectionCount {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        return 0
    }

    if ($Value -is [string]) {
        return 1
    }

    if ($Value -is [System.Collections.ICollection]) {
        return $Value.Count
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value).Count
    }

    return 1
}

function Get-RalphFinalResponseFields {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Output
    )

    $sessionMatches = if ([string]::IsNullOrWhiteSpace($Output)) {
        @()
    }
    else {
        @([regex]::Matches($Output, '(?im)SESSION_PATH:\s*(?<session>\S+)'))
    }

    $stateMatches = if ([string]::IsNullOrWhiteSpace($Output)) {
        @()
    }
    else {
        @([regex]::Matches($Output, '(?im)FINAL_STATE:\s*(?<state>[A-Z_]+)'))
    }

    $sessionMatchCount = Get-CollectionCount -Value $sessionMatches
    $stateMatchCount = Get-CollectionCount -Value $stateMatches

    return [PSCustomObject]@{
        session_path = if ($sessionMatchCount -gt 0) { $sessionMatches[$sessionMatchCount - 1].Groups['session'].Value } else { $null }
        final_state = if ($stateMatchCount -gt 0) { $stateMatches[$stateMatchCount - 1].Groups['state'].Value } else { $null }
        has_session_path = $sessionMatchCount -gt 0
        has_final_state = $stateMatchCount -gt 0
    }
}

function Test-DirectoryHasFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return $false
    }

    return $null -ne (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function New-RalphWorkflowArtifactLayoutCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LayoutId,
        [Parameter(Mandatory)][string]$MetadataPath,
        [Parameter(Mandatory)][string]$IterationDirectory
    )

    $iterationMetadataPath = Join-Path $IterationDirectory 'metadata.yaml'
    $iterationPlanPath = Join-Path $IterationDirectory 'plan.md'
    $iterationProgressPath = Join-Path $IterationDirectory 'progress.md'
    $iterationReviewPath = Join-Path $IterationDirectory 'review.md'
    $taskDirectory = Join-Path $IterationDirectory 'tasks'
    $questionDirectory = Join-Path $IterationDirectory 'questions'
    $reportDirectoryPath = Join-Path $IterationDirectory 'reports'
    $iterationKnowledgePath = Join-Path $IterationDirectory 'knowledge'
    $metadataContent = Get-FileTextIfExists -Path $MetadataPath
    $hasMetadata = Test-Path $MetadataPath -PathType Leaf
    $hasCompleteState = (-not [string]::IsNullOrWhiteSpace($metadataContent)) -and ($metadataContent -match '(?m)^\s*state\s*:\s*COMPLETE\s*$')
    $hasIterationMetadata = Test-Path $iterationMetadataPath -PathType Leaf
    $hasPlan = Test-Path $iterationPlanPath -PathType Leaf
    $hasProgress = Test-Path $iterationProgressPath -PathType Leaf
    $hasReview = Test-Path $iterationReviewPath -PathType Leaf
    $hasTasks = Test-DirectoryHasFiles -Path $taskDirectory
    $hasQuestions = Test-DirectoryHasFiles -Path $questionDirectory
    $hasReports = Test-DirectoryHasFiles -Path $reportDirectoryPath
    $hasKnowledge = Test-DirectoryHasFiles -Path $iterationKnowledgePath
    $signalPaths = New-Object System.Collections.Generic.List[string]
    $signalLabels = New-Object System.Collections.Generic.List[string]

    if ($hasMetadata) {
        $signalPaths.Add($MetadataPath)
        $signalLabels.Add('metadata')
    }
    if ($hasCompleteState) {
        $signalLabels.Add('metadata:COMPLETE')
    }
    if ($hasIterationMetadata) {
        $signalPaths.Add($iterationMetadataPath)
        $signalLabels.Add('iteration-metadata')
    }
    if ($hasPlan) {
        $signalPaths.Add($iterationPlanPath)
        $signalLabels.Add('plan')
    }
    if ($hasProgress) {
        $signalPaths.Add($iterationProgressPath)
        $signalLabels.Add('progress')
    }
    if ($hasReview) {
        $signalPaths.Add($iterationReviewPath)
        $signalLabels.Add('review')
    }

    if ($hasTasks) {
        $signalPaths.Add($taskDirectory)
        $signalLabels.Add('tasks')
    }
    if ($hasQuestions) {
        $signalPaths.Add($questionDirectory)
        $signalLabels.Add('questions')
    }
    if ($hasReports) {
        $signalPaths.Add($reportDirectoryPath)
        $signalLabels.Add('reports')
    }
    if ($hasKnowledge) {
        $signalPaths.Add($iterationKnowledgePath)
        $signalLabels.Add('knowledge')
    }

    $label = switch ($LayoutId) {
        'session-local' { 'session-local (.ralph-sessions/<id>/metadata.yaml + .ralph-sessions/<id>/iterations/1)' }
        'root-level' { 'root-level (metadata.yaml + iterations/1)' }
        default { $LayoutId }
    }
    $iterationSignalCount = Get-CollectionCount -Value @($signalLabels | Where-Object { $_ -in @('iteration-metadata', 'plan', 'progress', 'review', 'tasks', 'questions', 'reports', 'knowledge') })
    $signalPathCount = Get-CollectionCount -Value $signalPaths
    $score = 0
    if ($hasMetadata) { $score += 1 }
    if ($hasCompleteState) { $score += 2 }
    if ($hasIterationMetadata) { $score += 2 }
    if ($hasPlan) { $score += 3 }
    if ($hasProgress) { $score += 3 }
    if ($hasReview) { $score += 3 }
    if ($hasTasks) { $score += 3 }
    if ($hasQuestions) { $score += 2 }
    if ($hasReports) { $score += 3 }
    if ($hasKnowledge) { $score += 1 }

    return [PSCustomObject]@{
        layout_id = $LayoutId
        label = $label
        metadata_path = $MetadataPath
        iteration_directory = $IterationDirectory
        iteration_metadata_path = $iterationMetadataPath
        iteration_plan_path = $iterationPlanPath
        iteration_progress_path = $iterationProgressPath
        iteration_review_path = $iterationReviewPath
        task_directory = $taskDirectory
        question_directory = $questionDirectory
        report_directory = $reportDirectoryPath
        iteration_knowledge_path = $iterationKnowledgePath
        score = $score
        signal_count = $signalPathCount
        iteration_signal_count = $iterationSignalCount
        signal_paths = @($signalPaths | Select-Object -Unique)
        signal_labels = @($signalLabels | Select-Object -Unique)
        has_signals = $signalPathCount -gt 0
    }
}

function Resolve-RalphWorkflowArtifactLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$SessionPath
    )

    $sessionCandidate = New-RalphWorkflowArtifactLayoutCandidate -LayoutId 'session-local' -MetadataPath (Join-Path $SessionPath 'metadata.yaml') -IterationDirectory (Join-Path $SessionPath 'iterations\1')
    $rootCandidate = New-RalphWorkflowArtifactLayoutCandidate -LayoutId 'root-level' -MetadataPath (Join-Path $WorkspaceRoot 'metadata.yaml') -IterationDirectory (Join-Path $WorkspaceRoot 'iterations\1')
    $resolvedCandidate = if (($sessionCandidate.score -gt 0) -or ($rootCandidate.score -gt 0)) {
        if ($sessionCandidate.score -gt $rootCandidate.score) {
            $sessionCandidate
        }
        elseif ($rootCandidate.score -gt $sessionCandidate.score) {
            $rootCandidate
        }
        elseif ($sessionCandidate.has_signals) {
            $sessionCandidate
        }
        else {
            $rootCandidate
        }
    }
    else {
        $null
    }

    $detectedLayout = if ($null -ne $resolvedCandidate) { $resolvedCandidate.layout_id } else { 'undetected' }
    $detectionNotes = if ($null -ne $resolvedCandidate) {
        "Detected $($resolvedCandidate.label). Session-local score: $($sessionCandidate.score) [$((@($sessionCandidate.signal_labels) -join ', '))]; root-level score: $($rootCandidate.score) [$((@($rootCandidate.signal_labels) -join ', '))]."
    }
    else {
        "No durable Ralph workflow artifacts were detected in either supported layout. Session-local score: $($sessionCandidate.score); root-level score: $($rootCandidate.score)."
    }

    return [PSCustomObject]@{
        detected_layout = $detectedLayout
        label = if ($null -ne $resolvedCandidate) { $resolvedCandidate.label } else { 'undetected' }
        description = switch ($detectedLayout) {
            'session-local' { 'Validation resolved artifacts from the session-local .ralph-sessions/<id>/... layout.' }
            'root-level' { 'Validation resolved artifacts from the root-level workspace metadata.yaml + iterations/1 layout.' }
            default { 'Validation could not confirm whether the runtime used the session-local or root-level layout.' }
        }
        detection_notes = $detectionNotes
        metadata_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.metadata_path } else { $null }
        iteration_directory = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_directory } else { $null }
        iteration_metadata_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_metadata_path } else { $null }
        iteration_plan_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_plan_path } else { $null }
        iteration_progress_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_progress_path } else { $null }
        iteration_review_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_review_path } else { $null }
        task_directory = if ($null -ne $resolvedCandidate) { $resolvedCandidate.task_directory } else { $null }
        question_directory = if ($null -ne $resolvedCandidate) { $resolvedCandidate.question_directory } else { $null }
        report_directory = if ($null -ne $resolvedCandidate) { $resolvedCandidate.report_directory } else { $null }
        iteration_knowledge_path = if ($null -ne $resolvedCandidate) { $resolvedCandidate.iteration_knowledge_path } else { $null }
        session_signal_count = $sessionCandidate.signal_count
        root_signal_count = $rootCandidate.signal_count
        session_candidate = $sessionCandidate
        root_candidate = $rootCandidate
    }
}

function New-SmokeReportMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Summary,
        [Parameter(Mandatory)][object[]]$TestCases,
        [Parameter(Mandatory)][object[]]$EvidenceArtifacts,
        [Parameter(Mandatory)][string]$ReportDirectory
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Ralph v2 CLI smoke report')
    $lines.Add('')
    $lines.Add('## Run overview')
    $lines.Add('')
    $lines.Add('| Field | Value |')
    $lines.Add('| --- | --- |')
    $lines.Add("| Status | $(ConvertTo-MarkdownCell $Summary.status) |")
    $lines.Add("| Stage | $(ConvertTo-MarkdownCell $Summary.stage) |")
    $lines.Add("| Started (UTC) | $(ConvertTo-MarkdownCell $Summary.started_at) |")
    $lines.Add("| Finished (UTC) | $(ConvertTo-MarkdownCell $Summary.finished_at) |")
    $lines.Add("| Duration (seconds) | $(ConvertTo-MarkdownCell $Summary.duration_seconds) |")
    $lines.Add("| Channel | $(ConvertTo-MarkdownCell $Summary.channel) |")
    $lines.Add("| Model | $(ConvertTo-MarkdownCell $Summary.model) |")
    $lines.Add("| Reasoning effort | $(ConvertTo-MarkdownCell $Summary.reasoning_effort) |")
    $lines.Add("| Report directory | `{0}` |" -f (ConvertTo-MarkdownCell $Summary.artifacts.report_directory))
    $lines.Add("| Checkpoints passed | $(ConvertTo-MarkdownCell $Summary.checkpoint_summary.passed) / $(ConvertTo-MarkdownCell $Summary.checkpoint_summary.total) |")
    $lines.Add("| Checkpoints skipped | $(ConvertTo-MarkdownCell $Summary.checkpoint_summary.skipped) |")
    $lines.Add("| Checkpoints failed | $(ConvertTo-MarkdownCell $Summary.checkpoint_summary.failed) |")
    $lines.Add("| Checkpoints not run | $(ConvertTo-MarkdownCell $Summary.checkpoint_summary.not_run) |")
    $lines.Add('')
    $lines.Add('## Durable review artifacts')
    $lines.Add('')
    $lines.Add('| Artifact | Path |')
    $lines.Add('| --- | --- |')
    $lines.Add("| Report markdown | [$(Split-Path -Path $Summary.artifacts.report_markdown -Leaf)]($(Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $Summary.artifacts.report_markdown)) |")
    $lines.Add("| Summary JSON | [$(Split-Path -Path $Summary.artifacts.summary_json -Leaf)]($(Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $Summary.artifacts.summary_json)) |")
    $lines.Add("| Inputs JSON | [$(Split-Path -Path $Summary.artifacts.inputs_json -Leaf)]($(Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $Summary.artifacts.inputs_json)) |")
    $lines.Add("| Test cases JSON | [$(Split-Path -Path $Summary.artifacts.test_cases_json -Leaf)]($(Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $Summary.artifacts.test_cases_json)) |")
    $lines.Add("| Evidence directory | [$(Split-Path -Path $Summary.artifacts.evidence_directory -Leaf)]($(Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $Summary.artifacts.evidence_directory)) |")
    $lines.Add('')
    $lines.Add('## Commands used')
    $lines.Add('')
    $lines.Add('```json')
    $lines.Add(($Summary.commands | ConvertTo-Json -Depth 10))
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## Execution checklist')
    $lines.Add('')
    $lines.Add('| Bucket | Status | Checkpoint | Details | Evidence |')
    $lines.Add('| --- | --- | --- | --- | --- |')

    foreach ($testCase in $TestCases) {
        $evidenceLinks = if ((Get-CollectionCount -Value $testCase.evidence) -gt 0) {
            @(
                foreach ($evidencePath in $testCase.evidence) {
                    "[{0}]({1})" -f (Split-Path -Path $evidencePath -Leaf), (Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $evidencePath)
                }
            ) -join '<br/>'
        }
        else {
            '-'
        }

        $statusText = '{0} {1}' -f (Get-TestCaseStatusIcon -Status $testCase.status), $testCase.status
        $lines.Add("| $(ConvertTo-MarkdownCell $testCase.bucket) | $statusText | $(ConvertTo-MarkdownCell $testCase.checkpoint) | $(ConvertTo-MarkdownCell $testCase.details) | $evidenceLinks |")
    }

    if ($null -ne $Summary.workflow) {
        $lines.Add('')
        $lines.Add('## Ralph workflow path')
        $lines.Add('')
        if ($null -ne $Summary.workflow.layout) {
            $lines.Add('| Field | Value |')
            $lines.Add('| --- | --- |')
            $lines.Add("| Detected layout | $(ConvertTo-MarkdownCell $Summary.workflow.layout.label) |")
            $lines.Add("| Detection notes | $(ConvertTo-MarkdownCell $Summary.workflow.layout.detection_notes) |")
            $lines.Add("| Workflow metadata | `{0}` |" -f (ConvertTo-MarkdownCell $Summary.workflow.workflow_metadata))
            $lines.Add("| Iteration directory | `{0}` |" -f (ConvertTo-MarkdownCell $Summary.workflow.iteration_directory))
            $lines.Add('')
        }
        $lines.Add('| Workflow checkpoint | Status | Evidence | Notes |')
        $lines.Add('| --- | --- | --- | --- |')

        foreach ($checkpoint in @($Summary.workflow.state_path)) {
            $checkpointEvidence = if ((Get-CollectionCount -Value $checkpoint.evidence_paths) -gt 0) {
                @(
                    foreach ($evidencePath in $checkpoint.evidence_paths) {
                        "[{0}]({1})" -f (Split-Path -Path $evidencePath -Leaf), (Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $evidencePath)
                    }
                ) -join '<br/>'
            }
            else {
                '-'
            }

            $statusLabel = switch ($checkpoint.status) {
                'observed' { '✅ observed' }
                'skipped' { '⏭️ skipped' }
                'failed' { '❌ failed' }
                default { "⏳ $($checkpoint.status)" }
            }

            $lines.Add("| $(ConvertTo-MarkdownCell $checkpoint.label) | $(ConvertTo-MarkdownCell $statusLabel) | $checkpointEvidence | $(ConvertTo-MarkdownCell $checkpoint.notes) |")
        }

        $lines.Add('')
    $lines.Add('## Ralph role coverage')
    $lines.Add('')
    $lines.Add('| Role | Expected | Result | Evidence | Notes |')
    $lines.Add('| --- | --- | --- | --- | --- |')

        foreach ($role in @($Summary.workflow.role_coverage)) {
            $roleEvidence = if ((Get-CollectionCount -Value $role.evidence_paths) -gt 0) {
                @(
                    foreach ($evidencePath in $role.evidence_paths) {
                        "[{0}]({1})" -f (Split-Path -Path $evidencePath -Leaf), (Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $evidencePath)
                    }
                ) -join '<br/>'
            }
            else {
                '-'
            }

            $roleResult = switch ($role.status) {
                'observed' { '✅ observed' }
                'not_expected' { '⏭️ not expected' }
                'failed' { '❌ failed' }
                default { "⏳ $($role.status)" }
            }

            $lines.Add("| $(ConvertTo-MarkdownCell $role.label) | $(ConvertTo-MarkdownCell $(if ($role.expected) { 'yes' } else { 'no' })) | $(ConvertTo-MarkdownCell $roleResult) | $roleEvidence | $(ConvertTo-MarkdownCell $role.notes) |")
        }

        if ((Get-CollectionCount -Value $Summary.workflow.subagent_provenance) -gt 0) {
            $lines.Add('')
            $lines.Add('## Custom subagent provenance')
            $lines.Add('')
            $lines.Add('| Role | Expected custom agent | Result | Log evidence | Notes |')
            $lines.Add('| --- | --- | --- | --- | --- |')

            foreach ($provenance in @($Summary.workflow.subagent_provenance)) {
                $provenanceEvidence = if ((Get-CollectionCount -Value $provenance.evidence_paths) -gt 0) {
                    @(
                        foreach ($evidencePath in $provenance.evidence_paths) {
                            "[{0}]({1})" -f (Split-Path -Path $evidencePath -Leaf), (Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $evidencePath)
                        }
                    ) -join '<br/>'
                }
                else {
                    '-'
                }

                $provenanceResult = if ($provenance.observed) { '✅ observed' } else { '❌ missing' }
                $lines.Add("| $(ConvertTo-MarkdownCell $provenance.label) | $(ConvertTo-MarkdownCell $provenance.agent_name) | $(ConvertTo-MarkdownCell $provenanceResult) | $provenanceEvidence | $(ConvertTo-MarkdownCell $provenance.notes) |")
            }
        }
    }

    $lines.Add('')
    $lines.Add('## Test inputs and effective configuration')
    $lines.Add('')
    $lines.Add('```json')
    $lines.Add(($Summary.inputs | ConvertTo-Json -Depth 10))
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## Concrete evidence captured during this execution')
    $lines.Add('')
    $lines.Add('| Category | Evidence | Path | Notes |')
    $lines.Add('| --- | --- | --- | --- |')
    foreach ($artifact in $EvidenceArtifacts) {
        $relativePath = Get-MarkdownRelativePath -BasePath $ReportDirectory -TargetPath $artifact.path
        $lines.Add("| $(ConvertTo-MarkdownCell $artifact.category) | $(ConvertTo-MarkdownCell $artifact.description) | [$([System.IO.Path]::GetFileName($artifact.path))]($relativePath) | $(ConvertTo-MarkdownCell (Get-EvidenceArtifactNoteText -Artifact $artifact)) |")
    }

    if ($null -ne $Summary.error) {
        $lines.Add('')
        $lines.Add('## Failure summary')
        $lines.Add('')
        $lines.Add('| Field | Value |')
        $lines.Add('| --- | --- |')
        $lines.Add("| Error stage | $(ConvertTo-MarkdownCell $Summary.error.stage) |")
        $lines.Add("| Error message | $(ConvertTo-MarkdownCell $Summary.error.message) |")
    }

    return ($lines -join [Environment]::NewLine)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportTimestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$defaultReportDirectory = Join-Path $repoRoot ("scripts\test\.artifacts\ralph-v2-cli-smoke\run-{0}-{1}" -f $reportTimestamp, $PID)
$resolvedReportPath = if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    Join-Path $defaultReportDirectory 'report.md'
}
else {
    [System.IO.Path]::GetFullPath($ReportPath)
}
$reportDirectory = Split-Path -Path $resolvedReportPath -Parent
$reportEvidenceDirectory = Join-Path $reportDirectory 'evidence'
$summaryJsonPath = Join-Path $reportDirectory 'summary.json'
$inputsJsonPath = Join-Path $reportDirectory 'inputs.json'
$testCasesJsonPath = Join-Path $reportDirectory 'test-cases.json'
$promptTimeoutGraceSeconds = [Math]::Min([Math]::Max([int][Math]::Ceiling($PromptTimeoutSeconds * 0.1), 15), 120)
$effectivePromptTimeoutSeconds = $PromptTimeoutSeconds + $promptTimeoutGraceSeconds
$scriptStartTime = (Get-Date).ToUniversalTime()
$script:testCases = New-SmokeTestCases
$script:currentCheckpointId = $null
$script:summary = [ordered]@{
    status = 'failed'
    stage = 'initializing'
    started_at = $scriptStartTime.ToString('o')
    finished_at = $null
    duration_seconds = $null
    channel = $Channel
    model = $Model
    reasoning_effort = $ReasoningEffort
    repo_root = $repoRoot
    inputs = [ordered]@{
        channel = $Channel
        model = $Model
        reasoning_effort = $ReasoningEffort
        prompt_timeout_seconds = $PromptTimeoutSeconds
        prompt_timeout_grace_seconds = $promptTimeoutGraceSeconds
        effective_prompt_timeout_seconds = $effectivePromptTimeoutSeconds
        prompt_text = $null
        skip_agent_invocation = [bool]$SkipAgentInvocation
        session_id = $null
        smoke_output_relative_path = $SmokeOutputRelativePath
        keep_config_dir = [bool]$KeepConfigDir
        keep_log_dir = [bool]$KeepLogDir
        keep_working_directory = [bool]$KeepWorkingDirectory
        requested_paths = [ordered]@{
            config_dir = $ConfigDir
            log_dir = $LogDir
            working_directory = $WorkingDirectory
            report_path = $ReportPath
        }
        effective_paths = $null
    }
    artifacts = [ordered]@{
        report_directory = $reportDirectory
        report_markdown = $resolvedReportPath
        summary_json = $summaryJsonPath
        inputs_json = $inputsJsonPath
        test_cases_json = $testCasesJsonPath
        evidence_directory = $reportEvidenceDirectory
        evidence_files = @()
    }
    commands = [ordered]@{}
    build = $null
    install = $null
    agent_invocation = $null
    workflow = $null
    checkpoint_summary = $null
    test_cases = @()
    error = $null
}

$createdConfigDir = $false
$createdLogDir = $false
$createdWorkingDirectory = $false
$exitCode = 0
$resolvedConfigDir = $null
$resolvedLogDir = $null
$resolvedWorkingDirectory = $null
$pluginPreviouslyInstalled = $false
$pluginInstalledByHarness = $false
$copilotConfigRoots = @()
$copilotCommand = $null
$buildManifest = $null
$versionResult = $null
$sourceManifest = $null
$buildManifestPath = $null
$installResult = $null
$listResult = $null
$promptResult = $null
$preferredInstalledManifest = $null
$orchestratorAgentName = $null
$resolvedSessionId = $null
$effectivePromptText = $null
$sessionPath = $null
$smokeOutputPath = $null
$gitCommand = $null
$logDirectorySnapshotPath = $null
$sessionSnapshotRoot = $null

try {
    $script:summary.stage = 'preflight'

    $copilotCommand = Resolve-CommandExecution -CommandName 'copilot'
    $gitCommand = Resolve-CommandExecution -CommandName 'git'
    Import-BuildPluginFunctions -ScriptPath (Join-Path $repoRoot 'scripts\publish\build-plugins.ps1')

    $resolvedConfigDir = if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
        $createdConfigDir = $true
        New-TemporaryDirectory -Prefix 'ralph-cli-smoke-config'
    }
    else {
        [System.IO.Path]::GetFullPath($ConfigDir)
    }

    $resolvedLogDir = if ([string]::IsNullOrWhiteSpace($LogDir)) {
        $createdLogDir = $true
        New-TemporaryDirectory -Prefix 'ralph-cli-smoke-logs'
    }
    else {
        [System.IO.Path]::GetFullPath($LogDir)
    }

    $resolvedWorkingDirectory = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $createdWorkingDirectory = $true
        New-TemporaryDirectory -Prefix 'ralph-cli-smoke-workdir'
    }
    else {
        [System.IO.Path]::GetFullPath($WorkingDirectory)
    }

    New-Item -Path $resolvedConfigDir -ItemType Directory -Force | Out-Null
    New-Item -Path $resolvedLogDir -ItemType Directory -Force | Out-Null
    New-Item -Path $resolvedWorkingDirectory -ItemType Directory -Force | Out-Null
    $resolvedSessionId = if ([string]::IsNullOrWhiteSpace($SessionId)) { New-SmokeSessionId } else { $SessionId.Trim() }
    Initialize-SmokeWorkspaceFixture -WorkingDirectory $resolvedWorkingDirectory -SessionId $resolvedSessionId
    $copilotConfigRoots = @(Get-CopilotConfigRoots -ConfigRoot $resolvedConfigDir)
    $effectivePromptText = if ([string]::IsNullOrWhiteSpace($PromptText)) {
        Get-DefaultSmokePromptText -SessionId $resolvedSessionId -SmokeOutputRelativePath $SmokeOutputRelativePath
    }
    else {
        $PromptText
    }
    $sessionPath = Join-Path $resolvedWorkingDirectory ".ralph-sessions\$resolvedSessionId"
    $smokeOutputPath = Join-Path $resolvedWorkingDirectory $SmokeOutputRelativePath

    $script:summary.inputs.session_id = $resolvedSessionId
    $script:summary.inputs.prompt_text = $effectivePromptText
    $script:summary.inputs.effective_paths = [ordered]@{
        config_dir = $resolvedConfigDir
        log_dir = $resolvedLogDir
        working_directory = $resolvedWorkingDirectory
        session_path = $sessionPath
        smoke_output_path = $smokeOutputPath
        report_directory = $reportDirectory
        report_markdown = $resolvedReportPath
    }

    $script:currentCheckpointId = 'copilot-version'
    $versionResult = Invoke-ExternalCommand -FilePath $copilotCommand.FilePath -Arguments ($copilotCommand.PrefixArguments + @('--version')) -WorkingDirectory $repoRoot -TimeoutSeconds 30
    Assert-True -Condition ($versionResult.ExitCode -eq 0) -Message "copilot --version failed. STDERR: $($versionResult.StdErr)"
    $script:summary.commands.copilot_version = [ordered]@{
        command = $versionResult.CommandLine
        exit_code = $versionResult.ExitCode
    }
    Set-TestCaseStatus -Id 'copilot-version' -Status 'passed' -Details ("Resolved '{0}' and captured Copilot CLI version output: {1}" -f $copilotCommand.FilePath, $versionResult.StdOut)

    $script:summary.stage = 'building'
    $script:currentCheckpointId = 'build-cli-bundle'

    $sourcePluginDir = Join-Path $repoRoot 'plugins\cli\ralph-v2'
    $sourcePluginDirItem = Get-Item -Path $sourcePluginDir -ErrorAction Stop
    $sourceManifest = Get-JsonFileContent -Path (Join-Path $sourcePluginDir 'plugin.json')
    $versionContract = Get-RalphWorkflowVersionContract -PluginDir $sourcePluginDir -Manifest $sourceManifest
    Assert-True -Condition ($null -ne $versionContract) -Message 'Failed to resolve the Ralph workflow version contract.'

    Initialize-PluginBundleOutput -SelectedPluginDirs @($sourcePluginDirItem) -AllPluginDirs @($sourcePluginDirItem) -Channel $Channel
    $buildDir = Build-PluginBundle -PluginDir $sourcePluginDir -Channel $Channel
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($buildDir)) -Message 'Ralph plugin bundle build failed.'

    $bundleLayout = Get-PluginBundleLayout -PluginDir $sourcePluginDir -Channel $Channel
    $buildManifestPath = Join-Path $buildDir 'plugin.json'
    $expectedPluginName = Get-BundledPluginName -PluginName 'ralph-v2' -Channel $Channel
    $buildManifest = Get-JsonFileContent -Path $buildManifestPath
    Assert-True -Condition ($buildManifest.name -eq $expectedPluginName) -Message "Built plugin name mismatch. Expected '$expectedPluginName' but found '$($buildManifest.name)'."
    $bundledAgentNames = Get-BundledAgentNameMap -BuildDir $buildDir -PluginName $buildManifest.name
    $orchestratorAgentName = $bundledAgentNames.orchestrator
    Assert-True -Condition ($buildManifest.version -eq $versionContract.BundleVersion) -Message "Built plugin version mismatch. Expected '$($versionContract.BundleVersion)' but found '$($buildManifest.version)'."
    Assert-True -Condition ($buildManifest.runtime -eq 'github-copilot-cli') -Message "Built plugin runtime mismatch. Expected 'github-copilot-cli' but found '$($buildManifest.runtime)'."
    Assert-True -Condition (Test-Path (Join-Path $buildDir 'README.md') -PathType Leaf) -Message "Built Ralph bundle is missing README.md: $buildDir"

    $script:summary.build = [ordered]@{
        source_manifest = [ordered]@{
            name = $sourceManifest.name
            version = $sourceManifest.version
            bundle_version_override = if ($versionContract.UsesBundleVersionOverride) { $versionContract.BundleVersionOverride } else { $null }
            workflow_version = $versionContract.WorkflowVersion
        }
        bundle = [ordered]@{
            path = $buildDir
            name = $buildManifest.name
            version = $buildManifest.version
            runtime = $buildManifest.runtime
            orchestrator_agent = $orchestratorAgentName
            role_agents = [ordered]@{
                orchestrator = $bundledAgentNames.orchestrator
                planner = $bundledAgentNames.planner
                questioner = $bundledAgentNames.questioner
                executor = $bundledAgentNames.executor
                reviewer = $bundledAgentNames.reviewer
                librarian = $bundledAgentNames.librarian
            }
        }
        copilot_version = $versionResult.StdOut
    }
    Set-TestCaseStatus -Id 'build-cli-bundle' -Status 'passed' -Details ("Built bundle '{0}' version '{1}' at {2} and resolved orchestrator agent '{3}'." -f $buildManifest.name, $buildManifest.version, $buildDir, $orchestratorAgentName)

    $script:summary.stage = 'installing'

    $preInstallCandidates = @(Get-InstalledPluginManifestCandidates -ConfigRoots $copilotConfigRoots -ExpectedPluginName $buildManifest.name)
    $pluginPreviouslyInstalled = @($preInstallCandidates).Count -gt 0

    $script:currentCheckpointId = 'install-cli-plugin'
    $installResult = Invoke-ExternalCommand -FilePath $copilotCommand.FilePath -Arguments ($copilotCommand.PrefixArguments + @('plugin', 'install', '--config-dir', $resolvedConfigDir, $buildDir)) -WorkingDirectory $repoRoot -TimeoutSeconds 120
    Assert-True -Condition ($installResult.ExitCode -eq 0) -Message "copilot plugin install failed. STDOUT: $($installResult.StdOut)`nSTDERR: $($installResult.StdErr)"
    $pluginInstalledByHarness = $true
    $script:summary.commands.plugin_install = [ordered]@{
        command = $installResult.CommandLine
        exit_code = $installResult.ExitCode
    }
    Set-TestCaseStatus -Id 'install-cli-plugin' -Status 'passed' -Details ("Installed '{0}' into config root {1}. Preexisting install detected: {2}." -f $buildManifest.name, $resolvedConfigDir, $pluginPreviouslyInstalled)

    $script:currentCheckpointId = 'verify-plugin-discovery'
    $listResult = Invoke-ExternalCommand -FilePath $copilotCommand.FilePath -Arguments ($copilotCommand.PrefixArguments + @('plugin', 'list', '--config-dir', $resolvedConfigDir)) -WorkingDirectory $repoRoot -TimeoutSeconds 60
    Assert-True -Condition ($listResult.ExitCode -eq 0) -Message "copilot plugin list failed. STDOUT: $($listResult.StdOut)`nSTDERR: $($listResult.StdErr)"
    $script:summary.commands.plugin_list = [ordered]@{
        command = $listResult.CommandLine
        exit_code = $listResult.ExitCode
    }

    $pluginListText = @($listResult.StdOut, $listResult.StdErr) -join [Environment]::NewLine
    $pluginNamePattern = [regex]::Escape($buildManifest.name)
    Assert-True -Condition ($pluginListText -match $pluginNamePattern) -Message "Installed plugin '$($buildManifest.name)' was not detected in 'copilot plugin list'. Output: $pluginListText"

    $installedCandidates = @(Get-InstalledPluginManifestCandidates -ConfigRoots $copilotConfigRoots -ExpectedPluginName $buildManifest.name)
    $searchedRoots = ($copilotConfigRoots -join ', ')
    Assert-True -Condition (@($installedCandidates).Count -ge 1) -Message "No installed plugin manifest for '$($buildManifest.name)' was found under the searched Copilot roots after installation: $searchedRoots"

    $preferredInstalledManifest = Get-PreferredInstalledPluginManifest -Candidates $installedCandidates -ExpectedVersion $buildManifest.version
    Assert-True -Condition ($null -ne $preferredInstalledManifest) -Message "Installed plugin manifests were found, but none matched the expected version '$($buildManifest.version)'."

    $script:summary.install = [ordered]@{
        config_dir = $resolvedConfigDir
        log_dir = $resolvedLogDir
        searched_config_roots = $copilotConfigRoots
        preexisting_install_detected = $pluginPreviouslyInstalled
        install_command = $installResult.CommandLine
        plugin_list_command = $listResult.CommandLine
        plugin_list_output = $listResult.StdOut
        installed_manifest = [ordered]@{
            config_root = $preferredInstalledManifest.ConfigRoot
            path = $preferredInstalledManifest.Path
            relative_path = $preferredInstalledManifest.RelativePath
            cache_kind = $preferredInstalledManifest.CacheKind
            name = $preferredInstalledManifest.Manifest.name
            version = $preferredInstalledManifest.Manifest.version
            runtime = $preferredInstalledManifest.Manifest.runtime
        }
    }
    Set-TestCaseStatus -Id 'verify-plugin-discovery' -Status 'passed' -Details ("Plugin list contained '{0}' and the installed manifest was verified at {1}." -f $buildManifest.name, $preferredInstalledManifest.Path)

    $script:summary.stage = 'agent_invocation'
    $script:currentCheckpointId = 'orchestrator-invocation'

    if ($SkipAgentInvocation) {
        $script:summary.agent_invocation = [ordered]@{
            skipped = $true
            working_directory = $resolvedWorkingDirectory
            session_id = $resolvedSessionId
            session_path = $sessionPath
            requested_timeout_seconds = $PromptTimeoutSeconds
            timeout_grace_seconds = $promptTimeoutGraceSeconds
            effective_timeout_seconds = $effectivePromptTimeoutSeconds
        }
        $script:summary.commands.agent_invocation = [ordered]@{
            command = $null
            exit_code = $null
            skipped = $true
        }
        Set-TestCaseStatus -Id 'orchestrator-invocation' -Status 'skipped' -Details 'Agent invocation was intentionally skipped via -SkipAgentInvocation.'
        foreach ($skippedCaseId in @('orchestrator-session-state', 'planner-artifacts', 'questioner-artifacts', 'executor-artifacts', 'reviewer-artifacts', 'librarian-artifacts')) {
            Set-TestCaseStatus -Id $skippedCaseId -Status 'skipped' -Details 'Skipped because the live Ralph workflow invocation was disabled.'
        }
    }
    else {
        $promptArguments = @(
            '--config-dir', $resolvedConfigDir,
            '--log-dir', $resolvedLogDir,
            '--plugin-dir', $buildDir,
            '--model', $Model,
            '--reasoning-effort', $ReasoningEffort,
            '--agent', $orchestratorAgentName,
            '--allow-all',
            '--no-ask-user',
            '--no-auto-update',
            '--no-custom-instructions',
            '--disable-builtin-mcps',
            '--stream', 'off',
            '--silent',
            '--output-format', 'text',
            '--prompt', $effectivePromptText
        )

        $promptResult = Invoke-ExternalCommand -FilePath $copilotCommand.FilePath -Arguments ($copilotCommand.PrefixArguments + $promptArguments) -WorkingDirectory $resolvedWorkingDirectory -TimeoutSeconds $PromptTimeoutSeconds -TimeoutGraceSeconds $promptTimeoutGraceSeconds
        $promptFinalResponse = Get-RalphFinalResponseFields -Output $promptResult.StdOut
        $script:summary.agent_invocation = [ordered]@{
            skipped = $false
            working_directory = $resolvedWorkingDirectory
            plugin_dir = $buildDir
            session_id = $resolvedSessionId
            session_path = $sessionPath
            prompt_text = $effectivePromptText
            requested_timeout_seconds = $PromptTimeoutSeconds
            timeout_grace_seconds = $promptTimeoutGraceSeconds
            effective_timeout_seconds = $effectivePromptTimeoutSeconds
            grace_period_used = [bool]$promptResult.GracePeriodUsed
            reported_session_path = $promptFinalResponse.session_path
            reported_final_state = $promptFinalResponse.final_state
            command = $promptResult.CommandLine
            exit_code = $promptResult.ExitCode
            stdout = $promptResult.StdOut
            stderr = $promptResult.StdErr
        }
        $script:summary.commands.agent_invocation = [ordered]@{
            command = $promptResult.CommandLine
            exit_code = $promptResult.ExitCode
            requested_timeout_seconds = $PromptTimeoutSeconds
            timeout_grace_seconds = $promptTimeoutGraceSeconds
            effective_timeout_seconds = $effectivePromptTimeoutSeconds
            grace_period_used = [bool]$promptResult.GracePeriodUsed
            reported_session_path = $promptFinalResponse.session_path
            reported_final_state = $promptFinalResponse.final_state
            skipped = $false
        }

        $promptCombinedOutput = @($promptResult.StdOut, $promptResult.StdErr) -join [Environment]::NewLine
        Assert-True -Condition ($promptResult.ExitCode -eq 0) -Message ("Ralph agent invocation failed. " +
            "If this environment is not already authenticated, provide COPILOT_GITHUB_TOKEN/GH_TOKEN/GITHUB_TOKEN " +
            "or run 'copilot login' first. STDOUT: $($promptResult.StdOut)`nSTDERR: $($promptResult.StdErr)")
        Assert-True -Condition ($promptCombinedOutput -notmatch '(?i)No such agent:') -Message "Installed Ralph plugin did not expose agent '$orchestratorAgentName'. Output: $promptCombinedOutput"
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($promptResult.StdOut)) -Message 'Ralph agent invocation completed with exit code 0 but returned no output.'
        Assert-True -Condition $promptFinalResponse.has_final_state -Message "Ralph agent invocation did not return a FINAL_STATE line in stdout. STDOUT: $($promptResult.StdOut)"
        Assert-True -Condition ($promptFinalResponse.final_state -eq 'COMPLETE') -Message ("Ralph agent invocation finished without reaching COMPLETE. " +
            "Reported FINAL_STATE='$($promptFinalResponse.final_state)'. STDOUT: $($promptResult.StdOut)")

        $workspaceMetadataPath = Join-Path $resolvedWorkingDirectory 'metadata.yaml'
        $activeSessionPointerPath = Join-Path $resolvedWorkingDirectory '.ralph-sessions\.active-session'
        $sessionInstructionPath = Join-Path $resolvedWorkingDirectory ".ralph-sessions\$resolvedSessionId.instructions.md"
        $sessionMetadataPath = Join-Path $sessionPath 'metadata.yaml'
        $workflowArtifactLayout = Resolve-RalphWorkflowArtifactLayout -WorkspaceRoot $resolvedWorkingDirectory -SessionPath $sessionPath
        $workflowMetadataPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.metadata_path)) { $workflowArtifactLayout.metadata_path } else { $sessionMetadataPath }
        $iterationDirectory = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_directory)) { $workflowArtifactLayout.iteration_directory } else { $workflowArtifactLayout.session_candidate.iteration_directory }
        $iterationMetadataPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_metadata_path)) { $workflowArtifactLayout.iteration_metadata_path } else { Join-Path $iterationDirectory 'metadata.yaml' }
        $iterationPlanPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_plan_path)) { $workflowArtifactLayout.iteration_plan_path } else { Join-Path $iterationDirectory 'plan.md' }
        $iterationProgressPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_progress_path)) { $workflowArtifactLayout.iteration_progress_path } else { Join-Path $iterationDirectory 'progress.md' }
        $iterationReviewPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_review_path)) { $workflowArtifactLayout.iteration_review_path } else { Join-Path $iterationDirectory 'review.md' }
        $taskDirectory = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.task_directory)) { $workflowArtifactLayout.task_directory } else { Join-Path $iterationDirectory 'tasks' }
        $questionDirectory = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.question_directory)) { $workflowArtifactLayout.question_directory } else { Join-Path $iterationDirectory 'questions' }
        $reportDirectoryPath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.report_directory)) { $workflowArtifactLayout.report_directory } else { Join-Path $iterationDirectory 'reports' }
        $iterationKnowledgePath = if (-not [string]::IsNullOrWhiteSpace($workflowArtifactLayout.iteration_knowledge_path)) { $workflowArtifactLayout.iteration_knowledge_path } else { Join-Path $iterationDirectory 'knowledge' }
        $sessionKnowledgePath = Join-Path $resolvedWorkingDirectory 'knowledge'
        $workflowLayoutDetail = if ($workflowArtifactLayout.detected_layout -eq 'undetected') {
            $workflowArtifactLayout.detection_notes
        }
        else {
            Join-DetailSentences -Parts @(
                $workflowArtifactLayout.detection_notes,
                "Resolved metadata path: '$workflowMetadataPath'.",
                "Resolved iteration directory: '$iterationDirectory'."
            )
        }
        $progressContent = Get-FileTextIfExists -Path $iterationProgressPath
        $workflowMetadataContent = Get-FileTextIfExists -Path $workflowMetadataPath
        $workspaceMetadataContent = Get-FileTextIfExists -Path $workspaceMetadataPath
        $iterationMetadataContent = Get-FileTextIfExists -Path $iterationMetadataPath
        $sessionMetadataContent = Get-FileTextIfExists -Path $sessionMetadataPath
        $iterationReviewContent = Get-FileTextIfExists -Path $iterationReviewPath
        $taskFiles = if (Test-Path $taskDirectory -PathType Container) { @(Get-ChildItem -Path $taskDirectory -Filter '*.md' -File -ErrorAction SilentlyContinue) } else { @() }
        $questionFiles = if (Test-Path $questionDirectory -PathType Container) { @(Get-ChildItem -Path $questionDirectory -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue) } else { @() }
        $reportFiles = @(
            if (Test-Path $reportDirectoryPath -PathType Container) {
                Get-ChildItem -Path $reportDirectoryPath -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue
            }
            Get-ChildItem -Path $iterationDirectory -Filter '*report*.md' -File -ErrorAction SilentlyContinue
        ) | Sort-Object FullName -Unique
        $iterationKnowledgeItems = if (Test-Path $iterationKnowledgePath -PathType Container) { @(Get-ChildItem -Path $iterationKnowledgePath -Recurse -File -ErrorAction SilentlyContinue) } else { @() }
        $sessionKnowledgeItems = if (Test-Path $sessionKnowledgePath -PathType Container) { @(Get-ChildItem -Path $sessionKnowledgePath -Recurse -File -ErrorAction SilentlyContinue) } else { @() }
        $reportFileDetails = @(
            foreach ($reportFile in $reportFiles) {
                $reportContent = Get-FileTextIfExists -Path $reportFile.FullName
                [PSCustomObject]@{
                    Path = $reportFile.FullName
                    Content = $reportContent
                    HasPart1 = -not [string]::IsNullOrWhiteSpace($reportContent) -and ($reportContent -match 'PART 1:\s*IMPLEMENTATION REPORT')
                    HasPart2 = -not [string]::IsNullOrWhiteSpace($reportContent) -and ($reportContent -match 'PART 2:\s*REVIEW REPORT')
                }
            }
        )
        $questionFileDetails = @(
            foreach ($questionFile in $questionFiles) {
                $questionContent = Get-FileTextIfExists -Path $questionFile.FullName
                [PSCustomObject]@{
                    Path = $questionFile.FullName
                    Content = $questionContent
                    HasAnswers = -not [string]::IsNullOrWhiteSpace($questionContent) -and ($questionContent -match '##\s+Answers')
                }
            }
        )
        $subagentProvenance = @(Get-RalphSubagentProvenance -LogRoot $resolvedLogDir -SessionId $resolvedSessionId -BundledAgentNames $bundledAgentNames)
        $unexpectedBuiltinTaskMatches = @(
            @(Get-LogEvidenceMatches -LogRoot $resolvedLogDir -Pattern 'Task tool invoked with agent_type:\s*task(?:\s|,|$)') +
            @(Get-LogEvidenceMatches -LogRoot $resolvedLogDir -Pattern 'Custom agent "task"')
        )
        $unexpectedBuiltinDelegationObserved = (Get-CollectionCount -Value $unexpectedBuiltinTaskMatches) -gt 0
        $unexpectedBuiltinDelegationDetail = if ($unexpectedBuiltinDelegationObserved) {
            @(
                foreach ($match in @($unexpectedBuiltinTaskMatches | Select-Object -First 6)) {
                    "{0}:{1} {2}" -f $match.path, $match.line_number, $match.text
                }
            ) -join ' | '
        }
        else {
            'No built-in Copilot task-agent delegation was observed in the isolated workflow logs.'
        }
        $subagentProvenanceById = @{}
        foreach ($provenanceRecord in $subagentProvenance) {
            $subagentProvenanceById[$provenanceRecord.id] = $provenanceRecord
        }
        $orchestratorStateMatch = [regex]::Match(($workflowMetadataContent ?? ''), '(?ims)^\s*orchestrator\s*:\s*(?:\r?\n)+\s*state\s*:\s*"?([^"\r\n]+)"?\s*$')
        $topLevelStatusMatch = [regex]::Match(($workflowMetadataContent ?? ''), '(?im)^\s*status\s*:\s*"?([^"\r\n]+)"?\s*$')
        $legacyStateMatch = [regex]::Match(($workflowMetadataContent ?? ''), '(?im)^\s*state\s*:\s*"?([^"\r\n]+)"?\s*$')
        $finalState = if ($orchestratorStateMatch.Success) {
            $orchestratorStateMatch.Groups[1].Value.Trim()
        }
        elseif ($topLevelStatusMatch.Success) {
            $topLevelStatusMatch.Groups[1].Value.Trim()
        }
        elseif ($legacyStateMatch.Success) {
            $legacyStateMatch.Groups[1].Value.Trim()
        }
        else {
            $null
        }
        $normalizedFinalState = if ([string]::IsNullOrWhiteSpace($finalState)) { $null } else { $finalState.Trim().ToUpperInvariant() }
        $iterationPlanningComplete = ($iterationMetadataContent ?? '') -match '(?im)^\s*planning_complete\s*:\s*"?true"?\s*$'
        $legacyPlanningMarkersComplete = (Test-ProgressFileContainsPattern -ProgressContent $progressContent -Pattern '(?im)^\s*-\s*\[x\]\s+plan-init') -and
            (Test-ProgressFileContainsPattern -ProgressContent $progressContent -Pattern '(?im)^\s*-\s*\[x\]\s+plan-breakdown') -and
            (
                (Test-ProgressFileContainsPattern -ProgressContent $progressContent -Pattern '(?im)^\s*-\s*\[x\]\s+plan-brainstorm') -or
                (Test-ProgressFileContainsPattern -ProgressContent $progressContent -Pattern '(?im)^\s*-\s*\[x\]\s+plan-knowledge')
            )
        $planningMarkersComplete = $iterationPlanningComplete -or $legacyPlanningMarkersComplete
        $taskQualified = Test-ProgressFileContainsPattern -ProgressContent $progressContent -Pattern '(?im)^\s*-\s*\[x\]\s+task-'
        $knowledgeMarkerMatches = [regex]::Matches(($progressContent ?? ''), '(?im)^\s*-\s*\[(?<status>[xFC ])\]\s*plan-knowledge-(?<stage>[a-z-]+)')
        $knowledgeStatuses = @(
            foreach ($match in $knowledgeMarkerMatches) {
                [PSCustomObject]@{
                    stage = $match.Groups['stage'].Value
                    status = $match.Groups['status'].Value
                }
            }
        )
        $knowledgeSectionStatus = if (($progressContent ?? '') -match '(?ims)^\s*##\s*Knowledge\b.*?^\s*-\s*Status\s*:\s*(?<knowledgeStatus>[A-Za-z-]+)') {
            $Matches['knowledgeStatus'].ToLowerInvariant()
        }
        else {
            $null
        }
        $iterationKnowledgeCount = Get-CollectionCount -Value $iterationKnowledgeItems
        $sessionKnowledgeCount = Get-CollectionCount -Value $sessionKnowledgeItems
        $knowledgeArtifactCount = $iterationKnowledgeCount + $sessionKnowledgeCount
        $knowledgeCompletedCount = Get-CollectionCount -Value @($knowledgeStatuses | Where-Object { $_.status -eq 'x' })
        $knowledgeNonCancelledCount = Get-CollectionCount -Value @($knowledgeStatuses | Where-Object { $_.status -ne 'C' })
        $knowledgeStatusCount = Get-CollectionCount -Value $knowledgeStatuses
        $knowledgeSectionObserved = $knowledgeSectionStatus -in @('completed', 'complete', 'done')
        $knowledgeSectionSkipped = $knowledgeSectionStatus -in @('skipped', 'skip', 'cancelled', 'canceled')
        $taskFileCount = Get-CollectionCount -Value $taskFiles
        $questionFileCount = Get-CollectionCount -Value $questionFiles
        $answeredQuestionCount = Get-CollectionCount -Value @($questionFileDetails | Where-Object { $_.HasAnswers })
        $executorReportCount = Get-CollectionCount -Value @($reportFileDetails | Where-Object { $_.HasPart1 })
        $reviewerReportCount = Get-CollectionCount -Value @($reportFileDetails | Where-Object { $_.HasPart2 })

        $knowledgeObserved = ($knowledgeArtifactCount -ge 1) -or ($knowledgeCompletedCount -ge 1) -or $knowledgeSectionObserved
        $knowledgeExplicitlySkipped = (($knowledgeStatusCount -ge 1) -and ($knowledgeNonCancelledCount -eq 0)) -or $knowledgeSectionSkipped
        $plannerArtifactsPass = (Test-Path $iterationPlanPath -PathType Leaf) -and (Test-Path $iterationProgressPath -PathType Leaf) -and (Test-Path $iterationMetadataPath -PathType Leaf) -and ($taskFileCount -ge 1) -and $planningMarkersComplete
        $questionerArtifactsPass = $answeredQuestionCount -ge 1
        $executorArtifactsPass = ($executorReportCount -ge 1) -and $taskQualified
        $reviewerArtifactsPass = (Test-Path $iterationReviewPath -PathType Leaf) -and ($reviewerReportCount -ge 1) -and $taskQualified
        $orchestratorPass = (Test-Path $workflowMetadataPath -PathType Leaf) -and ($normalizedFinalState -in @('COMPLETE', 'COMPLETED')) -and (-not $unexpectedBuiltinDelegationObserved)
        $plannerPass = $plannerArtifactsPass -and $subagentProvenanceById['planner-artifacts'].observed
        $questionerPass = $questionerArtifactsPass -and $subagentProvenanceById['questioner-artifacts'].observed
        $executorPass = $executorArtifactsPass -and $subagentProvenanceById['executor-artifacts'].observed
        $reviewerPass = $reviewerArtifactsPass -and $subagentProvenanceById['reviewer-artifacts'].observed
        $librarianPass = ($knowledgeObserved -or $knowledgeExplicitlySkipped) -and $subagentProvenanceById['librarian-artifacts'].observed
        $workflowStatePath = @(
            [ordered]@{
                id = 'planning'
                label = 'INITIALIZING -> PLANNING'
                status = $(if ($plannerPass -and $questionerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($plannerPass -and $questionerPass) { 'Planner and Questioner artifacts plus Copilot log provenance show the planning checklist completed through Ralph custom-subagent delegation.' } else { 'Planning artifacts were incomplete or lacked Copilot log proof of Ralph custom-subagent delegation.' }),
                    $workflowLayoutDetail
                )
                source_paths = @($workflowMetadataPath, $iterationMetadataPath, $iterationPlanPath, $iterationProgressPath) + @($questionFiles | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'execution'
                label = 'BATCHING -> EXECUTING_BATCH -> REVIEWING_BATCH'
                status = $(if ($executorPass -and $reviewerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($executorPass -and $reviewerPass) { 'Task materialization, implementation report, reviewer verdict, and Copilot log proof of Ralph executor/reviewer delegation were all recorded.' } else { 'Execution or review artifacts were incomplete, or the Copilot logs did not prove Ralph executor/reviewer delegation.' }),
                    $workflowLayoutDetail
                )
                source_paths = @($iterationProgressPath, $smokeOutputPath) + @($taskFiles | ForEach-Object { $_.FullName }) + @($reportFiles | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'knowledge'
                label = 'KNOWLEDGE_EXTRACTION'
                status = $(if ($librarianPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($knowledgeObserved) { "Knowledge artifacts were produced or promoted ($knowledgeArtifactCount file(s)) and Copilot logs proved the Ralph librarian custom agent ran." } elseif ($knowledgeExplicitlySkipped) { 'The Ralph librarian custom agent ran and the workflow explicitly recorded the knowledge pipeline as skipped/cancelled for this smoke scenario.' } else { 'No durable librarian evidence or Copilot log proof of Ralph librarian delegation were found.' }),
                    $workflowLayoutDetail
                )
                source_paths = @($iterationProgressPath, $iterationReviewPath) + @($iterationKnowledgeItems | ForEach-Object { $_.FullName }) + @($sessionKnowledgeItems | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'complete'
                label = 'ITERATION_REVIEW -> COMPLETE'
                status = $(if ($orchestratorPass -and $reviewerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($orchestratorPass -and $reviewerPass) { "Workflow metadata reached COMPLETE and iteration review.md exists for session '$resolvedSessionId'." } else { 'The smoke workflow did not leave durable COMPLETE-state evidence.' }),
                    $unexpectedBuiltinDelegationDetail,
                    $workflowLayoutDetail
                )
                source_paths = @($workflowMetadataPath, $iterationReviewPath, $iterationProgressPath)
                evidence_paths = @()
            }
        )
        $roleCoverage = @(
            [ordered]@{
                id = 'orchestrator-session-state'
                label = 'Orchestrator'
                expected = $true
                status = $(if ($orchestratorPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($orchestratorPass) { "Workflow metadata '$workflowMetadataPath' recorded final state '$finalState' for session '$resolvedSessionId'." } else { "Workflow metadata '$workflowMetadataPath' did not show the Ralph orchestrator reaching COMPLETE." }),
                    $unexpectedBuiltinDelegationDetail,
                    $workflowLayoutDetail
                )
                source_paths = @($workflowMetadataPath, $activeSessionPointerPath, $sessionInstructionPath, $iterationReviewPath, $iterationProgressPath)
                evidence_paths = @()
            }
            [ordered]@{
                id = 'planner-artifacts'
                label = 'Planner'
                expected = $true
                status = $(if ($plannerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($plannerArtifactsPass) { "Planner created plan.md, progress.md, iteration metadata, and $taskFileCount task definition file(s)." } else { 'Planner-owned plan/progress/task artifacts were incomplete.' }),
                    $subagentProvenanceById['planner-artifacts'].notes,
                    $workflowLayoutDetail
                )
                source_paths = @($iterationMetadataPath, $iterationPlanPath, $iterationProgressPath) + @($taskFiles | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'questioner-artifacts'
                label = 'Questioner'
                expected = $true
                status = $(if ($questionerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($questionerArtifactsPass) { "Questioner produced $questionFileCount grounded question artifact(s) with answered guidance." } else { 'Questioner artifacts were missing or lacked answered sections.' }),
                    $subagentProvenanceById['questioner-artifacts'].notes,
                    $workflowLayoutDetail
                )
                source_paths = @($iterationProgressPath) + @($questionFiles | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'executor-artifacts'
                label = 'Executor'
                expected = $true
                status = $(if ($executorPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($executorArtifactsPass) { "Executor produced $executorReportCount implementation report(s) and the task reached a qualified progress state." } else { 'Executor artifacts were incomplete; expected a PART 1 task report plus durable task progress updates.' }),
                    $subagentProvenanceById['executor-artifacts'].notes,
                    $workflowLayoutDetail
                )
                source_paths = @($smokeOutputPath, $iterationProgressPath) + @($reportFileDetails | Where-Object { $_.HasPart1 } | ForEach-Object { $_.Path })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'reviewer-artifacts'
                label = 'Reviewer'
                expected = $true
                status = $(if ($reviewerPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($reviewerArtifactsPass) { 'Reviewer appended PART 2 verdict evidence and produced iteration review closure.' } else { 'Reviewer verdict artifacts were incomplete; expected PART 2 review output plus iteration review.md.' }),
                    $subagentProvenanceById['reviewer-artifacts'].notes,
                    $workflowLayoutDetail
                )
                source_paths = @($iterationProgressPath, $iterationReviewPath) + @($reportFileDetails | Where-Object { $_.HasPart2 } | ForEach-Object { $_.Path })
                evidence_paths = @()
            }
            [ordered]@{
                id = 'librarian-artifacts'
                label = 'Librarian'
                expected = $true
                status = $(if ($librarianPass) { 'observed' } else { 'failed' })
                notes = Join-DetailSentences -Parts @(
                    $(if ($knowledgeObserved) { "Knowledge extraction/staging produced $knowledgeArtifactCount reusable knowledge file(s)." } elseif ($knowledgeExplicitlySkipped) { 'The minimal smoke scenario explicitly recorded the knowledge pipeline as skipped/cancelled, and the Ralph librarian custom agent log evidence confirms that decision came from the correct role.' } else { 'No durable librarian evidence or explicit skip markers were found.' }),
                    $subagentProvenanceById['librarian-artifacts'].notes,
                    $workflowLayoutDetail
                )
                source_paths = @($iterationProgressPath, $iterationReviewPath) + @($iterationKnowledgeItems | ForEach-Object { $_.FullName }) + @($sessionKnowledgeItems | ForEach-Object { $_.FullName })
                evidence_paths = @()
            }
        )

        $script:summary.workflow = [ordered]@{
            session_id = $resolvedSessionId
            session_path = $sessionPath
            workspace_root = $resolvedWorkingDirectory
            workspace_metadata = $workspaceMetadataPath
            workflow_metadata = $workflowMetadataPath
            workspace_active_session = $activeSessionPointerPath
            session_instruction = $sessionInstructionPath
            session_metadata = $sessionMetadataPath
            smoke_output_path = $smokeOutputPath
            agent_reported_session_path = $promptFinalResponse.session_path
            agent_reported_final_state = $promptFinalResponse.final_state
            final_state = $finalState
            layout = [ordered]@{
                detected = $workflowArtifactLayout.detected_layout
                label = $workflowArtifactLayout.label
                description = $workflowArtifactLayout.description
                detection_notes = $workflowArtifactLayout.detection_notes
                metadata_path = $workflowMetadataPath
                iteration_directory = $iterationDirectory
                session_metadata_candidate = $sessionMetadataPath
                root_metadata_candidate = $workspaceMetadataPath
                session_iteration_candidate = $workflowArtifactLayout.session_candidate.iteration_directory
                root_iteration_candidate = $workflowArtifactLayout.root_candidate.iteration_directory
                session_score = $workflowArtifactLayout.session_candidate.score
                root_score = $workflowArtifactLayout.root_candidate.score
                session_signal_count = $workflowArtifactLayout.session_signal_count
                root_signal_count = $workflowArtifactLayout.root_signal_count
                session_signal_labels = @($workflowArtifactLayout.session_candidate.signal_labels)
                root_signal_labels = @($workflowArtifactLayout.root_candidate.signal_labels)
            }
            iteration_directory = $iterationDirectory
            iteration_metadata = $iterationMetadataPath
            iteration_plan = $iterationPlanPath
            iteration_progress = $iterationProgressPath
            expected_custom_agents = [ordered]@{
                orchestrator = $bundledAgentNames.orchestrator
                planner = $bundledAgentNames.planner
                questioner = $bundledAgentNames.questioner
                executor = $bundledAgentNames.executor
                reviewer = $bundledAgentNames.reviewer
                librarian = $bundledAgentNames.librarian
            }
            unexpected_builtin_agent_delegation = [ordered]@{
                observed = [bool]$unexpectedBuiltinDelegationObserved
                match_count = Get-CollectionCount -Value $unexpectedBuiltinTaskMatches
                notes = $unexpectedBuiltinDelegationDetail
                sample_matches = @(
                    foreach ($match in @($unexpectedBuiltinTaskMatches | Select-Object -First 6)) {
                        [ordered]@{
                            path = $match.path
                            line_number = $match.line_number
                            text = $match.text
                        }
                    }
                )
            }
            subagent_provenance = @($subagentProvenance)
            role_coverage = @($roleCoverage)
            state_path = @($workflowStatePath)
            task_files = @($taskFiles | ForEach-Object { $_.FullName })
            question_files = @($questionFiles | ForEach-Object { $_.FullName })
            report_files = @($reportFiles | ForEach-Object { $_.FullName })
            iteration_review = $iterationReviewPath
            iteration_knowledge_files = @($iterationKnowledgeItems | ForEach-Object { $_.FullName })
            session_knowledge_files = @($sessionKnowledgeItems | ForEach-Object { $_.FullName })
        }

        Set-TestCaseStatus -Id 'orchestrator-invocation' -Status 'passed' -Details (Join-DetailSentences -Parts @(
                "Agent '$orchestratorAgentName' completed a live Ralph workflow invocation for session '$resolvedSessionId' and reported FINAL_STATE '$($promptFinalResponse.final_state)'.",
                "Verified expected Ralph custom subagents via Copilot CLI logs: planner='$($bundledAgentNames.planner)', questioner='$($bundledAgentNames.questioner)', executor='$($bundledAgentNames.executor)', reviewer='$($bundledAgentNames.reviewer)', librarian='$($bundledAgentNames.librarian)'.",
                $unexpectedBuiltinDelegationDetail,
                $workflowLayoutDetail
            ))
        foreach ($role in $roleCoverage) {
            $testStatus = switch ($role.status) {
                'observed' { 'passed' }
                'not_expected' { 'skipped' }
                default { 'failed' }
            }

            Set-TestCaseStatus -Id $role.id -Status $testStatus -Details $role.notes
        }
    }

    $failedValidationCount = @($script:testCases.Values | Where-Object { $_.status -eq 'failed' }).Count
    Assert-True -Condition ($failedValidationCount -eq 0) -Message "Smoke validation failed: $failedValidationCount checkpoint(s) failed."

    $script:summary.status = 'passed'
    $script:summary.stage = 'complete'
}
catch {
    $exitCode = 1

    if (-not [string]::IsNullOrWhiteSpace($script:currentCheckpointId) -and $script:testCases.Contains($script:currentCheckpointId)) {
        $currentCase = $script:testCases[$script:currentCheckpointId]
        if ($currentCase.status -eq 'pending') {
            Set-TestCaseStatus -Id $script:currentCheckpointId -Status 'failed' -Details $_.Exception.Message
        }
    }

    $script:summary.error = [ordered]@{
        stage = $script:summary.stage
        message = $_.Exception.Message
    }
}
finally {
    $script:currentCheckpointId = 'cleanup'
    $cleanupFailed = $false
    $cleanupMessages = New-Object System.Collections.Generic.List[string]
    $preCleanupWorkspaceEvidencePath = $null
    $preCleanupSmokeOutputEvidencePath = $null
    $preCleanupLogEvidencePath = $null
    $script:summary.cleanup = [ordered]@{
        uninstall_attempted = $false
        uninstall_command = $null
        uninstall_exit_code = $null
        uninstall_stdout = $null
        uninstall_stderr = $null
        directories = [ordered]@{
            working_directory = [ordered]@{
                path = $resolvedWorkingDirectory
                created_by_harness = $createdWorkingDirectory
                keep_requested = [bool]$KeepWorkingDirectory
                exists_before_cleanup = if (-not [string]::IsNullOrWhiteSpace($resolvedWorkingDirectory)) { Test-Path $resolvedWorkingDirectory } else { $false }
                removed = $false
                exists_after_cleanup = $false
            }
            log_dir = [ordered]@{
                path = $resolvedLogDir
                created_by_harness = $createdLogDir
                keep_requested = [bool]$KeepLogDir
                exists_before_cleanup = if (-not [string]::IsNullOrWhiteSpace($resolvedLogDir)) { Test-Path $resolvedLogDir } else { $false }
                removed = $false
                exists_after_cleanup = $false
            }
            config_dir = [ordered]@{
                path = $resolvedConfigDir
                created_by_harness = $createdConfigDir
                keep_requested = [bool]$KeepConfigDir
                exists_before_cleanup = if (-not [string]::IsNullOrWhiteSpace($resolvedConfigDir)) { Test-Path $resolvedConfigDir } else { $false }
                removed = $false
                exists_after_cleanup = $false
            }
        }
        messages = @()
    }

    try {
        New-Item -Path $reportEvidenceDirectory -ItemType Directory -Force | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($resolvedWorkingDirectory) -and (Test-Path $resolvedWorkingDirectory -PathType Container)) {
            $preCleanupWorkspaceEvidencePath = Copy-PathToEvidenceSnapshot -SourcePath $resolvedWorkingDirectory -SnapshotRoot $reportEvidenceDirectory -RelativeDestination 'workflow\working-directory'
        }

        if (-not [string]::IsNullOrWhiteSpace($smokeOutputPath) -and (Test-Path $smokeOutputPath -PathType Leaf)) {
            $preCleanupSmokeOutputEvidencePath = Copy-PathToEvidenceSnapshot -SourcePath $smokeOutputPath -SnapshotRoot $reportEvidenceDirectory -RelativeDestination ('workflow\working-directory\' + (Split-Path -Path $smokeOutputPath -Leaf))
        }

        if (-not [string]::IsNullOrWhiteSpace($resolvedLogDir) -and (Test-Path $resolvedLogDir -PathType Container)) {
            $preCleanupLogEvidencePath = Copy-PathToEvidenceSnapshot -SourcePath $resolvedLogDir -SnapshotRoot $reportEvidenceDirectory -RelativeDestination 'workflow\logs'
        }
    }
    catch {
        $cleanupFailed = $true
        if ($exitCode -eq 0) {
            $exitCode = 1
            $script:summary.status = 'failed'
        }
        if ($null -eq $script:summary.error) {
            $script:summary.error = [ordered]@{
                stage = 'cleanup'
                message = "Pre-cleanup evidence snapshot failed: $($_.Exception.Message)"
            }
        }
        $cleanupMessages.Add("Pre-cleanup evidence snapshot failed: $($_.Exception.Message)")
    }

    if ($pluginInstalledByHarness -and -not $pluginPreviouslyInstalled -and $null -ne $copilotCommand -and $null -ne $buildManifest) {
        try {
            $uninstallResult = Invoke-ExternalCommand -FilePath $copilotCommand.FilePath -Arguments ($copilotCommand.PrefixArguments + @('plugin', 'uninstall', '--config-dir', $resolvedConfigDir, $buildManifest.name)) -WorkingDirectory $repoRoot -TimeoutSeconds 120
            $script:summary.cleanup.uninstall_attempted = $true
            $script:summary.cleanup.uninstall_command = $uninstallResult.CommandLine
            $script:summary.cleanup.uninstall_exit_code = $uninstallResult.ExitCode
            $script:summary.cleanup.uninstall_stdout = $uninstallResult.StdOut
            $script:summary.cleanup.uninstall_stderr = $uninstallResult.StdErr
            $script:summary.commands.plugin_uninstall = [ordered]@{
                command = $uninstallResult.CommandLine
                exit_code = $uninstallResult.ExitCode
                attempted = $true
            }

            if ($uninstallResult.ExitCode -ne 0) {
                $cleanupFailed = $true
                if ($exitCode -eq 0) {
                    $exitCode = 1
                    $script:summary.status = 'failed'
                }

                if ($null -eq $script:summary.error) {
                    $script:summary.error = [ordered]@{
                        stage = 'cleanup'
                        message = "Harness installed '$($buildManifest.name)' but could not uninstall it cleanly."
                    }
                }
            }
            else {
                $cleanupMessages.Add("Uninstalled plugin '$($buildManifest.name)' from $resolvedConfigDir.")
            }
        }
        catch {
            $cleanupFailed = $true
            if ($exitCode -eq 0) {
                $exitCode = 1
                $script:summary.status = 'failed'
            }

            $script:summary.cleanup.uninstall_attempted = $true
            $script:summary.commands.plugin_uninstall = [ordered]@{
                command = $null
                exit_code = $null
                attempted = $true
            }

            if ($null -eq $script:summary.error) {
                $script:summary.error = [ordered]@{
                    stage = 'cleanup'
                    message = $_.Exception.Message
                }
            }
        }
    }
    else {
        $cleanupMessages.Add('No plugin uninstall was required for this execution.')
        $script:summary.commands.plugin_uninstall = [ordered]@{
            command = $null
            exit_code = $null
            attempted = $false
        }
    }

    $directoryCleanupSpecs = @(
        [PSCustomObject]@{
            key = 'working_directory'
            path = $resolvedWorkingDirectory
            created = $createdWorkingDirectory
            keep = [bool]$KeepWorkingDirectory
            label = 'working directory'
        },
        [PSCustomObject]@{
            key = 'log_dir'
            path = $resolvedLogDir
            created = $createdLogDir
            keep = [bool]$KeepLogDir
            label = 'log directory'
        },
        [PSCustomObject]@{
            key = 'config_dir'
            path = $resolvedConfigDir
            created = $createdConfigDir
            keep = [bool]$KeepConfigDir
            label = 'config directory'
        }
    )

    foreach ($directorySpec in $directoryCleanupSpecs) {
        $directorySummary = $script:summary.cleanup.directories[$directorySpec.key]
        if ([string]::IsNullOrWhiteSpace($directorySpec.path)) {
            $directorySummary.exists_after_cleanup = $false
            continue
        }

        if ($directorySpec.created -and -not $directorySpec.keep -and (Test-Path $directorySpec.path)) {
            try {
                Remove-Item -Path $directorySpec.path -Recurse -Force
                $directorySummary.removed = $true
                $cleanupMessages.Add("Removed transient $($directorySpec.label): $($directorySpec.path)")
            }
            catch {
                $cleanupFailed = $true
                if ($exitCode -eq 0) {
                    $exitCode = 1
                    $script:summary.status = 'failed'
                }

                if ($null -eq $script:summary.error) {
                    $script:summary.error = [ordered]@{
                        stage = 'cleanup'
                        message = $_.Exception.Message
                    }
                }
            }
        }
        elseif ($directorySpec.keep -and -not [string]::IsNullOrWhiteSpace($directorySpec.path)) {
            $cleanupMessages.Add("Retained $($directorySpec.label) for review: $($directorySpec.path)")
        }

        $directorySummary.exists_after_cleanup = Test-Path $directorySpec.path
    }

    $script:summary.cleanup.messages = @($cleanupMessages)

    if ($cleanupFailed) {
        Set-TestCaseStatus -Id 'cleanup' -Status 'failed' -Details $script:summary.error.message
    }
    else {
        Set-TestCaseStatus -Id 'cleanup' -Status 'passed' -Details (($cleanupMessages -join ' ') -replace '\s+', ' ').Trim()
    }

    Complete-PendingTestCases

    try {
        New-Item -Path $reportEvidenceDirectory -ItemType Directory -Force | Out-Null
        $evidenceArtifacts = New-Object System.Collections.Generic.List[object]
        $commandsEvidencePath = Join-Path $reportEvidenceDirectory 'commands.json'
        Write-JsonArtifact -Path $commandsEvidencePath -InputObject $script:summary.commands
        Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'overall' -Description 'Commands used during this smoke run' -Path $commandsEvidencePath -Kind 'json' -Notes 'Verbatim command lines and exit codes for each harness step.'
        Add-TestCaseEvidence -Id 'overall' -EvidencePaths @($commandsEvidencePath)

        $copilotVersionPath = if ($null -ne $versionResult) {
            Join-Path $reportEvidenceDirectory 'copilot-version.txt'
        }
        else {
            $null
        }

        if ($null -ne $copilotVersionPath) {
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'overall' -Description 'copilot --version output' -Path $copilotVersionPath -Content $versionResult.StdOut -CommandLine $versionResult.CommandLine)
            Add-TestCaseEvidence -Id 'copilot-version' -EvidencePaths @($copilotVersionPath)
        }

        if ($null -ne $sourceManifest) {
            $sourceManifestEvidencePath = Join-Path $reportEvidenceDirectory 'source-plugin.json'
            Write-JsonArtifact -Path $sourceManifestEvidencePath -InputObject $sourceManifest
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'build' -Description 'Source plugin manifest used as build input' -Path $sourceManifestEvidencePath
            Add-TestCaseEvidence -Id 'build-cli-bundle' -EvidencePaths @($sourceManifestEvidencePath)
        }

        if ($null -ne $buildManifest) {
            $buildManifestEvidencePath = Join-Path $reportEvidenceDirectory 'built-plugin.json'
            Write-JsonArtifact -Path $buildManifestEvidencePath -InputObject $buildManifest
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'build' -Description 'Built plugin manifest emitted by the smoke harness build step' -Path $buildManifestEvidencePath
            Add-TestCaseEvidence -Id 'build-cli-bundle' -EvidencePaths @($buildManifestEvidencePath)
        }

        if ($null -ne $script:summary.build) {
            $buildSummaryEvidencePath = Join-Path $reportEvidenceDirectory 'build-summary.json'
            Write-JsonArtifact -Path $buildSummaryEvidencePath -InputObject $script:summary.build
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'build' -Description 'Structured build summary captured during execution' -Path $buildSummaryEvidencePath
            Add-TestCaseEvidence -Id 'build-cli-bundle' -EvidencePaths @($buildSummaryEvidencePath)
        }

        if ($null -ne $installResult) {
            $installStdOutPath = Join-Path $reportEvidenceDirectory 'plugin-install.stdout.txt'
            $installStdErrPath = Join-Path $reportEvidenceDirectory 'plugin-install.stderr.txt'
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'install' -Description 'copilot plugin install standard output' -Path $installStdOutPath -Content $installResult.StdOut -CommandLine $installResult.CommandLine)
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'install' -Description 'copilot plugin install standard error' -Path $installStdErrPath -Content $installResult.StdErr -CommandLine $installResult.CommandLine)
            Add-TestCaseEvidence -Id 'install-cli-plugin' -EvidencePaths @($installStdOutPath, $installStdErrPath)
        }

        if ($null -ne $listResult) {
            $pluginListStdOutPath = Join-Path $reportEvidenceDirectory 'plugin-list.stdout.txt'
            $pluginListStdErrPath = Join-Path $reportEvidenceDirectory 'plugin-list.stderr.txt'
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'discovery' -Description 'copilot plugin list standard output' -Path $pluginListStdOutPath -Content $listResult.StdOut -CommandLine $listResult.CommandLine)
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'discovery' -Description 'copilot plugin list standard error' -Path $pluginListStdErrPath -Content $listResult.StdErr -CommandLine $listResult.CommandLine)
            Add-TestCaseEvidence -Id 'verify-plugin-discovery' -EvidencePaths @($pluginListStdOutPath, $pluginListStdErrPath)
        }

        if ($null -ne $preferredInstalledManifest) {
            $installedManifestEvidencePath = Join-Path $reportEvidenceDirectory 'installed-plugin.json'
            Write-JsonArtifact -Path $installedManifestEvidencePath -InputObject $preferredInstalledManifest.Manifest
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'discovery' -Description 'Installed plugin manifest detected after installation' -Path $installedManifestEvidencePath
            Add-TestCaseEvidence -Id 'verify-plugin-discovery' -EvidencePaths @($installedManifestEvidencePath)
        }

        if ($null -ne $script:summary.install) {
            $installSummaryEvidencePath = Join-Path $reportEvidenceDirectory 'install-summary.json'
            Write-JsonArtifact -Path $installSummaryEvidencePath -InputObject $script:summary.install
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'discovery' -Description 'Structured install and discovery summary' -Path $installSummaryEvidencePath
            Add-TestCaseEvidence -Id 'verify-plugin-discovery' -EvidencePaths @($installSummaryEvidencePath)
        }

        if ($null -ne $script:summary.agent_invocation) {
            $agentInvocationEvidencePath = Join-Path $reportEvidenceDirectory 'agent-invocation.json'
            Write-JsonArtifact -Path $agentInvocationEvidencePath -InputObject $script:summary.agent_invocation
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'agent' -Description 'Structured agent invocation record' -Path $agentInvocationEvidencePath
            Add-TestCaseEvidence -Id 'orchestrator-invocation' -EvidencePaths @($agentInvocationEvidencePath)
        }

        if ($null -ne $promptResult) {
            $agentStdOutPath = Join-Path $reportEvidenceDirectory 'agent.stdout.txt'
            $agentStdErrPath = Join-Path $reportEvidenceDirectory 'agent.stderr.txt'
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'agent' -Description 'Agent invocation standard output' -Path $agentStdOutPath -Content $promptResult.StdOut -CommandLine $promptResult.CommandLine)
            [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'agent' -Description 'Agent invocation standard error' -Path $agentStdErrPath -Content $promptResult.StdErr -CommandLine $promptResult.CommandLine)
            Add-TestCaseEvidence -Id 'orchestrator-invocation' -EvidencePaths @($agentStdOutPath, $agentStdErrPath)
        }

        if ($null -ne $script:summary.workflow) {
            $script:summary.workflow.workspace_snapshot = $preCleanupWorkspaceEvidencePath

            foreach ($checkpoint in @($script:summary.workflow.state_path)) {
                $checkpoint.evidence_paths = @(
                    foreach ($sourcePath in @($checkpoint.source_paths)) {
                        $snapshotPath = Get-WorkspaceSnapshotPath -SourcePath $sourcePath -WorkspaceRoot $resolvedWorkingDirectory -WorkspaceSnapshotRoot $preCleanupWorkspaceEvidencePath
                        if (-not [string]::IsNullOrWhiteSpace($snapshotPath) -and (Test-Path $snapshotPath)) {
                            $snapshotPath
                        }
                    }
                ) | Select-Object -Unique
            }

            foreach ($role in @($script:summary.workflow.role_coverage)) {
                $role.evidence_paths = @(
                    foreach ($sourcePath in @($role.source_paths)) {
                        $snapshotPath = Get-WorkspaceSnapshotPath -SourcePath $sourcePath -WorkspaceRoot $resolvedWorkingDirectory -WorkspaceSnapshotRoot $preCleanupWorkspaceEvidencePath
                        if (-not [string]::IsNullOrWhiteSpace($snapshotPath) -and (Test-Path $snapshotPath)) {
                            $snapshotPath
                        }
                    }
                ) | Select-Object -Unique
            }

            foreach ($provenance in @($script:summary.workflow.subagent_provenance)) {
                $provenance.evidence_paths = @()
                if ($null -ne $preCleanupLogEvidencePath) {
                    $provenance.evidence_paths += $preCleanupLogEvidencePath
                }
            }

            $workflowEvidencePath = Join-Path $reportEvidenceDirectory 'workflow-summary.json'
            Write-JsonArtifact -Path $workflowEvidencePath -InputObject $script:summary.workflow
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'workflow' -Description 'Structured Ralph workflow artifact summary' -Path $workflowEvidencePath
            foreach ($role in @($script:summary.workflow.role_coverage)) {
                Add-TestCaseEvidence -Id $role.id -EvidencePaths (@($workflowEvidencePath) + @($role.evidence_paths))
            }

            if ((Get-CollectionCount -Value $script:summary.workflow.subagent_provenance) -gt 0) {
                $provenanceEvidencePath = Join-Path $reportEvidenceDirectory 'subagent-provenance.json'
                Write-JsonArtifact -Path $provenanceEvidencePath -InputObject $script:summary.workflow.subagent_provenance
                Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'workflow' -Description 'Structured proof that the expected Ralph custom subagents were invoked for each role' -Path $provenanceEvidencePath -Kind 'json'
                foreach ($provenance in @($script:summary.workflow.subagent_provenance)) {
                    $provenance.evidence_paths = @($provenance.evidence_paths + @($provenanceEvidencePath) | Select-Object -Unique)
                }
                foreach ($roleId in @('planner-artifacts', 'questioner-artifacts', 'executor-artifacts', 'reviewer-artifacts', 'librarian-artifacts')) {
                    Add-TestCaseEvidence -Id $roleId -EvidencePaths @($provenanceEvidencePath)
                }
            }
        }

        if ($null -ne $preCleanupWorkspaceEvidencePath) {
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'workflow' -Description 'Snapshot of the isolated workspace produced by the live Ralph smoke scenario' -Path $preCleanupWorkspaceEvidencePath -Kind 'directory'
            foreach ($roleId in @('orchestrator-session-state', 'planner-artifacts', 'questioner-artifacts', 'executor-artifacts', 'reviewer-artifacts', 'librarian-artifacts')) {
                Add-TestCaseEvidence -Id $roleId -EvidencePaths @($preCleanupWorkspaceEvidencePath)
            }
        }

        if ($null -ne $preCleanupSmokeOutputEvidencePath) {
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'workflow' -Description 'Snapshot of the generated smoke output file before workspace cleanup' -Path $preCleanupSmokeOutputEvidencePath
            Add-TestCaseEvidence -Id 'executor-artifacts' -EvidencePaths @($preCleanupSmokeOutputEvidencePath)
        }

        if ($null -ne $preCleanupLogEvidencePath) {
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'workflow' -Description 'Snapshot of Copilot CLI logs captured before cleanup' -Path $preCleanupLogEvidencePath -Kind 'directory'
            Add-TestCaseEvidence -Id 'orchestrator-invocation' -EvidencePaths @($preCleanupLogEvidencePath)
            foreach ($roleId in @('planner-artifacts', 'questioner-artifacts', 'executor-artifacts', 'reviewer-artifacts', 'librarian-artifacts')) {
                Add-TestCaseEvidence -Id $roleId -EvidencePaths @($preCleanupLogEvidencePath)
            }
        }

        if ($null -ne $script:summary.cleanup) {
            $cleanupEvidencePath = Join-Path $reportEvidenceDirectory 'cleanup.json'
            Write-JsonArtifact -Path $cleanupEvidencePath -InputObject $script:summary.cleanup
            Add-EvidenceArtifact -Artifacts $evidenceArtifacts -Category 'cleanup' -Description 'Cleanup results, retained paths, and removal decisions' -Path $cleanupEvidencePath
            Add-TestCaseEvidence -Id 'cleanup' -EvidencePaths @($cleanupEvidencePath)

            if ($script:summary.cleanup.uninstall_attempted) {
                $uninstallStdOutPath = Join-Path $reportEvidenceDirectory 'plugin-uninstall.stdout.txt'
                $uninstallStdErrPath = Join-Path $reportEvidenceDirectory 'plugin-uninstall.stderr.txt'
                [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'cleanup' -Description 'copilot plugin uninstall standard output' -Path $uninstallStdOutPath -Content $script:summary.cleanup.uninstall_stdout -CommandLine $script:summary.cleanup.uninstall_command)
                [void](Write-TextEvidenceArtifact -Artifacts $evidenceArtifacts -Category 'cleanup' -Description 'copilot plugin uninstall standard error' -Path $uninstallStdErrPath -Content $script:summary.cleanup.uninstall_stderr -CommandLine $script:summary.cleanup.uninstall_command)
                Add-TestCaseEvidence -Id 'cleanup' -EvidencePaths @($uninstallStdOutPath, $uninstallStdErrPath)
            }
        }

        $scriptEndTime = (Get-Date).ToUniversalTime()
        $script:summary.finished_at = $scriptEndTime.ToString('o')
        $script:summary.duration_seconds = [Math]::Round(($scriptEndTime - $scriptStartTime).TotalSeconds, 3)
        $script:summary.artifacts.evidence_files = @($evidenceArtifacts.ToArray())
        $script:summary.checkpoint_summary = Get-TestCaseCounts
        $overallDetail = "Run status: {0}. Passed {1}/{2} checkpoints, skipped {3}, failed {4}, not run {5}. Review bundle: {6}" -f $script:summary.status, $script:summary.checkpoint_summary.passed, $script:summary.checkpoint_summary.total, $script:summary.checkpoint_summary.skipped, $script:summary.checkpoint_summary.failed, $script:summary.checkpoint_summary.not_run, $resolvedReportPath
        Set-TestCaseStatus -Id 'overall' -Status $(if ($script:summary.status -eq 'passed') { 'passed' } else { 'failed' }) -Details $overallDetail
        Add-TestCaseEvidence -Id 'overall' -EvidencePaths @($summaryJsonPath, $testCasesJsonPath, $inputsJsonPath)
        $script:summary.test_cases = @(Get-TestCaseList)

        Write-JsonArtifact -Path $inputsJsonPath -InputObject $script:summary.inputs
        Write-JsonArtifact -Path $testCasesJsonPath -InputObject $script:summary.test_cases
        Write-JsonArtifact -Path $summaryJsonPath -InputObject $script:summary

        $reportMarkdown = New-SmokeReportMarkdown -Summary $script:summary -TestCases $script:summary.test_cases -EvidenceArtifacts $script:summary.artifacts.evidence_files -ReportDirectory $reportDirectory
        Write-Utf8File -Path $resolvedReportPath -Content $reportMarkdown
    }
    catch {
        if ($exitCode -eq 0) {
            $exitCode = 1
            $script:summary.status = 'failed'
        }

        $script:summary.finished_at = (Get-Date).ToUniversalTime().ToString('o')
        $script:summary.duration_seconds = [Math]::Round((((Get-Date).ToUniversalTime()) - $scriptStartTime).TotalSeconds, 3)

        if ($null -eq $script:summary.error) {
            $script:summary.error = [ordered]@{
                stage = 'reporting'
                message = $_.Exception.Message
            }
        }

        if ($script:testCases.Contains('cleanup') -and $script:testCases['cleanup'].status -ne 'failed') {
            Set-TestCaseStatus -Id 'cleanup' -Status 'failed' -Details $_.Exception.Message
        }

        Complete-PendingTestCases
        $script:summary.checkpoint_summary = Get-TestCaseCounts
        Set-TestCaseStatus -Id 'overall' -Status 'failed' -Details ("Run status: failed. Passed {0}/{1} checkpoints, skipped {2}, failed {3}, not run {4}. Reporting error: {5}" -f $script:summary.checkpoint_summary.passed, $script:summary.checkpoint_summary.total, $script:summary.checkpoint_summary.skipped, $script:summary.checkpoint_summary.failed, $script:summary.checkpoint_summary.not_run, $_.Exception.Message)
        $script:summary.test_cases = @(Get-TestCaseList)
    }

    $script:summary | ConvertTo-Json -Depth 12
    exit $exitCode
}
