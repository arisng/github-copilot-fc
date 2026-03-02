---
category: reference
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/reports/task-critique-1-1-report.md
  - iterations/7/review.md
  - iterations/7/reports/task-4-report.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
---

# [Regex]::Replace() Script Block Pattern for Safe String Replacement

## Problem

PowerShell's `-replace` operator passes the replacement string through .NET's regex replacement engine, which interprets special tokens as backreferences:

| Token | Meaning |
|-------|---------|
| `$0` | Entire match |
| `$1`–`$9` | Capture group N |
| `$&` | Entire match (alternate syntax) |
| `$+` | Last captured group |
| `$$` | Literal `$` (escape sequence) |

If the replacement string contains any of these tokens as literal text (common in documentation, code examples, or instruction files), the output will be silently corrupted.

## Unsafe Pattern

```powershell
# UNSAFE — $instructionContent may contain $0, $&, etc.
$body = $body -replace '(?m)^.*<!-- EMBED:\s*.+?\s*-->.*$', $instructionContent
```

## Safe Pattern — Script Block Evaluator

```powershell
# SAFE — script block returns content verbatim, bypasses backreference parsing
$body = [Regex]::Replace(
    $body,
    '(?m)^.*<!-- EMBED:\s*.+?\s*-->.*$',
    { param($m) $instructionContent }
)
```

The script block receives the match object as `$m` but ignores it, returning the replacement string directly. The .NET regex engine treats the script block's return value as a literal string — no backreference interpretation occurs.

## Alternative: Dollar-Sign Escaping

```powershell
# Also safe, but more brittle if content has many $ characters
$body = $body -replace $pattern, $instructionContent.Replace('$', '$$')
```

This escapes every `$` in the replacement string. Works but is less readable and requires careful escaping.

## When to Use

Use `[Regex]::Replace()` with a script block whenever the replacement string is **dynamic content** (file contents, user input, template expansions). Use plain `-replace` only when the replacement string is a **known literal** under your control.

## Discovery Context

Discovered during iteration 7 task-4 review (ISS-m-008). The bug had zero current impact because no instruction files contained `$0`/`$&`/`$+` tokens, but was fixed proactively in task-critique-1-1 (commit `9241ac6`).
