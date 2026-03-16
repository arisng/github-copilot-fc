---
category: reference
---

# Ralph-v2 agent frontmatter version contract

## Purpose

This reference answers a specific Ralph-v2 maintenance question: should source agent files in both CLI and VS Code runtimes keep a YAML frontmatter `metadata.version`, and if so, how should that field be managed?

## Explicit answer

- Yes. Keep `metadata.version` on every Ralph-v2 source agent wrapper under `agents/ralph-v2/cli/` and `agents/ralph-v2/vscode/`.
- No. Do not manage those fields as separate per-agent or per-runtime version streams.
- Treat the repeated field as the distributed representation of one canonical Ralph workflow/product version.

## Contract

1. Every Ralph-v2 source agent wrapper must declare `metadata.version` in YAML frontmatter.
2. All Ralph-v2 source agent wrappers must carry the same version value.
3. A Ralph version bump is a workflow-wide change, not an agent-local change.
4. Source `plugin.json` manifests should normally mirror that same version in their `version` field for readability, but they are not the canonical authority.
5. Independent plugin bundle releases must use `x-copilot-fc.bundleVersionOverride`; build automation stamps bundled plugin manifests from that override when present and otherwise falls back to the canonical Ralph source-agent version.
6. If a source `plugin.json` `version` drifts, build automation tolerates it with a warning, but the drift should be corrected instead of treating `version` as a second release stream.

## Operational maintenance rule

- When Ralph workflow behavior changes enough to require a release bump, update every Ralph-v2 source agent wrapper to the same new version.
- When only one runtime wrapper or one role-specific agent changes, still keep one shared Ralph version if the change belongs to the same shipped Ralph workflow/product.
- Choose patch, minor, or major based on the semantic impact of the Ralph release, not on how many agent files changed.
- If a source plugin manifest needs an independent plugin release, leave `version` aligned to the shared agent-frontmatter version and set `x-copilot-fc.bundleVersionOverride` instead.
- If a source plugin manifest `version` drifts from the shared agent-frontmatter version, fix the manifest; do not treat that drift as the sanctioned plugin release stream.
- Keep beta and stable channel identity orthogonal to versioning. Channel naming may change bundle identity, but it must not create a separate semantic version stream.

## Why the field remains on every agent file

- `scripts/publish/build-plugins.ps1` resolves the Ralph agent entries declared in `plugin.json`, reads each source agent's frontmatter version, and fails the build if they diverge.
- Keeping the field on every source agent wrapper makes the version contract visible at the same artifact boundary the build consumes.
- The repeated field is a validated mirror of one shared workflow version, not evidence that each agent owns its own release cadence.

## What not to do

- Do not remove `metadata.version` from some Ralph source agents while keeping it on others.
- Do not maintain separate version numbers for CLI wrappers and VS Code wrappers.
- Do not let one Ralph agent drift ahead or behind another to record implementation history.
- Do not use beta bundles as a reason to suffix, fork, or independently advance the Ralph semantic version.

## Relationship to other Ralph version artifacts

- `agents/ralph-v2/README.md` documents the high-level workflow-version model.
- `.docs/reference/ralph/ralph-workflow-version-governance.md` defines the broader governance contract for source manifests and bundled artifacts.
- This document defines the per-file maintenance rule for the repeated frontmatter field that carries that canonical workflow version.
