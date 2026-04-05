---
name: execution-harness
version: 0.2.0
description: 当需要让 dispatch 出去的 Claude Code agent 持续执行不中断、跨阶段保留决策上下文、或处理工具重试/限速恢复时使用。不用于任务调度（用 orchestrator-planner）、不用于通知路由（用 nanocompose-dispatch 的 callback）、不用于 skill 质量评估（用 improvement-learner）。参见 nanocompose-dispatch（单任务派发）、orchestrator-planner（批量 DAG 编排）。
license: MIT
triggers:
  - harness
  - ralph
  - 持续执行
  - 不要停
  - keep going
  - handoff
  - context survival
  - 限速
  - rate limit
  - 工具重试
  - tool retry
  - 上下文存活
metadata: {"openclaw": {"emoji": "🔧", "requires": {"bins": ["jq", "tmux"]}}}
---

# Execution Harness Patterns

蒸馏自 Claude Code 内部架构分析 + oh-my-claudecode (OMC) 实现，适配 OpenClaw 编排体系。

## Pattern 1: 持续执行循环（Ralph 模式）

通过 Stop hook 阻止会话终止，注入续航指令。无需外部 daemon。

**仅适用于 interactive 模式**。Headless（`-p`）模式没有 Stop 事件，用 `--max-turns` 控制。

### 启用方式

```bash
# 在 dispatch 时启用 ralph 模式
dispatch.sh --type bugfix --id WI123 --ralph --max-iterations 50 \
  --prompt "修复 WI-123 的内存泄漏，完成后运行全量测试"
```

### 工作原理

1. dispatch 创建 `~/.openclaw/shared-context/ralph/<session-id>.json`
2. Stop hook 检查该文件：如果 `active: true` 且 `iteration < max`，阻止停止并注入"继续工作"
3. 每次阻止递增 iteration 计数
4. 安全阀：context usage >= 95%、用户 Ctrl-C、认证错误时**不阻止**
5. 闲置超时：2 小时无活动自动释放

### 状态文件格式

```json
{
  "session_id": "nc-bugfix-WI123",
  "active": true,
  "iteration": 3,
  "max_iterations": 50,
  "created_at": "2026-04-05T10:00:00Z",
  "last_checked_at": "2026-04-05T10:15:00Z"
}
```

### Stop Hook 实现（两种模式）

**模式 A: Shell 脚本（当前实现）** — `scripts/ralph-stop-hook.sh`
读取 stdin JSON，检查 ralph 状态，输出 block/continue 决策。
安全优先：context 溢出、认证失败、cancel 信号时直接放行。

**模式 B: Prompt-type hook（推荐升级）**
用 LLM 本身判断任务是否完成，比 shell 脚本准确得多：

```json
{
  "hooks": [{
    "type": "prompt",
    "prompt": "检查当前任务是否已全部完成。评估标准：所有修改的文件已保存，测试已通过，无遗留 TODO。如果未完成，返回 {\"decision\":\"block\",\"reason\":\"未完成：<具体原因>\"}；如果已完成，返回 {\"decision\":\"allow\"}。"
  }]
}
```

模式 B 能捕捉 shell 脚本无法检测的语义级未完成状态（如"修了 bug 但没写测试"）。

---

## Pattern 1.5: Agent-type 验证门禁

比 prompt hook 更强——生成一个有完整工具访问权的 subagent 做多步验证：

```json
{
  "hooks": [{
    "type": "agent",
    "agent": "验证当前任务的完成质量：1) 读取修改的文件确认改动正确 2) 检查是否有遗留的 TODO/FIXME 3) 确认测试覆盖率。返回验证结果。"
  }]
}
```

适用场景：dispatch 高价值任务（如 MR review、安全修复）时，在 agent 声称"完成"后自动验证。

---

## Pattern 2: Handoff 文档（上下文存活）

长任务中 context 被压缩时，关键决策信息丢失。每个阶段结束时自动生成 handoff 文档。

### 文档结构

```markdown
# Handoff: <stage-name>
## Decided
- 选择了 X 方案因为 Y
## Rejected
- 排除了 Z 方案因为 W
## Risks
- 风险点列表
## Files Modified
- path/to/file.cpp (原因)
## Remaining
- 未完成的工作
```

### 存储位置

```
~/.openclaw/shared-context/handoffs/<session-id>/
  stage-1-plan.md
  stage-2-exec.md
  stage-3-verify.md
```

### 使用场景

- **dispatch 多阶段任务**：每个阶段的 agent 在结束前写 handoff
- **orchestrator batch**：batch 之间传递 handoff 文档作为下一批次的上下文
- **crash recovery**：resume 时自动注入最新 handoff

### 集成方式

在 agent prompt 尾部追加：
```
在完成当前阶段前，将关键决策写入 handoff 文档：
~/.openclaw/shared-context/handoffs/${SESSION_ID}/stage-${STAGE}.md
格式：Decided / Rejected / Risks / Files Modified / Remaining
```

---

## Pattern 3: 工具错误重试升级

防止工具调用进入无限重试死循环。

### 升级策略

| 连续失败次数 | 行为 |
|-------------|------|
| 1-2 | 正常重试，可能是瞬时错误 |
| 3-4 | 注入"换个参数/路径试试"提示 |
| 5+ | 注入"必须用替代方案"，禁止继续重试同一工具 |

### 实现

PostToolUseFailure hook 写入 `last-tool-error.json`：

```json
{
  "tool_name": "Bash",
  "error": "command not found: cargo",
  "count": 5,
  "first_at": "2026-04-05T10:00:00Z",
  "last_at": "2026-04-05T10:02:30Z"
}
```

PreToolUse hook 读取该文件，当 count >= 5 时在 additionalContext 中注入替代方案建议。

---

## Pattern 4: Rate Limit 检测与恢复

### tmux 会话限速检测

```bash
# scripts/rate-limit-watch.sh
# 扫描所有 nc-* tmux 会话，检测限速消息
tmux list-panes -a -F '#{session_name} #{pane_id}' | grep '^nc-' | while read sess pane; do
  tail=$(tmux capture-pane -t "$pane" -p -S -20 2>/dev/null)
  if echo "$tail" | grep -qiE 'rate.?limit|429|too many requests|usage limit'; then
    echo "$sess:$pane:limited"
  fi
done
```

### 自动恢复

当检测到限速解除（通过 API 状态或等待时间），向 tmux pane 发送回车键恢复：
```bash
tmux send-keys -t "$pane" "" Enter
```

### 集成到 session-monitor

在现有 session-monitor.sh 中增加限速检测扫描，发现限速时通过 DingTalk 通知。

---

## Pattern 5: Transcript 尾部读取（轻量上下文估算）

### 原理

Claude Code 的 transcript 是 JSONL 文件，可能达 100MB+。只读最后 4KB 即可提取 `context_window` 和 `input_tokens`。

### 实现

```bash
# scripts/context-usage.sh
transcript="$1"
if [ -f "$transcript" ]; then
  size=$(stat -f%z "$transcript" 2>/dev/null || stat -c%s "$transcript")
  if [ "$size" -gt 4096 ]; then
    tail -c 4096 "$transcript" | grep -o '"input_tokens":[0-9]*' | tail -1
    tail -c 4096 "$transcript" | grep -o '"context_window":[0-9]*' | tail -1
  fi
fi
```

### 用途

- Stop hook 中判断是否已接近 context 上限（>= 95% 时放行 stop，不要用 ralph 阻止）
- session-monitor 中显示各会话的 context 使用率

---

## Pattern 6: 原子文件写入

所有状态文件使用 write-then-rename 模式防止损坏：

```bash
write_atomic() {
  local target="$1" content="$2"
  local tmp="${target}.${$}.$(date +%s).tmp"
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

---

## Pattern 7: Cancel Signal with TTL

取消信号带 30 秒过期时间，防止旧信号影响新会话：

```json
{
  "requested_at": "2026-04-05T10:30:00Z",
  "expires_at": "2026-04-05T10:30:30Z",
  "reason": "user_abort"
}
```

Ralph stop hook 检查 cancel 信号时，过期信号直接忽略。

---

## Pattern 8: Compaction 前记忆提取（Save Before Delete）

当 context 接近上限触发压缩时，在丢弃旧消息之前先提取持久化知识。

### 工作原理

1. PreCompact hook 触发记忆提取
2. 从即将被压缩的 context 中提取 Decided/Learned/Risks 信息
3. 写入 handoff 文档或 memory 文件
4. 压缩后的 agent 仍可访问提取的知识

### 与 Handoff 的区别

Handoff 是主动写入（agent 在阶段结束时自行总结），记忆提取是被动抢救（系统在压缩前自动提取）。两者互补。

### 集成方式

在 PreCompact hook 中注入提取指令：
```
在 context 被压缩前，将关键决策和发现写入：
~/.openclaw/shared-context/handoffs/${SESSION_ID}/pre-compact.md
```

---

## Pattern 9: 权限否决追踪（Denial Circuit Breaker）

当同一工具调用被反复拒绝时，自动降级执行模式，防止 agent 无限重试被禁止的操作。

### 升级策略

| 连续否决次数 | 行为 |
|-------------|------|
| 1-2 | 正常，可能是误触 |
| 3+ | 注入"换个方案，这个操作被禁止了"提示 |
| 5+ | 标记该工具+参数组合为 session 级禁止 |

### 与工具错误升级的区别

工具错误升级处理的是"工具执行失败"（cargo not found），权限否决追踪处理的是"用户/策略拒绝"（不允许写这个文件）。

---

## Pattern 10: 三门控记忆合并（3-Gate Consolidation）

多次 session 后自动合并记忆，避免记忆碎片化。

### 三个门控

1. **Time Gate**: 距上次合并 >= 24h
2. **Session Gate**: 有 >= 5 个新 session 待处理
3. **Lock Gate**: 其他进程未在合并中（防并发）

### 用途

当 `~/.openclaw/shared-context/handoffs/` 目录下积累了大量碎片化 handoff 文档时，合并为精简的经验总结。

---

## Pattern 11: Hook Pair Bracket（每轮测量框架）

用 UserPromptSubmit + Stop 配对，在每轮 agent 交互前后建立测量/执行框架。

### 工作原理

1. **UserPromptSubmit hook**（"before"）：记录轮次开始时间、当前 context 使用量，写入 `$TMPDIR/harness-${session_id}.json`
2. **Stop hook**（"after"）：读取开始状态，计算本轮 context 增量、耗时、工具调用数

### 用途

- 每轮 context 预算强制执行（当单轮消耗 > 阈值时告警）
- 工具调用统计（哪些工具被频繁使用/失败）
- 长任务进度追踪（第 N 轮，已用 X% context）

### 与 Ralph 的关系

Ralph 的 Stop hook 决定"是否阻止停止"。Hook pair bracket 不阻止，只测量和记录。两者可叠加：先 bracket 记录数据，再 ralph 决定是否 block。

---

## Pattern 12: Component-Scoped Hooks

每个 skill 或 agent 可以在自己的 frontmatter 中定义 hooks，只在该组件激活时生效。

### 示例

```yaml
---
name: security-fix
hooks:
  Stop:
    - type: agent
      agent: "验证安全修复：检查修改的文件无新增漏洞，敏感数据已清理。"
---
```

### 用途

- 高价值 dispatch 任务（安全修复、生产热修）自带验证门禁
- 不污染全局 hooks 配置
- Skill 级别的质量保证

---

## 与现有系统集成

| 模式 | 集成点 | 优先级 |
|------|--------|--------|
| Ralph 持续执行 | dispatch.sh + Stop hook | P0 — 直接提升长任务完成率 |
| Handoff 文档 | dispatch.sh prompt 注入 + orchestrator batch 间传递 | P0 — 解决 context 压缩丢信息 |
| 工具错误升级 | PostToolUseFailure + PreToolUse hooks | P1 — 减少无效重试 |
| Rate Limit 恢复 | session-monitor.sh 扩展 | P1 — 减少人工干预 |
| Context 估算 | Stop hook + session-monitor | P2 — 可观测性 |
| 原子写入 | 所有状态文件操作 | P2 — 可靠性基础 |
| Cancel TTL | ralph-stop-hook.sh | P2 — 安全阀 |
| Compaction 记忆提取 | PreCompact hook | P0 — 被动抢救压缩前的知识 |
| 权限否决追踪 | PreToolUse hook | P1 — 防止重试被禁操作 |
| 三门控记忆合并 | cron / session-end | P2 — 减少 handoff 碎片 |
| Prompt-type Stop hook | settings.json Stop hook | P0 — LLM 语义完成度判断 |
| Agent-type 验证门禁 | settings.json Stop hook | P1 — 多步质量验证 |
| Hook pair bracket | UserPromptSubmit + Stop | P1 — 每轮测量和预算 |
| Component-scoped hooks | SKILL.md frontmatter | P2 — skill 级质量门禁 |
| Session-scoped 状态隔离 | 状态目录重构 | P0 — 结构基础，简化清理和恢复 |
| Session state rehydration | ralph-init.sh + resume | P0 — crash 后恢复执行状态 |
| `updatedInput` 工具改写 | PreToolUse hook | P1 — 确定性工具输入修正 |
| `maxTurns` subagent 预算 | Agent-type hook 参数 | P1 — 防止验证 agent 无限循环 |
| `context: fork` 隔离 | dispatch subagent | P2 — 防止子 agent 污染父 context |
| `once: true` 单次 hook | UserPromptSubmit hook | P2 — 一次性初始化 |
| Subagent 记忆持久化 | learnings JSONL | P2 — 跨 session 知识传递 |

## 工作流程

### Step 1: 初始化

当 dispatch 任务时，根据需要选择启用的模式：
- 如果任务需要持续执行 → `ralph-init.sh <session-id> [max-iterations]`
- 如果任务是多阶段 → 在 prompt 中注入 handoff 文档指令

### Step 2: 执行期间

Stop hook 自动介入，MUST 在以下条件满足时阻止停止，otherwise agent 会提前退出导致任务不完整：
- ralph 状态 active 且未达到 max_iterations
- 当 context usage >= 95% 时，MUST 放行 stop，否则会导致 context 溢出崩溃

### Step 3: 结束与清理

当任务完成或达到上限时，ralph 自动释放。如果不确定是否需要手动取消，使用 `ralph-cancel.sh`。

## Output

| 脚本 | 输出 |
|------|------|
| `ralph-init.sh` | 创建 `~/.openclaw/shared-context/ralph/<session-id>.json` |
| `ralph-stop-hook.sh` | JSON: `{"continue":true}` 或 `{"decision":"block","reason":"..."}` |
| `ralph-cancel.sh` | 创建 `~/.openclaw/shared-context/cancel/<session-id>.json`（30s TTL） |

## 不做的事

- **不要包装 Claude Code CLI**，而是通过 hooks 集成——我们不是 OMC，包装层增加复杂度却不增加可靠性
- **不要自建 keyword detector**，而是用现有 skill 触发词机制——避免重复建设
- **不要做 HUD 状态栏**，而是用 session-monitor + DingTalk 通知——已有可观测方案
- **不要混合多模型团队**，而是专注 Claude——减少集成表面积
