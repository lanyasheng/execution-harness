---
name: execution-harness
version: 1.0.0
description: Claude Code agent 执行可靠性增强。当 agent 提前停止、context 压缩丢失决策、工具重试死循环、或限速后挂死时使用。提供 Stop hook 持续执行、handoff 文档上下文存活、工具错误升级、限速恢复等 12 个可组合模式。不用于任务调度或编排（这是执行层，不是调度层）。参见 Claude Code hooks 文档了解 hook 机制。
license: MIT
triggers:
  - harness
  - ralph
  - persistent execution
  - 持续执行
  - 不要停
  - keep going
  - handoff
  - context survival
  - 上下文存活
  - rate limit
  - 限速恢复
  - tool retry
  - 工具重试
  - agent keeps stopping
  - crash recovery
  - session state
---

# Execution Harness Patterns

Claude Code agent 执行可靠性增强模式集合。解决 agent 在长任务中的 5 类常见失败：提前停止、上下文丢失、重试死循环、限速挂死、crash 后状态丢失。

蒸馏自 Claude Code 内部架构（Query Engine、Tool System、Permission Pipeline、Context Management、Session Persistence）和 oh-my-claudecode (OMC) 的生产实践。

## When to Use

- Agent 在多文件修改任务中只改了一部分就停了
- 长任务中 context 被压缩后，agent 忘记了之前的设计决策
- 工具调用反复失败但 agent 一直重试同一个命令
- Agent 遇到 API 限速后 tmux session 挂死
- 需要 crash 后恢复执行进度而不是从头开始

## When NOT to Use

- 任务调度和依赖管理（那是编排层的工作，不是执行层）
- 单次简单任务（不需要持续执行保障）
- Headless `-p` 模式（Stop hook 不触发，用 `--max-turns` 代替）

---

## Pattern 1: 持续执行循环（Ralph 模式）

**问题**：Claude Code agent 在复杂任务中经常"觉得自己做完了"就停了，实际上只完成了一部分。

**原理**：Claude Code 的 Stop hook 在 agent 尝试结束会话时触发。通过在 Stop hook 中返回 `{"decision":"block","reason":"..."}` 可以阻止终止并注入续航指令，让 agent 继续工作。这个机制来自 OMC 的 `persistent-mode.mjs`——OMC 最核心的设计之一，整个 ralph/autopilot/team 持续执行系统都建立在这个 Stop hook 机制上。

**仅适用于 interactive 模式**。Headless（`-p`）模式没有 Stop 事件循环。

### 工作原理

```
Agent 尝试停止
  → Stop hook 触发
    → 读取 sessions/<session-id>/ralph.json
      → active=true 且 iteration < max?
        → 是: 阻止停止，注入"继续工作"，iteration++
        → 否: 放行停止
```

### 5 个安全阀（NEVER block）

Stop hook 在以下条件下 MUST 放行，不管 ralph 状态如何：

1. **Context 上限**：usage >= 95%。阻止会导致 context 溢出崩溃。Claude Code 内部在 `context_window` 和 `input_tokens` 比值达到 95% 时会触发紧急压缩（reactive compact），此时 Stop hook 必须让路。
2. **认证失败**：401/403 错误。Token 过期或权限被撤销，继续执行无意义。
3. **Cancel 信号**：带 TTL 的取消文件存在且未过期（见 Pattern 7）。
4. **闲置超时**：2 小时无活动。防止 zombie 状态永远占用资源。OMC 使用 `STALE_STATE_THRESHOLD_MS = 7200000` 作为阈值。
5. **迭代上限**：达到 `max_iterations`。防止无限循环。

### 状态文件

```json
{
  "session_id": "my-bugfix-task",
  "active": true,
  "iteration": 3,
  "max_iterations": 50,
  "created_at": "2026-04-05T10:00:00Z",
  "last_checked_at": "2026-04-05T10:15:00Z"
}
```

存储在 `sessions/<session-id>/ralph.json`。所有状态文件使用 write-then-rename 原子写入防止并发损坏。

### 初始化

```bash
# 初始化 ralph 状态（session-id, max-iterations）
scripts/ralph-init.sh my-task-001 50

# 如果检测到已有 active 状态（crash 恢复），自动从上次迭代继续
# 输出: "Resuming ralph from iteration 37 (previous state: active=true, reason=stale)"
```

### Crash 恢复

`ralph-init.sh` 在初始化前检查是否存在残留状态。如果发现 `active: true` 或 `deactivation_reason: "stale"` 的状态文件，不会重置迭代计数器，而是从上次位置恢复。这解决了 agent 在第 37 轮 crash 后重启从第 0 轮开始的问题。

### settings.json 配置

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bash /path/to/execution-harness/scripts/ralph-stop-hook.sh"
      }]
    }]
  }
}
```

### 两种 Stop Hook 实现

**模式 A: Shell 脚本（已实现，`scripts/ralph-stop-hook.sh`）**

基于 JSON 状态文件的确定性检查。读 stdin（Claude Code hook 协议），读状态文件，输出 block/continue JSON。优点：快速、零 API 成本、可预测。缺点：只能做迭代计数检查，无法判断任务是否"语义上完成"。

**模式 B: Prompt-type hook（推荐用于高价值任务）**

用 LLM 本身判断任务是否完成。Claude Code 支持 `type: "prompt"` 的 hook，hook 内容作为 prompt 发给模型，模型返回结构化 JSON 决策。

```json
{
  "hooks": [{
    "type": "prompt",
    "prompt": "检查当前任务是否已全部完成。评估标准：1) 所有需要修改的文件已保存 2) 测试已通过 3) 无遗留 TODO/FIXME 4) 改动覆盖了原始需求的所有要点。如果未完成，返回 {\"decision\":\"block\",\"reason\":\"未完成：<具体缺失项>\"}；如果已完成，返回 {\"decision\":\"allow\"}。"
  }]
}
```

优点：能捕捉"修了 bug 但没写测试"、"改了 3 个文件但还有 2 个没改"等语义级未完成状态。缺点：每次 Stop 都消耗一次 API 调用。

**模式 C: Agent-type hook（最强，用于关键任务）**

生成一个有完整工具访问权（Read、Grep、Bash）的 subagent 做多步验证：

```json
{
  "hooks": [{
    "type": "agent",
    "agent": "验证当前任务完成质量：1) 读取所有修改的文件确认改动正确 2) 运行 grep 检查无遗留 TODO/FIXME 3) 如果有测试文件，运行 bash 确认测试通过。返回结构化验证结果。"
  }]
}
```

优点：能实际读文件、跑测试、检查编译。缺点：最慢、消耗最多 token。建议配合 `maxTurns: 10` 限制验证 agent 的执行轮数，防止验证本身无限循环。

### block 消息设计

OMC 的 Ralph 注入的 block 消息很简单："Work is NOT done. Continue working."。根据 prompt-hardening 的 P5（反推理阻断）原则，更有效的消息应该预判 agent 的"合理化"倾向：

```
[RALPH LOOP 5/50] Task is NOT done.
Do NOT rationalize that "the remaining work can be done in a follow-up."
Do NOT claim completion with caveats.
Check your original task description and verify EVERY requirement is met.
Continue working on the original task.
```

---

## Pattern 2: Handoff 文档（上下文存活）

**问题**：Claude Code 的 context window 有限。长任务中会触发 auto-compact（4 级压缩：MicroCompact → Session Memory → Full Compact → Reactive Compact），压缩后关键设计决策、排除过的方案、已识别的风险都会丢失。

**原理**：在阶段结束或 context 压缩前，将关键信息写入磁盘文件。压缩后的 agent 可以通过读取这些文件恢复上下文。这比依赖 Claude Code 的压缩摘要更可控——你决定保留什么，而不是让压缩算法决定。

### 文档结构（5 个必要段落）

```markdown
# Handoff: <stage-name>

## Decided
- 选择 Redis 作为缓存方案，因为项目已有 Redis 依赖，无需新增基础设施
- 使用 LRU 策略，TTL 设为 5 分钟

## Rejected
- 排除 Memcached：团队无运维经验
- 排除本地文件缓存：不支持多实例部署

## Risks
- Redis 单点故障需要 Sentinel（当前未配置）
- 缓存穿透风险：高频查询的 key 需要布隆过滤器

## Files Modified
- src/cache/redis_client.py — 新建，Redis 连接池封装
- src/api/handlers.py:45-67 — 添加缓存查询层
- tests/test_cache.py — 缓存命中/未命中/过期测试

## Remaining
- Sentinel 配置（下个迭代）
- 缓存预热逻辑
- 监控指标接入
```

### 存储位置

```
sessions/<session-id>/handoffs/
  stage-1-plan.md
  stage-2-implement.md
  stage-3-verify.md
  pre-compact.md          ← 压缩前自动抢救（见 Pattern 8）
```

### 注入方式

在 agent 的 prompt 尾部追加：
```
在完成当前阶段前，将关键决策写入 handoff 文档：
sessions/<session-id>/handoffs/stage-<当前阶段>.md
必须包含 5 个段落：Decided / Rejected / Risks / Files Modified / Remaining
```

下一阶段的 agent 启动时，通过 UserPromptSubmit hook 或 prompt 注入最新的 handoff 文档。

### 为什么不依赖 Claude Code 的内置压缩

Claude Code 的 Full Compact 使用 LLM 生成 9 段式结构化摘要，质量不错但有两个问题：
1. 摘要内容由 LLM 决定，你无法控制保留什么
2. 使用 `<analysis>` scratchpad 提高摘要质量但 strip 后注入（chain-of-thought 不进入压缩后的 context），意味着推理过程丢失

Handoff 文档让你显式控制保留的信息，和内置压缩互补而非替代。

---

## Pattern 3: 工具错误重试升级

**问题**：Agent 调用工具失败后会重试，但经常用完全相同的参数重试同一个失败的工具。5 次 `cargo build` 失败（因为容器里没装 cargo）后还在 `cargo build`。

**原理**：通过 PostToolUseFailure hook 追踪连续失败次数，在 PreToolUse hook 中注入逐级升级的干预消息。来自 OMC 的 `post-tool-use-failure.mjs`——OMC 在 5 次失败后注入"ALTERNATIVE APPROACH NEEDED"。

### 三级升级策略

| 连续失败次数 | Hook 行为 | 注入消息 |
|-------------|----------|---------|
| 1-2 | 记录但不干预 | （无） |
| 3-4 | PreToolUse 注入软提示 | "该工具已失败 3 次。考虑：换一个参数？换一个路径？是否缺少依赖？" |
| 5+ | PreToolUse 注入强制切换 | "MUST use an alternative approach. This tool+args combination has failed 5 times. Previous errors: [error summary]. Do NOT retry the same command." |

### 状态文件

```json
{
  "tool_name": "Bash",
  "input_hash": "a3f2c1...",
  "error": "command not found: cargo",
  "count": 5,
  "first_at": "2026-04-05T10:00:00Z",
  "last_at": "2026-04-05T10:02:30Z"
}
```

`input_hash` 是工具输入的哈希（取前 200 字符），区分"同一个命令反复失败"和"不同命令分别失败"。只有相同 tool_name + input_hash 的连续失败才计数升级。

### 与 `updatedInput` 的组合

Claude Code 的 PreToolUse hook 支持返回 `updatedInput` 字段，可以在执行前直接修改工具输入。这比在 additionalContext 中"建议"换方案更确定——直接改写命令：

```json
{
  "updatedInput": {
    "command": "pip install cargo-alternative && cargo-alternative build"
  }
}
```

additionalContext 是概率性的（LLM 可能忽略建议），updatedInput 是确定性的（直接改写输入）。

---

## Pattern 4: Rate Limit 检测与恢复

**问题**：Agent 在 tmux session 中遇到 API 限速后会挂在那里等待，但没有自动恢复机制。限速解除后需要人工去 tmux 里按回车。

**原理**：周期性扫描 tmux pane 内容，检测限速关键词。限速解除后发送按键恢复。来自 OMC 的 `rate-limit-wait/daemon.js`——一个后台 daemon，轮询 API usage endpoint + 扫描 tmux pane，自动恢复。

### 检测

```bash
# 扫描所有 Claude Code tmux 会话
tmux list-panes -a -F '#{session_name} #{pane_id}' | while read sess pane; do
  tail=$(tmux capture-pane -t "$pane" -p -S -20 2>/dev/null)
  if echo "$tail" | grep -qiE 'rate.?limit|429|too many requests|usage limit'; then
    echo "$sess:$pane:limited"
  fi
done
```

### 恢复

```bash
# 限速解除后发送回车恢复
tmux send-keys -t "$pane" "" Enter
```

### OMC 的完整方案（参考）

OMC 的实现更完善：
1. **Rate Limit Monitor**：调用 Claude Code 的 OAuth API 获取 usage 数据，检查 5 小时/周/月 三个窗口
2. **Tmux Detector**：不只检测关键词，还有置信度评分（`hasClaudeCode`, `hasRateLimitMessage`, `isBlocked`）
3. **Stale Data Handling**：当 usage API 本身返回 429 时，使用缓存数据并标记 `usingStaleData: true`
4. **PID 文件**：单实例强制，防止多个 daemon 同时运行
5. **State 持久化**：`blockedPanes`, `resumedPaneIds`, 成功/失败计数写入磁盘（权限 0o600）

---

## Pattern 5: 轻量 Context 使用量估算

**问题**：需要知道 agent 的 context window 用了多少，但 transcript JSONL 文件可能 100MB+，不能全部读取。

**原理**：Claude Code 的 transcript 是 append-only JSONL。最新的 API 响应总在文件末尾，包含 `context_window` 和 `input_tokens` 字段。只读最后 4KB 足以提取这些值。来自 Claude Code 内部的 HUD 实现和 OMC 的 `context-guard-stop.mjs`。

### 实现

```bash
transcript="$1"
if [ -f "$transcript" ]; then
  size=$(stat -f%z "$transcript" 2>/dev/null || stat -c%s "$transcript")
  if [ "$size" -gt 4096 ]; then
    input=$(tail -c 4096 "$transcript" | grep -o '"input_tokens":[0-9]*' | tail -1 | grep -o '[0-9]*')
    window=$(tail -c 4096 "$transcript" | grep -o '"context_window":[0-9]*' | tail -1 | grep -o '[0-9]*')
    if [ -n "$input" ] && [ -n "$window" ] && [ "$window" -gt 0 ]; then
      usage=$(( input * 100 / window ))
      echo "Context usage: ${usage}% (${input}/${window} tokens)"
    fi
  fi
fi
```

### 用途

1. **Stop hook 中的安全阀**：当 usage >= 95% 时，Ralph MUST 放行 stop（见 Pattern 1 安全阀 #1）
2. **Hook pair bracket 中的预算追踪**：每轮记录 context 增量（见 Pattern 11）
3. **外部监控**：周期性检查所有运行中 session 的 context 使用率

### Claude Code 的 token 估算精度

Claude Code 内部使用 3 级精度估算：
- **粗估**：bytes / 4（零成本，毫秒级）
- **代理**：Haiku input count（便宜但需要 API 调用）
- **精确**：countTokens API（慢但准确）

粗估还加 33% 保守缓冲：`Math.ceil(totalTokens * (4/3))`。transcript 尾部读取得到的是 API 返回的实际值，精度等同于精确级。

---

## Pattern 6: 原子文件写入

**问题**：Ralph stop hook 和外部监控可能同时读写同一个状态文件。直接写入可能导致读到半写的 JSON。

**原理**：先写到临时文件，再原子 rename。`rename` 在 POSIX 文件系统上是原子操作。来自 Claude Code 内部所有状态文件的写入模式。

```bash
write_atomic() {
  local target="$1" content="$2"
  local tmp="${target}.${$}.$(date +%s).tmp"
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

`${$}` 是当前进程 PID，`$(date +%s)` 是时间戳，两者组合确保临时文件名唯一。

---

## Pattern 7: Cancel Signal with TTL

**问题**：用户发送取消信号后，如果新 session 复用了同一个 session-id，旧的取消信号会错误地阻止新 session。

**原理**：取消信号带 30 秒过期时间。过期后自动忽略。来自 OMC 的 `CANCEL_SIGNAL_TTL_MS = 30000`。

```json
{
  "requested_at": "2026-04-05T10:30:00Z",
  "expires_at": "2026-04-05T10:30:30Z",
  "reason": "user_abort"
}
```

```bash
# 发送取消信号
scripts/ralph-cancel.sh <session-id> [reason]
# 创建 sessions/<session-id>/cancel.json（30 秒后过期）
```

Ralph stop hook 检查 cancel 信号时：
- 存在且未过期 → 停止 ralph，允许 agent 退出
- 存在但已过期 → 删除信号文件，继续 ralph 循环
- 不存在 → 继续 ralph 循环

---

## Pattern 8: Compaction 前记忆提取（Save Before Delete）

**问题**：Claude Code 的 auto-compact 在 context 接近上限时自动触发。压缩会丢弃旧消息，其中可能包含重要的设计决策和发现。

**原理**：利用 Claude Code 的 PreCompact hook，在压缩发生前提取关键信息到磁盘。来自 Claude Code 内部的 `buildExtractAutoOnlyPrompt` 和 `buildExtractCombinedPrompt`——Claude Code 在压缩时并行提取 memory。

### 与 Handoff 文档的区别

| | Handoff 文档 (Pattern 2) | Compaction 提取 (Pattern 8) |
|---|---|---|
| 触发时机 | 阶段结束时（主动） | 压缩触发时（被动） |
| 触发者 | Agent 自行写入 | PreCompact hook 自动注入 |
| 内容控制 | 完全由 agent 决定 | 由 hook prompt 引导 |
| 可靠性 | 依赖 agent 遵守指令 | 系统级保证 |

两者互补：handoff 是计划内的上下文传递，compaction 提取是应急的知识抢救。

### 实现

settings.json 中配置 PreCompact hook：

```json
{
  "hooks": {
    "PreCompact": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Context 即将被压缩。在压缩前，将以下信息写入 handoff 文档：1) 当前任务的完成状态 2) 已做的关键决策及原因 3) 已排除的方案 4) 已知风险 5) 下一步计划。写入路径：sessions/<session-id>/handoffs/pre-compact.md"
      }]
    }]
  }
}
```

---

## Pattern 9: 权限否决追踪（Denial Circuit Breaker）

**问题**：Agent 尝试执行被用户/策略拒绝的操作后，可能换一种表述再试——"我用 `rm` 删不了，试试 `unlink`"。

**原理**：追踪被拒绝的工具调用模式。连续多次否决后，从"允许但提醒"降级到"会话级禁止"。来自 Claude Code 内部的 `DenialTrackingState`——3 次连续否决或 20 次总否决后，系统从 auto 模式退回 default 模式（`shouldFallbackToPrompting`）。

### 三级降级

| 连续否决次数 | 行为 |
|-------------|------|
| 1-2 | 记录，不干预 |
| 3+ | 注入 additionalContext："该操作已被拒绝 3 次。MUST 使用完全不同的方案，不要变换表述重试相同操作。" |
| 5+ | 标记 tool_name + input_pattern 为 session 级禁止。PreToolUse hook 直接 `{"decision":"block"}` |

### 与工具错误升级 (Pattern 3) 的区别

| | 工具错误升级 | 权限否决追踪 |
|---|---|---|
| 触发 | 工具执行失败（exit code != 0） | 用户/策略拒绝（permission denied） |
| 原因 | 技术问题（依赖缺失、路径错误） | 策略问题（不允许该操作） |
| 解决方向 | 换参数/换工具 | 换完全不同的方案 |

---

## Pattern 10: 三门控记忆合并（3-Gate Consolidation）

**问题**：跨多个 session 积累了大量碎片化的 handoff 文档和记忆文件，重复信息多、互相矛盾。

**原理**：定期合并记忆，但用三个门控避免不必要的合并操作。来自 Claude Code 内部的 AutoDream——一个 "sleep consolidation" 机制，在 session 之间自动整理积累的知识。

### 三个门控

1. **Time Gate**：距上次合并 >= 24 小时。避免频繁合并。
2. **Session Gate**：有 >= 5 个新 session 积累。确保有足够的新内容值得合并。
3. **Lock Gate**：获取文件锁确认无其他进程正在合并。10 次重试，5-100ms 指数退避。

三个门控按计算成本从低到高排列。时间检查最便宜（读一个时间戳），session 计数次之（数文件数），加锁最贵（文件系统操作）。任一门控失败，跳过本次合并。

### 合并操作

通过门控后，遍历所有 `sessions/*/handoffs/` 目录：
1. 按时间排序所有 handoff 文档
2. 提取 Decided/Rejected 段落
3. 合并去重，解决冲突（后来的决策覆盖早期的）
4. 写入精简的经验总结文件

---

## Pattern 11: Hook Pair Bracket（每轮测量框架）

**问题**：无法知道每一轮 agent 交互消耗了多少 context、用了多长时间、调用了哪些工具。

**原理**：用 UserPromptSubmit + Stop 两个 hook 构成一个测量"括号"，在每轮前后采集数据。来自 claude-howto 的 context-tracker 示例——用 session-id 为 key 的临时文件在两个 hook 之间共享状态。

### 实现

**UserPromptSubmit hook（"before"）**：
```bash
# 记录轮次开始状态
jq -n --arg ts "$(date +%s)" --arg ctx "$CONTEXT_USAGE" \
  '{start_ts: $ts, start_ctx: $ctx}' > "$TMPDIR/bracket-${SESSION_ID}.json"
```

**Stop hook（"after"）**：
```bash
# 读取开始状态，计算本轮增量
START=$(cat "$TMPDIR/bracket-${SESSION_ID}.json")
ELAPSED=$(( $(date +%s) - $(echo "$START" | jq -r '.start_ts') ))
CTX_DELTA=$(( CURRENT_CTX - $(echo "$START" | jq -r '.start_ctx') ))
echo "Turn: ${ELAPSED}s, context delta: ${CTX_DELTA} tokens"
```

### 用途

- **Context 预算**：当单轮 context 增量 > 阈值时告警（"这一轮用了 30K token，可能有大文件被读入"）
- **工具统计**：哪些工具被频繁使用/失败
- **进度追踪**：第 N 轮，已用 X% context
- **与 Ralph 叠加**：先 bracket 记录数据，再 ralph 决定是否 block

---

## Pattern 12: Component-Scoped Hooks

**问题**：全局 hooks 对所有 session 生效。某些验证逻辑只在特定类型的任务中需要。

**原理**：Claude Code 支持在 SKILL.md 或 agent 定义的 frontmatter 中声明 hooks，这些 hooks 只在该组件被激活时生效。Stop hook 在 subagent frontmatter 中会自动转换为 SubagentStop。

```yaml
---
name: security-fix
hooks:
  Stop:
    - type: agent
      agent: "验证安全修复：1) 检查修改的文件无新增漏洞 2) 确认敏感数据已清理 3) 验证权限配置正确。"
---
```

### 配合 `once: true`

`once: true` 让 hook 只在 session 中触发一次后自动停用。适合初始化任务：

```json
{
  "type": "command",
  "command": "inject-latest-handoff.sh",
  "once": true
}
```

用途：在 session 开始时注入最新的 handoff 文档（Pattern 2），只注入一次。

---

## Session-Scoped State Layout

所有状态统一在一个 session 目录下，清理只需 `rm -rf` 一个目录：

```
sessions/<session-id>/
  ralph.json              ← Pattern 1 状态
  cancel.json             ← Pattern 7 取消信号
  handoffs/               ← Pattern 2/8 handoff 文档
    stage-1-plan.md
    pre-compact.md
  tool-errors.json        ← Pattern 3 工具错误追踪
  denials.json            ← Pattern 9 权限否决追踪
  bracket.json            ← Pattern 11 当前轮次测量
  learnings.jsonl         ← Subagent 发现的持久化知识
```

### 为什么不用多个散落目录

OMC 使用 `sessions/<sessionId>/` 为根的隔离方案。好处：
1. **清理简单**：一个 session 的所有状态一个 `rm -rf` 搞定
2. **无跨 session 污染**：不可能读到其他 session 的状态
3. **Crash 恢复简单**：检查目录是否存在就知道有没有残留状态
4. **Staleness 检查**：目录的 mtime 反映最后活动时间

---

## Output

| 脚本 | 输入 | 输出 |
|------|------|------|
| `ralph-init.sh <session-id> [max-iter]` | Session ID, 可选最大迭代 | 创建 `sessions/<id>/ralph.json` |
| `ralph-stop-hook.sh` | stdin: Claude Code hook JSON | stdout: `{"continue":true}` 或 `{"decision":"block","reason":"..."}` |
| `ralph-cancel.sh <session-id> [reason]` | Session ID, 可选原因 | 创建 `sessions/<id>/cancel.json`（30s TTL） |

## 条件判断规则

当使用本 skill 时：
- 如果 agent 在 headless `-p` 模式 → 不要使用 Ralph（用 `--max-turns`），否则 Stop hook 不会触发
- 如果任务预计 < 5 分钟 → 不要使用 Ralph，否则 overhead 不值得
- 如果不确定是否需要持续执行 → 先不启用，观察 agent 是否提前停止再决定

## Related Skills

- **prompt-hardening**：P13（代码级强制）= hooks；P5（反推理阻断）可强化 Ralph block 消息；P9（漂移防护）配合 Hook pair bracket
- **improvement-evaluator**：对长评估任务使用 Ralph 保证 task suite 全部跑完
- **improvement-gate**：用 agent-type hook 添加语义验证层
