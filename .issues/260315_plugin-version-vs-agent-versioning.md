---
date: 2026-03-15
type: Task
severity: Medium
status: Completed
---

# Task: Separate plugin version from bundled custom agent version

## Objective
Establish a clear versioning policy and implementation for Copilot plugins (e.g., `ralph-v2`) that decouples the plugin bundle version from the internal version(s) of the custom agents it contains.

The current workflow derives the plugin version from the collective version of the multi-agent workflow (e.g., `ralph-v2` agents all being `2.13.0`). This makes it hard to treat the plugin bundle as an independent product (e.g., plugin releases, bugfixes, channel promotions) without also bumping all agent versions.

## Tasks
- [x] Review current versioning implementation in `scripts/publish/build-plugins.ps1` and related publishing scripts that determine plugin version.
- [x] Identify where `ralph-v2` plugin version is derived from agent metadata and document the code path.
- [x] Adopt the requested two-version strategy:
  - Source `plugins/<runtime>/ralph-v2/plugin.json` `version` is the plugin semantic version (currently `0.1.0`).
  - Internal Ralph agent workflow version (`2.13.0`) remains independent in source agent frontmatter.
- [x] Update publishing scripts and source manifests so the plugin bundle version comes directly from source manifest `version`, without using `x-copilot-fc.bundleVersionOverride`.
- [x] Ensure downstream tooling reports the plugin bundle version separately from the workflow version where relevant.
- [x] Update documentation and specs explaining the workflow-version vs plugin-version model and the bump policy for each.
- [x] Update validation checks so bundle builds assert manifest-sourced plugin versioning instead of override-based behavior.

## Resolution

- `plugins/cli/ralph-v2/plugin.json` and `plugins/vscode/ralph-v2/plugin.json` now set `version` to the plugin release version (`0.1.0`) and no longer carry `x-copilot-fc.bundleVersionOverride`.
- `scripts/publish/build-plugins.ps1` now treats Ralph source manifest `version` as the shipped plugin version, while continuing to derive the canonical workflow version from Ralph agent frontmatter.
- `scripts/publish/publish-plugins.ps1` preflight reporting now surfaces plugin manifest version and workflow version as separate values without referring to any override field.
- `scripts/test/ralph-v2-cli-smoke.ps1` now validates that the built bundle version comes from source manifest `version`.
- Related Ralph docs and specs now describe plugin manifest `version` as the plugin release stream and agent frontmatter `metadata.version` as the workflow contract version.

## Acceptance Criteria
- [x] The `ralph-v2` plugin bundle can be built with a plugin version that is different from the internal agent workflow version.
- [x] Ralph publication now uses source manifest `version` as the plugin version instead of reusing the agent workflow version.
- [x] Documentation clearly describes when to bump the plugin version vs the agent workflow version.
- [x] Publishing/build reporting surfaces plugin version and workflow version as separate values.

## References
- Existing publish scripts: `scripts/publish/build-plugins.ps1`, `scripts/publish/publish-plugins.ps1`
- Ralph-v2 agent metadata: `agents/ralph-v2/` (agents, versions, plugin-managed folders)
- Repo memory: plugin version is currently derived from agent metadata (per established convention)
