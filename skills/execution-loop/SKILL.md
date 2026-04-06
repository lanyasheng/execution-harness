---
name: execution-loop
version: 2.0.0
description: Agent 执行循环控制。当 agent 提前停止、偏离任务、或在 headless 模式下需要执行控制时使用。
license: MIT
triggers:
  - agent keeps stopping
  - ralph
  - persistent execution
  - 不要停
  - doubt gate
  - task completion
  - headless mode
  - agent drifts
  - adaptive complexity
---

# Execution Loop

控制 agent 的执行循环：阻止提前停止、检测任务完成、防止任务漂移。

## When to Use

- Agent 只完成一部分就停了 → Ralph persistent loop
- Agent 说"可能"就声称完成 → Doubt gate
- 长 session 中偏离原始任务 → Drift re-anchoring
- 有明确任务清单 → Task completion verifier
- 用 `-p` headless 模式 → Headless execution control

## When NOT to Use

- 工具反复失败 → 用 `tool-governance`
- 上下文快用完 → 用 `context-memory`
- Session 挂死 → 用 `error-recovery`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 1.1 | Ralph persistent loop | [script] | Stop hook 阻止提前 end_turn，4 个安全阀 |
| 1.2 | Doubt gate | [script] | 检测投机语言，强制提供证据 |
| 1.3 | Adaptive complexity triage | [design] | 自动选择 harness 强度 |
| 1.4 | Task completion verifier | [script] | 未完成项存在则阻止停止 |
| 1.5 | Drift re-anchoring | [script] | 每 N 轮重新注入原始任务 |
| 1.6 | Headless execution control | [config] | `-p` 模式替代方案 |
| 1.7 | Iteration-aware messaging | [design] | 根据迭代次数调整 block 消息 |

## Scripts

| 脚本 | Hook 类型 | 功能 |
|------|----------|------|
| `ralph-stop-hook.sh` | Stop | 阻止提前停止，4 安全阀 |
| `ralph-init.sh <id> [max]` | CLI | 初始化持续执行 |
| `ralph-cancel.sh <id>` | CLI | 发送取消信号 |
| `doubt-gate.sh` | Stop | 检测 hedging words |
| `task-completion-gate.sh` | Stop | 读 .harness-tasks.json |
| `drift-reanchor.sh` | Stop | 每 N 轮注入原始任务提醒 |
