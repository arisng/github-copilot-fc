<#
.SYNOPSIS
    Smoke-tests the shared Ralph hook logger through the Windows manifest runtime.

.DESCRIPTION
    Validates that the hook manifest still points all shared hook events to the
    Windows PowerShell runtime contract and replays subagentStart,
    preToolUse, postToolUse, and subagentStop through that exact entrypoint.

    The test fails immediately on parser or startup regressions and verifies
    that each event appends the expected JSONL output in an isolated workspace.
#>

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

function Get-ManifestHookConfig {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$EventName
    )

    $eventHooks = $Manifest.hooks.PSObject.Properties[$EventName]
    Assert-True -Condition ($null -ne $eventHooks) -Message "Hook manifest entry not found for event '$EventName'."
    Assert-True -Condition ($eventHooks.Value.Count -ge 1) -Message "Hook manifest entry for '$EventName' is empty."
    return $eventHooks.Value[0]
}

function Set-TemporaryEnvironment {
    param($Environment)

    $snapshot = @{}
    if ($null -eq $Environment) {
        return $snapshot
    }

    foreach ($property in $Environment.PSObject.Properties) {
        $existing = [Environment]::GetEnvironmentVariable($property.Name, 'Process')
        $snapshot[$property.Name] = $existing
        [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value, 'Process')
    }

    return $snapshot
}

function Restore-TemporaryEnvironment {
    param([hashtable]$Snapshot)

    foreach ($name in $Snapshot.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Snapshot[$name], 'Process')
    }
}

function Get-LastJsonLine {
    param([Parameter(Mandatory)][string]$Path)

    Assert-True -Condition (Test-Path $Path) -Message "Expected log file was not created: $Path"
    $lastLine = Get-Content $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($lastLine)) -Message "Expected at least one JSONL entry in $Path"
    return $lastLine | ConvertFrom-Json
}

function Invoke-ManifestHook {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$HookConfig,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    $environment = $null
    $environmentProperty = $HookConfig.PSObject.Properties['env']
    if ($null -ne $environmentProperty) {
        $environment = $environmentProperty.Value
    }

    $environmentSnapshot = Set-TemporaryEnvironment -Environment $environment
    $payloadJson = $Payload | ConvertTo-Json -Compress -Depth 10

    Push-Location $RepoRoot
    try {
        $output = $payloadJson | & powershell -NoProfile -File 'hooks\scripts\ralph-tool-logger.ps1' 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        Restore-TemporaryEnvironment -Snapshot $environmentSnapshot
    }

    $outputLines = @($output | ForEach-Object { $_.ToString() })
    $combinedOutput = ($outputLines -join [Environment]::NewLine).Trim()

    Assert-True -Condition ($exitCode -eq 0) -Message "Manifest runtime failed for event '$($Payload.hookEventName)' with exit code $exitCode. Output: $combinedOutput"
    Assert-True -Condition ($combinedOutput -match '"continue"\s*:\s*true') -Message "Manifest runtime did not return a continue response for event '$($Payload.hookEventName)'. Output: $combinedOutput"

    return [ordered]@{
        exit_code = $exitCode
        output = $outputLines
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $repoRoot 'hooks\ralph-tool-logger.hooks.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$expectedCommand = 'powershell -NoProfile -File hooks\scripts\ralph-tool-logger.ps1'
$eventOrder = @('subagentStart', 'preToolUse', 'postToolUse', 'subagentStop')
$hookConfigs = @{}

foreach ($eventName in $eventOrder) {
    $config = Get-ManifestHookConfig -Manifest $manifest -EventName $eventName
    Assert-True -Condition ($config.type -eq 'command') -Message "Hook manifest entry for '$eventName' must use a command hook."
    Assert-True -Condition ($config.powershell -eq $expectedCommand) -Message "Hook manifest entry for '$eventName' must keep the Windows runtime contract '$expectedCommand'. Found '$($config.powershell)'."
    $hookConfigs[$eventName] = $config
}

$workspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ralph-hook-runtime-smoke-" + [Guid]::NewGuid().ToString('N'))
$sessionRoot = Join-Path $workspaceRoot '.ralph-sessions'
$sessionId = 'task-2-smoke'
$sessionPath = Join-Path $sessionRoot $sessionId
$iterationLogDir = Join-Path $sessionPath 'iterations\4\logs'

New-Item -ItemType Directory -Path $iterationLogDir -Force | Out-Null
Set-Content -Path (Join-Path $sessionRoot '.active-session') -Value $sessionId -Encoding UTF8
Set-Content -Path (Join-Path $sessionPath 'metadata.yaml') -Value @(
    'version: 2'
    "session_id: $sessionId"
    'iteration: 4'
    'state: ACTIVE'
) -Encoding UTF8

$toolLogPath = Join-Path $iterationLogDir 'tool-usage.jsonl'
$subagentLogPath = Join-Path $iterationLogDir 'subagent-usage.jsonl'
$transcriptPath = 'transcripts/executor-smoke.jsonl'
$agentName = 'executor-smoke'

$events = @(
    [ordered]@{
        name = 'subagentStart'
        payload = [ordered]@{
            hookEventName = 'subagentStart'
            timestamp = '1710000000000'
            cwd = $workspaceRoot
            transcript_path = $transcriptPath
            agent_id = $agentName
            agent_type = 'Executor'
        }
        logPath = $subagentLogPath
        validate = {
            param($entry)
            Assert-True -Condition ($entry.event -eq 'subagentStart') -Message 'subagentStart entry was not written to the subagent log.'
            Assert-True -Condition ($entry.agent -eq $agentName) -Message 'subagentStart entry did not preserve the agent name.'
            Assert-True -Condition ($entry.transcript_path -eq $transcriptPath) -Message 'subagentStart entry did not preserve the transcript path.'
        }
    }
    [ordered]@{
        name = 'preToolUse'
        payload = [ordered]@{
            hookEventName = 'preToolUse'
            timestamp = '1710000001000'
            cwd = $workspaceRoot
            transcript_path = $transcriptPath
            tool_name = 'read_file'
            tool_input = [ordered]@{ path = 'README.md' }
        }
        logPath = $toolLogPath
        validate = {
            param($entry)
            Assert-True -Condition ($entry.event -eq 'preToolUse') -Message 'preToolUse entry was not written to the tool log.'
            Assert-True -Condition ($entry.tool -eq 'read_file') -Message 'preToolUse entry did not preserve the tool name.'
            Assert-True -Condition ($entry.agent -eq $agentName) -Message 'preToolUse entry did not resolve the active subagent name.'
            Assert-True -Condition ($entry.tool_args.path -eq 'README.md') -Message 'preToolUse entry did not capture tool_args under the manifest payload contract.'
        }
    }
    [ordered]@{
        name = 'postToolUse'
        payload = [ordered]@{
            hookEventName = 'postToolUse'
            timestamp = '1710000002000'
            cwd = $workspaceRoot
            transcript_path = $transcriptPath
            tool_name = 'read_file'
            tool_input = [ordered]@{ path = 'README.md' }
            tool_result = [ordered]@{
                resultType = 'text'
                textResultForLlm = 'README contents'
                file_count = 1
            }
        }
        logPath = $toolLogPath
        validate = {
            param($entry)
            Assert-True -Condition ($entry.event -eq 'postToolUse') -Message 'postToolUse entry was not written to the tool log.'
            Assert-True -Condition ($entry.result_type -eq 'text') -Message 'postToolUse entry did not preserve result_type.'
            Assert-True -Condition ($entry.result_text -eq 'README contents') -Message 'postToolUse entry did not preserve result_text.'
            Assert-True -Condition ($entry.tool_result.file_count -eq 1) -Message 'postToolUse entry did not capture tool_result when payload logging is enabled.'
        }
    }
    [ordered]@{
        name = 'subagentStop'
        payload = [ordered]@{
            hookEventName = 'subagentStop'
            timestamp = '1710000003000'
            cwd = $workspaceRoot
            transcript_path = $transcriptPath
            agent_id = $agentName
            agent_type = 'Executor'
            stop_hook_active = $true
        }
        logPath = $subagentLogPath
        validate = {
            param($entry)
            Assert-True -Condition ($entry.event -eq 'subagentStop') -Message 'subagentStop entry was not written to the subagent log.'
            Assert-True -Condition ($entry.stop_hook_active -eq $true) -Message 'subagentStop entry did not preserve stop_hook_active.'
            Assert-True -Condition ($entry.agent -eq $agentName) -Message 'subagentStop entry did not preserve the agent name.'
        }
    }
)

$results = @()

try {
    foreach ($event in $events) {
        $result = Invoke-ManifestHook -RepoRoot $repoRoot -HookConfig $hookConfigs[$event.name] -Payload $event.payload
        $entry = Get-LastJsonLine -Path $event.logPath
        & $event.validate $entry

        $results += [ordered]@{
            event = $event.name
            exit_code = $result.exit_code
            log_path = $event.logPath
        }
    }

    [ordered]@{
        manifest_path = $manifestPath
        powershell_command = $expectedCommand
        workspace_root = $workspaceRoot
        session_id = $sessionId
        events = $results
        status = 'passed'
    } | ConvertTo-Json -Depth 10
}
finally {
    if (Test-Path $workspaceRoot) {
        Remove-Item -Path $workspaceRoot -Recurse -Force
    }
}