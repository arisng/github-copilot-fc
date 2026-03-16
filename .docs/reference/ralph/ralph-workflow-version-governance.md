---
category: reference
source_artifacts:
  - agents/ralph-v2/vscode/ralph-v2-orchestrator-VSCode.agent.md
  - openspec/specs/ralph-v2-orchestration/session/spec.md
  - plugins/cli/ralph-v2/plugin.json
  - plugins/vscode/ralph-v2/plugin.json
  - scripts/publish/build-plugins.ps1
  - scripts/publish/publish-plugins.ps1
extracted_at: 2026-03-09T10:55:16+07:00
promoted: true
promoted_at: 2026-03-09T11:00:21.9466240+07:00
---

# Ralph workflow version governance

## Purpose

This reference defines Ralph-v2's two-version governance model so workflow changes and published plugin bundles can evolve independently without losing a single canonical workflow version.

## Canonical version source

- The shared Ralph source agent wrapper `metadata.version` is the canonical workflow version.
- Workflow documentation and normalization rules must describe versioning in terms of that shared workflow version.
- Each Ralph source agent wrapper keeps that field, but all wrappers must carry the same value; see [Ralph-v2 agent frontmatter version contract](ralph-agent-frontmatter-version-contract.md).

## Bundle version source

- The published plugin bundle version comes from `x-copilot-fc.bundleVersionOverride` in the source `plugins/<runtime>/ralph-v2/plugin.json` when that override is present.
- When no override is present, build/publish automation falls back to the canonical Ralph workflow version.
- The source manifest `version` field should remain aligned to the canonical workflow version for readability and as the documented fallback value; do not repurpose that field as the independent bundle release stream.

## How to bump each version

- Bump the Ralph workflow version (`metadata.version` across the Ralph source agent wrappers, plus the readable source manifest `version`) when the shipped Ralph workflow behavior, orchestration contract, or compatibility expectations change.
- Bump `x-copilot-fc.bundleVersionOverride` when you need a plugin-only release such as packaging changes, installer/distribution fixes, or plugin metadata changes that do not justify a workflow-version bump.
- Remove `x-copilot-fc.bundleVersionOverride` when you want plugin bundle versioning to fall back to the workflow version again.

## Manifest correlation rule

- Source `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` `version` values should align with the canonical Ralph workflow version.
- If a source manifest `version` drifts, build/publish automation emits a warning, the bundle still resolves version from the override-or-fallback rules above, and the drift should be corrected.
- If `x-copilot-fc.bundleVersionOverride` is present, automation emits a guard warning so operators can see that the published plugin version differs from the workflow version.
- If the override is present but matches the workflow version, automation warns to remove the override and rely on fallback instead of keeping both versions in lockstep explicitly.

## Automation rule

- `scripts/publish/build-plugins.ps1` derives the Ralph workflow version from source agent frontmatter and stamps bundled `plugin.json` version from `x-copilot-fc.bundleVersionOverride` when present, otherwise from the canonical workflow version.
- `scripts/publish/publish-plugins.ps1` performs Ralph-specific preflight reporting so operators can see workflow version, source manifest version, bundle version, and override state before bundle publication.

## Channel orthogonality rule

- Stable and beta channels may change bundle identity, plugin names, and bundled agent filenames.
- Channel handling must remain orthogonal to version stamping and validation.
- A beta build must keep the same canonical workflow version as the corresponding stable build unless the source workflow version changes.

## Stable implementation points

- `agents/ralph-v2/vscode/ralph-v2-orchestrator-VSCode.agent.md` and the sibling Ralph source agent wrappers carry the canonical workflow version in `metadata.version`.
- `openspec/specs/ralph-v2-orchestration/session/spec.md` defines the normative workflow-version governance requirements and scenarios.
- `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` carry the readable source manifest `version` aligned to workflow version plus the optional `x-copilot-fc.bundleVersionOverride` source-only bundle release override.
- `scripts/publish/build-plugins.ps1` and `scripts/publish/publish-plugins.ps1` enforce the version propagation path.
