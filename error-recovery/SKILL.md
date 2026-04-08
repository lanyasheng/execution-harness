---
name: error-recovery
version: 2.0.0
description: Agent 错误恢复与容错。当 session 遇到限速、crash 或模型失败时使用。不适用于工具重试死循环（用 tool-governance）或 agent 提前停止（用 execution-loop）。参见 tool-governance（错误追踪数据）。
license: MIT
triggers:
  - rate limit
  - 限速
  - crash recovery
  - stale session
  - MCP disconnect
  - model fallback
  - agent hang
---

# Error Recovery

Agent session 的错误恢复：限速恢复、crash 状态恢复、MCP 断连、模型降级。

## When to Use

- tmux agent 限速后挂死 → Rate limit recovery
- Session crash 后恢复进度 → Crash state recovery
- 模型反复失败 → Model fallback advisory

## When NOT to Use

- 工具重试 → 用 `tool-governance`
- Agent 提前停止 → 用 `execution-loop`

---

## Patterns

### 5.1 Rate Limit Recovery [script]

周期性扫描 tmux pane 内容，检测限速关键词（429 / "too many requests" / "usage limit"），限速解除后自动发送按键恢复。发送 Enter 前必须二次验证 pane 当前内容——如果最后几行是破坏性确认提示而非限速消息，盲发 Enter 会确认危险操作。 → [详见](references/rate-limit.md)

### 5.2 Crash State Recovery [design]

新 session 启动时扫描残留状态：处于 `active` 的 ralph.json、超时未释放的 `.lock` 文件、`.working-state/` 中的中间产物。可恢复的状态从断点继续，损坏的中间文件回滚到最近 git checkpoint，过期 lock 自动清理。Claude Code 自身的 `conversationRecovery.ts` 已处理消息链修复（孤立 tool_use 补 placeholder），hook 只需聚焦 ralph.json 和 lock 这些 Claude Code 管不到的外部状态。 → [详见](references/crash-recovery.md)

### 5.3 Stale Session Daemon [design]

每个 session 通过 PostToolUse hook 定期发送 heartbeat。后台 daemon 检测到 heartbeat 超时（>5 分钟）且 tmux session 已不存在时，判定 session 死亡，从 transcript 中提取未保存的发现和推理过程，写入归档记忆文件。填补的是"session 静默死亡时知识丢失"这个空白——crash recovery 恢复执行状态，stale session daemon 抢救认知状态。 → [详见](references/stale-session.md)

### 5.4 MCP Reconnection [design]

检测 MCP 工具调用的特征性连接错误（ECONNREFUSED / ECONNRESET / EPIPE / transport closed），与业务错误区分后用指数退避重连（1s → 2s → 4s → 8s → 16s）。超过 5 次重试上限后停止重连，注入 fallback 建议引导 agent 切换到替代工具或提示用户手动重启 MCP server。 → [详见](references/mcp-reconnection.md)

### 5.5 Graceful Tool Degradation [design]

维护一份 fallback 工具映射表（`.working-state/fallback-tools.md`），记录每对首选/替代工具及其能力差异。PostToolUse hook 检测到工具连续失败 2 次后，查表注入降级建议，让 agent 知道替代工具的能力边界而非盲目切换。成功使用替代工具后自动清除失败计数。 → [详见](references/graceful-degradation.md)

### 5.6 Model Fallback Advisory [design]

模型连续失败 3 次后建议沿 haiku → sonnet → opus 链升级。529（容量不足）和 429（限速）的处理不同：429 等一下就好，529 需要换模型。StopFailure hook 追踪连续失败次数，触发阈值时注入升级建议——但 hook 无法直接切换模型，只能通过 additionalContext 建议 agent。在 subagent 架构中可通过定义不同模型的 agent 实现真正的自动切换。 → [详见](references/model-fallback.md)

### 5.7 Anti-Stampede Retry Asymmetry [design]

前台任务（用户直接发起的对话）遇 529 可重试，后台任务（summary、compaction、async hook）遇 529 立即放弃。这是刻意的不对称：后台任务丢失可容忍，但后台重试会在系统最脆弱的时候叠加负载。async hook 应用同一原则——失败不重试，超时设 5-10 秒，超时即静默退出。 → [详见](references/anti-stampede.md)

## Scripts

| 脚本 | 用途 |
|------|------|
| `rate-limit-recovery.sh` | 扫描 tmux 自动恢复 |

## Workflow

```
1. 检测错误类型（rate limit / crash / MCP disconnect / model failure）
   ⚠ 先查 ralph.json 和 lock 文件判断错误是暂时性还是永久性。
     永久性错误（auth 401/403、PTL）直接上报，不进入重试。

2. 按错误类型选择恢复策略（不同错误码的恢复路径独立，不共享重试计数）
   → rate limit (429): 扫描 tmux pane，二次验证内容后发送 Enter
   → crash: 读取 ralph.json 残留状态，清理过期 lock，从断点恢复
   → MCP disconnect: 指数退避重连，5 次失败后降级到本地工具
   → model failure (529): 3 次失败后建议升级模型或切换 provider

3. 区分前台/后台重试
   前台 session → 执行重试（honors retry-after）
   后台 session → 记录错误后放弃，不重试（anti-stampede）

4. 执行恢复

5. 验证 session 状态（ralph.json 一致、lock 文件已清理、pane 响应正常）
   → 成功 → 恢复执行
   → 失败 → 上报给用户，附带错误类型 + 已尝试的恢复策略 + 失败原因
```

<example>
tmux agent 遇到 429 限速，pane 卡在 "Rate limited. Press Enter to retry"。rate-limit-recovery.sh 扫描 pane 输出检测到限速关键词，二次验证最后 5 行不含破坏性确认提示后，发送 Enter 恢复执行。
</example>

<anti-example>
3 个后台 agent 同时遇到 529 过载，全部以相同间隔重试。重试请求叠加放大服务端压力，529 持续时间从 2 分钟延长到 15 分钟。后台 session 应直接放弃并记录。
</anti-example>

## Output

| 输出 | 说明 |
|------|------|
| recovery log entries | 每次恢复操作记录到 `logs/error-recovery.log`，含时间戳、pane、错误类型、执行动作、结果 |
| restored ralph.json | crash 恢复后 ralph.json 状态回到最后一致的 checkpoint，迭代计数器和任务列表保留 |
| cleaned lock files | 清除残留的 `.lock` 文件（如 `ralph.lock`、`session.lock`），防止后续 session 启动被阻塞 |

## Related

| Skill | 关系 |
|-------|------|
| `tool-governance` | error-recovery 的错误追踪数据（连续失败次数、错误类型分布）喂给 tool-governance 做工具降级决策 |
| `execution-loop` | Ralph crash 后由 error-recovery 恢复 ralph.json 状态，execution-loop 从断点继续执行 |
| `context-memory` | crash 恢复时 handoff state 由 context-memory 保障跨 session 存活，error-recovery 负责触发 handoff 写入 |
