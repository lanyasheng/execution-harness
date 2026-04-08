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

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 5.1 | Rate limit recovery | [script] | 扫描 tmux pane 自动恢复 |
| 5.2 | Crash state recovery | [design] | 检测残留状态恢复进度 |
| 5.3 | Stale session daemon | [design] | 死 session 知识回收 |
| 5.4 | MCP reconnection | [design] | MCP 断连指数退避重连 |
| 5.5 | Graceful tool degradation | [design] | 工具降级映射 |
| 5.6 | Model fallback advisory | [design] | 3 次失败建议升级模型 |
| 5.7 | Anti-stampede retry asymmetry | [design] | 前台重试、后台放弃，防止过载放大 |

## Scripts

| 脚本 | 用途 |
|------|------|
| `rate-limit-recovery.sh` | 扫描 tmux 自动恢复 |

## Rules

- **MUST** 区分前台 session 和后台 session 的重试策略——前台重试、后台放弃。否则后台任务同时重试会放大过载（anti-stampede）。
- **不要**对所有错误类型用相同的重试间隔和次数，**而是**按错误类型选择恢复策略：限速用指数退避，crash 用状态恢复，MCP 断连用重连，模型失败用降级。
- **如果不确定**错误是暂时性还是永久性，先检查 ralph.json 和 lock 文件状态，再决定是重试还是上报。盲目重试永久性错误只会浪费 token。

## Workflow

```
检测错误类型（rate limit / crash / MCP disconnect / model failure）
  → 选择恢复策略
    → rate limit: 扫描 tmux pane，检测 "Press Enter" 提示，发送 Enter
    → crash: 读取 ralph.json 残留状态，恢复进度
    → MCP disconnect: 指数退避重连，3 次失败后降级到本地工具
    → model failure: 3 次失败后建议升级模型或切换 provider
  → 执行恢复
  → 验证 session 状态（ralph.json 一致、lock 文件清理、pane 响应正常）
  → 恢复成功 → 恢复执行
  → 恢复失败 → 上报给用户，附带错误上下文
```

<example>
tmux agent 执行到一半遇到 429 限速，pane 输出卡在 "Rate limited. Press Enter to retry"。
rate-limit-recovery.sh 每 30 秒扫描 tmux pane 输出，检测到 "Press Enter" 关键词。
脚本向对应 pane 发送 Enter 键，agent 恢复执行，无需人工干预。
recovery log 记录：`[2026-04-07T10:23:15] pane=agent-3 event=rate_limit action=send_enter result=resumed`
</example>

<anti-example>
所有重试策略一视同仁——3 个后台 agent 同时遇到 529 过载错误，全部以相同间隔重试。
结果：重试请求叠加放大了服务端压力，529 持续时间从 2 分钟延长到 15 分钟。
违反 anti-stampede 原则：后台 session 应该直接放弃并记录，只有前台 session 才值得重试。
</anti-example>

## Output

| 输出 | 说明 |
|------|------|
| recovery log entries | 每次恢复操作记录到 `~/.openclaw/logs/error-recovery.log`，含时间戳、pane、错误类型、执行动作、结果 |
| restored ralph.json | crash 恢复后 ralph.json 状态回到最后一致的 checkpoint，迭代计数器和任务列表保留 |
| cleaned lock files | 清除残留的 `.lock` 文件（如 `ralph.lock`、`session.lock`），防止后续 session 启动被阻塞 |

## Related

| Skill | 关系 |
|-------|------|
| `tool-governance` | error-recovery 的错误追踪数据（连续失败次数、错误类型分布）喂给 tool-governance 做工具降级决策 |
| `execution-loop` | Ralph crash 后由 error-recovery 恢复 ralph.json 状态，execution-loop 从断点继续执行 |
| `context-memory` | crash 恢复时 handoff state 由 context-memory 保障跨 session 存活，error-recovery 负责触发 handoff 写入 |
