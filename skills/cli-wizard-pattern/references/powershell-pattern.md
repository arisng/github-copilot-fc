# PowerShell / Taskfile Wizard Pattern

Concrete, tested implementation of the [principles in SKILL.md](../SKILL.md).
All code examples use generic placeholder names — adapt to your own scripts.

## 1. Opt-in parameter block

Add an interactive switch in its own parameter set so it never collides with the
existing identification arguments. Keep existing required parameters reachable
when the flag is absent — do not mark them mandatory in a set that the flag
shares.

```powershell
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByPath')]
param(
    [Parameter(ParameterSetName = 'ByPath')]
    [string]$TargetPath,

    [Parameter(ParameterSetName = 'ByName')]
    [string]$Name,

    [Parameter(ParameterSetName = 'Interactive')]
    [alias('i')]
    [switch]$Interactive,

    [string]$Optional = 'default-value'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
```

Run the wizard, then fall through to the unchanged core logic:

```powershell
if ($Interactive) {
    Read-InteractiveWizard
}

# ...existing non-interactive resolution and execution...
```

## 2. Numbered selection menu

The workhorse. Renders a numbered list, loops until the selection is valid,
supports a quit token. Reuse for every enumerable parameter.

```powershell
function Show-NumberedMenu {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$ItemNoun = 'option',
        [bool]$AllowQuit = $true
    )

    if (-not $Options -or $Options.Count -eq 0) {
        Write-Error "No $ItemNoun values available."
        exit 1
    }

    Write-Host "`n    $Title" -ForegroundColor Cyan
    Write-Host "    ──────────────────────────────────────────" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "      [$($i + 1)] " -ForegroundColor Yellow -NoNewline
        Write-Host $Options[$i]
    }
    Write-Host "    ──────────────────────────────────────────" -ForegroundColor DarkGray

    $quitHint = if ($AllowQuit) { ", or 'q' to quit" } else { '' }
    while ($true) {
        $reply = Read-Host "    Select $ItemNoun (1-$($Options.Count)$quitHint)"
        if ($AllowQuit -and $reply -eq 'q') {
            Write-Host "`n  Cancelled." -ForegroundColor Yellow
            exit 0
        }
        $parsed = 0
        if ([int]::TryParse($reply, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $Options.Count) {
            return $Options[$parsed - 1]
        }
        Write-Host "    Invalid selection. Enter a number between 1 and $($Options.Count)." -ForegroundColor Red
    }
}
```

Add an explicit skip entry when an enumerable value may legitimately be absent:

```powershell
function Show-OptionalMenu {
    param([string]$Title, [string[]]$Options, [string]$ItemNoun)

    $withSkip = @($Options) + @('(skip)')
    return Show-NumberedMenu -Title $Title -Options $withSkip -ItemNoun $ItemNoun
}
# Caller: interpret '(skip)' as "no value".
```

## 3. Yes/no selection

Binary choices render as a numbered menu, not a `y/n` prompt.

```powershell
function Get-YesNoSelection {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    $defaultLabel = if ($Default) { 'Yes' } else { 'No' }
    Write-Host "    1. Yes" -ForegroundColor Cyan
    Write-Host "    2. No" -ForegroundColor Cyan
    while ($true) {
        $reply = Read-Host "    $Prompt (1-2, default: $defaultLabel)"
        if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
        if ($reply -eq '1') { return $true }
        if ($reply -eq '2') { return $false }
        Write-Host "    Invalid selection. Enter 1 or 2." -ForegroundColor Red
    }
}
```

## 4. Array-safe discovery

A command that returns one result yields a scalar in PowerShell, so `.Count`
throws. Wrap every discovery call in `@()` so the result is always an array.

```powershell
# WRONG — .Count fails when a single branch exists.
$branches = git branch --format='%(refname:short)'

# RIGHT — always an array.
$branches = @(git branch --format='%(refname:short)' 2>$null |
    Where-Object { $_ -ne 'HEAD' } |
    Select-Object -Unique)

$remotes = @(git remote 2>$null)
```

## 5. Wizard skeleton with confirmation

Gather values into script-scoped variables, print a summary, then confirm.
Assigning to `$script:ParamName` reaches the same parameter the core path reads.

```powershell
function Read-InteractiveWizard {
    Write-Host "`n╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          Operation Wizard (interactive)       ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan

    # Step 1 — enumerate and select
    Write-Host "`n  Step 1 — Select the target" -ForegroundColor Yellow
    $candidates = @(Get-SomethingDiscovered)
    $script:TargetPath = Show-NumberedMenu -Title 'Available targets:' -Options $candidates -ItemNoun 'target'
    Write-Host "  → Selected: $script:TargetPath" -ForegroundColor Green

    # Step 2 — optional enumerable with skip
    Write-Host "`n  Step 2 — Choose an optional scope" -ForegroundColor Yellow
    $choice = Show-OptionalMenu -Title 'Available scopes:' -Options @(Get-Scopes) -ItemNoun 'scope'
    $script:Optional = if ($choice -eq '(skip)') { '' } else { $choice }

    # Summary + confirmation
    Write-Host "`n  ── Summary ──────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "    Target:   $script:TargetPath"
    Write-Host "    Optional: $(if ($script:Optional) { $script:Optional } else { '(skip)' })"
    Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray

    if (-not (Get-YesNoSelection 'Proceed?' $false)) {
        Write-Host "`n  Cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ''
}
```

## 6. Conditional prompt from discovered state

Prompt only when the discovered state warrants it, so the wizard stays short in
the common case.

```powershell
$isDirty = [bool](git -C $TargetPath status --porcelain 2>$null)
$script:SkipCheck = $false
if ($isDirty) {
    Write-Host "`n  ⚠ Target has uncommitted changes." -ForegroundColor Yellow
    $script:SkipCheck = Get-YesNoSelection 'Skip the clean check and proceed anyway?' $false
    if (-not $script:SkipCheck) {
        Write-Host "`n  Resolve changes, then re-run. Cancelled." -ForegroundColor Yellow
        exit 0
    }
}
```

## 7. Taskfile wiring

Forward the flag conditionally. Remove a forced non-interactive shell mode for
the interactive invocation so prompts can reach the terminal.

```yaml
  cmd:do:
    desc: "Description"
    vars:
      INTERACTIVE: '{{.INTERACTIVE | default "false"}}'
    cmds:
      - pwsh -Command "& { $script = Join-Path $PSScriptRoot 'scripts/my-script.ps1'; & $script {{if eq .INTERACTIVE "true"}}-Interactive{{end}} -TargetPath '{{.TARGET}}' }"
```

When `INTERACTIVE` is `"true"`, `-Interactive` is forwarded and the wizard
launches. When `"false"` (or absent), the flag is omitted and the command runs
non-interactively.

## 8. Syntax validation

Before committing changes to the wizard or parameter block, verify the file
parses cleanly:

```powershell
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    'path/to/your-script.ps1', [ref]$null, [ref]$errors)
if ($errors) { $errors | ForEach-Object { Write-Error $_.Message } ; exit 1 }
```

And confirm the parameter sets render correctly:

```powershell
# Non-interactive help shows the flag in the Interactive set only:
(Help Your-Script -Parameter Interactive).Synopsis
# → "Add an interactive wizard..."
```
