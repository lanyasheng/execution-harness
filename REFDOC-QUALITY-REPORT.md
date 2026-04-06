# Reference Documentation Quality Report

**Generated**: 2026-04-06
**Scope**: All `.md` files under `skills/*/references/` (45 files total)
**Assessor**: Claude Opus 4.6 systematic review

---

## Summary Table

| # | File Path | Status | Notes |
|---|-----------|--------|-------|
| 1 | execution-loop/references/ralph.md | **Complete** | Excellent depth. 5 safety valves, 3 implementation modes, OMC cross-references. |
| 2 | execution-loop/references/doubt-gate.md | **Minor Issue** | Uses `{"continue":true}` instead of `{"decision":"allow"}` or silent exit. Inconsistent with other files. |
| 3 | execution-loop/references/cancel-ttl.md | **Complete** | Concise but complete. Problem/Solution/Implementation all present. |
| 4 | execution-loop/references/adaptive-complexity.md | **Complete** | Good decision tree, honest about heuristic limitations. |
| 5 | execution-loop/references/task-completion.md | **Complete** | Clear checklist-based approach with code. |
| 6 | execution-loop/references/drift-reanchor.md | **Inaccurate** | Claims UserPromptSubmit hook fires between Ralph iterations. In Ralph persistent mode, no user prompts are submitted between iterations -- Stop hook blocks and agent continues. Hook type should be Stop, not UserPromptSubmit. |
| 7 | execution-loop/references/headless-config.md | **Complete** | Solid three-dimension control model for `-p` mode. |
| 8 | execution-loop/references/iteration-aware-messaging.md | **Complete** | 4-phase message design with prompt-hardening P5 rationale. |
| 9 | execution-loop/references/extended-patterns.md | **Complete** | 4 extended patterns (E1.1-E1.4), all with source evidence. |
| 10 | tool-governance/references/tool-error.md | **Complete** | Three-tier escalation with input hashing. Includes 3-Strike and Error Capture extensions. |
| 11 | tool-governance/references/denial-circuit-breaker.md | **Complete** | Clear escalation ladder with DenialTrackingState reference. |
| 12 | tool-governance/references/checkpoint-rollback.md | **Inaccurate** | Comment says "PreToolUse does not support additionalContext, only permissionDecision" -- contradicted by graduated-permissions.md in the same skill, which shows PreToolUse returning additionalContext via hookSpecificOutput. |
| 13 | tool-governance/references/scoped-hooks.md | **Complete** | Concise. Stop-to-SubagentStop conversion claim is plausible but unverified. |
| 14 | tool-governance/references/graduated-permissions.md | **Complete** | 3-tier risk matrix with code. Good tradeoff analysis. |
| 15 | tool-governance/references/tool-input-guard.md | **Complete** | 3-category danger detection (path escape, destructive ops, remote code injection). |
| 16 | tool-governance/references/extended-patterns.md | **Complete** | 5 patterns (E2.1-E2.5) including Bash 6-layer defense. |
| 17 | context-memory/references/handoff-documents.md | **Complete** | Best-in-class reference. 5-section structure, 4-tier compression background, honest limitations. |
| 18 | context-memory/references/compaction-extract.md | **Inaccurate** | References `PreCompact` as a hook event. PreCompact is NOT among Claude Code's documented hook events (PreToolUse, PostToolUse, PostToolUseFailure, Stop, SubagentStop, UserPromptSubmit, Notification). The settings.json config shown would never fire. |
| 19 | context-memory/references/memory-consolidation.md | **Complete** | 3-gate model with AutoDream internals. |
| 20 | context-memory/references/token-budget.md | **Complete** | Reads `transcript_path` from hook stdin -- plausible but field availability in UserPromptSubmit unverified. |
| 21 | context-memory/references/context-usage.md | **Complete** | Excellent. Explicitly documents what CAN'T be done (no percentage). 3-tier estimation precision. |
| 22 | context-memory/references/filesystem-working-memory.md | **Complete** | Practical `.working-state/` pattern with plan + decisions JSONL. |
| 23 | context-memory/references/compaction-quality-audit.md | **Complete** | Works around the missing PreCompact hook by using UserPromptSubmit with transcript-size heuristic. |
| 24 | context-memory/references/extended-patterns.md | **Complete** | 6 patterns (E3.1-E3.6). Includes @include whitelist and prompt cache boundary. |
| 25 | multi-agent/references/delegation-modes.md | **Complete** | Core reference. 3 modes with decision tree, fork single-layer constraint, coordinator 4-phase workflow. |
| 26 | multi-agent/references/task-coordination.md | **Complete** | File-based task board with lockfile concurrency control. |
| 27 | multi-agent/references/file-claim-lock.md | **Complete** | Advisory locking with expiration. |
| 28 | multi-agent/references/workspace-isolation.md | **Complete** | Git worktree per agent with 3 merge strategies. |
| 29 | multi-agent/references/synthesis-gate.md | **Complete** | Enforces "coordinator must synthesize" with structural checks. |
| 30 | multi-agent/references/review-execution-separation.md | **Complete** | Dual-agent blind review pattern. |
| 31 | multi-agent/references/extended-patterns.md | **Complete** | 6 patterns (E4.1-E4.6). Cache-safe forking, mailbox, permission delegation. |
| 32 | error-recovery/references/rate-limit.md | **Complete** | tmux pane scanning with safety checks against blind Enter. OMC 5-component architecture. |
| 33 | error-recovery/references/crash-recovery.md | **Complete** | 3-category residual state handling. |
| 34 | error-recovery/references/stale-session.md | **Complete** | Heartbeat + daemon scavenging with knowledge extraction. |
| 35 | error-recovery/references/mcp-reconnection.md | **Complete** | Exponential backoff with characteristic error detection. |
| 36 | error-recovery/references/graceful-degradation.md | **Complete** | Fallback mapping table with capability deltas. |
| 37 | error-recovery/references/model-fallback.md | **Complete** | Honest about limitations (hook can't actually switch models). StopFailure event uncertainty documented. |
| 38 | error-recovery/references/extended-patterns.md | **Complete** | 5 patterns (E5.1-E5.5). Per-error-code map, watermark scoping, anti-loop guards. |
| 39 | quality-verification/references/post-edit-diagnostics.md | **Complete** | PostToolUse matcher for Write/Edit with per-language diagnostics. |
| 40 | quality-verification/references/hook-bracket.md | **Minor Issue** | Output says `context delta: ${CTX_DELTA}%` but context-usage.md explicitly states percentage cannot be computed (context_window_size unavailable). The `%` suffix is misleading; it's a raw token delta. |
| 41 | quality-verification/references/hook-profiles.md | **Complete** | 3 profiles (minimal/standard/strict) with env var control. |
| 42 | quality-verification/references/atomic-writes.md | **Complete** | Concise. Core utility pattern used across all state files. |
| 43 | quality-verification/references/test-before-commit.md | **Complete** | PreToolUse intercept for git commit with multi-language test detection. |
| 44 | quality-verification/references/session-hygiene.md | **Complete** | 4-category cleanup with dry-run support. |
| 45 | quality-verification/references/extended-patterns.md | **Complete** | 5 patterns (E6.1-E6.5). YOLO classifier, speculative execution, workspace trust. |

---

## Aggregate Statistics

| Category | Count | Percentage |
|----------|-------|------------|
| **Complete** | 41 | 91% |
| **Minor Issue** | 2 | 4% |
| **Inaccurate** | 2 | 4% |
| **Skeleton** | 0 | 0% |
| **Missing** | 0 | 0% |

---

## Detailed Findings

### 1. Factual Errors (must fix)

**A. `compaction-extract.md` -- Nonexistent hook event `PreCompact`**

The document shows this settings.json:
```json
{"hooks": {"PreCompact": [{"hooks": [{"type": "prompt", ...}]}]}}
```
`PreCompact` is not among Claude Code's documented hook events. The documented events are: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Stop`, `SubagentStop`, `UserPromptSubmit`, `Notification`. This configuration would silently do nothing.

**Fix**: Either (a) rewrite to use a `UserPromptSubmit` hook that detects post-compact state (as `compaction-quality-audit.md` does), or (b) use a `Stop` hook that checks context usage and proactively extracts before compact triggers, or (c) label the PreCompact approach as aspirational/advisory with a clear "NOT CURRENTLY SUPPORTED" warning.

**B. `checkpoint-rollback.md` -- Wrong claim about PreToolUse capabilities**

Contains comment: "PreToolUse 不支持 additionalContext，只能用 permissionDecision". This is contradicted by `graduated-permissions.md` (same skill), which correctly demonstrates:
```json
{"decision":"allow","hookSpecificOutput":{"additionalContext":"..."}}
```
PreToolUse hooks CAN return additionalContext via hookSpecificOutput.

**Fix**: Remove the incorrect comment. The checkpoint code can use additionalContext to inform the agent that a checkpoint was created.

**C. `drift-reanchor.md` -- Wrong hook event type**

Claims to use `UserPromptSubmit` hook to inject re-anchor messages between Ralph iterations. During Ralph persistent execution, the Stop hook blocks the agent's stop attempt and the agent continues -- no UserPromptSubmit event fires between iterations. The re-anchor injection would never trigger in the scenario it's designed for.

**Fix**: Change the hook type to `Stop`. The Stop hook already fires each time Ralph blocks -- it can check `iteration % interval == 0` and include re-anchor content in the block message alongside Ralph's continuation instruction.

### 2. Internal Inconsistencies (should fix)

**A. Hook response format for "allow stop"**

Three different formats are used across documents:
- `exit 0` with no output (ralph.md, graduated-permissions.md)
- `{"continue":true}` (doubt-gate.md)
- `{"decision":"allow"}` (task-completion.md, drift-reanchor.md)

Claude Code's actual behavior: outputting nothing (or exiting 0) allows the action. `{"decision":"block",...}` blocks it. `{"continue":true}` and `{"decision":"allow"}` are both non-blocking but use different schemas.

**Fix**: Standardize on `exit 0` (no output) for "allow" across all Stop hook examples, since this is the most reliable and documented behavior. Reserve JSON output for block decisions only.

**B. `hook-bracket.md` -- Misleading `%` in context delta output**

The Stop hook outputs `context delta: ${CTX_DELTA}%` but `context-usage.md` explicitly documents that context_window_size is not available in transcripts, so percentage cannot be computed. The value is actually a raw token count difference, not a percentage.

**Fix**: Change the output to `context delta: +${CTX_DELTA} tokens` or similar to avoid implying percentage.

### 3. Source Citation Assessment

**No "harness-books" or "CRC EP" citations in reference files.** The user's question asked about these sources. The `principles.md` file at the project root does cite:
- `https://github.com/wquguru/harness-books` (Harness Engineering)
- `https://github.com/openedclaude/claude-reviews-claude` (CRC -- Claude Reviews Claude)

However, individual reference files cite sources differently:
- **OMC** (Open Multi-agent Coordinator) internal code: `persistent-mode.mjs`, `post-tool-use-failure.mjs`, `rate-limit-monitor.js`, etc.
- **Claude Code source analysis** (v2.1.88): DenialTrackingState, QueryEngine, buildTool(), auto-compact logic
- **Community plugins**: `johnlindquist/plugin-doubt-gate`, `parcadei/Continuous-Claude-v3`, `affaan-m/everything-claude-code`, `rubenzarroca/sdd-autopilot`, `OthmanAdi/planning-with-files`, `alirezarezvani/claude-skills`
- **Anthropic official**: Multi-agent blog post, prompt caching docs, Claude Code docs
- **Practitioners**: LastWhisperDev distillation practice

These citations are plausible. The community plugin names follow GitHub naming conventions and reference specific files/mechanisms within those projects. OMC references cite specific files with line-level detail (e.g., `STALE_STATE_THRESHOLD_MS = 7200000`), suggesting actual source analysis rather than fabrication.

### 4. Implementation Actionability Assessment

All 45 files provide actionable implementation guidance. Specifically:

- **39 files** include working shell script examples with stdin parsing, jq processing, and hook protocol compliance
- **6 files** (extended-patterns) provide architectural descriptions without scripts, which is appropriate given their "design pattern" nature
- **0 files** are skeleton/placeholder content

The shell scripts follow a consistent pattern: read stdin JSON, extract fields with jq, apply logic, output hook protocol JSON. Someone with basic shell scripting knowledge and access to Claude Code's hook system could implement any of these.

### 5. Content Depth Assessment

Every file contains substantive content across these dimensions:

| Dimension | Files meeting standard | Notes |
|-----------|----------------------|-------|
| Problem statement | 45/45 | All describe a concrete failure mode |
| Solution mechanism | 45/45 | All explain the approach |
| Implementation code or design | 45/45 | 39 with code, 6 design-only |
| Tradeoffs/limitations | 43/45 | `cancel-ttl.md` and `scoped-hooks.md` are lighter on tradeoffs |
| Source attribution | 44/45 | `atomic-writes.md` has minimal sourcing |

---

## Recommendations

### Priority 1 (Factual fixes)
1. Fix `compaction-extract.md` -- replace PreCompact with a supported hook event or add a clear caveat
2. Fix `checkpoint-rollback.md` -- remove false claim about PreToolUse not supporting additionalContext
3. Fix `drift-reanchor.md` -- change hook type from UserPromptSubmit to Stop

### Priority 2 (Consistency)
4. Standardize Stop hook "allow" response format across all files (recommend: silent exit 0)
5. Fix `hook-bracket.md` misleading `%` in context delta output

### Priority 3 (Enhancement)
6. Add explicit "harness-books" / "CRC" cross-references in individual files where relevant, to match the citation style used in `principles.md`
7. Consider adding a "Verified against Claude Code version" note to files that reference internal implementation details, since these may change between versions
