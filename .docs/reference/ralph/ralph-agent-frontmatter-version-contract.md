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
4. Source `plugin.json` manifests use their own `version` field as the shipped plugin version for each runtime bundle, and that value may intentionally differ from the canonical workflow version.
5. Build/publish guidance must describe source manifest `version` as the shipped plugin version and `metadata.version` as the separate Ralph workflow contract version.
6. No separate bundle-version override field is part of Ralph source versioning.

## Operational maintenance rule

- When Ralph workflow behavior changes enough to require a release bump, update every Ralph-v2 source agent wrapper to the same new version.
- When only one runtime wrapper or one role-specific agent changes, still keep one shared Ralph version if the change belongs to the same shipped Ralph workflow/product.
- Choose patch, minor, or major based on the semantic impact of the Ralph release, not on how many agent files changed.
- If a source plugin manifest needs an independent plugin release, bump the manifest `version` directly.
- If a source plugin manifest `version` differs from the shared agent-frontmatter version, treat that as an intentional separation between plugin release version and workflow contract version unless other release notes say otherwise.
- Keep beta and stable channel identity orthogonal to versioning. Channel naming may change bundle identity, but it must not create a separate semantic version stream.

## Why the field remains on every agent file

- `scripts/publish/build-plugins.ps1` resolves the Ralph agent entries declared in `plugin.json`, reads each source agent's frontmatter version, and fails the build if they diverge.
- Keeping the field on every source agent wrapper makes the version contract visible at the same artifact boundary the build consumes.
- The repeated field is a validated mirror of one shared workflow version, not evidence that each agent owns its own release cadence.

## What not to do

- Do not remove `metadata.version` from some Ralph source agents while keeping it on others.
- Do not maintain separate version numbers for CLI wrappers and VS Code wrappers.
- Do not let one Ralph agent drift ahead or behind another to record implementation history.
- Do not describe plugin manifest `version` as a fallback mirror of the workflow version.
- Do not use beta bundles as a reason to suffix, fork, or independently advance the Ralph semantic version.

## Relationship to other Ralph version artifacts

- `agents/ralph-v2/README.md` documents the high-level workflow-version model.
- `.docs/reference/ralph/ralph-workflow-version-governance.md` defines the broader governance contract for source manifests and bundled artifacts.
- This document defines the per-file maintenance rule for the repeated frontmatter field that carries that canonical workflow version.
