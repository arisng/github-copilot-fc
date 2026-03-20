---
category: explanation
source_session: 260308-140826
source_iteration: 1
source_artifacts:
  - iterations/1/questions/technical.md
  - iterations/1/reports/task-2-report.md
  - iterations/1/reports/task-4-report-r2.md
extracted_at: 2026-03-08T14:40:53+07:00
staged_at: 2026-03-08T14:42:30+07:00
promoted: true
promoted_at: 2026-03-08T14:44:26+07:00
---

# About module-boundary loading for PowerShell publish helpers

## Background

The plugin publish flow reuses functions from `scripts/publish/build-plugins.ps1` inside `scripts/publish/publish-plugins.ps1`. Before this iteration, the publisher loaded the helper script by dot-sourcing it directly into the caller scope.

That was unsafe because `build-plugins.ps1` has its own top-level `param()` block. In PowerShell, dot-sourcing a script with a same-named parameter writes into the caller scope, so the helper import could overwrite the publisher's `$Channel` value.

## The core concept

If a reusable PowerShell helper script contains a top-level `param()` block, import it through a module boundary when the caller needs to preserve its own variables.

In this repository, the safe pattern is:

1. Wrap the helper script load in `New-Module`.
2. Dot-source the helper script inside that module.
3. Export the helper functions with `Export-ModuleMember`.
4. Import the temporary module into the caller.

That keeps the helper script's parameter binding isolated from the caller scope while still making its functions available.

## Why direct dot-sourcing failed here

The publish workflow needed explicit `-Channel beta` requests to survive the boundary between `publish-plugins.ps1` and `build-plugins.ps1`.

Direct dot-sourcing let `build-plugins.ps1` reset `$Channel` back to its own default during import, which meant a beta publish request could silently converge back to stable behavior. The visible symptom was beta verification writing stable bundle or registration paths even when the top-level command specified beta.

## Why the module boundary works better

A module-scoped import isolates the helper script's parameter block from the publisher's variables. After the helper functions are imported, `publish-plugins.ps1` can pass the effective channel value explicitly into helper calls instead of relying on ambient caller state.

That gives the publish pipeline two useful properties:

- The public default can change independently from helper implementation details.
- Explicit channel requests keep flowing through to build layout, install targets, and VS Code registration logic.

## Comparison to script-level dot-sourcing

Script-level dot-sourcing is still appropriate for helpers that are designed to share caller scope, such as files that only declare functions and constants. It is a poor fit for reusable entrypoint scripts with their own `param()` blocks, especially when caller and callee reuse parameter names like `Channel`.

## Repository implications

Future PowerShell publish helpers in this repository should prefer module-boundary loading when they are both:

- executable as standalone scripts, and
- imported for function reuse by another script.

That avoids hidden variable mutation and makes channel-sensitive publish flows easier to reason about and test.
