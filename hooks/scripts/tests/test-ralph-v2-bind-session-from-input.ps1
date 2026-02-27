Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
$scriptPath = Join-Path $repoRoot 'hooks/scripts/ralph-v2-bind-session-from-input.py'

function Invoke-PythonScript {
  param(
    [string]$Path,
    [string]$InputText
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    $InputText | & python $Path | Out-Null
    return
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    $InputText | & py $Path | Out-Null
    return
  }

  throw 'No Python runtime found (python/py).'
}

$testRoot = Join-Path $PSScriptRoot '.tmp-bind-session'
if (Test-Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot | Out-Null

$sessionsRoot = Join-Path $testRoot '.ralph-sessions'
New-Item -ItemType Directory -Path $sessionsRoot | Out-Null

$ralphSessionId = '260225-120000'
$sessionPath = Join-Path $sessionsRoot $ralphSessionId
New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
Set-Content -Path (Join-Path $sessionPath '.hook-enabled') -Value 'ralph-v2' -NoNewline -Encoding utf8

$payload = '{"hookEventName":"UserPromptSubmit","sessionId":"chat-001","prompt":"continue session 260225-120000"}'
$env:RALPH_HOOK_REPO_ROOT = $testRoot
Invoke-PythonScript -Path $scriptPath -InputText $payload
Remove-Item Env:RALPH_HOOK_REPO_ROOT

$bindingPath = Join-Path $sessionsRoot '.hook-bindings/chat-001.json'
if (-not (Test-Path $bindingPath)) { throw 'Expected binding file to be created' }

$bindingRaw = Get-Content -Path $bindingPath -Raw
if ($bindingRaw -notmatch '"ralph_session_id":"260225-120000"') { throw 'Expected mapped ralph_session_id in binding' }

Write-Host 'PASS: UserPromptSubmit binding test'
