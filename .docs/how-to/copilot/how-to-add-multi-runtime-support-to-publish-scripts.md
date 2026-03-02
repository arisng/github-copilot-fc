---
category: how-to
source_session: 260302-001737
source_iteration: 2
source_artifacts:
  - "Iteration 2 task-4 (publish-instructions redesign)"
  - "Iteration 2 task-4 report"
  - "Iteration 2 task-2 (WSL utility extraction)"
  - "Iteration 2 task-2 report"
extracted_at: 2026-03-02T12:35:33+07:00
promoted: true
promoted_at: 2026-03-02T12:41:22+07:00
---

# How to Add Multi-Runtime Support to a Publish Script

Goal-driven procedure for redesigning a single-runtime publish script (VS Code only) into a multi-runtime script that targets VS Code, copilot-cli (Windows), and copilot-cli (WSL).

## Prerequisites

- The shared WSL utility `scripts/publish/wsl-helpers.ps1` must exist (provides `Test-WSLAvailable`, `Convert-ToWSLPath`, `Copy-ToWSL`, `Remove-FromWSL`).
- The runtime-support framework reference (`.docs/reference/copilot/runtime-support-framework.md`) should be consulted to confirm the artifact type is supported on copilot-cli targets.

## Architecture: 3-Phase Pipeline

Structure the script as three sequential phases:

### Phase 1 — VS Code Targets (Preserve Existing Behavior)

Keep the original VS Code publishing logic unchanged. This phase copies artifact files to `%APPDATA%/Code/User/prompts/` and `%APPDATA%/Code - Insiders/User/prompts/`.

- Do not modify existing file selection, filtering, or overwrite behavior.
- Track success/fail counters: `$vscodePublished`, `$vscodeFailed`.

### Phase 2 — CLI Targets (New Runtime)

Add copilot-cli targeting with mode selection where needed. The approach depends on the artifact's delivery mechanism:

**Direct copy artifacts** (agents, skills, hooks): Copy files to `~/.copilot/<type>/` on Windows, and optionally to the WSL equivalent via `Copy-ToWSL`.

**Concatenation artifacts** (instructions): Use a `-Mode` parameter with `ValidateSet`:
- **Concat** (default): Concatenate all source files into a single target (`~/.copilot/copilot-instructions.md`). Strip YAML frontmatter with: `$content -replace '(?s)^---\r?\n.*?\r?\n---\r?\n', ''`. Insert separator comments between files: `# --- Source: <filename> ---`.
- **EnvVar** (alternative): Print informational commands for environment variable setup without modifying the system.

**WSL integration pattern:**
```powershell
# Dot-source at script level (before function definitions)
. "$PSScriptRoot/wsl-helpers.ps1"

# Detect WSL
$wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)

# Skip WSL when user opts out
if (-not $SkipWSL -and $wslAvailable) {
    $wslTargetPath = "$wslHome/.copilot/<type>/<filename>"
    Copy-ToWSL -Source $localFile -Destination $wslTargetPath
    # Use -Recurse for directories (skills), omit for files (agents, instructions)
}
```

For concatenated content, write to a temp file first, then `Copy-ToWSL` the temp file to avoid shell escaping issues with markdown.

### Phase 3 — Summary Output

Print a structured summary showing all targets:
```
Files processed: N
VS Code targets: X published, Y failed
CLI targets (Mode): X published, Y failed
WSL targets: X published, Y failed (or "skipped (-SkipWSL)")
```

## Standard Parameters

Add these parameters consistently across all multi-runtime publish scripts:

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `-SkipWSL` | Switch | `$false` | Opt out of WSL targets (always-on by default) |
| `-Mode` | ValidateSet | Varies | Select delivery mechanism variant (only for artifacts with multiple delivery options) |
| `-Force` | Switch | `$false` | Skip overwrite confirmation prompts |

## YAML Frontmatter Stripping

When concatenating `.instructions.md` files for copilot-cli's single-file format, strip the leading YAML frontmatter block:

```powershell
$content = Get-Content $file -Raw
$content = $content -replace '(?s)^---\r?\n.*?\r?\n---\r?\n', ''
```

Note: The `applyTo` frontmatter property is intentionally lost in concatenation mode — copilot-cli applies all instructions globally.

## Applicability

This pattern was first applied to `publish-instructions.ps1` and is applicable to any future publish script that needs copilot-cli support. Consult the runtime-support framework to determine which artifacts merit multi-runtime publishing:

- **Already automated**: Agents (direct copy), Skills (direct copy with `-Recurse`)
