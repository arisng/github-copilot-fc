param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir 'ralph-v2-bind-session-from-input.py'

try {
    if (-not (Test-Path $pythonScript)) {
        exit 0
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        [Console]::In.ReadToEnd() | & python $pythonScript | Out-Null
        exit 0
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        [Console]::In.ReadToEnd() | & py $pythonScript | Out-Null
        exit 0
    }

    exit 0
}
catch {
    exit 0
}
