---
name: execution-harness
version: 2.0.0
description: 38 patterns across 6 axes for making Claude Code agents work reliably. Hook scripts + design patterns for execution continuity, tool safety, context governance, multi-agent coordination, error recovery, and quality verification.
license: MIT
triggers:
  - agent keeps stopping
  - ralph
  - persistent execution
  - tool retry
  - tool error
  - context management
  - multi agent
  - error recovery
  - rate limit
  - quality gate
  - harness
  - execution harness
  - agent reliability
---

# Execution Harness

38 patterns (17 hook scripts + 21 design patterns) across 6 functional axes, plus 10 meta-principles from [Harness Engineering](https://github.com/wquguru/harness-books).

## 6 Axes

| Axis | Patterns | Scripts | What it solves |
|------|----------|---------|----------------|
| [execution-loop](skills/execution-loop/SKILL.md) | 7 | 6 | Agent 提前停止、任务漂移 |
| [tool-governance](skills/tool-governance/SKILL.md) | 6 | 5 | 工具重试死循环、权限绕过 |
| [context-memory](skills/context-memory/SKILL.md) | 7 | 2 | 压缩后知识丢失、上下文管理 |
| [multi-agent](skills/multi-agent/SKILL.md) | 6 | 0 | 多 agent 协调、并发编辑 |
| [error-recovery](skills/error-recovery/SKILL.md) | 6 | 1 | 限速、crash、MCP 断连 |
| [quality-verification](skills/quality-verification/SKILL.md) | 6 | 3 | 编辑后检查、提交前测试 |

## When to Use

当你的 Claude Code agent 遇到以下问题时：
- 复杂任务只做一半就停了
- 工具失败后反复重试同一个命令
- Context 压缩后忘了设计决策
- 多个 agent 同时编辑同一个文件
- 限速后 tmux session 挂死
- 编辑后没跑 linter

## When NOT to Use

- 简单任务（< 5 分钟）不需要 harness
- 已有完善的 CI/CD pipeline 覆盖质量检查
- 单次问答场景（非持续执行）

## Quick Start

```bash
git clone https://github.com/lanyasheng/execution-harness.git
# 将 hooks 配置到 ~/.claude/settings.json（见各轴 SKILL.md）
bash skills/execution-loop/scripts/ralph-init.sh my-task 50
```

See [README.md](README.md) for full installation guide and [principles.md](principles.md) for the 10 meta-principles.
