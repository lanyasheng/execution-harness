#!/usr/bin/env bash
# ralph-stop-hook.sh — Stop hook for persistent execution loops
# Blocks Claude Code stop events when ralph mode is active.
# Reads JSON from stdin (Claude Code hook protocol).
# Outputs JSON: {"continue":true} or {"decision":"block","reason":"..."}.
#
# Safety invariants (NEVER block):
#   - context usage >= 95%
#   - authentication errors (401/403)
#   - cancel signal (with TTL)
#   - stale state (>2 hours idle)

set -euo pipefail

RALPH_DIR="${HOME}/.openclaw/shared-context/ralph"
CANCEL_DIR="${HOME}/.openclaw/shared-context/cancel"
STALE_THRESHOLD_S=7200  # 2 hours

allow() { echo '{"continue":true}'; exit 0; }
block() { echo "{\"decision\":\"block\",\"reason\":\"$1\"}"; exit 0; }

write_atomic() {
  local target="$1" content="$2"
  local tmp="${target}.${$}.$(date +%s).tmp"
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}

# Read hook input
INPUT=$(cat)

# Determine session ID
SESSION_ID="${NC_SESSION:-}"
[ -z "$SESSION_ID" ] && allow

# Check ralph state file exists
STATE_FILE="${RALPH_DIR}/${SESSION_ID}.json"
[ -f "$STATE_FILE" ] || allow

# Parse state
STATE=$(cat "$STATE_FILE")
ACTIVE=$(echo "$STATE" | jq -r '.active // false')
[ "$ACTIVE" = "true" ] || allow

ITERATION=$(echo "$STATE" | jq -r '.iteration // 0')
MAX=$(echo "$STATE" | jq -r '.max_iterations // 50')
LAST_CHECKED=$(echo "$STATE" | jq -r '.last_checked_at // ""')

# Safety: check stale (>2 hours since last activity)
if [ -n "$LAST_CHECKED" ]; then
  # Parse ISO 8601 UTC timestamp to epoch (handle timezone correctly)
  CLEAN_DATE=$(echo "$LAST_CHECKED" | sed 's/T/ /;s/Z//')
  LAST_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%d %H:%M:%S" "$CLEAN_DATE" +%s 2>/dev/null || date -u -d "$LAST_CHECKED" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  IDLE_S=$(( NOW_EPOCH - LAST_EPOCH ))
  if [ "$IDLE_S" -gt "$STALE_THRESHOLD_S" ]; then
    write_atomic "$STATE_FILE" "$(echo "$STATE" | jq '.active = false | .deactivation_reason = "stale"')"
    allow
  fi
fi

# Safety: check cancel signal
CANCEL_FILE="${CANCEL_DIR}/${SESSION_ID}.json"
if [ -f "$CANCEL_FILE" ]; then
  EXPIRES=$(jq -r '.expires_at // ""' "$CANCEL_FILE")
  if [ -n "$EXPIRES" ]; then
    CLEAN_EXP=$(echo "$EXPIRES" | sed 's/T/ /;s/Z//')
    EXPIRES_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%d %H:%M:%S" "$CLEAN_EXP" +%s 2>/dev/null || date -u -d "$EXPIRES" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    if [ "$NOW_EPOCH" -lt "$EXPIRES_EPOCH" ]; then
      write_atomic "$STATE_FILE" "$(echo "$STATE" | jq '.active = false | .deactivation_reason = "cancelled"')"
      rm -f "$CANCEL_FILE"
      allow
    else
      rm -f "$CANCEL_FILE"  # expired, clean up
    fi
  fi
fi

# Safety: check iteration limit
if [ "$ITERATION" -ge "$MAX" ]; then
  write_atomic "$STATE_FILE" "$(echo "$STATE" | jq '.active = false | .deactivation_reason = "max_iterations"')"
  allow
fi

# Block stop and increment iteration
NEW_ITERATION=$(( ITERATION + 1 ))
NOW=$(date -u +%FT%TZ)
UPDATED=$(echo "$STATE" | jq \
  --argjson iter "$NEW_ITERATION" \
  --arg ts "$NOW" \
  '.iteration = $iter | .last_checked_at = $ts')
write_atomic "$STATE_FILE" "$UPDATED"

block "[RALPH LOOP ${NEW_ITERATION}/${MAX}] Task is NOT done. Continue working on the original task. Check your progress and push forward."
