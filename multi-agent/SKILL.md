---
name: multi-agent
version: 2.0.0
description: 多 agent 协调设计模式。当需要选择 coordinator/fork/swarm 模式或设计跨 agent 协作时使用。
license: MIT
triggers:
  - multi agent
  - 多 agent
  - coordinator
  - fork vs swarm
  - agent coordination
  - workspace isolation
  - file conflict
---

# Multi-Agent Coordination

多 agent 系统设计模式：委托模式选型、任务协调、并发控制、质量保障。纯设计指南。

## When to Use

- 选择 Coordinator/Fork/Swarm → Three delegation modes
- 多 agent 同时编辑同一文件 → File claim and lock
- 需要隔离工作空间 → Agent workspace isolation
- 协调者需要综合 worker 结果 → Synthesis gate

## When NOT to Use

- 只有 1 个 agent → 用 `execution-loop`
- 跨阶段知识传递 → 用 `context-memory`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 4.1 | Three delegation modes | [design] | Coordinator/Fork/Swarm 选型 |
| 4.2 | Shared task list protocol | [design] | 文件化任务协调 |
| 4.3 | File claim and lock | [design] | 编辑前写 claim 防并发 |
| 4.4 | Agent workspace isolation | [design] | 每 agent 独立 worktree |
| 4.5 | Synthesis gate | [design] | 协调者必须产出综合文档 |
| 4.6 | Review-execution separation | [design] | 实现和审查分离 |
