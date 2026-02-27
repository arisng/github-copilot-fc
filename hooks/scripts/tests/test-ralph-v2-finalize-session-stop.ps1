Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
$scriptPath = Join-Path $repoRoot 'hooks/scripts/ralph-v2-finalize-session-stop.py'

function Invoke-PythonScript {
  param(
    [string]$Path,
    [string]$InputText
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    if ($PSBoundParameters.ContainsKey('InputText')) {
      $InputText | & python $Path | Out-Null
    }
    else {
      & python $Path | Out-Null
    }
    return
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    if ($PSBoundParameters.ContainsKey('InputText')) {
      $InputText | & py $Path | Out-Null
    }
    else {
      & py $Path | Out-Null
    }
    return
  }

  throw 'No Python runtime found (python/py).'
}

$testRoot = Join-Path $PSScriptRoot '.tmp-stop-finalizer'
if (Test-Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot | Out-Null

$sessionsRoot = Join-Path $testRoot '.ralph-sessions'
New-Item -ItemType Directory -Path $sessionsRoot | Out-Null

$activeSessionPath = Join-Path $sessionsRoot '.active-session'
$sessionId = '260225-101500'
Set-Content -Path $activeSessionPath -Value $sessionId -NoNewline -Encoding utf8

$sessionPath = Join-Path $sessionsRoot $sessionId
$logsPath = Join-Path $sessionPath 'logs'
New-Item -ItemType Directory -Path $logsPath -Force | Out-Null

$markerPath = Join-Path $sessionPath '.hook-enabled'
Set-Content -Path $markerPath -Value 'ralph-v2' -NoNewline -Encoding utf8

$metadataPath = Join-Path $sessionPath 'metadata.yaml'
@"
version: 1
session_id: 260225-101500
created_at: 2026-02-25T10:15:00+07:00
updated_at: 2026-02-25T10:30:00+07:00
status: in_progress
iteration: 1
orchestrator:
  state: EXECUTING_BATCH
  current_wave: 1
"@ | Set-Content -Path $metadataPath -Encoding utf8

$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$updated = Get-Content -Path $metadataPath -Raw
if ($updated -notmatch "status: blocked") { throw 'Expected status to be blocked' }
if ($updated -notmatch "  state: COMPLETE") { throw 'Expected orchestrator.state COMPLETE' }
if ($updated -notmatch "finalized_by: hook.stop") { throw 'Expected finalized_by marker' }

$logPath = Join-Path $logsPath 'hook-finalization.jsonl'
if (-not (Test-Path $logPath)) { throw 'Expected hook log to exist' }

# Re-run for idempotence check
Set-Content -Path $activeSessionPath -Value $sessionId -NoNewline -Encoding utf8
$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$updated2 = Get-Content -Path $metadataPath -Raw
if ($updated2 -notmatch "status: blocked") { throw 'Idempotence failed: status changed unexpectedly' }

# Negative test: remove marker -> script must no-op
Remove-Item -Path $markerPath -Force
@"
version: 1
session_id: 260225-101500
created_at: 2026-02-25T10:15:00+07:00
updated_at: 2026-02-25T10:30:00+07:00
status: in_progress
iteration: 1
orchestrator:
  state: EXECUTING_BATCH
  current_wave: 1
"@ | Set-Content -Path $metadataPath -Encoding utf8

Set-Content -Path $activeSessionPath -Value $sessionId -NoNewline -Encoding utf8
$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$updated3 = Get-Content -Path $metadataPath -Raw
if ($updated3 -match "finalized_by: hook.stop") { throw 'Expected no-op without .hook-enabled marker' }
if ($updated3 -notmatch "status: in_progress") { throw 'Expected metadata untouched without marker' }

# Binding test: resolve by hook session id mapping
Set-Content -Path $markerPath -Value 'ralph-v2' -NoNewline -Encoding utf8
$bindingsPath = Join-Path $sessionsRoot '.hook-bindings'
New-Item -ItemType Directory -Path $bindingsPath -Force | Out-Null
$hookSessionId = 'chat-abc-001'
@"
{"ralph_session_id":"260225-101500","updated_at":"2026-02-25T10:40:00+07:00","source":"user_prompt"}
"@ | Set-Content -Path (Join-Path $bindingsPath "$hookSessionId.json") -Encoding utf8

@"
version: 1
session_id: 260225-101500
created_at: 2026-02-25T10:15:00+07:00
updated_at: 2026-02-25T10:30:00+07:00
status: in_progress
iteration: 1
orchestrator:
  state: EXECUTING_BATCH
  current_wave: 1
"@ | Set-Content -Path $metadataPath -Encoding utf8

$stopPayloadFromBinding = '{"hookEventName":"Stop","sessionId":"chat-abc-001"}'
$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath -InputText $stopPayloadFromBinding
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$updated4 = Get-Content -Path $metadataPath -Raw
if ($updated4 -notmatch "finalized_by: hook.stop") { throw 'Expected finalization via hook-session binding' }

# Transcript fallback test: no binding, no active-session, resolve from transcript_path
Remove-Item -Path (Join-Path $bindingsPath "$hookSessionId.json") -Force
Set-Content -Path $activeSessionPath -Value '' -NoNewline -Encoding utf8

@"
version: 1
session_id: 260225-101500
created_at: 2026-02-25T10:15:00+07:00
updated_at: 2026-02-25T10:30:00+07:00
status: in_progress
iteration: 1
orchestrator:
  state: EXECUTING_BATCH
  current_wave: 1
"@ | Set-Content -Path $metadataPath -Encoding utf8

$transcriptPath = Join-Path $testRoot 'sample.transcript.md'
@"
continue session 260225-101500 with new feedback
"@ | Set-Content -Path $transcriptPath -Encoding utf8

$stopPayloadFromTranscript = @{
  hookEventName = 'Stop'
  sessionId = 'chat-xyz-002'
  transcript_path = $transcriptPath
} | ConvertTo-Json -Compress
$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath -InputText $stopPayloadFromTranscript
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$updated5 = Get-Content -Path $metadataPath -Raw
if ($updated5 -notmatch "finalized_by: hook.stop") { throw 'Expected finalization via transcript fallback' }

Write-Host 'PASS: Stop finalizer deterministic fixture test'
