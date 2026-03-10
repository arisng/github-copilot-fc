---
category: reference
---

# jq Conditional Object Merging Pattern

## Summary

When constructing JSON objects with optional fields in jq, use conditional object merging (`+ (if ... then {k:v} else {} end)`) instead of `select()` guards. The `select()` function operates on the entire pipeline result — if a single `select(. != "")` evaluates to false, the entire output is suppressed, not just the empty field.

## The Anti-Pattern: `select()` for Optional Fields

```jq
# BROKEN: if agent is empty, the ENTIRE log entry is silently dropped
jq -cn --arg agent "$AGENT" --arg tool "$TOOL" \
  '{tool: $tool} + ($agent | select(. != "") | {agent: .})'
```

When `$AGENT` is an empty string, `select(. != "")` produces `empty`, which propagates through the `+` operator and suppresses the entire object — including the required `tool` field.

## The Fix: Conditional Object Merging

```jq
# CORRECT: empty agent is safely omitted; required fields always present
jq -cn --arg agent "$AGENT" --arg tool "$TOOL" \
  '{tool: $tool} + (if $agent != "" then {agent: $agent} else {} end)'
```

The base object `{tool: $tool}` always produces output. The `+ (if ... then {k:v} else {} end)` pattern:
- Merges `{agent: $agent}` when the value is non-empty
- Merges `{}` (no-op) when the value is empty
- Never produces `empty`, so the pipeline is never suppressed

## Comparison Operators by Argument Type

| jq arg type | Comparison | Example |
|-------------|------------|---------|
| `--arg` (string) | `!= ""` | `if $agent != "" then {agent:$agent} else {} end` |
| `--argjson` (JSON) | `!= null` | `if $tool_args != null then {tool_args:$tool_args} else {} end` |
| Stringified null | `!= "null"` | `if $ts_iso != "null" then {ts_iso:$ts_iso} else {} end` |

## Structural Pattern

```jq
# Base object with required fields (always emitted)
{ts: $ts, sid: $sid, event: $ev, cwd: $cwd, tool: $tool}

# Optional string fields
+ (if $ts_iso != "null" then {ts_iso: $ts_iso} else {} end)
+ (if $agent != "" then {agent: $agent} else {} end)

# Optional JSON fields
+ (if $tool_args != null then {tool_args: $tool_args} else {} end)
+ (if $tool_result != null then {tool_result: $tool_result} else {} end)
```

## Compatibility

Conditional object merging is standard jq syntax supported since jq 1.6+. No version probe is needed.
