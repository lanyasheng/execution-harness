#!/usr/bin/env bash
# denial-tracker.sh — PostToolUse hook: track permission denials by pattern
# Warns at 3 denials, suggests alternative at 5.

set -euo pipefail

SESSIONS_DIR="${HOME}/.openclaw/shared-context/sessions"
SOFT_THRESHOLD=3
HARD_THRESHOLD=5

INPUT=$(head -c 20000)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="${NC_SESSION:-}"
[ -z "$SESSION_ID" ] && exit 0

# Check if this was a denied action
WAS_DENIED=$(echo "$INPUT" | jq -r '.was_denied // .denied // false' 2>/dev/null)
[ "$WAS_DENIED" != "true" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null | head -c 200)
PATTERN="${TOOL}:${TOOL_INPUT}"

SESSION_DIR="${SESSIONS_DIR}/${SESSION_ID}"
STATE_FILE="${SESSION_DIR}/denials.json"
mkdir -p "$SESSION_DIR"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read or init state
if [ -f "$STATE_FILE" ]; then
  COUNT=$(jq -r --arg p "$PATTERN" '.patterns[$p].count // 0' "$STATE_FILE" 2>/dev/null)
else
  COUNT=0
fi
COUNT=$((COUNT + 1))

# Write state atomically
TMP="${STATE_FILE}.${$}.tmp"
if [ -f "$STATE_FILE" ]; then
  jq --arg p "$PATTERN" --argjson c "$COUNT" --arg t "$NOW" \
    '.patterns[$p] = {count: $c, last: $t}' "$STATE_FILE" > "$TMP"
else
  jq -n --arg p "$PATTERN" --argjson c "$COUNT" --arg t "$NOW" \
    '{patterns: {($p): {count: $c, last: $t}}}' > "$TMP"
fi
mv "$TMP" "$STATE_FILE"

# Output based on threshold
if [ "$COUNT" -ge "$HARD_THRESHOLD" ]; then
  jq -n --arg ctx "This action pattern '${TOOL}' has been denied ${COUNT} times. You MUST use a completely different approach. Do not rephrase — use a different tool or method entirely." \
    '{"hookSpecificOutput":{"additionalContext":$ctx}}'
elif [ "$COUNT" -ge "$SOFT_THRESHOLD" ]; then
  jq -n --arg ctx "WARNING: Action pattern '${TOOL}' denied ${COUNT} times. Consider an alternative approach." \
    '{"hookSpecificOutput":{"additionalContext":$ctx}}'
fi
