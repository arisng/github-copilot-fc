---
category: how-to
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/tasks/task-5.md
  - iterations/7/reports/task-5-report.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
---

# How to Publish Plugins with -SkipBundle

## Goal

Publish a Copilot CLI plugin using `publish-plugins.ps1`. Bundling is the **default** behavior — self-contained `.build/` directories are always produced unless explicitly skipped.

## Default: Bundled Install (Recommended)

```powershell
# Bundles and installs — the default path
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins 'ralph-v2'
```

This:
1. Copies plugin contents to `.build/` directory.
2. Rewrites relative paths in `plugin.json` to local `.build/` paths.
3. Runs `Merge-AgentInstructions` to inline instruction content into agent files via EMBED markers.
4. Validates the bundle (schema, section markers, body char counts).
5. Runs `copilot plugin install` on the `.build/` directory.

## Escape Hatch: -SkipBundle

```powershell
# Installs directly from source (non-bundled) — emits warning
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins 'ralph-v2' -SkipBundle
```

Use `-SkipBundle` only for local development/debugging. It:
- Emits a `Write-Warning` about relative path resolution risks.
- Skips `.build/` creation, instruction merging, and bundle validation.
- Installs directly from the source directory.

## Naming Convention

The `-SkipBundle` switch follows the established `-Skip*` naming pattern in the same script (e.g., `-SkipWSL`). Both switches are independent and can be combined.

## Via Router Script

```powershell
# The router passes -Plugins but not -SkipBundle
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type plugins -Name ralph-v2
```

The router (`publish-artifact.ps1`) always uses the default bundled path. To use `-SkipBundle`, invoke `publish-plugins.ps1` directly.
