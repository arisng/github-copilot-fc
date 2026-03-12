# jq empty-propagation bug in Ralph Bash hook logger

## Problem

The Bash Ralph hook logger (`hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh`) uses a `jq -cn` pattern to construct tool-usage JSONL entries. Several optional fields use `select(. != "")` or `if $var == null then empty else $var end` to conditionally include values. In jq, when **any** field expression evaluates to `empty`, the **entire JSON object** is suppressed — zero output, exit code 0.

## Affected events

- **`preToolUse`**: `result_type` and `result_text` are always empty strings (no tool result yet). `select(. != "")` evaluates to `empty`, suppressing the entire log entry.
- **`postToolUse` without payload logging**: `tool_args` is `null` → `if $args == null then empty else $args end` → `empty` → entire entry suppressed.
- **`postToolUse` with payload but missing result**: `tool_result` is `null` → same propagation.

## Impact

ALL tool-usage.jsonl entries are silently dropped by the Bash logger. Subagent events (`subagentStart`/`subagentStop`) are unaffected because they use a different jq construction path without `select(. != "")`. The `{"continue":true}` non-fatal contract is preserved — the bug is silent.

## Reproduction

```bash
# Empty result_type suppresses entire object:
jq -cn --arg rt "" '{result_type:($rt | select(. != ""))}'
# → no output (exit 0)

# Non-empty result_type produces output:
jq -cn --arg rt "text" '{result_type:($rt | select(. != ""))}'
# → {"result_type":"text"}
```

## Fix pattern

Replace `select(. != "")` with conditional object merging that omits empty fields without propagating `empty`:

```bash
# Before (broken):
'{..., result_type:($rt | select(. != "")), ...}'

# After (fixed):
'{ts:$ts, ts_iso:$ts_iso, sid:$sid, event:$ev, cwd:$cwd}
  + (if $rt  != "" then {result_type:$rt} else {} end)
  + (if $txt != "" then {result_text:$txt} else {} end)
  + (if $args != null then {tool_args:$args} else {} end)
  + (if $result != null then {tool_result:$result} else {} end)'
```

## Consequence for prior claims

The cross-shell schema parity claim made for tool events is invalidated. Schema parity remains verified for subagent events only. Once this bug is fixed and tool entries start being written, parity should be re-verified.
