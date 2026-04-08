---
name: context-memory
version: 2.0.0
description: 上下文窗口管理与跨 session 知识传递。当需要跨阶段传递决策、压缩前抢救知识时使用。不适用于工具重试（用 tool-governance）或多 agent 协调（用 multi-agent）。参见 execution-loop（阶段边界）。
license: MIT
triggers:
  - context management
  - 上下文管理
  - handoff document
  - compaction
  - token budget
  - memory consolidation
  - context estimation
author: OpenClaw Team
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

### 3.1 Handoff 文档 [design]

阶段结束或压缩前，将 Decided/Rejected/Risks/Files/Remaining 五段写入磁盘。压缩摘要由 LLM 决定保留什么，handoff 由你决定——信息在磁盘上，任何级别的 compact 都不会丢失。阶段边界不确定时，检查任务清单阶段标记或直接询问用户。 → [详见](references/handoff-documents.md)

### 3.2 Compaction 前记忆提取 [script]

Claude Code 没有 PreCompact hook。通过 Stop hook 每 N 轮定期快照关键决策到磁盘，作为预防性知识保存。和 handoff 互补：handoff 是计划内的阶段传递，compaction 提取是应急的自动抢救。 → [详见](references/compaction-extract.md)

### 3.3 三门控记忆合并 [design]

跨 session 积累的 handoff 和记忆文件会碎片化、重复、矛盾。三门控（Time >= 24h → Session >= 5 → FileLock）按计算成本从低到高排列，任一失败即跳过。通过门控后按时间排序合并 Decided/Rejected，后来的决策覆盖早期的。 → [详见](references/memory-consolidation.md)

### 3.4 Token 预算分配 [design]

在 UserPromptSubmit hook 中估算 context 使用量，按阈值梯度注入行为指令：< 40% 自由读取，60-80% 优先 grep/subagent，> 80% 禁止直接读大文件。前半段消耗过多 context 导致后半段被迫压缩是常见失败模式，预算感知把干预前移。 → [详见](references/token-budget.md)

### 3.5 Context Token 估算 [script]

从 transcript JSONL 尾行提取 `usage.input_tokens`。注意 transcript 不暴露 `context_window_size`（该字段仅通过 statusLine stdin pipe 提供给 HUD），因此 hook 脚本只能拿到原始 token 数，无法算百分比。阈值判断基于 200K window 假设做粗估。 → [详见](references/context-usage.md)

### 3.6 文件系统作工作记忆 [design]

用 `.working-state/` 目录存放 `current-plan.md`（当前计划，随时覆写）和 `decisions.jsonl`（决策日志，append-only）。compact 或 crash 后 agent 通过读取这两个文件恢复状态，避免丢失"为什么选方案 B 而不是方案 A"的推理链。需要在 prompt 中明确要求 agent 写入这些文件。 → [详见](references/filesystem-working-memory.md)

### 3.7 Compaction 质量审计 [design]

compact 后对照 `.working-state/decisions.jsonl` 的最近 N 条决策检查 compact summary 中是否存活。发现遗失则自动将缺失决策注入 context。关键词匹配是粗糙近似——compact 可能用同义词表达同一决策，但漏检的代价（方向倒退）远大于误检的代价（多注入几条信息）。 → [详见](references/compaction-quality-audit.md)

### 3.8 Auto-Compact 断路器 [design]

连续 3 次 auto-compact 失败后停止尝试（`MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3`），等待 Reactive Compact（API 413 触发）兜底。Claude Code 曾有 1,279 个 session 出现 50+ 次连续 compact 失败，浪费约 250K API 调用/天。如果你的 hook 依赖 compact 事件，需要处理 circuit breaker 跳过的情况。 → [详见](references/auto-compact-circuit-breaker.md)

## Scripts

| 脚本 | 用途 |
|------|------|
| `context-usage.sh <transcript>` | 从 transcript 尾行提取 input_tokens（原始数，非百分比） |
| `compaction-extract.sh` | Stop hook 定期触发，提取关键决策到 handoff |

## Workflow

```
阶段结束？
  → 写 handoff（Decided/Rejected/Risks/Files/Remaining 五段，缺一不可）
  → 不确定是否阶段边界？查任务清单或问用户

Context > 80%？
  → 运行 compaction-extract.sh 抢救关键决策到磁盘
  → 注入预算指令：禁止读大文件，委托 subagent

Compact 刚发生？
  → 审计存活：对照 decisions.jsonl 检查 compact summary
  → 发现遗失 → 自动注入缺失决策
  → 连续失败 3 次 → circuit breaker 生效，等 Reactive Compact 兜底
```

<example>
20 轮 Redis 方案讨论。第 16 轮定方案：Redis Cluster 6 节点，否决 Codis（社区停更、Proxy 延迟 +2ms）和 Sentinel（不支持分片）。第 17 轮写 handoff 到 sessions/xxx/handoffs/stage-2.md。第 20 轮 Full Compact 截断 context。Compact 后 agent 读 stage-2.md，恢复全部决策，不会重提 Codis。
</example>

<anti-example>
同样 20 轮讨论，没写 handoff。第 20 轮 Compact 后 agent 丢失 Codis 被否决的原因，重新提议"考虑 Codis？"。用户花 3 轮重复解释——浪费 token，决策质量倒退。
</anti-example>

## Output

| 产物 | 路径 | 说明 |
|------|------|------|
| 阶段 handoff 文件 | `sessions/xxx/handoffs/stage-N.md` | 每个阶段边界写一份，包含 Decided/Rejected/Risks/Files/Remaining |
| 压缩抢救文件 | `compaction-extract.json` | 压缩前自动提取的关键决策和否决记录 |
| context 使用率估算 | `context-usage.sh` 输出 | 当前 token 占比、预警阈值、剩余容量估算 |

## Related

- `execution-loop` — 阶段边界信号触发 handoff 写入（Pattern 1.4 task completion 完成时即为阶段边界）
- `multi-agent` — 跨 agent 任务交接时，handoff 文件作为知识传递载体（替代口头 context 传递）
- `error-recovery` — crash 恢复时读取最近的 handoff 文件重建进度（Pattern 5.2 crash state recovery）
