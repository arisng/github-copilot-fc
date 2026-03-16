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

- The published plugin bundle version comes from the source `plugins/<runtime>/ralph-v2/plugin.json` `version` field.
- That plugin manifest `version` is the shipped plugin release version for the runtime bundle, not a mirror or fallback of the canonical Ralph workflow version.
- No separate bundle-version override field is part of Ralph version governance.

## How to bump each version

- Bump the Ralph workflow version (`metadata.version` across the Ralph source agent wrappers) when the shipped Ralph workflow behavior, orchestration contract, or compatibility expectations change.
- Bump source `plugin.json` `version` when you need a plugin-only release such as packaging changes, installer/distribution fixes, or plugin metadata changes that do not justify a workflow-version bump.
- If a change affects both contracts, bump workflow version and plugin version intentionally as separate decisions rather than forcing lockstep.

## Manifest correlation rule

- Source `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` `version` values are the shipped plugin versions for those runtime artifacts.
- Keep the CLI and VS Code manifest versions aligned when cutting the same Ralph plugin release across runtimes.
- Those manifest versions may differ from the canonical workflow version without constituting drift, because they represent a separate release stream.
- Build/publish guidance should surface plugin version and workflow version as distinct values so operators can see both contracts during release handling.

## Automation rule

- Build/publish workflows should preserve source manifest `version` as the shipped plugin version.
- Build/publish workflows should derive Ralph workflow version from source agent frontmatter and report it separately as the workflow contract version.

## Channel orthogonality rule

- Stable and beta channels may change bundle identity, plugin names, and bundled agent filenames.
- Channel handling must remain orthogonal to version stamping and validation.
- A beta build must keep the same canonical workflow version as the corresponding stable build unless the source workflow version changes.

## Stable implementation points

- `agents/ralph-v2/vscode/ralph-v2-orchestrator-VSCode.agent.md` and the sibling Ralph source agent wrappers carry the canonical workflow version in `metadata.version`.
- `openspec/specs/ralph-v2-orchestration/session/spec.md` defines the normative workflow-version governance requirements and scenarios.
- `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` carry plugin release version in their `version` field.
- Build and publish documentation should present that manifest version as the shipped plugin version and the source agent frontmatter version as the separate workflow contract version.
