#!/usr/bin/env bash
# compaction-extract.sh — Stop hook: extract key decisions when context is near-full
# Writes session state to handoff document for post-compaction recovery.

set -euo pipefail

SESSIONS_DIR="${HOME}/.openclaw/shared-context/sessions"

INPUT=$(head -c 20000)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="${NC_SESSION:-}"
[ -z "$SESSION_ID" ] && echo '{"continue":true}' && exit 0

SESSION_DIR="${SESSIONS_DIR}/${SESSION_ID}"
HANDOFFS_DIR="${SESSION_DIR}/handoffs"
mkdir -p "$HANDOFFS_DIR"

# Check if context is near-full (from stop_reason or custom field)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // ""' 2>/dev/null)
CONTEXT_FULL=$(echo "$INPUT" | jq -r '.context_near_full // false' 2>/dev/null)

# Only extract when context is pressured
if [ "$CONTEXT_FULL" != "true" ] && [ "$STOP_REASON" != "context_full" ]; then
  echo '{"continue":true}'
  exit 0
fi

# Extract last assistant message as the knowledge to preserve
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null | head -c 5000)

TIMESTAMP=$(date +%s)
HANDOFF_FILE="${HANDOFFS_DIR}/pre-compact-${TIMESTAMP}.md"

cat > "$HANDOFF_FILE" << EOF
# Pre-Compaction Knowledge Extract
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Session: ${SESSION_ID}

## Last Context Summary
${LAST_MSG}
EOF

jq -n --arg ctx "Knowledge extracted to ${HANDOFF_FILE} before compaction." \
  '{"hookSpecificOutput":{"additionalContext":$ctx}}'
