---
category: explanation
source_session: 260308-140826
source_iteration: 2
source_artifacts:
  - iterations/1/reports/task-1-report.md
  - iterations/1/reports/task-3-report.md
  - iterations/1/reports/task-4-report-r2.md
  - iterations/1/review.md
  - iterations/2/feedbacks/20260308-193738/feedbacks.md
extracted_at: 2026-03-08T19:42:35+07:00
staged_at: 2026-03-08T19:44:12+07:00
promoted: true
promoted_at: 2026-03-08T20:15:25+07:00
---

# About beta plugin identity for parallel installs

## Background

This session changed the plugin publish flow so beta publishing is the default path while stable publishing remains explicit. That change only works safely when the beta channel has a distinct identity everywhere the bundle is built, copied, or registered.

## The core concept

When stable and beta variants of the same plugin can exist at the same time, the beta channel must stay distinguishable across every externally visible surface of the bundle.

In practice, that means keeping the channel choice aligned across:

1. bundle output selection,
2. plugin manifest naming,
3. installed CLI target paths,
4. VS Code registration targets, and
5. any bundled files whose names are used for discovery or operator inspection.

If one of those surfaces keeps the stable identity while the others switch to beta, a later publish or cleanup step can collide with the wrong variant.

## Why bundle identity matters more than install-name matching alone

The reworked beta publish verification showed that VS Code registration cleanup should identify sibling registrations by the source plugin bundle identity, not only by the final install name. A cleanup rule that keys only on the currently requested name can leave stale channel variants behind when the same plugin has both stable and beta registrations.

The more robust rule is:

- determine which plugin is being published from the source bundle location,
- treat other channel variants for that same plugin as siblings, and
- remove or replace those sibling registrations before writing the requested channel path.

That keeps registration state converged on the requested channel instead of accumulating mismatched stable and beta entries.

## Repository implications

Future changes to plugin bundling in this repository should preserve channel-distinct identity through the whole publish pipeline, not just at the bundle root. If beta-specific naming is introduced for additional bundled assets, the manifest paths and any cleanup logic that references those assets should be updated in the same change.

This is especially important for artifacts that can be inspected or loaded in parallel, such as bundled agent files, installed plugin roots, and registered VS Code bundle paths.

## Practical takeaway

Treat beta publishing as a parallel-install contract. The channel marker has to travel consistently with the plugin from bundle generation through installation and registration, otherwise later publish or cleanup steps will reintroduce stable/beta ambiguity.