#!/usr/bin/env bash
# Logs tool usage and subagent lifecycle events for Ralph-v2 sessions.
# Receives hook event JSON via stdin, appends JSONL to session log.
#
# Env: RALPH_LOG_PAYLOAD=true to include tool input in log entries.
set -euo pipefail

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

LOG_DIR="${SESSION_ROOT}/${SESSION_ID}/logs"
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
        if [ "${RALPH_LOG_PAYLOAD:-}" = "true" ]; then
            TOOL_INPUT=$(echo "$INPUT" | jq -c '.toolInput // null')
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
