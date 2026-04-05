#!/usr/bin/env bash
# ralph-init.sh — Initialize ralph persistent execution state for a session
# Usage: ralph-init.sh <session-id> [max-iterations]
#
# Creates the ralph state file that ralph-stop-hook.sh reads.
# Called by dispatch.sh when --ralph flag is used.

set -euo pipefail

SESSION_ID="${1:?Usage: ralph-init.sh <session-id> [max-iterations]}"
MAX_ITERATIONS="${2:-50}"

RALPH_DIR="${HOME}/.openclaw/shared-context/ralph"
mkdir -p "$RALPH_DIR"

STATE_FILE="${RALPH_DIR}/${SESSION_ID}.json"
NOW=$(date -u +%FT%TZ)

cat > "${STATE_FILE}.tmp" <<EOF
{
  "session_id": "${SESSION_ID}",
  "active": true,
  "iteration": 0,
  "max_iterations": ${MAX_ITERATIONS},
  "created_at": "${NOW}",
  "last_checked_at": "${NOW}"
}
EOF

mv "${STATE_FILE}.tmp" "$STATE_FILE"
echo "Ralph initialized: ${STATE_FILE} (max ${MAX_ITERATIONS} iterations)"
