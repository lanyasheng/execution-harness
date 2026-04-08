---
name: execution-loop
version: 2.0.0
description: Agent 执行循环控制。当 agent 提前停止、偏离任务、或在 headless 模式下需要执行控制时使用。不适用于工具重试（用 tool-governance）。参见 context-memory（阶段边界 handoff）、quality-verification（编辑后检查）。
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

## Workflow

```
用户下达任务
  → 1. 检查任务复杂度（Adaptive Complexity Triage, Pattern 1.3）
       → Trivial/Low: Express/Light 模式，不启用 Ralph
       → Medium+: Standard/Full 模式，继续 ↓
  → 2. 选择 hook profile（Pattern 6.2）
       → 按复杂度等级启用对应的 Stop hook 组合
  → 3. 初始化 Ralph（ralph-init.sh <id> [max]）
       → 创建 sessions/<id>/ralph.json 状态文件
       → 如有残留状态，从上次迭代恢复
  → 4. Agent 正常执行任务
       → 编辑文件、运行命令、调用工具...
  → 5. Agent 尝试停止 → Stop hook 触发
       → 5a. 安全阀检查（MUST 先于任何 block 逻辑）
            → context >= 95%? → 放行
            → 401/403 认证失败? → 放行
            → cancel 信号存在且未过期? → 放行
            → 闲置 > 2h? → 放行
            → 迭代 >= max? → 放行
       → 5b. Doubt gate 检查（Pattern 1.2）
            → 回复含投机语言? → block，要求提供证据
       → 5c. Task completion 检查（Pattern 1.4）
            → harness-tasks.json 有未完成项? → block，注入缺失项
       → 5d. Ralph 迭代检查（Pattern 1.1）
            → active=true 且 iteration < max? → block，注入续航指令
       → 所有检查通过 → 放行停止
```

MUST 按上述顺序执行安全阀检查，否则在 context 即将溢出时 Ralph 仍会 block 导致 session 崩溃。

不要在简单任务上启用全部 hook，而是根据 Adaptive Complexity Triage 选择合适的 profile——Trivial 任务走 Express 跳过 Ralph，Medium+ 才启用完整循环。

如果不确定任务复杂度应该选哪个等级，询问用户或默认 Standard（NEVER 默认 Express，Express 跳过验证）。

<example>
场景：7 文件 API 重构，Ralph 保持 agent 持续工作

用户任务：「把 user-service 的 7 个 endpoint 从 REST 迁移到 gRPC」
1. Adaptive Complexity Triage → High（7 文件，架构变更）→ Full 模式
2. ralph-init.sh api-migration 50 → 创建状态文件，max=50
3. Agent 改完第 1 个 endpoint 后尝试停止
   → Ralph block:「[RALPH LOOP 1/50] Task is NOT done. 还有 6 个 endpoint 未迁移。」
4. Agent 继续，改完第 3 个后又停
   → Task completion gate block:「未完成项: endpoint-4, endpoint-5, endpoint-6, endpoint-7」
5. Agent 改完全部 7 个 endpoint 后停止
   → Doubt gate 检查通过（无投机语言）
   → Task completion 检查通过（全部 done=true）
   → Ralph 放行
6. 实际迭代数: 12/50，agent 自然完成
</example>

<anti-example>
错误用法：对简单 typo 修复启用 Ralph

用户任务：「README 里 'recieve' 拼错了，改成 'receive'」
错误做法：ralph-init.sh typo-fix 50 → 启用全流程 → agent 改完 1 行后被 Ralph block
  → 被迫继续"寻找更多拼写错误"→ 引入不必要的改动 → 浪费 token
正确做法：Adaptive Complexity Triage → Trivial → Express 模式 → 不启用 Ralph → agent 改完即停
</anti-example>

## Output

| 产物 | 路径 | 说明 |
|------|------|------|
| Ralph 状态文件 | `sessions/<session-id>/ralph.json` | 记录 active、iteration、max_iterations、时间戳。原子写入（write-then-rename） |
| Doubt gate 守卫文件 | `$TMPDIR/doubt-gate-<session-id>` | 防止 doubt gate 同一轮重复触发。临时文件，触发后创建，放行后删除 |
| 任务清单 | `.harness-tasks.json` | 任务 checklist，格式 `{tasks: [{name, done}]}`。agent 完成子任务后标记 `done: true` |

## Related

| Skill | 关系 |
|-------|------|
| `tool-governance` | 上游：提供工具错误数据。工具连续失败时由 tool-governance 处理，不属于 execution-loop 范围 |
| `context-memory` | 互补：阶段边界时写 handoff document。Ralph 到达 max 或 context 接近上限时，应触发 context-memory 保存决策 |
| `quality-verification` | 下游：agent 完成编辑后由 quality-verification 做 post-edit 检查（lint、type check、测试） |
