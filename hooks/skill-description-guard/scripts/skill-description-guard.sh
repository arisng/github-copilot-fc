#!/usr/bin/env bash
# Validates that SKILL.md description fields do not exceed 1024 characters.
# PostToolUse hook — non-blocking warning via additionalContext output.
# POSIX-portable: uses [[:space:]] instead of GNU \s, requires jq for JSON.
set -euo pipefail

MAX_LENGTH=1024

# Check for jq dependency
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

INPUT=$(cat)

# Exit early if no input
if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# Guard against malformed JSON
if ! echo "$INPUT" | jq -e '.' >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# Determine tool name (VS Code: tool_name, CLI: toolName)
TOOL_NAME=""
if echo "$INPUT" | jq -e '.tool_name' >/dev/null 2>&1; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
elif echo "$INPUT" | jq -e '.toolName' >/dev/null 2>&1; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
fi

# Write tools across runtimes
case "$TOOL_NAME" in
  write_file|replace_string_in_file|multi_replace_string_in_file|create|edit) ;;
  *) echo '{}'; exit 0 ;;
esac

# Extract tool input object (VS Code: tool_input, CLI: toolArgs)
TOOL_INPUT=""
if echo "$INPUT" | jq -e '.tool_input' >/dev/null 2>&1; then
  TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')
elif echo "$INPUT" | jq -e '.toolArgs' >/dev/null 2>&1; then
  TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs')
  if echo "$TOOL_ARGS" | jq -e '.' >/dev/null 2>&1; then
    TOOL_INPUT="$TOOL_ARGS"
  fi
fi

if [ -z "$TOOL_INPUT" ] || [ "$TOOL_INPUT" = "null" ]; then
  echo '{}'
  exit 0
fi

# Extract file path (file_path, filePath, path)
FILE_PATH=""
for key in file_path filePath path; do
  val=$(echo "$TOOL_INPUT" | jq -r ".$key // empty" 2>/dev/null)
  if [ -n "$val" ]; then
    FILE_PATH="$val"
    break
  fi
done

if [ -z "$FILE_PATH" ]; then
  echo '{}'
  exit 0
fi

# Only fire for SKILL.md files
case "$FILE_PATH" in
  *SKILL.md) ;;
  *) echo '{}'; exit 0 ;;
esac

# Extract content (file_text, fileText, content, text, new_str, newText, new_string)
CONTENT=""
for key in file_text fileText content text new_str newText new_string; do
  val=$(echo "$TOOL_INPUT" | jq -r ".$key // empty" 2>/dev/null)
  if [ -n "$val" ]; then
    CONTENT="$val"
    break
  fi
done

if [ -z "$CONTENT" ]; then
  echo '{}'
  exit 0
fi

# Extract description from content (handles both full files and partial edits)
extract_description() {
  local text="$1"
  local in_folded=0
  local desc=""

  while IFS= read -r line; do
    # Folded block scalar (>-)
    if echo "$line" | grep -qE '^[[:space:]]*description[[:space:]]*:[[:space:]]*>-'; then
      in_folded=1
      continue
    fi
    if [ "$in_folded" -eq 1 ]; then
      # Continuation line: indented content or blank line
      if echo "$line" | grep -qE '^[[:space:]]+[[:alnum:]]' || [ -z "${line//[[:space:]]/}" ]; then
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
        if [ -n "$desc" ]; then
          desc="$desc $trimmed"
        else
          desc="$trimmed"
        fi
        continue
      else
        in_folded=0
        break
      fi
    fi
    # Double-quoted description
    if echo "$line" | grep -qE '^[[:space:]]*description[[:space:]]*:[[:space:]]*"'; then
      desc=$(echo "$line" | sed 's/.*description[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
      break
    fi
    # Single-quoted description
    if echo "$line" | grep -qE "^[[:space:]]*description[[:space:]]*:[[:space:]]*'"; then
      desc=$(echo "$line" | sed "s/.*description[[:space:]]*:[[:space:]]*'\(.*\)'.*/\1/")
      break
    fi
    # Bare description (no quotes)
    if echo "$line" | grep -qE '^[[:space:]]*description[[:space:]]*:[[:space:]]+.+'; then
      desc=$(echo "$line" | sed 's/.*description[[:space:]]*:[[:space:]]*//')
      break
    fi
  done <<< "$text"

  echo "$desc"
}

# Try full frontmatter extraction first (full-file writes with --- delimiters)
FRONTMATTER=$(echo "$CONTENT" | awk '
  BEGIN { in_fm=0; count=0 }
  /^---$/ { count++; if(count==1) { in_fm=1; next } else { in_fm=0; next } }
  in_fm { print }
')

DESCRIPTION=""
if [ -n "$FRONTMATTER" ]; then
  DESCRIPTION=$(extract_description "$FRONTMATTER")
fi

# If no frontmatter found, try partial-edit extraction (replacement fragments
# that don't contain --- delimiters but still contain a description line)
if [ -z "$DESCRIPTION" ]; then
  DESCRIPTION=$(extract_description "$CONTENT")
fi

if [ -z "$DESCRIPTION" ]; then
  echo '{}'
  exit 0
fi

# Check length
LENGTH=${#DESCRIPTION}
if [ "$LENGTH" -gt "$MAX_LENGTH" ]; then
  MSG="SKILL.md description is $LENGTH characters (limit: $MAX_LENGTH). Please trim the description field to no more than $MAX_LENGTH characters."
  jq -n --arg msg "$MSG" '{additionalContext: $msg}'
else
  echo '{}'
fi

exit 0
