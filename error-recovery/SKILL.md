---
name: error-recovery
version: 2.0.0
description: Agent 错误恢复与容错。当 session 遇到限速、crash 或模型失败时使用。
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

## Scripts

| 脚本 | 用途 |
|------|------|
| `rate-limit-recovery.sh` | 扫描 tmux 自动恢复 |
