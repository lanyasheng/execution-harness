#!/usr/bin/env bash
# commit-safety-guard.sh — PreToolUse(Bash) hook: block commits containing
# sensitive data, local paths, or out-of-scope files.
#
# Checks staged diff (git diff --cached) for:
# 1. Local absolute paths ($HOME, /Users/<any>/, /home/<any>/)
# 2. Secrets (API keys, tokens, passwords in common formats)
# 3. Branch scope violations (inferred from branch name patterns)
#
# Design: M1 determinism (deny), M5 fail-open (git not available → allow)

set -euo pipefail

INPUT=$(head -c 20000)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL=""

[ "$TOOL" != "Bash" ] && echo '{"continue":true}' && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
[ -z "$COMMAND" ] && echo '{"continue":true}' && exit 0

# Only intercept git commit
if ! echo "$COMMAND" | grep -qE 'git\s+commit\b'; then
  echo '{"continue":true}'
  exit 0
fi

# Get staged diff content
DIFF=$(git diff --cached --unified=0 2>/dev/null) || { echo '{"continue":true}'; exit 0; }
DIFF_FILES=$(git diff --cached --name-only 2>/dev/null) || DIFF_FILES=""

# No staged changes → allow
[ -z "$DIFF" ] && echo '{"continue":true}' && exit 0

# Only check added lines (lines starting with +, excluding +++ header)
ADDED_LINES=$(echo "$DIFF" | grep -E '^\+[^+]' || true)

VIOLATIONS=""

# --- Check 1: Local absolute paths ---
USER_HOME="${HOME:-}"
if [ -n "$USER_HOME" ] && [ -n "$ADDED_LINES" ]; then
  if echo "$ADDED_LINES" | grep -qF "$USER_HOME"; then
    VIOLATIONS="${VIOLATIONS}Local home path ($USER_HOME) found in staged diff\n"
  fi
fi

# Generic /Users/<any>/ or /home/<any>/ patterns
GENERIC_PATHS=$(echo "$ADDED_LINES" | grep -oE '(/Users/[a-zA-Z0-9._-]+/|/home/[a-zA-Z0-9._-]+/)' | sort -u | head -5 || true)
if [ -n "$GENERIC_PATHS" ]; then
  VIOLATIONS="${VIOLATIONS}Local user paths in diff: $(echo "$GENERIC_PATHS" | tr '\n' ' ')\n"
fi

# --- Check 2: Secrets patterns ---
# API keys (common formats)
SECRETS=$(echo "$ADDED_LINES" | grep -oiE '(sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9_-]{20,}|xoxb-[a-zA-Z0-9-]+)' | head -3 || true)
if [ -n "$SECRETS" ]; then
  VIOLATIONS="${VIOLATIONS}Possible API keys/tokens detected (redacted)\n"
fi

# Password assignments in config
PASSWORDS=$(echo "$ADDED_LINES" | grep -iE '(password|passwd|secret|api_key|apikey)\s*[:=]\s*["\x27][^"\x27]{8,}' | head -3 || true)
if [ -n "$PASSWORDS" ]; then
  VIOLATIONS="${VIOLATIONS}Possible hardcoded passwords/secrets in config\n"
fi

# .env files should never be committed
ENV_FILES=$(echo "$DIFF_FILES" | grep -E '\.env$|\.env\.' | head -3 || true)
if [ -n "$ENV_FILES" ]; then
  VIOLATIONS="${VIOLATIONS}Environment files staged: $ENV_FILES\n"
fi

# --- Check 3: Branch scope guard ---
BRANCH=$(git branch --show-current 2>/dev/null) || BRANCH=""

if [ -n "$BRANCH" ] && [ -n "$DIFF_FILES" ]; then
  SCOPE_VIOLATION=""

  # harness/ai-system/hook/skill branches → only AI/harness files
  if echo "$BRANCH" | grep -qiE 'harness|ai-system|hook|skill'; then
    OUT_OF_SCOPE=$(echo "$DIFF_FILES" | grep -vE '^(\.claude/|\.agents/|knowledge-base/|\.openclaw/)' | grep -vE '^\.' | head -5 || true)
    if [ -n "$OUT_OF_SCOPE" ]; then
      SCOPE_VIOLATION="Branch '$BRANCH' is scoped to AI/harness files only. Out-of-scope files: $OUT_OF_SCOPE"
    fi
  fi

  # doc branches → only docs
  if echo "$BRANCH" | grep -qiE '\bdoc\b'; then
    OUT_OF_SCOPE=$(echo "$DIFF_FILES" | grep -vE '^(knowledge-base/|website/|\.agents/|\.claude/)' | grep -vE '^\.' | head -5 || true)
    if [ -n "$OUT_OF_SCOPE" ]; then
      SCOPE_VIOLATION="Branch '$BRANCH' is scoped to docs only. Out-of-scope files: $OUT_OF_SCOPE"
    fi
  fi

  if [ -n "$SCOPE_VIOLATION" ]; then
    VIOLATIONS="${VIOLATIONS}${SCOPE_VIOLATION}\n"
  fi
fi

# --- Result ---
if [ -n "$VIOLATIONS" ]; then
  REASON=$(printf "Commit safety check failed:\n%b" "$VIOLATIONS")
  jq -n --arg reason "$REASON" \
    '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}'
else
  echo '{"continue":true}'
fi
