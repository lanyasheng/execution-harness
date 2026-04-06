---
name: execution-harness
version: 2.0.1
description: 38 patterns across 6 axes for making Claude Code agents work reliably. Hook scripts + design patterns for execution continuity, tool safety, context governance, multi-agent coordination, error recovery, and quality verification.
license: MIT
triggers:
  - agent keeps stopping
  - ralph
  - persistent execution
  - 不要停
  - tool retry
  - tool error
  - context management
  - 上下文管理
  - multi agent
  - 多 agent
  - error recovery
  - rate limit
  - 限速
  - quality gate
  - harness
  - execution harness
  - agent reliability
  - doubt gate
  - handoff
  - checkpoint
  - bash safety
---

# Execution Harness

38 patterns (17 hook scripts + 21 design patterns) for making Claude Code agents work reliably.

## Route to the right axis

Tell me what problem you're facing, and I'll load the right sub-skill:

| Problem | Axis to load |
|---------|-------------|
| Agent 提前停止 / Ralph / 持续执行 / 任务漂移 | `/execution-loop` |
| 工具重试死循环 / 权限被绕过 / 危险命令 / checkpoint | `/tool-governance` |
| 压缩后忘了决策 / context 预算 / handoff | `/context-memory` |
| 多 agent 协调 / 并发编辑 / coordinator 选型 | `/multi-agent` |
| 限速挂死 / crash 恢复 / MCP 断连 | `/error-recovery` |
| 编辑后检查 / 提交前测试 / session 指标 | `/quality-verification` |

## Quick Start

```bash
# 安装
git clone https://github.com/lanyasheng/execution-harness.git
# 或 clawhub install execution-harness

# 配置 hooks（见各轴 SKILL.md）
# 启动持续执行
bash skills/execution-loop/scripts/ralph-init.sh my-task 50
```

## 10 Meta-Principles

详见 `principles.md`：Determinism > Persuasion, Filesystem Coordination, Safety Valves, Session Isolation, Fail-Open, Proportional Intervention, Observe First, Explicit Transfer, Coordinator Synthesizes, Honest Labeling.
