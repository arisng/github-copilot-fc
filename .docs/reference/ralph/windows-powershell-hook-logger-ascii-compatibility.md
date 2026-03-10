---
category: reference
---

# Windows PowerShell Hook Logger ASCII Compatibility

## Summary

The Windows Ralph hook manifest executes `hooks/scripts/ralph-tool-logger.ps1` through `powershell -NoProfile -File ...`. Under that runtime contract, source-text compatibility matters before any hook routing or logging logic runs.

## Constraint

- Keep `hooks/scripts/ralph-tool-logger.ps1` ASCII-safe unless the runtime or file-encoding contract is intentionally changed.
- Treat non-ASCII punctuation in comments or emitted strings as a startup risk for the current Windows manifest runtime.
- Prefer narrow text-only fixes when the failure is a parser or startup regression rather than a logging-behavior defect.

## Blast Radius

`hooks/ralph-tool-logger.hooks.json` routes these four shared events to the same PowerShell entrypoint:

- `subagentStart`
- `subagentStop`
- `preToolUse`
- `postToolUse`

If the script fails to parse at startup, all four Windows hook events lose logging coverage at once.

## Safe Repair Pattern

- Normalize offending text to ASCII-safe punctuation.
- Preserve the existing Windows manifest command instead of switching runtimes as part of the compatibility repair.
- Re-verify event routing, payload logging, and fallback log-path behavior after the text-only change.

## Verification Expectations

- Confirm the script contains no incompatible source text for the current Windows runtime.
- Replay the exact manifest command, not just `pwsh` or a direct function call.
- Verify both normal iteration-scoped logging and degraded session-level fallback logging still return `{"continue":true}`.

## Related Guardrail

Pair this constraint with the Windows manifest-runtime smoke test in `hooks/scripts/tests/test-windows-hook-runtime.ps1` so future parser or startup regressions are detected before publish.
