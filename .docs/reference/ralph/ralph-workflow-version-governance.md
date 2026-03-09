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

This reference defines the canonical Ralph-v2 version-governance contract so workflow changes, source manifests, and bundle publication follow one durable version source.

## Canonical version source

- The shared Ralph source agent wrapper `metadata.version` is the canonical workflow version.
- Workflow documentation and normalization rules must describe versioning in terms of that shared workflow version.

## Manifest correlation rule

- Source `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` versions must align with the canonical Ralph workflow version.
- Bundled plugin manifests are stamped from the canonical workflow version before publication.
- Manual manifest drift is not an accepted long-term mechanism.

## Automation rule

- `scripts/publish/build-plugins.ps1` derives the Ralph workflow version from source agent frontmatter and stamps the bundled `plugin.json` version from that value.
- `scripts/publish/publish-plugins.ps1` performs Ralph-specific preflight reporting so operators can see the canonical workflow version before bundle publication.

## Channel orthogonality rule

- Stable and beta channels may change bundle identity, plugin names, and bundled agent filenames.
- Channel handling must remain orthogonal to version stamping and validation.
- A beta build must keep the same canonical workflow version as the corresponding stable build unless the source workflow version changes.

## Stable implementation points

- `agents/ralph-v2/vscode/ralph-v2-orchestrator-VSCode.agent.md` and the sibling Ralph source agent wrappers carry the canonical workflow version in `metadata.version`.
- `openspec/specs/ralph-v2-orchestration/session/spec.md` defines the normative workflow-version governance requirements and scenarios.
- `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` carry the source manifest version aligned to the workflow version.
- `scripts/publish/build-plugins.ps1` and `scripts/publish/publish-plugins.ps1` enforce the version propagation path.
