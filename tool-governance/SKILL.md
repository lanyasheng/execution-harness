---
name: tool-governance
version: 2.0.0
description: 工具使用安全与可靠性。当工具反复失败、agent 绕过权限否决、或需要破坏性操作保护时使用。不适用于 agent 提前停止（用 execution-loop）或上下文管理（用 context-memory）。参见 error-recovery（限速恢复）。
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

## Hook Protocol: PreToolUse 的三种响应

PreToolUse hook 不只是 allow/deny。Claude Code 支持三种响应：

| 响应 | stdout 字段 | 用途 |
|------|-----------|------|
| **Allow/Deny** | `permissionDecision: "allow"` 或 `"deny"` | 放行或拦截工具调用 |
| **Modify Input** | `updatedInput: {...}` | 修改工具参数后放行 |
| **Inject Context** | `additionalContext: "..."` | 不改工具调用，但给 agent 补充信息 |

`updatedInput` 的典型用法：

```bash
# 给危险的 bash 命令自动加 timeout
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
if echo "$TOOL_INPUT" | grep -qE '^(find|du|tar) '; then
  MODIFIED=$(echo "$TOOL_INPUT" | sed 's/^/timeout 60 /')
  jq -n --arg cmd "$MODIFIED" \
    '{"hookSpecificOutput":{"updatedInput":{"command":$cmd}}}'
  exit 0
fi
```

注意多 hook 场景下 `updatedInput` 是 **last-one-wins**——后执行的 hook 覆盖前面的修改。详见 `principles.md` 的 Hook Aggregation Rules。

## Scripts

| 脚本 | Hook 类型 | 功能 |
|------|----------|------|
| `tool-error-tracker.sh` | PostToolUseFailure | 追踪连续失败 |
| `tool-error-advisor.sh` | PreToolUse | 5 次失败后 block |
| `denial-tracker.sh` | Stop | 从对话中推断权限否决 |
| `checkpoint-rollback.sh` | PreToolUse (Bash) | 破坏性命令前 stash |
| `tool-input-guard.sh` | PreToolUse (Bash) | 安全验证 |

## Workflow

工具治理的核心流程是**观测→计数→升级**三阶段闭环：

1. **检测工具失败** — `tool-error-tracker.sh`（PostToolUseFailure hook）记录每次工具调用失败，按工具名+命令模式分组计数，写入 `tool-errors.json`
2. **Tracker 记录** — 每次失败追加一条记录，包含时间戳、工具名、退出码、stderr 摘要；连续失败计数器递增
3. **Advisor 检查计数** — `tool-error-advisor.sh`（PreToolUse hook）在每次工具调用前读取 tracker 状态，判断同一工具的连续失败次数
4. **3x 软提示** — 连续失败 3 次时，advisor 通过 `additionalContext` 注入提示："此工具已连续失败 3 次，建议检查前置条件或换用替代方案"，但不阻止调用
5. **5x 硬阻止** — 连续失败 5 次时，advisor 返回 `permissionDecision: "deny"`，强制阻止工具调用，并在 `denials.json` 记录阻止事件
6. **Agent 被迫换方案** — 工具被 block 后，agent 必须改变策略：修复前置条件、换用替代工具、或请求人工介入

MUST 同时部署 tracker 和 advisor 两个 hook，否则只有观测没有干预，等于形同虚设（违反 M7 Observe Before Intervening 原则）。

不要只部署 advisor 而跳过 tracker——advisor 依赖 tracker 写入的 `tool-errors.json` 做计数判断，而是先部署 tracker 确认数据采集正常，再启用 advisor 做阈值干预。

如果不确定阈值设置是否合适（比如某些工具天然失败率高），先用 tracker 单独运行一个 session 收集基线数据，再根据实际失败分布调整 advisor 的 soft/hard 阈值。

<example>
场景: cargo build 反复失败，因为 cargo 未安装
工具: Bash (command: "cargo build")
第 1-2 次: tracker 记录失败，advisor 放行，agent 继续尝试
第 3 次: advisor 注入 additionalContext="cargo build 已连续失败 3 次，stderr 显示 'command not found'。建议检查 cargo 是否已安装。"
第 4 次: agent 仍然尝试 cargo build，tracker 计数到 4
第 5 次: advisor 返回 permissionDecision="deny"，阻止调用，写入 denials.json
agent 被迫改变策略: 先执行 `apt-get install -y cargo` 安装依赖，安装成功后 tracker 重置计数，cargo build 恢复可用
</example>

<anti-example>
错误用法: 只部署 tool-error-tracker 而不部署 tool-error-advisor
结果: tracker 忠实记录了 agent 对同一个失败命令重试 47 次的完整历史，但没有任何机制阻止它继续重试
问题: 观测者没有配套干预者，违反 M7 (Observe Before Intervening) 原则——M7 要求先观测再干预，但不是说只观测不干预
修复: MUST 同时在 settings.json 中注册 tool-error-tracker.sh (PostToolUseFailure) 和 tool-error-advisor.sh (PreToolUse) 两个 hook
</anti-example>

## Output

| 文件 | 路径 | 说明 |
|------|------|------|
| `tool-errors.json` | `.claude/tool-errors.json` | 工具失败记录：工具名、命令、退出码、stderr、时间戳、连续失败计数 |
| `denials.json` | `.claude/denials.json` | 阻止记录：被 block 的工具调用、阻止原因、触发阈值、时间戳 |
| checkpoint stash entries | `git stash list` | 破坏性命令前由 checkpoint-rollback.sh 自动创建的 git stash 条目，命名格式 `harness-checkpoint-<timestamp>` |

## Related

| Skill | 关系 |
|-------|------|
| `execution-loop` | Ralph 提供持续执行保障；tool-governance 提供工具级安全护栏。agent 不停 + 工具不炸 = 完整执行 |
| `error-recovery` | 处理限速 (rate limit)、crash、MCP 断连等 session 级故障；tool-governance 处理工具级重试失败。二者互补不重叠 |
| `quality-verification` | 编辑后 linting、提交前测试；tool-governance 在工具调用前拦截，quality-verification 在工具调用后验证。前者防错，后者查错 |
