---
description: 'Enforce the OpenSpec protocol for any edits, reviews, or workflow changes involving openspec/ artifacts in this workspace'
applyTo: 'openspec/**, skills/openspec-sdd/**, .github/skills/openspec-*/**, .github/prompts/opsx-*.prompt.md, scripts/openspec/**'
---

# OpenSpec Protocol

Use [OpenSpec SDD](skills/openspec-sdd/SKILL.md) for any task involving OpenSpec protocol artifacts — specs, changes, config, generated skills/prompts, or validation scripts.

For AI-agent entry points, route by intent:

- Exploration or critique: use [openspec-explore](.github/skills/openspec-explore/SKILL.md)
- New or updated change proposal: use [openspec-propose](.github/skills/openspec-propose/SKILL.md)
- Implementation from tasks: use [openspec-apply-change](.github/skills/openspec-apply-change/SKILL.md)
- Archive or sync into current specs: use [openspec-archive-change](.github/skills/openspec-archive-change/SKILL.md)
- Brownfield baseline capture for undocumented current behavior: see Narrow Exceptions below

For comprehensive protocol guidance beyond these routing rules, read [OpenSpec SDD SKILL.md](skills/openspec-sdd/SKILL.md).

## Required Routing Rules

1. Treat `openspec/specs/**` as protocol-governed current-state artifacts, not ad hoc editing targets.
2. For any new behavior, changed behavior, renamed requirement, or removed requirement, create or continue a change in `openspec/changes/<change-name>/` first.
3. Update current specs only through the OpenSpec sync or archive workflow.
4. Treat `openspec/config.yaml` as protocol-governed. Change it only when project-wide OpenSpec context or rules need to change.
5. If a task mentions `/opsx:*`, interpret that as a workflow alias. Do not depend on slash-command UX being available.
6. If slash prompts are unavailable, execute the equivalent skill or CLI workflow directly instead of asking the user to do it manually.

> Custom profile commands (e.g., `/opsx:new`, `/opsx:verify`) generate their own skill and prompt files when the profile is enabled via `openspec update`. Route through those generated files using the same skill-first pattern.

## Directory Convention

This workspace uses a workspace-scoped namespace under `openspec/specs/<workflow>/<domain>/spec.md`.

- Never place domain specs directly under `openspec/specs/`. All domains must nest under a workflow-scoped subdirectory.
- Keep `ralph-v2-orchestration/<domain>` as the current pattern for Ralph-v2 specs.
- Use a new top-level namespace only when a genuinely separate workflow or system needs its own spec family.
- Use full path prefixes for cross-workflow requirement references (e.g., `ralph-v2-orchestration/session/SES-001`).

## Narrow Exceptions

Direct edits to `openspec/specs/**` are allowed only when one of these is explicitly true:

- Brownfield baseline capture is documenting current behavior for a domain that does not exist yet.
- The user explicitly requests repair of previously corrupted synced content.

Outside those cases, direct edits to current specs are a protocol violation.