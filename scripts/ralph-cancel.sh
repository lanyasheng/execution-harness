#!/usr/bin/env bash
# ralph-cancel.sh — Send cancel signal with 30s TTL
# Usage: ralph-cancel.sh <session-id> [reason]

set -euo pipefail

SESSION_ID="${1:?Usage: ralph-cancel.sh <session-id> [reason]}"
REASON="${2:-user_abort}"

CANCEL_DIR="${HOME}/.openclaw/shared-context/cancel"
mkdir -p "$CANCEL_DIR"

NOW=$(date -u +%FT%TZ)
EXPIRES=$(date -u -v+30S +%FT%TZ 2>/dev/null || date -u -d '+30 seconds' +%FT%TZ)

CANCEL_FILE="${CANCEL_DIR}/${SESSION_ID}.json"
cat > "${CANCEL_FILE}.tmp" <<EOF
{
  "requested_at": "${NOW}",
  "expires_at": "${EXPIRES}",
  "reason": "${REASON}"
}
EOF

mv "${CANCEL_FILE}.tmp" "$CANCEL_FILE"
echo "Cancel signal sent for ${SESSION_ID} (expires in 30s)"
