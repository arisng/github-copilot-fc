---
category: how-to
---

# How to Test Hook Scripts Locally

This guide shows you how to test Ralph hook logger scripts locally using JSON fixtures, the jq pipeline test suite, and session-state guard edge cases.

## When to Use This Guide

Use this after modifying hook logger scripts (`ralph-tool-logger.sh` or `ralph-tool-logger.ps1`) or their jq pipelines, to verify correctness before publishing.

## Prerequisites

- **jq 1.6+** installed and available in bash (`jq --version` to check).
- **Bash** environment (native Linux, WSL, or Git Bash on Windows).
- Familiarity with the jq conditional merging pattern — see [jq Conditional Object Merging Pattern](../../reference/ralph/jq-conditional-object-merging-pattern.md).
- Familiarity with the session-state guard — see [Hook Session-State Validation Guard](../../reference/ralph/hook-session-state-validation-guard.md).

## Steps

### 1. Run the jq Pipeline Test Suite

The test suite at `hooks/ralph-tool-logger/scripts/tests/test-jq-pipelines.sh` isolates and tests all three jq merging pipelines used by the Bash logger:

```bash
bash hooks/ralph-tool-logger/scripts/tests/test-jq-pipelines.sh
```

Expected output ends with a pass/fail summary:

```
=== Results ===
Passed: 15
Failed: 0
```

All tests should pass. Any `FAIL` lines include a diff showing expected vs actual output.

### 2. Create a Test Fixture for Manual Testing

To test a specific event type manually, create a JSON payload that matches the hook event schema. For a `preToolUse` event:

```bash
cat <<'EOF' > /tmp/test-hook-payload.json
{
  "hookEventName": "preToolUse",
  "cwd": "/tmp/test-workspace",
  "timestamp": "1710000000000",
  "tool_name": "readFile",
  "toolArgs": "{\"path\":\"/tmp/file.txt\"}",
  "agent_id": "executor",
  "transcript_path": "/transcripts/1.json"
}
EOF
```

For a `subagentStart` event:

```bash
cat <<'EOF' > /tmp/test-hook-subagent.json
{
  "hookEventName": "subagentStart",
  "cwd": "/tmp/test-workspace",
  "timestamp": "1710000000000",
  "agent_id": "reviewer",
  "agent_type": "sub",
  "transcript_path": "/transcripts/2.json"
}
EOF
```

### 3. Set Up a Mock Session Directory

The logger requires an active session to write logs. Create a minimal session structure:

```bash
TEST_ROOT="/tmp/test-workspace/.ralph-sessions"
SESSION_ID="260310-120000"

mkdir -p "$TEST_ROOT/$SESSION_ID/iterations/1/logs"

# Create the active session pointer
echo -n "$SESSION_ID" > "$TEST_ROOT/.active-session"

# Create minimal metadata (iteration 1, active state)
cat > "$TEST_ROOT/$SESSION_ID/metadata.yaml" <<EOF
session_id: $SESSION_ID
state: IN_PROGRESS
iteration: 1
EOF
```

### 4. Run the Hook Script Against a Fixture

Pipe the test fixture into the logger:

```bash
cat /tmp/test-hook-payload.json | bash hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh
```

The script outputs `{"continue":true}` on success. Check the generated log:

```bash
cat "$TEST_ROOT/$SESSION_ID/iterations/1/logs/tool-usage.jsonl"
```

Each line is a valid JSON object. Verify with jq:

```bash
jq . "$TEST_ROOT/$SESSION_ID/iterations/1/logs/tool-usage.jsonl"
```

### 5. Validate Session-State Guard Edge Cases

The guard prevents logging to stale or completed sessions. Test each edge case:

**Missing `.active-session` file:**

```bash
rm "$TEST_ROOT/.active-session"
echo '{"hookEventName":"preToolUse","cwd":"/tmp/test-workspace","tool_name":"test"}' \
  | bash hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh
# Expected: {"continue":true} — no log written, no error
```

**Completed session (state: COMPLETE):**

```bash
echo -n "$SESSION_ID" > "$TEST_ROOT/.active-session"
sed -i 's/IN_PROGRESS/COMPLETE/' "$TEST_ROOT/$SESSION_ID/metadata.yaml"
echo '{"hookEventName":"preToolUse","cwd":"/tmp/test-workspace","tool_name":"test"}' \
  | bash hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh
# Expected: {"continue":true} + stderr warning about COMPLETE session
```

**Missing session directory:**

```bash
echo -n "nonexistent-session" > "$TEST_ROOT/.active-session"
echo '{"hookEventName":"preToolUse","cwd":"/tmp/test-workspace","tool_name":"test"}' \
  | bash hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh
# Expected: {"continue":true} + stderr warning about missing directory
```

**Missing `metadata.yaml` (fail-open):**

```bash
echo -n "$SESSION_ID" > "$TEST_ROOT/.active-session"
rm -f "$TEST_ROOT/$SESSION_ID/metadata.yaml"
echo '{"hookEventName":"preToolUse","cwd":"/tmp/test-workspace","tool_name":"test"}' \
  | bash hooks/ralph-tool-logger/scripts/ralph-tool-logger.sh
# Expected: {"continue":true} — logging proceeds (fail-open design)
```

In all cases, the script exits with code 0 and outputs `{"continue":true}`. The guard never blocks agent operations.

### 6. Clean Up Test Artifacts

```bash
rm -rf /tmp/test-workspace /tmp/test-hook-payload.json /tmp/test-hook-subagent.json
```

## Troubleshooting

**Problem: `jq: command not found`**
Install jq for your platform: `sudo apt install jq` (Debian/Ubuntu), `brew install jq` (macOS), or download from https://jqlang.github.io/jq/download/.

**Problem: Test suite reports FAIL with diff output**
The diff shows expected vs actual jq output. Check if your jq version is 1.6+ (`jq --version`). Older versions may not support `fromjson?` or the conditional merging syntax.

**Problem: Logger writes to `logs/` instead of `iterations/<N>/logs/`**
The logger falls back to the session-level `logs/` directory when `metadata.yaml` is missing or has no valid `iteration` field. Ensure your test fixture includes a `metadata.yaml` with an integer `iteration` value.

## See Also

- [jq Conditional Object Merging Pattern](../../reference/ralph/jq-conditional-object-merging-pattern.md) — why `+ (if ... then {k:v} else {} end)` is used instead of `select()`
- [Hook Session-State Validation Guard](../../reference/ralph/hook-session-state-validation-guard.md) — the 4-step validation sequence and fail-open design
