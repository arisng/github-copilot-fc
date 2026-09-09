# export-corpus.ps1 — assemble the machina-simulator replay corpus from kept waza
# task workspaces and run the extension's OWN aggregate replay gate over it.
#
# The eval runs with `waza run --keep-workspace`, so each task's temp workspace
# (containing its produced runs/ dir with machine.json + ledger.jsonl) is
# retained on disk. This script copies every produced run into
# evals/machina-simulator/results/corpus/<task>/<runid>/ (gitignored), then
# executes the simulator extension's `scripts/replay-all.mjs` against the whole
# corpus — the batch driver the extension itself uses — and prints the
# MACHINA_RUN_ROOTS value + `/machina-simulator` opening instructions.
#
# Usage:
#   pwsh -File scripts/export-corpus.ps1 -Workspace <waza-ws-1> [-Workspace <waza-ws-2> ...]
#
# Flags:
#   -Workspace   absolute path to a kept waza task workspace (repeatable)
#   -TaskTags    optional friendly family names in the same order (defaults to
#                the workspace directory name)
#   -ExpectedStuck  optional expected STUCK (blocked-final) count across the
#                corpus (passed to replay-all as MACHINA_EXPECTED_STUCK)
#   -OutRoot     corpus parent dir (defaults to .\results\corpus)

param(
    [Parameter(Mandatory = $false)]
    [string[]]$Workspace = @(),
    [string[]]$TaskTags = @(),
    [int]$ExpectedStuck = -1,
    [string]$OutRoot = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$corpusRoot = if ($OutRoot) { $OutRoot } else { Join-Path $repoRoot "evals\machina-simulator\results\corpus" }
$replayAll = Join-Path $repoRoot "copilot-extensions\machina-simulator\scripts\replay-all.mjs"

if (-not $Workspace) {
    Write-Host "No -Workspace paths provided. Add each kept waza task workspace:" -ForegroundColor Yellow
    Write-Host "  pwsh -File scripts/export-corpus.ps1 -Workspace C:\path\waza-1 -Workspace C:\path\waza-2" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $replayAll)) {
    Write-Host "FATAL: replay-all.mjs not found at $replayAll" -ForegroundColor Red
    exit 2
}

if (Test-Path $corpusRoot) { Remove-Item $corpusRoot -Recurse -Force }
New-Item -ItemType Directory -Force $corpusRoot | Out-Null

$tagIndex = 0
$runsCopied = 0
foreach ($ws in $Workspace) {
    if (-not (Test-Path $ws)) {
        Write-Host "WARN: workspace $ws does not exist - skipping" -ForegroundColor Yellow
        continue
    }
    $tag = if ($TaskTags.Count -gt $tagIndex -and $TaskTags[$tagIndex]) { $TaskTags[$tagIndex] } else { (Split-Path $ws -Leaf) }
    $tagIndex++
    # a run dir = any dir directly containing ledger.jsonl
    $runDirs = Get-ChildItem $ws -Recurse -Filter "ledger.jsonl" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique
    $copiedAny = $false
    foreach ($rd in $runDirs) {
        $runName = Split-Path $rd -Leaf
        $dest = Join-Path $corpusRoot "$tag\$runName"
            New-Item -ItemType Directory -Force $dest | Out-Null
            Copy-Item (Join-Path $rd "*") $dest -Force
        $runsCopied++
        $copiedAny = $true
    }
    if ($copiedAny) {
        Write-Host "  copied $($runDirs.Count) run(s) from $ws -> $tag"
    } else {
        Write-Host "WARN: no runs found in $ws" -ForegroundColor Yellow
    }
}

if ($runsCopied -eq 0) {
    Write-Host "FATAL: no runs copied - nothing to replay." -ForegroundColor Red
    exit 3
}

Write-Host ""
Write-Host "=== Aggregate replay gate over the exported corpus ($corpusRoot) ===" -ForegroundColor Cyan
$env:MACHINA_RUN_ROOTS = $corpusRoot
if ($ExpectedStuck -ge 0) { $env:MACHINA_EXPECTED_STUCK = "$ExpectedStuck" }
try {
    node $replayAll
    $gateCode = $LASTEXITCODE
} finally {
    Remove-Item Env:MACHINA_RUN_ROOTS -ErrorAction SilentlyContinue
    Remove-Item Env:MACHINA_EXPECTED_STUCK -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Open the machina-simulator to audit these runs ===" -ForegroundColor Cyan
Write-Host "Set the run root, then issue /machina-simulator in a Copilot CLI session:"
Write-Host "   `$env:MACHINA_RUN_ROOTS = '$corpusRoot'" -ForegroundColor Green
Write-Host "   /machina-simulator" -ForegroundColor Green
Write-Host "The Runs tab lists every exported run ($runsCopied); click one to replay it"
Write-Host "with the integrity verdict, terminal disposition, blocked records and nested badges."

exit $gateCode