---
name: tool-governance
version: 2.0.0
description: 工具使用安全与可靠性。当工具反复失败、agent 绕过权限否决、或需要破坏性操作保护时使用。
license: MIT
triggers:
  - tool retry
  - tool error
  - permission denied
  - denial bypass
  - checkpoint rollback
  - bash safety
  - destructive command
  - tool input validation
---

# Tool Governance

工具使用的安全护栏：防止重试死循环、追踪权限否决、破坏性操作备份、输入验证。

## When to Use

- 工具反复失败 → Tool error escalation
- Agent 换说法绕过否决 → Denial circuit breaker
- Bash 可能造成不可逆破坏 → Checkpoint + rollback
- 需要阻止危险命令 → Tool input guard

## When NOT to Use

- Agent 提前停止 → 用 `execution-loop`
- 上下文管理 → 用 `context-memory`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 2.1 | Tool error escalation | [script] | 3x 软提示, 5x 强制换方案 |
| 2.2 | Denial circuit breaker | [script] | 追踪否决, 3x 警告, 5x 替代 |
| 2.3 | Checkpoint + rollback | [script] | 破坏性命令前 git stash |
| 2.4 | Graduated permission rules | [config] | 按风险分层 allow/warn/deny |
| 2.5 | Component-scoped hooks | [config] | 任务级 hook 控制 |
| 2.6 | Tool input guard | [script] | 路径边界 + 危险模式验证 |

## Scripts

| 脚本 | Hook 类型 | 功能 |
|------|----------|------|
| `tool-error-tracker.sh` | PostToolUseFailure | 追踪连续失败 |
| `tool-error-advisor.sh` | PreToolUse | 5 次失败后 block |
| `denial-tracker.sh` | PostToolUse | 追踪权限否决 |
| `checkpoint-rollback.sh` | PreToolUse (Bash) | 破坏性命令前 stash |
| `tool-input-guard.sh` | PreToolUse (Bash) | 安全验证 |
