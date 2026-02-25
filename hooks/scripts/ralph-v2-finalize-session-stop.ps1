param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir 'ralph-v2-finalize-session-stop.py'

function Resolve-PythonCommand {
    foreach ($name in @('python', 'py')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $name
        }
    }
    return $null
}

try {
    if (Test-Path $pythonScript) {
        $pythonCmd = Resolve-PythonCommand
        if ($null -ne $pythonCmd) {
            if ($pythonCmd -eq 'py') {
                & py $pythonScript | Out-Null
            }
            else {
                & python $pythonScript | Out-Null
            }
        }
    }
    exit 0
}
catch {
    exit 0
}
