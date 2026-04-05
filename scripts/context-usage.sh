#!/usr/bin/env bash
# context-usage.sh — Estimate context window usage from transcript tail
# Usage: context-usage.sh <transcript-jsonl-path>
# Output: "Context usage: XX% (input/window tokens)" or nothing if unavailable

set -euo pipefail

TRANSCRIPT="${1:-}"
[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

SIZE=$(stat -f%z "$TRANSCRIPT" 2>/dev/null || stat -c%s "$TRANSCRIPT" 2>/dev/null || echo 0)
[ "$SIZE" -lt 4096 ] && exit 0

INPUT_TOKENS=$(tail -c 4096 "$TRANSCRIPT" | grep -o '"input_tokens":[0-9]*' | tail -1 | grep -o '[0-9]*' || true)
CONTEXT_WINDOW=$(tail -c 4096 "$TRANSCRIPT" | grep -o '"context_window":[0-9]*' | tail -1 | grep -o '[0-9]*' || true)

if [ -n "$INPUT_TOKENS" ] && [ -n "$CONTEXT_WINDOW" ] && [ "$CONTEXT_WINDOW" -gt 0 ]; then
  USAGE=$(( INPUT_TOKENS * 100 / CONTEXT_WINDOW ))
  echo "Context usage: ${USAGE}% (${INPUT_TOKENS}/${CONTEXT_WINDOW} tokens)"
fi
