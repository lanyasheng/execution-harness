# Execution Harness v2 Review Report

Reviewed: 2026-04-06
Scope: 6 sub-skills, 17 scripts, 5 test files, README, SKILL.md files, references

---

## Critical

### C1. README.md is entirely v1 — all paths, counts, and structure references are stale

The root README still describes the old 3-skill structure (`agent-hooks`, `harness-design-patterns`, `agent-ops`). These directories no longer exist. Every path in the README is broken:

- `skills/agent-hooks/scripts/*.sh` (6 occurrences in settings.json example and CLI examples)
- `skills/harness-design-patterns/references/distillation-methodology.md` (2 occurrences)
- `skills/harness-design-patterns/references/quality-pipeline-integration.md` (1 occurrence)
- `cd skills/agent-hooks && python3 -m pytest tests/` in Testing section
- `cd skills/agent-ops && python3 -m pytest tests/` in Testing section
- The "Three Skills, Three Audiences" section describes a structure that no longer exists

Also stale: badge says "patterns: 21" but the 6 sub-skills now contain 38 patterns total. Script count says "8 bash scripts, 42 tests" but there are now 17 scripts. Test count (42) happens to still be correct.

### C2. denial-tracker.sh reads fields that don't exist in PostToolUse stdin

The script reads `.was_denied` / `.denied` from input, but Claude Code's PostToolUse hook provides `tool_name`, `tool_input`, `tool_result` — no denial flag. The script can never fire because `was_denied` always resolves to `false`/empty. The entire script is dead code as wired.

Fix options: (a) parse `tool_result` for denial text patterns, (b) wire to a different hook event, or (c) document it as advisory-only.

### C3. drift-reanchor.sh is wired to non-existent hook event

SKILL.md lists it as a `UserPromptSubmit` hook. Claude Code's hook events are: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Stop`, `Notification`, `SubagentStop`. There is no `UserPromptSubmit` event. The script cannot be registered as a hook.

---

## High

### H1. 9 test source files deleted, only .pyc bytecache remains

The v2 restructure deleted test `.py` files for all 9 new scripts but left orphaned `.pyc` in `__pycache__/`. The 42 passing tests only cover the 5 surviving test files (ralph, doubt-gate, post-edit-check, tool-error, context-usage). Zero test coverage for:

- `task-completion-gate.sh`
- `drift-reanchor.sh`
- `denial-tracker.sh`
- `checkpoint-rollback.sh`
- `tool-input-guard.sh`
- `compaction-extract.sh`
- `rate-limit-recovery.sh`
- `bracket-hook.sh`
- `test-before-commit.sh`

### H2. post-edit-check.sh has operator precedence bug (line 34)

```bash
if command -v npx &>/dev/null && [ -f "$(dirname "$FILE")/tsconfig.json" ] || [ -f "tsconfig.json" ]; then
```

Parsed as `(npx_exists AND tsconfig_in_dir) OR tsconfig_in_cwd`. If `tsconfig.json` exists in CWD, `tsc` runs even when `npx` is not installed, causing a command-not-found error. Should be:

```bash
if command -v npx &>/dev/null && { [ -f "$(dirname "$FILE")/tsconfig.json" ] || [ -f "tsconfig.json" ]; }; then
```

### H3. tool-input-guard.sh chmod 777 regex has dead branch (line 29)

```bash
grep -qE 'chmod\s+777\s+.*(^/|/usr|/etc|/var|/System)'
```

The `^/` inside `(..|..)` alternation after `.*` can never match — `^` anchors to start-of-line but `.*` has already consumed characters. Only `/usr`, `/etc`, `/var`, `/System` paths are actually caught. `chmod 777 /` and `chmod 777 /root` are NOT blocked.

### H4. compaction-extract.sh relies on unverified Stop hook stdin fields

The script checks `stop_reason == "context_full"` and `context_near_full == true`. These fields are not part of the documented Stop hook stdin schema. The script will never trigger its extraction logic — it always outputs `{"continue":true}`.

---

## Medium

### M1. 6 scripts exit 0 with zero stdout on some code paths

Claude Code hooks tolerate empty output (treated as "continue"), but this is inconsistent with the other scripts that explicitly output `{"continue":true}`. Affected:

| Script | Silent exit condition |
|--------|----------------------|
| `denial-tracker.sh` | `was_denied != true`, no session_id, count < 3 |
| `tool-error-tracker.sh` | no session_id, count < 3 |
| `post-edit-check.sh` | non-Write/Edit tool, no errors found |
| `context-usage.sh` | no transcript, no tokens (outputs plain text, not JSON) |
| `rate-limit-recovery.sh` | standalone script, outputs to stderr only |

While functionally harmless (hooks accept empty output), it makes debugging harder and breaks the documented "all JSON output" convention from the README.

### M2. post-edit-check.sh uses `go vet "$FILE"` on single files (line 47)

`go vet` operates on packages, not individual files. While `go vet file.go` is partially supported since Go 1.14, it doesn't resolve cross-file imports and produces unreliable results. Should use `go vet ./$(dirname "$FILE")` or `go vet .` instead.

### M3. 16 patterns listed in SKILL.md files lack reference docs

Patterns with `[script]` type that have no reference doc (most impactful):

- 1.4 Task completion verifier
- 1.5 Drift re-anchoring
- 2.6 Tool input guard
- 6.4 Test-before-commit gate

Patterns with `[design]` or `[config]` type that have no reference doc:

- 1.6 Headless execution control, 1.7 Iteration-aware messaging
- 2.4 Graduated permission rules
- 3.6 Filesystem as working memory, 3.7 Compaction quality audit
- 4.2-4.6 (5 multi-agent patterns — only delegation-modes.md exists)
- 5.2 Crash state recovery, 5.4 MCP reconnection, 5.5 Graceful tool degradation
- 6.6 Session state hygiene

### M4. checkpoint-rollback.sh uses `--include-untracked` which can be very slow

`git stash push --include-untracked` will stash `node_modules/`, build artifacts, and other large untracked trees. On repos with large untracked content, this can take minutes and block the agent. Consider `--keep-index` instead, or documenting the performance risk.

### M5. session-state-layout.md references old v1 pattern numbers

The shared state layout doc uses "Pattern 1", "Pattern 2", "Pattern 3", etc. which mapped to the old v1 numbering. The v2 numbering is different (e.g., tool errors are now 2.1, not "Pattern 3").

---

## Low

### L1. ralph-cancel.sh and ralph-init.sh exit 1 on empty stdin (expected for CLI scripts)

These are CLI scripts (not hooks), so they correctly require positional arguments and exit non-zero without them. The `echo '{}' | bash` test is not applicable. This is correct behavior.

### L2. Orphaned `__pycache__` and `.pytest_cache` directories

Multiple `__pycache__` directories contain `.pyc` files from deleted test sources. A `find . -name __pycache__ -exec rm -rf {} +` would clean these up.

### L3. context-usage.sh outputs plain text, not JSON

This is a CLI utility (`context-usage.sh <transcript>`) not a hook, so plain text output is acceptable. However, the inconsistency with the "all scripts use JSON" claim in the README is worth noting.

### L4. test-before-commit.sh is disabled by default (`TEST_BEFORE_COMMIT=0`)

Not a bug — this is a reasonable safety default. But the SKILL.md doesn't mention this env var requirement, which could confuse users who wire it up but see it do nothing.

### L5. `md5` vs `md5sum` fallback chain (tool-error-tracker.sh line 25)

The hash fallback `md5 || md5sum || shasum || echo "unknown"` works but `md5` (macOS) writes to stdout differently than `md5sum` (Linux). On macOS, `md5` outputs `MD5 ("stdin") = <hash>` which includes extra text. This means the same input produces different hashes on macOS vs Linux, which is fine for same-machine consistency but would break cross-platform state sharing.

---

## Summary

| Severity | Count | Key theme |
|----------|-------|-----------|
| Critical | 3 | README entirely stale; 2 scripts can never trigger |
| High | 4 | Tests deleted; regex/logic bugs in 2 scripts; 1 more unfireable script |
| Medium | 5 | Inconsistent output protocol; missing reference docs; perf risk |
| Low | 5 | Cosmetic/documentation nits |
