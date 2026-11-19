<#
.SYNOPSIS
    Regression test: a single changed .md must reach markdownlint as one path
    argument.

.DESCRIPTION
    Guards the scalar-splat bug (fixed in 828c9a2): `Test-MarkdownLint` built
    `$rel` from a pipeline, and a one-item pipeline returns a scalar string —
    splatting a string passes each character as a separate argument, so every
    push touching exactly one .md file linted the whole repo and failed.

    Runs workspace-check.ps1 dot-sourced (its main body is skipped for
    dot-sourced invocation), stubs `npx` on PATH to record its argv, and calls
    `Test-MarkdownLint -Files @('README.md')`.

.EXAMPLE
    pwsh -NoProfile -File scripts/test/workspace-check-lint.tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/workspace/workspace-check.ps1')

$stubDir = Join-Path ([System.IO.Path]::GetTempPath()) ('npx-stub-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stubDir | Out-Null
$log = Join-Path $stubDir 'npx-args.log'
$stub = Join-Path $stubDir 'npx.cmd'
@(
    '@echo off',
    'echo %*>>"%NPX_STUB_LOG%"',
    'exit /b 0'
) | Set-Content -Path $stub -Encoding ascii

$oldPath = $env:PATH
$oldLog = $env:NPX_STUB_LOG
$env:NPX_STUB_LOG = $log
$env:PATH = "$stubDir;$oldPath"

$failure = $null
try {
    $result = Test-MarkdownLint -Files @('README.md')

    $lines = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
    $lintLine = $lines |
        Where-Object { $_ -like '*markdownlint-cli2*' -and $_ -notlike '*--version*' } |
        Select-Object -Last 1

    if (-not $lintLine) {
        $failure = 'markdownlint invocation was never recorded'
    }
    elseif ($lintLine -notmatch 'markdownlint-cli2 README\.md\s*$') {
        $failure = "path did not arrive as one argument: [$lintLine]"
    }
    elseif ($result.Status -ne 'PASS') {
        $failure = "Test-MarkdownLint returned $($result.Status): $($result.Detail)"
    }
}
catch {
    $failure = "self-test crashed: $_"
}
finally {
    $env:PATH = $oldPath
    $env:NPX_STUB_LOG = $oldLog
    Remove-Item -Recurse -Force $stubDir -ErrorAction SilentlyContinue
}

if ($failure) {
    Write-Host "FAIL: $failure" -ForegroundColor Red
    exit 1
}
Write-Host 'PASS: single changed .md reached markdownlint as one path argument' -ForegroundColor Green
exit 0
