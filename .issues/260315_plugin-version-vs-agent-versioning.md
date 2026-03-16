---
date: 2026-03-15
type: Task
severity: Medium
status: Draft
---

# Task: Separate plugin version from bundled custom agent version

## Objective
Establish a clear versioning policy and implementation for Copilot plugins (e.g., `ralph-v2`) that decouples the plugin bundle version from the internal version(s) of the custom agents it contains.

The current workflow derives the plugin version from the collective version of the multi-agent workflow (e.g., `ralph-v2` agents all being `2.13.0`). This makes it hard to treat the plugin bundle as an independent product (e.g., plugin releases, bugfixes, channel promotions) without also bumping all agent versions.

## Tasks
- [ ] Review current versioning implementation in `scripts/publish/build-plugins.ps1` and related publishing scripts that determine plugin version.
- [ ] Identify where `ralph-v2` plugin version is derived from agent metadata and document the code path.
- [ ] Propose a new versioning strategy that allows:
  - A separate plugin semantic version (e.g., `0.1.0` initial) for the bundled plugin artifact.
  - The internal agent workflow version (`2.13.0`) to remain independent and continue being used for agent runtime logic, schema, and agent-level compatibility.
- [ ] Update publishing scripts (and any metadata files) so the plugin bundle version can be set/overridden independently, while preserving the existing behavior when no override is provided.
- [ ] Ensure downstream tooling (e.g., plugin installation, release notes) uses the plugin bundle version while still exposing the agent workflow version where relevant.
- [ ] Add or update documentation (in `.docs/` or relevant README) explaining the two-version model and how to bump each.
- [ ] Add tests or validation checks to prevent accidental coupling of plugin version and agent workflow version.

## Acceptance Criteria
- [ ] The `ralph-v2` plugin bundle can be built with a plugin version that is different from the internal agent workflow version.
- [ ] Existing mechanism for deriving plugin version from agent version still works when no explicit plugin version override is provided.
- [ ] Documentation clearly describes when to bump the plugin version vs the agent workflow version.
- [ ] Publishing scripts include a guard or warning when the plugin and agent versions are unintentionally kept in lockstep.

## References
- Existing publish scripts: `scripts/publish/build-plugins.ps1`, `scripts/publish/publish-plugins.ps1`
- Ralph-v2 agent metadata: `agents/ralph-v2/` (agents, versions, plugin-managed folders)
- Repo memory: plugin version is currently derived from agent metadata (per established convention)
