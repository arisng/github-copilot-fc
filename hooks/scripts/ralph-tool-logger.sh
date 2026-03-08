#!/usr/bin/env bash
# Logs tool usage and subagent lifecycle events for Ralph-v2 sessions.
# Receives hook event JSON via stdin, appends JSONL to iteration log when possible.
# Falls back to the session log if iteration metadata cannot be resolved.
#
# Env: RALPH_LOG_PAYLOAD=true to include tool input in log entries.
set -euo pipefail

should_log_payload() {
    local event_name="$1"
    local payload_mode="${RALPH_LOG_PAYLOAD:-}"

    if [ "$payload_mode" = "false" ]; then
        return 1
    fi

    if [ "$payload_mode" = "true" ]; then
        return 0
    fi

    case "$event_name" in
        PreToolUse|PostToolUse)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

extract_tool_input_json() {
    local input_json="$1"
    local tool_input_json

    if tool_input_json=$(printf '%s' "$input_json" | jq -c '.toolInput // null' 2>/dev/null); then
        printf '%s\n' "$tool_input_json"
        return
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
        tool_input_json=$(printf '%s' "$input_json" | powershell.exe -NoProfile -Command '$json = [Console]::In.ReadToEnd(); try { $data = $json | ConvertFrom-Json; if ($null -eq $data.toolInput) { Write-Output ''null'' } else { $data.toolInput | ConvertTo-Json -Compress -Depth 10 } } catch { Write-Output ''null'' }' | tr -d '\r')
        printf '%s\n' "$tool_input_json"
        return
    fi

    printf 'null\n'
}

resolve_log_dir() {
    local session_root="$1"
    local session_id="$2"
    local session_path="${session_root}/${session_id}"
    local fallback_dir="${session_path}/logs"
    local metadata_path="${session_path}/metadata.yaml"
    local iteration

    if [ ! -f "$metadata_path" ]; then
        printf '%s\n' "$fallback_dir"
        return
    fi

    iteration=$(sed -nE 's/^iteration:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$metadata_path" | head -n 1 || true)
    if [ -z "$iteration" ]; then
        printf '%s\n' "$fallback_dir"
        return
    fi

    printf '%s\n' "${session_path}/iterations/${iteration}/logs"
}

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
EVENT_NAME=$(echo "$INPUT" | jq -r '.hookEventName // empty')
TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // empty')

SESSION_ROOT="${CWD}/.ralph-sessions"
ACTIVE_SESSION_FILE="${SESSION_ROOT}/.active-session"
HOOK_STATE_DIR="${SESSION_ROOT}/.hook-state"

if [ ! -f "$ACTIVE_SESSION_FILE" ]; then
    echo '{"continue":true}'
    exit 0
fi

SESSION_ID=$(tr -d '[:space:]' < "$ACTIVE_SESSION_FILE")
if [ -z "$SESSION_ID" ]; then
    echo '{"continue":true}'
    exit 0
fi

LOG_DIR=$(resolve_log_dir "$SESSION_ROOT" "$SESSION_ID")
LOG_FILE="${LOG_DIR}/tool-usage.jsonl"
ACTIVE_AGENT_FILE="${HOOK_STATE_DIR}/active-agent.txt"

mkdir -p "$LOG_DIR" "$HOOK_STATE_DIR"

AGENT=""
[ -f "$ACTIVE_AGENT_FILE" ] && AGENT=$(tr -d '[:space:]' < "$ACTIVE_AGENT_FILE")

case "$EVENT_NAME" in
    SubagentStart)
        AGENT_NAME=$(echo "$INPUT" | jq -r '.agentName // empty')
        if [ -n "$AGENT_NAME" ]; then
            printf '%s' "$AGENT_NAME" > "$ACTIVE_AGENT_FILE"
            AGENT="$AGENT_NAME"
        fi
        jq -cn --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --arg ev "$EVENT_NAME" --arg ag "$AGENT" \
            '{ts:$ts,sid:$sid,event:$ev,agent:$ag}' >> "$LOG_FILE"
        ;;
    SubagentStop)
        jq -cn --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --arg ev "$EVENT_NAME" --arg ag "$AGENT" \
            '{ts:$ts,sid:$sid,event:$ev,agent:$ag}' >> "$LOG_FILE"
        rm -f "$ACTIVE_AGENT_FILE"
        ;;
    PreToolUse|PostToolUse)
        TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // empty')
        if should_log_payload "$EVENT_NAME"; then
            TOOL_INPUT=$(extract_tool_input_json "$INPUT")
            jq -cn --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --arg ev "$EVENT_NAME" \
                --arg ag "$AGENT" --arg tool "$TOOL_NAME" --argjson input "$TOOL_INPUT" \
                '{ts:$ts,sid:$sid,event:$ev,agent:$ag,tool:$tool,input:$input}' >> "$LOG_FILE"
        else
            jq -cn --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --arg ev "$EVENT_NAME" \
                --arg ag "$AGENT" --arg tool "$TOOL_NAME" \
                '{ts:$ts,sid:$sid,event:$ev,agent:$ag,tool:$tool}' >> "$LOG_FILE"
        fi
        ;;
    *)
        jq -cn --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --arg ev "$EVENT_NAME" \
            '{ts:$ts,sid:$sid,event:$ev}' >> "$LOG_FILE"
        ;;
esac

echo '{"continue":true}'
exit 0
