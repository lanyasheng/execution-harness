---
name: context-memory
version: 2.0.0
description: 上下文窗口管理与跨 session 知识传递。当需要跨阶段传递决策、压缩前抢救知识时使用。
license: MIT
triggers:
  - context management
  - 上下文管理
  - handoff document
  - compaction
  - token budget
  - memory consolidation
  - context estimation
---

# Context & Memory

上下文窗口生命周期管理：跨阶段知识传递、压缩前知识抢救、token 预算。

## When to Use

- 多阶段任务跨阶段传递决策 → Handoff documents
- 即将压缩需要保存知识 → Compaction memory extraction
- 需要监控 context 使用率 → Context budget estimation

## When NOT to Use

- Agent 提前停止 → 用 `execution-loop`
- 多 agent 协调 → 用 `multi-agent`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 3.1 | Handoff documents | [design] | 阶段边界写 Decided/Rejected/Remaining |
| 3.2 | Compaction memory extraction | [script] | 压缩前抢救知识 |
| 3.3 | Three-gate memory consolidation | [design] | 跨 session 记忆合并 |
| 3.4 | Token budget allocation | [design] | 注入预算感知指令 |
| 3.5 | Context budget estimation | [script] | 估算 context 使用率 |
| 3.6 | Filesystem as working memory | [design] | 磁盘文件作活跃工作状态 |
| 3.7 | Compaction quality audit | [design] | 验证关键信息存活 |

## Scripts

| 脚本 | 用途 |
|------|------|
| `context-usage.sh <transcript>` | 估算 context 使用率 |
| `compaction-extract.sh` | 提取关键决策到 handoff |
