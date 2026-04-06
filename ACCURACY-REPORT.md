# Execution Harness — Accuracy Report

Generated: 2026-04-06
Scope: 17 scripts vs SKILL.md (6 files), README.md, shared/session-state-layout.md

## Issue Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 3 |
| Low | 5 |
| **Total** | **9** |

---

## Issues

### HIGH

```
[skills/tool-governance/scripts/tool-error-advisor.sh] HIGH: PreToolUse deny response uses different JSON field name ("permissionDecisionReason") than tool-input-guard.sh and test-before-commit.sh (which use "reason"). All three are PreToolUse hooks. tool-error-advisor.sh also adds "hookEventName" field that the other two omit. One of these formats may silently fail at runtime.
```

Actual outputs:
- `tool-error-advisor.sh`: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}`
- `tool-input-guard.sh`: `{"hookSpecificOutput":{"permissionDecision":"deny","reason":$reason}}`
- `test-before-commit.sh`: `{"hookSpecificOutput":{"permissionDecision":"deny","reason":$reason}}`

### MEDIUM

```
[skills/context-memory/SKILL.md] MEDIUM: context-usage.sh described as "估算 context 使用率" (estimate context usage rate) but the script only reports raw input_tokens count. The script itself explicitly documents it CANNOT compute a percentage because context_window_size is unavailable. SKILL.md pattern 3.5 also says "Context budget estimation" which implies ratio computation.
```

```
[skills/quality-verification/SKILL.md] MEDIUM: post-edit-check.sh handles Write, Edit, AND MultiEdit (line 12: case match "Write|Edit|MultiEdit"), but SKILL.md only says "PostToolUse (Write|Edit)". README settings.json matcher also says "Write|Edit". MultiEdit is undocumented.
```

```
[README.md] MEDIUM: Settings.json example shows doubt-gate.sh wired as a Stop hook but does NOT show task-completion-gate.sh, drift-reanchor.sh, denial-tracker.sh, compaction-extract.sh, or bracket-hook.sh — all of which are also Stop hooks. The "Recommended settings.json" is significantly incomplete and could mislead users into thinking only ralph-stop-hook.sh and doubt-gate.sh need Stop wiring.
```

### LOW

```
[README.md] LOW: "2.1 Tool Error Escalation — 5 failures → alternative" omits the soft threshold. The actual script (tool-error-tracker.sh) has SOFT_THRESHOLD=3 (suggest) and HARD_THRESHOLD=5 (force). The "5 failures" description only describes the hard threshold.
```

```
[skills/quality-verification/SKILL.md] LOW: bracket-hook.sh is pattern "6.3 Hook pair bracket" with description "per-turn 时间/工具调用测量". The name "Hook pair bracket" implies a paired pre+post hook architecture, but the actual script is a single Stop hook that tracks elapsed time and turn count. There is no PreToolUse counterpart forming a "bracket". The description text is accurate; the pattern name is misleading.
```

```
[skills/context-memory/SKILL.md] LOW: compaction-extract.sh is a Stop hook (reads from stdin via head -c 20000, expects session_id in JSON), but the Scripts table uses "用途" (usage) column header instead of "Hook 类型" (hook type), hiding the fact that it must be wired as a Stop hook to function.
```

```
[skills/execution-loop/scripts/ralph-stop-hook.sh] LOW: Code comment on line 8 says "authentication errors (401/403 in stop_reason)" but the actual code (line 74) checks last_assistant_message, not stop_reason. The comment is internally misleading. No user-facing documentation affected.
```

```
[skills/context-memory/SKILL.md] LOW: compaction-extract.sh described as "提取关键决策到 handoff" (extract key decisions to handoff). The script actually dumps the raw last_assistant_message (up to 5000 chars) without any decision extraction logic. It is a crude snapshot, not a selective extraction.
```

---

## Verified Correct

The following were verified as factually accurate:

| Script | Hook Type | SKILL.md | README |
|--------|-----------|----------|--------|
| ralph-stop-hook.sh | Stop | correct | correct |
| ralph-init.sh | CLI | correct | correct |
| ralph-cancel.sh | CLI (30s TTL) | correct | correct |
| doubt-gate.sh | Stop (one-shot guard) | correct | correct |
| task-completion-gate.sh | Stop (24h staleness) | correct | correct |
| drift-reanchor.sh | Stop (every N turns) | correct | correct |
| tool-error-tracker.sh | PostToolUseFailure | correct | correct |
| denial-tracker.sh | Stop (inferred) | correct | correct |
| checkpoint-rollback.sh | PreToolUse (Bash) | correct | correct |
| rate-limit-recovery.sh | Standalone (tmux) | correct | correct |
| test-before-commit.sh | PreToolUse (Bash) | correct | correct |

## README Structural Checks

| Claim | Actual | Status |
|-------|--------|--------|
| "38 patterns across 6 axes" | 7+6+7+6+6+6 = 38 | correct |
| Badge "patterns-38" | 38 | correct |
| 6 axes listed | 6 axis directories exist | correct |
| Pattern numbering gaps | None | correct |
| Known Limitations section | All 5 limitations verified against code | correct |
| session-state-layout.md files | All listed files match actual script outputs | correct |

## Recommendations

1. **Fix tool-error-advisor.sh JSON format** to match the other two PreToolUse deny scripts (use `"reason"` not `"permissionDecisionReason"`), or determine the canonical format from Claude Code source and update all three.
2. **Update context-memory SKILL.md** to say "提取 input token 数" instead of "估算 context 使用率" for pattern 3.5.
3. **Add MultiEdit** to post-edit-check.sh documentation in SKILL.md and README.
4. **Add missing Stop hooks** to the README settings.json example, or add a comment noting it's a minimal subset.
5. **Rename pattern 6.3** from "Hook pair bracket" to "Session turn metrics" or similar to avoid bracket/pair confusion.
