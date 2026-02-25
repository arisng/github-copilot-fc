Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
$scriptPath = Join-Path $repoRoot 'hooks/scripts/ralph-v2-finalize-session-stop.py'

function Invoke-PythonScript {
  param(
    [string]$Path
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    & python $Path | Out-Null
    return
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    & py $Path | Out-Null
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

Write-Host 'PASS: Stop finalizer deterministic fixture test'
