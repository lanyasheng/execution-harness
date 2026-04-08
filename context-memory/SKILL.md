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

MUST 在每个阶段边界写 handoff 文件，否则 compact 后决策记忆全部丢失，后续阶段会重复讨论已否决的方案。

不要依赖 context 窗口本身保留决策记录，而是在阶段结束时把 Decided/Rejected/Risks/Files/Remaining 写入磁盘 handoff 文件。

如果不确定当前是否处于阶段边界，询问用户确认，或检查任务清单中是否有阶段标记。

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 3.1 | Handoff documents | [design] | 阶段边界写 Decided/Rejected/Remaining |
| 3.2 | Compaction memory extraction | [script] | 压缩前抢救知识 |
| 3.3 | Three-gate memory consolidation | [design] | 跨 session 记忆合并 |
| 3.4 | Token budget allocation | [design] | 注入预算感知指令 |
| 3.5 | Context token count | [script] | 从 transcript 提取 input_tokens 数（不含百分比） |
| 3.6 | Filesystem as working memory | [design] | 磁盘文件作活跃工作状态 |
| 3.7 | Compaction quality audit | [design] | 验证关键信息存活 |
| 3.8 | Auto-compact circuit breaker | [design] | 压缩连续失败 3 次停止尝试 |

## Scripts

| 脚本 | 用途 |
|------|------|
| `context-usage.sh <transcript>` | 估算 context 使用率 |
| `compaction-extract.sh` | 提取关键决策到 handoff |

## Workflow

```
1. 检测阶段边界 — 任务清单阶段完成、用户明确切换方向、或 execution-loop 发出阶段信号
       ↓
2. 写 handoff 文件 — 包含 Decided / Rejected / Risks / Files / Remaining 五个区块
       ↓
3. 监控 context 使用率 — 用 context-usage.sh 估算当前 token 占比，>70% 进入预警
       ↓
4. 压缩前知识抢救 — 用 compaction-extract.sh 把关键决策、否决理由、文件清单提取到 compaction-extract.json
       ↓
5. 压缩后审计 — 检查 handoff 文件和 extract 是否完整，关键信息是否可从磁盘恢复
```

<example>
场景: 20 轮 Redis 缓存方案讨论，最终选 Redis Cluster 弃用 Codis
第 1-15 轮: 讨论 Redis Sentinel vs Cluster vs Codis，对比延迟/运维成本/数据分片
第 16 轮: 决定用 Redis Cluster，否决 Codis（原因：社区停更、分片策略不透明）
第 17 轮: 检测到阶段边界，写 handoff 到 sessions/xxx/handoffs/stage-2.md

handoff 内容:
- Decided: Redis Cluster，6 节点 3 主 3 从
- Rejected: Codis（社区停更、Proxy 层额外延迟 2ms）、Sentinel（不支持数据分片）
- Risks: Cluster 在大 key 场景下 rebalance 耗时长
- Files: infra/redis-cluster.yaml, config/redis.conf
- Remaining: 压测验证、故障切换演练

第 20 轮: 触发 Full Compact，context 被截断
Compact 后: agent 读取 stage-2.md，立即恢复所有决策上下文，不会重新提议 Codis
</example>

<anti-example>
场景: 同样 20 轮 Redis 讨论，但没有写 handoff
第 16 轮决定用 Redis Cluster，否决 Codis，决策只存在于 context 窗口
第 20 轮触发 Full Compact，context 被截断到最近 5 轮
Compact 后: agent 丢失了 Codis 被否决的原因，重新提议"要不要考虑 Codis？"
用户不得不再花 3 轮重复解释为什么不用 Codis
结果: 浪费 token、用户体验差、决策质量下降
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
