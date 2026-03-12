#!/usr/bin/env bash
# Test suite for jq conditional merging pipelines in ralph-tool-logger.sh
# Prerequisite: jq 1.6+ (uses fromjson?, alternative operator //, conditional merging)
#
# Tests 3 isolated pipelines:
#   1. extract_tool_args_json — reads tool_input/toolInput/toolArgs with fromjson? fallback
#   2. extract_tool_result_json — reads tool_result/toolResult/tool_response/toolResponse
#   3. Main JSONL assembly — conditional + (if ... then {k:v} else {} end) for optional fields
#
# Usage: bash hooks/ralph-tool-logger/scripts/tests/test-jq-pipelines.sh
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"

    if diff <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n' "$test_name"
        diff <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") || true
    fi
}

# ---------------------------------------------------------------------------
# Pipeline 1: extract_tool_args_json
# jq expression extracted from ralph-tool-logger.sh extract_tool_args_json()
# ---------------------------------------------------------------------------
JQ_TOOL_ARGS='if .tool_input? != null then .tool_input elif .toolInput? != null then .toolInput elif .toolArgs? != null then (.toolArgs | fromjson? // .toolArgs) else null end'

echo "=== Pipeline 1: extract_tool_args_json ==="

# 1a: tool_input takes priority over other fields
# Build fixture with jq to embed a JSON-string toolArgs (avoids shell escaping)
FIXTURE_1A=$(jq -cn --arg ta '{"x":1}' '{"tool_input":{"path":"/tmp"},"toolArgs":$ta}')
assert_eq "tool_input takes priority" \
    "$(printf '%s' "$FIXTURE_1A" | jq -c "$JQ_TOOL_ARGS")" \
    '{"path":"/tmp"}'

# 1b: toolInput used when tool_input absent
assert_eq "toolInput fallback" \
    "$(printf '%s' '{"toolInput":{"cmd":"ls"}}' | jq -c "$JQ_TOOL_ARGS")" \
    '{"cmd":"ls"}'

# 1c: toolArgs as JSON string — fromjson? parses it
FIXTURE_1C=$(jq -cn --arg ta '{"file":"a.txt"}' '{"toolArgs":$ta}')
assert_eq "toolArgs JSON string parsed via fromjson" \
    "$(printf '%s' "$FIXTURE_1C" | jq -c "$JQ_TOOL_ARGS")" \
    '{"file":"a.txt"}'

# 1d: toolArgs as pre-parsed object — fromjson? fails on non-string input,
#     fallback evaluates .toolArgs in piped context (object has no .toolArgs key) → null.
#     This documents actual jq behavior of the source pipeline.
assert_eq "toolArgs pre-parsed object returns null (piped context)" \
    "$(printf '%s' '{"toolArgs":{"file":"b.txt"}}' | jq -c "$JQ_TOOL_ARGS")" \
    'null'

# 1e: no tool args fields present — returns null
assert_eq "no tool args fields returns null" \
    "$(printf '%s' '{"other":"data"}' | jq -c "$JQ_TOOL_ARGS")" \
    'null'

echo ""

# ---------------------------------------------------------------------------
# Pipeline 2: extract_tool_result_json
# jq expression extracted from ralph-tool-logger.sh extract_tool_result_json()
# ---------------------------------------------------------------------------
JQ_TOOL_RESULT='.tool_result // .toolResult // .tool_response // .toolResponse // null'

echo "=== Pipeline 2: extract_tool_result_json ==="

# 2a: tool_result present
assert_eq "tool_result field used" \
    "$(printf '%s' '{"tool_result":{"ok":true}}' | jq -c "$JQ_TOOL_RESULT")" \
    '{"ok":true}'

# 2b: toolResult used when tool_result absent
assert_eq "toolResult fallback" \
    "$(printf '%s' '{"toolResult":"success"}' | jq -c "$JQ_TOOL_RESULT")" \
    '"success"'

# 2c: tool_response used when tool_result and toolResult absent
assert_eq "tool_response fallback" \
    "$(printf '%s' '{"tool_response":{"status":200}}' | jq -c "$JQ_TOOL_RESULT")" \
    '{"status":200}'

# 2d: toolResponse used as last resort
assert_eq "toolResponse last-resort fallback" \
    "$(printf '%s' '{"toolResponse":[1,2,3]}' | jq -c "$JQ_TOOL_RESULT")" \
    '[1,2,3]'

# 2e: no result fields — returns null
assert_eq "no result fields returns null" \
    "$(printf '%s' '{"unrelated":"value"}' | jq -c "$JQ_TOOL_RESULT")" \
    'null'

echo ""

# ---------------------------------------------------------------------------
# Pipeline 3: Main JSONL assembly — conditional merging of optional fields
# Tests the jq -cn pattern used for preToolUse/postToolUse, subagentStart,
# and subagentStop events.
# ---------------------------------------------------------------------------
echo "=== Pipeline 3: Main JSONL assembly ==="

# Reusable jq JSONL assembly expression for tool events (preToolUse/postToolUse)
JQ_TOOL_ASSEMBLY='{ts:$ts,sid:$sid,event:$ev,cwd:$cwd,tool:$tool}
+ (if $ts_iso != "null" then {ts_iso:$ts_iso} else {} end)
+ (if $ag != "" then {agent:$ag} else {} end)
+ (if $at != "" then {agent_type:$at} else {} end)
+ (if $tp != "" then {transcript_path:$tp} else {} end)
+ (if $rt != "" then {result_type:$rt} else {} end)
+ (if $txt != "" then {result_text:$txt} else {} end)
+ (if $args != null then {tool_args:$args} else {} end)
+ (if $result != null then {tool_result:$result} else {} end)'

# Reusable jq JSONL assembly expression for subagentStart
JQ_START_ASSEMBLY='{ts:$ts,sid:$sid,event:$ev,cwd:$cwd}
+ (if $ts_iso != "null" then {ts_iso:$ts_iso} else {} end)
+ (if $ag != "" then {agent:$ag} else {} end)
+ (if $at != "" then {agent_type:$at} else {} end)
+ (if $tp != "" then {transcript_path:$tp} else {} end)'

# Reusable jq JSONL assembly expression for subagentStop
JQ_STOP_ASSEMBLY='{ts:$ts,sid:$sid,event:$ev,cwd:$cwd}
+ (if $ts_iso != "null" then {ts_iso:$ts_iso} else {} end)
+ (if $ag != "" then {agent:$ag} else {} end)
+ (if $at != "" then {agent_type:$at} else {} end)
+ (if $tp != "" then {transcript_path:$tp} else {} end)
+ (if $sha != "" then {stop_hook_active:($sha == "true")} else {} end)'

# 3a: Tool event — all optional fields empty → only base fields
assert_eq "tool event: all optional empty" \
    "$(jq -cn \
        --arg ts "1234567890" \
        --arg ts_iso "null" \
        --arg sid "sess-1" \
        --arg ev "postToolUse" \
        --arg cwd "/workspace" \
        --arg ag "" \
        --arg tp "" \
        --arg at "" \
        --arg tool "readFile" \
        --arg rt "" \
        --arg txt "" \
        --argjson args 'null' \
        --argjson result 'null' \
        "$JQ_TOOL_ASSEMBLY")" \
    '{"ts":"1234567890","sid":"sess-1","event":"postToolUse","cwd":"/workspace","tool":"readFile"}'

# 3b: Tool event — all optional fields populated
assert_eq "tool event: all optional populated" \
    "$(jq -cn \
        --arg ts "1710000000000" \
        --arg ts_iso "2025-03-10T00:00:00Z" \
        --arg sid "260310-120000" \
        --arg ev "preToolUse" \
        --arg cwd "/work" \
        --arg ag "executor" \
        --arg tp "/transcripts/1.json" \
        --arg at "sub" \
        --arg tool "editFile" \
        --arg rt "text" \
        --arg txt "File edited" \
        --argjson args '{"path":"/tmp/x"}' \
        --argjson result '{"ok":true}' \
        "$JQ_TOOL_ASSEMBLY")" \
    '{"ts":"1710000000000","sid":"260310-120000","event":"preToolUse","cwd":"/work","tool":"editFile","ts_iso":"2025-03-10T00:00:00Z","agent":"executor","agent_type":"sub","transcript_path":"/transcripts/1.json","result_type":"text","result_text":"File edited","tool_args":{"path":"/tmp/x"},"tool_result":{"ok":true}}'

# 3c: Tool event — stringified "null" ts_iso is omitted
assert_eq "tool event: stringified null ts_iso omitted" \
    "$(jq -cn \
        --arg ts "999" \
        --arg ts_iso "null" \
        --arg sid "s1" \
        --arg ev "postToolUse" \
        --arg cwd "/" \
        --arg ag "planner" \
        --arg tp "" \
        --arg at "" \
        --arg tool "runCmd" \
        --arg rt "" \
        --arg txt "" \
        --argjson args 'null' \
        --argjson result 'null' \
        "$JQ_TOOL_ASSEMBLY")" \
    '{"ts":"999","sid":"s1","event":"postToolUse","cwd":"/","tool":"runCmd","agent":"planner"}'

# 3d: Tool event — empty agent omitted from output
assert_eq "tool event: empty agent omitted" \
    "$(jq -cn \
        --arg ts "100" \
        --arg ts_iso "2025-01-01T00:00:00Z" \
        --arg sid "s2" \
        --arg ev "preToolUse" \
        --arg cwd "/c" \
        --arg ag "" \
        --arg tp "" \
        --arg at "" \
        --arg tool "search" \
        --arg rt "" \
        --arg txt "" \
        --argjson args 'null' \
        --argjson result 'null' \
        "$JQ_TOOL_ASSEMBLY")" \
    '{"ts":"100","sid":"s2","event":"preToolUse","cwd":"/c","tool":"search","ts_iso":"2025-01-01T00:00:00Z"}'

# 3e: Tool event — null tool_args omitted, non-null tool_result included
assert_eq "tool event: null args omitted, result included" \
    "$(jq -cn \
        --arg ts "200" \
        --arg ts_iso "null" \
        --arg sid "s2" \
        --arg ev "postToolUse" \
        --arg cwd "/" \
        --arg ag "" \
        --arg tp "" \
        --arg at "" \
        --arg tool "ls" \
        --arg rt "text" \
        --arg txt "file.txt" \
        --argjson args 'null' \
        --argjson result '{"files":["a","b"]}' \
        "$JQ_TOOL_ASSEMBLY")" \
    '{"ts":"200","sid":"s2","event":"postToolUse","cwd":"/","tool":"ls","result_type":"text","result_text":"file.txt","tool_result":{"files":["a","b"]}}'

# 3f: subagentStart — agent and transcript_path populated, agent_type empty
assert_eq "subagentStart: agent + transcript, no agent_type" \
    "$(jq -cn \
        --arg ts "5000" \
        --arg ts_iso "2025-06-01T12:00:00Z" \
        --arg sid "s3" \
        --arg ev "subagentStart" \
        --arg cwd "/proj" \
        --arg ag "reviewer" \
        --arg tp "/t/review.json" \
        --arg at "" \
        "$JQ_START_ASSEMBLY")" \
    '{"ts":"5000","sid":"s3","event":"subagentStart","cwd":"/proj","ts_iso":"2025-06-01T12:00:00Z","agent":"reviewer","transcript_path":"/t/review.json"}'

# 3g: subagentStop — with stop_hook_active=true boolean merging
assert_eq "subagentStop: stop_hook_active true merging" \
    "$(jq -cn \
        --arg ts "6000" \
        --arg ts_iso "null" \
        --arg sid "s3" \
        --arg ev "subagentStop" \
        --arg cwd "/proj" \
        --arg ag "reviewer" \
        --arg tp "/t/review.json" \
        --arg at "sub" \
        --arg sha "true" \
        "$JQ_STOP_ASSEMBLY")" \
    '{"ts":"6000","sid":"s3","event":"subagentStop","cwd":"/proj","agent":"reviewer","agent_type":"sub","transcript_path":"/t/review.json","stop_hook_active":true}'

# 3h: subagentStop — stop_hook_active=false produces boolean false
assert_eq "subagentStop: stop_hook_active false" \
    "$(jq -cn \
        --arg ts "7000" \
        --arg ts_iso "null" \
        --arg sid "s4" \
        --arg ev "subagentStop" \
        --arg cwd "/proj" \
        --arg ag "" \
        --arg tp "" \
        --arg at "" \
        --arg sha "false" \
        "$JQ_STOP_ASSEMBLY")" \
    '{"ts":"7000","sid":"s4","event":"subagentStop","cwd":"/proj","stop_hook_active":false}'

# 3i: subagentStop — stop_hook_active empty (omitted from output)
assert_eq "subagentStop: stop_hook_active empty omitted" \
    "$(jq -cn \
        --arg ts "8000" \
        --arg ts_iso "null" \
        --arg sid "s5" \
        --arg ev "subagentStop" \
        --arg cwd "/proj" \
        --arg ag "exec" \
        --arg tp "" \
        --arg at "" \
        --arg sha "" \
        "$JQ_STOP_ASSEMBLY")" \
    '{"ts":"8000","sid":"s5","event":"subagentStop","cwd":"/proj","agent":"exec"}'

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "=== Summary ==="
printf 'Total: %d  Passed: %d  Failed: %d\n' "$TOTAL" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
