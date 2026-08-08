<#
.SYNOPSIS
    Refresh the tools inventory (tools/inventory.yaml) grounded in the latest
    GitHub Copilot CLI.

.DESCRIPTION
    Gathers grounding signals and produces a drift report comparing the live
    Copilot CLI surface against the current tools/inventory.yaml.

    Steps:
      1. Capture CLI version (copilot version) and today's date.
      2. Run local introspection: copilot --help, copilot plugins list.
      3. Fetch the official CLI command reference (docs.github.com) and parse
         tool-availability signal points.
      4. Emit a drift report (JSON + human-readable) to the session or -ReportPath.
      5. Optionally apply mechanical metadata (cli_version, last_verified) with
         -ApplyMetadata.

    The script NEVER rewrites tool lists. Tool diffs are emitted for curated
    review. Only cli_version / last_verified are auto-applied with -ApplyMetadata.

    YAML parsing/diffing is delegated to Python (pyyaml), which is a workspace
    standard; the script only orchestrates the CLI/docs gathering.

.PARAMETER InventoryPath
    Path to the inventory YAML. Default: <repo>/tools/inventory.yaml.

.PARAMETER ReportPath
    Where to write the drift report. Default: <repo>/tools/inventory-drift-report.json
    (plus a .md sibling). Use -NoReport to skip file output.

.PARAMETER ApplyMetadata
    If set, update cli_version and last_verified in the inventory YAML in place
    (mechanical, safe). Tool list changes are never applied automatically.

.PARAMETER NoReport
    Skip writing report files; only print to the console.

.PARAMETER CliCommand
    The command used to invoke copilot. Default: "copilot". Override for test
    fixtures (e.g. a wrapper that echoes fixed output).

.EXAMPLE
    # Dry-run refresh: capture signals and write a drift report
    .\scripts\refresh-inventory.ps1

.EXAMPLE
    # Apply only metadata after reviewing the report
    .\scripts\refresh-inventory.ps1 -ApplyMetadata
#>
[CmdletBinding()]
param(
    [string]$InventoryPath,
    [string]$ReportPath,
    [switch]$ApplyMetadata,
    [switch]$NoReport,
    [string]$CliCommand = "copilot"
)

$ErrorActionPreference = "Stop"

# Resolve repo root (this script lives at .github/skills/<name>/scripts/ -> repo root)
$scriptDir = $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..\..")
if (-not $InventoryPath) {
    $InventoryPath = Join-Path $repoRoot "tools\inventory.yaml"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Get-CliOutput {
    param([string]$Arguments)
    Write-Host "[local] $CliCommand $Arguments" -ForegroundColor DarkGray
    try {
        $out = & $CliCommand $Arguments 2>&1 | Out-String
        return $out.Trim()
    }
    catch {
        Write-Warning "Could not run '$CliCommand $Arguments': $($_.Exception.Message)"
        return ""
    }
}

# 1. CLI version + date
Write-Section "1. CLI version and date"
$versionRaw = Get-CliOutput -Arguments "version"
$versionMatch = [regex]::Match($versionRaw, "GitHub Copilot CLI\s+([0-9][0-9a-zA-Z.\-]*)")
$cliVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value.Trim() } else { "" }
$today = Get-Date -Format "yyyy-MM-dd"
Write-Host "cli_version   : $cliVersion"
Write-Host "last_verified : $today"
if (-not $cliVersion) {
    Write-Warning "Could not detect a version from 'copilot version'. The report will use an empty cli_version."
}

# 2. Local introspection
Write-Section "2. Local CLI introspection"
$helpText = Get-CliOutput -Arguments "--help"
$pluginsText = Get-CliOutput -Arguments "plugins list"

# 3. Official docs fetch
Write-Section "3. Official docs (web)"
$commandRefUrl = "https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference"
$docsBody = ""
$docsError = ""
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    try {
        $docsBody = (& curl.exe -sL $commandRefUrl) -join "`n"
        Write-Host "[docs] fetched $($docsBody.Length) chars from $commandRefUrl"
    }
    catch {
        $docsError = $_.Exception.Message
        Write-Warning "Docs fetch failed: $docsError"
    }
}
else {
    $docsError = "curl.exe not available"
    Write-Warning "curl.exe not available; skipping docs fetch."
}

# 4. Build signals object and pass to the Python diff helper
Write-Section "4. Drift diff vs inventory"
if (-not (Test-Path $InventoryPath)) {
    throw "Inventory not found: $InventoryPath"
}

$signals = [ordered]@{
    cli_version   = $cliVersion
    last_verified = $today
    help_text     = $helpText
    plugins_text  = $pluginsText
    docs_text     = $docsBody
    docs_error    = $docsError
    # Known concrete CLI built-in names accepted by --available-tools / --excluded-tools
    known_concrete_tools = @(
        "bash", "powershell", "read_bash", "read_powershell", "write_bash", "write_powershell",
        "stop_bash", "stop_powershell", "list_bash", "list_powershell",
        "view", "create", "edit", "apply_patch",
        "grep", "rg", "glob", "web_fetch",
        "task", "read_agent", "list_agents",
        "skill", "ask_user", "report_intent", "show_file", "fetch_copilot_cli_documentation",
        "update_todo", "store_memory", "task_complete", "exit_plan_mode", "sql", "lsp"
    )
    # MCP namespace tokens to detect in the grounding text
    known_mcp_namespaces = @(
        "github-mcp-server", "playwright", "microsoftdocs", "deepwiki",
        "context7", "brave_web_search", "mcp_docker"
    )
}

$signalsJson = $signals | ConvertTo-Json -Depth 6

# Inline Python: parse inventory + signals, emit drift JSON on stdout.
$pythonScript = @'
import json, re, sys

def main():
    signals = json.loads(sys.stdin.read())
    inventory_path = sys.argv[1] if len(sys.argv) > 1 else ""

    import yaml
    with open(inventory_path, encoding="utf-8") as fh:
        inv = yaml.safe_load(fh)

    haystack = (signals.get("help_text", "") + "\n" +
                signals.get("docs_text", "") + "\n" +
                signals.get("plugins_text", ""))

    seen_concrete = [t for t in signals.get("known_concrete_tools", [])
                     if re.search(re.escape(t), haystack)]

    seen_mcp = [ns for ns in signals.get("known_mcp_namespaces", [])
                if re.search(re.escape(ns), haystack)]

    inv_cli = set()
    for tool in inv.get("tools", []):
        for name in tool.get("cli", []) or []:
            if name and name != "runtime-dependent":
                inv_cli.add(name)

    seen_set = set(seen_concrete)
    # HIGH-CONFIDENCE: a tool name observed in grounding that is not in the
    # inventory is a candidate addition.
    additions = sorted(seen_set - inv_cli)

    # LOW-CONFIDENCE: a tool in the inventory not seen in the grounding scan.
    # Absence from a docs HTML page or from --help (which lists flags, not
    # tools) does NOT prove removal. Report as informational only; never
    # auto-delete based on this.
    not_confirmed = sorted(inv_cli - seen_set)

    report = {
        "cli_version": signals.get("cli_version", ""),
        "last_verified": signals.get("last_verified", ""),
        "docs_error": signals.get("docs_error", ""),
        "inventory_tools": [t["id"] for t in inv.get("tools", [])],
        "inventory_cli_names": sorted(inv_cli),
        "seen_concrete": sorted(seen_set),
        "seen_mcp_namespaces": seen_mcp,
        "additions": additions,
        "not_confirmed": not_confirmed,
    }
    json.dump(report, sys.stdout, indent=2)

if __name__ == "__main__":
    main()
'@

$driftJson = $signalsJson | python3 -c $pythonScript $InventoryPath
if ($LASTEXITCODE -ne 0) {
    throw "Python drift-diff helper failed with exit code $LASTEXITCODE"
}
$drift = $driftJson | ConvertFrom-Json

Write-Host ""
if ($drift.additions.Count -eq 0) {
    Write-Host "No high-confidence additions detected between grounding signals and the inventory." -ForegroundColor Green
}
else {
    Write-Host "Proposed additions : $($drift.additions -join ', ')" -ForegroundColor Yellow
    Write-Host "Review these before editing tools/inventory.yaml (curated, not auto-applied)." -ForegroundColor Yellow
}
if ($drift.not_confirmed.Count -gt 0) {
    Write-Host ""
    Write-Host "Not confirmed in grounding (informational, DO NOT auto-delete): $($drift.not_confirmed -join ', ')" -ForegroundColor DarkGray
    Write-Host "Absence from the docs page / --help does not prove removal. Verify manually before any deletion." -ForegroundColor DarkGray
}

# 5. Optional metadata apply
if ($ApplyMetadata) {
    Write-Section "5. Applying metadata (cli_version / last_verified)"
    $content = [System.IO.File]::ReadAllText($InventoryPath)

    # Single-quoted patterns: PowerShell does NOT use backslash escapes, so use
    # single quotes for regex literals containing double quotes.
    $patternLastVerified = 'last_verified: "[^"]*"'
    $patternCliVersion = 'cli_version: "[^"]*"'
    $replacementLastVerified = 'last_verified: "' + $today + '"'
    $replacementCliVersion = 'cli_version: "' + $cliVersion + '"'

    $newContent = [regex]::Replace($content, $patternLastVerified, $replacementLastVerified)
    $newContent = [regex]::Replace($newContent, $patternCliVersion, $replacementCliVersion)

    if ($newContent -ne $content) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($InventoryPath, $newContent, $utf8NoBom)
        Write-Host "Updated cli_version -> $cliVersion and last_verified -> $today in $InventoryPath" -ForegroundColor Green
    }
    else {
        Write-Host "Metadata already current; no changes applied." -ForegroundColor Green
    }
}

# 6. Report output
if (-not $NoReport) {
    if (-not $ReportPath) {
        $ReportPath = Join-Path $repoRoot "tools\inventory-drift-report.json"
    }
    $drift | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportPath -Encoding utf8
    $mdPath = [System.IO.Path]::ChangeExtension($ReportPath, ".md")
    $md = @"
# Tools Inventory Drift Report

- Generated: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
- CLI version: $($drift.cli_version)
- Proposed additions: $($drift.additions -join ', ')
- Not confirmed in grounding (informational): $($drift.not_confirmed -join ', ')
- Docs fetch error: $($drift.docs_error)

See $(Split-Path $ReportPath -Leaf) for machine-readable output.
"@
    Set-Content -Path $mdPath -Value $md -Encoding utf8
    Write-Host ""
    Write-Host "Report written: $ReportPath" -ForegroundColor Green
    Write-Host "               $mdPath" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "DRIFT SUMMARY (JSON):" -ForegroundColor Cyan
    $drift | ConvertTo-Json -Depth 6
}
