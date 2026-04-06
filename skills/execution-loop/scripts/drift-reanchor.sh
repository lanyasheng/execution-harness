#!/usr/bin/env bash
# drift-reanchor.sh — UserPromptSubmit hook: re-inject original task every N turns
# Prevents long-session drift by anchoring to the original task description.

set -euo pipefail

SESSIONS_DIR="${HOME}/.openclaw/shared-context/sessions"
INTERVAL="${REANCHOR_INTERVAL:-10}"

INPUT=$(head -c 20000)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="${NC_SESSION:-}"
[ -z "$SESSION_ID" ] && echo '{"continue":true}' && exit 0

SESSION_DIR="${SESSIONS_DIR}/${SESSION_ID}"
STATE_FILE="${SESSION_DIR}/reanchor.json"
mkdir -p "$SESSION_DIR"

# Get user prompt from input
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // .prompt // ""' 2>/dev/null)

# First call: save original task
if [ ! -f "$STATE_FILE" ]; then
  TMP="${STATE_FILE}.${$}.tmp"
  jq -n --arg task "$USER_PROMPT" --argjson count 1 \
    '{"original_task":$task,"turn_count":$count}' > "$TMP"
  mv "$TMP" "$STATE_FILE"
  echo '{"continue":true}'
  exit 0
fi

# Increment turn count
TURN_COUNT=$(jq -r '.turn_count // 0' "$STATE_FILE" 2>/dev/null)
TURN_COUNT=$((TURN_COUNT + 1))
ORIGINAL_TASK=$(jq -r '.original_task // ""' "$STATE_FILE" 2>/dev/null)

# Update state
TMP="${STATE_FILE}.${$}.tmp"
jq -n --arg task "$ORIGINAL_TASK" --argjson count "$TURN_COUNT" \
  '{"original_task":$task,"turn_count":$count}' > "$TMP"
mv "$TMP" "$STATE_FILE"

# Every N turns, re-inject task
if [ $((TURN_COUNT % INTERVAL)) -eq 0 ] && [ -n "$ORIGINAL_TASK" ]; then
  jq -n --arg ctx "TASK REMINDER (turn ${TURN_COUNT}): ${ORIGINAL_TASK}" \
    '{"hookSpecificOutput":{"additionalContext":$ctx}}'
else
  echo '{"continue":true}'
fi
