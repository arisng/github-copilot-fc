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
      - kebab-case directory names across every authored tree (FAIL; the
        mechanical naming rule moved here from instruction prose - retro
        candidate 4; file-name exceptions that toolchains own, such as
        pytest test_*.py and waza trigger_tests.yaml, stay prose)
      - issue-tracking tree-template.html must match the fingerprint in
        assets/tree-template.version.json (FAIL; an edit without a version
        bump would only surface in consumer repos at render time - retro
        2026-11-20)
      - steering files (.github/copilot-instructions.md, git-scope docs,
        AGENTS.md/CLAUDE.md/CODING_STANDARDS.md when present) must not name
        repo paths that do not exist (FAIL; wildcard paths checked at their
        directory part, documented-conditional paths excepted - retro
        2026-11-20)
      - shipped-claim issue docs (.issues, status Completed/Implemented/
        Done/resolved) must cite repo paths that exist; planned docs may
        name future paths and out-of-tree deliveries declare
        out-of-tree-commands: true (FAIL - retro 2026-11-21: a "Completed"
        issue doc sent an agent to run the never-existent
        scripts/workspace/run-command.ps1)

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

# --- Issue-tree template version integrity (retro 2026-11-20) ---------------
# The rendered view's version contract: assets/tree-template.version.json must
# fingerprint assets/tree-template.html. Without this gate a template edit that
# skips bump-tree-template-version.ps1 passes here and only fails in consumer
# repos at render time, when the fix has to travel through a skill release.
$tplLib = Join-Path $repoRoot 'skills' 'issue-tracking' 'scripts' 'template-version-lib.ps1'
$tplAsset = Join-Path $repoRoot 'skills' 'issue-tracking' 'assets' 'tree-template.html'
$tplVersionFile = Join-Path $repoRoot 'skills' 'issue-tracking' 'assets' 'tree-template.version.json'
if (-not (Test-Path $tplLib)) {
    Add-Finding -Level 'FAIL' -Area 'template' -Detail 'missing skills/issue-tracking/scripts/template-version-lib.ps1'
}
elseif (-not (Test-Path $tplAsset) -or -not (Test-Path $tplVersionFile)) {
    Add-Finding -Level 'FAIL' -Area 'template' -Detail 'issue-tracking template assets incomplete (assets/tree-template.html or assets/tree-template.version.json missing)'
}
else {
    . $tplLib
    $tplState = Get-TreeTemplateVersionState -Path $tplVersionFile
    if ($tplState.Error) {
        Add-Finding -Level 'FAIL' -Area 'template' -Detail $tplState.Error
    }
    else {
        $tplActual = Get-TreeTemplateSha256 -Path $tplAsset
        if ($tplActual -ne $tplState.Sha256) {
            Add-Finding -Level 'FAIL' -Area 'template' -Detail "skills/issue-tracking/assets/tree-template.html changed without a version bump (recorded v$($tplState.Version)) - run: pwsh skills/issue-tracking/scripts/bump-tree-template-version.ps1 -Version <new>"
        }
        else {
            Add-Finding -Level 'PASS' -Area 'template' -Detail "tree-template.html fingerprint matches recorded v$($tplState.Version)"
        }
    }
}

# --- Steering files: no references to retired repo paths (retro 2026-11-20) --
# The always-loaded workspace instructions once sent agents to a dispatcher
# removed weeks earlier (6d98e87); reconciling retired artifacts happened by
# hand twice (9c481f8, 566bc59), and a stale hook claim (retired by 4ec4c64)
# still survived in three files. Mechanical rule: every repo-root-relative
# path a steering file names must exist - wildcard paths are checked at their
# directory part, and documented-conditional paths are excepted. The next
# retirement fails here instead of shipping an instruction that costs every
# session a failed command.
$steeringFiles = @(
    '.github/copilot-instructions.md',
    '.github/git-scope-constitution.md',
    '.github/git-scope-inventory.md',
    'AGENTS.md',
    'CLAUDE.md',
    'CODING_STANDARDS.md'
) | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) }
# Named by design before it exists (conditional wording in the steering file).
$steeringOptional = @('.github/plugin/marketplace.json')
$steeringRoots = [System.Collections.Generic.List[string]]::new()
foreach ($entry in Get-ChildItem -LiteralPath $repoRoot -Force) {
    if ($entry.Name -eq '.git') { continue }
    $steeringRoots.Add($entry.Name)
}
# Retired top-level names stay matchable, so a reference to a whole removed
# directory still trips the rule instead of silently falling out of the scan.
foreach ($name in @('.docs')) { $steeringRoots.Add($name) }
$rootPattern = ($steeringRoots | Sort-Object -Unique | ForEach-Object { [regex]::Escape($_) }) -join '|'
$steeringRx = "(?<![A-Za-z0-9_./-])(?:$rootPattern)/[A-Za-z0-9._\\/-]*"
$steeringMissing = [System.Collections.Generic.List[string]]::new()
$steeringSeen = @{}
$steeringGlobs = 0
$steeringOptionalHits = 0
foreach ($file in $steeringFiles) {
    $text = [System.IO.File]::ReadAllText((Join-Path $repoRoot $file))
    foreach ($m in [regex]::Matches($text, $steeringRx)) {
        $nextChar = if ($m.Index + $m.Length -lt $text.Length) { $text[$m.Index + $m.Length] } else { ' ' }
        $isGlob = ($nextChar -eq '*' -or $nextChar -eq '?')
        if ($isGlob) {
            # Wildcard path: only its directory part is knowable.
            $check = $m.Value.Substring(0, $m.Value.LastIndexOf('/'))
        }
        else {
            $check = $m.Value.TrimEnd('/').TrimEnd('.', '-')
        }
        if ([string]::IsNullOrEmpty($check)) { continue }
        if ($steeringSeen.ContainsKey($check)) { continue }
        $steeringSeen[$check] = $true
        if ($isGlob) { $steeringGlobs++ }
        if ($check -in $steeringOptional) { $steeringOptionalHits++; continue }
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $check))) {
            $steeringMissing.Add("$file -> $check")
        }
    }
}
if ($steeringMissing.Count -gt 0) {
    foreach ($bad in $steeringMissing) {
        Add-Finding -Level 'FAIL' -Area 'steering' -Detail "retired or dangling path reference: $bad"
    }
}
else {
    $steeringSuffix = $steeringOptionalHits -gt 0 ? "; $steeringOptionalHits documented-conditional" : ''
    Add-Finding -Level 'PASS' -Area 'steering' -Detail "$($steeringSeen.Count) path reference(s) across $($steeringFiles.Count) steering file(s) resolve$steeringSuffix ($steeringGlobs wildcard-checked)"
}

# --- Interpreter mandate: `python3`, never `python` (retro 2026-11-27) -------
# The workspace mandate says "`python3`, never `python`" and the gate hard-requires
# it (`Get-Command python3` above: a missing python3 is a FAIL), yet nothing
# checked authored docs for the bare form. A session writing a new skill
# documented `python scripts/...` in 10 places; on a host where the two names
# resolve to different interpreters (here 3.14.7 vs 3.13.15) a reader's command
# runs a different environment than the gate verified. Mechanical rule: no
# invocation of a script may name the bare interpreter in any authored markdown.
# Bare `python -c` / `python -m` are caught by the same spelling test.
$pythonRx = '(?<![A-Za-z0-9_-])python(?!3)(?=\s+(?:--?[A-Za-z]+\s+)*(?:\.\.?/)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/?[A-Za-z0-9_.-]+\.py\b)'
$pythonOffenders = [System.Collections.Generic.List[string]]::new()
$pythonScanned = 0
foreach ($tree in @('skills', 'instructions', 'docs', '.github')) {
    $dir = Join-Path $repoRoot $tree
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($md in Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.md' -File -Force) {
        if ($md.FullName -match '[\\/](node_modules|\.archived|\.build)[\\/]') { continue }
        $pythonScanned++
        $lines = [System.IO.File]::ReadAllLines($md.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ([regex]::IsMatch($lines[$i], $pythonRx, 'None')) {
                $rel = $md.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
                $pythonOffenders.Add("${rel}:$($i + 1): $($lines[$i].Trim())")
            }
        }
    }
}
if ($pythonOffenders.Count -gt 0) {
    foreach ($bad in $pythonOffenders) {
        Add-Finding -Level 'FAIL' -Area 'interpreter' -Detail "uses bare 'python' (mandate: python3) - $bad"
    }
}
else {
    Add-Finding -Level 'PASS' -Area 'interpreter' -Detail "$pythonScanned authored markdown file(s) name only 'python3'"
}

# --- Issue-doc shipped-claim path citations (retro 2026-11-21) --------------
# .issues/*.md reads like instructions to a subagent: one ran the
# never-existent scripts/workspace/run-command.ps1 because a "Completed"
# issue doc still advertised it. Same mechanical rule as steering, scoped by
# claim - statuses that assert delivery must cite repo paths that exist;
# planned docs may name future paths, and work delivered outside this tree
# declares `out-of-tree-commands: true` in frontmatter.
$shippedStatuses = @('Completed', 'Implemented', 'Done', 'resolved')
$issueDocs = @(Get-ChildItem -Path (Join-Path $repoRoot '.issues') -Filter '*.md' -File -ErrorAction SilentlyContinue)
$issueMissing = [System.Collections.Generic.List[string]]::new()
$issueScanned = 0
$issueExempt = 0
$issueSeen = @{}
foreach ($doc in $issueDocs) {
    $text = [System.IO.File]::ReadAllText($doc.FullName)
    $status = ''
    if ($text -match '(?m)^status:[ \t]*(\S+)') { $status = $Matches[1] }
    if ($shippedStatuses -notcontains $status) { continue }
    if ($text -match '(?m)^out-of-tree-commands:[ \t]*true[ \t]*\r?$') { $issueExempt++; continue }
    $issueScanned++
    foreach ($m in [regex]::Matches($text, $steeringRx)) {
        $nextChar = if ($m.Index + $m.Length -lt $text.Length) { $text[$m.Index + $m.Length] } else { ' ' }
        $isGlob = ($nextChar -eq '*' -or $nextChar -eq '?')
        if ($isGlob) {
            $check = $m.Value.Substring(0, $m.Value.LastIndexOf('/'))
        }
        else {
            $check = $m.Value.TrimEnd('/').TrimEnd('.', '-')
        }
        if ([string]::IsNullOrEmpty($check)) { continue }
        $seenKey = "$($doc.Name)|$check"
        if ($issueSeen.ContainsKey($seenKey)) { continue }
        $issueSeen[$seenKey] = $true
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $check))) {
            $issueMissing.Add("$($doc.Name) -> $check")
        }
    }
}
if ($issueMissing.Count -gt 0) {
    foreach ($bad in $issueMissing) {
        Add-Finding -Level 'FAIL' -Area 'issues' -Detail "shipped-claim doc cites missing path: $bad (fix the doc, ship the path, or declare out-of-tree-commands: true)"
    }
}
else {
    Add-Finding -Level 'PASS' -Area 'issues' -Detail "$($issueSeen.Count) path reference(s) across $issueScanned shipped-claim issue doc(s) resolve ($issueExempt out-of-tree)"
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

# --- Directory naming: kebab-case in authored trees (retro candidate 4) ----
# Mechanical rule promoted from .github/copilot-instructions.md prose to a
# deterministic check: directories only, hidden dirs / __pycache__ /
# node_modules excluded. Green on today's tree, so it ships FAIL.
$namedTrees = @('skills', 'agents', 'instructions', 'hooks', 'canvas', 'evals', 'docs', 'plugins', 'scripts')
$dirNamesChecked = 0
$badDirNames = [System.Collections.Generic.List[string]]::new()
foreach ($tree in $namedTrees) {
    $treeRoot = Join-Path $repoRoot $tree
    if (-not (Test-Path $treeRoot)) { continue }
    $rootLen = $treeRoot.Length
    Get-ChildItem -Path $treeRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $segments = @((($_.FullName.Substring($rootLen)) -split '[\\/]') | Where-Object { $_ })
        if (@($segments | Where-Object { $_ -like '.*' -or $_ -in @('__pycache__', 'node_modules') }).Count -gt 0) { return }
        $dirNamesChecked++
        if ($_.Name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            $badDirNames.Add("$tree/" + ($segments -join '/'))
        }
    }
}
if ($badDirNames.Count -gt 0) {
    foreach ($bad in $badDirNames) {
        Add-Finding -Level 'FAIL' -Area 'naming' -Detail "directory not kebab-case: $bad"
    }
}
else {
    Add-Finding -Level 'PASS' -Area 'naming' -Detail "$dirNamesChecked directory name(s) across $($namedTrees.Count) authored tree(s) kebab-case clean"
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
