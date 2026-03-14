# How to Publish Copilot Customizations for Copilot CLI

This guide shows you how to publish each workspace artifact type (Copilot Customization Primitives) to GitHub Copilot CLI (`copilot` command) so your agents, skills, instructions, and hooks are available outside VS Code.

## When to use this guide

Use this if you have Copilot customizations (agents, instructions, skills, hooks, toolsets, prompts) and want them available when using the `copilot` CLI tool in your terminal.

## Before you start

- **Copilot CLI installed**: GA v0.0.420+ (`copilot --version` to verify)
- **`~/.copilot/` directory exists**: Created automatically on first `copilot` run, or create manually
- **PowerShell available**: Publish scripts require `pwsh` (Windows or Linux/WSL)
- **Workspace cloned**: This repo's `scripts/publish/` directory must be accessible

## Cross-platform paths

Throughout this guide, paths are shown for both platforms:

| Placeholder     | Windows                        | Linux/WSL             |
| --------------- | ------------------------------ | --------------------- |
| `~/.copilot/`   | `$env:USERPROFILE\.copilot\`   | `$HOME/.copilot/`     |
| VS Code prompts | `%APPDATA%\Code\User\prompts\` | N/A (VS Code manages) |

> **Tip:** The `--config-dir` flag changes the Copilot CLI configuration root, but plugin install storage should still be verified on the target client. In the latest local CLI 1.0.4 check for this workspace, plugin installs triggered through `copilot plugin install` still landed under the default `~/.copilot/installed-plugins/_direct/...` tree rather than an isolated temp config root.

> **Note on plugins:** For local CLI plugins in this workspace, the supported flow is: build the bundle, then run `copilot plugin install <local_plugin_path>`. Treat any resulting `_direct/...` cache path as an implementation detail rather than the publish contract.

---

## Publishing agents

The `publish-agents.ps1` script already targets `~/.copilot/agents/`, making agents available to both VS Code and Copilot CLI.

### Steps

1. **Publish all agents:**

   ```powershell
   pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Force
   ```

2. **Publish specific agents:**

   ```powershell
   pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Agents 'planner,nexus' -Force
   ```

3. **Verify discovery:**

   ```bash
   ls ~/.copilot/agents/
   # Should list *.agent.md files
   ```

4. **Test in CLI:**

   ```bash
   copilot --agent planner "Create a project plan"
   ```

### What the script does

- Copies `agents/*.agent.md` → `~/.copilot/agents/` (Windows)
- Copies to WSL `~/.copilot/agents/` if WSL is detected (unless `-SkipWSL`)
- Also publishes to VS Code user prompts directories (dual-target)

### Frontmatter differences

Agent `.agent.md` files work in both VS Code and CLI, but the schema differs. Unrecognized fields are silently ignored.

- **CLI-only fields**: `model`, `infer`, `mcp-server`
- **VS Code-only fields**: `agents:`, `argument-hint:`, `user-invocable:`

See the [schema comparison](../../explanation/copilot/copilot-cli-vs-vscode-customization.md#agent-frontmatter-schema-comparison) for the full property table.

### Variant-aware publishing (iteration 2)

Agents are **not behaviorally shareable** across runtimes — a single `.agent.md` file cannot produce identical behavior on VS Code and copilot-cli (see [runtime-support-framework.md](../../reference/copilot/runtime-support-framework.md#agents--not-shareable-)). The workspace uses a **subdirectory convention** to separate variants:

- `agents/ralph-v2/` — VS Code variants (current location, unchanged)
- `agents/cli/` — copilot-cli variants (new, to be created in iteration 3)

When CLI variants exist, the publish flow becomes platform-aware:

```powershell
# Publish VS Code variants only
pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Platform vscode -Force

# Publish CLI variants only
pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Platform cli -Force

# Publish both (default)
pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Force
```

Both VS Code and CLI discovery expect **flat** file placement at the destination — the publish script strips the source subdirectory structure when copying. Shared platform-agnostic logic lives in `.instructions.md` files referenced by both variants, so updates to agent behavior only need to happen once.

See [agent-variant-proposal.md](../../reference/copilot/agent-variant-proposal.md) for the full directory layout, shared instruction extraction strategy, and `-Platform` parameter design.

---

## Publishing skills

The `publish-skills.ps1` script already targets `~/.copilot/skills/`, which is the CLI's skill discovery path.

### Steps

1. **Publish all skills:**

   ```powershell
   pwsh -NoProfile -File scripts/publish/publish-skills.ps1
   ```

   > Force mode is on by default. Use `-NoForce` to skip existing skills.

2. **Publish specific skills:**

   ```powershell
   pwsh -NoProfile -File scripts/publish/publish-skills.ps1 -Skills 'diataxis,beads'
   ```

3. **Verify discovery:**

   ```bash
   ls ~/.copilot/skills/
   # Should list skill directories, each containing SKILL.md
   ```

### What the script does

- Copies `skills/*/` → `~/.copilot/skills/` (and `.claude/skills/`, `.codex/skills/`)
- Copies to WSL equivalents if WSL is detected (unless `-SkipWSL`)
- Each skill folder is copied as-is (preserving `SKILL.md`, `scripts/`, `references/`)

---

## Publishing instructions

**Important:** `~/.copilot/instructions/` is **NOT** a valid discovery path for Copilot CLI. The CLI loads custom instructions from:

- **AGENTS.md**: A primary repo-level instruction file discovered in CWD, repo root, and `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` directories (alongside `.github/copilot-instructions.md`)
- **CLAUDE.md / GEMINI.md**: Recognized at repo root as instruction files
- **Single file**: `$HOME/.copilot/copilot-instructions.md`
- **Environment variable**: `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` pointing to directories containing `.github/instructions/*.instructions.md` files
- **Repo-level**: `.github/copilot-instructions.md` and `.github/instructions/**/*.instructions.md` (with `applyTo` and `excludeAgent`)

The current `publish-instructions.ps1` only targets VS Code prompts directories. Until the script is updated, use one of the manual approaches below.

### AGENTS.md (repo-level instructions)

`AGENTS.md` is a primary CLI instruction path — it works like `.github/copilot-instructions.md` but is discovered more broadly:

- **CWD**: The current working directory when `copilot` is invoked
- **Repo root**: The root of the current git repository
- **`COPILOT_CUSTOM_INSTRUCTIONS_DIRS`**: Any directories listed in this environment variable

This file requires no publishing — it is a **repo-level convention**. Place `AGENTS.md` in your repository root and it will be loaded automatically by the CLI.

```bash
# Verify AGENTS.md is discovered
ls AGENTS.md
# Should exist in repo root
```

`CLAUDE.md` and `GEMINI.md` are also recognized at the repo root as instruction files by the CLI. These are typically used for model-specific instructions.

> **Tip:** Use `--no-custom-instructions` flag to temporarily disable loading of all instruction files (including `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, and user-level instructions). This is useful for debugging instruction conflicts.

### Option A: Concatenate into single file

Best for: Simple setups where `applyTo` patterns aren't needed.

1. **Concatenate all instruction files:**

   ```powershell
   $instructionsDir = "instructions"
   $outputFile = Join-Path $env:USERPROFILE ".copilot\copilot-instructions.md"

   # Build concatenated file with section headers
   $content = "# Custom Instructions`n`n"
   $content += "<!-- Auto-generated from workspace instructions/ -->`n"
   $content += "<!-- Regenerate: pwsh publish-instructions-cli.ps1 -->`n`n"

   Get-ChildItem -Path $instructionsDir -Filter "*.instructions.md" | ForEach-Object {
       $name = $_.BaseName -replace '\.instructions$', ''
       $body = Get-Content $_.FullName -Raw
       $content += "---`n`n## $name`n`n$body`n`n"
   }

   Set-Content -Path $outputFile -Value $content -Encoding UTF8
   ```

2. **Verify:**

   ```bash
   cat ~/.copilot/copilot-instructions.md
   # Should contain all instruction content with section headers
   ```

**Limitation:** `applyTo` frontmatter is lost — all instructions apply globally.

### Option B: Use COPILOT_CUSTOM_INSTRUCTIONS_DIRS (recommended)

Best for: Preserving `applyTo` patterns so instructions apply only to matching files.

1. **Create the directory structure:**

   ```powershell
   $customInstrDir = Join-Path $env:USERPROFILE ".copilot\custom-instructions\.github\instructions"
   New-Item -ItemType Directory -Path $customInstrDir -Force | Out-Null
   ```

2. **Copy instruction files:**

   ```powershell
   Copy-Item -Path "instructions\*.instructions.md" -Destination $customInstrDir -Force
   ```

3. **Set the environment variable:**

   ```powershell
   # PowerShell (current session)
   $env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS = Join-Path $env:USERPROFILE ".copilot\custom-instructions"

   # Persistent (Windows)
   [Environment]::SetEnvironmentVariable(
       "COPILOT_CUSTOM_INSTRUCTIONS_DIRS",
       (Join-Path $env:USERPROFILE ".copilot\custom-instructions"),
       "User"
   )
   ```

   ```bash
   # Linux/WSL — add to ~/.bashrc or ~/.zshrc
   export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/.copilot/custom-instructions"
   ```

4. **Verify directory structure:**

   ```bash
   tree ~/.copilot/custom-instructions/
   # .github/
   #   instructions/
   #     powershell.instructions.md
   #     csharp-14.instructions.md
   #     ...
   ```

**Advantage:** `applyTo` patterns in YAML frontmatter are preserved — the CLI applies instructions only to files matching the glob pattern.

---

## Publishing hooks

Hooks use the same JSON schema in both VS Code and Copilot CLI. The CLI discovers hooks from the current working directory (repo root) or via installed plugins.

### Steps

1. **Publish hooks to `.github/hooks/` (repo-level):**

   ```powershell
   pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Force
   ```

2. **Verify:**

   ```bash
   ls .github/hooks/
   # Should list *.hooks.json files
   ```

3. **Test hook activation:**

   ```bash
   # Run copilot from the repo root — hooks are loaded from CWD
   cd /path/to/repo
   copilot "test hook activation"
   ```

### What the script does

- Default behavior is repo-scoped: publishes manifests discovered under `hooks/<name>/` into `.github/hooks/`
- `-Scope user-level` publishes globally to `~/.copilot/hooks/`; `-UserLevel` still works as a legacy alias
- User-level publishing copies referenced scripts into the published hook tree and rewrites command paths to full user-level paths
- Same JSON schema: `{ "version": 1, "hooks": { ... } }`

### Supported lifecycle events

| Event                 | Description                                            |
| --------------------- | ------------------------------------------------------ |
| `sessionStart`        | Fires when a session begins                            |
| `sessionEnd`          | Fires when a session ends                              |
| `userPromptSubmitted` | Fires when user submits a message                      |
| `preToolUse`          | Fires before tool execution (can `deny`/`allow`/`ask`) |
| `postToolUse`         | Fires after tool execution                             |
| `errorOccurred`       | Fires when an error occurs                             |

---

## Toolsets: CLI alternative

**`.toolsets.jsonc` has no Copilot CLI equivalent.** The CLI uses different mechanisms for tool restriction:

| VS Code (`.toolsets.jsonc`) | CLI Equivalent                               |
| --------------------------- | -------------------------------------------- |
| Tool allowlist              | `--allow-tool <pattern>` flag                |
| Tool denylist               | `--deny-tool <pattern>` flag                 |
| Per-agent tools             | Agent `tools:` frontmatter key               |
| Dynamic restriction         | `preToolUse` hooks with `deny`/`allow`/`ask` |

### Example: Restricting tools via CLI flags

```bash
# Allow only file read and edit tools
copilot --allow-tool "view" --allow-tool "edit" "Refactor this file"

# Deny shell execution
copilot --deny-tool "bash" "Review this code"
```

### Example: Restricting tools via agent frontmatter

```yaml
---
name: safe-reviewer
description: Code review agent with restricted tools
tools:
  - view
  - edit
---
```

**No publish-toolsets.ps1 changes needed** — the toolset concept doesn't map to CLI. Document equivalent CLI flags in your agent's README or usage docs instead.

---

## Prompts: CLI alternative

**`.prompt.md` has no confirmed CLI discovery path.** The CLI does not discover prompt files from `~/.copilot/prompts/` or any equivalent directory.

### Workarounds

- **Use skills instead**: Skills (`~/.copilot/skills/*/SKILL.md`) serve most of the same purpose as prompts — providing reusable context and instructions
- **Use agents**: For complex, reusable workflows, create an agent with the prompt content embedded in its instructions
- **Use `--prompt` flag**: Pass prompt content directly via CLI flag for one-off use

**No publish-prompts.ps1 changes needed** — prompts remain a VS Code-specific artifact.

---

## Implementation plan: publish-instructions.ps1 modifications

This section specifies the changes needed to make `publish-instructions.ps1` support Copilot CLI targets alongside existing VS Code targets.

### Current state

`publish-instructions.ps1` copies `instructions/*.instructions.md` files to:
- `%APPDATA%\Code\User\prompts\` (VS Code Stable)
- `%APPDATA%\Code - Insiders\User\prompts\` (VS Code Insiders)

It does **not** target any Copilot CLI paths.

### Proposed changes

#### Guard: Check for `~/.copilot/` existence

```powershell
$copilotDir = Join-Path $env:USERPROFILE ".copilot"
if (-not (Test-Path $copilotDir)) {
    Write-Host "Copilot CLI directory not found ($copilotDir). Skipping CLI targets." -ForegroundColor Yellow
    # Continue with VS Code targets only — do not fail
}
```

**Behavior:** Silently skip CLI targets if `~/.copilot/` doesn't exist. Existing VS Code publishing is preserved unchanged.

#### Approach A: Concatenate to single file

```powershell
function Publish-InstructionsToCopilotCli {
    param(
        [string]$ProjectInstructionsPath,
        [switch]$Force
    )

    $copilotDir = Join-Path $env:USERPROFILE ".copilot"
    if (-not (Test-Path $copilotDir)) {
        Write-Host "Copilot CLI not detected, skipping CLI target" -ForegroundColor Yellow
        return
    }

    $outputFile = Join-Path $copilotDir "copilot-instructions.md"

    if ((Test-Path $outputFile) -and -not $Force) {
        $overwrite = Read-Host "copilot-instructions.md exists. Overwrite? (y/N)"
        if ($overwrite -notmatch "^[Yy]") {
            Write-Host "Skipping copilot-instructions.md" -ForegroundColor Yellow
            return
        }
    }

    $instructionFiles = Get-ChildItem -Path $ProjectInstructionsPath -Filter "*.instructions.md"
    $content = "# Custom Instructions`n`n"
    $content += "<!-- Auto-generated by publish-instructions.ps1 -->`n"
    $content += "<!-- Source: $ProjectInstructionsPath -->`n`n"

    foreach ($file in $instructionFiles) {
        $name = $file.BaseName -replace '\.instructions$', ''
        $body = Get-Content $file.FullName -Raw
        # Strip YAML frontmatter (not useful in concatenated file)
        $body = $body -replace '(?s)^---\r?\n.*?\r?\n---\r?\n', ''
        $content += "---`n`n## $name`n`n$body`n`n"
    }

    Set-Content -Path $outputFile -Value $content -Encoding UTF8
    Write-Host "Published concatenated instructions to $outputFile" -ForegroundColor Green
}
```

**Trade-off:** Simple, but loses `applyTo` scoping — all instructions apply globally.

#### Approach B: Create COPILOT_CUSTOM_INSTRUCTIONS_DIRS structure

```powershell
function Publish-InstructionsToCopilotCliDirs {
    param(
        [string]$ProjectInstructionsPath,
        [switch]$Force
    )

    $copilotDir = Join-Path $env:USERPROFILE ".copilot"
    if (-not (Test-Path $copilotDir)) {
        Write-Host "Copilot CLI not detected, skipping CLI target" -ForegroundColor Yellow
        return
    }

    $customInstrRoot = Join-Path $copilotDir "custom-instructions"
    $targetDir = Join-Path $customInstrRoot ".github\instructions"

    # Create directory structure
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Host "Created $targetDir" -ForegroundColor Green
    }

    # Copy instruction files preserving applyTo frontmatter
    $instructionFiles = Get-ChildItem -Path $ProjectInstructionsPath -Filter "*.instructions.md"
    foreach ($file in $instructionFiles) {
        $destPath = Join-Path $targetDir $file.Name
        if ((Test-Path $destPath) -and -not $Force) {
            $overwrite = Read-Host "$($file.Name) exists. Overwrite? (y/N)"
            if ($overwrite -notmatch "^[Yy]") { continue }
        }
        Copy-Item -Path $file.FullName -Destination $destPath -Force
        Write-Host "Published: $($file.Name) to CLI custom-instructions" -ForegroundColor Green
    }

    # Remind about env var
    $envVar = [Environment]::GetEnvironmentVariable("COPILOT_CUSTOM_INSTRUCTIONS_DIRS", "User")
    if (-not $envVar -or $envVar -ne $customInstrRoot) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "ACTION REQUIRED: Set COPILOT_CUSTOM_INSTRUCTIONS_DIRS" -ForegroundColor Yellow
        Write-Host "  [Environment]::SetEnvironmentVariable('COPILOT_CUSTOM_INSTRUCTIONS_DIRS', '$customInstrRoot', 'User')" -ForegroundColor Cyan
    }
}
```

**Trade-off:** Preserves `applyTo` patterns, but requires the environment variable to be set once.

### Integration into existing script

```powershell
# At the end of the existing Publish-InstructionsToVSCode function:
# Add CLI targets (non-breaking — skips silently if ~/.copilot/ not found)

Publish-InstructionsToCopilotCli -ProjectInstructionsPath $projectInstructionsPath -Force:$Force
# OR
Publish-InstructionsToCopilotCliDirs -ProjectInstructionsPath $projectInstructionsPath -Force:$Force
```

### Recommendation

**Use Approach B** (`COPILOT_CUSTOM_INSTRUCTIONS_DIRS`) as the primary CLI target because:

1. Preserves `applyTo` frontmatter — instructions scope correctly per file type
2. Mirrors how `.github/instructions/` works in repository context
3. One-time env var setup vs. losing scoping permanently
4. Can coexist with a manually maintained `~/.copilot/copilot-instructions.md`

### Backward compatibility

- Existing VS Code publish targets are preserved unchanged
- CLI targets are additive — only activate if `~/.copilot/` exists
- No new required parameters — existing invocations work identically
- WSL support follows the same pattern as `publish-agents.ps1`

---

## Summary: publish script status

| Script                     | CLI Support                                  | Status                                         |
| -------------------------- | -------------------------------------------- | ---------------------------------------------- |
| `publish-agents.ps1`       | Already targets `~/.copilot/agents/`         | ✅ No changes needed                            |
| `publish-skills.ps1`       | Already targets `~/.copilot/skills/`         | ✅ No changes needed                            |
| `publish-instructions.ps1` | VS Code only                                 | ⚠️ Needs update (see implementation plan above) |
| `publish-hooks.ps1`        | Publishes to `.github/hooks/` (works in CLI) | ✅ No changes needed                            |
| `publish-prompts.ps1`      | VS Code only, no CLI equivalent              | ℹ️ No changes possible                          |
| `publish-toolsets.ps1`     | VS Code only, CLI uses flags                 | ℹ️ No changes possible                          |

---

## Troubleshooting

### Instructions not loading as expected

If custom instructions are causing unexpected behavior or conflicts:

```bash
# Disable all custom instruction loading for a single session
copilot --no-custom-instructions "your prompt here"
```

The `--no-custom-instructions` flag disables loading of all instruction files including `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `$HOME/.copilot/copilot-instructions.md`, and files from `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. This is useful for isolating whether instructions are the source of a problem.

### Scope instructions to specific agents

Use the `excludeAgent` frontmatter keyword in `.github/instructions/*.instructions.md` files to exclude instructions from specific agents:

```yaml
---
applyTo: "**/*.ts"
excludeAgent: "code-review"
---
```

Valid `excludeAgent` values: `"code-review"` (excludes from code review agent) and `"coding-agent"` (excludes from the coding agent).

---

## See also

- [Copilot-CLI Customization Support Matrix](../../reference/copilot/copilot-cli-customization-matrix.md) — Full compatibility table
- [CLI vs VS Code Customization Differences](../../explanation/copilot/copilot-cli-vs-vscode-customization.md) — Why things work differently
- [Ralph-v2 Tool Compatibility](../../explanation/copilot/copilot-cli-ralph-v2-tool-compatibility.md) — Tool gap analysis for ralph-v2 agents
