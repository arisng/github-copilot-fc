#!/usr/bin/env bash
# Logs tool usage and subagent lifecycle events for Ralph-v2 sessions.
# Receives hook event JSON via stdin, appends JSONL to iteration logs when possible.
# Falls back to the session log if iteration metadata cannot be resolved.
#
# Env: RALPH_LOG_PAYLOAD=true to include tool arguments and results in log entries.
set -euo pipefail

normalize_event_name() {
    case "$1" in
        PreToolUse|preToolUse) printf 'preToolUse\n' ;;
        PostToolUse|postToolUse) printf 'postToolUse\n' ;;
        SubagentStart|subagentStart) printf 'subagentStart\n' ;;
        SubagentStop|subagentStop) printf 'subagentStop\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

to_iso_timestamp() {
    local ts="$1"

    if [ -z "$ts" ] || [ "$ts" = "null" ]; then
        printf 'null\n'
        return
    fi

    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        if [ "$ts" -ge 1000000000000 ] 2>/dev/null; then
            if command -v python3 >/dev/null 2>&1; then
                python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]) / 1000, datetime.timezone.utc).isoformat().replace("+00:00", "Z"))' "$ts"
                return
            fi
        fi

        if [ "$ts" -ge 1000000000 ] 2>/dev/null; then
            if command -v python3 >/dev/null 2>&1; then
                python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).isoformat().replace("+00:00", "Z"))' "$ts"
                return
            fi
        fi
    fi

    printf 'null\n'
}

ensure_state_file() {
    local state_file="$1"

    if [ ! -f "$state_file" ]; then
        printf '{"activeAgents":{},"lastAgent":null}' > "$state_file"
    fi
}

resolve_agent() {
    local state_file="$1"
    local transcript_path="$2"
    local event_agent_name="$3"

    if [ -n "$event_agent_name" ]; then
        printf '%s\n' "$event_agent_name"
        return
    fi

    if [ -n "$transcript_path" ]; then
        local transcript_agent
        transcript_agent=$(jq -r --arg tp "$transcript_path" '.activeAgents[$tp] // empty' "$state_file")
        if [ -n "$transcript_agent" ]; then
            printf '%s\n' "$transcript_agent"
            return
        fi
    fi

    jq -r '.lastAgent // empty' "$state_file"
}

should_log_payload() {
    local payload_mode="${RALPH_LOG_PAYLOAD:-}"

    if [ "$payload_mode" = "false" ]; then
        return 1
    fi

    if [ "$payload_mode" = "true" ]; then
        return 0
    fi

    return 1
}

extract_tool_args_json() {
    local input_json="$1"
    local tool_args_json

    if tool_args_json=$(printf '%s' "$input_json" | jq -c 'if .toolInput? != null then .toolInput elif .toolArgs? != null then (.toolArgs | fromjson? // .toolArgs) else null end' 2>/dev/null); then
        printf '%s\n' "$tool_args_json"
        return
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
        tool_args_json=$(printf '%s' "$input_json" | powershell.exe -NoProfile -Command '$json = [Console]::In.ReadToEnd(); try { $data = $json | ConvertFrom-Json; if ($null -ne $data.toolInput) { $data.toolInput | ConvertTo-Json -Compress -Depth 10 } elseif ($null -ne $data.toolArgs) { try { $data.toolArgs | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10 } catch { $data.toolArgs | ConvertTo-Json -Compress } } else { Write-Output ''null'' } } catch { Write-Output ''null'' }' | tr -d '\r')
        printf '%s\n' "$tool_args_json"
        return
    fi

    printf 'null\n'
}

extract_tool_result_json() {
    local input_json="$1"

    if printf '%s' "$input_json" | jq -c '.toolResult // .toolResponse // null' 2>/dev/null; then
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
TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // empty')
EVENT_NAME_RAW=$(echo "$INPUT" | jq -r '.hookEventName // empty')
EVENT_NAME=$(normalize_event_name "$EVENT_NAME_RAW")
SESSION_ID_FROM_EVENT=$(echo "$INPUT" | jq -r '.sessionId // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty')

SESSION_ROOT="${CWD}/.ralph-sessions"
ACTIVE_SESSION_FILE="${SESSION_ROOT}/.active-session"
HOOK_STATE_DIR="${SESSION_ROOT}/.hook-state"

if [ ! -f "$ACTIVE_SESSION_FILE" ]; then
    echo '{"continue":true}'
    exit 0
fi

SESSION_ID="$SESSION_ID_FROM_EVENT"
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(tr -d '[:space:]' < "$ACTIVE_SESSION_FILE")
fi

if [ -z "$SESSION_ID" ]; then
    echo '{"continue":true}'
    exit 0
fi

LOG_DIR=$(resolve_log_dir "$SESSION_ROOT" "$SESSION_ID")
TOOL_LOG_FILE="${LOG_DIR}/tool-usage.jsonl"
SUBAGENT_LOG_FILE="${LOG_DIR}/subagent-usage.jsonl"
HOOK_STATE_FILE="${HOOK_STATE_DIR}/active-agents.json"

mkdir -p "$LOG_DIR" "$HOOK_STATE_DIR"
ensure_state_file "$HOOK_STATE_FILE"

AGENT_NAME=$(echo "$INPUT" | jq -r '.agentName // empty')
AGENT=$(resolve_agent "$HOOK_STATE_FILE" "$TRANSCRIPT_PATH" "$AGENT_NAME")
TS_ISO=$(to_iso_timestamp "$TIMESTAMP")

case "$EVENT_NAME" in
    subagentStart)
        if [ -n "$AGENT" ] && [ -n "$TRANSCRIPT_PATH" ]; then
            tmp_state=$(mktemp)
            jq --arg tp "$TRANSCRIPT_PATH" --arg ag "$AGENT" '.activeAgents[$tp] = $ag | .lastAgent = $ag' "$HOOK_STATE_FILE" > "$tmp_state"
            mv "$tmp_state" "$HOOK_STATE_FILE"
        fi
        jq -cn \
            --arg ts "$TIMESTAMP" \
            --arg ts_iso "$TS_ISO" \
            --arg sid "$SESSION_ID" \
            --arg ev "$EVENT_NAME" \
            --arg cwd "$CWD" \
            --arg ag "$AGENT" \
            --arg tp "$TRANSCRIPT_PATH" \
            '{ts:$ts,ts_iso:($ts_iso | select(. != "null")),sid:$sid,event:$ev,cwd:$cwd,agent:($ag | select(. != "")),transcript_path:($tp | select(. != ""))}' >> "$SUBAGENT_LOG_FILE"
        ;;
    subagentStop)
        STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // empty')
        jq -cn \
            --arg ts "$TIMESTAMP" \
            --arg ts_iso "$TS_ISO" \
            --arg sid "$SESSION_ID" \
            --arg ev "$EVENT_NAME" \
            --arg cwd "$CWD" \
            --arg ag "$AGENT" \
            --arg tp "$TRANSCRIPT_PATH" \
            --arg sha "$STOP_HOOK_ACTIVE" \
            '{ts:$ts,ts_iso:($ts_iso | select(. != "null")),sid:$sid,event:$ev,cwd:$cwd,agent:($ag | select(. != "")),transcript_path:($tp | select(. != "")),stop_hook_active:(if $sha == "" then empty else ($sha == "true") end)}' >> "$SUBAGENT_LOG_FILE"
        if [ -n "$TRANSCRIPT_PATH" ]; then
            tmp_state=$(mktemp)
            jq --arg tp "$TRANSCRIPT_PATH" 'del(.activeAgents[$tp]) | .lastAgent = ((.activeAgents | to_entries | last | .value) // null)' "$HOOK_STATE_FILE" > "$tmp_state"
            mv "$tmp_state" "$HOOK_STATE_FILE"
        fi
        ;;
    preToolUse|postToolUse)
        TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // empty')
        TOOL_ARGS='null'
        TOOL_RESULT='null'
        RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType // .toolResponse.resultType // empty')
        RESULT_TEXT=$(echo "$INPUT" | jq -r '.toolResult.textResultForLlm // .toolResponse.textResultForLlm // empty')

        if should_log_payload; then
            TOOL_ARGS=$(extract_tool_args_json "$INPUT")
            TOOL_RESULT=$(extract_tool_result_json "$INPUT")
        fi

        jq -cn \
            --arg ts "$TIMESTAMP" \
            --arg ts_iso "$TS_ISO" \
            --arg sid "$SESSION_ID" \
            --arg ev "$EVENT_NAME" \
            --arg cwd "$CWD" \
            --arg ag "$AGENT" \
            --arg tp "$TRANSCRIPT_PATH" \
            --arg tool "$TOOL_NAME" \
            --arg rt "$RESULT_TYPE" \
            --arg txt "$RESULT_TEXT" \
            --argjson args "$TOOL_ARGS" \
            --argjson result "$TOOL_RESULT" \
            '{ts:$ts,ts_iso:($ts_iso | select(. != "null")),sid:$sid,event:$ev,cwd:$cwd,agent:($ag | select(. != "")),transcript_path:($tp | select(. != "")),tool:($tool | select(. != "")),result_type:($rt | select(. != "")),result_text:($txt | select(. != "")),tool_args:(if $args == null then empty else $args end),tool_result:(if $result == null then empty else $result end)}' >> "$TOOL_LOG_FILE"
        ;;
esac

echo '{"continue":true}'
exit 0
