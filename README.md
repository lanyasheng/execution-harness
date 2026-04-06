# Execution Harness

38 patterns across 6 axes for making Claude Code agents work reliably.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks%20compatible-blueviolet)]()
[![Patterns: 38](https://img.shields.io/badge/patterns-38-orange)]()

> Agent 改了 7 个文件中的 2 个就停了。`cargo build` 在没有 cargo 的容器里重试了 12 次。说 "this should work" 但不跑测试。限速后 tmux session 永远挂着。5 个 agent 同时编辑同一个文件。压缩后忘了所有设计决策。
>
> 这个仓库修所有这些。

蒸馏自 [Harness Engineering](https://github.com/wquguru/harness-books)、[Claude Code v2.1.88 源码分析](https://github.com/openedclaude/claude-reviews-claude)、[ccunpacked.dev](https://ccunpacked.dev/)、[claude-howto](https://github.com/luongnv89/claude-howto)、[Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) harness engineering 研究。

## Architecture: 6 Axes

```
execution-harness/
├── principles.md                    ← 10 Meta-Principles
├── skills/
│   ├── execution-loop/              ← 7 patterns: Ralph, doubt gate, drift anchoring, ...
│   ├── tool-governance/             ← 6 patterns: error escalation, denial breaker, ...
│   ├── context-memory/              ← 7 patterns: handoff docs, compaction, budget, ...
│   ├── multi-agent/                 ← 6 patterns: delegation modes, synthesis gate, ...
│   ├── error-recovery/              ← 6 patterns: rate limit, crash recovery, ...
│   └── quality-verification/        ← 6 patterns: post-edit check, test gate, ...
└── shared/                          ← Session state layout
```

## Quick Start

```bash
git clone https://github.com/lanyasheng/execution-harness.git && cd execution-harness
```

Then add hooks to `~/.claude/settings.json`:

<details>
<summary><b>Recommended settings.json (click to expand)</b></summary>

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/execution-loop/scripts/ralph-stop-hook.sh"},
        {"type": "command", "command": "bash /path/to/skills/execution-loop/scripts/doubt-gate.sh"}
      ]
    }],
    "PostToolUseFailure": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/tool-governance/scripts/tool-error-tracker.sh", "async": true}
      ]
    }],
    "PreToolUse": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/tool-governance/scripts/tool-error-advisor.sh"},
        {"type": "command", "command": "bash /path/to/skills/tool-governance/scripts/tool-input-guard.sh"}
      ]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/quality-verification/scripts/post-edit-check.sh", "async": true}
      ]
    }]
  }
}
```
</details>

```bash
# Initialize persistent execution (max 50 iterations, auto-resume from crash)
bash skills/execution-loop/scripts/ralph-init.sh my-task 50
```

## What This Solves

| Problem | Pattern |
|---------|---------|
| Agent stops after 2 of 7 files | **1.1 Ralph** — Stop hook blocks premature stops |
| "This should work" without tests | **1.2 Doubt Gate** — forces evidence |
| `cargo build` × 12 without cargo | **2.1 Tool Error Escalation** — 5 failures → alternative |
| Agent rephrases denied command | **2.2 Denial Circuit Breaker** — tracks denials |
| `rm -rf` destroys work | **2.3 Checkpoint + Rollback** — auto git stash |
| Context compressed, decisions lost | **3.1 Handoff Documents** — persist to disk |
| Rate limit, tmux hangs | **5.1 Rate Limit Recovery** — auto resume |
| 5 agents edit same file | **4.3 File Claim and Lock** — claim markers |
| Agent drifts from task | **1.5 Drift Re-anchoring** — re-inject task |

## 10 Meta-Principles

From [Harness Engineering](https://github.com/wquguru/harness-books). Full details in [principles.md](principles.md).

| # | Principle | Core idea |
|---|-----------|-----------|
| M1 | Determinism over persuasion | Hooks > prompts |
| M2 | Filesystem as coordination | State goes through disk files |
| M3 | Safety valves on every enforcement | Every blocker needs an escape |
| M4 | Session-scoped isolation | One session, one directory |
| M5 | Fail-open on uncertainty | When unsure, allow |
| M6 | Proportional intervention | Match intensity to complexity |
| M7 | Observe before intervening | Measure first |
| M8 | Explicit knowledge transfer | Write decisions to disk |
| M9 | Coordinator synthesizes | Never delegate understanding |
| M10 | Honest limitation labeling | "Not implemented" > "silently broken" |

## 38 Patterns by Axis

### Execution Loop (7) — [SKILL.md](skills/execution-loop/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 1.1 | Ralph persistent loop | [script] |
| 1.2 | Doubt gate | [script] |
| 1.3 | Adaptive complexity triage | [design] |
| 1.4 | Task completion verifier | [script] |
| 1.5 | Drift re-anchoring | [script] |
| 1.6 | Headless execution control | [config] |
| 1.7 | Iteration-aware messaging | [design] |

### Tool Governance (6) — [SKILL.md](skills/tool-governance/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 2.1 | Tool error escalation | [script] |
| 2.2 | Denial circuit breaker | [script] |
| 2.3 | Checkpoint + rollback | [script] |
| 2.4 | Graduated permission rules | [config] |
| 2.5 | Component-scoped hooks | [config] |
| 2.6 | Tool input guard | [script] |

### Context & Memory (7) — [SKILL.md](skills/context-memory/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 3.1 | Handoff documents | [design] |
| 3.2 | Compaction memory extraction | [script] |
| 3.3 | Three-gate memory consolidation | [design] |
| 3.4 | Token budget allocation | [design] |
| 3.5 | Context budget estimation | [script] |
| 3.6 | Filesystem as working memory | [design] |
| 3.7 | Compaction quality audit | [design] |

### Multi-Agent Coordination (6) — [SKILL.md](skills/multi-agent/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 4.1 | Three delegation modes | [design] |
| 4.2 | Shared task list protocol | [design] |
| 4.3 | File claim and lock | [design] |
| 4.4 | Agent workspace isolation | [design] |
| 4.5 | Synthesis gate | [design] |
| 4.6 | Review-execution separation | [design] |

### Error Recovery (6) — [SKILL.md](skills/error-recovery/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 5.1 | Rate limit recovery | [script] |
| 5.2 | Crash state recovery | [design] |
| 5.3 | Stale session daemon | [design] |
| 5.4 | MCP reconnection | [design] |
| 5.5 | Graceful tool degradation | [design] |
| 5.6 | Model fallback advisory | [design] |

### Quality & Verification (6) — [SKILL.md](skills/quality-verification/SKILL.md)

| # | Pattern | Type |
|---|---------|------|
| 6.1 | Post-edit diagnostics | [script] |
| 6.2 | Hook runtime profiles | [config] |
| 6.3 | Hook pair bracket | [script] |
| 6.4 | Test-before-commit gate | [script] |
| 6.5 | Atomic state writes | [design] |
| 6.6 | Session state hygiene | [design] |

## What This Is NOT

- **Not an agent framework.** No model calls, no chains. Just hooks and scripts.
- **Not a task scheduler.** No DAGs, no fan-in. That's orchestration, not execution.
- **Not Claude Code specific in concept.** The patterns are portable; the scripts use Claude Code's hook protocol.

## Testing

```bash
python3 -m pytest skills/*/tests/ -v   # 42 tests
```

Requires: `bash`, `jq`, `python3`, `pytest`.

## Known Limitations

- **Context usage safety valve**: Claude Code doesn't expose `context_window_size` to hooks.
- **Auto model fallback**: Hooks cannot switch models, only suggest (advisory only).
- **Doubt gate false positives**: "should be", "could be" match in non-speculative contexts.
- **Drift re-anchoring**: Uses Stop hook to count turns; the original task must be set via `reanchor.json` state file.
- **Denial tracker**: Infers denials from assistant message text, not from a dedicated hook event.

## Sources

| Source | What we used |
|--------|-------------|
| [Harness Engineering](https://github.com/wquguru/harness-books) | 10 meta-principles, theoretical framework |
| [Claude Code v2.1.88](https://github.com/openedclaude/claude-reviews-claude) | Source-level architecture patterns |
| [ccunpacked.dev](https://ccunpacked.dev/) | Tool catalog, hidden features |
| [claude-howto](https://github.com/luongnv89/claude-howto) | Extension API surface |
| [Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) | Harness engineering principles |

## License

MIT
