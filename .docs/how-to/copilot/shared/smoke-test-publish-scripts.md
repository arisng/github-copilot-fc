---
category: how-to
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-6 report"
  - "Iteration 9 feedback-driven questions Q-FDB-008 Q-FDB-009"
  - "Iteration 9 session review SC-4"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# How to Smoke Test Publish Scripts After Parameter Changes

## Goal

Validate that `publish-agents.ps1` and `build-plugins.ps1` behave correctly after a parameter rename or script change, without requiring a dedicated test environment or a full install of all agents.

## Prerequisites

- Script changes are committed or staged.
- `$env:USERPROFILE\.copilot\agents` exists (created by prior CLI install).

## Four-Step Sequence

### Step 1 — Baseline Snapshot

Capture the current state of the installed agents directory before running any publish:

```powershell
$before = Get-ChildItem "$env:USERPROFILE\.copilot\agents" -Recurse -File |
    Select-Object FullName, LastWriteTime |
    Sort-Object FullName
```

### Step 2 — Canary Agent Publish (Single Agent Scoped)

Publish only a single lightweight agent (e.g., the Planner — no MCP, no embed dependencies) to validate the `-Runtime` parameter path:

```powershell
pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -Runtime cli -Agents "ralph-v2-planner" -Force
```

- Expected: `Exit code 0`, `Success: 1 | Failed: 0`
- This validates parameter parsing, file copy, and destination path resolution without touching other installed agents.

### Step 3 — Diff Check

Confirm only the canary agent changed:

```powershell
$after = Get-ChildItem "$env:USERPROFILE\.copilot\agents" -Recurse -File |
    Select-Object FullName, LastWriteTime |
    Sort-Object FullName
Compare-Object $before $after -Property FullName
```

Only `ralph-v2-planner.agent.md` should appear in the diff output.

### Step 4 — Plugin Parameter Smoke Test

Test the plugin build script's parameter path with a filtered build (avoids a full bundle regeneration):

```powershell
pwsh -NoProfile -File scripts/publish/build-plugins.ps1 -Plugins ralph-v2
```

- Expected: `Exit code 0`, `Build complete: 1 built, 0 error(s)`
- Builds only the ralph-v2 bundle under `plugins/cli/.build/` while still exercising the parameter path and conditional branches.

## Staging Smoke Test (`-CopilotHome`)

After adding or changing `-CopilotHome` on the publish scripts, verify it stages into a temp directory without touching production:

```powershell
$staging = Join-Path $env:TEMP "copilot-staging-smoke-$([guid]::NewGuid().ToString('N').Substring(0,8))"

# Agents → <staging>/agents
pwsh -NoProfile -File scripts/publish/publish-agents.ps1 -CopilotHome $staging -Agents "nexus" -Force

# Instructions → <staging>\Code\User\prompts (skips WSL)
pwsh -NoProfile -File scripts/publish/publish-instructions.ps1 -CopilotHome $staging -Instructions "powershell" -Force

# User-level hooks → <staging>/hooks (skips WSL + VS Code settings mutation)
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Scope user-level -CopilotHome $staging -Hooks "ralph-tool-logger" -Force

# Verify the tree, then clean up
Get-ChildItem $staging -Recurse -File | Select-Object FullName
Remove-Item $staging -Recurse -Force
```

- Expected: `Exit code 0` each; files land under the staging root, and no production `~/.copilot/` or `%APPDATA%` paths are written.
- `publish-hooks.ps1` staging mode prints `Staging mode: skipping VS Code settings update` and skips WSL.

## Backward Compatibility Test

Verify a deprecated parameter still emits the correct warning:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -SkipWSL 2>&1 |
    Where-Object { $_ -match "deprecated" }
```

- Expected: Output contains the deprecation warning text (publish-plugins.ps1 is deprecated; prefer `copilot plugins <options>` with `build-plugins.ps1` for bundle-only).
- This confirms the backward-compat shim is intact and the deprecation banner points to the correct replacement.
