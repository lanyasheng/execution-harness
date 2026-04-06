# Execution Harness

Make Claude Code agents finish their work.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks%20compatible-blueviolet)]()
[![Patterns: 38](https://img.shields.io/badge/core%20patterns-38-orange)]()
[![Tests: 90](https://img.shields.io/badge/tests-90%20passing-brightgreen)]()

Agent 改了 7 个文件中的 2 个就停了。`cargo build` 在没有 cargo 的容器里重试了 12 次。说 "this should work" 但不跑测试。限速后 tmux session 挂死。5 个 agent 同时编辑同一个文件。压缩后忘了所有设计决策。

17 个即插即用的 bash hook 脚本 + 21 个设计模式，覆盖 agent 可靠性的 6 个维度。不是框架，不做模型调用——只管住执行层。

## Quick Start

```bash
git clone https://github.com/lanyasheng/execution-harness.git
cd execution-harness
```

把需要的 hook 加到 `~/.claude/settings.json`：

<details>
<summary><b>settings.json 起步配置</b></summary>

> 这是最小子集。完整 hook 列表见各轴的 SKILL.md。

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/execution-loop/scripts/ralph-stop-hook.sh"},
        {"type": "command", "command": "bash /path/to/skills/execution-loop/scripts/doubt-gate.sh"},
        {"type": "command", "command": "bash /path/to/skills/quality-verification/scripts/bracket-hook.sh", "async": true}
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
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/quality-verification/scripts/post-edit-check.sh", "async": true}
      ]
    }]
  }
}
```
</details>

```bash
# 启动持续执行（最多 50 轮，crash 后自动恢复）
bash skills/execution-loop/scripts/ralph-init.sh my-task 50
```

## 解决什么问题

| 问题 | 对应 pattern |
|------|-------------|
| Agent 只做了一部分就停了 | **1.1 Ralph** — Stop hook 阻止提前退出 |
| "应该可以" 但没跑测试 | **1.2 Doubt Gate** — 检测投机语言，要求验证 |
| `cargo build` 重试 12 次 | **2.1 Tool Error Escalation** — 5 次失败后强制换方案 |
| 被拒后换个说法再试 | **2.2 Denial Circuit Breaker** — 追踪否决次数 |
| `rm -rf` 毁了未提交的代码 | **2.3 Checkpoint + Rollback** — 破坏性命令前 git stash |
| 压缩后忘了设计决策 | **3.1 Handoff Documents** — 决策写磁盘 |
| 限速后 tmux 挂死 | **5.1 Rate Limit Recovery** — 自动检测并恢复 |
| 5 个 agent 编辑同一文件 | **4.3 File Claim and Lock** — claim 标记防并发 |
| 长 session 偏离原始任务 | **1.5 Drift Re-anchoring** — 定期重新注入任务描述 |
| 提交了没跑过测试的代码 | **6.4 Test-Before-Commit** — commit 前自动跑测试 |

## 架构：6 个轴

```
execution-harness/
├── principles.md                    ← 10 条设计原则
├── skills/
│   ├── execution-loop/              ← 让 agent 继续工作直到完成
│   ├── tool-governance/             ← 让工具使用安全可控
│   ├── context-memory/              ← 让知识跨压缩存活
│   ├── multi-agent/                 ← 让多个 agent 协同而非冲突
│   ├── error-recovery/              ← 让 agent 从故障中恢复
│   └── quality-verification/        ← 让输出质量有保障
└── shared/                          ← Session 状态布局
```

每个轴是独立的 sub-skill，有自己的 SKILL.md、scripts、references、tests。装你需要的，忽略其余。

## 38 Core Patterns

### Execution Loop (7) — [SKILL.md](skills/execution-loop/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 1.1 | Ralph persistent loop | script | Stop hook 阻止提前退出，4 个安全阀保底 |
| 1.2 | Doubt gate | script | 检测 "可能""大概" 等投机语言 |
| 1.3 | Adaptive complexity triage | design | 按任务复杂度自动选 harness 强度 |
| 1.4 | Task completion verifier | script | 读任务清单，未完成项存在则阻止 |
| 1.5 | Drift re-anchoring | script | 每 N 轮重新注入原始任务描述 |
| 1.6 | Headless execution control | config | `-p` 模式下的替代控制方案 |
| 1.7 | Iteration-aware messaging | design | 按迭代阶段调整 block 消息语气 |

### Tool Governance (6) — [SKILL.md](skills/tool-governance/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 2.1 | Tool error escalation | script | 连续 3 次提示、5 次强制换方案 |
| 2.2 | Denial circuit breaker | script | 追踪否决，3 次警告、5 次建议替代 |
| 2.3 | Checkpoint + rollback | script | 破坏性 bash 命令前自动 git stash |
| 2.4 | Graduated permission rules | config | 按风险分层：auto-allow / warn / deny |
| 2.5 | Component-scoped hooks | config | 任务级别的 hook 控制 |
| 2.6 | Tool input guard | script | 拦截 `rm -rf /`、`curl \| sh` 等危险模式 |

### Context & Memory (7) — [SKILL.md](skills/context-memory/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 3.1 | Handoff documents | design | 阶段边界写入结构化的决策记录 |
| 3.2 | Compaction memory extraction | script | 定期快照关键知识到 handoff 文件 |
| 3.3 | Three-gate memory consolidation | design | 跨 session 记忆合并（时间/数量/锁三门控） |
| 3.4 | Token budget allocation | design | 注入预算感知指令 |
| 3.5 | Context token count | script | 从 transcript 提取 input token 数 |
| 3.6 | Filesystem as working memory | design | 用 `.working-state/` 目录作活跃工作状态 |
| 3.7 | Compaction quality audit | design | 压缩后验证关键信息是否存活 |

### Multi-Agent Coordination (6) — [SKILL.md](skills/multi-agent/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 4.1 | Three delegation modes | design | Coordinator / Fork / Swarm 选型指南 |
| 4.2 | Shared task list protocol | design | 文件化任务协调 + 状态跟踪 |
| 4.3 | File claim and lock | design | 编辑前写 claim 标记防并发冲突 |
| 4.4 | Agent workspace isolation | design | 每个 agent 独立 git worktree |
| 4.5 | Synthesis gate | design | 协调者必须综合 worker 结果后才能委派 |
| 4.6 | Review-execution separation | design | 实现和审查用不同 agent |

### Error Recovery (6) — [SKILL.md](skills/error-recovery/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 5.1 | Rate limit recovery | script | 扫描 tmux pane 自动发 Enter 恢复 |
| 5.2 | Crash state recovery | design | 检测残留状态，从断点恢复 |
| 5.3 | Stale session daemon | design | 死 session 的知识回收 |
| 5.4 | MCP reconnection | design | MCP 断连检测 + 指数退避重连 |
| 5.5 | Graceful tool degradation | design | 首选工具不可用时的降级映射 |
| 5.6 | Model fallback advisory | design | 3 次失败后建议升级模型 |

### Quality & Verification (6) — [SKILL.md](skills/quality-verification/SKILL.md)

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 6.1 | Post-edit diagnostics | script | 每次编辑后跑 linter / type checker |
| 6.2 | Hook runtime profiles | config | minimal / standard / strict 三档切换 |
| 6.3 | Session turn metrics | script | 记录每轮耗时和 turn 计数 |
| 6.4 | Test-before-commit gate | script | `git commit` 前自动跑测试套件 |
| 6.5 | Atomic state writes | design | write-to-temp-then-rename 保证 crash safety |
| 6.6 | Session state hygiene | design | 定期清理 stale session 和 orphaned lock |

## 10 条设计原则

详见 [principles.md](principles.md)。

| # | 原则 | 一句话 |
|---|------|--------|
| M1 | Determinism over persuasion | hook 是确定的，prompt 是概率的 |
| M2 | Filesystem as coordination | 所有跨 agent/session 通信走磁盘文件 |
| M3 | Safety valves on every enforcement | 每个阻止机制必须有逃生条件 |
| M4 | Session-scoped isolation | 一个 session 一个目录，互不污染 |
| M5 | Fail-open on uncertainty | 状态不明确时放行（安全场景除外） |
| M6 | Proportional intervention | 简单任务不需要全套 hook |
| M7 | Observe before intervening | 先跑 tracker 再决定 blocker |
| M8 | Explicit knowledge transfer | 决策写磁盘，不信 LLM 摘要 |
| M9 | Coordinator synthesizes | 协调者综合，不转发 |
| M10 | Honest limitation labeling | "未实现" 好过 "静默失效" |

## 不是什么

- **不是 agent 框架。** 不做模型调用，不管 prompt chain。只管 hook 和脚本。
- **不是任务调度。** 没有 DAG，没有 fan-in。那是编排，不是执行。
- **概念上不绑定 Claude Code。** Pattern 可移植；脚本碰巧用了 Claude Code 的 hook 协议。

## 测试

```bash
python3 -m pytest skills/*/tests/ -v   # 90 tests
```

依赖：`bash`、`jq`、`python3`、`pytest`

## 已知限制

- **Context 使用率**：Claude Code 不向 hook 暴露 `context_window_size`，只能读 raw token 数。
- **模型切换**：Hook 不能切换模型，只能建议（advisory only）。
- **Doubt gate 误报**：代码注释中的 "should be" 也会匹配，用 one-shot guard 防死循环。
- **Drift re-anchoring**：用 Stop hook 计数 turn，原始任务需通过 `reanchor.json` 设置。
- **Denial tracker**：从 assistant 消息推断否决，没有专用 hook event。

## Sources

| Source | 贡献 |
|--------|------|
| [Harness Engineering](https://github.com/wquguru/harness-books) | 10 条设计原则的理论框架 |
| [Claude Code v2.1.88 源码分析](https://github.com/openedclaude/claude-reviews-claude) | 源码级架构 pattern |
| [ccunpacked.dev](https://ccunpacked.dev/) | 工具全景、hidden features |
| [claude-howto](https://github.com/luongnv89/claude-howto) | 扩展点 API 教程 |
| [Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) | Harness engineering 设计原则 |

## License

MIT
