---
category: reference
---

# jq `fromjson?` Evaluation Context Pitfall

## Behavior

The `extract_tool_args_json` pipeline in Ralph hook loggers uses this jq expression:

```jq
if .tool_input? != null then .tool_input
elif .toolInput? != null then .toolInput
elif .toolArgs? != null then (.toolArgs | fromjson? // .toolArgs)
else null end
```

When `.toolArgs` contains a **JSON string** (e.g., `"{\"key\":\"value\"}"`), `fromjson?` successfully parses it and returns the parsed object. The `// .toolArgs` fallback is not reached.

When `.toolArgs` contains a **pre-parsed JSON object** (e.g., `{"key":"value"}`), `fromjson?` fails (objects are not strings), and the alternative operator `//` evaluates `.toolArgs` — but in the **piped context**, `.` now refers to the result of `fromjson?` (which is `null`/`false`), not the original `.toolArgs` from the outer scope. This causes the pipeline to return `null` instead of passing through the object.

## Impact

In practice, hook event payloads always provide `toolArgs` as a JSON string, so this behavior does not surface at runtime. It only matters if the pipeline is reused in a context where `toolArgs` might arrive as a pre-parsed object.

## Workaround

To support both string and object `toolArgs`, use variable capture instead of implicit pipe context:

```jq
elif .toolArgs? != null then (.toolArgs as $ta | $ta | fromjson? // $ta)
```

This correctly passes through pre-parsed objects because `$ta` retains the original value regardless of the piped `fromjson?` evaluation context.

## Test Evidence

The jq pipeline test suite (`hooks/scripts/tests/test-jq-pipelines.sh`, test case 1d) explicitly documents this behavior: a pre-parsed object `toolArgs` yields `null`, confirming the current source-code semantics.
