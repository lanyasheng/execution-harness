#!/usr/bin/env bash
# bash-output-compressor.sh — PreToolUse hook (matcher: Bash)
# Rewrites bash commands to reduce token-heavy output before it enters context.
#
# Strategy: rewrite commands to use native quiet/summary flags or pipe through
# tail/head/filtering. Preserves error output. Does NOT wrap with external tools.
#
# Exit behavior (Claude Code PreToolUse protocol):
#   stdout JSON with hookSpecificOutput.updatedInput → command is rewritten
#   stdout {"continue":true} or empty → command passes through unchanged

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Only process Bash tool calls
[ "$TOOL" != "Bash" ] && echo '{"continue":true}' && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && echo '{"continue":true}' && exit 0

# Helper: match CMD against pattern (avoids grep --flag misparse on macOS)
has() { echo "$CMD" | grep -qE -- "$1"; }

# Skip if command is already piped through head/tail/wc (user intentionally limiting)
has '\|\s*(head|tail|wc|less|more)\b' && echo '{"continue":true}' && exit 0

# Skip heredoc commands (too complex to safely rewrite)
has '<<' && echo '{"continue":true}' && exit 0

# Skip if command already uses rtk
has '\brtk\b' && echo '{"continue":true}' && exit 0

REWRITTEN=""

# --- Test runners: add quiet/summary flags ---

# cargo test → add --quiet (only shows failures)
if has '^\s*cargo\s+test\b' && ! has '\-\-quiet' && ! has '\s-q\b'; then
  REWRITTEN=$(echo "$CMD" | sed -E 's/(cargo[[:space:]]+test)/\1 --quiet/')
fi

# pytest → add --tb=short --no-header -q
if has '^\s*(python3?\s+-m\s+)?pytest\b' && ! has '\-\-tb=' && ! has '\-\-no-header'; then
  REWRITTEN="${CMD} --tb=short --no-header -q"
fi

# npm test / npx jest / vitest → add --silent
if has '^\s*(npm\s+test|npx\s+(jest|vitest))\b' && ! has '\-\-silent' && ! has '\-\-verbose'; then
  REWRITTEN="${CMD} --silent"
fi

# --- Build output: filter progress noise ---

# cargo build/clippy → add --message-format=short (one-line errors)
if has '^\s*cargo\s+(build|clippy)\b' && ! has '\-\-message-format'; then
  REWRITTEN=$(echo "$CMD" | sed -E 's/(cargo[[:space:]]+(build|clippy))/\1 --message-format=short/')
fi

# npm install → add --silent to suppress progress bars
if has '^\s*npm\s+install\b' && ! has '\-\-silent' && ! has '\-\-loglevel'; then
  REWRITTEN="${CMD} --silent"
fi

# --- Git: limit output size ---

# git log without explicit limit → add -20
if has '^\s*git\s+log\b' && ! has '\-[0-9]+' && ! has '\-\-oneline' && ! has '\s-n\s'; then
  REWRITTEN="${CMD} -20"
fi

# git diff without summary flags → pipe through head -500
if has '^\s*git\s+diff\b' && ! has '\-\-stat' && ! has '\-\-name-only' && ! has '\-\-name-status' && ! has '\-\-shortstat'; then
  REWRITTEN="${CMD} | head -500"
fi

# --- General long-output commands ---

# find without -maxdepth and no pipe → add -maxdepth 5
if has '^\s*find\s' && ! has '\-maxdepth' && ! has '\|'; then
  REWRITTEN=$(echo "$CMD" | sed -E 's/(find[[:space:]]+[^[:space:]]+)/\1 -maxdepth 5/')
fi

# ls -R (recursive) without pipe → add head limit
if has '^\s*ls\s+.*-[a-zA-Z]*R' && ! has '\|'; then
  REWRITTEN="${CMD} | head -200"
fi

# --- Output ---

if [ -n "$REWRITTEN" ] && [ "$REWRITTEN" != "$CMD" ]; then
  echo "$INPUT" | jq -c --arg cmd "$REWRITTEN" \
    '{"hookSpecificOutput":{"updatedInput":(.tool_input + {"command": $cmd})}}'
else
  echo '{"continue":true}'
fi
