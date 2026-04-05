# Execution Harness

**21 production patterns for making Claude Code agents actually finish their work.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests: 32 passed](https://img.shields.io/badge/tests-32%20passed-brightgreen)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks%20compatible-blueviolet)]()
[![Patterns: 21](https://img.shields.io/badge/patterns-21-orange)]()

---

> Your agent stops after fixing 2 of 7 files. It retries `cargo build` 12 times in a container without cargo. It says "this should work" instead of running the test. It hits a rate limit and hangs forever in tmux.
>
> This repo fixes all of that.

Distilled from **Claude Code v2.1.88 internals** (512K lines TypeScript), **[oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)** production code, and **[Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) harness engineering** research. Cross-referenced with [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill), [ccunpacked.dev](https://ccunpacked.dev/), [everything-claude-code](https://github.com/affaan-m/everything-claude-code), and [15+ community repos](#sources).

## Quick Start (60 seconds)

```bash
# 1. Clone
git clone https://github.com/lanyasheng/execution-harness.git
cd execution-harness

# 2. Add hooks to Claude Code
# Copy the settings.json snippet below into ~/.claude/settings.json

# 3. Initialize persistent execution for a task
bash skills/agent-hooks/scripts/ralph-init.sh my-task 50
```

<details>
<summary><b>settings.json hook configuration</b></summary>

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/ralph-stop-hook.sh"},
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/doubt-gate.sh"}
      ]
    }],
    "PostToolUseFailure": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/tool-error-tracker.sh", "async": true}
      ]
    }],
    "PreToolUse": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/tool-error-advisor.sh"}
      ]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/post-edit-check.sh", "async": true}
      ]
    }]
  }
}
```
</details>

## What This Solves

| Problem | What happens | Pattern that fixes it |
|---------|-------------|----------------------|
| Agent stops after fixing 2 of 7 files | `end_turn` too early | **Ralph** — Stop hook blocks premature stops |
| "This should work" without running the test | Speculative completion | **Doubt Gate** — forces evidence before stopping |
| `cargo build` × 12 in a container without cargo | Infinite retry loop | **Tool Error Escalation** — 5 failures → forced alternative |
| Context compressed, agent forgets design decisions | Knowledge loss | **Handoff Documents** — persist decisions to disk |
| Rate limit hit, tmux session hangs | No auto-recovery | **Rate Limit Recovery** — detect + safe resume |
| Agent crash at iteration 37, restarts from 0 | Lost progress | **Crash Recovery** — ralph-init detects and resumes |

## What This Is NOT

- **Not an agent framework.** No model calls, no prompt templates, no chains. Just hooks and scripts.
- **Not a task scheduler.** No DAGs, no fan-in, no dependency management. That's orchestration, not execution.
- **Not Claude Code specific in concept.** The patterns are portable. The scripts happen to use Claude Code's hook protocol.

## Three Skills, Three Audiences

```
execution-harness/
├── skills/
│   ├── agent-hooks/               ← You're a developer configuring hooks
│   ├── harness-design-patterns/   ← You're an architect designing agent systems
│   └── agent-ops/                 ← You're an SRE keeping agents alive
└── shared/                        ← Session state layout (used by all three)
```

### agent-hooks — Drop-in scripts for Claude Code

8 bash scripts, 27 tests. Configure in `settings.json`, forget about it.

| Script | Hook Type | What it does |
|--------|----------|--------------|
| `ralph-stop-hook.sh` | Stop | Blocks premature stops. 4 safety valves (auth error, cancel signal, 2h stale, max iterations) |
| `ralph-init.sh` | CLI | Initialize persistent execution. Auto-resumes from crash |
| `ralph-cancel.sh` | CLI | Send 30s TTL cancel signal |
| `doubt-gate.sh` | Stop | Scans for hedging words ("maybe", "probably", "可能"). Forces evidence |
| `tool-error-tracker.sh` | PostToolUseFailure | Tracks consecutive failures by tool+input hash |
| `tool-error-advisor.sh` | PreToolUse | Denies retry after 5 consecutive failures of same command |
| `post-edit-check.sh` | PostToolUse | Runs linter/type checker immediately after every edit |
| `context-usage.sh` | CLI | Extracts input token count from transcript |

Every script: reads `session_id` from Claude Code's stdin JSON (fallback to `$NC_SESSION` env var). All JSON output via `jq -n` (injection-safe). All state writes via write-then-rename (atomic).

### harness-design-patterns — Architecture knowledge base

10 design patterns. No executable code. Each pattern has: Problem → Principle → Tradeoffs → Source → Claude Code evidence.

Covers: handoff documents, compaction memory extraction (PreCompact hook), denial circuit breakers, 3-gate memory consolidation, hook pair brackets, coordinator/fork/swarm delegation modes, adaptive complexity scoring, hook runtime profiles.

Plus: [distillation methodology](skills/harness-design-patterns/references/distillation-methodology.md) (PCA analogy, review-execution separation) and [quality pipeline integration](skills/harness-design-patterns/references/quality-pipeline-integration.md).

### agent-ops — Runtime monitoring and recovery

6 operational patterns (1 scripted, 5 design references): context estimation, rate limit recovery, stale session daemon, checkpoint/rollback, token budget management, auto model fallback.

## How It Was Built

This repo is the result of a systematic distillation process — not a code dump.

**8+ sources analyzed in parallel:**

```
Claude Code v2.1.88 source ──┐
oh-my-claudecode (OMC)  ─────┤
ccunpacked.dev ───────────────┤
claude-howto ─────────────────┼──→ 40+ candidate patterns
Claude Code official docs ────┤      ↓
LastWhisperDev article ───────┤    dedup + prioritize
GitHub: 6 community repos ───┤      ↓
Anthropic/OpenAI blogs ───────┘    21 patterns → 3 skills
```

**Methodology** ([full doc](skills/harness-design-patterns/references/distillation-methodology.md)):

The distillation follows LastWhisperDev's PCA analogy: "Code is high-dimensional, but valuable design patterns are low-rank." We injected taste vectors (Anthropic's harness engineering blog, OpenAI's Context Engineering four-axis framework) and projected the 512K-line codebase along those directions.

Key method: **Review-Execution separation** — different agents for review (fact-checking against source) and execution (writing patterns), each in fresh sessions with handoff documents as the only shared context.

**Quality assurance:** 3 rounds of multi-agent review (functionality → protocol compliance → factual accuracy). 53 issues found, 30 fixed, 5 reviewer errors identified and rejected. All hook field names verified against [official Claude Code docs](https://code.claude.com/docs/en/hooks) (26 hook events).

## Positioning

| | This repo | [agentic-harness-patterns](https://github.com/keli-wen/agentic-harness-patterns-skill) | [OMC](https://github.com/Yeachan-Heo/oh-my-claudecode) | [ECC](https://github.com/affaan-m/everything-claude-code) |
|---|---|---|---|---|
| **What** | Hook scripts + design patterns | Design patterns (pure knowledge) | CLI wrapper + orchestration layer | Plugin ecosystem + optimization |
| **Executable code** | 8 bash scripts, 32 tests | 0 (knowledge only) | Full npm package | Full plugin package |
| **Hook protocol verified** | Yes (against official docs) | N/A | Yes (production-tested) | Yes (production-tested) |
| **Patterns covered** | 21 | 6 principles | 9 modes | 38 agents, 156 skills |
| **Scope** | Execution reliability only | Harness architecture | Full agent lifecycle | Everything |
| **Install friction** | Copy scripts + edit settings.json | `npx skills add` | `npm i -g` + `/setup` | Plugin marketplace |

**This repo is the middle ground**: more than a knowledge base (has working scripts), less than a full framework (no runtime, no CLI wrapper). Install what you need, ignore the rest.

## Session State Layout

All runtime state lives under `sessions/<session-id>/`:

```
sessions/<session-id>/
  ralph.json          ← persistent execution state
  cancel.json         ← cancel signal (30s TTL)
  handoffs/           ← stage handoff documents
  tool-errors.json    ← consecutive failure tracking
  denials.json        ← permission denial tracking
```

One `rm -rf` cleans everything. Crash recovery = check if directory exists.

## Testing

```bash
cd skills/agent-hooks && python3 -m pytest tests/ -v   # 27 tests
cd skills/agent-ops && python3 -m pytest tests/ -v      # 5 tests
```

Requires: `bash`, `jq`, `python3`, `pytest`.

## Known Limitations

- **Context usage safety valve is not implemented** — Claude Code does not expose `context_window_size` to hook scripts (only available via statusLine stdin pipe). Claude Code's own reactive compaction handles overflow independently.
- **Auto model fallback is advisory, not automatic** — hooks cannot control which model Claude Code uses. The pattern injects a suggestion into context.
- **Doubt gate has false positives** — "should be", "could be" match in non-speculative contexts. The one-shot guard prevents infinite loops but means the second attempt always passes.
- **Claude Code internal names** (AutoDream, DenialTrackingState, etc.) come from source-mapped v2.1.88 TypeScript. They are real but may change across versions.

## Sources

| Source | What we extracted |
|--------|------------------|
| [Claude Code v2.1.88](https://github.com/openedclaude/claude-reviews-claude) | Query Engine loop, Tool System, Permission Pipeline, Context Management, Session Persistence |
| [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | Ralph persistent-mode, Cancel TTL (30s), Stale threshold (2h), Team runtime v2 |
| [ccunpacked.dev](https://ccunpacked.dev/) | DenialTracking, AutoDream, MCP auto-healing, Memory extraction during compaction |
| [claude-howto](https://github.com/luongnv89/claude-howto) | Prompt-type/Agent-type hooks, Hook pair bracket, Component-scoped hooks, `once: true` |
| [Claude Code official docs](https://code.claude.com/docs/en/hooks) | 26 hook events, input/output JSON schemas, permission protocol |
| [LastWhisperDev](https://mp.weixin.qq.com/s/R9EgZlx1RnXK4L12OBQn-w) | Distillation methodology, PCA analogy, Review-Execution separation |
| [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill) | 6 design principles (Memory, Skills, Tools, Context, Multi-agent, Lifecycle) |
| [plugin-doubt-gate](https://github.com/johnlindquist/plugin-doubt-gate) | Speculation detection via hedging word scan |
| [Continuous-Claude-v3](https://github.com/parcadei/Continuous-Claude-v3) | TLDR 5-layer analysis, file claims, stale session daemon, post-edit diagnostics |
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | Hook runtime profiles, instinct evolution, observer loop prevention |
| [sdd-autopilot](https://github.com/rubenzarroca/sdd-autopilot) | Adaptive complexity scoring, 8-phase pipeline triage |
| [Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) | Harness engineering design principles, filesystem-as-context |

## License

MIT
