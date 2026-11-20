<#
.SYNOPSIS
    Cross-file consistency checks for the Copilot FC factory (plan W1.2 / W2.3 / W3.1).
.DESCRIPTION
    Validates relationships that per-file schema validation cannot see:
      - plugin dir name == manifest name; every component path resolves;
        no -beta identity in source; no duplicate plugin names (WARN)
      - skills/<name>/ dir == frontmatter name (FAIL); dirs without SKILL.md
        (WARN); SKILL.md body > 500 lines (WARN, ratchet-pending per W5.2)
      - agent frontmatter name uniqueness (FAIL); EMBED markers resolve to
        existing instructions/ files (FAIL); -beta agent sources (FAIL)
      - marketplace parity via the shipped verify-version-sync.py when
        .github/plugin/marketplace.json exists (B3: absorb, don't rebuild)
      - schema/frontmatter validation via validate-manifests.py (the
        jsonschema engine: plugin/skill/marketplace schemas + instruction
        frontmatter description/applyTo)

    Severity policy (plan Sequencing "day-one red guard"): structural rules
    FAIL and are green on today's tree; content budgets WARN-first until the
    shrink-only ratchet (W5.2) lands.
    Exits 0 with warnings, 1 on any FAIL, 2 on missing tooling (python3).
.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/check-consistency.ps1
#>
[CmdletBinding()]
param(
    # Sandbox override: point the checker at another repo root (diagnosis).
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}
$repoRoot = (Resolve-Path $RepoRoot).Path
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([ValidateSet('PASS', 'WARN', 'FAIL', 'SKIP')][string]$Level, [string]$Area, [string]$Detail)
    $findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Detail = $Detail })
}

function Get-VisibleChildDirectory {
    param([string]$Path)
    Get-ChildItem -Path $Path -Directory -Force -ErrorAction Stop |
        Where-Object { $_.Name -notlike '.*' }
}

# --- Schema + frontmatter engine (python3 is a hard gate dependency) --------
function Get-RenderedDescriptionLength {
    # Approximates the rendered menu description length from raw frontmatter
    # without a YAML parser: only the region before `metadata:` is considered,
    # then folded (>-), quoted, or plain scalars are measured.
    param([string]$Frontmatter)

    $descRegion = ($Frontmatter -split '(?m)^metadata:')[0]
    if ($descRegion -match '(?m)^description:\s*>-?\s*$') {
        $folded = [regex]::Match($descRegion, '(?ms)^description:\s*>-?[ \t]*\r?\n((?:[ \t]+\S.*\r?\n?)+)')
        if ($folded.Success) {
            $words = @($folded.Groups[1].Value -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            return (($words -join ' ').Length)
        }
        return 0
    }
    if ($descRegion -match '(?m)^description:\s*[''"](.*)[''"]\s*$') { return $Matches[1].Length }
    if ($descRegion -match '(?m)^description:\s*(\S.*)$') { return $Matches[1].Trim().Length }
    return 0
}

$validator = Join-Path $repoRoot 'scripts' 'workspace' 'validate-manifests.py'
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Output '[FAIL] tooling: python3 not found on PATH (required by validate-manifests.py)'
    exit 2
}
$engineOutput = & python3 $validator 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $engineOutput) {
        if ($line -match '^\[(FAIL|WARN|PASS|SKIP)\] (.*)$') {
            Add-Finding -Level ($Matches[1]) -Area 'schema' -Detail $Matches[2]
        }
        else {
            Add-Finding -Level 'FAIL' -Area 'schema' -Detail "$line"
        }
    }
}
else {
    # Success path: PASS detail collapses to the summary line, but WARN lines
    # (docs-index coverage backlog, etc.) must stay visible to the gate.
    foreach ($line in $engineOutput) {
        if ($line -match '^\[WARN\] (.*)$') {
            Add-Finding -Level 'WARN' -Area 'schema' -Detail $Matches[1]
        }
    }
    Add-Finding -Level 'PASS' -Area 'schema' -Detail ($engineOutput | Select-Object -Last 1)
}

# --- Plugin manifests: identity, paths, beta, duplicates --------------------
$pluginNames = @{}
Get-ChildItem -Path (Join-Path $repoRoot 'plugins') -Directory -Force |
    Where-Object { $_.Name -notlike '.*' } | ForEach-Object {
        $runtimeDir = $_
        Get-VisibleChildDirectory -Path $runtimeDir.FullName | ForEach-Object {
            $pluginDir = $_
            $manifestPath = Join-Path $pluginDir.FullName 'plugin.json'
            if (-not (Test-Path $manifestPath)) {
                Add-Finding -Level 'FAIL' -Area 'plugin' -Detail "$($runtimeDir.Name)/$($pluginDir.Name): missing plugin.json"
                return
            }
            try {
                $manifest = Get-Content -Path $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
            }
            catch {
                Add-Finding -Level 'FAIL' -Area 'plugin' -Detail "$($pluginDir.Name)/plugin.json: unreadable JSON ($($_.Exception.Message))"
                return
            }
            if ($manifest.name -ne $pluginDir.Name) {
                Add-Finding -Level 'FAIL' -Area 'plugin' -Detail "$($pluginDir.Name): manifest name '$($manifest.name)' != directory name"
            }
            if ("$($manifest.name)" -like '*-beta*') {
                Add-Finding -Level 'FAIL' -Area 'plugin' -Detail "$($pluginDir.Name): '-beta' identity in source manifest (beta identity is bundle-only)"
            }
            if ($pluginNames.ContainsKey("$($manifest.name)")) {
                Add-Finding -Level 'WARN' -Area 'plugin' -Detail "plugin name '$($manifest.name)' appears in multiple runtimes (cli/vscode)"
            }
            else { $pluginNames["$($manifest.name)"] = $runtimeDir.Name }

            foreach ($field in @('agents', 'skills', 'commands', 'hooks', 'mcpServers', 'lspServers')) {
                $values = $manifest.$field
                if ($null -eq $values) { continue }
                foreach ($value in @($values)) {
                    if (-not ("$value" -is [string]) -or "$value" -eq '') { continue }
                    $target = Join-Path $pluginDir.FullName "$value"
                    if (-not (Test-Path -LiteralPath $target)) {
                        Add-Finding -Level 'FAIL' -Area 'plugin' -Detail "$($pluginDir.Name): component path does not resolve: $field -> $value"
                    }
                }
            }
        }
    }
if (-not ($findings | Where-Object { $_.Area -eq 'plugin' -and $_.Level -eq 'FAIL' })) {
    Add-Finding -Level 'PASS' -Area 'plugin' -Detail "$($pluginNames.Count) plugin manifest(s): identity, component paths, beta scan clean"
}

# --- Skills: dir<->name, structure, body budget -----------------------------
$skillDir = Join-Path $repoRoot 'skills'
$skillNames = @{}
$skillFails = 0
$skillWarns = 0
$script:menuSize = 0
Get-VisibleChildDirectory -Path $skillDir | ForEach-Object {
    $dir = $_
    $skillFile = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path $skillFile)) {
        Add-Finding -Level 'WARN' -Area 'skill' -Detail "$($dir.Name): directory has no SKILL.md (not a skill; remove, archive, or add one)"
        $script:skillWarns++
        return
    }
    $text = Get-Content -Path $skillFile -Raw -Encoding utf8
    if ($text -match '(?m)^name:\s*["'']?([A-Za-z0-9._-]+)') { $frontName = $Matches[1] }
    else { $frontName = $null }
    if ($null -eq $frontName) {
        Add-Finding -Level 'FAIL' -Area 'skill' -Detail "$($dir.Name)/SKILL.md: no top-level name: in frontmatter"
        $script:skillFails++
    }
    elseif ($frontName -ne $dir.Name) {
        Add-Finding -Level 'FAIL' -Area 'skill' -Detail "$($dir.Name): frontmatter name '$frontName' != directory name"
        $script:skillFails++
    }
    if ($skillNames.ContainsKey("$frontName")) {
        Add-Finding -Level 'FAIL' -Area 'skill' -Detail "duplicate skill name '$frontName' ($($skillNames[$frontName]) and $($dir.Name))"
        $script:skillFails++
    }
    elseif ($frontName) { $skillNames["$frontName"] = $dir.Name }
    $lineCount = ($text -split "`n").Count
    if ($lineCount -gt 500) {
        Add-Finding -Level 'WARN' -Area 'skill' -Detail "$($dir.Name)/SKILL.md: $lineCount lines > 500-line body budget (move detail to references/)"
        $script:skillWarns++
    }
    if ($frontName) {
        $fmText = ''
        $fmMatch = [regex]::Match($text, '\A---\r?\n(.*?)\r?\n---', 'Singleline')
        if ($fmMatch.Success) { $fmText = $fmMatch.Groups[1].Value }
        $script:menuSize += $frontName.Length + (Get-RenderedDescriptionLength -Frontmatter $fmText) + 8
    }
}
# Rendered skill-menu budget (plan W2.7): measured 27,339 chars across 51
# skills on 2026-11-19; cap set at 30,000 with headroom (dotnet/skills uses a
# 15,000 cap for their menu — recalibrated for this factory's descriptions).
$skillMenuBudget = 30000
if ($script:menuSize -gt $skillMenuBudget) {
    Add-Finding -Level 'WARN' -Area 'skill' -Detail "rendered skill-menu size $($script:menuSize) chars exceeds budget $skillMenuBudget (shrink descriptions; router discipline in skills/README.md)"
    $script:skillWarns++
}
if ($skillFails -eq 0) {
    Add-Finding -Level 'PASS' -Area 'skill' -Detail "$($skillNames.Count) skill(s): dir<->name and uniqueness clean; menu $script:menuSize/$skillMenuBudget chars$($skillWarns -gt 0 ? '; ' + $skillWarns + ' warning(s)' : '')"
}

# --- Agents: uniqueness, EMBED resolution, beta sources ---------------------
$agentNames = @{}
$agentFiles = @()
foreach ($base in @((Join-Path $repoRoot 'agents'), (Join-Path $repoRoot 'plugins'))) {
    if (Test-Path $base) {
        $agentFiles += Get-ChildItem -Path $base -Recurse -Filter '*.agent.md' -File -Force |
            Where-Object { $_.FullName -notmatch '\\\.[^\\]+\\' }
    }
}
$agentFails = 0
foreach ($file in $agentFiles) {
    $text = Get-Content -Path $file.FullName -Raw -Encoding utf8
    $shortName = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    if ($file.Name -like '*-beta*') {
        Add-Finding -Level 'FAIL' -Area 'agent' -Detail "${shortName}: '-beta' source agent (beta identity is bundle-only)"
        $script:agentFails++
    }
    $name = if ($text -match '(?m)^name:\s*["'']?([A-Za-z0-9._-]+)') { $Matches[1] } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
    if ($agentNames.ContainsKey($name)) {
        Add-Finding -Level 'FAIL' -Area 'agent' -Detail "duplicate agent name '$name' ($($agentNames[$name]) and $shortName)"
        $script:agentFails++
    }
    else { $agentNames[$name] = $shortName }
    foreach ($match in [regex]::Matches($text, '<!--\s*EMBED:\s*(\S+)\s*-->')) {
        $target = $match.Groups[1].Value
        $instructionPath = Join-Path $repoRoot 'instructions' $target
        if (-not (Test-Path -LiteralPath $instructionPath)) {
            Add-Finding -Level 'FAIL' -Area 'agent' -Detail "${shortName}: EMBED marker '$target' does not resolve to instructions/$target"
            $script:agentFails++
        }
    }
}
if ($agentFails -eq 0) {
    Add-Finding -Level 'PASS' -Area 'agent' -Detail "$($agentFiles.Count) agent source(s): name uniqueness, EMBED resolution, beta scan clean"
}

# --- Generated skills catalog freshness (plan W2.4) -----------------------
$catalogScript = Join-Path $repoRoot 'scripts' 'workspace' 'generate-skills-catalog.py'
if (-not (Test-Path $catalogScript)) {
    Add-Finding -Level 'FAIL' -Area 'catalog' -Detail "missing $catalogScript"
}
else {
    $catalogOut = & python3 $catalogScript --check 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        Add-Finding -Level 'FAIL' -Area 'catalog' -Detail (($catalogOut -join ' | ') -replace '\s+', ' ')
    }
    else {
        Add-Finding -Level 'PASS' -Area 'catalog' -Detail (($catalogOut -join ' | ') -replace '^\[(PASS|FAIL)\] ', '')
    }
}

# --- Marketplace parity (absorb shipped verifier, B3) -----------------------
$marketplace = Join-Path $repoRoot '.github' 'plugin' 'marketplace.json'
$verifier = Join-Path $repoRoot 'skills' 'copilot-plugin-builder' 'scripts' 'verify-version-sync.py'
if (-not (Test-Path $marketplace)) {
    Add-Finding -Level 'SKIP' -Area 'marketplace' -Detail 'marketplace.json not present (no live plugins; recreate with the next plugin release; verifier wired then)'
}
elseif (-not (Test-Path $verifier)) {
    Add-Finding -Level 'FAIL' -Area 'marketplace' -Detail "verify-version-sync.py missing at $verifier"
}
else {
    $parityOutput = & python3 $verifier 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        Add-Finding -Level 'FAIL' -Area 'marketplace' -Detail (($parityOutput -join ' | ') -replace '\s+', ' ')
    }
    else {
        Add-Finding -Level 'PASS' -Area 'marketplace' -Detail 'verify-version-sync: marketplace <-> manifest parity clean'
    }
}

# --- Report -----------------------------------------------------------------
foreach ($f in $findings) {
    Write-Output "[$($f.Level)] $($f.Area): $($f.Detail)"
}
$failTotal = @($findings | Where-Object Level -eq 'FAIL').Count
$warnTotal = @($findings | Where-Object Level -eq 'WARN').Count
Write-Output "check-consistency: $failTotal FAIL, $warnTotal WARN, $($findings.Count) finding(s) total"
if ($failTotal -gt 0) { exit 1 }
exit 0
